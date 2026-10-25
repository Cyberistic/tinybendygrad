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

===============================================================================
THE LEAF, AND WHY IT IS `BUFFER(STACK())` AND NOT `BUFFER()`
===============================================================================
Upstream's `_shape` for a BUFFER reads `self.src[0].as_shape` (`ops.py:359`):

    case Ops.BUFFER | Ops.ALLOC | Ops.PARAM:
      assert len(self.src[0].as_shape) <= 1

so a SRC-LESS BUFFER has no `src[0]` and `_shape` raises `IndexError: tuple index
out of range`.  `compute_gradient` reads `k._shape` at `gradient.py:130`, so a
src-less leaf makes the whole walk UNCOMPUTABLE.

MEASURED 2026-10-25, on this tree's own `tinygrad/`: this file died at
`oracle-cg.py:83` with exactly that `IndexError`, AFTER printing five rows.  The
15 `walk_*` rows the prior art transcribed from it therefore could not be
re-verified -- they were a RECORD, not a measurement.

THE FIX IS THE LEAF.  `as_shape` of an EMPTY STACK is `()` (`ops.py:789`), so
`BUFFER(STACK())` has `_shape` `()` -- SCALAR -- and the shaped-edge reduce at
`gradient.py:131` never fires.  Every leaf in this file is built by `leaf()` so
that no two leaves disagree about their shape: a fixture that is half-changed is a
fixture that compares two different graphs.

THE SECOND FIXTURE (`build2`, the EXPAND) STILL CANNOT BE COMPUTED, and now for a
NAMED reason rather than an accident: its EXPAND's shape src is `ADD(a, d)`, whose
`as_shape` is the ONE-tuple `(ssimplify(c),)` (`ops.py:788`), so the EXPAND's
`_shape` is a 1-tuple, the shaped-edge reduce fires, and CPython raises there.
`main()` catches that and PRINTS IT AS A ROW, because an instrument that dies
without saying so is the failure mode this tree calls DEAD.
"""
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def leaf(slot):
  """A BUFFER whose src is an EMPTY STACK.  `as_shape` of an empty STACK is `()`
  (`ops.py:789`), so the leaf's `_shape` is `()` -- SCALAR -- and `compute_gradient`
  returns instead of raising.  MEASURED: `ops.py:359` reads `self.src[0].as_shape`,
  so a src-less BUFFER raises `IndexError` there."""
  return UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=()),), arg=ParamArg(slot, dtypes.float32))


def sig(u):
    ts = u.toposort()
    return "%d %s" % (len(ts), " ".join("%s/%d" % (x.op.name, len(x.src)) for x in ts))


def build1():
    """The DAG.  Pins the ACCUMULATE (gradient.py:134-138)."""
    a = leaf(0)
    b = leaf(1)
    c = leaf(2)
    p = UOp(Ops.MUL, src=(a, b))
    q = UOp(Ops.ADD, src=(a, c))
    return a, b, c, p, q, UOp(Ops.ADD, src=(p, q))


def build2():
    """The EXPAND.  Pins the HOLE (gradient.py:130) and the SKIP (:120).

    `EXPAND` answers `(ctx, None)` -- gradient.py:86 -- so its second src never
    receives a gradient.  That src is ON the target path (it is `ADD(a,d)` and `a` is
    a target) so it IS in the walk, and it is NOT in `grads` when the walk reaches it,
    which is gradient.py:120's `continue` firing for real rather than by construction.

    THE LEAVES ARE `BUFFER(STACK())` -- the same `leaf()` as `build1` -- so the two
    fixtures agree about what a leaf IS.  What this fixture CANNOT do is compute:
    its EXPAND's shape src is an ADD, so the shaped-edge reduce fires and CPython
    raises.  `main()` prints that raise as a row.
    """
    a = leaf(0)
    b = leaf(1)
    d = leaf(2)
    f = leaf(3)
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


def rule_rows(p, r, a):
    """THE RULE TABLE ON ITS OWN, and the forward-walk counterfactual -- BOTH built
    from the FIRST fixture only, so they are emitted whether or not the second
    fixture can be computed.  (Before the leaf was fixed, `main()` died in the FIRST
    fixture and NONE of these rows was ever printed.)"""
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


def main():
    a, b, c, p, q, r = build1()
    one("dag", r, {a, b, c}, (("a", a), ("b", b), ("c", c), ("p", p), ("q", q), ("r", r)))
    rule_rows(p, r, a)

    # THE SECOND FIXTURE, GUARDED.  It cannot be computed -- the shaped-edge reduce
    # fires on its EXPAND -- and the instrument SAYS SO instead of dying.
    try:
        a2, b2, d2, f2, c2, p2, e2, r2 = build2()
        one("hole", r2, {a2, b2, d2},
            (("a", a2), ("b", b2), ("c", c2), ("d", d2), ("p", p2), ("e", e2), ("r", r2)))
    except Exception as exc:
        # ONE LINE: a row is one `name=value` line, and upstream's message is
        # multi-line (it prints the whole UOp), so the newlines are folded.
        print("oracle_hole_error=%s: %s" % (type(exc).__name__, " ".join(str(exc).split())))
        print("oracle_hole_computed=no")


main()
