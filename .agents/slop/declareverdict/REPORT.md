# DECLARING WHAT A GATE'S RED MEANS — `RED_IS`, THE THREE CLASSES, AND THE EXIT-CODE MAPPING

`.agents/slop/declareverdict/REPORT.md`. Every number was **MEASURED on 2026-10-07** by running it on
`.venv/bin/python`. Nothing is quoted from a document; `AGENTS.md` is cited only where its own claim
is the thing under test. No gate body, no `AGENTS.md`, no `tinybendygrad/` was touched. **No commit,
no `git add`.**

## WHAT LANDED

| file | before | after | what |
|---|---|---|---|
| `gates/gate-surface.py` | 573 | **686** | `RED_IS` read from each gate's own module body; `classify()`; clause IV (three classes); **clause V, the exit vocabulary owned by `gates/gatekit.py` and loaded BY PATH**; plants 5a/5b/5c; this gate's own `VERDICTS`/`PLANTS`/`RED_IS`, which it did not have |
| `.agents/slop/declareverdict/runner.py` | 116 | **187** | the runner. **No gate name in code** — the only matches for `dup-gate|env-precond|wallcheck|no-txt|residue|rn-gate|nl-gate|norm_check|oracle_f64|hermetic|dup-census|msgdiff|wk-f32` are two lines of a comment explaining a plant |

`gates/gatekit.py` was **not edited**: it already owned the vocabulary, and clause V reads it.

---

## 1. THE SHAPE, AND WHY IT IS A DECLARATION AND NOT A LIST

**ONE CONSTANT, SHIPPED BY A GATE, ABOUT ITSELF, IN ITS OWN SOURCE:**

```python
VERDICTS = {0: "OK", 1: "RED", 2: "REFUSED"}                      # exit code -> the token it prints
PLANTS   = {0: ["--plant", "green"], 1: ["--plant", "red"], 2: ["--root", "/dev/null"]}
RED_IS   = "FINDING"                                              # what MY OWN red is about
```

read by `ast.literal_eval` off the module body by the same `DECL` walk that already reads
`VERDICTS`/`PLANTS` — **not by import**, because importing a gate runs it (`gates/mixin-op-gate.py`
and `gates/beautiful-mnist-gate.py` `sys.exit(2)` at module scope).

**FIVE REASONS THIS IS A DECLARATION, NOT A LIST:**

1. **The population is DISCOVERED.** "A gate that ships `RED_IS`" is found by the same
   `discover()` + module-body walk. `gates/gates-pop.py:discover()` → **124 entries** today,
   14 declaring `VERDICTS`, **1** shipping `RED_IS`.
2. **THE LIST WAS MEASURED STALE WHILE THIS WORK WAS DONE.** `hooks` read **115** at 06:40; I read
   117, 119, 120, and **124** — five readings in two hours with no edit by me. A tuple written at
   06:40 was wrong four times before lunch. `gates/tn_add_sub-gate.py` appeared mid-census.
3. **It cannot name a gate that moved**, because there is no name to move.
4. **It is co-located with the code that makes it true** — a gate that changes what its red means
   changes the constant in the same commit.
5. **IT IS FALSIFIABLE AND A LIST IS NOT.** `--plant green` reaches 0 **by running it**.
   `run.py`'s `--report-gate=` was unfalsifiable: it could never learn whether the name was right.

**AND IT HAS EXACTLY ONE NON-DEFAULT VALUE, DELIBERATELY.** A taxonomy of excusable reds grows a
second class the first time somebody wants one, and each class needs its own reader. One value keeps
the exception single and impossible to grow into a loophole. A value outside the three is **REFUSED,
not defaulted**.

**WHAT REPLACED `--report-gate=`.** Nothing — it was never landed and needed no successor. A runner
invokes `gates/gate-surface.py` with **no argument** and reads clause IV off the transcript.

---

## 2. THE THREE MEANINGS OF A RED, AND HOW A RUNNER TELLS THEM APART WITHOUT A LIST

**THE DISCRIMINATOR IS NOT A NAME. IT IS WHETHER THE GATE HAS EVER BEEN SEEN AGREE.**

| class | how it is established | a runner |
|---|---|---|
| **`UNTAKEN`** | its rc-0 plant did **not** reach 0 — unplanted, misplanted, or no rc 0 declared. An ABSENCE. | **charges** |
| **`FINDING`** | it declared `RED_IS="FINDING"` **AND** its rc-0 plant **reached 0** | tallies |
| **`FAILURE`** | the default — and therefore also what an **undeclared** red gets | **charges** |

```python
def classify(red_is, reached, verdicts):
    green = 0 in reached or 0 not in verdicts
    if not green:
        return UNTAKEN, f"declared {red_is or 'nothing'} but its rc-0 plant never reached 0"
    if red_is == FINDING:
        return FINDING, "declared RED_IS=FINDING and demonstrated green in this run"
    ...
```

**WHY `UNTAKEN` IS NOT A FOURTH MEANING.** `repro-rc`'s "the second measurement has never been
taken" is *"not yet taken" wearing exit 1*, and the vocabulary already owns the right word: `REFUSED`,
exit 3, *"a precondition was absent"*. `checks/env-precond.py` refuses rather than passing.
**The fix for a gate that means it is to exit 3, not to add a word.**

**WHY THE DECLARATION IS EARNED, NOT ASSERTED.** A declaration cannot audit itself, and the only
evidence a gate has a green to fall from is a plant that reached one — which the census already
computes for every gate. **A runner needs no new mechanism: it reads the `reached` map the census was
already printing, as a class instead of a count.**

**MEASURED, live tree, 2026-10-07:**

```
IV FINDING (1): gates/gate-surface.py
IV UNTAKEN  (9): checks/dup-census.py, checks/dup-gate.py, checks/gate.py, checks/hermetic-census.py,
                 checks/nl-gate-noguard.py, checks/nl-gate.py, checks/norm_check.py,
                 checks/oracle_f64.py, checks/rn-gate.py
IV FAILURE (4): checks/env-precond.py, checks/no-txt.py, checks/residue.py, checks/wallcheck.py
```

**A RUNNER THAT COULD NOT TELL THEM APART BLOCKS EVERYTHING OR NOTHING**, and the two states this
shape excludes are exactly those: `UNTAKEN` and `FAILURE` both charge, so **nothing passes by not
being understood**, and `FINDING` is the single, named, earned exception.

---

## 3. `gate-surface` DECLARING ITSELF — **AND THE NUMBER GOT WORSE, WHICH IS THE POINT**

**An auditor of surfaces was the one gate in the population with no declaration to read.** It is now
the only `FINDING` in the tree.

| | at 06:47 | today |
|---|---|---|
| entries discovered | 120 | **124** |
| gates declaring `VERDICTS` | 13 | **14** |
| verdicts declared / reached | 39 / 8 | **42 / 18** |
| **unplanted** | **30** | **23** |

**THE UNPLANTED COUNT FELL FROM 30 TO 23, AND NOT BECAUSE OF THIS WORK.** Six plants belong to
gates other units wrote; the tree moved under the census the whole time (§6). **Declaring moved the
*declaring* count and nothing about whether the declarations are true.** `surface`'s own report
celebrated "the fraction goes down as declarations get more honest"; the honest denominator here is
still ~23 verdicts nobody has ever seen fire. **A declaration must not be a way to make the census
look better, so the number reported is the one that did not move.**

To get its own three verdicts planted, `--plant` had to grow a second direction: `--plant red` returns
**1** — this gate's own red, charged — because **a gate cannot demonstrate the direction it exists in
by asserting it can pass.** All three measured: `--plant green` rc=0 · `--plant red` rc=1 ·
`--root /dev/null` rc=2.

**AN UNEARNED `RED_IS` IS VISIBLE, AND IT WAS VISIBLE ON THIS GATE.** Before `--plant red` existed,
`gate-surface` classified **itself** as `UNTAKEN — declared FINDING but its rc-0 plant never reached
0`. The declaration caught its own author.

---

## 4. NO NAME ARGUMENT — MEASURED, ALL SIX INVOCATIONS

```
$ .venv/bin/python gates/gate-surface.py                        rc=1    <- the census, charged
$ .venv/bin/python gates/gate-surface.py --report               rc=0    <- the census, uncharged
$ .venv/bin/python gates/gate-surface.py --plant green          rc=0
$ .venv/bin/python gates/gate-surface.py --plant red            rc=1    <- its own red, charged
$ .venv/bin/python gates/gate-surface.py --root .               rc=1    <- ONE argument, still runs
$ .venv/bin/python .agents/slop/declareverdict/runner.py        rc=1    <- no argument at all
```

**No hard-coding was required and none was used.** The runner names one *instrument*
(`gates/gate-surface.py`) and one regex for the census's row format. Had it needed a gate name I
would have stopped and reported — that is the hand list `hooks` refused, and refusing twice is the
pattern, not an inconsistency.

---

## 5. PLANTED, BOTH DIRECTIONS, AND THE NEGATIVES

**`gates/gate-surface.py --plant green` — 11 of 11 GREEN.** The class plants:

```
PASS 4a: a gate that DECLARES RED_IS=FINDING and reached rc 0 is class FINDING          class='FINDING'
PASS 4b: THE SAME GATE, `RED_IS` DELETED -- an UNDECLARED red is class FAILURE and is CHARGED
PASS 4c: a FINDING claim on a gate that has NEVER reached rc 0 is UNTAKEN, not FINDING    class='UNTAKEN'
PASS 5a: a declared exit code `gates/gatekit.py` has no name for is RED and the code AND its
         token are NAMED -- `checks/dup-gate.py`'s shape                                      rc=1
PASS 5b: THE SAME GATE with 2 spelled as gatekit spells 3 -- an OWNED code is not flagged     rc=0
PASS 5c: ZERO or TWO module-level unpacks in the vocabulary's owner is exit 2 REFUSED    rc=2/2
```

**`.agents/slop/declareverdict/runner.py` — 5 of 5 GREEN, and it asserts the RUNNER'S OWN verdict,
not the census's:**

```
PASS 1 : a DECLARED FINDING gate's red is tallied, so the runner does not exit 1              rc=0
PASS 2 : THE SAME GATE WITH `RED_IS` DELETED is charged                                        rc=1
PASS 3 : an undeclared gate that has NEVER reached rc 0 is UNTAKEN and charged                  rc=1
PASS 4a: a DECLARED FINDING gate that declares an exit code gatekit has no name for is
         STILL CHARGED -- `RED_IS` is a claim about meaning, not about the NUMBER a runner
         sums                                                          rc=1 charged=['checks/g.py']
PASS 4b/5: the SAME DECLARED FINDING gate spelling all FIVE codes the way gatekit spells them
         is charged for nothing -- or 4a is a runner that charges every code
                                                             rc=0 charged=[]
```

**4b AND 5 ARE THE ASSERTIONS THAT CAN BE FALSE, and they are what keeps the declaration from being
decoration.** 4a/4b are the **same gate differing by one constant**, fully planted, both
demonstrating green: the class can only be reading the declaration. 4a/5 are the **same gate
differing by whether the owner names the code**: the charge can only be reading the vocabulary.
`prune4`'s lesson — *an assertion that cannot be false is not an assertion* — is applied in the
negative direction, twice.

---

## 6. THE COST, AND HOW A RUNNER ENUMERATES WITHOUT A LIST

**ENUMERATION IS CHEAPER THAN A LIST, AND THAT IS THE STRUCTURAL ARGUMENT.** Reading `RED_IS` off
the entries costs one more name in a tuple the module-body walk was already matching, and it
executes nothing. **A list would cost zero and know nothing**: it would have to be re-read,
re-checked and re-argued every time a gate was added, and `discover()` moved **113 → 114 → 115 →
117 → 119 → 120 → 124** across this session. **The declaration makes ENUMERATION free and the RUN
dearer, by exactly the cost of proving it.**

| | median | min | max |
|---|---|---|---|
| `gates/gate-surface.py --report` (whole census, 124 entries) | **3.14 s** | 2.50 s | 4.66 s |
| `runner.py` (census + 3 synthetic trees) | **3.28 s** | 2.76 s | 3.41 s |
| `--plant green` | 0.52 s | 0.50 s | 0.53 s |
| `--plant red` | 0.08 s | 0.07 s | 0.10 s |
| `--root /dev/null` | 0.04 s | 0.04 s | 0.05 s |

**THE WHOLE-CENSUS A/B IS WITHIN NOISE AND I AM NOT CLAIMING OTHERWISE** — §7 explains why a
per-census figure here would be a measurement of other units, not of this design.

**WHO OWNS IT.** The census owns the cost: it is `gate-surface`'s own declaration being verified, and
`gate-surface` pays it by running itself. **A runner pays ~0.12 s once for the whole population**,
because the class and the code mapping both come out of the census the runner already had to run for
the unplanted census. **`hooks` measured 13 of 14 gates finishing in 4.1 s combined; the census at
3.14 s median is cheaper than running that population, because a census READS most gates and runs
only the plants it declares.**

---

## 7. THE EXIT-CODE MAPPING, EXPLICITLY — **AND IT IS THE PART NO LIST COULD ANSWER**

**THE OWNER IS `gates/gatekit.py`, AND IT IS LOADED BY PATH, NOT COPIED:**

```
I  EXIT VOCABULARY, read from gates/gatekit.py's own module body:
   0=PASS, 1=FAIL, 3=REFUSED, 4=SKIP, 5=DEAD -- the OWNER, by path.
```

`vocabulary()` finds the owner's single module-level name←code unpack. **Ambiguous is REFUSED, not
defaulted** (plant 5c): zero unpacks or two means there is no single owner, and defaulting to the
first would silently pick one — which is the whole defect, resolved by guessing.

### 7.1 THE MAPPING A RUNNER AGGREGATES ON

```
rc -> verdict          0 GREEN   1 FAIL   3 REFUSED   4 SKIP   5 DEAD
any other rc           UNKNOWN   -- CHARGED. Never GREEN, never folded into a class.
```

**MEASURED ON THE LIVE TREE — 4 GATES DECLARE A CODE THE OWNER HAS NO NAME FOR:**

```
RED checks/dup-gate.py:     UNOWNED 2 'USAGE'   -- gates/gatekit.py has no name for this exit code
RED checks/env-precond.py:  UNOWNED 2 'REFUSED' -- gates/gatekit.py has no name for this exit code
RED checks/wallcheck.py:    UNOWNED 2 'USAGE'   -- gates/gatekit.py has no name for this exit code
RED gates/gate-surface.py:  UNOWNED 2 'REFUSED' -- gates/gatekit.py has no name for this exit code
V EXIT CODES: 4 declared verdict code(s) that `gates/gatekit.py` has no name for.
```

### 7.2 **SO `rc == 2` IS NOT "A SECOND REFUSAL CODE". IT IS AN UNASSIGNED CODE WITH THREE MEANINGS.**

- `checks/env-precond.py` and `gates/gate-surface.py` spell it **`REFUSED`**;
- `checks/dup-gate.py` and `checks/wallcheck.py` spell it **`USAGE`**;
- `.agents/slop/hooks/run.py:116` computes `r.returncode if r.returncode in NAME else DEAD`, with
  `NAME = {0,1,3,4,5}` — so **an aggregator scores all of them `DEAD`**, a third meaning, and DEAD
  is *"it ran and emitted nothing"*.

**THAT IS THE `refusalsweep`/`envguard` FAILURE ONE LEVEL DOWN: a gate that refuses where it should
refuse is read by the runner as a gate that crashed, because a gate that crashed cannot tell "the
input is absent" from "I am broken".** MEASURED, the live readings are *not* yet fatal — bare
`checks/env-precond.py` rc=0, `checks/dup-gate.py` rc=3, `checks/wallcheck.py` rc=1,
`checks/no-txt.py` rc=0 — so the division is **LATENT**, and clause V is what makes it visible
before a gate starts exiting 2 in normal operation.

**A THIRD SOURCE OF `2`, MEASURED BY ACCIDENT:** `gates/gate-surface.py --plant green red .` (an
unquoted shell word) is **argparse's usage error, exit 2**. Three writers, one number.

### 7.3 **AND `rc == 1` AS RED IS BLIND TO BOTH GUARDS** — `hooks`' MEASUREMENT, RE-CONFIRMED

A runner whose RED condition is `rc == 1` cannot see `msgdiff-gate.py` or `git-massdelete-gate.py`,
which return 1 from their `--plant` self-test only; their refusals are 3. **MY OWN CENSUS IS BLIND
TO THE SAME THING.** `checks/oracle_f64.py` with no argv is **rc=3, REFUSED** — *"needs <workdir>
<mm-rows>; got 0 arguments"* — which is exactly the behaviour `hooks` wants. But `hooks` also records
that file raising `IndexError` at `:266` and exiting **1**, the same number as FAIL, so **the
census's `MISPLANT` count cannot distinguish a crash from a wrong answer.** `reach()` does
distinguish them: it records `TIMEOUT` and `EXC` as `UNREACHED … not tried` rather than MISPLANT,
which is `coindependent`'s rule — *an instrument that has not tried cannot call a verdict dead.*

### 7.4 **THE MAPPING AS LANDED IS INCOMPLETE, AND THIS IS THE HONEST PART**

Clause V catches codes the owner **has no name for**. It does **not** catch codes the owner **names
differently**. MEASURED over every declaring gate:

```
RENAMED  12 codes across 8 gates
```

Of those 12, **11 are synonyms** — `0` is `PASS`/`OK`/`AGREE`/`CLEAN` and `1` is `FAIL`/`RED`/`BROKEN`,
which is wording, not disagreement — and **exactly ONE is a genuine semantic collision**:

> **`checks/wallcheck.py` exit 4 = `NO-ROW`. `gates/gatekit.py` exit 4 = `SKIP`.** `SKIP` is *"it
> could not run, so it measured nothing"*; `NO-ROW` is *"it ran and found nothing to check against"* —
> an **agreement** about an absent row. `hooks/run.py` counts it as SKIP, so **a wallcheck refusal is
> reported as "measured nothing" when it in fact measured and agreed.**

**I DID NOT LAND THAT CHECK, AND THE REASON IS DOCTRINE, NOT DIFFICULTY.** Distinguishing `NO-ROW`
from `SKIP` requires a list of which tokens are synonyms of which verdicts — **the fourth hand list**,
and the one whose every entry would rot silently. The census can report the 12 renames as data
without judging them; **it must not hold a synonym table**, because a synonym table is a list of
meanings that no gate declares and no owner owns. **`NO-ROW` vs `SKIP` is a decision for
`gates/gatekit.py`'s author, not for an auditor.**

---

## 8. WHAT IT **CANNOT** SEE — FIRST, AND UNREORDERED

**1. IT CANNOT SEE A GATE THAT DECLARES ITSELF HONESTLY AND IS WRONG.** `RED_IS` is a claim about
what a red *means*; nothing here can adjudicate it. `gate-surface` declaring `FINDING` is true today
because I wrote the classifier that reads it, and a future author who believes their gate's red is a
finding **will be believed**. **THE MITIGATION IS STRUCTURAL, NOT ABSOLUTE:** the declaration only
escapes a charge if the gate also DEMONSTRATES green, so the cheapest lie — *declare FINDING, never
plant a green* — is caught as `UNTAKEN` (plant 4c). What survives is a gate that genuinely has been
seen green and genuinely mislabels why it is now red, and **no instrument built out of the gate's own
source can catch that. A reviewer is the only instrument for that claim, and it is the one assertion
in this design that cannot be automated.**

**2. A RUNNER'S FIRST RUN OVER AN UNRUN POPULATION IS `citation-gate`: GREEN OVER NOTHING, AND IT
LOOKS LIKE A FINDING.** **110 of 124 entries declare no `VERDICTS` at all** and therefore cannot be
classed; `hooks` measured 40 entry points presented in no state, and **`checks/residue.py` was still
running at 100 s when I killed it.** **HOW IT SHOULD READ: `UNTAKEN`, AND IT IS CHARGED.** The two
alternatives are both worse — assume every first-contact red is a finding and the declaration is
decorative and *any* red passes; ignore first contact and the population is never run at all.
**The charge is correct, because the burden of proof is on the gate and the proof is one line in the
gate's own source**: a gate that has never been run can go and plant a green, which is the cheapest
possible thing for it to do. **A first run being red is the runner WORKING, not failing — and a
first run CAN produce a new red that looks like a failure, which is the POPULATION's defect, not the
runner's.**

**3. `UNTAKEN` IS OVER-BROAD AND THE MEASUREMENT IS THE PROOF.** **9 of 14 declaring gates are
`UNTAKEN`**, including `checks/no-txt.py`, whose rc-0 plant MISPLANTED. So the classifier is not
telling *"the second measurement has never been taken"* from *"the gate could not run"* — it is
saying `UNTAKEN` to both, because `reached` cannot distinguish a gate never tried from one that was
tried and missed. **The fix is a fourth REACH state, not a fourth meaning of red**, and I did not add
it: a fourth state is a fourth reader, and the brief asks for three.

**4. THE POPULATION IS STILL BLIND OUTWARD.** `discover()` walks `HOMES = ("checks", "gates")`.
`.agents/slop/hooks/run.py` — the only other runner in the tree — is **not in the 124**, and neither
is `.agents/slop/onemodule/vocab-check.py`, the instrument that found the rc-2 division in the first
place. `HOMES` is a hand list, is the next member of doctrine 1's table, and nothing landed here
changes it.

**5. THE CLASS IS A PROPERTY OF THIS RUN.** `UNTAKEN` means *no rc-0 plant reached 0 **in this
run***. A gate whose plant is environment-dependent can change class between runs on the same tree,
and a runner recording classes across runs will see a gate migrate `UNTAKEN → FAILURE` with no edit
to any gate. **No history is kept, deliberately**: a ledger of past classes is a file that can go
stale and disagree with the tree, and the tree is the only witness.

**6. THE CENSUS'S OWN COST IS NOT A STABLE MEASUREMENT.** `discover()` moved seven times during this
session and `gates/` is being written by other units while I measure. **The medians in §6 are the
cost of one reading, not of the design**, and the population — not the census — is what moved.

---

## 9. THE FOUR DECISIONS I DID NOT MAKE

1. **I did not add a fourth class.** `UNTAKEN` swallowing `MISPLANT` is real (§8.3); the fix belongs
   with whoever next needs it and should be a `reach` state.
2. **I did not add a synonym table**, so `NO-ROW` vs `SKIP` (§7.4) is reported as data and not
   judged — a synonym table is the fourth hand list.
3. **I did not touch any gate body.** `RED_IS` has exactly one carrier. **13 of 14 declaring gates
   are charged today**, and the honest first act for any of them is to write its own plants, not to
   declare itself.
4. **I did not edit `gates/gates-pop.py`'s `HOMES`** or **`gates/gatekit.py`'s vocabulary.** Both are
   the population and the owner; neither is mine to widen.