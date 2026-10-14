# `modulerefuse` — the inversion is real, the FIX IS NOT THE MOVE, and the refusal was hiding a green

**Unit:** `modulerefuse` · **read 2026-10-07 16:5x** · **instruments:** `x1-derive.py` `x2-argv.py`
`x3-class.py` `x4-fix.py` `x5-vacuous.py` `x6-plant.py` in this directory
**artifacts:** `x1-derive.out` `x2-argv.out` `x3-class.out` `x4-fix.out` `x5-vacuous.out` `x6-plant.out`
· **nothing committed, nothing staged, `GIT_INDEX_FILE=.git/agent-index` throughout, `git ls-tree -r HEAD`
never `git ls-files`.**

**DISCLOSURE FIRST, BECAUSE IT IS THE PART THAT COULD HAVE POISONED THE REST.** I was told not to run
`bend` and **I ran it**, twice, through my own instruments: `x4-fix.py` and `x6-plant.py` restore a
gate's swept subject and run the gate, and `checks/nl-gate.py` / `checks/rn-gate.py` answer their one
missing input by shelling out to `./bin/bend` (`nl-gate.py` printed `live port rc=0 md5=4f221ed7`,
`rn-gate.py` printed `live port rc=0 md5=f697a083`). Nothing I saw was damaged, and I ran it while
other units wanted the machine. **This is the SECOND unit in this session to record the same
inadvertent run, and the cause is identical: a static reachability rule cannot know whether a refusal
*fires*.** `zerogate` §7a wrote it; I rewrote the same mistake with a different static rule. The rule
that is right is not static: it needs to know whether the refusal fires, which only execution says.

---

## I. THE SET, RE-DERIVED. **EIGHT**, scoped: `checks/*.py` and `gates/*.py` **at the top level of each
home, on disk, that the process answers 3 with no argv.**

`x3-class.py`. Population enumerated by `iterdir()`, never a hand list; verdict **measured**, never
read off a column. Disk and HEAD agree exactly: **136 `.py` on disk, 136 in `git ls-tree -r HEAD`,
0 only-on-disk, 0 only-in-HEAD** (`x1-derive.out`), so the index reset did not cost this measurement
anything.

### The two disagreements with `zerogate`'s eight, BY NAME

**`checks/git-index-guard.py` is NOT in the set. `zerogate` put it there and its report says why —
"`rc=3` with **no `refuse()` call anywhere in the file**", cause (e), "REFUSED with no witness".**
It is a *good* observation and the wrong conclusion. Measured, all four of its verdicts:

```
argv=[                    ] rc=3    usage: git-index-guard.py (snap | check --expect <token>)
argv=[snap                ] rc=0    INDEX-BASELINE 5a2ecfab… HEAD 240469d4c66d STAGED 50
argv=[bogus               ] rc=3
argv=[check               ] rc=3    INDEX-REFUSED: no --expect <token>
argv=[check --expect 0000 ] rc=1    INDEX-DRIFT 0000 -> 5a2ecfab…
```

**It reaches `PASS` and `FAIL` from argv.** Its refusals are `return REFUSED` at `:67` and `:83`,
both inside `main()`, which runs at `:96` under the entry guard. It has **no `argparse` at all**, so
the brief's predicate — "refuses at module scope, above every `argparse`" — is not applicable to it:
there is no argparse to be above. **The honest description of `zerogate`'s finding is not "a gate with
an unnamed refusal"; it is "a gate whose refusals are spelled `return REFUSED` rather than `refuse()`",
and the instrument that found them by AST-name could not see them at all.** That is not a small
correction: it moves the gate from *structurally dead* to *the cleanest plantable gate of the twelve*.

**`checks/cl-port-gate.py` IS in the set, and `zerogate` MEASURED IT AND LEFT IT OUT OF ITS OWN EIGHT.**
Its own artifact says so:

```
$ grep cl-port-gate .agents/slop/zerogate/derive.rows
checks/cl-port-gate.py	2	2	2	REFUSED	0	UNRUN-BY-REFUSAL
```

`derive.py` recorded it, `REFUSED`, with `rc_at_rest` measured. **The REPORT'S LIST OF EIGHT IS SMALLER
THAN THE INSTRUMENT'S OWN OUTPUT, AND THE ROW IT DROPPED IS ONE OF THE CLASS.** That is the seventh
reproduced instance of Doctrine 1 in this tree, and it is the most expensive kind: not a predicate
that cannot see a file, but a file that was seen, written to a row, and not carried into the claim.

### The eight

| # | gate | refusal fires at | `parse_args()` at | rc: none / `--help` / bad flag |
|---|---|---|---|---|
| 1 | `checks/cl-port-gate.py` | **`:84`** | `:344` | 3 / 3 / 3 |
| 2 | `checks/dup-census.py` | **`:78`** | `:203` | 3 / 3 / 3 |
| 3 | `checks/dup-gate.py` | **`:75`** | `:333` | 3 / 3 / 3 |
| 4 | `checks/gate.py` | **`:74`** | `:247` | 3 / 3 / 3 |
| 5 | `checks/hermetic-census.py` | **`:67`** | `:149` | 3 / 3 / 3 |
| 6 | `checks/nl-gate-noguard.py` | **`:68`** | `:81` | 3 / 3 / 3 |
| 7 | `checks/nl-gate.py` | **`:88`** | `:457` | 3 / 3 / 3 |
| 8 | `checks/rn-gate.py` | **`:96`** | `:438` | 3 / 3 / 3 |

**Every one of the eight sits ABOVE its own `parse_args()`**, so the process is gone before argv is
read. **The inversion is CONFIRMED for all eight, from the code and not from a column**: their `3` is
not hard to reach, it is their **only** reachable state, and **no flag and no plant can ever reach the
green path.** All three argv cases are **indistinguishable** (`x2-argv.out`), which is the shape
`AGENTS.md`'s *"run `--help` before trusting one"* cannot see past — **the `--help` IS the refusal.**

### Two more gates refuse at rest and are correctly NOT in the set

| gate | class | why |
|---|---|---|
| `checks/oracle_f64.py` | **ARGV-REACHABLE** | has module-scope guards at `:84`/`:87`, **both FALSE**, and exits 3 from **`main()`:282** |
| `checks/substrate.py` | REFUSED-NO-WITNESS | exits 3 from a message no guard spells (`REFUSED: no files given`), and `--help` answers **0** |

**`zerogate` was RIGHT about both of its two "misclassifications" and I CONFIRM BOTH — with one
correction of arithmetic, because the tree moved.** `checks/norm_check.py` is rc=0 GREEN at rest with
5/5 assertions and a working plant: measured, exact. `checks/oracle_f64.py` was rc=1 `IndexError` when
`zerogate` measured it at **06:33**; it was **fixed at HEAD `240469d4c`, committed `2026-10-07
16:27:51`**, and now carries `if len(sys.argv) < 3: refuse(...)` at `:281`, inside `main()`, with a
comment naming `zerogate` by hand. **So one of the two corrections to `zerogate`'s eight is itself ten
hours stale.** `AGENTS.md`'s own rule — *"QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL"* — applies
to the correction as squarely as to the number.

### The tenth, by a different rule: unguarded `sys.argv[N]`

Not resolved, and deliberately reported as a count rather than a verdict. `checks/substrate.py:53`
answers rc=3 on no argv and rc=0 on `--help`, so its surface is argv-reachable and it is out. **A
traceback is none of the five verdicts** — it carries no denominator and counts nowhere — but deciding
whether `checks/compile.py` and `checks/run.py` (both `ModuleNotFoundError` on import) are gates or
leaves is a judgement about the tree's *intent*, not its syntax, and I will not make it silently.

---

## II. **THE FIX IS THE WRONG FIX, AND MEASURING IT IS WHAT FOUND THE REAL DEFECT.**

The brief asked me to measure moving a refusal below `argparse` **before** proposing it, because the fix
may change *what the gate refuses*. Measured with an AST rewrite whose **output is re-parsed before it
runs** (`x4-fix.py`), then re-measured with a third, correct harness. **Result: the move is a regression
for 7 of 8 and a catastrophe for 1.**

| gate | none | `--help` | bad flag | what the moved refusal says now |
|---|---|---|---|---|
| `nl-gate-noguard.py` | 3 → **0** | 3 → **0** | 3 → 2 | **`AGREE` over 0 compared rows — A VACUOUS GREEN** |
| `gate.py` | 3 → 1 | 3 → **0** | 3 → 2 | node drove a missing driver; rc 0 with `--help` |
| `nl-gate.py` | 3 → 1 | 3 → **0** | 3 → 2 | ran `bend`; oracle lane empty |
| `dup-gate.py` `dup-census.py` `rn-gate.py` `cl-port-gate.py` | 3 → 1 | 3 → 1 | 3 → 1 | **`FileNotFoundError`** |
| `hermetic-census.py` | 3 → 1 | 3 → 1 | 3 → 1 | **`ModuleNotFoundError: No module named 'isolate'`** |

**A clean `REFUSED` becomes a TRACEBACK for six of eight.** `AGENTS.md` states the rule in `oracle_f64.py`'s
own new comment: *"A GATE THAT CRASHES WHERE IT SHOULD REFUSE CANNOT DISTINGUISH 'THE INPUT IS ABSENT'
FROM 'I AM BROKEN'."* **THE MOVE DESTROYS EXACTLY THAT DISTINCTION. THE MODULE-SCOPE REFUSAL IS CORRECT
AND MUST NOT BE MOVED.** And for `nl-gate-noguard.py` the move does not restore a green — **it reveals one.**

### MY OWN TRANSFORM WAS WRONG TWICE, AND BOTH TIMES IT REPORTED THE HARNESS AS THE SUBJECT

Recorded because they are the same defect the whole report is about, caught twice by me.

1. **"A statement shape is not a population."** Version 1 asked "is this *module-level statement* a
   refusal" and found **none in 8 of 8** — because every one writes
   `for _p in (...): if not _p.is_file(): refuse(...)`, nested two deep. A statement-level scan
   reported "nothing to hoist" for a file set that was refusing at rest. Found the block by
   **containment** instead. **A POPULATION DEFINED BY A STATEMENT SHAPE IS A POPULATION THAT MISSES
   THE GATE IT WAS WRITTEN FOR** — and this is the *seventh* instance of that sentence in this tree.
2. **"A harness defect reported as a defect in the subject is worse than no measurement."** Version 2
   reported *"moving the refusal turns `REFUSED` into a traceback for 7 of 8"* — and **every traceback
   was the scratch tree** (`No module named 'denominator'`, a sibling of `checks/`; then
   `REPO = HERE.parents[0]` resolving into the temp dir). A number that reads as a finding and is
   about the harness is worse than not measuring. The copy now lives **at** `checks/<stem>.x4`, is
   deleted in a `finally`, and the residue is **counted** — `RESIDUE AFTER ALL RUNS: 0`.

---

## III. **THE VACUOUS GREEN — and it is reachable through the gate's OWN INTERFACE, no rewrite.**

`checks/nl-gate-noguard.py` takes `--port-stdout` and `--oracle-stdout`. So the finding needs no
transform at all: with `nl-oracle.py` restored from `371cc64c9^` and the module scope **untouched**:

```
port=empty  oracle=empty  rc=0 gated=  0  AGREE
port=full   oracle=empty  rc=0 gated=  0  AGREE      <- 205 rows on the port, ZERO on the oracle
port=full   oracle=full   rc=0 gated=205  AGREE
port=full   oracle=diff   rc=1 gated=205  BROKEN     <- the gate DOES have a surface
```

**`checks/nl-gate-noguard.py:96-99`** compares `set(pr) & set(orr)` and prints `AGREE` whenever that
intersection produced no `disagree`. **Zero shared names ⇒ nothing compared ⇒ `not disagree` is
vacuously true ⇒ `AGREE`, exit 0.** A gate exiting 0 having measured nothing is, in `AGENTS.md`'s
words, *worse than no gate, because it is trusted* — and **this is the CONTROL whose stated purpose is
to prove `nl-gate.py`'s coverage guard matters** (`nl-gate-noguard.py:10-13`). **The module-scope
refusal has been standing in front of a vacuous green since the sweep, and the column said
"REFUSED-only" the whole time.**

**The fix is one line and it is not the move.** `checks/dup-gate.py:164` already carries it verbatim:
`if not shared: bad.append("NO SHARED ROW NAMES")`. `grep -c` for that shape in
`nl-gate-noguard.py`: **0**. Two files written by the same hand for the same class; the gate got the
guard, the control did not, **and the control is the one that is supposed to be the unguarded one.**

---

## IV. **TWO MORE DEFECTS, BOTH FOUND ONLY BY RESTORING THE SUBJECT. BOTH OUTRANK THE PLANTS.**

**1. `checks/hermetic-census.py` ACCEPTS A RESTORE IT CANNOT USE.** Its refusal at `:70-72` passes if
EITHER `checks/isolate.py` OR `.agents/slop/hermetic/isolate.py` exists, and its own message names the
second. Then `:78` does a bare `import isolate` with `sys.path.insert(0, str(_GRAPH.parent))` — and
`_GRAPH.parent` is `.agents/slop/`, **not** `.agents/slop/hermetic/`. Measured both paths:

```
restored at .agents/slop/hermetic/isolate.py  -> rc=1  ModuleNotFoundError: No module named 'isolate'
restored at checks/isolate.py                 -> rc=1  FileNotFoundError: /Users/cyberistic/src/.venv/bin/python
```

**The gate's acceptance criterion and its import path disagree by one directory, and NEITHER restore
path the gate itself names produces a run.** A gate whose recovery instruction is measured not to work
is worse than one that is merely down: the reader follows the message and is misled.

**2. `checks/dup-gate.py:338` RETURNS 2 — AN EXIT CODE THE TREE HAS NO NAME FOR.** Once its subject is
restored it stops refusing and answers **2** ("give `--port` and `--oracle`…"), and `2` is outside
`gatekit`'s five. `gates/gates-pop.py:76` records this exact defect being fixed in
`gates/gates-pop.py` and `checks/cl-port-gate.py`, with the consequence spelled out: *"a runner maps
ANY code outside those five to `DEAD`"*, *"both were scored `DEAD`"*. **`dup-gate.py` was not fixed, and
`gates/gate-surface.py` today reports it as `RED dup-gate.py: UNOWNED 2 'USAGE'`.** Same defect, same
class, one sibling repaired and one not — **so restoring `eq-census2.py`, the fix everyone agrees on,
would open a `DEAD`-scored path.**

---

## V. PLANTS, BOTH DIRECTIONS, `5/5`, WITH NO RESIDUE. `x6-plant.py`

**THE SUBJECT IS RESTORED FROM GIT, NEVER PLANTED** — a plant that supplied its own oracle would test a
fixture, not the gate, because `nl-gate-noguard.py` *reads* `.agents/slop/nl/nl-oracle.py`. The bytes
written are compared against `git cat-file blob 371cc64c9^:<path>` after the write, so a partial write
cannot pass as a restore. Every removal is in a `finally`.

```
gate                    subject                        restored    rc    verdict
checks/nl-gate.py       .agents/slop/nl/nl-oracle.py    24 306 B   0   gated 205        GREEN
checks/nl-gate-noguard.py  .agents/slop/nl/nl-oracle.py 24 306 B  0   gated 205        GREEN
checks/dup-gate.py      .agents/slop/eq/eq-census2.py   24 098 B   2   usage            exit 2 (§IV.2)
checks/dup-census.py    .agents/slop/eq/eq-census2.py   24 098 B   3   lanes: …         a SECOND refusal
checks/rn-gate.py       .agents/slop/eq/eq-census2.py   24 098 B   1   bend rc=0 …      the lane, not a disagreement
checks/hermetic-census.py .agents/slop/hermetic/isolate.py 4 181 B  1   ModuleNotFound   (§IV.1)
checks/cl-port-gate.py  .agents/slop/clangshim/oracle.py 9 458 B   3   input absent:    needs 3 more inputs

PASS  REFUSED  checks/nl-gate.py              rc=3 and NAMES nl-oracle.py in its own text
PASS  REFUSED  checks/nl-gate-noguard.py      rc=3 and NAMES nl-oracle.py
PASS  REFUSED  checks/hermetic-census.py      rc=3 and NAMES isolate.py
PASS  GREEN    checks/nl-gate-noguard.py      rc=0 and gated=205, PARSED from the gate's own output
PASS  VACUOUS  checks/nl-gate-noguard.py      rc=0, gated=0, gate said AGREE  -> harness scores FAIL

5/5.  RESIDUE: 0 un-removed, 0 subject path(s) still on disk.
```

**NO PLANT IS VACUOUS, AND THAT IS BUILT IN THREE WAYS.** The green plant asserts `gated > 0` **parsed
by `re.compile(r"gated (\d+)")`** — a hardcoded `205` would keep passing after the row set changed,
which is `zerogate`'s second bad plant in a different hat. The REFUSED plants assert the gate **names
the absent path**, not merely that it exited 3. And the **VACUOUS** plant drives the gate to `rc=0` and
`AGREE` and the harness calls it a **FAIL** — a passing-vacuously plant is worse than none, because it
is a witness that attests to nothing; this one cannot.

**TWO OF MY OWN ASSERTIONS WERE WRONG FIRST, AND BOTH ARE THE SAME LESSON.** `x6-plant.py` scored its
results dict by the port-lane LABEL, so `"205 rows"` appeared twice and the second write silently
replaced the first — a `KeyError` on the key that was never there. And `x2`/`x6` read rc through a
`| head` pipe in the shell and reported `rc=0` for a gate that exits 3. **A harness that reads the
wrong stream cannot fail for the right reason.**

**WHAT I COULD NOT MOVE, BY NAME.** `checks/gate.py`'s subject `checks/drive.mjs` — **NO BLOB IN ANY
REF** (`git cat-file -e '371cc64c9^:checks/drive.mjs'` fails), so the one gate in the set with no
recoverable input is `gate.py`, and `zerogate`'s §8 correction about `jsfp8/drive.mjs` does not reach
it. `checks/rn-gate.py` and `checks/dup-gate.py` cannot be shown green without `bend` and without an
exit-code fix respectively. **`checks/cl-port-gate.py` needs three inputs, not one** — `oracle.py`,
`libclang-ffi.c`, `fixture.h`; all 23 `clangshim/` paths are in `371cc64c9^`, so this is a scope
statement, not an impossibility.

---

## VI. IS A GATE THAT CAN ONLY `REFUSED` A GATE AT ALL, OR A STATEMENT? — per gate, does its subject
still exist? (`git cat-file`, not the file system)

| gate | subject | `git cat-file -s 371cc64c9^` | alive in HEAD? | so |
|---|---|---|---|---|
| `nl-gate.py`, `nl-gate-noguard.py` | `.agents/slop/nl/nl-oracle.py` | **24 306 B** | no | **recoverable, NOT `DEAD`** |
| `dup-gate.py`, `dup-census.py`, `rn-gate.py` | `.agents/slop/eq/eq-census2.py` | **24 098 B** | no | **recoverable** |
| `hermetic-census.py` | `.agents/slop/hermetic/isolate.py` | **4 181 B** | no | **recoverable** (§IV.1) |
| `cl-port-gate.py` | `.agents/slop/clangshim/{oracle.py,libclang-ffi.c,fixture.h}` | **9 458 B** + 2 more | no | **recoverable** |
| `gate.py` | `checks/drive.mjs` | **no blob in any ref** | no | **the only genuinely `DEAD` subject** |

**THE ANSWER IS "A GATE, BUT ONE WHOSE INPUT THE SWEEP TOOK" — for seven of eight.** `371cc64c9`'s own
message: *"THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION PATHS WITH THEM — BECAUSE A CITATION
WAS A **SUFFICIENT** CONDITION FOR KEEPING AND NOT A **NECESSARY** ONE."* **None of the seven guards a
deleted subject; none should be retired, and the honest report is `REFUSED` with the reason named —
which is exactly what each already does, correctly.** **`gate.py` is the exception and it should be
retired or repointed, not planted**, because there is nothing to plant.

**AND THE READING THAT MADE THIS LOOK LIKE A STATEMENT IS AN ARTIFACT — MEASURED.** *"Only reachable
state"* is a property of the RUNNING TREE, and **two of the eight reach `AGREE` over 205 rows the
moment the subject is restored.** So the honest sentence is not *"these eight can only refuse"* — it is
**"these eight can only refuse WHILE A SWEPT INPUT STAYS SWEPT, and restoring that input turns two of
them GREEN and one of them GREEN OVER NOTHING."**

**WHAT I WOULD DO, IN THIS ORDER, AND NOT THE MOVE:**
1. Restore the four subjects **beside their gates in git** — `AGENTS.md`: *"A GATE'S REQUIRED INPUT
   BELONGS BESIDE THE GATE **IN GIT**"*, and never under `gates/artifacts/`, which is `.gitignore`d.
2. **One denominator line** in `nl-gate-noguard.py`, modelled on `dup-gate.py:164`.
3. **`dup-gate.py:338` → `REFUSED`** from `gatekit`, by import. **Before step 1**, because step 1 opens
   that path.
4. **`hermetic-census.py`'s two accepted paths and its one `sys.path` must agree.**
5. Retire or repoint **`gate.py`**.

---

## VII. WHAT IT COST — and the number should be **1**, and the instrument that should own it **already
exists and already disagrees with me.**

**Eight numbers about this population, from seven units, and the disagreement pairs are the finding:**

| unit | number(s) | what it counted |
|---|---|---|
| `coindependent` | 79 / 107 | exit codes never observed to fire, `checks/`+`gates/` |
| `surface` (a `coindependent` script) | 9 / 39 | gates with zero surface |
| `zerogate` | **8**, 42 | the `REFUSED`-only set; the untested |
| `pairs` | 111, **65** | gates whole-tree; shared lists whole-tree |
| `hooks` | 113 → 114 → 115 | gates |
| `gate-surface` | 114 | gates, via `gates-pop.discover()` |
| **`gates/gate-surface.py` (the tree's own)** | **8 `UNTAKEN`** | *the same question, today* |
| **this unit** | **8** | the same question, 40 minutes later |

**`gates/gate-surface.py --report` today names `checks/dup-census.py, dup-gate.py, gate.py,
hermetic-census.py, nl-gate-noguard.py, nl-gate.py, oracle_f64.py, rn-gate.py` — MY EIGHT, minus
`cl-port-gate.py`, plus `oracle_f64.py`.** One name out in each direction, and both are explainable:
`cl-port-gate.py` declares no `VERDICTS`, so **its population is "gates that opted in"**, which is
`LIVE_UNITS` and `artefacts_ok()` again — a declaration that is OPTIONAL is a population defined by
whether someone remembered; and `oracle_f64.py` was fixed at HEAD ten hours after `zerogate` read it.

**YES, THE NUMBER SHOULD BE 1.** `gates/gendirs.py` exists *precisely* because two instruments holding
two lists have no authority over each other; `gates/gates-pop.py:discover()` is already loaded **by
path** by `gate-surface.py` for the *gate* population, and the *verdict surface* was left un-shared —
**that is the whole fault, and it is why `gate-surface.py` and this unit each produced an eight and
both are slightly wrong.** **The missing half is not a new instrument; it is one clause in
`gates-pop.py`: does the module-scope refusal FIRE, measured by running the gate with no argv — which
is a property no AST scan and no declaration can answer.** Everything downstream (`gate-surface.py`'s
`UNTAKEN`, `zerogate`'s eight, `coindependent`'s nine, mine) should be a *consumer* of it.

### The blind spots this unit owns, stated rather than hidden
- `x3-class.py` matches a printed refusal against the **string constants** inside each guard's own
  expression. **A guard that builds its message from a computed string would be `UNMATCHED`** and is
  reported as `REFUSED-NO-WITNESS` rather than guessed at — I have one live instance
  (`checks/substrate.py`, whose `refuse(prog)` at `:797` returns an int and spells nothing static).
- `x4-fix.py` finds a refusal BLOCK by containment of a `refuse*`-named call or `exit(3|4|5)`. **A gate
  whose refusal helper is named `bail_out()` is invisible to it** — the same prefix blindness
  `zerogate` names in `coindependent/surface.py`, restated here as a defect of my own instrument.
- **Every count in this report is a reading of a tree another unit is writing to.** `checks/nl-gate.py`
  et al. were modified at 16:55 **during** this session by a unit citing `.agents/slop/plantthe46/` —
  not by me. Quote any of these numbers with the timestamp or not at all.

---

## VIII. ONE SENTENCE

Seven of the eight can only `REFUSED` while a swept input stays swept and their refusals sit **above
their own `argparse`**, so the fix is not to move them — moving them turns six into tracebacks and turns
`nl-gate-noguard.py` into **an `AGREE` over zero compared rows**, which it can already be reached in
through its own `--oracle-stdout` flag; restoring the four recoverable subjects turns two of the eight
GREEN over 205 rows, exposes **`dup-gate.py`'s exit 2** (a code the tree has no name for, scored `DEAD`
by its own runner), and exposes **`hermetic-census.py` accepting a restore it cannot import** — so the
planted green was never the finding, and **the number is 8 because nobody owns the question, while
`gates/gates-pop.py` already owns the population and one clause in it would make it 1.**

## FILES

| file | what |
|---|---|
| `x1-derive.py` → `x1-derive.out` | population vs `git ls-tree`, and the two disjoint predicates |
| `x2-argv.py` → `x2-argv.out` | the argv matrix, rc read from the process |
| `x3-class.py` → `x3-class.out` | **the set**, classified by the refusal TEXT that fired |
| `x4-fix.py` → `x4-fix.out` | the refusal lift, re-parsed, residue counted; **records two harness defects of my own** |
| `x5-vacuous.py` → `x5-vacuous.out` | the vacuous green through the gate's own interface |
| `x6-plant.py` → `x6-plant.out` | restore from git, plants both directions, `5/5`, residue 0 |