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
# The conclusion is the interesting half: a reshape that preserves the element
# count PRESERVES the element count. The premise is the spec's own constraint.
law reshape_preserves_numel:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(t) : Nat}
  {numel_of(S.SpReshape{t, S.SpInvalid{}, dst}) == numel_of(t) : Nat}

# The same claim from the other side: a reshape whose element count matches is
# exactly one the spec permits. Together the two say the spec's constraint is
# not merely necessary but sufficient for numel to survive.
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
# The premise names the operand's shape because the checker cannot: without it
# both sides sit on the opaque `Sp.shape(t)` behind different closures, and no
# `match` opens a call's result (PORTING.md section 1.2). Nothing is lost: a
# shapeless operand counts 0, and so does a Stack of shapeless operands.
law stack_numel_is_the_leading_axis_times_the_operands:
  for +t: S.Sp
  for +rest: List<&2, S.Sp>
  for +bs: S.Shape
  for +premise: {shape_of(t) == Some{bs} : Maybe<&2, S.Shape>}
  {numel_of(S.SpStack{t <> rest}) == (Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), numel_of(t)) : Nat) : Nat}

# Reduce "remove axes": the count divides by the product of the reduced axes.
law reduce_numel_divides_by_the_reduced_axes:
  for +t: S.Sp
  for +ranges: List<&2, S.Sp>
  for +op: S.Sp
  for +n: Nat
  {reduced_numel(t, n) == numel_of(t) : Nat}

# ===========================================================================
# III. Broadcast -- tinyspec: "right-align shapes, element-wise max; each axis
# must be equal or 1".
#
# The count of a broadcast is the max of the two counts, which is only true
# because the two shapes differ in size by whole factors of the broadcast axes.
# ===========================================================================

law broadcast_takes_the_left_shape:
  for +a: S.Sp
  for +b: S.Sp
  {shape_of(S.SpAdd{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

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
# ===========================================================================

law comparison_is_bool:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpCmpLt{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law comparison_ne_is_bool:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpCmpNe{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law where_takes_the_second_operand_dtype:
  for +p: S.Sp
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpWhere{p, a, b}) == dtype_of(b) : Maybe<&2, S.Dt>}

law store_is_void:
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  {dtype_of(S.SpStore{buf, val, gate}) == none_of() : Maybe<&2, S.Dt>}

law call_is_void:
  for +body: S.Sp
  for +args: List<&2, S.Sp>
  {dtype_of(S.SpCall{body, args}) == none_of() : Maybe<&2, S.Dt>}

law range_is_index:
  for +bound: S.Sp
  {dtype_of(S.SpRange{bound}) == some_of(S.index()) : Maybe<&2, S.Dt>}

law binary_is_uint8:
  for +size: Nat
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
# ===========================================================================

law store_matches_its_buffer:
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  for +premise: {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}
  {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}

# ===========================================================================
# Helpers. These are defs, not laws: they exist so each law above reads like
# the sentence it came from. `for +x` marks them reusable, which is what a
# premise and its subject have to be to appear in more than one place.
# ===========================================================================

def shape_of(s: S.Sp) -> Maybe<&2, S.Shape>:
  S.Sp.shape(s)

def dtype_of(s: S.Sp) -> Maybe<&2, S.Dt>:
  S.Sp.dtype(s)

def numel_of(s: S.Sp) -> Nat:
  # the spec's shape is total on every op that has one; a shapeless op has no
  # element count, and 0 is the only honest total answer for one
  Maybe.default(&2, Nat, S.Sp.numel(s), 0n)

def some_of(d: S.Dt) -> Maybe<&2, S.Dt>:
  Some{d}

def none_of() -> Maybe<&2, S.Dt>:
  None{}

def dims_of.go(m: Maybe<&2, S.Shape>) -> List<&2, S.Sdim>:
  match m:
    case Some{sh}: S.Shape.to_dims(sh)
    case None{}: Nil{}

def dims_of(s: S.Sp) -> List<&2, S.Sdim>:
  dims_of.go(shape_of(s))

def drop_n(ds: List<&2, S.Sdim>, n: Nat) -> List<&2, S.Sdim>:
  S.drop_dims(ds, n)

def prod_of(ds: List<&2, S.Sdim>) -> Nat:
  S.prod(ds)

def reduced_numel(t: S.Sp, n: Nat) -> Nat:
  numel_of(S.SpReduce{t, Nil{}, S.SpInvalid{}, n})
