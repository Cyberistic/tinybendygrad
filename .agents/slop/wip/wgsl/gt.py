import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from tinygrad import Tensor, dtypes
from tinygrad.helpers import Target
from tinygrad.codegen import to_program
from tinygrad.renderer.wgsl import WGSLRenderer
D = "CPU"
def ren(arch=""): return WGSLRenderer(Target(device="", renderer="wgpu", arch=arch))
def render(fn, arch=""):
  lin = fn().schedule_linear()
  r = ren(arch); outs = []
  for call in lin.src:
    for a in call.src:
      if a.op.name == "SINK":
        outs.append(str(to_program(a, r).src[-1].arg))
  return "\n".join(outs)
def show(tag, text):
  for line in text.split("\n"): print(f"[{tag}] {line}")
def k_alu():
  a = Tensor([1.0,2.0,3.0,4.0], device=D).realize(); b = Tensor([5.0,6.0,7.0,8.0], device=D).realize(); return a+b
def k_where():
  a = Tensor([1.0,2.0,3.0,4.0], device=D).realize(); b = Tensor([5.0,6.0,7.0,8.0], device=D).realize(); return (a>b).where(a,b)
def k_half():
  a = Tensor([1.0,2.0,3.0,4.0], dtype=dtypes.f16, device=D).realize(); b = Tensor([5.0,6.0,7.0,8.0], dtype=dtypes.f16, device=D).realize(); return a+b
def k_packed():
  a = Tensor(list(range(16)), device=D).cast(dtypes.u8).realize(); b = Tensor(list(range(16)), device=D).cast(dtypes.u8).realize(); return a+b
def k_pchar():
  a = (Tensor(list(range(16)), device=D)-8).cast(dtypes.i8).realize(); b = (Tensor(list(range(16)), device=D)-8).cast(dtypes.i8).realize(); return a+b
def k_narrow():
  a = Tensor([1,2,3,4], dtype=dtypes.i8, device=D).realize(); b = Tensor([5,6,7,8], dtype=dtypes.i16, device=D).realize(); return (a+b).cast(dtypes.i32)
def k_nan():
  a = Tensor([1.0,2.0,3.0,4.0], device=D).realize(); return (a==a)+(a!=a)
def k_sum():
  a = Tensor([1.0,2.0,3.0,4.0], device=D).realize(); return a.sum().contiguous()
FIX = [("alu",k_alu,""),("where",k_where,""),("half",k_half,"shader-f16"),("packed",k_packed,""),
       ("pchar",k_pchar,""),("narrow",k_narrow,""),("nan",k_nan,""),("sum",k_sum,"")]
want = sys.argv[1] if len(sys.argv)>1 else "all"
for tag, fn, arch in FIX:
  if want in ("all",tag): show(tag, render(fn, arch))
