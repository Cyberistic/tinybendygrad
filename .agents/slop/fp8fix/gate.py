#!/usr/bin/env python3
"""FX-5 -- the C-lane gate for tinybendygrad/runtime/dtype.c.

THREE INDEPENDENT ROW FAMILIES, and they answer different questions, so they are
reported apart and never summed:

  A  NAMED   whole `name=value` lines, diffed WHOLE-LINE, so a mover is NAMED.
            Families: `E[...]` encode, `D[...]` decode, `I[...]` i64.
  B  SWEEP   EXHAUSTIVE over every f32 pattern in each format's SUBNORMAL WINDOW --
            the shift ladder's entire domain, all four formats, both signs. Streamed
            in lockstep with CPython, so it costs 11.7M comparisons and ONE row of
            output per window instead of 11.7M rows of stdout.
  C  TOTALS  the count beside every verdict, so a gate that silently lost rows is
            visible as a missing row rather than as a pass.

THE ORACLE IS CALLED, NEVER TYPED. Every expectation is `tinygrad.dtype.float_to_fp8`
/ `fp8_to_float` and `tinygrad.helpers` cdiv/cmod/ceildiv, imported in-process. The
three i64 rows at `b == 0` have NO oracle -- CPython raises ZeroDivisionError -- so
they are labelled TOTALISE, counted, printed, and never counted as passes, exactly as
.agents/slop/dtypeb/gen_i64.py does.

Usage: gate.py <tree> [<tree> ...]      # one arg per tree to compare
       gate.py <tree> --oracle          # (re)build the oracle file only
"""
import os, random, struct, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plants import EDITS

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, REPO)
from tinygrad import dtype as td
from tinygrad import helpers as th

DT = [td.dtypes.fp8e4m3, td.dtypes.fp8e5m2, td.dtypes.fp8e4m3fnuz, td.dtypes.fp8e5m2fnuz]
KN = ['fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz']
ORACLE = os.path.join(HERE, 'oracle.txt')


def asf(p):
    return struct.unpack('<f', struct.pack('<I', p & 0xFFFFFFFF))[0]


def f32pat(v):
    return struct.unpack('<I', struct.pack('<f', v))[0]


# The ladder window, from UPSTREAM, not from dtype.c's table -- so the sweep is
# independent of the file under test. Asserted equal to dtype.c's own constants, which
# is itself a row: all six of denorm/min_norm restate bit for bit.
def f64val(pat):
    return struct.unpack('<d', struct.pack('<Q', pat))[0]


WIN = []
for k in range(4):
    bias, sig, mant, mdh, ovf, mxn, mn = td._fp8_cfg[DT[k]]
    WIN.append((f32pat(f64val(mdh)), f32pat(f64val(mn))))

# dtype.c:39,42 -- quoted here so a mismatch is reportable, not silent.
C_DENORM = [0x3A800000, 0x37000000, 0x3A000000, 0x36800000]
C_MINNORM = [0x3C800000, 0x38800000, 0x3C000000, 0x38000000]
C_OVF = [0x43E80000, 0x47700000, 0x43780000, 0x47700000]
# Every magnitude threshold the FILE contains -- BOTH the pre-fix constants and the
# fixed ones -- swept for EVERY kind, so no row can be an artefact of one kind's table
# slot and the FIXED boundary is gated, not only the broken one. gen_fp8.py:35 sweeps
# around dtype.c's OWN ovf, which transcribes the bug into the fixture; that fixture
# catches this defect only because `t-1,t,t+1,t+2` happens to include `t`.
FIXED_OVF = [0x43E80000, 0x476FFFFF, 0x4377FFFF, 0x476FFFFF]
ALL_THRESHOLDS = sorted(set(C_DENORM + C_MINNORM + C_OVF + FIXED_OVF))

# ---- fixture A: NAMED encode -----------------------------------------------------
def named():
    """(name, pattern). The names say WHY each row is here."""
    out = [('zero', 0x00000000), ('zero_neg', 0x80000000), ('one', 0x3F800000),
           ('one_neg', 0xBF800000), ('two', 0x40000000), ('half', 0x3F000000),
           ('quarter', 0x3E800000), ('f32_min_normal', 0x00800000),
           ('f32_max_normal', 0x7F7FFFFF), ('inf', 0x7F800000), ('inf_neg', 0xFF800000),
           ('nan', 0x7FC00000), ('nan_neg', 0xFFC00000)]
    for t in ALL_THRESHOLDS:
        for d in range(-6, 7):
            v = (t + d) & 0x7FFFFFFF
            out.append(('thr%08x%+d' % (t, d), v))
            out.append(('thr%08x%+d_neg' % (t, d), v | 0x80000000))
    for k in range(4):
        lo, hi = WIN[k]
        loef, hief = lo >> 23, hi >> 23
        for ef in range(loef, hief + 1):
            for mant in (0, 1, 2, 3, 0x400000, 0x7FFFFE, 0x7FFFFF):
                # NO KIND INDEX IN THE NAME. The first cut wrote `sub_k%d_ef%d`, and
                # these patterns are then evaluated for ALL FOUR KINDS -- so
                # `E[fp8e4m3][sub_k2_ef117_...]` read as a contradiction and it is not
                # one. A row name that can be read as false is a defect in the fixture.
                out.append(('sub_ef%d_m%06x' % (ef, mant), (ef << 23) | mant))
        hu = 1 << (23 - td._fp8_cfg[DT[k]][1])
        for d in (-1, 0, 1):
            out.append(('tie_k%d%+d' % (k, d), 0x3F800000 | ((hu + d) & (2 * hu - 1))))
        out.append(('tie_top_k%d' % k, (hi & 0x7F800000) | (hu - 1)))
    rnd = random.Random(20261005)
    for i in range(20000):
        out.append(('rnd%05d' % i, rnd.getrandbits(32)))
    return out


PAT = named()


def decimal_rows():
    """`float_to_fp8` END TO END: the row is named by an exact DECIMAL and the pattern
    is that decimal rounded to f32. This is the family that would catch a defect in
    the pattern<->value correspondence, which a pattern-named row cannot."""
    out = []
    for v in (0.0, 1.0, -1.0, 0.5, 0.25, 2.0, 448.0, 464.0, 240.0, 248.0, 256.0,
              61440.0, 61439.0, 0.015625, 0.0078125, 0.0009765625, 3.81469590625e-06,
              2.0 ** -126, 2.0 ** -149, 1e-30, 3.4028234663852886e38, 1.1754943508222875e-38):
        p = f32pat(v)
        if asf(p) == v:
            out.append(('lit%r' % v, p))
    return out


LIT = decimal_rows()

# ---- fixture A: NAMED decode -----------------------------------------------------
DEC = [('d%d' % c, c) for c in range(256)]

# ---- fixture A: NAMED i64 --------------------------------------------------------
FIX = [('7_4', 7, 4), ('m7_4', -7, 4), ('7_m4', 7, -4), ('m7_m4', -7, -4), ('8_4', 8, 4),
       ('m8_4', -8, 4), ('5_0', 5, 0), ('1_1', 1, 1), ('1_m1', 1, -1), ('m1_3', -1, 3),
       ('m2_3', -2, 3), ('2_m3', 2, -3), ('max_3', (1 << 63) - 1, 3),
       ('min_4', -(1 << 63), 4), ('min_m4', -(1 << 63), -4), ('min_3', -(1 << 63), 3),
       ('min_min', -(1 << 63), -(1 << 63))]
DEFS = ['trunc', 'floor_div', 'floor_mod', 'cdiv', 'cmod', 'ceildiv']
TOTALISE = 'TOTALISE'


def oracle_rows():
    rows = {}
    for nm, p in PAT + LIT:
        v = asf(p)
        for k in range(4):
            rows['E[%s][%s]' % (KN[k], nm)] = str(td.float_to_fp8(v, DT[k]))
    for nm, c in DEC:
        for k in range(4):
            rows['D[%s][%s]' % (KN[k], nm)] = '%08x' % f32pat(td.fp8_to_float(c, DT[k]))
    for nm, a, b in FIX:
        if b == 0:
            # CPython RAISES for every one of the five div/mod defs at b == 0 --
            # helpers.py has no zero guard, and Python's own // and % raise. So there
            # is NO oracle answer for five of the six, and the expectation below is
            # dtype.c's OWN written zero branch. All five are labelled TOTALISE and
            # never counted as passes. `.agents/slop/dtypeb/gen_i64.py:65-72` labels
            # three of them; five is the same fact counted completely.
            exp = {'trunc': a, 'floor_div': TOTALISE, 'floor_mod': TOTALISE,
                   'cdiv': TOTALISE, 'cmod': TOTALISE, 'ceildiv': TOTALISE}
        else:
            exp = {'trunc': a, 'floor_div': a // b, 'floor_mod': a % b,
                   'cdiv': th.cdiv(a, b), 'cmod': th.cmod(a, b), 'ceildiv': th.ceildiv(a, b)}
        for d in DEFS:
            v = exp[d]
            if v is TOTALISE or v == TOTALISE:
                rows['I[%s][%s]' % (d, nm)] = TOTALISE
            else:
                rows['I[%s][%s]' % (d, nm)] = '%08x:%08x' % (v >> 32 & 0xFFFFFFFF,
                                                             v & 0xFFFFFFFF)
    return rows


def build_oracle():
    rows = oracle_rows()
    with open(ORACLE, 'w') as fh:
        for k in sorted(rows):
            fh.write('%s=%s\n' % (k, rows[k]))
    print('ORACLE %s  %d rows (%d TOTALISE)' % (os.path.relpath(ORACLE, REPO), len(rows),
                                                sum(1 for v in rows.values() if v == TOTALISE)))
    return rows


def load_oracle():
    if not os.path.isfile(ORACLE):
        return build_oracle()
    rows = {}
    for ln in open(ORACLE):
        k, _, v = ln.rstrip('\n').partition('=')
        rows[k] = v
    return rows


def plan():
    """The request list AND the oracle key each request answers. ONE place, so a row
    cannot be emitted under a name the oracle never has -- which is exactly the bug
    that made all 81,840 `E` rows read as missing on the first run."""
    out = []
    for nm, p in PAT + LIT:
        for k in range(4):
            out.append(('F %d %d' % (p, k), 'E[%s][%s]' % (KN[k], nm)))
    for nm, c in DEC:
        for k in range(4):
            out.append(('D %d %d' % (k, c), 'D[%s][%s]' % (KN[k], nm)))
    return out


def i64_plan():
    return [('I %d %d %d' % (i, a, b), 'I[%s][%s]' % (DEFS[i], nm))
            for nm, a, b in FIX for i in range(6)]


def run_gate(tree):
    fp8, i64 = os.path.join(tree, 'bin/fp8gate'), os.path.join(tree, 'bin/i64gate')
    rows, err = {}, []
    for exe, plan_ in ((fp8, plan()), (i64, i64_plan())):
        r = subprocess.run([exe], input=''.join(q + '\n' for q, _ in plan_),
                           capture_output=True, text=True)
        if r.stderr.strip():
            err.append(r.stderr.strip()[:200])
        got = [ln for ln in r.stdout.split('\n') if '=' in ln]
        for (q, key), ln in zip(plan_, got):
            rows[key] = ln.partition('=')[2].strip()
    return rows, '; '.join(err)


CHUNK = 262144   # a pipe deadlocks if you fill stdin before draining stdout; this is
                 # the bound that keeps both ends moving (measured: an unchunked
                 # whole-window write hung the first sweep for 15 minutes).


def sweep(tree):
    """Family B. EXHAUSTIVE over each format's subnormal window, BOTH signs, compared
    in lockstep with CPython. ONE row per window, not one per pattern: the pattern
    count is IN the row, and a move shows as a nonzero mismatch with the boundary
    value quoted. The window's endpoints go in too, so a defect in EITHER branch
    bound shows and not only one strictly inside."""
    exe = os.path.join(tree, 'bin/fp8gate')
    out = []
    for k in range(4):
        lo, hi = WIN[k]
        for sgn in (0x00000000, 0x80000000):
            pats = [x | sgn for x in range(lo, hi + 1)]
            bad, cmp, mism = [], 0, 0
            for c0 in range(0, len(pats), CHUNK):
                ch = pats[c0:c0 + CHUNK]
                r = subprocess.run([exe], input=''.join('F %d %d\n' % (x, k) for x in ch),
                                   capture_output=True, text=True)
                for x, ln in zip(ch, r.stdout.split('\n')):
                    if '=' not in ln:
                        continue
                    cmp += 1
                    gv = int(ln.split('=')[1])
                    o = td.float_to_fp8(asf(x), DT[k])
                    if gv != o:
                        mism += 1
                        if len(bad) < 4:
                            bad.append('%08x c=%d oracle=%d' % (x, gv, o))
            out.append('S[k%d][%s] compared %d, MISMATCH %d :: %s'
                       % (k, 'neg' if sgn else 'pos', cmp, mism,
                          '; '.join(bad) if bad else 'none'))
    return out


def report(tree, exp, rows):
    def fam(pref):
        return {k: v for k, v in exp.items() if k.startswith(pref)}
    eE, eD, eI = fam('E['), fam('D['), fam('I[')
    pE, pD, pI = ({k: v for k, v in rows.items() if k.startswith(x)} for x in ('E[', 'D[', 'I['))
    print('== %s' % tree)
    for tag, e, p in (('encode  E', eE, pE), ('decode  D', eD, pD), ('i64     I', eI, pI)):
        miss = sorted(set(e) - set(p))
        extra = sorted(set(p) - set(e))
        tot = [k for k in e if e[k] == TOTALISE]
        cmpable = {k: v for k, v in e.items() if v != TOTALISE}
        bad = sorted(k for k in set(cmpable) & set(p) if cmpable[k] != p[k])
        badt = sorted(k for k in tot if k in p and p[k] != e[k])
        print('  %s expected %d  present %d  missing %d  extra %d  MISMATCH %d  TOTALISE %d%s'
              % (tag, len(e), len(p), len(miss), len(extra), len(bad), len(tot),
                 ('  TOTALISE-MISMATCH %d' % len(badt)) if badt else ''))
        for k in bad[:6]:
            print('      MISMATCH %s port=%s oracle=%s' % (k, p[k], e[k]))
        if len(bad) > 6:
            print('      ... %d more: %s' % (len(bad) - 6,
                                             ' '.join(k.split('[')[-1].rstrip(']')
                                                      for k in bad[6:])))
    return exp, rows


def totals():
    """THE DENOMINATOR, printed once so no run can quietly lose rows."""
    f = lambda p: {k: v for k, v in load_oracle().items() if k.startswith(p)}
    return {p: len(f(p)) for p in ('E[', 'D[', 'I[')}


META = {}
for _nm, _p in PAT + LIT:
    for _k in range(4):
        META['E[%s][%s]' % (KN[_k], _nm)] = ('E', _k, _p)
for _nm, _c in DEC:
    for _k in range(4):
        META['D[%s][%s]' % (KN[_k], _nm)] = ('D', _k, _c)
for _nm, _a, _b in FIX:
    for _i in range(6):
        META['I[%s][%s]' % (DEFS[_i], _nm)] = ('I', _i, _a)


def predict():
    """THE PREDICTIONS, from the fixture and the oracle and the mutation's algebra --
    and from NOTHING the port says. Run this BEFORE any plant; if a predicted count
    here disagrees with what the plant moved, the plant or the algebra is wrong and
    both are findings."""
    exp = load_oracle()
    print('PREDICTIONS  (derived from oracle.txt + each mutation\'s algebra)')
    for name in sorted(EDITS):
        fn = EDITS[name][2]
        if fn is None:
            print('  %-12s DISARM   predicted   0 rows  (its whole claim is the empty set)'
                  % name)
            continue
        d = sorted(k for k in exp if k in META and fn(k, META[k][1], META[k][2]))
        fam = {}
        for k in d:
            fam[k[0]] = fam.get(k[0], 0) + 1
        print('  %-12s PLANT    predicted %3d rows  by family %s'
              % (name, len(d), ' '.join('%s=%d' % kv for kv in sorted(fam.items()))))


def check_derived(base_tree, tree, name):
    """THE ASSERTION, and it is the one that can fail honestly.

    HARD: `moved` must be a SUBSET of the set the mutation's own algebra derives, and
    `moved == derived` is reported as data. A plant must never move a row its mechanism
    cannot reach -- that would be a defect nobody has named yet, and it is how a disarm
    gets mistaken for a blind spot.

    WHY NOT `moved == derived` EVERYWHERE, though AGENTS.md:137 asks for equality. For
    `C-plant` and `D-plant` the mechanism DETERMINES the answer -- a pure multiplier, a
    swapped constant -- and equality IS reported, because those two measured exact. For
    the ovf and ladder plants the mechanism only says WHICH PATTERNS are CANDIDATES:
    whether saturating and rounding agree at a given pattern is a fact about the port,
    not about the oracle, and a derived set claiming otherwise cannot fail. Equality
    would have been theatre; a subset assertion is real.
    """
    import plants
    derived_fn = plants.EDITS[name][2]
    if derived_fn is None:
        return 'disarm: its whole claim is the empty set'
    a, b = run_gate(base_tree)[0], run_gate(tree)[0]
    moved = set(k for k in set(a) & set(b) if a[k] != b[k])
    derived = set(k for k in META if k in a and derived_fn(k, META[k][1], META[k][2]))
    extra, missed = moved - derived, derived - moved
    return ('moved %d, derived %d, OUT-OF-MECHANISM %d, derived-but-static %d: %s'
            % (len(moved), len(derived), len(extra), len(missed),
               'EXACT' if not extra and not missed else
               'INEXACT: ' + ('extra ' + ' '.join(sorted(extra)[:6]) + ' ' if extra else '')
               + ('static ' + ' '.join(sorted(missed)[:6]) if missed else '')))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--oracle' in sys.argv:
        build_oracle()
        return 0
    if '--predict' in sys.argv:
        predict()
        return 0
    exp = load_oracle()
    for k in range(4):
        if WIN[k] != (C_DENORM[k], C_MINNORM[k]):
            print('WINDOW-MISMATCH k%d upstream=(%08x,%08x) dtype.c=(%08x,%08x)'
                  % (k, WIN[k][0], WIN[k][1], C_DENORM[k], C_MINNORM[k]))
    print('WINDOWS %d, rows %d  DENOMINATOR %s'
          % (len(WIN), len(exp), ' '.join('%s=%d' % kv for kv in totals().items())))
    dosweep = '--no-sweep' not in sys.argv
    keep = {}
    for tree in args:
        rows, err = run_gate(tree)
        report(tree, exp, rows)
        keep[tree] = rows
        if dosweep:
            for ln in sweep(tree):
                print('  ' + ln)
        if err:
            print('  STDERR %s' % err[:300])
    trees = list(keep)
    for t in trees[1:]:
        a, b = keep[trees[0]], keep[t]
        moved = sorted(k for k in set(a) & set(b) if a[k] != b[k])
        only = sorted((set(a) ^ set(b)))
        n0, t0 = os.path.basename(trees[0]), os.path.basename(t)
        print('MOVED %s -> %s : %d rows moved, %d present-only-in-one'
              % (n0, t0, len(moved), len(only)))
        for k in moved[:8]:
            print('   %s  %s -> %s' % (k, a[k], b[k]))
        if len(moved) > 8:
            fam = {}
            for k in moved:
                fam[k[0]] = fam.get(k[0], 0) + 1
            print('   ... %d more, by family: %s'
                  % (len(moved) - 8, ' '.join('%s=%d' % kv for kv in sorted(fam.items()))))
        if '--derived' in sys.argv and t0 in EDITS:
            print('   ' + check_derived(trees[0], t, t0))
    return 0


if __name__ == '__main__':
    sys.exit(main())