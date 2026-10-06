# CLAUSE V — its count is the COMMITTED TREE's, and it already was

**HEAD `7918a6213` · measured 2026-10-06 · `gates/retention-check.py` (owned) and
`gates/gendirs.py` (read-only) · no source change made.**

## 0. Verdict in one line

**The clause has no count of its own.** All three of clause V's numbers are read from
`gates/gendirs.py`'s `tracked_dirs()`, which walks `git ls-tree -r HEAD` (`gendirs.py:481`).
**No clause-V number comes from `git ls-files`.** The index contamination the brief describes
was removed by the `gendirs.py` repair that is already HEAD (`705e7a644`, "emptyblob … REPAIRED"),
and clause V inherited that fix **by construction**, because it was never the location of the
bug — it is a *consumer* of `gendirs.table()`. **The brief's premise — that clause V "has its own
count" that still includes the index — is false against the current tree.** No change was
shipped, because the only available change would be a no-op.

---

## 1. Provenance — `file:line` per number

Clause V renders three numbers. Their chain:

| clause-V number | printed at | read from | ultimate command |
|---|---|---|---|
| **`n_tracked`** (CONTRADICTS, CENSUS, INDEXED lines) | `retention-check.py:456,458` (CONTRADICTS) · `:472-476` (CENSUS) · `:482-484` (INDEXED) | `gendirs.table()` row `r["n_tracked"]` — set at **`gendirs.py:533`** (`tracked.get(name, 0)`) ← `tracked` = **`gendirs.py:526`** ← `tracked_dirs(root)[0]` | **`gendirs.py:481` `git ls-tree -r HEAD`** |
| **"at git's EMPTY BLOB"** | `retention-check.py:461-462` and `:482-483` | `r["n_empty_blob"]` — **`gendirs.py:534`** ← `empty` ← **`gendirs.py:491-492`** (`if sha == GIT_EMPTY_BLOB`) | **`gendirs.py:481` `git ls-tree -r HEAD`** |
| **`IGNORED-BUT-INDEXED`** | `retention-check.py:463-465` | `contradiction` at **`retention-check.py:456`** = rows where `r["n_tracked"]` (above, HEAD) **and** `r["ignored"]` — `r["ignored"]` = **`gendirs.py:535`** ← `gendirs.ignored()` → **`gendirs.py:515` `git check-ignore --no-index`** | `ls-tree HEAD` **+** `check-ignore --no-index` |

**None of the three is `git ls-files`.** Clause V at `retention-check.py:442-444` is three lines
of plumbing — `gendirs = load_gendirs()`, `rows = gendirs.table()`, `read, present =
gendirs.coverage()` — and every number it prints is a field on a `table()` row. `table()` is
`gendirs.py:522-538`; it calls `tracked_dirs()` once (`:526`) and copies per-directory counts into
the rows. **"Clause V has its own count" is a mis-read of the emptyblob report's §4:** that report
correctly named clause V a *consumer* of `gendirs.tracked_dirs()` (then `ls-files -s`), and a
consumer inherits a producer's bug. The repair belonged in the producer, and it landed there.

*(The two surviving `ls-files` uses in `retention-check.py` are **not clause V**: `tracked()` at
`:286-290`, clause III's "is the output in the index", which is the index **on purpose**, and
`unregistered()` at `:308`, a census of `runs/` dirs whose index entry is non-empty. Both are
index questions by design.)*

## 2. Which the clause means — and whether `ls-files` is right for any number

Clause V measures **DISCOVERY** — "what this tree writes" — and cross-references it against the
**committed** tree. For that reading `git ls-tree -r HEAD` is correct and `git ls-files` is wrong:
`ls-files` answers from the index, where every unit's `git add --intent-to-add` placeholder wears
git's EMPTY BLOB regardless of the file's real bytes. So:

* `n_tracked` and `n_empty_blob` must be the committed tree's. **HEAD. ✓ already.**
* `IGNORED-BUT-INDEXED` inherits `n_tracked` from HEAD, and that is also consistent with
  `gates/gendirs.py` itself, which defines the same "CONTRADICTION" row from the same HEAD
  `n_tracked` (`gendirs.py:779`). **Changing clause V to an index query here would make clause V
  and `gendirs.py` disagree about the contradiction — two instruments, two answers, the exact
  thing this file's own header (`retention-check.py:28-31`) forbids.** So: no number wants
  `ls-files`, and the one place `ls-files` *is* used (clause III) is a different clause asking the
  index its own question.

## 3. The fix — none, and why a change would be a no-op

The brief asks for a narrow fix that consumes `gendirs.tracked_dirs()` "instead of re-deriving".
**Clause V already does exactly that**, through `gendirs.table()` (`retention-check.py:443`), which
calls `tracked_dirs()` (`gendirs.py:526`). One implementation, one population — the requirement is
met. The only edits available are (a) rewiring `table()`→`tracked_dirs()` and re-deriving the dir
key, which is pure churn and would be a *second* consumer shape, or (b) re-pointing the
contradiction at the index, which breaks agreement with `gendirs.py` and moves nothing on the live
tree anyway (§4: `IGNORED-BUT-INDEXED` is `0` under **both** algorithms). Per the brief's own rule —
*"if nothing moves, that is the finding — say so rather than shipping a no-op"* — the finding is
the deliverable. **No source file was modified.**

## 4. The number moves — same tree, both algorithms

`.agents/slop/clauseVfix/probe.py` imports the **live** `gates/gendirs.py` for the NEW numbers and
reproduces the pre-repair algorithm verbatim (its own docstring: "`ls-files -s`'s TWO fields") for
the OLD ones, on one committed tree:

```
=== clause V's three numbers, OLD (index, ls-files -s) vs NEW (HEAD, ls-tree) ===
number                                OLD/index     NEW/HEAD
CENSUS entries                             1577         1377
CENSUS dirs indexed                         121          107
CENSUS entries at EMPTY BLOB                265           65
IGNORED-BUT-INDEXED dirs                      0            0
```

**17 directories move**, and the moved lines are exactly the placeholders. The brief's cited
`arghalf` case is here in full — `OLD 7 entries / 7 empty → NEW 0 / 0`, because none of those files
is committed (they sit in the index as `git add -N` placeholders, content intact on disk):

```
  .agents/slop                                        entries  260->255   empty    5->0
  .agents/slop/arghalf/pin-tree/tinygrad              entries    7->0     empty    7->0
  .agents/slop/arghalf/pin-tree/tinygrad/llm          entries    7->0     empty    7->0
  .agents/slop/arghalf/pin-tree/tinygrad/mixin        entries    9->0     empty    9->0
  .agents/slop/arghalf/pin-tree/tinygrad/renderer     entries    7->0     empty    7->0
  .agents/slop/arghalf/pin-tree/tinygrad/runtime      entries   17->0     empty   17->0
  ...runtime/autogen 38->0 · .../autogen/am 19->0 · .../support 17->0 · .../uop 10->0 · .../viz 6->0
  .agents/slop/figurefix/plant                        entries    1->0     empty    1->0
  .agents/slop/figurefix/plant/scratch/.agents/slop   entries    1->0     empty    1->0
  .agents/slop/figurefix/plant/scratch/checks         entries    3->0     empty    3->0
  bin                                                 entries    1->0     empty    1->0
  checks                                              entries  143->92    empty   52->1
  tinygrad                                            entries    8->7     empty    2->1
MOVED DIRS: 17
```

`checks: 143 entries / 52 empty (index) → 92 / 1 (HEAD)` is the starkest: **51 of 52 "empty
blobs" were placeholders.** The clause-V line in the live run now prints the HEAD numbers — see
§6, `V INDEXED checks: 92 entries, 1 at git's EMPTY BLOB`.

**A correction to the brief.** It names `.agents/slop/canrun: 33 entries, 11 at git's EMPTY BLOB`
as an *inflation* instance "for files that were 0–17 KB on disk". Measured, that is wrong:
canrun's index and HEAD agree (`33/11` both, §4 table), and all 11 files are **0 bytes on disk**:

```
       0  .agents/slop/canrun/abi4.out      0  .../gate.out       0  .../norm_check.err
       0  .../beltA.out                     0  .../herm.out
       0  .../beltB.out                     0  .../final-dup-gate.out
       0  .../dup-census.out                0  .../final-norm_check.err
       0  .../dup-gate.out                  0  .../dup-gate2.out
```

canrun's line is a **true** census of committed empties; the emptyblob report agrees (it lists
`.agents/slop/canrun/census` among the *genuine* empties). The inflation lives in `arghalf`, which
is gone from clause V's listing under HEAD.

## 5. The plant — the hazard, reproduced and refuted

`.agents/slop/clauseVfix/plant.py`: make an 11-byte file, `git add --intent-to-add` it inside a
directory clause V already lists, measure both algorithms on the planted state, then unstage and
remove it.

```
1) BEFORE plant
  before       OLD/index entries=33  OLD/index empty=11  NEW/HEAD entries=33  NEW/HEAD empty=11

2) PLANT: 11 bytes on disk, `git add --intent-to-add`
  git status --porcelain=v2: '1 .A N... 000000 000000 100644 0000... 0000... .agents/slop/canrun/PLANT.intent-to-add.rows'
  on disk: 10 bytes   index blob: e69de29bb2d1d6434b8b29ae775ad8c2e48c5391

3) MEASURE under the planted state
  planted      OLD/index entries=34  OLD/index empty=12  NEW/HEAD entries=33  NEW/HEAD empty=11

4) ASSERTIONS
  PASS  OLD counts the placeholder as a tracked entry
  PASS  OLD counts it at git's EMPTY BLOB
  PASS  NEW does NOT add an entry (it is not in HEAD)
  PASS  NEW does NOT count it empty

6) RESTORE PROOF
  git ls-files -- <path>       -> '' (want empty)
  git diff --cached -- <path>  -> '' (want empty)
  git status --porcelain <path>-> '' (want empty)
  PASS  tree restored

PLANT: GREEN
```

`git diff --cached --name-only` is **0 lines tree-wide** after the plant — the 1300+ index entries
at EMPTY BLOB are other units' `intent-to-add` placeholders, which `git diff --cached` does not
report, so the restore proof holds globally, not merely per-path.

## 6. Clause V's full output before and after, and the overall verdict

**BEFORE** the repair — a real run at `c53ace4e8` (pre-repair `gendirs.tracked_dirs` = `ls-files -s`),
from the emptyblob unit's `.agents/slop/emptyblob/retention.out`:

```
V  DISCOVERED 222 directories ... from 1862 of 2350 source files.
V  IGNORED-BUT-INDEXED: 0/222 dirs -- none
V  CENSUS      118/222 discovered dirs are in the index (1513 entries), ...
V    INDEXED   .agents/slop/arghalf/pin-tree/tinygrad: 7 entries, 7 at git's EMPTY BLOB
V    INDEXED   .agents/slop/arghalf/pin-tree/tinygrad/runtime: 17 entries, 17 at git's EMPTY BLOB
V    INDEXED   .agents/slop/arghalf/pin-tree/tinygrad/uop: 10 entries, 10 at git's EMPTY BLOB
V    INDEXED   .agents/slop/gatesrun: 48 entries, 48 at git's EMPTY BLOB
V    INDEXED   .agents/slop/canrun: 33 entries, 11 at git's EMPTY BLOB
...   (78 more)
```

**AFTER** — this unit's run at `7918a6213`, `.agents/slop/clauseVfix/after-raw.out`:

```
V  DISCOVERED 232 directories something in this tree WRITES
   INTO, from 1922 of 2410 source files. A LOWER BOUND: ...
V  IGNORED-BUT-INDEXED: 0/232 dirs -- none
V  CENSUS      107/232 discovered dirs are in the index (1377 entries), of which 107 are
               not `.gitignore`d. ...
V    INDEXED   .agents/slop/canrun: 33 entries, 11 at git's EMPTY BLOB
V    INDEXED   .agents/slop/gatesrun: 72 entries, 27 at git's EMPTY BLOB
V    INDEXED   .agents/slop/e2epy/artifacts: 44 entries, 6 at git's EMPTY BLOB
V    INDEXED   checks: 92 entries, 1 at git's EMPTY BLOB
V              ... and 67 more
```

Every `arghalf` line — the placeholder population — is **gone**; `gatesrun` fell `48/48 → 72/27`
(the 27 are real, per the emptyblob report's §5) and `checks` fell `(unlisted before) → 92/1`.
`IGNORED-BUT-INDEXED` is `0/232`, as it was `0/222`: no gitignored directory is currently tracked,
so the clause is green under both algorithms (the number that *would* fire is `n_tracked`, and it
does not).

**Overall verdict: `RETENTION: RED`, rc = 1** — on **clause I** (11 `gates/artifacts/*` dirs carry
`.cmp`/`.out` residue, 66 declared files absent) and **clause IV** (`runs/graphcmp/D/` is stale:
`selfcheck=# SELFCHECK: FAIL`, `graphs-agree=20` expected 19). **Clause V is not red.** Clause IV is
another unit's; this change touches neither.

## 7. The residual stale prose (noted, not changed)

`retention-check.py:23` and `:453-454` still call `checks/gen/` "the live instance -- 2 entries,
BOTH git's EMPTY BLOB". Measured (emptyblob §6, re-confirmed): `git ls-files checks/gen/` → 0,
`git ls-tree -r HEAD -- checks/gen/` → 0. It is a **past** state. This is prose in a file this unit
owns, but it is not a clause-V **count** and the brief's scope is the count, so it is left for a
follow-up rather than folded into a no-op fix.

## Artifacts (`.agents/slop/clauseVfix/`)
* `probe.py` / `probe-now.out` — the same-tree OLD-vs-NEW clause-V numbers (§4).
* `plant.py` / `plant.out` — the `intent-to-add` plant and restore proof (§5).
* `after-raw.out` — the full live `retention-check.py` run at `7918a6213` (§6).
* `HEAD.out` — the pinned hash the numbers were taken at.
