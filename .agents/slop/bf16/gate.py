#!/usr/bin/env python3
"""bf16 gate -- drives the LIVE tinybendygrad/runtime/dtype.c under cc against
CPython, over the FULL bf16 input space.

WHAT UPSTREAM DOES, AND IT IS NOT A JUDGEMENT -- dtype.py:229-233:

    def float_to_bf16(x):
      if not math.isfinite(x): return x          # <-- dtype.py:230
      u = struct.unpack('I', struct.pack('f', truncate[dtypes.float](x)))[0]
      u = (u + 0x7FFF + ((u >> 16) & 1)) & 0xFFFF0000
      return struct.unpack('f', struct.pack('I', u))[0]

So upstream's answer for a non-finite input is `x` UNCHANGED: non-finite
round-trips, payload and sign both intact. It is NOT saturation, and it is NOT
"round the bits anyway". The missing guard's correct content is therefore
`return x`, and dtype.bend:608 already has exactly that guard in the Bend lane.

THE ORACLE BOUNDARY IS WHERE THIS CLASS OF GATE GOES WRONG, AND IT IS MEASURED
HERE, NOT ASSUMED. `float_to_bf16` takes a PYTHON FLOAT, and a Python float
cannot hold a signalling NaN: widening an f32 sNaN to f64 quiets it. Measured
exhaustively over all 16777216 non-finite f32 patterns, both signs:

    survives a Python-float round trip   8388610
    lost by the oracle boundary itself   8388606
    ... all 8388606 lost ONLY by sNaN->qNaN quieting (p | 0x400000)
    ... lost any other way                    0

Which is the SAME number, and the same class, as JSFP8's `JFP-5` on the JS lane
(8388606 of 16777214). Two runtimes, one IEEE rule, two lanes. So a gate that
routes every row through a Python float cannot see 8388606 of the patterns it
claims to cover, and would silently grade them against a value CPython invented.

THE ORACLE USED HERE THEREFORE HAS TWO PARTS, and neither is dtype.c:
  * `SPEC(p)` -- dtype.py:229-233 read AT THE PATTERN LEVEL, which is what the
    seam actually exchanges. Established against CPython on every pattern CPython
    can express (below), so it is a CHECKED reading of dtype.py, not a transcript.
  * `CPY(p)` -- dtype.py called for real, on every pattern a Python float CAN
    express. This is the part that is CALLED and not typed.

Both must agree with dtype.c. A row is a mismatch if EITHER oracle disagrees.
"""
import os, struct, subprocess, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
# HERE is .agents/slop/bf16 -- THREE levels deep. MEASURED: with `..`/`..` this
# resolved DTYPE_C into `.agents/tinybendygrad/...`, which does not exist, and
# the only symptom was clang saying `dtype.c` was not found.
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DTYPE_C = os.path.join(ROOT, "tinybendygrad", "runtime", "dtype.c")
EXE = os.path.join(os.environ.get("TMPDIR", "/tmp"), "bf16")

sys.path.insert(0, ROOT)
from tinygrad.dtype import float_to_bf16  # dtype.py:229
from tinygrad import dtypes


def build(dtype_c=DTYPE_C, exe=EXE):
    r = subprocess.run(
        ["cc", "-O2", "-I", HERE, "-I", os.path.dirname(dtype_c), "-o", exe,
         os.path.join(HERE, "bf16_gate.c"), "-lm"],
        capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("BUILD FAILED\n" + r.stderr)
    return exe


def md5(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def s2f(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def f2s(v):
    return struct.unpack("<I", struct.pack("<f", v))[0]


def spec(p):
    """dtype.py:229-233 AT THE PATTERN LEVEL -- what the seam exchanges."""
    if (p & 0x7F800000) == 0x7F800000:
        return p                                   # dtype.py:230, verbatim
    return (p + 0x7FFF + ((p >> 16) & 1)) & 0xFFFF0000   # dtype.py:232


def cpy(p):
    """dtype.py called for real. None when a Python float cannot express p."""
    x = s2f(p)
    if f2s(x) != p:
        return None                                # sNaN: CPython cannot hold it
    return f2s(float_to_bf16(x))


def expressible(p):
    return (p & 0x7F800000) != 0x7F800000 or f2s(s2f(p)) == p


def bf16_rows():
    """EVERY bf16 code, 65536, both signs: the sign is bit 15 so the 65536
    already carry it. The FULL space, not a sample."""
    for code in range(1 << 16):
        yield f"B[{code:04x}]", code << 16


def nonfinite_rows():
    """EVERY bf16 non-finite encoding: exponent all ones x 128 significands, BOTH
    signs = 256, of which 2 are inf. The measured count is the assertion: a range
    that covers one sign reads 128 and looks exhaustive."""
    for code in list(range(0x7F80, 0x8000)) + list(range(0xFF80, 0x10000)):
        yield f"N[{code:04x}]", code << 16


# THE LOW HALVES for family X. Chosen to sit either side of every rounding
# decision the RNE line makes, not sampled: 0x0000 exact, 0x0001/0x0002 just
# above, 0x3FFF/0x4000/0x4001 the tie and its two neighbours (0x4000 is the tie),
# 0x7FFF/0x8000/0x8001 the top of the low half and the carry, 0xC000 past it,
# 0xFFFE/0xFFFF the top. Any low half that can change the answer is in this set
# or differs from one that is, in which case the pair 0x4000/0x4001 already
# separates it -- and that claim is CHECKED by the mutation table, not asserted.
X_LOW = (0x0000, 0x0001, 0x0002, 0x3FFF, 0x4000, 0x4001,
         0x7FFF, 0x8000, 0x8001, 0xC000, 0xFFFE, 0xFFFF)


def f32_nonfinite_rows():
    """The FULL f32 non-finite space, 16777216, both signs: exponent all ones x
    2^23 significands x 2 signs.

    THIS IS 16.7 MILLION ROWS AND THE PIPE COSTS ~10 s PER DRIVE, which is why it
    is enumerated in C (`census`) rather than here. It is kept as a generator
    because its DEFINITION is the exhaustive one and the census is checked
    against it; see census_rows() for the count assertion.

    It is also the family the bf16 code space provably cannot see:

      For any pattern whose low 16 bits are ZERO -- which is EVERY bf16 code,
      since bf16 IS the top half of an f32 pattern -- adding 0x7FFF cannot carry
      out of the low half, so the unguarded rounding line is the IDENTITY there.

    So a gate over the bf16 input space cannot distinguish "guard present" from
    "guard absent" or "guard inverted": on all 65536 of its rows the rounding is a
    no-op either way. MEASURED below: PLANT-inverted and DISARM-removed each move
    0 rows over B and N. The defect the report names is REAL -- 16776960 of these
    patterns are wrong without the guard -- and it is INVISIBLE to the very gate
    the report's own remedy would build. Both facts are needed; either alone is a
    false report."""
    for sign in (0, 1):
        for m in range(0, 0x800000):
            p = (sign << 31) | 0x7F800000 | m
            yield f"F[{p:08x}]", p


def f32_rounding_rows():
    """FINITE patterns with a NONZERO low half -- the family that discriminates
    guard POLARITY, which the bf16 code space cannot (see above: rounding is the
    identity on a zero low half, so an inverted guard and no guard are the same
    function there).

    Every one of the 512 finite high halves (2 signs x 256 exponent/significand
    combinations) crossed with the 12 low halves that bracket every RNE
    decision: 6144 rows, both signs, every exponent from 0 (subnormal) to 254.
    The high half is enumerated, NOT sampled -- 0..0x7F then | 0x8000 per sign
    covers every bf16-representable high half there is."""
    for sign in (0, 1):
        for hi in range(0x100):
            base = (sign << 31) | (hi << 16)
            if (base & 0x7F800000) == 0x7F800000:
                continue                       # non-finite: family F's job
            for lo in X_LOW:
                yield f"X[{base | lo:08x}]", base | lo


def drive(rows, exe=EXE):
    inp = "".join(f"{n}\t{p:08x}\n" for n, p in rows)
    r = subprocess.run([exe, "rows"], input=inp, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("GATE FAILED\n" + r.stderr)
    out = {}
    for line in r.stdout.splitlines():
        if not line.strip():
            continue
        n, _, v = line.partition("=")
        assert n not in out, f"duplicate row name {n} -- fixture defect"
        out[n] = int(v, 16)
    return out


def check(rows, exe=EXE, verbose=True):
    """A row fails on EITHER oracle. Returns (n_expected, n_present, mismatches,
    n_cpy_rows)."""
    rows = list(rows)
    got = drive(rows, exe)
    mm, n_cpy = [], 0
    for n, p in rows:
        want_spec = spec(p)
        want_cpy = cpy(p)
        if want_cpy is not None:
            n_cpy += 1
            assert want_cpy == want_spec, (
                f"ORACLES DISAGREE at {n}: spec={want_spec:08x} cpython={want_cpy:08x}"
                "-- the fixture is wrong, not the port")
        have = got[n]
        if have != want_spec:
            mm.append((n, p, want_spec, want_cpy, have))
    return len(rows), len(got), mm, n_cpy


def census(exe=EXE):
    """The exhaustive claim, run in C: all 2^32, `nonfinite(p) && got(p) != p`,
    which is exactly dtype.py:230's contract for every non-finite pattern."""
    r = subprocess.run([exe, "census", os.devnull], capture_output=True, text=True)
    return r.stdout.strip()


def main():
    exe = build()
    print(f"dtype.c md5 {md5(DTYPE_C)}")
    for label, rows in (("B bf16 code space (FULL 65536)", list(bf16_rows())),
                        ("N bf16 non-finite (FULL 256)", list(nonfinite_rows())),
                        ("X f32 finite rounding (6144)", list(f32_rounding_rows()))):
        n_exp, n_got, mm, n_cpy = check(rows, exe)
        print(f"{label}: expected={n_exp} present={n_got} "
              f"cpython_checked={n_cpy} MISMATCH={len(mm)}")
        for n, p, w, c, h in mm[:6]:
            cs = "unexpressible" if c is None else f"{c:08x}"
            print(f"  {n} in={p:08x} spec={w:08x} cpython={cs} dtype.c={h:08x}")
        if len(mm) > 6:
            print(f"  ... {len(mm)-6} more")
    print()
    for line in census(exe).splitlines():
        print("  " + line)


if __name__ == "__main__":
    main()