import os, sys, json
os.environ["DEV"] = "PYTHON"
os.environ["IGNORE_BEAM_CACHE"] = "1"
os.environ["CACHELEVEL"] = "0"
import tinygrad.codegen.opt.postrange as PR
from tinygrad.codegen.opt.search import actions, get_kernel_actions

CAP = {}
orig = PR.apply_opts
def patched(ast, ren, beam=0):
  if ast.tag is not None: return ast
  k = PR.Scheduler(ast, ren)
  k.convert_loop_to_global()
  CAP["shape_len"] = k.shape_len
  CAP["full_shape"] = [str(x) for x in k.full_shape]
  CAP["axis_types"] = [str(x) for x in k.axis_types]
  CAP["reduce_axes"] = k.reduce_axes
  CAP["upcastable_dims"] = k.upcastable_dims
  CAP["unrollable_dims"] = k.unrollable_dims
  CAP["upcasted"] = k.upcasted
  CAP["group_for_reduces"] = k.group_for_reduces
  CAP["has_local"] = k.ren.has_local
  CAP["has_shared"] = k.ren.has_shared
  CAP["n_bufs"] = len(k.bufs)
  CAP["n_reduceops"] = len(k.reduceops)
  CAP["n_wmma"] = len([u for u in k.ast.backward_slice if u.op.name=="WMMA"])
  CAP["n_tc_actions"] = len([a for a in actions if a.op.name=="TC"])
  a0 = get_kernel_actions(k, include_0=True)
  a1 = get_kernel_actions(k, include_0=False)
  CAP["n_acted_incl0"] = len(a0)
  CAP["n_acted_excl0"] = len(a1)
  CAP["tgt"] = k.ren.target.device
  return orig(ast, ren, beam=beam)
PR.apply_opts = patched
import tinygrad.codegen as CG
CG.apply_opts = patched

from tinygrad import Tensor
with __import__("tinygrad").helpers.Context(BEAM=int(sys.argv[1]) if len(sys.argv)>1 else 1):
  a = Tensor([1.0,2.0,3.0,4.0]).contiguous().realize()
  b = (a+1).realize()
  print("result", b.tolist())
print(json.dumps(CAP, indent=1))
