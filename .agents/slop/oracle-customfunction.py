# oracle-customfunction.py -- facts about tinygrad.uop.ops.CustomFunction, read by CALLING it.
import dataclasses, inspect
from tinygrad.uop.ops import CustomFunction, CallInfo, UOp, UPat, dtypes, Ops

f = dataclasses.fields(CustomFunction)
print("fields_name=", ",".join(x.name for x in f))
print("fields_arity=", len(f))
print("types=", ",".join(x.type for x in f))
print("frozen=", CustomFunction.__dataclass_params__.frozen)
print("default_void=", CustomFunction("sel_registerName").dtype == dtypes.void)
print("default_name=", CustomFunction("sel_registerName").name)
print("eq_same=", CustomFunction("f") == CustomFunction("f"))
print("eq_dt_differs=", CustomFunction("f") == CustomFunction("f", dtypes.uint64))
print("eq_name_differs=", CustomFunction("f", dtypes.uint64) == CustomFunction("g", dtypes.uint64))
print("repr=", repr(CustomFunction("sel_registerName")))
print("hashed=", isinstance(hash(CustomFunction("f")), int))

# UOp.custom_function -- what it builds
u = UOp.custom_function("sel_registerName")
print("cf_op=", u.op)
print("cf_arg_name=", u.arg.name)
print("cf_arg_dtype_void=", u.arg.dtype == dtypes.void)
print("cf_nsrc=", len(u.src))
print("cf_dtype_void=", u.dtype == dtypes.void)
print("cf_shape_none=", u._shape is None)
print("cf_shape_empty=", u._shape == ())
print("cf_key_is_arg=", u.key[2] == u.arg)
print("cf_arg_is_CustomFunction=", isinstance(u.arg, CustomFunction))

u2 = UOp.custom_function("sel_registerName", dtype=dtypes.uint64)
print("cf2_arg_dtype_u64=", u2.arg.dtype == dtypes.uint64)
print("cf2_dtype_u64=", u2.dtype == dtypes.uint64)
print("cf2_shape_empty=", u2._shape == ())
print("cf2_nsrc=", len(u2.src))

# with src
b = UOp.placeholder((4,), dtypes.uint32)
u3 = UOp.custom_function("f", b, dtype=dtypes.uint64)
print("cf3_nsrc=", len(u3.src), "cf3_argname=", u3.arg.name)

# hash-consing: same key -> same object
print("cf_interned=", UOp.custom_function("sel_registerName") is UOp.custom_function("sel_registerName"))
print("cf_dtype_splits_cache=", UOp.custom_function("f") is not UOp.custom_function("f", dtypes.uint64))

# UPat.custom_function
p = UPat.custom_function("f")
print("pat_op=", p.op)
print("pat_arg_name=", p.arg.name)
print("pat_arg_dtype_void=", p.arg.dtype == dtypes.void)

# CallInfo lost its dtype field?
print("callinfo_fields=", ",".join(x.name for x in dataclasses.fields(CallInfo)))
print("callinfo_has_dtype=", any(x.name == "dtype" for x in dataclasses.fields(CallInfo)))

# the spec rule body
from tinygrad.uop import spec
import tinygrad.uop.ops as ops_mod
print("spec_has_CustomFunction_import=", getattr(spec, "CustomFunction", None) is CustomFunction)

# a CALL's dtype now comes from its body's arg
call = u2.call(b)
print("call_op=", call.op)
print("call_body_op=", call.body.op)
print("call_dtype_u64=", call.dtype == dtypes.uint64)
print("call_arg_is_CallInfo=", isinstance(call.arg, CallInfo))
cv = u.call(b)
print("call_void_dtype=", cv.dtype == dtypes.void)

# spec shared rule, read from the real table
sh = spec.spec_shared
r = sh.rules[21] if False else None

# --- what the two LEAF files that match Arg exhaustively need -------------
print("--- owner fixes ---")
print("repr_void=", repr(CustomFunction("sel_registerName")))
print("repr_u64=", repr(CustomFunction("sel_registerName", dtypes.uint64)))
print("is_int=", isinstance(CustomFunction("f"), int))
print("is_str=", isinstance(CustomFunction("f"), str))
print("uop_repr=", repr(UOp.custom_function("sel_registerName")))

# --- the sh_22 GATE ROWS, read from CPython's own spec_shared rewrite ----
def verdict(x):
  r = spec.spec_shared.rewrite(x)
  return {True:"1", False:"0", None:"9"}[r]

good = UOp.custom_function("sel_registerName")
bad  = UOp(Ops.CUSTOM_FUNCTION, arg="sel_registerName")
print("--- sh_22 rows ---")
print("good_op=", good.op, "good_nsrc=", len(good.src), "good_dt=", good.dtype)
print("bad_op=", bad.op, "bad_nsrc=", len(bad.src), "bad_dt=UNREADABLE(arg.dtype)")
print("good_verdict=", verdict(good))
print("bad_verdict=", verdict(bad))
# what the PIN's rule would have said, from the pin's own tree
import subprocess
pin = subprocess.run(["git","show","6c3d401cf324:tinygrad/uop/spec.py"],capture_output=True,text=True).stdout
i = pin.find("Ops.CUSTOM_FUNCTION, name=\"x\"")
print("pin_rule=", " ".join(pin[i:i+130].split()))
