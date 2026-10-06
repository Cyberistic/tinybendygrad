# figurefix — `corpus-figure.py` now reads the population it names

**Date:** 2026-10-06 · **Instrument:** `checks/corpus-figure.py` · **Owner of this change:** the figurefix unit
**Files touched:** `checks/corpus-figure.py` only. `checks/differ.py`, `runs/graphcmp/D/`, `checks/sweep.py`,
`checks/coverage.py`, `checks/e2e.py`, `AGENTS.md` untouched. No commit. `bend` never run.

## 1. The population, and the sample that called itself a verdict

| | count | denominator |
|---|---|---|
| pins `checks/differ.py` declares in `PINS` | **17** | 17 |
| pins the old `run_health()` consulted | **3** (`graphs`, `graphs-agree`, `not-comparable`) | 17 |
| pins never consulted | **14** | 17 |
| pins the old regex parse could even *see* | **8** | 17 |

The old parse `^(\S+)=(\S+)$` could not match the **9** values that contain spaces
(`stable-pairs=5 of 5`, `stable-failed=0 of 5`, `stable-differ=0 of 5`, `plants-disagree=7 of 7`,
`cross=1 of 1`, `controls=5 of 5`, `conflations=4 of 4`, `selfcheck=# SELFCHECK: OK`,
`oracle-selfcheck=# ORACLE SELFCHECK: OK`). So the instrument consulted 3 of 17 while being
structurally blind to 9 more. **It printed `RUN HEALTH : OK` over a run that was red on 4 of 17.**

## 2. The live run, measured on a COPY (the live directory was never read directly)

`runs/graphcmp/D/` was copied to `.agents/slop/figurefix/plant/D-live/` first; every reading below
is of that copy. The run is **red on 4 of 17 pins** (13 green):

```
expect-moved=1 (expected 0)   graphs-agree=20 (expected 19)
byte-identical=20 (expected 19)   selfcheck=# SELFCHECK: FAIL (expected # SELFCHECK: OK)
```

Note: `AGENTS.md` records a *different* red set (`census-rc` absent, `oracle-selfcheck FAIL`) —
the run has been regenerated since that measurement. Both of my measurements (before and after the
change) saw the same 4 red pins.

## 3. Before / after, with exit codes

| command | before | after |
|---|---|---|
| `DEV=CPU .venv/bin/python checks/corpus-figure.py` | **rc=0**, `RUN HEALTH : OK -- every one of 25 graphs was COMPARED, 20 agree and 5 disagree` | **rc=1**, `RUN HEALTH : **FAILED** -- 13 of 17 pins green. RED: expect-moved=1 (expected 0); graphs-agree=20 (expected 19); byte-identical=20 (expected 19); selfcheck=# SELFCHECK: FAIL (expected # SELFCHECK: OK).` |
| `env -u DEV .venv/bin/python checks/corpus-figure.py` | **rc=1**, `DEVICE PRECONDITION : **VIOLATED**` | **rc=1**, `DEVICE PRECONDITION : **VIOLATED**` (unchanged — the precondition still fires and was not removed) |

**The `DEV` precondition is confirmed still firing** (rc=1 with `DEV` unset, before and after).

## 4. The change, in `checks/corpus-figure.py`

1. **New `differ_pins()` loader** — imports `PINS` from `checks/differ.py` by path (`importlib`,
   the same pattern as `pinned_dev()` and `load_graphcmp()`). The pins are **never re-declared**;
   a second copy would be a contract with no generator. `differ.py` is stdlib-only at module scope
   and runs nothing at import (`gates/retention-check.py` already imports it the same way).
2. **`run_health()` consults every imported pin** and parses the summary with `differ.unhealthy()`'s
   own parse (split on the **first** `=`, so the 9 space-containing values are visible). It returns
   `(every pin green, the line to print)`. The OK line carries the denominator:
   `OK -- 17 of 17 pins green (checks/differ.py's PINS, imported; graphs=25 and not-comparable=0 among them)`.
   The FAILED line names each red pin with its expected value, in `differ.unhealthy()`'s own format.
3. **`main()` refuses on the bool**, not on the absence of the word `FAILED`. This fixes a latent
   bug found while planting: a missing summary returned a line with neither `OK` nor `FAILED`, so the
   old check let it **exit 0** — a check that measured nothing reporting a pass. Now `**NO RUN SUMMARY**`
   → rc=1.
4. Housekeeping forced by the change: dropped the now-unused `import re`; made the `run_health`
   docstring raw (the `\S` in the old regex raised a `SyntaxWarning`); corrected a stale "five
   conditions" count in the module docstring to "conditions" (17 pins are declared).

**Nothing was widened.** `OK` still means every declared pin matches by content. The green control
in the plant (below) is a *constructed fixture* — the live run's 4 red pins repaired in a copy —
not a relaxation of the criterion. The live tree still refuses.

## 5. The plant — a health check that cannot go red is a comment

Driver: `.agents/slop/figurefix/plant/plant.py`. It runs the **real script** (byte-identical copy)
against a scratch root (`.agents/slop/figurefix/plant/scratch/`) holding a planted copy of the run;
`graphcmp.py` is symlinked and resolves its own REPO through the symlink (`graphcmp.py:271`), so the
real tinygrad is imported. The live tree is never written. **All three cases PASS:**

| plant | fixture | result |
|---|---|---|
| A — green control | the 4 red pins repaired in the copy | **rc=0**, `RUN HEALTH : OK -- 17 of 17 pins green` — proves `OK` is reachable, the check is not vacuously red |
| B — one pin red | `graphs-agree` moved 19 → 18 on the green copy | **rc=1**, `RUN HEALTH : **FAILED** -- 16 of 17 pins green. RED: graphs-agree=18 (expected 19).` — one red pin is caught and named |
| C — no summary | `D0-run-summary.txt` removed | **rc=1**, `RUN HEALTH : **NO RUN SUMMARY**` — measured-nothing no longer exits 0 |

## 6. Counts with their denominators, before and after

| | pins declared | pins consulted | pins green | verdict on the live run |
|---|---|---|---|---|
| before | 17 | **3** | 3 of 3 consulted (run itself: 13 of 17) | `OK` printed, rc=0 — **a figure over a red run** |
| after | 17 | **17** | **13 of 17** | `**FAILED**` naming all 4 red pins, rc=1 — **the figure now tells the truth** |

## 7. Artifacts

- `checks/corpus-figure.py` — the change
- `.agents/slop/figurefix/plant/plant.py` — the plant driver (re-runnable: `.venv/bin/python .agents/slop/figurefix/plant/plant.py`)
- `.agents/slop/figurefix/plant/D-live/` — copy of the live run, taken before reading
- `.agents/slop/figurefix/plant/scratch/` — the scratch root the plant builds
- `.agents/slop/figurefix/before-devcpu.out`, `before-devunset.out`, `after-devcpu.out`, `after-devunset.out` — captured outputs
