# graphcmp-p14e.py -- Q3 ONLY: does the REAL `pm_linearize_cleanups` mint IF/ENDIF from a
# gated STORE? And what does the resulting LINEAR node look like?
#
# `pm_to_program` (codegen/__init__.py:426) calls
#   line_rewrite(linearize(sink), pm_linearize_cleanups+pm_alloc_to_buf)
# and wraps the result in a `LINEAR` node. So the ENDIF lives in the LINEAR's src list.
from tinygrad import Device
from tinygrad.uop.ops import UOp, Ops, KernelInfo, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.codegen import line_rewrite, pm_linearize_cleanups
from tinygrad.codegen.late.linearizer import linearize
from tinygrad.helpers import Context
import collections

print("# DEV =", Device.DEFAULT)


def census(tag, ts):
  c = collections.Counter(u.op.name for u in ts)
  print(f"# {tag:22s} nodes={len(ts):3d} " + " ".join(
      f"{k}={c[k]}" for k in ("IF", "ENDIF", "BACKEDGE", "END", "LOAD", "STORE", "INDEX",
                              "RANGE", "PARAM", "BUFFER", "LINEAR") if c[k]))


def gated_kernel():
  buf = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.float, 16, device="CPU"))
  val = UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.float, 16, device="CPU", name="v0"))
  r = UOp.range(4, 0)
  gate = r < UOp.const(3)
  st = buf.index(r).store(val.index(r), gate).end(r)
  return st.sink(arg=KernelInfo(name="gated"))


with Context(SPEC=1, DEBUG=0):
  sk = gated_kernel()
  print("# gated sink srcs:", [s.op.name for s in sk.src])
  lst = linearize(sk)
  print("# linearize ->", [(u.op.name, [s.op.name for s in u.src]) for u in lst])
  out = line_rewrite(lst, pm_linearize_cleanups)
  flat = list(out)
  for u in out:
    flat += [s for s in u.src if isinstance(s, UOp)]
  census("after pm_linearize", flat)
  print("# pm_to_program's LINEAR:")
  print("#   " + str(UOp(Ops.LINEAR, src=tuple(out))))
  print("# toposort of LINEAR:")
  lin = UOp(Ops.LINEAR, src=tuple(out))
  for u in lin.toposort():
    print(f"#   {u.op.name:10s} dtype={str(u.dtype):8s} arg={str(u.arg)[:44]:46s} src={[s.op.name for s in u.src]}")