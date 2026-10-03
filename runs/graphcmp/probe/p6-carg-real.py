import os, sys
os.environ["DEV"]="CPU"
import tinygrad
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, KernelInfo
from tinygrad.codegen.opt import Opt, OptOps
sys.path.insert(0, os.path.join(os.path.dirname(__file__),"..","..","..",".agents","slop"))
import graphcmp
graphcmp.load_tinygrad()
print("tree:", tinygrad.__file__)
print()
print("=== the REAL _carg on the objects a SINK arg can hold ===")
import enum
for o in (OptOps.TC, OptOps.SWAP, OptOps.SPLIT, OptOps.PADTO):
  try: t = graphcmp._carg(o)
  except Exception as e: t = f"*** CRASH {type(e).__name__}: {e}"
  print(f"  OptOps.{o.name:6} -> {t[:200]}")
print("  OptOps.TC.__dict__ :", getattr(OptOps.TC, '__dict__', 'ABSENT'))
print("  is enum.Enum       :", isinstance(OptOps.TC, enum.Enum))
print("  .name/.value       :", OptOps.TC.name, OptOps.TC.value)
print()
print("  Opt(TC,0,4)      -> CRASH (contains OptOps)" if False else "  (Opt render needs OptOps fixed first)")
print()
print("=== the SINK arg text today ===")
k = KernelInfo(name="k", applied_opts=(Opt(OptOps.TC,0,4),), opts_to_apply=(Opt(OptOps.SWAP),), beam=3)
try: print("  carg(SINK, k) =", graphcmp.carg(Ops.SINK, k)[:600])
except Exception as e: print("  carg(SINK, k) -> *** CRASH", type(e).__name__, e)
print()
print("=== the realized BUFFER ParamArg text today ===")
t = Tensor.empty(4,3); t.realize()
for n in t.uop.toposort():
  if n.op is Ops.BUFFER:
    print("  paramarg      =", graphcmp.paramarg(n.arg)[:400])
    break
