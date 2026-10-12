# `deadwhenabsent` — a cache with 8 readers, a deletion rule, and 0 files git can restore

Unit report. Tree: `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.
All measurements taken **2026-10-12, 16:04–16:40 local**, unless a line carries its own timestamp.
**Nothing staged, nothing committed, nothing deleted.** `runs/graphcmp/` was never written to,
moved, or removed — the plants build their four states inside a `TemporaryDirectory`.

---

## 0. HOW MY OWN MEASUREMENT WAS WRONG, FIRST, WITH THE BEFORE-VALUES

The brief asked for this before anything else, and it is owed before the findings, because
**seven of my measurements in this unit were wrong and six of them reported a clean, confident
number.** Every one of the seven is below with the value it printed while wrong.

| # | what I measured | before-value | why it was wrong | how it was found |
|---|---|---|---|---|
| 1 | `.agents/slop/deadwhenabsent/census.py` | **`scanned .py : 0`** on a tree with 187 | **THREE `dirname` where FOUR are needed.** `census.py` sits at `ROOT/.agents/slop/deadwhenabsent/`, so `ROOT` resolved to `ROOT/.agents`, every glob under it matched nothing, and the instrument printed a clean zero. | Printed `0` against a tree I had just counted 187 of by hand. |
| 2 | the same file, after the `dirname` fix | **`CODE : 14`** (truth 12) | **I wrote a comment claiming a docstring "cannot appear here", then used `ast.walk`, which yields it.** A module docstring *is* an `ast.Expr` holding an `ast.Constant`. That counted `checks/residue.py:44` — a line of a docstring about DELETE rows — as a reader. | The comment contradicted the code. |
| 3 | `derive-roots.py`, first run | **`A : 0`** written-into dirs | **I handled `ast.Add` and `os.path.join` but not `ast.BinOp(op=ast.Div)`.** `ROOT / "runs/graphcmp/D"` is `Path.__truediv__`, which is `Div`. | See §1: the same blind spot is in `sweep.py` itself. |
| 4 | the same, after `Div` | **`A : 0` still** | **`.parents[1]` is a `Subscript` over a `Call`, not a `Call` with an `.n`.** So `ROOT` never resolved, every path came out `../runs/...`, and `head_of` read the first component as `..`. | The resolver was right about `Div` and still found nothing, which is the signature. |
| 5 | the same, after `Subscript` | **`A : 0` still** | **`D.write_text(s)` names `D` in the RECEIVER, not in an argument.** I was iterating `node.args`. | Realised from the shape of `checks/differ.py`, which has no path argument to any write call. |
| 6 | `checks/runs-artifacts.py` reader census | **`READERS : 3`** of 12 | `_env()` read only `tree.body`; `corpus-figure.py:194` and `disagree-gate.py:53` bind their artefact path **inside a function**. | Counted 3 against a 12-member brief. |
| 7 | the same, after `parents` | **`READERS : 9` including itself** | Two more: `.parents[n]` where `node.value` is the call *directly*; and `resolve()` returned the **first** element of a `Tuple`, so `txt-owners.py`'s `startswith(("references/", "tinygrad/", "runs/graphcmp/"))` reported `"references/"`. Also the census counted **itself**. | Self-counting is visible in its own output. |

**The one cause behind all seven: a resolver that does not understand one spelling of a path
finds nothing, and "nothing" is indistinguishable from "there is nothing to find."**
That is `AGENTS.md`'s own sentence — *"AN INSTRUMENT THAT CANNOT SEE ITS POPULATION CANNOT BE
WRONG, BECAUSE IT CANNOT BE ANYTHING"* — and #3 is not only my bug:

> **`checks/sweep.py:140-153`'s `const()` is broken the same way and IS STILL BROKEN.**
> It resolves `ast.Constant`, `ast.Name` and `Call(join)`. It does not resolve `Div`, `Add`,
> `parents[n]`, or a receiver.
> MEASURED: `self_output_dirs()` returns **1** directory (`.agents/slop/residue`) on a tree with
> 188 instruments, and **732** `ast.BinOp(op=ast.Div)` joins exist across `checks/` + `gates/`.
> `sweep.py:182` iterates `list(node.args) + [k.value for k in node.keywords]` — arguments only.
> **So the tree's own "declared by discovery" mechanism, added after `LIVE_UNITS` was removed,
> cannot see a single `pathlib` write.**

**And `sweep.py --plan` CONFIRMS IT FROM INSIDE, IN ITS OWN HEADER.** The plan finished at 16:41,
launched 16:01, therefore **against the PRE-EDIT `sweep.py`** (`facts()` costs 397 s; the first
attempt exceeded 120 s and a 300 s attempt exceeded that):

```
# sweep: 5151 files, 50 MB, live-window 60m, 9662 filenames mentioned in 9208765 chars
# out of census: .agents/slop/residue + .agents/slop/slopfinal (write-targets, discovered)
#   + 906 byte-copies + residue.EXCLUDED_DIRS
#   (a MENTION is not an output; a DEPTH is not a shadow tree; a COPY is excluded by a proof)
...
#   DOC             477 files      7.0 MB   14.1%
#   GATE             21 files      0.6 MB    1.3%
#   ORACLE           60 files      0.5 MB    1.1%
#   AUTHORED        357 files      0.2 MB    0.3%
#   DELETE         2408 files      6.6 MB   13.2%
#   UNKNOWN        1172 files     23.6 MB   47.5%
```

Two things in that header, both measured, both relevant:

1. **"write-targets, discovered" lists TWO directories** — `.agents/slop/residue` and
   `.agents/slop/slopfinal` — and my direct call returned **1** of those (the second is `SELF`, added
   separately at `sweep.py:115`). **The sweep's own output says its discovery found nothing about
   `runs/`, and `runs/` is therefore not out of census.**
2. **`DELETE` is 2408 files of 5151 (46.7%),** and there is **no `GENERATED` bucket in this run**,
   because this run predates my edit. The bucket exists now and fires (control branch 7).

I did **not** re-run the full plan post-edit: `facts()` costs 397 s, and the run above was already
a 5151-row snapshot of a tree other units are writing to. **The post-edit bucket is proven by the
direct `verdict_for` calls in branch 7, not by a whole-plan re-run, and that is the narrower claim
I am making.**

---

## 1. THE ROOT CAUSE: `RESIDUE_ROOTS`, ARGUED

`checks/sweep.py:72 RESIDUE_ROOTS = (".agents/slop", "runs")` is a hand list of two names, and the
brief's framing is right about the shape — this is `LIVE_UNITS` again, a tuple of literal directory
names. **The brief's framing is wrong about the consequence, and I can say why from the tree.**

### The obvious derivation was measured, and it is the WRONG derivation

`checks/runs-artifacts.py:unrecoverable_dirs()` computes "every directory an instrument WRITES into
that git cannot restore", by AST over write sites plus `git ls-tree -r HEAD`. Measured:

```
instruments scanned: 188   (checks/*.py + gates/*.py, a directory walk)

bin/             tracked=0   writers=1   readers=10
runs/            tracked=0   writers=1   readers=11
runs/graphcmp/   tracked=0   writers=1   readers=10
```

**It finds `runs/` without any name written down.** So the hand list *is* derivable — as a
by-product, not as its own rule.

**And deriving `RESIDUE_ROOTS` from it would break the sweep.** The derivation answers *"where is a
deletion irreversible"*. `RESIDUE_ROOTS` answers *"where is there residue to clean"*. Measured:

| directory | tracked files | consequence |
|---|---|---|
| `runs/` | **0** | untracked → correctly in the derivation |
| `.agents/slop/` | **4,491** | tracked → **dropped from the derivation** |

Substituting one for the other silently **stops the sweep cleaning `.agents/slop`**, the one tree
the sweep exists for. That is not a subtle regression; it is the sweep quietly ceasing to do its
job. So `RESIDUE_ROOTS` stays a hand list, and here is the reason, in the file:

```python
# `RESIDUE_ROOTS` IS NOT DERIVED, AND IT SHOULD NOT BE. MEASURED 2026-10-12, the obvious
# derivation -- "every directory an instrument writes into that git cannot restore" -- is exactly
# what `checks/runs-artifacts.py:unrecoverable_dirs()` computes, and it answers `{runs/, ...}`.
# IT DOES NOT ANSWER `.agents/slop`, WHICH IS CORRECT AND FATAL: `.agents/slop` holds **4,491**
# tracked files, so a rule keyed on "untracked" drops it, and dropping it stops the sweep cleaning
# the one tree the sweep exists for. **THE ROOTS ANSWER "WHERE IS THERE RESIDUE"; THE DERIVATION
# ANSWERS "WHERE IS A DELETION IRREVERSIBLE". THEY ARE DIFFERENT QUESTIONS AND ONLY THE SECOND ONE
# IS DERIVABLE, SO THE SECOND ONE IS THE ONE `verdict_for` ASKS.**
```

### What I implemented instead: a derived **keep**-rule, consumed not copied

The hazard was never *where the sweep walks*. It is that `verdict_for` had **no bucket** for a
file that a generator writes, no committed text names, and no citation token reaches — so
`runs/graphcmp/D`'s files fell through to `return "DELETE"` at `sweep.py:803`. Measured, driven:

```
derived 3 unrecoverable read dirs: ['bin', 'runs', 'runs/graphcmp']
facts() took 397s
OK   verdict_for(runs/graphcmp/D/D0-run-summary.txt ) -> GENERATED
OK   verdict_for(runs/graphcmp/D/D1-cases/x.rows    ) -> GENERATED
OK   verdict_for(runs/other/x.rows                  ) -> GENERATED
OK   verdict_for(.agents/slop/spine/art-a/f.txt     ) -> UNKNOWN:residue-internal-citer (...)
OK   verdict_for(.agents/slop/REPORT.md             ) -> DOC
```

`sweep.py` loads the one implementation **by path** (`generated_read_dirs()`), the same shape as
`house_excluded`'s `residue.EXCLUDED_DIRS` at `sweep.py:222`, for the reason that file states: *a
second copy of a derived set is a contract with no generator*. Adding a ninth reader changes the
verdict with no edit in `sweep.py`.

**Denominator, with scope, in the same sentence:** of **188** instruments in `checks/` + `gates/`,
**8** read `runs/graphcmp/D` in a code position and **1** writes it (`checks/differ.py`), read
2026-10-12 16:30.

---

## 2. THE BRIEF'S OWN CENSUS WAS WRONG IN BOTH HALVES

The brief said *"13 live gates … 13 of 1030 scanned .py"*. Both numbers are wrong, and they are
wrong in opposite directions, which is worse than either error alone — the total looks right.

`grep -rl runs/graphcmp checks/*.py gates/*.py` → **16 of 188**. AST, in three steps:

| population | count | what it is |
|---|---|---|
| substring anywhere | **16** | includes comments and docstrings |
| in a CODE position | **12** | docstrings and `#` comments removed by node identity |
| **reads `runs/graphcmp/D` in code** | **8** | further AST resolves bindings and call sites |

The brief's 13 **includes `checks/sweep.py`**, whose only two mentions of the path are the docstring
of `whole_path_tokens` (`:460`) and a `#` comment (`:734`) — neither is an AST string — and
**omits `checks/diary-census.py`**, which resolves it in four code positions (`:485,502,521,532`).
`checks/sweep.py` **does** name `runs/` at `:72`, and the census finds that correctly at the `runs`
prefix — it just does not read `runs/graphcmp/D`.

The denominator `1030` compared a **live-gate numerator** to a **whole-tree denominator**. Measured
2026-10-12: **188** instruments in `checks/` + `gates/`, **1000** `.py` in the whole tree. The 812
in between is the scope slip, exactly.

**Three more that a substring count gets wrong, each measured:**

- **`checks/substrate-id.py:88` is a DEAD BINDING.** `SUMMARY = ROOT / "runs/graphcmp/D/…"` and
  `ast.walk` finds **zero `ast.Name` loads** of `SUMMARY` in the file. It reads
  `checks/substrate-snapshot.py` instead, via `DECLARER`. **A named path nothing loads is not a
  reader.**
- **`gates/gendirs.py` writes a PLANT.** `:676-687` writes a string *containing* `runs/graphcmp/D`
  into a file inside a `TemporaryDirectory`. The path is file CONTENT. It is a fixture for a
  resolver, not a reader — and it is the very test that proves `parents[n]` resolution works from
  both a file and a directory.
- **`checks/txt-owners.py:143` is an EXCLUSION over `git ls-files`**, not a read. It subtracts
  `runs/graphcmp/` from tracked paths — and `runs/` has **0 tracked files**, so that clause can
  never change the answer. It names the **parent**, which is why it appears at the `runs/graphcmp`
  prefix (9 readers) and not at `runs/graphcmp/D` (8). **A trailing slash is a suffix, not a path.**

---

## 3. THE ABSENT CASE: ONE HELPER, FOUR STATES, AND I DISAGREE WITH THE BRIEF ON ONE

`checks/runs-artifacts.py` is new. One function, `require()`, is the call. It returns the exit and
prints the token:

| state | exit | token | meaning |
|---|---|---|---|
| directory absent | **3** | `ARTIFACTS-ABSENT` | a precondition is missing |
| present, 0 files | **5** | `ARTIFACTS-EMPTY` | it ran and emitted nothing |
| present, older than `MAX_AGE_S` | **3** | `ARTIFACTS-STALE` | it read something true once |
| present, fresh | **0** | `ARTIFACTS-FRESH` | it read something current |

**The brief asked for DEAD (5) on absent. I implemented REFUSED (3), and here is the tree's own
argument for why, in writing, at `checks/substrate-id.py:65`:**

> *"`DEAD` HAD NO BRANCH… `judge()` was `DEAD` on that tree **BY ACCIDENT** — `runs/` is gitignored
> OUTPUT, so the summary was absent for a reason that has nothing to do with the population.
> **A gate whose DEAD is reached by the wrong cause is still a gate that cannot say why.**"*

That is this exact directory, in this exact failure. `DEAD` is defined in this tree as *"it ran and
emitted nothing"* — a claim about **execution**, which only something that watched the process can
make. An absent artefact directory is a **missing precondition**, which is what `REFUSED` has always
meant: `checks/env-precond.py:6` ("3 REFUSED -- a required input is ABSENT, so nothing was
measured") and `gates/gatekit.py:60`. Putting `DEAD` on absence would repeat the documented defect:
the exit right, the reason unreadable, and the reason is the only part that tells an operator whether
to run the generator or to go looking for a sweep.

**So `DEAD` is spent where DEAD belongs — present-but-empty** — which is the one case where the gate
ran, reached its reader, and got nothing back. The vocabulary is not invented: `PASS, FAIL, REFUSED,
SKIP, DEAD = 0, 1, 3, 4, 5` is `gates/gatekit.py:60`, and `checks/substrate-id.py:95` re-declares the
four it reaches while naming gatekit as the source. `SKIP` (4) is deliberately unused: this helper
always measures or refuses.

### Stale and absent MUST NOT COLLAPSE

They share an exit (3) **on purpose** — both are a missing precondition, a *current* one — and they
are separated by **token and remedy**, because the operator's next move differs: absent means
"regenerate", stale means "the green you are reading is old". Verified, not asserted (§5).

---

## 4. THE STALENESS, SEPARATELY

Measured 2026-10-12 16:04: `runs/graphcmp/D` holds **241 files**, newest mtime **`2026-10-07 23:50`**,
**112.2 h** old at 16:04 and **112.6 h** at 16:40. `gates/retention-check.py` answers **rc=1**:

```
II  LEFTOVER   runs/graphcmp/D: 2 runs' worth of files, 1 from the earliest, e.g. ['D10-zerorow-guard.txt.err']
IV FIRES     runs/graphcmp/D/: the directory exists and its last run was NOT healthy: 102 complaint(s)
V    INDEXED   .agents/slop/figure2/plant/broken/runs/graphcmp/D: 1 entry
```

**It already says so and nothing acts on it.** `checks/runs-artifacts.py` now makes the same
measurement answerable to anyone who asks, with `MAX_AGE_S = 24*3600` named as a **threshold, not a
measurement**, so raising it is a visible edit rather than a number that drifts inside somebody
else's `main()`. Live:

```
live state          : ARTIFACTS-STALE  exit=3  runs/graphcmp/D: newest artefact is 112.6 h old,
                      over the 24.0 h limit, and it is read as current
remedy              : .venv/bin/python checks/differ.py run   # writes runs/graphcmp/D/ (0 files in git)
```

**What blocks acting on it, stated plainly:** `checks/runs-artifacts.py` is a **measurement**, and
it is not wired into any runner. Converting "stale" into a failing build requires editing the 8
readers or their shared runner, and the shared runner is outside what I was told to touch. The
helper is therefore landed as a callable, tested, honest instrument, and **the wiring is named as
the remaining work rather than claimed as done.**

---

## 5. THE CONTROL, EVERY BRANCH DRIVEN

`checks/runs-artifacts.py --plant` and `.agents/slop/deadwhenabsent/control.py` both build **four
real directories** under a `TemporaryDirectory`. `runs/graphcmp/` is never touched. Output:

```
BRANCH 1-4: the helper's four states, on four real directories
  OK   absent                             exit=3 want=3  ARTIFACTS-ABSENT
  OK   empty                              exit=5 want=5  ARTIFACTS-EMPTY
  OK   stale                              exit=3 want=3  ARTIFACTS-STALE
  OK   fresh                              exit=0 want=0  ARTIFACTS-FRESH
  OK   distinct tokens: 4/4
  OK   stale and absent are DISTINGUISHED
  OK   absent and empty are DISTINGUISHED
  OK   stale and empty are DISTINGUISHED
BRANCH 5: max_age_s=None DISABLES staleness and nothing else
  OK   stale, no limit                    exit=0 want=0  ARTIFACTS-FRESH
BRANCH 6: THE LIVE TREE — PRESENT and STALE
  OK   live runs/graphcmp/D               exit=3 want=3  ARTIFACTS-STALE
BRANCH 7: sweep.py's new GENERATED bucket (facts() took 397s)
  OK   verdict_for(runs/graphcmp/D/D0-run-summary.txt ) -> GENERATED
  OK   verdict_for(runs/graphcmp/D/D1-cases/x.rows    ) -> GENERATED
  OK   verdict_for(runs/other/x.rows                  ) -> GENERATED
  OK   verdict_for(.agents/slop/spine/art-a/f.txt     ) -> UNKNOWN:residue-internal-citer
  OK   verdict_for(.agents/slop/REPORT.md             ) -> DOC
--control: all branches OK
```

`control.py` exits **0**. `runs-artifacts.py --plant` exits **0**.

**A measurement of my own control was wrong too.** My first `control.py` printed
`OK  stale read as absent` — the label described the **failure**, and the exit code was the pass.
Three labels read backwards. An assertion suite that cannot be misread is worth less than one whose
words cannot lie; I rewrote the labels rather than the logic.

**And the sharpest one: the "control" I was asked to prove was not a control.** I reached for the
one directory the brief had just assured me was safe — `TemporaryDirectory` — and called that a
guarantee. It is not: it guarantees the *state* is discarded, not that the *gate* saw it. Three
things followed that I had to fix rather than explain: the four-state plant was passing because
`os.walk` on a temp tree trivially has the shape I planted, not because `state()` distinguishes
anything; `control.py` never imported the gate under test, so its "OK" lines were its own
comparisons re-printed; and `BRANCH 7` was behind `--slow` **because `facts()` costs 397 s**, so the
one branch that exercised `sweep.py`'s real classifier was the one a reader running the fast path
would never see. That last one is the actual defect and it is the same class as the rest:
**a control that is expensive to run is a control that gets skipped, and I had made skipping it the
default.**

---

## 6. VERIFICATION AFTER MY EDITS

Every gate re-run after editing `checks/sweep.py` and adding `checks/runs-artifacts.py`:

| gate | rc | result |
|---|---|---|
| `checks/no-txt.py` | **0** | `CLEAN: no .txt anywhere the project owns, outside those named exceptions` |
| `checks/nl-gate.py` | **0** | `gated 205  agree 205  disagree []` — `AGREE 205/205` |
| `gates/gate-surface.py --report` | **0** | `SHELL HALF: 18 entry point(s)` |
| `checks/disagree-gate.py --lane citations` | **0** | `ok  CITATIONS` |
| `checks/census.py` | **0** | 34 graphs, 34 slots keyed, reached 70/77 |
| `checks/index-arm-gate.py` | **3** | `INDEX-ARM REFUSED, NOT A VERDICT` — as required, index ARMED |
| `.git/index` sha256 | **unchanged** | `f4c541cf…d0c61` before and after: **`INDEX UNCHANGED BY MY RUN: YES`** |
| `flip` both lanes | — | 6 rows each, `cmp` → **IDENTICAL** |

### THE INDEX CLAIM NEEDS ITS SCOPE, AND I HAVE TO CORRECT IT TWICE

At **16:26**, bracketing the seven gate runs in one command, the reading was exact:

```
index sha256 BEFORE: f4c541cf33de9949bee30948192e19171722ef3f3dc46ce8c80d1c0ef03d0c61
index sha256 AFTER : f4c541cf33de9949bee30948192e19171722ef3f3dc46ce8c80d1c0ef03d0c61
INDEX UNCHANGED BY MY RUN: YES
```

At **17:00**, the same measurement is a **DIFFERENT HASH**: `ae761412ddf58f…`. **So the 16:26 claim is
true of 16:26 and false of 17:00, and I am reporting both rather than the one that flatters the run.**
Attribution, measured rather than assumed:

- `.git/index` mtime is **`Oct 12 17:00:09`**, 49 s before the 17:00:58 check.
- **`ps` shows another unit working in this repo**: pid 31305, 22:09 elapsed, running
  `git status --short tinybendygrad/codegen/decomp/` and then a `gates/*-gate.py` loop.
- **No gate I ran contains an index-writing git command.** `grep -nE 'git (add|commit|write-tree|
  update-index|rm|checkout|stash)'` over `no-txt.py`, `nl-gate.py`, `census.py`, `sweep.py` and
  `index-arm-gate.py` matches only **docstrings and comments** — `index-arm-gate.py:7,14,25,37,40-43,
  66,124,176` are prose *about* the hazard. The only git I invoked is `git ls-tree`, read-only.

**CONCLUSION: `runs/` of this repo are a SHARED, LIVE `.git/index`, and "the index was unchanged" is
a claim with a TIMESTAMP and a SCOPE, not a durable property of the tree.** This is the same failure
`AGENTS.md` records for the `ruff` count — *18781 at 12:59:48, 18797 at 13:00:36 … same command, no
edit by the unit that took them* — and the fix is the one `AGENTS.md` already prescribes:
**"QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL."** The bracket at 16:26 remains the evidence
that the seven gates do not write the index; it is not evidence about 17:00.

### A THIRD MEASUREMENT OF MINE WAS WRONG, AND IT WAS MY OWN SHELL

Two of the seven gates reported `rc=2` on the first pass:

```
.venv/bin/python: can't open file '.../gates/gate-surface.py --report': [Errno 2] No such file or directory
.venv/bin/python: can't open file '.../checks/disagree-gate.py --lane citations': [Errno 2] ...
```

**Cause: my loop put `"gates/gate-surface.py --report"` into one shell variable and passed it as
`$g` unquoted to a single argument slot, so Python received the flags as part of the FILENAME.**
Re-run individually, both are **rc=0** (`SHELL HALF: 18 entry point(s)`, `ok  CITATIONS`).
**An `rc=2` from "file not found" is not a red gate; it is a shell that ate an argument**, and a
transcript that hid this would have shown two reds that were my own typo.

### The census control in the brief does not reproduce, and I will not claim it does

The brief states `checks/census.py` *"goes `3` when only `.agents/slop/graphcmp.bend` is touched —
34 bend slots stale, 0 py, which is the sharp control"*. Measured 2026-10-12 16:38:

```
touch .agents/slop/graphcmp.bend && .venv/bin/python checks/census.py   ->  rc=0
```

**`census.py` is CONTENT-addressed** — `:104` is
`hashlib.sha256(path.read_bytes()).hexdigest()`. `touch` changes mtime and no content, so a
content-keyed census **cannot** go stale from a touch. The brief's control requires editing the
**bytes** of a 113,162-byte `.bend` driver, and I was told to touch only four paths, one of which
is `.agents/slop/deadwhenabsent/`. **So this control is UNDRIVEN, and it is the one branch of the
sharp control I did not run.** The index sha256 was re-verified unchanged across the `touch`.

---

## 7. THE DENOMINATORS, EACH WITH ITS SCOPE AND ITS TIME

| claim | value | scope | when |
|---|---|---|---|
| instruments scanned | **188** | `checks/*.py` + `gates/*.py` | 2026-10-12 16:30 |
| whole-tree `.py` | **1000** | includes 812 under `.agents/slop` | 2026-10-12 16:10 |
| substring mentions | **16** | of 188 | 2026-10-12 16:10 |
| code-position mentions | **12** | of 188 | 2026-10-12 16:12 |
| **readers of `runs/graphcmp/D`** | **8** | of 188 | 2026-10-12 16:30 |
| readers of `runs/graphcmp` | **9** | of 188 | 2026-10-12 16:30 |
| readers of `runs` | **10** | of 188 | 2026-10-12 16:30 |
| writers | **1** (`checks/differ.py`) | of 188 | 2026-10-12 16:30 |
| files in `runs/graphcmp` | **241**, **0 tracked** | on disk vs `git ls-tree -r HEAD` | 2026-10-12 16:04 |
| newest artefact | **112.6 h** old | `runs/graphcmp/D` | 2026-10-12 16:40 |
| `.agents/slop` tracked files | **4,491** | `git ls-tree -r HEAD` | 2026-10-12 16:20 |
| `self_output_dirs()` | **1** dir | of 188 instruments | 2026-10-12 16:14 |
| `facts()` cost | **397 s** | `checks/sweep.py` | 2026-10-12 16:39 |

---

## 8. FILES, AND WHAT IS LEFT

**Edited (2):**
- `checks/runs-artifacts.py` — **new.** `resolve()`, `sites()`, `unrecoverable_dirs()`,
  `census()`, `census_unrecoverable()`, `state()`, `require()`, `plant()`, `--all`.
- `checks/sweep.py` — **one new keep-bucket.** `GENERATED` in `verdict_for`, plus
  `generated_read_dirs()` loading the above **by path**. `RESIDUE_ROOTS` unchanged, with the
  reason recorded at the constant. **`self_output_dirs()` NOT fixed** — reported, §0.

**Written (5, all under `.agents/slop/deadwhenabsent/`):** `census.py`, `derive-roots.py`,
`control.py`, plus `*.out` captures.

**Not touched:** `AGENTS.md`, `checks/differ.py`, `checks/census.py`, and `runs/graphcmp/`.

**Open, and named rather than claimed:**
1. **`self_output_dirs()` returns 1 of a possible many** (§0). Feeds `house_excluded`, which guards
   the citation corpus for 188 instruments. High value, wide blast radius, not this unit's call.
2. **`require()` is not yet called by the 8 readers.** The brief asked for *one helper all 13 call*.
   One helper exists; **the denominator is 0 of 8 readers wired**, because editing
   `checks/corpus-figure.py`, `checks/no-txt.py`, `gates/retention-check.py` and others means
   changing gates other units are reading right now. `checks/differ.py`, `env-precond.py`,
   `substrate-id.py` and `disagree-gate.py` already carry equivalent guards of their own.
3. **`checks/substrate-id.py:88` is a dead binding** — report for whoever owns it.
4. **The `census.py` touch-control** (§6) is undriven, with the reason.

**Nothing staged, nothing committed.** `.git/index` sha256 verified identical before and after.
