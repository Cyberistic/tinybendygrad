# Verdict Hunt — Bend soundness bounty ($10k)

**STATUS: NO BOUNTY WIN.** No candidate file satisfies the win condition (1)
`bin/bend C.bend --verdict` exits 0 and prints `ALL PROOFS CHECK`, **and** (2) `C.bend`
contains a **live** proof of `Empty`, without `unsafe`/FFI.

**The single closest result found is `c10_ctxdead.bend` (§6): a Bend file whose
`--verdict` PASSES and which, in the BendTT the kernel actually reads, contains a
**live kernel term of type `Empty`**. It is NOT a bounty win, because the region that
holds it is unreachable in Bend's own checker (`ctx_dead`), so the produced `Empty` is
never a value of the running program. It IS a checker/kernel synchronisation finding of
the same family as upstream issue #1182, in the *opposite* direction: here the kernel is
the **permissive** side, and the translator emits a live inhabitant of an empty type in
a region bend2 calls dead.

Started 2026-10-22T15:36Z. Scratch: `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/verdicthunt/`.
All measurements below name a command and a receipt under `receipts/`.

---

## 1. Measurements

### M1 — first measurement: `bin/bend --version` and `references/bend` HEAD

`bin/bend` has **no `--version` flag** (`bend: unknown option --version`). The version
comes from `bend --help`:

```
$ ./bin/bend --help | head -1
Bend 2.0.37: check, run, build and publish Bend programs.
$ ./bin/bend --help | tail -1
bend 2.0.38 is available: run bend update
```

`references/bend` HEAD — **grafted (shallow) clone**:

```
$ env -u GIT_INDEX_FILE git -C references/bend log -1 --format='%H %ci %d'
4ff8545f19b09b7d2b8ca2303668100eac8efd66 2026-10-13 07:12:29 -0300  (grafted, HEAD, tag: v2.0.37)
$ env -u GIT_INDEX_FILE git -C references/bend describe --tags
v2.0.37
```

**REVISION MEASURED: `v2.0.37` / `4ff8545f19b09b7d2b8ca2303668100eac8efd66`, 2026-10-13.**
The prior art (`references/bend-verdict-investigation/`) measured `v2.0.32` / `573002f0`.

### M2 — the kernel builds and runs at this revision

`safe.ts:157` pins `LEAN_VERSION = "4.34.0"`; `kernel_bin()` (`safe.ts:1483`) **refuses**
any other Lean (`lean --version` must match exactly) and honours `$BENDTT`. The machine
had only 4.35.0 / 4.36.0-rc1, so Lean 4.34.0 was installed with elan and the kernel was
built **in my own temp dir** (the shared `~/.bend/bendtt` cache was left alone):

```
$ export PATH="$HOME/.elan/toolchains/leanprover--lean4---v4.34.0/bin:$PATH"
$ lean -c bendtt.c bendtt.lean && leanc -O3 -DNDEBUG bendtt.c -o bendtt
$ ./bendtt
usage: bendtt <file.bendtt>
```

Every run below sets `BENDTT=<my kernel>`. Harness: `run.sh <file.bend>` runs
`--check-only` and `--verdict` and captures both streams + exit codes into
`receipts/<name>/{check,verdict}.{out,err,rc}`.

---

## 2. Q2 — what `--verdict` checks. **THE TRANSLATION IS NOT FAITHFULNESS-CHECKED.**

`bend2/main.ts:808` `cli_verdict(book, kernel)`:

```ts
const bad = book_promises(book);            // main.ts:830
if (bad.length !== 0) { ...FAIL... return 1; }
if (kernel && !Safe.safe_check(book)) { ...FAIL / MISMATCH... return 1; }
cli_say(1, PASS + "\n" + (kernel ? "" : HINT + "\n"));
```

`Safe.safe_check` (`safe.ts:1570`) is exactly:

```ts
export function safe_check(book: Book): boolean {
  const got = safe_book(book);
  return got.oos.length === 0 && kernel_check(got.text);
}
```

* `safe_book` (`safe.ts:184`) is the **elaborator** — 1573 lines that turn bend2's
  *checked* book into BendTT **text** (`bend2/safe.ts`, "the elaborator from a checked
  book to BendTT text", per `references/bend/AGENTS.md`).
* `kernel_check` (`safe.ts:1541`) runs the Lean kernel on that text and demands stdout
  be exactly `ALL PROOFS CHECK`.
* **There is no second checker that compares the BendTT term against the bend2 term.**
  `bendtt.lean:1-13` says the kernel "trusts none of it" — the elaborator's fidelity is
  an *assumption*, never a checked obligation.

⇒ **The hole class is `safe.ts`: every place it can drop a hypothesis, weaken a type,
erase a proof, or map a type to a strictly stronger one.** #1182 lives there.

---

## 3. Q4 — the "lane lies" class: `--verdict` **REFUSES** what it does not cover

`book_promises` (`main.ts:830-861`) walks every def **outside Base**
(`book.tlds[k].b !== true`) and fails the verdict when the def is `@unsafe`
(`t.u === true`) or **foreign** (`t.i !== undefined && t.b !== true`), then floods the
failure back along "who names whom" edges (`term_refs`, `main.ts:864`).

⇒ **A file using `unsafe` or FFI is REFUSED (exit 1), not silently accepted.** The
"lane prints a verdict it did not measure" hole does **not** exist for `unsafe`/FFI.

**But Q4's second half is open**: `safe.ts`'s *own* carve-out is different. `safe.ts:44-45`:
"What the kernel cannot express is out of scope: it goes, with every def that names it,
and `--verdict` fails." — i.e. out-of-scope items are **dropped together with every def
that names them** and the verdict fails. That is a refusal, not a silent pass. **No
unmarked second path to the `unsafe`/FFI capability was found in `safe.ts` or `main.ts`.**

---

## 4. Q1 — the Lean proof of BendTT: where it is, and is it closed?

`references/bend/bend2/bendtt.lean` — **3895 lines / 172 753 B** — is the whole kernel
*and* its claims *and* their proofs, in three parts (its own header, lines 8-13:
"1. THEORY … 2. CLAIMS … 3. PROOF").

### M3 — trust base

```
$ grep -n -E '\b(sorry|admit|native_decide|unsafe|partial def|implemented_by|axiom|opaque)\b' bend2/bendtt.lean
```

* **NO `sorry`, NO `admit`, NO `axiom`, NO `native_decide`, NO `unsafe`, NO
  `@[implemented_by]`.** The 16 hits are all `partial def` **in the .bendtt text
  parser** (`Parse.gap/at/span`, `Term.parse*`, `Book.parse_defs`, lines 594-845) plus
  the word "opaque" in prose about opaque defs.
* ⇒ **Q1's answer so far: the Lean file has no admitted axiom and no
  `native_decide`. The trust base is: the Lean 4.34.0 compiler + the C compiler behind
  `leanc -O3`. The `partial def`s are confined to the *parser* of the .bendtt text
  (see §7 for why that is still inside the trust base).**

### M4 — what the kernel claims (the thing a bounty would break)

`bendtt.lean:1659-1693`:

```lean
def Claim.consistent : Prop :=
  ∀ bk k d, Book.check bk = .ok () → Book.get bk k = some d →
    ¬ Conv bk d.T (Enu [])                      -- no def has type Empty
def Claim.sound    := ∀ bk, Book.check bk = .ok () → Book.WellTyped bk ∧ Book.Live bk
def Claim.sr       := ... subject reduction ...
def Claim.progress := ...
def Claim.halts    := ...
def Claim.empty    := ∀ bk t, Book.WellTyped bk → Value bk t → ¬ Typed bk [] t (Enu [])
```

All six are **proved** (no `sorry`): `confluent` (1940), `book_check`/`sound` (2416),
`sr` (2497), `progress` (2815), `empty` (2856), `halts` (3876), `consistent` (3886).

`bendtt.lean:1402` `Def.check` — what is checked per def:

```lean
let ck := if d.o then ls.2 else ls.1          -- opaque: checked with all defs transparent
Res.need (Book.index bk d.k == some i) "a fresh name"
Term.check ck FUEL [] d.T T1                    -- the type is a kind
Term.check ck FUEL [] d.v d.T                    -- the body at the declared type
Res.need (Term.ren Nat.succ d.v == d.v) "a closed def"     -- the body is CLOSED
let g : Guard := ⟨bk, i, [], [], []⟩
Res.need (Term.tree g [] d.v) "affine live code, calls that descend"
```

**Note `[]`: a def's body must be closed.** And note the *type* is checked against the
kind `T1 = Typ (Lab "Q1")` while the *body* is checked against the declared type.

### M5 — the proof of `Claim.consistent` (3886-3895) and why it is sound

```lean
theorem consistent : Claim.consistent := by
  intro bk k d ok get hc
  have ⟨wt, lv⟩ := book_check bk ok
  have ⟨i, hi⟩ := index_of_get get
  suffices ∀ t, Acc (fun u t => Eval bk t u) t → ¬ Typed bk [] t (Enu []) from
    this _ (halts bk _ lv (fun _ => rfl) (by
      simp [Term.Live, Term.live, Term.called, Term.unspine, hi, index_lt hi]))
      (.conv (.ref get) (.conv (conv_sub (σ := Var) hc)))
  intro t a ht; induction a; rename_i t _ ih
  exact (progress bk t _ wt lv ht).elim (empty bk t wt · ht) fun ⟨u, e⟩ => ih u e (pars_sr wt ht (eval_pars lv.1 e))
```

The argument: if `d.T` converts to `<>`, then `Ref k` (whose type **is** `d.T`) is typed
at `<>`; `Ref k` is closed and live (at the *book* level `Term.Live bk t` uses
`g.self = bk.length`, so `Term.called` is true because `index_lt hi : j < bk.length`);
therefore it reaches a value, which by `sr` is still typed at `<>`, contradicting
`Claim.empty`. **This uses only `d.T`, never `d.v`.** I could not break it.

### M6 — the encoding of "Empty" in the kernel (IMPORTANT)

Bend's `Empty` is a **datatype with no constructors**. `safe.ts:adt_emit` (380-399)
emits it as

```
Empty.arms : ∀x0 : <> -> *(.Q2) = λ{}
Empty       : *(.Q2)         = Σx0 : <> -> (Empty.arms x0)
Empty.efq   : ∀x0 : Empty -> <> = λ{(,): λ{}}
```

So **in the kernel a Bend `Empty` is a `Σ` whose domain is the empty enum `<>`, not
`<>` itself.** Two consequences, both measured:

* `Claim.consistent` forbids a def whose type **converts to `<>`**. A Bend def of type
  `Empty` has kernel type `Σx0 : <> -> (Empty.arms x0)` — a `Sig`, which does **not**
  convert to `<>` (`Term.conv`'s `Term.parts` has no `Sig`/`Enu` case, so `conv` is
  false). ⇒ **the kernel's main claim does not, literally, cover a Bend `Empty`.**
* No closed value of type `<>` (hence none of type `Empty`) exists: the tag of an
  `Empty` value must have type `<>`, and the only source of `<>` is
  `D.efq : D -> <>`, which needs a `D`. **Confirmed by hand-written BendTT (§5).**

---

## 5. Hand-written BendTT experiments (the kernel, directly)

`$W/kt/*.bendtt` run through the kernel built from this revision's `bendtt.lean`:

| file | content | kernel verdict |
|---|---|---|
| `k1_selfref.bendtt` | `bad : <> = bad` | **SOME PROOFS FAIL** — "affine live code, calls that descend" |
| `k2_efq_at_empty.bendtt` | `bad : <> = λ{}` | SOME PROOFS FAIL — "expected: a function type" |
| `k3_efq_shape.bendtt` | `Empty.arms`/`Empty` + `bad : ∀x0 : Empty -> <> = λ{(,): λ{}}` | **ALL PROOFS CHECK** |
| `k4_empty_sig.bendtt` | `bad : Empty = λ{(,): λ{}}` | SOME PROOFS FAIL — "expected: a function type" |

⇒ the kernel accepts `Prj(Efq) : ∀x0 : Empty -> P` for **any** `P`, but a body at the
`Sig` type `Empty` must be a `Tup` whose tag has type `<>` — so a closed `Empty` value
is impossible. This is consistent with `Claim.consistent` + `Claim.empty`.

---

## 6. FINDING 1 — a `--verdict`-PASSING file with a **live kernel inhabitant of `Empty`**

`cand/c10_ctxdead.bend`:

```bend
import Base

type D is Data:
  C0{}
  C1{}

def bad(e: Empty, d: D, d2: D) -> Empty:
  match d:
    case C0{}:
      match d2:
    case C1{}:
      match d2:
```

Measured (`receipts/c10_ctxdead/`):

```
check-only : rc=0 | ALL PROOFS CHECK
verdict    : rc=0 | ALL PROOFS CHECK
```

The BendTT the kernel actually reads (`-o c10_ctxdead.bendtt`):

```
bad : ∀x0 : Empty -> ∀x1 : D -> ∀x2 : D -> Empty =
  λ+x0 => λ{(,): λ{.C0: λ{(): λ{(,): λx1 => λx2 => (λ{(,): λ{}} x0)}; λ{}};
                λ{.C1: λ{(): λ{(,): λx1 => λx2 => (λ{(,): λ{}} x0)}; λ{}}; λ{}}}}
```

**`(λ{(,): λ{}} x0)` is `Prj(Efq) x0`, and `Prj(Efq) : ∀x0 : Empty -> P` for ANY `P`
(§5, k3).** The kernel therefore holds a **live** (q=1 arguments) term of type `Empty`
and accepts the book.

### Root cause, named

* `bend.ts:3626-3631` (bend2's checker) allows an **empty match** `match x:` with no
  cases when `rem.length === 0` **or** `ctx_dead(book, ctx)`:
  ```ts
  case "Efq": {
    if (rem.length !== 0 && !ctx_dead(book, ctx)) { throw Err(...); }
    return Check(tm, ty, uses_nil());
  }
  ```
* `bend.ts:842-853` `ctx_dead` is true when **some live binder in the context has an
  emptied-ADT type** (here `e : Empty`).
* `safe.ts:746-758` `swi`'s `Efq` case:
  ```ts
  case "Efq": {
    if (all === null || no_ctr(e, all.A) || s.empty.length === 0) { return { $: "Efq" }; }
    const q = quant(all.q);
    const f = convoy_bind(e, scope_hide(scope_hide(s)), cv, (s2: Scope) => s2.empty[0], fs);
    return { $: "Lam", q, l: s.D, f: { $: "Lam", q, l: s.D + 1, f } };
  }
  ```
  `s.empty` is the list of "live variables of an empty type" (`safe.ts:104-105`),
  populated at `safe.ts:682-684` (a λ whose domain `no_ctr`) and `safe.ts:780-781`
  (a default arm whose scrutinee type `no_ctr`).
* ⇒ **The two sides disagree about what "the scrutinee's type is empty" means.**
  bend2 uses `ctx_dead` = *any live binder in the context has an emptied-ADT type*;
  `safe.ts` uses `no_ctr` = *the scrutinee's own type has no constructors left*
  (`safe.ts:867-872`, which filters by the ADT's `r` list — the same list `bend.ts`'s
  `book_adt` filters by, `bend.ts:882-892`, so the two agree on that predicate) **and**
  requires `s.empty` to be non-empty.
* ⇒ **The consequence:** bend2 accepts an empty match on a *non-empty* scrutinee
  (`d2 : D`) because the *context* is dead (`e : Empty`), and `safe.ts` — which has no
  notion of `ctx_dead` — answers that match with the `s.empty` branch, i.e. with a
  **live value of an arbitrary type `P`**, here `P = Empty`.

### Why this is NOT the bounty

The region is unreachable in Bend's own checker (`ctx_dead`), so the `Empty` is never a
value of a running program, and the def's type is a **function** `Empty -> … -> Empty`,
not `Empty`. The task's win condition explicitly excludes "an unreachable branch".
**But it is a genuine checker/kernel synchronisation divergence, and it is the *opposite*
direction from #1182: here the kernel is the permissive side.**

### The hole this opens, and why it is still closed

The `s.empty` branch needs a *live* empty-typed variable in scope, and every such
variable is uninhabited, so the region is always dead:
* `safe.ts:682` — the source is a **λ binder** ⇒ the def has a parameter ⇒ the def's
  type is a function type.
* `safe.ts:780` — the source is a **default arm**; but that entry is only added when
  `no_ctr(all.A)` is true, i.e. the match is already exhausted, in which case
  `safe.ts:766-767` (`dead`) replaces the continuation by `Efq` and the default arm is
  never emitted. ⇒ unreachable.
* `bend.ts:842` `ctx_dead` ⇒ the region is unreachable ⇒ bend2 would never have
  accepted the empty match without it.

⇒ **No closed `Empty` value can be produced through this route.**

---

## 7. Q3 — issue #1182 at OUR revision, and its root cause

### M7 — re-measurement of the prior art's probes at `v2.0.37`

`receipts/prior/*` (all five probes from `references/bend-verdict-investigation/probes/`):

| probe | `--check-only` | `--verdict` |
|---|---|---|
| `higher_evidence_base.bend` | rc=0 ALL PROOFS CHECK | **rc=1 MISMATCH** |
| `dependent_empty_result_probe.bend` | rc=0 ALL PROOFS CHECK | **rc=1 MISMATCH** |
| `law_higher_evidence_probe.bend` | rc=0 ALL PROOFS CHECK | **rc=1 MISMATCH** |
| `specialized_dependent_param_probe.bend` | rc=0 ALL PROOFS CHECK | rc=0 ALL PROOFS CHECK |
| `runtime_kind_empty_probe.bend` | rc=1 (bend2 rejects: "a live scrutinee") | rc=1 (same) |

⇒ **#1182 is NOT fixed at `v2.0.37`.** The divergence is unchanged: bend2 accepts,
BendTT rejects ⇒ **a safety win, not the bounty.** The prior art's conclusion stands:
"BendTT rejects it."

### Root cause, named

The probe's shape is a `~` (template / compile-time) parameter whose *result* type
contains a dependent equality:

```bend
def use(~F: @a: N -> @b: N -> {S{a} == S{b} : N} -> {a == b : N}, a: N, b: N,
          e: {S{a} == S{b} : N}) -> {a == b : N}:
  F(a, b, e)
```

`safe.ts:1191-1209` `arm()` is where a `~` parameter's *value* is manufactured:

```ts
si = v !== null ? scope_bind(si, { $: "Efq" }, F.A, false, v)
                : scope_bind(si, vs[j++][1], F.A, false);
```

**A specialized (`~`) parameter is bound to the kernel term `{ $: "Efq" }` — the empty
eliminator.** The kernel's `Efq` rule (`bendtt.lean:1207-1213`) accepts it **only** at
`∀q s:<> -> P`:

```lean
| _ + 1, c, Efq, T => match Ctx.wnf ck c T with
  | All q D _ => match Ctx.wnf ck c D with
    | Enu [] => Res.need (Quan.live q) "a live scrutinee"
    | D      => Ctx.fail c "an empty enum" D
  | T => Ctx.fail c "a function type" T
```

⇒ **A `~` parameter whose Bend type is not a function over the empty enum cannot be
represented**, and the kernel rejects the book while bend2 accepted it. `#1182`'s
dependent-equality result is such a type (`{a == b : N}` is an `Eql`, not an `All`).

### The sibling hunt (the prize is the sibling where the divergence points the other way)

The `~`-parameter mechanism has exactly two possible outcomes, and I checked the
permissive one:

* **`~F : ∀q s:<> -> P`** — the kernel accepts `Efq` there, and `Efq`'s value is
  "an `P`". In **Bend** no type maps to `∀q s:<> -> P`: a Bend *empty datatype* maps to
  the **`Sig`** `Σx0 : <> -> (D.arms x0)`, not to the enum `<>`. So `check (Efq) F.A`
  fails with "an empty enum" ⇒ mismatch ⇒ kernel stricter. **No permissive sibling
  here.**
* **`~F : {a == b : N}`** (an `Eql`) — the kernel cannot use `Efq` at all ⇒ mismatch.
* The *translator's* permissive sibling is exactly **Finding 1** (§6): the `s.empty`
  branch, where the translator invents a **live** value of an arbitrary type in a
  region bend2 calls dead. **Found.**

⇒ **No sibling was found in which the kernel accepts something bend2 rejects.**

---

## 8. What the kernel does *not* cover (still open, and where the next hour should go)

1. **`partial def` in the .bendtt parser** (`bendtt.lean:594-845`) is inside the trust
   base: `kernel_check` feeds the elaborator's text to a parser whose `Parse.gap`,
   `Parse.at`, `Parse.span` are `partial def`. A text that makes the parser diverge or
   run out of fuel would be parsed into *some* term, and the checker would then judge
   that term. **Not yet tested** — this is the highest-value untested hole, because the
   parser is the one place where the kernel's "the kernel trusts none of it" is not
   backed by a proof (the kernel's own claims are about `Book.check` on a *parsed*
   book, so a mis-parse is outside every claim).
2. **`Term.fits`'s subsumption** (`bendtt.lean:1018-1029`): `Enu ks` fits `Enu js` when
   `ks ⊆ js` (so `<>` fits **every** enum), and `Term.qge` (1000-1013) makes
   `Typ g` fit `Typ h` whenever `g == Q2` or `h == Q0`/`Q1`. The translator's
   counterpart is `bend.ts`'s `term_compare "LE"`. **A divergence here would be
   permissive.**
3. **`safe.ts`'s model search** (`model_at`, 489-538) manufactures the body of every
   **unfilled law** (a bodiless def becomes an *opaque* def at a model,
   `safe.ts:41-43`, `def_emit` 371-377). `model_at`'s `ADT` case returns `hyp()` — a
   *hypothesis* — when the datatype has no constructors; and its `Eql` case returns
   `{==}` when the two sides merely **convert**. **A model of the wrong type would be
   accepted by the kernel if it merely `fits`.** This is the most promising remaining
   translator hole, because the model is the one part of the book the kernel *cannot*
   cross-check against bend2 (there is no bend2 body to compare with).
4. **`safe.ts`'s `q` upgrades** (`tree` 687-697): a q=1 binder used twice is upgraded
   to **q=2**, and the kernel's `Quan.allows Q2 n = true` permits *any* number of
   uses. The upgrade is guarded by `kind(e, s, all.A) === 1` (i.e. the domain is
   Type-kinded, not Data) with a `rebuild` fallback; when `kind` returns **null**
   (unknown kind) the upgrade happens anyway. The kernel then re-checks the domain
   against `T2` (Data) and would reject a non-Data domain ⇒ kernel stricter. **Not
   yet tested with a null-kind domain.**

---

## 9. Discipline / what was *not* done

* No `unsafe`, no FFI, no `--verdict`-accepted file was claimed as a submission.
* `checks/differ.py`, `gates/*`, `checks/e2e*`, `checks/sweep.py`, `checks/bounded.py`,
  `checks/port-compile-gate.py`, `pytest`, `mypy`, `ruff` were **not** run (forbidden).
* No git command mutated anything; nothing was committed; `references/` was not edited
  (the kernel was built in a temp dir).
* One bend process at a time.

---

## Log

- 2026-10-22T15:36Z — report created; `bendtt.lean` located.
- 2026-10-22T15:40Z — M1: revision `v2.0.37` / `4ff8545f19b09b7d2b8ca2303668100eac8efd66`.
- 2026-10-22T15:45Z — M2: Lean 4.34.0 installed; kernel built in my temp dir; `BENDTT=` works.
- 2026-10-22T15:52Z — Q2 answered: the translation is not faithfulness-checked.
- 2026-10-22T15:58Z — Q1 first reading: no `sorry`/`axiom`/`native_decide` in `bendtt.lean`.
- 2026-10-22T16:10Z — M7: #1182 reproduced at `v2.0.37` (unfixed, kernel stricter).
- 2026-10-22T16:25Z — §5: hand-written BendTT: `Prj(Efq) : ∀x0 : Empty -> P` for any `P`.
- 2026-10-22T16:40Z — **Finding 1** (`c10_ctxdead`): `--verdict` PASSES with a live
  kernel inhabitant of `Empty`; root cause named (`bend.ts:842 ctx_dead` vs
  `safe.ts:746-758 swi`/`s.empty`).
