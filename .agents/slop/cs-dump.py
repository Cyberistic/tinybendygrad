#!/usr/bin/env python3
# cs-dump.py -- print the arena of every renderer-oracle fixture, node by node,
# so tinybendygrad/renderer/cstyle.bend can build the SAME uop list in the SAME
# order.  `_render` walks the list in order and the emitted text depends on the
# order (bufs order, counter `c[prefix]`, depth), so a fixture that differs in
# order is a different kernel.
import sys
sys.path.insert(0, '.')
sys.path.insert(0, '.agents/slop/tools')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops, KernelInfo, AxisType
import renderer_oracle as RO

def dump(nm, sinks):
  uops = UOp.sink(*sinks, arg=KernelInfo()).toposort()
  print(f"### {nm}  n={len(uops)}")
  for i, u in enumerate(uops):
    print(f"  {i:2d} {u.op.name:10s} dt={str(u.dtype):24s} as={getattr(u,'addrspace',None)} "
          f"shape={u._shape} src={[x.op.name for x in u.src]} arg={u.arg!r} tag={u.tag!r}")
  print()

for nm in ("f_load_store", "f_alu", "f_consts", "f_smem", "f_special", "f_range", "f_cast", "f_stack", "f_stack4"):
  dump(nm, getattr(RO, nm)())
