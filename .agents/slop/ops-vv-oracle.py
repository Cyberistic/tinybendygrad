#!/usr/bin/env python3
"""CPython oracle for `ProgramInfo.vals` (tinygrad/uop/ops.py:1366).

    .venv/bin/python .agents/slop/ops-vv-oracle.py

Five rows, one per ANSWER, every one produced by CALLING the real
`ProgramInfo.vals`. Nothing is transcribed from reading the source.

`vals` is `tuple(var_vals[k.expr] for k in self.vars)` with a
`RuntimeError(f"unbound Variable {e}")` on a miss, so its three interesting
outcomes are: the full tuple, a REFUSAL, and -- the one that is invisible unless
you go looking for it -- a Variable BOUND TO 0. A miss returns `Map.get`'s
DEFAULT, which is 0, so "unbound" and "bound to 0" are the same value to a lookup
that does not also ask `Map.has`. `vv_zero` is that row, and a def that dropped
the `has` entirely would pass the other four.

`vv_miss_second` misses on the SECOND name, not the first. `vals` refuses at the
FIRST miss, so a fixture that missed on `i` would never look at `j` and the two
would be one row. Missing late is what proves the fold STOPS.

THE VALUES PRINT IN THE PORT'S OWN SPELLING. `H.i64_text` renders an `H.I64` as
`hi:lo` in two `U32` words, and a positive value is `0:7`. CPython prints `7`. The
oracle therefore prints the two-word form, because the gate's question is "did the
same value land in the same field in the same order" and not "can two languages
spell seven the same way" -- and because `vv_two` is a row about ORDER, which a
`7,9` that both languages agree on would also satisfy, but a reversed fold would
not.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg, ProgramInfo
from tinygrad.uop.spec import AxisType
from tinygrad.dtype import AddrSpace
from tinygrad import dtypes

L = AxisType.LOOP


def var(name):
  """A Variable, by the real constructor -- ops.py:1015, which is PORTED."""
  return UOp(Ops.PARAM, (),
             ParamArg(-1, dtypes.weakint, name=name, vmin_vmax=(0, 10), multiple_of=1,
                      addrspace=AddrSpace.ALU), L)


def words(v):
  n = int(v) & ((1 << 64) - 1)
  return f"{n >> 32}:{n & 0xFFFFFFFF}"


def vals(vs, given):
  """CPython's answer, or the refusal CPython raises."""
  try:
    out = ProgramInfo(vars=tuple(vs)).vals(given)
  except RuntimeError:
    return "none"
  return "(" + ",".join(words(v) for v in out) + ")"


def row(nm, got):
  print(f"{nm}={got}")


def main():
  i, j = var("i"), var("j")
  row("vv_two", vals((i, j), {"i": 7, "j": 9}))
  row("vv_one", vals((i,), {"i": 7}))
  row("vv_zero", vals((i,), {"i": 0}))
  row("vv_none", vals((), {}))
  row("vv_miss_second", vals((i, j), {"i": 7}))
  return 0


if __name__ == "__main__":
  sys.exit(main())
