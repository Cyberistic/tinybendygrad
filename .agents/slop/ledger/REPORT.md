# LEDGER / DIARY — the class, by discovery, and the falsifier

**TREE** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad` · **HEAD** `7ad97ccbcbfdd422133e29872f9039f9eb7938e3`
**POPULATION** `git ls-tree -r HEAD`, 6510 paths. **PYTHON** `.venv/bin/python` (3.12). **NO `bend` RUN.**
**DISCOVERY** `git ls-tree -r HEAD`, NEVER `git ls-files` (the index has reset 6+ times).

Every number below carries the rule that produced it, per `pairs`.

---

## 0. WHAT IT CANNOT SEE, FIRST

1. **A DETECTOR CANNOT SEE A WRITER IT DID NOT RUN.** `runit.py` answers "did THIS process read and
   write this file". It is blind to a run that did not happen, to an instrument invoked as a
   subprocess with a different interpreter, and to writes made by anything other than `open()`
   (a `rename(2)` over a ledger is invisible to `sys.addaudithook`; no file in this tree does
   that today, but the detector would not know).
2. **IT CANNOT SEE THE NON-PYTHON WRITERS.** The hook is CPython's. Every writer found here is
   Python; a `bend`, `node` or shell writer of a ledger is not observed. **The population of
   diaries in this tree is therefore a LOWER BOUND, and the bound is "written by `.venv/bin/python`".**
3. **IT CANNOT SEE A DIARY WRITTEN BY A *DIFFERENT* PROCESS THAT IS STILL A DIARY.** `citation-gate`
   writes only what a *previous* run measured, so its append is monotone; but a writer that shells
   out to itself would produce `PIN` here and still launder. The measurement is a lower bound on
   self-reference, not a proof of its absence.
4. **A PIN IS NOT PROVEN BY `PIN`.** `PIN` means "this run did not write it". It says nothing about
   whether the file is correct — see §3, where a baseline that is wrong **and present** goes green.

---

## 1. THE CLASS, BY DISCOVERY — THREE FILES, THREE PAIRS OF `file:line`

Population: data paths **written by tracked code**, found by the tree's own write sites
(`discover.py`, `WRITE_SHAPES` at `:27-34`), then confirmed by **running** each instrument under a
CPython audit hook (`tracesite/sitecustomize.py`) that records every `open()` **with its mode**.

| # | file | WRITES | READS | same process? | verdict |
|---|---|---|---|---|---|
| 1 | `gates/gates-pop.ledger.tsv` | `gates/gates-pop.py:646` (`write_ledger`), `:549` (mode `w`) | `gates/gates-pop.py:617` (`read_ledger`), `:535` (`read_text`) | **YES**, in `--ledger write` (the **default**, `:1006`) | **DIARY-REWRITE** |
| 2 | `checks/citation-gate.ledger.tsv` | `checks/citation-gate.py:219` (`open(HIST,"a")`, mode `a`) | `checks/citation-gate.py:134-137` | **YES**, every run | **DIARY-APPEND** |
| 3 | `gates/indexread-baseline.rows` | `gates/indexread-gate.py:193` (`BASELINE.open("w")`, mode `w`) | `gates/indexread-gate.py:170` (`read_text`) | **YES**, under `--write-baseline` (`:188`) | **DIARY-REWRITE** |

**#1 and #3 are the same pair in both directions of the same binary — mode is the discriminator.**
Measured on the live tree, `.venv/bin/python .agents/slop/ledger/runit.py <cmd>`:

```
gates/indexread-gate.py            -> read 806, wrote 0   DIARY COUNT 0     [PIN]
gates/gates-pop.py --ledger check  -> read 2053, wrote 0  DIARY COUNT 0     [PIN]
gates/gates-pop.py --plant         ->  DIARY-REWRITE .../gates-pop.ledger.tsv modes=['w']
gates/indexread-gate.py --write-baseline -> DIARY-REWRITE gates/indexread-baseline.rows modes=['w']
checks/citation-gate.py            -> DIARY-APPEND   checks/citation-gate.ledger.tsv modes=['a']
```

**A RUN MUTATES THE TREE. MEASURED, NOT INFERRED.** `checks/citation-gate.py` took
`checks/citation-gate.ledger.tsv` from **578 to 588 rows** in one run. It is a tracked file. I
restored it from `git cat-file blob HEAD:…` and verified byte-identity (`cmp`).

**AND IT RE-DIRTIED ITSELF. MEASURED A SECOND TIME, AND THIS ONE IS THE STRONGER FACT.** After that
verified restore to 578, the file returned to **588** with the *same ten quote-shaped rows* my run
had produced — and I did not re-run the instrument. **A CONCURRENT UNIT RAN IT.** So the ledger is
being rewritten in place by ordinary use, by a party that did not mean to, at a moment when no gate
is looking. **`gates/gates-pop.ledger.tsv` did the same: 127 -> 129 rows** (`tn_ceil_floor`,
`tn_isnan` added) between two of my commands, with `--ledger check` and `--plant` both verified to
write it **0** times. **I DID NOT RESTORE THAT ONE — clobbering a concurrent unit's live state to
satisfy my own bookkeeping would be the larger harm.** The tree's population also moved under me
(`indexread` `POPULATION 803 -> 799`) for the same reason.

---

## 2. THE REFRAMING — **"IS ITS WRITER SOMEONE ELSE" IS THE WRONG QUESTION**

The brief asks whether a pin is a *second file* or a *second writer*. Measured answer: **neither.
It is a second MODE.**

- `gates-pop.py` ships a `--ledger check` mode that reads and **never writes** (`DIARY COUNT 0`).
  Same file, same binary, same source line `:617`. In that mode it is a **pin**.
- `indexread-gate.py` has no flag for its pin at all; its default run is a pin
  (`BASELINE 61  NEW 6  -> FAIL`, rc=1) and `--write-baseline` is the diary.

So the property is neither "is it a ledger" nor "is its writer someone else" but:

> **Does the run that IS BEING RUN rewrite the file it consults?**
> A second *file* is neither necessary nor sufficient. A second *mode inside the same binary* is
> what separates #1 and #3 into a pin and a diary.

**This does not rescue any of the three.** It relocates the defect: the pin is not a property of
the artifact, it is a property of **one command line**, and the defect is that nothing records
which command line is the checking one.

---

## 3. THE CONVERSE — **THE ONE FILE EVERYBODY CITES AS "A REAL PIN" IS ALSO A DIARY**
> *"THEN THIS TREE HAS **ZERO** PINS, AND THAT IS THE FINDING."*

`gates/indexread-baseline.rows` is the file `onewalk` held up as the counterexample. **MEASURED:

```
BEFORE:  POPULATION 803  OFFENDERS 67  BASELINE 61  NEW 6
         INDEXREAD FAIL: 6 offender(s)  ->  rc=1

$ indexread-gate.py --write-baseline        # one command, same process, mode 'w'
   INDEXREAD BASELINE-WRITTEN 67
   DIARY-REWRITE gates/indexread-baseline.rows modes=['w']

AFTER:   POPULATION 803  OFFENDERS 67  BASELINE 67  NEW 0
         INDEXREAD PASS: 67 offender(s), all inside the pinned baseline  ->  rc=0
```

**SIX LIVE REGRESSIONS WERE ABSORBED BY ONE WRITE, AND NONE WAS FIXED.** The gate went from
`FAIL rc=1` to `PASS rc=0` with no change to the tree's behaviour. Restored from HEAD and
re-verified: `BASELINE 61  NEW 6  -> rc=1`.

### 3b. AND A **WRONG-BUT-PRESENT** BASELINE ALSO GOES GREEN — A DIFFERENT FAILURE FROM A DIARY

| planted baseline | rows | gate verdict |
|---|---|---|
| truth (HEAD) | 61 | `OFFENDERS 67  NEW 6` -> **FAIL rc=1** |
| **under**-approximating (40 rows) | 40 | `NEW 27` -> **FAIL rc=1** |
| **over**-approximating (61 real + 400 innocent) | 461 | **`NEW 6` -> `NEW 1`** — **absorbed 5 of 6 real regressions** |
| re-pinned by the instrument itself | 67 | `NEW 0` -> **PASS rc=0** |

**THE MECHANISM, at `gates/indexread-gate.py:206`:** `new = sorted(set(found) - base)`. A baseline
row that has **no offender** is never removed and never penalised — `:225-226` PRINTS it as `gone`
and nothing else. **So padding the pin with arbitrary innocent names is a silent suppressor of
regressions**, and the pad names no offender at all. **THIS IS THE FAILURE THE BRIEF ASKED FOR AND
IT IS NOT A DIARY:** it needs no re-pin, no write, no second process — a hand edit is enough, and
the pin is *present* throughout.

---

## 4. THE DETECTOR — AND THE FOURTH CHECK THAT THE TREE DOES **NOT** ALREADY OWN IT

**Checked a fourth time. THE TREE DOES NOT OWN IT.** `grep -rl "addaudithook"` over the tree returns
**exactly one hit: my own `tracesite/sitecustomize.py`**. `grep -rl "DIARY"` over `gates/` `checks/`
returns `checks/wallcheck.py:249,251,617` and `checks/no-txt.py:15` — **every hit is "a row with a
missing date" or "a `.txt` that is a diary entry". Not one is about this.**

**The closest thing the tree owns is `checks/wallcheck.py:175 class Pin`** — *"THE SECOND TREE, IN ONE
PROCESS"*, `git cat-file --batch` — and it is the right mechanism, **used for the wrong subject and
at the wrong altitude**:
- `wallcheck.py:296` `w, p = ck.work(scope), ck.pin.read(scope)` compares **two REVS of the same content**, never "did the run that read this file write it";
- `wallcheck.py:385` the drift check is `git status --porcelain -- tinybendygrad checks` — **its pathspec excludes `gates/` entirely**, so both `gates/gates-pop.ledger.tsv` and `gates/indexread-baseline.rows` are outside its scope;
- `wallcheck.py:391` and it is a **`WARNING`, with no exit code** — which `gates/indexread-gate.py:17`
  itself names as the failure: *"a finding with no exit code is a note, and notes are not run."*

### The instrument: `.agents/slop/ledger/runit.py` + `plants.py` — **5/5 GREEN**

`plants.py` asserts the properties, and each is chosen so a **diff-based** detector passes the first
and fails the rest:

| plant | asserts | result |
|---|---|---|
| 1 | a ledger **another process grew** is read **quietly** — flagging growth would be a change-detector, which `AGENTS.md` calls harmful | PASS `PIN`, 4 rows |
| 2 | **THE FALSIFIER: two runs leave BYTE-IDENTICAL ledgers and get DIFFERENT verdicts** | PASS `bytes_equal=True reader=PIN rewriter=DIARY-REWRITE` |
| 3 | read **and truncate** in one process = a diary | PASS `DIARY-REWRITE` |
| 4 | read **and append** = a **CACHE**, not a diary — it cannot delete what it read | PASS `DIARY-APPEND` |
| 5 | **hook ABSENT -> 0 opens observed**, so `PIN` on a real instrument is a measurement, not an unobserved run | PASS |

**PLANT 2 IS THE FALSIFICATION THE BRIEF DEMANDED.** *"A detector that cannot distinguish 'the
ledger did not move' from 'the ledger was rewritten' is the vacuous-plant class."* Plant 2 makes the
two files **byte-for-byte equal** and demands opposite verdicts. No content comparison can pass it.
The detector reads the **writer**, never the diff.

**THE FALSE-ABLE CONTROL IS PLANT 4, and it is why `--append` is not `--truncate`.** An appending
writer (`checks/citation-gate.py:219`) cannot delete or alter a row it read, so it is **monotone**;
collapsing `DIARY-APPEND` into `DIARY-REWRITE` would be a false positive on the one ledger in this
tree that genuinely grows. A detector that flagged it would be a change-detector.

---

## 5. CAN A LEDGER CARRY A CEILING? — **NO. ONLY A CONSUMER THAT WALKS TWICE CAN.**

MEASURED, from `gates/gates-pop.ledger.tsv`'s own header (`head -1 | tr '\t' '\n'`):

```
path  reason  root_const  asserts_root  on_root
```

**There is no count column and no bound anywhere in the schema.** A ledger row is a *membership*
claim (`this path is in the population`); a ceiling is an *inequality* over a cardinality. **A
DIFF-STRUCTURED LEDGER CANNOT EXPRESS `N <= K`**, because its only operation is set difference, and
set difference has no order and no magnitude.

**THE TWO ASKING CONSUMERS ARE ASYMMETRIC, and the brief's asymmetry is CONFIRMED WITH CORRECTED
LINE NUMBERS** (the brief cited `hooks/run.py:130` and `gate-surface.py:212`):

| consumer | file:line | walks twice? | carries a ceiling? |
|---|---|---|---|
| `hooks/run.py` | **`:166`** `print(f"POPULATION: gates-pop.discover() -> {len(entries)} entries, {len(libs)} modules")` | **NO** | no baseline, no pin — an absolute count |
| `gates/gate-surface.py` | **`:212`** `walk_control()` (called `:337`) | **YES** — a second `os.walk`, deliberately, as a labelled CONTROL (`:213-218`) | yes: `only_walk = sorted(control - disc)`, `:340` |

**`walk_control` IS NOT A CEILING EITHER — IT IS A CONTROL, AND ITS OWN DOCSTRING SAYS SO**
(`:216-218`: *"It is never used to decide what is a gate; two instruments holding two lists have no
authority over each other"*). So the honest answer to the brief's question is sharper than
"delete `walk_control` and the pair is silently wrong":

> **DELETE `walk_control` AND NOTHING IS SILENTLY WRONG — IT IS ALREADY A PRINT-ONLY CONTROL, NOT
> A CEILING. THE CEILING IS MACHINE-READABLE IN **0 PLACES** AT THE OWNER *AND* IN 0 PLACES IN
> EITHER CONSUMER.** `gate-surface.py:341-345` prints a difference and moves on. **THE REAL DEFECT
> IS NOT THE MISSING CEILING BUT THAT `hooks/run.py:166` IS THE INSTRUMENT THAT *RUNS THE GATES*
> AND IT PRINTS A BARE COUNT WITH NO BASELINE — SO THE RUNNER IS THE ONE NOT LOOKING.**

**AND THE LEDGER SNAPSHOTS ONE PROJECTION OF A TWO-TUPLE POPULATION.** `discover()` returns
`(entries, libs)` (`gates/gates-pop.py:325-326`). The ledger loop at **`:587` iterates `entries`
ONLY**; `libs` is counted in the print at `:585-586` and never given a row. MEASURED on the
committed ledger's `reason` column: `110 py-main`, `15 sh-selfref`, `2 sh-dispatch`, and
**0 `py-lib` rows**. Meanwhile `gate-surface.py:338-339` unions `entries | libs` into its
population. **So a new `py-lib` moves `gate-surface` and `hooks/run.py:166` and DOES NOT MOVE THE
LEDGER AND IS NOT REPORTED BY CLAUSE III** — `onewalk`'s finding, confirmed.

**AND IT ALREADY HAPPENED, UNREPORTED.** The on-disk ledger carries **127 rows; HEAD carries 121**
(6 added: `tn_and_or_xor`, `tn_fdiv_mod`, `tn_lshift_rshift`, `tn_maximum`, `tn_relu`, `tn_relu6`).
A `--ledger check` run then printed **`0 added, 0 gone, 0 changed (127 -> 127)`** and
**`no movement: the population is STABLE`** — because it read the file a prior default-mode run had
already rewritten. **THE DIFF REPORTED STABILITY ON A POPULATION THAT HAD MOVED.**

---

## 6. THE COST — HOW MANY "GUARANTEES" ARE DIARIES?

Going through the numbers the project has been relying on:

| number | who WRITES it | who can move it | diary? |
|---|---|---|---|
| `graphs=34`, `graphs-unset=0`, `graphs-answered=34` | **nobody at run time** — `checks/differ.py:240-261` is a **source-code dict literal** `PINS`, and a Python process does not rewrite its own `.py` | a **commit** | **NO — a real pin** |
| `graphs-agree=32`, `byte-identical=32` | same | a commit | **NO** |
| `census-rc=rc=0`, `selfcheck=# SELFCHECK: OK` | same | a commit | **NO** |
| — *but* | every one of those pins reads `runs/graphcmp/D/D0-run-summary.txt`, **which the same run writes** (`differ.py:386, :400`) | the run itself | **the FILE is a same-run product; the PINS are not.** Already owned: `differ.py:1191-1193` and `.agents/slop/pinindep/REPORT.md` — *"the DENOMINATOR IS 1, NOT 17"* |
| `{reached}/{declared} verdicts reached` (`gates/gate-surface.py:457`) | **nobody** — computed live from plants the run executes | the run, freely | **NO ledger, but NO pin either** — a bare count, like `hooks/run.py:166` |
| **the `127`-row ledger** | `gates/gates-pop.py:646`, same run it reads at `:617` | the run itself | **YES — DIARY-REWRITE**, and it has already absorbed 6 gates unreported |
| `checks/citation-gate.ledger.tsv` | `checks/citation-gate.py:219`, same run it reads at `:134` | the run itself (+10 rows measured) | **YES — DIARY-APPEND** (monotone) |
| `gates/indexread-baseline.rows` | `gates/indexread-gate.py:193`, same run it reads at `:170` | `--write-baseline`, or a hand edit | **YES — DIARY-REWRITE**; `FAIL rc=1` -> `PASS rc=0` measured |

### THE ANSWER, AND IT IS NOT "THEY ARE ALL DIARIES"

**IT IS A CLEAN SPLIT, AND THE SPLIT IS THE FINDING:**

> **A PIN LIVES IN SOURCE. A DIARY LIVES IN A FILE.**
> `differ.PINS` is a dict literal in a tracked `.py`: the run cannot rewrite it, so `graphs=34`,
> `graphs-agree`, `byte-identical` and `census-rc` are **four genuine pins** and the corpus numbers
> this project has been quoting are **sound**. Every number living in a **data file** is a diary:
> **3 of 3**, including the one file the tree held up as its counterexample.

**SO THE TREE HAS ZERO PINS IN ANY FILE — AND THAT IS PRECISELY WHY THE FOUR SOURCE-CONSTANT PINS
ARE THE ONLY ONES LEFT.** The lesson is not "ledgers are bad". It is: **a pin is safe only because
it is in code, and code is the one place a run cannot reach.**

---

## 7. WHAT I DID **NOT** DO, AND WHAT IS STILL RED

- **I did not commit, `git add`, `amend`, rebase, or `@` anyone.** No index operation.
- **I restored the two files MY OWN RUNS mutated and verified byte-identity against the HEAD blob:**
  `gates/indexread-baseline.rows` (61 rows, `cmp` clean — verified again at the end of the session).
  `checks/citation-gate.ledger.tsv` was restored to 578 and `cmp`-verified, then **re-dirtied to 588
  by a concurrent unit** (§1) — I left it alone rather than clobber their run.
  `gates/gates-pop.ledger.tsv` was already drifted from HEAD (127 vs 121) **before** I started;
  `--ledger check` and `--plant` both wrote it **0** times, verified by sha256.
- **`gates/indexread-gate.py` IS RED AND WAS RED BEFORE I STARTED**: `OFFENDERS 67  BASELINE 61  NEW 6` -> rc=1. I did not cause it and did not fix it.
- **NO INSTRUMENT IN THIS TREE CONSUMES `runit.py`.** It is a measurement, not a gate; promoting it to one is a separate decision that touches `gates/gate-surface.py` and `hooks/run.py`, which this unit does not own.
- **STALE CITATIONS CORRECTED:** the brief's `hooks/run.py:130` is `:166`; its `gate-surface.py:212` is correct. `hooks/run.py` lives at **`.agents/slop/hooks/run.py`**, under a swept tree — it is gone from the tree's own gates and would be deleted by a `sweep.py` pass, which is a gate's input under `.agents/slop/` (the exact defect `AGENTS.md` documents for `.agents/slop/schedule-bodies/sb-oracle.py`).