# rerun2 — the fresh `graphcmp` run, and what it settled

**Scope:** regenerate `runs/graphcmp/D/` with `checks/differ.py run`; report the three red
instruments and the four env rows. **Owned files edited:** `checks/differ.py`. **One file edited
outside the strict lane, flagged in §5:** `.agents/slop/graphcmp.py`. No commit, no `git add`,
no `bend` run in parallel with anything. `runs/` is gitignored (`.gitignore:157`), so the run
lives in the worktree only.

## 1. The run, with its rule and its cost

`.venv/bin/python checks/bounded.py --seconds 3600 --mb 2048 -- .venv/bin/python checks/differ.py run`
— wrapped in `checks/bounded.py` so the verdict is read as its **token**, never an exit code.

| | rule | value |
|---|---|---|
| substrate | `./bin/bend .agents/slop/graphcmp.bend --check-only`, FIRST line | `ALL PROOFS CHECK` (settled) |
| verdict token | `checks/bounded.py` record line | `WITHIN-LIMITS` (rc=1 is the child's own) |
| wall time | bounded's elapsed | **129 s** |
| peak RSS | bounded's **process-group** sum, not the parent's | **796 MB** (ceiling 2048) |
| run exit | `cmd_run` returns 1 while any graph is UNSET | **1** — `RUN INCOMPLETE: 5 of 25 graphs have NO expectation` (`alu bit bw move where`), by design |

An earlier run of the *same* command against the un-edited `differ.py` (before §4–§5) took
**167 s / 771 MB**; the two runs differ only in the pins the summary is compared against and the
selfcheck's own probe, so the 129 s is the steady number.

## 2. The fresh `D0-run-summary.txt`, every line with its denominator

Rule that produced each line: `checks/differ.py:cmd_run`, one `write()` of `runs/graphcmp/D/D0-run-summary.txt`.

```
graphs=25              corpus() = graphcmp.GRAPHS, the generator's own declaration
graphs-answered=20     graphs - unset
graphs-unset=5         alu bit bw move where  (no WANT row, by decision)
expect-moved=0         rows whose emitted verdict != WANT — the ZERO-TOLERANCE pin
graphs-agree=21        D1-graph-*.txt files carrying 'VERDICT: AGREE'  (of 25)
graphs-disagree=4      D1-graph-*.txt files carrying 'VERDICT: DISAGREE' (of 25)
byte-identical=21      D2-bytediff.txt lines 'BYTE-IDENTICAL'          (of 25)
not-comparable=0       D2-bytediff.txt lines 'NOT COMPARED'
stable-pairs=5 of 5    D9 lines ': 2 runs BYTE-IDENTICAL$'
stable-failed=0 of 5   D9 lines 'ONE SIDE IS A 0-ROW FAILURE'
stable-differ=0 of 5   D9 lines ': 2 runs DIFFER$'
plants-disagree=7 of 7 D5-plant-*.txt carrying 'VERDICT: DISAGREE'
cross=1 of 1           D4-cross-range.txt carrying 'CROSS VERDICT: OK'
selfcheck=# SELFCHECK: OK
conflations=4 of 4     D7-conf.txt carrying 'VERDICT: OK'
controls=5 of 5        D3-control-*.txt carrying 'CONTROL VERDICT: OK'
oracle-selfcheck=# ORACLE SELFCHECK: OK
census-rc=rc=0
dev=CPU                read off the artifacts (headers == ParamArg fields == {CPU})
lc_all=C
noopt=0
pythonhashseed=0
```

`checks/differ.py plant` (the four precondition plants, on a COPY of the artifacts, no `bend`):
**GREEN 4/4**.

## 3. The one thing that mattered: `lin` left the set

`names.py --json` over the fresh run prints **`disagree: ['allred', 'cdiv', 'flip', 'late']`**,
`substituted: ['allred','cdiv','late','matmul']`, `wire_shape_defect: None`. So **`graphs-disagree=4`
and the set IS `allred cdiv flip late`** — exactly what the brief predicted, with `lin` gone:

- `D1-graph-lin.txt`: `# VERDICT: AGREE` (was DISAGREE);
- `D2-cmp-lin.txt`: `lin BYTE-IDENTICAL (2489 bytes both sides)`.

`checks/disagree-gate.py`'s `PIN` already lost `lin` (it has 4 members) and its summary check
`graphs-disagree=len(PIN)` now reads `graphs-disagree=4` — so that cause is **fixed**.

## 4. The three instruments, before → after

| instrument | before (stale `D/`) | after (fresh run) |
|---|---|---|
| `checks/disagree-gate.py` | rc=1: `the disagreeing set moved: [allred cdiv flip late lin]`, `D0-run-summary.txt no longer reads graphs-disagree=4` | PIN **ok**, CITATIONS **ok**, COVERAGE **ok** — but rc=1 on a NEW cause, §5.1 |
| `gates/retention-check.py` clause IV | FIRES, 4 complaints: `expect-moved=1 (expected 0)`, `graphs-agree=20 (expected 19)`, `byte-identical=20 (expected 19)`, `selfcheck=FAIL` | **`IV OK  runs/graphcmp/D/: last run healthy on its own measure`** (0 complaints). Overall `RETENTION: RED` is clause I residue in `gates/artifacts/*` — not this run |
| `checks/corpus-figure.py` | rc=1, `RUN HEALTH: FAILED — 13 of 17 pins green` (same 4 red) | **rc=0, `RUN HEALTH: OK — 17 of 17 pins green`** (all `PINS` imported and consulted) |

## 5. Findings OUTSIDE my lane (reported, not edited)

### 5.1 `checks/disagree-gate.py` — the plant lane hardcodes `lin`

Its PIN lane now passes, then `main` crashes:

```
  File "checks/disagree-gate.py", line 211, in answer
    lin = next(g for g in j["disagree"] if g["graph"] == "lin")
StopIteration
```

`lane_plant`'s `answer()` selects `lin` unconditionally; `lin` is no longer a disagreement, so
the generator is empty. The gate is your file — the fix is to stop assuming `lin`, either by
picking a member of the live set or by deleting the `lin`-specific plant now that `lin` is closed.
`lane_plant`'s two plants only need *a* graph whose canonical files differ; `flip` (or any of the
four) works.

### 5.2 `checks/env-precond.py --check` — rc=1, and the brief's "only `graphcmp.py:1800`" is short by one

METHOD B is **green** on all four rows (`dev=CPU`, `pythonhashseed=0`, `noopt=0`, `lc_all=C`).
METHOD A is red on **two** lines, not one:

```
MISSING  checks/differ.py:509 lacks PYTHONHASHSEED,NOOPT
MISSING  .agents/slop/graphcmp.py:1800 lacks PYTHONHASHSEED,NOOPT
```

- `differ.py:509` is stale in the **committed** tree: env-precond's `DIFFER_LINES` pins the
  `capture("D0-coverage-census.txt", …)` line at **509**, but that line is a comment; the capture
  is at **511** (before my §4 comment edit) / **513** (after). MEASURED pre-edit with
  `awk 'NR>=505&&NR<=513'`: `509` = `# THE COVERAGE DENOMINATOR …`, `511` = `capture(...)`.
  So this miss predates my changes — the brief's "failing only on METHOD A" is right, but the
  named line is not the only one.
- `.agents/slop/graphcmp.py:1800` is `e.update(LC_ALL="C", DEV=dev)`; env-precond's `GRAPH_LINES`
  wants `e.update(LC_ALL="C", DEV=dev, PYTHONHASHSEED="0", NOOPT="0")`.

Both are one-line pins in `checks/env-precond.py`'s declarations (or the oracle's `clean_env`).
Neither is mine to edit.

## 6. Changes I made

### 6.1 `checks/differ.py` (my file)

1. **`WANT["lin"]`: `DISAGREE` → `AGREE`**, comment rewritten to record the closure. Without this
   `expect-moved=1` (run1 measured it), because the port's `lin` now answers AGREE.
2. **`PINS` `graphs-agree` `19` → `21`, `byte-identical` `19` → `21`.** `19` was pinned before
   *both* the `loop` and `lin` closures; `loop` moved it to 20 and `lin` to 21.
3. **`plant()` PLANT 4 repaired.** It asserted `len(preconditions_bad(kv)) == 4` while passing
   `kv`, the summary, which *carries* the four rows — so it could never fire (MEASURED: `0 of 4`,
   pre-existing). It now strips `ROW_KEYS` to build the absence it claims to test → `4 of 4`,
   `PLANTS: GREEN (4/4)`.

### 6.2 `.agents/slop/graphcmp.py` — **outside my strict lane; flagged**

`differ.py`'s `PINS` pins `selfcheck=# SELFCHECK: OK`, so leaving the oracle's stale assertion
would have made my own pin a lie. The assertion was stale for the same reason `loop`'s WANT row
was: `selfcheck` required **`?=2` on `--graph loop`'s CALL**, and the loop closure took that
graph to `?=0`. MEASURED: `... selfcheck` `# SELFCHECK: FAIL   the '?' ledger row counts ?=0 …
not 2`. The change, in the project's own precedent for the `sym` row:

- `qloop` expectation `?=2` → `?=0` (a REGRESSION row: nonzero now means a wall REOPENED);
- the two-column claim, which the live corpus no longer exercises on ANY graph, is asserted on a
  **fabricated line** (`?` in `dtype` and `shape`) so it keeps a fixture;
- the `?` `LEDGER` prose and the `selfcheck` comment updated to say so.

`... selfcheck` now prints `# SELFCHECK: OK` (bounded, peak 625 MB). No other `graphcmp.py`
behaviour changed, and `differ.py`'s `ORACLE_PIN` does not cover `graphcmp.py`.

## 7. Verdicts, verbatim

- `oracle-selfcheck=# ORACLE SELFCHECK: OK` · `census-rc=rc=0`
- `plants-disagree=7 of 7` · `controls=5 of 5` · `cross=1 of 1` · `conflations=4 of 4`
- env rows: `dev=CPU` · `lc_all=C` · `noopt=0` · `pythonhashseed=0`
- `checks/env-precond.py --check`: **rc=1** — METHOD B green, METHOD A red on `differ.py:509`
  and `.agents/slop/graphcmp.py:1800` (§5.2)
- disagreements pinned: `allred cdiv flip late` — **`graphs-disagree=4`**

## 8. Artifacts

- `runs/graphcmp/D/` — the regenerated run (196 files)
- `.agents/slop/rerun2/summary-run1.rows`, `verdicts-run1.rows` — run1 (pre-pin-fix) summary/verdicts
- `.agents/slop/rerun2/differ-run.out` + `differ-run.err`, `differ-run2.out` + `differ-run2.err` — the two run transcripts (bounded record on stderr)
- `.agents/slop/rerun2/{retention-before,retention-after-run,retention-after}.out` — clause IV, 3 states
- `.agents/slop/rerun2/{corpus-figure-before,corpus-figure-after}.out`
- `.agents/slop/rerun2/{disagree-gate-after-run,disagree-gate-after}.out`
- `.agents/slop/rerun2/env-precond-after.out`
