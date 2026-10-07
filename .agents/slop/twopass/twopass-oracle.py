#!/usr/bin/env python3
"""twopass-oracle.py -- CPython's own answers for the FOUR fixtures `plant.bend` builds.

The plant's halves are only meaningful against UPSTREAM: (a) is "the port now answers
what CPython answers", and (b) is "the port still refuses where CPython answers", which
is a divergence and not a failure -- so both halves need CPython's column or the rows
are just the port talking to itself.

  .venv/bin/python .agents/slop/twopass/twopass-oracle.py
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, AddrSpace


def base():
  """`Tensor.empty(4,3).uop` -- ALLOC + RESHAPE + STACK + two CONSTs."""
  return Tensor.empty(4, 3, dtype=dtypes.float).uop


def a1():
  """(a1) the corpus `g_unshard`: UNSHARD(a, range(2,0,DEVICE)), arg=(0,)."""
  a = base()
  r = UOp.range(2, 0, AxisType.DEVICE)
  return UOp(Ops.UNSHARD, src=(a, r), arg=(0,))


def a2():
  """(a2) the range-carrying STAGE the CORPUS DOES NOT HAVE: STAGE(a, range(3,0,DEVICE))."""
  a = base()
  r = UOp.range(3, 0, AxisType.DEVICE)
  return UOp(Ops.STAGE, src=(a, r), arg=None)


def b1():
  """(b1) RANGE over a SPECIAL end -- CPython computes a width, `rng_width` refuses."""
  a = base()
  r = UOp.range(UOp.special(UOp.const(1, dtypes.int32), "N"), 0, AxisType.DEVICE)
  return UOp(Ops.UNSHARD, src=(a, r), arg=(0,))


def b3():
  """(b3) arg names axis 9, which a (4,3) shape does not have: no axis scales."""
  a = base()
  r = UOp.range(2, 0, AxisType.DEVICE)
  return UOp(Ops.UNSHARD, src=(a, r), arg=(9,))


def show(nm, u):
  try:
    shp = u.shape
  except Exception as e:                                    # noqa: BLE001
    shp = f"RAISES {type(e).__name__}"
  try:
    dt = u.dtype
  except Exception as e:                                    # noqa: BLE001
    dt = f"RAISES {type(e).__name__}"
  print(f"{nm} dtype={dt} shape={shp}")


if __name__ == "__main__":
  for nm, f in (("(a1)", a1), ("(a2)", a2), ("(b1)", b1), ("(b3)", b3)):
    show(nm, f())
  print("# census a2 srcs:", [s.op.name for s in a2().src], "arg is", a2().arg)
  print("# census b1 srcs:", [s.op.name for s in b1().src])