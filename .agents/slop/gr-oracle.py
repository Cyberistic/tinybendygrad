"""The CPython oracle for tinybendygrad/codegen/__init__.bend.

Runs CPython's `pm_post_sched_cache.rewrite` on a fixture:
  SINK[PARAM{slot=0}, PARAM{slot=1}, ALLOC{slot=0}]
with ctx = [A, B] (two dummy UOps).

Prints the same shape the port prints: one line per toposort node,
`old->new`. The diff against the port's output is the gate.

The port's output is `new_sink=N repl=old1->new1,old2->new2,...`. The
CPython output uses the same convention. We don't try to print Python
`id()`; we print the UOp's op and arg, which is comparable.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad.uop.ops import UOp, Ops, RewriteContext
from tinygrad.dtype import dtypes
from tinygrad.schedule import pm_post_sched_cache


def uop_short(u: UOp) -> str:
  """A short printable form of a UOp: op name + arg (slot for PARAM)."""
  if u.op == Ops.PARAM:
    if hasattr(u.arg, 'slot'):
      return f"PARAM(slot={u.arg.slot})"
    return f"PARAM(arg={u.arg})"
  if u.op == Ops.ALLOC:
    return "ALLOC"
  if u.op == Ops.SINK:
    return "SINK"
  if u.op == Ops.BUFFER:
    return f"BUFFER(slot={u.arg.slot if hasattr(u.arg, 'slot') else '?'})"
  return f"{u.op.name}"


def main():
  from tinygrad.uop.ops import ParamArg
  # Two dummy PARAMs with placeholder slots 99 and 100. These are
  # the "A" and "B" in the ctx. Set device=PYTHON (the default
  # device) so `create_new_buffer` can resolve a device for the
  # ALLOC's BUFFER.
  ca = UOp(Ops.PARAM, arg=ParamArg(99, dtypes.int32, device="PYTHON"))
  cb = UOp(Ops.PARAM, arg=ParamArg(100, dtypes.int32, device="PYTHON"))
  ctx = ({}, (ca, cb))

  p0 = UOp(Ops.PARAM, arg=ParamArg(0, dtypes.int32, device="PYTHON"))
  p1 = UOp(Ops.PARAM, arg=ParamArg(1, dtypes.int32, device="PYTHON"))
  # ALLOC needs a max_shape and dtype for `create_new_buffer` to
  # build a BUFFER. Use shape=(1,) and dtype=int32, device=PYTHON.
  alloc = UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")

  sink = UOp(Ops.SINK, src=(p0, p1, alloc))
  rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
  new_sink = rc.walk_rewrite(sink)

  # Print the same shape as the port.
  # new_sink: the rebuilt SINK.
  print(f"new_sink_op={new_sink.op.name}")
  # repl: each entry in rc.replace, as `old_short->new_short`.
  entries = []
  for old, new in rc.replace.items():
    entries.append(f"{uop_short(old)}->{uop_short(new)}")
  print("repl=" + ",".join(entries))


if __name__ == "__main__":
  main()
