"""PROBE -- which fixtures can CPython's `compute_gradient` actually compute?

NOT a gate.  A throwaway that asks three questions and prints the answers:
  1. does `compute_gradient` return, or does it RAISE?
  2. does some TARGET have no entry in `grads` (the `const_like(0)` substitute)?
  3. does the walk fire a HOLE (gradient.py:130's `if v is None: continue`)?

Run with the repo's own tinygrad:
    LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward2/probe.py
"""
import traceback
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def buf(slot):
  return UOp(Ops.BUFFER, arg=ParamArg(slot, dtypes.float32))


def const1():
  return UOp.const(1.0, dtypes.float32)


def probe(tag, root, targets, names):
  print("== %s" % tag)
  try:
    walk, itp = _deepwalk(root, targets)
  except Exception as e:
    print("   deepwalk RAISED %s: %s" % (type(e).__name__, e)); return
  print("   walk=%s" % " ".join("%s/%d" % (x.op.name, len(x.src)) for x in walk))
  try:
    grads = compute_gradient(root, const1(), targets)
  except Exception as e:
    print("   compute_gradient RAISED %s: %s" % (type(e).__name__, e))
    traceback.print_exc()
    return
  print("   grads_n=%d" % len(grads))
  for nm, t in names:
    g = grads.get(t)
    print("   grad_%s=%s" % (nm, "NONE" if g is None else "%s/%d" % (g.op.name, len(g.src))))
  # the SKIP and the HOLE, counted through upstream's OWN loop
  seen, skipped, holes = set(), 0, 0
  g2 = {root: const1()}
  for t0 in reversed(walk):
    if t0 not in g2:
      skipped += 1
      continue
    lg = pm_gradient.rewrite(t0, ctx=g2[t0])
    if lg is None:
      continue
    holes += sum(1 for v in lg if v is None)
    seen.add(t0)
    for k, v in zip(t0.src, lg):
      if v is None:
        continue
      g2[k] = g2[k] + v if k in g2 else v
  print("   skip_n=%d hole_n=%d" % (skipped, holes))


def main():
  # F1: the prior art's DAG -- the accumulate, no hole.
  a, b, c = buf(0), buf(1), buf(2)
  p = UOp(Ops.MUL, src=(a, b))
  q = UOp(Ops.ADD, src=(a, c))
  r = UOp(Ops.ADD, src=(p, q))
  probe("dag", r, {a, b, c}, (("a", a), ("b", b), ("c", c)))

  # F2: the prior art's EXPAND fixture -- the hole, and CPython raises.
  a2, b2, d2, f2 = buf(0), buf(1), buf(2), buf(3)
  c2 = UOp(Ops.ADD, src=(a2, d2))
  p2 = UOp(Ops.MUL, src=(a2, b2))
  e2 = UOp(Ops.EXPAND, src=(p2, c2))
  r2 = UOp(Ops.ADD, src=(e2, f2))
  probe("expand", r2, {a2, b2, d2}, (("a", a2), ("b", b2), ("c", c2), ("d", d2)))

  # F3: the EXPAND with a SCALAR shape src -- `c` is a plain CONST 1 (the shape ()).
  a3, b3, f3 = buf(0), buf(1), buf(2)
  sh = UOp.const(1, dtypes.int32)
  p3 = UOp(Ops.MUL, src=(a3, b3))
  e3 = UOp(Ops.EXPAND, src=(p3, sh))
  r3 = UOp(Ops.ADD, src=(e3, f3))
  probe("expand_scalar", r3, {a3, b3}, (("a", a3), ("b", b3)))

  # F4: a target that is NOT on any path -- the ZERO substitute.
  a4, b4 = buf(0), buf(1)
  z4 = buf(9)
  p4 = UOp(Ops.MUL, src=(a4, b4))
  r4 = UOp(Ops.ADD, src=(p4, a4))
  probe("detached_target", r4, {a4, b4, z4}, (("a", a4), ("b", b4), ("z", z4)))


main()
