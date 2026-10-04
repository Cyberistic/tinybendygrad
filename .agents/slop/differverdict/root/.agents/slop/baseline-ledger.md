# The baseline ledger — every recorded count, and the load it was taken at

Written 2026-10-04 by the load-census unit. **This is a ledger, not a refresh.** No lane was
re-run to produce a number in this file. Every count is left exactly as recorded and MARKED.

> **THE RULE THIS FILE EXISTS TO KEEP**
>
> **A count measured under unknown load is not a count.**
>
> A baseline recorded under unknown load is still *evidence about that moment*. Marking it is
> correct. Overwriting it is not: re-running under low load and substituting the result would
> replace a true record of what was measured with a tidier number, and would destroy the ability
> to say UNCHANGED against the original capture. Where a baseline was re-measurable and was
> re-measured, that is a **separate artefact beside** the ledger entry — never in place of it.

Regenerate: `python3 .agents/slop/load-census.py --ledger [--ledger-json PATH]`.
Mechanical test: `python3 .agents/slop/load-census.py --guard` (exits 1 while the corpus is dirty).
Starvation retrospective: `python3 .agents/slop/load-census.py --starvation`.

---

## 1. THE DENOMINATOR

**234 recorded baseline counts, in 13 files.**

A "recorded baseline" is defined mechanically so the denominator is a number and not a mood: a
file in this corpus whose row counts a later comparison is made *against*. Three shapes, found by
glob, never typed — a lane stdout dump (`*baseline*.txt`), a recorded lane map
(`rebase/baseline*.json`), and the repeat-run capture (`rebase/stability-*.json`).

| file | counts | what it is |
|---|---:|---|
| `rebase/baseline.json` | 90 | **the** baseline: 30 ports × {interpreted, native, cpython oracle} |
| `rebase/stability-2026-10-03.json` | 110 | 38 ports × lanes, each lane run **twice** |
| `rebase/baseline-DEMO.json` | 24 | 8 ports × 3 lanes — see finding F1, it **disagrees** with the above |
| `boot42_baseline_port.txt` | 1 | 768 distinct row names — the `nvdev.bend` capture NV7 quotes |
| `memory-baseline-889.txt` | 1 | 889 |
| `naming-gate-baseline.txt` | 1 | 668 |
| `wgsl-baseline-172.txt` | 1 | 172 |
| `vw-mut-baseline.txt` | 1 | 159 |
| `amdev-baseline-552.txt` | 1 | 552 |
| `ops-python-baseline-85.txt` | 1 | 85 |
| `arena-jit-baseline.txt` | 1 | 137 — identified as `engine/jit.bend native` |
| `rangeify-baseline-126.txt` | 1 | 126 — identified as `schedule/rangeify.bend native` |
| `.mine-baseline.txt` | 1 | 40 — another unit's file, unidentified |

This is the ledger. **It reads as almost entirely un-green, and it should.** The whole corpus was
taken at unknown machine load and nothing recorded otherwise.

---

## 2. VERDICTS, WITH THE DENOMINATOR ATTACHED

| verdict | count | of |
|---|---:|---:|
| `OK` — a load is recorded beside the count, below the mark | **0** | 234 |
| `RE-MEASURED-ALONGSIDE` — no load, but a second run in the same session reproduced the count | **215** | 234 |
| `SUSPECT` — no load, no elapsed time, no revision, no corroborating second run | **19** | 234 |

**Counts taken at a known load: 0. Load recorded as UNKNOWN: 234.**

Across the *whole* record layer (every count written down anywhere in `.agents/slop`, not only
baselines): **92 of 1,816** sensitive recorded counts are load-qualified — **5.1%**. The remaining
**1,724** carry no load. This is the finding, not a defect in the scan: nothing in this project
ever recorded a load beside a count.

⚠ **The record-layer denominator is a MOVING TARGET and the ledger's is not.** Measured across this
session: 1,816 → 1,851 → 1,873 sensitive counts, because five other units are writing records right
now. The **ledger** denominator held at **234** across three consecutive runs. Quote the ledger
denominator for anything that has to stay true; quote the record-layer figure only with its date,
or the next reader will diff two different populations and call one of them a regression.

### What the 215 corroborated counts do and do not establish

`rebase/stability-2026-10-03.json` ran all 38 ports twice. **All 110 lane counts were identical
across the two runs** (`110 of 110`). That is real evidence that these counts are *reproducible*.

It is **not** evidence that they were taken at a known load. Two runs on one machine of unknown
loading are two draws from one distribution, not two machines — and they agree just as happily
when both are starved. This is why `RE-MEASURED-ALONGSIDE` is its own verdict and not a shade of
`OK`: the verdict must not overstate what the corroboration shows.

---

## 3. RECOVERABLE vs UNRECOVERABLE — **0 and 234**

The test, as briefed: a baseline whose *source file* is unchanged **and** whose *capture* records
an elapsed time can often be judged; one with neither cannot. Each half, measured:

| condition | holds for |
|---|---:|
| the capture records a **load** | **0 of 234** |
| the capture records an **elapsed time** (`row_secs`) | **0 of 234** |
| the capture records a **revision** | **0 of 234** |

**RECOVERABLE: 0 of 234. UNRECOVERABLE: 234 of 234.**

The revision half is worth stating precisely, because it is worse than "unmet". `UNCHANGED` means
"this port's rows are identical to the baseline", which is only meaningful if the baseline
describes *this* tree. With no recorded revision there is nothing for the working copy to be
compared against, so the test is **UNDECIDABLE, not merely unmet** — the ledger cannot establish
that any baseline is even about the tree it is being used to judge. That is a stronger statement
than "the load is missing", and it is the one the brief's `UNCHANGED` requirement actually turns on.

A ledger whose recoverable class is empty is not actionable by re-reading. It is actionable only
by **re-measuring forward** — which produces a *new* artefact beside these rows, and leaves every
row here standing as a record of what was measured at unknown load.

---

## 4. FINDINGS — things found, and what was done about them

### F1 — Two files both called "baseline" disagree on 7 of 21 shared lane counts

`rebase/baseline.json` (30 ports, 90 counts) and `rebase/baseline-DEMO.json` (8 ports, 24 counts)
share **7 ports**. Of their **21** common (port, lane) pairs, **7 disagree**:

| port / lane | `baseline.json` | `baseline-DEMO.json` |
|---|---:|---:|
| `codegen/opt/search.bend` interpreted, native | **38** | **18** |
| `uop/ops.bend` interpreted, native | **115** | **104** |
| `uop/ops.bend` cpython:rebase-oracle-ops | **68** | **63** |
| `uop/spec.bend` interpreted, native | **25** | **21** |

`baseline-DEMO.json` is ~23 h older (01:05 vs 23:55 on 2026-10-03). Both
`rebase/record-2026-10-03.txt` and `rebase/stability-2026-10-03.json` side with `baseline.json`,
so `DEMO` is the outlier — **but nothing in the corpus says which file a reader should load**, and
neither records a load. A reader who opens `baseline-DEMO.json` gets a different answer for 7 lane
counts than one who opens `baseline.json`. **NOT FIXED:** `baseline.json` is read-only for this
unit and `baseline-DEMO.json` was not in scope to rewrite. Both observed values are recorded above
rather than harmonised.

### F2 — The anchor number of the starvation invariant has three values and no unit

`loadwatch.py` `_OBSERVED["full_rows"] = 787`, quoted from NV7 ("787 rows in 0.5 s"). The stored
capture of that lane, `boot42_baseline_port.txt`, holds:

* **780** rows in **780** non-blank lines (787 total lines, 7 blank),
* of which **768 are distinct names** — six names are emitted **3× each**
  (`nv_largebar_0000_0000`, `nv_reserve_ptable_0000_0000`, `nv_sysmem_default_0000_0000`,
  `nv_sysmem_0000_0000_{None,True,False}`),
* the final line is the completion sentinel `nvdev-done=1`.

So the same lane is **787 / 780 / 768** depending on which unit you ask for. This matters beyond
bookkeeping: the baseline layer counts **distinct names** (`len(rowsd)` over a dict keyed by name),
while the starvation slope's axis is a **line count**. They differ by 19 on the one lane the whole
invariance is built on. Separately, `nv_nvdev_mutrun.py:13` records "`bend <file>` measured
**24 min** for 787 rows on this machine" — which is not compatible with the "0.5 s" the same
787 is quoted at. **Reported, not fixed:** `loadwatch.py` is not this unit's file.

### F3 — `THRESHOLD = 4.0` has no observation behind it

`loadwatch.py` derives the mark as "the largest load at which a full 787-row count was actually
observed". In `lane-load-measurements.tsv`, **0 of 18** row-emitting reps reached 787 (max **79**),
and `_OBSERVED["max_load_with_full_count"]` is `None`. The conservative threshold is therefore
derived from an observation class with **zero members**. The threshold may be entirely reasonable;
nothing in the corpus establishes it. It is currently a typed constant wearing a measured
provenance. **Reported, not fixed** — `loadwatch.py` is not this unit's file.

### F4 — `renderer/cstyle.bend` has a recorded baseline for a lane pair that shares no row name

`rebase/record-2026-10-03.txt` **EXCLUDED** this port four times — once per lane pair per run —
with the reason "a baseline here would be **a recording of silence**", and then, on its last
line, recorded:

> `LEFT UNTOUCHED (already recorded, not in the qualifying set): tinybendygrad/renderer/cstyle.bend`

`baseline.json` still carries `cpython:renderer_oracle = 33` for it, while
`stability-2026-10-03.json` measured the same oracle at **15** rows. The recorder identified this
exact hazard and then routed around it, because the port was *already* in the file and the
"already recorded" branch skipped re-qualification. **NOT FIXED** — `baseline.json` is read-only
for this unit. This is the only `SUSPECT` in the 90 counts of `baseline.json`.

### F5 — 3 of the 18 stored BROKEN verdicts are a documented non-defect

`dtype.bend` is BROKEN in all three stored sweeps with an identical `why`. Its lanes print
`SOME PROOFS FAIL` for 14 defs relying on unsafe or foreign code, and `native: Error: no main to
run` — the permanent condition recorded in `agent-core.md`. So of **18** stored BROKEN verdicts,
**3 are a known Bend limitation and 15 are unclassified**. Stated with the denominator because a
reader shown `BROKEN 18` would otherwise go looking for eighteen port defects.

### F6 — The stored sweeps violate this project's own denominator rule

4 of the 18 BROKEN verdicts read `2 row(s) disagree with CPython across 3 lane pair(s)` — a
disagreement count with **no shared-row denominator**. **0 of 4** carry one. Same species as the
load defect: a count reported without the population it is a fraction of.

### F7–F10 — Defects in the census itself, found and fixed by this unit

These are recorded because they are the exact shapes this unit exists to catch, and three of the
four were found *here* rather than by a reader.

* **F7.** `load-census.py`'s header claimed `rebase-gate-selftest.py` carried a `load_guard()`
  that called `census()` from here. **It does not, and never did** — that file imports nothing from
  this module. A docstring describing intended wiring as present wiring, written in the tool built
  to catch stale provenance. The guard now lives here, where it can be run.
* **F8.** The same header quoted "108 occurrences of the substring `load`" in `baseline.json`.
  Measured: **176** (27 of them the literal `load1`, every one inside a row name such as
  `k1_load_store`; **zero** JSON keys begin with `load`). The prose had gone stale the way every
  number in this project goes stale: the file grew, the prose did not.
* **F9.** `load_guard()` v1 printed *"215 of 234 carry a load or an elapsed time"*, computed as
  `total − SUSPECT` — so every `RE-MEASURED-ALONGSIDE` row silently counted as **qualified**. The
  headline contradicted its own detail table three lines below it, which is the most expensive
  shape there is: a summary flattering itself while its own detail disproves it. Now computed from
  the load and elapsed-time facts alone, and it reads **0 of 234**.
* **F10.** The ledger's `*baseline*.txt` glob matched `baseline-ledger.txt`, so **the ledger
  counted its own output**: the denominator read 234, then **235** seconds later, with no edit in
  between. `SELF` already excluded the census's own files from the *text* layer; it simply was not
  applied to the ledger's glob. Fixed, and the denominator is now stable at 234 across runs.
* **F11.** `starvation_retrospective()` v1 counted the `G_checkonly_f16` reps' **0 rows** as
  starvation. That cell is the `--check-only` **control**, which prints no rows *by design*
  (NV7: 0.37 s under 19 concurrent compilers). A deliberate zero read as a starved lane is the
  "never report an unexplained zero as a result" defect wearing a load number. The TSV has no
  invocation column, so the discriminator is the observable: 0-row reps are **excluded and named**
  (3 reps, cell `G_checkonly_f16`).

---

## 5. THE INVARIANT, WHERE A READER HITS IT

Stated in `loadwatch.py` (which is the gate's own header), asserted mechanically by
`load-census.py::load_guard()`, and recorded here:

> **A count measured under unknown load is not a count.**

The test that fails when a recorded count has no load beside it:

```
python3 .agents/slop/load-census.py --guard     # exits 1 while the corpus is dirty
```

It fails **by design**, and it will keep failing: **0 of 234** recorded baseline counts carry a
load. A guard that passed on the corpus as it stands would itself be the defect — it would mean
either the corpus had been fixed (it has not) or the guard had stopped looking.

**Already true in this corpus, for the record.** Two prior instances of this ledger, both done
correctly — each reports **both observed values** and the reason it moves, rather than silently
harmonising them:

* the **VERBATIM naming-gate count**, **283** (byte-identical md5 across repeated runs at a settled
  substrate) vs **278** (19:34–19:36, with `codegen/__init__.bend` mid-edit) —
  `ruling-naming-gate-getenv-int.md`, `hygiene-2026-10-04.md`, `state-audit-report.md`;
* the **`elf.bend` row count**, **353** (reproduced by a complete run) vs **331** (unreproduced),
  with a third value **246** explicitly **retracted** rather than quietly dropped —
  `hygiene-2026-10-04.md` §5.

That second one is the shape to copy: a number that cannot be trusted, stated **with the two
observed values and the reason it moves**.