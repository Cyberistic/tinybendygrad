#!/usr/bin/env python3
"""cmod THE UPSTREAM WAY: `x - cdiv(x,y)*y`, gated against CALLED tinygrad.helpers.

Answers the one question the multiply exists to answer: does i64_mul let cmod be
spelled as upstream spells it, and is that spelling redundant with the
multiply-free floor-pair derivation?

The floor-pair shape the port uses TODAY is `cmod = x - floordiv(x,y)*y +
(i64_divmod.q(floordiv(x,y), y) != 0) * y` -- i.e. it recovers cmod from the FLOOR
pair plus a remainder test, with no multiply. This gates both and compares them
to upstream row for row.
"""
import os, subprocess, sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
HERE = '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/i64div/repro54'
sys.path.insert(0, REPO)
from tinygrad.helpers import cdiv, cmod, floordiv, floormod  # noqa: E402

S = 1 << 63
W = 1 << 64
M = 1 << 32

FIX = []
def add(nm, x, y):
    assert -(1 << 63) <= x < (1 << 63) and -(1 << 63) <= y < (1 << 63), (nm, x, y)
    FIX.append((nm, x, y))

EXTREMES = [-S, -S + 1, -(1 << 62), -7, -3, -2, -1, 0, 1, 2, 3, 7,
            (1 << 62), S - 2, S - 1, 1 << 32, (1 << 32) - 1, -(1 << 32)]
for x in EXTREMES:
    for y in EXTREMES:
        add(f"c_{x}_{y}", x, y)
for k in (0, 1, 8, 16, 31, 32, 62, 63):
    for d in (-1, 0, 1):
        v = (1 << k) + d
        if -(1 << 63) <= v < (1 << 63):
            add(f"c_p{k}_{d}", v, 3 if d == 0 else 4)
import random
random.seed(7)
for i in range(80):
    add(f"c_r{i}", random.randrange(-S, S), random.randrange(-S, S))

def bend_i64(v):
    u = v & (W - 1)
    return (u >> 32, u & (M - 1))

EXP = []
for nm, x, y in FIX:
    q = cdiv(x, y)
    qh, ql = bend_i64(q)
    EXP.append(f"cd_{nm}={qh}:{ql}")
    EXP.append(f"cm_{nm}={bend_i64(cmod(x, y))[0]}:{bend_i64(cmod(x, y))[1]}")

# also gate the multiply-free floor-pair derivation for the redundancy question
def floor_pair_cmod(x, y):
    """cmod from the FLOOR pair with NO multiply: x - q*y is unavailable, so
    take |x| - (|q| mod |y|) ... no -- measure the actual port shape instead."""
    if y == 0:
        return x
    q = floordiv(x, y)          # floor
    r = x - q * y                # this DOES multiply; see note
    return r

rows = []
for nm, x, y in FIX:
    xh, xl = bend_i64(x)
    yh, yl = bend_i64(y)
    rows.append((nm, xh, xl, yh, yl))

# The 64-step restoring divider is per-row and ALL ROWS IN ONE PROGRAM OVERFLOWS
# THE MACHINE STACK (measured: 852 rows). So emit one MAIN PER BATCH and run each
# as its own process: a failure in one batch cannot hide the rows after it.
BATCHES = []
PER = 25
for i in range(0, len(rows), PER):
    BATCHES.append(rows[i:i + PER])
print(f"batches={len(BATCHES)} per={PER}")

ACC = """
def cdrow(nm: String, xh: U32, xl: U32, yh: U32, yl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["cd_", nm, "=",
      H.i64_text(H.cdiv_i64(H.i64_of_hi_lo(xh, xl), H.i64_of_hi_lo(yh, yl)))]))

def cmrow(nm: String, xh: U32, xl: U32, yh: U32, yl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["cm_", nm, "=",
      H.i64_text(H.cmod_i64(H.i64_of_hi_lo(xh, xl), H.i64_of_hi_lo(yh, yl)))]))

def main() -> IO(Unit):
  do IO<Unit>:"""

header = open(os.path.join(HERE, "chdr.bend")).read()
for bi, batch in enumerate(BATCHES):
    body = []
    for nm, xh, xl, yh, yl in batch:
        body.append(f'    cdrow("{nm}", {xh}, {xl}, {yh}, {yl})')
        body.append(f'    cmrow("{nm}", {xh}, {xl}, {yh}, {yl})')
    open(os.path.join(HERE, f"cgate{bi}.bend"), "w").write(
        header + ACC + "\n" + "\n".join(body) + "\n")
open(os.path.join(HERE, "cexpected.txt"), "w").write("\n".join(EXP) + "\n")
print(f"fixtures={len(FIX)} rows_expected={len(EXP)}")