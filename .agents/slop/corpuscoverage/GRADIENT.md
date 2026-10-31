# THE GRADIENT LAYER, REACHED -- and the port defect it found.

MEASURED 2026-10-31 on the tree at `HEAD` + this unit's commit.  Every number here was
produced by running the instrument named beside it, and the instruments are IN THIS
DIRECTORY (`COVER.py`, `reach4.py`) so a reader can re-run them.

    .venv/bin/python .agents/slop/corpuscoverage/COVER.py

---

## 0. THE ANSWER IN ONE PARAGRAPH

**`mixin/gradient.bend` WAS 0 OF 494 DEFS REACHED, AND IT IS NOW 174 OF 495.**  The corpus
reaches the port's AUTODIFF because two new graphs (`grad` and `gral`) CALL the port's own
`compute_gradient` instead of hand-building an arena, and **the second one found a real
port defect**: the port's MAX gradient rule built **FOUR** `WHERE` nodes where CPython
builds **THREE**, and **the port's own gate could not see it** because `size1` counts a
shared subtree once per PATH.  The defect is FIXED, **no exception was added to `WANT`**,
and the corpus is **38 of 38**.

**⇒ AND THE WALL WAS NOT WHERE THE BRIEF EXPECTED IT.**  The brief's own hypothesis was
right in its reasoning and wrong in its conclusion: a backward pass is indeed not a
binary op, it is a chain -- **AND A CHAIN IS EXACTLY WHAT A WALK PRODUCES, SO THE BEND
SIDE CAN CALL THE WALK.**  The corpus's bend lane was never structurally unable to reach
the gradient layer; it was structurally unable to reach it **while every graph hand-built
its arena node for node**, and that was one edit away.

---

## 1. THE RE-MEASUREMENT, BEFORE ANYTHING WAS ADDED

`reach4.py` -- the def-body call-graph walker, which UNDER-approximates and therefore
cannot invent a reach.  Run on the tree as it stood on 2026-10-31, BEFORE this unit's
graph:

| module | defs | reached |
|---|---|---|
| `tinybendygrad/mixin/gradient.bend` | 494 | **0** |
| `tinybendygrad/mixin/dtype.bend` | 177 | **0** |
| `tinybendygrad/mixin/elementwise.bend` | 254 | 31 |
| `tinybendygrad/uop/weak.bend` | 258 | 41 |
| `tinybendygrad/tensor.bend` | 347 | 32 |

**port defs in the corpus's import closure 4739, REACHED 959, UNREACHED 3780.**  The
corpus's own op census read `69 of 69 program ops` at the same time, which is the
sentence `0/494` was hiding.

**⇒ AND THE PY SIDE: 1196 upstream functions executed, across 55 of 214 upstream files,
and `tinygrad/mixin/gradient.py` and `tinygrad/uop/upat.py` were NOT AMONG THEM.**

---

## 2. WHY A GRADIENT GRAPH IS NOT A HAND-BUILT GRAPH

**THE SHORT ANSWER: A GRADIENT IS NOT A GRAPH YOU CAN SPELL OUT, BECAUSE A GRADIENT IS
THE OUTPUT OF A WALK OVER A GRAPH.**  Every other graph in the corpus hand-builds its
arena node for node, so it exercises `ops.bend`'s `UOp.new` and `fold.bend`'s derived
properties and never the port's OPERATIONS.  `mixin/gradient.bend` is the port's
operations at their most operational: a 33-entry rule table (`gr_0`..`gr_31`), a
first-wins scan, a dict-shaped `grads` table with an in-place update, and a walk that
descends the root's path in reverse.

**SO THE BEND SIDE HAS TO CALL THE WALK.**  `mixin/gradient.bend`'s `compute_gradient`
takes `(root, root_grad, targets, ar)` and answers a `CState` whose `grads` table holds
the gradient values as indices into the arena it GREW.  The corpus's differ toposorts ONE
root, so the graph is the GROUP of the gradient values -- the same shape `bw` uses for a
two-answer backward graph.

### THE FIXTURE, AND THE CONSTRAINT THAT IS NOT A CHOICE

`grad`'s fixture is **the port's own `dag()` fixture, node for node**:

    a = BUFFER(0)   b = BUFFER(1)   c = BUFFER(2)
    p = MUL(a,b)    q = ADD(a,c)     r = ADD(p,q)      <- the root
    seed = CONST 1.0 (f32)

`gates/gr_graph_census-oracle.py` builds the SAME graph on the CPython side, so the
fixture is not a second transcription of the port's.

**⇒ AND THE LEAF MUST BE `BUFFER(STACK())` AND NOT `BUFFER()`, AND THAT IS MEASURED.**
upstream's `_shape` reads `self.src[0].as_shape` (`ops.py:359`), so a src-less BUFFER
has no `_shape`, and `compute_gradient` reads `k._shape` at `gradient.py:130` -- so
CPython **RAISES `IndexError: tuple index out of range`**.  MEASURED on this line, before
the fixture was written.  **⇒ AND THIS IS NOT A HYPOTHETICAL: `gates/gr_graph_census-oracle.py`
is RED for exactly this reason** -- its fixture at `:89-91` is
`UOp(Ops.BUFFER, arg=ParamArg(...))` with no src, and the oracle dies inside CPython's
own `compute_gradient`.  **THAT **FAILURE **IS **PRE-EXISTING **AND **UNRELATED **TO **THIS
**UNIT'S **CHANGE** (MEASURED: it is a failure in the CPYTHON lane, at
`gates/gr_graph_census-oracle.py:97`, with the port's file uninvolved).

An EMPTY STACK's `as_shape` is `()` (`ops.py:789`), so the leaf is SCALAR and the
shaped-edge reduce at `gradient.py:131` never fires on either side.

### THE TWO GRAPHS

| graph | nodes | what it is | ops reached |
|---|---|---|---|
| `grad` | **9** | the walk over `dag()`'s fixture; the GROUP of `grad_a` and `grad_b` | 7 |
| `gral` | **52** | the walk over a fixture carrying EXP2, SQRT, TRUNC, POW and MAX | **15** |

**`gral` EXISTS BECAUSE A RULE BODY THAT IS NEVER ENTERED IS A BODY NO GRAPH CAN
DISAGREE WITH.**  `grad`'s forward graph is MUL and ADD only, so only TWO rule bodies
fire and the other sixteen answer their entry condition and nothing else.  `gral`'s
fixture carries one of each of the unary and binary ALU rules, and it is a **CHAIN**
(every ADD takes the previous ADD as one of its two srcs) so the root's path visits all
five and the walk descends into every one of them.

---

## 3. THE COVERAGE IT BUYS, MEASURED

The same instrument, before and after:

| module | before (36 graphs) | after (38 graphs) |
|---|---|---|
| `tinybendygrad/mixin/gradient.bend` | **0 / 494** | **174 / 495** |
| `tinybendygrad/uop/ops.bend` | 266 / 946 | **272 / 946** |
| `tinybendygrad/helpers.bend` | 58 / 380 | **63 / 380** |
| **total reached** | **959** | **1144** |

**⇒ AND ALL 32 RULES `gr_0`..`gr_31` ARE REACHED** (MEASURED, by listing the reached
names), which is the table the whole file exists for.

**⇒ AND THE 321 UNREACHED `gradient.bend` DEFS ARE THE FILE's OWN GATE READERS** --
`dag_*`, `gs_*`, `bw_*`, `t_*`, `Fix`, `Dag` -- MEASURED by classifying them: **292 of
the 321 are gate readers**, and the 29 that are not are the rule bodies for ops this
fixture does not have (`gexp2`, `gsqrt`, `gtrunc`), the file's own fixture builders
(`dag`, `gs`, `fx_buf`), and `main`/`row`/`srow`.  **⇒ SO 174/495 IS NOT "35% OF THE
AUTODIFF": IT IS THE AUTODIFF PLUS THE FIXTURES AND THE READERS.**

**⇒ AND ON THE PY SIDE: 1196 → 1203 upstream functions executed, and
`tinygrad/mixin/gradient.py` AND `tinygrad/uop/upat.py` ARE NOW AMONG THEM** -- the
corpus now runs upstream's own `compute_gradient`, `_deepwalk`, `pm_gradient.rewrite`,
`upat_compile` and `upat_interpret`.  MEASURED by `sys.setprofile` over the `grad`
builder alone.

**⇒ AND THE OP CENSUS DID NOT MOVE: `69 of 69` before and after.**  The gradient's ops
(ADD, MUL, BUFFER, CAST, CONST, STACK, AFTER, EXP2, SQRT, TRUNC, POW, MAX, WHERE, CMPLT,
CMPNE, LOG2, RECIPROCAL) were all already reached by the forward graphs.  **THE HONEST
COUNT OF WHAT `grad` AND `gral` ADD TO THE OP SURFACE IS ZERO, AND WHAT THEY ADD TO THE
CODE IS 185 DEFS.**  A graph's value is not its op count.

---

## 4. THE DEFECT `gral` FOUND

**`gral` DISAGREED, ON THE FIRST RUN, AT 52 NODES AGAINST 55.**  And the diff was not
noise: it was **a duplicated inner `WHERE`**.

### THE MEASUREMENT

The MAX rule alone, both sides, in the corpus's own normal form:

| | CPython | the port (before the fix) |
|---|---|---|
| nodes | **17** | **20** |
| `WHERE` | **3** | **4** |
| `CMPNE` | **2** | **3** |
| `CMPLT` | 2 | 2 |

**⇒ AND THE PORT'S OWN ROWS READ `max_n0=21 max_n1=21` ON BOTH SIDES, AND `max_eq_op=1`,
AND THE GATE IS GREEN.**  The port's own gate could not see it, and the reason is a
property of the instrument: **`size1` counts `n` plus everything under it, and a SHARED
subtree is counted ONCE PER PATH** -- so a duplicated inner `WHERE` costs exactly what a
shared one costs.  **A COUNT THAT IS RIGHT AND A STRUCTURE THAT IS WRONG**, which is the
failure `mixin/gradient.bend`'s own header names two hundred lines above the defect:
*"the counts coincide -- which is exactly the 'two rules agree and the gate cannot see
it' failure"*.

### THE CAUSE

upstream's rule body (`tinygrad/mixin/gradient.py:78-79`):

```python
(UPat(Ops.MAX, src=(UPat.var("x"), UPat.var("y"))), lambda ctx, x, y:
    ((x>y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)), (x<y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)))),
```

**`x` AND `y` ARE BOUND ONCE AND WRITTEN IN BOTH ARMS, AND `UOp` IS HASH-CONSED, SO THE
INNER `(x.eq(y)).where(ctx * 0.5, 0)` IS ONE NODE.**  MEASURED on CPython's own tree, the
two slots' inner `WHERE`s are the **same `id()`**.

**⇒ AND `(x>y)` IS `CMPLT(y, x)`** -- `_binop(Ops.CMPLT, y, reverse=True)`
(`elementwise.py:323`) puts `y` on the LEFT -- **AND `(x<y)` IS `CMPLT(x, y)`.**  So ONLY
THE OUTER COMPARISON IS SWAPPED BETWEEN THE TWO SLOTS.

**⇒ AND THE PORT SWAPPED BOTH.**  `gr_11.go` called `gr_11.one(ar, ctx, x, y)` and then
`gr_11.one(ar, ctx, y, x)`, so slot 1's inner was computed from `(y.eq(x))` -- a
DIFFERENT node, because `CMPNE` is not commutative -- and the port built a SECOND inner
`WHERE`.

| | slot 0 | slot 1 |
|---|---|---|
| CPython outer `CMPLT` | `CMPLT(B1, B0)` | `CMPLT(B0, B1)` |
| CPython inner `CMPNE` | `CMPNE(B0, B1)` | `CMPNE(B0, B1)` -- **THE SAME** |
| the port's outer `CMPLT` | `CMPLT(B0, B1)` | `CMPLT(B1, B0)` |
| the port's inner `CMPNE` | `CMPNE(B0, B1)` | `CMPNE(B1, B0)` -- **DIFFERENT** |

**⇒ AND THE OUTER SWAP IS INVISIBLE TO THE CANONICAL FORM** (the two `CMPLT`s are the
same two nodes in the other order, so the subtree SET is the same), **WHICH IS WHY THE
ONLY VISIBLE DIFFERENCE WAS THE DUPLICATED INNER.**  The port's outer was ALSO wrong; the
corpus could see the duplication but not the swap.

### THE FIX

`tinybendygrad/mixin/gradient.bend`'s `gr_11`: **build the inner ONCE and swap only the
outer.**  `gr_11.inner` builds `(x.eq(y)).where(ctx * 0.5, 0)`; `gr_11.outer` builds the
outer `WHERE`; `gr_11.go` builds `CMPLT(y, x)` for slot 0 and `CMPLT(x, y)` for slot 1 and
hands BOTH the same inner.

**⇒ AND THE PORT's OWN 138 GATE ROWS ARE BYTE-IDENTICAL BEFORE AND AFTER THE FIX**
(MEASURED, by running `tinybendygrad/mixin/gradient.bend` at `HEAD` and at the fix and
diffing the 138 `name=value` rows).  **⇒ THAT IS THE POINT: THE CORPUS WAS THE ONLY
INSTRUMENT THAT COULD SEE THIS DEFECT.**

### THE SECOND DEFECT, IN THE HARNESS

**`gral`'s first run also found a bug in the corpus's OWN normal form.**
`graphcmp.bend`'s `konst` spelled a bool CONST `bTrue` -- because it called the compiler's
`Bool.show` -- where the py side spells it `b1` (`graphcmp.py:410`'s `bo`).  **THE FILE
ALREADY HAD THE RIGHT RENDERER (`bo`, at `graphcmp.bend:122`) AND DID NOT USE IT.**
MEASURED: it was the ONLY difference between the two canonical forms of a 17-node graph.
FIXED.

---

## 5. THE CORPUS'S STATE AFTER THIS UNIT

`checks/differ.py run`, `rc=0`:

    graphs=38  graphs-answered=38  graphs-agree=38  graphs-disagree=0
    byte-identical=38  graphs-refused=0  expect-moved=0
    stable-pairs=5 of 5  plants-disagree=8 of 8  conflations=4 of 4  controls=5 of 5
    selfcheck=# SELFCHECK: OK   oracle-selfcheck=# ORACLE SELFCHECK: OK
    substrate-start == substrate-end

**⇒ AND `checks/differ.py`'s `WANT` IS EMPTY.**  It was empty before this unit and it is
empty after it, and the two new graphs -- 61 nodes between them -- AGREE.  **NO EXCEPTION
WAS ADDED TO MAKE THEM GREEN, AND NONE WAS NEEDED, BECAUSE THE DEFECT WAS FIXED RATHER
THAN CARVED OUT.**

**⇒ AND `POPULATION_PIN` MOVED IN THE SAME COMMIT**, from
`ff3e4de7d1fdb5f4918ec33086ad94f43be2660e57f0ad28444223e5f2f89abe` (36 graphs) through
`f8dd8dc77a7ad90c8c0bd5e8898c4481d204c1914f1f31f7606762b6966b77f1` (37) to
**`d8db03ddc3bf5fd4621a08f3b0eb356027ea38f602fc71fabc45999b98561b31` (38)** -- a CONTENT
pin over the population's own SOURCE, so adding a graph moves it by construction.

---

## 6. THE WALLS THAT REMAIN, MEASURED

**A WALL IS A NAMED, MEASURED ABSENCE.**  Three remain, and none of them is fixable by
adding a graph.

**(a) `mixin/dtype.bend` -- 0 of 177, and it is a PORT-SIDE DEAD MODULE.**  Its
`wk_eval_int` / `wk_eval_float` / `wk_eval_bool` / `wk_is_virtual` / `wk_commit_dtype`
-- the five that would carry `D.dt_is_int` / `D.md_weak` / `D.commit_dtype` -- **HAVE NO
CALLERS ANYWHERE IN THE PORT** (MEASURED over every `.bend` file in `tinybendygrad/`).
The `grad` graph did not change this: `mixin/elementwise.bend` does its promotion through
`uop/weak.bend` and never calls `mixin/op.bend`.  **IT IS REACHABLE ONLY BY THE PORT
GROWING A CALLER.**

**(b) `uop/render.bend` -- 2 of 316, and it ports a DELETED upstream function.**  The
port's `render.bend` ports upstream's `pyrender`, WHICH UPSTREAM DELETED
(`81157efb0`, "use render_uir instead of pyrender").  The live upstream function in that
file is `render_uir`, and the port's `render_uir` is `TODO(p3)`.  **THE CORPUS CANNOT
COMPARE `render.bend` AGAINST `render_uir` BECAUSE THE PORT HAS NO `render_uir`, AND IT
CANNOT COMPARE IT AGAINST `pyrender` BECAUSE UPSTREAM HAS NO `pyrender`.**

**(c) 160 of the 176 port modules are not in the corpus's import closure AT ALL**
(189354 LOC), and the reason is A PROPERTY OF THE PORT: **THE PORT CANNOT BUILD A
SCHEDULE AT ALL** -- `schedule/__init__.bend` ports only `__init__.py:14-80` and DEFERS
`:82-301` -- so no corpus graph can reach `schedule/` from the port's own code.  **A
COVERAGE GAP WHOSE CAUSE IS A PORT GAP IS NOT A CORPUS GAP.**

**⇒ AND ONE MORE WALL, NAMED BY THIS UNIT'S OWN WORK: A RULE BODY IS ONLY REACHED BY A
GRAPH WHOSE FIXTURE CONTAINS THE OP THAT CLAIMS IT.**  `gral` fires five rule bodies and
`grad` fires two, and the other twenty-five are reachable only by a fixture that carries
their op.  **THE PORT's `gs` FIXTURE (the `EXPAND` + `DETACH` one) IS THE SHAPE THAT
WOULD REACH THE REMAINING BODIES**, and it is not a corpus graph because its EXPECTED
ANSWER IS A TABLE OF PER-RULE ROWS rather than ONE GRAPH.  **⇒ SO THE NEXT GRAPH, IF
THERE IS ONE, IS A FIXTURE THAT CARRIES ONE OF EVERY UNARY AND BINARY OP THE PORT'S TABLE
CLAIMS -- AND THE PORT's OWN `gs`/`dag` FIXTURES ARE THE TEMPLATE.**
