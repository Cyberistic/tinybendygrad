# THE WIDENING, ROUNDS 1, 2 AND 3. Every artifact here, and the exact command that made it.
#
# env -u PYTHONPATH is REQUIRED (it contaminates a control) and LC_ALL=C is REQUIRED (a
# locale-colated sort fabricates diffs). DEV=NULL is the rebase gate's own setting; the
# differ OVERRIDES it with its `--dev` value, default CPU, and prints the device set on
# every report so a device mismatch is visible rather than inferred.
#
# E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py
# ALL OF IT AT ONCE: sh .agents/slop/graphcmp-run.sh
# REPRODUCIBILITY:         sh .agents/slop/graphcmp-repro.sh
#
# SUBSTRATE AT CAPTURE TIME (round 3):
#   tinybendygrad/uop/ops.bend    sha256 REPLACE_ME
#   tinybendygrad/uop/fold.bend   sha256 REPLACE_ME
#   .agents/slop/graphcmp.bend    sha256 REPLACE_ME
#   .agents/slop/graphcmp.py      sha256 REPLACE_ME
#   .agents/slop/graphcmp-run.sh  sha256 REPLACE_ME
#   .agents/slop/graphcmp-repro.sh sha256 REPLACE_ME
#   .agents/slop/graphcmp-p14-sched.py sha256 REPLACE_ME
# `uop/ops.bend` and `uop/fold.bend` are under SINGLE OWNERSHIP by another unit and moved
# through at least six digests across rounds 1-2 and then went COLD THREE MORE TIMES during
# round three (`sym_dim.pa` at :1250 not compiling; `ParamArg`'s field list renamed
# mid-run). Every artifact here was RE-CAPTURED at the digests above, and
# `graphcmp-repro.sh` waits for the substrate and accepts a run only if its own summary
# reads 16 graphs / 13 AGREE / selfcheck OK / census-rc=0. `ALL PROOFS CHECK` on
# graphcmp.bend is NOT the gate agreeing -- the gate is `E diff --graph NAME`, and it is
# run below.
#
# ---------------------------------------------------------------------------
# THE ARTIFACT. ONE command, ONE argument, ONE verdict line, WITH ITS DENOMINATOR.
# ---------------------------------------------------------------------------
# E diff --graph NAME
#
#   NAME         nodes/side  ops  depths  sym  multi-parent  live ledger  VERDICT
#   matmul          18/18     7     1      0      4          none        AGREE
#   reduce           7/7      6     1      0      0          none        AGREE
#   buffer           5/5      4     1      0      0          z=1/1       AGREE
#   sink             2/2      2     1      0      0          none        AGREE
#   range            2/2      2     2      0      0          none        AGREE
#   rangeflat        2/2      2     1      0      0          none        AGREE
#   cast             6/6      5     1      0      0          none        AGREE
#   special          2/2      2     1      0      0          none        AGREE
#   binblob         19/19     8     1      0      4          y=1/1       AGREE
#   group            8/8      7     1      0      1          none        AGREE
#   commute         14/14    11     1      0      3          none        AGREE
#   indexed          7/7      6     1      0      0          none        AGREE
#   sym             12/12     6     1      2/2    2          none        AGREE
#   lin             46/46    11     1      0      6          E=1/0 q=0/1 DISAGREE  <-- MEASURED
#   loop            25/25    14     1      0      8          ?=0/2       DISAGREE  <-- MEASURED
#   gate            14/14    12     1      0     11          none        AGREE
#   --------------------------------------------------------------------------
#   TOTAL         189/189   34 distinct ops: ADD AFTER ALLOC AND BACKEDGE BARRIER BINARY
#                                 BUFFER CALL CAST CMPLT CMPNE CONST END ENDIF GROUP IF
#                                 INDEX LINEAR LOAD MAX MUL NOOP OR PARAM PERMUTE RANGE
#                                 REDUCE RESHAPE SINK SPECIAL STACK STORE XOR
#   Commutative ops reached: 7 of 8 (CMPEQ is not reachable from an eager graph -- and is
#     STILL not reachable after three REAL kernels, which is the measurement).
#   Symbolic-dim nodes: 2 of 189.   Field-records: 189 x 6 = 1134 per side.
#   Byte-identical canonical files: 14 of 16 -- the two that differ are `lin` and `loop`, and
#     each differs on exactly the node named below.
#
# Fields: 8 on the wire, 6 IN THE EQUALITY DECISION (dtype shape depth tag arg src).
# `id` is reporting-only by R1 -- the two arenas number differently, so a differ keyed on
# it compares nothing. Each graph prints `fields=6 field-records=<nodes*6>`, so an AGREE
# on 2 nodes (12 field-records) cannot be read as an AGREE on 19 (114).
# Files: D1-graph-*.txt, and D1-verdicts.txt which ASSERTS the whole column above every run
# so a moved verdict is a moved file rather than something a reader has to notice.
#
# `sym` USED TO DISAGREE, on 3 of its 12 nodes and on `dtype`/`shape` only: the port's
# `fold.bend` could not mint a symbolic dim at all (`ssimplify` wall). MEASURED 2026-10-04
# late in the day: THAT WALL IS CLOSED. `fold.bend`'s `sym_dim.pa` (`fold.bend:1296`, the
# `AParam` arm of `sym_dim.of`) landed from the `fold` unit; `sym` now reads `?=0` and
# `VERDICT: AGREE` at 12 of 12 with `SYMBOLIC DIMS py=2/12 bend=2/12`. This unit did not
# fix it and did not cause it -- the fixture and the denominator are what this unit
# contributed. See LIMITS section 3b for the three pinned numbers that had to move with it.
#
# `lin`, `loop` and `gate` ARE ROUND THREE, and they are the first graphs here whose PY
# side is a call into tinygrad's own scheduler and codegen rather than a hand-built
# expression:
#   lin   `full_rewrite_to_sink(schedule_linear(matmul))` -- a REAL KERNELIZED PROGRAM.
#         DISAGREE on 1 node of 46: the SINK's `applied_opts`, which the port can only
#         answer with one `q` per option (ops.bend:978 types them `List<U32>`; upstream's
#         elements are `Opt` dataclasses). That residual was documented as a count-only
#         comparison while it was hypothetical; it is now a measured disagreement.
#   loop  `hcq_fence(tv, tv, tv, 0)` -- tinygrad's OWN HCQ2 poll-loop kernel, called.
#         DISAGREE on 1 node of 25: the CALL, whose dtype the port reads from
#         `CallInfo.cdtype` -- a field CPython's `CallInfo` DOES NOT HAVE (ops.py:130-131
#         reads `src[0].dtype`). Reported, not fixed; `fold.bend` is another unit's file.
#   gate  a gated STORE through the REAL `pm_linearize_cleanups` (codegen/__init__.py:403,
#         the only site in this tree that constructs `Ops.ENDIF`). AGREE at 14 nodes, and
#         it is the WIDEST FAN-IN in the corpus because its root is a `LINEAR` whose src is
#         the whole LINE LIST: RANGE#5 has 5 parents.
#   The BEND side of all three is still hand-built, because `schedule/__init__.bend` DEFERRs
#   `__init__.py:82-301` and THE PORT CANNOT BUILD A SCHEDULE AT ALL.
#
# `range` and `rangeflat` are a PAIR and are only meaningful as one: same op, same dtype,
# same `()` shape, same `N` tag, and they differ in exactly two of the eight fields.
# Before them EVERY node of EVERY graph had `depth=i0` on BOTH sides, so R5 had never been
# asked a question -- and the first graph to ask it found an off-by-one (LIMITS #1).
# `group` is the same argument about `src`, but NARROWER than it first looked: `matmul`
# already shared four nodes (its shape CONSTs, one of them with four parents), so what
# `group` adds is a shared node with a real SUBTREE under it and a REPEATED child index
# (`src=n(i5,i5)`). LIMITS #16 is the false version of that claim and how the census that
# caught it got onto every report.
# `commute` is the same argument about `equiv`: before it only ONE of the eight
# commutative ops had a node anywhere in the corpus.
# ---------------------------------------------------------------------------
# THE REST, in the order the runner does it. rc=0 unless the line says otherwise.
# ---------------------------------------------------------------------------
D0  E selfcheck                                     D0-selfcheck.txt
      MEASURED: OK. Now also runs the bend side of `sym` to assert the `?` ledger row
      counts BOTH columns (6 = 3 nodes x 2). MEASURED that the assertion FIRES: narrowing
      the row back to one column makes selfcheck print FAIL and exit 1.
D0  E2 .venv/bin/python .agents/slop/graphcmp-oracle.py    D0-coverage-census.txt
      Per graph: nodes on BOTH sides, distinct ops, distinct arg ATOM LETTERS, distinct
      shape texts, distinct depth values, SYMBOLIC-DIM nodes, and which ledger markers are
      LIVE. Then the corpus-wide PER-OP NODE COUNTS (nodes/graphs), which are the
      denominator for every op claim. MEASURED: 16 graphs, 189 nodes/side, 34 of 77 ops,
      7 of 8 commutative ops, 2 of 189 symbolic-dim nodes, 5 of 8 ledger markers live,
      0 unmapped atom letters, `# ORACLE SELFCHECK: OK`, and `rc=0` on the last line --
      the rc is captured because the oracle calls `emit_bend` and a dead substrate used to
      leave a nine-row table that read like a census. Its three assertions are the two
      `atoms()` rows of LIMITS defect 21 and the unmapped-atom row; MEASURED that they fire.
D0  (the runner's own tally of the run)            D0-run-summary.txt
D0  E3 .venv/bin/python .agents/slop/graphcmp-p13-ops.py     D0-ops-probe.txt
      THE RAW CPython MEASUREMENTS every coverage claim rests on, and a separate file
      because they are questions a port-vs-port diff cannot answer: does `Ops.GROUP` carry
      a `params` list (no -- Q1), which Tensor op emits which NODE op and is it one of the
      eight `GroupOp.Commutative` (Q3), can two different symbolic dims be separated and by
      which field (Q4), what is a variable PARAM's slot and does the port have a spelling
      for it (Q5), and the corpus-wide op/node/symbolic-dim tally (Q6). Q2 is the fan-in
      census per graph.
D1  E diff --graph NAME   (x16)                     D1-graph-*.txt
D1  (asserts the 16 verdicts)                      D1-verdicts.txt
D2  E emit --side py|bend --graph NAME; `cmp`       D2-bytediff.txt + D2-canon-*.txt
      MEASURED: 14 of 16 BYTE-IDENTICAL, and `lin` and `loop` DIFFER on exactly the nodes
      named above. The runner COUNTS BYTES on both sides first and prints `NOT COMPARED`
      rather than comparing two empty files -- see LIMITS #13, where this step had been
      reporting BYTE-IDENTICAL over 0-byte files for four graphs.
D3  E control --graph {matmul,binblob,group,gate,loop}   D3-control-*.txt
      MEASURED: CONTROL VERDICT OK on all five -- each side against ITSELF. `group` is the
      first DAG, so a control over a tree-only corpus is a control that has never met a
      two-parent node. `gate` and `loop` are here because a control that only ever runs on
      AGREEing fixtures has never had to agree with itself WHILE disagreeing.
D4  E cross --graph range                          D4-cross-range.txt
      MEASURED: CROSS VERDICT OK -- it disagrees with a DIFFERENT graph.
D5  E diff --graph matmul --plant P   (x6)          D5-plant-*.txt   ALL rc=1 (DISAGREE)
      The planted node is named. MEASURED, `--plant srcswap`:
        MISMATCH MUL  py#16 vs bend#16  (no shared core; paired one-to-one ...)
            src  py=['bd57da94', '2b7d1a7e'] bend=['2b7d1a7e', 'bd57da94']
D5  E diff --graph sym --plant sym1                D5-plant-sym1.txt  rc=1 DISAGREE
      The symbolic-dim control: 12 nodes become 9 and the GROUP's `src` is named. **NOT the
      attributable measurement** -- a plant edits the PY side only (planting the bend side
      would mean six DAG rewrites in Bend, which is why `--plant-side` was removed), so this
      file carries the plant's structural effect AND the `sym` graph's pre-existing `?`
      disagreements at once, and the rung-2 pair it prints is the latter. The attributable
      one is CONFLATION 4 in D7, which is py-vs-py and names `src` with nothing else moving.
D6  E diff --graph matmul  --plant srcswap          D6-srcswap-ordered.txt   rc=1 DISAGREE
     E diff --graph matmul  --plant srcswap --equiv  D6-srcswap-equiv.txt     rc=0 AGREE
     E diff --graph commute --plant srcswap          D6-commute-ordered.txt   rc=1 DISAGREE
     E diff --graph commute --plant srcswap --equiv  D6-commute-equiv.txt     rc=0 AGREE
      Two fixtures, TWO answers each, both results. 18 nodes / 108 field-records on the
      matmul, 14 / 84 on commute. The commute pair is what moves `--equiv` from ONE of the
      eight commutative ops to SEVEN, and the ORDERED answer there names `src` on BOTH the
      ADD and the GROUP above it.
D7  E conf                                          D7-conf.txt
      CONFLATION VERDICT: ALL FOUR DISTINGUISHED. The fourth is the symbolic-dim pair.
D8  E dbg --levels 0,1,2                            D8-dbg-012.txt
     E dbg --levels 0,3                              D8-dbg-03.txt
      DEBUG VERDICT: the levels are DISTINGUISHABLE and the graph was fixed.
D8b E .venv/bin/python .agents/slop/graphcmp-dbg-oracle.py   D8b-cpython-dbg1-reachability.txt
      MEASURED: CPython's own `DEBUG >= 1` memory line fired on 0 of its 8 tensor fixtures.
      Those 8 are TENSOR fixtures, not graphcmp graphs -- do not read the 8 as a graph
      count. So `dbg` is PORT-AT-LEVEL-A vs PORT-AT-LEVEL-B and not a port-vs-CPython
      comparison, and says so. A 0 of 8 is a statement about 8 fixtures.
D9  E diff --graph {group|sym|loop|gate|commute --plant srcswap}, twice; `cmp`   D9-stability-*.txt
      MEASURED: 5 of 5 pairs BYTE-IDENTICAL. Five cases because the interesting shapes
      differ: the first graph with a shared non-leaf, TWO graphs that DISAGREE (so a report
      whose disagreements moved would be the one that matters), the widest fan-in in the
      corpus, and a PLANT (a run killed mid-write once left three D5 files byte-identical
      to EACH OTHER, which no plant can produce).
      MEASURED OVER THE WHOLE DIRECTORY, by `sh .agents/slop/graphcmp-repro.sh`:
      **158 of 158 files identical across two clean runs.** The old claim of the same
      shape was backed by `find | md5 -q`, which on macOS takes exactly ONE file and
      prints nothing given several -- so it was not a digest, and when the check was
      written properly it found a real nondeterminism on its FIRST run (a `dict` printed in
      set-iteration order; LIMITS defect 20).
D10 E emit --side bend --bend-probe .agents/slop/graphcmp-empty.bend
      MEASURED: rc=1, "0 rows after 5 attempts -- a FAILURE, not a verdict". The guard is
      SEEN TO FIRE. Before round one the probe flag never reached the `emit` path, so
      the one command whose job is to emit could not demonstrate the guard (LIMITS #4).

# ---------------------------------------------------------------------------
# WHAT IS NOT HERE, and why.
# ---------------------------------------------------------------------------
# No `D3-control-sym.txt`, no `D3-control-lin.txt`. Those graphs DISAGREE against the port
# by construction (see the table above), so a CONTROL over them would be AGREE (each side
# against itself) and would say nothing about the disagreement. The py-vs-py control for
# `sym` is CONFLATION 4 in D7. (`loop` IS controlled, deliberately, and that is the
# difference: a control over a DISAGREEING graph is worth having precisely because the graph
# disagrees.)
# No per-op fixture for `CMPEQ`. It is not reachable from an eager graph: `UOp` has no
# `cmpeq`, and `(a == b).uop` emits `CMPNE CONST CMPNE`. MEASURED, and STILL measured after
# round three added three real kernels -- so it is a property of the op, not of the corpus.
# **CLOSED IN ROUND THREE:** there is no longer "no graph for `ENDIF`/`BACKEDGE`/`LOAD`/
# `STORE`". `lin`, `loop` and `gate` carry them, with per-op node counts in LIMITS 0 and 5.
# The narrowing that remains is stated rather than hidden: `ENDIF` is reachable ONLY from a
# hand-spelled gated store, because **0 of 9 scheduled programs** mint one
# (`.agents/slop/graphcmp-p14d.py` Q1); and `LOAD`/`STORE` need no executor at all -- they
# are graph ops and `lin`'s six LOADs have never been run.
#
# ---------------------------------------------------------------------------
# CONCURRENCY. `tinybendygrad/uop/ops.bend` and `uop/fold.bend` are being edited by another
# unit and moved through at least six digests across rounds 1-2 and then went COLD THREE
# MORE TIMES during round three. Every consequence is recorded rather than worked around:
#   * one failure named a def that is NOT in this unit's files -- `def UOp.huo.go` appeared
#     TWICE, a duplicate declaration. Reported, not edited: it is not my file.
#   * `uop/ops.bend:7028 UOp.const_factor.mul` stopped compiling and blocked the coverage
#     census for one pass. The census was re-run after the tree came back.
#   * ROUND THREE: `sym_dim.pa` at `uop/ops.bend:1250` (`match O.ParamArg.vmin_vmax(pa)` --
#     a computed-value scrutinee) failed to compile, twice; and `ParamArg`'s field list was
#     renamed mid-run once. All three were caught by `graphcmp.bend --check-only`'s FIRST
#     LINE, and `emit_bend`'s 5-attempt guard turned each into
#     `0 rows after 5 attempts -- a FAILURE, not a verdict`, with `D2-cmp-*` reporting
#     `NOT COMPARED` rather than `BYTE-IDENTICAL`. **That is the behaviour those guards were
#     written for and it is worth recording that they worked.**
#   * MEASURED CONSEQUENCE FOR THE REPRODUCIBILITY CLAIM: the two-run byte check CANNOT be
#     taken on a run that broke part way through -- a concurrent edit landed between graph
#     12 and graph 13 of one run, so twelve real reports and four 0-row failures were both
#     "files" and both hashed. `graphcmp-repro.sh` therefore takes a snapshot only from a
#     run whose own summary reads `graphs=16 graphs-agree=13 selfcheck=OK census-rc=rc=0`.
#   * the three round-two/round-three findings that are PORT bugs rather than harness bugs
#     are reported and NOT fixed, because the files are not this unit's: `ParamArg.slot = -1`
#     two conflicting sentinels (LIMITS section 2) and `fold.bend:1067`'s `call_dt` reading
#     `CallInfo.dtype`, a field CPython's `CallInfo` does not have (LIMITS section 2,
#     `loop`). `fold.bend`'s `marg` `ssimplify` wall (LIMITS 3b) WAS such a finding -- and it
#     was CLOSED by the `fold` unit mid-session, which is the one item on this list that has
#     since been fixed by someone else.
#   * the artifacts above are all from the final compiling tree at the digests quoted at
#     the top.
