#!/usr/bin/env python
# margsym-probe3.py -- WHAT A SYMBOLIC DIM MAKES REACHABLE. Every answer CALLED, run
# twice. The question is not "does the port build `sym`" -- it does -- but WHICH
# CONSUMERS of a shape a symbolic dim can now reach, and the honest answer needs a
# measurement rather than an argument.
#
#   env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/margsym-probe3.py
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg    # noqa: E402
from tinygrad import Tensor, dtypes                 # noqa: E402


def rep(x):
  if isinstance(x, UOp):
    if x.op is Ops.PARAM:
      return f"U(PARAM:{x.arg.name})"
    if x.op is Ops.SPECIAL:
      return f"U(SPECIAL:{x.arg})"
    return f"U({x.op.name}:?)"
  return str(x)


def sig(u):
  try:
    sh = "(" + ",".join(rep(x) for x in u._shape) + ")"
  except Exception as e:
    sh = f"RAISE:{type(e).__name__}"
  return f"n={len(list(u.toposort()))} op={u.op.name} nsrc={len(u.src)} shape={sh} dtype={u.dtype.name}"


def var(name, lo=0, hi=0xFFFFFF):
  return UOp.variable(name, lo, hi)


n, m = var("n"), var("m")
a = Tensor.empty(4, 3).uop
c4 = UOp.const(4)
r_n4 = UOp(Ops.RESHAPE, (a, UOp.stack(n, c4)))
r_m4 = UOp(Ops.RESHAPE, (a, UOp.stack(m, c4)))

print("== THE BASELINE, for reference: one RESHAPE over a symbolic marg ==")
print("  RESHAPE(a, STACK(n,4))          ", sig(r_n4))

print()
print("== A RESHAPE CHAINED OVER A SYMBOLIC RESHAPE: `prod(ps)` is symbolic TOO ==")
cases = [
    ("RESHAPE(RESHAPE(a,STACK(n,4)), STACK(4,n))", UOp(Ops.RESHAPE, (r_n4, UOp.stack(c4, n)))),
    ("RESHAPE(RESHAPE(a,STACK(n,4)), STACK(n,4))", UOp(Ops.RESHAPE, (r_n4, UOp.stack(n, c4)))),
    ("EXPAND(RESHAPE(a,STACK(n,4)), STACK(4,n))", UOp(Ops.EXPAND, (r_n4, UOp.stack(c4, n)))),
    ("PERMUTE(RESHAPE(a,STACK(n,4)), (1,0))", UOp(Ops.PERMUTE, (r_n4,), (1, 0))),
    ("FLIP(RESHAPE(a,STACK(n,4)), (True,False))", UOp(Ops.FLIP, (r_n4,), (True, False))),
    ("CAST(RESHAPE(a,STACK(n,4)) -> f32)", UOp(Ops.CAST, (r_n4,), dtypes.f32)),
    ("ADD(RESHAPE(a,STACK(n,4)), CONST(1))", UOp(Ops.ADD, (r_n4, UOp.const(1)))),
    ("MUL(RESHAPE(a,STACK(n,4)), RESHAPE(a,STACK(m,4)))",
     UOp(Ops.MUL, (r_n4, r_m4))),
    ("PAD(RESHAPE(a,STACK(n,4)), 0, n)", UOp(Ops.PAD, (r_n4, UOp.const(0), n))),
    ("SHRINK(RESHAPE(a,STACK(n,4)), 0, n)", UOp(Ops.SHRINK, (r_n4, UOp.const(0), n))),
    ("INDEX(RESHAPE(a,STACK(n,4)), n)", UOp(Ops.INDEX, (r_n4, n))),
    ("REDUCE(RESHAPE(a,STACK(n,4)), (1,), Ops.ADD, i32)",
     UOp(Ops.REDUCE, (r_n4, UOp.const(1)), (Ops.ADD, dtypes.int32))),
    ("GROUP(RESHAPE n, RESHAPE m)", UOp.group(r_n4, r_m4)),
]
for nm, u in cases:
  print(f"  {nm:46s} {sig(u)}")

print()
print("== TWO GRAPHS WHOSE SHAPE COLUMNS ARE BOTH `(U,4)` -- are they the same graph? ==")
g1 = UOp.group(r_n4, UOp(Ops.RESHAPE, (a, UOp.stack(m, c4))))
g2 = UOp.group(r_n4, r_n4)
print(f"  g1 nodes={len(list(g1.toposort()))} g2 nodes={len(list(g2.toposort()))}")
print(f"  g1 toposort: {[x.op.name for x in g1.toposort()]}")
print(f"  g2 toposort: {[x.op.name for x in g2.toposort()]}")
print(f"  the SHAPE COLUMNS of g1's two RESHAPEs: "
      f"{[tuple(rep(d) for d in x._shape) for x in g1.toposort() if x.op is Ops.RESHAPE]}")
print(f"  and of g2's:                               "
      f"{[tuple(rep(d) for d in x._shape) for x in g2.toposort() if x.op is Ops.RESHAPE]}")
