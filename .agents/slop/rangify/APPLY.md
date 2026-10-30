# THE PORT's `run_rangeify` -- THE APPLY REWRITE

**MEASURED 2026-10-29.** `tinybendygrad/schedule/rangify.bend` is the port's
`run_rangeify` driver. This file records what the APPLY half now does, what
it measures, and what it does NOT do.

## THE INSTRUMENT

| file | what it is | cost |
|---|---|---|
| `.agents/slop/rangify/rr-oracle.py` | SPY ON UPSTREAM's OWN `run_rangeify`; prints CPython's own `realize_map`, `range_map` and the 27-node graph it RETURNS | ~2 s, one CPython process |
| `.agents/slop/rangify/rr-rules.py` | ASKS UPSTREAM's OWN `PatternMatcher` ABOUT EVERY NODE of the same program and prints what each one BECOMES | ~2 s, one CPython process |
| `.agents/slop/rangify/cmp-out.py` | RUNS THE PORT AND COMPARES `rr_out` WITH `rr_py_out` **NODE FOR NODE** | ~1 s, one Bend process |

**THE COMPARISON IS OVER MULTISETS**, and both sides are the same spelling
(`op:argkey:srcops`, joined by `;`), so it is whole-string with no translator.

## WHAT WAS WRONG, AND HOW IT WAS FOUND

**FOUR SEPARATE DEFECTS, ALL OF THE CLASS THIS TREE NAMES: A RESULT THAT
NOTHING READS, OR A KEY THAT IS NOT THE KEY.**

1. **THE APPLY WAS **ONE** RULE, NOT A FIXED POINT.** Upstream's
   `unified_rewrite` (`ops.py`) runs the matcher in a **fixed-point loop**
   (`while test_n is not None: new_n, test_n = test_n,
   self.cached_bpm_rewrite(test_n)`). A `RESHAPE` is therefore rewritten
   **TWICE**: once by **RULE 4** (which puts an `INDEX` in its `src[0]`) and
   then again, and the **second** pass takes **RULE 5**. **MEASURED** by
   `rr-rules.py`: `RESHAPE -> RESHAPE`, `PERMUTE -> MUL`, `REDUCE -> REDUCE`,
   `STORE -> None`. The port applied one rule and produced **the unchanged
   input graph**.

2. **RULE 4 MUST RETURN **NONE** WHEN IT CHANGES NOTHING.** `PatternMatcher.
   rewrite` skips a rule that returns the node itself (`ret is not uop`), and
   that is what lets **RULE 5** see the same node.

3. **RULE 5 IS **A **MOVEMENT** OP's RULE** (`UPat(GroupOp.Movement)`).
   Leaving the movement test out made it fire on **every node in the range
   map** -- and the port's own range map has **six CONSTs and three PARAMs** in
   it. A `CONST` has **no `src[0]`**, so the answer was **the bottom** (node
   0). **MEASURED**: `1->0:CONST:cother:/OTHER:other:`.

4. **THE ARENA IS **A VALUE** AND `+` IS **A REUSABLE LET**, NOT A REBINDING**
   (`bend guide`: *"`x = v  +x = v  -x = v` -- a let: affine, reusable,
   erased"*). A def that mints a node must hand the **grown** arena back, and
   the port's spelling for that is **`Found{ar, i}`** (`ops.bend:2718`), read
   with **`O.Found.ar(f)`** -- the pattern `realize.bend:113` already uses. The
   first attempt dropped the arena (`O.Found.i(f)` alone), which put every new
   node in **a phantom arena** and made the reads below it read **the old
   arena's** entry.

**⇒ AND TWO MORE, FOUND BY THE ROW THAT DUMPS BOTH SPELLINGS:**

5. **THE PORT's RANGE MAP IS **A TABLE**,** so a range is a **table index**
   until `indexing.bend:901`'s `ix_rg_node` materialises it. The apply used
   the table indices as **node** indices. **MEASURED**:
   `29->43:...INDEX:none:PARAM,CONST,BUFFER` -- a `CONST` and a `BUFFER` where
   two `RANGE`s belong.

6. **THE FRESH NODES MUST BE FINALISED TOO.** Upstream's stack walks the
   `INDEX`, `END` and `STAGE` the rewrite created. **MEASURED** without it:
   the `END`'s src was **the old** `STORE`.

## WHAT THE APPLY NOW MEASURES

```
$ env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/cmp-out.py
port_nodes=22
cpython_nodes=27
AGREE=9  ONLY-PORT=4  ONLY-CPYTHON=9
port   : ['AFTER', 'CONST', 'END', 'INDEX', 'MUL', 'PARAM', 'RANGE', 'REDUCE', 'SINK', 'STORE']
cpython: ['ADD',  'AFTER', 'CONST', 'END', 'INDEX', 'MUL', 'PARAM', 'RANGE', 'REDUCE', 'SINK', 'STORE']
```

**THE OP CENSUS MATCHES EXCEPT FOR `ADD`.** The node-for-node comparison:

| the port | CPython | why |
|---|---|---|
| `INDEX:none:PARAM,RANGE,RANGE` | `INDEX:none:PARAM,ADD` | **THE AFFINE EXPRESSION** -- see the wall below |
| `INDEX:none:PARAM,CONST,RANGE,RANGE` | `INDEX:none:PARAM,ADD` | the same |
| `INDEX:none:PARAM,RANGE,CONST,RANGE` | `INDEX:none:PARAM,ADD` | the same |
| -- | `ADD:none:MUL,RANGE` x3 | the affine expression's own nodes |
| -- | `MUL:none:RANGE,CONST` x3 | the affine expression's own nodes |
| `CONST:cother:` | -- | **THE PORT's OWN EXTRA CONST** -- the range map's three extra `CONST` entries (W-E) |

**⇒ AND `REDUCE:other:MUL,RANGE` IS NOW AN **AGREEMENT**, NOT A DIFFERENCE.** IT WAS
THE ROW THIS FILE NAMED AS *"THE RANGE MAP's OWN DIFFERENCE"* (the port's table held a
`CONST 0` where upstream holds a `RANGE`), AND **THE FIX THAT CLOSED IT WAS NOT IN THE
APPLY AT ALL** -- IT WAS IN THE RANGE MAP's TABLE (W-D, BELOW).

**⇒ THE GRAPH'S SHAPE IS NOW CPython's SHAPE**: `SINK(AFTER(PARAM, END))`,
`END(STORE, RANGE, RANGE)`, `STORE(INDEX, REDUCE)`, `MUL(INDEX, INDEX)`,
`REDUCE(MUL, RANGE)`.

## THE WALLS, NAMED

* **W-A -- THE AFFINE RANGE EXPRESSION.** Upstream's `_apply_reshape`
  (`indexing.py:149-161`) builds the RESHAPE's input ranges as
  `UOp.const(0).usum(axes_in)` with `%` and `//`, and simplifies them with a
  **`symbolic` rewriter**. The port has **no `where`, no `usum`, no `%`, no
  `//` and no `symbolic` rewriter**, so the port's RESHAPE keeps its **plain
  ranges** where upstream has **one affine expression**. **⇒ AND THE PORT's
  OWN `apply_movement_op` IS THE IDENTITY FOR `RESHAPE`** (`rangify.bend`'s
  header says so, and it is the same wall).
* **W-B -- `PAD` AND `STACK`.** Upstream's rules 2 and 3 need `where` and
  `%`. The port **counts** them instead of pretending (`rr_wall`, and the
  measured value is **0** for this program).
* **W-D -- THE `R2` AXIS -- CLOSED 2026-10-30.** Upstream's `R2` is **a
  `RANGE`**; the port's was **nothing at all**. `rr_p4.reduce` computes the
  REDUCE-AXIS RANGE with `rr_new.all` -- WHICH APPENDS IT TO THE TABLE AND TAKES
  ITS INDEX FROM THE TABLE's LENGTH (`rr_new.one`) -- AND THEN BUILT THE NEW
  STATE WITH `RrMap.put`, **WHICH KEEPS `RrMap.tbl(m)`: THE TABLE AS IT WAS.**
  **⇒ SO THE RANGE's INDEX POINTED AT A TABLE THAT NEVER RECEIVED IT**, AND THE
  PORT's TABLE HELD **NO RANGE WITH EXTENT 3** (`0:1:0 0:0:4 1:0:5`; IT NOW
  READS `0:1:0 0:0:4 1:0:5 2:0:3`). **⇒ MEASURED, THE PORT AND THE FIX ON THE
  SAME COMPILER, IN A PRIVATE COPY OF THE TREE: BEFORE `port_nodes=20 AGREE=8
  ONLY-CPYTHON=11`, AFTER `port_nodes=22 AGREE=9 ONLY-CPYTHON=9`, AND THE ONE
  AGREEMENT THE FIX ADDED IS `REDUCE:other:MUL,RANGE`.**
* **W-E -- THE THREE EXTRA `CONST` ENTRIES -- CLOSED 2026-10-30.** The port's
  range map had **14** entries and upstream's **11**; the three extra were the
  `CONST` nodes at toposort positions 0, 6 and 12. **⇒ THE CAUSE WAS **ONE
  LINE**: `rangify.bend`'s `rr_dsrcs` READ `ix_ds_zero` -- WHICH MEANS "THIS OP
  HAS ZERO DATA SRCS", AND IS HOW `indexing.bend`'s OWN `ix_ds_n.of` READS IT --
  AS "TAKE ONE", SO **A `PARAM` CONTRIBUTED ITS FIRST SRC AS A DATA SRC**
  (`data_srcs` RETURNS **NO** SRCS FOR A `PARAM`, `indexing.py:69`) AND EVERY
  `CONST` THAT FEEDS A `PARAM` LOOKED CONSUMED. **⇒ THE LIST FORM NOW LIVES
  BESIDE THE LENGTH FORM, IN `indexing.bend` ITSELF (`ix_ds_list`).** **⇒ AND
  `.agents/slop/rmap/cmp.py` NOW READS **5 of 11 AGREE (denominator=11), 6
  DIFFER, 0 MISSING**, AND ALL SIX DIFFERENCES ARE **W-A** -- **⇒ AND THE
  PREVIOUS "5 of 11, all six are one wall" CLAIM WAS **NEVER** WHAT THE
  INSTRUMENT SAID** (IT READ `1 of 14`) **AND IS NOW TRUE FOR A REASON THE
  CLAIM NEVER NAMED** -- see `.agents/slop/rmap/RANGE.md`.
* **W-C -- THE REALIZE MAP's DELETION.** Upstream does `del
  ctx.realize_map[s]` when a `STORE` becomes an `END` (`indexing.py:88`), and
  the port's context is an immutable value and cannot delete. **⇒ AND THE
  PORT'S FRESH-NODE FINALISATION IS THEREFORE **A REMAP AND NOTHING ELSE**,
  WHICH IS EQUIVALENT** (a `STAGE` and an `INDEX` match no rule, and an
  `END`'s rule-4 result is unchanged precisely because upstream deleted the
  store).

## THE ROWS THE PORT NOW PRINTS

* `rr_out` -- the rangeified graph, the port's spelling.
* `rr_map` -- the `(old, final)` pairs of the walk.
* `rr_arena` -- **every pair with BOTH spellings** (`old->new:old/new`), which
  is the row that found defects 3, 5 and 6.
* `rr_wall` -- how many nodes hit **W-B**.

## WHAT IS STILL NOT DONE

* **`run_rangeify` IS NOT THE WHOLE OF `get_kernel_graph`.** Upstream's
  `rangeify.py:347-360` then runs `symbolic+pm_reduce_simplify+
  pm_const_buffer_folding+pm_remove_bufferize`, `pm_limit_bufs`,
  `pm_add_buffers`, `pm_no_indexing_calls`, `split_kernels` and `pm_no_views`.
  **⇒ AND EVERY ONE OF THOSE IS **A `symbolic` REWRITER** TOO.**
* **⇒ AND SO THE PORT's `schedule()` STILL ANSWERS **ZERO** KERNELS FOR THE
  PORT's OWN PROGRAM**, **=> BECAUSE `get_kernel_graph` IS NOT DONE**, **=> AND
  NOT BECAUSE OF ANYTHING IN THIS FILE.**
