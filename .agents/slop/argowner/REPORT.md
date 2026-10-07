# ARGOWNER — the `Arg` exhaustiveness surface has one owner, and the last `flip` disagreement is a type

Unit `argowner`, 2026-10-07. Repo `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.
**Nothing committed, nothing staged.** Six files under `tinybendygrad/` changed; everything
else I produced is under `.agents/slop/argowner/`.

> **VERDICT, IN ONE PARAGRAPH, BEFORE THE DETAIL.**
> **`flip`'s `arg` disagreement is closed and measured** (`SHARED cores 5 -> 6`, `ONLY-PY 1 -> 0`,
> `rung3.5-crossrefs 1 -> 0`) — but closing it needs **one arm in `.agents/slop/graphcmp.bend`,
> a file I was told not to touch**, and until that arm lands **the whole 34-graph corpus is
> `DEAD`** (`emit bend: 0 rows after 5 attempts`, `graphs-agree=0`). I built the fix in my own
> directory, compiled it and ran the real differ against it, so the unblock is a **measurement**,
> not a prediction — `.agents/slop/argowner/handoff.out`. **`mv_perm`, `mv_permrep`,
> `mv_permlen` are byte-identical to `HEAD`, 3 of 3, with a denominator of 22 `mv_` rows of which
> 22 of 22 are unchanged.** The tree I hand back is *better on the port and worse on the corpus*,
> and §7 says exactly how to un-worsen it in one line.

---

## 0. HOW MY OWN MEASUREMENT COULD BE WRONG — said FIRST, with the before-values

Seven ways, each either fixed or bounded. The two that changed a number are first because the
brief said this failure has happened twice in this project.

| # | how it could be wrong | before | what I did | after |
|---|---|---|---|---|
| **1** | **The census resolves a key and reports the resolution as a count.** `census.py` asks "are there `Arg` sites?" and the honest failure is a *filter* that matches nothing. My first wide-scope filter used `IMPORT_RE` with a **non-`MULTILINE` `^` against a non-joined 80-line window**, so it matched exactly one file and printed `of which 1 import tinybendygrad/uop/ops.bend` out of 288 `.bend` files. | `1 of 288` | fixed to `re.M` over the whole file | **`117 of 288`**, and the closed set went from 1 (wrong) to **6** |
| **2** | **The unqualified-pattern rule fires on every file.** `variants` included `""` (for `ops.bend`'s own bare `case ATuple{ys}`) and I applied it to *every* file — so `engine/worker.bend`'s own `type Arg is Data: AU32, AStr` had its bare `case AStr{s}` scored as `ops.bend`'s `AStr`. | `189 sites / 36 files` | `""` now applies to `ops.bend` only | **`188 sites / 35 files`** |
| **3** | **A radius read as a count of sites.** `plant.py` added a constructor and found **35 of 35** files red. `bend` reports **one** error per file and all 35 named the *same* shared `eq_arg.sel`. 35 files is a radius; it is not 35 sites. | "35 files break" | replaced by a **closure**: fix the named site, re-probe, until nothing is named | **3 sites**, and the closure is what found them |
| **4** | **`bend` pads patterns.** `case _         : Nil{}` — `WILD_RE = ^_\w*$` did not match the trailing spaces, so 13 real wildcards scored `INCOMPLETE`. | 7 `INCOMPLETE` | `pat.strip()` | **1** |
| **5** | **A `match` can be over a TUPLE of values**, so `case _ _:` is a wildcard and `case ARange{..} OpsRANGE{}` is a two-conjunct pattern. Splitting only on `,`\|` mis-scored both. | 4 more false `INCOMPLETE` | wildcard = *every* conjunct is `_`/binder | closed set 3 |
| **6** | **The whole closed set is outside the scope the brief gave me.** `census.py`'s scope is `tinybendygrad/`, and that scope **cannot see the site that actually broke the corpus**. | 3 closed, all in the port | added `census-wide.py`: `os.walk` the repo root | **6 closed: 3 in the port, 3 outside** — and one of the 3 outside is the differ's live harness |
| **7** | **`oracles/FINAL_mv.rows` is stale, so diffing against it would have measured nothing.** It holds **16** rows and spells `dtype=int`; the port emits **22** rows and spells `dtype=i32`. | — | did **not** use it as an oracle; the port's own rows are the population, and a **pristine `HEAD` control** is the comparison | 22/22 |
| **8** | **The instrument counts its own scratch.** After landing, `census-wide.py` walked `.agents/slop/argowner/` and found `handoff-graphcmp.bend` + `mine/*.bend` — **copies of rows already counted**, reporting 3 phantom "closed" sites. | `296 files / 339 sites / 9 closed` | excluded this unit's own directory by name | **`287 files / 271 sites / 6 closed`** |

One more bound, stated rather than fixed: **`argstr`'s closed set is proven only for the 34 files
the closure compiled.** A file no `.bend` file imports is not reached. `upat.bend` is exactly that
(§4), and it is why I filed it rather than fixed it.

---

## 1. THE CENSUS — `Arg` has ONE OWNER, and it is 3 sites, and 2 of them are now mine

### 1a. The population, by the three admissible kinds and none of the three inadmissible

`.agents/slop/argowner/census.py` → `census.rows`. Scope: `os.walk(tinybendygrad)` `*.bend`.

- **(a) the constructors are PARSED**, not typed — out of the generator's own declaration
  `type Arg is Data:` at `tinybendygrad/uop/ops.bend`, every indented `Ctor{…}` line under it.
  The file is not in this file. `census.py` exits **3 `REFUSED`**, not "0 sites", if that parse
  returns nothing; it fired for real on the first run, when a stale `ctors_of()` read the *first*
  `type … is Data:` in `ops.bend` (`Op`, 130 constructors) instead of `Arg`.
- **(b) the files are a DIRECTORY WALK**, `os.walk`, `*.bend` — **134 files**.
- **(c) the alias is DERIVED** from the `import …/ops.bend as X` lines — one alias, `O`, 49 sites.

**The negative control that makes the denominator mean something: `Arg` is a NAME in Bend, not a
type.** There are **six** `type Arg is Data:` declarations in this tree —

| file | its `Arg` is | would a `\bArg\b` census have counted it? |
|---|---|---|
| `uop/ops.bend:1190` | **the one under census**, 22 ctors | yes |
| `renderer/amd/dsl.bend:120` | a 4-field record `Arg{name, v, has}` | yes, falsely |
| `engine/worker.bend:105` | `AU32{v}` \| `AStr{s}` | yes, falsely |
| `runtime/ops_python.bend:898` | `Arg{kind, x, y}` | yes, falsely |
| `runtime/ops_cl.bend:707` | `Arg{i, slot, kind, size, off}` | yes, falsely |
| `runtime/support/hcq2.bend:448` | `Arg{at, k}` | yes, falsely |

Qualifying every pattern by the *derived* alias is what keeps the other five out.

### 1b. THE DENOMINATOR

> **190 sites** — `match` blocks naming ≥1 of the parsed `Arg` constructors — across **all 134
> `.bend` files under `tinybendygrad/`**, read on the **landed** tree, so 22 constructors because
> this unit added one. Of those 190:
>
> | kind | n | a new constructor… |
> |---|---:|---|
> | **WILDCARDED** (`case _`, `case _ _`, or a binder) | **187** | cannot break them |
> | **EXHAUSTIVE** (names all 22, no wildcard) | **2** | **BREAKS them** |
> | **INCOMPLETE** (no wildcard, missing ≥1) | **1** | already red |
>
> The **same walk before the landing** read **188 sites / 185 wildcarded / 2 exhaustive /
> 1 incomplete** — 21 constructors, and `arg_int` was then missing **two** (`AOpLit` *and*
> `ABoolList`). 188 → 190 is `upat.bend`'s new arm plus `render.bend`'s.

> **THE CLOSED SET — the real owner surface — IS 3 SITES OF 190, IN 3 FILES.**
>
> | file | line | def | state before | state after |
> |---|---:|---|---|---|
> | `tinybendygrad/uop/ops.bend` | 2180 | `eq_arg.sel` — the **ucache key** | EXHAUSTIVE, 22 arms | **FIXED here** (arm 23) |
> | `tinybendygrad/uop/render.bend` | 718 | `arg_repr` | EXHAUSTIVE, 22 arms | **FIXED here** (arm 23) |
> | `tinybendygrad/uop/upat.bend` | 398 | `arg_int` | INCOMPLETE, missing **`AOpLit`** | **unchanged — §3** |

**`eq_arg` is not optional.** It is the ucache key (`ops.py:201`), so a constructor with no
comparator interns two different values to one node. A new `Arg` variant without an `eq_arg` arm
is a *silent* merge, not a compile error — which is why `eq_arg.sel` is the one arm that must never
be skipped.

### 1c. THE COMPILER CONFIRMS 3, AND THE CENSUS'S 185 ARE NOT AN ASSUMPTION

A regex cannot decide "closed". So I let `bend` decide, as a **closure** (`closure.py`): fix the
site the compiler named, re-probe all 35 site files, repeat.

| round | tree state | GREEN | RED | sites the compiler named |
|---|---|---:|---:|---|
| `plant.py` PASS 2 | +`ABoolList`, nothing fixed | **0** of 35 | 35 | `eq_arg.sel` — **named by all 35**, which is how the radius masqueraded as 35 sites |
| `closure` round 1 | `eq_arg.sel` fixed | **32** of 35 | 3 | `arg_repr` (2 files: `render.bend` **and `codegen/__init__.bend`, which only INHERITS it by import**), `arg_int` |
| `closure` round 2 | `+ arg_repr` arm | **34** of 35 | 1 | **`arg_int`, missing `AOpLit` only** — the pre-existing defect |

**Why "32 of 35 GREEN" is a falsification and not a partial one.** `bend` lists *every* missing
constructor for the match it stops at (it printed `expected : cases for ops.AOpLit, ops.ABoolList` —
both), and type-checking a file covers everything it imports transitively (`codegen/__init__.bend`
inheriting `render.bend`'s error is the proof). So **a file that is GREEN with a 23rd constructor
present has NO closed `Arg` match anywhere in its transitive closure.** That is 34 of 35 files, and
the 35th's single site is pre-existing.

### 1d. THE SCOPE THAT MATTERS IS BIGGER THAN THE PORT — and it broke the corpus

`census-wide.py` → `census-wide.rows`. Scope: `os.walk(<repo root>)` `*.bend` = **287 files**
(this unit's own `argowner/` directory excluded — §0 row 8), of which **116 import
`tinybendygrad/uop/ops.bend`**. **271 `Arg` sites** across those 116. Closed:

> **6 closed sites over the whole repo, of which 3 are OUTSIDE `tinybendygrad/`:**
>
> | file | line | def | live? |
> |---|---:|---|---|
> | `tinybendygrad/uop/ops.bend` | 2180 | `eq_arg.sel` | **live — fixed** |
> | `tinybendygrad/uop/render.bend` | 718 | `arg_repr` | **live — fixed** |
> | `tinybendygrad/uop/upat.bend` | 398 | `arg_int` | **live, red — §3** |
> | **`.agents/slop/graphcmp.bend`** | **411** | **`argstr`** | **LIVE — the differ's own harness. THIS is what made the corpus DEAD.** |
> | `.agents/slop/linfix/before/drivers/two/gcmp.bend` | 379 | `argstr` | a `before/` snapshot; nothing compiles it |
> | `runs/margsym/snap/graphcmp.bend` | 363 | `argstr` | a `runs/` snapshot; nothing compiles it |

**The owner surface is therefore 4 LIVE sites, not 3** — and the fourth is not in the port.

### 1e. THE OWNERSHIP, STATED SO IT CAN BE ENFORCED

**Whoever adds or removes an `Arg` constructor owns all four live closed sites.** Three are in the
port and were fixed here. The fourth is `.agents/slop/graphcmp.bend:411 argstr` and it is **not
mine** — §7. `upat.bend:398` is the fifth and it is **already red** — §3.

**The recurrence this removes:** every prior attempt at FLIP (`flipbool`, `flipport`, `flipblock`,
`flipthird`) re-derived the same decomposition — *two of these arms are one line each and nobody
owns them* — and `flipthird` §4.2 named it verbatim. It was never wrong; it was **unowned**.

---

## 2. WHAT I LANDED, IN `tinybendygrad/` ONLY — 92 lines added, 18 removed, 6 files

| file | +/− | what |
|---|---:|---|
| `uop/ops.bend` | **+40 −0** | `ABoolList{bs: List<&2, Bool>}`; `eq_bool_list`; `eq_arg.ABoolList`; the `eq_arg.sel` arm; `bools_of`/`bools_of.go` |
| `uop/render.bend` | +15 −1 | `bool_tuple_repr`/`.go`; the `arg_repr` arm |
| `uop/fold.bend` | +21 −9 | `flip_len`; `flip_ds` takes a `Nat` count instead of a `List<&2,U32>`; `g_mv_flip` builds `ABoolList` |
| `uop/upat.bend` | **+6 −0** | **the `ABoolList` arm only** — see §3 |
| `schedule/prepare.bend` | +6 −5 | `pr_flip` builds `ABoolList` |
| `mixin/movement.bend` | +4 −3 | `G.flip`, `mxw_flip_new` build `ABoolList` |

**Why a new `Arg` constructor and not a fix to `ATuple`.** `ATuple` is PERMUTE's spelling and it
is **correct** there; making it carry both would make PERMUTE's `n(i1,i0)` a lie. Upstream itself
has **one** `UPat` over PERMUTE **and** FLIP (`spec.py:166` asserts `isinstance(mv.arg, tuple)` for
both) over **two** arg types, and `ops.py:428` guards FLIP's element type and PERMUTE has no such
guard. `Bool` is not a `U32` in this port, so the bool was *unrepresentable*, not merely
*mis-rendered*.

**Why `flip_len` and not an `order_arg` arm** (this is `flipthird` §2's point, confirmed by
reading `flip_ds`): `flip_ds.put` uses its `ys` for **nothing but `List.length`**. So `flip_ds`
asks for a count, and `order_arg` keeps answering `List<&2, U32>` for `perm_ds`, which does read
the permutation. A shared `order_arg` arm would have needed a `Bool→U32` converter at a *second*
place — a second answer to a question that only asks how many.

**Reuse, not reinvention:** `eq_bool_list` reuses the existing `eq_bool` (`ops.bend:1625`). I
wrote a duplicate `eq_bool` first and the compiler refused it —
`expected : a fresh name (duplicate declaration: eq_bool)` — which is the reuse rule enforced by
the toolchain rather than by me.

---

## 3. `upat.bend`'s MISSING `AOpLit`, FILED PRECISELY, **NOT FIXED**

### THE DEFECT, with the before-value

`tinybendygrad/uop/upat.bend:397-421`, `def arg_int(a: O.Arg) -> Maybe<&2, U32>`. It names **20**
of the 22 constructors and has **no** wildcard arm, so it is one constructor short and the
compiler has been refusing the file.

**MEASURED, RED AT REST, IN MY OWN TREE, WITH ZERO EDITS OF MINE APPLIED**
(`flipthird/arg22.rows` §1 records the same reading; `.agents/slop/argowner/upat2.err` is mine):

```
$ .venv/bin/python checks/bounded.py --seconds 600 --mb 2048 -- ./bin/bend tinybendygrad/uop/upat.bend --check-only
token=WITHIN-LIMITS  rc=1
SOME PROOFS FAIL
Error:
- expected : cases for ops.AOpLit
- observed : \{}
Location: arg_int
397 | def arg_int(a: O.Arg) -> Maybe<&2, U32>:
398>|   match a:
```

### WHY IT IS INDEPENDENT OF FLIP, AND NOT MY DEBT

- It is about `AOpLit` — `Arg`'s 11th constructor, `UOp(Ops.PYLITERAL, arg=<a bare Ops>)`,
  landed by unit `ARGLIT` on 2026-10-05 (`.agents/slop/ARGLIT.md`). **Nothing in this unit's diff
  creates it** and `git diff HEAD -- tinybendygrad/uop/upat.bend` shows **+6 −0**: my one arm, for
  my own `ABoolList`, and no other line.
- **`arg_int` has no correct reading of `AOpLit` that is not `None{}`** — `isinstance(Ops.ADD, int)`
  is False upstream, exactly as for `ACustom` (`upat.bend:404-406` already says so). So the arm is
  one line, and *anyone* can write it; what took three units was that nobody owned the surface.
- **It gates nothing today, and that is the finding.** `grep -rln "import.*upat\.bend" --include='*.bend' .`
  → **no importer, rc=0** — so no other `.bend` file is broken by it, and no gate in `gates/`
  names it. It has been **DEAD, not red-and-blocking**: it runs and emits nothing, and nothing
  reads it. That is why three units could leave it.
- **I left it EXACTLY as I found it.** After my `ABoolList` arm landed, the error went from
  `expected : cases for ops.AOpLit, ops.ABoolList` back to **`expected : cases for ops.AOpLit`** —
  my change adds no debt and discharges no pre-existing debt, so the next agent sees one defect,
  not two. The unblock, for whoever takes it:

  ```
  tinybendygrad/uop/upat.bend, in `arg_int`, after the line `case O.ATuple{ys}: head1(ys)`:
      case O.AOpLit{_}: None{}
  ```
  Expect `ALL PROOFS CHECK`, rc=0, token `WITHIN-LIMITS`. **Do not** merge it with an `Arg`
  constructor change: merged, nobody can say which edit moved what, and this file has now been
  the subject of two wrong predictions (`flipthird` §1a: *"anyone told upat.bend is 1 line is
  being told a line count for a file that does not build"*).

---

## 4. THE OWED TRADE — all four verdicts, with denominators

### First, a correction to the brief's framing

**`mv_perm`, `mv_permrep`, `mv_permlen` are NOT graphs in the differ's corpus.** `GRAPHS`
(`graphcmp.py:1591`) is **34** entries and none of them is named `mv_perm*`; `ls
runs/graphcmp/D/D1-graph-mv_perm*` → no such file. They are **3 rows of `fold.bend`'s movement
unit** — `mv_of("perm", g_mv_perm10())`, `mv_of("permrep", …)`, `mv_of("permlen", …)` at
`fold.bend:6216-6218`, from `g_mv_perm` at `fold.bend:5493`. They are not differ verdicts at all,
and **`oracles/FINAL_mv.rows` cannot be their oracle**: it holds **16** rows and spells
`dtype=int`, the port emits **22** rows and spells `dtype=i32` (§0 row 7). So their verdict is a
**row-identity** measurement against a **pristine `HEAD`** control, which is stronger than a
comparison to a stale file.

### The four, with the direction each moved

| # | name | kind | population / denominator | BEFORE | AFTER | direction |
|---|---|---|---|---|---|---|
| 1 | `mv_perm` | `fold.bend` row | 1 of **22** `mv_` rows | `n=6 … shape=(3,2) dtype=i32` | **identical** | **correct way (held)** |
| 2 | `mv_permrep` | `fold.bend` row | 1 of **22** | `… shape=ABSENT dtype=ABSENT` | **identical** | **correct way (held)** |
| 3 | `mv_permlen` | `fold.bend` row | 1 of **22** | `… shape=ABSENT dtype=ABSENT` | **identical** | **correct way (held)** |
| 4 | `flip` | differ graph, 1 of **34** | `SHARED cores`, `ONLY-PY/BEND`, `rung3.5` | `cores=5 ONLY-PY=1 ONLY-BEND=2 rung3.5=1`, `arg py=n(b1,b0) bend=n(i1,i0)` | `cores=6 ONLY-PY=0 ONLY-BEND=1 rung3.5=0`, **`arg` paired** | **correct way on the arg; see §5** |

**`3 of 3 mv_* rows are byte-identical, and the denominator is `22 of 22`** — the whole `mv_`
block, not just the three named rows, is unchanged. Evidence, in order of increasing rigour:

1. `mv-BEFORE.rows` (22 rows, md5 `38aed9ed672a0573f5c351bda2b9044e`) vs `mv-AFTER.rows` →
   `diff` empty. *This control is weaker than it looks:* it was taken with `ops/render/upat` already
   landed, so it isolates the `fold.bend` edit only.
2. `movement.bend`, controlled **one-line revert** of `mxw_flip_new`'s constructor
   (`ABoolList{bools_of(flags)}` → `ATuple{flags}`, `md5` proven restored byte-identical):
   `mx-BEFORE.out` vs `mx-AFTER.out` → `diff` empty over **all 72 rows**, including
   `flip0`, `flip01`, `flip_noop` (which still reads `n=6 … srcops=Ops.BUFFER|Ops.STACK` — the
   `any(flip_arg)` identity test still drops the all-zero flip).
3. **The strong control.** All six files reverted to `HEAD` (`git show HEAD:<file>`; the six diffs
   are mine alone, `git diff --numstat` = 4+6+21+40+15+6 lines). `mv-PRISTINE.rows` ==
   `mv-AFTER.rows`, **22 of 22, byte-identical.**

### The two FLIP siblings the brief did not name, which is the real trade

`flip` moving its arg proves nothing unless the FLIP rows that consume it hold. Measured, both
identical to pristine `HEAD`:

```
mv_flip     n=6 op=Ops.FLIP nsrc=1 srcops=Ops.RESHAPE shape=(2,3)   dtype=i32
mv_fliplen  n=6 op=Ops.FLIP nsrc=1 srcops=Ops.RESHAPE shape=ABSENT dtype=ABSENT
```

`mv_fliplen` is the **load-bearing** one: it reads `shape=ABSENT` because `flip_ds` refuses a
length mismatch (`len(ps) != len(self.marg)`), so it goes through the exact `flip_len` path my
`ABoolList` change rerouted. **It still refuses.** That is the proof that `flip_len` counts rather
than converts: had it converted `Bool→U32` or fallen through `order_arg`'s `_` arm to `Nil{}`,
`mv_fliplen` would have read `shape=(2,3)`, and `mv_flip` would have read `shape=ABSENT`.

`oracles/FINAL_mv.rows` names `mv_flip`/`mv_fliplen` as the two FLIP rows, and
`fold.bend`'s own M6/M12 mutation ledger (`fold.bend:6865`, `:6872`) says M12 (`order_arg` →
`Nil{}`) moves **5** rows. **Measured: 5 of 5 still move** — `mv_perm`, `mv_permrep`,
`mv_permlen`, `mv_flip`, `mv_fliplen` — because `perm_ds` still reads `order_arg` and `flip_ds`
now reads `flip_len`, which *includes* the `ATuple` arm. I did not need `order_arg` to change, so
its mutation surface is untouched.

---

## 5. `flip` — the `arg` disagreement is closed, and the corpus is `DEAD` until ONE arm lands

### 5a. What the port change alone did to `flip`: NOTHING

`flip`'s row is emitted by `.agents/slop/graphcmp.bend:1340`, and it builds its graph **by hand**:

```python
+fl = O.UOp.new(O.Found.ar(r43), O.OpsFLIP{}, [O.Found.i(r43)], O.ATuple{[1, 0]}, O.TNone{})
```

It does not call `pr_flip`, `G.flip`, `mxw_flip_new` or `g_mv_flip`. So repointing all four live
construction sites — which I did, and which is what makes the harness edit honest rather than a rig
— **cannot move the `flip` row**. `flip` is decided by the harness, and the harness is outside my
write scope. **This is the single most important sentence in this report and it is a measurement,
not a claim: I could not move `flip` inside my scope, and §0 row 6 is the census that says why
nobody could see it coming.**

### 5b. What the harness edit does, measured — in my own directory

`handoff.py` copies `.agents/slop/graphcmp.bend` to `.agents/slop/argowner/handoff-graphcmp.bend`,
applies **three** edits, and **never opens the original for writing** (both md5s printed;
`SRC md5 UNCHANGED` verified):

1. import depth `./../../` → `./../../../` (this directory is one level deeper);
2. `bools.go`, copied from the adjacent `u32s.go` (`List.append`, not `String.append` — my first
   attempt used the latter and the compiler said `expected : String / observed : Quant`);
3. **one `argstr` arm** `case O.ABoolList{bs}: …` after `case O.ATuple{ys}: us(ys)`, and
   `g_flip`'s `O.ATuple{[1, 0]}` → `O.ABoolList{[True{}, False{}]}`.

Then it runs the **real differ**, read-only on both real files, via the `--bend-probe` flag
`graphcmp.py` already has (`:3038`, `:3054`):

```
$ .venv/bin/python .agents/slop/graphcmp.py diff --graph flip --bend-probe .agents/slop/argowner/handoff-graphcmp.bend
```

| | pristine `HEAD` | **with the handoff** |
|---|---|---|
| `SHARED cores` | **5** | **6** |
| `ONLY-PY` | **1** | **0** |
| `ONLY-BEND` | **2** | **1** |
| `rung3.5-crossrefs` | **1** | **0** |
| the FLIP's `arg` | `py=n(b1,b0) bend=n(i1,i0)` | **paired — `n(b1,b0)` on both** |
| `VERDICT` | `DISAGREE` | `DISAGREE` |

**The `arg` disagreement named in the brief is GONE, measured.** `ONLY-PY 1 → 0`: the FLIP node is
no longer one-sided.

**`flip` still reads `DISAGREE`, on a different and pre-existing residual:** `bend#7 GROUP dtype=void
shape=R … src=['6']` is bend-only. **It was bend-only in the pristine run too** (as `bend#7`, with
`bend#6` also FLIP). So my change removed one disagreement and left one that has nothing to do with
`Arg` — a bend-only GROUP wrapper. **I am not claiming `flip` reaches `AGREE`.** I could not get
there from inside my scope, and that is a reportable outcome the brief named in advance.

### 5c. THE STATE I AM HANDING BACK: the corpus is `DEAD`, and it is DEAD because of my change

```
$ .venv/bin/python checks/differ.py run          # WITH my landing, harness NOT patched
graphs=34  graphs-answered=34  graphs-agree=0  graphs-disagree=0  byte-identical=0
not-comparable=34  expect-moved=34  stable-failed=5 of 5
D1-graph-flip.txt.err: emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict:
  Location: argstr 410 | def argstr(a: O.Arg, depth: U32) -> String:
```

`VERDICT=` **empty** on 34 of 34. By doctrine 2 that is **`DEAD`** — it ran and emitted nothing. It
is **not** zero, **not** `AGREE`, and **not** the `graphs-disagree=1` I found. **Before my change:
1 of 34 disagree, 33 of 34 agree. After: 34 of 34 dead.** I have made the corpus unusable, and the
reason is structural rather than careless: **`argstr` is a closed match over `Arg`, so *any*
constructor I add breaks it, and the file that owns it is one I was told not to edit.**

`checks/differ.py` does say so loudly — `expect-moved=34`, exit 1, per-graph `VERDICT=` empty — so
this is not a silent green. It is a loud red, and it is the honest state.

---

## 6. THE FIVE VERDICTS, THIS UNIT'S OWN

| # | what | verdict | exit | scope / denominator |
|---|---|---|---:|---|
| 1 | `census.py` — the `Arg` sites in the port | **PASS** | 0 | **190 sites** (188 before the landing), 134 files; 3 closed |
| 2 | `census-wide.py` — the `Arg` sites in the repo | **PASS** | 0 | **271 sites**, 116 of 287 files import `ops.bend`; 6 closed |
| 3 | `plant.py` PASS 2 — the radius | **PASS** (as a radius) | 0 | 35 of 35 files red, **all 35 at one shared site** |
| 4 | `closure.py` round 2 — the closed set, by the compiler | **PASS** | 0 | **34 of 35 GREEN**; 1 RED = `upat.bend`/`AOpLit` |
| 5 | `fold.bend`, `ops.bend`, `render.bend`, `prepare.bend`, `movement.bend`, `tensor.bend` `--check-only` | **PASS** | 0 | 6 of 6, all `WITHIN-LIMITS` |
| 6 | `upat.bend` | **`FAIL`** — red, and **by design** | 1 | **pre-existing**, `expected : cases for ops.AOpLit`, §3 |
| 7 | `mv_perm`, `mv_permrep`, `mv_permlen` | **PASS** — held | 0 | **3 of 3 identical; 22 of 22 `mv_` rows identical to pristine `HEAD`** |
| 8 | `movement.bend`'s rows, one-line revert control | **PASS** — held | 0 | **72 of 72 identical** |
| 9 | `flip`, port change alone | **`DEAD`** | 1 | **0 of 34 corpus graphs comparable**; §5c |
| 10 | `flip`, with the measured handoff | **`FAIL`** | 1 | `SHARED cores 5 → 6`, `ONLY-PY 1 → 0`, `rung3.5 1 → 0`; residual = the bend-only `GROUP` |

**Nothing here is `SKIP` and nothing is `REFUSED`** except #6's *repair*, which is deliberately not
performed. Verdict tokens were read off the `[bounded]` line every time; no exit code was used as a
verdict.

---

## 7. THE UNBLOCK — one arm in one file, measured above

`.agents/slop/graphcmp.bend`, `argstr`, immediately after `case O.ATuple{ys}: us(ys)` at **:453**:

```
case O.ABoolList{bs}: String.concat(["n(", String.join(bools.go(bs, Nil{}), ","), ")"])
```

plus `bools.go` (the `u32s.go` shape, `:171`), plus `g_flip`'s `:1340`
`O.ATuple{[1, 0]}` → `O.ABoolList{[True{}, False{}]}`.

**Why the second edit is no longer the route this brief refused.** The refusal was that
"`pr_flip` (`prepare.bend:277`, live at `:773`) and `tensor.bend:950` would still spell it
`ATuple`. **A fixture edited to agree is a diary, not a pin.**" Those two sites now spell
`ABoolList` — as do `G.flip` (`movement.bend:993`), `mxw_flip_new` (`movement.bend:1533`) and
`g_mv_flip` (`fold.bend:5514`) — and all four are measured compiling. The differ would then be
modelling what the port builds rather than what a hand-written fixture spells.

**I did not land it.** My scope is `tinybendygrad/` and `.agents/slop/argowner/`, and
`.agents/slop/graphcmp.bend` is neither. `handoff.py` builds, compiles (`ALL PROOFS CHECK`,
`WITHIN-LIMITS`) and measures it under my own directory so the next agent inherits a **number** and
not a **suggestion**. **One caveat they must check: `.agents/slop/graphcmp.bend` is listed in
`checks/differ.py:846 SUBSTRATE_INPUTS`, so editing it changes `substrate_digest()` and any pin
keyed on it.**

---

## 8. THE SIBLING CLASS (`boolexit`), because closing one member is not closing the class

The brief names five members. I checked each against the shape I just landed.

| member | sibling of the change just made | state after this unit | evidence |
|---|---|---|---|
| `bool`/`int` | **THE ONE I CLOSED** — CPython renders `True` where the port rendered `1` | **CLOSED in the port, measured**; the corpus is still `DEAD` until §7 | `n(b1,b0)`; `SHARED 5 → 6` |
| `int`/`float` | same normal form, `konst`/`f32bits` | **already handled** — `graphcmp.py:443 konst` normalises int→`i64` and float→f32 bits, and the port's `Const` is `CBool`/`CInt`/`CFloat` | `graphcmp.py:443`; 32 of 34 graphs agree |
| `str`/`bytes` | same, `AStr` vs `ABlob` | **still open, and declared.** `graphcmp.py:645` states the port's `Const` has **no bytes constructor** and `graphcmp.bend`'s `konst` has no bytes arm; the differ's own ledger row `y arg` says the content is compared but a bytes `CONST` is **not comparable** | `graphcmp.py:645`; `runs/graphcmp/D/D1-graph-*.txt` `LEDGER` block, `y` row, in all 34 |
| `None`/absent | **the same seam one level down** — `ANone` is both CPython's `None` and the arena bottom | **CLOSED by construction, measured**: `ANone` is one constructor and `ABad` is another, so absence and unreadable are already distinct values. `graphcmp.py:523` states the choice *for this reason* | `ops.bend` `ANone`/`ABad`; `graphcmp.py:523`; `differ.py:762` |
| `Path`/`str` | both `AStr`-shaped, upstream-typed differently | **NOT APPLICABLE as a silent-mismatch here, and NOT CHECKED**: there is no `Path` value in any of the 34 graphs. The port's `Arg` has no path constructor and neither does `Const`. **I am reporting an absence of evidence, not evidence of absence** | `Const` is `CBool\|CInt\|CFloat\|CInvalid` (`ops.bend:807`) |

**So: 1 of 5 closed by this unit, 1 already handled, 1 still open and declared, 1 closed by
construction, 1 out of scope and unchecked.** The class is not closed. The `str`/`bytes` member is
the one that would next pay, and it is the same shape of hole: a CPython value the port's type
cannot hold.

---

## 9. PRECONDITIONS HONOURED, AND THE INSTRUMENTS

- **`bend` runs.** Every one under `.venv/bin/python checks/bounded.py --seconds N --mb N --`, and
  **every verdict is the `[bounded]` TOKEN** — `WITHIN-LIMITS` on all of them; none was
  `KILLED-ON-MEMORY` or `TIMED-OUT`. No exit code was read as a verdict.
- **The sum-precondition.** From `.agents/slop/peakrss/census.rows`: the 35 census site files' peaks
  are ≤ **745 MB** (`uop/symbolic.bend`), and I ran **SEQUENTIAL** by construction — `closure.py`
  loops, `plant.py` loops, and the single-file checks ran one at a time. Concurrent sum = the largest
  single file, **745 MB against `hw.memsize` = 16384 MB**, i.e. **4.5 %**, far under the 60 % bar.
  The two heaviest single runs were `fold.bend` at 484 MB and the differ at 803 MB.
- **I waited for other agents.** Three times a `pgrep -f "bin/bend"` found another unit compiling
  (one gate loop held it); I polled and ran only when idle rather than racing it.
- **Path discipline.** `tinybendygrad/PROOF.bend` and `LAWS.bend` were **not** run: they are red at
  rest with 18 and 34 TODOs, this unit lowers neither, and running them would have measured a
  pre-existing red and called it a verdict about my change. **Stated rather than hidden.**
- **No `.txt` was created.** Every artifact is `.rows`, `.out`, `.err` or `.md`.
- **Nothing committed, nothing staged.** `git diff --cached --stat` is empty; the whole of my tree
  change is `git diff --numstat HEAD -- <my 6 files>` = 4+6+21+40+15+6 added lines.
  (`jj st` lists 22 modified `tinybendygrad/` files; **16 of those are other agents'** — this unit's
  6 are named in §2 and none of the other 16 appears in my diff.)
- **`.agents/TODO.md` was NOT ticked**, because my scope is `tinybendygrad/` and
  `.agents/slop/argowner/`, and `AGENTS.md`'s tick-off rule points at a file outside both. **The
  omission is deliberate and stated rather than silently dropped**; whoever lands §7 should add the
  row.
- **Files outside my scope were not touched**, with two deliberate exceptions, both read-only and
  both measured as such: `git show HEAD:<file>` into six files **I own** for the pristine control
  (restored, md5-proven), and `.agents/slop/graphcmp.bend` **opened for reading only** —
  `handoff.py` prints `SRC md5 UNCHANGED` after building the copy.

### Instruments (all `.py`, all `.venv/bin/python`, all under `.agents/slop/argowner/`)

| file | what it measures | population |
|---|---|---|
| `census.py` | the `Arg` match sites in the port | constructors **parsed** from `ops.bend`; files by `os.walk`; alias derived |
| `census-wide.py` | the same over the **whole repo** | `os.walk(root)` `*.bend` = 287 (own dir excluded), filtered by an import **regex**, not a list |
| `plant.py` | **falsifies the census**: add a ctor, diff the error sets | 35 site files, both passes |
| `closure.py` | **the compiler's** closed set, iteratively | 35 site files × 2 rounds |
| `handoff.py` | **builds, compiles and measures the out-of-scope fix** | one file, copied; SRC md5 printed |
| outputs | `census.rows`, `census-wide.rows`, `plant.out`, `closure{1,2}.out`, `mv-{PRISTINE,BEFORE,AFTER}.rows`, `mx-{BEFORE,AFTER}.out`, `flip-{PRISTINE,handoff}.out`, `differ-AFTER.out`, `handoff.out` | |

**Two of my own instruments lied to me and both are in §0:** `census-wide.py`'s import filter
reported `1 of 288` and I nearly believed it, and `plant.py` reported `35 files break` and would
have become "35 sites" in the report if I had not read the `Location:` on all 35 lines.