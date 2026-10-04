# lintable/ — the ops.py linear rule table

Main write-up: `../LINEAR-TABLE.md`. Run the gate with `sh lintable-gate.sh`.

| file | what |
|---|---|
| `01-WHAT.md` | what the table must do, `file:line` from `tinygrad/uop/ops.py` |
| `02-TABLE.md` | the table, with `ops.bend` line numbers |
| `03-PROBE.md` | the probe, its pairs, and the four defects it caught |
| `04-PLANT.md` | the plant and its paired disarm |
| `05-TOTALITY.md` | where the port is total and Python raises |
| `06-UNBLOCKED.md` | what actually unblocked, with the denominator |
| `lintable-probe.bend` | the probe (54 rows: 36 shared, 33 bend-only, 15 `_n` companions) |
| `lintable-oracle.py` | the CPython lane; every expectation computed, none typed |
| `lintable-gate.sh` | three lanes + `--plant` / `--disarm` |
| `BEFORE-*` | pre-edit baselines, **captured before the first edit and never re-recorded** |
| `AFTER-*`, `*-py.txt`, `*-bd.*`, `*-bn.*` | lane outputs |
| `ops-names.txt` | the 77 `Op` constructors, used to generate `all_ops()` |

`plant/` is a throw-away COPY of the tree that `--plant` creates and destroys. It is
deleted after each run and is not an artifact: a `$TMPDIR` scratch copy cannot resolve a
relative import, which produced 22 phantom blind spots in one unit, so the copy keeps
the relative depth. Re-created on demand by `lintable-gate.sh --plant`.
