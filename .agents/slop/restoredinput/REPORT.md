# restoredinput — TWO DEFECTS FOUND BY RESTORING TWO DELETED INPUTS, AND **NEITHER FIX IS THE FIX THE BRIEF PROPOSED**

`restoredinput`, 2026-10-07. Files: `checks/dup-gate.py`, `checks/hermetic-census.py`,
`.agents/slop/restoredinput/plant.py`, `.agents/slop/restoredinput/plant.rows`.
**NOT COMMITTED. NOT STAGED. `git diff --cached` names none of these five paths** — verified.

---

## 0. WHAT IT CANNOT SEE — FIRST, AS ASKED

**1. NEITHER FIX TOUCHES THE MODULE-SCOPE REFUSALS. THEY ARE STRUCTURAL AND
`modulerefuse` PROVED THEY MUST NOT MOVE.**

MEASURED with `.agents/slop/modulerefuse/discover.py`'s **AST half only** — imported by path,
`main()` never reached, so no gate was executed by the census:

```
MODULE-SCOPE REFUSALS: 17 files carry a refusal CALL SITE at module scope
```

| shape (17) | fires at rest (8) |
|---|---|
| `abi4_gate` `abi_gate` `both-census` `census` `cl-port-gate` `dup-census` `dup-gate` `gate` `gate_norm` `hermetic-census` `jsfix_gate` `nl-gate-noguard` `nl-gate` `norm_check` `nvrows-deadrow-gate` `oracle_f64` `rn-gate` | `cl-port-gate` `dup-census` **`dup-gate`** `gate` **`hermetic-census`** `nl-gate` `oracle_f64` `rn-gate` |

(The brief's "NINE" is the count that **FIRES**; the 17 is the count that has the **SHAPE**.
`modulerefuse/discover.py`'s own docstring is the instrument that insists on the distinction: *"A
refusal CALL SITE at module scope is a SHAPE. Whether it FIRES is a MEASUREMENT."* `zerogate`
counted **eight**, `coindependent` **nine**, `modulerefuse` **nine** — **three numbers in the tree
for one set, and mine reads 8.**)

**MY DELTA: shape 17 → 17 (ZERO). Fires-at-rest 8 → 6 (−2, both mine).**

**SO THE ANSWER TO THE QUESTION ASKED IS: NO, NEITHER FIX CHANGES THAT NUMBER OF GATES — AND THE
OTHER HALF IS STILL SIX GATES NOBODY CAN PLANT.** They are the gates whose refusal is
*unconditional or whose input is not recoverable in place*:

| still-unplantable | why, MEASURED |
|---|---|
| `checks/dup-census.py:73` | refuses on `checks/lanes` **not being a directory** — not a swept file, so no restore reaches it |
| `checks/gate.py:70` | `zerogate` §2(b): the input **MOVED**; `371cc64c9^:checks/drive.mjs` fails, the blob is at `.agents/slop/jsfp8/drive.mjs` |
| `checks/cl-port-gate.py:80` | input absent, blob path not established by any report I read |
| `checks/nl-gate.py:81` | needs `.agents/slop/nl/nl-oracle.py` — **I did not restore it**, out of scope |
| `checks/oracle_f64.py:84` | needs argv (`<workdir> <mm-rows>`), not a file |
| `checks/rn-gate.py:90` | needs `eq-census2.py` — **which I DID restore**, so it now *runs* and its `PLANTS[3]=[]` is MISPLANT (§5) |

**THE SURFACE I WORKED ON IS THE EASY HALF AND I AM NOT CLAIMING THE OTHER HALF.**

**2. `hermetic-census.py`'s `0` IS NOT PLANTED AND WAS NOT PLANTED, AND IT CANNOT BE BY ME.**
`0` runs `census()` → `isolate.emit(name, "bend")` → `graphcmp.py:1949` `subprocess.run([BEND, …])`.
I am forbidden to fork `bend`. `PLANTS` for that gate is therefore `{}` and
`gates/gate-surface.py` keeps `0` and `3` **UNPLANTED**. That redness is DATA, not a gap I closed.

**3. I FORKED `bend`, TWICE, UNINTENTIONALLY, AND SAID SO RATHER THAN QUIETLY DROPPING IT.**
- **Once:** after fixing an `IndentationError` I ran `checks/hermetic-census.py` bare assuming it
  would refuse. The inputs were present (my plant's payload), so it ran the **whole 34-graph
  census** and exited `0` — `# graphs in corpus: 34 · reached BOTH: 70 · WALLS: []`. It also wrote
  **68 published artifacts** into `checks/rows/`. I deleted all 68 (`rm -rf checks/rows`; the
  directory was **untracked**, `git ls-tree` count 0). They were `.rows` — the rename below had
  already landed, so the one thing that saved me was my own fix.
- **Once:** re-taking the "fires at rest" count in §0 by executing all 17 bare. `checks/gate_norm.py`
  printed `bend -o emitted no JS:`. **I should not have executed the 17 at all** — the question
  asked was a *delta*, which only two files can move, and I had both numbers already. Cost: two
  `bend` forks, one artifact directory created and removed, no tracked file touched.

**4. NO ROW COUNT IN THIS REPORT IS FROM A RUN THAT MAY STILL BE RUNNING.** Every number below was
read back from a completed command.

---

## 1. DEFECT (1) — `checks/dup-gate.py:338` RETURNS `2`. **REPRODUCED, AND THE VERDICT IS `USAGE`, NOT `DEAD`, NOT `REFUSED`.**

### The state that reaches `:338`

```
$ .venv/bin/python checks/dup-gate.py        # eq-census2.py PRESENT, argv names neither --compare nor --port/--oracle
give --port and --oracle, or --compare BEFORE AFTER, or --selftest with both
rc=2
```

**`dup-gate.py` HAS A MODULE-SCOPE REFUSAL — IT IS AMONG THE SEVENTEEN, ROW 7 OF THE TABLE ABOVE —
AND THE BRIEF'S PREMISE IS WRONG ABOUT WHY IT RUNS.** `dup-gate.py:69`/`:75` refuses **only when
an input is ABSENT**. `.agents/slop/eq/eq-census2.py` is recoverable (24 098 B at `371cc64c9^`) and
I restored it, so the precondition is satisfied, the parser is reached, and **`2` is reachable**.
`modulerefuse` proved the refusal must not MOVE. **It did not prove it always FIRES, and nobody had
checked which.**

### THE REAL DEFECT IS NOT THE EXIT CODE. IT IS THE DECLARATION, AND IT WAS FALSE IN BOTH HALVES.

`checks/dup-gate.py:345-356` (at HEAD) said `PLANTS = {3: []}` and, in prose:

> `PLANTS[3]` IS THE REFUSAL PLANT, and **it is the only state argv can reach** … **no argument of
> any shape gets past it**. `[]` therefore reaches `3`, **and nothing else ever will.**

`gates/gate-surface.py --report` **MEASURED IT FALSE ON THE PRESENTED TREE**:

```
before: checks/dup-gate.py  declared 0/1/2/3  reached (none)  red=UNTAKEN
   RED UNPLANTED 0 'PASS' -- declared, no plant
   RED UNPLANTED 1 'FAIL' -- declared, no plant
   RED UNPLANTED 2 'USAGE' -- declared, no plant
   RED MISPLANT  3 'REFUSED' -- plant [] produced 2
   RED UNOWNED   2 'USAGE' -- gates/gatekit.py has no name for this exit code
```

**FIVE reds, one of them `MISPLANT` — a plant that measures something other than what it claims.
That is the tree's own name for a false witness.** `MILE`D by the same run:
`checks/hermetic-census.py … MISPLANT 3 'REFUSED' -- plant [] produced 1`.

### WHAT VERDICT SHOULD `:338` BE? **`USAGE` — unchanged. THE BRIEF'S PROPOSAL IS WRONG, AND `gatekit` ALREADY SAID SO.**

`checks/dup-gate.py:338 RETURNS 2 → 3` is **BREAKING** in two directions and I recommend **against** it:

1. **`gates/gatekit.py:75`** — verbatim: *"a gate returning `2` — **which 13 files in this tree do
   on purpose**, `USAGE` by `checks/wallcheck.py`'s own declaration among them."* The owner of the
   vocabulary has already ruled `2` legitimate.
2. **`gates/gatekit.py:97` `verdict_of()`** — `2` maps to `"UNASSIGNED (code 2 is not one of the
   five)"`, **not** to `DEAD`. And its docstring argues the exact distinction the brief asked me to
   state: *"`DEAD` is 'it ran and emitted nothing' — a claim about EXECUTION, which only something
   that watched the process can make. **A code this table does not define has not been shown to
   have run at all.**"* `2` RAN — it printed a usage line. Scoring it `DEAD` claims a run nobody
   witnessed, and `2` **witnessed itself**.
3. **`.agents/slop/exitcode/plant.py:74`** — a PLANTED assertion that `VERDICT[2]` raises
   `KeyError(2)`, printed as `OK … the reason gate() must not index the dict`. **Adding `2` to
   `gates/gatekit.py`'s `VERDICT` breaks a planted assertion, and I do not own that file.**
4. **`2` IS ALSO `argparse`'s OWN EXIT CODE.** `.agents/slop/declareverdict/REPORT.md` §7.3:
   *"**A THIRD SOURCE OF `2`, MEASURED BY ACCIDENT:** `gates/gate-surface.py --plant green red .`
   (an unquoted shell word) is **argparse's usage error, exit 2**."* Moving `dup-gate`'s usage state
   to `3` while `argparse` still owns `2` **collapses caller error into gate refusal** — a mistyped
   argv would read "a precondition was absent". Wrong in the other direction, same collision.
5. Moving it to `3` would also erase this gate's **USAGE/REFUSED distinction**: it declares both
   today, and `checks/env-precond.py`/`gates/gate-surface.py` spell `2` as `REFUSED` while
   `dup-gate`/`wallcheck` spell it `USAGE`. **ONE NUMBER, THREE SPELLINGS** (`onemodule/REPORT.md`).

### ⚠ A CORRECTION TO THE BRIEF'S PREMISE ABOUT THE RUNNER

The brief asks me to choose between changing the exit to `REFUSED`(3) and changing
`.agents/slop/hooks/run.py:116` to charge unassigned codes as `REFUSED`. **I recommend NEITHER, and
the reason is that the tree has already made this decision in the one file that owns the vocabulary
— `gates/gatekit.py` — and `hooks/run.py` is the STALE copy.**

`hooks/run.py:116` is `return (r.returncode if r.returncode in NAME else DEAD)`. `gatekit.py:68-95`
exists precisely to supersede it, and says so. **The distinguishing rule the brief asked me to
state — "a crash has a traceback and an unassigned code does not" — is already implemented as
OUTPUT, not exit code**: `hooks/run.py:112` is `if r.returncode == 1 and "Traceback" in out`. So the
runner fix is one line and costs **0 broken consumers**:

```python
# .agents/slop/hooks/run.py:116 — ONE LINE, NOT LANDED (I do not own this file)
return (r.returncode if r.returncode in NAME else (DEAD if "Traceback" in out else REFUSED)), head, …
```

**AND I RECOMMEND AGAINST IT ANYWAY, FOR A MEASURED REASON.** It would silently repair **four**
gates — `dup-gate.py`, `env-precond.py`, `wallcheck.py`, `gate-surface.py`, all `UNOWNED 2` per
`gate-surface --report` — **without one of them being fixed**, and `gates/gate-surface.py`'s
`UNOWNED` class — the instrument whose whole job is to NAME this — **would go quiet while the defect
remained**. A runner that guesses is a runner that stops reporting. **Fix the declaration at the
source; leave the instrument red.** `.agents/slop/hooks/` is outside my two files, so it is
**reported, not landed.**

---

## 2. WHAT DEFECT (1) COST — BREAKING OR ADDITIVE, WITH THE CONSUMERS COUNTED

`git grep` over the **tracked tree** (`git ls-tree -r HEAD`, never `git ls-files`), not over the
file. **The exit path is `sys.exit(main())` → `$?`.**

| consumer | `file:line` | reads | breaking? |
|---|---|---|---|
| `.agents/slop/hooks/run.py` | `:116` | every gate's rc through `NAME = {0,1,3,4,5}` | **0 broken** — `dup-gate.py:338` is not one of 4 rows |
| `gates/gate-surface.py` | `:307 reach()` | `PLANTS` argv → rc | **CHANGED, and that is the fix**: 5 reds → 2 |
| `.agents/slop/zerogate/plant.py` | `:105 run()` | bare argv for its 5 cells | **0 broken** |
| `.agents/slop/gatesrun/finalize.py` | `:34` | a class-name dict, not a code | 0 |

**VERDICT: MY CHANGE TO `dup-gate.py` IS 100 % ADDITIVE.** `VERDICTS` is **byte-identical** at
HEAD and now — `2: "USAGE"` is untouched. The exit code is untouched. **The ONLY edit is
`PLANTS` + the prose that lied about it.**

### THE PLANTS ARE MEASURED, AND TWO OF THE THREE INPUTS ARE FOUND, NOT INVENTED

| declared | argv | rc | token |
|---|---|---|---|
| `0` | `--compare gates/cstyle-live.rows gates/cstyle-live.rows` | **0** | `AUDIT OK` |
| `1` | `--compare gates/cstyle-live.rows oracles/usb-oracle-BEFORE.rows` | **1** | `AUDIT FAILED` |
| `2` | *(bare argv)* | **2** | — |
| `3` | **NOT PLANTED, DELIBERATELY** | — | with the inputs present **no argv reaches 3**; `PLANTS[3]=[]` measures 2, which is `MISPLANT` — a lie. **An UNPLANTED verdict is a true gap; a MISPLANTED one is a false witness.** |

`gates/cstyle-live.rows` is the tracked repaired fixture `AGENTS.md` names for stage 7.
`oracles/usb-oracle-BEFORE.rows` is a **tracked lane that already carries 2 duplicate names** —
found by walking the 1 018 tracked `.rows` files through the gate's OWN `dupes()`, **96 of them
carry duplicates**, so the red plant is the tree's own and not a synthetic file.

### THE MEASURED DELTA

```
before: declared 0/1/2/3  reached (none)   red=UNTAKEN   5 reds
after:  declared 0/1/2/3  reached 0/1/2     red=FAILURE  2 reds  (UNPLANTED 3, UNOWNED 2)

II SURFACE: 42 verdicts declared, 22 reached  ->  25 reached
IV UNTAKEN (8)  ->  IV UNTAKEN (7)
MISPLANT, tree-wide: 3  ->  1   (the survivor is checks/rn-gate.py, §5, not mine)
V EXIT CODES: 4  ->  4     *** UNCHANGED, AND THAT IS THE POINT ***
```

`UNTAKEN → FAILURE` is a real move: `gate-surface.py:299` classifies `UNTAKEN` as *"declared … but
its rc-0 plant never reached 0"*. **dup-gate now HAS a green to have fallen from.**
`V EXIT CODES` staying at **4** is the load-bearing result: `UNOWNED 2 'USAGE'` is `gatekit`'s
`UNOWNED` class working, **not a defect in my file**.

---

## 3. DEFECT (2) — `checks/hermetic-census.py` ACCEPTS A RESTORE PATH IT CANNOT IMPORT. **REPRODUCED. BOTH PATHS MEASURED. NEITHER IMPORTS.**

The gate's own predicate, `checks/hermetic-census.py:71` at HEAD:

```python
if not any(p.is_file() for p in (HERE / "isolate.py", REPO / ".agents" / "slop" / "hermetic" / "isolate.py")):
```

**THE ANSWER TO "MISSING FILE, WRONG `sys.path`, OR A NAME THAT MOVED?" IS ALL THREE — ONE PER PATH.**

### PATH A — `.agents/slop/hermetic/isolate.py` (the path the gate names, and `zerogate`'s payload)

**PRESENT, `is_file()` TRUE, `sys.path` WRONG:**

```
$ .venv/bin/python checks/hermetic-census.py --help
  File ".../checks/hermetic-census.py", line 78, in <module>
    import isolate
ModuleNotFoundError: No module named 'isolate'
rc=1                                  ← + a TRACEBACK. `hooks/run.py:112` scores this DEAD.
```

`sys.path` at `:76` is `REPO` and `_GRAPH.parent` = `.agents/slop`. **Neither contains
`.agents/slop/hermetic/`.** The existence predicate and the import mechanism are two different
things, and only one of them was wired.

### PATH B — `checks/isolate.py` (the gate's other accepted name — `HERE`)

**`sys.path[0]` HAPPENS TO BE THE SCRIPT'S OWN DIRECTORY — UNDER ONE INVOCATION STYLE ONLY:**

```
$ .venv/bin/python checks/hermetic-census.py --help     # rc=0, and for the WRONG reason:
usage: hermetic-census.py [-h] …                        # it is a passenger of hermetic-census's own
                                                          # `sys.path.insert(0, .agents/slop)` at :76
$ .venv/bin/python <by-path importer> checks/hermetic-census.py
  File ".../checks/isolate.py", line 36, in <module>
    import graphcmp as G
ModuleNotFoundError: No module named 'graphcmp'
```

`isolate.py:36` is `REPO = HERE.parents[2]` — correct at `.agents/slop/hermetic/`
(`hermetic/ → slop/ → .agents/ → repo`), **stale one level shallower**, giving
`/Users/cyberistic/src`. **MEASURED, PATH A's `REPO` resolves to the repo and its child
`PY = <repo>/.venv/bin/python` EXISTS; PATH B's does not.** A by-path importer is how *every*
declaration reader in this tree loads a gate (`hooks/run.py:13-18`, `gate-surface.py:266`).

**PATH B IS THE WORSE OF THE TWO: A CRASHES LOUDLY, B LIES QUIETLY.** B would spawn
`/Users/cyberistic/src/.venv/bin/python`, the child would fail, `isolate.emit` would raise
`SystemExit("emitted 0 rows")`, `census()` would catch it as a **WALL** — and the gate would print a
plausible coverage number over an absent subject.

### ⚠ THE `indextree` THIRD CLASS — CHECKED, AND IT IS **NOT** PRESENT IN EITHER FILE

`plantthe46/reach.py` unpacks **3** from `declaration()`, which returns **4**. Same question, both
of my files, by AST (never by import) and then **at runtime**:

```
dup-gate.py:126       unpack 3 from refusals()   declared :110 returns [3]   OK
dup-gate.py:115       unpack 4 from SCAN()  (= eq-census2.py:scan, imported)
  eq-census2.py:176 scan() returns 4 values AT RUNTIME -> OK
hermetic-census.py:186 unpack 3 from census()    declared :120 returns [3]  OK
```

**Runtime proof, not just AST: 6 successful `dup-gate.py` plant cells each call `refusals()` →
`SCAN()`.** Neither file has the arity defect.

---

## 4. WHAT DEFECT (2) COST, AND WHY THE FIX IS **BOTH** OPTIONS, IN THIS ORDER

The brief offers *restore the import path* **or** *refuse when the path cannot be imported*. **I
did both, and they are not alternatives — one without the other is not a fix.**

**THE IMPORT **SHOULD** BE RESTORED**, and the measured reason is `droppedinput`'s own distinction:
*"a freeze of a tree with a hole is faithful, but a gate over an absent subject has nothing to
say."* `isolate.py` is not a freeze target — it is `hermetic-census.py`'s **denominator producer**
(`# reached BOTH: 70 <- the honest coverage number`, the gate's own words). **A gate with no
denominator is `REFUSED`, not `0`.** These two cases differ and neither answer fits both.

**AND THE RESTORE IS WHERE, NOT WHETHER.** The faithful restore is **byte-identical at
`.agents/slop/hermetic/isolate.py`** (4 181 B, `sha256[:12] = e6edd55d413a`), because that is the
path where `isolate.REPO` is **correct** (MEASURED) — so the fix is **one `sys.path` line in a file
I own and ZERO edits to a file I do not.** Moving it to `checks/isolate.py` would have required
editing its `parents[2]`, i.e. editing another unit's file to satisfy a path I chose. The gate's
own line `:70` already says *"Restoring a swept instrument is not this file's call."*

**THE REFUSAL IS REQUIRED, AND IT IS THE ONE THIS PROJECT KEEPS CHOOSING.** `envguard` and
`env-precond` both landed *"MISSING INPUT → REFUSED, EXIT 3, NO TRACEBACK"* because *"a gate that
crashes where it should refuse cannot distinguish 'the input is absent' from 'I am broken'."*
**A `sys.path` fix alone cannot see PATH B at all** — PATH B imports cleanly under the script
invocation and only breaks under a by-path importer. The predicate must be **importability**, so:

```python
# checks/hermetic-census.py — the shape, landed
_ISOLATE_DIRS = (HERE, REPO / ".agents" / "slop" / "hermetic")
_ISOLATE = next((d / "isolate.py" for d in _ISOLATE_DIRS if (d / "isolate.py").is_file()), None)
if _ISOLATE is None: refuse("input absent: isolate.py (… restored from git at 371cc64c9^:…)")
sys.path.insert(0, str(_ISOLATE.parent))
try:
    import isolate                       # BaseException, not Exception: sys.exit at import is also a refusal
except BaseException as _e:
    refuse(f"input PRESENT but not IMPORTABLE: {_ISOLATE} -> {type(_e).__name__}: {_e}. …")
```

### ⚠ A SECOND DEFECT FOUND WHILE FIXING IT, IN MY OWN FILE

`checks/hermetic-census.py:108-114` at HEAD carried a **`TODO(no-txt)`** naming this exact hazard:
the `census()` write was `.txt` and *"UNREACHABLE today — the module-level `refuse()` calls
`sys.exit(3)` at IMPORT, before `import isolate`, so `census()` never runs … restore `isolate.py`
and this fires. Rename it here **AND** the reader in `check()` beside it … before restoring."*

**I RESTORED `isolate.py`. SO IT FIRED.** I did the rename — `.txt` → `.rows` in **both** the
writer (`:114`) and the reader (`:150`) — **before** restoring, as instructed. `checks/rows/` was
**empty (0 files)**, so the rename cost nothing and there is no published artifact to repoint.
**`checks/no-txt.py` rc=0, and that TODO is closed.** It was the only `TODO` in either file.

---

## 5. THE COLLATERAL MY RESTORE CAUSED, IN A GATE I DO NOT OWN

**`checks/rn-gate.py` SHARES `eq-census2.py` WITH `dup-gate.py` (`rn-gate.py:93` names the same
file), SO RESTORING IT UN-BROKE `rn-gate.py`'s DECLARED REFUSAL PLANT.**

```
with eq-census2.py ABSENT,  bare argv: rc=3   ← PLANTS[3] = [] is correct
with eq-census2.py PRESENT, bare argv: rc=1   ← MISPLANT 3 'REFUSED' -- plant [] produced 1
```

**`rc=1` IS A REAL `FAIL`, NOT A TRACEBACK** — `rn-gate.py` ran its lanes and reported a lane
failure (`render-gate-oracle.py`, also swept). **So the gate is HEALTHIER than before: it went from
*unable to run at all* to *measuring and failing honestly*.** Its declaration is now wrong in one
place, which `gates/gate-surface.py` names. `zerogate` restored this same file and had **no `rn-gate`
cell** in `cells()`, so it never saw this.

**ONE-LINE DIFF, NOT LANDED (not my file):**
```python
# checks/rn-gate.py:497-498
VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
PLANTS  = {3: []}          →   PLANTS = {}      # `[]` measures 1 with the input restored
```

**`checks/dup-census.py` WAS AFFECTED AND IS SAFE — MEASURED BEFORE TRUSTING IT.** `zerogate`
measured that a bare `dup-census.py` run **overwrites a tracked 797 251-byte `dup-census.json`
with a 1-line `[]`**. I did not trust that and did not assume:

```
before: 88cf4751cfd69184  797251 B   →  dup-census rc=3  →  after: 88cf4751cfd69184  797251 B
```

**UNCHANGED**, because `dup-census.py:73` refuses for an **unrelated** reason: `checks/lanes` is
**not a directory**. So the destructive vacuous-green does **not** reproduce from my restore.
`rn-gate.py` is the only collateral, and it is one line, and it is not a crash.

---

## 6. THE PLANT — 13 ROWS, 0 NOT-OK, `.agents/slop/restoredinput/plant.rows`

**THE SHAPE IS `.agents/slop/zerogate/plant.py`, READ AND NOT DUPLICATED.** One difference: its
payload is a temporary plant it deletes again; **mine is a RESTORE**, because these two files are two
gates' required inputs and `AGENTS.md` puts a gate's input BESIDE THE GATE IN GIT. So the residue
contract is **inverted** — both swept paths PRESENT and byte-identical to `371cc64c9^`, and the one
wrong path ABSENT — and **both halves are re-read from disk, not from a boolean this file set.**

```
state                  gate                argv                                       rc token         ok
at rest (input absent) dup-gate.py         (bare argv)                                 3 REFUSED       YES
at rest (input absent) hermetic-census.py  (bare argv)                                 3 REFUSED       YES
planted                eq-census2.py       371cc64c9^:.agents/slop/eq/eq-census2.py    0 PLANTED        -   24 098 B
planted                isolate.py          371cc64c9^:.agents/slop/hermetic/isolate.py 0 PLANTED        -    4 181 B
planted                dup-gate.py         --compare gates/cstyle-live.rows gates/cstyle-live.rows 0 AUDIT OK  YES   GREEN
planted                dup-gate.py         --compare … oracles/usb-oracle-BEFORE.rows   1 AUDIT FAILED YES  RED
planted                dup-gate.py         (bare argv)                                 2 -             YES   USAGE
planted                dup-gate.py         --port … --oracle …                         0 AGREE         YES   value lane
planted                dup-gate.py         --port … --oracle … --selftest              0 SELFTEST OK   YES   4 cells
planted-BROKEN         hermetic-census.py  --help                                      3 REFUSED       YES   *** NEGATIVE ***
planted                hermetic-census.py  --help                                      0 -             YES   *** POSITIVE CONTROL ***
after                  both swept paths    -                                          0 RESTORED      YES   2/2 byte-identical
after                  checks/isolate.py   -                                          0 ABSENT        YES   the path that must REFUSE
PLANT OK (13 rows, 0 not-ok)
```

### THE NEGATIVE PLANTS ARE NAMED, AND BOTH KINDS ARE HERE

**(a) THE `REFUSAL` PATH → `REFUSED` 3, NO TRACEBACK.** The `planted-BROKEN` cell writes a **REAL
file at a REAL accepted path that RAISES AT IMPORT** (`checks/isolate.py`, `is_file()` true,
`RuntimeError`). **`rc=3`, no traceback.** **A cell that merely renamed the path would have PASSED
on the old code** — I built that cell first, measured it passing, and threw it away: it was not a
plant. This one fails the old code and passes the new one.

**(b) THE `ABSENT` PATH → SAME.** `at rest`, both inputs gone: both gates `rc=3`, both with
`== REFUSED, NOT A VERDICT:` on stderr and **no traceback** (asserted by the crash flag, which
comes out of the *same* subprocess as the rc — a second bare invocation is what forked `bend` in my
first draft).

**(c) **A GATE THAT **SHOULD** RUN STILL RUNS.** The `POSITIVE CONTROL`: **same argv
(`--help`), input GOOD → `rc=0`, module scope reaches the parser, `refuse()` does not fire,
`import isolate` does not raise.** `modulerefuse` measured that "refuses everything" is a **9-gate
disease**; a fix that turns every path into a refusal is that disease. This cell is the assertion
that my fix is not it. **It is labelled as argparse's help, not as a census** — because it is.

### WHAT THE PLANT DOES **NOT** CLAIM

`hermetic-census.py` reaching **`0`** or **`3`**. `0` forks `bend`; `3` needs an input absent, which
is the `at rest` row above and cannot be a steady-state plant. **Both stay UNPLANTED in the source
and `gates/gate-surface.py` keeps them red.**

**THE PLANT IS ONE-SHOT AND SAYS SO:** re-running it on the landed tree returns **`3`** — *"a swept
input I was told is absent is PRESENT — another unit restored it and this plant would overwrite
their work"* — **the `zerogate` guard, kept.** `plant.rows` is from the clean run.

---

## 7. CHECKING FOR A FOURTH "THE TREE ALREADY OWNS IT"

The brief says three units found it already owned what they were asked to build. **It is five, and
one of them is decisive.**

| # | what I was going to build | the tree already owns it |
|---|---|---|
| 1 | a restore plant | **`.agents/slop/zerogate/plant.py`** — same shape, same `PRE = 371cc64c9^`, same `SWEPT` dict keyed by each gate's OWN refusal text. Read, adapted, **not duplicated**. |
| 2 | a refusal token | **`refuse()` at `checks/hermetic-census.py:43`**, in the file. Used. |
| 3 | an `ABSENT` marker | **`checks/hermetic-census.py:128` already writes the literal `"ABSENT"`**. Not invented. |
| 4 | a census of the `2` exit code | **`.agents/slop/onemodule/vocab-check.py`** (11 089 B) and `gates/gate-surface.py`'s `UNOWNED` class, both already reporting it. **I built neither and my `V EXIT CODES` row is `gate-surface`'s.** |
| 5 | **the rule that an unassigned code is not `DEAD`** | **`gates/gatekit.py:68-95 verdict_of()`, whose docstring is the brief's own question, answered in the first sentence of the "WHY `REFUSED` AND NOT `DEAD`" paragraph — before I got to it.** |

**#5 IS WHY MY ANSWER TO DEFECT (1) IS THE OPPOSITE OF THE BRIEF'S.** The tree had already ruled on
`2`. Building a fix on top of a question the owner of the vocabulary answered in `gatekit.py` is how
`.agents/slop/declareverdict/runner.py` ended up with `VERDICT[2]` planted as **correct**.

---

## 8. FOOTPRINT

```
 M checks/dup-gate.py            PLANTS 3→{0,1,2}  + the prose that denied it  (VERDICTS untouched)
 M checks/hermetic-census.py     existence predicate → importability; `.txt`→`.rows` ×2; PLANTS→{}
 A .agents/slop/eq/eq-census2.py          24 098 B, byte-identical from 371cc64c9^
 A .agents/slop/hermetic/isolate.py        4 181 B, byte-identical from 371cc64c9^
?? .agents/slop/restoredinput/plant.py, plant.rows
```

**`ruff` INTRODUCED NOTHING: HEAD had 4 findings in these two files, the tree has 3** — the
`f-string-missing-placeholders` went away because I deleted an `f`-prefix that had no placeholders.
The 3 survivors are pre-existing at HEAD. (`checks/` is 2-space-indented and is not what `ruff`
defaults to; `AGENTS.md` says so.)

**NOT COMMITTED. NOT STAGED. `git diff --cached` names none of these paths — verified.**
No `@`. No amend, rebase, or force-push. `git ls-tree -r HEAD` throughout; `git ls-files` never.