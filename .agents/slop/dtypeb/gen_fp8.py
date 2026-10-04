#!/usr/bin/env python3
"""DTB-2 -- the float_to_fp8 lane gate for tinybendygrad/dtype.bend.

Two row families, and they ask different questions:

  fp8_from[kind][pattern]      `Dt.fp8_from` over arbitrary f32 BIT PATTERNS. This
                               is where all of the arithmetic is, and a U32
                               literal is the only way to name a pattern, because
                               Bend cannot BUILD an F32 from bits -- the very gap
                               that keeps `Dt.fp8_to` a seam.
  float_to_fp8[kind][decimal]  the wrapper, end to end, over f32 LITERALS. It adds
                               `F32.bits` and `fp8_kind`, and nothing else, so it is
                               gated on patterns chosen from the ladder rather than
                               at random.

Oracle: tinygrad/dtype.py float_to_fp8, CALLED on the f32-rounded value, never
transcribed. Expectations are generated here and asserted in Bend; the two are
compared by the differ in run.py.

Usage: gen_fp8.py <tree-root> [--emit-only]
"""
import os, random, re, struct, subprocess, sys

REPO = '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad'
sys.path.insert(0, REPO)
from tinygrad import dtype as td

DT = [td.dtypes.fp8e4m3, td.dtypes.fp8e5m2, td.dtypes.fp8e4m3fnuz, td.dtypes.fp8e5m2fnuz]
KN = ['fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz']

# dtype.c:31-37 in hex, the five thresholds the ladder turns on.
BIAS = [7, 15, 8, 16]
SIG = [4, 3, 4, 3]
DENORM = [0x3A800000, 0x37000000, 0x3A000000, 0x36800000]
OVF = [0x43E80000, 0x47700000, 0x43780000, 0x47700000]
MINNORM = [0x3C800000, 0x38800000, 0x3C000000, 0x38000000]


def as_f32(pattern):
    return struct.unpack('<f', struct.pack('<I', pattern & 0xFFFFFFFF))[0]


def patterns():
    """Named, and the names say WHY each one is here. Ordered by f32 bit pattern,
    which puts the negative ones first -- they are the sign-bit rows."""
    p = [('zero', 0x00000000), ('zero_neg', 0x80000000),
         ('one', 0x3F800000), ('one_neg', 0xBF800000),
         ('two', 0x40000000), ('half', 0x3F000000), ('quarter', 0x3E800000),
         ('min_normal', 0x00800000), ('max_normal', 0x7F7FFFFF),
         ('exp_ff', 0x7F800000), ('exp_ff_neg', 0xFF800000),
         ('nan', 0x7FC00000), ('nan_neg', 0xFFC00000)]
    for k in range(4):
        # every threshold, one either side, and the sign of it
        for tag, t in (('denorm', DENORM[k]), ('ovf', OVF[k]), ('minnorm', MINNORM[k])):
            for d in (-1, 0, 1, 2):
                v = (t + d) & 0x7FFFFFFF
                p.append(('%s_k%d_%s%+d' % (tag, k, '', d), v | 0x80000000))
                p.append(('%s_k%d_%s%+d_p' % (tag, k, '', d), v))
        # the whole subnormal window: bias + exp_field == 127 - 1 .. bias + ... ;
        # each of its exponents is a distinct rung of the shift ladder
        lo = ((DENORM[k] & 0x7F800000) >> 23) + 1
        hi = ((MINNORM[k] & 0x7F800000) >> 23) - 1
        for ef in range(lo, hi + 1):
            for mant in (0, 1, 0x400000, 0x7FFFFF, 0x600000):
                p.append(('sub_k%d_ef%d_m%06x' % (k, ef, mant), (ef << 23) | mant))
        # the tie bit exactly, and one either side of it: the only rows that can
        # separate round-half-to-even from round-half-away
        hu = 1 << (23 - SIG[k])
        for d in (-1, 0, 1):
            p.append(('tie_k%d%+d' % (k, d), 0x3F800000 | ((hu + d) & (2 * hu - 1))))
        p.append(('tie_maxnorm_k%d' % k, (MINNORM[k] & 0x7F800000) | (hu - 1)))
    rnd = random.Random(20261004)
    for i in range(40):
        p.append(('rnd%02d' % i, rnd.getrandbits(32)))
    return p


def short_decimal(pattern):
    """The exact value of the f32 as a decimal Bend can be given, or None if it is
    not short enough to be worth a literal."""
    v = as_f32(pattern)
    if v != v or v in (float('inf'), float('-inf')) or v == 0.0:
        return None
    s = repr(v)
    if '.' not in s and 'e' not in s:
        s += '.0'
    return s if len(s) <= 22 and 'e' not in s else None


def oracle(pattern, k):
    return td.float_to_fp8(as_f32(pattern), DT[k])


def expected():
    exp = {}
    for nm, pat in patterns():
        for k in range(4):
            exp['fp8_from[%s][%s]' % (KN[k], nm)] = oracle(pat, k)
    lits = []
    for nm, pat in patterns():
        d = short_decimal(pat)
        if d is not None and all(lits.count((d, k)) == 0 for k in range(4)):
            lits.append((d, nm))
    for d, nm in lits:
        for k in range(4):
            exp['float_to_fp8[%s][%s]' % (KN[k], d)] = oracle(int.from_bytes(
                struct.pack('<f', float(d)), 'little'), k)
    return exp, len(lits)


KEY = re.compile(r'^(fp8_from|float_to_fp8)\[([^\]]+)\]\[(.+)\]$')


CHUNK = 100          # one do-block per chunk: 1228 rows in ONE block overflows the
                     # machine stack (measured), so the chunking is a build fact.


def emit(root, exp, nlits):
    calls, n = [], 0
    for k in exp:
        pre, kn, arg = KEY.match(k).groups()
        ki = KN.index(kn)
        if pre == 'fp8_from':
            call = 'D.Dt.fp8_from(%d, %d)' % (PAT[arg], ki)
        else:
            # Bend has no unary minus on a literal (llvmir.bend:990 spells it
            # F32.neg), and the ROW NAME keeps the sign either way.
            lit = 'F32.neg(%s)' % arg[1:] if arg.startswith('-') else arg
            call = 'D.float_to_fp8(%s, S.%s())' % (lit, DTNAME[ki])
        calls.append((k, call))
        n += 1
    out = [
        'import Base',
        'import ./tinybendygrad/LAWS/spec.bend as S',
        'import ./tinybendygrad/helpers.bend as H',
        'import ./tinybendygrad/dtype.bend as D',
        '',
    ]
    for c0 in range(0, len(calls), CHUNK):
        ch = calls[c0:c0 + CHUNK]
        out.append('def chunk%d() -> IO(Unit):' % c0)
        out.append('  do IO<Unit>:')
        for j, (k, call) in enumerate(ch):
            out.append('    s%d : String <- IO.pure(String, "%s=" ++ U32.show(%s))' % (c0 + j, k, call))
        out.append('    out%d : String <- IO.pure(String, String.concat([' % c0)
        out.append(', '.join('s%d ++ "\\n"' % (c0 + j) for j in range(len(ch))) + ']))')
        out.append('    IO.print(out%d)' % c0)
        out.append('')
    out.append('def main() -> IO(Unit):')
    out.append('  do IO<Unit>:')
    for c0 in range(0, len(calls), CHUNK):
        out.append('    c%d : Unit <- chunk%d()' % (c0, c0))
    out.append('    IO.print("")')
    src = '\n'.join(out) + '\n'
    dst = os.path.join(root, 'gate_fp8.bend')
    open(dst, 'w').write(src)
    return dst, n


DTNAME = ['fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz']
PAT = dict(patterns())


def run(path):
    r = subprocess.run(['./bin/bend', path], cwd=REPO, capture_output=True, text=True,
                       timeout=1800)
    rows = {}
    for ln in r.stdout.split('\n'):
        ln = ln.strip()
        if '=' in ln and ln.split('=')[0].startswith(('fp8_from', 'float_to_fp8')):
            k, _, v = ln.partition('=')
            rows[k.strip()] = v.strip()
    return rows, r.stderr


def main():
    root = sys.argv[1]
    exp, nlits = expected()
    path, nrows = emit(root, exp, nlits)
    if '--emit-only' in sys.argv:
        print('emitted %d rows (%d f32 literals) -> %s' % (nrows, nlits, path))
        return
    rows, err = run(path)
    missing = sorted(set(exp) - set(rows))
    extra = sorted(set(rows) - set(exp))
    bad = sorted(k for k in set(exp) & set(rows) if str(exp[k]) != rows[k])
    print('ROWS  emitted %d  expected %d  present %d  missing %d  extra %d  mismatch %d'
          % (nrows, len(exp), len(rows), len(missing), len(extra), len(bad)))
    print('PATTERNS %d  F32-LITERALS %d  RANDOM %d'
          % (len(PAT), nlits, sum(1 for n in PAT if n.startswith('rnd'))))
    if err.strip() and '2.0.35' not in err:
        print('STDERR:', err.strip()[:3000])
    for k in missing[:8]:
        print('  MISSING %s' % k)
    for k in extra[:8]:
        print('  EXTRA   %s = %s' % (k, rows[k]))
    for k in bad[:10]:
        print('  MISMATCH %s port=%s cpython=%s' % (k, rows[k], exp[k]))
    ok = not missing and not extra and not bad and len(rows) == len(exp)
    print('GATE %s' % ('PASS' if ok else 'FAIL'))
    with open(os.path.join(root, 'rows_fp8.txt'), 'w') as fh:
        for k in sorted(rows):
            fh.write('%s=%s\n' % (k, rows[k]))
    with open(os.path.join(root, 'oracle_fp8.txt'), 'w') as fh:
        for k in sorted(exp):
            fh.write('%s=%s\n' % (k, exp[k]))
    sys.exit(0 if ok else 1)


main()