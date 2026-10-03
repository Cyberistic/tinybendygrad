import os
os.environ["DEV"]="CPU"
from tinygrad import Tensor
from tinygrad.uop.ops import UOp, Ops, ParamArg
t1 = Tensor.empty(4,3)
print("t1.uop.op:", t1.uop.op.name, "| arg:", t1.uop.arg)
print("  is ParamArg:", isinstance(t1.uop.arg, ParamArg), "slot:", getattr(t1.uop.arg,'slot','-'))
print("  graph:", [(n.op.name, type(n.arg).__name__, getattr(n.arg,'slot','-')) for n in t1.uop.toposort()])
t1.realize()
print("after realize:", [(n.op.name, type(n.arg).__name__, getattr(n.arg,'slot','-')) for n in t1.uop.toposort()])
t2 = Tensor.empty(3,5)
print("t2 graph:", [(n.op.name, getattr(n.arg,'slot','-')) for n in t2.uop.toposort()])
