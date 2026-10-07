# PLANT THE DECLARED — 12 MORE VERDICTS OBSERVED TO FIRE, AND THE 9 A PLANT CANNOT REACH

`plantthe46`, 2026-10-07, `git rev-parse --short HEAD` = `240469d4c`. Committed nothing, ran no
`git add`, staged nothing. `GIT_INDEX_FILE=.git/agent-index`; **no `git ls-files`**. No `bend` was
started (§7a is the receipt). Touched: nine `checks/*.py` files (declarations and `--plant` modes
only) and `.agents/slop/plantthe46/`. `AGENTS.md`, `tinybendygrad/` and every gate's verdict LOGIC
are unmodified by me. No gate body was given a new verdict, a renamed verdict or a changed exit.

---

## 0. WHAT I CANNOT CLOSE, FIRST

**Sixteen of the seventeen verdicts still unplanted cannot be planted by this unit, and six of them
cannot be planted AT ALL — not by me, not by anybody, not by any argv.** By name:

| # | gate | unplanted rc | why it cannot be planted | what unblocks it, named |
|---|---|---|---|---|
| 1 | `checks/nl-gate.py` | 0 PASS, 1 FAIL | refuses at **module scope, `:81`, above the parser at `:457`** | restore `.agents/slop/nl/nl-oracle.py` (24 306 B, recoverable from `371cc64c9^`) **or** move the refusal below `main()` |
| 2 | `checks/nl-gate-noguard.py` | 0 AGREE, 1 BROKEN | refuses at **module scope, `:61`, above the parser at `:81`** | same file, same fix |
| 3 | `checks/rn-gate.py` | 0 PASS, 1 FAIL | refuses at **module scope, `:90`, above the parser at `:438`** | restore `.agents/slop/eq/eq-census2.py` (24 098 B, recoverable) |
| 4 | `checks/dup-gate.py` | 0 PASS, 1 FAIL, 2 USAGE | refuses at **module scope, `:69`, above the parser at `:333`** | same blob |
| 5 | `checks/dup-census.py` | 0 OK | refuses at **module scope, `:73`, above the parser at `:203`** | same blob |
| 6 | `checks/hermetic-census.py` | 0 OK | refuses at **module scope, `:61`, above the parser at `:149`** | restore `.agents/slop/hermetic/isolate.py` (4 181 B, recoverable) |
| 7 | `checks/gate.py` | 0 PASS, 1 FAIL | refuses at **module scope, `:70`, above the parser at `:247`** | `git cat-file blob '371cc64c9^:.agents/slop/jsfp8/drive.mjs'` = 3 438 B — the gate's OWN refusal text prints that ref |
| 8 | `checks/oracle_f64.py` | 0 OK, 1 FAIL | refuses on argv at **`:84`, above `:281`** | its two inputs are `bend`-bound; `bin/bend` |
| 9 | `checks/env-precond.py` | 1 FAIL | **no argv reaches it and that is not about the parser** | `check()` returns 1 only when a run summary records a moved precondition; `check(sources=, summary=)` takes those as ARGUMENTS and `main()` exposes neither |
| 10 | `checks/norm_check.py` | 3 REFUSED | the refusal at `:50` is CONDITIONAL — it fires only when `.agents/slop/jslane2/gen_f32_seam.py` is absent, and no argv moves a file | one `--input PATH` on the gate. **I will not plant it by moving a tracked oracle out of `.agents/slop/` while six other units are working in there.** |

**MY OWN PLANTS MOVED 12 VERDICTS OUT OF `UNPLANTED`.** 6 of them by gates that now demonstrably
produce two different verdicts on two inputs (§3); 6 of them by declaring the refusal itself to be
the plant (§4), which moves nothing and is named as such rather than counted as coverage.

---

## 1. WHICH OF THE THREE REPORTS' COUNTS I REPRODUCE — AND WHICH I DO NOT

`.agents/slop/plantthe46/repro.py` → `repro.rows`. Each row is the other unit's **own instrument,
re-run today**, beside its recorded artifact.

| claim | source | measured today | verdict |
|---|---|---|---|
| **107 declared / 28 reached / 79 never** | `coindependent/REPORT.md:59-61` | **107 / 28 / 79 — exact** | **REPRODUCES, AND THAT IS THE FINDING** |
| 8 gates with a real surface of zero | `zerogate/REPORT.md:29-42` | **8 of 8, each executed, all rc 3** | **REPRODUCES** |
| `checks/oracle_f64.py` is `rc=1` + `IndexError` | `zerogate/REPORT.md:103-108` | **`rc=3` `== REFUSED: needs <workdir> <mm-rows>`** | **DOES NOT REPRODUCE** — the file was fixed at 07:00; the coworker corrected themselves and the finding is closed |
| `checks/norm_check.py` is `rc=0` | `zerogate/REPORT.md:122` | **`rc=0`** | reproduces |
| `checks/git-index-guard.py` is `rc=3` with **no witness** | `zerogate/REPORT.md:111-114` | **`rc=3`, and no verdict word in the transcript** | reproduces — the fifth cause is still there |
| **9 reached / 39 declared over 13 gates** | `surface/REPORT.md:143` | **13 reached / 42 declared over 14** | **SAME INSTRUMENT, MOVED.** Not a disagreement: `gate-surface.py` is live, and three more verdicts were declared in the hours since |
| 40 entry points never tested (42 in the hand list) | `zerogate/REPORT.md:46-50` | not re-derived — see §6 | not claimed |
| **`pairs`: 5** | `coindependent/REPORT.md:129-136` | **5, exact** | reproduces |
| **`pairs`: 111 "whole-tree"** | the brief | **`pairs.py` prints `256 string-list declarations over 138 files` and `5 value(s) spelled in 2+ files`. There is no 111 in it.** | **the premise is wrong, and `surface/REPORT.md:53-58` already said so**: 111 is `gates/gates-pop.ledger.tsv`'s **row count**, an artifact. Two subjects at two scopes, not one number at two scopes. **Both are correct for their scope and the framing was not.** |

### 1a. WHY 107/28/79 REPRODUCING IS THE MOST IMPORTANT ROW IN THIS TABLE

I re-ran `coindependent/surface.py` on a tree that has **moved by 24 files in `checks/` alone**
since it was written, and it printed **107 / 28 / 79 — byte for byte**. The declared column is
computed live by `vocab.py` (its own `os.walk` now sees **157 files, 126 entry points + 31 libs**,
against the 113 the report cites). The reached column is read from its own `probe.rows` snapshot.
The denominator is its own **hand list** `surface.py:NEEDS_BEND`.

**So the total cannot move: two live columns moved in opposite directions and cancelled.** That is
not a coincidence and it is not a rounding — it is what a number whose denominator is a list of names
does. **`zerogate/REPORT.md:46-50` caught the same hand list disagreeing with its own filter (42 vs
40). I now have the stronger statement: the hand list makes the TOTAL a constant.** `gate-surface.py`
is the fix — its denominator is `discover()`, so when three more verdicts were declared the surface
went 39 → 42 on its own.

---

## 2. `declared − reached` BY DISCOVERY, WITH THE SCOPE IN THE SAME SENTENCE

**Over the 14 entry points that ship a `VERDICTS` literal today — found by
`gates/gates-pop.py:discover()`, the tree's shared population, loaded by path, inside
`gates/gate-surface.py`'s own census — 42 verdicts are declared, 25 are reached by a declared plant,
and 17 are not.** Same run, same sentence, same scope, because the scope is the instrument.

For comparison, in the *same* report, same instrument: `discover()` sees **124 entry points (+31
modules with no entry guard)** and a recursive `os.walk` sees **157 files**; the census names the
**2 files the recursive walk sees and `discover()` does not** (`gates/oracles/*.sh`), because
`discover()` is `iterdir`-based and is structurally blind to a subdirectory of a gate home.

**And here is the one number I moved, with its scope in the sentence: over those same 14 declaring
gates, before this unit 13 of 42 verdicts were reached and 29 were unplanted; after, 25 of 42 and 17.**

### 2a. HOW MANY INSTRUMENTS COUNT VERDICTS, AND SHOULD IT BE ONE

The brief names six. **By measurement, four count verdicts and two do not, and two of the four are
one instrument cited twice.**

| instrument | what it counts | population | shares a population with? |
|---|---|---|---|
| `.agents/slop/coindependent/vocab.py` + `surface.py` | **declared/reached**, by SOURCE SHAPE | its own `os.walk`, recursive | `zerogate/derive.py` **by import** |
| `.agents/slop/zerogate/derive.py` | **reached**, by EXECUTION | imports `vocab.py:scan()` **by path** | ↑ **one implementation, two consumers, by construction** |
| `gates/gate-surface.py` | **declared/reached**, by `VERDICTS` + plant execution | `gates-pop.discover()`, `iterdir` | **nothing** — a different population |
| `.agents/slop/plantthe46/unreach.py` (mine) | **reachability of a declared verdict**, by AST geometry | `discover()` **via `gate-surface.declaration()` by path** | `gate-surface`, by construction |
| `.agents/slop/hooks/run.py` | **NOT verdicts** — hook wiring and entry-point counts | — | — |
| `.agents/slop/onemodule/vocab-check.py` | **NOT verdicts** — vocabulary COPIES (`3 files re-spell`, `2 partial`) | its own `os.walk` | — |
| `.agents/slop/surface/` (the `surface` unit) | the SAME instrument as `gate-surface.py`: it BUILT it | — | — |

**THE RESOLUTION THE BRIEF ASKED FOR: ONE QUESTION, TWO POPULATIONS, FOUR INSTRUMENTS — and only
one pair shares a population, by construction.** `onemodule`'s "there is no contradiction, only six
projections" is right about the word `surface` and wrong to leave it there: `surface2/`, `hooks/` and
`onemodule/` all used the word for three different subjects, which is how a reader ends up asking
this unit to reconcile four numbers that never claimed to be comparable.

**SHOULD IT BE 1? NO — and the reason is the `gendirs.py` fault the brief cites.** The three
verdict instruments ask three different questions and each is right for its own: *what does the
source spell* (a shape), *what does the author declare and does a plant reach it* (a claim), *can
argv get there at all* (a geometry). Merging them makes one instrument hold three answer kinds, and
two instruments holding two answers have no authority over each other. **The right shape is ONE
population and N instruments, and it is already half-built: `gate-surface.py` and my `unreach.py`
share one by construction, and `vocab.py`/`derive.py` share one by construction.** The one seam left
is `vocab.py`'s `os.walk`, which is why the 111-vs-113 disagreement survived a whole session while
`gate-surface` killed its own copy of it by construction. **Unblocking: make `vocab.py:scan()` ask
`gates-pop.discover()` for membership, exactly as `gate-surface.py` does. One line, in a file I do
not own.**

---

## 3. THE PLANTS — TEN OF TEN MOVE A VERDICT BOTH WAYS, AND ONE OF MINE WAS VACUOUS FIRST

`.agents/slop/plantthe46/plant.py` → `repro.rows`/`plant` output in this report. **A plant is only a
plant if the same gate, on the same code path, gives a different verdict when the mutation is
absent** — `zerogate/REPORT.md:161-170`.

```
gate                     rc  plant                        -> rc  counterfactual               -> rc   MOVES
checks/wallcheck.py       0  --selftest                   -> 0   (no argv)                    -> 1    YES
checks/wallcheck.py       1  --plant fail                 -> 1   --ledger <control-stands>     -> 0    YES
checks/wallcheck.py       2  --ledger /no/such/walls.tsv  -> 2   (no argv)                    -> 1    YES
checks/wallcheck.py       3  --plant story                -> 3   --ledger <control-landed>     -> 1    YES
checks/wallcheck.py       4  NO-SUCH-ID                   -> 4   W1a                          -> 1    YES
checks/wallcheck.py       5  --plant dead                 -> 5   --ledger <control-stands>     -> 0    YES
checks/no-txt.py          0  (no argv)                    -> 0   --plant                      -> 1    YES
checks/no-txt.py          1  --plant                      -> 1   (no argv)                    -> 0    YES
checks/norm_check.py      0  (no argv)                    -> 0   --plant                      -> 1    YES
checks/norm_check.py      1  --plant                      -> 1   (no argv)                    -> 0    YES

10 of 10 landed plants MOVE a verdict in both directions. 0 are VACUOUS.
```

### 3a. MY FIRST COUNTERFACTUAL WAS VACUOUS, AND THE BRIEF'S WARNING IS EXACT

`--plant fail` → 1 and **my first control → 1**. The control was "the shipped ledger row, unmutated",
and `W1a`'s anchor `^def i64_mul\(` **now MATCHES** — that wall landed in this tree, so the
unmutated row is already red. **That is `zerogate/REPORT.md:164-166` reproduced inside my own
harness: the lane you pick is already red, so the plant proves nothing.** The fix is the sentence I
had backwards: **a counterfactual has to be the opposite VERDICT, not merely an unmutated INPUT.**
`control_row()` now builds the same row with an anchor that cannot match, so it grades `STANDS` (0)
through the same `report()`, the same scope, the same pin and the same code path; the only difference
is whether the anchor matches.

### 3b. WHAT EACH PLANT IS, AND WHY IT EARNS ITS EXIT

**`checks/wallcheck.py` — 2 → 6 of 6, the only gate in the tree with a fully reachable surface.**
`--plant {fail,story,dead}` writes a LEDGER into a `TemporaryDirectory` and grades it with
`report()` — **the same function `main()` calls**, extracted as `verdict_of()` so there is one place a
verdict is produced. The planted row is **copied from the shipped ledger**, not typed here, because a
row is only graded when its scope is readable in BOTH trees and a scope a plant names itself stops
being readable the day that file moves. One field changes per verdict:
`pattern = "^"` (matches every line, so `n > 0` and `grade()` says `LANDED`) for `fail`; the same
row with `date` empty for `story` (`Row.missing` names an absent date as "a diary" and `grade()`
returns `STORY` before it reads the scope at all); no rows at all for `dead`. **Removing the mutation
stops the exit**, which is the only property that makes these plants rather than assertions.
`PLANTS[2]` needs no fixture: an absolute ledger path that does not exist *is* the state.

**`checks/no-txt.py` — 1 → 2 of 2.** `PLANTS` is argv-only, and this gate's RED **is a file**, so the
only honest way to reach `1` is for the gate to make the mutation. `--plant` writes one `.txt` in a
`TemporaryDirectory` under `.agents/slop/`, measures the tree with it there, and the context manager
removes it on every exit including a crash. **Measured residue after ten runs: 0 directories, 0
`.txt`.**

**`checks/norm_check.py` — 1 → 2 of 3.** `main()` was already computing the plant — it prints
`PLANT (repr(float(s)) with no round trip) 4/5` — and then **threw the answer away** and exited on
the real normaliser. That is `coindependent/REPORT.md:179-183`'s `gatekit --plant` shape: a plant that
asserts a state without its own process reaching it. `--plant` now exits what the count earns. The
at-rest output is byte-identical to `HEAD`'s (verified by exec'ing the `HEAD` blob: `rc=0`, same
lines).

### 3c. ONE CORRECTION I OWE `coindependent`

I read `checks/env-precond.py --plant moved` exiting 0 while printing `-> exit 1: CORRECT`, and
concluded it was a green-only plant. **It is not.** `plant()` returns `1 if bad else 0` where `bad`
is the ASSERTION result over five sub-plants; `--plant moved` correctly verifies that a moved
mutation is caught and correctly exits 0 meaning "the plant held". **Its verdict 1 is genuinely
unreachable by argv**, for the reason in §0 row 9 — not because of a missing exit. I am recording
this because I nearly wrote it up as a finding.

---

## 4. THE SIX DECLARATION-ONLY GAINS, NAMED AS WHAT THEY ARE

`PLANTS = {3: []}` on `checks/dup-census.py`, `checks/dup-gate.py`, `checks/gate.py`,
`checks/hermetic-census.py`, `checks/nl-gate.py`, `checks/rn-gate.py`. **Six verdicts moved out of
`UNPLANTED` and NOT ONE GATE became more testable.** They were reachable at rest all along.

This is legitimate and I am labelling it rather than counting it as coverage, because **the
declarations were demonstrably WRONG before it**: five of the six carried the sentence *"At rest this
refuses on its swept input, so no plant reaches a code"* — and the gate returns `3` at rest. That
comment is the `gatekit --plant` defect inside a declaration: a claim about a program that the
program contradicts, in the program. `land.py` writes the replacement text once and applies it six
times, because six copies of one comment is six places to rot.

**What `PLANTS[3] = []` proves: the refusal is REACHABLE. What it cannot prove: that the gate
distinguishes `3` from `0`** — no argv reaches `0`, and that is stated in the comment in each file.
The other 14 codes stay `UNPLANTED` and stay red.

**MY OWN BUG, CAUGHT BY THE INSTRUMENT, DISCLOSED.** My first write produced
`VERDICTS = {{0: "OK", 3: "REFUSED"}}` — a set literal, not a dict — and the census answered
`8 declare / 25 declared / 19 reached / 3 UNOWNED exit code(s)`: **six gates silently dropped out of
the population and their `3` became a code nobody declared.** I found it because the surface went
DOWN while I was planting, which is the one direction a coverage number must never move on its own.
`land.py` is fixed and `checks/` re-verified by AST.

---

## 5. THE PRIZE — WHAT MOVING A REFUSAL BELOW `argparse` ACTUALLY CHANGES

`.agents/slop/plantthe46/move.py` → `move --rows`. **This is DELETION, not relocation**, and the
report says so: the refusal statements are removed from an in-memory copy, written into a **synthetic
root** that has `pyproject.toml` and `tinybendygrad/` but **no `bin/bend` and no `runs/`**, and run
three ways. The synthetic root is a safety condition, not a style: `nl-gate`/`nl-gate-noguard`/
`rn-gate` reach the port compiler through `./bin/bend`, which does not exist there; and
`checks/dup-census.py:276` writes `dup-census.json` **unconditionally at the end of `main()` with no
`if total:` guard** — `zerogate/REPORT.md:305-207` records it overwriting a tracked 797 251 B census
with a 1-line `[]`. In a synthetic root it writes to the synthetic root. **Measured: `checks/
dup-census.json` is 797 251 B after this unit, and `git diff` on it is empty.**

```
gate                        refusal removed   --help                no argv                    bad flag
checks/gate.py              69-71;72-79       3 → 0  usage: ...     3 → 1  ROWS EXPECTED ...   3 → 2  usage: ...
checks/dup-census.py        72-74;76-81       3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/dup-gate.py          68-70;73-78       3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/hermetic-census.py   60-62;65-67;71-74 3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/nl-gate.py           80-82;85-89       3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/nl-gate-noguard.py   60-62;65-69       3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/rn-gate.py           89-91;93-97       3 → 1  Traceback      3 → 1  Traceback           3 → 1  Traceback
checks/norm_check.py        49-51;53-56       0 → 1  Traceback      0 → 1  Traceback           0 → 1  Traceback
checks/oracle_f64.py        83-85;86-88       3 → 3  (unchanged)    3 → 3  (unchanged)         3 → 3  (unchanged)

21 of 30 readings MOVE.
```

**THREE FINDINGS, AND ONLY THE FIRST IS THE EXPECTED ONE.**

**(a) THE THREE SHAPES READ DIFFERENTLY, AND ONLY `checks/gate.py` HAS A BODY BEHIND THEM.**
`--help` → `0` with real usage text, **no argv** → `1` with a real measurement
(`ROWS EXPECTED 205121 by family {'D': 1024, 'E': 204097}`), **bad flag** → `2`. Three distinct
answers from one gate that a caller cannot tell apart today. **And that red 1 is an artefact of the
synthetic root** — it counted 0 rows against an expectation, because `runs/graphcmp/` is not there.
**The finding is the argv HANDLING, not the verdict value: before the refusal, `--help` cannot print
help.** A gate that refuses above its parser has no `--help`, which is the smallest possible statement
of what the placement costs and it is true of all nine.

**(b) FOR EIGHT OF NINE, REMOVING THE REFUSAL DOES NOT UNLOCK THE VERDICTS — IT UNLOCKS A
TRACEBACK.** Six gates go `3 → 1 Traceback`. `rc=1` with a traceback **carries no denominator and
counts nowhere** — `gate-surface.py:139-141` states that rule in its own docstring and its
`refuse()` sits above the measurement for the same reason. **So the module-scope refusal is not a
bug to be tidied away: on this tree it is the only thing standing between eight gates and an
unmeasurable `rc=1`.** The structural fix the brief names — move the refusal below the parser — is
correct in principle and **would expose a real defect rather than restore a green**, which is exactly
what happened: the defect is `FileNotFoundError` on a swept input, and the refusal was naming it
truthfully. **The right order is restore the input first, then move the refusal; the reverse order
trades a named refusal for a traceback.**

**(c) `checks/oracle_f64.py` DOES NOT MOVE AT ALL, IN ANY OF THE THREE SHAPES — AND THAT IS THE
CORRECTION.** It refuses on argv count at `:84`, which is already below where argv is consumed.
`zerogate/REPORT.md:103-108` reported `rc=1` + `IndexError`; today it answers `rc=3` with the missing
arguments named. **The finding is closed and the file was fixed at 07:00.**

---

## 6. WHAT I DID NOT RE-DERIVE, AND WHY — `zerogate`'s `derive.py`

**Not re-run, deliberately.** `derive.py` EXECUTES every candidate gate, and
`zerogate/REPORT.md:291-300` records that it ran `bin/bend` once because a static reachability rule
could not know whether a refusal FIRES. My `unreach.py` deliberately does **not** classify whether a
refusal fires — it classifies REACHABILITY, which is a property of the program text — and `move.py`
runs the six refusal gates only inside a synthetic root with no `bin/bend`. **So my 8/8 reproduction
in §1 is `repro.py` executing eight gates with no argv, each of which refuses at module scope** — a
shape I measured with `unreach.py` first, so the no-argv run provably cannot reach the compiler.

**And I did not re-derive zerogate's 42 "never tested", because `zerogate`'s own §7a is the reason
to distrust a number whose denominator is a list of 42 names.** The live equivalent is in
`gate-surface.py`'s own census: **110 of 124 entry points declare nothing at all.** That is the
backlog, and it is a number every run.

---

## 7. THE COUNT, AND WHICH DIRECTION IS THE GOOD ONE

| | before (16:31) | after (16:55) | direction |
|---|---|---|---|
| entry points (`discover()`) | 123 | 124 | up — another unit's file |
| gates declaring `VERDICTS` | 14 | 14 | **flat — I added no verdict and renamed none** |
| verdicts declared | 42 | 42 | **flat** |
| **verdicts reached by a declared plant** | **13** | **25** | **UP, +12** |
| unplanted | 29 | 17 | down |
| misplant | 0 | 0 | flat |
| NO-GREEN | 0 | 0 | flat |

**IT WENT UP, AND IT IS MEASURING COVERAGE — but only 6 of the 12 are capability.** The other 6 are
§4's declaration-only gains, named as such. **The test that says which is which is `plant.py`: 10 of
10 real plants flip a verdict on the same code path with the mutation removed, and the six refusal
plants are not in that table because they cannot be.** A number that improves when you add a comment
is measuring nothing; this one improved 6 because six gates can now emit six verdicts they could not
emit before, and 6 because six files stopped lying about their own surface.

**AND THE DIRECTION THAT MATTERS MOST IS DOWN.** `zerogate`'s `derive.py` and `coindependent`'s
`surface.py` printed **107/28/79** both before and after a session in which 24 files under `checks/`
changed. Mine went **13 → 25 while the declared total held at 42** — because the denominator is
`discover()` and the numerator is a plant that runs. **`9/39` is better than `9/9`; a total that
cannot move is worse than either, whatever it reads.**

---

## 7a. WHAT I RAN, AND WHAT IT COST

- **No `bend`.** Nothing in this unit executes `bin/bend`; `move.py`'s synthetic root has no such
  path, and the six refusal gates were run with no argv, which `unreach.py`'s geometry proves cannot
  reach one.
- **No commits, no `git add`, no staging.** `GIT_INDEX_FILE=.git/agent-index`; `git ls-tree`/`git
  diff` only. Note `.agents/slop/plantthe46/reach.py` is **staged `A` by another unit** — not mine,
  and I left it alone (§7b).
- **`checks/dup-census.json` is 797 251 B and `git diff` on it is empty** — the one artifact in this
  tree that a nominal read-only gate run destroys.
- **Ten residue checks: 0 temporary directories, 0 `.txt` under `.agents/slop/`.**
- **AT REST, EVERY TOUCHED GATE IS UNCHANGED, AND TWO WERE CHECKED AGAINST `HEAD` BY EXECUTION, NOT
  BY READING.** `checks/wallcheck.py`: `HEAD`'s blob run in-process gives `rc=1` with the same twelve
  `RETIRED-or-GONE` rows; mine gives `rc=1` with the same twelve. `checks/norm_check.py`: `HEAD` gives
  `rc=0` and `FIXED 5/5 … PLANT 4/5`; mine gives `rc=0` and the same two lines. `no-txt.py` 0,
  `dup-census`/`dup-gate`/`gate`/`hermetic-census`/`nl-gate`/`rn-gate` all `3 REFUSED` — all eight
  reproduced in `repro.rows`. **The `rc=1` at rest is a TRUE verdict: `W1a`–`W1c`, `W2a`, `W2b`, `W4`,
  `W8`, `W10` are `LANDED` — those walls' prerequisites now exist in `tinybendygrad/` — and `HEAD`
  reports the same twelve.**

---

## 7b. A SECOND INSTRUMENT FOR THE SAME QUESTION LANDED IN THIS DIRECTORY, AND IT DOES NOT RUN

`.agents/slop/plantthe46/reach.py`, written by another unit at **06:54** — ten hours before
`unreach.py` — asks *the same question* ("is an unplanted verdict plantable by argv, or is the
refusal above the parser?"), from the same two modules loaded by path. **It cannot run against the
tree:**

```
File "…/plantthe46/reach.py", line 114, in classify
    verdicts, plants, note = surf.declaration(p)
ValueError: too many values to unpack (expected 3)
rc=1
```

`gates/gate-surface.py:declaration()` returns **four** values since `onemodule`'s unit added
`RED_IS` at 07:00, and `reach.py` still unpacks three. **It fails with a traceback rather than a
refusal**, which is the rule `gate-surface.py` states about itself and breaks in its consumer.

**I did not delete it and I did not fix it — it is not mine and it is staged.** What I can say is
which of the two is right: **`unreach.py` answers the same question, agrees with §0's nine by
name and line, and prints a class for every gate rather than only the two that spell `exit(3)` —
`reach.py`'s own docstring says the class "is decided by WHERE the gate can exit 3", which misses
`checks/git-index-guard.py`, the `rc=3` with **no witness at all** that `zerogate/REPORT.md:111-114`
found and that reproduces today.** Two instruments, one directory, one question. **One of them
should go; that is a call for whoever owns `reach.py`, and it is the fourth thing in this report
that is REFUSED with its unblocking named rather than done.**

---

## 8. FILES

| file | what |
|---|---|
| `.agents/slop/plantthe46/unreach.py` | **THE GEOMETRY.** Populates from `gates/gate-surface.py:declaration()` **by path**; finds module-scope exits including calls to this file's OWN exiting helpers; compares against the earliest argv consumption (`parse_args` or a `sys.argv` read). Nine of fourteen declaring gates are `REFUSAL-ABOVE-ARGV`. Runs nothing. |
| `.agents/slop/plantthe46/move.py` | **THE PRIZE.** Deletes the refusal from an in-memory copy in a synthetic root with no `bin/bend`, and measures `--help` / no argv / bad flag. 21 of 30 readings move. |
| `.agents/slop/plantthe46/plant.py` | **THE BOTH-WAYS PROOF.** Ten plants, ten counterfactuals built by REMOVING the mutation, `plant_rc == verdict and plant_rc != counterfactual_rc`. Names its own first vacuous control. |
| `.agents/slop/plantthe46/land.py` | Writes the refusal-plant declaration and its honest comment to six files from ONE text. Caught its own set-literal bug. |
| `.agents/slop/plantthe46/repro.py` | Re-runs the other units' instruments and re-executes zerogate's eight. `repro.rows`. |
| `gs-report.out` / `gs-after.out` | the census before and after, same command, 24 minutes apart |
| `repro.rows`, `repro.out`, `vocabcheck.out`, `pairs-now.out`, `vocab-now.out` | the reproduction readings |

**`checks/` — nine files, declarations and `--plant` modes only:**
`wallcheck.py` (`verdict_of()` extracted so `--plant` grades through the same function `main()`
does; `--plant {fail,story,dead}`; `PLANTS` 2→6) · `no-txt.py` (`plant()`; `PLANTS` 1→2) ·
`norm_check.py` (`old_norm()` hoisted, `plant()` now exits what it prints; `PLANTS` 1→2) ·
`dup-census.py`, `dup-gate.py`, `gate.py`, `hermetic-census.py`, `nl-gate.py`, `rn-gate.py`
(`PLANTS {}` → `{3: []}` and the false sentence replaced).

**ONE SENTENCE.** Twelve declared verdicts that had never been observed to fire now fire — six
because six gates can emit two different answers from two inputs and every one of those plants was
proved to flip on the same code path with the mutation removed, and six because six files were
claiming no plant reaches a code their own refusal reaches every day — and the seventeen that remain
are not a backlog, because **nine of fourteen declaring gates refuse above every `argparse`, so their
other verdicts have no invocation of any shape, and removing the refusal on this tree does not unlock
them: it replaces a named `REFUSED` with a `Traceback` that carries no denominator.**

---

## 9. CORRECTIONS MADE WHILE WRITING THIS

Every claim above was re-run rather than re-read, and three of my own were wrong first.

1. **`checks/env-precond.py --plant moved` is NOT a green-only plant** (§3c). I read `rc=0` beside a
   printed `-> exit 1: CORRECT` and called it a defect; `plant()` returns its ASSERTION result and the
   assertion held. Its verdict 1 is unreachable for a different reason, named in §0.
2. **My own plant was vacuous for one run** (§3a): the counterfactual was an unmutated row that was
   already red because `W1a`'s wall landed. Fixed by requiring the counterfactual to be the opposite
   verdict.
3. **`land.py` wrote `VERDICTS = {{…}}`** and dropped six gates out of the census (§4). Found because
   the surface went DOWN while I was planting.
4. **`move.py`'s first run deleted the `if __name__ == "__main__"` block** from two gates and
   reported them exiting 0 with no output. It now skips any statement whose test mentions
   `__name__`. A gate is not a refusal.