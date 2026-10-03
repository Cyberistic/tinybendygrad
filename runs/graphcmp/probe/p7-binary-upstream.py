import os
os.environ["DEV"]="CPU"
from tinygrad.uop.ops import UOp, Ops
b1 = UOp(Ops.BINARY, (), b"aaaa")
b2 = UOp(Ops.BINARY, (), b"bbbb")
print("b1 is b2 :", b1 is b2)
print("b1.key == b2.key :", b1.key == b2.key)
print("b1.unique_num/b2 :", b1.unique_num, b2.unique_num)
print("b1.argstr/b2     :", b1.argstr(), b2.argstr())
print("shapes           :", b1.shape, b2.shape, "dtypes:", b1.dtype.name, b2.dtype.name)
print("toposort b1      :", [n.op.name for n in b1.toposort()])
# and a repeated IDENTICAL blob, which upstream also interns
b3 = UOp(Ops.BINARY, (), b"aaaa")
print("b1 is b3 (same bytes) :", b1 is b3, "unique_num:", b3.unique_num)
