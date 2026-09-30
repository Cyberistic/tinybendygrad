# Laws: what we gain

The spec used to be prose. `spec/tinyspec.tex` says what every op's dtype, shape
and device are, in LaTeX tables, and nobody checked it against the code. We wrote
it as Bend types plus laws instead, so the checker reads it.

## What tinyspec.tex claims

Every op has five derived properties. `Add` has the shape of the broadcast of its
two inputs. `Reshape` may not change the element count. `CmpLt` produces `bool`.
`Store` produces nothing. `Permute` reorders axes and keeps the count.

## What we wrote

`tinybendygrad/LAWS/spec.bend` — the ops as one datatype, and the five properties as
functions over it. Total, so a missing case is a type error rather than a crash
at 3am on a GPU.

`tinybendygrad/LAWS/alu.bend` — the table of ops that are *defined* in terms of
others. `Sub(a,b) = Add(a, Neg(b))`. `Div(a,b) = Mul(a, Recip(b))`. `CmpGt(a,b)
= CmpLt(b,a)`. `CmpEq(a,b) = CmpNe(CmpNe(a,b), 1)`. `Sqrt(a) = Exp2(0.5 *
Log2(a))`. Sixteen rows, written as defs, so each row is a definitional equality
the compiler can discharge.

`tinybendygrad/LAWS.bend` — the laws themselves. Each names the paragraph of
`tinyspec.tex` it comes from.

## What we gain

**The decomposition table stops being a comment someone might typo.** If the port
ever changes how `CmpEq` is built, `tinybendygrad/LAWS.bend --check` fails and names
the op. It was previously only true because someone read the table carefully
once.

**The spec's constraints become proof premises, not comments.** `Reshape` is
legal only if `prod(shape) == prod(dst)`. In Bend that is a `for` clause carrying
its own proof:

```
law reshape_preserves_numel:
  for +t: S.Sp
  for +dst: List<&2, S.Sdim>
  for +premise: {prod_of(dst) == numel_of(t) : Nat}
  {numel_of(S.SpReshape{t, ...}) == numel_of(t) : Nat}
```

The premise is what the spec calls a validity condition. It is now something the
checker discharges, not something a reviewer has to remember.

**Missing cases are compiler errors.** The datatype enumerates the ops. A new op
added to the port but not to `spec.bend` fails to typecheck until the fold grows
a case for it. In Python that was a `KeyError` on a shape that only some shape
reaches.

**Termination is explicit.** Both folds take a fuel budget and spend one per
level. Too little fuel returns `None` — "past this depth I don't know" — instead
of a wrong shape. There is no `@unsafe` anywhere in the file, so nothing escapes
the check.

## What we do not gain, and why

**Float arithmetic.** Bend's guide is blunt: `F32` is axiomatic, nothing about
floating point can be proven. A law about `exp` would be a claim the checker
cannot decide, which is worse than no law. The transcendental ops are carried as
their names plus the log2/exp2 decomposition, which *is* provable. The numerics
stay pinned by tinygrad's own pytest suite.

**The Codegen ops.** tinyspec says of them: "these ops are not part of the core
specification and are subject to change." We left them out on the spec's own
instruction.

**`min_max`.** It is interval arithmetic over the same ops and is exact only
where tinygrad says it is. Pinned by `test/null/test_uop_vmin_vmax.py` instead —
55 tests that run on CPU.

**The compilation IR.** `tinygrad/uop/ops.py` is a cyclic hash-consed graph in
an arena, because the range graph has back-edges and the test suite depends on
node identity. That cannot be a pure tree, so these laws do not reach it. What
they pin is the semantics every IR must agree on, which is exactly what
`tinyspec.tex` states.

## The gate

```
$ ./bin/bend tinybendygrad/PROOF.bend
ALL PROOFS CHECK
```

Red while any law is open. It names the law, not a line number.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/LAWS/spec.bend` | ops as a datatype; dtype/shape as functions |
| `tinybendygrad/LAWS/alu.bend` | the decomposition table, as defs |
| `tinybendygrad/LAWS.bend` | the laws |
| `tinybendygrad/PROOF.bend` | shape half |
| `tinybendygrad/PROOF2.bend` | ALU/dtype half |
| `spec/depth.md` | what the fuel budget bought, and what it costs |
| `spec/shape-laws.md` | what pinning the element count bought |
| `.agents/slop/notes/bend2-constraints.md` | the Bend rules that shaped all of it |