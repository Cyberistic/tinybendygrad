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
from tinygrad import Tensor, dtypes, nn  # noqa: E402


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


def sh(*dims):
  """CPython's tuple, printed as the port prints it: 4-D until flattened. THE PORT CARRIES
  A FLATTENED SHAPE AS FOUR DIMS WITH TWO UNIT ONES (`h = w = 1`), so a two-element tuple
  from the real chain is padded the same way and the two spellings cannot disagree."""
  ds = tuple(dims) + (1, 1) * (4 - len(dims))
  return f"({ds[0]},{ds[1]},{ds[2]},{ds[3]})" if ds[2] * ds[3] != 1 else f"({ds[0]},{ds[1]})"


# `mdl_walk` / `mdl_lin_in` / `mdl_out` ARE NOW COMPUTED BY tinygrad ITSELF, by calling
# `nn.Conv2d(...)(x)`, `Tensor.relu`, `nn.BatchNorm(...)(x)`, `Tensor.max_pool2d()`,
# `Tensor.flatten(1)` and `nn.Linear(...)(x)` on a lazy `Tensor.empty`. NOTHING IS
# REALIZED, so this needs no device and no data -- every step is a shape fact.
#
# WHY THIS REPLACED A FORMULA. The previous draft of this oracle carried
# `conv_out = (n, cout, h - k + 1, w - k + 1)` and `pool_out = (n, c, h // 2, w // 2)`
# with a docstring citing `_apply_ceil_mode` and `stride == kernel_size`. That is the
# SAME REDUCTION the Bend side used, so the two lanes could only ever agree, and the row
# was green against a `_pool` that was wrong. The Bend side now goes through
# `mixin/movement.bend`'s `mx_pool_shape`, which is `_pool`'s real `o_` comprehension
# (movement.py:604) for ANY stride and dilation, and this side now calls `conv2d` and
# `max_pool2d` for real -- so a wrong `o_` on either lane turns the row RED.
#
# THE LAYER TABLE IS THE SAME FOURTEEN ENTRIES in the same order, and it is what drives
# BOTH sides, so the rows still say what they said: the model, walked.
LAYERS = [("conv2d", 1, 32, 5), ("relu",), ("conv2d", 32, 32, 5), ("relu",), ("batchnorm", 32), ("max_pool2d",),
          ("conv2d", 32, 64, 3), ("relu",), ("conv2d", 64, 64, 3), ("relu",), ("batchnorm", 64), ("max_pool2d",),
          ("flatten", 1), ("linear", 576, 10)]


def cell(L):
  return f"{L[0]}({','.join(str(x) for x in L[1:])})"


def step(L, x):
  """ONE LAYER, by the real method, on a lazy tensor. `nn.Conv2d` keeps the layer so its
  parameters exist, but every shape below is decided before any of them is read."""
  kind = L[0]
  if kind == "conv2d":
    _, ci, co, k = L
    return nn.Conv2d(ci, co, k)(x)
  if kind == "relu":
    return x.relu()
  if kind == "batchnorm":
    return nn.BatchNorm(L[1])(x)
  if kind == "max_pool2d":
    return x.max_pool2d()
  if kind == "flatten":
    return x.flatten(L[1])
  if kind == "linear":
    return nn.Linear(L[1], L[2])(x)
  raise ValueError(kind)


def walk(ll=None):
  """The shape walk, and `ll` defaults to the whole table so the SAME function produces
  `mdl_walk` (all fourteen) and `mdl_lin_in` (the first thirteen, whose product is the
  576 that `nn.Linear(576, 10)` asserts). Returns `(row, final_shape)`."""
  ll = LAYERS if ll is None else ll
  x, out = Tensor.empty((1, 1, 28, 28)), []
  for L in ll:
    x = step(L, x)
    out.append(f"{L[0]}={sh(*x.shape)}")
  return " ".join(out) + " ", x.shape


def pool_shape(shape, k, stride):
  """`_pool`'s FULL output shape -- `noop ++ o_ ++ k_` -- which is the intermediate both
  `conv2d` (op.py:1546-1553) and `max_pool2d` (op.py:1370-1371) reduce over and which the
  REDUCED shape in `mdl_walk` cannot show. This is the row `mdl_pool_*`, and it is the
  one place the trailing kernel dims are visible at all."""
  return tuple(Tensor.empty(shape)._pool((k, k), stride, 1).shape)


def const_like_sig(shape):
  """`Y.const_like(True, dtypes.bool)` (op.py:1740) as a SIGNATURE, because its shape is
  ONE-dimensional -- and a one-element shape arg is a BARE CONST
  (`tinybendygrad/tensor.bend:587`, CPython's ops.py:110), which `mxm_as_shape` reads no
  srcs from and therefore answers `Nil{}` for. So the ONE-dim shape is un-gateable and
  the ONE-dim GRAPH is, which is the row `w3_mask`."""
  return sig(Tensor.empty(shape, dtype=dtypes.long).const_like(True, dtypes.bool))


def const_like_dims(shape):
  """The SAME node at a shape arg of length != 1, where `mxm_as_shape` CAN read it, so
  the row `w3_mask2d` can see the DIM that `w3_mask`'s signature cannot -- a signature is
  `3 CONST/0 CONST/0 EXPAND/2` for every dim, which is why `mn_mask`'s dim was a measured
  blind spot before this row existed. Both rows go through the port's `mn_mask`, so this
  is a shape control on the same def and not a second fixture."""
  return tuple(Tensor.empty(shape, dtype=dtypes.long).const_like(True, dtypes.bool).shape)


def conv_out_ns():
  """THE NON-SQUARE CONTROL. Every shape in this model is square (`mdl_in` is
  `(1,1,28,30)`'s neighbour `(1,1,28,28)`, and every kernel is `k x k`), so `o_h == o_w`
  at every step and the Bend side can read its WIDTH out of the HEIGHT index without any
  row telling. Measured: that mutation moved nothing. This fixture is `(1,1,28,30)` and it
  goes through the real `nn.Conv2d(1, 32, 5)`, so the row supplies what the model cannot.
  """
  return tuple(nn.Conv2d(1, 32, 5)(Tensor.empty((1, 1, 28, 30))).shape)


# --- the rows, in the .bend file's order --------------------------------------
tbl, out_shape = walk()
n_out, c_out = out_shape[0], out_shape[1]
print("mdl_table=" + " ".join(cell(L) for L in LAYERS) + " ")
print(f"mdl_count={len(LAYERS)}")
print("mdl_pad5=" + ",".join(str(x) for x in (2, 2, 2, 2)))
print("mdl_pad3=" + ",".join(str(x) for x in (1, 1, 1, 1)))
print("mdl_in=(1,1,28,28)")
# `mdl_pool_*` -- `_pool`'s UNREDUCED shape, for the model's TWO distinct (kernel, stride)
# pairs. These are the rows W1 and W2 need and `mdl_walk` cannot carry, because `mdl_walk`
# prints the shape AFTER the reduce and the reduce is what eats `k_`.
print("mdl_pool_k5=" + ",".join(str(x) for x in pool_shape((1, 1, 28, 28), 5, 1)))
print("mdl_pool_k2s2=" + ",".join(str(x) for x in pool_shape((1, 32, 20, 20), 2, 2)))
print("mdl_pool_ns=" + sh(*conv_out_ns()))
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
print("w3_mask=" + const_like_sig((4,)))
print("w3_mask2d=" + ",".join(str(x) for x in const_like_dims((4, 10))))

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