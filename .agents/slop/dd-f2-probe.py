#!/usr/bin/env python3
# dd-f2-probe.py -- CALL CPython: why is `lo.const_like(0)` (dtype uint32) NOT a
# fresh node in `lg6`, when lg2's `x.const_like(0)` (dtype i32) is the only 0-at-
# an-integer-dtype node interned before it?  And: what is `reciprocal()`?
import sys
sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location("ddoracle", ".agents/slop/dd-oracle.py")
DDO = importlib.util.module_from_spec(spec)
sys.modules["ddoracle"] = DDO
spec.loader.exec_module(DDO)
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops

DDO.IDX()
interned = set(id(u) for u in DDO.ORDER)

# run lg1..lg5 exactly as the oracle does
for nm, op, dt, xdt, n in DDO.L2I():
    if nm in ("lg6", "lg7"):
        break
    DDO.DD.l2i(op, dt, *DDO.ws(xdt, n))

for dtn, dt in (("u32", dtypes.uint32), ("i32", dtypes.int32), ("u64", dtypes.uint64)):
    k = UOp.const(0, dt)
    print(f"UOp.const(0, {dtn}) id-interned-before-lg6 = {id(k.src[0]) in interned}, "
          f"cast-interned = {id(k) in interned}, repr={k!r}")

# ---- what `reciprocal()` does to a CONST
from tinygrad.uop.ops import UOp as _U
r = _U.const(2**32).reciprocal()
print("reciprocal(C(2**32)) =", repr(r))
r2 = _U.const(2**32).reciprocal()
print("reciprocal again same id?", id(r) == id(r2))
import inspect
print(inspect.getsource(type(_U.variable('p',0,0)).reciprocal))
