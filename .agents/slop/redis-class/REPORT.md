# THE FOUR `RED_IS` DECLARATIONS, AND THE ONE THAT WAS REFUSED

**MEASURED 2026-10-28.** The instrument is `gates/gate-surface.py`; the census before and after is
below; the falsification harness is `.agents/slop/redis-class/falsify.py`.

## THE QUESTION, AND WHY IT IS A JUDGEMENT AND NOT A FLAG

`gates/gate-surface.py` classes each gate's red into `FINDING` / `UNTAKEN` / `FAILURE`. `FINDING`
needs BOTH halves: the gate declared `RED_IS="FINDING"` in its OWN source AND its own rc-0 plant
REACHED 0 in this run. `FAILURE` is the default, and the default is **the ABSENCE of a
declaration** -- "An undeclared red is CHARGED" (`gate-surface.py:66`).

**SO A BLANKET `RED_IS = "FINDING"` ON FIVE GATES IS THE FAILURE THE INSTRUMENT EXISTS TO
PREVENT.** Its own plant 4b is "the same gate as 4a with one constant deleted", and the census
asserts that 4a is `FINDING` and 4b is `FAILURE`. A declaration that cannot change the answer is
decoration, and "an assertion which cannot be false is not an assertion" (`gate-surface.py:69`).

**THE QUESTION, THEN, IS ONE SENTENCE: IS THIS GATE'S RED A FACT ABOUT THE TREE, OR A STATEMENT
THAT THE GATE ITSELF IS BROKEN?**

## THE CENSUS

| class | before | after |
|---|---:|---:|
| `FINDING` | 2 | **7** |
| `UNTAKEN` | 11 | **11** |
| `FAILURE` | 9 | **4** |
| verdicts declared / reached | 70 / 45 | **70 / 45** |

`GATE-SURFACE: RED -- 22 gate(s) declare a surface, 45/70 verdicts reached, 16 unplanted, 0
NO-GREEN, 4 UNOWNED exit code(s), 10 RENAMED exit code(s)` -- **UNCHANGED**, because a
`RED_IS` changes a CLASS and never a VERDICT. Every issue the census charged before is still
charged after; `RED_IS` is not a way to make a red go away.

**`checks/wallcheck.py` ALSO MOVED, `FAILURE` -> `FINDING`, AND IT IS NOT MINE.** Another unit is
editing it (`git status` shows `M checks/wallcheck.py`, 16 insertions, authored elsewhere). The
`FINDING` count is 7 and **4** of those 7 are mine.

## THE FOUR DECLARED, AND WHY EACH RED IS A FINDING

### `checks/dup-gate.py` -- FINDING

Exit 1 is `gate()`'s or `compare()`'s verdict: a name printed more than once, a measurement no
name can reach, a line the shipped row rule refuses, no shared name at all, or two lanes that
disagree on a shared row's value. **Every one of those is a fact ABOUT THE TREE'S OWN ROWS.** The
guard's FIRST job is to make the loss visible (`dup-gate.py:13`), and a duplicated name costs
`n-1` measurements -- so the red IS the loss, named.

It is NOT "the tree disagrees with CPython": the value comparison is what the gate does
*afterwards*, and on a lane whose two sides print the same bytes it is a tautological zero
(`dup-gate.py:16`).

**The declaration is earned, not asserted**: `PLANTS[1]` compares the tracked repaired fixture
against `oracles/usb-oracle-BEFORE.rows`, a lane that ALREADY carries two duplicate names -- so
the red plant reaches 1 on the tree's OWN rows, not on a synthetic file.

### `checks/env-precond.py` -- FINDING

Exit 1 is `check()`'s `bad` list: a pin the tree's OWN source no longer carries (METHOD A,
anchored on the line's JOB so an edit above it cannot move the pin), or a value the run RECORDED
that differs from the declaration (METHOD B). **Both are facts ABOUT THE TREE'S ENVIRONMENT
PLUMBING** -- the declared precondition MOVED, and this file exists to say which one and where.
A REFUSED (an absent input) is a different thing and is not a verdict at all.

**The declaration is earned, not asserted**: `PLANTS[0]` runs the whole instrument against a
FABRICATED tree whose three values MATCH the declaration and must exit 0.

### `checks/norm_check.py` -- FINDING

The file's own title is "prove `norm` round-trips, **or does not**", and exit 1 is the "or does
not": the SUBJECT's `norm` does not round-trip the f32 pair, or the negative case no longer
discriminates. The subject is a FILE IN THE TREE (`.agents/slop/jslane2/gen_f32_seam.py`), so the
red is a fact ABOUT THE TREE'S NORMALISER. `3` is not a red: it is the refusal for an absent
subject, and a refusal is not a verdict.

**The declaration is earned, not asserted**: `PLANTS[0]` is the gate's OWN run over the tree's own
subject, and it reaches 0.

### `checks/render-gate-oracle-gate.py` -- FINDING

Exit 1 is the PIN SPEAKING, and a pin that goes red is the only thing a pin is for: "This is a
PIN ON THE ANSWER, not a change-detector: **it goes RED when the answer moves**, which is the
only thing a pin is for" (`render-gate-oracle-gate.py:38`). Concretely it is one of two facts
ABOUT THE TREE: the pinned upstream subject MOVED, or the oracle's rows now DIFFER from
`checks/rn-orc.rows`, the tree's own capture of them. `3` is not a red: it is the refusal for a
lane that cannot run.

**The declaration is earned, not asserted**: `PLANTS[0]` runs the same check against an UNMODIFIED
COPY of the oracle and must exit 0.

## THE ONE THAT WAS REFUSED: `checks/residue.py` -- LEFT ALONE

**`checks/residue.py`'s EXIT 1 IS NOT A RED ABOUT THE TREE AT ALL.** Its ONLY exit-1 path is
`plant()`'s `1 if bad else 0` (`residue.py:569`), where `bad` is the list of rows where the
classifier's verdict differs from the hand-written `expect` column in `checks/residue-plant.tsv`.
**That is the instrument disagreeing with its own oracle: the gate cannot do its job.** Its normal
mode (no `--plant`, no `--disarm`) ALWAYS exits 0 and publishes a census; it has no red about the
tree to be a finding about.

**AND IT HAS NO DECLARED RED VERDICT TO BE A FINDING ABOUT.** It declares
`VERDICTS = {0: "PASS", 3: "REFUSED"}` -- **NO EXIT 1**. A `RED_IS` on a gate with no declared red
code would be decoration on a verdict that does not exist. Its census class is `FAILURE` because
"undeclared and green was demonstrated: a red is charged" -- and that is CORRECT: the red it can
emit is the plant failing, and a plant failing is not information about the tree.

**⇒ SO IT STAYS `FAILURE`, AND `gates/gate-surface.py` NAMES IT AS THE ONE THAT IS.**

## THE FALSIFICATION: THE DECLARATIONS ARE NOT DECORATION

`gates/gate-surface.py`'s own plant 4a/4b is "the same gate with one constant deleted". Applied
to the REAL gates (`.agents/slop/redis-class/falsify.py`, which places each gate in a synthetic
tree as a TEMPLATE with its root constants rewritten, so every file it reads is the real file and
nothing in the real tree is written):

```
gate                                    as-is   RED_IS deleted  falsifiable?
checks/dup-gate.py                    FINDING          FAILURE   CLASS MOVES
checks/env-precond.py                 FINDING          FAILURE   CLASS MOVES
checks/norm_check.py                  FINDING          FAILURE   CLASS MOVES
checks/render-gate-oracle-gate.py     FINDING          FAILURE   CLASS MOVES
checks/residue.py                     FAILURE          FAILURE   same
```

**`REDIS: OK -- 0 declared RED_IS that does not move the class.`**

**AND EACH GATE GOES RED ON ITS OWN PLANT**, measured:

```
rc=1  checks/dup-gate.py --compare gates/cstyle-live.rows oracles/usb-oracle-BEFORE.rows
rc=1  checks/norm_check.py --plant
rc=1  checks/render-gate-oracle-gate.py --plant red
rc=0  checks/env-precond.py --plant satisfied          (its rc-1 has NO plant -- pre-existing)
```

`checks/env-precond.py`'s rc-1 remains `UNPLANTED` after this change, and that is a TRUE GAP the
census still charges. `RED_IS` does not close it, and it is not this task's to close: the
`UNPLANTED 1` row, the `UNOWNED 2` rows, and the `RENAMED 0` row are all still charged.

## WHAT WAS NOT DECIDED

**`checks/env-precond.py`'s EXIT-CODE VOCABULARY IS A SEPARATE DEFECT AND IS NOT MINE TO FIX.** It
spells exit 2 `REFUSED` where `gates/gatekit.py` spells 3 `REFUSED` (two meanings on one number),
and spells exit 0 `OK` where `gatekit.py` spells it `PASS` -- the census charges both as `UNOWNED`
and `RENAMED`. Fixing them means changing the gate's exit codes, which is a different change from
a declaration, and `checks/dup-gate.py` spells 2 `USAGE` for the same reason its own comment
explains at length. **A DECLARATION DOES NOT FIX A VOCABULARY, AND A VOCABULARY IS NOT FIXED BY
DECLARING IT.**

**`checks/dup-gate.py`'s exit 3 remains UNPLANTED** and the census charges it. Its own comment
says why: no argv reaches 3 with the inputs present, and an UNPLANTED verdict is a true gap while
a MISPLANTED one is a false witness. **NOTHING WAS WEAKENED TO HIDE IT.**
