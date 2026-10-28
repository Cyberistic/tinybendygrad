#!/usr/bin/env python3
"""rr-rules.py -- WHAT DOES UPSTREAM's `pm_apply_rangeify` DO TO EACH NODE?

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/rr-rules.py

WHY THIS FILE
-------------
`tinygrad/schedule/indexing.py:130-141` is upstream's `pm_apply_rangeify`, a
`PatternMatcher` with FIVE rules. `PatternMatcher.rewrite` (`ops.py`) walks
`self.pdict[uop.op]` IN DECLARATION ORDER and takes the FIRST rule whose
function returns a node that is not the input.

THE QUESTION THIS FILE ANSWERS: for a `RESHAPE`, does rule 4
(`GroupOp.All-{STAGE,INDEX}` -> `create_bufferize_and_index_based_on_ranges`)
or rule 5 (`GroupOp.Movement` -> `remove_movement_op_after_rangeify`) fire?
**THE ORDER IN THE SOURCE SAYS RULE 4, BUT THE MEASURED OUTPUT OF
`run_rangeify` HAS NO `RESHAPE` IN IT AT ALL**, AND A FILE THAT MEASURES BEATS
A FILE THAT GUESSES.

THE COST: **ONE CPYTHON PROCESS, ~2 s.**
"""
import sys


def main() -> int:
    import tinygrad.schedule as S
    import tinygrad.schedule.rangeify as R
    import tinygrad.schedule.indexing as IX
    from tinygrad import Tensor

    captured = {}
    orig_rr = R.run_rangeify

    def spy_rr(tsink, debug=False):
        captured.pop("ctx", None)
        captured["in"] = tsink
        out = orig_rr(tsink, debug)
        captured["out"] = out
        return out

    R.run_rangeify = spy_rr
    S.run_rangeify = spy_rr

    # THE SPY ON THE CONTEXT (`rr-oracle.py`'s SPY, verbatim in shape): upstream
    # MUTATES `rctx` IN PLACE, so the OBJECT READ AFTER THE RUN HOLDS THE MAPS.
    orig_gwr = IX.graph_rewrite

    def spy_gwr(src, matcher, ctx=None, **kw):
        out = orig_gwr(src, matcher, ctx=ctx, **kw)
        if isinstance(ctx, IX.IndexingContext):
            captured["ctx"] = ctx
        return out

    IX.graph_rewrite = spy_gwr

    a = Tensor.randn(4, 3).realize()
    b = Tensor.randn(3, 5).realize()
    c = (a @ b).realize()

    ctx = captured.get("ctx")
    if ctx is None:
        print("NO CONTEXT CAPTURED")
        return 1

    pm = IX.pm_apply_rangeify
    tsink = captured["in"]

    # THE ORDER `unified_rewrite` WALKS: THE REVERSED TOPOSORT.
    topo = tsink.toposort()
    print("=== THE NODE COUNT:", len(topo))
    for x in reversed(topo):
        pats = pm.pdict.get(x.op, [])
        res = pm.rewrite(x, ctx)
        names = []
        for entry in pats:
            p = entry[0]
            names.append(p.op.name if hasattr(p.op, "name") else str(p.op))
        tag = "None" if res is None else ("SAME" if res is x else res.op.name)
        print("%-10s in_range_map=%-5s rules=%-40s -> %s" % (
            x.op.name, str(x in ctx.range_map), ",".join(sorted(set(names)))[:40], tag))

    return 0


if __name__ == "__main__":
    sys.exit(main())
