#!/usr/bin/env python3
"""gkg-oracle.py -- CPython's answer for the ENGINE rows `tinybendygrad/schedule/rangeify.bend`
prints about `get_kernel_graph` (`tinygrad/schedule/rangeify.py:341-376`).

WHY THIS FILE EXISTS. `rangeify.bend` prints 159 rows and NO GATE DIFFED ANY OF THEM against
CPython -- `gates/rng_graph_census-gate.py` and friends compare CENSUSES (how many copies of
a rule), not answers. The `eng_*` rows are the seven stages of `get_kernel_graph` driving two
fixtures, i.e. the pipeline itself, and they were a reading of the port's own behaviour.

WHAT IS COMPARED, AND WHAT IS NOT. The port drives SEVEN stages and its own `eng_stages()`
declares which TABLE NUMBERS go in each. Stage 2 lists `[0, 1]` -- `pm_const_buffer_folding`
and `pm_remove_bufferize` -- and NOT `symbolic` or `pm_reduce_simplify`, because neither has a
port (`rg 'def symbolic\\b' tinybendygrad/` answers nothing). So this oracle runs the SAME
SUBSET, and the rows therefore compare the ENGINE and the EIGHT PORTED TABLES; they do not
compare the two absent matchers, and they cannot.

THE PORT DRIVES EVERY STAGE AS A PRE-ORDER FIXED POINT (`eng_apply` inside `eng_fix`), which
is upstream's `bottom_up=True` (`ops.py:1891` puts the matcher in `self.bpm`). So every stage
here is `graph_rewrite(x, pm, ctx, bottom_up=True)`. THAT IS A CLAIM ABOUT THE PORT AND IT IS
FALSIFIABLE: run the same stages with `bottom_up=False` and see whether the dumps move.
`--both` prints the second set so the difference can be read instead of guessed.

TWO ROWS PER STAGE IN THE PORT, AND ONLY ONE IS HERE. `eng_<tag>_s<n>` is the graph;
`eng_<tag>_r<n>` is `<moved>;<kept>` about the engine's own memoisation map, and CPython has no
map to count, so `gates/gkg-gate.py` declares those PORT-ONLY rather than inventing a number.
"""
import itertools
import sys

from tinygrad.dtype import AddrSpace, Invalid, dtypes
from tinygrad.schedule.rangeify import (LimitBufsContext, pm_add_buffers,
                                        pm_add_param_range_tags, pm_const_buffer_folding,
                                        pm_limit_bufs, pm_no_indexing_calls, pm_no_views,
                                        pm_remove_bufferize, split_kernels)
from tinygrad.uop.ops import Ops, UOp, graph_rewrite

# The port's `eng_stages()`, table for table. Stage 0 is `run_rangeify`, which the port does
# NOT run (the fixtures arrive rangeified) so it is the identity here too.
STAGES = (
    None,
    pm_const_buffer_folding + pm_remove_bufferize,
    pm_limit_bufs,
    pm_add_buffers + pm_add_param_range_tags,
    pm_no_indexing_calls,
    split_kernels,
    pm_no_views,
)


def argkey(u: UOp) -> str:
    a = u.arg
    if a is None: return "none"
    if a is Invalid: return "cinvalid"
    if isinstance(a, int): return f"c:{(a >> 32) & 0xFFFFFFFF}:{a & 0xFFFFFFFF}"
    return "other"


def dump(root: UOp) -> str:
    # BFS from the root, each node once, children APPENDED in src order -- the port's
    # `eng_dump.push` is `t ++ srcs`, so its todo is a queue and not a stack. The arena keeps
    # the nodes a rule replaced, so a dump of the whole arena would show both graphs.
    out, seen, todo = [], set(), [root]
    while todo:
        n = todo.pop(0)
        if n in seen: continue
        seen.add(n)
        out.append(f"{n.op.name}:{argkey(n)}:{','.join(s.op.name for s in n.src)}")
        todo = todo + list(n.src)
    return ";".join(out)


# ---- the two fixtures, src order identical to the port's `efx_a`/`efx_b` ----
def efx_a() -> UOp:
    c0, c1 = UOp.const(0), UOp.const(1)
    ci = UOp(Ops.CONST, arg=Invalid)
    n0 = UOp(Ops.NOOP, src=())
    e0 = UOp(Ops.END, src=(n0,))
    a0 = UOp(Ops.AFTER, src=(c0,))
    ixc = UOp(Ops.INDEX, src=(c0,))
    mst = UOp(Ops.MSTACK, src=(c0,))
    ixm = UOp(Ops.INDEX, src=(mst, c0))
    rs = UOp(Ops.RESHAPE, src=(a0, c0))
    cli = UOp(Ops.CALL, src=(ixc, rs))
    sts = UOp(Ops.STORE, src=(a0, a0))
    sti = UOp(Ops.STORE, src=(a0, ci))
    afn = UOp(Ops.AFTER, src=(a0, e0))
    return UOp(Ops.SINK, src=(afn, cli, sts, sti, ixm))


def efx_b() -> UOp:
    c1 = UOp.const(1)
    ci = UOp(Ops.CONST, arg=Invalid)
    n0 = UOp(Ops.NOOP, src=())
    e0 = UOp(Ops.END, src=(n0,))
    e1 = UOp(Ops.END, src=(e0,))
    a1 = UOp(Ops.AFTER, src=(c1,))
    ix1 = UOp(Ops.INDEX, src=(c1,))
    ix2 = UOp(Ops.INDEX, src=(ix1,))
    mst = UOp(Ops.MSTACK, src=(c1,))
    ixm = UOp(Ops.INDEX, src=(mst, c1))
    st1 = UOp(Ops.STORE, src=(a1, a1))
    si1 = UOp(Ops.STORE, src=(a1, ci))
    af1 = UOp(Ops.AFTER, src=(a1, e0))
    return UOp(Ops.SINK, src=(af1, e1, ix2, st1, si1, ixm))


def drive(root: UOp, bottom_up: bool) -> list[str]:
    out = [f"__in={dump(root)}"]
    x = root
    for n, pm in enumerate(STAGES):
        if pm is None:
            out.append(f"__s{n}={dump(x)}")
            continue
        ctx = None
        if n == 2:
            next_range = max([x.axis_id[0] for x in x.toposort() if x.op is Ops.RANGE] + [-1]) + 1
            ctx = LimitBufsContext(range_idx=itertools.count(next_range))
        elif n == 3:
            slots = [v.arg.slot for v in x.toposort() if v.op is Ops.ALLOC]
            ctx = itertools.count(max([-1] + slots) + 1)
        x = graph_rewrite(x, pm, ctx=ctx, bottom_up=bottom_up)
        out.append(f"__s{n}={dump(x)}")
    return out


def rows(bottom_up: bool = True) -> dict[str, str]:
    r = {}
    for tag, f in (("a", efx_a), ("b", efx_b)):
        for line in drive(f(), bottom_up):
            k, v = line.split("=", 1)
            r[f"eng_{tag}{'_in' if k == '__in' else '_s' + k[3:]}"] = v
    return r


def main() -> None:
    tag = "_bu" if "--both" in sys.argv else ""
    for k, v in rows(bottom_up="--both" not in sys.argv).items():
        print(f"{k}{tag}={v}")


if __name__ == "__main__":
    main()
