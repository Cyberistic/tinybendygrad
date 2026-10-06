# `env-precond.py` crashed where it should refuse — reproduced, fixed, planted, and the class surveyed

Scope: `checks/env-precond.py` only. Live tree read-only; `bend` not run. Nothing committed.

## 1. Reproduced

The report from `runsgate` (commit `5bc4ed6b6`) is correct, and the crash is `--record`, not `--check`.

`runs/graphcmp/D` absent, `--check` does **not** crash — it returns **1** with `no run summary`
(an absent run reported as a FAIL). `--record` crashes:

```
File "/…/checks/env-precond.py", line 255, in record
    o = observed()
File "/…/checks/env-precond.py", line 149, in observed
    for ln in (ROOT / "runs/graphcmp/D/D2-canon-py-late.txt").read_text().splitlines()
File "/…/lib/python3.12/pathlib.py", line 1013, in open
    return io.open(self, mode, buffering, encoding, errors, newline)
FileNotFoundError: [Errno 2] No such file or directory: '…/runs/graphcmp/D/D2-canon-py-late.txt'
rc = 1
```

- **Type**: `FileNotFoundError`. **Raiser**: `checks/env-precond.py:149` in `observed()`, first reached
  from `record():255`.
- **Exit 1** — the *same* code a legitimate FAIL uses, so an absent run was indistinguishable from a
  wrong answer except for the traceback. A traceback is none of the five verdicts.

Method: `.agents/slop/envguard/repro.py` builds a temp ROOT that mirrors the real one (the three
`PINS` sources symlinked, `env-precond.py` copied so `parents[1]` resolves there) and drives the real
CLI with `runs/graphcmp/D` absent. Same code, same line, real tree untouched.

## 2. What it reads under `runs/graphcmp/D`, and where absence first bites

Pre-fix, six open sites; the first one to raise is marked ◀.

| file:line | function | path | preceding check |
|---|---|---|---|
| `:134` | `dev_route()` | `D0-coverage-census.txt` | **no** |
| `:136`/`:149` ◀ | `dev_route()` / `observed()` | `D2-canon-py-late.txt` | **no** |
| `:151` | `observed()` | `D0-coverage-census.txt` | **no** |
| `:159 → :188` | `observed() → declared_values()` | `D0-run-summary.txt` | `SUMMARY.exists()` |
| `:235` | `check()` (METHOD B) | `D0-run-summary.txt` | `summary.exists()` at `:230` |

**Denominator: 6 reads, 2 with a preceding existence check, 4 without.** Separately, `check()`'s
METHOD A reads the three `PINS` sources at `:212` with no check (they live under `checks/` and
`.agents/slop/`, not `runs/`) — a missing pin source was the same `FileNotFoundError` shape.

## 3. The contract as it stood

`grep -n 'REFUSED\|exit(3)\|sys.exit'` → only the final `sys.exit(main())` at `:364`. **No `REFUSED`
path anywhere.** Exits were `0` (pass), `1` (a pin moved **or** a crash), `2` (argparse/unknown plant):
a gate whose absent-input half said exit 1 and whose crash half also said exit 1.

## 4. The guard landed

The project's refusal vocabulary is `checks/abi_gate.py`'s rule (used by ~15 `checks/*.py`); `gatekit.py:59`
spells the same five verdicts as exits. Matched exactly:

```python
REFUSED = 3
def refuse(*why: str) -> int:                      # prints "== REFUSED, NOT A VERDICT: …"
def require(*paths: pathlib.Path) -> int:          # 0 if all exist, else refuse naming each absent
```

- `record()` calls `require(CENSUS, LATE)` **before** its first read (`:289`) — closes the crash at `:149`.
- `check()` refuses a missing run: `return refuse("no run summary: …")` (`:267`) — was `return 1`.
- `check()` requires the `PINS` sources before METHOD A reads them (`:245`).
- `dev_route()`/`observed()` now use the named `CENSUS`/`LATE` constants (no re-typed literals).

No sixth verdict; absence is not a PASS and not a FAIL. Guard is at the **call site** (`record` is the
sole caller of `observed`/`dev_route`), so the four reads share one check rather than four copies.

## 5. Planted — two states, distinguishable in token and exit

Added `--plant` cases `absent-record` and `absent-summary`, both **MUST be exactly 3** (a refusal is
not a moved value). Captured live:

| state | `runs/graphcmp/D` | `--check` | `--record` | traceback |
|---|---|---|---|---|
| ABSENT | missing | **rc 3**, `== REFUSED, NOT A VERDICT: no run summary…` | **rc 3**, `== REFUSED, NOT A VERDICT: input absent: …/D0-coverage-census.txt; …/D2-canon-py-late.txt` | **no** |
| PRESENT | symlinked | rc 0 | rc 0 | no |

`.agents/slop/envguard/two-states.out` is the capture. `--plant satisfied` → `all five plants … OK`,
rc 0; `--plant moved` → rc 0; `--check`/`--record`/`--declare` on the live tree → rc 0.

## 6. The rest of the tree — same shape

`.agents/slop/envguard/scan.py` (AST, population by `glob("checks/*.py")` + `glob("gates/*.py")`,
paths resolved through module-level `NAME = <expr> / "lit"` folds; a read through a helper-returned
`Name` is a NAMED miss, so counts are a lower bound).

**FILES 89 · READS 19 · raw UNGUARDED 11.** Classified by reading each site:

| reads | verdict |
|---|---|
| 4 | `env-precond.py` `dev_route`/`observed` — guarded at their sole call site `record():289` (scanner sees read-site guards only; over-report) |
| 3 | `gates/{bc-u32,i64-shl,wk-f32}` lanes — read **inside `if ok:` / after PASS**, so `gatekit` promoted them (guarded by construction) |
| 2 | `checks/differ.py:326 text()` and `:383 one_line()` — raw read helpers with **no guard at the read site**; callers guard (`unhealthy()` checks the summary first). `differ.py` is off-limits here. |
| 2 | `checks/differ.py:458/502` — `write`-then-`read` of the same path in `cmd_run` (guarded by construction) |

So the **genuine** no-guard-anywhere instances are `differ.py`'s two read helpers, call-site dependent.
`env-precond.py` was the single instance where a `runs/` path was opened with no guard anywhere on the
path to it — and that is now closed.

**Scanner misses (named, not hidden):** helper-returned paths (`bd = lane_file("bd")`, then
`bd.read_text()` in `i64-shr-gate`; `rows_of` for `py`/`bn`), method-form `.open("r")`, and dynamic
`f"{...}"` components. `gates/*.py` reads under `artifacts/` are visible only through `GATE.dir`, which
is why `.dir` is a token.

## Files

- `checks/env-precond.py` — guard + two absent plants (the deliverable).
- `.agents/slop/envguard/repro.py` — the two-state reproduction (temp mirror, live tree read-only).
- `.agents/slop/envguard/scan.py` — the class census.
- `.agents/slop/envguard/two-states.out` — captured both states.

Not done: `.agents/TODO.md` left untouched to avoid a concurrent-edit conflict (another unit is live);
`runs/graphcmp/D/`, `gates/`, `checks/differ.py`, `AGENTS.md` untouched; nothing staged or committed.
