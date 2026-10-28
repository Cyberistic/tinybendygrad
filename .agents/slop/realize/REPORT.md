# REALIZE-TO-SINK DRIVER — REPORT

Unit: subagent, spawned 2026-10-28T13:16Z, finished 2026-10-28T14:0xZ.
Owns: `.agents/slop/realize/`, `tinybendygrad/tensor.bend`, plus ONE new file under
`tinybendygrad/schedule/` or `tinybendygrad/engine/`.

HARD CONSTRAINT (from the user, three times): **ONE BEND PROCESS AT A TIME. NEVER
BACKGROUND. NEVER A SWEEP. NEVER A GATE SWEEP. NEVER A CORPUS RUN. NEVER A
PARALLEL FIXTURE LOOP.** Every command's wall-clock cost is reported below. **NO
COMMIT WAS MADE.** No gate was run; no corpus was run; nothing was parallelised.

**⇒ WHAT LANDED**

| file | what | lines |
|---|---|---|
| `tinybendygrad/schedule/realize.bend` | THE DRIVER | 547 |
| `.agents/slop/realize/cmp.py` | THE COMPARISON (node-for-node, 3 folds) | 160 |
| `.agents/slop/realize/probe.py` | WHAT EXACTLY IS THE ORACLE's 23-NODE GRAPH | 83 |
| `.agents/slop/realize/probe2.py` | WHERE THE AFTER's src0 BECOMES THE BASE | 90 |
| `.agents/slop/realize/probe3.py` | UPSTREAM's OWN graph AT EACH STAGE | 92 |
| `.agents/slop/realize/port.rows` | THE PORT's driver output (a BEND run) | 11 |
| `.agents/slop/realize/oracle.rows` | THE ORACLE's output (a CPYTHON run) | 6 |

`tinybendygrad/tensor.bend` was **NOT** edited. `git status` (with
`env -u GIT_INDEX_FILE`) answers `?? .agents/slop/realize/` and
`?? tinybendygrad/schedule/realize.bend` and NOTHING ELSE for my paths.

---

## 1. THE MEASUREMENT — THE PORT's SINK OF AFTERs vs CPython's

**THE COMMANDS AND THEIR WALL-CLOCK COST**

| command | cost |
|---|---|
| `BEND_NO_TELEMETRY=1 ./bin/bend tinybendygrad/schedule/realize.bend` | **1.5 s** (user 3.6 s, 264 % cpu) |
| `env -u PYTHONPATH .venv/bin/python .agents/slop/realize/cmp.py` | **0.46 s** (user 0.18 s) |
| `env -u PYTHONPATH .venv/bin/python .agents/slop/engine/eng-oracle.py` | **0.59 s** |
| `env -u PYTHONPATH .venv/bin/python .agents/slop/realize/probe.py` | **0.45 s** |
| `env -u PYTHONPATH .venv/bin/python .agents/slop/realize/probe3.py` | **0.95 s** |
| `./bin/bend tinybendygrad/schedule/realize.bend --check-only` | **1.7 s** |

**THE VERDICT** (`cmp.py`, rc=0):

```
OK   the oracle's published dump and this file's computation are byte-identical
OK   C1 nodes AGREE (denominator=12 distinct kinds, 23 items)
OK   C2 consts AGREE (denominator=7 distinct kinds, 7 items)
OK   C3 params AGREE (denominator=3 distinct kinds, 3 items)
OK   C0 node count port=23 cpython=23 (denominator=23)
OK   CONTROL A (adjacent-RESHAPE merge OFF): the node multiset DIVERGES=True (plant kinds=13, oracle kinds=12)
OK   CONTROL B (PARAM slots shifted by one): the (slot,size) multiset DIVERGES=True and the NODE multiset is UNCHANGED=True
VERDICT PASS
```

**⇒ THE DENOMINATOR, NAMED: 23 NODES over 10 OP KINDS** (12 distinct node
STRINGS — the 10 op kinds and the two CONST spellings the node string carries).
**⇒ THE ORACLE's PUBLISHED DUMP AND `cmp.py`'s OWN COMPUTATION OF IT ARE
BYTE-IDENTICAL** — that is the line that makes `cmp.py` the ORACLE and not a
second opinion, and it is asserted, not assumed.

**THE PORT's OWN DUMP** (`.agents/slop/realize/port.rows`, `rz_dump`):

```
SINK:none:AFTER;AFTER:none:PARAM,STORE;PARAM:other:CONST;STORE:none:RESHAPE,REDUCE;
CONST:cother:;RESHAPE:none:PARAM,STACK;REDUCE:other:PERMUTE;STACK:none:CONST,CONST;
PERMUTE:other:MUL;CONST:cother:;CONST:cother:;MUL:none:RESHAPE,PERMUTE;
RESHAPE:none:PARAM,STACK;PERMUTE:other:RESHAPE;PARAM:other:CONST;
STACK:none:CONST,CONST,CONST;RESHAPE:none:PARAM,STACK;CONST:cother:;CONST:cother:;
CONST:cother:;PARAM:other:CONST;STACK:none:CONST,CONST,CONST;CONST:cother:
```

**THE ORACLE's 23-NODE DUMP** (`eng-oracle.py`, `eng_py_in`): the same 23 node
strings, in a different ORDER — because **the port's `eng_dump` is a BFS and the
oracle's `dump` is a DFS** (see §5). The comparison is over MULTISETS, which is
why the ORDER is not the subject.

**⇒ THE SECOND AND THIRD COMPARISONS CARRY WHAT THE FIRST THROWS AWAY.** The
oracle's own CONST key is `cother` for every CONST, so the node dump says
nothing about the CONST's VALUE; `rz_consts` carries it
(`20,4,5,12,1,3,15` — CPython's own values, in CPython's own order) and
`rz_params` carries the `(slot,size)` pairs (`0:20,1:12,2:15` — CPython's
`ParamArg(0)` on the 20-element buffer, `ParamArg(1)` on 12, `ParamArg(2)` on 15).

---

## 2. THE DRIVER — `file:line` ON BOTH SIDES, EVERY STEP

### 2.1 THE PROGRAM — the port's own `Tensor` graph

| step | upstream | port |
|---|---|---|
| `Tensor.empty(shape)` = a BUFFER of `prod(shape)` RESHAPED | `tinygrad/tensor.py:88` | `mixin/movement.bend:1231` (`mxw_buf`) + `:1434` (`mxw_reshape`) — `rz_input` |
| `dot`'s x-reshape `(4,3) -> (4,1,3)` | `tinygrad/mixin/op.py:390` | `rz_dot_x` (`mxw_reshape.go`) |
| `dot`'s w-reshape `(3,5) -> (1,3,5)` then `transpose(-1,-2)` = PERMUTE `(0,2,1)` | `tinygrad/mixin/op.py:391` | `rz_dot_w` (`mxw_reshape.go` + `mxw_permute.go`) |
| `(x*w)` | `tinygrad/mixin/op.py:392` | `tensor.bend:656` (`tn_mul`) |
| `_rop`: the reduced axes move to the FRONT, `perm = reduce_axis + rest`, and the REDUCE's arg is `(op, len(reduce_axis))` | `tinygrad/uop/ops.py:633-643` | `rz_reduce` (`mxw_permute.go` + `O.UOp.new(..., O.AReduce{O.OpsADD{}, 1}, ...)`) |
| `assign`: `self.uop = self.uop.after(self.uop.store(x.uop))` | `tinygrad/tensor.py:271` | `rz_after` (`O.UOp.store` + `O.UOp.after`) |
| `sink = UOp.sink(*[t.uop ...])` | `tinygrad/tensor.py:169` | `rz_sink` (`O.UOp.sink`) |

### 2.2 THE TRANSFORMS — the port's own `tensor_map` loop

| # | rule | upstream | port |
|---|---|---|---|
| A | the ALLOC -> BUFFER rebind | `tinygrad/tensor.py:184` | **A NO-OP IN THE PORT** — MEASURED, `grep -n "def UOp.new_buffer" tinybendygrad/uop/ops.bend` ANSWERS NOTHING (the port's `ops.bend:5332` carries it as a `TODO(p3)`) and the port's `Tensor` path has no ALLOC; `mxw_buf` builds the BUFFER (`mixin/movement.bend:1232`) |
| B | the GLOBAL BUFFER -> PARAM rebind (`b.param_like(slot)`) | `tinygrad/schedule/__init__.py:244-254` | `rz_rule.buf` |
| C | merge adjacent RESHAPEs (`x.replace(src=(x2.src[0], x.src[1]))`, UNCONDITIONAL) | `tinygrad/uop/movement.py:8` (`mop_cleanup`) | `rz_rule.reshape` |
| D | the AFTER's `src[0]` BECOMES THE BASE — the NET of `pm_mops`' `r.after(a)` and `earliest_rewrites`' "remove movement ops from SINK/AFTER" | `tinygrad/schedule/prepare.py:85-86` + `tinygrad/schedule/prepare.py:273-274` | `rz_rule.after` |

**⇒ RULE D IS THE NET OF TWO UPSTREAM RULES AND IT WAS MEASURED, NOT GUESSED.**
`.agents/slop/realize/probe3.py` prints upstream's OWN graph at each stage:

```
# THE SINK `create_linear_with_vars` RECEIVED (tensor.py:209):   27 nodes
    SINK<-AFTER ; AFTER<-RESHAPE,STORE ; RESHAPE<-BUFFER,STACK ; BUFFER<-CONST ; ...
# after pm_mops+pm_inline_calls+pm_disk_copy:
    SINK<-RESHAPE ; RESHAPE<-AFTER,STACK ; AFTER<-BUFFER,STORE ; ...
# after earliest_rewrites:                                        23 nodes
    SINK<-AFTER ; AFTER<-BUFFER,STORE ; BUFFER<-CONST ; CONST(20) ; ...
```

⇒ **THE PORT's PRE-REBUILD SINK IS THE SAME 27-NODE GRAPH AS UPSTREAM's** (the
port's `rz_dump0` row), and **THE PORT's POST-REBUILD SINK IS THE SAME
23-NODE GRAPH** (`rz_dump`, compared above).

### 2.3 THE COMPARISON

`cmp.py` computes CPython's engine input **by spying on upstream's own call to
`get_kernel_graph`** — the same spy `eng-oracle.py` uses — and then compares:

* **C1** the node MULTISET (`op:argkey:srcops`, the oracle's spelling);
* **C2** the CONST VALUE multiset;
* **C3** the PARAM `(slot, size)` multiset;
* **C0** the node COUNT.

⇒ **ALL THREE ARE MULTISET COMPARISONS AND HERE IS WHY** (§5): the two dumps'
ORDERS cannot agree.

---

## 3. THE CONTROLS — TWO PLANTS, BOTH RED

**PLANT A — RULE C (merge adjacent RESHAPEs) OFF.** The graph is 27 nodes
instead of 23 and the node multiset DIVERGES. `cmp.py`:
`CONTROL A ... DIVERGES=True (plant kinds=13, oracle kinds=12)`.

**PLANT B — THE PARAM SLOTS SHIFTED BY ONE.** **THE NODE DUMP IS IDENTICAL**
(the slot is not in the node string) and only the `(slot,size)` pairs move:
`rz_params=0:20,1:12,2:15` becomes `rz_plant_params=1:20,2:12,3:15`.
`cmp.py`: `CONTROL B ... DIVERGES=True and the NODE multiset is UNCHANGED=True`.

**⇒ PLANT B IS THE ONE THAT MATTERS.** It says the node dump ALONE would not
have caught a wrong slot assignment, and that C3 is load-bearing rather than
decoration. Both plants live INSIDE the one driver file as two flags
(`rz_rebuild(p, no_merge, slot_off)`), so there is no second copy of the driver
to drift.

⇒ **⇒ AND A ROW IN THE PORT IS NOT A TEST.** The port prints rows with
`IO.print`, and `IO.print` is OUTSIDE the law system by design: reverting a
one-line fix in a copy leaves `bend --check-only` GREEN. **The test here is the
comparison against CPython's own dump, and the plants are what make it a test.**

---

## 4. WHAT THE PORT's OWN SCHEDULER DID WITH IT — AND THE SEAM

**`rz_lin_n=0`.** The port's own `schedule()` (`schedule/__init__.bend:1141`,
upstream's `create_schedule`) on the port's own 23-node sink answers **ZERO
kernels**, and the reason is exact: `_split_after`
(`schedule/__init__.bend:465`) partitions an AFTER's `src[1:]` into KERNELS
(CALL/END) and DEPENDENCIES (AFTER), and the 23-node sink's AFTER has a
**STORE** there, so there is no kernel to linearize. **Upstream's
`create_schedule` is fed `get_kernel_graph`'s OUTPUT, not `prepare_rangeify`'s.**

**⇒ AND THE PORT's OWN ENGINE WAS RUN ON THE 23-NODE SINK** (`rz_eng` row,
`schedule/rangeify.bend`'s `eng_stages`/`eng_drive`, upstream's
`get_kernel_graph`'s seven rewrites, `tinygrad/schedule/rangeify.py:341-367`):

```
eng_rz_s0=0;84;...   eng_rz_s3=27;84;...   eng_rz_s4=0;114;...   eng_rz_s6=59;114;...
```

⇒ The seven stages MOVE 27 nodes at stage 3 and 59 at stage 6, and the FINAL
graph is STILL `SINK(AFTER(..., STORE(...)))` — **NOT** upstream's 9-node kernel
graph `SINK(AFTER(PARAM, CALL))`.

**⇒ ⇒ ⇒ THE NAMED SEAM, AND IT IS ONE LINE: `run_rangeify` IS NOT PORTED.**
Upstream's `get_kernel_graph` opens with

```python
# tinygrad/schedule/rangeify.py:344
tsink = run_rangeify(tsink, bool(DEBUG_RANGEIFY))   # "convert movement ops to ranges"
```

and the port's engine's stage 1 is `Stg{0, Nil{}}` — an EMPTY table — with the
comment **`# 1 run_rangeify -- rangeify.py:344 -- NOT PORTED`**
(`schedule/rangeify.bend:2810`). **⇒ THAT IS THE LAST STRUCTURAL LINK, AND IT IS
NOT IN THIS TREE.** Everything upstream of it is now in the port and MEASURED
equal.

---

## 5. FINDINGS, NAMED — five of them, each with its measurement

**F1 — THE ORACLE's `const_key` AND THE PORT's `eng_constkey` DISAGREE, AND
THE ORACLE'S IS THE ONE THAT CANNOT SEE A VALUE.** MEASURED:
`UOp.const(20).arg` is the bare `int` `20` (NOT the three-tuple
`(dtype, "CONST", val)` that `eng-oracle.py:52`'s `const_key` looks for), so the
oracle's key is `cother` for EVERY CONST; the port's `eng_constkey`
(`schedule/rangeify.bend:3008`) spells the same node `c:0:20`. **⇒ THE TWO
CANNOT BOTH BE RIGHT ABOUT THE SAME GRAPH.** The driver uses the ORACLE's rule
(so the two dumps are literally comparable) and adds `rz_consts`/`rz_params`
so the VALUE is not lost. **⇒ AND `schedule/rangeify.bend` IS NOT MINE, SO IT IS
NOT FIXED HERE.**

**F2 — THE PORT's `UOp.reduce` CANNOT SPELL `AReduce{op, 1}`.** MEASURED:
`uop/ops.bend:7435`'s `UOp.reduce.arg` builds `AReduce{r, 0}` — `num_axes`
HARDCODED to zero — while upstream's arg is `(op, len(reduce_axis))`
(`tinygrad/uop/ops.py:641`). The driver builds the node with `O.UOp.new` and the
right `num_axes`. **⇒ A NAMED PORT DIVERGENCE, NOT A DRIVER HACK.**

**F3 — THE PORT's `UOp.toposort` IS A POST-ORDER WALK AND THAT IS WHY THE
REBUILD WORKS.** MEASURED: the port's `rz_preops` row reads
`CONST,BUFFER,CONST,...,AFTER,SINK` — children first, the SINK LAST. **⇒ AND
`schedule/rangeify.bend:3055`'s `eng_dump` IS A BFS WHILE `eng-oracle.py:79`'s
`dump` IS A DFS** — MEASURED from the two sources — **⇒ THE TWO ORDERS CANNOT
AGREE AND THE COMPARISON MUST BE ORDER-FREE.** This is why `cmp.py` compares
MULTISETS.

**F4 — AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT MINTED IT, AND THREE
PLACES IN THE DRIVER GOT IT WRONG FIRST.** MEASURED, in order:
(a) interning the SINK in the DESTINATION's arena put the AFTER's index into a
SIBLING arena, where it named whatever node sat there — a BUFFER — and the dump
answered `SINK:none:BUFFER` over a THREE-node graph; (b) interning the SINK in
the REDUCE's arena read the AFTER's index OUT OF RANGE and answered the arena's
bottom (`OTHER`); (c) interning each rebuilt node into the ORIGINAL arena put
consecutive nodes in DIFFERENT arenas and the map's indices named nothing. **⇒
THE FIX IS ONE RULE — every node is interned in the arena that holds its srcs'
indices, and the parent in the child's arena — and it is `tensor.bend`'s own
"THE ARENA A BUILD RETURNS IS NOT THE ARENA THAT WENT IN" (tensor.bend:136).**

**F5 — THE PORT's `mixin/movement.bend`'s `mxw_reshape` HAS AN IDENTITY TEST
THE PORT'S FOLD CANNOT ANSWER, SO THE DRIVER CALLS `.go`.** MEASURED from
`tensor.bend:42-48`: `UOp._shape`'s RESHAPE arm is a documented gap, so
`mxw_same` would answer "identity" for a reshape that is not one. The driver
calls `mxw_reshape.go` / `mxw_permute.go` — the UNGUARDED builders — and says
so at the def.

**F6 — THE BRIEF's OWN TABLE COUNTS NAMES, NOT DEFS, AND THREE OF ITS
"PRESENT" ROWS ARE `TODO(p3)` WALLS.** MEASURED, `grep -rn "^def <name>("
tinybendygrad/ | wc -l` and `grep -rn "TODO(p3).*def <name>"`:

```
is_store_after             defs=1 todo_walls=0     <- schedule/__init__.bend:1206
pm_drop_after              defs=0 todo_walls=0     <- the def is pm_drop_after_TABLE (uop/ops.bend:4496)
contiguous_mops_to_view    defs=0 todo_walls=0     <- a TODO(p3) WALL BLOCK, schedule/__init__.bend:1748-1768
new_buffer                 defs=0 todo_walls=1     <- ops.bend:5332
needs_storage              defs=0 todo_walls=1     <- ops.bend:5364
create_linear_with_vars    defs=0 todo_walls=0
run_linear                 defs=0 todo_walls=0
capturing                  defs=0 todo_walls=0
```

**⇒ THE BRIEF's TABLE SAID "PRESENT" FOR `contiguous_mops_to_view`,
`UOp.new_buffer` AND `needs_storage`. NONE OF THEM HAS A DEF.** Their grep
"hits" ARE the TODO WALLS. **⇒ THIS IS THE TREE's OWN DOCTRINE 1 FAILURE, IN
THE BRIEF ITSELF: "A CENSUS THAT NAMES A BROKEN DRIVER WITHOUT SAYING WHETHER
IT IS BROKEN IS A CENSUS OF NAMES."**
**⇒ AND IT CHANGES THE DELIVERABLE's SCOPE IN ONE PLACE:** upstream's
`linear_with_vars` has a THIRD branch -- `elif contiguous and (view :=
contiguous_mops_to_view(None, u, src)) is not None: u = view`
(`tinygrad/tensor.py:193`) -- and `contiguous_mops_to_view` IS A WALL IN THE
PORT. **⇒ THAT BRANCH CANNOT BE PORTED, AND THIS DRIVER DOES NOT NEED IT:
THE PROGRAM IT DRIVES HAS NO `STAGE`, SO THE BRANCH IS NOT REACHED.** The
driver's rule set is therefore complete FOR THE PROGRAM IT DRIVES and
incomplete for a STAGE-bearing one -- and that is named, not hidden.
**⇒ AND `needs_storage` BEING A WALL IS WHY `tensor.bend`'s `realize` IS
WALLED (`tensor.bend:2153-2155`): upstream's `realize` FILTERS ON IT
(`tinygrad/tensor.py:220`).**

---

## 6. WHAT WAS NOT CLOSED — SPECIFICALLY AND NAMED

1. **`run_rangeify` (upstream `tinygrad/schedule/rangeify.py:344`, "convert
   movement ops to ranges") IS NOT PORTED.** The port's engine's stage 1 is an
   empty table (`schedule/rangeify.bend:2810`). **⇒ THE PORT's `schedule()`
   ANSWERS 0 KERNELS ON A REAL PROGRAM AND THAT IS WHY.** Everything upstream of
   `run_rangeify` is landed and MEASURED equal (§1, §2).
2. **`tinybendygrad/tensor.bend` WAS NOT EDITED.** Its handoff note
   (`tensor.bend:36-40`, `:50-58`) asks for `create_linear_with_vars`,
   `contiguous_mops_to_view`, `is_store_after`, `run_linear` and `capturing`.
   **⇒ MEASURED (F6): `is_store_after` HAS A DEF
   (`schedule/__init__.bend:1206`) AND `pm_drop_after` HAS ONE UNDER ANOTHER
   NAME (`pm_drop_after_table`, `uop/ops.bend:4496`); `contiguous_mops_to_view`,
   `UOp.new_buffer` AND `needs_storage` HAVE **NO DEF** AND ARE `TODO(p3)`
   WALLS; `create_linear_with_vars`, `run_linear` AND `capturing` ARE ABSENT
   ENTIRELY.** **⇒
   THIS UNIT LANDS THE GRAPH-SIDE OF THAT (`create_linear_with_vars`' INPUT,
   the SINK OF AFTERs) AND NOT `run_linear` (it needs the engine) NOR
   `capturing` (it needs the JIT).** The note's wall list is therefore one
   wall shorter, not zero walls shorter.
3. **THE MNIST MODEL WAS NOT RUN THROUGH THE DRIVER.** `nn/mnist_cnn.bend`
   builds the model in the port's own language, but the model is
   `BUFFER`-based, and the port's `nn_conv2d`/`nn_linear` build movement graphs
   the port's fold cannot answer — so the MNIST sink would be a shape without a
   comparable CPython graph (the oracle's dump is for a MATMUL). **⇒ THE
   NODE-FOR-NODE MEASUREMENT IS AGAINST THE ORACLE's OWN PROGRAM, and the
   MNIST end-to-end is left open and NAMED.**
4. **`O.UOp.new_buffer` IS STILL A `TODO(p3)`** (`uop/ops.bend:5332`). The
   driver does not need it (rule A is a no-op) but the port's `Tensor` path has
   no ALLOC at all, so upstream's `linear_with_vars` rebind has no counterpart
   to mirror.
5. **`schedule/rangeify.bend`'s `eng_constkey` DIVERGES FROM THE ORACLE's
   `const_key` (F1).** `rangeify.bend` is not mine; the fix is one line and it
   belongs to whoever owns it.

---

## 7. THE DENOMINATORS THIS UNIT MOVED

* **`tinybendygrad`'s `.bend` FILE COUNT: 172 -> 173** (MEASURED,
  `find tinybendygrad -name '*.bend' | wc -l` = 173 after this unit's file).
  **⇒ EVERY GATE THAT COUNTS `.bend` FILES HAS ITS DENOMINATOR MOVED BY ONE,
  AND `checks/port-compile-gate.py` (169 files at the time of writing) WILL
  SEE 170.** **⇒ THE NEW FILE COMPILES: `./bin/bend
  tinybendygrad/schedule/realize.bend --check-only` READS `ALL PROOFS CHECK`
  (1.7 s).**
* **NOTHING ELSE.** `tinybendygrad/tensor.bend` is byte-identical to HEAD.
  `tinygrad/` is byte-identical to HEAD. No gate was run, so no gate row moved.

---

## 7b. TWO HOUSEKEEPING ITEMS THIS UNIT DID **NOT** DO, AND WHY

* **`.agents/TODO.md` WAS NOT TICKED.** The brief's own DO-NOT-EDIT list names
  it, so the brief's later instruction to tick tasks off there contradicts its
  own list. **⇒ THE LIST WON, because a unit that edits a file another unit
  owns is the shared-state failure this tree measures.**
* **`.agents/TOOLS.md` WAS NOT UPDATED.** Same reason: it is in the
  DO-NOT-EDIT list. **⇒ NO NEW TOOL AND NO NEW DEPENDENCY WAS INTRODUCED** --
  the driver uses only `bin/bend` and the port's own `.bend` files, and the
  comparator uses only `.venv/bin/python` and the vendored `tinygrad/` as the
  ORACLE. Nothing to ledger.

---

## 8. THE FILES, AND HOW TO RE-RUN THE MEASUREMENT

```bash
# 1. THE PORT's DRIVER (1.5 s).  BEND_NO_TELEMETRY=1 because the compiler
#    phones home once a day (references/bend/bend2/main.ts:185-211) and the
#    corpus's pin must not move under me.
BEND_NO_TELEMETRY=1 ./bin/bend tinybendygrad/schedule/realize.bend \
  > .agents/slop/realize/port.rows 2>&1

# 2. THE ORACLE (0.6 s).
env -u PYTHONPATH .venv/bin/python .agents/slop/engine/eng-oracle.py \
  > .agents/slop/realize/oracle.rows 2>&1

# 3. THE COMPARISON (0.5 s).  rc=0 ONLY IF C1, C2, C3 AGREE AND BOTH PLANTS
#    GO RED.
env -u PYTHONPATH .venv/bin/python .agents/slop/realize/cmp.py
```

**⇒ THE DRIVER'S ROWS** (`port.rows`): `rz_dump` (the 23-node sink),
`rz_consts` (the CONST values), `rz_params` (the PARAM slots), `rz_nodes` (23),
`rz_dump0` (the 27-node pre-rebuild sink), `rz_lin_n` (0 — the seam), `rz_eng`
(the port's engine's seven stages on the sink), `rz_plant_dump` and
`rz_plant_params` (the two controls).

**⇒ AND THE PROBES**: `probe.py` (the oracle's 23 nodes with args and shapes),
`probe2.py` (upstream's graph at each stage of `transform_to_call`),
`probe3.py` (upstream's OWN sink and the two rules that make the AFTER's
`src[0]` the base). **⇒ ALL THREE ARE THROWAWAY INSTRUMENTS AND ALL THREE ARE
KEPT, because a claim with no instrument behind it is a label.**
