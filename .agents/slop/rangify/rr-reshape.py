#!/usr/bin/env python3
"""rr-reshape.py -- WHAT UPSTREAM's OWN `_apply_reshape` BUILDS, AND WHAT THE
`symbolic` REWRITER MAKES OF IT.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/rr-reshape.py

IT ANSWERS ONE QUESTION, AND IT IS THE ONE THAT **SIZES W-A**: **DOES THE
AFFINE EXPRESSION NEED THE `symbolic` REWRITER AT ALL, OR IS THE ARITHMETIC
ENOUGH?**

**⇒ AND IT ANSWERS IT BY ASKING UPSTREAM's OWN CODE, NOT BY REASONING ABOUT
IT**: THE PROBE WRAPS `IX._apply_reshape` AND, FOR EACH CALL, BUILDS THE
**UNSIMPLIFIED** EXPRESSION WITH UPSTREAM's OWN `UOp` API -- **THE SAME LINES
THE FUNCTION BUILDS, STOPPING BEFORE THE `graph_rewrite`** -- AND PRINTS BOTH.
**⇒ AND THE DIFFERENCE IS EXACTLY THE WORK THE `symbolic` REWRITER DOES ON THIS
PROGRAM, AND THE SPELLING IS THE PORT's OWN (`op:argkey:srcops`), SO THE PORT's
DRIVER CAN BE ASKED FOR THE SAME THING.**

THE COST: **ONE CPYTHON PROCESS, ~2 s.**
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent


def load_oracle():
    """THE ORACLE's OWN SPELLING (`node_str`), LOADED BY PATH -- NOT COPIED."""
    spec = importlib.util.spec_from_file_location("rr_oracle", HERE / "rr-oracle.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.node_str


def main() -> int:
    from tinygrad import Tensor
    from tinygrad.uop.ops import UOp
    import tinygrad.schedule.indexing as IX

    node_str = load_oracle()
    calls = []

    def unsimplified(in_shape, out_shape, urngs):
        """THE SAME LINES AS `indexing.py:150-160`, STOPPING BEFORE THE
        `graph_rewrite` -- SO THE DIFFERENCE IS THE REWRITER's WORK."""
        acc = 1
        axes_in = []
        for s, src in list(zip(out_shape, urngs.src))[::-1]:
            axes_in.append(acc * src)
            acc *= s
        combined_axes = UOp.const(0).usum(*axes_in)
        axes_out = []
        for s in in_shape[::-1]:
            axes_out.append(combined_axes % s)
            combined_axes //= s
        return UOp.sink(*axes_out[::-1])

    orig = IX._apply_reshape

    def spy(in_shape, out_shape, urngs):
        before = unsimplified(in_shape, out_shape, urngs)
        after = orig(in_shape, out_shape, urngs)
        calls.append((in_shape, out_shape, before, after))
        return after

    IX._apply_reshape = spy

    t = Tensor.empty(4, 5).realize()
    t.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
    t.schedule_linear()

    if not calls:
        print("# THE SPY DID NOT FIRE -- A REFUSAL IS A RESULT")
        return 1

    print("# _apply_reshape CALLS: %d" % len(calls))
    for i, (in_shape, out_shape, before, after) in enumerate(calls):
        b = [node_str(s) for s in before.src]
        a = [node_str(s) for s in after.src]
        print("=== CALL %d  in_shape=%s out_shape=%s" % (i, in_shape, out_shape))
        print("  UNSIMPLIFIED srcs: %s" % " | ".join(b))
        print("  SIMPLIFIED   srcs: %s" % " | ".join(a))
        # **NOT `before != after`: A `UOp`'s `!=` IS THE ELEMENTWISE NOT-EQUAL,
        # NOT IDENTITY, AND ASKING IT WHETHER TWO NODES ARE THE SAME NODE RAISES
        # `KeyError: dtypes.void`. THE COMPARISON IS **THE SPELLINGS**.**
        print("  THE SAME SPELLING? %s" % (b == a))
        if b != a:
            print("  BEFORE's FULL DUMP: %s" % ";".join(
                node_str(u) for u in before.toposort()))
            print("  AFTER's  FULL DUMP: %s" % ";".join(
                node_str(u) for u in after.toposort()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
