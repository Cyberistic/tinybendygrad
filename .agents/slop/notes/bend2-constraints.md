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

## THE ENGINE SHAPE for a rewrite rule table

Measured over thirteen wrong shapes. `.agents/slop/notes/engine-shape.bend` is a
working, runnable model — `ALL PROOFS CHECK`, and it prints `27` because the
arena ends as `[2, 7]` after two passes.

```bend
type Arena is Type: Nodes{items: List<&2, U32>}
type Rule  is Type: R{use: (Arena -> Arena)}

def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
  match rules:
    case Nil{}: a
    case R{use} <> rest: engine_pass(rest, use(a))
```

**The rule returns the ARENA, not a pair.** This is the whole trick. Twelve
shapes failed before this one, and they all failed the same way:

- a rule returning `(Arena & U32)` works, but then the pass must `match` on the
  rule's result — and **a `match` may not scrutinise a computed value**, so
  `match apply(r, a):` is refused;
- giving it a helper def doesn't help, because the helper has to call back into
  the pass, and that is **mutual recursion**, which is also refused;
- ordering the helper above the pass just moves the error to
  `expected a filled definition ... observed use_go`.

Returning the arena removes the destructuring entirely, so there is no helper
and no cycle. ONE recursive def does it.

Three more rules this cost:

1. **`case R{use} <> rest:` destructures a rule in the cons position.** The
   nested `case r:` then `match r:` form is `a R pattern with 2 fields`.
2. **A `match` cannot head a lambda body either.** `R{a => match a: ...}` is
   refused; the rule calls a named helper, which must then be declared ABOVE it.
3. **The arena is `Type`, so a rule consumes it and returns the new one.** That
   is not a workaround, it is right: applying a rule *grows* the arena, so
   ownership should move with it.

And the constraint that survives from the retraction: **the table is linear**, so
a second pass rebuilds it (`pass2(prev)` calls `engine_pass(table(), prev)`).
That is the entire structural cost to `uop/spec.py`, and it is one call site.

## Writing a Kahn worklist, which is how the folds get expressed

Measured on `tinybendygrad/uop/fold.bend`: the derived properties of
`tinygrad/uop/ops.py` as ONE topological fold, `ALL PROOFS CHECK` on both lanes
with no `@unsafe`. This is the shape every recursive property in the port wants,
so the rules it forced are the rules that decide the port.

**THE HEADLINE, and §8 is the evidence: a fold that TERMINATES is not a fold that
is CORRECT.** All five bugs below were `ALL PROOFS CHECK` and four printed
plausible output. Termination is the easy half and it is not the half that is
tested.

### 1. No forward references, and the error lies about the cause

    def caller(n: U32) -> U32:  helper(n)
    def helper(n: U32) -> U32:  U32.add(n, 1)
    #| - expected : a filled definition (an unfilled law is a dead claim:
    #|             live code cannot use it)
    #| - observed : helper

So **declaration order is a hard ordering constraint** (Python's order is not
reusable), and the message is the one the compiler also gives for a law
declaration left unfilled — a mis-ordered def and a dead `def foo:` stub are
indistinguishable. My order came out of a Tarjan SCC pass over the def graph
(`slop_topo.py`, since deleted): 0 SCCs, so a plain topological order.

### 2. A self-call SPENDS the list it walks, so a walk cannot return it

    def len2(xs: List<&2, U32>) -> Nat:
      Nat.add(List.length(&2, U32, xs), List.length(&2, U32, xs))
    #| - expected : xs
    #| - observed : xs (consumed more than once)

`+xs` fixes exactly this, and it is accepted on a `List` (measured — `+` is
refused only for `Type`-kinded values: functions, `Array<T>`, handles, `IO`):

    def len2(+xs: List<&2, U32>) -> Nat:  ...        # ALL PROOFS CHECK

But `+` licenses *the caller's* uses, not the callee's: a self-call still
consumes its argument, so the recursive arm's value is the **tail**. A fold that
must return both the list it walked and a number derived from it has to rebuild
the list in reverse and `List.reverse` it. Two of the five bugs below are this,
and both were silent.

### 3. A `Data` record is how a list travels with something derived from it

Bend has no tuple, so a fold step that needs `(shapes, max_dim)` needs a record:

    type Shapes is Data: Shapes{ds: List<&2, Sized>, m: Nat}

and the record is `Data` precisely so the step can read both fields. This is
*not* a workaround: a fold that answers a node's `dtype` and its `shape` has two
values to hand on, and the arena hands out one.

### 4. A two-scrutinee `match` must cover the cross product, and `_` counts

    match xs b:
      case Nil{} True{}: 0
      case Nil{} False{}: 1
      case h <> t True{}: h
    #| - expected : cases for False
    #| - observed : {}

A wildcard is a cover, not a gap: `case Nil{} _:` and `case h <> t _:` check, and
so does a match of two wildcards. So the rule is plain exhaustiveness over the
product of the scrutinees' constructors — which is what forces an
accumulator-carrying walk to enumerate `Nil`/`cons` × `True`/`False` rather than
return early. **This is why "just return `None` when the answer is no" is not
available**: an early return from the middle of a walk needs a def that calls
back into the walk, and that is mutual recursion, which is refused (1.5). The
flag rides along instead.

### 5. `Nat` and `U32` are different types, and only `Nat` hands out a tail

    U32.is_eq(List.length(&2, U32, xs), 1)
    #| - expected : U32
    #| - observed : Nat

`List.length` returns `Nat`, so every length comparison is
`Nat.is_eq(n, U32.to_nat(x))`. `Nat.to_u32` **does not exist** —
`expected : a defined name / observed : Nat.to_u32`; use `U32.from_nat` and
`U32.to_nat`. Numeric patterns are not uniform: `case 0:` on a `U32` and
`case Some{0}:` on a `Maybe<U32>` both check, while `Nat`'s `1n+p` is a
first-match prefix (see the correction above) **and is the only pattern that
binds a smaller Nat**. So a countdown has to be a `Nat`:

    def down(c: U32) -> U32:
      match c:
        case 0: 0
        case _: down(U32.sub(c, 1))
    #| - expected : a decreasing self-call (arguments are read left to right:
    #|             each passed unchanged until one shrinks)

`U32` literals pattern fine; what `U32` cannot do is *descend*.

### 6. A `do` block has no statement limit, and bare calls are statements

    def main() -> IO(Unit):
      do IO<Unit>:
        IO.print("bare")            # a bare call is a statement
        a : Unit <- IO.print("x")
        IO.print("bare again")
        IO.print("done")            # and the LAST line is a term, not a statement

Measured: 256 bound statements check, and the *only* thing the block insists on
is that it ends in a term — leaving the final term off gives `expected : a term /
observed : end of input`, which reads like a truncation bug and is not one. So a
5-row test table is one `do` block, not five defs.

### 7. A `List` table is O(n²) and `Array` cannot fix it

`Array.get` computes `i & (n-1)`, so `Array.set` cannot grow a table: a resolved
table that is built by appending **has** to be a `List`, and every read is a
walk. One walk per src of a popped node, plus one per consumer released. Slow and
checkable beats fast and unprovable — the alternative was an `Array` whose
`set` silently writes the wrong cell.

### 8. FIVE bugs that all typechecked, and what caught them

A `List` fold is where a port stops being a transliteration, and the failures are
silent, so they are worth writing down. Every one of these five was `ALL PROOFS
CHECK` and four of them printed plausible output:

1. **A countdown that does not count down.** `case c <> t 0n: c <> Kahn.dec.go(t, p)`
   keeps the head and recurses. It typechecks, and the fuel runs out.
2. **The edges, backwards.** Kahn lowers a node's *successors*, not its srcs.
   Releasing a node's own srcs leaves every node whose src is the arena's bottom
   unanswered forever — a fold that terminates, answers one node, and is wrong
   about the rest.
3. **Membership where the count is wanted.** `u in node.src` is a `Bool`, and a
   node that names the same src twice has **two** edges into it: Python's
   `UOp(Ops.BACKEDGE, src=(self, loop, cond))` with `self is cond` is exactly
   that. The consumer's count never reaches zero and the fold silently drops one
   node out of five. The fix is a count of occurrences, and it is a one-word
   change that a Bool cannot express.
4. **Index order is not resolution order.** `List.get(out, i)` on a table built
   by appending as the fold answers nodes reads the wrong entry; the table is in
   *resolution* order, so the read is a search.
5. **Returning the tail instead of the input** (§2), twice.

**The lesson: in a Bend port, "the fold terminates and prints" is not a test.**
Four of these five reached a green run. What caught them was a row whose value
Python specifies — `dtype(CONST(3)) is weakint`, `shape(ADD) == (4,)`,
`ended_ranges(BACKEDGE) == src[1:2]` — and then **running the mutation both
ways**, which is the half that is easy to skip and the half that is the test:

| mutation | rows that moved | measured by |
| --- | --- | --- |
| `ended_of.one` (the BACKEDGE arm) `src[1:2]` → `src[0:1]` | `cycle_safe` only | re-run, 2026-09-30 |
| `Kahn.degree` from an occurrence count to a `Bool` membership | `shape_ok` **and** `device_ok`; `cycle_safe` stays `True` | re-run, 2026-09-30 |

The FIRST row is the clean case and the SECOND is the correction. An earlier
version of this table claimed "one row each", measured on a mutation of
`Kahn.src_count` rather than of `Kahn.degree`. Re-running it as a mutation of
`Kahn.degree` — the occurrence count itself, made a membership test — moves TWO
rows, and notably leaves `cycle_safe` `True`.

Which is the more interesting fact, and worth stating plainly: the two rows are
NOT independent, and the suite is weaker than five green rows suggest. A
membership test under-counts the in-edges of any node an operator lists twice, so
it perturbs the *derived values* (`shape`, `device`) and not the *termination*
claim. `cycle_safe` is the row that was supposed to be about the worklist, and
it is the one that does not notice.

The lesson is not "one row each" — it is that a mutation table has to be
MEASURED, and re-measured when the mutation is re-targeted, or it becomes a
claim about a mutation nobody ran.
row `False` means the rows are not independent and the suite is weaker than it
looks — which is worth knowing before, not after.

## A CLOSURE IN A DATATYPE FIELD MUST TAKE ALL-AFFINE ARGUMENTS

The rule that decides how `uop/spec.py` has to be written. Minimal case in
`.agents/slop/notes/closure-shared-arg-wall.bend`:

```bend
def needs_twice(+ar: A, i: U32) -> V: ...
type R is Type: Shared{test: (A -> U32 -> V)}
def r() -> R: Shared{needs_twice}
```

is rejected with `expected : @_:A -> @_:U32 -> V` / `observed : @+ar:A ->
@i:U32 -> V`. The `+` is part of the function's TYPE, and a field cannot spell
it: `+A`, `A&2`, `&2 A`, `A<2>`, `((A&2) -> U32 -> V)` and `(A&2) -> (U32 -> V)`
were each tried and each is a parse or type error.

**So a rule table cannot hand a rule a shared value.** `spec.py`'s rules need
several nodes -- `x.src[0]`, `x.base`, `x.arg` -- and the arena is `Type`, so it
cannot be shared into a closure at all.

The resolution, and the working model is
`.agents/slop/notes/spec-classifier-shape.bend`:

**the engine hands each rule a SNAPSHOT, not the arena.** One node, flattened,
`Data`. The rule DESTRUCTURES it once, and the binders are then separate values
each usable once and each readable field by field -- so a rule can reach every
node it needs, provided they arrive in one record.

Two more measured rules from the same model:

- **The classifier's accumulator is the VERDICT, not the arena.** The rewrite
  engine's rule rewrites the arena; a spec rule only judges a node, so the pass
  threads `True`/`False`/`Skip` and `keep` is a leaf. The naive port of the
  rewrite shape has the wrong accumulator and its `keep` has to call the pass
  back, which is the same mutual-recursion wall one layer up.
- **`when(cond, v)` is `if cond: v else None` and `when_bad(cond, v)` is
  `if not cond: v else None`.** Both are leaves, and they are what keep a rule
  ONE def instead of three, because a `match` may not scrutinise a call. Almost
  every rule body in `spec.py` is one of those two shapes.

## `UPat.match` AND `upat_interpret`: THE SHAPE, AND WHY IT IS NOT THE REWRITER

`ops.py:1537` and `ops.py:1566`. These drive `spec.py`, so they are the unblocker
for the critical path, and they are NOT the same problem as the rewrite engine
above. Measured by analysis against the ported `UPat`; the model is not written
yet, so treat this as a design with its risks stated, not as a result.

Python threads a mutable `dict[str, UOp]` and returns
`list[dict[str, UOp]]` -- a CARTESIAN PRODUCT over the bindings -- and then calls
the rule as `real_fxn(**match)`. Three things change.

**1. THE STORE MUST BE A COPYABLE `Data` RECORD, not a bare list.** `is_any` is
`flatten([x.match(uop, store.copy()) for x in self.src[0]])` -- one COPY of the
store per alternative -- and a bare `List` is spent when read, so this is already
a type error. Same reason `fold.bend`'s `Table` wraps its list and
`spec-classifier-shape.bend`'s `Snap` is a record. This is the recurring Bend
shape: anything a fold reads twice, or branches over, gets a `Data` wrapper.

**2. `store.setdefault(name, uop) is not uop` BECOMES AN INDEX IDENTITY TEST,
and it is strictly MORE precise than Python's.** Python compares object identity;
UPats and UOps are both arena indices, so the test is "the bound index differs
from this one". This is not a weakening: two structurally equal UOps ARE the
same object in the arena, so the index test is the identity test. Worth stating
because the port is easy to read as a loosening.

**3. A RULE IS `(Store -> Verdict)`, NOT A KEYWORD CALL.** `real_fxn(**match)`
names its arguments, and a Bend closure cannot be called with keyword arguments.
So every rule reads its own captures out of the store. The upside is real: ONE
rule type instead of one per arity, and `is_any` and the commutative
permutations need no special case because the product already multiplies.

THE STORE, in full. `Bind{name: U32, uop: U32}` -- a name is a pattern-arena
concept, the node is a UOp arena index, and the two must not be confused.
`setdefault` is the only place `UPat.match` can reject on a name alone, and it
answers `Maybe<Store>`: `None` is "this name is already bound elsewhere".

THE WALK. `is_any` recurses over the PATTERN's `src`; every other arm recurses
over the NODE's `src`. Then the six rejection tests (op, name, dtype, arg, tag,
length) and either `[store]` for the leaf or the zip:

    for uu, vv in zip(uop.src, vp):
      for s in stores: new_stores.extend(vv.match(uu, s))

That zip is the whole reason `match` returns a list, and it is the part most
likely to hit a wall: it is a fold that MULTIPLIES a list, and every step reads
the pattern arena and the UOp arena.

RISKS, stated before writing it rather than after:

- Two arenas and a store means three things read per step. If any of them needs
  to be read twice, the `+` wall from the section above applies -- and a `+`
  cannot be spelled in a closure TYPE, though these are plain defs so it can.
- The `Data`-wrapper rule from (1) has to hold for the store at EVERY point in
  the zip, or the multiply will not type.
- A rule that reads a node other than the one it matched is a SECOND arena read
  and the `+` annotation, which is legal in a def but makes the rule's signature
  part of the table's type. Same trap as `spec.py`'s `Snap`.

## THE STORE PORTED; THE WALK IS BLOCKED ON `is_any`

Follow-up to the section above, with a runnable model:
`.agents/slop/notes/matcher-store.bend`. `ALL PROOFS CHECK`, both lanes,
`insert_1_then_3=13 same=1 conflict=0`.

**THE STORE IS DONE, and it confirms the recorded design.** `Store` is a `Data`
record wrapping `List<&2, Bind>`, and `Bind{name: U32, uop: U32}` keeps the name
(a pattern-arena concept) and the node (a UOp arena index) apart.

- `insert_1_then_3=13` — `setdefault` on an empty store INSERTS: one binding, and
  it is bound to node 3.
- `same=1` — the same name on the SAME node is NOT a reject. This is the identity
  test, and it is the case that would be easy to get wrong by testing only
  "is the name present".
- `conflict=0` — the same name on a DIFFERENT node IS a reject, and this is the
  one place `UPat.match` can fail on a name alone.

`Store.setdefault.find` also demonstrates the fix for a wall the earlier
sections describe: walking a list with an early exit needs mutual recursion if the
decision gets its own def, and the fixpoint script showed the oscillation
directly. The answer is to evaluate the tail walk EAGERLY and let a leaf `go` pick
between two already-computed answers. That costs a full tail walk even when the
answer is in the head, which is the price of a linear store and is fine here.

**THE WALK IS NOT DONE, and the wall is `is_any`.** `is_any` is the one arm that
recurses over the PATTERN's own src, and it recurses back into the walk. Every
attempt produced mutual recursion, refused, in this specific shape:

    def pmatch(...)          = pmatch.of(pat_at(p, i), ...)   # read the pattern
    def pmatch.of(...)       = pmatch.any(...)
    def pmatch.any.of(...)   = pmatch.is_any(alts0(up), ...)  # or pmatch.op
    def pmatch.is_any(...)   = pmatch(a, ...)                  # BACK

The read is a CALL, so it cannot be inlined into the `match` that needs its
result, so it becomes a def, so the chain is a cycle. `pmatch.op` and the six
rejection tests are the same shape one level down.

Two escapes are visible and NEITHER is written yet, so this is a lead rather
than an answer:

1. **Hoist the `is_any` flatten out of the recursion.** Pass the alternative list
   IN, already extracted, so `pmatch` never calls the thing that calls it. The
   flatten itself needs no recursion -- it is a fold over a list of pattern
   indices.
2. **Make the entry point non-recursive.** The pattern read, the `is_any`
   decision, and the alternative extraction all happen in a def that
   `pmatch` never calls, and `pmatch` takes the pattern and the alternatives as
   PARAMETERS.

Either way the cost is that the six rejection tests each become a `Bool` that
crosses a def boundary, because a `match` may not scrutinise a call. Measured
while building this: `U32.is_eq(n, name)` in a match arm is refused, and the
working idiom is to compute it in the arm and pass it to a def as a parameter --
`Store.setdefault.pick(U32.is_eq(n, name), ...)`, the same shape as
`intern.find.pick`.

**A MEASURED RULE THIS COST AND DID NOT RECORD:** removing the last use of a
parameter is a compile error in some positions -- a mutation that made `eq`
unused stopped the file checking. So an unused parameter is not free to leave
behind, which matters because the natural way to write a rejection test as a
one-line helper leaves `eq` unused in the `False` arm.

## THE COMPILED FORM IS THE RIGHT TARGET, AND IT SUPERSEDES THE INTERPRETER

This supersedes the two sections above it. Measured 2026-09-30 by reading
`tinygrad/uop/upat.py` rather than by porting, and the reading changed the plan.

**TINYGRAD SHIPS TWO MATCHERS AND THE INTERPRETER IS THE FALLBACK.**
`ops.py:1588` is `compiled=bool(getenv("UPAT_COMPILE", 1))` -- default 1, so
`upat_compile` is the live path and `upat_interpret` is not.

**AND THE INTERPRETER CARRIES EVERY AWKWARDNESS, WHILE THE COMPILER ELIMINATES
EACH ONE:**

| interpreter | compiler (`upat.py`) |
| --- | --- |
| mutable `dict` store, `.copy()`ed | `Ops.STORE` is a node in a pattern IR; at emit it is straight-line `x = uop.src[0]` |
| `-> list[dict[str, UOp]]`, a cartesian product | alternatives become `OR` of `AND` (`upat.py:63`); no early exit, nothing to multiply |
| `is_any` flattens, recursing over the PATTERN's own src (`:18`) | `AND(OR(clause for s in src[0]))` -- a disjunction, so that recursion is not there |
| `itertools.repeat` threads the store per src | `all([... for x in base.src])`, a fold |

So the store is an artifact of the interpreter needing a mutable accumulator, and
the wall I hit -- `is_any` recursing back into the walk -- is a wall in the
FALLBACK path. Target the compiled form and `Store`, `setdefault`, the product
and the flatten all disappear. The store was DELETED rather than kept: it is a correct
implementation of a component that should not exist, and leaving it invites the
next agent to build on it.

**THE BIG WIN, AND IT IS NOT OBVIOUS: THE RULE TABLE BECOMES `Data`.** Every
constraint in the sections above about a table being linear -- because a closure
in a datatype field forces `Type` -- applies ONLY to the interpreter, whose rules
are closures. A compiled rule is a TOP-LEVEL DEF named by a tag, so the table is
`CRule{tag, ops, rej}` and is copyable. It can be read twice. `spec.py` and
`schedule` stop paying the linear-table cost entirely, and the `+Arena ->
...` closure wall does not arise because there are no closures.

**THE TRADE, STATED AND NOT ASSUMED AWAY.** One def per pattern instead of one
data entry, so `spec.py`'s 82 rules become 82 defs. That is more LOC, which this
project treats as a quality measure. Against it: each rule is individually
readable and individually gateable, and `movement`/`symbolic`/`schedule` reuse
one shape. It is a real trade, not a free win.

**ONE THING TO CHECK BEFORE COMMITTING, because it may be a divergence.** The
interpreter REJECTS when a name rebinds to a different node
(`store.setdefault(...) is not uop`). The compiled `Ops.STORE` (`upat.py:33`)
just overwrites, and the identity check appears only in the `repeat` arm
(`:54-58`). If a pattern can bind one name to two different nodes, the two paths
disagree. That is either an ill-formed pattern or a bug in one of them, and it
should be settled deliberately rather than papered over by porting the
interpreter "faithfully".

## THE NAME-REBIND QUESTION, SETTLED: THE TWO PATHS AGREE

The loose end from the section above, measured rather than left open. I claimed
the interpreter REJECTS a name rebinding to a different node while the compiled
`Ops.STORE` overwrites, and that this might be a divergence. **It is not.**

`upat.py:100-105` builds a `dict_stores` and, on a duplicate, emits the identity
comparison as an ordinary clause -- with the comment "duplicate store is an
identity compare":

    if store.src[0] in dict_stores:
      new_src.append(UOp(Ops.CUSTOM, src=(dict_stores[store.src[0]], store.src[1]),
                                        arg=("{0} is {1}", dtypes.void)))

So the interpreter states the constraint IMPLICITLY, as a store rejection, and
the compiler states it EXPLICITLY, as an `is`. Same constraint, two spellings.
The compiled form is therefore safe to target, and the check ports to an index
comparison -- `U32.is_eq` on two `U32` arena indices, which is the same thing
`Store.setdefault.same` did.

**AND IT IS LOAD-BEARING, not decorative.** Scanned all 213 files under
`tinygrad/` for a pattern binding one name more than once. Three:

| where | names | verdict |
| --- | --- | --- |
| `uop/symbolic.py:180` | `c` twice | SAFE -- the two are `is_any` ALTERNATIVES, and `is_any` copies the store per alternative, so they never meet |
| `mixin/gradient.py:101` | `dest` twice | **LOAD-BEARING** -- bound to `src[0]` AND to `src[1].src[0]`, two different nodes, so the rule only matches when they are the same node |
| `schedule/__init__.py:182` | `r` three times | **LOAD-BEARING** -- the same `RANGE` node in three positions |

`gradient.py:101` is the clearest statement of intent:

    UPat(Ops.AFTER, src=(UPat(name="dest"), UPat(Ops.STORE, src=(UPat(name="dest"), UPat()))))

"the buffer being stored into is the AFTER's own source" IS this rebind. Without
the identity check the rule would match strictly more nodes than intended, and it
would typecheck and run. So a compiled rule that binds a name twice must emit the
`is` check, and that is a rule to enforce while porting `gradient.py` and
`schedule/`, not a footnote.

## ELEVEN MORE RULES, MEASURED IN `uop/upat.bend`

Every one of these cost a wrong answer or a refused file, so they are measured
and not inferred. The first three change the SHAPE of a recursive port; the rest
are sharp edges.

**1. THERE IS NO MUTUAL RECURSION.** `A` may not call `B` when `B` calls `A`, in
either order, and the error is the actively misleading `expected : a filled
definition (an unfilled law is a dead claim: live code cannot use it)` pointing
at the LATER call. Reproduced in three lines:

```python
def even(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+p: odd(p)          # "expected : a filled definition ... observed : odd"
def odd(n: Nat) -> Bool: ...
```

Consequence for a port: **each recursive descent must be ONE self-recursive
def**, and everything it needs on the way down must be a leaf. Python's
`_get_clause` is a mutual recursion with its own `src` arms and it took three
self-recursive defs here (`get_clause.go`, `rend.go`, `proc`) plus flags to keep
the arms apart. A visitor that dispatches through a table wants a cycle; it has
to be flattened into one match first.

**2. A SELF-CALL MUST BE DECREASING, READ LEFT TO RIGHT.** `expected : a
decreasing self-call (arguments are read left to right: each passed unchanged
until one shrinks)`. So in `def f(fuel, +tree)`, the recursive call must be
`f(fuel', smaller)` -- the arguments BEFORE the one that shrinks are passed
unchanged, and the fuel is what shrinks, so **the fuel is the first parameter of
every self-recursive def**, which is why `proc_fix(f: Nat, +t: C)` reads
backwards from the Python. A subterm counts as shrinking: `f(fuel, t)` on a list
tail is fine.

**3. THE SAME FUEL MAY NOT BE PASSED TO TWO SELF-CALLS IN ONE ARM.** The error is
`expected : p -- observed : p (consumed more than once)`, reported at the
`case 1n+p:` PATTERN, which sends you looking at the pattern instead of the body.
`flatands.go` gets out of it with `+q = p` and passes `q` to both; that is the
fix, and it is a `let` precisely because a `let` is a shared reference and a
pattern binder is not.

**4. A SELF-CALL MAY NOT FORWARD-REFERENCE.** Every callee of a self-call must
already be defined, so a self-recursive def sits at the BOTTOM of its own
dependency chain -- which is what a topological sort gives you for free, and what
hand-ordering gets wrong. Same error as rule 1, so check the order first.

**5. A `match` KILLS EVERY NAME BOUND EARLIER IN THE SAME BODY** -- parameters
AND pattern binders. `match br:` then `match op:` (where `op` came from
`case C{op, lit, k} <> t:`) gives `a match on a parameter or field (this name is
a def or a consumed binder)`. A def that dispatches on two flags must read them
in ONE `match` per arm, never as two nested ones: `rend.go` repeats `br` inside
all four op arms for exactly this reason, and it costs four lines to save a
refused file.

**6. `case p <> t:` ON A `String` GIVES YOU THE FIRST CHARACTER.** `String` is
`List<&2, Char>`, so the head/tail pattern that reads a `List<&2, String>`'s
first element also matches inside the `String` itself. The symptom is a value
that is one character long where a whole piece was expected -- and the piece that
is lost is always the one AFTER it, because `head_or` then answers the empty
tail. There is no `List.split` in `base.bend`; the fix is to take the element as
a whole and let a helper def destructure it.

**7. `List.append(a, -A, xs, ys)` IS `xs ++ ys`.** Prepending is
`List.append(a, A, [x], xs)`. A recursive `map`/`filter` that writes
`append(fold(t), [head])` compiles, typechecks, runs, and returns every list in
REVERSE -- and the reversed list is still a list of the right type, so nothing
downstream complains. Six separate folds in `upat.bend` had it; the only reason
it was caught is that the port is gated on CPython's exact output.

**8. `String.concat` IS NOT A NO-OP ON EMPTY PIECES.** It is `SNil{}` for `Nil{}`
and `h + concat(t)` otherwise, so a format substitution built from pieces
concatenates to the right string even when a piece is `""`. That is how a
dropped literal stays invisible: `"{0}.op is {1}"` rendered as `"uopa0"` with no
error anywhere. Compare against a known-good string, never against a type.

**9. `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE.** Obvious, and worth
writing down because the natural reading of the call site
`Bool.pick(List<&2, C>, is_empty(xs), [x], xs)` is the other way round; getting
it backwards silently swaps two arms of every dispatch that uses it.

**10. A `do` BLOCK MUST BE THE LAST EXPRESSION OF A DEF BODY.** A bare
statement or a `do` block followed by another expression is
`expected : a term -- observed : '.'`, and a `do` block whose type is `IO(Unit)`
followed by the function's value is `expected : a term -- observed : end of
input`. A pure function cannot print mid-body: put the effect in a wrapper that
RETURNS the value (`String.concat([IO.print(x), ...])`) or in `main`.

**11. `proc(t)` SPELLED TWICE IS TWO WALKS, NOT A SHARED BINDING.** A `let` is
affine, so `n = proc(t)` followed by two uses of `n` is
`expected : n -- observed : n (consumed more than once)`; `+n = proc(t)` is the
shared form, and `Bool.pick(C, eq_c(t, proc(t)), proc(t), recheck(proc(t)))` with
`proc` pure is a legitimate way to say "call it three times" when a fixpoint test
needs both the old and the new value. Purity makes the repetition free of state
and only expensive in time.

## WHAT THE UPAT PORT COST, IN ORDER

The three recursive rules above are why `upat.bend` is 2.3k lines for 186 lines
of Python, and the count is not padding: the alternative is a self-recursive def
with seven `Bool` parameters and a `match` per arm, which is what `rend.go` and
`get_clause.go` are. The other half of the cost is `do_process_and`, whose
`found` is read in five places and is therefore threaded through four
`Maybe`-returning helpers (`of0` .. `of6`) that exist only to keep the flag out of
a record. Both are the direct consequence of rules 1-3, and both would be one
line each in a language with mutual recursion and a mutable local.

## EXTENDING THE DIFFERENTIAL ORACLE: THE a{n} ORDER HOLDS, AND IT FOUND A BUG

The compiler's nine rows are CPython's own `_get_code` output, which is the right
kind of evidence, but none of them spends more than one or two `a{n}`s — so the
NUMBERING, which the port makes a separate pre-order pass, was untested. The
oracle extends in one command. The probe is
`.agents/slop/notes/upat-anum-probe.bend`; run it and run CPython's `_get_code`
on the same patterns and diff.

**THE ORDERING HOLDS.** Four patterns, four levels deep, up to four `a{n}`s, all
MATCH CPython byte for byte:

| pattern | `a{n}` spent | result |
| --- | --- | --- |
| `UPat(Ops.ADD, src=(UPat(Ops.MUL, name="x"), UPat(Ops.CAST, name="y")))` | `a0 a1 a2` | MATCH |
| `UPat(Ops.CALL, src=(UPat(Ops.PARAM, name="dst"), UPat(Ops.RANGE, name="r")))` | `a0 a1 a2` | MATCH |
| `UPat.any(UPat(Ops.MUL, name="a"), UPat(Ops.SUB, name="b"))` | `a0 a1` | MATCH |
| `UPat(Ops.INDEX, src=(UPat(Ops.ADD, src=(UPat(Ops.MUL, name="m"), UPat(Ops.SUB, name="s"))), UPat(name="i")))` | `a0 a1 a2 a3` | MATCH |

So the deviation reported in the compiler commit — Python numbering inside
`pm_renderer`, the port numbering in a separate pre-order pass — is NOT observable
in the generated source, through four levels. It remains a structural difference
between the two implementations, so it is not disproved, only unexercised less
than feared.

**AND THE SAME PROBE FOUND A REAL BUG -- whose first diagnosis was WRONG.**

The `repeat` arm (`src=UPat(...)`, which is `itertools.repeat`) sometimes returns
`None` where CPython returns a full `compiled_match`. The first reading was "it
resolves its child only at pattern index 0", because the passing fixture used
`SOne{0}` and the failing one used `SOne{1}`. **That is falsified.** The
discriminating experiment is one variable:

| fixture | repeat child at | an UNREFERENCED pattern in the arena | port |
| --- | --- | --- | --- |
| `p_rep_at0` | index 0 | no | full code, MATCHES CPython |
| `p_rep_dangling` | index 1 | yes, one var no parent references | **`None`** |
| `p_rep_nested` | index 1 | yes, same shape | **`None`** |

So the repeat index is NOT the trigger. **A pattern in the arena that no parent
references is.** Same structure, same `SOne{1}`, and adding one dangling pattern
turns working code into `None`.

Two candidates eliminated while narrowing it, which is the useful part:

- `alt_ys` reads the repeat's index correctly (`case O.UpRepeat{x}: [x]`), so the
  index is not being dropped.
- `broken_of` is NOT recursive -- it checks only the top-level UPat's own `src` --
  and on these shapes it does not fire, so it is not rejecting them either.

That leaves the failure downstream, in the repeat arm of `get_clause.go` (the
`case alt <> at:` branch, where the walk descends with `alts = Nil{}` and
`ys = alt_ys(alt)`) or in `final_render` / `code_of`. The walk appears to be
sensitive to the arena containing patterns the root's subtree does not reach, and
the natural suspect is anything driven by arena POSITION or by a FIXPOINT over the
whole arena rather than by the pattern's own subtree -- `pm_proc` is a fixpoint,
and if it enumerates the arena rather than the reachable tree, a dangling pattern
is exactly the kind of node that would change the round count.

`repeat` nested inside `is_any` also returns `None` where CPython emits both
branches -- and there CPython numbers PER BRANCH, both branches using `a0`, which
is a third thing the nine rows could not see. Whether that is the same cause is
NOT established.

WHY THIS MATTERS BEYOND THE PORT. `UPat.var` and `cvar` are INTERNED, so a name
built once and reused across rules leaves entries in a pattern arena. If a rule
builder ever creates a pattern it does not reference -- which `UPat.or_any` does
when it appends a named copy alongside the original -- then this is reachable in
ordinary use and not only from a hand-built fixture. That is worth checking before
assuming the bug is confined to probes.

THE LESSON, which is the point of doing this at all: nine rows against a real
oracle is strong evidence about the cases the rows cover and NO evidence about
the rest. The cheapest possible extension — six more patterns through the same
oracle — turned an "unverified deviation" into a "verified ordering plus a
concrete bug". Neither was findable by reading the code.

## SIX MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/spec.py`

Appended, not edited. All six are Bend 2.0.34 and all six were found by porting
84 rules; each one cost at least one compile cycle.

### 1. A `Data` RECORD PARAMETER NEEDS `+` FOR TWO READS. IT IS NOT IMPLICITLY COPYABLE

    type CRules is Data:
      CRules{rs: List<&2, U32>}
    def CRules.rs(rs: CRules) -> List<&2, U32>:
      match rs:
        case CRules{rs}: rs
    def cr_rewrite(rs: CRules, ar: U32, i: U32) -> U32:
      cr_scan.rs(rs, ar, i, CRules.rs(rs), 0)
    #| - expected : rs
    #| - observed : rs (consumed more than once)

`+rs` fixes it and nothing else does. This CORRECTS the claim in
`compiled-matcher-shape.bend`'s header -- "the table is `Data`, so `rs` is COPYABLE
and readable twice" -- and the model's `cr_rewrite` is a live instance of the
error, unreachable only because nothing calls it yet. `Data` makes a record
shareable ACROSS functions; it does not make the PARAMETER readable twice inside
one body. Same for `F.Folded` and for `O.Arena`.

### 2. AN UNUSED `+` PARAMETER IS ACCEPTED

    def q1(+fx: F.Folded, self: U32) -> Verdict: VSkip{}
    #| ALL PROOFS CHECK

So `+` can be applied UNIFORMLY to a parameter without a dead-parameter error, and
a driver can pass an argument a rule does not need. Worth knowing because the
alternative -- annotating only where the compiler complains -- is exactly the
manual loop `share.py` automates.

### 3. `+` CANNOT BE SPELLED ON A `Maybe` PARAMETER

    def facts(+m: Maybe<&1, ParamArg>) -> Bool: ...
    #| - expected : Data
    #| - observed : Type

`Maybe` is a `Type`, and the `+`-notes section above already says `+` is refused
for `Type`-kinded values. The consequence is the one that cost the most here: a
`Maybe` can be read ONCE, so every answer it carries has to travel together, and a
`Data` record CANNOT HOLD A `Maybe` FIELD. So a `Maybe<ParamArg>` becomes a
`Data` record of `Bool`s (and a third `Data` type for the device's three states),
not a record of `Maybe`s:

    type DevOpt is Data:
      DNo{}
      DOne{tag: U32}
      DMany{tags: List<&2, U32>}
    type Pa is Data:
      Pa{ok: Bool, size: Bool, dev: DevOpt, buf: Bool, vrange: Bool}

This is a recurring shape and it is not a workaround: Bend has no `Data` field
that can hold a `Maybe`, so ANY record that would naturally hold a list of
optional answers has to be flattened to a tree of `Data`.

### 4. A ONE-FIELD RECORD'S PATTERN MUST NAME ITS FIELD

    match a:
      case ADt{}: True{}
    #| - message : a ADt pattern with 1 field

    match a:
      case ADt{dt}: True{}      # checks, and the unused binder is fine

A zero-field constructor takes `{}` and a one-field constructor takes `{name}` --
`{}` is never "ignore the fields". And an UNUSED pattern binder is accepted, which
is what makes `case ADt{dt}: True{}` a one-line `isinstance(x.arg, DType)`.

### 5. A TWO-SCRUTINEE `match` NEEDS ONE PATTERN PER SCRUTINEE, AND `_ _` IS THE COVER

    match a b:
      case Some{x} Some{y}: ...
      case _: False{}
    #| - expected : 2 patterns (one per scrutinee)
    #| - observed : '_'

The fix is `case _ _: False{}`. This is the rule-4 note above with the spelling:
a wildcard is a cover, and it is a cover PER POSITION.

### 6. A THREE-SCRUTINEE `match` WITH A `Nat` COUNTDOWN HAS NO `0n` ARM

    match xs want n:
      case Nil{} Nil{} 0n: True{}
      case _ _ 1n+p: ...
    #| - expected : a constructor of U32 (missing, or already matched)

The note above already says a `Nat`'s `0n` is a first-match PREFIX that claims its
successors, and it already says to use `List.get`. What is new here is that this
bites in a THREE-scrutinee match too -- `case _ _ 1n+p:` after a `0n` arm is dead
for the same reason, and the `0n` arm swallows the whole countdown. For two lists
compared for equality there is no countdown at all: `ops.bend`'s `eq_op_list` is
the right tool and the countdown was 20 lines of nothing.

### 7. A SELF-CALL DRIVEN BY A `Nat` COUNTDOWN MUST PASS THE SHRINKING ARGUMENT FIRST

    def go(xs: List<&2, U32>, k: Nat, acc: U32) -> U32:
      match xs k:
        case Nil{} _: acc
        case h <> t 0n: ...
        case h <> t 1n+p: go(p, t, ...)     # REFUSED
    #| - expected : a decreasing self-call
    #|   (arguments are read left to right: each passed unchanged until one shrinks)

`go(t, p, ...)` is the only spelling. The two-scrutinee `match` reads its
scrutinees in declaration order, and the decrease check reads the arguments in
declaration order, so the countdown has to be the SECOND parameter for both to
line up. `fold.bend`'s `Arena.at.go` and `Kahn.dec.go` already have it in that
shape; the reason they do is this.

## RUNTIME "MEMORY FAULT" / MACHINE STACK OVERFLOW, IN THIS CODEBASE'S TERMS

Bend 2 runs on HVM2, so a stack overflow is not a CPU stack overflow — it is the
runtime exhausting its memory NODES, because recursion builds interaction-net
graph rather than moving an instruction pointer. The symptom is a hang or a
memory fault, and it looks identical to an infinite loop. Three causes, ordered by
how often they have actually bitten here.

**1. A FOLD WHOSE FUEL NEVER REACHES ZERO.** This is the common one, and it has
bitten twice in this repo. Both times the cause was a bound derived from
something that is NOT what the fold is walking:

- The Kahn fold in \`fold.bend\` seeds its worklist from \`Arena.next(ar) + edges\`
  — one push per zero-src node PLUS one per edge. The arena is a DAG by
  construction (\`UOp.make\` only names src indices already appended, so every src
  index is strictly less than its consumer's), so the arithmetic terminates. If
  the bound is derived from anything else, the worklist never drains.
- \`UPat.repeat\` is Python's \`itertools.repeat\`: an UNBOUNDED alternative. It is
  a VARIANT (\`UpRepeat\`), not an infinite list, precisely so nothing enumerates
  it — \`required_len\` and \`strict_length\` are what bound the read. A fold that
  walks \`UpRepeat\` without that bound never terminates.

**2. A BOUND THAT DOES NOT DECREASE.** Measured while porting the pattern
compiler: a self-call must be DECREASING and read LEFT TO RIGHT, and the same
fuel may not feed two self-calls in one arm. A self-call that passes the fuel on
unchanged, or passes it after a value that already consumed it, is an infinite
net. \`upat.bend\` makes fuel the FIRST parameter of every self-recursive def for
exactly this reason.

**3. AN AFFINITY VIOLATION THAT EXPONENTIATES NODES.** \`Data\` makes a record
shareable ACROSS functions but does NOT make the PARAMETER readable twice — the
parameter still needs \`+\`. Getting that wrong typechecks, and the net it builds
duplicates subtrees instead of sharing them, so node count grows with depth rather
than with width. The \`+Arena -> ...\` closure wall is the same fact seen from the
other side, which is why the port has no closures.

**HOW TO LOCALISE, in the order that has worked:**

- Run the INTERPRETED lane first. If the native lane hangs and the interpreter
  does not, it is a compilation/backend issue, not your logic. If BOTH hang, it is
  a non-terminating walk.
- \`--check-only\` passing tells you nothing here. Both a terminating and a
  non-terminating fold check.
- Bisect by making a fold's accumulator a COUNT and printing it, so you can see
  which node it stalls on. \`fold.bend\`'s \`Table\` is a \`Data\` record precisely so
  it can be read while a walk is in flight.
- Compile to a local target and inspect, as a last resort — but in this repo the
  interpreted-lane split plus a count has been enough every time.

**WHAT DOES NOT HELP:** raising a timeout. Every occurrence here was a genuine
non-termination, and each one cost 120s of waiting to learn nothing.

## EIGHT MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/weak.py`

### 1. `def f.b(...)` MUST BE DECLARED BEFORE `def f.a(...)` THAT CALLS IT
The "no forward references" rule bites hardest in the `name.phase` naming
convention, because the reading order a human expects (outer call first, helper
below) is the order the checker refuses. `weak.py`'s port lost four cycles to it:
`derived_dtypes.hold`, `commit_srcs_at.bare`, `wk_dt_const.sealed_pick` and
`wk_blocked.of` each had to be moved ABOVE its own caller. The error reads
`expected : a filled definition (an unfilled law is a dead claim: live code cannot
use it) / observed : <name>`, which does not say "declared too late" at all. The
existing driver `tools/hoist.py` fixes it; the tell is the error text above.

### 2. A `Some{g}` BINDER OVER A `Data` RECORD IS AFFINE: TWO READS NEED `Some{+g}`
`Found` is `Data`, which makes it shareable ACROSS functions, but a binder pulled
out of a `Maybe` is a normal affine binder. Measured on
`case Some{g}: wk_dt(refold(g), wk_src1(refold(g), O.Found.i(g)))` -- two reads of
`g` and the error is `expected : g / observed : g (consumed more than once)`.
`+` in the PATTERN position (`Some{+g}`) is the fix, not `+` on the `Maybe`
parameter, which rule 3 of the section above forbids.

### 3. `Nat` LITERALS ONLY BIND IN A `Nat` CONTEXT, AND `Bool.to_u32` IS NOT ONE
`Nat.add(n, 1)` is `expected : Nat / observed : U32`; `Nat.add(n, 1n)` is fine.
There is a `Bool.to_u32` and NO `Bool.to_nat`, so a COUNT over a predicate needs
its own two-arm def:
    def nat_of(b: Bool) -> Nat:
      match b: case True{}: 1n case False{}: 0n
This is the same shape as `Cmp` being a datatype that a `match` can scrutinise.

### 4. A RECORD PATTERN MAY NAME FEWER FIELDS THAN THE RECORD HAS -- SILENTLY
`case Fix{fx, wl, a, c, b, bs}` against a SEVEN-field `Fix` is ACCEPTED and the
missing field is a wildcard. So a partially-updated record type is caught ("a Fix
pattern with 6 fields") but a partially-updated PATTERN is not: it compiles, reads
whatever is in the un-named slot, and the gate row that depends on it goes quietly
wrong. When a `Data` record gains a field, EVERY `case` of it must be updated by
hand, and `--check-only` will not tell you.

### 5. BEND IS STRICT: AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES
    def pick2(some: Bool, dt: ODt, fx, self, ss) -> O.Arena:
      pick(some, go(ss, walk_seed(Folded.ar(fx)), fx, ODt.dt(dt)), fx, self)
The `dt is None` arm of `commit_weak_consts` is Python's identity, but `go` is an
ARGUMENT, so it runs on that arm too: the walk mints nodes, and `pick` then hands
back the GROWN arena. It typechecks, it checks, and the gate row that counts arena
nodes is the only thing that sees it. To keep a branch LAZY the work must be inside
a `match` ARM of a def whose FIRST parameter is the flag:
    def walked(some: Bool, dt: ODt, fx, self, ss) -> O.Arena:
      match some:
        case True{}: replace_walk(go(ss, walk_seed(...), fx, ODt.dt(dt)), fx, self)
        case False{}: O.Folded.ar(fx)
The general rule: **a flag parameter makes the arms cheap, it does not make the
arguments lazy.**

### 6. A GROWING ACCUMULATOR CANNOT BE THE FIRST PARAMETER OF A SELF-CALL
Rule 7 of "ELEVEN MORE RULES" makes the SHRINKING argument first when the fuel is a
`Nat`. The same holds when the fuel is a LIST and the accumulator GROWS: a
`Walk{arena, srcs}` in the first slot is a `expected : a decreasing self-call`.
`commit_srcs_at.go(ss, w, fx, dt, bare)` is the shape; `w` in the first slot is
not. Same cause as the `Nat` case: arguments are read left to right, each passed
unchanged until one shrinks, and `Walk` never shrinks.

### 7. A `Data` RECORD CAN CARRY THE `Maybe` A PARAMETER CANNOT
`dt: DType|None` is read once PER SRC in `commit_weak_consts`, and `+` cannot be
spelled on a `Maybe` parameter (rule 3 above). The port that works is a two-field
record -- a `Bool` plus the value -- which is rule 15's own spelling (`spec.bend`
does it for `Pa`, `fold.bend` for `Sized`). Same for `derived_dtypes`' answer:
`Dts{some: Bool, meet, result}`, read once for `bare` and once for the pair.

### 8. AN `IO<Unit>` `do` BLOCK CAN ONLY BIND AN `IO`
    f = g_fix()                                  # expected : a pattern
    f : Fix <- pure(g_fix())                     # expected : a defined name: pure
    f : Unit <- row(...)                         # OK -- what fold.bend's main does
A pure value cannot be bound in the block at all, so a fixture has to be passed to
each row as a PARAMETER (`main` calls `g_fix()` per row) or wrapped in an IO for no
reason. For an 11-node fixture the repeated `g_fix()` is free; for a real arena it
would not be, and the honest shape is `Folded` carried in the caller's parameters.

## FIVE MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/divandmod.bend`

### 1. A `Maybe` PATTERN BINDER CANNOT BE READ TWICE

`bend2-constraints` rule 3 says a `Data` record PARAMETER needs `+` for two reads
in one body. A binder from `case Some{f}:` is the same restriction and there is
no spelling for it:

    def hit(m: Maybe<&2, Found>) -> U32:
      match m:
        case Some{f}: Found.ar(f) + Found.i(f)      # refused: f, consumed more than once
        case None{}: 0

The fix is to hand `f` to a def and put `+` on THAT:

    def hit.put(ar: Arena, +f: Found) -> U32: Found.ar(f) + Found.i(f)
    def hit(m: Maybe<&2, Found>) -> U32:
      match m:
        case Some{f}: hit.put(arena, f)
        case None{}: 0

So rule 4 ("`+` cannot be spelled on a `Maybe`") and rule 3 meet: the binder is
unfixable and the parameter is not. **This is not the same as a `Maybe`
PARAMETER, which `+` handles normally** — it is specifically the binder.

### 2. A COMMUTATIVE `alu` BUILDS AN `is_any`, SO A `+` PATTERN IS A DISJUNCTION

`UPat.alu` (ops.py:1533-1536) passes `list(asrc) if op in GroupOp.Commutative
else asrc`, and `GroupOp.Commutative` is `{MUL, MAX, CMPNE, CMPEQ, XOR, OR, AND,
ADD}`. So `UPat.cvar("a") + UPat.cvar("c")` is `is_any` over BOTH ORDERS and a
port that writes "src0 is the CONST" drops one alternative, typechecks, and is
wrong on every fixture with the operands the other way round. **There is no
`reject set` and no `on` flag that catches it**; the two-sided fixture is the
only thing that does.

### 3. `dm_which`-STYLE DISJUNCTIONS ARE NOT DISTINGUISHABLE BY ONE FIXTURE FAMILY

Two rules each with one commutative `is_any` ("which side is the CONST" and
"which side is the quotient") move the SAME mutation set from one fixture family,
because from outside the question is the same question. See `divandmod.bend`'s
mutation table, notes 1 and 2. Separating them needs a fixture where the two
answers DISAGREE, not more fixtures of the same shape.

### 4. AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT PRODUCED IT, AND `+` DOES NOT ENFORCE IT

`+x = O.UOp.new(O.Found.ar(previous), ...)` binds an index into the arena it was
built in. Building `+b` from `O.Found.ar(a)` when `b` should have been threaded
through an INTERMEDIATE node silently reuses index `n` for a DIFFERENT node, and
every read of `Found.i(b)` in the later chain then reads the wrong node. Measured:
a fixture PARAM created and then dropped from the thread aliased a `FLOORDIV`
three nodes later, and the gate printed `div25=FLOORDIV` for a node whose divisor
was a PARAM. `share.py` and `hoist.py` cannot see this — it is not a `+` or an
order error — **so the last arena threaded is the thing to re-read when a label is
wrong.** Symptom to recognise: a node's src prints as a plausible index but the
wrong `op`.

### 5. `floor` IS NOT AVAILABLE AND MUST NOT BE ASSUMED FROM A HELPER NAMED `floordiv`

`H.floordiv_i32` in `helpers.bend:1097` adds one whenever the division is
inexact and IGNORES the sign, so it is correct for a negative dividend and for an
exact division and WRONG (off by +1) for a non-negative dividend with an inexact
division — which is most of them. Measured: `6 // 4 == 2`, `10 // 3 == 4`,
`1000 // 7 == 143`, `6 % 4 == -2`, against Python's `1, 3, 142, 2`.

**The general rule: a port that depends on floor semantics must TEST the helper
against the Python answer before using it, and a correct local copy with the
upstream bug named is better than a gate that pins wrong numbers.** `divandmod.bend`
carries `dm_floordiv` / `dm_floormod` for exactly this, with the one-line fix and
the removal condition written down. `H.asr` is broken the same way (see that
file's header): `shrn(v,31)` is the sign BIT, so `shrn(shrn(v,31), n)` is 0 for
every `n >= 1` and `H.asr(-1, 1) == 2147483647` where the answer is `4294967295`.
Both are UNUSED and UNTESTED in `helpers.bend`, which is why ten green rows in
another unit never saw them.

### 6. A NESTED-FORWARD TREE PRINTER IS A MUTUAL RECURSION, AND BEND REFUSES IT

`print(node) -> fold(srcs) -> print(src)` is two mutually recursive defs. A `Nat`
fuel does not rescue it: a binop spends one fuel on TWO self-calls, and rule 5
forbids that. The honest answer is to make the DEPTH a parameter of the printer
(`dm_sh1` / `dm_sh2` in `divandmod.bend`) and pick the depth the ANSWERS need —
two levels with CONST VALUES printed reproduces Python's trees exactly for that
file's rules. **When a printer cannot be recursive, printing less but printing
VALUES beats printing more but printing op names.**

## SEVEN MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/symbolic.py`

Appended, not edited. All seven are Bend 2.0.34 and each one cost a wrong answer
or a refused file.

### 1. A `Maybe` IS READ ONCE AND CANNOT BE `+`, SO "TEST IT AND USE IT" IS TWO DEFS

`Maybe<&1, T>` is a `Type`, `+` is refused on it (section "THREE" of the
`spec.py` notes), and it is read once. So the Python

```python
if c is not None: ... c ...
```

is three defs, not one, and the test crosses as a `Bool` **beside** the value:

```bend
def rm_0.ok(hit: Bool, ok: Bool, +x: F.Folded, +u: U32, z: U32) -> Maybe<&1, U32>: ...
def rm_0.of(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match z:
    case Some{v}: rm_0.ok(hit, True{}, x, u, v)
    case _: rm_0.ok(hit, False{}, x, u, 0)
```

Writing `Bool.pick(Maybe<&1, U32>, Maybe.is_some(&1, U32, z), Some{f(z)}, None{})`
is `expected : Data / observed : Type` on the `+z` that `share.py` helpfully
adds — **and `share.py` will add it every time**, because the error it is fixing
is real. That is a loop: run `share.py`, get the `+`, get the `Data`/`Type`
error, restructure, run `share.py` again. The fix is to notice that the shape is
wrong, not to add annotations.

### 2. `Maybe<a, A>` IS INVARIANT IN ITS USAGE COUNT

`Maybe<&1, O.Const>` and `Maybe<&2, O.Const>` are DIFFERENT types and are not
interchangeable in a call. A `Data` field cannot hold a `Maybe` at all, and a
helper that takes a `Maybe` parameter inherits whichever count its call site
spells. The measured cost was a chain of `sy_maybe_c` / `sy_maybe_c2` — two
three-line defs with identical bodies — because a FOLD's answer is `&1` and a
`sy_val` out of `fold.bend` is `&2`. It is not worth deduplicating into a
typeclass; it is worth knowing before the second one surprises you.

### 3. A `find`-STYLE RECORDER IS USUALLY A FOLD WITH AN INVERTED `Bool`, AND THAT IS THE BUG

`const_i64` was written `Bool.not(Cmp.is_eq(...))` — "the value is NOT `n`" —
inside a def named `p_is_const_0`. It typechecked, it ran, and it inverted every
caller. The mutation that catches it is one character (`is_eq` -> `not is_eq`)
and it moved **three** rows at once, because the predicate is shared by
`sym_6.pat` and `sym_8`'s shape. A shared predicate is a shared blast radius:
the mutation table should always include one, because "which rows does this one
comparison own" is not answerable by reading the rule that uses it.

### 4. `ops.bend`'s `Arena.empty()` SPENDS INDEX 0, SO EVERY FIXTURE IS OFF BY ONE

`# the arena starts with the bottom at index 0, so Arena.next is next(UOp.unique_num)
# with the first slot already spent` (ops.bend:925). So a graph of two nodes has
indices 1 and 2, and `Arena.next` is 3. Four of this file's gate rows were `0`
because every hard-coded index was one short, and `Arena.node` answering
`Arena.bottom()` for an index past the end means a mis-indexed fixture answers
`None{}` rather than raising — so the symptom is a rule that silently does not
fire. **The fixture's own node count is a gate row** (`lay`), and it is the row
that would have caught it.

### 5. A FIXTURE BUILDER THAT RETURNS AN INDEX THROWS THE GROWN ARENA AWAY

`Arena` is affine, so `sy_cast(ar, ...)` grows a *copy* and the caller keeps the
old one. A builder written as `-> U32` therefore produces a graph whose last
node is not in the store, and `fx_castbad` answered `Arena.next == 1` for a graph
of two nodes. **EVERY construction in a fixture must return a `Found`**, and a
chain is `+a = ...` then `+b = ...` off `O.Found.ar(a)` — which is the same
shape `fold.bend`'s `g_keys` uses.

The deeper form of the same fact is the wall this file stands on: a rule
returning `Maybe<&1, U32>` that GREW the arena gives the caller an index it
cannot dereference. `Maybe<&1, O.Found>` is expressible (`Found` is `Data`), so
that is the shape a growing rule should have; it was not written here because
it touches every rule body, and it is the first thing to change when the tables
grow past thirteen entries.

### 6. `List.append(a, A, xs, ys)` IS `xs ++ ys`, AND A FOLD THAT USES IT ACCUMULATES IN REVERSE

Already recorded ("THE SAME FOLDS..." / rule 7) and re-measured while porting
`pm_remove_invalid`'s `src=tuple(...)` and `pm_clean_up_group_sink`'s
`flatten`. Both read correctly and both are reversed. `List.reverse` at the end
of the walk is the fix and it costs one call. The new datum is that a fold whose
accumulator is a `List` of `List` (the sink-flatten case) has the SAME trap one
level up: `H.flatten_u32` is `List.concat`, so it flattens the accumulated list
of lists and the order is whatever the accumulation produced.

### 7. TWO RULES THAT CLAIM ONE NODE AND **AGREE** CANNOT SEE FIRST-WINS

Already the brief's trap and it is worth stating with the measured result. The
first `first` fixture was `GROUP(GROUP(C(7)))`: tags 11 (`GROUP(x)` -> `x`) and
12 (the flatten) both claim the outer GROUP, and the first-wins -> last-wins
mutation moved **NOTHING** — because `flatten([inner.src])` happens to rebuild
the inner GROUP, so both answers are the same index. The fix is a fixture whose
two answers genuinely differ (`GROUP(SINK(C(7)))`: tag 11 answers the SINK,
tag 12 answers a fresh GROUP over `[1]`), and with it M1 moves exactly `first`.
Two rows with two-sided fixtures in the same file (`rebind0`, `xorb0`) had the
same shape of failure and the same cure: ask for the *absence* of a rewrite, not
for a particular index, on the negative side. `eq_u(m, 0)` is satisfied by any
wrong-but-present answer and witnesses nothing.


## EIGHT MORE RULES, MEASURED 2026-09-30 FIXING `eq_cls.sel` AND `floordiv_i32`

Appended, not edited. All eight are Bend 2.0.34 and each one cost a wrong answer
or a change that would have compiled and done nothing.

### 1. AN ARM AFTER A `case _:` IS **DEAD CODE**, AND BEND DOES NOT SAY SO

This is the one that changes how you write a catch-all ladder, and it is
invisible in the source: the arm is right there, spelled correctly, and never
runs. Measured, with every arm answering a distinct number:

    type C is Data: A{} B{} Cc{}
    match x: case A{}: 1; case _: 99; case Cc{}: 3     # A=1  Cc=99

`case _:` claims every remaining tag, so anything written after it is
unreachable. Bend 2.0.34 accepts it silently -- no error, no warning, and
`--check-only` still says `ALL PROOFS CHECK`.

**So the last constructor of a sum type is spelled `case _:`, and every other one
is spelled out.** That is not a style choice, it is the only placement that can
work, and it is the shape this repo's own `eq_const.sel` already uses: `Const`
is `CBool CInt CFloat CInvalid`, the ladder writes the first three and gives
`CInvalid` the catch-all. Arm ORDER among the explicit ones does not matter --
measured, `case Cc/B/A` and `case A/B/Cc` agree -- so "where do I put the new
arm" is answered by "which one is last in the type's declaration", not by
`dtype.py`'s priority order.

Corollary for the "just append the missing arm" instinct: appending to a ladder
that already ends in `case _:` is the ONE edit guaranteed to do nothing. If a
`match` over a sum type has an `N`-armed version and the type has `N+1`
constructors, the fix is to make constructor `N` explicit and move the catch-all
onto constructor `N+1`.

### 2. A GATE THAT NEVER CALLS THE FUNCTION UNDER REPAIR IS BLIND, AND IT IS NOT AN ACCIDENT

`uop/ops.bend` had twelve rows and all twelve were green while `eq_dt(weakfloat,
weakfloat)` was `False` and two structurally identical `CAST(..., weakfloat)`
nodes built FOUR arena nodes where two would do. Nothing was flaky and nothing
was mis-transcribed; the twelve rows simply never mentioned a dtype except
`S.void()` and `S.boolean()` in fixtures, and `eq_dt` is reached only through
`eq_arg.ADt`.

**The test for "is this gate blind to X" is one grep: does any row's fixture
carry a value of X's type?** If not, the gate cannot see X, and the first thing
to add is a row whose EXPECTATION COMES FROM THE ORACLE (`dtypes.weakfloat ==
dtypes.weakfloat` in CPython), not one whose expectation is what the code
prints. A row that asks "is it equal to itself" for every member of a
seven-member type is a better gate than none, and it took one line per member.

### 3. `+` IS NEEDED ON A `Data` PARAMETER USED **TWICE IN ONE EXPRESSION**, NOT TWICE IN A BODY

`Bool.and(eq_dt(x, y), Bool.not(eq_dt(y, x)))` is refused with
`expected : y / observed : y (consumed more than once)`, and the fix is
`(+x: S.Dt, +y: S.Dt)`. This is not the affine rule ("a binder is used at most
once") -- the same two values are used once each in every `eq_node`/`eq_paramarg`
ladder in `uop/ops.bend` and those compile, because they go through a `match`
that BINDS a fresh name per case. The distinction that matters: passing a binder
to two calls in the same expression needs `+`; passing it to two calls in two
DIFFERENT `case` arms does not. Getting this backwards costs a rebuild.

### 4. `U32.show` ON A NEGATIVE `i32` IS THE BIT PATTERN, SO A GATE MUST SAY SO

`-7` in a U32 is `4294967289`, and a gate row that prints the raw U32 next to a
comment saying `-7` is a gate that needs mental arithmetic to read -- which is
the failure the repo already hit once. The fix that costs nothing: put the
pattern in the ROW NAME (`ok_fd_4294967289_4`) rather than in a comment, and have
the Python oracle print `v & 0xFFFFFFFF`, so both sides are in the same alphabet
and `diff` is the test. Sign is then visible in the number, not inferred.

### 5. A `(Bool, Bool)` FLAG PAIR IS NOT INTERCHANGEABLE, AND WHICH HALF IS
###    CONSULTED IS THE WHOLE DEFINITION

`floordiv_i32.trunc.exact(exact, neg, q)` was right for exact divisions, right
for negative dividends, and wrong for same-sign inexact divisions: it applied
`q + 1` on the inexact arm unconditionally. The arithmetic is not subtle --
`x // y` is the truncation, and the truncation is ALREADY the floor whenever the
two signs agree, so the step belongs to the opposite-sign case alone (`-7 // 4`
is `-2` because `-1` truncates but `-2` floors). It went unnoticed because the
two wrong cells and the two right cells interleave, and the fixture set happened
to hold the right ones.

**So a two-flag ladder wants a truth table written out before it is written in
Bend, and it wants the fixture set to hold one row per cell.** All four cells
here are cheap: same-sign/inexact, same-sign/exact, opposite-sign/inexact,
opposite-sign/exact. A sign matrix is the same idea and generalises: four
combinations of `(x<0, y<0)` times inexact/exact is eight rows, and it is what
`.agents/slop/dm.bend` now holds.

### 6. FLOOR AND TRUNCATION ARE TWO FUNCTIONS AND BOTH GET PORTED, SO "DELETE
###    THE DUPLICATE" IS USUALLY THE WRONG MOVE

`helpers.bend` carries `floordiv_i32`/`floormod_i32` (helpers.py:76-77, Python's
`//` and `%`, i.e. FLOOR) beside `cdiv_i32_go`/`cmod_i32` (helpers.py:73-74, C
semantics, i.e. TRUNCATE). They are not a stale duplicate of each other, and
`ceildiv` (`-(num // -amt)`) and `round_up` (`(num+amt-1)//amt*amt`) are floors
that CANNOT be spelled with the truncating pair -- measured, `ceildiv(10,4)` is 3
and neither `-cdiv(10,-4)` (2) nor `-cdiv(-10,-4)` (-2) gives it, and
`round_up(-10,4)` is -8 while `cdiv(-7,4)*4` is -4.

So when two same-shaped functions disagree, **check what the CALLERS need before
proposing to delete one.** A caller is the evidence; three callers all wanting
FLOOR is what settles it. And when a wrong def sits beside a right one, the fix
is to make the wrong one right AND say in a comment which pair is which, because
the next reader cannot tell an intentional pair of functions from an accidental
copy.

### 7. A COMPILED ARENA MAKES A `Dt` A KEY, SO A `Cls` COMPARISON IS NOT A COSMETIC
###    BUG EVEN WHEN EVERY FIXTURE IS A DIFFERENT `pri`

`eq_dt` also compares `pri` and `bits`, so a conflated `Cls` is invisible on any
pair of DIFFERENT dtypes -- `eq_dt(weakfloat, half)` was already `False` because
`9 != 12`. The only reachable symptom is a dtype compared to ITSELF, and the only
code that does that is the hash-cons table, so the gate needs a row that builds a
node twice and counts nodes, not a row that compares two dtypes. Building the
smallest such node is worth the trouble: `bottom + CONST + CAST + CAST` is three
nodes when the two CASTs intern and four when they do not, and the count is a
number the oracle can be asked for.

### 8. `.venv/bin/python`, NOT `python3`, FOR A GATE THAT IMPORTS THE ORACLE

`tinygrad.helpers` imports cleanly under the system `python3`, but the house
invocation pattern is `uv run --with tabulate python3` / `.venv/bin/python`, and
`mutate-*.py` scripts that shell out to a gate should use the venv explicitly so
they do not depend on the ambient `PYTHONPATH`. Related and cheap: a shell gate
script that `cd`s must use an ABSOLUTE path for its own siblings -- `$0` is
relative to wherever it was invoked from, and `$(dirname "$0")/../..` from
`.agents/slop/tools/` is `.agents/`, not the repo root. That cost two rounds.

## MEASURED: the Bend INTERPRETER has a hard 32 KiB input cliff

The generic advice is that a Bend "machine stack overflow" is a runaway expansion.
That was wrong for the one case we actually hit. Measured on a pure-whitespace
`.js` input, so the LEXER NEVER RUNS:

| input | interpreter |
| --- | --- |
| 4 KiB .. 24 KiB | exit 0 |
| 32768 B | exit 1, `bend: memory fault (machine stack overflow?)` |
| 49152 B, 65536 B | exit 1, ditto |

The COMPILED lane reads 96 KiB of the same input, and tinygrad's own `ops.py` at
110 KB, without complaint. So:

- the threshold is exactly 32768, which is a HOST constant, not a property of our
  recursion depth -- the `.js` lane splits on whitespace and is shallow, yet it
  dies at the same byte count as the tokenizing `.py` lane;
- the diagnostic message says "stack overflow", which sends you looking for a
  non-terminating or over-deep fold in YOUR code. There is none here. **If the
  failing input is at or above 32 KiB and the compiled lane is fine, stop hunting
  and use the compiled lane.**

This BOUNDS THE GATE, which is the part worth writing down: an interpreted lane
cannot exercise any fixture of 32 KiB or more. Those rows are compiled-lane-only,
and a file whose gate claims otherwise is overstating what it checked.

The earlier reading of this -- "a fold whose fuel never reaches zero", which is
cause 1 in the section above -- was right in general and wrong here. Both
descriptions produce the same message, so distinguish them by INPUT SIZE first:
small input that hangs is our bug; input at or above 32 KiB that dies is the host.

## TWO BENCHMARK LESSONS, BOTH LEARNED THE EXPENSIVE WAY ON `sz`

**1. "x100-x1000 slower" was asserted from MECHANISM and was wrong.** Before
measuring, the claim was made that the port was 100-1000x slower than CPython,
derived from: a Bend `String` being a linked list of `Char`s, `String.trim` being
`reverse . trim_start . reverse` (three rebuilds per line), `lex` doing
`chars(s) = List.reverse(chars.go(...))` (two full copies of the file), and every
`U32` op being a net node rather than a machine instruction. Every one of those
facts is real and measured. **The product of them was never measured, and it is not
the slowdown.** The compiled lane lands in CPython's own range. Mechanism explains
a cost's *existence*; it never predicts its *magnitude*. Estimate, then measure,
and never let the estimate be the finding.

**2. Process-per-invocation timing cannot measure anything this fast.** Timings
taken that way were dominated by startup and were non-monotonic in input size --
native got FASTER as the tree grew (0.154s -> 0.049s), and CPython took 1.18s,
then 0.41s, then 0.15s for MORE input. An empty tree costs 0.00s, so a real
workload needs to be big enough to swamp it, or measure in-process with min-of-N.

**AND THE ONE THAT MATTERS MOST: compare like with like, or you will "find" a bug
that is not there.** Diffing `/tmp/sz .` (full display, including directory
aggregate rows) against CPython's bare `gen_stats()` (flat file table only) showed
"124 files vs 114" and looked like ten spurious directory rows. It was the harness.
Running the real CLI on both sides gives **byte-identical output on the real
`tinygrad/` tree, 131 of 133 lines, the only two differences being `ops: 77` and
`flags: 55`** -- the two `len(Ops)` / `len(ContextVar._cache)` reflection lines
`sz.bend` documents as not portable. A synthetic fixture suite said nothing about
this, because it never contained a real repository.

A speed or equality claim is worthless until you have checked the two sides do the
SAME WORK. This repo already had one instance of that class shipped (a dropped
index aliased a FLOORDIV and printed a plausible answer) and one gate row that
merely restated the code. Check the output before quoting the number.

## CORRECTION to the "32 KiB cliff" entry above -- the number was not reproducible

The entry above claims the interpreter dies at EXACTLY 32768 bytes and calls it a
host constant. **That precision is false.** Re-running the identical 24576-byte
case: it read `exit=0` on a quiet machine and `TIMEOUT >45s` on a loaded one. Load
average was 38.8 on 12 cores -- 3.2x oversubscribed -- at the time of the failing
run.

So the correct statement is:

- there IS a size-dependent failure in the INTERPRETER, and the compiled lane is
  unaffected;
- the threshold is NOT a fixed byte count. It moves with available CPU and memory,
  so ">= 32 KiB dies, below that it is fine" is NOT a usable rule and must not be
  relied on or written into a plan;
- what survives from the original entry is the DIAGNOSTIC: if the interpreter dies
  and the compiled lane is fine, stop hunting for a non-terminating fold in your
  own code. That is still good advice, because the failure really is the host's.

This is the third time in this session that a confident number written into these
notes turned out to be an artifact of when it was measured: first "x100-x1000
slower" (mechanism, never measured), then "124 vs 114 files" (a harness that
compared the full display against a bare `gen_stats`), now "exactly 32768" (a
quiet machine). **Measure under load, or do not claim precision.** A specific
number with no error bar is worse than a range, because the next agent cannot tell
which part to distrust.

## PEER-LANGUAGE REFERENCE SOLUTIONS, FOR THE WALLS THIS PORT KEEPS HITTING

Every wall hit in the sz/render work is a solved problem elsewhere. Not measured-Bend
rules; references so the next agent does not re-derive them.

1. NO MUTATION / accumulators threaded through recursion. Reference: Koka's
   PERCEUS reuse analysis (Xie & Leijen, OOPSLA 2021) -- "Functional but In-Place"
   (FBIP); uniqueness types in Clean (1995); Lean 4 reuses uniquely-owned nodes.
   Bend HAS the static half (+ and &n ownership) but not the reuse pass, which is
   why Array.set does not mutate in place (see the fold.bend Table note).

2. String IS A LINKED LIST OF CHARS (String.trim = two reverses; lex copies the
   file twice via chars() + List.reverse). Reference: Haskell's `text` library
   (the community treats String=[Char] as a mistake it migrated off); Roc built
   packed UTF-8 Str from day one. Until Bend ships packed strings, hot paths
   should consume a char list in ONE pass; do not call String.trim in a loop.

3. NO os.walk / filesystem effects in base.bend. Not a research problem: just
   library maturity (Haskell System.Directory). Keep the foreign effect + TODO.

4. Dev loop where every expectation is manufactured by a hand CPython round trip,
   and bugs slip that reading cannot see. Reference: PROPERTY-BASED TESTING --
   QuickCheck (Claessen & Hughes, ICFP 2000), Hypothesis in Python. State the
   property `forall src. lexer(src) == cpython_tokenize(src)` and generate; the
   sz 4 lexer bugs and the upat repeat bug are exactly what a generator finds.

5. List.append O(n) / spent-on-read accumulators. Reference: Bagwell's HAMT
   (2000) -> Clojure's persistent vectors. Reach for a tree-shaped accumulator
   before threading a List, when the fold is hot.

## NINE MORE RULES, MEASURED 2026-09-30 SPLITTING THE FILESYSTEM WALK OUT OF `sz.bend`

### 1. `--check-only`'s FOREIGN NOTICE IS A "WHO NAMES WHOM" CLOSURE, AND `@unsafe`
###    DOES NOT SHRINK IT

`bend2/main.ts`'s `book_promises` seeds a `bad` set with every def that is
`@unsafe` OR foreign, then floods back along every "names" edge (a def's type and
its body term). So the count is a REACHABILITY closure and the only way to shrink
it is to shrink the set of defs that name the foreign one. Measured on `sz.bend`:
marking `Sz.read_dir` and `Sz.is_dir` `@unsafe` left the count at exactly what it
was, because both were already in the seed set as foreign. `@unsafe` is a promise
you make, not an exemption you take.

The practical consequence is an ARCHITECTURAL one, and it is the same for every
port that needs the filesystem: keep the impure loop in as few defs as possible and
give the pure consumers a value parameter. In `sz.bend` that took the notice from
10 defs to 7 -- the two effects, the three defs of the walk, and the mode dispatch
that has to call it -- and left the lexer, both tables and `gen_diff` proving.

### 2. A `U32` LITERAL PATTERN IS A PREFIX MATCH, AND THE ERROR SAYS NOTHING USEFUL

`case 1: ...` then `case 0: ...` is refused, because `1` claims every successor, so
the `0` arm is dead and the match is not exhaustive. The message is

    - expected : cases for True
    - observed : \{}

which is the checker explaining its `Empty`-match DEFAULT against `Bool`, not your
arm order. Write `case 0:` first, or end with `case _:`. (Same fact as §1.1 rule
9 here, but the diagnostic is the trap, and the first wall cost twenty minutes.)

### 3. `Data` TYPES ARE NOMINAL, so two records with the same fields are TWO TYPES

    type D1 is Data: D1{a: String, b: String}
    type D2 is Data: D2{a: String, b: String}
    def take(d: D2) -> String: ...
    take(make())            #| - expected : D2 / observed : D1

Useful, not a nuisance: it is how `sz.bend` keeps the walk's worklist of
directories (`Dir`) distinct from the list of files it answers with (`It`), even
though both are a path to read and a path to print.

### 4. TWO SELF-CALLS IN ONE ARM IS REFUSED EVEN WITH TWO DIFFERENT `Nat` FUELS

    def p4(k: Nat, j: Nat, n: U32) -> U32:
      match k:
        case 0n: n
        case 1n+r: p4(j, r, U32.add(n, 1))
    #| - expected : a decreasing self-call
    #|             (arguments are read left to right: each passed unchanged until one shrinks)

So a def cannot fold over two lists by recursing twice per arm. This is why
`os.walk` cannot become ONE def over a worklist of directories AND a list of that
directory's names, and why the per-name loop has to be a def of its own that the
caller calls once per directory.

### 5. A LIST SELF-CALL MUST SHRINK ITS FIRST ARGUMENT, SO A GROWING ACCUMULATOR GOES SECOND

    sz.rows(List.append(&2, Row, xs, [rr]), rest)     #| expected : rest, observed : rest
                                                      #|  (consumed more than once) / not decreasing
    sz.rows(rest, List.append(&2, Row, xs, [rr]))     # WORKS

Read left to right, each argument is passed unchanged until one shrinks, so the
tail comes first. The consequence worth remembering: the accumulator may then be
read only ONCE per arm, which rules out the `Bool.pick(cond, rec(xs'), rec(xs))`
shape and wants the pick hoisted into its own `x : List<...> =` binding first.

### 6. AN `IO` EFFECT IS NOT A VALUE: `f(walk(...))` IS A TYPE ERROR, `f`'s arg must be pure

    sz.one(walk(16777216n, Nil{}, [Sz.root(".")]))
    #| - expected : List<&2, Dir>
    #| - observed : @-R:Type -> @k:(@_:List<&2, Dir> -> IO.OP<R>) -> IO.OP<R>

`do` blocks desugar to binds, so an effect in an argument position is read as the
CONSUMER of a bind that has not happened. Bind it in the enclosing block and pass
the name. A `Bool.pick` branch, by contrast, MAY be a `do` block -- that is how
`sz.main` gets three different walks out of three arms.

### 7. A `match` CANNOT FOLLOW A `<-` BIND INSIDE A `do` BLOCK

    do IO<U32>:
      s : String <- IO.get_env("X")
      match s:                  #| - expected : a term (a match heads a def body, not a term)
        case SNil{}: ...

Same rule as everywhere else, restated because the do-block looks like a scope: the
`match` must be the whole body of a def whose parameter is the scrutinee. (So
`sz.main` is a def that takes the argv and matches, and `main` only reads argv.)

### 8. THE INTERPRETER'S PER-FILE BYTE CLIFF IS 28987/28988, NOT 32768

Measured by bisection on both lanes of `sz.bend`, twice, on a 63-space `.js` file
and on an `x=1\n` `.py` file:

    largest passing   28987 bytes
    first failing     28988 bytes   bend: memory fault (machine stack overflow?)

The two lanes AGREE byte for byte, the 63-space `.js` file never runs the lexer
and has the same cliff, and two `.py` files totalling 29000 bytes are fine in the
same process -- so it is a per-file limit on the host, not a lexer depth and not a
per-process total. The "about 32 KB" figure in `spec/sz.md` came from testing only
round sizes (4096..24576, then 32768). Bisect it, do not sample it.

### 9. THE INTERPRETED LANE RE-CHECKS THE WHOLE FILE ON EVERY RUN, SO BISECTING A CLIFF
###    IS DOMINATED BY THE CHECK, NOT BY THE PROBE

Each `./bin/bend FILE.bend ARGS` pays a full proof of all 220 defs before it reads a
byte of the tree, so 21 bisection steps is 21 proofs. If you are measuring something
in the interpreted lane, either budget 20s+ per probe or move the measurement into
the compiled lane and only spot-check the boundary in the interpreted one.

## NINE MORE RULES #2, MEASURED 2026-10-01 WRITING THE `uop/upat.bend` FUZZ DRIVER

### 1. A `match` ON A `String` NEEDS A `case _:`, AND WITHOUT ONE THE ERROR IS A PARSE ERROR

String-literal cases work on a `String` parameter. What does NOT work is leaving
the match without a catch-all, and the diagnostic points at the wrong thing
entirely -- it is a PARSE error about an SCon, at the `match` line, naming a
`{}` that appears nowhere near:

    def pick(tag: String) -> S2:
      match tag:
        case "x": S2A{1}      #| - expected : cases for SCon
        case "t": S2B{2}      #| - observed : \{}
                              #| Location: pick

`String` is a linked list of `Char` and the element type is not closed, so the
match is not exhaustive and the checker says so in the shape it has for a data
type. Adding `case _: S2B{0}` fixes it. THE TRAP IS THE MESSAGE: it reads like
"SCon" and it names `{}`, so the natural reaction is to go looking for an SCon in
the arms, and there is none -- a `SNone{}` three lines down is a red herring.
Measured on both an SCon-returning def and a two-constructor one; the return
type is irrelevant, only the missing catch-all matters.

### 2. `String.take`, `String.drop` and `String.split` CONSUME THE STRING

Every one of them takes their `String` by value, so a def that needs both the
head and the tail of one string needs `+`:

    def src.of2(s: String) -> O.SrcArg:      #| - expected : s
      drv.src.of(String.take(s, 1n),        #| - observed : s (consumed more than once)
        String.drop(s, 1n))

`+s: String` works because `String` is a linked list, so the cost is a reference
count like any other `Data`. This is the general case of rule 1.1 showing up
where nobody expects it: reading a string in two pieces is the most ordinary
thing a parser does.

### 3. `IO.args()` ANSWERS `List<&1, String>`, NOT `List<&2, String>`

A dispatcher that takes the argv tail must be spelled `&1`:

    def dispatch(ps: List<&2, String>) -> IO(Unit):   #| - expected : List<&2, String>
      ...                                            #| - observed : List<&1, String>

`sz.bend`'s `sz.main` takes `List<&1, Dir>` for the same reason. Reading an `IO`
value and then handing its payload to a helper is the only place the lifetime
shows up, and it is the difference between a file that checks and one that does
not.

### 4. `List.get` ANSWERS A `Maybe`, AND `String.get` ANSWERS A `Maybe<Char>`

    String.join(List.get(&2, String, xs, 0n), "")    #| - expected : List<&2, String>
                                                    #| - observed : Maybe<&2, String>
    String.get("abc", 1n)                            #| - expected : String
                                                    #| - observed : Maybe<&2, Char>

So every positional read needs a total wrapper (`upat.bend` grows two: `drv.one`
for `String` and `drv.nth` for `U32`), and `String.split(s, sep)` always answers
at least one piece -- `String.split("", ',')` is `[""]`, NOT `Nil{}` -- so a
`List.is_empty` test on a split result is the wrong emptiness test.

### 5. `String.to_u32` DOES NOT EXIST; `Char.to_u32` DOES, AND IT RETURNS A CODEPOINT

    String.to_u32("42")     #| - expected : a defined name
                            #| - observed : String.to_u32
    Char.to_u32('4')        # 52   (so a digit is `U32.sub(Char.to_u32(c), 48)`)

A decimal parse is therefore a fold over `String.to_list(s)` feeding
`U32.add(U32.mul(acc, 10), ...)`. `String.show` is also absent -- `U32.show`,
`Bool.show` and `Nat.show` are the printers -- and `String.is_empty` is absent
while `List.is_empty` is present, which reads as a typo rather than a gap.

### 6. A `match` INSIDE A `do` BLOCK IS REFUSED, SO DISPATCH GETS ITS OWN DEF

    def main() -> IO(Unit>Unit):
      do IO<Unit>:
        as : List<String> <- IO.args()
        match drv.rest(as):        #| - expected : a term (a match heads a def body, not a term)
          case Nil{}: gate()       #| - observed : 'match'

Same as rule 7 below, and it is the reason `upat.bend`'s `main` is three lines
over a `dispatch` def: argv is an effect, the choice on it is a match, and the
two cannot be one body. The `dispatch` def is the whole of the pattern -- it is
what `sz.bend` does with `sz.one`/`sz.two` and what every argument-reading
`main` in the port has to look like.

## SEVEN MORE RULES, MEASURED 2026-10-01 WHILE PORTING `uop/render.py`

### 1. `Map.put` IS NOT `Map.set`, AND `Map.put` LOSES KEYS
`Map.put` on a one-entry `MLeaf` is `MLeaf{k, x}` -- it REPLACES the leaf and drops
the old key. Three sequential puts gave `d[1]=three d[2]= d[3]=`. `Map.set` is the
inserting one and gives `d[1]=one d[2]=two d[3]=three`. If you are building a dict,
use `Map.set`.

### 2. `Map.get` ANSWERS A `Sigma`, NOT A `Maybe`
    def get.of(r: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
      match r:
        case Tuple{m, v}: v
    def get(a: Acc, k: String) -> String: get.of(Map.get(String, "", Acc.mm(a), k))
The `Sigma` type annotation IS the parameter type; `Maybe.default(.., Map.get(..))`
is `expected : Data -- observed : Quant`. `Map.has` is the same shape with `Bool`.

### 3. A RECORD PATTERN MUST NAME EVERY FIELD, IMPORTED RECORD OR NOT
`case O.ParamArg{slot}` is `a ops.ParamArg pattern with 13 fields`. This CORRECTS
the "may name fewer fields" note above: that was measured on a SEVEN-field record
and does not generalise -- and it does not generalise to locally-declared records
either (a three-field `Loc` with `case Loc{a}` is refused the same way). ops.bend
already carries all thirteen ParamArg accessors, which is why the repr reads
through `O.ParamArg.size(pa)` rather than destructuring.

### 4. `case +h <> t:` -- `+` ON A PATTERN BINDER RESOLVES "TWO READS IN ONE EXPRESSION"
Two answers out of one comparison that both feed one expression is the shape
    Bool.or(U32.is_lt(h, g), Bool.and(U32.is_eq(h, g), lt_u32(t, u)))
and neither `h` nor `g` can be a `let` (affine). `case +h <> t:` is the spelling
and it works because `U32` is `Data`. A helper def does NOT rescue it: it calls
back into the walk and that is the mutual recursion Bend refuses.

### 5. A SELF-CALL WITH A COMPUTED ARGUMENT IN FRONT OF THE TAIL IS NOT DECREASING
    def tr_all(+ss, +ar, +tr): match ss: case s <> t: tr_all(ar, tr_set(tr, s), t)
is refused; `tr_all(t, ar, tr_set(tr, s))` -- list FIRST -- is accepted. So the
shrinking argument has to be the FIRST parameter whenever another argument is a
computed value.

### 6. A `Nat` COUNTDOWN IS THE ONLY COUNTDOWN A U32 LOOP GETS
`tuple(range(n))` for a `U32` n cannot be a `U32` self-call (`expected : a
decreasing self-call`); it has to be `range_tuple.go(n: Nat, +p: Nat, acc)` with
`case 1n+p:` consing `U32.from_nat(p)`. The consed value and the fuel are the same
`p`, which is why `p` is `+`.

### 7. `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- AND GETTING IT
###    BACKWARDS EMITS A PLAUSIBLE STRING
`CallInfo(None, None, False, False)` for every dtype is what a flipped `Bool.pick`
looks like: it typechecks, it runs, and it is a string, not a crash. Three gate
rows over void / int32 / weakint caught it. `acall_void` also had to stop testing
`pri == 0` -- `S.void()` and `S.weakint()` BOTH have priority 0, so the void test
is `cls == CVoid`.

## THE UPAT DEDUP DIVERGENCE, ROOT-CAUSE CHAIN (2026-10-01, depth-8 fuzz case)

Symptom: same tag-filter node reachable via two clause branches gets ONE `a{n}`
in CPython (`tag in a2` everywhere) but a FRESH number per path in the port
(`tag in a7`), so the compiled text and the dyn_lookup arity differ. Gate rows
stay green; only the fuzzer at --max-depth 8 sees it.

Chain, each link verified by reading the code:

1. `wrap` is ONE walk over the WHOLE processed clause tree, threading a Bind
   list `d` and a counter `n` (upat.bend wrap.go / wrap.found). The dedup env
   IS global -- the bug is NOT a per-clause reset.
2. The dedup KEY is `eq_lit(Bind.lit(b), lit)` -- Lit VALUE equality.
3. `eq_lit` covers every Lit constructor, including LTag via O.eq_tag_list.
4. `O.eq_tag_list` compares lists ELEMENT-WISE IN ORDER. Python's tag filter
   is a FROZENSET. Order-sensitive list equality vs set semantics -- the same
   defect family as eq_cls (missing CWeakFloat arm) and eq_addr (Aalu answered
   as AReg): an equality predicate that does not match Python's semantics.
5. Python's `wrap` dedups by CLAUSE-NODE IDENTITY (each clause graph node is
   wrapped once), not by literal value. The port's value-keyed dedup and
   Python's node-keyed dedup agree on TREE-shaped patterns and diverge on
   DAG-shaped ones, where get_clause materialises one arena node into several
   clause positions.

The fix must make the port's dedup agree with CPython's on the harness case
(upatfuzz --seeds 51 --max-depth 8). Candidate directions, in order of
fidelity: (a) key the dedup by clause-node identity as Python does; (b) make
the list equalities set-semantics where Python's are sets; measure which one
CPython's _get_clause actually exhibits BEFORE choosing -- read upat.py.

## FIVE MORE RULES, MEASURED 2026-10-01 WRITING THE `uop/divandmod.bend` FUZZ DRIVER

### 1. A `match` MAY NOT SCRUTINISE A COMPUTED VALUE -- THE `.go` SPLIT IS NOT OPTIONAL

    def dmc.num(s: String) -> U32:
      match String.starts_with(s, "-"):        #| - message : a parameter or field scrutinee
        case True{}: ...                       #| - observed: (a match cannot scrutinize a computed value)

The rule is already known for a PROJECTION (`n.f` parses as a name lookup); this
is the same rule for a CALL. Every `def f(x) -> T: match g(x): ...` must become
`def f.go(gx: T, x: T) -> R: match gx: ...` + `def f(x) -> R: f.go(g(x), x)`.
The error names the scrutinee expression, which is the useful half: it points at
the CALL, not at the `match`.

### 2. THE `+` PROPAGATES ONE READER DOWN, AND `List<&2, T>` IS NOT `List<&1, T>`

    def dmc.den.mul(ar: O.Arena, m: U32) -> U32:
      U32.mul(dmc.den.c(ar, O.Arena.src0(ar, m)), dmc.den.c(ar, O.Arena.src(ar, m, 1)))
      #| - expected : m     - observed : m (consumed more than once)
      #| Context: - ar : O.Arena
    def dmc.den.mul(ar: O.Arena, +m: U32) -> U32: ...   #| - expected : ar  - observed : ar (consumed more than once)
    def dmc.den.mul(+ar: O.Arena, +m: U32) -> U32: ...  # ok

The compiler does NOT tell you the whole chain: it stops at the first parameter
it can blame, names THAT one, and prints the rest as `Context:`. Fixing the named
one exposes the next, so the arithmetic above took four compiles to green. The
lesson is that `+` is transitive UP the call chain, not just local to one def --
budget an edit per error rather than assuming one error is one fix.

### 3. A `Maybe` FROM `List.get` NEEDS THE SPLIT EVEN INSIDE A `match` HEAD POSITION

    def dmc.two() -> List<&2, O.Op>:
      match List.get(&2, O.PMEntry, O.PMEntrys.es(dm_table()), 2n):
        case Some{e}: O.PMEntry.ops(e)      #| - message : a parameter or field scrutinee
        case None{}: Nil{}

Rule 1 again, and it is the one that bites a PARSER hardest because a parser is
mostly `match` over `Maybe`s read out of a list. The split is mechanical and
`upat.bend`'s `drv.one` / `drv.nth` are the precedent: one total reader per
element type, and the `match` reads a PARAMETER.

### 4. AN ARENA IS A `Data`, AND `Found.ar` / `Found.i` ARE NON-CONSUMING READERS

    def dmc.of.put(+f: O.Found) -> String:
      dmc.of.put.go(dm_zero(O.Found.ar(f), O.Found.i(f)),
                    div_and_mod_symbolic(F.folded(O.Found.ar(f)), O.Found.i(f)))   # ok

Three reads of one `+Found` check, because `Found.ar`/`Found.i` are
`def Found.ar(f: Found) -> Arena` -- no `+`. So a LINEAR record's readers need
no `+` themselves and a `+` value can be read any number of times THROUGH them.
This is the opposite of `String.take`/`String.drop` (rule 2 of the `upat.bend`
set above, which DO consume), and the two being opposite is the whole trap:
whether a reader consumes depends on whether the type is a linked list or a
record.

### 5. AN UNFILLED LAW IS A HARD ERROR, SO A DEF MUST BE DEFINED BEFORE IT IS CALLED

    def dmc.of.put(+f: O.Found) -> String:
      dmc.of.put.go(...)                       #| - expected : a filled definition
                                               #| - observed : dmc.of.put.go   (an unfilled law is a dead claim)

Bend is order-sensitive top-to-bottom. The `go`-before-caller convention that
makes rule 1's split work is ALSO what makes this necessary, and the two rules
pull in the same direction: **define the leaf `match` first, call it second**.
Reading order top-to-bottom is the one habit that satisfies both.

## SYMBOLIC.BEND — TWO FINDINGS FROM THE FUZZ ATTEMPT (file restored to green)

The symbolic fuzz agent broke the file mid-driver and was rescued by restoring
its last verified copy (`_sym_dbg.bend`). Its driver work was discarded; these
two READING findings survive and are ungated:

1. sym_10 (symbolic.py:463, `UPat.var("x") * UPat.var("x")`) is a REAL DIVERGENCE
   the port's own header half-documents: Python's UPat cache INTERNS BY NAME, so
   the second `var("x")` is the same STORE that the first overwrites -- the
   compiled form matches 1/(x*y) too. The port's `p_same` check is STRicter, so
   it matches strictly FEWER nodes than Python. The gate's `sym_rebind` pair
   covers only sym_7 and sym_8. Decide: match Python (drop the check) or record
   the divergence as deliberate; either way it needs a row.

2. symbolic.py:124 `((x%y)%y -> x%y)` is DEFERRED but invisible: absent from
   sym_table AND from the TODO block, so `skip=114`'s arithmetic does not count
   it. A rule absent from both is a bookkeeping hole, whatever the reason.

Driver lessons (its design notes are in the file history): the s-expr tokenizer,
Frm/St arena builder, and IO.args() convention were sound; the fz_jobs fuel must
be ONE Nat split across branches -- a rebuilt `[a] <> rest` is rejected by the
checker ("expected a decreasing self-call"), and List.range(4096n) is not in
Base's surface the way it was used.

## FOUR MORE RULES, MEASURED 2026-10-01 WHILE FIXING THE UPAT WAITLIST

### 1. A FOLD THAT ALSO CARRIES A CHANGED-BIT MUST `or` THE WHOLE LIST, NOT THE HEAD
`proc.go` returns `Pg{cs, ch}` per LIST, and the list's `ch` has to be
`Bool.or(head's ch, tail's ch)`. Returning the head's bit alone type-checks,
`--check-only` is green, and the gate is green, and the fold is wrong: a parent
reading `b.ch` sees only its FIRST child, so it runs while a LATER sibling is
still moving. Caught by `store_ord` and `deep` below, and by `upatfuzz` seed 40.
`proc.join` is one line and it is the whole difference between the two builds.

### 2. `+` ON A `Data` FIELD BINDER IS A COPY AND IS NEEDED TO USE IT TWICE
`case Pg{+cs, ch}:` then `C{op, lit, cs}` and `do_process_and(op, lit, cs)` in one
expression. Without the `+`: `cs (consumed more than once)`. The same on a
parameter (`def f(+a: Pg, +r: Pg)`) and on a list binder (`case +c <> t`).

### 3. A `match` CANNOT SCRUTINISE A COMPUTED VALUE -- GIVE IT ITS OWN DEF
    match Pg.ch(b):                     #| - expected : a term
                                        #| - observed : 'match'
`match b: case Pg{cs, ch}:` then `match ch:` nests, and the record binder is the
scrutinisee. This is why `proc.node` is a separate def from `proc.step` rather
than one `Bool.pick`.

### 4. A DEF MUST BE DEFINED BEFORE IT IS CALLED, AND THAT IS NOT DEF ORDER
`proc.node` calling `proc.go` is fine in either order, but a def calling a LATER
def is `a filled definition (an unfilled law is a dead claim)` -- a message that
names the callee and not the caller, so it reads like a `LAWS.bend` problem. And
`dbg.go` calling `dbg.node` calling `dbg.go` is refused outright: MUTUAL RECURSION
IS OUT, so a recursive printer has to carry its own fuel AND its own name
(`dbg.op` for the leaf case) instead of splitting into two mutually recursive
defs. Same answer as rule 5 of the SEVEN MORE RULES, reached from the other side.

### 5. A `Nat` FUEL BOUND IS A BOUND, AND A WAITLIST MAKES IT MUCH LOOSER
`proc_fix` used to be a fixpoint on a DEPTH (splice one AND level per round) and
`8 * len(upats)` was ample. It is now the `unified_rewrite` WAITLIST -- a node
runs its rule only when its children are final -- and the deepest shape the
fuzzer reaches needs 33 to 48 ROUNDS for FIVE arena UPats, i.e. 9 to 12 rounds
per UPat. `8n` was short by four rounds and the port answered `NONE` where
CPython answered five lines of clause. `12n` is the smallest multiplier that
reaches the fixpoint; the file uses `32n`. A BOUND may be over-provisioned and
costs nothing -- an under-provisioned one is a silent wrong answer, and it is
the WORST failure mode in the file because every other row still passes.

## FOUR MORE GENERAL RULES, MOVED OUT OF movement.bend AND weak.bend 2026-10-01

A pass over `uop/movement.bend` and `uop/weak.bend` cut their comments back to tinygrad's
shape. These four were general Bend rules living in those files' headers; they are recorded
here so the next agent does not re-derive them from a file that no longer states them.

1. **A PAIR IS A `Type`, SO A TWO-FIELD `Data` RECORD IS THE SPELLING OF `(A, B)` -- AND A
   `Type` CANNOT BE A LIST ELEMENT.** Already recorded for `Found` ("an `Arena & U32` pair
   is a `Type` and cannot carry a `+`", this file's THE ENGINE SHAPE) and for `Seen.parts`;
   what the files were also carrying locally is the LIST half: refused with
   `expected : Data / observed : Type`. That is why movement.bend's `Marg` -- Python's
   `(o, n)` margin pair -- is a two-field `Data` record and not the tuple
   `(H.I64 & H.I64)`: `List<&2, H.I64 & H.I64>` does not compile.

2. **A `Maybe` CANNOT BE A FOLD'S ACCUMULATOR.** `Maybe<a, A>` is affine and has no `+`
   spelling, so it cannot be threaded through a recursive walk. Two consequences seen in the
   port: a fold whose accumulator would be a `Maybe` is written as TWO folds over the same
   list (movement.bend's `as_shape.allc` + `as_shape.vals`, splitting
   `tuple(s.val if s.op is CONST else ssimplify(s) ...)`), and an answer that must be read
   twice is hoisted into a `Data` record carrying a `Bool` plus the value (weak.bend's
   `Dts` for `derived_dtypes`, `ODt` for `commit_weak_consts`'s `dt:DType|None`).

3. **THE FOLD-VERDICT SHAPE: ONE DEF, THE ELEMENT'S VERDICT AS A PARAMETER.** A fold over a
   list whose accumulator is a `Bool` and whose step needs to READ the accumulator cannot be
   written `.go` + wrapper: the wrapper would call the fold and then need the fold to call
   it back, which is mutual recursion. The port's shape is a single def taking the
   accumulator as a PARAMETER and matching on the ELEMENT in the head -- movement.bend's
   `mp_ident.at` and `mp_5.each.at`, whose comments both name the reason. Same family as "a
   `match` may not scrutinise a computed value" above; this is the fold-shaped escape from
   it.

4. **A LIST BINDER, LIKE A PARAMETER, IS READ-AT-MOST-ONCE.** `case m <> t:` with `m` of
   record type gives an affine binder, so `Marg.o(m)` and `Marg.n(m)` in one expression is
   refused exactly as a parameter used twice would be. `+` on the pattern binder fixes it
   (the render.bend entry "`case +h <> t:` -- `+` ON A PATTERN BINDER RESOLVES TWO READS IN
   ONE EXPRESSION"), or hoist the pair into a def taking the record whole, which is what
   movement.bend's `marg_pair.of` does.

## FOUR MORE RULES, MEASURED 2026-10-01 WHILE PORTING `uop/divandmod.bend` and
## `uop/symbolic.py`

Appended, not edited. All four are Bend 2.0.34 / substrate facts, so they were
cut out of the two `.bend` headers where they had drifted into file-local prose.

### 1. A 64-BIT PRODUCT IS A WALL, NOT A TODO: `base.bend` DOES NOT EXPORT `Word`

`Word.mul` is the only widening multiply in Bend 2, and `base.bend` does not
export `Word`'s constructors -- `match Word.mul(64n, ...)` from outside the file
is refused with "a declared constructor (unknown: Word.Nil)". So a magic multiplier
(anything needing a 64-bit product) cannot be written from a `.bend` file at all,
and that is a wall of ONE export: either `Word` and `WCon` become public, or the
port writes the product as four `U32` multiplies and a carry chain (`U32.mul`
already truncates mod 2^32, so it composes).

The same wall one level up: `H.I64{hi,lo}` exists in `helpers.bend` with
`i64_add` / `i64_sub` / `i64_cmp` and NOT `i64_mul` / `i64_div` / `i64_mod`. So
`UOp._min_max` and `const_factor` are blocked on arithmetic, not just on shape.
`_min_max` is the unlock for five of `divandmod.bend`'s TODOs and nine of
`symbolic.bend`'s, which is why it is the first item in both "WHAT NEXT" lists.

### 2. TWO FIXTURE BUILDERS THAT RETURN AN INDEX ARE THE SAME TRAP AS ONE

The `divandmod.bend` version (`Arena` is affine, so a fixture builder that returns
`-> U32` throws the grown arena away) is recorded above as "A FIXTURE BUILDER THAT
RETURNS AN INDEX THROWS THE GROWN ARENA AWAY". The `symbolic.bend` variant is
slightly different and worth separating: there the rule table itself returns
`Maybe<&1, U32>`, so a gate row cannot read the rewritten node back at all, because
`Arena.node` answers `Arena.bottom` for an index past the end. The rows that work
around it are "did the rule fire" (a `Bool`) plus "what is the value" (computed by
calling `exec_alu` directly). **`Maybe<&1, O.Found>` is the shape a growing rule
should have** -- `Found` is `Data`, so it is expressible -- and it is the first
change to make when a rule table passes a dozen entries.

### 3. A GATE ROW THAT SAYS WHAT A BOOLEAN CANNOT IS NOT OPTIONAL

`x // x -> 1` needs TWO rows: one where the two srcs are the SAME node and one where
they are two DIFFERENT nodes. Drop `U32.is_eq` from the pattern and the positive row
still passes -- so the pair is the only thing that can see the identity check
disappear. Two instances in this port (`sym_7`/`rebind`+`rebind0` and
`sym_8`/`xorb`+`xorb0`), both measured.

The negative side must ask for ABSENCE, not for an index: written as `eq_u(m, 0)`
the row is satisfied by any wrong-but-present answer. Ask `Maybe.is_none`.

And the same shape for first-wins: a fixture where the two claiming rules AGREE
cannot distinguish first-wins from last-wins at all.

### 4. A `list`-TAIL FOLD THAT MUST HAND SOMETHING BACK CARRIES IT IN A RECORD

`upat.bend` records "A `Data` RECORD IS HOW A LIST TRAVERS WITH SOMETHING DERIVED
FROM IT" for `Shapes{ds, m}`. The `symbolic.bend` form is the same fact one level
up: an s-expr builder pushes a frame on `(`, pops it on `)`, and the finished node
has to get OUT to the frame above -- which a list tail cannot carry, because the
tail is the only thing that survives the recursion. So the answer rides in the
STATE (`St{ar, stk, root}`) rather than in a return value, and the walk is one
def. The same shape is `exec_alu`'s `Opr{fit, bits, f}` and `rm_0.ok`'s
`(hit: Bool, ok: Bool, ..., z: U32)`: whenever a fold must answer both a thing and
a fact about it, both travel together.

## SZ PERFORMANCE BASELINE, MEASURED 2026-10-01 (load recorded, min-of-N, floors subtracted)

Whole tree (114 files, 25591 lines, 2.04 MB): compiled sz.bend work = 165 ms vs
CPython gen_stats 369 ms at load 27-34 -> 2.24x FASTER. Per-file lexing of
uop/ops.py (110 KB): 8.1 ms vs 18.4 ms at load 47. Ordering stable across a 3x
load swing (min +-3%). Verdict: keep as-is; the owner ruled, and the profile
backs it (the per-char step's 5-deep call chain dominates, not the state width).

A measured-and-reverted option exists: deleting chars()'s two per-file copies
(String-fuel lexer) is -18% tree / -11% file and -7 LOC, byte-identical, patch
at /tmp/opencode/szbench/OPTION-string-fuel.patch. Not applied: owner said keep;
the mutation table was not re-run under it.

TWO SEMANTICS FINDINGS (decisions, not speed):
1. Fuzz seed 13 fails at --seeds 30 on the KNOWN rounding divergence: 109/20 =
   5.45, CPython %.1f formats the double 5.4500000000000002 as 5.5, exact
   rational rounds 5.4. So 'fuzz-green at 30 seeds' was never true; the real
   tree is green because no counted file hits an exact tie. Record before
   anyone treats a red --seeds 30 as a regression.
2. LATENT .js-LANE DIVERGENCE: base.bend Char.is_space = {0x20} U [9,13]; Python
   str.isspace also holds 0x1c-0x1f, 0x85, 0xa0, 0x1680, 0x2000-0x200a, 0x2028,
   0x2029, 0x202f, 0x205f, 0x3000. A line like \x1c//c counts for the port, not
   CPython. sz.bend's is_hspace already includes 28-31 (internally inconsistent).
   No tree file and no fuzz fragment hits it -- latent, not live.

---
Measured on 2.0.34 while porting `tinybendygrad/mixin/dtype.bend`. Four new rules, and
one correction to an old one.

1. `def some: U32 == other` is REFUSED -- "expected a term, observed '='". There is no
   `==` on `U32`; it is `U32.is_eq(a, b)`. This is separate from rule 9 below, which is
   about `+`/`-` needing an annotation. A sed that writes `==` produces a parse error
   whose message names `':'`, not the operator, so it reads like a match-syntax bug.

2. `case _ <: f(x)` is NOT the catch-all spelling of a numeric countdown. It parses as
   "expected a term, observed ':'". `case _:` is the catch-all; and when the scrutinee
   is a `Nat` that is also the fuel, destructure it as `case Succ{p}:` and recurse on `p`
   (the shape helpers.bend:399 and :474 already use). That gives a decreasing self-call
   with no `Nat.sub` and therefore no type annotation, which is the real point.

3. A def whose name merely LOOKS like a qualified name is not rescued by existing: writing
   `F.Founded` instead of `F.Folded` compiles to "expected a defined name, observed
   'F.Founded'", which is indistinguishable from rule 1 (no forward reference) unless you
   notice the name is misspelled. Check the spelling before hoisting anything.

4. CORRECTION to the brief's rule 4 area: `Maybe<&1, T>` and `Maybe<&2, T>` are NOT
   interchangeable in a parameter position, and the error names the LIFETIME, not the
   type -- "expected : Maybe<&2, U32>, observed : Maybe<&1, U32>". A `Data` field holding
   `List<&2, Maybe<&2, U32>>` pins its consumer helpers to `&2`; every shared file that
   passes a `Maybe` around already uses `&2` (fold.bend:270, helpers.bend:435). Do not
   write `&1` in a helper that receives one of those.

5. `Some{v}` with an unused binder is REFUSED -- "a Some pattern with 1 field" (this is
   rule 14 in the brief, re-measured, and it applies to `Maybe` as well as to records).
   The one-line shape `case Some{}: False{}` is NOT available. For a predicate that
   ignores the payload the honest spelling is a tautology on the payload, e.g.
   `case Some{u}: Bool.not(U32.is_zero(U32.sub(u, u)))`, which reads as "always False"
   without naming a sentinel. CAUTION: that shape is easy to get wrong in the other
   direction -- see the mutation note in mixin/dtype.bend, where `u32_none` was first
   written `Bool.not(U32.is_zero(v))`, which is TRUE for any non-zero value and silently
   inverted the whole refusal test. A `Some` arm that is supposed to be a constant False
   is the highest-risk line in a gate file.

---

## Measured by the `schedule/memory.py` port, 2026-10-01. Reproducers in this section.

### A. `List.append` IS `xs ++ ys` -- IT APPENDS. It is the single most expensive
###    misreading in this port, and everything downstream of it looks like a Bend bug.

`List.append(a, -A, xs, ys)` (base.bend:822) is `xs ++ ys`: **`ys` lands at the
TAIL.** So an accumulator fold written `List.append(&2, T, acc, [x])` builds the list
in FORWARD order, and one written `List.append(&2, T, [x], acc)` PREPENDS.

Reproducer, one line, `.agents/slop/notes/probe-list.bend`:

    List.append(&2, U32, [9], [8])        -- head 9, second 8
    List.append(&2, U32, [8], [9])        -- head 8, second 9

**Both `List.append` and `List.reverse` are correct.** `List.reverse` reverses a
literal list, a computed list, a one-field record and a three-field record
(`probe-list.bend`, `probe-list2.bend`). An earlier revision of this file claimed
`List.reverse` "silently stops reversing once the fold is two steps deep". **That
claim is FALSE and is retracted**: the accumulator in that experiment was being read
backwards because the code PREPENDED where it meant to append, and the reverse was
faithfully reversing a list that was already the wrong way round.

`List.sort` is correct and STABLE -- see section B.

### B. `List.sort` IS STABLE, AND A COMPARATOR THAT SAYS FALSE IN BOTH DIRECTIONS
###    SORTS IN REVERSE. The comparator is where the bug is, always.

`List.merge.step` (base.bend:1015-1023) takes `x`, the FIRST run's head, whenever
`le(x, y)` holds, and `le` is a `<=`. That is a stable merge. Measured with
`.agents/slop/notes/probe-sort-stability.bend`: tied runs of 2, 4 and 6 came back in
input order, and `[k2,k1,k2,k1,k1,k2]` came back `[k1,k1,k1,k2,k2,k2]` with each key
class in input order.

**The failure mode is a comparator that returns `False` for every DIFFERING key** --
"only ties are comparable". It typechecks, it proves, and it makes `List.sort` return
the list in REVERSE key order, because a comparator that says False in both directions
makes every merge take the second run's head. There is no diagnostic anywhere in that
chain. If a sort output looks reversed, check the comparator before you check
`List.sort`:

    def ev_cmp(same: Bool, ai: U32, ao: U32, bi: U32, bo: U32) -> Bool:
      match same:
        case True{}: U32.is_le(ao, bo)   # the tie-break
        case _: U32.is_le(ai, bi)        # NOT False{} -- this is the whole key

This was measured, not guessed: it is the bug that moved sixteen rows of
`schedule/memory.bend`'s gate at once, and the count row stayed green throughout.

`List.sort`'s comparator parameter type is `~A -> A -> Bool`, so `+` on its parameters
is REFUSED -- "expected : @_:Ev -> @_:Ev -> Bool, observed : @+a:Ev -> @+b:Ev -> Bool".
It is the one place in the `schedule/` port where `+` had to be REMOVED rather than
added.

### B. A "match on the hit, else recurse" PAIR IS MUTUAL RECURSION, and a
###    `found: Bool` ACCUMULATOR IS THE ONLY SPELLING THAT COMPILES.

    def find(hit: Bool, ls: List<&2, A>, k: A) -> Bool:      # looks fine
      match hit:
        case True{}: True{}
        case _: find.go(ls, k)                                 # ... and calls BELOW

    def find.go(ls, k):
      match ls:
        case e <> t: find(hit(e, k), t, k)                     # ... which calls UP

One of the two is always a forward reference. The shape that works is a fuel def whose
only `match` is on the fuel, with the Bool folded into an accumulator:

    def find(fuel: Nat, ls: List<&2, A>, k: A, found: Bool) -> Bool:
      match fuel:
        case 0n: found
        case 1n+p: find(p, List.tail(&2, A, ls), k, Bool.or(found, hit(...)))

`Bool.or`/`Bool.and` on an accumulator is the general answer to "find the first /
find the last" over a list, and it is what `mem_first_i` and `mem_last_i` in
`schedule/memory.bend` are.

### C. FUEL IS `len` FOR A TERMINAL FOLD AND `len+1` FOR AN INSERTING ONE. Getting
###    them the same way round is how a value lands in a list twice.

A fuel fold whose `Nil{}` arm RETURNS THE ACCUMULATOR needs `fuel = len`: `case 1n+p:`
consumes the head immediately, so `len` already visits the last element and `len+1`
visits one past the end. A fold whose `Nil{}` arm INSERTS needs `len+1`, for the same
reason. In `schedule/memory.bend` both spellings are live in the same file:

| fold | `Nil{}` arm | fuel |
| --- | --- | --- |
| `mem_touch` | returns the accumulator | `len` |
| `mem_first_i` / `mem_last_i` | returns the accumulator | `len` |
| `mem_lane_in` | returns the accumulator | `len` |
| `mem_scan` (the kernel walk) | returns the accumulator | `len` |

and the inserting case, which was the bug: a rebuild-on-every-touch fold whose last step
appends a new entry. With `len` it never reaches the insert and the value is lost; with
`len+1` the `Nil{}` arm runs on a call that already found the entry and appends a
DUPLICATE unless the insert is gated on a `found` flag threaded through the fold. Both
failure modes were measured (a buffer in `first_appearance` twice, then a buffer in it
zero times).

### D. `List.head` ANSWERS A `Maybe`, NOT A VALUE.

    def red_head_of(m: Maybe<&2, U32>) -> U32: Maybe.default(&2, U32, m, 0)
    def red_head(+xs: List<&2, U32>) -> U32: red_head_of(List.head(&2, U32, xs))

`Maybe.default`'s FIRST argument is the LIFETIME, and it must match what `List.get` /
`List.head` return (`&2`). A one-line `red_head` that inlined both runs out of lifetime
budget the moment it is read twice, which is what makes the `.of` split look arbitrary
until you hit it. `schedule/allreduce.bend` calls it `red_head` and
`schedule/memory.bend` calls it `mem_head`; the two are the same def.

### E. A TWO-SCRUTINEE `match` WITH A `Nat` COUNTDOWN NEEDS NO `0n` ARM ONLY IF
###    THE COUNTDOWN IS NOT ALSO A PATTERN BINDER. `case 1n+p _ <> t:` is REFUSED.

    #| - expected : 2 patterns (one per scrutinee)
    #| - observed : '1n+p Nil{} _'
    match fuel todo:
      case 0n _: ...
      case 1n+p Nil{} _: ...          # <- two scrutinees, one pattern

This is rule 14 in the brief with a `Nat` added, and it is worth stating because the
error says "patterns", not "scrutinees". The two-dimensional match is not available;
split the fuel check into its own def.


## Appendix, measured in `tinybendygrad/schedule/__init__.bend` (2026-10-01)

Five shapes that cost that file most of its compile cycles, all of them REFUSALS
or near-misses. A probe for each is at `.agents/slop/notes/p-sc-{1..5}.bend`.

### A. A `match` nested inside a `case h <> t:` LIST arm is REFUSED

    def go(fuel: Nat, cls: U32, xs: List<&2, U32>, acc: U32) -> List<&2, U32>:
      match fuel:
        case 0n: acc
        case 1n+p:
          match xs:
            case Nil{}   : acc
            case +x <> t :
              match cls:                      #| - message : a match on a parameter or field
                case 0: ...                   #|             (this name is a def or a consumed
    #|                                          #|              binder: give the value its own def)

Refused for a `Bool`, a `U32` and a `List` scrutinee alike. A List arm may hold a
CALL (`body(next, acc)` is fine) but never a `match`. Two escapes, and the port
uses both:

1. Put the decision in a PARAMETER and match it in the def's own body. `st.go`
   takes `cls: U32` and matches `fuel cls` two-scrutininee, so the pop and the
   decision live in one def.
2. Split the def and let exactly one of the pair recurse. `ln_go.pop` holds the
   List arm and calls `ln_go`, which is declared ABOVE it. A cycle is impossible
   because only one member recurses.

### B. A `match` nested inside a `Data`-RECORD arm: Bool refused, Nat and List fine

    def pick(is_k: Bool, s: U32, sp: Split) -> Split:      #| - message : a match on a parameter
      match sp:                                            #|             or field ...
        case Split{ks, ds}:                                #|
          match is_k:                                      #| <-- REFUSED

while `case Split{ks, ds}: match n: case 0n:` and `case Split{ks, ds}: match ys:`
both pass, and `match t: case Nil{}: ... case x <> rest: <a call>` passes. So the
refusal is about the INNER scrutinee's KIND, and the cheap answer is a
TWO-SCRUTINEE match over two `Bool` PARAMETERS, which needs no nesting at all:

    def sp_put(ker: Bool, aft: Bool) -> U32:
      match ker aft:
        case True{}  _       : 0
        case False{} True{}  : 1
        case False{} False{} : 2

### C. A self-call may not pass a COMPUTED argument before the SHRINKING one

    ka_go(Bool.or(found, U32.is_eq(j, key)), t, key)   #| - expected : a decreasing self-call
    ka_go(t, Bool.or(found, U32.is_eq(j, key)), key)   #| OK

"read left to right: each passed unchanged until one shrinks". So an accumulator
that ACCUMULATES has to sit after the list argument, which is why `found` is
`ka_go`'s SECOND parameter in `ka_go` / `da_go` / `wa_go`.

### D. A `Bool` match IS legal in a numeric arm, which makes the `.step` helper a MUTUAL RECURSION

    def unwrap.go(fuel: Nat, go: Bool, +ar: O.Arena, +s: U32) -> U32:
      match fuel:
        case 0n   : s
        case 1n+p :
          match go:
            case True{} : unwrap.go(p, sc_go(ar, sc_src0(ar, s)), ar, sc_src0(ar, s))
            case False{}: s

This is what `Topo.step` cannot do: `step` needs `n in cache` (a call) and a
decision, and a helper holding that decision has to call back into the fold, so
the pair is mutual and declaration order makes one member a forward reference --
reported as "an unfilled law is a dead claim: live code cannot use it", which is
the message for a MIS-ORDERED def and not for a dead stub. Making the decision a
parameter removes the cycle and the helper with it.

### E. `List.append` is `xs ++ ys`, so a REBUILD scan must cons and an ACCUMULATOR must append

    # rebuild -- the entry goes back IN FRONT of the rebuilt tail
    List.append(&2, Dep, [Dep{j, d + n}], r)      #| OK
    List.append(&2, Dep, r, [Dep{j, d + n}])      #| OK TOO, AND WRONG

Both compile, the second silently relocates the entry to the end, and `List.length`
of the rebuilt table does not move -- which is the shape of bug this port keeps
finding: three such scans here cost an afternoon (`in_degree` ended up with five
keys for three kernels and a Kahn loop that never drained). An accumulator is the
other way round, so the SAME builtin is right and wrong in adjacent arms.

## TWO REPORTS AND THREE RULES, MEASURED 2026-10-01 PORTING `schedule/rangeify.py`
## R1 and R2 FIXED 2026-10-01 -- see the FIXED sections below for the evidence and for
## FOUR more defects the two reports could not see.

### R1. FIXED: `mp_nsrc_ge` IS NOW `n <= nsrc`, AND THE FIX IS NOT THE WHOLE STORY.

    # `len(x.src) >= n` -- `allow_any_len=True`'s "at least n srcs". `U32.is_ge`, NOT
    # `U32.is_lt(n, nsrc)`: the name is the whole contract, and one arity is the entire
    # content of a rule's arity test. A `len(x.src) == n` test is `mp_nsrc_is` -- this is
    # `>=` and nothing else, so `mp_5.one`'s STRICT two-tuple is `mp_nsrc_is`, not this.
    def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:
      U32.is_ge(mp_nsrc(ar, i), n)

The report was right that the name and the body disagreed, and right that the
distance is one arity. It was WRONG that `mp_nsrc_ge(ar, i, 2)` "passes on a
three-src node" was the defect's whole reach: the fix is `U32.is_ge`, and the
second half is that **`mp_5.one` should not have been calling this at all**. Its
pattern is `UPat(INDEX, src=(UPat.var("src"), UPat(CONST)))` -- a two-TUPLE, so
`strict_length` is on and the test is `== 2`, which is `mp_nsrc_is`. With
`U32.is_ge` in place, `mp_5.one` now reads `mp_nsrc_is(ar, x, 2)`.

MEASURED, `mop-mut.py` M2 (revert `mp_nsrc_ge` to `n < nsrc`): moves TWO rows,
`const_idx2` and `idx_pick` -- both the two-src INDEXes, which a `> 2` test
rejects. M9 (relax `mp_5.one` to `>= 2`): moves NOTHING, because every stacked
element in the fixture is a two-src INDEX, so the stricter and looser tests agree
on this fixture. The arity test is load-bearing (M2 proves it) and M9 records
that the gate does not yet separate `==` from `>=` there.

### R2. FIXED: `hop_self` WAS INVERTED, AND THE GATE WAS PINNING IT. FOURTEEN ROWS
###     DEPENDED ON THAT FIXTURE-BREAKING BUG.

    # `ret is not uop` -- ops.py:1611. ... `drop` is "the answer IS self, OR the answer
    # IS none", and `True` must answer NOTHING: keeping `self` and dropping a genuinely
    # new node is the inverse of ops.py:1610 and of this comment, and `t_ret_new` is the
    # row that pins it.
    def hop_self.of(drop: Bool, +r: Hop) -> Hop:
      match drop:
        case True{}: Hop{hop_ar(r), 0}
        case False{}: r

The report was right, and its own last paragraph was the important part: "do not
read the zeros as `hop_self`". It was right for a reason stronger than it gave.
**The gate's own fixture index list was missing the arena's bottom**, so
`G.at(g, n)` was one node PAST the one every row's comment names. That is a THIRD
defect, in the gate rather than in a rule, and it is what made half the rows read
0 and masked the rest.

THE THREE FIXES, and the evidence for each, all in
`tinybendygrad/uop/movement.bend`'s mutation table (`mop-mut.py`):

| fix | mutation | rows moved |
| --- | --- | --- |
| `hop_self`'s arms | M1 | **14** |
| `mp_nsrc_ge` | M2 | 2 |
| `G.ix` gets the bottom's 0 | M11 | **17** |

M1's fourteen are `ret_new` plus every row that reads a FIRED rule's answer:
`shrink1_ns`, `shrink1_marg`, `reshape_pick`, `permute_merge`, `permute_noop`,
`stack_idx`, `const_idx2`, `const_idx3`, `const_idx5`, `rej_pair`, `idx_idx`,
`idx_pick`, `idx_shaped`. The report measured four of them (`const_idx2` 0 -> 40,
`const_idx3` 0 -> 3, `rej_pair` 0 -> 40, `ret_new` 1 -> 0) and read the other ten as
"0 either way". They read 0 either way **because the rows were addressing the wrong
node**: the values 40, 3 and 40 it recorded were the answers for IX3 and IX5, not
for the IX2 and IX3 the rows name. `schedule/rangeify.bend`'s M1 measured its LOCAL
`rf_self` and was right to; it now has a corrected reason to keep not calling
`M.hop_self`, and `M.hop_first`/`M.hop_next` are still correct and still reused.

`ret_new` is the row and it now reads **0**, not 1: `Hop{empty, 3}` against `self 2`
is `ret is not None and ret is not uop`, so the answer SURVIVES. The gate was
asserting "a rule that built a new node was dropped".

**THE PAIRS ARE NOT INDEPENDENT, and the new table says so.** M14 (last-wins in
`hop_first`) moves M1's thirteen rows and NOT `ret_new`: `hop_self` and the fold
are the same defect seen from two sides, both "the answer survives when it should
not", and neither mutation substitutes for the other. And M6 -- `mp_ident.at`
reading an arg ELEMENT as an arena index, which killed `mp_4` entirely -- moves
one row, `permute_noop`, which M1 also moves. A 26-row gate whose rows are
overlapping in this way is weaker than "26 green" suggests, and the table is where
that is visible.

The notes' standing rules held up and are worth repeating at the fix:
**a row that cannot fail is a restatement, and a gate that agrees with a bug is
worse than no gate.** `t_ret_new` agreed with the inversion.

## FOUR MORE DEFECTS IN `movement.bend`, FOUND WHILE FIXING R1 AND R2
### 2026-10-01. NONE OF THEM IS VISIBLE FROM `movement.py`; ALL FOUR ARE PORT ERRORS.

`movement.py` is correct in all four places. These are transliteration mistakes, and
three of the four typechecked and printed plausible output.

| where | the port did | CPython does | mutation |
| --- | --- | --- | --- |
| `mp_index.pick` | answered `new_srcs[0].val`, the VALUE | `self.src[val]`, a NODE INDEX (ops.py:223) | M3, 1 row |
| `mp_replace` | read the arg off `self` | `replace(arg=...)` REPLACES it (ops.py:252) | M4, 1 row |
| `mp_3` | composed the permutation from `x2`'s SRCS | from `x2.ARG` -- a list of INTS | M5, 1 row |
| `mp_ident.at` | read an arg ELEMENT as an ARENA INDEX | compares `x.arg[k] == k`, two INTS | M6, 1 row |

**AND THE ONE THAT IS NOT A PORT ERROR AT ALL: `marg.go` REVERSED THE MARGIN.**
`List.append(&2, A, r, [x])` puts `x` at the END of `r`, so a fold that appends on
the way UP builds its list backwards. MEASURED, reproducer
`.agents/slop/notes/probe-append.bend` (prints `1` for the head of a `[1,2,3]` built
by accumulating-append, so it appends). `marg.go` was accumulating on the way up;
`marg_zip.go` and `as_shape.vals.go` were already right. Only `shrink2_marg` moved
(M7, 1 row), because a ONE-element margin is order-blind -- and every single-margin
row in the gate stayed correct while the two-element one did not.

**FIVE OF THESE SIX ARE THE SAME SHAPE, and the shape is the lesson.** Four of them
read a PYTHON INT as a BEND ARENA INDEX, or answered a VALUE where CPython answers an
INDEX. `x.arg` is a tuple of ints; `x.src` is a tuple of UOps; `new_srcs[0].val` is
an int; `self.src[val]` is a UOp. The port has one `U32` for all of them, and Bend
cannot tell which is which, so the type checker will not catch the confusion. The
gate is the only thing that can, which is the argument for a mutation table over a
check-and-run: **M3, M4, M5 and M6 are four independent single-row mutations, and
four rows that each move exactly one is a far stronger statement than 26 green.**

### AND THE RULE THE FIXTURE GOT WRONG, WHICH IS NOT ANY OF THE ABOVE

`G.ix` was missing the arena's bottom, so `G.at(g, n)` was one node past the one every
row's comment named. Seventeen rows depend on that (M11) and it is the single biggest
mutation in the table. A fixture that renumbers its own nodes is a fixture whose rows
cannot be checked by reading them: the row says `shrink1` and the code rewrites S3.
The oracle (`.agents/slop/notes/mop-truth3.py`) prints the whole index map, and it is
the reason a diff of the two gates is now the acceptance test rather than a reading
exercise.

### WHAT A CONSUMER SHOULD DO ABOUT IT

`schedule/rangeify.bend` still implements `ret is not uop` locally as `rf_self`. That
was the right call and it is now better justified: `M.hop_self` was wrong, and M14
(last-wins in `M.hop_first`, which `rangeify` DOES call) moved thirteen rows when it
was mutated. If `rangeify` wants the local `rf_self` replaced by the now-correct
`M.hop_self`, M1 and M14 are the two measurements to re-run. `M.hop_first` and
`M.hop_next` are unchanged and still correct.

### R3. `Bool` HAS NO `U32.show`, SO EVERY GATE ROW PAYS A `Bool -> U32` STEP.

    def b2u(b: Bool) -> U32:
      match b:
        case True{} : 1
        case False{}: 0

Not a deep rule, but it is a per-row cost and it has a SHAPE: a row that
computes a `Bool` cannot print it, so the conversion has to be threaded through
81 call sites or hoisted into one def. Hoist it, and put it ABOVE the fixture
rather than inside `main` -- `Bool.match` is the only branch, and there is no
`U32.from_bool`.

### R4. `List.sort`'s COMPARATOR IS `A -> A -> Bool` WITH ONE BINDER, SO A KEY THAT
###     LIVES IN THE ARENA HAS TO TRAVEL IN A `Data` RECORD.

    def List.sort(~A: Data, ~le: A -> A -> Bool, xs: List<&2, A>) -> List<&2, A>

The comparator takes TWO elements but binds ONE, and it answers `Bool`, not a
`Cmp` (`Cmp` is for `Order`/`Min`/`Max`). So "sort these indices by the key in
arena slot `k`" is not expressible: the closure cannot close over `ar`, and it
cannot take `ar` as a second argument because there is no second argument. The
port packs the pair first.

    type Rk is Data:
      Rk{k: U32, i: U32}

and sorts `List<&2, Rk>` with `le` reading `Rk.k`. The list then has to be
unpacked. That is the same "a `list`-tail fold that must hand something back
carries it in a record" shape as the memory.py note, one level down: there the
record carries an accumulator, here it carries a sort key.

### R5. A `Data` RECORD WITH A FIELD NAMED AFTER A KEYWORD IS A SYNTAX ERROR, AND
###     `where` IS A KEYWORD.

Not worth a rule of its own except as a name-collision list while porting:
`where`, `match`, `case`, `type`, `def`, `let`, `if`, `else`, `do`, `fold`. The
port needed a `where`-shaped local and had to pick another name. Hit it once,
recorded so the next port does not spend the compile cycle on it.

## SIX MORE RULES, MEASURED 2026-10-01 WHILE PORTING `mixin/gradient.py`

### 1. A `Data` RECORD PATTERN IS CAPPED AT 28 FIELDS, AND THE ERROR IS A BARELY
###     PARSEABLE "a `Fix` pattern with 28 fields"

`spec.bend`'s largest record is `Shrunk`; a fixture record of 29 `U32` fields is
refused with `- message : a Fix pattern with 28 fields` and NO position hint. The
workaround is to REUSE an unused field rather than add one: a gate fixture rarely
needs every slot it declares, so renaming an unused slot to the new meaning costs
nothing and keeps the record inside the cap.

### 2. A `match` ON A `Nat` COUNTDOWN AND A LIST IN ONE ARM NEEDS THE COUNTDOWN
###     FIRST, AND `p` MAY NOT BE BOUND IN TWO ARMS EVEN FOR THE EMPTY-LIST ONE

A depth-first node count over a DAG wants `match fuel todo: case 1n+p s <> t: ...`
plus a cover. The cover cannot be `case 0n _:` AND `case 1n+p Nil{}:` together,
because `p` is consumed by the arm that uses it and binding it in a second arm is
`expected : p / observed : p (consumed more than once)`. So the EMPTY-LIST case is
reached by the cover arm `case _ _:` and the countdown binds `p` exactly once:

    def size(+fuel: Nat, +ar: O.Arena, todo: List<&2, U32>, acc: U32) -> U32:
      match fuel todo:
        case 1n+p s <> t: U32.add(U32.add(1, size(p, ar, O.Arena.srcs(ar, s), 0)),
                                  size(fuel, ar, t, 0))
        case _ _: acc

This is also the ONE legal spelling of "two self-calls in one arm": the two calls
get DIFFERENT fuel (`p` into the head, `fuel` unchanged into the tail), so rule 5's
"the same fuel may not feed two self-calls" is satisfied without a helper def.

### 3. A NODE-COUNT FOLD MUST ADD ITS `+1` TO THE ACCUMULATOR, NOT TO THE HEAD

The shape above looks right and returns a count that is one LOW for a leaf, because
`case _ _: acc` also catches the `Nil{}` case and returns without counting. The
fix is `U32.add(U32.add(acc, U32.add(1, ...)), ...)` rather than
`U32.add(U32.add(1, ...), ...)`. What caught it was a CONTROL row: `size_const`
must be 2 (`CAST(CONST)`) and it printed 1. The lesson is the general one -- a
recursive counter needs a fixture whose answer is known independently, or the
off-by-one is indistinguishable from a wrong rule.

### 4. A `Data` RECORD FIELD READ TWICE THROUGH A FIELD ACCESSOR NEEDS `+`, AND
###     `+` ON THE RECORD IS NOT ENOUGH -- THE CALL IS

`F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i)` reads `fx` twice. `+fx` on the
parameter is required and NOT sufficient: the first accessor CONSUMES the value
before the second is evaluated (Bend is strict -- "an argument is evaluated before
the callee branches"). `uop/spec.bend` avoids this with `sp_ar`/`sp_tb`, two
one-read helpers. When the helpers are in another file and importing that file is
undesirable, pass the two fields as SEPARATE PARAMETERS:

    def gr_0.dt(ar: O.Arena, tb: F.Table, self: U32) -> Maybe<&2, S.Dt>:
      dt_of(F.fold.dt(ar, tb, self))

### 5. A RULE THAT GROWS THE ARENA RETURNS `(Arena, answer)` AND THE ANSWER MUST
###     BE A `Data` RECORD, NOT A `Maybe`

`pm_gradient`'s rules return `tuple[UOp|None, ...]`, `None` meaning "keep
scanning". A `Maybe` of a list cannot be a `Data` field, so the answer is two
constructors -- `GFired{gs, ar}` and `GSkip{}` -- which also lets `gs` carry the
GROWN arena. A hole in `gs` is index 0, which is not an invention: `Arena.empty`
spends index 0 on `Arena.bottom` and `UOp.is_none(u) = U32.is_zero(u)`.

### 6. THE GATE NEEDS A ROW THAT READS AN INDEX OR AN OP, NOT A LENGTH -- MEASURED
###     TWICE IN ONE FILE

Two mutations in `mixin/gradient.bend` produced the CORRECT ANSWER LENGTH while
being wrong, and both were invisible until a row read something else:

* `gs_keep` under LAST-WINS: every scan-level answer is identical because only one
  rule ever fires in the fixture. Only a row calling `gs_keep` on two `GFired`
  values moved.
* `x.eq(y)` spelled as `CMPEQ` instead of `CMPNE`-then-`CMPNE`: `max_n0` is 21
  either way, because the two spellings have the same node COUNT. Only a row
  reading `Arena.op` of the node `eq` built moved.

The generalisation of the existing "two rules agree and the gate cannot see it"
note: it is not only rules that collide, it is any check whose oracle is a COUNT
rather than a STRUCTURE. `pow_n0` is 23 in the port and 24 in Python for a third
reason and the same rule applies -- see the file's header, where the disagreement
is recorded rather than fitted away.

## FOUR MORE RULES, MEASURED 2026-10-01 PORTING `tinygrad/tensor.py`

### 1. `case 1n+p:` IS A PREFIX MATCH TOO, AND IT IS WORSE THAN `case 0n:`
The note above says a numeric `case 0n:` is a first-match prefix and so is not
exhaustive. `1n+p` is the SAME trap and more dangerous, because the arm reads like a
test for "one or more" and silently claims every larger count, leaving the arm after it
DEAD CODE. `shape_to_shape_arg`'s three arms were written
`case 0n: ... case 1n+p: <the one-element case> case _: <the many case>` and the
one-element case fired for 2, 3, 4, ... — so a shape arg of `[2, 2]` (two CONSTs, one
interned index) built a bare CONST where the oracle says a two-src STACK. There is no
diagnostic; the `case _:` is simply unreachable. The fix is the idiom every other
dispatch uses: compute a `Bool` with `Nat.is_eq(n, 1n)` and pass it in.

### 2. A `.go`/`.step` PAIR IS MUTUAL RECURSION, SO THE SELF-CALL MUST BE AN ARGUMENT
There is no `|>` and a def body is one expression, so a walk that needs both a two-way
choice and a descent cannot be written as `match cond: case A: ... case B: self(tail)`.
The working shape is `Bool.pick(TYPE, cond, <the A value>, <the self-call>)`: both
branches are evaluated (Bend is strict), so the self-call runs whether or not the branch
is taken, and the accumulator is still correct because the discarded branch's value is
thrown away. The LIST must be the first parameter so the tail is the self-call's first
argument. Two instances in `tensor.bend`: `tn_rop.ins` and `tn_rop.ne1`.

### 3. A `match` ON A LIST SPENDS IT, AND `[head] ++ tail-of-tail` LOSES AN ELEMENT
`case s <> t:` destructures the scrutinee, so the arm cannot re-wrap the list. A SECOND
destructuring `case u <> v:` and then `[s] ++ v` drops `u` SILENTLY. It is invisible on a
one-element list and it is visible on a list of two equal interned indices, which is
exactly what a shape arg like `[2, 2]` is. The fix is to compute the LENGTH before the
match and hand the whole list to the constructor, which is also what makes the duplicate
case correct: `UOp(Ops.STACK, src=(c, c))` is a two-src node and hash-consing keys on the
src tuple, so it is a different node from `STACK(c)`.

### 4. AN ARENA IS THE ONE A BUILD RETURNED, NOT THE ONE THAT WENT IN
Every arena-taking def that BUILDS must return the `Found` the build gave it. Passing the
incoming `Arena` forward typechecks, compiles, and yields an index that points into the
arena as it was BEFORE the node was interned. The symptoms are all plausible numbers and
none of them raises: a node that reads as the `ABad` bottom (`NOOP/0`), an EMPTY
toposort, a node whose src count is wrong, and a `replace`-style shape comparison that
answers "not equal" for two equal shapes. Three separate graph-building defs and three
gate fixtures had it, and the gate caught them only because every row is derived from
CPython. The tell is a row that is `0`, or a COUNT that is smaller than it should be,
with no error anywhere.

## F. TWO AGENTS PORTED `schedule/multi.py` CONCURRENTLY. The oracles AGREE;
##    the file is contested and only one agent may write it.

Measured 2026-10-01 while porting `schedule/multi.py`. The brief says "Create
ONLY the one .bend file named in your unit", and `multi.bend` was named in mine
AND was being written by someone else at the same time: a 232-line file I wrote
was overwritten within 60 seconds, and the replacement grew 288 -> 398 -> 461
lines while I watched it across four 30-second samples. The two files use
incompatible prefixes for the same concepts (`Cfg`/`Sh`/`Nd` vs `Cfg`/`MPat`,
`mu_*` vs `mt_*`), so merging them is not mechanical -- every one of ~60 call
sites would have to be renamed, and the `MPat`/`Nd` split is a real design
difference (pattern columns vs. per-source node state), not a spelling one.

THE ORACLE CROSS-CHECK IS WHAT IS WORTH KEEPING. Both agents independently wrote
a CPython oracle for the same file:

    .agents/slop/notes/sched-multi-truth.py   (mine, 380 lines, 471 rows)
    .agents/slop/multi-rows.py                (theirs, 213 rows)

and all 25 `early_reject` sets, all 25 op sets, `own_n`/`ra_n`/`ea_n`, the
28-op ALU set and the 6-op Movement set AGREE, computed from
`M.multi_pm.patterns`, `M.replace_allreduce.patterns` and
`M._early_allreduce.patterns` respectively. The ONE apparent disagreement,
`pm_len=25` vs `own_n=19`, is a NAMING difference and not a value difference:
`own_n` counts `multi_py:282-310`'s own list and `all_n` counts
`multi_py:311`'s `PatternMatcher([...19...]) + replace_allreduce`, which is 25.
Both numbers are right and both are rows.

THE GENERAL RULE, and it is the one that cost the work: TWO INDEPENDENT
TRANSCRIPTIONS OF THE SAME PYTHON TABLE THAT AGREE IS STRONG EVIDENCE BOTH ARE
RIGHT, AND IS CHEAPER THAN EITHER MUTATION TABLE. A transcription error -- a
misread `early_reject`, a wrong `required_len`, a GroupOp set with one member
missing -- shows up as a DISAGREEMENT. Neither agent's own gate can find it,
because a gate compares against the code in its own file. Cross-checking two
oracles that were written from the same Python finds the class of bug a
self-consistent gate is blind to by construction.

A cheaper and more general form: when a port's subject is DATA rather than
control flow -- a rule table, an op table, a dispatch order -- write the oracle
FIRST and print a hash or a sorted dump of the whole structure, so two runs can
be diffed as files instead of compared row by row. `diff <(a.py) <(b.py)` on the
dumps answers in one command what 25 row-by-row comparisons answer in a script.

## SIX MORE RULES, MEASURED 2026-10-01 PORTING `nn/optim.py`

Every one of these cost a compile cycle or a wrong gate row, and every one is a
consequence of an earlier rule rather than a new law. The file is
`tinybendygrad/nn/optim.bend` and its header records each at the def.

1. **A `Data` record parameter needs `+` for two reads even when the reads are in ONE
   argument position.** `fold.bend`'s `ones.go(+n: Nat, acc)` is the precedent; the
   nn form is a `Tensor` read for its arena and again for its index
   (`op_ar(t), T.Tensor.u(t)`). `+` on a `List` parameter also works, which the `List` is
   a Type-kinded thing should not predict:
   `def op_filter.go(want: Bool, +xs: List<&2, T.Tensor>)` checks.
2. **`Bool.pick` is STRICT, so a two-arm walk over a `List` needs the list `+`.**
   `Bool.pick(List<&2, U32>, want, op_filter.tgo(xs, Nil{}), op_filter.fgo(xs, Nil{}))`
   with a plain `xs` is "consumed more than once". Measured, and it is the difference
   between a two-arm filter and an uncompilable one.
3. **A `match` on TWO scrutinees is `case P Q:`, and a `Data` variant whose pattern has
   ONE field must NAME it**: `case False{} S.Dn{tags}:` — `S.Dn{}` is rejected with
   "a ../LAWS/spec.Dn pattern with 1 field".
4. **A nested `match` whose scrutinees are PATTERN BINDERS is refused** ("a match on a
   parameter or field (this name is a def or a consumed binder)"). `op_nop` matches
   `Optim{...}` and then needs to branch on `fused` and `device`, both binders. The
   shape that works is a `.arm` def taking them as PARAMETERS, which is the same
   Bool-parameter rule as everywhere else and costs one extra def.
5. **`Nat` binders in `case 1n+p:` cannot be read twice, and the fix is `+n: Nat` on
   the SCRUTINEE, not on the binder.** `def axes.go(+n: Nat, acc)` with
   `case 1n+p: axes.go(p, ...)` checks; without the `+` the error is "expected: p /
   observed: p (consumed more than once)" even though `p` appears once in the source.
6. **THE ARENA RULE, AND IT IS THE ONE THAT MATTERS.** `O.Arena.empty()` inside a
   helper that builds a node produces a node the rest of the graph cannot see, and it
   typechecks and prints a plausible number. Measured five distinct failures in one
   file: a bare-`U32` helper (every graph row printed `1 NOOP/0`), a stale `ar` on
   `op_sub` (`op_apply` printed `0`), a fresh arena in a `Bool.pick` re-wrap
   (`op_nesterov` printed `1 BUFFER/0`), the unary helpers `sqrt`/`reciprocal`/`cmplt`/
   `neg`, and `op_mulf` interning its CONST into a NEWER arena than the MUL that
   consumes it. **The rule is: a node belongs in the arena as it stood after the last
   node built before it, so every helper takes the arena where it is not already
   carried and takes a `Tensor` where it is.** `Tensor` is exactly the `Arena & U32`
   pair, which is what `O.Found` is for and why `tn_alu.of` returns a `Tensor` rather
   than a `U32`.
7. **A gate row that builds a graph twice per row silently gates the wrong graph.**
   `sig(nm, st_ar(s), op_trust(st_ar(s), ...))` calls `g_step()` twice, so the fixtures
   are in one arena and the graph in another, and every row printed `1 NOOP/0`. The
   `n=` COUNT is what makes it visible: a one-node signature is never a right answer
   here. Read the arena off the built `Tensor`, not off the fixture.

## 2026-10-01, mixin/elementwise.bend -- rule 6 has a SECOND HALF, and it is the
## one that bites

Rule 6 above ("a node belongs in the arena as it stood after the last node built
before it") is about a node being built in the WRONG arena. There is a second
failure that rule 6's fix does not cover, and it is worse because `next` looks right.

**THE FAILURE: two builds from the same base produce SIBLING arenas, and "take the
longer" does not find a store containing both.** Rule 6's remedy for a two-operand
build is to pick the longer of `x`'s and `y`'s arenas before building. That is sound
ONLY when one is an append-only extension of the other. It is NOT when both operands
have already minted into their own copies: then both arenas are `base ++ [one node]`,
the same length, and index `k` holds a DIFFERENT node in each. Taking the longer picks
one, and the other operand's freshly minted node is simply absent -- it reads back as
whatever the winner put at index `k`.

The symptom is silent and is why this took a while: the arity is right, the count is
plausible, and the graph is wrong. `sub`'s int arm printed `4 CONST/0 BUFFER/0 MUL/2
ADD/2` where CPython prints `6 BUFFER/0 CAST/1 BUFFER/0 CONST/0 MUL/2 ADD/2` -- a
missing BUFFER and a missing CAST, with both operands still 2-src.

**THE FIX, and it is a discipline rather than a helper.** Three rules together:

1. **A def that may mint takes the arena as an ARGUMENT and builds there.** Not
   `Tensor.ar(t)` -- an argument. `Tensor.ar(t)` is only correct while nothing has
   been minted since `t` was made, which is exactly the condition that has stopped
   holding by the time a second operand is used.
2. **A def that mints NOTHING still rebase onto the arena it was handed** on every
   arm, including the two no-op arms. An arm that returns `t` unchanged hands back a
   tensor carrying the arena as it was BEFORE its sibling minted, and the next build
   in that stale store takes an index a real node already holds. This is the rule that
   fixed `ew_add_f`, and it costs one `T.tn_new` per arm.
3. **The promotions are SEQUENTIAL and the second takes the arena the first grew.**
   Not a fold threaded down, and not two parallel mints.

**COROLLARY: a helper that builds over two operands which are NOT the pair being
combined needs the rebase written out.** `div`'s float arm is
`cast_if_int(a) * reciprocal(b)`: `cast` grows the arena, and `b` must be rebased
onto the grown store before `reciprocal` builds in it, or the `MUL` names the `cast`.
`ew_alu2`'s `ew_join` only covers the pair it is combining.

**COROLLARY 2: `arena.next` is NOT a containment test.** Two sibling arenas of equal
length are indistinguishable by it, so any "pick the bigger store" rule is reading a
number that does not mean what it looks like. The store is only ever an extension
because the code made it one.

**AND THE FOLD VERSION OF THE SAME TRAP.** Rule: never accept a `+fx: F.Folded` as a
parameter to a def that builds. A `F.Folded` is a fold of ONE arena and goes stale
the moment the callee mints, and the failure is the *silent* one -- `wk_dt` of an
index past the end answers `void`, `void` is not in `dtypes.weaks`, so every operand
takes the CAST arm and you get right ops with right arities and wrong dtypes. Thread
the arena (or take the fold from the tensor AT THE POINT OF USE, `ew_fx`) and the
staleness becomes unrepresentable. Measured here on `ew_ge`/`ew_eq`, which took a fold
from the caller, then built a CMPLT, then cast the result against the PRE-BUILD fold.

## EIGHT MORE RULES, MEASURED 2026-10-01 PORTING `codegen/transcendental.py`

Every one of these cost a full gate round-trip. The gate is
`.agents/slop/tx-arena.txt` — 891 STRING rows, and the interpreted lane, the
native lane, and the Python oracle have to be byte-identical, so "it type-checks"
is worth nothing here on its own.

### 1. A def that returns a BARE INDEX DISCARDS ITS ARENA

The rule at line 558 ("the rule returns the ARENA, not a pair") has a mirror
image, and this port is the case where BOTH are read. `ops.bend`'s `Arena` is
`Data` holding a `List<&2, Node>`, and a build appends to it, so the arena *is*
the side effect and the index is not. A def that builds nodes and returns only
`U32` therefore hands the caller nothing: Bend eliminates the call, and every
node it built goes with it.

    def ph_i(+ar: O.Arena, +e: U32) -> O.Found:     # right: the pair comes back
      +a = tx_cast(ar, e, S.uint64())
      +b = tx_ci(O.Found.ar(a), 32)
      tx_alu2(O.Found.ar(b), O.OpsFLOORDIV{}, O.Found.i(a), O.Found.i(b))

    def ph_i(+ar: O.Arena, +e: U32) -> U32:         # wrong: the CAST is dropped
      +a = tx_cast(ar, e, S.uint64())               # ... unless the caller reads .ar
      ...

**The tell is a count row that is silently short.** The first version of
`payne_hanek_reduction` passed the post-`frexp` arena to all four of
`ph_ia`/`ph_i`/`ph_ec`/`ph_off`; `ph_i`'s CAST was eliminated because only its
index was read, and `n_ph` came out **60 against 116** with three rows reading
slots that did not exist. There is no error, no proof failure, and `--check-only`
still says `ALL PROOFS CHECK`.

**Corollary, the one that makes it expensive: two bindings that both read
`ar(n)` for the same `n` produce SIBLING arenas.** `+a = f(n)` and `+b = g(n)`
are each `base ++ [one node]`, the same length, index `k` holding a different node
in each — which is the tensor case already written up at the top of this file, one
level down. And `f(ar, ..) .. f(ar, ..)` written twice lets the compiler pick
either order, so the two nodes' indices are not even determined by the source.

So the discipline is one sentence: **every step threads
`O.Found.ar(<previous binding>)`, and a def that may mint returns the pair.**

### 2. AN ELISION MUST HAND BACK THE ARENA IT WAS GIVEN

`mixin/dtype.py`'s `cast` is a no-op when the dtype already matches, and a port
that models the no-op as "return the index" throws the arena away — the caller's
next node then lands in a store that does not contain this one. The elision has
to be the *same pair, with no node added*:

    def tx_cast_same.go(+ar: O.Arena, +x: U32, +dt: S.Dt, same: Bool) -> O.Found:
      match same:
        case True{}: O.Found{ar, x}
        case False{}: tx_cast(ar, x, dt)

This is the tensor rule at the end of this file ("a def that mints nothing still
rebases onto the arena it was handed, on every arm, including the no-op arms")
specialised to a `(store, index)` pair.

### 3. A DTYPE PROJECTION IS NOT IDEMPOTENT

`rintk`'s output dtype is the int of the same name
(`{float64: int64, float32: int32, float16: int16}[d.dtype]`). Once that is a
def, `tx_int_dt(tx_int_dt(x))` is **not** `tx_int_dt(x)`: `tx_int_dt` matches on
`pri` 12 / 14 / else, and `int32` is `pri` 5, so the second application answers
`int64`.

The port had `tx_rintk` apply it internally (mirroring line 24, which reads
`d.dtype`) *and* a caller pass an already-converted dtype. **Every count row was
correct and three rows were wrong**: `a_cw 23`, `a_xsinf 39`, `a_xsin 143` printed
`CAST,long,22` where the oracle says `CAST,int,22`. Nothing else moved — same
nodes, same arity, same count, a different dtype on three CASTs.

**Rule: a derived-dtype helper goes at exactly ONE place, and the def that mirrors
the Python helper that reads `.dtype` is that place.** Every other caller passes
the dtype of the *operand* the Python code would have had in hand.

### 4. `F32.to_u32` IS A TRUNCATION IN THE NATIVE LANE AND UNFOLDED IN THE INTERPRETER

`F32.to_u32` is a law, and the two lanes do not agree about it:

    def main() -> U32: U32.add(F32.to_u32(2.9), U32.mul(F32.to_u32(F32.neg(0.0)), 1000))

    ./bin/bend  ->  U32.add(F32.to_u32(2.9), U32.mul(F32.to_u32(F32.neg(0.0)), 1000))
    native      ->  2

The interpreter has no body and prints the residual term; the backend
constant-folds it to a truncation. So it is not a lane-divergence bug you can
diff your way to, and it is not a bit pattern either. **The bit pattern is the
datatype field, and it is a constructor so `--check-only` covers it:**

    def tx_fbits(f: F32) -> U32:
      match f:
        case F32{data}: U32{data}

Verified against `struct.pack('<f', .)` on the gate's own rows:
`0.3183098861837907` -> `1050868099`, `0.3183098861837907 / 2.0**24` ->
`849541507`, `2.0**24` -> `1266679808`, `-0.5` -> `3204448256`, and the rest all
agree in both lanes. `F32.bits` (line 131 of these notes) also agrees; it is a law
too, so prefer the destructor on general grounds, and **`to_u32` is the one to
never reach for** — the name reads like a bitcast and the value is a truncation.

### 5. A SELF-CALL NEEDS `Nat` FUEL FIRST, AND THE FUEL IS NOT THE COUNTER

Python's `_take` recurses on a COMPILE-TIME bound (`count+offset <
len(two_over_pi_f) - 1`), so Bend needs a fuel parameter, and the fuel and the
Python `count` are **different numbers**: for `offset = k` there are `6 - k` levels
and `count` runs `0..5-k`.

    def ph_take(+k: Nat, +c: U32, +ar: O.Arena, +i: U32, +an: O.Found,
                 +off: U32) -> O.Found:
      match k:
        case 0n: O.Found{ar, O.Found.i(an)}
        case 1n+p:
          +cc = tx_ci(ar, c)
          +ne = tx_alu2(O.Found.ar(cc), O.OpsCMPNE{}, i, O.Found.i(cc))
          +in = ph_take(p, U32.add(c, 1), O.Found.ar(ne), i, an, off)
          +t = tx_ci64(O.Found.ar(in), H.i64_of_hi_lo(0, two_over_pi(U32.add(c, off))))
          tx_alu3(O.Found.ar(t), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(in), O.Found.i(t))

`Nat` first, so the recursive binder is `p`. Reading one Nat as both makes the
CMPNE compare against 6 instead of 0, misses `i.ne(0)` entirely, and shifts every
node by one. **And the base case returns the PAIR** (rule 1) — `O.Found{ar, O.Found.i(an)}`,
not the index.

**The receiver-first order inside the arm is load-bearing too.** Python evaluates
`i.ne(count).where(_take(...), an.const_like(...))` receiver-first, so the six
CMPNEs come OUTERMOST FIRST (`a_ph36`..`a_ph43`) and the six WHEREs INNERMOST
FIRST (`a_ph45`..`a_ph54`). The `+` binder is also what keeps the recursive call
alive at all; without it the self-call is unused and eliminated.

### 6. TWO dtype GUARDS ON THE SAME VALUE ARE NOT NEGATIONS OF EACH OTHER

`cody_waite_reduction` has `d.dtype == dtypes.float64` (line 123/146) and
`x.dtype == dtypes.float16` (line 133) — two independent facts about one dtype, so
two Bool parameters. Collapsing them ("not float64" -> "float32") sends float16
down the float32 chain, and since a float16 that builds the float32 chain is a
*wrong tree* rather than a missing one, nothing in the gate would have said so.
Same shape as `decomp.bend`'s `cls`/`cplx` split. Also note `Bool.not(f16)` is
only sound because the *third* dtype case (`bfloat16`) cannot reach
`cody_waite_reduction` — `TRANSCENDENTAL_DTYPES` is `half, float, double`.

### 7. A `match` MAY NOT SCRUTINISE A CALL, SO A dtype TEST IS A PARAMETER

Already recorded (lines 562, 793, 905). One more data point: `cw_quadrant` needs
`d.dtype == float64` for BOTH the `rintk(d * m_1_pi - qdh)` arm and the float32
arm, and the caller already has the `S.Dt`; so the flag is `d64: Bool` with **no
`+`** and the caller passes `tx_d64(dt)`. The `+` would be a lie — the call
carries no arena.

The `+` is also how you spot the sibling mistake: a def parameter that is
`O.Arena`-returning is `+`; a plain predicate is not.

### 8. WRITE FLOAT COEFFICIENTS AS FULL DECIMALS, AND NEGATIVES AS `F32.neg`

Bend's float parser is not reliable at every exponent: `6.1e-5` and `1e-4` do not
parse at all, while `0.000061` does. A coefficient table is a place where one
dropped digit is silent — `String.concat` shows you the number it got, not the
number you meant — so **full decimals everywhere**, and `F32.neg(0.5)` rather
than a leading `-`. A dropped digit in a truncated float also cannot be caught by
a count row, which is the argument for string-diffing the CONST rows.

## THE SHAPE OF A GATE THAT ACTUALLY BITES

Worth stating once, because four separate bugs got past the type checker here and
this is the reason they did not get past the gate:

- **STRING-DIFF THE CONSTS AND THE DTYPES, NOT JUST THE COUNTS.** Every count row
  stayed correct through a wrong CAST dtype (rule 3), a dropped arena (rule 1) and
  an off-by-one fuel (rule 5). A `n_<tag>` row is necessary and nowhere near
  sufficient.
- **RUN BOTH LANES.** A count row can be right in the interpreter and wrong in the
  binary, which is the whole content of rule 4.
- **MUTATE THE FILE AND MEASURE WHICH ROWS MOVE.** Thirteen mutations, all of which
  still pass `--check-only`; four of them move exactly ONE row
  (`a_xexp2#32`, `a_xpow#31`, `a_ph#99`, `sw7`). A gate with no single-row claims
  cannot see a single-row mistake, and the `sw30`/`sw7` pair exists only because
  `xsin`'s `switch_over` is a parameter — the shape does not depend on the value,
  so both rows are read at the same slot and only the value row can tell.

## `Maybe<&2, S.Dt>` in a def signature is position-sensitive (measured on 2.0.34)

Found by `codegen/kernel.bend`, and it cost four bisection cycles because the
reported location is the WRONG line -- bend blames the signature while the file
that differs is a blank line earlier or later.

Repro, all three files under `tinybendygrad/codegen/`, same imports:

    A: head -179 kernel.bend  + "\n\ndef kn_dt(tb: F.Table, ar: O.Arena, i: U32) -> Maybe<&2, S.Dt>: ..."
       -> ALL PROOFS CHECK
    B: head -179 kernel.bend  + "\ndef kn_dt(...): ..."     (one blank)   -> ALL PROOFS CHECK
    C: head -182 kernel.bend                                  (same bytes) -> SOME PROOFS FAIL
                                            - expected : a term
                                            - observed : ']'

B and C are byte-identical in the region bend points at -- verified with a byte
diff -- and neither the def name nor the blank-line count changes the outcome, so
**do not spend time bisecting blank lines against this one.** The workaround is
the only thing worth keeping: put the `Maybe` through a def whose return type is
already known to parse (`Bool`), or go through `fold.bend`'s `F.dt_is` /
`F.Folded` instead of carrying an `S.Dt` value.

`Maybe<&2, List<&2, O.Sint>>` in a signature is fine, and the same file with the
def named `bb` instead of `kn_dt` is fine, so the trigger is the annotation in
that POSITION, not the name and not the blank lines.

## FIVE MORE RULES, MEASURED 2026-10-02 WRITING `renderer/__init__.bend` and
## `renderer/cstyle.bend`

### 1. A `do IO<Unit>:` BODY MUST END WITH A BARE TERM, NOT A `<-` BINDING
    def main() -> IO(Unit):
      do IO<Unit>:
        _ : Unit <- p2(7)
        _ : Unit <- p3(8)          # "expected : a term, observed : end of input"
and a def whose body is a `do` block must be the LAST def in the file -- a `def`
after it is "expected : a term, the keyword 'def' cannot head one". Both cost two
compile cycles to find. Every other file in the tree already puts `main` last.

### 2. A SELF-CALL MUST BE LEXICALLY INSIDE THE DEF THAT OWNS THE FUEL MATCH
A `def` may only call defs declared ABOVE it, so a NON-recursive rebuild helper
must sit above the recursion -- that is fine, because it holds no self-call. But
`hoist.py` cannot fix a helper that DOES hold one: with
`ws -> ws.pick.of -> ws_deep -> ws` the cycle is unresolvable by reordering, and
the tool reports "no progress on ws at line 51" after eight rounds. The fix is to
move the guard Bool into a PARAMETER of the recursive def, so the inner `match`
scrutinises a parameter (legal) and the self-call is one expression in one arm.

### 3. A RECURSIVE ARENA REBUILD MUST BE BUILT ON THE INNER NODE'S ARENA
`O.Found.ar(inner)`, not the arena passed in. An arena only GROWS, so the passed
arena is a PREFIX and the inner node's index is not in it: the outer node's src0
then points past the end and `Arena.arg` answers the bottom's `ABad`. This is
INVISIBLE -- it typechecks, it runs, and it prints a plausible wrong string.
MEASURED: `INDEX float src0=?` where CPython prints `float`. The outer
op/arg/tag are still read from the OLD arena, which is correct.

### 4. `Maybe.map(&2, T, ...)` NEEDS A `Data` RESULT, AND `.bind` READS DIFFERENTLY
`Maybe.map(&1, S.Dt, m, d => d)` is "expected : Type, observed : Maybe<&2, S.Dt>"
-- the third argument is a QUANTIFIER over the RESULT and `S.Dt` is not the
`Data` being mapped. The tree's own convention is better and shorter anyway: skip
`Maybe` combinators entirely and `match` the fold read in a `.of` def.

### 5. `O.ParamArg`'s FIELD ORDER IS NOT THE PROSE ORDER
ops.bend:697-711 declares `... volatile, image, buffer, bind_on_realize, val`,
while the header lists `val` before `addrspace`. A record literal built from the
prose order compiles until it hits `bind_on_realize` -- "expected : Maybe<&2, U32>
observed : Bool" -- because the eighth field is `addrspace: S.Addr` and the ninth
is `device: Maybe<&2, S.Dev>`. Read the declaration, not the comment. This is
rule 3 of `bend2-constraints` (a record pattern must name every field) biting
from the other side: a record LITERAL must too, and the compiler's error names
the position, not the mistake.

### 6. A `Data` UNION'S CONSTRUCTORS ARE CONSTRUCTORS, NOT NAMES -- AND `O.OpsCMPLT{}` IS ONE
A pattern binder `case MnBn{c}:` binds `c` AFFINE, and a `case MnConv{cin, cout, k}:` arm
whose body reads `k` twice needs `case MnConv{cin, cout, +k}:`, which the compiler
refuses. The fix is not `+` on the binder: a `Data` record parameter still needs a `+`
for two reads, and a pattern binder CANNOT carry one. The fix is a `.go` DEF whose
parameters can -- `mn_conv_w.go(+cin, +cout, +k)` called from the arm -- which is the same
answer `mo_reshape.pick` and `tn_rop.ne1` already give. MEASURED: four arms in
`examples/beautiful_mnist.bend` (the conv weight shape, the BatchNorm row, the padding
row, `mn_shape_str`) each cost one compile cycle before becoming a `.go` def.

### 7. A RECURSION WITH A BOUND AND NO COUNTDOWN STOPS ON THE EMPTY TAIL
`x.sequential(ll[:-1])` -- "every layer but the last" -- does not want a `Nat` countdown
when the tail IS the test: `case l <> Nil{}: acc` and `case l <> +t: recurse(t, ...)`.
MEASURED: the countdown spelling (`mn_head13.go(Nat.pred(n), ...)`) does not compile at
all, because `n` is then read in the arm's head AND unused in its tail and the compiler
reports "consumed more than once". The tail test is shorter, has no unused parameter, and
is the same condition Python writes.

### 8. `dtype.bend`'s FOURTEEN SEAMS MAKE EVERY IMPORTER RED, AND `@unsafe` IS NOT THE FIX
MEASURED (2026-10-02): `bend tinybendygrad/dtype.bend --check-only` prints
```
SOME PROOFS FAIL
Error: 14 defs rely on unsafe or foreign code:
- Dt.bf16  Dt.fp16  Dt.fp8_from  Dt.fp8_to
- Dt.i64_trunc  Dt.i64_floor_div  Dt.i64_floor_mod  Dt.i64_cdiv  Dt.i64_cmod  Dt.i64_ceildiv
- float_to_bf16  float_to_fp16  float_to_fp8  fp8_to_float
```
The cause is not a defect in the seams. `bend base --types` for the pinned 2.0.34
has NO `F16`, `I64`, `F64` or `U64` -- only `U32`/`F32` (`Word(32n)`), `Nat`,
`Bool` -- so a pure-Bend fp16 round-trip or a floored 64-bit div/mod is not
writable, and the C seam is the correct engineering, not a shortcut.

Two dead ends, both measured, so nobody walks them again:
1. `@unsafe` does NOT silence it. The guide is explicit: "@unsafe ... falls
   outside Bend's proof-guarantees: `bend` runs it, but a check prints SOME
   PROOFS FAIL and names every def that relies on it". `@unsafe def` also is not
   the spelling (`unsafe def` is a parse error: "expected : 'def', 'type' or
   'law'"); the sugar is `def f?`.
2. The checker reports the IMPORT CLOSURE, not the file's own defs. A file that
   never mentions a seam still goes red, and a file that mentions it thrice gets
   named once per def, not once per use. `wgsl.bend` prints ALL PROOFS CHECK
   precisely because it does not import `dtype`.

CONSEQUENCE FOR EVERY UNIT: importing `dtype.bend` means your `--check-only` is
permanently red and that redness is NOT evidence about your work. Gate on the
two lanes printing identically (string rows), which is the project's rule
anyway; do not spend a cycle trying to make the checker green. Splitting the
seams into their own module WOULD make most files green again and was rejected:
one file per Python file is the prime directive.

## MEASURED 2026-10-02, renderer/wgsl.bend: list ORDER is a per-call-site choice and
## `String.join` is HEAD-FIRST (and the brief's rule 6 is INVERTED)

The brief's "MEASURED Bend 2.0.34 rules" item 6 says:

    6. Re-wrapping a list TAIL in any constructor is rejected. A head is fine
       (`[x] ++ rest` via `List.append` is a prepend). `List.append(a, A, xs, ys)`
       is `xs ++ ys`.

The first half is right. The parenthetical is BACKWARDS, and it cost three hours
and one shipped bug. Four facts, measured on a probe (`.agents/slop/wgsl_lprobe.bend`
shape), and only together do they fix the direction:

    `case h <> t` on a list LITERAL is head-first: ["a","b","c"] walks a,b,c.
    `x <> rest` is a PREPEND, so `h <> f(t)` rebuilds the list head-first.
    `List.append(acc, [x])` is an APPEND, so it rebuilds the list TAIL-first.
    `String.join` is HEAD-FIRST.

So the constructor is chosen by WHERE THE LIST GOES NEXT, and there is no default:

  - a fold whose result reaches `String.join`  ->  `List.append(acc, [x])`
  - a fold whose result is WALKED by `case h <> t`  ->  `x <> rest`

Getting it backwards typechecks, runs, and silently reverses whatever it built.
`renderer/wgsl.bend` M4/M5/M6 are the three mutations that do exactly this, and
each moves three rows -- `rk_bindings` and `rk_body` are the localised rows and
`rk alu` / `rk mixed` are the whole-shaders. The practical tell: a list built by
`List.append(acc, [x])` inside a `case h <> t:` walk comes out BACKWARDS, and the
error is a reversed shader, not a type error.

Corollary for a fold that feeds BOTH a walk and a join (a sort, a partition): the
walk is the one that is order-sensitive and the join is not, so build for the walk.

## The corollary about GATES, which cost a real bug: a predicate with no row is a
## predicate no mutation can find.

`is_packed` is three clauses and decides whether a buffer renders as
`array<atomic<u32>>` or `array<u32>`. This port shipped it with its third clause
INVERTED (ANDing `addr_is_reg` where tinygrad negates it), which made the whole
packed path -- `atomic<u32>`, `atomicLoad`, the `atomicAnd`/`atomicAdd` read-
modify-write -- dead code, because no buffer a shader reads is a REGISTER.

It typechecked. It passed 100+ rows. The ONLY row that moved was one line of a
700-character module row, and only after the `is_packed`/`buf_map`/`packed_size`
rows were added -- 40 rows, and the mutation table went from "M1 moves 1 row" to
"M1 moves 36". Two rules, both from this:

  - EVERY predicate needs its own row, called DIRECTLY, over the domain that
    discriminates it. A predicate reachable only through a big composed string
    has one bit of coverage per big string, and a module row's diff does not
    localise.
  - A mutation table is how you find out which rows you do not have. `moved == 0`
    on a mutation of live code is a MISSING ROW, not a passing test. The four
    zero-move mutations in `wgsl-mutate.py` named three missing row classes
    (`render_load` has none at all; the sort needs a fixture whose walk order
    differs from its sort order; one control edit).

## `match` cannot scrutinise a computed Maybe, and the fix is a `.of` helper whose
## name is NOT a def the body calls -- which then trips "unfilled law".

Refusing `match F.fold.addr(ar, tb, u):` (a CALL scrutinee) is the brief's rule 2.
The usual fix is `def w_addr.of(m): match m: ...; def w_addr(ar, tb, u) = w_addr.of(...)`.
That works. What does NOT work is splitting a SELF-RECURSIVE def the same way:
`def ls_ins.of(...): Bool.pick(..., ls_ins(x, t))` with `ls_ins` below it is
refused as "an unfilled law" (a law may not call live code), and putting `ls_ins`
above it is a forward reference. A self-recursive def keeps its decision inline --
`case h <> t: Bool.pick(..., x <> acc, h <> ls_ins(x, t))` compiles fine, as
`uop/render.bend`'s `u32_ins` shows. So: the `.of` split is for CALLS, never for
the self-call.

## `Bool.and` is not short-circuiting, and neither is the `Bool` in a fold

Not a Bend rule, a note on the shape: `Bool.and(U32.is_lt(...), Bool.not(O.eq_dt(...)))`
reads like short-circuiting and is not, so both calls are evaluated and both must
typecheck. In a `case 0n:`-style fold that means the `0n` arm cannot be written as
"skip the expensive call" -- it has to be `Bool.pick`, which IS lazy in its arms.

### 9. `F32` HAS NO SOURCE-LEVEL OPS, NO NEGATIVE LITERALS, AND IEEE `is_eq`
MEASURED (2026-10-02), four facts about the pinned 2.0.34 that between them cost
five compile cycles and would cost the next agent the same:

1. **`bend base F32` prints NINE defs and none of them are arithmetic.** The rest
   exist only as LAWS -- `grep "^law F32\."` lists `add sub mul div mod pow neg
   abs sqrt exp log sin cos ... is_eq is_ne is_lt bits read show to_u32`. They are
   compiler builtins with no body to read, so `bend base --names` and grepping for
   `def F32.add` both come up empty and the natural conclusion ("F32 has no
   arithmetic, this port must have rolled its own") is wrong.
2. **A NEGATIVE FLOAT LITERAL DOES NOT PARSE.** `def f() -> F32: -0.0` fails with
   "expected : a name / observed : '0'" -- the lexer takes `-` as a binder. Write
   `F32.neg(0.0)`. There is no float bitcast either (`dtype.bend:537` records this
   for the wide-dtype seams), so a bit pattern is reachable only via `F32.bits` on
   the way OUT.
3. **`F32.is_eq` is IEEE and `UOp.key` is a hash over the packed arg, so CONST
   IDENTITY MUST BE BITWISE.** The two cells where they disagree disagree in
   OPPOSITE directions, both measured live in CPython:
   `Tensor(0.0)._uop is Tensor(-0.0)._uop` -> **False** (0x00000000 vs 0x80000000)
   `Tensor(nan)._uop is Tensor(nan)._uop` -> **True** (0x7fc00000 both)
   So an IEEE test in an interning predicate collapses two distinct CONSTs in the
   first cell AND re-mints one identical node in the second. `U32.is_eq(F32.bits(a),
   F32.bits(b))` is the comparison the key performs. Keep `F32.is_eq` where the
   question really is a value question (`decomp.bend:126` asks "is this 1.0?").
   Every sibling of that predicate is already bitwise -- `eq_bool` is a xor,
   `eq_op` is the U32 tag, `eq_i64` is `H.i64_cmp` -- which is how you can tell a
   predicate that drifted from one that never had to.
4. **`{expr}` INTERPOLATION IN AN `IO.print` STRING DOES NOT FIRE.** `"is_eq={F32.is_eq(a, b)}"`
   prints the template verbatim, braces and all, with NO error -- a probe that looks
   like it ran and produced data. Use the tree's idiom: `String.concat([...])` with
   `Bool.show` / `U32.show` / `F32.show`.

### 10. FOUR MORE, ALL MEASURED BY THE `codegen/opt` UNIT (2026-10-02)
1. **A NEWLINE AFTER `Bool.and(` LEAVES IT UNAPPLIED.** The next line parses as the
   first argument and the whole nest collapses into one function value:
   "expected : Bool, observed : @b:Bool -> Bool". Same family as `case 0n:` quietly
   claiming every successor -- one construct, two unrelated-looking errors.
2. **`match rs hit:` WITH `hit` AS AN ACCUMULATOR IS WRONG FOR A FILTER.** The arms
   consume `h` and hand the NEXT call the CURRENT `hit`. Write a `_put(helper)` that
   takes the element and the accumulator and returns the next accumulator.
3. **`+` IS REFUSED ON A `U32`, AND A `U32` CANNOT BE READ TWICE IN ONE EXPRESSION.**
   So `a == 0 or a > 1` and `0 < a <= 2` are both unwritable as written. The exact
   rewrites are `a != 1` and `a - 1 <= 1` (using `U32`'s wrap), or thread the value
   through a `Data` record. Both rewrites are gated, not asserted.
4. **`def X.of(...)` MUST BE DECLARATED IMMEDIATELY BEFORE `def X(...)`, and the whole
   call chain must be in declaration order.** `X.of` before `X` fails with the
   misleading "a filled definition" -- which reads like a proof obligation, not an
   ordering rule.

### 11. FIVE MORE, ALL MEASURED BY THE `nn/state` + `nn/__init__` UNIT (2026-10-02)
1. **A `Char` LITERAL IS A VALID MATCH PATTERN, AND IT IS THE ONLY WAY TO SPELL A
   CHOICE-PLUS-DESCENT WALK.** `case '.':` scrutinees a BINDER and consumes `c` once
   per arm, so a walk like `drop(cs, acc)` needs no `Bool` at all:

   ```bend
   def drop(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
     match cs:
       case Nil{}: List.reverse(&2, Char, acc)
       case c <> t:
         match c:
           case '.': drop(t, acc)
           case _: drop(t, List.append(&2, Char, acc, [c]))
   ```

   This is the FOURTH shape found for that problem and the cheapest. `Char.is_eq(c,
   ...)` is a CALL and a `match` may not scrutinise one (rule 2); `Bool.pick` evaluates
   both arms and consumes `c` twice; and hoisting the `Bool` into a second def makes
   the two defs MUTUALLY recursive, which Bend refuses. A literal dodges all three.
   **The trap: a bare `case '.':` is not `lstrip`.** Dropping every dot gives
   `a..b..` -> `ab` where Python's `str.strip('.')` gives `a..b`; a head-run strip needs
   a "seen a non-dot yet" flag, and a `Data` sum type carrying it is the answer.
2. **`case 0n:` DOES NOT MATCH A `U32` AT ALL.** "expected : a constructor of U32
   (missing, or already matched)". So a countdown and the INDEX IT COUNTS must have
   different types: `def f(n: Nat, +i: U32, ...)` with `U32.to_nat(ndim)` at the entry.
   And there is **no `Nat.to_u32`** in base (only `U32.to_nat`), so a value that has to
   come OUT of a `Nat` countdown needs a second `U32` parameter rather than a
   conversion. For a negative axis, `-1-m` is built as
   `H.i64_of_hi_lo(0xFFFFFFFF, 0xFFFFFFFF - m)` -- the two's complement pair -- and not
   by subtraction.
3. **`List.append` AT THE TAIL AND `h <> acc` AT THE HEAD ARE DIFFERENT ORDERS, AND
   ONLY THE SECOND ONE NEEDS A `List.reverse`.** An accumulator built with
   `List.append(&2, T, acc, [x])` is ALREADY in order; a final `List.reverse` undoes the
   walk. This cost two gate rows (`bn_mask`, `bn_axes` both came out reversed) and it is
   the exact inverse of `state.bend`'s walk, which conses onto the head and so does
   reverse. **Read the accumulator's construction before you add a reversal.**
4. **`Bool.pick` IS THE ONLY WAY TO PUT A SELF-CALL IN A CHOICE-POSITION WITHOUT
   MUTUAL RECURSION, and it costs a `+` on every value both arms touch.** Rule 3's
   `_put(helper)` shape works when the two arms are VALUES; when one arm is the
   recursive call, `Bool.pick(T, cond, a, self_call(t, e))` is the shape, and `f`/`e`
   need `+` because `pick` evaluates both. The LIST must still be the first parameter:
   rule 5 reads left to right and stops at the first argument that shrinks, so a
   parameter that GROWS in the self call (`seen`) has to come second.
5. **BARE `False`/`True` IS A PARSE ERROR IN A CALL ARGUMENT BUT `False{}` IS NOT
   OPTIONAL EITHER WAY.** `T.flag(x, False)` gives "expected : a defined name, observed
   : False" while `Bool.show(...)` and a `match` scrutinee are the only places a bare
   `False` ever worked. **Write `False{}`/`True{}` in every value position** (rule 8 is
   about patterns; this is the value case it does not cover).

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING `device.bend`

The gate is 107 printed rows checked against the `tinygrad.device` oracle, both
lanes byte-identical, plus a 30-entry mutation table at the foot of the file.
Every rule below cost a compile cycle; the reproducer for each is a three-line
`.bend` file.

### 1. A LIST OF `Bool` IS NOT A USABLE TYPE

`List<&2, Bool>` is ACCEPTED as a parameter annotation and then refused by
every reader of one:

    def f(oks: List<&2, Bool>) -> Bool:
      match oks:
        case Nil{}: False{}
        case h <> t: h
    #| - message : a match on a parameter or field
    #|             (this name is a def or a consumed binder: give the value its own def)

which is the message you get for a PROJECTION and not for a list, so it sends
you looking for a `Data` field access. `List.get(&2, Bool, xs, 0n)` and
`List.length(&2, Bool, xs)` both report "expected a defined name": `Bool` does
not resolve in a `Kind` position. A `Bool` FIELD of a `Data` record is fine, and
so is `List<&2, Rec>` where `Rec` wraps the flag.

The fix that also removed a zip fold: availability/deprecation/mock-ness are a
U32 BITMASK read with `U32.shrn`/`U32.and` against the row's own index.

### 2. A PATTERN BINDER MUST NOT SHADOW A DEF NAME, and the error names the CONSTRUCTOR

    type Telf is Data: Telf{nm: String, sigs: List<&2, U32>}
    def Telf.name(x: Telf) -> String:
      match x:
        case Telf{name, sig}: name
    #| - message : a declared constructor (unknown: Telf)

The binder `name` shadows the def `Telf.name`, and the error points at
`Telf` -- the thing that is perfectly well declared. `case Bn{... spec}: spec`
fails the same way when the file also has `def spec()`. This is the same defect
the existing "A `Data` RECORD PATTERN ... " family has, one level up, and it is
worth grepping for: a binder named after any def in the file is a landmine whose
error message names something innocent.

### 3. `+` ON A PATTERN BINDER IS THE SPELLING FOR "TWO READS IN ONE EXPRESSION"

`+` is documented for parameters and for list heads, and the binder case is the
one that unblocks arithmetic. A `U32` is affine and cannot take a `+` as a
PARAMETER, so `(n+a-1)//a*a` -- `a` three times -- is a `Data` record of the two
operands with the `+` on the binder:

    type Amt is Data: Amt{n: U32, a: U32}
    def round_up.go(x: Amt) -> U32:
      match x:
        case Amt{n, +a}: U32.mul(round_up2(a, U32.add(n, U32.sub(a, 1))), a)

`Flags`, `Cap`, `Step` and `Run` in `device.bend` are the same trick for the same
reason, and the generalisation is the useful part: **when a `U32`/`Nat` is read
more than once in one expression, put the operands in a `Data` record and `+` the
binders.** That is cheaper than a `.go` split per read and it composes.

### 4. A NESTED `match` ARM MAY NOT CALL A `Type.def`

    def bnew.go(ns: List<&2, Bn>, b: Bn, ix: U32) -> BFound:
      match b:
        case Bn{...}:
          BFound{List.append(&2, Bn, Bar.nodes(ar), [...]), ix}
    #| - expected : Bar
    #| - observed : List<&2, Bn>

Inside a `Data` record arm, `Type.def(x)` is read as the TYPE applied to the
arm's binder, and the error is about the argument. Hoist the call above the
`match` and pass the value in. The same shape also bit `too_big`, where
`Bool.and(a, Bool.and(b, c))` with a shared `U32` produced the identical message.

### 5. A DEF MAY NOT CALL A NAMESPACE THAT A PARAMETER SHADOWS

    def isig.go(sig: List<&2, U32>, ...) -> ...:
      ...
        case Nil{}: acc
        case _ <> t: sig.go(t, ...)      # sig is the PARAMETER
    #| - expected : a term
    #| - observed : '.'

A parameter named `sig` makes `sig.go` a name lookup on the parameter. Every
`case k <> t:` fold in a file that also has a namespace called `t` has this
landmine -- and the error points at the fold, not at the binder.

### 6. `case True{} True{}:` IS A FINE ARM AND `case _ _:` AFTER IT IS FINE, BUT A `+` PARAMETER AND A `+` FIELD ARE NOT THE SAME THING

`def recycled(glru: Bool, lru: Bool, sp: Bspec)` reads `glru` and `lru` once each
and works. What does NOT work is `match glru lru Bspec.nolru(sp) ...` -- a
`Data` field is not a legal scrutinee even when the record is the parameter, so
the two flags have to travel as a two-field record (`Flags`) and be destructured
by the binder. This is `spec.bend`'s `DevOpt` shape and it is the ONLY reason
that shape exists; the `Maybe`-field prohibition and the non-scrutinee-field
prohibition are the same rule seen from two sides.

### 7. A `U32` THAT IS BOTH A LOOKUP KEY AND A FALLBACK VALUE BELONGS IN THE NODE

`base_of` needs the buffer's own index as an ANSWER (Python's `self._base if
self._base is not None else self`) AND the node to read `has_base` out of, and
`U32` is affine so the index cannot be passed twice. A `Slot{b: Bn, i: U32}`
record does NOT fix it -- `slot(ar, i) = Slot{bar_at(ar, i), i}` reads `i` twice,
and the fix-up `bar_at.make(ns, n) = Slot{..., n}` then reads `n` twice, one
level down. The fix that works is to put the index IN the node (`Bn.self_ix`),
stamp it at append time, and read it back off the record the append returned
(`BFound{ar, bar_next(ar) - 1}`). Three attempts failed before that one; the
tell in every case is the same error, "expected : i, observed : i (consumed more
than once)", and the generalisation is: **a value that is both a key and a
result belongs in the record you looked it up in, not beside it.**

## A GATE LESSON, AND IT IS THE SAME ONE THREE TIMES

`device.bend`'s first mutation table had three rows that moved NOTHING, and
none of them was a bad mutation:

* dropping `is_param` from `pm_bufferize` rules 0, 1 and 2 -- every fixture was
  a PARAM, so the conjunct was vacuously true. The fix was three NEGATIVE
  fixtures: a node that is not a PARAM, one named `b` that is not a PARAM, and
  one tagged `timeline` that is not a PARAM.
* lower-casing the `ALLOW_DEVICE_USAGE` list -- every fixture passed a
  lower-case spelling, so again the conjunct was vacuous. The fix was
  `allow_lower`, the spelling that must NOT be allowed.
* and then, WITH that fixture in place, the mutation STILL moved nothing,
  because the mutation touched the `DISK` branch and the rows exercise the
  `PYTHON` one.

So: **a mutation that moves nothing is information about the GATE, and the
response is to build the fixture it is asking for -- twice, if the first fixture
was for the wrong conjunct.** The third case is the one worth remembering: after
adding a fixture, RE-RUN the mutation, because "I added a fixture" and "the
fixture sees this mutation" are different claims.

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING `mixin/movement.bend`

Appended, not edited. All seven are Bend 2.0.34 and each one cost a compile cycle or a
wrong answer. The first is the one that cost the most and it generalises further than
it looks.

### 1. `case 1n+p:` DESTROYS THE SCRUTINEE — THE ARM CANNOT READ THE CURRENT COUNT

This is distinct from the recorded "`1n+p` is a first-match prefix" rule, and it is the
single most expensive fact in this port. `match k: case 1n+p:` binds `p` as a strict
subterm of `k` for the decrease check AND SPENDS `k`: the arm can no longer mention the
name `k` at all. Every walk that needs the current INDEX — not the tail — must thread
that index as its own parameter. Measured, three refusals and one working spelling:

```python
# REFUSED: expected p / observed p (consumed more than once) -- reported AT THE `1n+p:`
# PATTERN, so it reads like a pattern-syntax bug and is not one
List.append(&2, U32, [ix], go(p, nn, U32.add(ix, 1)))              # ix as a param: WORKS
List.append(&2, U32, [U32.from_nat(k)], go(p, nn))                 # reads k: REFUSED
List.append(&2, U32, [U32.add(nn, 2*U32.from_nat(p))], go(p, nn))  # reads p: REFUSED
```

The error text names `p` in all three cases and the CAUSE is `k`. Diagnosing this costs
a cycle every time because the compiler is pointing at the one binder that is fine.

### 2. SPLITTING A SELF-RECURSIVE STEP TO AVOID A DOUBLE READ CREATES MUTUAL RECURSION

Rule 3's remedy is "split the step into a `.go` and a `.put`". That works when the split
is between a WALK and its DECISION, and it is REFUSED when the split is between a
self-recursive walk and its own STEP — because the step calls back into the walk, and
the walk calls the step, and that is mutual recursion in either declaration order:

```
def w.go(k: Nat, ...) -> R:
  match k:
    case 1n+p: w.put(p, ...)          # w.put needs w.go  -> MUTUAL, refused
```

The working shape is ONE def whose arm both recurses and does the work, with the
element's contribution computed by a LEAF. The cost is that the leaf's own arguments
must not include the fuel.

### 3. `Bool` HAS NO `U32.show`, AND THE CONVERSION IS `Bool.pick` — THERE IS NO `Bool.match`

`base.bend` has `Bool.pick(-A, c, a, b)` and no `Bool.match`, so a gate row that computes
a `Bool` pays a two-arm conversion at every call site. Hoist it:

```bend
def b2u(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)
```

`U32.show` and `Nat.show` exist; `String.show` and `String.to_u32` do not.

### 4. `String.join(xs, sep)` TAKES THE LIST FIRST, AND `String.concat(xs)` TOO

Both take a LIST of pieces, so `String.concat("a", b)` is `expected : List<&2, String> /
observed : String`. And `String.join(",", xs)` — the natural Python reading — is the same
error. `String.join(xs, sep)` is right. The failure is silent in neither direction: it is
a type error at the first call, which is the good case.

### 5. `IO.print` TAKES A `String`, AND A `do IO<Unit>` BLOCK CAN ONLY BIND AN `IO`

The first is one line. The second is recorded for `uop/weak.bend` and it recurred here:
`m : MxMarg <- pure(...)` is `expected : a defined name / observed : pure`, so a PURE
fixture value is a `let` in the caller and a PARAMETER of the printing def. The cost is
one extra parameter per row def; the alternative is recomputing the pure value per row.

### 6. `List.take(xs, 0n)` IS THE EMPTY LIST AND `List.append(a, A, xs, ys)` IS `xs ++ ys`

The second is recorded. The first is new and it is a TRAP rather than a rule: a fixture
that takes a prefix of length 0 gets `Nil{}` and a fold over it produces an EMPTY answer
that reads as a correct empty shape. It cost one cycle here — a four-dim shape came out
with its two leading dims missing, and the `List.take` of length 0 in the debugger was
the whole diagnosis.

### 7. A FIXTURE MUST INTERN ITS SHAPE ARGS THROUGH ONE BUILDER, AND A LIST OF RAW INTS IS NOT A LIST OF ARENA INDICES

`shape_to_shape_arg` (ops.py:106) turns python ints into CONST nodes. A fixture that
writes `UOp.new(ar, OpsSTACK{}, [0, 1, 2, 3], ...)` builds a STACK whose "srcs" are the
raw VALUES 0..3 read as arena indices — index 0 is the arena's BOTTOM, so the reader
answers the bottom's `ANone` arg and the value comes out 0. It typechecks, the node count
is right, the `nsrc` is right, and every marg element reads 0. The one row that sees it
is the one that prints the marg's VALUES, and it is the reason this file has a separate
`*_marg` row next to every `*_shape` row.

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING THE WRITE HALF OF `mixin/movement.bend`

Appended, not edited, continuing the count from 11. All seven are Bend 2.0.34 and each one
cost a compile cycle or a wrong answer. The first is the most dangerous silent failure in
this port so far.

### 11. AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES, SO AN INTERNING INSIDE AN ARGUMENT BUILDS A SELF-EDGE

`O.UOp.new(ar, op, [u, O.Found.i(G.c1(ar, v))], ...)` is the obvious spelling and it
produces a node whose SECOND SRC IS ITSELF:

```python
add=n=8 op=Ops.ADD nsrc=2 srcops=Ops.RESHAPE|Ops.CONST   # correct
# add=n=6 op=Ops.ADD nsrc=2 srcops=Ops.RESHAPE|Ops.ADD   # what the obvious spelling gives
```

`G.c1(T.Tensor.ar(t), v)` interned into a COPY of the arena, and the index it returned is
the slot the ADD was about to occupy. The fix is to intern into a `let` FIRST and build
in the resulting arena -- which is the notes' existing "BEND IS STRICT" rule, reached from
a new direction. **The tell is a src-op sequence that names the root's own op.**

### 12. A `list` SELF-CALL MAY PASS A LIST TAIL FIRST AND A `U32` ARENA SECOND, AND THAT IS THE ONLY ORDER

`mxw_stk` walks a list of dims and grows an arena per dim. The decrease check wants the
list first, and the arena second:

```bend
def mxw_stk(+vs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> O.Found:
  match vs:
    case Nil{}: G.mstack(ar, acc)
    case v <> t: mxw_stk(t, O.Found.ar(G.c1(ar, v)), ...)     # list FIRST
```

Walking a LIST rather than a `Nat` countdown is the reason this is one def with no fuel:
the tail `t` is a strict subterm of `vs`, so the check is satisfied by the first argument
and there is nothing to thread.

### 13. THE "INTERN ONCE, READ TWICE" FIX IS MUTUAL RECURSION IN A WALK

`+f = G.c1(ar, v)` then reading `Found.ar(f)` and `Found.i(f)` is obviously right and it
needs a def boundary, and in a self-recursive walk the def calls back into the walk. The
workable forms, all measured in this file:

- a straight-line fixture (`stk4` for a fixed arity);
- a `Data` record carrying the accumulator;
- **call the pure function twice.** `O.UOp.new` and `O.UOp.const` are pure given an
  arena -- the arena carries the intern table, so the second call finds the node the first
  one added -- so `Found.ar(g(ar,v))` beside `Found.i(g(ar,v))` is CORRECT, not lucky.

That last one cost a cycle to convince me of and is the reason it is written down.

### 14. A GATE ROW THAT PRINTS A `srcops` SEQUENCE MUST PUT ALL FOUR FACTS IN ONE STRING

Four separate rows let a fixture drop one. The mutation that made this concrete: SWAPPING
A PAD'S TWO SHAPE ARGS (`self|a|b` to `self|b|a`) leaves the root op, the src count and
almost the node count alone, and it moved exactly TWO of seventy rows -- the two where an
identity test happened to fire. A gate carrying `op` and `nsrc` but not the sequence is
completely blind to it. `mxw_sig` prints `n= op= nsrc= srcops=` as one string for exactly
this reason, and the cost is that a mutation in the PRINTER then invalidates a quarter of
the suite (measured: 25 of 70 rows).

### 15. A SHAPE ARG BUILT BY A WALK MUST APPEND, AND THE BUG IS INVISIBLE IN THE COUNT

The second time in this file (the first was the printer). `mxw_stk` walks the dim list
DOWN and accumulates UP, and `List.append(&2, U32, [i], acc)` puts the new index at the
FRONT, so a STACK for `[1, 4, 8, 8]` came out `STACK(8, 8, 4, 1)`. The node count was
right, the root op was right, the `nsrc` was right. The symptom was an EMPTY shape,
because `mxm_as_shape` read a first element of 8 where the base had 1 and the identity
test could not match. **The general rule: an accumulator fold over DIMENSIONS has to say
which end it adds to, in a comment, because the type and the count cannot see it.**

### 16. `Arena.node` ANSWERS THE BOTTOM FOR AN INDEX PAST THE END, SO A STALE ARENA GIVES AN EMPTY ANSWER NOT A WRONG ONE

`mxw_reshape`'s identity test reading `T.Tensor.ar(t)` (the base's arena) with
`T.Tensor.u(made)` (the made node's index) returned `False` for a no-op reshape, so
`reshape` to the shape it already had BUILT a RESHAPE where CPython returns `self`. The
usual symptom of the aliasing rule is a wrong node; this one is a MISSING node, because
the bottom's shape is the empty list and the empty list does not equal anything.

### 17. A GATE MUST HAVE A NON-MOVEMENT FIXTURE OR A `match`'s CATCH-ALL ARM IS DEAD CODE

`mxw_shape_of`'s `case _ False{}` arm -- the one that answers a NON-movement op from the
fold -- had no fixture, so mutating it to `Nil{}` moved NOTHING. The reason every movement
row missed it: the one non-movement node they reached (the BUFFER under a RESHAPE) is a
node `fold.bend` does not answer, so its answer is the empty list EITHER WAY. The fix is a
non-movement node the fold DOES answer -- `ADD` inherits its shape from its src -- and the
row is `add_shape`.

This is the mirror image of the recorded "an arm after a `case _:` is dead code" rule: a
catch-all with no fixture is equally invisible, and a `case _` that is only reached by
nodes nothing else reaches is the same defect wearing a different hat.

## SIX MORE RULES, MEASURED 2026-10-02 WRITING `mixin/creation.bend`
## (items continue the count from 17)

Appended, not edited. Four of these six are substrate facts about `uop/fold.bend` and
`uop/ops.bend` that a caller must know and cannot read off either file's header; the
other two are Bend syntax. Each one cost a compile cycle or a wrong answer, and the
reproducers are named.

### 18. AN UNANSWERABLE NODE POISONS ITS CONSUMERS, SO "CAN THE FOLD ANSWER X" IS A
###     PROPERTY OF THE WHOLE SUBGRAPH, NOT OF X

This is the most expensive thing in this section and it is not in `fold.bend`'s header.

`fold.bend` answers `Ops.EXPAND` with `None{}` for the SHAPE (fold.bend:1629,
"`marg` -> `as_shape` -> `ssimplify`"). `Ops.STORE` and `Ops.AFTER` are `store_ds` and
`thru0` (fold.bend:730, :726), and BOTH read `src[0]`'s `Derived` -- so they are answered
when their `src[0]` is answered. But a Kahn worklist does not resolve a node until all
of its own srcs are resolved, so:

    MEASURED over `Tensor.full((2,3),42)`, nine nodes, one arena:
      1 ALLOC     dt=yes shape=yes
      2 CONST 2   dt=yes shape=yes
      3 CONST 3   dt=yes shape=yes
      4 STACK     dt=yes shape=yes
      5 RESHAPE   dt=yes shape=yes
      6 CONST 42  dt=yes shape=yes
      7 EXPAND    dt=NO  shape=NO      <- fold.bend:1629
      8 STORE     dt=NO  shape=NO      <- its src[1] is the EXPAND
      9 AFTER     dt=NO  shape=NO      <- src[1] is the STORE

So one unanswerable node three levels down makes the ROOT unanswerable, and a gate row
that asks the fold about the root of ANY graph containing an EXPAND gets `void` and `()`
for reasons that have nothing to do with its own code.

**THE CONSEQUENCE FOR EVERY CALLER, and it is a design decision rather than a workaround:
decide WHICH node to fold, not whether to fold.** The AFTER's own answer is `thru0`, i.e.
literally `AFTER.src[0]`'s, so folding `AFTER.src[0]` is not a weakening -- it is the
same answer obtained from the node the fold can reach. `mixin/creation.bend`'s `cr_d_root`
does exactly that, names the measurement, and its `_d` rows are still gated. The
alternative -- computing the shape from the construction -- is a row that restates the
code, which is the thing the gate exists to prevent.

This also retires a reading of `fold.bend`'s header: "the fold reports the absence and
the caller decides" is true PER NODE and misleading PER GRAPH, because the absence
propagates upward along every edge.

### 19. A FOLD THAT NEEDS AN INDEX MUST USE `Arena.srcs`, NOT A COUNT AND A RE-DERIVED
###     INDEX

    def srcops.go(+ar: O.Arena, +c: CU, n: Nat) -> String:      # the WRONG shape
      match n:
        case 0n:   ""
        case 1n+p: ... O.Arena.op(ar, O.Arena.src(ar, CU.u(c), 0)) ... cr_srcops.go(ar, c, p)

Every row printed `ALLOC|ALLOC|` for a two-src root. It checked, ran, and printed a
plausible string; the only reason it was caught is that the row carried `nsrc=2` beside
it. The fix is one call:

    O.Arena.srcs(ar, u)   # -> List<&2, U32>, and the walk needs no index at all

This is the same class as the recorded `mxm_as_shape.go` slip (an accumulator read
backwards) and it generalises the pair "walk a list" / "index into a structure": if the
walk needs `xs[k]`, take `xs` and walk it. `Arena.srcs` is already the substrate's own
answer for `x.src`, and `Tensor`'s `Tensors.ts` is the same idea for a record.

### 20. A LIST-OF-STRINGS FOLD MUST END IN `String.join`, NOT IN A BAKED-IN SEPARATOR

There are now four recorded spellings of "join a list of strings" in this port and the
first three each cost a row. The one that costs nothing is:

    List.append(&2, String, acc, [piece])   # APPEND, in walk order
    String.join(xs, " ")                    # HEAD-FIRST, and no trailing separator

`String.concat([acc, piece, " "])` needs a head test to avoid a trailing separator;
`String.concat([acc, cr_topo.go(List.tail(xs), ...), " "])` DROPS THE HEAD (and leaves a
trailing space). Both were written, both compiled, and both were caught only by the
CPython byte diff -- because the shape row reads `(2,3)` and the buggy one reads `(3,2)`,
which is a REAL wrong answer rather than a formatting one.

The general form, and it is the same for `U32` lists rendered with `U32.show`: **build a
`List<&2, String>` with `List.append` and hand it to `String.join` once, at the end.**
`List.append` is already the "which end does this list go next" decision from the wgsl
entry; `String.join` removes the other half of it.

### 21. `+r = R{a, b}` NEEDS AN ANNOTATION; `+r = f(...)` DOES NOT

    def f() -> U32:
      +r = R{1, 2}      #| - expected : an annotated term (cannot infer)
                        #| - observed : R{1, 2}
      R.a(r)

    def f() -> U32:
      +r: R = R{1, 2}   # ok
      R.a(r)

Three lines, no imports, both lanes. A `let`-bound RECORD LITERAL needs its type spelled;
a `let`-bound def call does not, because a def's return type is already known (upat.bend
rule "a computed value is not a valid scrutinee" has the same shape). It bites the
FIRST time in a file, which is usually a `CU{u: index}` or a `Fixed{n: U32}` helper
record, and it costs a cycle each time because the message names the record rather than
the `+`.

### 22. A BYTE-DIFFED GATE MUST NOT INHERIT A PRINTER WHOSE OUTPUT HAS TRAILING WHITESPACE

`mixin/op.bend`'s shared signature printer `mo_sig.go` emits `" "` after every node, so
every row built from it ends in a space. `mixin/creation.bend` needs the same toposort
string, reused it, and then the CPython oracle needed `.rstrip()` to match -- a
formatting asymmetry in the one comparison that is supposed to be exact. Four local lines
(`cr_topo.go` + `String.join`, rule 20) removed the asymmetry and made the rows readable
in a diff.

The general form: **a shared printer that another file's gate already diffs is a shared
FORMAT CONTRACT, and inheriting it means inheriting its whitespace.** When a new gate
reuses one, check `tail -c 1` on a row before the oracle is written, not after.

### 23. THE `int_*_new` SHAPE -- "HOW MANY DID THE SECOND CALL MINT" -- IS A ROW CLASS OF
###     ITS OWN, AND IT IS THE ONLY ONE THAT SEES `UOpMetaClass.ucache`

tinygrad hash-conses every UOp, so a second `Tensor.full((2,3), 42)` re-uses the CONST,
the STACK and the EXPAND and mints only the ALLOC/RESHAPE/STORE/AFTER. **Both graphs
have a nine-node toposort**, so `n=`, `op=`, `nsrc=` and the toposort are all identical
and every one of them is blind to the whole question.

The row that answers it is

    <n>_new = |{u in b.toposort() : u is not any(v in a.toposort())}|

with `is` in CPython and `U32.is_eq` on arena indices in Bend -- which is the same test,
because `ops.bend:940` says the index IS the identity. Two things about it worth keeping:

* the COUNT is not enough, and a second Bool row asking directly ("is the node that must
  be shared, shared?") is what localises the failure. In `creation.bend` the count row
  `int_full_new` moved 3 mutations and the Bool row `int_full_expand` moved exactly ONE
  that nothing else saw: reversing the STORE's two srcs. Same count, same op, same nsrc,
  same toposort, same src op sequence.
* the CPython oracle must count the same way. A `len(UOp.ucache)`-shaped row will not do:
  the cache holds WEAKREFS and entries not in the delta get collected, so the same
  program answers a different number on a second run.

This is the "it is not only rules that collide, it is any check whose oracle is a COUNT
rather than a STRUCTURE" note from `mixin/gradient.bend`, stated for the specific case
where the two structures are EQUAL in count by construction.

## NINE MORE RULES, MEASURED 2026-10-02 WRITING `mixin/rand.bend` (items continue from 23)

Appended, not edited. All nine are Bend 2.0.34 or substrate facts, and each one cost a
compile cycle or a wrong answer. Rules 1, 2 and 3 are the ones that cost the most and the
first two are the reason that file's gate is red rather than green.

### 1. AN ARENA IS AFFINE, SO A DEF THAT BUILDS **GROWS A COPY** -- AND THE FIX IS TO THREAD `+ar`
###    THROUGH EVERY BUILDING DEF, NOT TO "BUILD IN THE LAST ARENA"

The recorded rule (`codegen/transcendental.py` rule 1) is "every step threads
`O.Found.ar(<previous binding>)`". Measured while porting `mixin/rand.py`, the part that is
easy to believe and easy to get wrong is that **taking the arena off a tensor you were
HANDED is not the same thing as threading it**, because every def that builds along the way
has already grown a copy that you do not have a handle on:

    rd_tfb -> rd_p64 -> rd_c64 -> MO.mo_cast_t -> MO.mo_cast_in -> F.folded(T.Tensor.ar(t))

`mo_cast_in` re-folds the arena off its own argument and hands back a tensor whose arena is
that fold's, which is a copy. Two operands built through two such chains are in two
SIBLING arenas, and a node built in one of them names an index the other does not have.

**THE SYMPTOM IS A TOPOSORT OF ONE NODE, WHICH LOOKS LIKE A BUG IN THE PRINTER.**

    bits6_g=1 op=RESHAPE nsrc=2 srcops=STACK|STACK topo=CONST/0     <- the port
    bits6_g=81 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 CAST/1 ...  <- CPython

and `st_six_g=2` against CPython's `st_six_g=20`. The root's data src is not in the arena
being walked, so the "graph" is one node. **It also HANGS** when a `mxw_dims_of` fold runs
over it: `mixin/rand.bend`'s `randn_like23_g` dies with
`bend: memory fault (machine stack overflow?)`, which the notes' RUNAWAY-EXPANSION section
sends you looking for a non-terminating fold in your own code. There is none; the arena is
inconsistent and the fold over it does not terminate.

The generalisation, and it is the shape of every multi-file port in this repo: **a def that
may mint takes the arena as an ARGUMENT and rebases its operands with
`T.tn_new(ar, T.Tensor.u(t))` before building.** A node index is valid in every EXTENSION
of the arena it was interned into, so rebasing into a longer arena is always sound; what is
unsound is a def that picks its own arena off an operand it was handed.

### 2. A `U32` LITERAL PATTERN IS A PREFIX MATCH **FOR THE SUCCESSOR RELATION ONLY**, SO `case 8:`
###    DOES NOT SWALLOW `case 32:` -- AND THAT IS THE GOOD NEWS AND THE BAD NEWS

The recorded rule is "`case 1:` claims every successor", and
`codegen/opt` unit rule 10.3 restates it as "a `U32` literal pattern is a prefix match".
MEASURED here, the generalisation is FALSE and the narrow form is true: `case 8:` does NOT
claim 16, 32 or anything above it. `rd_one_bits`' arms `case 16: 15360 / case 32: 1065353216`
both fire on their own value (measured: `ref_one_bits_h=15360`, `ref_one_bits_f32=1065353216`).

**THE BAD NEWS IS WHAT ELSE IT DOES NOT CATCH, and the cost is a whole gate row.** The same
def spelled `case 8: 23 / case 16: 10 / case _: 0` -- arms on the EXPONENT where the switch
is on the BIT WIDTH -- compiles, checks, runs and answers `0` for float32. The
`case _:` is a real cover, so exhaustiveness is satisfied and nothing is dead. Two rows
(`ref_nmant_f32`, `ref_shift_f32`) caught it, and the mutation that drops the `case 32:`
arm moves EXACTLY those two and nothing else.

So the useful statement is: **a numeric arm ladder is only as good as the number it switches
on, and the compiler cannot see that number.** The recorded "prefix match" rule bites on the
ONE literal that generates all successors; the general hazard is that a `case _:` cover makes
a WRONG-NUMBERED ladder indistinguishable from a right one.

### 3. `mxw_reshape` / `mxw_shrink` / `mxw_pad` BUILD A `STACK` FOR A ONE-ELEMENT SHAPE ARG AND
###    CPYTHON BUILDS A BARE `CONST` -- SO A FILE THAT NEEDS CPYTHON'S ANSWER MUST CALL
###    `T.tn_mop` WITH `T.ADims`/`T.APairs` INSTEAD

`shape_to_shape_arg` (ops.py:106-110) is `return src[0] if len(src) == 1 else UOp(Ops.STACK,
src=src)`. MEASURED in CPython: `Tensor.empty(5).pad(((2, 0),))` is
`ALLOC/0 CONST/0(2) CONST/0(7) PAD/3` -- FOUR nodes, and the two shape args are BARE CONSTs.
`movement.bend`'s `mxw_stk` is `G.mstack`, which is UNCONDITIONALLY a STACK, and
`movement.bend`'s OWN header says so ("THE BARE-CONST CASE IS A DIFFERENT NODE and that is
the row `mxm_reshape1`").

**SO `T.tn_shape_arg.k`'s `one` arm is the ONLY spelling of CPython's rule, and it is
reachable only through `T.tn_mop`/`T.ADims`/`T.APairs` -- not through any `mxw_*` wrapper.**
`creation.bend` gets it right for free because `cr_mop` calls `T.tn_mop`; a file that
reaches for `mxw_reshape` gets a different graph for a one-element shape. `_cumalu`'s pad
is `((shape-1, 0),)` (op.py:754) and `_pool`'s first shrink is `(0, k*(i*f+1))`
(movement.py:610), so on the `arange` path BOTH of `_pool`'s first two shape args are
one-element and every `mxw_*` call adds a STACK.

The identity test is affected too, and the notes' `mxm_reshape1` row is the same fact from
the other side: `mxm_as_shape` reads `Arena.srcs` and a bare CONST has none, so a one-element
RESHAPE is un-answered for a SECOND and independent reason. `mixin/rand.bend` carries local
`op_pad`/`op_shr` for this and names the owner file, because `movement.bend` is read-only
there. **A file that needs CPython's graph has to own the one-element case itself until
`mxw_stk` grows `tn_shape_arg`'s fold.**

### 4. `+p: F32` IS ACCEPTED, SO THE `U32` "TWO READS NEED A RECORD" RULE IS NOT A `U32` RULE

`rd_p_ok(+p: F32) -> Bool: Bool.and(rd_p_ok.put(p), F32.is_le(p, 1.0))` checks, so a
two-read `F32` is a `+` parameter and a two-read `U32` is NOT (`+` is refused on a `U32`,
`nn/optim` unit rule 1). The `U32` answer is the `Data` record and the reader def
(`mixin/rand.bend`'s `U1`/`U1.v`), which is `device.bend`'s rule 3. Having both answers in
one file is what made the distinction visible: the rule is about the KIND, not about
"numbers".

### 5. `+dev: S.Dev` ON A `Data` PARAM IS FREE AND A GLOBAL `+` SWEEP IS THE FASTEST FIX FOR A
###    WHOLE FILE OF `Device` PASSED ONWARD

Twenty-five `S.Dev` parameters in `mixin/rand.bend` needed `+`, because `device` is threaded
from the fixture through six layers and read once per layer. `creation.bend` has the same
parameter. A blanket `dev: S.Dev)` -> `+dev: S.Dev)` sweep compiled first try. An UNUSED `+`
parameter is accepted (`uop/spec.bend` rule 2), so the sweep cannot break a def that does
not read it -- which is exactly why a uniform annotation is safe here and a uniform
annotation on a `U32` is not.

### 6. A `def X.of` CHAIN MUST BE DECLARED LEAF-FIRST **AND** `X.of` MUST IMMEDIATELY PRECEDE
###    `X` -- SO THE THREE-LINK CHAIN READS BOTTOM-UP

`codegen/opt` unit rule 10.4 records the one-def version. The three-link version, and it is
what "a `match` may not scrutinise a call" forces whenever a choice needs a call's result:

    def op_mop.of(same: Bool, +t, +made) -> T.Tensor: ...   # the LEAF
    def op_mop.of2(+t, +f) -> T.Tensor: op_mop.of(MX.mxw_same(...), t, T.tn_alu.put(f))
    def op_mop.put2(op, +t, lo, hi) -> T.Tensor: op_mop.of2(t, T.tn_mop(...))
    def op_mop(op, +t, lo, hi) -> T.Tensor: op_mop.put2(op, t, CR.cr_cdims(lo), CR.cr_cdims(hi))

Written in the order the reader wants (outer first) every one of the three is a forward
reference, and the error is "a filled definition (an unfilled law is a dead claim)". So the
chain is declared leaf-first and READ bottom-up, and the naming is what makes it legible:
`.of` is the leaf, `.of2` the next, `.put2` the next, and the bare name the wrapper.

### 7. `def f.g` and `def F.g` ON A LOCALLY-DECLARED `Data` RECORD NEED A READER DEF, A FIELD
###    PROJECTION IS NOT ONE, AND A ONE-FIELD READER IS REFUSED

`def PK.i(q: PK) -> U32: match q: case PK{i}: i` is refused with
`a PK pattern with 2 fields` -- the two-field rule from `renderer/cstyle.bend` rule 5, reached
from a record whose fields are all `U32`. And `PK.i(q)` as a BARE projection is
"a defined name, observed : PK.i", so a locally-declared record has no projection syntax at
all: a reader def is the only way, and it is the shape `ops.bend`'s `CU.u`,
`movement.bend`'s `MxMarg.ds` and `tensor.bend`'s `Tensors.ts` already use.

### 8. THE ORACLE'S `print("k=", v)` HAS A TRAILING SPACE AND IT IS HALF THE DIFF

`creation.bend` rule 22, re-measured. `print("ref_x=", True)` prints `ref_x= True` and the
Bend row prints `ref_x=True`, so a byte diff reports 31/49 mismatches on a file where 31/49
match. `print("k=" + str(v))` is the fix, and the generalisation is: **write the oracle's
row strings the same way the port's are, before the first diff, not after the first
confusing one.** The same row of this table and the `fold_np`/`fold5_np` BEND-ONLY rows are
the other half: a row with no oracle is a `BEND-ONLY` row and it belongs in a named list, not
in a silent filter.

### 9. A `.bend` FILE CAN `ALL PROOFS CHECK` IN BOTH LANES, PRINT LANE-IDENTICAL OUTPUT, AND
###    STILL BE WRONG AGAINST CPYTHON -- SO "THE GATE IS GREEN" IS NOT A PROPERTY OF THE FILE

`mixin/rand.bend` measured 2026-10-02: `ALL PROOFS CHECK`, interpreted and native lanes
byte-identical, 49 printed rows, 31 shared with CPython and GREEN, 18 RED. All 31 green rows
are NON-GRAPH rows (refusals, dtype arithmetic, counts) and all 18 red rows are GRAPH rows.
The two lanes agreeing with each other says the port is DETERMINISTIC; it says nothing about
whether the port is RIGHT, and the only thing that says that is the third lane.

**THE SHARP FORM OF IT, and it is the cheapest diagnostic in this section:** a row that is
RED can be a *printer* problem (rule 8 above) and a row that is GREEN can be a
*reachability* problem (a `ref_*` predicate that nothing in the file calls). Measure the
green count BY ROW CLASS, not in aggregate. "31/49" is uninformative; "31/31 non-graph rows
and 0/18 graph rows" names the defect in one sentence.

### 24. `Emit` AND `Halt` BELONG TO BASE's `IO.OP` — A LOCAL `type Emit` IS A DUPLICATE
MEASURED (2026-10-02, cost the renderer/cstyle unit its whole run: the agent died
mid-rename and left a file that would not check). Bend's Base declares
`type IO.OP<-R: Type> is Type:` with constructors `Emit{value: R}` and
`Halt{code, message}`, so the names `Emit` and `Halt` are TAKEN in the flat
constructor namespace. Declaring your own `type Emit is Data:` fails with
    expected : a fresh constructor name (duplicate declaration: Emit)
which reads like a duplicate in YOUR file and is not: `grep -rn "type Emit is Data"`
returns exactly one hit, and `Emit` appears nowhere else in the port. It is not
shadowing either -- an aliased import (`import ./__init__.bend as R`) does not help,
because Base itself is imported unqualified.

THE FIX IS TO ESCAPE THE NAME, not to invent a different concept for it: `Emit_`,
with a comment naming the wall and Base's owner. Same precedent as `@function_` in
`examples/beautiful_mnist.ts`. `bend base 2>/dev/null | grep -n Emit` is the check,
and it costs one second -- do it BEFORE naming a record, not after the file is 2000
lines deep.

### 25. `volatile` IS A RESERVED WORD AND CANNOT BE A FIELD NAME
MEASURED (2026-10-02, three-line probe, ~30 seconds versus a 90-second compile of
the file that hit it). A record field named `volatile` does not even parse:

    type T is Data:
      T{volatile: Bool}
    def rd(t: T) -> Bool: t.volatile
    -- expected : a defined name / observed : t.volatile

There is nothing wrong with the declaration and nothing in Base defines `volatile`
(`bend base --names | grep volatile` is empty), so unlike rule 24 this is the LEXER
holding the name, not a namespace collision. CONFIRMED with the correct spelling
(rule 26) so the two are not confused: `T.mutable(t)` compiles and `T.volatile(t)`
fails with the same message. tinygrad's `ParamArg` has a `volatile` field, so every
port that mirrors that record hits this. ESCAPE IT: `volatile_`, with a comment
naming the reserved word -- same precedent as `Emit_` in rule 24 and `@function_`
in the TS example.

CAUTION, and this cost an hour: this rule was FIRST observed as `t.volatile`
failing, which is really rule 26 wearing a disguise. `volatile_` did not fix that
error, because the syntax was wrong, not the name. When a probe disagrees with a
rule, suspect the rule you have not yet measured.

THE LESSON, which is the real content of both rules: before naming a record after
the Python, check the name is AVAILABLE. Two commands, both about a second:
`bend base --names | tr ',' '\n' | grep -i <name>` for a Base collision (rule 24)
and a three-line probe for a reserved word (this rule). Both were found by an agent
dying mid-file and the coordinator re-deriving the cause from a parse error.

### 26. A FIELD IS READ `Type.field(value)` -- THERE IS NO `value.field` SUGAR
MEASURED (2026-10-02, three-line probes). `def rd(t: T) -> Bool: t.mutable` does
NOT parse:

    expected : a defined name / observed : t.mutable

and it fails identically whether `t` is `+`-affine or plain, so this is not rule 5.
The working spelling is the namespace-qualified projection, which is what the rest
of this port already does everywhere: `T.mutable(t)`, `T.Tensor.u(t)`,
`O.Arena.op(ar, u)`, `S.Dt.cls(d)`. A `match` arm must still name EVERY field
(`case T{mutable, image}: ...`), or it reports "a T pattern with 2 fields".

This is why the tree reads the way it does. `value.field` is the Python/C reflex
and it is silently unavailable; the projection-def idiom is not a style choice, it
is the only spelling. A 1960-line file written in the Python reflex does not merely
have a few errors -- it has one per field read, and each costs a compile cycle to
discover because the checker reports only the FIRST. When a dead agent leaves a
large file that does not check, COUNT the errors in the file's idiom before you
start patching: if it is this mistake, it is a mechanical rewrite (one sed-shaped
pass plus a hand pass for nested ones), not a debugging session.

### 27. THERE IS NO AUTO-GENERATED FIELD PROJECTION AT ALL -- AND RULE 26's `T.mutable(t)`
###     EXAMPLE IS WRONG, THOUGH ITS VERDICT ABOUT `t.mutable` IS RIGHT

MEASURED (2026-10-02, cost `renderer/cstyle.bend` a compile cycle and, more
importantly, would have sent the next agent looking for a Bend feature that does not
exist). Rule 26 says the working spelling is the namespace-qualified projection and
gives `T.mutable(t)` as compiling. **For a LOCALLY-DECLARED record it does not
compile.** The three-line probe, run one line at a time because the checker reports
only the first:

```bend
import Base
type T is Data:
  T{mutable: Bool}
def rd(t: T) -> Bool: t.mutable
#| - expected : a defined name
#| - observed : t.mutable
def rd2(t: T) -> Bool: T.mutable(t)
#| - expected : a defined name
#| - observed : T.mutable          <-- rule 26 says this COMPILES
```

And the rule-25 escape does not help either: `T2{volatile_: Bool}` with
`T2.volatile_(t)` is refused the same way. So rule 26's VERDICT (`t.mutable` is
unavailable) is right and its SPELLING is not, and the reason the tree looks like
rule 26 says is that **every `Type.field` reader in the port is a hand-written
`def`**. `ops.bend` declares `Arena.op` / `Arena.src` / `Found.ar` / `Node.tag`;
`spec.bend` declares `Dt.bits` / `Dt.cls` / `Sp.shape`; `cstyle.bend` declares
twenty-two of them for its own four records. There is no record in the tree whose
reader is generated, and there cannot be one: the reader needs a `match` that names
EVERY field, and the compiler does not know the field list at the point a reader
would be needed.

THE CORRECT RULE, THEN: a field is read `Type.field(value)` **and `def
Type.field(x: Type) -> T: match x: case Type{f1, f2, ..., fn}: fi` is written out
by hand for every field.** Cost: two lines per field, and renaming a field is one
edit per reader. What it buys back: the reader is a real def, so it is nameable in a
comment, mutable in a mutation, and identical in shape whether the record is local or
imported.

THE PART THAT HAD BEEN MISREAD FOR TWO RULES: "the only spelling is
`Type.field(value)`" is true of the CALL and false of the DEFINITION. Rule 24
(`Emit` is Base's), rule 25 (`volatile` is reserved) and rule 26 (`value.field`) all
described the call site. This one describes the declaration, and it is the reason
the same three escapes (`Emit_`, `volatile_`, and twenty-two `Type.field` readers)
appear together at the top of a file that touches four local records.

### 28. A `Bool` PARAMETER DOES NOT MAKE A TWO-DEF SPLIT OF ONE RECURSION LEGAL -- IT IS
###     STILL MUTUAL RECURSION, AND THE COUNTDOWN MUST BE THE REMAINING COUNT

MEASURED (2026-10-02) building HIP's and CUDA's prefix clauses, which are "emit
clause 0, then 1, then 2, ... up to a per-device count". The natural shape is a
pair, because a `match` may not scrutinise a computed value:

```
def go(..., k, acc): at(U32.is_eq(k, count), ..., k, acc)     # compute the Bool
def at(same, ..., k, acc): match same: ... go(..., k+1, ...)    # consume the Bool
```

That is mutual recursion and it is refused -- but the FIRST error is the misleading
one, `expected : a filled definition ... observed : go`, because `go` is declared
below `at`. Fix the order and the mutual-recursion refusal arrives. Convention 9 in
`renderer/__init__.bend` already says the self-call must live inside the def that
owns the `match`; this is the measured consequence, and it forces ONE def:

```
def dev_prefix.go(rem: Nat, ..., k: U32, acc: ...) -> ...:
  match rem:
    case 0n: acc
    case 1n+m: dev_prefix.go(m, ..., U32.add(k, 1), add(acc, clause(..., k)))
```

**THE COUNTDOWN IS THE REMAINING CLAUSE COUNT AND NOT THE LOOP INDEX**, and that is
the whole shape rather than a style choice: `k` only GROWS, the decrease checker
reads the first argument that shrinks, and so a `k`-first signature fails with
`expected : a decreasing self-call`. Passing `count - k` in first and incrementing
`k` inside is what makes one def enough. It also happens to read better: `rem` is the
question ("is there anything left?") and `k` is bookkeeping.

### 29. `+` ON A LATER PARAMETER DOES NOT DISTURB THE DECREASE CHECK ON THE FIRST ONE

MEASURED (2026-10-02), same def. The self-call above passes `rem` (shrinks, first),
then `dev`, `u`, `vecs`, `ockl`, `ocml`, `cdna4`, `k` and `acc`. Three of those are
read twice in the one arm and need `+`: `cdna4` (once in `prefix_clause`, once in the
self-call) and `k` (once in the self-call's arithmetic, once in `prefix_clause`).
`+` on them is accepted and `ALL PROOFS CHECK` holds.

This is worth one line because the fuel sections above say twice that "marking either
`+` breaks the check -- a reusable binder stops counting as a subterm". That is true
**only for the binder that does the shrinking**. A `+` on the SEVENTH argument of a
nine-argument self-call cannot affect the decrease, and refusing to add it (on the
theory that it might) makes the arm impossible.

### 30. `+` ON A `U32` IS FREE, AND A `Nat` `match` WITH `case 0n:` THEN `case 1n+m:` IS
###     THE WHOLE COUNTDOWN

MEASURED (2026-10-02), same def, and both halves of it are things the sections above
state only in fragments. `+k: U32` is accepted: `U32` is `Data`, so a `+` costs a
reference count and nothing else (`rand.bend`'s rule 4 already said this for `F32`).
And `match rem: case 0n: acc; case 1n+m: ...` is exhaustive and correct -- `1n+p` IS
a first-match prefix (the correction section's point), and it is correct HERE
precisely because the `0n` arm is listed first, so the prefix pattern never sees a
zero. The prefix semantics are not a hazard in a countdown; they are a hazard in a
`match` whose arms are *intended* to be disjoint, which is the only place the
correction actually applies.

### 31. NO LIST COMPREHENSIONS -- BUT CLOSURES EXIST AND `List` IS FULLY ERGONOMIC
MEASURED (2026-10-02, five probes). Three facts, and the third one retracts a
standing instruction in the agent brief.

1. **THERE IS NO COMPREHENSION SYNTAX.** `[U32.add(x, 1) for x in xs]` fails with
       expected : a term (the keyword 'for' cannot head one)
   and `[x for x in xs() if p(x)]` likewise. The guide never mentions the word.
   CONSEQUENCE: a Python comprehension is NOT a source of our line-count excess,
   because the Bend equivalent is also one call -- `List.map(~A, ~B, f, xs)` is the
   same length as `[f(x) for x in xs]`. Anyone blaming comprehensions for the 2.28x
   is looking in the wrong place.
2. **CLOSURES AND DEF REFERENCES BOTH WORK.** `x => U32.add(x, 1)` is a closure;
   a plain def may be passed as a function value and called as many times as you
   like (the guide is explicit: "unlike a closure, may be called as many times as").
   Multi-arg function types are curried: `U32 -> U32 -> U32`.
3. **THE ARITY QUANTIFIER IS HOW YOU CALL THE `List` FOLDS.** A `List` is
   `List<a, A>` where `a` is the arity, so a cons list is `List<&2, U32>` and you
   pass the arity to the fold:
       List.filter(~U32, big, xs)                     -- f is 1-ary, the ELEMENT
       List.foldl(~&2, ~U32, ~U32, addn, xs, 0)       -- f is 2-ary, (acc, elem)
       List.any(~&2, ~U32, big, xs)
   All three compile. Note `List.map` takes `List<A>` (whole-list element type) and
   so infers `&1` unless you pass the arity explicitly -- that inference is what
   makes a map over a cons list look like it "lost" a level.

**WHAT THIS RETRACTS.** The agent brief has said for days that rule tables must be
copyable `Data` "so there are no closures". That was my assumption, not a
measurement, and it is wrong: closures and def references both work. The rule
tables are still plain `Data` -- copyable, gateable, mutation-testable, and a
closure per rule would make a table unprintable -- but the REASON is now the gate
and the table, not a language limitation. Do not tell the next agent that Bend
lacks closures; it has them. The real cost of our line count is elsewhere: one
hand-written reader per record field (3,499 of them), ~81 duplicated dispatch
scans, ~1,316 two-arm `Maybe` reads, and comment density -- and a share of the
`.put`/`.go` helper proliferation is self-inflicted when `List.foldl` with a
top-level 2-ary def would do.
