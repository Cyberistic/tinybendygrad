#!/usr/bin/env python3
"""validate-dv-truth.py -- CPython's `uop/validate.py` answers for the SAME two inputs
`uop/validate.bend`'s `dv_and*` and `dv_shr*` rows build, CALLED.

WHY. Fixing the stale arena at validate.bend:1696/1826 moved three rows, and the value that
moved is the `1` in `... BV2Int(...) - 1 ...` becoming `- 256`. That is a value a `case` arms
on inside `z3_bv`, so the change is SILENT in the sense agent-core means: nothing failed, and
a reader of the diff alone cannot tell which side is right. **So the direction comes from
calling CPython, not from my reading of the diff.**

The bit width is the whole question. `z3_bv` (validate.py:15-17) computes `w` from the node's
dtype, and `BV2Int(..., is_signed=True)` prints its bound as a signed subtraction -- `- 1`
for an 8-bit value and `- 256` for a 16-bit one. So the two answers differ by DTYPE, and the
stale arena was supplying the WRONG NODE -- the arena bottom, whose dtype is `void`. Reading
the bottom's `vmin`/`vmax` is what produced the narrower width.

Run twice; the differ refuses a single run.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import z3
from tinygrad.uop.ops import UOp, Ops, AxisType
from tinygrad.uop.validate import uops_to_z3, z3_bv
from tinygrad.dtype import dtypes


def const(v, dt=dtypes.int32):
  return UOp(Ops.CONST, arg=v, dtype=dt)


def rng(hi):
  return UOp(Ops.RANGE, src=(const(hi), const(0)), arg=AxisType.GLOBAL)


def show(nm, u):
  solver = z3.Solver(ctx=z3.Context())
  (expr,) = uops_to_z3(solver, u)
  print(f"{nm}_expr={expr}")
  print(f"{nm}_dtype={u.dtype}")
  print(f"{nm}_bits={dtypes.ints and u.dtype.size*8}")
  # the signed bound the row prints: BV2Int(...) - 2**(w-1)
  w = u.dtype.size * 8
  print(f"{nm}_signed_bound=2**{w - 1}")


def main():
  for k in (15, 21, -4):
    show(f"dv_and{k}", UOp(Ops.AND, src=(rng(100), const(k))))
  show("dv_shr2", UOp(Ops.SHR, src=(rng(64), const(2))))


if __name__ == "__main__":
  main()