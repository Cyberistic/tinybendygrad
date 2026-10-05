#!/usr/bin/env python3
"""I64DIV gate generator.

EVERY expectation is produced by CALLING tinygrad/helpers.py -- `floordiv`,
`floormod`, `cdiv`, `cmod` -- and `math.gcd`, and Python's `str`. Nothing is typed.

FIVE row families, because five defs are under test:
  d_  i64_div     <- floordiv
  m_  i64_mod     <- floormod
  c_  cdiv_i64    <- cdiv
  k_  cmod_i64    <- cmod
  g_  gcd         <- math.gcd
  t_  i64_dec     <- str          (a second, String-linear lane: a row name cannot
                                     feed two IO.prints, so this is its own def)

Emits one main PER BATCH: the divider is 64 steps of restoring division per call and
a single program over ~800 rows dies with `the machine stack overflowed`.
"""
import sys, os, math, random

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, REPO)
from tinygrad.helpers import cdiv, cmod, floordiv, floormod  # noqa: E402

W = 1 << 64
S = 1 << 63
M = 1 << 32
def w(v):
    v &= W - 1
    return f"{v >> 32}:{v & 0xFFFFFFFF}"
def sg(v):
    v &= W - 1
    return v - W if v >= S else v
def bend_i64(v):
    u = v & (W - 1)
    return (u >> 32, u & (M - 1))

# ---------------------------------------------------------------- fixtures --
FIX = []
def add(nm, a, b):
    assert -(1 << 63) <= a < S and -(1 << 63) <= b < S, (nm, a, b)
    FIX.append((nm, a, b))

# the extremes, both signs, and the neighbours of every one of them
CORE = [-S, -S + 1, -S + 2, -S + 3, -(1 << 62), -(1 << 62) + 1, -(1 << 32),
        -(1 << 32) + 1, -65537, -65536, -65535, -257, -256, -255, -7, -3, -2, -1,
        0, 1, 2, 3, 7, 255, 256, 257, 65535, 65536, 65537,
        (1 << 32) - 1, 1 << 32, (1 << 62) - 1, 1 << 62, S - 3, S - 2, S - 1]
for a in CORE:
    for b in CORE:
        add(f"g_{a}_{b}", a, b)

# THE SEAM. A quotient whose BIT 63 is set is only reachable when the MAGNITUDE
# reaches 2**63, and the only i64 with that magnitude is int64.min -- so every
# such pair has int64.min as the DIVIDEND. (2**63 is not representable, so it can
# never be the divisor; that is stated, not assumed: see seam_probe.py.)
LADDER = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 7, -7, 8, -8, 9, 9 - 1, 1 << 16,
          1 << 31, (1 << 31) - 1, 1 << 32, (1 << 32) - 1, 1 << 62, (1 << 62) - 1,
          -S + 1, S - 1, -S]
DIVIDENDS = [-S, -S + 1, -S + 2, -S + 3, -(1 << 62), S - 3, S - 2, S - 1, -1, 0, 1]
for a in DIVIDENDS:
    for b in LADDER:
        add(f"s_{a}_{b}", a, b)
# and the transpose, so int64.min is the DIVISOR (that is the 2**63 operand the
# seam needs: floor(|a| / 2**63) is 0 for every |a| < 2**63)
for b in [-S, -S + 1, S - 1, S - 2, 1, -1, 3, -3]:
    for a in DIVIDENDS:
        add(f"v_{a}_{b}", a, b)

# the 2**k +- 1 ladder, since a divisor just below a power of two is what pushes
# the quotient's top bit
for k in (0, 1, 2, 8, 15, 16, 17, 31, 32, 33, 62):
    for d in (-1, 0, 1):
        v = (1 << k) + d
        if -(1 << 63) <= v < S:
            for a in (-S, -S + 1, S - 1, -1, 1, 7):
                add(f"p{k}_{d}_{a}", a, v)

random.seed(20261005)
for i in range(90):
    add(f"r{i}", random.randrange(-S, S), random.randrange(-S, S))
# random pairs WITH int64.min, which is the population the whole defect lives in
for i in range(90):
    if i % 2:
        add(f"n{i}", -S, random.randrange(-S, S))
    else:
        add(f"n{i}", random.randrange(-S, S), -S)
# random small divisors against extreme dividends: the highest quotient density
for i in range(60):
    add(f"q{i}", random.choice([-S, -S + 1, S - 1, -1, 1, S - 2]),
        random.choice([1, -1, 2, -2, 3, -3, random.randrange(1, 1 << 16)]))

# the ZERO-DIVISOR rows, called not assumed: floordiv/floormod/cdiv/cmod all guard
# and only ceildiv raises. These are emitted as their own family so a divergence
# there can never be counted as an ordinary pass.
ZERO = [1, -1, 7, -7, S - 1, -S, S - 2, 1 << 32, 0]
for x in ZERO:
    add(f"z{x}_0", x, 0)

# --------------------------------------------------------------- expected ---
EXP, WRAP, ZERO_ROWS = [], set(), set()

def emit(name, upstream):
    """One expectation. A row whose EXACT upstream answer is outside the i64 range
    is recorded in WRAP as well, so it is never silently counted as an ordinary
    pass -- it is the documented 64-bit wrap direction."""
    EXP.append(f"{name}={w(upstream)}")
    if not (-S <= upstream < S):
        WRAP.add(name)

for nm, a, b in FIX:
    if b == 0:
        # `d_`/`c_` are floordiv/cdiv (both answer 0), `m_`/`k_` are the two
        # remainders (both answer the dividend). Measured by calling, not assumed.
        emit(f"d_{nm}", floordiv(a, b)); emit(f"c_{nm}", cdiv(a, b))
        emit(f"m_{nm}", floormod(a, b)); emit(f"k_{nm}", cmod(a, b))
        emit(f"g_{nm}", math.gcd(a, b))
        for t in ("d", "c", "m", "k", "g"):
            ZERO_ROWS.add(f"{t}_{nm}")
        continue
    emit(f"d_{nm}", floordiv(a, b))
    emit(f"m_{nm}", floormod(a, b))
    emit(f"c_{nm}", cdiv(a, b))
    emit(f"k_{nm}", cmod(a, b))
    emit(f"g_{nm}", math.gcd(a, b))

# `i64_dec` is `str(int)` for a NON-NEGATING fold. It is a separate lane because
# `String` is LINEAR: a row name cannot feed two IO.prints, so `trow` owns it.
DEC_X = [-S, -S + 1, -S + 2, -(1 << 62), -65537, -257, -7, -1, 0, 1, 2, 3, 7,
         255, 256, 65535, 65536, (1 << 32) - 1, 1 << 32, (1 << 62) - 1, 1 << 62,
         S - 3, S - 2, S - 1, 10, 100, 1234567890123456789]
for x in DEC_X:
    EXP.append(f"t_{x}={str(x)}")
    ZERO_ROWS.discard(f"t_{x}")

# ------------------------------------------------------------------ .bend ---
HEADER = open(os.path.join(HERE, "hdr.bend")).read()

ACC = """
def drow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["d_", nm, "=",
      H.i64_text(H.i64_div(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def mrow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["m_", nm, "=",
      H.i64_text(H.i64_mod(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def crow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["c_", nm, "=",
      H.i64_text(H.cdiv_i64(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def krow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["k_", nm, "=",
      H.i64_text(H.cmod_i64(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def grow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["g_", nm, "=",
      H.i64_text(H.gcd(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def trow(nm: String, ah: U32, al: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["t_", nm, "=", H.i64_dec(H.i64_of_hi_lo(ah, al))]))

def main() -> IO(Unit):
  do IO<Unit>:"""

def lits(a, b):
    ah, al = bend_i64(a)
    bh, bl = bend_i64(b)
    return f"{ah}, {al}, {bh}, {bl}"

PER = 20
for f in os.listdir(HERE):
    if f.startswith("gate") and f.endswith(".bend"):
        os.remove(os.path.join(HERE, f))

pairows = [(nm, a, b) for nm, a, b in FIX if b != 0]
zerorows = [(nm, a, b) for nm, a, b in FIX if b == 0]
# the zero-divisor rows ride in their OWN batch: upstream answers them by GUARDING,
# and a row whose expectation came from a guard must not sit silently beside 10 000
# ordinary rows -- they get their own main and their own `diverge` accounting.
BATCHES = [pairows[i:i + PER] for i in range(0, len(pairows), PER)] + [zerorows]
for bi, batch in enumerate(BATCHES):
    body = []
    for nm, a, b in batch:
        body.append(f'    drow("{nm}", {lits(a,b)})')
        body.append(f'    mrow("{nm}", {lits(a,b)})')
        body.append(f'    crow("{nm}", {lits(a,b)})')
        body.append(f'    krow("{nm}", {lits(a,b)})')
        body.append(f'    grow("{nm}", {lits(a,b)})')
    # the String lane rides in the FIRST batch only: it is one IO.print per row
    # and a row name cannot feed two, so it is its own `main`.
    if bi == 0:
        for x in DEC_X:
            ah, al = bend_i64(x)
            body.append(f'    trow("{x}", {ah}, {al})')
    open(os.path.join(HERE, f"gate{bi}.bend"), "w").write(
        HEADER + ACC + "\n" + "\n".join(body) + "\n")

# fixtures.tsv: row name -> its two operands. WITHOUT THIS the classifier has to
# re-parse the row name, and a name like `c_n0` or `p0_-1_-9223372036854775808`
# parses as nothing -- which silently turned 95 real int64.min rows into
# "without int64.min". Measured: that is how the first census of this defect
# under-counted its own population.
with open(os.path.join(HERE, "fixtures.tsv"), "w") as fh:
    for nm, a, b in FIX:
        fh.write(f"{nm}\t{a}\t{b}\n")
    for x in DEC_X:
        fh.write(f"@{x}\t{x}\t-\n")

open(os.path.join(HERE, "expected.txt"), "w").write("\n".join(sorted(EXP)) + "\n")
open(os.path.join(HERE, "wrap.txt"), "w").write("\n".join(sorted(WRAP)) + "\n")
open(os.path.join(HERE, "zero.txt"), "w").write("\n".join(sorted(ZERO_ROWS)) + "\n")
print(f"fixtures={len(FIX)} pair_rows={len(pairows)*5} dec_rows={len(DEC_X)} "
      f"rows_expected={len(EXP)} batches={len(BATCHES)} wrap_rows={len(WRAP)}")
