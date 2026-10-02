#!/usr/bin/env python3
"""rf-probe-arg.py -- what does CPython put in a CALL's `arg`, and does it
survive the two `x.replace(src=...)` rules that rangeify.bend ports at
ab_7 (`drop RESHAPEs on KERNEL`, rangeify.py:267) and `no_indexing_calls`
(rangeify.py:143-158)?

The Bend fixture gives every CALL an `ANone` arg, so on it
`eq_arg(rebuilt_arg, original_arg)` is the tautology `eq_arg(ANone, ANone)`
and no row can tell "kept its own arg" from "was handed ANone".  A CALL whose
arg is NOT None is the node that makes the arg observable, so this probe finds
a legal non-None arg first."""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, KernelInfo, AxisType
from tinygrad.dtype import dtypes, AddrSpace

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(n=4, a=AddrSpace.GLOBAL, s=0): return UOp(Ops.BUFFER, arg=ParamArg(s, dtypes.i32, n, addrspace=a))

b4 = B(4, AddrSpace.GLOBAL, 0)
c0, c4 = C(0), C(4)
rs = UOp(Ops.RESHAPE, (b4, c4))

# --- find a legal non-None arg for a CALL -------------------------------
cands = {}
try:
  cands['KernelInfo()'] = KernelInfo()
except Exception as e:
  print("KernelInfo() failed:", e)
for name, a in cands.items():
  try:
    u = UOp(Ops.CALL, (rs, c0), arg=a)
    print(f"CALL arg={name}: OK, is arg {u.arg!r}, type {type(u.arg).__name__}")
  except Exception as e:
    print(f"CALL arg={name}: REJECTED {type(e).__name__}: {e}")

# what arg TYPES does the KernelInfo-shaped thing actually round-trip as?
u = UOp(Ops.CALL, (rs, c0), arg=KernelInfo())
print("roundtrip identical:", u.arg == KernelInfo(), "| repr:", repr(u.arg))
print("CALL dtype:", u.dtype, "| shape:", u.shape)