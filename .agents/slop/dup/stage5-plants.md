# STAGE 5 — the guard, and the plants WITH THEIR DISARM

Guard: `checks/dup-gate.py`.  `--selftest` over the REAL captured pair.

## 1. WHAT THE GUARD DOES, IN ORDER

**GUARD 0 runs before any value is read**, and every non-zero fact goes into `bad`:

| fact | how it is computed | reader |
|---|---|---|
| duplicate names, WITH multiplicity | `Counter(ROW(l)[0] ...)` over the **lines** | `rebase-gate.py:row()` IMPORTED |
| lines with no writer boundary | bracket-depth pass + the writer's boundary | `eq-census2.scan()` IMPORTED |
| writer rows `row()` refuses | the two above, differenced | both |
| measurements unreachable | `accepted − distinct keys`, the reader's own arithmetic | — |
| **byte identity of the two lanes** | `sha256` of the **non-blank** lines | — |

Then, and only then, the value comparison over shared names.

**Three things this file deliberately does NOT do, each because the same mistake is already in this
project's record:**

* **No second row reader.** `row()`/`rows()` from `rebase-gate.py` and `scan()`/`boundary()` from
  `eq-census2.py` are imported. 156 forked readers exist and one caused a two-round contradiction
  between two gates.
* **No `set()` where a multiplicity is wanted.** `dupes()` returns a LIST-backed `Counter` and reads
  multiplicities from it. `eq-census2.py` read 0 on the one lane in this tree that HAS a duplicate,
  twice, because two `set()`s had already erased it — and its reconciliation line is what caught
  both.
* **No `md5 -q`.** On macOS it takes exactly ONE file and prints nothing given several, so a
  two-lane byte comparison with it silently compares one lane and calls it two. `digest()` uses
  `sha256` over non-blank lines and prints the value on every run.

**Every count carries its denominator**, and the byte-identity line is printed every run with the
sentence that follows from it, because on a lane whose two sides print the same bytes `disagree` is
a **tautological zero** and the byte diff is the gate.

## 2. THE PLANT MATRIX — `nir_llvmir`, a BYTE-IDENTICAL pair

```
.venv/bin/python checks/dup-gate.py \
    --port   .agents/slop/dup/lanes/tinybendygrad_renderer_nir_llvmir.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.].port.txt \
    --oracle .agents/slop/dup/lanes/tinybendygrad_renderer_nir_llvmir.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.].oracle0.txt --selftest

[selftest base] the REAL captured pair: 205 shared names, 0 duplicate name(s), byte-identical=True
  cell     verdict  dup(port) dup(oracle)  byteIdent disagree
  clean    AGREE            0           0       True        0
  value    BROKEN           0           0      False        1
  name     BROKEN           1           1       True        0
  collide  BROKEN           1           1       True        0
[selftest assert] value must BREAK byte-identity: True (base byteIdent=True)
[selftest assert] name must raise dup on BOTH sides with the lanes STILL byte-identical: True --
                  raised port 0->1, oracle 0->1, byteIdent True, disagree 0
SELFTEST OK    (rc 0)
```

| cell | what was injected | expected | measured | |
|---|---|---|---|---|
| **clean** | nothing | the **DISARM**: AGREE, dup 0, byteIdent True | AGREE, 0/0, True, 0 | ✅ |
| **value** | one token inserted **immediately after the first `=`** | caught, and byte-identity breaks | BROKEN, dup 0/0, **byteIdent False**, **disagree 1** | ✅ |
| **name** | one row renamed onto an existing name, **on both sides** | caught, dup rises, lanes **still byte-identical** | BROKEN, dup **1/1**, **byteIdent True**, **disagree 0** | ✅ |
| **collide** | a row renamed onto another name, **the one whose value differs** | dup rises | BROKEN, dup **1/1**, byteIdent True, disagree 0 | ✅ |

**THE NAME PLANT IS DISTINGUISHABLE FROM THE VALUE PLANT IN EXACTLY ONE WAY, and it is the way
that matters:** the NAME plant leaves the two lanes **byte-identical** and `disagree` at 0, while
every value agrees; the VALUE plant breaks byte-identity and raises `disagree` by 1.  A value plant
is **incapable** of the NAME plant's shape, and a name check a value plant can turn green is not
testing the name.

## 3. THE MATRIX REPEATED WHERE THE BASE IS **NOT** ZERO — the four un-disarmed controls

A control whose base is hardcoded 0 is a control that cannot fail, and three controls on this
project were found disarmed, one leaving six lanes green.  So the base is MEASURED, and on four
lanes it is **1 duplicate per side with NO plant at all** — the guard catches the pre-existing
defects by itself:

| lane pair | base dup (port/oracle) | clean verdict | value | name | collide | rc |
|---|---|---|---|---|---|---|
| `renderer/nir_llvmir.bend` (byte-identical) | 0 / 0 | **AGREE** | BROKEN | BROKEN | BROKEN | 0 |
| `renderer/llvmir.bend` (byte-identical) | **1 / 1** | **BROKEN** | BROKEN | BROKEN | BROKEN | 0 |
| `viz/serve.bend` (byte-identical) | **1 / 1** | **BROKEN** | BROKEN | BROKEN | BROKEN | 0 |
| `renderer/tc_ptx.bend` | **1 / 1** | **BROKEN** | BROKEN | BROKEN | BROKEN | 1 (byte-identity claim unavailable) |
| `uop/fold.bend` | **1 / 1** | **BROKEN** | BROKEN | BROKEN | BROKEN | 1 (idem) |
| `runtime/support/usb.bend` | 0 / 0 (post-fix) | **AGREE** | BROKEN | BROKEN | BROKEN | 1 (idem) |

`clean = BROKEN` on `llvmir`, `viz`, `tc_ptx` and `fold` is the load-bearing row of this table: **the
guard is red on four live lanes with nothing injected**, and it is green on `usb` and `nir_llvmir`
only because their duplicates are genuinely gone or genuinely never there.

The three rc=1 rows are the honest limit of the NAME cell, and the gate says so itself:

> `SELFTEST FAILED <<< the pair is NOT byte-identical, so the NAME plant cannot demonstrate the
> byte-identity claim; re-run on a byte-identical pair (nir_llvmir, llvmir, ptx, c, viz, nn) for
> that cell`

## 4. THREE PLANT BUGS THIS SELFTEST CAUGHT ON ITSELF, all recorded in the file

Each one produced a **plausible** wrong answer — which is why they are written down rather than
just fixed.

1. **THE VALUE PLANT WAS IN THE WRONG COLUMN, AND IT WAS NOT CAUGHT.**  The first version appended
   a token to the END of the line.  On an F2 lane the end of the line is inside the `py=`
   **transcription**, and `rebase-gate.py:row()`'s own docstring says so — *"`right` IS DELIBERATELY
   NOT THE COMPARED COLUMN"*.  The measured result on `nir_llvmir` was
   `verdict AGREE, dup 0/0, byteIdent False, disagree 0`: **bytes changed, byte-identity broken,
   and the gate said nothing.**  The fix puts the token immediately after the first `=`, inside
   `left` on every shape.  *A plant that changes bytes without changing anything a comparison reads
   is the exact shape of a transcription-only row, and it is why `rebase-gate.py` refuses to compare
   transcriptions.*
2. **THE ORACLE'S ROW WAS LOCATED BY LINE NUMBER.**  `usb` is 940 lines against 939, so "the same
   edit at the same index" renamed a **different** row on the other side and the NAME plant appeared
   on the oracle alone: `dup(port)=0 dup(oracle)=1`.  Fixed by locating a row by its **name**.
3. **AND BY `startswith`, WHICH WAS ALSO WRONG.**  On an F2 lane whose names are prefixes of one
   another (`ldt f32` / `ldt f32x`) `startswith` renames the wrong row, the plant becomes a no-op,
   and `dup` stays 0 on both sides: a plant that proves nothing, reporting that it proved nothing.
   Fixed by exact-name matching — `dup-gate.py:selftest`'s `idx_of` and the comment above it.

## 5. THE STANDING HAZARD, said on every run

* **On 7 of the 39 port pairs the two sides print the SAME BYTES** — `nn/__init__`, `nn/onnx`,
  `renderer/llvmir`, `renderer/nir_llvmir`, `renderer/ptx`, `runtime/support/c`, `viz/serve`
  (measured with `sha256` of the non-blank lines).  On those, `disagree` is 0 by construction and
  **GUARD 0 is the only thing that can be red.**  The gate prints that sentence every run.
* **On the other 32 the sides differ**, so the value comparison is a real measurement there.
* **The substrate is NOT still on these lanes.** **24 of the 39** port import closures contain
  `tinybendygrad/uop/ops.bend`, another live unit's file (measured through
  `rebase-gate.py:import_closure`; the 15 that do not are the device/runtime files with their own
  two- and four-file closures — and `runtime/support/usb.bend`, the lane this unit fixed, has a
  **2-file** closure, so its substrate is the least exposed on the tree). All 39 port captures went
  through `.agents/slop/eq/lane.py`, which digests the whole closure before and after and prints
  `rc / seconds / lines / distinct keys / closure size`. **A zero on these lanes is a RETRY REQUEST,
  never a result**, and the driver retries three times with backoff. No port capture needed a retry
  except `dtype.bend`, which is the 14-unfilled-laws wall and not a starvation.

## 6. REPRODUCE

```
.venv/bin/python checks/dup-gate.py --port P.txt --oracle O.txt            # rc 0/1
.venv/bin/python checks/dup-gate.py --port P.txt --oracle O.txt --selftest # the matrix
.venv/bin/python checks/dup-gate.py --compare BEFORE.txt AFTER.txt         # multiset proof
```

On a lane with duplicates this exits **1** today. That is the guard armed, and it is the same rc a
value disagreement gives — which is why `--selftest` exists: it is the only thing on these lanes
that says *where* the red landed.