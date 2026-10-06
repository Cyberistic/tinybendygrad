# `checks/*.sh` — a population the governing document does not count

Measured 2026-10-06 by this unit. Machine: macOS, `.venv/bin/python` is 3.12.10.
Companion: `SHELLS.tsv` (one row per script) and `runs/` (captured stdout/stderr/rc).

`AGENTS.md` says *"`gates/*.py` — per-def gates, and they are Python, never shell
(measured: 21 `.py`, 0 `.sh`)"*. That claim is about `gates/`. **The `checks/*.sh`
population is real, unenumerated, and the file that governs everything names three of
seventeen.** This report enumerates it and classifies each member.

## 1. The denominator, BY DISCOVERY

```python
for dp, _d, fs in os.walk("checks"):
    for f in fs:
        if f.endswith(".sh"): found.append(...)
```

**DENOMINATOR = 17.** No file is named by hand. They are:

```
bounded-selftest.sh  classify.sh  demo.sh  disarm.sh  e2e.sh  gate.sh  gen.sh
lint_demo.sh  lintable-gate.sh  plant.sh  run-all.sh  run-f64.sh
run-port-mm.sh  sb-gate.sh  substrate-check.sh  walk-mutate.sh  wt-sync.sh
```

## 2. Each one: what it drives, whether it exists, rc and token

The DRIVER list is the one admitted hand-list in this instrument (a script's referenced
paths cannot be discovered without parsing shell); existence is `os.path.exists`, so a
stale name shows as `[GONE]` and never as an assumption. `[GONE]` is 15 references across
6 scripts.

| path | class | rc | token | AGENTS.md | hazards |
|---|---|---|---|---|---|
| `bounded-selftest.sh` | SHIM | 0 | `selftest PASS` (13/13) — **invokes bend** (selftest case 12) | no | none |
| `classify.sh` | DRIVER | 0 | (no stdout: empty sandbox arg) | no | none |
| `demo.sh` | DRIVER | 0 | PROVENANCE split, no leftover | no | none |
| `disarm.sh` | DRIVER | READ-ONLY | compiles bend | no | none |
| `e2e.sh` | GATE | READ-ONLY | compiles bend | **path+base** | none |
| `gate.sh` | GATE | 2 | DEAD: `gen.py` absent, never reaches bend | no | `&&`-diff, trap-EXIT |
| `gen.sh` | DRIVER | READ-ONLY | compiles bend | no | none |
| `lint_demo.sh` | GATE | 1 | `DID NOT FLIP` | no | trap-EXIT |
| `lintable-gate.sh` | GATE | READ-ONLY | compiles bend | no | none |
| `plant.sh` | DRIVER | READ-ONLY | compiles bend | no | none |
| `run-all.sh` | DRIVER | READ-ONLY | compiles bend | no | none |
| `run-f64.sh` | GATE | READ-ONLY | compiles bend | **base** | `&&`-diff, `<( )` |
| `run-port-mm.sh` | GATE | READ-ONLY | compiles bend | **base** | trap-EXIT, `<( )` |
| `sb-gate.sh` | GATE | 3 ; 0 | `REFUSED` \| `SUBSTRATE` | **path+base** | none |
| `substrate-check.sh` | SHIM | READ-ONLY | compiles bend | **path+base** | none |
| `walk-mutate.sh` | DRIVER | READ-ONLY | compiles bend | no | none |
| `wt-sync.sh` | DRIVER | 0 | mirror tree written (gitignored `xd1/`) | no | none |

`sb-gate.sh` reads `3 ; 0` because it is run twice: plain → `REFUSED` rc 3, `--substrate`
→ rc 0. It is listed as "compiles bend" in spirit (its full lane is a bend compile) but its
two observable paths both stop before the compile, so they were run.

`READ-ONLY` = this unit was forbidden to run `bend` (another unit holds it). The script
invokes `./bin/bend`, directly or through `checks/bounded.py` / `checks/substrate.py` /
`portexec/run-kernel.sh`. **`gate.sh` is NOT read-only**: its driver `gen.py` is gone, so it
exits 2 before the bend line — measured, harness never reached.

## 3. Classes, counted by what each DOES

| class | rule | count | denominator |
|---|---|---|---|
| **GATE** | exits non-zero when a check FAILS (a verdict) | **7** | of 17 |
| **DRIVER** | runs something and prints; exit is not a verdict | **8** | of 17 |
| **SHIM** | `exec`s a `.py` | **2** | of 17 |
| **WRAPPER** | delegates to another shell | **0** | of 17 |

- GATE: `gate.sh` · `sb-gate.sh` · `lintable-gate.sh` · `e2e.sh` · `run-f64.sh` ·
  `run-port-mm.sh` · `lint_demo.sh`
- DRIVER: `demo.sh` · `disarm.sh` · `gen.sh` · `plant.sh` · `run-all.sh` ·
  `walk-mutate.sh` · `classify.sh` · `wt-sync.sh`
- SHIM: `substrate-check.sh` · `bounded-selftest.sh`
- WRAPPER: none.

**A `.sh` that exits 0 whatever happens is none of those — it is a script.** None of the
17 does that; `classify.sh` and `demo.sh` print and exit 0, but their exit is not read as a
verdict (no failure branch), which is why they are DRIVER and not GATE.

## 4. Which ones AGENTS.md names

Word-boundary matched against `AGENTS.md` so `sb-gate.sh` does not falsely "name" `gate.sh`.

- **Named by full path — 3 of 17** (this is the count AGENTS.md's own critic used):
  `checks/substrate-check.sh`, `checks/sb-gate.sh`, `checks/e2e.sh`.
- **Also named by bare basename — 2 more:** `run-f64.sh` (stage-7 prose) and
  `run-port-mm.sh` (the "read rc 1 then rc 0" change-detector note). So **5 are mentioned,
  12 are mentioned nowhere** — and AGENTS.md "calls none of them a population".

## 5. The four recorded shell hazards, per script

The four from `gates/README.md`: (1) `&&` consuming a diff's status under `set -e`;
(2) an `EXIT` trap whose status becomes `rm`'s; (3) `<( )` process substitution that POSIX
`sh` cannot parse; (4) `${=VAR}` zsh word-split that never expands under `sh`.

| script | (1) `&&`-diff | (2) trap-EXIT-rm | (3) `<( )` | (4) `${=}` |
|---|---|---|---|---|
| `gate.sh` | line 61, 81 | line 24 `trap 'rm -rf "$OUT"' EXIT` | – | – |
| `lint_demo.sh` | – | line 29 `trap 'rm -rf "$WORK"' EXIT` | – | – |
| `run-f64.sh` | line 208 | – | line 214 | – |
| `run-port-mm.sh` | – | line 58 `trap cleanup EXIT` (cleanup rm's) | line 131 | – |
| **all other 13** | – | – | – | – |

`${=}` is absent from the whole population. `<(` appears only in the two `#!/bin/zsh`
scripts, where it parses; it would break under `sh`. `gate.sh`'s `diff … && RC=$? || RC=$?`
(line 61) is the *correct* rc-capture idiom, not the masking bug — the shape is present, the
defect is not.

## 6. The worked example: `checks/sb-gate.sh`

### 6a. The input is absent, and the gate says so

`sh checks/sb-gate.sh` → `== REFUSED, NOT A VERDICT: the regression floor is absent:
.agents/slop/schedule-bodies/BEFORE-rows.txt` rc=3. `checks/sb-gate.sh:76`. No SKIP branch
exists (`grep -c SKIP` = 0). The prescription that put the input there — *"gate inputs live
under `.agents/slop/`"* — is the one that deleted it.

### 6b. Recovery — it CAN be recovered (a blob exists, and a tracked copy too)

- `git cat-file -p b35cf5f7048a39a26f066ab6d9c660fb84fa2402 | wc -c` → **1131** (non-empty).
- The tracked copy is `oracles/schedule-bodies/BEFORE-rows.rows`, working blob
  `b35cf5f7048a39a26f066ab6d9c660fb84fa2402`, sha256 `7a3aa4a4b9e2…`, **81 lines, all
  `name=value`** (0 non-row lines). It is byte-identical to the blob.
- The name moved while this unit worked: a concurrent `no-txt` sweep renamed
  `BEFORE-rows.txt` → `BEFORE-rows.rows` in `oracles/`. `.rows` is the correct extension
  for a row dump, so the fix uses it.

### 6c. Generator — nameable, but regeneration needs bend

The file is a row dump of the gate's own lane `bd`: `./bin/bend
tinybendygrad/schedule/__init__.bend` via `checks/bounded.py`. Regenerating it therefore
compiles `bend`, which this unit may not do. Recovery is the route taken.

### 6d. The fix — a git-tracked path, near the oracle role dir, not `.agents/slop/`

`checks/sb-gate.sh` (this unit owns `checks/*.sh`) now reads:

```sh
BASE=oracles/schedule-bodies/BEFORE-rows.rows   # was $D/BEFORE-rows.txt
```

`oracles/schedule-bodies/` is git-tracked and already holds this gate's published
`rows-bd.rows` / `sb-oracle.rows`, so the baseline has a git home. The fix does **not** go
to `gates/artifacts/` (gitignored, swept) and does **not** go back to `.agents/slop/`.

### 6e. The plant — two states, distinguishable, no bend

`plant_sbgate.py` (the two-state plant; restores by sha256 in `finally`):

```
STATE B  fixture present  rc=3  == REFUSED … the CPython oracle is absent: …/sb-oracle.py
STATE A  fixture moved    rc=3  == REFUSED … the regression floor is absent: …/BEFORE-rows.rows
RESTORED  sha256 7a3aa4a4b9e2 -> 7a3aa4a4b9e2  OK
```

With the baseline absent the gate refuses **on the baseline**; with it present the gate
gets past the baseline and refuses **on the oracle** — the baseline input is satisfied.

### 6f. Why the rc does NOT yet move off 3 — exactly

After the baseline is satisfied the gate still refuses, and it cannot leave rc=3 here for
two measured reasons, in order:

1. **The other two inputs are also absent.** `sb-oracle.py` (`$D/sb-oracle.py`) and
   `sb-diff.py` (`$D/sb-diff.py`) are gone; the gate refuses on `sb-oracle.py` next
   (`checks/sb-gate.sh:77-78`). Both are recoverable **blobs** — `git cat-file -s
   a71ed4548b267678242fa5d0e9c4762e8ccf66eb` = **15694** (sb-oracle.py) and
   `git cat-file -s 61654fb779deae483c93eb20e621a1959b230aa0` = **1822** (sb-diff.py) — but
   they are whole ORACLE INSTRUMENTS the sweep deliberately removed, and restoring them is
   a separate act with its own tracked home; doing it does not help (2).
2. **The step after the three asserts is `$BEND $PORT`** (`checks/sb-gate.sh:96`) — a
   `bend` compile. This unit is forbidden to run `bend`. So no run of this gate can produce
   a non-refusal verdict here, whatever the inputs; the baseline refusal moved, the process
   exit did not.

## 7. Read-only scripts and why

Eleven compile `bend` and were read only: `e2e.sh`, `gen.sh`, `lintable-gate.sh`,
`plant.sh`, `run-all.sh`, `run-f64.sh`, `run-port-mm.sh`, `walk-mutate.sh`, `disarm.sh`
(via `.agents/slop/substrate-check.sh`), `substrate-check.sh` (via `checks/substrate.py`),
and — **not obvious** — `bounded-selftest.sh`, whose `exec` target `checks/bounded.py
--selftest` runs `./bin/bend <0-byte file> --check-only` in case 12 (twice: once for
`truth`, once under the guard).

**CORRECTION, MEASURED.** This unit ran `bounded-selftest.sh` once before discovering
that case 12 invokes `bend`. The invocation is a `--check-only` on an empty temp file, but
it is still `bend`, and the instruction was not to run `bend`. The capture is kept (rc=0,
`selftest PASS`) and flagged in `SHELLS.tsv`; no other restart of this unit should run it.
`demo.sh` does not fall in this class: its `-n` mode is HALF 2 only and skips the
`bend --check-only` verdicts, which is why it could be run.

## 8. Findings

- **`gate.sh` is DEAD in the doctrine-2 sense**: rc=2 comparing nothing, because its driver
  `.agents/slop/shlscope/gen.py` is gone (only `00-stub.md` remains). It exits **before**
  the bend line, which is why it could be run. `AGENTS.md` does not mention it.
- **`lint_demo.sh` cannot demonstrate its own lint**: base run is already red (exit 1) from
  files other units wrote — `arghalf/pin-tree/tinygrad/viz/serve.py:135,144` and
  `canrun/belt/nc_probe.py:34,63` — so the `base=0 && planted=1` guard fails and it prints
  `THE LINT DID NOT FLIP`. A red with no paired green, from a different unit's tree.
- **Six scripts name a driver that is GONE** (15 references): `gate.sh` (`gen.py`),
  `lintable-gate.sh` (`lintable-probe.bend`), `plant.sh` and `run-all.sh` (six
  `checks/*.py` each), `classify.sh` (`BLOBHIST.tsv`), `sb-gate.sh` (`sb-oracle.py`,
  `sb-diff.py`). None of these refusals is a SKIP and none is a PASS.
- **`checks/plant.sh` and `checks/run-all.sh` read their drivers from `checks/`**
  (`$HERE/derive.py`, `$HERE/measure.py`, …) and those files are gone, so both are dead
  before they plant anything — but they invoke `bend` first and were not run.
- **`gate.sh` uses `python3`** (PATH's 3.14) not `.venv/bin/python`; the tree's own rule.

## 9. Files this unit wrote

- `checks/sb-gate.sh` — one line: `BASE=` repointed to the tracked fixture.
- `.agents/slop/checkshells/census.py` — the discovery + census instrument.
- `.agents/slop/checkshells/plant_sbgate.py` — the two-state plant.
- `.agents/slop/checkshells/SHELLS.tsv`, `runs/` (`.out`/`.err` captures +
  `rc.tsv`) — the table and the captures.
- `.agents/slop/checkshells/REPORT.md` — this file.

Nothing committed.
