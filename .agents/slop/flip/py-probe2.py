import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from tinygrad import Tensor, dtypes, UOp
from tinygrad.uop.ops import Ops

a = Tensor.empty(4, 3, dtype=dtypes.float)
au = a.uop

print("== THE ATOM LETTERS (graphcmp.py:324-326) ==")
import re
src = open(os.path.join(os.path.dirname(__file__), "..", "graphcmp.py")).read()
m = re.search(r'ATOMS = \{(.*?)\}', src, re.S)
for k, v in re.findall(r'"(\w+)":\s*"(\w+)"', m.group(1)):
    print(f"  {k:<8} -> {v}")

print("\n== upstream REFUSES a non-bool flip arg (ops.py:428) ==")
for arg in [(0,), (1, 0), (True, False), (5, 7)]:
    try:
        print(f"  UOp(Ops.FLIP,(au,),{arg!r}).shape -> {UOp(Ops.FLIP, (au,), arg).shape}")
    except Exception as e:
        print(f"  UOp(Ops.FLIP,(au,),{arg!r}).shape -> {type(e).__name__}: {e}")

print("\n== upstream PERMUTE for contrast (ops.py:415) ==")
for arg in [(1, 0), (True, False)]:
    try:
        print(f"  UOp(Ops.PERMUTE,(au,),{arg!r}).shape -> {UOp(Ops.PERMUTE, (au,), arg).shape}")
    except Exception as e:
        print(f"  UOp(Ops.PERMUTE,(au,),{arg!r}).shape -> {type(e).__name__}: {e}")

print("\n== spec.py -- the shared isinstance(tuple) assertion ==")
for node in (a.flip(0).uop, a.permute(1, 0).uop):
    print(f"  {node.op} arg={node.arg!r} isinstance(tuple)={isinstance(node.arg, tuple)}")