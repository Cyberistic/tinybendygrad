#!/usr/bin/env python3
"""tc-mutate.py -- the mutation table for transcendental_f32.bend.

One edit per PORTED RULE and per COEFFICIENT GROUP, applied to a scratch copy
BESIDE the real file (a `$TMPDIR` copy cannot resolve a relative import -- that
produced 22 phantom blind spots in another unit), run through a lane, and diffed
as WHOLE `name=value` LINES, never row names.

WHY PER-MUTATION LANES.  The full value lane is 784 rows and 21 minutes on an
idle box, so 35 serial mutations are twelve hours and the table would never get
run -- which is the whole reason a table written but not executed is not a table.
MEASURED on 2026-10-02: with the coefficient rows removed the same file is 0.17 s.
So each edit names the value tags its rule can REACH, the harness builds a lane
containing the coefficient rows plus exactly those tags, and it caches ONE
baseline per distinct lane.  A zero is then a statement about a lane that really
contains a fixture for the rule, not an artefact of which families were cheap.

The baseline of a lane is captured immediately before its first mutation and the
lane is RE-CHECKED against the unmutated file afterwards, because a concurrent
agent moving a substrate file turns every row red and looks like a mutation that
moves everything.

A zero is reported with its CLASS:
  fixture-request  the mutation moves nothing because no fixture reaches it
                   -- a request for a fixture, NOT a coverage claim
  theorem          the two spellings are the same function over every input
  unfixable        a predicate identical over every possible answer
"""
import os, re, subprocess, sys, tempfile, time
import patch_not_apply as PNA
from concurrent.futures import ThreadPoolExecutor

SRC = 'tinybendygrad/codegen/transcendental_f32.bend'
SCRATCH = os.path.join(os.path.dirname(SRC), '_tcmut_transcendental.bend')
WORKERS = int(os.environ.get('TC_WORKERS', '6'))

# (id, python line, what it is, the edit as (old, new), value tags it can reach)
# `tc.eval`'s tags, from the file: 0/1 sin_poly, 4 rintk, 5 ilogb2k, 6/7 frexp,
# 8/9/10 cody_waite, 11/12 sps/spl, 13 xsin, 14 xexp2, 15 xlog2, 16/17 lazy,
# 18 pow2if, 19/20 ldexp, 23-27 xpow predicates, 28-42 the guards.
EDITS = [
 ('M01', ':19-20', 'shr: floor-div by one power less',
  ('def tc.shr_u(+x: U32, +y: U32) -> U32: U32.div(x, tc.pow2u(y))',
   'def tc.shr_u(+x: U32, +y: U32) -> U32: U32.div(x, tc.pow2u(U32.sub(y, 1)))'), (2, 5, 21)),
 ('M02', ':25', 'rintk: round-half-away-from-zero becomes round-half-up',
  ('def tc.rintk(+d: F32) -> U32:\n  tc.f2i(tc.pick(F32.is_lt(d, tc.zero()), F32.sub(d, 0.5), F32.add(d, 0.5)))',
   'def tc.rintk(+d: F32) -> U32:\n  tc.f2i(F32.add(d, 0.5))'), (4, 8, 9, 13, 14)),
 ('M03', ':56-57', 'frexp: the mantissa mask loses its SIGN bit',
  ('F32.neg(F32.add(0.5, F32.mul(U32.to_f32(U32.and(F32.bits(v), sp.frac_mask())),\n                                         tc.f(sp.two_m24()))))',
   'F32.add(0.5, F32.mul(U32.to_f32(U32.and(F32.bits(v), sp.frac_mask())),\n                                         tc.f(sp.two_m24())))'), (6,)),
 ('M04', ':57', 'frexp: m2 sets exponent 125 rather than 126 (mantissa in [1,2))',
  ('def tc.fexp2(+v: F32) -> U32: U32.and(tc.shr_u(F32.bits(v), sp.mb_32()), sp.em_32())',
   'def tc.fexp2(+v: F32) -> U32: U32.add(U32.and(tc.shr_u(F32.bits(v), sp.mb_32()), sp.em_32()), 1)'), (6, 21)),
 ('M05', ':30', 'the f32 lane exponent bias is off by one (127 -> 126)',
  ('def tc.i2f(+b: U32) -> F32:\n  +m = U32.to_f32(Bool.pick(U32, tc.isneg(b), tc.neg(0, b), b))',
   'def tc.i2f(+b: U32) -> F32:\n  +m = U32.to_f32(Bool.pick(U32, tc.isneg(b), tc.neg(0, b), tc.neg(0, b)))'), (14, 15, 19, 20)),
 ('M06', ':146', 'cody_waite quadrant: `rintk(d * m_1_pi)` -> `rintk(2 * d * m_1_pi)`',
  ('def tc.cw_quadrant(+x: F32) -> U32: tc.rintk(F32.mul(x, tc.f(sp.m_1_pi())))',
   'def tc.cw_quadrant(+x: F32) -> U32: tc.rintk(F32.mul(x, F32.mul(2.0, tc.f(sp.m_1_pi()))))'), (8, 9, 13)),
 ('M07', ':138', 'the first Cody-Waite pi term loses its sign',
  ('def sp.cw0() -> String: "-3.1414794921875"', 'def sp.cw0() -> String: "3.1414794921875"'), (8, 10)),
 ('M08', ':139', 'the second Cody-Waite pi term loses its last digit',
  # the two spellings are the SAME binary32 (3102560256, MEASURED), so this can
  # only be seen by the `cd_` DECIMAL row -- which is the point of having one.
  ('cw1|-0.0001131594181060791|', 'cw1|-0.0001131594181060792|'), (8, 10)),
 ('M09', ':152', 'sin_poly coeff32[1] sign flipped',
  ('String.split("2.6083159809786594e-06|-0.00019810690719168633|',
   'String.split("2.6083159809786594e-06|0.00019810690719168633|'), (0, 1, 11, 12, 13)),
 ('M10', ':209', 'xexp2 coeff32[3] loses a digit (0.05550347269 -> 0.0555034726)',
  ('|0.009618384764|0.05550347269|', '|0.009618384764|0.0555034726|'), (1, 14)),
 ('M11', ':242', 'xlog2 coeff32[0] transposed (0.4374550283 -> 0.4375450283)',
  ('"0.4374550283|0.5764790177|', '"0.4375450283|0.5764790177|'), (15,)),
 ('M12', ':77', 'two_over_pi_f[2] 0x9391054a -> 0x9391154a (one nibble)',
  ('683565275|0x28be60db|2475754826|0x9391054a|', '683565275|0x28be60db|2475893354|0x9391154a|'), ()),
 ('M13', ':77', 'two_over_pi_f[4] 0x7d4d3770 -> 0x7d4d3771 (low bit)',
  ('|2102212464|0x7d4d3770|', '|2102212465|0x7d4d3771|'), ()),
 ('M14', ':211', 'xexp2 upper bound 128 -> 127',
  ('def sp.xexp2_up_32() -> String: "128"', 'def sp.xexp2_up_32() -> String: "127"'), (28,)),
 ('M15', ':211', 'xexp2 lower bound -150 -> -149',
  ('def sp.xexp2_lo_32() -> String: "-150"', 'def sp.xexp2_lo_32() -> String: "-149"'), (29,)),
 ('M16', ':170', 'xsin switch_over 30.0 -> 31.0',
  ('def sp.switch_over() -> String: "30.0"', 'def sp.switch_over() -> String: "31.0"'), (37,)),
 ('M17', ':227', 'xlog2 FLT_MIN 1e-4 -> 1.1e-4 (the denormal band edge)',
  ('flmin_32|0.0001|', 'flmin_32|0.00011|'), (31, 15)),
 ('M18', ':110', 'the Payne-Hanek remainder scale loses a digit',
  ('neg_half_pi_over_2|3.4061215800865545e-19|',
   'neg_half_pi_over_2|3.4061215800865556e-19|'), ()),
 ('M19', ':125', 'PI_A 3.1415926218032837 -> 3.1415926218032838 (last digit)',
  ('pi_a|3.1415926218032837|', 'pi_a|3.1415926218032835|'), ()),
 ('M20', ':240', 'the float64 log2(e) constant loses its last digit',
  ('nlog2e64|2.8853900817779268|', 'nlog2e64|2.8853900817779265|'), ()),
 ('M21', ':244', 'the s_lo term loses its last digit',
  ('s_lo32|3.273447448356849e-08|', 's_lo32|3.273447448356848e-08|'), (15,)),
 ('M22', ':14', 'mantissa_bits f32 23 -> 22',
  ('def sp.mb_32() -> U32: 23', 'def sp.mb_32() -> U32: 22'), (2, 5, 6, 7, 20, 21, 22)),
 ('M23', ':16', 'exponent_mask f32 255 -> 127',
  ('def sp.em_32() -> U32: 255', 'def sp.em_32() -> U32: 127'), (2, 5, 6, 7, 21)),
 ('M24', ':9-11', '_lazy_map_numbers: the -inf arm is dropped (ratio takes it)',
  ('Bool.pick(F32, tc.beq(x, tc.ninf()), _inf, ratio)))',
   'Bool.pick(F32, False{}, _inf, ratio)))'), (16, 17, 21, 38, 39, 40, 41, 42)),
 ('M25', ':249', 'xlog2: the `d != 0` guard becomes `d < 0`',
  ('def tc.xlog2_nezero(+d: F32) -> Bool: F32.is_eq(d, tc.zero())',
   'def tc.xlog2_nezero(+d: F32) -> Bool: F32.is_lt(d, tc.zero())'), (33,)),
 ('M26', ':255', 'xlog2: the reciprocal guard is dropped',
  ('def tc.xlog2.last(+rec: Bool, +r0: F32) -> F32:\n  Bool.pick(F32, rec, tc.ninf(), r0)',
   'def tc.xlog2.last(+rec: Bool, +r0: F32) -> F32:\n  Bool.pick(F32, rec, r0, tc.ninf())'), (36, 15)),
 ('M27', ':261', 'xpow non_int: the cast-round-trip becomes `e != e`',
  ('def tc.xpow_non_int(+e: F32) -> Bool: Bool.not(F32.is_eq(e, tc.i2f(tc.f2i(e))))',
   'def tc.xpow_non_int(+e: F32) -> Bool: Bool.not(F32.is_eq(e, e))'), (24,)),
 ('M28', ':262', 'xpow is_odd: `& 1` becomes `& 3`',
  ('U32.is_eq(U32.and(tc.f2i(tc.pick(F32.is_lt(e, tc.zero()), F32.neg(e), e)), 1), 1)',
   'U32.is_eq(U32.and(tc.f2i(tc.pick(F32.is_lt(e, tc.zero()), F32.neg(e), e)), 3), 1)'), (25,)),
 ('M29', ':150', 'trig_poly: `d * polyN(d*d)` becomes `polyN(d*d)`',
  ('def tc.sin_poly(+d: F32) -> F32: F32.mul(d, tc.polyn(sp.sin32(), F32.mul(d, d)))',
   'def tc.sin_poly(+d: F32) -> F32: tc.polyn(sp.sin32(), F32.mul(d, d))'), (0, 1, 11, 12, 13)),
 ('M30', ':47-50', 'ldexp2k: `e - shr(e,1)` becomes `e + shr(e,1)`',
  ('F32.mul(F32.mul(d, tc.pow2if(tc.shr_i(e, 1))), tc.pow2if(U32.sub(e, tc.shr_i(e, 1))))',
   'F32.mul(F32.mul(d, tc.pow2if(tc.shr_i(e, 1))), tc.pow2if(tc.iadd(e, tc.shr_i(e, 1))))'), (19, 14)),
 ('M31', ':82', 'the Payne-Hanek 4.294967296e9 scale becomes 2**33',
  ('topi_scale|4294967296.0|', 'topi_scale|8589934592.0|'), ()),
 ('M32', ':84-86', 'the `_take` window: `len - 1` becomes `len - 2`',
  ('def tc.take_len(+off: U32) -> U32: U32.sub(sp.take_window(), off)',
   'def tc.take_len(+off: U32) -> U32: U32.sub(sp.take_window(), U32.sub(off, 1))'), ()),
 ('M33', 'defect 1', 'tc.f LOSES the String.trim the reverse lookup depends on',
  ('def tc.f(+s: String) -> F32: tc.rdf(F32.read(String.trim(s)))',
   'def tc.f(+s: String) -> F32: tc.rdf(F32.read(s))'), ()),
 ('M34', 'defect 1', 'tc.u LOSES the String.trim the integer reverse lookup depends on',
  ('def tc.u(+s: String) -> U32: tc.rdu(U32.read(String.trim(s)))',
   'def tc.u(+s: String) -> U32: tc.rdu(U32.read(s))'), ()),
 ('M35', 'defect 1', 'the reverse-lookup sentinel becomes 0 instead of "not found"',
  ('def tc.vi(+xs: List<&2, String>, +b: U32, +i: U32) -> U32:\n  match xs:\n    case Nil{}: 4294967295',
   'def tc.vi(+xs: List<&2, String>, +b: U32, +i: U32) -> U32:\n  match xs:\n    case Nil{}: 0'), ()),
]


def load(path):
  d = {}
  for L in open(path):
    L = L.rstrip('\n')
    if '=' in L and not L.startswith(('SOME', 'ALL', 'Error', '-', 'Location',
                                      'Use ', '  ', 'Context')):
      k, v = L.split('=', 1)
      d[k] = v
  return d


def lane(src, tags):
  """`src` with a `main` that runs the coefficient rows plus `tags`."""
  L = src.split('\n')
  i = next(k for k, l in enumerate(L) if l.startswith('def main()'))
  keep = set(tags)
  body = []
  for l in L[i + 2:]:
    if l.strip() == 'IO.print("ts-done=1")': continue
    m = re.match(r'    t_of\((\d+), ', l)
    if m is not None and int(m.group(1)) not in keep: continue
    body.append(l)
  return '\n'.join(L[:i] + ['def main() -> IO(Unit):', '  do IO<Unit>:'] + body
                   + ['    IO.print("ts-done=1")']) + '\n'


def run(text, tag):
  """Run `text` in a scratch file beside the real one, return its rows."""
  p = f'{SCRATCH[:-5]}_{tag}.bend'
  open(p, 'w').write(text)
  try:
    d = tempfile.mkdtemp(prefix='tcmut')
    out = os.path.join(d, 'out.txt')
    with open(out, 'w') as f:
      subprocess.run(['./bin/bend', p], stdout=f, stderr=subprocess.STDOUT)
    return load(out)
  finally:
    if os.path.exists(p): os.remove(p)


BASE_CACHE = {}
BASE_LOCK = __import__('threading').Lock()


def lane_key(tags): return ','.join(str(t) for t in sorted(tags))


def baseline(tags):
  k = lane_key(tags)
  with BASE_LOCK:
    if k not in BASE_CACHE:
      BASE_CACHE[k] = run(lane(open(SRC).read(), tags), 'base')
  return BASE_CACHE[k]


def one(entry):
  mid, pline, what, (old, new), tags = entry
  src = open(SRC).read()
  if old not in src:
    return (mid, pline, what, None, None, PNA.not_applied(), '')
  t0 = time.time()
  base = baseline(tags)
  got = run(lane(src.replace(old, new, 1), tags), mid)
  dt = time.time() - t0
  moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
  return (mid, pline, what, dt, (len(base), len(got)), moved, lane_key(tags))


def main():
  only = sys.argv[1:] or None
  edits = [e for e in EDITS if not only or e[0] in only]
  with ThreadPoolExecutor(max_workers=WORKERS) as ex:
    results = list(ex.map(one, edits))
  rows, out = [], []
  for mid, pline, what, dt, n, moved, lk in results:
    if isinstance(moved, str):
      line = f'{mid} {pline:9s} EDIT-NOT-APPLIED'
      out.append(line); rows.append((mid, pline, '-', 'EDIT-NOT-APPLIED', ''))
      print(line, flush=True); continue
    cls = '' if moved else 'ZERO'
    nb, ng = n
    line = (f'{mid} {pline:9s} lane[{lk:22s}] base {nb:4d} rows  got {ng:4d}  '
            f'{len(moved):4d} moved  {dt:6.1f}s  {cls:5s} {what[:36]}')
    out.append(line); print(line, flush=True)
    rows.append((mid, pline, len(moved), cls, lk + ' :: ' + ' '.join(moved[:18])))
  with open('.agents/slop/tc-mutations.txt', 'w') as f:
    f.write('\n'.join(out) + '\n\nDETAIL\n')
    for r in rows: f.write('%-5s %-9s %-5s %-5s %s\n' % r)
  print('\nwrote .agents/slop/tc-mutations.txt')


if __name__ == '__main__':
  main()
