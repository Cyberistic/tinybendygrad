# Depth: what threading a fuel budget buys us

Every fold in `tinybendygrad/LAWS/spec.bend` — `Sp.shape`, `Sp.dtype` — takes a
`depth: Nat` and spends one unit per level of the tree it walks. This replaced
`@unsafe`.

## What it replaced

The folds were mutually recursive. `Sp.shape` walks the op tree and calls the
shape folds; the shape folds ask `Sp.shape` about a child. Nineteen defs were
marked `@unsafe`, which in Bend means *this recursion is not checked*.

`@unsafe` is Turing completeness with the safety off. It runs, but the gate stays
red and names every def that relies on it. You cannot get `ALL PROOFS CHECK`
past one.

## What we gain

**Termination is machine-checked, not asserted.** A fold walks a finite tree, so
it must stop. `@unsafe` said "trust me". Fuel says "you get `depth` levels, and
at zero the answer is `None`", and the compiler verifies that every recursive
call passes a strictly smaller budget. There is no path where a fold loops.

**No escape hatch to accumulate.** Nineteen `@unsafe` defs is nineteen places a
later change can quietly become non-terminating, and the gate cannot tell.
Zero is zero.

**Running out of budget is visible, not silent.** Past the budget the fold
returns `None`. That is the honest answer for "past this depth I don't know" —
never a wrong shape, never a plausible-looking zero.

**The shape of the code is forced by the checker, and the forcing was useful.**
Bend has no mutual recursion, so `Sp.shape` and the shape folds had to become one
def over a type covering both cases:

```
type Item is Data:
  One{s: Sp}              # a node
  Many{xs: List<&2, Sp>}  # a list, for Index's index list and Stack's operands
```

That is the guide's own prescription, and it happens to be exactly what
`tinyspec.tex` describes: `Index` and `Stack` are the two ops that descend into a
list. The checker forced the datatype to match the spec's shape.

## What it costs

**Every call site passes a depth.** A caller must know the tree's height. The
compiler's arena knows the node count, so twice that is the honest bound. Too
little is not a crash, just `None`.

**Laws must quantify a depth.** A law over all ops cannot supply one fixed
budget, because an arbitrarily deep tree would exceed it and both sides would
degrade to `None == None` — provable and meaningless. So each law carries
`for +depth: Nat` as its first binder and states the property *at that budget*.
23 of the 32 laws changed this way.

## Where it stands

Not finished, and the honest count is worse than "done":

- 22 of 32 laws are open. The gate is red, which is correct — a green gate over a
  weakened law is worse.
- **The `case 2n+p:` arm of both folds is dead.** `case 1n+p:` is matched first
  and matches every successor, so the two-budget arm never runs, fuel decrements
  by one until it hits zero, and both folds answer `None` for every operand. The
  checker accepted the code; the *runtime* is wrong. Fix is arm order.
- **A symbolic depth will not reduce.** `Sp.shape(s, depth)` computes
  `2*depth + 1` before matching, and a `match` cannot open a computed value. So
  a law quantified over symbolic depth has no induction to hang on, even once the
  dead arm is fixed. The entry point has to match on `depth` itself.

Both are recorded here rather than in a commit message because they are the state
of the work, not the history of it.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/LAWS/spec.bend` | the two folds, fuel-parameterised |
| `.agents/slop/notes/bend2-constraints.md` | the four measured facts about the checker |
| `spec/laws.md` | the laws themselves |