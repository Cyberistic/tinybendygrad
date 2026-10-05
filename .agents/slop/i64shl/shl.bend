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
# pairing IS the test. `_amt`/`_lc` take the amount as a `Nat` LITERAL out of a table;
# `_rt_amt`/`_rt` take the SAME amount out of the SAME table but at an index computed
# from the PROCESS ENVIRONMENT. So the amounts are one table of ten `Nat` literals, and
# the only difference between the two routes is whether the index is syntax or runtime
# data -- which is precisely what the wall's claim turns on. Both amounts are printed as
# ROWS, so a drifting amount is a diff on the input rather than a silent wrong answer.
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

# ---- the amount table, and the TWO ROUTES INTO IT ---------------------------
#
# TEN AMOUNTS, and each is a boundary rather than a sample. `0` is one of the two
# amounts where the low form and the high form MEET (helpers.bend:1797-1799), so the
# pick's two arms must agree there. `31` is the last amount `U32.shln`'s saturation
# does not eat. `32` is the OTHER meeting amount and the edge of the `k <= 32` test.
# `33` is the first amount the high arm serves. `62` and `63` are the widest in-range
# amounts, and `63` is the widest a SIGNED 64-bit pair can express at all. `64` is
# `2**64` -- THE WALL'S AMOUNT, which no 64-bit pair holds. `65` is past it. `127` is
# far enough past 64 that a `& 63` CLAMP would also answer 0, so `127` is the row that
# tells "wraps to zero" apart from "clamps to a bit width", which `64` alone cannot.
def nats() -> List<&2, Nat>:
  [0n, 1n, 31n, 32n, 33n, 62n, 63n, 64n, 65n, 127n]

# THE CONTROL. The index is the row's own slot, so the `Nat` comes straight out of the
# table with nothing computed -- this is a shift amount that is a LITERAL.
def amt_lit(i: U32) -> Nat:
  Maybe.default(&2, Nat, List.get(&2, Nat, nats(), U32.to_nat(i)), 999n)

# THE CLAIM UNDER TEST. Same table, same amounts, but the INDEX is
# `(seed + i) mod 10` and `seed` is read from the PROCESS ENVIRONMENT
# (`H.getenv_int`, helpers.bend:298, itself `IO.get_env`), so the `Nat` handed to
# `i64_shl` is derived from a runtime `U32` and is nowhere in this file's text. That is
# the shape of `uop/fold.bend:3234 bnd.pw2` (`U32.to_nat(U32.sub(bits, 1))`, `bits` a
# runtime `U32` parameter) and of `codegen/decomp/dtype.bend:1604` (`U32.to_nat(j)`).
#
# `(seed + i) mod len` is a PERMUTATION, so with any seed the ten rows reach all ten
# amounts and changing the seed changes which amount each row carries. That is what
# makes the seed a fixture: `seed` is printed as a ROW, so a drifting seed is a diff on
# the input rather than ten silently wrong answers.
def amt_rt(seed: U32, i: U32) -> Nat:
  Maybe.default(&2, Nat, List.get(&2, Nat, nats(), U32.to_nat(U32.mod(U32.add(seed, i), 10))), 999n)

# ---- one row: the value, and BOTH routes' amount and answer ----------------
#
# `hi`/`lo` rather than a decimal because `2**63` has no `U32` image and
# `H.i64_text` prints the two halves (helpers.bend:1698-1700): a decimal fixture would
# have to be transcribed on one side and derived on the other.
def shift_go(seed: U32, +nm: String, xh: U32, xl: U32, +i: U32) -> IO(Unit):
  +x = lit64(xh, xl)
  +kl = amt_lit(i)
  +kr = amt_rt(seed, i)
  do IO<Unit>:
    p(String.concat([nm, "_x"]), H.i64_text(x))
    p(String.concat([nm, "_amt"]), Nat.show(kl))
    p(String.concat([nm, "_lc"]), H.i64_text(H.i64_shl(x, kl)))
    p(String.concat([nm, "_rt_amt"]), Nat.show(kr))
    p(String.concat([nm, "_rt"]), H.i64_text(H.i64_shl(x, kr)))

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