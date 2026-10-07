# quiesce — the quiet-window precondition, measured

Unit of 2026-10-07. Owns `.agents/slop/quiesce/` only. No `bend` started, nothing staged, nothing
committed. Every number below carries its method and its reading time.

**The result, before the defence.** The tree alternates long quiet gaps with short bursts. Two
measured windows had quiet gaps of **595 s and 552 s**, both longer than the **294 s** a
`differ.py run` needs — so a quiet window CAN be obtained. But a burst began **48 s before one
window closed** (`fold.bend`, 05:55:47) and **on the first second of the other** (`nn/__init__.bend`,
05:35:43). **A `PASS` certifies the PAST, not the next 294 s.** So the quietness gate is a
NECESSARY precondition and not a sufficient one, and the thing that makes it sufficient is the
**snapshot** — built, verified, and shown to hold while the live tree moved (`checks/differ.py`
rewritten 05:42:13, `fold.bend` rewritten 05:55:47, snapshot unmoved).

---

## 1. The instrument (`.agents/slop/quiesce/quiesce.py`)

A precondition instrument in `checks/env-precond.py`'s shape — declared population, enforced check,
verdict vocabulary — applied to a different resource: **writes** instead of environment variables.
`AGENTS.md` owns the general rule for a different resource ("THE PRECONDITION IS THE SUM, NOT THE
COUNT" for `bend`'s RSS); this is the same rule applied to writes.

Three verdicts, and **no `FAIL`, because a quietness precondition can only hold, be absent, or be
unmeasured** — `FAIL` means "a stage ran and got the wrong answer", and nothing here compares two
answers:

| verdict | exit | means |
|---|---|---|
| `PASS` | 0 | a quiet window at least `--needs` seconds long was **measured** (never "probably") |
| `REFUSED` | 3 | the tree moves; no window that long exists → **SNAPSHOT, do not wait** |
| `DEAD` | 5 | the observed span is shorter than the run, so nothing about such a window was measured |

`--needs` defaults to **294 s**, run34's own guard wall time (`run34/REPORT.md` §2:
`[bounded] WITHIN-LIMITS rc=1 peak-RSS=771 MB 294s`).

The population is **discovered, not listed** (Doctrine 1): it is the run's inputs, read from
`snapshot.py`'s **declaration, loaded by path** — so the quiet gate and the freeze have ONE author
and cannot disagree about what the run reads. `--declare` prints it and names any input whose anchor
or file is missing (rc=1).

## 2. The window, measured

Two 600 s observations, period 5 s; logs kept at `writes.tsv` and `writes2.tsv`. An 8 h mtime
census over all 142 port+harness files gives the cadence behind them.

| reading | window (local) | population | writes | longest quiet gap | verdict |
|---|---|---|---|---|---|
| A | 05:35:43..05:45:43 | 142 (port + 4 harness files) | 1 — `tinybendygrad/nn/__init__.bend` 05:35:48 | **595 s** | PASS — **and WRONG, see below** |
| B | 05:46:35..05:56:35 | 148 (the run's inputs) | 1 — `tinybendygrad/uop/fold.bend` 05:55:47 | **552 s** | PASS |

**Reading A's `PASS` was a coincidence, and the defect was in this instrument.** Its population
watched the port and the `graphcmp.{py,bend}` pair but not `checks/differ.py` — and
`checks/differ.py` was **rewritten at 05:42:13, inside reading A's window**. The gate said "quiet"
while an input moved. That is Doctrine 1 failing one level down: *an instrument that watches half
its population passes on a coincidence.* Reading B fixed the population to the run's **148** inputs
(`snapshot.py.inputs()`), and the two are now the same list by construction.

**Cadence (8 h mtime census, method: bucket `st_mtime` of the 142 tracked port+harness files into
10-minute bins; `writes_in_last_8h = 7`):**

```
10-min bin (local)   writes
10-07 00:20             2
10-07 00:30             1
10-07 00:40             2
10-07 05:30             2
```

Two bursts — 00:20–00:42 (5 writes in 22 min) and 05:34–05:35 (2 writes in 2 min) — separated by a
**quiet gap of 17,496 s (4 h 51 m)** from 00:42:33 to 05:34:09. `getaddrwire`'s "3 writes in 11 min"
is the same shape.

## 3. Duration vs window — can a quiet window be obtained?

- `differ.py run` needs **294 s** (run34, measured).
- The longest quiet gaps measured are **595 s** (reading A), **552 s** (reading B), and **17,496 s**
  (between bursts, 8 h census).

So **a quiet window long enough DOES exist, and a run can be taken in one.** The task's hypothesis —
"the longest gap is 10 s, so no window exists" — is **not supported by this tree today**: the 10 s
figure was run34's gap *after* its graph phase, not the tree's actual quiet cadence.

**But a `PASS` is still not sufficient, and the measurements say exactly why.** Reading B stayed
quiet for 552 s and then `fold.bend` was written at 05:55:47 — 48 s before the window closed. A
294 s run started at 05:50:47 would have been edited 293 s in. Reading A: `nn/__init__.bend` was
written on the first second of the window. **A burst can begin at any second, and the gate can only
report the window up to now.** Therefore:

> `PASS` → you may start a run, but you have bought a probability, not a guarantee. `REFUSED`/`DEAD`
> → do not wait for a window; **snapshot**.

And because the failure is silent (run34: every step from `control` onward emitted `0 rows` — a
compile break read as a measurement), the robust answer is the snapshot **regardless of the reading**.

## 4. Snapshot (`.agents/slop/quiesce/snapshot.py`) — design and measurement

**What is COPIED vs SYMLINKED, and the split is the design.** The run **re-reads its inputs
throughout**: every `gc()` spawns a fresh `.venv/bin/python graphcmp.py` (which re-reads
`graphcmp.py` **and** `graphcmp.bend` from disk — `differ.py:320`, `graphcmp.py:1949`), and every
`emit` runs `bin/bend` over the port. So the port, the two harness files, the oracles, the driver and
`devpin.py` are **copied** (a real byte copy — **never a hardlink**, because a unit editing a file in
place would move the shared inode). The **toolchain** (`.venv`, `references/`, `tinygrad/`) is
**symlinked**: it is not what moves, and copying 264 MB to freeze 11 MB is a backup, not a snapshot.

**The output directory is RE-POINTED**, the one thing a run cannot resolve for itself: `differ.py`
computes `D = ROOT/"runs/graphcmp/D"` from its own `__file__`, so a snapshot run writes to the
snapshot's `runs/`. `--out DIR` symlinks `DEST/runs` at `DIR`; point it at the live
`runs/graphcmp/D` to keep the canonical artifact location (`runs/` is gitignored **output**, not an
input, so it is safe to share). Default is `DEST/runs`.

**Measurements.**

1. **Built** the real tree at 05:36:13: `froze 148 input(s)`; toolchain symlinked
   (`.venv`, `references`, `tinygrad`). `.venv` here is 34 MB, `references` 227 MB, `tinygrad` 30 MB
   — 291 MB of toolchain symlinked rather than copied.
2. **Resolves inside itself** (loaded the snapshot's own `differ.py`/`graphcmp.py`):
   `ROOT`, `GCMP`, `BEND_PROBE`, `BEND` all point into the snapshot dir; `corpus()` = 34; and
   `snap/.venv/bin/python snap/checks/differ.py --help` runs.
3. **Holds while the live tree moves** — the real snapshot, re-verified at 05:59:51:
   ```
   VERIFY: OK -- 148 of 148 frozen inputs unchanged; 2 differ from the live tree
     frozen  checks/differ.py             snap=6014818d33ce live=8119ffa0b56e
     frozen  tinybendygrad/uop/fold.bend  snap=472018f50fd0 live=fd9cc05c7479
   ```
   Two LIVE inputs were rewritten after the freeze (05:42:13, 05:55:47) and the snapshot did not
   move. **This is the real-tree half** — and it proves the freeze covers `checks/differ.py`, the
   input reading A's population missed.
4. **End-to-end on a live clone** (`freeze-check.py`, touching nothing live): clone the real
   140-file port + harness into a temp tree, `build`, edit the clone, verify. `snapshot unchanged:
   PASS`; `the edit reached the clone: PASS`; `FREEZE-CHECK: OK`. A toy tree would prove the toy;
   this exercises the same `build`/`verify` on the real bytes.

## 5. `--gate` and both plants

- **`--gate`** re-judges a log with no sampling, so the verdict and the evidence cannot disagree.
  On `writes2.tsv`: `PASS`, rc=0, evidence = the 552 s gap and the `fold.bend` write at 05:55:47.
  With `--needs 900` (a run longer than the observed span): `DEAD`, **rc=5** — "observed 600s < the
  run's 900s".
- **Plants, both halves** (`--plant`, fixed expectations, no real tree):
  ```
  PLANT moving: longest gap 60s  -> 3 (want 3)  OK
  PLANT quiet : longest gap 600s -> 0 (want 0)  OK
  ```
  A moving tree is `REFUSED` (3); a quiet tree is evaluated (0). A gate that can only refuse is a
  coin that always says no.

## 6. What a snapshot must freeze, and what only a snapshot cannot fix

**Item 6's residual is the point**: a snapshot that freezes only the port freezes half its inputs.
The run's inputs, by where `differ.py` reads them:

| input | read when | must freeze |
|---|---|---|
| `tinybendygrad/**` | every `emit` (imported by `graphcmp.bend`) | **yes — repeated** |
| `.agents/slop/graphcmp.py` | every `gc()` spawns `python graphcmp.py` (`differ.py:320`) | **yes — repeated** |
| `.agents/slop/graphcmp.bend` | every `emit_bend` (`graphcmp.py:1949`) and `ready()`'s probe (`differ.py:783`) | **yes — repeated** |
| `checks/differ.py` | `repro`'s `clean_run` re-invokes it (`differ.py:950`) | **yes — repeated under `repro`** |
| `checks/devpin.py` | once, at summary time (`differ.py:701`) | yes |
| the three oracles | once each (`differ.py:544,547,551`) | yes |
| `graphcmp-empty.bend` | once, the 0-row guard (`differ.py:541`) | yes |
| `graphcmp-dbg.bend` | once, the `dbg` steps (`graphcmp.py:2758`) | yes |
| `diffpy/oracle-*.sh` | once, `check_oracle()` (`differ.py:79`) | yes |

So: **the repeated ones break every later step (run34's exact mechanism), and the once-read ones can
be edited before their step — therefore ALL must be frozen, not just the port.** `snapshot.py` freezes
the whole set (148 inputs), and `quiesce.py` watches the same set.

**Two of those inputs are currently ABSENT**, and `--declare` (rc=1) names them:
`graphcmp-dbg.bend` and `graphcmp-empty.bend` do not exist on disk. They were deleted by the sweep
commit `371cc64c9` ("deleted 3,603 files") after run34 produced their artifacts (which still exist
under `runs/graphcmp/D/`). With them gone, `differ.py run`'s `D8-dbg-*` and `D10-zerorow-guard`
steps cannot be produced. **This is a run-input defect, not a quietness one** — reported here because
a snapshot cannot freeze a file that is not there, and a gate that silently skips it would freeze
half its inputs.

**What ONLY a snapshot cannot fix:** nothing that this instrument can see. A snapshot freezes the
inputs; the residual risk moves to the *outputs* and to `runs/` (shared, gitignored) — if `--out`
points at the live `runs/graphcmp/D`, a concurrent reader (`corpus-figure.py`, `disagree-gate.py`)
can read a half-written run. Take the run with a private `--out` and copy the artifacts to the
canonical path on completion.

## 7. How to use it (the two commands a next unit needs)

```sh
# 1. Is the tree quiet enough to bother? (PASS = necessary, not sufficient; REFUSED/DEAD = snapshot)
.venv/bin/python .agents/slop/quiesce/quiesce.py --watch 600 --needs 294

# 2. The robust path: freeze the inputs, edit nothing live, run against the copy.
SNAP=$(mktemp -d)/snap
.venv/bin/python .agents/slop/quiesce/snapshot.py --build "$SNAP" --out "$PWD/runs"
"$SNAP/.venv/bin/python" "$SNAP/checks/differ.py" run \
  && .venv/bin/python .agents/slop/quiesce/snapshot.py --verify "$SNAP"
```

`--verify` prints `frozen ... live=...` for every input a concurrent unit edited after the freeze —
the audit trail that the run was measured against a fixed tree.

## Denominators

- Population: **148 present** run inputs (140-file port walk + `bin/bend` + 7 harness files); **2
  further declared inputs are ABSENT** (`graphcmp-dbg.bend`, `graphcmp-empty.bend`).
- Observations: 2 × 600 s live windows, period 5 s; 1 × 8 h mtime census.
- Run duration: 294 s (run34), the number `--needs` beats against.
- No `.txt` written; logs are `.tsv`, output is `.out`, this report is `.md`.
