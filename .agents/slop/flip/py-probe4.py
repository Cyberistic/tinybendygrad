import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from tinygrad import Tensor, dtypes, UOp
from tinygrad.uop.ops import Ops

print("UOp has .reset :", hasattr(UOp, "reset"))
print("UOp cache attr :", [n for n in dir(UOp) if "cache" in n.lower() or "reset" in n.lower()])

def fresh():
  for n in ("uop_cache", "_uop_cache"):
    if hasattr(UOp, n): getattr(UOp, n).clear()
  # the module-level cache tinygrad actually uses
  import tinygrad.uop.ops as O
  for n in dir(O):
    v = getattr(O, n)
    if isinstance(v, dict) and getattr(v, "__class__", None).__name__ == "DefaultDict":
      v.clear()

print("\n== FRESH CACHE, BOOL ARG FIRST, absolutely nothing interned yet ==")
fresh()
a = Tensor.empty(4, 3, dtype=dtypes.float)
au = a.uop
n = UOp(Ops.FLIP, (au,), (True, False))
print("  arg stored   :", repr(n.arg), [type(x).__name__ for x in n.arg])
print("  .shape       :", n.shape)

print("\n== FRESH CACHE, INT ARG FIRST ==")
fresh()
b = Tensor.empty(4, 3, dtype=dtypes.float)
bu = b.uop
m = UOp(Ops.FLIP, (bu,), (1, 0))
print("  arg stored   :", repr(m.arg), [type(x).__name__ for x in m.arg])
try:
  print("  .shape       :", m.shape)
except Exception as e:
  print(f"  .shape       : {type(e).__name__}: {e}")

print("\n== AFTER INT-FIRST, DOES A BOOL REQUEST GET THE INT NODE? ==")
print("  UOp(FLIP,(bu,),(True,False)).arg :", repr(UOp(Ops.FLIP, (bu,), (True, False)).arg))
print("  SAME OBJECT as the int node      :", UOp(Ops.FLIP, (bu,), (True, False)) is m)

print("\n== fresh(), bool first, then int: SAME OBJECT? ==")
fresh()
c = Tensor.empty(4, 3, dtype=dtypes.float)
cu = c.uop
p = UOp(Ops.FLIP, (cu,), (True, False))
q = UOp(Ops.FLIP, (cu,), (1, 0))
print("  p.arg :", repr(p.arg), " q.arg :", repr(q.arg), " p is q:", p is q)

print("\n== AND THE ELIDED GROUP, on a fresh cache ==")
fresh()
d = Tensor.empty(4, 3, dtype=dtypes.float)
g = UOp.group(d.flip(0).uop)
print("  root op:", g.op, " n=", len(g.toposort()))
print("  GROUP count in census:", sum(1 for n2 in g.toposort() if n2.op is Ops.GROUP))