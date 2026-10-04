# LASTLAW — the eight red laws, re-derived

Unit: `.agents/slop/lastlaw/`. **`tinybendygrad/dtype.bend` IS PATCHED IN THE LIVE
TREE — 971 → 1132 lines, +184/-23. Nothing committed.** Owns that one file.
Compiler **Bend 2.0.34** via `./bin/bend`. Rule prefix `LL-`.

---

## 1. THE STALENESS WAS TOTAL. **8 → 0.**

The previous scoping named a missing `i64_mul` (`mixin/dtype.bend:56`) as the blocker
for seven of the eight, and `F32.from_bits` as the blocker for the eighth. **Both
prerequisites have landed** — `i64_mul` at `tinybendygrad/helpers.bend:2206`,
`F32.from_bits` at `tinybendygrad/base.bend:54-56` — and **all eight fill.** There is no
remaining blocker; the note was true when written and is now false, which is the most
respectable kind of wrong note there is.

| def | file:line (live) | was | now |
|---|---|---|---|
| `Dt.fp8_from` | `tinybendygrad/dtype.bend:919` | seam | pure `fp8_enc` call |
| `Dt.i64_trunc` | `:923` | seam | identity (`dtype.c:i64_run` re-packs) |
| `Dt.i64_floor_div` | `:927` | seam | `H.i64_div` |
| `Dt.i64_floor_mod` | `:931` | seam | `H.i64_mod` |
| `Dt.i64_cdiv` | `:935` | seam | `H.cdiv_i64` |
| `Dt.i64_cmod` | `:939` | seam | `H.cmod_i64` |
| `Dt.i64_ceildiv` | `:943` | seam | `cdiv + (cmod != 0 and signs equal)` |
| `float_to_fp8` | `:967` | seam | `-> U32`; red only through `Dt.fp8_from` |

`bend tinybendygrad/dtype.bend --check-only`: **`Error: 8 defs rely on unsafe or
foreign code`** → **`ALL PROOFS CHECK`**, **0 foreign laws**. No law was deleted: all
eight names are still declared once each.

**`import "./runtime/dtype.*"` lines in the file: 14 → 0, and `IO(` : 7 → 0.** The
file declares **no foreign effect at all**, which is `agent-core.md`'s stated proven
lane ("a `.bend` that runs under both lanes" is not what this file is any more).

Whole-tree census (`.agents/slop/lastlaw/sweep.sh`, `bend --check-only` per file,
137 files, refuses an empty result):

| | before | after |
|---|---|---|
| red files | **11** | **2** |
| `dtype.bend` | 8 | **0** |
| the 8 files that only `import dtype.bend` | 8 each | **0 each** |
| `sz.bend` | 7 | 7 (its own) |
| `runtime/autogen/libclang.bend` | 336 | 336 (its own) |

Re-measured on the **landed** tree: **138 files (another agent added one), red 2.**
`nn/{__init__,onnx,optim,state}.bend`, `runtime/ops_python.bend`,
`runtime/zzprobe2.bend`, `test/dtype_oracle.bend`, `test/_probe/v5.bend` — all eight
inheritors go from 8 inherited red laws to **zero**. Nothing else moved.

`zsh .agents/slop/substrate-check.sh tinybendygrad/dtype.bend` on the landed file:
**WARM**, 1132 lines, **NAMES CLEAN** (3 modules, 306 refs, 306 exact, 0 suffix-only,
0 unresolved, 0 dead imports).

## 2. WHAT EACH CLOSURE COST

**`Dt.i64_cdiv` / `Dt.i64_cmod` — cost: nothing but a delegation.** `helpers.bend:2244`
and `:2248` already carry upstream's spelling (`cmod = x - cdiv(x,y)*y`), so these two
are one call each. **DTYPEB's multiply-free floor-pair derivation is deleted rather
than kept as a second spelling of one function** — that derivation existed *only*
because Bend had no multiply, and `I64MUL.md §4` reaches the same conclusion from the
other side.

**`Dt.i64_ceildiv` — the only arithmetic written here, and it is `dtype.c`'s.** No
`ceildiv_i64` exists in helpers.bend. `helpers.py:66-69`'s `-(num // -amt)` is not
total — `-x` is unrepresentable at `int64.min`, and `ceildiv(int64.min, int64.min)`
is 1 where the negation route answers -1 — so it is `cdiv + (cmod != 0 and
sign(a) == sign(b))`, which is exactly `runtime/dtype.c:262-267`. `min_min` is the row
that says so.

**`Dt.fp8_from` — cost: the encoder, which was simply never ported.** This is the
correct diagnosis of the eighth law and FROMBITS/DTYPEB both got it backwards. The
live file grew a **decoder** (`fp8_decode.*`) and kept an imported body for the other
direction. **The encoder needs nothing new at all**: every step is U32 arithmetic on
a bit pattern, no `F32` is ever *built*, and building one is the only thing Bend could
not do. `F32.from_bits` is a **decoder** primitive. It retired `Dt.bf16`, `Dt.fp16`
and `Dt.fp8_to`; it was never this law's dependency. The two notes named a real
missing primitive and attached it to the wrong def.

**`Dt.i64_floor_div` / `Dt.i64_floor_mod` / `Dt.i64_trunc`** — one call each, and
`i64_trunc` is the identity because `runtime/dtype.c:i64_run` only re-packs and
`H.I64 -> H.I64` is the only thing the signature can express.

## 3. ROWS PASSED AGAINST ROWS EXPECTED

Every expectation is a **call** into CPython — `tinygrad/helpers.py` `cdiv`/`cmod`/
`ceildiv`, Python's `//` and `%`, `tinygrad/dtype.py` `float_to_fp8` — never typed.

| lane | rows expected | rows present | disagree | note |
|---|---|---|---|---|
| i64 | **102** | **102** | **0** | **99 CPython-verified**, 3 `TOTALISE` |
| fp8 | **1228** | **1228** | **0** | 215 patterns, 122 f32 literals, 40 randoms |
| **total** | **1330** | **1330** | **0** | |

The 3 `TOTALISE` rows are `b == 0` (`5_0`), where `helpers.py:66-69` has no zero
guard and CPython raises `ZeroDivisionError`. Their expectation is the seams' own
written zero branch (`runtime/dtype.c:239`, `:262-263`) and they are **counted,
printed, and never counted as passes**. `cdiv` and `floordiv` guard the zero divisor
and answer 0; only `ceildiv` raises upstream, and it is totalised here to 0 the same
way both seams already did.

## 4. PLANT AND DISARM — DISARM FIRST

`run.py`. Whole `name=value` lines. Every bend run is under
`perl -e 'alarm N; exec @ARGV'` — **`timeout` is not installed here.**

```
BASE         ALL PROOFS CHECK   0 foreign laws   1330/1330 rows
DISARM D1  i64_trunc  x -> x | 0                       moved 0
DISARM D2  fp8 zero line  <=  ->  not(> k-1)            moved 0
DISARM D3  ceildiv.of  Bool.pick(zero,..) -> match zero moved 0
PLANT  P1  ceildiv drops the evenness test              moved 4   == 4 derived
PLANT  P2  fp8 exponent mask 255 -> 8388607             moved 203, 0 outside the family (384)
PLANT  P3  fnuz zero keeps the sign                     moved 33  == 33 derived
PINV   helpers.bend  i64_is_neg  ->  not i64_is_neg     moved 65
LIVE TREE  143 files  md5 drift 0   (MINE 0, ANOTHER AGENT'S 0)
GATE PASS
```

**Re-run against the LANDED tree, not the scratch tree: identical, `GATE PASS`,
`md5 drift 0`.** `patch_dtype.py` is idempotent so the unit reproduces after landing.

**The moved sets are DERIVED from each mutation's own algebra, never transcribed.**
P1: `cmod(a,b) == 0 and sign(a) == sign(b)`, computed from `tinygrad.helpers`. P2's
family: `& 0xFF` removes bit 8 of `pattern >> 23`, which is **bit 31 of the pattern**,
so the reachable set is every row whose f32 carries a sign. P3's: fnuz + CPython
answer 0 + sign bit set, from `tinygrad.dtype` called on the pattern read back out of
the emitted program.

### LL-1. THE HELPER-INVERSION PLANT FIRES, AND IT IS THE ONE THAT COUNTS

`PINV` inverts `i64_is_neg` (`helpers.bend:1692-1693`) inside the **variant's own
copy** of `helpers.bend` — a file this unit does not own, mutated only in a scratch
tree. `i64_is_neg` is read directly by `Dt.i64_ceildiv` and indirectly by
`cdiv_i64`/`cmod_i64`, so the inversion is invisible to `--check-only`, to a whole-tree
sweep, and to every lane except one that moves.

**It moved 65 rows: 41 `i64_cdiv`, 12 `i64_ceildiv`, and the rest.** Before the plant
the gate is 1330/1330; under it the i64 lane reports **65 disagreements**. The gate is
armed. `I64MUL.md` rule 5 records the alternative — a gate that was blind to an
inverted sign test for 442 rows while `cdiv` caught it instantly — and this lane is the
one that catches it.

### LL-2. `P1` MOVED **0** ROWS ON THE FIRST RUN, AND THE REASON WAS A DEFECT IN MY OWN PORT

The first `P1` deleted `Bool.not(H.i64_is_zero(r))` from `Dt.i64_ceildiv.above`. It
moved nothing, because **that test was already there twice**: `above` computed it and
`Dt.i64_ceildiv.of` computed it again from the same `r`, and `Dt.i64_ceildiv` asked
`H.cmod_i64(a, b)` for `r` **twice**. Removing the copy in `above` could not change a
single row — which is what a **disarm** does, not what a plant does.

**A plant that moves nothing is a statement about the code under the plant, and this
one was about mine.** The port is fixed: `above` is now `Bool.not(Bool.xor(an, bn))`
and owns no remainder, `.of` owns the evenness test, and `cmod_i64` is asked once.
Re-run, `P1` moves **exactly** the 4 derived rows (`8_4`, `1_1`, `min_m4`,
`min_min`) and no others. `cmod_i64` is a multiply and a subtract, so the duplicate
was a cost as well as a redundancy.

### LL-3. TWO MORE HARNESS DEFECTS, BOTH MINE, BOTH FOUND BY A SUSPECT NUMBER

- **P1's derived set was INVERTED.** It derived `cmod != 0` — the set of rows the
  plant leaves *alone* — and so predicted 3 moves where there are 4. The moved set is
  `cmod == 0`, which is the whole difference between `above` and `not above`.
- **P3's derived set was EMPTY** beside a plant that moved 33 rows. The kind was read
  as `k.split('][')[1][:-1]`, and the row key
  `fp8_from[fp8e4m3fnuz][denorm_k1_+0]` splits on `][` into
  `['fp8_from[fp8e4m3fnuz', 'denorm_k1_+0]']` — index 1 is the **pattern name**. Now a
  regex, the same one `gen_fp8.py` uses.
- **P2's reachability family was half-built.** It held the `fp8_from` rows only, so 86
  `float_to_fp8` negative-decimal rows were reported "outside the family" — and every
  one of them has the sign bit set. Both families are needed.

## 5. THE GUARDS I PUT IN

- **Zero denominator.** `run.py:guard()` **REFUSES** a lane that emitted 0 rows, has 0
  rows present, has **0 CPython-verified rows**, has **0 `TOTALISE` rows** (the zero
  divisor would be ungated), or has **0 f32 literals** (`float_to_fp8` would prove
  nothing). It also refuses rows-expected ≠ rows-present. `P4` passed the first time
  over a window with **zero** NaN patterns, and `i64_div`'s 65th bit passed over a grid
  with no `int64.min` in it; both were green runs about nothing.
- **`sweep.sh` refuses an empty census.** An inline
  `xargs -P 6 -I{} sh -c '…' | grep -v '^0 '` walk examined **137 files and printed
  nothing** in this session, with no error — a "0 red files" result that was a claim
  about no files. The walk is a file, it counts, and it prints `TOTAL 137 red 2`.
- **Timeout.** `perl -e 'alarm N; exec @ARGV'` around every `bend` run.
- **The live tree is never written, and the run proves it.** One pristine copy is taken
  up front, every variant is built from **that** (`patch_dtype.py --src:` takes the
  source as a parameter, so the patch cannot drift onto whatever the live file says
  later), and `run.py` re-verifies the **md5 of all 143 live files** at the end:
  **`md5 drift 0`**.
- **Anchors, not line numbers.** Every patch and every mutation asserts its anchor
  appears **exactly once** (`assert s.count(a) == 1`). DTYPEB's `patch_dtype.py` cut at
  `HEAD_END = 566`, which is four hundred lines stale now.
- **`substrate-check.sh` is run with `zsh`** (the shebang is `#!/bin/zsh`; `sh -n` fails
  on it).

## 6. WHAT I COULD NOT FILL, WITH `file:line`

Nothing in `tinybendygrad/dtype.bend` is left. These are other files', reported:

1. **`runtime/dtype.c`'s registrations for the eight are now DEAD CODE.**
   `dtype.c:283` `CID(Dt.fp8_from)`, `:293` `Dt.i64_trunc`, `:298` `Dt.i64_floor_div`,
   `:303` `Dt.i64_floor_mod`, `:308` `Dt.i64_cdiv`, `:313` `Dt.i64_cmod`, `:318`
   `Dt.i64_ceildiv` — with no foreign effect declared in `dtype.bend` no program can
   define those CIDs, so `fp8_from_run`, `i64_run`, `div64_*_run` are unreachable.
   `Dt.bf16` `:273`, `Dt.fp16` `:278`, `Dt.fp8_to` `:288` have been dead since FROMBITS.
   **All ten are dead now.** Same in `runtime/dtype.js:199-210`.
   **Not fixed — a live unit owns `runtime/dtype.c`.**
2. **`mixin/dtype.bend:52-53` "MUL … `i64_mul` NOWHERE" is FALSE**: it is
   `helpers.bend:2206`. **`mixin/dtype.bend:54-57`** names `Dt.i64_cdiv` /
   `Dt.i64_floor_div` / `Dt.i64_floor_mod` / `Dt.i64_cmod` as `IO(..)` EFFECT SEAMS at
   `dtype.bend:563-571`, which are pure; **`mixin/dtype.bend:50-51`** does the same for
   `Dt.i64_trunc` as an `IO(F32)`-style seam. **`mixin/dtype.bend:61-68`** is the
   two-part wall ("`i64_mul` and a shift are missing outright") — **part one is now
   closed** and the seams it calls the *second, harder* part are closed too, so
   **`UOp._min_max`'s only remaining gap is a 64-bit SHIFT**, and `i64_shl`
   (`helpers.bend:1819`) takes a `Nat`, which a runtime shift amount cannot be.
3. **`helpers.bend:1740-1741`** — "`Dt.i64_floor_div` / `Dt.i64_cdiv` are `IO(..)`
   EFFECT SEAMS, so `_min_max` cannot call them" — false as of this change.
4. **`renderer/__init__.bend:326-327`** lists all ten `dtype.bend` seams, including the
   eight that no longer exist.
5. **`runtime/dtype.c:168-176` (`bf16_run`) still has no `isfinite` guard** that
   `dtype.py:230` has, and **`:97-98` still reads as if e5m2 were the only saturating
   format**. Both previously reported, both unchanged, both in a file a live unit owns.
6. **The JS lane's NaN collapse is untouched and unfixable from this side.**
   `comp.ts:539` hands the float to JavaScript, whose `NaN` is one value, so 0 of
   199,999 NaN payloads survive. No port-side definition repairs it.
7. **`ops_python.bend:274-278` (`w32`/`f32_of`) is still a duplicate** of
   `base.bend`'s `from_bits` and should import it. Not this file's; the edit is not
   made here.

## 7. REPRODUCE

```sh
python3 .agents/slop/lastlaw/run.py          # base / 3 disarms / 3 plants / PINV
zsh   .agents/slop/lastlaw/sweep.sh tinybendygrad   # whole-tree census, refuses an empty one
zsh   .agents/slop/substrate-check.sh tinybendygrad/dtype.bend
```

The gate's two lanes are DTYPEB's own generators, unmodified, because their oracles are
CPython calls and re-deriving them would have been a second place for an expectation to
rot: `.agents/slop/dtypeb/gen_i64.py` and `gen_fp8.py`.

## 8. FILES

`.agents/slop/lastlaw/` — `patch_dtype.py` (anchor-asserted, `--src:`, idempotent
assembly) · `tail-fp8-enc.bend.txt` (the encoder, ported from `dtype.c:44-87`) ·
`run.py` (base / disarm / plant / PINV, with both guards) · `sweep.sh` · `00-stub.md`

`tinybendygrad/dtype.bend` — **live, patched, 971 → 1132 lines (+184/-23)**.