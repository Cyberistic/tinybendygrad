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
# `make_tuple` -- helpers.py:1326, `(x,)*cnt` when x is an int and `tuple(x)`
# otherwise. `H.make_tuple_rep` and `H.to_tuple_seq` are that pair already, so
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

# `Tensor.glorot_uniform`'s bound -- mixin/rand.py:197,
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
# TODO(p3) mixin/elementwise.py:426 x.where, :43 x.detach, :480 x.sqrt, :575 x.square
# TODO(p3) mixin/op.py:1971  x.nbytes           -- only `safe_save` needs it and that
#   is `state.bend`'s wall.
# TODO(p3) nn/__init__.py:307 _embedding_bwd -- a RAW KERNEL. `UOp.range`, `.store`,
#   `.end`, `.sink`, `UOp.range(BLOCK_J, 2, AxisType.WEAK)`, an
#   `index`/`load`/`where`/`clip`/`cast` chain, and an `Ops.CUSTOM` atomic whose
#   third argument is a device-specific C SNIPPET chosen by
#   `if device in ("CPU","NULL")` / `elif device == "AMD"` / `else: raise`. That is
#   CODEGEN and it is a wall IN FULL. `USE_ATOMICS` then selects between this and
#   `_embedding_fwd`, and only the second is graph building.
# TODO(p3) nn/__init__.py:369 _embedding_fwd -- `(arange == idx.unsqueeze(-1))
#   .unsqueeze(-1).where(weight, 0).sum(-2, dtype=weight.dtype)`: four mixin methods
#   and an `arange`, of which the `arange` is W4. The output SHAPE is gated below
#   and the graph is not built.
# TODO(p3) nn/__init__.py:373 _embedding_fwd_fxn -- `functools.cache`d on
#   `(wp, ip, device)`, i.e. memoised over UOp IDENTITY. A `Data` record has no
#   identity to key on and no globals to hold a cache in.
# TODO(p3) nn/datasets.py:1  mnist -- a download, an unzip and an `open`.

# ===========================================================================
# THE LAYERS, IN PYTHON'S ORDER.
# ===========================================================================

# ---------------------------------------------------------------------------
# BatchNorm -- :8-60. `BatchNorm2d = BatchNorm3d = BatchNorm` (:60) is an ALIAS
# and not a subclass, so it is two more names over one set of defs.
# ---------------------------------------------------------------------------

# the parameter shapes -- `Tensor.ones(sz)` at :35 and :39, `Tensor.zeros(sz)` at
# :36 and :39, `Tensor.zeros(dtype='long')` at :38. The last is a SCALAR, so its
# shape is the EMPTY list, and that is the one shape in this file that is `Nil{}`.
# `affine` is the `Tensor.ones(...) if affine else None` ternary at :35-36.
def bn_w(sz: U32, affine: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, affine, [sz], Nil{})

def bn_b(sz: U32, affine: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, affine, [sz], Nil{})

def bn_nbt() -> List<&2, U32>: Nil{}

# `__dict__` in ASSIGNMENT order -- :33-39. `eps`, `track_running_stats` and
# `momentum` are assigned first and are NOT TENSORS, so they contribute no key
# (state.py:107); the five that do appear are the four below plus the scalar.
# `is_param_` is `tensor.py:141` and is a REAL ported line: it is the flag
# `Optimizer` (:13) filters on, and getting it wrong would put
# `num_batches_tracked` and both running stats into the optimizer's `params`.
def bn_st.trk(track: Bool, +acc: List<&2, ST.Ent>, rm: T.Tensor, rv: T.Tensor) -> List<&2, ST.Ent>:
  Bool.pick(List<&2, ST.Ent>, track,
    nn_app(nn_app(acc, ST.Ent{"running_mean", T.tn_is_param_(rm, False{})}),
      ST.Ent{"running_var", T.tn_is_param_(rv, False{})}),
    acc)

def bn_st.aff(affine: Bool, w: T.Tensor, b: T.Tensor) -> List<&2, ST.Ent>:
  Bool.pick(List<&2, ST.Ent>, affine,
    nn_app(nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})}),
      ST.Ent{"bias", T.tn_is_param_(b, True{})}),
    Nil{})

def bn_st(affine: Bool, track: Bool, w: T.Tensor, b: T.Tensor, nbt: T.Tensor,
    rm: T.Tensor, rv: T.Tensor) -> List<&2, ST.Ent>:
  bn_st.trk(track, nn_app(bn_st.aff(affine, w, b), ST.Ent{"num_batches_tracked", T.tn_is_param_(nbt, False{})}), rm, rv)

# `shape_mask: list[int] = [1, -1, *([1]*(x.ndim-2))]` -- :42. It is an `H.I64`
# list because the `-1` has no `U32` image. `ndim` is a PARAMETER because it
# comes from a fold over the input (`x.ndim` is mixin/op.bend's `mo_ndim`) and a
# fold is not callable from a gate fixture.
# THE COUNTDOWN IS A `Nat` AND THE INDEX IS A `U32`, and that is not a style
# choice: `case 0n:` is a `Nat` pattern and it does not match a `U32` at all
# (MEASURED: "expected : a constructor of U32"). So `n` counts down as a `Nat`
# and `i` -- the axis index, which IS a `U32` because it is what
# `x.mean(axis=...)` is given -- counts up.
# NO REVERSE AT THE END. The accumulator is appended at the TAIL (`nn_i64_app`
# is `List.append`), so it is already in axis order and reversing it undoes the
# walk. The gate measured this: the first version answered `mask4=[1,1,-1,1]`
# against Python's `[1, -1, 1, 1]`. `state.bend`'s walk reverses because IT
# conses onto the head; these two append, and the difference is the whole bug.
# `[1] * (x.ndim - 2)` SATURATES AT ZERO, and the two head elements are ALWAYS
# present. MEASURED against `[1, -1] + [1]*(n-2)` for n = 1, 2, 3, 4:
# `[1,-1]`, `[1,-1]`, `[1,-1,1]`, `[1,-1,1,1]`. A walk that emitted `ndim`
# elements -- which is what the first version of this def did, and what an
# index-and-compare walk does naturally -- answers `[1]` for `ndim == 1`, and a
# one-element mask is not a broadcastable shape at all. The gate measured
# `mask4` correctly and this row (`nn_bn_mask`'s `ndim == 2` half) is what caught
# the shape of the mistake.
def nn_sat2(n: Nat) -> Nat:
  match n:
    case 0n: 0n
    case Succ{0n}: 0n
    case Succ{Succ{p}}: p

def bn_mask.go(n: Nat, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match n:
    case 0n: acc
    case Succ{p}: bn_mask.go(p, nn_i64_app(acc, H.i64_of_i32(1)))

def bn_mask(ndim: U32) -> List<&2, H.I64>:
  bn_mask.go(nn_sat2(U32.to_nat(ndim)), [H.i64_of_i32(1), nn_neg1()])

def bn_axes.go(n: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case Succ{p}:
      bn_axes.go(p, U32.add(i, 1), Bool.pick(List<&2, U32>, U32.is_eq(i, 1),
        acc, List.append(&2, U32, acc, [i])))

def bn_axes(ndim: U32) -> List<&2, U32>:
  bn_axes.go(U32.to_nat(ndim), 0, Nil{})

# ---------------------------------------------------------------------------
# Conv1d / Conv2d -- :62-109. `Conv1d` (:62-78) is a FUNCTION that forwards to
# `Conv2d` with `kernel_size` wrapped in a 1-tuple, so it has no arithmetic of
# its own and the row `nn_c1d` pins only that wrapping.
# ---------------------------------------------------------------------------

# the two `kernel_size` arms again, as a `Data` sum type, because a Bend def
# cannot take `int|tuple` and `Bool.pick` on `nn_len(ks) == 0` is the test that
# a `List` is empty. `Ks2{v: U32}` is the INT arm and `Ks2{s: List<&2, U32>}` is
# the TUPLE arm, and the constructor IS the sum type -- no flag, no `Maybe`.
type Ks2 is Data:
  Ks2{v: U32}
  Ks2s{s: List<&2, U32>}

def conv_ks.of(k: Ks2) -> List<&2, U32>:
  match k:
    case Ks2{v}: H.make_tuple_rep(v, 2)
    case Ks2s{s}: H.to_tuple_seq(s)

# `Conv1d(...)` -> `Conv2d(..., (kernel_size,), ...)` -- :78
def conv_ks1(k: U32) -> List<&2, U32>: H.make_tuple_rep(k, 1)

# `self.weight = Tensor.uniform(out_channels, in_channels//groups, *self.kernel_size)`
# -- :106. `//` is a floor and the dividend is `U32`, so it is `U32.div`; the
# degenerate `groups=2, in_channels=1` case gives `0` and MEASURED agrees
# (`nn.Conv2d(1,4,3,groups=2).weight.shape` is `(4, 0, 3, 3)`), so this is not
# guarded and must not be.
def conv_w(out_c: U32, in_c: U32, groups: U32, ks: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [out_c, nn_groups(in_c, groups)], ks)

# `self.bias: Tensor|None = Tensor.uniform(out_channels, ...) if bias else None`
# -- :107
def conv_b(out_c: U32) -> List<&2, U32>: [out_c]

# `self.stride, self.dilation, self.groups, self.padding = stride, dilation,
# groups, padding` -- :104. The default `padding=0` is a scalar and the
# `padding='same'` arm is a list, so the stored padding is a LIST in both arms
# and the scalar arm is a one-element list. That is a DIVERGENCE and it is forced:
# a `Data` value cannot be `int|tuple`, and a layer's `padding` is read by
# `x.conv2d(..., self.padding)` (:109), which wants the tuple. MEASURED:
# `nn.Conv2d(1,1,3).padding` is the int `0` and `nn.Conv2d(1,1,3,
# padding='same').padding` is the tuple `(1, 1, 1, 1)`.
def conv_pad(dil: U32, ks: List<&2, U32>) -> List<&2, U32>:
  nn_same(dil, ks)

# ---------------------------------------------------------------------------
# ConvTranspose1d / ConvTranspose2d -- :111-154. `ConvTranspose2d` SUBCLASSES
# `Conv2d` (:130) and its `__init__` (:146-151) calls `super().__init__(...)` and
# then REASSIGNS `self.weight`. In a `__dict__` a re-assignment keeps the FIRST
# position, so the key order is unchanged; the VALUE is a different tensor with a
# TRANSPOSED shape.
# ---------------------------------------------------------------------------

def convT_w(in_c: U32, out_c: U32, groups: U32, ks: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [in_c, nn_groups(out_c, groups)], ks)

def convT_st(w: T.Tensor, b: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})}),
    ST.Ent{"bias", T.tn_is_param_(b, True{})})

# `ConvTranspose1d(...)` -> `ConvTranspose2d(..., (kernel_size,), ...)` -- :128
def convT_ks1(k: U32) -> List<&2, U32>: H.make_tuple_rep(k, 1)

# ---------------------------------------------------------------------------
# Linear -- :156-177. The simplest layer in the file and the one the example
# needs last, which makes it the right one to read first.
# ---------------------------------------------------------------------------

# `Tensor.uniform(out_features, in_features, ...)` -- :174
def lin_w(in_f: U32, out_f: U32) -> List<&2, U32>: [out_f, in_f]

# `Tensor.uniform(out_features, ...) if bias else None` -- :175
def lin_b(out_f: U32) -> List<&2, U32>: [out_f]

def lin_st(w: T.Tensor, b: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})}),
    ST.Ent{"bias", T.tn_is_param_(b, True{})})

# ---------------------------------------------------------------------------
# GroupNorm -- :179-207 and InstanceNorm -- :209-233. Their `__call__`s are the
# SAME two lines with different field names (:203/:207 and :231/:233), so the two
# `reshape` shapes are two defs shared by both classes rather than four.
# ---------------------------------------------------------------------------

# `x.reshape(x.shape[0], num_groups, -1)` -- :203 and :231. The `-1` is Python's
# INFERRED dimension and it is what makes the shape `(N, G, -1)`; it survives
# into the graph as a `RESHAPE` with a `S.U` dim, not a number, and that is why
# this is the shape the port can state and not the shape the fold can read.
def gn_reshape(n: U32, groups: U32) -> List<&2, H.I64>:
  [H.i64_of_i32(n), H.i64_of_i32(groups), nn_neg1()]

# `self.weight.reshape(1, -1, *[1] * (x.ndim-2))` -- :207 and :233. `1, -1` and
# then `ndim-2` ones.
def gn_affine.go(n: Nat, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match n:
    case 0n: acc
    case Succ{p}: gn_affine.go(p, nn_i64_app(acc, H.i64_of_i32(1)))

def gn_affine(ndim: U32) -> List<&2, H.I64>:
  gn_affine.go(U32.to_nat(U32.sub(ndim, 2)), [H.i64_of_i32(1), nn_neg1()])


def gn_st(w: T.Tensor, b: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})}),
    ST.Ent{"bias", T.tn_is_param_(b, True{})})

# ---------------------------------------------------------------------------
# LayerNorm -- :235-261 and LayerNorm2d -- :263-279.
# ---------------------------------------------------------------------------

# `self.normalized_shape: tuple[int, ...] = make_tuple(normalized_shape, 1)`
# -- :252, and it is the shape of BOTH parameters (:254-255).
# `normalized_shape` is `int|tuple` at :251 and BOTH are legal, so it is the
# `Ks2` sum type again rather than a list with a length test.
def ln_shape.of(n: Ks2) -> List<&2, U32>:
  match n:
    case Ks2{v}: [v]
    case Ks2s{s}: s

# `self.axis, self.eps = tuple(-1-i for i in range(len(self.normalized_shape))), eps`
# -- :253. NEGATIVE and DECREASING: for a one-element `normalized_shape` it is
# `(-1,)` and for two it is `(-1, -2)`, and it is `x.layernorm(eps=..., axis=...)`'s
# axis list (:259) so the sign is load-bearing. `H.I64` for the sign.
# `-1-m` for the m-th axis, as an `H.I64` BUILT rather than subtracted: base has
# `U32.to_nat` and NOT `Nat.to_u32` (MEASURED, `rg` over base.bend), so the
# magnitude cannot come out of the `Nat` countdown. It is a second `U32`
# parameter instead, and the two's complement of `-1-m` is
# `hi = 0xFFFFFFFF, lo = 0xFFFFFFFF - m`, which is `i64_of_hi_lo` and no
# subtraction at all.
def ln_axis.go(n: Nat, +m: U32, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match n:
    case 0n: acc
    case Succ{p}: ln_axis.go(p, U32.add(m, 1),
      nn_i64_app(acc, H.i64_of_hi_lo(4294967295, U32.sub(4294967295, m))))

def ln_axis(n: U32) -> List<&2, H.I64>:
  ln_axis.go(U32.to_nat(n), 0, Nil{})

def ln_st(w: T.Tensor, b: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})}),
    ST.Ent{"bias", T.tn_is_param_(b, True{})})

# `x.permute(0, 2, 3, 1).permute(0, 3, 1, 2)` -- :279. Two permutes and no shape
# arithmetic, so the row is the two index LISTS.
def ln2d_in() -> List<&2, U32>: [0, 2, 3, 1]
def ln2d_out() -> List<&2, U32>: [0, 3, 1, 2]

# ---------------------------------------------------------------------------
# RMSNorm -- :281-304.
# ---------------------------------------------------------------------------

def rms_w(dim: U32) -> List<&2, U32>: [dim]

# `x.square().mean(-1, keepdim=True{})` -- :300. `axis=-1` is the LAST axis and
# `keepdim=True` is what leaves the rank alone, so the axis list is `[ndim-1]`
# and NOT `[-1]`: `x.mean(axis=...)` is given a non-negative axis in this port
# because that is what the reduce needs, and Python's negative spelling is
# resolved against the rank here rather than inside the mixin.
def rms_axis(ndim: U32) -> List<&2, U32>:
  [U32.sub(ndim, 1)]

def rms_st(w: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})})

# ---------------------------------------------------------------------------
# Embedding -- :377-396. `__init__` is one line and its SHAPE is the vocab table.
# ---------------------------------------------------------------------------

def emb_w(vocab: U32, embed: U32) -> List<&2, U32>: [vocab, embed]

# `if not dtypes.is_int(idx.dtype): raise TypeError(...)` -- :392. The dtype test
# is `DT.dtypes.is_int` and it is PORTABLE; the raise is not, so the def answers
# the `Bool` the test is and the caller owns the refusal.
def emb_idx_ok(dt: S.Dt) -> Bool: S.Dt.is_int(dt)

def emb_st(w: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(Nil{}, ST.Ent{"weight", T.tn_is_param_(w, True{})})

# ---------------------------------------------------------------------------
# LSTMCell -- :398-420. Four parameter shapes and one `1.0 / math.sqrt` (:408).
# ---------------------------------------------------------------------------

def lstm_ih(input: U32, +hidden: U32) -> List<&2, U32>:
  [U32.mul(hidden, 4), input]

def lstm_hh(input: U32, +hidden: U32) -> List<&2, U32>:
  [U32.mul(hidden, 4), hidden]

def lstm_b(input: U32, +hidden: U32) -> List<&2, U32>:
  [U32.mul(hidden, 4)]

# FOUR entries, so four `nn_app`s is the whole thing. The `.ih`/`.hh`/`.bi`
# chain this replaces was written to avoid a mutual recursion that does not
# exist -- `nn_app` is not recursive -- so it was four defs where one line is
# enough, which is the opposite of what the brief asks for.
def lstm_st(wi: T.Tensor, wh: T.Tensor, bi: T.Tensor, bh: T.Tensor) -> List<&2, ST.Ent>:
  nn_app(nn_app(nn_app(nn_app(Nil{}, ST.Ent{"weight_ih", T.tn_is_param_(wi, True{})}),
    ST.Ent{"weight_hh", T.tn_is_param_(wh, True{})}), ST.Ent{"bias_ih", T.tn_is_param_(bi, True{})}),
    ST.Ent{"bias_hh", T.tn_is_param_(bh, True{})})

# ===========================================================================
# THE GATE. Every row is a SHAPE, a PADDING, a COUNT or a KEY LIST, and every
# row is a claim CPython can be asked about with no device.
# ===========================================================================

def nn_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# Three CLOSED folds over a String accumulator, so the step inlines as a lambda and each
# of these is one line where it was five (bend2-constraints rule 31). The comma is
# appended, not prepended, so the output order is the input order -- which is what the
# rows below check, since a reversed fold would still print the same COUNT.
def nn_u(xs: List<&2, U32>) -> String:
  List.foldl(~&2, ~U32, ~String, (acc: String) => (h: U32) => String.concat([acc, U32.show(h), ","]), xs, "")

def nn_i(xs: List<&2, H.I64>) -> String:
  List.foldl(~&2, ~H.I64, ~String, (acc: String) => (h: H.I64) => String.concat([acc, H.i64_text(h), ","]), xs, "")

def nn_k(es: List<&2, ST.Ent>) -> String:
  List.foldl(~&2, ~ST.Ent, ~String, (acc: String) => (e: ST.Ent) => String.concat([acc, ST.Ent.k(e), ","]), es, "")

# A tensor fixture. A `state_dict` key is a NAME and nothing here reads a value,
# so a CONST in a fresh arena is the cheapest thing that is a real leaf. The
# `is_param` FLAG is not decorative: it is what `Optimizer` filters on and
# `nn_isparam` is the row that pins it through the `*_st` defs.
def nn_t(n: U32) -> T.Tensor:
  T.tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(n)})

def nn_isparam(es: List<&2, ST.Ent>) -> String:
  List.foldl(~&2, ~ST.Ent, ~String,
    (acc: String) => (e: ST.Ent) => String.concat([acc, Bool.show(T.Tensor.flag(ST.Ent.t(e))), ","]), es, "")

# --- the four convolutions `beautiful_mnist.py` builds ---

def t_conv() -> IO(Unit):
  nn_row("nn_conv", Bool.and(
    Bool.and(String.eq(nn_u(conv_w(32, 1, 1, nn_mt(5, 2))), "32,1,5,5,"),
      String.eq(nn_u(conv_w(32, 32, 1, nn_mt(5, 2))), "32,32,5,5,")),
    Bool.and(String.eq(nn_u(conv_w(64, 32, 1, nn_mt(3, 2))), "64,32,3,3,"),
      String.eq(nn_u(conv_w(64, 64, 1, nn_mt(3, 2))), "64,64,3,3,"))))

# the bias is `Tensor.uniform(out_channels)` -- :107
def t_convb() -> IO(Unit):
  nn_row("nn_convb", String.eq(nn_u(conv_b(32)), "32,"))

# `make_tuple(kernel_size, 2)` -- :98 -- and the DEGENERATE `groups` case at :106
# where `in_channels//groups` is `0`. MEASURED: `nn.Conv2d(1,4,3,groups=2)
# .weight.shape` is `(4, 0, 3, 3)`, so this is not an error and must not be
# guarded; a `max(1, ...)` would answer `4,1,3,3` and the row would go red.
def t_conv0() -> IO(Unit):
  nn_row("nn_conv0", String.eq(nn_u(conv_w(4, 1, 2, nn_mt(3, 2))), "4,0,3,3,"))

# `padding='same'` -- :102-103 -- over the four measured cases. `dilation=2` is the
# one that separates this from a hard-coded `(k-1)//2`: with `d=2, k=3` the answer
# is `(2,2,2,2)` and a `d`-ignoring implementation gives `(1,1,1,1)`.
def t_same() -> IO(Unit):
  nn_row("nn_same", Bool.and(
    Bool.and(String.eq(nn_u(nn_same(1, nn_mt(3, 2))), "1,1,1,1,"),
      String.eq(nn_u(nn_same(2, nn_mt(3, 2))), "2,2,2,2,")),
    Bool.and(String.eq(nn_u(nn_same(3, nn_mt(3, 2))), "3,3,3,3,"),
      String.eq(nn_u(nn_same(1, [3, 4])), "1,2,1,1,"))))

# THE REVERSAL FIXTURE. `zip(make_tuple(dilation, len(ks))[::-1], ks[::-1])`
# pairs the LAST kernel with the FIRST dilation, so for a NON-SQUARE kernel the
# padding is `(1,2,1,1)` and not `(1,1,2,2)`. MEASURED:
# `nn.Conv2d(1,1,(3,4),padding='same').padding` is `(1, 2, 1, 1)`. Without the
# reversal this row answers `1,1,2,2` and no square-kernel row can see it, which
# is why the fixture is non-square.
def t_same_rev() -> IO(Unit):
  nn_row("nn_same_rev", String.eq(nn_u(nn_same(1, [3, 4])), "1,2,1,1,"))

# and the RECTANGULAR kernel_size arriving through the sum type's tuple arm
def t_ks2() -> IO(Unit):
  nn_row("nn_ks2", String.eq(nn_u(conv_ks.of(Ks2{5})), "5,5,"))

# `Conv1d` wraps its kernel in a 1-tuple -- :78 -- which is a DIFFERENT shape from
# `Conv2d`'s, and `Conv2d(1,1,(3,))` then pads to length 2 rather than 4.
def t_c1d() -> IO(Unit):
  nn_row("nn_c1d", String.eq(nn_u(nn_same(1, conv_ks1(3))), "1,1,"))

# --- Linear -- the example's last layer --

def t_lin() -> IO(Unit):
  nn_row("nn_lin", Bool.and(
    String.eq(nn_u(lin_w(576, 10)), "10,576,"),
    String.eq(nn_u(lin_b(10)), "10,")))

# --- BatchNorm ---

# `shape_mask = [1, -1, *([1]*(x.ndim-2))]` -- :42. `H.i64_text` prints `hi:lo`,
# so `-1` is `4294967295:4294967295` and the ones are `0:1`.
def t_bn_mask() -> IO(Unit):
  nn_row("nn_bn_mask", Bool.and(
    String.eq(nn_i(bn_mask(4)), "0:1,4294967295:4294967295,0:1,0:1,"),
    Bool.and(String.eq(nn_i(bn_mask(2)), "0:1,4294967295:4294967295,"),
      String.eq(nn_i(bn_mask(1)), "0:1,4294967295:4294967295,"))))

# `reduce_axes = tuple(x for x in range(x.ndim) if x != 1)` -- :47. It EXCLUDES
# axis 1 and keeps 0, which is the whole content of the comprehension's filter.
def t_bn_axes() -> IO(Unit):
  nn_row("nn_bn_axes", Bool.and(
    String.eq(nn_u(bn_axes(4)), "0,2,3,"),
    String.eq(nn_u(bn_axes(2)), "0,")))

# the `__dict__` ORDER and the `is_param` FLAGS -- :33-39. This is the row the
# example's optimizer depends on: the three scalars contribute no key, the scalar
# tensor does, and only the two affine entries are parameters.
def t_bn_st() -> IO(Unit):
  nn_row("nn_bn_st", Bool.and(
    String.eq(nn_k(bn_st(True{}, True{}, nn_t(1), nn_t(2), nn_t(3), nn_t(4), nn_t(5))),
      "weight,bias,num_batches_tracked,running_mean,running_var,"),
    String.eq(nn_isparam(bn_st(True{}, True{}, nn_t(1), nn_t(2), nn_t(3), nn_t(4), nn_t(5))),
      "True,True,False,False,False,")))

# `affine=False` drops weight and bias but KEEPS `num_batches_tracked` (:38 is
# outside the ternary), and `track_running_stats=False` drops the two running
# stats but keeps the counter. Two rows rather than one because the two flags
# are INDEPENDENT and a single row that set both would not see a swap.
def t_bn_flags() -> IO(Unit):
  nn_row("nn_bn_flags", Bool.and(
    String.eq(nn_k(bn_st(False{}, True{}, nn_t(1), nn_t(2), nn_t(3), nn_t(4), nn_t(5))),
      "num_batches_tracked,running_mean,running_var,"),
    String.eq(nn_k(bn_st(True{}, False{}, nn_t(1), nn_t(2), nn_t(3), nn_t(4), nn_t(5))),
      "weight,bias,num_batches_tracked,")))

# the parameter shapes, including the SCALAR `num_batches_tracked` at :38 whose
# shape is the empty list -- the only `Nil{}` shape in this file.
def t_bn_shapes() -> IO(Unit):
  nn_row("nn_bn_shapes", Bool.and(
    Bool.and(String.eq(nn_u(bn_w(32, True{})), "32,"), String.eq(nn_u(bn_b(32, True{})), "32,")),
    Bool.and(String.eq(nn_u(bn_w(32, False{})), ""), String.eq(nn_u(bn_nbt()), ""))))

# --- ConvTranspose2d -- the REASSIGNED weight --

# `self.weight = Tensor.uniform(in_channels, out_channels//groups, *ks)` at :150
# REPLACES the one :106 built, and the shape is the other order round. MEASURED:
# `nn.ConvTranspose2d(1,2,3).weight.shape` is `(1, 2, 3, 3)` where `Conv2d(1,2,3)`
# is `(2, 1, 3, 3)`. A port that shared the two would answer `(2,1,3,3)`.
def t_ct() -> IO(Unit):
  nn_row("nn_ct", Bool.and(
    String.eq(nn_u(convT_w(1, 2, 1, nn_mt(3, 2))), "1,2,3,3,"),
    String.eq(nn_u(conv_w(2, 1, 1, nn_mt(3, 2))), "2,1,3,3,")))

# --- the norms --

# `self.axis = tuple(-1-i for i in range(len(self.normalized_shape)))` -- :253.
# MEASURED: `nn.LayerNorm(3).axis` is `(-1,)` and `nn.LayerNorm((2,3)).axis` is
# `(-1, -2)`. Two rows because a one-element axis is the case that a
# "prepend -1" implementation would get right by accident.
def t_ln() -> IO(Unit):
  nn_row("nn_ln", Bool.and(
    String.eq(nn_i(ln_axis(1)), "4294967295:4294967295,"),
    String.eq(nn_i(ln_axis(2)), "4294967295:4294967295,4294967295:4294967294,")))

# the two parameters are `Tensor.ones(*normalized_shape)` -- :254-255
def t_ln_sh() -> IO(Unit):
  nn_row("nn_ln_sh", String.eq(nn_u(ln_shape.of(Ks2s{[2, 3]})), "2,3,"))

# `LayerNorm2d`'s two permutes -- :279
def t_ln2d() -> IO(Unit):
  nn_row("nn_ln2d", Bool.and(
    String.eq(nn_u(ln2d_in()), "0,2,3,1,"),
    String.eq(nn_u(ln2d_out()), "0,3,1,2,")))

# `x.reshape(x.shape[0], num_groups, -1)` -- :203 and :231 -- and the affine
# `reshape(1, -1, *[1]*(x.ndim-2))` at :207/:233. The `-1` is Python's INFERRED
# dim and it is what makes the reshape legal at all.
def t_gn() -> IO(Unit):
  nn_row("nn_gn", Bool.and(
    String.eq(nn_i(gn_reshape(2, 2)), "0:2,0:2,4294967295:4294967295,"),
    String.eq(nn_i(gn_affine(4)), "0:1,4294967295:4294967295,0:1,0:1,")))

# `RMSNorm._norm`'s `mean(-1, keepdim=True)` -- :300 -- resolved against the rank
def t_rms() -> IO(Unit):
  nn_row("nn_rms", Bool.and(
    String.eq(nn_u(rms_axis(4)), "3,"),
    String.eq(nn_u(rms_w(4)), "4,")))

# --- Embedding and LSTMCell --

def t_emb() -> IO(Unit):
  nn_row("nn_emb", String.eq(nn_u(emb_w(10, 3)), "10,3,"))

# `glorot_uniform`'s bound is `sqrt(6/(fan_in+fan_out))` and NOT `1/sqrt`: the two
# differ by `sqrt(6)`, so a port that used `nn_bound` here would answer
# `0.2773501` against Python's `0.6793662204867574`. The row prints the f32
# image of the CPython double, which is what both sides can be held to.
def t_glorot() -> IO(Unit):
  nn_row("nn_glorot", String.eq(F32.show(nn_glorot(10.0, 3.0)), "0.67936623"))

# the four LSTMCell shapes -- :409-412, with `hidden_size*4` in three of them
def t_lstm() -> IO(Unit):
  nn_row("nn_lstm", Bool.and(
    Bool.and(String.eq(nn_u(lstm_ih(3, 4)), "16,3,"), String.eq(nn_u(lstm_hh(3, 4)), "16,4,")),
    String.eq(nn_u(lstm_b(3, 4)), "16,")))

def t_lstm_st() -> IO(Unit):
  nn_row("nn_lstm_st", String.eq(nn_k(lstm_st(nn_t(1), nn_t(2), nn_t(3), nn_t(4))),
    "weight_ih,weight_hh,bias_ih,bias_hh,"))

# the two float formulas, over the literal factors Python's own fixtures give.
# `nn_scale(1, 25)` is `Conv2d(1,32,5)`'s `1/sqrt(1*5*5)` = 0.2 and
# `nn_bound(576)` is `nn.Linear(576,10)`'s `1/sqrt(576)`. The U32-to-F32
# conversion at the real call site is a `TODO(p3)`; the FORMULA is what is here.
def t_formula() -> IO(Unit):
  nn_row("nn_formula", Bool.and(
    String.eq(F32.show(nn_scale(1.0, 25.0)), "0.2"),
    String.eq(F32.show(nn_bound(576.0)), "0.041666668")))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_conv()
    b : Unit <- t_convb()
    c : Unit <- t_conv0()
    d : Unit <- t_same()
    e : Unit <- t_same_rev()
    f : Unit <- t_ks2()
    g : Unit <- t_c1d()
    h : Unit <- t_lin()
    i : Unit <- t_bn_mask()
    j : Unit <- t_bn_axes()
    k : Unit <- t_bn_st()
    l : Unit <- t_bn_flags()
    m : Unit <- t_bn_shapes()
    n : Unit <- t_ct()
    o : Unit <- t_ln()
    p : Unit <- t_ln_sh()
    q : Unit <- t_ln2d()
    r : Unit <- t_gn()
    s : Unit <- t_rms()
    u : Unit <- t_emb()
    v : Unit <- t_glorot()
    w : Unit <- t_lstm()
    x : Unit <- t_lstm_st()
    t_formula()

# ===========================================================================
# THE GATE, AS A COMMAND. BOTH LANES AND THE ORACLE AGREE ON ALL 24 ROWS:
#
#     .venv/bin/python .agents/slop/nn-init-gate.py  > /tmp/py.txt
#     ./bin/bend tinybendygrad/nn/__init__.bend        > /tmp/bd.txt
#     ./bin/bend tinybendygrad/nn/__init__.bend -o /tmp/nat && /tmp/nat > /tmp/nat.txt
#     diff /tmp/bd.txt /tmp/nat.txt    # MEASURED: byte identical, all 24 rows
#     diff /tmp/py.txt /tmp/bd.txt     # MEASURED: byte identical, all 24 rows
#
# `--check-only` reports "14 defs rely on unsafe or foreign code" and all fourteen
# are in `dtype.bend`; `optim.bend` reports the identical fourteen. Not a property
# of this file.
#
# THE MUTATION TABLE, MEASURED, by `.agents/slop/nn-init-mutate.py`.
#
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | the half-pad's dilation factor is `1` | `nn_same` | `d*(k-1)//2` at :102. Only `nn_same` moves because the other two pad rows use `dilation=1` -- and that is the point of `nn_same` being a conjunction over three dilations rather than three rows. |
# | M2 | the two lists are walked forwards, not `[::-1]` | `nn_same` `nn_same_rev` | the REVERSAL at :102. `nn_same_rev` exists ONLY for this: the square cases are symmetric so they cannot see a missing reverse, and the non-square fixture is the one that can. |
# | M3 | the half-pad is `m` and not `m//2` | `nn_same` `nn_same_rev` `nn_c1d` | `//2` specifically. `nn_c1d` moves because a 1-D kernel of 3 gives `m=2` and `m//2=1` against `m=2`, so the pair is `(2,0)` -- a zero pad, which is visible. |
# | M4 | `num_batches_tracked` is appended last | `nn_bn_st` `nn_bn_flags` | the `__dict__` ORDER at :33-39. **This mutation is the bug the gate caught in this file**: the first `bn_st` appended the counter inside the `track` ternary, so with `track=True` the order was right by luck and with `track=False` the key VANISHED. Both rows are why the order is now asserted from two flag settings and not one. |
# | M5 | `num_batches_tracked` is not `is_param_(False)` | `nn_bn_st` | :38. This is the flag `Optimizer` (:13) filters on, and it is a claim about `t.is_param` and not about a key. |
# | M6 | the running stats are added unconditionally | `nn_bn_flags` | the `track_running_stats` ternary at :39. Only one row moves because `nn_bn_st` uses `track=True` and cannot see a missing `Bool.pick`. |
# | M7 | the mask drops its `-1` | `nn_bn_mask` | `shape_mask` at :42. |
# | M8 | the `[1]*(ndim-2)` tail count stops saturating | `nn_bn_mask` | `[1] * -1` is `[]` in Python, so a non-saturating count gives a THREE-element mask for `ndim == 1`. **The `ndim == 1` third of the row is the only thing that can see it** and it was added because the first version of `bn_mask` was an index-and-compare walk that emitted `ndim` elements and answered `[1]`. |
# | M8b | the same, dropping the `0n` arm as well | `nn_bn_mask` | a second, coarser cut of M8. Two mutations of one def because the saturating subtraction has two arms and a reviewer should be able to see that removing either one is visible. |
# | M9 | `reduce_axes` excludes axis 0 rather than axis 1 | `nn_bn_axes` | the `!= 1` filter at :47. |
# | M10 | `ConvTranspose2d` reuses `Conv2d`'s weight shape | `nn_ct` | :150 against :106. The two differ by a TRANSPOSE of the in/out pair and a `ConvTranspose2d` whose weight shape equalled its parent's would still load a checkpoint, so this is a real corruption. |
# | M11 | the group division is clamped to at least 1 | `nn_conv0` | `in_channels//groups` at :106. tinygrad does NOT guard it and MEASURED `nn.Conv2d(1,4,3,groups=2).weight.shape` is `(4, 0, 3, 3)`; a port that "fixed" this answers `(4, 1, 3, 3)`. `nn_conv0` is the only row that can see it, and it exists for that reason alone. |
# | M12 | the axis counts up instead of down | `nn_ln` | `-1-i` at :253. |
# | M13 | the RMSNorm axis is `0` rather than `ndim-1` | `nn_rms` | `mean(-1, keepdim=True)` at :300, resolved against the rank. |
# | M14 | a no-op edit | **NOTHING** | the control. A table with no row that CANNOT move is a table of coincidences. |
#
# ONE MUTATION THAT WAS ATTEMPTED, MOVED NOTHING, AND IS NOT IN THE TABLE:
# dropping `nn_sat2`'s `Succ{0n}` arm and keeping `case _: 0n`. That is
# SEMANTICALLY IDENTICAL -- `0n` and `1n` reach the same answer either way -- so
# "a mutation that cannot move" and "a mutation that does not change the function"
# look the same in a table and are not the same thing. M8 and M8b are the real
# cuts. Recorded because the difference is the whole reason a mutation table is
# worth having.
#
# WHAT THE TABLE DOES NOT COVER, stated rather than left to be discovered:
#   * Every `__call__`. Eleven of the thirteen classes have no gate row at all
#     because their body is one mixin method, and the mixin is not built. The rows
#     here are the `__init__` arithmetic and the `__dict__` and nothing else.
#   * The float CONSTANTS. `nn_formula` and `nn_glorot` pin the FORMULAS with
#     literal F32 factors; the `U32.to_f32` conversion at the real call sites is
#     an unfilled law and is a `TODO(p3)`, so no row can reach it.
#   * `_embedding_fwd`'s output shape. Its four mixin methods include the
#     `arange` that mixin/op.bend's W4 calls uncheckable, so a shape row for it
#     would be a row about a graph nobody can build.
