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

## The spec's own compositions

`tinyspec.tex` writes five common ops as compositions of the primitives:

```python
def gemm(A, B):
  M,K = A.shape; _,N = B.shape
  return (A.reshape(M,K,1) * B.reshape(1,K,N)).sum(1)
```

The port stated the COMPONENTS — the reshape law, the elementwise law and the
reduce law — and not the COMPOSITION. The composition is what the spec's
readers care about, because it is the shape the schedule's fusion decisions
read.

MEASURED 2026-11-17: the gemm's shape claim is now a law, and the claim is
the sharpest part — the two reshapes broadcast, and the broadcast of `(M,K,1)`
and `(1,K,N)` is `(M,K,N)`:

```
law gemm_broadcasts_to_the_three_axis_shape:
  for +m: S.Sdim
  for +k: S.Sdim
  for +n: S.Sdim
  for ma: S.AllSN([m, k, S.SN{1n}])
  for mb: S.AllSN([S.SN{1n}, k, n])
  for same: S.SameLen([m, k, S.SN{1n}], [S.SN{1n}, k, n])
  {shape_of(S.SpMul{S.SpReshape{...}, S.SpReshape{...}})
   == some_of_shape(S.Shape.of([m, k, n])) : Maybe<&2, S.Shape>}
```

**THE PROOF IS A CHAIN OF CONGRUENCES, ONE PER AXIS**, and each congruence's
function fixes everything EXCEPT the axis it rewrites. The port's `cons_tail`
appends a fixed tail, so its argument is the head; the port had no cons that
fixes a head AND a tail, so two were added — `cons_mid` for the middle axis
and `cons_at` for a general position. The three are chained with two
`Equal.trans` steps, and the whole list is then lifted through `Shape.of` and
`Some`.

**AND THE SECOND ONE IS THE GATHER**, and its claim is the NET SHAPE — `(D,)`,
the gather axis, which is `idx`'s length and not `T`'s:

```
# gather: out[i] = T[idx[i]]. one-hot mask along gather axis, then reduce
def gather(T, idx):
  K = T.shape[0]
  pos = arange(K).reshape(K, 1)                     # (K, 1)
  mask = (pos == idx.reshape(1, -1)).cast(T.dtype)  # (K, D)
  return (T.reshape(K, 1) * mask).sum(0)            # (D,)
```

Its two broadcasts are `(K, 1)` with `(1, D)` and `(K, 1)` with `(K, D)`, and
the reduce drops the first axis. **AND THE PROOF IS A `%` USE**, and that is
the shape of a proof that *rewrites* rather than *adds* — see
`.agents/slop/loc/bend-proof-rules.md`. The evidence is the reduce of the
product's shape; its right endpoint is the goal's right-hand side, so the use's
fit check passes; and its left endpoint becomes the new goal, which the
construction's congruence closes.

**AND THE THIRD ONE IS THE SCATTER_ADD**, and its claim is the broadcast's
shape — `(K, D)` — which is *the same shape fact as the gather's mask*,
because the two masks are the same pair of shapes:

```
# scatter_add: T[idx[i]] += val[i]
def scatter_add(T, idx, val):
  K, D = T.shape[0], idx.shape[0]
  pos = arange(K).reshape(K, 1)                     # (K, 1)
  mask = (pos == idx.reshape(1, D)).cast(T.dtype)   # (K, D)
  return T + (mask * val.reshape(1, D)).sum(1)      # (K,)
```

**AND ALL FIVE CLAIMS ARE ABOUT THE BROADCAST AND NOT ABOUT THE REDUCE, AND
THAT IS A MEASURED CONSTRAINT RATHER THAN A CHOICE.** Reading the pin's spec:
`gemm` reduces axis 1 of a *three*-axis shape, `prefix_sum` reduces axis −1,
`arange` goes through `prefix_sum`, `gather` reduces axis 0, and `scatter_add`
reduces axis 1. **So ONLY the gather reduces the FIRST axis — and the port's
`SpReduce` drops the first `k` axes.** The reduce's axis is therefore a
separate matter from the broadcast's shape, and the broadcast's shape is the
part both agree on.

**AND THE FOURTH AND FIFTH ARE NOW STATED TOO**, and they needed no arithmetic
lemma at all:

```
# prefix_sum: cumulative sum via repeat+reshape sliding window trick
def prefix_sum(T):
  n = T.shape[0]
  x = T.pad((n-1, 0))                            # (2n-1,)
  x = x.reshape(1,2*n-1).expand(n+1,2*n-1)       # tile
  x = x.reshape((n+1)*(2*n-1)).shrink_to(2*n*n)  # trim
  x = x.reshape(n,2*n).shrink_to(n,n)            # windows
  return x.sum(-1)                               # reduce

# arange: prefix_sum of all 1s gives [1,2,...,n], subtract 1 for [0,1,...,n-1]
def arange(n):
  return prefix_sum(Tensor(1).reshape(1).expand(n)) - 1
```

**AND THE ARITHMETIC IS A DIM, NOT A PROBLEM.** A dim may hold an arithmetic
term — MEASURED, `S.dim_of(S.SN{Nat.mul(a, b)})` is `Nat.mul(a, b)` — so the
spec's `2n-1` and `(n+1)*(2n-1)` are STATED DIRECTLY, and the folds answer
them without a `Nat.mul` lemma. The `Nat.mul` wall this file recorded earlier
was in the *product* of the dims, and the products are not needed here.

**AND THE ARANGE's CLAIM NEEDS NO BROADCAST LEMMA EITHER, AND THAT IS MEASURED
TOO.** Its subtract broadcasts `(n,)` with `()`, and the lengths are UNEQUAL —
and the port's `elem_pick` truncates at the shorter list while `zip_max` keeps
the longer one's remainder, so the port's `bcast_axes` lemma does NOT apply.
But `zip_max([n], [])` is `[n]` by `zip_max`'s own rule, so the claim is
definitional.

**AND BOTH ARE LOAD-BEARING, MEASURED NOT ASSUMED.** A law that cannot go red
is worse than no row, so the mutation test is in
`.agents/slop/loc/comp-mutate.py`: it builds a book holding ONE law — the
gemm's or the gather's — with its proof and the port's own helpers, and breaks
the broadcast's per-axis fold. The book goes red, and the failing def is
inside the book, so the failure is that law's own proof and not a neighbour's.

That isolation was needed, and the reason is general: **the checker reports
the FIRST failing proof, not all of them.** Mutating a shared fold arm is
named by whichever law happens to be checked first, so "the suite went red"
is not "this law is load-bearing". Three readings established it — mutating
`Shape.max_dim`'s concrete arm named `L.max_dim_idempotent` (a neighbour),
mutating `pick_dim`'s `a == 1` arm named `pick_dim_one_left` (a helper), and
mutating a helper's own statement named the helper (the claim itself was
changed, so nothing was tested). The isolated book removes the neighbours, and
then the law names itself.

## The index family

`tinyspec.tex` gives `Index` a prose column and a shape column:

> Index from left. `()`-shaped `i` removes dim.

and the shape column says **remaining dims**. MEASURED 2026-11-17: the shape
census named `SpIdx2`, `SpIdx3` and `SpIdx4` **unpinned** — no law named
them — and the blocker was recorded as the PROOF, not the claim: *"the shape of
an `Idx2` is the zip of the two index shapes with the base's dims after
dropping two, and proving that needs the same induction the broadcast law
needs — the zip's shape and the drop's shape together."*

**AND THE BLOCKER WAS A FOLD THAT IS NOT THERE.** The shape fold is

```
Sp.shape.index(pre, bt, k) = Some{Shape.of(List.append(index_dims, drop_n(base_dims, k)))}
```

— a CONCATENATION and a DROP. Neither is a zip, so no induction is needed and
each arity is one step. Four laws now state it, one per arity:

```
law index_one_with_an_empty_shape_removes_the_base_dim:
  for +t: S.Sp
  for +a: S.Sp
  for +st: S.Shape
  for +pt: {shape_of(t) == Some{st} : Maybe<&2, S.Shape>}
  for +pa: {shape_of(a) == Some{S.Shape.empty()} : Maybe<&2, S.Shape>}
  {shape_of(S.SpIdx1{t, a}) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 1n))} : Maybe<&2, S.Shape>}
```

**AND THE `()`-SHAPED INDEX IS THE SPEC's OWN SENTENCE.** The premise says the
index's shape is `Some{Shape.empty()}` — the empty shape, which is the spec's
`()`. So the claim is the spec's: an index whose shape is `()` removes a dim,
and what remains is the base's remaining dims.

**AND THE PROOF IS A CASCADE OF `%` USES, ONE PER PREMISE.** Each use replaces
one slot of the fold's `pre` with the HOLE, and the next use's motive carries
the replacement — so the fit check is the goal. The `%`-use semantics are in
`.agents/slop/loc/bend-proof-rules.md`.

**AND THE CENSUS's OWN MUTATION HAD TO BE FIXED, AND THE DEFECT WAS REAL.**
The census breaks a law's subject to see whether the law goes red. For a shape
arm it replaces a unary passthrough `Sp.shape(x)` with `Some{Shape.empty()}` —
the same type, a different answer. But `Some{Shape.empty()}`'s type parameter
is **not inferable at an assignment**, so when the replacement landed in a
local (`p = Sp.shape(a)` — the `SpIdx1`..`SpIdx4` arms) the copy STOPPED
TYPECHECKING and the gate went red naming **no law**. The census reported all
four new laws VACUOUS — not because they could not fail, but because the
mutation did not typecheck. MEASURED: the `SpStack`, `SpReduce`, `SpAdd` and
`SpMul` arms were unaffected, because their replacement lands where the type
is already pinned.

The fix is to pin the local's type in the mutation (`p: Maybe<&2, Shape> =
Some{Shape.empty()}`), and after it the four laws are **RED** — the gate names
each of them. The census's own docstring forbade this ("a mutation that made
the file ill-typed would redden the gate for the wrong reason"); the mutation
was doing exactly that, and only the new laws exposed it.

## The ordering ops, and the spec fold was wrong

MEASURED 2026-11-24: the shape census named FIVE arms unpinned — `SpEnd`,
`SpBackedge`, `SpGroup`, `SpSink` and `SpLinear` — and the census's word for
an unpinned arm is *"the arm may be wrong and the book says nothing"*.

**AND ONE OF THEM WAS.** The spec fold said `End` has NO shape and NO dtype.
The pin says otherwise, twice:

- `ops.py:143` — the "pass through first" arm lists `Ops.END`, so
  `dtype_from_uop(Ops.END, src, arg)` is `src[0].dtype`.
- `ops.py:371` — the passthrough arm lists `Ops.END`, so `_shape` is
  `self.src[0]._shape`.

and `ops.py:316-319` — the "late ops don't have shape" list — names `SINK`,
`BACKEDGE` and `LINEAR` but **not** `END`. So `End` is a passthrough and the
other three are shapeless.

**AND THE PORT'S OWN IMPLEMENTATION ALREADY AGREED WITH THE PIN AND NOT WITH
THE SPEC FOLD.** `tinybendygrad/uop/fold.bend:1761` reads
`case O.OpsEND{}: thru0(ss)` — passthrough of dtype AND shape — and
`thru0` is `dt_of(src_dt(0, ss), src_shape(0, ss))`.

**AND THE CORPUS PROVES IT, BYTE-IDENTICAL.** The canonical form prints the
two facts apart: `runs/graphcmp/D/D2-canon-bend-lin.txt:48` reads
`3:i48 3:END 4:void 2:()` — dtype `void`, shape `()` — while the `SINK` on
the next line reads `1:R` for its shape, and `R` is "no shape". So
"no shape" and "the empty shape" are two facts, and upstream's `END` has the
empty one. And `i48`'s `src[0]` is a `STORE` with shape `()`, so `END`'s
shape is its body's — measured, not inferred.

So the fold was corrected, and five laws now state the ordering ops' shape:

```
law end_preserves_shape:
  for body: S.Sp
  for ranges: List<&2, S.Sp>
  {shape_of(S.SpEnd{body, ranges}) == shape_of(body) : Maybe<&2, S.Shape>}

law sink_has_no_shape:
  for ss: List<&2, S.Sp>
  {shape_of(S.SpSink{ss}) == none_of_shape() : Maybe<&2, S.Shape>}
```

**AND `SpGroup` HAS NO UPSTREAM OP AT ALL** — upstream deleted `Ops.GROUP`
(`4e0192eaf remove Ops.GROUP (#18637)`) — so the port's `Group` is a STACK of
AFTERs, and a STACK has no shape column here.

## Every law is now tested by exactly one census

MEASURED 2026-11-24, and this was a hole in the tree's own rule. The two
census gates divide the laws by their `LAWS.bend` SECTION, and the rule read
the section with `^# ([IVX]+)\. ` — which **misses every sub-section header**
(`V-bis`, `V-ter`, `V-ter-bis`, `V-quater`, `VI-bis`). A law under one of them
inherited the *previous* section, and the split was wrong in both directions:
`V-bis`'s three shape laws landed in the ALU half, and `VI-bis`'s seventeen
laws landed in the shape half by luck.

**ELEVEN LAWS WERE TESTED BY NEITHER CENSUS** — four of the five composition
laws, both reshape numel laws, four shape laws and one ALU law. So the tree's
"every law must be load-bearing" rule was not enforced for them.

**AND THE FIX IS A DECLARATION RATHER THAN A LIST**, because a list of section
names in a gate is a hand list and a hand list rots: each section header now
says which half it is, and both gates read `gatekit.law_half`.

```
# V-bis. THE PASSTHROUGH OPS' SHAPE, and the spec says so in words. -- HALF: shape
```

**AND THE CENSUS's OWN INSTRUMENTS HAD THREE MORE HOLES**, all exposed by
laws that had never been testable:

- `goal_of` took "the last line that starts with `{` and ends with `}`", and
  the gemm's conclusion is **three lines** — so the subject was `None` and the
  law was reported `NO-SUBJECT`. The goal is now found by its braces.
- The subject finder could not see a law that concludes on a
  *premise-bound* variable (`shape_of(out) == …`), which is four of the five
  composition laws. The premise says what the variable is, and the subject is
  now read from it.
- `mutate_definition` required a **one-line** body, and `alu.bend`'s
  `truncmod` is four — so its law was reported `NO-MUTATION`.

**AND TWO ARMS COULD NOT BE MUTATED AT ALL**: `SpBuffer` and `SpAlloc` are
`Some{Shape.of([SN{size}])}` — a list literal, and the rule wanted a bare
word — and `SpConst` and `SpRange` are `Some{Shape.empty()}`, which no rule
reached. All four are now mutated and their laws are RED.

**MEASURED, AFTER:** `43 shape laws, 53 shape fold arms` and `66 ALU/dtype
laws`, and **every one of the 109 laws is tested by exactly one census** —
0 untested, 0 unpinned arms.

**AND THE ALU PLANT's CASE 4 WAS A DEAD LANE, AND IT IS FIXED.** Its claim is
"breaking an arm no law reads leaves the gate green", and every arm is now
read by a law, so the control had nothing to break and printed "NO UNPINNED
ARM". The control now *makes* such an arm by removing the law that reads it.
**AND AT HEAD THAT CONTROL WAS FAILING FOR A DIFFERENT REASON** — it broke
`SpEnd` and the gate went RED, proving the census's "unpinned" verdict for
`SpEnd` was wrong. It is now pinned by a law, and the control is GREEN.

## A failure in a helper is not a law failing

MEASURED 2026-11-24: the ALU census's `--plant` had one red row since
2026-11-23 — *"the mutated copy did not go red naming
`neg_is_mul_by_minus_one` (rc=1, named=None)"*. And the reading recorded at
the time was wrong in three places: it said the mutation "is not landing on
the subject it claims to", and that the law's proof being `{==}` explained
the failure.

**None of that was true. The mutation lands exactly on its subject, the law
is present, and the law is load-bearing.** The reason is that `bend` reports
the FIRST failing proof, and the first failing proof was a **helper**:

```
Location: alu_neg_one_eq
1134 |   def alu_neg_one_eq() -> {A.neg(A.one()) == S.SpMul{A.one(), A.one()} : S.Sp}:
```

A failure in a helper is not a law failing — and it is not "no law failed"
either: the row said "no law" because the failure's `Location:` named a def
and not a `L.` law.

**AND THE HELPER WAS UNNECESSARY.** `alu_neg_one_eq` stated
`A.neg(A.one()) == S.SpMul{A.one(), A.one()}`, and `A.neg(a)` is
`S.SpMul{a, one()}` — so at `a = A.one()` the fact is **definitional**. The
arange proof's `c2` step closes with `{==}` directly. The helper went, and
with it went the "failure in a helper" class: a LOC reduction and a class
removal at once.

**AND WHAT REMAINED WAS A MASK, AND THE ALU CENSUS NOW ASKS IT.** The arange
law reads `A.neg(A.one())` and `neg_is_mul_by_minus_one` reads `A.neg(a)`, so
they share the subject, and the arange law comes first in the book. The ALU
census now masks exactly as the shape census does — remove the masking law,
re-check — and the law is **MASKED**: the gate goes red naming the arange
law, and with the masker removed it names `neg_is_mul_by_minus_one`. **So the
law can fail; it is just not the failure `bend` reports first.**

**AND THE PLANT's CLAIM WAS ASSERTING SOMETHING THE BOOK's ORDER MAKES
FALSE.** It said "must redden naming **its** law", and for this law that is
not satisfiable while the arange law comes first. A plant that asserts
something false is not a control, so it now asserts the claim that is true:
the law must be **reachable**, masked or not.

**AND THE FIVE `vacuous-on-mask` LAWS REMAIN, AND THEY ARE A DOCUMENTED
STRUCTURAL LIMIT.** `A.one()` and `A.zero()` are the same term — both are
`S.SpConst{S.SpInvalid{}, S.index()}` — because the spec IR is structural and
its consts carry no number, which is also why the spec's `min_max` arithmetic
cells are not stated.

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
needed. The proof file is now `LAWS/PROOF.bend` and it holds all 109 laws —
MEASURED 2026-11-24 by `.agents/slop/laws17/laws.py`: `109/ 0/109` in
`LAWS.bend` and `0/109/109` in `PROOF.bend`.

**THE ORDER OF THE BOOK IS PART OF THE SPEC, AND MEASURED 2026-11-17.** `bend`
names the FIRST proof that fails, so an instrument that asks "which law goes
red" reads the book's order. The gemm law -- the spec's own "Common Ops as
Compositions" -- sat BEFORE the elementwise laws, and that made
`mul_is_elementwise` **masked**: both laws read `SpMul`, so a broken `SpMul`
named the gemm law and the elementwise law was never the failure reported.
The gemm proof now comes AFTER the elementwise proofs, the shape census is
green with the same three masked laws it had before, and the reorder is a pure
one -- the two laws are independent, one is about the broadcast of two
reshapes and the other about two operands of the same shape.

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
| `gates/shape-law-census-gate.py` | the law census: can each shape law go red? |
| `.agents/slop/loc/comp-mutate.py` | the composition laws' isolated mutation test |
| `.agents/slop/notes/bend2-constraints.md` | the Bend rules that shaped all of it |

`spec/depth.md` used to live here. It described a fuel budget that turned out to
be a misreading of the compiler, so it is deleted rather than corrected — the
current folds have no fuel.