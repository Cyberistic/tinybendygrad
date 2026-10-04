#!/usr/bin/env python3
"""CPython oracle for `UOp.set` (tinygrad/uop/ops.py:1224).

    .venv/bin/python .agents/slop/ops-set-oracle.py

Four rows, one per SHAPE of the `end` argument, every one produced by CALLING the
real `UOp.set` on a real `UOp`.

`set` is three lines and upstream says so in its own comment:
`return self.src[0].after(self.store(val).end(*argfix(end)))`. So the def has no
logic of its own -- it is a COMPOSITION, and the only thing a row can test is
whether the three pieces are wired in the right ORDER and whether `argfix`'s
`None`-means-empty arm is honoured. That is why `set_end_*` is the family: the
number of `end` operands is the only input, and it is the only thing that varies.

`self.src[0]` IS WHY THE FIXTURE IS A STORE AND NOT A BUFFER. The first draft
built a BUFFER and got `IndexError: tuple index out of range`, because `set` is
called ON a store: `src[0]` is the store's target and the store is what gets
rewritten. A fixture that does not reach the code is a fixture that cannot fail.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.uop.spec import AxisType
from tinygrad import dtypes

L = AxisType.LOOP


def deep(x):
  """`OP(OP,OP,...)` to the leaves: the op NAMES are the four facts, and an
  AFTER's SRC ORDER is one of them."""
  if not x.src:
    return x.op.name
  return x.op.name + "(" + ",".join(deep(s) for s in x.src) + ")"


def main():
  buf = UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32), L)
  # `set` reads `self.src[0]`, so the subject is a STORE and `src[0]` is its target.
  st = UOp(Ops.STORE, (buf, UOp.const(1)))
  v, e, f = UOp.const(7), UOp.const(9), UOp.const(3)

  print(f"set_end_none={deep(st.set(v))}")
  print(f"set_end_one={deep(st.set(v, e))}")
  print(f"set_end_seq={deep(st.set(v, (e, f)))}")
  # A BARE INT is the `UOp|ConstType` half of the signature: `argfix` turns it into
  # a CONST, and a row that passes a node would not see that arm at all.
  print(f"set_val_int={deep(st.set(5))}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
