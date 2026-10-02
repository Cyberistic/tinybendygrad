import sys, os, json
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import Ops, UOp
from tinygrad.dtype import AddrSpace
from tinygrad.helpers import Target
from tinygrad.codegen import to_program
from tinygrad.renderer import wgsl as W
from tinygrad.renderer.wgsl import WGSLRenderer
D = "CPU"

class Spy(WGSLRenderer):
  def render_kernel(self, function_name, kernel, bufs, uops, prefix=None):
    rec = {"fn": function_name, "kernel": list(kernel),
           "bufs": [{"name": n, "addrspace": u.addrspace.name, "packed": W.is_packed(u),
                     "dt": u.dtype.name, "numel": u.max_numel(), "mutable": m} for n,(u,m) in bufs],
           "local_size": [str(u.src[0]) for u in sorted([u for u in uops if u.op is Ops.SPECIAL and u.arg[0]=='l'], key=lambda u: u.arg)],
           "any_half": any(u.dtype == dtypes.f16 for u in uops), "n": len(uops)}
    print("RENDER_KERNEL_JSON " + json.dumps(rec))
    return super().render_kernel(function_name, kernel, bufs, uops, prefix)

def run(fn, arch=""):
  lin = fn().schedule_linear()
  outs = []
  for call in lin.src:
    for a in call.src:
      if a.op.name == "SINK":
        outs.append(str(to_program(a, Spy(Target(device="", renderer="wgpu", arch=arch))).src[-1].arg))
  return outs

def k_alu():
  a = Tensor([1.0,2.0,3.0,4.0], device=D).realize(); b = Tensor([5.0,6.0,7.0,8.0], device=D).realize(); return a+b
def k_packed():
  a = Tensor(list(range(16)), device=D).cast(dtypes.u8).realize(); b = Tensor(list(range(16)), device=D).cast(dtypes.u8).realize(); return a+b
def k_narrow():
  a = Tensor([1,2,3,4], dtype=dtypes.i8, device=D).realize(); b = Tensor([5,6,7,8], dtype=dtypes.i16, device=D).realize(); return (a+b).cast(dtypes.i32)

if __name__ == "__main__":
  for tag, fn, arch in [("alu",k_alu,""),("packed",k_packed,""),("narrow",k_narrow,"")]:
    for i, o in enumerate(run(fn, arch)): print(f"[{tag}{i}] {o}")
