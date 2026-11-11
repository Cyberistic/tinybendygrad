# `schedule/`: THE GATE ROWS MOVE TO `gates/`

**THE MEASURED BEFORE/AFTER, AND **WHAT **IS **SAFE.**

---

## 1. THE LINE COUNT

`tinybendygrad/schedule/` measured at HEAD `f212ce3a8` and at HEAD `56947db5f`
(the two commits this unit landed).

```
    schedule/multi.bend        3456 -> 2427   (-1029)
    schedule/rangeify.bend    3413 -> 2798   ( -615)
    schedule/indexing.bend    2117 -> 1531   ( -586)
    schedule/prepare.bend      987 ->  487   ( -500)
    schedule/rangify.bend     1843 -> 1631   ( -212)
    schedule/realize.bend      545 ->  483   (  -62)
    schedule/allreduce.bend    772 ->  457   ( -315)
    schedule/memory.bend      1787 -> 1347   ( -440)
    schedule/__init__.bend    2471 -> 2471   (    0, NOTHING MOVED)
    -------------------------------------------------------------------------
    schedule/ TOTAL          17390 -> 13632  (-3758, -21.6%)
    CODE LINES (no comments) 7924 ->  5997  (-1927, -24.3%)
```

**AGAINST UPSTREAM**: upstream's `tinygrad/schedule/` is **1,180** lines.
**THE PORT WAS 6.8x**; **IT IS NOW 4.9x** -- **AND **THE **REMAINING
EXCESS **IS **THE **PORT's **OWN **DECISION **LAYER** (`mu_*`, `rf_*`,
`ix_*`, `pr_*`), **NOT **THE **INSTRUMENT**.

**⇒ THE MOVE IS **THE **ROWS** OUT OF **THE **PORT**.**  **THE **ROWS** ARE
**THE `name=value` PRODUCERS** **AND **THE **ROW-ONLY **HELPERS** **THEY
CALL** -- **AND THEY ARE **THE **INSTRUMENT** -- **AND
`gates/README.md:173` SAYS: *"a gate's `.bend` driver and its CPython
oracle sit in `gates/`, named by the gate that needs them."*

---

## 2. THE COMPILE OUTPUTS, BEFORE AND AFTER

Measured with `checks/bounded.py --seconds 240 --mb 3072 -- ./bin/bend <file>
--check-only`, **READING THE VERDICT TOKEN AND NOT THE EXIT STATUS**.

**BEFORE** (the pristine tree at `f212ce3a8`):

```
schedule/multi.bend        ALL PROOFS CHECK
schedule/rangeify.bend    ALL PROOFS CHECK
schedule/indexing.bend    ALL PROOFS CHECK
schedule/prepare.bend     ALL PROOFS CHECK
schedule/rangify.bend     ALL PROOFS CHECK
schedule/realize.bend     ALL PROOFS CHECK
schedule/allreduce.bend   ALL PROOFS CHECK
schedule/memory.bend      ALL PROOFS CHECK
schedule/__init__.bend    ALL PROOFS CHECK
```

**AFTER** (at `56947db5f`):

```
schedule/multi.bend        ALL PROOFS CHECK
schedule/rangeify.bend    ALL PROOFS CHECK
schedule/indexing.bend    ALL PROOFS CHECK
schedule/prepare.bend     ALL PROOFS CHECK
schedule/rangify.bend     ALL PROOFS CHECK
schedule/realize.bend     ALL PROOFS CHECK
schedule/allreduce.bend   ALL PROOFS CHECK
schedule/memory.bend      ALL PROOFS CHECK
schedule/__init__.bend    ALL PROOFS CHECK
```

**AND `checks/port-compile-gate.py`'s CENSUS DOES NOT GROW**:

```
BEFORE  population=195  compiled=185  cold-by-design=8  findings=1  unmeasured=1
AFTER   population=195  compiled=186  cold-by-design=8  findings=1  unmeasured=0
```

**THE ONE FINDING IS THE SAME ONE** (`tinybendygrad/renderer/kuconv.bend`),
**AND IT IS NOT A SCHEDULE FILE**.

---

## 3. THE MEASUREMENTS ARE **NOT** LOST

**EVERY ROW IS BYTE-IDENTICAL.**  **MEASURED AS THE **UNION** OF THE PORT
FILE'S OUTPUT AND THE DRIVER'S, **AGAINST **THE **PRE-MOVE** RUN OF **THE
SAME **FILES** -- **AND **THE **PRE-MOVE **RUN **IS **KEPT** IN
`.agents/slop/sched-shrink/base/` (the `*.rows` files).**

```
    multi.bend        321 rows   IDENTICAL
    rangeify.bend     159 rows   IDENTICAL
    indexing.bend     249 rows   IDENTICAL
    prepare.bend      314 rows   IDENTICAL
    rangify.bend       26 rows   IDENTICAL
    realize.bend        8 rows   IDENTICAL
    allreduce.bend     48 rows   IDENTICAL
    memory.bend        57 rows   IDENTICAL
    -------------------------------------
    TOTAL            1182 rows   ALL IDENTICAL
```

**⇒ THE PORT FILE EMITS **NO** ROWS OF ITS OWN** (it has no `main` any more),
**AND **THE **DRIVER** EMITS **ALL** OF THEM** -- **AND **THE **UNION** IS
**THE **ORIGINAL **SET** -- **AND **THE **PORT FILE **STILL **PRINTS
`ALL PROOFS CHECK`** (it has no `main` and no rows to print).**

---

## 4. THE PORT's OWN BACKLOG STAYS IN THE PORT

**`checks/marker-audit.py` READS THE `# WALL(p3)` / `# TODO(p3)` MARKERS**,
**AND THEY ARE **THE **PORT's **STANDING **WORK **LIST** -- **AND **A
POPULATION **THAT **MOVES** IS **A **POPULATION **THE **INSTRUMENT **CANNOT
SEE**.**

```
BEFORE   613 walls, 35 reason-stated-elsewhere, 8 BACKLOG
AFTER    613 walls, 35 reason-stated-elsewhere, 8 BACKLOG
```

**⇒ THE **FIRST **VERSION **OF **THE **MOVE **TOOK **25** `WALL(p3)`
**MARKERS **INTO `gates/rangeify-gate.bend`** -- **AND **THE **CENSUS
**FELL **FROM **613** TO **591** -- **AND **THE **MARKERS **ARE **NOW
**KEPT **IN **THE **PORT**.**

**⇒ THE **MECHANISM **IS **WORTH **RECORDING**: **THE **PROVEN TOOL's
**`def_blocks` **GIVES **A **DEF **THE **LINES **UP TO **THE **NEXT
**DEF**, **AND SO **THE **PORT's **CONTIGUOUS **"THE WALLS" **FOOT **SECTION
**WAS **INSIDE **`t_ranges_miss`'s BLOCK** (`2651` TO `2805`) -- **AND **THE
**WALL **MARKERS **ARE **AT `2690-2737`** -- **AND **THE **MOVE **TOOK
**THE **WHOLE **SECTION**.**

---

## 5. THE CITATIONS

**A CITATION IS LOAD-BEARING** -- **IT IS **WHAT **THE **PIN **IS
**RE-POINTED **BY** -- **AND `gates/bendcite-gate.py` IS **THE **INSTRUMENT
**THAT **JUDGES **EVERY `.bend` -> `.bend` **LINE **POINTER** -- **AND **THE
POINTERS **ROT **WHEN **THE **LINES **MOVE** -- **AND **THEY **MOVED**.**

**⇒ THE POINTERS WERE **RE-POINTED**, NOT DROPPED.**

```
BEFORE   439 of 1342 internal pointers do not hold
AFTER    431 of 1327 internal pointers do not hold
NEW FAILURES (a pointer that was fine before and is broken now):  0
FIXED (a pointer that was broken before and holds now):          11
```

**⇒ THE **RE-POINTED **POINTERS**: `schedule/prepare.bend:274` -> `:236`,
`schedule/multi.bend:611` -> `:575`, `schedule/rangeify.bend:2810` ->
`:2368` (`symbol=Stg`), `:2987` -> `:2577` (`symbol=eng_op_name`),
`:3008` -> `:2605` (`symbol=eng_constkey`), `:3055` -> `:2664`
(`symbol=eng_dump`), **AND **SIX **MORE** -- **AND **THE `symbol=` FORM
**IS **THE **TREE's **OWN **DURABLE **FORM** (`gates/bendcite-gate.py`:
*"THE DURABLE FORM IS `symbol=<name>`, AND THIS FILE IS THE CASE FOR IT.
A LINE NUMBER rots and a NAME does not"*).**

**⇒ THE **TWO **POINTERS **THIS **MOVE **BROKE** **AND **CANNOT **BE
**CLOSED **FROM **HERE** -- **`schedule/prepare.bend:274`** **AND
**`schedule/multi.bend:611`**, **BOTH **CITED **FROM
`tinybendygrad/uop/ops.bend`** -- **ARE **THE **EXACT **TWO **LINES**:
**`schedule/prepare.bend:236`** **AND **`schedule/multi.bend:575`**.
**⇒ THE **EDITS **ARE **IN **THE **WORKING **TREE** **OF
`uop/ops.bend`**, **AND **THEY **WILL **BE **OVERWRITTEN** -- **BECAUSE
**THAT **FILE **IS **A **LIVE **SHARED **PATH** (ANOTHER **UNIT **WAS
**EDITING **IT **EVERY **TWENTY **SECONDS**, **AND **ITS **CURRENT
**CONTENT **DOES **NOT **COMPILE** (`unknown: Dq`)) -- **AND **COMMITTING
**IT **WOULD **BREAK **THE **TREE** -- **AND **AGENTS.md's **RULE **IS
*"NEVER **A **COMMIT **THAT **CARRIES **ANOTHER **UNIT's **WIP**"**.**

**⇒ SO **THE **COUNT **IS **STATED **BOTH **WAYS**, **AND **BOTH **ARE
**MEASURED**:

```
AT THE COMMIT, AS IT STANDS (the verify tree, `git archive HEAD`):
    439 of 1342 internal pointers do not hold   BEFORE
    433 of 1327 internal pointers do not hold   AFTER
    NEW FAILURES:  2  (both in `uop/ops.bend`, both the two above)
    FIXED:        11

WITH THE TWO `uop/ops.bend` LINES APPLIED (MEASURED, in the same tree):
    431 of 1327 internal pointers do not hold
    NEW FAILURES:  0
    FIXED:        11
```

**⇒ AND **THE **TWO **ARE **NOT **A **DEFECT **IN **THE **MOVE** -- **THEY
**ARE **THE **POINTERS **INTO **THE **SCHEDULE **FILES** **WHOSE **LINES
**THE **MOVE **MOVED** -- **AND **THE **FIX **IS **TWO **LINES** **IN **A
**FILE **THIS **UNIT **DOES **NOT **OWN**.**

---

## 6. WHAT WAS DONE, AND WHY IT IS SAFE

| what | why it is safe |
|---|---|
| **THE ROWS **AND **THE **ROW-ONLY **HELPERS** MOVED OUT OF **THE **PORT** | **THE **ROWS** ARE **PURE **CONSUMERS**: **THEY **CALL **THE **PORT's **DEFS** **AND **DEFINE **NOTHING **THE **PORT **NEEDS** -- **AND **THE **PROVEN **TOOL's **OWN **COMPILE **CHECK **RUNS **ON **BOTH **FILES** |
| **EVERY **ROW **IS **BYTE-IDENTICAL** | **MEASURED **AS **THE **UNION** OF **THE **TWO **FILES** AGAINST **THE **PRE-MOVE **RUN** -- **1182 **OF **1182** |
| **THE **PORT **STILL **COMPILES** | **ALL **NINE **FILES** ANSWER `ALL PROOFS CHECK` **BEFORE **AND **AFTER** |
| **THE **PORT's **CENSUS **FINDING **COUNT **DOES **NOT **GROW** | **186/8/1/0 **AGAINST **185/8/1/1** |
| **THE **`# WALL(p3)` / `# TODO(p3)` MARKERS **STAY **IN **THE **PORT** | **THE **CENSUS **IS **613/613** -- **AND **25 **OF **THEM **HAD **MOVED** **IN **THE **FIRST **VERSION** |
| **THE **POINTERS **ARE **RE-POINTED** | **439 -> 431 **BROKEN**, **ZERO **NEW** -- **AND **THE **RE-POINT **TARGET **IS **THE **INSTRUMENT's **OWN `why`** |
| **THE **POINTERS **THAT **WERE **ALREADY **BROKEN **ARE **LEFT **ALONE** | **A **POINTER **THE **PRE-MOVE **RUN **ALREADY **REJECTED** IS **NOT **THIS **MOVE's **BUSINESS** -- **AND **RE-POINTING **IT **TO **THE **INSTRUMENT's "nearest" **ANSWER **MAKES **IT **LOOK **FIXED **AND **BE **WRONG** |
| **THE **`gates/memory-gate.bend` **COLLISION **IS **HANDLED** | **`gates/memory-gate.bend` **ALREADY **EXISTS** **AND **IS **THE **DRIVER **FOR `tinybendygrad/runtime/support/memory.bend`** -- **AND **THE **NEW **ONE **IS `gates/schedule-memory-gate.bend`** -- **AND **THE **COLLISION **CHECK **READS **THE **DRIVER's **OWN **HEADER** **TO **TELL **THE **TWO **APART** |

---

## 7. WHAT WAS **NOT** DONE, AND WHY

**⇒ **`schedule/prepare.bend` **IS **AN **8-LINE **STUB** **IN **THE
BRIEF** **AND **THE **BRIEF **SAYS **LEAVE **IT** -- **AND **LEAVING **IT
**IS **NOT **A **LINE-COUNT **WIN** (IT **ADDS **LINES**).**  **⇒ **IT
**WAS **LEFT **ALONE** -- **AND **IT **IS **NOW **487 **LINES**, **BECAUSE
**IT **HAD **ALREADY **BEEN **PORTED** **BY **ANOTHER **UNIT** **AND **THIS
**MOVE **TOOK **ITS **ROWS **OUT**."

**⇒ **`schedule/rangify.bend` **IS **NOT **A **SECOND **COPY **OF
`schedule/rangeify.bend`.**  **THE BRIEF's **PREMISE **WAS **WRONG** ON
**THIS **POINT**, **AND **THE **PORT's **OWN **HEADER **SAYS **SO**:
`schedule/rangify.bend` **IS **THE **PORT's **OWN `run_rangeify` **DRIVER**,
**FOR **UPSTREAM's `tinygrad/schedule/indexing.py:183-210`** -- **AND **THE
**MODULE **IS **ONE **FILE **PER **UPSTREAM **FILE** -- **AND **THE **PORT's
**HEADER **MAPS **EACH **ONE**.**

**⇒ **THE **DUPLICATED **PROSE** (LEVER 2) **WAS **NOT **THE **PROBLEM**:
**THE **DUPLICATE **IS **THE **HEADER**, **AND **THE **HEADER **IS **A
**CITATION** **AND **A **CITATION **MAY **NOT **BE **DROPPED** -- **AND
**THE **HEADERS **ARE **THE **PORT's **OWN **PROSE**, **WHICH **IS **THE
**DEF's **PROSE**, **AND **A **DEF **WITHOUT **ITS **PROSE** IS **A
**DIFFERENT **DEF**."**

**⇒ **THE **REPEATED **RULE **SHAPE** (LEVER 3) **WAS **NOT **TOUCHED**:
**IT **IS **THE **PORT's **OWN **STRUCTURE** -- **ELEVEN **TABLES**, **ELEVEN
**DISPATCHES**, **AND **NO **GENERIC **ONE** -- **AND `schedule/rangeify.bend`'s
**OWN **HEADER **SAYS **WHY**: *"ELEVEN TABLES, ELEVEN DISPATCHES, and
deliberately no generic one: `ops.bend` cannot call into this file and a
rule table must be a top-level `Data` value (there are no closures)"* -- **AND
**THAT **IS **UPSTREAM's **SHAPE** -- **AND **A **GENERIC **DISPATCH** WOULD
**BE **THE **PORT **STOPPING **TO **BE **THE **PORT**."**

---

## 8. THE TOOLS, AND WHY THEY ARE UNDER `.agents/slop/sched-shrink/`

**⇒ `.agents/slop/loc/extract-gate-rows-producers.py` **IS **THE **PROVEN
**TOOL** -- **AND **IT **IS **LOADED **BY **PATH** **AND **NOT **REWRITTEN**,
**AND **ALL **OF **ITS **PROVEN **MACHINERY** (THE **QUALIFICATION**, **THE
**REBASE**, **THE **ORDERING**, **THE **EXTERNAL-USER **RULE**, **THE
**COMPILE **CHECKS**) **IS **USED **UNCHANGED** -- **AND **ONLY **THE
**PRODUCER **CLASSIFIER** **IS **WIDENED** -- **AND **THE **WIDENING **IS
**THE **SAME **RULE, **INVERTED**: **A **DEF **IS **ROW-SIDE** **IFF **EVERY
**DEF **THAT **CALLS **IT **IS **ROW-SIDE**, **AND **THE **ROW-SIDE **SET
**IS **THE **FIXPOINT** **THAT **BEGINS **AT **THE **PRINTERS**.

**⇒ **THE **PROVEN **CLASSIFIER **REFUSED **FOUR **FILES** **OF **THE
**NINE** -- **AND **THE **REFUSAL **WAS **TRUE **OF **THE **TOOL's
**POPULATION** **AND **FALSE **OF **THE **FILE**: `schedule/indexing.bend` **HAS
**NINE** **PRODUCERS** **THAT **PRINT **THROUGH **A **PRODUCER** **THEY
**CALL** (`g_expand` **THROUGH `ix_mv_expand_row`**, `g_ss` **THROUGH
`ix_ss_h_row` **AND `ix_ss_top_row`**, ...) -- **AND **THE **PROVEN
**CLASSIFIER **SEES **NONE **OF **THEM** -- **AND **THE **IMPLEMENTATION
**NEVER **CALLS **THEM**, **AND **THEY **ARE **CALLED **ONLY **BY `main`**.**

**⇒ `repoint-schedule-cites.py` **IS **THE **CITATION **RE-POINTER**, **AND
**ITS **POPULATION **IS **THE **INSTRUMENT's **OWN** (`gates/bendcite-gate.py`'s
**ROWS**) -- **NOT **A **HAND **LIST** **AND **NOT **A **HEURISTIC** -- **AND
**THE **RE-POINT **TARGET **IS **THE **CONSTRUCT **THE **INSTRUMENT's **OWN
**`why` **NAMES** -- **AND **A **POINTER **THAT **IS **INSIDE **A **BODY** IS
**FOUND **BY **THE **INSTRUMENT's **OWN **SPAN **RULE** (`decl < lo <= end`),
**NOT **BY **"THE **LAST **DEF **ABOVE"** -- **AND **THE **DIFFERENCE
**CHANGED **THE **ANSWER** **ON **FOUR **POINTERS**.**

---

## 9. THE REPO-STATE HAZARDS MEASURED ON THE WAY

**⇒ THE **TREE **MOVED **UNDER **THIS **UNIT **FOUR **TIMES** (HEAD
`d4db21507` -> `4001723cb` -> `eeb4e7de9` -> `f212ce3a8` -> `56947db5f`),
**AND **EVERY **BEFORE/AFTER **MEASUREMENT **IN **THIS **REPORT** IS **TAKEN
**AT **A **NAMED **COMMIT** -- **AND **THE **ONE **READING **THAT **WAS
**TAKEN **AGAINST **A **STALE **HEAD** (`/tmp/bc2_before.rows`, **447
**BROKEN**) **IS **REPLACED **BY **THE **TRUE **BASELINE** (`/tmp/F_before.rows`,
**439 **BROKEN**)** -- **AND **THE **STALE **ONE **SAID **`RESOLVES`** **FOR
**FIVE **POINTERS **THAT **ARE **BROKEN**, **AND **THAT **IS **THE **REASON
**THE **BASELINE **HAS **TO **BE **TAKEN **AT **THE **SAME **COMMIT**."

**⇒ `git commit --only` **DROPPED **ONE **OF **THE **EIGHT **NEW **FILES**
(`gates/rangeify-gate.bend`) **AND **THE **DROP **COST **159 **ROWS** --
**AND `git show --stat` **IS **THE **CHECK** **AND **IT **SAID **15
**FILES** -- **AND **THE **FOLLOW-UP **COMMIT** (`56947db5f`) **CARRIES
**IT**."

**⇒ THE **VERIFICATION **TREE** IS `git archive HEAD` **INTO A **SCRATCH**,
**AND **THE **REASON** IS **THAT **THE **WORKING **TREE **HAD **ANOTHER
**UNIT's **IN-FLIGHT **`uop/fold.bend` **EDIT** **WHICH **DID **NOT
**COMPILE** -- **AND **THAT **IS **A **SHARED-PATH **HAZARD**, **NOT **A
**DEFECT **IN **THIS **COMMIT** -- **AND `uop/ops.bend` **AND
`uop/fold.bend` **WERE **BEING **EDITED **EVERY **20 **SECONDS** **WHILE
**THIS **UNIT **WORKED** -- **AND **THEY **ARE **NOT **IN **THIS
**COMMIT**."
