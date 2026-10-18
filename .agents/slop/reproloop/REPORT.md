# `repro`'s bound, its exit code, and the stale second witness

Grant: `checks/differ.py`, `runs/graphcmp/**`, new `gates/*repro*`. No `.bend` touched.
`tinygrad/` untouched (read-only, byte-identical to upstream).

Every number below was printed by a command run during this session. Where a figure is quoted
from a file, the file's date is given, because the file is older than the claim.

---

## 1. THE SEVEN COMPLAINTS, VERBATIM

`.venv/bin/python -c "<import differ.py by path; print(unhealthy())>"`, on the artifact set
`runs/graphcmp/D/D0-run-summary.txt` dated **2026-10-18 05:51:48**:

```
unhealthy() -> 7 complaint(s)
1. expect-moved=3 (expected 0)
2. graphs-agree=31 (expected 34)
3. byte-identical=20 (expected 34)
4. stable-pairs=4 of 5 (expected 5 of 5)
5. stable-failed=1 of 5 (expected 0 of 5)
6. oracle-selfcheck=# ORACLE SELFCHECK: FAIL (expected # ORACLE SELFCHECK: OK)
7. census-rc=rc=1 (expected rc=0)
repro_bad() -> []
```

A complaint count of 7 is not universal: `unhealthy()` also calls `substrate_bad()`, so a run
whose `substrate-start != substrate-end` yields an 8th. I produced an 8th myself by editing
`checks/differ.py` mid-run — see §8.

## 2. WHICH ARE REAL DEFECTS AND WHICH ARE UNREGENERATED WITNESSES

**ALL SEVEN ARE REAL DEFECTS. NONE IS A STALE WITNESS.** Decided by two commands, not by reading.

The question is only open if the summary could be describing a tree that is gone. It is not:

```
gates/corpusverdict-gate.py   ->  substrate ... verdict=CURRENT
                                 recorded=9528bb5e2489ad69  live=9528bb5e2489ad69  inputs=156
```

`corpusverdict-gate.py:170` compares `differ.substrate_digest()` against the two rows
`differ` itself wrote. Recorded == live. The Oct-18 05:51 summary describes THIS tree, so its
rows are measurements, and a measurement that contradicts `PINS` is a defect reported by a
working gate.

**THE PINS ARE THE STALE SIDE, NOT THE COMPLAINTS.** `PINS["graphs-agree"]="34"` and
`PINS["byte-identical"]="34"` were moved `32 -> 34` on 2026-10-13 per the comment at
`differ.py:288`. The measurement is 31 and 20. A pin HIGHER than its subject is not a strict
gate, it is a gate the port has not caught up with — and re-pinning it downward to 31/20 would
be exactly the forbidden move: **it would delete the defect the complaint is about.** The
comment at `differ.py:288-290` already says this ("A PIN THAT IS LOWER THAN ITS SUBJECT IS
NOT A STRICTER GATE, IT IS A STALE ONE"), and the pins here are higher, so they are the
aspiration and the run is the truth.

### THE SEVEN ARE FOUR ROOT CAUSES, read off the artifacts

| # | complaint | root cause | witness |
|---|---|---|---|
| 1, 2, 4, 5 | `expect-moved=3`, `graphs-agree=31`, `stable-pairs=4 of 5`, `stable-failed=1 of 5` | **the `loop` graph's bend side emits 0 rows** | `D1-verdicts.txt`: `loop: VERDICT= EXPECTED=AGREE` (empty). `D9-stability.txt`: `loop: ONE SIDE IS A 0-ROW FAILURE after a retry` |
| 1, 2 | `expect-moved=3`, `graphs-agree=31` | **`gate` and `lin` DISAGREE** | `D1-verdicts.txt`: `gate: VERDICT=DISAGREE`, `lin: VERDICT=DISAGREE`. 31 agree + 2 disagree + 1 empty = 34, which reconciles exactly |
| 3 | `byte-identical=20` | **14 of 34 graphs differ on node-id numbering / emission order, not on graph content** | `D2-bytediff.txt`: 20 `BYTE-IDENTICAL` + 14 `DIFFERS`. `alu`: py emits `2:i1 5:STACK ...` while bend emits `3:i15 5:STACK` then restarts `2:i1` — same nodes, different ids/order |
| 6, 7 | `oracle-selfcheck=FAIL`, `census-rc=rc=1` | **ONE cause: the census selfcheck's device sets disagree** | `D0-coverage-census.txt`: `ORACLE SELFCHECK: FAIL` / `loop: the two sides opened DIFFERENT devices -- py ['N', 'sCPU'] against bend ['sCPU']` |

So 7 complaints, 4 defects. Fixing 6 and 7 is one edit; fixing 4 and 5 is one edit; 1 and 2
need the `loop`/`gate`/`lin` emissions fixed; 3 needs the canonicaliser.

## 3. `clean_run`'s BOUND — it HAS ONE

**The brief's premise is wrong on this point and I measured it rather than accepting it.**

```python
# checks/differ.py:1266  (pre-edit line number)
for attempt in range(wait):
```

`clean_run` has been bounded by `wait` attempts all along, default 9. **It was never an
infinite loop**, so "a timer bounding an infinite loop" misdescribes it. What was missing was
the ARITHMETIC: `ready(wait)` is called once per attempt and itself probes `wait` times with
`time.sleep(60)` between probes, so the sleep ceiling is `60*(wait-1)+30` = 510 s **per
attempt**, `9 x 510 = 4590 s` for one `clean_run`, and `cmd_repro` calls it twice = **9180 s =
2 h 33 min**. `checks/bounded.py:209-212` already recorded the consequence: "`differ.py repro`
ran 184 s on 2026-10-13 and was killed at 900 s on 2026-10-14 with `out=0B err=0B`".

**A bound no caller can compute is indistinguishable from no bound.** So the observed "600 s" was
a caller's budget meeting a 9180 s ceiling — not a timeout policy and not a loop.

### WHAT I CHANGED, AND WHICH VERDICT

`cmd_repro` returned **`2`**. `2` is a code no vocabulary in this tree names. `gatekit.py:60`
declares `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`, and `gatekit.py:94-101` records the
consequence in the past tense for another gate: *"a gate returning 2 -- a code `VERDICT`
deliberately does NOT name -- made `VERDICT[code]` raise `KeyError: 2`, so the runner that
aggregated it CRASHED while reporting on a gate that had answered."* So `2` was not a sixth
verdict; it was a **trapdoor**, already measured to be one.

**IT IS NOW `REFUSED` (3), READ FROM `gates/gatekit.py` BY PATH, NOT RETYPED.**
`differ.gatekit()` loads the module that owns the table and returns `gk.REFUSED`. Retyping `3`
would be a second copy of a table that has a generator — the defect `artefacts_ok()` and
`checks/no-txt.py` were each fixed for, one level apart.

Why `REFUSED` and not `FAIL`: `FAIL` (1) is what `cmd_repro` returns when it DID take both runs
and they differed — a measurement. Reaching the bound means a healthy run to snapshot was
absent, so the second measurement was never taken and nothing was determined about
reproducibility: *a precondition was absent*, which is `REFUSED`'s own definition. Not `SKIP`
(the run executed, repeatedly, and produced verdicts), not `DEAD` (it emitted complaints), and
never 0 — a gate that exits 0 having measured nothing is worse than no gate.

### THE PLANT THAT PROVES THE BOUND IS REACHABLE

`repro 1` — `wait=1`, so the bound is one attempt:

```
.venv/bin/python checks/bounded.py --mb 2048 .venv/bin/python checks/differ.py repro 1

WITHIN-LIMITS                     <- verdict TOKEN, not rc
# run A: run 1 summary was NOT healthy -- waiting: expect-moved=3 (expected 0); graphs-agree=31
#   (expected 34); byte-identical=20 (expected 34); stable-pairs=4 of 5 (expected 5 of 5);
#   stable-failed=1 of 5 (expected 0 of 5); oracle-selfcheck=# ORACLE SELFCHECK: FAIL
#   (expected # ORACLE SELFCHECK: OK); census-rc=rc=1 (expected rc=0)
# run A: no healthy run in 1 attempts, 366s spent (ceiling 30s of sleep) -- this is NOT a measurement
REPRO: REFUSED -- no healthy run A in 1 attempt(s), so the SECOND MEASUREMENT WAS NOT TAKEN.

bounded.py rc=3,  peak-RSS=956 MB (ceiling 2048),  366s
```

**It exits 3.** Same tree, same artifacts, same seven complaints reproduced inside a fresh run —
so the seven are not an artefact of a stale summary. Before the change this path returned 2.

I also added `clean_run`'s wall clock to the refusal line, so a caller can now tell `TIMED-OUT`
from `REFUSED` without re-deriving the formula. **The ceiling is not reduced**: `--seconds`
remains the budget and this only makes the two distinguishable.

## 4. TWO RUNS, BOTH VERDICTS, AND WHETHER THEY AGREE

**HEADLINE: the corpus OUTPUT agrees — 241 of 242 artifacts byte-identical, three times over.
The byte-comparison `repro` performs cannot go green, and the reason is not non-determinism.**

`snap()` = sha256 over non-blank lines of every artifact, `differ.py:1012-1017`.

| pair | substrate of each run | artifacts differing |
|---|---|---|
| Oct-18 05:51 vs my run 1 | `9528bb5e` vs `a842e832` | **1 of 242** — `D0-run-summary.txt` only |
| my run 1 vs my run 2 | `9528bb5e`→`a842e832` (mixture) vs `a842e832`→`7f84fd3d` (mixture) | **1 of 242** — `D0-run-summary.txt` only |
| my run 3 vs my run 4 | `7f84fd3d`→`77dc4b11` (mixture) vs `b19c20f8`→`b19c20f8` (clean) | **1 of 242** — `D0-run-summary.txt` only |

Both verdicts, with denominators, from run 4 (`substrate-start == substrate-end == b19c20f8`,
so it is one substrate and not a mixture):

```
graphs=34  graphs-answered=34  graphs-unset=0   graphs-agree=31  graphs-disagree=2
byte-identical=20  not-comparable=0  expect-moved=3
stable-pairs=4 of 5  stable-failed=1 of 5  stable-differ=0 of 5
plants-disagree=7 of 7  cross=1 of 1  selfcheck=# SELFCHECK: OK  conflations=4 of 4
controls=5 of 5  oracle-selfcheck=# ORACLE SELFCHECK: FAIL  census-rc=rc=1
```

`diff summary3.txt summary4.txt` differs on **two lines, both substrate rows, and nothing
else**. Every verdict row is identical.

### WHY `repro-rc=rc=0` IS CURRENTLY UNREACHABLE, STATED PRECISELY

`D0-run-summary.txt` records `substrate-start`/`substrate-end`, and `checks/differ.py` is itself
`SUBSTRATE_INPUTS[0]` — deliberately, per the comment at `differ.py:924`: *"and
`checks/differ.py` itself, which every artifact's driver is"*. So:

* any edit to `differ.py` moves the digest, and `snap()` covers the summary, so **`repro`'s own
  byte comparison includes the file it is comparing with**;
* `gates/corpusverdict-gate.py`'s commit `f62666ad6` extended `substrate_entries()` to
  `SUBSTRATE_WALKS = ("tinybendygrad", "tinygrad")`, so the digest now also covers all 213
  `tinygrad/*.py`;
* other units are editing this tree continuously (measured: the digest moved 5 times during
  this session, and no `.bend` changed — the mover was `checks/differ.py`).

So `repro-rc=rc=0` needs the substrate **frozen for the whole of both runs**. That is a real
precondition, not a workaround, and it is the same thing `substrate_bad()` already reports as
`THE SUBSTRATE MOVED WHILE THE RUN WAS IN FLIGHT`.

**THE NEGATIVE RESULT, STATED HONESTLY: no, two runs of `repro` cannot be made to agree today,
and neither can two `differ.py run`s byte-for-byte, because the summary legitimately records
which bytes produced it. The corpus itself agrees at 241/242.** I did not manufacture a green
`repro-rc` to hide this, and `D0-repro.txt` was NOT written to.

## 5. `D0-repro.txt`'s STALENESS — WHAT I DID, AND WHY NOT TO THE FILE

`D0-repro.txt`: **2026-10-17 01:50:09, 130 bytes, 4 lines** — `repro-files=242`,
`repro-identical=242`, `repro-rc=rc=0`, `d10-transcript=9bfb8517…`. Before this change
`repro_bad()` returned `[]`, so a four-day-old file was serving as the second witness.

**I DID NOT WRITE TO IT.** Writing a fresh value would make the pin green without any
measurement behind it, which is the defect rather than the cure. After `repro 1` refused, its
mtime was re-read: **still `2026-10-17 01:50:09`, 130 bytes** — the refusal writes nothing.

**`gates/corpusverdict-gate.py` DOES NOT COVER IT, AND I AM NOT CLAIMING A ONE-LINE FIX.**
Measured: `grep -c 'D0-repro\|REPRO_ARTIFACT\|REPRO_PINS' gates/corpusverdict-gate.py` → **0**.
That gate's `SUMMARY` is `runs/graphcmp/D/D0-run-summary.txt` (`corpusverdict-gate.py:67`) and
nothing else. So the one-line-that-calls-it **does not exist**, and inventing it would be the
second mechanism the brief forbids.

What I did instead is **ask that instrument's question of the second witness**, using the
instrument's own comparator rather than a new one:

* `cmd_repro` now writes one extra row, `repro-substrate=<substrate_digest()>`, beside the
  verdict it writes;
* `repro_bad()` compares it against `substrate_digest()` — the same function
  `corpusverdict-gate.py:170` calls — and reports **ABSENT** or **STALE**.

It is a **row and not a pin**, and that is the whole distinction: a pin would have to move with
every port edit, which is `pinindep`'s finding and this file's own stated reason for leaving
`substrate` out of `PINS` (`differ.py:895-901`).

**It fires today, on the real file:**

```
repro_bad() -> 1
  repro-substrate ABSENT from D0-repro.txt -- a witness that names no bytes is a measurement
  with no subject, which is `substrate_bad()`'s own rule for a summary and applies here
  unchanged. RE-TAKE it with `checks/differ.py repro`; never hand-edit a value into it
```

This is why the arm is load-bearing rather than theoretical: `cmd_repro` refusing its bound
leaves the OLD artifact in place, so without this row the worst outcome of a refusal is that the
previous success keeps reading as one.

**THE PLANT, ALL THREE HALVES** — a comparator that says STALE for anything is as worthless as
one that never says it, which is why `corpusverdict-gate.py:103-117` plants two digests and the
identical one. `checks/differ.py plant`, plant 5:

```
PASS  5: ***a witness nobody re-took must NOT read as a measurement*** --
          stale digest reds, live digest is silent, absent row reds
          observed: stale=1 live=0 row-absent=1

PLANTS: GREEN (5/5)      rc=0
```

**MEASURED CONSEQUENCE, STATED SO IT IS NOT A SURPRISE LATER:** because `checks/differ.py` is a
substrate input, **editing `differ.py` invalidates the second witness.** That is correct — the
instrument changed, so the measurement must be re-taken — and it is the same semantics
`corpusverdict-gate.py` already applies to the summary.

## 6. PEAK RSS AND RUNTIME PER `bend` INVOCATION

All under `checks/bounded.py --mb 2048`, `SPEC=1`-equivalent env as `differ` sets it
(`DEV=CPU` per the run's own `dev=CPU` row), read from the verdict TOKEN, never `$?`.
`SPEC=1`, `DEV=NULL` inside `cmd_run`'s child (the run's own `dev=CPU` row records the override).

| invocation | token | peak RSS | wall |
|---|---|---|---|
| corpus run 1 | `WITHIN-LIMITS` | 836 MB | 315 s |
| corpus run 2 | `WITHIN-LIMITS` | 1018 MB | 311 s |
| corpus run 3 | `WITHIN-LIMITS` | 957 MB | 257 s |
| corpus run 4 | `WITHIN-LIMITS` | 876 MB | 225 s |
| `repro 1` (bounds one corpus run) | `WITHIN-LIMITS` | 956 MB | 366 s |
| `graphcmp.bend --check-only` probe (`corpusverdict-gate.py`) | `ALL PROOFS CHECK` | 540 MB | 2 s |

`peak-RSS` is the DIRECT child (`differ.py run`) as `bounded.py` sees it; `bounded.py` polls one
process and cannot see the sum, and it says so in its own footer:
`MACHINE: **VIOLATED** -- loadavg 8.4 on 12 cores, swap free 1.65 of 16.00 GiB`.
The census row for the driver, `.agents/slop/peakrss/census.rows`, reads
`748 MB  2s  rc=0  .agents/slop/graphcmp.bend` — my 540 MB agrees in shape. **Never two
concurrent `bend`:** every run here was sequential, and `ps -Ao args | grep bend2/main.ts` was
checked before each read of `runs/graphcmp/` (it returned rc=1, i.e. no live `bend`, before every
artifact read quoted above).

## 7. GIT

`git fsck` and `git show --stat`: see the commit message of the commit carrying this file.

**A SHARED-INDEX SWEEP HAPPENED TO ME, MEASURED.** While my `checks/differ.py` edits sat
uncommitted, a concurrent unit's bare commit **`f62666ad6`** swept them in:

```
git show --stat f62666ad6
 .agents/TODO.md  |  27 ++++++++++
 checks/differ.py | 162 +++++++++++++++++++++++++++++++++++++++++++++++++++----
```

2 paths, both of which that unit had touched — `checks/differ.py` is in my grant and evidently
in theirs. `git diff HEAD -- checks/differ.py` is empty; my markers are in HEAD
(`REPRO_SUBSTRATE` 13, `gk.REFUSED` 2, `def gatekit` 1). **Nothing was reverted or lost** — this
was the `IN-ARM` half of the hazard, not the destructive half — but **my 144 added lines are
attributed to a commit message that describes only the `tinygrad` walk.** Not amended, per
`AGENTS.md`; this report and the follow-up commit name it.

Two more consequences of the armed default index, both measured: `git diff` with no `HEAD`
compares the working tree to the **stale index**, not to `HEAD`, and reported 151 insertions
where the true diff against `HEAD` was 0 — `checks/index-arm-gate.py` reads
`INDEX-ARM REFUSED ... 68 path(s) a bare 'git commit' acts on RIGHT NOW (29 deletion, 39 stale,
0 foreign addition)` and `The tree is fine; the TOOL is pointed wrong`.

## 8. FOUND BUT NOT DONE

1. **`corpusverdict-gate.py` covers only the first witness.** 0 mentions of the second. Its
   `control()` is the exact mechanism my arm reuses and it is not mine to extend — not done,
   named here.
2. **`corpusverdict-gate.py`'s own docstring is now stale.** It asserts `settled()` answers
   `SOME PROOFS FAIL` because `graphcmp.bend:791` builds `O.OpsGROUP{}` and
   `tinybendygrad/uop/ops.bend` declares no such constructor. Measured today: its own `bend` row
   reads `token=ALL PROOFS CHECK rc=0`. The substrate settled at `ops.bend` mtime
   **2026-10-18 05:14:37**. Not mine to edit — named.
3. **I caused an 8th complaint myself.** `checks/differ.py` is `SUBSTRATE_INPUTS[0]`, so editing
   it mid-run made runs 1, 2 and 3 read `substrate-start != substrate-end`, and `unhealthy()`
   returned 8 with `THE SUBSTRATE MOVED WHILE THE RUN WAS IN FLIGHT`. That is
   `substrate_bad()` working. Run 4 was clean (start == end) and is the one quoted in §4.
   **Runs 1-3 are mixtures and are NOT evidence of reproducibility**; §4's conclusions rest on
   run 4 plus the 241/242 agreement, which holds across all three pairs regardless.
4. **The seven complaints are NOT fixed.** They are four port defects (§2) and the port is not
   my grant. I did not re-pin `graphs-agree`/`byte-identical` down to 31/20 — that is deleting
   the defect the complaint names.
5. **`D2-bytediff` shows 14 graphs differing on node ids and emission order only.** Whether the
   canonicaliser or the emitter is at fault is a port question; I characterised it and stopped.
6. **`checks/differ.py run` is still UNGATED** (`corpusverdict-gate.py` measures this from
   `cmd_run`'s own source: `run.gated … verdict=UNGATED`). Never run it blind; I ran it
   deliberately, four times, under `bounded.py`, with a snapshot taken after each.
7. **`repro`'s byte comparison includes the file doing the comparing.** `snap()` covers
   `D0-run-summary.txt`, which records `substrate-*` over a population containing
   `checks/differ.py`. A `repro` run is therefore a measurement of a substrate that includes the
   measurer. Not changed — narrowing `snap()` would weaken the gate — but it is a real circularity
   and it is why `repro-rc=rc=0` is unreachable while this file is being edited.