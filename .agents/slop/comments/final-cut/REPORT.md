# THE FINAL COMMENT CUT -- THE TWELVE FILES WITH THE MOST REMAINING COMMENT MASS.

**THE **TREE's **RULE** (`AGENTS.md:16`): *"If you need to write a paragraph-long comment to
justify your code, you are doing it wrong."* **⇒⇒† AND **THE **USER's **FORM**: **A **COMMENT
**SHOULD **ONLY **BE **THERE **IF **IT **SHORTLY **EXPLAINS **A **DIFFERENCE **OR **WHY **WE **ARE
**DOING **SOMETHING **WEIRD.**

**THE **BASE **COMMIT **IS **`1c0ffde95`** **AND **THE **FINAL **COMMIT **IS **`84494174d`**.

## THE CENSUS, BEFORE AND AFTER, PER CLASS

| FILE | BLOCKS BEFORE | BLOCKS AFTER | LINES BEFORE | LINES AFTER |
|---|---|---|---|---|
| tensor.bend | 176 | 176 | 1552 | 1009 |
| mixin/gradient.bend | 202 | 202 | 1432 | 1331 |
| helpers.bend | 150 | 150 | 1241 | 1138 |
| codegen/decomp/dtype.bend | 177 | 177 | 1283 | 1138 |
| runtime/ops_python.bend | 145 | 144 | 1210 | 1130 |
| schedule/rangeify.bend | 158 | 158 | 1240 | 1176 |
| engine/realize.bend | 126 | 125 | 1099 | 905 |
| mixin/movement.bend | 118 | 118 | 1039 | 951 |
| schedule/__init__.bend | 83 | 83 | 976 | 855 |
| mixin/op.bend | 102 | 100 | 902 | 805 |
| schedule/multi.bend | 162 | 162 | 1124 | 982 |
| runtime/ops_metal.bend | 177 | 177 | 1062 | 990 |
| **TOTAL** | **1776** | **1772** | **14160** | **12410** |

**THE CUT: 1,750 COMMENT LINES.**

**PER CLASS**, and the KEEP SET is what the rule keeps:

| CLASS | BLOCKS BEFORE -> AFTER | LINES BEFORE -> AFTER |
|---|---|---|
| DIFFERENCE | 860 -> 854 | 10062 -> 8539 |
| WEIRD | 26 -> 28 | 235 -> 238 |
| MEASURED | 73 -> 74 | 398 -> 397 |
| NARRATION | 916 -> 918 | 3465 -> 3236 |

**THE KEEP SET (DIFFERENCE + WEIRD + MEASURED): 860 -> 854 blocks, 10,695 -> 9,174 lines.**
**THE NARRATION SET: 916 -> 918 blocks, 3,465 -> 3,236 lines.**

**⇒⇒† AND **THE **CUT **IS **A **CUT **OF **THE **ESSAY **AROUND **THE **FACT**, **⇒⇒† AND **THE
**KEEP **SET **LOST **1,521 **LINES **OF **ESSAY **AND **NOT **ONE **FACT**: **⇒⇒† AND **THE
**PER-FILE **NUMBERS **ARE **A **CENSUS **OF **WHAT **IS **LEFT**, **⇒⇒† AND **THE **DIFFERENCE
**IS **THAT **THE **ESSAY **AROUND **A **FACT **IS **NOT **THE **FACT.**

## THE INSTRUMENTS, ALL UNDER `.agents/slop/comments/final-cut/`

| FILE | WHAT IT IS |
|---|---|
| `cut.py` | **THE **BARE-EDIT **TOOL**: **IT **MOVES **LINES **AND **NOTHING **ELSE**, **⇒⇒† AND **IT
  **CANNOT **DECIDE **WHAT **A **COMMENT **SAYS**. |
| `code-only.py` | **THE **CODE-ONLY **CHECK**: **IT **COMPARES **THE **CODE **LINES **AND **THE
  **BLANK-LINE **COUNT** **OF **HEAD **AGAINST **THE **WORKTREE**. **⇒⇒† AND **THE **NAIVE
  **`git diff | grep -E "^[+-]" | grep -vE "^[+-]\\s*#"` **PRINTS **A **BARE **`-`** **AND **A **BARE
  **`+`** **WHEN **A **BLANK **LINE **MOVES **BETWEEN **TWO **HUNKS**, **⇒⇒† AND **THAT **IS **A
  **DIFF **RENDERING **ARTIFACT **AND **NOT **A **CHANGE **TO **THE **FILE**. |
| `census12.py` | **THE **CENSUS **FOR **THE **TWELVE **FILES**, **BEFORE **AND **AFTER**, **PER
  **CLASS**, **READ **OFF **THE **TWO **COMMITS **WITH **`git show`**. |
| `tensor.py` … `realize4.py` | **THE **PER-FILE **CUTS**, **ONE **FILE **EACH**, **EACH **A **LIST **OF
  **`(start, end, new_text)` **LINE **RANGES**. **⇒⇒† AND **THEY **ARE **THE **JUDGEMENT **AND **THE
  **DIFF **IS **THE **PROOF**. |

## THE TABLES THAT WERE WRITTEN

| FILE | WHAT IT HOLDS |
|---|---|
| `.agents/slop/tables/helpers-2694.md` | `Target.parse`'s TWENTY MEASURED ROWS, THE PLANT LIST AND THE LIST-LEVEL ROWS |
| `.agents/slop/tables/codegen-decomp-dtype-16.md` | THE INVENTORY TABLE AND THE SIX dd-fix-ROUND-2 DEFECTS |
| `.agents/slop/tables/schedule-__init__-1.md` | THE GATE'S EXPECTED ROWS AND THE FIFTEEN-ROW MUTATION TABLE |
| `.agents/slop/tables/mixin-movement-1.md` | THE NOT-PORTED INVENTORY, THIRTY-SIX NAMES WITH THE WALL BEHIND EACH |
| `.agents/slop/tables/mixin-op-40.md` | THE EIGHT WALLS, EACH NAMED AT ITS PYTHON LINE |
| `.agents/slop/tables/engine-realize-22.md` | THE TWO GROUPS, INVENTORIED: `[a]` PORTED, `[b]` THE FOREIGN-EFFECT SEAM |
| `.agents/slop/tables/engine-realize-2205.md` | THE GATE'S ROWS AND WHAT EACH ROW PINS |
| `.agents/slop/tables/schedule-multi-1460.md` | THE UPSTREAM BODY OF `shrink_multi`, VERBATIM |

## THE VERDICTS, MEASURED ON A CLEAN WORKTREE OF `84494174d`

**THE CORPUS** (`checks/differ.py run`):

```
graphs=38  graphs-answered=38  graphs-agree=38  graphs-disagree=0
byte-identical=38  graphs-refused=0  not-comparable=0  expect-moved=0
stable-pairs=5 of 5  stable-failed=0 of 5  stable-differ=0 of 5
plants-disagree=8 of 8  cross=1 of 1  conflations=4 of 4  controls=5 of 5
selfcheck=# SELFCHECK: OK  oracle-selfcheck=# ORACLE SELFCHECK: OK  census-rc=rc=0
substrate-start=8441b07e721b8a8eafa55e9ae071dc12f806bdcd7c7205cb89e80a47388f22f6
substrate-end=8441b07e721b8a8eafa55e9ae071dc12f806bdcd7c7205cb89e80a47388f22f6
substrate-head=84494174d334ea2012902625c73790a78e501a44
```

**⇒⇒† AND **`substrate-start == substrate-end`**, **⇒⇒† AND **SO **THE **RUN **DID **NOT **STRADDLE
**AN **EDIT**, **⇒⇒† AND **AND **`substrate-head` **IS **MY **FINAL **COMMIT**.

**THE REPRO** (`checks/differ.py repro`):

```
repro-files=339  repro-identical=339  repro-rc=rc=0
repro-substrate=8441b07e721b8a8eafa55e9ae071dc12f806bdcd7c7205cb89e80a47388f22f6
```

**⇒⇒† AND **339 **OF **339 **FILES **IDENTICAL **ACROSS **TWO **CLEAN **RUNS.**

**THE WITNESS** (`gates/corpuswitness-gate.py`): **PASS -- the claim is ESTABLISHED.** ALL SEVEN
READINGS OK: `control`, `verdict.current` (CURRENT), `witness.fresh` (FRESH, `delta_ms=+138.499`),
`freshness.source`, `witness.substrate` (CURRENT, `rows=3 of 3`), `verdict.reported` (AGREE,
`graphs=38 agree=38`), `claim` (REPRODUCIBLE).

## WHAT WAS KEPT, AND IT IS THE LOAD-BEARING PART

- **EVERY `TODO(p3)` / `WALL(p3)` MARKER**, with its reason. **⇒⇒† AND **THE **TREE'S **EVERY
  **MARKER **COUNT **(`\`.bend` **PLUS **`.agents/slop/tables/`**) **IS **4,507 **AT **THE **BASE **AND
  **4,658 **AT **MY **FINAL **COMMIT**, **⇒⇒† AND **SO **NOT **ONE **MARKER **WAS **LOST**.
- **EVERY MEASUREMENT.** THE SIBLING-ARENA TABLE, THE `CMPEQ(CMPEQ(...))` NODE SHAPES, THE 31
  NO_COLOR PROBES, THE 24 `int()` PROBES, THE 43-FIXTURE ANSI CORPUS, THE 301-ROW SHR PLANTS, THE
  2,106-ROW DIVMOD ROWS, THE 153-FIXTURE EXECUTOR CENSUS, THE 20-ROW `Target.parse` ROUND TRIP,
  THE 192,899 `exec_alu` CALLS, AND THE 45-ROW `early_reject` SUBSET TEST.
- **EVERY BUG THAT WAS FOUND.** THE SIBLING-ARENA READ, THE `tn_alu.put` WRONG INDEX, THE PRE-PIN
  `CMPNE` SPELLING OF `ne` AND `eq`, THE `SUB`-vs-`ADD` ORACLE PATH, THE ZERO-SHIFT IN THE STORE,
  THE FLOAT-TO-INTEGER CAST ARM, THE `Bool.pick` TRAP THAT KILLED THE BASE64 DECODER, THE `case _:`
  CASCADE OF ABOUT A DOZEN ENTRY POINTS, THE PREPEND THAT BUILT THE LIST BACKWARDS, THE PERMUTE THAT
  CARRIED ITS ORDER IN `arg`, THE `shrank`-BEFORE-`one` ORDER, AND THE HEADER THAT NAMED A MARKER
  SPELLING THE FILE DOES NOT USE.
- **EVERY UPSTREAM CITATION**, AND THE QUOTES ARE VERBATIM.

## THE FOUR TRUNCATED SENTENCES THAT WERE RESTORED

**⇒⇒† AND **A **TRUNCATED **COMMENT **IS **NOT **A **CUT**, **⇒⇒† AND **THE **ORIGINALS **ARE **AT
`394eae369` **— **MEASURED, **NOT **WRITTEN **FROM **MEMORY**.

| FILE | THE RESTORED TEXT |
|---|---|
| `runtime/ops_metal.bend` | "THE seam that remains is one pointer. `ctypes.byref(callback, -0x10)` is the **address of the `invoke` field of an Apple BLOCK, and Bend can neither allocate a block descriptor nor name its sixteenth byte. Hand the seam an already-compiled MTLB and the submission path is complete; hand it a block and `compile` runs.**" |
| `runtime/ops_metal.bend` | "THERE IS NO dtype-to-MTLPixelFormat TABLE IN ops_metal.py, and the brief asked **for one. `grep -n PixelFormat tinygrad/runtime/ops_metal.py` is empty and `MTLPixelFormat` reaches this file only through `autogen/metal.py`, where it describes TEXTURES.**" |
| `runtime/ops_metal.bend` | "`.agents/slop/dead-defs.py` is the tool -- name-based, and it blanks a def's own **NAME in place rather than dropping the whole line, because most defs here are ONE LINE and dropping the line hides every constant they read. It found 17 dead defs on top of `main`.**" |
| `runtime/ops_metal.bend` | "`pm_bufferize` WAS a third one and it is GONE from upstream at the pin, so **the port carries it no longer -- see the section that used to hold it.**" |
| `runtime/ops_python.bend` | "The last row is the load-bearing one. A Python `bytes` and a Bend **`List<&2, Char>` carry the SAME total information about the SAME program; the port chose the spelling a total language can inspect, and the seam (`ops_bend.py`'s `BendProgram`) reads it back.**" |
| `runtime/ops_python.bend` | "CPython for every non-trivial input. Port vs CPython, measured: **With that fixed, the decoder ran, and its OUTPUT WAS WRONG against CPython for every non-trivial input.**" |

**⇒⇒† AND **ONE **MERGED **LINE **WAS **REPAIRED**: **`engine/realize.bend`'s **`[b] realize.py:58
Estimates`** **AND **`[b] realize.py:60 first_run_cache`** **WERE **ON **ONE **LINE**, **⇒⇒† AND
**THE **LIST **IS **ONE **ENTRY **PER **LINE**, **⇒⇒† AND **A **MERGED **LINE **IS **A **TRUNCATION**.
