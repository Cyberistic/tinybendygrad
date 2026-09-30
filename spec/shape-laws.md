# Shape laws: what pinning the element count buys us

`tinybendygrad/LAWS.bend` states, as Bend laws, what `spec/tinyspec.tex` says
about shapes — and most of it reduces to one invariant: **a view may not change
how many elements a tensor has.**

**26 of 32 laws are proven. The gate is red because 6 are open, and it names
them.**

## The laws

A `view` is a movement op. `Reshape` reinterprets, `Permute` reorders axes,
`Flip` mirrors, `Pad` grows, `Shrink` narrows, `Stack` adds a leading axis,
`Reduce` removes axes. Each gets a law:

```
law permute_preserves_numel:
  for +t: S.Sp
  for +order: List<&2, Nat>
  {numel_of(S.SpPermute{t, order}) == numel_of(t) : Nat}
```

`Reshape` is the interesting one, because its count is set by something else —
the destination shape — so the law carries tinyspec's own validity condition as a
premise rather than as prose to be remembered:

```
law reshape_preserves_numel:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(t) : Nat}
  {numel_of(S.SpReshape{t, ...}) == numel_of(t) : Nat}
```

## What we gain

**A dropped element in a view becomes a compile error.** In Python a reshape to
the wrong element count raises at runtime, on one shape, on one backend, after
the model has trained. Here it fails `bend --check-only` on the definition.

**Two of our own laws were wrong and the checker said so.** This is the part
worth reading:

- `broadcast_takes_the_left_shape` claimed a broadcast takes the left operand's
  shape. Refuted: (1,3) with (2,3) is (2,3), which is *neither* operand. tinyspec
  says right-align and take the element-wise max.
- `reduce_numel_divides_by_the_reduced_axes` was named "divides by" and its body
  asserted *equality*. (4,5,6) reduced over its first axis is (5,6) — 30, not 120.

Neither was a proof failure. Both were the spec written down wrongly, found by a
machine that could not be argued with. That is the whole argument for this file
existing.

**And the broadcast rule the other laws depend on was an actual bug.**
`zip_max` returned `Nil{}` when the left list ran out, so it truncated instead of
right-aligning: `SpMax{(2,), (2,2)}` yielded `(2,)` where the spec gives `(2,2)`.
The comment directly above it described the correct behaviour and the code
contradicted it. Found by measurement, fixed, and now pinned by a runtime probe.

**The proofs are mutation-tested.** Each `{==}` is trivial only because the
`Sp.shape` arm *is* the right-hand side. To check that is real and not a
placeholder, each arm is broken in turn and the expected law confirmed to be the
one that fails:

```
reshape  -> L.reshape_preserves_numel        dtype CmpLt -> L.comparison_is_bool
permute  -> L.permute_preserves_numel        dtype Range -> L.range_is_index
flip     -> L.flip_preserves_numel
pad      -> L.pad_numel_is_the_new_shape
shrink   -> L.shrink_numel_is_the_new_shape
```

`spec.bend` restored byte-for-byte after each run.

## The six that stay open, and why

All six are **true and stuck**, not refuted. One limit explains them: Bend's
checker can only decide a law when the fold arm reads **its own fields**. Every
arm that must case-split on *another* node's result sits behind a call and never
reduces.

| open law | blocked on |
| --- | --- |
| `stack_numel_is_the_leading_axis_times_the_operands` | `Shape.prepend` over another fold's result |
| `reduce_numel_divides_by_the_reduced_axes` | `Shape.drop` over another fold's result |
| `broadcast_is_elementwise_max` | `zip_max` over two symbolic shapes |
| `add_is_elementwise`, `mul_…`, `max_…` | `zip_max`, same |

A shape-level law saying `zip_max(s, s) == s` would settle three of them at once.
That is the next thing to try, and it is a real law about the shape algebra
rather than a workaround.

## What it does not buy

**That the count is *right*, only that it is *preserved*.** `numel` conservation
says a view is faithful. It says nothing about whether the destination shape is
the one the caller wanted. That stays a runtime error.

**Anything about the compilation IR.** These laws reach the pure spec datatype,
not `tinygrad/uop/ops.py`, which is a cyclic hash-consed arena and cannot be a
tree.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/LAWS.bend` | the shape laws |
| `tinybendygrad/PROOF.bend` | their proofs, with the mutation-test record |
| `spec/tinyspec.tex` | the prose this replaces |