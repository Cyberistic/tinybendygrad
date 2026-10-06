# FROMBITS — `def F32.from_bits`, and the six `dtype.bend` laws it unblocked

Unit: `.agents/slop/frombits/`. **Nothing committed.** Owns `tinybendygrad/base.bend`
(new) and `tinybendygrad/dtype.bend`. Compiler **Bend 2.0.34** via `./bin/bend`.
Rule prefix `FB-`.

---

## 1. WHERE `F32` IS DECLARED

`references/bend/bend2/base.bend:60`

```bend
type U32 is Data:
  U32{data: Word(32n)}      # :57

type F32 is Data:
  F32{data: Word(32n)}      # :60-61
```

**A name is not a binding, and the search order matters.** The brief said
`tinybendygrad/base.bend`; that file did not exist. `F32.bits` is a `law` at
`base.bend:1697`. `import Base` is how every file in the tree gets it
(`dtype.bend:33`, `helpers.bend:24`).

**The observation the whole unit rests on:** a float's payload and an integer's
payload are the SAME TYPE, `Word(32n)`, so a float's payload *is* its IEEE-754
pattern. The constructor `F32{..}` is already a bitcast. `runtime/ops_python.bend:274-278`
had already measured this (`w32`/`f32_of`) and could not hand it to `dtype.bend`,
because `ops_python.bend` IMPORTS `dtype.bend` and the dependency runs one way.

## 2. THE DEFINITION

`tinybendygrad/base.bend:54-56`. `F32.bits` **is** the inverse; there is
deliberately no second name for it.

```bend
def F32.from_bits(bits: U32) -> F32:
  match bits:
    case U32{data}: F32{data}
```

Two lines, **safe**, so `bend --check-only` accepts it (`ALL PROOFS CHECK`, and
`substrate-check.sh` reports `WARM`). It is NOT a compiler intrinsic and NOT a
`law`: `comp.ts:320-321` emits `F32{word}` as `f32_from_bits(word_to_u32(word))`
and `word_to_u32` (`comp.ts:478`) is the identity on the payload.

`U32.to_f32` is **not** this and the gate measures what that costs: planted in
`Dt.bf16` it **compiles clean** (`U32 -> F32` is a law) and moves **214016 of
463360 rows** with plausible-looking floats. `U32.to_f32(3) == 3.0`.

## 3. THE CENSUS — bit patterns and NaN payloads against a denominator

`gate.sh`, whole `name=value` lines, `sum_in` per chunk as the anti-skip check.

| lane | space swept | patterns round-tripped | NaN in window | **NaN payloads kept** | mismatch |
|---|---|---|---|---|---|
| **C** | `0 .. 2^32` — **ALL of it**, 22 chunks | **4 294 967 296** | 16 777 214 | **16 777 214 / 16 777 214** | **0** |
| JS | `2139095040 .. +200000` (the NaN region) | 200 000 | 199 999 | **0 / 199 999** | 199 999 |

The denominator is derived twice and the two must agree or the run fails:
`expect.py:nan_count_field` reads it off the field widths (2 signs × (2²³−1)
nonzero mantissas) and `nan_count_iterated` calls CPython `struct` + the IEEE
self-compare on each of the 16777214.

### FB-1. THE LANE SPLIT IS THE FINDING

`F32.bits(F32.from_bits(p)) == p` for every one of the 2³² patterns in the C
lane and for every **non-NaN** in JS. JS collapses every NaN — payload AND sign —
onto `0x7FC00000`, because `comp.ts:539 f32_from_bits` hands the float to
JavaScript, whose `NaN` is one value. C carries an F32 as the raw `u64` of its
pattern (`comp.ts:391 f32_unbox` / `:396 f32_rewrap`, a union), so `f32_bits` is
the identity. **No definition of `from_bits` can repair this**, and the seam
(`runtime/dtype.c`) lives in C, which is the lane that is exact.

### FB-2. THE FIXTURE SET THE BRIEF ASKED FOR, AND WHERE IT IS

Covered by the whole-space sweep, so it is stated rather than re-listed: ±0,
smallest/largest subnormal, smallest normal, 1.0, ±1 ULP around it, ±inf, every
exponent class (all 256 × both signs × 5 mantissas), every NaN class — quiet,
signalling, negative, `0xFFFFFFFF` — and 40 seeded randoms. `expect.py
--fixtures` and `--classes` emit the named tables for anyone who wants them
individually.

## 4. `dtype.bend`'s RED COUNT, BEFORE AND AFTER

`bend tinybendygrad/dtype.bend --check-only`

**14 → 8.** Retired exactly the six named: `Dt.bf16`, `Dt.fp16`, `Dt.fp8_to`,
`float_to_bf16`, `float_to_fp16`, `fp8_to_float`. No law was deleted — all
fourteen names are still declared once each. Whole-tree sweep: **the set of red
files is byte-identical**, 14 files, `dtype.bend` among them; the new
`base.bend` is **not** among them. The eight files that merely *import*
`dtype.bend` (`nn/*`, `runtime/ops_python.bend`, …) dropped from **14 inherited
laws to 8**.

### The eight that remain, with `file:line`

| def | file:line | why it is not mine |
|---|---|---|
| `Dt.fp8_from` | `tinybendygrad/dtype.bend:919` | the one conversion whose f32 restatement is **not** a rewrap. `runtime/dtype.c:12-17` says why: dtype.py does it on f64 and this on the f32 pattern. |
| `Dt.i64_trunc` | `tinybendygrad/dtype.bend:923` | needs `I64 → F32`-free trunc; `helpers.bend:1639` has the type |
| `Dt.i64_floor_div` | `:927` | `i64_mul` is missing (`mixin/dtype.bend:56`) |
| `Dt.i64_floor_mod` | `:931` | same |
| `Dt.i64_cdiv` | `:935` | same |
| `Dt.i64_cmod` | `:939` | same |
| `Dt.i64_ceildiv` | `:943` | same |
| `float_to_fp8` | `:967` | red only through `Dt.fp8_from` |

DTYPEB measured the i64 six at "an effect boundary removed" and left them in a
patched file. **This unit did not touch them** — the effect boundary is not a
missing type, and removing it was DTYPEB's lane, not this one's. They are named
here so the 8 has a cause.

## 5. FOUR REAL BUGS THE GATE CAUGHT, ALL IN THE PORT I WROTE

Every expectation is a **call** into `tinygrad/dtype.py` (`float_to_bf16`,
`float_to_fp16`, `fp8_to_float`) with the answer read out by `struct`. 463360
rows per lane; JS skips 26936 whose *answer* is a NaN pattern (it cannot check
those) and C runs all of them.

1. **`U32.shrn(x, sig)` for `U32.shrn(x, sig - 1)`.** Every fp8 code, wrong
   exponent. `dtype.py:273` shifts by `mant_bits = sig_bits - 1`.
2. **`x & 0x80 == 0x80` for `x == 0x80`.** Returned a NaN for **127 codes per
   fnuz format** that are ordinary finite numbers.
3. **`kind == e5m2` inside the saturating GUARD.** dtype.py:272-277's guard is
   `not fnuz and exp == exp_max` and its THIRD answer is a **fall-through**.
   Putting e5m2 in the guard answered a finite number for e4m3 `0x7F`/`0xFF`;
   answering nan/inf for the whole arm answered infinity for `0x78..0x7E` where
   dtype.py says 464.0, 480.0, ….
4. **The half NaN payload was dropped in BOTH directions.** `dtype.c:121` and
   `:147` OR in only the quiet bit; CPython's `struct.pack('e', …)` also
   truncates the mantissa by the 13-bit difference, so `0xFFFFFFFF` becomes half
   `0xFFFF`, not half `0xFE00`.

**Two defects found in `runtime/dtype.c`, REPORTED NOT FIXED — it is not this
file's:**

5. **`dtype.c:168-176` (`bf16_run`) has no `isfinite` guard.** `dtype.py:230` is
   `if not math.isfinite(x): return x`. The C rounds every pattern, so at
   `0x7F800001` it answers `0x7F800000` and dtype.py answers `0x7F800001`. bf16
   exists to keep a NaN's payload and rounding is what destroys it. **This port
   has the guard**; the C does not, and the C and this file will disagree on every
   non-finite input until it does.
6. **`dtype.c:97-98` reads as if e5m2 were the only saturating format**, which is
   bug 3 above. Same disagreement.

Also unchanged, and consistent with DTYPEB: `dtype.c:40`'s missing trailing `-1`
on three of four thresholds, and the shaper's 4-wide subnormal window. Not
touched, not worked around.

## 6. PLANT AND DISARM — DISARM FIRST

`mutate.sh`. Whole `name=value` lines, against CPython.

```
BASE                              moved=0
DISARM D3  bf16 is_eq(m,c) -> not(is_ne(m,c))    moved=0
PLANT  P1  F32.from_bits -> U32.to_f32           moved=214016   COMPILES CLEAN
PLANT  P2  fp8 exponent shift  sig-1 -> sig      moved=31104
PLANT  P3  fp8 exponent mask    -> 127           moved=16256
PLANT  P4  the CENSUS's own NaN test, blinded    nan_in 0 != 16777214   FAIL
CONTROL P4 unblinded, whole space                nan_kept 16777214      PASS
```

**TWO DISARMS FAILED FIRST, and both were mine — this is the part worth keeping.**

- **D1** replaced `(bits & 0x7F800000) != 0x7F800000` with `bits < 0x7F800000`.
  **Moved 116984 rows.** It is false for every pattern with the sign bit set, so
  it is a different *predicate*, not a different spelling.
- **D2** replaced `is_eq(masked, c)` with `is_ne(masked, c)`. **Moved 215288
  rows.** Those are complements, so it inverted the test rather than respelling
  it. Two failed disarms in a row, both from turning "the same test" into "the
  other test".

A disarm is only a disarm if it is the same FUNCTION by a different expression.
Both were caught, and only because the run diffs values instead of names.

**A third failure, and it is the worst kind: the script itself.** The first
`mutate.sh` mutated the LIVE `tinybendygrad/dtype.bend` and restored it on EXIT.
A run killed by the 120 s tool timeout left plant **P1 sitting in the live tree**,
answering a plausible float for 214016 rows and **still compiling**. That is a
disarm that removed the fix and became a second mutation. `mutate.sh` now copies
the tree to `$TMP` and the live `tinybendygrad/` is **never written**; the last
line of the run prints the live file's own `--check-only` to prove it.

**P4 PASSED THE FIRST TIME**, over a 400000000-pattern window — which contains
**zero** NaN patterns, the first being at 2139095040. A NaN census over a
NaN-free window is a claim about no patterns. `run.py` now **REFUSES** a partial
range whose NaN denominator is 0 instead of reporting a zero, and P4 runs over
the whole space.

## 7. WHAT I COULD NOT FILL

- The eight laws in §4, with `file:line`. Seven of them are one missing
  primitive (`i64_mul`) and one (`Dt.fp8_from`) is a deliberate f64/f32 split.
- **`runtime/dtype.js` was not re-checked against anything.** It is not this
  file's, and the JS lane's NaN collapse means the JS fp8/bf16/fp16 paths cannot
  separate two NaNs — which is a statement about `comp.ts`, not about that file's
  arithmetic.
- **`ops_python.bend:274-278` (`w32`/`f32_of`) is now a DUPLICATE** of
  `base.bend`'s `from_bits` and should import it. `ops_python.bend` imports
  `dtype.bend`, which imports `base.bend`, so the cycle is already broken — but
  that file is not this unit's and the edit is not made here.
- **`F32.from_bits` itself has no mutation.** It is the identity on `Word(32n)`,
  so no change to its body can change its output; deleting the name is a
  compile error, not a value change. The census is its gate.

## 8. REPRODUCE

```sh
zsh .agents/slop/frombits/gate.sh      # both lanes, both halves
zsh .agents/slop/frombits/mutate.sh    # disarm first, then four plants
```

## 9. FILES

`tinybendygrad/base.bend` (56 lines, live) ·
`tinybendygrad/dtype.bend` (971 lines, live) ·
`.agents/slop/frombits/sweep.bend` (the census driver) ·
`expect.py` (the two derivations of the denominator) ·
`run.py` (chunk walker; refuses a NaN-free window) ·
`gate_dtype.bend` / `gate_dtype.py` (the six laws) ·
`gen_dtype.py` (the per-case oracle) ·
`gate.sh` · `mutate.sh` · `00-stub.md`
