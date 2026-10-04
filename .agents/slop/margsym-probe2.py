#!/usr/bin/env python
# margsym-probe2.py -- MEASURE what CPython does for the RESHAPE/EXPAND arms over a
# symbolic marg, and what `ssimplify` is for every element a shape arg can carry.
# Run twice. Nothing here is transcribed.
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, shape_to_shape_arg   # noqa: E402
from tinygrad import dtypes                                            # noqa: E402


def buf(size, dt=dtypes.i32):
  return UOp(Ops.BUFFER, (), ParamArg(0, dt, size=size))


def var(name, lo=0, hi=0xFFFFFF):
  return UOp.variable(name, lo, hi)


def rep(x):
  if isinstance(x, UOp):
    nm = x.arg.name if x.op is Ops.PARAM else (x.arg if x.op is Ops.SPECIAL else '')
    return f"UOp({x.op.name}{':' + str(nm) if nm != '' else ''})"
  return repr(x)


def sig(u):
  try:
    sh = "(" + ",".join(rep(x) for x in u._shape) + ")"
  except Exception as e:
    sh = f"RAISE:{type(e).__name__}"
  return f"n={len(list(u.toposort()))} op={u.op.name} shape={sh} dtype={u.dtype.name}"


print("== RESHAPE over a symbolic marg: does ops.py:410 raise or not? ==")
b4 = buf(4)
n, m = var("n"), var("m")
cases = [
    ("RESHAPE(BUF4, STACK(n,4))", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (n, UOp.const(4)))))),
    ("RESHAPE(BUF4, STACK(2,SPEC N))", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (UOp.const(2), UOp(Ops.SPECIAL, (UOp.const(0),), 'N')))))),
    ("RESHAPE(BUF4, STACK(n,SPEC N))", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (n, UOp(Ops.SPECIAL, (UOp.const(0),), 'N')))))),
    ("RESHAPE(BUF4, STACK(4,n))", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (UOp.const(4), n))))),
    ("RESHAPE(BUF4, n)  bare PARAM", UOp(Ops.RESHAPE, (b4, n))),
    ("RESHAPE(BUF4, STACK(m,4))", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (m, UOp.const(4)))))),
]
for nm, u in cases:
  try:
    msg = u._shape
    print(f"  {nm:34s} {sig(u)}  marg={[rep(x) for x in u.marg]}")
  except Exception as e:
    print(f"  {nm:34s} {sig(u)}  marg={[rep(x) for x in u.marg]}")
    print(f"      {type(e).__name__}: {e}")

print()
print("== THE DIFFER's `sym` GRAPH, verbatim ==")
from tinygrad import Tensor                                              # noqa: E402
a = Tensor.empty(4, 3).uop
g = UOp.group(UOp(Ops.RESHAPE, (a, UOp(Ops.STACK, (n, UOp.const(4))))),
              UOp(Ops.RESHAPE, (a, UOp(Ops.STACK, (m, UOp.const(4))))))
print(f"  nodes={len(list(g.toposort()))} root={g.op.name}")
for i, x in enumerate(g.toposort()):
  print(f"    {i} {x.op.name:8s} shape={tuple(rep(d) for d in x._shape) if x.op not in
        (Ops.IF, Ops.BARRIER, Ops.SINK, Ops.GROUP, Ops.WHERE) else '-'}")

print()
print("== ssimplify over a POINT-range PARAM: the other direction ==")
for nm, p in [("p(3,3)", var("p", 3, 3)), ("p(0,0)", var("p", 0, 0)), ("SPEC N end=1", UOp(Ops.SPECIAL, (UOp.const(1),), 'N'))]:
  print(f"  {nm:14s} vmin={p.vmin} vmax={p.vmax} ssimplify -> {p.ssimplify()!r} ({type(p.ssimplify()).__name__})")

print()
print("== THE IDENTITY CLAIM: is `simplify` the identity for every non-POINT PARAM/SPECIAL? ==")
bad = []
cands = [var("n"), var("m"), var("n2"), var("big", 0, 2 ** 40), var("neg", -5, 5),
         UOp(Ops.SPECIAL, (UOp.const(0),), 'N'), UOp(Ops.SPECIAL, (UOp.const(3),), 'N'),
         UOp(Ops.SPECIAL, (UOp.const(1),), 'N'), UOp(Ops.SPECIAL, (UOp.const(99),), 'N')]
for u in cands:
  r = u.simplify()
  pt = (u.vmin == u.vmax)
  tag = "SAME" if r is u else "OTHER"
  if (not pt) and tag != "SAME":
    bad.append((u, r))
  print(f"  {rep(u):22s} vmin={u.vmin:>6} vmax={u.vmax:<12} point={pt!s:5s} simplify -> {tag}")
print(f"  NON-POINT PARAM/SPECIAL CHANGED BY simplify: {len(bad)} of {len([u for u in cands if u.vmin != u.vmax])}")

print()
print("== AND: does a POINT-range PARAM/SPECIAL ALWAYS become an int? ==")
badp = []
for u in cands:
  if u.vmin == u.vmax:
    r = u.ssimplify()
    if not isinstance(r, int):
      badp.append((u, r))
    print(f"  {rep(u):22s} point -> ssimplify {r!r} ({type(r).__name__})")
print(f"  POINT PARAM/SPECIAL NOT an int: {len(badp)}")
