# ABI4CHECK — IS `checks/abi4_gate.py`'s `NEEDS/FIXES` TABLE A MEASUREMENT OF `dtype.bend` OR OF `dtype.js`?

Rule prefix: **`ABI4CHK-`**. Instrument: `checks/abi4_gate.py` (98 rows × 15 arms × 1 lane).
Artifacts, all in this directory: `now-venv.{stdout,stderr,rc}`, `now-py3.{stdout,stderr,rc}`,
`135bf0204-run.{out,err,rc}`, `abi4-gate-at-135bf0204.rows`, `abi4_gate.135bf0204.py`,
`table-now.rows`, `at-135bf0204/`, `now/`, `belt-now/`.

Reproduce: `.venv/bin/python checks/abi4_gate.py`. `checks/abi4_gate.py` was **NOT EDITED** —
`git diff HEAD -- checks/abi4_gate.py` is empty. The three scripts here read it:
`probe-measure.py` (the lane assertion, ABI4CHK-3), `plant-measure.py` (the same assertion plus the
plants, ABI4CHK-6), `lane-belt.py` (ABI4CHK-5), and `table-now.py`, which calls the gate's **own
`main()`** (ABI4CHK-7).

**THE ANSWER IS #2: THE SEAMS ARE PURE BEND. THERE ARE NO TWO LANES. THE TABLE IS A MEASUREMENT OF
`tinybendygrad/dtype.bend`, AND `tinybendygrad/runtime/dtype.js` IS NOT IN IT.**

---

## ABI4CHK-1 — THE VERDICT BEFORE, UNDER BOTH INTERPRETERS, VERBATIM

This is the first thing on disk. Both interpreters produce the **same** answer, on the **same**
exception, which is itself the finding: the two-site split `abifix` measured on `abi_gate.py` is
**gone**, and what replaced it is a stale FIXTURE, not a stale CONSTANT.

    $ .venv/bin/python checks/abi4_gate.py          # Python 3.12.10
    (stdout: 0 bytes)
    (stderr: 13 lines)
    no backend for arm shipped: rc=1

    SOME PROOFS FAIL
    Error:
    - expected : @-R:Type -> @k:(@_:F32 -> IO.OP<R>) -> IO.OP<R>
    - observed : F32
    Location: main
    4 |   do IO<Unit>:
    5>|     v0 : F32 <- D.Dt.fp16(1.5)
      |                 ^^^^^^^^^^^^^^
    6 |     IO.print("F32ROW abi4_fp16_1p5 = " ++ F32.show(v0))
    bend 2.0.35 is available: run bend update
    exit=1

    $ python3 checks/abi4_gate.py                    # Python 3.14.6
    (stdout: 0 bytes)   (stderr: byte-identical, 13 lines)   exit=1

**`rc=1` is not a red gate, and it is not a green one either.** `run()` at
`checks/abi4_gate.py:305` `sys.exit`s on the FIRST arm, `shipped`. The 15 arms, the 98 rows, the
`NEEDS/FIXES` table and the 16-check verdict are **never reached**. It dies on the first of 98 binds
because `emit()` at `:267` writes `v{i} : {show} <- {expr}` and `tinybendygrad/dtype.bend:748` is now
`def Dt.fp16(+x: F32) -> F32:` — **a pure function, so an effect bind does not typecheck.**

> **So this gate cannot reach a verdict today, and the reason is NOT the lane disconnection. Two
> independent blockers, in this order, and the first one hides the second.**

## ABI4CHK-2 — BLOCKER ONE: A STALE FIXTURE (the bind), AND IT IS THE SAME CLASS AS `abi_gate.py`'S

`dtype.bend`'s four seams changed from effects to pure functions. Measured, side by side:

| seam | at `135bf0204` | at `HEAD` | line now |
|---|---|---|---|
| `Dt.bf16` | `def Dt.bf16(bits: U32) -> IO(F32):` | `def Dt.bf16(+bits: U32) -> F32:` | `dtype.bend:607` |
| `Dt.fp16` | `def Dt.fp16(x: F32) -> IO(F32):` | `def Dt.fp16(+x: F32) -> F32:` | `dtype.bend:748` |
| `Dt.fp8_from` | `def Dt.fp8_from(bits: U32, kind: U32) -> IO(U32):` | `def Dt.fp8_from(bits: U32, +kind: U32) -> U32:` | `dtype.bend:1060` |
| `Dt.fp8_to` | `def Dt.fp8_to(bits: U32, kind: U32) -> IO(F32):` | `def Dt.fp8_to(bits: U32, +kind: U32) -> F32:` | `dtype.bend:916` |

**`abifix`'s ABIFIX-8 holds here exactly, and the parent is right that the toolchain is not broken.**
`bind-eq.probe.js` in `now/` is a **1,673-line emitted backend that runs 98/98 rows** under node,
compiled from a probe that differs from the gate's by one character per bind. **The port emits rows.**

This is the **FOURTH** stale fixture of this class in these two files (`ab_gate.py` counted three:
`<-` vs `=`, the deleted `abi.json`, the wrong `parents[n]`). It is not a new class. It is the same
class, in the neighbouring file, one commit later.

## ABI4CHK-3 — BLOCKER TWO: THE LANE IS NOT IN THE ARTIFACT. ASSERTED **BEFORE** PLANTING.

`lane-belt.py` and `plant-measure.py` both do this in the order the brief demands: **the lane
assertion runs before any arm is planted, and it is what decides the answer.**

Shipped probe, compiled, on the live tree, tokens counted in the EMITTED artifact:

| token | `135bf0204` | **`HEAD`** | `dtype.js` on disk |
|---|---|---|---|
| `of32` | 5 | **0** | 5 |
| `bits32` | 4 | **0** | 4 |
| `i64_of` | 18 | **0** | 18 |
| `pack64` | 7 | **0** | 7 |
| `fp8_decode` | 2 | 31 | 2 |
| `dtype.js` | **1** | **0** | — |
| `dtype.c` | **3** | **0** | — |

`of32` **0** and `bits32` **0** are the load-bearing numbers. Those are the two converters all three
sites (`SITES` at `:146-148`), all three plants (`PLANTS` at `:180-181`) and all three disarms
(`DISARMS` at `:182-183`) are written in. **The tokens the plants edit are in the artifact zero times,
so no plant and no break can reach them.** `dtype.js` going 1 → 0 is the direct name of the seam.

And the seam, in the source:

    git grep -c 'import "\./runtime/dtype' -- 'tinybendygrad/*.bend'
      135bf0204:  21 lines across 2 files   (20 in dtype.bend, 1 a comment in mixin/dtype.bend)
      HEAD:        2 lines across 2 files, and BOTH survivors are PROSE INSIDE COMMENTS
                  (tinybendygrad/mixin/dtype.bend:63, tinybendygrad/uop/fold.bend:2708)
      HEAD seam imports: 0

At `135bf0204` the seam's BODY WAS the FFI into the lane — `dtype.bend:577-614` was ten pairs of
`import "./runtime/dtype.c"` / `import "./runtime/dtype.js"` inside the seam signatures. That is why
the lane was in the artifact then, and it is why the plants were live then.

## ABI4CHK-4 — WHAT THE TABLE IS A FUNCTION OF. POSITIVELY IDENTIFIED, NOT INFERRED.

`now/bind-eq.probe.js:813`:

    function $tinybendygrad$047dtype$fp8_decode$(_x_0, _kind_0) {

`$tinybendygrad$047dtype$fp8_decode$` is the mangling of `tinybendygrad/dtype/fp8_decode` — a
namespace `bend` synthesised from **`tinybendygrad/dtype.bend`'s own `def fp8_decode.*` helpers at
`dtype.bend:807-850`.** The JS lane's `function fp8_decode(x, kind)` at
`tinybendygrad/runtime/dtype.js:94` occurs **zero** times in the artifact.

    dtype.bend:  fp8_decode x32   of32 x0   bits32 x0
    dtype.js:    fp8_decode x2    of32 x5   bits32 x4      <- the lane, present and correct, READ BY NOTHING

**So: the table is a measurement of `tinybendygrad/dtype.bend`.** `tinybendygrad/runtime/dtype.js`
is a **live, correct, 211-line file that no `.bend` file imports** — it is not the subject, and it is
not evidence about the subject.

## ABI4CHK-5 — THE BELT: TWO METHODS THAT DO NOT SHARE AN ASSUMPTION

The lane assertion above counts TOKENS, and "the plants moved 0" is downstream of the same fact.
**One tokenizer, one assumption, is not a belt.** So the lane is attacked two more ways, neither of
which reads a token (`belt-now/`):

| plant into `runtime/dtype.js` | bend | node | rows | moved | identical? |
|---|---|---|---|---|---|
| `THIS_IS_NOT_JS ((( error` | rc 0 | rc 0 | 98/98 | 0 | **yes** |
| `throw new Error("LANE_REACHED");` | rc 0 | **rc 0** | 98/98 | 0 | **yes** |
| `const LANE_REACHED_MARKER_7a3f = 1;` | rc 0 | rc 0 | 98/98 | 0 | **yes** |

**`B2` is the belt that closes it.** A top-level `throw` in `dtype.js` is valid JS that compiles;
the only way node exits 0 having printed 98 rows is that **the module never executed**. That is a
fact about execution, not about text, and it shares no assumption with the count. `B1` says the same
about compilation. Three methods, one answer: **`dtype.js` is never loaded.**

## ABI4CHK-6 — THE PLANTS: MOVING AT `135bf0204`, NOT MOVING NOW. **BOTH HALVES.**

The instrument is the gate's own bytes at each tree, imported, never retyped
(`plant-measure.py`). The tree is a `git archive` of `135bf0204` with the shared compiler symlinked in
(read-only; `references/bend/bend2` was neither moved nor checked out).

**FIRST HALF — `135bf0204`, plants 30 / 8 / 40. The gate is runnable there and was:**

    $ .venv/bin/python .agents/slop/abi4check/abi4_gate.135bf0204.py     # unmodified, own location
    [bounded] WITHIN-LIMITS  rc=0  peak-RSS=592 MB  104s
    $ diff <that> <(git show 135bf0204:.agents/slop/abi4/abi4-gate.txt)
    BYTE-IDENTICAL TO abi4-gate.txt

| arm | at `135bf0204` | **at `HEAD`** |
|---|---|---|
| DISARM A / B / C | 0 / 0 / 0 | 0 / 0 / 0 |
| **PLANT A** | **30 / 98** | **0 / 98** |
| **PLANT B** | **8 / 98** | **0 / 98** |
| **PLANT C** | **40 / 98** | **0 / 98** |
| bind that compiles | `<-` | `=` |
| `gate rc` | **0** | **1** |

**ANSWER 4 IS REFUTED. The plants fired at `135bf0204` on this side, reproducibly, and their
moved-counts are byte-identical to the committed artifact.**

**THE BIND AND THE SEAM MOVED TOGETHER — A TWO-WAY DOOR.** `=` on the `135bf0204` tree is
`NO BACKEND`, `<-` on `HEAD` is `NO BACKEND`. The probe is correct on each tree and dead on the other.
**This gate is dialect-locked to its own commit**, which is the deepest form of the staleness: it is
not merely that the constants expired, it is that the *language the gate speaks* did.

## ABI4CHK-7 — THE SAME TABLE, RUN TWICE. THIS IS THE ANSWER IN ONE LINE.

`table-now.rows` is `checks/abi4_gate.py`'s **own `main()`**, on the live tree, with **exactly one**
thing changed — `emit()`'s bind character, the stale FIXTURE of ABI4CHK-2, not the subject:

| | `135bf0204` | **`HEAD`** |
|---|---|---|
| `shipped` | 98/98 agree | 98/98 agree |
| **every one of the other 14 arms** | 58–98/98 agree | **98/98 agree** |
| `NEEDS` A / B / C | 30 / 10 / 40 | **0 / 0 / 0** |
| `FIXES` A / B / C | 0 / 10 / 10 | **0 / 0 / 0** |
| `PLANT A/B/C` moved | 30 / 8 / 40 | **0 / 0 / 0** |
| gate rc | 0 | 1 (6 FAIL) |

**All fifteen arms are now the same bytes. `NEEDS` and `FIXES` are empty, and every number the
ABI4-7 report quotes — `NEEDS 10/40/30`, `FIXES 10/10/0` — is gone.**

## ABI4CHK-8 — THE TWELFTH INSTANCE, AND IT IS THE PUREST ONE YET: **THE PASSES ARE CONSTANTS**

Sixteen checks, **9 PASS / 6 FAIL / and every one of those 9 PASSes holds without the lane existing:**

| check | line | why it is a constant |
|---|---|---|
| `every arm printed every row, so no arm is a silent no-op` | :513 | all 15 arms ARE the same file |
| `every DISARM moved 0` | :517 | nothing moves |
| `the shipped tree agrees with CPython on all 98 rows` | :519 | **true — and it is about `dtype.bend`** |
| `B is separable from A and C BY ROW` | :523 | `b_alone = not (set() & …)` — **the empty set is separable from everything** |
| `A alone fixes nothing, so no fixture can witness A by itself` | :527 | `not []` |
| `A is NESTED in C: NEEDS(A) ⊆ NEEDS(C)` | :528 | `set() <= set()` — **the empty set is a subset of the empty set** |
| `the repair moved no loc_* row` | :534 | `esc` empty because `mv_full` empty |
| `by CONTENT: mentions no other ABI's token` | :535 | reads ARM TEXT, never the artifact |
| `NO ARM of the 15 names another ABI's token` | :537 | reads ARM TEXT, never the artifact |

**`:523`, `:527` and `:528` are the eleventh-instance predicate in its purest form: a check written
about a NON-EMPTY set, which an EMPTY set satisfies vacuously.** `:528` in particular asserts
"NESTED rather than separable" and proves it with `set() <= set()`. The gate's own text at `:527`
says "no fixture can witness A by itself" and reports that as **PASS**, while the truth is that no
fixture witnesses A **at all**. Only `the re-broken tree is RED on abi4_ rows` (:516) and `every
PLANT moved rows` (:518) require the lane to exist, and **both are the ones that go red.**

## ABI4CHK-9 — STALE CITATIONS FOUND, EVERY ONE WITH ITS LINE

Every one of these was a file that looks fine.

| # | `file:line` | the claim | the measurement |
|---|---|---|---|
| 1 | `checks/abi4_gate.py:267` | `body.append(f"    v{i} : {r.show} <- {r.expr}")` | **kills the gate on arm `shipped`**; `dtype.bend:748` is pure (ABI4CHK-2) |
| 2 | `checks/abi4_gate.py:430` | "`dtype.bend` declares `Dt.fp16(x: F32)` and `Dt.fp8_to(..) -> IO(F32)`" | `dtype.bend:916` is `-> F32`. **TRUE at `135bf0204`, false now** |
| 3 | `checks/abi4_gate.py:202` | "`decl_in`/`decl_out` are copied from `tinybendygrad/dtype.bend`'s SEAM SIGNATURES" | **they are hardcoded literals** (`:243 :247 :252 :257`) **and read by NOTHING in the file.** Dead fields attributed to a file |
| 4 | `checks/abi4_gate.py:58` | "`dtype.c` is byte-unchanged" | **FALSE**: `git diff --stat 135bf0204 HEAD -- tinybendygrad/runtime/dtype.c` = 42 insertions, 11 deletions |
| 5 | `checks/abi4_gate.py:495-499` | "the only arm that differs from it by a row is ALT (0 rows), so the bytes in the repo ARE the repair — measured, not asserted" | **a CONCLUSION printed from a ZERO.** Prose a reader takes as a measurement |
| 6 | `checks/abi4_gate.py:540` | "`abi_gate.py` exits 0 against this tree`" | `abi_gate` exits **1** now |
| 7 | `checks/abi4_gate.py:541` | "`jsfix_gate.py` exits 0 against this tree`" | `jsfix_gate` exits **1** now |
| 8 | `checks/abi4_gate.py:6` | `python3 checks/abi4_gate.py  # ~2 min, writes nothing live` | 104 s at `135bf0204`; **cannot run at all now**, and `rc_of` at `:501` makes `abi_gate.py` **write 10,063 lines into two TRACKED files, `checks/gen/probe.js` and `checks/gen/probe.gen.c`** |
| 9 | `checks/abi4_gate.py:57-59` | "THE PLANTS ARE SECOND MUTATIONS… a plant that moves nothing means the violation has another witness" | **backwards on a dead lane**: a plant that moves nothing means the lane was never consulted, which is a different finding with a different remedy |

`checks/abi4_gate.py:30` ("`abi_gate.py`'s 12 rows contain exactly ONE fp8_to row") is **TRUE** —
`checks/abi_gate.py:129` is the only `fp8_to` row. It is the one cross-gate citation that survives.

## WHAT IS NOT SETTLED

1. **Whether `checks/gen/` belongs in the tree.** `checks/gen/probe.js` and
   `checks/gen/probe.gen.c` are **TRACKED** (`git ls-files`) and are **staged as EMPTY blobs**
   (`e69de29…`) while the working tree holds real content, so `git diff` reports them as new files
   with 10,063 insertions. My run populated them at 05:38; the directory is dated 05:12 and is
   `abi_gate.py`'s output, not mine. **I left them as my run left them rather than truncate another
   unit's evidence, and I did not commit.** `abifix` already flagged the directory as unsettled; the
   new fact is that it is TRACKED and INDEXED-EMPTY, which is a third state nobody has named.
2. **Whether ABI-4 still exists as a seam question.** Sites B and C are described at `:443-445` as
   "ABI-4 AT THE SEAM". There is no seam. Whether the *conversion obligation* survives as a
   statement about `dtype.bend`'s pure functions is a question about the declaration's content, and
   **`checks/abi.json` is not mine to answer.**
3. **Whether the two gates' verdicts can be restored without authoring the subject.** The honest
   arithmetic: re-binding the probe (`<-` → `=`) is a FIXTURE fix and is done in one character. What
   would remain is a gate with **no second lane**, so `NEEDS`/`FIXES`/`ALT`/`by CONTENT` have no
   referent. **Answer 3 applies to the rest: making this gate able to measure ABI-4 again means
   authoring the subject under test, which is not this unit's to do.**