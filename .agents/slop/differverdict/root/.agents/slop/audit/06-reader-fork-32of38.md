# 06 — "32 of 38 readers drifted"

**VERDICT: CAN-FAIL** — the number is a function of the corpus and moves when the
corpus moves. **The denominator is a classification decision, and 315 of the 353
functions are excluded from it without an assertion that the exclusion is right.**

## Subject and instrument

- **Subject:** the reader functions in `.agents/slop/` that answer a row question,
  and how each drifts from `rebase-gate.py`'s `rows()`.
- **Instrument:** `.agents/slop/reader-fork-census.py`. Reproduced live:

```
text->mapping      29    drifted=28
line->answer        5    drifted=4
value->fold         4    drifted=0
DRIFT, over every function in this corpus that ANSWERS A ROW QUESTION
  DRIFTED 32 of 38    (29 text readers, 5 per-line, 4 inverse-fold)
```

29 + 5 + 4 = 38. The decomposition is printed, so the denominator is not a bare
number.

## Plant — CAN-FAIL: the number tracks its corpus

Narrowing the corpus is a subject perturbation and needs no writes.

| corpus | result |
|---|---|
| whole tree | `DRIFTED 32 of 38` |
| `--only rebase` | `DRIFTED 1 of 3  (2 text readers, 1 per-line, 0 inverse-fold)` |
| `--only renderer` | `DRIFTED 0 of 0` |
| `--only opsbend` | `DRIFTED 0 of 0` |

**32/38 → 1/3 → 0/0.** The numerator is real and the denominator is derived, not
typed.

## The control is right, and it is the right kind

`reader-fork-census.py:13` — *"THE CONTROL IS `rebase-gate.py`'s OWN `rows()`,
LOADED BY PATH AND NEVER RE-TYPED"*, and line 100 `CANON_ROW = GATE_MOD.row`.
This directly answers agent-core's rule that *a row whose expected value is a def
of the thing under test is not a test*: here the canonical behaviour is loaded
from the real module rather than transcribed, and the census prints an md5 of it
plus how many of the drifted readers are the control itself.

## The CANNOT-FAIL component: the denominator is a classifier's opinion

The full census of the corpus:

```
not-single-arg     137   drifted=0   (not a row reader: excluded from drift)
NOT-COMPARABLE      82   drifted=0   (not a row reader: excluded from drift)
runner              72   drifted=0   (not a row reader: excluded from drift)
text->mapping       29   drifted=28
path-reader         13   drifted=0   (not a row reader: excluded from drift)
refused-text         9   drifted=0   (not a row reader: excluded from drift)
line->answer         5   drifted=4
value->fold          4   drifted=0
not-a-reader         2   drifted=0   (not a row reader: excluded from drift)
```

**38 is the denominator. 315 functions are outside it**, each excluded because a
static classifier said it is not a row reader. The exclusion is *printed*, which
is the good half — but it is a **judgement**, and there is **no assertion that a
reader classified as `not-single-arg` is not in fact a reader.**

This is the brief's denominator hazard in its sharpest form. A coverage number
whose denominator is produced by a classifier that can be wrong, with no control
on the classifier, can only go red in one direction: a misclassified reader makes
the denominator *smaller* and the drift fraction *larger*, so the headline
number gets worse for the wrong reason and nobody notices the exclusion.

I could not plant this without editing a live `.agents/slop/*.py`, which the
brief forbids and several concurrent units are holding. **So: the numerator is
CAN-FAIL and measured; the denominator is unverified against its own classifier
and I am not claiming otherwise.**

## Reproduce

```
.venv/bin/python .agents/slop/reader-fork-census.py
.venv/bin/python .agents/slop/reader-fork-census.py --only rebase
grep -n 'excluded from drift\|CANON_ROW\|def qualified\|family' .agents/slop/reader-fork-census.py
```