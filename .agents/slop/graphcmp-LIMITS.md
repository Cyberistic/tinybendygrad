# graphcmp -- WHAT IT DOES NOT COMPARE, and what it got wrong.

Every item here is MEASURED on this tree, and every one is printed by the tool rather than
living only in this file: the ledger rows are on every report, the denominators are on
every verdict, and `selfcheck` asserts the ones that are assertions rather than counts.
What this file adds is the reasoning, and the items that CANNOT be printed.

Run: `E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`
(`E` is also the prefix in `runs/graphcmp/D/README-D.txt`.)

---

## 1. DEFECTS FOUND BY WIDENING, all in this file's own normal form

These are not limits; they are bugs that existed before 2026-10-04 and are now fixed.
They are listed because a coverage claim is only worth what the holes in it cost, and
these are what the holes cost.

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
5. **`unchunks` REQUIRED a space between chunks, which made whitespace structural** -- the
   one thing the `<bytecount>:<bytes>` wire exists to avoid. Nothing caught it because every
   field the eight-field wire carried was an ATOM text and no atom contains a space. The
   DEBUG rows broke it: a site prints `memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2
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
    shared-cores= commutative-ops=` on the line above the verdict.

---

## 2. WHAT THE DIFFER DOES NOT COMPARE

**Node identity (`id`, R1) -- never.** The two arenas number differently: CPython interns
in ucache-hit order, `ops.bend` numbers by construction order. A differ keyed on `id`
compares nothing. `id` is printed for the reader and is not in the equality decision.

**Construction order and node order.** Nothing compares which node was built first, only
the `src` order inside each node. Two arenas that build the same DAG in opposite orders
agree.

**A symbolic dimension's identity.** A dim is `int|UOp` (`ops.py:1925`) and a symbolic
one renders `U` -- so two DIFFERENT symbolic dims are indistinguishable. MEASURED: 0 of the
63 nodes across 9 graphs has a symbolic dim, so this is an untested hole and not a measured
one.

**A float CONST's structure.** `konst` renders a float as `f` + `repr(x)`, so for a float
CONST the normal form IS a string comparison. That is the ONE place a `repr` reaches the
equality decision and it is deliberate: a Python float has no structure to compare, so
there is nothing structural to lose. MEASURED: 0 of the 63 nodes has a float CONST, so the
choice is untested rather than measured.

**A realized buffer's device object (`z`) -- PRESENCE only.** `Buffer` has no `slot`
(MEASURED) and the port's is a P6 allocator slot with no runtime behind it. Size, dtype,
device and offset are already `ParamArg` fields 2/3/8 and ARE compared. Live on `buffer`
(`z=1/1`).

**A bytes CONST -- a PORT gap, not a normal-form loss.** Upstream's `PyConst` includes
`bytes` (`ops.py:122`); the port's `Const` is `CBool|CInt|CFloat|CInvalid`
(`ops.bend:810-811`) and `graphcmp.bend`'s `konst` has no bytes arm, so there is no port
spelling at all. The `y` residual is now exactly this and nothing else.

**A UOp nested in an arg (`u`) -- identity NOT compared.** MEASURED: `PYLITERAL`'s nested
UOp is in neither `src` nor `toposort`, so it has no arena index here. Reachable only via
`--plant pyuop`.

**Applied options (`q`) -- a COUNT.** `ops.bend:978` types `applied_opts`/`opts_to_apply`
as `List<U32>` and upstream's elements are `Opt` dataclasses. Reachable only via
`--plant opt`, where the port emits one `q` per option.

**Six of the eight ledger markers are live on NO graph**: `u`, `q`, `X!`, `BAD`, `?`, `E`.
`?` cannot be produced by the py side at all (it is the port's "fold produced no shape").
The other five are reachable only through plants, which is what the plants are for.

**`KernelInfo.estimates` -- NEITHER SIDE CARRIES IT.** Dropped by the port (P5,
`tinygrad.renderer`) and `None` for every kernel the port can build, so the count would be
0 by construction and is named rather than printed as a zero.

---

## 3. WHAT THE DIFFER CANNOT DO, structurally

**Two nodes with the same core and a different multiplicity.** `zip` truncates; the count
is printed (`zip-truncated=`) so it is not silent, but a multiplicity difference is not
REPORTED as one.

**A rung-2 pairing with no mutual best is DROPPED to rung 3.** Both nodes are printed in
full, so nothing is hidden, but the difference is reported as "one-sided" rather than named
as a field. That is a deliberate refusal to claim (five RESHAPEs of the matmul share one
`loose` key and pairing them all produced a report full of crosswise nonsense) and it is a
real cost: some genuine field differences arrive as unpaired nodes.

**Rung 3.5 pairs only when the op is UNIQUE on both sides.** An op appearing twice on each
side gets no cross-reference. `field-records` and the rung counts are still printed.

**The device is pinned.** `--dev CPU` by default, because the port's fixture pins the
ALLOC device at arena tag 0. A different device is exit 2 ("NOT WELL-POSED, and this is
NOT a verdict"), never a verdict.

**`dbg` is a PORT-vs-PORT comparison across levels, not port-vs-CPython.** MEASURED:
CPython's own `DEBUG >= 1` memory line (`memory.py:59-60`) fired on 0 of 8 real graphs
(`runs/graphcmp/D/D8b-cpython-dbg1-reachability.txt`), so there is no CPython lane for the
trace text on this host. The seven sites are reached through the port's own `*_dbg*` defs
with the level threaded in, so what `dbg` proves is that a LEVEL CHANGE MOVES A NAMED SET
OF ROWS -- not that any row's text is right.

**13 of 77 ops. That is the coverage number, not "nine graphs".** MEASURED by
`list(Ops)` on this tree, not by reading the enum:

  REACHED (13): ALLOC BINARY BUFFER CAST CONST MUL PERMUTE RANGE REDUCE RESHAPE SINK
                SPECIAL STACK
  NOT REACHED (64): NOOP REWRITE_ERROR PARAM CALL PROGRAM LINEAR SOURCE AFTER GROUP
                GETADDR INDEX SHRINK LOAD STORE WMMA BITCAST EXP2 LOG2 SIN SQRT RECIPROCAL
                NEG TRUNC ADD SHL SHR CDIV MAX CMOD CMPLT CMPNE CMPEQ XOR OR AND THREEFRY
                SUB FDIV POW FLOORDIV FLOORMOD WHERE MULACC BARRIER IF END ENDIF BACKEDGE
                CUSTOM CUSTOMI INS CONTIGUOUS_BACKWARD DETACH STAGE COPY MSELECT MSTACK
                CUSTOM_FUNCTION EXPAND PAD FLIP UNSHARD ALLREDUCE PYLITERAL

  So six of the eight COMMUTATIVE ops (ADD AND MAX CMPNE CMPEQ XOR OR) are unexercised;
  only MUL is, and it is the one `--plant srcswap` reorders. `--equiv` is therefore
  MEASURED on one of its eight ops, not eight.
  **These are hand-built graphs, not a kernelized program.** A real
  `kernelize`+`rangeify` graph brings INDEX/BARRIER/GROUP/ENDIF/BACKEDGE/LOAD/STORE, and
  those are exactly the ops that decide whether a SCHEDULE is right -- the shapes here do
  not exercise a single one of them.

---

## 4. THE THREE CONFLATIONS, and the honest answer on the third

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
   MODE. `--equiv` did not exist before this session. On ONE fixture (`--plant srcswap`):
   `diff` prints `DISAGREE` naming `src`, and `diff --equiv` prints `AGREE` on 18 nodes /
   108 field-records. The naive answer -- keying on `repr` -- gives AGREE for BOTH, which is
   right for equivalence and wrong for identity, so it conflates the two. The commutative
   set is read from CPython's `GroupOp.Commutative` rather than typed, and MEASURED to
   agree with the port's `GroupOp.commutative` on all eight ops.

---

## 5. WHAT A CLEAN RUN DOES AND DOES NOT ESTABLISH

A clean run establishes: on this substrate, for these nine graphs, the port's arena and
CPython's arena agree on op, dtype, shape, depth, tag, a structural arg and the ordered
child edges for all 63 nodes -- 378 field-records -- modulo the residuals printed above.

It does NOT establish: that the port builds correct graphs (only that they MATCH
CPython's), that the residual-bearing constructs are right, anything about the ~190
unexercised ops, anything at a device other than CPU, or anything about a real kernelized
program.