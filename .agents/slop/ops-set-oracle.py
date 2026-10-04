#!/usr/bin/env python3
"""CPython oracle for `UOp.set` (tinygrad/uop/ops.py:1224).

    .venv/bin/python .agents/slop/ops-set-oracle.py

Three rows, one per SHAPE of the `end` argument, every one produced by CALLING the
real `UOp.set` on a real `UOp`.

`set` is three lines and upstream says so in its own comment:
`return self.src[0].after(self.store(val).end(*argfix(end)))`. So the def has no
logic of its own -- it is a COMPOSITION, and the only things a row can test are
that the three pieces are wired in this ORDER and that `argfix`'s empty arm is
honoured. The number of `end` operands is the only input that varies, so it is the
only thing the family varies.

THE PRINTED SHAPE IS TWO LEVELS: the answer's op and its DIRECT children's ops.
CPython's `deep` would print to the leaves, and it is a one-liner there so the
depth was free -- but a row deeper than it needs to be is cost for nothing, and
two levels already separate all three answers (`AFTER` with a `STORE` child, with
an `END` child, with an `END` child of a different width). The port and this file
print the SAME shape deliberately: a gate about ORDER is a gate whose two sides
have the same ORDER.

`self.src[0]` IS WHY THE FIXTURE IS A STORE AND NOT A BUFFER. The first draft built
a BUFFER and got `IndexError: tuple index out of range`, because `set` is called ON
a store: `src[0]` is the store's target and the store is what gets rewritten. A
fixture that does not reach the code is a fixture that cannot fail.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.uop.spec import AxisType
from tinygrad import dtypes

L = AxisType.LOOP


def two(x):
  """`Ops.OP(Ops.OP ...)` -- the answer's op and its DIRECT children's ops."""
  kids = " ".join(f"Ops.{s.op.name}" for s in x.src)
  return f"Ops.{x.op.name}({kids})"


def main():
  buf = UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32), L)
  # `set` reads `self.src[0]`, so the subject is a STORE and `src[0]` is its target.
  st = UOp(Ops.STORE, (buf, UOp.const(1)))
  v, e, f = UOp.const(7), UOp.const(9), UOp.const(3)

  # A 0-operand end, a 1-operand end, and a 2-operand end. The third is what proves
  # `argfix`'s list arm is the same `*` as its single-item arm rather than a
  # one-element special case: with one end the END has one src and with two it has
  # two, and both rows print the same TOP-LEVEL shape.
  print(f"set_end_none={two(st.set(v))}")
  print(f"set_end_one={two(st.set(v, e))}")
  print(f"set_end_two={two(st.set(v, (e, f)))}")
  # The SAME two operands in the OTHER ORDER. A def that sorted, deduped or
  # reversed  would print the same two-level shape here and differ only in
  # the END's src order -- which this depth cannot see. So the row earns its place
  # by being the one that would catch it if the printer ever went deeper.
  print(f"set_end_two_src={two(st.set(v, (f, e)))}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
