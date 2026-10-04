#!/usr/bin/env python3
"""CPython oracle for `UOp.expr` (tinygrad/uop/ops.py:1030).

    .venv/bin/python .agents/slop/ops-var-oracle.py

Four rows, one per ANSWER `expr` can give, because one row cannot tell a name
from a missing name from an arg that is not a `ParamArg` -- and those are three
different reasons CPython raises.

Every row is produced by CALLING the real `UOp.expr` on a real `UOp`. Nothing
here is a transcription of what the port prints: the port's four `vr_expr_*`
values are diffed against these bytes, so a shared misreading of ops.py:1030
would have to be made twice, independently, in two languages.
"""
import sys

from tinygrad import dtypes
from tinygrad.uop.ops import Ops, UOp, ParamArg, AddrSpace
from tinygrad.uop.spec import AxisType  # noqa: F401  (imported for parity with ops.py)

BOTTOM = UOp(Ops.NOOP)


def param(name):
  """A PARAM whose only interesting field is `name`; every other field default."""
  return UOp(Ops.PARAM, (), ParamArg(1, dtypes.int32, name=name), AxisType.LOOP)


def show(x):
  return "none" if x is None else f"some:{x}"


def expr_of(u):
  """CALL `UOp.expr` and map its refusal to the port's `Maybe`.

  `ops.py:1030` is `assert self.op in {Ops.PARAM, Ops.BUFFER}; return
  unwrap(self.arg.name)`. Two of the four fixtures make it REFUSE -- the CONST on
  the op assert, the unnamed PARAM on the `unwrap` -- and both raise
  `AssertionError` (measured, not assumed: `unwrap(None)` is itself an assert at
  tinygrad/helpers.py).

  The refusal is mapped to `none` because that is what the port's `Maybe` IS: this
  file's standing spelling for "CPython raises here", the same `None` `UOp.body`
  uses for its RuntimeError. A refusal is not a value, so it does not get a
  `some:` row -- but it is not a hole either, because a row that expects `none` and
  gets it is a row that FAILS if the port ever starts answering a name where
  CPython refuses.

  This calls the real def. An earlier draft reimplemented the two-line body here,
  which is the failure this project's oracles exist to prevent: a port and an
  oracle that share a misreading of ops.py:1030 agree with each other and are both
  wrong.
  """
  try:
    return show(u.expr)
  except AssertionError:
    return "none"


def row(nm, value):
  print(f"{nm}={value}")


def main():
  row("vr_expr_param", expr_of(param("i")))
  # A BUFFER's arg is a ParamArg too, so this is the SAME arm of the arg sum as the
  # row above. The pair is what says the op is genuinely not consulted: if the port
  # ever starts testing the op, exactly one of these two moves.
  row("vr_expr_buffer", expr_of(UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32, name="buf"), AxisType.LOOP)))
  row("vr_expr_unnamed", expr_of(param(None)))
  # A CONST's arg is a PyConst, not a ParamArg: the other refusal, and a different
  # one. `vr_expr_unnamed` and `vr_expr_nonparam` both answer `none` in the port and
  # must not be collapsed into a single row, or a port that refused for the wrong
  # reason would pass.
  row("vr_expr_nonparam", expr_of(UOp(Ops.CONST, (), dtypes.int32, 7, AxisType.LOOP)))
  return 0


if __name__ == "__main__":
  sys.exit(main())
