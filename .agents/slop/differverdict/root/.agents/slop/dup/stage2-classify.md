# STAGE 2 — the classification.  They are NOT one bug, and one of the four expected classes is
# measured to be EMPTY.

Tool: `dup-census.py --names`.  Raw: `.agents/slop/dup/stage2-classify.txt`.
The classifier decides from **the row text and the two values**, never from the name's shape.

## 0. THE CLASSES, AND THEIR POPULATIONS

| class | test | names | measurements lost |
|---|---|---|---|
| **P1 PRODUCER-LOOP** — one measurement printed more than once | all values on the key are equal | 46 | 46 |
| **P2 DISTINCT-VALUES** — two measurements, one name | every value on the key is distinct | 2 | 2 |
| **P3 SET-ROW** — a name that legitimately repeats because the row IS a set | the name itself carries `| + /` | **0** | **0** |
| **P4 SEPARATOR** — an oracle/port name pair differing only in a separator | see §4 | **0** | **0** |
| | | **48** | **48** |

P1 further splits into two mechanisms, and they have different fixes:

| | mechanism | lanes | lost |
|---|---|---|---|
| **P1a** | the producer **flushes its output twice** | `usb` ORACLE (fixed, 75) | 75 |
| **P1b** | the producer has **two emission sites for one row family** | `ops_nv` 27+11, `hcq2` 2, `llvmir` 1+1, `tc_ptx` 1+1, `fold` 1+1 | 46 |

## 1. P1a — `usb`: ONE `sys.stdout.write` TOO MANY.  FIXED.  75 measurements.

`.agents/slop/usb-oracle-trace.py` accumulates rows into `OUT` and writes that list out **twice**:

```
:268   sys.stdout.write("\n".join(OUT) + "\n")      with  73 rows in OUT
:340   sys.stdout.write("\n".join(OUT) + "\n")      with 126 rows in OUT
```

The counts are **measured, not inferred**: `dup-fix-usb.py` instrumented a copy of the source and
printed `len(OUT)` at each write site.  `73 + 126 = 199` lines, and `usb-oracle-trace.py` alone is
measured at exactly 199.

The 71-duplicate-name / 146-row / 75-measurement shape follows from those two numbers and nothing
else:

* the 73 rows of the first flush are printed again inside the second flush, so **73 names** are on
  a key twice;
* **two** of those 73 are emitted twice INSIDE the first block as well —
  `usb_enum_refused_5_is_checked` (`usb-oracle-trace.py:194` and `:250`) and
  `usb_enum_refused_6_raw_no_fire` (`:195` and `:252`) — so they land 4 times, which is why the
  duplicate-NAME count is 71 rather than 73;
* `73 = 71 + 2`, and the arithmetic closes: **69 × 1 + 2 × 3 = 75.**

The two spellings of each duplicated name compute from different dicts (`checked_pairs`, the
one-device order, versus `_ck_hit`, the two-device order) and the census **measured** their values
equal, so which one survives is immaterial.  It is recorded as a measurement, not assumed.

## 2. P1b — TWO EMISSION SITES FOR ONE ROW FAMILY.  46 measurements, REPORTED.

`ops_nv`'s oracle says out loud what happened, at `nv-oracle.py:338-339`:

```
# :688-694 `_ensure_has_local_memory`. The early return is the NEGATIVE case:
# The `_ensure_has_local_memory` rows live at the foot of this file with the rest
# of the stage-3/4 rows, so there is ONE definition of each.
```

**and the foot copies exist while the body copies also remained.**  Every duplicate in that oracle
is one loop family emitted at two sites:

| family | body site | foot site | names | lost |
|---|---|---|---|---|
| `nv_errstr_%d` | `nv-oracle.py:380` | `:981` | 5 | 5 |
| `nv_iowr_%d_%d` | `:428` | `:439` | 9 | 9 |
| `nv_reloc_msg_%d` | `:701` | `:1154`/`:1156` | 3 | 3 |
| `nv_paccess_%d` | `:385-387` | `:986-990` | 3 | 3 |
| `nv_reloc_bad_refused` / `nv_reloc_bad_n` / `nv_reloc_kind_n` | `:692,:720,:721` | `:1159-1162`, `:1222` | 3 | 3 |
| `nv_bpt_1_48428` | `:878` explicit | `:886` loop | 1 | 1 |
| `nv_launch_ok_1024_1024` / `…_8192` | `:757`,`:760` explicit | `:756` loop | 2 | 2 |

`ops_nv`'s **PORT** has its own 11, and they are a different mechanism again: two rows are
adjacent (`nv_pc_id_after_hit` at lane lines 344/345, `nv_copy_nsteps_4294967295` at 109/111) and
two are at the file's tail (`nv_iface_count` 37/609, `nv_encode_names` 38/610) — i.e. a re-print
at the end of `main` plus two loops whose fixture lists overlap.  **`.bend` files are not this
unit's to edit, so these are reported with `file:line` and not fixed.**

`hcq2`'s oracle's 2 are **adjacent** emissions, `hq2_cfield_gpu_command_flags_at`/`_sz` at lane
lines 152/154 and 153/155 — a two-row block written twice.  Neither name is printed by the port
at all, so the fix is oracle-only and loses no shared name.  NOT FIXED here (see Stage 3 §3).

`llvmir`, `tc_ptx` and `fold` each have **one** duplicate and it is **SYMMETRIC** — the port and
the oracle print the identical line twice.  That symmetry is the evidence that the producer is
shared: `nir_llvmir`'s row-builders are byte-identical to their generator's output (the `=`-unit
measured that for 12 of 12), so the duplication is in the PORT and the oracle inherits it.  Fixing
the oracle alone would un-gate the row instead of gating it twice.  Reported:

| lane | the duplicated line | values |
|---|---|---|
| `renderer/llvmir.bend` PORT+ORACLE | `lt 1 ptr f32 = [float*]   py=[float*]` at lane lines 26 and 29 | equal |
| `renderer/tc_ptx.bend` PORT+ORACLE | `fmt 'ret;' = ['\tret;']   py=['\tret;']` at lane lines 331 and 334 | equal |
| `uop/fold.bend` PORT+ORACLE | `lf_sub_int32_-3_4 lo=-0:7 hi=-0:7` at PORT L84/L87, ORACLE L11/L14 | equal |

## 3. P2 — TWO MEASUREMENTS, ONE NAME.  2 measurements.  THE NAME IS WRONG.

**`nv_reloc_bad_n`, `ops_nv` ORACLE, lane lines 319 and 561, values `1` and `0`.**
`nv-oracle.py:719-721` emits it from `_bad = reloc_fold([(16,8,2),(48,8,3),(64,8,0x38)])` — one
survivor — and `nv-oracle.py:1162` emits `row("nv_reloc_bad_n", 0)` from the **negative-case
block** that starts at `:1153`.  So the second block re-uses the first block's names for a
DIFFERENTLY SHAPED fixture.

**This is worse than a lost measurement: it makes a NEGATIVE CASE unaddressable.**
`nv_reloc_bad_refused` is emitted three times — `"True"` at `:721`, then `"False"` at `:1159` and
`"True"` again at `:1161` — and `rows()` keeps the LAST, so the `"False"` row is the one a reader
would have seen and it is the one CPython does not answer.  `agent-core.md` requires a negative
case for every cache/eviction/refusal rule; **this one exists and is invisible.**

**`dev_sort.GPU Memory`, `viz/serve.bend` PORT and ORACLE (SYMMETRIC), lane lines 117 and 129:**

```
dev_sort.GPU Memory=true/100/GPU/GPU Memory
dev_sort.GPU Memory =false/100/GPU/GPU Memory
```

Two different measurements — the same key before and after the sort toggle — and the second line
carries a **SPACE before the `=`**, so under F1 the name is `dev_sort.GPU Memory` on line 117 and
`dev_sort.GPU Memory ` on line 129, which `.strip()`s to the same key.  This is a separator defect
at the BOUNDARY rather than inside a name: `row()` cannot see it because it strips the head.

## 4. P3 — SET-ROW: MEASURED, AND EMPTY

The brief warned that `Ops.BUFFER|Ops.STACK` in the fold fixture is a row that legitimately
repeats, and that miscounting it would be the third re-run of this project's worst mistake.  So it
was measured rather than assumed, on `uop/fold.bend`'s PORT:

```
rows whose VALUE carries a `|`-joined set: 25 over 25 distinct names
names printed MORE THAN ONCE among them:    []          <-- ZERO
```

**The set is in the VALUE, not in the NAME.**  `mv_exp23`, `mv_expsym`, `mv_reshsym_nm` and 21
others each print once, and the lane's single duplicate is `lf_sub_int32_-3_4 lo`, which has
nothing to do with a set.  A `|`-joined token is not a repeated NAME, and a row carrying one is
not a duplicate.

## 5. P4 — SEPARATOR: CHECKED, AND 0 GENUINE PAIRS

A cross-lane sweep for oracle/port name pairs that differ **only** in a separator, restricted to
pairs where one side's name is a duplicate, found **6** — and **all 6 are false positives of the
check itself**:

```
uop/fold: lf_sub_int32_3_-4 / lf_sub_int32_-3_4      (and the 4 further permutations)
```

They normalise equal because my normaliser treats `-` as a separator, and in
`lf_sub_int32_<signed>_<signed>` a `-` is a **MINUS SIGN**: `3 − 4`, `−3 − 4`, `−3 − 4`, `3 − 4`
are four different measurements.  **So: 0 of the duplicate population belongs to the closed `=`
class, and none of it is recounted there.**  The general rule is worth keeping — a
separator-insensitive name comparison is unsound on any lane whose names embed arithmetic signs,
which in this tree is `uop/fold.bend` and `runtime/ops_nv.bend` (`nv_errstr_N`).

## 6. THE DIRECTION OF THE ERROR, restated because it decided two things here

The `=`-unit's decisive finding was that a one-sided reading of a two-sided defect measures the
reader.  Three places this class would have repeated that mistake, and what the two-sided reading
said instead:

1. **`usb`**: PORT 0 duplicates, ORACLE 71.  Fixing the PORT would have been impossible — there is
   nothing there to fix.
2. **`llvmir` / `tc_ptx` / `fold` / `viz`**: SYMMETRIC, 1 on each side.  A one-sided reading
   reports "the oracle duplicates a row the port prints once" and the fix looks like a rename; the
   two-sided reading reports "both sides print the same line twice", which is a shared producer.
3. **`uop/render.bend`**: under the shipped definition 5-6 names per side are duplicates; under
   the writer's definition **0** are.  The one-sided reading is the whole defect.