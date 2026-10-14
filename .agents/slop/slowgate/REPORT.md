# THE CLASS OF GATES THAT CANNOT FINISH, AND THE ONE THAT CRASHED INSTEAD

**Measured 2026-10-07. Every verdict below is the TOKEN on `[bounded]`, never the exit code** — rc 3 is
`sh -c 'exit 3'` at 0 MB and a memory kill at 2,988 MB, and a unit in this tree lost 425 rows reading
the status. Scope is stated in the same sentence as every count.

## 1. BOTH REPRODUCED, AND THE TWO UNITS THAT DISAGREED WERE BOTH RIGHT

**`checks/oracle_f64.py` — THE `IndexError` IS ALREADY FIXED. `plantthe46` WAS CORRECT AND
`zerogate` WAS NOT.** MEASURED, bare:

```
[bounded] WITHIN-LIMITS  rc=3  peak-RSS=21 MB  0s  :: .venv/bin/python checks/oracle_f64.py
  said=REFUSED, NOT A VERDICT: needs <workdir> <mm-rows>; got 0 argument(s).
```

**Zero tracebacks** (`grep -c Traceback` = **0**), rc **3**, and `PLANTS = {3: []}` — so the plant and
the defect are the same command and cannot drift apart. The fix is at `checks/oracle_f64.py:281` and
its rationale is at `:266-280`: **the guard is in `main()`, not at module scope, and that is measured
rather than styled** — `checks/run-f64.sh:147` *imports* this module, so `sys.argv` is the harness's.
Verified: importing with a 2-element `sys.argv` returns without refusing.

**SO THE DIFFERENCE THE TASK ASKED FOR IS NOT A DISAGREEMENT ABOUT THE FILE, IT IS A DISAGREEMENT
ABOUT THE INVOCATION** — and the reason it is a real one:

| how it is called | what happens | reader |
|---|---|---|
| `python checks/oracle_f64.py` (no argv) | **rc 3, `REFUSED`, no traceback** | `plantthe46` — "does not reproduce" |
| `python checks/oracle_f64.py a b` | runs the census | the intended use |
| `import oracle_f64` from a 1-arg harness | **does NOT refuse**; module scope is untouched | `run-f64.sh:147` |

A unit that *imported* it, or read only the guard's absence from memory, would have reported the old
traceback. The fix is real and was not re-applied here — **a second unit landing the same fix is a
commit that says nothing.** Planted both ways: no argv → `REFUSED`/3; `--plant`-equivalent → clean.

**`checks/residue.py` — REPRODUCED, AND IT IS WORSE THAN "SLOW".**

```
[bounded] TIMED-OUT  rc=-9  peak-RSS=67 MB  120s   out=0B err=0B
```

**0 bytes of output at 120 s.** The report file is never opened, so every run that included it was
waiting for a census that was never written. With the cap landed, same command: `WITHIN-LIMITS`.

**AND A PRIOR MEASUREMENT IN THIS VERY DIRECTORY EXPLAINS WHY TWO UNITS COULD DISAGREE ABOUT IT.**
`.agents/slop/slowgate/residue-full.err`, written 07:16 today, is:

```
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=359 MB  524s  :: .venv/bin/python checks/residue.py
```

**A COMPLETE 524 s RUN, UNBOUNDED, ON THE SAME FILE.** So `residue.py` does not have a fixed runtime;
it has a runtime **a function of how much the units have written**, and the 600 s uncapped runner
catches it only when the tree is quiet. **`TIMED-OUT` AND `WITHIN-LIMITS` ARE BOTH TRUE OF THIS GATE
ON THE SAME DAY**, which is the worst property a gate can have: a reader who ran it at 07:16 saw a
census, and a reader who ran it at 07:00 saw a timeout, and **neither observation is a lie and
neither one tells you the gate is unreliable.** MEASURED wall times on this tree, uncapped: 524 s,
1,131 s, and still climbing — the floor moved from 117 s to >900 s within one session. **A GATE
WHOSE VERDICT DEPENDS ON WHAT ELSE IS RUNNING IS NOT A GATE, AND NO AMOUNT OF RE-RUNNING FIXES IT.
ONLY A CAP DOES.**

## 2. WHAT THE COST IS — POPULATION, PER-FILE WORK, OR AN UNBOUNDED LOOP?

**IT IS PER-FILE WORK, TWICE, AND BOTH INSTANCES ARE `checks/sweep.py`'s.** Not this file's
population; not an unbounded loop. There is no loop here that does not terminate.

**MEASURED, uncontended, one phase at a time:**

| phase | file:line | cost | shape |
|---|---|---:|---|
| `sweep.house_excluded` × 438 | `sweep.py:219-225` | **104.0 s** | re-`importlib`-loads `residue.py` **and** re-AST-parses all of `checks/*.py` + `gates/*.py`, **once per path, no memo** |
| `committed_named_text` (551 × `git show`) | `sweep.py:351` | **96.9 s** | one subprocess per corpus member |
| `mentioned_filenames` (1 regex pass) | `sweep.py:446` | 0.15 s | the fix that already landed |
| `outside_twins` | `residue.py:289` | 1.2 s | 479 twins |
| `index_citations` | `residue.py:501` | 8.2 s | 127,742 keys |
| **belt A: 1,641 rows × 0.32 s** | `residue.py:366` | **525 s** | **one `git grep` per row** |

`self_output_dirs()` MEASURED **0.205 s warm, 0.256 s cold, identical every call — there is no
memo**, and `house_excluded` is called once per tracked `.md` under `.agents/slop/` (**438**).
`sweep.py:435` calls this exact shape "this project's worst performance bug" and fixed its own
instance; the fourth instance was one call away, in the function that consumes it.

**WHAT `residue.py`'s OWN POPULATION IS: 4,612 files walked, 2,111 DELETE rows, 1,641 of which reach
belt A.** And a bounded version answers a useful question — §3.

**WHAT THIS MEASUREMENT CANNOT DISTINGUISH, AND IT MATTERS TWICE.**
1. **It cannot separate belt A from the pre-classify floor, because both are wall-clock.** At
   `--seconds 900` the run paid **0** belt-A calls and took **1,131 s** — so on this tree the floor
   now *exceeds* a 15-minute budget, and it moved from 117 s to >900 s inside one session as units
   wrote reports. **A bound derived from a phase this file does not own is a bound on a clock someone
   else sets.**
2. **My first numbers were contended and I published them anyway.** A first pass measured
   `committed_named_text` at 187 s and reported 43 minutes for a phase that costs 103 s; the second
   copy of the probe was running. **Every figure above is from a single un-contended pass, and the
   117 s floor is itself a lower bound that has already been falsified twice.** Report the per-call
   cost (0.32 s), not the phase total: it is the one that does not move.

## 3. THE CAP, AND WHY IT IS IN THE GATE AND NOT THE RUNNER

**`checks/bounded.py` ALREADY EMITS THE RIGHT VOCABULARY, AND THAT IS THE REASON NOT TO USE IT AS
THE ONLY BOUND.** A bound that lives in the runner exists only when someone remembers to run the
runner; `coindependent` MEASURED 40 entry points nobody runs, and this file is one of them.
**A GATE THAT CANNOT BE RUN BY HAND IS NOT A GATE.** It now carries its own.

**IT IS A ROW CAP, NOT A WALL CAP, AND THE MEASUREMENT IS WHY:** belt A costs a MEASURED, CONSTANT
0.32 s per call, so 500 calls = **160 s of citation work** whatever else is happening on the machine.
The wall bound (`--seconds 1800`) is kept as a backstop but it is not what binds.

**WHAT IT ANSWERS ON A SMALL BOUND — MEASURED, BOTH DIRECTIONS, WITH WALL TIMES:**

| run | belt calls paid | rows left `UNKNOWN` | verdict | wall |
|---|---:|---:|---|---:|
| `--plant` (synthetic tree) | — | — | `WITHIN-LIMITS` rc 0 | **1 s** |
| `--belt-rows 20` (over-cap) | **20 of 20** | **1,299 of 2,087** | `WITHIN-LIMITS` rc 0 | **562 s** |
| `--belt-rows 400` (under-cap) | **400 of 400** | **916 of 2,084** | `WITHIN-LIMITS` rc 0 | **428 s** |
| uncapped, before this change | all 1,641 | 0 | **`TIMED-OUT`** | **>600 s, 0 bytes out** |

The wall times are contended (two runs differ by 134 s in the direction the *smaller* budget took
longer) — so the honest reading is the **ratio and the row counts, not the milliseconds**, exactly as
`substrateid` did. **A CAP WITH NO SMALL-VALUE READING IS A CAP THAT CAN ONLY EVER REPORT FAILURE, SO
THE CAP DOES NOT ABORT THE RUN.** Every run above published a census and returned rc 0.

**THE ONE SENTENCE THE CAP MUST NOT BE ALLOWED TO SAY.** A row whose second belt never ran is
**`UNKNOWN`, never `UNNAMED`** — `UNNAMED` means *every test ran*, and a spent budget would make that
a lie in the exact direction this file exists to prevent. `--plant` now runs the fixture **twice**,
once armed and once with `BeltBudget(0, 0)` spent, and the spent pass asserts those rows come out
`UNKNOWN`, so **the bound is asserted by the same oracle as the verdict it can change.**

## 4. THE CLASS, BY DISCOVERY

**SCOPE, STATED WITH EVERY NUMBER: every `.py`/`.sh` DIRECTLY inside `checks/` and `gates/`
(`iterdir`, no `rglob`, so no `__pycache__`), PLUS every repo-root file with a `#!`. 163 files
walked → 129 entry points (18 shell, 111 python), census wall time 0.55 s.** `gates/gates-pop.py`'s
`HOMES=("checks","gates")` is deliberately **not** used: a hand list is not a population, so the
repo-root lane is walked here instead. **Other units measured this population at 113, 114, 115 and
124 while they worked; 129 is this reading, 2026-10-07, and it MOVES.**

### CANNOT FINISH

| count | what | who |
|---|---|---|
| **1 MEASURED** | hangs past 600 s, 0 bytes out | `checks/residue.py` — now capped |
| **35 of 111** python entries | spawn `subprocess.*` with **no `timeout=`** — an unbounded wait | `cl-port-gate.py`(5), `differ.py`(5), `bounded.py`(4), `jsfix_gate.py`(4), `sweep.py`(4), `abi_gate.py`(3), `disagree-gate.py`(3), `e2e.py`(3), `residue.py`(3) +26 |
| **105 of 129** | carry **no time bound of any kind** — rely on a runner | *this column distinguishes nothing; it is reported to be reported* |

**WHAT THE CENSUS CANNOT DISTINGUISH, AND IT IS THE WHOLE OF THE HANG COLUMN: a gate that HANGS from
a gate that is merely UNBOUNDED.** Only `residue.py` was measured, and only because it was named. 105
entries that *could* hang are not 105 that do — `bounded.py` is in the unbounded list and is the
instrument that bounds. **A STATIC PROPERTY IS NOT A HANG.** Ruling on the other 104 needs 104 bounded
runs, and 108 of the 163 files name `bend`, which I was told not to run: **that census is not taken,
and this report does not pretend to have taken it.**

### CAN CRASH AT rc 1

**STATIC (AST, decidable): 2 of 111 — `checks/coverage.py:53` and `checks/repair-dupes.py:78`, both
BARE-RUN AND MEASURED `rc=1` with a traceback.** Six more read `argv[i>=1]` behind a `len()` guard
and are named in the census. **My first filter counted `sys.argv[0]`, which cannot raise, and called
`checks/substrate.py:931` CRASHABLE — running it bare answered rc 3, `WITHIN-LIMITS`, in 0 s. The
static claim and the measurement disagreed, the measurement was right, and the filter was the defect.**
`prune4`'s lesson, reproduced inside the instrument that was sent to apply it.

**AND `oracle_f64.py` IS IN THE GUARDED COLUMN, NOT THE CRASHING ONE — WHICH IS THE ANSWER TO THE
TWO UNITS' DISAGREEMENT, MEASURED.**

## 5. IS A GATE THAT CANNOT FINISH WORSE THAN ONE THAT IS GREEN OVER NOTHING?

**YES — AND BY A MARGIN THIS TREE HAS ALREADY PAID FOR.**

`zerogate` MEASURED a gate going green over `0 of 0` after restoring one input. Both are observed here.
The asymmetry:

- **A HANG LIES ABOUT ITS WORK, AND IT IS SELF-ANNOUNCING.** `residue.py` emitted **0 bytes** in
  120 s. Anyone reading its output sees nothing at all. The cost of the lie is the runner's timeout
  slot, which is *someone else's* budget.
- **A GREEN-OVER-`0 of 0` LIES ABOUT ITS EXISTENCE, AND IT IS SILENT.** It prints a verdict, occupies
  the same slot, and is **indistinguishable in a log from a real pass**. Nothing times out. Nobody
  investigates.

**THE ASYMMETRY IS IN THE TIMING, AND IT IS WHY A HANG IS THE LESSER EVIL.** A hang **announces itself
by consuming the resource** — it is noticed, which is why THREE units found it and why it became this
report. A false green announces nothing and consumes nothing. **A DEFECT THAT COSTS YOU TIME IS
DEBUGGABLE; A DEFECT THAT COSTS YOU NOTHING IS INVISIBLE.** But that is a statement about
*discoverability*, not about *harm*, and the honest summary is: **the hang is worse for the runner's
budget and better for the reader; the false green is worse for both the reader and the project, and
only survives because nothing is watching the denominator.**

**AND `residue.py` WAS THE THIRD CASE, WHICH IS THE ONE NOBODY NAMED: it was not hanging, and it was
not green — it was `DEAD` the whole time, and it was sitting in a slot where every other gate returns
a token in 4.1 s.** `DEAD` = ran and emitted nothing. Every run that included it was **waiting for
nothing**. So the ranking is not hang > green-over-nothing; it is:

**`DEAD` > false-green > hang**, where "worse" means "harder to notice and less likely to be acted
on". And the reason `DEAD` is worst is the one this file was written to record: **a `DEAD` gate looks
exactly like a gate that is working, because both produce no output and both exit without anyone
reading a token.**

## 6. WHAT I DID AND DID NOT CHANGE

**`checks/residue.py`** — `--seconds` (default 1800) and `--belt-rows` (default 500), a `BeltBudget`
opened at the **top of `main()`** (a budget that starts at the classifier measures nothing for the
whole of its own cost), a spent budget yielding `UNKNOWN needs=rerun-with-more-seconds`, the shortfall
**printed and written into the report header**, and a second `BeltBudget(0, 0)` pass in `plant`.
The header says **THE CENSUS BELOW IS PARTIAL** when the cap bit, because a cap whose effect is
invisible is the clock-dependence this file's own docstring rails against.

**`checks/oracle_f64.py`** — **UNCHANGED.** Already correct; the fix and its plant are already there.

**`gates/gate-surface.py` CHARGES `checks/residue.py` A `FAILURE`, AND IT IS PRE-EXISTING:** HEAD's
`residue.py` declares no `RED_IS` either (`git show HEAD:checks/residue.py | grep -c RED_IS` = 0), and
`FAILURE` is that instrument's default for any gate that demonstrates green without declaring one.
**Both declared verdicts are REACHED** (`declared 0/3 reached 0/3`): `--plant` → 0 and `--disarm DELETE`
→ 3, both verified directly. **I am not adding a `RED_IS` to silence a charge I did not cause, and I
am not editing another unit's instrument.** Reported, not papered over.

## 7. NOTHING COMMITTED. NO INDEX TOUCHED.