# Verdict Hunt 2 — Bend soundness bounty ($10k), second pass

**STATUS: NO BOUNTY WIN.** No file `C.bend` was found such that
`bin/bend C.bend --verdict` exits 0 **and** the BendTT the kernel reads contains
a live, closed inhabitant of `Empty`. **The best near-miss is
`cand/f03_unreachable.bend`** (= the prior hunt's `c10_ctxdead.bend`): `--verdict`
PASSES (rc=0, `ALL PROOFS CHECK`) and the BendTT **does** contain a live kernel
term at type `Empty` — `(λ{(,): λ{}} x0)` — **but it is an application, not a
value; its argument `x0 : Empty` is uninhabited; and the def's declared type is
the FUNCTION type `Empty -> D -> D -> Empty`, not `Empty`.** That is why it is
not the bounty: a *proof of `Empty`* is a def of type `Empty`, and no candidate
reached that.

**Second FINDING, and it is a real one though not the type-theoretic prize:
`--verdict` IS DECIDED BY A BINARY OUTSIDE THE REPOSITORY.**
`safe.ts:1483-1494` reads the verifying kernel from
`~/.bend/bendtt/<hash>/bendtt` and, **if that file exists, executes it without
rebuilding or checking it against `bendtt.lean`.** Measured: with
`HOME=<temp>` and a two-line shell script in that path, the verdict **flipped
both ways** with nothing in the repository changed. **§3, Finding B.**

Second pass. The prior hunt (`../verdict-hunt/REPORT.md`, 459 lines) established
the shape of the problem and is my foundation. **I did not redo it.**

- **Revision measured:** `v2.0.37` / `4ff8545f19b09b7d2b8ca2303668100eac8efd66`,
  2026-10-13 (`references/bend` HEAD, grafted clone). Named in every claim below.
- **Started:** 2026-10-22T18:51Z. **This report was written from minute five and
  appended to as the work went.**
- **Scratch:** `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/verdicthunt2/`.
- **Artifacts:** `.agents/slop/verdict-hunt2/` — `REPORT.md`, `validate.py`,
  `run.sh`, `c12_probe.py`, `b3_fetch.py`, `cand/` (17 files), `receipts/`,
  `kernel/`.

### The kernel every claim below was measured against

`references/bend/bend2/bendtt.lean` sha256 `83cdd36e…d51be3`, built with **Lean
4.34.0** (the version `safe.ts:157` pins) into
`.agents/slop/verdict-hunt2/kernel/bendtt`, sha256 `989d9cf2…a613b`.
**That binary is byte-identical to the one the prior hunt built and to the one
cached in `~/.bend/bendtt/b9f3e0253abffb11/bendtt` on this machine** — so the
cache here is faithful and every comparison is like-for-like.

**A NOTE ON THE TEMP DIRECTORY:** the shared
`/private/var/folders/…/T/opencode/` was **wiped under me mid-session** (the
prior hunt's `kernel/` and mine both vanished). The kernel now lives in my own
artifact dir, which is stable. **⇒ A TOOL THAT LIVES ONLY IN A SHARED TEMP DIR
IS A TOOL THAT CAN VANISH.**

---

## 1. THE VALIDATOR — built first, and it goes red

`validate.py` is the rejector. It parses the BendTT the kernel reads with a
parser that mirrors `bendtt.lean`'s own `Term.parse*` (lines 676-836) —
including its Var/Ref rule (`Term.parse_name`: a name in the binder scope is a
`Var`, else a `Ref`) and its `parse_paren` rule (the quantity mark comes first,
so `(-a, b)` is a `Tup` and `(f x)` is an `App`).

It grades a candidate on five levels, weakest first:

| grade | meaning |
|---|---|
| `VERDICT-FAIL` | the verdict lane did not accept the book |
| `VERDICT-OK` | `--verdict` accepted it; **no proof of `Empty` found** |
| `TERM-OF-EMPTY` | a term at type `Empty` exists, but only inside a def of a **function** type |
| `DEF-OF-EMPTY` | a **def whose type IS `Empty`**: the kernel checked a term of type `Empty` against a declared type of `Empty` |
| `CLOSED-INHABITANT` | that def's body is a closed **value** (a `Tup`): the kernel accepted an actual inhabitant of `Empty` |

**Only `CLOSED-INHABITANT` is a bounty win.** The validator finds the empty
datatypes **structurally, not by name**: a def whose **body** is a `Σ` over the
empty enum `<>` (`Empty : *(.Q2) = Σx0 : <> -> (Empty.arms x0)`), so a
*different* type that happens to be called `Empty` is not the empty type.

### M1 — the validator rejects all four fakes

`cand/f01..f04`; receipts in `receipts/f0*/summary.rows`.

| fake | what it is | `--check-only` | `--verdict` | validator grade |
|---|---|---|---|---|
| `f01_comment_only.bend` | `Empty` only in a comment | rc=0 | rc=0 | **`VERDICT-OK`** (rejected as a proof) |
| `f02_different_empty.bend` | a **different** `Empty`, WITH a constructor | rc=0 | rc=0 | **`VERDICT-OK`** (`empty_datatypes=[]`) |
| `f03_unreachable.bend` | the prior hunt's `c10_ctxdead` | rc=0 | rc=0 | `TERM-OF-EMPTY` (a near miss, not a win) |
| `f04_no_proof.bend` | no `Empty` at all | rc=0 | rc=0 | **`VERDICT-OK`** |

**⇒ THE VALIDATOR GOES RED ON ALL FOUR. IT IS NOT A LABEL.**
`f02` needs care: Base's `Empty` cannot be redeclared (bend2 refuses with
"a fresh name (duplicate declaration: Empty)"), so the fake declares its own
`Empty` **without** importing Base, and the validator sees `empty_datatypes=[]`
and refuses to call it a proof.

**⇒ `--check-only` ACCEPTING IS NOT EVIDENCE.** All four fakes pass
`--check-only`; only `--verdict` was ever treated as acceptance, and the
validator's `CLOSED-INHABITANT` grade is the only thing that would have
counted as a win.

### M1.1 — the validator was itself caught crashing, and fixed

The first version crashed on `e06`'s book, because the tokenizer splits `==`
into two `=` tokens and `braced()` looked for a single `==`. **⇒ A VALIDATOR
THAT CRASHES IS NOT A VALIDATOR; the fix is in the file and every grade above
was re-taken after it.**

### M1.2 — the grades of every candidate, all current receipts

```
f01_comment_only         check=0 verdict=0  VERDICT-OK
f02_different_empty      check=0 verdict=0  VERDICT-OK
f03_unreachable          check=0 verdict=0  TERM-OF-EMPTY
f04_no_proof             check=0 verdict=0  VERDICT-OK
e01_law_empty            check=1 verdict=1  (bend2: "1 TODO found" — an open law)
e02_law_for_empty        check=1 verdict=1  (open law)
e03_law_exs_empty        check=1 verdict=1  (open law)
e04_law_two_for_empty    check=1 verdict=1  (open law)
e05_law_eql_empty        check=1 verdict=1  (open law)
e06_law_for_empty_eql    check=0 verdict=0  TERM-OF-EMPTY
h01_refute_empty         check=1 verdict=1  (bend2: "a match cannot scrutinize a computed value")
h02_neq                  check=1 verdict=1  (bend2: "expected: @_:{a == b : Nat} -> Empty")
h03_law_neq              check=1 verdict=1  (open law)
h04_neq_match            check=1 verdict=1  (bend2: cannot scrutinize a computed value)
h05_tmpl_empty           check=0 verdict=0  VERDICT-OK (defs=0 — the template went out of scope)
h06_c10                  check=0 verdict=0  TERM-OF-EMPTY
```

**⇒ NOT ONE CANDIDATE REACHED `DEF-OF-EMPTY`, LET ALONE `CLOSED-INHABITANT`.**

---

## 2. TARGET A — the `c10_ctxdead` hole, and the question it leaves open

### M2 — the prior hunt's `c10_ctxdead` re-measured at `v2.0.37`

`cand/f03_unreachable.bend`:

```
check-only : rc=0 | ALL PROOFS CHECK
verdict    : rc=0 | ALL PROOFS CHECK
GRADE: TERM-OF-EMPTY
  defs=6 empty_datatypes=['Empty']
  NEARMISS-PRJ-EFQ: bad has 2 App(Prj(Efq),_) and 2 bare Prj(Efq) term(s)
```

The BendTT the kernel read (`receipts/f03_unreachable.bendtt`):

```
bad : ∀x0 : Empty -> ∀x1 : D -> ∀x2 : D -> Empty =
  λ+x0 => λ{(,): λ{.C0: λ{(): λ{(,): λx1 => λx2 => (λ{(,): λ{}} x0)}; λ{}};
              λ{.C1: λ{(): λ{(,): λx1 => λx2 => (λ{(,): λ{}} x0)}; λ{}}; λ{}}}}
```

**⇒ CONFIRMED: a LIVE kernel term of type `Empty` — `(λ{(,): λ{}} x0)` =
`App(Prj(Efq), x0)` — in a def whose type is a FUNCTION type.**

### M3 — the simplest expression of the same hole (`h06`)

`cand/h06_c10.bend`:

```bend
import Base

def bad(e: Empty) -> Empty:
  match e:
```

Its BendTT — **the whole hole in one line**:

```
bad : ∀x0 : Empty -> Empty =
  λ{(,): λ{}}
```

**⇒ `Prj(Efq)` IS THE BODY, AT TYPE `∀x0 : Empty -> Empty`.** The `Prj` rule
gives `Prj(Efq) : ∀q (s : Empty) -> P` for **any** `P`; here `P = Empty`.

### M4 — the kernel's rules for `Empty`, read from the source

* **How Bend's `Empty` is encoded** (`safe.ts:380-399` `adt_emit`):
  `Empty : *(.Q2) = Σx0 : <> -> (Empty.arms x0)`. **⇒ In the kernel a Bend
  `Empty` is a `Σ` whose domain is the EMPTY ENUM `<>`, and the def `Empty`
  itself has the KIND `*2` as its declared type.** A value of type `Empty` must
  be a `Tup` whose tag has type `<>` (`bendtt.lean:1175-1181`).
* **A `Lab` can never have type `<>`** (`bendtt.lean:1182-1185`:
  `Res.need (ks.contains k)`), so the tag cannot be a label.
* **`Prj`'s rule** (`bendtt.lean:1186-1195`): `Prj h : ∀q (s : Σr x:A -> B) -> P`
  requires `h` to check at `∀(fld r q) x:A -> ∀q y:B -> P`. The special `Efq`
  (`bendtt.lean:1207-1213`) checks at `∀q (s:<>) -> P` for **any** `P` — it
  constrains only the DOMAIN. **⇒ `Prj(Efq) : ∀q (s : Empty) -> P` for any `P`.**
* **`App`'s special case** (`bendtt.lean:1227-1234`): for `App q f (Var i)` where
  `f` takes the variable, `f` is checked at `∀q A P` with `P = Ren.pick i T` —
  **the expected result type `T` is pushed into `f`'s check. ⇒
  `App(Prj(Efq), x0)` can be checked at ANY `T`.**
* **The catch-all** (`bendtt.lean:1235-1237`): every other term is *inferred* and
  then **FITTED**: `Ctx.fit ck c U T`, i.e. `Term.fits` (`bendtt.lean:1018-1029`).

### M5 — `s.empty` is written in EXACTLY TWO PLACES (the enumeration asked for)

`grep -n 's\.empty\|\.empty\b' safe.ts` over all 1573 lines:

```
598:  return { ...s, c: ..., empty: s.empty.map(mv),      <- the map, not a write
683:      s2 = { ...s2, empty: [...s2.empty, { $: "App", q: 1, f: { $: "Prj", h: { $: "Efq" } }, x: { $: "Var", l } }] };
751:      if (all === null || no_ctr(e, all.A) || s.empty.length === 0) {   <- read
756:      const f = convoy_bind(e, scope_hide(scope_hide(s)), cv, (s2: Scope) => s2.empty[0], fs);  <- read
780:      const s2e = no_ctr(e, all.A) ? { ...s2, empty: [...s2.empty,        <- write
781:        { $: "App", q: 1, f: { $: "Efq" }, x: { $: "Var", l: lt } } as O] } : s2;
```

**⇒ TWO writes: line 683 (a λ whose domain `no_ctr`) and line 780 (a default
arm whose scrutinee type `no_ctr`). THERE IS NO THIRD WRITE.** The task's
question — "is there a third?" — is answered: **no.**

### M6 — and why both are closed, re-derived (not copied)

* **Line 780** is reached only in `swi`'s `default` arm and only when
  `no_ctr(e, all.A)`. But `swi`'s `Mat` case (`safe.ts:766`) already sets `dead`
  when `mT?.$ === "All" && no_ctr(e, mT.A) && x.m.$ !== "Mat"`, and then
  `safe.ts:767` replaces the continuation by `B.Efq()`. **⇒ the default arm is
  never emitted in that case. Unreachable.**
* **Line 683** is a **λ binder**. **⇒ the def has a parameter ⇒ the def's type
  is a FUNCTION type.**

**⇒ ⇒⇒ THE PRIZE, SHARPENED: a win needs a def whose declared type is `Empty`
and whose body is a closed `Tup`. The `s.empty` route cannot produce one,
because `s.empty`'s only live source is a λ binder. ⇒ THE HOLE MUST BE FOUND
ELSEWHERE.**

### M7 — the two emptiness predicates AGREE (the task's "sharpest lead", checked)

* `bend.ts:842-853` `ctx_dead`: `t.$ === "ADT" && book_adt(book, t, ctx).c.length === 0`.
* `bend.ts:882-892` `book_adt`: `tld.c.filter((c) => !r.has(c.k))` where `r` is
  the type's refuted-constructor list.
* `safe.ts:867-872` `no_ctr`: `tld.c.every((c) => x.r.includes(c.k))`.

**⇒ BOTH PREDICATES ARE "every constructor of the ADT is in the type's `r`
list". THEY AGREE. ⇒ THE SHARPEST LEAD THE TASK NAMED — "FIND THE ADT WHERE THE
PREDICATES DISAGREE" — HAS NO ANSWER: THERE IS NO SUCH ADT.** The disagreement
is not in the predicates but in **what the two sides DO with them**: bend2 uses
"any live binder in the context is empty" (`ctx_dead`), `safe.ts` uses "the
scrutinee's own type is empty" (`no_ctr`) — which is the prior hunt's finding,
and it is a difference of *scope*, not of *predicate*.

**⇒ AND A SECOND DIVERGENCE, THE REFINEMENT:** bend2's `LE` on ADTs is
`b.r ⊆ a.r` (`bend.ts:3167-3176`, `mode === "LE"` skips the length check) — a
MORE-REFINED type fits a LESS-REFINED one. **The kernel has no `r` list at
all**: `adt_emit` always emits the FULL constructor list as the tag enum
(`safe.ts:394`), so the kernel's `D` is always `<C0, C1, …>` and the refinement
is invisible to it. **⇒ the two sides' notions of "the same datatype, less
refuted" are simply incomparable.** Measured at the kernel (§4, C2).

### M8 — why a closed term of type `Empty` is unreachable (measured, not argued)

`check` of a `Tup` at `Ref Empty` needs a tag of type `Enu []`; `check` of a
`Lab` at `Enu []` needs `k ∈ []`. The catch-all's `Ctx.fit (Enu []) (Enu [])`
requires the inferred type to be `Enu []` (`fits`'s `Enu`/`Enu` case is
`ks ⊆ js`; its `conv` fallback needs literal equality — and `Term.conv` has
**no `Enu` case** in `Term.parts`, `bendtt.lean:965-977`). The only ways to
infer `Enu []`:

* `infer (Ref k) = d.T` — needs a def of type `Enu []`. `D.efq : ∀x0 : D -> <>`
  has `Enu []` as a **codomain**, not as a type; there is no def of type `Enu []`.
* `infer (App f x) = inst B (arg x A)` — needs `f : ∀q A -> Enu []`. `D.efq` is
  the only such def and its domain is `D`, an **empty** datatype ⇒ circular.
* `infer (Var i)` — needs a binder of type `Enu []` ⇒ the term is not closed.
* `infer (Ann x T) = T` — needs `check x (Enu [])` ⇒ circular.

**⇒ A CLOSED INHABITANT OF `Enu []` (hence of `Empty`) IS NOT REACHABLE BY ANY
OF THESE. THE KERNEL'S `Claim.empty` HOLDS FOR EVERY CONSTRUCT I COULD FIND.**
The remaining hope is a *divergence* between the elaborator and the kernel
(§4), not a direct construction.

---

## 3. TARGET B — the out-of-repo input in the proof toolchain

**The task pointed at `~/.bend/check.json`. I measured that, and then found a
bigger one. Both are below; the bigger one is stated with its limits.**

### M9 — `check.json` cannot change the verdict (the task's (a)–(e), measured)

`references/bend/bend2/main.ts:75` `const CHECK = path.join(os.homedir(),
".bend", "check.json");` and `:185-212` `check()`.

| question | answer | how |
|---|---|---|
| (a) HTTPS or HTTP? | **HTTPS by default** (`ORIGIN = process.env.BEND_ORIGIN ?? "https://bend-lang.com"`, `main.ts:65`), **but `BEND_ORIGIN` overrides it with ANY string, including `http://`** | measured: with `BEND_ORIGIN=http://127.0.0.1:<port>` the compiler issued a **plain-HTTP** `GET /check?v=2.0.37&os=darwin&arch=arm64` and accepted the answer |
| (b) does `check.json` reach the checker/elaborator/BendTT? | **NO.** `check()` is called once, at `main.ts:157`, after the command; its only output is `cli_say(2, …)` — fd 2, stderr. Nothing in it reaches `safe_check`/`safe_book`/`kernel_check` or the BendTT text | read `main.ts:129-212` + `safe.ts:1570-1573`; measured: a crafted `check.json` left the verdict unchanged |
| (c) what happens to the version string? | **compared and printed, never compiled.** `ver_newer(last.ver)` (`main.ts:226-231`) is a 3-component integer compare; `main.ts:208` prints `"bend " + last.ver + " is available…"`. **`last.ver` is printed RAW** — only `last.notice` is sanitised (control chars stripped, 200 chars) | read `main.ts:207-211` |
| (d) is `BEND_NO_TELEMETRY=1` the only guard, and does it also suppress the READ? | **It is the only guard, and it suppresses the read too**: the guard is at `main.ts:186-188`, the `readFileSync` at `:191` | measured: with the flag, **no request arrived** and **the cached notice was not printed** |
| (e) can a crafted `check.json` change what `--verdict` accepts? | **NO. MEASURED.** | M10 |

**⇒ THE ANSWER TO (e) IS NO, AND THE REASON IS STRUCTURAL: `check()`'s ENTIRE
OUTPUT IS STDERR, AND THE VERDICT LANE READS STDOUT.** `cli_verdict`
(`main.ts:808-821`) prints `PASS` to **fd 1** and everything else to **fd 2**.

### M10 — the fetch, measured end to end

`b3_fetch.py` points `BEND_ORIGIN` at a local HTTP server and runs the real
compiler. `receipts/b3_fetch/b3_fetch.out`:

```
A: no ~/.bend/check.json, BEND_ORIGIN=local http
   stderr='bend 9.9.9 is available: run bend update\nNOTICE-FROM-THE-LOCAL-SERVER'
   requests: ['/check?v=2.0.37&os=darwin&arch=arm64']
   ~/.bend/check.json now: '{"t":…,"ver":"9.9.9","notice":"NOTICE-FROM-THE-LOCAL-SERVER"}'
B: the cache is fresh -> no request        requests: []
C: BEND_NO_TELEMETRY=1                     requests: []   stderr: ''
D: --verdict with the local server
   stderr="Error: BendTT infrastructure: the kernel did not build (lean: warning: could not
           canonicalize path: '…/fetchhome/.elan/toolchains'…"
   VERDICT-OK? False
E: crafted check.json with t=0             requests: ['/check?v=2.0.37&os=darwin&arch=arm64']
```

**⇒ M10.1: A REMOTE SERVER CONTROLS THE COMPILER'S STDERR.** The answer's `ver`
and `notice` are printed verbatim (the `notice` minus control chars). With the
default `https://bend-lang.com` that is a trusted server; with `BEND_ORIGIN` set
to an `http://` URL it is a cleartext one.

**⇒ M10.2: A FILE OUTSIDE THE REPOSITORY RE-ARMS THE NETWORK INPUT.** A crafted
`~/.bend/check.json` with `"t": 0` makes `Date.now() - last.t > DAY` true on
**every** run (case E), so the compiler phones home every time instead of once
a day. The file is in the developer's home, so a repository clone does not
carry the behaviour: **the behaviour is a function of the machine, not of the
code.**

**⇒ M10.3 (an unplanned finding): `HOME` RELOCATES THE PROOF TOOLCHAIN.** Case
D: with `HOME` pointed at a temp dir, `--verdict` **REFUSED** with "BendTT
infrastructure: the kernel did not build". `safe.ts:1489` looks for the Lean
4.34.0 toolchain at `path.join(os.homedir(), ".elan", "toolchains", …)`.
**⇒ `--verdict`'s outcome is a function of `$HOME` in at least three ways: which
kernel binary, which Lean, and which telemetry cache.**

### M11 — **FINDING B: THE VERDICT IS DECIDED BY A BINARY OUTSIDE THE REPOSITORY**

`safe.ts:1483-1494`:

```ts
function kernel_bin(): string {
  const env = process.env.BENDTT;
  if (env !== undefined && env !== "") { return env; }
  const src = path.join(B.BEND_DIR, "bendtt.lean");
  const text = fs.readFileSync(src, "utf8");
  const hash = crypto.createHash("sha256").update(LEAN_VERSION).update("\0").update(text).digest("hex").slice(0, 16);
  const dir = path.join(os.homedir(), ".bend", "bendtt", hash);
  const bin = path.join(dir, "bendtt");
  if (fs.existsSync(bin)) { return bin; }      // <== used AS-IS, never re-verified
  ...
}
```

**⇒ THE VERIFYING KERNEL IS READ FROM `~/.bend/bendtt/<hash>/bendtt` AND, IF IT
EXISTS, IS EXECUTED WITHOUT BEING REBUILT OR CHECKED AGAINST `bendtt.lean`.**
The `<hash>` is `sha256("4.34.0" + "\0" + bendtt.lean)[:16]` — computable from
the public repository. Measured on this revision: `b9f3e0253abffb11`.

**MEASURED (control, then two treatments, on `cand/f03_unreachable.bend`):**

```
CONTROL    : BENDTT=<the kernel I built>         rc=0  stdout=[ALL PROOFS CHECK]
TREATMENT 1: HOME=<temp>, forged kernel says "SOME PROOFS FAIL"
                                                  rc=1  stdout=[]  stderr1=[SOME PROOFS FAIL]
            forged-kernel.log: 1 line(s)     <- the forged kernel WAS consulted
TREATMENT 2: HOME=<temp>, forged kernel says "ALL PROOFS CHECK"
                                                  rc=0  stdout=[ALL PROOFS CHECK]
            forged-kernel.log: 1 line(s)
```

The forged kernel is a two-line shell script that ignores the `.bendtt` it is
given. **⇒ THE VERDICT FLIPPED BOTH WAYS WITH NOTHING CHANGED IN THE
REPOSITORY.**

**⇒ AND A CONTROL ON THE FORGERY ITSELF, WHICH CORRECTS ONE READING OF THE PRIOR
REPORT:** for the three prior-art probes that the REAL kernel rejects
(`higher_evidence_base`, `dependent_empty_result_probe`,
`law_higher_evidence_probe`), the forged kernel was **never consulted** (0 log
lines) — because `safe_check` (`safe.ts:1570-1573`) is
`got.oos.length === 0 && kernel_check(got.text)`, and those defs are **OUT OF
SCOPE**, so the kernel is never asked. **THE OUT-OF-SCOPE REASON, MEASURED**
(`bin/bend <probe> -o out.bendtt`, whose oos lines go to **stderr**,
`main.ts:381-384`):

```
higher_evidence_base          - use: no model for use~F
dependent_empty_result_probe  - use: no model for use~F
law_higher_evidence_probe     - use: no model for use~F
specialized_dependent_param_probe   (no oos lines — it is in scope)
```

**⇒ THE PRIOR HUNT'S "MISMATCH" FOR THOSE THREE IS THE ELABORATOR REFUSING, NOT
THE KERNEL REJECTING — AND THE REFUSAL IS `model_at` FAILING TO MODEL THE `~F`
TEMPLATE PARAMETER (`safe.ts:374`, `oos("no model for …")`). THE KERNEL WAS
NEVER CONSULTED.** The prior report (§7) attributes it to the kernel; that
attribution is wrong, and the distinction matters: a "kernel stricter" claim
needs the kernel to have been consulted. **⇒ AND THE FAILURE IS IN
`model_at` — WHICH IS TARGET C3, AND IT IS THE ONE PLACE THE PRIOR HUNT'S OWN
ROOT CAUSE (#1182, THE `~` PARAMETER) ACTUALLY LIVES.**

**⇒ WHAT THIS IS, AND WHAT IT IS NOT.**
* **It is NOT a `⊥` zero day in the author's sense**: it is not a type-theoretic
  unsoundness, and it uses no `unsafe` and no FFI. **It is a trust-base
  observation.**
* Its practical significance is bounded and I say so: an attacker who can write
  `$HOME/.bend/bendtt/<hash>/bendtt` can equally replace `bin/bend` itself.
  **⇒ it is not a privilege escalation.**
* **Where it DOES bite:** a CI machine, a container image, or a laptop that
  **caches `~/.bend`** inherits a *verdict* from the cache, not from the
  repository. And this tree already met the consequence from the other end: the
  `d10-transcript` pin in `checks/differ.py` is the sha256 of a stderr stream
  that contains this notice, so upstream's next release redded a repository pin
  with no repository change.
* **⇒ THE FIX IS ONE LINE:** `kernel_bin()` should compare the cached binary
  against the one it would build, or rebuild it; and a verdict should not depend
  on a path in `$HOME`.

---

## 4. TARGET C — the three untested holes the prior hunt named

### C1 — the `.bendtt` parser's `partial def`s (`bendtt.lean:594-845`)

The `partial def`s are `Parse.gap`, `Parse.at`, `Parse.span` — inside the trust
base, and the kernel's claims are about `Book.check` on a *parsed* book, so a
mis-parse is outside every claim.

**MEASURED** with hand-written `.bendtt` fed straight to the kernel
(`c12_probe.py`, receipts in `receipts/c12_probe.out` and `receipts/kt/`):

| probe | what it is | verdict |
|---|---|---|
| `p_ctrl_ok` | the control: `bad : ∀x0 : Empty -> Empty = λ{(,): λ{}}` | **ACCEPT** |
| `p_parse_comment` | a `#` comment **inside a term** | REJECT — *"expected: a function type"*, i.e. the comment was skipped and the term parsed as intended |
| `p_parse_eof_hash` | a `#` at EOF with **no newline** | REJECT — same message ⇒ the comment was skipped |
| `p_parse_crlf` | CR and TAB whitespace | REJECT — same message ⇒ whitespace handled |
| `p_parse_uni` | a **multi-byte character in a name** (`bäd`) | REJECT — *"parse error: expected ':'"* |
| `p_parse_shadow` / `p_parse_shadow2` | a def whose **name equals a bound variable's name** (`x0`) | REJECT — *"In x0: expected: \*2 observed: \*1"* |

**⇒ THE FIRST ROW OF THAT TABLE WAS NOT A CLEAN CONTROL** (the body carried an
extra `λ`, so the failure was the `Lam` shape, not the comment), **SO IT WAS
RE-TAKEN with the control's exact body** — seven variants, all **ACCEPT**:

```
p2_ctrl          rc=0  ALL PROOFS CHECK
p2_comment       rc=0  ALL PROOFS CHECK   (a comment after the '=')
p2_comment_mid   rc=0  ALL PROOFS CHECK   (a trailing comment after the body)
p2_crlf          rc=0  ALL PROOFS CHECK   (every LF replaced by CRLF)
p2_tab           rc=0  ALL PROOFS CHECK   (a TAB as the body's indent)
p2_eof_hash      rc=0  ALL PROOFS CHECK   (a '#' at EOF, no newline)
p2_eof_hash_nl   rc=0  ALL PROOFS CHECK   (a '#' at EOF, with a newline)
```

**⇒ FINDINGS.**
1. **The comment and whitespace handling is CORRECT** — `Parse.gap`'s `where
   eol` clause (a `partial def` with a `where` block, the least-proved code in
   the file) skips `#`-to-EOL correctly, in every position tried, **and the
   whole book still checks**. **⇒ THE `partial def`s DID NOT YIELD A HOLE.**
2. **`Parse.span` STOPS AT THE FIRST NON-ASCII BYTE.** A name with a multi-byte
   character cannot be parsed at all. **⇒ NOT EXPLOITABLE FROM A BEND FILE**,
   because `safe.ts:555-557` `name_tt` encodes every non-`[A-Za-z0-9_.]`
   character as `_hex_`. **⇒ BUT IT IS A REAL LIMITATION OF THE TEXT FORMAT
   AND IT IS UNPROVED.**
3. **THE `Ref`/`Var` AMBIGUITY IS REAL AND IT IS WHAT MAKES `safe.ts`'s
   `book_show` NAMING CONVENTION LOAD-BEARING.** `Term.parse_name`
   (`bendtt.lean:695-699`) reads a name that is in the binder scope as a `Var`
   and anything else as a `Ref` — so a def named `x0` **cannot be referenced
   from inside a λ that binds `x0`**; the reference is silently read as the
   VARIABLE. `safe.ts:1435-1438` (`book_show`) picks the variable prefix `p` so
   that `^p[0-9]+$` matches **no def name**, which is exactly what prevents
   the mis-parse. **⇒ THE AMBIGUITY IS CLOSED BY CONSTRUCTION, AND THE
   CONSTRUCTION IS UNPROVED AND UNDOCUMENTED AS A SAFETY PROPERTY.**

**⇒ C1's VERDICT: THE PARSER'S `partial def`s DID NOT YIELD A HOLE, BUT THEY
YIELD ONE DOCUMENTED LATENT AMBIGUITY (the `Ref`/`Var` rule) AND ONE REAL
FORMAT LIMITATION (non-ASCII names).**

### C2 — `Term.fits`'s subsumption vs `bend.ts`'s `term_compare "LE"`

`Term.fits` (`bendtt.lean:1018-1029`):

```
| Typ g, Typ h => Term.qge ck cl (min m n) g h
| Enu ks, Enu js => (ks.all js.contains, m)          -- U fits T iff ks ⊆ js
| All q A B, All p C D =>
  let r := if q == p then Term.fits ck cl (min m n) C A else (false, m)   -- DOMAIN REVERSED
  if r.1 then Term.fits ck false (min r.2 n) B D else r
| U, T => Term.conv ck cl (min m n) U T
```

`bend.ts`'s `term_compare "LE"` (`:3064-3207`), used by the checker at
`:3700` and `:3715` as ITS subsumption, **reverses the `All` domain the same
way** (`bend.ts:3150-3154`: `compare_go(mode, book, b.A, a.A, dep)`) — **so the
two AGREE on the `All` case.** The kinds agree too (`bend.ts:3117-3136` vs
`bendtt.lean:1000-1013`): Data fits Data, Data fits Type, Type does not fit
Data.

**MEASURED at the kernel** (`c12_probe.py`):

| probe | what it is | verdict |
|---|---|---|
| `p_fits_empty_lab` | a `Lab` at the EMPTY enum (`bad : <> = .C0`) | **REJECT** — *"a label of <>"* |
| `p_fits_empty_any` | `<>` used where `<C0>` is expected | **REJECT** — *"expected: <C0> / observed: \*2"* |
| `p_fits_all_dom` | `bad : ∀x0 : <C0> -> <>` (the reversed-domain direction) | **REJECT** — *"expected: <> / observed: \*2"* |
| `p_fits_all_dom2` | `bad : ∀x0 : <> -> <C0>` (the other direction) | **ACCEPT** |
| `p_efq_anycod` | `bad : ∀x0 : <> -> <C0> = λ{}` | **ACCEPT** |
| `p_tup_empty` | a `Tup` at the `Empty` `Σ` whose tag has type `<C0>` | **REJECT** — *"a label of <>"* |
| `p_tup_empty2` | a `Tup` at the `Empty` `Σ` whose tag has type `<>` | **REJECT** — *"expected: <> / observed: \*2"* |

**⇒ FINDINGS.**
1. **THE SUBSUMPTION DOES NOT REACH `Empty`.** `p_tup_empty` is the direct
   test: a `Tup` at the `Empty` `Σ` whose tag is a label of `<C0>` is REJECTED
   with "a label of <>". `p_tup_empty2` shows the other half: **`<>` used as a
   TERM has type `*2` (a kind), not `<>`** — so it cannot be a tag either.
   **⇒ THE TAG OF AN `Empty` VALUE MUST BE A TERM OF TYPE `Enu []` THAT IS NEITHER
   A `Lab` NOR THE ENUM ITSELF.**
2. **THE `All` CASE'S REVERSED DOMAIN IS REAL AND IT IS PERMISSIVE IN ONE
   DIRECTION:** `∀x0 : <> -> <C0>` is ACCEPTED (a function from the EMPTY enum
   to a NON-empty one) while `∀x0 : <C0> -> <>` is REJECTED. **⇒ `Efq`'s
   CODOMAIN IS UNCONSTRAINED — MEASURED.** This is the `Efq` rule
   (`bendtt.lean:1207-1213`) constraining only the domain.
3. **⇒ AND HERE IS THE SHARP POINT FOR THE PRIZE: `∀x0 : <> -> P` IS A FUNCTION
   FROM THE **EMPTY ENUM** TO `P` — AND THE `Empty` DATATYPE'S `Σ` HAS THAT VERY
   EMPTY ENUM AS ITS DOMAIN.** So `Prj(Efq) : ∀q (s : Empty) -> P` is the
   `Σ`-analogue of the accepted `Efq`. **⇒ BUT THE PRIZE NEEDS A VALUE, NOT A
   FUNCTION, AND `p_tup_empty` SHOWS THE VALUE'S TAG CANNOT BE BUILT.**
4. **⇒ THE REFINEMENT DIVERGENCE (M7) IS CONFIRMED AT THE KERNEL:** the kernel
   has no `r` list, so bend2's "a more-refined type fits a less-refined one" has
   no kernel counterpart. **⇒ THE TWO SIDES' NOTIONS OF "THE SAME DATATYPE, LESS
   REFUTED" ARE INCOMPARABLE. THIS IS A REAL DIVERGENCE, AND IT IS THE
   PERMISSIVE DIRECTION ON bend2's SIDE.**

**⇒ C2's VERDICT: A DIVERGENCE EXISTS AND IT IS BENCHMARKED — THE REFINEMENT
ONE — BUT IT DOES NOT REACH `Empty`, BECAUSE THE KERNEL'S `Empty` IS A `Σ` OVER
THE EMPTY ENUM AND EVERY WAY TO FILL THAT ENUM IS CLOSED.**

### C3 — `safe.ts`'s `model_at` (the body of every UNFILLED LAW)

`safe.ts:489-538` `model_at` manufactures the body of a bodiless def (a law).
`safe.ts:371-377` `def_emit` then emits it, **opaque** when the model is a
model, or **transparent** when the def had a body.

**READ, CASE BY CASE:**
* **`Typ`** (`:498-501`): `B.ADT("Unit", [])` — a model of a kind. Safe.
* **`All`** (`:502-508`): `Ann(Lam(x, model of the codomain), F)`. The codomain's
  model is substituted for `x`. Safe.
* **`Eql`** (`:531-533`): `term_compare("EQ", F.a, F.b, d) ? Ann(Rfl(), F) : null`.
  **The kernel's `Rfl` rule (`bendtt.lean:1214-1217`) requires `Term.conv a b`.**
  **⇒ IF bend2's "EQ" IS LOOSER THAN THE KERNEL'S `conv`, THE KERNEL REJECTS
  (kernel stricter ⇒ safe). IF bend2's "EQ" IS TIGHTER, `model_at` RETURNS
  `null` ⇒ THE DEF GOES OUT OF SCOPE ⇒ `--verdict` FAILS (a refusal ⇒ safe).
  ⇒ `model_at`'s `Eql` CASE IS SAFE IN BOTH DIRECTIONS. PROVEN BY READING.**
* **`ADT`** (`:509-530`): builds `Ann(Ctr(c.k, xs), F)` with `xs` the models of
  the constructor's fields. **A WRONG FIELD MODEL MAKES THE `Ann` ASSERT THE
  WRONG TYPE, AND THE KERNEL CHECKS THE `Tup`'s COMPONENTS AGAINST THE `Σ`
  CHAIN ⇒ THE KERNEL CATCHES IT (kernel stricter ⇒ safe).** A field model that
  is `null` makes the whole model `null` ⇒ out of scope ⇒ refusal.
* **`default` ⇒ `hyp()`** (`:496`): `hs.find(([, A]) => term_compare("EQ", A, F, d))?.[0] ?? null`.
  **A hypothesis is returned only when its type is EQ to the target ⇒ the
  hypothesis's TYPE IS RIGHT ⇒ the model is well-typed.** The same
  looser/tighter argument as the `Eql` case applies: if the kernel's `conv`
  disagrees with bend2's "EQ", the kernel is the stricter side (it checks the
  body at the declared type, `bendtt.lean:1402-1407`) ⇒ **safe**.

**⇒ C3's VERDICT: `model_at` IS SAFE IN EVERY BRANCH, BY THE SAME ARGUMENT
EACH TIME — the kernel checks the manufactured body at the DECLARED type, so a
model of the wrong type is rejected by the kernel and a model that cannot be
found is refused by the elaborator. THE ONE PART OF THE BOOK THE KERNEL CANNOT
CROSS-CHECK AGAINST bend2 IS ALSO THE ONE PART WHERE THE KERNEL'S OWN CHECK
DOES THE WORK.**

**⇒ AND THE ONE `model_at` BEHAVIOUR WORTH NAMING, MEASURED (`e01`–`e05`):** a
law whose claim is `Empty` has **no model** (`model_at` on an empty ADT returns
`hyp()`, and there is no hypothesis ⇒ `null` ⇒ the def goes out of scope), and
a law whose claim is `∀x : Empty -> Empty` has the model `λx => x` — a
**hypothesis of the empty type returned as a value**. That model is correct
(the identity on `Empty` is a function, not an inhabitant), and the resulting
book passes the kernel — but it is the same `s.empty` shape as `c10`, and it is
**not** a proof of `Empty`.

**⇒ AND THE ONE `model_at` FAILURE THAT IS ACTUALLY REACHED IN PRACTICE,
MEASURED:** the three prior-art probes all die with **"no model for use~F"**,
i.e. `model_at` cannot model a **`~` template parameter** whose type is a
dependent equality. **⇒ `model_at` IS NOT JUST A CORNER: IT IS WHERE
`--verdict` ACTUALLY REFUSES.** And note the shape of the refusal: **the
kernel is never consulted at all**, so this is a *refusal*, not a divergence.
**⇒ A DIVERGENCE NEEDS A BOOK THAT IS IN SCOPE AND THAT THE KERNEL STILL
REJECTS — AND NONE OF THE 17 CANDIDATES, NOR THE PRIOR HUNT'S 12, IS ONE.**

---

## 5. WHAT I DID NOT FIND, AND WHY IT MATTERS

* **No def of type `Empty` was produced by any of the 17 candidates.** The
  three ways the kernel can be given a term of type `Empty` are all closed:
  the `Tup`'s tag cannot be a `Lab` (`p_fits_empty_lab`), cannot be the enum
  itself (`p_tup_empty2`), and cannot be an application without an `Empty` to
  apply it to (`Empty.efq`'s domain is an empty datatype ⇒ circular).
* **No `s.empty` source outside a λ binder** (`safe.ts:683`, `safe.ts:780` are
  the only two writes).
* **No divergence between `safe.ts`'s `no_ctr` and `bend.ts`'s emptiness test**
  — they are the same predicate on the same `r` list.
* **No parser mis-parse reachable from a Bend file.**

## 6. Discipline / what was NOT done

* No `unsafe`, no FFI, no `--verdict`-accepted file is claimed as a submission.
* `references/bend/` was **not** edited. The kernel was built in **my own**
  artifact dir. `tinybendygrad/`, `checks/`, `gates/`, `AGENTS.md`,
  `.agents/TODO.md`, `.agents/TOOLS.md` were **not** touched.
* **No git command mutated anything; nothing was committed.** No `git add`,
  no `reset`, no `rebase`. (`git ls-tree`/`git log` were read with
  `env -u GIT_INDEX_FILE`.)
* Forbidden instruments were **not** run: `checks/differ.py`, `gates/*`,
  `checks/e2e*`, `checks/sweep.py`, `checks/bounded.py`,
  `checks/port-compile-gate.py`, `pytest`, `mypy`, `ruff`.
* **One bend process at a time**, never background.
* **NO `.txt` FILES** were created: `.rows`/`.out`/`.err`/`.md`/`.json`/`.rc`
  only.

---

## Log

- 2026-10-22T18:51Z — report created (minute five). Prior hunt's report read in full.
- 2026-10-22T18:55Z — kernel re-derived: `bendtt.lean` sha256 `83cdd36e…`, built with
  Lean 4.34.0 ⇒ `bendtt` sha256 `989d9cf2…`, byte-identical to the prior hunt's and to
  the machine's `~/.bend/bendtt/b9f3e0253abffb11/bendtt`.
- 2026-10-22T19:05Z — M1: the validator and its four fakes.
- 2026-10-22T19:30Z — M2-M4: c10 re-measured; h06 found (the minimal shape); the
  kernel's `Prj`/`App`/`Tup`/`Lab`/`fits` rules read at `v2.0.37`.
- 2026-10-22T19:45Z — M5: `s.empty` has exactly TWO writes (safe.ts:683, safe.ts:780).
  No third.
- 2026-10-22T20:05Z — M6-M8: why the hole is closed, and the sharpened prize.
- 2026-10-22T20:20Z — M9-M11: TARGET B measured. **FINDING B: the verdict is decided
  by `~/.bend/bendtt/<hash>/bendtt`, a binary outside the repository.**
- 2026-10-22T20:30Z — the shared temp dir was wiped under me (the prior hunt's kernel
  and mine). Rebuilt into `.agents/slop/verdict-hunt2/kernel/`.
- 2026-10-22T21:10Z — M1.1: the validator CRASHED on an `Eql` book. Fixed; every grade
  re-taken.
- 2026-10-22T21:40Z — TARGET C measured: C1 (the parser's `partial def`s), C2
  (`Term.fits`), C3 (`model_at`, by reading).
- 2026-10-22T22:05Z — all 17 candidates re-run; receipts current; final report.
