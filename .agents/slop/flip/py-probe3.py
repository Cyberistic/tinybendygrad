import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from tinygrad import Tensor, dtypes, UOp
from tinygrad.uop.ops import Ops

a = Tensor.empty(4, 3, dtype=dtypes.float)
au = a.uop

print("== PYTHON-LEVEL EQUALITY OF THE TWO SPELLINGS ==")
print("  (1,0) == (True,False)      :", (1, 0) == (True, False))
print("  hash((1,0))==hash((True,F)):", hash((1, 0)) == hash((True, False)))
print("  {1:0} == {True:False}      :", {1: 0} == {True: False})

print("\n== DOES THE UCACHE CONFLATE THEM? fresh cache, int arg FIRST ==")
UOp.reset() if hasattr(UOp, "reset") else None
n_int = UOp(Ops.FLIP, (au,), (1, 0))
print("  UOp(FLIP,(au,),(1,0)).arg         :", repr(n_int.arg))
print("  then UOp(FLIP,(au,),(True,False)) :", repr(UOp(Ops.FLIP, (au,), (True, False)).arg))

print("\n== REVERSE ORDER: bool arg FIRST ==")
UOp.reset() if hasattr(UOp, "reset") else None
n_bool = UOp(Ops.FLIP, (au,), (True, False))
print("  UOp(FLIP,(au,),(True,False)).arg :", repr(n_bool.arg))
print("  then UOp(FLIP,(au,),(1,0)).arg   :", repr(UOp(Ops.FLIP, (au,), (1, 0)).arg))

print("\n== SO: WHAT DOES THE UOP HASH ON? ==")
print("  UOp.key(FLIP True) :", UOp(Ops.FLIP, (au,), (True, False))._key()[:3] if hasattr(UOp(Ops.FLIP, (au,), (True, False)), "_key") else "n/a")
print("  UOp.key(FLIP int)  :", UOp(Ops.FLIP, (au,), (1, 0))._key()[:3] if hasattr(UOp(Ops.FLIP, (au,), (1, 0)), "_key") else "n/a")
print("  equal keys         :", UOp(Ops.FLIP, (au,), (True, False))._key() == UOp(Ops.FLIP, (au,), (1, 0))._key())

print("\n== AND THE GROUP ELISION, MEASURED ONCE MORE ==")
UOp.reset() if hasattr(UOp, "reset") else None
fl = Tensor.empty(4, 3, dtype=dtypes.float).flip(0).uop
print("  len(UOp.group(fl).toposort())      :", len(UOp.group(fl).toposort()), "root", UOp.group(fl).op)
print("  len(UOp.group(fl,fl).toposort())   :", len(UOp.group(fl, fl).toposort()), "root", UOp.group(fl, fl).op)