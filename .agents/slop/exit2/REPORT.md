# EXIT CODE 2: A CONVENTION WITH NO NAME IN THE VOCABULARY

**HEAD:** `9574a3e2aa2508e400dc9931d01399ee9ba30226` (`9574a3e2a`)
**Read:** `2026-10-20T20:41:52Z` – `2026-10-20T20:59:23Z` (UTC). Load average at the start: `4.52`.
**Artifacts:** `.agents/slop/exit2/sites.rows` (every site), `.agents/slop/exit2/roles.rows`
(the non-instruments, named), `.agents/slop/exit2/refused-phrase.rows` (the phrase/code
measurement), `.agents/slop/exit2/census.py` (the generator), `.agents/slop/exit2/argparse-control.py`
(the argparse control).

**THE TREE IS A MOVING TARGET AND THE NUMBERS BELOW MOVE WITH IT.** The instrument population
read **296, 297, 298, 299** entries across four runs of `census.py` inside one hour, because
another unit was writing `gates/` and `checks/` while this unit was measuring. Every number
here is quoted with the reading it was taken at. **Nothing under `checks/` or `gates/` was
edited. Nothing under `gates/` was RUN. `checks/differ.py` was NOT RUN, in any subcommand.**

**WHAT WAS RUN:** three things, all of them this unit's own files —
`.agents/slop/exit2/census.py` (an `ast`/regex census, no gate executed),
`.agents/slop/exit2/argparse-control.py` (a scratch `argparse` reproduction), and
`git rev-parse --short HEAD`.

---

## 0. THE SUBJECT IN ONE SENTENCE

`gates/gatekit.py:60` owns five verdicts as exits — `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3,
4, 5` — and **2 is not one of them**. `gates/gatekit.py:94-131` therefore has to answer "what
is 2?" for every caller, and it answers *"UNASSIGNED"*. Meanwhile **32 live instruments carry a
literal `2` at an exit site**, and they use it for **four mutually incompatible meanings**.
The trace tool had to coin a token for one of them (`UNASSIGNED(2)`), and that token is now a
row in a table a human reads.

**THE ANSWER, FROM THE EVIDENCE, IS IN §3. IT IS NOT "USAGE" AND IT IS NOT "REFUSED". IT IS
"SPARE".**

---

## 1. THE DENOMINATOR

**The population is discovered, not listed.** `gates/gates-pop.py:discover()` — the tree's own
generator declaration, **loaded by path** (never imported by name: importing a gate RUNS it) —
gives the entry points and the libs. A plain `os.walk` of `checks/` and `gates/` gives
everything else, and the difference is **named** in `roles.rows`, so no denominator here is a
hand list and nothing is hidden by the choice of population.

| population | count | what it is |
|---|---|---|
| `gates-pop.py:discover()` entries | **299** | the tree's own instrument population |
| `gates-pop.py:discover()` libs | **79** | modules with no entry guard |
| `os.walk` of `checks/` + `gates/` (`.py`/`.sh`) | **399** | everything on disk, including fixtures |
| non-instrument files in the walk | **24** | e2e stage-7 fixtures, and another unit's `.tmp-` scratch |
| **instruments that can reach 2 by a DETERMINATE mechanism** | **51** | 41 ENTRY + 2 LIB + 8 not-instrument |
| **instruments that carry a LITERAL 2 at an exit site** | **32** | 20 `.py` + 12 `.sh` — the deliberate class |
| instruments that import `argparse` | **98** | the implicit class |
| instruments that import `argparse` and carry **no** literal 2 | **88** | the pure-(i) class |
| **instruments that DECLARE a name for 2** | **4** | and they disagree two-and-two — see §3.1 |

**SITES** (one row each, in `sites.rows`): `argparse-usage` **99**, `deliberate` **48**,
`propagated-child` **19**, `accidental` **8**, and **`NOT-AN-EXIT` 1** — the last is a
classifier false positive that was found, verified by hand, and *excluded*; see §6.

**WHY 32 AND NOT "13", WHICH `gates/gatekit.py:98` CLAIMS.** `gates/gatekit.py:98-110` says
*"MEASURED 2026-10-16, that figure reproduces under NONE of the three available definitions: **9**
files declare `USAGE` in their own prose … a static AST walk of the **226** `.py` files of
`checks/`+`gates/` finds **20** that can return `2` at all."* **That sentence is stale and the
file says so itself** ("THE COUNT IS NOT IN THE SENTENCE ANYMORE, BECAUSE IT WAS NOT
RE-TAKABLE"). Re-taken today: the walk is **399** `.py`/`.sh` files (not 226 `.py`), and
**32** live instruments carry a literal 2 at an exit site (20 `.py` + 12 `.sh`). The 20 `.py`
figure still holds for `.py` alone; the shell half was invisible to a `.py` census.

---

## 2. THE ENUMERATION

Every row below is a row in `sites.rows`, with `file:line`, the mechanism, what a caller
reading `$?` sees, and the instrument's own message as the evidence.

### 2.1 (i) ARGPARSE-USAGE — 98 instruments, 99 parse sites

**The mechanism, proved, not assumed.** `checks/differ.py:1892-1895` builds an
`ArgumentParser` whose subparsers are `required=True`. Called bare, CPython's
`argparse.ArgumentParser.error()` calls `sys.exit(2)`. **The number 2 is not in the
instrument's source at all.** `.agents/slop/exit2/argparse-control.py` reproduces that exact
shape in a scratch file and observes it:

```
bare invocation  : rc=2
  stderr tail    : checks/differ.py: error: the following arguments are required: cmd
valid invocation : rc=0  stdout='REACHED THE BODY -- argparse did not refuse'
```

**This is the row in `gates/edge-trace.rows`.** `gates/edge-runner.py:386-391` names the
cause: *"MEASURED 2026-10-20: bare `differ.py` exits 2 because it has NO BARE MODE — it is a
mode selector with four."* The edge runs the gate **bare**, so the trace's
`checks/differ.py RAN-UNASSIGNED UNASSIGNED UNASSIGNED(2) 2` row is a **mis-called
instrument**, not a verdict about the tree.

**98 instruments import `argparse`**; 88 of them carry no literal 2 anywhere, so for those
the *only* path to 2 is a caller mistake.

### 2.2 (ii) DELIBERATE — 32 instruments, 48 sites

**A DELIBERATE `sys.exit(2)` IS A DECLARATION AND MUST BE READ AS ONE.** The 32 instruments
that carry a literal 2 at an exit site, named:

**Python (20):** `checks/al-verdict.py:127` · `checks/disagree-gate.py:557` ·
`checks/dup-gate.py:341` · `checks/e2e.py:589` · `checks/env-precond.py:351` ·
`checks/nvrows-deadrow-gate.py:294` · `checks/repair-dupes.py:99` · `checks/substrate-id.py:684` ·
`checks/substrate-manifest.py:574` · `checks/substrate-snapshot.py:267` ·
`checks/txt-owners.py:273` · `checks/wallcheck.py:591,602,637` ·
`gates/amd_dsl_census-mutate.py:140` · `gates/beautiful-mnist-gate.py:89` ·
`gates/crp_graph_census-mutate.py:124,144` · `gates/gate-surface.py:221,429` ·
`gates/gates-pop.py:1391` · `gates/linearizer_census-oracle.py:207` ·
`gates/mixin-op-gate.py:99` · `gates/retention-check.py:195`

**Shell (12):** `checks/bounded-selftest.sh:19` · `checks/demo.sh:18` · `checks/disarm.sh:17` ·
`checks/e2e.sh:42` · `checks/gate.sh:20,61,65,69,73` · `checks/run-all.sh:30,35` ·
`checks/run-f64.sh:69` · `checks/run-port-mm.sh:43` · `checks/substrate-check.sh:39` ·
`checks/walk-mutate.sh:34,109` · `checks/wt-sync.sh:18,19` ·
`gates/groupflip-baseline.sh:22,24,25`

**The declarations, quoted, as the task requires:**

- `checks/dup-gate.py:365-373` — the tree's fullest statement of the position:
  > **`2` IS `USAGE` AND STAYS `USAGE`.** It is `argparse`'s own exit code, and
  > `gates/gatekit.py:75` records that 13 files here return `2` on purpose with `USAGE` in
  > their own declaration among them; `gates/gatekit.py:97`'s `verdict_of()` gives an
  > unassigned code a name that is NOT `DEAD`, and `.agents/slop/exitcode/plant.py:74` PLANTS
  > that `VERDICT[2]` raises `KeyError` as the correct design. **Adding `2` to
  > `gates/gatekit.py`'s `VERDICT` would break that planted assertion, and moving it to `3`
  > here would erase this gate's USAGE/REFUSED distinction** — the same collision one level
  > down. `2` is UNOWNED BY `gatekit`, which is `gates/gate-surface.py`'s `UNOWNED` class doing
  > its job, and NOT a defect in this file.
  >
  > `VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED"}`

- `checks/wallcheck.py:590-591` — the exit stated in the message the operator sees:
  > `print(f"LEDGER UNREADABLE: {lp} does not exist. **A missing ledger is exit 2, never CLEAN.**")`
  > `VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}`

- `gates/gate-surface.py:213-221` — a **contradiction inside one file**:
  > `"""exit 2 = REFUSED, and NOT a verdict. `checks/abi_gate.py`'s rule, in this file's idiom.`
  > `print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)`
  > `sys.exit(2)`
  > `VERDICTS = {0: "OK", 1: "RED", 2: "REFUSED"}`

- `gates/retention-check.py:187-195` — the collision declared and the reason it was kept:
  > So gatekit does NOT read 2 as a REFUSAL; it reads it as NOT A VERDICT AT ALL, which is the
  > opposite of what the sentence claimed and is a WORSE reading: a caller cannot even tell
  > this file's instrument-gone case from a caller bug. **The exit is KEPT — it predates the
  > readers and renumbering it is a behaviour change, not a fix** — and the divergence is now
  > declared in the EXIT paragraph instead of being argued away here. `gates/gendirs.py` exits
  > 3 for the identical sentence, so **the tree carries two numbers for one meaning and this
  > is the second.**

- `checks/env-precond.py:451-452` — the fourth declaration, and it says the opposite thing:
  > `VERDICTS = {0: "OK", 1: "FAIL", 2: "REFUSED"}`

- **`gates/retention-check.py:167-195` — THE FIFTH DECLARATION, AND THE MOST COMPLETE ONE IN
  THE TREE. THIS IS THE SECOND CONTROL SITE (see §6).**
  > `def refuse(why):`
  > `"""Exit 2, and the NUMBER was chosen here before either site below was written.`
  > `This file's own EXIT paragraph says a precondition of the INSTRUMENT is 2, and both sites`
  > `refuse() carries are that class verbatim -- `git` could not answer, and the discovered`
  > `population itself is absent. What was wrong was only the CODE: `sys.exit` (and`
  > `raise SystemExit`) handed a STRING, which CPython prints and exits **1**, and 1 is FAIL.`
  > `MEASURED, the string was the whole disagreement -- a missing input was tallied as a red`
  > `clause.`
  > `**2 IS NOT ONE OF GATEKIT'S FIVE, AND THIS DOCSTRING USED TO SAY IT WAS.** …`
  > `So gatekit does NOT read 2 as a REFUSAL; it reads it as NOT A VERDICT AT ALL, which is the`
  > `opposite of what the sentence claimed and is a WORSE reading: a caller cannot even tell`
  > `this file's instrument-gone case from a caller bug. **The exit is KEPT -- it predates the`
  > `readers and renumbering it is a behaviour change, not a fix** -- and the divergence is now`
  > `declared in the EXIT paragraph instead of being argued away here. `gates/gendirs.py` exits 3`
  > `for the identical sentence, so the tree carries two numbers for one meaning and this is`
  > `the second."""`
  > `print(f"== REFUSED, NOT A VERDICT: retention-check: {why}", file=sys.stderr)`
  > `raise SystemExit(2)`

- **`gates/gendirs.py:461-467` — THE TREE HAS ALREADY MEASURED THE OTHER HALF OF THIS
  QUESTION, FROM THE OTHER DIRECTION:**
  > `raise SystemExit(3)   # `git` could not answer, so the half that asks it measured`
  > `                      # nothing. MEASURED, 20 files in this tree already exit a`
  > `                      # CHOSEN 3 for a precondition absent and 16 of the 20 do not`
  > `                      # import gatekit, so 3 is the tree's number and not this`
  > `                      # file's invention. It was a string, which CPython exits 1.`

**AND ONE CITATION INSIDE `checks/dup-gate.py:366` IS ALREADY STALE:** it cites
`gates/gatekit.py:75` for *"13 files here return `2` on purpose"*, and `gates/gatekit.py:75`
today is a comment about `SKIP`. The number it points at now lives in
`gates/gatekit.py:98-110`, which says the count **is not re-takeable** and names the census
that re-takes it (`.agents/slop/exitcodes/census.py`). **This unit re-took it: 32 live
instruments, not 13, and 20 `.py` files, not 13 either.**

### 2.3 (iii) PROPAGATED CHILD — 19 sites

The exit status is a **child's** status handed up, so the child chooses the 2. Named:
`checks/e2e.py:629,643` · `gates/amd_dsl_census-gate.py:1146` · `gates/bc-u32-gate.py:97` ·
`gates/beautiful-mnist-gate.py:97` · `gates/ew-consts-gate.py:55` ·
`gates/ew-explog-gate.py:82` · `gates/mixin-op-gate.py:108` ·
`gates/ops_python_census-gate.py:869` · `gates/oracle-census-gate.py:240,286,312,324,461,492` ·
`gates/wgsl_render_census-gate.py:1464`

`checks/e2e.py:294` is the sharpest of these: it computes
`status = 127 if isinstance(exc, FileNotFoundError) else 126` (`checks/e2e.py:474`, and again at
`:574`) and forwards the child's status out through `main()`'s `return rc` — so `e2e.py` can
also exit **126** and **127**, codes `gates/gatekit.py` has no name for either. The instrument
DECLARES them in prose (`checks/e2e.py:89`: *"So is rc 127: no `zsh`, nothing measured"*, and
`:445-450`: *"A COMMAND THAT DOES NOT EXIST IS STATUS 127, NOT A TRACEBACK … `PermissionError`
is 126 for the same reason"*), and `charge()` bills them `REFUSED` — a "command not found"
reported as a refusal to run.

### 2.4 (iv) ACCIDENTAL — 8 sites

Nothing in the file chooses 2, and yet the process can leave with 2. **A shell gate under
`set -e` running an interpreter that cannot open its script**: CPython's *"can't open file"*
exit **is 2** (MEASURED here: `python3 /nonexistent/x.py` → `rc=2`), and `errexit` hands it
up. Named: `checks/bounded-selftest.sh:21` · `checks/gate.sh:41` ·
`checks/lintable-gate.sh:88` · `checks/plant.sh:45` · `checks/run-all.sh:45` ·
`checks/sb-gate.sh:250` · `gates/oracles/beautiful-mnist-oracle.sh` ·
`gates/oracles/mixin-op-oracle.sh`

`checks/gate.sh:23-30` records this class being closed, and records the cost of the closing:
> MEASURED before this guard: `zsh checks/gate.sh` answers **rc=2**, `python3: can't open file
> '.agents/slop/shlscope/gen.py'`, and **NO `DIED`**, because errexit aborts at the call BELOW.
> Two consequences, and only the first is fixable here:
>   * the observable exit was `UNASSIGNED(2)`, which `checks/gatesweep.py:classify` folds to
>     REFUSED with the token `UNASSIGNED(2)` — **right verdict, for a reason nobody wrote**;
>   * **THE FOUR `DIED`/`exit 2` GUARDS AT 44-59 ARE UNREACHABLE**, so renumbering them would
>     be a line no run could exercise. They are left alone on purpose, not overlooked.

### 2.5 The 8 NOT-IN-POP files, named

`roles.rows` lists them: `checks/.e2e-fixture/f64/repair-dupes.py`,
`checks/.e2e-fixture/opsbend-milestone.sh`, `checks/.e2e-fixture/opsbend-milestone_gate.py`,
`checks/.e2e-fixture/portexec/run-kernel.sh`, `checks/.e2e-fixture/substrate-check.sh`,
`checks/.tmp-amd_dsl_census-mutate.py` (another unit's in-flight scratch),
`gates/oracles/beautiful-mnist-oracle.sh`, `gates/oracles/mixin-op-oracle.sh`.
**They are counted in the walk, excluded from the instrument population, and named.**

---

## 3. IS EXIT 2 USAGE, OR IS IT REFUSED?

### 3.1 The tree has TWO ANSWERS, IN FOUR FILES, AND THEY DISAGREE TWO-AND-TWO

| file:line | declaration |
|---|---|
| `checks/dup-gate.py:373` | `2: "USAGE"` |
| `checks/wallcheck.py:692` | `2: "USAGE"` |
| `checks/env-precond.py:452` | `2: "REFUSED"` |
| `gates/gate-surface.py:136` | `2: "REFUSED"` |

`gates/gate-surface.py:97-102` already records the collision, and names a THIRD reader:
> MEASURED, four gates declare one: `checks/dup-gate.py` and `checks/wallcheck.py` spell exit 2
> `USAGE`, `checks/env-precond.py` and THIS FILE spell it `REFUSED` — **two meanings on one
> number** — and `.agents/slop/hooks/run.py`'s aggregator scores every code outside its own five
> as `DEAD`, which is a THIRD.

**The THIRD is verified live**: `.agents/slop/hooks/run.py:32-33` reads *"Anything else is
UNKNOWN and is counted as DEAD, never as GREEN."* So 2 is **DEAD** to the hook, **USAGE** to
two files, and **REFUSED** to two others. **One number, three names, three readers.**

### 3.2 The tree's OWN convention, measured: 27 of the 31 that exit a code exit 3

`gates/runner.py:42-43` states the rule:
> A REFUSAL IS NOT A VERDICT. All five refusals exit `gatekit.REFUSED` (3) and print
> `REFUSED, NOT A VERDICT`, because the tree is fine in every one of them — the RUN is not
> permitted.

`refused-phrase.rows` measures every function that prints that phrase and the code it
actually uses:

| exit code | functions |
|---|---|
| **3** | **27** |
| **2** | **3** — `gates/gate-surface.py:213` `refuse()`, `gates/retention-check.py:167` `refuse()`, `gates/crp_graph_census-mutate.py:128` `_write_mutations()` |
| 1 or 3 | 1 — `gates/ops_python_exec-gen.py:524` |
| unresolved local | 1 — `checks/verdict.py:57` |

**So the tree's rule is 27-to-3, and the 3 are the outliers.** (The 32nd is
`gates/ops_python_exec-gen.py:524`, which exits 3 on one path and 1 on another; the 33rd,
`checks/verdict.py:57`, exits a local name this census cannot resolve.) `gates/gate-surface.py:220` and
`gates/retention-check.py:194` print the tree's canonical phrase and then exit with a code
the tree has reserved for something else.

### 3.3 The tree's OWN prose says 2 IS USAGE

`checks/disagree-gate.py:538-542` — nineteen lines above a `return 2` in the same file:
> THIS REPLACED `if not tree.is_dir(): return 2`, and **2 IS NOT NEUTRAL HERE: exit 2 is USAGE
> in `checks/env-precond.py` and `checks/differ.py`, so a caller reading `$?` could not tell
> "you passed a bad `--tree`" from "the corpus was never run". ABSENT AND STALE ARE BOTH
> REFUSED (3) AND ARE DISTINGUISHED BY TOKEN, NOT BY EXIT.**

Three claims in one paragraph, and each is checkable:
1. **2 is USAGE.**
2. **A refusal is 3.**
3. **Two refusals that must be told apart are told apart by TOKEN, not by exit.**

**AND `checks/disagree-gate.py:557` — NINETEEN LINES BELOW THAT PARAGRAPH — DOES `return 2`
FOR A REFUSAL:**
> `print(f"FATAL: {NAMES} is missing; the pin has no reader.", file=sys.stderr)`
> `return 2`

**That is a self-contradiction inside one file, and it is the sharpest single fact in this
report.** The same file states the rule and breaks it.

**AND `checks/disagree-gate.py:539-540`'s prose about `checks/env-precond.py` IS WRONG.** It
says *"exit 2 is USAGE in `checks/env-precond.py`"*, but `checks/env-precond.py:452` declares
`2: "REFUSED"`. The tree's own summary of the collision mis-states one of its four members.

### 3.4 The tree's own ROUTING-AWAY-FROM-2 is the strongest evidence for the answer

`checks/differ.py:1903-1909`, at the point where an author could have let argparse own a
refusal and chose not to:
> **NO `choices=`**: argparse would exit 2 on a name that is not a plant, and 2 IS A CODE NO
> VOCABULARY NAMES (`checks/differ.py`'s own `cmd_repro` comment says so and is why that exit
> became 3). **An unknown plant is REFUSED by `plant()` itself, which is the shape that keeps
> the five exits in one place.**
> `p.add_argument("--name", default=None, metavar="N", help=f"run ONE plant of {list(PLANT_NAMES)}; an unknown name is REFUSED (exit 3), never PASS")`

And `checks/differ.py:1562-1564` does exactly that: an unknown plant name returns
`gatekit().REFUSED` — **3**.

**An author, in the same file, faced with "argparse would exit 2 here", deliberately routed
the refusal to 3.** `checks/differ.py:1820-1827` records the same decision being made the
other way, historically:
> MEASURED 2026-10-18: this was `return 2`, and 2 IS A CODE NO VOCABULARY NAMES. … So the exit
> was not a sixth verdict, it was a TRAPDOOR, and a caller reading `$?` had nothing to read.
> **IT IS `REFUSED` AND NOT `FAIL`**, and the difference is the whole claim.

**So: the tree's own authors, writing the tree's own vocabulary, treat 2 as a number to ROUTE
AROUND for refusals, and use 3.**

### 3.5 WHAT 2 ACTUALLY CARRIES: FOUR INCOMPATIBLE MEANINGS, PLUS TWO LOCAL OR INHERITED ONES

The 48 deliberate sites sort into four groups. **The instrument's own message is the witness**
(it is the `evidence` column of `sites.rows`):

**(A) "YOU CALLED ME WRONG" — USAGE.**
`checks/al-verdict.py:127` (prints its own docstring) · `checks/dup-gate.py:341` (*"give
`--port` and `--oracle`, or `--compare BEFORE AFTER`, or `--selftest` with both"*) ·
`checks/env-precond.py:351` (*"unknown plant {kind!r}"*) · `checks/substrate-id.py:684` and
`checks/substrate-snapshot.py:267` (`ap.print_help()`) ·
`gates/groupflip-baseline.sh:24` (*"usage: gates/groupflip-baseline.sh `<outdir>`"*) ·
`checks/walk-mutate.sh:109` (*"UNKNOWN ARM $ARM"*).

**(B) "A PRECONDITION WAS ABSENT" — REFUSED.**
`checks/wallcheck.py:591` (*"LEDGER UNREADABLE"*) and `:602` (*"LEDGER MALFORMED"*) ·
`checks/disagree-gate.py:557` (*"the pin has no reader"*) ·
`checks/txt-owners.py:273` (*"no such file, so nothing was checked"*) ·
`checks/repair-dupes.py:99` (*"GOOD is absent — rows vs the recorded good run CANNOT be
checked"*) · `checks/run-all.sh:30,35` (*"REFUSING."*) ·
`gates/beautiful-mnist-gate.py:89` and `gates/mixin-op-gate.py:99` (*"ORACLE DRIFT"*) ·
`gates/amd_dsl_census-mutate.py:140`, `gates/crp_graph_census-mutate.py:124,144` (*"THE PINS
SHAPE IS NOT WHAT THIS HARNESS EXPECTS"*) · `gates/gate-surface.py:429` and
`gates/gates-pop.py:1391` (*"EMPTY POPULATION … cannot fail … REFUSED."*) ·
`gates/linearizer_census-oracle.py:207` · `gates/retention-check.py:195` · the eight
`cd "$_d/.." || exit 2` chdir guards.

**(C) "THE LANE DIED" or "THE ANSWERS DISAGREE" — DEAD or FAIL.**
`checks/gate.sh:61,65,69,73` — the tree's own word is **"DIED"**, and `gates/gatekit.py:60`
spells DEAD as **5** · `checks/repair-dupes.py:103` — `sys.exit(0 if same else 2)`, i.e. **the
rows are NOT identical**, which the tree calls **FAIL (1)** · `gates/linearizer_census-oracle.py:207`
(*"the transcription disagrees with linearize"*).

**(D) "THE ANSWER IS UNKNOWN" — INCONCLUSIVE.**
`checks/e2e.py:589` (*"no run produced rows in 8 attempts — SUBSTRATE OR FIXTURE, not a
verdict"*) · `checks/nvrows-deadrow-gate.py:294` (*"VERDICT: INCONCLUSIVE"*).

**AND (E) A FIFTH, INHERITED: argparse's usage error.** 98 instruments, none of which chose it.

**(F) AND A SIXTH, WHICH IS A LEGITIMATE LOCAL VOCABULARY: THE MUTATOR FAMILY'S OWN 2.**
Three files — `gates/amd_dsl_census-mutate.py:137-140`,
`gates/crp_graph_census-mutate.py:120-124`, and `checks/.tmp-amd_dsl_census-mutate.py:136-139`
(this last one another unit's scratch) — raise `SystemExit(2)` with the **same message**:
*"THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS"*. **They are a family, and they agree.**
And `gates/crp_graph_census-mutate.py:135-141` says, in its own source, WHY:
> 2, and it is THIS FILE'S OWN NUMBER, not the tree's: `assert_pins()` above already exits 2 for
> "THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS", eleven lines up and in the same
> before-anything-is-counted position. This is the same class — a required input is not what
> this harness needs — and **going to 3 here would put two numbers for one class in one file**,
> which is the defect the model commit (`fef1b64d7`) was written about. It was a string, which
> CPython exits 1.

**A MUTATOR IS NOT A GATE.** It is a harness that rewrites a tree so a gate can be tested
against a broken one, and its caller is the gate, not a runner reading `$?` for a verdict about
the tree. **A LOCAL VOCABULARY, HELD BY A FAMILY THAT AGREES, IS NOT A COLLISION — IT IS A
CONVENTION.** This is the same shape as `checks/dup-gate.py`'s `USAGE`: a local code, locally
declared, locally consistent. **WHAT IT LACKS IS THE DECLARATION: none of the three mutators
carries a `VERDICTS` line, so nothing in the tree reads their 2 as anything.**

### 3.6 THE ANSWER

> **2 IS NOT USAGE AND IT IS NOT REFUSED. IT IS A SPARE NUMBER THAT 32 INSTRUMENTS REACH FOR
> WHEN THEY HAVE SOMETHING TO SAY AND NO WORD TO SAY IT WITH.**
>
> **THE TREE'S OWN WORDS FOR THE FOUR MEANINGS ALREADY EXIST AND ALREADY HAVE CODES:**
> USAGE has none (it is argparse's, and it is the only meaning that is genuinely a CALLER's
> error and not the tree's), REFUSED is **3**, FAIL is **1**, DEAD is **5**, INCONCLUSIVE is
> `UNASKABLE`/`SKIP` (**4**, per `gates/gatekit.py:84-85`). **THE COLLISION IS NOT "2 MEANS TWO
> THINGS". IT IS "2 MEANS SIX THINGS" -- FOUR OF WHICH THE TREE ALREADY NAMES AND HAS ALREADY
> NUMBERED.**

**SO: WHAT SHOULD A GATE THAT REFUSES BECAUSE ITS ARGUMENTS ARE WRONG DO?**

**It should exit 3, and say so on stderr, and — if two refusals must be told apart — be told
apart by TOKEN, not by exit.** That is the tree's own answer, stated in
`checks/disagree-gate.py:538-542`, implemented in 27 of the 31 functions that print the
tree's REFUSED phrase and exit a code, and applied deliberately by `checks/differ.py:1903-1909` when its author
was faced with the same choice.

**THE TWO AUDIENCES ARE REAL, AND THE EXIT CODE IS THE WRONG SEAM FOR THEM.** A caller that
mis-calls an instrument is a HUMAN or a SCRIPT that has a bug; the stderr says exactly what
was wrong and the exit code tells it nothing. A caller that is told "the tree is fine, the run
is not permitted" is a RUNNER, and it needs a code it can switch on. **They are different
audiences and they read different channels: stderr for the operator, `$?` for the runner.**
`checks/disagree-gate.py:540` says this exactly: *"ABSENT AND STALE ARE BOTH REFUSED (3) AND
ARE DISTINGUISHED BY TOKEN, NOT BY EXIT."*

**BUT THE ARGPARSE CASE CANNOT BE REMOVED, AND THAT IS WHY 2 IS NOT SIMPLY "WRONG".** 98
instruments inherit CPython's 2 and no amount of vocabulary will make that number mean
something else — unless the instrument overrides `argparse.ArgumentParser.error`, which is
option (c) below and costs 98 edits. **SO 2 WILL REMAIN IN THE TREE. THE QUESTION IS ONLY
WHETHER IT CARRIES A MEANING OR ONLY A COLOUR.**

---

## 4. THE TRACE TOKEN `UNASSIGNED(2)` — ITS PROVENANCE

**THE TOKEN IS NOT PRODUCED BY THE TRACE TOOL.** `gates/edge-trace.rows` is written by
`gates/edge-runner.py`; the string `UNASSIGNED(2)` is produced by
**`checks/gatesweep.py:413`**:

```python
return (word, word) if word else ("REFUSED", f"UNASSIGNED({rc})")
```

`gates/edge-runner.py:382-392` then RE-LABELS it:
```python
if token.startswith("UNASSIGNED"):
    status, verdict = "RAN-UNASSIGNED", "UNASSIGNED"
```
and its own comment records the reasoning:
> **A STATUS NO VOCABULARY NAMES IS NOT A PRECONDITION THAT WAS ABSENT.** … MEASURED 2026-10-20:
> bare `differ.py` exits 2 because it has NO BARE MODE … and the edge's classifier folded that
> usage error into REFUSED, which means "a precondition was absent". **THOSE ARE DIFFERENT
> THINGS**, and folding them is how "the tool has no such mode" reads as "the tree is not
> ready". It is COUNTED and it does not CHARGE, and it says which it is.

**SO THE TOKEN IS THE TREE'S OWN FIX, APPLIED ONE LEVEL UP FROM WHERE THE PROBLEM IS.** The
edge already refused to fold a usage error into REFUSED. It did it by COINING A WORD, because
the vocabulary had no word.

**SEVEN SPELLINGS OF ONE UNASSIGNED CODE EXIST IN THE TREE** — and they are not all
spellings:

| # | site | what it says about a 2 |
|---|---|---|
| 1 | `gates/gatekit.py:131` `verdict_of(2)` | `"UNASSIGNED (code 2 is not one of the five)"` |
| 2 | `gates/gatekit.py:143` `charge(2)` | **3** — a bare number, no word at all |
| 3 | `checks/gatesweep.py:413` | `("REFUSED", "UNASSIGNED(2)")` |
| 4 | `gates/edge-runner.py:392` | status `RAN-UNASSIGNED`, verdict `UNASSIGNED` |
| 5 | `gates/shellverdict-gate.py:162` | `"UNASSIGNED"` (no number) |
| 6 | `gates/help-census.py:137` | `"UNASSIGNED(2)"` |
| 7 | `gates/gate-surface.py:517` | **`"UNOWNED … so a caller aggregating it is guessing"`** |
| 8 | `.agents/slop/hooks/run.py:33` | **DEAD (5)** — a THIRD MEANING, not a spelling |

### 4.1 SHOULD THE TRACE NAME 2, OR KEEP THE RAW NUMBER?

**IT SHOULD KEEP THE RAW NUMBER, AND THE REASON IS THE MEASUREMENT IN §3.5: 2 HAS SIX
CLASSES -- FOUR INCOMPATIBLE MEANINGS PLUS TWO LOCAL OR INHERITED ONES -- SO ANY SINGLE
NAME WOULD BE FALSE FOR AT LEAST ONE OF THEM.**

`UNASSIGNED(2)` is **already a name** — of the CLASS ("the tree's vocabulary does not name
this"), plus the number, so a reader can look it up. Calling it `USAGE` would be a LIE for
`gates/gate-surface.py:221`, `gates/retention-check.py:195`,
`gates/gates-pop.py:1391`, `checks/wallcheck.py:591` and `checks/gate.sh:61`. **A table a
human reads that carries a false name is worse than one that carries a number and a class.**

**BUT THE TRACE IS STILL MISSING SOMETHING, AND THE FIX IS NOT A NEW WORD — IT IS A NEW
COLUMN.** `gates/edge-trace.rows`'s columns are
`gate, status, verdict, token, rc, seconds, peak-mb, measured-at`, and the `token` column
holds the **CLASSIFIER's** token (`UNASSIGNED(2)`, `TRACEBACK`), not the **gate's own** words.
`gates/edge-runner.py:386-391` has to explain the `differ.py` row **in the source of the
trace tool**, because **the table itself cannot carry the reason**. The gate's stderr is
already captured — `checks/gatesweep.py:440` builds it and hands it to `classify()` — so the
honest fix is a column for the instrument's own message, after which the classifier's coined
token becomes a fallback rather than a substitute.

**A CAVEAT, STATED: `UNASSIGNED(2)` IS ALSO A STATUS, NOT A VERDICT, AND THAT IS CORRECT.**
`gates/edge-runner.py:82-86` says so, and the edge's choice to COUNT it and NOT CHARGE it is
right: *"the tool has no such mode" is not a finding about the tree.* **THE TRACE TOOL GOT
THIS RIGHT. IT IS THE VOCABULARY THAT IS MISSING A NAME, NOT THE TRACE.**

---

## 5. THE THREE OPTIONS, AND WHAT EACH COSTS

### (a) `VERDICT` GAINS A NAME FOR 2

**THE COST IS MEASURED, AND IT IS FOUR BROKEN ASSERTIONS PLUS A TABLE THAT CHANGES.**

1. **`.agents/slop/exitcode/plant.py:70-74` breaks.** It exists on disk (3,609 B) and asserts
   `gatekit.VERDICT[2]` raises `KeyError`. Adding 2 to `VERDICT` makes that plant print
   *"FAIL VERDICT[2] did not raise — the old shape is gone, the plant is stale"* and exit 1.
   `checks/dup-gate.py:369` cites this plant as the reason.
2. **`gates/exitcode-census-gate.py:503`'s plant breaks.** Its case is
   `('sys.exit(2) is CHOSEN and UNOWNED', 'sys.exit(2)', 1, "INT", 2, "UNASSIGNED", True)`, and
   the check at `:585` is `verdict.startswith(want_verdict)` — a name other than `UNASSIGNED`
   fails it.
3. **`gates/exitcode-census-gate.py:453`'s `unowned` count changes**, so
   `gates/exitcode-census-gate.py`'s own PASS message changes shape.
4. **`checks/gatesweep.py:413` changes behaviour**: `gatekit.VERDICT.get(2)` would stop
   returning `None`, so the token stops being `UNASSIGNED(2)` and the verdict stops being
   `REFUSED`. **`gates/edge-runner.py:382`'s `token.startswith("UNASSIGNED")` branch would
   stop firing**, and `gates/edge-trace.rows`'s `checks/differ.py` row would change from
   `RAN-UNASSIGNED / UNASSIGNED / UNASSIGNED(2)` to whatever the new name is.
5. **AND THE WORST COST: THE NEW NAME WOULD BE FALSE.** §3.5 measures six classes, and
   §5(b)'s table applies all 32 to them. **A name `USAGE` is false for 24 of the 32
   instruments it would cover — everything except the eight whose 2 really is a usage error —
   including `gates/gate-surface.py:221`, `gates/retention-check.py:195`,
   `gates/gates-pop.py:1391`, `checks/wallcheck.py:591` and `checks/gate.sh:61`. A name
   `REFUSED` is false for 13 of them: the eight usage errors, the three that mean FAIL or DEAD
   (`checks/gate.sh:61` — *"DIED"*; `checks/repair-dupes.py:103` — *"not identical"*;
   `gates/linearizer_census-oracle.py:207` — *"the transcription disagrees"*) and the two that
   mean INCONCLUSIVE. **A name that is false for 24 of the 32 sites it names is not a
   vocabulary; it is a lie with a table.**

**THE COST OF (a), SUMMARISED: it buys a name for a number that does not have one, and it
breaks two live plants to do it.**

### (b) 2 STAYS UNOWNED, AND EVERY INSTRUMENT THAT EXITS 2 MUST DOCUMENT IT

**THIS IS THE RECOMMENDATION**, and the tree already owns the machinery for it:
`gates/gate-surface.py` reads each gate's `VERDICTS` declaration **by AST** (never by import:
import RUNS a gate) and reports an unowned code as **RED and NAMED**
(`gates/gate-surface.py:517-518`). `gates/exitcode-census-gate.py` already censuses
chosen-vs-unchosen. `gates/gatekit.py:94-131` already names an unassigned code and
`gates/gatekit.py:143` already decides what to charge it.

**THE CONVENTION TO DECLARE, WITH ITS EVIDENCE:**

> **2 IS `USAGE`, AND IT IS A CODE THE TREE DOES NOT OWN.**
> **2 means: the CALLER named something the instrument could not use, and the instrument never
> ran. It is never a verdict about the tree, and it is never a refusal — a refusal is 3.**
> **A refusal that needs to be told apart from another refusal is told apart by TOKEN, not by
> exit** (`checks/disagree-gate.py:540`).

**AND THE CONVENTION HAS TEETH: HERE IS ALL 32 AGAINST IT.** *Conforms* = the 2 really is "the
caller named something unusable". *Violates* = the 2 means something the tree already has a
number for. *Local* = a family that agrees with itself and needs a declaration, not a
renumbering.

| verdict | instruments (site) | the 2 means | the code the tree would use |
|---|---|---|---|
| **conforms** | `checks/al-verdict.py:127` · `checks/dup-gate.py:341` · `checks/env-precond.py:351` · `checks/substrate-id.py:684` · `checks/substrate-manifest.py:574` · `checks/substrate-snapshot.py:267` · `checks/walk-mutate.sh:109` · `gates/groupflip-baseline.sh:24` | the caller named something unusable | **2 stays 2** |
| **violates — 3** | `checks/disagree-gate.py:557` · `checks/repair-dupes.py:99` · `checks/txt-owners.py:273` · `checks/wallcheck.py:591,602,637` · `gates/beautiful-mnist-gate.py:89` · `gates/gate-surface.py:221,429` · `gates/gates-pop.py:1391` · `gates/mixin-op-gate.py:99` · `gates/retention-check.py:195` · `checks/e2e.sh:42` · `checks/run-all.sh:30,35` · `checks/wt-sync.sh:19` · `gates/groupflip-baseline.sh:25` | a precondition was absent | **3 (REFUSED)** |
| **violates — 3 or 5** | `checks/e2e.py:589` · `checks/nvrows-deadrow-gate.py:294` | the answer is not a verdict (*"SUBSTRATE OR FIXTURE, not a verdict"*, *"VERDICT: INCONCLUSIVE"*) | **3 or 5** — the file's own words decide |
| **violates — 1 or 5** | `checks/gate.sh:61,65,69,73` · `checks/repair-dupes.py:103` · `gates/linearizer_census-oracle.py:207` | the lane DIED, or the answers disagree | **5 (DEAD)** / **1 (FAIL)** |
| **violates — 3** (installation) | `checks/bounded-selftest.sh:19` · `checks/demo.sh:18` · `checks/disarm.sh:17` · `checks/gate.sh:20` · `checks/run-f64.sh:69` · `checks/run-port-mm.sh:43` · `checks/substrate-check.sh:39` · `checks/walk-mutate.sh:34` · `checks/wt-sync.sh:18` · `gates/groupflip-baseline.sh:22` | the tool is not where it thinks it is (`cd "$_d/.." \|\| exit 2`) | **3** — the same sentence in 10 files |
| **local vocabulary** | `gates/amd_dsl_census-mutate.py:140` · `gates/crp_graph_census-mutate.py:124,144` | *"THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS"* — a mutator's own code | **2 stays 2**, and it must be **declared** |

**SO THE CONVENTION, APPLIED, LEAVES 9 INSTRUMENTS ON 2 (one of them by choice and eight by
argparse's inheritance) AND ASKS 23 TO CHANGE.** **The eight `cd … || exit 2` guards are ONE
class in TEN files, and they are the cheapest renumbering in the whole report** — ten
one-character edits — but they are also the class with the weakest forcing function, because
a broken checkout is not a verdict about the tree and nothing is counting them.

**THE COST OF (b), STATED HONESTLY:**
1. **The two files that declare `2: "REFUSED"` must be reconciled** — `checks/env-precond.py:452`
   and `gates/gate-surface.py:136` — and **the reconciliation is a behaviour change, not a
   rename**: `gates/retention-check.py:190` says so in as many words (*"renumbering it is a
   behaviour change, not a fix"*).
2. **The three files that print the tree's canonical `REFUSED, NOT A VERDICT` phrase and exit
   2 must be reconciled** —
   `gates/gate-surface.py:213` `refuse()`, `gates/retention-check.py:167` `refuse()`,
   `gates/crp_graph_census-mutate.py:128` `_write_mutations()`. **This is the single most
   defensible change in the whole report: it makes three outliers match 27 siblings, it changes
   no verdict the tree relies on (a refusal is a refusal), and it costs three lines.**
   **BUT THE THREE ARE NOT ALIKE, AND THE DIFFERENCE IS THE POINT:**
   - `gates/gate-surface.py:213` and `gates/retention-check.py:167` are **`refuse()` helpers
     whose siblings in the tree exit 3** — `gates/gates-pop.py:251`, `gates/gendirs.py:465`,
     `gates/ops_python_exec-gate.py:64`, `checks/denominator.py:42`,
     `gates/citations-census-gate.py:182`, `checks/gatesweep.py:577`. **RENUMBERING THESE TWO
     TO 3 IS THE CLEAN, TWO-LINE FIX, and it is what `gates/gendirs.py:465` already argues for
     in its own comment: *"3 is the tree's number and not this file's invention."***
   - `gates/crp_graph_census-mutate.py:144` is **a mutator, and its own author has already
     argued against renumbering it** (§3.5(F)). **IT SHOULD BE DECLARED, NOT RENUMBERED.**
3. **The sites that mean FAIL or DEAD and currently use 2 must be renumbered to 1 or 5** —
   `checks/gate.sh:61,65,69,73` (*"DIED"* → 5) and `checks/repair-dupes.py:103` (*"not
   identical"* → 1) and `gates/linearizer_census-oracle.py:207` (*"the transcription
   disagrees"* → 1). **COST: `checks/gate.sh`'s own comment at `:29` says those four guards
   are UNREACHABLE** (the generator they guard is absent from the tree and from HEAD), **so
   renumbering them would be a line no run could exercise** — the file itself declines it.
4. **The 98 argparse users keep 2 by inheritance and CANNOT be renumbered** without an
   override each. **THIS IS FINE — it is exactly what the convention above says 2 means.**
5. **Every instrument that exits 2 must carry a `VERDICTS`-shaped declaration naming 2** —
   32 files today, and `gates/gate-surface.py` will report the ones that do not as RED.
   **The declaration is one line per file, and the instrument that checks it already exists.**

**THE COST OF (b), SUMMARISED: 32 declaration lines, three renumberings that align three
outliers with 27 siblings, and an honest statement that 2 is a CALLER's error and never a
verdict about the tree. NOTHING BREAKS: no plant asserts that 3 must be 2, and no live
assertion depends on 2 meaning REFUSED.**

### (c) THE ARGPARSE USAGE CODE IS REMAPPED TO 3 (REFUSED) AT EVERY CALL SITE

**THE COST IS 98 EDITS, AND IT FIXES NONE OF THE 32 DELIBERATE SITES.**

1. **98 instruments import `argparse`.** Each would need an `ArgumentParser` subclass or an
   `error()` override. (`exit_on_error=False`, new in 3.9, turns a usage error into an
   **EXCEPTION**, not a different code, so it does not help.)
2. **IT DOES NOT TOUCH A SINGLE DELIBERATE SITE.** The 32 instruments that *chose* 2 are not
   argparse's. **Option (c) leaves the entire §3.5 problem exactly where it is.**
3. **IT ERASES THE ONE DISTINCTION `checks/dup-gate.py:370` EXPLICITLY DEFENDS** — *"moving
   it to `3` here would erase this gate's USAGE/REFUSED distinction — the same collision one
   level down."*
4. **IT MAKES THE TREE'S OWN PROSE FALSE.** `checks/disagree-gate.py:538-542` would be a
   description of a convention that no longer exists, and
   `gates/edge-runner.py:383-391` — the fix that made the edge's own trace honest — would
   have nothing to fix.
5. **AND IT MAKES `UNASSIGNED(2)` VANISH BY FIAT RATHER THAN BY TRUTH.** The trace row would
   stop appearing because the number stopped appearing, not because the vocabulary grew.

**THE COST OF (c), SUMMARISED: 98 edits to remove a number that is not the problem, at the
price of the distinction that IS the problem.**

### 5.4 THE RECOMMENDATION, IN ONE PARAGRAPH

**TAKE (b), AND MAKE IT (b) PLUS TWO LINES.** Declare **2 = `USAGE`**, unowned by
`gates/gatekit.py`, and require the 32 instruments that reach 2 to declare it. Then **renumber
the TWO `refuse()` HELPERS that print the tree's own REFUSED phrase and exit 2** —
`gates/gate-surface.py:221` and `gates/retention-check.py:195` — **to 3**, which is what 27 of
their 31 siblings already do, what `gates/runner.py:42-43` already states, and what
`gates/gendirs.py:465` already argues for in its own comment (*"3 is the tree's number and not
this file's invention"*). **DECLARE the mutator family's 2 rather than renumber it**
(`gates/amd_dsl_census-mutate.py:140`, `gates/crp_graph_census-mutate.py:124,144`), because
`gates/crp_graph_census-mutate.py:135-141` has already argued why it is a local number.
**Leave argparse's 2 alone: it is the one meaning 2 has that is genuinely the CALLER's error,
and the convention says so.** **Do NOT add 2 to `gates/gatekit.py`'s `VERDICT`** — two live
plants assert that it is unowned, and §3.5 shows the name would be false for 5 of the 32 sites
it would cover.

**THE 32 DECLARATION LINES ARE NOT OPTIONAL AND NOT THE POINT.** They are the machinery
(`gates/gate-surface.py` already reads them by AST and reds an undeclared one), and they make
the tree's own reading of 2 — *"the caller named something unusable"* — checkable instead of
folklore. **But the TWO LINES THAT MATTER ARE THE TWO `refuse()` HELPERS**, because they are
the only places in the tree where the tree contradicts ITSELF, and fixing them costs two
characters.

**AND THE TRACE TOOL SHOULD BE LEFT ALONE ON THE VOCABULARY, AND IMPROVED ON THE COLUMN.**
`UNASSIGNED(2)` is correct as it stands: it names a class and carries the number, and it does
not claim a meaning the tree has not agreed on. **What the trace lacks is not a word for 2; it
is the gate's own words.** Add the instrument's message to the row — it is already captured at
`checks/gatesweep.py:440` — and the coined token becomes a fallback instead of a substitute.

---

## 6. THE CONTROL

**THE CLASSIFIER MUST FIND THE DELIBERATE `sys.exit(2)` SITES AND TELL THEM FROM ARGPARSE'S
IMPLICIT ONES. IT CAN, AND THE DISCRIMINATOR IS NOT A HEURISTIC:**

> **A LITERAL `2` IN THE SOURCE IS A DECLARATION. ARGPARSE'S 2 IS NOT IN THE SOURCE.**

Argparse's usage exit is CPython's `ArgumentParser.error()` calling `sys.exit(2)`; the number
never appears in the instrument. So a census that reads the source sees either a literal 2
(chosen) or the mere presence of `import argparse` (inherited), and those are disjoint
observations.

**THE CONTROL SITE IS `checks/dup-gate.py`, WHICH HAS BOTH**, and which documents the
reasoning in its own source at `checks/dup-gate.py:365-373` (§2.2 quotes it).
**THE SECOND CONTROL SITE IS `gates/retention-check.py:167-195`** — a deliberate
`raise SystemExit(2)` with the tree's fullest in-source rationale, and the one declaration
that says the number was *chosen* ("Exit 2, and the NUMBER was chosen here before either site
below was written"). **EIGHT ASSERTIONS, ALL GREEN, PRINTED BY THE CENSUS EVERY RUN:**

| # | assertion | result |
|---|---|---|
| **C1** | `checks/dup-gate.py` shows BOTH `argparse-usage` AND `deliberate` | **OK** — `['argparse-usage', 'deliberate']` |
| **C1b** | `gates/retention-check.py`'s DELIBERATE site is at line **195**, the line its own docstring names | **OK** |
| **C1c** | a file with a DELIBERATE 2 and **no argparse at all** exists (n=27) — so "deliberate" is not "argparse plus noise" | **OK** |
| **C2** | a file with `argparse` and NO literal 2 shows `argparse-usage` ALONE | **OK** — 88 such files |
| **C3** | the oracle's rung-counting `return 2` is NOT reported as an exit | **OK** |
| **C4** | the control instrument itself is in the census | **OK** |
| **C5** | no DELIBERATE site was attributed to a file that has none | **OK** |
| **C6** | every DELIBERATE python site is either a literal exit call or a PROPAGATING `return 2` | **OK** |

**AND A CONTROL THAT CAUGHT ITS OWN AUTHOR, WHICH IS THE POINT OF HAVING ONE.** The FIRST
version of **C1b** asserted that `gates/retention-check.py` imports no `argparse` and so shows
`deliberate` ALONE. **IT FAILED, AND IT WAS WRONG: `gates/retention-check.py:80` imports
`argparse`.** The assertion was rewritten to what is actually true — the DELIBERATE site is at
line 195 — and the failure is recorded here rather than quietly corrected. **A control that
only ever passes is a decoration; this one caught a wrong claim this unit had already written
into its own report.**

### 6.1 C3 IS THE INTERESTING ONE, AND IT IS A FALSE POSITIVE THAT WAS FOUND

**`gates/amd_dsl_census-oracle.py:1046` returns 2 — and it is NOT AN EXIT CODE.** It is
`_num_srcs()`, which returns **the number of source rungs** of a DSL node:

```python
def _num_srcs(names):
    """`dsl.Inst.num_srcs` (dsl.py:404-410) -- the THREE RUNGS, in order."""
    if "src2" in names: return 3
    if {"src1", "vsrc1", "ssrc1"} & names: return 2
    ...
```

**A LEXICAL CLASSIFIER CANNOT TELL THIS FROM `checks/dup-gate.py:341`'S REAL USAGE EXIT.**
Both are `return 2` in a function. **THE ONLY DISCRIMINATOR IS PROPAGATION**: does the value
REACH the process exit? `_num_srcs()` is called at
`gates/amd_dsl_census-oracle.py:1025` as `row(f"numsrcs_{label}", _num_srcs(set(names)))` —
its value is a **row**, not an exit.

**SO THE CLASSIFIER NEEDS A PROPAGATION FIXPOINT, AND IT IS IN `census.py`
(`exit_reaching`).** It is a fixpoint over the file's own call graph: seed on
`sys.exit(F(...))` / `raise SystemExit(F(...))` and on a name bound to a call and passed to
`sys.exit`; then step — if `reach(F)`, every `G` whose value `F` hands back is itself a
reacher.

**AND THE FIRST VERSION OF THAT FIXPOINT HAD ITS DIRECTION BACKWARDS, AND DROPPED EIGHT REAL
SITES** (`checks/wallcheck.py:591` among them). It was caught by comparing the classifier's
output against the hand-read list, and the corrected version is what produced §2.2. **THIS IS
REPORTED BECAUSE A CONTROL THAT ONLY RUNS ONCE AND PASSES IS NOT A CONTROL.**

### 6.2 THE HONEST LIMIT OF THE CLASSIFIER

**THE CLASSIFIER CANNOT TELL (i) FROM (ii) BY THE NUMBER ALONE. IT CAN TELL THEM BY WHERE THE
NUMBER LIVES — AND THAT IS THE WHOLE OF THE DISTINCTION.** For (i) it observes
`import argparse` plus a `parse_args()` call and **no literal 2**; for (ii) it observes a
literal 2 at a site whose value provably reaches the process exit. **The two observations are
disjoint, and `checks/dup-gate.py` — which has both — is reported with both.** So the answer
to *"if your classifier cannot tell (i) from (ii), say so"* is: **it can, and the site that
proves it is the one the brief named.**

**WHAT IT *CANNOT* DO IS TELL WHICH OF THE 48 DELIBERATE SITES *MEAN* WHAT.** The
classifier reports the mechanism, the line, and the instrument's own message; the MEANING is
read by a human, and §3.5 is that reading.

---

## 7. WHAT THIS DOES NOT SAY

- **Nothing was run that could change the tree.** No gate, no `bend`, no `checks/differ.py` in
  any subcommand, no `checks/e2e*`, no `checks/sweep.py`, no `checks/bounded.py`, nothing
  under `gates/`. The only subprocesses are `git rev-parse HEAD` and, inside
  `argparse-control.py`, the unit's own scratch file.
- **A site in `sites.rows` means 2 is REACHABLE in the source, not that a run was observed to
  produce it.** §3.5's meaning-groups are read off the instrument's own message, which is
  stronger than a code but is still a reading.
- **The counts MOVE.** The instrument population read 296, 297, 298 and 299 across four runs
  in one hour. Quote these with the timestamp, or not at all.
- **The `argparse-usage` class is INFERRED, not observed, for the 98 instruments.** The
  mechanism is *proved* on one scratch reproduction (§2.1) and the structural condition
  (`import argparse` + a `parse_args()` call + no literal 2) is *read* on the other 96. An
  instrument that overrides `ArgumentParser.error` would be a false positive; **a search of
  `checks/` and `gates/` for an `error(` override found none**, and the argparse control
  confirms the default behaviour.
- **The 214 instruments in the population whose exit value is COMPUTED (a local name, not a
  subprocess) are a "2 IS NOT EXCLUDED" class, not a "reaches 2" class.** They are not in
  `sites.rows` as 2-sites. **Their names are in the census's own output** (the rows the
  classifier marks `unresolved`), and the count is a lower bound on what a static census can
  see. **A negative result is a result**: the propagation fixpoint resolved every one of the
  48 deliberate sites, and it also resolved `gates/amd_dsl_census-oracle.py:1046` OUT of the
  deliberate class — so the filter is not simply refusing to answer.
- **Nothing was fixed.** `checks/`, `gates/`, `AGENTS.md` and `.agents/TODO.md` are
  byte-unchanged by this unit. The only files written are under `.agents/slop/exit2/`.
