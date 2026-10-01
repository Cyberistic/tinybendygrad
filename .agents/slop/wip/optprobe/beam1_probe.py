import os
os.environ["DEV"] = "PYTHON"
os.environ["IGNORE_BEAM_CACHE"] = "1"
os.environ["CACHELEVEL"] = "0"
from tinygrad import Tensor, Device
from tinygrad.uop.ops import Ops, AxisType
from tinygrad.codegen.opt.search import actions, get_kernel_actions
from tinygrad.codegen.opt.postrange import Scheduler
from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.renderer import Renderer
from tinygrad.helpers import Target

ren = ClangRenderer(Target(Device.DEFAULT, arch="x86_64,native"))
print("tensor_cores", ren.tensor_cores)
print("n_actions", len(actions))

# build a real kernel ast: reduce
a = Tensor.empty(16, 32).realize()
b = Tensor.empty(16, 32).realize()
k = (a * b).sum(axis=1).uop
print("k op", k.op)
sched = Scheduler(k, ren)
print("shape_len", sched.shape_len)
print("full_shape", sched.full_shape)
print("axis_types", sched.axis_types)
acts = get_kernel_actions(sched, include_0=True)
print("n_acted_incl0", len(acts))
acts0 = get_kernel_actions(sched, include_0=False)
print("n_acted_excl0", len(acts0))
print("reduce_axes", sched.reduce_axes)
print("upcastable_dims", sched.upcastable_dims)
print("unrollable_dims", sched.unrollable_dims)
