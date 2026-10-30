#!/usr/bin/env python3
"""mop_idxneg-oracle.py -- CPython's answers to `gates/mop_idxneg.bend`'s sixteen rows.

The two lanes share no code: the Bend lane calls `mop_cleanup` and `mp_index` from the
port, this lane calls CPython's `mop_cleanup` and `UOp.index` and asks the same questions.
A row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/mop_idxneg-oracle.py

THE SUBJECT IS PYTHON'S LIST INDEX. Both upstream call sites index a STACK's srcs with a
CONST's VALUE:

    `a.src[i.val] if len(idx.src) <= 2 else a.src[i.val].index(*idx.src[2:])` -- tinygrad/uop/movement.py:22
    `return self.src[new_srcs[0].val]` -- tinygrad/uop/ops.py:561

`a.src[v]` is a Python list index, so a NEGATIVE `v` reads from the END. MEASURED, on
`UOp(Ops.INDEX, src=(STACK(CONST 3, CONST 5, CONST 7), CONST(-1)))`:

    mop_cleanup.rewrite(idx)  ->  UOp(Ops.CONST, arg=7)

and the port answered `UOp(Ops.CONST, arg=3)` -- the FIRST element -- because it read the
index as a `U32` and a negative `v` became a huge `U32`.

THE OUT-OF-RANGE ROWS ARE `none`, AND THAT IS UPSTREAM'S `IndexError`. CPython raises
`IndexError: tuple index out of range` for `v = -4` and for `v = 3` on a three-element
STACK. The port has no exception form, so its answer is "no rewrite" -- and `none` is the
ONE spelling both sides can print, so the two lanes compare the same thing rather than
comparing "CPython raised" with "the port declined".

THE ROW IS THE VALUE and not the OP: a CONST's ARG. An OP row would read `CONST` on both
sides for the WRONG index and would not move, so it could not see the defect this gate
exists for.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.uop.movement import mop_cleanup

# THREE elements, so `-1` is the LAST, `-3` is the FIRST and `-4` is out of range.
def stk():
  return UOp(Ops.STACK, src=(UOp.const(3), UOp.const(5), UOp.const(7)))


def idx(k):
  return UOp(Ops.INDEX, src=(stk(), UOp.const(k)))


def val_of(u):
  """THE ANSWER'S VALUE, or `none`. `None` is upstream's `None` (no rule fired) and
  `IndexError` is caught and printed as `none` too -- the port's "no rewrite" is the same
  shape, and the gate compares the two."""
  if u is None: return "none"
  if u.op is Ops.CONST: return str(u.arg)
  return "none"


def mcl(k):
  try:
    return val_of(mop_cleanup.rewrite(idx(k)))
  except IndexError:
    return "none"


def uidx(k):
  try:
    return val_of(stk().index(k))
  except IndexError:
    return "none"


for name, fn in (("mcl", mcl), ("uidx", uidx)):
  for tag, k in (("neg1", -1), ("neg2", -2), ("neg3", -3), ("neg4", -4),
                 ("pos0", 0), ("pos1", 1), ("pos2", 2), ("pos3", 3)):
    print(f"{name}_{tag}={fn(k)}")
