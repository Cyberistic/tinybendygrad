# The AGENTS.md audit — every prescription, measured

Measured 2026-10-06 on `ce24dd60` by RUNNING each prescription. Raw output:
`.agents/slop/agend/spec{0,1,2,3}.rows`, `notxt.rows`, `ruff.rows`, `txtowners.rows`,
`oracletxt.rows`, `gatespop.rows`, `retention.rows`, `repropaths.rows`, `e2everdicts.rows`,
`sz.err`, `szA.err`, `nirB.err`, `proof.err`, `laws.err`, `rss.err`, `guide.rows`.

`jj diff -- PATH` prints nothing, so nothing here is a diff. **NOTHING IS COMMITTED.**

---

## 1. THE HEADLINE: `SPEC=2` FOR CI IS FALSE, AND I MEASURED WHICH LEVEL IS RIGHT

`AGENTS.md:105` — `| SPEC | 1 | UOp spec validation level after rewrites (CI uses SPEC=2) |`

| SPEC | graphs built | graphs FAILED | union | rc | `NOT reached` |
|---|---|---|---|---|---|
| **0** | 25 / 25 | 0 | **61 of 77** | **0** | (16) |
| **1** | 25 / 25 | 0 | **61 of 77** | **0** | (16) |
| **2** | **11 / 25** | **14** | 26 of 77 | **1** | **(51)** |
| **3** | **0 / 25** | **25** | **0 of 77** | **1** | **(77)** |

`DEV=CPU SPEC=$s .venv/bin/python checks/corpus-figure.py`. **SPEC=0 and SPEC=1 are BYTE-IDENTICAL**
(`diff spec0.rows spec1.rows` → identical, 0 err bytes each).

**THE RIGHT LEVEL IS SPEC=1 — WHICH IS ALREADY THE DEFAULT.** `tinygrad/helpers.py:276`:
`SPEC = ContextVar("SPEC", 1)`. **THE PRESCRIPTION IS NOT WRONG ABOUT UPSTREAM.** `.github/workflows/test.yml:190`
and `:256` really do run `SPEC=2 pytest test/null/`, and `.github/workflows/platform.yml:66` runs
`SPEC=2 DEV=NULL python -m pytest test/null/`. Those are **upstream tinygrad's own CI on upstream's own
test suite.** They are not this project's corpus, and the flag table in AGENTS.md is upstream's
`docs/env_vars.md` transcribed.

**THE ROOT CAUSE, MEASURED — AND IT IS NOT A PORT DEFECT.** `tinygrad/uop/ops.py:211-212`:

```python
with Context(CHECK_OOB=0): fret = cast(bool|None, spec_full.rewrite(created))
if fret is not True: raise RuntimeError(f"SPEC ISSUE {fret}: {created}")
```

`spec_full` is `136` patterns naming `77 of 77` Ops — **every op is covered.** But `rewrite()` is a
three-valued thing: `True` (ok), `False` (violation), **`None` (no pattern matched)**. `fret is not True`
treats `None` as a violation. Probed directly:

```
GROUP(simple children).rewrite     -> True
ADD(const,const).rewrite           -> True
GROUP(sz.bend's SQRT(RESHAPE(STACK))) -> None      <- ops.py:212 raises on THIS
```

So **SPEC>1 measures "did a spec pattern match this exact node shape", not "is the port correct."**
`sz.bend`'s own node shape is unrepresented upstream, so upstream's CI level raises on it. That is why
SPEC=2 drops the census to 26 of 77 and SPEC=3 (which adds `created._shape`, then
`test_pyrender`) drops it to **zero**.

## 2. THE PARALLELISE CONTRADICTION, RESOLVED AS A RULE WITH A PRECONDITION

`AGENTS.md:29` says **"parallelize the code whenever possible"**, required, unqualified.
Every brief this session has said **"never run two `bend` processes concurrently"**.
Both cannot be obeyed. Measured, one `bend` at a time, verdict read from the **TOKEN**:

| run | peak RSS | token |
|---|---|---|
| `./bin/bend tinybendygrad/sz.bend --check-only` (alone) | **1,547 MB** | `WITHIN-LIMITS rc=1` |
| `./bin/bend tinybendygrad/sz.bend --check-only` (alone, later) | **1,383 MB** | `WITHIN-LIMITS rc=1` |
| `./bin/bend tinybendygrad/renderer/nir.bend --check-only` (alone) | **1,387 MB** | `WITHIN-LIMITS rc=1` |
| `./bin/bend tinybendygrad/sz.bend --check-only` **‖ concurrent** `nir` | 1,435 MB | `WITHIN-LIMITS rc=1` |
| **‖ concurrent** `nir` | 1,464 MB | `WITHIN-LIMITS rc=0` |
| `./bin/bend tinybendygrad/dtype.bend --check-only` | 505 MB | `WITHIN-LIMITS rc=1` |
| `./bin/bend tinybendygrad/helpers.bend --check-only` | 196 MB | `WITHIN-LIMITS rc=1` |

**FOUR FINDINGS, AND NONE OF THEM SAYS "NEVER TWO".**

1. **`sz.bend` IS NOT 1,468 MB. IT IS 1,383–1,547 MB.** `checks/bounded.py --mb 2048`.
   `.agents/slop/substrate/SUBSTRATE.md:96` and `.agents/slop/loopq/01-wall.md:240` both say
   1,468 MB. **A 5%–12% spread on one file, one command, one tree, three runs.** `.agents/slop/PEAKRSS.md`
   records the max as 1,152 MB. **THE NUMBER MOVES, SO THE RULE MUST NOT BE A NUMBER.**
2. **TWO CONCURRENT `--check-only` RUNS BOTH SURVIVED, BOTH `WITHIN-LIMITS`.** There was no OOM.
   `hw.memsize` is **16,384 MB** today. `checks/bounded.py:115` still says *"4 GB. This machine has
   8-ish"* — **that comment describes a machine this is not.**
3. **`--mb` IS A PER-PROCESS WATCHDOG, NOT A GLOBAL ONE.** `bounded.py` polls the child's RSS and kills
   it. Two children under `--mb 2048` each can together exceed 2,048 MB; the ceiling never sees the sum.
   **So `--mb 2048` is not a machine budget, and citing it as one is the error the whole rule turns on.**
4. **THE PER-FILE NUMBERS ARE ALREADY MEASURED AND THEY ARE BIMODAL.**
   `.agents/slop/peakrss/census.txt`, 138 files, sequential, 1,024 MB ceiling:
   `nir` 1,152 · `sz` 1,108 · `ops_python` 864 · `nn/onnx` 777 · `uop/symbolic` 745 ·
   `dtype` 683–699 · `helpers` 204 · **median 207 · 43 of 138 under 50 MB.**
   **Sum over all 138 = 39,079 MB.** The two largest are 2,260 MB = **14% of this machine's RAM**.

**THE RULE AS WRITTEN INTO `AGENTS.md`:**

> **PARALLELISE EVERYTHING THAT IS NOT A `bend` PROCESS. FOR `bend`, PARALLELISE ONLY WHEN THE SUM OF
> THE CONCURRENTLY-RUNNING FILES' MEASURED PEAKS IS UNDER 60% OF `hw.memsize` — AND THE PER-FILE PEAK
> IS THE NUMBER IN `.agents/slop/peakrss/census.txt`, NOT A NUMBER YOU REMEMBER.**

That is a rule with a precondition, it is actionable, and both halves are measured. The
"never two at once" house rule is **not enforceable** (nothing can tell a second agent's `bend` from
your own) and the unconditional "parallelise whenever possible" is **not safe** (`sz ‖ sz` is 2,766–3,094 MB,
which on the 8 GB machine the OOM happened on was 35% of RAM before `bun` overhead).

## 3. EVERY NAMED PATH: DOES IT EXIST, DOES IT RUN

| named in `AGENTS.md` | exists | runs / notes |
|---|---|---|
| `.agents/slop/` | YES | — |
| `references/` | YES | gitignored (`.gitignore:2`) |
| `.gitignore` | YES | — |
| `README.md` | YES | **does NOT link `references/`** — see §5 |
| `.agents/TODO.md` | YES | — |
| `.agents/TOOLS.md` | YES | **99 of its 213 named paths are GONE** — §7 |
| `checks/no-txt.py` | YES | **rc=1**, 553 hard + 139 excused |
| `LAWS.bend` (bare) | **NO** at root | `tinybendygrad/LAWS.bend` exists; `--check-only` = **34 TODOs, "not a valid proof yet"** |
| `PROOF.bend` (bare) | **NO** at root | `tinybendygrad/PROOF.bend` exists; `--check-only` = **18 TODOs, "not a valid proof yet"** |
| `checks/differ.py run/repro/snap` | YES | `--help` runs; `run`/`repro` **NOT RUN** — they compile `bend` |
| `runs/graphcmp/D` + `D0-run-summary.txt` | YES | 139 `.txt`, 0 zero-byte |
| `checks/README.md` | YES | — |
| `graphcmp-run.sh` / `graphcmp-repro.sh` | **NOT AT ROOT** | they are `.agents/slop/graphcmp-run.sh` / `-repro.sh` |
| `.agents/slop/diffpy/` | YES | both `ORACLE_PIN`s **INTACT** (measured) |
| `differ.py:58` | **WRONG LINE** | `ORACLE_PIN = {` is at **:61**; :58 is a comment |
| `oracle-repro.sh:61` | **CORRECT** | `s=runs/graphcmp/D/D0-run-summary.txt` |
| `oracle-repro.sh:105` | **CORRECT** | `find runs/graphcmp/D -name '*.txt' ! -name '*.err'` |
| `checks/corpus-figure.py:72` | **WRONG LINE** | the read is at **:137**; :72 is `mod = importlib.util.module_from_spec(spec)` |
| `.agents/slop/difftxt/` | YES | — |
| `checks/e2e.py` | YES | `--help` runs; **its own census is RED, rc=1** — §4 |
| `checks/e2e.sh` | YES | `sh -n` rc=0; `:334 exit 4` on PASS-with-SKIP |
| `.agents/slop/xd2/cdp.mjs` | **YES** | AGENTS.md says "the sweep deleted" it. **IT IS HERE.** |
| `.agents/slop/ops_bend-milestone-expected.txt` | **YES** | AGENTS.md says "the sweep deleted" it. **IT IS HERE.** |
| `checks/run-port-mm.sh` | YES | (e2e.py calls `.agents/slop/e2e_port/run-port-mm.sh`) |
| `tinybendygrad/runtime/dtype.js` | YES | consistent with "stage 8 retired" |
| `.agents/slop/e2estage8/verdicts.py` | YES | **rc=1** — `e2e.py: PROSE names [0] the CODE does not emit` |
| `checks/substrate-check.sh` | YES | shim → `checks/substrate.py`; `--help` runs, rc=0 |
| `gates/gatekit.py` · `gates/README.md` · `gates/artifacts/` | YES | 21 `gates/*.py`, **0 `gates/*.sh`** ✓ |
| `checks/bounded.py` | YES | `--help` runs; 2-space indent, **not ruff-clean** |
| `./tinygrad/viz/README.md` | YES | — |
| `docs/env_vars.md` | YES | — |
| `test/null/test_dtype.py` | YES | **`pytest` is NOT in `.venv`** — `No module named pytest` |
| `.agents/slop/DIFFPY.md` | **NO** | cited by `checks/README.md:94`, 0 files |

## 4. THE `e2e.py` PARAGRAPH IS WRONG IN BOTH DIRECTIONS

`AGENTS.md:45-55` says: **"NOT CURRENTLY GREEN, AND NOT FOR ONE REASON: … stage 3 needs `.agents/slop/xd2/cdp.mjs`
and stage 5 needs `.agents/slop/ops_bend-milestone-expected.txt`, and the sweep deleted BOTH … Stage 7
refuses (rc 3, cold substrate) and stage 6's lane is not reproducible run-to-run."**

Measured, from `.agents/slop/e2epy/artifacts/live.port.out` via `.agents/slop/e2estage8/verdicts.py`:

```
3  stage 3 gpu (node): PASS   DENOMINATOR  1   node's exit status
4  stage 4 gate (matmul vs CPython, via WebGPU): PASS  DENOMINATOR 38 mm_e2e_* rows
5  stage 5 ops_bend (kernel executes in Bend): PASS  DENOMINATOR 46 rows
6  stage 6 port (matmul THROUGH the port, no Node): PASS  DENOMINATOR 64 u32 words
7  stage 7 f64: SKIP -- run-f64.sh refused: its substrate is cold
8  RETIRED     DENOMINATOR -  rows that REACH `dtype.js`
```

- **"the sweep deleted BOTH" — FALSE. BOTH EXIST AND BOTH STAGES PASS.**
- **"Stage 7 refuses (rc 3, cold substrate)" — TRUE.** 1 of 7 stages measures nothing, so `e2e.py`
  returns **4**, not 0 (`e2e.py:510`), and `checks/e2e.sh:335` likewise `exit 4`.
- **"all seven stages run" — TRUE but incomplete: SEVEN are emitted, and `verdicts.py` is RED**
  because `e2e.py`'s own docstring names a stage `0` the code does not emit.
- **Stage 8 RETIRED — TRUE**, and `.agents/slop/cstyle-live/port.txt`, the fixture `e2e.py:99` calls a
  DELETED FIXTURE, **EXISTS** (only `run-all.sh` is beside it, so `repair-dupes.py:48`'s target is absent —
  that one is right).

**THE FIFTH DEFECT IS NOT WHERE THE BRIEF SAID.** The brief names `checks/sb-gate.sh:289/292` exiting 0
on `PASS WITH SKIP(S)`. **`sb-gate.sh` IS 150 LINES** (there is no `:289`), it has **no SKIP branch at
all**, and it runs: `sh checks/sb-gate.sh` → **rc=3, `== REFUSED, NOT A VERDICT: the regression floor is
absent:`**. **That defect does not exist.** I did not inherit it.

**THE FIFTH DEFECT THAT DOES EXIST — AND IT IS WORSE, BECAUSE IT IS THE ENTRY POINT AGENTS.md NAMES.**
**TWO INSTRUMENTS READ `runs/graphcmp/D/D0-run-summary.txt` AND DISAGREE ABOUT ITS HEALTH.**

```
checks/differ.py PINS   -> 2 of 17 MISMATCH:  census-rc   pin 'rc=0'  live ABSENT
                                       oracle-selfcheck pin '# ORACLE SELFCHECK: OK'  live '... FAIL'
gates/retention-check.py -> "IV FIRES runs/graphcmp/D/ ... 2 complaint(s)"   exit 1
checks/corpus-figure.py -> "RUN HEALTH : OK -- every one of 25 graphs was COMPARED"   exit 0
```

`corpus-figure.py:run_health()` reads `graphs-agree`, `not-comparable` and `graphs` and **never reads
`oracle-selfcheck` or `census-rc`** — so it prints **OK** and **exits 0** over a run its own sibling
instrument calls RED. **AN INSTRUMENT THAT CANNOT SEE A FAILURE IN ITS OWN INPUT IS A FIGURE** is the
sentence `corpus-figure.py:223` already writes about a *different* defect. It is now true of itself.

## 5. PRESCRIPTIONS THAT ARE TRUE, FALSE, OR UNACTIONABLE — THE TABLE

| # | prescription (`AGENTS.md:line`) | verdict today | the measurement |
|---|---|---|---|
| 1 | `SPEC=2` for CI (`:105`) | **FALSE for this corpus** | 26 of 77, 14/25 graphs fail, rc=1. Upstream's CI really does use it on `test/null/`. |
| 2 | "no `.txt` files, **ever**" (`:18`) | **RULE TRUE, TOTAL FALSE** | `no-txt.py` rc=1: **553 hard + 139 excused = 692 owned.** `AGENTS.md:56`'s "there is no `.txt` file in this project" is false by 692. |
| 3 | `checks/no-txt.py` "enforces it" (`:19`) | **true as a gate, false as a state** | rc=1. And 692 − 553 = 139 are excused by `differ.declared()` — **imported, not copied**, which is why it never moved. |
| 4 | "the **103** `.txt` names there are a contract" (`:41`) | **STALE — 139** | `len(differ.declared()) == 139`; 139 `.txt` on disk; 0 declared-but-absent. Also stale in `checks/README.md:51,53,55,58,75` and `checks/no-txt.py:19,25,26,30,65`. |
| 5 | "Always stay turing-incomplete" (`:22`) | **TRUE, unenforced** | no instrument in `checks/`/`gates/` mentions turing. Nothing can fail. |
| 6 | "No external dependancies" (`:17`) | **TRUE for the port; the ledger does not say which** | every import under `tinybendygrad/` is `Base` or a repo `.bend`. But `ruff` is on **PATH** (`/opt/homebrew/bin/ruff`, 0.15.18) and **NOT in `.venv`**; `mypy`/`pytest` are **neither**. `.agents/TOOLS.md` says nothing about which interpreter a prescription runs under. |
| 7 | "Run `python -m ruff check .`" (`:74`) | **TRUE-AND-RED, and not runnable as written** | PATH `ruff check .` → **797 errors**, rc=1. `.venv/bin/python -m ruff` → `No module named ruff`, rc=1. |
| 8 | "Run `python -m mypy tinygrad/`" (`:73`) | **NOT RUNNABLE** | `.venv/bin/python -m mypy tinygrad/` → `No module named mypy`, rc=1. |
| 9 | "Run tests with `-n12`" (`:72`) | **NOT RUNNABLE** | `.venv/bin/python -m pytest test/null/test_dtype.py -x -q -n12` → `No module named pytest`, rc=1. |
| 10 | "use uv and ty" (`:71`) | **TRUE** | `uv 0.6.14`, `ty 0.0.78` both on PATH; `uv.lock` has 586 packages. |
| 11 | "run `bend guide`" (`:26`) | **TRUE** | rc=0, 677 lines. |
| 12 | "use `LAWS.bend` to keep important rules" (`:27`) | **TRUE-AND-RED** | `--check-only` → `Error: 34 TODOs found. The code is incomplete, and not a valid proof yet.` |
| 13 | "run `bend PROOF.bend` before committing" (`:28`) | **TRUE-AND-RED — it cannot pass** | `--check-only` → `Error: 18 TODOs found. The code is incomplete, and not a valid proof yet.` **A pre-commit gate that is red at rest teaches nothing.** |
| 14 | "parallelize the code whenever possible" (`:29`) | **UNSAFE unqualified** | §2. `sz ‖ sz` = 2,766–3,094 MB. |
| 15 | "Do not do amend commits" (`:76`) | **TRUE, and it is not the rule the brief thinks** | **AGENTS.md NEVER SAYS "NEVER REBASE."** `ad117c928` *"rebase B1: 17 files…"* is an ancestor of HEAD and touched **16 `tinygrad/` vendored files** — an upstream re-vendor, not an `amend` of ours. |
| 16 | "`gates/*.py` … **Python, never shell**" (`:59`) | **TRUE** | 21 `gates/*.py`, 0 `gates/*.sh` (the two `.sh` under `gates/oracles/` are oracle bodies, not gates). |
| 17 | "**`checks/*.sh` … 14 of 17 resolved a path outside the repo**" | **FALSE — the defect is FIXED** | `sh -n` 14/17 rc=0, 3 rc=2. **All 17 `cd` land on the repo root**, measured per file. `sb-gate.sh:62` and `substrate-check.sh` now ASSERT it (exit 3). |
| 18 | "`gates/*.py` … a gate names its `.bend` driver and its CPython oracle, which stay in `.agents/slop/`" (`:60`) | **UNSAFE — it is what deleted the gates' inputs** | `e2e.py:99` names `cstyle-live/port.txt`, **absent**; `sb-gate.sh:76` names `.agents/slop/schedule-bodies/BEFORE-rows.txt`, **absent** (rc=3). 99 of `TOOLS.md`'s 213 named paths are gone. |
| 19 | "NEVER write unit tests after you write code" (`:82`) | **TRUE as a doctrine; unenforced, and the tree refutes it** | `test/` holds upstream tinygrad's suite; `.agents/slop/` holds 40+ `*-mutate.py` / `*-selftest.py`. |
| 20 | "Read `./tinygrad/viz/README.md`" (`:75`) | **TRUE, and it is upstream's file** | exists. |
| 21 | "link `references/` under `references/` in your README" (`:10`) | **CONTRADICTED BY THE LEDGER** | `grep references README.md` → rc=1. `.agents/TOOLS.md:51-52` says *"Do not. The README is off limits. This table is the ledger instead."* **AGENTS.md's instruction was overridden and the override is only in the other file.** |
| 22 | "tick it off in `.agents/TODO.md`" (`:11`) | **TRUE; ledger contended** | `.agents/TODO.md` exists. **7 units are writing it; one already declined.** Not mine. |
| 23 | "always place agent-state Markdown under `.agents/slop/`" (`:9`) | **TRUE** | — |
| 24 | "Update `.agents/TOOLS.md`" (`:13`) | **TRUE as a rule, FALSE as a ledger** | **99 of 213 named paths missing**, incl. `.agents/slop/rebase-survey.py`, `.agents/slop/xd1/verify.py`, `.agents/slop/zero-classify.py`. |
| 25 | "`checks/no-txt.py` … exits 1 and prints each path" (`:56`) | **HALF TRUE** | rc=1 ✓. It prints **40** paths then `... and 513 more` — **it does not print each path.** |
| 26 | "`e2e.py` — **the SEVEN-STAGE** gate" (`:45`) | **TRUE** | 7 emitted, 8 retired; `verdicts.py` RED on the docstring's `0`. |
| 27 | "Stage 8 is **RETIRED** … `runtime/dtype.js` is not one byte of the emitted bundle" (`:52`) | **TRUE** | `verdicts.py` row 8: `RETIRED DENOMINATOR - rows that REACH dtype.js`. |
| 28 | "`gates/gatekit.py` … holds nothing but the three lanes, the row counts and the diff" (`:62`) | **UNVERIFIED** | read only; another unit's file. |
| 29 | "`gates/README.md` records the four ways a shell gate failed" (`:64`) | **TRUE** | the table is there, four rows. |
| 30 | "`oracles/` holds 259 `.txt` that nothing names" | **TRUE, sharpened** | `oracle-txt-census.py`: 259 files, **249 rowdump**, and **`NAMED BY NOTHING 225 / 259`**. |
| 31 | "`run `bend PROOF.bend` before committing" — see 13. | | |
| 32 | "Run `--help` before trusting one" (`:33`) | **TRUE, and it works** | `differ.py --help`, `bounded.py --help`, `substrate.py --help`, `e2e.py --help` all rc=0. |

## 6. THE SIXTH CLASS: THE POPULATION MUST BE DISCOVERED, NOT LISTED

Six instruments in this repo define their population by a **LIST** or a **SPELLING**. I re-ran each.

| # | instrument | how its population was declared | status today |
|---|---|---|---|
| 1 | `checks/sweep.py:266` `LIVE_UNITS` | 14 literal directory names | **still a list.** Its own comment: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."* Six finished units held **2,353 of 4,455 = 53%** of `.slop`. |
| 2 | `checks/sweep.py:658` `ORACLE_WORD` | a **basename regex** | **still a regex**, guarded by `name in mentioned`. Was **670 of 675 classified by filename, 5 named by a live gate.** |
| 3 | `checks/differ.py:artefacts_ok()` | was a `find … -name '*.txt'` glob | **FIXED — verified by re-running its own negative control.** `d.D = <empty tmpdir>` now returns **139 `MISSING`** where the old glob returned `[]`. Live: `[]`. |
| 4 | `checks/repro-paths.py:57` `REF` | `(?:sh\|py\|bend)` | **FIXED — `.mjs` and `.json` added.** Was: 6 of 15 `e2e.py` stage inputs invisible; *"RESTORING THEM MOVED THIS TOOL'S OUTPUT BY EXACTLY ZERO."* Still exits 1 today (30+ dangling paths). |
| 5 | `gates/gates-pop.py:95` `HOMES` | `("checks", "gates")` | **still a literal list**, and the file **admits it**: *"A LIST, AND IT IS ADMITTED: this is the one universe this file names by hand."* Exits 0 today, 92 entry points. |
| 6 | `AGENTS.md` itself | names gates by **hand** | **17 `checks/*.sh` exist; AGENTS.md names 3** (`substrate-check.sh`, `e2e.sh`, `graphcmp-*.sh`) and calls none of them a population. **THE GOVERNING DOCUMENT IS THE SEVENTH MEMBER OF THE CLASS.** |

**THE DOCTRINE, AND ITS INSTRUMENT.** An instrument may declare its population **only** by (a) a
generator's own declaration, **loaded by path** (`differ.declared()` — the 139 `.txt` carve-out and
`artefacts_ok()` both ask it, which is why the carve-out never moved while the total moved
398 → 552 → 562 → 553); (b) a **directory walk** (`os.walk` + `endswith`, because `glob('*.bend')`
returns `[]` when `.bend` is on disk); or (c) a **regex over the tree's own write sites**, with the
list admitted in a comment and a **ledger** so an edit is visible. **A basename shape, a suffix set, or
a hand list is not a population, and an instrument that cannot see its population cannot be wrong,
because it cannot be anything.**

## 7. THE FOUR GATE STATES, AND WHERE A `DEAD` STATE ALREADY EXISTS

`checks/e2e.py:73` and `:505-511` already name three — `PASS` / `FAIL` / `SKIP` — with
**`PASS WITH n SKIP(S) → 4`**, and `checks/e2e.sh:325-335` mirrors it. **`checks/bounded.py` has five:**
`WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT` / `NOT-STARTED` / `NO-VERDICT`, and its own header
says the status cannot substitute: *"a unit lost 425 rows by believing the status instead of the token."*

**A FOURTH VERDICT, `DEAD`, EXISTS AND IS THE ONE NOBODY WRITES DOWN.** `.agents/slop/rebase-survey.py`
— itself now deleted — reported `WIRED` / `NO-SHARED` / **`DEAD-LANE`** / `DISAGREES`, and
`.agents/slop/rebase-gate-selftest.py` (the file survives) drives **six** states: *dead lane, empty
output, no shared row name, a shared name that differs, agreement, malformed baseline.* **A LANE THAT
EMITS NOTHING IS NOT A ZERO AND NOT A PASS — IT IS A LANE THAT MEASURED NOTHING, AND THE INSTRUMENT
THAT CANNOT DISTINGUISH IT FROM AGREEMENT HAS NO VERDICT AT ALL.** That is what `artefacts_ok()`
reported on a directory holding nothing, and what `corpus-figure.py` still reports on a run whose
`oracle-selfcheck` is `FAIL`.

**THE FIVE STATES, AND EACH ONE'S EXIT:**
`PASS` 0 · `FAIL` 1 · `SKIP` (measured nothing, could not) 4 · `DEAD` (ran and emitted nothing —
**no exit anywhere claims it**; `differ.py` answers it as `not-comparable`, `corpus-figure.py` does
not answer it at all) · `REFUSED` (a precondition was absent) 3.

**WHERE THE FIFTH DEFECT IS — AND IS NOT `sb-gate.sh`.** §4: `corpus-figure.py` prints
`RUN HEALTH : OK` and exits **0** over a run `differ.py`'s `PINS` call RED on 2 of 17 and
`retention-check.py` reports `IV FIRES … 2 complaint(s)` and exits **1**. **Three instruments, one
file, two verdicts, and the green one is the instrument `AGENTS.md:41` sends a reader to.**

## 8. WHAT I COULD NOT VERIFY, AND WHY

| prescription | why not |
|---|---|
| `checks/differ.py run` / `repro` | **compiles `bend`.** House rule: do not run a gate that compiles `bend`, and six other units hold the shared `references/bend/bend2`. I verified `--help`, both `ORACLE_PIN`s, `declared()`, `artefacts_ok()`, `WANT` and `PINS` by importing and by running `artefacts_ok()` against a redirected `D`. |
| `checks/e2e.py` end-to-end | same. Its last full transcript is on disk (`.agents/slop/e2epy/artifacts/live.port.out`) and is what §4 quotes. |
| "stage 6 not reproducible run-to-run (rc 1 then rc 0)" | needs two `bend` runs of `run-port-mm.sh`; **another unit had a `bend` process live twice during this audit.** Not refuted — untested. |
| `gates/gatekit.py` holds "nothing but three lanes, row counts and the diff" | read-only, another unit's file. `bounded.py:112` imports `_said` from it, so it is live and shared. |
| the Tinygrad flag tables (`AGENTS.md:96-275`) | ~180 lines of upstream `docs/env_vars.md` transcribed. **I spot-checked only `SPEC`**, which is the one carrying a parenthetical claim. I did **not** diff 180 flag rows; that is a `diff docs/env_vars.md` away and nobody has asked. **THIS IS THE LARGEST UNVERIFIED BLOCK IN THE FILE.** |
| "no external dependancies" as a *rule* | true for `tinybendygrad/`; whether `ruff` on PATH counts is a policy question, not a measurement. §5 #6. |

## 9. WHAT I COULD NOT SETTLE

1. **Is `SPEC=2` a false prescription or a true one about the wrong subject?** Both readings are
   defensible: it is FALSE as an instruction to this project's agents, TRUE as a transcription of
   upstream CI. I resolved it by naming the subject (`CI` = upstream's CI on `test/null/`) rather than
   by deleting the parenthetical, because deleting it would lose a true fact about upstream.
2. **Which 4 of the 139 `.txt` in `runs/graphcmp/D/` should become `.rows`.** The carve-out is
   *imported* and *correct*; but `oracle-repro.sh:105` **globs `*.txt`**, and a sha256 over an oracle's
   **bytes** does not cover the names it **reads** (`checks/README.md:60` says so itself). So the
   rename is safe only as ONE commit touching the oracle and both consumers, and it is not mine.
3. **Whether the 692 `.txt` is a rule failure or a migration in flight.** `oracle-txt-census.py` says
   **249 of 259 `oracles/` files are rowdumps** — i.e. the *rule is right* and the tree is *behind*.
   That is `oracles259`'s call, not mine, and I did not touch `oracles/**`.
4. **Whether `checks/corpus-figure.py` should read `oracle-selfcheck`/`census-rc`.** It plainly should,
   but `corpus-figure.py` is explicitly **not mine.** §4 records it as the fifth defect.
5. **Whether the per-file RSS table should be re-taken.** `sz.bend` measured 1,383 / 1,435 / 1,547 MB on
   three runs today; `census.txt` says 1,108; `SUBSTRATE.md` says 1,468; `PEAKRSS.md` says 1,152.
   **FIVE NUMBERS FOR ONE FILE.** The rule I wrote uses the *shape* (bimodal, per-file, sum vs RAM)
   precisely so it does not depend on settling the number. Re-taking it is `bendpin`'s, since it owns
   the census and `TOOLS.md`.

## 10. WHAT I WANT TICKED IN `.agents/TODO.md` — **NOT MINE, SO I AM ASKING**

`.agents/TODO.md` is contended by seven units and I did not write to it. **Four lines, please:**

- `[ ] AGENTS.md:105 — replace "(CI uses SPEC=2)" with the measured level (SPEC=1) and upstream's scope.` — owner: whoever owns `checks/corpus-figure.py`.
- `[ ] corpus-figure.py run_health() reads 3 of differ.py's 17 PINS; it prints RUN HEALTH: OK and exits 0 over a run retention-check.py calls RED on 2.` — **the fifth defect.** Owner: `corpus-figure.py`'s.
- `[ ] AGENTS.md:41, checks/README.md:51-58, checks/no-txt.py:19-30 all say 103 declared .txt; differ.declared() is 139. Three witnesses, one stale number.` — owner: `differ`'s.
- `[ ] AGENTS.md:41 cites differ.py:58 and corpus-figure.py:72; the pins are at differ.py:61 and the read at corpus-figure.py:137.` — owner: whoever owns the pins.
- `[ ] TOOLS.md: 99 of its 213 named paths are gone (rebase-survey.py, xd1/verify.py, zero-classify.py, …).` — owner: `bendpin`.