# `stalefix` — the stale-artifact bug in `gates/gatekit.py`, and what it cost to find

**CLAIM (RECOVERED.md §2):** *a FAILED gate run left the previous run's `bd.txt` in place, so a
diff after a RED run diffed the last GREEN run.* **STATUS: fixed, measured both ways, not committed.**

Everything here is reproducible with three commands, and each one prints its own verdict:

```
.venv/bin/python .agents/slop/stalefix/stale-repro.py      # BEFORE.rows vs AFTER.rows
.venv/bin/python .agents/slop/stalefix/gate-matrix.py      # MATRIX.rows -- 9 gates, both sides
.venv/bin/python .agents/slop/stalefix/plant-disarm.py     # PLANT.rows
```

## the files

| file | what it is |
|---|---|
| `stale-repro.py` | the repro. S0 green, S1 a deterministic type error in `_warm`, S2 a row-count failure **after** every lane wrote. Runs against `gates/gatekit.py` AND `gatekit-old.py`. |
| `gatekit-old.py` | `gates/gatekit.py` as it stood, frozen, `sha256 cba801e65d4b3a4601a091c8fa6f5da9f99d9054b317653a2c78d3fdb3a786f3` |
| `gate-matrix.py` | every gate, OLD in a shadow tree and NEW on the live tree, each wrapped in `checks/bounded.py` |
| `plant-disarm.py` | plants marker bytes into a real gate's directory and a red run's, then checks they are gone |
| `green.bend` `broken.bend` `oracle.py` `oracle-short.py` | the fixture: 3 rows, 177 MB, ~1 s per compile |
| `*.rows` | the captured output of each harness |

## what the repro measured

| | S0 green | S1 type error | S2 short row |
|---|---|---|---|
| **OLD** | rc=0, 7 artifacts | rc=1, **7 of 7 STALE**, `no --check-only output in 25 tries (the stack flake)`, **1.98 s** | rc=1, **6 of 7 STALE**, `py.txt` fresh |
| **NEW** | rc=0, 7 artifacts | rc=1, **NOTHING**, `bend said: SOME PROOFS FAIL \| Error: \| - expected : a defined name (rc=1)`, **0.07 s** | rc=1, **NOTHING** |

`STALE` is measured by sha256 against the previous green run's bytes, not by counting files — a
leftover count cannot tell "its own bytes" from "the last good run's bytes", and that distinction
is the whole claim.

## the fix, in three sentences

Every write goes to `.tmp.<name>` (`checks/differ.py:158`'s own convention, same directory, so
promotion is an `os.replace` atomic rename). `_clear()` empties the directory **first**, because
promotion alone cannot help: a run that fails before its first write would leave the previous run's
promoted files untouched, which is the bug. `_settle(ok)` promotes or unlinks in **one `finally`**,
which all sixteen `return 1`s and an exception reach.

## three things that were not as the report said

1. **The stderr discriminator was NOT in the tree.** `RECOVERED.md` §2 records it as survived; it
   was not. `_warm` guarded on `not stdout and rc != 0`, which is the stack flake's shape *and* a
   type error's shape. The new `_said()` strips `bend`'s `… is available: run bend update` notice
   first, because that goes to **stderr on every invocation including a green one** (42 bytes,
   measured) — so "stderr is non-empty" is not "bend said something".
2. **`retention-check.py` probes no `gatekit.declared()`** — it transcribes the set. So no new API
   was added, and `Gate.run`, `Gate.dir`, `Gate.warm_out`, `oracle_drift`, `main` are all unchanged.
3. **`retention-check.py` reads `Gate.run`'s AST**, so `run()` had to keep its `self.dir` references
   and its exits inside it. Extracting a `_check()` helper would have made the clause II denominator
   **0** — a green with no denominator.

## three things left, named

- `gates/mixin-op-gate.py:91` and `gates/beautiful-mnist-gate.py:87` `sys.exit(2)` **before**
  `GATE.run()`, so `_clear()` never runs and the previous run's 7 artifacts survive a red run.
  Measured on the live tree: `mixin-op-gate` left 7 files at rc=2.
- `gates/retention-check.py:133` counts dotfiles as residue (`checks/differ.py:400-402` prunes
  them), and a SIGKILL cannot run a `finally` — measured, `beautiful-mnist-gate/` held
  `.tmp.bd.txt` + `.tmp.py.txt` after `bounded.py` killed it at 2,048 MB. The next run swept both,
  and `retention-check` then read `10/10 dirs clean, 0 with residue`.
- `gates/artifacts/*/{bd,bn,py}.txt` are `.txt`, and `checks/no-txt.py` exits 1. Renaming is a
  contract change across 9 gates and `retention-check.py:57`. Not done.
