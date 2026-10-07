# SUBTREE — `discover()` IS ONE RECURSION FLAG SHORT OF THE POPULATION, AND ITS OWN DOCSTRING MAKES A SECOND FALSE CLAIM

**READING: HEAD `240469d4c`, 2026-10-07T16:48:12, `.venv/bin/python` 3.12.10.**
Every number below is from `.agents/slop/subtree/final.rows`, written by one run at that stamp.
The tree is being written live (`AGENTS.md` records it, and `gates/gate-surface.py` moved 52 lines
between two of my reads), so a number is a reading **with its time**, not a fact.
Re-read with `.venv/bin/python .agents/slop/subtree/final.py`.

**VERDICT: not a false number. A SILENT one — and the silence is REPORTED BY ONE CONSUMER OUT OF
NINE, AND BY THE OWNER OF THE POPULATION AT NO.**

---

## 0. WHAT CANNOT BE SEEN, FIRST

| | |
|---|---|
| The population's **name** | `discover()` — unqualified. No `top`, no `shallow`, no `flat`. A name is a claim about scope, and this one claims *all of it*. |
| The population's **docstring** (`:325`) | *"`(entries, libs)`, by walking the two homes."* — then, honestly, *"`iterdir()` and not `rglob()`."* |
| **Is that honest?** | **The docstring is honest and the NAME IS NOT.** `discover()` states its own limitation in the same breath as its function, and a reader who opens the file learns the ceiling. A reader who reads the *name* — from `gate-surface.py:158`, from `hooks/run.py:130`, from every call site — learns nothing. **The gap is DOCUMENTED IN THE OWNER AND UNDOCUMENTED IN EVERY PLACE THE OWNER IS NAMED.** That is the shape of the defect, and it is why the brief's framing is right: this is a name that outruns its own docstring. |

`pairs` measured the whole-tree census at 111 where the gates-only one is 5 and said *"BOTH ARE
CORRECT FOR THEIR SCOPE AND THE NUMBER IS MEANINGLESS WITHOUT IT."* `discover()` is the gates-only
one, and its scope is `HOMES × {top level}` — **two axes, and only the first is in the name.**

### THE SECOND FALSE CLAIM, IN THE SAME DOCSTRING, AND IT IS WORSE

`:327-330` claims:

> *"`os.lstat` and not `Path.exists()`, because `Path.exists()` FOLLOWS SYMLINKS … an existence
> test that follows it would certify a link target as a tree file."*

**The code calls neither. `:338` is `not p.is_file()`.** `os.lstat` appears **nowhere in the file's
code** — only in the docstring's prose (`census3.rows` / `census2.rows`).

MEASURED on a scratch tree, over all three link shapes (`census3.rows`, `SHAPE`):

| shape | `exists()` | `is_file()` | `os.lstat()` | `os.path.lexists()` |
|---|---|---|---|---|
| `plain.py` | True | True | 33188 | True |
| `good-link.py` (live target) | True | True | 41453 | True |
| `dead-link.py` (**dangling**) | **False** | **False** | 41453 | **True** |

`exists()` and `is_file()` **agree on every shape**. They diverge from `lstat`/`lexists` on exactly
the one shape the docstring's own reasoning is about — a link whose target is a *worktree*. So the
docstring names the one predicate that would have caught its own hazard, and calls neither it nor
its stated alternative.

**PLANTED, BOTH DIRECTIONS** (`census3.rows`, `PLANT_DANGLE`, on a scratch gate home with the real
`discover()` loaded by path):

- **CERTIFIED — the hazard the docstring says it prevents, happening.** A `.sh` symlink whose target
  is a real file **outside** the home: `link_to_real_file_seen=True`. `is_file()` follows the link,
  so a link target is counted as a tree file. *The exact outcome `:327-330` says cannot happen.*
- **INVISIBLE — the hazard `lstat` would have caught.** A **dangling** `.sh` gate symlink:
  `discover()` reports `entries=1`, `discover_sees_dead_gate=False`. `os.lstat` succeeds on it.

**So the docstring is not merely mis-describing the code — the code is wrong in BOTH directions, and
one of the two is the failure the docstring was written to prevent.** This is a false claim in the
owner, which the brief said would be worse than the gap. It is worse.

**ONE-LINE FIX, IF IT IS FIXED:** `:338` becomes `or not os.lstat(p)` (plus `stat.S_ISREG` for
directories), which makes the code match its own stated reason. **NOT DONE — it is a gate body, and
this unit does not touch gate bodies.**

---

## 1. CONFIRMED: `discover()` IS `iterdir()`-BASED AND NON-RECURSIVE

`gates/gates-pop.py:324-342`. Walk at **`:337`**, `for p in sorted(h.iterdir()):`.

```
324 def discover(root):
337     for p in sorted(h.iterdir()):
338         if p.suffix not in SUFFIXES or not p.is_file():
339             continue
```

`HOMES = ("checks", "gates")` at `:102`; `SUFFIXES = (".py", ".sh")` at `:140`.

**DOES THE DOCSTRING CLAIM RECURSION? NO — it claims the opposite, in the same sentence as the walk**
(`doc_claims_recursion=False`, `doc_negates_recursion=True`). **There is no false recursion claim
here.** The depth gap is *stated*. The `os.lstat` claim at `:327` is the false one.

### THE MECHANISM IS NOT "BLIND TO THE DIRECTORY" — IT IS "DISCARDS IT AFTER VISITING"

`gates/oracles` **IS RETURNED by `iterdir()`**. It is dropped at `:338` because a directory's
`Path.suffix` is `''`, which is not in `SUFFIXES` (`census6.rows`, `MECH`):

```
checks/__pycache__   is_dir=True suffix='' in_SUFFIXES=False files_inside=54
checks/gen           is_dir=True suffix='' in_SUFFIXES=False files_inside=2
gates/__pycache__    is_dir=True suffix='' in_SUFFIXES=False files_inside=24
gates/artifacts      is_dir=True suffix='' in_SUFFIXES=False files_inside=0
gates/oracles        is_dir=True suffix='' in_SUFFIXES=False files_inside=2
```

The walk **visited `gates/oracles` and threw it away on a shape the caller never sees.** That is why
the gap is invisible rather than loud: no directory is ever reported as skipped, and the drop looks
identical to a walk that never went there. **A silently-discarded directory and an unvisited one are
the same observation, and only the second is knowable.**

---

## 2. THE GAP'S CONSEQUENCE, MEASURED ON THE WHOLE SET

| | |
|---|---|
| `discover()` entries | **123** |
| `discover()` libs | **30** |
| `discover()` **total** | **153** |
| recursive `os.walk` (same `HOMES`, same `SUFFIXES`, minus `__pycache__`) | **155** |
| **`\|only-discover\|`** | **0** |
| **`\|only-walk\|`** | **2** |

**The two, and nothing else:**

| path | `entry_reason()` | class | tracked |
|---|---|---|---|
| `gates/oracles/beautiful-mnist-oracle.sh` | **`sh-selfref`** | **ENTRY** | yes (`git ls-tree`, HEAD `240469d4c`) |
| `gates/oracles/mixin-op-oracle.sh` | **`sh-selfref`** | **ENTRY** | yes |

`checks/` contributes **0**. `gates/` contributes both. The whole set is 2 files — **the brief's
`gates/oracles/*.sh` is the complete answer, not an example.**

### WOULD A RECURSIVE WALK FIND THEM? YES — AND `entry_reason()` ALREADY CALLS THEM ENTRIES

Both are `sh-selfref`, which `:340` puts in the **entries** bucket. The brief's inference holds and
is now measured rather than assumed: **these are gates, not fixtures.** Their heads say so — each
opens `#!/bin/sh`, names three lanes (`py` / `bend` / `bn`), and *every step is `set -e`*:

```
gates/oracles/beautiful-mnist-oracle.sh   3984 bytes
  2  # beautiful-mnist-gate.sh -- run BOTH lanes ... and diff them
  3  # against the CPython oracle. Every step is `set -e`, so the script fails loudly.
gates/oracles/mixin-op-oracle.sh           1451 bytes
  2  # mixin-op-gate.sh -- run BOTH lanes of tinybendygrad/mixin/op.bend and diff them against
  3  # the CPython oracle. Every step is `set -e`, so the script fails loudly.
```

And they are **consumed**: `gates/mixin-op-gate.py:27` and `:69` name
`gates/oracles/mixin-op-oracle.sh` in its own source.

**SO: `gate-surface.py`, WHICH CALLS `discover()`, CANNOT GIVE EITHER OF THE TREE'S OWN GATES A CENSUS
ROW.** Measured directly (`census4.rows`, `SURFACE_POP`): `entry_points_with_no_census_row_for_deeper_files = [both]`.
`report()` iterates `for p in entries` (`:354`), so a file `discover()` did not return **cannot
appear, cannot be classified, cannot be counted**. Its census denominator is `discover()`'s
denominator — which `gate-surface.py:643` states out loud: *"DENOMINATOR: every entry point
`gates-pop.discover()` finds. A verdict with no …"*. **A denominator that is defined by the walk it
audits is not a denominator; it is a restatement.**

---

## 3. RECURSE, OR GIVE IT A SECOND NAME?

### RECOMMENDATION: **MAKE IT RECURSIVE** — and it is cheaper than the alternative by an order of magnitude.

| | RECURSIVE | SECOND NAME |
|---|---|---|
| Files that change | **1** (`gates/gates-pop.py`) | **1 owner + every consumer that wants the deep set** |
| Populations in the tree | **1** | **2** — the fault `gendirs.py` exists to prevent |
| Ledger rows | 123 → **125** | 123 (unchanged) + a second ledger |
| `\|only-discover\|` | stays **0** | stays 0 for the shallow set; the deep set is unverified |
| Consumers that change number | **1 of 9** (`gate-surface`, +2) | **0** — and that is the *defect* |

**BLAST RADIUS, MEASURED** (`final.rows`, `BLAST` / `FINAL`): entries **123 → 125**, libs
**30 → 30**, total **153 → 155**, delta **+2**, **`lost_by_recursion = 0`**. Nothing is lost: the
recursive set is a **strict superset**, measured on the live tree and again in the clone.

**DOES ANY CONSUMER'S NUMBER CHANGE? ONE.**
- `gates/gate-surface.py`: `discover()` census 153 → **155**, and the `WALK-ONLY` block at `:344`
  goes from 2 lines to **0**. That is the gate reaching **completeness**, and it is the correct
  direction.
- `gates/gates-pop.ledger.tsv`: 123 → **125** rows. `--ledger check` reports **2 NEW** and returns
  **1** — a **RED that is the gate working**, not a regression. One `--ledger write` re-baselines it.
- The other **8** consumers print no population total, so **no number of theirs moves**.

**`onemodule` measured 113 → 114 → 115 WHILE WORKING. That drift is the argument, not an aside: a
number that moves when the population widens was measuring the *tree at that minute*, not the
population. Recursion replaces a moving number with a stable one.** The 153 is not the population;
it is the top level of it.

**WHY NOT A SECOND NAME.** A second name is a second population, and the tree already carries the
injury: `HOMES` is a hand list and is admitted as one at `:97-101`; the module's own header (`:92-95`)
concedes *"IT IS BLIND TO THE 'LITERAL LIST INSTEAD OF A POPULATION' HALF — AND IT IS THE BLIND ONE,
BECAUSE A POPULATION GATE IS ITSELF A POPULATION GATE."* Adding `discover_deep()` beside `discover()`
re-creates the exact fault in the file whose subject is not re-creating it. **The two sets would
differ by one recursion flag and both would be named `discover` — and no ledger diffs between two
functions in one file.**

**THE ONE ARGUMENT FOR THE SECOND NAME, STATED HONESTLY:** recursion widens `gate-surface`'s census
denominator from 153 to 155, and both new rows are `.sh` files with **no `VERDICTS`/`PLANTS`/`RED_IS`
module body** (that clause is `.py`-only, `:352-353`). So they would appear as census rows with
**nothing to audit** — `verdicts is None → continue` (`:359-360`). They would be counted and not
checked: **a wider denominator with the same numerator discipline.** That is a real cost, it is
*smaller* than a second population, and it is what the `WALK-ONLY` block at `:337-344` was already
printing by name. **Recursion, plus the 2 new rows showing as `NO DECLARATION` rather than
silently vanishing, is strictly better than a name that hides them.**

---

## 4. PLANTED, BOTH DEPTHS, IN A SCRATCH CLONE

`.agents/slop/subtree/plant.py` — `git init` + `copytree(symlinks=True)` of the two `HOMES` and
`pyproject.toml` into a temp dir **outside** the repo. **Not `git clone`**: this `.git` is **246 MB**
(measured) and cloning it cost >5 min for a measurement needing two directories.
**rc=0, `OVERALL = ALL ASSERTIONS HELD`, `FAILURES = none`.** Full rows: `plant.rows`.

**`zerogate` found two of its own plants proved nothing, and `prune4` found a clause vacuously true
for 3 974 files. So each assertion below carries the control that makes it non-vacuous.**

| step | `discover()` entries | `os.walk` total | Δ entry | Δ walk | verdict |
|---|---|---|---|---|---|
| BASE | 123 | 155 | — | — | `only_walk=2`, `only_discover=0` |
| empty-root control | **0** | — | — | — | **the walk CAN return 0, so a later 0 is a measurement** |
| **PLANT depth 0** `checks/zzz-plant-top.sh` | **124** | **156** | **+1** | **+1** | **MOVES — not a no-op** |
| **PLANT depth 1** `gates/oracles/zzz-plant-deep.sh` | **123** | **156** | **+0** | **+1** | **MOVES — the split, reproduced** |
| control `.txt` at depth 1 | 123 | 156 | +0 | +0 | **VACUITY EXCLUDED** |
| RESTORE | 123 | 155 | 0 | 0 | **`byte_identical = True`** |

**THE WHOLE TASK IS THE DEPTH-1 ROW.** The planted file exists, is 1 451 bytes of real shell, and
`entry_reason()` returns **`sh-selfref`** → `is_entry=True`. The recursive projection **moved +1**;
the shared projection **moved +0**. `DEEP_in_only_walk = True`, `DEEP_only_walk_now` 2 → **3**.

**IT IS NOT A NO-OP, AND THAT IS PROVEN TWICE:**
1. **Depth 0 is the positive control.** `checks/zzz-plant-top.sh` moves **both** projections +1 and
   appears **by name** in `discover()`'s entries. A predicate that fires at depth 0 and not at
   depth 1 is measuring **depth**, not "does a gate exist".
2. **The `.txt` control is the vacuity guard.** `gates/oracles/zzz-notagate.txt` at the same depth
   moves **neither** projection. `prune4`'s failure was a clause true for 3 974 files; this clause
   is **false for every file that is not a gate**, so the +1 above is attributable to the gate.
   (Had it moved a count, `SUFFIXES` would be leaking — the run records `SUFFIX LEAK` and rc=1.)

**RESTORE IS BYTE-IDENTICAL, NOT BY INSPECTION:**
`BASE_sha256 = e25706d24cc1c44b415b7a8b95b3134f35f0b2a3680fd8cec474e10ee550e154` over **366 files**
(path + bytes, sorted, `.git`/`__pycache__` excluded) == `RESTORE_sha256`, and the counts match.
The live tree is **structurally** untouched: both plant paths live under `/var/folders/…/clone/`,
and `(ROOT / rel).exists()` is False for both.

---

## 5. IS IT A FALSE NUMBER, OR AN INCOMPLETE ONE? — **INCOMPLETE. SILENCE, NOT WRONGNESS.**

`|only-discover| = 0` in **both** comparisons (live tree and clone), independently reproduced.
**`discover()` is a strict SUBSET of the recursive walks. It can be SILENT about a file and never
WRONG about one.** Its numbers are *true*; they are *smaller than the question*. That is the better
property and it should not be traded away — a wrong number is worse than a small one, because a
wrong one cannot be reasoned about.

### IS THE SILENCE REPORTED? **BY ONE CONSUMER OF NINE. AND NOT BY THE OWNER.**

| consumer | prints the ceiling? |
|---|---|
| **`gates/gates-pop.py` — THE OWNER** | **NO** |
| `gates/gate-surface.py` | **YES** — `:337-344` |
| `.agents/slop/hooks/run.py` | NO |
| `.agents/slop/plantthe46/reach.py` | NO |
| 4 others under `.agents/slop/` | mixed |

`gates/gate-surface.py:337-344` is exactly the right shape and **already exists**:

```python
only_walk = sorted(control - disc)
print(f"I  POPULATION CONTROL: `discover()` sees {len(disc)} file(s) "
      f"({len(entries)} entries + {len(libs)} libs) vs\n   recursive `os.walk` {len(control)} "
      f"... {len(only_walk)} file(s) the\n   recursive "
      f"walk sees and `discover()` does not:")
for rel in only_walk:
    print(f"I    WALK-ONLY {rel}")
```

**SO: A KNOWN CEILING EXISTS IN THIS TREE. IT IS IN THE WRONG FILE.** `gate-surface.py` is a
*consumer* of `discover()`. The ceiling belongs to `discover()` — the thing with the gap — and
`gates-pop.py:577` prints `DISCOVERED 153 entry point(s) under checks/ gates/` with **no second
number, no `only_walk`, no `os.walk` anywhere in the file** (`os.walk_in_source=False`).

> **A KNOWN CEILING IS NOT THE SAME AS AN UNKNOWN ONE. `gate-surface.py` is the instrument that
> CAN BE SILENT BUT PRINTS ITS OWN SILENCE; `gates-pop.py` is the instrument that IS INCOMPLETE AND
> UNDOCUMENTED. The second is worse, and it is the OWNER.**

**THE FIX THAT FITS THE TREE'S OWN DOCTRINE IS THE SMALLEST ONE: move `walk_control()` and the
`only_walk` print from `gate-surface.py` INTO `gates-pop.py:report()`, beside `:577`, and have
`gate-surface.py` print the owner's line instead of recomputing it.** That makes **one** population
with **one** declared ceiling, keeps the two-instruments-holding-two-lists argument `gate-surface.py`
spent a paragraph defending (`:163-168` — it calls itself "the SECOND one **deliberately**, so the
difference is visible"), and adds **zero** populations. **NOT DONE — a gate body, and this unit does
not touch gate bodies.**

---

## 6. WHAT THIS UNIT DID NOT TOUCH

`gates/gates-pop.py` (both fixes above), `gates/gate-surface.py`, `AGENTS.md`, `tinybendygrad/`,
the ledger, the index. **`git add` was never run. `git status --porcelain -- checks gates` shows only
another unit's in-flight work** (`MM checks/abi_gate.py`, `DA checks/coindep.py`, …). All new files
are under `.agents/slop/subtree/`. No `bend` was run; no gate was executed; every number came from
reading `gates-pop.py`'s pure walk.

## 7. INSTRUMENTS (all re-runnable, all `.rows`)

| file | what it settles |
|---|---|
| `measure.py` | `discover()` is `iterdir()`-based; the walk site; the `only_walk=2` set |
| `measure2.py` | the `os.lstat` claim vs `is_file()`; consumers; `git ls-tree` tracking |
| `measure3.py` | the symlink table, the dangling-gate plant, blast radius |
| `measure4.py` | who references the two deeper gates; what each census reports |
| `measure5.py` | re-measured line numbers + HEAD stamp; the deeper gates' own inputs |
| `measure6.py` | the **mechanism** (`iterdir()` returns the directory, `:338` discards it) |
| `plant.py` | **both depths planted, with controls; rc=0** |
| `final.py` | the one timestamped reading every number above is quoted from |

## 8. THE THREE FINDINGS, RANKED

1. **`gates/gates-pop.py:327-330` claims `os.lstat`; `:338` calls `is_file()`.** The code is wrong in
   **both** directions — it certifies a link target outside the home (the hazard the docstring says
   it prevents) and hides a dangling gate (the hazard `lstat` would catch). **A false claim in the
   owner, and it is the more serious of the two.**
2. **`gates/gates-pop.py:577` reports 153 with no ceiling**, while `gates/gate-surface.py:337-344`
   already computes and prints exactly that ceiling. **The known ceiling exists and is in the wrong
   file.** The gap costs 2 of 155 gates — *visible*; the undocumented `discover()` inside the owner
   costs nothing today and would cost the ceiling the moment a third home appears.
3. **The depth gap itself is small, honest, and cheap to close**: 2 files, strict superset, `0`
   lost, **1 consumer's number moves**, and the ledger goes red **once** as designed.