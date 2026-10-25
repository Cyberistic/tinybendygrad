"""PROBE 2 -- which LEAF kind can CPython's `compute_gradient` compute TODAY?

The prior art's fixture (`.agents/slop/backward/oracle-cg.py`) uses
`UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))` -- a BUFFER with NO src -- and it
NO LONGER RUNS: `compute_gradient` reads `k._shape` (gradient.py:130) and upstream's
`_shape` for a BUFFER reads `self.src[0].as_shape` (ops.py:359), so a src-less BUFFER
raises `IndexError: tuple index out of range`.

So the leaf has to have a src whose `as_shape` is `()`.  Candidates:
  L1  BUFFER with an EMPTY STACK src   -> as_shape () -> _shape ()
  L2  a bare CONST leaf                -> _shape () by ops.py:351, dtype weakfloat
  L3  PARAM with an EMPTY STACK src

NOT a gate.  Run:
    LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward2/probe2.py
"""
import traceback
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def leaf_empty_stack(op, slot, dt):
  return UOp(op, src=(UOp(Ops.STACK, src=()),), arg=ParamArg(slot, dt))


def probe(tag, root, targets, names):
  print("== %s" % tag)
  walk, itp = _deepwalk(root, targets)
  print("   walk=%s" % " ".join("%s/%d" % (x.op.name, len(x.src)) for x in walk))
  try:
    grads = compute_gradient(root, UOp.const(1.0, dtypes.float32), targets)
  except Exception as e:
    print("   compute_gradient RAISED %s: %s" % (type(e).__name__, e))
    traceback.print_exc()
    return
  print("   grads_n=%d" % len(grads))
  for nm, t in names:
    g = grads.get(t)
    print("   grad_%s=%s" % (nm, "NONE" if g is None else "%s/%d" % (g.op.name, len(g.src))))
  # the SKIP and the HOLE, counted through upstream's OWN loop
  skipped, holes = 0, 0
  g2 = {root: UOp.const(1.0, dtypes.float32)}
  for t0 in reversed(walk):
    if t0 not in g2:
      skipped += 1
      continue
    lg = pm_gradient.rewrite(t0, ctx=g2[t0])
    if lg is None:
      continue
    holes += sum(1 for v in lg if v is None)
    for k, v in zip(t0.src, lg):
      if v is None:
        continue
      g2[k] = g2[k] + v if k in g2 else v
  print("   skip_n=%d hole_n=%d" % (skipped, holes))
  # THE GRADIENT SET -- mixin/op.py:471
  for nm, t in names:
    g = grads.get(t)
    if g is None:
      sub = t.const_like(0)
      print("   set_%s=ZERO -> %s/%d dtype=%s" % (nm, sub.op.name, len(sub.src), sub.dtype))
    else:
      print("   set_%s=%s/%d dtype=%s" % (nm, g.op.name, len(g.src), g.dtype))


def main():
  for lname, mk in (("L1", lambda s: leaf_empty_stack(Ops.BUFFER, s, dtypes.float32)),
                    ("L2", lambda s: UOp.const(1.0 + s)),
                    ("L3", lambda s: leaf_empty_stack(Ops.PARAM, s, dtypes.float32))):
    print("############ leaf=%s" % lname)
    try:
      a, b, c = mk(0), mk(1), mk(2)
    except Exception as e:
      print("   leaf build RAISED %s: %s" % (type(e).__name__, e)); continue
    print("   leaf0 dtype=%s shape=%s" % (a.dtype, a._shape))
    p = UOp(Ops.MUL, src=(a, b))
    q = UOp(Ops.ADD, src=(a, c))
    r = UOp(Ops.ADD, src=(p, q))
    probe("%s-dag" % lname, r, {a, b, c}, (("a", a), ("b", b), ("c", c)))
    # the EXPAND: the HOLE, and a target with NO gradient at all
    a2, b2, f2 = mk(0), mk(1), mk(2)
    sh = UOp.const(1, dtypes.int32)
    p2 = UOp(Ops.MUL, src=(a2, b2))
    e2 = UOp(Ops.EXPAND, src=(p2, sh))
    r2 = UOp(Ops.ADD, src=(e2, f2))
    probe("%s-expand" % lname, r2, {a2, b2}, (("a", a2), ("b", b2)))
    # a target that is ON NO PATH: the ZERO substitute for real
    a3, b3, z3 = mk(0), mk(1), mk(9)
    p3 = UOp(Ops.MUL, src=(a3, b3))
    r3 = UOp(Ops.ADD, src=(p3, a3))
    probe("%s-detached" % lname, r3, {a3, b3, z3}, (("a", a3), ("b", b3), ("z", z3)))


main()
