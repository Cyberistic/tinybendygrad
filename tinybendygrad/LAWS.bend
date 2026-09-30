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
# arena and cannot be a pure tree, so it is not covered here; see PORTING.md
# section 6. What these laws pin is the semantics every IR must agree on, which
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

# THE DEPTH BUDGET. Both folds are fuelled: `Sp.shape` and `Sp.dtype` take a
# depth, and a depth that is too small makes them answer None -- the honest
# answer for "past this depth the property is unknown". A Bend law is
# universally quantified, so a law that mentions one of these helpers must
# quantify the depth too. It cannot pick one: an arbitrary Sp may be deeper than
# any fixed bound, and past the bound both sides of a law are None, so a fixed
# bound would make the deep cases pass VACUOUSLY. Every such law therefore opens
# with `for depth: Nat` or `for +depth: Nat` -- `+` exactly when the law uses the
# budget more than once -- and the helpers below take it as their first argument,
# matching the order the binders appear in.
#
# See PROOF.bend for why none of those laws is currently provable. Both are
# faults in LAWS/spec.bend, not here.

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
# The premise and the subject ask the shape fold the same question at the same
# budget, so the budget is quantified once and shared.
#
# The conclusion is the interesting half: a reshape that preserves the element
# count PRESERVES the element count. The premise is the spec's own constraint.
law reshape_preserves_numel:
  for +depth: Nat
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(depth, t) : Nat}
  {numel_of(depth, S.SpReshape{t, S.SpInvalid{}, dst}) == numel_of(depth, t) : Nat}

# The same claim from the other side: a reshape whose element count matches is
# exactly one the spec permits. Together the two say the spec's constraint is
# not merely necessary but sufficient for numel to survive. It quantifies a
# depth budget because the left-hand side is the shape fold.
law reshape_numel_is_the_new_shape:
  for depth: Nat
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  {numel_of(depth, S.SpReshape{t, S.SpInvalid{}, dst}) == prod_of(dst) : Nat}

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
# Both quantify a depth budget, for the reason above: a fixed one would make a
# Sp deeper than the budget answer None on BOTH sides and the law would pass
# without saying anything about Permute.
law permute_preserves_numel:
  for +depth: Nat
  for +t: S.Sp
  for +order: List<&2, Nat>
  {numel_of(depth, S.SpPermute{t, order}) == numel_of(depth, t) : Nat}

law flip_preserves_numel:
  for +depth: Nat
  for +t: S.Sp
  for +flags: List<&2, Bool>
  {numel_of(depth, S.SpFlip{t, flags}) == numel_of(depth, t) : Nat}

# Pad grows the shape and fills the new region with Invalid, so the element
# count grows by exactly the amount the new shape says -- not by "whatever the
# fill pattern happens to be". `depth` is used once, on the right, so it is
# affine: the claim is about the new shape and never consults the operand.
law pad_numel_is_the_new_shape:
  for depth: Nat
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {prod_of(size) == numel_of(depth, S.SpPad{t, off, size}) : Nat}

# Shrink narrows the shape, and the element count follows the narrowed shape.
# `depth` is affine here for the same reason as Pad's.
law shrink_numel_is_the_new_shape:
  for depth: Nat
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {prod_of(size) == numel_of(depth, S.SpShrink{t, off, size}) : Nat}

# Pad and Shrink are inverse in EXTENT: shrinking back out of a pad returns
# the original element count. This is the spec's "Inverse of Pad" for Shrink.
# It quantifies a depth budget, and the premise shares it: a premise proved at
# one budget and a subject queried at another would be comparing two different
# questions.
law pad_shrink_round_trip:
  for +depth: Nat
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  for +premise: {prod_of(size) == numel_of(depth, t) : Nat}
  {numel_of(depth, S.SpShrink{S.SpPad{t, off, size}, off, size}) == numel_of(depth, t) : Nat}

# Stack adds a LEADING axis: "Join along a newly created leading axis", and an
# empty Stack has no shape at all -- so this is stated for a non-empty Stack,
# whose leading axis is 1 + the number of the rest.
#
# The premise names the operand's shape because the checker cannot: without it
# both sides sit on the opaque `Sp.shape(t, depth)` behind different closures,
# and no `match` opens a call's result (PORTING.md section 1.2). Nothing is
# lost: a shapeless operand counts 0, and so does a Stack of shapeless operands.
# The budget is quantified, and shared with the premise for the reason above.
law stack_numel_is_the_leading_axis_times_the_operands:
  for +depth: Nat
  for +t: S.Sp
  for +rest: List<&2, S.Sp>
  for +bs: S.Shape
  for +premise: {shape_of(depth, t) == Some{bs} : Maybe<&2, S.Shape>}
  {numel_of(depth, S.SpStack{t <> rest}) == (Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), numel_of(depth, t)) : Nat) : Nat}

# Reduce "remove axes": the count divides by the product of the reduced axes.
# `depth` is quantified because `reduced_numel` is the shape fold on the Reduce
# node and the right-hand side is the same fold on the operand.
law reduce_numel_divides_by_the_reduced_axes:
  for +depth: Nat
  for +t: S.Sp
  for +ranges: List<&2, S.Sp>
  for +op: S.Sp
  for +n: Nat
  {reduced_numel(depth, t, n) == numel_of(depth, t) : Nat}

# ===========================================================================
# III. Broadcast -- tinyspec: "right-align shapes, element-wise max; each axis
# must be equal or 1".
#
# The count of a broadcast is the max of the two counts, which is only true
# because the two shapes differ in size by whole factors of the broadcast axes.
# It quantifies a depth budget: both sides are the shape fold, and a budget that
# did not reach both would make the law compare None with None.
# ===========================================================================

law broadcast_takes_the_left_shape:
  for +depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  {shape_of(depth, S.SpAdd{a, b}) == shape_of(depth, a) : Maybe<&2, S.Shape>}

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
# Every law here quantifies a depth budget, because the dtype fold is fuelled
# exactly as the shape fold is. Where the budget is affine it is because the
# fold is asked once: `dtype_of` of a comparison, a Range or a Binary never
# descends past the node itself.
# ===========================================================================

law comparison_is_bool:
  for depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(depth, S.SpCmpLt{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law comparison_ne_is_bool:
  for depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(depth, S.SpCmpNe{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law where_takes_the_second_operand_dtype:
  for +depth: Nat
  for +p: S.Sp
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(depth, S.SpWhere{p, a, b}) == dtype_of(depth, b) : Maybe<&2, S.Dt>}

law store_is_void:
  for depth: Nat
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  {dtype_of(depth, S.SpStore{buf, val, gate}) == none_of() : Maybe<&2, S.Dt>}

law call_is_void:
  for depth: Nat
  for +body: S.Sp
  for +args: List<&2, S.Sp>
  {dtype_of(depth, S.SpCall{body, args}) == none_of() : Maybe<&2, S.Dt>}

law range_is_index:
  for depth: Nat
  for +bound: S.Sp
  {dtype_of(depth, S.SpRange{bound}) == some_of(S.index()) : Maybe<&2, S.Dt>}

law binary_is_uint8:
  for depth: Nat
  for +size: Nat
  {dtype_of(depth, S.SpBinary{size}) == some_of(S.uint8()) : Maybe<&2, S.Dt>}

# The marker ops are "identity on data": both properties pass through.
law detach_preserves_dtype:
  for +depth: Nat
  for +a: S.Sp
  {dtype_of(depth, S.SpDetach{a}) == dtype_of(depth, a) : Maybe<&2, S.Dt>}

law detach_preserves_numel:
  for +depth: Nat
  for +a: S.Sp
  {numel_of(depth, S.SpDetach{a}) == numel_of(depth, a) : Nat}

# ===========================================================================
# VI. The elementwise column: "all inputs same shape, output same shape".
#
# This is the claim the schedule's fusion decisions rest on, so it is worth
# stating rather than leaving in a table caption. Each quantifies a depth budget
# and passes the SAME budget to the premise, so "all inputs same shape" is asked
# at the one budget the conclusion is answered at.
# ===========================================================================

law add_is_elementwise:
  for +depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(depth, a) == shape_of(depth, b) : Maybe<&2, S.Shape>}
  {shape_of(depth, S.SpAdd{a, b}) == shape_of(depth, a) : Maybe<&2, S.Shape>}

law mul_is_elementwise:
  for +depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(depth, a) == shape_of(depth, b) : Maybe<&2, S.Shape>}
  {shape_of(depth, S.SpMul{a, b}) == shape_of(depth, a) : Maybe<&2, S.Shape>}

law max_is_elementwise:
  for +depth: Nat
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(depth, a) == shape_of(depth, b) : Maybe<&2, S.Shape>}
  {shape_of(depth, S.SpMax{a, b}) == shape_of(depth, a) : Maybe<&2, S.Shape>}

# ===========================================================================
# VII. The Store invariant -- tinyspec: "buf.shape = val.shape".
#
# VACUOUS BY CONSTRUCTION, and it was before the fold grew a depth budget: the
# conclusion restates the premise verbatim, so the proof is the premise and the
# law can never fail. It is kept because the spec states the constraint, but it
# pins no behaviour. See .agents/TODO.md, "Audit against tinyspec".
# ===========================================================================

law store_matches_its_buffer:
  for +depth: Nat
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  for +premise: {shape_of(depth, buf) == shape_of(depth, val) : Maybe<&2, S.Shape>}
  {shape_of(depth, buf) == shape_of(depth, val) : Maybe<&2, S.Shape>}

# ===========================================================================
# Helpers. These are defs, not laws: they exist so each law above reads like
# the sentence it came from. `for +x` marks them reusable, which is what a
# premise and its subject have to be to appear in more than one place.
#
# `depth` is the fold's fuel budget and leads every helper, because the law it
# serves quantifies it FIRST and a proof def takes the law's `for` binders in
# order.
#
# `dims_of` and the local `drop_n` are gone: `S.drop_n` is spec.bend's, and the
# old `dims_of` existed only to open a shape the laws never ask for by name.
# ===========================================================================

# The three folds, each taking the depth budget its law quantified.
def shape_of(depth: Nat, s: S.Sp) -> Maybe<&2, S.Shape>:
  S.Sp.shape(s, depth)

def dtype_of(depth: Nat, s: S.Sp) -> Maybe<&2, S.Dt>:
  S.Sp.dtype(s, depth)

# numel is not a fold of its own in spec.bend: it is the product of the shape's
# dims, and a shapeless op has no element count, so 0 is the only honest total
# answer for one.
def numel_of(depth: Nat, s: S.Sp) -> Nat:
  S.dims_prod(S.Sp.shape(s, depth))

def some_of(d: S.Dt) -> Maybe<&2, S.Dt>:
  Some{d}

def none_of() -> Maybe<&2, S.Dt>:
  None{}

def drop_n(ds: List<&2, S.Sdim>, n: Nat) -> List<&2, S.Sdim>:
  S.drop_n(ds, n)

def prod_of(ds: List<&2, S.Sdim>) -> Nat:
  S.prod(ds)
def reduced_numel(depth: Nat, t: S.Sp, n: Nat) -> Nat:
  numel_of(depth, S.SpReduce{t, Nil{}, S.SpInvalid{}, n})
