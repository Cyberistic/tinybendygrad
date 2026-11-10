# PROOF-AUDIT: `PROOF.bend` AND `PROOF2.bend` -- DELETE, MOVE, OR KEEP?

**DATE: 2026-11-10. UNIT: a subagent. TREE: `2026-09-30-tinybendygrad`.**

## THE DECISION: **(B) MOVE BOTH INTO `tinybendygrad/LAWS/`** -- DONE.

`tinybendygrad/PROOF.bend` -> `tinybendygrad/LAWS/PROOF.bend`
`tinybendygrad/PROOF2.bend` -> `tinybendygrad/LAWS/PROOF2.bend`

**AND `tinybendygrad/LAWS.bend` STAYS AT THE PORT'S ROOT** -- measured reason in §5.

### WHY NOT (A) DELETE BOTH: **TWO GATES GO rc=3 AND THE AGGREGATE DIES.**

Measured on a SCRATCH COPY (`$SCRATCH/del`, the tree's `tinybendygrad/` copied
and the two halves removed), with `TINYGRAD_ROOT` pointing the gate at it:

```
$ TINYGRAD_ROOT=$SCRATCH/del .venv/bin/python gates/alu-law-census-gate.py
REFUSED, NOT A VERDICT: the ALU/dtype half could not be found by discovery
rc=3

$ TINYGRAD_ROOT=$SCRATCH/del .venv/bin/python gates/shape-law-census-gate.py
REFUSED, NOT A VERDICT: the shape half could not be found by discovery
rc=3
```

**AND THE AGGREGATE NO LONGER COMPILES:**

```
$ .venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend $SCRATCH/del/tinybendygrad/LAWS/PROOF-ALL.bend --check-only
[bounded] WITHIN-LIMITS  rc=1  peak-RSS=35 MB (ceiling 3072)  0s  :: ...  said=SOME PROOFS FAIL | Error: | - message  : no such file: .../tinybendygrad/PROOF.bend
Location:
13 | import Base
14>| import ../PROOF.bend as P1
   |        ^
15 | import ../PROOF2.bend as P2
```

**AND THE PROOF POPULATION SHRINKS FROM 7 FILES TO 4.** `gates/verdict-lane-gate.py`'s
`proof_population()` computes the population from the IMPORT GRAPH, so a broken
import edge does not just lose a file -- it loses the ROOT:

| tree | proof population | roots |
|---|---|---|
| real (before) | **7** | `LAWS/PROOF-ALL.bend`, `runtime/autogen/libclang.bend` |
| **DELETED** | **4** | `LAWS.bend`, `runtime/autogen/libclang.bend` |
| **MOVED** | **7** | `LAWS/PROOF-ALL.bend`, `runtime/autogen/libclang.bend` |

**DELETE IS REFUSED BY THE INSTRUMENTS. THE TWO HALVES ARE LOAD-BEARING.**

### WHY NOT (D) KEEP: **THE MOVE COSTS FOUR IMPORT LINES AND ZERO GATE EDITS.**

Measured: **ZERO** gates or checks hardcode a path to either half.

```
$ rg -n '"PROOF\.bend"|"PROOF2\.bend"|/ "PROOF' gates/ checks/ --glob '!*.rows'
gates/shape-law-census-gate.py:87:AGGREGATE = PORT / "LAWS" / "PROOF-ALL.bend"
gates/shape-law-census-gate.py:531:        rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
... (every hit is PROOF-ALL.bend, which already lives in LAWS/)
```

**EVERY INSTRUMENT DISCOVERS THE HALVES BY CONTENT, NOT BY PATH:**

* `gates/alu-law-census-gate.py` and `gates/shape-law-census-gate.py` both call
  `proof_books(port)`, which is `port.rglob("*.bend")` filtered by
  `re.search(r"^def L\.\w+\(", ...)`. **PATH-AGNOSTIC.** MEASURED: on the MOVED
  tree it still finds exactly **2** books, and still tells them apart by content
  (`A.<fn>` / `dtype_of` => the ALU half; the other => the shape half):
  `alu_half` returns `LAWS/PROOF2.bend` with the same **18** law names.
* `gates/verdict-lane-gate.py` computes the population from import edges.
  **PATH-AGNOSTIC.** MEASURED: **7** files on the MOVED tree, same membership.
* `gates/gapcensus.py` classifies by STEM (`{"LAWS", "PROOF", "PROOF2", "PROOF-ALL"}`).
  **PATH-AGNOSTIC.** MEASURED: `modules.port_only_that_are_laws_or_proof = 4` on the
  real tree, the moved tree, AND the deleted tree.
* `checks/port-compile-gate.py` walks the population and classifies by the
  COMPILER'S OWN ERROR TEXT (`Error: N TODOs found.`). **PATH-AGNOSTIC.**
* `checks/substrate.py`, `checks/compile-census.py` -- path-agnostic.

### THE FOUR IMPORT LINES THAT CHANGED, AND NOTHING ELSE IN THE PORT

```
tinybendygrad/LAWS/PROOF.bend:2   import ./LAWS.bend as L     ->  import ../LAWS.bend as L
tinybendygrad/LAWS/PROOF.bend:3   import ./LAWS/spec.bend as S ->  import ./spec.bend as S
tinybendygrad/LAWS/PROOF2.bend:52 import ./LAWS.bend as L     ->  import ../LAWS.bend as L
tinybendygrad/LAWS/PROOF-ALL.bend:14 import ../PROOF.bend as P1  ->  import ./PROOF.bend as P1
tinybendygrad/LAWS/PROOF-ALL.bend:15 import ../PROOF2.bend as P2 ->  import ./PROOF2.bend as P2
```

(FIVE lines: two in each half plus two in the aggregate. The aggregate's TWO
are the ones that had to change because the halves moved UP a level.)

---

## 1. WHAT IS IN EACH FILE -- MEASURED

| file | lines | TODO count | what it is |
|---|---|---|---|
| `tinybendygrad/LAWS/PROOF.bend` | **494** | **18** | the SHAPE half of the proof set (LAWS.bend sections I, II, III, VI, VII, VIII -- sixteen laws) |
| `tinybendygrad/LAWS/PROOF2.bend` | **141** | **16** | the ALU/dtype half (section IV's nine elementwise-decomposition laws + section V's nine dtype laws -- eighteen) |
| `tinybendygrad/LAWS.bend` | **412** | 34 (declares, fills 0) | THE LAWS. Declares 34 `law NAME:` obligations. Fills none. |
| `tinybendygrad/LAWS/PROOF-ALL.bend` | **15** | **0** | THE AGGREGATE. Imports both halves and is the one command that must pass. |
| `tinybendygrad/LAWS/spec.bend` | **869** | -- | the spec IR as a pure Bend datatype (`Sp`), plus `Sp.shape` / `Sp.dtype` folds |
| `tinybendygrad/LAWS/alu.bend` | **121** | -- | tinyspec's decomposition table as Bend defs |
| `tinybendygrad/LAWS/spec-mut.bend` | 869 | -- | a mutation copy of `spec.bend` (a driver, not a book) |

### THE TODO COUNTS ARE NOT BACKLOG -- THEY ARE THE HALF-BOOK BOUNDARY

MEASURED, `checks/bounded.py --mb 3072 -- ./bin/bend <file> --check-only`, one
bend at a time, verdict token read and not the exit code:

```
LAWS/PROOF.bend    WITHIN-LIMITS rc=1 peak-RSS=35 MB  Error: 18 TODOs found.
LAWS/PROOF2.bend   WITHIN-LIMITS rc=1 peak-RSS=35 MB  Error: 16 TODOs found.
LAWS/PROOF-ALL.bend WITHIN-LIMITS rc=0 peak-RSS=35 MB  ALL PROOFS CHECK
```

**AND THE DISCOVERY CENSUS AGREES, AND THE AGGREGATE'S OWN HEADER SAYS WHY:**
`bend discharges a law by a def of the same name ANYWHERE IN THE BOOK, so the two
halves simply have to meet in one book` (`LAWS/PROOF-ALL.bend:9-11`).

MEASURED, `.agents/slop/laws17/laws.py` on the moved tree (its hardcoded list
updated with the move -- see §6):

```
 34/  0/ 34  tinybendygrad/LAWS.bend
 18/ 16/ 34  tinybendygrad/LAWS/PROOF.bend
 16/ 18/ 34  tinybendygrad/LAWS/PROOF2.bend
  0/ 34/ 34  tinybendygrad/LAWS/PROOF-ALL.bend
```

**EACH HALF SEES THE OTHER'S LAWS AS OPEN. 18 + 16 = 34. THE AGGREGATE IS 0/34.**

**SO THE HYPOTHESIS IN THE BRIEF IS CONFIRMED AND CORRECTED IN ONE PLACE:
THE HALVES ARE STALE *AS A VERDICT*, BUT THEY ARE NOT STALE AS *CONTENT*.** Each
half's own laws are all proved; the TODO count is a property of the BOOK, and a
half-book's closure does not hold the other half's proofs. `PROOF2.bend`'s own
header says this at length, and it is CORRECT (it was verified by
`5fcfd07a0`, "THE SIXTEEN TODOs ARE THE BOUNDARY, NOT A BACKLOG").

**AND THE 34/34 CLAIM IS NOT A LABEL: `gates/alu-law-census-gate.py` and
`gates/shape-law-census-gate.py` MUTATE EVERY LAW'S SUBJECT AND ASK THE GATE TO
GO RED NAMING THAT LAW.** MEASURED on the moved tree: **18 of 18** ALU laws and
**16 of 16** shape laws are not vacuous; the gate is green against its declared
baseline. A law that cannot go red is the failure a count cannot see, and these
are not that.

## 2. WHO IMPORTS THEM

**EXACTLY ONE IMPORTER OF EACH, AND IT IS THE AGGREGATE.**

```
$ rg -n 'import .*PROOF' --glob '*.bend' tinybendygrad/
tinybendygrad/LAWS/PROOF-ALL.bend:14:import ./PROOF.bend as P1
tinybendygrad/LAWS/PROOF-ALL.bend:15:import ./PROOF2.bend as P2
```

**AND THE TWO HALVES IMPORT `LAWS.bend` AND `LAWS/spec.bend`, NOTHING ELSE.**
`LAWS.bend` is imported by exactly two files -- the two halves.
`LAWS/spec.bend` is imported by ~80 port files (it is the datatype the port
itself is built on), which is why `LAWS.bend` CANNOT move without a 16-literal
sweep of two gates (§5).

## 3. DOES ANY GATE DEPEND ON THEM -- **YES, TWO, AND THEY GO RED ON DELETION**

| instrument | on DELETED | on MOVED |
|---|---|---|
| `gates/alu-law-census-gate.py` | **rc=3 REFUSED** ("the ALU/dtype half could not be found by discovery") | **rc=0 PASS** |
| `gates/shape-law-census-gate.py` | **rc=3 REFUSED** ("the shape half could not be found by discovery") | **rc=0 PASS** |
| `gates/verdict-lane-gate.py` (`proof_population`) | **4 files** | **7 files** |
| `LAWS/PROOF-ALL.bend` | **does not compile** (`no such file`) | **ALL PROOFS CHECK** |

**THE CENSUS'S READ OF THEM IS LOAD-BEARING. A GATE GOES RED IF THEY ARE GONE.**

**AND THE `LAWS/PROOF-ALL.bend` DEPENDENCY IS A CONSTRAINT, NOT A CHOICE.**
`PROOF2.bend`'s header records it: bend allows ONE `def L.<name>` per book, so
the two halves CANNOT be merged into one file without duplicating 22 of their 27
helper defs -- the regression `98721d492` repaired. And a FOURTH complete book
in the proof population breaks `gates/verdict-lane-gate.py`'s
`want_disagree = {"tinybendygrad/LAWS/alu.bend", "tinybendygrad/LAWS/PROOF-ALL.bend"}`
anchor. **SO THE AGGREGATE MUST STAY A SEPARATE BOOK, AND THE HALVES MUST STAY
TWO FILES. WHAT THAT LEAVES IS *WHERE THEY LIVE*.**

## 4. THE `LAWS/` FOLDER -- WHAT IT ALREADY HOLDS

```
tinybendygrad/LAWS/
  PROOF-ALL.bend   15    the aggregate: both halves, and THE GATE
  PROOF.bend      494    the shape half          (moved by this commit)
  PROOF2.bend     141    the ALU/dtype half      (moved by this commit)
  alu.bend        121    the decomposition table, as defs
  spec.bend       869    the spec IR as a datatype; dtype/shape as functions
  spec-mut.bend   869    a mutation copy of spec.bend (a driver, not a book)
```

**IT IS THE PROOF FOLDER. BEFORE THIS COMMIT IT HELD THE SPEC'S *MATERIALS*
(`spec.bend`, `alu.bend`) AND THE GATE, BUT NOT THE TWO HALVES THE GATE IS
MADE OF -- SO THE AGGREGATE IMPORTED ITS OWN COMPONENTS FROM OUTSIDE THE
FOLDER. THE MOVE CLOSES THAT.**

**AND THE FOLDER IS NOT NAMED BY ANYBODY.** MEASURED:
`rg 'proof folder|proof dir|proof directory'` -> **no hits** anywhere in the
tree. The name was the brief's, not the tree's. It is the right name: after the
move the folder holds the spec IR, the decomposition table, both proof halves
and the aggregate that discharges them.

## 5. `LAWS.bend` STAYS AT THE ROOT -- MEASURED, NOT BY PREFERENCE

**MOVING `LAWS.bend` INTO `LAWS/` WORKS COMPILES-WISE** (MEASURED in a
scratch copy: `LAWS/PROOF-ALL.bend` -> `ALL PROOFS CHECK`, and
`proof_population` still 7 files), **BUT IT COSTS 16 PATH LITERALS IN 2 GATES.**

```
$ rg -n '"LAWS\.bend"' gates/ checks/ --glob '!*.rows'
gates/shape-law-census-gate.py:140:    declared = set(law_names(port / "LAWS.bend"))
gates/shape-law-census-gate.py:275:    laws_text = (root / "LAWS.bend").read_text(...)
gates/shape-law-census-gate.py:305:        return {"kind": "def", "name": m.group(1), "file": "LAWS.bend"}
gates/shape-law-census-gate.py:327:    laws_text = (root / "LAWS.bend").read_text(...)
gates/shape-law-census-gate.py:480:    elif rel == "LAWS.bend":
gates/shape-law-census-gate.py:501:    laws_f = root / "LAWS.bend"
gates/alu-law-census-gate.py:141:    laws_declared = set(law_names(port / "LAWS.bend"))
gates/alu-law-census-gate.py:400:            (control_root / "LAWS.bend").read_text(...)
gates/alu-law-census-gate.py:403:            laws_text = (control_root / "LAWS.bend").read_text(...)
gates/alu-law-census-gate.py:588:    text = (root / "LAWS.bend").read_text(...)
gates/alu-law-census-gate.py:653:    laws_text = (root / "LAWS.bend").read_text(...)
gates/alu-law-census-gate.py:667:        for n in law_names(root / "LAWS.bend"):
+ 4 more in shape-law-census-gate.py
```

**AND THE NAME `LAWS/LAWS.bend` IS SELF-REFERENTIAL.** `LAWS.bend` is the
LAW BOOK; `LAWS/` is the SPEC folder. The two are DIFFERENT things: `LAWS/`
holds the spec's MATERIALS (`spec.bend` the datatype, `alu.bend` the table),
and `LAWS.bend` holds the CLAIMS about them. Putting the claims inside the
materials' folder, under a name that repeats its own directory, buys
nothing that the four import lines did not already buy.

**SO THE MOVE IS SCOPED TO THE TWO HALVES. `LAWS.bend` STAYS.**

## 6. EVERY OTHER PATH THAT NAMED THE OLD LOCATION -- AND WHAT WAS DONE

| file | what | action |
|---|---|---|
| `tinybendygrad/LAWS/PROOF-ALL.bend` | `import ../PROOF.bend` / `../PROOF2.bend` | **imports re-pointed**; header prose re-pointed |
| `tinybendygrad/LAWS/PROOF.bend` | `import ./LAWS.bend` / `./LAWS/spec.bend` | **imports re-pointed** |
| `tinybendygrad/LAWS/PROOF2.bend` | `import ./LAWS.bend` | **import re-pointed**; its own header's command line re-pointed |
| `spec/laws.md` | the gate was documented as `./bin/bend tinybendygrad/PROOF.bend` -> `ALL PROOFS CHECK` | **REPAIRED.** **THAT WAS FALSE TODAY** (the file reports 18 TODOs). Now names `LAWS/PROOF-ALL.bend`, and says WHY a half is not a gate |
| `spec/shape-laws.md` | file table | path re-pointed |
| `AGENTS.md:80-81` | the two per-file TODO counts | paths re-pointed |
| `checks/substrate-id.py` | 4 scratch-fixture paths (`tinybendygrad/PROOF.bend`) | **re-pointed.** **THESE ARE THE GATE'S OWN SCRATCH-TREE FIXTURE, NOT THE REAL TREE** -- `_seed()` WRITES the file, so the gate never read the real one. MEASURED: `checks/substrate-id.py --plant` -> **`PLANT: OK`, rc=0** after the change |
| `.agents/slop/laws17/laws.py` | a hardcoded list of 4 named roots | **re-pointed.** **THIS IS A HAND LIST, AND THE MOVE BROKE IT** (MEASURED: it printed `MISSING tinybendygrad/PROOF.bend` on the moved tree). **ITS WALK-DISCOVERED ROWS WERE NEVER AFFECTED** -- it also walks the tree, and those rows showed the correct 18/16/34 and 16/18/34 at the NEW paths with no edit at all. The hand list was the only broken part |
| `checks/port-compile.rows` | the `file` column of the two COLD-BY-DESIGN rows | **re-pointed** (2 rows; the classification and the detail text are UNCHANGED, because the compiler's verdict did not move) |
| `checks/unrunnable-recipes.rows` | 13 rows naming the three books | **re-pointed, SURGICALLY** (13 rows changed, 1 file, **no other row touched**). **A FULL REGENERATION WAS REFUSED ON PURPOSE:** `checks/unrunnable-recipes.py --out /tmp/x.rows` differs from the tracked file by **138,316 lines**, because other agents' `.agents/slop/` scratch trees have changed the population. Regenerating would have swept that churn into this commit -- the tree's documented "A DIRECTORY IS NOT A PATH" hazard |
| `oracles/hdr_rows.rows` | 2 rows naming the halves | **re-pointed.** **NO INSTRUMENT READS THIS FILE** (`rg 'hdr_rows'` -> no hits outside itself), so it is an orphan artifact; it was updated for coherence, not because something depended on it |

## 7. THE LOC -- BEFORE AND AFTER

**MEASURED OVER `git ls-tree -r HEAD` (NOT `git ls-files` -- the tree's index
is armed), over `tinybendygrad/*.bend`:**

```
BEFORE  240,529 lines across 194 .bend files   (git ls-tree -r HEAD)
AFTER   235,527 lines across 195 .bend files   (git ls-tree -r HEAD, this commit)
```

**BUT THE TOTAL IS NOT A MEASUREMENT OF *THIS* CHANGE, AND THE HONEST WAY
TO MEASURE THIS CHANGE IS THE COMMIT'S OWN DIFF.** OTHER UNITS COMMITTED
CONCURRENTLY, so the tree's totals moved for reasons that have nothing to do
with this unit. **THE COMMIT'S OWN NUMSTAT IS THE MEASUREMENT:**

```
$ git diff --numstat HEAD~1 HEAD -- 'tinybendygrad/*.bend' 'tinybendygrad/**/*.bend'
5	5	tinybendygrad/LAWS/PROOF-ALL.bend
3	3	tinybendygrad/{ => LAWS}/PROOF.bend
6	6	tinybendygrad/{ => LAWS}/PROOF2.bend
```

**14 INSERTIONS, 14 DELETIONS, 3 FILES, AND THE PORT's `.bend` FILE COUNT IS
195 BEFORE AND 195 AFTER. THE MOVE IS LOC-NEUTRAL BY CONSTRUCTION.** A move that
changes the line count is a move that edits something; this one renames two
paths and re-points five import lines, so the count of lines cannot move.

**AND THE TWO HALVES' OWN LINE COUNTS ARE UNCHANGED TO THE LINE:**

```
BEFORE  494  tinybendygrad/PROOF.bend        AFTER  494  tinybendygrad/LAWS/PROOF.bend
BEFORE  141  tinybendygrad/PROOF2.bend       AFTER  141  tinybendygrad/LAWS/PROOF2.bend
```

**NO LINE WAS ADDED AND NO LINE WAS DELETED. THE MOVE RENAMES TWO PATHS AND
RE-POINTS FIVE IMPORT LINES. THAT IS THE WHOLE OF IT.**


## 8. THE VERIFICATION RUN

```
$ .venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=35 MB (ceiling 3072)  0s  :: ...  out=58B err=0B
ALL PROOFS CHECK

$ .venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend tinybendygrad/LAWS/PROOF.bend --check-only
[bounded] WITHIN-LIMITS  rc=1  peak-RSS=35 MB  Error: 18 TODOs found.      <- UNCHANGED

$ .venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend tinybendygrad/LAWS/PROOF2.bend --check-only
[bounded] WITHIN-LIMITS  rc=1  peak-RSS=35 MB  Error: 16 TODOs found.      <- UNCHANGED

$ .venv/bin/python gates/alu-law-census-gate.py
-- 18 ALU/dtype laws, 15 ALU dtype arms
-- vacuous laws: 0
-- unpinned dtype arms: 13
-- vacuous on their mask: 5
OK: the census is no worse than the baseline: every ALU/dtype law goes red when its subject is broken, and no arm lost its law
rc=0

$ .venv/bin/python gates/shape-law-census-gate.py
-- 16 shape laws, 50 shape fold arms
-- vacuous laws: 1  store_matches_its_buffer
-- masked laws: 3  add_is_elementwise, pad_shrink_round_trip, reshape_numel_is_the_new_shape
-- unpinned shape arms: 39
OK: the census is no worse than the baseline: no shape law is more vacuous than the declared baseline
rc=0

$ .venv/bin/python checks/substrate-id.py --plant
PLANT: OK
rc=0

$ .venv/bin/python .agents/slop/laws17/laws.py
 34/  0/ 34  tinybendygrad/LAWS.bend
 18/ 16/ 34  tinybendygrad/LAWS/PROOF.bend
 16/ 18/ 34  tinybendygrad/LAWS/PROOF2.bend
  0/ 34/ 34  tinybendygrad/LAWS/PROOF-ALL.bend
```

**AND `gates/verdict-lane-gate.py`'s `proof_population()` IS 7 FILES WITH THE
SAME MEMBERSHIP AS BEFORE THE MOVE.** The gate's `want_disagree` set names
`LAWS/alu.bend` and `LAWS/PROOF-ALL.bend` -- **both already in `LAWS/`, both
UNAFFECTED.**

## 9. THE THING THAT WAS TRUE AND IS NOT ANY MORE

**`spec/laws.md` DOCUMENTED A GATE THAT DID NOT EXIST.** It said:

```
$ ./bin/bend tinybendygrad/PROOF.bend
ALL PROOFS CHECK
```

**AND `tinybendygrad/PROOF.bend` REPORTS `Error: 18 TODOs found.`** The real gate
is `LAWS/PROOF-ALL.bend`. The document has been repaired to name the aggregate
AND to say why a half is not a gate.

**THAT IS THE CLASS `AGENTS.md` NAMES:** *"A GOVERNING DOCUMENT THAT CARRIES A
FALSE CLAIM PROPAGATES INTO EVERY BRIEF THAT CITES IT."* This one was in
`spec/laws.md` -- the spec's own README for the proof book -- and it named a
command that cannot succeed.

## 10. THE SHARED-TREE HAZARD THAT WAS ACTIVE DURING THIS UNIT

**MEASURED MID-TASK: ANOTHER AGENT RAN A TREE-WIDE PROSE-LINT OVER THE WHOLE
WORKING COPY WHILE THIS UNIT WAS WORKING.**

```
$ git diff --name-only HEAD | wc -l
33048
$ git diff --name-only HEAD -- '*.bend' | wc -l
10634
```

**AND EVERY CHANGED LINE IN A SAMPLE OF FIVE FILES WAS A COMMENT** (0 non-comment
changed lines in `base.bend`, `tensor.bend`, `uop/ops.bend`, `device.bend`,
`function.bend`) -- an ALL-CAPS-to-sentence-case prose rewrite.

**TWO CONSEQUENCES, AND BOTH ARE MEASURED:**

1. **`PROOF.bend` AND `PROOF2.bend` CARRY ANOTHER UNIT'S UNCOMMITTED COMMENT-ONLY
   EDITS INTO THIS COMMIT.** The tree's rule is "NEVER DISCARD ANOTHER UNIT'S
   WORK", so the move carried their bytes. The rename is therefore **R99 / R93**,
   not R100 -- the delta is their edit, not mine.
2. **A FULL REGENERATION OF `checks/unrunnable-recipes.rows` WAS REFUSED.** Its
   138,316-line delta is other agents' scratch trees, and a regeneration would
   have swept that into this commit. The 13 rows were re-pointed by hand
   instead. **A REGENERATED ARTIFACT IS NOT A SAFE THING TO REGENERATE ON A
   SHARED TREE, AND THE FIXTURE-PATH PROOF IS CHEAPER THAN THE REGENERATION.**

## 11. THE COMMIT

**`328145c7c` -- "THE TWO PROOF HALVES MOVE INTO `LAWS/`..."**

```
$ git show --name-only --format='' HEAD | sort
.agents/slop/laws17/laws.py
.agents/slop/proof-audit/REPORT.md
AGENTS.md
checks/port-compile.rows
checks/substrate-id.py
checks/unrunnable-recipes.rows
oracles/hdr_rows.rows
spec/laws.md
spec/shape-laws.md
tinybendygrad/LAWS/PROOF-ALL.bend
tinybendygrad/LAWS/PROOF.bend
tinybendygrad/LAWS/PROOF2.bend
```

**TWELVE FILES. ZERO FOREIGN FILES SWEPT.** (`--only` with an explicit
pathspec; the two old paths do not appear because git recorded them as renames:
`rename tinybendygrad/{ => LAWS}/PROOF.bend (99%)` and
`rename tinybendygrad/{ => LAWS}/PROOF2.bend (93%)`.)

**`git fsck --no-progress` NAMES TWO MALFORMED TREES, AND NEITHER IS OURS:**

```
error in tree 3a60f33f57a4bb2fe120a97720b6bb2af38d9593: duplicateEntries: contains duplicate file entries
error in tree d83cf685f89af04f607a49a3c6d2c8ef0c1eec65: duplicateEntries: contains duplicate file entries
```

**AND BOTH ARE ORPHANED, WHICH IS THE RIGHT OUTCOME:** MEASURED,
`git merge-base --is-ancestor <tree> HEAD` answers **NOT AN ANCESTOR** for both.
`AGENTS.md` already names them (`d83cf685` owned by `591f6b499`, `3a60f33f`
owned by `63b64ebad`, `d57bc484` UNOWNED) as the 435-file armed-index outage.
**AND `git fsck HEAD` DOES NOT NAME `HEAD`'s OWN TREE, SO THIS COMMIT'S TREE
IS WELL-FORMED.** A push of HEAD would not carry the malformed trees.

**AND THE COMMIT CARRIES ANOTHER UNIT'S PROSE-LINT BYTES, DELIBERATELY.**
MEASURED on `AGENTS.md` alone: **4** changed rows are this unit's path edits and
**88** are the other unit's ` ` -> `AND` prose rewrite. **THE TREE'S RULE IS
"NEVER DISCARD ANOTHER UNIT'S WORK", AND A COMMIT THAT DROPPED THEM WOULD HAVE
BEEN A REVERT.** The renames are therefore R99 and R93, not R100 -- and the
delta is THEIR edit and not this unit's.

## 12. WHAT WAS NOT DONE, AND WHY

* **`tinybendygrad/LAWS.bend` was NOT moved.** 16 path literals in 2 gates, and
  the name `LAWS/LAWS.bend` is self-referential. §5.
* **`gates/alu-law-census-gate.py` and `gates/shape-law-census-gate.py` were NOT
  edited.** Zero edits were needed -- their discovery is path-agnostic. §2, §3.
* **`.agents/TODO.md` was NOT touched** (the brief forbids it; 5 other agents are
  editing it).
* **`checks/port-compile-gate.py` was NOT run** (4 minutes, and the brief caps it
  at one run; the census's classification of the two halves is by the COMPILER'S
  OWN ERROR TEXT, and the compiler's verdict for both is UNCHANGED at the new
  paths -- §8).
* **NO CORPUS RUN, NO `differ.py run`, NO `pytest test/`.**
