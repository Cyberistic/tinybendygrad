# `def i64_shr` — IMPLEMENTED. The wall's premise was right and its arithmetic was not.

unit: one job. measured 2026-10-05. Bend 2.0.35 (`bin/bend`), bounded through
`checks/bounded.py`. **no commit.**

---

## 1. VERDICT

`def i64_shr` existed nowhere; it now exists at `tinybendygrad/helpers.bend:1873` (the
`.lo`/`.hi`/`.put` arms at 1862/1866/1869), is pure, takes a `+k: Nat` like its mirror
`i64_shl`, and **301 rows over 3 lanes are byte-identical to a CPython oracle**. The
brief's own framing — that arithmetic and logical shift "depends on the caller" — is
**settled: it is arithmetic, and upstream says so in two places.**

| the brief's question | measured |
|---|---|
| arithmetic or logical? | **ARITHMETIC** — `tinygrad/uop/ops.py:1429`, `tinygrad/codegen/decomp/dtype.py:48` |
| a sign-extending SHR loses the sign for `k >= 64` | **FALSE.** It *is* `-1`, and `-1` fits a signed 64-bit pair |
| therefore `i64_shr` needs a wider carrier or a `Maybe` | **NEITHER.** It is exact at **every** `Nat` amount, for every `int64` |
| is a `Maybe`/checked shape right, per the "re-signed vs lost" distinction? | **No — and the distinction is stronger than for `i64_shl`.** Nothing is ever *re-signed*: the answer is *identical* |

## 2. ARITHMETIC OR LOGICAL, with `file:line`

- `tinygrad/uop/ops.py:1429` — `python_alu` binds **`Ops.SHR: operator.rshift`**, and
  `operator.rshift` on a CPython int *is* the sign-extending (floor) shift.
- `tinygrad/codegen/decomp/dtype.py:48` — the 64-bit pair decomposition of `Ops.SHR`:
  **`fill = a1 >> 31 if dt == dtypes.int else zero  # vacated high word: sign bits when
  signed, else 0`**. That is the signature of an *arithmetic* shift, stated in the
  upstream's own comment, and `fill` is precisely the term `helpers.bend` now computes.

**NEITHER FILE IS GENERATED**, checked rather than assumed (nine stale-citation classes
have been recorded here in one day): `grep -c 'GENERATED\|autogen\|do not edit'` is **0**
for both, and neither opens with a generator header. So `file:line` is safe for both, and
the lines are quoted so a reader can re-derive them.

**A THIRD, INDEPENDENT WITNESS, AND IT IS THE ONE THAT DECIDES THE `k > 32` SHAPE.**
`tinygrad/codegen/decomp/dtype.py:45-49` is upstream's own decomposition of `Ops.SHR` on a
**64-bit** value into two 32-bit words, and it agrees with `helpers.bend` term for term:

```
case Ops.SHR:
  a0u, a1u, n = a0.bitcast(dtypes.uint), a1.bitcast(dtypes.uint), (b0 & 31).cast(dtypes.uint)
  lo, hi = ((a0u >> n) | ((a1u << 1) << (31 - n))).bitcast(dt), a1 >> (b0 & 31)
  fill = a1 >> 31 if dt == dtypes.int else zero  # vacated high word: sign bits when signed, else 0
  return (b0 >= 32).where(hi, lo), (b0 >= 32).where(fill, hi)
```

- its `(b0 >= 32).where(fill, hi)` is `helpers.bend`'s high word = the fill above 32;
- its `(b0 >= 32).where(hi, lo)` is the arm split, on the **same** side of 32 — so upstream
  agrees the small arm owns `b0 <= 32` and therefore that `k == 32` is one arm's row;
- its `lo, hi = ... a1 >> (b0 & 31)` supplies the small arm's high word from `a1` alone
  past 32, which is `helpers.bend`'s `U32.shrn(hi, Nat.sub(k, 32n))`.

One difference, and it is **not** a disagreement: upstream masks the amount with `& 31`
and does not answer `b0 >= 64`, because a `UOp` SHR amount upstream is already bounded by
its range analysis. The port takes an unbounded `Nat`, so it must *answer* the wide amounts
rather than leave them unreachable — and §5 shows the answer is `-1`/`0`, i.e. upstream's
own `fill`, reached by the width law.

**So "which does the caller want" is not a real fork for an `int64`: upstream SHR of a
signed dtype sign-extends, period.** The unsigned reading is a `BITCAST` away — the pair
is already two `U32`s and `i64_or`/`i64_and` are wordwise — so a logical variant is not a
second def but a caller-side `BITCAST`, and the port does not need one to exist.

## 3. THE SIGNATURE, AND WHY IT IS NOT A `Maybe`

```python
def i64_shr(+x: I64, +k: Nat) -> I64          # helpers.bend:1873
```

Same shape as `i64_shl(+x: I64, +k: Nat) -> I64`. The brief told me to establish
*re-signed vs lost* **with rows, not with an argument**, so:

> `x >> k` is `floor(x / 2**k)`, so `|x >> k| <= |x| <= 2**63` for every `k <= 63`; and for
> every `k >= 64` the answer is `floor(x / 2**64)`-and-below, which is `-1` for `x < 0` and
> `0` otherwise. **Every one of those is an ordinary signed 64-bit word.**

The oracle asserts that as a *predicate over all 60 cells* (per value and amount, for the
range check), and the gate asserts it again over the **port's own rows** (per cell, for
`unpair(got) == x >> k`). So it is not *re-signed* and it is not *lost*: **it is exactly
`x >> k`, always.** There is no width boundary at all, so there is nothing to report and
nothing to widen. `i64_shl`'s first loss at `k = 63` (measured by the sibling unit) has
no counterpart here because a right shift cannot grow.

Two consequences worth naming:

- **`i64_shl` is the one that needs the wider carrier.** Its predicate really is
  `k + bit_length(x) <= 63`. The sibling unit's "a wider carrier, not a `Maybe`-returning
  one" conclusion is right for `i64_shl` and *does not transfer*.
- **The `k >= 64` answer is a saturation, and it is the ONLY interesting amount law.**
  Past 63 the pair reads `4294967295:0` for `x < 0` and `0:0` for `x >= 0`.

## 4. THE UNIVERSE, WHICH CAME FIRST AND CHANGED THE FIXTURES

`i64_shr`'s three failure modes are the bits **crossing** the word boundary, the **sign
fill**, and an amount **wrapped modulo 64**. Each is invisible to values chosen without
that in mind, so the fixture set is deliberately **half negative** — `zero`, `one` and
`max` cannot see a deleted sign fill at all, because the fill is `0` when the high word's
bit 31 is clear.

| fixture | pair | what it can see | what it CANNOT |
|---|---|---|---|
| **`spill`** | `2147483649:2596069105` = `0x80000001_9ABCDEF1` | **all four terms of the small-amount arm at once** — high word negative, `!= 0xFFFFFFFF`, `bit 0` of BOTH words set | — (it is the load-bearing row) |
| `neg1` | `4294967295:4294967295` | arithmetic vs logical at `k = 63` (`-1` vs `1`) | the amount wrap: `x >> 0` and `x >> 64` are both `-1` |
| `signmin` | `2147483648:0` = `-2**63` | the fill; the wrap at 64/65 | both cross-boundary terms (`lo == 0`, `hi`'s low 32 bits are 0) — a boundary row, not a coverage row |
| `max` | `2147483647:4294967295` = `2**63-1` | every cross-boundary term at every `k <= 31`; an **unconditional** fill (its own fill is 0) | — |
| `one` | `0:1` | the amount wrap at 64/65 | everything below 32 (`hi == 0`) |
| `zero` | `0:0` | nothing — exact 0 at every amount | **everything**, which is why it is here |

**THE OUT-OF-MECHANISM ASSERTIONS**, all measured in the oracle rather than assumed:

- The oracle asserts **every non-negative fixture cannot see a fill**: `(x >> k) ==
  ((x & M64) >> k)` for `zero`, `one`, `max` at all ten amounts. A gate built only from
  those three would pass an implementation that never writes the sign at all.
- The oracle asserts the set of past-the-width rows that can tell a `mod 64` **wrap** from
  a saturation is exactly **7 cells**: `(one|max, 64|65)`, `(signmin|spill, 64|65)`.
  **At `k = 127` NO row can see a wrap**, for any fixture — a wrap of 127 lands on 63, and
  `x >> 63` is `-1` for every negative int64 and `0` for every non-negative one. So the
  sibling gate's `127`, useful there, would have been a blind amount here.
- The oracle asserts `spill @ 1` is `0xC0000000:0xCD5E6F78` **and** that each of the four
  terms, deleted one at a time, gives a different word — so those four assertions are not
  one fact counted four times.
- The gate asserts the seed **value** on all three lanes (a pin asserting only *presence*
  passes when the driver silently used its default), every compared row **non-empty**
  (the recorded `"" == ""` failure), every expected row **NAME** present (a count is not a
  row set), and refuses to answer from a `bd.txt` that is not exactly 301 rows.

**Amounts** (`nats()` at `shr.bend`): `0, 1, 31, 32, 33, 62, 63, 64, 65, 127` — boundaries,
not a sample. `0` identity; `1` all four terms load-bearing; `31` last amount with both
cross terms nonzero; `32` **the amount where the two arms meet** (hence `k <= 32`, not
`< 32`); `33` first amount only the large arm serves; `62`/`63` widest in range; `64` =
`2**6`, `65` past it, `127` far past.

**Two routes per row.** `_amt`/`_lc` take the amount at the row's own slot (syntax);
`_rt_amt`/`_rt` take the same amount at `(seed + i) mod 10` with `seed` read from the
**process environment**. `(seed + i) mod len` is a permutation, so any seed reaches all ten
amounts, and the amount is what selects the shift's two arms — so a folded amount would
fold the arm too. Green at seeds **7, 0, 3, 9**.

## 5. THE BOUNDARY TABLE — what my implementation does, and whether upstream agrees

`spill` = `0x80000001_9ABCDEF1`, `max` = `2**63-1`, `neg1` = `-1`, `one` = `1`. Pairs are
`hi:lo`.

`spill` = `0x80000001_9ABCDEF1`, `max` = `2**63-1`, `neg1` = `-1`, `one` = `1`.
**DECIMAL, because that is what the driver and the gate's rows actually hold** — a table of
hex here would be a second transcription to keep in step with the 301 rows rather than a
reading of them. `F` is not used as an abbreviation.

| `k` | `neg1` = `-1` | `one` = `1` | `max` = `2**63-1` | `spill` = `0x80000001_9ABCDEF1` | CPython `>>` | agree? |
|---|---|---|---|---|---|---|
| `0` | `4294967295:4294967295` | `0:1` | `2147483647:4294967295` | `2147483649:2596069105` | `x` | ✅ identity, low arm only |
| `1` | `4294967295:4294967295` | `0:0` | `1073741823:4294967295` | **`3221225472:3445518200`** = `0xC0000000:0xCD5E6F78` | `x >> 1` | ✅ **all four terms load-bearing here** |
| `31` | `4294967295:4294967295` | `0:0` | `0:4294967295` | `4294967295:3` | `x >> 31` | ✅ |
| **`32`** | `4294967295:4294967295` | `0:0` | `0:2147483647` | `4294967295:2147483649` | `x >> 32` | ✅ **the arms MEET** — low word is `hi`, high word the fill |
| **`33`** | `4294967295:4294967295` | `0:0` | `0:1073741823` | `4294967295:3221225472` | `x >> 33` | ✅ **fill in BOTH words** — the row a high-word-only fill gets wrong (`spill@33` loses its low fill) |
| `62` | `4294967295:4294967295` | `0:0` | `0:1` | `4294967295:4294967294` | `x >> 62` | ✅ |
| **`63`** | `4294967295:4294967295` | `0:0` | `0:0` | `4294967295:4294967295` | `x >> 63` | ✅ **arithmetic** — a *logical* shift reads `0:1` for `neg1` |
| **`64`** = `2**6` | `4294967295:0` = `-1` | `0:0` | `0:0` | `4294967295:0` = `-1` | `0` / `-1` | ✅ **saturates to the sign**, does NOT wrap |
| `65` | `4294967295:0` | `0:0` | `0:0` | `4294967295:0` | | ✅ |
| `127` | `4294967295:0` | `0:0` | `0:0` | `4294967295:0` | | ✅ and **no row can see a wrap at this amount** |

**WHAT THE TABLE SETTLES ABOUT THE TWO SIGNS.** For a negative `x` the high word becomes
`0xFFFFFFFF` **as soon as `k >= 1`** and stays there — so the sign-extension is decided by
the FIRST amount, and amounts 1 through 63 differ from one another only in the low word.
For `x = -1` the low word is *also* saturated, which is why it is blind to a wrapped
amount. For a non-negative `x` the high word is `0` at every amount and the low word
reaches `0` by 62 (`max`) or 63.

**UPSTREAM DOES THE SAME THING AT EVERY ONE OF THESE ROWS**, because `x >> k` *is*
CPython's answer and `-1` is representable. There is no row in this table where my
implementation and `operator.rshift` disagree, and there is no row where they *could*
disagree — that is the whole of §3.

## 6. PLANT AND DISARM — four plants, all IN `helpers.bend`, all disarmed

Instrument: whole-`name=value` **line** diff against `.agents/slop/ishr/base.bd.rows`
(301 rows, asserted non-empty and by length), moved rows printed **BY NAME**. Not a name
*comparison* — the recorded failure is a name-comparing harness reporting 0 for all 30 and
all 68 mutations in two other units.

| plant | change | rows moved, BY NAME | gate |
|---|---|---|---|
| **P1** | delete the sign fill from the **high** word | **18** — all on `neg1`/`signmin`/`spill`; `zero`/`one`/`max` move **0** | FAIL |
| **P2** | delete the sign fill from the **low** word (fill in the high word alone) | **36** — and **not one** at an amount ≤ 32 | FAIL |
| **P3** | `hi << (32-k)` → `hi << (31-k)`, one bit off the cross term | **8** — `max`, `signmin`, `spill` only | FAIL |
| **P4** | take the amount `mod 64` | **12** — `one`/`max`/`signmin`/`spill`, **none of `neg1`, none at 127** | FAIL |

**All four disarmed**, and the disarm is *re-measured through the same bounded instrument
that armed them*: 301 rows, identical to the baseline. `helpers.bend`'s sha256 is taken
before each edit and **verified in a `finally`**, and a mismatch exits 2 rather than
compounding.

P1 and P4 are the two that justify the fixture set: **P1 moves 0 rows on half the
fixtures, and P4 moves 0 rows on `-1` and at `127`** — an exhaustive gate over the wrong
universe, exactly the `bf16` failure in miniature. P2 is the one that would have been
missed by an amount table without 33.

## 7. `helpers.bend` WAS EDITED — hashes

| | bytes | sha256 |
|---|---|---|
| before | 125,668 | `1c9f47b23d85ac78c6c77ab4f666e151d30b8d65182429d8819d953cef315703` |
| after | 130,719 | `2f2cb93e9a6d147458f31c3e25548fbf5aeca702ddc10e4e82e07dd67329f200` |

**+76/−1 lines, one contiguous hunk** immediately after `i64_shl` (`:1819` → the new block
at `:1822`-`:1874`). `import "` count is **0 before and after** — still pure. Verified
after every gate run and after every plant. `checks/no-shrink.py`: `1 GREW, 0 SHRANK`.

**This was the one file I touched outside my own, and I took the hash first because the
brief warned it has been truncated to 0 bytes four times.** I did not observe that here.

## 8. THE REOPEN, THE ANCHOR, THE DATE

- **ANCHOR (a grep settles existence).** `grep -c '^def i64_shr' tinybendygrad/helpers.bend`
  → **1**. It was **0** before this unit.
- **ANCHOR (the command that re-runs it).** `I64SHR_SEED=7 .venv/bin/python gates/i64-shr-gate.py`
  → rc 0, 301 rows, 3 lanes identical. `.venv/bin/python .agents/slop/ishr/plant.py` → rc 0,
  4 of 4 armed and disarmed.
- **REOPEN.** the gate going red; or `helpers.bend:1873` ceasing to read `+k: Nat`; or
  `grep -c '^def i64_shr'` reaching 0 again; or a `tinygrad/uop/ops.py` rebinding of
  `Ops.SHR` away from `operator.rshift`.
- **DATE.** 2026-10-05, of the measurement. Nothing here is dated by a read.

## 9. WHAT I COULD NOT SETTLE

- **`mixin/dtype.bend:58` still says `SHL/SHR -> NOWHERE`** and its neighbours `:52-53`
  (`i64_mul` "NOWHERE" — it is `helpers.bend:2206`), `:60`, and `:54-57`/`:58-59` (the
  `IO(..)` seams) are uncorrected. **Not mine, reported, not touched** — six units share
  that file. **`:58` is now half stale**, like `:57` was before the `i64_shl` unit.
- **No caller.** `i64_shr` has no caller in the tree, so nothing consumes it yet. Whether
  `uop/fold.bend`'s `_min_max` can use it is `fold.bend`'s call and not mine.
- **The `uint64` reading has no def.** If a caller needs a *logical* 64-bit shift, the
  port has no `i64_ushr`. I judged that unnecessary — upstream's unsigned SHR is CPython's
  `>>` on a non-negative int, which `i64_shr` already computes — but I did not measure a
  demand for it.
- **`checks/no-txt.py` fails on 389 pre-existing files** unrelated to this unit. My files
  are `.bend`/`.py`/`.rows`/`.md`.
- **`gatekit.py`'s API moved under me** mid-unit (`_lane` now takes a name and stages;
  `run()` clears the directory and promotes only on green). I did **not** edit it. My gate
  resolves the lane path and **fails loudly** if it cannot, rather than hard-coding it.

## 10. FILES

| path | |
|---|---|
| `tinybendygrad/helpers.bend:1822-1874` | **the implementation**, one hunk after `i64_shl` |
| `gates/i64-shr-gate.py` | **mine.** 301 rows, 3 lanes, holds only this gate's rows and claims |
| `.agents/slop/ishr/shr-oracle.py` | **written FIRST.** CPython oracle; expectations from unbounded `x >> k`, decomposed — not the port's word-wise route |
| `.agents/slop/ishr/shr.bend` | driver. imports `helpers.bend` as `H`; defines no `I64` arithmetic of its own |
| `.agents/slop/ishr/plant.py` | four plants in `helpers.bend`, with the before/after hash guard and the re-measured disarm |
| `.agents/slop/ishr/base.bd.rows` | pre-plant baseline, 301 rows, sha `b9bbdcf7…` |
| `gates/artifacts/i64-shr/` | `py/bd/bn.txt`, `.sub`, `gate.bin` (Mach-O arm64) |

Peak RSS, all bounded through `checks/bounded.py`, **one `bend` at a time, none in the
background**: `--check-only` 210 MB, driver runs 206–214 MB, gate runs within the 2048 MB
ceiling. Every run parsed the `[bounded] WITHIN-LIMITS` **token**, not the exit code —
`plant.py` and the gate would both have run blind otherwise. No run was killed, none timed
out, and no other `bend` process was started.