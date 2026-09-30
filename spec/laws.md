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

**Termination is structural, with no escape hatch.** One recursive def per
property, no mutual recursion, every descent passing a field of its own
parameter. No `@unsafe` and no fuel budget anywhere in the file.

Getting there cost a detour worth recording, because the first design *typechecked
and was wrong*. The folds were parameterised with an explicit `Nat` fuel on the
reading that `case 2n+p:` was an "at least two" case. It is not: numeric patterns
in Bend are first-match prefix matches, so `case 1n+p:` claims every successor and
the pair arm was dead code. Both folds answered `None` for every operand while
reporting clean.

Two measured rules replaced it: a recursive call must pass a **field of its own
parameter**, and re-wrapping a **list tail** in any constructor is rejected
outright (a list *head* binder is fine). Together those mean a fold that maps a
recursive function over a list cannot be written — the head is legal, the tail is
not, and making the tail a field needs a second mutually-recursive def, which is
also rejected. Hence bounded arity for `Index`. All of it is in
`.agents/slop/notes/bend2-constraints.md`, which is what an agent reads first.

**The lesson generalises past this file: a compiler that accepts your code does
not mean the code does what you meant.** Six laws were refuted or found vacuous
during this work, and two of those were bugs in code a type checker had approved.

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
| `spec/shape-laws.md` | what pinning the element count bought |
| `.agents/slop/notes/bend2-constraints.md` | the Bend rules that shaped all of it |

`spec/depth.md` used to live here. It described a fuel budget that turned out to
be a misreading of the compiler, so it is deleted rather than corrected — the
current folds have no fuel.