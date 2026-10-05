# MMFOLD — the 93 one-space rows, and the gate that could not see them

Unit: make `uop/fold.bend`'s 93 ungated one-space rows gateable, and stop a dead gate from
reporting zero. **Nothing committed.** Nothing outside `.agents/slop/` was edited.

Measured on this tree, 2026-10-04, `bend 2.0.34` (`--help` reports 2.0.34; 2.0.35 is available
and not installed), `tinybendygrad/uop/fold.bend` sha256 `e8c7bdc8c27e227…`, its stdout sha256
`232be7fe302e80b9…`.

---

## 1. THE URGENT ONE: `mm-lift-gate.py` WAS DEAD, AND NOW SAYS SO

Reproduced exactly as briefed, from the repo root:

| launcher | before this unit | after |
|---|---|---|
| `python3 .agents/slop/mm-lift-gate.py` | **rc=1, STDOUT 0 lines**, `ModuleNotFoundError` | rc=0, STDOUT **132** lines |
| `.venv/bin/python .agents/slop/mm-lift-gate.py` | rc=0, STDOUT 131 lines | rc=0, STDOUT **132** lines |

Both launchers now produce **byte-identical** stdout (sha256[:16] `05a529c728405c01` under each).
PATH's `python3` is 3.14 with no `.pth`; the editable tinygrad install exists only in `.venv`
(3.12), so `from tinygrad import dtypes` used to raise.

**What it actually produces once it can reach CPython — 132 lines:**

- **127 `lf_` rows** (`lift-mut-table.txt` and `fold.bend:4092+`'s `lf_row` family). All 127
  **agree with `fold.bend`** — `diff` over whole `name=value` lines is 0 differing lines.
- **4 `satcp_` lines**: CPython's unbounded integers for the four saturation rows the port
  saturates on. Diagnostics, not compared.
- **1 `DUPLICATE` line** — new, see §4.

### `DIED` is now distinct from `COMPARED ZERO`

`mm-lift-gate.py --selfcheck` drives **both** refusals `oracle_py.resolve()` can make, in a
throwaway tree under `$TMPDIR` (never the live one), and prints `DIED` on **STDOUT** and exits
**2**:

```
selftest no .venv (resolve: PYTHON MISSING)
  rc=2 (want 2)  stdout DIED lines=1 (want 1)  PASS
  DIED mm-lift-gate oracle_py refused to name an interpreter: ORACLE PYTHON MISSING: …
selftest a .venv whose python cannot import tinygrad (resolve: CANNOT IMPORT)
  rc=2 (want 2)  stdout DIED lines=1 (want 1)  PASS
  DIED mm-lift-gate oracle_py refused to name an interpreter: ORACLE PYTHON CANNOT IMPORT tinygrad: …
selftest: PASS
```

Two refusals, not one, because a control that can only produce one answer is not a control.
Exit **2**, not 1, because `oracle_py.refuse()` already reserves 1 for "the run happened and found
a broken port". The `DIED` line carries `resolve()`'s own diagnosis so a reader of stdout alone
can tell the two apart.

The **disarm**: under `.venv/bin/python` the same file prints 132 lines and **0** `DIED` lines.
A `DIED` that is always printed is not a signal.

**The mechanism is the project's own.** `oracle_py.resolve()` names the interpreter and this
file `os.execv`s into it, which is what makes the verdict a function of the port rather than of
the launcher. It also refuses an interpreter whose tinygrad resolves outside this tree, which is
the L-11 trap: a `.venv` copied out of the repo still carries
`MAPPING = {'tinygrad': '/abs/path/to/the/original/tinygrad'}` in
`__editable___tinygrad_0_14_0_finder.py`.

### THE BRIEF'S READING OF THE 0 WAS WRONG, AND THE CORRECTION MATTERS

> *"the project has been reading that 0 as '93 measurements have no CPython answer'."*

That reading is a **category error**, and here is the measurement:

- `mm-lift-gate.py` gates the **`lf_` family only**. It emits **no `mm_*` and no `bl_*` row, ever**
  — it could not have answered for the 93 whether it ran or died.
- The oracles for the 93 have existed since 2026-10-02 and are **pure CPython with no
  tinygrad import**: `.agents/slop/mm-gate.py` (72 `mm_*` rows) and `.agents/slop/mm-bl-gate.py`
  (38 `bl_*` rows). Neither can die of `ModuleNotFoundError`.
- `.agents/slop/LANE-LIVENESS.md:190` and `:281`, and `.agents/slop/revive/REVIVE.md:222`, already
  record these two as **"NO automated driver exists"** / "Six emitters have no driver at all".

So the 0 did not mean "no CPython answer". It meant **"no lane had ever compared them"** — and the
`mm_*`/`bl_*` rows are missing from **a lane that was never whole**, not from a lane that was
otherwise green. The `lf_` lane was green over those 127 rows the whole time the gate was dead.

---

## 2. THE 93, GATED

```
$ .venv/bin/python .agents/slop/mmfold/mmfold-lane.py
oracle mm-gate.py: 72 rows, 0 unread by either reader, 0 name(s) printed twice
oracle mm-bl-gate.py: 38 rows, 0 unread by either reader, 0 name(s) printed twice

port  …/tinybendygrad/uop/fold.bend
  334 lines -> 333 rows by rows()+rows_f3one(), 0 unread, 1 name(s) printed twice
  of those rows: rows() read 240 and rows_f3one() read 93
  ONE-SPACE F3 POPULATION (what the 93 were): 93 rows, of which 0 are outside these two oracles
SCOPE: 110 oracle rows ({'mm': 72, 'bl': 38})
COMPARED 110   DISAGREEMENTS 0   MISSING FROM PORT 0   port rows out of scope 223

VERDICT GREEN -- the 110 rows these two oracles measure
LANE INTEGRITY 1 name(s) printed twice (fold.bend, NOT this lane's scope: see mm-lift-gate.py's
  DUPLICATE line) -- all 334 lines of the port lane
```

### THE DENOMINATOR, BEFORE AND AFTER

| | before | after |
|---|---|---|
| lines `fold.bend` prints | 334 | 334 |
| read by `rebase-gate.py`'s `rows()` alone | **240** | 240 |
| **ungated** (no lane compared them against CPython) | **110** | **0** |
| — of which the **93** unreadable by the shared reader | 93 | 0 |
| — of which 17 `mm_div_*`, already F1-readable but equally unwired | 17 | 0 |
| rows with a CPython answer **available** | 110 | 110 |
| rows with a CPython answer **actually compared** | **0** | **110** |
| disagreements | — | **0** |

**The 93 was never 110 and the honest before-number is 110, not 93.** `mm-gate.py`'s `DIV` family
prints `mm_div_17_5 q=0:3 r=0:2`, which contains `=` and is therefore F1 — `rows()` reads those
17 today. They were still ungated, because nothing ran the oracle against them. The brief's "93"
counts only what the shared reader could not read; the population with no lane was 110.

**Per-family, all measured on this tree** (the brief's family list is stale for `mm_*`: 55 → 72,
because `fold.bend` has grown since):

| family | rows | read by `rows()`? | compared now |
|---|---|---|---|
| `mm_add_*` | 8 | no (one space) | 8 |
| `mm_sub_*` | 7 | no | 7 |
| `mm_mul_*` | 14 | no | 14 |
| `mm_shl_*` | 17 | no | 17 |
| `mm_shr_*` | 9 | no | 9 |
| `bl_bl_*` | 26 | no | 26 |
| `bl_mk_*` | 12 | no | 12 |
| **one-space subtotal** | **93** | | **93** |
| `mm_div_*` | 17 | **yes** (F1, `q=`/`r=`) | 17 |

### A LANE THIS PROJECT ALREADY SAID COULD NOT BE MADE LIVE — REFUTED

`.agents/slop/LANE-LIVENESS.md:190` lists `mm-gate.py` and `mm-bl-gate.py` as
**`NOT A GATE · CANNOT-BE-MADE-LIVE`**, and `:281` names the obstacle as *"no driver exists at all
— the docstrings are a manual `diff` recipe and there is no `mm-*-gate.sh`"*, with the shortest
honest path *"one `sh` driver each"*.

**`.agents/slop/mmfold/mmfold-lane.py` is that driver and it runs: 110 compared, 0 disagreements.**
The obstacle was real when written and is now gone; per `agent-core.md` I am reporting the
contradiction rather than reconciling it, and `LANE-LIVENESS.md` is not mine to edit.

The two other entries on that line are **not** mine and are **still walls**:
`mm-dt-gate.py` (the 24 `bl_dt_*` F1 rows, out of this lane's scope) and `mm-walk-gate.py`.

---

## 3. THE CONTRACT: `.agents/slop/mmfold/mmfold-rows.py::rows_f3one`

One appended row in `.agents/slop/reader-contracts.tsv` (58 rows, was 57). **Signature
`7c471b64d6f5`, computed by calling `reader-fork-census.py`'s `behavior_fingerprint`, not
written by hand.**

### `GAP` WAS NOT TOUCHED

`rebase-gate.py:412` is read-only to this unit and its `GAP = "  "` is unchanged. It is right: a
TAB is a table cell, so `oracle/dtype_tables.py` must keep reading as zero rows. Measured today:
that oracle emits **14,766** non-empty TAB lines (the 14,774 in the brief and in
`rebase-gate.py:415` was an earlier tree), and **`rows_f3one` reads 0 of them.** The lane wired on
purpose to be dead stays dead, measured rather than asserted.

### THE CONFORMING CENSUS BEHAVIOUR, ALL SIX SHAPES

| shape | text | `rows()` | `rows_f3one` |
|---|---|---|---|
| F1 `name=value` | `ctl OPENCL sz1 k0=half` | 1 | **0** |
| F2 `name = [v] py=[w]` | `ctl OPENCL sz1 k0 = [half]   py=[half]` | 1 | **0** |
| F3 two-space | `ctlf3  half` | 1 | **0** |
| F4 `name` contains `=` | `na=me=value` | 1 | **0** |
| F5 **single-space gap** | `ctl single half` | 0 | **1** |
| F6 TAB gap | `ctl\ttab\thalf` | 0 | **0** |

The two readers are **complementary**, and the lane **asserts** their key sets are disjoint rather
than assuming it — two readers both claiming a name is two answers to what a line means.

### WHO MAY USE IT, AND WHAT SUBSTITUTING IT BREAKS

- **May be used by** `.agents/slop/mmfold/mmfold-lane.py`, and by nothing else, **only unioned
  with `rows()`**.
- **Substituting it for `rows()`** turns cstyle.bend's 225 F2 rows into 225 BROKEN — the same
  227-BROKEN outcome `cstyle-gate.py`'s `rows_strict` is forbidden for, reached from the opposite
  direction.
- **Substituting `rows()` for it** re-breaks the 93: 93 printed rows read as none. That is the
  defect the row closes.
- It reads a name only when it is ONE token with no `=`, no TAB and no double space, and it
  **refuses to collapse a repeated name silently**.

### THE GUARD, BEFORE AND AFTER

```
python3 .agents/slop/reader-guard.py
  before:  358 candidates, 39 answer a row question, 57 registry rows, rc=1, 1 finding
  after:   359 candidates, 40 answer a row question, 58 registry rows, rc=1, 1 finding
  finding: .agents/slop/dsl_gate.py:87 unstable_rows  — IDENTICAL, PRE-EXISTING, NOT MINE
  mentions of mmfold in the output: 0
python3 .agents/slop/reader-guard.py --self-test   → SELF-TEST OK (8/8)
```

The delta is **+1 candidate, +1 answering a row question, +1 registry row, and zero new findings**,
so R1 passes and R2 is armed against this file. `--self-test` reports `OK  R2 armed (real file
matches its signature)`, which is what makes the signature evidence rather than a decoration.

While the guard was running, `rebase-gate.py`'s own md5 changed
(`5dac37bd7…` → `51442159c…`) — another unit is editing it — but `rows()` and `row()`'s
behavioural fingerprints are **unchanged** (`053856678061`, `5426c8bb9af7`), so the reader's
meaning did not move and no contract I depend on is stale.

---

## 4. A REAL DEFECT FOUND, IN A FILE I MUST NOT EDIT

`fold.bend` prints **334 lines carrying 333 distinct names.** `mmfold-lane.py` reports
`1 name(s) printed twice` beside every row count, and the name is **`lf_sub_int32_-3_4`**:

- `.agents/slop/mm-lift-gate.py:31` — `SUB`'s pair list carries `(-3, 4)` **twice** (positions 1
  and 4), so 8 `sub` fixtures produce **7** distinct `sub_int32_*` names.
- `.agents/slop/uop/fold.bend:5862` **and** `.agents/slop/uop/fold.bend:5865` — the same
  `lf_row("sub_int32_-3_4", …)` twice, because the port's rows are generated from that fixture list.

`.agents/TODO.md:278` already records the `mm-lift-gate.py:31` duplication as REPORTED. What was
not recorded is **why nothing caught it**: a `diff` of the two lanes is **GREEN** over it (both
sides carry the duplicate, so the line multisets match) and so is any comparison keyed on NAME
(the dict keeps the last and the first is gone with nothing saying so). Only
**lines-claimed vs distinct-names** sees it.

**Fixed on my side of the line, loudly rather than by deletion:**

- `mm-lift-gate.py` now prints `DUPLICATE lf_sub_int32_-3_4 printed 2 times — one case measured
  twice, not two cases` on every run.
- `mmfold-lane.py` reports `printed twice` for both lanes and attributes the count to the side that
  owns it.
- **The fixture is NOT deleted.** Deleting it makes `--emit-bend` stop emitting the second line
  while `fold.bend` keeps it, trading a duplicated measurement for an unexplained port row — a
  worse defect, in a file I must not edit.

**The fix belongs to whoever owns `fold.bend`: delete `fold.bend:5865`.** It moves a row name other
units' tables cite, so per the brief it needs the coordinator's call, not mine.

**Measured alongside it, and worth knowing:** `mm-lift-gate.py --emit-bend` reproduces
`fold.bend`'s **127 `lf_row` names byte-for-byte in the same multiset**, so the claim at
`fold.bend:4078` that these 127 lines are *generated* and not transcribed holds, duplicate
included.

---

## 5. THE PLANT AND THE DISARM — `.agents/slop/mmfold/mmfold-plant.py`

Every mutation happens in a **throwaway `copytree` of `tinybendygrad/` under `$TMPDIR`.** The live
`fold.bend` is read and never written — six units are live on it, and `agent-core.md` records one
unit's `cp -R src "$W/tree/"` with no destination *renaming* the directory so its empty hashes
looked like a concurrent edit.

**Plant: drop the low-word carry out of `mm.u64.add`** — a *semantic* mutation in the port's own
arithmetic, not a changed string.

```
BASELINE (live tree, never written)
    port stdout sha256[:16] = 232be7fe302e80b9
    COMPARED 110  DISAGREEMENTS 0  MISSING FROM PORT 0  -> GREEN
PLANT: mm.u64.add: drop the low-word carry
    precondition 3 -- port stdout sha256[:16] = 7b5d03b87263be7e (MOVED)
    COMPARED 110  DISAGREEMENTS 3  MISSING FROM PORT 0  -> NOT GREEN
    rows it moved by name: ['mm_add_2p31', 'mm_add_carryhi', 'mm_add_carrylo']
    expected victims     : ['mm_add_2p31', 'mm_add_carryhi', 'mm_add_carrylo']
    PLANT PASS (lane rc=1)
DISARM: swap two independent bl_row lines
    port stdout sha256[:16] = 7bb0fc69f951fc07 (same bytes, different order)
    COMPARED 110  DISAGREEMENTS 0  MISSING FROM PORT 0  -> GREEN
    measurement identical to baseline: True   lane rc=0
    DISARM PASS
```

Three preconditions per mutation, each inherited from a failure that already cost this project
time: **the anchor occurs exactly once** (`nv_mutate.py` had two anchors whose mutants never
compiled and had been reporting 19 of 28 entries as the whole); **the mutant compiles**
(`bend --check-only` clean, or a DIED verdict would be read as a measurement); **the port's
stdout sha256 moved** — the vacuous-plant trap, where flipping a value whose other operand was
already `True` left a lane's sha256 identical and reading that unchanged verdict as "the gate is
blind" would have been a false finding.

**My predicted victim set was wrong twice and the run corrected it.** I predicted
`{carrylo, carryhi, maxmax}`; the measurement said `{2p31, carryhi, carrylo}`. `2**31 + 2**31` **is**
`2**32`, so `add_2p31` wraps its low word and is a victim. `add_maxmax` is **not** one, and it is
the interesting row: with the carry `hi` is `2**32-1` and without it `2**32-2`, but **both**
spellings overflow, so both print `OVER` — a row that cannot fail is not a row. Prose about
arithmetic is not a measurement.

The disarm's `rc` is deliberately **not** part of its pass condition: the baseline is already
non-green on a defect outside these two oracles (§4), so requiring rc=0 would test the wrong thing.
What it tests is that a pure reordering — the port's bytes change — leaves the *measurement*
identical, which is what makes the plant's redness attributable to a changed **value**.

---

## 6. WALLS, WITH `file:line`

1. **`fold.bend:5865` duplicates `fold.bend:5862`** → 334 lines, 333 names. Root cause is
   `mm-lift-gate.py:31`. Invisible to `diff` and to every name-keyed reader. **Needs the
   coordinator's call**; not mine to edit.
2. **`mm-dt-gate.py` has no driver** → the 24 `bl_dt_*` dtype-limit rows in `fold.bend` are read by
   `rows()` but **compared against nothing**. `LANE-LIVENESS.md:190`, `:281`. Out of scope here:
   those rows are F1, so this lane's reader is not what blocks them — a driver is.
3. **`mm-walk-gate.py` has no driver** → the `_min_max` WALK family. `LANE-LIVENESS.md:190`, `:281`.
   Same cause, same fix shape.
4. **`dsl_gate.py:87 unstable_rows` is an unregistered reader** — pre-existing, and the reason
   `reader-guard.py` still exits 1. Not mine; recorded here so the rc=1 is not misread as my row
   failing. `.agents/slop/LANE-LIVENESS.md:275` names its real obstacle (`oracles/dsl_oracle.txt` embeds a
   heap address).
5. **`.agents/slop/rebase-oracle-ops.py:54` still lacks `import importlib`** (briefed; confirmed
   present, untouched — not mine). This is the lane `LANE-LIVENESS.md:70` calls
   `CANNOT-BE-MADE-LIVE`.
6. **`oracle/dtype_tables.py` emits 14,766 TSV lines, not the 14,774** recorded at
   `rebase-gate.py:415`. Not a defect — the tree grew/shrank — but a number in a comment that is
   now stale, and it is the count that justifies `GAP`, so it is worth restating.
7. **No wall found for the 93 themselves.** `mm-gate.py` and `mm-bl-gate.py` are pure-CPython,
   import nothing from the project, and need no `.venv`. There was nothing blocking them but the
   missing driver.

---

## 7. FILES

| file | what |
|---|---|
| `.agents/slop/mm-lift-gate.py` | **edited.** `oracle_py` pin + re-exec; `DIED` on stdout, rc 2; `--selfcheck` driving both refusals; `DUPLICATE` reporting. |
| `.agents/slop/mmfold/mmfold-rows.py` | **new.** `rows_f3one`, the one-space F3 reader. Registered. |
| `.agents/slop/mmfold/mmfold-lane.py` | **new.** The driver `LANE-LIVENESS.md` asked for: runs the port lane and both oracles, unions the two readers with a disjointness assertion, diffs whole `name=value` lines, `DIED` ≠ `COMPARED ZERO`. |
| `.agents/slop/mmfold/mmfold-plant.py` | **new.** The plant and the disarm, in `$TMPDIR` copies, with the three preconditions. |
| `.agents/slop/reader-contracts.tsv` | **one row appended.** Nothing restructured. |
| `.agents/slop/MMFOLD.md` | this file. |
| `.agents/slop/notes/bend2-constraints.md` | `M-1`…`M-5` appended at the end. |
| `.agents/TODO.md` | the 93 entry ticked. |

**NOT touched:** `tinybendygrad/**`, `rebase-gate.py`, `reader-guard.py`, `LAWS/**`, `PROOF*.bend`,
and every other file on the DO NOT TOUCH list. **Nothing committed.**
