import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes


def buf(size, dt=dtypes.i32):
  return UOp._buffer(size, dt, 0, device='CPU')


def st(*dims):
  return UOp(Ops.STACK, tuple(UOp.const(d) for d in dims))


b4 = buf(4)


def show(tag, u):
  try:
    sh = tuple(f"{x}:{type(x).__name__}" for x in u._shape)
  except Exception as e:
    sh = f"RAISE {type(e).__name__}: {e}"
  print(f"{tag:14} n={len(list(u.toposort()))} op={u.op.name} nsrc={len(u.src)} "
        f"srcops={','.join(str(s.op.name) for s in u.src)} shape={sh} dtype={u.dtype.name} arg={u.arg}")


for op, arg in [(Ops.EXPAND, (2,)), (Ops.EXPAND, (2, 3)), (Ops.EXPAND, ())]:
  m = b4._mop(op, arg)
  show(f"mop {op.name}{arg}", m)

print()
print("by hand EXPAND(b4, st(2))")
show("hand exp2", UOp(Ops.EXPAND, (b4, st(2))))
show("hand exp23", UOp(Ops.EXPAND, (b4, st(2, 3))))
print("same as _mop(2):", UOp(Ops.EXPAND, (b4, st(2))) is b4._mop(Ops.EXPAND, (2,)))
print("same as _mop(2,3):", UOp(Ops.EXPAND, (b4, st(2, 3))) is b4._mop(Ops.EXPAND, (2, 3)))

print()
print("=== the arg of a _mop-built node")
# Ops.FLIP is NOT a member upstream any more: a flip is a PAD/SHRINK/TRANSPOSE chain now
# (`mixin/movement.py`'s `flip`), so there is no op for `_mop` to carry and no `marg` to read.
print("Ops.FLIP present:", hasattr(Ops, "FLIP"))
for op, arg in [(Ops.PERMUTE, (1, 0)), (Ops.PAD, ((0, 1), (2, 2))), (Ops.SHRINK, ((0, 1), (1, 2)))]:
  m = b4._mop(op, arg)
  show(f"mop {op.name}", m)
  print("     marg=", m.marg, " types=", tuple(type(x).__name__ for x in m.marg))

print()
print("=== hand-built PAD / SHRINK / PERMUTE (FLIP: see Ops.FLIP present above)")
show("hand pad", UOp(Ops.PAD, (b4, st(0, 1), st(2, 2)), ((0, 1), (2, 2))))
show("hand shk", UOp(Ops.SHRINK, (b4, st(0, 1), st(2, 2)), ((0, 1), (2, 2))))
show("hand perm", UOp(Ops.PERMUTE, (b4,), (1,)))
