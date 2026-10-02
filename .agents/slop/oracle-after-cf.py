# does CPython's spec_shared have an opinion about an AFTER whose arg is a CustomFunction?
# An AFTER with no src: `sh_20` (spec.py:101) requires allow_any_len over a Movement src, so
# it cannot match. If CPython also answers None, the port's row is an oracle-backed fact
# and not an artifact of the port.
from tinygrad.uop.ops import UOp, Ops, CustomFunction, dtypes
from tinygrad.uop import spec

def verdict(x):
  r = spec.spec_shared.rewrite(x)
  return {True:"1", False:"0", None:"9"}[r]

a = UOp(Ops.AFTER, src=(), arg=CustomFunction("f"))
print("after_op=", a.op, "after_nsrc=", len(a.src), "after_arg_is_cf=", isinstance(a.arg, CustomFunction))
print("after_verdict=", verdict(a))
n = UOp(Ops.NOOP, src=(), arg=CustomFunction("f"))
print("noop_verdict=", verdict(n))
