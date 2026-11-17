# How a Bend proof actually works

MEASURED 2026-11-17, from `references/bend/bend2/bend.ts` and confirmed by the
Lean kernel at `references/bend/bend2/bendtt.lean`. A proof here is written by
hand and the syntax is not guessable, so this file records what the checker
does.

## The five verdicts, and the one that matters here

`PASS`, `FAIL`, `SKIP`, `DEAD`, `REFUSED` — the tree's own vocabulary. A proof
that does not compile is `FAIL`, and its message says *what* it wanted.

## The `%` use: a REWRITE of the goal, not a side fact

```
%e : P; f
```

parses (`bend.ts:1915-1940`) to

```
Rwt(e, Lam("_", xi, Lam(k, ei, P, s), s), f, s)
```

and the checker (`bend.ts:3793-3815`) does:

| step | what it does |
| --- | --- |
| the evidence | `e` must have type `{a == b : T}` after weak-head normalisation |
| the motive | checked against `@_ : T -> @e : {a == _ : T} -> Type`, so `_` is the evidence's LEFT endpoint and the motive may return any type |
| the fit check | `b_gol = P(b, e)` and `term_compare("LE", book, b_gol, ty, d)` — `b` is the evidence's RIGHT endpoint |
| the new goal | `a_gol = P(a, {==})` — the motive applied to the evidence's LEFT endpoint — and the body `f` is checked against it |

**So the rule a proof is written by is:**

> The motive is **the goal, with the right-hand side replaced by the hole**.

The hole `_` is a real binder, fresh per use, and **all `_` in one motive are
the same hole**. The new goal always has the evidence's LEFT endpoint
substituted where the hole was.

### The three examples in `base.bend`

| def | evidence | motive | fit check | new goal | body |
| --- | --- | --- | --- | --- | --- |
| `Equal.cong` | `e : {a == b : A}` | `{f(a) == f(_) : B}` | `{f(a) == f(b) : B}` = the goal | `{f(a) == f(a) : B}` | `{==}` |
| `Equal.sym` | `e : {a == b : A}` | `{_ == a : A}` | `{b == a : A}` = the goal | `{a == a : A}` | `{==}` |
| `Equal.trans` | `bc : {b == c : A}` | `{a == _ : A}` | `{a == c : A}` = the goal | `{a == b : A}` | `ab` |

`Equal.trans`'s motive is worth reading twice: its LEFT side is the **goal's**
left side and its hole takes the **evidence's** left endpoint. That is why the
body is `ab` and not `bc`.

### There is NO SEARCH

`bend.ts:3816-3832` is the fallback: a bare term is inferred and accepted iff
its type fits the goal. **The checker never picks a fact for you.** The
"expected / observed" error names the LOCAL it found instead — so it names the
first fact whose type does not match, which is why a proof can be *almost*
right and still fail.

### `{==}` closes only what is definitionally equal

`bend.ts:3771-3783`: the goal must be an equation, and its two sides must
compare `EQ` — tried once with every def rigid, then once with unfolding.

### The rewrite is goal-only

A `%` use rewrites the GOAL; it does not rewrite hypotheses. The idiom for
transitivity is: rewrite the goal until it becomes the other hypothesis's
type, then hand back that hypothesis.

### A `%` use by a `{==}` reduces to its body

`bend.ts:2949-2956` — so `%e : P` where `e` computes to `{==}` is just its
body.

## Other forms of the motive

The motive's *result* type is unconstrained — it is `Type` — so it may return
an equation, `Unit`, a type family, or a type.

- `clash.at(A, _)` — the "refute a clash" idiom: `b_gol` is `A` (the goal),
  `a_gol` is `Unit`, and the body is `Unit{}`.
- `%e@E : P` — the **explicit** motive: `E` binds the evidence as a NAME, so
  the motive can mention the proof term itself, not just the endpoints. The
  grammar is `"%" (Name "@")? Term ":" Term ";"? Body`.
- `%e : &j: Nat -> {...}` — the hole can be inside a pair's second component.
- A motive whose result type is a pair: `P` may return `A & B`, so the goal must
  fit that pair.

## The rules a proof is written by, in one list

1. **A def must be IMPLEMENTED BEFORE IT IS USED** (`bend.ts:3422`). A helper
   used before its definition is REFUSED with "a def whose body is implemented
   before the def is used (defs are checked in file order, and an unfilled law
   has none)".
2. **A binder may be READ TWICE only if it is bound with `+`** — and a `Type`
   binder is not a `Data` one, so `for ca: S.AllSN(...)` comes LAST among a
   law's binders.
3. **A binder cannot be MATCHED after a local statement.** The `%` use must
   come last in a branch.
4. **A value read twice needs `+`.** A consumed fact cannot be read again:
   "consumed more than once" is the error.
5. **A list literal cannot appear in a premise.** A premise's braces end at
   the literal's own braces — MEASURED, `{a == [S.SN{k}] : ...}` is a parse
   error ("expected: '}', observed: ']'") and the same list inside a CALL is
   not. `S.Shape.of([...])` works where `[...]` does not.
6. **A bare `h <> t` in a call argument or a local's right-hand side is
   "cannot infer"** — the operator needs its type spelled out, and the port's
   `snoc` is the typed cons.
7. **A `match` cannot scrutinise a computed value** — bind it first.
8. **A def that fills a law needs no return type**; a def that does not fill a
   law must supply its own `-> T`.

## What the port's own proofs look like

`LAWS/PROOF.bend` is the worked example, and `L.broadcast_is_elementwise_max`
is the model:

```
def L.broadcast_is_elementwise_max(a, b, sa, sb, pa, pb, same, ca, cb):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{sa}, pa)
  %spa : {S.dims_zip_max(_, S.Sp.shape(b)) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{sb}, pb)
  %spb : {S.dims_zip_max(Some{sa}, _) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  ih = bcast_axes(S.Shape.to_dims(sa), S.Shape.to_dims(sb), ca, cb, same)
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(...), S.elem_pick(...), ih)
  Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(...), S.Shape.of(...), c1)
```

**AND THE ORDER IS PART OF IT: the `%` USES COME FIRST, right after the
`Equal.sym` that makes the equation, and the congruences come after.** The
use's motive is "the goal with the right-hand side replaced by the hole", and
in this def the goal IS that shape — so the use's fit check passes.

**AND THE LAST EXPRESSION IS THE GOAL.** A local is a fact; the body ends with
an expression whose type is the def's LHS, and that expression is what the
checker checks.
