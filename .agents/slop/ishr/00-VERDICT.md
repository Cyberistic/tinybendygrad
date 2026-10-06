# `def i64_shr` — verdict

unit: one job. **STATUS: DONE. The def existed nowhere; it now exists and is gated.**

## SHORT FORM

`mixin/dtype.bend:58` records `SHL/SHR -> i64 shift -> NOWHERE` as one row. The `i64_shl`
half went stale last unit. **The `i64_shr` half was genuinely open and is now closed:**
`def i64_shr(+x: I64, +k: Nat) -> I64` at `tinybendygrad/helpers.bend:1873`, pure,
**301 rows / 3 lanes byte-identical** to a CPython oracle, 4 of 4 plants armed and
disarmed.

## THE THREE ANSWERS

1. **ARITHMETIC**, cited: `tinygrad/uop/ops.py:1429` (`Ops.SHR: operator.rshift`) and
   `tinygrad/codegen/decomp/dtype.py:48` (`fill = a1 >> 31 if dt == dtypes.int else zero
   # vacated high word: sign bits when signed, else 0`). Neither file is generated
   (`grep -c 'GENERATED\|autogen\|do not edit'` is 0 for both). The brief's framing —
   "depends on whether the caller wants arithmetic or logical" — is **not a real fork for an
   `int64`**: upstream SHR of a signed dtype sign-extends, full stop.
2. **THE SIGNATURE IS `(+x: I64, +k: Nat) -> I64`, NOT A `Maybe`.** Established with rows,
   not with an argument: `x >> k = floor(x / 2**k)`, so the magnitude never grows, and for
   `k >= 64` the answer is `-1` or `0` — **both ordinary signed words**. The brief's premise
   that a sign-extending SHR "loses the sign for `k >= 64`" is **false**: it *is* `-1`, and
   `-1` fits the carrier. So `i64_shr` is exact at **every** `Nat` amount for every
   `int64`. There is no width boundary and nothing to widen. The sibling's "wider carrier,
   not a `Maybe`" conclusion is right for `i64_shl` and **does not transfer** — and neither
   is needed here.
3. **THE UNIVERSE IS HALF NEGATIVE, AND THAT IS THE WHOLE FIXTURE SET.** The fill is `0` for
   every non-negative value, so `zero`/`one`/`max` cannot see a deleted sign fill at all
   (measured: plant P1 moves 18 rows, **none** of them on those three). `neg1` is all ones,
   so it cannot see a **wrapped** amount (P4 moves 12 rows, **none** on `neg1`). And **no
   row at all can see a wrap at `k = 127`**, for any value. The load-bearing fixture is
   `spill` = `0x80000001_9ABCDEF1`: negative high word, `!= 0xFFFFFFFF`, `bit 0` of both
   words set, so at `k = 1` all four terms are individually necessary.

## BOUNDARY, IN ONE LINE

`k = 32` is where the two arms meet (hence `k <= 32`, not `< 32`, and upstream's own
`dtype.py:49` picks on `b0 >= 32`). `k = 63` is where arithmetic and logical differ by a
sign bit (`neg1 >> 63` is `-1`; a logical shift reads `0:1`). `k >= 64` **saturates to the
sign** — `-1` for negative, `0` for non-negative — it does **not** wrap.

## NOT MINE, REPORTED, NOT TOUCHED

`mixin/dtype.bend:58` still says `NOWHERE` and is **now half stale**, like `:57` was.
`:52-53` (`i64_mul` "NOWHERE" — it is `helpers.bend:2206`), `:60`, `:54-57`/`:58-59` (the
`IO(..)` seams) are uncorrected. **No caller** for `i64_shr` exists yet; whether
`uop/fold.bend`'s `_min_max` can use it is `fold.bend`'s call. **No `i64_ushr`** for the
unsigned reading — judged unnecessary, and I did not measure a demand for it.
`gatekit.py`'s API moved under me mid-unit; I did not edit it and my gate resolves the
lane path and fails loudly rather than hard-coding it.

## `helpers.bend` WAS EDITED — the one file outside my own

125,668 B / `1c9f47b2…` → **130,719 B / `2f2cb93e…`**, **+76/−1**, one contiguous hunk right
after `i64_shl`, `import "` **0 before and after**. Hash taken before every edit and
verified in a `finally` (mismatch → exit 2). `checks/no-shrink.py`: 1 GREW, 0 SHRANK. I did
not observe the 0-byte truncation the brief warns about.

## RUN IT

    I64SHR_SEED=7 .venv/bin/python gates/i64-shr-gate.py   # rc 0, 301 rows, 3 lanes
    .venv/bin/python .agents/slop/ishr/plant.py             # rc 0, 4 of 4 armed+disarmed

Full report, boundary table with decimals, and the plant table:
**`.agents/slop/ishr/REPORT.md`**.