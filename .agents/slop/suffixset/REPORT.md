# `suffixset` — the suffix set that was the population

Unit `suffixset`. Read at **2026-10-08T14:57Z** against `HEAD` `72d554611`.
Tree under concurrent agents; every number below carries its scope and its timestamp.

**One file changed: `gates/gates-pop.py`.** No commit, no staging. `gates/gates-pop.ledger.tsv`
restored byte-exact (`sha256 494a3482…`) after each run that writes it.

---

## 0. MY OWN MEASUREMENT WAS WRONG FOUR TIMES. THE BEFORE-VALUES ARE HERE FIRST.

Every one of these was found by the instrument disagreeing with itself, not by a reviewer.

| # | What I measured first | What was true | How it was found |
|---|---|---|---|
| 1 | "`git ls-files` holds **7095** against a tree of 6680 — the index is armed" | **Both read 6680** four commands later, no edit by me | I re-ran it instead of citing it. **A single reading of a tree under concurrent agents is not a property.** The census now reports the index count as an observation with no verdict, and every other number comes from `ls-tree` or the filesystem. It read **7095, then 6680, then 7121** across this session. |
| 2 | `checks/*` holds **3 no-extension files**, 1 tracked | `Path('.err').suffix` is `''` — **a leading dot starts no suffix** — so my `(none)` bucket mixed one extensionless executable shim with two dotfiles | `suffix_of()` was rewritten by hand. `gates-pop.py` now carries the same helper, and says why. |
| 3 | First census: **175 candidates**, no verdicts | **61.** 175 was the count of *shaped* collections; the population is shaped-**and**-standing-in, and the two are separated by reading use sites off the AST, not by shape | `checks/differ.py:13 LITERALS`, `tinygrad/runtime/autogen/am/regs.py:__all__` and `.agents/slop/toolsledger/probe.py:EXTS` have the same word-shape and opposite roles. **A SHAPE ALONE CANNOT TELL THE TWO APART.** |
| 4 | Section C "census's own blind spot: 13129 unreadable collections" | Noise — it counted every non-literal module assignment | Dropped. It was reporting my own sloppiness at a scale that read like a finding. |

And three more that were bugs **in the fix itself**, all caught before they reached the ledger:

- `if py is not False` — `is_python_entry` returns the **string** `"UNPARSEABLE"`, and `is not False`
  is true of it. 137 `.rows` fixtures answered `py-lib` and the new OPAQUE bucket stayed at **zero**
  while the module count went to 190. **A test that cannot fail looks exactly like a test that passes.**
- `ast.parse` **succeeds on JSON** — `{"a": 1}` is a valid Python dict display. `checks/census.json`
  (1.2 MB) and `checks/dup-census.json` (797 KB) answered `py-lib`, costing 893 ms and 550 ms.
  **"It parses" is a proof of syntax, not of programhood.**
- `import\s+[\w{*]` read **39 `gates/*.bend` drivers as `js-main`** — **bend has its own `import`
  keyword**. A shape that also matches another language is not a narrower population, it is a wider one.

---

## 1. THE DIVERGENCE, WITH DENOMINATORS

Denominator: a directory walk (`iterdir` + `os.lstat` + `S_ISREG`) of the two gate homes at depth 1,
compared against the tuple read **by path from `git show HEAD:gates/gates-pop.py`** — not off the
live subject, because the fix removed it, and a census reading the running module would now report
a divergence of **zero** and call the defect repaired when it is only unmeasured.

```
THE DECLARATION UNDER TEST, read by path from `git show HEAD:gates/gates-pop.py`: ('.py', '.sh')
   and read off the LIVE subject: ABSENT -- the fix removed it

checks/  walk sees  241 file(s); the tuple admits   84;  157 DROPPED unread
gates/   walk sees  133 file(s); the tuple admits   90;   43 DROPPED unread
   declared-but-ABSENT in gates/: .sh -- a tuple member that matches nothing here
TOTAL across both homes: walk 374, tuple admits 174, DROPPED 200
```

**It is not only `.mjs`.** Fifteen distinct suffixes were dropped unread, and two of the dropped
were **true members the walk finds and the tuple could not reach at all**:

- **`checks/nan_census.mjs`** — a tracked ES-module census driver (`node nan_census.mjs <workdir>`),
  the file `checks/gate.py:200` and `checks/e2e.py:428` reach for a `.mjs` driver. **1 tracked.**
- **`checks/bend`** — a tracked **extensionless executable `#!/bin/sh` shim** onto the reference
  checkout. `entry_reason()` read it, when called directly, as a correct `sh-dispatch`. It was not
  wrong; it was unreachable. **1 tracked.**

**And the tuple was not consistent with itself.** Clause IV of the same file loads `gates/gendirs.py`
by path, and `gates/gendirs.py:70 SOURCE_SUFFIXES` is `(".py", ".sh", ".mjs", ".js")`. So **clause I
and clause IV of one instrument disagreed about what a source file is, in one file** — while that
file's own clause IV states that two instruments holding two lists *"have no authority over each
other."* **THE CLASS WAS INSIDE THE CENSUS OF THE CLASS.**

### 1b. The classifier was a second instance, one layer down

Dropping the tuple was **not** sufficient. `entry_reason()` read `p.suffix == ".py"` and sent
**every other suffix to the shell tokenizer**, so admitting a file was not the same as
understanding it: `nan_census.mjs` would have been relabelled `sh-lib` — a census of JavaScript by
a shell grammar, which still adds up.

**`$0` is not a shell token either.** `SH_SELFREF` was `\$\{?0\b`, and `$0` is **bend's CPS state
variable in emitted JavaScript**: `tinybendygrad/runtime/webgpu_call.mjs:315` is
`const _cs_0 = $0;`. Measured as a tightening, not a guess — the quoted-or-braced form matches
**17 of 17 `checks/*.sh`** (zero lost), keeps `checks/bend`, and drops both emitted-JS false
positives.

---

## 2. THE FIX: A DIRECTORY WALK PLUS THE TREE'S OWN WRITE SITES

`discover()` walks **every regular file** in a home. `entry_reason()` asks each one what language it
is **in**, by content: `JS_MODULE` (ESM syntax, conclusive — neither Python nor shell can spell it)
→ `ast.parse` → `SH_SHEBANG` / `SH_SELFREF`. **`p.suffix` appears nowhere in `entry_reason()`.**

A file no grammar can read is **not silently bucketed**: it is counted OPAQUE and printed by
extension, so a tree that grows a language **moves a number** instead of quietly losing a subject.

```
I  DISCOVERED 136 entry point(s) under checks/gates/ (+42 module(s) with no entry guard,
   196 file(s) OPAQUE -- readable by no grammar in this instrument, which is a DENOMINATOR)
     opaque .rows     140 file(s)      opaque .bend   42 file(s)
     opaque .json       4 file(s)      opaque .tsv     4 file(s)
     opaque .md         2 file(s)      opaque (none)   1 file(s)
     opaque .bin        1 file(s)      opaque .err     1 file(s)
     opaque .dylib      1 file(s)
entry reasons: {py-main: 117, sh-selfref: 15, sh-dispatch: 3, js-main: 1}
```

**Two new members, both from the walk:** `checks/bend` → `sh-dispatch`, `checks/nan_census.mjs` →
`js-main`. Ledger delta **4 added, 0 gone, 0 changed (132 → 136)**; two of the four are other
agents' gates that were already pending before this unit started. `ledger-delta.rows` holds the four.

### A regression I caused, and paid for outside the signature

The first version returned a 3-tuple and `gates/gate-surface.py:280` hands `discover()`'s result
straight to a two-value unpack — **`ValueError: too many values to unpack`, rc 1 in a gate I was told
not to edit.** `discover()` now keeps its **two-value arity as a contract**; the third bucket leaves
through `opaque()`. **A fix that breaks a caller is not a fix, it is a trade, and the trade has to be
paid somewhere else.**

### Plant 6's denominator was the same defect, in the file I had just fixed it in

`live_sh = sorted((HERE.parent / "checks").glob("*.sh"))` named **one home by hand and one suffix**,
so `union == len(live_sh)` was `17 == 17` over a population it had chosen — **the assertion agreed
with itself by construction**, which is `artefacts_ok()`'s shape. Now walked over both homes:

```
narrow=3 selfref=21 union=21 of 21 walked shell entries -- 18 gates only the SECOND token can see
```

### Residual, named not papered over

A JavaScript file with no ESM syntax whose whole body is also a valid Python program is read by the
Python grammar — `console.log("REPRO stub: stage 3 gpu");` is a valid `Expr(Call)`. **Counts 3 of
the 19 `.mjs` in this tree**, all three 40-byte stubs under `.agents/slop/`. There is no test for it
that is not a list of JavaScript spellings, and a list of spellings is the defect. A file it
mislabels is **counted as a module, never dropped**.

---

## 3. THE SIBLING CLASS, TREE-WIDE, BY DISCOVERY

Denominator: **AST over 1682 tracked `.py`** (0 unreadable on disk), classified by **ROLE** — the
call each use site passes the constant to — not by shape.

**60 candidates, 44 STANDING-IN** (`sibling.rows`). Live, named by the brief:

| instrument | verdict | why |
|---|---|---|
| **`gates/gates-pop.py:141 SUFFIXES`** | **STANDING-IN — the defect** | filtered the enumeration. **REMOVED.** |
| **`gates/gate-surface.py:299 walk_control`** | **STANDING-IN — now the sharpest one** | `fn.endswith((".py",".sh"))` over a recursive `os.walk`. After this fix `discover()` sees **178** where the walk sees **176** — **the relation inverted** — and `:424` prints only `control - disc`, **never `disc - control`**, so the two new members are now in the population, invisible to the control, and **the control cannot say so.** |
| **`checks/no-txt.py DECLARATIONS`** | **NOT PRESENT — gone** | AST over its 247 lines: `ROOT, SKIP, SKIP_PREFIX, GRAPH_D, PLANT, RENAMER, VERDICTS, PLANTS`. It loads `differ.declared()` by path. **NAMING, and correct.** |
| **`checks/differ.py` artifact suffixes** | **NAMING, not a defect** | `artefacts_ok()` globs `*.txt` — and **MEASURED: that glob matches 175 real files in `runs/graphcmp/D`** (241 files total; `*.rows` matches 0). Consistent with the `differ.declared()` carve-out, which is why `checks/no-txt.py` is `rc=0`. |
| `checks/no-txt.py SKIP_PREFIX` | STANDING-IN, **defensible** | a *skip* set names what to EXCLUDE. Worth stating: skipping `tinygrad` means `.txt` under upstream `tinygrad/` is invisible to the `.txt` census. |

**My own census is blind by construction, and the number says so.** Section **E**: **159 inline call
sites** pass an extension shape that was never a named constant — `endswith((".py",".sh"))`,
`glob("*.txt")`. **That is the same blindness one level down** that `checks/sweep.py`'s
extension-gated rule had, and it is why section C reported nothing about `gate-surface.py` or
`differ.py`. An inline literal is the most anonymous form of a suffix set: no name to grep, no line
to pin. Section **D** covers the third population — **15 lines over 261 tracked shell files** name
a `-name '*.txt'` shape, which no Python AST can see at all.

## 4. DID THE TREE ALREADY OWN THE ANSWER?

**Yes, in two places, and both were cited as evidence rather than used as a source.**

- `.agents/slop/capstream/refsplit.py:23 CODE_EXT = (".py",".sh",".bash",".mjs",".js",".cjs",".ts",".bend")`
  — the brief's `capslre`; **already includes `.mjs`**. `gates/gendirs.py:70` includes it too.
- `gates/README.md`'s retirement note on shell gates — and `gate-surface.py:146`, whose own prose
  quotes the very tuple I removed (`".py", ".sh"`). **A stale citation, in a file I may not edit.**

So this was never "no instrument knows about `.mjs`". It was **four instruments that know, and one
that decided**, with none declaring the others.

## 5. VERDICTS AND DENOMINATORS — every one with its scope

`gates/gates-pop.py --plant` — **PASS, rc 0, 10/10** (was 9/9; plant 9 is new), plus the
inertness assertion: **the live ledger was byte-identical afterwards.**

| check | scope | before | after |
|---|---|---|---|
| `checks/no-txt.py` | whole owned tree | rc 0, CLEAN | **rc 0, output byte-identical** |
| `checks/nl-gate.py` | 205 shared rows | rc 0, `AGREE 205/205` | **rc 0, `AGREE 205/205`, byte-identical** |
| `gates/gate-surface.py --report` | 136 discovered entries | rc 0, **`SHELL HALF: 17`** | **rc 0, `SHELL HALF: 18`** |
| `gates/msgdiff-gate.py range --since=2026-10-06T12:00` | commits in range | rc 3, `215 — 212 PASS, 3 REFUSED` @14:41Z | rc 3, **`216 — 196 PASS, 20 REFUSED`** @14:57Z |

**`SHELL HALF` moved 17 → 18 and that is the fix working, not a regression.** The roster gained
exactly one member — **`checks/bend`** — and all 17 `.sh` files are unchanged. An extensionless shim
is now in the population, which is the entire claim.

**`msgdiff-gate` did not hold the brief's 148/147/1, and neither reading is mine.** This unit
commits nothing, so a message-vs-diff gate cannot move because of it; `gates/msgdiff-gate.py` is in
the working diff and another agent is editing it, and the count moved 212→196 PASS across 16
minutes of their commits. **Quote that number with its timestamp or not at all.**

`gates-pop --ledger write` remains **RED (rc 1)** both before and after, for the same pre-existing
reason: `45 name a root, 20 assert it, 1 resolve outside the repo`, unchanged at 136 entries. The
run is **not vacuous** — 136 entries, 196 opaque, and a 4-row ledger diff — but it does not go green
and this change did not make it green.

## 6. LEFT UNTOUCHED, AND WHY

`checks/`, `tinybendygrad/`, `gates/gate-surface.py`, and `gates/msgdiff-gate.py` are **byte-identical**
(mtimes `Oct 3 15:09`, `Oct 8 07:26`, `Oct 8 00:07`). **`gates/gates-pop.ledger.tsv` was restored
byte-exact** after every run that writes it; the four ledger rows belong to whoever lands this.

**`gates/gate-surface.py:299` is still a suffix set and `:424` is still a one-directional diff.**
That is the next unit's, and it is the one place where this fix's new members are currently
uncountable by the only control that exists.

**`discover()` still walks depth 1.** `gates/oracles/beautiful-mnist-oracle.sh` and
`gates/oracles/mixin-op-oracle.sh` are reported WALK-ONLY by `gate-surface` — a residual in the
*directory-shape* half of the same class, left because changing it moves a number in a gate I may
not edit.

## 7. INSTRUMENTS

| file | what |
|---|---|
| `suffix-census.py` | sections A–E; the pre-fix tuple read by path from `git show HEAD` |
| `divergence.rows` | per-home, per-suffix, with the tracked count on every row |
| `classifier.rows` | what the old classifier answered for each of the 200 dropped files |
| `sibling.rows` | 44 STANDING-IN constants, by AST use-site |
| `inline.rows` | the 159 inline extension literals section C cannot see |
| `ledger-delta.rows` | the 4 ledger rows for the landing unit |
| `census.out`, `*-plants.out`, `final-*.out` | captured streams |

No `.txt` was created. Commits: **none**. Staged: **nothing**.