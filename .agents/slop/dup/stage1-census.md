# STAGE 1 — the duplicate-name census, FROM DATA, both sides of every lane

Tool: `checks/dup-census.py`.  Capture: `.agents/slop/dup/dup-capture.py`.
Raw output: `.agents/slop/dup/stage1-census.txt`.  Lane texts: `.agents/slop/dup/dup/lanes/`.

## 0. WHY EVERY LANE TEXT HERE IS FRESH

`eq-census2.py` reads `.agents/slop/eq/lanes/`, which its own author documents as **stale**
(`uop/render.bend`'s cached text is 129 lines where the live one is 140).  So all 78 texts were
re-captured, live, through `.agents/slop/eq/lane.py` — IMPORTED, not forked — which digests the
whole import closure before and after each capture and exits non-zero on a zero-row or mid-edit
one.  The port/oracle pairing comes from `rebase-gate.py`'s own `BASE_ORACLES`, imported.

**Three lanes did not answer, and they are in the denominator:**

| lane | what happened |
|---|---|
| `tinybendygrad/dtype.bend` PORT | `./bin/bend` exits 1 with `Error: 14 defs rely on unsafe or foreign code` and prints 0 rows. 3 capture attempts. The eq cache's copy of this lane is **0 bytes**, so the earlier "78 lane texts" included an empty one. |
| `uop/ops.bend` ORACLE | `.agents/slop/rebase-oracle-ops.py:54` raises `NameError: name 'importlib' is not defined` (it imports `os, pathlib, subprocess, sys` at :34-37 and uses `importlib.util` at :54). **It exits 0 having printed nothing**, which `rebase-gate.py`'s GUARD 2 names as a FAILED ORACLE. Its eq-cache copy has 2,633 bytes, so it broke after that capture. |
| `engine/jit.bend` ORACLE | `.agents/slop/jit-oracle.py` dies in `tinygrad/runtime/support/elf.py:13` with `Attempting to relocate against an undefined symbol sel_registerName`. Its eq-cache copy is 0 bytes. |

So the census below is over **78 lane texts of 39 ports, of which 75 texts are live captures with
content and 3 are empty.**  Every denominator in this file counts them.

## 1. THE TWO NAME DEFINITIONS, AND WHY BOTH ARE COUNTED

`rebase-gate.py:row()` cuts a row at its **FIRST `=`**.  That is the writer's boundary on an F1
lane and NOT on an F2 lane, where the boundary is ` = [` and a name may legally carry one.  So a
duplicate counted under one definition is not yet a duplicate, and the census reports both:

* **strict** — the writer's own boundary, via `eq-census2.boundary()`;
* **shipped** — `row()`'s first-`=` cut, which is what a mutation harness keys on.

**11 names are a duplicate under one definition and not under the other**, and all 11 are on
`uop/render.bend` (5 per side: `ast`, `c2`, `c3`, `c4`, `c5`, plus `py` on the port).  They are
the CONTINUATION class: the structural reader knows those physical lines start inside a bracketed
value, while `row()` cannot tell them from rows and gives them names — so under the shipped
definition they are duplicates and under the writer's they are not rows at all.

## 2. THE TABLE — per lane, both sides, every count with its denominator

`phys` rows the writer emitted · `acc` lines `row()` accepts · `nmS` distinct names under the
writer's boundary · `dupN`/`dupR` duplicate names and the rows on them · **LOST** measurements
unreachable by any name · `refuse` writer rows `row()` refuses · `cont` continuation lines ·
`nob` lines with no writer boundary.

### 2a. The 11 lane texts WITH duplicates (post-fix)

| lane | phys | acc | nmS | dupN | dupR | **LOST** | side |
|---|---|---|---|---|---|---|---|
| `runtime/ops_nv.bend` ORACLE | 574 | 574 | 547 | 27 | 54 | **27** | oracle |
| `runtime/ops_nv.bend` PORT | 611 | 611 | 600 | 11 | 22 | **11** | port |
| `runtime/support/hcq2.bend` ORACLE | 165 | 165 | 163 | 2 | 4 | **2** | oracle |
| `renderer/llvmir.bend` PORT | 471 | 471 | 470 | 1 | 2 | **1** | port |
| `renderer/llvmir.bend` ORACLE | 471 | 471 | 470 | 1 | 2 | **1** | oracle |
| `renderer/tc_ptx.bend` PORT | 334 | 334 | 333 | 1 | 2 | **1** | port |
| `renderer/tc_ptx.bend` ORACLE | 334 | 334 | 333 | 1 | 2 | **1** | oracle |
| `uop/fold.bend` PORT | 241 | 241 | 240 | 1 | 2 | **1** | port |
| `uop/fold.bend` ORACLE | 131 | 131 | 130 | 1 | 2 | **1** | oracle |
| `viz/serve.bend` PORT | 175 | 177 | 174 | 1 | 2 | **1** | port |
| `viz/serve.bend` ORACLE | 175 | 177 | 174 | 1 | 2 | **1** | oracle |
| **11 texts** | | | | **48** | **96** | **48** | 5 port / 6 oracle |

### 2b. The 67 lane texts with NO duplicate — printed, because a table of failures cannot report
a clean lane as clean (`nir_llvmir` vanished from the `=`-unit's table the moment its rename
landed, and `dup-census.py --all` exists for that reason)

`codegen/decomp/dtype`, `codegen/gpudims`, `codegen/opt/search`, `codegen/simplify`, `device`,
`dtype`, `mixin/elementwise`, `mixin/op`, `nn/__init__`, `nn/onnx`, `renderer/amd/generate`,
`renderer/amd/sqtt`, `renderer/cstyle`, `renderer/nir_llvmir`, `renderer/ptx`,
`runtime/ops_amd`, `runtime/ops_cpu`, `runtime/ops_metal`, `runtime/ops_null`,
`runtime/ops_python`, `runtime/ops_qcom`, `runtime/ops_rdma`, `runtime/support/c`,
`runtime/support/elf`, `runtime/support/usb`, `schedule/indexing`, `schedule/prepare`,
`schedule/rangeify`, `tensor`, `uop/ops`, `uop/render`, `uop/spec` — each 0 duplicate names.

Two of those are worth naming: `runtime/support/usb.bend` PORT (940 rows / 940 keys) is **0** and
was 0 before the fix, which is why the fix could be oracle-only; `schedule/prepare` ORACLE has
14 writer rows `row()` refuses and 0 duplicates (§4).

## 3. THE TOTAL, AND IT RECONCILES

```
TOTAL over 78 lane texts of 39 ports
  DENOMINATOR: 11 of 78 lane texts carry at least one duplicate name under the WRITER'S OWN boundary
  rows the writer emitted: 22793   lines the shipped reader ACCEPTS: 23015
  distinct names the producer printed: 22731   distinct keys `rows()` produces: 22885
  DUPLICATE NAMES: 48 over 96 rows, costing 48 measurements (one per surplus row)
  the reader's OWN loss: accepted 23015 − keys 22885 = 130
  and the reader's loss attributes to: 82 continuation + 0 `=`-in-a-name + 48 duplicate = 130   RECONCILES
  NAME-DEFINITION DISAGREEMENT: 11 name(s)
```

**The 0 for the `=`-in-a-name half is not this unit's result — it is the `eb67a99e` rename's, read
back.**  `eq-census2.measure()` is imported for that share precisely so this unit cannot re-derive
it, and it reports 0 reshape rows over the same 78 texts where it reported 294 before
`renderer/nir_llvmir.bend`'s eight `osx=` names were renamed.  The eq unit's `499 = 82 + 294 + 123`
becomes, after the reshape half closed and this unit's `usb` fix, **`130 = 82 + 0 + 48`**, and
the 123 is REPRODUCED by this census's own arithmetic before the fix (`123 = 71 usb + 27 ops_nv
oracle + 11 ops_nv port + 2 hcq2 + 1 tc_ptx + 1 fold + 1 viz_serve + 8 llvmir`, and the 8 llvmir
are a FINDING — the printed list in the eq unit's §10 does not mention them).

## 4. THE TWO CLASSES THAT ARE NOT DUPLICATES, COUNTED APART

Both are measured over the same 78 texts and neither is a duplicate, which is why the
reconciliation needs them separated:

* **14 writer rows `row()` REFUSES** — all in `schedule/prepare`'s ORACLE, all `== SECTION ==`
  banners whose first `=` gives them the name `""`. `rebase-gate.py:row():441` refuses an empty
  name **on purpose**, with the argument in its own docstring.  Counting them as duplicates made
  this census read `82 + 0 + 136 = 218` against a measured `205`; the 13-row gap was exactly the
  banner population minus one.  **A loss is a property of the READER, so a duplicate is measured
  over the lines the reader accepts.**
* **93 lines with NO writer boundary** — all in `uop/fold.bend`'s PORT, §Stage 4.
* **224 continuation lines** — the `=`-unit's class, 82 of which cost a key. Untouched here.

## 5. REPRODUCE

```
.venv/bin/python .agents/slop/dup/dup-capture.py            # 78 live captures, closure-digested
.venv/bin/python checks/dup-census.py --all        # the table above
.venv/bin/python checks/dup-census.py --names      # every offending name, per lane
```

A note on the method's own history, because it is the same species as the bug it measures: the
first version of `dup-census.py` unpacked its `(label, text)` pairs as `for t, lb in texts` and
therefore passed each lane's LABEL as its text.  Every count was a real `int` and all of them were
`0`, and a census of 0 rows over 1 lane reads exactly like a clean lane.  The pair order is now
carried in a comment at `dup-census.py:171`.