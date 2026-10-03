"""ORACLE: which CUSTOMI arg shape is right, and what is a CUSTOM_FUNCTION's
(dtype, shape)? Called, never typed. ops.py:137 asserts the arg, so the assert's
own message is the answer -- but build the node and read the fields back."""
import sys; sys.path.insert(0, ".")
from tinygrad.uop.ops import UOp, Ops, CustomFunction
from tinygrad.dtype import dtypes

print("=== Q1 what does a real CUSTOMI node's arg ACTUALLY hold? ===")
# The real caller: Kernel.custom / Ops.CUSTOMI. Find the constructor in the port's world.
import tinygrad.uop.ops as O
import inspect
src = inspect.getsource(O)
for ln, line in enumerate(src.splitlines(), 1):
  if "CUSTOMI" in line or "Ops.CUSTOM," in line:
    print(f"  ops.py:{ln}: {line.strip()}")

print("\n=== Q2 dtype_from_uop for each op (ops.py:122) ===")
def probe(op, arg, src=()):
  u = UOp(op, src=src, arg=arg)
  print(f"  {op.name:<16} arg={arg!r:<34} dtype={u.dtype.name:<8} shape={u._shape!r}")
  return u

probe(Ops.CUSTOM_FUNCTION, CustomFunction("myext", dtypes.uint64))
probe(Ops.CUSTOM_FUNCTION, CustomFunction("myvoid", dtypes.void))
probe(Ops.CUSTOM_FUNCTION, CustomFunction("f16fn", dtypes.float16))
print()
probe(Ops.CUSTOM, ("mysym", dtypes.uint64))
probe(Ops.CUSTOMI, ("mysym", dtypes.uint64))

print("\n=== Q3 the assert text itself, verbatim ===")
for ln, line in enumerate(src.splitlines(), 1):
  if "CUSTOM/CUSTOMI arg must be" in line:
    print(f"  ops.py:{ln}: {line.strip()}")

print("\n=== Q4 does a bare str survive as a CUSTOMI arg? ===")
try:
  u = UOp(Ops.CUSTOMI, src=(), arg="mysym")
  print(f"  UOp built; dtype={u.dtype.name} shape={u._shape!r}   <-- assert did NOT fire")
except AssertionError as e:
  print(f"  AssertionError: {e}")
except Exception as e:
  print(f"  {type(e).__name__}: {e}")

print("\n=== Q5 so is a bare `('x',)`-style AStr a legal CUSTOMI arg at all? ===")
for bad in ["x", ("x",), None]:
  try:
    u = UOp(Ops.CUSTOMI, src=(), arg=bad)
    print(f"  arg={bad!r:<10} -> dtype={u.dtype.name}")
  except AssertionError as e:
    print(f"  arg={bad!r:<10} -> AssertionError: {str(e)[:90]}")
  except Exception as e:
    print(f"  arg={bad!r:<10} -> {type(e).__name__}: {str(e)[:90]}")

print("\n=== Q6 CUSTOM_FUNCTION (dtype, _shape) pair -- the Defect 2 table ===")
for nm, dt in (("void", dtypes.void), ("uint64", dtypes.uint64), ("float16", dtypes.float16),
               ("int32", dtypes.int32), ("bool", dtypes.bool), ("f64", dtypes.float64)):
  cf = CustomFunction(nm, dt)
  u = UOp(Ops.CUSTOM_FUNCTION, src=(), arg=cf)
  print(f"  CustomFunction({nm!r}, {dt.name:<8}) -> dtype={u.dtype.name:<8} shape={u._shape!r}")
print("\n  and CustomFunction(name) with NO dtype:")
cf = CustomFunction("x")
print(f"    CustomFunction('x').dtype = {cf.dtype.name}   (ops.py:1395 default)")
