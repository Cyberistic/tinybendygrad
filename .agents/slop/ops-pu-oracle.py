#!/usr/bin/env python3
"""CPython oracle for `print_uops` (tinygrad/uop/render.py:18).

    .venv/bin/python .agents/slop/ops-pu-oracle.py

Five rows, each a LIST of `print_uops` output lines, produced by CALLING the real
`print_uops` with stdout captured rather than by reimplementing its f-string.

`print_uops` is a DEBUG PRINTER and its whole content is one f-string with FIVE
fields per line:

    print(f"{i:4d} {str(u.op):20s}: {multirange_str(u.ranges, color=True, pad=10)} "
          f"{str(u.dtype):40s} {str(formatted_srcs):32s} {u.arg}")

Each row is named for the ONE field it is the only row that can pin:

  pu_range     a BUFFER with a RANGE -- the baseline, and the `--` src arm
  pu_missing   a src NOT IN THE LIST -- `--`, and not the CONST's value
  pu_const     that same CONST IN THE LIST -- its VALUE, and not its index
  pu_index     BOTH srcs in the list -- the index arm, which only this row exercises
  pu_constarg  two CONSTs -- the last column is a PyConst, not a ParamArg

THE COLOURING IS KEPT AND NOT STRIPPED. `NO_COLOR` does not suppress it --
`range_str`'s `colored(...)` is unconditional on its `color=` argument and
`print_uops` passes `color=True` -- and that was MEASURED: the first draft set
`NO_COLOR=1` expecting bare text and got `\x1b[31m0\x1b[0m`.

A BUFFER CARRIES A CONST SRC, and that is not incidental. The port's fold derives a
BUFFER's shape and dtype FROM ITS SRCS -- `g_buf` at fold.bend:3919 is
`BUFFER(int32, size=4)` hung off a SPECIAL -- and MEASURED here: a srcless BUFFER
reads `?` from `UOp.dtype` while the node ABOVE it reads a real answer, because the
fold had nothing to derive from. CPython's fixtures have the src too.

THE WIDTHS ARE REAL and the gate keeps them: `20s` on the op, `40s` on the dtype,
`32s` on the srcs and `pad=10` on the ranges are all in the f-string. A port with
the right VALUES and the wrong widths is a different format, and the diff catches
it, which is why these rows are whole lines and not a name-to-value map.

THE RANGE MUST BE BUILT WITH `UOp.range`. `UOp(Ops.RANGE, src, arg, AxisType.LOOP)`
takes the axis type as its THIRD argument and sets the TAG, so `axis_id` comes back
empty and `print_uops` dies in `axis_colors[u.axis_type]` with a KeyError. That is
not a subtlety of this port -- it is CPython's own constructor, and it cost two
rounds of "the oracle is broken".
"""
import contextlib
import io
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg, AxisType
from tinygrad.uop.render import print_uops
from tinygrad import dtypes

L = AxisType.LOOP

# The arena, matching the port's `pu_ar` node for node. A BUFFER WITH A CONST SRC,
# a RANGE over it, an ADD over that, and two bare CONSTs.
C1 = UOp.const(4)
RANGE = UOp.range(4, 0, AxisType.LOOP)
BUF = UOp(Ops.BUFFER, (C1,), ParamArg(1, dtypes.int32, size=4, name="b"), L)
ADD = UOp(Ops.ADD, (BUF, C1))   # no axis: the 3rd positional is ARG, not axis_type
C2 = UOp.const(8)


def rows(nm, uops):
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    print_uops(uops)
  for line in buf.getvalue().split("\n"):
    if line:
      print(f"{nm}|{line}")


def main():
  rows("pu_range", [BUF])
  rows("pu_missing", [ADD])                       # c1 is NOT in the list
  rows("pu_const", [ADD, C1])                     # c1 IS, so its VALUE prints
  rows("pu_index", [BUF, ADD, C1])                # both srcs in, so indices print
  rows("pu_constarg", [C1, C2])                   # a PyConst last column
  return 0


if __name__ == "__main__":
  sys.exit(main())
