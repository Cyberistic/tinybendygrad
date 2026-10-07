# `SKIP` IS NOT VACANT, AND THE VACANT SLOT IS `2`

`.agents/slop/exitcode/` — `reach.py`, `subject.py`, `plant.py`, `plant-runner.py`.
Every number below was measured by running the instrument named beside it. **NO NUMBER HERE IS
INHERITED**, and three of the four claims I was handed were measured FALSE before I changed anything.

**THE HEADLINE, IN ONE LINE: `SKIP` HAS 3 LIVE `return` SITES AND HAS ALWAYS HAD THEM; WHAT IS
VACANT IS EXIT `2`, WHICH 13 FILES RETURN ON PURPOSE AND WHICH `gatekit` HAS NO NAME FOR.**

---

## 0. WHAT IT CANNOT SEE — FIRST, AS ASKED

| limit | measured how | consequence |
|---|---|---|
| I did **not** run `bend`. No number here comes from a run that may still be running. | instruction | every figure is a parse or a fast subprocess |
| `discover()` is **127 entries / 34 modules** today (`gates/gates-pop.py`). The brief said it moved 113 → 124. **It has moved again, to 127, while I worked.** | `gates-pop.discover(Path('.'))` | any count of "the gate population" carries its timestamp; mine is 2026-10-07 and is already stale once |
| `subject.py` reads gates **statically**. It cannot know whether an absence-shaped `if` is REACHABLE at runtime — only that it exists in source. | by construction | "0 real collisions" below is a source claim |
| `reach.py` counts `return <NAME>` / `return <int>`. It cannot see a verdict produced by `sys.exit(...)` at module scope, or by a shell wrapper. | AST scope | the true producer count is a **lower bound** |
| I did not run any gate that needs `bend`, so `gatekit.Gate.run()`'s five returns were read, not exercised. | instruction | §1's reachability is static |
| The **index reset again** during this session: another unit committed a `D` for my untracked `reach.py`/`subject.py`. Files survived in the working tree and were re-added **by explicit path**. | `git status --porcelain` | **I committed nothing.** Anyone reconciling the index should expect my three files to look deleted-and-restored |

---

## 1. THE FIVE EXITS, RE-DERIVED BY AST — AND `SKIP` IS **REACHABLE**

Population by **discovery** (`reach.py`): every `.py` under the repo, pruned of `.git`/`.venv`/
`references`/`__pycache__`/`node_modules`, whose parsed AST contains an import naming `gatekit`.
**47 consumers**, not 45. `.agents/slop/` holds 4 of them, `checks/` 3, `gates/` 40.

| token | `return <TOKEN>` sites | files | produced by a code path? |
|---|---|---|---|
| `PASS` | 3 | `gates/indexread-gate.py:187,201,234` | yes |
| `FAIL` | 1 | `gates/indexread-gate.py:232` | yes |
| `REFUSED` | 4 | `indexread-gate.py:179,183`, `msgdiff-gate.py:339`, `.agents/slop/modulerefuse/x1-derive.py:108` | yes |
| **`SKIP`** | **3** | **`gates/msgdiff-gate.py:318,329,341`** | **YES** |
| `DEAD` | 2 | `indexread-gate.py:220`, `msgdiff-gate.py:344` | yes |

**THE BRIEF'S CENTRAL CLAIM IS FALSE, AND MEASURED FALSE: `return SKIP` HAS 3 SITES, NOT 0.**

### 1a. `gatekit.py`'s own integer literals are NOT `[1]`

The brief said the file's only integer literals are `[1]`. **MEASURED: 33 literals, distinct
`{0,1,2,3,4,5,16,25,200}`** (`reach.py`). `16` is a truncation width, `25` the retry count, `200`
a stderr slice, `2` the `:434` `[:2]` cap. The claim is true only of `return`-position literals,
and even there `run()` returns `REFUSED`, `DEAD`, `0` and `1` — **four distinct numbers, never 4.**

### 1b. Why the claim looked true, and the instrument that produced it

`gatekit.py` has **no `return SKIP`**. That is a fact about *this file*. The briefing converted it
into a fact about *the vocabulary* — a name no consumer produces, as though the constant were only
ever spelled at its definition. `SKIP` is produced 4 lines into `msgdiff-gate.py`'s `main`, and
`checks/wallcheck.py:398` returns the **bare integer 4**. **A CONSTANT NOTHING IN ONE FILE NAMES IS
NOT A CONSTANT NOTHING CAN PRODUCE**, and the scanner that reported 0 was reading one file for a
claim about forty-seven.

---

## 2. DOES `SKIP` NEED CONSUMERS, OR A SUBJECT? — IT HAS BOTH

Asked with the subject inventory, per `droppedinput`'s "a guard over an absent subject has
nothing to say".

**`SKIP` IS REAL, AND ITS SUBJECT IS ABSENT — MEASURED, NOT ASSUMED.** `subject.py` §1 walks every
gate and asks whether an absence-shaped `if` can return early: **15 files can leave early with
nothing to examine.** Three carry `SKIP` and each names a genuinely empty subject:

| site | the absent subject |
|---|---|
| `msgdiff-gate.py:318` | **no arguments** — nothing was asked of the gate |
| `msgdiff-gate.py:329` | **`range` matched no commits** — the population is empty |
| `msgdiff-gate.py:341` | **unknown mode** — the request names no known work |
| `wallcheck.py:398` | **the selector matched no row** — `NO-SUCH-ID` is in no ledger |

So `SKIP` **must NOT be deleted.** It is not an unused slot; it is the verdict for *"the subject
was absent"*, and four gates in this tree already rely on it. **Deleting it would be a BREAKING
change to 4 live producers**, not a cleanup.

### The harder half: **is a crash not a `SKIP` waiting to be named?**

**NO — and the vocabulary already separates them, which is the answer.** `SKIP`'s subject is an
absent *population*; a crash's subject was *present* and the gate died on it. `DEAD` says exactly
that ("it ran and emitted nothing"), and `hooks/run.py:112` maps a traceback to `DEAD`
**deliberately and by name**. Collapsing them would destroy the one measurement that separates
"nothing to grade" from "graded and died" — which is `msgdiff-gate`'s own discipline: *refuse only
what you cannot judge*.

---

## 3. THE COLLISION IN `wallcheck.py` — **THE TREE ALREADY OWNS THE DISAMBIGUATION**

### **THIS IS THE FOURTH TIME TONIGHT THE TREE ALREADY OWNED WHAT I WAS ASKED TO BUILD.**

The brief says `:396` returns 4 and `:400` returns 5, "**both printing `REFUSED, NOT CLEAN`** —
**one verdict under two numbers**." The second half is **false**, and the tree's own declaration
says so:

```python
# checks/wallcheck.py:681
VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED", 4: "NO-ROW", 5: "DEAD"}
PLANTS  = {0: ["--selftest"], 1: ["--plant", "fail"], 2: ["--ledger", "/no/such/walls.tsv"],
           3: ["--plant", "story"], 4: ["NO-SUCH-ID"], 5: ["--plant", "dead"]}
```

Read by `gates/gate-surface.py`'s `declaration()` (AST, no import) — **it is already
DISAMBIGUATED**: `NO-ROW` and `DEAD` are two names for two facts, each with its own plant. Both
plants fire, verified by running them:

```
$ .venv/bin/python checks/wallcheck.py NO-SUCH-ID     -> "NO ROW MATCHES ['NO-SUCH-ID']"    rc=4
$ .venv/bin/python checks/wallcheck.py --plant dead   -> "LEDGER HAS NO ROWS"               rc=5
```

**The facts ARE different** — *the selector matched nothing* vs *the ledger is empty* — **and the
tree already gives them two names.** **THE BUG IS NOT THE NUMBERING. THE BUG IS THE PROSE:** both
branches print `"REFUSED, not CLEAN"`, a token that is in **neither** the declared surface nor the
owner's. `subject.py` §2 flags exactly these two lines and nothing else.

### COST: **DISAMBIGUATION, NOT COLLAPSE** — and the collapse would have been pure loss

| option | cost | verdict |
|---|---|---|
| **collapse 4 and 5 into one number** | **BREAKING**: `PLANTS` declares both, `resolve.py` reads the declaration and **already flags `wallcheck.py 4 NO-ROW` as `COLLISION?` against the owner's `SKIP`**, and collapsing destroys the second fact outright | **rejected** — it would delete a correct distinction to make a wrong one uniform |
| **disambiguate** | **ADDITIVE, 0 consumers**: the numbers and the names are already right | **already landed by the tree** |

**WHAT CONSUMERS COST, MEASURED RATHER THAN ASSUMED: `checks/wallcheck.py` HAS ZERO COMMITTED
SUBPROCESS CONSUMERS.** Discovery was a walk for `subprocess`/`run(`/`$(`/`spawn`/`Popen` naming
`wallcheck.py`; the only two hits are an unscripted `.agents/slop/coindependent/twostate.py`
experiment. **So the 6-consumer figure is not reproducible from the tree, and this is a third
inherited number that did not survive measurement.** A collapse would still be wrong — it would
delete the `PLANTS` entry `gate-surface.py` executes to earn exit 5.

**THE ONE-LINE FIX, NOT LANDED BECAUSE `wallcheck.py` IS NOT MINE:** change the two printed strings
to the names the file already declares — `"NO ROW MATCHES … -- NO-ROW, not CLEAN"` and
`"LEDGER HAS NO ROWS -- DEAD, not CLEAN"`. **That is a string edit, not a numbering edit, so it
touches no consumer at all.** Filed, not applied.

---

## 4. WHAT A RUNNER SHOULD CHARGE FOR AN UNASSIGNED CODE — **LANDED**

**THE VACANT SLOT, MEASURED: EXIT `2`.** `return 2` is deliberate in **13 tracked files**:
`checks/{al-verdict,differ,disagree-gate,dup-gate,e2e,env-precond,nvrows-deadrow-gate,substrate-id,
txt-owners,wallcheck}.py`, `gates/{gate-surface,gates-pop}.py`. `wallcheck.py` **declares it as
`2: "USAGE"`** and gives it a plant.

**AND THE OLD BEHAVIOUR WAS NOT "FOLD INTO DEAD" — IT WAS A CRASH, WHICH IS WORSE.** Planted:

```
gatekit.main() on a gate returning 2  ->  KeyError: 2
VERDICT has 2? False
bool aliasing: VERDICT[True] == FAIL ; VERDICT[False] == PASS
```

`gate()` and `main()` did `print(f"{name}: {VERDICT[code]}")`, so **the runner aggregating a
`USAGE` gate crashed while reporting on a gate that had answered correctly.** `hooks/run.py:116`
had the same shape as `… else DEAD`. A mapping that raises on a legitimate code is not a
vocabulary, it is a trapdoor.

### THE EDIT (additive, in files I own)

`gates/gatekit.py` gains two functions and `gate()`/`main()` stop indexing the dict:

- **`verdict_of(code)`** → the word, or a NAMED `UNASSIGNED …` string. **Never raises.**
- **`charge(code)`** → **the exit a runner should tally.** Assigned codes return **themselves**;
  only an unassigned code becomes `REFUSED`.

**WHY `REFUSED` AND NOT `DEAD`, PER THE BRIEF:** `DEAD` is a claim about **execution** — only
something that watched the process can make it. A code the table does not define **has not been
shown to have run at all**, so the absent precondition is a *definition*. **A CRASH IS NOT AN
UNASSIGNED CODE, AND THE FIX DOES NOT CONFLATE THEM:** the traceback→`DEAD` rule in `run.py:112-113`
is untouched and remains the **only** place that call is made, because only the caller that saw the
traceback holds that evidence. `charge()` is not given it.

`.agents/slop/hooks/run.py` now loads the table **by path from the owner** and delegates. That also
deletes a **second copy of the five numbers** the runner held — `resolve.py:23`'s "two copies of a
table are blind exactly where they disagree", which is the only place a table is read.

### WHAT CHANGES, AND WHAT DOES NOT

| | before | after |
|---|---|---|
| gate returns `2` | `KeyError` in `gatekit`; `DEAD` in `run.py` | `REFUSED`, **named** |
| gate crashes (rc 1 + traceback) | `DEAD` | **`DEAD` — unchanged** |
| gate exits `4` | `SKIP` | **`SKIP` — unchanged** |
| gates 0/1/3/5 | — | **unchanged: 0 of 47 consumers broken** |

### IT SURVIVES A GENUINE CRASH — PLANTED, NOT ASSERTED

`.agents/slop/exitcode/plant-runner.py` calls **`hooks/run.py:invoke()` itself** (imported by path,
never re-implemented), against real and planted gates:

```
OK   wallcheck NO-SUCH-ID charges          'SKIP'
OK   wallcheck --plant dead charges        'DEAD'
OK   exit 2 charges                        'REFUSED'      <- N3
OK   and is not DEAD                       False
OK   a raised exception charges            'DEAD'         <- N1
OK   and is not REFUSED                    False
OK   exit 4 charges                        'SKIP'         <- N2
OK   exit 0 / exit 1 / silence             'GREEN' / 'FAIL' / 'DEAD'   <- N4
--plant: all states OK
```

**BOTH PLANTS GREEN. `plant.py` 30 assertions rc=0; `plant-runner.py` rc=0.**

---

## 5. THE FOURTH "ALREADY OWNED" — `resolve.py` ALREADY REFUSES AN UNASSIGNED TOKEN

Run, not inherited: **`resolve.py` prints `PLANTS: GREEN (5/5)`** and already refuses a token the
owner does not name — including `wallcheck.py 4 NO-ROW` and `2 USAGE`. **I did not build a second
resolver.** My `charge()` is a different question (a bare integer at runtime, not a gate's declared
table), it is 9 lines, and it answers from the **owner's** table rather than a copy — which is the
distinction `resolve.py:23` insists on.

---

## 6. THE `bool`/`int` TRAP, AND `gate-surface.py:251` — **NOT FIXED, NOT MINE, AND IT IS WORSE THAN DESCRIBED**

**`bool` IS A SUBCLASS OF `int`: `VERDICT[True]` is `FAIL` and `VERDICT[False]` is `PASS`,
MEASURED.** My first `verdict_of` inherited exactly that bug — `if code in VERDICT` is `True` for
`True` — and **my own N4 plant caught it** (`verdict_of(True) names the aliasing: False`). The
`isinstance(code, bool)` guard now runs **first**, and `charge(True)` returns `REFUSED` rather than
silently becoming `FAIL`. **A PLANT THAT FAILS IS THE ONE THAT EARNS ITS KEEP.**

**`gate-surface.py:251` IS WORSE THAN "STALE": IT IS A LIVE CRASH.** Measured — an unparseable gate
makes the instrument **itself** die at its own call site `:359`:

```
ValueError: not enough values to unpack (expected 4, got 3)
```

`:251` returns a **3-tuple**; `:271,:273,:275,:277,:278` return **4-tuples**. **SO: NEITHER LIST
ENUMERATION NOR POSITIONAL UNPACKING IS THE PROBLEM — THE SHAPE IS UNSOUND AT ONE BRANCH, AND NO
AMOUNT OF DISCOVERY FIXES IT.** `gate-surface.py` is not mine; **filed, not applied.** The fix is
one line: `:251` returns `None, None, None, note`.

**DOES MY CHANGE IMPROVE OR WORSEN EITHER?**
- **List-enumeration staleness: NEITHER.** I added no list. `charge()` reads the owner's dict, so a
  sixth verdict added to `gatekit.py` is picked up **without editing a runner** — the enumeration
  moved *into* the owner. **That is an improvement**, and it is the same shape as
  `differ.declared()`: one generator, loaded by path.
- **Positional unpacking: UNTOUCHED and still live at `gate-surface.py:251`.** I neither fixed nor
  worsened it. It is the one defect in this area I did **not** land, and it is the one that can take
  an instrument down.

---

## 7. WHAT I LANDED, WHAT I FILED, WHAT I DID NOT DO

**LANDED (additive, both plants green, 0 of 47 consumers touched):**
- `gates/gatekit.py` — `verdict_of()`, `charge()`; `gate()`/`main()` no longer index `VERDICT`.
- `.agents/slop/hooks/run.py` — table loaded **by path** from the owner; `charge()` delegates; the
  traceback→`DEAD` rule untouched.
- `.agents/slop/exitcode/{reach,subject,plant,plant-runner}.py` — the instruments.

**FILED, NOT APPLIED (not my files):**
- `checks/wallcheck.py:396,400` — print `NO-ROW`/`DEAD`, the names `:681` already declares.
- `gates/gate-surface.py:251` — the 3-tuple that crashes its own call site.

**NOT DONE, AND WHY:** **no commit, no `git add -A`, no amend/rebase/force-push, no `@`.** The index
reset mid-session and another unit committed a deletion of my files; I re-added them **by explicit
path** and left every commit to the session that owns the tree.

**THE ONE VERDICT I WOULD RE-READ FIRST IF THIS REPORT IS WRONG:** `SKIP`. Everything else here is a
measurement I re-ran. `SKIP` was handed to me as a vacant slot, and it is the most-exercised of the
five.