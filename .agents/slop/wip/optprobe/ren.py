import os
os.environ["DEV"]="PYTHON"; os.environ["CACHELEVEL"]="0"
import tinygrad.codegen.opt.postrange as PR
orig=PR.apply_opts
seen=[]
def patched(ast,ren,beam=0):
  if ast.tag is not None: return ast
  seen.append((type(ren).__name__, ren.target.device, ren.has_local, ren.has_shared, ren.shared_max, len(ren.tensor_cores)))
  return ast
PR.apply_opts=patched
import tinygrad.codegen as CG; CG.apply_opts=patched
from tinygrad import Tensor
a = Tensor([1.0,2.0,3.0,4.0]).contiguous().realize(); (a+1).realize()
for s in seen: print(s)
