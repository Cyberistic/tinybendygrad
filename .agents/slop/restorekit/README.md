# Why this file exists

`gates/retention-check.py` gates four clauses of the retention rule. Two of them can fire for a
reason that has nothing to do with the rule: a plant, and a run that failed. If neither moves the
verdict, the instrument is reporting the tree rather than the rule.

Both plants run against a COPY, through the instrument's own `--dir`, so the live tree is never
the thing under test. `checks/differ.py` is imported and its `D` rebound, so the unhealthy-run
plant exercises differ's real `unhealthy()`/`artefacts_ok()` rather than a copy of them.

    .venv/bin/python .agents/slop/restorekit/plants.py

| plant | clause | moved the verdict |
|---|---|---|
| injected residue (`PLANTED.txt` in a clean gate dir) | I | 9/9 clean -> 8/9, 1 RESIDUE, exit 1 |
| injected unhealthy run (a `D0-run-summary.txt` with wrong pins) | IV | 64 -> 66 complaints, exit 1 |
| injected LEGITIMATELY EMPTY `*.err` | IV | **no move** -- and that is the point |
| injected healthy run (every pin correct, every artifact non-empty) | IV | fires -> OK |

The third row is the one that matters most and the one most likely to be wrong. `artefacts_ok()`
excludes `*.err` deliberately, because a healthy run may hold legitimately empty stderr, and *a
rule that flags a correct file is a rule that always fails*. If this plant moved the verdict, the
instrument would be one `.err` away from failing on every correct run in the repo. It does not
move, and that is inherited from `checks/differ.py:438` rather than reimplemented here.
