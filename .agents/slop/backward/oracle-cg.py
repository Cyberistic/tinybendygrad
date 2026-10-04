"""STEP 1 ORACLE -- `compute_gradient`'s walk, measured by CALLING CPython.

THE FIXTURE is a DAG, not a tree, on purpose.  `compute_gradient` has two branches
that a TREE cannot reach at all:

  * gradient.py:134-138  `if k in grads: grads[k] = grads[k] + v  else: grads[k] = v`
    -- the ACCUMULATE.  Only a node with TWO parents is written twice.
  * gradient.py:129-130  `if v is None: continue`, and gradient.py:120
    `if t0 not in grads ... continue` -- the SKIP, which every leaf hits.

    a = BUFFER(0)
    b = BUFFER(1)   c = BUFFER(2)
    p = MUL(a, b)        <- one parent of a
    q = ADD(a, c)        <- the OTHER parent of a, so a is written twice
    r = ADD(p, q)        <- root, seed CONST 1.0

`_deepwalk` keeps only the nodes on a path TO a target, so `c` is in the walk and is
in `targets`; every node in the walk is visited in reverse toposort order.

THE ORACLE PRINTS SIGNATURES (node count, then root op/root nsrc/src op sequence) and
COUNTS -- never a name and never a boolean.  The gate's `py=` values are this file's
output, transcribed BY SCRIPT, never by hand.
"""
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def sig(u):
    ts = u.toposort()
    return "%d %s" % (len(ts), " ".join("%s/%d" % (x.op.name, len(x.src)) for x in ts))


def build1():
    """The DAG.  Pins the ACCUMULATE (gradient.py:134-138)."""
    a = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))
    b = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.float32))
    c = UOp(Ops.BUFFER, arg=ParamArg(2, dtypes.float32))
    p = UOp(Ops.MUL, src=(a, b))
    q = UOp(Ops.ADD, src=(a, c))
    return a, b, c, p, q, UOp(Ops.ADD, src=(p, q))


def build2():
    """The EXPAND.  Pins the HOLE (gradient.py:130) and the SKIP (:120).

    `EXPAND` answers `(ctx, None)` -- gradient.py:86 -- so its second src never
    receives a gradient.  That src is ON the target path (it is `ADD(a,d)` and `a` is
    a target) so it IS in the walk, and it is NOT in `grads` when the walk reaches it,
    which is gradient.py:120's `continue` firing for real rather than by construction.
    """
    a = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))
    b = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.float32))
    d = UOp(Ops.BUFFER, arg=ParamArg(2, dtypes.float32))
    f = UOp(Ops.BUFFER, arg=ParamArg(3, dtypes.float32))
    c = UOp(Ops.ADD, src=(a, d))
    p = UOp(Ops.MUL, src=(a, b))
    e = UOp(Ops.EXPAND, src=(p, c))
    return a, b, d, f, c, p, e, UOp(Ops.ADD, src=(e, f))


def osig(u):
    """A TOPOSORT-ORDER-INSENSITIVE signature: node count, then the root op, then the
    src ops SORTED.  The port's `O.UOp.toposort` visits a different order from
    CPython's on the same graph (measured: CPython prints `BUFFER/0 CONST/0 CAST/1
    MUL/2` where the port prints `CONST/0 CAST/1 BUFFER/0 MUL/2`), so an ordered
    comparison would report a disagreement that is not one.  The ORDER is printed
    separately by `oracle_osig_order_*` rather than folded in silently."""
    ts = u.toposort()
    return "%d root=%s/%d srcs=%s" % (len(ts), u.op.name, len(u.src),
                                      " ".join(sorted("%s/%d" % (x.op.name, len(x.src)) for x in ts)))


def one(tag, root, targets, names):
    walk, itp = _deepwalk(root, targets)
    ts = root.toposort()
    print("oracle_%s_n_toposort=%d" % (tag, len(ts)))
    print("oracle_%s_walk=%s" % (tag, " ".join("%s/%d" % (x.op.name, len(x.src)) for x in walk)))
    print("oracle_%s_walk_n=%d" % (tag, len(walk)))
    print("oracle_%s_inpath=%s" % (tag, " ".join("1" if itp.get(x, False) else "0" for x in ts)))
    print("oracle_%s_n_inpath=%d" % (tag, sum(1 for x in ts if itp.get(x, False))))

    grads = compute_gradient(root, UOp.const(1.0, dtypes.float32), targets)
    print("oracle_%s_grads_n=%d" % (tag, len(grads)))
    for nm, t in names:
        g = grads.get(t)
        print("oracle_%s_grad_%s=%s" % (tag, nm, "NONE" if g is None else osig(g)))
    # the key set in INSERTION order, which is what the port's parallel-list table
    # reproduces: a walk in forward order leaves a different set AND a different order.
    print("oracle_%s_keys=%s" % (tag, " ".join("%s/%d" % (x.op.name, len(x.src)) for x in grads)))
    # THE SKIP COUNT, instrumented through `compute_gradient`'s OWN loop rather than a
    # second transcription of it: count the walk nodes that are not in grads when the
    # walk reaches them, and the rule answers that are all-holes.
    seen, skipped, holes = set(), 0, 0
    for t0 in reversed(walk):
        if t0 not in grads:
            skipped += 1
            continue
        lg = pm_gradient.rewrite(t0, ctx=grads[t0])
        if lg is None:
            continue
        holes += sum(1 for v in lg if v is None)
        seen.add(t0)
        for k, v in zip(t0.src, lg):
            if v is None:
                continue
            grads[k] = grads[k] + v if k in grads else v
    print("oracle_%s_skip_n=%d" % (tag, skipped))
    print("oracle_%s_hole_n=%d" % (tag, holes))


def main():
    a, b, c, p, q, r = build1()
    one("dag", r, {a, b, c}, (("a", a), ("b", b), ("c", c), ("p", p), ("q", q), ("r", r)))
    a2, b2, d2, f2, c2, p2, e2, r2 = build2()
    one("hole", r2, {a2, b2, d2},
        (("a", a2), ("b", b2), ("c", c2), ("d", d2), ("p", p2), ("e", e2), ("r", r2)))

    # the rule table on its own, the one-step comparison the census did
    lg = pm_gradient.rewrite(p, ctx=UOp.const(1.0, dtypes.float32))
    print("oracle_pmul=%s" % ("GSKIP" if lg is None else
                              "FIRED n=%d solid=%d" % (len(lg), sum(1 for g in lg if g is not None))))
    print("oracle_pmul0=%s" % sig(lg[0]))
    print("oracle_pmul1=%s" % sig(lg[1]))
    print("oracle_seed=%s" % sig(UOp.const(1.0, dtypes.float32)))
    # THE FORWARD-WALK COUNTERFACTUAL.  A walk in toposort order accumulates almost
    # nothing, because the seed sits only at the root and the root is visited FIRST.
    # Measured on the ORACLE side, so the port's row has a number that came from
    # CPython rather than from my reading of gradient.py:119.
    g2, skipped = {r: UOp.const(1.0, dtypes.float32)}, 0
    for t0 in r.toposort():
        if t0 not in g2:
            skipped += 1
            continue
        for k, v in zip(t0.src, pm_gradient.rewrite(t0, ctx=g2[t0])):
            if v is None:
                continue
            g2[k] = g2[k] + v if k in g2 else v
    print("oracle_fwdwalk_n=%d" % len(g2))
    print("oracle_fwdwalk_skipped=%d" % skipped)
    print("oracle_fwdwalk_a=%s" % ("NONE" if a not in g2 else osig(g2[a])))


main()
