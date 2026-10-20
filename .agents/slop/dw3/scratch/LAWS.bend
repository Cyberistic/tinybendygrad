# LAWS.bend -- tinybendygrad's specification.
#
# This file is the contract between tinygrad's behaviour and the Bend port. It
# states, in Bend's law syntax, the claims that spec/tinyspec.tex makes in prose
# and in LaTeX tables. `bend PROOF.bend` is the gate: it prints SOME PROOFS FAIL
# while any law here is open or false, and ALL PROOFS CHECK once every law holds.
#
# HOW TO READ THIS FILE. Each law names the paragraph of tinyspec.tex it comes
# from, in its comment. A law is a claim about the pure spec IR in LAWS/spec.bend
# -- the tree of ops, with the spec's five derived properties as total functions
# over it. The compilation IR (uop/ops.py) is a cyclic hash-consed graph in an
# arena and cannot be a pure tree, so it is not covered here; see
# `.agents/slop/notes/bend2-constraints.md` section 6 (line 454), which is where
# that decision is actually written down. `PORTING.md`, cited here before, DOES
# NOT EXIST in this repo -- it is prep-work item 3 of
# `.agents/slop/plans/00-master-plan.md` and was never written. What these laws
# pin is the semantics every IR must agree on, which
# is precisely what the spec states.
#
# WHAT IS DELIBERATELY NOT HERE, and why:
#
#   * Anything about F32 arithmetic. Bend's guide is blunt: "F32 is
#     axiomatic: nothing about floating point can be proven." A law about
#     `exp` or `mul` would be a claim the checker cannot decide, so stating one
#     would be theatre. The spec's transcendental rows are therefore carried as
#     the op names they are and their decomposition (log2/exp2/Mul above), which
#     IS provable, and the numerics are pinned by the original pytest suite
#     instead.
#
#   * The 20 Codegen Ops. tinyspec says of them: "these ops are not part of the
#     core specification and are subject to change."
#
#   * The `min_max` column. It is interval arithmetic over the same ops, and it
#     is exact only where tinygrad says it is; proving it would need the float
#     machinery above. It is pinned by test/null/test_uop_vmin_vmax.py (55
#     tests) instead.
#
# A law here is not decoration. If the port changes a shape rule, a broadcast
# rule or a decomposition, the checker catches it here rather than a reviewer
# catching it three weeks later in a schedule diff.

import Base
import ./LAWS/spec.bend as S
import ./LAWS/alu.bend as A

# THE FOLDS ARE TOTAL. `Sp.shape` and `Sp.dtype` take the node and nothing
# else, so no law below quantifies a budget and no law can degrade to `None ==
# None` for want of one. That is the whole point of dropping the fuel: every
# claim here is a claim about a total function, and a law that holds only
# because both sides are the same opaque constant is not a proof.

# ===========================================================================
# I. The spec's constraints become premises.
#
# tinyspec states validity conditions on ops -- "prod s_k = prod s'_k" for
# Reshape, "buf.shape = val.shape" for Store -- as things a well-formed graph
# must satisfy. A Bend law is universally quantified, so it cannot carry an
# assumption inline; the condition enters as a premise carrying its own proof.
# ===========================================================================

# tinyspec Reshape: "Reinterpret in row-major order. prod s_k = prod s'_k."
#
# The premise is the spec's own constraint. The conclusion is the interesting
# half: a reshape that preserves the element count PRESERVES the element count,
# so the spec's constraint is not merely necessary but sufficient.
law reshape_preserves_numel:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(t) : Nat}
  {numel_of(S.SpReshape{t, S.SpInvalid{}, dst}) == numel_of(t) : Nat}

# The same claim from the other side: a reshape's element count IS the new
# shape's, whether or not the spec's constraint holds. Together the two say the
# count follows `dst` and nothing else.
law reshape_numel_is_the_new_shape:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  {numel_of(S.SpReshape{t, S.SpInvalid{}, dst}) == prod_of(dst) : Nat}

# ===========================================================================
# II. The spec's derived properties, stated as laws.
#
# tinyspec's shape column, read off the clauses: every movement op passes the
# shape through except Reshape, Expand, Pad, Shrink, Index, Stack and Bitcast,
# which have their own clause. The laws below are the ones that constrain the
# ELEMENT COUNT, because that is the invariant the whole scheduler rests on: a
# view may not change how many elements a tensor has.
# ===========================================================================

# Permute and Flip reorder and mirror; neither adds or removes an element.
law permute_preserves_numel:
  for +t: S.Sp
  for +order: List<&2, Nat>
  {numel_of(S.SpPermute{t, order}) == numel_of(t) : Nat}

law flip_preserves_numel:
  for +t: S.Sp
  for +flags: List<&2, Bool>
  {numel_of(S.SpFlip{t, flags}) == numel_of(t) : Nat}

# Pad grows the shape and fills the new region with Invalid, so the element
# count grows by exactly the amount the new shape says -- not by "whatever the
# fill pattern happens to be".
law pad_numel_is_the_new_shape:
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {prod_of(size) == numel_of(S.SpPad{t, off, size}) : Nat}

# Shrink narrows the shape, and the element count follows the narrowed shape.
law shrink_numel_is_the_new_shape:
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {prod_of(size) == numel_of(S.SpShrink{t, off, size}) : Nat}

# Pad and Shrink are inverse in EXTENT: shrinking back out of a pad returns
# the original element count. This is the spec's "Inverse of Pad" for Shrink.
law pad_shrink_round_trip:
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  for +premise: {prod_of(size) == numel_of(t) : Nat}
  {numel_of(S.SpShrink{S.SpPad{t, off, size}, off, size}) == numel_of(t) : Nat}

# Stack adds a LEADING axis: "Join along a newly created leading axis", and an
# empty Stack has no shape at all -- so this is stated for a non-empty Stack,
# whose leading axis is 1 + the number of the rest.
#
# NOT VACUOUS. Under the fuel the fold answered None for every operand, so the
# premise had no witness and the law held only because its hypothesis was
# empty. The fold is total now, `t = SpBuffer{4, ...}` with `bs = [4]` is a
# witness, and the conclusion is NOT the premise restated: it says the count is
# the operand count times the head's count, which is the spec's sentence.
#
# The premise names the operand's shape because the checker cannot: without it
# both sides sit on `Sp.shape(t)` behind different closures, and no `match`
# opens a call's result (`.agents/slop/notes/bend2-constraints.md` rule 1.2 and
# its worked example near line 4352). Nothing is lost: a shapeless
# operand counts 0, and so does a Stack of shapeless operands.
law stack_numel_is_the_leading_axis_times_the_operands:
  for +t: S.Sp
  for +rest: List<&2, S.Sp>
  for +bs: S.Shape
  for +premise: {shape_of(t) == Some{bs} : Maybe<&2, S.Shape>}
  {numel_of(S.SpStack{t <> rest}) == (Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), numel_of(t)) : Nat) : Nat}

# Reduce "remove axes": the count is the original divided by the product of the
# axes that were removed. `(4,5,6)` reduced over its first axis is `(5,6)`, so
# 30, not 120. `drop_n` returns the axes that remain, so the multiplier is
# `List.take(dims, n)`. `prod(drop_n(...))` is the square of the surviving
# count: false if drop drops `n` (16==4, 900==120) and false when it dropped
# `n+1` (1==4, 36==120). `take(n+1)` only matched that off-by-one.
# `.agents/slop/ind/dropn-measure.bend`.
law reduce_numel_divides_by_the_reduced_axes:
  for +t: S.Sp
  for +n: Nat
  {Nat.mul(reduced_numel(t, n), prod_of(List.take(&2, S.Sdim, dims_of(t), n))) == numel_of(t) : Nat}

# ===========================================================================
# III. Broadcast -- tinyspec: "right-align shapes, element-wise max; each axis
# must be equal or 1".
#
# The previous law here claimed the result took the LEFT operand's shape. That
# is refuted by the rule itself: broadcasting (1,3) with (2,3) gives (2,3), which
# is neither operand.
#
# The count form `max(numel(add), numel(b)) == numel(add)` is false as
# quantified, measured on the live spec and on tinygrad:
#   spec (SS,5)+(3,7) is 21==0; (5,0)+(3,) is 3==0; shapeless+(3,3) is 9==0
#   tinygrad (2,0)+(1,1) is a valid broadcast of shape (2,0), numel 0 < 1
#   tinygrad (2,3)+(3,3) is not a broadcast at all (neither axis is 1)
# What tinyspec and tinygrad agree on, once a 1 is allowed to broadcast to 0,
# is the axis rule: equal-length concrete shapes, each axis is the non-1 size.
# Equal length is the alignment boundary (the spec zips from the head; tinygrad
# right-aligns; they coincide exactly when the ranks match). Symbolic axes are
# excluded because `dim_of(SS)` is 0, which is not tinygrad's symbolic shape.
# ===========================================================================

law broadcast_is_elementwise_max:
  for +a: S.Sp
  for +b: S.Sp
  for +sa: S.Shape
  for +sb: S.Shape
  for +pa: {shape_of(a) == Some{sa} : Maybe<&2, S.Shape>}
  for +pb: {shape_of(b) == Some{sb} : Maybe<&2, S.Shape>}
  for same: S.SameLen(S.Shape.to_dims(sa), S.Shape.to_dims(sb))
  for ca: S.AllSN(S.Shape.to_dims(sa))
  for cb: S.AllSN(S.Shape.to_dims(sb))
  {shape_of(S.SpAdd{a, b}) == Some{S.Shape.of(S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb)))} : Maybe<&2, S.Shape>}

# ===========================================================================
# IV. The decomposed elementwise ops.
#
# tinyspec's "Decomposed elementwise ops" table. Each of these is DEFINED in
# terms of the primitives, so each is a definitional equality and the checker
# proves it by reflexivity. If the port ever changes one of these, a law fails
# immediately and names the op -- which is the entire value of writing the
# table down at all.
# ===========================================================================

law neg_is_mul_by_minus_one:
  for +a: S.Sp
  {A.neg(a) == S.SpMul{a, A.one()} : S.Sp}

law sub_is_add_of_neg:
  for +a: S.Sp
  for +b: S.Sp
  {A.sub(a, b) == S.SpAdd{a, A.neg(b)} : S.Sp}

law div_is_mul_by_recip:
  for +a: S.Sp
  for +b: S.Sp
  {A.div(a, b) == S.SpMul{a, S.SpRecip{b}} : S.Sp}

law cmp_gt_is_cmp_lt_swapped:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_gt(a, b) == S.SpCmpLt{b, a} : S.Sp}

law cmp_ge_is_ne_of_cmp_lt:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_ge(a, b) == S.SpCmpNe{S.SpCmpLt{a, b}, A.one()} : S.Sp}

law cmp_le_is_ne_of_cmp_lt_swapped:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_le(a, b) == S.SpCmpNe{S.SpCmpLt{b, a}, A.one()} : S.Sp}

law cmp_eq_is_double_neg:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_eq(a, b) == S.SpCmpNe{S.SpCmpNe{a, b}, A.one()} : S.Sp}

law not_is_ne_one:
  for +a: S.Sp
  {A.logical_not(a) == S.SpCmpNe{a, A.one()} : S.Sp}

law mulacc_is_add_of_mul:
  for +a: S.Sp
  for +b: S.Sp
  for +c: S.Sp
  {A.mulacc(a, b, c) == S.SpAdd{S.SpMul{a, b}, c} : S.Sp}

# ===========================================================================
# V. The dtype column, for the ops where it is not simply src[0].
#
# tinyspec: comparisons are bool; Where takes src[1]; Range is index; Store and
# Call are void; Binary is uint8.
#
# Every law here reads the dtype fold at a node that answers without
# descending, so each is a single arm of `Sp.dtype` rather than a fold.
# ===========================================================================

law comparison_is_bool:
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpCmpLt{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law comparison_ne_is_bool:
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpCmpNe{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law where_takes_the_second_operand_dtype:
  for p: S.Sp
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpWhere{p, a, b}) == dtype_of(b) : Maybe<&2, S.Dt>}

law store_is_void:
  for buf: S.Sp
  for val: S.Sp
  for gate: Maybe<&2, S.Sp>
  {dtype_of(S.SpStore{buf, val, gate}) == none_of() : Maybe<&2, S.Dt>}

law call_is_void:
  for body: S.Sp
  for args: List<&2, S.Sp>
  {dtype_of(S.SpCall{body, args}) == none_of() : Maybe<&2, S.Dt>}

law range_is_index:
  for bound: S.Sp
  {dtype_of(S.SpRange{bound}) == some_of(S.index()) : Maybe<&2, S.Dt>}

law binary_is_uint8:
  for size: Nat
  {dtype_of(S.SpBinary{size}) == some_of(S.uint8()) : Maybe<&2, S.Dt>}

# The marker ops are "identity on data": both properties pass through.
law detach_preserves_dtype:
  for +a: S.Sp
  {dtype_of(S.SpDetach{a}) == dtype_of(a) : Maybe<&2, S.Dt>}

law detach_preserves_numel:
  for +a: S.Sp
  {numel_of(S.SpDetach{a}) == numel_of(a) : Nat}

# ===========================================================================
# VI. The elementwise column: "all inputs same shape, output same shape".
#
# This is the claim the schedule's fusion decisions rest on, so it is worth
# stating rather than leaving in a table caption.
# ===========================================================================

law add_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpAdd{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

law mul_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpMul{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

law max_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpMax{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

# ===========================================================================
# VII. The Store invariant -- tinyspec: "buf.shape = val.shape".
#
# VACUOUS BY CONSTRUCTION, and it was before the folds were fuelled: the
# conclusion restates the premise verbatim, so the proof is the premise and the
# law can never fail. It is kept because the spec states the constraint, but it
# pins no behaviour. See .agents/TODO.md, "Audit against tinyspec".
# ===========================================================================

law store_matches_its_buffer:
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  for +premise: {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}
  {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}

# ===========================================================================
# VIII. The shape algebra's own laws.
#
# These are about `zip_max` and `Shape.max_dim` directly, with no `Sp` in
# sight. They matter because the elementwise laws in section VI are stuck on
# exactly this function, and a law about the algebra is the honest way to say
# what it does rather than leaving it implied by a comment.
#
# `max_dim` is idempotent: broadcasting a dim against itself changes nothing.
# It is the leaf fact an induction over a dim list needs, and the only part of
# `Shape.max_dim` that is not a case split in the source.
# ===========================================================================

law max_dim_idempotent:
  for +x: S.Sdim
  {S.Shape.max_dim(x, x) == x : S.Sdim}

# `zip_max` is idempotent too, and this is the law the three elementwise laws
# need: each of them carries the premise that the two shapes are EQUAL, and
# this is what equal shapes do. OPEN -- PROOF.bend records why the induction
# step does not close, and why that is a limit of the rewriter rather than of
# the claim.
law zip_max_idempotent:
  for +ds: List<&2, S.Sdim>
  {S.zip_max(ds, ds) == ds : List<&2, S.Sdim>}

# ===========================================================================
# Helpers. These are defs, not laws: they exist so each law above reads like
# the sentence it came from. `for +x` marks them reusable, which is what a
# premise and its subject have to be to appear in more than one place.
#
# `dims_of` is gone: `S.drop_n` is spec.bend's, and the old `dims_of` existed
# only to open a shape the laws never ask for by name.
# ===========================================================================

# The folds, total: a node in, a shape or a dtype out.
def shape_of(s: S.Sp) -> Maybe<&2, S.Shape>:
  S.Sp.shape(s)

def dtype_of(s: S.Sp) -> Maybe<&2, S.Dt>:
  S.Sp.dtype(s)

# numel is not a fold of its own in spec.bend: it is the product of the shape's
# dims, and a shapeless op has no element count, so 0 is the only honest total
# answer for one.
def numel_of(s: S.Sp) -> Nat:
  S.dims_prod(S.Sp.shape(s))

def some_of(d: S.Dt) -> Maybe<&2, S.Dt>:
  Some{d}

def none_of() -> Maybe<&2, S.Dt>:
  None{}

# Forwards spec.bend's `drop_n`, which is `List.drop`: the suffix that remains.
# The reduce law does not call this. Its multiplier is the removed prefix.
def drop_n(ds: List<&2, S.Sdim>, n: Nat) -> List<&2, S.Sdim>:
  S.drop_n(ds, n)

def prod_of(ds: List<&2, S.Sdim>) -> Nat:
  S.prod(ds)

def reduced_numel(t: S.Sp, n: Nat) -> Nat:
  numel_of(S.SpReduce{t, Nil{}, S.SpInvalid{}, n})

def dims_of.go(m: Maybe<&2, S.Shape>) -> List<&2, S.Sdim>:
  match m:
    case Some{sh}: S.Shape.to_dims(sh)
    case None{}: Nil{}

def dims_of(s: S.Sp) -> List<&2, S.Sdim>:
  dims_of.go(shape_of(s))
