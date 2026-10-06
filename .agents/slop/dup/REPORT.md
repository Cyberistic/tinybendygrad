# DELIVERABLE — the DUPLICATE row-name class.  `usb` CLOSED (75 measurements), the rest
# CLASSIFIED with `file:line`, and the census RECONCILES against the reader's own arithmetic.

**Nothing under `tinybendygrad/` was edited.**  Three lines were deleted from
`.agents/slop/usb-oracle-trace.py`.  **No `jj` write command was run.**

| stage | file |
|---|---|
| 1 — the census, both sides, from live captures | `.agents/slop/dup/stage1-census.md` |
| 2 — the classification | `.agents/slop/dup/stage2-classify.md` |
| 3 — the fix and the multiset proof | `.agents/slop/dup/stage3-multiset.md` |
| 4 — `uop/fold.bend`'s 93 | `.agents/slop/dup/stage4-fold.md` |
| 5 — the guard and the plants | `.agents/slop/dup/stage5-plants.md` |
| tools | `checks/dup-census.py`, `dup-capture.py`, `dup-gate.py`, `dup-fix-usb.py` |
| raw | `.agents/slop/dup/stage1-census.txt`, `stage2-classify.txt`, `dup-census.json`, `lanes/` |

## 1. STAGE 1 — the census

**78 lane texts of 39 ports, ALL re-captured live** through `.agents/slop/eq/lane.py` (imported,
closure-digested, retries on a zero) because `.agents/slop/eq/lanes/` is documented stale.

```
DENOMINATOR: 11 of 78 lane texts carry at least one duplicate name under the WRITER'S OWN boundary
rows the writer emitted: 22793   lines the shipped reader ACCEPTS: 23015
distinct names the producer printed: 22731   distinct keys `rows()` produces: 22885
DUPLICATE NAMES: 48 over 96 rows, costing 48 measurements
the reader's OWN loss: accepted 23015 - keys 22885 = 130
attributes to: 82 continuation + 0 `=`-in-a-name + 48 duplicate = 130   RECONCILES
```

| lane | rows | distinct names | duplicates | **unaddressable** |
|---|---|---|---|---|
| `runtime/ops_nv.bend` ORACLE | 574 | 547 | 27 | **27** |
| `runtime/ops_nv.bend` PORT | 611 | 600 | 11 | **11** |
| `runtime/support/hcq2.bend` ORACLE | 165 | 163 | 2 | **2** |
| `renderer/llvmir.bend` PORT / ORACLE | 471 / 471 | 470 / 470 | 1 / 1 | **1 / 1** |
| `renderer/tc_ptx.bend` PORT / ORACLE | 334 / 334 | 333 / 333 | 1 / 1 | **1 / 1** |
| `uop/fold.bend` PORT / ORACLE | 241 / 131 | 240 / 130 | 1 / 1 | **1 / 1** |
| `viz/serve.bend` PORT / ORACLE | 175 / 175 | 174 / 174 | 1 / 1 | **1 / 1** |
| the other 67 lane texts | — | — | **0** | **0** |

**11 of 78 texts: 5 on the PORT side, 6 on the ORACLE side. 15 measurements lost port-side, 33
oracle-side.  67 of 78 carry none.**

**Both name definitions were counted, and the census REPRODUCES the `=`-unit's 123 from a second
implementation** that imports `rebase-gate.py:row()` and `eq-census2.scan()` and adds only the
multiplicity: `123 = 71 usb + 27 ops_nv oracle + 11 ops_nv port + 2 hcq2 + 1 tc_ptx + 1 fold +
1 viz_serve + 8 llvmir`.  **The 8 `llvmir` are a FINDING — the printed list in the eq unit's §10
does not mention them.**

## 2. STAGE 2 — the classification

| class | names | measurements | mechanism |
|---|---|---|---|
| **P1 PRODUCER-LOOP** | 46 | 46 | one measurement printed twice |
| ├ P1a **double flush** | 71 | **75** | `usb-oracle-trace.py` writes `OUT` at `:268` (73 rows) and `:340` (126 rows) |
| └ P1b **two emission sites for one family** | 46 | 46 | `ops_nv` 38, `hcq2` 2, `llvmir` 2, `tc_ptx` 2, `fold` 2 |
| **P2 DISTINCT-VALUES** | 2 | 2 | two measurements, one name |
| **P3 SET-ROW** | **0** | **0** | *measured empty* |
| **P4 SEPARATOR** | **0** | **0** | *measured empty* |

**P3 was measured because miscounting it would be the third re-run of this project's worst
mistake:** 25 rows on `fold`'s port carry a `|`-joined set in their VALUE over 25 distinct names,
and **0 of the 25 is a duplicate**. The set is in the value; the name is a name.

**P4 was checked and is 0 genuine.** My own separator-insensitive sweep reported 6 pairs on
`uop/fold` and **all 6 are false positives**: `lf_sub_int32_<signed>_<signed>` puts a **MINUS SIGN**
where the check expects a separator.

**P2 is two measurements and both are worse than a lost row.** `nv_reloc_bad_n` is `1` at
`nv-oracle.py:720` and `0` at `:1162`; `nv_reloc_bad_refused` is `"False"` at `:1159` and
overwritten by `"True"` at `:1161`, so **a NEGATIVE CASE is unaddressable** — the one kind of row
`agent-core.md` requires for every refusal rule.  `viz`'s `dev_sort.GPU Memory` has **different
values** and a space before the second `=`, so its key is one key for two answers.

## 3. STAGE 3 — the fix, PROVEN BY MULTISET

`usb-oracle-trace.py`, **3 lines deleted**, and the arithmetic closes on two measured numbers:
`73 = 71 + 2` names duplicated, `69×1 + 2×3 = 75` measurements lost.

```
ROWS       1014 -> 939 lines; 939 -> 939 distinct names -- a rename created no name
VALUES     only in BEFORE []   only in AFTER []        VALUE SET identical: True
DUPLICATES 71 -> 0     LOST 75 -> 0     RENAME 0 pair(s)     BYTES CHANGED
BYTE DIFF  75 lines deleted, 0 added   -- only deletions, so no answer moved
```

**Every citing file is listed** in `stage3-multiset.md` §2 — `usb.bend` itself cites both names
(×1 and ×4) — and **none of them can break, because no name changed**: `RENAME 0 pair(s)`.
`rebase-gate.py`'s GUARD 1 absolute count is satisfied rather than tripped: `shared names: 939 of
940 port / 939 oracle, disagree=[]`, and the port lane's `sha256` is **unmoved**.

**`disagree` is UNAFFECTED BY THIS FIX BY CONSTRUCTION** — the comparison dict already collapsed
the duplicates — so the evidence is the byte diff and the multiset, not the value comparison. This
lane is **not** a tautological-zero lane (the two sides' bytes differ), so `disagree=[]` is also a
real measurement here.

**Confirmed by the TREE'S OWN gate, and it is the sharpest statement of the class:**

```
$ rebase-gate.py --port tinybendygrad/runtime/support/usb.bend    -> UNCHANGED  rc 0
$ rebase-gate.py --port tinybendygrad/viz/serve.bend              -> UNCHANGED  rc 0
$ rebase-gate.py --port tinybendygrad/runtime/support/hcq2.bend   -> UNCHANGED  rc 0
```

`usb` is right — nothing the gate measures moved, so GUARD 1 is satisfied and not tripped.  But
`viz/serve.bend` and `hcq2.bend` are green **while each still carries a duplicate name on its
oracle side**, so the class is not under-reported: the tree's gate cannot see it at all.

## 4. STAGE 4 — `fold.bend`'s 93: **A FORMAT THE READER CANNOT PARSE**

93 lines at L201–L310, 55 `mm_*` and 38 `bl_*`, **each with exactly ONE space** (histogram `{1: 93}`).
`rebase-gate.py:412`'s `GAP` is **TWO** spaces and `:448-455` is the whole F3 rule, so `row()`
returns `None` for all of them.  Proof the row is well-formed:
`row("mm_add_zero  0:0")` → `('mm_add_zero','0:0','0:0')`.  The lane reports **0** continuations and
is bracket-balanced, so the brief's "cannot fold" does not apply.  Producer:
**`tinybendygrad/uop/fold.bend:4071` and `:4077`**.

**And they are UNGATED as well as unaddressable:** `mm-lift-gate.py` prints **0** `mm_*`/`bl_*`
rows.  93 measurements have no CPython answer either, and any coverage claim reading "241 rows" for
that lane is reading 241 of 334.

**`fold.bend` is do-not-touch and was not edited.**

## 5. STAGE 5 — the guard, and the plants WITH THEIR DISARM

```
cell     verdict  dup(port) dup(oracle)  byteIdent disagree
clean    AGREE            0           0       True        0     <-- the DISARM
value    BROKEN           0           0      False        1
name     BROKEN           1           1       True        0     <-- lanes STILL byte-identical
collide  BROKEN           1           1       True        0
SELFTEST OK   (rc 0)   -- over the REAL 205-row nir_llvmir pair
```

**A NAME plant leaves the lanes byte-identical; a VALUE plant cannot.**  And on `llvmir`, `viz`,
`tc_ptx` and `fold` the **base cell is BROKEN with nothing injected** — the guard is armed on four
live lanes.

**Three plant bugs caught on the guard's own selftest, each producing a plausible wrong answer:**
the VALUE plant landed in the `py=` **transcription** column and read
`AGREE, byteIdent False, disagree 0` — bytes changed, gate silent; the oracle's row was located by
LINE NUMBER (`usb` is 940 against 939) so the plant hit the oracle alone; and by `startswith`,
which made the plant a no-op and reported `dup 0` on both sides.

## 6. WALLS AND FINDINGS, with `file:line`

| | where |
|---|---|
| **A LIVE DEFECT: `uop/ops.bend`'s wired oracle cannot run.** `NameError: name 'importlib' is not defined` at `.agents/slop/rebase-oracle-ops.py:54` (imports at `:34-37`), and it **exits 0 having printed nothing** — `rebase-gate.py`'s GUARD 2's own words. Its eq-cache copy has 2,633 bytes, so it broke after that capture. **`uop/ops.bend` is the file every closure contains.** NOT FIXED — not this unit's oracle. |
| **`tinybendygrad/dtype.bend`'s PORT cannot be captured at all.** rc=1, 0 rows, `Error: 14 defs rely on unsafe or foreign code`. 3 attempts. |
| **`engine/jit.bend`'s ORACLE dies** in `tinygrad/runtime/support/elf.py:13`: `Attempting to relocate against an undefined symbol sel_registerName`. |
| **The earlier "78 lane texts" denominator included two EMPTY files** — `eq/lanes/*dtype.bend.port.txt` and `*jit-oracle.txt` are 0 bytes. So the eq unit's "rows the writer emitted: 22968" is over 78 texts of which 2 print nothing. |
| **The 93 need a 2-character producer fix AND an oracle that answers them**, and `fold.bend` is do-not-touch while `mm-lift-gate.py` prints none of the families. |
| **`ops_nv` 38, `llvmir` 2, `tc_ptx` 2, `fold` 2, `viz` 2, `hcq2` 2** need `.bend` edits (or an oracle edit whose port side must move too, or the fix un-gates the row instead of gating it twice). All with `file:line` in `stage3-multiset.md` §7. |
| **`hcq2`'s 2 is the one remaining ORACLE-ONLY fix** (adjacent duplicate emissions at lane lines 152-155, and the port prints neither name). Left for the unit that owns `hcq2.bend`. |
| **The brief's recorded `lf_sub_int32_-3_4` finding is wrong on both halves**: the real key is **`lf_sub_int32_-3_4 lo`** (the producer writes `" lo="`), and the two values are **equal**, not different. |

## 7. ⚠ A CONCURRENCY FACT

`tinybendygrad/uop/ops.bend` is in **24 of the 39** port import closures (measured through
`rebase-gate.py:import_closure`; the 15 without it are the device/runtime files with their own
two- and four-file closures) and belongs to a live unit. `runtime/support/usb.bend` — the lane this
unit fixed — has a **2-file** closure, so it is the least exposed substrate on the tree. All 39
port captures went through `.agents/slop/eq/lane.py`, which digests the whole closure before and
after and prints `rc / seconds / lines / distinct keys / closure size`; **no port capture needed a
retry except `dtype.bend`**, which is the 14-unfilled-laws wall rather than starvation.
`.agents/slop/rebase-gate.py` was **not** modified — its `row()`, `rows()`, `GAP`, `PY_TAIL`,
`import_closure` and `substrate_manifest` are IMPORTED by every tool here, which is the whole
reason this unit forked no reader.

## 8. REPRODUCE

```
.venv/bin/python .agents/slop/dup/dup-capture.py                 # 78 live captures
.venv/bin/python checks/dup-census.py --all             # the table
.venv/bin/python checks/dup-census.py --names           # every offending name
.venv/bin/python .agents/slop/dup/dup-fix-usb.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git] --check          # the count assertions, no writes
.venv/bin/python checks/dup-gate.py --port P --oracle O --selftest
.venv/bin/python checks/dup-gate.py --compare BEFORE.txt AFTER.txt
```