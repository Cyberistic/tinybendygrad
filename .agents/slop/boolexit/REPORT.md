# `bool` IS A SUBCLASS OF `int` — THE CENSUS, THE CONSEQUENCE, AND THE CLASS IT BELONGS TO

**MEASURED 2026-10-07T16:54:56Z under `.venv/bin/python` 3.12.10. Scope, in one sentence: every
`.py` file discovered by `os.walk` under `checks/` and `gates/`, read with `ast` — NOT a regex, NOT
a hand list, NOT a suffix glob.** The population read **150 files** at that instant and it MOVES:
it read 144 at 16:41, 145 at 16:43, 146 at 16:45, 148 at 16:47, 150 at 16:49, because other units
are writing the tree while this census walks it. Every count below carries the timestamp for
`AGENTS.md`'s reason: *"NEVER QUOTE A ROW COUNT WITHOUT THE RULE THAT PRODUCED IT."*

Reproduce: `.venv/bin/python .agents/slop/boolexit/census.py` (and `reach.py`, `plant.py`,
`residual.py`, `selftest.py`, `class.py`, `livehunt.py`). All seven exit 0. No `bend` was run.

---

## 0. WHAT THIS CANNOT SEE, FIRST

The brief asks for this first, and it is the right order, because every number below is bounded by
these holes.

1. **THE CENSUS HAS NO INTERPROCEDURAL ANALYSIS.** `census.py` resolves a container's shape and
   its members within ONE file. A dict built in `differ.py` and probed in `substrate.py` is
   invisible to it, and the site is graded by the *probing* file's own bindings. **279 of the 831
   sites are UNKNOWN** for exactly this reason — the literal contained a name or a `**spread`
   this file cannot resolve. They are counted, not dropped.
2. **299 SITES ARE `DYNAMIC`**: the container is an empty literal, i.e. an **accumulator** whose
   keys arrive at run time (`out[k] = v`). No static tool can say whether a bool will ever be one
   of them. These are the majority hole and they are undecidable without running the program.
3. **THE REACH HALF GRADES BY SYNTAX, NOT BY EXECUTION.** `reach.py` asks "is the index
   expression a comparison?" — a static question. It cannot know that `verdict_for()` returns only
   module int constants *today*; it knows only that it is annotated `-> tuple[int, str]`. The
   LATENT grade therefore means **"no comparison is visible at this site"**, not "no bool arrives".
4. **`float` IS NOT IN THE GRADE AT ALL.** `reach.py` asks about bools. `1.0` is a key hit on
   every table in this report and the grader is blind to it by construction — see §7.
5. **I OWN NO GATE BODY, SO NOTHING WAS FIXED.** The brief says *"land a fix for the LIVE sites
   only"* — the measured LIVE count is **0**, so per its own rule there was nothing to land. §7
   reports the one-line close that is available and is **not landed here**, with the reason.
6. **THIS IS NOT A TYPER.** `mypy` is not installed in `.venv` (`No module named mypy`, measured
   by `AGENTS.md`). A real type checker would answer §7 in one line. The reason this census exists
   at all is that **the tree's type checker cannot run**, so the question has to be answered by a
   tool that can.

---

## 1. THE CLASS, BY DISCOVERY

### The method, stated because the choice is the finding

**AST, NOT GREP.** `prune4`'s lesson is exact: a regex census reported **183 where the truth was
61**, because `\.add\(` matched `seen.add(` on Python sets. The same failure is worse here — `in`
is a keyword, `VERDICT` is a substring of nothing, and `[` appears in slices, comprehensions and
strings. So: `ast.parse`, `ast.walk`, and the container's **type is resolved by walking to the
binding**, never by naming the identifier.

**POPULATION BY DISCOVERY.** `os.walk` + `endswith(".py")` over the two homes the tree itself
declares. `glob("*.py")` and `find -name '*.py'` were both measured by the tree to disagree with
what is on disk; a population an instrument cannot see is not a population.

### Three bugs the census had, each of which produced a CONFIDENT wrong answer

This is recorded because it is the whole reason the numbers needed four attempts to be true.

| bug | what the census reported | what is true |
|---|---|---|
| `ast.literal_eval` on a `Name` | **0 REACHES across 681 sites** | `PASS, FAIL, REFUSED, SKIP, DEAD = 0,1,3,4,5` is a **tuple target**, so every key of `VERDICT` was `None`. The class was not empty; **the constant table was**. |
| `_PARENTS` keyed by `id()`, never reset | every site `no-enclosing-function` | `gatekit.py:97` sits **three lines below a real `isinstance(code, bool)`**. CPython recycles `id()` across trees. |
| `_parents()` returns the DIRECT parent only | guard lookup found no function | `_enclosing_function` never walked *up*. One level is not enough. |
| `BoolOp.op` treated as a list | `AttributeError` killed the run | it is a **single node** on 3.12+. |
| the reach **summary** tested one substring | `GUARDED: 2` over a 3-row table | the classifier found the guard, the tally dropped it |
| the census **sum** omitted a grade | `592 graded vs 724 sites` | `MEMBER-IS-STR` was in the rows and not in the total |

**The last two are now ASSERTIONS rather than careful reading: both tools exit 1 if their grades
do not partition their population.** The census assertion fired on its first run and was right.

**Each of those reported a confident, stable, plausible answer. Three reported "the class is
empty" or "the tree is unguarded" — the two most dangerous shapes an instrument has.** This is
`plantthe46`'s vacuous counterfactual and `AGENTS.md`'s doctrine 1 in one file: an instrument that
cannot fail is not an instrument. `selftest.py` exists to keep that from recurring, and **it has
already caught one of my own false claims** (§6).

### The counts

```
files discovered (population, os.walk over checks/+gates/) : 150
files UNPARSEABLE                                            : 0
`x in C` sites on dict/list/set/tuple                       : 192
`C[k]` sites on a dict                                      : 532   (489 `[k]` + 43 `.get(k)`)
sites a bool REACHES                                        : 14
sites a bool CANNOT reach (str members)                     : 132
sites DYNAMIC (an accumulator -- a hole)                    : 299
sites UNKNOWN (a name or **spread in the literal)          : 279
```

### The 14, by name — scope stated with the count

| file:line | form | table | keys | a bool can reach? |
|---|---|---|---|---|
| `gates/gatekit.py:96` | `in` | `VERDICT` | `0,1,3,4,5` | **YES** — and it is **GUARDED** |
| `gates/gatekit.py:97` | `[k]` | `VERDICT` | `0,1,3,4,5` | **YES** — and it is **GUARDED** |
| `gates/gatekit.py:110` | `in` | `VERDICT` | `0,1,3,4,5` | **YES** — and it is **GUARDED** |
| `checks/substrate-id.py:247` | `.get` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:329` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:347` ×2 | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:367` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:382` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:436` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:448` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:451` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/substrate-id.py:457` | `[k]` | `NAMES` | `0,1,3,5` | **YES** — LATENT |
| `checks/fw_live.py:51` | `.get` | `PSP_ERRORS` | `1..18` | **YES** — LATENT (a device driver, not a gate) |

**And the claim the brief makes is confirmed exactly: `int(True) == 1` means a bool DOES reach
every dict whose keys include `0`/`1` — which is the whole `gatekit.VERDICT` table.** Measured:
`VERDICT[True] == 'FAIL'` and `True in VERDICT` is `True`.

---

## 2. THE CONSEQUENCE, NOT THE PRESENCE

From `plant.out`, running the tree's own code:

| probe | `VERDICT[…]` | what a reader is told |
|---|---|---|
| `True` | `'FAIL'` | **a `True` that MEANS PASS prints FAIL** |
| `False` | `'PASS'` | **a `False` that means FAIL prints PASS** |
| `True in VERDICT` | `True` | **a "false member" verdict IS a member** |
| `VERDICT.get(True)` | `'FAIL'` | **`.get()` does not refuse either** |
| `True + 1` | `2` | it is not an approximation; it is the same value |

**THE FALSE BRANCH, IN THE TREE'S OWN CODE** (`plant.out` §2, the shape before tonight's fix):

```
charge_BEFORE(True)  -> True    <-- TRUE became FAIL(1). SILENT.
charge_BEFORE(1)     -> 1       (the int, indistinguishable)
charge_BEFORE(False) -> False   <-- and False became PASS(0)
charge_AFTER(True)   -> 3       (the fix, gatekit.py:110)
charge_AFTER(1)      -> 1       <-- 0 consumers change; that is WHY it lands
```

No exception. No traceback. No word. That is `exitcode`'s `charge(True)` → `FAIL`, reproduced
against the pre-fix shape with a **`True`**, because a plant with an integer proves nothing.

### LIVE vs LATENT — the grade that is actually useful

| grade | n | meaning |
|---|---|---|
| **LIVE** | **0** | a bool expression indexes an int-keyed table with no guard |
| **GUARDED** | **3** | all of `gatekit.py:96,97,110` — `isinstance(code, bool)` protecting each |
| **LATENT** | **11** | a non-bool expression indexes it, unguarded |

`0 + 11 + 3 = 14`, and **the three tallies are asserted to partition the 14 sites** (`reach.py`
exits 1 if they do not). They did not, twice: the summary first printed `GUARDED: 2` under a
three-row table because the classifier detected the same-expression guard and the tally then
dropped it on a substring test. `census.py` carries the same assertion over its four grades, and
**it fired on its first run** — `592 graded vs 724 sites found` — because the sum omitted
`MEMBER-IS-STR` entirely. Both are the same defect `rebase-gate-selftest` records: *"'0
disagreements' over '0 comparisons' is indistinguishable from agreement."*

**The 3rd gatekit site is guarded by SHORT-CIRCUIT, not by line order** — `gatekit.py:110` reads
`code in VERDICT and not isinstance(code, bool)`, and `and` evaluates left to right, so the table
is never probed for a bool. A line-order test graded the tree's own fix UNGUARDED. That is how a
guard gets "fixed" twice.

**`checks/substrate-id.py:247` is the sharpest of the twelve.** `NAMES.get(rc, rc)`: the `rc` is
a verdict and the whole deliverable of that function is **a word**. A `True` would print
`FAIL` — and because `True` IS a key, **the `.get` default never fires**. An out-of-range *int*
does reach the default; the bool does not, because the bool is a legitimate member.

---

## 3. IS `bool`-AS-`int` THE FIRST INSTANCE? THE CLASS HAS NO NAME, AND THAT IS THE FINDING

From `class.out` — **5 members, 23 rows, 0 mismatches.** Every row was checked to have produced
the expected severity, so the labels are measurements, not the argument.

| member | behaviour in this interpreter | what the tree does about it |
|---|---|---|
| **bool vs int** | **ACCEPTED, SILENT** — `True==1`, `hash(True)==hash(1)`, `True in D` | `not isinstance(x, bool)` at `gatekit.py:94,110` — **one function's width** |
| **int vs float** | **ACCEPTED, SILENT** — `hash(1.0)==hash(1)`, `isinstance(1.0,int)` is `False` | **nothing** — and the bool guard cannot see it |
| **str vs bytes** | **CRASHES** — `TypeError: cannot use a string pattern on a bytes-like object` | mapped to `DEAD` by name at `hooks/run.py:138` |
| **None vs absent** | **ACCEPTED, AMBIGUOUS** — `None` is a first-class key, not a missing one | `.get(k)` vs `[k]` on the same line |
| **Path vs str** | **CRASHES** | an explicit `.as_posix()` at `substrate-id.py:125` |

**THE FINDING, STATED AS THE BRIEF ASKS FOR IT: the class has NO NAME, and that is the finding.**
Python's name for the first two is "numerical tower"; Python has no name for the set, because the
set is not a Python concept — it is a **language-boundary** concept, and Python has no boundaries.

> Every instrument in this tree handles `bool`/`int` **by hand**, `str`/`bytes` **by crashing**,
> `Path`/`str` **by an explicit conversion**, and `None`/`absent` **by a different `.get`-vs-`[`**.
> **None of that is a design decision. It is four accommodations that accumulated.**

`bool`-as-`int` is **not the first instance — it is one of five.** It is the only one of the five
that is **both silent and unguarded anywhere else**, and the only one where the tree has **already
written the fix and still has a hole in it**.

**WHY THE SILENT MEMBER IS WORSE THAN THE CRASHING ONE, MEASURED.** The tree *learns* from a
traceback: `run.py:138` maps `rc == 1 and "Traceback" in out` to `DEAD`, **deliberately and by
name**. Nobody learns from `'FAIL'` where the answer was `'PASS'`.

---

## 4. THE FIX

**LIVE sites: 0. Per the brief's own rule — *"land a fix for the LIVE sites only"* — nothing was
landed, and the brief also says to report the rest.** This section reports the rest.

**`gates/gatekit.py` ALREADY OWNS IT.** `verdict_of` and `charge` both carry the guard, and both
were graded GUARDED by the census. The three instances named in the brief are the SAME instance in
three files:

- `exitcode` — **landed** at `gatekit.py:110`.
- `synonyms` — *reported the fact.*
- `plantthe46` — *reported the 3-tuple vs 4-tuple defect, which is a DIFFERENT class (§3's
  sibling: a value crossing a boundary with the wrong **arity**), not this one.*

---

## 5. DOES THE TREE ALREADY OWN THE SHAPE? **YES — AND IT NAMED ITS OWN RESTRICTION.**

The brief says ask **where**, not whether. **The answer is `gates/gatekit.py`, and the evidence it
already holds is stronger than the question assumed:**

- `gatekit.py:60-61` — the five verdicts as named exits.
- `gatekit.py:94-95` — `verdict_of` checks `isinstance(code, bool)` **FIRST**, and its docstring
  says: *"`bool` IS A SUBCLASS OF `int`, so `verdict_of(True)` is `FAIL` and `verdict_of(False)`
  is `PASS` — which is not a bug here but is a trap for a caller that passes a computed flag. It
  is named rather than silently absorbed, so the aliasing is visible at the call site."*
- `gatekit.py:110` — `charge` returns `code if code in VERDICT and not isinstance(code, bool)
  else REFUSED`, and its docstring records that **0 of the 46 discovered consumers are touched**,
  "which is the property that makes it landable".
- `gatekit.py:86-88` — it already cites `.agents/slop/hooks/run.py:112` for the traceback→`DEAD`
  mapping **by name**.

**So the tree chose to type an exit in exactly one place — and `hooks/run.py:57` says why:
*"this file used to hold a SECOND COPY of its five numbers … Two copies of a table are blind."*
The tree knows the lesson. It has not generalised it from *tables* to *types*.**

---

## 6. THE COST OF NOT LANDING THE LATENT ONES

`prune4`'s grade: **LATENT TODAY, A LIVE FALSE-VERDICT THE MOMENT ONE CALLER PASSES A
COMPARISON.** Named per site, because "latent" without a trigger is not a plan:

| site | what would have to change for it to become LIVE |
|---|---|
| `substrate-id.py:247` `.get` | `verdict_for()` would have to return a comparison instead of `REFUSED`/`PASS`/`DEAD`. **It is annotated `-> tuple[int, str]` and every `return` is a module int constant** — so this needs a *new* return shape, not a new caller. |
| `substrate-id.py:329/347/367/382/436/448/451/457` | the same nine sites, all inside `plant()`, all reading `verdict_for()`'s result. |
| `fw_live.py:51` | `command()` would have to return `error` as a bool. It is `value & 0xffff` — an int. |

**`slowgate` ran a gate for 562 s to prove it was dead, and the price of being wrong about a
`bool` is SILENT: a `FAIL` that should be a `PASS` costs NOTHING to produce and NOTHING to
notice.** That is the **same ranking** `slowgate` derived for false-green vs hang, and it is why
**LATENT IS NOT THE SAME AS SAFE.**

### THE HARNESS FALSIFIED ONE OF MY OWN CLAIMS

`selftest.py` asserts the census can see a bool **and fails when it should**:

```
WRONG: a str key can NEVER be hit by a bool    got='z' want=0
```

**My assertion was wrong, not the code.** I had written `{0:"z"}.get(False) == 0`; the true
answer is `"z"`, because `False == 0` is `True`. The str case is the one that needs the *hash*
argument, and it now has it: `{"a":"z"}.get(False, "DEFAULT") == "DEFAULT"`.

`class.py` had the same failure in a worse costume: it reported `re.search('a', b'a')` as
`NameError` and **labelled it `CRASHES`, which agreed with the expectation and was false** — an
`eval` in a function scope cannot see the module's imports. **A harness that reports the right
verdict for the wrong reason is the most dangerous kind, because nothing downstream can tell.**

---

## 7. DOES A bool FIX CLOSE THE CLASS? **NO — ONE MEMBER OF FIVE.**

**MEASURED, `residual.out` §A–B: `sys.exit(charge(x))` for six inputs.**

| input | exit rc | verdict to a reader | refused by the bool guard? |
|---|---|---|---|
| `True` | **3** | REFUSED | **YES** |
| `False` | **3** | REFUSED | **YES** |
| `1.0` | **1** | FAIL | **no** |
| `0.0` | **1** | FAIL | **no** |
| `1` | 1 | FAIL | no |
| `0` | 0 | GREEN | no |

**`charge(1.0)` returns `1.0` and `sys.exit(1.0)` is exit status 1.** A float reaches the runner
through the same function, past the same guard, and lands on `FAIL`. `isinstance(1.0, bool)` is
`False`, so `not isinstance(code, bool)` does not see it.

**A CORRECTION, MADE IN THE TRANSCRIPT BECAUSE THE TRANSCRIPT IS THE WITNESS: a draft of §B
claimed `0.0` exits GREEN. It does not.** CPython's `sys.exit` accepts an int or `None`; a float is
**printed to stderr and the process exits 1** (measured directly: `sys.exit(0.0)` → rc 1,
`sys.exit(0.5)` → rc 1). So the float's damage is **false-red plus a stray line on the stream the
verdict was supposed to be on** — a worse nuisance than a wrong number alone. Meanwhile
`sys.exit(False)` → **rc 0, GREEN, silently.**

### THE ONE-LINE CLOSE, AND WHY IT IS NOT LANDED HERE

`type(code) is int` in place of `not isinstance(code, bool)` agrees with `charge` on **every
int** — the same 0-consumer change — and differs on **every bool and every float**:

```
charge_type_is_int(1.0) -> 3      charge(1.0) -> 1.0
charge_type_is_int(0.0) -> 3      charge(0.0) -> 0.0
```

**It is not landed because `gates/gatekit.py` IS A GATE BODY and this unit owns no gate bodies.**
Reporting it is the honest move; landing it here would be `AGENTS.md` doctrine 1 in reverse — a
unit editing an instrument it did not census.

**AND WHAT IT WOULD COST, MEASURED, because a "better" fix that breaks a caller is worse than the
defect it fixes:**

```
isinstance(IntEnum.FAIL, int) : True    charge(IntEnum.FAIL) -> IntEnum.FAIL
type(IntEnum.FAIL) is int    : False
```

`type(x) is int` **refuses an `IntEnum` verdict** that `isinstance` accepts. `exitcode`'s
`not isinstance(code, bool)` is the shorter-range choice and it is defensible. **The point is that
its range is one member wide, and the tree now MEASURES that rather than assuming it.**

### THE WIDTH OF THE FIX, MEASURED

```
146  sys.exit(...)  sites in checks/ + gates/, of which 0 name charge
 43  files import gatekit          3 call verdict_of        0 call charge
```

**The bool guard is real and it is ONE FUNCTION'S WIDTH.** The 43 importers get `PASS/FAIL/...` as
bare module constants and call `sys.exit(main())` with whatever `main()` returned. **One place is
not a boundary.**

---

## 8. THE VERDICT, IN THE TREE'S OWN FIVE

| verdict | this report |
|---|---|
| **PASS** | the census ran and answered. 150 files, 0 unparseable, 14 sites, 0 live. `selftest.py` rc=0 and it falsified one of my claims while doing it. |
| **FAIL** | three of my instruments reported a confident wrong answer before the harness caught them (§1, §6). Recorded, not hidden. |
| **SKIP** | none. Nothing here could not run. |
| **DEAD** | none. Every artifact emits rows; `census.out` is 119 KB of them. |
| **REFUSED** | **the fix.** The LIVE count is 0 and this unit owns no gate bodies, so §7's one-line close is reported rather than landed. |

**THE ONE-LINE FINDING:** `bool`-as-`int` is one of five members of an unnamed class; it is the
only member that is **both silent and unguarded outside one function**; the tree **already owns
the shape** in `gates/gatekit.py`; and **the fix the tree landed closes one member of five, because
`1.0` is still a key hit.**

---

## APPENDIX — artifacts

| file | what it is | rc |
|---|---|---|
| `census.py` / `.out` | the class by AST over `os.walk(checks, gates)` | 0 |
| `reach.py` / `.out` | LIVE / LATENT / GUARDED grading | 0 |
| `plant.py` / `.out` | the FALSE BRANCH, planted with `True` against the tree's own code | 0 |
| `residual.py` / `.out` | `sys.exit(charge(x))` for six inputs; the float residual | 0 |
| `selftest.py` / `.out` | **the harness that can fail**, written first; contains an INT control | 0 |
| `class.py` / `.out` | the 5 members by measured behaviour, 23 rows | 0 |
| `livehunt.py` / `.out` | int-annotated functions that can return a comparison (30 hits, 29 are legitimate `-> bool`) | 0 |

No `.txt`. No `bend`. No `git add`, no commit, no amend.