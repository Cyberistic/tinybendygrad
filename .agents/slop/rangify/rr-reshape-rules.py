#!/usr/bin/env python3
"""rr-reshape-rules.py -- **WHICH RULES** TURN THE AFFINE EXPRESSION INTO WHAT
UPSTREAM'S RANGE MAP HOLDS.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/rr-reshape-rules.py

WHY THIS FILE
-------------
`rr-reshape.py` MEASURED THAT `_apply_reshape`'s OUTPUT CHANGES: THE
UNSIMPLIFIED EXPRESSION IS `FLOORMOD(ADD(...), CONST)` AND THE SIMPLIFIED ONE
IS `ADD(MUL(RANGE,CONST), RANGE)`. **⇒ AND "THE REWRITER CHANGES IT" IS NOT A
WORK LIST.** THIS FILE NAMES **EVERY RULE THAT FIRES**, BY SPYING ON
UPSTREAM's OWN `graph_rewrite` AND WRAPPING THE MATCHER, **⇒ SO THE PORT's WORK
LIST IS UPSTREAM's OWN RULE LIST AND NOT A GUESS.**

THE COST: **ONE CPYTHON PROCESS, ~2 s.**
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def load_oracle():
    spec = importlib.util.spec_from_file_location("rr_oracle", HERE / "rr-oracle.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.node_str


def main() -> int:
    from tinygrad import Tensor
    import tinygrad.schedule.indexing as IX

    node_str = load_oracle()
    steps = []

    class SpyMatcher:
        """A MATCHER THAT REPORTS EVERY REWRITE IT MAKES, **AND WHICH RULE
        MADE IT** -- `UPat.location` IS `get_location()`, **⇒ SO THE WORK LIST
        IS UPSTREAM's OWN FILE AND LINE.**"""

        def __init__(self, inner):
            self.inner = inner

        def rewrite(self, uop, *a, **kw):
            out = self.inner.rewrite(uop, *a, **kw)
            if out is not None and out is not uop:
                steps.append((node_str(uop), node_str(out), self.which(uop, *a, **kw)))
            return out

        def which(self, uop, *a, **kw):
            """THE RULE THAT FIRED: THE FIRST ENTRY OF `pdict` WHOSE MATCH
            RETURNS A NODE THAT IS NOT THE INPUT -- **THE SAME LOOP
            `PatternMatcher.rewrite` WALKS** (`ops.py:1600-1606`)."""
            ler = {u.op for u in uop.src}
            for p, match, early_reject in self.inner.pdict.get(uop.op, []):
                if not early_reject.issubset(ler):
                    continue
                try:
                    ret = match(uop, *a, **kw)
                except Exception:
                    continue
                if ret is not None and ret is not uop:
                    return "%s:%s  %s" % (
                        getattr(p.location, "filename", p.location),
                        getattr(p.location, "lineno", "?"),
                        (p.name or getattr(p, "__repr__", lambda: "")()))
            return "THE RULE WAS NOT FOUND"

        def __getattr__(self, k):
            return getattr(self.inner, k)

    orig_gwr = IX.graph_rewrite

    def spy_gwr(src, matcher, ctx=None, **kw):
        if kw.get("name") == "reshape":
            return orig_gwr(src, SpyMatcher(matcher), ctx=ctx, **kw)
        return orig_gwr(src, matcher, ctx=ctx, **kw)

    IX.graph_rewrite = spy_gwr

    t = Tensor.empty(4, 5).realize()
    t.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
    t.schedule_linear()

    if not steps:
        print("# NO REWRITE STEP WAS SEEN -- A REFUSAL IS A RESULT")
        return 1

    print("# THE REWRITE STEPS: %d" % len(steps))
    for i, (before, after, rule) in enumerate(steps):
        print("%3d  %-46s -> %-30s  %s" % (i, before, after, rule))
    print()
    print("# THE DISTINCT RULES -- **THE WORK LIST**")
    seen = []
    for _, _, rule in steps:
        if rule not in seen: seen.append(rule)
    for i, r in enumerate(seen): print("%2d  %s" % (i, r))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
