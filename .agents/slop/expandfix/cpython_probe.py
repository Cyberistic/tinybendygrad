"""CPython ground truth for the EXPAND marg.

Records every `UOp._mop(Ops.EXPAND, arg=...)` the REAL `tinygrad` builds, so the
marg is READ OFF CPython rather than re-derived by a second implementation.

Run:  .venv/bin/python .agents/slop/expandfix/cpython_probe.py
Out:  .agents/slop/expandfix/cpython.rows
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", ".."))

from tinygrad.uop.ops import UOp, Ops
from tinygrad import Tensor

EXPANDS = []


def _mop(self, op, arg=None):
  if op == Ops.EXPAND:
    EXPANDS.append(tuple(arg) if arg is not None else ())
  return _ORIG_MOP(self, op, arg)


_ORIG_MOP = UOp._mop
UOp._mop = _mop

ROWS = []


def row(name, got, want):
  ROWS.append(f"{name}\t{got}\t{want}")


def expands_of(fn):
  EXPANDS.clear()
  try:
    out = fn()
  except Exception as e:  # noqa: BLE001
    return f"RAISED {type(e).__name__}: {e}"
  return out


def case(name, fn):
  EXPANDS.clear()
  try:
    r = fn()
  except Exception as e:  # noqa: BLE001
    r = f"RAISED {type(e).__name__}: {e}"
  margs = "|".join(",".join(str(x) for x in m) for m in EXPANDS)
  row(name, f"marg=[{margs}] result={r}", "")


# ---------------------------------------------------------------- CASES ----
# CASE A -- the conv2d expand: source has a 1 at axis 3, target has rcout.
case("A_conv_expand", lambda: Tensor.zeros(1, 4, 1, 5, 5, 3, 3).expand(1, 4, 1, 8, 5, 5, 3, 3).shape)

# CASE B -- the repeat expand: source (b0,b1,1,i0,1,i1) -> (b0,b1,r0,i0,r1,i1)
case("B_repeat_expand", lambda: Tensor.zeros(2, 3, 1, 7, 1, 11).expand(2, 3, 4, 7, 5, 11).shape)

# CASE C -- 0-dim source -> target (the `full`/`const_like` case).
case("C_scalar_expand", lambda: Tensor(42).expand(2, 3, 4).shape)

# CASE D -- target WIDER on the LEFT: source (4,) -> target (2,3,4).
case("D_left_added", lambda: Tensor.zeros(4).expand(2, 3, 4).shape)

# CASE E -- same rank, a 1 in the MIDDLE expanded.
case("E_middle_one", lambda: Tensor.zeros(2, 1, 5).expand(2, 3, 5).shape)

# CASE F -- no expansion needed at all (same shape) -> early return, NO expand node.
case("F_same_shape", lambda: Tensor.zeros(2, 3).expand(2, 3).shape)

# CASE G -- two 1s to expand.
case("G_two_ones", lambda: Tensor.zeros(1, 1, 6).expand(2, 3, 6).shape)

# CASE H -- the real CPython repeat(): what marg does IT build?
case("H_repeat_call", lambda: Tensor.zeros(2, 3, 7, 11).repeat(1, 1, 4, 5).shape)

# CASE I -- the real CPython conv2d(): what marg does IT build?
case("I_conv2d_call", lambda: Tensor.zeros(1, 3, 32, 32).conv2d(Tensor.zeros(8, 3, 3, 3)).shape)

# CASE J -- full(): 0-dim CONST -> target.
case("J_full_call", lambda: Tensor.full((2, 3, 4), 7).shape)

# CASE K -- const_like on a 2-dim source.
case("K_const_like", lambda: Tensor.zeros(2, 3).const_like(5).shape)

# CASE L -- the FULL conv2d expand chain, marg + intermediate shapes.
def conv_chain():
  t = Tensor.zeros(1, 4, 16, 16)
  w = Tensor.zeros(8, 4, 3, 3)
  return t.conv2d(w).shape
case("L_conv2d_chain", conv_chain)

# CASE M -- _pool's repeat, isolated.
def pool_repeat():
  t = Tensor.zeros(1, 4, 16, 16)
  return t._pool((3, 3), 1, 1).shape
case("M_pool_repeat", pool_repeat)

# CASE N -- expand where a source 1 stays 1 (out also 1) -> NOT expanded.
case("N_one_stays_one", lambda: Tensor.zeros(1, 2, 1).expand(1, 2, 1).shape)

# CASE O -- left-added AND a 1 expanded at once.
case("O_left_and_expand", lambda: Tensor.zeros(1, 5).expand(3, 1, 5).shape)

out = "\n".join(ROWS) + "\n"
print(out, end="")
with open(os.path.join(os.path.dirname(__file__), "cpython.rows"), "w") as f:
  f.write(out)
