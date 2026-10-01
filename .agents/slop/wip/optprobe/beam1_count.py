import os, sys, json
os.environ["DEV"] = "PYTHON"
os.environ["IGNORE_BEAM_CACHE"] = "1"
os.environ["CACHELEVEL"] = "0"
import tinygrad.codegen.opt.postrange as PR
import tinygrad.codegen.opt.search as SR
from tinygrad.helpers import Context

CNT = {"compile":0, "compile_ok":0, "time":0, "time_ok":0, "rounds":0}
orig_tc = SR._try_compile
def tc(x):
  CNT["compile"] += 1
  r = orig_tc(x)
  if r[1] is not None: CNT["compile_ok"] += 1
  return r
SR._try_compile = tc
orig_tp = SR._time_program
def tp(*a, **k):
  CNT["time"] += 1
  CNT["time_ok"] += 1
  return orig_tp(*a, **k)
SR._time_program = tp
orig_bs = SR.beam_search
def bs(s, *a, **k):
  CNT["rounds"] += 1
  return orig_bs(s, *a, **k)
SR.beam_search = bs

CAP = {}
orig = PR.apply_opts
def patched(ast, ren, beam=0):
  if ast.tag is not None: return ast
  k = PR.Scheduler(ast, ren)
  k.convert_loop_to_global()
  CAP.setdefault("shape_len", k.shape_len)
  CAP.setdefault("full_shape", [str(x) for x in k.full_shape])
  CAP.setdefault("axis_types", [str(x) for x in k.axis_types])
  return orig(ast, ren, beam=beam)
PR.apply_opts = patched
import tinygrad.codegen as CG
CG.apply_opts = patched

from tinygrad import Tensor
case = sys.argv[2] if len(sys.argv)>2 else "plus"
with Context(BEAM=1):
  if case == "plus":
    a = Tensor([1.0,2.0,3.0,4.0]).contiguous().realize()
    print("result", (a+1).realize().tolist())
  elif case == "reduce":
    a = Tensor.empty(16,32).realize(); b = Tensor.empty(16,32).realize()
    print("result", (a*b).sum(axis=1).realize().tolist()[:3])
  elif case == "matmul":
    a = Tensor.empty(64,64).realize(); b = Tensor.empty(64,64).realize()
    print("result", (a@b).realize().tolist()[0][:2])
print("CAP", json.dumps(CAP))
print("CNT", json.dumps(CNT))
