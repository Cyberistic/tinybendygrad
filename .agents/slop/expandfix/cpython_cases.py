"""CPython ground truth for the EXACT cases the Bend probe runs.

Records the marg of the EXPAND CPython builds and the shape `_broadcast_to`
returns, for the same (source, target) pairs the Bend probe uses.

Run:  .venv/bin/python .agents/slop/expandfix/cpython_cases.py
Out:  .agents/slop/expandfix/cpython-cases.rows
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", ".."))

from tinygrad.uop.ops import UOp, Ops
from tinygrad import Tensor

EXPANDS = []
_ORIG_MOP = UOp._mop


def _mop(self, op, arg=None):
  if op == Ops.EXPAND:
    EXPANDS.append(tuple(arg) if arg is not None else ())
  return _ORIG_MOP(self, op, arg)


UOp._mop = _mop

ROWS = []


def case(name, src, dst, note):
  """`Tensor.empty(src).expand(dst)` IS `_broadcast_to` (movement.py:128)."""
  EXPANDS.clear()
  t = Tensor.empty(*src).expand(*dst)
  marg = EXPANDS[-1] if EXPANDS else ()
  ROWS.append(f"{name}\tsrc={','.join(str(x) for x in src)}\tdst={','.join(str(x) for x in dst)}"
               f"\tmarg={','.join(str(x) for x in marg)}\tshape={','.join(str(x) for x in t.shape)}\t{note}")


# THE SEVEN CASES, in the Bend probe's order.
case("case1_conv_expand", (1, 1, 4, 1, 14, 14, 3, 3), (1, 1, 4, 8, 14, 14, 3, 3),
     "conv2d op.py:1600-1601; the marg is (rcout,) and the permute puts it back")
case("case2_repeat", (1, 64, 1, 58, 1, 58), (1, 64, 4, 58, 4, 58),
     "repeat movement.py:576-604; the marg is the REPEAT COUNTS")
case("case3_repeat_mid", (1, 64, 1, 58, 1, 58), (1, 64, 4, 58, 4, 58),
     "the same expand, read on its own")
case("case4_pool_maxpool", (1, 64, 1, 58, 1, 58), (1, 64, 4, 58, 4, 58),
     "_pool movement.py:624; kk0=kk1=ceildiv(3*(58+1),58)=4")
case("case5_scalar_expand", (), (2, 3, 4),
     "creation.py:85 const(v,dt).expand(shape); a 0-dim source has EVERY dim left-added")
case("case6_left_added", (4,), (2, 3, 4),
     "the target is WIDER than the source; the marg is the LEFT-ADDED dims only")
case("case7_middle_one", (2, 1, 5), (2, 3, 5),
     "a 1 in the middle, no left added; the marg is (3,)")

out = "\n".join(ROWS) + "\n"
print(out, end="")
with open(os.path.join(os.path.dirname(__file__), "cpython-cases.rows"), "w") as f:
  f.write(out)
