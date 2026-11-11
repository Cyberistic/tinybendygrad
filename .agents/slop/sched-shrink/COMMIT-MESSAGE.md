schedule/: THE GATE ROWS MOVE TO gates/, AND **17,390 LINES **BECOME **13,632**

The port's schedule module carried **8,060** code lines against upstream's
**1,180** -- a **6.8x** excess. **This commit moves the **ROWS** (the
`name=value` producers and the **ROW-ONLY HELPERS** they call) out of the
**PORT** and into **THE GATE DRIVER** the tree's own convention asks for.

**`gates/README.md:173`**: *"a gate's `.bend` driver and its CPython oracle
sit in `gates/`, named by the gate that needs them."* **The port file
carries the port; the gate file carries the instrument.**

THE NUMBERS, MEASURED.

    schedule/multi.bend        3456 -> 2427   (-1029)
    schedule/rangeify.bend    3413 -> 2798   (-615)
    schedule/indexing.bend    2117 -> 1531   (-586)
    schedule/prepare.bend      987 ->  487   (-500)
    schedule/rangify.bend     1843 -> 1631   (-212)
    schedule/realize.bend      545 ->  483   ( -62)
    schedule/allreduce.bend    772 ->  457   (-315)
    schedule/memory.bend      1787 -> 1347   (-440)
    --------------------------------------------------------------
    schedule/ TOTAL          17390 -> 13632  (-3758, -21.6%)
    CODE LINES               7924 ->  5997  (-1927, -24.3%)

**THE MEASUREMENTS ARE **NOT **TOUCHED.**  **Every row is byte-identical**:
**321 + 159 + 249 + 314 + 26 + 8 + 48 + 57 = 1182 rows**, measured as the
**UNION** of the port file's output and the driver's, against the **PRE-MOVE**
run of the same files.  **The port file emits **NO** rows of its own** (it has
no `main`), and the driver emits **ALL** of them.

THE COMPILER.  **All nine `schedule/*.bend` files still answer
`ALL PROOFS CHECK`**, and `checks/port-compile-gate.py`'s census does not
grow: **186 compiled, 8 cold-by-design, 1 finding, 0 unmeasured** -- the same
finding (`renderer/kuconv.bend`) as before.

THE PORT's OWN BACKLOG STAYS IN THE PORT.  **The `# WALL(p3)` /
`# TODO(p3)` markers are the port's standing work list**, and
`checks/marker-audit.py` reads them: **613 walls and 8 BACKLOG before, 613
walls and 8 BACKLOG after.**  **The first version of this move took **25**
`WALL(p3)` markers into `gates/rangeify-gate.bend`** -- **and the census
fell from 613 to 591**, **and a population that moves is a population the
instrument cannot see.**

THE CITATIONS.  **A CITATION IS LOAD-BEARING**: it is what the pin is
re-pointed by.  **`gates/bendcite-gate.py` judges every `.bend` -> `.bend`
line pointer**, and the pointers rot when the lines move.  **So the pointers
were RE-POINTED, not dropped**: `schedule/prepare.bend:274` ->
`:236`, `schedule/multi.bend:611` -> `:575`, `schedule/rangeify.bend:2810` ->
`:2368`, and **six** more.  **MEASURED: 439 broken pointers before, 431
after, and ZERO pointers that were fine before are broken after.**  **The
six that were already broken were left alone**: **a pointer the
pre-move run already rejected is not this move's business**, and
re-pointing it to the instrument's "nearest" answer makes it LOOK fixed and
be wrong.

THE TOOLS, under `.agents/slop/sched-shrink/`.

**`widen-producers.py`** -- **the proven `extract-gate-rows-producers.py`,
LOADED BY PATH, with the PRODUCER CLASSIFIER WIDENED.**  **The proven
classifier asks "does this def's body call `row`/`srow`/`urow`"**, and
**`schedule/indexing.bend` has **NINE** producers that print through a
producer it calls** (`g_expand` through `ix_mv_expand_row`, `g_ss` through
`ix_ss_h_row` and `ix_ss_top_row`, ...) **-- and the proven tool REFUSED the
file over them.**  **The widened classifier is **THE SAME RULE, INVERTED**:
a def is row-side iff **every def that calls it is row-side**, and the
row-side set is the fixpoint that begins at the printers.  **The proven
tool's qualification, rebasing, ordering, external-user rule and compile
checks are all reused unchanged.**

**`repoint-schedule-cites.py`** -- **the citation re-pointer.**  **The
BROKEN SET IS THE INSTRUMENT's OWN** (`gates/bendcite-gate.py`'s rows),
**not a hand list and not a heuristic**: **a pointer the instrument already
rejected is not this move's business**, and **the re-point target is the
construct the instrument's own `why` names.**

**WHY THE THREE FILES.**  `schedule/rangify.bend` is **NOT** a second copy
of `schedule/rangeify.bend`: **it is the port's own `run_rangeify` driver**,
for upstream's `tinygrad/schedule/indexing.py:183-210`, and **its header
says so.**  **The module is one file per upstream file**, and the port's
header maps each one.

**AND THE ONE NAME THAT NEEDED CARE**: `schedule/memory.bend`'s driver is
**`gates/schedule-memory-gate.bend`**, **not `gates/memory-gate.bend`** --
**because `gates/memory-gate.bend` ALREADY EXISTS** and **it is the driver
for `tinybendygrad/runtime/support/memory.bend`** -- **and the collision
check READS the driver's own header** to tell the two apart.
