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
* A rewrite rule needs the arena, so it cannot be a closure (a closure is
  single-use and cannot capture an affine value). Rules become **top-level
  `def`s taking and returning `ctx`**, dispatched by an explicit tag. This
  is the biggest single structural change in the port and the reason
  `uop/ops.py`'s `PatternMatcher` is not a mechanical transliteration.

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
