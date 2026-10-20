# THE EXIT-CODE CENSUS: PROMOTE IT, AND WITH WHICH EXIT CONTRACT?

**Read at** `2026-10-20T20:52:52Z` · **HEAD** `9574a3e2aa2508e400dc9931d01399ee9ba30226`
**Tree state** `sysctl -n vm.loadavg` → `{ 4.62 6.22 6.40 }` (under 12; the full census was run).
**Nothing outside `.agents/slop/exitcensus/` was written.** No commit, no mutating git command, no
`checks/differ.py`, nothing under `gates/` executed, no `bend`.

**THE HEAD MOVED FOUR TIMES WHILE THIS WAS MEASURED** — `d9dcd0fe2ffb6559beb13e67f083021fa0a6748c`
at `20:41:53Z`, `520d3cf3b16eec3745c6d3f543c856fae8cb5235` at `20:44:49Z`,
`9c66365b7623813a843f36db145cd5d2df20245a` at `20:49:48Z`, and the one above at `20:52:52Z`. The
population grew 368 → 370 → 372 → **373** `.py` files under ten minutes, and one instrument
(`gates/ledgerdue-gate.py`) was **committed inside the window** — it was untracked and uncharged at
`20:49:48Z` and tracked and charged at `20:52:52Z`. **Every number below carries its timestamp
because the tree is a moving target** — `AGENTS.md`: "NEVER QUOTE A ROW COUNT WITHOUT THE RULE
THAT PRODUCED IT, AND NEVER QUOTE ONE FROM A JOB THAT MAY STILL BE RUNNING."

---

## 0. THE ANSWER, IN ONE PARAGRAPH

**Promote it to `checks/exitcode-census.py`**, with the exit contract **0 = PASS, 1 = FAIL,
3 = REFUSED**, a `--selftest` that is **its own lane with its own exit (0/1)**, and its rows written
to **`checks/exitcode-census.rows`, beside the instrument and in git**. It is **RED on arrival**:
**9 UNOWNED rows over 9 instruments + 10 MESSAGE-EXIT instruments = 19 charged rows over 18
instruments**, every one of them named with a line number, and every one of them fixable in one
line. That redness is the instrument's entire reason to exist: a census that is green on arrival is
a census with nothing to say. **And `checks/differ.py`'s exit 2 is NOT a defect in
`checks/differ.py`** — it is argparse's own usage code, raised because the *caller* invoked a
mode-selector with no mode, and **the census cannot see it at all** because the `sys.exit(2)` lives
inside the `argparse` module and not inside `differ.py`. The defect is in the **vocabulary**, and
`gates/gatekit.py` deliberately declines to widen it; the trace tool's invented token
`UNASSIGNED(2)` is the measure of that gap, not of `differ.py`'s honesty.

---

## 1. THE NUMBERS (the re-run, and what moved)

Both censuses were run at the same timestamp on the same tree, one after the other:

```
TIMESTAMP=2026-10-20T20:52:52Z   HEAD=9574a3e2aa2508e400dc9931d01399ee9ba30226
```

### 1a. The ORIGINAL census — `.agents/slop/exitcodes/census.py`, re-run ONCE

```
population   373 .py under checks/gates/ (os.walk + endswith('.py'))
rows         599
distinct     8 exit codes: [0, 1, 2, 3, 4, 5, 126, 127]
UNOWNED      25 rows over 23 files
UNDETERMINED 174 files
NO-EXIT-PATH 96 files
```

Classes the script's own summary does not print, derived from the `codes.rows` it wrote:

| class | rows | instruments | by code |
|---|---|---|---|
| MESSAGE-EXIT | 10 | 10 | 18 sites |
| UNDECLARED (a vocabulary code the prose never names) | 223 | 126 | `0`:98 `1`:71 `3`:49 `5`:4 `4`:1 |
| SHARP (declares one code, omits another) | 27 | 27 | — |

### 1b. What MOVED against the 2026-10-15 reading in `.agents/slop/exitcodes/REPORT.md`

| class | 2026-10-15 | 2026-10-20 | what moved |
|---|---|---|---|
| population (`.py` under `checks/`+`gates/`) | 226 | **373** | +147 files, +65% |
| rows | 388 | **599** | +211 |
| distinct exit codes | 8 | **8** | unchanged: `0 1 2 3 4 5 126 127` |
| UNOWNED | 20 rows / 18 files | **25 rows / 23 files** | +5 rows, +5 files |
| UNDECLARED | 140 rows / 73 files | **223 rows / 126 files** | +83 rows, +53 files |
| MESSAGE-EXIT | **24 instruments / 57 sites** | **10 instruments / 18 sites** | **−14 instruments, −39 sites** |
| SHARP | 14 | **27** | +13 |

**The MESSAGE-EXIT collapse is the headline and it is real, not a measurement artefact.** The
2026-10-15 report named 24 instruments; the tree now charges 10. **All 24 of the old names still
exist on disk** — none was deleted — and 23 of them no longer hand a sentence to the exit.
`gates/ops_python_exec-gate.py` — the one the brief says was already fixed — is **absent from the
current list, and so are these 22**: `checks/abi4_gate.py`, `checks/abi_gate.py`,
`checks/al-verdict.py`, `checks/cl-port-gate.py`, `checks/corpus-figure.py`, `checks/dup-gate.py`,
`checks/gate.py`, `checks/gate_dtype.py`, `checks/gate_norm.py`, `checks/jsfix_gate.py`,
`checks/oracle_f64.py`, `checks/plant.py`, `checks/residue.py`,
`gates/crp_graph_census-mutate.py`, `gates/crp_graph_census-oracle.py`, `gates/gendirs.py`,
`gates/i64-shr-gate.py`, `gates/ops_python_exec-gen.py`, `gates/ptx_render_census-gen.py`,
`gates/ptx_render_census-mutate.py`, `gates/retention-check.py`,
`gates/tc_ptx_types-mutate.py`. (`gates/ops_python_census-oracle.py` is the one that **stayed**.)

**And the tree records HOW, in the file it fixed** — `gates/ops_python_exec-gate.py:64-75`:

> *"**THIS FUNCTION IS THE POINT OF THE CHANGE THAT INTRODUCED IT.** The first three sites used
> `sys.exit(f"...")`, and `sys.exit` with a STRING prints it and exits **1**. So an ABSENT input
> and an OVER-BUDGET refusal both announced themselves in the message -- one of them literally
> beginning `REFUSED:` -- and then exited `FAIL`. MEASURED 2026-10-16: `gatesweep.py` classifies a
> gate by its exit code through this same `VERDICT`, so the tally recorded a refusal as a
> failure."*

**So the MESSAGE-EXIT fix is not a proposal of mine — it is a NAMED, MEASURED shape the tree
already has twice**: `gates/ops_python_exec-gate.py:64` `def refuse(why)` (exit **3**), and
`gates/gates-pop.py:251` `def refuse(*why)` (exit **3**, *"The code is IMPORTED, not re-spelled: a
second copy of the vocabulary is the same fault as a second copy of a population"*). **§4(a) is
the application of the tree's own `refuse()` to the 10 that are left.** A census instrument that
only ever goes down is a census nobody re-reads, which is why §4 is a worklist and not a victory
lap.

### 1c. The PROMOTED instrument's view of the same tree

```
population   373 .py under checks/gates/ (os.walk + endswith('.py'))
tracked      368 in HEAD; 5 on disk only (NOT in HEAD, not charged)
rows         599
distinct     8 exit codes: [0, 1, 2, 3, 4, 5, 126, 127]
CONVENTION   13 rows
CLAIMED      2 rows
UNOWNED      9 rows over 9 instruments -- CHARGED
MESSAGE-EXIT 10 instruments -- CHARGED
UNDETERMINED 174 instruments -- NOT charged
NO-EXIT-PATH 96 instruments
UNDECLARED   213 rows over 120 instruments -- NOT charged
exit         1
```

**Same 599 rows, same 8 codes, a different verdict on 15 of them** — the difference is entirely
the classification below, and it is the whole content of the promotion.

### 1d. The 23 code-`2` rows, split by whether argparse is the reason

```
imports argparse (2 is INHERITED): 11
  checks/disagree-gate.py  checks/dup-gate.py  checks/env-precond.py
  checks/nvrows-deadrow-gate.py  checks/substrate-id.py  checks/substrate-manifest.py
  checks/substrate-snapshot.py  checks/wallcheck.py  gates/gate-surface.py
  gates/gates-pop.py  gates/retention-check.py
does NOT import argparse (2 is CHOSEN): 12
  checks/.e2e-fixture/f64/repair-dupes.py  checks/.e2e-fixture/opsbend_milestone_gate.py
  checks/.tmp-amd_dsl_census-mutate.py  checks/al-verdict.py  checks/e2e.py
  checks/repair-dupes.py  checks/txt-owners.py  gates/amd_dsl_census-mutate.py
  gates/beautiful-mnist-gate.py  gates/crp_graph_census-mutate.py
  gates/linearizer_census-oracle.py  gates/mixin-op-gate.py
```

**The 12/11 split is the argument, and it is an argument about the SOURCE, not about the
number.** "2 is argparse's" is not a claim about the digit; it is a claim about *who chose it*. A
file that imports argparse inherited the code and cannot be blamed for it. A file that does not
import argparse picked `2` and owes the reader a name for it. The original census recorded the
difference as a **note on the row** (`"; the file uses argparse, so 2 is USAGE here"`) while still
**charging the row as UNOWNED** — a note that does not change a verdict is a note.

---

## 2. THE PRECEDENT: `checks/cites-census.py`'s SHAPE

`checks/cites-census.py` (966 lines) is the tree's **tracked census**, and its shape is what the
promotion must be able to adopt. Measured, not remembered:

**The exit contract, in one place.**
- `checks/cites-census.py:52-53` — the five verdicts as **tokens** and their exits:
  `PASS, FAIL, REFUSED, SKIP, DEAD = "PASS", "FAIL", "REFUSED", "SKIP", "DEAD"` and
  `EXITS = {PASS: 0, FAIL: 1, REFUSED: 3, SKIP: 4, DEAD: 5}`.
- `checks/cites-census.py:625-631` — `worst(judged)`: **`FAIL` if any FAIL, else `REFUSED` if any
  REFUSED, else `PASS`**, with `SKIP` and `DEAD` excluded by the caller so they can never raise it.
  Its docstring says why it is ONE function: *"`summarise` and `main` each carried their own copy
  of this expression, and a refusal that reached the summary but not `main` — or the reverse — is
  a census whose printed verdict and exit code disagree."*
- `checks/cites-census.py:962-963` — `main()` returns `EXITS[worst(real)]`; `:967` — `sys.exit(main())`.
- `checks/cites-census.py:60-64` — **a precondition absent is `sys.exit(EXITS[REFUSED])` = 3**,
  never a crash and never a silent pass: `git ls-tree` failing means the population is unknown.

**Three separate lanes, three separate exits.**
- `--selftest` (`:886`, `:898-899`) returns `selftest(ROOT)`, and `selftest` ends at `:879-881`
  with `return EXITS[PASS if not fails else FAIL]` — **the self-check's exit is its own**, because
  "do my plants still move?" is not the census's question.
- `--sample-fail` (`:907`, `:942`) returns `EXITS[PASS]` — it wrote a sample, it did not judge.
- the census lane returns `EXITS[worst(real)]`.

**The harness comes first, and it PLANTS.** `:710-712`:
*"THE HARNESS COMES FIRST: five claims, and the tree must move its verdict for each. A census that
cannot fail is the instrument this file was written to catch."* The plants build a scratch tree in
a `tempfile.TemporaryDirectory`, **mutate it, and assert the verdict MOVED** — a DRIFT plant
(the needle moved up one line), a GROW plant, a SHORTENED plant, a NUMERIC plant, and **ten
"false FAIL" plants** (`:745-757`) built from needles the 2026-10-14 sample actually produced.

**The population is DISCOVERED, twice, and the two are DIFFERED.** `:59-65` `committed()` uses
`git ls-tree -r HEAD --name-only` and `:68-77` `on_disk()` walks the filesystem; `:68-71` says
why: *"a census that reports one population and never notices the other is the `differ.declared()`
fault with the import removed."* `:947-948` prints the difference.

**The census cannot state its own precision, so a human does.** `:888-896` — `--sample-fail N`
writes N FAIL rows **with an EMPTY LABEL COLUMN** (`:929-932`: *"The predecessor's sample carried
its 15 TRUE labels in the REPORT PROSE and nowhere else, so no one — including its author — could
check them"*), and `--precision <file>` re-reads a labelled sample and reports **per-lane
precision with each lane's own n** (`:944-946`, `:700-704`).

**Verdicts are tokens, never exit codes** (`:24`): *"FIVE VERDICTS, REPORTED AS TOKENS, NEVER AS
EXIT CODES"*, and an absent subject is `REFUSED`, *"NEVER A SILENT PASS AND NEVER A `FAIL`"*
(`:25-27`).

**What the promoted census can and cannot adopt.** It can adopt the **exit discipline** (one
place computes the exit; the summary and the exit cannot disagree; a precondition absent is 3;
the self-check is its own lane), the **plant-first harness**, the **population discovery**, and the
**empty label column** idea. It can **not** adopt cites-census's *"worst verdict over the judged
claims"* rule unchanged, because cites-census judges **claims about files** (a claim is either
true or false) whereas the exit-code census judges **the tree's own instruments** (an instrument
may be unowned, or undeclared, or absent from the vocabulary — and *refusing to guess* about one
of those is not a FAIL). §3 is that difference, made explicit.

---

## 3. THE EXIT CONTRACT, AND WHY

### 3a. The contract

| exit | word | when |
|---|---|---|
| **0** | `PASS` | the census measured the population and there is nothing to charge |
| **1** | `FAIL` | the census measured and it found something: a code the vocabulary does not name and no convention owns, **or** an instrument that hands a **sentence** to the exit |
| **3** | `REFUSED` | the census **could not measure**: the vocabulary owner is missing / ambiguous / unreadable, an instrument in the population cannot be parsed, or the committed population cannot be read |
| **4** | `SKIP` | *not used* — the census always runs; there is nothing to skip |
| **5** | `DEAD` | *not used* — the census always emits its rows; "it ran and emitted nothing" is not a state it has |

`--selftest` is a **separate lane with its own exit**: 0 when every plant moved, 1 when one did
not. **A census's exit and a census's self-check's exit are different questions**, and
`checks/cites-census.py:879-881` is the precedent for keeping them apart.

### 3b. Why the rejected options are rejected, against the tree's OWN rules

**"Exit 0 always — it is a report."** Rejected. `AGENTS.md` doctrine 2: *"A GATE THAT EXITS 0
HAVING MEASURED NOTHING IS WORSE THAN NO GATE, BECAUSE IT IS TRUSTED."* An exit-0-always census
that holds 19 named findings is the same object with a different name. A report is what a
**`.rows` file** is; the exit is what a **gate** is. The promotion needs both, and the promoted
instrument has both: the rows file is the report, the exit is the gate.

**"Exit 1 on findings — it is RED NOW and permanently, until 24 instruments are fixed."**
Rejected as stated, and the reason is arithmetic, not taste. The charged set is **19 rows over 18
instruments**, and every one of them is a **one-line** change (§4). "Permanently red" is not what
19 named one-line changes is; it is what an unnamed class of 24 would be. **And a gate that is
green on arrival is one that has nothing to say** — if the census shipped green, either the census
is blind or the tree is clean, and on this tree it is neither. The redness is the **witness**;
`checks/differ.py`'s own plant 3: *"if it does not go red, the row is a label."*

**"Exit 3 REFUSED when it cannot classify."** **Accepted, and it is load-bearing, not a
fallback.** The census's *precondition* is the live `gates/gatekit.py` vocabulary. If the owner is
gone, ambiguous, or renamed, the census **cannot classify at all** — and `REFUSED` is exactly
`AGENTS.md`'s word for that: *"a precondition was absent"*. The refusal must reach the **exit**,
not merely the log: `checks/cites-census.py:60-64` refuses with exit 3, and a refusal that does not
reach the exit is a census that said `0` while it had measured nothing. Three concrete triggers,
all measured:

1. **the owner is missing or ambiguous** — `gates/gatekit.py` holds **two** name←code unpacks, or
   zero, or is gone. `gates/gate-surface.py:270` refuses an ambiguous owner rather than picking
   one, and so does this. *The plant `DRIFT 3` and `DRIFT 4` are exactly this.*
2. **an instrument in the population cannot be parsed** — a `SyntaxError` in a `checks/` or
   `gates/` `.py` means the population contains a thing the census cannot read. Charged as 3.
3. **`git ls-tree -r HEAD` fails for a reason other than "not a git repository"** — then the
   *committed* population is unknown, and the census cannot tell a tracked instrument from a
   staging temp. `checks/cites-census.py:60-64` refuses here; the original census **silently
   treated it as "everything is tracked"**, which would have charged the tree for its own
   `.tmp-` files. (The original census's `_committed()` equivalent does not exist — the slop
   census has no git filter at all, so it charged `checks/.tmp-amd_dsl_census-mutate.py`.)

### 3c. What the census CHARGES, and what it does not — and why that line is where it is

**Charged (exit 1):**
- **UNOWNED** — the instrument can return a code the vocabulary does not name, that no convention
  owns, and that the instrument's own header does not claim. *A reader aggregating this instrument
  is guessing.*
- **MESSAGE-EXIT** — the instrument hands a **non-int** to the exit. CPython prints it to stderr
  and exits **1**, so to `$?` every one of them already reads as an honest FAIL **whatever the
  text says** — and the token is the only witness. Seven of the ten current ones are a **REFUSED**
  wearing a FAIL's number, which is the harm: *"a precondition was absent"* and *"the tool has no
  such mode"* are different things, and folding them is how *"the tool has no such mode"* reads as
  *"the tree is not ready"* — `gates/edge-runner.py:388-391` says this in its own words about
  its own classifier.

**NOT charged, and named:**
- **CONVENTION** (13 rows) — the code's meaning is fixed *outside* this tree: `2` where the
  instrument **imports argparse** (argparse's own USAGE code), `126`/`127` (POSIX: not
  executable / not found). The list is of **codes, not instruments** — *"it names no instrument,
  so it cannot go stale by an instrument moving"*.
- **CLAIMED** (2 rows) — the instrument names the number in its own header. **This test is a
  lexical LOWER BOUND** and it is safe in this direction and unsafe in the other: it can only
  *under*-report (a meaning stated without the digit is missed), so a census that under-reports is
  a census with false negatives, which is the safe direction to be wrong in. **A gate cannot charge
  a lower bound** — the charge would be on the LEXICON, not on the tree.
- **UNDECLARED** (213 rows over 120 instruments) — the same lexical lower bound, and **not
  charged** for the same reason. This is where the 2026-10-15 report's "140 rows, 64 of them code
  `0`" went: the class is real, it is large, and it is **a measurement of the prose, not of the
  tree's behaviour.** Charging it would be charging a sentence.
- **UNDETERMINED** (174 instruments) — a **declared limit of a static reader**, not an absent
  precondition. *"An UNDETERMINED row is not a claim that the instrument has no other codes; it is
  a claim that THIS instrument cannot see them."* A reader is told what it cannot see, by name.
- **NO-EXIT-PATH** (96 instruments) — modules, not entry points.
- **not in HEAD** (5 files, named) — a staging temp or a half-written gate. The census charges
  only what is committed, because a verdict that depends on an untracked file is a verdict that
  moves with the working tree.

---

## 4. THE MINIMUM FIX SET — named, by instrument and line

**19 charged rows over 18 instruments** (`checks/.e2e-fixture/opsbend_milestone_gate.py` carries
two of them). Grouped by what each one is. Every line number is from `2026-10-20T20:52:52Z` at
HEAD `9574a3e2a`.

### (a) GENUINE DEFECTS TO FIX — **12 UNOWNED rows over 9 instruments** (three instruments carry two
rows each), **plus 10 MESSAGE-EXIT instruments over 10 rows**

A "defect" here means: **the number does not mean what the site is telling the reader it means.**

| # | instrument : line | the shape at that site | what it should be |
|---|---|---|---|
| a1 | `gates/linearizer_census-oracle.py:207` | `sys.exit(2)` on *"ladder_check: the transcription disagrees with linearize"* — **a DISAGREEMENT** | **1 (FAIL)**. The only site in the tree where `2` signals a FAIL; a disagreement is the tree's `1`. |
| a2 | `checks/repair-dupes.py:99` | `sys.exit(2)` on *"`GOOD` is absent — rows vs the recorded good run CANNOT be checked"* — a **REFUSED** | **3 (REFUSED)** |
| a3 | `checks/repair-dupes.py:103` | `sys.exit(0 if same else 2)` — the rows **DIFFER** from the recorded good run — a **FAIL** | **1 (FAIL)**. **a2 and a3 are two classes on one number in one file**, which `gates/crp_graph_census-mutate.py:138-140` names as *"[a] defect the model commit (`fef1b64d7`) was written about."* |
| a4 | `checks/.e2e-fixture/f64/repair-dupes.py:99` | the fixture copy of a2 | **3** |
| a5 | `checks/.e2e-fixture/f64/repair-dupes.py:103` | the fixture copy of a3 | **1** |
| a6 | `gates/amd_dsl_census-mutate.py:140` | `raise SystemExit(2)` on *"THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS"* — a **REFUSED** | **3 (REFUSED)** |
| a7 | `gates/crp_graph_census-mutate.py:124` | the same class, eleven lines up in the same file — a **REFUSED** | **3 (REFUSED)** — see (b1): both sites move together |
| a8 | `gates/crp_graph_census-mutate.py:144` | *"== REFUSED, NOT A VERDICT: … the creation.bend import is gone"* — a **REFUSED** | **3 (REFUSED)** — see (b1) |
| a9 | `gates/beautiful-mnist-gate.py:89` | **module scope**, `sys.exit(2)` on *"ORACLE DRIFT … this run would compare against nothing"* — a **REFUSED** | **3 (REFUSED)**. `gates/gate-surface.py:27` already names this site and this file. |
| a10 | `gates/mixin-op-gate.py:99` | the same, module scope, same drift message | **3 (REFUSED)** |
| a11 | `checks/al-verdict.py:127` | `return 2` on `if len(sys.argv) not in (3, 4)` — a **USAGE**, on a number the file **CHOSE** (it does not import argparse) | **inherit argparse's 2** (use `argparse`, so the code is not the file's to explain) **or declare `2: "USAGE"` in a `VERDICTS` table** |
| a12 | `checks/.e2e-fixture/opsbend_milestone_gate.py:114` | `return 2` on `if len(sys.argv) < 4` with a printed `usage:` line — the same shape | the same fix as a11 |

**a1–a10 are one-line changes to one number each, and `gates/gates-pop.py:251-258` is the
precedent for the migration**: *"`gates/gates-pop.py` used to `sys.exit(2)` — `checks/abi_gate.py`'s
rule in its own idiom — but `gatekit.py:60` OWNS the vocabulary … a tree-owned runner maps ANY code
outside those five to `DEAD`."* **The tree has already done this migration once and left nine
instruments behind.**

**The MESSAGE-EXIT half (10 instruments, 18 sites) is also (a)**, and it is the same shape of
defect: a site that means *REFUSED* and exits *1* because it hands a sentence to `sys.exit`.
Named, with the class each one is:

| instrument : line | the text it prints | the class it is |
|---|---|---|
| `checks/.e2e-fixture/e2e_mm.py:239` | *"expected 2 launches, traced N — a zero-launch trace reads exactly like a program that computes nothing"* | **FAIL** (1) — the text is right, the number is right, but the exit is a *sentence*, so the token is the only witness |
| `checks/.e2e-fixture/e2e_port/plant.py:24` | *"VACUOUS PLANT: … contains N copies of the target text, not 1"* | **REFUSED** (3) |
| `checks/.e2e-fixture/f64/oracle_f64.py:178` | *"FIXTURE CONSTANT MOVED … Refusing to emit an oracle"* | **REFUSED** (3) |
| `checks/.e2e-fixture/opsbend_milestone_gate.py:50` | *"{STEM}: expected exactly one file beside this gate, found …"* | **REFUSED** (3) |
| `checks/.e2e-fixture/portexec/oracle.py:80` | *"expect_words is only written for CLANG, not {dev}"* | **REFUSED** (3) |
| `gates/e2emm-plant.py:75` | *"A: old call returned"* — the plant did not fire | **FAIL** (1) |
| `gates/falseclaim-census-gate.py:515` | *"PLANT DEAD: … row has N columns, wanted 8"* | **REFUSED** (3) |
| `gates/ledgerdue-gate.py:106` | `SystemExit(a string)` — a new instrument, committed inside the measurement window | **read it before fixing it** |
| `gates/ops_python_census-oracle.py:303` | *"amd_rdna3[0] and amd_rdna4[0] no longer share a triple"* | **REFUSED** (3) |
| `gates/questionmark-plant-gate.py:77` | *"PLANT STALE: … re-measure the plant, do not widen it"* | **REFUSED** (3) |

**Seven of the ten are a REFUSED that exits 1** — and that is the class `gates/edge-runner.py:388-391`
names: *"a precondition was absent"* and *"the tool has no such mode"* are different things.
**The fix in every case is the same shape, and THE TREE ALREADY HAS IT**: introduce the
`refuse(why)` that `gates/ops_python_exec-gate.py:64` and `gates/gates-pop.py:251` already use
(**exit 3**), print the message to stderr as now, and let the number say what the sentence says.
**`gates/ops_python_exec-gate.py`'s own docstring is the measurement** (quoted in §1b):
*"a gate that says REFUSED and exits FAIL is tallied as a failure, and the tally is the thing that
is wrong."*

### (b) DELIBERATE CONVENTIONS TO DOCUMENT — not charged, but they must be WRITTEN DOWN

| # | what | where | what to write |
|---|---|---|---|
| b1 | `gates/crp_graph_census-mutate.py:136-140` says **"2, and it is THIS FILE'S OWN NUMBER, not the tree's"** and argues *"going to 3 here would put two numbers for one class in one file, which is the defect the model commit (`fef1b64d7`) was written about."* | `gates/crp_graph_census-mutate.py:136-140` | **The principle is right and the conclusion is wrong.** *"One number for one class"* is satisfied by **3** exactly as well as by 2 — there is no second class in the file — and 3 is the number `gates/gatekit.py` names. Move **both** sites (a7, a8) to 3 and the comment becomes true; the comment as written **justifies a number the vocabulary does not own**, and `gates/gates-pop.py:251-258` is the tree's own statement that a refusal must be 3. |
| b2 | **the tree spells `2` two ways.** `2: "USAGE"` in `checks/dup-gate.py:373` and `checks/wallcheck.py:692`; `2: "REFUSED"` in `checks/env-precond.py:452` and `gates/gate-surface.py:136`. | those four `VERDICTS` tables | `gates/gate-surface.py:97-100` already names this: *"four gates declare one … two meanings on one number."* **The document is: `2` is `USAGE` everywhere** (it is argparse's code, in all four), and the two `2: "REFUSED"` spellings are wrong. One line each in `checks/env-precond.py:452` and `gates/gate-surface.py:136`. |
| b3 | **`126` and `127` are POSIX** — the command was found and is not executable / the command was not found. `checks/e2e.py:474` computes them (`status = 127 if isinstance(exc, FileNotFoundError) else 126`) and `:89`, `:445-450` and `:549` declare them in prose. | `checks/e2e.py` | The census calls them **CONVENTION**, not charged, because `checks/e2e.py` DECLARES them. But `gates/gatekit.py` has no name for them and `charge()` bills them `REFUSED` — *"A 'command not found' would be reported as a refusal to run."* **The document belongs in `gates/gatekit.py`'s `VERDICT` prose**: 126/127 are POSIX and mean what POSIX says; they are not refusals. |
| b4 | **the CLAIMED shortlist** — `checks/e2e.py:807` and `checks/txt-owners.py:296` read `declared=yes` (the instrument names the number in its own header). | those two rows | **Not charged, but they need a human.** The test is a lexical lower bound and it has a false positive: `checks/e2e.py`'s header names `2` and also `126`/`127` in the same breath, and `checks/txt-owners.py`'s header names `2` in a sentence about something else. The census prints both as the shortlist for hand adjudication, and a human must rule on them. **This is the "cannot state its own precision" lane that `checks/cites-census.py` answers with `--sample-fail` + an empty label column + `--precision`.** |
| b5 | **the tree's `gates/gatekit.py:106` sentence still carries "226 `.py` files" and "20 that can return `2`"** | `gates/gatekit.py:106` | Measured now: **373** `.py` files, and **23** rows of code `2` over **23** instruments (11 argparse, 12 chosen). The sentence's own argument — *"Three numbers, three questions, and a bare `13` answering none of them **is the defect this whole table is about**"* — is a complaint about a **bare number**, and it is carrying two more of them. **Either re-take them with the promoted census or delete them**; a fourth stale count is the same defect. |

### (c) CLASSIFIER ERRORS — in the census itself, and fixed BY THE PROMOTION

| # | the error | the fix |
|---|---|---|
| c1 | **the census charged a code `2` in an instrument that imports argparse.** The original census's note (`"; the file uses argparse, so 2 is USAGE here"`) was a **note on the row**, and the row was still charged `UNOWNED`. | the promotion makes it a **CLASS** (`CONVENTION`), so the 11 argparse instruments are not charged. The argument is **structural** — the file imports argparse — and a file that does not import argparse has no such argument. |
| c2 | **the census charged a code `2` in an instrument whose own header declares the number** (`checks/e2e.py:807`, `checks/txt-owners.py:296`). | the promotion makes it a **CLASS** (`CLAIMED`) and does not charge it. It also prints both as the shortlist for hand adjudication, because the test is a lower bound. |
| c3 | **the census charged files that are not in HEAD** (`checks/.tmp-amd_dsl_census-mutate.py` — a staging temp). | the promotion charges only instruments in `git ls-tree -r HEAD` and **names** the 5 it leaves out. |
| c4 | **the census could not see an INHERITED code at all** — `checks/differ.py`'s argparse `2`. | **This is not fixable by the census, and that is the finding.** The census's population is per-**module**, and a code inherited from a *library* is in no module. §5 is the whole of this. The promotion names the class rather than pretending to see it. |
| c5 | **the census's UNDECLARED class was 140 rows over 73 instruments with 64 of them code `0`** — and it was a **LEXICAL LOWER BOUND** presented as a finding. | the promotion keeps the class, **counts it, and does NOT charge it** — 213 rows over 120 instruments today, 94 of them code `0`. *"A gate cannot charge a measurement its own instrument says is not a reading."* |
| c6 | **the census's UNDETERMINED class was indistinguishable from a refusal.** | the promotion separates them in the exit: **UNDETERMINED is a declared limit of a static reader** (not charged, reported); **REFUSED is an absent precondition** (exit 3). `gates/gate-surface.py:97-100` and `gates/gatekit.py:112-115` are the two places the tree already draws that line. |

---

## 5. WHAT SHOULD `checks/differ.py`'s EXIT 2 BE?

**The question's premise is measurably false, and the evidence says so from three directions.**

**FIRST: the census does not call `checks/differ.py`'s exit 2 `UNOWNED`, and it cannot.**
`checks/differ.py` has **no static `sys.exit(2)` at all**. Its only exit site is
`checks/differ.py:1943` — `sys.exit(main())` — and the census resolves that to `main()`'s
returns. Its four rows in the census are:

```
checks/differ.py  ?  UNDETERMINED  na  4 site(s) whose code is computed at runtime or delegated …
checks/differ.py  0  PASS         no  sys.exit at line 1943
checks/differ.py  1  FAIL         yes sys.exit at line 1943
checks/differ.py  3  REFUSED      no  sys.exit at line 1943
```

**There is no code-2 row for `checks/differ.py` in either census, because argparse's
`parser.error()` calls `sys.exit(2)` inside the `argparse` module, not inside `differ.py`.** The
census's population is per-module, so a code **inherited from a library** is in no module at all.
**The census is BLIND to `differ.py`'s 2, not WRONG about it** — and that blindness is c4 above,
and it is the finding.

**SECOND: the run that produced `UNASSIGNED(2)` was a CALLER error, and the tree already knows
it.** `gates/edge-trace.rows` (generated by `gates/edge-runner.py`, in git):

```
# written 2026-10-20T17:22:27Z HEAD=852216853
checks/differ.py	RAN-UNASSIGNED	UNASSIGNED	UNASSIGNED(2)	2	0.36	25	2026-10-20T17:20:35Z
```

and `gates/edge-runner.py:386-391`, in its own words:

> *"MEASURED 2026-10-20: bare `differ.py` exits 2 because it has **NO BARE MODE** — it is a mode
> selector with four — and the edge's classifier folded that usage error into REFUSED, which means
> 'a precondition was absent'. **THOSE ARE DIFFERENT THINGS**, and folding them is how 'the tool has
> no such mode' reads as 'the tree is not ready'."*

`checks/differ.py:1892-1903` is the mode selector (`run` / `repro` / `snap` / `plant`) and it says
so in its own source at `:1903`: *"NO `choices=`: argparse would exit 2 on a name that is not a
plant, and 2 IS A CODE NO VOCABULARY NAMES."*

**THIRD: the tree's own direction is fixed, and it is the opposite of "2 is a verdict".**
`gates/gatekit.py:94-121` `verdict_of()` **deliberately does not name 2**, and says why: *"A gate
returning `2` — **a code `VERDICT` deliberately does NOT name** — made `VERDICT[code]` raise
`KeyError: 2`, so the runner that aggregated it CRASHED while reporting on a gate that had
answered. A mapping that raises on a legitimate code is not a vocabulary, it is a trapdoor."* And
`.agents/slop/exitcode/plant.py:68-76` **plants** that `VERDICT[2]` must raise, calling it *"the
trapdoor plant"*. `gates/gate-surface.py:517` charges the same thing under the name `UNOWNED`, and
`gates/gate-surface.py:654` plants a synthetic gate with `VERDICTS = {0: 'PASS', 1: 'FAIL',
2: 'USAGE'}` to prove the class is caught.

### THE ANSWER

**`checks/differ.py`'s exit 2 is CORRECT and must STAY 2.** It is argparse's own USAGE code, and
argparse's own exit code for a usage error is 2 — that is the tool's convention, and a tool's
convention is not a defect in the tool. `git diff` using 1 is a different tool's convention and
irrelevant here. **The defect is in the VOCABULARY, and the vocabulary is the tree's deliberate
choice**: `gates/gatekit.py` has no room for 2 because its five are fixed, and the census must
report that as a fact about the vocabulary rather than as a defect in whichever instrument
happened to be reading.

**What must change is the READER, and there are two of them:**
1. **`gates/edge-runner.py` already fixed its half** — it coined `UNASSIGNED` as a **status, not a
   verdict** (`:82-86`: *"THE SIXTH STATE IS NOT A VERDICT AND IS NOT COUNTED AS ONE"*), it stopped
   charging it, and it said the reason. That is the correct response to a code the vocabulary does
   not name, and it is the shape the trace row now has.
2. **The census must gain a class for it.** The promoted instrument has exactly one: `2` in an
   instrument that **imports argparse** is `CONVENTION` (c1). **`checks/differ.py` cannot be
   classified that way by the census, because the census cannot see the code at all** — so the
   census's honest statement is the one it already makes: *the population of exit codes is
   per-module, and an inherited code is in no module.* **That limit belongs in the report, in
   words, and the promoted instrument puts it there.**

**And the one thing that IS a defect in this area, which nobody has fixed:** the tree's
`VERDICTS` tables spell `2` **two ways** — `USAGE` (`checks/dup-gate.py:373`,
`checks/wallcheck.py:692`) and `REFUSED` (`checks/env-precond.py:452`,
`gates/gate-surface.py:136`) — and `gates/gate-surface.py:97-100` has been naming that collision
since before this census existed. **Two meanings on one number is the defect `gates/gatekit.py`'s
own docstring says the whole table is about** (*"Three numbers, three questions, and a bare `13`
answering none of them **is the defect this whole table is about**"*). **That is b2.**

---

## 6. THE PROMOTION DIFF

**`promoted.diff`, in this directory, 829 lines, applies cleanly** (`patch -p1 --dry-run` against
a scratch tree: `patching file 'checks/exitcode-census.py'` / `patching file 'gates/gatekit.py'`).
It is two files:

### 6a. The new file: `checks/exitcode-census.py` (811 lines, new)

**THE `ROOT` / `parents[N]` FIX.** The slop census sits at `.agents/slop/exitcodes/census.py` and
used `parents[3]`. The promoted file sits at `checks/exitcode-census.py` and uses
**`parents[1]`** — and it counts **from the FILE**, not from the file's directory:
`Path(__file__).resolve().parents[0]` is `checks/`, `parents[1]` is the repo root. The tree
already has both spellings and **both are right**: `checks/differ.py:41` is
`ROOT = Path(__file__).resolve().parents[1]` and `checks/abi_gate.py:50` is `REPO = HERE.parents[0]`
where `HERE = Path(__file__).resolve().parent` — and `gates/gates-pop.py:756-764` is the
instrument that measures the difference, with the reason: *"`resolve_root` … the arithmetic
shifted by one and answered `/Users/cyberistic/src/tries`."* **The promoted file adds a ROOT
ASSERTION as well**, in the tree's own shape (`gates/gates-pop.py:679-680` looks for a `refuse(`
guarded by a marker-file test; `gates/gates-pop.py:2468-2470` refuses when the marker is absent):
a missing `pyproject.toml` or `tinybendygrad/` at the root is a **REFUSED (3)**, checked *before
any measurement*, because *"a census that walked the WRONG tree and printed 'nothing to charge'
would be a green about a tree that does not exist."*

**THE OUTPUT PATH.** `checks/exitcode-census.rows` — **beside the instrument and in git**. NOT
`runs/` (`.gitignore:262`) and NOT `gates/artifacts/` (`.gitignore:214`): *"a finding that lives
in an ignored directory is a finding that a fresh clone does not have."* The precedent is
`gates/edge-trace.rows` — a GENERATED trace, committed beside its generator. `AGENTS.md`:
*"A GATE'S REQUIRED INPUT BELONGS BESIDE THE GATE IN GIT — AND NOT IN `gates/artifacts/`, WHICH
THIS FILE USED TO RECOMMEND."* **The rows file must be committed in the same commit that first runs
the instrument**; a commit that adds the gate without its witness leaves a gate whose findings
exist only in a worktree.

**THE EXIT CONTRACT.** §3a, in the file's own docstring, with the three numbers taken from
`gates/gatekit.py` (not retyped — the file reads the owner's unpack by path) and `--selftest` as
its own lane with its own 0/1.

**THE `--selftest`.** Eleven plants, `selftest()` at the end of the file, each asserting that the
census's grammar **FOLLOWS the owner**: the owner GAINS a code (1); the owner RENAMES a verdict
(2a, 2b — two sides, because a one-sided plant cannot tell "the grammar followed the owner" from
"the prose is declared by anything"); the owner is AMBIGUOUS (3); the owner is GONE (4); a
MESSAGE-EXIT site is CHARGED (5); argparse's `2` is a CONVENTION and a CHOSEN `2` is not (6); an
UNPARSED instrument is REFUSED and the refusal **REACHES THE EXIT** (7); **the tree's own
`gates/gatekit.py` is READABLE** (8); and **no code is BOTH in the live vocabulary and in this
file's `CONVENTIONS`** (9) — a code the owner names cannot also be "a convention outside the tree".

**ALSO IN THE FILE, and each of them is a fix to a real defect in the slop census:**
- the vocabulary is **PARSED from the owner's module body**, not `importlib`-imported — because
  *"a census that executes its own vocabulary owner also executes whatever side effects that file
  has"*, and because a rename of the owner's attribute must be a **REFUSAL**, not an
  `AttributeError` that DIEs;
- the committed population is **`git ls-tree -r HEAD`**, and a git that fails for any reason other
  than "not a git repository" is a **REFUSED**, not an empty population;
- another file's `SyntaxWarning` is suppressed (`warnings.catch_warnings()`), because *"a census
  that prints another file's warning on its own stderr teaches a reader to ignore its stderr"*
  (`checks/cites-census.py:903-904` is the precedent).

### 6b. The citation move: `gates/gatekit.py:109-110`

```diff
-    name) and names the census that re-takes it: `.agents/slop/exitcodes/census.py`, whose
-    `codes.rows` column 3 is `UNOWNED`.
+    name) and names the census that re-takes it: `checks/exitcode-census.py`, whose
+    `checks/exitcode-census.rows` column 3 is `UNOWNED`.
```

**This is the load-bearing reason to promote at all.** `gates/gatekit.py` is a **tracked gate** and
it cites **`.agents/slop/exitcodes/census.py`** — a path in a tree that is being pruned. `AGENTS.md`:
*"A PATH INSIDE A SWEPT TREE IS DELETABLE WHILE THE GATE STILL NAMES IT."* The same citation appears
at `checks/coverage.py:175` (which names `.agents/slop/exitcodes-report/REPORT.md` — a **different,
also live** path under the same swept tree).

### 6c. What it would report on the tree as it stands

**19 charged rows over 18 instruments, and exit 1.** Named in §4(a). The full report:

```
population   373 .py under checks/gates/ (os.walk + endswith('.py'))
tracked      368 in HEAD; 5 on disk only (NOT in HEAD, not charged): <named>
rows         599
distinct     8 exit codes: [0, 1, 2, 3, 4, 5, 126, 127]
CONVENTION   13 row(s) -- a code the tree uses that the vocabulary does not name, with a meaning
                         fixed outside this tree
CLAIMED      2 row(s) -- the instrument names the number in its own header, so the tree is not
                        silent about it (NOT charged).  THE SHORTLIST FOR HAND ADJUDICATION:
                        checks/e2e.py code 2, checks/txt-owners.py code 2
UNOWNED      9 row(s) over 9 instrument(s) -- CHARGED
MESSAGE-EXIT 10 instrument(s) -- CHARGED
UNDETERMINED 174 instrument(s) -- NOT charged: a declared limit of a static reader, not an absent
                                 precondition
NO-EXIT-PATH 96 instrument(s) -- modules, not entry points
UNDECLARED   213 rows over 120 instrument(s) -- NOT charged: a LEXICAL LOWER BOUND, and a gate
                                                cannot charge a lower bound
wrote        checks/exitcode-census.rows
exit         1
```

**"A GATE THAT IS GREEN ON ARRIVAL IS ONE THAT HAS NOTHING TO SAY — SO SAY WHAT IT WOULD SAY ON
DAY ONE."** It says: *the tree's instruments return eight distinct exit codes against a five-word
vocabulary; nineteen rows across eighteen instruments return a code no reader can name; seven of
those are refusals wearing a failure's number; and one of them is a disagreement wearing a usage's
number.* **That is the finding, and it is worth a gate.**

---

## 7. THE CONTROL — "does the census's grammar still match the live `gates/gatekit.py`?"

### 7a. What is coupled, and how it is tested

The census's grammar and `gates/gatekit.py` are coupled in **two** places, and a control that only
covers one is a control that has not been tried:

1. **the code→word map** — which codes the vocabulary OWNS. A census that retyped
   `{0:"PASS",1:"FAIL",3:"REFUSED",4:"SKIP",5:"DEAD"}` would keep working after the owner changed,
   and would then charge a code the owner names. **MUTANT A** breaks this.
2. **the DECLARING word set** — which words the prose test recognises, so that *"5: DROPPED"* is a
   declaration under a `DROPPED` owner and is not one under a `DEAD` owner. **MUTANT B** breaks this.

**The control is the `--selftest`, and it is a plant suite over a synthetic tree** — the same shape
as `checks/cites-census.py:710-880`, and the same rule: *"A control that has never failed is a
label, not a control"* (`checks/differ.py`'s own plant 3). So the control is **shown to go RED** by
building two mutants of the delivered file, each breaking exactly one coupling, and running the
selftest on each.

### 7b. THE RESULT, MEASURED

`mutate-promoted.py` builds the mutants from
`.agents/slop/exitcensus/scratch/checks/exitcode-census.py` — the delivered file — by a single
anchored text substitution each, so the mutants differ from the original in **one line**:

| run | command | exit | result |
|---|---|---|---|
| **the promoted instrument** | `exitcode-census.py --root . --selftest` | **0** | `selftest PASS: 11 case(s) run, 0 failed` |
| **MUTANT A** — the vocabulary is a typed copy instead of a load | `mutant-promoted-a.py --root . --selftest` | **1** | `selftest FAIL: 11 case(s) run, **4 failed**` |
| **MUTANT B** — the DECLARING word set is retyped instead of derived | `mutant-promoted-b.py --root . --selftest` | **1** | `selftest FAIL: 11 case(s) run, **1 failed**` |

**MUTANT A's four red cases** (the selftest output, verbatim):

```
[   FAIL] DRIFT 1: the owner GAINS `2` -- the CHOSEN `2` is now OWNED and must STOP being charged
[   FAIL] DRIFT 2b: under a DROPPED owner, the SAME prose IS a declaration -- the grammar follows the owner
[   FAIL] DRIFT 3: the owner holds TWO unpacks -- REFUSED, never a guess
[   FAIL] DRIFT 4: the owner is GONE -- REFUSED, never a typed fallback
```

**MUTANT B's one red case:**

```
[   FAIL] DRIFT 2b: under a DROPPED owner, the SAME prose IS a declaration -- the grammar follows the owner
```

**The control is therefore SHARP IN BOTH DIRECTIONS AND MEASURED IN BOTH**: the selftest is green
only when the census genuinely follows the live owner, and it is red the moment the census stops
following it. **MUTANT B is the more interesting of the two**, because the code→word map is still
correct in it — only the *grammar* stopped following — and it is the direction nobody would have
thought to test.

### 7c. THE LIMIT OF THIS CONTROL, STATED RATHER THAN HIDDEN

**The plants are SYNTHETIC, and a synthetic owner cannot catch a drift the real one has already
undergone.** That is why plants 8 and 9 read the tree's **own** `gates/gatekit.py`: 8 asserts it
is **READABLE** (a census that cannot read the owner would charge nothing and say nothing, and
that must be a hard assertion, not a warning), and 9 asserts that **no code is BOTH in the live
vocabulary and in this file's `CONVENTIONS`** — a code the owner names cannot also be "a
convention outside the tree", and a shadowed code is the coupling failing in the one direction a
synthetic owner cannot show. **Both are green today** (the owner is `{0,1,3,4,5}`, the conventions
are `{126,127}` — disjoint), and **both are live assertions about the real tree, not about a
fixture.**

**What this control does NOT cover, and it is a real gap:** it does not detect a drift in the
**owner** that the census's *own* grammar cannot express — for example, if the owner were to gain a
sixth verdict whose name the prose test does not recognise. Plant 9 catches the *shadowing* form
of that (a code in both sets), but a sixth verdict with a fresh word would pass silently, and the
fix for it is not a plant but a rule: **when the owner gains a verdict, the census's `verdict_words()`
already picks the new word up** (it reads the owner's words by path), so the only thing that needs
updating is the *prose* that names the new word — and that is the tree's own convention to keep in
step. **This gap is named rather than papered over.**

---

## 8. WHAT IS STILL OPEN (named, not resolved here)

1. **`gates/ledgerdue-gate.py` was committed inside the measurement window** — untracked and
   uncharged at `20:49:48Z`, tracked and **charged** at `20:52:52Z`, and it carries a MESSAGE-EXIT
   at `:106`. **It is the live proof that this document's numbers expire**, and its site must be
   read before it is fixed.
2. **`gates/gatekit.py:106` still carries "226" and "20"** (b5). It must be re-taken from the
   promoted census or deleted. **The promoted census is the instrument that makes the re-taking
   possible, and that is the point of the promotion.**
3. **`checks/coverage.py:175` cites `.agents/slop/exitcodes-report/REPORT.md`** — a second live
   citation of a swept tree, by a tracked file. It is not part of this diff.
4. **The `checks/.e2e-fixture/` population (22 tracked files)** is charged by the census, and
   **5 of the 10 MESSAGE-EXIT instruments and 2 of the 9 UNOWNED are fixture copies** of files
   that also exist in `checks/`. Fixing `checks/repair-dupes.py:99,103` without fixing its fixture
   copy leaves the gate red; **the two must move together.**
5. **`checks/differ.py`'s inherited code `2` is invisible to any per-module census** (c4, §5). The
   promotion NAMES the class. It does not close it, and **it cannot**: closing it needs a census
   over the *imports* of every instrument, which is a different instrument with a different
   population. **Named, not done.**
6. **No commit was made and no existing file was edited.** The diff is a proposal, and the tree
   moved four times while it was being written.

---

## 9. THE FILES IN THIS DIRECTORY

| file | what it is |
|---|---|
| `decision.md` | this document |
| `promoted.diff` | **the deliverable**: the exact promotion diff — `checks/exitcode-census.py` (new, 811 lines) + the `gates/gatekit.py:109-110` citation move. **Applies cleanly with `patch -p1`**, and its new-file hunk is byte-identical to `scratch/checks/exitcode-census.py` (verified by re-extracting it and diffing). |
| `scratch/checks/exitcode-census.py` | the promoted instrument, as it would land — **the file the control was run against** |
| `scratch/mutant-promoted-a.py` | MUTANT A: the vocabulary as a typed copy. `selftest` → **4 of 11 red** |
| `scratch/mutant-promoted-b.py` | MUTANT B: the DECLARING word set retyped. `selftest` → **1 of 11 red** |
| `mutate-promoted.py` | builds both mutants from the delivered file, one anchored substitution each |
| `promoted-codes.rows` | the 599 rows the promoted instrument wrote on the tree as it stands (600 lines with the header) |
| `ctl-promoted.out` · `ctl-promoted-a.out` · `ctl-promoted-b.out` | the three selftest transcripts quoted in §7b — **a control's transcripts are its witness** |
| `selftest.out` · `run.out` · `run.err` | earlier runs, kept for the same reason |
| `scratch/exitcode-census.py` · `scratch/mutant-a.py` · `scratch/mutant-b.py` · `mutate.py` · `mutant-a.out` · `mutant-b.out` | an **earlier draft's** instrument, mutants and transcripts, kept rather than deleted — they are the 9-plant version the 11-plant one grew out of, and deleting another unit's work is not this unit's call |
| `promotion.diff` · `analyse.py` · `run-census.py` · `codes.rows` | the earlier draft's diff and helpers, same reason |
