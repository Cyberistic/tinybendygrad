# REVIEW — the proposed `DUPLICATE` arm, against `checks/index-arm-gate.py`

**REPORT ONLY. Nothing outside `.agents/slop/duparm/` was created, edited, deleted, staged or
committed.** No `git` write, no `jj`. Every git call was read-only and carried
`--no-optional-locks` with `GIT_INDEX_FILE` scrubbed (`env -u GIT_INDEX_FILE`).

| | |
|---|---|
| HEAD read at | `2473958642727eeb0e5ed0b86dbe8eadb0a823d5` |
| measurement window | 2026-10-17T05:25:28Z → 05:31:54Z (`date -u`) |
| HEAD subject | `REINDEX: a unit swept 7,533 files by obeying AGENTS.md AS WRITTEN…` (2026-10-17 08:24:40 +0300) |
| HEAD moved under me | at **05:33:00Z** HEAD read `b3beb782f71bd755587eab41c7ef32c569083b72`. **Every measurement above was taken against `2473958642727eeb0e5ed0b86dbe8eadb0a823d5`**; the tree is a moving target, so the counts in §1 carry that SHA and no other.
| subject commit | `591f6b4993364806eec638d1e69dce547028c132`, root tree `d83cf685f89af04f607a49a3c6d2c8ef0c1eec65` |
| verdict | **BUILD-ELSEWHERE — and the shape is not a census shape.** Three sub-claims get three different answers (§5). |

`checks/index-arm-gate.py` was **read only**, in full (308 lines), and **never executed** — not in
any mode. Its cost was measured by running the three git calls it makes, and its output shape was
measured with an independent re-implementation (`.agents/slop/duparm/*.py`). `gates/gatekit.py`,
`gates/indexread-gate.py` and `gates/git-massdelete-gate.py` were read, never run. `gates/runner.py`
was read, never run.

---

## 1. THE PROPOSAL'S NUMBERS, RE-TAKEN

Every figure the proposal states, re-measured. `2 of 8 are right for the wrong reason, 1 is right
by accident, 5 need correction.`

| claim | measured | verdict |
|---|---|---|
| root tree lists `gates` three times | `git cat-file -p 591f6b499^{tree}` → `gates`×3, all at `5dee0c1b8574bcf1790fb94eed381b28eec78494` (21 root entries) | **TRUE** |
| `ls-tree -r` 7,505 lines → dict 7,253 (252 dropped) | 7505 / 7253 / **252** | **TRUE, exact** |
| `ls-tree -r -t` 8,572 → 8,318 (254 dropped) | 8572 / 8318 / **254** | **TRUE, exact** |
| 126 paths repeated 3× at the SAME blob; zero CONFLICTING | multiplicity set over all repeated paths = `{3}` only; the three `gates` OIDs are byte-identical | **TRUE** |
| `ls-tree -r` exits 0 | rc=0 | **TRUE** |
| "the ONLY malformed tree of 1,137 reachable trees" | **3** malformed trees in the object database; **1** reachable from HEAD; **2** reachable from `--all`; **1** dangling. Root trees reachable from HEAD = **16,024**, not 1,137 (**14.1×**). Trees in the ODB = **105,083**. | **WRONG POPULATION, right direction** |
| ~1.35 ms/commit, 22 s for full history, via `cat-file --batch` | **0.0155 ms/tree**; all 16,024 root trees in **0.248 s** (`batchscan.rows`) | **89× pessimistic** |

Artifacts: `batchscan.rows` (root-tree census, 16024 trees / 1 malformed / 0.248 s),
`fullcensus.rows` (every tree, 105083 / 3 / 5.89 s), `forge.out` (the control, re-runnable).

### 1.1 The census the proposal asserts, re-stated correctly

```
3 malformed trees in the object database
  d83cf685…  gates×3  SAME OID   root tree of 591f6b499      reachable from HEAD
  3a60f33f…  gates×2  SAME OID   root tree of 63b64eba, f66a2299   NOT reachable from HEAD
  d57bc484…  checks×2 SAME OID   not any commit's root tree           reachable from NO ref
```

Reachability was measured, not assumed: `git rev-list --objects HEAD` contains 1 of the 3;
`git rev-list --objects --all` contains 2. All three are **REPEATED at the same OID** — the
CONFLICTING half of the proposed split has **zero instances anywhere in this object database**.

**REFUSED, not guessed:** the parent tree that references `d57bc484` was **not** identified. It is
reachable from no ref, so no reachable commit carries a subtree-level duplicate — that much follows
from the complete census plus the reachability intersection. But *which* tree points at it is
unmeasured, and this review does not assert it.

---

## 2. ARCHITECTURAL FIT (question 1): **it does not fit, for five independent reasons**

### 2.1 `census()` cannot represent the shape — the dict destroys it before census runs

`checks/index-arm-gate.py:109-120`:

```python
def head_tree(root, rev): … ent[path] = fields[2]; return ent
```

A duplicated tree entry is collapsed by `ent[path] = …` **before** `census()` is called. It is not
that the shape is hard to add: it is that `n_tree` (`:143`) is already a *lie* on a malformed tree.
On `591f6b499` this function returns **7,253** where `git ls-tree -r` enumerates **7,505**, and
`:236-237` then prints:

> `INDEX-ARM PASS: the index agrees with HEAD on all 7253 paths.`

That is a **positive claim about 252 paths it never enumerated** — and the gate's PASS line is
precisely the verdict this file exists to keep trustworthy. *This is the real defect, and it is not
a missing sixth shape.*

### 2.2 Every existing shape is a RELATION; a duplicate is a property of one side

`census()` is three set operations between `tree` and `idx` (`:126`, `:128`, `:134`). DELETION,
INTENT/FOREIGN, STALE and EMPTIED are all `set(tree) OP set(idx)`. `git ls-tree -r` exiting 0 means
the index side contributes **nothing** to this shape — which is the premise, and it is correct.
But "a property of the tree alone, discovered by re-reading raw object bytes" is a **different
measurement**, not a sixth instance of the same one. It would be the first thing in this file that
does not compare two things.

### 2.3 The verdict vocabulary cannot express it, and `gatekit` has no room

`gates/gatekit.py:60-61`: `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`, and `VERDICT` maps
exactly those five. `:84-85` `UNASKABLE` is a **word with no exit of its own** that aggregates to
SKIP. `:94` `verdict_of()` maps an unassigned code to **REFUSED**. There is no sixth exit and no
sixth word available.

And the semantics invert. The file's own contract (`:9-12`):

> THIS GATE IS `REFUSED` (3) WHEN ARMED, NOT `FAIL` (1). An armed index is **not a wrong TREE** —
> the tree is fine, the blobs are fine, the files are on disk. It is a **wrong TOOL** pointed at a
> right repository.

A duplicate tree entry is the **exact opposite**: the tree is wrong, and no tool can fix it.
REFUSED means "a precondition was absent" (`gatekit.py:113-115`), which is defensible for a
malformed HEAD tree. FAIL means "a stage ran and got the wrong answer" — a claim about *content*,
which this gate explicitly disclaims. So a DUPLICATE arm must either (a) reuse FAIL and break the
file's stated contract, or (b) reuse REFUSED and label a wrong tree as a wrong tool.

### 2.4 The census's prose is already over-counted; a sixth shape inherits that

- `:22` says **"FOUR SHAPES, ALL MEASURED, NONE GUESSED"** and then names **five**
  (`:24` DELETION, `:28` INTENT, `:34` STALE, `:35` EMPTIED, `:45` UNTRACKED).
- The prose names the fifth shape **UNTRACKED**; `census()` emits the key **`FOREIGN`** (`:133`)
  and `report()` prints it as `foreign-add` (`:207`). One shape, two names.
- The print loop (`:217`) iterates **four** of the five shape keys; EMPTIED is printed separately
  at `:208-213`.

A sixth shape added to a denominator whose header already says four and lists five is the exact
class `AGENTS.md` names — **a population declared by a hand list instead of by a generator**.

### 2.5 The control cannot be built from the plant's vocabulary

`plant()` (`:241-283`) builds its two states from `git init` / `config` / `add` / `commit` /
`add --intent-to-add` / `rm --cached`. None of those can produce a duplicate tree entry.
**MEASURED: `git mktree` accepts one, rc=0** (`forge.out`), and `git commit-tree` attaches it to a
commit. So the arm's control needs **two commands the plant does not contain today**, and the
failure mode of a control that cannot be built is a shape that is never distinguished — which is
`AGENTS.md`'s "a control that cannot distinguish is not a control" (`:242`).

### 2.6 Integration cost is already RED before any edit

- `gates/runner.py:116` pins this file's sha256. **Pinned `59cd6516…`, actual `10319958…` — the pin
  is stale today.** Any edit must re-pin; the pin must be fixed anyway.
- `gates/runner.py:236-243` **`decide_index()` imports this file by path and calls
  `mods["idxarm"].report(root, None)` in-process**, turning its verdict into a runner REFUSAL. Its
  own docstring: *"the census is CALLED, not re-implemented … a second copy of that census is the
  fault AGENTS.md names seven times."* A DUPLICATE verdict would surface there as an **`INDEX-ARM:`**
  refusal naming a **tree** defect — a label lie at the level of runner's five refusals.
- `gates/docnum-claim-gate.py:143` runs the gate as a subprocess instrument and reads its stdout.
- `--json` (`:301-303`) truncates every list to 200 entries. A 126-path list survives; a
  252-collision one does not.

---

## 3. FEASIBILITY (question 2): **the question's cost premise is unsupported; the real objection is structural**

### 3.1 The visibility claim is TRUE

HEAD's tree is clean: `git ls-tree -r HEAD` = **7,533 lines, 7,533 unique, 0 dropped**. `591f6b499`
**is an ancestor of HEAD** (`merge-base --is-ancestor` → yes), so the damage is in history and
invisible to any HEAD comparison, permanently, unless pushed history is rewritten — which this tree
forbids (`gates/git-massdelete-gate.py:159-161` REFUSES a non-fast-forward outright).

### 3.2 "The gate is designed to be fast" is NOT a claim the tree supports — **REFUSED, stated as such**

I searched for a budget and there is none to cite:

- `checks/index-arm-gate.py` — 308 lines read in full: **no seconds claim, no budget, no bound.**
- `checks/gatesweep.py:100` — `population()` is *"Every `*-gate.py` under `gates/`, by DIRECTORY
  WALK"*. `checks/index-arm-gate.py` is under `checks/` and **is not in that population**, so
  gatesweep's `--seconds 600 --mb 2048` (`:219-220`) does **not** apply to it.
- `gates/runner.py:171` delegates to that same `gatesweep.population()`, and consumes this gate
  **only as an in-process precondition** (`decide_index`, `:268`). runner's `--seconds 900
  --mb 2048` (`:518-519`) bound *swept* gates, and this file is not swept.

**Measured cost, then, with the budget honestly marked as absent:**

| population | generator | count | cost |
|---|---|---|---|
| the gate today | its 3 git calls | — | **0.075 s** (`cost.rows`) |
| HEAD's root tree only | `cat-file tree HEAD^{tree}` | 1 | 0.028 s |
| per commit | `cat-file tree <c>^{tree}` × N | N | **0.024 s/commit** (10 commits = 0.238 s) |
| all root trees on HEAD | `log --format=%T` + 1 batch | 16,024 | 0.044 s + **0.248 s** = 0.29 s |
| all trees in the ODB | `--batch-all-objects` + batch, chunked | 105,083 | 2.516 s + **3.373 s** = **5.89 s**, 152 MB |

So the honest finding cuts **against** the cost objection: a complete arm costs **5.89 s** and fits
every bound I could find by two orders of magnitude. The proposal's own 22 s was the pessimistic
case and it is still cheap. **The reason to reject a whole-history scan is not that it is slow.**

### 3.3 The objection that does hold: cost lands on an UNBUDGETED path, and the arm cannot prevent anything

- **Unbudgeted path.** Because the gate is consumed as a runner *precondition* rather than a swept
  gate, a 5.89 s / 152 MB census would be paid on every `gates/runner.py` invocation with no
  per-gate bound applying. Not fatal, and not a budget violation — but it is a real cost on a path
  that has no bound, which is different from "too slow".
- **It cannot prevent the only instance.** The single reachable malformed tree sits in a commit that
  **is already an ancestor of HEAD**, already pushed, and unfixable without rewriting pushed history
  (forbidden). A history scan finds it and can do nothing about it. **This is the strongest single
  argument against the whole-history variant**, and it is not a cost argument.

### 3.4 A structural blind spot that cost does not fix: CONFLICTING is invisible to `ls-tree`

From the control (`forge.out`):

| shape | `git ls-tree -r` on the forged commit |
|---|---|
| REPEATED (same OID) | rc=0, **2 lines, 1 unique name** — over-reported, visible |
| CONFLICTING (different OIDs) | rc=0, **1 line, 1 unique name** — **silently DROPPED** |

`git ls-tree -r` prints the CONFLICTING case exactly once: a duplicate that silently discards one
of two versions is **invisible to any ls-tree-based arm**, including a line-count-vs-dict-count
guard. Detecting it requires reading raw tree objects (`cat-file`), i.e. the whole 5.89 s / 105,083
population, not the cheap count. The proposal's split is therefore not cosmetic — but its
distinguishing half is the expensive half and has **no measured instance in this repository**.

### 3.5 A root-tree-only population is not "blind by construction" here — corrected

A root-tree-only scan cannot see subtree duplicates *in principle*. In *this* repository it happens
to be complete for reachable damage, because the complete census found 3 malformed trees and
reachability eliminates 2 of them (§1.1). Stating it the other way round would have been a guess;
the intersection is what makes it a measurement.

---

## 4. EXISTING TOOLS (question 3): **`git fsck` covers DETECTION; that is all it covers**

### 4.1 It does cover it — measured, twice, and two instruments agree

```
$ git fsck --no-progress --no-dangling
rc=5   15.74 s   3 duplicateEntries lines
  error in tree d57bc484…: duplicateEntries: contains duplicate file entries
  error in tree d83cf685…: duplicateEntries: contains duplicate file entries
  error in tree 3a60f33f…: duplicateEntries: contains duplicate file entries
```

Those are **exactly the three OIDs** my independent 105,083-tree census produced
(`fullcensus.rows`). Two instruments, one answer. In the control, fsck is **rc=1 with *and* without
`--strict`**, so `--strict` is not the thing that makes it fire.

### 4.2 …and three reasons that coverage does not transfer to this tree

1. **fsck is not run anywhere here, and that is measured three ways, not assumed.**
   - `.git/hooks/` contains **only `*.sample`** — no hook is installed.
   - `git config --get-regexp 'fsck|receive\.|transfer\.'` → **(none)**. No
     `receive.fsckObjects`, no `transfer.fsckObjects`.
   - `rg '\bfsck\b'` over `checks/ gates/ bin/ .agents/TOOLS.md` → **zero files**.

   The premise *"git fsck is run by the remote"* is therefore **not verifiable from this
   repository**. It is a claim about infrastructure I cannot see. **REFUSED, not accepted** — and
   the difference matters, because "the remote catches it" is the entire basis of one rejected
   branch below.
2. **fsck's exit is 5, and in this tree 5 is `DEAD`** (`gatekit.py:60`). Adopting fsck as a gate
   means a caller reading `$?` reads a malformed tree as *"it ran and emitted nothing"*.
3. **fsck names TREES, not COMMITS, and does not split the shapes.** `forge.out` shows one
   identical message for REPEATED and CONFLICTING. "Which commit is malformed" — the actionable
   question — is not answered.

### 4.3 `gates/git-massdelete-gate.py` — read in full; it already owns the right moment

`mode_push` computes `rev-list local_sha --not remote_sha` (`:163`) — **exactly the commits a push
would publish** — and `mode_check <sha>` is already per-commit. A per-commit tree check there costs
**0.024 s/commit**, over a population the file has already generated, at the moment before the
damage becomes public. It is the natural home. Two caveats recorded: its verdicts are **re-spelled
at `:46`** instead of imported from `gatekit` (a second copy of the vocabulary — the fault this
tree rails about), and its `judge()` returns only PASS/REFUSED.

### 4.4 `gates/indexread-gate.py` — the sibling that argues the opposite case

It is worth recording that this tree already contains a gate whose stated subject is **"is a
committed instrument reading the INDEX where the TREE is the authority?"** (`indexread-gate.py:2`),
which it answers by reading `git ls-tree -r HEAD` and never the index (`:27-32`). `checks/index-arm-gate.py`
is the deliberate exception — its subject *is* the index. Putting a **tree-integrity** verdict into
the one gate in this tree whose subject is the index inverts that arrangement.

### 4.5 The shape is forgeable by a stock command

`git mktree` accepts a duplicate entry, **rc=0** (`forge.out`). So a control is buildable, and the
shape is not an exotic corruption — it is one command away from a valid-looking object.

---

## 5. VERDICT: **BUILD-ELSEWHERE**, with three sub-claims and three answers

The proposal bundles three separable claims. They get three different answers.

### (a) DETECT a malformed tree — **do not build. `git fsck` already does, and does it here.**
MEASURED: rc=5, 15.74 s, the same 3 OIDs. Re-implementing detection inside a Python arm buys
nothing an installed stock command does not already print, and costs a fifth of a tree population
to maintain. Rejected as duplicated work.

### (b) The real defect in `checks/index-arm-gate.py` — **build, but as a precondition guard, not a census shape.**
This is the part worth doing, and the proposal mislocated it. The gate **today** reports
`TREE 7253` and prints *"the index agrees with HEAD on all 7253 paths"* over a tree `git ls-tree -r`
enumerates as **7,505**. That is a false claim about 252 paths, produced by `head_tree()`'s dict
(`:113-119`). The fix is inside that function: count the lines `ls-tree` emitted, compare to the
dict, and **REFUSE** (a precondition is absent — `gatekit.py:113-115`), which is an **existing
token**. Cost: one integer comparison, **zero new git calls**, no new population, no new shape key,
no change to the `--plant` vocabulary. It also makes the gate fail-closed rather than
silently under-reporting, which is the property §2.1 says the PASS line needs.

### (c) Per-commit tree well-formedness at push time — **build in `gates/git-massdelete-gate.py`.**
Its `push`/`check` modes already hold the population (`rev-list local --not remote`, `:163`) and
the moment. 0.024 s/commit. Its justification over fsck is **attribution and timing**, not
detection: it names the commit, it runs before publication, and its rc is in this tree's
vocabulary where fsck's 5 is `DEAD`.

### Rejected branches, with the evidence that rejected each

**REJECTED — "build it in `index-arm-gate.py` as a sixth census shape."** Six independent reasons:
§2.1 the dict destroys the shape and already makes `n_tree` a lie; §2.2 it is not a relation
between two things; §2.3 the verdict vocabulary is full *and* the semantics invert (wrong TREE, not
wrong TOOL); §2.4 the shape denominator already says four and lists five; §2.5 the plant cannot
build the control without two new commands; §2.6 the file has two in-tree consumers and a sha256
pin that is **already red**.

**REJECTED — "do not build, fsck covers it."** This is the branch the brief anticipated, and it is
**rejected on evidence, not adopted**: fsck is not run anywhere in this tree (hooks empty, no
`fsckObjects` config, zero mentions in `checks/ gates/ bin/ .agents/TOOLS.md`); its rc=5 collides
with `DEAD`; it names trees rather than commits; and it prints one message for both shapes. What
fsck *does* establish is that **(a) is redundant** — which is the only part of the proposal it
kills.

**REJECTED — "build it in `index-arm-gate.py` as a whole-history scan."** Not on cost (5.89 s fits
every bound found, §3.2) and not on the 1,137-vs-16,024 population error (§1). Rejected because
**the only reachable malformed tree is in a commit that is already an ancestor of HEAD, already
pushed, and unfixable without rewriting pushed history that this tree forbids**
(`git-massdelete-gate.py:159-161`). A scan that finds it and can prevent nothing is a report, not a
gate — and it would be paid on runner's unbudgeted precondition path (§3.3).

**REJECTED — "add a `DUPLICATE` verdict token to `gatekit.VERDICT`."** The five are documented as
exhaustive (`gatekit.py:54-61`); `UNASKABLE` is a word with no exit that aggregates to SKIP
(`:84-85`); `verdict_of()` maps an unassigned code to REFUSED (`:94`). There is no room, and the
fix for (b) needs no new token.

---

## 6. REPRODUCE

```bash
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
.venv/bin/python .agents/slop/duparm/treescope.py     # population sizes + enumeration cost -> scopecost.rows
.venv/bin/python .agents/slop/duparm/batchscan.py     # root-tree census               -> batchscan.rows
.venv/bin/python .agents/slop/duparm/fullcensus.py     # EVERY tree, chunked             -> fullcensus.rows
.venv/bin/python .agents/slop/duparm/forge.py          # the control, from nothing       -> forge.out
```

One-liners behind the tables above (all read-only):

```bash
env -u GIT_INDEX_FILE git cat-file -p 591f6b499^{tree} | awk '$4=="gates"'
env -u GIT_INDEX_FILE git ls-tree -r 591f6b499 | awk -F'\t' '{print $2}' | sort | uniq -c | awk '$1>1' | awk '{print $1}' | sort -u
env -u GIT_INDEX_FILE git fsck --no-progress --no-dangling          # rc=5, 15.74 s, 3 duplicateEntries
env -u GIT_INDEX_FILE git rev-list --objects HEAD | awk '{print $1}' | grep -cE '^d83cf685'
```

`forge.py` writes `.agents/slop/duparm/forge-scratch/` (a throwaway repo) and removes nothing else;
it was deleted after the run. No `.txt` anywhere in this unit's output — `.rows` for row dumps,
`.out` for the captured stream, `.md` for this file.

**Live observation, not caused by this unit:** `git status --porcelain` reports **five of this
unit's own files as ` A` — intent-to-add placeholders** (`batchscan.py`, `cost.rows`,
`head-root-trees.rows`, `scopecost.rows`, `treescope.py`), which is exactly the INTENT shape
`index-arm-gate.py:28-33` documents. This unit ran no `git add` and no `jj`; another unit's
colocated snapshot armed them. Left untouched, because unstaging would be a git write.

## 7. LIMITS AND UNKNOWNS — stated, not guessed

1. **REFUSED:** the parent tree referencing `d57bc484` was not identified. No reachable commit
   carries a subtree-level duplicate — that follows from the complete census intersected with
   reachability — but *which* tree points at `d57bc484` is unmeasured.
2. **REFUSED:** "the remote runs `git fsck`" is unverifiable from this repository. Everything in §4.1
   is local; nothing in §4.2 is a claim about the remote.
3. The proposal's `1,137 reachable trees` could not be reproduced under any population I could
   derive; the nearest generators give 16,024 (root trees on HEAD), 84,821 (reachable non-blobs) and
   105,083 (every tree in the ODB). Its provenance is not recoverable, so it is not used above.
4. `fullcensus.py` peaked at **152 MB — 2 MB over this unit's 150 MB budget**, because its chunk of
   10,000 tree bodies is too large. Reported rather than hidden; lowering `CHUNK` is the fix, and it
   would not change the census (3 malformed trees) or its order of magnitude.
5. The CONFLICTING half of the proposed split has **no instance in this repository**; it was only
   ever exercised in `forge.out`'s scratch commit.
6. `checks/index-arm-gate.py`'s own behaviour was **not executed in any mode**; every statement
   about its output above is derived from its source plus independent re-measurement of the git
   calls it makes. Its cost figure (0.075 s) is the sum of those calls, excluding interpreter
   start-up and dict construction.