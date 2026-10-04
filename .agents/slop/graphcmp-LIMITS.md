# graphcmp -- WHAT IT DOES NOT COMPARE, and what it got wrong.

Every item here is MEASURED on this tree, and every one is printed by the tool rather than
living only in this file: the ledger rows are on every report, the denominators are on
every verdict, the ops census with per-op NODE counts is on every report, and `selfcheck`
plus the census's own three assertions are the ones that are assertions rather than counts.
What this file adds is the reasoning, and the items that CANNOT be printed.

Run: `E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`
(`E` is also the prefix in `runs/graphcmp/D/README-D.txt`.)
Regenerate everything: `sh .agents/slop/graphcmp-run.sh`
Check reproducibility: `sh .agents/slop/graphcmp-repro.sh` -- **MEASURED 2026-10-04:
158 of 158 files byte-identical across two clean runs**, sha256 over non-blank lines.

**THE THREE ROUNDS.** The first built 9 graphs / 63 nodes / 13 of 77 ops and found eleven
defects in the differ's own normal form. The second added four graphs -- `group`,
`commute`, `indexed`, `sym` -- and four more, of which two were in a check that had been
reporting `PASS` over nothing. The third (this file's §6) added three graphs -- `lin`,
`loop`, `gate` -- whose PY side is a call into tinygrad's own scheduler and codegen rather
than a hand-built expression, and found six more. Current state, MEASURED and printed by
`runs/graphcmp/D/D0-run-summary.txt` and `D0-coverage-census.txt`:

    graphs 16   AGREE 14 (lin/loop DISAGREE, each with a named measured cause)   nodes 189 per side
    ops 34 of 77   commutative ops 7 of 8   symbolic-dim nodes 2 of 189 (BOTH SIDES, see 3b)
    field-records 1134 per side   byte-identical 14 of 16   stable pairs 5 of 5
    selfcheck OK   oracle-selfcheck OK   controls 5 of 5   conflations 4 of 4   repro 158/158

**THE LIMIT THAT WAS CLOSED WHILE THIS ROUND RAN.** §3b's symbolic-dim wall was OPEN when
this unit started and is CLOSED now: `uop/fold.bend`'s `sym_dim.pa` (`fold.bend:1296`, the
`AParam` arm of `sym_dim.of`) landed from the `fold` unit, `--graph sym` reads `?=0` and
`VERDICT: AGREE` at 12 of 12, and the port now mints a symbolic dim. Three pinned numbers
moved with it -- `selfcheck`'s `?=6` row, `graphcmp-run.sh`'s `sym:DISAGREE`, and
`graphcmp-repro.sh`'s `graphs-agree=13` -- and §3c is the table of what moved and why. **A
limits file left claiming a resolved limit is worse than one that never had it**, and so is
an assertion pinned to a bug that is gone: the `?=6` row was a regression row for a defect
that no longer existed, which made a FIX look like a break.

---

## 0. WHAT ROUND THREE CLOSED, AND WHAT IT COST

The first line of this file used to read:

> **13 of 77 ops** -- *"These are hand-built graphs, not a kernelized program, and they
> exercise not one of `INDEX`/`BARRIER`/`GROUP`/`ENDIF`/`BACKEDGE`/`LOAD`/`STORE`."*

**RESOLVED, at 34 of 77 ops.** `INDEX`, `BARRIER` and `GROUP` had been reached by hand in
round two; `ENDIF`, `BACKEDGE`, `LOAD` and `STORE` could not be, because they are
properties of a SCHEDULE and not of an expression. Three graphs closed that, and the
interesting part is HOW, because the answer was not the obvious one.

| graph | nodes | py side is | the four ops, PER GRAPH |
|---|---|---|---|
| `lin` | 46 | `full_rewrite_to_sink(schedule_linear(matmul))` | LOAD 6, STORE 1 |
| `loop` | 25 | `hcq_fence(...)` -- tinygrad's OWN kernel, `runtime/support/hcq2.py:405-413` | BACKEDGE 1, LOAD 2, STORE 2 |
| `gate` | 14 | a gated STORE through the REAL `pm_linearize_cleanups` | ENDIF 1, IF 1, STORE 1 |

Corpus-wide those read `LOAD 8/2 graphs`, `STORE 4/3 graphs`, `BACKEDGE 1/1`, `ENDIF 1/1`;
§5 carries the full per-op table with node counts.

**THE COST, STATED WHERE IT IS AND NOT ONLY IN A REPORT.** The PY side stopped being
hand-written; the BEND side did not stop being hand-written, because it never was.
`tinybendygrad/schedule/__init__.bend` ports only `__init__.py:14-80` and DEFERS `:82-301`
("every rule is a `graph_rewrite` over the arena with a PYTHON ctx DICT"), so **the port
cannot build a schedule at all** and 85 new Bend nodes were written by hand for these three
graphs -- exactly as the other thirteen graphs' nodes were. What the widening bought is that
the py side now runs three pipelines the corpus had never run, and three of tinygrad's own
kernel bodies, so a disagreement is against something upstream built rather than against
something this harness invented.

**`ENDIF` IS REACHED, AND THE ROUTE IS NARROWER THAN THE OP.** `Ops.ENDIF` is constructed at
exactly ONE site in this tree -- `tinygrad/codegen/__init__.py:403`, inside
`pm_linearize_cleanups` -- and it fires only on a STORE with THREE srcs whose third is a
bool. A gated STORE is `UOp.store(val, gate)` (`ops.py:613-616`), which is how the tree's own
renderers spell one (`renderer/wgsl.py:20`, `codegen/late/gater.py:16,:22`).

**AND THE SCHEDULER NEVER MINTS ONE.** MEASURED over **NINE** scheduled programs
(`.agents/slop/graphcmp-p14d.py` Q1: matmul / assign / shrink / pad / pad+shrink / sum /
expand+slice / assign-into-view / 3d-slice): **0 gated STOREs in 9 programs.** The closest
miss is `shrink`, which leaves two GATED **LOAD**s (`LOAD(3src)`) -- the gater
(`codegen/late/gater.py`) fires on the READ side, and `to_program` then REFUSES the result
("memory coalescing does not support gated loads/stores"). So the honest claim is the
narrow one: **`ENDIF` is reachable, and only from a store body this harness spells; it is
NOT reachable from an eager program on this host**, with 9 programs as the denominator.

**`LOAD`/`STORE` NEED NO KERNEL EXECUTOR.** That was the open question in the brief and the
answer is a clean yes: `lin` is a real kernelized program with 6 LOADs and 1 STORE on the
py side and none of it has ever been run. `LOAD`/`STORE` are graph ops whose args are a
BUFFER and an INDEX; there is nothing to execute. What *does* need an executor is making the
`Buffer` VALUES agree, and §2 already says why they cannot (`Buffer` has no `slot`).

---

## 1. DEFECTS FOUND BY WIDENING, all in this file's own normal form

These are not limits; they are bugs that existed before 2026-10-04 and are now fixed.
They are listed because a coverage claim is only worth what the holes in it cost, and
these are what the holes cost. Items 1-11 are round one; **12-15 are round two and 17-21
are round three, and every one of 12-15 and 17-21 is the same shape: a field, a CHECK, or a
PRINTING that nothing had ever asked a question.**

1. **`cdepth` was OFF BY ONE against `Arena.depth`, and both sides read 0 so the two
   errors cancelled.** MEASURED over four fixtures, calling CPython for both numbers:

       axis_id    graphcmp (old)   Arena.depth   u.arg
       0           1                 0             (AxisType.WEAK, 0)
       (0,)        2                 1             (AxisType.WEAK, (0,))
       (0, 1)      2                 1             (AxisType.WEAK, (0, 1))
       ((0, 1),)   3                 2             (AxisType.WEAK, ((0, 1),))

   The old body walked `arg[1:]`, and `arg` is a 2-tuple, so it counted the tuple-ness of
   the ARG rather than the nesting of `axis_id`. It was invisible because NO graph emitted
   before 2026-10-04 contained a RANGE, so the py side returned 0 and the port returned 0
   and the field read equal. **A field that reads equal because both sides are wrong is
   worse than a field that is not compared.** The port's own header already had the right
   definition in prose (`ops.bend:1097-1101`) and this file did not match it.
2. **A RANGE's axis-id tail was rendered by `str(tuple)` INSIDE a `u32` atom** --
   `u((0,1))` is the six characters `i(0, 1)`, which is Python's repr doing the work
   inside a structural field, and a shape the port cannot produce for any ids at all. Now
   `flat(axis_id)` + `depth`, which is the pair the port actually stores.
3. **`--plant-side` was accepted and never read.** The same defect class as the `--graph`
   default this file was already measured to have: a flag that reaches nothing. Removed,
   not documented -- planting the bend side would mean six DAG rewrites in Bend against a
   graph the port builds node for node, which is a second implementation of the tree.
4. **`--bend-probe` did not reach the `emit` path.** It was read once and handed only to
   `diff`/`control`/`cross`, so `emit --side bend --bend-probe <a file that prints nothing>`
   ran the REAL probe and answered with 18 rows. MEASURED both ways: the guard now fires
   (`D10`, rc=1).
5. **`unchunks` REQUIRED a space between chunks, which made whitespace structural** --
   the one thing the `<bytecount>:<bytes>` wire exists to avoid. Nothing caught it because
   every field the eight-field wire carried was an ATOM text and no atom contains a space.
   The DEBUG rows broke it: a site prints `memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2
   bufs`, and the reader walked off the end of the first chunk and REFUSED the line, which
   surfaced as "0 trace rows" -- a reader returning fewer rows than the emitter wrote,
   reported as a COUNT. The counts are authoritative; the separator is now optional, and
   `selfcheck` has three rows for it.
6. **`y` (a bytes arg) compared the LENGTH only**, on the stated reason that "the port
   cannot fill it". That reason was true when written and is FALSE now: MEASURED,
   `ABlob{bs: List<&2, U32>}` (ops.bend:1062) holds the bytes and `eq_arg.ABlob` (:1801)
   compares them element-wise. The cost was measurable -- `--plant bytes` hangs `b"aaaa"`
   and `b"bbbb"` off the matmul and the old column printed `arg=y4` for BOTH. Now:
   `y n(i97,i97,i97,i97)` against `y n(i98,i98,i98,i98)`.
7. **Rung 2 could not pair a node that differed only in `depth`**, so `range` against
   `rangeflat` was reported as two separate "ONLY ON THE ... SIDE" blocks and the reader
   had to diff two lists BY EYE to learn the difference was `depth`. Rung 2's key now
   erases the depth slot (`erase_depth`) as well as the dtype spell.
8. **Rung 3 printed no cross-reference**, which is limit 7's other half. There is now a
   rung 3.5: leftovers with the SAME OP on both sides and no ambiguity are diffed field by
   field, so the report names the field. Nothing is summarised away -- both nodes are still
   printed in full.
9. **`--equiv` canonicalised only the node it was looking at**, so a NON-commutative
   parent of a commutative child still disagreed: MEASURED, the MUL paired and then
   PERMUTE#17 and REDUCE#18 did not. The canonical form must be canonical all the way down.
10. **The shared-core pairing used `zip`, which TRUNCATES**, so two sides with the same
     set of cores and a different MULTIPLICITY would lose the extra copies silently. Now
     counted and printed as `zip-truncated=` on every report; `0` on every run in
     `runs/graphcmp/D`.
11. **The verdict line carried no denominator.** `AGREE` on 2 nodes and `AGREE` on 19 are
     different claims. Every report now prints `graphs= nodes= fields= field-records=
     shared-cores= commutative-ops= ops-reached= symbolic-dims=` on the line above the
     verdict.

---

## 2. WHAT THE DIFFER DOES NOT COMPARE

**Node identity (`id`, R1) -- never.** The two arenas number differently: CPython interns
in ucache-hit order, `ops.bend` numbers by construction order. A differ keyed on `id`
compares nothing. `id` is printed for the reader and is not in the equality decision.

**Construction order and node order.** Nothing compares which node was built first, only the
`src` order inside each node. Two arenas that build the same DAG in opposite orders
agree. (Round two raised the fan-in to six and it did not change this: the `commute`
census shows `RESHAPE` at 2 nodes with 6 parents each on both sides.)

**A symbolic dimension's IDENTITY, in the `shape` column only -- RESOLVED, see §3.**

**A float CONST's structure.** `konst` renders a float as `f` + `repr(x)`, so for a float
CONST the normal form IS a string comparison. That is the ONE place a `repr` reaches the
equality decision and it is deliberate: a Python float has no structure to compare, so
there is nothing structural to lose. MEASURED: **still 0 of the 189 nodes** across 16
graphs has a float CONST, so the choice remains untested rather than measured.

**A realized buffer's device object (`z`) -- PRESENCE only.** `Buffer` has no `slot`
(MEASURED) and the port's is a P6 allocator slot with no runtime behind it. Size, dtype,
device and offset are already `ParamArg` fields 2/3/8 and ARE compared. Live on `buffer`
(`z=1/1`) and, since round three, on `gate`'s BUFFER -- though `gate`'s BUFFER carries no
device `Buffer` upstream either, so the live count is unchanged at `z=1`.

**A bytes CONST -- a PORT gap, not a normal-form loss.** Upstream's `PyConst` includes
`bytes` (`ops.py:122`); the port's `Const` is `CBool|CInt|CFloat|CInvalid`
(`ops.bend:808-811`) and `graphcmp.bend`'s `konst` has no bytes arm, so there is no port
spelling at all. The `y` residual is now exactly this and nothing else.

**A UOp nested in an arg (`u`) -- identity NOT compared.** MEASURED: `PYLITERAL`'s nested
UOp is in neither `src` nor `toposort`, so it has no arena index here. Reachable only via
`--plant pyuop`. STILL 0 of 16 graphs.

**Applied options (`q`) -- a COUNT, and since round three a MEASURED DISAGREEMENT rather
than a silent equality.** `ops.bend:978` types `applied_opts`/`opts_to_apply` as
`List<U32>` and upstream's elements are `Opt` dataclasses. `--graph lin` is the first graph
in the corpus with a non-empty `applied_opts` (the scheduler applied a `SPLIT`), so the
`q`-count design now produces what it was designed to produce: py
`kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0)` against the port's
`kI(sr_4_5_3,n(q),N,i0)`, on **1 node of 46**, and the verdict is DISAGREE. The `E` ledger
marker (an `OptOps` enum member) is live for the first time.

**THREE of the eight ledger markers are live on NO graph**: `u`, `X!` and `BAD`. (`estimates`
is a ninth line in every report and is NAMED rather than counted, because NEITHER side
carries it -- see the paragraph below.) `y`, `z`, `E`, `q` and `?` are all live. MEASURED on
every run and printed: `runs/graphcmp/D/D0-coverage-census.txt`. `?` cannot be produced by the
py side at all (it is the port's "the fold produced no `Derived`"); the other two are
reachable only through plants, which is what the plants are for. **`E` and `q` became live in
round three** (`lin`) and **`?` became live outside `sym`** (`loop`), which is why the count
went 3 -> 5.

**`KernelInfo.estimates` -- NEITHER SIDE CARRIES IT.** Dropped by the port (P5,
`tinygrad.renderer`) and `None` for every kernel the port can build, so the count would be
0 by construction and is named rather than printed as a zero.

**`ParamArg.slot = -1` -- A PORT GAP, found by widening, NOT FIXED.** MEASURED, calling
CPython: `UOp.variable(name, lo, hi)` hard-codes `slot=-1` (`ops.py:1015-1018`) and the
port's `ParamArg.slot` is a `U32` (`ops.bend:871`), so `-1` has **no port spelling at
all**. The tree has TWO conflicting sentinels for it and they disagree:

| position | what it says |
|---|---|
| `schedule/__init__.bend:1100-1103` | writes slot `0`, and says "The slot is `None` in Python's `-1`; nothing in this file reads a slot, so it is 0 here" |
| `uop/ops.bend:3566-3573` | calls any slot but 0/1 "the free Variable" sentinel, and uses `4294967295` for its own absent-`ParamArg` case |

So the graph spells the slot as `0` (the one a committed port fixture already writes) and
the AMBIGUITY is reported here rather than reconciled. MEASURED that the choice does not
change the subject: the thirteen `ParamArg` fields differ in EXACTLY ONE between
`UOp.variable`'s arg and the spelled one, the RESHAPE's dim-0 **is** the PARAM object
either way, and the rendered shape text is `(U,l0:4)` either way. **Choosing the sentinel is
an owner decision about `ops.bend`, not a harness decision, and `ops.bend` is under single
ownership this round.** Reported, not fixed.

**A CALL's dtype -- A PORT GAP, new in round three, and it is the cause of `loop`'s single
disagreement.** `dtype_from_uop` reads `Ops.CALL: return src[0].dtype` (`ops.py:130-131`,
"a call has the dtype of its body, void for opaque bodies"). The port reads the dtype off
the ARG instead -- `call_dt` is `case O.ACall{ci}: O.CallInfo.dtype(ci)`
(`uop/fold.bend:1067-1070`) against a comment quoting an OLDER upstream line, "`return
arg.dtype if isinstance(arg, CallInfo) else dtypes.void`". CPython's `CallInfo` has **no
dtype attribute at all** (MEASURED: `repr` is `CallInfo(None, 'hcq_fence', False, False)`
-- four attributes, `grad_fxn`/`name`/`precompile`/`precompile_backward`). So the port's
CALL dtype is decided by a field upstream does not consult and does not have, and on
`--graph loop` it reads `?` where CPython reads `void`/`R` on **1 node of 25**. Two
consequences: the `?` marker is live OUTSIDE `sym` for the first time (`?=0/2` on `loop`),
and the differ now names a real port divergence instead of a documentation drift.
**`fold.bend` and `ops.bend` are not this unit's files.** Reported, not fixed.

---

## 3. THE SYMBOLIC-DIM LIMIT: RESOLVED, IN THREE HALVES, ALL THREE MEASURED

The old text was: *"A symbolic dimension's identity. A dim is `int|UOp` (`ops.py:1925`) and
a symbolic one renders `U` -- so two DIFFERENT symbolic dims are indistinguishable.
MEASURED: 0 of the 63 nodes across 9 graphs has a symbolic dim, so this is an untested
hole and not a measured one."* That was true and it was a sentence nothing recomputed.
What follows is what the claim turned into once it had a denominator.

**(a) THE DIFFER DOES separate two different symbolic dims. MEASURED, `--graph sym`.**
The graph is `UOp.group(RESHAPE(a, STACK(n, CONST 4)), RESHAPE(a, STACK(m, CONST 4)))` with
`n = _variable("n")` and `m = _variable("m")`: 12 nodes, and the two RESHAPEs' `shape`
columns are **IDENTICAL**, `(U,l0:4)` and `(U,l0:4)`. So the shape column cannot separate
them -- that half of the limit stands, exactly as stated. But the differ separates them at
rung 1, through two independent fields:

* `arg`, in `ParamArg`'s **sixth** field (`name`, `ops.py:32`) --
  `P(i0,Dweakint,N,r(l0:1,l0:100),i1,sn,SALU,N,b0,N,N,b0,N)` against the same text with
  `sm`. The PARAMs' cores therefore differ, and so does every consumer's `src`.
* the plant `sym1` is the controlled experiment: it replaces both PARAMs with the SAME
  variable, the ucache collapses PARAM/STACK/RESHAPE #2 into #1, **12 nodes become 9**, and
  the GROUP's `src` becomes `n(i8,i8)` against `n(i8,i11)`. CONFLATION 4 in `conf` asserts
  that the differ names `src` (`runs/graphcmp/D/D7-conf.txt`, 4 of 4). **CONFLATION 4, and
  not `D5-plant-sym1.txt`:** a plant edits the py side only -- planting the bend side would
  mean six DAG rewrites in Bend, which is why `--plant-side` was removed in the first place --
  so the `D5` file carries the plant's structural effect and `sym`'s `?` disagreements (when
  it had any) together, and the rung-2 pair it prints is the latter. The py-vs-py comparison
  is the one where the cause is attributable.

**So the first half of the honest statement is: `U` is a hole in the SHAPE COLUMN, not in the
differ's identity.** A symbolic dim's identity is carried by its PARAM's `arg` and by the
`src` edges above it, and both are compared. Every report prints
`# SYMBOLIC DIMS: py=2/12 bend=2/12 nodes carry a 'U' dim; ids py=['8','11'] bend=['8','11']`
so the denominator is recomputed per run instead of living in this paragraph.

**(b) THE PORT COULD NOT BUILD A SYMBOLIC DIM AT ALL -- AND THAT IS NOW RESOLVED, BY
ANOTHER UNIT, MEASURED BY THIS HARNESS.** The old text here read: `uop/fold.bend`'s
`marg.of` answers `None{}` -- upstream's `(ssimplify(self),)` arm, the `ssimplify` wall --
for any STACK element that is not a CONST (`marg.step`'s `case None{}` cleared the `ok`
flag), so both `dtype` and `shape` came out `?` and `sym` DISAGREED on 3 of 12 nodes. That
was MEASURED, and it was a PORT LIMIT rather than a harness one, and the port's own ledger
recorded it: `fold.bend` said "`O.SU` is a shape dim for a SYMBOLIC size, and **nothing in
this tree can mint one** ... `rg 'SInt\.uop'` finds the constructor and NO caller".

**MEASURED 2026-10-04, LATE IN THE DAY: THAT LIMIT IS GONE.** `uop/fold.bend`'s
`sym_dim.of` now has an `AParam` arm -- `case O.AParam{pa}: sym_dim.pa(pa, i)`
(`fold.bend:1296`) -- which is the symbolic-dim-as-a-PARAM case the `ssimplify` wall was
refusing, and the consequence is visible in this harness's own output:

    diff --graph sym  ->  VERDICT: AGREE     12 of 12 nodes, 72 field-records
    # RESIDUALS IN THIS RUN: none -- every ledger entry is 0 on both sides.
    # SYMBOLIC DIMS: py=2/12 bend=2/12 nodes carry a 'U' dim; ids py=['8','11'] bend=['8','11']

So: **`sym` is AGREE**, `?` is no longer produced by it, and the port builds a symbolic dim.
**I DID NOT FIX THIS AND I DID NOT CAUSE IT** -- `fold.bend` belongs to the `fold` unit, and
what this unit contributed is the fixture and the denominator that made the closure visible
and checkable. That is the whole division of labour the harness was built for, and it is
worth recording as a result rather than as a footnote.

**(c) WHAT HAD TO CHANGE BECAUSE OF (b), and it is the part that is easy to get wrong.**
Three things in this file and its neighbours were pinned to the OLD limit, and all three had
to move **in the same direction**, because a limits file left claiming a resolved limit is
worse than one that never had it:

| what | was | is | why the old value had to go |
|---|---|---|---|
| `selfcheck`'s `?` row | `?=6` on `sym` | `?=0` on `sym` AND `?=2` on `loop` | the `?=6` assertion was a REGRESSION ROW for a bug that no longer exists, so it made a FIX look like a break |
| `graphcmp-run.sh`'s `$WANT` | `sym:DISAGREE` | `sym:AGREE` | the verdict assertion is what turns "a reader has to notice" into "a moved file" |
| `graphcmp-repro.sh`'s health gate | `graphs-agree=13` | `graphs-agree=14` | MEASURED: the gate reported "not healthy" for a run that was entirely CORRECT and sat retrying it |

**The two-column `?` claim did NOT die with `sym`, and keeping it alive needed a new
fixture.** The claim being tested is "`?` takes `dtype` AND `shape` together", and `sym`
was the only graph that produced it. `--graph loop`'s CALL is now the carrier (`?=2`, one
node x two columns) because its wall has a DIFFERENT and still-open cause -- `fold.bend`'s
`call_dt` reads `CallInfo.dtype` and CPython's `CallInfo` has no dtype (see §2). So the
assertion moved to a node that still has a wall, which is the only way it can keep testing
anything. **MEASURED that both new rows can fire**: before the fix, `sym` answered `?=6` and
`selfcheck` printed `# SELFCHECK: FAIL` naming the closure; that is how the move was caught
rather than assumed.

**TWO GRAPH DISAGREE NOW, AND BOTH ARE PORT GAPS WITH A NODE COUNT, NOT HARNESS LIMITS.**
`lin` on its SINK's `applied_opts` (1 node of 46) and `loop` on its CALL's dtype (1 node of
25). `runs/graphcmp/D/D1-verdicts.txt` asserts the whole set every run, so a moved verdict
is a moved file rather than something a reader has to notice.

---

## 4. WHAT THE DIFFER CANNOT DO, structurally

**Two nodes with the same core and a different multiplicity.** `zip` truncates; the count
is printed (`zip-truncated=`) so it is not silent, but a multiplicity difference is not
REPORTED as one. MEASURED `0` on every run over 189 nodes.

**A rung-2 pairing with no mutual best is DROPPED to rung 3.** Both nodes are printed in
full, so nothing is hidden, but the difference is reported as "one-sided" rather than named
as a field. That is a deliberate refusal to claim (five RESHAPEs of the matmul share one
`loose` key and pairing them all produced a report full of crosswise nonsense) and it is a
real cost: some genuine field differences arrive as unpaired nodes. Round two made this
worse on purpose and it is worth stating: `--graph commute --plant srcswap` reorders an
ADD, the ADD's core moves, and so does the GROUP's -- **two** rung-2 pairs instead of the
one the matmul produced, because a six-src GROUP has six children whose cores all move.
The differ names `src` on both, so nothing is lost, but the report is longer for the same
one swap.

**Rung 3.5 pairs only when the op is UNIQUE on both sides.** An op appearing twice on each
side gets no cross-reference. `field-records` and the rung counts are still printed.

**The device is pinned.** `--dev CPU` by default, because the port's fixture pins the
ALLOC device at arena tag 0. A different device is exit 2 ("NOT WELL-POSED, and this is
NOT a verdict"), never a verdict.

**`dbg` is a PORT-vs-PORT comparison across levels, not port-vs-CPython.** MEASURED:
CPython's own `DEBUG >= 1` memory line (`memory.py:59-60`) fires on **0 of the 8 tensor
fixtures** in `runs/graphcmp/D/D8b-cpython-dbg1-reachability.txt` -- those 8 are the dbg
oracle's own Tensor programs, NOT graphcmp graphs, so the 8 is a statement about 8
fixtures and not about the corpus. There is therefore no CPython lane for the trace text
on this host. The seven sites are reached through the port's own `*_dbg*` defs with the
level threaded in, so what `dbg` proves is that a LEVEL CHANGE MOVES A NAMED SET OF ROWS
-- not that any row's text is right.

**`Graph` construction is not order-independent on the bend side.** Every graph is built
into its own `O.Arena.empty()`, and `UOp.toposort` fixes the output order, so the two sides'
ids line up -- MEASURED, 14 of 16 graphs' canonical files are byte-identical. The other two
are `lin` and `loop`, and each differs on exactly the node named in §0 and §2.

---

## 5. COVERAGE, WITH THE DENOMINATOR THAT PRODUCED IT

**34 of 77 ops. That is the coverage number, not "sixteen graphs".** MEASURED by
`list(Ops)` on this tree, not by reading the enum, and reprinted by `graphcmp-oracle.py` on
every run:

  REACHED (34), with the corpus-wide NODE counts and how many graphs reach each:
    ADD 10/4   AFTER 3/1    ALLOC 10/7   AND 1/1     BACKEDGE 1/1   BARRIER 1/1
    BINARY 1/1 BUFFER 2/2    CALL 1/1     CAST 8/3     CMPLT 2/2     CMPNE 1/1
    CONST 36/16 END 3/2      ENDIF 1/1    GROUP 3/3    IF 1/1        INDEX 14/4
    LINEAR 1/1  LOAD 8/2     MAX 1/1      MUL 8/4      NOOP 1/1      OR 1/1
    PARAM 11/5 PERMUTE 5/3   RANGE 7/6    REDUCE 3/3   RESHAPE 17/8  SINK 5/5
    SPECIAL 1/1 STACK 16/8   STORE 4/3    XOR 1/1
  NOT REACHED (43 of 77): REWRITE_ERROR PROGRAM SOURCE GETADDR SHRINK WMMA BITCAST EXP2
    LOG2 SIN SQRT RECIPROCAL NEG TRUNC SHL SHR CDIV CMOD CMPEQ THREEFRY SUB FDIV POW
    FLOORDIV FLOORMOD WHERE MULACC CUSTOM CUSTOMI INS CONTIGUOUS_BACKWARD DETACH STAGE
    COPY MSELECT MSTACK CUSTOM_FUNCTION EXPAND PAD FLIP UNSHARD ALLREDUCE PYLITERAL
    (CROSSED THROUGH IN ROUND THREE, and these are the ten: NOOP, CALL, LINEAR, AFTER,
     END, IF, ENDIF, BACKEDGE, LOAD, STORE -- every one of them from `lin`/`loop`/`gate`)

  **A node count of 1 is the weakest coverage there is and the table says so.** Fourteen of
  the 34 are at 1 node in 1 graph; `ENDIF`, `IF`, `BACKEDGE`, `CALL`, `LINEAR` and `NOOP`
  are all at exactly 1 node. `AGREE` on one node is not a claim about the op, it is a claim
  about one node -- which is why the denominator is a column and not a footnote. **`gate` is
  AGREE at 14 nodes and 12 ops, which is the strongest single fixture in the corpus and is
  still 1 node per control-flow op.**

**SEVEN of the eight COMMUTATIVE ops.** `--equiv` is measured on `ADD AND CMPNE MAX MUL OR
XOR` (all of `GroupOp.Commutative` except `CMPEQ`). `CMPEQ` is **not reachable from an eager
graph at all**, and that is a measured limit rather than a missing fixture: `UOp` has no
`cmpeq`/`cmpne` method (`[a for a in dir(UOp) if 'cmp' in a.lower()]` is `[]`, because
`UOp.__eq__` is overridden for the ucache and answers a Python `bool`), and
`(Tensor.empty(4,3) == Tensor.empty(4,3)).uop` emits `CMPNE CONST CMPNE`, not a `CMPEQ`.
**ROUND THREE DID NOT CHANGE THIS, and that is worth saying:** three real kernels later,
`CMPEQ` is still 0. Reaching it needs a pattern-matched rewrite, which is a different kind
of fixture from either an eager graph or a scheduled one.

**`ENDIF`/`BACKEDGE`/`LOAD`/`STORE` ARE NOW REACHED -- see §0.** What is still unreached
from the §4 set is `SHRINK`, which the scheduled corpus reaches easily (the `shrink`
program's full sink has `SHRINK=1` and the `pad` program's has `SHRINK=8`) and which round
three's `lin` happens not to. It is the nearest unclosed gap and it is a graph, not a wall.

---

## 6. THE SIX DEFECTS ROUND THREE FOUND, all in this file's own normal form

Same shape as §1: **a field, a CHECK, or a PRINTING that nothing had asked a question.**
17-20 are the ones that matter, and 17 and 20 are the ones that would have kept lying.

16. **THIS FILE ASSERTED, IN THREE PLACES, THAT NO NODE IN THE CORPUS HAD MORE THAN ONE
    PARENT. IT IS FALSE, AND THE CENSUS THAT CAUGHT IT IS NOW ON EVERY REPORT.** The
    sentences were in `graphcmp.py`'s header, in `g_group`'s docstring, and here; they were
    written as justification for building `--graph group` and they were never measured.
    MEASURED, per graph (`# MULTI-PARENT NODES (op#id in-edges/parents)`, printed by `diff`
    on both sides):

        matmul   CONST#2 2e/2p  CONST#3 4e/4p  CONST#6 2e/2p  CONST#10 2e/2p
        binblob  the same four, because it hangs the BINARY off the matmul
        commute  STACK#4 2e/2p  RESHAPE#5 6e/6p  RESHAPE#7 6e/6p
        group    RESHAPE#5 4e/2p
        sym      CONST#2 3e/3p  RESHAPE#5 2e/2p
        gate     ELEVEN multi-parent nodes -- RANGE#5 5e/5p, INDEX#6 3e/3p -- because the
                 root is a `LINEAR` whose src list names EVERY LINE of the kernel, so the
                 program order itself is multi-parent
        lin      RANGE#4 4e/4p  RANGE#8 5e/5p  CAST#6 3e/3p  PARAM#11 3e/3p  MUL#14 3e/3p
                 PARAM#17 3e/3p
        reduce, buffer, sink, range, rangeflat, cast, special, indexed, loop   ZERO or few
        loop     PARAM#1 2e/2p  LOAD#5 2e/2p  CONST#3 3e/3p  RANGE#7 2e/2p  LOAD#10 2e/2p
                 CONST#14 2e/2p  AFTER#8 (not listed: single parent)  ADD#18 2e/2p

    So the differ HAD been placing shared nodes by up to four parents all along, and every
    one of them was a shape `CONST` whose `core` is a leaf. The two properties the round
    actually added are narrower and are what `--graph group` is for: **a shared node with a
    real subtree under it** (`group`'s RESHAPE, `commute`'s two at six parents each) and
    **a repeated child index** (`src=n(i5,i5)`), which no earlier graph had.

    The lesson is the one this section keeps earning, in a new place: **a prose claim
    written to justify a fixture is a claim with no denominator, and it was wrong in the
    direction that flattered the fixture.** `multiparent` is now computed on every report
    and folded into the verdict's `DENOMINATOR` line, so the next version of the claim has
    to agree with a number that a reader can see move. Two COUNTS are printed rather than
    one -- in-edges and distinct parents -- because a node that names the same child twice
    in its own `src` inflates the edge count (`group`'s RESHAPE is 4 edges over 2 parents),
    and reporting only the edge count would have made the fixture look four-parented.

17. **A SINK WITH `arg=None` HAD NO SPELLING, AND THE EMITTER DIED ON IT.** A SINK's arg is
    `KernelInfo | None` and upstream **BUILDS** the `None` one: `hcq_fence` ends in a bare
    `.sink()` (`tinygrad/runtime/support/hcq2.py:412`) and so does `usb.py:236`'s helper.
    MEASURED: `emit --side py --graph loop` died with
    `AttributeError: 'NoneType' object has no attribute 'name'` at the `kI(...)` line, so a
    real in-tree kernel could not be diffed AT ALL -- and the corpus's thirteen graphs of
    silence about `arg=None` SINKs was a CRASH, not an agreement. It is the same shape as
    defect 13 (`BYTE-IDENTICAL` over two 0-byte files): **an emitter that dies is
    indistinguishable, in a report that only counts rows, from an emitter that has nothing
    to say.** The fix is ONE arm, and `N` is the right letter rather than a new one:
    `KernelInfo | None` is `Maybe<KernelInfo>`, the port's `AKernel`/`ANone` pair is the
    same distinction, and `mm`/`mum`/`nm`/`dm` already spell every other optional field with
    `N`. The port agrees: `--graph loop`'s SINK row is byte-identical.

18. **THE `tag` COLUMN COULD NOT BE READ AT ALL, AND NOTHING IN THE CORPUS HAD EVER ASKED.**
    `ctag` called `carg(t)` -- the OP-DISPATCHING entry point, which takes `(op, x)` -- with
    ONE argument, so it raised `TypeError: carg() missing 1 required positional argument:
    'x'` on the first non-None tag. Every one of the thirteen earlier graphs has `tag is
    None` on every node, so R6 had never been evaluated: it was a FIELD THAT COULD NOT BE
    READ, and the eight-field row still printed `N` on both sides, so it agreed by never
    being computed. `_carg` is the value grammar `ctag` wanted (a tag is
    `UOp.tagstr`'s `bool | str | int | tuple[UOp,...] | None`, `ops.py:277`, and has no op to
    dispatch on).

    **IT IS NOT COSMETIC, AND THE GRAPH THAT FOUND IT SAYS WHY.** `lin` is the first corpus
    graph with a tag at all, because a tag is what a renderer attaches to an INSTRUCTION and
    `full_rewrite_to_sink` is the first corpus graph to BE a kernelized program: the SINK's
    row reads `tag=i1` on both sides. So the field and the fixture arrived together --
    without a linearized program there was nothing to tag, and without a tag the field was
    unreadable, and **neither fact is visible from the other**.

19. **A LINEARIZED KERNEL'S NAME IS ANSI-COLOURED TEXT, AND IT REACHED A STRUCTURAL FIELD.**
    MEASURED: the SINK's `arg` began
    `kI(sr\x1b[90m_\x1b[0m\x1b[31m4\x1b[0m\x1b[31m5\x1b[0m\x1b[33m3\x1b[0m, ...)` --
    **18 bytes of `\x1b[..m` inside a chunk** whose whole job is to be compared byte for
    byte. `full_rewrite_to_sink` names its SINK through `helpers.colored`
    (`tinygrad/helpers.py:41-43`); `NO_COLOR` is a `ContextVar` defaulting to 0
    (`helpers.py:240`) and is **NOT an environment variable**, so no `NO_COLOR=1` on the
    command line reaches it -- the only spelling is `Context(NO_COLOR=1)`. The escape bytes
    are ASCII (`0x1b`), so `unchunks`' non-ASCII guard did not fire.

    The differ now wraps EVERY command in `Context(NO_COLOR=1)` rather than one graph: it is
    a property of the emitter and not of a fixture, and a fixture that needed it would be a
    fixture whose reproducibility depends on a flag the reader has to know about. tinygrad
    ships its own answer (`helpers.ansistrip`) and the differ deliberately does **NOT** use
    it: stripping would silently NORMALISE the field instead of refusing a graph whose name
    is not plain text, whereas `Context(NO_COLOR=1)` makes the name plain at the SOURCE.

20. **THE TWO-RUN BYTE CHECK WAS WRONG, AND WHEN IT WAS FIXED IT IMMEDIATELY FOUND A REAL
    NONDETERMINISM.** `graphcmp-run.sh` step 15 claimed, in a comment, that two consecutive
    clean runs leave every file under `$D` byte-identical, and backed it with
    `find | md5 -q`. **That command is not a digest**: macOS `md5 -q` takes exactly ONE file
    and prints nothing given several. The claim survived because the file it produced looked
    like a digest. The corrected check -- `sha256` over non-blank lines, one file per
    `printf` -- found **one** file out of 158 that moved:
    `D0-coverage-census.txt`, which prints
    `dict(all_res)`, a `Counter` fed by a SET UNION, whose iteration order over STRINGS
    follows the per-process string hash. MEASURED: three consecutive oracle runs gave
    `{'y': 1, 'z': 1, 'q': 1, 'E': 1, '?': 2}`, `{'y': 1, 'z': 1, 'E': 1, 'q': 1, '?': 2}`,
    and the first again. Every other set in that file is already `sorted(...)`, which is why
    157 of 158 files were stable and that one was not.

    It is the exact class the brief names: **a COUNT that is right and an ORDER that is not,
    printed where a reader reads it as one line of fact** -- and it was invisible to
    `selfcheck`, to `control`, to every verdict and to every `DENOMINATOR` line in the
    directory. Fixed by `sorted(all_res.items())`, and the command is now
    `sh .agents/slop/graphcmp-repro.sh`.

    **AND THE CORRECTED CHECK NEEDS A HEALTH GATE, which is itself a measurement.** A
    concurrent edit to `tinybendygrad/uop/ops.bend` landed *part way through* a run, so the
    first twelve graphs wrote real reports and the last four wrote "0 rows after 5
    attempts". Both halves are files; both halves hash; the diff is a wall of unrelated
    changes. The `emit_bend` 0-row guard did the right thing throughout (a FAILURE, never a
    verdict, and `D2-cmp-*` said `NOT COMPARED` rather than `BYTE-IDENTICAL`) but a
    FAILURE is still not a reproducibility measurement. So `graphcmp-repro.sh` waits for
    `graphcmp.bend --check-only` to read `ALL PROOFS CHECK` **and** then accepts a run only
    if its own summary says sixteen graphs, thirteen AGREE, selfcheck OK and `census-rc=0`.
    **FINAL: 158 of 158 files identical across two clean runs.**

21. **THE COVERAGE CENSUS COUNTED A DATACLASS FIELD NAME AS AN ATOM LETTER.** `atoms()`
    counted `o` from `Opt(op=EOptOps.SPLIT,...)` and `a` from `axis`, so the census printed
    `an unmapped value: o` -- warning about an UNMAPPED ATOM over a string the differ had
    just rendered correctly. Found only because `lin` is the corpus's first `Opt`. The `=`
    is at the END of the token (`op=`, not `=op`), so the test must run AFTER the token is
    skipped: **MEASURED, the first fix tested `arg[i+1] != "="` at the token's first
    character and changed nothing**, because `arg[i+1]` is `p`. The three rows asserting the
    fix are in the census itself (`# ORACLE SELFCHECK:`) and MEASURED TO FIRE -- the first
    version of the assertion printed
    `atoms() counts a dataclass FIELD NAME as an atom letter: ['E','O','X','a','i','o']` and
    exited 1. An assertion that cannot fail is not an assertion.

**ONE MORE FINDING THAT IS NOT A DEFECT IN THIS FILE, and is the most useful thing round
three produced.** `lin`'s SINK DISAGREEs on `applied_opts` and `loop`'s CALL DISAGREEs on
`dtype`. Both were already documented as residual PORT gaps in §2, written down when they
were hypothetical. Round three made them **measured disagreements with a node count** --
1 of 46 and 1 of 25 -- and that is strictly better than the alternative this file keeps
warning about: **a field that reads equal because both sides are wrong.** The two graphs
now carry their disagreement in the verdict line instead of in a comment.

---

## 7. THE FOUR CONFLATIONS, and the honest answer on the third

1. **`arg` differs structurally, `repr(arg)` is identical** -- CAN DISTINGUISH.
   MEASURED on `plant_srcswap`: `repr(arg)` is `None` on both sides and the normal form's
   arg text is `N` on both sides, and the differ names `src` on the node
   (`MUL py#16 vs srcswap#16`). A differ keying on `repr` would have reported nothing here.
2. **The same `arg` at a different `depth`** -- **NOT REPRESENTABLE, and that is the
   finding.** The depth is encoded TWICE on purpose: its own field AND as the first slot of
   the RANGE arg (`rg(i<n>,XWEAK,...)`, `graphcmp.bend`'s `argstr`), so a same-arg /
   different-depth pair does not exist in the normal form and a disagreement in either place
   is a disagreement. What IS demonstrated is the weaker and still useful thing: the differ
   NAMES a depth difference. `range` against `rangeflat` differ in `depth` (`i0`/`i1`) and
   in `arg`, rung 3.5 prints both fields by name, and each graph separately agrees with the
   port -- so the difference is between two graphs, not a field the port always gets wrong.
3. **A reordered but equivalent graph** -- CAN DISTINGUISH, but ONLY AFTER ADDING THE
   MODE. `--equiv` did not exist before the first session. On TWO fixtures now
   (`--plant srcswap` on `matmul`, and on `commute`): `diff` prints `DISAGREE` naming
   `src`, and `diff --equiv` prints `AGREE` on 18 nodes / 108 field-records and on 14
   nodes / 84 field-records respectively. The naive answer -- keying on `repr` -- gives
   AGREE for BOTH, which is right for equivalence and wrong for identity, so it conflates
   the two. The commutative set is read from CPython's `GroupOp.Commutative` rather than
   typed, and MEASURED to agree with the port's `GroupOp.commutative` on all eight ops.
4. **Two DIFFERENT symbolic dims against ONE** -- CAN DISTINGUISH, and the shape column
   alone cannot. See §3(a): the two `sym` RESHAPEs' `shape` texts are `(U,l0:4)` and
   `(U,l0:4)`, byte-identical, so a differ that keyed on `shape` would report nothing; the
   differ pairs them at rung 1 on `arg` (ParamArg's `name`) and `src`, and
   `--plant sym1` (12 nodes -> 9) is asserted to name `src`.

---

## 8. WHAT A CLEAN RUN DOES AND DOES NOT ESTABLISH

A clean run establishes: on this substrate, for these 16 graphs, the port's arena and
CPython's arena agree on op, dtype, shape, depth, tag, a structural arg and the ordered
child edges for **189 nodes -- 1134 field-records** -- on **13 of 16** graphs, modulo the
residuals printed above. The other three DISAGREE on 3 of 12, 1 of 46 and 1 of 25 nodes
respectively, and every one of those disagreements is a NAMED, MEASURED cause: the
`ssimplify` wall, the `applied_opts` count, and the `CallInfo.dtype` gap.

It does NOT establish: that the port builds correct graphs (only that they MATCH
CPython's), that the residual-bearing constructs are right, anything about the 43
unexercised ops, anything at a device other than CPU, that a symbolic dim can be built by
the port at all, that the port can build a SCHEDULE at all (§0: `schedule/__init__.bend`
DEFERS `__init__.py:82-301`), or anything about EXECUTING a kernel. `.agents/slop/e2e.sh`
is still the only end-to-end artefact in the project and it still proves one matmul.