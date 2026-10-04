"""grw-oracle.py -- CPython's OWN answers for `graph_rewrite`'s two arms, on
the two fixtures the port gates, plus the ONE place the two disagree.

`graph_rewrite` dispatches on a single Bool (tinygrad/uop/ops.py:1890):

    return rewrite_ctx.walk_rewrite(sink) if walk else rewrite_ctx.unified_rewrite(sink)

so there are TWO arms and the port prints rows for both.  Two fixtures:

  F1  SINK[PARAM(0), PARAM(1), ALLOC]  ctx = [PARAM(99), PARAM(100), BUFFER]
      the FULL `pm_post_sched_cache` table (two rules, schedule/__init__.py:96-101)
  F2  SINK[ALLOC]                       ctx = [BUFFER]
      the ALLOC rule ALONE

F2 exists because of a MEASURED CRASH: CPython's `unified_rewrite` raises
`IndexError: tuple index out of range` on F1, at schedule/__init__.py:98 --
after the first pass the graph contains the dummy PARAM(99), the rule reads
`ctx[1][x.arg.slot]` with slot 99, and the ctx has two entries.  The port's
`pm_r_param_m` (`uop/ops.bend`, another unit's file) answers `None{}` for any
slot it does not name, so the port CONVERGES where CPython RAISES.  That is a
divergence in a RULE BODY and it is reported here rather than reconciled:
without F2 the fixpoint arm would have no CPython expectation at all, and a
green row with no oracle is the failure this project has paid for five times.

Nothing here is typed by hand except the row names.  Run it and read the
output.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad.uop.ops import RewriteContext, UOp, Ops, PatternMatcher, ParamArg, UPat  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.schedule import pm_post_sched_cache  # noqa: E402


def create_new_buffer(ctx, b):
  """schedule/__init__.py:90-94, verbatim, because it is the rule under test."""
  if (ret := ctx[0].get(b, None)) is None:
    device = b.device if b.device is not None else next(a.device for a in ctx[1] if a.device is not None)
    ctx[0][b] = ret = UOp.new_buffer(device, b.max_numel(), b.dtype)
  return ret


pm_alloc_only = PatternMatcher([(UPat(Ops.ALLOC, name="b"), create_new_buffer)])


def uop_short(u):
  """`OP(slot=N)` for a PARAM and the bare op name otherwise -- the same shape
  the port's `gr_show.node` prints, so the diff compares two printouts of one
  format rather than two formats."""
  if u.op == Ops.PARAM and hasattr(u.arg, 'slot'):
    return f"PARAM({u.arg.slot})"
  return u.op.name


def f1():
  ca = UOp(Ops.PARAM, arg=ParamArg(99, dtypes.int32, device="PYTHON"))
  cb = UOp(Ops.PARAM, arg=ParamArg(100, dtypes.int32, device="PYTHON"))
  ctx = ({}, (ca, cb))
  p0 = UOp(Ops.PARAM, arg=ParamArg(0, dtypes.int32, device="PYTHON"))
  p1 = UOp(Ops.PARAM, arg=ParamArg(1, dtypes.int32, device="PYTHON"))
  alloc = UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")
  return UOp(Ops.SINK, src=(p0, p1, alloc)), ctx, pm_post_sched_cache


def f2():
  alloc = UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")
  return UOp(Ops.SINK, src=(alloc,)), ({}, ()), pm_alloc_only


def repl(rc, order):
  parts = [f"{uop_short(u)}->{uop_short(rc.replace.get(u, u))}" for u in order]
  return ",".join(parts) + ", "


def arm(pfx, arm_name, field, sink, ctx, pm, walk):
  rc = RewriteContext(pm=pm, bpm=None, ctx=ctx, enter_calls=False)
  name = f"grw_{pfx}_{arm_name}"
  try:
    out = rc.walk_rewrite(sink) if walk else rc.unified_rewrite(sink)
  except Exception as e:
    print(f"{name}=RAISED:{type(e).__name__}")
    return
  # each driver keys `replace` by a different graph: the walk arm by the
  # ORIGINAL, the unified arm by the FINAL
  order = list(sink.toposort()) if walk else list(out.toposort())
  print(f"{name}_sink={out.op.name}")
  print(f"{name}_n={len(list(out.toposort()))}")
  print(f"{name}_mapn={len(rc.replace)}")
  print(f"{name}_repl={repl(rc, order)}")


def main():
  for fx, build in (("f1", f1), ("f2", f2)):
    sink, ctx, pm = build()
    arm(fx, "walk", "", sink, ctx, pm, True)
    arm(fx, "fix", "", sink, ctx, pm, False)


if __name__ == "__main__":
  main()