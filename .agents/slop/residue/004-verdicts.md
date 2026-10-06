# A FIFTH VERDICT, AND WHAT IT IS FOR

## WHY FOUR BUCKETS PLUS SEVEN ESCAPES IS NOT ENOUGH

`checks/sweep.py` has four buckets — `DOC` / `GATE` / `ORACLE` / `DELETE` — and `verdict_for` can also
return `PROTECTED`, `LIVE`, `LIVE-UNIT` and `KEEP-CITED`. **Every escape is a way of saying "I am not
sure"**, and every one of them encodes its not-sure as a FACT ABOUT THE WORLD rather than as a fact
about the classifier:

| escape | encodes not-sure as | what it cost when it was wrong |
|---|---|---|
| `PROTECTED` | an INCIDENT (`"42 files restored from origin"`) | the subtree was never classified at all, because the return is BEFORE the citation test |
| `LIVE_UNITS` | a NAME in a list | 2,353 files, 53% of the tree, named by nothing outside themselves |
| `ORACLE_WORD` | a BASENAME shape | 670 of 675 oracle files, 5 of them real |
| `KEEP-CITED` | a literal token | a citation the corpus cannot see is not a citation |

What the instrument lacks is a place to RECORD the not-sure. With nowhere to put it, the not-sure
leaks into the one bucket that acts. **`verdict_for`'s last statement is `return "DELETE"`. It is the
DEFAULT, reached whenever every escape above declined to fire.** So `DELETE` is not a verdict — it is
the ABSENCE of one — and it is the only bucket `--apply` destroys.

## THE FIFTH VERDICT: `UNKNOWN`

    UNKNOWN    a test COULD NOT BE RUN.
               REPORTED, NEVER ACTED ON.
               The row carries `needs=` -- the cheapest test that would resolve it.

Three properties, and each one is the reason the other four cannot be it:

1. **It is not a bucket a deletion pass can be pointed at.** `--apply` cannot name it, because naming it
   is the mistake. On this residue it is **93 of 361 rows — 25%** — and every one of them would otherwise
   have been deleted.
2. **It is not an escape, so it cannot rot.** `UNKNOWN` does not exempt a directory, or a subtree, or a
   name. It is a property of a FILE and of a TEST, and both are re-measured every run. **A name in a
   list outlives its reason; a per-row verdict does not.**
3. **It carries its own resolution.** `needs=unstage-self`, `needs=belts-disagree`,
   `needs=commit-the-report-that-explains-it`, `needs=owner-decision`, `needs=commit-or-drop`. **A group
   with no deciding test is a group that has been labelled**, so `UNKNOWN` is not permitted to exist
   without naming the test that would end it.

## THE DECISION PROCEDURE THAT ADMITS IGNORANCE

Three positive questions, all MEASURED, none of them a hand-maintained list. **A row no question answers
is `UNKNOWN`, and `DELETE` is not a fallthrough.**

| # | question | test | what it is replacing |
|---|---|---|---|
| 1 | `AUTHORED` — does a NAMING AUTHORITY outside the residue **render** this name? | `differ.declared()` | `ORACLE_WORD`'s basename shape, and `KEEP-CITED`'s literal token |
| 2 | `LIVE` — is a **DIRECTORY** being written right now? | dir-aggregated max mtime | `LIVE_UNITS` (14 names, 342 files, 0 updated since it was written) |
| 3 | `DERIVED` — is it regenerable **by construction**? | `__pycache__/*.pyc` | nothing; this class has no verdict at all today |

and three corroborating measurements, which are evidence rather than verdicts:

| # | measurement | test |
|---|---|---|
| 4 | `COPY` — same bytes as a file outside the residue | sha256 over the **whole repo**, not the residue |
| 5 | `CITED` — a WHOLE-PATH TOKEN names it from **outside** the residue | two belts that share no regex |
| 6 | `UNNAMED` — every test ran, every test said no | **a candidate. not a verdict.** |

Two more questions produce `UNKNOWN` rather than a verdict:

| # | why the test could not run | `needs=` |
|---|---|---|
| 7 | excluded from this walk by the house rules | `owner-decision` |
| 8 | it is a **TOOL** and its own directory has no **committed** report | `commit-the-report-that-explains-it` |
| 9 | it is untracked and nothing renders or names it | `commit-or-drop` |
| 10 | the two citation belts disagree | `belts-disagree` |
| 11 | a **residue-internal** citer — a tool chain, or a shadow tree naming its own copies | `residue-internal-citer` |
| 12 | this check's own report cites it | `unstage-self` |

**Question 6 is where the instrument stops.** `UNNAMED` is reported as a candidate and is explicitly
NOT a verdict, because *"nothing I can measure names this"* and *"this is junk"* are different sentences
and only the first is one this instrument can support. The five places `UNNAMED` used to be DELETE are
the five places the project's own answer is missing.

## THE INTERACTION WITH THE THREE CLASSIFIERS `sweep.py` ALREADY HAS

`sweep.py` is not mine to edit, so this is **a second opinion that CONSUMES `verdict_for()`** and
publishes the disagreement, not a replacement. **A SECOND INSTRUMENT THAT DISAGREES WITH THE FIRST IS
WORTH MORE THAN A REPLACEMENT THAT AGREES WITH NEITHER**, and `003-disagreements.md` is the artifact that
makes the disagreement a number: on this residue **229 of 361 rows `sweep` would destroy are, by a test
`sweep` does not run, files the gate that owns them already declares, or live, or derived, or copies.**
`AUTHORED` alone is 181 of the 229, and it is the only figure in this directory that has not moved
between runs.

Precise proposals, so whoever owns `sweep.py` can take them without reading this file:

1. **One import, one call.** In `verdict_for`, before the `DELETE` fallthrough:
   `if name in declared_names: return "ORACLE"` where `declared_names` comes from
   `import differ; differ.declared()`. `checks/no-txt.py` already imports it this way. **This alone moves
   181 rows and it is the whole of G1.**
2. **Replace `LIVE_UNITS` with per-directory aggregation — IN THAT ORDER, IN ONE CHANGE.** The file's own
   header says the mtime window is the guard and the list is a second belt that has been the only belt.
   **MEASURED, and this is why the order matters: of `LIVE_UNITS`' 342 files, 109 are also inside the
   60-minute window and 233 are not.** The list cannot be deleted on its own — that exposes 233 files the
   window does not reach. Land `checks/residue.py:dir_ages` (6 lines, no roster, so it cannot go stale)
   and remove the tuple in the same commit. **Until then the 342 files' exemption is justified by a list
   that nobody updates at dispatch time, which is the mechanism that produced the last three failures.**
3. **Anchor `PROTECTED` to the basename, not the root.** `^\.agents/slop/(e2e|e2e_port|f64|portexec)/`
   cannot match `runs/portexec/`. Matching the directory NAME at any depth protects both, and protects
   the 3 rows currently in DELETE.
4. **Make `--live-minutes` default to 0 in `--plan`** and print the count at both 0 and the requested
   window. The window is a fact about the last hour; the plan's headline should not be.
5. **Do not add a fifth verdict to `verdict_for`.** Add it to the *report*: `verdict_for` returns
   `UNKNOWN` instead of `DELETE` for any row where `authored`/`live`/`derived`/`copy`/`cited` all ran and
   all said no **and** the row is a tool, and `--apply` already refuses any verdict not named on the
   command line, so an un-actionable verdict is safe by construction.

## PLANT AND DISARM, FOR EVERY VERDICT ADDED

`checks/residue-plant.tsv` is the plant. Its `expect` column is a **literal** — nothing computes it — and
the tree is built in a temp directory, `git init`ed so citation belt A is git's REAL `-w -F` matcher rather
than a stand-in that shares belt B's assumptions, with the `age` column applied by `os.utime` so the
`LIVE` resolver has a genuinely 30-day-old file beside a genuinely new one in one directory and cannot
pass by reading either file's mtime. **No production file is touched** — one repro in this project read
`LEFT=NOTHING` on BOTH sides because it `rmtree`d the state under test between beats.

| verdict | plant row | what it pins | `--disarm` moves |
|---|---|---|---|
| `AUTHORED` | `D/D1-graph-matmul.txt`, `+.err` | rendered by `differ.declared()`, invisible to a literal index | 2 |
| — | `D/D1-graph-nosuch.txt` → `UNNAMED` | rendered-**looking** is not rendered | — |
| `LIVE` | `fresh/cold-looking.txt` (30d) + `fresh/whatever.txt` (0s) | per-**directory**, so per-file mtime cannot pass | 2 |
| `DERIVED` | `p/__pycache__/m.cpython-312.pyc` | by construction, no measurement | 1 |
| `COPY` | `cp/copy.rows` ≡ `keep/orig.rows` | twin **outside** the residue | 1 |
| `CITED` | `cited/named.py`, cited by full path | a full-path citation is a citation | 3 |
| — | `traps/a.err` `UNNAMED`, `traps/graphcmp.py` `UNKNOWN`, `traps/xgraphcmp.py` `CITED` | one sentence, three answers: `.error` ≠ `.err`, `xgraphcmp.py` ≠ `graphcmp.py`, and a TOOL and an OUTPUT in the same directory with the same missing report get different verdicts | — |
| `UNKNOWN`(self) | `self/x.rows` cited by `residue/000-the-residue.md` | an instrument may not measure itself | 3 |
| `UNKNOWN`(witness) | `w/plant.py` `UNKNOWN`, `w/out.rows` `UNNAMED` | extension, not judgement | 2 |
| `UNKNOWN`(untracked) | `u/new-thing.py` | with `u/README.md` committed, so `witness` cannot shadow it | 1 |
| `UNKNOWN`(excluded) | `dd-cone-wt/arm1/dtype.bend`, `strays/artifacts/blob` | excluded rows are COUNTED | 1 |

**MEASURED: `--plant` PASSES and all eight disarms MOVE rows (`authored` 2, `live` 2, `derived` 1,
`copy` 1, `cited` 3, `witness` 2, `excluded` 1, `untracked` 1). Disarming every resolver at once lands
every row on `UNNAMED` — which is the proof that `UNNAMED` is an absence and not a verdict, because it is
what the classifier says when it knows nothing.**

Two harness failures this caught, which is the point of having one:

- **`--disarm untracked` returned rc 3 on the first attempt** — "the plant still passes with a resolver
  off" — because the `witness` resolver answered UNKNOWN for the same row and shadowed the branch. **A
  branch that cannot be made to move is a branch that is not being computed**, and nothing else in this
  directory would have said so. Fixed by giving `u/` a committed report.
- **`--disarm cited` moved 2 rows, not 3**, until belt C was added — the self-citation branch was
  unreachable while belt A was still seeing the staged report.

And the one that fired on the real tree, which is why the `UNKNOWN` verdict exists at all:

- **MEASURED 2026-10-06: `000-the-residue.md` names every residue row by path, so the moment it was
  STAGED — a concurrent unit's bare `git add` did it — the next run found every row cited by this check's
  own report and the residue collapsed from 40 `UNNAMED` to 0.** `EXCLUDED_DIRS` now carries `residue`,
  belt A carries a `:(exclude)` pathspec, belt C fails the run loudly if a citer is inside this check's
  output, and `AUTHORED` has held at 181 on every run since. **That is the fifth time in this project a
  citation index has been built out of the thing it was measuring, and the first time the instrument was
  its own corpus.**