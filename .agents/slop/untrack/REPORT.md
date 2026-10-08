# `untrack` — the 459 "untracked" paths under `.agents/slop/`

Unit `untrack`. Python only (`.venv/bin/python`, 3.12.10). **Committed nothing, staged nothing.**
Touched only untracked paths under `.agents/slop/`, plus this directory.

**HEAD at every measurement below: `72d554611`. The tree is LIVE — five other units are writing.
Every number carries the HEAD it was read at, and the population moves.**

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG, FIRST, WITH THE BEFORE-VALUE

**My first census said `UNTRACKED: 1,085 paths`. The correct figure is 449.** I was counting
**directories**. The 636-path gap is not a measurement subtlety, it is a category error:
`git ls-files --others` reported **444** for the same scope and I could not reconcile the 647
difference until I asked whether the extra paths were files at all — **they were not one.**

Two separate defects, both mine, both caught before anything was deleted:

| my first cut | defect | corrected |
|---|---|---|
| `os.walk` `dn + fn` → **1,085** | a DIRECTORY is not a FILE; the tree lists files and never dirs, so no `ls-files` output can contain one | **449** files + **148** dirs, reported separately |
| `dir not in owned` to test a dir | the tree holds FILES, so almost every directory looks unowned | a directory is unowned iff **no tracked path lies beneath it** → **148**, not 647 |
| pyc-source check `dirname(p)` | **looked for the source INSIDE `__pycache__/`**, so every cache read as an orphan | **46 orphaned** → **3 orphaned**, source is in the cache's PARENT (PEP 3147) |

The third one matters most: I had a delete list of 46 and the check that was supposed to clear them
was **a check that cannot fail**. It reported 46/46 orphans; the truth is 3.

---

## 1. THE CENSUS, REPRODUCED — AND IT REPRODUCES THE BRIEF

`.agents/slop/untrack/census.py`. Tree from `git ls-tree -r HEAD`, disk from `os.walk(followlinks=False)`,
every entry compared as `bytes`.

```
SCOPE          : paths under .agents/slop/, at HEAD 72d554611
OWNED-IN-SCOPE : 4270 tracked paths
UNTRACKED FILES: 483 paths, 10.16 MiB          <- THE POPULATION
UNTRACKED DIRS : 149 dirs holding no tracked path (23 empty)
SYMLINKED DIRS : 7 under scope, contents counted by NEITHER side
OWNED-ABSENT   : 46 tracked paths in scope not on disk
```

**The per-directory figures match the brief EXACTLY** at the read where the total was 449:

```
citeresolve 16 · livenum 22 · modulerefuse 29 · unreachable 35 · orcdecide 24 · synonyms 24 · boolexit 15
```

So the inherited population was **FILES**, right all along, and **only its total is stale**:

| read | total | HEAD |
|---|---|---|
| inherited | 459 | — |
| mine, first correct | **449** | `6e6725d3b` |
| mine, final | **483** | `72d554611` |

**449 vs 459 is 10 files in an hour of a live tree, and the bytes agree (9.11 MiB vs "9.0 MB"), so
the two censuses are the same census.** Quote the number with its HEAD or not at all.

### The three corrections, each measured

1. **`comm` over two independently-sorted lists is not a set operation.** Both sides are read as
   `bytes` and compared as sets, so `LC_ALL` cannot matter. Reproduced.
2. **`find -type f` does not descend a symlinked directory.** Neither does `git ls-files --others`,
   and **neither does `git status`** — git models a link as a blob and stops. **7 symlinked dirs
   sit under `.agents/slop/`** (`figure2/plant/{broken,real}/.agents`, `rf2root/{LAWS,mixin,runtime,
   codegen,uop}`) and their contents are counted by **neither** side, so the census is a strict
   undercount there and says so rather than pretending.
3. **An untracked path is not a file.** `git ls-files --others` returned 444 where my first walk
   returned 1,091; the 647 delta was directories. There is no single number for "untracked paths".

**THE CENSUS IS INDEX-IMMUNE BY CONSTRUCTION, AND THAT IS WHY IT IS THE STABLE NUMBER.** Measured
while the index was armed (below): `git status --porcelain -uall` under `.agents/slop/` read
**344, then 420, then 343** across my session. `git ls-tree -r HEAD` read **4,270** every time.

---

## 2. THE CLASSIFICATION — AND THE FINDING THAT INVALIDATES THE BRIEF'S PREMISE

`checks/unowned.py` already computes reader / generator / owner from `HEAD`, and separates a prose
mention from an execution site. **I loaded it by path rather than reimplementing it.** The four
checks it does not do — jj ownership, plant fixtures, on-disk generators, PEP 3147 — are added and
each is declared, none is a list.

### THE SET IS 80% JJ-OWNED AND IN FLIGHT

| of the **483** untracked files under `.agents/slop/` | count |
|---|---|
| owned by `jj file list -r @` — **pending, will be committed** | **388 (80.3%)** |
| owned by `git ls-tree -r HEAD` | **0** |
| **owned by NEITHER VCS** — the only real candidates | **95** |

`git ls-tree -r HEAD` is the right instrument for *the tree*, and it is the **wrong** instrument for
*ownership* in a Jiujitsu workspace. `5bd39bcea` (jj change `vsutprllqolu`) holds **byte-identical
blobs** for these paths — spot-checked, `unreachable/d1-derive.rows` 10,307 B = 10,307 B,
`synonyms/charge.py` 5,073 = 5,073, `modulerefuse/argv.py` 2,998 = 2,998 — and
`git merge-base --is-ancestor 5bd39bcea HEAD` = **NO**.

**"Git does not own them; a clone would not have them" is TRUE today and FALSE the moment
`jj commit` lands.** 388 of 483 are `A` in `jj status`.

### The five classes, over the **95** candidates

| class | n | what it means here |
|---|---|---|
| **has-both** | **0** | not one is both written and executed by a committed site |
| **has-generator-only** | **1** | sibling `.py`/`.sh` names it; writer is not committed |
| **has-reader-only** | **15** | a committed file opens/executes it |
| **has-mention-only** | **35** | named in committed PROSE, never executed |
| **has-neither** | **44** | committed files say nothing at all |
| **is-a-plant-fixture** | **0** | `no-txt.py:excused_names()` loads five generator declarations; **none of the 95 is in any of them** |

**`has-both = 0` is not a bug in the table and the table is not degenerate:** over the same 95,
**51 cited / 15 executed / 0 written**. The zero is `written>0 = 0` — **no committed file writes any
of the 95** — because their generators are themselves untracked or jj-owned. That is the same blind
spot as §0, one level up: **the rule asks a question of COMMITTED files, and the files that would
answer it are not committed.**

---

## 3. WHAT I DELETED — 3 PATHS, AND THE RULE'S OWN LETTER NAMES 46

**All 44 of the current `has-neither` paths are `__pycache__/*.cpython-312.pyc`.** Under the rule's
letter every one is waste, because a bytecode cache's generator (CPython) and reader (CPython's
import machinery) are not files in this repository. **The rule cannot see the most obvious
generator in the tree.**

So the rule's mandated verification is what actually moves the set. At the 46-path read:

* **43 have their source `.py` still beside the cache**, and **43 of 43 sources are jj-owned**.
  Deleting those is clearing a build cache, not pruning research residue.
* **3 have no source.** A `__pycache__` `.pyc` without its source is **unimportable** — measured,
  not asserted: a directory holding only `__pycache__/m.cpython-312.pyc` raises
  `ImportError: No module named 'm'` under this repo's own `.venv/bin/python`.
* **Byte-identical twins: 0 tracked-or-jj, 0 within the waste set.**

### `VERDICT PASS  deleted=3 refused=43 of 46 the rule's letter names`

```
.agents/slop/gitinput/__pycache__/blastradius.cpython-312.pyc   source absent
.agents/slop/gitinput/__pycache__/plant.cpython-312.pyc         source absent
.agents/slop/quiesce/__pycache__/snapshot.cpython-312.pyc        source absent
```

Honest recoverability: **none of the 3 is in any of the 6,239 git refs or any jj change, and all
three sources are gone too**, so the modules are unrecoverable either way. That is why losing the
caches costs nothing — not because the check said so.

---

## 4. WHAT I REFUSED TO DELETE, AND WHY

| refused | n | why |
|---|---|---|
| jj-owned and in flight | **388** | `jj status` lists them `A`; deleting a pending commit's content is a mass-delete, which is what `gates/msgdiff-gate.py` REFUSES a message for |
| has-reader-only | **15** | a committed file executes them (`commentpass/README.md` 12 exec sites, the 11 `gatehealth/**/gate.bin` at 10 each, `elf/REPORT.md` 2) |
| has-mention-only | **35** | `e2epy/fixtures/*/.venv/bin/python` ×19, `helpers-tc-gate.bin` 12 cites, `notxt139/differ.py.orig` 5. **A prose mention is not a reader, so by the rule's letter these are waste — and deleting a file a committed report names is how a report becomes a lie.** Kept. |
| `citeresolve` | **16** | see below |
| live `__pycache__` | **43** | source `.py` present and jj-owned |
| **the index** | — | see §5 |

### `citeresolve`'s 2.4 MB — decided by the rule, and the brief's premise is wrong

**All 16 files are jj-owned. NONE is waste, and size was never the question.** But the brief's
stated reason is false and worth correcting:

> *"`citeresolve`'s 2.4 MB is derived `.tsv` written by **committed** `classify.py`/`hist.py`"*

**`classify.py` and `hist.py` are NOT committed.** They are in the jj working-copy change
(`own=jj@`), which is why `unowned.py` — which reads `HEAD` — reports `wrt=0` for `hist.tsv`. The
generator exists; it is simply invisible to an instrument that asks the tree. `hist.tsv` carries
**682 committed citations**, `classify.py` has 2 execution sites, `REPORT.md` 58 citations.
Refused. Had it been unowned, it would have scored has-reader-or-better on 3 files and been kept
anyway.

---

## 5. **THE INDEX IS ARMED RIGHT NOW** — 977 ENTRIES, AND THE DETECTOR IN HEAD'S OWN COMMIT MESSAGE REPORTS ZERO

Measured, and **I did not touch it**:

```
index entries carrying the empty blob e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 : 977
  of those, with NON-EMPTY content on disk (the destroying shape)                  : 422
  git diff --cached --name-only                                                       : 0
  git commit --dry-run  ->  ?? entries only, nothing staged
```

The bulk is **another unit's** work: `unreachable` 26, `modulerefuse` 26, `orcdecide` 24,
`synonyms` 23, `livenum` 22, `exitzero` 20, `citeresolve` 16, `boolexit` 15 — **the brief's own
list.** 6 of the 977 are mine; I never staged them.

**THE FINDING: `git diff --cached` IS NOT A DETECTOR FOR `--intent-to-add` ON GIT 2.50.1.**
HEAD's commit message (`6e6725d3b`) names `git diff --cached` as the thing that would have shown
the eighth stale-index failure. **It reports 0 with 977 entries armed.** `git ls-files -s | grep " $E "`
sees all 977; `git status --porcelain` sees 437; `git diff --cached` sees **0**. A unit that checks
`$?` and the diff is looking at the one instrument that cannot fail here.

**It is currently benign** — `git commit --dry-run` shows only `??`, so a bare commit would carry
nothing. **AND IT IS STILL SWEEPING: the number of MY files carrying the empty-blob index entry went
7 → 12 between my first measurement and this line**, so the arming is an ongoing event and not a
snapshot. **I did not disarm it.** `git read-tree HEAD` is the documented remedy and it would
destroy 977 entries of another unit's staged work. That is a decision for whoever owns them, and
making it from here is the mass-delete the gate exists to refuse.

---

## 6. THE META-QUESTION, ONE LINE, WITH THE MEASUREMENT

> **No — not while it is the jj working area: 388 of the 483 untracked `.agents/slop/` files are
> owned by the jj working-copy change and would be committed by the next `jj commit`, so "untracked"
> there measures the VCS you ask, not the absence of an owner.**

`AGENTS.md`'s *"a path inside a swept tree is deletable while the gate still names it"* is **true and
is the wrong frame here**: it warns that a sweep can remove a named path. Measured, that risk is
**388/483 = 80.3% of this set**, and the frame that catches it is `jj file list -r @`, not
`git ls-tree`. The set that was actually prunable — owned by neither VCS — was **95 of 483 (19.7%)**,
and of those the rule's own verification cleared **3**.

---

## 7. FILES, AND WHAT I DID NOT DO

**Written (all untracked, all under `.agents/slop/untrack/`):** `census.py` `prune.py` `REPORT.md`
`census.rows` `census-from.rows` `class.tsv` `class.err` `pop-from.rows` `git-head.rows` `jj-at.rows`
`jj-parent.rows` `slop-untracked.rows` `unowned-slop.rows`.

**Not done, deliberately:**

* **`.agents/TODO.md` not ticked.** `AGENTS.md` asks for it; this unit's brief forbids touching
  tracked files. Handing the parent the line to add is cheaper than a mass-delete incident.
* **The index not disarmed** (§5) — not mine to reset.
* **`git add` never run.** Verified: `git diff --cached --name-only` = 0 and every one of my files
  is `??` or a stranger's intent-to-add entry.

**`checks/no-txt.py` → `rc=0`**, `CLEAN: no .txt anywhere the project owns, outside those named
exceptions`, five carve-outs each a generator declaration loaded by path. Re-run after the deletions.

**Did the tree already own the answer?** **Yes, and it should have stopped me earlier.**
`checks/unowned.py` (243 lines) already computes reader / generator / owner from `HEAD` and already
separates prose from execution. `checks/no-txt.py:excused_names()` already loads five plant
declarations by path. `checks/coindep.py:SKIP_DIRS` is already the shared skip set. **I added 2
scripts, not a classification** — the classification is theirs.

### Verdict tokens

| | |
|---|---|
| census reproduction | **PASS** — per-directory counts match exactly; total 483 vs 459 is tree drift, not a different population |
| prune rule, applied | **PASS** — `deleted=3 refused=43 of 46` |
| `checks/no-txt.py` | **PASS** — `rc=0` |
| index | **REFUSED** — 977 armed entries, not mine to reset |
| the 449/459/483 totals | **DEAD as a bare number** — three readings in one hour; every one of them is only meaningful beside its HEAD |