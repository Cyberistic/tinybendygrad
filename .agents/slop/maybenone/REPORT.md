# THE `MAYBE-NONE` CENSUS SAYS 0 OF 291. A UNIT FOUND ONE BY HAND. MEASURED.

Subagent report. Instruments: `.agents/slop/maybenone/{hunt,verify,verify2,sweep,outside,fourclasses,controls,controlC}.py`.
Every number below was produced by a command in this session; nothing is carried from a brief.

---

## 1. WHICH IS TRUE, AND THE AST MEASUREMENT THAT SETTLES IT

**BOTH, AND THEY ARE NOT THE SAME CLAIM. `optim-nop-mutate.py` is NOT the `MAYBE-NONE` shape, and
the census is RIGHT that it is not. The defect is real, live, and one process above the census's
population.**

### 1a. The site is FOREIGN, not MAYBE-NONE — MEASURED, by the census's OWN functions

`gates/exitcode-census-gate.py:222` is `sys.exit(main())` over `gates/optim-nop-mutate.py:156 main()`:

| question | instrument | answer |
|---|---|---|
| what shape? | `classify_site` (the shipped one) | **`FOREIGN`** — `gates/artifacts/exitcode-census/rows.tsv:177` |
| does `main` reach an exit of its own? | `own_exits(tree)` | **∅** — no `sys.exit`/`exit`/`quit`/`raise SystemExit` anywhere in it |
| does `main` run off its end? | `_terminates(main.body)` | **True** — last statement is `return 0` at `:218` |
| can it hand back `None`? | `returns_none(main)` | **False** |
| so | `_callee` | `returns_none` False → not DELEGATED → **`FOREIGN`, CHOSEN** |

`sys.exit(main())` therefore hands `sys.exit` the **integer 0**, a number the author chose. There
is no `None`, no fall-off path, no unchosen value. **The unit's reading of the SHAPE is wrong and
the census's verdict on it is right.**

### 1b. The DEFECT is real and live, and `MAYBE-NONE` cannot name it

`main()` **computes three states, prints all of them, and returns a constant.** MEASURED on one run,
same machine, minutes apart, the file at HEAD and the patched file:

```
BEFORE  git show HEAD:gates/optim-nop-mutate.py   rc=0   4 REFUSED lines   863 MB  16 s
AFTER   gates/optim-nop-mutate.py                 rc=3   4 REFUSED lines   875 MB  12 s
diff optim-before.out optim-after.out  ->  STDOUT BYTE-IDENTICAL, 2249 B BOTH
```

**2249 bytes of identical output, and `$?` moved 0 → 3.** That is the whole finding: a reader of
`$?` alone was told PASS on a run in which **4 of 11 mutations were never applied**.

The four are `P2`, `P4`, `P5`, `Z1`, and MEASURED statically before any `bend` ran —
`mutant_text()` returns `None` unless `src.count(find) == 1`, and **each of those four `find`
strings occurs 0 times in the current `tinybendygrad/nn/optim.bend` (85 937 B)**:

```
key  count(find)  mutant_text
P2       0        REFUSED        P4       0        REFUSED
P5       -        REFUSED        Z1       0        REFUSED
M1 M2 M3 M4 P1 P3 Z2  count 1     text ok
```

So the brief's claim is **TRUE AS A FINDING and FALSE AS A SHAPE**. `MAYBE-NONE` means
"`sys.exit(None)`". What is here is the same *meaning* — a lane that ran and did not answer — reached
by a different mechanism: the author CHOSE `0`, and the choice did not depend on the run.

### 1c. Is there another shape `_terminates` misses? YES — one, and it has **0 live instances**

`_terminates` was wrong twice before (the `try` arm, then `finally`) and was corrected **in the
direction of MORE CANDIDATES**. I walked every hole that would answer "terminates" when the callee
can still fall off. All walked with the census's own `extract`/`classify_site` over the census's own
population `W`, never a hand list (`.agents/slop/maybenone/{hunt,sweep}.py`):

| # | hole in the census | live instances | what I did |
|---|---|---|---|
| **A** | `_callee` asks `delegated` BEFORE `returns_none`, and `delegated` answers "does `f` **CONTAIN** an exit", not "does `f` **REACH** one". `def f():\n  if c:\n    sys.exit(3)` is `delegated` and returns `None` when `c` is false → `sys.exit(None)` = 0 = PASS. **This is the census's own named `DELEGATED` exemplar `checks/vz_gate.py:249`, and its plant row asserts `want_chosen=True`.** | **0** | **CLOSED**: added `_always_exits()` + 2 locking plants. `checks/vz_gate.py:249` hand-read: `verify`'s `sys.exit` at `:106` is at FUNCTION-BODY level AFTER the `for` at `:104`, so it runs whatever the loop does — the exemplar was correctly graded all along |
| **B** | `_terminates` checks `_terminates(try.body) and bool(handlers or finalbody)` and NEVER checks a **handler body**. A `try` whose `except` falls off the end returns `None` on the exception path | **0** of 16 | closed in `_always_exits` (`all(_exits_at(h.body) for h in handlers)`); MEASURED by `verify2.py`, which re-implements `_terminates` while recording every `Try` it graded: all 16 offending `try`s are MID-BODY, never the tail, so the later `return` is still reached |
| **C** | `classify_site` grades a same-module callee FOREIGN without asking what it RETURNS — `sys.exit(main())` where `main` ends `return "no records"` is `sys.exit(<str>)` = 1 | **0** | none needed |
| **D** | `sys.exit(a, b)` — `extract` takes `args[0]`, so the message is printed but ungraded | **0** | none needed |
| **E** | `from sys import exit as x` — `extract` only knows `sys.exit`/`exit`/`quit` by name | **0** | none needed |
| **F** | `async def main()` — `sys.exit(main())` hands `sys.exit` a coroutine | **0** | none needed |
| **G** | `env["funcs"]` is `{n.name: n}` from `ast.walk`, so a name bound twice keeps the LAST | 13 files shadow a name, **0** of the shadowed names is an exit callee | none needed |
| **P** | the census SET is `os.walk` over the **derived gate homes** (`checks` + `gates`) only | **601 tracked `.py` files, 805 exit sites OUTSIDE**, of which **154 are NOT-CHOSEN in 68 files** | REPORT ONLY — out of grant, and `.agents/` is not a gate home |

**A plain reorder would have been WRONG**, and the plant says so: `returns_none` calls
`def f(): sys.exit(3)` a MAYBE, because `not _terminates(f.body)` is true of a body whose last
statement is a call to something else. So the repair is not "which check runs first" but "which
claim each check makes" — hence `_always_exits`.

---

## 2. THE FOUR HARNESS CLASSES × COUNT × VERDICT PER SITE

Instrument `.agents/slop/maybenone/fourclasses.py`. Populations **discovered** by directory walk over
`git ls-files` (never a list): `*-mutate.py` / `*-gen.py` / `*-oracle.py` by `fnmatch`, plant
harnesses by `def plant(`, shell harnesses by `checks/*.sh`. **167 tracked harness sites.**

The question per site is one: **can the process's exit code change when the child lane answers
REFUSED / DEAD / nothing?** `rc_reaches` is a **fixpoint over the entry's own local assignments** (no
depth limit, no guess); it does not follow calls, so a verdict laundered through `report(x)` is
reported as NOT REACHING — the safe direction for a question whose bad answer is "the harness sees it".

### Verdict vocabulary (fixed, no sixth state invented)

| verdict | meaning |
|---|---|
| `SEES-CHILD` | the rc **MOVES** with the child's verdict — **the harness is honest** |
| `CONST-PASS` | constant rc, and there is nothing for it to see — honest |
| `GREEN-ON-REFUSAL` | **constant rc + a live refusal counter that only reaches stdout** — the defect |
| `PRINTS-REFUSAL-UNWIRED` | non-constant rc, but the fixpoint cannot tie it to the counter |
| `COMPUTED-UNTRACED` | the rc goes through a **call**; **not measurable lexically** — reported, not graded |
| `MAYBE-NONE` | a bare `return` reaches `sys.exit` — the census's own shape |
| `NO-EXIT-SITE` | nothing reaches `sys.exit` |

| class | n | breakdown |
|---|---|---|
| **`*-mutate.py`** | **28** | NO-EXIT-SITE 14 · CONST-PASS 9 · **GREEN-ON-REFUSAL 2** · PRINTS-REFUSAL-UNWIRED 1 · COMPUTED-UNTRACED 1 · **SEES-CHILD 1** |
| **`*-gen.py`** | **6** | NO-EXIT-SITE 4 · CONST-PASS 2 |
| **`*-oracle.py`** | **93** | NO-EXIT-SITE 78 · CONST-PASS 10 · **MAYBE-NONE 3** · **GREEN-ON-REFUSAL 1** · COMPUTED-UNTRACED 1 |
| **plant harnesses** | **40** | NO-EXIT-SITE 8 · CONST-PASS 9 · **COMPUTED-UNTRACED 22** · PRINTS-REFUSAL-UNWIRED 1 |
| **shell** | **17** | **12 of 17 emit a number `gatekit` does not assign** |

### The 6 sites that are not honest, named

| site | class | verdict | evidence | grant |
|---|---|---|---|---|
| `gates/optim-nop-mutate.py:170` | mutate | **was GREEN-ON-REFUSAL → now SEES-CHILD** | **LIVE: 4 of 11 refuse, rc was 0, now 3** | **MINE — FIXED** |
| `gates/amd_dsl_census-mutate.py:365` | mutate | **GREEN-ON-REFUSAL** | counters `guard_fail,moved_any,refused` printed at the tail; `return 0`. **LATENT: 0 of 30 entries statically refuse** | mine — **NOT fixed, see §6** |
| `gates/crp_graph_census-mutate.py:584` | mutate | **GREEN-ON-REFUSAL** | same three counters; `return 0`. **LATENT: 0 of 52 entries statically refuse** | mine — **NOT fixed, see §6** |
| `.agents/slop/graphcmp-dbg-oracle.py:55` | oracle | **GREEN-ON-REFUSAL** | counter `failed`, `return 0` | not mine — slop |
| `.agents/slop/exitcodes-maybenone/silent-wgsl-oracle.py:946` | oracle | **MAYBE-NONE** | bare `return` reaches `sys.exit` | another unit is IN that directory |
| `.agents/slop/i64shl/shl-oracle.py:91`, `.agents/slop/ishr/shr-oracle.py:129` | oracle | **MAYBE-NONE** | bare `return`; slop copies of the `gates/i64-*-oracle.py` the census already repaired | not mine |

**All 3 MAYBE-NONE sites are OUTSIDE `W`**, so the exitcode census is structurally blind to them —
that is hole **P** again, and it is the one that would have mattered most.

### The two `-gen.py` findings the brief names — CONFIRMED BY HAND READ

`gates/ops_python_census-gate.py:313` `names_hold()`: `oracle_rows()` returns `(None, why)` when the
oracle exits non-zero (`:276`), and the caller does `bad.append(why)` — **the same list as
`"row i: port X, oracle Y"`.** A crashed oracle is billed as a `FAIL` row. `ops_python_exec-gate.py:277`
does the same with `report("coverage_hold", [f"--coverage failed rc=..."])`. **CONFIRMED, both, by
reading the call sites. NOT FIXED — `gates/ops_python_*-gate.py` is not this unit's grant.**

### The plant class, and the brief's `dropbranch`

`gates/docnum-claim-gate.py` and `gates/runner.py` both read **COMPUTED-UNTRACED** — their rc goes
through a call (`return {'PASS': PASS, …}`, `return gatekit.PASS if ran == …`), so **lexically they
are not gradeable and I will not claim a verdict on them.** 22 of 40 plant sites are in that state.

**`dropbranch` is not where the brief says.** `grep -rn dropbranch gates/ checks/` → **one** file:
`gates/falseclaim-census-gate.py:411`, with `:297` already recording *"exits 1 through a `TypeError`,
which is a crash, not a verdict"*. **So that instance is KNOWN AND DOCUMENTED, not undiscovered.**

### The shell class — the brief's 12 of 17 is EXACT

```
checks/*.sh total 17;  uses ONLY gatekit's five {0,1,3,4,5}: 5;  uses an UNASSIGNED number: 12
  11 of the 12 offend with `2`   bounded-selftest demo disarm e2e gate run-all run-f64
                                run-port-mm substrate-check walk-mutate wt-sync
  1 offends with `6`             sb-gate.sh (emits 0,1,3,5,6)
```
**MEASURED 12, matching the brief. REPORTED ONLY — `checks/*` is not this unit's grant.**

---

## 3. THE FIXES, AND THE EXECUTION THAT PROVES EACH, WITH ITS CONTROL

### FIX 1 — `gates/optim-nop-mutate.py`: the exit IS the run

Three states the harness already computed, each given **`gatekit`'s** number (imported, not retyped),
combined by **`gatekit.py:766 gate()`'s own rule — FIRST NON-PASS WINS, and a later finding can only
move `PASS` somewhere else. No precedence table invented, no sixth state.**

| state | number | why that one |
|---|---|---|
| a `find` that matched nothing or twice | **REFUSED (3)** | "a precondition was absent" — the edit site is gone |
| `bend` ran and emitted no rows | **DEAD (5)** | "it ran and emitted nothing"; REFUSED would bill a **present** precondition as absent |
| an entry moved nothing, not expected to | **FAIL (1)** | the table carries a rule no row observes |
| baseline unreadable | **REFUSED (3)**, was 1 | the run did not happen; FAIL said the TABLE was wrong |

**EXECUTION.** `.venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- .venv/bin/python gates/optim-nop-mutate.py`
→ **`[bounded] WITHIN-LIMITS rc=3 peak-RSS=875 MB (ceiling 2048) 12s`**, 4 `REFUSED` lines
(`P2`,`P4`,`P5`,`Z1`), `5 of 7 mutations moved rows`, `2 moved nothing … 2 of those 2 were EXPECTED`.

**CONTROL 1 — THE SAME RUN ON THE PRE-PATCH FILE.** `git show HEAD:gates/optim-nop-mutate.py > gates/.optim-before-tmp.py`,
same command → **`rc=0 peak-RSS=863 MB 16s`, 4 `REFUSED` lines, and `diff` of the two stdouts is EMPTY.**
**Identical 2249 bytes, `$?` 0 → 3.** The fix changes nothing a reader gets except the verdict.

**CONTROL 2 — the DEAD branch is reachable and named (fake, no compiler).** `.agents/slop/maybenone/controls.py`
stubs `mutkit.bend_rows`: good for the BASE, `({}, 1)` for every mutant → **`rc=5 DEAD`**. Not 0, not 3.

**CONTROL 3 — the FAIL branch is reachable and named (fake).** every call returns the same rows, so
every entry moves nothing and only `M4`/`Z2` are expected → **`rc=1 FAIL`**. Not 0.

**CONTROL 4 — THE FIX IS NOT "ALWAYS RED" (real compiler).** `.agents/slop/maybenone/controlC.py` runs
only the 7 entries whose `find` still matches → **`rc=0 PASS`, `0 refused`**,
`[bounded] WITHIN-LIMITS rc=0 peak-RSS=895 MB 15s`.

### FIX 2 — `gates/exitcode-census-gate.py`: close hole **A**, plant it, move **0** rows

`_always_exits(fn)` (+ `_is_exit_call`, `_exits_at`) and `_callee` becomes
`if returns_none(fn) and not _always_exits(fn): MAYBE-NONE` before the `delegated` branch. **Two new
PLANT_CASE rows that differ from the file's existing `DELEGATED` row by ONE WORD.**

**EXECUTION.** `--plant` → **rc=0, 28 shapes + 4 decision states + 5 verdicts + 1 collision, 0 `BAD`**
(was 26 shapes), `26 MB / 0.42 s`.

**CONTROL — the two classifiers DISAGRE, and the rows table does not move.**
```
case                                        BEFORE      AFTER
OLD 'def f(): sys.exit("x")'                 DELEGATED   DELEGATED      <- plant preserved
NEW 'def f():\n  if c:\n    sys.exit("x")'    DELEGATED   MAYBE-NONE     <- the hole, now closed
    'if c: ... else: sys.exit(3)'             DELEGATED   DELEGATED
checks/vz_gate.py:249 (the live exemplar)    DELEGATED   DELEGATED      <- 0 live flips, as swept
```
Full run both sides: **`rows.tsv` BYTE-IDENTICAL, 256 sites, `MAYBE-NONE` 0, rc 1 → 1.** The 1 is a
**pre-existing** `STR` at `gates/ops_python_census-oracle.py:303` (another unit's file) — this gate
was **already red before I touched it**, so no green became red.

---

## 4. `MAYBE-NONE` COUNT BEFORE AND AFTER, AND rc

| | before | after |
|---|---|---|
| **`MAYBE-NONE`** | **0** | **0** |
| exit sites in `W` | 256 | 256 |
| `rows.tsv` | — | **byte-identical** |
| `--plant` | rc 0, 26 shapes | **rc 0, 28 shapes, 0 BAD** |
| census rc | **1** | **1** (pre-existing `STR`, not mine) |

**The census's `0` is CORRECT and stays `0`.** The site the brief points at is `FOREIGN`, the four
live `MAYBE-NONE` sites the brief does not know about are all **outside `W`**, and the one real hole
in the classifier has **0 live instances**. `MAYBE-NONE` was never going to find this.

## 5. PEAK RSS AND RUNTIME

No `bend` was running before any of these (`ps -Ao pid,rss,comm | grep bend` → empty). Every `bend`
run under `checks/bounded.py --mb 2048`, `WITHIN-LIMITS` each time. `.agents/slop/peakrss/census.rows:49`
records `tinybendygrad/nn/optim.bend` at **383 MB**; the harness is the wrapper around it.

| run | rc | peak RSS | wall |
|---|---|---|---|
| `optim-nop-mutate.py` AFTER (real bend ×7) | 3 | **875 MB** | 12 s |
| `optim-nop-mutate.py` BEFORE (real bend ×7) | 0 | **863 MB** | 16 s |
| control C (real bend ×7) | 0 | **895 MB** | 15 s |
| controls A + B (fakes, no bend) | 5 / 1 | trivial | <1 s |
| `exitcode-census-gate.py --plant` | 0 | 26 MB | 0.42 s |
| `exitcode-census-gate.py` | 1 | 98 MB | 3 s |

## 6. FOUND BUT NOT DONE — AND WHY

1. **`gates/amd_dsl_census-mutate.py` and `gates/crp_graph_census-mutate.py` are NOT patched.** Same
   defect, and both in my grant. Their refusal branch is **LATENT, not live: 0 of 30 and 0 of 52
   entries statically refuse** (each `old` counted against that harness's OWN uniqueness rule, which
   for crp is `all(src.count(o) == 1 for o in old)`, and one `crp` entry `C8` carries a LIST `old`).
   I did not patch them because **I cannot execute them**: each entry runs a full census gate plus
   `bend`, so 82 gate runs on a tree at **load 54 on 12 cores with four users**. A fix I cannot run is
   exactly the unverified fix the brief warns against. **HANDOFF: `return 0` at the tail of each
   `main()`, with `refused`/`guard_fail`/`moved_any` computed at `:600` and printed.**
2. **`gates/ops_python_census-gate.py:313` / `ops_python_exec-gate.py:277`** collapse a non-zero
   child rc into a `FAIL` row. CONFIRMED by read. Not my grant.
3. **Hole P, the population edge: 601 tracked `.py`, 805 exit sites outside `W`, 154 NOT-CHOSEN in 68
   files**, incl. **all 3 live `MAYBE-NONE` sites**. `.agents/` is not a gate home, so
   `gates-pop.py:gate_homes()` cannot see it and this gate structurally cannot. Not my grant.
4. **`gates/ops_python_census-oracle.py:303` `sys.exit(<str>)`** is the ONE `NOT CHOSEN` row and the
   sole reason the census is rc 1 today. Not my grant; **it is what a caller will hit first.**
5. **The 22 `COMPUTED-UNTRACED` plant/mutate sites** (including `gates/runner.py` and
   `gates/docnum-claim-gate.py`) — **I will not grade these.** Their rc goes through a call; a lexical
   fixpoint does not follow calls, and inventing a sentinel here would be the failure mode the brief
   names. **A harness that cannot see its child's verdict should SAY SO; it does not get a number
   from me.**
6. **`checks/*.sh`, 12 of 17 off-vocabulary.** Report only.
7. The three `.agents/slop/*` MAYBE-NONE oracles and `graphcmp-dbg-oracle.py`. Slop, other units.