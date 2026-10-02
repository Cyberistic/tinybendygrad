import sys, os; sys.path.insert(0, os.getcwd())
from tinygrad.dtype import dtypes
from tinygrad.renderer import nir
from tinygrad.helpers import Target
SPEC={"unsigned char":"uint8","unsigned short":"uint16","unsigned int":"uint32","unsigned long":"uint64",
      "signed char":"int8","short":"int16","int":"int32","long":"int64","float8_e4m3":"fp8e4m3",
      "float8_e5m2":"fp8e5m2","float8_e4m3fnuz":"fp8e4m3fnuz","float8_e5m2fnuz":"fp8e5m2fnuz",
      "half":"half","__bf16":"bfloat16","float":"single","double":"double","bool":"boolean"}
def s_(cls, arch):
  s = object.__new__(cls); s.target = Target("", "", arch); return s
for lbl, cls, arch in [("nir", nir.NIRRenderer, "sm_86"), ("nak86", nir.NAKRenderer, "sm_86"),
                       ("nak53", nir.NAKRenderer, "sm_53"), ("nak52", nir.NAKRenderer, "sm_52"),
                       ("nak120", nir.NAKRenderer, "sm_120"), ("ir3", nir.IR3Renderer, "sm_86")]:
  print(lbl, arch, ",".join(sorted(SPEC[d.name] for d in cls.supported_dtypes(s_(cls, arch)))))
print("cfo nir", len(nir.NIRRenderer.code_for_op), ",".join(sorted(k.name for k in nir.NIRRenderer.code_for_op)))
print("cfo lvp", len(nir.LVPRenderer.code_for_op), ",".join(sorted(k.name for k in nir.LVPRenderer.code_for_op)))
print("aop order", ",".join(d.name for d in nir.aop))
print("u_aop order", ",".join(k.name for k in nir.u_aop))
print("s_aop order", ",".join(k.name for k in nir.s_aop))
print("f_aop order", ",".join(k.name for k in nir.f_aop))
