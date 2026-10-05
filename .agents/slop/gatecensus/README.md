# gate census — which gate-shaped files are REAL GATES, and which of them RUN

    .venv/bin/python .agents/slop/gatecensus/enum.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]            # the denominator, alone
    .venv/bin/python .agents/slop/gatecensus/classify.py --list  # the classification
    .venv/bin/python .agents/slop/gatecensus/classify.py --selftest   # prove each fix moved a number
    .venv/bin/python .agents/slop/gatecensus/run.py --dry-run   # enumerate, run nothing
    .venv/bin/python .agents/slop/gatecensus/run.py             # run every candidate, sequentially
    .venv/bin/python .agents/slop/gatecensus/group.py --why     # reds grouped by CAUSE

Four files, four jobs. `enum.py` counts. `classify.py` decides what a gate is. `run.py` executes.
`group.py` answers "how many distinct problems".

## A CENSUS THAT EXAMINED NOTHING AND REPORTED ALL-CLEAR IS THE FAILURE MODE

`substrate-check.sh` printed `SUBSTRATE CLEAN: 0 file(s)` with no arguments for the life of the
project. So every number here is a count of something measured, and every verdict is mechanical:

| verdict | rule |
|---|---|
| `PASS` | within BOTH bounds, child rc 0, output present, a verdict token seen |
| `FAIL` | within both bounds, child rc != 0, **and the cause line is quoted** |
| `NOT-RUN` | a bound fired (`KILLED-ON-MEMORY` / `TIMED-OUT`), or ZERO bytes, or rc 0 with no verdict token, or `NO-BOUNDED-LINE` |
| `SKIP` | printed usage / `REFUSED` — bare is a different instrument from "run with its population" |
| `UNSAFE` | not attempted BY NAME: it would write the port or plant a mutation |

**NEVER REPORT A GREEN YOU DID NOT SEE.** A gate that timed out, was killed on memory, printed
nothing, or refused is `NOT-RUN`. `rc=142` is a `SIGALRM` — our own alarm — and proves nothing.

## SIX THINGS THIS INSTRUMENT GOT WRONG FIRST, ALL MEASURED

1. **`git grep -- '.agents/slop/*.md'` — a git pathspec `*` CROSSES `/`.** The 43 "citers" of
   `substrate-check.sh` were 17 real documents plus 26 inside `.agents/slop/differverdict/root/`,
   **a shadow copy of this tree inside this tree**. Fixed with `:(glob)`, which is documented git
   pathspec magic, not a guess: `43 -> 17`, `39 -> 12`, `21 -> 6`, `22 -> 6`.

2. **Bare basename.** `bend` reported 89 citing lines; none names the executable. Fixed by anchoring
   on the full basename WITH its extension. There is deliberately no extensionless branch —
   `xd1/bend` has none, and no text search separates it from the word `bend`, which in this
   project's prose means the LANGUAGE. An instrument that cannot answer is not allowed to answer.

3. **The anchored regex handed to `git grep -E`.** POSIX ERE has no lookaround:
   `repetition-operator operand invalid`, rc 128 — which the original guard swallowed as "no
   citations". **Every gate came back named-by-nothing and the classifier printed a confident list
   built on a total failure to look.** The anchor is applied in Python, never in grep.

4. **`bounded.py` exit 3 IS AMBIGUOUS.** `checks/bounded.py:152` ends `return rc if rc else 0`, so
   a WITHIN-LIMITS run whose CHILD exited 3 leaves bounded.py exiting 3 — byte-identical to the
   KILLED-ON-MEMORY return at line 147. MEASURED: `substrate-check.sh` refuses an empty population
   with exit 3 at peak-RSS 2 MB. A runner reading the exit code calls a correct refusal a machine
   that nearly died. **The verdict TOKEN is parsed; the exit code is recorded beside it, never
   substituted for it.**

5. **Classifying on the rc and keeping no text.** 425 rows came back `FAIL` and **404 could not
   name what they were failing on**. A red you cannot quote is not a finding. Every row now keeps
   the child's verbatim output and quotes the cause line — a traceback's last line, which is where
   the defect is named.

6. **The walk paid for every shadow script.** Marking a file shadow and skipping it still
   stat-ed ~4,600 scripts inside the copies. Worse, the marker (`.agents/`, `tinygrad/`) is a
   property of the DIRECTORY, so a per-file test cannot see it at all. Pruned at the walk: the
   denominator went 1,375 -> 455, all of it copies.

## WHAT IS NOT A FIX

- `classify.py` reports a GATE on name (`-gate`, `-check`, `-census`) even with zero citers, and
  labels those rows `[NAME ONLY - no document names it]`. A name is evidence about intent, not a
  measurement, and the two are printed separately.
- `--dry-run` on a gate-shaped population does not tell you whether a gate is any good. Only
  `run.py` does that.
- Grouping is by CAUSE KEY, deliberately coarse. Too fine re-counts one problem as N; too coarse
  merges two. Both have been measured wrong in this project.

## MEASURE ONLY

Nothing here edits a gate, a `.bend`, or `runtime/**`. A red with a one-line cause is **reported
with the line**, not fixed — those files belong to units that are mid-edit.