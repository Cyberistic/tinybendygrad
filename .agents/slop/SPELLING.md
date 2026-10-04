# SPELLING — one 64-bit spelling for this tree, and what it costs

Unit: `.agents/slop/spelling/`. Prefix **`S-`**. Nothing committed.

```
python3 .agents/slop/spelling/roundtrip.py --plants   # generator vs product, 5 controls
node    .agents/slop/spelling/jslane-probe.js         # not standalone; see §5
```

---

## 1. THE RULING

**`H.I64` — `helpers.bend:1639-1640`, `type I64 is Data: I64{hi: U32, lo: U32}` — is the
tree's canonical 64-bit value. It is the only one of the three that is a value.**

| | where | uses | has arithmetic? |
|---|---|---|---|
| **`H.I64`, a signed pair** | `helpers.bend:1639` | **678 qualified uses, 41 files** | **40 defs** — `i64_add` `:1720`, `i64_sub` `:1725`, `i64_div` `:1969`, `i64_mod` `:2062`, `i64_shl` `:1819`, `i64_neg` `:1785`, `i64_dec` `:2060`, `i64_cmp` `:1688` |
| two `U32` halves over FFI | `runtime/dtype.c:205`, `runtime/dtype.js:136` | one seam, 7 defs | none — **it is not a type.** `helpers.bend:2099` already names it: `data64(x: I64) -> U32 & U32` |
| nullary `I64`/`U64`/`F64` | `runtime/autogen/libclang.bend:95,98,101` | **13 uses, 1 file, 0 elsewhere** | **none.** `I64{}` has no constructor that carries a value |

**⚠ THE TWO COUNTS IN THE `H.I64` ROW ARE NOW WRONG, AND THE CITATIONS ARE NOT.**
Re-measured 2026-10-04 by `notes-sweep`: **678 qualified `H.I64` uses is ✅ still exactly
678**, but the file count is **39, not 41** (`grep -rl 'H\.I64' tinybendygrad --include='*.bend' | wc -l`).
The **`40 defs`** is stale and was not reproduced: `grep -cE '^def i64_[a-z0-9_]*\('
tinybendygrad/helpers.bend` reads **23**, and "40" would have to count nested `def`s too —
**STALE — not re-measured, not guessed.** **So: the numerator that mattered (678 uses)
held, the smaller denominator next to it did not, and the "40 defs" is unverified.** Same
shape as `agent-core.md`'s `14 of the 136`. Also note the `libclang.bend:95,98,101`
citation is now **wrong** — those lines are a `Ty` record, a `CXIdxLoc{}` and a blank;
**STALE — not re-measured** which lines now carry the nullary uses (16 tokens: `I64` 11,
`U64` 4, `F64` 1).

**THE `i64_*` LINE NUMBERS RE-VERIFIED 2026-10-04 by `notes-sweep` — ALL EIGHT ARE STILL
CORRECT**, which is worth stating because `helpers.bend` is four units' code and this is the
only note in the tree that cites it by line. `i64_cmp` `:1688`, `i64_add` `:1720`,
`i64_sub` `:1725`, `i64_neg` `:1785`, `i64_shl` `:1819`, `i64_div` `:1969`, `i64_dec`
`:2060`, `i64_mod` `:2062`, and `data64` `:2099` (`-> U32 & U32`, as this row says). ✅
**The two `runtime/dtype.*` citations were NOT re-verified — `runtime/dtype.js` is owned by
another live unit that is editing it right now, and `notes-sweep` will not certify a line in
a file that is moving. STALE by construction; re-read before citing.**

The middle row is not a rival at all: `dtype.c:205` already *opens* it as
`ctr_take(e, t, 2, o)` on an `H.I64`, so the two halves are `H.I64`'s two **fields** in
transport. The e2e `f64` stage is the same fact one level down — a `double` in a WebGPU
buffer is two `U32` words, and `runs/e2e/e2e-f64.txt` measures `64/64 u32 words,
diff bytes: 0`. That is a wire format, not a Bend type.

**So there are two things, not three**, and only one of them is a value.

## 2. WHAT THE CHOICE COSTS — four bills, all measured

1. **Canonicalisation of `libclang.bend` is IMPOSSIBLE, not merely expensive.** Five of
   the 16 uses cannot be spelled canonically: `helpers.bend:1633-1635` says the value is "a signed 64-bit int … the pair of
   halves in two's complement", and `dtype.bend:384-386` says so again —
   "an I64 is a SIGNED pair, so `[2**64-1]` has no image". So the four `U64` uses
   (`libclang.bend:641,668,1142,1178`) have no canonical image, and `F64`
   (`:1181`) has no canonical pair in `helpers.bend` at all — `helpers.bend:1653`,
   `:1657` and `:2099` give `lo32`/`hi32`/`data64` and there is no `f64_to_data`. **The third spelling stays.** It is
   deleted only by a 64-bit *unsigned* pair and a 64-bit float pair existing first.
2. **Naming the nullary `I64` next to the canonical `I64` is a hazard, and renaming it
   does NOT close the hazard** — measured, not assumed. Adding `import ../../helpers.bend
   as H` to `libclang.bend` and keeping the local `type I64 is Data` compiles clean
   (`SOME PROOFS FAIL`, the same 11 foreign defs, nothing new): imports are namespaced,
   so `I64` and `H.I64` coexist. The `U32` wall was a *Base* collision, which is
   namespaces-blind — and that is exactly why the fix had to be about Base and not about
   spelling.
3. **Importing helpers into `libclang.bend` to use the canonical spelling would make it
   transitively depend on a 116 KB file** whose `--check-only` was already 0 bytes three
   times today (`W64-MILE.md:300-308`). A generated ABI table should not inherit that.
4. **What the ruling does buy**, measured: the 16 trampolines' signature column stops
   being a fourth, differently-shaped thing called `I64` with the same name and no
   algebra. The product's own header now says so, in the file, where a reader finds it.

## 3. THE GENERATED FILE COMPILES. IT DID NOT FAIL ON THE 64-BIT SPELLING.

**The briefed premise is FALSE and its citation is stale.** `agent-core.md:149` records
`runtime/autogen/libclang.bend` as `duplicate declaration: U32`, and this brief forwarded
it. Both are wrong as of now:

```
./bin/bend tinybendygrad/runtime/autogen/libclang.bend --check-only
  SOME PROOFS FAIL
  Error: 11 defs rely on unsafe or foreign code:      <- the FFI lane, not a duplicate
  bend -o out.c                                        -> rc 0, 151,040 bytes
  cc -O1 -I .agents/slop/clangshim -o run out.c ...    -> rc 0
  ./run                                                -> 13 rows, all correct
```

The `U32` wall is **real and already closed**: re-inserting `type U32 is Data` into the
product alone reproduces `duplicate declaration: U32` exactly (`PLANT-A`). And the three
nullary 64-bit declarations contribute **nothing** to any failure — deleting them makes
the file **worse**: `expected : a defined name / observed : I64` at
`libclang.bend:638`.

**What still stops it being RUN** (the real wall, and it is not 64-bit): all 11 FFI laws
import only `libclang-ffi.c`, and `references/bend/bend2/comp.ts:3385` demands a `.js`
import for every foreign def. `bend <file>` and `bend <file> -o out.js` both give
`a foreign def without a .js import: Loaded_dylib`; add an empty `.js` and it becomes
`bend: no effect registers Loaded_dylib` for each of the 11. **`bend -o out.c` is rc 0 and
`cc` links and runs it — the file COMPILES as C and CANNOT BE RUN.** `dtype.bend:577-578`
has both a `.c` and a `.js` import per seam; this lane has one.

## 4. THE FIX IS IN THE GENERATOR, AND THE GENERATOR REPRODUCES THE PRODUCT BYTE FOR BYTE

The `duplicate declaration` wall was closed with a **two-entry literal list** —
`DROPPED = ["type U32 …", "type Unit …"]` — which is "by hand", and a list the next ABI
width will not be on. Replaced with a rule:

* a name Base declares is never minted, read from `references/bend/bend2/base.bend`
  (`:9 Unit`, `:57 U32{data: Word(32n)}`, `:60 F32`) instead of listed;
* it runs **LAST**, after `EXTRA` has had its chance to mint, or the mint re-introduces
  what the rule removed (`PLANT-B[first]` measures that hole);
* it asserts on the way out, so it cannot be silently defeated.

```
$ python3 .agents/slop/clangshim/apply-port-lane.py --check
IN SYNC
$ python3 .agents/slop/spelling/roundtrip.py --plants
EMITTER  rc=0   raw=07383541c500c904c43d75738bc6d0fe/63334B/1298L
MINTED   60 distinct `type X is Data` names; the product carries none of ['U32', 'Unit']
BASE     PASS   rebuilt=04199adf44475397189de8aa36e4b943/71324B  product=04199adf44475397189de8aa36e4b943/71324B
PLANT-A[U32 ] PASS   -> bend rc=1  duplicate declaration: U32
PLANT-A[Unit] PASS   -> bend rc=1  duplicate declaration: Unit
DISARM-A PASS   the two-entry literal list rebuilds the SAME md5 as the derived rule: yes
PLANT-B  PASS   `F32` (a Base name, in neither the list nor EXTRA) appended to EXTRA -> not minted
PLANT-B[first] PASS   same plant, rule moved BEFORE the mint -> F32 SURVIVES (so LAST is load-bearing)
```

`rebuilt == product`, both by md5, on the same machine, from `ag-emit.bend` +
`apply-port-lane.py` alone. The product went `69800 -> 71324 B`
(`4c0b6a89… -> 04199adf…`) and **that change is header-only**: `bend -o` on the old and
new files emits **byte-identical C** (`cmp` clean) and both run 13 identical rows.

## 5. WHAT THE JS LANE MUST READ

`runtime/dtype.js:137` reads `p.fst` / `p.snd`. Measured by execution, on four fixtures
including `int64.min`, through the same JS lane and the same `H.I64`:

```
JS  argument keys = ["$","hi","lo"]
JS  argument      = {"$":"tinybendygrad/helpers.I64","hi":0,"lo":7}
JS  shipped i64_of(a)     = 0          (input was 7)
JS  shipped pack64(...)   = {"$":"Tuple","fst":0,"snd":0}
JS  is shipped the identity? false
JS  is named   the identity? true
```

`H.I64` crosses **by NAME**. `p.fst` and `p.snd` are both `undefined`,
`undefined >>> 0 === 0`, and **`i64_of` is identically 0 on 4 of 4 fixtures**, so
`Dt.i64_trunc` — the identity — is not the identity. `4/4`, including `hi = 7` and
`hi = 4294967295`; only `hi = 0` would have been an accidental pass.

> **THE REQUIREMENT (not mine to apply — `runtime/dtype.js` and `runtime/dtype.c` are the
> dtype ABI owner's):** the JS lane must read the canonical spelling's **field names
> `hi` / `lo`** — **in both directions**. `i64_of` must take `{hi, lo}`, and `pack64`
> must **return an `I64`, not `io_tup`**, because `io_tup` is `Tuple{fst, snd}` and the
> caller reads `{hi, lo}` (divergence 2, measured). Reading `hi`/`lo` is the whole fix
> and it is four characters per direction.

The discriminator needs **no oracle**: `i64_trunc` is the identity, so apply both
readings to the same bytes and exactly one of them is it.

## 6. PLANTS AND DISARMS — including two of my own controls that were not controls

| | what | moved | verdict |
|---|---|---|---|
| PLANT-A[U32] | `type U32 is Data` re-inserted into the **product alone** | bend rc=1, `duplicate declaration: U32` | PASS |
| PLANT-A[Unit] | same, one at a time | bend rc=1, `duplicate declaration: Unit` | PASS |
| DISARM-A | the derived rule **replaced by the two-entry literal list** | rebuilt md5 **identical** | PASS |
| PLANT-B | `F32` — a Base name in neither the list nor `EXTRA` — appended to `EXTRA` | not minted | PASS |
| PLANT-B[first] | same plant, rule **moved before** the mint | `F32` **survives** | PASS |
| PLANT-B (product) | nullary `I64`/`U64`/`F64` deleted, 13 uses kept | `expected : a defined name / observed : I64` | the premise, refuted |
| PLANT-C | `import ../../helpers.bend as H` added beside the local `I64` | **nothing** | namespaces are safe |

**Two of my own controls moved, and neither was a failed disarm — both were defects.**

* The first DISARM-A set `DROPPED = []`. That **removes the fix** rather than
  re-expressing it, and it reported FAIL with a 56-byte difference. A disarm is only a
  disarm after it has moved 0 *in fact* (`JSL2-5`).
* The first PLANT-B[first] **added** `drop_base_types` at the top of `fix()` while
  leaving the real call in place, so it moved nothing and reported FAIL. A control that
  proves nothing and reports FAIL looks exactly like a control that proves nothing and
  reports PASS.
* PLANT-A also failed its first form: planting both collisions and demanding `bend` name
  both. `bend` stops a batch parse at the **first** error (`agent-core.md:49-51`) and named
  only `Unit`. A control whose failure is the compiler's documented stopping behaviour
  cannot fail.
* And the probe itself refused to run twice before it ran at all: an ESM `import` in a
  file the emitted CJS scope inlines verbatim, and a `$TMPDIR` copy of the applier
  resolving `REPO` from its own location. Both **raised** rather than reported, which is
  the good kind.

## 7. WALLS, WITH `file:line`

| # | wall | where |
|---|---|---|
| S-1 | `bend <file>` and `-o out.js`: `a foreign def without a .js import: Loaded_dylib`, then `bend: no effect registers <k>` ×11. `-o out.c` is rc 0. | `.agents/slop/clangshim/ffi-lane.bend:28,34,40,46,52,58,64,70,76,82` (10 `.c` imports; `main` at `:88` has none, and `bend` names 11 defs); `references/bend/bend2/comp.ts:3385` |
| S-2 | `dtype.js` reads `p.fst`/`p.snd`; the record crosses as `{hi, lo}`; `i64_of ≡ 0`, the identity is not the identity, 4/4 | `runtime/dtype.js:137`; field names from `helpers.bend:1640`; probe `.agents/slop/spelling/jslane-probe.js` |
| S-3 | `pack64` returns `io_tup` = `Tuple{fst, snd}` where the caller reads `{hi, lo}` — the return direction diverges too | `runtime/dtype.js:140-143`, `io_tup` on `:142` |
| S-4 | `U64` and `F64` have **no canonical spelling**, so `libclang.bend`'s 13 uses cannot be canonicalised | `helpers.bend:1633-1635`; `tinybendygrad/dtype.bend:384-386`; `libclang.bend:641,668,1142,1178` (`U64`), `:1181` (`F64`) |
| S-5 | `agent-core.md:149`'s `duplicate declaration: U32` is **stale**: the wall was closed and the file now reports only its 11 foreign defs | `agent-core.md:149` vs `tinybendygrad/runtime/autogen/libclang.bend` today |
| S-6 | `renderer/amd/dsl.bend:64` cites `helpers.bend:1167` for `I64{hi: U32, lo: U32}`. Line 1167 is a comment about run emission; the declaration is at `:1639-1640` | `renderer/amd/dsl.bend:64` |
| S-7 | `ffi-lane.bend:20` points the reader at `.agents/slop/clangshim/cl-port-gate.sh`, which **does not exist**. The gate is `cl-port-gate.py` | `.agents/slop/clangshim/ffi-lane.bend:20` |

**BOTH S-6 AND S-7 RE-VERIFIED 2026-10-04 by `notes-sweep` — both are STILL TRUE, and the
defects they name are STILL LIVE.** Checked against the tree, not against a note:
`tinybendygrad/renderer/amd/dsl.bend:64` still reads
``# 2. `H.I64` EXISTS (helpers.bend:1167, `I64{hi: U32, lo: U32}`)``;
`helpers.bend:1167` is still the run-emission comment; and `helpers.bend:1639-1640` is
``type I64 is Data:`` / `I64{hi: U32, lo: U32}` — **the declaration, at the cited
correction.** `.agents/slop/clangshim/ffi-lane.bend:20` still names `cl-port-gate.sh`, and
`ls .agents/slop/clangshim/` shows `cl-port-gate.py` and **no `.sh`**.
**Neither file is this unit's to edit (`.bend` is out of scope), so both are reported
unfixed — which is the correct outcome for a note whose content is a true claim about a
defect someone else owns.**
| S-8 | `a : H.I64 <- …` inside a `do IO<Unit>:` block does not parse on 2.0.34 — `expected : … @k:(@_:H.I64 -> IO.OP<R>) -> IO.OP<R>`. Inline the argument instead | measured in `$TMPDIR`, `tinybendygrad/probe.bend` |
| S-9 | the 16 that "CANNOT be executed" (`libclang.bend`'s own old header, `:18-19`) — **15 of them do**: they compile, link, run and match CPython. The header text was corrected | `.agents/slop/W64-MILE.md:100-104`; header now says so |
| S-10 | `clang_getOffsetOfBase` is absent from libclang 17.0.0 (`nm -gU` → 0) against `CINDEX_VERSION_MINOR = 64`. Version skew, not a language wall | `tinygrad/runtime/autogen/libclang.py`; not re-measured here |
| S-11 | **A `file:line` INTO A GENERATED BODY is invalidated by a change to that file's HEADER.** This unit's header-only repair moved `type I64 is Data` from `:77` to `:98` and `clang_getEnumConstantDeclValue` from `:617` to `:638` — **+21 lines, every downstream def shifted, nothing semantic.** The brief's positions were correct when written and are wrong now, and the emitted C is byte-identical across both. **Cite a generated body by NAME, or the citation is a timestamp.** | measured: `69800 -> 71324 B` moved every body def by 21 lines |

## 8. NOT MINE, REPORTED

- `tinybendygrad/runtime/dtype.js` and `runtime/dtype.c` are **byte-unchanged** by this
  unit. S-2/S-3 are a requirement for their owner.
- `runtime/autogen/libclang.bend` changed, but **through its generator** — the file is a
  product and the change is header-only (byte-identical emitted C). `apply-port-lane.py
  --check` says `IN SYNC`.
- `.agents/slop/clangshim/clangshim-gen.py` and `libclang-ffi.c` are another unit's and
  were **not read for edit and not edited**. S-1 is theirs.