#!/usr/bin/env python
# margsym-probe.py -- what does CPython's `ssimplify` DO with a non-CONST STACK
# element? Every answer here is CALLED, never transcribed. Run twice.
#
#   env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/margsym-probe.py
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, shape_to_shape_arg   # noqa: E402
from tinygrad import dtypes                                            # noqa: E402


def sig(u):
  """ONE token per candidate: is `ssimplify(u)` the SAME node, a CONST, or neither?"""
  r = u.ssimplify()
  if isinstance(r, UOp):
    return ("SAME" if r is u else "OTHER") + ":" + r.op.name
  return f"CONST:{r!r}:{type(r).__name__}"


def var(name, lo=0, hi=0xFFFFFF):
  return UOp.variable(name, lo, hi)


cands = []
cands.append(("PARAM n", var("n")))
cands.append(("PARAM m", var("m")))
cands.append(("PARAM narrow", var("p", 3, 3)))
cands.append(("SPECIAL N", UOp(Ops.SPECIAL, (UOp.const(0),), 'N')))
cands.append(("SPECIAL 3", UOp(Ops.SPECIAL, (UOp.const(3),), 'N')))
cands.append(("AFTER", UOp(Ops.AFTER, (var("q"),))))
cands.append(("FLOORDIV", var("z") // UOp.const(4)))
cands.append(("ADD(n,m)", var("n") + var("m")))
cands.append(("ADD(n,0)", var("n") + UOp.const(0)))
cands.append(("ADD(p,p)", var("p", 3, 3) + var("p", 3, 3)))
cands.append(("MUL(n,2)", var("n") * UOp.const(2)))
cands.append(("MUL(n,n)", var("n") * var("n")))
cands.append(("MUL(p,1)", var("p", 3, 3) * UOp.const(1)))
cands.append(("CAST i32->i64", var("n").cast(dtypes.int64)))
cands.append(("WHERE", (var("n") > UOp.const(0)).where(UOp.const(1), UOp.const(2))))
cands.append(("NEG", -var("n")))
cands.append(("MAX(n,1)", UOp.maximum(var("n"), UOp.const(1))))
cands.append(("CMPNE(n,1)", (var("n") != UOp.const(1))))

print("== ssimplify, per candidate ==")
for nm, u in cands:
  print(f"  {nm:16s} vmin={u.vmin} vmax={u.vmax} -> {sig(u)}")

print()
print("== THE WALL ROW: what CPython ANSWERS for `as_shape` / marg ==")
b4 = UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32, size=4))
n, m = var("n"), var("m")
# RESHAPE over a STACK(n, 4) -- what the differ's `sym` graph is.
r1 = UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (n, UOp.const(4)))))
r2 = UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (m, UOp.const(4)))))
print(f"  r1._shape = {[ (x.op.name, getattr(x,'arg',None)) if isinstance(x,UOp) else x for x in r1._shape]}")
print(f"  r2._shape = {[ (x.op.name, getattr(x,'arg',None)) if isinstance(x,UOp) else x for x in r2._shape]}")
print(f"  r1 shape text  = {str(r1.shape)}")
print(f"  r2 shape text  = {str(r2.shape)}")
print(f"  r1.dtype={r1.dtype.name} r2.dtype={r2.dtype.name}")
print(f"  n is n in r1._shape[0] -> {r1._shape[0] is n};  m is m in r2._shape[0] -> {r2._shape[0] is m}")
print(f"  r1._shape[0] is r2._shape[0] -> {r1._shape[0] is r2._shape[0]}")
print(f"  marginal(r1) == (n, 4) -> {r1.marg[0] is n}")
print(f"  marg text r1 = {[x.arg if isinstance(x,UOp) else x for x in r1.marg]}")

print()
print("== BARE PARAM marg: a 1-element shape arg is the PARAM ITSELF (ops.py:108) ==")
r3 = UOp(Ops.RESHAPE, (b4, n))
print(f"  r3._shape = {[ (x.op.name, getattr(x,'arg',None)) if isinstance(x,UOp) else x for x in r3._shape]}")
print(f"  r3.src[1].op = {r3.src[1].op.name}  as_shape = {r3.src[1].as_shape}")
print(f"  r3.marg[0] is n -> {r3.marg[0] is n}")

print()
print("== shape_to_shape_arg keeps a UOp verbatim (ops.py:105) ==")
print(f"  shape_to_shape_arg((n, 4)).op = {shape_to_shape_arg((n, 4)).op.name}")
print(f"  shape_to_shape_arg((n,)).op    = {shape_to_shape_arg((n,)).op.name}  (src[0] itself)")
