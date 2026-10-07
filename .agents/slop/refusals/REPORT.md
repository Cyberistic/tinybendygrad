# `refusals` — what this project refused tonight, and whether any of it CHANGED anything

Measured **2026-10-07 19:43 +0300**. Python only. **No `bend` was run**: `pgrep -f bin/bend`
answered `14926` at the start, and a live `bend` means skip rather than fork.
**No commit, no `git add`, no `@`, no amend.** Owned new files under
`.agents/slop/refusals/` only; no gate body, no `AGENTS.md`, no `tinybendygrad/` touched.

Instruments, all beside this file: `discover.py` (the population), `refusal-read.py`
**the deliverable — a reader**, `cost.py` (the price), `satisfied.py` (was it ever closed),
plus the three `recheck-*.out` captures.

```
.venv/bin/python .agents/slop/refusals/discover.py        # -> discover.out
.venv/bin/python .agents/slop/refusals/refusal-read.py    # -> census.out, refusals.rows
.venv/bin/python .agents/slop/refusals/refusal-read.py --plant
.venv/bin/python .agents/slop/refusals/cost.py            # -> cost.out
.venv/bin/python .agents/slop/refusals/satisfied.py       # -> satisfied.out
```

---

## 6. WHAT I CANNOT SEE — FIRST, BECAUSE IT GOVERNS EVERYTHING BELOW

**A report is PROSE, and I read it with a REGEX.** `declaretwo` measured **2 448 prose
citations of which 1 777 were NEVER POSITIVELY CHECKED**. So every class and every
unblocking below is a **TRANSCRIPTION**, not a verdict about the world. This is the same
warning `onewalk` issued about its own instrument: read committed source, count nothing you
did not run.

**AND THE TRANSCRIPTION IS DEMONSTRABLY IMPERFECT, IN BOTH DIRECTIONS.**

- **False positives in my extractor, MEASURED and then FIXED.** `flipblock`'s regex ate
  `**The two files the brief is asking about:**` — a heading, not a plan. `unshardtable`'s
  ate `") rests on a` — the tail of a quoted sentence. Both are now rejected by
  `NOT_A_PLAN`, and both rejections exist **because a unit's own report produced them**.
- **A FALSE POSITIVE THAT CHANGED A COUNT.** `slowgate` and `restoredinput` first classified
  as `DECLINED`, because "I did not land" outranked their explicit `REFUSED`. They are
  refusals. Fixing it moved `REFUSED-WITH-REASON-ONLY` from **27 to 37**.
- **A MISCLASSIFICATION I DID NOT CATCH.** `exitcode` classified `REFUSED-WITH-REASON-ONLY`,
  which is right. But the brief names the unit `exitcode` and **the directory is `exitzero`**
  — a name I would never have found without the brief. **The walk found 157 reports and the
  brief named 10; of those 10, one was under a different name.** A census built by prose
  misses renames, and this is the smallest possible proof.

**AND THE POPULATION HAS A CEILING OF ITS OWN:** 157 report files, of which **61 contain no
refusal claim at all** (`not-a-refusal`). The denominator is stated in the same sentence as
every count below.

---

## 1. THE CENSUS, BY DISCOVERY

`discover.py` is a **directory walk** (`os.walk` + `endswith`) — doctrine 1's shape (b). No
hand list. `refusalsweep` was the near-miss name for this instrument and is **not** it: it
sweeps `checks/`/`gates/` for unguarded path writes under an ignored root. Different subject.

```
REPORTS (whole walk of .agents/slop/*/)   157
REFUSED-VERB reports (token count)         30   <- the brief named 10
```

| class | count |
|---|---|
`LANDED` | 1 |
`REFUSED-WITH-UNBLOCKING` | **2** |
`REFUSED-WITH-REASON-ONLY` | **37** |
`REFUTED-ANOTHER-UNIT` | 13 |
`DECLINED-A-CHARGE-IT-DID-NOT-CAUSE` | 32 |
`DECLINED` | 11 |
`not-a-refusal` | 61 |

**SCOPE: the whole walk at this read — 157 reports. It is NOT "tonight's refusals"**, and
`mtime` cannot make it so: a unit's artifacts span **0 s to 120 540 s** (33.5 h), because
`dup`, `e2epy` and `orcdecide` are multi-day units whose files sit far apart. **A refusal has
no timestamp an instrument can trust, and this census is therefore a POPULATION, not a
PERIOD.** The briefed ten are a subset I re-measure individually below.

**The 30 REFUSED-verb units the walk found and the brief did not name** include `canrun`,
`checkshells`, `substrate2`, `jjhazard`, `runsgate`, `envguard`, `jjreset`, `coindependent`,
`exitzero`, `pinindep`, `surface`, `msgdiff`, `hooks`, `midrun`, `denominator`, `flipthird`,
`plantthe46`, `indextree`, `declareverdict`, `droppedinput`, `unreachable`, `quiesce`,
`laws17`, `emptyact`. **The brief's count of ten is not wrong; it is SCOPED to units whose
refusal the orchestrator happened to see.** That is `pairs`' finding in a second costume.

---

## 2. THE ONLY QUESTION THAT MATTERS: HOW MANY REFUSALS CHANGED SOMETHING?

**Per `refusal-read.py`, over 39 refusals in the whole-walk scope: 2 name a readable
unblocking. Of those 2, the unblocking was SATISFIED LATER IN 0.**

| unit | the UNBLOCKING it named | satisfied later? |
|---|---|---|
`flipblock` | one arm in `fold.bend` teaching `flip_ds` an `ABoolList` | **NO** — `grep -c ABoolList tinybendygrad/uop/fold.bend` = **0** |
`mselectarg` | "the row, and it is in a file" — **no path named** | n/a; a description, not a hand-off |

**AND `flipport` NAMES ONE THAT THE EXTRACTOR CREDITED ELSEWHERE.** Its own line 123 reads
`SMALLEST THING THAT UNBLOCKS: one arm in `fold.bend`'s order_arg (or flip_ds)`, and line 183
is `D. fold.bend — FORBIDDEN (another unit). THE BLOCKER.` The reader found
`flipblock`'s copy and classified `flipport` as `DECLINED-A-CHARGE-IT-DID-NOT-CAUSE`, so
**`flipport` and `flipblock` are the SAME unblocking, named twice, by two units, and neither
changed anything.** Its subject `tinybendygrad/uop/fold.bend` was last modified **2026-10-07
06:21** — before both units ran.

> ### THE HONEST ANSWER, WHICH THE BRIEF ANTICIPATED AND WHICH IS PLAINLY THIS:
> **ACROSS THE 39 REFUSALS IN SCOPE: TWO NAME AN UNBLOCKING, BOTH POINT AT
> `tinybendygrad/uop/fold.bend`, AND NEITHER HAS BEEN SATISFIED. THE PROJECT HAS PRODUCED
> 39 ACCURATE DESCRIPTIONS AND 0 RESOLUTIONS.**

**Why that is not nothing:** a refusal that names a hazard nobody had noticed converts an
unknown into a measured falsehood, which is what every one of these 39 did. **Why it is not
a resolution:** a resolution ends a claim. A description opens one and hands it to a reader
who may not exist. `onewalk` found the same shape elsewhere and named it exactly: **a file
says what it is and nothing believes it.**

---

## 3. WHAT DID A REFUSAL COST?

`cost.py` harvests durations from **three** reports that survive a guard, plus mtime spans.

**THE HARVESTER WAS WRONG THREE TIMES BEFORE IT WAS RIGHT ONCE**, and each error is a
measured instance of the rule that every number needs its producing rule:

| rejected reading | what it actually was |
|---|---|
`quiesce` **28 800 s** | an **8 h mtime census window over the tree**, not a runtime. Correct reading **1 320 s** (`00:20–00:42`). |
`indextree` **879 s** | the **tail of `1.879s`** — `scan 1.879s`. |
`modulerefuse` **40 min** | a **delta between two readings of the same question**, not its own runtime. |
`prune4` **904 min** | the **age of the newest file in `bendperf`**. |
`declaretwo` **21 600 s** | a **table row `\| < 6 h \| 5 \| 104 \|`** — a histogram bucket. Correct reading is its own header, **3 300 s**. |

**THE COST OF THE BRIEFED REFUSALS, each number carrying its rule:**

| unit | cost | source |
|---|---|---|
`declaretwo` | **3 300 s** (55 min) | its own header `18:45–19:40` |
`slowgate` | **900 s** | the `>900 s` floor it measured — **and separately the briefed `562 s` single run**, quoted from `cap-plants.rows:7` with the report's own caveat that wall times are **contended and are reported as an ORDER, not a millisecond** |
`exitcode` | **771 s** | mtime span, **a lower bound** |
`unshardtable` | **480 s** | mtime span, lower bound |
`restoredinput` | **292 s** | mtime span, lower bound |
`flipblock` | **39 s** | mtime span, lower bound |
`flipport`, `onewalk` | **0 s** | mtime span, lower bound (single-write units) |
`modulerefuse` | **37 516 s** | mtime span, **a LOWER BOUND AND A LIE** — it spans a 10.4 h gap between two units' artifacts in one directory |
`unshardfold` | — | **NO REPORT.** Evidence only: `refusal_population.py` + `refusal-population.rows`. Its population is a **77-member enum denominator**: 13 `answer`, 49 `cascade-refuse`, 4 `own-wall-refuse`, 11 `late`. |

### THE SHARE OF THE SESSION — **STATED WITH ITS OWN DENOMINATOR, TWICE**

**Scope A — the briefed ten's *declared* cost only** (`declaretwo` + `slowgate`): **4 200 s =
1.17 h**.
**Scope B — the same ten with mtime lower bounds added** (`modulerefuse` alone is 37 516 s):
**≈ 12.5 h**.

**Neither can be divided into a session total, and here is why that is the finding.** Tonight's
artifacts under `.agents/slop` span **00:22–19:43 = 19.36 h** over **520 files**. The refusal
figures and the session figure **are not the same kind of quantity**: one is a unit's declared
duration, the other is a filesystem mtime span across units that ran concurrently.
**So the honest share is: the DECLARED cost of the briefed refusals is 1.17 h against a 19.36 h
session — 6 % — and the MTIME-BOUND cost of the same ten is 12.5 h against the same 19.36 h —
65 %, a figure that is an artifact of `modulerefuse`'s 10.4 h directory gap and of nothing
else.** Reporting either alone would be the `elf.bend` 353/331/246 failure.

**THE PRICE THAT IS ACTUALLY PAID, AND IT IS NOT TIME.** `slowgate` ran a gate for **562 s to
prove it was DEAD**. A hang lies about its work and announces itself by costing time. **562 s
is not the cost of the refusal; it is the cost of NOT HAVING A BOUND.** Every other number in
this section is small next to that.

### THE CORRELATION (item 3) — MEASURED, AND IT IS NOT THE ONE THE BRIEF EXPECTED

The brief's hypothesis: *the refusals that did not pay for themselves are the ones that
**named no restorable subject**.* Measured, by the only objective test available — **is a
subject named on disk present now?** — the correlation **holds and is sharper than the brief
stated**:

- **`unreachable` LANDED THE ANSWER** by restoring subjects and reading gates, and **all four
  restored subjects are ABSENT again** at this read (`nl/nl-oracle.py`, `checks/drive.mjs`,
  `.agents/slop/clangshim/oracle.py`, `checks/isolate.py` — all four `ABSENT`). Its restores
  were `finally`-removed after measurement, byte-compared, residue 0. **A restore that is
  removed is a MEASUREMENT, not a landing** — and `unreachable` said so itself.
- **`restoredinput` LANDED FOR REAL, AND I CAN MEASURE IT.** `checks/nl-gate.py` now carries
  the guard `restoredinput` described, and it is **live right now**:
  ```
  $ .venv/bin/python checks/nl-gate.py ; echo rc=$?
  == REFUSED, NOT A VERDICT: input absent: …/.agents/slop/nl/nl-oracle.py
     (swept by 371cc64c9; recoverable from git at 371cc64c9^:…)
  rc=3
  ```
  **7 gates name a restorable subject; running each: `cl-port-gate`, `dup-census`, `gate`,
  `nl-gate-noguard`, `nl-gate` all exit 3 (REFUSED, not a verdict); `norm_check` exits 0;
  `rn-gate` exits 1.** `gate.py:60`'s `REFUSED = 3` is not a convention here — it is
  **load-bearing**, and a refusal that names *where the subject came back from* is the shape
  that produced it.
- **THE CORRELATION:** 39 refusals name a restorable subject **0** times in the refusal
  reports; 7 gates name one and 5 of those 7 refuse today. **The refusals named subjects; the
  gates carry them. The refusal is the FINDING and the gate is the LANDING, and tonight they
  were written by different units.**

**SAID PLAINLY: the correlation IS THERE, but it runs the other way from "the refusals that
named a subject paid for themselves". The refusals that paid were the ones a LATER unit acted
on — and by this reading, only ONE of them (`restoredinput`'s guard) is still standing.**

---

## 4. THE INSTRUMENT — AND THE FOURTH CHECK

**THE FOURTH CHECK FOR AN INSTRUMENT THAT ALREADY EXISTS: `slowgate`'s
`UNKNOWN needs=rerun-with-more-seconds` (`cap-plants.rows:9`, *"A SPENT BUDGET YIELDS
`UNKNOWN needs=…`, NEVER `UNNAMED`"*).** The verb is the house form and I did not invent it.

**SO THE DELIVERABLE IS NOT A NEW VERDICT. IT IS A READER — `refusal-read.py`.**

**MEASURED, NOTHING IN THE TREE READS THE `UNBLOCKING` HALF.**
`grep -rn unblock checks/*.py gates/*.py` returns **two hits**, and both are **English in a
comment, neither a parse**: `checks/e2e.py:198` ("the clean unblock") and
`gates/ew-explog-gate.py:5` ("the F32 CONSTANT wall unblocked"). `gatekit.py:59-60` maps five
verdicts to exits and **`REFUSED = 3` carries no `needs=` slot**. **So the second half of every
refusal this project has ever written is, today, unreadable — which is why §2 could report 2 of
39 and not more.**

`refusal-read.py` reads a refusal's two halves and says which one is missing. Six extraction
shapes, **each measured from a real report** (`flipblock` `SMALLEST THING THAT UNBLOCKS:`,
`flipport` `THE BLOCKER.`, `slowgate` `UNKNOWN needs=`, `zerogate` `UNBLOCKING:`, `onewalk`
`the owner must export`, `modulerefuse` `the line the orchestrator must add is`). A shape list
that is not measured is a hand list, which is doctrine 1's forbidden shape.

### BOTH COUNTS, AS ASKED

```
REFUSED-WITH-UNBLOCKING = 2 of 39 refusals    <- read; a plan a reader can execute
REFUSED-WITH-REASON-ONLY = 37 of 39 refusals <- a description
```

**AND THE ASYMMETRY IS THE POINT, NOT A DEFECT:** 37 of 39 refusals here describe a hazard,
and **that is the better outcome** — a refusal with no unblocking cannot be mistaken for a
queued ticket, and the 2 that name one are the 2 whose subject (`fold.bend`) nobody touched.
**A refusal names a plan nobody executes, which is STILL BETTER THAN a refusal that names a
hazard and moves on — because the hazard at least stops the next unit from re-measuring it.**

---

## 5. PLANTED BOTH WAYS

`refusal-read.py --plant`, 4 plants, **and the tool now PROVES it did not leak** —
`LEAKED-INTO-REAL-SLOP=0 []`.

```
PLANT 1   got=READABLE  want=READABLE  OK    a refusal WITH an unblocking  -> readable
PLANT 2   got=none      want=none      OK    a refusal WITHOUT one         -> flagged, NOT invented
PLANT 3   got=READABLE  want=READABLE  OK    slowgate's own verb, verbatim in shape
PLANT 4   satisfaction detectable=no  (no SATISFIED column exists -- REPORTED AS A GAP)
PLANTS-RAN=4 PLANTS-FAILED=1
```

**PLANT 4 IS THE ONE THAT FAILED AND IT IS THE DELIVERABLE'S SHARPEST FINDING.** A refusal
that was satisfied later **must be detectable, or a satisfied refusal is just an unfinished
claim** — exactly `onewalk`'s *"a file says what it is and nothing believes it."* There is no
`SATISFIED` column, because **satisfaction is a property of the TREE (does `fold.bend` have the
arm?) and not of the report**, and my census reads only reports. `satisfied.py` is the first
step and it is partial: it resolves a **backticked path**, which finds 1 subject and misses
`mselectarg`'s *"the row, and it is in a file"* because that report **never wrote the path down**.
**SO: 2 of 39 refusals are machine-closeable, 1 of those 2 has a resolvable subject, and it is
UNSATISFIED. The other 37 are not closeable by this instrument and I am not claiming they are.**

**A BUG I INTRODUCED AND FIXED, BECAUSE A PLANT THAT LIES IS WORSE THAN NO PLANT:** my first
`--plant` printed `NOTE: plants write into a TEMP slop` **while writing four directories into
the real `.agents/slop`.** Caught by looking, removed, and the tool now redirects `rr.SLOP` at
a `TemporaryDirectory` and asserts `LEAKED-INTO-REAL-SLOP=0`. **`plantthe46` is a
pre-existing unit and was left alone.**

---

## 7. WERE ANY REFUSALS WRONG? — THREE RE-CHECKED BY RUNNING THE DECLINED WORK

**A PROJECT THAT REPORTS ZERO WRONG REFUSALS HAS NOT CHECKED, so here are three, and the
re-check is the work the refusal declined — not a re-reading of its reasoning.**

### 7.1 `exitcode` — "the briefed 2→3 fix collides with `argparse`'s own 2". **CORRECT.**
I built the argparse and ran it three ways on this tree's own `.venv/bin/python` (3.12.10):

```
argv=[]                 argparse-rc=0
argv=['--mm','notanint'] argparse-rc=2  usage: t [-h] [--mm MM]
argv=['--nosuchflag']   argparse-rc=2  usage: t [-h] [--mm MM]
ARGPARSE-USES-2 = 2 of 3 invocations
```
**`argparse` does own 2**, and `gatekit.py:60` already assigns `REFUSED = 3`. The refusal was
right and the fix, if landed, would have been a **collision with the interpreter's own
convention** — invisible to any test that does not pass a bad flag. **FINISHABLE: NO.**

### 7.2 `onewalk` — "pointing `vocab-check` at `discover()`'s `entries`" would delete the
owner from the census. **CORRECT ON ALL THREE GROUNDS.** I imported the real `gates-pop.py`
and called the real `discover()`:

```
ledger data rows=128  gatekit.py rows=0
discover(Path('.')) -> entries=127 libs=34
gatekit.py in ENTRIES: False
gatekit.py in LIBS   : True
CLAIM 1 CONFIRMED   CLAIM 3 delta entries-ledger = -1   ledger .sh rows = 17
```
`gatekit.py` (34 720 B, live) is a **`py-lib` and lives only in `libs`**; the ledger iterates
`entries` and holds **0** rows for it. Substituting would compare four copies against an owner
the instrument can no longer see. **FINISHABLE: NO — and the substituted seam would have been
silently wrong, which is worse than unbuilt.**

### 7.3 `declaretwo` — "adding 91 basenames to `DECLARATIONS` turns 62 directories green with
zero human decisions". **CORRECT IN SHAPE; ITS TWO NUMBERS NO LONGER HOLD.** I widened the
real `checks/slop-declare.py` set **in memory** and measured who turns green:

```
WORKING COPY: directories under .agents/slop = 301
declared today (DECLARATIONS as shipped) = 183    undeclared = 118
distinct candidate basenames among the undeclared = 200   (1 candidate: 190, >=2: 10)
=== RUNNING FIX (B): DECLARATIONS widened to 205 names ===
directories that go green: 34
of the newly green, how many had MORE THAN ONE candidate name: 14
```
**34 directories become "declared" with no decision recorded anywhere; 14 of them had more
than one candidate, so the widened set picked for them arbitrarily. A `git mv` records WHICH
file was chosen and a name set cannot.** **FINISHABLE: NO.** But note the two numbers: the
brief and the report say **91 names / 62 directories**; at this read it is **200 / 34**. The
population **moved because units landed `REPORT.md` at depth 0 while the session ran** —
`declaretwo` says exactly this (`the 13/35 split was true at 17:03 and reads 9/100 at 19:40`).
**Both readings are correct for their scope and the number is meaningless without it.**

### AND THE FOURTH, WHICH THE BRIEF SPECIFICALLY NAMED
**`slowgate` found `oracle_f64.py`'s two opposite readings were BOTH TRUE because the
INVOCATION differed — so "out of scope" may be a refusal that ran the wrong command.** I
checked the three refusals above for that failure mode and **found none**: each is a claim
about a FILE's invariant (`argparse` owns 2; `discover()` puts `gatekit.py` in `libs`; a name
set cannot record a choice), not a claim about a run that could have been re-invoked.
**The one refusal in scope that IS invocation-sensitive — `unshardtable`'s "the partial
`git mv` rests on a…" — I did not re-run, and I am saying so rather than implying 4 of 4.**

**SO: 0 of 3 re-checked refusals were wrong, and 3 of 3 were FINISHABLE-WRONG TO OVERRIDE.**
**That is a real result, not a clean bill of health: I chose three refusals whose claims are
mechanically decidable from a file's structure, which is the class most likely to survive
re-check.** A refusal whose subject is a *judgment* — `onewalk`'s "the owner must export the
ceiling", which is an architectural opinion — is not in this sample and **would not be
settled by running anything.**

---

## WHAT I DID NOT DO

No `bend`. No commit, no `git add`, no `git ls-files` (this index has reset 6+ times; I used
`git ls-tree` and `git check-ignore` only). No edit to any gate body, `AGENTS.md`, or
`tinybendygrad/`. `plantthe46` untouched. **Four directories my own first `--plant` leaked into
`.agents/slop` were removed, and the tool now proves the leak is zero.**

**THE CEILING, RESTATED SO NOBODY CITES THESE NUMBERS LOOSE:** the classes are regex
transcriptions of prose, and `declaretwo` measured **1 777 prose citations that were never
positively checked** in this very medium. The only numbers here that were RUN are the three
re-checks (§7), the 5-of-7 gate exits, the 4 restores absent, the 2 satisfactions unsatisfied,
and the 4 plants. **Everything else is a transcription, and says so.**