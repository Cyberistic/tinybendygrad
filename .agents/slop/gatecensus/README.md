# gate census — which of the 148 gate-shaped files are REAL GATES

    .venv/bin/python .agents/slop/gatecensus/census.py --dry-run   # enumerate, run nothing
    .venv/bin/python .agents/slop/gatecensus/census.py -j 10        # run every candidate
    .venv/bin/python .agents/slop/_cleanup/move_gates.py --list     # classify for migration

Artifacts: `census.log` (the run), `manifest.json` (every row), `runs/` (per-gate stdout/stderr),
`classify.log` (the migration classification).

## WHAT A VERDICT MEANS HERE

This instrument exists because of `substrate-check.sh`, which printed `SUBSTRATE CLEAN: 0 file(s)`
when given no arguments — a census that examined nothing and reported all-clear. So verdicts are
mechanical and strict:

| verdict | rule |
|---|---|
| `PASS` | rc 0 **and** output on at least one stream **and** a verdict token seen |
| `FAIL` | rc != 0, after the usage test below |
| `NOT-RUN` | our alarm fired (`rc=124`/`142`), **or** zero bytes on both streams, **or** rc 0 with output but no verdict token |
| `SKIP` | the gate printed usage: bare is a different instrument from "run with its population" |
| `NOT-ATTEMPTED` | excluded by name because running it would edit a tree six units are writing into |

A zero-byte run is a **refusal**, not a pass (`graphcmp.py:2869` refuses `--dev NULL` with 0 bytes).

## THE TWO ORDERING BUGS THIS FILE ALREADY HAD

1. **`rc != 0` was tested before the usage test**, so a gate that prints usage and exits 1 was
   recorded FAIL. It is not red; it is a gate that refused to run without its population.
2. **The verdict regex was unbounded.** `FAIL` matched `FAILSAFE`, `MATCH` matched inside `MISMATCH`
   and inside paths. Tokens are now `\b`-anchored.

## MEASURE ONLY

This file never edits a gate, a `.bend`, or `runtime/**`. A red with a one-line cause is
**reported with the line**, not fixed — the files belong to units that are mid-edit.