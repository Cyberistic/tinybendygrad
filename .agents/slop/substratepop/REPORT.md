# `checks/substrate.py` — the walk that discovered, and then filtered the discovery away

Unit: `substratepop`. Owner: `checks/substrate.py` only. **`bend` was NOT run** — the `.bend`/`.c`
lanes are read-only here, so every count below is `discover()`/provenance/HALF-2, and `-n` was used
to suppress instrument verdicts. No `.txt`. Artifacts beside this file: `measure.py` (harness),
`measure.out`, `discover.rows`, `counts.rows`, `scratch-strays-n.out`, `live-clean-n.out`,
`live-before-plant-n.out`, `live-with-plant-n.out`, `live-after-plant-n.out`, `live-bend-stray-n.out`,
`onefile-n.out`, `help.out` (all `.out`/`.err` pairs). Scratch tree: `tree/` (12 MB copy, debris).

---

## 1. THE EXACT RULE (`checks/substrate.py`)

`POP_ROOT = "tinybendygrad"` (`:121`) · `POP_SUFFIXES = (".bend", ".c", ".js", ".mjs")` (`:122`).

Before this unit, `discover()` (`:125`) was:

```python
for d, dirs, fs in os.walk(root):
    dirs.sort()
    out += [os.path.join(d, f) for f in sorted(fs) if f.endswith(POP_SUFFIXES)]
```

**There is NO explicit `*.staged-*` exclusion in the code. The answer to the task's question is: a
SUFFIX SET DOING A POPULATION'S JOB.** The pattern `*.staged-*` appears in the file only as a
docstring *assertion* (`:118-120` before the fix): *"The `*.staged-*` scratch copies and `*.mut`
mutants do not end in one of these, so they are excluded by the same rule that includes the real
files."* That sentence is TRUE and is the whole defect: the exclusion is a **consequence** of
`endswith`, never a named branch, never a reason. The prior unit (`strayblobs`) read that prose as
an "explicit exclusion that named the very pattern" — more accurate: **the walk NAMED the pattern it
was blind to and mistook a filter for a decision.** `discover()` decided membership by suffix and
`instrument_for()` (`:361`) is the router that should have decided what to DO with a file.

---

## 2. WHAT THE FILTER COSTS, MEASURED (scratch, four `ops.staged-blob-*` restored from git)

The four historical strays were restored from `07cb5a85a:tinybendygrad/uop/ops.staged-blob-*` into
`.agents/slop/substratepop/tree/tinybendygrad/` — **never the live tree** (`measure.py`).

| tree | `discover()` OLD (suffix) | `discover()` NEW (every file) | delta |
|---|---|---|---|
| live `tinybendygrad/` | 144 | 144 | **0** |
| scratch + 4 restored | 144 | **148** | **+4** |

The four files the OLD rule could not name: `uop/ops.staged-blob-{36145,64022,66397,97648}`
(2×286,404/286,321 B mutants, 2×287,092 B pristine mirrors — 6,297/6,306 lines each).

**THE DECISIVE MEASUREMENT: the live tree holds exactly 144 files and every one is already a router
class** (`bend`×138, `js`×3, `c`×2, `mjs`×1; zero empties, one empty dir `uop/.mutwork`). So the
suffix filter changes *today's denominator by ZERO* — it has no effect until a stray appears, which
is exactly when it hides one. The filter is not load-bearing on the good population and is only
load-bearing on the bad one.

---

## 3. DECISION: (c) — THE SUFFIX SET IS THE FAULT

**(c) chosen. The population is EVERY file under `POP_ROOT`; the lanes decide what to DO with each.**

- **(a) is false.** "The exclusion is right, it merely needs its reason written" would keep a
  discovery-time filter, and a population an instrument *filters* is one it cannot be wrong about.
- **(b) is misdirected.** There is no explicit branch to fix, and making `substrate.py` a residue
  guard duplicates `no-strays.py`'s now-depth-correct `stray_shapes_anywhere()` (`no-strays.py:104`).
  A compilation/name gate should not become a second debris scanner.
- **(c) is the shape the file was already built for.** `instrument_for()` already returns `none`
  for a class it cannot judge (`:367`), and `half1` already prints `NO INSTRUMENT … **NOT JUDGED,
  AND NOT COLD**` and counts it (`:405-407`). The router, not the walk, owns "what to DO". Moving
  the decision off `endswith`-at-discovery and onto the router is a 1-line deletion.

**AND (c) MATCHES THE CONTRACT THE TREE ALREADY HAD.** The frozen shell oracle's HALF 2 name-checks
**every argument** (`oracle-check.sh:368`, `print -l -- "$@"`), and `diff.py:72`'s `pop` set already
hands it `rglob("*")` — every file. `--root` now hands HALF 2 exactly the population the oracle and
the `pop` diff already use, instead of a suffix-filtered subset. **This is why HALF 2 was NOT
scoped to router classes**: doing so would have diverged from the oracle on any non-source input.

The fix (`checks/substrate.py`): `discover()` (`:125-138`) walks every file — `endswith` removed;
`POP_SUFFIXES` kept as the ROUTER's classes (`:122`), not a filter; the module docstring POPULATION
paragraph, the `--root` help, and the `POPULATION` output line all rewritten.

---

## 4. WHAT THE OUTPUT NOW SAYS IT DID NOT LOOK AT

The `run()` disclosure (`:785-794`), printed on every `--root` sweep:

```
POPULATION root=tinybendygrad files=145 by os.walk (EVERY file; router classes .bend .c .js .mjs)
UNJUDGED  1 of 145 discovered file(s) are not a router class: NO INSTRUMENT ran on them
          (HALF 2 still name-checks every discovered file, as the oracle does):
          tinybendygrad/uop/zz.staged-blob-PLANT
```

The `COVERAGE qualified=… checked=… UNSEEN=…` line (`:683`) is HALF **2**'s denominator and is the
wrong shape for a HALF-**1** population question, so `UNJUDGED` is the parallel disclosure: it NAMES
the files the router could not route instead of dropping them. The existing `ROUTE … no-instrument=`
count (`:783`) and the `NO INSTRUMENT <path>` per-file rows (`:407`) already carried the class; the
new line ties it to the population and lists the names.

---

## 5. PLANT IT — TWO STATES (`-n`, no `bend`)

A non-router stray `tinybendygrad/uop/zz.staged-blob-PLANT` **created and then removed on the live
tree** (permitted by the task; a non-`.bend` name so no concurrent unit's `bend` could ever see it):

| state | files | UNJUDGED | PORT ALARM | rc |
|---|---|---|---|---|
| 0 — no plant | 144 | 0 | 1 | 1 |
| 1 — plant present | **145** | **1 (`zz.staged-blob-PLANT`)** | **2** | 1 |
| 2 — plant removed | 144 | 0 | 1 | 1 |

Proven removed: `exists=False`, `git status --porcelain -- <plant>` empty. A `.bend` stray
(`zz-probe.bend`) also goes 144→145 and PORT ALARM 1→2 (it is a router class, so the OLD rule saw it
too — the suffix path was never the only one). **rc stays 1 in every state here only because the
tree is already red at rest on an unrelated untracked probe, `tinybendygrad/test/_probe/v5.bend`**
(1 finding, pre-existing, not this unit's). The *output* changes in the way that matters: the stray
appears as `files 144→145`, is NAMED in `UNJUDGED`, and is counted in `PORT ALARM 1→2`.

---

## 6. `SUBSTRATE CLEAN` — MEANING, rc, TOKEN, BEFORE vs AFTER

Token names unchanged: clean prints `SUBSTRATE CLEAN`, red prints `SUBSTRATE NOT CLEAN`, misuse
`REFUSED`. rc: `0` clean · `1` ≥1 finding · `3` refused/drift.

- **BEFORE.** `SUBSTRATE CLEAN: N file(s) …` where **N was the suffix-filtered count**, and
  `provenance()` (`:472`) received only those files. A non-source file inside `tinybendygrad/` was
  invisible to the walk and therefore invisible to the PORT ALARM: untracked and present, it did
  **not** alarm. The gate could print CLEAN (`rc=0`) over a population it had filtered.
- **AFTER.** N is **every discovered file**. A non-source file is printed `NO INSTRUMENT` (HALF 1),
  name-checked (HALF 2), named in `UNJUDGED`, and — **if untracked inside `tinybendygrad/` — it
  joins the NOT-PORT rows and fires the PORT ALARM, which IS a finding.** So on an otherwise-clean
  tree, an untracked non-source stray flips the verdict **rc 0 → 1**. On this tree the flip is
  masked by the pre-existing probe (1→2, rc already 1), which is why §5 states it as a count, not a
  bare rc.

**VERDICT CHANGE, STATED: yes, and it is a strengthening at the DISCLOSURE and at the PORT ALARM.**
A *tracked* non-source file (the scratch case, rc=0) is an **unmeasured surface** (`NO INSTRUMENT`),
not a finding — a file `substrate.py` cannot judge is not a file `substrate.py` should fail;
residue is `no-strays.py`'s job. What changed is that the sweep no longer hides the file, and the
untracked case now alarms. No change to explicit-file callers: `-n tinybendygrad/base.bend` is
byte-identical (rc=0), because the `POPULATION`/`UNJUDGED` lines are gated on `origin is not None`
(a `--root` sweep only), so the frozen-oracle diff over explicit file args is unaffected — and the
`pop` set already used the full-`rglob` population, so the port now *agrees* with the oracle where
it previously filtered.
