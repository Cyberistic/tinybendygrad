# NOTES — what Bend 2.0.34 actually does

Everything here was measured against the pinned checkout in `references/bend`,
not read off the guide. Each item has a reproducer. These are additions to
`.agents/slop/notes/bend2-constraints.md`, which is the project's own record;
this file is the part that only the `langs/` work turned up, and it is written
for whoever hits one of these next.

Reproduce any of it with `./bin/bend FILE.bend`.

---

## 1. `Array.get` cannot be called on a def parameter

`Array.get` is the documented reader for a non-`U32` array. On 2.0.34 it does
not typecheck when the array is a plain def parameter:

```python
def t(a: Array<U32>, i: U32) -> U32:
  (aa, v) = Array.get(U32, a, i)      # error: a match cannot scrutinize a
  v                                   #        computed value
```

Every other array call is fine — measured, one case each:

| call | with a def parameter |
| --- | --- |
| `Array.get` | **FAIL** |
| `Array.set` | ok |
| `Array.size` | **FAIL** |
| `Array.swap` | ok |
| `Array.clone` | ok |
| `Array.to_list` | ok |
| `Array.map` | ok |

So it is `Array.get` and `Array.size` specifically, and `Array.get` is the one
the guide tells you to use. `Array.swap` is the way out: it takes the new value
and answers the **old** one, so it reads as well as writes — but it writes, so a
read costs a write.

`brw_arrays.bend` in bend's own test suite passes an array that is a *field
binder* from a matched constructor, which is why the defect has survived: that
call site works.

**What `langs/core.bend` does instead.** Arrays stay the boundary type and
`core_step` still takes `Array`, but inside the kernel an array becomes a list,
because `List.get` works on a parameter. `Array.to_list` answers
`List<&1, F32>`, which is single use, so `share_f` copies the spine into a
`List<&2, F32>` and the kernel indexes that.

---

## 2. A def may not destructure the result of a call

```python
def f(x: U32) -> F32 & F32: ...

def g(xs: List<U32>, acc: F32) -> F32:
  match xs:
    case Con{h, t}:
      (a, b) = f(h)          # error: a match cannot scrutinize a computed value
      g(t, F32.add(acc, a))
```

A let-bound *scalar* off a call is fine; the tuple destructure is not. The whole
repo's idiom agrees — every `(a, b) = r` in `tinybendygrad/` destructures a
parameter, never a call result:

```
$ grep -rEn '^[[:space:]]*\([A-Za-z_0-9]+, [A-Za-z_0-9]+\) = ' tinybendygrad
tinybendygrad/helpers.bend:1248:  (hi, lo) = r
```

**The way out** is a value that travels in a cons and is read back by index,
which is what `core_trace` is: it answers one `List<&2, F32>` rather than a
tuple, and `at_f` reads it. A def that takes the pair as a *parameter* and
destructures that works, but threading it there needs a caller, and a caller
that also cannot destructure a call — so cons-and-index is the shape that
actually composes.

---

## 3. A `case 1n+pn:` arm cannot hold a call

This one matters most, because the project's recorded design leans on Nat fuel
for every loop (see `.agents/slop/notes/bend2-constraints.md`, "The fuel
detour"). On 2.0.34 that is only true while the arm holds nothing but the
self-call:

```python
def f(n: Nat) -> F32: 0.0

def g(nb: Nat, acc: F32) -> F32:
  match nb:
    case 1n+pn:
      g(pn, F32.add(acc, 1.0))        # ok

def h(nb: Nat, acc: F32) -> F32:
  match nb:
    case 1n+pn:
      g(pn, F32.add(acc, f(nb)))      # error: pn (consumed more than once)
```

The error blames `pn` and points at the pattern, which is why it costs time.
The same arm with a list fuel is fine, with or without a call:

| fuel | a call in the arm |
| --- | --- |
| `case 0n:` / `case 1n+pn:` (Nat) | **FAIL** |
| `case Nil{}:` / `case Con{}:` (list) | ok |

**So every walk in this port is list-fueled.** That is not a style preference;
Nat fuel is unusable the moment the loop body calls anything, which is almost
always.

---

## 4. A Nat parameter is not a literal pattern

```python
def split(cs: List<&2, Nat>, n: Nat, w: List<&2, F32>, cur: List<&2, F32>, ...)
  match cs w:
    case Con{n, ct} Con{h, t}:     # matches ANY c, not just c == n
      split(ct, n, t, Nil{}, Con{List.reverse(&2, F32, Con{h, cur}), out})
```

The checker accepts it and it always matches, so the "row width" silently
becomes "every element", and the program typechecks while doing the wrong thing.
This one produced 1-element rows and a plausible-looking loss before it was
caught.

**The way out** is to put the marker in the list, where `0n` and `1n` are real
literals, and destructure it in the pattern: `case Con{0n, md} ...`. A marker
list built by `marks(n)` is 1 line and says what it is.

---

## 5. A nested pattern must be exhaustive at every level it names

`case Con{a, Con{b, Con{c, Con{d, t}}}}} Con{_, lt}:` is rejected with
"expected: cases for Nil", because the scrutinee may hold 0, 1, 2, 3 or 4+
elements and the pattern names exactly 4. A `case Nil{} _:` does **not**
substitute — `_` on a scrutinee still has to enumerate.

**The way out**, used by `batch`: peel one level per match. Four levels of
nested `match` where a four-deep pattern would do, but each is two arms and
needs no permutation table.

---

## 6. A nested `match` on a fresh field binder is rejected

```python
def split(marks: List<&2, Nat>, w: List<F32>, cur: List<F32>, out: ...) -> ...:
  match marks w:
    case Con{d, md} Con{h, t}:
      match d:              # error: a match on a parameter or field
        case 0n: ...         #        (this name is a def or a consumed binder)
```

`d` was just bound by the enclosing pattern, and re-matching it is not allowed.
Put the distinction **inside** the pattern instead — `case Con{0n, md}` versus
`case Con{1n+q, md}` — and the same thing compiles.

---

## 7. Declaration order is binding

```
def get_u(...): get_u.maybe(...)
def get_u.maybe(m: ...): ...     # error: an unfilled law is a dead claim
```

A dotted name used before it is declared is read as a *law proof* to be
filled. The same def in the other order is fine. Bend has `@unsafe` to lift
this; without it, just declare in order.

---

## 8. `Array.to_list` is in index order

Worth recording because it reads like it should not be. Its accumulator makes it
look reversed; it is not. Filling slots 0..3 with 10.0, 11.0, 12.0, 13.0 gives
`10, 11, 12, 13` back, not `13, 12, 11, 10`.

---

## 9. The emitted C source, and what it needs to build

`-o file.c` writes `Comp.compile_book(book)` — C source, 7597 lines for
`langs/core.bend`. Three things about it that a C lane has to know:

- **It owns `main`.** It parses the runtime's own flags (`--threads`, `--gpu`)
  and hands the rest to `IO.args`, which is where the program's payload comes
  from. Linking a separate harness means renaming it: `-Dmain=bend_main`.
- **There are no per-def symbols.** Every def compiles to a segment of a flat
  state machine, so there is nothing named `core_step` to `dlsym`; a C lane has
  to drive the program's own entry point.
- **bend builds with no `-ffp-contract` flag** (`cli_build` in `main.ts`), so
  on arm64 clang may fuse `a*b+c` into an FMA and produce a different f32 from
  every other lane. Nothing in `langs/core.bend` trips it — measured, the native
  binary and `-ffp-contract=off` agree — but the C lane passes the flag itself
  so contraction is never the variable under test.

---

## 10. f32 agreement between the C and JS lanes is a property, not luck

Worth writing down because it is the assumption the whole gate rests on. The JS
lane wraps every f32 operation in `Math.fround`, so each one is computed in f64
and rounded once more. That double rounding is *innocuous* for `+ - * /` and
`sqrt` (f64 carries 53 bits, more than the 2p+2 = 50 that guarantees it), which
is why the matmul agrees exactly. It is **not** innocuous in general for a
transcendental — but `exp` and `log` were checked directly and agreed bit for
bit on every value tried, so the core uses them and the gate holds.

If a future core needs a function with no such guarantee, the answer is to write
it in the core using only `+ - * /`, not to hope.

---

## 11. `Array.set` writes through a wrapped index

Indexes wrap, like `a[i]` does. A `put` that writes one element past its count
silently corrupts slot 0. It typechecks, it runs, and the answer is a plausible
loss computed over rotated data. Truncate at the count instead — for a
fixed-shape core, an over-long payload is a payload bug, not a shape to honour.
