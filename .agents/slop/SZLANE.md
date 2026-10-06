# SZLANE — `runtime/sz.c`'s bare registrations, and the two CID symbols

**Owner:** this unit. **Files owned:** `tinybendygrad/runtime/sz.c`. **Nothing committed.**
**Tool:** Bend 2.0.34 (`bin/bend`), `Apple clang 21.0.0`. Rule prefix `SZ-`.
**Verdict, in one line:** both defects are **LIVE, not latent**, they are **one failure**,
and the `CID_NIL`/`CID_CON` half of the report was a **false red whose real cause is the same
demand-allocation fact as the first half** — the names are right, the *guarding* was wrong.

Everything below is reproduced by the three probes in this directory.

---

## 1. What bend emits for a `CID` used OUTSIDE an `#ifdef` — MEASURED

**`CID(x)` is NOT a macro. It is a TEXTUAL SUBSTITUTION performed by bend at emit time.**

`./bin/bend tinybendygrad/sz.bend -o sz_full.c` → **rc 0**, 119,075 lines. In that emit:

| measurement | value |
|---|---|
| occurrences of the literal text `CID(` | **0** |
| `CID(Sz.read_dir)` became | `CID_SZ_READ_DIR` (bare identifier) |
| `CID(Sz.is_dir)` became | `CID_SZ_IS_DIR` |
| `CID(Nil)` / `CID(Con)` became | `CID_NIL` / `CID_CON` |
| `#ifdef CID(X)` became | `#ifdef CID_X` — an ordinary C `#ifdef` on a real object-like macro |

The mangled name is **path-dependent**: the same effect is `CID_SZ_READ_DIR` when `sz.bend`
is the root file, and `CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR` when it is imported from
`.agents/slop/szlane/probe-isdir.bend`. **Never hard-code an id; always write `CID(...)`.**
This is why `dtype.c`'s guards work: bend substitutes *inside* the directive too, so the
preprocessor only ever sees `#ifdef CID_SOME_ID`.

**Is the unguarded form safe? NO.** `cc -fsyntax-only` on the emit of a build that reaches
only `Sz.is_dir`:

```
emit-isdir.c:2981:23: error: use of undeclared identifier 'CID_NIL'
emit-isdir.c:2983:22: error: use of undeclared identifier 'CID_CON'
emit-isdir.c:3001:10: error: use of undeclared identifier
    'CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR';
    did you mean 'WL_FID__________TINYBENDYGRAD_SZ_SZ_IS_DIR'?
```

**THE CAUSAL FACT, STATED ONCE: bend allocates effect AND constructor ids ON DEMAND.** A
build that never reaches an effect never `#define`s its id; a build that never mentions
`Nil`/`Con` in bend never `#define`s `CID_NIL`/`CID_CON`. Preambles measured: 51 `#define
CID_*` for `sz.bend`, **15** for `probe-isdir.bend`, **14** for `probe-none.bend`.

---

## 2. The fix — `dtype.c`'s idiom, wrapped around the GROUP, not the call

`runtime/sz.c` now carries **2** guards, one per effect: `#ifdef CID(Sz.read_dir)` around
lines 26–90 and `#ifdef CID(Sz.is_dir)` around lines 92–119.

**Count: 2 registrations wrapped** — `io_eff(CID(Sz.read_dir), sz_read_dir_run, 0)` and
`io_eff(CID(Sz.is_dir), sz_is_dir_run, 0)`. There are no other registrations in the file.

**Why the GROUP and not just the `io_eff`, which is a difference from `dtype.c` and is
forced, not chosen:** `sz_read_dir_pack` names `CID(Nil)` and `CID(Con)`, which are
demand-allocated exactly like an effect id, and `sz_read_dir_run` calls that packer. Guard
only the constructor and a guarded-out effect leaves an *undeclared function* behind it — the
same failure, one step later. So the unit that goes inside a guard is **the C group that
implements one effect**.

**The mirror direction is also live, and was measured before fixing** (`probe-readdir.bend`
reaches `Sz.read_dir` alone): `CID__________TINYBENDYGRAD_SZ_SZ_IS_DIR` undeclared, cc rc 1.
A fix that guarded only the registration the first probe happened to catch would have left
that one broken.

---

## 3. `CID_NIL`/`CID_CON` vs `CID_SNIL`/`CID_SCON` — settled by what is emitted

**BOTH PAIRS ARE DEFINED. They are different ids for different types, and `sz.c` is right.**

| bend name | id | type | in `sz.bend`'s preamble? |
|---|---|---|---|
| `CID_SNIL` / `CID_SCON` | 1 / 2 | **String** nil / cons | yes |
| `CID_NIL` / `CID_CON` | 13 / 14 | **List** nil / cons | yes |

`Sz.read_dir` returns `List<String>`, and `sz_read_dir_pack` builds a **List**, so
`CID(Nil)`/`CID(Con)` is the correct pair. The emitter's own code agrees: it destructures
lists with `term_aux(v) == CID_NIL` and `ctr_take(e, v, 2, …)`, and builds them with
`term_ctr(CID_CON, nd)`; `CID_SCON` is used for the **empty String** (`STAT_OFF`).

**So the reported "naming mismatch" is a false red, and the brief's reason for it is wrong.**
`CID_NIL`/`CID_CON` are not missing because the preamble "spells them `CID_SNIL`/`CID_SCON`"
— it spells *both*. They went undefined in the isolated build for the **same
demand-allocation reason** as the effect ids: nothing in that build mentions `Nil`/`Con`.

Renaming them to `CID_SNIL`/`CID_SCON` would have been a **semantic change** — building a
String where `IO(List<String>)` is declared. Nothing was renamed. **No defensive `#define`
was added for either spelling**, for the reason the brief gives and that this tree
demonstrates: there are already three live spellings of a 64-bit value (`dtype.js`'s two
halves, `dtype.c`'s flat frame, and the header's unstated order).

**CONFIRMED IN THE JS LANE TOO, WHICH SETTLES IT TWICE.** `bend -o out.js` for the same
probe emits `sz_read_dir` as:

```js
return { $: "Nil" };                                     // CID(Nil)
xs = { $: "Con", head: names[i - 1], tail: xs };         // CID(Con)
io_eff("../../../tinybendygrad/sz.Sz.read_dir", sz_read_dir);   // CID(Sz.read_dir)
```

Both lanes agree: `Nil`/`Con` are the **List** pair, `SNil`/`SCon` the **String** pair, and
`WNil`/`WCon` a third (a WeakList — which is why the tree has *three* `…Nil`/`…Con`
spellings and why `rg 'CID_.*NIL'` is not a way to count them).

### 3b. THE `#ifdef CID(…)` IDIOM IS **C-LANE ONLY**, AND THE `.js` FILES ARE NOT THE SAME DEFECT

A tree-wide sweep of every `io_eff(CID(…))` site:

| file | registrations | guarded? |
|---|---|---|
| `tinybendygrad/runtime/dtype.c` | 10 | yes |
| `tinybendygrad/runtime/sz.c` | 2 | **yes (this fix)** |
| `tinybendygrad/runtime/dtype.js` | 10 | no |
| `tinybendygrad/runtime/sz.js` | 2 | no |
| `tinybendygrad/runtime/support/nv/nvdev.bend` | 1 | no |

**The two `.c` files are now the only guarded ones and both are correct. The `.js` files are
NOT the same defect, and must not be "consistently" fixed**, because the JS emit has **no
conditional-compilation mechanism at all** — measured, **0** occurrences of `ifdef` or
`defined(`. There, `CID(x)` becomes a **string key**, and the registration key is byte-identical
to the call-site key, so an unreached registration is a harmless unused table entry rather
than an undefined identifier. **`#ifdef` in a `.js` file would be a syntax error.** The
mechanisms differ:

| | C lane | JS lane |
|---|---|---|
| `CID(x)` becomes | an integer macro, `#define`d **on demand** | a **string key**, always defined |
| unreached effect | **undeclared identifier → build fails** | an unused table entry → harmless |
| guard available | yes (`#ifdef CID_X`) | **none** |

`nvdev.bend`'s single site is a `.bend` calling `io_eff` directly; **not mine, not measured,
reported not fixed.**

---

## 4. The gate — FOUR builds, all measured. Baseline is `BASELINE.md`.

`bend -o` returns **rc 0 in every case, before and after the fix** — it emits C and does not
compile it. **`bend -o` alone cannot see this class of defect at all.** The instrument is
`cc -fsyntax-only` on the emit, and `bend -o <binary>` (which invokes `cc` and `ld`).

| build | reaches | `bend -o` emit | `cc -fsyntax-only` **before** | **after** | registrations after |
|---|---|---|---|---|---|
| `probe-none.bend` | nothing | rc 0, 2,885 L | rc 0 | **rc 0** | **0** (sz.c is not pasted at all) |
| `probe-isdir.bend` | `Sz.is_dir` only | rc 0, 3,112 L | **rc 1** | **rc 0** | **1** — id 14, `Sz.is_dir` |
| `probe-readdir.bend` | `Sz.read_dir` only | rc 0, 3,168 L | **rc 1** | **rc 0** | **1** — id 16, `Sz.read_dir` |
| `sz.bend` | all of `sz.c` | rc 0, 119,097 L | rc 0 | **rc 0** | **2** — ids 44, 45 |

Registration counts are counted from `cc -E` output (the preprocessor has already resolved
every `#ifdef`), so they are the registrations that actually **land in the binary**, not
sites that merely exist in the source. **The isolated build registers exactly the one
effect whose seam it reached — 1, not 2 — which is the whole claim of the fix.**

**And the registrations still WORK**, which a compile-only gate would not have shown:

```
$ ./bin-isdir     SZLANE is_dir(.) = 1  [OK]
$ ./bin-readdir   SZLANE read_dir(.) = NONEMPTY  [OK]
$ ./bin-none      SZLANE reached-nothing: 0 registrations, 0 seams  [OK]
```

A guard that compiles but silently fails to register is the same silent non-registration the
brief warns about, so the runtime check is the load-bearing one.

**The fourth corner is a REAL BINARY, not just an emit.** `bend sz.bend -o bin-sz` → **rc 0**
(287 KB), which is the only `bend` invocation here that runs `cc` **and** `ld`. Run on a
4-file fixture it walks with **both** registrations live in one process, classifies `sub/` as
a directory via `Sz.is_dir`, enumerates it via `Sz.read_dir`, and skips the non-`.py`/`.js`
name:

```
Name                 Lines    Tokens/Line
-----------------  -------  -------------
tinygrad/a.py            2            3.5
tinygrad/b.js            2            3.0
tinygrad/sub/c.py        1            3.0

tinygrad                       :      4 in  2 files
tinygrad/sub                   :      1 in  1 files
```

(The compiled lane also clears the 28,988-byte interpreted-lane cliff recorded in `sz.bend`'s
own header. There is no upstream `sz.py` in this tree, so this row is **not** diffed against
CPython — stated rather than implied.)

---

## 5. Is the guard's `#define CID(x) 0` shim masking anything else? YES — and here is the exact list

**The shim does NOT blind the guard, and this is counter-intuitive enough to be worth the
measurement.** `#ifdef` does **not** macro-expand its operand: it tests whether the macro
*named* `CID` is defined. The shim defines it, so **every** `#ifdef CID(...)` is TRUE.

Measured, with a deliberate syntax error injected inside the guarded region:

| fragment | guard verdict |
|---|---|
| unguarded `sz.c` + error | **COLD**, `sz.c:16: use of undeclared identifier 'this'` |
| guarded `sz.c` + error | **COLD**, `sz.c:32: use of undeclared identifier 'this'` |

So the guard still sees every byte. That is the design intent its own comment states: the
shim can only add permissiveness, never turn a real syntax error green.

**What the shim DOES mask — three things, and only the first was previously named:**

1. **`TODO(GXR-11)`, the demand-allocation defect.** This is what it was written for, and it
   was **live in this tree**, not hypothetical. Now fixed in `sz.c`.
2. **Registration identity.** The shim rewrites *every* `CID(x)` to `0`, so
   `io_eff(0, f, 0)` in two different `.c` files is indistinguishable from two distinct
   effect ids. A file that registers an id **another file already registered** is invisible
   to this instrument. Named here; not fixed here (it is the guard's file, not mine).
3. **The id VALUE never matches.** The shim is correct only because the value is irrelevant
   to parsing. Any check that would care about the value is out of its remit by
   construction — which is exactly why the fix had to be a `bend -o` + `cc` gate and not a
   guard change.

**The blind spot is not `CID`. It is `bend -o`'s rc.** `bend -o` was **rc 0** for all four
builds including the two that did not compile. Any lane that reads `bend -o`'s exit status
as a build verdict is reading a number that cannot fail for this class of defect.

---

## 6. Bend facts this unit had to discover (costs an agent 20 minutes each otherwise)

- `do IO<T>:` takes **angle brackets**; a return type takes **parens** (`-> IO(U32)`).
  Mixing them is a parse error that points at the *next* line, not the wrong one.
- A `do`-block or `def` binding is **consumed once**. Read twice → prefix the name with `+`.
  This bites `.bend` local binders, not parameters.
- `List<&1, String>` is `read_dir`'s real level; `List.length(a, Kind, xs)` and
  `List.is_empty(a, Kind, xs)` are the list predicates.
- `bend -o <path>` with **no extension** builds and links a real binary — that is the only
  `bend` invocation in this unit that exercises `cc` **and** `ld`.
- Generated C ids are **numbered per build** and **mangled by import path**: `CID_SZ_IS_DIR`
  is 45 in `sz.bend`'s emit and `CID__________TINYBENDYGRAD_SZ_SZ_IS_DIR` is 14 in
  `probe-isdir.bend`'s. Nothing may depend on either.