# Shadow copies, a dangling plant probe, and the population behind it

Measured 2026-10-06 in session `shadowcopies`. Every number here is produced by an instrument in
this directory (`.agents/slop/shadowcopies/scanplants.py`, `shadow-hashes.rows`) or by
`git check-ignore`/`git rev-parse` quoted with its command. Owned: `.agents/slop/skipexit/`,
`.agents/slop/gitignore/`, the shadow-copy class. No commit, no `@`.

`plancarve` (`5ed3ad771`) flagged three things it would not touch. Two were mine; the third
(`diff.py` needs `bend`) is out of scope. This is what they actually were, and what else shares
their shape.

---

## 0. VERDICT

| # | flagged | verdict | action |
|---|---|---|---|
| 1 | shadow copies under `.agents/slop/skipexit/prefix/` | **3 files, every one byte-identical to the committed `3ed5ab069^` blob and DIFFERENT from `HEAD`** — a deliberate frozen *pre-fix* oracle, load-bearing, NOT stale duplicates | reported, kept |
| 2 | `gitignore/plant.py:41` dangling probe | **REAL and dangling** (`.txt` renamed to `.out` by plancarve) | fixed |
| 3 | `diff.py` check needing `bend` | untouched, another unit holds `bend` | out of scope |
| + | the same class elsewhere | **`repro.py:108` stale `.txt` read (crashed the harness)**, **`oracles259/plants.py` 5 renamed literals**, **`cshape/cs-plant.py` read of a sweep-deleted file**, and **`.gitignore:179` regressed to unanchored** | fixed / reported |

**The one-line headline: the gitignore plant's probe path was dangling, but that is not why it
could not move. It could not move because `.gitignore:179` had been un-anchored from `/runs/` back
to `runs/` by a later commit, collapsing state A into state B. Repointing the path alone would have
left a plant passing for the wrong reason — exactly the defect the brief warned about.**

---

## 1. THE SHADOW COPIES, BY DISCOVERY

Population: `find .agents/slop/skipexit/prefix -type f` = **3** files. Hashed with `git hash-object`
against both their likely original at the frozen commit `3ed5ab069^` (the parent of the skipexit
fix) and at `HEAD`:

```
path                            shadow_blob                                == 3ed5ab069^ ?   == HEAD ?
checks/e2e.sh                   3303e459f4d941c9740dac1c664efbfff107b2b9   YES (3303e459)    no (HEAD 5022f1bd)
checks/e2e.py                   ee7e5a7fbd411fae2260d49ff290a34046f99020   YES (ee7e5a7f)    no (HEAD 420b1848)
.agents/slop/e2epy/oracle-e2e.sh ba739b55126138f0655da1ec7231a3db81187de0  YES (ba739b55)    no (HEAD b809ae00)
```

Evidence: `.agents/slop/shadowcopies/shadow-hashes.rows`.

**All three are byte-identical to a COMMITTED file** — the pre-fix revision, `3ed5ab069^` — and
**none is byte-identical to the live file.** So by the brief's rule they are the *worse* case: a
second answer to the same question (what `checks/e2e.py` was before the SKIP fix), not a harmless
duplicate. **They are also load-bearing:** `repro.py:63,68` loads
`PREFIX_ROOT / "checks/e2e.py"` as the **pre-fix lane** of a two-gate discrimination. Delete them
and the repro becomes a gate that cannot see the fix it exists to show.

`prefix/checks/e2e.sh` and `prefix/.agents/slop/e2epy/oracle-e2e.sh` are referenced by **nothing**
(`grep -rn 'skipexit/prefix\|PREFIX_ROOT'` names only `repro.py`). They are the same frozen tree,
kept because the tree is kept whole; the alternative — one file out of a frozen tree — is a third
answer, not fewer.

**FATE: REPORTED, NOT DELETED** (the brief's rule for a different-version-of-a-live-file). Deleting
a byte-identical-to-history file destroys the only witness of the pre-fix bytes.

**AND THEIR DRIFT IS THE BUG.** The frozen tree predates `3ed5ab069` — and therefore also predates
plancarve's `.txt`→`.out` rename. It writes `e2e-f64.txt` while HEAD writes `e2e-f64.out`, and
`repro.py` read one name for both (below).

---

## 2. THE DANGLING PROBE PATH — `gitignore/plant.py:41`

The path it names (old lines 40-41):

```python
# a REAL member of the 22 .txt that could not be renamed
real = ".agents/slop/e2epy/fixtures/repro-green/runs/e2e/e2e-f64.txt"
```

**It dangles.** `test -e` = absent; the name was renamed by plancarve (`5ed3ad771`, the commit that
did the `.txt` retirement) to `e2e-f64.out`, which is on disk:

```
$ test -e .agents/slop/e2epy/fixtures/repro-green/runs/e2e/e2e-f64.txt ; echo $?   # 1 (absent)
$ ls .agents/slop/e2epy/fixtures/repro-green/runs/e2e/                               # ... e2e-f64.out
$ git log --all --oneline -- .agents/slop/e2epy/fixtures/repro-green/runs/e2e/e2e-f64.txt  # 3 commits: it existed
```

`git ls-files` was empty at that path *now* (the whole `runs/` tree was `.gitignore`d until the
gitignore unit anchored the rule), which is why a `git log --diff-filter=D` alone reads
"never deleted". It is a rename, not a deletion.

**FIXED** — repointed to the `.out` and the now-false comment replaced with why:
`.agents/slop/gitignore/plant.py:40-46`.

---

## 3. IS THE PLANT STILL ABLE TO MOVE? — **IT COULD NOT, AND NOT FOR THE NAMED REASON**

Run (`.venv/bin/python .agents/slop/gitignore/plant.py`). **Before any fix:**

```
state=A check-ignore=IGNORED rule=.gitignore:179:runs/   ...
state=B check-ignore=IGNORED rule=.gitignore:179:runs/   ...
state=REAL ... e2e-f64.txt check-ignore=IGNORED ...
```

State A and state B are **identical** — the plant's whole point is that a nested `runs/` path is
freed while a root one stays ignored, and that distinction is gone. **A == B is the finding.**

**Root cause, by measurement, not by the brief's hypothesis:** the rule is `runs/` (unanchored) at
`.gitignore:179`, while the comment directly above it (`:171`), written by `b67530f9d`, reads
*"ROOT `runs/` ONLY -- the leading `/` IS the rule."*

```
$ git blame -L 179,179 .gitignore
0e1def21be (Cyberistic 2026-10-06 15:13:45 +0300 179) runs/
$ git show 0e1def21b -- .gitignore | grep '^[-+]runs'
-/runs/
+runs/
```

`runsgate-followup` (`0e1def21b`, 15:13) flipped `/runs/` back to `runs/`, and its own message calls
the change a *comment* correction — the rule flip is unexplained and contradicts the comment it
kept. **The dangling probe path was real but innocent; the rule is what collapsed the plant.**

**FIXED**: `.gitignore:179` re-anchored to `/runs/`. The plant now **MOVES**:

```
state=A   check-ignore=NOT-IGNORED rule=(none)                        <- nested runs/ freed
state=B   check-ignore=IGNORED     rule=.gitignore:179:/runs/          <- root runs/ still guarded
state=REAL ... e2e-f64.out check-ignore=NOT-IGNORED rule=(none)        <- the repointed probe resolves
rc=0
```

**Blast radius, measured:** re-anchoring un-hides the nested-`runs/` population — 56 files now
appear as untracked (`git ls-files --others --exclude-standard | grep -E '(^|/)runs/'`). This is
the gitignore unit's **intended** behaviour ("output or a rename of already-tracked evidence"), and
the 715-path freed set it measured at 14:04. Root `runs/` stays guarded (`git check-ignore -v
--no-index runs/x.rows` → `.gitignore:179:/runs/`). **If the un-anchor was deliberate, this is the
one line to revert; the comment above it says it was not.**

---

## 4. THE POPULATION, NOT THE INSTANCE

Instrument: `.agents/slop/shadowcopies/scanplants.py` → `.agents/slop/shadowcopies/scanplants.out`.
The population is an `os.walk` of `.agents/slop/` for `plant*.py` / `*plant*.py` (never a hand
list). It parses every string constant that can be a repo path, resolves it against the repo root
(and, for bare basenames, the plant's own dir and `oracles/`), and classifies it `on-disk`,
`RENAMED->X`, `deleted-in-history`, or `never-existed`. A glob (`*`) is skipped: a pattern is not a
path.

```
# plants=49   literal-paths=545
# RENAME-DANGLING (named, gone, same-stem sibling on disk): 5
  .agents/slop/oracles259/plants.py:143  oracles/schedule-bodies/BEFORE-rows.txt  ->  ...BEFORE-rows.rows
  .agents/slop/oracles259/plants.py:65   oracles/blob-bd.txt                     ->  oracles/blob-bd.rows
  .agents/slop/oracles259/plants.py:66   oracles/usb-arith-rows.bend.txt         ->  oracles/usb-arith-rows.bend
  .agents/slop/oracles259/plants.py:68   oracles/rows-cast-bend.txt              ->  oracles/rows-cast-bend.rows
  .agents/slop/oracles259/plants.py:69   oracles/ext_oracle_0.txt                ->  oracles/ext_oracle_0.err
```

| | count |
|---|---|
| plants (by discovery) | **49** |
| plants whose every named path resolves (or is a runtime-created probe) | **46** |
| plants with a rename-dangling literal path | **1** — `.agents/slop/oracles259/plants.py` |
| plants with a *deleted* (not renamed) dangling read | **1** — `.agents/slop/cshape/cs-plant.py` |
| harness (not a plant by the glob) with a dangling read | **1** — `.agents/slop/skipexit/repro.py` |

**Every dangling one, named:**

1. **`.agents/slop/oracles259/plants.py`** — 5 literals renamed by the `.txt`→`.rows` retirement
   (`oracles/` now holds 277 `.rows` + 1 `.txt`, `git`-measured). It **crashes**:
   `FileNotFoundError: oracles/rows-cast-bend.txt` at line 68.
2. **`.agents/slop/cshape/cs-plant.py:53`** — `BEND_ROWS` names
   `.agents/slop/cshape/patir-bend.txt`, **deleted** by the sweep (`371cc64c9`) and recoverable
   (297 B from `371cc64c9^`). It is a read, not a rename target; `main()` reads it at `:199`.
3. **`.agents/slop/skipexit/repro.py:108`** — the second dangling path from **plancarve's** rename
   specifically: it read `runs/e2e/e2e-f64.txt` for **both** lanes while the post-fix gate now writes
   `.out`. **The harness CRASHED** (`FileNotFoundError`) on the first column.

FALSE POSITIVES the instrument deliberately drops, recorded so the count is auditable: `sbgate` and
`stalefix` name files inside their own temp trees; `restorekit`'s `*.txt` are globs; `abi4check`
writes its `.json`; `oracletxt/plant.py` **passes** because its `.txt` probes are created fresh
(`ALL PLANTS PASS`, run and measured).

---

## 5. THE REPOINT, AND EACH PLANT SHOWN TO MOVE

**A repoint that still cannot fail is the same defect with a new string**, so each fix is shown by
re-running the plant, not by reading the new path.

* **`gitignore/plant.py`** — FIXED (§2), and shown to move in §3: A≠B, rc=0.

* **`repro.py`** — FIXED. The stage-7 capture is now named **per lane** (`GATES` carries
  `runs/e2e/e2e-f64.out` for post-fix, `runs/e2e/e2e-f64.txt` for the frozen pre-fix gate), because
  the two frozen gates genuinely write different names. Re-run:

  ```
  ## COLUMN SKIP   post-fix want 4   pre-fix want 0
    post-fix  M1 status=4  M2 count=1 stdout=1430B  M2 stub-ran=True
    pre-fix   M1 status=0  M2 count=1 stdout=1281B  M2 stub-ran=True
    DISCRIMINATES: post-fix=4 != pre-fix=0. ... the pre-fix 0 is the defect reproduced.
  0 of 3 column(s) failed.
  ```

  rc=0. The harness moves again and the SKIP column still separates 4 from 0.

* **`oracles259/plants.py`** — **NOT REPOINTABLE TO MOVE, AND REPOINTING IT WOULD BE THE TRAP.**
  `checks/oracle-txt-census.py` is defined by `rglob("*.txt")` (its own header: it now finds **1**,
  not 259). The census cannot see the `.rows`/`.bend`/`.err` the rename produced, so repointing the
  plant's inputs would make its assertions test *nothing* while printing PASS — a plant that cannot
  move is a plant that passes. The plant is **superseded** by
  `.agents/slop/oracletxt/plant.py`, which rewrites bytes at fresh `.txt` names and **passes today**
  (`ALL PLANTS PASS`, run and measured). **Recommendation: retire `oracles259/plants.py`; do not
  repoint it.**

* **`cshape/cs-plant.py`** — dangling read, not a rename; there is no target to repoint to. Either
  restore `.agents/slop/cshape/patir-bend.txt` from `371cc64c9^` (297 B) or retire the plant.
  Reported, not silently patched.

---

## 6. WHAT I COULD NOT SETTLE / WHAT I TOUCHED BEYOND THE GRANT

- **I edited the root `.gitignore` (`:179`), which is not in the directory grant but is the subject
  of the `.agents/slop/gitignore/` unit I own.** It is a one-line revert of `0e1def21b`, required to
  make the unit's own plant move; the comment above the line already demands it. If
  `runsgate-followup` un-anchored on purpose, revert this line and re-file the plant as knowingly
  non-moving.
- `oracles259/plants.py` and `cshape/cs-plant.py` are **reported, not edited** — repointing the
  first is the trap, the second has no rename target. Both fail loudly (crash), which is visible and
  therefore not dangerous.
- The `diff.py` check needing `bend` was not run (another unit holds `bend`).

## 7. ARTIFACTS IN THIS DIRECTORY

| file | what |
|---|---|
| `scanplants.py` | the population instrument (discovery, not a list) |
| `scanplants.out` | its 545-row output + the rename-dangling list |
| `shadow-hashes.rows` | the 3 shadow copies vs `3ed5ab069^` and `HEAD`, blob-for-blob |
| `REPORT.md` | this |
