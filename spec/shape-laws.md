# Shape laws: what pinning the element count buys us

`tinybendygrad/LAWS.bend` states, as Bend laws, what `spec/tinyspec.tex` says
about shapes — and most of it reduces to one invariant: **a view may not change
how many elements a tensor has.**

## The laws

A `view` is a movement op. `Reshape` reinterprets, `Permute` reorders axes,
`Flip` mirrors, `Pad` grows, `Shrink` narrows, `Stack` adds a leading axis,
`Reduce` removes axes. None of them may add or remove an element. Each gets a law:

```
law permute_preserves_numel:
  for +depth: Nat
  for +t: S.Sp
  for +order: List<&2, S.Nat>
  {numel_of(depth, S.SpPermute{t, order}) == numel_of(depth, t) : Nat}
```

`Reshape` and `Pad` are the interesting ones, because their count is set by
something else — the destination shape — so the law says the count follows the
new shape, and carries tinyspec's own validity condition as a premise:

```
law reshape_preserves_numel:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(t) : Nat}
  {numel_of(S.SpReshape{t, ...}) == numel_of(t) : Nat}
```

The premise is what tinyspec calls a constraint on a well-formed graph. It was
prose. It is now a term the checker discharges.

## What we gain

**A dropped element in a view becomes a compile error.** In Python a view that
reshapes to the wrong element count raises at runtime, on one shape, in one
backend, after the model has already trained. Here it fails `bend --check-only`
on the definition.

**The spec's validity conditions are enforced, not remembered.** A `Reshape` that
changes the count is not "probably fine because the caller checked". It is a law
that fails, naming the op.

**The laws caught a vacuous law of our own making.** `stack_numel_is_the_leading_
axis_times_the_operands` was written as

```
for +ts: List<&2, S.Sp>
{prod_of(stack_dims(ts)) == stack_numel(ts) : Nat}
```

and `stack_numel` was *defined* as `prod_of(stack_dims(ts))`. That asserts
`x == x`. It never mentions `Sp.shape`, never mentions `SpStack`, and constrains
nothing. It would have stayed green forever. Restated over a non-empty Stack with
the operand's shape named, it is strictly stronger and actually exercises the
fold.

**The proofs were mutation-tested.** Each `{==}` proof is trivial only because the
`Sp.shape` arm *is* the right-hand side — `SpPermute`'s arm is literally
`Sp.shape.item(n, One{t})`. To check that is real and not a placeholder, each arm
was broken in turn and the expected law confirmed to be the one that failed:

```
reshape  -> Location: L.reshape_preserves_numel
permute  -> Location: L.permute_preserves_numel
flip     -> Location: L.flip_preserves_numel
pad      -> Location: L.pad_numel_is_the_new_shape
shrink   -> Location: L.shrink_numel_is_the_new_shape
stack    -> Location: L.stack_numel_is_the_leading_axis_times_the_operands
```

`spec.bend` was restored byte-for-byte after each run.

## What it does not buy

**That the count is *right*, only that it is *preserved*.** `numel` conservation
says a view is faithful. It says nothing about whether the destination shape is
the shape the caller wanted. That is the caller's job and stays a runtime error.

**The compilation IR.** These laws reach the pure spec datatype, not
`tinygrad/uop/ops.py`, which is a cyclic hash-consed arena and cannot be a tree.
See `spec/laws.md`.

**Anything past the depth budget.** See `spec/depth.md` — including the fact that
the fold currently answers `None` for everything, because one of its two fuel
arms is dead.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/LAWS.bend` | the shape laws |
| `tinybendygrad/PROOF.bend` | their proofs, plus the mutation-test record |
| `spec/tinyspec.tex` | the prose this replaces |