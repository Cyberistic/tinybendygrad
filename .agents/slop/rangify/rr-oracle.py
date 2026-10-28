#!/usr/bin/env python3
"""rr-oracle.py -- THE CPYTHON ORACLE FOR THE PORT's `run_rangeify` DRIVER.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/rr-oracle.py

WHAT THIS FILE IS
-----------------
`tinygrad/schedule/indexing.py:183` is upstream's `run_rangeify`, and it is the
ONE stage of `get_kernel_graph` (`tinygrad/schedule/rangeify.py:341-376`) that
the port's own engine marks `Stg{0, Nil{}}` -- "run_rangeify -- NOT PORTED"
(`tinybendygrad/schedule/rangeify.bend:2810`).

⇒ SO THIS FILE SPIES ON UPSTREAM's OWN CALL to `run_rangeify`, ON THE SAME REAL
PROGRAM the port's own `realize.bend` builds (`(4,5) = (4,3) @ (3,5)`), AND
PRINTS:

  * `rr_py_in`  -- the 23-node graph `run_rangeify` RECEIVES. MEASURED, that is
                   upstream's `prepare_rangeify` OUTPUT and it is the graph the
                   PORT's OWN `realize.bend` reproduces (`.agents/slop/realize/
                   cmp.py`: `C0 node count port=23 cpython=23`).
  * `rr_py_out` -- the graph `run_rangeify` RETURNS. **THIS IS THE TARGET.**
                   It is upstream's stage-1 output, and the port's driver has to
                   produce it.
  * `rr_py_realize` -- CPython's OWN `IndexingContext.realize_map` after the
                   run: node -> `None` (realized) or a list of realized axes.
  * `rr_py_range`   -- CPython's OWN `IndexingContext.range_map`: node ->
                   (input ranges, output ranges), each range rendered by its
                   axis id.
  * `rr_py_shapes`  -- every node's SHAPE and `marg`, because `run_rangeify`
                   reads `x.shape` and `x.marg` and the port's driver needs the
                   same two facts.

THE SPELLING is the PORT's OWN dump spelling (`op:argkey:srcops`, joined by
`;`), the same one `.agents/slop/engine/eng-oracle.py` uses, so the two
oracles and the port's `rz_dump` are byte-comparable.

THE COST: **ONE CPYTHON PROCESS, ~2 s.**
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def const_key(v):
    """THE PORT's `rz_constkey` (`schedule/realize.bend:344`): a CONST's arg in
    THIS upstream is a BARE VALUE (MEASURED, `UOp.const(20).arg` is the int
    `20`), so the key is `cother` for EVERY CONST."""
    if isinstance(v, tuple) and len(v) == 3 and v[1] == "CONST":
        return "cother"
    return "cother"


def arg_key(u):
    """THE PORT's `rz_argkey` (`schedule/realize.bend:353`): `none` for a node
    with no arg, the CONST key for a CONST, `other` for everything else."""
    if u.op.name == "CONST":
        return const_key(u.arg)
    if u.arg is None or u.arg == ():
        return "none"
    return "other"


def node_str(u):
    """THE PORT's `rz_node_str` (`schedule/realize.bend:368`)."""
    return "%s:%s:%s" % (u.op.name, arg_key(u), ",".join(s.op.name for s in u.src))


def dump(root):
    """THE PORT's `rz_dump` (`schedule/realize.bend:381`): A DFS FROM THE RESULT
    ROOT, EACH NODE ONCE, JOINED BY `;`."""
    out = []
    seen = set()
    todo = [root]
    while todo:
        u = todo.pop(0)
        if u in seen:
            continue
        seen.add(u)
        out.append(node_str(u))
        todo = list(u.src) + todo
    return ";".join(out)


def render_range(r):
    """A RANGE's axis id. MEASURED, upstream's RANGE arg is `(axis_type,
    axis_id)` (`tinygrad/uop/ops.py:624`: `arg=(axis_type, axis_id)`) and
    `UOp.axis_id` is `self.arg[1:]` (`ops.py:486`). A node that is NOT a RANGE
    is an AFFINE EXPRESSION -- upstream's `_apply_reshape` (`indexing.py:155`)
    makes the RESHAPE's input ranges affine -- so it is rendered in FULL, by
    the same `op:argkey:srcops` spelling everything else uses."""
    if getattr(r, "op", None) is None or r.op.name != "RANGE":
        return "<%s>" % node_str(r)
    ids = r.arg[1:]
    if isinstance(ids, (list, tuple)):
        return "R" + ",".join(str(x) for x in ids)
    return "R" + str(ids)


def main() -> int:
    import tinygrad.schedule as S
    import tinygrad.schedule.rangeify as R
    import tinygrad.schedule.indexing as IX
    from tinygrad import Tensor

    captured = {}

    # --- THE SPY ON `run_rangeify` ITSELF. `rangeify.py:344` calls it as a
    # MODULE GLOBAL, so patching the module attribute is what intercepts it.
    orig_rr = R.run_rangeify

    def spy_rr(tsink, debug=False):
        captured["in"] = tsink
        # MEASURED, `t.schedule_linear()` calls `run_rangeify` TWICE -- once on
        # a sink with NO STORE (so `pm_generate_realize_map` fires nothing) and
        # once on the 23-node sink this file is about. The captures below are
        # therefore CLEARED per call, or they would carry the FIRST run's
        # (empty) realize map and measure nothing.
        captured.pop("ctx", None)
        captured.pop("realize", None)
        captured.pop("nonremovable", None)
        out = orig_rr(tsink, debug)
        captured["out"] = out
        return out

    R.run_rangeify = spy_rr
    S.run_rangeify = spy_rr

    # --- THE SPY ON THE CONTEXT. `run_rangeify` calls
    # `graph_rewrite(tsink, pm_generate_realize_map, ctx=rctx, name="get
    # realize")` (indexing.py:191) and then mutates `rctx` in place, so
    # capturing the ctx OBJECT and reading it AFTER the run gives CPython's own
    # realize_map and range_map.
    orig_gwr = IX.graph_rewrite

    def spy_gwr(src, matcher, ctx=None, **kw):
        out = orig_gwr(src, matcher, ctx=ctx, **kw)
        if isinstance(ctx, IX.IndexingContext):
            captured["ctx"] = ctx
            # THE REALIZE MAP **BEFORE** `pm_apply_rangeify` runs. Upstream's
            # `create_bufferize_and_index_srcs` DELETES the STORE from the map
            # when it turns it into an END (`del ctx.realize_map[s]`,
            # indexing.py:88), so the map read AFTER the run is EMPTY and would
            # measure nothing. This is the map as `pm_generate_realize_map`
            # left it, which is the thing the port's driver has to reproduce.
            if "realize" not in captured:
                captured["realize"] = dict(ctx.realize_map)
                captured["nonremovable"] = dict(ctx.non_removable)
        return out

    IX.graph_rewrite = spy_gwr

    t = Tensor.empty(4, 5).realize()
    t.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
    t.schedule_linear()

    if "out" not in captured:
        print("# THE SPY DID NOT FIRE -- A REFUSAL IS A RESULT")
        return 1

    i, o = captured["in"], captured["out"]
    print("rr_py_in_nodes=%d" % len(list(i.toposort())))
    print("rr_py_in=%s" % dump(i))
    print("rr_py_out_nodes=%d" % len(list(o.toposort())))
    print("rr_py_out=%s" % dump(o))
    print("# the output census: %s" % sorted(set(u.op.name for u in o.toposort())))

    # --- THE CONTEXT. `realize_map` maps a UOp to `None` (realized) or a list
    # of realized axes; `range_map` maps a UOp to (input ranges, output ranges).
    ctx = captured.get("ctx")
    if ctx is None:
        print("# NO CONTEXT CAPTURED -- A REFUSAL IS A RESULT")
        return 1

    rm = []
    src_rm = captured.get("realize", {})
    for n in sorted(src_rm, key=lambda x: (x.op.name, node_str(x))):
        v = src_rm[n]
        rm.append("%s:%s" % (node_str(n), "none" if v is None else ",".join(str(a) for a in v)))
    print("rr_py_realize_n=%d" % len(rm))
    print("rr_py_realize=%s" % ";".join(rm))

    rg = []
    # THE KEY IS THE NODE'S INDEX IN THE TOPOSORT, NOT ITS DUMP STRING. MEASURED:
    # the dump string cannot tell the three RESHAPEs apart -- they are all
    # `RESHAPE:none:PARAM,STACK` -- and a census keyed by a string that is not
    # unique is a census of names. The toposort index is unique.
    order = {u: k for k, u in enumerate(i.toposort())}
    for n in sorted(ctx.range_map, key=lambda x: order.get(x, 1 << 30)):
        ins, outs = ctx.range_map[n]
        rg.append("#%d %s:[%s]->[%s]" % (order.get(n, -1), node_str(n),
                                         ",".join(render_range(r) for r in ins),
                                         ",".join(render_range(r) for r in outs)))
    print("rr_py_range_n=%d" % len(rg))
    print("rr_py_range=%s" % ";".join(rg))

    # THE TOPOSORT ORDER, because the port's own toposort is a PRE-ORDER DFS and
    # upstream's is a POST-ORDER one, and the range-id allocation follows the
    # visit order. The port does NOT have to reproduce upstream's ORDER -- the
    # comparison is over the DUMP, and a RANGE's dump key is `other` -- but the
    # ORDER is what the port's own driver must be able to reproduce, so it is
    # printed.
    print("rr_py_order=%s" % ";".join("%d:%s" % (k, node_str(u)) for k, u in enumerate(i.toposort())))

    nr = sorted(ctx.non_removable, key=lambda x: (x.op.name, node_str(x)))
    print("rr_py_nonremovable_n=%d" % len(nr))
    print("rr_py_nonremovable=%s" % ";".join(node_str(n) for n in nr))

    # --- THE SHAPES AND THE `marg`s. `run_rangeify` reads `x.shape` (for the
    # new ranges' extents and for `broadcast_axes`) and `x.marg` (for
    # `apply_movement_op`), so the port's driver needs the same two facts.
    sh = []
    for n in i.toposort():
        try:
            shape = tuple(str(s) for s in n.shape)
        except Exception as e:  # a shape the port cannot spell is a refusal
            shape = ("ERR:" + type(e).__name__,)
        try:
            marg = repr(n.marg)
        except Exception as e:
            marg = "ERR:" + type(e).__name__
        sh.append("%s shape=%s marg=%s" % (node_str(n), ",".join(shape), marg))
    print("rr_py_shapes=%s" % ";".join(sh))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
