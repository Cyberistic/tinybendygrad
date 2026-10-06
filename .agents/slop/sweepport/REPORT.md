# sweep.py — the population it rosters does not include the port

Unit: `sweepport`. Owner of `checks/sweep.py`. Measured 2026-10-06 ~13:55–14:16.
Interpreter `.venv/bin/python` throughout; `bend` never run. No commit, no `git add`.

## Verdict

- **`tinybendygrad/` is a population `sweep.py` has NEVER walked** — HEAD's `checks/sweep.py`
  mentions the string `tinybendygrad` **0 times** (`git show HEAD:checks/sweep.py | grep -c`).
  The classification walk is `os.walk` over `RESIDUE_ROOTS = (".agents/slop", "runs")`
  (`checks/sweep.py:72`, `:556-572`), so all **144** files of the shipped port reach **no verdict at
  all**. A missing population and an unclassifiable row are the same silence.
- **Landed:** a report-only port arm. `--plan` now prints the port's buckets and its `needs=`
  breakdown. It is **never fed into `rows`**, so no `--apply` argument can reach it — the tree SHIPS,
  and a population a DELETE-capable pass can walk is a population it can destroy. Fail-safe by
  construction, not by remembering.
- **Fixed:** the stale `103` at `checks/sweep.py:212` → `139`.
- **No slower:** `--plan` wall `4:46.16` before → `4:39.57` after. The added arm walks 144 files.

## 1. The populations, by discovery (`file:line`, and what each misses)

| # | site | `file:line` | how it declares its population | what it MISSES |
|---|---|---|---|---|
| 1 | classification WALK | `walk_residue` `checks/sweep.py:556-572`; roots `:72` | `os.walk` over `RESIDUE_ROOTS = (".agents/slop", "runs")` | **every file outside those two roots.** MEASURED: `tinybendygrad/` 144, `tinygrad/` 441, `test/` 479, `examples/` 277, `checks/` 232, `gates/` 118, `oracles/` 358, `docs/` 34. So `ROLE_DIRS`' `checks`/`gates`/`oracles` entries can only fire for *shadow copies nested under slop/runs*. |
| 2 | liveness CLOCK | `live_set` `:582-594` | `os.walk` over `SLOP`, `RUNS` | same two roots; it is a clock, not a classifier. |
| 3 | live ROSTER | `live_units` `:600-637` | `os.walk(".agents/slop")`, first path component vs newest mtime | **`runs/` is never consulted**; `tinybendygrad/` never consulted. Lower bound on liveness (documented there). |
| 4 | write-TARGET discovery | `self_output_dirs` `:118-197` | AST over `glob("checks/*.py") + glob("gates/*.py")` (`:157-158`) | a writer that does not live in `checks/` or `gates/` — e.g. a `.agents/slop/*.py` or a port script — is invisible. Found: `.agents/slop/residue` only. |
| 5 | CITATION corpus | `NAMED_BY` `:108-110` + `committed_files` `:305-357` | `git ls-files` over 7 pathspecs + tracked `.agents/slop/**/*.md` (any depth) | `.agents/slop` non-`.md` (`.py`/`.sh`/`.rows`); `tinybendygrad/**` (correct — port source is not a report). |
| 6 | naming AUTHORITY | `declared_names` `:408-425` | imports `differ.declared()` | nothing — this one is a generator's own declaration, the correct shape. |
| 7 | empty-dir prune | `main` `:913-919` | `os.walk(SLOP/RUNS, topdown=False)` | the two roots only. |

**A population claim that the code does NOT implement (secondary finding).**
`house_excluded`'s docstring (`:215-217`) states the house rules must exclude a path "for the CITATION
INDEX **and for the WALK**." MEASURED: `house_excluded` is called at **exactly one** site,
`checks/sweep.py:345` — the corpus filter. `walk_residue` never calls it, so `residue.EXCLUDED_DIRS`
(`xd1`, `strays`, `diffpy`, `lost`, `f64`… ) are excluded from the citation index but **are still walked
and classified**. Not fixed here (out of scope, and it moves the DELETE count for other units' rows).

## 2. What a `tinybendygrad/` arm WOULD see

`os.walk`, no suffix filter — **144 files** (138 `.bend`, 3 `.js`, 2 `.c`, 1 `.mjs`). Under the
current rules (`verdict_for`), from the `--plan` after-run at 2026-10-06 14:09:

| bucket | files | /144 |
|---|---|---|
| KEEP-CITED | 119 | 82.6% |
| UNKNOWN | 24 | 16.7% |
| ORACLE | 1 | 0.7% |
| DELETE | 0 | 0.0% |

**24 of 144 rows are `UNKNOWN:<needs>` — the sweep's rules cannot place them, and `UNKNOWN` is not a
pass.** Printed breakdown at 14:09: `residue-internal-citer 16`, `belts-disagree 4`,
`commit-the-report-that-explains-it 4`.

Per-path detail (`probe.py`, read a few minutes later — one row drifted because the tree is live; the
`needs=` split read `15 / 4 / 5` there, the printing above is the authoritative `--plan` read):

- `belts-disagree` (4): `dtype.bend`, `codegen/decomp/dtype.bend`, `mixin/dtype.bend`,
  `runtime/support/rdma/bnxtdev.bend` — the token regex and the path scanner disagree on citing them.
- `residue-internal-citer` (15–16): `engine/worker.bend`, `runtime/ops_null.bend`,
  `runtime/support/compiler_{amd,cpu,cuda,qcom}.bend`, `runtime/zz{diag,read,split}.bend`, … — named
  only from inside `.agents/slop`.
- `commit-the-report-that-explains-it` (4–5): `codegen/late/coalesce.bend`, `runtime/support/amd.bend`,
  `runtime/support/compiler_llvm.bend`, `runtime/support/zz_objc_mutant.bend`, `viz/cli.bend`.
- `ORACLE` (1): `tinybendygrad/test/dtype_oracle.bend` — an oracle-*shaped* name the corpus names.

The 119 `KEEP-CITED` are port source some report happens to name; that bucket is a **lower bound on
value, not a statement about the port**, which is why the arm is report-only.

## 3. Retiming

`--plan` **is the bare run** — `main` takes the plan branch when `not args.apply`, so bare
`checks/sweep.py` and `checks/sweep.py --plan` are the same work. **There is no `--only <area>` path**
(no such flag exists; `grep -n only` finds only prose).

| run | wall | user | sys | residue rows |
|---|---|---|---|---|
| before (HEAD code) | **4:46.16** | 158.74 | 118.91 | 4906 |
| after (this unit) | **4:39.57** | 161.74 | 114.52 | 4957 |

Wall moved −6.6 s (noise; the two runs disagree on the live tree by 51 rows because other units wrote
during them). The added arm walks 144 files. **Not slower.**

Phase attribution (`probe.py`, one pass; the production `Facts` calls `committed_files` **twice**):

```
tracked_files      0.06s  (6402 paths)
walk_residue       0.09s  (5010 rows)
residue_copies     2.36s  (1417 copies)
declared_names     0.00s  (350 names)
committed_files   66.20s  (411 corpus files)   <-- the cost: one `git show HEAD:<path>` per file
facts() TOTAL     69.31s
```

The 4:46 wall is dominated by `committed_files` (one `git` subprocess per corpus file, invoked twice)
plus the 3-window classify loop — **not** by the walk. So the port arm is free.

## 4. The change landed (narrow)

- `checks/sweep.py:575-596` — `port_files(root, base=None)`: walks `tinybendygrad/`, no suffix
  filter. `base` is a parameter so the arm can be planted against a fixture (the `witness_committed`
  lesson: a walk that reads a global cannot be exercised against a tree the plant did not write).
- `checks/sweep.py:599-622` — `port_report(f, population=None)`: classifies the population with the
  same `verdict_for`, returns `(buckets, needs, total)`. **REPORT-ONLY.**
- `checks/sweep.py:901-914` (in `main`) — prints the port block into the `--plan` output. It returns
  counts; it is never appended to `rows`, so `--apply` cannot reach it.
- The port root is a literal in `port_files`, the same shape as `SLOP`/`RUNS`/`CHECKS`/`ORACLES`
  (`:68-71`) — a single named root, not a roster.

**Why report-only and not `RESIDUE_ROOTS += ("tinybendygrad",)`:** that would make the port a bucket
`--apply DELETE` can reach. Today the port classifies to **0 DELETE**, so nothing would be deleted
*yet* — but the fallthrough is `return "DELETE"`, and a restructure that un-names a port file would
silently make it deletable. **A population a destructive pass can walk is a population it can
destroy, and `SKIP`/silence is not a pass.** Secure → correct → fast.

## 5. The stale literal

`checks/sweep.py:212` — `house_excluded` docstring, naming the class the file exists to warn about:

- old: `` `LIVE_UNITS`, `ORACLE_WORD` and the 103 `.txt` names in one session ``
- new: `` `LIVE_UNITS`, `ORACLE_WORD` and the 139 `.txt` names in one session ``

`139 = len(differ.declared())`, the carve-out two other witnesses (`checks/README.md:51-58`,
`checks/no-txt.py`) were already moved to hours earlier. Confirmed this is the only `103` in the file.

## 6. Plant — the arm MOVES with its subject

`plant.py` drives `port_report` over a fixture port tree via `base=`, two states, real `tinybendygrad/`
untouched:

| state | files | buckets | needs |
|---|---|---|---|
| A: one file a report names | 1 | `{KEEP-CITED: 1}` | `{}` |
| B: + one file nothing names | 2 | `{KEEP-CITED: 1, UNKNOWN: 1}` | `{commit-or-drop: 1}` |

- funnel MOVED: `1 → 2` files. verdict CHANGED: `['KEEP-CITED'] → ['KEEP-CITED','UNKNOWN']`.
- UNKNOWN ADDED: `0 → 1`. **`PLANT PASSED`** (rc=0).

An arm that returned a constant would fail this. The production read (144 files, 24 UNKNOWN) is the
same function over the real tree.

## Artifacts (this unit's directory)

`pop.py`/`pop.out` · `probe.py`/`probe.out` · `plant.py`/`plant.out` ·
`plan-before.out`/`plan-before-stderr.err` · `plan-after.out`/`plan-after-stderr.err`.

## Reproduce

```
.venv/bin/python checks/sweep.py --plan        # full run, ~4:40
.venv/bin/python .agents/slop/sweepport/plant.py   # PLANT PASSED, rc=0
```
