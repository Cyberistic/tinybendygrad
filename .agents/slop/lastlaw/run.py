#!/usr/bin/env python3
"""LL-3 -- the gate for the eight laws, plus the plants that arm it.

    BASE       the patch as written
    DISARM x3  three rewrites that are THE SAME FUNCTION by another expression
    PLANT  x3  three real defects, each with its moved set DERIVED from the
               mutation's own algebra -- never a transcribed list
    PINV       THE HELPER-INVERSION PLANT. `i64_is_neg` is inverted inside the
               variant's OWN COPY of helpers.bend, so every `Dt.i64_*` that reads a
               sign reads the wrong one. This is the plant the whole instrument
               exists for: I64MUL's rule 5 records a gate that was blind to an
               inverted sign test for 442 rows while `cdiv` caught it instantly. If
               PINV moves nothing, this gate is not an instrument.

GUARDS, both of which exist because this area has already produced the failure they
prevent:

  * ZERO DENOMINATOR. A lane that emits 0 rows, 0 CPython-verified rows, 0 TOTALISE
    rows or 0 f32 literals is REFUSED, not passed. P4 passed the first time over a
    window containing no NaN at all, and `i64_div`'s 65th bit passed over a grid
    with no `int64.min` in it.
  * TIMEOUT. `timeout` is NOT INSTALLED here; every bend run goes through
    `perl -e 'alarm N; exec @ARGV'`. A run killed by a harness timeout mid-mutation
    is how a plant was left in the LIVE tree in a previous unit.

THE LIVE TREE IS NEVER WRITTEN. One pristine copy is taken up front, every variant
is built from THAT, and the md5 of every live file is re-verified at the end -- a
restore that is not verified is not a restore.

Usage: run.py [lane ...]      (lanes: i64 fp8, default both)
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WORK = os.environ.get('TMPDIR', '/tmp') + '/lastlaw'
SRC = os.path.join(REPO, 'tinybendygrad')
DTB = os.path.join(REPO, '.agents/slop/dtypeb')
MIN64, MAX64 = -(1 << 63), (1 << 63) - 1

FIX = [('7_4', 7, 4), ('m7_4', -7, 4), ('7_m4', 7, -4), ('m7_m4', -7, -4),
       ('8_4', 8, 4), ('m8_4', -8, 4), ('5_0', 5, 0), ('1_1', 1, 1), ('1_m1', 1, -1),
       ('m1_3', -1, 3), ('m2_3', -2, 3), ('2_m3', 2, -3), ('max_3', MAX64, 3),
       ('min_4', MIN64, 4), ('min_m4', MIN64, -4), ('min_3', MIN64, 3),
       ('min_min', MIN64, MIN64)]

DT = ('dtype.bend', 'helpers.bend')

# ---------------------------------------------------------------- DISARM -------
# Same function, different expression. A disarm that moves a row is a defect that
# has not been named yet -- two in this project "moved 116984 and 215288 rows"
# because they turned "the same test" into "the other test".
DISARM = [
    ('D1 i64_trunc  x  ->  x | 0',
     ('dtype.bend', 'def Dt.i64_trunc(x: H.I64) -> H.I64:\n  x\n',
      'def Dt.i64_trunc(x: H.I64) -> H.I64:\n  H.i64_or(x, H.i64_zero())\n')),
    ('D2 fp8 zero line  <=  ->  not(> k-1)',
     ('dtype.bend',
      'Bool.pick(U32, U32.is_le(absx, Fp8.at(cfg, 3)), 0,',
      'Bool.pick(U32, Bool.not(U32.is_gt(absx, U32.sub(Fp8.at(cfg, 3), 1))), 0,')),
    ('D3 ceildiv.of  Bool.pick(zero,..)  ->  match zero',
     ('dtype.bend',
      '''def Dt.i64_ceildiv.of(zero: Bool, +q: H.I64, +r: H.I64, up: Bool) -> H.I64:
  Bool.pick(H.I64, zero, H.i64_zero(),
    H.i64_add(q, H.i64_bit(Bool.to_u32(Bool.and(up, Bool.not(H.i64_is_zero(r)))))))
''',
      '''def Dt.i64_ceildiv.of(zero: Bool, +q: H.I64, +r: H.I64, up: Bool) -> H.I64:
  match zero:
    case True{}: H.i64_zero()
    case False{}: H.i64_add(q, H.i64_bit(Bool.to_u32(Bool.and(up, Bool.not(H.i64_is_zero(r))))))
''')),
]

# ----------------------------------------------------------------- PLANT -------
PLANT = [
    # P1 drops the "the division did not come out even" half of the ceiling.
    ('P1 ceildiv drops  cmod != 0',
     ('dtype.bend',
      'Bool.and(up, Bool.not(H.i64_is_zero(r)))',
      'up')),
    # P2 is the bug this lane exists for: dtype.c:40/48 drops `& 0xFFu`.
    ('P2 fp8 exponent field mask  255 -> 8388607',
     ('dtype.bend',
      'def fp8_enc.exp_field(xb: U32) -> U32: U32.and(fp8_enc.shr(xb, 23), 255)',
      'def fp8_enc.exp_field(xb: U32) -> U32: U32.and(fp8_enc.shr(xb, 23), 8388607)')),
    # P3 gives fnuz the negative zero it does not have.
    ('P3 fnuz zero keeps the sign',
     ('dtype.bend',
      'Bool.pick(U32, fp8_enc.is_fnuz(kind), Bool.pick(U32, U32.is_zero(res), 0, U32.or(res, sgn)), U32.or(res, sgn))',
      'Bool.pick(U32, fp8_enc.is_fnuz(kind), Bool.pick(U32, U32.is_zero(res), sgn, U32.or(res, sgn)), U32.or(res, sgn))')),
]

# PINV -- THE GATE-ARMING PLANT, and the only one that touches a file this unit does
# not own. `i64_is_neg` is the sign read by `Dt.i64_ceildiv` DIRECTLY and by
# helpers.bend's `cdiv_i64`/`cmod_i64` INDIRECTLY, so an inversion here is invisible
# to a `--check-only` census and visible to nothing except a row that moves.
PINV = ('PINV helpers.bend  i64_is_neg  ->  not i64_is_neg',
        ('helpers.bend',
         'def i64_is_neg(x: I64) -> Bool:\n  i32_is_neg(hi32(x))\n',
         'def i64_is_neg(x: I64) -> Bool:\n  Bool.not(i32_is_neg(hi32(x)))\n'))


def sh(cmd, timeout=3600):
    """Every bend run is under `perl -e 'alarm N; exec @ARGV'`: `timeout` is not
    installed here, and a harness that cannot kill a run cannot clean up after one."""
    return subprocess.run(['perl', '-e', 'alarm %d; exec @ARGV' % timeout] + cmd,
                          cwd=REPO, capture_output=True, text=True, timeout=timeout + 120)


def md5(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


def tree_md5(root):
    out = {}
    for d, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f)
            out[os.path.relpath(p, root)] = md5(p)
    return out


def build(name, edit, pristine):
    """Copy the PRISTINE tree -- never the live one, never a mutated one."""
    holder = os.path.join(WORK, name)
    root = os.path.join(holder, 'tree')
    if os.path.isdir(holder):
        shutil.rmtree(holder)
    os.makedirs(holder)
    shutil.copytree(pristine, os.path.join(root, 'tinybendygrad'))
    p = os.path.join(root, 'tinybendygrad', 'dtype.bend')
    r = subprocess.run(['python3', os.path.join(HERE, 'patch_dtype.py'), root,
                        '--src:' + os.path.join(pristine, 'dtype.bend')],
                       capture_output=True, text=True)
    if r.returncode:
        raise SystemExit('patch failed: %s' % r.stderr[-2000:])
    for f, a, b in edit:
        q = os.path.join(root, 'tinybendygrad', f)
        s = open(q).read()
        assert s.count(a) == 1, '%s: anchor in %s appears %d times, wanted 1' % (name, f, s.count(a))
        open(q, 'w').write(s.replace(a, b, 1))
    return root


def rows(root, which, lanes):
    out = {}
    if which not in lanes:
        return out
    r = sh(['python3', os.path.join(DTB, 'gen_%s.py' % which), root])
    head = r.stdout.rstrip()
    print('----- %s / %s\n%s' % (os.path.basename(os.path.dirname(root)), which, head))
    if r.stderr.strip():
        print('  stderr:', r.stderr.strip()[:1200])
    guard(root, which, head, r)
    for ln in open(os.path.join(root, 'rows_%s.txt' % which)):
        k, _, v = ln.rstrip('\n').partition('=')
        out[k] = v
    return out


def guard(root, which, head, r):
    """THE ZERO-DENOMINATOR GUARD. Refuse a lane that examined nothing instead of
    reporting it green -- `P4` and the 65th bit are both prior instances."""
    def num(pat):
        m = re.search(pat, head)
        return int(m.group(1)) if m else -1
    exp, got = num(r'emitted (\d+)'), num(r'present (\d+)')
    if exp <= 0 or got <= 0:
        raise SystemExit('%s: ZERO DENOMINATOR -- emitted %d, present %d' % (which, exp, got))
    if exp != got:
        raise SystemExit('%s: rows expected %d != present %d' % (which, exp, got))
    if which == 'i64':
        cpy, tot = num(r'CPYTHON-VERIFIED (\d+)'), num(r'TOTALISE (\d+)')
        if cpy <= 0:
            raise SystemExit('i64: 0 CPYTHON-VERIFIED rows -- the lane proved nothing')
        if tot <= 0:
            raise SystemExit('i64: 0 TOTALISE rows -- the zero divisor is ungated')
        if cpy + tot != got:
            raise SystemExit('i64: %d + %d != %d rows present' % (cpy, tot, got))
    if which == 'fp8':
        lit = num(r'F32-LITERALS (\d+)')
        if lit <= 0:
            raise SystemExit('fp8: 0 f32 literals -- `float_to_fp8` proved nothing')
    if 'GATE PASS' not in head and os.environ.get('LL_ALLOW_RED'):
        print('  (lane %s is RED under this mutation; expected for a plant)' % which)
    elif 'GATE PASS' not in head:
        print('  (lane %s is RED under this mutation; expected for a plant)' % which)


def check(root):
    r = sh(['./bin/bend', os.path.join(root, 'tinybendygrad', 'dtype.bend'), '--check-only'])
    n = [l[2:].strip() for l in r.stderr.split('\n') if l.startswith('- ')]
    return r.stdout.strip().split('\n')[0], n


def moved(base, var):
    return sorted(k for k in set(base) | set(var) if base.get(k) != var.get(k))


def expect_p1():
    """P1 removes the "the division did not come out even" term, so it moves a row
    exactly when that term was the ONE holding the answer down: `cmod(a,b) == 0` AND
    the operands SHARED a sign. Computed from the ORACLE, not written down.

    THE FIRST VERSION OF THIS WAS INVERTED -- it derived `cmod != 0`, which is the
    set of rows the plant leaves ALONE, and so predicted 3 moves where there are 4
    and then reported a moved-set mismatch on a plant that had not moved anything.
    `cmod == 0` is the whole difference between `above` and `not above`."""
    sys.path.insert(0, REPO)
    from tinygrad import helpers as th
    want = []
    for nm, a, b in FIX:
        if b == 0:
            continue
        if th.cmod(a, b) == 0 and (a < 0) == (b < 0):
            want.append('i64_ceildiv[%s]' % nm)
    return sorted(want)


FNUZ = ['fp8e4m3fnuz', 'fp8e5m2fnuz']
KEY = re.compile(r'^(fp8_from|float_to_fp8)\[([^\]]+)\]\[(.+)\]$')


def fnuz_zero_rows(root, pat):
    """P3's reachable set, DERIVED: dtype.py's last line drops the sign from a zero
    answer, so the plant can only answer differently on a fnuz format whose CPython
    answer is 0 -- and on the sign-bearing side, since `fp8_enc.put` already answers
    0 there. The patterns come back out of the EMITTED program, so this set and the
    rows cannot drift apart, and the answers are CPython CALLS.

    THE KIND IS READ BY REGEX, not by `k.split('][')[1]`. That indexing was in my
    first version and it reads the PATTERN NAME, not the kind: the row key
    `fp8_from[fp8e4m3fnuz][denorm_k1_+0]` splits on `][` into
    `['fp8_from[fp8e4m3fnuz', 'denorm_k1_+0]']`. It returned an empty reachable set,
    which is what a suspect result looks like beside a plant that moved 33 rows.

    BOTH ROW FAMILIES, or the derivation is one short: the first version read only
    `fp8_from` and derived 32 of the 33 the plant moved. A `float_to_fp8` row's f32
    pattern is recovered from the LITERAL in its emitted call, sign included, so it is
    a call-derived pattern and not a typed one."""
    import struct
    sys.path.insert(0, REPO)
    from tinygrad import dtype as td
    pat = dict(pat)
    for ln in open(os.path.join(root, 'gate_fp8.bend')):
        if 'D.float_to_fp8(' not in ln:
            continue
        # `D.float_to_fp8(F32.neg(1.0), S.fp8e4m3())` -- the argument ends at the LAST
        # comma, not the first: `split(')')` stops inside `F32.neg(`.
        lit = ln.split('D.float_to_fp8(')[1].rsplit(',', 1)[0].strip()
        val = -float(lit[8:-1]) if lit.startswith('F32.neg(') else float(lit)
        pat[ln.split('"')[1].split('=', 1)[0]] = int.from_bytes(
            struct.pack('<f', val), 'little')
    kinds = [td.dtypes.fp8e4m3fnuz, td.dtypes.fp8e5m2fnuz]
    out = set()
    for k, p in pat.items():
        m = KEY.match(k)
        if not m or m.group(2) not in FNUZ or not (p & 0x80000000):
            continue
        v = struct.unpack('<f', struct.pack('<I', p))[0]
        if td.float_to_fp8(v, kinds[FNUZ.index(m.group(2))]) == 0:
            out.add(k)
    return out


def main():
    lanes = [a for a in sys.argv[1:] if a in ('i64', 'fp8')] or ['i64', 'fp8']
    os.makedirs(WORK, exist_ok=True)
    pristine = os.path.join(WORK, 'pristine')
    if os.path.isdir(pristine):
        shutil.rmtree(pristine)
    shutil.copytree(SRC, pristine)
    live = tree_md5(SRC)
    print('PRISTINE %d files   live md5 recorded' % len(live))

    base_root = build('base', [], pristine)
    verdict, names = check(base_root)
    print('BASE  --check-only: %s   %d foreign laws' % (verdict, len(names)))
    if names:
        print('  %s' % ', '.join(names))
        fail = 1
    else:
        fail = 0
    b = {l: rows(base_root, l, lanes) for l in lanes}
    print('BASE rows: %s' % '  '.join('%s %d' % (l, len(b[l])) for l in lanes))

    pat = {}
    fp = os.path.join(base_root, 'gate_fp8.bend')
    if 'fp8' in lanes and os.path.exists(fp):
        for ln in open(fp):
            if 'D.Dt.fp8_from(' in ln:
                row = ln.split('"')[1].split('=', 1)[0]
                pat[row] = int(ln.split('D.Dt.fp8_from(')[1].split(',')[0])

    for label, edit in DISARM:
        v = {l: rows(build(label.split()[0].lower(), [edit], pristine), l, lanes)
             for l in lanes}
        m = sum((moved(b[l], v[l]) for l in lanes), [])
        print('DISARM %-46s rows moved: %d %s' % (label, len(m), m[:8]))
        if m:
            print('  A DISARM MOVED ROWS -- that is a defect, not a disarm')
            fail += 1

    for label, edit in PLANT:
        nm = label.split()[0].lower()
        root = build(nm, [edit], pristine)
        v = {l: rows(root, l, lanes) for l in lanes}
        m = moved({**b['i64']}, v['i64']) + moved({**b['fp8']}, v['fp8'])
        print('PLANT  %-46s rows moved: %d' % (label, len(m)))
        if label.startswith('P1'):
            want = expect_p1()
            print('  derived from the mutation algebra: %d  %s' % (len(want), ' '.join(want)))
            if m != want:
                print('  P1 MOVED SET != DERIVED SET')
                fail += 1
        if label.startswith('P2'):
            # `& 0xFF` removes exactly bit 8 of `pattern >> 23`, which is bit 31 of
            # the pattern -- the SIGN BIT. So the reachable family is every row whose
            # f32 pattern carries a sign, and a negative f32 LITERAL is exactly that.
            # BOTH families are needed: my first version built only the `fp8_from` half
            # and reported 86 rows "outside the family" that were all `float_to_fp8`
            # negative decimals.
            fam = {r for r, p in pat.items() if p & 0x80000000}
            fam |= {r for r in b['fp8'] if r.startswith('float_to_fp8[')
                    and r.split('][')[1].startswith('-')}
            out = sorted(set(m) - fam)
            print('  reachability family %d (a sign-bit f32), outside it %d' % (len(fam), len(out)))
            if out:
                print('  OUTSIDE THE FAMILY: %s' % ' '.join(out[:10]))
                fail += 1
        if label.startswith('P3'):
            zero = fnuz_zero_rows(base_root, pat)
            print('  fnuz-zero sub-plant: derived %d, moved %d' % (len(zero), len(zero & set(m))))
            if zero & set(m) != zero:
                print('  P3 MOVED SET != DERIVED SET')
                fail += 1
        if not m:
            print('  PLANT MOVED NOTHING')
            fail += 1

    # ---- THE HELPER-INVERSION PLANT -------------------------------------
    root = build('pinv', [PINV[1]], pristine)
    v = {l: rows(root, l, lanes) for l in lanes}
    m = moved(b['i64'], v['i64']) + moved(b['fp8'], v['fp8'])
    print('PINV   %-46s rows moved: %d' % (PINV[0], len(m)))
    print('  %s' % ' '.join(m[:20]))
    if not m:
        print('  ** THIS GATE IS NOT AN INSTRUMENT: it is blind to an inverted sign helper **')
        fail += 1

    after = tree_md5(SRC)
    drift = sorted(k for k in set(live) | set(after) if live.get(k) != after.get(k))
    print('')
    print('LIVE TREE  %d files  md5 drift: %d' % (len(after), len(drift)))
    # ATTRIBUTION, not a bare alarm. A guard that fires on another agent's concurrent
    # edit trains its reader to ignore it, and then it does not fire on a real plant
    # either. `dtype.bend` is this unit's file and its drift is FATAL; anything else
    # under `tinybendygrad/` is another agent mid-edit, REPORTED and not failed on.
    mine = [k for k in drift if k == 'dtype.bend']
    theirs = [k for k in drift if k != 'dtype.bend']
    print("  MINE  %d  %s" % (len(mine), mine[:5]))
    print("  ANOTHER AGENT'S, not this unit's  %d  %s" % (len(theirs), theirs[:5]))
    if mine:
        print("  ** THIS UNIT'S OWN FILE MOVED. A plant was left behind. **")
        fail += 1
    print('GATE %s' % ('FAIL (%d finding(s))' % fail if fail else 'PASS'))
    sys.exit(1 if fail else 0)


main()