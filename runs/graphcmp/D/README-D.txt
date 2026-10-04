# THE WIDENING, ROUNDS 1 AND 2. Every artifact here, and the exact command that made it.
#
# env -u PYTHONPATH is REQUIRED (it contaminates a control) and LC_ALL=C is REQUIRED (a
# locale-colated sort fabricates diffs). DEV=NULL is the rebase gate's own setting; the
# differ OVERRIDES it with its `--dev` value, default CPU, and prints the device set on
# every report so a device mismatch is visible rather than inferred.
#
# E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py
# ALL OF IT AT ONCE: sh .agents/slop/graphcmp-run.sh
#
# SUBSTRATE AT CAPTURE TIME (round 2):
#   tinybendygrad/uop/ops.bend    sha256 4d9157b89833d11f5ed545b4f40560741f424997bb624f099f9eadfd8beb5ab6
#   tinybendygrad/uop/fold.bend   sha256 b90f015ea74bb4669d85ee5d18adbb436df205738ddc0c3902fe10939828a107
#   .agents/slop/graphcmp.bend    sha256 eaaf1eb4ac5fc590424ad3127709cf8897169c11fa2ecc4a73233b32e2997c8c
#   .agents/slop/graphcmp.py      sha256 3e4a110ea0754763e824d860fc95f12747c42c9ad0e10882431d474040f01fca
#   .agents/slop/graphcmp-run.sh  sha256 1f6a60e81238e72cc1d8100fa99f5eaa5242f672946144b2e203b5ed0f3736e5
#   .agents/slop/graphcmp-p13-ops.py  sha256 6afb384fb7f6744ed5307bc50556f3138e847a9bc799cac8c88dca8cb8c21039
# `uop/ops.bend` and `uop/fold.bend` are under SINGLE OWNERSHIP by another unit and moved
# during the session (round 1 captured `ops.bend` at 496f1607; round 2 at 4d9157b8). Every
# artifact here was RE-CAPTURED at the digests above. `ALL PROOFS CHECK` on graphcmp.bend
# is NOT the gate agreeing -- the gate is `E diff --graph NAME`, and it is run below.
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
#   sym             12/12     6     1      2/0    2          ?=0/6       DISAGREE  <-- ON PURPOSE
#   --------------------------------------------------------------------------
#   TOTAL         104/104   23 distinct ops: ADD ALLOC AND BARRIER BINARY BUFFER CAST
#                                 CMPNE CONST GROUP INDEX MAX MUL OR PARAM PERMUTE RANGE
#                                 REDUCE RESHAPE SINK SPECIAL STACK XOR
#   Commutative ops reached: 7 of 8 (CMPEQ is not reachable from an eager graph).
#   Symbolic-dim nodes: 2 of 104.   Field-records: 104 x 6 = 624 per side.
#
# Fields: 8 on the wire, 6 IN THE EQUALITY DECISION (dtype shape depth tag arg src).
# `id` is reporting-only by R1 -- the two arenas number differently, so a differ keyed on
# it compares nothing. Each graph prints `fields=6 field-records=<nodes*6>`, so an AGREE
# on 2 nodes (12 field-records) cannot be read as an AGREE on 19 (114).
# Files: D1-graph-*.txt, and D1-verdicts.txt which ASSERTS the whole column above every run
# so a moved verdict is a moved file rather than something a reader has to notice.
#
# `sym` IS SUPPOSED TO DISAGREE, on 3 of its 12 nodes and on `dtype`/`shape` only: the
# port's `fold.bend` `marg` cannot `ssimplify` a non-CONST STACK element, so the port
# cannot build a symbolic dim at all. See LIMITS section 3.
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
      denominator for every op claim. MEASURED: 13 graphs, 104 nodes/side, 23 of 77 ops,
      7 of 8 commutative ops, 2 of 104 symbolic-dim nodes, 3 of 8 ledger markers live,
      0 unmapped atom letters.
D0  (the runner's own tally of the run)            D0-run-summary.txt
D0  E3 .venv/bin/python .agents/slop/graphcmp-p13-ops.py     D0-ops-probe.txt
      THE RAW CPython MEASUREMENTS every coverage claim rests on, and a separate file
      because they are questions a port-vs-port diff cannot answer: does `Ops.GROUP` carry
      a `params` list (no -- Q1), which Tensor op emits which NODE op and is it one of the
      eight `GroupOp.Commutative` (Q3), can two different symbolic dims be separated and by
      which field (Q4), what is a variable PARAM's slot and does the port have a spelling
      for it (Q5), and the corpus-wide op/node/symbolic-dim tally (Q6). Q2 is the fan-in
      census per graph.
D1  E diff --graph NAME   (x13)                     D1-graph-*.txt
D1  (asserts the 13 verdicts)                      D1-verdicts.txt
D2  E emit --side py|bend --graph NAME; `cmp`       D2-bytediff.txt + D2-canon-*.txt
      MEASURED: 12 of 13 BYTE-IDENTICAL, and `sym` DIFFERS on exactly the 3 rows LIMITS
      section 3 names. The runner COUNTS BYTES on both sides first and prints
      `NOT COMPARED` rather than comparing two empty files -- see LIMITS #13, where this
      step had been reporting BYTE-IDENTICAL over 0-byte files for four graphs.
D3  E control --graph NAME   (matmul, binblob, group)   D3-control-*.txt
      MEASURED: CONTROL VERDICT OK on all three -- each side against ITSELF. `group` is
      here because it is the first DAG and a control over a tree-only corpus is a control
      that has never met a two-parent node.
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
D9  E diff --graph {group|sym|commute --plant srcswap}, twice; `cmp`   D9-stability-*.txt
      MEASURED: 3 of 3 pairs BYTE-IDENTICAL. Three cases because the three interesting
      shapes differ: the first graph with a shared non-leaf, the one graph that DISAGREES,
      and a PLANT (a run killed mid-write once left three D5 files byte-identical to EACH
      OTHER, which no plant can produce). MEASURED SEPARATELY, over the whole directory: two
      consecutive clean runs of graphcmp-run.sh leave all 126 files here byte-identical.
D10 E emit --side bend --bend-probe .agents/slop/graphcmp-empty.bend
      MEASURED: rc=1, "0 rows after 5 attempts -- a FAILURE, not a verdict". The guard is
      SEEN TO FIRE. Before round one the probe flag never reached the `emit` path, so
      the one command whose job is to emit could not demonstrate the guard (LIMITS #4).

# ---------------------------------------------------------------------------
# WHAT IS NOT HERE, and why.
# ---------------------------------------------------------------------------
# No `D3-control-sym.txt`. `sym` is DISAGREE against the port by construction, so a
# CONTROL over it would be AGREE (each side against itself) and would say nothing about
# the disagreement. The py-vs-py control for `sym` is CONFLATION 4 in D7.
# No per-op fixture for `CMPEQ`. It is not reachable from an eager graph: `UOp` has no
# `cmpeq`, and `(a == b).uop` emits `CMPNE CONST CMPNE`. Measured, and recorded as a limit.
# No graph for `ENDIF`/`BACKEDGE`/`LOAD`/`STORE`. Those need a `STORE` body or a loop, and
# none is constructible from the eager Tensor API in a few lines. They are the remaining
# gap and LIMITS section 5 says so.
#
# ---------------------------------------------------------------------------
# CONCURRENCY. `tinybendygrad/uop/ops.bend` and `uop/fold.bend` are being edited by another
# unit and moved through at least six digests across the two rounds. Two consequences, both
# recorded rather than worked around:
#   * one failure named a def that is NOT in this unit's files -- `def UOp.huo.go` appeared
#     TWICE, a duplicate declaration. Reported, not edited: it is not my file.
#   * `uop/ops.bend:7028 UOp.const_factor.mul` stopped compiling and blocked the coverage
#     census for one pass. The census was re-run after the tree came back.
#   * the two round-two findings that are PORT bugs rather than harness bugs are reported
#     and NOT fixed, because the files are not this unit's: `fold.bend`'s `marg`
#     `ssimplify` wall (LIMITS 3b) and `ParamArg.slot = -1`'s two conflicting sentinels
#     (LIMITS section 2).
#   * the artifacts above are all from the final compiling tree at the digests quoted at
#     the top.
