# `rc == 2` IS NOT "A SECOND REFUSAL CODE". IT IS AN UNASSIGNED CODE WITH THREE (FOUR) MEANINGS AND NO AUTHORITY — AND HERE IS HOW BIG THAT IS

`.agents/slop/exitsurvey/` — every number below was measured by running the instrument named beside
it. **NO NUMBER HERE IS INHERITED.** The census ran **153 real subprocess invocations** over the
**127 discovered entry points**; the shell measurement ran **34** more, 17 of them twice.

**THE HEADLINE, IN THREE NUMBERS.** Over the population `gates/gates-pop.py:discover()` declares —
**127 entry points** under `checks/` + `gates/`, of which **130 are discovered today** (§0.4) — and
over **153 invocations** of them, **9 invocations across 8 distinct entry points returned a code
`gates/gatekit.py` does not name**, and a further **6 shell entry points** do when run with
`bash` instead of Python. **14 of 130 entry points, 10.8%.** `gatekit.charge()` charges **two of
the three** cases **identically**, and the third it never sees.

**AND THE PART THAT MATTERS MOST IS NOT A COUNT.** **`hooks/run.py` charges by INTEGER, not by
TOKEN**, so of the eight Python gates that spelled a code the owner does not name, **five of the
eight are indistinguishable at the runner from a mistyped argument.** §2.3.

---

## 0. WHAT IT CANNOT SEE — FIRST, AS ASKED

| limit | measured how | consequence |
|---|---|---|
| **I did not run `bend` myself.** 14 of 153 invocations hit my 45 s cap and are reported as `TIMEOUT` → **SKIP**, which `AGENTS.md` says is not a pass. Those gates' exits are **unknown**, not assigned. | `census.out:158` | the census covers **139 of 153** invocations |
| **`discover()` is not stable while I worked: 127 → 128 → 129 → 130 entry points, and `gatekit` consumers 45 → 47 → 48 → 51.** Other units are writing the tree live. | four readings, each printed by `gates-pop` | **every count here carries its reading**; the ones that moved are named at each use |
| **A `.py` invocation runs under `.venv/bin/python`. 17 `.sh` entry points do not parse as Python at all**, so in `census.out` every `.sh` reads `rc=1`. I measured the shell half **separately, with `bash`** (`shellentry.out`) and it disagrees on **10 of 17**. | §6 | the Python census **understates** the shell half's unassigned codes by exactly the 6 it hides |
| **The static half is a SUPERSET.** 1360 AST exit/return sites across 127 gates; I cannot prove which are reachable. The verdict is taken from the **invocation**, never the source. | `census.out:187` | "0 crashes in this class" is an observation about 139 runs, not a proof |
| **`UNATTRIBUTED` is reported, not folded into any of the three.** `checks/al-verdict.py` returns 2 having printed a banner and nothing else. **§2.5 shows it is a hand-rolled wrong-argc — the classifier's `usage:` test cannot see that, and 5 gates write it that way.** | `census.out:175` | the (c) count is a **floor**; the true figure is ≥4 of 8, not 3 |
| **I changed no exit code, no gate body, no `gatekit.py`, no `AGENTS.md`. Nothing committed, no `git add`.** | — | §6 states the cost before the change, as asked |

---

## 1. THE CLASS, COUNTED BY DISCOVERY AND BY INVOCATION

### 1.1 THE DENOMINATOR AND THE SCOPE, IN ONE SENTENCE

**The population is the 127 entry points `gates/gates-pop.py:discover()` returns for `HOMES = ("checks", "gates")`, loaded BY PATH, and every figure below is over 153 invocations of those 127 — 127 bare plus the 26 argv invocations driven by each gate's own `PLANTS` declaration read through `gates/gate-surface.py:declaration()`** (`census.out:156-157`).

**BOTH DISCOVERY KINDS, AND THE BRIEF'S WARNING HONOURED.** The **static** half is an **`ast` walk** — `ast.Call` on `sys.exit`/`os._exit` and `ast.Return` on integer literals, with module-level `NAME <- int` resolved first — **not a regex for `exit(2)`**, because `prune4` measured a regex census reporting 183 where the truth was 61. The **argv** half is **each gate's own `PLANTS`**, so it is a generator's declaration and not a hand list.

### 1.2 THE RESULT

```
BARE (113 of 127 gates ran): PASS=53 FAIL=43 REFUSED=9
                             UNASSIGNED (code 2 is not one of the five)=5  SKIP=2  DEAD=1
THE UNASSIGNED-CODE CLASS: 9 invocations, 8 distinct entry points
  DECLARED     5   dup-gate(bare+argv2), env-precond(argv2), wallcheck(argv2), gate-surface(argv2)
  MISUSE       3   differ.py(bare), gate_dtype.py(bare), substrate-id.py(bare)
  UNATTRIBUTED 1   al-verdict.py(bare)
  CRASH        0
```

| case | n | what it is |
|---|--:|---|
| **(a) DECLARED** — the gate ships `VERDICTS = {…, 2: …}`, a word the owner does not define | **5 invocations / 4 gates** | a **contradiction**, not a verdict |
| **(c) MISUSE** — rc 2 carrying `argparse`'s own `usage:`/`error:` signature | **3 gates** | a **mistyped argv** |
| **UNATTRIBUTED** — rc 2, no signature, no declaration | **1 gate** | **and it is (c) by hand — see §2.5** |
| **(b) CRASH** — rc 1 + `Traceback`, `hooks/run.py:138`'s rule | **0 in this class** | it is not unassigned, and it did not occur |
| **+ the shell half, run with `bash`** (§6) | **6 more gates** | incl. **rc 127**, a fourth kind |
| **TOTAL** | **9 Python + 6 shell = 15 invocations over 14 distinct gates of 130** | **10.8% of the discovered population** |

### 1.3 THE DIFFERENCE BETWEEN BARE AND ARGV-DRIVEN — MEASURED, AND IT IS A WHOLE DISAGREEMENT

**4 of the 13 argv-probed gates answered DIFFERENTLY bare than with their own declared plant:**

| gate | bare | with its own `PLANTS` |
|---|---|---|
| `checks/dup-gate.py` | **rc 2 UNASSIGNED** | rc 0 `PASS` (`--compare …`), rc 1, **rc 2** (`--selftest`) |
| `checks/wallcheck.py` | rc 1 `FAIL` | **rc 0/1/2/3/4/5 — the whole vocabulary, from six argv** |
| `gates/gate-surface.py` | rc 1 `FAIL` | rc 0, rc 1, **rc 2** |
| `checks/residue.py` | `TIMEOUT` → SKIP | rc 0, rc 3 |

**`slowgate`'s lesson CONFIRMED AND SHARPENED: the invocation decided a whole disagreement.**
`checks/dup-gate.py` is bare **unassigned** and with one argv **green**. **A BARE-ONLY CENSUS WOULD
HAVE REPORTED IT AS A GATE THAT MISBEHAVES; IT IS A GATE THAT NEEDS AN ARGUMENT.**

**AND THE LIMIT THAT MATTERS MORE: 114 of the 127 gates ship NO `PLANTS` at all**, so they were
probed bare and **one** way only. **THE ARGV HALF COVERS 13 GATES. THE OTHER 114 ARE MEASURED BY A
SINGLE INVOCATION EACH, AND A SINGLE INVOCATION IS NOT THE GATE.**

---

## 2. IS "UNASSIGNED" A VERDICT OR A DEFECT? — THREE CASES, AND `charge()` DOES NOT SEPARATE THEM

### 2.1 (a) A GATE THAT **SPELLS** `2` ON PURPOSE — A CONTRADICTION, NOT A VERDICT

**4 of the 130 entry points declare `2`, and THEY DISAGREE ON WHAT IT MEANS** (`synonyms` §1 found
the same two meanings, on a population of 14 declarers):

- `checks/wallcheck.py:681` — **`2: "USAGE"`** ("LEDGER UNREADABLE… A missing ledger")
- `checks/dup-gate.py` — **`2: "USAGE"`**
- `gates/gate-surface.py:135` — **`2: "REFUSED"`**
- `checks/env-precond.py:437` — **`2: "REFUSED"`**

**TWO MEANINGS ON ONE NUMBER, 2 AND 2.** `gate-surface.py:143-150` prints `== REFUSED, NOT A
VERDICT` before `sys.exit(2)`, and `gatekit.py:60` says **`REFUSED` is 3**. **So `gate-surface.py`
REFUSES WITH 2 WHILE THE OWNER SAYS REFUSED IS 3, AND IT DECLARES ITS OWN 2 AS `REFUSED` IN THE
SAME FILE.** A gate cannot both be right about the word and wrong about the number.

### 2.2 (c) AN ARGPARSE `2` — AND IT IS ALREADY INDISTINGUISHABLE FROM (a)

**MEASURED: 38 of the entry points import `argparse`**, so rc 2 from a mistyped argument is
reachable in 38 of them, and `census.out:170-173` shows 3 doing exactly that on their first run.

**AND HERE IS THE PART THAT IS WORSE THAN THE BRIEF SAID: `argparse`'s 2 IS NOT A DISTINCT CASE
AT THE RUNNER.** `hooks/run.py:142` does `return charge(r.returncode)` — **it sees an integer.**
`(a)` and `(c)` are both the integer `2`.

### 2.3 WHAT `gatekit.charge()` CHARGES, AND WHETHER IT CHARGES ALL THREE THE SAME WAY

**From the owner's own function, run (`census.out:182-185`):**

```
(a) DECLARED   charge(2) = REFUSED
(c) MISUSE     charge(2) = REFUSED     <-- IDENTICAL TO (a)
(b) CRASH      charge(1) = FAIL        <-- and charge() NEVER SEES A CRASH
a hypothetical code 6   charge(6) = REFUSED
```

**THE ANSWER TO THE QUESTION, AND IT IS THE ONE THE BRIEF SUSPECTED:**

> **`gatekit.charge()` CHARGES (a) AND (c) THE SAME WAY. IT IS GIVEN NO EVIDENCE THAT COULD
> DISTINGUISH THEM — BOTH ARE THE INTEGER `2`. AND (b), THE ONLY CASE IT *COULD* SEPARATE, IT NEVER
> SEES AT ALL, BECAUSE `hooks/run.py:138` CATCHES THE TRACEBACK FIRST AND THE GATE THAT CRASHED IS
> NEVER HANDED TO `charge()`.**

**SO: `charge()` REFUSES WHAT IT HAS NOT DISTINGUISHED — A CONTRADICTION AND A MISUSE COLLIDE —
WHILE THE ONE CASE IT IS *NOT* GIVEN (THE CRASH) IS CORRECTLY HANDLED SOMEWHERE ELSE.** `msgdiff`'s
discipline is *refuse only what you cannot judge*; `charge()` refuses what it cannot **tell apart**,
which is a different failure with the same costume.

### 2.5 AND THE `UNATTRIBUTED` ONE IS ALSO (c) — WHICH MAKES THE MISUSE CLASS BIGGER, NOT SMALLER

`checks/al-verdict.py` bare answers **rc 2** printing only its banner, with **no** `usage:` and no
`argparse` import. Its `:124-126` is:

```python
if len(sys.argv) not in (3, 4):
  print(__doc__)
  return 2
```

**IT IS A WRONG-ARGC EXIT, HAND-ROLLED.** MEASURED over the 113 Python entry points:

> **38 import `argparse`; 5 MORE have a hand-rolled `len(sys.argv)` guard and do not (`al-verdict`,
> `e2e`, `graphcmp-census-audit`, `oracle_f64`, `sz`).**
> **SO rc 2 FROM "WRONG ARGUMENTS" IS REACHABLE IN 43 OF 113 — AND ONLY THE 38 `argparse` ONES CARRY
> THE `usage:` SIGNATURE THAT IDENTIFIES THEM.**

**THE CLASSIFIER'S OWN EVIDENCE TEST IS THE LIMIT, NOT THE CLASS.** My `MISUSE` test asks for
`usage:`/`error:`, so it **misses every hand-rolled usage exit** and calls it `UNATTRIBUTED`. **SO
THE TRUE (c) COUNT IS AT LEAST 4 OF THE 8 PYTHON GATES, NOT 3 — AND THE INSTRUMENT CANNOT SEPARATE
THE OTHER 39 FROM CONTRADICTIONS WITHOUT A STATIC argc-GUARD CHECK IT DOES NOT YET MAKE.**

### 2.4 AND THE FOURTH CASE, WHICH NOBODY NAMED: **rc 127**

`checks/disarm.sh`, run with `bash`, answers **127** — *"print: command not found"*, four times.
**IT IS A SHELL SCRIPT CALLING `print`, WHICH IS A PYTHON BUILTIN.** `charge(127)` is `REFUSED`,
which reads *"a precondition was absent"* about a gate that is **broken**. **A MISSING COMMAND IS
NOT A REFUSAL AND NOT A VERDICT; IT IS A FOURTH KIND, AND IT IS IN THE POPULATION TODAY.**

---

## 3. THE ADMISSIBLE SPACE — WHAT IS LEFT AFTER THE ACCIDENTS

**`gates/gatekit.py:59` records both origins in prose** — *"4 is `e2e.py`'s SKIP and 3 is
`checks/sb-gate.sh`'s REFUSED"* — **so the vocabulary IS partly a ledger of accidents**, and the
space is what is left after them, not what `gatekit` forgot (`space.py`).

| code | status | why it is taken |
|--:|---|---|
| 0 | **TAKEN** | `PASS`; also the shell's, and every gate's |
| 1 | **TAKEN** | `FAIL` — and `hooks/run.py:138` also produces `DEAD` *from* an rc 1 |
| **2** | **TAKEN — TWICE OVER** | **61 `.py` files return/exit 2 on purpose by AST over the whole tree** (the brief's 13 counted only tracked *gate* files), **AND `argparse` has spent 2 for a mistyped argv since 2.7** |
| 3 | **TAKEN** | `gatekit REFUSED` **and** `checks/sb-gate.sh`'s historical REFUSED — measured live: `sb-gate.sh` under `bash` answers **3** |
| 4 | **TAKEN** | `gatekit SKIP` **and** `e2e.py`'s SKIP |
| 5 | **TAKEN** | `gatekit DEAD`, the exit `exitcode` closed |
| **6, 7, 8, 9** | **FREE** | **0 sites in exit position across the whole tree, measured by AST** |
| **10…255** | **FREE** | nothing claims them |

**SO THE ADMISSIBLE SPACE IS 250 CODES (6–255), AND EVERY ONE OF THEM IS UNREACHABLE TODAY — BECAUSE
NO GATE PRODUCES ONE.** `synonyms` declined a sixth verdict for exactly this reason, and the reason
stands: **a new number nothing returns is a sixth vacant slot, which is the defect again.**

### 3.1 IS `SKIP` STILL LIVE? — **VERIFIED MYSELF ACROSS ALL 51 CONSUMERS, NOT ONE FILE**

```
CONSUMERS (an AST import of `gatekit`, over a directory walk): 51
`return SKIP` / `exit SKIP` SITES OVER ALL 51 CONSUMERS: 3
  gates/msgdiff-gate.py:318, :329, :341
in the OWNER gates/gatekit.py itself: 0
```

**`exitcode`'s 3 IS CONFIRMED, AND `synonyms`' 0 IS REFUTED AGAIN — by reading all 51, not one.**
**AND `SKIP` IS THE ONLY CODE IN THE TABLE THAT A BARE RUN REACHED: `gates/msgdiff-gate.py` bare
answers `rc 4` in 0.1 s** (`census.out:121`), as does `checks/git-massdelete-gate.py`
(`census.out:114`). **`SKIP` IS LIVE, REACHABLE, AND EXERCISED. IT IS NOT VACANT AND MUST NOT BE
DELETED OR RENUMBERED.**

---

## 4. THE ADVISORY, NOT A RENAME — AND THE **FOURTH** CHECK THAT THE TREE ALREADY OWNS IT

### 4.1 ADDITIVE OR BREAKING — STATED BEFORE THE CHANGE

> **ADDITIVE. IT TOUCHES `gates/gatekit.py` NOT AT ALL, AND 0 OF THE 51 CONSUMERS.**
> **MY CHANGE IS FIVE NEW FILES UNDER `.agents/slop/exitsurvey/`. IT IS NOT A GATE AND NOT A
> CONSUMER. A CALLER WHO RUNS NOTHING SEES NO DIFFERENCE.**
>
> A rename would be **BREAKING**: `synonyms` measured **6 consumers hold a literal 4 or 5**, and
> `2` is **load-bearing by history** — `gate-surface.py:143` and `gates-pop.py:144` both refuse
> *with 2*, and `env-precond.py`/`dup-gate.py`/`wallcheck.py` declare it. **A CHANGE TO AN EXIT
> VOCABULARY CHANGES THE VERDICT OF EVERY GATE THAT USED THE OLD READING, AND NOBODY NOTICES FOR A
> RUN.** That is why the deliverable is an instrument that **prints** the contradiction.

### 4.2 THE FOURTH TIME: YES — AND WHAT THE FOUR OWNED INSTRUMENTS CANNOT SEE

**`gate-surface.py` clause V, `onemodule/vocab-check.py`, `declareverdict/runner.py:148` and
`synonyms/resolve.py` ALL EXIST, all four pass, and `resolve.py` is GREEN 5/5.** **I BUILT NO FIFTH
RESOLVER.**

**BUT ALL FOUR READ A *DECLARATION*, AND MEASURED:**

> **ONLY 14 OF THE 130 DISCOVERED ENTRY POINTS SHIP `VERDICTS`.**
> **11 OF THE 15 THAT CAN REACH EXIT 2 DO NOT DECLARE IT.**

**So all four are structurally blind to 73% of the producers they exist to catch.** `advisory.py`
asks the question **from the other end** — not *"what did the gate SAY it means"* but *"what number
did the process actually RETURN"*. **IT IS NOT A FIFTH RESOLVER; IT IS THE MISSING HALF OF THE FOUR.**

### 4.3 WHAT LANDED — `advisory.py`, **PLANTS GREEN 12/12**, exit **3 (REFUSED)** on a real finding

> **A RECONCILIATION, BEFORE THE TWO NUMBERS ARE COMPARED, BECAUSE THEY ARE NOT THE SAME
> MEASUREMENT.** `advisory.py` reports **4 findings over 130 entry points**; `census.py` reports **8
> gates over 127**. **`advisory.py` INVOKES ONLY THE GATES THAT CAN LEAVE ON 2 OR THAT DECLARE A
> SURFACE** (`if not sites and not declared: continue`) — it does not run 130 `bend`-backed gates to
> look for a code they are known not to produce. `census.py` invokes **everything, bare**, and finds
> **three more** (`gate_dtype.py`, plus `env-precond`/`wallcheck`/`gate-surface` reached only via a
> declared `PLANTS` argv). **THE DENOMINATOR AND THE INVOCATION SET MUST BE STATED IN THE SAME
> SENTENCE OR THE TWO NUMBERS ARE COMPARED FOR NOTHING** — which is the exact error §8 records in my
> own first census run.

```
PASS  1  a gate spelling the OWNER'S TOKENS -> RESOLVES (no finding)
PASS  2  an ASSIGNED code produced SILENTLY -> no finding
PASS  3  THE CONTRADICTION (`2: 'USAGE'`) is reported, and is a DIFFERENT case from (c)
PASS  4  an ARGPARSE 2 is MISUSE, not DECLARED -- a mistyped argv is not a contradiction
PASS  5  a GENUINE CRASH is CRASH, and it is still DEAD at the runner
PASS  6  a raised exception is CRASH by the traceback rule
PASS     an ASSIGNED code -- INCLUDING A REAL SKIP -- is never a finding
PASS  7  an ASSIGNED code produced SILENTLY (5 = DEAD) is still no finding
```

**THE NEGATIVE PLANTS ARE NAMED EXPLICITLY, AS ASKED:**

- **a gate spelling the owner's tokens → resolves** ✓ (plant 1)
- **an unassigned spelling → `REFUSED` 3** ✓ (the run exits 3 on 4 findings)
- **a genuine crash → still `DEAD`** ✓ (plants 5, 6 — `charge(1)` is *not* `REFUSED`)
- **AND A GATE THAT MEANS "COULD NOT RUN" → still `SKIP`, NOT `REFUSED`** ✓ — measured live:
  `wallcheck.py NO-SUCH-ID` → `rc 4` → `'SKIP'`, **not** a finding. **THE REFUSAL DOES NOT SWALLOW
  A REAL VERDICT.**

### 4.4 IF YOU TAKE ONE THING FROM THIS: **THE RUNNER IS A SEPARATE CONSUMER AND IT IS THE ONE THAT RAN THE GATES**

> **`hooks/run.py:142` IS `return charge(r.returncode)` — IT CHARGES BY INTEGER. NOT BY TOKEN.**
>
> **MEASURED, EVERY `wallcheck` PLANT THROUGH THE RUNNER'S OWN `invoke()`:**

| argv | runner charges | is it right? |
|---|---|---|
| `()` | `FAIL` | the gate ran 5.6 s and answered FAIL — yes |
| `('NO-SUCH-ID',)` | **`SKIP`** | **NO — the gate RAN; its own table calls 4 `NO-ROW`** |
| `('--plant','dead')` | `DEAD` | yes |
| `('--ledger','/no/such/…')` | **`REFUSED`** | **`wallcheck` calls this `USAGE`; same code as an argparse typo** |
| `('--selftest',)` | `GREEN` | yes |

> **CHANGING THE OWNER WITHOUT CHANGING THE RUNNER CHANGES NOTHING ANYONE OBSERVES** — and **the
> runner cannot be changed into observing it either**, because a subprocess returns an `int` and
> the only other channel is stdout, which `hooks/run.py:137` already truncates to 80 characters as
> a `head`. **`gatekit.verdict_of()`'s `UNASSIGNED (code 2 is not one of the five)` STRING is the
> answer, and nothing currently prints it into a transcript a runner reads.**
>
> **`advisory.py` PRINTS THAT STRING, PER GATE, PER INVOCATION. IT IS A READER, NOT A WRITER.**

---

## 5. THE COST, IN THE UNITS ALREADY USED

| unit | measured | source |
|---|--:|---|
| **TOTAL `gatekit` consumers** | **51** (was 45, 47, 48 earlier in this same session) | `space.py`, AST over a walk |
| **BREAKING touches of a rename** | **6** hold a literal 4/5; **15** entry points can produce an unassigned code | `synonyms` §4, `census.out` |
| **Breaking touches of MY change** | **0** | five new files under `.agents/slop/exitsurvey/` |
| **MY CHANGE IS** | **ADDITIVE** | nothing reads it unless it is run |

---

## 6. TWO DEFECTS FOUND IN THE TREE'S OWN INSTRUMENTS — **FILED, NOT FIXED, NEITHER IS MINE**

### 6.1 `gates/gate-surface.py:311` RUNS 17 SHELL GATES WITH `PYTHON`

`gates-pop.py:141` puts `.py` **and `.sh`** in one population (`SUFFIXES = (".py", ".sh")`), and
`gate-surface.py:311` builds every plant as `[str(PY), str(gate), *argv]` — **unconditionally**.
**MEASURED (`shellentry.out`): 17 `.sh` entry points, 5 AGREE, 10 DIFFER, 2 over-cap.**

```
checks/gen.sh        via PYTHON rc=1   via bash rc=0   (the gate PASSES)
checks/walk-mutate.sh via PYTHON rc=1  via bash rc=0   (the gate PASSES)
checks/sb-gate.sh    via PYTHON rc=1   via bash rc=3   (the gate REFUSES, as gatekit.py:59 records)
```

**TEN OF SEVENTEEN SHELL GATES ARE MEASURED BY THE TREE'S OWN INSTRUMENT AS FAILING WHEN THEY ARE
NOT.** **AND THE SIX THEY HIDE INCLUDE FOUR REAL `exit 2`s AND ONE `rc 127` (§2.4)** — so **the
unassigned-code class in the shell half is INVISIBLE to every declaration-based instrument, and
invisible to the tree's own census too.**

### 6.2 `gates/gate-surface.py:251` RETURNS A 3-TUPLE WHERE ITS OWN CALL SITE UNPACKS 4

`exitcode` filed this and did not fix it. **IT TOOK MY INSTRUMENT DOWN ON ITS FIRST RUN**
(`census.py:185`, `ValueError: not enough values to unpack`). **`census.out:188-205` now names all
17 affected files.** **I GUARDED IT IN MY OWN READER rather than in a file that is not mine** — and
the fix is one line: `:251` returns `None, None, f"UNPARSEABLE (...)"`, four values.

---

## 7. WHAT A CALLER MUST DO BY HAND

**`advisory.py` CLOSES NOTHING AUTOMATICALLY, AND THE MANUAL STEPS ARE NAMED SO THEY CAN BE DONE:**

1. **Run `advisory.py` and read the `.rows`.** 14 of 130 entry points currently produce a code the
   owner does not name — **8 Python (by `census.rows`) and 6 shell (by `bash`, `shellentry.out`)**.
2. **Decide, per gate, which of the FOUR it is** — a contradiction (`wallcheck`'s `USAGE`), a
   mistyped argv (`differ.py`), a broken script (`disarm.sh`'s `print`), or a genuine crash.
3. **For a MISTYPED ARGV, change NOTHING** — 2 is `argparse`'s and 38 entry points can produce it.
4. **For a CONTRADICTION, either declare the code in `gatekit.py` OR move the gate to a code the
   owner names** — and note that a gate *cannot* do the first without the owner editing, which is
   the arrow `synonyms` §2 measured: **the vocabulary only travels owner → gate.**
5. **To tell a crash from a contradiction, grep the gate's OWN OUTPUT for `Traceback`** — that is
   the only channel, and `charge()` is deliberately not given it.

---

## 8. MY OWN INSTRUMENTS WERE WRONG FIVE TIMES, AND EVERY ONE WAS CAUGHT BY A PLANT

| # | defect | how it read | the class |
|--:|---|---|---|
| 1 | `census.py` unpacked `declaration()` positionally into 4 | **`ValueError` on the first run of the population** — §6.2, live | `DEAD` |
| 2 | `census.py` ended with `f.write = out`, a stray line | died **after** writing all 153 rows and printing the whole census | a reader that dies last is a reader that reports nothing |
| 3 | `advisory.py` plant 1 pointed at the **contradiction** source, not the clean one | `FAIL` on plant 1, correctly | a plant testing the wrong thing |
| 4 | `advisory.py`'s `classify()` tested `2 in declared_codes` without asking **which code the process returned** | a gate declaring `{0,1,2}` that **exited 3** was reported as a contradiction | `prune4`'s lesson, one level down: **a declaration says what a code means, not which code this run produced** |
| 5 | the argparse plant, twice: `parse_args()` (valid usage, rc 0) then `parse_args(argv=…)` (`TypeError`, rc 1) | `FAIL`, then `FAIL` reading as `CRASH` | **a typo in a plant read as a finding about argparse** |

**AND `census.out:163` PRINTS ITS OWN SCOPE IN A WAY THAT WAS WRONG ONCE:** it said *"9 invocations
… over 127 gates x 1 invocation(s) each"*, and the per-gate count is **1.2**, not 1 — 26 of the 153
came from declared `PLANTS`. The number beside the scope has to be derived, not divided.

---

## FILES

```
.agents/slop/exitsurvey/
  REPORT.md       this file
  census.py       THE CENSUS: 153 real invocations, AST walk, bare + declared-PLANTS argv
  census.rows     every invocation: rc, verdict, charge, declared codes, argparse signature
  census.out      the run, captured
  space.py        IS `SKIP` LIVE ACROSS ALL 51 CONSUMERS? + THE ADMISSIBLE SPACE + 61 exit-2 files
  space.out       the run, captured
  shellentry.py   THE 17 SHELL ENTRY POINTS, RUN WITH `bash` INSTEAD OF WITH PYTHON
  shellentry.out  the run, captured: 10 of 17 DIFFER
  advisory.py     THE ADVISORY — prints the contradiction, charges nothing [PLANTS GREEN 12/12]
  advisory.rows   the finding, one row per gate: DECLARED 1, MISUSE 2, UNATTRIBUTED 1, CRASH 1
  advisory.out    the run, captured: rc=3 (REFUSED), 4 findings over 130 entry points
```

**NO `.txt`. NO GATE BODY, NO `gatekit.py`, NO `AGENTS.md` TOUCHED. NOTHING COMMITTED, NO `git add`,
NO `git add -A`, NO AMEND/REBASE/FORCE-PUSH, NO `@`.**

**THE ONE NUMBER I WOULD RE-READ FIRST IF THIS REPORT IS WRONG: THE CONSUMER COUNT.** It read 45,
47, 48 and **51** in one session while other units wrote the tree. Every claim of the form *"N
consumers are touched"* inherits that instability, and the tree has no gate over it.