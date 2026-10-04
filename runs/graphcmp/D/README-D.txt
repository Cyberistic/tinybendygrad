# THE 2026-10-04 WIDENING. Every artifact here, and the exact command that made it.
#
# env -u PYTHONPATH is REQUIRED (it contaminates a control) and LC_ALL=C is REQUIRED (a
# locale-colated sort fabricates diffs). DEV=NULL is the rebase gate's own setting; the
# differ OVERRIDES it with its `--dev` value, default CPU, and prints the device set on
# every report so a device mismatch is visible rather than inferred.
#
# E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py
# ALL OF IT AT ONCE: sh .agents/slop/graphcmp-run.sh
#
# SUBSTRATE AT CAPTURE TIME: tinybendygrad/uop/ops.bend
#   sha256 496f16076418b8b32fa4c915326e0163bcfdec40b7b1a7f05a7ebcb20bb8baf3
# It STOPPED COMPILING MID-SESSION (another unit, `UOp.const_factor.mul` at ops.bend:7028)
# and every artifact here was RE-CAPTURED once it came back, at the digest above. The
# interruption is recorded because it is the reason one command is a separate file: see the
# "CONCURRENCY" note at the end.
#
# ---------------------------------------------------------------------------
# THE ARTIFACT. ONE command, ONE argument, ONE verdict line, WITH ITS DENOMINATOR.
# ---------------------------------------------------------------------------
# E diff --graph NAME
#
#   NAME         nodes/side  ops  depths  live ledger  VERDICT
#   matmul          18/18     7     1       none        AGREE
#   reduce           7/7      6     1       none        AGREE
#   buffer           5/5      4     1       z=1/1       AGREE
#   sink             2/2      2     1       none        AGREE
#   range            2/2      2     2       none        AGREE
#   rangeflat        2/2      2     1       none        AGREE
#   cast             6/6      5     1       none        AGREE
#   special          2/2      2     1       none        AGREE
#   binblob         19/19     8     1       y=1/1       AGREE
#   ------------------------------------------------------------------
#   TOTAL          63/63    13 distinct ops: ALLOC BINARY BUFFER CAST CONST MUL PERMUTE
#                                 RANGE REDUCE RESHAPE SINK SPECIAL STACK
#
# Fields: 8 on the wire, 6 IN THE EQUALITY DECISION (dtype shape depth tag arg src).
# `id` is reporting-only by R1 -- the two arenas number differently, so a differ keyed on
# it compares nothing. Each graph prints `fields=6 field-records=<nodes*6>`, so an AGREE
# on 2 nodes (12 field-records) cannot be read as an AGREE on 19 (114).
# Files: D1-graph-*.txt
#
# `range` and `rangeflat` are a PAIR and are only meaningful as one: same op, same dtype,
# same `()` shape, same `N` tag, and they differ in exactly two of the eight fields.
# Before them EVERY node of EVERY graph had `depth=i0` on BOTH sides, so R5 had never been
# asked a question -- and the first graph to ask it found an off-by-one (see LIMITS #1).
# ---------------------------------------------------------------------------
# THE REST, in the order the runner does it. rc=0 unless the line says otherwise.
# ---------------------------------------------------------------------------
D0  E selfcheck                                     D0-selfcheck.txt
D0  E2 .venv/bin/python .agents/slop/graphcmp-oracle.py    D0-coverage-census.txt
      Per graph: nodes on BOTH sides, distinct ops, distinct arg ATOM LETTERS, distinct
      shape texts, distinct depth values, and which ledger markers are LIVE. It emits both
      sides so an op or atom the py side never produces shows up as a per-side difference
      instead of being absorbed into an AGREE.
      MEASURED: 9 graphs, 63 nodes/side, 13 of 77 ops, 8 of 16 atom letters + 3 of 10
      composite arg-form prefixes reached, 0 unmapped letters, 2 of 8 ledger markers live.
D1  E diff --graph NAME   (x9)                      D1-graph-*.txt
D2  E emit py|bend --graph NAME; `cmp` the two      D2-bytediff.txt + D2-canon-*.txt
      MEASURED: matmul/range/cast/binblob BYTE-IDENTICAL. The cheapest check in the file
      and the one that fails first when an atom letter moves.
D3  E control --graph NAME                         D3-control-*.txt
      MEASURED: CONTROL VERDICT OK on matmul and on binblob -- each side against ITSELF.
D4  E cross --graph range                          D4-cross-range.txt
      MEASURED: CROSS VERDICT OK -- it disagrees with a DIFFERENT graph.
D5  E diff --graph matmul --plant P   (x6)          D5-plant-*.txt   ALL rc=1 (DISAGREE)
      The planted node is named. MEASURED, `--plant srcswap`:
        MISMATCH MUL  py#16 vs bend#16  (no shared core; paired one-to-one ...)
            src  py=['bd57da94', '2b7d1a7e'] bend=['2b7d1a7e', 'bd57da94']
D6  E diff --graph matmul --plant srcswap          D6-srcswap-ordered.txt  rc=1 DISAGREE
    E diff --graph matmul --plant srcswap --equiv  D6-srcswap-equiv.txt    rc=0 AGREE
      ONE fixture, TWO answers, both results. 18 nodes / 108 field-records either way.
D7  E conf                                          D7-conf.txt
      CONFLATION VERDICT: ALL THREE DISTINGUISHED.
D8  E dbg --levels 0,1,2                            D8-dbg-012.txt
    E dbg --levels 0,3                              D8-dbg-03.txt
      DEBUG VERDICT: the levels are DISTINGUISHABLE and the graph was fixed.
D8b E .venv/bin/python .agents/slop/graphcmp-dbg-oracle.py   D8b-cpython-dbg1-reachability.txt
      MEASURED: CPython's own `DEBUG >= 1` memory line fired on 0 of 8 real graphs. So `dbg`
      is PORT-AT-LEVEL-A vs PORT-AT-LEVEL-B and not a port-vs-CPython comparison, and says
      so. A 0 of 8 is a statement about 8 fixtures.
D9  E diff --graph binblob, twice; `cmp`            D9-stability.txt
      MEASURED: 2 runs BYTE-IDENTICAL. A differ whose output moves on its own cannot be
      used to detect that the PORT moved.
D10 E emit --side bend --bend-probe .agents/slop/graphcmp-empty.bend
      MEASURED: rc=1, "0 rows after 5 attempts -- a FAILURE, not a verdict". The guard is
      SEEN TO FIRE. Before this session the probe flag never reached the `emit` path, so
      the one command whose job is to emit could not demonstrate the guard (LIMITS #4).

# ---------------------------------------------------------------------------
# CONCURRENCY. `tinybendygrad/uop/ops.bend` is being edited by another unit and went
# through at least four digests during this session: d777ae30 -> 8451d2c0 -> 3ea82892 ->
# fefb7e21 -> fbf2de82 (DID NOT COMPILE) -> 496f1607. Two consequences, both recorded rather
# than worked around:
#   * one failure named a def that is NOT in this unit's files -- `def UOp.huo.go` appeared
#     TWICE, a duplicate declaration. Reported, not edited: it is not my file.
#   * `uop/ops.bend:7028 UOp.const_factor.mul` stopped compiling and blocked the coverage
#     census for one pass. The census was re-run after the tree came back; the artifacts
#     above are all from the final compiling tree at the digest quoted at the top.