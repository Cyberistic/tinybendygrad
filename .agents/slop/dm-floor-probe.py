# The ORACLE for `.agents/slop/dm.bend`: the SAME rows, from CPython. The diff
# IS the test -- the gate is `.agents/slop/tools/dm-floor-gate.sh`, which runs
# `dm.bend` in both lanes, runs this, and compares the `ok_` rows.
#
# Every number comes out of `tinygrad.helpers` itself -- helpers.py:65-77 -- so
# this is not the port agreeing with itself. The `& 0xFFFFFFFF` is the only
# transformation: it puts a Python int into the bit pattern a U32 holds, so the
# two sides print in the same alphabet and the diff needs no sign convention.
# `-7` here and `4294967289` in `dm.bend` are the same row.
#
# The `bad_ceildiv_*` rows are EXPECTED to disagree, and that is the point: they
# are the gate naming the one remaining hole in this block -- `ceildiv_i32` is
# `-(floordiv(-num, -amt))` where helpers.py:68 says `-(num // -amt)`, so it
# negates BOTH operands. The gate fails on the `ok_` rows and only reports these.
import sys
sys.path.insert(0, '.')
from tinygrad.helpers import cdiv, cmod, floordiv, floormod, ceildiv, round_up, round_down

def emit(name, v):
  print(f"{name}={v & 0xFFFFFFFF}")

# exactly the rows `.agents/slop/dm.bend` prints, in the same order
M7, M4, M8 = 4294967289, 4294967292, 4294967288   # -7, -4, -10
CASES = [(6, 4), (10, 3), (1000, 7), (10, 7), (4, 4), (0, 7), (7, 0),
         (-7, 4), (7, -4), (-7, -4), (-4, 4), (-1, 2), (1, 2),
         (2147483647, 2), (-2147483648, 1)]

def nm(p, x, y):
  return f"{p}_{x & 0xFFFFFFFF}_{y & 0xFFFFFFFF}"

for x, y in CASES:
  emit(nm("ok_fd", x, y), floordiv(x, y))
for x, y in CASES:
  emit(nm("ok_fm", x, y), floormod(x, y))
for x, y in [(6, 4), (-7, 4), (7, -4), (-7, -4), (7, 0)]:
  emit(nm("ok_cd", x, y), cdiv(x, y))
for x, y in [(6, 4), (-7, 4), (7, -4), (7, 0)]:
  emit(nm("ok_cm", x, y), cmod(x, y))
for n, a in [(10, 4), (10, 3), (1000, 7), (-10, 4), (-7, 3)]:
  emit(f"ok_ru_{n & 0xFFFFFFFF}_{a}", round_up(n, a))
for n, a in [(10, 4), (-10, 4), (1000, 7)]:
  emit(f"ok_rd_{n & 0xFFFFFFFF}_{a}", round_down(n, a))
for n, a in [(10, 4), (10, 3), (1000, 7), (-10, 4)]:
  emit(f"bad_ceil_{n & 0xFFFFFFFF}_{a}", ceildiv(n, a))
