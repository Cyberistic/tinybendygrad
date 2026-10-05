# WANT — the expectation table, the corpus it is a subset of, and what a missing expectation does

MEASURED 2026-10-06, `DEV=NULL` (the differ's own setting), substrate **WARM**. Not committed.
Owned: `checks/differ.py`, `.agents/slop/want/`. Not owned and not touched: `graphcmp.bend`,
`graphcmp.py`, `checks/corpus-figure.py`, the two frozen oracles in `diffpy/`.

## 0. THE INSTRUMENT, FIRST ON DISK

    .venv/bin/python .agents/slop/want/census.py     # GRAPHS vs WANT, both directions; rc 1 on a gap

This was written **before** the first edit to `differ.py`, deliberately: a fix whose own census
arrives after the fix is a fix that cannot be checked against what it changed.

## 1. THE GAP, BOTH DIRECTIONS, BY NAME

    corpus   graphcmp.GRAPHS :  25
    table    differ.WANT     :  16
    in WANT, NOT in the corpus : 0
    in the corpus, NOT in WANT : 9
      allred alu bit bw cdiv flip late move where
    declared() misses 0 of the 100 per-graph `.txt` names the run writes

`git log -S'"flip": "AGREE"' -- checks/differ.py` returns **nothing**: those nine were never in
`WANT` in any run. They were not dropped from one.

## 2. WHY NOT THE OBVIOUS FIX, AND WHY NOT THE OTHER TWO

**NOT "iterate `GRAPHS` and compare".** `WANT` maps a name to an **expected verdict**, so a new
graph has no expectation to compare against, and a gate that compares against an unset
expectation is a gate that cannot fail. The table is hand-written for that reason. It also rotted,
because a hand-written table has no generator and nothing says when it is incomplete.

**NOT "derive the expectation from the last run's artifact".** Circular, and measurably so:
an expectation derived from the thing it predicts is a description, not a check. Worse here, the
artifact it would be derived from **is currently changing underneath us** — see §4.

**CHOSEN: RUN AND RECORD, AND MAKE THE RUN INCOMPLETE.** A graph with no expectation is run
anyway, its real verdict is recorded, it is marked `UNSET`, and **the run exits non-zero**. Not
skipped (a skip is a silent hole), not defaulted (a default is a gate that cannot fail).

## 3. WHAT IT PRINTS AND WHAT IT RETURNS

`D1-verdicts.txt`, one line per unset graph:

    flip: VERDICT=DISAGREE EXPECTED=UNSET -- RUN AND RECORDED, NOT COMPARED. The corpus declares
    this graph and `WANT` has no expectation for it, so the run cannot say whether that verdict
    is right.

and a trailer, `16 of 25 graphs compared; **RUN INCOMPLETE -- 9 HAVE NO EXPECTATION**`.

`D0-run-summary.txt`:

    graphs=25          <- was `len(WANT)`, i.e. the table's length wearing the corpus's name
    graphs-answered=16 <- the separate count the brief asks for
    graphs-unset=9
    graphs-agree=…     <- counts ARTIFACTS, so it includes unset graphs; see §5

`cmd_run` exits **1**, and prints to stderr:

    RUN INCOMPLETE: 9 of 25 graphs have NO expectation in WANT: allred, alu, bit, bw, cdiv,
    flip, late, move, where. Each was run and recorded (D1-verdicts.txt, marked UNSET) and each
    is in `graphs=`; add an expectation for each to complete the run.

**The refusal is the exit status, not a line in the summary**, because a line in the summary is
something a reader has to know to look for. `PINS` also pins `graphs=25`, `graphs-unset=9` and
`graphs-answered=16`, so a corpus that grows without a matching expectation cannot pass, **and a
corpus that SHRINKS cannot pass either** — which the old `graphs=len(WANT)` could not detect.

## 4. WHICH NUMBERS ARE A FUNCTION OF THE PORT — RE-READ THESE WHEN THE OTHER FIX LANDS

**Functions of the CORPUS (stable, and the whole point of this change):**

| | |
|---|---|
| `graphs` | 25 |
| `graphs-answered` | 16 |
| `graphs-unset` | 9 |
| the nine names | `allred alu bit bw cdiv flip late move where` |
| `declared()` coverage | 0 missing of 100 per-graph names |

**Functions of the PORT (they move when `graphcmp.bend` does).** From the measured warm run:

| | |
|---|---|
| `graphs-agree` | **19** of 25 — 14 answered AGREE plus 5 UNSET graphs that happen to AGREE |
| `graphs-disagree` | **6** — `lin`, `loop`, plus 4 UNSET (`allred` `cdiv` `flip` `late`) |
| `byte-identical` | **19** (was 14 over 16) |
| `not-comparable` | **0** — the port now emits on all 25 |
| `stable-*` | `5 of 5` / `0 of 5` / `0 of 5` |
| `plants-disagree`, `cross`, `conflations`, `controls` | `7 of 7`, `1 of 1`, `4 of 4`, `5 of 5` |
| `oracle-selfcheck`, `census-rc` | **`# ORACLE SELFCHECK: FAIL` / `rc=1`** — the port's own printers, still red |

**THE MEASUREMENT THAT SETTLES THE CHOICE, AND IT IS A TIMING.** On 2026-10-05 the substrate was
COLD — `.agents/slop/graphcmp.bend --check-only` printed `SOME PROOFS FAIL` on a missing
`AOpLit` arm, so **every** bend emission was a 0-row failure and all 16 `D1-graph-*.txt` were
`rc=1` with **no `# VERDICT:` line at all**. On 2026-10-06, mid-task, the same command printed
**`ALL PROOFS CHECK`** — another unit's `AOpLit` arm landed, with no change to any file of mine.

So an expectation derived from the last artifact would have been derived from a run where **every
graph read `rc=1` and no verdict existed at all**, and it would have "passed" for the wrong reason.
That is not a hypothetical circularity; it is what the artifacts on disk said a few hours ago.
**A DERIVED EXPECTATION IS A DESCRIPTION OF A RUN THAT WAS NOT A MEASUREMENT.**

Now measured warm, one run each, `ENV` exactly as `differ.py:44-48` sets it:

| graph | verdict | | graph | verdict |
|---|---|---|---|---|
| `alu` `bit` `bw` `move` `where` | AGREE | | `allred` `cdiv` `flip` `late` | DISAGREE |
| the 16 in `WANT` | 14 AGREE + `lin`, `loop` DISAGREE, unchanged | | | |

**`flip` is `nodes=6/7` on every trial (5 of 5)** — stable, so an expectation written for it
should be `DISAGREE`. **BUT DO NOT TAKE ANY OF THESE AS THE EXPECTATION.** They are one warm run
of a port under active repair; writing them into `WANT` today is exactly the derivation §2 rejects.
They are recorded here so the next person writes an expectation from a **re-measurement**, not
from this file.

## 4a. THE TWO GUARDS, AND THAT THEY WERE MADE TO FIRE

`.agents/slop/want/selftest.py` — rc 0, all assertions pass. A census never shown to fail is not
known to be a guard, so it builds a **throwaway** `graphcmp.py` with one extra graph in a temp
dir, points `differ.py` at it, and asserts the new name reaches the corpus, the unset list,
`graphs=`, `graphs-unset` and `declared()`; then that a **shrinking** corpus is caught too
(the old `graphs=len(WANT)` could not detect that at all); then the **negative** case — a table
with no gap must not report one, or the gate is always-red and therefore not a gate. It mutates
nothing: the live tree, corpus and artifacts are untouched.

`checks/differ.py` `artefacts_ok()`: **0 findings** on the live tree, 25 `D1-graph-`, 25 `D2-cmp-`
and 50 `D2-canon-` names all inside `declared()`, no `UNEXPECTED`, no `MISSING`.
`checks/no-txt.py`: excused rose **103 → 139** (the 36 new corpus names), and the hard `.txt`
count under `runs/graphcmp/` is **0** — nothing of mine is unexcused.

## 5. TWO THINGS THIS CHANGE DOES NOT FIX, ON PURPOSE

1. **`graphs-agree` counts ARTIFACTS, so an UNSET graph that happens to AGREE counts in it.** That
   is honest (it is what the artifacts say) but it means `graphs-agree` is no longer "answered
   and agreed". It is left as a raw count because the alternative — filtering it by `WANT` — would
   make the number depend on the table while `graphs=` depends on the corpus, and two different
   denominators in one summary is how the original defect started. **The two numbers that answer
   "how much of the corpus did we actually check" are `graphs-answered` and `graphs-unset`.**
2. **The `DIFFPY.md` pointer.** `checks/differ.py` said "Reported, not fixed — see DIFFPY.md" and
   `DIFFPY.md` **exists nowhere in the repo** (MEASURED: `find` returns nothing). A pointer to a
   document that is not there is a claim that a fix was reported *somewhere* and the somewhere is
   absent. The finding is three lines of code in `clean_run` itself, so it now lives **in that
   docstring**, where a reader of the defect finds it, and the pointer is gone.
   **`checks/README.md:93` STILL POINTS AT THE MISSING FILE. That file is not mine — reported,
   not edited.**

## 6. REPRO, BEFORE AND AFTER

Both measured on the WARM substrate, `repro 1`, so they are comparable to each other.

    BEFORE  rc=2   5 offenders, ALL PORT FUNCTIONS
      stable-pairs=0 of 5; stable-failed=5 of 5; plants-disagree=1 of 7;
      oracle-selfcheck= (empty); census-rc=rc=1
    AFTER   rc=2   2 offenders, BOTH PORT PRINTERS
      oracle-selfcheck=# ORACLE SELFCHECK: FAIL; census-rc=rc=1

**The three `stable-*` / `plants-*` offenders cleared on their own, with no change from this
work** — they were the port's `AOpLit`/warm-substrate state, which moved under both runs. That
is the clearest possible demonstration of §4: **these numbers are functions of the port, and
they moved while I was working.** Nothing of mine can be credited with the improvement.

**What this change owns in that pair is the two offenders that REMAIN.** `oracle-selfcheck` and
`census-rc` are `graphcmp-oracle.py`'s own printers (`ORACLE SELFCHECK: FAIL`, `rc=1`) and are
**not mine** — reported, not fixed. Before this change there was no way to tell those two apart
from a corpus problem, because `graphs=16` claimed the corpus was fully covered; now the corpus
line reads `graphs=25 graphs-unset=9`, so a reader can see the coverage gap and the printer gap
as two different things.

`check_oracle()` → `[] -- PIN INTACT`; `artefacts_ok()` → **0 findings**; `census.py` → rc 1
(gap reported); `selftest.py` → rc 0, all pass; `no-txt.py` → 139 excused, **0** unexcused under
`runs/graphcmp/`.

**`repro` refuses in both directions, and the refusal is the port's, not this change's.**
