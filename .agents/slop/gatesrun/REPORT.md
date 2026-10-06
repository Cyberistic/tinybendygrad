# gatesrun — a gate that cannot run is a gate nobody runs

`.agents/slop/gatesrun/` · 2026-10-06 · **nothing committed.** Every number carries the
instrument that produced it. `rc` and the **verdict TOKEN** are both reported, because a raw
`rc` column cannot separate *ran and got the wrong answer* from *could not run at all*.

---

## 1. THE POPULATION, BY DISCOVERY

`run.py` walks **both gate homes** with `iterdir` (never `rglob`, so `__pycache__` is not
descended) and keeps `.py`/`.sh`. An **entry point** is a Python file with an `if __name__`
guard (read off the AST) or a shell file that self-references `$0`. `gates/gates-pop.py`'s
ledger is **not** read — the population is recomputed, and its **path set is identical** to the
ledger's 92 (`diff <(tail -n+2 ledger | cut -f1 | sort) <(tail -n+2 run-classes.tsv | cut -f1 |
sort)` → rc=0).

| denominator | count | instrument |
|---|---|---|
| `.py`/`.sh` files under `checks/`+`gates/` | **99** | `iterdir`, `run.py` |
| **entry points** (the population) | **92** | AST `__main__` / shell `$0` |
| libraries (no guard) | **7** | `checks/gen_gate.py plant.py reorder-gate.py reset.py rw-gate-oracle.py stage1-census.py`, `gates/gatekit.py` |

**THE CLASSIFIER, BY WHAT THE FILE DOES, NOT ITS NAME** (`finalize.py`; the `cause` column of
`CLASSES.tsv` carries the per-row evidence):

| class | rule | count |
|---|---|---|
| `gate` | imports `gates/gatekit.py`, **or** asserts a property and exits nonzero on a violation | **50** |
| `oracle` | emits expected `name=value` rows, consumed by a diff; no verdict of its own | 14 |
| `driver` | exercises a port/tool/hardware; needs args, a dep or a device | 21 |
| `wrapper` | delegates to the program that is the gate (shell shim, `exec`) | 5 |
| `mutator` | rewrites a source file | 2 |
| **not a gate at all** | `oracle`+`driver`+`wrapper`+`mutator` | **42 / 92** |

**42 of 92 entry points are not gates.** They are in the population only because
`gates-pop.py`'s population predicate is *"has an `__main__` guard"*, not *"is a gate"* —
doctrine 1 inside the instrument that enforces doctrine 1.

## 2. THE FIVE VERDICTS, WITH THEIR DENOMINATORS

`RUN` = **28** (the rest invoke `bend`, exclusively another unit's, or are meta-instruments
that write state). **`SKIP` = 64, and SKIP is not a pass.**

| token | all entries | gates | not-gates |
|---|---|---|---|
| `PASS` | 12 | 6 | 6 |
| `REFUSED` (rc=3) | 3 | 3 | 0 |
| `FAIL` | 5 | 3 | 2 |
| **`DEAD`** | **8** | **0** | **8** |
| `SKIP` | 64 | 38 | 26 |
| **TOTAL** | **92** | **50** | **42** |

Executed, with rc and token:

```
PASS    gate     rc=0  checks/devgate.py · devpin.py · no-shrink.py · no-strays.py · norm_check.py
PASS    gate     rc=0  checks/test_rewrite_bottom_up_gate.py
REFUSED gate     rc=3  checks/dup-gate.py · gate.py · hermetic-census.py
FAIL    gate     rc=1  checks/env-precond.py · no-txt.py · repro-paths.py
PASS    oracle   rc=0  gates/ew-consts-oracle.py · ew-explog-oracle.py · ops-core-oracle.py
PASS    oracle   rc=0  gates/wk-cd-oracle.py · wk-eval-oracle.py · checks/render-gate-oracle.py
DEAD    driver   rc=1  checks/classify.sh · compile.py · fw_live.py · llama.py · romless.py · run.py · sz.py
DEAD    driver   rc=2  checks/lint_demo.sh
FAIL    driver   rc=1  checks/corpus-figure.py · process_replay.py
```

**THE FINDING THIS TASK EXISTS FOR: every `DEAD` is a non-gate, and no gate is `DEAD`.**
`classify.sh` dies on `$1: unbound variable`; `lint_demo.sh` does not parse (`syntax error:
unexpected end of file`); `compile.py`/`run.py`/`sz.py`/`llama.py`/`fw_live.py`/`romless.py`
die on a missing module (`llvmlite`/`hexdump`/`tabulate`/`extra`/`common`). A caller reading
only `rc` sees `1` for all eight **and** for the five real `FAIL`s and cannot tell them apart.
That is why the token column exists.

## 3. THE VOCABULARY IS ONE LAYER TOO HIGH — RE-MEASURED

`gates/gatekit.py:59` defines `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. Only the
**13 gatekit gates** can emit `DEAD = 5`, **and not one of the 8 measured `DEAD`s is a gatekit
gate** — they are plain scripts that exit `1` (or `2`) after a `ModuleNotFoundError`. So `DEAD`
is spelled in a vocabulary the dead files never import: **0 of 8 dead gates emit the token for
dead.** `REFUSED = 3`, by contrast, *is* honoured outside gatekit — all three `REFUSED`s use
`sys.exit(3)`.

## 4. THE NAMED DEFECTS

### 4.1 `checks/dup-gate.py` — ALREADY FIXED, RE-MEASURED ONLY

`.venv/bin/python checks/dup-gate.py` → **`rc=3`, `REFUSED`**:
`input absent: …/.agents/slop/eq/eq-census2.py (swept by 371cc64c9; recoverable from git at
371cc64c9^:)`. Pre-fix this was `rc=1` + `FileNotFoundError`. Still refused, now honestly.

### 4.2 `checks/norm_check.py` — ALREADY FIXED, RE-MEASURED ONLY

`.venv/bin/python checks/norm_check.py` → **`rc=0`, `PASS`**: `FIXED 5/5 assertions hold   PLANT
(repr(float(s)) with no round trip) 4/5`. The built-in plant fails 4 of 5, so the passing five
are shown able to move.

### 4.3 `.agents/slop/helpers-tc-gate.sh` — **THE ORACLE IS WRONG**, AND THE CITATION IS TOO

`helpers-tc-gate.sh:64` is `diff "$GT.rows" "$GT.bd"`; `:66` echoes `237 shared rows, 3 lanes
identical`; `REVIVE.md:217` cites that echo at `rc=0`. **`:66` cannot execute while the diff
fails, and the diff failed on exactly one row.** Measured on the committed lanes:

```
diff .agents/slop/helpers-tc-gate.rows .agents/slop/helpers-tc-gate.bd
237c237
< d_i64min_d=2147483648:0                 <- the ORACLE's `.rows`
---
> d_i64min_d=-9223372036854775808         <- the PORT (and .bn, byte-identical)
```

**Decision: the oracle is wrong.** `helpers-oracle.py:286-291` claimed *"the port answers
`2147483648:0` — the bit pattern — because Bend's `I64` cannot hold the magnitude 2\*\*63"*, and
`dec_limit()` substituted that bit pattern for CPython's own `str`. **The port answers the
decimal — CPython's true `str` — so the oracle was encoding the port's asserted answer as the
expected value, which is inverted and tautological.** `deadgens` diagnosed exactly this
(`5bf27ad2f`) and named the one-line fix, declining it because the oracle is a byte-exact
restore; the fix is safe (no `bend`) and is what makes the gate legitimately green **without
widening the diff**:

- `helpers-oracle.py`: `dec_rows()` now prints `_d={v}` for every fixture; `dec_limit()` is
  deleted; the `286-291` prose is replaced with the measurement.
- `.agents/slop/helpers-tc-gate.rows` regenerated from the fixed oracle (only line 237 moved).
- `diff .rows .bd` → **rc=0**, `diff .bd .bn` → **rc=0**. The gate reaches `:66`.

**Separately, `REVIVE.md:217` is a false citation** — it reports `rc=0` for a run whose `:66` is
unreachable. It is a *second*, independent defect: fixing the oracle makes the line reachable
*next* run, and cannot make the historical claim true.

**PLANTS** (`plant-helpers-tc.py`, `.out` beside it) — **3/3 GREEN**, driving the gate's own
`diff` against the committed `.bd` (no `bend` run):

```
PASS  GREEN   fixed .rows              vs .bd          diff rc=0
PASS  PLANT-A PRE-CHANGE oracle (git)  vs .bd          diff rc=1   <- the pre-change file FAILS
PASS  PLANT-B fixed .rows              vs BROKEN .bd   diff rc=1   <- a wrong port FAILS
```

### 4.4 `checks/hermetic-census.py:108,120` — LATENT `.txt`, A `TODO`, NOT A FIX

Both writes (`census()` and `check()`) produce `rows-<node>-<side>.txt`, against the house rule.
They are **unreachable**: the module-level `refuse()` calls `sys.exit(3)` at *import*, before
`import isolate`, and `isolate.py` is swept — so `checks/no-txt.py` cannot see a file the gate
never writes. **A `TODO` comment is the right act** and is added at both sites (the second names
the first). Renaming them is not this unit's call, and would be *the fix for a file that has
never run*.

**PLANTS** (`plant-hermetic.py`) — **4/4 GREEN**, all measurements, because the change is inert:

```
PASS  A ordering          module-level refuse() at lines [61,67,72] sit ABOVE the .txt sites [114,126]
PASS  B still refused     rc=3, names isolate.py  (the change is inert)
PASS  C guard removed     the isolate refusal block is removed on a copy
PASS  C unreachable twice rc=1, ModuleNotFoundError: No module named 'isolate', no rows written
```

C is the load-bearing one: strip the guard and the write **still** does not run, because the
`import isolate` beneath it fails first. The `.txt` is latent for two independent reasons, which
is what a `TODO` records and a rename would paper over.

## 5. THE THIRD HOME: THE NAMED DEFECT IS OUTSIDE THE POPULATION

`helpers-tc-gate.sh` lives at `.agents/slop/`, **not** in `HOMES = ("checks", "gates")`. It is a
`.sh` gate with a self-dispatch entry that `gates-pop.py` cannot discover by construction — the
`HOMES` hand list the file itself admits. **The task's headline gate cannot run and is not even
counted**, which is the same defect the task describes, one level out.

## 6. WHAT WAS NOT RUN, AND WHY

`SKIP` = 64. Every entry that **invokes `bend`** — directly, through `gatekit`, or through a
shell wrapper whose target invokes it — was **not executed**: `bend` is another unit's
exclusively. That set includes all 13 gatekit gates, `differ.py`, `e2e.py/.sh`, `bounded.py`,
`census.py`, `gate_norm.py`, `jsfix_gate.py`, `substrate.py`, `sb-gate.sh`, and the run
harnesses. Also `SKIP`: `gates/gates-pop.py`, `gates/gendirs.py`, `gates/retention-check.py`
(meta-instruments that **write state** on a bare run — read, not run), `cli.py`/`serve.py`
(servers), and `residue.py` (`timeout >120s`). **A SKIP measures nothing and is never reported
as a pass.** The runner's `bend` detector was widened after a first pass was too narrow; the
final table reflects the wide detector, and `both-census.py`/`al-verdict.py` — executed in the
narrow pass — are `SKIP` in the final run.

## 7. FILES

- edited: `.agents/slop/helpers-oracle.py` (the fix), `checks/hermetic-census.py` (the `TODO`)
- regenerated: `.agents/slop/helpers-tc-gate.rows`, `.agents/slop/helpers-tc-gate.rows.err`
- **`CLASSES.tsv`** — one row per entry point: `path, class, rc, token, cause, answer`
- instruments: `run.py` (discovery+run), `finalize.py` (class), `plant-helpers-tc.py`,
  `plant-hermetic.py`, `scan.py` (signal dump), captures `*.out`/`*.err`
- **not committed.** `checks/dup-gate.py`, `checks/norm_check.py`, `gates/gatekit.py`,
  `gates/gates-pop.py`, `gates/gendirs.py`, `gates/retention-check.py`, `checks/differ.py`,
  `checks/sweep.py`, `AGENTS.md` — untouched. `gates/README.md`, `gates/gates-pop.py`,
  `gates/gates-pop.ledger.tsv` show modified in `git status` from **concurrent units**, not
  this one.
