# WHAT THE CORPUS DOES NOT COVER, and the graph that reached the largest gap.

**⇒ AND ON 2026-10-31 THE LARGEST GAP IN THE TABLE BELOW WAS **CLOSED**, AND THE GRAPH
THAT CLOSED IT **FOUND A REAL PORT DEFECT**: `GRADIENT.md`, IN THIS DIRECTORY, HAS THE
MEASUREMENTS.  **`mixin/gradient.bend` WENT **0/494 → 174/495** (**ALL **32 **RULES
`gr_0`..`gr_31` **REACHED**), **TOTAL **REACHED **959 → 1144**, **AND **THE **PORT's **MAX
GRADIENT **RULE **BUILT **FOUR **WHERE **NODES **WHERE **CPYTHON **BUILDS **THREE** — **A
DEFECT **THE **PORT's **OWN **`max_n0`/`max_n1` **ROWS **COULD **NOT **SEE, **BECAUSE
`size1` **COUNTS **A **SHARED **SUBTREE **ONCE **PER **PATH**.  **FIXED**, **AND
`checks/differ.py`'s **`WANT` **IS **EMPTY** — **NO **EXCEPTION **WAS **ADDED.**

MEASURED 2026-10-30 on the tree at `HEAD` + this unit's commit.  Every number here was
produced by running the instrument named beside it, and the instruments are IN THIS
DIRECTORY (`COVER.py`, `reach4.py`) so a reader can re-run them.

    .venv/bin/python .agents/slop/corpuscoverage/COVER.py

---

## 0. THE ANSWER IN ONE PARAGRAPH

**The corpus's GREENNESS is about the OP SURFACE, and it says almost nothing about the
CODE.**  MEASURED: the corpus reaches **69 of 69** of upstream's program ops -- the op
surface is FULLY covered, and the 6 enum members it does not reach cannot appear in a
program graph at all.  MEASURED at the same time: the corpus's bend lane reaches **954
of 4724** defs in the 15 port modules it imports, and **55 of 214** upstream `.py` files
execute while its 36 graph builders run.  **A CORPUS THAT IS 100% OF ITS OWN OP CENSUS
IS 20% OF THE PORT'S DEFS.**  Those are two different subjects and only the first one has
a denominator in the corpus's own report.

**THE LARGEST UNCOVERED AREA INSIDE THE CORPUS'S OWN IMPORT CLOSURE WAS THE PORT'S
OPERATION LAYER**, and it was uncovered for a STRUCTURAL reason, not an accidental one:
**every graph in the corpus hand-builds its arena node for node**, so the corpus tests the
port's DATA STRUCTURES (`ops.bend`'s `UOp.new`, `fold.bend`'s derived properties) and
never the port's OPERATIONS.  MEASURED, before this unit's graph:

| module | defs | reached by the 35 graphs |
|---|---|---|
| `mixin/gradient.bend` | 494 | **0** |
| `mixin/elementwise.bend` | 254 | **0** |
| `uop/weak.bend` | 258 | **0** |
| `mixin/dtype.bend` | 177 | **0** |
| `tensor.bend` | 347 | 4 |

**1183 defs of the port's operation layer, 100% unreached, and 160 of the 175 port
modules never imported at all.**

**THE GRAPH THIS UNIT ADDED -- `api` -- IS THE FIRST ONE WHOSE BEND SIDE IS BUILT BY THE
PORT'S OWN TENSOR API**, and it (a) reaches that layer and (b) finds a REAL, MEASURED
PORT DEFECT that the corpus was structurally unable to see.

---

## 1. THE THREE MEASUREMENTS, AND HOW EACH WAS TAKEN

### (1) OP LEVEL -- the corpus's own census, quoted verbatim

`runs/graphcmp/D/D0-coverage-census.txt`:

    # COVERAGE: 69 of 69 program ops === 69 of 75 enum members
    # NOT REACHED (6 of 75 ENUM MEMBERS): REWRITE_ERROR SOURCE CUSTOM CUSTOMI INS PYLITERAL
    #   OF WHICH 6 CANNOT APPEAR IN A PROGRAM GRAPH AT ALL (by construction)

**THIS IS THE CORPUS'S STRONGEST CLAIM AND IT IS TRUE.**  It is also a claim about the OP
SURFACE, and the op surface is not what a reader of "35/35 agree" is thinking about.

### (2) BEND SIDE -- the port's `.bend` defs, by a static call graph over DEF BODIES

`.agents/slop/corpuscoverage/reach4.py`.  The instrument:

1. parses the corpus's import closure (13 files at the 35-graph corpus, 16 at the 36);
2. splits every file into `(def-name, body-lines)` -- Bend's bodies are INDENTED blocks,
   so a def's body is the run of lines under its header whose indentation is deeper;
3. attributes every call site to the def that CONTAINS it;
4. seeds the walk with the corpus's OWN defs (`.agents/slop/graphcmp.bend`) and follows
   call sites OUT of the port.

A def is REACHED only when a call site inside a REACHED def names it.

**WHAT IT DOES NOT SEE, and the direction of each miss.**  A `+`-bound parameter shadowing
a module-level def, and a def reached only through a namespace the parser did not
attribute, are both UNDER-approximations.  Neither can INVENT a reach.  **A def this
calls UNREACHED may still run** -- the honest reading is "not reached by any call site this
instrument can attribute".

**TWO EARLIER VERSIONS OF THIS INSTRUMENT WERE WRONG, AND BOTH WRONGS MATTERED.**  The
first resolved an unqualified call `f` by searching `[file] + imports_of(file)` for the
first file defining `f`; that resolution is OVER-BROAD and it measured `uop/render.bend` at
189 of 303 reached when the corpus calls exactly ONE of its defs.  The second had a
two-segment qualified-call regex and so missed every `O.GroupOp.elementwise(`-shaped call
-- which is the port's entire op-classification layer.  **A COVERAGE NUMBER PRODUCED BY
AN INSTRUMENT THAT CANNOT SEE ITS POPULATION IS NOT A COVERAGE NUMBER**, and both of these
were caught by a RE-DERIVATION rather than by an argument.

### (3) PY SIDE -- upstream functions that EXECUTE

`sys.setprofile` on CALL events, filtered to code objects under `tinygrad/`, while the 36
graph builders run.  This is DYNAMIC, so it sees the arm that actually fired.

**MEASURED: 1196 distinct upstream functions execute, across 55 of 214 upstream files.**
159 files never execute -- including `tinygrad/mixin/rand.py`, `tinygrad/nn/*`,
`tinygrad/schedule/*`, `tinygrad/renderer/*` and `tinygrad/engine/*`.

### WHAT THE THREE SAY TOGETHER

| subject | covered |
|---|---|
| upstream's op surface | **69 of 69 program ops** |
| the port's defs, in the corpus's import closure | **954 of 4724** |
| the port's modules | **15 of 175** |
| upstream's functions, executed by the builders | **1196** |
| upstream's files, executed by the builders | **55 of 214** |

---

## 2. THE GRAPH: `api`

`Tensor.empty(4,3) + Tensor(1)` -- MEASURED at 8 nodes, census
`ADD=1 ALLOC=1 CONST=4 RESHAPE=1 STACK=1`.

**WHAT MAKES IT DIFFERENT FROM THE OTHER 35.**  Every other graph in the corpus
hand-builds its arena node for node.  `api`'s bend side CALLS the port:

    def g_api() -> O.Found:
      +ar = O.Arena.empty()
      +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
      +s = E.ew_add(a, E.ECon{O.CInt{H.i64_of_i32(1)}}, False{})
      O.Found{T.Tensor.ar(s), T.Tensor.u(s)}

**WHY A BINARY OP IS THE ONE THAT WORKS, and it is measured rather than chosen.**
`mixin/elementwise.bend`'s own header says "ONE ARENA PER METHOD" and names
`O.Arena.merge` as the composition operator: a method builds in its own arena and the
operands' arenas are MERGED at ENTRY.  A BINARY op merges its two operands' arenas and
builds the op in the merged arena, so the WHOLE graph lands in ONE arena -- which is what
the corpus's bend lane needs, because `rows.of` emits one canonical row per arena node.
**MEASURED: an EIGHT-OP graph of independent unary ops CANNOT be built this way** -- the
port's API gives each method its own arena and there is no operator that COLLECTS them --
so the corpus's `alu` shape (a GROUP of eight) is not buildable through the API, and a
BINARY graph is.

**THE OPERAND IS A WEAKINT CONST, AND THAT IS THE POINT.**  `Tensor(1)` is `weakint`, so
upstream PROMOTES it: the ADD's second src is `CONST(weakfloat 1.0)`, not `CONST(1)`.
MEASURED on the port's side, `E.ew_add` produces the same `weakfloat` CONST.  An operand
that needed no promotion would reach the binop but NOT the promotion, and the promotion
is what reaches `uop/weak.bend`'s evaluation machinery.

### THE COVERAGE IT BUYS, MEASURED

The same instrument, before and after:

| module | before (35 graphs) | after (36 graphs) |
|---|---|---|
| `mixin/elementwise.bend` | 0 / 254 | **31 / 254** |
| `uop/weak.bend` | 0 / 258 | **41 / 258** |
| `tensor.bend` | 4 / 347 | **32 / 347** |
| `mixin/creation.bend` | not in the closure | **9 / 105** |
| `mixin/op.bend` | 6 / 176 | **7 / 176** |
| **total reached** | **828** | **954** |

### THE DEFECT IT FINDS

**`api` is a DISAGREE, ON PURPOSE, AND THE EXPECTATIONS TABLE NOW HOLDS ONE EXCEPTION.**
MEASURED, the two sides' ALLOC carries a DIFFERENT `ParamArg.slot`:

    CPython   ALLOC slot 0
    the port  ALLOC slot 1

and the cause is `tinybendygrad/mixin/creation.bend`'s `cr_alloc` (:377), which mints
`cr_alloc.arg(O.Arena.next(ar), dt, dev)` -- **the arena's LENGTH** -- where upstream mints
`next(UOp.unique_num)` (`tinygrad/uop/ops.py:1208`), **a MONOTONE counter**.

**THE CORPUS COULD NOT SEE THIS DEFECT, AND THE REASON IS STRUCTURAL.**  Every other
graph hand-builds its ALLOC and SPELLS the slot itself
(`.agents/slop/graphcmp.bend`'s `alloc(slot)`), so **the port's own slot-minting was
executed by NOTHING the corpus compares.**  A graph whose bend side calls `cr_empty` is
the first thing in this corpus that can see the port's OWN allocator.

**REPORTED, NOT FIXED.**  `mixin/creation.bend` is not this unit's file, and the corpus's
own claim -- "the port and CPython AGREE" -- is not something a corpus unit may weaken
silently.  So the graph is expected to DISAGREE (`checks/differ.py`'s `WANT`), the cause
is named in the report, and the corpus's coverage went from 35 of 35 to 35 of 36.

### A SECOND DIVERGENCE, MEASURED AND NOT USED

`(4,3) + (3,5)` does not broadcast: CPython RAISES `IndexError: shape mismatch`
(`tinygrad/uop/ops.py:86`, `_broadcast_shape`), and MEASURED on the port's side
`E.ew_add` **BUILDS IT ANYWAY**.  The fixture deliberately does not use it, because a
fixture that dies on one side cannot be a comparison at all -- but it is a second real
divergence in the same two lines of the port, and it is reported here rather than used.

---

## 3. THE WALLS, MEASURED

**A WALL IS A NAMED, MEASURED ABSENCE -- NOT A THING THE INSTRUMENT COULD NOT SEE.**  Two
are named here, and each names the instrument that found it.

### (a) `uop/render.bend` -- 2 of 315 defs reached, and it ports a DELETED upstream function

`tinybendygrad/uop/render.bend` is 3120 LOC and 315 defs, and the corpus reaches 2 of
them.  **THE REASON IS NOT A GAP IN THE HARNESS: the port's `render.bend` ports upstream's
`pyrender`, WHICH UPSTREAM DELETED.**  MEASURED, from the port's own header
(`render.bend:69-79`):

> `tinygrad/uop/spec.py` HAS NO `exec` AT THE PIN: upstream DELETED the whole `pyrender`
> round-trip in `81157efb0` ("use render_uir instead of pyrender"), and
> `tinygrad/uop/spec.py:41` now PRINTS `render_uir(lst)` under `DEBUG >= 3` instead of
> EXECUTING a rendered string.

**AND THE TWO UPSTREAM FUNCTIONS THAT ARE STILL LIVE IN THAT FILE ARE `TODO(p3)` IN THE
PORT**, so there is nothing for a corpus graph to compare against:

| upstream `tinygrad/uop/render.py` | live at this pin? | the port |
|---|---|---|
| `render_uir` (:65) | YES | `TODO(p3)` -- `ops.bend:5484`, `spec.bend:3222` |
| `renderer` (:102, the `PatternMatcher`) | YES | `TODO(p3)` -- `render.bend:132` |
| `renderer_infer` (:129) | YES | not ported |
| `pretty_print` (:7) | YES | `TODO(p3)` -- `render.bend:1913` |
| `_render_arg` (:30) | YES | not ported as such |
| `pyrender` | **NO -- DELETED upstream** | **THIS IS WHAT `render.bend` PORTS** |

**SO THE WALL IS MEASURED, NOT ASSUMED:** the corpus cannot compare `render.bend` against
`render_uir` because the port has no `render_uir`, and it cannot compare it against
`pyrender` because upstream has no `pyrender`.  The module's own `py=` column is a
**TRANSCRIPTION of the port's own answer** (`render.bend:2077`), not a live CPython
comparison -- and its own comment records that the transcription went stale for 6 of 80
rows against a pin that predates the current upstream.

### (b) `mixin/dtype.bend` -- 0 of 177 defs reached, and it is unreachable from ANY eager graph

MEASURED: 11 of `mixin/dtype.bend`'s 177 defs are called from outside it, and the callers
are `tensor.bend`'s `tn_logical_not` / `tn_isfinite.promote`, `mixin/op.bend`'s
`mo_promote` / `mo_commit_dt` / `mo_downcast` / `mo_remint`, `nn/item.bend`, and
`mixin/rand.bend`.  **NONE of those is on the eager path the `api` graph takes**, because
`mixin/elementwise.bend` does its promotion through `uop/weak.bend` and NEVER CALLS
`mixin/op.bend` (MEASURED: `grep 'MO\.mo_' tinybendygrad/mixin/elementwise.bend` is
EMPTY), and `mixin/op.bend`'s 176 defs are reached on 7.

**AND `mixin/dtype.bend`'s OWN route into `uop/weak.bend` IS DEAD IN THE PORT.**  Its
defs `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` / `wk_is_virtual` /
`wk_commit_dtype` -- the five that would carry `D.dt_is_int` / `D.md_weak` /
`D.commit_dtype` -- **HAVE NO CALLERS ANYWHERE IN THE PORT** (MEASURED over every
`.bend` file in `tinybendygrad/`).

**SO `mixin/dtype.bend` IS A PORT-SIDE DEAD MODULE FROM THE EAGER PATH'S POINT OF VIEW,
and a corpus graph cannot revive it.**  It is not reachable by a better fixture; it is
reachable only by the port growing a caller.

### (c) 160 of the 175 port modules are not in the corpus's import closure AT ALL

MEASURED, by size: `runtime/ops_dsp.bend` (6510 LOC), `uop/symbolic.bend` (4450),
`runtime/support/nv/ip.bend` (4072), `runtime/ops_metal.bend` (3817),
`runtime/ops_qcom.bend` (3684), `uop/spec.bend` (3473), `schedule/multi.bend` (3458),
`runtime/support/elf.bend` (3455), `renderer/amd/dsl.bend` (3348), `schedule/rangeify.bend`
(3318) -- **160 modules, 189308 LOC.**

**AND THE REASON IS A PROPERTY OF THE PORT, NOT OF THE CORPUS.**  The corpus's bend lane
imports `ops.bend`, `fold.bend`, `helpers.bend`, `LAWS/spec.bend`, `uop/render.bend`,
`tensor.bend` and `mixin/movement.bend`, and the port's OWN scheduler
(`schedule/__init__.bend`) ports only `__init__.py:14-80` and DEFERS `:82-301` ("every
rule is a `graph_rewrite` over the arena with a PYTHON ctx DICT").  **THE PORT CANNOT
BUILD A SCHEDULE AT ALL**, so no corpus graph can reach `schedule/` from the port's own
code, and the corpus's `lin` / `loop` / `gate` graphs hand-build their bend sides for the
same reason.  **A COVERAGE GAP WHOSE CAUSE IS A PORT GAP IS NOT A CORPUS GAP**, and
naming it as one would move a port problem onto the harness.

---

## 4. WHAT A READER SHOULD TAKE FROM THIS

1. **"69 of 69 ops" and "35 of 36 graphs agree" are BOTH TRUE and they are about
   DIFFERENT SUBJECTS.**  The op surface is covered; the code is not.
2. **A corpus's greenness is a statement about the FIXTURES IT HAS.**  This corpus's
   fixtures are 36 small hand-built graphs, and a graph that hand-builds an arena cannot
   test the code that builds arenas.
3. **THE LARGEST GAP WAS NOT A MISSING OP.**  Every op was reached.  The gap was a whole
   LAYER -- the port's operations -- and no op census can see a layer.
4. **THE FIX THAT FOUND A REAL DEFECT WAS TO CHANGE WHAT BUILDS THE GRAPH, NOT WHICH
   GRAPH IS BUILT.**  `api` compares the same op the corpus already compared; it differs
   only in that the port builds it.
5. **THE WALLS ARE NAMED AND MEASURED.**  `render.bend` ports a function upstream deleted;
   `mixin/dtype.bend` has no live caller; 160 modules are outside the closure because the
   port has no scheduler.  **None of those three is fixable by adding a graph.**
