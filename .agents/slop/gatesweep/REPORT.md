# `checks/gatesweep.py` — replacing the `/tmp/sweep.sh` foreign sweep

Working notes for the unit that wrote `checks/gatesweep.py`. Every number carries the scope and a
timestamp. HEAD at start: `c51c5ffd2a6a`.

## 1. Does a compliant instrument already exist? (checked first, as instructed)

Four files enumerate or run gates. None is the instrument the brief asks for:

| file | what it does | why it is not this |
|---|---|---|
| `gates/gates-pop.py` (1529 lines) | enumerates the gate population by AST `__main__` + shell self-dispatch; never runs one | its own docstring: *"whether a gate is ever RUN. Nothing here executes one -- deliberately"* |
| `gates/gate-surface.py` | reads each gate's declared `VERDICTS`, EXECUTES its `--plant`, requires the observed rc to equal the declared one | it runs **plants**, not gates; population is `gates-pop.discover()` |
| `.agents/slop/hooks/run.py` | runs a 13-gate subset (those declaring `VERDICTS`), timeout only, writes `run.tsv` | **no memory ceiling**; covers 13 of 70; lives in a **prunable** directory (`.agents/slop/`) |
| `checks/bounded.py` | the watchdog: time bound + RSS ceiling + a verdict TOKEN | it is the **component**, not the sweep; no gate knowledge |

`run.py` is the closest, and it is a good instrument — but it caps TIME only (`CAP=60s`), filters to
the 13 gates that declare a surface, and its home (`.agents/slop/`) is explicitly swept. So the
brief's population (`gates/*-gate.py`, 70) had **no** compliant runner. Built one.

## 2. What was built

`checks/gatesweep.py` (218 lines incl. docstring). Population by **directory walk**
(`os.walk`, `lstat`-regular, `__pycache__` skipped, symlinks rejected), non-hard-coded. Per gate it
runs **through `checks/bounded.py`** (`--seconds`, `--mb`), captures both streams, parses the
watchdog's `[bounded] <TOKEN>  rc=<rc>` record, and classifies into gatekit's five. Emits
`gates/artifacts/gates-sweep.rows` (`gate, verdict, token, rc, seconds`).

- **Population (measured 2026-10-15 ~12:05):** directory walk `gates/*-gate.py` → **70**.
- **Control, printed every run (same time):** `gates-pop.discover()` → **188 entries + 60 modules**.
  The two disagree **on purpose**: `discover()` answers "every entry point in both gate homes", the
  walk answers the brief's question. The control makes the gap a number a reader sees, not a claim.
- **The vocabulary is loaded by path** from `gates/gatekit.py` (`VERDICT = {0:PASS,1:FAIL,3:REFUSED,4:SKIP,5:DEAD}`)
  and the tokens from `checks/bounded.py`. Neither list is re-typed here.

The four `classify()` branches answer the foreign sweep's four faults. The one that matters most:
**a gate that exits 0 having printed nothing is `DEAD`** — the state the foreign sweep's `>/dev/null`
made invisible.

## 3. Proof against real data (no gate run)

Two proof inputs, both **already-captured** by a prior run, so nothing was executed:

- `.agents/slop/hooks/cost.out` — real per-gate `rc` (or `OVER-CAP`), seconds, path, first line.
- `.agents/slop/hooks/run.tsv` — real per-gate **recorded verdict**.

`--prove` reconstructs `(bounded token, rc, first line)` from `cost.out` and requires `classify()`
to reproduce `run.tsv`'s verdict. **Result, 2026-10-15 ~12:12: `14/14` reproduced** — REFUSED×7,
PASS×3, FAIL×2, SKIP×1, DEAD×1 — including `oracle_f64.py` rc=1 + a traceback → **DEAD**, and
`residue.py` OVER-CAP → `TIMED-OUT` → **SKIP**. Run it: `.venv/bin/python checks/gatesweep.py --prove`.

The record parser was separately proven on **7 real `[bounded]` lines** in `.agents/slop/twopass/*.err`
(peaks 416–832 MB), no run.

**The brief names `gates/artifacts/*/` as the proof artifact; used, and it is the honest caveat.**
Measured 2026-10-15 ~12:12: **64** gate dirs, **63** hold promoted lanes, **1** empty (`cstyle-mut`,
a mutator dir). Those files are **`py.rows`/`bd.out`/`bn.out`/`*.cmp`/`gate.bin` — LANE files, never a
gate's stdout**, so the directory is *not* an input a token parser can read. It IS a real captured
outcome: `gatekit.Gate` promotes its lanes on PASS and leaves the dir empty otherwise
(`_clear` at construction, `_settle(False)` unlinks), so populated ⇒ the gate reached the diff. Also
found: `uop_cast-gate/` holds `.tmp.py.rows`/`.tmp.bd.out`/`.tmp.gate.bin` — a run **killed between
staging and promotion**, exactly the residue of the kill path `classify()` handles. `--prove` prints
this census.

## 4. Cost (measured; the machine is BUSY, so the numbers move)

**Cannot be measured honestly on this host: the brief bans running a gate, and `bounded.py` samples
RSS — "any RSS sampling" is banned — so `run_one()` is UNEXERCISED.** What I have is the foreign
sweep's own footprint:

- **Per-gate wall time**, from the artifact dirs the running sweep left, measured 2026-10-15 12:13:
  **60** dirs fresh in the window `11:53:55 → 12:11:57` (span **1081 s**, **59** gaps), **mean 18.3 s**,
  min 0 s, max **435 s** (before `ops-core-gate`). Extrapolated to the full **70**-gate population at
  the mean: **≈21 min**, with a heavy tail (that 435 s gap is one gate).
- **The sweep is still running** — fresh dirs went from 26 (my first read, ~12:03) to 60 (~12:13) while
  I worked, so re-read the window before quoting it.
- **Per-gate peak memory**: not measurable here. Real captured `[bounded]` records bound it from real
  data at **416–832 MB** for a single `bend --check-only`; `AGENTS.md`'s census puts the population's
  median at **207 MB** and its largest drivers at **745–1,152 MB** (`nir`/`sz`/`ops_python`/`nn-onnx`/
  `uop-symbolic`). So per gate ≈ **0.4–1.2 GB**, and `--mb 2048` (default) sits above the observed max.
  One-at-a-time keeps the machine sum at the per-gate peak.

## 5. What I refused, and why

- **I did not run it end to end.** `bounded.py` polls RSS, and RSS sampling is banned this session. So
  every statement above is from static reads and already-captured data. **`gatesweep.py` is DEAD (5)
  until the orchestrator runs it once** — a tool that has never been run is DEAD, not green, and I will
  not imply otherwise. The two non-running modes (`--plan`, `--prove`) were exercised.
- **I did not scrape prose for a verdict word.** The token is `gatekit.VERDICT`'s word for the exit
  code. A word matched out of free text is a *shape*, and shape-matching a population is the fault this
  repo has paid for repeatedly (`gates-pop.py`'s own lesson). This is stated in the file.
- **I did not touch `gates/` sources or run any `*-gate.py`.**
- **No commit, no `git add`, no `jj`.**

## 6. A finding worth keeping: the five are spelled TWO ways

`gatekit.py:60` says `PASS=0`, but `run.py:56` and `gate-surface.py`'s per-gate `VERDICTS` say
**`GREEN`** for code 0. Same code, two words in two instruments. `--prove` normalises `GREEN→PASS` when
reading `run.tsv`; the sweep itself always uses `gatekit`'s spelling, because that file *is* the owner
of the vocabulary. Anyone reconciling the two instruments should settle on one spelling first.

## 7. Self-note: I shipped my own DEAD-by-silence for one edit

The first draft of `checks/gatesweep.py` had **no `if __name__ == "__main__"` guard** — it imported
cleanly, ran `main()` never, and exited **0 having printed nothing**. That is *exactly* the `DEAD`
state the file exists to catch, reproduced in the file itself, and it was invisible to `$?`. Fixed in
the same session; noted because the trap is easy and the file's own subject.
