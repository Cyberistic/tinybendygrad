# helpers-device-shrink -- THE REPORT

unit: two files. `tinybendygrad/helpers.bend` and `tinybendygrad/device.bend`.

goal: bring the port's line count as close to upstream's as possible WITHOUT LOSING
FUNCTIONALITY, WITHOUT LOSING A SINGLE CITATION OR MEASUREMENT, AND WITHOUT BREAKING
ANY GATE.

measured 2026-11-10. Bend 2.0.34. upstream pin `f5ac54685074`.

---

## 1. THE METRIC, BEFORE AND AFTER

`.venv/bin/python .agents/slop/loc/the-1to1.py` -- the whole tree's metric, the
number the goal is measured by.

| | BEFORE | AFTER | delta |
|---|---|---|---|
| the port | 297806 | 282778 | **-15028** |
| THE RATIO | **4.70x** | **4.46x** | **-0.24x** |
| CODE | 127902 | 124688 | -3214 |
| THE CODE-ONLY RATIO | **2.27x** | **2.21x** | **-0.06x** |
| GATE ROWS | 6658 | 1181 | -5477 |
| COMMENTS | 124925 | 114499 | -10426 |
| BLANK | 38321 | 42410 | +4089 |

**AND THE TREE MOVED UNDERNEATH THIS UNIT WHILE IT WORKED** -- OTHER AGENTS
LANDED COMMITS, **INCLUDING ONE THAT LANDED THIS UNIT's OWN `device.bend`
CHANGES** (COMMIT `1d3d5e7a6`, "THE COMMENT BLOCK's **PROVABLY **REMOVABLE
**HALF** GOES, AND **NOTHING **ELSE**") -- **SO THE TREE-WIDE NUMBER ABOVE IS
**NOT** THIS UNIT's DELTA ALONE.** THE TWO FILES, MEASURED ON THE FILES
THEMSELVES, ARE THE HONEST NUMBER:

| file | BEFORE lines | AFTER lines | BEFORE code | AFTER code |
|---|---|---|---|---|
| `tinybendygrad/device.bend` | 1846 | **1181** | 699 | **429** |
| `tinybendygrad/helpers.bend` | 3313 | **3310** | 1397 | **1397** |

`device.bend`: **-665 lines (-36%)**, and **-270 code lines (-39%)**.

**AND THE `helpers.bend` THREE-LINE MOVE IS **NOT** THIS UNIT's** -- another
agent's prose edit landed in the same file. THIS UNIT's `helpers.bend` IS
UNCHANGED IN CODE: **1397 code lines before and after.**

---

## 2. WHAT CHANGED, AND WHERE

### 2.1 `device.bend`: THE GATE ROWS MOVED TO `gates/device-gate.bend`

`.agents/slop/loc/extract-gate-rows.py --apply tinybendygrad/device.bend` -- the
tree's OWN TOOL, which "MOVES A `.bend` FILE's GATE ROWS INTO `gates/`" and
"VERIFIES THAT THE ROWS ARE BYTE-IDENTICAL BEFORE AND AFTER".

```
tinybendygrad/device.bend: 1127 impl lines, 596 gate lines, 127 helper lines
    port file: WITHIN-LIMITS   driver: WITHIN-LIMITS
```

**THE ROWS ARE BYTE-IDENTICAL.** MEASURED, THE ORIGINAL FILE'S 129 ROWS AGAINST
THE DRIVER'S 129 ROWS:

```
IDENTICAL: 129 rows byte-for-byte
```

**AND `gates/README.md:173` IS THE CITATION FOR THE MOVE** -- "a gate's `.bend`
driver and its CPython oracle sit in `gates/`, named by the gate that needs
them."

### 2.2 THE TOOL HAD A REAL DEFECT, AND FIXING IT IS PART OF THE WORK

`extract-gate-rows.py`'s `external_users()` EXCLUDED **ALL** OF `gates/` FROM
THE CONSUMER SCAN, ON THE GROUND THAT "THE `gates/` DRIVERS ARE THE THING THIS
TOOL WRITES". **THAT IS TRUE OF **ONE** DRIVER -- **THE ONE THIS TOOL IS ABOUT
TO WRITE** -- AND FALSE OF EVERY OTHER.**

**MEASURED 2026-11-10 ON `device.bend`:** THE FIRST EXTRACTION MOVED FOUR DEFS
OUT OF THE PORT THAT **TWO PRE-EXISTING GATE DRIVERS CALL** --
`gates/ops_dsp-gate.bend`'s `D.needs_compile` AND `gates/hcq2-gate.bend`'s
`D.dev_name` / `D.link_add` / `D.link_buffer_base` -- **AND BOTH DRIVERS FAILED
TO COMPILE WITH "expected : a defined name".**

**THE FIX** -- AND IT IS **ONE FUNCTION** SO THE SELF-REFERENCE EXCLUSION AND
THE DRIVER's OWN NAME **CANNOT DRIFT**:

```python
def driver_name(port: Path, root: Path) -> str:
    """**THE NAME OF THE DRIVER THIS TOOL WRITES FOR `port`** -- **AND IT IS **ONE
    FUNCTION** SO THAT `external_users()`'s SELF-REFERENCE EXCLUSION AND THE DRIVER's
    OWN NAME **CANNOT DRIFT**."""
```

AND `external_users()` NOW EXCLUDES **ONLY** `gates/<the-driver-this-tool-writes>`:

```python
        # **AND ONLY **THE DRIVER THIS TOOL WRITES** IS NOT A CONSUMER** -- **EVERY
        # OTHER `gates/` DRIVER IMPORTS OTHER PORTS AND CONSUMES THIS ONE's API TOO.
        rel_parts = cand.resolve().relative_to(root).parts
        if len(rel_parts) > 1 and rel_parts[0] == "gates" and cand.name == self_driver:
            continue
```

**THE FIXED TOOL'S OWN OUTPUT IS 50 LINES LARGER** (1127 impl, not 1077), BECAUSE
THE FOUR DEFS STAYED IN THE PORT.

### 2.3 THE SUBSTITUTION-TABLE CORRECTIONS -- **THREE REAL 1:1 DEFECTS FOUND**

**THE BRIEF ASKED FOR EXACTLY THIS** -- "LOOK FOR SUBSTITUTION TABLES IN YOUR
TWO FILES AND CHECK EACH AGAINST UPSTREAM AT THE PIN" -- **AND THE PORT HAD
THREE.**

---

#### DEFECT 1 -- `is_disk` DROPPED THE `"NVME"` ARM

| | |
|---|---|
| **UPSTREAM** | `tinygrad/device.py:71-72`: `return any(d.split(":", 1)[0].upper() in ("DISK", "NVME") for d in to_tuple(device))` |
| **THE PORT** | `tinybendygrad/device.bend`: `def is_disk(ixs: List<&2, String>) -> Bool:` -- `String.eq(String.to_upper(head(k)), "DISK")` |
| **THE PORT's OWN COMMENT** | MISQUOTED UPSTREAM: it said `any(d.split(":", 1)[0].upper() == "DISK")` -- **ONE** NAME, WHERE UPSTREAM HAS **TWO** |

**MEASURED AGAINST CPython'S OWN FUNCTION, 2026-11-10:**

```
is_disk_device(("DISK:0",)) -> True
is_disk_device(("NVME:0",)) -> True    <-- THE PORT ANSWERED False
is_disk_device(("nvme:0",)) -> True    <-- UPPER-CASED, SO ALSO True
```

**AND `NVME` IS NOT HYPOTHETICAL.** `tinygrad/runtime/ops_nvme.py` EXISTS AT THE
PIN, DEFINES `NVMEDevice`, AND **THE PORT PORTS THAT FILE** AS
`tinybendygrad/runtime/ops_nvme.bend` -- SO THE PORT HAS THE DEVICE AND
`is_disk` DID NOT RECOGNISE IT. `uop/spec.py:178` READS
`not is_disk_device(copy.arg)` AND `uop/ops.py:724` READS
`is_disk_device(device)`, SO A WRONG ANSWER HERE IS A WRONG SPEC AND A WRONG
`on_disk`.

**THE FIX** -- `is_disk_head` AND THE COMMENT THAT RECORDS WHY:

```bend
def is_disk_head(+h: String) -> Bool:
  Bool.or(String.eq(h, "DISK"), String.eq(h, "NVME"))
```

**AND THREE NEW ROWS** -- `disk_nvme`, `disk_nvme_lower`, `disk_nvme_mixed` --
BECAUSE **A SINGLE ROW CANNOT SEE BOTH A DROPPED NAME AND A DROPPED CASE FOLD.**

---

#### DEFECT 2 -- `registry()` HAD NO `nvme` ROW

| | |
|---|---|
| **UPSTREAM** | `tinygrad/device.py:34-37`, `get_class`: `importlib.import_module(f'{base}.runtime.ops_{x}')` then `[cls for cname, cls in getmembers(m) if cname.lower() == x + "device"][0]`, with `x = ix.split(":")[0].lower()` |
| **THE PORT** | `tinybendygrad/device.bend`'s `registry()` -- SIXTEEN ROWS, **NO `nvme`** |

**MEASURED AGAINST UPSTREAM'S OWN REFLECTION SCAN, 2026-11-10:**

```
upstream get_class('nvme') -> NVMEDevice
```

**SO UPSTREAM'S `Device['NVME:0']` OPENS AND THE PORT's DID NOT.**

**THE FIX** -- A `DEnt{17, "nvme", "NVMEDevice"}` ROW, AT **17** AND NOT AT 13,
BECAUSE **`tag_of` HARD-CODES THE INDICES 6 (DISK), 10 (NPY) AND 13 (PYTHON)**
AND `DEnt.ix` IS THE ROW's OWN INDEX, SO A ROW INSERTED IN THE MIDDLE WOULD
MOVE THEM. **`gates/devtag-gate.py` READS THOSE THREE TAGS OUT OF `tag_of` AND
IS THE WITNESS THAT THEY DID NOT MOVE** -- AND IT STILL PASSES:

```
tag_of_named_n=3
tag_of_arms=DISK,NPY,PYTHON
tag_of_tags=6,10,13
devtag-gate: PASS -- two claims, no bend lane, no row of its own
```

**AND TWO NEW ROWS** -- `dcls_nvme` AND `dcls_nvme_lower`, BOTH ANSWERING **17**.

---

#### DEFECT 3 -- `stems()` SPENT `NVME`'s SLOT ON THE PORT's OWN `BEND`

| | |
|---|---|
| **UPSTREAM** | `tinygrad/device.py:23`, `_Device.__init__`: `self._devices = [x.stem[len("ops_"):].upper() for x in (pathlib.Path(__file__).parent/"runtime").iterdir() if x.stem.startswith("ops_")]` |
| **THE PORT** | `tinybendygrad/device.bend`'s `stems()` -- SIXTEEN ENTRIES, WITH `BEND` WHERE `NVME` BELONGS |

**MEASURED AGAINST UPSTREAM'S OWN WALK, 2026-11-10:**

```
upstream stem count: 16
['AMD','CL','CPU','CUDA','DISK','DSP','HIP','METAL','NPY','NULL','NV','NVME','PYTHON','QCOM','RDMA','WEBGPU']
```

**AND THE PORT's OWN `stems()` HAD SIXTEEN TOO -- WITH `NVME` MISSING AND
`BEND` IN ITS PLACE.** `BEND` IS THE PORT's OWN DEVICE AND IT IS **RIGHT** AND IT
STAYS -- **IT IS THE SEVENTEENTH ROW** -- BUT `NVME` IS UPSTREAM'S SIXTEENTH AND
IT WAS ABSENT.

**THE FIX** -- `AEnt{13, "NVME"}` AND EVERY EXISTING SLOT **MOVED UP BY ONE**,
WITH `NVME` AT 13 AND `WEBGPU` AT 17. **AND THE INDICES HERE ARE THE **BITMASK
SLOTS** -- `go_dep` READS `bit(m, AEnt.ix(k))` -- SO THEY ARE A DIFFERENT KIND
OF INDEX FROM `registry()`'s, AND THE TWO TABLES' INDEX SPACES ARE
INDEPENDENT.**

**THE COUNT THAT COULD NOT SEE IT: `stem_len=16` AND `reg_len=16` BOTH READ
CORRECTLY, SO **NO COUNT COULD SEE THE MISSING ROW** -- A COUNT IS NOT A TABLE.**

---

### 2.4 THE MUTATION TABLE -- MEASURED, NOT ASSERTED

`gates/device-gate.bend`'s MUTATION TABLE claims three new rows. **A TABLE ROW
NOBODY MEASURED IS A LABEL**, SO
`.agents/slop/helpers-device-shrink/nvme-mutate.py` MEASURES THEM -- **AND THE
MEASUREMENT CORRECTED THE TABLE ONCE:**

| mutation | rows moved | how many |
|---|---|---|
| `is_disk_device` drops the `"NVME"` arm of `("DISK", "NVME")` | `disk_nvme`, `disk_nvme_lower`, `disk_nvme_mixed` | 3 |
| `registry` loses the `nvme` row | `reg_len`, `dcls_nvme`, `dcls_nvme_lower` | 3 |
| `stems` loses the `NVME` row | `stem_len` | **1** |

**THE THIRD ROW'S CLAIM WAS WRONG WHEN WRITTEN** -- IT SAID `stem_len` **AND**
`dcls_nvme` **AND** `dcls_nvme_lower`, AND IT MOVES **`stem_len` ALONE** --
BECAUSE **`dcls` READS `registry()` AND NOT `stems()`, SO THE TWO TABLES ARE
SEPARATE CLAIMS.** THE TABLE NOW SAYS WHAT WAS MEASURED.

---

### 2.5 `helpers.bend`: A NEW DIFFERENTIAL GATE FOR THE DEFS NO GATE COVERED

**THE MEASUREMENT THAT JUSTIFIED IT.** THE THREE EXISTING GATES COVER:

| gate | rows |
|---|---|
| `.agents/slop/helpers-tc-gate.sh` | 237 shared rows, 3 lanes identical |
| `gates/i64-shl-gate.py` | 151 rows, 3 lanes identical |
| `gates/i64-shr-gate.py` | 301 rows, 3 lanes identical |

**AND NONE OF THEM COVERS `i64_mul`, `gcd`, `u64_divmod`, `i64_abs`, `i64_not`,
`i64_neg`, `cdiv_i64`, `cmod_i64`, `floordiv_i32`, `floormod_i32`, `cdiv_i32`,
`cmod_i32`, `ceildiv_i32`, `round_up_i32`, `round_down_i32` OR `next_power2`.**

**SO `.agents/slop/helpers-device-shrink/helpers-gap-gate.sh` FILLS THAT GAP** --
A BEND DRIVER AND A CPYTHON ORACLE, DIFFED:

```
helpers-gap-gate: 95 shared rows, the port and CPython agree
```

**AND EVERY EXPECTATION IS CPython's OWN ARITHMETIC OR CPython's OWN
`math.gcd`** -- **AND THE 64-BIT ROWS COMPARE AGAINST CPython's UNBOUNDED
INTEGERS TAKEN MODULO 2**64**, BECAUSE THE PORT's PAIR IS 64 BITS WIDE AND THE
WRAP IS THE WIDTH RATHER THAN A CHOICE. **NO ROW IS TYPED FROM MEMORY.**

**THE RESULT: `helpers.bend`'s ARITHMETIC HAS **NO** SUBSTITUTION DEFECTS.**
**95 ROWS, THE PORT AND CPython AGREE, BYTE FOR BYTE.**

**AND THE ROWS GO RED.** `.agents/slop/helpers-device-shrink/helpers-gap-mutate.py`
MUTATES THE PORT IN A SCRATCH COPY **OUTSIDE `tinybendygrad/`** -- SO A MUTATION
NEVER MOVES THE SUBSTRATE DIGEST's POPULATION -- AND ASKS WHETHER THE GATE
GOES RED:

| mutation | rows moved | how many |
|---|---|---|
| `i64_mul` negates on the wrong sign | `cmod_neg7_neg2`, `mul_neg1_neg1` | 2 |
| `gcd` steps with the SIGNED division instead of the unsigned one | `gcd_neg_neg`, `gcd_neg_pos` | 2 |
| `u64_divmod`'s zero-divisor arm answers 0 instead of the dividend | `udm_100_0_r`, `udm_min_0_r` | 2 |
| `floordiv_i32` steps DOWN on the wrong sign | `ceil_7_2`, `fdiv_7_neg2`, `fdiv_neg7_2`, `fmod_7_neg2`, `fmod_neg7_neg2`, `rdown_8_2` | 6 |
| `cdiv_i32` stops negating on a sign mismatch | `cdiv32_7_neg2`, `cdiv32_neg7_2`, `cmod32_7_neg2`, `cmod32_neg7_neg2` | 4 |
| `next_power2`'s comparison is off by one | `np2_2` | 1 |

**EVERY MUTATION MOVES AT LEAST ONE ROW. NO ROW IS A LABEL.**

**AND THE MEASUREMENT FOUND **TWO FIXTURE GAPS** THAT THE FIRST DRAFT OF THE
GATE HAD** -- AND THE FIXTURES WERE BUILT RATHER THAN THE MUTATION DROPPED:

1. **`gcd_min_min` AND `gcd_min_2` CANNOT SEE THE SIGNED/UNSIGNED SPLIT** --
   BOTH HAVE REMAINDER 0 UNDER EITHER SPELLING. `gcd_min_3` WAS ADDED, AND IT
   CAN: THE MAGNITUDE OF int64.min IS 2**63, AND 2**63 % 3 IS 2 WHILE THE
   SIGNED REMAINDER IS -2.
2. **NO ROW EXERCISED `u64_divmod`'s ZERO DIVISOR AT ALL** -- AND A ROW THAT
   SAYS "THE ZERO DIVISOR ANSWERS ZERO" IS A ROW THAT CANNOT SEE THE ARM. THE
   ROWS `udm_100_0_r` AND `udm_min_0_r` WERE ADDED, AND **THE DIVIDEND IS
   NON-ZERO** SO THE ROW IS THE ARM.

---

## 3. THE COMPILE OUTPUTS, BEFORE AND AFTER

`./bin/bend <file> --check-only`:

| file | BEFORE | AFTER |
|---|---|---|
| `tinybendygrad/device.bend` | `ALL PROOFS CHECK` | `ALL PROOFS CHECK` |
| `tinybendygrad/helpers.bend` | `ALL PROOFS CHECK` | `ALL PROOFS CHECK` |
| `gates/device-gate.bend` | (did not exist) | `ALL PROOFS CHECK` |
| `.agents/slop/helpers-device-shrink/helpers-gap.bend` | (did not exist) | `ALL PROOFS CHECK` |

**AND EVERY IMPORTER OF `device.bend` STILL COMPILES** -- **ELEVEN PORT FILES**
(`ops_amd`, `ops_cpu`, `ops_dsp`, `ops_metal`, `ops_npy`, `ops_null`, `ops_nv`,
`ops_disk`, `ops_rdma`, `support/hcq2`, `support/nv/ip`) **AND SEVEN GATE
DRIVERS** (`ops_metal`, `ops_dsp`, `ops_disk`, `ops_rdma`, `ops_amd`, `hcq2`,
`ops_cpu`).

**AND THE TWO THAT DO NOT SAY `ALL PROOFS CHECK` ARE THE PRE-EXISTING FOREIGN-C
EFFECTS** -- `ops_cpu.bend` AND `ops_null.bend` ANSWER
`Error: 2 defs rely on unsafe or foreign code: defs that depend on foreign
effects: Cpu.compile, Cpu.exec` -- **AND THAT WAS MEASURED **ON THE PRE-CHANGE
TREE** AND IS IDENTICAL.**

---

## 4. THE GATES THAT WERE RUN, AND WHAT THEY SAID

| gate | verdict |
|---|---|
| `.agents/slop/helpers-tc-gate.sh` | `237 shared rows, 3 lanes identical` |
| `.agents/slop/helpers-device-shrink/helpers-gap-gate.sh` | `95 shared rows, the port and CPython agree` |
| `gates/i64-shl-gate.py` | `151 rows, 3 lanes identical` |
| `gates/i64-shr-gate.py` | `301 rows, 3 lanes identical` |
| `gates/devtag-gate.py` | `PASS -- two claims, no bend lane, no row of its own` |
| `gates/device-gate.bend --check-only` | `ALL PROOFS CHECK` |
| `tinybendygrad/device.bend --check-only` | `ALL PROOFS CHECK` |
| `tinybendygrad/helpers.bend --check-only` | `ALL PROOFS CHECK` |

**AND THE `device.bend` ROWS AGAINST CPYTHON'S OWN `is_disk_device`:**

```
is_disk_device(("NVME:0",)) -> True
is_disk_device(("nvme:0",)) -> True
is_disk_device(("CPU:1","NVME:0")) -> True
```

---

## 5. WHAT WAS **NOT** DONE, AND WHY -- THE HONEST PART

### 5.1 `helpers.bend`'s 1,397 CODE LINES WERE NOT REDUCED

**AND THE REASON IS MEASURED, NOT GUESSED.**

- **THE CODE IS 392 DEFS AND THE LARGEST DEF IS 19 CODE LINES.** THE DISTRIBUTION
  IS FLAT: THE TOP FORTY DEFS HOLD 400 OF THE 1,002 CODE LINES **INSIDE** DEFS,
  AND EVERY OTHER LINE IS A TYPE DECLARATION OR A SIGNATURE. **THERE IS NO
  HOTSPOT.**
- **THE ONLY PAIR OF DEFS WITH **IDENTICAL** BODIES IS `floordiv_u32` AND
  `cdiv_u32`** -- AND THOSE ARE **DIFFERENT UPSTREAM NAMES** (`helpers.py:74` and
  `:77`), SO BOTH MUST EXIST.
- **THE PROSE IS ALREADY IN THE TREE's HOUSE STYLE.** `helpers.bend`'s COMMENT
  LINES AVERAGE **67.2 CHARACTERS**, AND THE OTHER PORT FILES AVERAGE **64.3** to
  **73.3** (`mixin/elementwise.bend` 73.3, `uop/ops.bend` 67.7, `dtype.bend` 64.3,
  `schedule/memory.bend` 69.9). **REFLOWING TO A WIDER LINE WOULD BREAK THE
  TREE's OWN STYLE, NOT FOLLOW IT.**
- **THE PROSE IS NOT DUPLICATED.** OF 1,467 COMMENT LINES, **1,281 ARE DISTINCT**,
  AND THE ONLY LINE REPEATED 73 TIMES IS THE `# ===` SEPARATOR. A SHINGLE SCAN
  OVER 6-GRAMS FOUND **16 NEAR-DUPLICATE PAIRS**, AND EVERY ONE OF THEM IS **A
  DIFFERENT DEF EXPLAINING ITS OWN SHAPE** -- e.g. `i64_shl` AND `i64_shr` BOTH
  SAY "k == 0 and k == 32 are the two amounts where the two forms meet", AND
  **THEY ARE TWO DIFFERENT SHIFTS WITH TWO DIFFERENT EXPLANATIONS**; DELETING
  EITHER LOSES A LOAD-BEARING ONE.
- **`.agents/slop/loc/prune-comments.py --report` FINDS **2** REMOVABLE LINES**
  IN THE WHOLE OF `helpers.bend`, **AND BOTH ARE FALSE POSITIVES** (THEY ARE
  "THE ONE VALUE THEY EXISTED FOR IS NOW THE ONE VALUE THAT WORKS", WHICH IS A
  MEASUREMENT IN DISGUISE).

**SO THE HONEST ANSWER IS: `helpers.bend`'s CODE AND PROSE ARE BOTH
LOAD-BEARING, AND SHRINKING IT FURTHER WOULD COST A CITATION OR A MEASUREMENT.
**WHAT LANDED INSTEAD IS THE **NEW GATE** FOR ITS **MOST RISKY** BLOCKS -- WHICH
IS THE 1:1 TASK DONE PROPERLY, EVEN THOUGH IT IS NOT A LINE-COUNT WIN.

### 5.2 THE PHASE-P6 ITEMS NAMED IN `helpers.bend`'s "NOT PORTED" BLOCK

THE BLOCK NAMES THREE. **THE VERDICT ON EACH:**

| item | verdict |
|---|---|
| **THE ContextVar VARIABLE LIST** | **NOT WORTH DOING NOW, AND THE FILE SAYS WHY.** THE COUNT IS **MEASURED**: UPSTREAM DECLARES **61** `ContextVar`s AND THE PORT's `Flags` IMPLEMENTS **3** PLUS `SUM_DTYPE` (A BARE `getenv`, NOT A ContextVar). **EVERY ONE OF THE OTHER 57 IS CONSUMED** -- `DEBUG` HAS 119 READS AND THE LOWEST IS `HCQ_CACHE_THRESH` WITH 1. **AND THE MECHANISM IS ALREADY PORTED**: `Context.__enter__` SNAPSHOTS NAMED KEYS AND `Context.__exit__` WRITES THEM BACK, SO P6 IS **A WIDER `Flags` AND A WIDER `Flags.snap1.go` DISPATCH**, NOT A NEW MECHANISM. **DOING IT WOULD ADD ~57 FIELDS TO A RECORD EVERY READER PASSES BY VALUE, FOR AN EXERCISE THAT THE TREE's OWN MEASUREMENT SAYS IS DEFERRED.** |
| **`Target.parse`** | **ALREADY PORTED.** `helpers.bend` HAS THE `Target` RECORD AND THE `Target.parse` DEV STRING PARSER, WITH SIX NAMED FACTS AND A MEASURED COMPARISON AGAINST CPython's OWN `Target.parse`. **THE BLOCK SAYS SO ITSELF**: "`Target` and `Target.parse` are PORTED ABOVE". **WHAT IS STILL P6 IS THE DEV ContextVar ITSELF, WHICH IS WHAT A `Target` POINTS AT** -- AND THAT IS THE SAME ITEM AS THE ROW ABOVE. |
| **`classproperty`** | **NOT WORTH DOING, AND IT IS NOT PORTABLE.** IT IS A DESCRIPTOR: IT MAKES AN ATTRIBUTE READ AS A FUNCTION. **BEND HAS NO DESCRIPTORS, NO CLASS OF METHODS AND NO `getattr`, AND EVERY PORTED DEF HERE IS A TOP-LEVEL FUNCTION, SO THERE IS NOTHING FOR IT TO ATTACH TO.** THE FILE SAYS EXACTLY THIS. **PORTING IT WOULD BE INVENTING A MECHANISM THE LANGUAGE DOES NOT HAVE.** |

**SO: ALL THREE ARE EITHER ALREADY DONE OR EXPLICITLY DEFERRED WITH A MEASURED
REASON, AND NONE OF THEM IS A LINE-COUNT WIN.**

### 5.3 A PRE-EXISTING DEFECT FOUND AND REPORTED, NOT FIXED

**`.agents/slop/linkbuf/oracle.py` IS STALE AGAINST THE CURRENT VENDORED
UPSTREAM**, AND IT IS **NOT** THIS UNIT's BREAKING:

```
TypeError: LinkCtx.__init__() got an unexpected keyword argument 'use_rt'
```

**MEASURED.** THE ORACLE'S HEADER PINS UPSTREAM `5c2bf39d6c4b`, AND THE
RE-VENDOR COMMIT `75955a97a` MOVED THE TREE'S `tinygrad/` FROM `5c2bf39d6c4b` TO
`f5ac54685` -- **223 COMMITS** -- **AND UPSTREAM DROPPED `use_rt` FROM
`LinkCtx`**:

```
f5ac54685074: class LinkCtx: inputs:list[UOp]; refs:list[UOp] = field(default_factory=list)
5c2bf39d6c4b: class LinkCtx: inputs:list[UOp]; use_rt:bool; refs:list[UOp] = field(default_factory=list)
```

**SO THE ORACLE'S CALL `LinkCtx(inputs=[], use_rt=False, refs=[])` CANNOT RUN.**
**IT IS THE RE-VENDOR's LEFTOVER AND IT IS NOT A ROW THIS UNIT'S WORK BROKE.**
**IT IS REPORTED HERE AND NOT FIXED HERE** -- FIXING IT MEANS RE-POINTING THE
ORACLE AT THE PIN's CONSTRUCT, WHICH IS A SEPARATE UNIT WITH ITS OWN ORACLE.

**AND TWO MORE, SAME CLASS, SAME CAUSE:** `helpers.bend`'s HEADER CITES
`.agents/slop/helpers-i64-mutate.sh` AND `.agents/slop/helpers-i64-mutations.txt`,
**AND NEITHER FILE EXISTS** (the i64 work MOVED to `.agents/slop/i64div/`,
`.agents/slop/i64mul/` AND `.agents/slop/i64shl/`) -- **AND THE `i64div` GATE's
OWN GENERATOR `gen_gate.py` AND THE `i64mul` CENSUS's OWN `expected.txt` ARE
MISSING.** **THREE GATES NAMING AN INPUT THAT IS GONE.** THAT IS THE CLASS
`AGENTS.md` RECORDS: "A PATH INSIDE A SWEPT TREE IS DELETABLE WHILE THE GATE
STILL NAMES IT".

---

## 6. THE FILES THIS UNIT LANDED

| path | what |
|---|---|
| `tinybendygrad/device.bend` | **-665 lines.** THE GATE ROWS AND THEIR FIXTURES MOVED OUT; THE `NVME` CORRECTIONS IN `is_disk`, `registry()` AND `stems()`. |
| `gates/device-gate.bend` | **THE GATE DRIVER** -- 791 lines, 129 ROWS, BYTE-IDENTICAL TO THE ROWS THE PORT PRINTED. |
| `.agents/slop/loc/extract-gate-rows.py` | **THE TOOL FIX** -- `external_users()` NO LONGER EXCLUDES EVERY `gates/` DRIVER, ONLY THE ONE THE TOOL WRITES. |
| `.agents/slop/helpers-device-shrink/helpers-gap.bend` | **THE NEW GATE's DRIVER** -- 95 ROWS OVER THE DEFS NO GATE COVERED. |
| `.agents/slop/helpers-device-shrink/helpers-gap-oracle.py` | **THE CPYTHON ORACLE** FOR THOSE ROWS. |
| `.agents/slop/helpers-device-shrink/helpers-gap-gate.sh` | **THE GATE** -- TWO LANES AND A DIFF. |
| `.agents/slop/helpers-device-shrink/helpers-gap-mutate.py` | **THE MUTATION TABLE** -- PROVES THE 95 ROWS GO RED. |
| `.agents/slop/helpers-device-shrink/nvme-mutate.py` | **THE THREE NEW MUTATIONS** -- PROVES THE FIVE NEW ROWS GO RED. |
| `.agents/slop/helpers-device-shrink/REPORT.md` | **THIS FILE.** |
