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
#   * The `min_max` column, IN PART. It is interval arithmetic over the same
#     ops, and it is exact only where tinygrad says it is; the ARITHMETIC cells
#     ("[a+b, A+B]" and the rest) would need the float machinery above, and
#     the port's IR is STRUCTURAL -- its `one()` and `zero()` are placeholder
#     consts with no number. So the arithmetic is not stated.
#
#     IT WAS NOT PINNED ELSEWHERE EITHER, and this line claimed it was: "pinned
#     by test/null/test_uop_vmin_vmax.py (55 tests) instead". MEASURED
#     2026-11-17: `tinygrad/test/` is NOT VENDORED at the pin --
#     `git ls-tree f5ac54685074 --name-only tinygrad/test` answers 0 -- so the
#     column was pinned by NOTHING. The two cells that need no NUMBER are
#     stated now: "src[0]" and "dtype range".
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
#
# tinyspec states validity conditions on ops -- "prod s_k = prod s'_k" for
# Reshape, "buf.shape = val.shape" for Store -- as things a well-formed graph
# must satisfy. A Bend law is universally quantified, so it cannot carry an
# assumption inline; the condition enters as a premise carrying its own proof.
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

# II. The spec's derived properties, stated as laws.
#
# tinyspec's shape column, read off the clauses: every movement op passes the
# shape through except Reshape, Expand, Pad, Shrink, Index, Stack and Bitcast,
# which have their own clause. The laws below are the ones that constrain the
# ELEMENT COUNT, because that is the invariant the whole scheduler rests on: a
# view may not change how many elements a tensor has.
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

# IV. The decomposed elementwise ops.
#
# tinyspec's "Decomposed elementwise ops" table. Each of these is DEFINED in
# terms of the primitives, so each is a definitional equality and the checker
# proves it by reflexivity. If the port ever changes one of these, a law fails
# immediately and names the op -- which is the entire value of writing the
# table down at all.

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

law cmp_ge_is_eq_of_cmp_lt:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_ge(a, b) == S.SpCmpEq{S.SpCmpLt{a, b}, A.zero()} : S.Sp}

law cmp_le_is_eq_of_cmp_lt_swapped:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_le(a, b) == S.SpCmpEq{S.SpCmpLt{b, a}, A.zero()} : S.Sp}

law cmp_ne_is_eq_of_double_eq:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_ne(a, b) == S.SpCmpEq{S.SpCmpEq{a, b}, A.zero()} : S.Sp}

law cmp_eq_is_primitive:
  for +a: S.Sp
  for +b: S.Sp
  {A.cmp_eq(a, b) == S.SpCmpEq{a, b} : S.Sp}

law not_is_eq_zero:
  for +a: S.Sp
  {A.logical_not(a) == S.SpCmpEq{a, A.zero()} : S.Sp}

law truncmod_is_a_minus_b_times_truncdiv:
  for +a: S.Sp
  for +b: S.Sp
  {A.truncmod(a, b) == A.sub(a, S.SpMul{b, S.SpTruncdiv{a, b}}) : S.Sp}

law mulacc_is_add_of_mul:
  for +a: S.Sp
  for +b: S.Sp
  for +c: S.Sp
  {A.mulacc(a, b, c) == S.SpAdd{S.SpMul{a, b}, c} : S.Sp}

# V. The dtype column, for the ops where it is not simply src[0].
#
# tinyspec: comparisons are bool; Where takes src[1]; Range is index; Store and
# Call are void; Binary is uint8.
#
# Every law here reads the dtype fold at a node that answers without
# descending, so each is a single arm of `Sp.dtype` rather than a fold.

law comparison_is_bool:
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpCmpLt{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

law comparison_ne_is_bool:
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpCmpNe{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

# THE COMPARISON THAT WAS MISSING.  MEASURED 2026-11-17: the spec IR had no
# `CmpEq` arm at all, so the spec's own primitive comparison -- the one
# tinyspec calls "primitive elementwise equality, returning bool (as do CmpLt
# and CmpNe)" -- could not be stated.  The port had `CmpNe` as the constructor
# and derived `CmpEq` from it, which is BACKWARDS: the spec says `CmpNe` is
# `CmpEq`'s complement.
law comparison_eq_is_bool:
  for a: S.Sp
  for b: S.Sp
  {dtype_of(S.SpCmpEq{a, b}) == some_of(S.boolean()) : Maybe<&2, S.Dt>}

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

# THE PASSTHROUGH OPS, WHOSE DTYPE THE SPEC'S TABLE GIVES AS src[0]'s.  The
# spec's derived-properties table says so for `Load` ("from src[0]"), `Copy`
# ("from src[0]"), `After` ("src[0].dtype") and `Bitcast` ("from arg" -- so
# Bitcast is NOT a passthrough and has no law here), and the marker ops
# ("identity on data").
#
# MEASURED 2026-11-17: none of these was stated, and each is a single arm of
# `Sp.dtype` -- so each is a fact the port already knows and the book did not
# say.
law load_preserves_dtype:
  for buf: S.Sp
  for alt: Maybe<&2, S.Sp>
  for gate: Maybe<&2, S.Sp>
  {dtype_of(S.SpLoad{buf, alt, gate}) == dtype_of(buf) : Maybe<&2, S.Dt>}

law copy_preserves_dtype:
  for buf: S.Sp
  for dev: S.Dev
  {dtype_of(S.SpCopy{buf, dev}) == dtype_of(buf) : Maybe<&2, S.Dt>}

law after_preserves_dtype:
  for buf: S.Sp
  for deps: List<&2, S.Sp>
  {dtype_of(S.SpAfter{buf, deps}) == dtype_of(buf) : Maybe<&2, S.Dt>}

# AND THE TWO OPS THAT CAME WITH THE SPEC'S OWN DECOMPOSITIONS.
law truncdiv_preserves_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpTruncdiv{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law truncmod_preserves_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpTruncmod{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law detach_preserves_numel:
  for +a: S.Sp
  {numel_of(S.SpDetach{a}) == numel_of(a) : Nat}

# V-bis. THE PASSTHROUGH OPS' SHAPE, and the spec says so in words.
#
# "After & (buf, deps...) & --- & Passthrough of buf; guarantees deps execute
# first."  So `After`'s shape IS its buffer's -- and the same holds for `Load`
# and `Copy`, whose shapes the spec's table gives as src[0]'s.
#
# MEASURED 2026-11-17: these were not stated.  They are single arms of
# `Sp.shape`, so each is a fact the port already knew and the book did not say.
law after_preserves_shape:
  for buf: S.Sp
  for deps: List<&2, S.Sp>
  {shape_of(S.SpAfter{buf, deps}) == shape_of(buf) : Maybe<&2, S.Shape>}

law load_preserves_shape:
  for buf: S.Sp
  for alt: Maybe<&2, S.Sp>
  for gate: Maybe<&2, S.Sp>
  {shape_of(S.SpLoad{buf, alt, gate}) == shape_of(buf) : Maybe<&2, S.Shape>}

law copy_preserves_shape:
  for buf: S.Sp
  for dev: S.Dev
  {shape_of(S.SpCopy{buf, dev}) == shape_of(buf) : Maybe<&2, S.Shape>}

# V-ter-bis. The ALU OPS' DTYPE, which the spec's table gives as one row for
# the family: "ALU unary & src[0].dtype" and "Other binary & src[0].dtype".
#
# MEASURED 2026-11-17: the ALU census named THIRTEEN dtype arms unpinned --
# `SpAdd`, `SpAnd`, `SpIdiv`, `SpMod`, `SpMul`, `SpOr`, `SpRecip`, `SpShl`,
# `SpShr`, `SpTrunc`, `SpXor` and `SpContiguousBackward` -- and every one of
# them is the spec's "src[0].dtype".
law recip_takes_the_source_dtype:
  for +a: S.Sp
  {dtype_of(S.SpRecip{a}) == dtype_of(a) : Maybe<&2, S.Dt>}

law trunc_takes_the_source_dtype:
  for +a: S.Sp
  {dtype_of(S.SpTrunc{a}) == dtype_of(a) : Maybe<&2, S.Dt>}

law add_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpAdd{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law mul_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpMul{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law max_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpMax{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law mod_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpMod{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law idiv_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpIdiv{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law xor_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpXor{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law or_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpOr{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law and_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpAnd{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law shr_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpShr{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law shl_takes_the_source_dtype:
  for +a: S.Sp
  for +b: S.Sp
  {dtype_of(S.SpShl{a, b}) == dtype_of(a) : Maybe<&2, S.Dt>}

law contiguous_backward_takes_the_source_dtype:
  for +a: S.Sp
  {dtype_of(S.SpContiguousBackward{a}) == dtype_of(a) : Maybe<&2, S.Dt>}

# V-ter. The DEVICE column, and the spec's THIRD derived property.
#
# tinyspec: "Each UOp has five derived properties -- dtype, shape, device,
# addrspace, and min_max -- determined by the rules at the end of this
# document."  MEASURED 2026-11-17: the port had the dtype column and the shape
# column and NO device column, so this law set is the port's THIRD.
#
# The column is SHORT and TOTAL: an op's device is `src[0].device` (the
# movement ops, the ALU ops, `Reduce`, `Unshard`, `Load`, `Index`, `After` and
# the marker ops), "from arg" (the three source ops and `Copy`), `null`
# (`Const` and `Range`), or "first non-null src device" (`Call`).

law movement_preserves_device:
  for +a: S.Sp
  {device_of(S.SpPermute{a, Nil{}}) == device_of(a) : Maybe<&2, S.Dev>}

law alu_preserves_device:
  for +a: S.Sp
  for +b: S.Sp
  {device_of(S.SpAdd{a, b}) == device_of(a) : Maybe<&2, S.Dev>}

law source_op_device_is_from_arg:
  for size: Nat
  for dt: S.Dt
  for dev: S.Dev
  for addr: S.Addr
  {device_of(S.SpBuffer{size, dt, dev, addr}) == some_of_dev(dev) : Maybe<&2, S.Dev>}

law copy_device_is_from_arg:
  for buf: S.Sp
  for dev: S.Dev
  {device_of(S.SpCopy{buf, dev}) == some_of_dev(dev) : Maybe<&2, S.Dev>}

law const_has_no_device:
  for v: S.Sp
  for dt: S.Dt
  {device_of(S.SpConst{v, dt}) == none_of_dev() : Maybe<&2, S.Dev>}

law range_has_no_device:
  for bound: S.Sp
  {device_of(S.SpRange{bound}) == none_of_dev() : Maybe<&2, S.Dev>}

law after_preserves_device:
  for buf: S.Sp
  for deps: List<&2, S.Sp>
  {device_of(S.SpAfter{buf, deps}) == device_of(buf) : Maybe<&2, S.Dev>}

# AND THE CALL's device, which the spec gives as "first non-null src device".
# The port's fold takes the BODY's device -- the body IS the first src -- and
# the spec's rule for the ARGS onward is NOT modelled, because the args' device
# fold needs this fold and Bend refuses mutual recursion.  The law states the
# port's rule and `spec.bend`'s `Sp.device` says which half it implements.
law call_device_is_the_body_device:
  for +body: S.Sp
  for args: List<&2, S.Sp>
  {device_of(S.SpCall{body, args}) == device_of(body) : Maybe<&2, S.Dev>}

# AND THE STACK's device, which the spec's op table gives as "All shapes must
# match" -- so the stack is on ONE device and the port's fold takes the FIRST
# element's.
law stack_device_is_the_first_element_device:
  for +a: S.Sp
  for +b: S.Sp
  {device_of(S.SpStack{[a, b]}) == device_of(a) : Maybe<&2, S.Dev>}

# AND THE MOVEMENT OPS' DTYPE, which the spec's table gives as one row for the
# whole family: "Movement ops & src[0].dtype & (see op) & src[0].device".
#
# MEASURED 2026-11-17: the ALU CENSUS named `SpReshape`'s dtype arm UNPINNED
# -- and it was right, because the shape laws about a Reshape read its NUMEL
# and not its dtype, so the arm was unpinned and the gate's own plant broke it
# and the gate stayed green.
law reshape_preserves_dtype:
  for +t: S.Sp
  for +src: S.Sp
  for +dst: List<&2, S.Sdim>
  {dtype_of(S.SpReshape{t, src, dst}) == dtype_of(t) : Maybe<&2, S.Dt>}

law permute_preserves_dtype:
  for +t: S.Sp
  for +order: List<&2, Nat>
  {dtype_of(S.SpPermute{t, order}) == dtype_of(t) : Maybe<&2, S.Dt>}

law expand_preserves_dtype:
  for +t: S.Sp
  for +pre: List<&2, S.Sdim>
  for +total: List<&2, S.Sdim>
  {dtype_of(S.SpExpand{t, pre, total}) == dtype_of(t) : Maybe<&2, S.Dt>}

law pad_preserves_dtype:
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {dtype_of(S.SpPad{t, off, size}) == dtype_of(t) : Maybe<&2, S.Dt>}

law shrink_preserves_dtype:
  for +t: S.Sp
  for +off: List<&2, S.Sdim>
  for +size: List<&2, S.Sdim>
  {dtype_of(S.SpShrink{t, off, size}) == dtype_of(t) : Maybe<&2, S.Dt>}

# AND THE TWO THAT ARE "from arg" AND NOT src[0]'s: `Cast` and `Bitcast` both
# take a TARGET dtype, and the spec's table gives them "from arg" -- so their
# dtype is the one they were given and NOT the source's.
law bitcast_takes_the_target_dtype:
  for +t: S.Sp
  for dt: S.Dt
  {dtype_of(S.SpBitcast{t, dt}) == some_of(dt) : Maybe<&2, S.Dt>}

law cast_takes_the_target_dtype:
  for +t: S.Sp
  for dt: S.Dt
  {dtype_of(S.SpCast{t, dt}) == some_of(dt) : Maybe<&2, S.Dt>}

# AND THE TWO THE ALU CENSUS MEASURED AS UNPINNED.  MEASURED 2026-11-17: the
# census names the arms no law reads, and it named `SpIdx1` and `SpReduce` --
# the spec's table gives both `src[0].device`, and the book did not say so.
law index_preserves_device:
  for +t: S.Sp
  for +a: S.Sp
  {device_of(S.SpIdx1{t, a}) == device_of(t) : Maybe<&2, S.Dev>}

# AND THEIR DTYPE, which the spec's table gives as src[0].dtype for both --
# "Index & src[0].dtype & remaining dims & src[0].device" and "Reduce &
# src[0].dtype & remove first n axes & src[0].device".
law index_preserves_dtype:
  for +t: S.Sp
  for +a: S.Sp
  {dtype_of(S.SpIdx1{t, a}) == dtype_of(t) : Maybe<&2, S.Dt>}

law reduce_preserves_dtype:
  for +t: S.Sp
  for ranges: List<&2, S.Sp>
  for op: S.Sp
  for n: Nat
  {dtype_of(S.SpReduce{t, ranges, op, n}) == dtype_of(t) : Maybe<&2, S.Dt>}

law reduce_preserves_device:
  for +t: S.Sp
  for ranges: List<&2, S.Sp>
  for op: S.Sp
  for n: Nat
  {device_of(S.SpReduce{t, ranges, op, n}) == device_of(t) : Maybe<&2, S.Dev>}

# V-quater. The MIN_MAX column, and the spec's FOURTH derived property.
#
# The column has THREE kinds of cell, and this law set states the TWO that need
# no NUMBER:
#
#   * "src[0]"      -- the movement ops, `Unshard`, `Copy`, `Index` and `After`.
#                      The interval is the SOURCE'S.
#
# The third kind -- "[a+b, A+B]" and the other arithmetic cells -- needs the
# VALUES, and the port's IR is STRUCTURAL: its `one()` and `zero()` are
# placeholder consts with no number.  So those cells are NOT stated, and
# `spec.bend`'s fold says so at each arm.
#
# AND THE HEADER'S CLAIM THAT THE COLUMN IS PINNED BY A TEST FILE WAS STALE --
# the file is not in this tree -- so the column was pinned by NOTHING before this.

law movement_preserves_min_max:
  for +a: S.Sp
  {min_max_of(S.SpPermute{a, Nil{}}) == min_max_of(a) : Maybe<&2, S.Iv>}

law copy_preserves_min_max:
  for buf: S.Sp
  for dev: S.Dev
  {min_max_of(S.SpCopy{buf, dev}) == min_max_of(buf) : Maybe<&2, S.Iv>}

law after_preserves_min_max:
  for buf: S.Sp
  for deps: List<&2, S.Sp>
  {min_max_of(S.SpAfter{buf, deps}) == min_max_of(buf) : Maybe<&2, S.Iv>}

# AND THE "dtype range" CELL, WHICH IS THE INTERVAL OF THE DTYPE'S RANGE.  The
# bounds are `Maybe`s, so the law says the interval IS the range rather than
# spelling the numbers -- and the two helpers below are the port's.
law bitcast_takes_the_dtype_range:
  for +a: S.Sp
  for dt: S.Dt
  {min_max_of(S.SpBitcast{a, dt}) == min_max_of(S.SpBuffer{1n, dt, S.D1{0}, S.AGlobal{}}) : Maybe<&2, S.Iv>}

# AND THE PARAM's SHAPE, which the spec's column gives as "$(n)$ from src, or
# $()$" -- the size, the same as a Buffer's.
law param_shape_is_its_size:
  for size: Nat
  for dt: S.Dt
  for dev: S.Dev
  {shape_of(S.SpParam{size, dt, dev}) == some_of_shape(S.Shape.of([S.SN{size}])) : Maybe<&2, S.Shape>}

# AND THE UNSHARD's SHAPE, WHICH IS NOT THE SPEC'S.  The spec's column is
# "src[0], each a_k x n_k" -- the source's shape with EACH SHARDED AXIS SPLIT
# into its axis and its length.  MEASURED 2026-11-17: the port's fold answers
# `src[0]` WHOLE, so the split is not modelled, and the law says what the port
# does rather than what the spec says.
#
# AND THE DIVERGENCE IS NOTED BECAUSE THE SPEC'S RULE IS NOT THE SAME THING.
# It is the one place where the port's shape column is NARROWER than the spec's,
# and a reader of the spec would expect the split.
law unshard_preserves_the_source_shape:
  for +t: S.Sp
  for ranges: List<&2, S.Sp>
  for axes: List<&2, Nat>
  {shape_of(S.SpUnshard{t, ranges, axes}) == shape_of(t) : Maybe<&2, S.Shape>}

# AND THE INDEX FAMILY'S SHAPE, WHICH THE SPEC'S COLUMN GIVES AS "remaining
# dims": the base's trailing dims, after the index shapes.
#
# MEASURED 2026-11-17: the shape census named `SpIdx0`, `SpIdx2`, `SpIdx3` and
# `SpIdx4` UNPINNED -- and they are the four arities the spec's one row covers,
# so the row was pinned only for `SpIdx1`.
law index_of_no_operands_keeps_the_base_shape:
  for +t: S.Sp
  {shape_of(S.SpIdx0{t}) == shape_of(t) : Maybe<&2, S.Shape>}

# AND THE SHAPE IS NOT THE BASE'S WHOLE: an index of k operands DROPS k of
# the base's dims and keeps the rest -- "remaining dims".
#
# THE OTHER ARITIES ARE NOT STATED, and the reason is the PROOF and not the
# claim: the shape of an `Idx2` is the zip of the two index shapes with the
# base's dims after dropping two, and proving that needs the same induction the
# broadcast law needs -- the zip's shape and the drop's shape together.  That is
# a piece of work and not a piece of prose, so it is not claimed here.

# VI. The elementwise column: "all inputs same shape, output same shape".
#
# AND THE SHAPE COLUMN for the ops the spec pins it on -- the same section,
# because it is the SHAPE column and the shape census counts this section's
# laws.
#
# MEASURED 2026-11-17: the shape census names the shape fold's arms that no
# law reads -- THIRTY-SEVEN of them -- and an arm no law reads "may be wrong
# and the book says nothing".  These are the ones the spec's table pins.
#
# THE SOURCE OPS' SHAPE IS THEIR SIZE: the spec's column is "$(n)$ from src,
# or $()$" -- so a Buffer of n elements has the shape (n,).
law buffer_shape_is_its_size:
  for size: Nat
  for dt: S.Dt
  for dev: S.Dev
  for addr: S.Addr
  {shape_of(S.SpBuffer{size, dt, dev, addr}) == some_of_shape(S.Shape.of([S.SN{size}])) : Maybe<&2, S.Shape>}

law alloc_shape_is_its_size:
  for size: Nat
  for dt: S.Dt
  for dev: S.Dev
  for addr: S.Addr
  {shape_of(S.SpAlloc{size, dt, dev, addr}) == some_of_shape(S.Shape.of([S.SN{size}])) : Maybe<&2, S.Shape>}

# AND A CONSTANT IS A SCALAR: the spec's column is "$()$" for a Const, and the
# port's fold says the same.
law const_shape_is_empty:
  for v: S.Sp
  for dt: S.Dt
  {shape_of(S.SpConst{v, dt}) == some_of_shape(S.Shape.empty()) : Maybe<&2, S.Shape>}

# AND THE PASSTHROUGH OPS' SHAPE IS THE BUFFER'S: the spec's column gives
# `Load` and `Copy` the shape "src[0].shape".
law load_shape_is_the_buffer_shape:
  for buf: S.Sp
  for alt: Maybe<&2, S.Sp>
  for gate: Maybe<&2, S.Sp>
  {shape_of(S.SpLoad{buf, alt, gate}) == shape_of(buf) : Maybe<&2, S.Shape>}

law copy_shape_is_the_buffer_shape:
  for buf: S.Sp
  for dev: S.Dev
  {shape_of(S.SpCopy{buf, dev}) == shape_of(buf) : Maybe<&2, S.Shape>}

# AND A CAST AND A BITCAST KEEP THE SOURCE'S SHAPE, and a Range is a scalar.
law cast_preserves_shape:
  for +t: S.Sp
  for dt: S.Dt
  {shape_of(S.SpCast{t, dt}) == shape_of(t) : Maybe<&2, S.Shape>}

law bitcast_preserves_shape:
  for +t: S.Sp
  for dt: S.Dt
  {shape_of(S.SpBitcast{t, dt}) == shape_of(t) : Maybe<&2, S.Shape>}

law range_shape_is_empty:
  for bound: S.Sp
  {shape_of(S.SpRange{bound}) == some_of_shape(S.Shape.empty()) : Maybe<&2, S.Shape>}


#
# This is the claim the schedule's fusion decisions rest on, so it is worth
# stating rather than leaving in a table caption.

# VI-bis. THE SPEC'S OWN COMPOSITIONS, and the shape each one claims.
#
# tinyspec's "Common Ops as Compositions" writes five of them in Python, and
# each is a SHAPE claim about a composition of the primitives.  THE FIRST IS:
#
#   def gemm(A, B):
#     M,K = A.shape; _,N = B.shape
#     return (A.reshape(M,K,1) * B.reshape(1,K,N)).sum(1)
#
# MEASURED 2026-11-17: the port stated the COMPONENTS -- the reshape law, the
# elementwise law and the reduce law -- and not the COMPOSITION.  And the
# composition is what the spec's readers care about, because it is the shape
# the schedule's fusion decisions read.
#
# AND THE CLAIM IS THE PRODUCT'S SHAPE, which is the sharpest part: the two
# reshapes broadcast, and the broadcast of `(M,K,1)` and `(1,K,N)` is `(M,K,N)`.
law gemm_broadcasts_to_the_three_axis_shape:
  for +m: S.Sdim
  for +k: S.Sdim
  for +n: S.Sdim
  for ma: S.AllSN([m, k, S.SN{1n}])
  for mb: S.AllSN([S.SN{1n}, k, n])
  for same: S.SameLen([m, k, S.SN{1n}], [S.SN{1n}, k, n])
  {shape_of(S.SpMul{S.SpReshape{S.SpInvalid{}, S.SpInvalid{}, [m, k, S.SN{1n}]},
                              S.SpReshape{S.SpInvalid{}, S.SpInvalid{}, [S.SN{1n}, k, n]}})
   == some_of_shape(S.Shape.of([m, k, n])) : Maybe<&2, S.Shape>}

# The GATHER composition, and the claim is the NET SHAPE: `(D,)` -- the
# gather axis, which is `idx`'s length and not `T`'s.
#
# tinyspec's "Common Ops as Compositions":
#
#   # gather: out[i] = T[idx[i]]. one-hot mask along gather axis, then reduce
#   def gather(T, idx):
#
# AND THE TWO BROADCASTS ARE THE WORK: `(K, 1)` with `(1, D)` is `(K, D)`, and
# `(K, 1)` with `(K, D)` is `(K, D)`.  AND THE REDUCE DROPS THE FIRST AXIS.
law gather_composition_has_the_gather_axis_shape:
  for +t: S.Sp
  for +idx: S.Sp
  for +k: Nat
  for +d: Nat
  for +pos: S.Sp
  for +idxr: S.Sp
  for +mask: S.Sp
  for +tr: S.Sp
  for +prod: S.Sp
  for +out: S.Sp
  # AND THE SHAPES, and the premises NAME THE CONCRETE LISTS -- the gemm law's
  # own spelling, and the reason the gemm law's `elem_pick_gemm` lemma
  # applies to it.
  for +pa: {shape_of(pos) == Some{S.Shape.of([S.SN{k}, S.SN{1n}])} : Maybe<&2, S.Shape>}
  for +pb: {shape_of(idxr) == Some{S.Shape.of([S.SN{1n}, S.SN{d}])} : Maybe<&2, S.Shape>}
  for +pm: {shape_of(mask) == Some{S.Shape.of([S.SN{k}, S.SN{d}])} : Maybe<&2, S.Shape>}
  for +ptr: {shape_of(tr) == Some{S.Shape.of([S.SN{k}, S.SN{1n}])} : Maybe<&2, S.Shape>}
  for +pp: {shape_of(prod) == Some{S.Shape.of([S.SN{k}, S.SN{d}])} : Maybe<&2, S.Shape>}
  # AND THE CONSTRUCTION, so the law is about the SPEC's gather and not about
  # five unrelated nodes: the mask compares `pos` with `idx` reshaped, the
  # product is the product of `mask` with `T` reshaped, and the output
  # reduces the product's FIRST axis.
  for +cmask: {mask == S.SpCmpEq{pos, idxr} : S.Sp}
  for +cprod: {prod == S.SpMul{tr, mask} : S.Sp}
  for +cout: {out == S.SpReduce{prod, Nil{}, S.SpInvalid{}, 1n} : S.Sp}
  # AND THE "EVERY DIM IS CONCRETE" AND "SAME LENGTH" PROOFS, because the
  # broadcast lemma needs them and the port's own broadcast law carries the
  # same two premises.  AND THEY COME LAST, because a `Type` binder is not a
  # `Data` one.
  for ca: S.AllSN([S.SN{k}, S.SN{1n}])
  for ca2: S.AllSN([S.SN{k}, S.SN{1n}])
  for cb: S.AllSN([S.SN{1n}, S.SN{d}])
  for cc: S.AllSN([S.SN{k}, S.SN{d}])
  for same1: S.SameLen([S.SN{k}, S.SN{1n}], [S.SN{1n}, S.SN{d}])
  for same2: S.SameLen([S.SN{k}, S.SN{1n}], [S.SN{k}, S.SN{d}])
  {shape_of(out) == Some{S.Shape.of([S.SN{d}])} : Maybe<&2, S.Shape>}

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

# AND THE COMPARISONS, WHICH THE SPEC'S TABLE PUTS IN THE SAME TABLE: "CmpLt,
# CmpEq" are Binary ops with "all inputs same shape, output same shape".
#
# MEASURED 2026-11-17: `CmpLt` and `CmpNe` had no elementwise law, and the
# shape fold's arms for them were UNPINNED -- the census said so and named them.
law cmp_lt_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpCmpLt{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

law cmp_eq_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpCmpEq{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

law cmp_ne_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpCmpNe{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

# AND THE INTEGER DIVISION PAIR, which the spec's derived-properties table
# covers as "Other binary" -- src[0].dtype, BROADCAST, src[0].device.  So they
# broadcast like every other binary ALU op.
law truncdiv_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpTruncdiv{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

law truncmod_is_elementwise:
  for +a: S.Sp
  for +b: S.Sp
  for +premise: {shape_of(a) == shape_of(b) : Maybe<&2, S.Shape>}
  {shape_of(S.SpTruncmod{a, b}) == shape_of(a) : Maybe<&2, S.Shape>}

# VII. The Store invariant -- tinyspec: "buf.shape = val.shape".
#
# VACUOUS BY CONSTRUCTION, and it was before the folds were fuelled: the
# conclusion restates the premise verbatim, so the proof is the premise and the
# law can never fail. It is kept because the spec states the constraint, but it
# pins no behaviour. See .agents/TODO.md, "Audit against tinyspec".

law store_matches_its_buffer:
  for +buf: S.Sp
  for +val: S.Sp
  for +gate: Maybe<&2, S.Sp>
  for +premise: {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}
  {shape_of(buf) == shape_of(val) : Maybe<&2, S.Shape>}

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

# Helpers. These are defs, not laws: they exist so each law above reads like
# the sentence it came from. `for +x` marks them reusable, which is what a
# premise and its subject have to be to appear in more than one place.
#
# `dims_of` is gone: `S.drop_n` is spec.bend's, and the old `dims_of` existed
# only to open a shape the laws never ask for by name.
# The folds, total: a node in, a shape or a dtype out.
def shape_of(s: S.Sp) -> Maybe<&2, S.Shape>:
  S.Sp.shape(s)

def dtype_of(s: S.Sp) -> Maybe<&2, S.Dt>:
  S.Sp.dtype(s)

# The THIRD derived property, and the port had two of the spec's five.
#
# tinyspec: "Each UOp has five derived properties -- dtype, shape, device,
# addrspace, and min_max -- determined by the rules at the end of this
# document."  MEASURED 2026-11-17: the port had `Sp.dtype` and `Sp.shape` and
# NO device fold at all, so the device column of the spec's table was a claim
# the book could not state.
def device_of(s: S.Sp) -> Maybe<&2, S.Dev>:
  S.Sp.device(s)

# The FOURTH derived property, and the part of it that is STATEABLE WITHOUT A
# VALUE.
#
# tinyspec: "Each UOp has five derived properties -- dtype, shape, device,
# addrspace, and min_max -- determined by the rules at the end of this
# document."  MEASURED 2026-11-17: the port had the dtype column, the shape
# column and the device column, and NO min_max fold.
#
# AND THE HEADER'S CLAIM THAT THE COLUMN IS PINNED ELSEWHERE WAS STALE: it says
# "pinned by test/null/test_uop_vmin_vmax.py (55 tests) instead", and
# `tinygrad/test/` is NOT VENDORED at the pin -- MEASURED,
# `git ls-tree f5ac54685074 --name-only tinygrad/test` answers 0.  So the
# column was pinned by NOTHING, and the two cells that need no number are
# stated here.
def min_max_of(s: S.Sp) -> Maybe<&2, S.Iv>:
  S.Sp.min_max(s)

# numel is not a fold of its own in spec.bend: it is the product of the shape's
# dims, and a shapeless op has no element count, so 0 is the only honest total
# answer for one.
def numel_of(s: S.Sp) -> Nat:
  S.dims_prod(S.Sp.shape(s))

def some_of_shape(sh: S.Shape) -> Maybe<&2, S.Shape>:
  Some{sh}

def some_of(d: S.Dt) -> Maybe<&2, S.Dt>:
  Some{d}

def none_of() -> Maybe<&2, S.Dt>:
  None{}

# The device column's two answers: "from arg" is a device, and "null" is the
# absence of one.  They are SEPARATE helpers from `some_of`/`none_of` because
# those are about a DTYPE and these are about a DEVICE, and a law that reads
# both would have to name two different absence types.
def some_of_dev(d: S.Dev) -> Maybe<&2, S.Dev>:
  Some{d}

def none_of_dev() -> Maybe<&2, S.Dev>:
  None{}

# And the interval column's "there is one" -- the shape `Sp.min_max` answers.
def some_of_iv(i: S.Iv) -> Maybe<&2, S.Iv>:
  Some{i}

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
