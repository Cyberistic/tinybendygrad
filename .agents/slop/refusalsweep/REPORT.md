# `gates/` had the same absent-output-dir crash `envguard` found in `checks/` — found, reproduced, fixed, planted

Scope: `gates/*.py` (my ownership). `checks/differ.py`, `checks/env-precond.py`, `AGENTS.md`,
`tinybendygrad/` untouched. No commit, no `git add`, no `bend` run. `gates/artifacts/` left at its
14 dirs (verified; experiments use a temp `ART`).

## 1. Population, by discovery — and the names

`.agents/slop/refusalsweep/scan.py` (AST). Files by `glob("checks/*.py") + glob("gates/*.py")`;
the ignored roots are **parsed out of `.gitignore` itself** (50 prefixes, printed in the header of
`scan.rows`), not a hand list. A site is a read (`read_text`/`read_bytes`/`open`/`iterdir`/`glob`),
a write (`write_text`/`write_bytes`/`open w`/`replace`/`unlink`), or `mkdir`. Paths resolved
through module-level `NAME = <expr>` folds; an unresolvable component stays `{NAME}` (honest miss).

```
FILES 89   SITES 54 (paths under an ignored root)   SCANNER-GUARDED 20   RAW UNGUARDED 34
```

**The raw-unguarded names, `file:line`, classified.** `gates/` is my scope; `checks/` is named for
the population but not mine to edit.

| site | kind | root | verdict |
|---|---|---|---|
| `gates/gatekit.py:308` | write | `gates/artifacts/<gate>` | **genuine — the reported crash. NOW FIXED** (`_ensure_dir` before it) |
| `gates/gatekit.py:522` | read | `gates/artifacts/<gate>` | OUTPUT, guarded-by-construction (`run()` ensures; `glob`→`[]` if gone) |
| `gates/gatekit.py:524` | write | `gates/artifacts/<gate>` | OUTPUT, guarded-by-construction |
| `gates/bc-u32-gate.py:79` | read | `gates/artifacts/<gate>` | OUTPUT read-back, **after** `GATE.run()` (`:72`), dir made at construction |
| `gates/i64-shl-gate.py:69` | read | `gates/artifacts/<gate>` | OUTPUT, helper reached after PASS |
| `gates/i64-shr-gate.py:76` (×2) | read | `gates/artifacts/<gate>` | OUTPUT, after PASS |
| `gates/wk-f32-gate.py:59` | read | `gates/artifacts/<gate>` | OUTPUT, `checks` runs only after PASS |
| `checks/differ.py:305,305,307,309,318,321,326,332,362,383,388,473,502,502,531,741,820,943` | read+write | `runs/graphcmp/D` | differ owns its dir (`:387`,`:972` `mkdir`); the 2 genuine no-guard read helpers are `:326`,`:383` (envguard; call-site dependent). **OFF-LIMITS** |
| `checks/env-precond.py:164,166,179,181` | read | `runs/graphcmp/D` | fixed by envguard: guarded at sole caller `record():289` via `require()` |
| `checks/devpin.py:79,87` | read | `runs/graphcmp/D` | safe: `D.glob(...)` on an absent dir returns `[]`, no crash |
| `checks/abi_gate.py:368` | write | temp `work/` | guarded at call site (`main():609` `work.mkdir()`) |
| `checks/gate.py:207` | read | temp `work/` | produced by the `node` run two lines above (read-back) |

**K (genuine no-guard-that-can-crash): 1 in `gates/` (`gatekit.py:308`, fixed) + 2 in
`checks/differ.py` (off-limits).** Everything else is guarded by construction, by a glob, by a
call-site `mkdir`/`require`, or by a write-then-read.

## 2. Reproduced — one instance, both ways

`.agents/slop/refusalsweep/repro.py` drives the **real** `gatekit.py` source and the **real**
`wk-cd-oracle.py`, with `ART` on a temp dir. No `bend`. Captured in `repro.out`:

```
A dir ABSENT at construction:      crashed=False  _oracle() -> True
B dir removed mid-run, NO ensure:   crashed=True  FileNotFoundError at gatekit.py:308 (in _oracle):
                                                   '…/artifacts/repro/.tmp.py.rows'
C dir removed mid-run, WITH ensure: crashed=False  _oracle() -> True  ensure_rc=0
D out dir UNCREATABLE:              constructor_ok=True  _ensure_dir rc=3 (REFUSED=3)
BOTH-WAYS: OK -- B crashes where C does not; D refuses; A creates
```

**The reported traceback, exactly:** `FileNotFoundError: [Errno 2] No such file or directory:
'…/gates/artifacts/<gate>/.tmp.py.rows'`, raised in `gatekit._oracle` at the staged `py.rows`
write (`gates/gatekit.py:308` today; it was `:266` before this fix added lines above `Gate`). B is
that line. A exists because `Gate.__init__` already `mkdir`s — so the report's crash requires the
directory to vanish **between construction and `run()`**, which `AGENTS.md` documents as a live
command: *"one `rm -rf gates/artifacts` deletes anything kept there."* C is the fix.

**Why A/B/C**: the constructor guard alone was already present (since `4e6c3c437`, 2026-10-04), so
"output dir absent at process start" does not crash — but `run()` re-entering with the directory
gone does. A repro that only showed A would have proven nothing; B is what crashes and C is what
stops it.

## 3. `gatekit`'s vocabulary, and whether it already solved this

`gates/gatekit.py:59-60`:
```python
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {0:"PASS",1:"FAIL",3:"REFUSED",4:"SKIP",5:"DEAD"}
```
**It CREATED the artifacts dir inline** — `self.dir.mkdir(parents=True, exist_ok=True)` at
construction — but had **no named `ensure_dir`/`refuse`**, and `run()` did not re-ensure. It did
**not** solve the mid-run case: `run()`'s first line `_clear()` (and later `_oracle`/`_settle`)
assumed the directory still existed. So the fix is to **hoist the existing inline mkdir into one
named `_ensure_dir()` and call it at both ends** — no second mechanism invented.

## 4. The fix landed

`gates/gatekit.py` only:
- `_ensure_dir()` — `mkdir -p`; on `OSError` prints envguard's exact wording
  `== REFUSED, NOT A VERDICT: output directory absent and uncreatable: <dir>` and returns
  `REFUSED (3)`. An OUTPUT dir you can make is **not** a precondition; only an uncreatable one refuses.
- Called at **construction** (`self.dir_rc = self._ensure_dir()`, replacing the inline mkdir) and at
  the **top of `run()`** (`if (rc := self._ensure_dir()) != PASS: return rc`).
- `_clear()` now tolerates a missing/non-directory path (`if not self.dir.is_dir(): return`),
  because a file where the directory must go made the constructor raise `NotADirectoryError`
  (state D) before `run()` could refuse.
- `output_dir_plant()` — the reusable plant (below).

No sixth verdict. `REFUSED == 3`. Inputs still refuse via `_warm`/`_oracle` returning `REFUSED`.

## 5. Plant — two gates, three states, in TOKEN and EXIT

Wired `--plant` into **two** gates: `gates/wk-cd-gate.py` (the reported one) and
`gates/wk-f32-gate.py`. Both delegate to the one shared `gatekit.output_dir_plant()`.
Captured in `plant.out` (identical on both, `rc=0`):

| state | command | token | exit |
|---|---|---|---|
| dir absent | `--plant` | `OUTPUT-CREATED` | 0 |
| dir present | `--plant` | `OUTPUT-PRESENT  rc=0` | 0 |
| dir blocked by a file | `--plant` | `REFUSED, NOT A VERDICT` | 3 |

**Gates NOT touched, and why:**
- every other `gatekit` gate (`bc-u32`, `i64-shl`, `i64-shr`, `ops-core`, `render_val_s`,
  `replace`, `uop_cast`, `ew-consts`, `ew-explog`, `wk-eval`, `mixin-op`, `beautiful-mnist`) —
  they inherit the fix through `gatekit`; adding a per-gate plant would copy one contract N times.
- the `*-oracle.py` / `*-rows.py` files and `gates/wk-f32-rows.py` — not `gatekit`, and they write
  beside themselves (tracked), not under an ignored dir.
- `gates/retention-check.py`, `gates/gates-pop.py`, `gates/gendirs.py` — instruments that READ
  `gates/artifacts/`; `retention-check` already reports `UNMEASURABLE gates/artifacts/: 0/14` when
  absent (verified, no crash), and the other two scan sources.
- `checks/differ.py`, `checks/env-precond.py` — not mine (off-limits / already fixed).

## 6. Is `gates/artifacts/` being `.gitignore`d itself the defect? — **No; the split is the finding**

Every one of the **8** `gates/` sites under `gates/artifacts/` is an **OUTPUT** (`gatekit` writes
the lane files; gates read them back). `AGENTS.md`: *"an OUTPUT there is correct and an INPUT there
is a bug."* So gitignoring it is **correct**, and an INPUT there does not exist.

The INPUT-under-a-gitignored-dir bug **does** exist — just not under `gates/artifacts/`. **5 gates
take their driver/oracle from `.agents/slop/`** (gitignored AND being pruned):
`bc-u32-gate.py:59-60`, `beautiful-mnist-gate.py:74`, `i64-shl-gate.py:60-61`,
`i64-shr-gate.py:56-57`, `mixin-op-gate.py:83`. Those are **inputs that belong beside the gate in
GIT**. Their *absence* is already handled — `_resolve`/`_warm`/`_oracle` yield `REFUSED (3)`, not a
traceback — so this is not the crash; it is a shelf-life defect, reported and **not** fixed here
(relocating another unit's oracle/driver files is out of scope).

## 7. Files

- `gates/gatekit.py` — `_ensure_dir` (construction + `run()`), tolerant `_clear`, `output_dir_plant`.
- `gates/wk-cd-gate.py`, `gates/wk-f32-gate.py` — `--plant` entry points.
- `.agents/slop/refusalsweep/scan.py` — the population census. `scan.rows` — its output.
- `.agents/slop/refusalsweep/repro.py` — the both-ways reproduction. `repro.out` — capture.
- `.agents/slop/refusalsweep/plant.out` — the two gates' plant transcript.

Note: running `gates/gates-pop.py` (to prove my `gatekit` edit did not break it) regenerated the
**tracked** `gates/gates-pop.ledger.tsv`; since that ledger belongs to the unit adding
`gates/uop_cast-gate.py`, it was **restored to `HEAD`** so my change-set stays minimal.
`gates-pop` reports `OK, 96 entry points`; `gendirs` `0 directories in index AND ignored`;
`retention-check` `RED` on its pre-existing `runs/graphcmp/D` clauses (not this change).
