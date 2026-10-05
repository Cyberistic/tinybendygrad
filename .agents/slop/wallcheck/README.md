# wallcheck — the instrument, rebuilt 2026-10-05

`.agents/slop/wallrule/wallcheck.py` and `wallcheck.sh` were never committed; a prune took them
with `walls.tsv` and `walls.truth.tsv`. The rule they enforced survived in `RULE.md` and `SWEEP.md`.
Rebuilt here, plus a sixth failure the old one died of that is not in that list of five.

Run: `.venv/bin/python checks/wallcheck.py [ID ...]` · `--selftest` for the guard fixtures.
Files: `walls.tsv` (the ledger) · `walls.truth.tsv` (**hand-measured, read-only, never written here**).

## Verdicts

`LANDED` a MISSING wall's capability arrived · `GONE` a DEFECT wall's defect is fixed ·
`GONE/ANNOTATED` the claim is still on disk **and the file now says it is false** ·
`STANDS` the wall's premise is still there · `SPLIT` the two trees disagree, so the answer is
**WAIT** · `STORY` missing anchor/reopen/date · `REFUSED/RUN` the prerequisite is a re-run ·
`REFUSED/NO-SCOPE` readable in neither tree · `REFUSED/BAD-ANCHOR` the pattern will not compile.

`GONE/ANNOTATED` exists because "the defect is fixed" and "the claim survives with its refutation
beside it" are different states and WALL/1 forbids conflating them. U5 and U1 are both that state,
and a presence-anchor reads both as `STANDS`.

Exit 0 all stands · 1 something moved · 2 ledger unreadable · 3 a row is a STORY ·
4 selection matched nothing · 5 nothing was graded. Zero ids is every row, **never `CLEAN`**.

## The six failures, and the guard for each

The first five are the ones the deleted instrument documented about itself. Each is reproduced by
`--selftest` on an in-memory fixture and printed with the measurement that shows it is true.

| | failure | guard |
|---|---|---|
| 1 | whole-tree patterns: `PRESENT` 11/11, hit rate 100%, information 0 | `scope` is **one file**; `tree_copy()` prunes tree copies by shape |
| 2 | working copy only: called two walls `STANDS` for capabilities at HEAD | grade `work` **and** `pin`, answer `SPLIT` when they disagree |
| 3 | `runtime/dtype.c emit` is not a path; a silent `[[ -r ]]` failure read as `GONE` | readable in **neither** tree ⇒ `REFUSED/NO-SCOPE`, never a verdict |
| 4 | `[[:space:]]` compiles as a nested set and matches `:` — the row grades 0 **forever** | translate POSIX classes, then assert **every** anchor compiles before any row is graded |
| 5 | a 4-way anchor read `work=4`; dropping one moved it to 3 and the verdict held | re-ask per alternative; all drops agreeing ⇒ `COARSE`, and the ledger row is split |
| 6 | **`^` without `re.M` matches offset 0 only, so every line-anchored anchor reads 0** — the mirror of 1: not "matches too much" but "matches nothing" | `compile_posix` passes `re.M`, because a POSIX grep is line-based |

**6 was not in the list and it invalidated every `^`-anchored row in the ledger** — `W1a`, `W1b`,
`W1c`, `W2a`, `W2b`, `U1`, `W7`. It was found by `--selftest`, not by reading. The lesson is the
one the five already make: an instrument reports its other rows while it is wrong.

## Two more that are not the previous instrument's

- **`re.M` is not the only silent default.** `TextIOWrapper.read(n)` blocks for a *decoded* `n`,
  so a binary pipe from `git cat-file --batch` hung forever on the second row. `_exact()`.
- **A tree copy is detected by SHAPE, not by name.** `differverdict` and `xd1` were named in the
  brief; `dd-cone-wt`, `rf2root`, `strays/origin`, `strays/working` hold copies too and nobody
  listed them. `tree_copy()` counts the source tree's own top-level names under a directory, so a
  **partial** copy is caught too, and the pruned list is printed.

## The two columns beyond the verdict

- **`disposition`** — `RE-DATED` vs `STALE/UN-RE-ASKED`. WALL/1's two acts, kept apart. A void wall
  whose home file carries no `REOPEN:` clause is the **forwarding hazard**: it reads identically to a
  live wall in a note, and that is the copy that gets sent to the next unit.
- **REDUNDANCY** — files that state the claim on **one line** (with `WINDOW = 2`, because a wall
  wraps) and which of them lack its correction. A claim stated in three places gets corrected in two
  by accident and the third is the copy a reader finds, so **the count predicts which copy rots**.
  `KEY-TOO-BROAD` fires above 12 files: past that the count is a sentence length, not a census.

## Known limits, stated

- **One labeller.** Every truth row was hand-measured by the agent that wrote the anchors, so the
  error rate is a **self-consistency** rate and cannot catch an anchor and its truth wrong in the
  same way. It did earn its place: it caught a `GONE` that should have been `GONE/ANNOTATED`, and
  `U1`'s count moved under it while the verdict held.
- **The truth file is not exempt from WALL/4.** `U5` was re-labelled after a disagreement and the
  reason is written into the row, because a truth file edited to agree is not a truth file.
- **A count is a measurement of a tree.** `master` advanced from `eed25a30b` to `8575adaab` while
  this was written; every graded verdict held across the move. The report prints the resolved
  commit and **names** any file that differs from it, so `SPLIT` is always attributable.
