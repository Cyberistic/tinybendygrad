import os, sys, json
os.environ["DEV"] = "PYTHON"
os.environ["IGNORE_BEAM_CACHE"] = "1"
os.environ["CACHELEVEL"] = "0"
import tinygrad.codegen.opt.postrange as PR
from tinygrad.codegen.opt.search import get_kernel_actions, actions
from tinygrad.helpers import Context
ROWS = []
orig = PR.apply_opts
def patched(ast, ren, beam=0):
  if ast.tag is not None: return ast
  k = PR.Scheduler(ast, ren)
  k.convert_loop_to_global()
  ROWS.append(dict(fs=[str(x) for x in k.full_shape], at=[str(x).split(".")[1] for x in k.axis_types],
                   n0=len(get_kernel_actions(k, include_0=True)), n=len(get_kernel_actions(k, include_0=False))))
  return ast   # STOP HERE: no search, no heuristic
PR.apply_opts = patched
import tinygrad.codegen as CG
CG.apply_opts = patched
from tinygrad import Tensor
with Context(BEAM=0):
  case = sys.argv[1]
  if case == "plus":
    a = Tensor([1.0,2.0,3.0,4.0]).contiguous().realize(); (a+1).realize()
  elif case == "reduce":
    a = Tensor.empty(16,32).realize(); b = Tensor.empty(16,32).realize(); (a*b).sum(axis=1).realize()
  elif case == "matmul":
    a = Tensor.empty(64,64).realize(); b = Tensor.empty(64,64).realize(); (a@b).realize()
  elif case == "conv":
    a = Tensor.empty(32,3,3,3).realize(); b = Tensor.empty(8,3,3,3).realize(); (a@b).sum(axis=(0,1)).realize()
for r in ROWS: print(json.dumps(r))
