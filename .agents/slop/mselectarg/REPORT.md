# mselectarg — `MSELECT`'s arg is an `int`, and the port stored it as a one-byte `ABlob` (`bytes`)

Unit `mselectarg`, 2026-10-06. **STATIC-ONLY: `bend` was NOT run** (unit `run34` holds it). Python
only; no `.txt`; no commit, no `git add`, no `@`.
**Files I edited (3):** `tinybendygrad/uop/ops.bend`, `tinybendygrad/uop/render.bend`,
`tinybendygrad/uop/upat.bend`.
**I did NOT touch** `checks/`, `gates/`, `AGENTS.md`, `.agents/slop/graphcmp.*`,
`tinybendygrad/uop/fold.bend`. **`graphcmp.bend` is FORBIDDEN and it now does not compile — §6.**

---

## 0. Verdict up front

The `WALL(p3)` has **arisen** (a graph exercises it) and is **closed on the port side**: `mselect`'s
arg is now the new `AInt` variant, not `ABlob`. **The differ row cannot go `AGREE` without ONE arm in
`graphcmp.bend` that I am forbidden to add** — so the bend lane is **UNMEASURED / build-broken**
(§6, §7). `SKIP`/`DEAD`/`REFUSED` are not passes.

---

## 1. The WALL block, verbatim (pre-edit `ops.bend:4553-4566`)

The marker's own text is the spec; not paraphrased:

```
# `mselect` -- ops.py:772. `UOp(Ops.MSELECT, src=(self,), arg=arg)` where `arg` is
# an INT -- a shard index into a multi-device tensor. `ABlob` is the arena's existing
# "a bare number in the arg" arm, and reusing it is the honest choice over minting a new
# one: MSELECT's arg is a number and nothing else reads it. Since `ABlob` now holds BYTES
# rather than a length, the int is the ONE-BYTE blob `[k]` -- which is injective in `k`,
# so two different shard indices are still two different keys, and it is what the key
# needs since `eq_arg.ABlob` reads content. The op is in the key too, so an MSELECT's
# `[k]` can never collide with a BINARY's bytes.
# WALL(p3) ops.py:201 -- BLOCKED ON A CASE THAT HAS NOT ARISEN, and the trigger is written down.
# `type(arg)` in `ops.py:201` separates an `int` arg from a `bytes` one; `eq_arg` has no such arm.
# The port does not need one TODAY: `ABlob` holds BYTES rather than a length, so an MSELECT's `[k]`
# is injective in `k` (two shard indices stay two keys) and the op is in the key too, so it cannot
# collide with a BINARY's bytes. IF A LATER UNIT MUST TELL AN `int` FROM A `bytes` ON ONE NODE,
# that is a NEW `Arg` arm and `eq_arg` grows an arm with it.
```

Read against the trigger's own words:

* **what it claims is missing** — "`eq_arg` has no such arm" for the `int`-vs-`bytes` separation
  that `ops.py:201`'s key makes with `type(arg)`. The *closest available thing*, in the wall's own
  words, is "`ABlob` is the arena's existing 'a bare number in the arg' arm".
* **the promise/prescription** — "IF A LATER UNIT MUST TELL AN `int` FROM A `bytes` ON ONE NODE, that
  is a NEW `Arg` arm and `eq_arg` grows an arm with it." That is exactly what `AInt` is.
* **the trigger has now fired**, in `runs/graphcmp/D/D1-graph-mselect.txt:12`:
  `arg   py=i0 bend=y n(i0)` and `:37 VERDICT: DISAGREE`.

---

## 2. Both sides' current spelling (file:line, old → new)

| site | file:line (pre-edit) | old text | new text |
|---|---|---|---|
| py lane, op arm | `.agents/slop/graphcmp.py:477-564` `carg` — **no `MSELECT` arm**; falls to `:564 return _carg(x)` | `_carg(0)` → `u(0)` → **`i0`** (`:372 def u(x): ATOMS["u32"]+str(x)`; `ATOMS["u32"]="i"` `:324`) | unchanged (py is already right) |
| py lane, write site | `.agents/slop/graphcmp.py:1562-1568` `g_mselect` | `… .mselect(0)` → int `0` → `i0` | unchanged |
| bend lane, op arm | `.agents/slop/graphcmp.bend:465` | `case O.ABlob{bs}: blobstr(bs)` → `blobstr` (`:392`) = `"y n("+…+")"` → **`y n(i0)`** | **NEEDS `case O.AInt{n}: i(n)` — FORBIDDEN, §6** |
| bend lane, write site | `.agents/slop/graphcmp.bend:1519-1527` `g_mselect` | `O.UOp.mselect(O.Found.ar(cp), O.Found.i(cp), 0)` | unchanged (calls the port's constructor) |
| **PORT storage** | `tinybendygrad/uop/ops.bend:4586-4587` (was `:4567-4568`) `UOp.mselect` | `UOp.new(ar, OpsMSELECT{}, [self], ABlob{[k]}, TNone{})` | `… AInt{k} …` |
| **PORT renderer** | `tinybendygrad/uop/render.bend:727-728` `arg_repr` | `case O.ABlob{bs}: String.concat(["<bytes ", …, ">"])` | added `case O.AInt{i}: U32.show(i)` |

`ops.py` key (PIN, `git show 'ad117c928^:tinygrad/uop/ops.py'`): `:199` is
`ucache.get(key:=(op, src, arg, tag, type(arg)), …)` — `type(arg)` is the fifth element, so an `int`
`0` and a `bytes` `b""` are two keys. The port spells that fifth element by *variant*, so an int
needs a variant that is not `ABlob`.

---

## 3. WHY it was one byte — which CALLER forced the shape

`grep -n 'mselect\|MSelect' tinybendygrad/uop/ops.bend` gives every site; the arg is a bare `int` in
both constructors and was re-typed to `ABlob` because **`ABlob`'s payload is `List<&2, U32>` and a
`U32` `k` is a one-element list `[k]`** — the "one byte" is that one element.

* `ops.py:772` (PIN) `def mselect(self, arg:int) -> UOp: return UOp(Ops.MSELECT, src=(self,), arg=arg)`.
  The arg is **`int`**, always. There is no `bytes` mselect anywhere.
* The port's two call sites both pass a `U32`:
  * `ops.bend:4586-4587` `UOp.mselect(ar, self, k: U32)` — the wall's own constructor.
  * `ops.bend:7660` `UOp.copy_to_device.inp` → `case Some{j}: UOp.mselect(ar, self, j)` (`j: U32`).
* **The forcing caller is `UOp.mselect` itself**: there was no bare-`int` `Arg` variant, and the
  nearest existing one that held numbers was `ABlob` (a `List<U32>`), so `[k]` was the only spelling
  available. The op is *not* the reason — `ops.py`'s arg is an int independent of the op — but the
  port's `Arg` vocabulary had no int, so the constructor reached for bytes.

The wall itself conceded the reuse was a **substitution** ("reusing it is the honest choice over
minting a new one"), and the substitution is exactly what the graph caught. Independent corroboration
that the port's `ABlob` here was also semantically wrong: `upat.bend`/`spec.bend` ask
`isinstance(x.arg, bytes)`; with `ABlob{[k]}` an `MSELECT` answered **`True`** where CPython answers
`False`. `AInt` fixes that too (§5).

---

## 4. The PIN's truth (not the worktree)

`git show 'ad117c928^:tinygrad/uop/ops.py'`:

* `:772` `def mselect(self, arg:int) -> UOp: return UOp(Ops.MSELECT, src=(self,), arg=arg)` — arg is
  `int`.
* `:765` `copy_to_device` — `inp = self if arg is None else UOp(Ops.MSELECT, src=(self,), arg=arg)` —
  the int flows straight from `copy_to_device`'s `arg`.
* Render site: **`argstr` does NOT branch on the type.** `UOp.__repr__` → `render.py` `pretty_print`
  → `x.argstr()` → `ops.py:272-274` `return repr(self.arg)` (except `REDUCE`). For an int that is
  `repr(0) == "0"`.
* **The type IS branched on elsewhere**: `ops.py:199`'s ucache key `(op, src, arg, tag, type(arg))`,
  and `device()` `:895-897` `self.src[0].device[self.arg]` (an int index), `buf_uop` `:927`
  `self.src[0].buf_uop.mselect(self.arg)`, `:985` `ret.bufs[self.arg]`. So upstream's int is USED as
  an int — indexing — not merely rendered. The port never uses it as an index (no `arg`-based
  indexing of an MSELECT), so re-typing it is safe.

---

## 5. Decision: a NEW `Arg` variant `AInt{i: U32}` — not a tagged union, not a render branch

Read against the file's own union vocabulary first (`grep` for the strategies `adevfix`/`awmma`
used):

* **`str|tuple`** (`ADev`, `AAllred.dev`, `ParamArg.device`) is a tagged union `S.Dev = D1{tag} |
  Dn{tags}` plus `Maybe<&2, S.Dev>` — solved by `adevfix`. **A second `str|tuple` is not the case
  here.**
* **`tuple|None`** (`AWmma.tc`) uses the existing `Maybe` — solved by `awmma`. **`int|bytes` is not
  an optional; it is a SUM of two present, different types, and there is no `Maybe` for it.**
* The file's own precedent for a **bare scalar as its own arm** is right here: `AFloat{f: F32}` is
  documented as "the one bare float". `AInt{i: U32}` is its twin and is equally literal.
* `str|tuple` in `ARange`/`AReduce` etc. is a marker of a *different* problem (shape, not value
  type) and is handled by `Arena.depth`.

So: **a new `Arg` variant.** A tagged union would be inventing a union for a value that needs none; a
render-time branch in `graphcmp.bend` would leave the PORT still lying (the ucache key and `isinstance`
tests would stay wrong) and is in a forbidden file anyway. The wall says "a NEW `Arg` arm" and it is
right.

**Applied edits (mine):**

| file:line | change |
|---|---|
| `ops.bend:1168-1176` (Arg table comment) | new `int → AInt` row, naming the wall and the measurement |
| `ops.bend:1214` | `AInt{i: U32}` added between `ABlob` and `AFloat` |
| `ops.bend:2092-2100` | new `eq_arg.AInt` (`U32.is_eq`) |
| `ops.bend:2160` | `eq_arg.sel` arm `case AInt{i}: eq_arg.AInt(y, i)` |
| `ops.bend:4575-4587` | `UOp.mselect` stores `AInt{k}`; the WALL comment rewritten to CLOSED |
| `ops.bend:7027` | the `s5.ga.arena` MSELECT fixture: `ABlob{BLOB_A()}` → `AInt{0}` (it was the last live example of the lie) |
| `render.bend:728` | `arg_repr` arm `case O.AInt{i}: U32.show(i)` (upstream `repr(int)`) |
| `upat.bend:418` | `arg_int` arm `case O.AInt{i}: Some{i}` — this is `isinstance(x.arg, int)`; the close is a real improvement, `AInt` is the only bare int (`ATuple{ys}`→`head1` stays the tuple approximation) |

`ops.bend`'s own `s5_mselect` row (`:7764`) is **unchanged**: `sg.ctor` has `case _: "other"` and both
`ABlob` and `AInt` fall to it, and `oracles/ops501-*.rows:76` reads `s5_mselect=Ops.MSELECT/Ops.BUFFER`
(op/src only). No oracle in `oracles/` pins the MSELECT arg representation.

---

## 6. The forbidden unblocker — the ONLY thing between this and a green row

Adding the `AInt` variant makes `argstr` in `graphcmp.bend` **non-exhaustive**, so the differ will not
build until this ONE arm lands. It is the smallest thing that unblocks the row, and it is in a file
this unit must not touch:

```bend
# .agents/slop/graphcmp.bend, beside case O.ABlob{bs}: blobstr(bs) at :465
case O.AInt{n}: i(n)
```

(`i` is the atom fn at `graphcmp.bend:73` `def i(x: U32) -> String: "i"+U32.show(x)`; bind `n`, not
`i`, or the arm shadows the function it calls.) **`graphcmp.py` needs NO change**: `carg` already
falls through to `_carg(int)` = `i0`. So the whole row is one forbidden line from `AGREE`.

Measured set of exhaustive `O.Arg`/`Arg` matches (by `grep 'case (O\.)?ABad{}'`, the last arm of any
exhaustive match): `ops.bend:eq_arg.sel` (mine, patched), `render.bend:arg_repr` (mine, patched),
`upat.bend:arg_int` (mine, patched), `graphcmp.bend:argstr` (**FORBIDDEN, unpatched**). Every other
`Arg` match in the tree has a `case _` wildcard (`fold.bend:binary_n.of`, `spec.bend:arg_blob`, …) and
is unbroken.

---

## 7. What ONLY `bend` settles — I could not run it

1. That `ops.bend` + `render.bend` + `upat.bend` **compile** with `AInt{i: U32}` as a `Data` field and
   its three arms. Every change is a pattern arm or a constructor; nothing static here compiles Bend.
   (And `graphcmp.bend` will compile only after §6's arm.)
2. That `graphcmp.bend diff --graph mselect` returns **`AGREE 9/9`**. The py lane is MEASURED to emit
   `i0`; the port now stores `AInt{0}`, and `i(0)` is static arithmetic to `"i0"` — so the *predicted*
   row is `arg=i0` on both sides. A normal-form change is about OUTPUT TEXT and only bend prints bend's
   bytes.
3. That the port's `s5_mselect` row still prints `MSELECT/… other t=none` (§5).

**The bend lane today is UNMEASURED, and the differ is build-broken without §6's arm.**

---

## 8. The denominator — `int|bytes` is N = 1, so the fix is the arm, not a helper

Ambiguous-typed `Arg` variants, by the task's two shapes, over the 21 variants now in
`ops.bend:1181-1205`:

* **`int` OR `bytes`: `1` — `ABlob` (before this fix). It held `MSELECT`'s int *and* `BINARY`'s
  bytes.** Rendered by ONE non-branching helper, `blobstr` (`.agents/slop/graphcmp.bend:392`), which
  always emits `y n(…)`. **N = 1 ⇒ the fix is THIS variant, not a shared-helper retune.** After the
  fix `ABlob` is pure `bytes` and `AInt` is pure `int`: N = 0 for int|bytes.
* **`str` OR `tuple`: `3` sites — `ADev.dev`, `AAllred.dev`, `ParamArg.device`.** All rendered through
  the tagged union `S.Dev = D1|Dn` (branching in `dev`/`devs`), per `adevfix`. They are NOT a single
  non-branching helper and NOT the same defect.
* A THIRD ambiguous case exists and is **out of this unit's scope**: `ATuple{ys: List<U32>}` also
  carries `FLIP`'s `tuple[bool,…]` (`ops.bend:1150-1159`), and is rendered by the single
  non-branching `us` (`graphcmp.bend:176`). Its trigger has not fired in the corpus.

So: the "int OR bytes, str OR tuple" population is **N(int|bytes) = 1, N(str|tuple) = 3**, and only
the first is the single-non-branching-helper shape — hence the arm/variant, as the wall prescribed.

---

## 9. Artifacts / md5s (post-edit)

```
tinybendygrad/uop/ops.bend      006b9cfbc1282f28abd9e199ad86d6f2
tinybendygrad/uop/render.bend   2db0f1807e595e72d64df6a446499753
tinybendygrad/uop/upat.bend     be8ed81536d86ddbd7cc458103da32a5
```

`git status --porcelain` shows exactly those three modified. The evidence row is
`runs/graphcmp/D/D1-graph-mselect.txt` (`arg py=i0 bend=y n(i0)`, `VERDICT: DISAGREE`, `rc=1`) —
**stale until §6 lands and `bend` re-runs**.
