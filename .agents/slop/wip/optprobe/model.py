# The guard model I will port to Bend: apply_opt's `check` LAYER + get_kernel_actions' guards,
# expressed on (full_shape, axis_types, ren) only -- no AST mutation.
import itertools
from tinygrad.uop.ops import Ops, AxisType
from tinygrad.helpers import prod
from tinygrad.codegen.opt.search import actions
split_targets = {AxisType.UPCAST: (AxisType.GLOBAL, AxisType.LOCAL, AxisType.WEAK),
                 AxisType.UNROLL: (AxisType.REDUCE, AxisType.LOCAL),
                 AxisType.LOCAL: (AxisType.GLOBAL, AxisType.WEAK, AxisType.REDUCE)}
def zero_variant(a):
  # replace(a, arg=(0,)+arg[1:]) in actions
  if a.op.name != "SPLIT" or not isinstance(a.arg, tuple): return False
  z = type(a)(op=a.op, axis=a.axis, arg=(0,)+tuple(a.arg)[1:])
  return z in actions

def opt_ok(fs, at, opt, ren):
  """every `check()` in postrange.apply_opt, as a Bool"""
  n = len(fs)
  if opt.op.name == "TC":
    if opt.axis is None or opt.axis < 0: return False
    if not (-1 <= opt.arg[0] < len(ren.tensor_cores)): return False
    if not (0 <= opt.arg[1] <= 2): return False
    if not (0 < opt.arg[2] <= 2): return False
    # _apply_tc_opt: needs reduceops, ADD, MUL under it -> we cannot see that here
    return "TC-UNKNOWN"
  if not (0 <= opt.axis < n): return False
  if opt.op.name == "SPLIT":
    amt, new_type, top = (*opt.arg, False)[0:3]
    if not (isinstance(amt, int) and (amt == 0 or amt > 1)): return False
    if new_type not in split_targets: return False
    if not isinstance(top, bool): return False
    if new_type is AxisType.LOCAL and not ren.has_local: return False
    if amt == 0: amt = fs[opt.axis]
    if new_type is AxisType.UNROLL and amt > 32: return False
    if new_type is AxisType.UPCAST and not (ren.target.device == "DSP" or amt <= 16): return False
    # `old_sz = rng.src[0].divides(amount)` is None -> KernelOptError
    if amt > 0 and fs[opt.axis] % amt != 0: return False
    if new_type is AxisType.UNROLL or at[opt.axis] is AxisType.REDUCE:
      # must be parented by some REDUCE.  An axis is in a reduce iff some axis_type is REDUCE
      if not any(t is AxisType.REDUCE for t in at): return False
      if new_type is AxisType.LOCAL:
        # check(not any(u.axis_type in (REDUCE,UNROLL) for u in reduces[0].ranges)) -- for the single-reduce case
        if any(t is AxisType.REDUCE for t in at): return False
    return True
  if opt.op.name == "PADTO":
    if not (isinstance(opt.arg, int) and opt.arg > 1): return False
    if at[opt.axis] in (AxisType.UPCAST, AxisType.UNROLL): return False
    return True
  if opt.op.name == "SWAP":
    if not (0 <= opt.arg < n): return False
    if at[opt.axis] is not AxisType.GLOBAL or at[opt.arg] is not AxisType.GLOBAL: return False
    return True
  return False

def count(fs, at, ren, include_0, max_up=256, max_lcl=1024):
  out = []
  for i, a in enumerate(actions):
    if a.axis is not None and a.op.name != "TC":
      if a.axis >= len(fs) or (a.op.name == "SPLIT" and isinstance(a.arg, tuple) and fs[a.axis] == a.arg[0] and zero_variant(a)): continue
    r = opt_ok(fs, at, a, ren)
    if r is "TC-UNKNOWN":
      continue
    if not r: continue
    out.append(i+1)
  return len(out)

from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.helpers import Target
from tinygrad import Device
from tinygrad.runtime.ops_python import PythonRenderer
ren = PythonRenderer(Target("PYTHON", arch="x86_64,native"))
for name, fs, at in [("plus",[4],["GLOBAL"]), ("reduce",[16,32],["GLOBAL","REDUCE"]),
                     ("matmul",[64,64,64],["GLOBAL","GLOBAL","REDUCE"])]:
  fsl = [int(x) for x in fs]
  atl = [getattr(AxisType, x) for x in at]
  print(name, "n0 =", count(fsl, atl, ren, True), " n =", count(fsl, atl, ren, False))

def accepted(fs, at, ren):
  out=[]
  for i,a in enumerate(actions):
    if a.axis is not None and a.op.name != "TC":
      if a.axis >= len(fs) or (a.op.name == "SPLIT" and isinstance(a.arg,tuple) and fs[a.axis]==a.arg[0] and zero_variant(a)): continue
    r = opt_ok(fs, at, a, ren)
    if r == "TC-UNKNOWN" or not r: continue
    out.append(i+1)
  return out
print("plus mine", accepted([4],[AxisType.GLOBAL],ren))
print("reduce mine", accepted([16,32],[AxisType.GLOBAL,AxisType.REDUCE],ren))
print("matmul mine", accepted([64,64,64],[AxisType.GLOBAL,AxisType.GLOBAL,AxisType.REDUCE],ren))
