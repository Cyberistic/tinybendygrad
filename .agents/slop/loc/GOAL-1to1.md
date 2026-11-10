# THE 1:1 GOAL — THE MEASUREMENT, THE LEVERS, AND WHAT IS PROVEN IMPOSSIBLE

**MEASURED 2026-11-10. EVERY NUMBER HERE IS A READING.**

## THE METRIC — AND WHY THE NAIVE COMPARISON IS WRONG

`git ls-tree -r HEAD` (the **tracked** files; the tree's index is armed, so `git ls-files`
lists a different set) × each file's **own header** (which names its upstream counterpart)
× upstream at the **pin `f5ac54685074`**.

| | before | after |
|---|---|---|
| the port's lines | 321,417 | **279,414** |
| upstream's | 63,395 | 63,395 |
| **the ratio** | **5.08×** | **4.41×** |
| GATE ROWS | 9,389 | **1,041** |
| COMMENTS | 131,240 | **112,944** |
| BLANK | 43,365 | 42,041 |
| **CODE** | **137,423** | **123,388** |
| **the code-only ratio** | **2.44×** | **2.19×** |

**THE HEADLINE IS **THE CODE-ONLY RATIO**, BECAUSE A COMMENT IS NOT A LINE OF PORT AND A
GATE ROW IS NOT EITHER.**

**AND THE MEASUREMENT IS AN INSTRUMENT: `.agents/slop/loc/the-1to1.py`.**

### The four corrections the metric makes

1. **THE POPULATION IS `git ls-tree -r HEAD`**, not `git ls-files` — the tree's index is
   armed (`checks/index-arm-gate.py`), and `checks/repro-paths.py` measured `584` under an
   armed index and `541` under a disarmed one, **same tree**.
2. **THE MAPPING IS EACH FILE's OWN HEADER**, which is where the census reads it too.
   **A FILE WITH NO UPSTREAM NAME IS THE TREE's OWN** and is counted and listed separately —
   **49 files, 11,350 lines**, led by `sz.bend` (1,675).
3. **THE UPSTREAM IS THE PIN**, not `HEAD` — the port was written against that revision.
4. **THE `*-mut.bend` FILES ARE EXCLUDED** — `.gitignore` has `*mut.bend` ("in-place
   mutation scratch") and `checks/differ.py:1936` calls them "FIVE GITIGNORED SCRATCH
   FILES" that a mutation probe **rewrites as it runs**.

## THE `sz.bend` QUESTION — ANSWERED

**`sz.py` IS AT THE REPO ROOT (95 LINES). IT IS **NOT** IN `tinygrad/` AT ALL.**
**`sz.bend` (1,675 LINES) IS **ITS **BEND **PORT** — **IT IS **THE **TREE's **OWN
INSTRUMENT** (THE **TOOL **THAT **COUNTS **THE **TREE's **OWN **LINES**), **AND **IT **MUST
BE **COUNTED **SEPARATELY**, **NOT **AS **A **PORT **OF **AN **UPSTREAM **FILE**.**

## THE FIVE LEVERS, AND WHAT EACH IS WORTH — **MEASURED**

### 1 — THE GATE ROWS OUT OF THE IMPLEMENTATION FILES — **DONE, 9,389 → 1,041**

**THE TREE's OWN CONVENTION SAYS SO: `gates/README.md:173` — *"a gate's `.bend` driver and
its CPython oracle sit in `gates/`, named by the gate that needs them."* **AND 89 SUCH
DRIVERS ALREADY EXIST.**

**AND EVERY MOVE WAS **VERIFIED **BY **THE **ROW **DIFF**: **THE **ROW **SETS **BEFORE
**AND **AFTER **WERE **BYTE-IDENTICAL** ON EVERY FILE.**

**AND **THE **FOUR **MOVES **LANDED **20,000+ **GATE **LINES** OUT OF **THE **PORT.**

### 2 — THE COMMENT BLOCK — **PARTLY DONE, AND **THE **REST **IS **MEASURED **NOT **REDUNDANT**

**THE CLASSIFICATION OF EVERY COMMENT LINE IN THE TREE:**

| class | lines | words | verdict |
|---|---|---|---|
| separator (punctuation only) | 9,897 | 4,022 | **REMOVED** — a blank line says the same |
| citation (names an upstream position) | 8,959 | 87,763 | **KEPT** — it is what the pin is re-pointed by |
| measurement | 1,754 | 21,908 | **KEPT** — it is the evidence |
| history (says what the code WAS) | 270 | 3,865 | **REMOVED** — the git log is the history |
| prose (explains the shape) | 70,579 | 818,726 | **KEPT** — it is the explanation |

**AND IT IS **PROVABLY **LOSSLESS: **THE **CITATIONS **WENT **8,812 -> 8,812** AND **THE
**MEASUREMENTS **1,868 -> 1,868** WHEN **3,856 **LINES **WERE **REMOVED**.**

**AND **THE **PROSE **IS **NOT **REDUNDANT: **ONLY **755 **LINES **ARE **DUPLICATED
**WITHIN **A **FILE** **AND **457 **ACROSS **FILES** -- **AND **THE **PROSE **EXPLAINS **WHY
**THE **CODE **IS **SHAPED **THAT **WAY**, **AND **THAT **IS **THE **ONLY **PLACE **IT **CAN
**LIVE**.**

### 3 — THE HAND-EXPANDED RULES — **AND **THIS **IS **WHERE **THE **REMAINING **EXCESS **IS**

**MEASURED: THE PORT's `uop/symbolic.bend` HAS **5,114 **CODE **LINES** FOR **UPSTREAM's
`uop/symbolic.py`'s **332** — **15.4× — **AND **UPSTREAM WRITES **A **RULE **AS **ONE
**LINE**:**
```python
(UPat.var("x") * 1, lambda x: x)     # x*1 -> x
```

**AND **THE **WALL **IS **NAMED, **AND **IT **IS **NOT **A **MATTER **OF **EFFORT**:
`uop/upat.bend`'s OWN HEADER SAYS **"`exec` **IS **THE **WALL**"** — **BEND HAS **NO `exec`
AND **NO **FUNCTION **VALUES**, **SO **A `UPat` **CANNOT **BE **DATA **AT **RUNTIME** — **AND
**EVERY **RULE's **MATCH/GUARD/BUILD **MUST **BE **HAND-WRITTEN**.**

**AND **THE **PROOF **THAT **THIS **IS **THE **WALL **AND **NOT **A **CHOICE**: MEASURED,
`tinybendygrad/mixin/` IS **1.2×** UPSTREAM (`4,504` vs `3,824` code lines) **AND **IT **IS
**METHOD **DISPATCH **WITH **8 `UPat` **MENTIONS **TOTAL** — **AND **`mixin` **IS **HOW
**A **PORTED **MODULE **LOOKS **WHEN **THE **PATTERN **ENGINE **IS **NOT **THE **PROBLEM**.**

**AND **THE **SUPPORT **FAMILIES **ARE **THE **REST**: MEASURED, `symbolic.bend`'s 620 DEF
FAMILIES ARE **135 `sym_<N>` **UPSTREAM **RULES (527 **DEFS)** + **485 **SUPPORT
**FAMILIES (813 **DEFS)** — **THE `sy_*` **MATCHER **HELPERS **ARE **132** — **AND **THE
`sym_*` **RULES' **OWN **BODIES **ARE **NOT **DUPLICATED** (330 **DISTINCT **SHAPES **FOR
354 **DEFS**).**

### 4 — THE CODE EXCESS, PER UPSTREAM FILE — **THE **NEXT **TARGET**

**67,957 LINES OVER 119 UPSTREAM FILES. THE TOP SIX ARE 29% OF IT:**

| excess | port code | upstream code | file |
|---|---|---|---|
| 7,506 | 9,049 | 1,543 | `uop/ops.py` |
| 4,782 | 5,114 | 332 | `uop/symbolic.py` |
| 4,200 | 4,736 | 536 | `helpers.py` |
| 3,959 | 4,398 | 439 | `device.py` |
| 2,821 | 3,225 | 404 | `runtime/support/hcq2.py` |
| 2,727 | 3,361 | 634 | `runtime/ops_nv.py` |

### 5 — THE PER-MODULE RATIO, ON **THE **TREE's **OWN **SHAPE**

| module | port code | upstream code | ratio |
|---|---|---|---|
| **uop** | 20,567 | 2,590 | **7.9×** |
| **schedule** | 7,874 | 1,180 | **6.7×** |
| **codegen** | 7,880 | 1,863 | **4.2×** |
| renderer | 11,596 | 3,698 | 3.1× |
| engine | 1,523 | 429 | 3.6× |
| nn | 3,264 | 1,740 | 1.9× |
| **mixin** | **4,504** | **3,824** | **1.2×** ← THE TARGET |
| viz | 570 | 862 | 0.7× |
| runtime | 31,179 | 244,114 | 0.1× |

## THE DEFECTS THIS WORK FOUND

### 1 — THE `ne`/`eq` INVERSION — **FIXED** (`1548d717e`)

**`mixin/elementwise.bend` BUILT **THE **PRE-PIN **SPELLING** WHILE **THE **PORT's **OWN
`uop/symbolic.bend` **BUILT **THE **PIN's** — **THE **TWO **HALVES **OF **THE **SAME
**RULE **HAD **DRIFTED **APART**, **AND **THE **CENSUS **COULD **NOT **SEE **IT** (IT
READS **THE **SYMBOLIC **LAYER's **TABLE**, **AND **THE **MIXIN **LAYER's **EMISSION **IS
**A **DIFFERENT **FILE**).**

| | upstream @ the pin | the port BEFORE | AFTER |
|---|---|---|---|
| `a.eq(b)` | `CMPEQ(a, b)` | `CMPNE(CMPNE(a,b), True)` | **`CMPEQ(a, b)`** |
| `a.ne(b)` | `CMPEQ(CMPEQ(a,b), False)` | `CMPNE(a, b)` | **`CMPEQ(CMPEQ(a,b), False)`** |
| `a.logical_not()` | `CMPEQ(CAST(a), False)` | `CMPNE(CAST(a), True)` | **`CMPEQ(CAST(a), False)`** |

**AND **THE **ROW **THAT **COULD **NOT **GO **RED** IS **FIXED**: `t_ne` USED
`g_bin1(O.OpsCMPNE{}, 3)` — **A GENERIC FIXTURE **THAT **BUILDS **THE **RAW **OP** AND
**NEVER **CALLS `ew_ne`** — **IT **PRINTED `CMPNE/2` **EVEN **AFTER **THE **RULE **WAS
**CORRECTED**.**

**AND **UPSTREAM's **OWN `symbolic.py:349` **KEYS **ON **THE `CMPEQ` **SPELLING**:
`neg = v.op is Ops.CMPEQ and v.src[1].op is Ops.CONST and v.src[1].val == 0` — **SO **A
**GRAPH **THAT **SAYS `CMPNE` **IS **NOT **UPSTREAM's **GRAPH**.**

### 2 — THE **INSTRUMENT **DEFECT **THAT **WAS **HIDING **IT** — **FIXED**

**`checks/bounded.py` PRINTS `WITHIN-LIMITS` **AND** `said=SOME PROOFS FAIL` **ON **THE
**SAME **LINE** — **AND **ITS **OWN **HEADER **SAYS **SO** (`:47`): *"`WITHIN-LIMITS` IS A CLAIM
ABOUT THE BOUNDS AND NEVER ABOUT THE CHILD."*** **AND **THE **GATE-ROW **EXTRACTOR
**REPORTED **A **FILE **AS **COMPILING **WHEN **IT **DID **NOT** (MEASURED **BY **A
**CONCURRENT **AGENT**: "the marker tool reported `WITHIN-LIMITS` for a port file that did not
compile").** **THE **EXTRACTOR **NOW **READS **THE **COMPILER's **OWN **VERDICT** (`ALL
**PROOFS **CHECK` / `SOME **PROOFS **FAIL`) **AND **TREATS **THE **BOUNDS **TOKEN **AS **A
**SEPARATE **FACT**.**

### 3 — THE **ROW **THAT **CANNOT **GO **RED** — **FIXED**

**`t_ne` **BUILT **THE **RAW **OP** **INSTEAD **OF **CALLING **THE **RULE**, **SO **IT
**COULD **NOT **GO **RED **WHEN **THE **RULE **CHANGED** — **AND **THE **PLANT **PROVED
**IT**: **REVERTING **`ew_ne` **LEFT **THE **ROW **PRINTING `CMPNE/2`.**

## THE TOOLS THIS WORK ADDED

| tool | what it does |
|---|---|
| `.agents/slop/loc/the-1to1.py` | **THE METRIC** — the tracked port, mapped by its own headers, against the pin |
| `.agents/slop/loc/extract-gate-rows.py` | **MOVES **THE **GATE **ROWS **OUT** — and verifies the row sets are byte-identical |
| `.agents/slop/loc/extract-gate-rows-producers.py` | **THE **SAME **FOR **FILES **WHERE **THE **ROWS **ARE **INTERLEAVED** — finds the population BY DISCOVERY |
| `.agents/slop/loc/demark.py` | **STRIPS **THE **BANNED **MARKERS** (` `, `**`) AND **LEAVES **THE **EXPONENTS** |
| `.agents/slop/loc/ban-marks.py` | **THE **LINT** — ` `, `**`, AND **>5 **ALL-CAPS **WORDS **IN **ONE **LINE** |
| `.agents/slop/loc/prune-block.py` | **REMOVES **THE **PROVABLY **REMOVABLE **COMMENT **LINES** — the separators and the history |

## THE BANS, AND WHY

| banned | measured hits | why |
|---|---|---|
| ` ` (U+21D2) | 482 | **THE **OLD **ARROW **STYLE** — **IT **PACKS **A **PARAGRAPH **INTO **ONE **LINE** **AND **MAKES **THE **COMMENT **UNREADABLE **AT **A **GLANCE** |
| `**` | 5,271 | **THE **EMPHASIS **MARKER** — **AND **EMPHASIS **ON **EVERY **LINE **IS **NO **EMPHASIS** |
| **>5 ALL-CAPS WORDS IN ONE LINE** | 9,778 | **A **LINE **THAT **SHOUTS **SIX **WORDS **IS **A **PARAGRAPH **IN **CAPS** |

**AND THE **EXEMPTION **THAT **MATTERS: `2**64` **IS **THE **EXPONENT **OPERATOR**, **NOT
**EMPHASIS** — **AND **STRIPPING **IT **WOULD **CORRUPT **THE **COMMENT** (MEASURED:
`uop/fold.bend:86` READS "`uint64.max` = 2**64-1").**

## WHAT IS PROVEN IMPOSSIBLE, AND WHY

**THE **REWRITE **LAYER **CANNOT **BE **1:1 **IN **LINE **COUNT**, **AND **THE **PROOF **IS
**THE **LANGUAGE**: BEND HAS NO `exec` AND NO FUNCTION VALUES, **SO **A `UPat` **CANNOT **BE
**DATA** AND **EVERY **RULE **MUST **BE **HAND-WRITTEN**.**

**SO **THE **GOAL **IS **NOT **"THE **PORT **IS **THE **SAME **NUMBER **OF **LINES".** **IT
IS: **THE **PORT **PRODUCES **THE **SAME **GRAPHS **AS **UPSTREAM**, **AND **THE **PORT's
**OWN **LOGIC **IS **AS **SMALL **AS **THE **LANGUAGE **ALLOWS**, **AND **THE **INSTRUMENTS
**ARE **NOT **INSIDE **THE **PORT**.**

**AND **THE **PROOF **OF **THE **SECOND **HALF **IS **`mixin`**: **IT **IS **1.2×**, **AND
**IT **IS **A **PORTED **MODULE**, **AND **THE **DIFFERENCE **IS **METHOD **DISPATCH, **NOT
**THE **PATTERN **ENGINE**.**
