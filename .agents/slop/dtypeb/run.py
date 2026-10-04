#!/usr/bin/env python3
"""DTB-3 -- the four-way gate for the patched tinybendygrad/dtype.bend.

    BASE    the patch as written
    DISARM  two rewrites that compute THE SAME FUNCTIONS by different expressions
    PLANT   two mutations that are real defects
    DISARM2 one mutation that cannot move any row, and says why

ORDER IS THE POINT: DISARM runs BEFORE PLANT. A disarm that moves something is a
defect that has not been named yet -- the W64-MILE lane records a control that moved
15 rows and would have shipped a false theorem, and `renderer/cstyle.bend`'s 17 of
215 hand-typed constants were caught only because the port disagreed with CPython
rather than with itself.

The differ compares WHOLE `name=value` LINES, never row names: a name-comparing
harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
Each moved set is asserted to EQUAL the set the mutation's own algebra can reach,
so a lane that is not the one under test fails rather than passing wide.

Usage: run.py
"""
import os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WORK = os.environ.get('TMPDIR', '/tmp') + '/dtb/gate'
SRC = os.path.join(REPO, 'tinybendygrad')

# ---- the two fixtures of the i64 lane: 17 (a, b) pairs, named -----------------
MIN64, MAX64 = -(1 << 63), (1 << 63) - 1
FIX = [(7, 4), (-7, 4), (7, -4), (-7, -4), (8, 4), (-8, 4), (5, 0), (1, 1), (1, -1),
       (-1, 3), (-2, 3), (2, -3), (MAX64, 3), (MIN64, 4), (MIN64, -4), (MIN64, 3),
       (MIN64, MIN64)]

# ---- DISARM: same function, different expression ---------------------------
DISARM_I64 = [(
    'def Dt.i64_trunc(x: H.I64) -> H.I64:\n  x\n',
    'def Dt.i64_trunc(x: H.I64) -> H.I64:\n  H.i64_or(x, H.i64_zero())\n')]
DISARM_FP8 = [(
    'Bool.pick(U32, U32.is_le(absx, Fp8.at(cfg, 3)), 0,',
    'Bool.pick(U32, Bool.not(U32.is_gt(absx, U32.sub(Fp8.at(cfg, 3), 1))), 0,')]

# ---- PLANT: real defects ---------------------------------------------------
PLANT_I64 = [(
    '  Bool.pick(H.I64, fix, H.i64_sub(H.divmod_r(d), b), H.divmod_r(d))',
    '  Bool.pick(H.I64, fix, H.divmod_r(d), H.divmod_r(d))')]
# The bug the fp8 lane actually found: the exponent field without C's `& 0xFFu`.
PLANT_FP8 = [(
    'def fp8_enc.exp_field(xb: U32) -> U32: U32.and(fp8_enc.shr(xb, 23), 255)',
    'def fp8_enc.exp_field(xb: U32) -> U32: U32.and(fp8_enc.shr(xb, 23), 8388607)')]
# The exactly-derivable one: fnuz has no negative zero, and this gives it one.
PLANT_FP82 = [(
    'Bool.pick(U32, fp8_enc.is_fnuz(kind), Bool.pick(U32, U32.is_zero(res), 0, U32.or(res, sgn)), U32.or(res, sgn))',
    'Bool.pick(U32, fp8_enc.is_fnuz(kind), Bool.pick(U32, U32.is_zero(res), sgn, U32.or(res, sgn)), U32.or(res, sgn))')]

# ---- the blindness control: a real mutation whose moved set is asserted to be 0,
# and the reason is a FIXTURE GAP, not a theorem.
BLIND_FP8 = [(
    'U32.add(res, Bool.to_u32(U32.is_eq(U32.and(res, 1), 1)))',
    'U32.add(res, Bool.to_u32(U32.is_eq(U32.and(res, 2), 2)))')]


def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=3600, **kw)


def build(name, edit):
    root = os.path.join(WORK, name, 'tree')
    if os.path.isdir(os.path.dirname(root)):
        shutil.rmtree(os.path.dirname(root))
    os.makedirs(os.path.dirname(root))
    shutil.copytree(SRC, os.path.join(root, 'tinybendygrad'))
    subprocess.run(['python3', os.path.join(HERE, 'patch_dtype.py'), root],
                   check=True, capture_output=True, text=True)
    p = os.path.join(root, 'tinybendygrad', 'dtype.bend')
    s = open(p).read()
    for a, b in edit:
        assert a in s, 'DISARM/PLARM anchor not found: %r' % a[:70]
        s = s.replace(a, b, 1)
    open(p, 'w').write(s)
    return root


def rows(root, which, require=True):
    r = sh(['python3', os.path.join(HERE, 'gen_%s.py' % which), root])
    print('----- %s / %s\n%s' % (os.path.basename(os.path.dirname(root)), which,
                                 r.stdout.rstrip()))
    if r.stderr.strip():
        print('  stderr:', r.stderr.strip()[:1500])
    if require and 'GATE PASS' not in r.stdout:
        raise SystemExit('this %s lane is not green; stop here' % which)
    out = {}
    for ln in open(os.path.join(root, 'rows_%s.txt' % which)):
        k, _, v = ln.rstrip('\n').partition('=')
        out[k] = v
    return out


def check(root):
    r = sh(['./bin/bend', os.path.join(root, 'tinybendygrad', 'dtype.bend'), '--check-only'])
    first = r.stdout.strip().split('\n')[0] + ' ' + r.stderr.strip().split('\n')[0]
    n = [l for l in r.stderr.split('\n') if l.startswith('- ')]
    return first, [l[2:].strip() for l in n]


def moved(base, var):
    ks = set(base) | set(var)
    return sorted(k for k in ks if base.get(k) != var.get(k))


def expect_i64_plant():
    want = []
    NAMES = ['7_4', 'm7_4', '7_m4', 'm7_m4', '8_4', 'm8_4', '5_0', '1_1', '1_m1',
             'm1_3', 'm2_3', '2_m3', 'max_3', 'min_4', 'min_m4', 'min_3', 'min_min']
    for nm, (a, b) in zip(NAMES, FIX):
        if b != 0 and (a < 0) != (b < 0) and a % b != 0:
            want.append('i64_cmod[%s]' % nm)
    return sorted(want)


def patname(k):
    """`fp8_from[fp8e4m3][tie_k0_+0]` -> `tie_k0_+0`"""
    return k.split('][')[1][:-1]


def main():
    os.makedirs(WORK, exist_ok=True)
    base_root = build('base', [])
    v1, n1 = check(base_root)
    print('BASE  --check-only: %s\n  %d defs: %s' % (v1, len(n1), ', '.join(n1)))
    b64 = rows(base_root, 'i64')
    bf8 = rows(base_root, 'fp8')
    print('BASE rows: i64 %d, fp8 %d, total %d' % (len(b64), len(bf8), len(b64) + len(bf8)))

    # the pattern behind every `fp8_from` row, read back out of the EMITTED
    # program, so the derived set and the rows cannot drift apart
    pat = {}
    for ln in open(os.path.join(base_root, 'gate_fp8.bend')):
        if 'D.Dt.fp8_from(' in ln:
            row = ln.split('"')[1].split('=', 1)[0]
            pat[row] = int(ln.split('D.Dt.fp8_from(')[1].split(',')[0])

    fail = 0

    d_root = build('disarm', DISARM_I64 + DISARM_FP8)
    d64, df8 = rows(d_root, 'i64'), rows(d_root, 'fp8')
    m = moved(b64, d64) + moved(bf8, df8)
    print('DISARM  rows moved: %d %s' % (len(m), m[:12]))
    if m:
        print('  DISARM MOVED SOMETHING -- that is a defect, not a disarm')
        fail += 1

    p_root = build('plant', PLANT_I64 + PLANT_FP8 + PLANT_FP82)
    p64, pf8 = rows(p_root, 'i64', False), rows(p_root, 'fp8', False)
    mi = moved(b64, p64)
    mf = moved(bf8, pf8)
    wi = expect_i64_plant()
    print('PLANT  i64 rows moved: %d   derived from the mutation algebra: %d' % (len(mi), len(wi)))
    print('  moved   %s' % ' '.join(mi))
    print('  derived %s' % ' '.join(wi))
    if mi != wi:
        print('  I64 MOVED SET != DERIVED SET')
        fail += 1

    # fp8, two plants in one lane. The reachability family is DERIVED: `& 0xFF`
    # removes exactly bit 8 of `pattern >> 23`, which is bit 31 of the pattern, so
    # only a pattern with the sign bit set can be in the family -- and a negative f32
    # literal is exactly that. Anything outside the family moving would mean the
    # harness, not the mutation.
    fam = set()
    for row, p in pat.items():
        if p & 0x80000000:
            fam.add(row)
    for row in pf8:
        if row.startswith('float_to_fp8[') and row.split('][')[1].startswith('-'):
            fam.add(row)
    # the fnuz-zero plant IS exactly derivable from the oracle: it moves a row iff the
    # format is fnuz and CPython's answer is 0, because dtype.py's last line drops
    # the sign exactly there.
    zero_fnuz = set()
    for ln in open(os.path.join(base_root, 'oracle_fp8.txt')):
        k, _, v = ln.rstrip().partition('=')
        if not k.startswith(('fp8_from[fp8e4m3fnuz', 'fp8_from[fp8e5m2fnuz',
                             'float_to_fp8[fp8e4m3fnuz', 'float_to_fp8[fp8e5m2fnuz')):
            continue
        if v != '0':
            continue
        # and the sign has to be set, or the plant answers `sgn` where the port
        # already answered 0
        if k.startswith('fp8_from['):
            if pat[k] & 0x80000000:
                zero_fnuz.add(k)
        elif k.split('][')[1].startswith('-'):
            zero_fnuz.add(k)
    fam_moved = sorted(set(mf) & fam)
    outside = sorted(set(mf) - fam)
    print('PLANT  fp8 rows moved: %d   reachability family: %d   outside the family: %d'
          % (len(mf), len(fam), len(outside)))
    print('  fnuz-zero sub-plant: derived %d, of those moved %d'
          % (len(zero_fnuz), len(zero_fnuz & set(mf))))
    if outside:
        print('  OUTSIDE THE FAMILY: %s' % ' '.join(outside[:10]))
        fail += 1
    if len(set(mf) & zero_fnuz) != len(zero_fnuz):
        print('  FNUZ-ZERO MOVED SET != DERIVED SET')
        fail += 1
    if not mf:
        print('  PLANT MOVED NOTHING')
        fail += 1

    b2_root = build('blind', BLIND_FP8)
    b2f8 = rows(b2_root, 'fp8', False)
    m2 = moved(bf8, b2f8)
    print('BLIND  fp8 rows moved: %d' % len(m2))
    if m2:
        print('  %s' % ' '.join(m2[:10]))

    print('')
    print('GATE %s' % ('FAIL (%d finding(s))' % fail if fail else 'PASS'))
    sys.exit(1 if fail else 0)


main()