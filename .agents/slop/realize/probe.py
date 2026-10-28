#!/usr/bin/env python3
"""inspect.py -- WHAT EXACTLY IS THE ORACLE's 23-NODE GRAPH.

    env -u PYTHONPATH .venv/bin/python .agents/slop/realize/inspect.py

SPIES ON UPSTREAM's OWN CALL TO `get_kernel_graph` (the same spy as
`.agents/slop/engine/eng-oracle.py`) AND PRINTS THE ENGINE's INPUT NODE BY NODE,
WITH ARGS AND SHAPES, SO THE PORT's DRIVER CAN BE BUILT AGAINST THE REAL THING
INSTEAD OF AGAINST A READING OF IT.

NEVER A HAND-TYPED EXPECTATION: every line below is printed by CPython.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def brief(u, depth=0):
    if depth > 2:
        return "..."
    try:
        shp = u.shape
    except Exception:
        shp = None
    return "%s(arg=%r, shape=%r)" % (u.op.name, u.arg, shp)


def main() -> int:
    import tinygrad.schedule as S
    import tinygrad.schedule.rangeify as R
    from tinygrad import Tensor

    orig = R.get_kernel_graph
    seen = {}

    def spy(tsink):
        seen["in"] = tsink
        out = orig(tsink)
        seen["out"] = out
        return out

    R.get_kernel_graph = spy
    S.get_kernel_graph = spy

    t = Tensor.empty(4, 5).realize()
    print("# after realize: %s" % brief(t.uop))
    print("#   srcs: %s" % [brief(s) for s in t.uop.src])
    val = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
    print("# the matmul value: %s" % brief(val.uop))
    t.assign(val)
    print("# after assign: %s" % brief(t.uop))
    print("#   srcs: %s" % [brief(s) for s in t.uop.src])
    t.schedule_linear()

    if "in" not in seen:
        print("# THE SPY DID NOT FIRE -- A REFUSAL IS A RESULT")
        return 1

    for tag, root in (("ENGINE-IN", seen["in"]), ("ENGINE-OUT", seen["out"])):
        print("# ===== %s =====" % tag)
        for n, u in enumerate(root.toposort()):
            print("%02d %s" % (n, brief(u)))
            for k, s in enumerate(u.src):
                print("     src%d %s" % (k, brief(s)))
        print("# %s nodes=%d" % (tag, len(list(root.toposort()))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
