# THE `aligned(...)` NUMBER -- `render_vector_prefix` / `ku_align`

THE DEFECT, MEASURED. UPSTREAM `tinygrad/renderer/cstyle.py:310-313` (the **Clang**
`render_vector_prefix`):

```python
  def render_vector_prefix(self, dt:DType, count:int) -> str:
    # round (down) to power of two (this is actually the default clang behavior)
    alignment = dt.itemsize if self.target.device == "CPU" else (2**int(math.log2(dt.itemsize * count)) if not dtypes.is_bool(dt) else 1)
```

THE PORT, BEFORE THIS SESSION: `tinybendygrad/renderer/cstyle.bend`'s `ku_align` TOOK NO
`count` AND ANSWERED A CONSTANT `4` OFF-CPU.

| dtype | count | itemsize | itemsize*count | upstream (GPU) | port (GPU, BEFORE) | upstream (CPU) | port (CPU, BEFORE) |
|---|---|---|---|---|---|---|---|
| f32 | 4 | 4 | 16 | **16** | **4** | 4 | 4 |
| f32 | 3 | 4 | 12 | **8** | **4** | 4 | 4 |
| f32 | 5 | 4 | 20 | **16** | **4** | 4 | 4 |
| f32 | 6 | 4 | 24 | **16** | **4** | 4 | 4 |
| i8 | 3 | 1 | 3 | **2** | **4** | 1 | 1 |
| i8 | 5 | 1 | 5 | **4** | **4** | 1 | 1 |
| i8 | 6 | 1 | 6 | **4** | **4** | 1 | 1 |
| bool | 4 | 1 | 4 | **1** | **4** | 1 | 1 |
| bool | 16 | 1 | 16 | **1** | **4** | 1 | 1 |

SO THE PORT'S ALIGNMENT WAS **TOO SMALL FOR EVERY VECTOR WIDER THAN ONE ELEMENT** AND
**TOO LARGE FOR A `bool` VECTOR**. THE `bool` ARM WAS WRONG ON **EVERY** COUNT, INCLUDING
THE ONES WHERE THE PRODUCT IS 4.

## THE FIX

`tinybendygrad/renderer/cstyle.bend`, `ku_align`:

```python
def ku_align(cpu: Bool, +dt: S.Dt, +count: U32) -> U32:
  Bool.pick(U32, cpu, S.Dt.itemsize(dt),
    Bool.pick(U32, S.Dt.is_bool(dt), 1, U32.shln(1, U32.log2(U32.mul(S.Dt.itemsize(dt), count)))))
```

* **CPU -> `dt.itemsize`.** UPSTREAM's `self.target.device == "CPU"`.
* **OTHERWISE -> `1` FOR A `bool`.** UPSTREAM's `dtypes.is_bool(dt)` ARM.
* **OTHERWISE -> THE GREATEST POWER OF TWO `<= dt.itemsize * count`.** UPSTREAM's
  `2**int(math.log2(dt.itemsize * count))`.

## WHY `U32.shln(1, U32.log2(n))` IS UPSTREAM's `2**int(math.log2(n))`

`U32.log2` IN BEND IS THE **FLOOR** OF `log2` -- IT IS THE INDEX OF THE HIGHEST SET BIT --
SO `1 << log2(n)` IS THE GREATEST POWER OF TWO `<= n`. MEASURED, BEND AGAINST CPython:

| n | 12 | 3 | 5 | 6 | 1 | 2 | 4 | 8 | 16 | 20 | 24 | 28 | 32 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `U32.shln(1, U32.log2(n))` | 8 | 2 | 4 | 4 | 1 | 2 | 4 | 8 | 16 | 16 | 16 | 16 | 32 |
| `2**int(math.log2(n))` | 8 | 2 | 4 | 4 | 1 | 2 | 4 | 8 | 16 | 16 | 16 | 16 | 32 |

AND IT IS THE PORT's OWN IDIOM: `tinybendygrad/runtime/support/memory.bend`'s `shl1`
(`U32.shln(1, U32.to_nat(x))`, BECAUSE THAT CALL SITE ALREADY HAD A `U32` IN HAND) AND
`frag_sz_max` THERE IS THE SAME FUNCTION UNDER A DIFFERENT NAME -- "THE BIGGEST POWER OF
TWO `<= sz`".

## THE EDGE CASES THE TASK NAMED

* `itemsize * count == 3` -> **2** (GREATEST POWER OF TWO `<= 3`).
* `itemsize * count == 5` -> **4**.
* `itemsize * count == 6` -> **4**.
* `itemsize * count == 12` -> **8**. MEASURED AGAINST CPython, NOT INFERRED.

## WHY IT WAS INVISIBLE

1. **THE CORPUS COULD NOT SEE IT.** THE `aligned(...)` CLAUSE APPEARS IN **NONE** OF THE
   CORPUS's 38 OUTPUTS. MEASURED: `grep -rho "aligned([0-9]*)" runs/graphcmp/D/` IS EMPTY.
   SO **NO GRAPH's OUTPUT MOVED WHEN IT WAS FIXED** -- CONFIRMED BY MEASUREMENT, NOT
   ASSUMED: AFTER THE FIX, **339 OF THE 340** CORPUS ARTIFACTS ARE BYTE-IDENTICAL TO THE
   PRE-FIX RUN. THE ONE EXCEPTION IS `D0-ops-probe.txt`, WHICH DIFFERS **ONLY** IN THE
   ABSOLUTE WORKTREE PATH INSIDE A PYTHON TRACEBACK (9 LINES, ONE LINE DIFFERS, AND IT IS
   THE `File "..."` LINE).
2. **NO GATE COMPARED IT.** `gates/cstyle_render_census.bend`'s HEADER SAID, IN ITS
   POPULATION RULE, THAT `render_vector_prefix` HAS "NO PORT DEF" -- **AND THAT WAS FALSE**:
   `tinybendygrad/renderer/cstyle.bend:3089` DEFINES IT. THE DISCOVERY COMMAND NOW
   RETURNS **13** NAMES, NOT 8.

## THE 64 `rvp_*` ROWS

`gates/cstyle_render_census.bend` (the DRIVER), `gates/cstyle_render_census-oracle.py`
(the ORACLE), `gates/cstyle_render_census-gate.py` (the GATE).

THE ORACLE CALLS CPython's **REAL** `ClangRenderer.render_vector_prefix` -- NOT A
REIMPLEMENTATION. CUDA (`cstyle.py:455`) AND HIP (`cstyle.py:554`) **OVERRIDE** THE METHOD
WITH A DIFFERENT BODY (A `struct __align__(...)` AND A TYPEDEF WITH **NO** ALIGNMENT
ATTRIBUTE), AND THE PORT's DEF EMITS THE CLANG FORM FOR EVERY DEVICE TAG -- SO THE ORACLE
IS THE CLANG RENDERER AND THE PORT's DEVICE TAG IS `1`.

THE FIXTURE VARIES ALL THREE OF UPSTREAM's ARMS:

| arm | the fixture that reaches it |
|---|---|
| `self.target.device == "CPU"` | THE 32 `rvp_cpu_*` ROWS (THE ORACLE SETS `R[1].target` PER ROW, BECAUSE `self.target.device` IS READ **INSIDE** THE METHOD) |
| `dtypes.is_bool(dt)` | THE 6 `rvp_*_1_*` ROWS (`bool` AT COUNTS 2, 4, 16) |
| `dt.itemsize * count` | THE 32 `rvp_gpu_*` ROWS, AND THE COUNTS 3, 5 AND 6 ARE CHOSEN BECAUSE THEIR PRODUCTS (12, 20, 24) ARE **NOT** POWERS OF TWO |

**THE FULL TABLE IS `alignment-table.rows`** (64 ROWS, ONE PER (dtype, count, cpu) FIXTURE,
WITH BOTH SIDES' ANSWERS). **0 DISAGREEMENTS.**

## THE PLANT

`gates/cstyle_render_census-mutate.py`'s **M12** PUTS THE CONSTANT `4` BACK:

```
ok M12 the alignment is the constant 4 again: rc=1, 26 row(s): rvp_gpu_10_8, rvp_gpu_12_16,
   rvp_gpu_12_2, rvp_gpu_12_3, rvp_gpu_12_4, rvp_gpu_12_5, rvp_gpu_12_6, rvp_gpu_12_8,
   rvp_gpu_13_2, rvp_gpu_13_3, rvp_gpu_13_4, rvp_gpu_13_6, rvp_gpu_13_8, rvp_gpu_1_16,
   rvp_gpu_1_2, rvp_gpu_1_4, rvp_gpu_2_16, rvp_gpu_2_3, rvp_gpu_2_8, rvp_gpu_3_3,
   rvp_gpu_6_2, rvp_gpu_6_3, rvp_gpu_6_4, rvp_gpu_6_5, rvp_gpu_6_6, rvp_gpu_6_8
```

THE GATE GOES **rc=1**. THE 38 THAT DO NOT MOVE ARE THE **32 CPU** ROWS (WHICH TAKE THE
`dt.itemsize` ARM, WHICH M12 KEEPS) AND THE **SIX OFF-CPU ROWS WHOSE ANSWER WAS ALREADY 4**
(`f16 x 2`, `f16 x 3`, `i8 x 5`, `i8 x 6`, `u8 x 5`, `u8 x 6` -- ALL OF THEM A 4-BYTE
PRODUCT, WHICH IS THE ONE CASE WHERE THE DEFECT AND THE FIX AGREE).

## THE REACHABILITY, WHICH WAS NOT THERE

THE EDGE's CANDIDATE RULE IS "A MEMBER THAT HOLDS A CAN-FAIL PIN ITS OWN CODE READS", AND
`gates/pincensus-pop.py`'s `rule_a` FINDS A PIN SITE BY A **HEX-VALUED RIGHT-HAND SIDE**.
THIS GATE HAD **NO SUCH CONSTANT** (ITS `PINS` IS A TUPLE OF ROW NAMES, WHICH IS A
DIFFERENT THING), SO IT WAS **NOT A CANDIDATE**:

* BEFORE: `gates/edge-runner.py --plan` -> **28** candidates, `gates/cstyle_render_census-gate.py` **NOT AMONG THEM**.
* AFTER:  -> **29** candidates, and `RUN gates/cstyle_render_census-gate.py`.

THE FIX IS A `DRIFT_PIN` DICT OF FIVE sha256 VALUES PINNING THE UPSTREAM FILES THE ORACLE
READS (`tinygrad/renderer/cstyle.py`, `tinygrad/uop/ops.py`, `tinygrad/dtype.py`,
`tinygrad/helpers.py`, `tinygrad/uop/__init__.py`), RE-MEASURED ON EVERY RUN BY
`gatekit.oracle_drift`. THE SHAPE IS `gates/wgsl_render_census-gate.py`'s `DRIFT_PIN`,
WHICH IS WHY THAT ONE WAS A CANDIDATE AND THIS ONE WAS NOT.

## A FINDING THAT IS NOT MINE: FOUR STALE MUTATION ANCHORS

`gates/cstyle_render_census-mutate.py`'s **M2, M5, M9 AND M10** REPORT
`ANCHOR NOT UNIQUE` (THE ANCHOR APPEARS **0** TIMES). **THIS IS PRE-EXISTING AND IS NOT
CAUSED BY THIS SESSION**: MEASURED AGAINST `git show HEAD:tinybendygrad/renderer/cstyle.bend`
BEFORE THIS SESSION'S EDIT, ALL FOUR ANCHORS ALREADY APPEARRED 0 TIMES. THE CAUSE IS
ANOTHER UNIT's REFACTOR OF THE PORT's `cfo_*` HELPERS FROM `String` TO
`List<&2, String>`:

| anchor | the port's CURRENT spelling |
|---|---|
| `def cfo_unhandled(op: O.Op) -> String: ...` | `def cfo_unhandled(op: O.Op) -> List<&2, String>: ...` |
| `def cfo_unary(nm: String, +x: String) -> String: ...` | `def cfo_unary(nm: String, +x: List<&2, String>) -> List<&2, String>: ...` |
| `def cfo_recip(+x: String) -> String: ...` | `def cfo_recip(+x: List<&2, String>) -> List<&2, String>: ...` |

**NOT FIXED HERE**, BECAUSE THE FIX BELONGS TO WHOSEVER OWNS THAT REFACTOR AND
RE-ANCHORING FOUR MUTATIONS OF ANOTHER UNIT's WORK IS NOT THIS UNIT's SCOPE. IT IS
RECORDED HERE RATHER THAN PAPERED OVER.

## A CHANGE THIS SESSION DID MAKE TO THE HARNESS

THE HARNESS's OWN LANE-ROW COUNT WAS THE LITERAL `722` (361 py + 361 bd). THE `rvp_*` ROWS
MADE IT **850**, SO THE HARNESS REFUSED TO RUN AND SAID "the unmutated tree does not
reproduce" -- WHICH **READS LIKE A BROKEN TREE** AND IS ACTUALLY A STALE NUMBER. IT IS NOW
**DERIVED** FROM THE GATE's OWN `ROWS` BY IMPORTING THE GATE FILE
(`_gate_rows()`), BECAUSE A SECOND COPY OF A COUNT IS A CONTRACT WITH NO GENERATOR.
