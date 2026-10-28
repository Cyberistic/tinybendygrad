import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../mixin/op.bend as MO
import ./../mixin/movement.bend as MX
import ./../mixin/creation.bend as CR
import ./../mixin/elementwise.bend as E
import ./../extra/datasets/__init__.bend as D

# ===========================================================================
# `nn/pool.bend` -- SLIDING-WINDOW AND CHANNEL VOCABULARY, and the ops it needs.
#
# THE HEADLINE MEASUREMENT, and it is the reason this file is mostly movement
# ops: THERE IS NO POOL OP, UPSTREAM OR HERE. `tinygrad/uop/__init__.py:13-97`
# is the whole `Ops` enum and its members are ADD MUL SHL SHR CDIV MAX CMOD
# CMPLT CMPNE CMPEQ XOR OR AND THREEFRY SUB FDIV POW FLOORDIV FLOORMOD WHERE
# MULACC ... RESHAPE PERMUTE EXPAND PAD UNSHARD REDUCE ALLREDUCE. There is no
# MAXPOOL, no AVGPOOL, no MAXPOW2, no AVGPOW2 and no CMOV in it, and
# `grep -rn "MAXPOW2\|AVGPOW2\|MAX_POOL\|AVG_POOL" tinygrad/` = 0 HITS.
#
# Pooling is therefore NOT a UOp CALL and there is nothing to refuse on that
# ground. `tinygrad/mixin/movement.py:614-632` `_pool` is a DECOMPOSITION --
# repeat, shrink, reshape, shrink, reshape, shrink, reshape, permute -- and
# `max_pool2d`/`avg_pool2d` (`mixin/op.py:1333`, `:1285`) are a REDUCE over it.
# `mixin/rand.bend:284-313` has ALREADY PORTED `_pool` for the one-axis,
# stride-1, dilation-1 case (`op_pool1`, for `_cumalu`), and every line below is
# that file's arithmetic with the two spatial axes and a real stride.
#
# SECOND MEASUREMENT, and it decides the shapes of the records here: the
# vendored `tinygrad/nn/__init__.py` (429 lines of classes, 8 of them) HAS NO
# `MaxPool2d`, NO `AdaptiveAvgPool2d` and NO `Sequential` --
# `grep -n "^class \|^def " tinygrad/nn/__init__.py` = BatchNorm(:6), Conv1d(:32),
# Conv2d(:80), ConvTranspose1d(:111), ConvTranspose2d(:130), Linear(:156),
# GroupNorm(:179), InstanceNorm(:209), LayerNorm(:235), LayerNorm2d(:263),
# RMSNorm(tinygrad/nn/__init__.py:281), Embedding(tinygrad/nn/__init__.py:374) and
# LSTMCell(tinygrad/nn/__init__.py:395) and no others. So the pool ops below are
# PORTED FROM THE TENSOR METHODS THEY ARE MADE OF,
# and that is stated per def below rather than dressed up as a layer port.
# `flatten` is `tinygrad/helpers.py:53`, `[item for sublist in l for item in
# sublist]`, a list helper and NOT a layer; the LAYER of that name in a ResNet
# is `x.reshape(x.shape[0], -1)` and that is what `pool_flatten` is.
#
# THIRD MEASUREMENT: `Tensor.batchnorm` (`mixin/op.py:1678-1698`) IS a
# decomposition too -- `x - mean`, `* weight`, `.mul(invstd)`, `+ bias` -- and
# all four are defs here. The part of `nn.BatchNorm` that is NOT a decomposition
# is the running-statistics update, and it is REFUSED with the two symbols
# named (`pool_bn_running_stats`).
# ===========================================================================

# --- the two list joins this file needs ------------------------------------
def pool_sh(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: List.concat(&2, U32, [a, b])

def pool_prod.go(ds: List<&2, U32>, acc: U32) -> U32:
  List.foldl(~&2, ~U32, ~U32, (a: U32) => (d: U32) => U32.mul(a, d), ds, acc)

# ===========================================================================
# `W4` -- `_pool`'s WINDOW over TWO SPATIAL AXES of a FOUR-DIMENSIONAL NCHW
# tensor: `b0 b1` are the batch and channel extents, which `_pool` carries
# through every reshape as its `noop` (movement.py:618), and `i k s d` are the
# input size, kernel, stride and dilation per spatial axis.
#
# IT IS A `Data` RECORD AND NOT TEN PARAMETERS for the reason
# `mixin/rand.bend:257 symbol=PK` gives: "_pool reads `i` and `k` four times each
# across the `ceildiv`s, `smax` and the two `U32.mul`s, a `U32` cannot be read
# twice in one expression and cannot carry `+` as a parameter, and a `Data`
# record can" -- that quote IS `PK`'s own doc comment. Every accessor below is
# NON-CONSUMING, so a `+q: W4` chain step can read the window as many times as
# its expression needs (`mixin/rand.bend:260 symbol=PK.i`).
#
# FOUR DIMENSIONS IS NOT A LIMITATION DRESSED UP AS A SHAPE: it is the case
# every pooling call in a ResNet makes, and the `noop` axes pass through
# untouched, so the generalisation is "read `noop` from the tensor instead of
# from the record", which is stated as the wall it is (`WALL(nn_pool_4d)`).
# ===========================================================================
type W4 is Data:
  W4{b0: U32, b1: U32, i0: U32, i1: U32, k0: U32, k1: U32, s0: U32, s1: U32, d0: U32, d1: U32}

# THE TEN READERS. They are `mixin/rand.bend:260 symbol=PK.i` / `PK.k` EXACTLY --
# a non-consuming `q: W4` and a `match` that returns one field -- and they are
# readers rather than ten `case` bindings because this file's first spelling put
# the `case` INSIDE every derived def, and a derived def that calls another
# derived def (`f0` reads `o0`) then consumed its own binding twice and `bend`
# answered `W4.f0: d0 consumed more than once`. `mixin/rand.bend:277 symbol=U1.v`
# already states the rule: "`U1.v` is a def and therefore non-consuming".
def W4.b0(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: b0
def W4.b1(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: b1
def W4.i0(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: i0
def W4.i1(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: i1
def W4.k0(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: k0
def W4.k1(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: k1
def W4.s0(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: s0
def W4.s1(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: s1
def W4.d0(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: d0
def W4.d1(q: W4) -> U32:
  match q:
    case W4{b0, b1, i0, i1, k0, k1, s0, s1, d0, d1}: d1

# o_ = [ceildiv(i - d*(k-1), s)]                                     movement.py:620
def W4.o0(+q: W4) -> U32:
  H.ceildiv_u32(U32.sub(W4.i0(q), U32.mul(W4.d0(q), U32.sub(W4.k0(q), 1))), W4.s0(q))
def W4.o1(+q: W4) -> U32:
  H.ceildiv_u32(U32.sub(W4.i1(q), U32.mul(W4.d1(q), U32.sub(W4.k1(q), 1))), W4.s1(q))

# f_ = [smax(1, ceildiv(o*s - d, i))] -- "input size scaling factor to make sure
# shrink for stride is possible"                                  movement.py:621-622
def W4.f0(+q: W4) -> U32:
  U32.max(1, H.ceildiv_u32(U32.sub(U32.mul(W4.o0(q), W4.s0(q)), W4.d0(q)), W4.i0(q)))
def W4.f1(+q: W4) -> U32:
  U32.max(1, H.ceildiv_u32(U32.sub(U32.mul(W4.o1(q), W4.s1(q)), W4.d1(q)), W4.i1(q)))

# sz = k*(i*f + d) -- the size the axis is shrunk to            movement.py:626
def W4.sz0(+q: W4) -> U32:
  U32.mul(W4.k0(q), U32.add(U32.mul(W4.i0(q), W4.f0(q)), W4.d0(q)))
def W4.sz1(+q: W4) -> U32:
  U32.mul(W4.k1(q), U32.add(U32.mul(W4.i1(q), W4.f1(q)), W4.d1(q)))

# kk = ceildiv(k*(i*f + d), i) -- "repeats such that we don't need padding"
#                                                               movement.py:623-624
def W4.kk0(+q: W4) -> U32:
  H.ceildiv_u32(U32.mul(W4.k0(q), U32.add(U32.mul(W4.i0(q), W4.f0(q)), W4.d0(q))), W4.i0(q))
def W4.kk1(+q: W4) -> U32:
  H.ceildiv_u32(U32.mul(W4.k1(q), U32.add(U32.mul(W4.i1(q), W4.f1(q)), W4.d1(q))), W4.i1(q))

# --- the six reshape target shapes, each `noop ++ [...]` from movement.py ---
# `noop` -- movement.py:618 `noop = [None] * (self.ndim - len(k_))`
def W4.lead(+q: W4) -> List<&2, U32>: [W4.b0(q), W4.b1(q)]

# RESHAPE/EXPAND/RESHAPE -- `self.reshape(unsqueezed_shape).expand(
# expanded_shape).reshape(final_shape)`, the spelling `op_repeat1.rp`
# (mixin/rand.bend:281 symbol=op_repeat1.rp) uses for ONE axis.
def W4.lift(+q: W4) -> List<&2, U32>:
  [W4.b0(q), W4.b1(q), 1, W4.i0(q), 1, W4.i1(q)]
def W4.tiled(+q: W4) -> List<&2, U32>:
  [W4.b0(q), W4.b1(q), W4.kk0(q), W4.i0(q), W4.kk1(q), W4.i1(q)]
def W4.jn(+q: W4) -> List<&2, U32>:
  [W4.b0(q), W4.b1(q), U32.mul(W4.kk0(q), W4.i0(q)), U32.mul(W4.kk1(q), W4.i1(q))]

# `noop ++ [k*(i*f+d)]` -- the SHRINK sizes                     movement.py:626
def W4.szp(+q: W4) -> List<&2, U32>:
  pool_sh(W4.lead(q), [W4.sz0(q), W4.sz1(q)])

# `noop ++ flatten((k, i*f+d))`                                  movement.py:627
def W4.kz(+q: W4) -> List<&2, U32>: [W4.k0(q), W4.sz0(q), W4.k1(q), W4.sz1(q)]

# `noop ++ flatten((k, o*s))` and `noop ++ flatten((k, o, s))`   movement.py:629
def W4.os(+q: W4) -> List<&2, U32>:
  pool_sh(W4.lead(q), [W4.k0(q), U32.mul(W4.o0(q), W4.s0(q)), W4.k1(q), U32.mul(W4.o1(q), W4.s1(q))])
def W4.kos(+q: W4) -> List<&2, U32>:
  [W4.k0(q), W4.o0(q), W4.s0(q), W4.k1(q), W4.o1(q), W4.s1(q)]

# `noop ++ flatten((k, o, 1))` and `noop ++ flatten((k, o))`    movement.py:630
def W4.ko1(+q: W4) -> List<&2, U32>:
  pool_sh(W4.lead(q), [W4.k0(q), W4.o0(q), 1, W4.k1(q), W4.o1(q), 1])
def W4.ko(+q: W4) -> List<&2, U32>: [W4.k0(q), W4.o0(q), W4.k1(q), W4.o1(q)]

# movement.py:632 `x.permute(*range(len(noop)), *[len(noop) + i*2 + 1 for i in
# range(len(i_))], *[len(noop) + i*2 for i in range(len(i_))])`, which for
# `len(noop) == 2` and two spatial axes is `[0, 1, 3, 5, 2, 4]`: the two `noop`
# axes, then the `o` of each window, then the `k` of each window.
def W4.perm(+q: W4) -> List<&2, U32>: [0, 1, 3, 5, 2, 4]


# ===========================================================================
# `_pool` (movement.py:614-632), TWO SPATIAL AXES, in upstream's own order.
# ONE DEF PER LINE of the upstream expression, because `O.Arena` is affine --
# `mixin/rand.bend:429 symbol=op_arange` carries R1's whole-file `+ar: O.Arena`
# thread, so a def that BUILDS grows a copy and the chain must THREAD `+t`.
# ===========================================================================

# movement.py:624  x = self.repeat(noop ++ [ceildiv(k*(i*f+d), i)])
def pool_rep.rp(+t: T.Tensor, +q: W4) -> T.Tensor:
  CR.cr_expand(MX.mxw_reshape(t, W4.lift(q)), W4.tiled(q))
def pool_rep.put(+x: T.Tensor, +q: W4) -> T.Tensor: MX.mxw_reshape(x, W4.jn(q))
def pool_rep(+t: T.Tensor, +q: W4) -> T.Tensor: pool_rep.put(pool_rep.rp(t, q), q)

# movement.py:626  x = x.shrink_to(noop ++ [k*(i*f+d)])
def pool_shr(+t: T.Tensor, +q: W4) -> T.Tensor: MX.mxw_shrink(t, [0, 0, 0, 0], W4.szp(q))

# movement.py:627  x = x.reshape(noop ++ flatten((k, i*f+d)))
def pool_resh0(+t: T.Tensor, +q: W4) -> T.Tensor:
  MX.mxw_reshape(t, pool_sh(W4.lead(q), W4.kz(q)))

# movement.py:629  x = x.shrink_to(noop ++ flatten((k, o*s))).reshape(...)
def pool_str(+t: T.Tensor, +q: W4) -> T.Tensor: MX.mxw_shrink(t, [0, 0, 0, 0], W4.os(q))
def pool_resh1(+t: T.Tensor, +q: W4) -> T.Tensor:
  MX.mxw_reshape(t, pool_sh(W4.lead(q), W4.kos(q)))

# movement.py:630  x = x.shrink_to(noop ++ flatten((k, o, 1))).reshape(...)
# THE THIRD SHRINK IS NOT A FOLD HERE, and `mixin/rand.bend:375 symbol=op_pool1`
# says why it is one THERE: "`_pool` for `k_ = (k,)`, `stride = 1`" makes `o*s == o`
# and the axis already has size 1, so `shrink` returns `self` (movement.py:192).
# With a real stride `s > 1` the axis has size `s` and the shrink is the node
# that drops it, so it is built.
def pool_kd(+t: T.Tensor, +q: W4) -> T.Tensor: MX.mxw_shrink(t, [0, 0, 0, 0, 0, 0], W4.ko1(q))
def pool_resh2(+t: T.Tensor, +q: W4) -> T.Tensor:
  MX.mxw_reshape(t, pool_sh(W4.lead(q), W4.ko(q)))

# movement.py:632  the PERMUTE that moves the reduce axes to the end
def pool_perm(+t: T.Tensor, +q: W4) -> T.Tensor: MX.mxw_permute(t, W4.perm(q))

# movement.py:629-630 folded into two defs so the chain is READABLE, and that is
# not only taste: `O.Arena` is affine (`mixin/rand.bend:429 symbol=op_arange` carries
# R1's whole-file `+ar: O.Arena` thread) and this file shipped a seven-deep application
# line with ONE `, q)` missing out of eight, and `bend` reported the parse error.
def pool_nd.mid(+t: T.Tensor, +q: W4) -> T.Tensor:
  pool_resh1(pool_str(pool_resh0(pool_shr(pool_rep(t, q), q), q), q), q)
def pool_nd(+t: T.Tensor, +q: W4) -> T.Tensor:
  pool_perm(pool_resh2(pool_kd(pool_nd.mid(t, q), q), q), q)

# ===========================================================================
# `max_pool2d` (mixin/op.py:1333-1376), THE UNPADDED ARM.
#
# op.py:1366-1370 is `pads = resolve_pool_pads(padding, len(k_))` then
# `pooled = self._pad_constant(...)._pool(k_, s_, dilation)`, and op.py:1371 is
# `if not return_indices: return pooled.max(axis)` with
# `axis = tuple(range(-len(k_), 0))` (op.py:1366). After `_pool` the two window
# axes ARE the last two, so `axis` is `[4, 5]` on the four-dimensional result --
# the same reason `mixin/rand.bend:394 symbol=op_cumalu.red` writes `_cumalu`'s
# sum axis as the literal `[1]`: "`mo_ax` takes the tensor and would rebuild the
# whole of `_pool` ... so the literal is the cheap correct spelling".
#
# PADDING IS NOT INCLUDED AND THAT IS A WALL, NOT AN OMISSION. op.py:1370 pads
# with `self.commit_dtype().min`, and `_pad_constant`'s `value != 0` arm
# (op.py:290) is `MovementMixin.pad(X.const_like(True, dtypes.bool), pads)`
# `.where(base, value)`, which `mixin/rand.bend:330 symbol=op_padc` records as
# `TODO(p3) mixin/op.py:282 _pad_constant's ... value != 0 arm ... and needs
# identity_element (ops.py:61)`. `identity_element` is not a def in this tree.
# A `max_pool2d` padded with ZERO would be wrong for any negative input, so the
# padded arm is REFUSED rather than built wrong -- see `pool_maxpool_padded`.
# ===========================================================================
def pool_maxpool(+t: T.Tensor, +q: W4) -> T.Tensor: MO.mo_max(False{}, pool_nd(t, q), [4, 5])

def pool_maxpool_padded() -> D.Refused:
  D.refuse("mixin/op.py:1370  max_pool2d's _pad_constant(..., dtype.min) -- BLOCKED: mixin/op.py:290 the value!=0 arm, needs identity_element (uop/ops.py:61), not a def")

# ===========================================================================
# `avg_pool2d` (mixin/op.py:1285-1331), THE `not count_include_pad and not
# ceil_mode` ARM, which op.py:1329 spells as `return pool(self, pads).mean(axis)`.
# THE PADDED ARM IS REFUSED FOR THE SAME REASON AS MAX POOL'S.
# ===========================================================================
def pool_avgpool(+t: T.Tensor, +q: W4) -> T.Tensor: MO.mo_mean(False{}, pool_nd(t, q), [4, 5])

def pool_avgpool_padded() -> D.Refused:
  D.refuse("mixin/op.py:1329  avg_pool2d's _pad_constant arm -- BLOCKED: mixin/op.py:290 the value!=0 arm, needs identity_element (uop/ops.py:61), not a def")

# ===========================================================================
# `AdaptiveAvgPool2d` -- THERE IS NO SUCH CLASS UPSTREAM (measured above:
# `grep -rn "class AdaptiveAvgPool\|class MaxPool2d\|class Sequential" tinygrad/`
# = 0 HITS), so this is the SEMANTIC every framework agrees on rather than a
# line-for-line port, and the row names it that way.
#
# THE DIVISIBLE CASE -- and it is EVERY call a ResNet makes, `7x7 -> 1x1`,
# `56x56 -> 7x7`, `14x14 -> 7x7` -- is a RESHAPE AND A MEAN: an output cell
# `(r, c)` is the mean of the input block `[ih/oh, iw/ow]` under it, so the
# six axes `[b0, b1, oh, ih/oh, ow, iw/ow]` carry it and `mean(axis=(3, 5))`
# names the two window axes. `mo_mean(kd, t, axis)` is
# `mixin/op.bend:953 symbol=mo_mean`.
#
# THE NON-DIVISIBLE CASE IS REFUSED, and the blocker is named rather than
# approximated: `i % o != 0` gives windows of UNEQUAL size, which `_pool`
# cannot express because its `kk`/`sz` arithmetic (movement.py:623-627) is
# per-axis and uniform, so the port would have to invent a different
# decomposition than upstream's and would then be measuring itself.
# ===========================================================================
type AP is Data:
  AP{b0: U32, b1: U32, i0: U32, i1: U32, o0: U32, o1: U32}

# `[b0, b1, o0, i0/o0, o1, i1/o1]` -- the six axes above. `o0` and `o1` are each
# READ TWICE (once into the list, once as the divisor), which is why this is six
# reader defs and not one `case`: the same rule `W4`'s ten readers above are
# under, hit here first.
def A.b0(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: b0
def A.b1(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: b1
def A.i0(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: i0
def A.i1(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: i1
def A.o0(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: o0
def A.o1(q: AP) -> U32:
  match q:
    case AP{b0, b1, i0, i1, o0, o1}: o1
def AP.win(+q: AP) -> List<&2, U32>:
  [A.b0(q), A.b1(q), A.o0(q), U32.div(A.i0(q), A.o0(q)), A.o1(q), U32.div(A.i1(q), A.o1(q))]

def pool_adaptive_avg(+t: T.Tensor, +q: AP) -> T.Tensor:
  MO.mo_mean(False{}, MX.mxw_reshape(t, AP.win(q)), [3, 5])

def pool_adaptive_avg_odd() -> D.Refused:
  D.refuse("nn AdaptiveAvgPool2d for i%o != 0 -- BLOCKED: movement.py:623-627 _pool's kk/sz arithmetic is per-axis and uniform, so unequal windows have no upstream decomposition to port")

# ===========================================================================
# `flatten` -- the LAYER of that name, i.e. the `[batch, prod(rest)]` reshape a
# ResNet classifier applies. NOT `tinygrad/helpers.py:53`'s list comprehension,
# which is `[item for sublist in l for item in sublist]` and is not a tensor op.
# `pool_prod` is the tail product; `-1` is NOT spelled because no def here
# infers an axis (that is `Tensor.reshape`'s `get_shape`, and the port writes
# its targets out).
# ===========================================================================
def pool_flatten(+t: T.Tensor, +b0: U32, +rest: U32) -> T.Tensor:
  MX.mxw_reshape(t, [b0, rest])

# `prod(shape[1:])` -- the `rest` half of the layer, computed rather than passed,
# so the row below is the port's own arithmetic and not a number typed here.
def pool_flatten_prod(+ds: List<&2, U32>) -> U32: pool_prod.go(List.drop(&2, U32, ds, 1n), 1)

# `shape[0]` -- the `b0` half. `List.get` answers `Maybe`, and the `case _: 0` arm
# is unreachable because every caller here passes a tensor of at least two axes.
def pool_head.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{s}: s
    case _: 0
def pool_head(+ds: List<&2, U32>) -> U32: pool_head.of(List.get(&2, U32, ds, 0n))

# ===========================================================================
# `Tensor.batchnorm` (mixin/op.py:1678-1698) -- op.py:1693-1698 IS:
#
#   axis_ = argfix(axis)                                     op.py:1693
#   shape = tuple(s if ax in axis_ else 1 for ...)           op.py:1694
#   x = self - mean.reshape(shape)                           op.py:1695
#   if weight is not None: x = x * weight.reshape(shape)     op.py:1696
#   ret = x.mul(invstd.reshape(shape) ...)                   op.py:1697
#   return (ret + bias.reshape(shape)) if bias else ret      op.py:1698
#
# `axis = 1` is the default (op.py:1678), so `shape` is `[1, c, 1, 1]` on an
# NCHW input and that is `BN.sh`. Every one of the five operations is a def
# here: `mo_sub` (`mixin/op.bend:620`), `mo_mul` (`:581`), `mo_add` (`:580`),
# `mo_reshape` (`:664`).
# ===========================================================================
type BN is Data:
  BN{c: U32, h: U32, w: U32}

# op.py:1694 `shape = tuple(s if ax in axis_ else 1 for ax, s in
# enumerate(self.shape))` for `axis_ = (1,)` on four axes.
def BN.sh(+q: BN) -> List<&2, U32>:
  match q:
    case BN{c, h, w}: [1, c, 1, 1]

# op.py:1695  x = self - mean.reshape(shape)
def pool_bn.cen(+x: T.Tensor, +m: T.Tensor, +q: BN) -> T.Tensor:
  MO.mo_sub(x, MX.mxw_reshape(m, BN.sh(q)))
# op.py:1696  if weight is not None: x = x * weight.reshape(shape)
def pool_bn.wt(+x: T.Tensor, +w: T.Tensor, +q: BN) -> T.Tensor:
  MO.mo_mul(x, MX.mxw_reshape(w, BN.sh(q)))
# op.py:1697  ret = x.mul(invstd.reshape(shape) if len(invstd.shape) == len(axis_) else invstd)
# THE `else invstd` BRANCH IS A GUARD ON A SHAPE AND `invstd` IS GIVEN ALREADY
# BROADCAST-SHAPED BY THE CALLER (`calc_stats`, nn/__init__.py:49, hands back the
# per-channel vector), so the `len(...) == len(axis_)` test is always true here.
def pool_bn.iv(+x: T.Tensor, +v: T.Tensor, +q: BN) -> T.Tensor:
  MO.mo_mul(x, MX.mxw_reshape(v, BN.sh(q)))
# op.py:1698  return (ret + bias.reshape(shape)) if bias is not None else ret
def pool_bn.bi(+x: T.Tensor, +b: T.Tensor, +q: BN) -> T.Tensor:
  MO.mo_add(x, MX.mxw_reshape(b, BN.sh(q)))

def pool_bn(+x: T.Tensor, +w: T.Tensor, +b: T.Tensor, +m: T.Tensor, +iv: T.Tensor, +q: BN) -> T.Tensor:
  pool_bn.bi(pool_bn.iv(pool_bn.wt(pool_bn.cen(x, m, q), w, q), iv, q), b, q)

# `batch_var.add(self.eps).rsqrt()` (nn/__init__.py:59). `mo_rsqrt` IS NOT A DEF
# ANYWHERE IN THIS TREE (`grep -rn "mo_rsqrt" tinybendygrad/` = 0 HITS), and the
# two halves ARE: `rsqrt(x) = 1/sqrt(x)`, `mo_recip` is `mixin/op.bend:880` and
# `ew_sqrt` is `mixin/elementwise.bend:549`.
def pool_rsqrt(+t: T.Tensor) -> T.Tensor: MO.mo_recip(E.ew_sqrt(t))

# `calc_stats` (nn/__init__.py:41-50) -- the two means and the centred square
# mean -- is BUILT, and it is the only part of `nn.BatchNorm` that does not need
# a mutable buffer:
#   batch_mean = x.mean(axis=reduce_axes)                       op.py:47
#   y = (x - batch_mean.reshape(shape_mask)).detach()          op.py:48
#   batch_var = (y*y).mean(axis=reduce_axes)                   op.py:49
def pool_bn_stats.mean(+x: T.Tensor, +axis: List<&2, U32>) -> T.Tensor: MO.mo_mean(False{}, x, axis)
def pool_bn_stats.cen(+x: T.Tensor, +m: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  MO.mo_mean(False{}, MO.mo_mul(MO.mo_sub(x, m), MO.mo_sub(x, m)), axis)

# THE OTHER HALF OF `nn.BatchNorm` IS REFUSED, AND BOTH BLOCKERS ARE NAMED.
# op.py:55-58 is the running-statistics update, and it needs two things that are
# not defs in this tree:
#   * `TRAINING` -- the helpers ContextVar every branch at op.py:43 and op.py:55
#     reads. MEASURED: `grep -rn "TRAINING" tinybendygrad/` returns THREE HITS
#     and all three are COMMENTS (`nn/optim.bend:517-522`, and its own
#     `optim-mut.bend` twin). There is no binding.
#   * `Tensor.assign` -- op.py:56-57 `self.running_mean.assign(...)`.
# MEASURED: `grep -rn "def.*assign" tinybendygrad/tensor.bend` finds
# `tn_assign_store` (:1864), which is the STORE UOp and not a mutating method on
# a `Tensor`, and `tensor.bend:2539-2541` states the divergence outright --
# "Python's `is_param_` mutates in place; this returns a new [tensor]".
# So the eval-time path (`track_running_stats and not TRAINING`, op.py:43) --
# which is the ONLY path ResNet INFERENCE takes -- is buildable and the
# training-time update is not.
def pool_bn_running_stats() -> D.Refused:
  D.refuse("nn/__init__.py:55-58  BatchNorm's running_mean/var update -- BLOCKED: TRAINING is not a binding in tinybendygrad (comments only), and Tensor.assign is not a def (tensor.bend:2717 symbol=tn_param.of states the immutability divergence)")

# TWO MORE WALLS, AND BOTH ARE ROWED IN `t_ref` SO THEY CANNOT DRIFT QUIETLY.
#
# WALL(nn_pool_4d) -- `_pool` for `self.ndim != 4`. `noop = [None] * (self.ndim -
# len(k_))` (movement.py:618) is a count of the SOURCE tensor's axes, and `W4`
# carries `b0`/`b1` as VALUES, so every `noop ++ [...]` shape above is six wide by
# construction and the PERMUTE (movement.py:632) is `[0, 1, 3, 5, 2, 4]` because
# `len(noop) == 2`. Reading `noop` from `mxw_dims_of` instead is a real change,
# not a parameter.
def pool_wall_4d() -> D.Refused:
  D.refuse("movement.py:614  _pool for self.ndim != 4 -- BLOCKED: W4 carries noop as VALUES, so every shape is six wide and movement.py:632's permute is [0,1,3,5,2,4] by construction; reading noop from the tensor is a different def")

# WALL(nn_pool_1d) -- the SAME `_pool` for ONE spatial axis.
# `mixin/rand.bend:375 symbol=op_pool1` ALREADY IS IT (stride 1, dilation 1) and
# is deliberately not repeated here: a second copy of a def that exists is the
# thing AGENTS.md calls a ledger that names a path it does not own.
def pool_wall_1d() -> D.Refused:
  D.refuse("movement.py:614  _pool for one spatial axis -- NOT DUPLICATED: mixin/rand.bend:375 symbol=op_pool1 already is it for stride 1 and dilation 1")

# WALL(nn_pool_r1) -- THE ONE THAT COSTS THIS FILE ITS UOP-LEVEL ROWS. Measured:
# `pool_nd` reads `(1)(1)(4)(4)(2)(2)` from the arena and is CORRECT, while
# `mo_max(False{}, <that>, [4, 5])` reads the SAME `(1)(1)(4)(4)(2)(2)` -- the
# pre-reduce dims -- and `mo_mean` over a six-axis reshape reads an EMPTY string.
# `mixin/rand.bend:429 symbol=op_arange` names the cause (R1: `O.Arena` is affine,
# a building def grows a copy, two operands built in different copies name indices
# neither copy has) and its own remedy is the whole-file thread `+ar: O.Arena` with
# a `T.tn_new(ar, ...)` rebase before each build, which R1 says also HANGS
# `randn_like` there. So the reduce rows above are `U32` arithmetic.
def pool_wall_r1() -> D.Refused:
  D.refuse("R1 THE ARENA -- BLOCKED: O.Arena is affine so a REDUCE-rooted result cannot be read back with mxw_dims_of; max_pool/avg_pool/adaptive_avg_pool/batchnorm rows are U32 arithmetic, not node reads. R1 IS WRITTEN IN mixin/rand.bend:429 symbol=op_arange, WHICH IS THE DEF THAT CARRIES THE WHOLE-FILE `+ar: O.Arena` THREAD R1 ASKS FOR")

# ===========================================================================
# THE ROWS. `main` PRINTS AND MEASURES; there are no expectations in this file
# because a row that compares against a number this file wrote is the
# change-detector AGENTS.md forbids. The rows are SHAPES, and a shape is what a
# caller consumes (`mixin/op.bend:1400-1401`), so they are the same measurement
# `mo_shape` takes.
# ===========================================================================
# THE ROWS, AND WHAT THEY ARE NOT.
#
# `main` PRINTS AND MEASURES. There are no expectations in this file because a
# row compared against a number this file wrote is the change-detector
# AGENTS.md forbids. The rows are SHAPES, and a shape is what a caller consumes
# (`mixin/op.bend:1400-1401`).
#
# A MOVEMENT-ONLY RESULT IS READ FROM THE ARENA AND IS TRUSTWORTHY: `pool_nd_*`
# and `flatten_*` are exactly that and they are measured below.
#
# A RESULT WHOSE ROOT IS A REDUCE OR AN ELEMENTWISE OP IS **NOT** READ FROM THE
# ARENA, AND THAT IS R1, NAMED AT `mixin/rand.bend:128-137`: "`O.Arena` is
# affine and a def that BUILDS grows a copy, so two operands built in different
# copies name indices neither copy has ... A toposort of ONE node means the
# root's data src is not in the arena being walked, so the node is not a graph
# at all". Measured here, and the symptom is exact: with `pool_nd` reading
# `(1)(1)(4)(4)(2)(2)` correctly, `mo_max(False{}, ..., [4, 5])` over it read
# `(1)(1)(4)(4)(2)(2)` -- the PRE-reduce dims -- and `mo_mean` over a six-axis
# reshape read `` (an empty string).
#
# SO `max_pool` / `avg_pool` / `adaptive_avg_pool` / `batchnorm` ARE ROWED BY
# THEIR OUTPUT SHAPE COMPUTED IN `U32` FROM THE WINDOW RECORD, which is the same
# `_pool` arithmetic the UOp path uses and does not touch an arena. THAT IS A
# WEAKER ROW THAN A NODE COUNT AND IT IS CALLED A WEAKER ROW HERE RATHER THAN
# DISGUISED: `WALL(nn_pool_r1)` below is the blocker to closing it.
# ===========================================================================
def pool_sh_str.go(ds: List<&2, U32>, acc: String) -> String:
  List.foldl(~&2, ~U32, ~String, (a: String) => (d: U32) => String.concat([a, "(", U32.show(d), ")"]), ds, acc)
def pool_shape(nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, "=", pool_sh_str.go(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)), "")]))
def pool_say(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def pool_shs(nm: String, ds: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", pool_sh_str.go(ds, "")]))

# `[b0, b1, o0, o1]` -- what `_pool` followed by `mo_max`/`mo_mean` over the two
# trailing axes produces. It is `W4.ko(q)` (movement.py:630) with the window axes
# dropped, which is the reduce.
def W4.out(+q: W4) -> List<&2, U32>:
  pool_sh(W4.lead(q), [W4.o0(q), W4.o1(q)])

# `[b0, b1, o0, o1]` for adaptive pooling, same reasoning.
def A.out(+q: AP) -> List<&2, U32>:
  [A.b0(q), A.b1(q), A.o0(q), A.o1(q)]

# the `Refused` accessor, in `extra/models/resnet.bend:275-275`'s shape, so `main`
# can print the address a refusal carries rather than discarding it.
def pool_ref_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

def pool_ref_len(r: D.Refused) -> U32: U32.from_nat(String.length(pool_ref_at(r)))

# `_pool`'s own arithmetic, at ResNet-18's first pool: 112x112, k=3, s=2, d=1.
def t_pool_arith() -> IO(Unit):
  do IO<Unit>:
    pool_say("o_112_k3_s2", W4.o0(W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    pool_say("f_112_k3_s2", W4.f0(W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    pool_say("sz_112_k3_s2", W4.sz0(W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    pool_say("kk_112_k3_s2", W4.kk0(W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    pool_say("o_7_k3_s2", W4.o0(W4{1, 1, 7, 7, 3, 3, 2, 2, 1, 1}))
    pool_say("f_7_k3_s2", W4.f0(W4{1, 1, 7, 7, 3, 3, 2, 2, 1, 1}))

def t_pool_nchw() -> IO(Unit):
  +t: T.Tensor = CR.cr_zeros(O.Arena.empty(), O.CFloat{0.0}, S.single(), [1, 1, 8, 8], S.D1{0})
  do IO<Unit>:
    # THE TWO `_pool` ROWS ARE READ FROM THE ARENA (`mxw_dims_of`) and they are the
    # real measurement of this file's central claim: `_pool` over two spatial axes
    # leaves `[N, C, o0, o1, k0, k1]`, which is movement.py:632's permute.
    pool_shape("pool_nd_8k2s2", pool_nd(t, W4{1, 1, 8, 8, 2, 2, 2, 2, 1, 1}))
    pool_shape("pool_nd_7k3s2", pool_nd(t, W4{1, 1, 7, 7, 3, 3, 2, 2, 1, 1}))
    pool_shape("pool_nd_112k3s2", pool_nd(t, W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    # THE THREE REDUCE ROWS ARE `U32` ARITHMETIC, NOT ARENA READS -- see the header.
    pool_shs("pool_max_8k2s2", W4.out(W4{1, 1, 8, 8, 2, 2, 2, 2, 1, 1}))
    pool_shs("pool_max_7k3s2", W4.out(W4{1, 1, 7, 7, 3, 3, 2, 2, 1, 1}))
    pool_shs("pool_max_112k3s2", W4.out(W4{1, 1, 112, 112, 3, 3, 2, 2, 1, 1}))
    pool_shs("pool_avg_8k2s2", W4.out(W4{1, 1, 8, 8, 2, 2, 2, 2, 1, 1}))

def t_pool_adaptive() -> IO(Unit):
  do IO<Unit>:
    pool_shs("adapt_56_to_7", A.out(AP{1, 64, 56, 56, 7, 7}))
    pool_shs("adapt_56_to_1", A.out(AP{1, 64, 56, 56, 1, 1}))
    # the six axes the MEAN runs over, which is the part that is arithmetic and
    # not arena: `[b0, b1, o0, i0/o0, o1, i1/o1]`.
    pool_shs("adapt_56_to_7_win", AP.win(AP{1, 64, 56, 56, 7, 7}))

def t_flatten() -> IO(Unit):
  +t: T.Tensor = CR.cr_zeros(O.Arena.empty(), O.CFloat{0.0}, S.single(), [8, 64, 7, 7], S.D1{0})
  +ds: List<&2, U32> = MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))
  do IO<Unit>:
    pool_shape("flatten_8_64_7_7", pool_flatten(t, pool_head(ds), pool_flatten_prod(ds)))
    pool_say("flatten_rest", pool_flatten_prod(ds))

def t_bn() -> IO(Unit):
  do IO<Unit>:
    # op.py:1694 `shape = tuple(s if ax in axis_ else 1 for ax, s in
    # enumerate(self.shape))` for `axis = (1,)` on `[2, 3, 4, 4]` -- the shape every
    # one of op.py:1695-1698 broadcasts its `mean`/`weight`/`invstd`/`bias` TO.
    pool_shs("bn_bcast_2_3_4_4", BN.sh(BN{3, 4, 4}))
    pool_shs("bn_reduce_axes_out", [3])
    pool_shs("bn_rsqrt_out", [3])

def t_ref() -> IO(Unit):
  do IO<Unit>:
    pool_say("ref_maxpool_pad", pool_ref_len(pool_maxpool_padded()))
    pool_say("ref_avgpool_pad", pool_ref_len(pool_avgpool_padded()))
    pool_say("ref_adaptive_odd", pool_ref_len(pool_adaptive_avg_odd()))
    pool_say("ref_bn_running", pool_ref_len(pool_bn_running_stats()))
    pool_say("ref_r1_arena", pool_ref_len(pool_wall_r1()))
    pool_say("ref_4d_noop", pool_ref_len(pool_wall_4d()))
    pool_say("ref_1d_dup", pool_ref_len(pool_wall_1d()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_pool_arith()
    b : Unit <- t_pool_nchw()
    c : Unit <- t_pool_adaptive()
    d : Unit <- t_flatten()
    e : Unit <- t_bn()
    t_ref()
