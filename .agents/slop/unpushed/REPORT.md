# UNPUSHED RANGE — HEALTH INVENTORY

**Read-only. Nothing was committed, pushed, amended, reset or repaired. No index was
written. Every git call is a read (`rev-list`/`rev-parse`/`cat-file`/`ls-tree`/`log`/
`diff-tree`/`diff`/`merge-base`/`grep`/`status`/`ls-files`), each prefixed
`env -u GIT_INDEX_FILE` so a colocated `jj`-staged index cannot move a denominator.**

## 0. THE RANGE, CAPTURED ONCE

| | |
|---|---|
| captured at | **2026-10-17T05:11:21Z** (`date -u`) |
| merge base | `52d77134b90312eb001ab3362477dc5db9ebac5e` |
| **HEAD at capture** | **`c0795853ae9bc75b4442db43eb6cf035ddddf4a6`** |
| origin/master | `473d7ce988d0f0741e26bccf5e8c1495d864be4c` (`Update README.md`, 2026-10-17 06:51:22 +0300) |
| range | `52d77134b..c0795853a` |
| size | **49 commits**, 0 merges, 1096 files changed in sum |
| ahead / behind | 49 ahead, 1 behind |

`git rev-list --count origin/master..HEAD` = **49**. `HEAD..origin/master` = **1**.
Merge base is an ancestor of origin/master (`git merge-base --is-ancestor` = YES), so the
one origin commit is a real fast-forward divergence and the eventual push is a **merge**,
not a fast-forward.

**THE TREE MOVED TWICE WHILE I MEASURED — this is why the range was pinned.** The
per-commit table below describes the 49-commit range named above and nothing else:

| observed at | HEAD | ahead | the new commit(s) | in this inventory? |
|---|---|---|---|---|
| 05:11:21Z | `c0795853a` | 49 | — | **yes, this is it** |
| 05:17:47Z | `030a34fe` | 50 | `gates/gatekit.py: print the disagreement COUNT, not the list's length` (1 file, M) | no |
| 05:18:48Z | `62032e2a` | 51 | `DISAGREE: the "shared plumbing" has 10 FORKS, so the fix has an UNKNOWN DENOMINATOR` | no |

**The two later commits are NOT inventoried.** The finding that would change the owner's
decision — §3 — was **re-measured at all three tips and is unchanged: still exactly 3
paths.** `591f6b499` remains an ancestor of `62032e2a`, so it still blocks the push.

## 1. PER-COMMIT INVENTORY

Full table: **`range.rows`** (TAB, 49 rows, newest first).
`sha <TAB> author_kind <TAB> files_changed <TAB> tree_ok <TAB> note`

* `files_changed` = `git diff-tree -r --name-only <sha>^ <sha>`, vs first parent.
* `tree_ok` = `parses` (49−1) or `parses+DUP` (1). `parses` means `git ls-tree -r` walked
  the whole tree with rc=0 **and** raw `cat-file -p` parsed — it does **not** mean
  well-formed. A tree with a duplicate entry reads `parses`, so the verdict column carries
  `+DUP` rather than letting a readable tree read as a healthy one.

**tree_ok: 48 `parses`, 1 `parses+DUP`, 0 `BAD`.**
**files_changed: 48 commits ≥1 file, 1 commit 0 files (`eff33dffc`, `EMPTY-diff`).**

### AUTHORSHIP — NOT DISTINGUISHABLE, AND I DO NOT GUESS

**All 49 commits carry ONE identity: `Cyberistic <Cyb3ristic@gmail.com>`.**
Author identity therefore separates **nothing**: I cannot tell the orchestrator's commits
from the concurrent session's, and I will not guess.

What *is* in the messages: **35 of 49 carry a leading unit tag** (`idxpriv` ×13,
`tnvalue` ×2, `SPECPROGRAM` ×2, and 18 singletons incl. `TWORED`, `REPAIR`, `INDEXRACE`,
`CENSUS`, `IDXPRIV`, `SPECFIX`, `REVENDOR`, `PURGE`, `MANIFEST`, `opseven`,
`HELPCENSUS`, `CHECKSREADS`, `ARGV`, `bend`, `bend-health`, `gates-pop`, `checks`,
`autogen-oracle`), **14 carry none** (`unit:none`). A unit tag is the author naming their
own unit; it is **not** evidence of which session ran it, and two sessions running under
one identity produce the same tag vocabulary. **`author_kind` records the tag, not a
session.**

## 2. INTEGRITY RESULTS

### 2a. Does every commit's tree parse? — YES, 49 of 49
`git ls-tree -r <sha>` rc=0 for **49/49**; raw `git cat-file -p <sha>^{tree}` parsed for
**49/49**. `recursive_parse_fail=0`, `raw_tree_parse_fail=0`.

### 2b. Duplicate entries — 1 tree of 1137, and it is the known one
A prior unit checked **root trees only**. I did that *and* closed the limit by
measurement:

* **root-only pass** (`audit.py`, `cat-file -p` text form): **1 of 49** root trees has a
  duplicate entry — `591f6b499`, root tree `d83cf685f89af04f607a49a3c6d2c8ef0c1eec65`,
  **`gates` listed 3×** (all three pointing at the same tree `5dee0c1b8574bcf1…`).
* **all-trees pass** (`alltrees.py`): the union of every tree reachable from the 49
  commits — **1137 unique trees**, batch-read in ONE `git cat-file --batch` pass,
  **0 framing/parse anomalies** — yields **exactly 1 tree with duplicate entries**, the same
  `d83cf685…`. **No duplicate anywhere in the range except `591f6b499`'s root.**
* `d83cf685…` is the root tree of **exactly one** commit in the range. `591f6b499` is an
  ancestor of HEAD (child: `02329daf`; `591f6b499..HEAD` = 44 commits), so **pushing HEAD
  pushes it.** It has **not** reached origin.

> The all-trees pass also corrected a real blind spot in my own first attempt:
> `git ls-tree` **never emits the root tree itself** (it lists entries *inside* a tree), so
> a tree-set built only from `ls-tree -r -t` silently excludes every commit's root — and
> reported **0 duplicates**, contradicting a fact already established by `cat-file -p`.
> The root oids have to be asked for with `rev-parse <sha>^{tree}`. An instrument that
> reported "clean" here was measuring the wrong population.

### 2c. Root tree missing paths vs its parent (mass deletion) — 1 commit, the same one
**1 of 49** commits drops root entries relative to its parent: `591f6b499`, **9 names** —
`langs`, `mkdocs.yml`, `opencode.json`, `pyproject.toml`, `serve_docs.sh`, `spec`, `sz.py`,
`tools`, `uv.lock`. No other commit drops anything at any depth.

### 2d. The real deletion count — the brief's "36 files" understates it by 4×
Walking both trees (`ls-tree -r --name-only`, sorted, set-differenced — independent of
`diff-tree` and safe here because the 3 `gates` entries are byte-identical trees):

```
deleted 182   (146 under gates/  +  36 under the 9 dropped root names)
added   252
changed 435   = 252 + 182 + 1 (the duplicate gates entry)
```

**`591f6b499` deletes 182 files, not 36.** The 36 figure is only the files *under the 9
dropped root names*; the larger half is the **146 under `gates/`**, which the 9-name
framing cannot see. `435` matches the `252 + 182 + 1` arithmetic already recorded in
`AGENTS.md`.

## 3. ⚠️ DOES THE RANGE DELETE ANYTHING ORIGIN HAS? — **YES. THREE FILES. LOUD.**

```
git diff --name-status --diff-filter=D origin/master HEAD
D  gates/assertlit.rows
D  gates/falseclaim.rows
D  gates/oracleblind.rows
```

**Denominator: 7 501 blobs at HEAD (`c0795853a`), 7 433 at origin/master.** HEAD is net
**+68** files over origin — and **3 paths origin/master carries that HEAD does not.** All
three are present at the **merge base** (7 435) and at **origin/master**, so they came in
through already-pushed history and the unpushed range removes them. They are not "never
committed": they are **deletions of tracked files that a merge would carry out.** Re-measured at **both**
drifted tips, `030a34fe` (7 501) and `62032e2a`: **still exactly 3, same three paths.**

**Who names them (read-only `git grep` at HEAD):**

| path | named by | kind |
|---|---|---|
| `gates/oracleblind.rows` | `gates/tnvalue-census.py:52` — *"verdict is read from `gates/oracleblind.rows`, ALSO LOADED BY PATH"* | **REQUIRED INPUT** |
| `gates/oracleblind.rows` | `gates/oracleblind-census.py:118` (`REPORT =`), `gates/pins-shape-gate.py:324,330`, `gates/assertlit-census.py:62` | generator output + prose |
| `gates/assertlit.rows` | `gates/assertlit-census.py:85` (`REPORT =`) | generator output |
| `gates/falseclaim.rows` | `gates/falseclaim-census-gate.py:100` (`ROWS =`) | generator output |

So `assertlit.rows` and `falseclaim.rows` are each their own generator's **output**
(regenerable), but **`gates/oracleblind.rows` is a required INPUT of `gates/tnvalue-census.py`.**

**A dangling citation, measured:** `gates/tnvalue-census.py:8` pins that file as
*`COMMITTED, sha256 614ea700469eeea9…`*. The sha256 of origin/master's blob content is
**`614ea700469eeea9e67d8e344f6a3d202d78a16c7cc16fcb8d769da70c7454e6`** — an exact match. The
commit the header cites **is** the one the local branch deletes.

**Why they are still missing — the on-disk state is a trap.** All three exist in the
working tree with real content (`5 646`, `17 457`, `35 858` bytes) but git's index holds
git's **EMPTY blob** for each:

```
git ls-files -s -- gates/assertlit.rows gates/falseclaim.rows gates/oracleblind.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0  gates/assertlit.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0  gates/falseclaim.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0  gates/oracleblind.rows
```

`e69de29b` is `git hash-object /dev/null` — these are **intent-to-add placeholders**, the
`jj`-colocation signature `AGENTS.md` already documents. `checks/index-arm-gate.py` (run
read-only, disarmed) reports **693 intent-to-add paths, 0 deletions, 1 stale
(`.agents/TODO.md`)** and returns **REFUSED, not a verdict**. The three are therefore
**untracked from git's point of view** — present on disk, absent from every commit.

**And their content differs from what is being deleted.** sha256, worktree vs origin:

| path | worktree | origin/master |
|---|---|---|
| `gates/assertlit.rows` | `1880d9e6…` | `fe9dde82…` |
| `gates/falseclaim.rows` | `7a941f76…` | `cf2670c9…` |
| `gates/oracleblind.rows` | `0cc47cbe…` | **`614ea700…`** ← the sha `tnvalue-census.py:8` pins |

**⇒ Which version should be committed is not a question I can answer from the repo.
REFUSED to guess.** It is the owner's call, and it is the whole content of the decision.

**How this happened, from the commits themselves:** `02329daf` (`REPAIR: 178 phantom
deletions… restored verbatim from HEAD~1`) restores **178 of the 182** and its own message
names the 4 it withheld: *"`gates/assertlit.rows`, `gates/falseclaim.rows`,
`gates/gates-pop.py`, `gates/oracleblind.rows` — `gates-pop.py` BEING EDITED AT THE MOMENT
OF THE MEASUREMENT."* So the loss was **known and deliberately deferred**, `gates-pop.py`
was picked up by a later commit, and **the other 3 were never picked up by any of the 44
commits that followed.** They are not a fresh accident; they are an **open item that the
repair left behind.**

## 4. MESSAGE-VS-DIFF (COARSE) — denominator stated

Instrument: a **word match** on the whole message for
`delet|remov|prun|mass-delet|drop|revert|purge` (any inflection), against
`diff-tree -r --diff-filter=D` vs first parent. **This counts words; it does not judge
messages.** Denominator: **all 49 commits.**

| | count |
|---|---|
| messages containing a deletion word | **28 / 49** |
| …and the diff contains ≥1 deleted path | **2 / 28** |
| …and the diff contains **0** deleted paths | **26 / 28** |

**All 26 changed ≥1 file** (no empty diffs among them), so the word refers to code/rules
dropped *inside* a file, not to a deleted path. Sampling 8 confirms it:
`SPECPROGRAM: pr_0 dropped BOTH halves of spec.py:204` (4 files changed, 0 deleted),
`REVENDOR…` (1, 0), `RE-VENDOR… MOVE EVERYTHING` (93, 0), etc. **I count these as
false positives of the word match, not as 26 defects.** The real `gates/msgdiff-gate.py`
(`REFUSED`/3 on a claim its diff cannot witness) is the instrument that judges polarity;
per brief I did not run it, so **this section is a word census, not a verdict.**

**The one case that deserves a human's eye — and it passes the word test, so no gate
flags it:** `02329daf` (`REPAIR: 178 phantom deletions… **restored** verbatim from
HEAD~1`) has **430 files changed, 252 deletions**. The word "deletions" is *present* and
the diff *does* delete — but the message describes **restoring**, and the commit instead
**removes the 252 phantom additions** while re-adding the 178. Reading "deletions" as
deletions gives the **opposite** of the truth. That is a polarity defect a word match is
structurally unable to see, and it is why `msgdiff-gate` "counts pids rather than judging
them" — the same limit, one level up.

## 5. LIMITS OF THIS INVENTORY — DECLARED, NOT ASSUMED

1. **Root-only, and it COST something.** The duplicate/mass-deletion pass proper
   (`audit.py`) compares **root trees only**. I closed that with the 1137-tree scan
   (§2b), so for *duplicate entries* the limit is now measured, not declared. **It is
   still open for one thing**: a subtree that silently lost entries would not appear as a
   "root drop", and the 1137-tree scan looks for **duplicates**, not for **missing
   entries**, in subtrees. **§3 is what actually caught the real deletions — and all three
   are at depth 2 (`gates/…`), which a root-only check cannot see by construction.**
2. **Content equality was checked for 3 paths only** (§3). I did not diff the other
   7 502 files' blobs; I checked *presence*, and presence is what §3 turns on.
3. **Empty blob ≠ zero-byte file.** I classified the 3 as untracked from the index oid
   `e69de29b` plus `.A` porcelain state. I did not run the gates, `differ`, `bend`,
   `pytest`, `mypy` or `ruff`, so **no claim here is a behavioural test result.**
4. **Authorship is undetermined**, not inferred (§1).
5. **Which content should be committed is REFUSED**, not guessed (§3).
6. **The tree moved under me, twice** (§0). This inventory is 49 commits at `c0795853a`;
   by 05:18:48Z HEAD was `62032e2a` at **51**. Two commits are uninventoried. Re-run the
   two scripts against a pinned HEAD if the per-commit numbers matter — the §3 finding was
   re-verified at every tip and did not move.

## 6. WHAT THE OWNER MUST DO

**Nothing here was changed. The owner decides. In priority order:**

1. **Decide the fate of the 3 files before any push.** They are tracked at origin and
   absent from HEAD; a merge **deletes them**, and `gates/tnvalue-census.py` needs
   `gates/oracleblind.rows` as a **required input** while its header pins the sha256 of the
   very version being deleted. Worktree content ≠ origin content for all 3, so "just
   re-add them" is **not** a safe instruction — it commits *different* bytes. **REFUSED to
   choose.**
2. **Do not let them be committed as 0 bytes.** The index holds `e69de29b` for all three.
   A commit made from that index can land the empty blob. Check the resulting
   `git show --stat` / blob oid in the **same command** that makes the commit.
3. **The push blocker is `591f6b499` alone** and is a **history** problem, not a content
   problem: 1 of 1137 trees is malformed, its root tree lists `gates` 3×, and it is 44
   commits behind HEAD. Repairing it means rewriting shared history (the tree is
   duplicated in every descendant's ancestry), **which is a mutation and therefore not
   mine to perform or to recommend blindly.** Decide deliberately, and note the AGENTS.md
   rule: **no amend, no rebase** — a new commit if a force push would be required.
4. **Push will not fast-forward.** origin/master is 1 commit ahead (`Update README.md`).
   The merge is a real merge; expect the 3 files in §3 to be resolved **by deletion**
   unless step 1 is done first.
5. **Optionally run the real judge on §4:** `gates/msgdiff-gate.py` over the range, which
   can judge polarity where a word match cannot. It returns `REFUSED`(3), not `FAIL`(1).

## 7. ARTIFACTS

| file | what |
|---|---|
| `range.sha.rows` | the 49 shas, captured once |
| `range.rows` | **the deliverable**: `sha⇥author_kind⇥files_changed⇥tree_ok⇥note` |
| `findings.rows` | machine summary of every check above |
| `dropped.rows` / `added.rows` | the 182 / 252 path sets for `591f6b499` |
| `p.rows` / `c.rows` | its parent / child recursive path sets (7 435 / 7 505) |
| `alldups.rows` | the 1 malformed tree from the 1137-tree scan |
| `audit.py`, `alltrees.py` | the two instruments (read-only) |
| `audit.out` | their console output |

Re-run: `.venv/bin/python .agents/slop/unpushed/audit.py && .venv/bin/python .agents/slop/unpushed/alltrees.py`
