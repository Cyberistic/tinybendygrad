# JSFP8 — the two fp8 defects `runtime/dtype.js` carried, and the decode gate that did not exist

Unit: `.agents/slop/jsfp8/`. Rule prefix **`JFP-`**. **Nothing committed.**
I own `tinybendygrad/runtime/dtype.js` and `.agents/slop/jslane2/**`; **every
mutation ran on a `$TMPDIR` copy** and the live tree was never written. Four code
lines changed in `dtype.js`, twelve comment lines added.

## THE TWO FIXES

| file:line | before | after |
|---|---|---|
| `runtime/dtype.js:46-48` (table rows 2-4, `FP8_CFG[1..3]`) | `0x47700000, 0x43780000, 0x47700000` | `0x476fffff, 0x4377ffff, 0x476fffff` |
| `runtime/dtype.js:109` (`fp8_decode`, e4m3's NaN) | `return sgn ? 0xffc00000 : 0x7fc00000` | `return 0x7fc00000` |

The report cited `dtype.js:37-38` and `:97`; those are the pre-fix line numbers
and the table is three rows, so **three of the four entries** were the defect, not
two. `dtype.js:113` (`Math.pow(2, 1 - bias)`, `:101` before the fix) was left
alone — finding 3 is C-only and `Math.pow(2, 1 - bias)` is `dtype.py:279`'s
`2 ** (1 - bias)`.

## ROWS PASSED vs ROWS EXPECTED

`gate.py`, 205,121 rows, **every expectation CALLED from `tinygrad/dtype.py`**:

| | rows expected | present | MISMATCH |
|---|---|---|---|
| **BEFORE** | 205,121 | **205,121** | **7** |
| **AFTER** | 205,121 | **205,121** | **0** |

The 7: `D[e4m3][cff]` `ffc00000` where CPython says `7fc00000`, and
`T[…][47700000p|n]` / `T[…][43780000p|n]` for the three formats dtype.py writes a
`-1` on, both signs. **e4m3 has no `T` row and the reason is upstream's, not the
gate's**: `dtype.py:238-241` writes the `-1` on e5m2, e4m3fnuz and e5m2fnuz and
not on e4m3, and for e4m3 the two f32 spellings of the threshold coincide.

## THE DECODE GATE, AND WHY IT HAD TO BE A DIRECT DRIVER

`DTYPEB.md` and `FP8FIX.md:160` record `Dt.fp8_to` as red and unreached, and
`FP8FIX.md:153` states the consequence: 1,228 C-side rows never saw findings 3
and 4 because `fp8_to_float` was not in that gate at all. So the instrument that
had to catch these two was a decode gate, and **none existed**.

`Dt.fp8_to` is now **PURE** — `dtype.bend:916 def Dt.fp8_to(bits, +kind) -> F32`
imports **no** `.js` seam and uses Bend's own `fp8_decode` (`dtype.bend:780-914`).
So `dtype.js:162 fp8_decode`'s value is unreachable from any `.bend`, and the seam
that does exist (`dtype_fp8_to`, `dtype.js:162-163`, registered at `:202`) ends in
`of32(...)`, which hands the pattern to JavaScript. `drive.mjs` therefore loads
the **live** file under plain node and calls `fp8_encode`/`fp8_decode` directly —
the same shape as `fp8fix/build.py`, which compiles the live `dtype.c` instead of
going through `dtype.bend`. It appends **exactly one line** (an export list,
`fp8_decode` is module-local) and `gate.py` **asserts** the appended text equals
that line, so "we drove the tree" is checked rather than asserted.

| family | what | rows |
|---|---|---|
| **D** | `fp8_decode(x, kind)`, all **256 codes × 4 formats**, compared as f32 PATTERNS | 1,024 |
| **T** | both f32 spellings of `dtype.py`'s own threshold, ±64 patterns, **both signs** | 1,040 |
| **R** | every exact fp8 code and its two neighbours — exhaustive over the rounding path | 3,057 |
| **W** | a fixed-seed LCG over the whole 32-bit pattern space | 200,000 |

**The sweep centres come from `tinygrad`'s `_fp8_cfg`, never from `dtype.js`.**
That is the whole point: `fp8fix/gen_fp8.py:35` builds its sweep from `dtype.c`'s
own `OVF`, so the bug was transcribed into the fixture. The fixture here is built
from the ORACLE and covers **both** spellings, so a tree that moves back is
counted right.

**Three fixture bugs of my own, all of which MOVED rows** (agent-core.md:167-172):

1. `_fp8_cfg`'s thresholds are f64 **bit patterns as ints**, not floats. Passed
   straight to `struct.pack("<f", …)` they encode 465.0's *bit pattern* as a
   float, and the sweep centred on `0x5e80fa00` instead of `0x43e80000`.
2. **`nextafter` in f64 is a no-op after the cast.** The f64 ULP is ~2^-42
   relative and the f32 ULP ~2^-15, so "both spellings of the threshold" collapsed
   to one pattern and the fixture claimed a coverage it did not have. The
   predecessor has to be taken in the **f32** domain — for a positive pattern,
   `p - 1`.
3. **The two families answer in different units.** `float_to_fp8` answers an fp8
   CODE and `fp8_to_float` a VALUE. One formatter for both reported 8,170 of
   9,202 rows as MISMATCH — every row, for a string-width reason.
4. Row names collided across signs and across the two centres, so the differ
   silently kept the last of each. `worklist()` now **asserts** name uniqueness;
   a name that cannot be read as true about its own row is a fixture defect
   (agent-core.md:182).

## THE NAN-PAYLOAD CENSUS, EXHAUSTIVE, WITH ITS DENOMINATOR

`nan_census.mjs` walks **every** f32 NaN pattern — exponent `0xFF`, mantissa
1…`0x7FFFFF`, **both signs** — and counts `f32_bits(f32_from_bits(p)) === p`,
using `comp.ts:539-546`'s two helpers copied in verbatim.

> **8,388,608 / 16,777,214 kept. The 8,388,606 that do not are exactly the
> SIGNALLING NaNs** — `signallingKept 0` out of 8,388,606. Quiet NaNs keep their
> payload **and their sign** through this path, and two quiet NaNs are two
> different JS doubles (`two_nans_one_JS_value: false`).

**This REFUTES `base.bend:42-44`**, which claims "JS `F32.bits(F32.from_bits(p))`
collapses EVERY NaN onto `0x7FC00000` — payload and sign both gone — because
`comp.ts:539 f32_from_bits` hands the float to JavaScript". On node v26.8.1
(darwin) the f32→f64 widening **quiets** an sNaN and changes nothing else.
`norm/canon.py:56-62` measured the four patterns `0x7fc00001, 0x7fc00000,
0xffc00001, 0xffc00002` — all four quiet — and generalised correctly for those
and wrongly for signalling ones. `base.bend` is DO-NOT-TOUCH: reported.

**All four non-finite patterns `fp8_decode` can return — `0x7FC00000`,
`0xFFC00000`, `0x7F800000`, `0xFF800000` — survive the round trip.** So the
`of32` wrapper would have carried this unit's own fix correctly, and reaching
`fp8_decode` directly was **necessary for reachability, not for NaN fidelity**.
Stating that is the point: the brief's premise ("JS keeps 0 / 199,999") is
**wrong for this file's path**, and the real loss — signalling NaNs, and any NaN
that goes through JS arithmetic — is still **not repairable port-side**, because
the conversion is in the runtime.

## THE `norm` FIX, AND THE THIRD INSTANCE

`.agents/slop/jslane2/gen_f32_seam.py:100` `norm` was `repr(float(s))` with **no
round trip**. It now delegates to `.agents/slop/norm/canon.py`'s `canon(s,"f32")`,
which rounds through f32 once on **both** sides and answers `f32:?nan` for a NaN
so a gate cannot quietly call two NaNs the same row. A **new row `fp16_1p1`**
closes the escape — the defect only hid because no `1.1` row was in `CASES`.
`norm_check.py` proves it on the exact pair the defect names
(`1.0996094` vs `1.099609375`, one f32), carries the **negative** case so a
constant `norm` cannot pass, and **plants** the old `repr(float(s))`, which
**fails 1 of 5**. Fix 5/5, plant 4/5.

`canon.py:87-88` claimed `gen_f32_seam.py` was already routed through it. **It
was not**, until now. Reported.

**THE THIRD INSTANCE: `.agents/slop/mm-lift-gate.py:158`** carries
`"F" + (f"{v:g}" if v.is_integer() else repr(v))` — the **same** expression as
`mm-dt-gate.py:60` and `mm-walk-gate.py:44`, and `norm/canon.py:99-102` names
**only those two**. All three are another unit's tree: reported, not edited. The
census of every float-spelling comparator in the tree, measured by reading each:

| file:line | verdict |
|---|---|
| `jslane2/gen_f32_seam.py:100` | **DEFECT — fixed here** |
| `mm-dt-gate.py:60`, `mm-walk-gate.py:44`, `mm-lift-gate.py:158` | `%g`/`repr` with no round trip — another unit's tree |
| `dc-oracle.py:135` | `f"{a:g}"` — another unit's tree, and its author **knew** (`:131`) |
| `abi/abi_gate.py:118`, `abi4/abi4_gate.py:235` | correct (f32 round trip), DO-NOT-TOUCH |
| `jstage/jsstage.py:315` | correct — `repr` at the oracle, `f32()` on both sides at `:328` |
| `ew-consts-oracle.py:14-34`, `dd-oracle.py:28-42` | correct — deliberately bits-based |
| `validate-oracle.py:80`, `codegen-init-measure.py:240`, `arena-audit.py:121` | not float comparators |

**Both `jslane2` gates are now RED against the current tree, for reasons that
predate this unit** — verified by running the **committed** copies:

* `gen_f32_seam.py`: `bend` rejects its `SRC` template. `Dt.bf16` and `Dt.fp16`
  became SEAMS in `dtype.bend` (`dtype.bend:581-583`), so `v : F32 <- D.Dt.bf16(…)`
  is a type error. `dtype.bend` is another unit's LIVE file. Reported.
* `gen_js_seam.py`: `anchor not unique (0x) -- dtype.js moved`. Its anchor still
  expects `p.fst`/`p.snd` in `i64_of`; the committed `dtype.js:160` reads
  `p.hi`/`p.lo`. The anchor predates the ABI repair. Reported.

## PLANT AND DISARM

`plants.py`, 205,121 rows per tree, differ over **whole `name=value` lines**.
**BASE is reconstructed by reverse-applying this unit's edits INCLUDING the
comments and is PROVEN byte-identical: md5 `fa61344f1dbecd9afa7563364583ae47`,
the pre-fix file's measured md5.**

| mutation | moved | mechanism | out-of-mech | verdict |
|---|---|---|---|---|
| **BASE** (both fixes reversed) | **7** | 18 | **0** | BOUND |
| PLANT-ovf-transcription (all three entries) | 6 | 16 | **0** | BOUND |
| PLANT-ovf-e5m2-only (granularity) | 2 | 16 | **0** | BOUND |
| PLANT-nan-signed | 1 | 2 | **0** | BOUND |
| **PLANT-fnuz-helper-inverted** | **1** | **1** | **0** | **EXACT** |
| DISARM-ovf-respell (`0x47700000 - 1`) | **0** | — | — | holds |
| DISARM-nan-rewrap (`bits32(NaN)`) | **0** | — | — | holds |
| BLIND-fp16-subnormal-zero | 0 | — | — | stated blind spot |

**`OUT-OF-MECHANISM 0` on every plant is the assertion that can actually fail.**
Each mutation carries the mechanism(s) naming the rows that could move, and any
row that moved without being named is printed. Subset, not equality, where the
property is a fact about the PORT: for the threshold plants the mechanism says
which patterns are *candidates*, and whether the saturating and the rounding
answer differ at one is CPython's to say (FP8FIX.md:79-83). **10 of 16** ovf
candidates do not move and **1 of 2** nan candidates does not, both with reasons
in the log — e4m3 is the threshold dtype.py writes without a `-1`, and its two
f32 spellings coincide; and `dtype.py:275`'s bare `math.nan` is unsigned on
**both** e4m3 codes, so the plant can only move the negative one.

**THE HELPER-INVERSION PLANT.** `kind >= FP8_E4M3FNUZ` is the file's own fnuz test
(`dtype.js:96`); `>` keeps e4m3fnuz out of it. **A new gate is the weakest
instrument in the tree, so this one plants an inverted helper and confirms it
fires: 1 row moved, and the mechanism determines it exactly — `>= → >` changes
the test for kind 2 alone, and the arm is guarded by `x === 0x80`, so `EXACT`.**

## WHAT I COULD NOT FIX, WITH file:line

1. **`dtype.js:162` `dtype_fp8_to` is registered as a seam (`:202`) for a
   `Dt.fp8_to` that is PURE.** `dtype.bend:916` imports no `.js`, so this seam —
   and its `of32` wrapper, and `fp8_decode`'s only JS caller — is
   **unreachable**. I can see it and I must not edit `dtype.bend`.
2. **`base.bend:42-44`'s NaN claim is wrong**, as measured above. DO-NOT-TOUCH.
3. **`mm-lift-gate.py:158`** and the two `mm-*` siblings. Another unit's tree.
4. **Both `jslane2` gates are red against the live `dtype.bend`/`dtype.js`** —
   pre-existing, verified on the committed copies, and the cause is in files I do
   not own.
5. **`gen_f32_seam.py`'s row count moved 6 → 7** (`fp16_1p1` added). `JS-LANE-GATE.md`
   §6 documents 6 rows and is now stale in that one number.
6. **The fp8 SUBNORMAL ladder in `dtype.js:83-90` is not swept exhaustively.** The
   C unit swept all 234,881,032 patterns in that window; here it is covered by
   the `W` sample and by `R`'s exact codes only. Building the same exhaustive
   sweep means calling CPython 268 M times, which is minutes of wall clock per
   format — a real cost, not an oversight, and `fp8fix`'s sweep already covers
   the arithmetic.

## REPRODUCE

```sh
python3 .agents/slop/jsfp8/gate.py            # 205,121 rows, 1.1 s
python3 .agents/slop/jsfp8/plants.py          # 8 trees, BASE proven by md5
python3 .agents/slop/jsfp8/norm_check.py      # the `norm` fix and its plant
node    .agents/slop/jsfp8/nan_census.mjs  "$TMPDIR/jfp"
zsh .agents/slop/substrate-check.sh tinybendygrad/runtime/dtype.js
```

## RULES LEARNED

- **`JFP-1` — A sweep CENTRE read out of the code under test is a transcript, not
  a fixture.** `fp8fix` caught the C defect by sweeping `t-1,t,t+1,t+2` around
  `dtype.c`'s own `OVF`, which works by luck; here the centres come from
  `tinygrad`'s `_fp8_cfg` and cover **both** f32 spellings, so a tree that moves
  back is counted rather than accommodated.
- **`JFP-2` — `nextafter` in f64 is a no-op after a cast to f32, so "both
  spellings" can silently collapse to one.** The fixture asserted a coverage it
  did not have, and said so in its own row names.
- **`JFP-3` — Two families that answer in different UNITS under one formatter
  make every row a string mismatch.** 8,170 of 9,202 rows read MISMATCH for a
  hex-width reason and not one for a numeric one.
- **`JFP-4` — A seam that ends in a bitcast is not a gate on the thing it
  bitcasts.** `Dt.fp8_to` is pure, so `dtype.js`'s decoder has no caller; the
  gate reaches the function.
- **`JFP-5` — "the JS lane cannot hold a NaN payload" is FALSE for the
  typed-array path this tree uses, and TRUE for signalling NaNs.** Measured
  exhaustively: 8,388,608 / 16,777,214, the loss being exactly the 8,388,606
  sNaNs. The general claim was made from four quiet probes.
- **`JFP-6` — `Object.is(NaN, NaN)` is true for every pair of NaNs, so an
  `Object.is` test of NaN identity cannot fail.** My first census asserted it and
  it asserted nothing. Read the doubles' own 64-bit patterns with a `DataView`.