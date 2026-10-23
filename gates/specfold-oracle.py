#!/usr/bin/env python3
"""CPython's half of `gates/specfold.bend`: the SAME eight shapes, the SAME six tables.

    .venv/bin/python gates/specfold-oracle.py

WHY A SECOND FILE AND NOT A FLAG. `gates/specnew-oracle.py` is this pattern already, and
the reason is the one `AGENTS.md` keeps restating: the two lanes must be built by DIFFERENT
code from DIFFERENT construction sites, or a diff between them compares one implementation
with itself. The port mints its RESHAPE, RANGE, BACKEDGE, BUFFER and ALLOC from `ops.bend`'s
own constructors and this file mints them from upstream's `UOp`, so agreement is evidence.

THE EIGHT SHAPES, and each one is a shape whose verdict commit `d4160980e` decides:

  reshape_f32   RESHAPE whose SECOND src -- the SHAPE -- is a float. Upstream's
                `spec.py:166` puts the shape's dtype in the PATTERN
                (`UPat(dtype=dtypes.ints+(dtypes.weakint, dtypes.void))`), so a float shape
                cannot match it and upstream's scan CONTINUES.
  reshape_i32   the CONTROL: the same RESHAPE with an INT shape, which the pattern admits.
  range2        RANGE with TWO srcs. Upstream's `spec.py:81` is `src=(UPat(),)` -- a
                ONE-tuple, so EXACTLY one src.
  range1        the CONTROL: the same RANGE with ONE src.
  backedge_int  BACKEDGE whose THIRD src -- the CONDITION -- is not boolean-dtyped.
                Upstream's `spec.py:88` puts the condition's dtype in the PATTERN
                (`UPat(dtype=dtypes.bool)`).
  backedge_bool the CONTROL: the same BACKEDGE with a BOOL-typed condition.
  buffer0       BUFFER with ZERO srcs. Upstream's `spec.py:150` is
                `src=(p_size,), allow_any_len=True`, and `allow_any_len` relaxes the length
                ABOVE the tuple's length, never below it, so a 0-src BUFFER cannot match.
  alloc0        ALLOC with ZERO srcs -- `spec.py:153`, the same shape.

THE SIX NUMBERS PER SHAPE are `sh te sp hq sk sf` -- `spec_shared`, `spec_tensor`,
`spec_program`, `spec_hcq`, `spec_kernel_graph`, `spec_full` -- printed as `1` True, `0`
False, `9` the `None` that `rewrite` returns when no rule decided. `ops.py:1605` returns the
first non-`None` and `type_verify` accepts only `is True`, so `9` is a rejection that no
rule owns. That is the port's `Sp.show_v` spelling and it is not a coincidence of notation:
both sides are answering "which of the three did the first-wins fold produce".

WHY THE FLOAT SHAPE IS A CAST IN BOTH TREES. Upstream's `UOp.const(1.0, dtypes.float32)` is
a CAST over a CONST -- a CONST cannot carry a float dtype -- and the port's
`O.UOp.const(arena, O.CFloat{1.0})` has dtype `weakfloat`, so the port's driver casts it to
`S.single()` (f32) explicitly. The shape src's dtype is f32 on BOTH sides, which is the
whole point of the fixture: the rule asks about the dtype.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tinygrad.device import Buffer  # noqa: E402
from tinygrad.dtype import AddrSpace, dtypes  # noqa: E402
from tinygrad.uop.ops import AxisType, Ops, ParamArg, UOp  # noqa: E402
from tinygrad.uop.spec import spec_full, spec_hcq, spec_kernel_graph, spec_program, spec_shared, spec_tensor  # noqa: E402


def verdict(m, u: UOp) -> int:
  ret = m.rewrite(u)
  return 9 if ret is None else (1 if ret is True else 0)


def reshape_f32() -> UOp:
  return UOp(Ops.RESHAPE, (UOp.const(1), UOp.const(1.0, dtypes.float32)))


def reshape_i32() -> UOp:
  return UOp(Ops.RESHAPE, (UOp.const(1), UOp.const(1, dtypes.int32)))


def range2() -> UOp:
  # upstream's RANGE arg is `(axis_type, axis_id)` (ops.py:624)
  return UOp(Ops.RANGE, (UOp.const(1), UOp.const(2)), (AxisType.WEAK, 0))


def range1() -> UOp:
  return UOp(Ops.RANGE, (UOp.const(1),), (AxisType.WEAK, 0))


def backedge_int() -> UOp:
  # upstream's `backedge` is `UOp(Ops.BACKEDGE, src=(self, loop, cond))` (ops.py:598)
  loop = UOp(Ops.RANGE, (UOp(Ops.NOOP),), (AxisType.WEAK, 0))
  return UOp(Ops.BACKEDGE, (UOp.const(1), loop, UOp.const(1)))


def backedge_bool() -> UOp:
  loop = UOp(Ops.RANGE, (UOp(Ops.NOOP),), (AxisType.WEAK, 0))
  return UOp(Ops.BACKEDGE, (UOp.const(1), loop, UOp.const(True, dtypes.bool)))


def _paramarg(buffer) -> ParamArg:
  """A GLOBAL int32 ParamArg with a device. `buffer` is None for an ALLOC and a real
  Buffer for a BUFFER -- upstream's `spec.py:150` asks `buf.arg.buffer is not None`."""
  return ParamArg(0, dtypes.int32, None, None, None, AddrSpace.GLOBAL, "CPU", False, None, buffer, False, None)


def buffer0() -> UOp:
  return UOp(Ops.BUFFER, (), _paramarg(Buffer("CPU", 64)))


def alloc0() -> UOp:
  return UOp(Ops.ALLOC, (), _paramarg(None))


TABLES = (("sh", spec_shared), ("te", spec_tensor), ("sp", spec_program), ("hq", spec_hcq),
          ("sk", spec_kernel_graph), ("sf", spec_full))

SHAPES = (("reshape_f32", reshape_f32), ("reshape_i32", reshape_i32),
          ("range2", range2), ("range1", range1),
          ("backedge_int", backedge_int), ("backedge_bool", backedge_bool),
          ("buffer0", buffer0), ("alloc0", alloc0))


def main() -> int:
  for name, make in SHAPES:
    u = make()
    for key, m in TABLES:
      print(f"{name}_{key}={verdict(m, u)}")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. This file is the census half; `gates/specfold-gate.py` is the gate and it carries
# the guard. Run this file BY PATH; `raise SystemExit` keeps the exit status.
raise SystemExit(main())
