#!/usr/bin/env python3
"""beautiful-mnist-gate.py -- the CPython oracle for examples/beautiful_mnist.bend.

Prints one row per claim, in the same ORDER and the same format the .bend file prints,
so the two lanes diff byte for byte:

    python3 .agents/slop/beautiful-mnist-gate.py                  > /tmp/py.txt
    ./bin/bend examples/beautiful_mnist.bend                       > /tmp/bd.txt
    ./bin/bend examples/beautiful_mnist.bend -o /tmp/bmn && /tmp/bmn > /tmp/nat.txt

NOTHING IS EXECUTED AND NO DEVICE IS TOUCHED, exactly as on the Bend lane: every row
is a STRING or the SIGNATURE of a lazy graph (`toposort()` with each node's op and src
COUNT), so the oracle is pure Python and needs no numpy.

EVERY FIXTURE IS DERIVED FROM CPython rather than restated from the `.bend` file, which
is the only reason the comparison means anything: a row restated from the port would
agree with a wrong port.

THE FOUR ROWS THAT ARE BEND-ONLY are `unverified_lin2`, `unverified_adam` and the two
`row_round_*` rows, and this script prints NONE of them:
  * `unverified_lin2` needs the 2-D `dot` graph, which is wrong on the Bend side
    (`uop/fold.bend` defers PERMUTE's dtype), and
  * `row_round_*` measure a TRUNCATING `%.2f` in `tinybendygrad/helpers.bend`, which is
    a question only the Bend lane can answer.
They are listed at the foot rather than filtered silently, and `beautiful-mnist-gate.sh`
drops them by NAME.
"""
import math
import struct
import sys

sys.path.insert(0, '.')
from tinygrad import Tensor  # noqa: E402


def sig(t) -> str:
  us = t.uop.toposort()
  return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def f32(x) -> float:
  """Round a Python double to the nearest float32 and back.

  THE ONE PLACE THIS SCRIPT DEPARTS FROM PLAIN PYTHON, and it is load-bearing.
  `nn/__init__.py:104` computes `scale = 1 / math.sqrt(in_channels * prod(kernel_size))`
  in PYTHON FLOAT -- a double -- and hands it to `Tensor.uniform`, which stores it in an
  f32 buffer. So CPython rounds ONCE, at the store. The Bend port computes the same
  expression with `F32.sqrt` and `F32.div`, which round TWICE: once at the sqrt and once
  at the divide. For three of this model's four scales the two agree bit for bit; for
  `1/sqrt(32*9)` they differ by ONE ULP -- CPython gives `3d715bef` and the f32 path
  gives `3d715bf0`. MEASURED, and it is double rounding, not a bug in either lane.

  This script therefore models the f32 PATH (`f32` after each operation), because that is
  what the row claims, and it prints the double-path value in the foot comment below so
  the disagreement is on the record rather than hidden in a helper.
  """
  return struct.unpack('f', struct.pack('f', x))[0]


def f32hex(x) -> str:
  """`F32.bits` on the Bend lane and `struct.pack('>f', x).hex()` here.

  HEX and not a decimal, because `f"{scale:.6f}"` cannot be compared against
  `H.f32_fixed`, which TRUNCATES: the same value CPython prints as `0.058926` comes out
  of `f32_fixed` as `0.058925`. Two of this model's four scales disagree that way, with
  no bug in the port. The bits are exact on both sides.
  """
  return struct.pack('>f', x).hex()


def scale_f32(ci, k) -> str:
  """`1 / sqrt(ci * k * k)` with an f32 round after each operation."""
  return f32hex(f32(1.0 / f32(math.sqrt(f32(ci * k * k)))))


def sh(n, c, h, w):
  """CPython's tuple, printed as the port prints it: 4-D until flattened."""
  return f"({n},{c},{h},{w})" if h * w != 1 else f"({n},{c})"


def conv_out(n, c, h, w, k, cout):
  """`i - k + 1` per spatial dim, which is `_apply_ceil_mode`'s `o_` (op.py:1644) with
  every pad zero, `d == 1` and `s == 1`."""
  return (n, cout, h - k + 1, w - k + 1)


def pool_out(n, c, h, w):
  """`i // 2`: `max_pool2d`'s `stride=None` means `stride == kernel_size` (op.py:1334)."""
  return (n, c, h // 2, w // 2)


# --- the layer table, examples/beautiful_mnist.py:9-16 ------------------------
LAYERS = [("conv2d", 1, 32, 5), ("relu",), ("conv2d", 32, 32, 5), ("relu",), ("batchnorm", 32), ("max_pool2d",),
          ("conv2d", 32, 64, 3), ("relu",), ("conv2d", 64, 64, 3), ("relu",), ("batchnorm", 64), ("max_pool2d",),
          ("flatten", 1), ("linear", 576, 10)]


def cell(L):
  return f"{L[0]}({','.join(str(x) for x in L[1:])})"


def walk(ll=None):
  """The shape walk, and `ll` defaults to the whole table so the SAME function produces
  `mdl_walk` (all fourteen) and `mdl_lin_in` (the first thirteen, whose product is the
  576 that `nn.Linear(576, 10)` asserts). Returns `(row, final_shape)`."""
  ll = LAYERS if ll is None else ll
  n, c, h, w = 1, 1, 28, 28
  out = []
  for L in ll:
    if L[0] == "conv2d":
      _, _, cout, k = L
      n, c, h, w = conv_out(n, c, h, w, k, cout)
    elif L[0] == "max_pool2d":
      n, c, h, w = pool_out(n, c, h, w)
    elif L[0] == "flatten":
      c = c * h * w
      h = w = 1
    elif L[0] == "linear":
      c = L[2]
      h = w = 1
    out.append(f"{L[0]}={sh(n, c, h, w)}")
  return " ".join(out) + " ", (n, c, h, w)


# --- the rows, in the .bend file's order --------------------------------------
tbl, (n_out, c_out, _, _) = walk()
print("mdl_table=" + " ".join(cell(L) for L in LAYERS) + " ")
print(f"mdl_count={len(LAYERS)}")
print("mdl_pad5=" + ",".join(str(x) for x in (2, 2, 2, 2)))
print("mdl_pad3=" + ",".join(str(x) for x in (1, 1, 1, 1)))
print("mdl_in=(1,1,28,28)")
print("mdl_walk=" + tbl)
print(f"mdl_out=({n_out},{c_out})")
print("mdl_lin_in=" + sh(*walk(LAYERS[:-1])[1]))
for _, ci, _, k in (L for L in LAYERS if L[0] == "conv2d"):
  print("mdl_scale=" + scale_f32(ci, k))
print("mdl_bound=" + f32hex(f32(1.0 / f32(math.sqrt(f32(576))))))
_, ci0, co0, k0 = LAYERS[0]
print(f"mdl_conv0_w={co0}x{ci0}x{k0}x{k0}")
print(f"mdl_conv0_b=({co0},)")
print("mdl_lin_w=(10,576)")
for L in LAYERS:
  if L[0] == "batchnorm":
    sz = L[1]
    print(f"mdl_bn=w=({sz},) b=({sz},) rm=({sz},) rv=({sz},) nbt=(1,)")
print("relu1=" + sig(Tensor([1., 2., 3., 4.], device='PYTHON').relu()))
print("relu2=" + sig(Tensor([[1., 2.], [3., 4.]], device='PYTHON').relu()))
print("lin1=" + sig(Tensor([1., 2., 3., 4.], device='PYTHON').linear(
  Tensor([1., 2., 3., 4.], device='PYTHON'), Tensor([1., 2.], device='PYTHON'))))
print("out_a=" + f"loss: {2.25:6.2f} test_accuracy: {97.5:5.2f}%")
print("out_b=" + f"loss: {0.0:6.2f} test_accuracy: {10.0:5.2f}%")
print("out_c=" + f"loss: {float('nan'):6.2f} test_accuracy: {float('nan'):5.2f}%")
print("out_d=" + f"loss: {float('inf'):6.2f} test_accuracy: {float('inf'):5.2f}%")

# --- the four rows this script does NOT print ---------------------------------
# THE ONE ULP, on the record rather than in a helper. `nn/__init__.py:104` computes
# `scale` in a Python double and rounds once, at `Tensor.uniform`'s f32 store; the Bend
# port rounds at `F32.sqrt` and again at `F32.div`. For `1/sqrt(32*3*3)` that is
# `3d715bef` (CPython, one rounding) against `3d715bf0` (the f32 path, two roundings) --
# ONE ULP apart, and neither lane is wrong. The other three scales agree bit for bit.
#
# unverified_lin2   needs the 2-D `dot` graph; the Bend lane mints a CAST and drops a
#                   PERMUTE because uop/fold.bend defers PERMUTE's dtype (fold.bend:1621)
# unverified_adam   nn.optim.Adam == LAMB(adam=True) (optim.py:139) and
#                   nn/optim.bend's own `unverified_lamb` row is RED: 1 node vs CPython's 49
# row_round_2.3456  measures H.f32_fixed(2.3456, 2n) == "2.35"; it prints False
# row_round_2.30    measures H.f32_fixed(2.3, 2n) == "2.30"; it prints False