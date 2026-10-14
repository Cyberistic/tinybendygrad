# THE `REFUSALS BY KIND` SUMMARY IS NOT REPRODUCIBLE FROM THE INSTRUMENT'S OWN ROWS

**MEASURED 2026-10-15. The population agrees exactly; the breakdown does not.**

```
                        summary                        --rows file
VERDICT C               PASS=186 FAIL=89 REFUSED=2992 PASS=186 FAIL=89 REFUSED=2992
LANE C total            3,267                          3,267                      <- IDENTICAL

REFUSALS BY KIND        cell-label=2274  fragment=146  code=120  reference=84
                        digest=71  short=69  command=28
re-derived from the rows, using the tool's OWN needle_kind() and the claiming line
read back out of each file:                                 reference=2990  command=2  cell-label=0
```

**So `cell-label` is either `2,274` or `0`, and both numbers come from the same instrument.**

## WHY THIS MATTERS MORE THAN THE NUMBER

**The breakdown is what tells a reader WHICH RULES ARE LOAD-BEARING.** `cell-label=2274` says one branch
of `needle_kind` handles **76%** of all refusals. **A reader tuning the classifier would tune that branch,
and its own docstring says it was designed for `1` row of a `30`-row sample** — which is either a rule that
grew by three orders of magnitude or a summary that stopped describing its own rows.

## AND I CANNOT SAY WHICH SIDE IS WRONG, BECAUSE MY RECONSTRUCTION MAY FEED THE FUNCTION THE WRONG ARGUMENTS

**`needle_kind(needle, gap, line)` needs THREE arguments and I have been supplying one.** That is not a
hypothetical: my first attempt passed the default `line=""`, which **cannot** begin with `|`, so
`cell-label` was structurally unreachable and I reported **`0`** — **a clean zero from an instrument I had
starved of an argument.** *That is the `P([0-9]*)` error for the fourth time, and it is mine: **a resolver
that does not understand one spelling of an input finds nothing, and nothing looks like the answer.***

## THE FOUR IN A ROW, AND THE PATTERN IS MINE

| # | what I tried | what I got | why |
|---|---|---|---|
| 1 | `grep 'P([0-9]*)'` | `0` hits, wrote a citation was unreproducible | the spelling is `P(i0,` |
| 2 | column 4 as the subject | all 10 "in range" | column 4 is where the claim is *made* |
| 3 | `needle_kind(needle)` | `cell-label: 0` | the default `line` cannot satisfy the rule |
| 4 | `rc=$?` after a pipe | `rc=1` | `$?` is the pipe's |

**Every one of them was a clean number from a broken instrument, and three of the four were mine in this
session alone.** ***AN **INSTRUMENT **THAT **RE-DERIVES **ITS **OWN **OUTPUT **IS **A **SECOND **INSTRUMENT**, **AND
**IT **NEEDS **THE **SAME **DISCIPLINE **AS **THE **FIRST **— **A **SECOND **COPY **OF **A **DERIVED **SET **IS **A
**CONTRACT **WITH **NO **GENERATOR.***

## WHAT WOULD SETTLE IT, AND IT IS NOT A GUESS

**Have the instrument write `needle_kind` as a COLUMN on every row it writes.** Then the summary is a
`Counter` over its own rows and cannot disagree with them, because it is computed from the same values it
published. **That is one column and it removes the entire class.**
