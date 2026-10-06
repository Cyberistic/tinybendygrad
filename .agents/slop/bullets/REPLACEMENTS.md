# REPLACEMENTS — `AGENTS.md` bullets that carry NEITHER a measurement nor a named instrument

**Paste-ready. One OLD / NEW pair per MEASURED bullet.** The orchestrator applies these; do not re-derive.

Instrument rule used to select this set (see `REPORT.md`): a bullet is *measured* if its text contains
`measured` (case-insensitive); it is *instrumented* if its text matches `(checks|gates)/*.py` or a
`file:line`. The 24 bullets carrying neither were classified; the 11 that I could supply a measurement
for are below. The other 13 are DELETABLE (12) / UNVERIFIABLE (1) — see `REPORT.md`, and are intentionally
NOT patched here.

Measurement date: **2026-10-06**, from `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.
Every count below was produced by the named command in a single run. Where a number MOVES under
concurrent units, it says so.

---

## 1. L21 — tick-off / progress-bar directive

**OLD**
```
- Whenever you finish a task, make sure to tick it off in .agents/TODO.md, If the task is not in TODO.md, add it there and check it off. Keep a progress bar inside TODO.md for each category of tasks. If it's an implementation detail or a small task, do not add it to TODO.md. Only add tasks that are meaningful and require tracking.
```
**NEW**
```
- Whenever you finish a task, tick it off in .agents/TODO.md; add it there and check it off if missing. Keep a progress bar per category. Skip implementation details and small tasks. **MEASURED: `.agents/TODO.md` exists; `wc -l` = 13477. Progress bars present: `rg -c '[█▓▒░]' .agents/TODO.md` = 12 lines, plus ASCII bars.**
```

## 2. L22 — TODO comments, `rg`-searchable

**OLD**
```
- Add TODO comments in the code for any tasks that are not yet completed, so we can use `rg` to search for TODO comments later on.
```
**NEW**
```
- Add TODO comments in code for unfinished tasks, so `rg` finds them. **MEASURED: `rg -l 'TODO' --glob '*.bend' . | wc -l` = 94 files.**
```

## 3. L23 — `.agents/TOOLS.md` ledger

**OLD**
```
- Update .agents/TOOLS.md with the tools or libraries you're using, it will act as a ledger and overview for the project.
```
**NEW**
```
- Update .agents/TOOLS.md with tools/libraries used; it is the project ledger. **MEASURED: `.agents/TOOLS.md` exists; `wc -l` = 1543. 99 of the 213 paths it names are gone (the audit in `.agents/slop/agend/REPORT.md`).**
```

## 4. L50 — `LAWS.bend` path

**OLD**
```
- use `LAWS.bend` to keep important rules — **the path is `tinybendygrad/LAWS.bend`; there is no
  `LAWS.bend` at the repo root, so the bare name resolves to nothing.** `--check-only` reports
  `Error: 34 TODOs found. The code is incomplete, and not a valid proof yet.`
```
**NEW**
```
- use `LAWS.bend` to keep important rules — **the path is `tinybendygrad/LAWS.bend` (MEASURED: exists,
  `wc -l` = 412; there is no `LAWS.bend` at the repo root, so the bare name resolves to nothing).**
  `--check-only` reports `Error: 34 TODOs found. The code is incomplete, and not a valid proof yet.`
```

## 5. L114 — `substrate-check.sh` bare name

**OLD**
```
- `substrate-check.sh` — import-graph and cold-file sweep over the `.bend` tree.
```
**NEW**
```
- `checks/substrate-check.sh` (46-line shim → `.venv/bin/python checks/substrate.py`, 765 lines) —
  import-graph and cold-file sweep over the `.bend` tree. **MEASURED: the bare name
  `substrate-check.sh` resolves to nothing (`command -v` absent; no root-level file).**
```

## 6. L187 — `uv` and `ty`

**OLD**
```
- use uv and ty
```
**NEW**
```
- use uv and ty. **MEASURED: `command -v uv` = `~/.local/bin/uv`; `command -v ty` = `~/.local/bin/ty`.**
```

## 7. L193 — pytest `-n12` command

**OLD**
```
- Run tests with `-n12` for speed (e.g. `python -m pytest test/null/test_dtype.py -x -q -n12`)
```
**NEW**
```
- Run `test/` with `-n12` for speed, e.g. `.venv/bin/python -m pytest test/null/test_dtype.py -x -q -n12`. **MEASURED: that command rc=1, `No module named pytest` — `pytest` is not in `.venv` today.**
```

## 8. L194 — mypy command

**OLD**
```
- Run `python -m mypy tinygrad/` to typecheck
```
**NEW**
```
- Run `.venv/bin/python -m mypy tinygrad/` to typecheck. **MEASURED: rc=1, `No module named mypy` — not installed in `.venv` today.**
```

## 9. L195 — ruff command

**OLD**
```
- Run `python -m ruff check .` to lint
```
**NEW**
```
- Run `ruff check .` to lint (`ruff` 0.15.18 is on PATH; it is NOT in `.venv`). **MEASURED: `ruff check .` reports 18752–18754 errors, rc=1, and the count MOVES between runs under concurrent units — quote it with a timestamp. The `797` claimed a few lines below is stale.**
```

## 10. L202 — viz README

**OLD**
```
- Read `./tinygrad/viz/README.md` for profiling and debugging rewrite rules
```
**NEW**
```
- Read `./tinygrad/viz/README.md` for profiling and debugging rewrite rules. **MEASURED: exists; `wc -l` = 93.**
```

## 11. L203 — no amend / no rebase

**OLD**
```
- **Do not do amend commits, and do not REBASE. Always do a new commit if a force push to origin would
  be required.** The previous revision said only "no amend". **`ad117c928` IS **OURS**, NOT UPSTREAM, AND AN
  EARLIER REVISION OF THIS LINE GOT IT BACKWARDS**: `git log -1` READS `author: tinybendygrad
  <tinybendygrad@localhost>`, `Fri Oct 2 19:35:06 2026`, **16 FILES ALL UNDER `tinygrad/`**, AND
  `git merge-base --is-ancestor ad117c928 HEAD` = **YES**. **SO THE RE-VENDOR THAT BROKE A PIN THE TREE CITES
  WAS DONE BY THIS PROJECT, NOT BY UPSTREAM — WHICH IS WHY THE RULE IS ABOUT OUR OWN HISTORY AND WHY THE
  EXCUSE THIS LINE USED TO CARRY COULD NOT HAVE EXCUSED IT.**
  Its message is *"rebase B1: 17 files, the tree imports again, and the GUARD that was supposed to catch this
  is DEAD"* and it names the tool it came from (`rebase-plan.py --json`, `rebase-try.sh`), **AND BOTH ARE NOW
  DELETED, SO THE PLAN THAT RE-VENDORED `tinygrad/` HAS NO SCRIPT LEFT TO AUDIT IT.** **THE PIN SURVIVES:
  `git show 'ad117c928^:tinygrad/uop/ops.py'` STILL ANSWERS EVERY CITATION, `:1398` `dtype: DType =
  dtypes.void` AND `:1404` THE CONDITIONAL `__repr__` — **SO `ad117c928^` IS THE PIN, NOT `ad117c928`.**
```
**NEW**
```
- **Do not amend commits and do not REBASE; make a new commit if a force push would be required.**
  **MEASURED: `git log -1 ad117c928` — author `tinybendygrad <tinybendygrad@localhost>`, `Fri Oct 2
  19:35:06 2026 +0300`, 16 files all under `tinygrad/`; `git merge-base --is-ancestor ad117c928 HEAD`
  = rc 0 (YES). SO `ad117c928` IS OURS, NOT UPSTREAM.** Its message is *"rebase B1: 17 files, the tree
  imports again, and the GUARD that was supposed to catch this is DEAD"*; it names `rebase-plan.py
  --json` and `rebase-try.sh`, **both now deleted.** **THE PIN IS `ad117c928^`: `git show
  'ad117c928^:tinygrad/uop/ops.py'` line 1398 reads `dtype: DType = dtypes.void` and line 1404 the
  conditional `__repr__` (both verified today).**
```
