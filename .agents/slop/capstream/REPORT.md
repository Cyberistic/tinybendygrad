# `.agents/slop/**/*.txt` — the CAPTURED-STREAM class, recounted

Measured 2026-10-06, session `capstream`. Every number below is produced by an instrument in this
directory, not typed:

| instrument | what it does |
|---|---|
| `discover.py` → `discover.json` | walks the tree with `no-txt.py`'s ownership rule, classifies every owned `.txt` by `sloptxt/classify.py`'s content rule (reimplemented, so this is an independent recount), splits by refusal reason |
| `refsplit.py` → `refsplit.json` | separates a PATH reference from a BASENAME collision inside REFERENCED |
| `pathgrep.py` | the literal per-path grep over committed files |
| `rename.py` | the only two `os.rename` moves, with the collision each one is |
| `plan.py` → `PLAN.tsv` | the per-file plan: reason, sub, reader, planned extension, one-line change |

**Verdict up front: the "369" does NOT reproduce; it is 350.** The 19-file difference is exactly
the `sloptxt` renames — the premise double-counts them. Under every operational definition the
remaining **NEITHER group is EMPTY**. This unit moved **2** files (`dtypeb/gate.txt`,
`fp8fix/gate.txt` → `.out`), the only reader-free basename collisions. Nothing deleted.

---

## 1. Recount by discovery — I do NOT reproduce the 369

A fresh `os.walk` (same ownership rule as `checks/no-txt.py`) finds **689 owned `.txt`** =
**550 HARD + 139 EXCUSED**, which is `no-txt.py`'s own live reading, so the denominator is
re-derived and agrees. Under `.agents/slop/` alone: **543**.

| class | `.agents/slop` (now) | `sloptxt` (session start) | delta |
|---|---:|---:|---:|
| CAPTURED-STREAM | **350** | 369 | −19 |
| ROWDUMP | 187 | 190 | −3 |
| PROSE | 1 | 1 | 0 |
| EMPTY | 5 | 5 | 0 |
| **total** | **543** | **565** | **−22** |

**350 = 369 − 19, and the sets are identical, not merely equal in size.** `discover.py` proves it:

```
old CAPTURED (369) − sloptxt's 19 renamed  ==  fresh CAPTURED (350)   -> True
in fresh not in old: []     in old (not renamed) not now: []
every one of sloptxt's 22 renamed sources: gone
```

The 19 are CAPTURED-STREAM files `sloptxt` moved to `.out`. So the task's sentence *"369 files …
were left as `.txt`"* is false by 19: those 19 were among the *renamed 22*. **The refusal and the
rename were never two questions for those 19 — they were the same answer.**

## 2. Split by WHY they were refused

`sloptxt`'s operational REFERENCED test is *"a committed CODE file names the BASENAME"*
(`readers.py`). Under it:

| reason | count | meaning |
|---|---:|---|
| **DECLARED** | **301** | basename is in `checks/differ.py`'s `declared()` — the generator's own name, same contract as the 139 excused |
| **REFERENCED** | **49** | a committed code file names the basename |
| **NEITHER** | **0** | — |
| **denominator** | **350** | |

**NEITHER is zero because `sloptxt` already renamed it.** There is no second renamable group hiding
at the basename level.

## 3. The finding the task is actually about: REFERENCED was declared by a BASENAME

`sloptxt` refused 49 files because a committed code file names their *basename*. That is doctrine
1's failure again, one level down: a basename is a shape, not a path. `e2e_negctl.sh:160` names
`"$NC/runs/e2e/gate.txt"` (`NC` is a `$TMPDIR`), and by basename that marks **every** `gate.txt` in
the tree. `refsplit.py` re-tests each REFERENCED file for a **parent-qualified suffix** (≥2 path
components) in committed code:

| REFERENCED sub-class | count |
|---|---:|
| **path** — a committed code file names a ≥2-component suffix (unambiguously this file) | **20** |
| **basename** — only a bare basename appears; the reader may be bound elsewhere | **29** |

The 29 basename-only, by basename:

```
e2e-opsbend.txt 9   e2e-port-mm.txt 9   gate.txt 4   ops_bend-milestone-expected.txt 1
build.txt 1   check.txt 1   census.txt 1   after.txt 1   before.txt 1   closure.txt 1
```

A safety test (`rename.py`'s rationale) then asked, per file, whether a code file that names the
basename ALSO names the target's directory (i.e. is *bound* to it):

* **bound (23)** — keep. `e2epy/oracle-e2e.sh` sets `RUN` and `checks/e2e.py` sets `E2E_ROOT`, so
  the fixture copies under `e2epy/fixtures/*/runs/e2e/` ARE opened by basename through a bound
  dir; `opsbend-milestone.sh:33 RUN="$ROOT/.agents/slop/opsbend-milestone"` binds
  `build.txt`/`check.txt`/`gate.txt`; `ops_bend-milestone-expected.txt` is a stage-5 input.
* **collision (6)** — `dtypeb/gate.txt`, `fp8fix/gate.txt`, `jsfp8/gate.txt`,
  `strays-root/{after,before,closure}.txt`. No code file binds the basename to their directory.

Two of the six were then held back for a stated reason and **not** moved:

* `jsfp8/gate.txt` — its line 1 is `# jsfp8/gate.txt -- …`, i.e. **the file names its own path**.
  Step 6 blocks a rename it would itself cite.
* `strays-root/{after,before,closure}.txt` — evidence deliberately kept under `.agents/slop/` by
  `checks/no-strays.py`'s stated design (*"it is CITED, so MOVE it under `.agents/slop/` and keep
  the basename"*); their paths are named by `agend2/notxt.out` and `emptyblob/summary.json`.
* `peakrss/census.txt` was already REFERENCED by **path**: `AGENTS.md:66` names
  `.agents/slop/peakrss/census.txt`.

## 4. What moved

`os.rename` (never `git mv`), `--dry` first, `.out` by content (both are captured stdout: a
`--check-only` log and a tree/hash banner; neither is traceback- or error-shaped):

| old | new | why it is a collision |
|---|---|---|
| `.agents/slop/dtypeb/gate.txt` | `.agents/slop/dtypeb/gate.out` | `e2e_negctl.sh` names `$NC/runs/e2e/gate.txt`; `dtypeb/run.py` reads `gate_fp8.bend`, not `gate.txt` (`git grep gate\.txt .agents/slop/dtypeb` → rc 1) |
| `.agents/slop/fp8fix/gate.txt` | `.agents/slop/fp8fix/gate.out` | `opsbend-milestone.sh` names `$RUN/gate.txt`; `fp8fix/run.sh` reads `$T/sweep-*.txt`, not `gate.txt` |

**2 moved.** The other 348 are DECLARED (301) or REFERENCED (47, after the two moves), and
`PLAN.tsv` gives each the one-line change that would let it move. **Nothing deleted.**

### The one-line change, per refusal class

* **DECLARED (301)** — the basename must leave `checks/differ.py`'s `declared()` (one line), with
  the sha256-pinned oracle lines that write/read it moving in the same commit; every one of these
  is a COPY under `figurefix/plant/D-live/`, `figurefix/plant/scratch/…`, `rerun/D-before/`, or
  `differverdict/*/…`, and `figurefix/plant/plant.py:54` `copytree(HERE/"D-live", …)` then reads
  `D0-run-summary.txt` by that name — the name is the generator's, not the copy's.
* **REFERENCED-path (20)** — the reader line named in `PLAN.tsv` must name the new extension
  (e.g. `checks/e2e.py:455` `f64 = RUN / "e2e-f64.txt"` → `…".out"`).
* **REFERENCED-basename (29)** — the reader is dir-bound (`$RUN/…`, `E2E_ROOT/…`); the one-line
  change is the same edit at the bound site, and the file moves only when that site does.

## 5. `checks/no-txt.py` HARD, before and after — the delta does NOT equal 2

| reading | HARD |
|---|---:|
| before (this session) | **550** |
| after the 2 renames | **550** |
| delta | **0** |

**0 ≠ 2, and the cause is external, measured.** A re-walk right after the moves:

```
added since session start: 2
   13:01:36  .agents/slop/figure2/plant/broken/runs/graphcmp/D/D0-run-summary.txt
   13:01:36  .agents/slop/figure2/plant/real/runs/graphcmp/D/D0-run-summary.txt
removed since session start: 2
   .agents/slop/dtypeb/gate.txt
   .agents/slop/fp8fix/gate.txt
```

A concurrent unit wrote **2** new `.txt` (mtime `13:01:36`) under a NEW directory `figure2/`, which
offset this unit's **2** renames exactly; the owned total is `689 → 689`. The new files were not in
the 689 census at session start and are not in `PLAN.tsv`. *`689` at session start is itself
already below `sloptxt`'s `711`, so the tree moved before this unit ran too.* **The count is
external movement, not this unit's rename bookkeeping.**

## 6. Limits, stated

* **NEITHER=0 is a real result, not a null one.** It says `sloptxt`'s rename was complete for the
  renamable class. A caller expecting to move 19 will find them already moved.
* **"A committed file names the path" cannot be the REFERENCED test literally**, and `final_split.py`
  measures why: with census artifacts counted, **all 350** are named by path
  (`emptyblob/summary.json`, `unknowns/*.rows`, `sloptxt/PLAN.tsv` …), because a census that
  enumerates a set names every member. The test that means anything is a **reader** — a committed
  code file that opens it — which is what `sloptxt/readers.py` used and what this unit refines.
* **`.out` vs `.err` is a content guess.** `rename.py` chose `.out` for both moves on shape; the
  19 `sloptxt` moved are all `.out` and all content-shape `.out` (checked).
* `jsfp8/gate.txt` stays because it self-names its path; a stricter rule that ignores self-citation
  would move it too.

## Instrument

`.venv/bin/python .agents/slop/capstream/discover.py` · `refsplit.py` · `pathgrep.py` ·
`final_split.py` · `rename.py [--dry]` · `plan.py`
Artifacts: `discover.json`, `refsplit.json`, `pathgrep.json`, `final_split.json`, `safety.json`,
`notxt-before.out`, `notxt-after.out`, `pathgrep.out`, `PLAN.tsv`.
