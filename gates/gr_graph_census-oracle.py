#!/usr/bin/env python3
"""gr_graph_census-oracle.py -- CPython's DEEP OP SEQUENCE for every graph-producing
`pm_gradient` rule the port implements.

    .venv/bin/python gates/gr_graph_census-oracle.py

THE SAME 18 ROWS `gates/gr_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's deep toposort sequence for each gradient a rule answers; this lane prints CPython's for
`pm_gradient.rewrite(node, ctx=...)` -- the REAL matcher, not a lambda called by hand -- so a
divergence is a SHAPE divergence and not a prose claim.

THE FIXTURE IS THE BEND LANE'S, NODE FOR NODE. `ctx` is `CONST 1.0`, the POW base `b` is
`CONST 3.0` and the exponent `e` is `CONST 4.0` -- DISTINCT, so an operand swap moves a row.
`gradient.bend`'s own `fix()` uses `CONST 1.0` for EVERY operand, which makes `e` and the `1`
the POW rule subtracts the SAME node and hides a swap; this lane does not. `UOp.const` hash-conses
here, so both lanes see the same interned nodes.

THE PRINTER IS THE DEEP TOPOSORT, NOT `Rng.sig`. `Rng.sig` prints only the root, its direct srcs
and the COUNT, and the COUNT is BLIND here: `gr_10`'s slot 0 prints the SAME
`15 Ops.MUL/2 Ops.CAST Ops.WHERE` on both sides because the port's extra `CAST(CONST 0.0)` and
its missing `MUL(e, POW)` cancel. One `toposort()` join shows the tree instead.
"""

from tinygrad.uop.ops import Ops, UOp, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import pm_gradient, compute_gradient, _deepwalk


def dsig(u):
    us = u.toposort()
    return f"{len(us)} " + " ".join(f"{x.op.name}/{len(x.src)}" for x in us) + " "


def sigs(r):
    return " | ".join(dsig(x) for x in r if x is not None)


def one(name, node, ctx):
    print(f"{name}={sigs(pm_gradient.rewrite(node, ctx=ctx))}")


# ---- the fixture: ONE intern pool, DISTINCT operands (mirror of the bend lane's `world()`) ----
c1 = UOp.const(1.0, dtypes.float32)          # ctx
c3 = UOp.const(3.0, dtypes.float32)          # POW base
c4 = UOp.const(4.0, dtypes.float32)          # POW exponent
ci = UOp.const(4)                            # a BARE weakint CONST
t_cast = UOp(Ops.CAST, src=(c1,), arg=dtypes.int32)      # src f32 == ctx -> IDENTITY
t_cast_r = UOp(Ops.CAST, src=(ci,), arg=dtypes.int32)    # src weakint -> REAL cast
t_recip = UOp(Ops.RECIPROCAL, src=(c3,))
t_sin = UOp(Ops.SIN, src=(c3,))
t_log2 = UOp(Ops.LOG2, src=(c3,))
t_exp2 = UOp(Ops.EXP2, src=(c3,))
t_sqrt = UOp(Ops.SQRT, src=(c3,))
t_trunc = UOp(Ops.TRUNC, src=(c3,))
t_add = UOp(Ops.ADD, src=(c3, c4))
t_pow = UOp(Ops.POW, src=(c3, c4))
t_max = UOp(Ops.MAX, src=(c3, c4))
t_mul = UOp(Ops.MUL, src=(c3, c4))
t_where = UOp(Ops.WHERE, src=(c1, c3, c4))
t_stage = UOp(Ops.STAGE, src=(c3,))
t_expand = UOp(Ops.EXPAND, src=(c3,))
t_sink = UOp.sink(c3, c4)
t_store = UOp(Ops.STORE, src=(c3, c4))
bA = UOp.new_buffer("PYTHON", 4, dtypes.float32)
t_after = UOp(Ops.AFTER, src=(bA, UOp(Ops.STORE, src=(bA, c3))))

one("gr_0", t_cast, c1)
one("gr_0_r", t_cast_r, c1)
one("gr_1", t_recip, c1)
one("gr_2", t_sin, c1)
one("gr_3", t_log2, c1)
one("gr_4", t_exp2, c1)
one("gr_5", t_sqrt, c1)
one("gr_6", t_trunc, c1)
one("gr_9", t_add, c1)
one("gr_10", t_pow, c1)
one("gr_11", t_max, c1)
one("gr_12", t_mul, c1)
one("gr_13", t_where, c1)
one("gr_16", t_stage, c1)
one("gr_18", t_expand, c1)
one("gr_26", t_sink, t_sink)
one("gr_29", t_after, c1)
one("gr_31", t_store, c1)

# ---- THE WALK: `compute_gradient`/`_deepwalk` on the DAG the port's own `dag()` builds ----
# `a`, `b`, `c` are three distinct BUFFERs, `p = MUL(a,b)`, `q = ADD(a,c)`, `r = ADD(p,q)`;
# `a` has TWO parents so `grads[a]` is written twice (the ACCUMULATE, gradient.py:134-138).
wa = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))
wb = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.float32))
wc = UOp(Ops.BUFFER, arg=ParamArg(2, dtypes.float32))
wp = UOp(Ops.MUL, src=(wa, wb))
wq = UOp(Ops.ADD, src=(wa, wc))
wr = UOp(Ops.ADD, src=(wp, wq))
wt = {wa, wb, wc}
wwalk, witp = _deepwalk(wr, wt)
wgrads = compute_gradient(wr, UOp.const(1.0, dtypes.float32), wt)


def groot(t):
    g = wgrads.get(t)
    return "NONE" if g is None else f"{len(g.toposort())} root={g.op.name}/{len(g.src)}"


print(f"walk_sig={' '.join(f'{x.op.name}/{len(x.src)}' for x in wwalk)}")
print(f"walk_inpath={' '.join('1' if witp.get(x, False) else '0' for x in wr.toposort())}")
print(f"walk_keys={' '.join(f'{x.op.name}/{len(x.src)}' for x in wgrads)}")
print(f"walk_grad_a={groot(wa)}")
print(f"walk_grad_b={groot(wb)}")
print(f"walk_grad_c={groot(wc)}")
print(f"walk_grad_p={groot(wp)}")
print(f"walk_grad_q={groot(wq)}")
print(f"walk_grad_r={groot(wr)}")
print(f"walk_walk_n={len(wwalk)}")
print(f"walk_grads_n={len(wgrads)}")
# The skip/hole counters are `compute_gradient`'s OWN `continue`s; CPython does not expose
# them, so they are re-run exactly as `.agents/slop/backward/oracle-cg.py:94-108` does.
_skipped, _holes = 0, 0
_g2 = dict(wgrads)
for _t0 in reversed(wwalk):
    if _t0 not in _g2:
        _skipped += 1
        continue
    _lg = pm_gradient.rewrite(_t0, ctx=_g2[_t0])
    if _lg is None:
        continue
    _holes += sum(1 for _v in _lg if _v is None)
    for _k, _v in zip(_t0.src, _lg):
        if _v is None:
            continue
        _g2[_k] = _g2[_k] + _v if _k in _g2 else _v
print(f"walk_skip_n={_skipped}")
print(f"walk_hole_n={_holes}")
print(f"walk_n_inpath={sum(1 for x in wr.toposort() if witp.get(x, False))}")
