# `checks/gatesweep.py` — a `--selftest` that can fail, and proof inputs that cannot be pruned

Unit report. Every number carries its denominator and a timestamp. HEAD at start `c1e2b9fb2`, at
finish `00e0b4f78` (a concurrent session is committing into this tree; none of the numbers below
depends on which of the two is HEAD). Repo-relative paths throughout.

## Paths changed

| path | state | why |
|---|---|---|
| `checks/gatesweep.py` | **modified** (246 → 358 lines) | extracted `sweep()`, added `--selftest`/`--plant`, repointed `--prove` to pinned in-repo inputs |
| `checks/gatesweep-cost.out` | **new** (1673 B) | the frozen per-gate transcript, byte-identical to `.agents/slop/hooks/cost.out` |
| `checks/gatesweep-run.tsv` | **new** (1535 B) | the frozen recorded-verdict transcript, byte-identical to `.agents/slop/hooks/run.tsv` |
| `.agents/slop/gwself/{REPORT.md,*.out}` | new | this report and the raw captures it cites |
| `.agents/TOOLS.md` | **modified** (the `gatesweep` section, `:1605–1611`) | its `--prove` row named the prunable `.agents/slop/hooks/` inputs, and its `flush()` claim was asserted rather than proven — both now say what is measured |

Nothing was committed, nothing was `git add`ed, and `jj` was not run.

## 1. `--selftest` — the ad-hoc probe, made repeatable, and made able to fail

The loop moved out of `main()` into `sweep(gates, out, seconds, mb)`. `main()`'s default branch is
now `return sweep(...)` and nothing else, so the selftest drives **the same function the real run
calls** — not a copy of the loop. `sweep()` is the only place the header, the per-gate row, the
per-gate `flush()`, the tally and the denominator live.

The population is a temp `gates/` under `.agents/slop/gwself.<rand>/`, **inside the repo**, so
`population()` (a real `os.walk`) walks it and every `relative_to(ROOT)` inside the loop holds. Five
tiny children, one per fixture, named so the sleeper sorts last:

| planted child | source | the branch it must land on |
|---|---|---|
| `dead-gate.py` | *(0 bytes)* | rc 0, emitted nothing → `DEAD`/`SILENT` |
| `fail-gate.py` | `sys.stderr.write('no\n'); sys.exit(1)` | rc 1, said something, no traceback → `FAIL` |
| `pass-gate.py` | `print('ok')` | rc 0 with output → `PASS` |
| `refuse-gate.py` | `sys.stderr.write('absent\n'); sys.exit(3)` | `gatekit.VERDICT[3]` → `REFUSED` |
| `skip-gate.py` | `time.sleep(60)` | the 1 s watchdog bound kills it → `SKIP`/`TIMED-OUT` |

Run (2026-10-15 12:30 local, `.venv/bin/python checks/gatesweep.py --selftest`, capture
`selftest.out`, per-gate lines abridged to `.../`): **rc=0, 3 case(s), 0 failed.** The rows file's own
content is the assertion — the subject is the artifact a killed sweep leaves behind, not `classify()`'s
return value:

```
  DEAD        0.1s  rc=0    peak=   0MB  .../dead-gate.py SILENT
  FAIL        0.3s  rc=1    peak=   0MB  .../fail-gate.py FAIL
  PASS        0.1s  rc=0    peak=   0MB  .../pass-gate.py PASS
  REFUSED     0.3s  rc=3    peak=   0MB  .../refuse-gate.py REFUSED
  SKIP        1.2s  rc=-9   peak=  18MB  .../skip-gate.py TIMED-OUT
TALLY: DEAD=1  FAIL=1  PASS=1  REFUSED=1  SKIP=1
THE DENOMINATOR: 2 of 5 gates reached a verdict about the tree; 1 refused, 1 did not finish, 1 crashed or said nothing.
[PASS] FIVE VERDICTS: the rows file classifies each planted child as planted
[PASS] SHAPE: a header and exactly one row per gate
[PASS] INCREMENTAL: rows are ON DISK while the sweep is STILL RUNNING
=== selftest PASS: 3 case(s), 0 failed ===
```

**7 clean runs** (2026-10-15 12:25–12:32 local; every run of the unmutated harness this session returned
rc=0 — the harness is timing-dependent in exactly one case, and that case is stated below rather
than hoped about). Temp dirs are removed by `TemporaryDirectory`; `ls -d .agents/slop/gwself.*` is a
no-match after every run (measured).

### It can fail — twice, deliberately, on two different subjects

**(a) A planted expectation that is wrong.** `--selftest --plant` mislabels one expected verdict
(`dead-gate.py -> PASS` while the row says `DEAD`) on the same code path. Capture
`selftest-plant.out`, measured 2026-10-15 12:30 local: **rc=1, 3 case(s), 1 failed**, and the failure is
the planted one by name:

```
[FAIL] FIVE VERDICTS: the rows file classifies each planted child as planted
          dead-gate.py -> 'DEAD', expected 'PASS'
=== selftest FAIL: 3 case(s), 1 failed -- PLANTED, and the failure is the point ===
```

**(b) The mutation that matters: the per-gate `flush()` removed.** `--plant` proves the *assertion*
is real; it does not prove the *flushing* is tested. So the `sink.flush()` at `sweep()` was deleted
by hand, the selftest re-run, and the line restored. Capture `selftest-noflush.out`, measured
2026-10-15 12:31 local: **rc=1**, and the other two cases stay green —

```
[PASS] FIVE VERDICTS: ...   [PASS] SHAPE: ...
[FAIL] INCREMENTAL: rows are ON DISK while the sweep is STILL RUNNING
          read (5, False) (rows, sweep-alive) mid-sweep
```

`(5, False)` is the whole defect in one pair: with no per-gate flush the file only becomes complete
at `close()`, so a reader mid-sweep sees nothing and a reader at exit sees a `False`. The unmutated
run reads `(1, True)` — a row on disk **while the sweep is still running**, which is the durability
property and the one claim a run that *completes* cannot make.

### The one timing-dependent case, stated

`INCREMENTAL` needs at least one row on disk before the last gate finishes, and it gets its window
from `skip-gate.py`, which the 1 s bound holds open for ~1.2 s. The read is a 20 ms busy-wait for
`rows >= 1`, and `worker.is_alive()` is sampled **with** the read, so a file that was complete at
exit cannot be mistaken for an incremental one (that is exactly what the mutation run reported). If
the sleeper were ever removed the case would go red rather than silently weak; it does **not** pass
on a `rows == len(PLANTS)` reading, because `1 <= rows < 5` is asserted as well.

## 2. `--prove`'s inputs moved beside the gate, and are pinned

`--prove` read `.agents/slop/hooks/{cost.out,run.tsv}` — a **prunable** directory (`AGENTS.md`
counts 85 of the 169 already-gone `.agents/TOOLS.md` paths under `.agents/slop/`). Losing them makes
`--prove` print `PROOF: 0/0 ...` and return 1: a failure whose denominator cannot say it lost its
data. The two transcripts are now `checks/gatesweep-cost.out` and `checks/gatesweep-run.tsv`, in
git, beside the gate, and `PROVE_PIN` holds their sha256:

```
checks/gatesweep-cost.out  de8038e7bfc24f8be65d8357773e4329d8cfedadb98e86b691ca17a1aebb65b2
checks/gatesweep-run.tsv   d44ab732bf834012d5127b3d099a097312678d013401fa93761320b4b8c555a2
```

Both hashes are byte-identical to the `.agents/slop/hooks/` originals (measured 2026-10-15 12:28 local,
`shasum -a 256`, all four lines equal in pairs). `--prove` now calls `gatekit.oracle_drift(PROVE_PIN)`
first and **REFUSES (3) on drift**, because a transcript that moved is a proof about other bytes.
Proven live, 2026-10-15 12:29 local: one `x` appended to `checks/gatesweep-cost.out` gives

```
PROVE: REFUSED -- checks/gatesweep-cost.out: ea8627b170e6fb28 != pinned de8038e7bfc24f8b    rc=3
```

and after restoring the identical bytes, `--prove` is **14/14 recorded verdicts reproduced from
(rc, first line) alone, rc=0** (capture `prove.out`) — the same 14 as before the move, run against
the pinned copies.

**I kept `--prove`; it is not redundant with `--selftest`, measured.** The two carry different
populations: the selftest classifies five *synthetic* children it wrote a moment ago, and proves the
**loop** (rows, flush, tally, denominator). `--prove` classifies 14 outcomes from a run that
*actually happened*, and those include shapes the selftest cannot manufacture from a one-liner —
`residue.py`'s `OVER-CAP` reconstructed as `TIMED-OUT` → `SKIP`, `oracle_f64.py`'s rc 1 + traceback
→ `DEAD`, and seven `rc=3` refusals. A synthetic five and a recorded fourteen are not the same
denominator, so retiring one to keep the other would have narrowed the instrument.

**What I refused to delete.** The `.agents/slop/hooks/{cost.out,run.tsv}` originals are left in
place. They are the **hooks harness's own outputs** (`.agents/slop/hooks/REPORT.md:44-45` cites
both by name), tracked in git, and belong to a different unit's directory — deleting another unit's
artifacts is outside this brief and the orchestrator commits by explicit path. `--prove` has exactly
**one** live input path now (`checks/`), and the pin is what keeps that path from being edited into
passing; the `.agents/slop` copies are inert as far as this instrument is concerned. If the
orchestrator wants the duplicate gone, `git rm .agents/slop/hooks/cost.out
.agents/slop/hooks/run.tsv` is a one-line follow-up that `--prove` does not notice.

## 3. Numbers, each with its denominator

- `--selftest`: **3 cases, 0 failed, rc=0**, 7 runs, 2026-10-15 12:25–12:32 local.
- `--selftest --plant`: **3 cases, 1 failed, rc=1** (the planted `DEAD → 'PASS'`), 12:30 local.
- `--selftest` with `sweep()`'s per-gate `flush()` deleted: **3 cases, 1 failed, rc=1**
  (`INCREMENTAL` read `(5, False)`), 12:31 local; the line was restored immediately and re-verified.
- `--prove`: **14 of 14 recorded verdicts reproduced, rc=0**, 12:30 local, over the pinned
  `checks/gatesweep-cost.out` + `checks/gatesweep-run.tsv`.
- `--prove` on a 1-byte-drifted transcript: **REFUSED, rc=3**, 12:29 local.
- `--plan`: unchanged — **70** `gates/*-gate.py` by directory walk against the control's
  **188 entries + 60 modules**, 12:32 local.
- Per-gate peak in the selftest: **0 MB** for the four instant children, **18 MB** for the sleeper —
  the synthetic population is a ~0 MB child per run, which is why the brief's one exception
  (`gatesweep.py` against synthetic gates) is the only thing this unit ran under a watchdog.

## 4. What I refused

- **I did not run the default sweep.** It runs all 70 `gates/*-gate.py` through `bend`, and the
  host is under a concurrent editor at load ~7/12. `sweep()` is exercised only on the synthetic
  population; the 70-gate path is the same code and is left to the orchestrator.
- **I did not delete anything outside the selftest's own temp directory**, and nothing at all inside
  the repo except the one hand-mutation of `checks/gatesweep.py`, which was reverted in the same
  minute and re-verified (`py_compile` clean, selftest rc=0).
- **I did not scrape prose for a verdict word.** The token is still `gatekit.VERDICT`'s word for
  the exit code; the selftest asserts on the rows file, which is that word.
- **No commit, no `git add`, no `jj`** — a concurrent session is committing into this repo.
