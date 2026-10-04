# The record correction — 222 is a retired READER's number, not a population

## What is wrong, precisely

`222` is what **one forked reader** produced on one tree at one moment, before the
`kern CUDA  lb=1` / `kern CUDA  lb=4` collision was fixed by renaming. It appears in
`.agents/slop/cstyle-gate.py`'s own docstrings at three sites, and it is a **count of
names a since-replaced reader produced**, not a count of rows, kernels, or anything the
port emits. Quoted as a population it is wrong in both directions at once:

- the live gate reads **227 port rows / 224 oracle rows / 221 gated / 6 excluded**
  (audit 05, measured twice);
- the real population for "how much of this port actually executes" is
  **227 rows from the port's own stdout**, per `portexec/README.md:45`.

`portexec` is committed and its numbers are right; I did not touch it.

## The authority, quoted

`.agents/slop/portexec/README.md:50-55`, the file that owns the measurement:

```
| **EXECUTED, numbers compared against CPython** | **1** (`kern2 CLANG`) | **0.44%** |
| plus a kernel NOT among the 227 rows, emitted by the same `render_kernel` with 4
  buffers, also executed | 1 | — |

So: 2 of 227 rows have been executed. 225 are still text-only, and 216 of those
are not even compilable C. The denominator matters more than the numerator here.
```

**The defensible statement is that one, in that file.** Not a number restated here,
because the defect being corrected is a number restated somewhere it does not live.

## The consequence that was published from it

Commit `63d9adc2fd` quoted "222 rows" as cstyle's population and derived "0.9%
executable" from it. Both halves are wrong:

- the population is **227**, not 222;
- and the percentage was never 2/222 to begin with — it came from the *other* reader's
  224. `2/224 = 0.89%`, `2/227 = 0.88%`, `2/222 = 0.90%`. Three denominators, one
  numerator, and the published figure is the one built from a number that measures
  nothing. The figures happen to be close, which is exactly why the error survived:
  **a wrong number that lands near the right one is harder to catch than one that does
  not**, and it is still wrong.

## WHAT I DID NOT DO, AND WHY

The brief says "fix the docstrings that repeat 222 as a population", and also lists
`.agents/slop/cstyle-gate.py` in **DO NOT TOUCH**. Those two instructions conflict, and
the DO-NOT-TOUCH list wins: `cstyle-gate.py` belongs to a live unit, and a subagent
widening its own scope by three lines in another unit's file is how two agents end up
resolving the same conflict.

So this file records the correction and the exact edit, and the owner applies it.

## The edit, for whoever owns `cstyle-gate.py`

All three sites are already *historical* — each is describing a fork that has since
been replaced — and each is worded so the number reads as current. None needs a new
claim; each needs its number attributed.

**Site 1, `cstyle-gate.py:179-181`** — already correct in substance ("Over this tree's
own oracle lane the fork's number was `222` against `rows_strict`'s `224`"). It says
*fork's number*, which is the right attribution. No change strictly required; adding
"(that reader has since been replaced; the live lane reads 224)" would close it.

**Site 2, `cstyle-gate.py:208-211`** — the offender, because it reads as a present-tense
property of this lane:

> this lane BEFORE the `kern lb=` -> `kern lb ` rename, on BOTH lanes: 227 port rows read
> as 225 names and 224 oracle rows as 222, ...

This one is already marked BEFORE, so it is defensible. The risk is a reader who takes
`222` and searches for it. Suggest appending, after the existing sentence:

```
`222` is that dead reader's output, not a population: the live gate reads 227 port
rows / 224 oracle rows / 221 gated / 6 excluded, and the executed fraction is
portexec/README.md's own "2 of 227 rows have been executed".
```

**Site 3, `cstyle-gate.py:448-449`** — "put 9 of the 222 shared rows into
disagreement". Also historical ("the 222 shared rows" of that fork), and the correct
current figure for shared rows is **227** per audit 05's `IDENTICAL (227 shared)`. This
is the one most likely to be misread, because "the shared rows" sounds like a
population. Suggest:

```
put 9 of that fork's 222 shared rows (227 shared on the live lane) into disagreement
```

**Then, the standing rule this exposes.** A number that names a *reader* belongs in the
sentence that names the reader, and nowhere else — not in a commit message, not in a
derived percentage, not in a docstring three paragraphs from the attribution. Every
instance of this class in the project so far has been a reader that was replaced and a
number that outlived it: 222, and the 227/224/221 split, and the `239`/`224` family the
audit found in the forked readers. The scrub has to be a *scrub*, not a fix of one site.