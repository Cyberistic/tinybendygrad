import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from tinygrad.dtype import dtypes, DType, AddrSpace, truncate
from tinygrad.uop.ops import Ops, UOp, ParamArg
from tinygrad.renderer import wgsl as W
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.helpers import Target
R = WGSLRenderer(Target(device="", renderer="wgpu", arch=""))
def row(nm, v): print(f"{nm} = {v!r}")

# type_map
ALIAS = {"unsigned char":"uchar","unsigned short":"ushort","signed char":"char","unsigned int":"uint","unsigned long":"ulong"}
def dt_of(n): return getattr(dtypes, ALIAS.get(n,n))
for n in ["float","uchar","ushort","short","char","int","uint","bool","half","long","ulong","bfloat16"]:
  row(f"type_map {n}", R.type_map.get(dt_of(n), "MISSING"))

# render_cast
for n in ["unsigned char","unsigned short","signed char","short","int","unsigned int","float","half","bool"]:
  row(f"render_cast {n}", R.render_cast(UOp(Ops.CAST, (UOp.const(0),), dt_of(n)), "V"))

# _render_dtype
for dt in [dtypes.f32, dtypes.f16, dtypes.i32, dtypes.u32, dtypes.bool]:
  row(f"_render_dtype {dt.name}", R._render_dtype(dt))
row("_render_dtype float sz2", R._render_dtype(dtypes.f32, sz=2))
row("_render_dtype float global", R._render_dtype(dtypes.f32, addrspace=AddrSpace.GLOBAL))
row("render_dtype float", R.render_dtype(dtypes.f32))

# packed_field
for n in ["uchar","char","ushort","short","half","int"]:
  dt = dt_of(n)
  row(f"packed_field {n} elems", 4//dt.itemsize)
  row(f"packed_field {n} width", 8*dt.itemsize)
  row(f"packed_field {n} mask", (1<<(8*dt.itemsize))-1)

# wmask
for mask, shift in [(255,0),(255,8),(255,16),(255,24),(65535,0),(65535,16)]:
  row(f"wmask {mask}<<{shift}", ((mask<<shift) ^ 0xFFFFFFFF))

# is_nan constants
for n in ["float","half","bfloat16","double"]:
  dt = dt_of(n); bs, (e,m) = dt.bitsize, dtypes.finfo(dt)
  row(f"is_nan {n} bs", bs); row(f"is_nan {n} exp", e); row(f"is_nan {n} mant", m)
  row(f"is_nan {n} mask", (1<<(bs-1))-1); row(f"is_nan {n} thr", ((1<<e)-1)<<m)

# code_for_op
for op in ["SQRT","RECIPROCAL","NEG","EXP2","LOG2","SIN","TRUNC","AND","XOR","OR","ADD","SUB","MUL","CMOD","CDIV","CMPNE","SHR","SHL","CMPLT","WHERE","CMPEQ"]:
  f = R.code_for_op[getattr(Ops, op)]
  row(f"code_for_op {op}", f("A","B","C",dtypes.f32) if op=="WHERE" else (f("A", dtypes.f32) if op in ("SQRT","RECIPROCAL","NEG","EXP2","LOG2","SIN","TRUNC") else f("A","B",dtypes.f32)))

# code_for_workitem
for k in ["g","l"]:
  for x in range(3): row(f"workitem {k}{x}", R.code_for_workitem[k](x))

# buf_map / is_packed on a buf uop
for n in ["uchar","char","ushort","short","half","float","int","uint"]:
  dt = dt_of(n)
  b = UOp(Ops.BUFFER, src=(UOp.range(16,0),), arg=ParamArg(0, dt, 16, device="CPU", addrspace=AddrSpace.GLOBAL))
  row(f"buf_map {n}", R.buf_map(b))
  row(f"is_packed {n}", W.is_packed(b))
  row(f"packed_size {n} 16", W._packed_size(b))
  b2 = UOp(Ops.BUFFER, src=(UOp.range(17,0),), arg=ParamArg(0, dt, 17, device="CPU", addrspace=AddrSpace.GLOBAL))
  row(f"packed_size {n} 17", W._packed_size(b2))
  b3 = UOp(Ops.BUFFER, src=(UOp.range(16,0),), arg=ParamArg(0, dt, 16, device="CPU", addrspace=AddrSpace.REG))
  row(f"is_packed {n} REG", W.is_packed(b3))
  row(f"is_packed {n} LOCAL", W.is_packed(UOp(Ops.BUFFER, src=(UOp.range(16,0),), arg=ParamArg(0, dt, 16, device="CPU", addrspace=AddrSpace.LOCAL))))

row("global_max", R.global_max); row("local_max", R.local_max)
row("barrier", R.barrier); row("nan", R.nan); row("supports_float4", R.supports_float4)
row("supported_dtypes noarch", sorted(d.name for d in R.supported_dtypes()))
R2 = WGSLRenderer(Target(device="", renderer="wgpu", arch="shader-f16"))
row("supported_dtypes f16", sorted(d.name for d in R2.supported_dtypes()))
