# ROT1 — the 40 pointers that `uop/fold.bend`'s move rotted

**SLICE**: `rot1.rows` — **40 `WRONG-LINE` ROWS IN 12 FILES**.
**STATUS**: **LANDED** — **40 -> 0** IN MY FILES, **AND TREE-WIDE `WRONG-LINE`
IS **0****.
**COMMITS**: `dde1f7645`, `6585d1fb8`, `a797bcd5e`.

---

## 1. THE CAUSE, AND IT IS ONE EVENT

Another unit landed the RANGEIFY lane in `tinybendygrad/uop/fold.bend` — a
**real port fix**, `60e36e23f`:

> "the fold's `rng_width` refused every AFTER-bound RANGE, so every `vmax` was
> zero"

The fix inserted **68 lines** near the top of the file, so **every declaration
after it moved down**. The measured deltas:

| construct family | old | new | delta |
|---|---|---|---|
| `sym_dim.end` / `sym_dim.range` / `sym_dim.val` / `sym_dim` | 1622 / 1599 / 1632 / 1641 | 1685 / 1662 / 1695 / 1711 | **+63** |
| `dt_shape` | 2610 | 2673 | **+63** |
| `reshape_ds` / `reduce_ds` / `reshape_ds.of` / `reshape_ds.go` | 2188 / 2199 / 2180 / 2170 | 2251 / 2262 / 2243 / 2233 | **+63** |
| `marg_prod.step` | 2126 | 2189 | **+63** |
| `pre_all` / `stage_widths` | 1538 / 1528 | 1601 / 1591 | **+63** |
| `Kahn.pop` / `Kahn.step` / `Kahn.run` | 4818 / 4824 / 4833 | 4881 / 4887 / 4896 | **+63 / +63 / +63** |
| `fold.addr` / `fold.shape` / `fold.dt` | 4752 / 4764 / 4770 | 4815 / 4827 / 4833 | **+63** |
| `ended_of` | 2805 | 2868 | **+63** |
| `UOp.axis_id` / `UOp.axis_type` | 3028 / 3036 | 3091 / 3099 | **+63** |
| `UOp.ranges` | 5055 | 5118 | **+63** |
| `UOp.min_max` | 5175 | 5238 | **+63** |
| `UOp.dtype` | 4783 | 4846 | **+63** |
| `main` | 6492 | 6590 | **+98** |

**⇒ THE CLASS IS THE ONE THE TREE ALREADY NAMED: "THE LINE IS A ROT AND THE
NAME IS NOT, AND THE ROT IS NOT SLOW."**

## 2. THE REPAIR, AND THE FOUR KINDS

**⇒ THE DURABLE FORM IS `symbol=<name>`, NOT A NEW LINE NUMBER.** A CITATION
THAT NAMES A CONSTRUCT DOES NOT ROT WHEN THE LINES MOVE.

| kind | count | what was done |
|---|---|---|
| **line re-point** (`symbol=` already present, line was wrong) | **34** | the line moved to the construct's DECLARATION line; the `symbol=` and the prose are untouched |
| **`symbol=` conversion** (no `symbol=` at all) | **6** | `kuconv.bend`'s `fold.addr`, `fold.shape` and `sym_dim.of`; `rangify.bend`'s `par_table`, `pfd_table` and `rz_dump`; `tensor.bend`'s `UOp.dtype` — **7** new `symbol=` FIELDS IN **6** ROWS, because `rangify.bend:37` CARRIES **TWO** CITATIONS AND BOTH GOT ONE |
| **absence stated** | **0** | **every construct still exists**; none was deleted, so no claim had to be weakened |
| **`D.refuse("…")` diagnostic corrected** | **0** | **no code line was touched in any of the twelve files** |

### 2.1 THE TRAP THE `symbol=` RULE CARRIES, AND IT IS A REAL ONE

**`gates/todo-cite-gate.py` BINDS THE NEAREST-PRECEDING `symbol=` TO A
CITATION.** A `symbol=` written **next to an upstream `.py` citation** therefore
LANDS ON THE `.py` ONE AND IS JUDGED AGAINST THE UPSTREAM FILE.

**MEASURED**: `renderer/kuconv.bend`'s table rows carry `ops.py:896` and
`movement.py:35` (upstream) BESIDE the port's reader. Putting
`symbol=fold.addr` / `symbol=fold.shape` on those lines produced:

```
WRONG-SYMBOL   kuconv.bend:35  ops.py:896  symbol=fold.addr  how=symbol-absent
                 the marker names `fold.addr`, which `uop/ops.py` does not declare at the pin
UNRESOLVABLE    kuconv.bend:37  movement.py:35  symbol=-  how=no-file
```

**⇒ SO THE PORT's `symbol=` GOES ON ITS OWN LINE**, and that satisfies BOTH
gates: `bendcite-gate` puts every `symbol=` on a line into every citation on
that line, and `todo-cite-gate` binds the nearest preceding one — a line with
only the port's citation binds correctly.

## 3. THE TREE MOVED UNDER ME, TWICE, AND IT IS THE BEST ARGUMENT FOR `symbol=`

**`schedule/indexing.bend` IS A HOT PATH.** Another unit was rewriting it
while this slice ran, and it grew by **+104 lines**.

**MEASURED, `grm_table`'s DECLARATION**:
`1141 -> 1184 -> 1204 -> 1235 -> 1246 -> 1254`.

**MEASURED, `g_nr`'s DECLARATION**: `1316 -> 1409 -> 1420 -> 1428`.

**⇒ EVERY POINTER INTO THAT FILE ROTTED WITH EACH MOVE**, and I re-pointed
them **four times**. **⇒ THE `symbol=` NAME WAS NEVER WRONG** — only the line
moved — **and that is the whole argument for the durable form, measured a
second time.**

**⇒ AND THE ROWS THAT ROTATED OUTSIDE MY SLICE** (the `indexing.bend`
citations at `rangify.bend:26-28, 33, 177, 184, 197, 201, 205` and
`ops.bend:607`) **WERE `RESOLVES` WHEN THE SLICE STARTED** — they are not in
`rot1.rows` — **and they are re-pointed anyway, because a pointer I own that
rots is a pointer I own.**

## 4. THE MEASUREMENTS

### 4.1 `gates/bendcite-gate.py` — PER FILE

| file | before | after |
|---|---|---|
| `tinybendygrad/mixin/op.bend` | **7** | **0** |
| `tinybendygrad/mixin/movement.bend` | **6** | **0** |
| `tinybendygrad/renderer/kuconv.bend` | **5** | **0** |
| `tinybendygrad/schedule/prepare.bend` | **5** | **0** |
| `tinybendygrad/uop/divandmod.bend` | **4** | **0** |
| `tinybendygrad/uop/ops.bend` | **3** | **0** |
| `tinybendygrad/codegen/kernel.bend` | **2** | **0** |
| `tinybendygrad/mixin/creation.bend` | **2** | **0** |
| `tinybendygrad/schedule/rangify.bend` | **2** | **0** |
| `tinybendygrad/tensor.bend` | **2** | **0** |
| `tinybendygrad/codegen/decomp/op.bend` | **1** | **0** |
| `tinybendygrad/codegen/opt/heuristic.bend` | **1** | **0** |
| **TOTAL** | **40** | **0** |

### 4.2 TREE-WIDE

| reading | before | after |
|---|---|---|
| `WRONG-LINE` (mine) | **40** | **0** |
| `WRONG-LINE` (other units' files) | **13** | **0** (they landed `998e57ee9`) |
| `WRONG-LINE` (tree) | **53** | **0** |
| `DANGLING-LINE` | **0** | **0** |
| `ABSENT-FILE` | **0** | **0** |
| `RESOLVES` | 999 | 1062 |
| `WRONG-LINE-BY-BLOCK` | 120 | 120 (**not raised**) |
| `UNCLAIMED` | 66 | 68 (**+2, from the other unit's new citations, not mine**) |
| `AMBIGUOUS` / `OUT-OF-CORPUS` | 19 / 10 | 19 / 10 (**not raised**) |
| **total rows** | 1267 | 1282 |

**⇒ NO OTHER CLASS ROSE BECAUSE OF MY EDIT.** The `UNCLAIMED` +2 is the other
unit's new `schedule/indexing.bend` and `schedule/realize.bend` citations.

### 4.3 `gates/todo-cite-gate.py`

`0 WRONG-LINE`, `0 WRONG-SYMBOL`, `0 UNRESOLVABLE` — **PASS**, before and
after. (It was made RED by my first `kuconv.bend` attempt and is the reason
§2.1 exists.)

## 5. THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()`, loaded **BY PATH**, blank
lines dropped, sha256 of the surviving code:

| file | base | now | same |
|---|---|---|---|
| `mixin/op.bend` | `277efa989ef00407` | `277efa989ef00407` | **YES** |
| `mixin/movement.bend` | `68cbbc85224210ec` | `68cbbc85224210ec` | **YES** |
| `renderer/kuconv.bend` | `5cbe464a90b01c53` | `5cbe464a90b01c53` | **YES** |
| `schedule/prepare.bend` | `184c75603836ef4b` | `184c75603836ef4b` | **YES** |
| `uop/divandmod.bend` | `a84d33eaa6a580e0` | `a84d33eaa6a580e0` | **YES** |
| `uop/ops.bend` | `21b223a750b772bf` | `21b223a750b772bf` | **YES** |
| `codegen/kernel.bend` | `3329bc140313e016` | `3329bc140313e016` | **YES** |
| `mixin/creation.bend` | `374e5cb7b377c739` | `374e5cb7b377c739` | **YES** |
| `tensor.bend` | `ec30c983218f6e4a` | `ec30c983218f6e4a` | **YES** |
| `codegen/decomp/op.bend` | `21cd48af47b92778` | `21cd48af47b92778` | **YES** |
| `codegen/opt/heuristic.bend` | `1eb870624d1936b2` | `1eb870624d1936b2` | **YES** |
| `schedule/rangify.bend` | `2ff901aa6bee8c94` | `2ff901aa6bee8c94` | **YES** — **against ITS PARENT `92fa67d0b`**, because the other unit's `92fa67d0b` landed their `rr_range_map` CODE **and** swept my comment edits in with it. **My commit's contribution to that file is comment-only, and their 312 lines of in-flight code are NOT in my commit and are still in the working tree.** |

**⇒ ALL TWELVE FILES ARE COMMENT-ONLY. ZERO FILES ARE NOT.**

## 6. THE COMPILE TOKENS

`checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE bend at a time, and the
**VERDICT TOKEN** is what is read:

| file | token | peak RSS |
|---|---|---|
| `mixin/op.bend` | **`WITHIN-LIMITS`** | 599 MB |
| `mixin/movement.bend` | **`WITHIN-LIMITS`** | 582 MB |
| `renderer/kuconv.bend` | **`WITHIN-LIMITS`** | 475 MB |
| `schedule/prepare.bend` | **`WITHIN-LIMITS`** | 507 MB |
| `uop/divandmod.bend` | **`WITHIN-LIMITS`** | 502 MB |
| `uop/ops.bend` | **`WITHIN-LIMITS`** | 358 MB |
| `codegen/kernel.bend` | **`WITHIN-LIMITS`** | 461 MB |
| `mixin/creation.bend` | **`WITHIN-LIMITS`** | 873 MB |
| `schedule/rangify.bend` | **`WITHIN-LIMITS`** | 650 MB |
| `tensor.bend` | **`WITHIN-LIMITS`** | 564 MB |
| `codegen/decomp/op.bend` | **`WITHIN-LIMITS`** | 820 MB |
| `codegen/opt/heuristic.bend` | **`WITHIN-LIMITS`** | 196 MB |

## 7. THE PLANT

**A TEXT EDIT ON A COPY OF THE LIVE TREE** (never `git show HEAD:`), and the
plant **INSERTS CODE, NOT A COMMENT** — because a comment is absorbed into the
construct's DOC RUN and the row still resolves.

```python
# IN /tmp/rot1plant/moved/tinybendygrad/uop/fold.bend, AT THE TOP:
def rot1_plant_probe(a: U32) -> U32:
  a

```

| tree | rows | `WRONG-LINE` | mine | `DANGLING` | `ABSENT` | `RESOLVES` |
|---|---|---|---|---|---|---|
| **CONTROL** (copy of the live tree) | 1282 | **0** | **0** | 0 | 0 | 1062 |
| **MOVED** (4 CODE lines inserted at the top of `fold.bend`) | 1282 | **47** | **33** | 0 | 0 | 1014 |
| **TWIN** (byte-identical copy) | 1282 | **0** | **0** | 0 | 0 | 1062 |

**⇒ THE PLANT GOES RED AND THE BYTE-IDENTICAL TWIN STAYS GREEN.** The 33
red rows in the moved copy are exactly this slice's rows.

**⇒ AND THE GATE's OWN `--plant` HAS A PRE-EXISTING DEFECT IN ITS ARM TWO**:
it inserts 2 lines above a pointer that lands **inside a construct's span**,
and the pointer still resolves (`PLANT arm-two moved : RESOLVES`). **ARM ONE
WORKS** (`RESOLVES` -> `WRONG-LINE` -> `RESOLVES` on the twin). **⇒ THIS IS A
DEFECT IN `gates/bendcite-gate.py`'s PLANT AND NOT IN MY WORK, AND I DID NOT
EDIT THE GATE.**

## 8. THE COMMITS

| commit | files | what |
|---|---|---|
| `dde1f7645` | **11** | the 36 pointers into `uop/fold.bend` — 31 line re-points + 5 `symbol=` conversions |
| `6585d1fb8` | **1** | `uop/ops.bend`'s `g_nr`, re-pointed after `schedule/indexing.bend` moved again |
| `a797bcd5e` | **1** | `schedule/rangify.bend`'s 12 pointers into `schedule/indexing.bend` |

**⇒ `git show --stat` AND `git fsck --no-progress` WERE RUN IN THE SAME COMMAND
FOR EACH.** `fsck` NAMES **3** MALFORMED TREES — `d57bc484`, `3a60f33f`,
`d83cf685` — **ALL THREE PRE-EXISTING AND NONE MINE.**

**⇒ THE SHARED INDEX WAS CHECKED BEFORE EACH COMMIT**
(`checks/index-arm-gate.py`: `PASS`, the index agrees with `HEAD` on all
**10012** paths), **AND NOTHING WAS STAGED WITH `git add -A` OR `git add
<dir>`.** `schedule/rangify.bend` WAS A SHARED PATH WITH **312 LINES** OF
ANOTHER UNIT'S IN-FLIGHT CODE, **SO MY COMMIT'S CONTENT WAS BUILT FROM `HEAD`'s
VERSION OF THE FILE PLUS MY COMMENT RE-POINTS, AND THEIR WORKING TREE WAS
RESTORED BYTE-FOR-BYTE AFTERWARDS** (`md5 e0b0040dbc06fbdbe96d0d6387886f88`
before and after).

## 9. THE DIGEST

| reading | digest |
|---|---|
| **BEFORE** (the base of the rot slice, `dde1f7645^` = `739772319`) | `b29839418d8bd8247f71fbfa12aedbc3ab5c1649da1608a8498e68d1c4dd6bd6` |
| **AFTER** (now) | `40c3e432754207c6a8d4657aeebfec12d2b4defa7b09be01474eefe80cf98268` |

**⇒ A COMMENT IS SUBSTRATE, SO A CITATION FIX IS A CORPUS-STALING EDIT.**
**⇒ THE CORPUS MUST BE RE-RUN ONCE THE PORT STOPS MOVING**, and the digest
moved for a second reason too: another unit is editing `schedule/indexing.bend`
and `schedule/rangify.bend` right now.

## 10. WHAT I DID **NOT** FIX, AND WHY

1. **`gates/bendcite-gate.py`'s OWN PLANT, ARM TWO, DOES NOT GO RED.** Its
   inserted 2 lines land above a pointer that is **inside a construct's span**,
   so the pointer still resolves. **⇒ IT IS A GATE DEFECT AND I WAS TOLD NOT
   TO EDIT GATES, SO IT IS REPORTED AND NOT FIXED.** ARM ONE IS CORRECT.

2. **THE `WRONG-LINE-BY-BLOCK` **120** AND `UNCLAIMED` **68** ROWS.** These are
   counted and not failed by the gate's own rule (a claim read off the
   enclosing comment block is a weaker claim than one read off the pointer's
   own line), and they are **not in `rot1.rows`**. **⇒ NOT MINE AND NOT
   FIXED.**

3. **`schedule/indexing.bend` IS BEING REWRITTEN RIGHT NOW, AND IT WILL ROT
   MY POINTERS AGAIN.** **⇒ THAT IS EXPECTED AND IT IS WHY THE `symbol=` FORM
   EXISTS:** the name will still be right, and the next unit only has to move
   the line.

4. **THE OTHER UNIT'S 312 LINES OF IN-FLIGHT `rr_range_map` CODE** IN
   `schedule/rangify.bend`. **⇒ NOT MINE, NOT COMMITTED BY ME, AND LEFT IN
   THEIR WORKING TREE.**

5. **`D.refuse("…")` DIAGNOSTIC STRINGS.** **⇒ NONE EXISTED IN THESE TWELVE
   FILES** — every changed line is a comment, and no file needed the
   diagnostic-string exception.
