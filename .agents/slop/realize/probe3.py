#!/usr/bin/env python3
"""probe3.py -- THE SINK UPSTREAM's OWN `create_linear_with_vars` RECEIVES.

    env -u PYTHONPATH .venv/bin/python .agents/slop/realize/probe3.py

MONKEYPATCHES `tinygrad.schedule.create_linear_with_vars` TO PRINT ITS INPUT,
WHICH IS EXACTLY THE `sink` `Tensor.linear_with_vars` BUILT (tensor.py:209),
AND THEN PRINTS THE STAGES OF `prepare_rangeify` THAT TURN IT INTO THE
ENGINE's INPUT.

THE POINT: THE PORT's DRIVER MUST PRODUCE **THIS** SINK, NOT A HAND-BUILT ONE.
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent


def brief(u):
    return "%s(arg=%r)" % (u.op.name, u.arg)


def dump(root):
    out = []
    seen = set()
    todo = [root]
    while todo:
        u = todo.pop(0)
        if u in seen:
            continue
        seen.add(u)
        out.append("%s<-%s" % (brief(u), ",".join(s.op.name for s in u.src)))
        todo = list(u.src) + todo
    return "\n    ".join(out)


def main() -> int:
    import tinygrad.schedule as S
    import tinygrad.schedule.prepare as P
    import tinygrad.tensor as TP
    import tinygrad.uop.ops as ops
    from tinygrad import Tensor

    orig_clwv = TP.create_linear_with_vars
    captured = {}

    def spy(big_sink):
        captured["sink"] = big_sink
        return orig_clwv(big_sink)

    # `tensor.py:11` does `from tinygrad.schedule import create_linear_with_vars`,
    # so the name the CALL SITE uses is `tinygrad.tensor`'s -- patching the
    # schedule module's attribute does NOT reach it.
    TP.create_linear_with_vars = spy

    t = Tensor.empty(4, 5).realize()
    val = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
    t.assign(val)
    t.schedule_linear()

    if "sink" not in captured:
        print("# THE SPY DID NOT FIRE")
        return 1
    sink = captured["sink"]
    print("# THE SINK `create_linear_with_vars` RECEIVED (tensor.py:209):")
    print("    %s" % dump(sink))
    print("#    nodes=%d" % len(list(sink.toposort())))

    # the stages of prepare_rangeify, on a SINK OF AFTERs
    fco = P.forward_call_outputs(sink)
    print("# forward_call_outputs:\n    %s" % dump(fco))
    ts = ops.graph_rewrite(fco, P.pm_mops + P.pm_inline_calls + P.pm_disk_copy, name="inline calls")
    print("# after pm_mops+pm_inline_calls+pm_disk_copy:\n    %s" % dump(ts))
    ts2 = ops.graph_rewrite(ts, P.pm_mops + P.earliest_rewrites, bottom_up=True, name="earliest rewrites")
    print("# after earliest_rewrites:\n    %s" % dump(ts2))
    print("#    nodes=%d" % len(list(ts2.toposort())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
