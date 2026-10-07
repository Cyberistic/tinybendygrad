# HOW MANY GATES IN THIS TREE CAN GO RED AT ALL

`coindependent`, 2026-10-07T02:46Z, `git rev-parse --short HEAD` = `2ba824620`. This unit
committed nothing and ran no `git add`; a concurrent `jj`/shared-index process marked some of these
files `A` while this ran (the file-moving hazard `AGENTS.md` warns about), so no staging state is
claimed here. No `bend` was started. Owned and touched only `.agents/slop/coindependent/`
(`checks/`, `gates/`, `AGENTS.md`, `tinybendygrad/` untouched).

**HEADLINE. Over the 73 entry points this unit could present a state for WITHOUT `bend`, they
declare 107 distinct exit codes between them and this unit REACHED 28. 79 declared codes (74%) were
NOT REACHED — and that is not 79 dead verdicts, it is 79 codes NOBODY IN THIS SESSION WATCHED FIRE.
A further 40 entry points were NOT TESTED AT ALL. `AGENTS.md`'s sentence is the reason this is the
most important number in the project: *"A gate that exits 0 having measured nothing is worse than
no gate, because it is trusted."* The measurement below is the first time the denominator has been
written down per gate.**

**AND THE SHARPEST SINGLE NUMBER: of the 73 gates presented, FOUR declare `REFUSED` as their ONLY
exit (`checks/gate.py`, `checks/nl-gate-noguard.py`, `checks/norm_check.py`, `checks/oracle_f64.py`)
and FIVE MORE could be driven only to `REFUSED` at rest because the input they compare against was
swept — so NINE gates cannot reach their green state on this tree today. A gate that cannot go
green has a real surface of ZERO.**

---

## 1. THE INSTRUMENT — what it measures, and what it owns

Landed under `.agents/slop/coindependent/` (the measuring harness):

| file | what |
|---|---|
| `vocab.py` → `vocab.rows` | THE POPULATION, by `os.walk` (never a hand list): every `.py`/`.sh` under `checks/` and `gates/`, with the exit codes and verdict tokens its SOURCE spells. |
| `probe.py` → `probe.rows` | 43 curated EXPERIMENTS (a state + a command), run with no `bend`, recording rc + tokens. A hand list of EXPERIMENTS, not a population — labelled so it cannot be mistaken for one. |
| `twostate.py` → `twostate.rows` | The TWO-STATE discipline: for each gate this unit could move, BOTH the green and the red, with the exact change between them. |
| `surface.py` → `surface.out` | The joined table: per gate `declared / reached / difference`, and the totals. |
| `pairs.py` | The independent-pair sweep (§4). |

`vocab.py` DISCOVERED **113 entry points** (+22 modules with no entry guard); `gates/gates-pop.py`,
the tree's existing gate-population instrument, reports **111** on the same tree — a difference of 2,
because `gates-pop.py` classifies a shell file by a line-anchored `$0`/`exec` union while `vocab.py`
uses the wider `$0` self-reference. **THE TWO NUMBERS ARE THE SAME CLAIM MEASURED TWO WAYS AND THEY
DISAGREE BY 2 — which is itself the finding that two instruments over one population share no
authority (§4).**

**THE DECLARED COLUMN IS NOT AUTHORITATIVE, AND THE REACHED COLUMN PROVES IT IN BOTH DIRECTIONS.**
`checks/nvrows-deadrow-gate.py` spells `2` and `3` yet emitted `0` and `1`; `checks/unowned.py`
spells only `0` yet emitted `1`. So `vocab.py`'s column is a LOWER BOUND in some files (a computed
`return 1` is invisible to a literal scan) and an OVER-credit in others (a `return <int>` in a helper
is credited to the whole file). This is exactly why the deliverable is the REACHED column and not
the declared one: **a declaration cannot audit itself.**

---

## 2. THE TABLE — declared vs reached, per gate (the deliverable)

Totals over the 73 presented gates (the 40 `needs bend` entry points are excluded and named in §3):

```
declared exit-codes      : 107
declared codes REACHED   :  28
declared-but-not-reached :  79   (74% of the declared surface)
gates whose ONLY declared code is REFUSED (cannot go green) : 4
```

The full table is `surface.out`. The gates this unit could actually MOVE, with the states used:

| gate | declared | reached | what reached, and how |
|---|---|---|---|
| `checks/no-txt.py` | 0/1 | **0/1** | `0` at rest; `1` after planting a `.txt` in this unit's own dir; `0` again after removing it |
| `checks/citation-gate.py` | 0/1 | **0/1** | `1` scanning the tree; `0` pointed at a root that does not exist (a VACUOUS green) |
| `checks/residue.py` | 0/3 | **0/3** | `0` `--plant`; `3` `--disarm DELETE` |
| `checks/env-precond.py` | 0/2 | **0/2** | `0` `--plant satisfied`; `2` `--plant nonsense` |
| `checks/unowned.py` | 0 | **0/1** | `0` at rest; `1` `--why /nonexistent` (a code the source does not spell) |
| `checks/wallcheck.py` | 0/2/3/4/5 | **0/4** | `0` `--selftest`; `4` an id that matches no row |
| `checks/nvrows-deadrow-gate.py` | 2/3 | **0/1/2** | four plants; reached `0/1/2`, not the declared `3` |
| `gates/retention-check.py` | 0..5 | **1** | `1` at rest (residue `.tmp.D1-graph-cdiv.txt`) |

Gates this unit presented and could ONLY drive to `REFUSED` at rest (`3`), because the input they
compare against was swept from the tree — **their green and red are UNREACHABLE today**:

```
checks/hermetic-census.py   checks/dup-census.py   checks/dup-gate.py
checks/rn-gate.py           checks/nl-gate.py      checks/nl-gate-noguard.py
```

And gates whose ONLY declared code is `REFUSED` (they have no green to reach by construction):
`checks/gate.py`, `checks/nl-gate-noguard.py`, `checks/norm_check.py`, `checks/oracle_f64.py`.

The `needs bend` gates (`checks/substrate.py`, all 23 `gates/*-gate.py`, `checks/abi*_gate.py`,
`checks/e2e.py`, `checks/sb-gate.sh`, …) each declare `0/1/2/3/4/5` through `gatekit`'s shared
vocabulary — **a 5-verdict surface this unit did not observe ANY of.** Their reached column is the
empty set by refusal, not by evidence.

---

## 3. THE GATES I COULD NOT MAKE RED — BY NAME

**Attempted, and stayed GREEN in every state this unit could present (without `bend`):**

```
gates/gates-pop.py            --plant exits 0; its rc=1 needs a ledger diff or an off-repo root
gates/gendirs.py              --plant exits 0; its red needs a generated dir it does not discover
gates/gatekit.py              --plant exercises REFUSED internally but the process exits 0
gates/wk-f32-gate.py          --plant exits 0 (the 3 output-dir states are internal)
gates/wk-cd-gate.py           --plant exits 0 (same)
checks/txt-owners.py          0 credits, 0 files: green by having nothing to attribute
checks/oracle-txt-census.py   0 at rest; its red needs a `.txt` named by no generator
checks/disagree-gate.py       0 at rest (the gatedelete fix landed)
checks/differ.py              snap/plant exit 0; red needs a full `differ.py run` (bend)
checks/bounded.py             --selftest exits 0; it EXERCISES all five tokens but its own exit is 0
```

**NOT TESTED (40 entry points, all `needs bend`):** named in `surface.py:NEEDS_BEND`. `SKIP`/`DEAD`
are not passes, so these are counted in NEITHER the reached NOR the unreachable total. **The single
most valuable follow-up is to present ONE red state per `gates/*-gate.py` — e.g. a driver with a
type error, which `gatekit._said` already documents as `rc=1`, 0 bytes stdout, `SOME PROOFS FAIL`
on stderr — and watch all five exits fall out.**

**`checks/sweep.py --plan` was a 45 s TIMEOUT (an instrument refusal, not a gate verdict): its red
is unmeasured.**

---

## 4. THE INDEPENDENT PAIRS — two files asserting one fact, where agreement is the PASS condition

The sweep (`pairs.py`) found the class in two shapes. **A PAIR IS A FINDING WHEN THE SAME LITERAL
SET IS SPELLED IN TWO FILES AND ONE IS USED AS AN EXPECTATION — editing one moves only that one, so
one-sided drift is caught, but a SHARED OMISSION is invisible to both.**

| # | pair | shared value | can agreement be falsified? |
|---|---|---|---|
| 1 | `checks/abi_gate.py:457` `JS_ARM_TOKENS` ↔ `checks/abi4_gate.py:189` `OTHER_ABI_TOKENS` | the **same 9 strings**, character-identical | **one-sided edit → caught; a 10th ABI token → INVISIBLE to both.** This is the `names.py`/`ARMED` shape exactly: the fence lists nine tokens and no derivation finds a tenth. |
| 2 | `gates/mixin-op-gate.py:89` `port_only` ↔ `gates/mixin-op-oracle.py:149` `BEND_ONLY` | `rop_gap, exp_cast, commit_weak, bin_promote` | one-sided edit breaks the DERIVED py row count → red; a 5th port-only row both add → agreed, and the addition is invisible. |
| 3 | `gates/i64-shl-gate.py:50,130` ↔ `gates/i64-shl-oracle.py:169` | value vocab `neg1/one/lowhi` + row-name grammar | one-sided edit breaks the row set → red; a 4th value both omit → the claim is narrower than the graph and nothing says so. |
| 4 | `checks/disagree-gate.py:58` `ARMED` ↔ `checks/differ.py:161` `WANT` | `allred, cdiv, late` | one-sided edit caught; `differ`'s own `graphs-unset` DISCOVERY catches a wholly-new graph, so the shared blind spot is only within the three. The `names.py` half of this pair is now DERIVED (§below). |
| 5 | `checks/no-strays.py:127` `SKIP_DIRS` ↔ `checks/unowned.py:42` `SKIP_DIRS` | `{.git,.venv,__pycache__,node_modules,references}` | NOT an expectation whose agreement is pass — but a shared exclusion: a NEW top-level dir is skipped by both. Weaker than 1–4. |

**THE PAIRS THE BRIEF NAMED, RE-MEASURED AND CLOSED:**

- **`names.py`'s `substituted` vs `disagree-gate.py`'s `ARMED`.** The hand list in
  `.agents/slop/disagree/names.py:255-283` is GONE — `dispatcher_substitutions()` now DERIVES the
  set from `GRAPHS` and `rows.pick3`'s own arms, and `disagree-gate.py` reads it through
  `names.py --json`. **The pair is closed by making one file the source and the other a consumer.**
  The remaining literal `ARMED` is a positive claim about three known names, not the population.
- **`checks/oracle-txt-census.py:219` hand `skip`.** GONE — `plant_exclusions()` loads the plant's
  own `excluded()` by path; `grep -n skip` is empty. Closed.
- **`differ.declared()` reads `corpus()`.** That is ONE SOURCE, not a pair: `declared()` is read by
  `checks/no-txt.py`, `corpus-figure.py`, `repro-paths.py`, `sweep.py` and `residue.py` — five
  consumers, one implementation. `run34`'s `175 → 231` was a miscalculation OF that one source, not a
  pair failing to disagree. **This is the FIX shape, and `pairs.py` prints it under `DERIVED`:**

  ```
  checks/no-txt.py, corpus-figure.py, repro-paths.py, sweep.py, residue.py  -> differ.declared()
  gates/gates-pop.py, gates/retention-check.py                             -> gates/gendirs.py
  ```

**A PAIR THAT CAN ONLY AGREE IS A PAIR THAT CANNOT FAIL.** None of the five pairs above is
*structurally* unable to fail — each fails on a one-sided edit — but each contains an unfalsifiable
DIRECTION: the shared omission. The fix shape is the `DERIVED` list: a single declared population
that every consumer asks, so there is no second copy to agree with. **The pair to hunt is not "two
files that disagree"; it is "two files that can only ever agree because neither derives the set."**

---

## 5. THE TWO-STATE DISCIPLINE, MEASURED

`twostate.rows` holds every gate this unit moved, with BOTH states and the exact change:

```
no-txt      at rest 0        -> planted .txt 1   -> removed 0    BOTH SHOWN
wallcheck   --selftest 0     -> bad id 4                          BOTH SHOWN
residue     --plant 0        -> --disarm DELETE 3                 BOTH SHOWN
env-precond --plant satisfied 0 -> --plant nonsense 2             BOTH SHOWN
unowned     at rest 0        -> --why missing 1                   BOTH SHOWN
nvrows      REVIVE 0 / ORPHAN 1 / SELF 1 / STRIP 2                THREE SHOWN
citation    tree 1           -> nonexistent root 0                BOTH SHOWN (the green is vacuous)
gatekit     --plant 0        -> (REFUSED internal, rc never moves) GREEN ONLY
```

**`gatekit.py --plant` demonstrates three output-directory STATES but only ONE exit** — the plant
prints `OUTPUT-CREATED`/`OUTPUT-PRESENT`/`REFUSED, NOT A VERDICT` and returns 0. **A plant that
asserts a refusal without its own process exiting non-zero is a two-state plant measured in ONE
state at the caller's `$?`.** That is the exact defect `AGENTS.md` names, reproduced inside the
instrument that measures it.

---

## 6. THE ONE INSTRUMENT THAT WOULD MAKE THIS A NUMBER EVERY RUN — REPORTED, NOT BUILT

**`gates/gate-surface.py` — a gate over the gates' VERDICT VOCABULARIES.** Not built today: an
instrument that does not exist cannot be wrong, and one that exists badly can.

**Does it extend `gates/gates-pop.py`, or is it new? BOTH, and the distinction matters.**

- It EXTENDS `gates-pop` in exactly the way `gates/gendirs.py` extends it: **the POPULATION is not a
  second list.** `gate-surface.py` loads `gates-pop.discover()` by path (the same one-module,
  N-consumers shape the tree already uses for `gendirs`), so the set of gates has one implementation
  and two consumers, and a drift between the two counts is a bug rather than an opinion.
- It is a NEW INSTRUMENT because it asks a question `gates-pop` deliberately refuses to ask. Clause
  I of `gates-pop` enumerates gates by AST; it says outright it never RUNS one (bend peaks at 1.4 GB).
  Reachability NEEDS execution. So `gate-surface` is opt-in and bounded: it presents each gate ONLY
  the states the gate itself declares (`--plant`, `--help`, a missing input named in its own
  refusal), records rc + token, and prints `declared / reached / difference`.

**The declaration that makes it a GATE and not a report.** Each gate exports
`VERDICTS = (0, 1, 5)` (or a token tuple) and ONE PLANT per verdict. The instrument goes RED when a
declared verdict has no plant, and RED when a plant does not produce its verdict. **A verdict with no
plant is then red by construction — which is the only way to make "this verdict is dead" a number
every run instead of a finding one session wrote down.** `AGENTS.md`'s own example is the spec: the
`censusred` denominator (17 exit paths, 6 ever seen to fire, 10 never) is what this instrument
produces automatically.

**What it must NOT do:** run `bend` unflagged, or reuse a hand list of gates. Both are the two
documented failure modes of this tree (`gates-pop`'s blindness to gates outside the two homes, and
`LIVE_UNITS`' 14 literal names).

---

## 7. WHAT THIS UNIT COULD NOT MEASURE, NAMED

- Every `needs bend` gate (40 entry points): rc and tokens unobserved.
- `checks/sweep.py --plan`: 45 s timeout.
- Whether a `REFUSED`-only gate could reach green with its swept input restored — the input is
  recoverable from git (`371cc64c9^`), and restoring it is another unit's call.
- The tree moved while this ran (parallel units edit `checks/` and the `jj` index); every reading
  above carries the `HEAD` and time in the header. `checks/citation-gate.py` moved from observed
  GREEN to RED between two commands this session, which is why its two states are recorded
  explicitly rather than as a single rc.
