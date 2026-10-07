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
# gated at `gates/tn_sqrt-gate.py` 5/5 rows. `Tensor.detach` is ported at
# `tensor.bend:296` as `tn_detach` and gated at `gates/tn_detach-gate.py` 5/5 rows.
# The wall text said `detach` was `self.replace(arg=KernelInfo())` -- and that
# description is the FULL version CPython uses, but the one-liner
# `return self.alu(Ops.DETACH)` is what `Tensor.detach` does in `elementwise.py:43`,
# and THAT is what the port covers. `Tensor.bitwise_not` BOOL arm is ported at
# `tensor.bend:338` as `tn_bitwise_not`, gated at `gates/tn_bitwise_not-gate.py` 8/8
# rows; `Tensor.logical_not` is ported at `tensor.bend:352` as `tn_logical_not`,
# gated at `gates/tn_logical_not-gate.py` 4/4 rows. The arith arms of `bitwise_not`
# stay walled on the dtype fold + arith ops, named at `tensor.bend:308`.
# `Tensor.contiguous_backward`, `Tensor.trunc`, `Tensor.reciprocal`, and
# `Tensor.threefry` are also ported (all one-liners in elementwise.py at :68,
# :474, :460, :457), at `tensor.bend:302, 307, 311, 315`, gated at
# `gates/tn_contiguous_backward-gate.py` and `gates/tn_trunc_reciprocal_threefry-gate.py`.
# `Tensor.where` (elementwise.py:426) is ported at `tensor.bend:369` as `tn_where`
# for the no-broadcasting case (`self.ufix(x)._broadcasted(y)` collapses to identity
# when x and y are already Tensors of the same shape, and the body is then
# `tn_alu(cond, O.OpsWHERE{}, [x, y])`), gated at `gates/tn_where-gate.py` 5/5 rows.
# The broadcasting case stays walled on `_broadcasted`. `Tensor.__mul__`
# (elementwise.py:125) and its `__rmul__` arm (elementwise.py:300) are ported at
# `tensor.bend:466, 471, 474` as `tn_mul.go` / `tn_mul` / `tn_rmul` for the
# no-broadcasting case (`_binop`'s `_broadcasted` is the identity for two same-shape
# Tensors, so the body is `tn_alu(self, MUL, [Tensor.u(rhs)])` for `__mul__` and
# `tn_alu(rhs, MUL, [Tensor.u(self)])` for `__rmul__`), gated at
# `gates/tn_mul-gate.py` 13/13 rows. With `__mul__` ported, `Tensor.square`
# (elementwise.py:575, `return self * self`) is a one-liner: `tn_square` at
# `tensor.bend:481` is `tn_mul(t, t)`, gated by the same 13/13 gate. The
# broadcasting case for `__mul__`/`__rmul__` stays walled on `_broadcasted` (same
# wall as `where`). `Tensor.__add__` (elementwise.py:267) and its `__radd__` arm
# (elementwise.py:295) are ported at `tensor.bend:518, 523, 526` as
# `tn_add.go` / `tn_add` / `tn_radd` for the no-broadcasting case (CPython's
# `add` writes `a.alu(Ops.ADD, -b)` at elementwise.py:84, :123 -- the `-b` is a
# CONST trap and a unary minus on a Tensor is also walled, so for two same-shape
# Tensors the body collapses to `_binop`'s shape with `MUL` replaced by `ADD`:
# `tn_alu(self, ADD, [Tensor.u(x)])` for `__add__` and `tn_alu(x, ADD, [Tensor.u(self)])`
# for `__radd__`), gated at `gates/tn_add_sub-gate.py` 17/17 rows. `Tensor.__sub__`
# (elementwise.py:270) and its `__rsub__` arm (elementwise.py:297) are ported at
# `tensor.bend:536, 541, 544` as `tn_sub.go` / `tn_sub` / `tn_rsub` for the
# no-broadcasting case (CPython's `sub` is the same `-b` shape at
# elementwise.py:103, :123, so the port is `_binop`'s shape with `SUB`: same
# gate). The broadcasting case for `__add__`/`__radd__`/`__sub__`/`__rsub__`
# stays walled on `_broadcasted` (same wall as `where` and `__mul__`).
# `Tensor.__lt__`/`__gt__` (elementwise.py:321, :324, via `_binop(Ops.CMPLT, ...)`),
# `Tensor.__ne__`/`ne` (:339, :333, via `_binop(Ops.CMPNE, ...)`),
# `Tensor.__and__`/`__rand__` (:285, :309, via `bitwise_and`'s `_binop(Ops.AND, ...)`),
# `Tensor.__or__`/`__ror__` (:288, :312), `Tensor.__xor__`/`__rxor__` (:291, :315),
# `Tensor.maximum` (:378, `self._binop(Ops.MAX, x, False)`),
# `Tensor.__lshift__`/`__rlshift__` (:366, :372, via `lshift`'s `_binop(Ops.SHL, ...)`),
# `Tensor.__rshift__`/`__rrshift__` (:369, :375),
# `Tensor.__pow__`/`__rpow__` (:569, :572, via `pow`'s `_broadcasted + alu(Ops.POW, ...)`)
# are all ported at `tensor.bend:554-704` as
# `tn_cmplt.go`/`tn_cmplt`/`tn_rcmplt`,
# `tn_cmpne.go`/`tn_cmpne`/`tn_rne`,
# `tn_and.go`/`tn_and`/`tn_rand`,
# `tn_or.go`/`tn_or`/`tn_ror`,
# `tn_xor.go`/`tn_xor`/`tn_rxor`,
# `tn_max`,
# `tn_shl.go`/`tn_shl`/`tn_rshl`,
# `tn_shr.go`/`tn_shr`/`tn_rshr`,
# `tn_pow.go`/`tn_pow`/`tn_rpow`
# for the no-broadcasting case (each is `_binop`'s body with `MUL` replaced by
# `Ops.<OP>`, mirroring `tn_add.go`/`tn_mul.go`). The shape with `Pow` is the
# same, and the `isinstance(x, ConstType)` guard upstream is unreachable for two
# Tensors. `Tensor.__pow__`/`__rpow__` is gated at `gates/tn_pow-gate.py`
# (9/9 rows: op/arg/srcs/purity for the forward arm, op/arg/srcs/purity for the
# `reverse=True` arm, and the reachability row that names the wall). The
# broadcasting case for `__pow__`/`__rpow__` stays walled on `_broadcasted`.
# `Tensor.__and__`/`__rand__`/`__or__`/`__ror__`/`__xor__`/`__rxor__` are
# gated at `gates/tn_and_or_xor-gate.py` (25/25 rows: op/arg/srcs/purity for
# the forward arm of each pair, op/arg/srcs/purity for the `reverse=True`
# arm, and the reachability row that names the wall). The broadcasting case
# for all six stays walled on `_broadcasted` (same wall as `__add__`/
# `__sub__`/`__mul__`/`__pow__`).
# `Tensor.__floordiv__` (elementwise.py:279, `self.div(x, rounding_mode="floor")`)
# and its `__rfloordiv__` arm are ported at `tensor.bend:700, 705, 708` as
# `tn_fdiv.go` / `tn_fdiv` / `tn_rfdiv` for the no-broadcasting INT case
# (elementwise.py:252, `if rounding_mode == "floor": return a.alu(Ops.FLOORDIV, b)`,
# which is the int-typed path of `div`). For two same-shape Tensors `_broadcasted`
# is identity and the body is `_binop`'s shape with `Ops.FLOORDIV`: `__floordiv__`
# is `self.alu(FLOORDIV, x)` -- srcs `(self, x)` -- and `__rfloordiv__` (the
# `reverse=True` arm of `_binop`) is `x.alu(FLOORDIV, self)` -- srcs `(x, self)`.
# `Tensor.__mod__` (elementwise.py:282, `self.mod(x)`) and its `__rmod__` arm
# (the `reverse=True` arm of `mod`) are ported at `tensor.bend:722, 727, 730` as
# `tn_mod.go` / `tn_mod` / `tn_rmod` for the no-broadcasting INT case
# (elementwise.py:213, `if dtypes.is_int(a.dtype) and dtypes.is_int(b.dtype):
# return a.alu(Ops.FLOORMOD, b)`). The shape is `_binop`'s with `Ops.FLOORMOD`:
# `__mod__` is `self.alu(FLOORMOD, x)` and `__rmod__` is `x.alu(FLOORMOD, self)`.
# The float arm of `mod` (`return a - a.div(b, rounding_mode="floor") * b`,
# elementwise.py:214) and the float arm of `div` (the `cast(default_float)` +
# FDIV path past the int-typed guard, elementwise.py:253-254) stay walled on
# the dtype fold and on the FDIV op, the same fold the other dtype-gated
# arithmetic arms name (tensor.bend:385). The `__truediv__` arm
# (`self.div(x)` with `rounding_mode=None`, elementwise.py:276) is SKIPPED for the
# same reason -- its float body needs the dtype fold -- and because porting it
# would need an extra `rounding_mode` parameter the port does not track. Gated
# at `gates/tn_fdiv_mod-gate.py` (17/17 rows: op/arg/srcs/purity for each of
# the four defs, plus the reachability row that names the wall). The
# broadcasting case for `__floordiv__`/
# `__rfloordiv__`/`__mod__`/`__rmod__` stays walled on `_broadcasted` (same wall
# as the other `_binop`-shaped defs).
# `Tensor.__ge__` (:327, `(self < x).logical_not()`)
# and `Tensor.__le__` (:330, `(self > x).logical_not()`) are ported at
# `tensor.bend:691`/`698` as `tn_dunder_ge`/`tn_dunder_le` -- the chain
# `tn_logical_not(tn_cmplt(...))` / `tn_logical_not(tn_rcmplt(...))` -- and
# `Tensor.eq` (:336, `self.ne(x).logical_not()`) is `tn_eq` at `tensor.bend:704`,
# the chain `tn_logical_not(tn_cmpne(...))`. All three gates are at
# `gates/tn_binop2_cmp-gate.py`. `Tensor.__invert__` (:264, `self.bitwise_not()`)
# is ported as `tn_dunder_invert` at `tensor.bend:479`, one of the ONE-ARM
# ports: `bitwise_not`'s BOOL arm IS `tn_logical_not` (gated 4/4); the arith
# arms (`self ^ dtype.max` for unsigned, `self ^ -1` for signed, :157) stay
# walled on the dtype fold + arith ops (tensor.bend:385 -- `self.dtype` is a
# FOLD property and `tn_bitwise_not`'s arith arms are `None`). Returns
# `Maybe<&2, Tensor>` and lets the caller decide; the port convention
# (`tn_replace`, `tn_as_param`) is the same shape. Gated at
# `gates/tn_dunder_invert-gate.py`. The broadcasting case for all
# `__lt__`/`__gt__`/`__ne__`/`__and__`/`__rand__`/`__or__`/`__ror__`/`__xor__`/
# `__rxor__`/`maximum`/`__lshift__`/`__rlshift__`/`__rshift__`/`__rrshift__`/
# `__pow__`/`__rpow__`/`__floordiv__`/`__rfloordiv__`/`__mod__`/`__rmod__`/
# `__ge__`/`__le__`/`eq` stays walled on `_broadcasted`
# (same wall as `__add__`/`__sub__`/`__mul__`/`__rmul__`/`where`).
# `Tensor.ceil` (elementwise.py:656, `(self > (b := self.trunc())).where(b+1, b)`)
# and `Tensor.floor` (elementwise.py:662, `(self < (b := self.trunc())).where(b-1, b)`)
# are ported at `tensor.bend:632, 650, 664, 682` as `tn_ceil` / `tn_floor` (and their
# helpers `tn_ceil.b` / `tn_ceil.gt` / `tn_ceil.bp1` / `tn_ceil.go` / `tn_ceil.c1` /
# `tn_ceil.c1t` and `tn_floor.b` / `tn_floor.lt` / `tn_floor.bm1` / `tn_floor.go` /
# `tn_floor.c1` / `tn_floor.c1t`) for the no-broadcasting case. The body is a 4-step
# chain: `b := tn_trunc(self)`, cond := `tn_rcmplt(self, b)` for ceil or
# `tn_cmplt(self, b)` for floor, `b±1 := tn_add(b, c1t)` for ceil or
# `tn_sub(b, c1t)` for floor (the `c1t` is a Tensor wrapping a CONST 1, the same
# `tn_new(Tensor.ar(t), O.Found.i(c1))` shape `tn_relu.c0t` uses), and the final
# `tn_where(cond, b±1, b)`. The deps cited by the wall text (`b+1` / `tn_trunc`)
# are all ported: `tn_trunc` (tensor.bend:320, gated 9/9 with `tn_reciprocal` and
# `tn_threefry`), `tn_add` (tensor.bend:523, gated 17/17 with `tn_sub`), `tn_sub`
# (tensor.bend:541, same gate), `tn_cmplt` (tensor.bend:559, gated in
# `tn_binop2_cmp-gate.py`), `tn_rcmplt` (tensor.bend:568, gated in the same
# file), `tn_where` (tensor.bend:369, gated 5/5 in `tn_where-gate.py`), and
# `O.UOp.const` (ops.bend:2922, gate rc=0). Gated at
# `gates/tn_ceil_floor-gate.py` 11/11 rows (op/arg/srcs/purity for each of
# `tn_ceil` and `tn_floor`, the cond's CMPLT shape for each, and the reachability
# row). The broadcasting case stays walled on `_broadcasted` (same wall as
# `where`, `__add__` / `__sub__` / `__mul__` / `__pow__` / the rest of the
# `_binop`-shaped defs).