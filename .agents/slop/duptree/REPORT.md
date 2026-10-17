# DUPTREE — how many commits in this repo have a tree that DUPLICATES a path entry

**MEASURED 2026-10-17T03:44:00Z · PINNED BASE `d0d7ec47086e6a29a078f0e828f81a4f0b05e8da` ·
HEAD AT MEASUREMENT `311e476575e5f043243be6f1a9adaec7ed2db72c` · HEAD AT FIRST READ
`08554e4097b25bf2ccff295996725fee14825ece` (HEAD moved 3× during this task; every number below
is either pinned or re-stamped)**

Instrument: `.agents/slop/duptree/dupscan.py` (a measurement, not the gate — the gate is
PROPOSED in §5 and **NOT IMPLEMENTED**). Control: `.agents/slop/duptree/control.py`.
Rows: `.agents/slop/duptree/dups.rows`.

> **`AGENTS.md` WAS REVISED UNDER THIS TASK, AND IT OVERTURNED THE MECHANISM §3 IS ABOUT.** I first
> read it carrying `a2da165`'s concurrency claim as the supported explanation. The live `AGENTS.md`
> now records that claim as **MEASURED UNSUPPORTED** (`race.py`: 0 sweeps in 36 shared-index
> concurrent commits) and names a different route. **§3 IS WRITTEN AGAINST THE NEW TEXT, AND THE
> CHANGE IS MARKED IN PLACE RATHER THAN SILENTLY APPLIED** — because a document that restates a
> superseded document is one witness, not two, and this one disagrees with itself across a revision.
> **WHAT CHANGED IS BELOW, IN `AGENTS.md`'s OWN WORDS:**
> *"SO THE **ONLY** ROUTE **MEASURED** THAT SWEEPS IS **A **COMMIT **WITH NO PATHSPEC** … THE
> PATHSPEC IS THE BOUNDARY AND A SHARED INDEX IS WHAT PUTS ANOTHER UNIT'S WORK **INSIDE** IT"* and
> *"EXACTLY **`1` IN `62` (`1.6%`)** SWEPT (`591f6b499`, repaired by `02329daf`)"*.

---

## 1. THE ANSWER

**`591f6b499` IS THE ONLY ONE. RATE 1 / 16,176 = 0.0062%.**

| | |
|---|---|
| POPULATION | `git rev-list <pin>` = **16,176** commits |
| SCANNED | **16,176** — 100%, not a sample of it |
| COVERAGE PROOF | union of 5 `--max-count/--skip` windows `sort -u` = **16,176** = the population exactly |
| DUPLICATED COMMITS | **1** |
| DUPLICATED PATHS | **1** (`gates`, ×3) |
| ON ORIGIN | **no** — `git merge-base --is-ancestor 591f6b499 origin/master` **rc=1**; origin/master is `52d77134b` |
| IN THE REQUESTED 500-WINDOW | 1 / 500 = 0.2% |
| COST | 16,176 root trees in ~22 s across 5 processes, peak RSS **25 MB** (`.agents/slop/duptree/chunk0.time`) |

**THE COVERAGE PROOF MATTERS AND COST ME TWO RUNS TO GET RIGHT.** My first seam check compared
`chunk_i NEWEST` against `chunk_{i+1} OLDEST`, which is the wrong pair — a mismatch there proves
nothing, because those commits are 4,000 apart. Comparing the *union of the populations* against
the *population* is the check that carries the claim, and it came out exactly equal. **A COUNT
FROM A CHUNKED SCAN IS NOT A DENOMINATOR UNTIL THE CHUNKS ARE PROVEN DISJOINT-AND-COMPLETE.**

### Two corrections to the prior report (`08554e409`, `.agents/TODO.md:466-489`)

Both are measured, both are in the tree's own records, and both change what this class is:

1. **"lists `gates` TWICE" → it is listed THREE TIMES.** `TODO.md:469` and `08554e409` both say
   TWICE. MEASURED: **3** entries for `gates`, all three at the **same** OID `5dee0c1b`. This does
   not change the verdict, but "twice" is a number someone measured and wrote down, and it is wrong.

2. **"THE DEFECT IS SPECIFIC AND SMALL" → the same tree also DROPS 9 TOP-LEVEL PATHS.** Against its
   parent `3173198bd`, whose root has **28** entries, `591f6b499`'s root has **19 distinct** and is
   **missing**:

   `langs` · `mkdocs.yml` · `opencode.json` · `pyproject.toml` · `serve_docs.sh` · `spec` · `sz.py` · `tools` · `uv.lock`

   That is **36 files** (`git ls-tree -r <parent> -- <those 9>` = 36; 30 under `langs|spec|tools`, 6 loose).
   **THEREFORE: THE DUPLICATE WAS MASKING A MASS DELETION AT THE ROOT.** Had the push gone through
   under `push.fsck.skipList=duplicateEntries`, `git push` would have carried a tree that deletes
   `pyproject.toml`, `uv.lock`, `tools/`, `spec/` and `langs/` from the repository's root.

   **THIS IS NOT A SECOND, INDEPENDENT DEFECT — IT IS THE SAME EVENT.** The whole thing reconciles
   exactly, and I checked every term:

   | term | measured |
   |---|---|
   | parent `3173198bd` files | 7,435 |
   | bad `591f6b499` files | 7,505 |
   | `git diff --name-status` | **252 A, 182 D, 1 M** |
   | 7,435 − 182 + 252 | **7,505** ✓ |
   | 36 of the 182 D are the dropped root paths | ✓ |
   | child `02329daf` files | 7,431 = 7,435 − 4, the 4 "live work" files the repair left pending ✓ |

   **So the 182 phantom deletions the tree's author already found and repaired INCLUDE the
   36 root-level ones. The root-level omission is the top of the same iceberg the author already
   named.** That is why "small" is wrong even though the diff counts the author quoted (252/182/1)
   are right — I reproduced them.

---

## 2. BLAST RADIUS — a duplicate root entry is not one bad row

MEASURED, and this is the part that makes the arm worth having:

| measurement | value |
|---|---|
| `git ls-tree -r -t 591f6b499` lines | **8,572** |
| distinct paths in those lines | **8,318** |
| extra lines | **254** |
| occurrences of `gates/replace-gate.py` | **3** |
| occurrences of `README.md` (outside `gates/`) | **1** |

**ONE DUPLICATE ROOT ENTRY MAKES `ls-tree -r` ENUMERATE THE WHOLE SUBTREE THREE TIMES — 253 blobs
plus 1 tree = 254 rows.** The defect is at one path in the root tree; its *observable footprint* is
254 rows spread over an entire directory. **ANY INSTRUMENT THAT COUNTS ROWS, OR THAT DEDUPES BY
PATH, LOSES IT.**

### And the blind spot is provable in three lines of the existing gate

`checks/index-arm-gate.py` builds **`dict`s keyed by path on BOTH SIDES of its comparison**:

- `:100-106` `index_entries()` → `ent[path] = (fields[1], fields[2])`
- `:114-119` `head_tree()` → `ent[path] = fields[2]`

**A `dict` CANNOT REPRESENT A DUPLICATE ENTRY.** Not "would probably miss it" — the data structure
has no representation for the state being looked for, so the three `gates` entries collapse to one
on assignment and the gate measures a 19-path tree it believes is whole. And `git ls-tree -r <rev>`
**succeeds** on the malformed commit — MEASURED **rc=0, empty stderr** — so the gate gets a clean
exit and a plausible number rather than an error.

**THE GATE'S OWN COMMENT NAMES THE FAILURE MODE ONE ARM AWAY** (`:79-83`): *"this gate printed
`PASS: the index agrees with HEAD on all 7231 paths` while the DEFAULT index held 38 stale paths — a
PASS about a DIFFERENT FILE."* **A COLLAPSED DUP IS THE SAME ERROR WITH A DIFFERENT SUBJECT: a PASS
about a DIFFERENT TREE.**

---

## 3. MECHANISM — what the evidence supports, and what it does not

### Supported (measured, or the repo's own measurement, re-verified here)

**⚠ WRITTEN AGAINST A SUPERSEDED `AGENTS.md`, CORRECTED IN PLACE — READ THIS, NOT `a2da165`.**
`a2da16597` states: *"both sweeping commits both happened while FOUR units were committing through the
SAME index file"*, and proposes *"a private index per unit: `GIT_INDEX_FILE=.git/agent-index-<session>`"*.
**THE LIVE `AGENTS.md` NOW MEASURES THAT CLAUSE UNSUPPORTED** — `race.py`, 12 trials × 3 units, 36
concurrent one-path commits through one shared index, **swept 0**; and `contam.py` carried exactly one
path against **4 of 4** shapes `index-arm-gate.py` names, so `--only` **was already bounded**.
**CONCURRENCY-THROUGH-A-SHARED-INDEX IS NOT THE CAUSE.**

**THE ROUTE `AGENTS.md` MEASURES INSTEAD IS A COMMIT WITH NO PATHSPEC** — *"**THE **ONLY **ROUTE
**MEASURED **THAT **SWEEPS IS **A **COMMIT **WITH NO PATHSPEC** … THE PATHSPEC IS THE BOUNDARY AND A
SHARED INDEX IS WHAT PUTS ANOTHER UNIT'S WORK **INSIDE** IT"*, and over the 62 commits of 2026-10-17:
**60 bounded, exactly `1` in `62` (`1.6%`) swept** — `591f6b499`. **A SHARED INDEX IS A NECESSARY
CO-FACTOR, NOT THE CAUSE.**

**AND MY OWN MEASUREMENT LANDS ON ITS ARITHMETIC.** `AGENTS.md` records the bare sweep as carrying
*"**9 FOREIGN ADDS + 9 DELETIONS + ITS OWN 1**"*. I measured §1's root drop as **exactly 9 top-level
paths** dropped and **zero** additions. **TWO INDEPENDENT MEASUREMENTS, ONE NUMBER — arrived at from
opposite directions. I DID NOT GO LOOKING FOR THAT MATCH; IT IS A CONVERGENCE, NOT PROOF AT n=1.**

**THE REPAIR COMMIT ALREADY DIAGNOSED THIS EXACT COMMIT — BUT ITS WORDING IS ALSO SUPERSEDED.**
`02329daf`: *"REPAIR: 178 phantom deletions from an armed-index race, restored verbatim from HEAD~1"*,
and *"A CONCURRENT AGENT's INDEX STATE LANDED IN A `--only` COMMIT THAT NAMED ONE PATH."* I re-measured
its counts (252/182/1) and they are correct. **IT SAYS `--only`, AND `AGENTS.md` NOW MEASURES THAT
`--only` BOUNDS CORRECTLY — SO TWO REPO DOCUMENTS DESCRIBE THIS ONE COMMIT WITH DIFFERENT MECHANISMS,
AND THE NEWER MEASUREMENT IS THE ONE I BELIEVE.**

**THE TREE IS CONTAINED AND THE DAMAGE IS LOCAL.** The duplicated subtree `5dee0c1b` has **no
duplicate entries of its own** — my scanner recursed into every `gates` entry and emitted zero `sub`
rows. The duplication exists at the ROOT ONLY.

**IT WAS NEVER ON ORIGIN AND IT WAS REPAIRED LOCALLY.** rc=1 for `--is-ancestor`; the child `02329daf`
has a clean 28-entry root and restores all 9 dropped paths; and no descendant of `591f6b499` carries a
duplicate — the full 16,176-commit scan found exactly one row.

### NOT supported — and I am not going to guess past this line

1. **I DID NOT OBSERVE THE INDEX THAT CAUSED IT.** The index is not in the commit. Every statement
   above about *what the index held* is the tree's author reporting, not me measuring. I could not
   have measured it and did not try: the constraint was read-only, and the commit is 40 minutes old.
   **THE LINK "CONTAMINATED INDEX → DUPLICATE TREE ENTRY" IS INFERRED FROM CO-OCCURRENCE IN n=1.**

2. **`n = 1. ONE DUPLICATE CANNOT ESTABLISH A CORRELATION WITH ANYTHING** — not with the phantom
   deletions, not with concurrency, not with `jj`. It is one observation. What §1 establishes is a
   **RATE** (1/16,176), which is a different and weaker claim than a mechanism.

3. **I COULD NOT DISTINGUISH `jj` FROM `git` AS THE WRITER.** The commit object records an author and
   a committer (`Cyberistic <Cyb3ristic@gmail.com>`) and nothing else; a colocated `jj` commit and a
   `git` commit are the same bytes in the same object store. `AGENTS.md`'s jj-colocation paragraph
   makes `jj` the plausible suspect for *writing into git's index at all*, but **which process wrote
   THIS tree is not recoverable from the objects.**

4. **~~`--only` DOES NOT EXPLAIN IT~~ — NOW ANSWERED, BUT NOT BY ME.** I wrote this as an open gap:
   `AGENTS.md` records a `--only` commit as building its tree from HEAD, which would preserve all 28
   root paths, yet the observed tree has 19 and repeats one three times, so *either the commit did not
   take the `--only` path, or something wrote the tree without HEAD-based `--only` semantics*.
   **THE REVISED `AGENTS.md` RESOLVES IT: THE ROUTE IS A COMMIT WITH **NO PATHSPEC**, not `--only`.**
   That is consistent with what I measured — 19 root paths is what a bare commit carrying another
   unit's 9 deletions would produce. **BUT I DID NOT MEASURE THAT. I AM RELAYING IT, AND THE RELAY IS
   THE WEAKER ACT: it comes from a throwaway repo (`.agents/slop/idxpriv/`), not from `591f6b499`'s
   own reflog or index. **THE ONLY THING STILL UNEXPLAINED BY ANY DOCUMENT IS WHY THE ROOT ENTRY IS
   DUPLICATED THREE TIMES RATHER THAN SIMPLY ABSENT — AND NOT ONE WORD IN `AGENTS.md`, IN
   `02329daf`, OR IN `a2da165` EXPLAINS THE DUPLICATION ITSELF. THE ROUTE EXPLAINS THE 9 DROPS. THE
   TRIPLE IS STILL UNATTRIBUTED.**

5. **THE SUBTREE-WIDE CLASS IS NOT MEASURED.** §1 is about **root** trees. A duplicate inside a
   non-root subtree of a commit with a clean root would not have been found unless its *ancestor's*
   root was also duplicated. The count of distinct tree objects reachable from the pin is **UNMEASURED**,
   so the cost of closing this is unknown. **1/16,176 IS NOT "ONE BAD TREE IN THE REPO."**

---

## 4. CONTROL — PASS (and the rate is therefore reportable)

`control.py` ran both lanes; **a failed control would have made this a REFUSED report, not a
slower one.**

| lane | population | result |
|---|---|---|
| POSITIVE | `591f6b499` (the reported finding) | **1 row** — `591f6b499…  gates  21  19  rootx1` ✓ detector fires |
| NEGATIVE | **60** commits, each individually proven good by `git merge-base --is-ancestor <c> origin/master` = true — *origin accepted them*, not "they look fine" | **0 rows** ✓ detector silent |
| VERDICT | | **CONTROL PASS** (exit 0) |

`rootx1` = the 3 duplicated entries resolve to **one** distinct OID, so this is a **repeated** entry,
not a **conflicting** one. That distinction matters and is what the arm in §5 must preserve.

**THE NEGATIVE POPULATION IS DISCOVERED, NOT LISTED** (`git rev-list origin/master`, minus the known
bad commit) — a hand list would have been a population-by-listing, which is the failure this repo has
already catalogued seven times.

---

## 5. THE ARM `checks/index-arm-gate.py` IS MISSING — PROPOSED, NOT IMPLEMENTED

### Where it belongs

**Not a new file. A new shape inside the existing `census()` at `checks/index-arm-gate.py:123-146`**,
returning a new key alongside `DELETION/INTENT/FOREIGN/STALE/EMPTIED`, folded into `destructive()`
at `:166-175`. Reasons, both load-bearing:

- `census()` **already** calls `head_tree(root, rev)` at `:125`. The arm is the same read, compared
  differently. A separate file would pay a second `git ls-tree` for the same tree.
- A **separate file is what made this invisible for 40 minutes.** One gate, one census, one verdict.
  The class is not "a missing arm"; it is **one census whose two sides are `dict`s**, and only the
  code holding both sides can fix both.

### What it would measure

`head_tree()` currently returns `dict[str, str]`. It must also return the **raw entry multiset**:

```
def head_tree_counts(root, rev) -> tuple[dict[str, str], list[tuple[str, str]]]
    # -> (path -> sha  [last wins, unchanged, so every existing shape keeps working],
    #     [(path, sha) for EVERY entry, in stored order])
```

and `census()` gains:

```
"DUPLICATE": [(p, n_entries, n_distinct_oids) for p where n_entries > 1]
```

**TWO SUB-SHAPES, because conflating them is how this would become the next unmeasured shape:**

| sub-shape | condition | meaning |
|---|---|---|
| `REPEATED` | `n_distinct_oids == 1` | benign-looking, and what `591f6b499` is. Harmless to `read-tree`; fatal to `receive-pack` |
| `CONFLICTING` | `n_distinct_oids > 1` | two different objects claim one path. **Far worse, and I did not look for it** |

### Population — BOTH sides, and this is the part that is genuinely new

The gate's whole subject is *"is the default index armed?"*, answered **index vs HEAD**. That is the
wrong population for this arm, and the reason is the one in §2:

> **THE INDEX CANNOT HOLD A DUPLICATE ROOT ENTRY.** An index holds one entry per path per stage.
> The duplication is a property of a **WRITTEN TREE**, so no index-side census can ever see it.
> **THE INDEX ARM IS NECESSARY AND NOT SUFFICIENT; THE COMMIT-SIDE ARM IS THE ONE THAT FINDS THIS.**

So the arm needs a **second, commit-side population**, and it must be over **history**, not the
working tree, because the malformed commit is 40 minutes old and is not HEAD:

| population | source | why |
|---|---|---|
| A. the **committed trees** | `git rev-list <base>`, bounded window | **this is the one that finds it** |
| B. HEAD's tree | already in `census()` | catches the malformed-HEAD case |

### Verdict it would give for `591f6b499`

**FAIL (1).** `DUPLICATE: [("gates", 3, 1)]` → `REPEATED`. And because `destructive()` feeds the
verdict, the path is destructive → the commit is flagged.

**IF A WINDOW SCAN FINDS NONE, THE VERDICT IS NOT `PASS` — IT IS `SKIP` (4).** A duplicate tree entry
is invisible to `ls-tree`'s exit code (MEASURED **rc=0**), to `read-tree`, and to every consumer that
keys by path. **`A SCAN THAT RAN AND FOUND NOTHING HAS MEASURED ONE ROOT TREE PER COMMIT, WHICH IS
NOT THE CLAIM `THE TREE IS WELL-FORMED`.** Per `gates/gatekit.py:59`, `SKIP` is exit 4 — distinct from
`PASS` exit 0 — and that separation is the entire point of this arm.

### Cost — measured where measured, and marked UNMEASURED where not

| design | measured cost |
|---|---|
| **root tree only, via `cat-file --batch`** (what I ran) | **1.35 ms/commit**, 25 MB peak, **22 s for 16,176 commits** (`.agents/slop/duptree/chunk0.time`: 4,000 in 5.38 s). ONE process, no per-commit spawn. **This is the recommended shape** |
| `git ls-tree -r -t` per commit | **0.16 s/commit, one process each** → **~43 min for the full history.** Cheap to WRITE, 100× too slow to RUN |
| **full recursive, all trees, OID-memoised** | **UNMEASURED.** Depends on the distinct-tree count from the pin, which I did not compute. **This is the only shape that closes the gap in §3.5, and it must be measured before anyone claims the class is closed** |

**THE COST IS NOT THE ARGUMENT AGAINST IT. 22 s ONCE IS FREE. THE ARGUMENT IS THAT 1/16,176 IS A
RATE AND NOT A BOUND, AND THE ONLY WAY TO MAKE IT A BOUND IS TO MEASURE THE THIRD ROW.**

---

## 6. A LIVE MEASUREMENT OF THE HAZARD, TAKEN WHILE DOING THIS TASK

**I WROTE 6 FILES AND NEVER RAN `git add`. SIX OF THEM ARE ARMED INTENT-TO-ADD IN THE DEFAULT
INDEX.** Measured, `.agents/slop/duptree/{chunk0.rows, chunk0.time, control.py, dupscan.py,
probe591.names, probe591.rows}`:

```
$ git ls-files --stage -- .agents/slop/duptree
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/chunk0.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/chunk0.time
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/control.py
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/dupscan.py
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/probe591.names
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	.agents/slop/duptree/probe591.rows
```

**`e69de29b` IS GIT'S EMPTY BLOB, AT STAGE 0 — EXACTLY THE PLACEHOLDER `AGENTS.md` AND `a2da165`
DESCRIBE, AND EXACTLY THE `INTENT` SHAPE `index-arm-gate.py:149-163` NAMES.** Some other unit's
`jj` snapshot armed them; I read only, and wrote only under `.agents/slop/duptree/`.

**WHY THIS MATTERS TO THE HANDOFF, AND IT IS NOT A SIDE NOTE:** per the revised `AGENTS.md`, **a
bare commit is the only route measured to sweep.** These 6 files are now inside the default index,
which is inside the scope of the next bare commit by any unit. **THE HANDOFF MUST NOT `rm` THEM** —
deleting a file whose index entry is an empty-blob placeholder turns an `INTENT` row into the
`EMPTIED`/`DELETION` shapes, and `AGENTS.md`'s own rule for exactly this case is *"A FILE THAT EXISTS
MAY BE A **LIVE** UNIT's, AND DELETING IT IS THE SAME SHARED-STATE FAILURE ONE LEVEL DOWN."*
**LEAVE THEM. THEY ARE SMALL AND THEY ARE MINE.**

## 7. WHAT I DID NOT TOUCH

Read-only throughout. **No `git` write or mutation was run** — no add, commit, push, checkout,
reset, gc, prune, repack, rebase, amend; no `jj` mutation. Every git call read (`rev-parse`,
`rev-list`, `cat-file`, `ls-tree`, `diff`, `merge-base --is-ancestor`, `log`, `show`), and every
one was prefixed `env -u GIT_INDEX_FILE` per the chronically-stale-index instruction. **The repo's
index and every tracked file are unmodified — §6 above is another unit's write, not mine.** All
writes are under `.agents/slop/duptree/`; no `.txt` was created anywhere.

**NOT RUN, PER INSTRUCTION:** `bend`, `checks/differ.py`, anything under `gates/`, `checks/e2e*`,
`checks/sweep.py`, `checks/bounded.py`, `checks/repro-paths.py`, `checks/cites-census.py`, corpus
loops, `pytest`, `mypy`, `ruff`. Peak RSS of my heaviest process: **25 MB**.