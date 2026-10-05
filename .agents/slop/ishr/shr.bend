# shr.bend -- the .bend driver for `gates/i64-shr-gate.py`.
#
#   I64SHR_SEED=7 .venv/bin/python gates/i64-shr-gate.py
#
# `def i64_shr` EXISTS NOWHERE -- `grep -c '^def i64_shr' tinybendygrad/helpers.bend` is
# 0 -- while its mirror `def i64_shl(+x: I64, +k: Nat) -> I64` is at `tinybendygrad/
# helpers.bend:1819`. `mixin/dtype.bend:58` records the pair as one row, `SHL/SHR ->
# NOWHERE`, so the row is half dead. This file is the rows for the half that is open.
#
# EVERY ROW IS REACHED THROUGH `H.`, so a mutation of the def moves them; this file
# defines no `I64` arithmetic of its own and `rg '^def (i64_shr|hi32|lo32|match_hi)'`
# over it must find nothing.
#
# TWO ROUTES TO THE SAME `i64_shr` ON EVERY ROW, ONE LITERAL AND ONE RUNTIME, and the
# pairing IS the test. `_amt`/`_lc` take the amount at the row's own slot, out of a table
# of ten `Nat` LITERALS; `_rt_amt`/`_rt` take the SAME amount out of the SAME table at an
# index computed from the PROCESS ENVIRONMENT. Both amounts are printed as ROWS, so a
# drifting amount is a diff on the input rather than a silent wrong answer -- and the
# amount is the argument that selects the two ARMS, so a folded amount would fold the arm
# too, which is the thing the runtime route exists to rule out.
#
# THE VALUE SET IS THE UNIVERSE, and it was chosen by asking which rows CAN see the
# defect -- and the answer is that a value's SIGN decides it, so the set is deliberately
# half negative. `i64_shr`'s three failure modes are the bits CROSSING the word boundary,
# the SIGN FILL, and an amount WRAPPED modulo 64; the fill is invisible on every
# non-negative value and the wrap is invisible on most negative ones. So:
#   spill  0x80000001_9ABCDEF1.  THE LOAD-BEARING VALUE. Its high word is NEGATIVE and
#          not 0xFFFFFFFF, and `bit 0` of BOTH words is set -- so at `k = 1` all four
#          terms of the small-amount arm are individually necessary and deleting any one
#          of them changes the answer: `lo' = (lo>>k)|(hi<<(32-k))`, `hi' = (hi>>k)|fill`.
#   neg1   -1.  Where arithmetic and logical differ MOST (`-1 >> 63` is -1, `-1 >>> 63` is
#          1), and the `k = 63` boundary row. It is BLIND TO THE AMOUNT WRAP: `x >> 0` is -1
#          and `x >> 64` is -1, so a `mod 64` amount is indistinguishable here.
#   signmin 0x8000000000000000.  The MIN, with `lo = 0`, so it is BLIND to both
#          cross-boundary terms -- a boundary row, not a coverage row.
#   max    0x7FFFFFFF_FFFFFFFF.  The MAX. Both words all ones with `bit 0` set, so every
#          cross-boundary term contributes at every `k <= 31`; and being NON-NEGATIVE its
#          fill is 0, which is what lets it catch an UNCONDITIONAL fill.
#   one    1.  THE ONLY VALUE THAT SEES THE AMOUNT WRAP at 64: past 63 the answer is 0 and
#          a `mod 64` amount would answer `x` itself.
#   zero   0.  Exact 0 at every amount, so it can never be evidence of anything.
import Base
import ./../../../tinybendygrad/helpers.bend as H

def p(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# ---- the amount table, and the TWO ROUTES INTO IT ---------------------------
#
# TEN AMOUNTS, each a boundary rather than a sample. `0` is the identity. `1` is where
# all four terms of the small-amount arm are load-bearing. `31` is the last amount at
# which `lo >> k` and `hi << (32-k)` are both still nonzero. `32` IS WHERE THE TWO FORMS
# MEET -- `Nat.sub(32n, 32n)` is 0, so the small arm's `hi << 0` is `hi` and the large
# arm's `hi >> 0` is also `hi` -- which is why the pick must be `k <= 32` and not `< 32`.
# `33` is the first amount only the large arm serves. `62`/`63` are the widest in range.
# `64` is `2**6`, past the width; `65` past it; `127` far enough past that a `& 63` WRAP
# would answer -1 for every negative value, so `127` is the row that tells "saturates to
# the sign" apart from "wraps", which `64` alone cannot -- for `neg1`, `signmin` and
# `spill` those are the same answer and only `one` and `max` separate them at 64/65.
def nats() -> List<&2, Nat>:
  [0n, 1n, 31n, 32n, 33n, 62n, 63n, 64n, 65n, 127n]

# THE CONTROL. The index is the row's own slot, so the `Nat` comes straight out of the
# table with nothing computed -- a shift amount that is a LITERAL.
def amt_lit(i: U32) -> Nat:
  Maybe.default(&2, Nat, List.get(&2, Nat, nats(), U32.to_nat(i)), 999n)

# THE CLAIM UNDER TEST. Same table, but the index is `(seed + i) mod 10` and `seed` is
# read from the PROCESS ENVIRONMENT (`H.getenv_int`), so the `Nat` handed to `i64_shr` is
# derived from runtime data and is nowhere in this file's text -- the shape of
# `uop/fold.bend:3234 bnd.pw2`. `(seed + i) mod len` is a PERMUTATION, so with any seed
# the ten rows reach all ten amounts and changing the seed changes which amount each row
# carries, which is what makes the seed a fixture rather than a constant.
def amt_rt(seed: U32, i: U32) -> Nat:
  Maybe.default(&2, Nat, List.get(&2, Nat, nats(), U32.to_nat(U32.mod(U32.add(seed, i), 10))), 999n)

# ---- one row: the value, and BOTH routes' amount and answer ----------------
#
# `hi`/`lo` rather than a decimal because `2**63` has no `U32` image and `H.i64_text`
# prints the two halves: a decimal fixture would have to be transcribed on one side and
# derived on the other.
def shift_go(seed: U32, +nm: String, xh: U32, xl: U32, +i: U32) -> IO(Unit):
  +x = H.i64_of_hi_lo(xh, xl)
  +kl = amt_lit(i)
  +kr = amt_rt(seed, i)
  do IO<Unit>:
    p(String.concat([nm, "_x"]), H.i64_text(x))
    p(String.concat([nm, "_amt"]), Nat.show(kl))
    p(String.concat([nm, "_lc"]), H.i64_text(H.i64_shr(x, kl)))
    p(String.concat([nm, "_rt_amt"]), Nat.show(kr))
    p(String.concat([nm, "_rt"]), H.i64_text(H.i64_shr(x, kr)))

# ---- the six values, TEN AMOUNTS EACH ---------------------------------------
#
# `hi`/`lo` are DECIMAL `U32`s because a decimal fixture transcribed on one side and
# derived on the other is exactly the constant that is wrong and green; every value's hex
# reading is in its comment and in the oracle's table, which is the place that has to
# agree with it.
def v_neg1(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_neg1_0", 4294967295, 4294967295, 0)
    shift_go(seed, "sr_neg1_1", 4294967295, 4294967295, 1)
    shift_go(seed, "sr_neg1_2", 4294967295, 4294967295, 2)
    shift_go(seed, "sr_neg1_3", 4294967295, 4294967295, 3)
    shift_go(seed, "sr_neg1_4", 4294967295, 4294967295, 4)
    shift_go(seed, "sr_neg1_5", 4294967295, 4294967295, 5)
    shift_go(seed, "sr_neg1_6", 4294967295, 4294967295, 6)
    shift_go(seed, "sr_neg1_7", 4294967295, 4294967295, 7)
    shift_go(seed, "sr_neg1_8", 4294967295, 4294967295, 8)
    shift_go(seed, "sr_neg1_9", 4294967295, 4294967295, 9)

def v_zero(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_zero_0", 0, 0, 0)
    shift_go(seed, "sr_zero_1", 0, 0, 1)
    shift_go(seed, "sr_zero_2", 0, 0, 2)
    shift_go(seed, "sr_zero_3", 0, 0, 3)
    shift_go(seed, "sr_zero_4", 0, 0, 4)
    shift_go(seed, "sr_zero_5", 0, 0, 5)
    shift_go(seed, "sr_zero_6", 0, 0, 6)
    shift_go(seed, "sr_zero_7", 0, 0, 7)
    shift_go(seed, "sr_zero_8", 0, 0, 8)
    shift_go(seed, "sr_zero_9", 0, 0, 9)

def v_one(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_one_0", 0, 1, 0)
    shift_go(seed, "sr_one_1", 0, 1, 1)
    shift_go(seed, "sr_one_2", 0, 1, 2)
    shift_go(seed, "sr_one_3", 0, 1, 3)
    shift_go(seed, "sr_one_4", 0, 1, 4)
    shift_go(seed, "sr_one_5", 0, 1, 5)
    shift_go(seed, "sr_one_6", 0, 1, 6)
    shift_go(seed, "sr_one_7", 0, 1, 7)
    shift_go(seed, "sr_one_8", 0, 1, 8)
    shift_go(seed, "sr_one_9", 0, 1, 9)

def v_signmin(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_signmin_0", 2147483648, 0, 0)
    shift_go(seed, "sr_signmin_1", 2147483648, 0, 1)
    shift_go(seed, "sr_signmin_2", 2147483648, 0, 2)
    shift_go(seed, "sr_signmin_3", 2147483648, 0, 3)
    shift_go(seed, "sr_signmin_4", 2147483648, 0, 4)
    shift_go(seed, "sr_signmin_5", 2147483648, 0, 5)
    shift_go(seed, "sr_signmin_6", 2147483648, 0, 6)
    shift_go(seed, "sr_signmin_7", 2147483648, 0, 7)
    shift_go(seed, "sr_signmin_8", 2147483648, 0, 8)
    shift_go(seed, "sr_signmin_9", 2147483648, 0, 9)

def v_max(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_max_0", 2147483647, 4294967295, 0)
    shift_go(seed, "sr_max_1", 2147483647, 4294967295, 1)
    shift_go(seed, "sr_max_2", 2147483647, 4294967295, 2)
    shift_go(seed, "sr_max_3", 2147483647, 4294967295, 3)
    shift_go(seed, "sr_max_4", 2147483647, 4294967295, 4)
    shift_go(seed, "sr_max_5", 2147483647, 4294967295, 5)
    shift_go(seed, "sr_max_6", 2147483647, 4294967295, 6)
    shift_go(seed, "sr_max_7", 2147483647, 4294967295, 7)
    shift_go(seed, "sr_max_8", 2147483647, 4294967295, 8)
    shift_go(seed, "sr_max_9", 2147483647, 4294967295, 9)

def v_spill(+seed: U32) -> IO(Unit):
  do IO<Unit>:
    shift_go(seed, "sr_spill_0", 2147483649, 2596069105, 0)
    shift_go(seed, "sr_spill_1", 2147483649, 2596069105, 1)
    shift_go(seed, "sr_spill_2", 2147483649, 2596069105, 2)
    shift_go(seed, "sr_spill_3", 2147483649, 2596069105, 3)
    shift_go(seed, "sr_spill_4", 2147483649, 2596069105, 4)
    shift_go(seed, "sr_spill_5", 2147483649, 2596069105, 5)
    shift_go(seed, "sr_spill_6", 2147483649, 2596069105, 6)
    shift_go(seed, "sr_spill_7", 2147483649, 2596069105, 7)
    shift_go(seed, "sr_spill_8", 2147483649, 2596069105, 8)
    shift_go(seed, "sr_spill_9", 2147483649, 2596069105, 9)

def main() -> IO(Unit):
  do IO<Unit>:
    +seed : U32 <- H.getenv_int("I64SHR_SEED", 7)
    p("seed", U32.show(seed))
    v_neg1(seed)
    v_zero(seed)
    v_one(seed)
    v_signmin(seed)
    v_max(seed)
    v_spill(seed)