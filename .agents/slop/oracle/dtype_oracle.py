import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad.dtype import dtypes, commit_int, strong_dtype, weak_dtype
from tinygrad.uop.ops import UOp, Ops

print("== strong_dtype")
for nm in ["weakint","weakfloat","int32","half","bool","uint8","int64","double","bfloat16"]:
  print(" strong_%s=%s" % (nm, strong_dtype(getattr(dtypes, nm))))

print("== DType.min / DType.max (64-bit dtypes shown as python ints)")
for nm in ["void","weakint","bool","int8","uint8","int16","uint16","int32","uint32","int64","uint64","weakfloat","half","single","double"]:
  d = getattr(dtypes, nm)
  print(" lim_%s=%r,%r" % (nm, d.min, d.max))

print("== commit_int  (lo,hi,default_int_or_None) -> dtype   [OVERFLOW=raise]")
CASES = [
  (0, 0, None), (0, 255, None), (-1, 1, None), (0, 127, None), (0, 128, None),
  (-(2**31), 2**31-1, None), (-(2**31)-1, 0, None), (0, 2**31, None),
  (-(2**62), 2**62, None), (-(2**63), 2**63-1, None), (0, 2**63-1, None),
  (0, 2**63, None), (-1, 2**64-1, None), (0, 2**64-1, None), (0, 2**64, None),
  (0, 127, "int8"), (0, 128, "int8"), (-1, 0, "int8"), (-128, 127, "int8"),
  (0, 255, "uint8"), (-1, 255, "uint8"), (0, 65535, "uint16"), (-32768, 32767, "int16"),
  (0, 2**32-1, "uint32"), (-(2**31), 2**31, "int32"), (0, 2**63, "long"), (0, 2**63, "uint64"),
  (2**63, 2**63, None), (2**64, 2**64, None), (-(2**64), -(2**64), None),
  (-5, -5, None), (-5, -5, "int8"),
]
for lo, hi, di in CASES:
  dd = None if di is None else getattr(dtypes, di)
  try:
    print(" ci=%d,%d,%s->%s" % (lo, hi, "None" if di is None else di, commit_int(lo, hi, dd)))
  except OverflowError as e:
    print(" ci=%d,%d,%s->OVERFLOW" % (lo, hi, "None" if di is None else di))

print("== commit_dtype through the mixin (weakint vs strong)")
for nm, lo, hi in [("weakint",0,255),("weakint",0,2**40),("weakint",0,2**63),("weakfloat",0,255),("half",0,255),("bool",0,255),("int8",0,255)]:
  d = getattr(dtypes, nm)
  u = UOp(Ops.CONST, arg=d.const(lo), src=()) if nm in ("weakint","weakfloat","half","bool","int8") else None
  if u is None: continue
  class M: pass
  m = M(); m._uop = u; m.dtype = d
  from tinygrad.mixin import DTypeMixin
  class T(DTypeMixin):
    @property
    def dtype(self): return d
    @property
    def _uop(self): return u
    @classmethod
    def _wrap_uop(cls, u): return u
  print(" cd_%s=%s" % (nm, T().commit_dtype()))

print("== element_size / is_floating_point")
for nm in ["int16","bool","half","single","int64","fp8e4m3"]:
  d = getattr(dtypes, nm)
  print(" es_%s=%s fp_%s=%s" % (nm, d.itemsize, nm, dtypes.is_float(d)))

print("== to_dtype")
for s in ["int32","uint8","float16","bfloat16","bool","float","half","long","short","double","float32","float64"]:
  print(" td_%s=%s" % (s, to_dtype_x(s)) if False else " td_%s=%s" % (s, getattr(dtypes, s.lower())))

print("== weaks / is_weaks")
print(" weaks=%s" % (dtypes.weaks,))
