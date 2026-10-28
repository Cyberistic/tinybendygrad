#!/usr/bin/env python3
"""probe2.py -- WHERE THE AFTER's src0 BECOMES THE BASE.

    env -u PYTHONPATH .venv/bin/python .agents/slop/realize/probe2.py

PRINTS UPSTREAM's OWN GRAPH AT EACH STAGE OF THE PIPELINE, so the port's driver
mirrors the STAGE that does the work instead of guessing which one it is.
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
    from tinygrad import Tensor

    t = Tensor.empty(4, 5).realize()
    val = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
    t.assign(val)
    print("# tensor uop after assign: %s" % brief(t.uop))

    # the sink `linear_with_vars` builds, by hand (same three lines)
    sink = t.uop.__class__.sink(t.uop)
    print("# SINK handed to transform_to_call:\n    %s" % dump(sink))

    call = S.transform_to_call(sink)
    print("# transform_to_call -> %s" % brief(call))
    print("#   body:\n    %s" % dump(call.body))

    fn = call.body
    fco = P.forward_call_outputs(fn)
    print("# forward_call_outputs:\n    %s" % dump(fco))

    import tinygrad.uop.ops as ops
    ts = ops.graph_rewrite(fco, P.pm_mops + P.pm_inline_calls + P.pm_disk_copy, name="inline calls")
    print("# after pm_mops+pm_inline_calls+pm_disk_copy:\n    %s" % dump(ts))

    ts2 = ops.graph_rewrite(ts, P.pm_mops + P.earliest_rewrites, bottom_up=True, name="earliest rewrites")
    print("# after earliest_rewrites:\n    %s" % dump(ts2))
    print("# nodes=%d" % len(list(ts2.toposort())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
