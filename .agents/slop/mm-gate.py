#!/usr/bin/env python
# mm-gate.py -- the CPython oracle for the `_min_max` ARITHMETIC CORE, which is the
# part of ops.py:1104 that is pure unsigned-64 magnitude arithmetic plus a sign bit.
#
# NOTHING HERE IS TRANSCRIBED. Every fixture is a pair of Python ints; the Bend call
# is GENERATED from them (`hi(a), lo(a)`) and the expectation is COMPUTED by CPython
# from the same pair. So a fixture cannot be right on one lane and wrong on the
# other, and the whole gate is two invocations and a diff:
#
#     .venv/bin/python .agents/slop/mm-gate.py --emit-bend > $OUT/mm-rows.bend
#     .venv/bin/python .agents/slop/mm-gate.py                 > $OUT/py.txt
#     ./bin/bend tinybendygrad/uop/probe-mmcore.bend            > $OUT/bend.txt
#     diff $OUT/py.txt $OUT/bend.txt
#
# `--emit-bend` prints the gate rows, so the ROWS THEMSELVES are CPython output and
# not something a human typed into a file. That is the form the "two transcriptions
# of the same table that agree is strong evidence" rule (bend2-constraints, the
# schedule-multi note) reduces to when there is only one transcription left to make.
import sys

M64 = (1 << 64) - 1


def pair(v):
  return f"{v >> 32}:{v & 0xFFFFFFFF}"


def w(v):
  """CPython's arbitrary-precision int in the port's window, or None for OVER."""
  return None if v < 0 or v > M64 else v


# ---------------------------------------------------------------------------
# THE FIXTURES. `a`, `b` are the 64-bit operands; `k` is the shift amount. The sign
# cases matter and they are separate rows because ONE row cannot see both: the ADD
# overflow test and the SUB underflow test are different predicates, the 32x32 limb
# product overflows at 2**32 and not at 2**31, and `shl` overflows one step before
# `mul` does.
# ---------------------------------------------------------------------------
ADD = [
  ("add_zero",    0, 0),
  ("add_small",   5, 7),
  ("add_carrylo", 2**32 - 1, 1),
  ("add_carryhi", 1, 2**32 - 1),
  ("add_hilo",    2**32, 2**32 - 1),
  ("add_over64",  2**32, M64),
  ("add_maxmax",  M64, M64),
  ("add_2p31",    2**31, 2**31),
]
SUB = [
  ("sub_ok",      7, 5),
  ("sub_zero",    5, 5),
  ("sub_borrow",  5, 7),
  ("sub_borrowhi", 2**32, 1),
  ("sub_under64", 0, 2**32),
  ("sub_tomax",   0, 1),
  ("sub_maxmax",  M64, M64),
]
MUL = [
  ("mul_small",   100000, 100000),
  ("mul_16sq",    65535, 65535),
  ("mul_31sq",    2**31 - 1, 2**31 - 1),
  ("mul_32sq",    2**32 - 1, 2**32 - 1),
  ("mul_2p32sq",  2**32, 2**32),
  ("mul_over64",  2**32 - 1, 2**32),
  ("mul_maxsq",   M64, M64),
  ("mul_1e12",    10**6, 10**6),
  ("mul_6x",      6, 715827883),
  ("mul_zero",    0, 2**32 - 1),
  ("mul_2p63",    2**32, 2**31),
  ("mul_2p32m",   2**32 - 1, 2**32 - 1),
  ("mul_2p48sq",  2**48, 2**48),
  ("mul_2p47sq",  2**47, 2**47),
]
SHL = [
  ("shl_0",       1, 0),
  ("shl_1",       1, 1),
  ("shl_31",      1, 31),
  ("shl_32",      1, 32),
  ("shl_63",      1, 63),
  ("shl_64",      1, 64),
  ("shl_hi1",     2**32, 1),
  ("shl_hi32",    2**32, 32),
  ("shl_hi63",    2**32, 63),
  ("shl_over63",  M64, 1),
  ("shl_over32",  M64, 32),
  ("shl_edge32",  2**32, 32),
  ("shl_max32",   2**32 - 1, 32),
  ("shl_max31",   2**32 - 1, 31),
  ("shl_max63",   2**32 - 1, 63),
  ("shl_0hi",     2**32, 0),
  ("shl_bigk",    2**32, 100),
]
SHR = [
  ("shr_0",       2**32 + 5, 0),
  ("shr_1",       2**32 + 5, 1),
  ("shr_31",      2**32 - 1, 31),
  ("shr_32",      2**32, 32),
  ("shr_63",      2**32, 63),
  ("shr_64",      2**32, 64),
  ("shr_max",     M64, 1),
  ("shr_max40",   M64, 40),
  ("shr_bigk",    M64, 100),
]
DIV = [
  ("div_17_5",    17, 5),
  ("div_17_1",    17, 1),
  ("div_2p32_3",  2**32, 3),
  ("div_7_2p32",  7, 2**32),
  ("div_maxmax",  M64, M64),
  ("div_max_2p32m", M64, 2**32 - 1),
  ("div_2p32m_x", 2**32 - 1, 715827883),
  ("div_max_2p32", M64, 2**32),
  ("div_2p33_7",  2**32 + 5, 7),
  ("div_max_p1",  M64, 1),
  ("div_100_7",   100, 7),
  ("div_max_3",   M64, 3),
  ("div_2p32_2p32m", 2**32, 2**32 - 1),
  ("div_max_2",   M64, 2),
  ("div_1_2",     1, 2),
  ("div_2p63_max", 2**63, M64),
  ("div_2p63_2p62", 2**63, 2**62),
]


def call(fn, a, b):
  return f"{fn}({a >> 32}, {a & 0xFFFFFFFF}, {b >> 32}, {b & 0xFFFFFFFF})"


def emit_bend():
  for name, a, b in ADD:
    print(f'    mm_row("{name}", mm_show(u64.add({a >> 32}, {a & 0xFFFFFFFF}, {b >> 32}, {b & 0xFFFFFFFF})))')
  for name, a, b in SUB:
    print(f'    mm_row("{name}", mm_show(u64.sub({a >> 32}, {a & 0xFFFFFFFF}, {b >> 32}, {b & 0xFFFFFFFF})))')
  for name, a, b in MUL:
    print(f'    mm_row("{name}", mm_show(u64.mul({a >> 32}, {a & 0xFFFFFFFF}, {b >> 32}, {b & 0xFFFFFFFF})))')
  for name, a, k in SHL:
    print(f'    mm_row("{name}", mm_show(u64.shl({a >> 32}, {a & 0xFFFFFFFF}, {k}n)))')
  for name, a, k in SHR:
    print(f'    mm_row("{name}", H.i64_text(u64.shr({a >> 32}, {a & 0xFFFFFFFF}, {k}n)))')
  for name, a, b in DIV:
    print(f'    mm_row("{name}", dm_show(dm_run({a >> 32}, {a & 0xFFFFFFFF}, {b >> 32}, {b & 0xFFFFFFFF})))')


def emit_py():
  for name, a, b in ADD:
    print(f"mm_{name} {'OVER' if w(a + b) is None else pair(a + b)}")
  for name, a, b in SUB:
    print(f"mm_{name} {'OVER' if w(a - b) is None else pair(a - b)}")
  for name, a, b in MUL:
    print(f"mm_{name} {'OVER' if w(a * b) is None else pair(a * b)}")
  for name, a, k in SHL:
    print(f"mm_{name} {'OVER' if w(a << k) is None else pair(a << k)}")
  for name, a, k in SHR:
    print(f"mm_{name} {pair(a >> k)}")
  for name, a, b in DIV:
    q, r = divmod(a, b)
    print(f"mm_{name} q={pair(q)} r={pair(r)}")


if __name__ == "__main__":
  emit_bend() if "--emit-bend" in sys.argv else emit_py()