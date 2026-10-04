#!/usr/bin/env python3
"""Emit the FIXTURE BLOCK of tinybendygrad/renderer/ptx.bend.

TWO INDEPENDENT THINGS HAPPEN HERE AND THEY MUST NOT BE CONFUSED.

(1) THE STEP LIST. Each fixture's `Wk` list is written out BY HAND below, as a
    transcription of the graph recipe in `.agents/slop/ptx-s3-oracle.py`. A
    transcription error is harmless: it changes the walk's INPUT, so the diff
    against CPython fires. What this file must never do is DERIVE a `want`
    string from the port.

(2) EVERY `want` IS READ OUT OF THE ORACLE'S ROWS -- never typed. That includes
    the two per-fixture literals `cnt` and `entry`, which are the rows a
    per-line diff cannot make: a LOST `.reg` line is invisible in a set of line
    rows, and a renamed entry point is invisible in a set of register names.

Run from the repo root:
    python3 .agents/slop/ptx-s3-gen.py
It rewrites the region between the BEGIN/END markers in ptx.bend.
"""
import sys
sys.path.insert(0, '.')
sys.argv = ['gen']
G = {'__name__': 'oracle'}
exec(open('.agents/slop/ptx-s3-oracle.py').read(), G)

# ---------------------------------------------------------------------------
# the two literals, straight out of the oracle's own rows
# ---------------------------------------------------------------------------
def bq(x):
  """A Bend string literal, double-quoted, with the escapes Bend needs."""
  return '"' + x.replace('\\', '\\\\').replace('"', '\\"') + '"'

def split_rows():
  """(fixture, field) -> want. The split is on the FIRST dot after a fixture
  name, because `reg.count` and `r[0] BUFFER` both contain dots."""
  out = {}
  for line in G['rows']().splitlines():
    k = line.split(' = [', 1)[0]
    want = line.split('   py=[', 1)[1].rstrip(']')
    if k.startswith('to_function_name '):
      out[('fn', k[len('to_function_name '):])] = want
    else:
      for n in FIX:
        if k.startswith(n + '.'):
          out[(n, k[len(n):])] = want
          break
  return out

# ---------------------------------------------------------------------------
# the hand-written step lists
# ---------------------------------------------------------------------------
# (op, dt, addr, nmn, nm, refs, idx, idx_ok)
G_, L_, R_, A_ = 'S.AGlobal{}', 'S.ALocal{}', 'S.AReg{}', 'S.Aalu{}'
def B(dt="f32", addr=G_, nmn=1): return ('OpsBUFFER', dt, addr, nmn, '', [], 0, True)
def PR(dt="f32", addr=G_):        return ('OpsPARAM', dt, addr, 1, '', [], 0, True)
def N():                         return ('OpsCONST', 'f32', A_, 1, '', [], 0, True)
def CA(dt="f32"):                 return ('OpsCAST', dt, A_, 1, '', [], 0, True)
def BI(dt):                      return ('OpsBITCAST', dt, A_, 1, '', [], 0, True)
def AL(op, dt="f32"):            return (op, dt, A_, 1, '', [], 0, True)
def SP(nm):                      return ('OpsSPECIAL', 'f32', A_, 1, nm, [], 0, True)
def SK(op):                      return (op, 'f32', A_, 1, '', [], 0, True)
def AF(i):                       return ('OpsAFTER', 'f32', A_, 1, '', [i], 0, True)
def IXG(i):                      return ('OpsINDEX', 'f32', G_, 1, '', [i], 0, True)
def IXR(i, idx, ok):             return ('OpsINDEX', 'f32', R_, 1, '', [i], idx, ok)
def SHG(i):                      return ('OpsSHRINK', 'f32', G_, 1, '', [i, 0], 0, True)
def LDG(nmn):                    return ('OpsLOAD', 'f32', G_, nmn, '', [], 0, True)
def LDR(i, nmn):                 return ('OpsLOAD', 'f32', R_, nmn, '', [i], 0, True)
def ST(refs):                    return ('OpsSTACK', 'f32', A_, 1, '', refs, 0, True)
def EN():                        return ('OpsEND', 'i32', A_, 1, '', [], 0, True)
def RG(dt):                      return ('OpsRANGE', dt, A_, 1, '', [], 0, True)
def SN(nm='test'):               return ('OpsSINK', 'f32', A_, 1, nm, [], 0, True)

FIX = {
 # the prefix table and the counter over five ALU/CAST steps
 'f1_alu':       [B(), N(), CA(), AL('OpsADD'), N(), CA(), AL('OpsMUL'), N(), CA(), AL('OpsADD'), SN()],
 # ONE prefix, five allocations: `cast_f32_<5>` and `alu_f32_<5>`
 'f2_counter':   [B()] + [x for _ in range(5) for x in (N(), CA(), AL('OpsADD'))] + [SN()],
 # `cast` over five DTYPES: five keys, so five `.reg` lines
 'f3_cast':      [B('i32'), CA('i32'), B('u32'), CA('u32'), B('i64'), CA('i64'),
                  B('f16'), CA('f16'), B('f32'), CA('f32'), SN()],
 # END is the only op whose TABLE dtype is the literal "pred"
 'f4_pred':      [B('i32'), N(), CA('i32'), AL('OpsADD', 'i32'), EN(), SN()],
 # a REG buffer is a LIST of `reg` registers, one per element
 'f5_regbuf':    [B('f32', R_, 4), SN()],
 # ... and ONE element is still a LIST
 'f6_regbuf1':   [B('f32', R_, 1), SN()],
 # INDEX off a REG buffer SUBSCRIPTS it; LOAD off one COPIES it
 'f7_reuse':     [B('f16', R_, 4), N(), CA('i32'), IXR(0, 2, True), N(), SP('g0'), LDR(0, 4), SN()],
 # the same INDEX with a non-CONST subscript is the REFUSAL
 'f8_refuse':    [B('f16', R_, 4), N(), CA('i32'), N(), CA('i32'), AL('OpsADD', 'i32'), IXR(0, 0, False), SN()],
 # SPECIAL's register is "%"+arg verbatim: no prefix, no counter
 'f9_special':   [B(), N(), SP('l1'), AL('OpsADD'), SN()],
 # three vector LOADs: one `val` series of 24, and three `.reg .u32` lines
 # emitted in REVERSE toposort order
 'f10_loads':    [B('f32', G_, 8), N(), SP('g0'), LDG(8), SP('g1'), LDG(8),
                  B('f32', G_, 8), SP('g2'), LDG(8), SN()],
 # STACK collects its srcs' registers as a LIST of two SCALARS
 'f11_stack':    [B(), N(), CA(), AL('OpsADD'), ST([0, 3]), SN()],
 # AFTER aliases src0 and spends no counter
 'f12_after':    [B(), AF(0), SN()],
 # PARAM takes `dat`, and `u64` only when GLOBAL
 'f13_param':    [PR('f32', G_), PR('f32', L_), SN()],
 # NOOP, GROUP and CONST never reach the counter, and their indices are GONE
 'f14_skips':    [SK('OpsNOOP'), SK('OpsGROUP'), N(), B(), CA(), AL('OpsADD'), SN()],
 # INDEX and SHRINK take `bidx_u64`
 'f15_bidx':     [B(), N(), SP('g0'), IXG(0), SP('g1'), SHG(0), SN()],
 # BITCAST shares the `cast` key with CAST
 'f16_bitcast':  [B('i32'), CA('f32'), BI('f32'), SN()],
 # every hard-coded-dtype prefix in ONE walk, and the counter order
 'f17_u64':      [B(), N(), SP('g0'), IXG(0), SP('g1'), SHG(0), B('i32'), N(), CA('i32'),
                  AL('OpsADD', 'i32'), EN(), SN()],
 # a SINK with no arg leaves the entry point at "test"
 'f18_name':     [B(), N(), CA(), AL('OpsADD'), SN()],
 # every allocating prefix, and `.reg` in INSERTION order
 'f19_mixed':    [B(), CA('i32'), N(), SP('g0'), IXG(0), N(), CA('f32'), AL('OpsADD'),
                  PR('f16', G_), SP('g1'), LDG(4), SN()],
 'f20_idx_pred': [B('i32'), N(), CA('i32'), AL('OpsADD', 'i32'), EN(), SN()],
 # a SINK whose arg renames the entry point, through `to_function_name`
 'f21_name':     [B(), N(), CA(), AL('OpsADD'), SN('my kernel')],
 'f22_name2':    [B(), N(), CA(), AL('OpsADD'), SN('MyKernel')],
 # a SCALAR LOAD: `max_numel == 1` answers a bare register and NOT a one-element
 # list, which is the OPPOSITE of f6's REG buffer. This fixture is the only
 # thing that separates ptx.py:208's `if max_numel > 1` from ptx.py:198's
 # comprehension -- M12 moved nothing until it existed.
 'f23_load1':    [B('f32', G_, 1), N(), SP('g0'), LDG(1), SN()],
 # RANGE: `ridx` over a real dtype, and the VOID clause (ptx.py:219) that clears
 # the prefix so a loop header has a label and no register. M13 and M14 both
 # moved nothing until these two existed.
 'f24_range':    [N(), CA('i32'), RG('i32'), B(), N(), CA(), AL('OpsADD'), SN()],
 'f25_rangevoid':[SK('OpsNOOP'), RG('void'), B(), N(), CA(), AL('OpsADD'), SN()],
}

DT = {'f32': 'S.single()', 'f16': 'S.half()', 'i32': 'S.int32()', 'u32': 'S.uint32()',
      'i64': 'S.int64()', 'void': 'S.void()'}

def step(s):
  op, dt, addr, nmn, nm, refs, idx, ok = s
  refs = 'Nil{}' if not refs else '[' + ', '.join(str(r) for r in refs) + ']'
  return 'Wk{O.%s{}, %s, %s, %d, %s, %s, %d, %s{}}' % (op, DT[dt], addr, nmn, bq(nm), refs, idx,
                                                        'True' if ok else 'False')

def fn_block(rows):
  # THE THREE that close the CONSTANTS SWEEP's blind list: `~` is one above
  # `fn_kp`'s 122, `/` is one below its 48, and `:` is one above its 95. Each is
  # a character the sweep's `+1` on a bound would flip, and each is INSIDE no
  # range, so `a-b` and `x$y.z` could never have found them.
  ins = ["test", "my kernel", "MyKernel", "a-b", "x$y.z", "  lead", "trail  ", "a b c",
         "a~b", "a/b", "a:b", "a0b", "a_b"]
  out = 'def r_fns() -> String: String.concat(['
  for t in ins:
    q = "'" + t + "'"
    out += 'T.r(String.concat(["to_function_name ", %s]), fn_name(%s), %s), ' % (
      bq(q), bq(t), bq(rows[('fn', q)]))
  return out[:-2] + '])'

def fix_def(nm, steps, rows):
  """The step list AND the whole wants list, in the ORACLE'S OWN ROW ORDER.

  The `Wt` names are the row suffixes (`r[0] BUFFER`, `reg[2]`, `reg.count`,
  `entry`) so the Bend side rebuilds the same order from its own walk; a
  disagreement about how many rows there are is then a diff, not a silent
  truncation."""
  body = ',\n   '.join(step(s) for s in steps)
  keys = [k for (n, k) in rows if n == nm]
  ws = ',\n   '.join('Wt{%s, %s}' % (bq(k), bq(rows[(nm, k)])) for k in keys)
  return ('def %s_ss() -> List<&2, Wk>:\n   [%s]\n\ndef %s() -> String: r_fix("%s", %s_ss(),\n   [%s])'
          % (nm, body, nm, nm, nm, ws))

rows = split_rows()
BLOCK = '\n'.join([fn_block(rows), ''] + [fix_def(n, FIX[n], rows) for n in FIX]) + '\n'

P_ = 'tinybendygrad/renderer/ptx.bend'
src = open(P_).read()
B, E = '# ==== BEGIN GENERATED FIXTURES', '# ==== END GENERATED FIXTURES'
assert E in src, 'end marker missing'
if B in src:
  src = src[:src.index(B)] + B + '\n' + BLOCK + E + src[src.index(E) + len(E):]
else:
  src = src.rstrip('\n') + '\n\n' + B + '\n' + BLOCK + E + '\n'
open(P_, 'w').write(src)
print('fixtures written:', len(FIX), '+ r_fns')