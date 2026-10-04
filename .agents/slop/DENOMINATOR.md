# DENOMINATOR — is `59 of 77` the right denominator? Unit `DENOM`, 2026-10-04

**NO CLAIM IS TRANSCRIBED.** Every number below comes out of
`.agents/slop/denom/{denom-probe,census,emittable,yield}.py`, each of which MEASURES by
calling CPython. Run them; the transcripts are the report's evidence.

---

## 1. THE BRIEF'S TEST FINDS NOTHING. The hypothesis is falsified.

The brief proposed a checkable test: *"**No `UOp` is ever constructed with it** is the
finding."* I ran it, in the form the brief asked for — **search for construction sites, not
for the name** — and then went one step further and **called** each construction.

```
# denom-probe.py, DEV=CPU, 18/18
# CONSTRUCTIBLE       = 18 of 18
# CARRIED-ON-A-UOP   = 18 of 18      <- a UOp exists whose .op IS Ops.X
# IN root.toposort() = 18 of 18      <- so it is a row the differ would emit
# SPEC-PASSING       = 12 of 18
```

**Every one of the 18 is a real node in a real UOp dataflow graph.** Not one is
"unreachable as a dataflow graph". `grep` on construction sites agrees (each has at least
one `UOp(Ops.X, ...)`), and `mulacc`/`threefry` — the two with **no** direct `UOp(Ops.X`
site — are minted through `UOp.alu` (`ops.py:627`), which is the same two-argument call.

Two independent refutations of the "structural, not unreachable" reading:

* **`tinygrad/uop/__init__.py:85` says `# ** 6 -- ops that don't exist in programs **` and
  that section CONTAINS `STAGE COPY MSELECT MSTACK CUSTOM_FUNCTION UNSHARD` — nine of the
  18.** But `CONTIGUOUS_BACKWARD` and `DETACH` (`__init__.py:88`) are in the *same section*
  and are **already reached** by the corpus. **A section header is not a reachability
  oracle, and this one is falsified by two members of its own section.** (Same family as
  `flip`'s stale `7/7`: a number or a label that nobody voted on.)
* The three ops the brief called "markers around code generation" — `PROGRAM`, `SOURCE`,
  `PYLITERAL` — are produced by upstream's own pipeline at `codegen/__init__.py:502`,
  `codegen/__init__.py:455/459` and `upat.py:25-29`, and I **built all three by calling
  those functions.**

## 2. PER OP: expressible, with the deciding `file:line`

`SPEC` = upstream's own table, chosen as upstream chooses it (`spec_program` for a `PROGRAM`
root per `codegen/__init__.py:392`, else `spec_tensor` per `schedule/__init__.py:263`).
Every construction is upstream's, cited at the row.

| op | expressible | deciding site (`tinygrad/…`) | SPEC | upstream construction called |
|---|---|---|---|---|
| ALLREDUCE | **yes** | `uop/ops.py:679` (only site) | OK | `copy_to_device(tuple).allreduce(Ops.ADD, tuple)` |
| COPY | **yes** | `uop/ops.py:765` (only site) | OK | `UOp.copy_to_device` |
| CUSTOM | **yes** | `uop/upat.py:25-31`; `llm/kernels/amd.py:167` | OK | `_get_clause` on a real `UPat` |
| CUSTOMI | **yes** | `uop/upat.py:33,51`; `llm/kernels/amd.py:108` | OK | `_get_clause` |
| CUSTOM_FUNCTION | **yes** | `uop/ops.py:1258`; only production site `tensor.py:563` | OK | `UOp.custom_function("f", var.unbound())` |
| GETADDR | **yes** | `uop/ops.py:844`, guarded by `ops.py:843` | FAIL | `UOp.new_buffer(...).getaddr("CPU")` |
| INS | **yes** | `uop/ops.py:622` (`UOp.ins`) | FAIL | `UOp(Ops.NOOP).ins("nop", dtype=void)` |
| MSELECT | **yes** | `uop/ops.py:769` | OK | `copy_to_device(tuple).mselect(0)` |
| MSTACK | **yes** | `uop/ops.py:770` | OK | `UOp.mstack` |
| MULACC | **yes** | **zero** direct sites; minted only by the REWRITE `codegen/decomp/op.py:119,121` | OK | carried via `UOp(Ops.MULACC, …)`, then see §4 |
| PROGRAM | **yes** | `codegen/__init__.py:502`, via `to_program` `:518` | FAIL | `to_program(schedule_linear kernel, renderer)` |
| PYLITERAL | **yes** | `uop/upat.py:25-29,36-44` | OK | `_get_clause` |
| REWRITE_ERROR | **yes** | `viz/serve.py:197`; also `uop/ops.py:1722` | FAIL | `UOp(Ops.REWRITE_ERROR, arg=<traceback>)` |
| SOURCE | **yes** | `codegen/__init__.py:455,459` | FAIL | `to_program` (which applies `pm_to_program`) |
| STAGE | **yes** | `uop/ops.py:676` (`bufferize`) | OK | `UOp.bufferize` |
| THREEFRY | **yes** | **zero** direct sites; `mixin/elementwise.py:458` via `alu` | FAIL | `Tensor.threefry` |
| UNSHARD | **yes** | `uop/ops.py:701` | OK | `UOp.unshard(0, range)` |
| WMMA | **yes** | `uop/ops.py:651` | OK | `UOp.wmma` |

The 6 `SPEC FAIL`s are not defects in my fixtures and I am **not** reporting them as holes
in the ops: all six **carry a real UOp and appear in `toposort()`**, and each fails the
*tensor-stage* table because it belongs to a later or different stage — `GETADDR`/`INS`/
`REWRITE_ERROR`/`SOURCE`/`PROGRAM` are the codegen/HCQ/viz vocabulary and `spec_tensor`
applies at schedule time; `THREEFRY` is decomposed away by `op.py:77`
(`if Ops.THREEFRY not in ops`) for every backend except `NullRenderer`
(`runtime/ops_null.py:16`), and `op.py:76` says so in a comment: *"no real hardware
supports THREEFRY"*. **An op that a rewrite removes before render is still a node in the
graph the rewrite ran on**, which is the whole question.

## 3. THE DENOMINATOR THAT IS ACTUALLY REACHABLE

```
denominator                 : 77   (measured len(list(Ops)) — NOT transcribed)
reachable as a UOp graph    : 77 of 77   <- every op above is in a real toposort
reachable by the DIFFER     : 73 of 77   <- emittable.py: cshape renders every node
NOT emittable (4)           : CUSTOM CUSTOMI PYLITERAL MULACC
```

**So `59 of 77` was measured against the RIGHT denominator, and the shortfall was the
corpus, not the denominator.** `emittable.py` builds **14 graphs, every one from an
upstream constructor**, and their union reaches **73 of 77** — 14 of the 18.

**The 4 that the differ cannot emit, and it is the DIFFER, not tinygrad:**

* **`CUSTOM CUSTOMI PYLITERAL` — `AND`'s shape raises `AssertionError`, and
  `graphcmp.py:750` catches only `RuntimeError`.** MEASURED:
  `issubclass(AssertionError, RuntimeError)` is `False`; `cshape(AND)` raises
  `AssertionError: None input shape not supported for Ops.AND` (`ops.py:442`, because `AND`
  is in `GroupOp.Broadcastable` and its srcs are shapeless). And `upat.py:66` makes **every**
  pattern-compiler IR `AND`-rooted by construction:
  `return UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI, arg=("True", …))`.
  **A one-arm widening in `cshape` retires all three.** These are the ops the brief called
  "markers around code generation", and the marker was real — it was in the *instrument*.
* **`MULACC` — device-gated, not dead.** Its one rule is `op.py:118` `if Ops.MULACC in ops:`,
  where `ops` is the backend's `code_for_op`, and **exactly one renderer lists it:
  `renderer/ptx.py:33`.** MEASURED: `Ops.MULACC in ClangRenderer.code_for_op` is `False`, so
  on CPU the rule does not fire — my `mulacc` graph emits **0** `MULACC` and 11 nodes.
  It needs an NVIDIA device, not a different graph.

## 4. GRAPHS ADDED — one, and it DISAGREEs, and the cause is one field

`g_allred`, added to `graphcmp.py` (`def g_allred`, `GRAPHS["allred"]`) and `graphcmp.bend`
(`def g_allred`, one dispatch arm). **Purely additive: 0 lines deleted, 0 existing lines
changed.** Claim and md5s: `.agents/slop/denom/CLAIM.md`.

```
py side : Tensor.empty(4,3,f32).uop.copy_to_device(('CPU','CPU')).allreduce(Ops.ADD,('CPU','CPU'))
MEASURED  9 nodes  ALLOC=1 CONST=3 STACK=1 RESHAPE=1 RANGE=1 COPY=1 ALLREDUCE=1
VERDICT: DISAGREE          nodes=9/9  shared-cores=7  ONLY-PY=2 ONLY-BEND=2  field-mismatches=0
ledger: z y u q X! BAD E ?  all 0/0 on BOTH sides      selfcheck: OK
```

**TWO NEW OPS REACHED, BOTH SIDES, AND THE HEADLINE IS NOT THE VERDICT.** `?=0` on both
sides while `DISAGREE`ing — **the `flip` pattern, reproduced deliberately**, and it confirms
`?` measures omission, not agreement.

**The cause, and it is the finding:**

```
COPY      arg  py=n(sCPU,sCPU)     bend=ssCPU,sCPU
ALLREDUCE arg  py=al(OADD,sCPU,CPU)  bend=al(OADD,ssCPU,sCPU)
```

**`COPY`'s arg has NO representation in the port's `Arg` taxonomy.** `graphcmp.bend:390` is
`case O.ADev{dd}: dev(dd)`, and `ADev` (`uop/ops.bend:1070`, documented `ops.bend:1036` as
*"str|tuple  ADev  COPY arg"*) is the **only** variant that can hold a COPY's device — and
it FLATTENS through `devs` (`graphcmp.bend:156-158`, `String.join(…, ",")`). The py side has
**no `carg` arm for `COPY`** (`graphcmp.py:479-566`; `ALLREDUCE` has one at `:497`, `COPY`
does not), so `COPY`'s arg falls through to the generic tuple grammar `_carg` and NESTS.
**`n(sCPU,sCPU)` is unreachable through the port's own constructors**, and my fixture used
the port's own constructors (`O.ADev{S.Dn{[0,0]}}`) precisely so the port, not my fixture,
would be the one on trial.

**This is also a PY-side inconsistency, and one of the two sides is wrong either way:** py
spells a device tuple `n(sCPU,sCPU)` for `COPY` and `sCPU,CPU` for `ALLREDUCE`, from the same
graph, two nodes apart. **Choosing which is correct is a NORMAL-FORM decision affecting both
files, so I am reporting it and NOT changing it** — `ADev`'s tuple arm has had no fixture
until now, so nothing in the corpus ever exercised it.

## 5. RE-MEASURED CORPUS — 59 → 61, both sides, zero asymmetry

```
             BEFORE    AFTER
graphs          24        25
denominator     77        77     (measured len(list(Ops)))
reached PY      59        61
reached BEND    59        61
reached BOTH    59        61
py-only         []        []
bend-only       []        []
WALLS           []        []
NEITHER         18        16
```

`NEITHER` is now `CUSTOM CUSTOMI CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK MULACC PROGRAM
PYLITERAL REWRITE_ERROR SOURCE STAGE THREEFRY UNSHARD WMMA`.

**NOTHING ELSE MOVED.** All 24 prior verdicts re-measured individually: **23 `AGREE`, 2
`DISAGREE` (`lin`, `loop` — disagreeing on purpose, for named measured reasons).**
`selfcheck: OK`. The new `allred` is the 25th and is the third `DISAGREE`.

## 6. THE CLAIM I DID NOT MAKE

**This does not mean the corpus compares training graphs, and it must not be stretched to
say so.** `bw` is the gradient of **one eager expression**; `schedule -> render -> compile`
is still **forward-only**; and `late` is a graph the port can **reproduce but not produce** —
it writes the rewritten graph into its arena and does not implement
`get_late_rewrite_patterns`. **`g_allred` does not change this in either direction:** its py
side is `copy_to_device` + `allreduce` on a `Tensor`, an eager call, and its port side is a
9-node arena fixture — it is *reproduced*, not *produced*. **Reproducing a graph and
producing it are different claims, and a corpus built of reproducible graphs looks identical
to one built of producible ones.** Nothing here measures the emitter's ability to reach
`schedule -> render -> compile` on its own.

I also did **not** claim `THREEFRY` is reachable in a rendered program — it is decomposed
away (`op.py:77`) for every backend but `NullRenderer`; it is reachable in the graph the
rewrite *runs on*, which is a smaller claim.

## 7. RULES (fresh prefix `DENOM-`, append-only)

* **DENOM-1. `tinygrad/uop/__init__.py:85`'s `# ** 6 -- ops that don't exist in programs **`
  is NOT a reachability oracle, and is falsified by two members of its own section**:
  `CONTIGUOUS_BACKWARD` and `DETACH` (`:88`) are both in the corpus's reached-59. An enum
  *section comment* is a label nobody voted on, exactly like `flip`'s stale `7/7`.
* **DENOM-2. "No `UOp` is ever constructed with it" is a test with a measured hit rate of
  ZERO on this set.** Before using it to shrink a denominator, call each construction and
  check `.toposort()`. Two of the 18 (`MULACC`, `THREEFRY`) have *no* `UOp(Ops.X, …)` site
  at all and are both fully constructible, through `UOp.alu` (`ops.py:627`).
* **DENOM-3. `graphcmp.py:750` catches `RuntimeError`, and `ops.py:442` raises
  `AssertionError`.** Any node whose `.shape` raises anything else is uncannonicalisable and
  reads as a CRASH, not a difference. `cshape`'s `except` must widen before a graph
  containing a shapeless `AND` can be compared at all — and `upat.py:66` makes every
  pattern-compiler IR `AND`-rooted, so that one arm gates `CUSTOM`, `CUSTOMI` and
  `PYLITERAL` together.
* **DENOM-4. A graph is only a denominator sample if `cshape` renders every one of its
  nodes.** Measure emittability before counting a candidate's yield: `emittable.py` reports
  `patir` as "3 NEW" on the raw census and `NO` on emittability. **The census and the
  emitter are different instruments and they disagree.**
* **DENOM-5. `ADev`'s TUPLE arm (`graphcmp.bend:390`) had no fixture in 24 graphs**, and a
  tuple device is the only value in `Arg` that can hold more than one of something. Grep a
  datatype for its *composite* cases, not its atoms: `D1` was exercised by every graph,
  `Dn` by none.

## 8. WHAT I DID NOT DO

Did not add the other 13 candidate graphs (`stage copy getaddr customfn ins rwrerr threefry
wmma mstack mselect unshard program` — each measured emittable, each 1–2 new ops, listed
with its citation in `emittable.py`); the port has `ADev`, `AAllred`, `AInk`, `AProgram`,
`AWmma`, `ATuple`, `AStr` and `ACustom` already, so they are mechanical once the `ADev`
spelling question in §4 is settled. Did not fix `ADev`. Did not touch `MULACC`'s PTX gate.
Did not commit anything.
