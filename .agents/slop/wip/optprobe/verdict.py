import os, sys, json
os.environ["DEV"]="PYTHON"; os.environ["CACHELEVEL"]="0"
import tinygrad.codegen.opt.postrange as PR
from tinygrad.codegen.opt.search import actions
from tinygrad.uop.ops import Ops, AxisType
from tinygrad.helpers import prod, Context
GOT=[]
orig=PR.apply_opts
def patched(ast,ren,beam=0):
  if ast.tag is not None: return ast
  k=PR.Scheduler(ast,ren); k.convert_loop_to_global()
  rows=[]
  for i,a in enumerate(actions):
    if a.axis is not None and a.op.name != "TC":
      if a.axis >= k.shape_len: rows.append((i+1,"AXIS")); continue
    s2=k.copy()
    try:
      s2.apply_opt(a)
    except PR.KernelOptError as e:
      rows.append((i+1,"ERR:"+str(e)[:40])); continue
    up,lcl,tcup=1,1,next((prod(u.arg[0])//u.arg[2] for u in s2.ast.backward_slice if u.op is Ops.WMMA),1)
    for x,t in zip(s2.full_shape,s2.axis_types):
      if t in (AxisType.UPCAST,AxisType.UNROLL): up*=x
      elif t in (AxisType.WARP,AxisType.LOCAL): lcl*=x
    rows.append((i+1,"OK" if not (up//tcup>256 or lcl>1024) else "LIMITS"))
  GOT.append(rows); return ast
PR.apply_opts=patched
import tinygrad.codegen as CG; CG.apply_opts=patched
from tinygrad import Tensor
with Context(BEAM=0):
  c=sys.argv[1]
  if c=="plus": a=Tensor([1.0,2.0,3.0,4.0]).contiguous().realize(); (a+1).realize()
  else: a=Tensor.empty(16,32).realize(); b=Tensor.empty(16,32).realize(); (a*b).sum(axis=1).realize()
for i,st in GOT[0]:
  if not st.startswith("ERR:") and st!="AXIS": print(i, st, actions[i-1])
print("--- errors on axis 1 ---")
for i,st in GOT[0]:
  if st.startswith("ERR:") and actions[i-1].axis==1: print(i, st, actions[i-1])
