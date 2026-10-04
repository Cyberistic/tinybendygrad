# CIDSWEEP — the rest of the tree, after `libclang.bend`'s 324 → 0

Unit `.agents/slop/cidsweep/`. Prefix **`CIDS-`**. Tool Bend 2.0.34 (`bin/bend`),
Apple clang 21.0.0. **Nothing committed.** `sh .agents/slop/cidsweep/gate.sh`
reproduces every number below; it exits 1 today, on one seam, on purpose.

```
== C1  dtype.c             10 registrations  10 guards  0 ctor ids   WARM  (2 builds)
== C2  sz.c                 2 registrations   2 guards  2 ctor ids  WARM  (3 builds)
== C3  libclang-tramp.c   325 registrations 325 guards  0 ctor ids   WARM  (1 build)
== C4  libclang-ffi.c      10 registrations   0 guards  0 ctor ids   COLD  (2 builds)  *** CIDS-1
== C5  .js seams           12 registrations   no #ifdef mechanism      BENIGN (node rc 0)
GATE FAIL  1 cold seam
```

---

## 1. EMPTY vs FILLED, per file, with denominators

**`.bend` bodies — 5 empty of 27,993 declared (`def` + `law`), across 140 files.**

| file | declared | EMPTY | site | what it is |
|---|---|---|---|---|
| `tinybendygrad/LAWS.bend` | 44 | 1 | `:393` `none_of() -> Maybe<&2, S.Dt>` | **`Maybe`'s nullary value** |
| `tinybendygrad/schedule/multi.bend` | 699 | 1 | `:2582` `ml_none() -> Maybe<&2, U32>` | **`Maybe`'s nullary value** |
| `tinybendygrad/codegen/decomp/dtype.bend` | 289 | 1 | `:2064` `graph_rewrite.wall` | **documented wall** — the rewrite half's refusal |
| `tinybendygrad/engine/worker.bend` | 79 | 1 | `:417` `terminate_worker_pool` | **documented** in an 8-line comment above it |
| `tinybendygrad/tensor.bend` | 193 | 1 | `:453` `tn_init.none()` | **TODO(p3)** at `:451` — an unconstructible `F32` literal |

**`0 of the 5 is a silent hole.** Two are `None{}` in a `Maybe<…>` position, which
is the type's own constructor and a *legal value*; three carry their wall in the
source above them.

**`.c` seams — 0 empty of 371 function definitions.** `dtype.c` 0/21, `sz.c` 0/6,
`libclang-tramp.c` 0/330, `libclang-ffi.c` 0/14. **`.js` seams — 0 empty** of 16
`function` decls and 6 arrows across `dtype.js`/`sz.js`.

### 1a. THE 324 WERE NEVER "EMPTY BODIES" AND THAT CHANGES THE CLAIM

Re-derived from the pre-fill emitter (`.agents/slop/ag-emit.bin`, run to
`$TMPDIR`, **63,334 B — CLANGFILL.md's byte count is right**):

```
raw.bend   laws: 0    '  None{}$' bodies: 324
```

Every one read:

```bend
def clang_createIndex(excludeDeclarationsFromPCH: I32, displayDiagnostics: I32) -> Maybe<&2, CXIndex>:
  None{}
```

**324 of 324 return `Maybe<&2, T>`.** So `None{}` there was a **type-correct
`Option.None` value**, and what made them "declared-but-unimplemented" is the
`law` binding, not the body: **a law whose body is a constant refusal.** The fill
was real and correct — but "324 empty bodies → 0" and "324 laws that did nothing
but refuse → 0" are different claims about the same 324 bytes, and only the second
is what the fix changed. Counting `None{}` as an *empty body* is a **false
positive the moment the return type is `Maybe`/`Option`**, and my own first census
fell into a worse version of it (below).

## 2. UNGUARDED `io_eff(CID(…))` REGISTRATIONS, per file, with denominators

| seam | registrations | unguarded | guards | constructor ids named | covered? |
|---|---|---|---|---|---|
| `tinybendygrad/runtime/dtype.c` | 10 | **0** | 10 | 0 | n/a |
| `tinybendygrad/runtime/sz.c` | 2 | **0** | 2 | `CID(Nil)` `:67`, `CID(Con)` `:69` | **yes**, both in `#ifdef CID(Sz.read_dir)` `:26–90` |
| `.agents/slop/clangshim/libclang-tramp.c` | 325 | **0** | 325 | `CID(Unit)` ×37, `CID(SCon)` ×2 | **NO — see CIDS-2** |
| `.agents/slop/clangshim/libclang-ffi.c` | 10 | **10** | **0** | 0 | **CIDS-1** |
| `tinybendygrad/runtime/dtype.js` | 10 | 10 | — | — | no `#ifdef` exists (CIDS-3) |
| `tinybendygrad/runtime/sz.js` | 2 | 2 | — | — | no `#ifdef` exists (CIDS-3) |
| `.bend` files | **0** | 0 | — | — | see CIDS-4 |

**`.c` lane total: 337 guarded, 10 unguarded.**

`langs/c/core.c` (2 sites) is **not a project seam** — it is bend's own vendored
runtime and it is **not** what gets pasted. Measured: `io_args_use` appears **0**
times in every emit while `io_eff(CID_IO_PRINT, …)` appears once, i.e. bend's
emitter demand-filters its *own* registrations. Its `#ifdef CID_CON` at `:7102`
is the same idiom, from the compiler's own source.

## 3. WHICH SITES ARE REAL DEFECTS, AND THE BUILD THAT PROVED IT

Every verdict below is `bend -o` **then `cc -fsyntax-only` on the emit**.
`bend -o` was **rc 0 in all 12 builds**, before and after every fix — it cannot
see this class at all.

| build | reaches | `bend -o` | `cc` | registrations landing (`cc -E`) |
|---|---|---|---|---|
| dtype: one seam | `Dt.fp8_from` | rc 0 | **rc 0** | **1** — `io_eff(14, fp8_from_run, 0)` out of 10 sites in the emit |
| dtype: no seam | — | rc 0 | **rc 0** | 0 (`dtype.c` not pasted at all) |
| sz: nothing | — | rc 0 | **rc 0** | 0 |
| sz: `Sz.is_dir` | 1 law | rc 0 | **rc 0** | **1** — `io_eff(15, sz_is_dir_run, 0)` |
| sz: `Sz.read_dir` | 1 law | rc 0 | **rc 0** | **1** — `io_eff(16, sz_read_dir_run, 0)` |
| sz: full `sz.bend` | both | rc 0 (119,097 L, 51 `CID_*`) | **rc 0** | both, ids 44/45 — and a real 287 KB binary links and runs rc 0 |
| libclang: one **tramp** effect | 1 law | rc 0 | **rc 0** | 1 — and `libclang-ffi.c` is **not pasted** |
| libclang: one **ffi** effect | 1 law | rc 0 | **rc 1, 14 errors** | **10 attempted, 9 literal undeclared `CID_` names** |

### CIDS-1 — `libclang-ffi.c:271-280`, **10 unguarded registrations. LIVE DEFECT.**

The build that reaches **one** `libclang-ffi.c` effect (`probe-libclang-ffi-one.bend`,
calling only `Clang_version`). `cc`'s **first** error is a red herring —

```
emit.c:2985:10: fatal error: 'fixture.h' file not found
```

which is only the missing `-I .agents/slop/clangshim`. **A result that contradicts
the tool's own error message is a suspect result**, so with `-I` supplied:

```
emit.c:3197:10: error: use of undeclared identifier 'CID_…_LIBCLANG_TYPE_REPORT';
                    did you mean 'WL_FID…_LIBCLANG_CLANG_VERSION'?
   … 9 distinct undeclared ids: TYPE_REPORT FIELD_REPORT FIELD_OFFSET_UNKNOWN
     FIELD_NAME FIELD_SPELL RECORD_WORDS RECORD_REPORT PAIR_SIZE LOADED_DYLIB
```

The emit defines **15** `CID_` macros and the only libclang one is `CLANG_VERSION`.

**The fix is `libclang-tramp.c`'s own idiom, 15 lines above it in the same unit.**
Applied as a patch, re-run through the whole pipeline on a scratch copy:

| | before | after |
|---|---|---|
| `cc -fsyntax-only` | **rc 1, 9 errors** | **rc 0, 0 errors** |
| registrations landing | **10** | **1** — `io_eff(14, Clang_version_run, 0)` |

The registration that *is* reached still registers, so this is not a
compiles-but-silently-fails-to-register guard.

**The defect is ONE-DIRECTIONAL, not symmetric.** A build reaching only a *tramp*
effect does **not** paste `libclang-ffi.c` (`Type_report_run` occurrences: **0**),
because bend's `import` is **per-def**: the file is pasted when a law that imports
it is *emitted*, not when the module is in the graph. So the fix has to cover only
the "reaches a strict non-empty subset of the 10" case. That is the same mechanism
that makes `dtype.c`'s three pure bend defs (`Dt.bf16`, `Dt.fp16`, `Dt.fp8_to` —
`dtype.bend:593/720/849`, no `import`) harmless despite being 3 of its 10
registrations.

### CIDS-2 — `libclang-tramp.c`, **39 constructor uses in `_run` bodies, 0 guarded. LATENT.**

The 325 guards cover the *registrations*. They do **not** cover the
`term_pak(CID(Unit), 0)` ×37 and `CID(SCon)` ×2 inside the `_run` bodies, and the
whole file is pasted whenever any tramp law is reached.

It is **latent, not live**, and only because of an accident worth naming: the ids
it happens to use are in the **always-allocated** base set — the same 14
`CID_*` appear in a build that reaches *nothing*
(`CID_CHR CID_DONE CID_EMIT CID_FAIL CID_FALSE CID_HALT CID_IO_PRINT CID_NONE
CID_SCON CID_SNIL CID_SOME CID_TRUE CID_TUPLE CID_UNIT CID_WCON`). `CID_NIL` and
`CID_CON` are **absent from that set** in every build I measured.

**PLANT, so this is falsifiable rather than asserted.** One `term_pak(CID_UNIT, 0)`
in the one-tramp emit changed to `CID_NIL`:

```
BASELINE  cc rc=0  errors=0
PLANTED   cc rc=1  errors=1
  emit.c:3571:19: error: use of undeclared identifier 'CID_NIL'
```

So the one-step-later undeclared-*function* failure SZLANE documented for `sz.c`
is reachable in the tramp file the moment a packer names a non-base constructor.
`sz.c` is right to guard its `CID(Nil)`/`CID(Con)` **as a group**; `libclang-tramp.c`
guards per-registration and would need the group form for this to be closed.

### CIDS-3 — the `.js` seams. **BENIGN, and I rebuilt SZLANE's claim instead of citing it.**

SZLANE §3b says the `.js` files are not the same defect. I measured it rather than
trusting it, because a citation is not a binding.

`bend -o out.js` on the one-dtype-seam probe: **`#ifdef` 0, `#endif` 0,
`defined(` 0** — the JS emit has no conditional-compilation mechanism, so
`#ifdef` there would be a syntax error. And `CID(x)` becomes a **string key**
into a table:

```js
function io_eff(k, run, need) { if (k in $0eff) { throw … } $0eff[k] = { run, need }; }
io_eff("../../../tinybendygrad/dtype.Dt.bf16", dtype_bf16);   // ×10, none guarded
```

An unreached registration is an **unused table entry**, not an undefined
identifier. The one-`Sz.is_dir` JS emit registers **both** sz effects unguarded and
`node` still prints `SZLANE is_dir(.) = 1  [OK]`, rc 0. `node --check` passes.
**SZLANE §3b is correct.** Do not "consistently" guard the `.js` files.

**The JS lane's own failure mode, which SZLANE did not name:** its only
extra-registration failure is the `throw` on a **duplicate key**, and `dtype.js`
and `sz.js` write the same `$0eff`. A C lane cannot hit this (C overwrites a slot).
No duplicate exists today; the mechanism is named, not a live instance.

### CIDS-4 — **there are ZERO `io_eff(CID(…))` registrations in any `.bend` file.**

`nvdev.bend` has exactly one hit and it is **`nvdev.bend:66`, inside a comment**:
`#  RESOLVE -- real \`io_eff(CID(...), run, need)\` registrations and real C.`
SZLANE §3b's table row *"`nvdev.bend` | 1 | no"* counted that comment as a site.
**Stale citation, class: a name/comment counted as a binding.**

## 4. WHAT I FIXED, AND WHAT I DID NOT

**Fixed: nothing in the live tree.** Every candidate site is forbidden to me —
`tinybendygrad/**`, `runtime/dtype.{c,js}`, `runtime/sz.c`, and
`.agents/slop/clangshim/` are all another unit's. So the CIDS-1 repair ships as a
**patch plus a proven verification**, for the owning unit to apply:

- `.agents/slop/cidsweep/libclang-ffi-CIDS-1.patch` — 10 guards, `libclang-ffi.c:271-280`.
  Verified by applying it to a scratch copy and rebuilding: **9 errors → 0,
  10 registrations → 1.**

**Reported, not fixed:**

| # | site | why not |
|---|---|---|
| **CIDS-1** | `clangshim/libclang-ffi.c:271-280` | another unit's slop tree; patch + proof supplied |
| **CIDS-2** | `clangshim/libclang-tramp.c` `:646…4312` (39 sites) | same tree. Fix needs the **group** form, i.e. a restructure of 325 guards — the owning unit's call |
| CIDS-3 | `tinybendygrad/runtime/{dtype,sz}.js` | **no fix exists** — `#ifdef` is a syntax error in JS. Benign by mechanism (built) |
| CIDS-4 | `tinybendygrad/runtime/support/nv/nvdev.bend:66` | a comment. Nothing to fix; the *citation* is the defect |
| — | `langs/c/core.c:7518`, `:7533` | not a seam. Bend demand-filters its own registrations (measured: 0 occurrences in the emit) |
| — | `dtype.bend:838-843` `fp8_decode.pre` → `fp8_decode.nz` | **not a finding.** One build rejected it as "a filled definition"; ten minutes later it built rc 0. `dtype.bend` is a live unit's file and this is agent-core.md's *concurrent mid-edit* signature, not a defect |

## 5. REFUSAL SENTINELS AND NULL ARGUMENTS — where it can be measured

Re-ran `python3 .agents/slop/clangfill/gate.py` (not cited — re-run):

```
ROWS 324   EXECUTED 320   ungated 4 (faulted 4, rc0-no-row 0)
ANSWER CLASSES  box 90  int 144  ptr 40  void 41  cstr 4  double 1
ANSWER a refusal sentinel 175   a non-sentinel value 145
ROWS called with at least one NULL argument 256
```

**175 of 320 executed rows (55%) answer a refusal sentinel, and 256 of 320 (80%)
ran with at least one NULL argument.** So "0 empty bodies" in `libclang.bend` is
**not** "the bodies work": a filled body called with a null object that answers
NULL has executed and has not been shown to bind.

**`dtype.c` (10) and `sz.c` (2): NOT MEASURED, and I will not type a number.** There
is no row harness on either seam. What I can say is bounded: sz's compiled binary
links (287 KB), runs rc 0, and in the isolated builds each seam registers exactly
the one effect reached — but I could not get `szbin` to print rows on an ad-hoc
fixture (`sz.bend:1595` `sz.show` prints nothing for an empty row set, which is
`sz.py`'s documented behaviour, not a failure), so **sz's and dtype's refusal rates
are unknown, not zero.**

## 6. RULES, with the instrument beside each

**CIDS-1 — a `None{}` census must check the RETURN TYPE, not the token.** 460 of my
own first census's 478 "empty bodies" were `case _: None{}`, a **match arm**. The
detector that survives: a whole-line `None{}` whose immediately-preceding non-blank
line ends in `:` and is not `case`/`match`. Census v1's 478 → **5**, and 5 is
already split into 2 constructor values + 3 documented walls. *(`census2.py`)*

**CIDS-2 — a guard on the registration is not a guard on the seam.** The unit that
belongs inside `#ifdef CID(…)` is **the C group implementing one effect**, because
a packer's `CID(Nil)` is demand-allocated on the same terms as the effect id.
*(`cidcensus.py`; CIDS-1 above)*

**CIDS-3 — `bend -o out.c` and `bend -o binary` are DIFFERENT instruments, and
`cc -fsyntax-only` on the emit is a third.** All 12 builds here are rc 0 under
`bend -o`. `cc` is the only one that saw CIDS-1. *(One build rejected on
`fp8_decode.nz` and ten minutes later built rc 0 — a concurrent editor, so a single
red build is not a verdict either.)*

**CIDS-4 — bend pastes a foreign `.c` per-DEF, not per-MODULE.** A module in the
import graph whose laws are all unreached contributes **nothing** to the emit. This
is why `dtype.c`'s 3 pure-def registrations, `libclang-ffi.c` in a tramp-only
build, and `sz.c` in the reaches-nothing build are all absent rather than broken —
and it is why "the file is imported" is not evidence the file is in the build.

**CIDS-5 — the shim's blindness is not where it was claimed.** `#ifdef` does not
macro-expand its operand, so `#define CID(x) 0` makes every `#ifdef CID(…)` TRUE:
the shim cannot report a missing guard *or* hide one. Its real blind spot is
`bend -o`'s rc — a number that cannot fail for this class. So the gate must be a
build per seam. *(SZLANE §5 reached the same conclusion by a different route; the
`fixture.h` red herring in §3 above is the sharpest example I have of a tool's
first error naming something other than the defect.)*

## 7. NOT MINE / NOT DONE

- `substrate-check.sh`, `runtime/dtype.{c,js}`, `runtime/sz.c`, `sz.bend`,
  `dtype.bend`, `libclang.bend`, `helpers.bend`, `base.bend`, `graphcmp*`,
  `nvdev.bend`, `uop/**`, `renderer/**`, `LAWS/**` — **read only, unmodified.**
- Nothing committed. `.agents/slop/cidsweep/` is the only thing written.
- `gate.sh` exits **1** today. That is the finding, not a broken gate: C1/C2/C3/C5
  are green and C4 is red because CIDS-1 is unfixed by design.
- **A stale citation in my own unit's brief, for the ledger:** CLANGFILL.md
  describes `.agents/slop/ag-emit.bin` as emitting text. It is a **Mach-O arm64
  executable** (`file` says so) that prints the emit on stdout — so the redirect in
  CLANGFILL.md §1 works, but "the generator" being a binary and not a script is
  worth knowing before anyone greps it for `law `.
