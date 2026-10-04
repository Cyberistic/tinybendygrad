import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
import tinygrad.uop.ops as O
from tinygrad import Tensor, dtypes, UOp
from tinygrad.uop.ops import Ops

CACHE = [v for v in vars(O).values()
         if isinstance(v, dict) and type(v).__name__ == "DefaultDict"]
print("ucache objects found:", len(CACHE))

def fresh():
  for c in CACHE: c.clear()

print("\n== IS THE CONFLATION SPECIFIC TO FLIP, OR GENERAL TO TUPLE ARGS? ==")
for op, a1, a2 in [(Ops.FLIP, (True, False), (1, 0)), (Ops.PERMUTE, (1, 0), (True, False))]:
  fresh()
  t = Tensor.empty(4, 3, dtype=dtypes.float)
  tu = t.uop
  p = UOp(op, (tu,), a1)
  q = UOp(op, (tu,), a2)
  print(f"  {op.name:<8} {a1!r} then {a2!r}: p is q = {p is q}   stored = {p.arg!r}")

print("\n== A BARE-BOOL ARG IS A DIFFERENT KEY PATH (not a tuple) ==")
fresh()
t = Tensor.empty(4, 3, dtype=dtypes.float)
bu = t.uop
print("  ALLOC bind_on_realize True :", repr(UOp(Ops.ALLOC, (), __import__("tinygrad").uop.ops.ParamArg(0, dtypes.f32, 12, None, True)).arg.bind_on_realize))
print("  ALLOC bind_on_realize 1    :", repr(UOp(Ops.ALLOC, (), __import__("tinygrad").uop.ops.ParamArg(0, dtypes.f32, 12, None, 1)).arg.bind_on_realize))

print("\n== SO THE PORT'S SPELLING IS A VALUE CPYTHON ITSELF CANNOT HOLD APART ==")
fresh()
t = Tensor.empty(4, 3, dtype=dtypes.float)
tu = t.uop
p = UOp(Ops.FLIP, (tu,), (True, False))
print("  bool-first: arg=", repr(p.arg), " shape=", p.shape)
print("  int request is the same node:", UOp(Ops.FLIP, (tu,), (1, 0)) is p)
fresh()
t = Tensor.empty(4, 3, dtype=dtypes.float)
tu = t.uop
q = UOp(Ops.FLIP, (tu,), (1, 0))
print("  int-first : arg=", repr(q.arg))
try:
  print("  shape=", q.shape)
except Exception as e:
  print(f"  shape={type(e).__name__}: {e}")
print("  bool request is the same node:", UOp(Ops.FLIP, (tu,), (True, False)) is q)
print("\n  => ops.py:428's guard is INSERTION-ORDER DEPENDENT. Which spelling is")
print("     stored is decided by which request reached the ucache first.")