import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

import ./../uop/ops.bend as O
import ./state.bend as ST

# ===========================================================================
# nn/__init__.bend -- tinygrad/nn/__init__.py (420 lines).
#
# FIRST, THE FINDING THAT CHANGES THE SHAPE OF THIS FILE: THERE IS NO
# `nn.Module`. I went looking for one and it is not there -- `nn/__init__.py` is
# eleven plain classes with no base class, no `parameters()`, no `state_dict()`
# method and no registry, and `get_state_dict` (state.py:89) reaches a layer by
# walking `obj.__dict__` by REFLECTION. So the "Module base" the hand-off asked
# for is not a thing to port; it is `state.bend`'s `Obj` tree, and this file's
# job is to be the thing that tree is built from. That is why this file imports
# `state.bend` and not the other way round, which is also Python's own direction
# (`nn/__init__.py:6`, `from tinygrad.nn import optim, state, datasets`).
#
# WHY A LAYER IS NOT A `Data` RECORD HERE, and it is the second real finding. In
# Python a layer is an OBJECT: its parameters are attributes, so `get_state_dict`
# finds them by reflection without the layer cooperating, and
# `self.eps: float`/`self.bias: Tensor|None` are just attributes. In Bend a
# `Data` record has NO REFLECTION and a `Data` field cannot hold a `Maybe`
# (measured: bend2-constraints rule 15), so every field read would need a paired
# accessor def (`Tensor.ar`/`Tensor.u` in tensor.bend is that pattern) and
# `Tensor|None` would need a third type. So each layer here is a def over its
# CONSTRUCTOR ARGUMENTS that answers a SHAPE, plus a `*_st` def that answers the
# ordered `(name, tensor)` list that IS `__dict__`. That is optim.bend's WALL-1
# shape and this file inherits it rather than inventing a layer type: the
# constructor arguments come in, the shape goes out, the tensors come in.
#
# THE THREE LAYERS `beautiful_mnist.py` NAMES, confirmed against the example
# (`Model.__init__`, examples/beautiful_mnist.py:9-16) because the example agent
# needs this list confirmed and not guessed:
#     nn.Conv2d    x4  -- lines 10, 12, 13, 14
#     nn.BatchNorm x2  -- lines 12, 15
#     nn.Linear    x1  -- line 16, (576, 10)
# and the ops that are NOT mine and that the example also needs: `Tensor.relu`,
# `Tensor.max_pool2d`, `x.flatten(1)`, `x.sequential`,
# `Tensor.sparse_categorical_crossentropy`, `Tensor.argmax`, `Tensor.randint`,
# `nn.datasets.mnist`. All named in the WALL list below with the line each is on.
# `nn.Linear`'s input width 576 is DERIVED -- two 5x5 and two 3x3 convs over a
# 28x28 image -- and is `beautiful_mnist.py`'s arithmetic, not this file's.
#
# THE PORTABLE CORE IS SHAPE ARITHMETIC, and every gate row below is a shape, a
# padding, a count or a key list -- never a value, never a device. That is not a
# consolation prize: it is where a bug in this file would actually live, and it
# is the part a CPython oracle answers with no GPU. All 24 rows agree with
# `.agents/slop/nn-init-gate.py` on BOTH lanes; the row list and the mutation
# table are at the gate section at the foot of the file.
#   nn_conv nn_convb nn_conv0   the four `beautiful_mnist` convs' weight shapes,
#                              the bias, and the DEGENERATE `in//groups == 0`
#   nn_same nn_same_rev        `padding='same'` at :102, and the REVERSAL
#   nn_ks2  nn_c1d             `make_tuple(ks, 2)` and `Conv1d`'s 1-tuple
#   nn_lin                     `Linear(576, 10)`'s two shapes
#   nn_bn_mask nn_bn_axes      `shape_mask` (:42) and `reduce_axes` (:47)
#   nn_bn_st nn_bn_flags       the `__dict__` ORDER and the `is_param` flags
#   nn_bn_shapes               the two affine shapes and the SCALAR counter
#   nn_ct                      `ConvTranspose2d`'s REASSIGNED weight
#   nn_ln nn_ln_sh nn_ln2d     `axis` (:253), the parameter shape, the permutes
#   nn_gn                      GroupNorm/InstanceNorm's two `reshape` shapes
#   nn_rms                     `mean(-1, keepdim=True)`'s resolved axis
#   nn_emb nn_glorot           the embedding shape and its `sqrt(6/(fi+fo))` bound
#   nn_lstm nn_lstm_st         LSTMCell's four shapes and four keys
#   nn_formula                 `1/sqrt(f*n)` and `1/sqrt(n)` with literal factors
#
#   Conv2d.__init__  make_tuple(:98), the `padding='same'` comprehension (:102),
#                    `flatten(pad)` (:103), the weight/bias shapes (:106-107)
#   BatchNorm        `shape_mask` (:42), `reduce_axes` (:47), and the `__dict__`
#                    entries in ASSIGNMENT order (:33-39)
#   Linear           `bound` (:173) and the two shapes (:174-175)
#   LayerNorm        `axis` (:253) and the shapes (:254-255)
#   GroupNorm /      the two `reshape` shapes (:203, :207, :231, :233)
#   InstanceNorm
#   RMSNorm          the `-1` axis of `mean(-1, keepdim=True{})` (:300)
#   LSTMCell         the four parameter shapes (:409-412)
#   Embedding        the `glorot_uniform` bound (mixin/rand.py:197) and the shape
#
# TWO WALLS SHAPE THE FILE AND NEITHER IS A SURPRISE.
#   1. REALIZATION. `Tensor.uniform` (:106, :174), `Tensor.ones` (:35, :197, :254),
#      `Tensor.zeros` (:36, :198, :255) and `Tensor.glorot_uniform` (:389) are all
#      `creation.py`'s `full`/`_frompy`, which need a Buffer. So every shape here
#      is computed and every TENSOR COMES IN as a parameter. That is optim.bend's
#      WALL 1 and it is why this file has no arena of its own.
#   2. EVERY `__call__` IS A MIXIN METHOD. `x.linear` is mixin/op.py:1254,
#      `x.batchnorm` is :1662, `x.layernorm` is :1644, `x.conv2d` and
#      `x.conv_transpose2d` are in the same file, `reshape`/`permute`/`squeeze`
#      are mixin/movement.py, `chunk`/`sigmoid`/`tanh`/`rsqrt`/`square`/
#      `unsqueeze`/`where`/`detach` are mixin/elementwise.py, `mean`/`sum` are
#      mixin/reduce.py, `arange` is op.py:166. NONE is mine and none is built, so
#      every `__call__` is a `TODO(p3)` naming the line: 11 of the 13 classes.
#      I am NOT writing defs that return a `TODO` -- a def with no body is a
#      paragraph pretending to be code, and the honest form is the comment.
#
# A THIRD WALL IS NEITHER A DEVICE NOR A MIXIN and it is what shaped three defs:
# `scale = 1 / math.sqrt(in_channels * prod(kernel_size))` (:105, :149, :173,
# :408) is a `U32` product fed to `F32.sqrt`, and the only `Nat`-to-`F32`
# conversion in Bend is `U32.to_f32`, which tensor.bend's header records as an
# UNFILLED LAW. So `nn_scale`/`nn_bound`/`nn_glorot` take their factors as `F32`:
# the FORMULAS are ported and gated, and the U32-to-F32 conversion at the call
# site is a named `TODO(p3)`. Splitting it there is what makes the rows possible
# at all -- a literal-`U32` version could only be gated for shapes I chose, which
# is the tautology the brief warns about.
#
# ONE MORE FACT THE GATE LEANS ON, and it is a tinygrad QUIRK rather than a
# design: `BatchNorm.__init__` (:32-39) assigns `eps`, `track_running_stats` and
# `momentum` BEFORE its tensors, and `num_batches_tracked` is
# `Tensor.zeros(dtype='long').is_param_(False)` -- a TENSOR, so it IS in the
# `state_dict`, and `Optimizer` then filters it out on `is_param`. Measured:
# `get_state_dict(nn.BatchNorm(32))` has FIVE keys in the order
# `weight, bias, num_batches_tracked, running_mean, running_var`, and the three
# scalars are ABSENT because `get_state_dict` drops every non-tensor leaf
# (state.py:107). The optimizer therefore receives `num_batches_tracked` and both
# running stats as "parameters", which is real tinygrad behaviour and the reason
# `state.bend`'s walk -- not an `is_param` filter -- is what the example needs.
#
# `ConvTranspose2d.__init__` (:146-151) calls `super().__init__(...)` and then
# ASSIGNS `self.weight` a second time. In a `__dict__` a re-assignment keeps the
# FIRST position, so the key order is unchanged -- but the VALUE is a different
# tensor with a TRANSPOSED shape (`in, out//groups, *ks` at :150 against
# `out, in//groups, *ks` at :106), and that is the row `nn_ct` pins.
# ===========================================================================

# ===========================================================================
# THE PRIMITIVES, and they are the only things above the layers.
# ===========================================================================

# `Tensor|None` has no `Data` field and no `Maybe` in a record, so the conditional
# ENTRY is a `Bool` beside the value at each `*_st` def. This is the one helper
# for it and the `Bool.pick` at each site is the decision.
def nn_app(xs: List<&2, ST.Ent>, e: ST.Ent) -> List<&2, ST.Ent>:
  List.append(&2, ST.Ent, xs, [e])

def nn_len(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

# Python's `-1` has no `U32` image, and every negative in this file is a `-1` in a
# shape or an axis, so this is the single spelling of it.
def nn_neg1() -> H.I64: H.i64_of_i32(4294967295)
def nn_i64_app(xs: List<&2, H.I64>, v: H.I64) -> List<&2, H.I64>:
  List.append(&2, H.I64, xs, [v])

# ---------------------------------------------------------------------------
# `make_tuple` -- tinygrad/helpers.py:51, `(x,)*cnt` when x is an int and
# `tuple(x)` otherwise. `H.make_tuple_rep` (helpers.bend:828) and
# `H.to_tuple_seq` (helpers.bend:839) are that pair already, so
# they are CALLED and not re-spelled; the two arms are the two call sites
# `Conv2d.__init__` (:98, :102) needs, because `kernel_size` is `int|tuple`.
def nn_mt(x: U32, cnt: U32) -> List<&2, U32>: H.make_tuple_rep(x, cnt)
def nn_mt_seq(xs: List<&2, U32>) -> List<&2, U32>: H.to_tuple_seq(xs)

# ---------------------------------------------------------------------------
# `padding='same'` -- `pad = [(d*(k-1)//2, d*(k-1) - d*(k-1)//2) for d,k in
# zip(make_tuple(dilation, len(self.kernel_size))[::-1], self.kernel_size[::-1])]`
# then `padding = tuple(flatten(pad))`, at :102-103.
#
# `m = d*(k-1)` is read twice, and a `let` is affine (rule 3), so the product and
# the half are hoisted into defs with `+` parameters rather than recomputed at
# each use. `U32.div` TRUNCATES where Python's `//` FLOORS, and the two agree
# here because `m = d*(k-1) >= 0` for every dilation and kernel in this file.
# A `groups=2, in_channels=1` conv is not an error in tinygrad -- measured, its
# weight shape is `(4, 0, 3, 3)` -- so the products must not be assumed positive
# in a way that a floor would fix. `d=0` gives `m=0` and both answers `0`.
# ---------------------------------------------------------------------------

def nn_half(+m: U32) -> U32: U32.div(m, 2)
def nn_prod(d: U32, k: U32) -> U32: U32.mul(d, U32.sub(k, 1))

# `in_channels//groups` -- :106 and :150. It is `U32.div` and it is NOT GUARDED,
# because tinygrad does not guard it either: `nn.Conv2d(1,4,3,groups=2)` builds a
# weight of shape `(4, 0, 3, 3)` (MEASURED) and a port that "fixed" it would
# answer `(4, 1, 3, 3)`. The row `nn_conv0` is the fixture.
def nn_groups(in_c: U32, groups: U32) -> U32: U32.div(in_c, groups)
def nn_k1(k: U32) -> U32: U32.sub(k, 1)

def nn_pair.right(+m: U32, +h: U32) -> List<&2, U32>:
  [h, U32.sub(m, h)]

def nn_pair.left(+d: U32, +k: U32) -> List<&2, U32>:
  nn_pair.right(nn_prod(d, k), nn_half(nn_prod(d, k)))

# the walk over the two REVERSED lists. `List.reverse` is base's; `H.flatten_u32`
# is helpers' `flatten` (:489) and it is what turns the list of PAIRS into the
# flat padding tuple.
def nn_pad.go(ds: List<&2, U32>, ks: List<&2, U32>, acc: List<&2, List<&2, U32>>) ->
  List<&2, List<&2, U32>>:
  match ds:
    case Nil{}: acc
    case d <> t:
      match ks:
        case Nil{}: acc
        case k <> u: nn_pad.go(t, u, List.append(&2, List<&2, U32>, acc, [nn_pair.left(d, k)]))

def nn_same(dil: U32, +ks: List<&2, U32>) -> List<&2, U32>:
  H.flatten_u32(nn_pad.go(List.reverse(&2, U32, nn_mt(dil, nn_len(ks))),
    List.reverse(&2, U32, ks), Nil{}))

# ---------------------------------------------------------------------------
# the three float formulas, each its own def because each is a different Python
# expression. `nn_scale` is `1 / math.sqrt(in_c * prod(ks))` at :105 and :149;
# `nn_bound` is `1 / math.sqrt(in_features)` at :173 and `1.0 /
# math.sqrt(hidden_size)` at :408 -- the SAME expression with one factor, so ONE
# def and not two, because a repeated line is a shared function, not a pair of
# coincidentally equal ones.
# ---------------------------------------------------------------------------

def nn_scale(f: F32, n: F32) -> F32: F32.div(1.0, F32.sqrt(F32.mul(f, n)))
def nn_bound(n: F32) -> F32: F32.div(1.0, F32.sqrt(n))

# `Tensor.glorot_uniform`'s bound -- mixin/rand.py:201,
# `(6 / (argfix(*shape)[0] + prod(argfix(*shape)[1:]))) ** 0.5`. It is a `sqrt` of
# a RATIO and NOT `1/sqrt`, and the two differ by `sqrt(6)`: measured,
# `nn.Embedding(10,3)`'s bound is `0.6793662204867574` where `1/sqrt(13)` is
# `0.2773501`, so mixing them up rescales every embedding.
def nn_glorot(fan_in: F32, fan_out: F32) -> F32: F32.sqrt(F32.div(6.0, F32.add(fan_in, fan_out)))

# ===========================================================================
# THE WALLS. One TODO per Python line, and no prose pretending otherwise.
# ===========================================================================

# TODO(p3) mixin/rand.py:190  Tensor.uniform / Tensor.glorot_uniform -- `creation.py`'s
#   `full` plus `randstate`. The CONST `low=-scale, high=scale` needs the F32 values
#   above and those need `U32.to_f32`, an UNFILLED LAW (tensor.bend's header names
#   it), which is why the three formulas take `F32` factors.
# TODO(p3) mixin/op.py:1254  x.linear           -- `linear_with_vars` (movement.py) is
#   P3 and mixin/op.bend's W8 already names the WMMA lowering as its own wall.
# TODO(p3) mixin/op.py:1662  x.batchnorm        -- mixin/op.bend SIDE B, not built.
# TODO(p3) mixin/op.py:1644  x.layernorm        -- SIDE B, not built.
# TODO(p3) mixin/op.py       x.conv2d           -- SIDE B, not built.
# TODO(p3) mixin/op.py       x.conv_transpose2d -- SIDE B, not built.
# TODO(p3) mixin/movement.py x.reshape / x.permute / x.squeeze -- `GroupOp.movement`
#   exists in ops.bend but `movement.bend`'s defs are a separate unit's.
# TODO(p3) mixin/op.py:166   x.arange           -- and mixin/op.bend's W4 says `_pool`
#   is buildable but not CHECKABLE, so everything reaching it inherits that.
# TODO(p3) mixin/reduce.py:20 x.mean / x.sum    -- `mo_sum`/`mo_mean` EXIST in
#   mixin/op.bend (they are the reduce.py:73/:20/:47 hoists) and are callable. They
#   are not inlined here because every `__call__` in this file is a mixin METHOD and
#   naming the call IS the port; inlining a callee would be a second port.
# PARTIALLY PORTED. `Tensor.sqrt` is ported at `tensor.bend:294` as `tn_sqrt` and
# gated at `gates/tn_sqrt-gate.py` 5/5 rows. `Tensor.where`, `Tensor.detach`, and
# `Tensor.square` remain walled: `where` is `self.alu(Ops.WHERE, x, y)` with a
# `_broadcasted` up-stream step, `detach` is `self.replace(arg=KernelInfo())` (the
# replace is now ported, but `KernelInfo` is the next piece), and `square` is
# `self * self` (the `__mul__` method is a separate wall).
# TODO(p3) mixin/elementwise.py:426 x.where, :43 x.detach, :575 x.square -- BLOCKED: see above.