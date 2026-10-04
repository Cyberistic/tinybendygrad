#!/usr/bin/env python3
"""DTB-1 -- the i64 lane gate for tinybendygrad/dtype.bend.

Emits a .bend program into a tree that holds the PATCHED dtype.bend, runs it, and
diffs whole `name=value` lines against an oracle that is CPython CALLED, never
transcribed. rows PRESENT vs rows EXPECTED are counted on every run.

  oracle    tinygrad/helpers.py cdiv/cmod/ceildiv, and Python's own // and %
  fixtures  17, named, chosen to separate floor from truncated on every sign

Usage: gen_i64.py <tree-root>
"""
import os, subprocess, sys

REPO = '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad'
sys.path.insert(0, REPO)
from tinygrad import helpers as th

MIN64 = -(1 << 63)
MAX64 = (1 << 63) - 1

# (name, a, b). Named, because the PLANT's moved set is DERIVED from these by the
# mutation's own algebra; a transcribed list is the thing AGENTS.md has caught five
# times. `fix` is sign(a) != sign(b) and floormod(a,b) != 0 -- the only inputs on
# which dropping the `- b` from cmod can change the answer.
FIX = [
    ('7_4',            7, 4),
    ('m7_4',          -7, 4),
    ('7_m4',           7, -4),
    ('m7_m4',        -7, -4),
    ('8_4',            8, 4),
    ('m8_4',          -8, 4),
    ('5_0',            5, 0),
    ('1_1',            1, 1),
    ('1_m1',           1, -1),
    ('m1_3',          -1, 3),
    ('m2_3',          -2, 3),
    ('2_m3',           2, -3),
    ('max_3',   MAX64, 3),
    ('min_4',   MIN64, 4),
    ('min_m4',  MIN64, -4),
    ('min_3',   MIN64, 3),
    ('min_min', MIN64, MIN64),
]

DEFS = ['i64_trunc', 'i64_floor_div', 'i64_floor_mod', 'i64_cdiv', 'i64_cmod', 'i64_ceildiv']


def u32(v):
    return v & 0xFFFFFFFF


def bend(v):
    return 'H.i64_of_hi_lo(%d, %d)' % (u32(v >> 32), u32(v))


def fix_true(a, b):
    """The plant's own algebra, computed from the oracle -- not a written list."""
    if b == 0:
        return False
    r = a % b
    return (a < 0) != (b < 0) and r != 0


# NO CPython ANSWER FOR THESE THREE, and no pretense of one. helpers.py:66-69 has no
# zero guard on ceildiv and Python's own `//` and `%` raise ZeroDivisionError, so
# for b == 0 the oracle is CPython RAISING. What the port answers instead is the
# zero branch runtime/dtype.c already documented -- dtype.c:191 `if (b == 0) {q=0,
# r=a}`, dtype.c:239 `if (b == 0) return 0` -- so the expectation below is checked
# against the C lane's own written totalisation and is labelled TOTALISE. It is not
# a pass and it is not CPython; saying so is the point.
TOTALISE = 2

def oracle(a, b):
    if b == 0:
        return {'i64_trunc': (a, 0), 'i64_floor_div': (0, TOTALISE),
                'i64_floor_mod': (a, TOTALISE), 'i64_cdiv': (0, 0),
                'i64_cmod': (a, 0), 'i64_ceildiv': (0, TOTALISE)}
    return {'i64_trunc': (a, 0), 'i64_floor_div': (a // b, 0),
            'i64_floor_mod': (a % b, 0), 'i64_cdiv': (th.cdiv(a, b), 0),
            'i64_cmod': (th.cmod(a, b), 0), 'i64_ceildiv': (th.ceildiv(a, b), 0)}


def expected():
    exp = {}
    for nm, a, b in FIX:
        for dfx, (v, d) in oracle(a, b).items():
            exp['%s[%s]' % (dfx, nm)] = ('%d:%d' % (u32(v >> 32), u32(v)), d)
    return exp


def emit(root):
    binds, body, n = [], [], 0
    for nm, a, b in FIX:
        A, B = bend(a), bend(b)
        for dfx in DEFS:
            arg = A if dfx == 'i64_trunc' else '%s, %s' % (A, B)
            binds.append('    s%d : String <- IO.pure(String, "%s[%s]=" ++ show(D.Dt.%s(%s)))'
                         % (n, dfx, nm, dfx, arg))
            body.append('      s%d ++ "\\n"' % n)
            n += 1
    src = '\n'.join([
        'import Base',
        'import ./tinybendygrad/LAWS/spec.bend as S',
        'import ./tinybendygrad/helpers.bend as H',
        'import ./tinybendygrad/dtype.bend as D',
        '',
        'def show(+x: H.I64) -> String:',
        '  match x:',
        '    case H.I64{hi, lo}: U32.show(hi) ++ ":" ++ U32.show(lo)',
        '',
        'def main() -> IO(Unit):',
        '  do IO<Unit>:',
    ] + binds + [
        '    out : String <- IO.pure(String, String.concat([',
        ', '.join(body) + ']))',
        '    IO.print(out)',
        ''])
    dst = os.path.join(root, 'gate_i64.bend')
    open(dst, 'w').write(src)
    return dst, n


def run(path):
    r = subprocess.run(['./bin/bend', path], cwd=REPO, capture_output=True, text=True,
                       timeout=1800)
    rows = {}
    for ln in r.stdout.split('\n'):
        ln = ln.strip()
        if '=' in ln and ln.split('=')[0].startswith(('i64_', 'float_to', 'fp8')):
            k, _, v = ln.partition('=')
            rows[k.strip()] = v.strip()
    return rows, r.stderr


def main():
    root = sys.argv[1]
    path, nrows = emit(root)
    rows, err = run(path)
    exp = expected()
    div = sorted(k for k, (v, d) in exp.items() if d == TOTALISE)
    cmp = {k: v for k, (v, d) in exp.items() if d != TOTALISE}
    tot = {k: v for k, (v, d) in exp.items() if d == TOTALISE}
    missing = sorted(set(exp) - set(rows))
    extra = sorted(set(rows) - set(exp))
    bad = sorted(k for k in set(cmp) & set(rows) if cmp[k] != rows[k])
    badt = sorted(k for k in set(tot) & set(rows) if tot[k] != rows[k])
    print('ROWS  emitted %d  expected %d  present %d  missing %d  extra %d  mismatch %d'
          % (nrows, len(exp), len(rows), len(missing), len(extra), len(bad)))
    print('CPYTHON-VERIFIED %d rows   TOTALISE %d rows (mismatch %d)'
          % (len(cmp), len(tot), len(badt)))
    print('FIXTRUE %d: %s' % (sum(1 for _, a, b in FIX if fix_true(a, b)),
          ' '.join(nm for nm, a, b in FIX if fix_true(a, b))))
    if err.strip() and '2.0.35' not in err:
        print('STDERR:', err.strip()[:3000])
    for k in missing[:8]:
        print('  MISSING %s' % k)
    for k in extra[:8]:
        print('  EXTRA   %s = %s' % (k, rows[k]))
    for k in bad[:10]:
        print('  MISMATCH %s port=%s oracle=%s' % (k, rows[k], cmp[k]))
    for k in badt[:8]:
        print('  TOTALISE-MISMATCH %s port=%s c_zero_branch=%s' % (k, rows[k], tot[k]))
    ok = not missing and not extra and not bad and not badt and len(rows) == len(exp)
    print('GATE %s' % ('PASS' if ok else 'FAIL'))
    with open(os.path.join(root, 'rows_i64.txt'), 'w') as fh:
        for k in sorted(rows):
            fh.write('%s=%s\n' % (k, rows[k]))
    sys.exit(0 if ok else 1)


main()