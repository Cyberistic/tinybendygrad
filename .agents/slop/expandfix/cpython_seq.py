"""CPython ground truth for the EXPAND marg, WITH the node sequence.

Records every `UOp._mop(Ops.EXPAND, arg=...)` the REAL `tinygrad` builds AND the
toposort of the resulting graph, so the port's node sequence can be compared
against CPython's rather than against a re-derivation.

Run:  .venv/bin/python .agents/slop/expandfix/cpython_seq.py
Out:  .agents/slop/expandfix/cpython-seq.rows
"""
import os, sys

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


def ops_of(u):
  """The toposort's op names, in the order the arena holds them."""
  return "|".join(str(x.op).replace("Ops.", "") for x in u.toposort().keys())


def case(name, fn):
  EXPANDS.clear()
  try:
    t = fn()
    shape = tuple(t.shape)
    seq = ops_of(t._uop)
  except Exception as e:  # noqa: BLE001
    shape, seq = f"RAISED {type(e).__name__}: {e}", ""
  margs = "|".join(",".join(str(x) for x in m) for m in EXPANDS)
  ROWS.append(f"{name}\tmarg=[{margs}]\tshape={shape}\tseq={seq}")


# THE PORT'S THREE DEFECTIVE CHAINS, expressed in CPython.
# CASE 1 -- conv2d's expand (mixin/op.py:1600-1601).
def c1():
  bs, groups, cin, rcout = 1, 1, 4, 8
  oy, ox, kh, kw = 14, 14, 3, 3
  x = Tensor.zeros(bs, groups, cin, 1, oy, ox, kh, kw)
  return x.expand(bs, groups, cin, rcout, oy, ox, kh, kw)


# CASE 2 -- repeat (movement.py:576-604), the `_pool` repeat.
def c2():
  t = Tensor.zeros(1, 64, 58, 58)
  return t.repeat(1, 1, 4, 4)


# CASE 3 -- repeat, the pool's own call.
def c3():
  t = Tensor.zeros(1, 64, 58, 58)
  return t._pool((3, 3), 2, 1)


# CASE 4 -- the 0-dim source (creation.py:85 `const(v, dt).expand(shape)`).
def c4():
  return Tensor(42).expand(2, 3, 4)


# CASE 5 -- the left-added case: target WIDER than the source.
def c5():
  return Tensor.zeros(4).expand(2, 3, 4)


# CASE 6 -- a middle 1 expanded, no left added.
def c6():
  return Tensor.zeros(2, 1, 5).expand(2, 3, 5)


# CASE 7 -- two 1s expanded.
def c7():
  return Tensor.zeros(1, 1, 6).expand(2, 3, 6)


# CASE 8 -- left-added AND a 1 expanded at once.
def c8():
  return Tensor.zeros(1, 5).expand(3, 1, 5)


# CASE 9 -- the conv2d whole (the shape the port's row expects).
def c9():
  return Tensor.zeros(1, 3, 32, 32).conv2d(Tensor.zeros(8, 3, 3, 3))


# CASE 10 -- max_pool2d (the port's pool_maxpool).
def c10():
  return Tensor.zeros(1, 64, 58, 58).max_pool2d(kernel_size=(3, 3), stride=(2, 2))


for nm, fn in [("C1_conv_expand", c1), ("C2_repeat", c2), ("C3_pool", c3),
               ("C4_scalar_expand", c4), ("C5_left_added", c5),
               ("C6_middle_one", c6), ("C7_two_ones", c7),
               ("C8_left_and_expand", c8), ("C9_conv2d", c9), ("C10_max_pool2d", c10)]:
  case(nm, fn)

out = "\n".join(ROWS) + "\n"
print(out, end="")
with open(os.path.join(os.path.dirname(__file__), "cpython-seq.rows"), "w") as f:
  f.write(out)
