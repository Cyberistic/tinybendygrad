# Bend 2: the constraints that decide how tinygrad gets ported

Everything here was **measured** against the pinned checkout in `vendor/bend`
(bend 2.0.34), not read off the docs. Where the docs and the compiler
disagree, the compiler wins. Every claim has a reproducer.

Reproduce anything here with:

    ./bin/bend FILE.bend              # check, then run main (interpreted)
    ./bin/bend FILE.bend -o FILE      # compile to a native binary, run it
    ./bin/bend FILE.bend --check-only # check only
    ./bin/bend PROOF.bend             # the laws gate

---

## 1. The five rules that shape every line of the port

### 1.1 Affinity: a value is used at most once

The default binder `x: T` means *Lone* — at most one use. Reusing it is a
type error:

    def c2():
      TLam{f => TLam{x => TApp{f, TApp{f, x}}}}
    #| - expected : f
    #| - observed : f (consumed more than once)

* `+x: T` licenses many uses, but **only if `T` is `Data`**. It costs a
  runtime reference count, not a copy.
* `Type`-kinded things are *never* copyable: function values, `Array<T>`,
  every handle (`File`, `Socket`, …), `IO<A>`, and any datatype declared
  `is Type` — regardless of what its fields are.
* Dropping a value is free. Only *reusing* one is an error.
* Matching a `+` value hands out `+` fields. To make a field of a plain
  value reusable, write `+name` in the pattern.

tinygrad reuses values constantly (`self.src[0]` twice, a UOp in two
dicts), so this is the #1 source of port friction and the #1 thing for a
reviewer to check.

### 1.2 Scrutinees follow binder order

**This is the trap that costs the most time.** A `match` may inspect a
parameter or a pattern binder, never a projection and never a computed
value — *and the scruts must be matched in the order they were bound.*

    type Dt is Data:
      Dt{pri: U32, bits: U32, sgn: Bool, fl: Bool, nm: String}

    # FAILS: fl is field 4, sgn is field 3 -- out of order
    match d:
      case Dt{pri, bits, sgn, fl, nm}:
        match fl:            # <- 4th
          case False{}:
            match sgn:       # <- 3rd, rejected
    #| - message : a match on a parameter or field
    #|             (this name is a def or a consumed binder: give the value its own def)

    # WORKS: in binder order
    match sgn fl:            # <- 3rd then 4th
      case True{} True{}:  None{}
      case True{} False{}: Some{bits}
      case False{} True{}: None{}
      case False{} False{}: Some{0}

Matching **two fields at once** (`match a b:` / `case P Q:`) is the
idiomatic fix, and the checker verifies the rows are exhaustive.

Related, same family:

* A projection (`d.fl`) is not a valid scrutinee — destructure first.
* A computed value is not a valid scrutinee (`match f(x):`). Give it its
  own `def` and match the parameter.
* A `let`-bound name is not a valid scrutinee either.
* A `match` **must head the def body**. It cannot appear inside a `do`
  block: hoist the match out, and return a `do` block from each arm.
* A nested `match` inside a `case` arm is fine.

### 1.3 Operators need their type in the enclosing parens

    (a + b : U32)      # U32.add(a, b)
    (a .&. b : U32)    # U32.and  -- bitwise is DOTTED
    (a << n : U32)     # U32.shln -- the shift count is a Nat
    (a >> n : U32)     # U32.shrn -- LOGICAL; saturates to 0 past 31

Braces do **not** namespace: `{2n * 3n : Nat}` is rejected. A bare operator
is rejected. Space both sides — `>>` glued to a non-space never fires, and
`+`/`-` glued to a name heads a binder, which is why `1n+p` is a `Nat`
literal and not addition.

### 1.4 No `if`, and no `return` in a pure def

`if` is an ordinary identifier now. A branch is a `match` on `True{}` /
`False{}`, usually in its own helper. A pure `def` body is just a term;
`return` only exists inside a `do` block.

### 1.5 Recursion must visibly descend

The checker requires each argument of a self-call to be passed unchanged
until one is a structurally smaller part of its parameter. Almost no
tinygrad loop satisfies this, so the escape is:

    @unsafe                      # on its OWN LINE, above the def
    def fib(n: U32) -> U32:      # or the sugar `def fib?(n: U32) -> U32:`
      ...

`@unsafe` also lifts mutual recursion and the "call a def declared below
me" restriction. A file using it prints `SOME PROOFS FAIL` and names every
def that relies on it — that is the price, and it is the right one, because
it is greppable. **Every `@unsafe` must be recorded in `AFFINITY.tsv`** with
why the termination check cannot apply, and a reviewer must reject any new
one that is not on the list.

`bend f.bend -o f` compiles `@unsafe` code happily; only the *check*
complains.

---

## 2. The numeric situation: this is the good news

Bend has **only `Nat`, `U32`, `F32`**. No signed integers, no 64-bit, no
`f16`/`f64`. But:

**`F32` arithmetic works natively.** The `law F32.add: ...` declarations in
`base.bend` are not missing implementations — they are *axioms* the
compiler recognises and emits as intrinsics. Verified:

    F32.add(1.5, 2.25) = 3.75      F32.sqrt(2.0) = 1.4142135
    F32.div(1.0, 0.0)  = inf       F32.exp(1.0)  = 2.7182817
    F32.log2(8.0)      = 3          F32.sin(0.5)  = 0.47942555
    F32.bits(1.0)      = 1065353216  F32.to_u32(2.9) = 2
    U32.to_f32(3)      = 3          F32.is_lt(1.5, 2.25) = True

So the whole float layer is free. Two consequences:

* **F32 laws are unprovable.** The guide is blunt: "F32 is axiomatic:
  nothing about floating point can be proven." So `LAWS.bend` must not
  claim anything about `F32` arithmetic, `exp`, `log`, `sin`, … It can
  claim things about *shape* and *structure*, which is where the spec's
  content actually is. Stated as a rule in the master plan.
* **Bend's own `F32` laws cannot be filled from outside** — `def F32.add`
  is a duplicate declaration, and `def Base.F32.add` is "no law named
  Base.F32.add is in scope". So do not try; just use them.

`Nat` is **unary** (`Zero{}`/`Succ{pred}`) and capped at 2^48-1. It is fine
as a small tag and a recursion counter, and a wrong choice for tensor
indices. `U32` it is, with `Nat` only where the spec is naturally
symbolic (axis numbers, sizes, `Nat` in the `lawof` positions).

Integer semantics, all verified or read off the intrinsics:

* `U32.add/sub/mul` **wrap** mod 2^32. `U32.sub(0, 1) = 4294967295`.
* `U32.div(a, 0) = 0` and `U32.mod(a, 0) = a` — the dividend, not a trap.
  This matches tinygrad's `floordiv`/`floormod` on a zero divisor, but it
  does **not** match C, so generated C must guard.
* `U32.shl/shr` shift by one; `shln/shrn` take a `Nat` and saturate to 0
  past 31. **Both are logical** — there is no arithmetic shift, which
  `divides`/`const_factor`/`_min_max` all need. Write `asr` by hand:

      def asr(+v: U32, n: Nat) -> U32:
        U32.or(U32.shrn(v, n), U32.shrn(U32.shrn(v, 31n), n))

* No rotate, no popcount, no leading/trailing zeros. `U32.log2` exists.
  `threefry` and the SHA/KECCAK round need these; they get written.

## 3. The collections situation

* `List<T>` is a singly-linked list. `List.length(a, -A, xs)` takes the
  **quantity as the first argument**, so `List.length(&1, U32, xs)` and
  `List.length(&2, U32, xs)` are different calls. Easy to get wrong.
* `Map` is string-keyed only. You cannot key it by `U32`. For a UOp arena
  keyed by node index, use an `Array` of options, not a `Map`.
* `Array<T>` is a persistent balanced tree (`ALeaf`/`ANode`), **not** a
  flat buffer. `a[i]` is `Array<U32>`-only and wraps the index; other
  element types need `Array.get`/`Array.swap`/`Array.set`. `Array.clone`
  is the explicit deep copy. It is `is Type`, so it has exactly one owner
  and can never be duplicated for free.
* **`Maybe<&2, T>` demands a `+` (reusable) payload.** If the payload is
  affine, use `Maybe<&1, T>`. Getting this backwards produces a misleading
  "a match on a parameter or field" error several lines away from the real
  cause. This cost real time; it is listed here so it costs nobody else
  time.

## 4. Effects, and where tinygrad's `runtime/` lands

A foreign effect is a `def` returning `IO(R)` whose whole body is two
imports:

    def Clock.now() -> IO(U32):
      import "./clock.c"
      import "./clock.js"

Verified working in both lanes (`bend f.bend` and `bend f.bend -o f`).
Rules that matter:

* The **return type must be spelled `IO(...)`** — "return type aliases are
  not unfolded". So an effect cannot return a type alias.
* The `.c` file registers `io_eff(CID(Name), run, need)`. `CID(Name)`
  resolves in the *declaring file's* namespace first. `#ifdef CID(Name)`
  tests whether the program uses it at all.
* Return a `Bool` as `term_pak(CID(True{}), 0)` — but `CID_BOOL` is only
  defined if the program uses `Bool`, so prefer returning a `U32` and
  converting in Bend.
* Arguments: a `U32` is `(u32)f[0]`, a `String` via `io_cstr(e, f[0], &n)`
  (a `malloc`ed copy you free), a handle via `io_hand_v(f[0])`.
* `Process.run` works and is how the port reaches `clang`, exactly as
  tinygrad reaches it. Verified end to end.
* A user handle type is a **WONTFIX** (`WONTFIX.txt` #825): handle types
  are laws only Base may leave unfilled. Workaround: reuse a Base handle
  law and put a pointer or an `(index, generation)` pair in the 56-bit
  value. `chan.c` is the reference for the generation scheme.

### The boundary this draws in the port

| tinygrad | goes where |
| --- | --- |
| `dtype`, `helpers`, `uop/spec`, `uop/symbolic`, `schedule`, `codegen`, `renderer/cstyle` | **pure Bend** — string building is `String.append`, and the laws live here |
| `runtime/*`, `device.py`, memory, the compiler subprocess | **C effects** — exactly as tinygrad uses ctypes and shells out to clang |
| `ops_cpu` LLVM path | **dropped**, use `clang`. tinygrad already prefers `ClangRenderer`; deleting `CPULLVMRenderer` from the renderer list is the whole change |

## 5. The test format, which the port must adopt

Every `tests/<ns>/*.bend` file ends with the `#|` lines its run must print.
`#|` is not syntax; it is the expectation. So the port's own test harness is
"a `.bend` file plus its expected output", which is a good fit: the ported
`test/` can keep tinygrad's *file* structure while Bend's checker does the
comparison.

## 6. The one architectural decision the laws forced

`uop/ops.py` hash-conses UOps through `UOpMetaClass.ucache` keyed on
`(op, src, arg, tag, type(arg))`, and the range graph has **back-edges**, so
the graph is cyclic. `UOp.__eq__` is deliberately **identity**, and the test
suite leans on it (`assertIs`, `id(uop)`, `toposort` ordering).

So the compilation IR **cannot** be a pure inductive tree. It must be an
arena: a UOp is a `U32` index into an append-only table, which gives O(1)
identity, O(1) sharing, and cycles. That is also what tinygrad itself does
(`UOp.unique_num` is a monotonic slot counter that must never be reset).

Consequences, and they are expensive:

* `UOp` as a `U32` is `Data`, so handles are freely copyable at zero cost —
  the DAG-sharing problem disappears. This is the one place Bend's model is
  *better* than Python's.
* The arena is affine (`Array`), so exactly one owner exists and it must be
  threaded explicitly through every function as `(ctx, value)`.
* Therefore **the laws cannot cover the compilation IR.** They cover the
  *pure spec IR* in `bendgrad/LAWS/spec.bend`, which is a tree and whose
  derived properties (dtype, shape, device, addrspace, min_max) are total
  functions of the node. That is exactly what `spec/tinyspec.tex` states,
  so nothing is lost — but it is why `LAWS.bend` is a separate artefact
  from the arena.
* ~~A rewrite rule needs the arena, so it cannot be a closure (a closure is
  single-use and cannot capture an affine value). Rules become **top-level
  `def`s taking and returning `ctx`**, dispatched by an explicit tag.~~

  **RETRACTED — the capture half is false.** A closure captures an affine `Nat`
  fine; see "Closures: capturing is fine, STORING is the constraint" at the end
  of this file. Rules stay lambdas.

  What survives is narrower: a **function value in a datatype field forces
  `Type`, not `Data`**, so the rule TABLE is linear and one walk consumes it.
  `graph_rewrite` is called many times, so it cannot take the table as a
  parameter — it builds one per call, or takes a thunk that makes a fresh one.
  That is one function signature, not a restructuring of the rule language, and
  `PatternMatcher` is closer to a mechanical transliteration than this note
  claimed.

## 7. Reviewer checklist for the port

Reject a change that:

1. adds an `@unsafe` not in `AFFINITY.tsv`;
2. introduces a `+` where the type is not `Data` (or vice versa — a missing
   `+` that forces a copy, or a spurious one that leaks a reference);
3. branches on a value out of binder order, or on a projection/computed
   value;
4. reimplements something `base.bend` already provides — check
   `bend base` and `bend base --types` first;
5. silently changes behaviour when the Python raised or returned `None` —
   the port has no exceptions, so a Python `RuntimeError` is `IO.die`, and a
   Python `None` is `Maybe`. Neither is optional.
6. drops a Python edge case. tinygrad's spec has *tri-state* rules (accept /
   no-opinion / reject) and its tests assert exact kernel counts and exact
   `repr` strings. Both are behaviour and both are covered by tests that
   must keep passing.

## Explicit fuel instead of @unsafe (measured on 2.0.34)

The project rule is that any Turing completeness must be approved first, and the
answer was no `@unsafe`: thread a `Nat` fuel argument instead. Four facts, each
established by bisection against the pinned compiler, not by reading the guide.

1. **Fuel is the FIRST parameter.** The decrease check reads a recursive call's
   arguments left to right, stopping at the first that is a strict subterm of its
   corresponding parameter. Put the shrinking argument first. Everything after it
   is free.

2. **`case 2n+p:` yields TWO independent strict subterms.** That is how one arm
   makes two decreasing calls: one takes `n`, the other `p`. Marking either `+`
   *breaks* the check -- a reusable binder stops counting as a subterm. Two
   calls, two ordinary binders.

3. **The checker only honours `2n+p` when a `1n+p` sibling is present.** A def
   whose only fuel arm is `2n+p:` is rejected; add `case 1n+p: f(p, i)` and it
   passes. The sibling need not be reachable in practice. bendgrad/LAWS/spec.bend
   makes it meaningful: odd fuel burns one unit and re-enters, so fuel is counted
   in pairs and a caller with an odd budget is rounded down rather than lied to.

4. **A recursive call must be a tail expression, or bound to a local first.**
   `pair(go(..), go(..))` fails; `hd = go(..)` then `tl = go(..)` then
   `pair(hd, tl)` also fails when the def returns a `Maybe`; the reliable form is
   one self-call per arm with a single binder, or the `2n+p` pair above.

What all of this rules out: mutual recursion. Two functions that call each other
cannot both be checked, so the shape and dtype folds are ONE def each over a
type that covers both cases:

    type Item is Data:
      One{s: Sp}          # a node
      Many{xs: List<&2, Sp>}   # a list, for Index's index list and Stack's operands

The guide says exactly this -- "two mutually recursive functions become one def
with an extra argument selecting which to run" -- and `Item` is that argument.

Cost: every call site now passes a depth. A caller that under-counts gets
`None`, which is the honest answer for "past this depth the property is
unknown", never a wrong shape.

## Correction: numeric patterns are first-match prefix matches

The fuel section above is wrong in its central claim, and the mistake cost a
commit. Measured, not read:

```
match fuel:
  case 0n: 0
  case 1n+p: 1
  case 2n+p: 2
  case 3n+p: 3

fuel 0..4  ->  1 1 1 1 1      # 1n+p claims every successor
```

`1n+p` matches ANY positive Nat. `2n+p` is not a disjoint "even" case; it is
"at least 2", and it only fires if it is listed *before* `1n+p`. Swapping the
arms gives `2 2 2 2 2`. So any `case 2n+p:` placed after `case 1n+p:` is dead
code that still typechecks — and a fold built that way answers `None` for
everything, because fuel walks down to zero one unit at a time.

Also: `2n+p` binds **only** `p`. The `2n` is a literal, not `2` times a binder.

## The real rule for a descent

Two facts, both established by bisection:

1. **A recursive call must be a tail expression, or bound to a local first.**
   `ca(go(a), go(b))` is rejected; `x = go(a)` then `y = go(b)` then `ca(x, y)`
   is accepted.
2. **A recursive call must pass a field of its own parameter**, either bare or
   re-wrapped in the *same* constructor. `go(One{t})` from `One{Pas{t}}` is
   fine. `go(Pair{Node{l}, Node{r}})` from `Node{Bin{l,r}}` is rejected — a
   constructed sibling is not a subterm.

Together these mean: **every recursive call needs its own field.** Which in
turn means a fold that maps a recursive function over a list, and then combines
the results, is impossible without fuel — because the head and the tail come
out of ONE destructured list and so share a binder. `+` on that binder stops it
counting as a subterm. There is no arrangement that avoids this.

Bounded arity sidesteps it entirely and needs no fuel at all:

```
type Sp is Data:
  Buf{v: U32}
  Idx2{t: Sp, a: Sp, b: Sp}
  Idx3{t: Sp, a: Sp, b: Sp, c: Sp}

def shape(s: Sp) -> Maybe<&2, U32>:
  match s:
    case Buf{v}: Some{v}
    case Idx2{t, a, b}:
      r = ca(shape(a), shape(b))
      ca(shape(t), r)
```

`ALL PROOFS CHECK`, no `@unsafe`, no fuel. Every descent is a distinct field.
Verified on both the interpreted and compiled lanes.

## Writing a Bend proof: the syntax that costs time

Measured while proving `Shape.max_dim(x, x) == x`. Each of these was a compile
error before it was a rule.

1. **A def with no return type is a law proof.** `def helper(v):` is parsed as
   "fill the law named `helper`". A plain helper must spell its type:
   `def nat_max_idem(+v: Nat) -> {Nat.max(v, v) == v : Nat}:`. The return type is
   an equation, so the helper is a proof of it.

2. **Binders used twice need `+`.** `def nat_max_idem(v)` then using `v` in two
   places is "consumed more than once". `+v` fixes it, at the cost of a refcount.

3. **The `%proof : P` motive is written against the goal AFTER the match, not
   before.** This is the one that cost the most. In

   ```
   case 1n+p:
     %ih : {Nat.max(p, p) == p : Nat}
   ```

   the goal is `1n+Nat.max(p, p) == 1n+p`, so the motive must be
   `{1n+Nat.max(p, p) == 1n+_ : Nat}`. Writing the pre-match equation is silently
   accepted and does nothing.

4. **Constructor names are module-qualified in motives.** Inside a motive you
   write `S.SN{...}`, not `SN{...}` — "expected a declared constructor
   (LAWS/spec.Sdim declares LAWS/spec.SN)".

5. **`Equal.cong(A, B, f, a, b, e)` congrues a function of ONE argument.** A
   two-argument `f` is refused. To lift a proof about a list tail into a proof
   about the whole list, fix the head first:

   ```
   def cons_head(h: Sdim) -> (List<&2, Sdim> -> List<&2, Sdim>): t => h <> t
   c = Equal.cong(List<&2, Sdim>, List<&2, Sdim), cons_head(Shape.max_dim(x, x)),
                  zip_max(xs, xs), xs, ih)
   ```

   `c`'s type is `{Shape.max_dim(x, x) <> xs == Shape.max_dim(x, x) <> xs}`.
   Getting from there to the goal needs a rewrite under a list constructor,
   which is rule 3's hard case — see `zip_max_idempotent` in `PROOF.bend`.

6. **A trailing comma at end of line breaks a call.** `Equal.cong(A, B,\n  f, ...)`
   is a parse error; keep the call on one line.

## Under a list constructor, congr and trans -- not `%` rewrites

Rule 3 above says a `%proof : P` motive is written against the goal after the
match. It does not say what to do when the rewrite target sits **under a list
constructor**. Measured on `zip_max(s, s) == s`:

Every `%ih : P` shape was **accepted and did nothing**:

- `{zip_max(xs, xs) == xs}` — goal unchanged
- `{zip_max(xs, xs) == _}` — goal unchanged
- `{md <> zip_max(xs, xs) == md <> _}` — goal unchanged
- `{_ <> xs == md <> xs}` — goal unchanged
- `{_ == x <> xs}` — lands on the wrong endpoint

What works is congruence plus transitivity. `Equal.cong(A, B, f, a, b, e)` is
the workhorse, and it has one hard requirement: **`f` must be unary**. A cons
has two arguments, so it is split by fixing one side:

```bend
def cons_head(h: Sdim) -> (List<&2, Sdim> -> List<&2, Sdim>): t => h <> t
def cons_tail(t: List<&2, Sdim>) -> (Sdim -> List<&2, Sdim>):  h => h <> t

c1 = Equal.cong(List<&2, Sdim>, List<&2, Sdim>, cons_head(md), zip_max(xs, xs), xs, ih)
c2 = Equal.cong(Sdim,            List<&2, Sdim>, cons_tail(xs), md, x, mh)
Equal.trans(List<&2, Sdim>, left, mid, end, c1, c2)
```

`c1` lifts the tail proof, `c2` lifts `max_dim`'s, they share the middle term
`md <> xs`, and `Equal.trans` does the substitution that `%` refused to.

Four more measured details, all of which cost an iteration:

7. **A bare `h <> t` as a local's right-hand side is "cannot infer"**, and so is
   one in a call argument. Route it through a typed `snoc(h, t)` def rather than
   annotating every use — `h <> t` also breaks the parser inside a `#` comment.
8. **`md`, `mh`, `zmx` all need `+`.** Each is used twice: once to build the
   congruence function and once in the `Equal.trans` endpoints.
9. **A nested call in an argument breaks the parser.** `cons_head(md)` written
   inline as `Equal.cong`'s third argument gives "expected a term, observed
   `)`". Bind it to a local first: `f1 = cons_head(md)`.
10. **A `def` with no return type is a law proof**, so a helper that shares a
    name with a law in scope must spell its type. `max_dim_idem` needed
    `-> {Shape.max_dim(x, x) == x : Sdim}` before it would parse as a helper.

The general lesson: **if a rewrite under a constructor is refused, reach for
`Equal.cong` and `Equal.trans` rather than more motive shapes.** The motive
grammar is for equalities that line up; congruence is for the ones that do not.

## Closures: capturing is fine, STORING is the constraint

An earlier draft of the master plan said closures "cannot capture affine values"
and prescribed restructuring every rewrite rule into a top-level def threading an
explicit ctx. **That was wrong**, and cost an afternoon to disprove. Measured:

```bend
# CAPTURING AN AFFINE VALUE: fine.
def maker(n: Nat) -> Rule:
  R{x => (x + U32.from_nat(n) : U32)}
```
`ALL PROOFS CHECK`, evaluates to 8. So tinygrad's `lambda x: ...` rules port as
lambdas. Do not restructure them.

What is actually true, and it is a real constraint, just a different one:

1. **A function value in a datatype field forces `Type`, not `Data`.**
   ```bend
   type Rule is Data:
     R{pat: Pat, f: (U32 -> U32)}     # REJECTED: expected Data, observed Type
   type Rule is Type:
     R{pat: Pat, f: (U32 -> U32)}     # ALL PROOFS CHECK
   ```
   Function types are linear, so a record holding one is linear.

2. **Therefore a table of rules is linear, and one walk consumes it.**
   ```bend
   def twice() -> U32:
     t = table()
     a = walk(t, 5)
     walk(t, a)      # REJECTED: t (consumed more than once)
   ```

3. **Pattern dispatch on a separate `Data` field is fine**, and the pattern can
   be matched by a helper that also calls the function:
   ```bend
   def apply(p: Pat, f: U32 -> U32, n: U32) -> U32:
     match p:
       case PSink{}: f(n)
       case PAdd{}:  f(n)
   ```

Two syntax rules that cost iterations and are not recorded anywhere:
- a `match` pattern with a **function-typed field** destructures as
  `case R{pat, f} <> rest:` — inline `case r:` then `match r:` is
  `a R pattern with 2 fields`;
- the same, an `apply`/`walk` pair must be ordered `apply` before `walk`, since
  a def may only call defs declared above it. The mutual shape (walk calls
  apply, apply mentions the type) is fine as long as it is not mutual.

WHAT THIS COSTS `uop/spec.py`, which is the reason it was worth measuring: the
rule list is walked once per `graph_rewrite` call, and `graph_rewrite` is called
many times over a graph. So `graph_rewrite` cannot take the table as a
parameter. It either constructs the table itself, or takes a thunk that makes a
fresh one each call. That is a question about ONE function signature -- not about
restructuring the rule language.
