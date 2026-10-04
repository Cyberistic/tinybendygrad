import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/tinygrad"))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from tinygrad import Tensor, dtypes, UOp
from tinygrad.uop.ops import Ops

a = Tensor.empty(4, 3, dtype=dtypes.float)

print("== atom letters in graphcmp.py ATOMS ==")
print("  bool ->", ATB if (ATB := None) else "see probe 2")

g = UOp.group(a.flip(0).uop)
print("\n== UOp.group(a.flip(0).uop) ==")
print("  root op      :", g.op)
print("  is the FLIP  :", g.op is Ops.FLIP)
print("  len(toposort):", len(g.toposort()))
print("  census       :", {str(o): sum(1 for n in g.toposort() if n.op is o)
                          for o in sorted({n.op for n in g.toposort()}, key=str)})

f = a.flip(0).uop
print("\n== a.flip(0).uop ==")
print("  arg          :", repr(f.arg))
print("  arg types    :", [type(x).__name__ for x in f.arg])
print("  arg == (1,0) :", tuple(int(x) for x in f.arg) == (1, 0))

print("\n== upstream REFUSES a non-bool flip arg ==")
for arg in [(0,), (1, 0), (5, 7)]:
    try:
        print(f"  UOp(Ops.FLIP,(a,),{arg}).shape ->", UOp(Ops.FLIP, (a,), arg).shape)
    except Exception as e:
        print(f"  UOp(Ops.FLIP,(a,),{arg}).shape -> {type(e).__name__}: {e}")

print("\n== UOp.group elision ==")
print("  UOp.group(FLIP).op  :", UOp.group(f).op)
print("  UOp.group(FLIP,FLIP).op:", UOp.group(f, f).op)
print("  UOp.group().op      :", UOp.group().op, "nsrc", len(UOp.group().src))

print("\n== spec.py:166 accepts both ==")
try:
    UOp.spec_preview([f]) if hasattr(UOp, "spec_preview") else None
except Exception as e:
    print("  spec_preview:", type(e).__name__, e)