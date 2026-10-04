# graphcmp -- WHAT IT DOES NOT COMPARE, and what it got wrong.

Every item here is MEASURED on this tree, and every one is printed by the tool rather than
living only in this file: the ledger rows are on every report, the denominators are on
every verdict, the ops census with per-op NODE counts is on every report, and `selfcheck`
asserts the ones that are assertions rather than counts. What this file adds is the
reasoning, and the items that CANNOT be printed.

Run: `E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`
(`E` is also the prefix in `runs/graphcmp/D/README-D.txt`.)
Regenerate everything: `sh .agents/slop/graphcmp-run.sh`

**THE TWO ROUNDS.** The first round built 9 graphs / 63 nodes / 13 of 77 ops and found
eleven defects in the differ's own normal form. The second round (this file's §6) added
four graphs -- `group`, `commute`, `indexed`, `sym` -- and found four more, of which two
were in a check that had been reporting `PASS` over nothing. Current state, MEASURED and
printed by `runs/graphcmp/D/D0-run-summary.txt` and `D0-coverage-census.txt`:

    graphs 13   AGREE 12 (sym DISAGREE on purpose)   nodes 104 per side
    ops 23 of 77   commutative ops 7 of 8   symbolic-dim nodes 2 of 104
    field-records 624 per side   byte-identical 12 of 13   stable pairs 3 of 3
    conflations 4 of 4   selfcheck OK

---

## 1. DEFECTS FOUND BY WIDENING, all in this file's own normal form

These are not limits; they are bugs that existed before 2026-10-04 and are now fixed.
They are listed because a coverage claim is only worth what the holes in it cost, and
these are what the holes cost. Items 1-11 are round one; **12-15 are round two and every
one of them is the same shape as an earlier one: a field or a CHECK that nothing had ever
asked a question.**

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

**Construction order and node order.** Nothing compares which node was built first, only
the `src` order inside each node. Two arenas that build the same DAG in opposite orders
agree. (Round two raised the fan-in to six and it did not change this: the `commute`
census shows `RESHAPE` at 2 nodes with 6 parents each on both sides.)

**A symbolic dimension's IDENTITY, in the `shape` column only -- RESOLVED, see §3.**

**A float CONST's structure.** `konst` renders a float as `f` + `repr(x)`, so for a float
CONST the normal form IS a string comparison. That is the ONE place a `repr` reaches the
equality decision and it is deliberate: a Python float has no structure to compare, so
there is nothing structural to lose. MEASURED: **still 0 of the 104 nodes** across 13
graphs has a float CONST, so the choice remains untested rather than measured.

**A realized buffer's device object (`z`) -- PRESENCE only.** `Buffer` has no `slot`
(MEASURED) and the port's is a P6 allocator slot with no runtime behind it. Size, dtype,
device and offset are already `ParamArg` fields 2/3/8 and ARE compared. Live on `buffer`
(`z=1/1`).

**A bytes CONST -- a PORT gap, not a normal-form loss.** Upstream's `PyConst` includes
`bytes` (`ops.py:122`); the port's `Const` is `CBool|CInt|CFloat|CInvalid`
(`ops.bend:808-811`) and `graphcmp.bend`'s `konst` has no bytes arm, so there is no port
spelling at all. The `y` residual is now exactly this and nothing else.

**A UOp nested in an arg (`u`) -- identity NOT compared.** MEASURED: `PYLITERAL`'s nested
UOp is in neither `src` nor `toposort`, so it has no arena index here. Reachable only via
`--plant pyuop`.

**Applied options (`q`) -- a COUNT.** `ops.bend:978` types `applied_opts`/`opts_to_apply`
as `List<U32>` and upstream's elements are `Opt` dataclasses. Reachable only via
`--plant opt`, where the port emits one `q` per option.

**Five of the eight ledger markers are live on NO graph**: `u`, `q`, `X!`, `BAD`, `E`.
`?` is now live (on `sym`) and `y`, `z` were already. MEASURED on every run and printed:
`runs/graphcmp/D/D0-coverage-census.txt`. `?` cannot be produced by the py side at all (it
is the port's "the fold produced no `Derived`"); the other four are reachable only through
plants, which is what the plants are for.

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
`UOp.variable`'s arg and the spelled one (`replace(variable.arg, slot=0) == spelled` is
`True`), the RESHAPE's dim-0 **is** the PARAM object either way (`r.shape[0] is param`,
`True` in both), and the rendered shape text is `(U,l0:4)` either way. **Choosing the
sentinel is an owner decision about `ops.bend`, not a harness decision, and `ops.bend` is
under single ownership this round.** Reported, not fixed.

---

## 3. THE SYMBOLIC-DIM LIMIT: RESOLVED, IN TWO HALVES, BOTH MEASURED

The old text was: *"A symbolic dimension's identity. A dim is `int|UOp` (`ops.py:1925`) and
a symbolic one renders `U` -- so two DIFFERENT symbolic dims are indistinguishable.
MEASURED: 0 of the 63 nodes across 9 graphs has a symbolic dim, so this is an untested
hole and not a measured one."* That was true and it was a sentence nothing recomputed.
Both halves are now measured, and they point in opposite directions.

**(a) THE DIFFER DOES separate two different symbolic dims. MEASURED, `--graph sym`.**
The graph is `UOp.group(RESHAPE(a, STACK(n, CONST 4)), RESHAPE(a, STACK(m, CONST 4)))` with
`n = _variable("n")` and `m = _variable("m")`: 12 nodes, and the two RESHAPEs' `shape`
columns are **IDENTICAL**, `(U,l0:4)` and `(U,l0:4)`. So the shape column cannot separate
them -- the limit stands, exactly as stated. But the differ separates them anyway, at rung
1, through two independent fields:

* `arg`, in `ParamArg`'s **sixth** field (`name`, `ops.py:32`) --
  `P(i0,Dweakint,N,r(l0:1,l0:100),i1,sn,SALU,N,b0,N,N,b0,N)` against the same text with
  `sm`. The PARAMs' cores therefore differ, and so does every consumer's `src`.
* the plant `sym1` is the controlled experiment: it replaces both PARAMs with the SAME
  variable, the ucache collapses PARAM/STACK/RESHAPE #2 into #1, **12 nodes become 9**, and
  the GROUP's `src` becomes `n(i8,i8)` against `n(i8,i11)`. CONFLATION 4 in `conf` asserts
  that the differ names `src` (`runs/graphcmp/D/D7-conf.txt`, 4 of 4). **CONFLATION 4, and
  not `D5-plant-sym1.txt`:** a plant edits the py side only -- planting the bend side would
  mean six DAG rewrites in Bend, which is why `--plant-side` was removed in the first place --
  so the `D5` file carries the plant's structural effect and `sym`'s pre-existing `?`
  disagreements together, and the rung-2 pair it prints is the latter. The py-vs-py
  comparison is the one where the cause is attributable.

**So the honest statement of the limit is: `U` is a hole in the SHAPE COLUMN, not in the
differ's identity.** A symbolic dim's identity is carried by its PARAM's `arg` and by the
`src` edges above it, and both are compared. Every report now prints
`# SYMBOLIC DIMS: py=2/12 bend=0/12 nodes carry a 'U' dim; ids py=['8','11'] bend=[]` so
the denominator is recomputed per run instead of living in this paragraph.

**(b) THE PORT CANNOT BUILD A SYMBOLIC DIM AT ALL, and that is now a REPORTED
DISAGREEMENT rather than an assertion.** MEASURED by reading `uop/fold.bend` and then by
running it: `marg.of` answers `None{}` -- upstream's `(ssimplify(self),)` arm, the
`ssimplify` wall -- for any STACK element that is not a CONST, because `marg.step`'s
`case None{}` clears the `ok` flag (`fold.bend:1229-1248`). That unsettles the RESHAPE's
whole `Derived`, so both `dtype` and `shape` come out `?`. Hence:

    diff --graph sym   ->   DISAGREE
      MISMATCH RESHAPE py#8  vs bend#8   dtype py=f32 bend=?
      MISMATCH RESHAPE py#8  vs bend#8   shape py=(U,l0:4) bend=?
      MISMATCH RESHAPE py#11 vs bend#11  dtype py=f32 bend=?
      MISMATCH RESHAPE py#11 vs bend#11  shape py=(U,l0:4) bend=?
      MISMATCH GROUP   py#12 vs bend#12  dtype py=void bend=?
      MISMATCH GROUP   py#12 vs bend#12  shape py=R bend=?

**6 field mismatches on 3 of 12 nodes, on cores that MATCH.** By this file's own measured
theorem (§4) a rung-1 field mismatch cannot mean "the graphs differ": it means the two
`_shape`/`dtype_from_uop` implementations disagree about the same node. The port's OWN
ledger already records the same wall -- `fold.bend:6180`: "`O.SU` is a shape dim for a
SYMBOLIC size, and **nothing in this tree can mint one** ... `rg 'SInt\.uop'` finds the
constructor and NO caller". `--graph sym` is that claim with a denominator on it. The port
gap is in `fold.bend`, which this unit does not own; reported, not fixed.

**`sym` IS THE ONE GRAPH IN THE CORPUS THAT DISAGREES, AND IT IS SUPPOSED TO.** 12 of 13
graphs are AGREE. `runs/graphcmp/D/D1-verdicts.txt` asserts the whole set every run, so a
moved verdict is a moved file rather than something a reader has to notice.

---

## 4. WHAT THE DIFFER CANNOT DO, structurally

**Two nodes with the same core and a different multiplicity.** `zip` truncates; the count
is printed (`zip-truncated=`) so it is not silent, but a multiplicity difference is not
REPORTED as one. MEASURED `0` on every run over 104 nodes.

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
ids line up -- MEASURED, 12 of 13 graphs' canonical files are byte-identical. The 13th is
`sym`, and it differs on exactly the 3 rows named in §3.

---

## 5. COVERAGE, WITH THE DENOMINATOR THAT PRODUCED IT

**23 of 77 ops. That is the coverage number, not "thirteen graphs".** MEASURED by
`list(Ops)` on this tree, not by reading the enum, and reprinted by
`graphcmp-oracle.py` on every run:

  REACHED (23), with the corpus-wide NODE counts and how many graphs reach each:
    ADD 2/2      ALLOC 10/7    AND 1/1      BARRIER 1/1   BINARY 1/1
    BUFFER 1/1   CAST 1/1      CMPNE 1/1    CONST 26/13   GROUP 3/3
    INDEX 1/1    MAX 1/1       MUL 3/3      OR 1/1       PARAM 3/2
    PERMUTE 5/3  RANGE 3/3     REDUCE 3/3   RESHAPE 17/8  SINK 2/2
    SPECIAL 1/1  STACK 16/8    XOR 1/1
  NOT REACHED (54): NOOP REWRITE_ERROR CALL PROGRAM LINEAR SOURCE AFTER GETADDR SHRINK
    LOAD STORE WMMA BITCAST EXP2 LOG2 SIN SQRT RECIPROCAL NEG TRUNC SHL SHR CDIV CMOD
    CMPLT CMPEQ THREEFRY SUB FDIV POW FLOORDIV FLOORMOD WHERE MULACC IF END ENDIF
    BACKEDGE CUSTOM CUSTOMI INS CONTIGUOUS_BACKWARD DETACH STAGE COPY MSELECT MSTACK
    CUSTOM_FUNCTION EXPAND PAD FLIP UNSHARD ALLREDUCE PYLITERAL

  **A node count of 1 is the weakest coverage there is and the table says so.** Eleven of
  the 23 are at 1 node in 1 graph; `BARRIER` and `INDEX` are at 1 node each. `AGREE` on one
  node is not a claim about the op, it is a claim about one node -- which is why the
  denominator is a column and not a footnote.

**SEVEN of the eight COMMUTATIVE ops, up from one.** `--equiv` used to be measured on MUL
alone; it is now measured on `ADD AND CMPNE MAX MUL OR XOR` (all of `GroupOp.Commutative`
except `CMPEQ`). `CMPEQ` is **not reachable from an eager graph at all**, and that is a
measured limit rather than a missing fixture: `UOp` has no `cmpeq`/`cmpne` method
(`[a for a in dir(UOp) if 'cmp' in a.lower()]` is `[]`, because `UOp.__eq__` is overridden
for the ucache and answers a Python `bool`), and `(Tensor.empty(4,3) ==
Tensor.empty(4,3)).uop` emits `CMPNE CONST CMPNE`, not a `CMPEQ`. Reaching it needs a
pattern-matched rewrite, which is a different kind of fixture and not a hand-built graph.

**`ENDIF`/`BACKEDGE`/`LOAD`/`STORE` are still unreached, and that is the real gap.** A
grouped graph is a DAG, not a linearized program: `LOAD`/`STORE` need a `STORE` body,
`ENDIF`/`BACKEDGE` need a loop, and none of the four is constructible from the eager
Tensor API in a handful of lines. `INDEX` and `BARRIER` were reachable by hand and are
now in; the remaining four are the ones a real `kernelize`+`rangeify` graph brings and
this corpus still does not.

---

## 6. THE FOUR DEFECTS ROUND TWO FOUND, all in this file's own normal form

Same shape as §1: **a field, or a CHECK, that nothing had asked a question.** 12 and 13
are the two that matter most, because 13 was reporting `PASS` over nothing.

12. **`ParamArg`'s FOURTH field had never been emitted in its `Some` case, and the port's
    formatter was missing an atom letter.** `--graph sym` is the first graph in the corpus
    with a `vmin_vmax` -- every `ParamArg` the nine earlier graphs carried had
    `vmin_vmax=None` -- so `mm`'s `Some` arm had never run. It ran, and produced
    `r(0:1,0:100)` against the py side's `r(l0:1,l0:100)`: `H.i64_text` is only the
    `hi:lo` PAIR (`helpers.bend:1701-1705`) and the `l` that marks it as an I64 is
    `is64`'s contribution, one line up, which `rng` did not call. **The cost was a
    four-node cascade with the cause in none of them:** `arg` is in the `core`, so a PARAM
    whose `arg` differs is a different node, its STACK is a different node, its RESHAPE is
    a different node, and the GROUP above them is a fifth -- and `rung-2`'s `loose` key
    includes `arg`, so even the fallback could not pair them. The report would have said
    "five nodes on one side, four on the other" and named no field. Fixed by using
    `is64`, and the fix is a one-token widening of an existing def rather than a new one.

13. **THE BYTE-IDENTITY CHECK HAD BEEN COMPARING NOTHING, AND REPORTING `BYTE-IDENTICAL`.**
    This is the most expensive defect this file has had, because it was a check that
    looked like the strongest evidence in the directory. `graphcmp-run.sh` ran
    `graphcmp.py emit py --graph G` and `... emit bend --graph G`; `--side` is a **flag**,
    not a positional, so argparse rejected both with `unrecognized arguments: py` and exit
    2, writing **zero bytes** each; and `cmp -s` on two empty files returns success.
    MEASURED BOTH WAYS: the committed `runs/graphcmp/D/D2-canon-{py,bend}-*.txt` were all
    **0 bytes** while `D2-cmp-*.txt` read `BYTE-IDENTICAL` for four graphs, and the same
    command with the correct spelling produces 18 rows for `matmul` that ARE
    byte-identical. **The cheapest check in the file was a vacuous pass, and it looked like
    a pass because a verdict line cannot tell an empty comparison from a satisfied one.**
    Two fixes, and the second is the one that generalises: the invocation is corrected,
    and `graphcmp-run.sh` now counts BYTES on both sides and prints
    `NOT COMPARED: py=0 bytes bend=N bytes` before it compares anything. A 0-row side is a
    FAILURE, never a pass -- the same rule `emit_bend`'s 5-attempt guard already enforces
    for the bend side, now enforced on the harness side too. The same round produced a
    second instance of the shape: a run killed mid-write left three `D5-plant-*.txt` files
    byte-identical to each other, which no plant can produce. `D1-verdicts.txt` and the
    byte guard are what catch that class, and step D9 now pairs a PLANT too.

14. **`dt_str`'s "the fold produced nothing" arm rendered `R` -- the letter that means
    "upstream raises" -- and the `?` ledger row counted only `shape`.** `dtype_from_uop`
    (`ops.py:123-190`) is TOTAL over `Ops`, so on the py side the dtype column is always a
    real name and `R` there could never mean anything. On the port side `F.UOp.dtype`
    answers `None` for an unsettled node and `dt_str` said `R` -- the same letter
    `shape_str` used for no-shape, for a state that is not upstream's. Two collisions in
    one letter, in a file whose own rule is that a letter is ONE fact. `dt_str`'s `None`
    is now `?`, and the ledger row for `?` is registered against **both** `dtype` and
    `shape` (`("?", (2, 3), ...)`): MEASURED `?=0/6` on `--graph sym` with the two-field
    row against `?=0/3` with the one-field row, and 6 is the truth (3 nodes x 2 columns).
    `selfcheck` asserts the count is 6 by running the bend side, and MEASURED that the
    assertion FIRES: narrowing the row back to `(3,)` makes `selfcheck` print
    `# SELFCHECK: FAIL` and exit 1. An assertion that cannot fail is not an assertion.

15. **`plant_srcswap` was hardcoded to `MUL`, so `--equiv` was only ever exercised on one
    of the eight commutative ops, and it silently found nothing on any other graph.** With
    the corpus widened, `--plant srcswap --graph commute` ran and reported
    `plant srcswap: no commutative op occurs exactly once in []` -- a plant that quietly
    finds no target is a plant that would have reported `AGREE` for its own reasons. Two
    changes, both measured: the plant now picks the first commutative op that occurs
    EXACTLY ONCE in the graph (MUL on `matmul`, unchanged; ADD on `group` and `commute`),
    and it **raises** if there is none. A second defect surfaced in the same line:
    `COMM` holds bare NAMES (`o.name`) because `Node.op` is wire text, and `Ops.ADD in COMM`
    is `False` -- the first version answered an empty list on a graph built out of six
    commutative nodes. And `--equiv` now has a second fixture:
    `diff --graph commute --plant srcswap` DISAGREE naming `src` on the ADD **and** the
    GROUP, `--equiv` AGREE on 14 nodes.

16. **THIS FILE ASSERTED, IN THREE PLACES, THAT NO NODE IN THE CORPUS HAD MORE THAN ONE
    PARENT. IT IS FALSE, AND THE CENSUS THAT CAUGHT IT IS NOW ON EVERY REPORT.** The
    sentences were in `graphcmp.py`'s header, in `g_group`'s docstring, and here; they were
    written as justification for building `--graph group` and they were never measured.
    MEASURED, per graph (`# MULTI-PARENT NODES (op#id in-edges/parents)`, printed by
    `diff` on both sides):

        matmul   CONST#2 2e/2p  CONST#3 4e/4p  CONST#6 2e/2p  CONST#10 2e/2p
        binblob  the same four, because it hangs the BINARY off the matmul
        commute  STACK#4 2e/2p  RESHAPE#5 6e/6p  RESHAPE#7 6e/6p
        group    RESHAPE#5 4e/2p
        sym      CONST#2 3e/3p  RESHAPE#5 2e/2p
        reduce, buffer, sink, range, rangeflat, cast, special, indexed   ZERO

    So the differ HAD been placing shared nodes by up to four parents all along, and every
    one of them was a shape `CONST` whose `core` is a leaf. The two properties the round
    actually added are narrower and are what `--graph group` is for: **a shared node with
    a real subtree under it** (`group`'s RESHAPE, `commute`'s two at six parents each) and
    **a repeated child index** (`src=n(i5,i5)`), which no earlier graph had.

    The lesson is the one this section keeps earning, in a new place: **a prose claim
    written to justify a fixture is a claim with no denominator, and it was wrong in the
    direction that flattered the fixture.** `multiparent` is now computed on every report
    and folded into the verdict's `DENOMINATOR` line, so the next version of the claim has
    to agree with a number that a reader can see move. Two COUNTS are printed rather than
    one -- in-edges and distinct parents -- because a node that names the same child twice
    in its own `src` inflates the edge count (`group`'s RESHAPE is 4 edges over 2 parents),
    and reporting only the edge count would have made the fixture look four-parented.

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

A clean run establishes: on this substrate, for these 13 graphs, the port's arena and
CPython's arena agree on op, dtype, shape, depth, tag, a structural arg and the ordered
child edges for **104 nodes -- 624 field-records** -- on **12 of 13** graphs, modulo the
residuals printed above. The 13th, `sym`, DISAGREES on 3 of 12 nodes and on `dtype` and
`shape` only, and that disagreement is the measurement in §3(b).

It does NOT establish: that the port builds correct graphs (only that they MATCH
CPython's), that the residual-bearing constructs are right, anything about the 54
unexercised ops, anything at a device other than CPU, that a symbolic dim can be built by
the port at all, or anything about a real kernelized program.
