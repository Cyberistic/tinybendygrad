# nn/layers.bend -- the LAYER vocabulary, which `nn/__init__.bend` is not.
#
# `nn/__init__.bend` (429 lines, 17 defs) is SHAPE ARITHMETIC: `nn_scale`,
# `nn_bound`, `nn_groups`, `nn_same`, `nn_mt`, `nn_glorot`. It builds no graph.
# Its own WALL block says why -- every `__call__` in tinygrad's nn is a Tensor
# MIXIN METHOD (`x.conv2d` mixin/op.py:1562, `x.linear` mixin/op.py:1254,
# `Tensor.relu` mixin/elementwise.py:672) and NONE of them was built. THIS FILE
# IS THE OTHER HALF: the defs that INTERN UOps.
#
# THE WALL TEXT NAMED THE WRONG BLOCKER, MEASURED AGAINST WHAT IS ON DISK.
#   `nn/__init__.bend:227` -- `x.linear` "walled on `linear_with_vars`
#     (movement.py) P3 and mixin/op.bend's W8 (the WMMA lowering)". NOT REACHED.
#     `Tensor.linear` (op.py:1254) is `x = self.mul(w) if len(w.shape) == 1 else
#     self.dot(w)`; for `nn.Linear` the weight is 2-D so it takes `dot`, and
#     `dot` (op.py:367) is RESHAPE + RESHAPE + PERMUTE + MUL + REDUCE + CAST.
#     All six are built today: `M.mo_reshape` (mixin/op.bend:664),
#     `M.mo_permute` (:680), `T.tn_mul` (tensor.bend:656), `M.mo_sum` (:811),
#     `M.mo_cast_t` (:370), `DT.least_upper_dtypes` (dtype.bend:218). WMMA is
#     `dot`'s HANDLER, and the layer's own arithmetic never selects it.
#   `nn/__init__.bend:231` -- `x.conv2d` "SIDE B, not built". `mixin/op.bend`'s
#     SIDE B is EMPTY: `tinybendygrad/mixin/op.bend:1523` is the last line and
#     reads `# SIDE B's SECTION GOES BELOW THIS LINE.`. Nothing there to wait on
#     -- `mixin/op.bend:246` reserves that half for a unit that writes it, and
#     this file is not that unit, so `conv2d` is built HERE from the same
#     primitives.
#   `Tensor.relu` is ALREADY PORTED at `tensor.bend:774` as `tn_relu`. So the
#     wall line naming it as missing is STALE; `nn_relu` below is a NAME onto it
#     and not a second copy of its body.
#
# WHY THE MUL IS NOT A WALL HERE, and this is the one non-obvious thing here.
# `nn/__init__.bend:299` says the broadcasting case of `__mul__` is walled on
# the SHAPE FOLD. THE FOLD IS NOT THE WALL: `_broadcast_shape` (ops.py:80 symbol=_broadcast_shape) is
# PORTED -- `F.bcast_shape` (uop/fold.bend:672) over `bcast.first(_align_left
# (sh))` -- and `F.alu_ds` (fold.bend:999) is where every elementwise `OpsMUL` /
# `OpsADD` node's SHAPE is read from. A `T.tn_mul` of two DIFFERENTLY SHAPED
# tensors therefore builds the right node and folds to the right shape. What
# `nn/__init__` calls walled is the other half of `_broadcasted`
# (elementwise.py:21 symbol=ufix): `ufix`, then `least_upper_dtype`, then `cast(out_dtype)`.
# THAT is the half this file refuses rather than assumes, and `nn_dot.dts`
# refuses it by NAME.
#
# ONE REFUSAL POINT, AND IT IS A `Maybe` RATHER THAN A SILENT ZERO. Every dim
# `dot` does arithmetic on is a `sint` -- `tinygrad/uop/ops.py:1923`'s
# `int|UOp`, spelled `SI{i64} | SU{uop}` at `uop/ops.bend:810`. The port has FOUR
# defs on that union (`SInt.of`, `SInt.uop`, `SInt.i`, `SInt.u`; ops.bend:814-822
# and :74-81 symbol=smax) and NOT ONE ARITHMETIC DEF: `ceildiv` and `smax` on a `Sint`
# are ABSENT, and `smax` upstream is `UOp.maximum` (uop/ops.py:233), i.e. a
# symbolic MAX NODE, not a function. So `nn_u32` projects a shape to `U32` and
# answers `None` on the `SU` arm, and every def downstream of a shape is a
# `Maybe`. That is the whole of the wall, stated in one place.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./../dtype.bend as DT
import ./../mixin/op.bend as M
import ./../mixin/movement.bend as MX
import ./__init__.bend as NN
import ./../mixin/elementwise.bend as E
import ./../uop/weak.bend as W

# ===========================================================================
# THE SHAPE PROJECTION -- the file's one refusal point.
# ===========================================================================

# `Sint` -> `List<U32>`, `None` on the `SU` arm. THE WALK APPENDS AT THE TAIL,
# NOT AT THE HEAD, and that is the whole reason it needs no reversal: Bend's
# `List.append(a, A, xs, ys)` IS `xs ++ ys`, so `append(acc, [x])` puts the new
# element at the END and a walk that descends `ds` while accumulating UP
# therefore rebuilds `ds` in order. `mixin/movement.bend:246` records the same
# fact from the other side -- a walk that PREPENDS builds the answer backwards
# and needs the `List.reverse` that `mxm_pick.go` (movement.bend:684) carries.
#
# MEASURED, AND IT WAS WRONG FIRST: this walk appended at the tail AND reversed,
# so it answered `[3, 2]` for the shape `[2, 3]` -- every dim transposed, with
# every dim still a legal size, which is why `--check-only` was green and the row
# `where_xshape` was not. `nn_ks.go`, `nn_rep.*.go` and `nn_zipcat.go` below all
# append at the tail and reverse NOWHERE, and `nn_pads.grp` is the ONE place a
# reversal is wanted, because `flat_to_grouped` (helpers.py:58) genuinely
# reverses the pair order.
def nn_u32.go(+ds: List<&2, O.Sint>, +acc: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match ds:
    case Nil{}: Some{acc}
    case O.SI{i} <> rest: nn_u32.go(rest, List.append(&2, U32, acc, [H.lo32(i)]))
    case _: None{}

def nn_u32(+ds: List<&2, O.Sint>) -> Maybe<&2, List<&2, U32>>: nn_u32.go(ds, Nil{})

def nn_len32(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

def nn_shape(+t: T.Tensor) -> Maybe<&2, List<&2, U32>>:
  nn_u32(M.mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))

# `U32` -> `O.Const`, so a projected shape is a legal movement ARG.
# `mo_reshape` (mixin/op.bend:664) takes `List<&2, O.Const>` and `mo_ki`
# (:340) is the tree's one def for the conversion, so it is CALLED.
def nn_ks.go(+xs: List<&2, U32>, +acc: List<&2, O.Const>) -> List<&2, O.Const>:
  match xs:
    case Nil{}: acc
    case h <> rest: nn_ks.go(rest, List.append(&2, O.Const, acc, [M.mo_ki(h)]))

def nn_ks(+xs: List<&2, U32>) -> List<&2, O.Const>: nn_ks.go(xs, Nil{})

# `[0, 1, ..., n-1]` -- the IDENTITY PERMUTE ORDER, in `U32`. `List.range`
# (base:1020) answers `List<&2, Nat>` and `nn_dot.order` needs the index into a
# `U32` list, so it is one walk and not a `Nat` -> `U32` re-projection per cell.
def nn_range(n: U32) -> List<&2, U32>: M.mo_range(U32.to_nat(n))

# ===========================================================================
# `_rop` -- tinygrad/uop/ops.py:630-639. THIS IS THE ONE PLACE A LAYER CANNOT
# USE THE PORT'S OWN REDUCE, AND THE REASON IS NAMED.
#
# CPython SAYS IT IN A COMMENT: "permute so reduced axes are at the FRONT"
# (ops.py:636), then `UOp(Ops.REDUCE, src=(self.permute(perm),), arg=(op,
# len(reduce_axis)))` (:637). The port's TWO HALVES AGREE WITH EACH OTHER --
# `F.reduce_dims.put` (uop/fold.bend:892) answers `drop_n(shape, num_axes)` and
# `S.drop_n` (LAWS/spec.bend:270) drops FROM THE HEAD -- SO THE PORT'S REDUCE
# REDUCES THE FIRST `num_axes` AXES. THE PERMUTE THAT WOULD MAKE THAT TRUE FOR
# AN ARBITRARY AXIS IS NOT BUILT: `tn_rop.perm.of` (tensor.bend:1815) answers
# `self` IN BOTH ARMS and its own comment says so.
#
# MEASURED ON THIS FILE, AND IT IS WHY EVERY LAYER REDUCE IS WRONG WITHOUT THE
# PERMUTE: `sum(axis=-1)` over a `(2, 4, 3)` product answered `(4, 3)` -- axis 0
# -- where CPython answers `(2, 4)`, and `sum(..., keepdim=True)` answered
# `(1, 4, 3)` where CPython answers `(2, 4, 1)`. Both are legal shapes of the
# right RANK-adjacent size, so no node count and no op name sees it.
#
# `tensor.bend` IS NOT THIS UNIT'S FILE, SO THE PERMUTE IS BUILT HERE. It is
# ops.py:636 verbatim -- `reduce_axis` ++ the axes not in it -- and `nn_reduce`
# IS `_rop` with that line restored; it is not a workaround and it does not
# change the REDUCE node, whose arg is still `(op, len(reduce_axis))`.
# ===========================================================================

# `[i for i in range(len(shape)) if i not in axis]` -- ops.py:636's second
# half and ops.py:638's `kept`, so ONE walk answers both and the two cannot
# disagree about which axes a reduce removes.
def nn_reduce.mem(+axis: List<&2, U32>, +i: U32) -> Bool:
  match axis:
    case Nil{}: False{}
    case a <> t: Bool.pick(Bool, U32.is_eq(a, i), True{}, nn_reduce.mem(t, i))

def nn_reduce.at(+ds: List<&2, U32>, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ds, U32.to_nat(i)), 0)

def nn_reduce.rest.go(+ns: List<&2, U32>, +axis: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case i <> tail:
      nn_reduce.rest.go(tail, axis,
        Bool.pick(List<&2, U32>, nn_reduce.mem(axis, i), acc, List.append(&2, U32, acc, [i])))

def nn_reduce.rest(ns: List<&2, U32>, axis: List<&2, U32>) -> List<&2, U32>:
  nn_reduce.rest.go(ns, axis, Nil{})

# `reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1)` --
# ops.py:633. IT IS NOT OPTIONAL: an axis of size 1 is excluded from the permute
# AND from `len(reduce_axis)`, so a port that keeps it reduces one axis too many.
# `T.tn_rop`'s own `ne1` filter (tensor.bend:1796) is the same test and runs
# again on the PERMUTED tensor, where it keeps everything -- which is the point:
# this filter decides the SHAPE, that one decides the ARG, and they agree
# because the permute moved exactly these axes to the front.
# THE INDEX IS READ OUT OF THE SHAPE, NOT POSITIONALLY. `resolve(self.shape[x] !=
# 1)` is `shape[axis[j]]`, and a walk that zips `axis` with `ds` and reads `ds[j]`
# agrees with it only when `axis` IS `range(n)` -- which is the case for
# `mixin/op.bend`'s own rows (`t_sh_sum0kd` reduces axis 0 of a 1-D tensor) and
# NOT the case for a layer, where the axes are the trailing ones. MEASURED on
# this file's own row: `sum([-1,-2,-3])` over a 6-axis product read `ds[0..2]`
# instead of `ds[3..5]` and kept the wrong `reduce_axis`.
def nn_reduce.rn.go(+axis: List<&2, U32>, +ds: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match axis:
    case Nil{}: acc
    case a <> at:
      nn_reduce.rn.go(at, ds,
        Bool.pick(List<&2, U32>, U32.is_eq(nn_reduce.at(ds, a), 1), acc,
          List.append(&2, U32, acc, [a])))

def nn_reduce.rn(axis: List<&2, U32>, ds: List<&2, U32>) -> List<&2, U32>:
  nn_reduce.rn.go(axis, ds, Nil{})

def nn_reduce.empty(rn: List<&2, U32>) -> Bool: U32.is_eq(nn_len32(rn), 0)

# `self.permute(perm)` then `_rop`'s REDUCE -- ops.py:636-637. The axis handed to
# `T.tn_rop` is `[0, ..., len(reduce_axis)-1]`: after the permute those ARE the
# reduced axes, and the port's head-drop REDUCE then reduces exactly them.
def nn_reduce.two(+t: T.Tensor, +rn: List<&2, U32>, +n: U32, op: O.Op) -> T.Tensor:
  +p = M.mo_permute(t, List.concat(&2, U32, [rn, nn_reduce.rest(nn_range(n), rn)]))
  +r = T.tn_rop(T.Tensor.ar(p), T.Tensor.u(p), op, nn_range(nn_len32(rn)))
  T.tn_new(O.Found.ar(r), O.Found.i(r))

# `if not len(reduce_axis): return self.reshape(kept)` -- ops.py:634. There is
# NO REDUCE and NO PERMUTE on this arm; a permute with an empty head would be a
# real node that CPython does not build.
# `kept = tuple(s for i, s in enumerate(self.shape) if i not in axis)` --
# ops.py:634 and ops.py:638. THE DIM VALUES at the surviving INDICES, so it walks
# `range(ndim)` and READS `ds[i]`. `nn_reduce.rest` answers the INDICES, which
# is what the permute at ops.py:636 wants; reading one as the other is what the
# row `fold_rr` caught -- `nn_reduce` reshaped a `(2, 4)` REDUCE to `(0, 1)`.
def nn_reduce.kept.go(+ns: List<&2, U32>, +axis: List<&2, U32>, +ds: List<&2, U32>,
  +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case i <> tail:
      nn_reduce.kept.go(tail, axis, ds,
        Bool.pick(List<&2, U32>, nn_reduce.mem(axis, i), acc,
          List.append(&2, U32, acc, [nn_reduce.at(ds, i)])))

def nn_reduce.kept(+ds: List<&2, U32>, +axis: List<&2, U32>) -> List<&2, U32>:
  nn_reduce.kept.go(nn_range(nn_len32(ds)), axis, ds, Nil{})

# `if not len(reduce_axis): return self.reshape(kept)` -- ops.py:634. There is
# NO REDUCE and NO PERMUTE on this arm; a permute with an empty head would be a
# real node CPython does not build.
def nn_reduce.none(+t: T.Tensor, +kept: List<&2, U32>) -> T.Tensor:
  M.mo_reshape(t, nn_ks(kept))

def nn_reduce.pick(+rn: List<&2, U32>, +t: T.Tensor, +kept: List<&2, U32>, +n: U32, op: O.Op) -> T.Tensor:
  Bool.pick(T.Tensor, nn_reduce.empty(rn), nn_reduce.none(t, kept), nn_reduce.two(t, rn, n, op))

# `ret.reshape(kept) if axis != reduce_axis else ret` -- ops.py:638. APPLIED
# UNCONDITIONALLY, which is the same thing: `axis == reduce_axis` makes `kept`
# the identity, and `M.mo_reshape` (mixin/op.bend:664) answers its source
# unchanged on an identity target rather than minting a RESHAPE. MEASURED: with
# the reshape applied, `sum(axis=[2])` over `(2, 4, 3)` is a 20-node graph whose
# root IS the REDUCE and whose folded shape is `(2, 4)`; with the INDICES
# substituted for the values it minted a second RESHAPE to `(0, 1)`, which the
# fold could not read, and the row printed nothing.
# `1 if i in axis else s for i,s in enumerate(self.shape)` -- reduce.py:18,
# THE KEEPDIM TARGET. **THIS IS NOW READ FROM `mixin/op.bend`'s `mo_keep_ds` AND NOT
# SPELLED HERE, AND THE REASON THE LOCAL COPY EXISTED IS GONE.**
# THE HISTORY, BECAUSE IT IS WHY THE BUG WAS HARD TO SEE: THE LOCAL COPY WAS WRITTEN
# WHEN `mo_keep_ds`'S INDEX WAS WRONG -- `mixin/op.bend`'s `mo_at` ANSWERED `len(t)`, THE
# INDEX **COUNTED FROM THE END**, WHILE EVERY NEIGHBOUR IS FORWARD (`mo_dim_at` READS
# `mo_dims` AT A FORWARD INDEX, `mo_resolve` ADDS `total` TO A NEGATIVE AXIS, `mo_range`
# BUILDS `0..n-1`). `.agents/slop/nnconv/probe/moat.bend` MEASURED `idx(10,20,30) = 2,1,0`
# OVER A FORWARD WALK, SO `mo_keep_ds` WAS RIGHT ON A ONE-DIMENSIONAL SHAPE -- WHERE THE
# TWO READINGS AGREE, AND WHERE `mixin/op.bend`'s `sh_sum0kd` ROW LIVES -- **AND WRONG ON
# EVERY OTHER**: IT ANSWERED `(1,4,3)` ON `(2,4,3)` WITH AXIS `[2]` WHERE CPython ANSWERS
# `(2,4,1)` (tinygrad/mixin/reduce.py:18).
# **⇒ SO THE PORT HAD *TWO* IMPLEMENTATIONS OF ONE RULE, ONE RIGHT AND ONE WRONG, AND THE
# NN LAYER USED THE RIGHT ONE -- WHICH IS EXACTLY WHY THE WRONGNESS WAS INVISIBLE: THE ROW
# THAT CAUGHT IT, `fold_smk`, EXPECTED `2,1,3`, WHICH IS CPython's ANSWER FOR AXIS `[1]`
# **AND ALSO WHAT THE PORT'S `mo_keep_ds` ANSWERED FOR EVERY AXIS**. A WRONG ANSWER THAT
# COINCIDES WITH A RIGHT ONE IS THE DEEPEST FORM OF *\"A ROW THAT CANNOT GO RED IS A
# LABEL\"*.**
# **⇒ AND `mo_at` IS NOW FIXED** (`mixin/op.bend`: `n - len(ds)`, THE ORIGINAL LENGTH
# THREADED, BECAUSE `ds` AT THE CALL SITE IS THE *REMAINING* LIST), SO `mo_keep_ds` IS
# FORWARD AND CORRECT, AND THE LOCAL COPY IS DEAD WEIGHT. **⇒ AND THE TWO READ THE SAME
# SHAPE: `nn_shape` IS `nn_u32(M.mo_dims(...))` AND `mo_keep_ds` IS `mo_dims(...)` -- THE
# FOLD'S SHAPE, BOTH OF THEM -- SO THE SWAP CHANGES THE INDEX AND NOTHING ELSE.**
def nn_reduce.keep(kd: Bool, +src: T.Tensor, +r: T.Tensor,
  +axis: List<&2, U32>) -> T.Tensor:
  M.mo_reduce.keep(kd, src, r, axis)

def nn_reduce(+t: T.Tensor, +axis: List<&2, U32>, op: O.Op, kd: Bool) -> T.Tensor:
  +ds = Maybe.default(&2, List<&2, U32>, nn_shape(t), Nil{})
  +n = nn_len32(ds)
  +rn = nn_reduce.rn(axis, ds)
  +red = M.mo_reshape(nn_reduce.pick(rn, t, nn_reduce.kept(ds, axis), n, op),
    nn_ks(nn_reduce.kept(ds, axis)))
  nn_reduce.keep(kd, t, red, axis)

# `sum` -- mixin/reduce.py:20, on top of `nn_reduce`. The HEAD is `mo_sum`'s own
# (mixin/op.bend:811): `sum_acc_dtype(commit_dtype())` then a cast back iff the
# dtype was defaulted AND it is half/bfloat16/fp8 (`mo_downcast`). A layer sum
# is `dtype=None` upstream, so the head is not optional.
def nn_sum(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +uns = M.mo_downcast(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))
  +c = M.mo_cast_t(t, M.mo_sum_acc(M.mo_commit_dt(F.folded(T.Tensor.ar(t)), t)))
  M.mo_sum.castback(uns, nn_reduce(c, axis, O.OpsADD{}, kd))

# ===========================================================================
# `relu` -- mixin/elementwise.py:672, `return (self > 0).where(self, 0)`.
#
# THE BODY IS ALREADY PORTED at `tensor.bend:774` (`tn_relu`), as the chain
# `tn_rcmplt` -> `tn_where` over one shared `CONST 0`, and gated at
# `gates/tn_relu-gate.py`. `nn_relu` is a NAME onto it and not a second copy:
# a repeated line is a shared function, so the layer entry point and the tensor
# method cannot both spell the body.
#
# The `NOTE` at elementwise.py:673 -- "if you write this as self.maximum(0) the
# gradient is wrong, passing through half when self is 0" -- is why the graph is
# `CMPLT` + `WHERE` and never `MAX`. `nn_relu` cannot become `tn_maximum` and
# keep meaning `relu`.
# ===========================================================================

def nn_relu(+x: T.Tensor) -> T.Tensor: T.tn_relu(x)

# ===========================================================================
# `dot` -- mixin/op.py:367-392 (THE VENDORED `002630241`), THE BODY LINE BY LINE.
#
#   x, dx, dw = self, self.ndim, w.ndim                                         # :387
#   if not (dx > 0 and dw > 0): raise RuntimeError(...)                        # :388
#   if x.shape[-1] != w.shape[axis_w:=-min(w.ndim,2)]: raise RuntimeError(...)   # :389
#   x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])         # :390
#   w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)  # :391
#   return (x*w).sum(-1, dtype=dtype).cast(least_upper_dtype(x.dtype, w.dtype))  # :392
#
# AND THE TWO RAISES AT :388-389 ARE PORTED AS A `Maybe`, not skipped: a def
# whose answer for a 0-D operand is a well-formed graph is a def that builds the
# wrong graph silently, which is the failure mode this file is written against.
#
# `axis_w = -min(w.ndim, 2)` (:389) -- NOT THE `-w.ndim` AN EARLIER REVISION OF
# THIS BLOCK CLAIMED. THE TWO SPELLINGS ARE NOT THE SAME EXPRESSION:
#
#   * :389 IS `w.shape[axis_w:=-min(w.ndim,2)]`, AND PYTHON'S GRAMMAR MAKES THE
#     WALRUS THE SUBSCRIPT'S ONLY INDEX -- THERE IS NO SECOND `:` -- SO THE
#     GUARD READS `w.shape[axis_w]`, A SINGLE DIM. MEASURED, `.venv/bin/python`:
#     IT ANSWERS `3` FOR `w.shape=(3,4)`, NOT `(3,4)`.
#   * :391 IS `w.shape[axis_w:]` WITH `axis_w` A PLAIN NAME, SO IT IS A SLICE
#     AND ANSWERS THE LAST `min(dw,2)` DIMS.
#
# SO ON THE RESHAPED `w` OF LENGTH `len` THE AXIS `axis_w` IS `len - min(dw,2)`
# AND `-1` IS `len - 1`. THAT IS THE PAIR `nn_dot.order` EXCHANGES, AND IT IS
# WHY :391 NEEDS NO NEGATIVE INDEX ANYWHERE.
# ===========================================================================

# `*[1]*min(dx-1, dw-1, 1)` -- ONE def for the count that appears in BOTH
# reshapes (:387 and :388). It is 1 exactly when both operands have >= 2 dims,
# and `Bool.to_u32` is the Bool-as-`U32` helpers.bend:1609 already uses.
def nn_dotk(+dx: U32, +dw: U32) -> U32:
  Bool.to_u32(Bool.and(U32.is_ge(dx, 2), U32.is_ge(dw, 2)))

# `xs[0:-n]` -- CPython's TAIL SLICE, WHICH `List.drop` CANNOT SPELL.
#
# `List.drop` (references/bend/bend2/base.bend:993) IS A HEAD DROP: IT ANSWERS
# `xs[n:]`, AND `List.take` (base.bend:984) IS ITS COMPLEMENT, SO
# `take(xs, k)` ANSWERS `xs[:k]`. MEASURED, `.agents/slop/dotfix/sem.bend`:
# `drop([2,4,3], 1)` = `[4,3]` AND `drop([2,4,3], 2)` = `[3]`.
#
# CPython's `x.shape[0:-1]` (op.py:390) IS THE OTHER END: IT KEEPS EVERY DIM
# BUT THE LAST, AND ITS ANSWER IS `xs[:len-1]`. `Nat.sub` SATURATES AT 0
# (base.bend:657), SO A SHAPE SHORTER THAN `n` ANSWERS `Nil{}` -- WHICH IS
# WHAT `xs[0:-2]` ANSWERS FOR A 1-D OR A 2-D `w`.
#
# `uop/fold.bend`'s `take_n`/`drop_last` ARE THE SAME IDIOM ON `O.Sint`, AND
# `runtime/support/system.bend`'s `pcibus[:-1]` IS THE SAME IDEA ON A STRING.
def nn_tail_drop(+xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  List.take(&2, U32, xs, Nat.sub(List.length(&2, U32, xs), n))

# `x.shape[0:-1]` ++ `[1]*k` ++ `[x.shape[-1]]` -- :387.
def nn_dot.xshape(+xs: List<&2, U32>, k: U32) -> List<&2, U32>:
  List.append(&2, U32, List.concat(&2, U32,
    [nn_tail_drop(xs, 1n), H.make_tuple_rep(1, k)]),
    [Maybe.default(&2, U32, List.last(&2, U32, xs), 0)])

# `axis_w = -min(dw,2)` (header), SO `w.shape[axis_w:]` IS THE LAST
# `min(dw,2)` DIMS -- `(w0,)` FOR dw==1, `(w0,w1)` FOR dw==2, `(w1,w2)` FOR
# dw==3 -- AND `w.shape[0:-2]` IS EVERY DIM BUT THE LAST TWO -- `()` FOR
# dw<=2 AND `(w0,)` FOR dw==3.
#
# SO THE TARGET IS `DROP_LAST 2` ++ `ONES k` ++ `DROP_FIRST (dw-min(dw,2))`, AND
# `Nat.sub` SATURATES AT 0 (base.bend:657) SO `dw-min(dw,2)` IS 0 FOR dw==1
# AND dw==2 -- WHICH IS EXACTLY CPython's `w.shape[axis_w:]` THERE. THE HEAD
# DROP `List.drop(ws, 2n)` THIS USED TO SPELL ANSWERED `ws[2:]`, WHICH IS
# `(w2,)` FOR dw==3 WHERE CPython'S FIRST SLICE ANSWERS `(w0,)`.
def nn_dot.wshape(+ws: List<&2, U32>, k: U32) -> List<&2, U32>:
  +dw = List.length(&2, U32, ws)
  List.concat(&2, U32, [nn_tail_drop(ws, 2n), H.make_tuple_rep(1, k),
    List.drop(&2, U32, ws, Nat.sub(dw, Nat.min(dw, 2n)))])

def nn_umin(a: U32, b: U32) -> U32: U32.min(a, b)

# `.transpose(-1, axis_w)` -- :391, AS THE IDENTITY ORDER WITH TWO POSITIONS
# EXCHANGED. `axis_w = -min(dw,2)` (header), SO ON THE RESHAPED `w` OF LENGTH
# `len` THE AXIS IS `len - min(dw,2)` AND `-1` IS `len - 1`: THOSE ARE THE TWO
# POSITIONS EXCHANGED. FOR dw==1 THEY COINCIDE (BOTH 0), SO THE ORDER IS THE
# IDENTITY AND `M.mo_permute`'s OWN IDENTITY TEST HANDS `w` BACK UNCHANGED --
# WHICH IS EXACTLY WHAT CPython'S `transpose(-1, -1)` ON A 1-D TENSOR DOES.
def nn_dot.order(+len: U32, +dw: U32) -> List<&2, U32>:
  +ids = nn_range(len)
  +b = U32.sub(len, nn_umin(dw, 2))
  List.set(&2, U32, List.set(&2, U32, ids, U32.to_nat(b), U32.sub(len, 1)),
    U32.to_nat(U32.sub(len, 1)), b)

# `sum(-1)` -- :392. PYTHON'S `-1` HAS NO `U32` IMAGE, and the port's own
# `mo_ax`/`mo_resolve` (mixin/op.bend:753/:719) cannot spell it:
# `mo_resolve(neg, dim, total) = dim + total`, so `neg=True, dim=1` answers
# `ndim+1`, one PAST the last axis. THE RESOLVED INDEX IS TAKEN FROM THE OTHER
# END -- `nn_last_ax` -- which is the same value and is total.
def nn_last_ax(n: U32) -> U32: U32.sub(n, 1)

def nn_umax(a: U32, b: U32) -> U32: U32.max(a, b)

# `_broadcasted`'s dtype half (elementwise.py:24) -- THE REFUSAL. `tn_mul`
# (tensor.bend:651) is the NODE, and the node's shape comes from the fold
# (`F.alu_ds`, fold.bend:999), but the `cast(out_dtype)` is `mo_promote`'s job
# (mixin/op.bend:246's W9b) and it is what the no-broadcasting gates do not
# cover. `dot` multiplies two tensors of the SAME dtype, where that cast is the
# identity, so this answers `None` rather than assuming it -- and `None` for an
# UNREADABLE dtype too, so a caller can never `least_upper_dtype` from `void`.
def nn_dot.dts(xdt: Maybe<&2, S.Dt>, wdt: Maybe<&2, S.Dt>) -> Maybe<&2, S.Dt>:
  match xdt:
    case Some{a}: Maybe.map(&2, S.Dt, S.Dt, b => DT.least_upper_dtypes([a, b]), wdt)
    case None{}: None{}

# `(x*w).sum(-1).cast(dt)` -- :392. `M.mo_sum(False{}, ...)` IS
# `mixin/reduce.py:20` hoisted (mixin/op.bend:811), downcast-and-cast-back
# included. IT TAKES THE PRODUCT, NOT THE TWO OPERANDS, BECAUSE THE PRODUCT
# IS WHERE THE SECOND REFUSAL LIVES.
def nn_dot.tail(+xw: T.Tensor, ax: U32, dt: S.Dt) -> T.Tensor:
  M.mo_cast_t(nn_sum(False{}, xw, [ax]), dt)

# CPython's SECOND REFUSAL IS AT `(x*w)`: `_broadcast_shape` (ops.py:80) RAISES
# `IndexError` WHEN THE TWO RESHAPED SHAPES DO NOT BROADCAST. THE PORT'S FOLD
# REFUSES THE SAME WAY -- `F.bcast_shape` (fold.bend:672) ANSWERS `None` -- AND
# THE PRODUCT IS WHERE THAT REFUSAL SHOWS. THE PRODUCT IS NEVER 0-D (BOTH
# OPERANDS HAVE AT LEAST ONE DIM), SO AN EMPTY SHAPE IS THE REFUSAL AND NOT A
# ZERO-RANK TENSOR: THE RESULT OF A 1-D `dot` A 1-D IS 0-D, AND THE PRODUCT IS
# NOT.
def nn_dot.mul(+xr: T.Tensor, +wr: T.Tensor, ax: U32, dt: S.Dt) -> Maybe<&2, T.Tensor>:
  +xw = T.tn_mul(xr, wr)
  Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(xw),
    s => Bool.pick(Maybe<&2, T.Tensor>, List.is_empty(&2, U32, s), None{}, Some{nn_dot.tail(xw, ax, dt)}))

# `x.reshape(...)` and `w.reshape(...).transpose(-1, axis_w)` -- :390-391. The
# two reshapes SHARE ONE `k`: the `*[1]*min(dx-1, dw-1, 1)` at :387 and at :388
# is one expression in CPython and must be one value here, or the two arms can
# disagree about `dw`. The product's rank is `max(len(x'), len(w'))` -- that is
# `_align_left` + `bcast.first`, the same fold the node's own shape is read from
# (`F.bcast_shape`, fold.bend:672) -- and `sum(-1)` is over THAT, so the axis is
# `nn_last_ax` of the max and not of either operand. `xs` and `ws` are VALUES
# because each is both a reshape argument and the source of a rank; computing
# either twice is how the two would drift apart.
def nn_dot.pair(+x: T.Tensor, +w: T.Tensor, +ax: List<&2, U32>, +bw: List<&2, U32>, dt: S.Dt) -> Maybe<&2, T.Tensor>:
  +k = nn_dotk(nn_len32(ax), nn_len32(bw))
  +xs = nn_dot.xshape(ax, k)
  +ws = nn_dot.wshape(bw, k)
  +wr0 = M.mo_reshape(w, nn_ks(ws))
  nn_dot.mul(M.mo_reshape(x, nn_ks(xs)),
    M.mo_permute(wr0, nn_dot.order(nn_len32(ws), nn_len32(bw))), nn_last_ax(nn_umax(nn_len32(xs), nn_len32(ws))), dt)

# ===========================================================================
# `nn_dot` -- the `dot` ENTRY, refusals first. `Maybe` is the port's spelling
# of `raise RuntimeError` for the two guards at :388-389 and for the `SU` shape
# arm, and all three are the SAME `None`: CPython raises for two of them and the
# fold refuses the third.
# ===========================================================================

# A MISSING DIM IS A REFUSAL, NOT A DEFAULT VALUE: THE WHOLE GUARD IS `False`.
def nn_dot.guard.ans(m: Maybe<&2, Bool>) -> Bool:
  match m:
    case Some{b}: b
    case None{}: False{}

# `x.shape[-1] != w.shape[axis_w]` (:389) -- THE SECOND REFUSAL, AND THE ONE
# THAT WAS NEVER PORTED. `axis_w = -min(dw,2)` (header), SO `w.shape[axis_w]`
# IS `w.shape[-1]` FOR dw==1 AND `w.shape[-2]` FOR dw>=2: THE INDEX IS
# `dw - min(dw,2)` INTO `w.shape`. A MISSING DIM IS A REFUSAL, NOT A DEFAULT
# VALUE: THE WHOLE GUARD IS `False`.
def nn_dot.guard(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  +dw = List.length(&2, U32, bw)
  nn_dot.guard.ans(
    Maybe.bind(&2, U32, Bool, List.last(&2, U32, ax),
      xl => Maybe.map(&2, U32, Bool, wl => U32.is_eq(xl, wl),
        List.get(&2, U32, bw, Nat.sub(dw, Nat.min(dw, 2n))))))

# `dx > 0 and dw > 0` (:388) AND `x.shape[-1] != w.shape[axis_w]` (:389) --
# BOTH REFUSALS, AND A `Bool` AND NOT A `Maybe`, BECAUSE IT SELECTS BETWEEN
# TWO ANSWERS THAT BOTH EXIST. CPython RAISES ON THE FIRST, SO THE ORDER IS
# CPython's: THE RANK GUARD FIRST.
def nn_dot.rd(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  Bool.and(U32.is_gt(nn_len32(ax), 0), Bool.and(U32.is_gt(nn_len32(bw), 0), nn_dot.guard(ax, bw)))

def nn_dot.body(dt: Maybe<&2, S.Dt>, +x: T.Tensor, +w: T.Tensor, ax: List<&2, U32>, bw: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  match dt:
    case Some{d}: nn_dot.pair(x, w, ax, bw, d)
    case None{}: None{}

def nn_dot.go(+x: T.Tensor, +w: T.Tensor, +ax: List<&2, U32>, +bw: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  Bool.pick(Maybe<&2, T.Tensor>, nn_dot.rd(ax, bw),
    nn_dot.body(nn_dot.dts(T.tn_dtype(x), T.tn_dtype(w)), x, w, ax, bw), None{})

def nn_dot(+x: T.Tensor, +w: T.Tensor) -> Maybe<&2, T.Tensor>:
  Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(x),
    ax => Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(w),
      bw => nn_dot.go(x, w, ax, bw)))

# ===========================================================================
# `nn.Linear.__call__` -- tinygrad/nn/__init__.py:180,
# `return x.linear(self.weight.transpose(), self.bias)`.
#
# AND `Tensor.linear` (mixin/op.py:1254) IS ENTIRELY SPELLED BY WHAT IS ALREADY
# HERE PLUS TWO LINES, so it is not a separate def: `dtype is None` from the
# layer (the layer never passes one), so :1267 is dead on this path; `weight`
# is 2-D (`nn_linear.wshape` puts the batch dims in for `dw >= 3` and
# `nn_dot.wshape` is its mirror), so :1268 takes the `dot` arm and not the
# `self.mul(weight)` arm; and :1269 is `nn_linear.add`. THAT IS THE WHOLE OF
# `linear`, and it is why the wall naming `linear_with_vars` never binds --
# `linear_with_vars` is `dot`'s HANDLER, which this graph never reaches.
#
# THE BIAS IS A `Maybe<&2, T.Tensor>` AND NOT A THIRD TYPE. `nn/__init__.bend:26`
# measured that a `Data` field cannot hold a `Maybe`, which is why that file's
# `*_st` defs put a `Bool` BESIDE the value; here the `Maybe` is a PARAMETER, and
# a parameter may hold anything. So Python's `Tensor|None` is one `Maybe` here
# and not a parallel pair of defs.
# ===========================================================================

# `x.transpose()` -- movement.py:343 with the DEFAULT args `(dim0=1, dim1=0)`,
# so the order is `[1, 0, 2, ..., n-1]`. It is two `List.set`s because that is
# how the port spells "exchange two positions of a permute order", and
# `nn_dot.order` (header) is the same operation written the other way round.
def nn_transpose.put(+t: T.Tensor, ds: List<&2, U32>) -> T.Tensor:
  M.mo_permute(t, List.set(&2, U32, List.set(&2, U32, nn_range(nn_len32(ds)), 0n, 1), 1n, 0))

def nn_transpose(+t: T.Tensor) -> Maybe<&2, T.Tensor>:
  Maybe.map(&2, List<&2, U32>, T.Tensor, ds => nn_transpose.put(t, ds), nn_shape(t))

# `x.add(bias) if bias is not None else x` -- op.py:1269. The `tn_add` node's
# shape comes from the same `F.alu_ds` broadcast arm `nn_dot` relies on, and
# `bias` is `(out_features,)` against a `(..., out_features)` product, so this
# is a broadcast ADD and the fold answers it.
def nn_linear.add(+y: T.Tensor, bias: Maybe<&2, T.Tensor>) -> Maybe<&2, T.Tensor>:
  match bias:
    case Some{b}: Some{T.tn_add(y, b)}
    case None{}: Some{y}

def nn_linear(+x: T.Tensor, +w: T.Tensor, bias: Maybe<&2, T.Tensor>) -> Maybe<&2, T.Tensor>:
  Maybe.bind(&2, T.Tensor, T.Tensor, nn_transpose(w),
    wt => Maybe.bind(&2, T.Tensor, T.Tensor, nn_dot(x, wt), d => nn_linear.add(d, bias)))
# ===========================================================================
# `conv2d` -- mixin/op.py:1562-1603. THE WALL NAMED AT `nn/__init__.bend:231`
# IS NOT A WALL, and both halves of that are measurements.
#
#   "mixin/op.bend SIDE B, not built" -- `mixin/op.bend`'s SIDE B IS EMPTY.
#     `mixin/op.bend:1523` is that file's LAST line and reads
#     `# SIDE B's SECTION GOES BELOW THIS LINE.` There is nothing to wait for,
#     and `mixin/op.bend:246` reserves that half for whoever writes it. So
#     `conv2d` is written HERE, out of the primitives, rather than parked.
#
#   `_pool` -- `mixin/op.bend:60-70` (W4) calls it "BUILDABLE but not
#     CHECKABLE", and THAT is the true state: `mixin/movement.bend` Section E
#     IS the whole of `_pool`'s shape arithmetic -- `mx_pool_out` (:247),
#     `mx_pool_f` (:297), `mx_pool_kid` (:313), `mx_pool_rep` (:318),
#     `mx_pool_perm` (:392), `mx_pool_shape` (:902), `mx_i_` (:225),
#     `mx_nnoop` (:232), `mx_dropn` (:896) -- and its own header (:88-95) NAMES
#     these three defs as the interface a conv2d should call. WHAT IS BUILT
#     NOWHERE IS THE CHAIN: `repeat`, three `shrink_to`/`reshape` pairs, then
#     the `permute`. The chain is MOVEMENT NODES and not arithmetic, so it
#     belongs with the layer that calls it, and every node in it is one of
#     `mixin/movement.bend`'s own gated `mxw_*` builders.
#
# WHAT IS STILL REFUSED IS THE `SU` SHAPE ARM, by `nn_u32` (header) and by
# nothing else: `_pool`'s whole domain is concrete dims, which is exactly what
# `mixin/movement.bend`'s Section A is written in, so a symbolic input is the
# one thing this section cannot answer and says so with a `Maybe`.
# ===========================================================================

# --- the list algebra `_pool`'s chain needs --------------------------------

# `flatten((a, b) for ...)` over two equal-length lists. It is ONE def for the
# shape `movement.py:610-615` writes four times (`flatten((k, i*f+d))`,
# `flatten((k, o*s))`, `flatten((k, o, s))`, `flatten((k, o))`), and the four
# differ ONLY in their inputs -- a repeated shape is a shared function.
def nn_zipcat.go(+a: List<&2, U32>, +b: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case x <> at y <> bt: nn_zipcat.go(at, bt, List.append(&2, U32, List.append(&2, U32, acc, [x]), [y]))
    case _ _: acc

def nn_zipcat(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: nn_zipcat.go(a, b, Nil{})

def nn_zeros(n: Nat) -> List<&2, U32>: MX.mxf_zeros(n)

# `[1] * n` -- THE ONES. `MX.mx_range` IS `range(n)` (movement.py:616's
# `range(len(noop))`), so it answers `0, 1, ...` and NOT ones, and a list of
# ones is `helpers.bend`'s `make_tuple_rep`. MEASURED: with `mx_range` here the
# repeat's first count was `0`, so every repeated shape carried a LEADING ZERO
# and the fold's answer for the whole `_pool` chain was off by that zero.
def nn_ones(n: U32) -> List<&2, U32>: H.make_tuple_rep(1, n)

# `x.shrink_to(shape)` -- movement.py:291, `self.shrink(tuple((0, ns) for ns in
# shape))`. `mxw_shrink`'s marg is `(offset, SIZE)` (movement.bend:1525), so the
# offsets are ALL ZEROS and only the sizes carry the target -- and the zero list
# has the length of the TARGET, not of the source, which is the one thing a
# `shrink_to` gets wrong if it is written as a `shrink`.
def nn_shrink_to(+t: T.Tensor, +sizes: List<&2, U32>) -> T.Tensor:
  MX.mxw_shrink(t, nn_zeros(U32.to_nat(nn_len32(sizes))), sizes)

# --- `repeat` -- movement.py:590-604 ---------------------------------------
#
# `_align_left(self.shape, repeats)[0]` IS `self.shape` on this path, because
# `_pool` hands `repeat` exactly `ndim` counts: `[1]*len(noop)` ++ one per
# spatial dim. So the three shapes are three walks over ONE zip of
# `(shape, repeats)` and the `r == 1` arm -- which CPython writes three separate
# times -- is one `Bool.pick` per walk over the same pair.
def nn_rep.unsq.go(+ss: List<&2, U32>, +rr: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss rr:
    case s <> st r <> rt:
      nn_rep.unsq.go(st, rt, Bool.pick(List<&2, U32>, U32.is_eq(r, 1), List.append(&2, U32, acc, [s]),
        List.append(&2, U32, List.append(&2, U32, acc, [1]), [s])))
    case _ _: acc

def nn_rep.ex.go(+ss: List<&2, U32>, +rr: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss rr:
    case s <> st r <> rt:
      nn_rep.ex.go(st, rt, Bool.pick(List<&2, U32>, U32.is_eq(r, 1), List.append(&2, U32, acc, [s]),
        List.append(&2, U32, List.append(&2, U32, acc, [r]), [s])))
    case _ _: acc

def nn_rep.fin.go(+ss: List<&2, U32>, +rr: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss rr:
    case s <> st r <> rt: nn_rep.fin.go(st, rt, List.append(&2, U32, acc, [U32.mul(r, s)]))
    case _ _: acc

def nn_rep.unsq(ss: List<&2, U32>, rr: List<&2, U32>) -> List<&2, U32>: nn_rep.unsq.go(ss, rr, Nil{})

def nn_rep.ex(ss: List<&2, U32>, rr: List<&2, U32>) -> List<&2, U32>: nn_rep.ex.go(ss, rr, Nil{})

def nn_rep.fin(ss: List<&2, U32>, rr: List<&2, U32>) -> List<&2, U32>: nn_rep.fin.go(ss, rr, Nil{})

# THE EXPAND NODE. `repeat` needs one and `mixin/movement.bend` has NO `mxw_*`
# for it (its `EXPAND` readers at :635/:707 are `marg` readers, not builders),
# so it is `T.tn_mop` -- `tensor.bend:1699`, the movement builder whose `ADims`
# arm is `tn_mop.dims` and which `mxw_reshape` / `mxw_permute` / `mxw_pad` /
# `mxw_shrink` all wrap. `nn_ks` is `nn_dot`'s own `U32 -> O.Const` projection.
#
# **IT IS `_broadcast_to` (movement.py:128-146) AND NOT A BARE EXPAND.** CPython's
# `expand` (movement.py:149-162) IS `_broadcast_to`, and `_broadcast_to`'s marg is
# the LEFT-ADDED dims and THEN the dims of the source axes that were 1 and became
# BIGGER -- with a squeeze before and a permute after, so that the result's shape
# is the TARGET's. A marg that is the WHOLE TARGET is what `tuple(self.marg) + ps`
# (ops.py:397) reads as: THE TARGET CONCATENATED WITH THE SOURCE, which is a
# `1,64,4,58,4,58,1,64,1,58,1,58` where CPython's answer is `1,64,4,58,4,58`.
# `mixin/movement.bend`'s `mxw_bcast` IS that rule, and it is the SAME def
# `mixin/creation.bend`'s `cr_expand` calls, so the two sites cannot disagree.
def nn_expand(+t: T.Tensor, +ds: List<&2, U32>) -> T.Tensor: MX.mxw_bcast(t, ds)

def nn_repeat(+t: T.Tensor, +shp: List<&2, U32>, +reps: List<&2, U32>) -> T.Tensor:
  MX.mxw_reshape(nn_expand(MX.mxw_reshape(t, nn_rep.unsq(shp, reps)), nn_rep.ex(shp, reps)), nn_rep.fin(shp, reps))

# --- `_pool` -- movement.py:614-632, IN UPSTREAM'S ORDER --------------------
#
# NO ARITHMETIC IS SPELLED HERE. Every number is `mixin/movement.bend`'s.
#
# THE CHAIN IS UPSTREAM'S, LINE BY LINE, AND THE ORDER IS LOAD-BEARING:
#   movement.py:624  x = self.repeat(noop ++ [ceildiv(k*(i*f+d), i)])
#   movement.py:626  x = x.shrink_to(noop ++ [k*(i*f+d)])
#   movement.py:627  x = x.reshape(noop ++ flatten((k, i*f+d)))
#   movement.py:629  x = x.shrink_to(noop ++ flatten((k, o*s))).reshape(noop ++ flatten((k, o, s)))
#   movement.py:630  x = x.shrink_to(noop ++ flatten((k, o, 1))).reshape(noop ++ flatten((k, o)))
#   movement.py:632  return x.permute(range(nn), *[nn+2i+1], *[nn+2i])
#
# `noop` IS `[None] * (self.ndim - len(k_))` (movement.py:618) AND `None` MEANS
# "THIS AXIS IS NOT SHRUNK", so the shrink's target KEEPS THE SOURCE'S OWN SIZE
# on those axes. THE PORT'S TARGETS ARE SIZES, so the noop axes carry the
# SOURCE'S OWN DIMS -- which is `nn/pool.bend:145`'s `W4.lead` and NOT a list of
# ones. MEASURED: with ones there, the channel axis was shrunk from 3 to 1 and
# every shape in the chain was wrong.
#
# AND THE TWO SHRINK TARGETS ARE NOT THE SAME LIST. `movement.py:626` shrinks to
# `k*(i*f+d)` and `movement.py:627` reshapes to `(k, i*f+d)` -- THE DILATED SIZE
# WITHOUT THE `k *`. `mx_pool_kid` (movement.bend:316) IS `k*(i*f+d)`, so the
# reshape's target needs a SECOND number, and a reshape that is not
# size-preserving is a ValueError (movement.py:181).
def nn_pool.dil.go(+i: List<&2, U32>, +f: List<&2, U32>, +d: List<&2, U32>,
  +acc: List<&2, U32>) -> List<&2, U32>:
  match i f d:
    case a <> t b <> u c <> v: nn_pool.dil.go(t, u, v,
      List.append(&2, U32, acc, [U32.add(U32.mul(a, b), c)]))
    case _ _ _: acc

def nn_pool.dil(i: List<&2, U32>, f: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  nn_pool.dil.go(i, f, d, Nil{})

# `o * s` -- the STRIDED OUTPUT COUNT (movement.py:629), elementwise.
def nn_zipmul.go(+a: List<&2, U32>, +b: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match a b:
    case x <> at y <> bt: nn_zipmul.go(at, bt, List.append(&2, U32, acc, [U32.mul(x, y)]))
    case _ _: acc

def nn_zipmul(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  nn_zipmul.go(a, b, Nil{})

# `flatten((k, o, s) for ...)` -- movement.py:629 -- the THREE entries of each
# axis, FLATTENED, IN THE ORDER k, o, s. `nn_zipcat` (above) zips TWO lists, so
# a THREE-tuple needs its own walk: zipping the two-list zip with the third
# would pair `s0` with `k0` and `s1` with `o0`.
def nn_zipcat3.go(+a: List<&2, U32>, +b: List<&2, U32>, +c: List<&2, U32>,
  +acc: List<&2, U32>) -> List<&2, U32>:
  match a b c:
    case x <> at y <> bt z <> ct: nn_zipcat3.go(at, bt, ct,
      List.append(&2, U32, List.append(&2, U32, List.append(&2, U32, acc, [x]), [y]), [z]))
    case _ _ _: acc

def nn_zipcat3(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>) -> List<&2, U32>:
  nn_zipcat3.go(a, b, c, Nil{})

# THE NOOP AXES, AS THE SOURCE'S OWN DIMS.
def nn_pool.noop(+padded: List<&2, U32>, nn: U32) -> List<&2, U32>:
  List.take(&2, U32, padded, U32.to_nat(nn))

def nn_pool.go(+t: T.Tensor, +padded: List<&2, U32>, +k: List<&2, U32>,
  +s: List<&2, U32>, +d: List<&2, U32>, +nd: U32, +ni: U32) -> T.Tensor:
  +nn = MX.mx_dropn(nd, ni)
  +iv = MX.mx_i_(U32.to_nat(nd), U32.to_nat(ni), padded)
  +os = MX.mx_pool_out(iv, d, k, s)
  +fs = MX.mx_pool_f(os, s, iv, d)
  +sz = MX.mx_pool_kid(k, iv, fs, d)
  +dl = nn_pool.dil(iv, fs, d)
  +np = nn_pool.noop(padded, nn)
  +a = nn_repeat(t, padded, MX.mx_cat(nn_ones(nn), MX.mx_pool_rep.go(k, sz, iv, Nil{})))
  +b = nn_shrink_to(a, MX.mx_cat(np, sz))
  +c = MX.mxw_reshape(b, MX.mx_cat(np, nn_zipcat(k, dl)))
  +e = nn_shrink_to(c, MX.mx_cat(np, nn_zipcat(k, nn_zipmul(os, s))))
  +f2 = MX.mxw_reshape(e, MX.mx_cat(np, nn_zipcat3(k, os, s)))
  +g = nn_shrink_to(f2, MX.mx_cat(np, nn_zipcat3(k, os, nn_ones(ni))))
  +h = MX.mxw_reshape(g, MX.mx_cat(np, nn_zipcat(k, os)))
  MX.mxw_permute(h, MX.mx_pool_perm(nn, ni))

# --- `resolve_pool_pads` -- tinygrad/helpers.py:59 --------------------------
#
# THE `int` ARM IS THE `None` ARM. Python's `padding:int|Sequence[int]` is a sum
# type and a Bend `Maybe` is the port's spelling of one, so `None{}` IS "it was
# an int" and `v` is its value. `two` is `2*dims`, the length both non-int arms
# are measured against, and it is a PARAMETER because `conv2d` computes it once
# from `len(HW)` and every arm below reads it.
def nn_pads.dup(+ps: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> rest: nn_pads.dup(rest, List.append(&2, U32, List.append(&2, U32, acc, [p]), [p]))

def nn_pads.seq(+ps: List<&2, U32>, two: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(nn_len32(ps), two), ps,
    List.reverse(&2, U32, nn_pads.dup(ps, Nil{})))

def nn_pads(ps: Maybe<&2, List<&2, U32>>, v: U32, two: U32) -> List<&2, U32>:
  match ps:
    case None{}: H.make_tuple_rep(v, two)
    case Some{p}: nn_pads.seq(p, two)

# --- `flat_to_grouped` -- tinygrad/helpers.py:58 ---------------------------
#
# `tuple(zip(padding[-2::-2], padding[::-2]))`. BOTH slices step by two FROM THE
# END, so the pairs come out in REVERSE order of the flat list. That is
# CPython, not an accident: `resolve_pool_pads`'s third arm already REVERSES
# (`[p for p in padding for _ in range(2)][::-1]`) and the two reversals are
# what make `padding=(1,1)` land on `(h, w)` rather than `(w, h)`. A zip that
# runs off the end of an odd-length list truncates, and so does the `case _:`
# arm below.
def nn_pads.grp.go(+ps: List<&2, U32>, +acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ps:
    case a <> b <> rest:
      nn_pads.grp.go(rest, List.append(&2, List<&2, U32>, acc, [[a, b]]))
    case _: acc

def nn_pads.grp(ps: List<&2, U32>) -> List<&2, List<&2, U32>>:
  List.reverse(&2, List<&2, U32>, nn_pads.grp.go(ps, Nil{}))

# --- `_pad_constant(..., 0.0)` -- op.py:282-290 ------------------------------
#
# WITH `value == 0` THE WHOLE BODY IS ONE `PAD`. `:290` is `if value == 0:
# return base`, and `base` is `MovementMixin.pad(X, pads)` at :288. `has_neg` is
# FALSE for the pads `conv2d` builds -- `resolve_pool_pads` never invents a
# negative and a negative one would take the `shrink` arm at :286 -- so THAT arm
# is REFUSED BY `nn_cnv.pad` and named there rather than spelled.
#
# `pad`'s marg is `(x[0], s + x[0] + x[1])` (movement.py:189), so the SECOND
# half is an ABSOLUTE END INDEX and not a width, and the PADDED SHAPE is that
# second half. `nn_pad.his.go` is therefore the shape AND the marg in one walk:
# two walks over the same pairs are two chances to disagree about which axis
# `flat_to_grouped` reversed.
def nn_pad.his.go(+shp: List<&2, U32>, +pb: List<&2, U32>, +pa: List<&2, U32>,
  +acc: List<&2, U32>) -> List<&2, U32>:
  match shp pb pa:
    case s <> st b <> bt a <> at:
      nn_pad.his.go(st, bt, at, List.append(&2, U32, acc, [U32.add(U32.add(s, b), a)]))
    # THE BASE ARM RETURNED `Nil{}` AND DISCARDED ITS OWN ACCUMULATOR, so `conv2d`'s FIRST node
    # read EMPTY rather than wrong -- and `nn_cnv.build:735` fires it before a single UOp is
    # interned. MEASURED 2026-10-20: this line was the ONLY base arm in this file not returning
    # `acc` (`nn_ks.go:102`, `:150`, `:174`, `:204`, `nn_zipcat.go:467` and four more all do), out
    # of 4 `.go` walks and 37 `Nil{}` returns. **A base arm that drops the accumulator reads the
    # same as an empty fold, which is why THREE units were needed to find it.**
    case _ _ _: acc

def nn_pad.at(g: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, g, n), 0)

def nn_pad.pb.go(+gs: List<&2, List<&2, U32>>, +acc: List<&2, U32>) -> List<&2, U32>:
  match gs:
    case Nil{}: acc
    case g <> rest: nn_pad.pb.go(rest, List.append(&2, U32, acc, [nn_pad.at(g, 0n)]))

def nn_pad.pa.go(+gs: List<&2, List<&2, U32>>, +acc: List<&2, U32>) -> List<&2, U32>:
  match gs:
    case Nil{}: acc
    case g <> rest: nn_pad.pa.go(rest, List.append(&2, U32, acc, [nn_pad.at(g, 1n)]))

# --- the conv itself -- op.py:1591-1603 ------------------------------------
#
# `(bs,cin_), (cout,cin), HW = self.shape[:2], weight.shape[:2], weight.shape[2:]`
# is ONE tuple-unpack and it is read by every line below, so `nn_cnv.go` takes
# the two PROJECTED shapes and derives the rest once.
def nn_cnv.k(ws: List<&2, U32>) -> List<&2, U32>: List.drop(&2, U32, ws, 2n)

# `[0, 1, 3]` ++ `range(4, 4+ni)` ++ `[2]` ++ `range(4+ni, 4+2*ni)` -- the
# permute at :1582, which is `*[4+i for i in range(len(oyx))]` then
# `*[4+len(oyx)+i for i in range(len(HW))]` around the literal `0, 1, 3` and
# `2`. It is NOT `mx_pool_perm` (`mixin/movement.bend:392`): that one moves a
# window's `o` after its `k`, this one moves the product's reduce axes next to
# the channel axis so the `sum` at :1585 is contiguous.
def nn_cnv.perm(+ni: U32) -> List<&2, U32>:
  +mid = List.drop(&2, U32, nn_range(U32.add(4, U32.mul(2, ni))), 4n)
  List.concat(&2, U32, [[0, 1, 3], List.take(&2, U32, mid, U32.to_nat(ni)), [2],
    List.drop(&2, U32, mid, U32.to_nat(ni))])

# `[-1-i for i in range(1+len(oyx))]` -- :1585, resolved against the PRODUCT's
# rank. `T.tn_rop` (tensor.bend:1843) sorts the axis tuple, so the direction is
# a readability choice and not a correctness one; it is DESCENDING because that
# is what CPython's comprehension produces.
def nn_cnv.axes.go(+hs: List<&2, U32>, +t: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match hs:
    case Nil{}: acc
    case h <> rest: nn_cnv.axes.go(rest, t, List.append(&2, U32, acc, [U32.sub(t, U32.add(h, 1))]))

def nn_cnv.axes(t: U32, ni: U32) -> List<&2, U32>:
  nn_cnv.axes.go(nn_range(U32.add(ni, 1)), t, Nil{})

# `x.reshape(bs, groups, cin, 1, *oyx, *HW)` and
# `.expand(bs, groups, cin, rcout, *oyx, *HW)` -- :1582, as ONE def taking the
# fourth entry as a VALUE, because the two calls differ only in it (`1` then
# `rcout`). `rcout` is `cout//groups` and `NN.nn_groups` IS that division
# (`nn/__init__.bend:175`), unguarded, because tinygrad does not guard it
# either: `nn.Conv2d(1, 4, 3, groups=2)` has a weight of shape `(4, 0, 3, 3)`
# and a port that "fixed" it would answer `(4, 2, 3, 3)`.
# `weight.reshape(1, groups, rcout, *[1]*len(oyx), cin, *HW)` -- :1585.
def nn_cnv.wt(groups: U32, rcout: U32, ni: U32, cin: U32, k: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [[1, groups, rcout], nn_ones(ni), [cin], k])

# `(x * w).sum([...], keepdim=True).reshape(bs, cout, *oyx)` -- :1585-1586.
def nn_cnv.dot(+a: T.Tensor, +b: T.Tensor, +ni: U32, +ds: List<&2, U32>, dt: S.Dt) -> T.Tensor:
  +r = nn_sum(True{}, T.tn_mul(a, b), nn_cnv.axes(U32.add(4, U32.mul(2, ni)), ni))
  MX.mxw_reshape(M.mo_cast_t(r, dt), ds)

# --- `nn_conv2d` -- THE ENTRY, op.py:1591-1603 -----------------------------
#
# AND THE ONE REFUSAL THE WHOLE SECTION CARRIES, NAMED: NEGATIVE PADDING IS
# NOT EXPRESSIBLE. `_pad_constant` opens with
#     `has_neg = not all(resolve(p >= 0) for p in flatten(pX))` (op.py:285)
#     `X = self.shrink(...) if has_neg else self` (op.py:286)
#     `pads = tuple((smax(pB,0), smax(pA,0)) ...) if has_neg else pX` (:287)
# (op.py:285-287) and `padding` arrives here as `U32`, which has no negative.
# SO THE `has_neg` ARM IS UNREACHABLE RATHER THAN PORTED, and it is unreachable
# for a reason that is upstream's too: `nn.Conv2d`'s `padding` is an `int` or a
# tuple of non-negative ints, and `resolve_pool_pads` invents none. A caller that
# genuinely needs a shrink-then-pad passes the shrunk tensor and the positive
# pads, which is what the arm computes.
# ===========================================================================

# THE PADDED SHAPE, and it is ALSO the PAD node's `his` -- `pad`'s marg is
# `(pB, s + pB + pA)` (movement.py:189), so the padded shape and the marg's
# second half are THE SAME LIST and computing them twice is the chance for the
# two to drift. `nn_pad.his.go` is that one walk.
def nn_pad.his(+pb: List<&2, U32>, +pa: List<&2, U32>, +xs: List<&2, U32>, nn: U32) -> List<&2, U32>:
  +sp = List.drop(&2, U32, xs, U32.to_nat(U32.sub(nn_len32(xs), nn_len32(pb))))
  MX.mx_cat(List.take(&2, U32, xs, U32.to_nat(nn)), nn_pad.his.go(sp, pb, pa, Nil{}))

# `_pad_constant(((0,0),)*(self.ndim-len(HW)) + flat_to_grouped(padding_), 0.0)`
# -- :1580. The leading `nn` dims are `(0, 0)`, and `pad` turns `(0, 0)` into
# `(0, s + 0 + 0)` = `(0, s)`, which is why the leading `his` is the leading
# `s` and needs no walk.
def nn_conv.pad(+x: T.Tensor, +his: List<&2, U32>, +pb: List<&2, U32>, nn: U32) -> T.Tensor:
  MX.mxw_pad(x, MX.mx_cat(nn_zeros(U32.to_nat(nn)), pb), his)

def nn_cnv.pre(v: U32, bs: U32, groups: U32, cin: U32, p: List<&2, U32>, k: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [[bs, groups, cin, v], p, k])

def nn_cnv.out(bs: U32, cout: U32, p: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [[bs, cout], p])

# `bias.reshape(1, -1, *[1]*len(HW))` -- :1603. `-1` IS `cout` because
# `Conv2d.__init__` builds `Tensor.uniform(out_channels, ...)` (nn/__init__.py:107)
# and `nn/__init__.bend`'s `nn_convb` row already pins that shape.
def nn_cnv.bias(cout: U32, ni: U32) -> List<&2, U32>:
  List.concat(&2, U32, [[1, cout], nn_ones(ni)])

# `ret if bias is None else ret.add(bias.reshape(1, -1, *[1]*len(HW)))` -- :1603.
# The ADD is a BROADCAST add -- `(bs, cout, oy, ox)` against `(1, cout, 1, 1)` --
# and the fold answers its shape through the same `F.alu_ds` arm `nn_dot` and
# `nn_linear` already rely on (uop/fold.bend:999).
def nn_cnv.add.put(+ret: T.Tensor, +b: T.Tensor, ds: List<&2, U32>) -> T.Tensor:
  T.tn_add(ret, MX.mxw_reshape(b, ds))

def nn_cnv.add(+ret: T.Tensor, bias: Maybe<&2, T.Tensor>, ni: U32, cout: U32) -> Maybe<&2, T.Tensor>:
  match bias:
    case Some{b}: Some{nn_cnv.add.put(ret, b, nn_cnv.bias(cout, ni))}
    case None{}: Some{ret}

def nn_cnv.build(dt: Maybe<&2, S.Dt>, +x: T.Tensor, +w: T.Tensor, +xs: List<&2, U32>,
  +ws: List<&2, U32>, +groups: U32, +stride: U32, +dilation: U32, +pb: List<&2, U32>,
  +his: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  match dt:
    case Some{d}:
      +ni = nn_len32(nn_cnv.k(ws))
      +nd = nn_len32(xs)
      +k = nn_cnv.k(ws)
      +nn = MX.mx_dropn(nd, ni)
      +s_ = NN.nn_mt(stride, ni)
      +d_ = NN.nn_mt(dilation, ni)
      +os = MX.mx_pool_out(MX.mx_i_(U32.to_nat(nd), U32.to_nat(ni), his), d_, k, s_)
      +bs = nn_pad.at(xs, 0n)
      +cout = nn_pad.at(ws, 0n)
      +cin = nn_pad.at(ws, 1n)
      +rcout = NN.nn_groups(cout, groups)
      +p = nn_pool.go(nn_conv.pad(x, his, pb, nn), his, k, s_, d_, nd, ni)
      +e = nn_expand(MX.mxw_reshape(p, nn_cnv.pre(1, bs, groups, cin, os, k)),
        nn_cnv.pre(rcout, bs, groups, cin, os, k))
      Some{nn_cnv.dot(MX.mxw_permute(e, nn_cnv.perm(ni)),
        MX.mxw_reshape(w, nn_cnv.wt(groups, rcout, ni, cin, k)), ni,
        nn_cnv.out(bs, cout, os), d)}
    case None{}: None{}

def nn_conv2d.go(+x: T.Tensor, +w: T.Tensor, +xs: List<&2, U32>, +ws: List<&2, U32>,
  +groups: U32, +stride: U32, +dilation: U32, +pad_v: U32, +padding: Maybe<&2, List<&2, U32>>,
  bias: Maybe<&2, T.Tensor>) -> Maybe<&2, T.Tensor>:
  +ni = nn_len32(nn_cnv.k(ws))
  +nd = nn_len32(xs)
  +gs = nn_pads.grp(nn_pads(padding, pad_v, U32.mul(2, ni)))
  +pb = nn_pad.pb.go(gs, Nil{})
  +cout = nn_pad.at(ws, 0n)
  Maybe.bind(&2, T.Tensor, T.Tensor,
    nn_cnv.build(nn_dot.dts(T.tn_dtype(x), T.tn_dtype(w)), x, w, xs, ws, groups, stride, dilation,
      pb, nn_pad.his(pb, nn_pad.pa.go(gs, Nil{}), xs, MX.mx_dropn(nd, ni))),
    ret => nn_cnv.add(ret, bias, ni, cout))

def nn_conv2d(+x: T.Tensor, +w: T.Tensor, groups: U32, stride: U32, dilation: U32,
  pad_v: U32, padding: Maybe<&2, List<&2, U32>>, bias: Maybe<&2, T.Tensor>) -> Maybe<&2, T.Tensor>:
  Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(x),
    xs => Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(w),
      ws => nn_conv2d.go(x, w, xs, ws, groups, stride, dilation, pad_v, padding, bias)))

# ===========================================================================
# THE ROWS. Every expected value below is CPython's own answer, read off
# `tinygrad` in this repo's `.venv`, and the ONE witness for all 31 of them is
# `.agents/slop/nnrowsfix/nn-oracle.py` (re-runnable; its output is
# `.agents/slop/nnrowsfix/nn-oracle.rows`). A row that prints its expectation
# next to its answer cannot pass by having both be wrong, which is the whole
# point of printing the pair and not the answer alone.
#
# THE SPELLING IS THE PORT'S AND THE VALUE IS CPython's, and the two are
# separate questions. The port prints in three spellings and the expectations
# are written in those three:
#
#   SHAPE  `MX.mx_show` (mixin/movement.bend:878) is
#          `String.join(mx_shows.go(xs, Nil{}), ",")` -- the dims joined by a
#          comma, with NO parentheses. CPython's `Tensor.shape` is a TUPLE and
#          prints `(1, 4, 8, 8)`, so the shape rows' `want` is the DIMS in the
#          port's punctuation.
#   DTYPE  `E.ew_dtnm` (mixin/elementwise.bend:1033) is the `nm` field of
#          `S.Dt`, and `S.single()` (LAWS/spec.bend:741) is
#          `Dt{14, 32, CFloat{}, "f32"}`. CPython's own `DType.name` for
#          float32 is "f32" (tinygrad/dtype.py:136, `DType.new(14, 32, "f32",
#          'f')`); `float32` is the ALIAS (dtype.py:140), not the name. So the
#          port's spelling and CPython's NAME are the same string.
#   GRAPH  `MX.mxw_sig` (mixin/movement.bend:1380) is
#          `n=<count> op=Ops.<root> nsrc=<n> srcops=Ops.<a>|Ops.<b>`, and the
#          witness renders CPython's graph in that spelling. CPython's own
#          oracle format (`gates/mixin-op-oracle.py`) is
#          `n OP/nsrc OP/nsrc ...` -- a DIFFERENT format, so it cannot be a
#          `want`; the witness prints both, and the port's own
#          `M.mo_valsig.of` (mixin/op.bend:1255) prints the same value-carrying
#          list the witness prints, CONST payloads included.
#
# THE GRAPH WITNESS IS CPython's OWN GRAPH, AND THE FIXTURE IS WHY. The port's
# fixture `nn_row.t` is a BUFFER and a RESHAPE, with NO COPY: `mxw_buf`
# (mixin/movement.bend:1231) builds `Ops.BUFFER` directly. Upstream's numpy
# path builds the same node -- `Tensor.__init__` calls `_fromnp`
# (tinygrad/tensor.py:37-40), which is `UOp.new_buffer("NPY", x.size, ...)` --
# but ONLY while the requested device IS "NPY": `tinygrad/tensor.py:93` is
# `data if data.device is None or data.device == _device else
# data.copy_to_device(_device)`, so on the DEFAULT device the numpy buffer is
# COPIED and CPython's graph grows an `Ops.COPY` the port has no node for.
# MEASURED, both arms: the default device answers `n=7 ... srcops=Ops.COPY|
# Ops.STACK` and the "NPY" device answers `n=6 ... srcops=Ops.BUFFER|Ops.STACK`
# -- and the port's own `dbg_x_sig` row says `Ops.BUFFER`, so the "NPY" arm is
# the one that matches the fixture. A witness built on the default device would
# go red on a FIXTURE MISMATCH and call it a port defect.
#
# WHY NOT THE SPEC IR. `LAWS/spec.bend` is the SPECIFICATION IR: `Sp`
# (spec.bend:422) is one constructor per op in tinyspec.tex, a TREE, with the
# derived properties `Sp.shape` (:546) and `Sp.dtype` (:750). It has NO op-name
# function, NO arity function and NO node count, and it CANNOT have the last
# one: `mxw_sig`'s `n=` is `mxw_count` (mixin/movement.bend:1359) -- the
# COMPILED ARENA's toposort length -- and `Sp` is not that arena. Three
# measured reasons. (1) `Sp` is a tree and the arena is HASH-CONSED: the
# port's own fixture says "The two CONSTs HASH-CONS to one node"
# (uop/fold.bend:4435), so equal spec subtrees collapse to one arena node and a
# tree count over-counts. (2) `Sp` is the PRE-compilation form: `SpReshape`
# carries its target dims as a VALUE (`dst: List<&2, Sdim>`, spec.bend:436),
# while the arena's RESHAPE carries a STACK node (mixin/movement.bend:1234) --
# so the spec tree has no node where the arena has one. CONCRETE: the port's
# `dbg_x_sig` arena graph is 6 nodes (CONST(size) BUFFER CONST(2) CONST(3)
# STACK RESHAPE) and the spec-level description of the same computation is
# `SpReshape{SpBuffer{6,...}, SpInvalid{}, [SN{2n},SN{3n}]}` -- two `Sp` nodes
# and no node at all for the two CONSTs or the STACK. (3) spec.bend's own
# header says it (spec.bend:9-14): "The compilation IR (tinygrad/uop/ops.py) is
# a cyclic hash-consed graph in an arena ... That IR cannot be a pure tree, so
# the laws cannot reach it." WHAT WOULD HAVE TO BE ADDED: `Sp.opname` and
# `Sp.srcs` (one arm per constructor) would give `op=`, `nsrc=` and `srcops=`,
# and then `n=` would still have to come from somewhere that models the
# hash-consed arena -- which is the compilation IR, out of reach by that
# file's own design. A spec-IR `want` could therefore only be a DIFFERENT
# signature (no `n=`), and `mxw_sig` always prints `n=`, so the row could not
# use it. THE WITNESS IS CPython's graph, which is a DIFFERENT IMPLEMENTATION
# of the same computation and is independent of the port's fold.
#
# TWO OF THE FIVE GRAPH ROWS ARE THE SAME STRING, AND THAT IS NOT A DEFECT.
# `dbg_dot_sig` and `fold_cc_sig` both answer
# `n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE`, on BOTH sides, because they
# ARE the same computation: upstream's `dot` IS a reshape-transpose-multiply-
# sum-cast (`tinygrad/mixin/op.py:367-392`: `x.reshape(...)`, `w.reshape(...)
# .transpose(...)`, `(x*w).sum(-1)`, `.cast(...)`), and the port's `fold_cc` is
# that same chain spelled out of the port's own `reshape`/`permute`/`mul`/
# `sum`/`cast`. So the two rows differ in the CODE PATH they exercise (the
# port's `nn_dot` against the port's `nn_sum`+`tn_mul`+`mo_cast_t`) and not in
# the graph they produce, and a GRAPH SIGNATURE cannot tell them apart. The
# other three are distinct: `fold_xw_sig` is `n=18 ... Ops.MUL`, `dbg_x_sig` is
# `n=6 ... Ops.BUFFER|Ops.STACK` and `dbg_conv_sig` is `n=57`.
#
# THE FIXTURE IS `mixin/movement.bend`'s (`mxw_base`, movement.bend:1724): a
# BUFFER plus a RESHAPE. A BUFFER ALONE IS UNUSABLE HERE -- `fold.shape` does not
# answer a BUFFER, and every identity test in `mxw_reshape`/`mxw_pad`/
# `mxw_shrink` reads its source's shape.
# ===========================================================================

def nn_row.buf(+ar: O.Arena, slot: U32, size: U32) -> T.Tensor: MX.mxw_buf(ar, slot, size)

def nn_row.t(ns: List<&2, U32>, slot: U32, size: U32) -> T.Tensor:
  MX.mxw_reshape(MX.mxw_buf(O.Arena.empty(), slot, size), ns)

# THE SHAPE OF A BUILT TENSOR, printed as CPython prints it: `1,3,34,34`.
#
# IT READS `nn_shape` -- `M.mo_dims` over the real fold -- AND NOT
# `MX.mxw_dims_of` (`mixin/movement.bend:1332`). MEASURED: on the 19-node `dot`
# graph `mxw_dims_of` answered the EMPTY list and on the 37-node `conv2d` graph
# it answered `1,8` -- a truncation, not a shape. `mxw_dims_of` is a FUELLED
# WALK over a movement chain (`mxw_shape_of`, :1321) and this file's graphs are
# one merge and one elementwise tower deep, which is past what its fuel covers.
# A row that prints a truncated shape reads as a wrong port, so the row reads
# the fold the layer itself reads.
def nn_row.shp.of(+t: T.Tensor) -> String:
  MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(t), Nil{}))

def nn_row.shp(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: nn_row.shp.of(t)
    case None{}: "NONE"

def nn_row.line(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, " got=", got, " want=", want]))

# `Tensor.relu` -- elementwise.py:674. `(1, 4, 8, 8)` in, `(1, 4, 8, 8)` out.
# The `want` is CPython's dims in the PORT's shape spelling (`mx_show`, no
# parentheses): CPython's `Tensor.relu().shape` is the tuple `(1, 4, 8, 8)`.
def nn_row_relu() -> IO(Unit):
  nn_row.line("relu", nn_row.shp(Some{nn_relu(nn_row.t([1, 4, 8, 8], 0, 256))}), "1,4,8,8")

# `Tensor.dot` -- op.py:367. `x(2,3) . w(3,4)` -> `(2, 4)`.
def nn_row_dot() -> IO(Unit):
  nn_row.line("dot_2d", nn_row.shp(nn_dot(nn_row.t([2, 3], 0, 6), nn_row.t([3, 4], 1, 12))), "2,4")

# THE 1-D WEIGHT ARM of `dot` (`axis_w = 0`, op.py:383): `x(2,3) . w(3)` -> `(2,)`.
def nn_row_dot1() -> IO(Unit):
  nn_row.line("dot_1d", nn_row.shp(nn_dot(nn_row.t([2, 3], 0, 6), nn_row.t([3], 1, 3))), "2")

# `nn.Linear.__call__` -- nn/__init__.py:180. `x(2,576)`, `weight(10,576)`, `bias(10)`.
def nn_row_linear() -> IO(Unit):
  nn_row.line("linear",
    nn_row.shp(nn_linear(nn_row.t([2, 576], 0, 1152), nn_row.t([10, 576], 1, 5760), Some{nn_row.t([10], 2, 10)})),
    "2,10")

# THE `bias is None` ARM of op.py:1269 -- CPython's `nn.Linear(576, 10, bias=False)`.
def nn_row_linear_nb() -> IO(Unit):
  nn_row.line("linear_nobias",
    nn_row.shp(nn_linear(nn_row.t([2, 576], 0, 1152), nn_row.t([10, 576], 1, 5760), None{})), "2,10")

# `Tensor.conv2d` -- op.py:1562, `x(1,3,32,32)`, `weight(8,3,3,3)`.
#   padding=1 (the 'same' a ResNet block uses) -> (1, 8, 32, 32)
#   padding=0                            -> (1, 8, 30, 30)
#   padding=1, stride=2                   -> (1, 8, 16, 16)
#
# THE EXPECTATIONS ARE CPython's, AND EVERY ONE OF THEM WAS READ OFF CPython's
# OWN `tinygrad` IN THIS REPO'S `.venv` (`Tensor.zeros(1,3,32,32).conv2d(
# Tensor.zeros(8,3,3,3), padding=...).shape`), WHICH IS UPSTREAM'S LINE FOR
# LINE: op.py:1591-1603. `op.py:1596` is the pad+`_pool`, `op.py:1598` the
# expand+permute, `op.py:1601-1602` the multiply+sum, `op.py:1602`'s
# `.reshape(bs, cout, *oyx)` the output.
def nn_row_conv(+pad_v: U32, +stride: U32, want: String) -> IO(Unit):
  nn_row.line(String.concat(["conv_p", U32.show(pad_v), "_s", U32.show(stride)]),
    nn_row.shp(nn_conv2d(nn_row.t([1, 3, 32, 32], 0, 3072), nn_row.t([8, 3, 3, 3], 1, 216),
      1, stride, 1, pad_v, None{}, None{})), want)

# `padding=(1, 2)` -- the `resolve_pool_pads` sequence arm (helpers.py:59-62,
# `tinygrad/helpers.py` -- NOT `tinygrad/mixin/helpers.py`, WHICH DOES NOT EXIST),
# whose REVERSAL plus `flat_to_grouped`'s is what puts (1,1) on the FIRST axis.
# `helpers.py:62`'s `[p for p in padding for _ in range(2)][::-1]` answers
# (2,2,1,1) and `helpers.py:58`'s `flat_to_grouped` answers ((1,1),(2,2)), so
# the pad is (1,1) on the HEIGHT and (2,2) on the WIDTH: (1,3,32,32) becomes
# (1,3,34,36) and the output is (1, 8, 32, 34).
def nn_row_conv_t() -> IO(Unit):
  nn_row.line("conv_seq",
    nn_row.shp(nn_conv2d(nn_row.t([1, 3, 32, 32], 0, 3072), nn_row.t([8, 3, 3, 3], 1, 216),
      1, 1, 1, 0, Some{[1, 2]}, None{})), "1,8,32,34")

# THE BIAS ARM of op.py:1603 -- `bias(8,)` reshaped to `(1, 8, 1, 1)`.
# `op.py:1603`'s `ret.add(bias.reshape(1, -1, *[1] * len(HW)))` is a BROADCAST
# add, so the shape is the conv's own: (1, 8, 32, 32).
def nn_row_conv_bias() -> IO(Unit):
  nn_row.line("conv_bias",
    nn_row.shp(nn_conv2d(nn_row.t([1, 3, 32, 32], 0, 3072), nn_row.t([8, 3, 3, 3], 1, 216),
      1, 1, 1, 1, None{}, Some{nn_row.t([8], 2, 8)})), "1,8,32,32")

# THE PADDING ARITHMETIC, printed against CPython's own `resolve_pool_pads` /
# `flat_to_grouped` reading. `nn_pads` answers the FLAT list `resolve_pool_pads`
# returns (helpers.py:62) and `nn_pad.grp`/`nn_pads.grp` answers
# `flat_to_grouped` (helpers.py:58).
def nn_row_pads() -> IO(Unit):
  do IO<Unit>:
    nn_row.line("pads_int1", MX.mx_show(nn_pads(None{}, 1, 4)), "1,1,1,1")
    nn_row.line("pads_seq12", MX.mx_show(nn_pads(Some{[1, 2]}, 0, 4)), "2,2,1,1")
    nn_row.line("pads_seq11", MX.mx_show(nn_pads(Some{[1, 1]}, 0, 4)), "1,1,1,1")

def nn_row_shape() -> IO(Unit):
  nn_row.line("shape_x", nn_row.shp.of(nn_row.t([1, 3, 32, 32], 0, 3072)), "1,3,32,32")

# WHERE THE `Maybe` GOES. `nn_shape` is `nn_u32(mo_dims(...))` and `nn_dot.dts`
# is `least_upper_dtypes` over the two `tn_dtype`s; a `None` from either is a
# refusal and a refusal with no name is not a result, so both are printed.
def nn_row_shp2(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{v}: MX.mx_show(v)
    case None{}: "NONE"

def nn_row_dt(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{v}: E.ew_dtnm(v)
    case None{}: "NONE"

def nn_row_where() -> IO(Unit):
  +x = nn_row.t([2, 3], 0, 6)
  +w = nn_row.t([3, 4], 1, 12)
  do IO<Unit>:
    nn_row.line("where_xshape", nn_row_shp2(nn_shape(x)), "2,3")
    nn_row.line("where_wshape", nn_row_shp2(nn_shape(w)), "3,4")
    nn_row.line("where_xdt", nn_row_dt(T.tn_dtype(x)), "f32")
    nn_row.line("where_wdt", nn_row_dt(T.tn_dtype(w)), "f32")
    nn_row.line("where_dts", nn_row_dt(nn_dot.dts(T.tn_dtype(x), T.tn_dtype(w))), "f32")

# THE GRAPH, not just the shape: `mxw_sig` (mixin/movement.bend:1377) prints
# node count, root op and the SOURCE OP SEQUENCE in one string, so a row cannot
# drop one of the three.
def nn_row.sig.of(+t: T.Tensor) -> String: MX.mxw_sig(T.Tensor.ar(t), T.Tensor.u(t))

def nn_row.sig(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: nn_row.sig.of(t)
    case None{}: "NONE"

def nn_row_dbg() -> IO(Unit):
  +x = nn_row.t([2, 3], 0, 6)
  +w = nn_row.t([3, 4], 1, 12)
  +c = nn_conv2d(nn_row.t([1, 3, 32, 32], 0, 3072), nn_row.t([8, 3, 3, 3], 1, 216),
    1, 1, 1, 1, None{}, None{})
  do IO<Unit>:
    nn_row.line("dbg_dot_sig", nn_row.sig(nn_dot(x, w)), "n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE")
    nn_row.line("dbg_conv_sig", nn_row.sig(c), "n=57 op=Ops.RESHAPE nsrc=2 srcops=Ops.RESHAPE|Ops.STACK")
    nn_row.line("dbg_x_sig", MX.mxw_sig(T.Tensor.ar(x), T.Tensor.u(x)), "n=6 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.STACK")

# THE REDUCE CHAIN, LAYER BY LAYER, against CPython's own shapes. `fold.shape`
# is what `nn_shape` reads, and these five rows are the depths at which the
# chain is built -- so when a later row reads empty, this one says where.
def nn_row_fold() -> IO(Unit):
  +x = nn_row.t([2, 3], 0, 6)
  +w = nn_row.t([3, 4], 1, 12)
  +xr = MX.mxw_reshape(x, [2, 1, 3])
  +wr = MX.mxw_permute(MX.mxw_reshape(w, [1, 3, 4]), [0, 2, 1])
  +xw = T.tn_mul(xr, wr)
  +sm = nn_sum(False{}, xw, [2])
  +cc = M.mo_cast_t(sm, S.single())
  +smk = nn_sum(True{}, xw, [2])
  do IO<Unit>:
    nn_row.line("fold_base", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(x), Nil{})), "2,3")
    nn_row.line("fold_xr", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(xr), Nil{})), "2,1,3")
    nn_row.line("fold_wr", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(wr), Nil{})), "1,4,3")
    nn_row.line("fold_xw", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(xw), Nil{})), "2,4,3")
    nn_row.line("fold_sm", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(sm), Nil{})), "2,4")
    # `sum(axis=[2], keepdim=True)` over (2,4,3) is (2,4,1): reduce.py:18's
    # `tuple(1 if i in axis else s for i,s in enumerate(self.shape))` puts the
    # ONE AT THE REDUCED INDEX. THE OLD EXPECTATION "2,1,3" WAS WRONG: it is
    # CPython's answer for axis [1], and it is ALSO what the port's
    # `mixin/op.bend:781 mo_keep_ds` answers for axis [1] -- because
    # `mixin/op.bend:316 mo_at` counts the index FROM THE END, so the port
    # answers the axis [1] target for every axis.
    nn_row.line("fold_smk", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(smk), Nil{})), "2,4,1")
    nn_row.line("fold_cc", MX.mx_show(Maybe.default(&2, List<&2, U32>, nn_shape(cc), Nil{})), "2,4")
    nn_row.line("fold_cc_sig", MX.mxw_sig(T.Tensor.ar(cc), T.Tensor.u(cc)), "n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE")
    nn_row.line("fold_xw_sig", MX.mxw_sig(T.Tensor.ar(xw), T.Tensor.u(xw)), "n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE|Ops.PERMUTE")

def main() -> IO(Unit):
  do IO<Unit>:
    nn_row_fold()
    nn_row_dbg()
    nn_row_where()
    nn_row_pads()
    nn_row_shape()
    nn_row_relu()
    nn_row_dot()
    nn_row_dot1()
    nn_row_linear()
    nn_row_linear_nb()
    nn_row_conv(1, 1, "1,8,32,32")
    nn_row_conv(0, 1, "1,8,30,30")
    nn_row_conv(1, 2, "1,8,16,16")
    nn_row_conv_t()
    nn_row_conv_bias()
