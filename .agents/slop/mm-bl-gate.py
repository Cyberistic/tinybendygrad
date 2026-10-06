#!/usr/bin/env python
# mm-bl-gate.py -- the CPython oracle for `int(x).bit_length()` over the port's
# SIGN-PLUS-UNSIGNED-64 window, and for the `Bound` type's four constructors.
#
# SAME ZERO-TRANSCRIPTION RULE AS mm-gate.py. Every fixture is ONE Python int; the
# Bend call is GENERATED from it as `hi(a), lo(a)` and the expectation is COMPUTED by
# CPython from the same int. So `bit_length` has no place for a second mistake to be
# made -- which is exactly the failure `nv/ip` shipped when a hand-tabulated oracle
# agreed with a swapped `Bool.pick` on all five rows.
#
#     .venv/bin/python .agents/slop/mm-bl-gate.py --emit-bend > $OUT/bl-rows.bend
#     .venv/bin/python .agents/slop/mm-bl-gate.py                 > $OUT/bl-py.txt
#     ./bin/bend tinybendygrad/uop/fold2_work.bend                  > $OUT/bl-bend.txt
#     diff $OUT/bl-py.txt $OUT/bl-bend.txt
import sys

M64 = (1 << 64) - 1


def w(v):
  """CPython's int inside the port's window, or None for OVER."""
  return None if v < 0 or v > M64 else v


# ---------------------------------------------------------------------------
# THE FIXTURES, and every one is a place the ladder can be WRONG rather than a
# place it is merely exercised:
#   * `bl_0` / `bl_1` -- zero has bit_length 0, and a ladder that ends on
#     "is the residue nonzero" without the 0 case answers 1.
#   * every power of two AND its neighbour -- the ladder's five thresholds are
#     2**16, 2**8, 2**4, 2**2, 2**1, so 65536/65535, 256/255, 16/15, 4/3 and 2/1
#     are the FIVE boundaries at which a `>=` and a `>` disagree. A ladder with
#     one `>` in it answers one of these wrong and nothing else.
#   * `bl_2p31` / `bl_2p32` -- the top of the low word and the bottom of the high,
#     which is where `bl64`'s `hi == 0` pick decides.
#   * the masking rows -- `M64 & mask` for each threshold, because the AND arm
#     APPLIES the mask and a bit_length that is one too large gives a different
#     integer rather than a different shape.
# ---------------------------------------------------------------------------
BL = [
  ("bl_0", 0),
  ("bl_1", 1),
  ("bl_2", 2),
  ("bl_3", 3),
  ("bl_4", 4),
  ("bl_5", 5),
  ("bl_15", 15),
  ("bl_16", 16),
  ("bl_255", 255),
  ("bl_256", 256),
  ("bl_65535", 65535),
  ("bl_65536", 65536),
  ("bl_2p24", 2**24),
  ("bl_2p31", 2**31),
  ("bl_2p31m1", 2**31 - 1),
  ("bl_2p32", 2**32),
  ("bl_2p32m1", 2**32 - 1),
  ("bl_2p32p1", 2**32 + 1),
  ("bl_2p48", 2**48),
  ("bl_2p48m1", 2**48 - 1),
  ("bl_2p63", 2**63),
  ("bl_2p63m1", 2**63 - 1),
  ("bl_max", M64),
  ("bl_maxm1", M64 - 1),
  ("bl_1000000", 10**6),
  ("bl_123456789", 123456789),
]

# `int(s1_vmax) & ((1 << int(s0_vmax).bit_length()) - 1)` -- ops.py:1110 verbatim.
# `s0` is the value whose bit_length is taken (it names the MASK WIDTH) and `s1` is the
# operand being masked, so the row answers a REAL INTEGER and not a shape. These are the
# rows that gate the AND arm rather than the counter, and they are why `bit_length` is
# worth a gate at all: a count one too large gives a mask one bit too wide, which is a
# different number rather than a different answer shape.
#
# `s1 = M64` against every threshold is the sharpest of these, because M64 has ALL bits
# set and so its bit_length is 64 -- the one case where `1 << k` leaves the window.
# Python's `(1 << 64) - 1` is 2**64-1, which is INSIDE the pair, so the port's mask must
# be all ones there rather than an overflow.
MASK = [
  ("mk_0_0", 0, 0),
  ("mk_5_255", 5, 255),
  ("mk_255_5", 255, 5),
  ("mk_256_256", 256, 256),
  ("mk_256_m1", 256, M64),
  ("mk_65535_m1", 65535, M64),
  ("mk_65536_m1", 65536, M64),
  ("mk_2p31m1_m1", 2**31 - 1, M64),
  ("mk_2p32_m1", 2**32, M64),
  ("mk_m1_m1", M64, M64),
  ("mk_m1_2p32", M64, 2**32),
  ("mk_7_2p63", 7, 2**63),
]


def call(fn, a):
  return f"{fn}({a >> 32}, {a & 0xFFFFFFFF})"


def emit_bend():
  for name, a in BL:
    print(f'    bl_row("{name}", U32.show(mm.bl64({a >> 32}, {a & 0xFFFFFFFF})))')
  for name, s0, s1 in MASK:
    print(f'    bl_row("{name}", mm_show(mm_mask64({s0 >> 32}, {s0 & 0xFFFFFFFF}, '
          f'{s1 >> 32}, {s1 & 0xFFFFFFFF})))')


def emit_py():
  for name, a in BL:
    print(f"bl_{name} {a.bit_length()}")
  for name, s0, s1 in MASK:
    print(f"bl_{name} {pair(s1 & ((1 << s0.bit_length()) - 1))}")


def pair(v):
  return f"{v >> 32}:{v & 0xFFFFFFFF}"


if __name__ == "__main__":
  emit_bend() if "--emit-bend" in sys.argv else emit_py()
