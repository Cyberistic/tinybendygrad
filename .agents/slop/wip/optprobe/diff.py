import os, sys
os.environ["DEV"]="PYTHON"; os.environ["CACHELEVEL"]="0"
import tinygrad.codegen.opt.postrange as PR
from tinygrad.codegen.opt.search import get_kernel_actions
from tinygrad.helpers import Context
GOT=[]
orig=PR.apply_opts
def patched(ast,ren,beam=0):
  if ast.tag is not None: return ast
  k=PR.Scheduler(ast,ren); k.convert_loop_to_global()
  d=get_kernel_actions(k,include_0=False)
  GOT.append(([str(x) for x in k.full_shape],[str(x) for x in k.axis_types],sorted(d.keys())))
  return ast
PR.apply_opts=patched
import tinygrad.codegen as CG; CG.apply_opts=patched
from tinygrad import Tensor
with Context(BEAM=0):
  c=sys.argv[1]
  if c=="plus": a=Tensor([1.0,2.0,3.0,4.0]).contiguous().realize(); (a+1).realize()
  elif c=="reduce": a=Tensor.empty(16,32).realize(); b=Tensor.empty(16,32).realize(); (a*b).sum(axis=1).realize()
  else: a=Tensor.empty(64,64).realize(); b=Tensor.empty(64,64).realize(); (a@b).realize()
from tinygrad.codegen.opt.search import actions
fs,at,keys=GOT[0]
print("fs",fs,"at",at)
print("accepted",keys)
for i in keys: print("  ",i,actions[i-1])
