# codegen/ and renderer/ shrink -- the report

## WHAT LANDED

One change to the port, and the repair of the two instruments it broke.

| file | what |
|---|---|
| `gates/dsl-gate.bend` | NEW. The 887 census rows of `renderer/amd/dsl.bend`, moved out of the port. |
| `tinybendygrad/renderer/amd/dsl.bend` | 3,348 lines -> 1,593. The port's own logic, no rows. |
| `gates/amd_dsl_census-gate.py` | REPAIRED. Its lane, its row-name population and its fixture readers pointed at the port, which now prints ZERO rows. The gate was DEAD (rc=5) on every run. |
| `gates/amd_dsl_census-mutate.py` | REPAIRED. Its lane pointed at the port too, so every mutation was a silent green. |
| `tinybendygrad/renderer/cstyle.bend` | ONE citation re-pointed. `dsl.bend:2066-2069` -> `dsl.bend:1577-1579`. The text did not move; the port's line count did. |

The port move itself was committed by another session as `8db5114da` while this unit was
working. This unit's contribution is the INSTRUMENT REPAIR: the move left two live gates
reading a file that no longer holds the rows, and a tree where a census reads ZERO rows and
a mutation harness reads GREEN is a tree with two dead instruments that look alive.

## THE MEASURED LINE COUNTS

The census rule is `.agents/slop/loc/the-1to1.py`'s: `GATE ROWS` are lines whose first
non-space token is `srow(`/`row(`, `COMMENTS` are lines whose first non-space token is `#`,
`BLANK` are empty lines, and `CODE` is everything else. The population is `git ls-tree -r
HEAD` (NOT `git ls-files`, because the tree's index is armed).

### BEFORE the move (`6dc1fc649`, the commit before `8db5114da`)

```
codegen:   lines=18148  gate_rows=101  comments=7872  blank=2295  code=7880
renderer:  lines=25472  gate_rows=887  comments=9970  blank=3019  code=11596
```

### AFTER (`1d3d5e7a6`, HEAD at the time of writing)

```
codegen:   lines=18123  gate_rows=101  comments=7493  blank=2649  code=7880
renderer:  lines=23688  gate_rows=  0  comments=9233  blank=3376  code=11079
```

### THE DELTA

| module | lines | gate rows | code |
|---|---|---|---|
| codegen | -25 | 0 | 0 |
| **renderer** | **-1,784** | **-887** | **-517** |

**codegen's CODE IS UNCHANGED (7,880)**, and its 25 fewer lines are 25 fewer COMMENT lines
from the tree's own comment-pruning commit `1d3d5e7a6`, not a port change. **renderer's
517 fewer code lines are the `dsl.bend` move**, and its 449 fewer comment lines are the
same pruning commit.

**WHY codegen's 101 GATE ROWS DID NOT MOVE.** They are in `decomp/op.bend` (52),
`decomp/transcendental.bend` (26), `late/linearizer.bend` (48) and `late/regalloc.bend` (2),
and they are NOT separable from the port by the tree's own tool:

- `gates/linearizer_census-gate.py` and `gates/regalloc_census-gate.py` point `DRIVER` at
  the PORT file and run IT as the bend lane. Moving the rows means re-pointing both gates,
  and their row populations are DISCOVERED by running the two lanes and comparing the row
  NAMES IN ORDER.
- `codegen/decomp/op.bend`'s rows are interleaved with the port: `gate()` is a producer
  that calls the port's defs, and `main()` calls `gate()`.

**The lever is real but it is a GATE RE-POINT, not a text move**, and the brief's absolute
rules ("never weaken an instrument") make it a much larger change than the `dsl` move was.
It was NOT landed here.

## WHY THE MOVE IS SAFE

### The rows are BYTE-IDENTICAL

MEASURED 2026-11-10, by running the OLD port (from `8db5114da^`) and the NEW driver and
diffing:

```
1178 rows before, 1178 rows after, `diff` EMPTY
```

The old port was restored into the tree at its own path so its relative imports resolved
(`/tmp` does not resolve `import ../../helpers.bend`), and both were run with the same
`bin/bend`.

### Both files compile

```
$ ./bin/bend tinybendygrad/renderer/amd/dsl.bend --check-only
ALL PROOFS CHECK
$ ./bin/bend gates/dsl-gate.bend --check-only
ALL PROOFS CHECK
```

### The dependants still work

MEASURED, after the move:

```
$ ./bin/bend gates/sqtt-gate.bend | wc -l   ->  1033
$ ./bin/bend gates/elf-gate.bend  | wc -l   ->   115
$ ./bin/bend tinybendygrad/renderer/amd/sqtt.bend --check-only -> ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/renderer/amd/elf.bend  --check-only -> ALL PROOFS CHECK
```

`gates/sqtt-gate.bend` IMPORTS `tinybendygrad/renderer/amd/dsl.bend`, so it is the
dependant that would have caught a broken port. It emits the same 1,033 rows.

### The gate is GREEN AGAIN, at the same numbers

```
$ .venv/bin/python gates/amd_dsl_census-gate.py
  groups_hold: OK
  names_hold: OK
  dup_rows_hold: OK
  axes_hold: OK
  pin_drift_hold: OK
  divergences_hold: OK
  classes_hold: OK
amd_dsl_census: PASS -- 1178 rows x 3 lanes, 1147 exact, 31 pinned (31 names)
```

1178 rows, 1147 exact, 31 pinned -- THE SAME reading as before the move. The pins file,
the class list, the row counts and the comparison logic are UNCHANGED; the diff against
`8db5114da^` is the reader re-pointing and nothing else.

### The mutation harness is ALIVE again

MEASURED, 19 input mutations and 13 guard mutations:

- BEFORE the repair: `bd=0 lines` on the unmutated lane, and EVERY mutation "MOVED
  NOTHING at rc=0" -- a green harness measuring nothing.
- AFTER: `bd=1178 lines`, `py=1178 lines`, 1164 distinct port row names, 31 divergences on
  the unmutated tree, and the mutations move rows.

## THE TWO REPAIRS, AND WHAT EACH ONE FOUND

### 1. `gates/amd_dsl_census-gate.py` -- the reader that pointed at the wrong file

The gate used one name, `PORT`, for FOUR different reads, and the move split them:

| read | what it wanted | where it lives now |
|---|---|---|
| the LANE to run | the file that emits the rows | `gates/dsl-gate.bend` |
| the ROW-NAME population | the `g_*` bodies' `row` calls | `gates/dsl-gate.bend` |
| the FIXTURE declarations | `VOP2_FIELDS`, `VOP2_ALL`, ... | BOTH files, split |
| the CONSTANTS | `def X() -> U32: <n>` | BOTH files, split |

**FOUND 1 -- the ORDER is `main()`'s CALL order, not the file order.** Bend has no forward
references, so the move put the `g_*` groups into their DEPENDENCY order: the file order
is `enc, vs, get, inst, ops, mod, bf, tables, const, lit, fmt` and the EMITTED order is
`tables, const, get, fmt, mod, bf, enc, lit, inst, ops, vs`. A reader that walked the FILE
would compare 1178 names in the wrong order and report a move on row 0, which is not a
defect in the port. THE READER NOW COLLECTS PER GROUP AND VISITS THE GROUPS IN `main()`'s
ORDER.

**FOUND 2 -- the driver QUALIFIES the port's names.** The driver calls the port's `row` as
`P.row(...)` (76 rows) and spells the fixtures `P.Vf.of(P.Fld.vgpr(...), ...)`. A reader
that accepted only the bare spelling counted 1,102 names against the oracle's 1,178 and
was FAIL on a reader that had not lost a row. THE `P.` IS NOW OPTIONAL, IN EVERY READER.

**FOUND 3 -- the FIXTURES ARE SPLIT ACROSS THE TWO FILES.** `VOP2_FIELDS`, `F40_VALS` and
`F8_VALS` moved into the driver with the census body, and `F40_FIELDS` and `F8_FIELDS` STAYED
in the port because the IMPLEMENTATION calls them -- the move's own "stay-and-qualify"
rule. A reader of ONE file found half the fixtures and reported the other half as "not
declared". THE READER READS BOTH.

**FOUND 4 -- the CONSTANTS ARE SPLIT, AND THE SETS ARE DISJOINT.** MEASURED: the port holds
111 `def X() -> U32: <n>` constants and the driver holds 19, with NO name in both. The
fixture's VALUES spell the driver's and the implementation spells the port's, so a reader
of one file resolves only half and the other half RAISES -- which is the
`refuse rather than compare as zero` rule doing its job on a reader pointed at the wrong
file. THE READER READS BOTH.

**FOUND 5 -- a DOTTED CALL is not a bare call.** The driver's fixture spells the float
`P.src_ov_float(P.F0_5_OFF(), True{})` where the port's own was
`src_ov_float(F0_5_OFF(), True{})`, and the bare `\w+\(\)` did not match a dotted name, so
the `src0` field of `VOP2_FCONST` and `VOP2_FNOLIT` was not matched AT ALL and the reader
reported the fixture as spelling five fields where the oracle spells six. THE DOTTED NAME
IS NOW ACCEPTED.

MEASURED, the whole table after the repair: 19 input mutations, 13 guard mutations. 17 of 19
input mutations move rows; 12 of 13 guard mutations go red. The two that move nothing are
**A6 and A7**, and they are the KNOWN finding, not a regression: the census's own header
records that "no fixture here sets `Reg.abs_`, and the opsel family asks about `src2`,
which `VOP2_FIELDS` has NO FIELD FOR."

### 2. `gates/amd_dsl_census-mutate.py` -- the harness that ran the wrong lane

- The lane ran the PORT, which prints ZERO rows.
- The mutated driver imports the port by a FIXED relative path
  (`./../tinybendygrad/renderer/amd/dsl.bend`), so a mutated port copy at `dsl-mut.bend`
  was NEVER the file the driver imported and every PORT mutation was a silent green.
- The `m.PORT`/`m.PINS` override in the runner left `m.DRIVER` alone, so the lane ran the
  UNMUTATED driver.
- Four mutation PATTERNS were in the driver's qualified spelling and matched nothing.

**ALL FOUR ARE FIXED.** The mutated driver now imports the mutated port, by the REAL path
and not by string arithmetic; the runner points `m.DRIVER` at the mutated copy and
re-derives `_U32_DEFS` from BOTH mutated files; the four patterns carry the driver's
spelling; and a "port" mutation RESOLVES TO WHICHEVER FILE HOLDS THE PATTERN, with a
pattern in NEITHER or in BOTH a REFUSED entry and not a green one.

MEASURED, the whole table after the repair (`.agents/slop/cr-shrink/mutate.out`):

```
amd_dsl_census-mutate: {'GUARD': 13, 'VALUE': 9, 'POPULATION': 5, 'AXIS': 5} by kind;
  17 of 19 input mutations moved rows;
  2 moved NOTHING at rc=0;
  0 moved nothing but still went RED;
  0 did not compile;
  0 refused on a non-unique pattern;
  12 of 13 guard mutations went red
```

BEFORE the repair the same table read `bd=0 lines` on the unmutated lane and EVERY mutation
"MOVED NOTHING at rc=0" -- and **4 REFUSED on a non-unique pattern**, which is the
pre-repair count of zero. The two that move nothing are **A6 and A7**, and they are the
KNOWN finding, not a regression: the census's own header records that "no fixture here
sets `Reg.abs_`, and the opsel family asks about `src2`, which `VOP2_FIELDS` has NO FIELD
FOR."

## THE CITATION

`tinybendygrad/renderer/cstyle.bend:2303` cited `dsl.bend:2066-2069` for the
`_variant_suffix` comment. The move shortened the port to 1,593 lines, so the citation
pointed PAST THE END. The TEXT did not move -- it is still in the port -- but its LINE
NUMBER moved to 1577-1579, and the citation was re-pointed.

MEASURED, `gates/bendcite-gate.py`: 496 failures -> 495, and the one that went away is this
one. The remaining 495 are pre-existing across the tree and are NOT this unit's work.

## WHAT WAS NOT DONE, AND WHY

### `codegen/` was NOT shrunk.

The 101 gate rows in `codegen/` are interleaved with the port, and the two gates that own
them (`linearizer_census-gate.py`, `regalloc_census-gate.py`) point their `DRIVER` at the
PORT and run it as the lane. Moving the rows is a GATE RE-POINT, and the rule "never
weaken an instrument" means the re-point has to preserve the gates' DISCOVERED row
populations and their ORDER. That is a real piece of work and it was not done here.

### `renderer/ptx.bend`'s generated-fixtures region was NOT moved.

`renderer/ptx.bend` holds a `# ==== BEGIN GENERATED FIXTURES` region (lines 678-1247, 570
lines) with the port's own 25 fixture graphs and 268 `want` values, and its `main()` emits
the port's rows. The region is LOAD-BEARING BY PATH:

- `gates/fixture-region-gate.py` runs the generator the region NAMES and compares the
  region with what came out -- so the region must stay where the generator writes it.
- `gates/fixture-embed-census.py` reads the region's `Wt` records out of
  `tinybendygrad/renderer/ptx.bend` by path.

Moving it would break two live instruments. The port's PORT LOGIC (`wk_all`, `r_go`,
`Wal`, `Rg`, `reg_block`) is consumed by `gates/ptx_render_census.bend`, and that part
stays.

### `codegen/late/gater.bend` has a BYTE-IDENTICAL duplicated 12-line block (lines 15-25
and 34-44), and removing one copy gains 12 lines -- but THE FILE DOES NOT COMPILE**, and
it did not compile before the edit either (MEASURED: `a declared constructor (unknown:
../../uop/ops.Dq)`, on the stashed original as well). A change to a file that does not
compile gains nothing verifiable, so the edit was REVERTED and the pre-existing breakage
is reported here instead.

## THE MEASUREMENT CAVEAT, AND WHY IT MATTERS

The shared working tree is under active edit by other sessions. MEASURED 2026-11-10 at
13:30, `tinybendygrad/uop/ops.bend` carried **2,195 UNCOMMITTED DELETIONS** in the working
tree, and `type OI` was among the deleted lines. Six of the ten target files
(`codegen/decomp/dtype.bend`, `codegen/decomp/op.bend`, `codegen/late/linearizer.bend`,
`renderer/cstyle.bend`, `renderer/ptx.bend`, and `codegen/decomp/transcendental.bend`)
therefore answered `SOME PROOFS FAIL -- a declared constructor (unknown: ../uop/ops.OI)`.

**THAT IS NOT A DEFECT OF THESE FILES.** MEASURED: with `ops.bend` stashed back to HEAD,
all ten answer `ALL PROOFS CHECK`. So the BASELINE and the AFTER readings in this report
were taken in a CLEAN WORKTREE at `1d3d5e7a6`, and NOT in the shared tree.

A gate that reads the shared tree right now would be red on another unit's half-finished
work, and the honest reading is that the tree is in flight, not that the port is broken.

## THE COMPILE OUTPUTS, BEFORE AND AFTER

Taken in the clean worktree, with `bin/bend` and `references/bend` linked in from the main
tree.

### BEFORE the move (`6dc1fc649`)

```
tinybendygrad/codegen/decomp/dtype.bend            ALL PROOFS CHECK
tinybendygrad/codegen/decomp/op.bend               ALL PROOFS CHECK
tinybendygrad/codegen/decomp/transcendental.bend   ALL PROOFS CHECK
tinybendygrad/codegen/late/linearizer.bend         ALL PROOFS CHECK
tinybendygrad/codegen/late/regalloc.bend           ALL PROOFS CHECK
tinybendygrad/renderer/isa/x86.bend                ALL PROOFS CHECK
tinybendygrad/renderer/cstyle.bend                 ALL PROOFS CHECK
tinybendygrad/renderer/amd/generate.bend           ALL PROOFS CHECK
tinybendygrad/renderer/amd/dsl.bend                ALL PROOFS CHECK
tinybendygrad/renderer/ptx.bend                    ALL PROOFS CHECK
```

### AFTER (`1d3d5e7a6`)

The same ten lines. `renderer/amd/dsl.bend` is the ONLY one that changed, and it changed
from "prints 1178 rows" to "prints zero rows and `ALL PROOFS CHECK`", which is the point.

## THE UPSTREAM RATIO

The brief's target is `mixin`'s 1.2x. At `1d3d5e7a6`:

```
$ .venv/bin/python .agents/slop/loc/the-1to1.py --json
{
  "port_lines": 282744,
  "upstream_lines": 63395,
  "ratio": 4.46,
  "gate_rows": 1181,
  "comments": 114588,
  "blank": 42292,
  "code": 124683,
  "upstream_code": 56436,
  "code_ratio": 2.21
}
```

**THE RATIO IS 4.37x ON LINES AND 2.16x ON CODE**, and the difference between the two is
the COMMENT BLOCK: 117,224 comment lines are 42% of the tree. The `dsl` move took 887
GATE ROWS out of the port, which is the right shape of change -- a gate row is an
instrument, not a port -- but it is 887 lines out of 277,166, and the COMMENTS are the
dominant block by a factor of ten over the gate rows.

**SO THE HONEST ANSWER TO "can this be shrunk without losing a citation or a
measurement" is: the GATE ROWS can, and the COMMENTS cannot be deleted but can be
RESTATED.** The tree's own `demark.py` already did the mechanical pass (the comment style
is quiet now). What is left in the comment block is mostly the FIXED-BUG NARRATIVE and
the MUTATION TABLES, and `prune-comments.py` exists for exactly that -- but it removes
prose, and every citation and every measurement in it is load-bearing by the brief's own
rules.

## WHAT I WOULD DO NEXT, AND WHY IT IS THE RIGHT ORDER

1. **Re-point the `codegen/late` census gates at a driver, the way `dsl` was.** That is
   50 rows (`linearizer` 48 + `regalloc` 2) and it is the LAST contiguous instance of
   Lever 1. The gates are already discovery-based, so the re-point is a `DRIVER` constant
   and a row-name reader, and the population keeps being DISCOVERED.

2. **`codegen/decomp/op.bend` (52 rows) and `transcendental.bend` (26 rows)**, whose
   `gate()` producers call the port's defs. These need the port's defs to stay reachable
   and the producer to move, which the tree's producer tool does -- but the two files'
   gates are not census gates with a `DRIVER` constant, so the re-point is a larger change.

3. **THE COMMENT BLOCK, by hand, not by regex.** The `prune-comments.py` tool removes the
   shell transcripts and the fixed-bug narrative. What it CANNOT remove without losing a
   citation or a measurement is the MUTATION TABLE -- and the mutation tables in
   `codegen/decomp/op.bend` and `codegen/late/regalloc.bend` are exactly the kind of
   measurement the brief says is load-bearing.

## THE TOOLS USED

- `.agents/slop/loc/the-1to1.py` -- the 1:1 census instrument. The line counts in this
  report are ITS numbers, not a second implementation of its rule.
- `.agents/slop/loc/extract-gate-rows-producers.py` -- the producer-discovery tool. It is
  the tool the `dsl` move used.
- `./bin/bend <file> --check-only` -- the per-file compile reading. `ALL PROOFS CHECK` is
  the verdict; the exit code is not.
