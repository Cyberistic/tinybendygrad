# DELIVERABLE — the duplicate-row-name class, `ops_nv` ORACLE CLOSED (27 of 48), and the
# "lost refusal" is not an overwrite, it is an **UNREACHABLE ARM**

**One file edited: `.agents/slop/nv-oracle.py`.**  20 lines deleted, 3 replaced, 0 added.
**No `.bend` under `tinybendygrad/` was touched** — `nvdev.bend` was not needed and its
`sha256` is reported.  **No `jj` write command was run. Nothing was committed.**

| stage | file |
|---|---|
| 1 — the negative case: what `:1159` actually does | `.agents/slop/nvdup/stage1-the-negative-case.md` |
| 2 — the fix and its multiset proof | `.agents/slop/nvdup/stage2-the-fix.md` |
| 3 — the 21 that remain, every one with `file:line` | `.agents/slop/nvdup/stage3-what-remains.md` |
| 4 — the plant/disarm matrix, and proof the selftest can fail | `.agents/slop/nvdup/stage4-plants.md` |
| tools | `nvdup/nvdup-trace.py` `nvdup/nvdup-probe.py` `nvdup/nvdup-fix-nv.py` `nvdup/nvdup-deadarm.py` |
| raw | `nvdup/nvdup-trace.txt` `nvdup-probe.txt` `nvdup-fix-check.txt` `nvdup-multiset.txt` `nvdup-lanediff.txt` `nvdup-deadarm.txt` `nvdup-deadarm-BEFORE.txt` `nvdup-deadarm-selftest.txt` `nvdup-deadarm-selftest-DISARMFAIL.txt` `nvdup-gate-after.txt` `nvdup-selftest-opsnv.txt` `nvdup-selftest-disarm.txt` |
| rules | `.agents/slop/notes/bend2-constraints.md`, appended as `DUP-2` and `DUP-3` |

## 1. DUPLICATES BEFORE/AFTER, PER SIDE

```
DENOMINATOR: 11 of 78 lane texts -> 10 of 78   (the dup unit's, re-measured on the current lanes)
DUPLICATE NAMES: 48 -> 21 over 42 rows, costing 21 measurements
  the reader's OWN loss: 130 -> 103
    attributed to: 82 continuation + 0 `=`-in-a-name + 21 duplicate = 103   RECONCILES
```

| side | lane text | before | after | moved |
|---|---|---|---|---|
| **oracle** | **`runtime/ops_nv.bend`** | **27 dup names / 27 lost** | **0 / 0** | **← this unit, 574 → 547 rows** |
| oracle | `runtime/support/hcq2.bend` | 2 / 2 | 2 / 2 | not this unit's oracle |
| oracle | `renderer/llvmir.bend` | 1 / 1 | 1 / 1 | producer `llvmir-oracle.py:866` |
| oracle | `renderer/tc_ptx.bend` | 1 / 1 | 1 / 1 | producer `tcptx-oracle.py:394` |
| oracle | `uop/fold.bend` | 1 / 1 | 1 / 1 | producer `mm-lift-gate.py:31` |
| oracle | `viz/serve.bend` | 1 / 1 | 1 / 1 | producer `vz/viz_oracle.py:79-80` |
| **port** | **`runtime/ops_nv.bend`** | **11 / 11** | **11 / 11** | `.bend` DO NOT TOUCH, `sha256 24497e96…` |
| port | `llvmir` / `tc_ptx` / `fold` / `viz` | 1 each | 1 each | generated from the oracle fixtures above |

**The three DEAD ARMS found and deleted cost 0 measurements**, so they appear in no column — they
are §3.  **16 of the 21 remaining are one-element deletions in four lines of `.agents/slop/`**
that un-gate their symmetric port half for free (stage 3 §6).

## 2. IS THE `nv_reloc_bad_refused` OVERWRITE THE SAME DEFECT AS THE DUPLICATES? **NO — TWO.**

> the brief: `:1159` emits `"False"` and `:1161` **overwrites it with `"True"`** — a negative
> case no name can address.

**The `"False"` at `:1159` is never emitted. The line never executes.**  Two instruments that
cannot disagree, over two different things:

| instrument | reads |
|---|---|
| `grep` the captured lane text | the name appears **twice, both `True`** — `:721` and `:1161` |
| `dup-gate.py` multiplicity over the lines | `DUPLICATE 'nv_reloc_bad_refused' x2` |
| `nvdup-trace.py` (every `row()` CALL → its source line) | `x2` — `nv-oracle.py:721 True`, `:1161 True` |

`nvdup-probe.py`, asking CPython element by element: `reloc_of(16,8,2)` **returns**,
`reloc_of(48,8,3)` **raises**, so the comprehension on `:1157` aborts and `:1159` is skipped.

| | mechanism | measurements lost | does a multiplicity census see it? |
|---|---|---|---|
| **D1** two sites for one name | `:720` and `:1162` both write `nv_reloc_bad_n` | **1** | **yes**, `x2` |
| **D2** a dead `try:` arm | `:1159` writes a row into an arm no fixture reaches | **0** | **NO — it emits nothing** |

**They are the same family and they are not one defect.**  Only D1 costs a measurement.  D2 costs
**zero**, because a line that does not execute has no output line to count — so **D2 is invisible
to every duplicate instrument in this project, including `dup-gate.py` and this unit's own
fixer.**  The row it was written to carry, the rule's negative case, was never emitted and never
existed, so **no count of emitted names could ever have reported its absence.**

**D2 is the worse of the two, and it is what the brief was reaching for.**  A lost refusal is a
hole.  An *unrepresentable* refusal is a hole the instrument is shaped so it cannot show you —
the same species as the `py=`-column plant that left six lanes green while disarmed, arrived at
from the other direction.

**AND D2 IS NOT AN INSTANCE OF ONE.**  `nvdup-deadarm.py` reads **4** dead `row()` sites on the
pre-fix oracle, in two families, and two of them had nothing to do with `reloc_of`:

| pre-fix line | row | why it is dead | structural? |
|---|---|---|---|
| `:1139` | `nv_smemcfg_too_big="False"` | `_smem_cfg`'s `min(...)` over `[32,64,100]` is **empty** for `shmem > 102400`; the fixture is `131072` | yes, every `shmem > 102400` |
| `:1146` | `nv_smemcfg_msg_big=""` | same fixture, same block | yes |
| `:1154` | `nv_reloc_msg_%d=""` | every type in `(0,3,100)` falls through `reloc_of`'s arms to its `raise` | yes, 3 of 3 |
| `:1159` | `nv_reloc_bad_refused="False"` | the comprehension aborts on element 1 | yes |

**All four are deleted** (they cost 0 measurements, and the accepted side of each rule is
measured elsewhere by calling), and the census reads **4 → 0**.

**THE FIX MADE THE REFUSAL ADDRESSABLE, NOT MERELY UN-DUPLICATED.**  Two measurable consequences:
`nv_reloc_bad_refused` is now sourced from **CPython's caught `RuntimeError` at `:1161`** instead
of the typed `"True"` at `:721`, and `nv_reloc_msg_0/3/100` are now CPython's own `str(_e)`
instead of three transcribed `"unknown NV reloc %d"` strings.  The rule's negative case was never
missing — it is `nv_reloc_ok_refused="False"` at `:718`, and **both lanes print it**
(port line 318, oracle line 318), so deleting the dead arm loses nothing.

## 3. THE RESIDUAL SEMANTIC DISPUTE, reported not resolved

`nv_reloc_bad_n`'s two sites print **different** values (`1` at `:720`, `0` at `:1162`) and
measure different **subjects**:

| site | expression | subject | answer |
|---|---|---|---|
| `:720` | `len(reloc_fold(...))` | `reloc_fold`, **a helper defined at `:704` of the oracle itself**, which BREAKS on the raise and keeps the prefix | **1** |
| `:1162` | typed `0` | upstream's `NVProgramData.__init__`, which **raises and abandons the object** | **0** |

Upstream, live: `tinygrad/runtime/ops_nv.py:235` `self.relocs = []`, `:262-266`
append-then-`raise`.  **Both are renderings of an unobservable state** — what a discarded object
held.  The port models the second and says why at `tinybendygrad/runtime/ops_nv.bend:2344-2348`.

**The fix deletes the site that has no upstream subject**, per `agent-core.md`'s "a row whose
expected value is a def of the thing under test is not a test" — `reloc_fold` *is* the thing
`nv_reloc_bad_n` was measuring.  So the fix removes the party with no standing instead of choosing
between the readings, and **the surviving `0` is a TYPED model claim, not a CPython answer.**
Recorded as the residual.

**AND THE PORT'S OWN COMMENT RECORDS A THIRD FOLD.**  `ops_nv.bend:2348` says keeping the prefix
"made `nv_reloc_bad_n` answer **2**".  With the fixture the row actually uses (`ops_nv.bend:2372`,
`relocs_bad()`, identical to the oracle's) the prefix is **1**; 2 is what you get if the fold
**continues past** the bad element instead of breaking.  **Three renderings, one name.**  Both
lanes printed `0` before and print `0` after, so this dispute was never a `disagree` — it was
masked by the duplicate itself.

## 4. THE MULTISET PROOF AND THE BYTE-DIFF SHAPE, FOR EACH FIX

There is **one** fix, in one file, with 16 hunks.  The proof is the committed
`dup-gate.py --compare`, **imported, never forked**:

```
ROWS       574 -> 547 lines; 574 -> 547 read; 547 -> 547 distinct names -- EQUAL distinct counts
           is the collision check: a rename created no name
VALUES     same multiset: False   distinct 234 -> 234   only in BEFORE []   only in AFTER []
VALUE SET  identical: True   instances 574 -> 547
DUPLICATES 27 -> 0 name(s) printed more than once, COUNTED FROM THE LINES: none
LOST       27 -> 0 measurements unreachable by any name
RENAME     0 pair(s); 547 name(s) on the BEFORE side have no partner
BYTES      sha256(nb) 0df379b30cd8 -> 92c9e3a8e135   CHANGED
AUDIT OK -- no name is printed more than once
```

* **547 → 547 distinct names**, plus `names LOST entirely: []` and `names GAINED: []`.
* **VALUE SET identical: True**, both `only in` lists empty.  `same multiset: False` is the
  EXPECTED answer for a duplicate fix — it removes surplus *instances* — which is why the set
  question is asked separately and answered separately.
* **27 → 0 duplicates, 27 → 0 lost**, counted from the LINES.
* **`RENAME 0 pair(s)`.**
* **BYTE DIFF OF THE LANE TEXT: 27 deleted, 0 added** — pure deletions, **even though three hunks
  were REPLACEMENTS** (`:296` and `:755` are fixture lists, and the third is a comment).  A
  replacement on a fixture list removes an instance; a replacement on a comment moves no row.
  **That is the load-bearing half: not one answer moved.**  Source diff `1227 → 1207`.

### Every citing file

**`RENAME 0 pair(s)` and no name was gained or lost, so no citation *can* break.**  The census is
printed anyway, because a rename with an unmeasured citation list is how a fix silently un-gates a
lane.  The real hazard was **line-number** citations, which the edit shifts:

| file | cites | after | |
|---|---|---|---|
| `.agents/TODO.md` | `:338-339` | `:338-339` | OK |
| `.agents/slop/dup/stage2-classify.md` | `:338-339` `:380` `:1162` | `:338-339` `:380` **`:1144`** | OK |
| `.agents/slop/dup/stage3-multiset.md` | `:338-339` `:380` | unchanged | OK |
| `.agents/slop/notes/bend2-constraints.md` | `:688` `:417-420` | **`:684`** `:417-420` | OK |
| `.agents/slop/pin-tree-oracle-report.md` · `.agents/slop/reader-fork-census.txt` | `:149` · `:29` | unchanged | OK |
| **`.agents/slop/dup/REPORT.md`** | **`:720`** | **GONE** | **STALE, do-not-touch** |
| **`.agents/slop/dup/stage2-classify.md`** | **`:719-721`** | **GONE** | **STALE, do-not-touch** |

Both stale citations are in `.agents/slop/dup/**`, are stale **in the right direction** (they
describe the defect this unit closed), and are reported rather than edited.
`stage3-multiset.md` §7's `ops_nv` row is stale for the same reason.

### `disagree` — stated before the result

**`disagree=[]` on `ops_nv` is UNAFFECTED BY THIS FIX BY CONSTRUCTION**, because the comparison
dict already collapsed the duplicates; the evidence is the multiset and the byte diff, not the
comparison.  **This lane is NOT a tautological-zero lane** — the two sides' bytes differ
(`f9b565af…` port vs `92c9e3a8…` oracle) — **so `disagree=[]` is also a real measurement here,
and it still says `[]`.**  And the PORT lane's bytes did not move at all:
`sha256 f9b565af8ceabfee9df8a80203a4a19def955ec4e2539055ca018517a40e21de` before and after.

### The tree's own gate, from an instrument with no part in this fix

```
$ .venv/bin/python .agents/slop/rebase-gate.py --port tinybendygrad/runtime/ops_nv.bend
  CAUSE: 600 shared row name(s) across 3 lane pair(s), every one agreeing
    rows interpreted=600   rows native=600   rows cpython:nv-oracle=547
TALLY UNCHANGED=1
```

**GUARD 1 is an ABSOLUTE row count** (the usb unit's lesson), it read `574` before this fix, and
it is **satisfied rather than tripped** — measured, not assumed.  `ops_nv.bend`'s
`sha256 = 24497e96ddebc56c802bc8ed9fd36c998c794d066e5ce7b3575cb0f42272062c`, unchanged.

**AND THE TREE'S OWN GATE IS STILL RED ON THIS LANE**: `VERDICT: BROKEN (DUPLICATE NAME)`, rc 1,
on the PORT's 11.  The dup unit's sharpest point applies again — `usb` and `viz` were green while
carrying duplicates, so the class is not merely under-reported, the gate is **green-capable** on
it and only `dup-gate.py` is red.

## 5. THE PLANT / DISARM MATRIX, AND PROOF THE SELFTESTS CAN FAIL

### `dup-gate.py --selftest` on `nir_llvmir` (byte-identical) — `SELFTEST OK`, **rc 0**

| cell | dup p/o | byteIdent | disagree |
|---|---|---|---|
| clean (**DISARM**) | 0 / 0 | True | 0 |
| **value** | 0 / 0 | **False** | **1** |
| **name** | **1 / 1** | **True** | 0 |
| collide | 1 / 1 | True | 0 |

### `dup-gate.py --selftest` on `ops_nv` — **`SELFTEST FAILED`, rc 1**

**This is the required proof the selftest can fail, and it is on the lane I fixed.**  Base
`dup(port)=11 dup(oracle)=0`: my fix moved the oracle 27 → 0 and the `clean` cell is **still
red, on the port's 11**.  A red with no paired disarm proves nothing about where it landed; here
the disarm says where it is.  The tool names its own limit in the failure text instead of
reporting a green it did not earn.

### `nvdup-deadarm.py --selftest` — `OK`, **rc 0**, and **rc 1 against the pre-fix file**

```
                 dead sites   dup names     assertion
clean  (DISARM)       0          0        PASS
dead                  1          0        PASS      <- a row() in an unreachable try-arm IS seen
live                  0          0        PASS      <- a row() that DOES execute is not called dead
dup                   0          1        PASS      <- a duplicate is NOT a dead site
longhand              0          1        PASS      <- a duplicate that BYPASSES row() escapes the
                                                      SITE census; the LINE census catches it

same code, .agents/slop/nvdup/nv-oracle-PREFIX.py:  clean DEAD SITES=4  ->  [FAIL] x4, rc 1
```

**4 of 5 assertions go red on the pre-fix file and 5 of 5 pass on the fixed one.**  The DISARM
assertion *firing* is what makes the green run mean something — a control whose base is hardcoded
0 cannot prove it would have fired, and three controls on this project were found disarmed.

**The census, before and after, on one instrument:** dead sites **4 → 0**, duplicate names
**27 → 0**, lane rows **574 → 547**, over `sha256 995767bf35fb0717 → 6ce19734cb5a865b`.

**The `dup`/`longhand` pair is load-bearing:** a duplicate is not a dead site, and a row emitted
without `row()` is invisible to the site census, so **neither census substitutes for the other** —
and the `longhand` cell makes that limit a printed number instead of a surprise.

### Three things that failed, each producing a plausible wrong answer

1. **Wrapping `row()` by assignment read `0` calls against 574 printed lines** — `nv-oracle.py:29`'s
   own `def row` reclaims the name on every `exec`.  The assert on that line caught it.
2. **The dead-arm selftest could not RUN on its first attempt** — the plant anchor carries the
   `if __name__ == "__main__":` line, so appending put the plant inside that block and the
   `IndentationError` fired.  A control that cannot run is not a control.
3. **The fixer nearly wrote a broken oracle** — deleting `nv_smemcfg_msg_big`'s dead arm left
   `try:` with only an `except:`; `nvdup-fix-nv.py:run()` raises on a non-zero oracle exit, so it
   reported and **wrote nothing**, and the census still read 27 afterwards.

## 6. THE FIVE CLASSES, REVISED BY MEASUREMENT

| class | dup unit | **measured here** | what changed |
|---|---|---|---|
| P1 two sites, same value | 46 | **25** on `ops_nv` | and **19 of those 25 are ONE line**, not two — a fixture list that names the key twice |
| P2 two sites, distinct values | 2 | **1** on `ops_nv` | the sibling's `nv_reloc_bad_refused` is **not** P2; it is P1-with-a-dead-arm |
| P3 set-row | 0 | not re-run | measured empty by the dup unit; not re-litigated |
| P4 separator | 0 | not re-run | measured empty; the `vf_` minus-sign false positives are real |
| **P5 DEAD-ARM** | — | **4 sites, 0 measurements** | **new, and invisible to every multiplicity census** |
| **P6 value-only misclassification** | — | **1 name** | `nv_launch_ok_1024_1024` / `_1024_8192`: two fixtures, one name, answers that COINCIDE, so a value test calls it P1 |

**The P1/P2 split is a VALUE test, not a SEMANTIC one.**  It answers "do the two rows agree",
which is not "are they the same measurement".  `nvdup-trace.py` attributes every `row()` call to
its source line and reads `26 P1 / 1 P2`; reading the two *expressions* then shows one of those
P1s is two fixtures.  That changes the fix: drop the colliding tuple member, do not delete a
duplicate instance.

## 7. WALLS, `file:line`

| | where |
|---|---|
| **The brief's central premise is wrong**: `:1159`'s `"False"` is not emitted and not overwritten; it never executes, and the name appears **twice, both `True`**. | `nv-oracle.py:1157-1161` (pre-fix numbering) |
| **`nv_reloc_bad_n` = 0 is a TYPED model claim**, and CPython cannot answer it without a device; the site that could (`:720`) measured an oracle-local helper instead. | `nv-oracle.py:1162` |
| **The port's `nv_reloc_bad_n=0` comment cites a measurement of a different fold** — it says keeping the prefix answers `2`; with this fixture the prefix is `1`, and `2` is a fold that CONTINUES past the bad element. | `tinybendygrad/runtime/ops_nv.bend:2348`, fixture at `:2372` |
| **THE PORT'S 11, all in a do-not-touch file**, `sha256 24497e96…` reported and not edited. | `ops_nv.bend:1687`, `:1688`, `:3464`, `:3472`, `:3608-3613`, `:3625`, `:3634`, `:3642`, `:3643`, `:3648-3652`, `:3857`, `:3858` |
| **`nvdev.bend` was NOT needed** and not touched: `sha256 d00afaf6628bfa6dc0cd9178fe52cff99267689345310ecb2bb53866e712e4f7`. | — |
| **17 of the 21 remaining are one-element deletions in four `.agents/slop/` lines**, and each un-gates its symmetric port half for free. | `llvmir-oracle.py:866`, `tcptx-oracle.py:394`, `mm-lift-gate.py:31`, `hcq2-oracle.py` |
| **"Symmetric" has the direction backwards on `llvmir` and `tc_ptx`**: the PORT lines are GENERATED from the oracle's fixture. | `llvmir.bend:981` ← `llvmir-oracle.py:866`; `tc_ptx.bend:878` ← `tcptx-oracle.py:394` |
| **`viz`'s 1 is NOT a mechanical deletion** — `"GPU Memory "` vs `"GPU Memory"` with a trailing space, two different values, and `row()` `.strip()`s the head. It needs a DECISION. | `vz/viz_oracle.py:79-80`; `serve.bend:1909` |
| **A `fold` row's producer cannot be found by grepping the name** — `grep -c 'lf_sub_int32' tinybendygrad/uop/fold.bend` is **0**; the name is built at `mm-lift-gate.py:206`. | `mm-lift-gate.py:206-207` |
| **`helpers.bend` moved under the `ops_nv` gate run** (six units live), so its counts are lower bounds; its own text says so. | `rebase-gate.py` output |
| **`nvdup-deadarm.py`'s site selector is textual** (`^\s*row\(`): a row emitted any other way escapes it. Measured as the `longhand` cell. | `nvdup-deadarm.py` |
| **`timeout` is not installed on this box**, so `dup-census.py --all` cannot be bounded. | — |

## 8. REPRODUCE

```
.venv/bin/python .agents/slop/nvdup/nvdup-trace.py                       # every row() -> its source line
.venv/bin/python .agents/slop/nvdup/nvdup-probe.py                       # asks CPython: is the arm dead?
.venv/bin/python .agents/slop/nvdup/nvdup-fix-nv.py --check               # runs BOTH oracles, writes nothing
.venv/bin/python .agents/slop/nvdup/nvdup-deadarm.py --selftest          # the matrix, rc 0
.venv/bin/python .agents/slop/nvdup/nvdup-deadarm.py --selftest --file .agents/slop/nvdup/nv-oracle-PREFIX.py   # rc 1, THE PROOF
.venv/bin/python .agents/slop/dup/dup-capture.py --only ops_nv            # re-capture both sides, live
.venv/bin/python .agents/slop/dup/dup-gate.py --compare BEFORE AFTER       # the multiset proof
.venv/bin/python .agents/slop/dup/dup-gate.py --port P --oracle O --selftest   # rc 1: the port's 11
.venv/bin/python .agents/slop/dup/dup-census.py --all                     # the tree-wide table
```