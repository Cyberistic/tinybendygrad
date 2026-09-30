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
and the flatten all disappear. `matcher-store.bend` is a correct implementation
of a component that should not exist.

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
