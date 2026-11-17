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

**`min_max`, IN PART.** It is interval arithmetic over the same ops and is
exact only where tinygrad says it is. The ARITHMETIC cells (`[a+b, A+B]` and
the rest) need the values, and the port's IR is structural — `one()` and
`zero()` are placeholder consts with no number — so those cells are not stated.

It was **not pinned elsewhere either**, and this file claimed it was: "Pinned by
`test/null/test_uop_vmin_vmax.py` instead — 55 tests that run on CPU." MEASURED
2026-11-17: `tinygrad/test/` is **not vendored** at the pin —
`git ls-tree f5ac54685074 --name-only tinygrad/test` answers 0 — so the column
was pinned by nothing. The two cells that need no number are stated now: the
`"src[0]"` cells and the `"dtype range"` cells.

**The compilation IR.** `tinygrad/uop/ops.py` is a cyclic hash-consed graph in
an arena, because the range graph has back-edges and the test suite depends on
node identity. That cannot be a pure tree, so these laws do not reach it. What
they pin is the semantics every IR must agree on, which is exactly what
`tinyspec.tex` states.

## The gate

```
$ ./bin/bend tinybendygrad/LAWS/PROOF.bend
ALL PROOFS CHECK
```

Red while any law is open. It names the law, not a line number.

**ONE FILE, AND IT WAS THREE BECAUSE OF A CONSTRAINT AND NOT A PLAN.** Bend
discharges a law by a `def` of the same name ANYWHERE IN THE BOOK, and allows
ONE such def per book, so a half-book reports the OTHER half's laws as open:
the shape half alone reported 18 TODOs and the ALU/dtype half 16, and the
aggregate `PROOF-ALL.bend` existed to import both. MEASURED 2026-11-17: the two
halves' sixty defs have NO NAME IN COMMON and neither calls a def declared
later in its own file, so ONE file holds both halves and the aggregate is not
needed. The proof file is now `LAWS/PROOF.bend` and it holds all ninety-eight
laws.

The port states **four of the spec's five derived properties** now — `dtype`,
`shape`, `device` and the value-free half of `min_max`. The fifth, `addrspace`,
has no column in the spec's derived-properties table (only the `ParamArg`
prose), so there is nothing to state.

Two places where the port is **narrower than the spec**, and both say so:

- **Broadcast right-alignment.** The spec says "right-align shapes,
  element-wise max". The port zips from the head, which coincides with
  right-alignment only at equal rank — so the port's broadcast law requires
  `SameLen`.
- **Unshard's shape.** The spec says "src[0], each a_k × n_k" — the source's
  shape with each sharded axis split. The port answers `src[0]` whole.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/LAWS/spec.bend` | ops as a datatype; dtype/shape as functions |
| `tinybendygrad/LAWS/alu.bend` | the decomposition table, as defs |
| `tinybendygrad/LAWS.bend` | the laws |
| `tinybendygrad/LAWS/PROOF.bend` | the proofs: all of them, and the gate |
| `spec/shape-laws.md` | what pinning the element count bought |
| `.agents/slop/notes/bend2-constraints.md` | the Bend rules that shaped all of it |

`spec/depth.md` used to live here. It described a fuel budget that turned out to
be a misreading of the compiler, so it is deleted rather than corrected — the
current folds have no fuel.