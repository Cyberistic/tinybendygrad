# shl.bend -- the .bend driver for `gates/i64-shl-gate.py`.
#
#   I64SHL_SEED=7 .venv/bin/python gates/i64-shl-gate.py
#
# THE QUESTION THIS FILE EXISTS TO SETTLE. `i64_shl` takes a `+k: Nat`
# (`tinybendygrad/helpers.bend:1819`), and a wall records that "a runtime shift amount
# cannot be a `Nat`". Every row here is reached through `H.`, so a mutation of
# helpers.bend moves them; this file defines no `I64` arithmetic of its own and
# `rg '^def (i64_|hi32|lo32)'` over it must find nothing.
#
# TWO ROUTES TO THE SAME `i64_shl`, ONE LITERAL AND ONE RUNTIME, ON EVERY ROW. That
# pairing IS the test. `_lit` passes the amount as a `Nat` literal; `_rt` passes
# `U32.to_nat` of a `U32` read out of a table at an index computed from the PROCESS
# ENVIRONMENT (`H.getenv_int`, helpers.bend:298, itself `IO.get_env`). The amount is
# therefore not in this file's text at all, which is the shape
# `uop/fold.bend:3234 bnd.pw2` uses (`U32.to_nat(U32.sub(bits, 1))`, `bits` a runtime
# `U32` parameter) and `codegen/decomp/dtype.bend:1604` uses (`U32.to_nat(j)`). So
# `_amt` is printed as a ROW, which is what makes a drifting amount a diff on the
# input rather than a silent wrong answer.
#
# THE VALUE SET IS THE UNIVERSE, and it is chosen so the rows CAN see the defect.
# A set of small values cannot: for both words below 2**32 the high arm and the low
# arm of the shift agree, so every such row is blind to the one place `i64_shl` can go
# wrong (`helpers.bend:1801-1804`, "FOR `k >= 32` THE HIGH WORD COMES FROM `lo` AND
# ONLY FROM `lo`").
#   neg1  -1. The only value whose `k = 63` row still holds a nonzero pair, so it is
#          the row that separates `63` from `64`.
#   one    1. The case helpers.bend:1803-1804 names verbatim for the high arm.
#   lowhi  0x0000_0001_9abc_def0. Both words NONZERO and different, so for `k` in
#          `1..30` the high arm and the spill out of the low word both contribute, and
#          for `k >= 32` only the low word may. Its magnitude is 33 bits, so its own
#          signed-range boundary is `k = 31`, and the amounts include 31/32/33.
import Base
import ./../../../tinybendygrad/helpers.bend as H

def p(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def pu(+nm: String, v: U32) -> IO(Unit):
  p(nm, U32.show(v))

def lit64(hi: U32, lo: U32) -> H.I64:
  H.i64_of_hi_lo(hi, lo)

# ---- the amount table, and the RUNTIME index into it ----------------------
#
# TEN AMOUNTS, and each is a boundary rather than a sample. `0` is one of the two
# amounts where the low form and the high form MEET (helpers.bend:1797-1799), so the
# pick's two arms must agree there. `31` is the last amount `U32.shln`'s saturation
# does not eat. `32` is the OTHER meeting amount and the edge of the `k <= 32` test.
# `33` is the first amount the high arm serves. `62` and `63` are the widest in-range
# amounts, and `63` is the widest a signed 64-bit pair can express at all. `64` is
# `2**64` -- THE WALL'S AMOUNT, which no 64-bit pair holds. `65` is past it. `127` is
# far enough past 64 that a `& 63` CLAMP would also answer 0, so `127` is the row that
# tells "wraps to zero" apart from "clamps to a bit width", which `64` alone cannot.
def amounts() -> List<&2, U32>:
  [0, 1, 31, 32, 33, 62, 63, 64, 65, 127]

def amt_len() -> U32:
  U32.from_nat(List.length(&2, U32, amounts()))

# THE INDEX IS `(seed + i) mod len`, so a permutation of the table rather than a walk
# of it: ten rows reach all ten amounts with any seed, and changing the seed changes
# which amount each row carries -- which is what makes the seed a fixture rather than
# decoration.
def amt_index(seed: U32, i: U32) -> U32:
  U32.mod(U32.add(seed, i), amt_len())

def amt_rt(seed: U32, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, amounts(), U32.to_nat(amt_index(seed, i))), 999)

def amt_lit(i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, amounts(), U32.to_nat(i)), 999)

# ---- one row: the value, BOTH amounts, and BOTH answers -------------------
#
# `hi`/`lo` rather than a decimal because `2**63` has no `U32` image and
# `H.i64_text` prints the two halves (helpers.bend:1698-1700): a decimal fixture would
# have to be transcribed on one side and derived on the other.
def shift_go(seed: U32, +nm: String, xh: U32, xl: U32, +i: U32) -> IO(Unit):
  +x = lit64(xh, xl)
  +kr = amt_rt(seed, i)
  +kl = amt_lit(i)
  do IO<Unit>:
    p(String.concat([nm, "_x"]), H.i64_text(x))
    pu(String.concat([nm, "_amt"]), kr)
    pu(String.concat([nm, "_lit"]), kl)
    p(String.concat([nm, "_rt"]), H.i64_text(H.i64_shl(x, U32.to_nat(kr))))
    p(String.concat([nm, "_lc"]), H.i64_text(H.i64_shl(x, U32.to_nat(kl))))

def v_neg1(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sh_neg1_0", 4294967295, 4294967295, 0)
    shift_go(seed, "sh_neg1_1", 4294967295, 4294967295, 1)
    shift_go(seed, "sh_neg1_2", 4294967295, 4294967295, 2)
    shift_go(seed, "sh_neg1_3", 4294967295, 4294967295, 3)
    shift_go(seed, "sh_neg1_4", 4294967295, 4294967295, 4)
    shift_go(seed, "sh_neg1_5", 4294967295, 4294967295, 5)
    shift_go(seed, "sh_neg1_6", 4294967295, 4294967295, 6)
    shift_go(seed, "sh_neg1_7", 4294967295, 4294967295, 7)
    shift_go(seed, "sh_neg1_8", 4294967295, 4294967295, 8)
    shift_go(seed, "sh_neg1_9", 4294967295, 4294967295, 9)

def v_one(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sh_one_0", 0, 1, 0)
    shift_go(seed, "sh_one_1", 0, 1, 1)
    shift_go(seed, "sh_one_2", 0, 1, 2)
    shift_go(seed, "sh_one_3", 0, 1, 3)
    shift_go(seed, "sh_one_4", 0, 1, 4)
    shift_go(seed, "sh_one_5", 0, 1, 5)
    shift_go(seed, "sh_one_6", 0, 1, 6)
    shift_go(seed, "sh_one_7", 0, 1, 7)
    shift_go(seed, "sh_one_8", 0, 1, 8)
    shift_go(seed, "sh_one_9", 0, 1, 9)

def v_lowhi(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sh_lowhi_0", 1, 2596069104, 0)
    shift_go(seed, "sh_lowhi_1", 1, 2596069104, 1)
    shift_go(seed, "sh_lowhi_2", 1, 2596069104, 2)
    shift_go(seed, "sh_lowhi_3", 1, 2596069104, 3)
    shift_go(seed, "sh_lowhi_4", 1, 2596069104, 4)
    shift_go(seed, "sh_lowhi_5", 1, 2596069104, 5)
    shift_go(seed, "sh_lowhi_6", 1, 2596069104, 6)
    shift_go(seed, "sh_lowhi_7", 1, 2596069104, 7)
    shift_go(seed, "sh_lowhi_8", 1, 2596069104, 8)
    shift_go(seed, "sh_lowhi_9", 1, 2596069104, 9)

def main() -> IO(Unit):
  do IO<Unit>:
    +seed : U32 <- H.getenv_int("I64SHL_SEED", 7)
    pu("seed", seed)
    v_neg1(seed)
    v_one(seed)
    v_lowhi(seed)