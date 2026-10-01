import Base
import ./optim.bend as OP

# tinybendygrad/nn/__init__.bend -- tinygrad/nn/__init__.py (420 lines).
#
# NOT STARTED. This is a PLACEHOLDER, kept deliberately visible so that nobody reads
# `tinybendygrad/nn/` as done. It is the stub this unit created first, per the brief,
# so that a server restart could not lose the directory.
#
# WHAT IS IN THIS UNIT AND WHERE IT STANDS:
#
#   tinygrad/nn/optim.py     179 lines -> tinybendygrad/nn/optim.bend   PARTIAL
#   tinygrad/nn/state.py     299 lines -> (not started)
#   tinygrad/nn/datasets.py   14 lines -> (not started)
#   tinygrad/nn/torch.py       4 lines -> (not started)
#   tinygrad/nn/__init__.py  420 lines -> THIS FILE
#   tinygrad/nn/onnx.py     1319 lines -> OUT OF THIS UNIT (see below)
#
# `optim.bend`'s own header carries its honest gate state: FOUR rows green against the
# CPython oracle (`op_params`, `op_bufs`, `op_acc`, `op_nop`) and SEVEN printed under
# `unverified_*` names because they do not yet match. The `_step` graph construction is
# ported and believed arithmetically correct; the ARENA PLUMBING under it is not
# finished. Read that header before trusting anything in this directory.
#
# WHAT `nn/__init__.py` NEEDS, so the next pass does not re-derive it:
#
#   * EVERY layer's `__call__` is a MIXIN method and NOT MINE: `x.linear` is
#     `mixin/op.py:1254`, `x.batchnorm` is `:1662`, `x.layernorm` is `:1644`,
#     `x.conv2d` and `x.conv_transpose2d` are in the same file, and `x.reshape` /
#     `x.permute` are `mixin/movement.py`. Each is a named `TODO(p3)` with the op it
#     resolves to -- which for the ELEMENTWISE ones is an `Ops.*` I can build directly
#     (`optim.bend`'s gate is the proof: `t.detach() - up` builds `DETACH` + `SUB`
#     without any mixin method existing).
#   * WHAT IS GENUINELY PORTABLE IN `__init__.py`, and it is the shape arithmetic:
#       - `Conv2d.__init__`'s `make_tuple(kernel_size, 2)` and the `padding='same'`
#         list comprehension at :102-103, `pad = [(d*(k-1)//2, d*(k-1) - d*(k-1)//2)
#         for d,k in zip(make_tuple(dilation, len(...))[::-1], self.kernel_size[::-1])]`
#         followed by `flatten(pad)`. PURE INTEGERS, and gateable against CPython
#         exactly -- this is the best remaining candidate in the file.
#       - `BatchNorm.calc_stats`'s `shape_mask = [1, -1, *([1]*(x.ndim-2))]` and its
#         `reduce_axes = tuple(x for x in range(x.ndim) if x != 1)` (:42, :47).
#       - `LayerNorm.__init__`'s `self.axis = tuple(-1-i for i in range(len(...)))`
#         (:253) and the `assert self.normalized_shape == x.shape[-len(...):]` (:258).
#       - `GroupNorm`/`InstanceNorm`'s `x.reshape(x.shape[0], num_groups, -1)` and the
#         affine `reshape(1, -1, *[1] * (x.ndim-2))` (:203, :207, :231, :233).
#       - `LSTMCell.__init__`'s four parameter SHAPES (:409-412).
#     Those are all gateable as STRING rows with no device and no mixin dependency, and
#     they are where a bug in `nn/__init__.py` would actually live.
#   * WHAT IS A WALL: `_embedding_bwd` (:307-367) writes two RAW KERNELS through
#     `UOp.range`/`store`/`end`/`sink` and a `functools.cache`d `_embedding_fwd_fxn`
#     (:373) -- that is codegen, not graph building, and it is a `TODO(p3)` in full.
#     `USE_ATOMICS` selects between the kernel path and `_embedding_fwd` (:369-396),
#     and only the second is graph-building.
#   * `onnx.py` (1319 lines) is a SEPARATE CONCERN from the layer surface and was not
#     part of this unit's brief. It is not started and should get its own agent.
#
# THE CONST-LITERAL CONSTRAINT CARRIES OVER. `scale = 1 / math.sqrt(...)`, `bound =
# 1 / math.sqrt(in_features)`, `eps=1e-5`, `momentum=0.1` are Python FLOATS and a Bend
# float literal is `O.CFloat{1.0}` -- which `optim.bend` proves IS reachable, contrary
# to the stale `TODO(p3)` at `tensor.bend:308`. So `Tensor.uniform(..., low=-scale,
# high=scale)` is reachable as a CONST once someone ports `mixin/rand.py`'s `rand`.
def main() -> IO(Unit):
  IO.print("nn/__init__.bend is NOT STARTED -- see its header")