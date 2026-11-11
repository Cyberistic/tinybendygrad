# `uop/ops.bend`: THE GATE ROWS MOVE TO `gates/ops-gate.bend`

**MEASURED 2026-11-11.**

## THE METRIC

`.venv/bin/python .agents/slop/loc/the-1to1.py`

| | BEFORE | AFTER |
|---|---|---|
| the port | 290,786 lines | **276,644 lines** |
| the ratio | 4.59x | **4.36x** |
| CODE ONLY | 125,834 vs 56,436 = 2.23x | **121,366 vs 56,436 = 2.15x** |
| COMMENTS | 123,773 | 112,357 |
| BLANK | 38,069 | 41,930 |
| GATE ROWS | 3,110 | 991 |

**THE PORT FILE ITSELF:** `tinybendygrad/uop/ops.bend` went **11,402 -> 9,199 lines**
(-2,203) and `gates/ops-gate.bend` is **3,360 lines** (new).

## WHAT WAS DONE

**THE GATE ROWS MOVED.** THE `# --- THE GATE ROWS` MARKER WAS INSERTED BEFORE THE
`row` HELPER IN `ops.bend`, AND `.agents/slop/loc/extract-gate-rows.py` DID THE
MOVE. THE TOOL'S OWN `split()` IS THE INSTRUMENT THAT DECIDES WHICH GATE-REGION
BLOCKS ARE ROW-ONLY, AND THE REBUILD USES **THE TOOL's OWN `split()`**, NOT A
SECOND POPULATION.

**THE PORT IS THE ORIGINAL MINUS THE MOVED BLOCKS, IN THE ORIGINAL ORDER.** BEND
HAS NO FORWARD REFERENCES, SO A DEF MUST BE IMPLEMENTED BEFORE IT IS USED. THE
PORT's OWN ORDER IS THE ORDER THAT COMPILED, SO THE PORT IS BUILT BY DELETING
BLOCKS AND NEVER MOVING ONE. THE REBUILD WAS **THE PORT IS THE ORIGINAL**, NOT
`impl + hoist`, BECAUSE THE SECOND SHAPE PUTS A TYPE AFTER ITS FIRST USE.

**THE PUBLIC API IS UNCHANGED.** EVERY DECLARATION IN THE ORIGINAL IS STILL
DECLARED, IN THE PORT OR IN THE DRIVER:

```
original decls: 895   port: 895   driver: 313
MISSING decls: 0
DUPLICATED in port: []
```

**THE TWELVE TYPES THE PORT OWNS STAY IN THE PORT.** `S5`, `DRng`, `CLike`,
`Ctr`, `Dv`, `Ds`, `Dq`, `PSlot`, `PInfo`, `FS`, `Sz`, `OI` LIVE BELOW THE
MARKER IN THE ORIGINAL, AND THE PORT's IMPLEMENTATION **CONSTRUCTS AND MATCHES**
THEM. A TYPE WHOSE CONSTRUCTOR THE PORT USES IS THE PORT's DATA MODEL, SO IT
STAYS, AND SO DO ITS FIELD READERS. THE DRIVER THEN USES THEM AS `P.<T>`.

**THE DRIVER DECLARES NO TYPE OF ITS OWN.** A QUALIFIED TYPE NAME IS NOT A FRESH
NAME (`expected : a fresh name (P is an import's alias)`), SO THE DRIVER USES
`P.S5`, `P.Dq`, `P.Ctr` AND SO ON INSTEAD OF DECLARING ITS OWN COPIES.

**THE DRIVER'S OWN DEFS ARE THE DRIVER's.** A DEF THE DRIVER DECLARED IS
DECLARED BARE (`def s5.dr(...)`), AND THE PORT'S COUNTERPART IS CALLED
QUALIFIED (`P.UOp.device_range_src(...)`).

## WHY IT IS SAFE

**NO ROW LOST, NO ROW CHANGED.** THE ORIGINAL `ops.bend` AND THE NEW DRIVER WERE
BOTH RUN AND THEIR OUTPUT COMPARED BYTE-FOR-BYTE:

```
orig.rows: 342 lines
drv.rows:  342 lines
diff: EMPTY
sha256 (both): 85ac93894b61f878be39f19efc381b30de1e256c81e387a3314852684e163867
```

**NO CITATION LOST.** EVERY COMMENT LINE OF THE ORIGINAL SURVIVES:

```
original comment lines: 4162   distinct: 3697
in port: 3697   in driver: 505
LOST: 0
```

**NO CODE LINE LOST.**

```
original code lines: 3537   distinct: 2828
LOST code lines: 0
```

**NO SELF-CITATION BROKE.** EVERY `ops.bend:<line>` CITATION **INSIDE** `ops.bend`
AND INSIDE THE DRIVER STILL RESOLVES TO THE SAME CONTENT, COMPARED LINE BY LINE
AGAINST THE ORIGINAL.

**NO EXTERNAL CITATION BROKE.** EVERY `ops.bend:<line>` CITATION IN EVERY `.bend`
FILE IN THE TREE STILL RESOLVES TO THE SAME CONTENT:

```
citations whose target MOVED: 0
```

**THE CITATION GATES MOVED NEITHER COUNT.** `gates/bendcite-gate.py` READS 524 OF
1317 INTERNAL POINTERS AS NOT HOLDING, AND **334** OF THEM NAME `ops.bend`, **ON
HEAD AND AFTER, IDENTICALLY**. `gates/todo-cite-gate.py` READS 435 OF 1145, ALSO
IDENTICALLY. BOTH GATES ARE **ALREADY RED ON HEAD** (`opseven-gate` AND
`replace-gate` TOO), SO THE CHANGE MOVED NO COUNT AND ADDED NO FAILURE.

**THE COMPILE CENSUS GOT BETTER, NOT WORSE.** `checks/port-compile-gate.py`:

| | HEAD | AFTER |
|---|---|---|
| FINDING | 4 | **1** |
| population | 201 | 201 |

THE ONE REMAINING FINDING IS `tinybendygrad/renderer/kuconv.bend`, AND IT IS A
`cstyle.KU` FIELD-COUNT MISMATCH THAT **FAILS IDENTICALLY WITH HEAD's
`ops.bend` IN PLACE**, SO IT IS PRE-EXISTING AND UNRELATED.

**THE CONSUMERS COMPILE.**

```
tinybendygrad/uop/ops.bend                 ALL PROOFS CHECK
gates/ops-gate.bend                        ALL PROOFS CHECK
tinybendygrad/tensor.bend                  ALL PROOFS CHECK
tinybendygrad/function.bend                ALL PROOFS CHECK
.agents/slop/graphcmp.bend                 ALL PROOFS CHECK   (the corpus's bend lane)
tinybendygrad/mixin/creation.bend          ALL PROOFS CHECK
tinybendygrad/mixin/gradient.bend          ALL PROOFS CHECK
tinybendygrad/schedule/prepare.bend        ALL PROOFS CHECK
tinybendygrad/renderer/cstyle.bend         ALL PROOFS CHECK
tinybendygrad/renderer/ptx.bend            ALL PROOFS CHECK
tinybendygrad/uop/fold.bend                ALL PROOFS CHECK
tinybendygrad/uop/movement.bend            ALL PROOFS CHECK
tinybendygrad/uop/spec.bend                ALL PROOFS CHECK
```

**THE GATES READING `ops.bend` PASS.**

```
ops-core-gate        rc=0   (44 rows, 3 lanes, all agree with CPython)
uop_cast-gate        rc=0   (8 rows, 3 lanes)
target-census-gate   rc=0
opsref-census        rc=0
opname-census-gate   rc=0
allcopies-census     rc=0
```

`opseven-gate` AND `replace-gate` ARE **REFUSED/FAIL ON HEAD TOO**, VERIFIED BY
PUTTING HEAD's `ops.bend` BACK IN PLACE AND RUNNING THEM.

## WHAT WAS **NOT** DONE

- **NO PROSE WAS DELETED.** THE PROSE IS THE EXPLANATION, AND IT WAS NOT THE
  EXCESS.
- **NO ROW WAS DELETED TO GO GREEN.** THE DRIVER PRINTS EXACTLY THE ORIGINAL's
  342 ROWS, BYTE-FOR-BYTE.
- **NO GATE WAS WEAKENED.**
- **NO HAND-EXPANDED RULE FAMILY WAS TOUCHED.** THAT IS THE NEXT LEVER.

## THE NEXT LEVER

THE PORT IS STILL **9,199 LINES** AGAINST UPSTREAM's **1,891**, SO **6,479 LINES
OF EXCESS** REMAIN AFTER THE ROWS MOVED. THE NEXT LEVER IS **THE HAND-EXPANDED
RULE FAMILIES** MEASURED IN `helpers.bend`: `name` + `name.go` + `name.of` +
`name.at`. ONE GENERAL HELPER THAT THE PER-RULE DEFS CALL IS THE MECHANISM, AND
THE PER-RULE DEFS SHRINK WITH IT. THE GATE REGION'S OWN FAMILIES ARE VISIBLE IN
THE DRIVER: `UOp.gcd.*` IS **40 DEFS**, `UOp.divide_exact.*` IS **19**, AND
`UOp.index.*` IS **9**.

## THE TOOLS

- `.agents/slop/loc/extract-gate-rows.py` -- THE INSTRUMENT. ITS OWN `split()`
  IS THE POPULATION.
- THE REBUILD THAT USES IT IS A SCRATCH SCRIPT UNDER THE APPROVED TEMP DIR AND
  IS **NOT** PART OF THE COMMIT, BECAUSE IT IS A ONE-SHOT MOVE, NOT A TOOL.

## THE CITATIONS THAT HAD TO BE REPINED

NONE. EVERY `ops.bend:<line>` CITATION IN THE TREE STILL RESOLVES TO THE SAME
CONTENT, AND THE `bendcite` AND `todo-cite` COUNTS ARE UNCHANGED.
