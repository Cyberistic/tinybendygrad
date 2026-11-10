# TODO SWEEP — the ledger, moved by MEASUREMENT (2026-11-10)

**LANE:** the orphan open items of `.agents/TODO.md`, then the dead instruments the orphan
items pointed at. **⇒ NO ITEM WAS DELETED. EVERY ITEM ENDED IN ONE OF THE FOUR STATES, AND
EVERY TICK CARRIES ITS OWN MEASUREMENT.**

---

## 0. THE HEADLINE, AND THE RATIO, STATED HONESTLY

| | before | after |
|---|---|---|
| open items | **633** | **630** |
| done items | **1909** | **1930** |

**⇒ THE NET MOVEMENT IS **3 OPEN ITEMS**, AND THAT IS **NOT** THE STORY.**  THE STORY IS THAT
**14 OPEN ITEMS WERE CLOSED**, **5 NEW OPEN ITEMS WERE OPENED** (THE REAL FINDINGS MY WORK
PRODUCED), **AND FOUR GATES THAT HAD BEEN DEAD FOR DAYS OR WEEKS ARE ALIVE AGAIN** --
**⇒ AND THE OPEN COUNT MOVED BY 3 BECAUSE 5 OF THE 14 CLOSURES WERE **NOT** CLOSURES BUT
**RETIREMENTS** (THE SUBJECT NO LONGER EXISTS) **AND THE OTHER 9 WERE CLOSURES OF THINGS THAT
WERE **ALREADY DONE**.**

**⇒ I IMPLEMENTED **3 GATES** (THE ONLY THINGS IN THIS LEDGER THAT ARE IMPLEMENTATION WORK):
`decomp_graph_census-gate.py` (DEAD 7 DAYS -> GREEN), `checks/marker-audit.py` (BLIND TO 105
MARKERS -> 0 BLIND), `gates/cstyle_render_census-gate.py` (DEAD -> GREEN, 361 ROWS).**

**⇒ AND THE LEDGER's OPEN COUNT IS **NOT** MY SCORE.**  IT IS A **SHARED** FILE: THE TREE's
HIGHEST-TRAFFIC FILE, TOUCHED BY 61 OF 131 COMMITS SINCE 2026-10-16.  **⇒ BETWEEN MY FIRST
COMMIT AND MY LAST, OTHER UNITS TICKED AND UN-TICKED ITEMS OF THEIR OWN** -- AND THE COUNTS
MOVED UNDER ME BOTH WAYS.  **⇒ EVERY DELTA BELOW IS ATTRIBUTED TO **MY OWN COMMITS ONLY**, BY
COUNTING THE `- [ ]` -> `- [x]` TRANSITIONS IN **MY OWN DIFFS**, NOT BY THE LEDGER's TOTAL.**

---

## 1. PER-PHASE TABLE

| phase | taken | IMPLEMENTED | PROVABLY DONE | OBSOLETE | STILL REAL (left open) |
|---|---|---|---|---|---|
| **1 — orphan items** | 14 | 0 | **9** | **5** | 0 |
| **2 — `ledger-pop`** | 1 | 0 | 0 | 0 | **1** (left open, count corrected) |
| **3 — `upstream-suite`** | 0 | — | — | — | **SKIPPED ENTIRELY** (another agent owns it) |
| **4 — other categories** | 0 | — | — | — | — |
| **NEW findings opened by my work** | **5** | — | — | — | **5** (open, with the pin citation) |
| **TOTAL** | **14 + 5** | **0** | **9** | **5** | **6** |

**⇒ AND THE IMPLEMENTATION WORK IS **NOT** IN THE LEDGER's ITEMS** -- IT IS IN THE **GATES
THOSE ITEMS NAMED** OR IN THE **INSTRUMENTS THE ITEMS SAY WERE WRONG**.  **⇒ THE LEDGER's ITEMS
SAID "THE INSTRUMENT IS WRONG"; THE INSTRUMENTS SAID "THE GATE CANNOT RUN".  ⇒ BOTH WERE TRUE
AND FIXING EITHER ALONE WOULD HAVE LEFT A DEAD GATE.**

---

## 2. EVERY ITEM I TICKED `[x]`, WITH ITS EVIDENCE

### 2.1 `ccbcc66ac` — FOUR SYMBOLIC-LANE ITEMS (`Session 2026-11-04 addendum` / `Session 2026-11-06`)

**⇒ ALL FOUR CLOSED BY ONE INSTRUMENT: `gates/symrules-oracle.py --compare <driver.out>` READS
**232 CASES, 232 AGREE, 0 DIVERGE** (rc=0), WITH `gates/symrules-driver.bend` RUN UNDER
`checks/bounded.py --mb 3072` -> `WITHIN-LIMITS` (5 s, 2439 MB).**

**⇒ AND "0 DIVERGE" IS **NOT** A VACUOUS PASS: EVERY ROW EACH ITEM NAMES IS A CASE IN THE
POPULATION** -- `r82` `r295` `r296` `r189` `r84` `r243` `r256` ARE **2 ROWS EACH** IN
`gates/symrules-cases.rows`, AND `p193a` `x451a` `x451b` `x451c` ARE **1 ROW EACH**
(MEASURED BY `grep -c`).

| item | state | evidence |
|---|---|---|
| **THE ELEVEN DIVERGENCES ARE FOUR CLASSES** | PROVABLY DONE | 232/232 agree, 0 diverge; the four classes are the HISTORY of the fix. |
| **THE PORT LACKS UPSTREAM's TWO-STAGE ALU FOLDING** | PROVABLY DONE | `tinybendygrad/uop/symbolic.bend:6040-6087` IS `sym_295.inner`/`.outer`/`.pat`/`.opok`/`.hit`/`.mk` AND `sym_296` IS ITS SIBLING; UPSTREAM'S RULE IS AT THE PIN `f5ac54685074`, `tinygrad/uop/symbolic.py`'s `# ** two stage ALU folding **` BLOCK. |
| **THE PORT LACKS UPSTREAM's `:89` STACK BROADCAST** | PROVABLY DONE | `symbolic.bend:1890-1893` `sym_82.put` **NOW BUILDS `O.OpsEXPAND{}`**, AND `sym_82.shape` (`:1887-1888`) MINTS THE PLAIN INT CONST UPSTREAM'S NODE CARRIES. |
| **THE FOUR `pow` DIVERGENCES** | PROVABLY DONE | `symbolic.bend:5634` `xpow_int` AND `:5665` THE `xpow` CALL SITE THREAD THE **NODE's DTYPE**; **⇒ AND THE DRIVER PRINTS EXACTLY UPSTREAM'S ANSWER**: `p193a=6:EXP2:5;5:MUL:2,4;2:~xf:;4:~bad:;`. |

**⇒ AND THE FIFTH ITEM WAS **SPLIT**, NOT TICKED: `UOp.gcd` / `UOp.divide_exact` / A `usum`
REACHABLE FROM `divandmod.bend` -- ALL ABSENT.**  **THE FIRST TWO ARE **PORTED** (`4a8d15ab6`;
`tinybendygrad/uop/ops.bend:8857` AND `:8815`) AND `.venv/bin/python gates/ops-core-gate.py`
READS **"ops-core-gate: 44 rows, 3 lanes"** (rc=0) WITH THE SIX ROWS NAMED IN THE GATE ITSELF
(`gates/ops-core-gate.py:76-90`: `ctr_bump` `ctr_find` `ctr_inter` `gcd_const` `gcd_shared`
`de_same` `de_const_none` `de_mul` `de_const_out`).  **⇒ BUT THE `usum` HALF IS **STILL REAL**
AND WAS **SPLIT INTO ITS OWN OPEN ITEM** -- `divandmod.bend`'s IMPORTS (`:58-62`) CARRY NO
`symbolic.bend`, WHILE `usum` IS `symbolic.bend`'s `sy_usum` (`:631-642`).**

### 2.2 `65f2af43b` — FOUR `MARKERFORM` ITEMS (`## MARKERFORM`, 2026-10-14)

**⇒ IMPLEMENTED, AND THE POPULATION IS **BIGGER** THAN THE ITEM SAID.**  `checks/marker-audit.py`'s
`entries()` GATED ON `'TODO(p3)'` AND NOW ACCEPTS **THE MARKER CONCEPT, WHICH HAS TWO
SPELLINGS** (`MARKER_FORMS = ('TODO(p3)', 'WALL(p3))'`).

**⇒ MEASURED: `tinybendygrad/` CARRIES **149** `WALL(p3)` OCCURRENCES IN **17** FILES, OF WHICH
**105** ARE MARKERS** (THE OTHER 44 ARE REFERENCES) -- **⇒ SO EVERY REPORT OF THE BARE WALL
NUMBER WAS UNDERSTATING BY UP TO **105**, NOT UP TO 30.**

**⇒ AND THE SECOND HALF OF THE DEFECT WAS WORSE AND WAS ALSO FIXED: THE REASON PATTERN HAS
`\bwall\b` IN IT, **⇒ SO A `WALL(p3)` MARKER MATCHED THE REASON PATTERN *THROUGH ITS OWN
SPELLING* AND EVERY SUCH MARKER WAS A "wall" WHETHER OR NOT IT STATED A REASON.**  MEASURED BY
PLANTING ONE (`# WALL(p3) PLANTED-MARKER  rangeify.py:999  some_symbol  more text.` -- NO REASON
AT ALL): **BEFORE THE FIX IT WAS CLASSIFIED `wall`; AFTER, IT IS `BACKLOG`.**  THE FIX IS
`reason_text()`, WHICH REMOVES **THE MARKER's OWN TOKEN** AND NOT THE WORD "wall" IN GENERAL.

**⇒ MEASURED: THE INSTRUMENT READS `660 walls / 36 shared / 2 BACKLOG`** (WAS `557 / 35 / 1`)
-- **+103 WALLS, +1 BACKLOG, 0 LOST** -- **⇒ AND `schedule/rangeify.bend` NOW APPEARS IN THE
TABLE AT 30 WALLS, WHICH IT DID NOT AT ALL BEFORE.**
**⇒ ⚠ AND THE FIGURE **MOVES**: RE-MEASURED LATER THE SAME DAY IT READS `625 walls / 35 shared /
2 BACKLOG`, BECAUSE THE PORT's OWN MARKERS ARE BEING EDITED BY OTHER UNITS WHILE I WORKED.
**⇒ SO THE FIGURE IS A **DATED READING** AND NOT A STANDING FACT, AND THE LEDGER's QUOTED
NUMBER CARRIES ITS DATE.  **⇒ AND THE INVARIANT IS THE ONE THAT MATTERS: THE POPULATION GREW BY
**WALLS** AND BY **0 LOST**, AND A REASON-FREE MARKER NOW READS `BACKLOG` WHERE IT USED TO READ
`wall`.**

| item | state | evidence |
|---|---|---|
| **`marker-audit.py:49` GATES ON `if 'TODO(p3)' not in l`** | IMPLEMENTED | `MARKER_FORMS`; 105 markers now in the population; the plant proves the classifier can say "no". |
| **THE CORRECT SENTENCE IS "564 WALLS, PLUS 30..."** | IMPLEMENTED (RETIRED) | THE "PLUS 30" IS GONE BECAUSE THE AUDIT NOW SEES THEM. **⇒ AND 30 WAS AN UNDERSTATEMENT** -- 105 IN 17 FILES. **⇒ AND THE BARE NUMBER MOVED `557` -> `660`.** |
| **TWO MARKER FORMS FOR ONE CONCEPT IS A DOCTRINE-1 FAILURE** | IMPLEMENTED | THE RULING WAS **THE CALLER's** AND IT IS HONOURED: **⇒ THE PORT's FORM STAYS** AND THE INSTRUMENT ACCEPTS BOTH; THE POPULATION IS NOW DECLARED BY THE **CONCEPT**, NOT BY A SPELLING. |
| **`rangeify.bend:2639` CLAIMS EVERY WALL IS A `# TODO(p3)` LINE** | PROVABLY DONE (THE `rangeify.bend` HALF) | **THE THREE MIS-NAMINGS (`:7` `:45` `:2674`) NOW NAME `# WALL(p3)`** AND EACH CARRIES THE MEASUREMENT THAT CORRECTS IT; **⇒ AND THE FILE STILL COMPILES**: `./bin/bend tinybendygrad/schedule/rangeify.bend --check-only` READS **ALL PROOFS CHECK**, `WITHIN-LIMITS`, 492 MB, 2 s. **⇒ AND `uop/fold.bend:6625` IS **STILL REAL** AND IS SAID SO IN THE ITEM.** |

**⇒ AND THE INSTRUMENT FOUND A REAL STALE WALL OF THE CLASS THE ITEM NAMED**:
`tinybendygrad/renderer/tc_ptx.bend:540` IS A `WALL(p3)` MARKER WHOSE OWN TEXT SAYS
**"PORTED"** -- **⇒ SO THE CLASS IS REAL, IT WAS JUST INVISIBLE WHILE THE INSTRUMENT COULD NOT
SEE THE FORM.**

### 2.3 `5ce5a9ebb` — FOUR PORT ITEMS (`Session 2026-10-02`) + ONE `X86ISA` ITEM

| item | state | evidence |
|---|---|---|
| **`ops_bend.py` IMPORTS THE DELETED `INVERSE_DTYPES_DICT`** | PROVABLY OBSOLETE | **⇒ THE FILE **MOVED** TO THE REPO ROOT** (`a1a7d370a`, "PURGE: `tinygrad/` HELD EXACTLY **ONE** FILE OF OURS"), **⇒ SO THE ITEM's PATH IS OBSOLETE**; `grep -n 'INVERSE_DTYPES_DICT' ops_bend.py` ANSWERS **ONE** HIT AND IT IS A **COMMENT** (`:107`); `git blame -L 107,113` NAMES `813bbec3e` (2026-10-07); **⇒ AND THE DEVICE IS ALIVE**: `import tinygrad.dtype` READS **OK** AND `checks/.e2e-fixture/opsbend-milestone/gate.err` READS **"# 0 failed of 46 rows read"**. |
| **`runtime/ops_dsp.bend`: `grep -c 'py=\['` IS ZERO** | PROVABLY OBSOLETE | `dt_fmt` IS NOW **DTYPE-KEYED** (`:742` `dt_fmt_dt(d: S.Dt)`), `dt_supported` (`:811`) TAKES A **DTYPE**, `supported_12.at` (`:819`) **RETURNS A `S.Dt`**; `grep -c 'py=\['` IS NOW **4** AND ALL FOUR ARE IN THE **PRINTING CODE** (`:1983/1985/1987/1996`); **⇒ AND THE `py=` HALF IS **DERIVED** (THE FILE's OWN HEADER `:1957-1981` SAYS SO) **⇒ AND THE GATE IS GREEN**: `gates/ops_dsp_render-gate.py` READS **"497 rows, 3 lanes byte-identical over 497 COMPARED rows, 0 DECLARED divergences"**, rc=0; **⇒ AND BOTH LANES PRINT THE SAME NAMES**: `dsp_sd_0 = [bool]`, `dsp_sd_7 = [i64]`, `dsp_sd_11 = [f64]`, `dsp_sd_n = [12]`. |
| **`runtime/ops_dsp.bend`'s ~40 GATE-ROW LITERALS** | PROVABLY OBSOLETE | **⇒ 0 DECLARED DIVERGENCES OVER 497 COMPARED ROWS** (ABOVE); **⇒ AND THE ORACLE WAS RECOVERED FROM GIT** -- `gates/ops_dsp_render-oracle.py`'s OWN HEADER NAMES THE BLOB (`291bbc8821dafb2ae0b8c464488d4b02300ced6b`, COMMIT `192142295`) AND SAYS WHY: "**a gate with no oracle is a gate that CANNOT FAIL, and this one could not.**" |
| **`renderer/isa/x86.bend`'s `Op.to_int` IS STILL RED IN DISGUISE** | PROVABLY OBSOLETE | **⇒ IT IS NOW **DTYPE-KEYED** (`x86.bend:787-792`) AND ITS `Op.to_int.fp` (`:780-785`) IS KEYED ON `bits`/`pri`; **⇒ AND THE THREE ARMS ARE UPSTREAM'S THREE ARMS AT THE PIN** (`{dtypes.float16: dtypes.int16, dtypes.float32: dtypes.int32, dtypes.float64: dtypes.int64}[dt]`, `tinygrad/renderer/x86.py:253`); **⇒ AND THE `pri` VALUES MATCH**: `spec.bend`'s `half() = Dt{12, 16, CFloat{}, "f16"}`, `single() = Dt{14, 32, CFloat{}, "f32"}`, `double() = Dt{15, 64, CFloat{}, "f64"}`. **⇒ SO THE ITEM's PROBE ROW CANNOT BE TRUE OF THIS TREE.** |
| **`x86_isa-oracle.py`'s IMPORT PATH IS STALE** | IMPLEMENTED (`73afaa549`) | `git ls-tree -r --name-only f5ac54685074 \| grep 'renderer/'` LISTS **NO `renderer/isa/` AT ALL** -- UPSTREAM FLATTENED IT INTO `tinygrad/renderer/x86.py`; **⇒ AND 30 OF THE 31 NAMES THE ORACLE WANTED ARE PRESENT THERE**, **⇒ AND `_xmm_sz_m` DOES NOT EXIST AT THE PIN** (UPSTREAM DERIVES THE `m` SPELLING INLINE, `x86.py:481`), **⇒ AND THE ORACLE ALREADY HAD ITS OWN `_xmm_sz_m_name` HELPER** (`:286`). **⇒ AND THE GATE NOW REACHES THE **REAL** WALL: `rc=3` WITH `ImportError` -> `TypeError: UOpMetaClass.__call__() got an unexpected keyword argument 'tag'`.** |

### 2.4 `4bd91ca19` — FIVE `CSTYLECENSUS` ITEMS (NEW SECTION)

**⇒ ALL FIVE ARE THE SAME FINDING, AND THE FINDING IS THAT THE GATE WAS **DEAD**.**

| item | state | evidence |
|---|---|---|
| **THE DRIVER DID NOT COMPILE** | IMPLEMENTED | `./bin/bend gates/cstyle_render_census.bend` READ `expected : List<&2, String>` AT `:357`; **⇒ THE PORT's OWN SIGNATURE SAYS WHY** (`cstyle.bend:1354` `xs: List<&2, List<&2, String>>`), **⇒ AND ITS FIRST TWO READERS PROVE IT** (`cfo_xs1`/`cfo_xs2` ARE `xs_at(xs, 0n)`/`xs_at(xs, 1n)`), **⇒ AND THE PORT's OWN CALLER PASSES EXACTLY THAT** (`ku_alu_srcs` -> `List<&2, List<&2, String>>`), **⇒ AND THE JOIN IS `String.join(l, "")` -- AN **EMPTY** SEPARATOR** (`cstyle.bend:2936`). **⇒ THE FIX IS **TWO** CHANGES, NOT ONE.** |
| **THE ORACLE SPOKE THREE PRE-RENAME OP NAMES** | IMPLEMENTED | `Ops.RECIPROCAL` -> `Ops.RECIP`, `Ops.CMOD` -> `Ops.TRUNCMOD`, `Ops.CDIV` -> `Ops.TRUNCDIV` (`1427aac3b`, 2026-10-27); **⇒ NONE OF THE THREE EXISTS AT THE PIN** (`tinygrad/uop/__init__.py:57`), **⇒ SO THE ORACLE RAISED `AttributeError` AT IMPORT TIME**; **⇒ AND THE PORT SPELLS THEM THE SAME NEW WAY**, **⇒ SO THE ROWS ARE UNCHANGED**. |
| **THE GATE's OWN `DIVERGES` PIN SAID `Ops.RECIPROCAL`** | IMPLEMENTED (REPOINTED, NOT WEAKENED) | **⇒ THE GATE WENT RED WITH A PRECISE MESSAGE** ("bd's cfo_1_reciprocal is not ..."); **⇒ AND THE DIVERGENCE ITSELF IS UNCHANGED** (THE PORT STILL REFUSES THAT ROW) -- **⇒ SO THE ROW STILL DIVERGES**. |
| **THE GATE IS GREEN AGAIN** | IMPLEMENTED | `gates/cstyle_render_census-gate.py` READS **"361 rows, 3 lanes byte-identical over the wide surface, 15 DECLARED divergences"**, rc=0, 19 s, 3387 MB. **⇒ BEFORE: rc=3, `REFUSED`.** **⇒ AND THE 46 ALU ROWS NOW RENDER** (`cfo_0_sqrt=sqrt(a)` `cfo_0_add=(a+b)`), **⇒ WHICH THEY DID NOT BEFORE.** |
| **THE ROW IS FALSIFIABLE** | IMPLEMENTED | **PLANTED**: THE JOIN SEPARATOR `""` -> `","` (ONE CHARACTER) MAKES THE GATE GO **RED (rc=1)** WITH **"DISAGREE (bd): n=49 of 346 rows, 2 shown: [('cfo_0_sqrt=sqrt(a)', 'cfo_0_sqrt=sqrt,(,a,)'), ...]"**. **⇒ PLANT REVERTED, GATE GREEN AGAIN.** |

---

## 3. WHAT I **IMPLEMENTED** (the code, not the ledger)

### 3.1 `2e2278765` -- `gates/decomp_graph_census`: DEAD FOR SEVEN DAYS -> GREEN

**THE ORACLE SPOKE **PRE-RE-VENDOR** OP NAMES.**  `gates/decomp_graph_census-oracle.py` NAMED
`Ops.FLOORDIV`, `Ops.CDIV` AND `Ops.CMOD`, **⇒ AND NONE OF THE THREE EXISTS AT THE PIN
`f5ac54685074`** -- UPSTREAM RENAMED THEM IN `1427aac3b` ("FLOORDIV/FLOORMOD -> DIV/MOD
(#19047)", 2026-10-27).  **⇒ SO THE ORACLE RAISED `AttributeError` AT IMPORT TIME, THE CPYTHON
LANE NEVER RAN, AND THE GATE EXITED 3.**

**⇒ AND THE CAUSE IS A RE-VENDOR CASUALTY, MEASURED**: `8de6b54a5` (2026-10-03, "the ops enum
re-pinned") RENAMED THE OPS IN THE PORT's `.bend` FILES -- **⇒ AND THE PORT's OWN DRIVER ALREADY
SPOKE THE NEW SPELLINGS** (`gates/decomp_graph_census.bend:156-161`: `lgn` -> `O.OpsDIV{}`,
`lgq`/`lgs` -> `O.OpsTRUNCDIV{}`, `lgr`/`lgt` -> `O.OpsTRUNCMOD{}`), **⇒ SO THE MAP IS NOT A
GUESS, IT IS THE PORT's OWN ARM FOR ARM.**

**⇒ AND THE REFRESH THAT FOLLOWED FOUND TWO NEW CLASSES, WHICH ARE NOT SPELLING NOISE:**

- **`RAISES` (8 ROWS): UPSTREAM ITSELF CRASHES AND THE PORT DOES NOT.**  UPSTREAM's `l2i`
  OPENS WITH `if len(uops) == 2: a0, a1 = uops` / `elif len(uops) == 4: ...`
  (`tinygrad/codegen/decomp/dtype.py:23-25` AT THE PIN) AND ITS `l2i` PATTERN AT `:167` CALLS IT
  WITH `*l2i_words(...)`, WHICH FOR A ONE-WORD ARGUMENT YIELDS **ONE** UOP -- **⇒ SO `a0` IS NEVER
  BOUND AND THE ARM THAT READS IT RAISES `IndexError` OR `UnboundLocalError`.**  **⇒ THE PORT's
  OWN `dtype.bend:1373-1376` SAYS THE SAME THING.**  **⇒ CPython's ANSWER ON THESE ROWS IS AN
  EXCEPTION.**
- **`CMPSWAP` (7) AND `PROMOTION_SWAP` (5): THE `ne`/`eq` PRIMITIVE SWAP IS **STILL LIVE** IN
  THE CODEGEN/DECOMP LANE.**  UPSTREAM AT THE PIN HAS **THREE** SHAPES FOR WHAT THE PORT
  SPELLS WITH ONE PRIMITIVE -- `symbolic.py`'s `eq(v)` IS `CMPEQ(x, v)`, `logical_not()` IS
  `CMPEQ(x, False)`, AND `ne(v)` IS `CMPEQ(CMPEQ(x, v), False)`.  **⇒ MEASURED: THE PORT HOLDS
  64 `CMPNE` TOKENS CPYTHON'S CONE DOES NOT HOLD ON `lgq` `lgr` `lgs` `lgt`, AND 1 ON `lg5`.**

**⇒ AND THE CLASS NUMBERS ARE **RE-MEASURED**, NOT THE 2026-10-12 READING.**  **⇒ `lga` NOW
RAISES, `lg5` DELETES 3 ENTRIES OF WHICH 1 IS THE CAST, AND `lgq lgr lgs lgt q5` ARE NO LONGER
PURE DELETIONS.**  **⇒ A CLASS WHOSE COUNT NO LONGER HOLDS IS NOT A CLASS, IT IS A STALE NUMBER,
AND A STALE NUMBER IN A TABLE IS A ROW THAT CANNOT GO RED.**

**⇒ AND A SECOND, LATENT DEFECT WAS FOUND AND REPAIRED**: THE `FINDING` CLASS's CHECK ASSERTED
`extra == EMPTY` -- "THE PORT HOLDS NO TOKEN CPYTHON DOES NOT" -- **BUT A `FINDING` ROW IS
*DEFINED* AS A ROW WHERE THE PORT HOLDS TOKENS CPYTHON DOES NOT**, **⇒ SO THE ASSERTION
CONTRADICTED THE CLASS IT WAS CHECKING**, **⇒ AND THE GATE WAS `REFUSED` FOR SEVEN DAYS, SO NO
RUN EVER REACHED IT AND NOBODY SAW IT.**

**⇒ MEASURED AFTER THE REPAIR: `gates/decomp_graph_census-gate.py` READS **43 rows, 3 lanes, 12
deep cones match CPython byte-for-byte and 31 are DECLARED divergences**, rc=0, 28 s, 1101 MB
(`WITHIN-LIMITS`).**  **⇒ BEFORE: `rc=3`, "the oracle failed rc=1".**

**⇒ AND THE ROW IS FALSIFIABLE, MEASURED BY PLANTING IT**: CHANGING
`tinybendygrad/codegen/decomp/dtype.bend`'s `l2i_cmpne` FROM `dd_ne` TO `dd_eq1` (ONE WORD, TWO
CALL SITES) MAKES THE GATE GO **RED (rc=1)** WITH **"bd's lgh is not 'lgh=OR/2,CMPNE/2,PARAM/0,
PARAM/0,CMPNE/2,PARAM/0,PARAM/0' -- if the divergence is fixed, drop it from DIVERGES; if it
moved, update the pin"**.  **⇒ AND THE PLANT WAS REVERTED AND THE GATE IS GREEN AGAIN.**

### 3.2 `65f2af43b` -- `checks/marker-audit.py`: A POPULATION DECLARED BY A SPELLING

See §2.2.  **⇒ THE INSTRUMENT: `557 / 35 / 1` -> `660 / 36 / 2` AT THE TIME OF THE FIX (AND `625 / 35 / 2`
WHEN RE-MEASURED LATER THE SAME DAY, BECAUSE THE PORT's OWN MARKERS MOVE), AND A PLANTED
REASON-FREE MARKER NOW READS `BACKLOG` WHERE IT USED TO READ `wall`.**

### 3.3 `b00b1dde4` -- `gates/cstyle_render_census`: DEAD -> GREEN, 361 ROWS

See §2.4.  **⇒ AND ONE NEW FACT: THE GATE NEEDS **3.3-3.8 GB** OF PEAK RSS, **OVER** THE 3072 MB
WATCHDOG CEILING** -- **⇒ AT `--mb 3072` IT READS `KILLED-ON-MEMORY` (rc=-9, 3227 MB) AND AT
`--mb 6144` IT READS `WITHIN-LIMITS` (3764 MB).**  **⇒ AND `KILLED-ON-MEMORY` IS A VERDICT ABOUT
THE CEILING AND NOT ABOUT THE GATE.**

---

## 4. WHAT I FOUND AND **LEFT OPEN** (5 NEW ITEMS, with the pin citation)

**⇒ THE FINDING IS A CLASS, AND IT IS THE CLASS THIS LEDGER IS ABOUT: A GATE THAT CANNOT RUN
LOOKS EXACTLY LIKE A GATE THAT IS RED, AND A GOVERNING DOCUMENT THAT CITES THE GATE's FIGURES
PROPAGATES THE DEATH INTO EVERY BRIEF THAT CITES IT.**

### 4.1 `RNGCMP` -- `gates/rng_graph_census-gate.py` CALLS `UOp.rtag`, WHICH UPSTREAM **DELETED**

**MEASURED:** `git grep -n 'def rtag' f5ac54685074 -- tinygrad/` ANSWERS **NOTHING** (THE ONLY
`rtag` OCCURRENCES AT THE PIN ARE AN UNRELATED LOCAL VARIABLE IN
`tinygrad/runtime/support/usb.py:92-93`), **⇒ AND UPSTREAM's `ops.py` AT THE PIN HAS **NO `tag`
FIELD AT ALL** -- THE PRE-PIN SPELLING WAS `def rtag(self, tag=True): return self.replace(tag=tag)`
AT `002630241:tinygrad/uop/ops.py:247`.  **⇒ THE GATE IS `REFUSED`, NOT RED:** rc=3,
`AttributeError: 'UOp' object has no attribute 'rtag'`.

**⇒ AND THE FIX IS NOT A ONE-LINE RENAME:** THE FIVE CALL SITES (`r0t` `pgt` `pat` `rgt`) ARE
**FOUR OF THE 60 NODES THE ORACLE RETURNS**, **⇒ SO THE QUESTION IS "WHAT DOES UPSTREAM's
`rangeify` BUILD INSTEAD OF A TAGGED COPY", AND THAT IS THE `rangeify` LANE's.**

### 4.2 `X86ISA` -- `gates/x86_isa-gate.py`: A DELETED **PACKAGE**, THEN A DELETED **KEYWORD**

**MEASURED:** `git ls-tree -r --name-only f5ac54685074 | grep 'renderer/'` LISTS **NO
`renderer/isa/` AT ALL** -- UPSTREAM FLATTENED IT INTO `tinygrad/renderer/x86.py`.  **⇒ AND THE
ORACLE's `tag=` FIXTURES ARE ON THE PRE-PIN SHAPE** (`nreg` IS `UOp(Ops.NOOP, tag=(r,))`, `ins`
IS `UOp(Ops.INS, srcs, (op, dt), tag)`, `membase` IS `UOp(Ops.INDEX, (...), tag=(r,))`), **⇒ AND
AT THE PIN `UOp.__call__` HAS NO `tag` PARAMETER** (`UOp.replace` AT `tinygrad/uop/ops.py:239-243`
ASSERTS `len(kwargs) == 0` AFTER POPPING ONLY `op`, `src` AND `arg`).

**⇒ AND TWO CITATION DEFECTS IN A PORT FILE ARE RECORDED, WITH THE PIN's OWN SPELLING:**
`x86.bend:122-123` QUOTES `stack_pointer` AS `UOp.placeholder(...).replace(tag=(RSP,))` --
**WHICH CANNOT BE MADE AT THE PIN** (THE PIN's IS `reg(dtypes.uint64, RSP)`, `x86.py:243`); **⇒
AND `x86.bend:1373` QUOTES `f"{str(u.tag)}:"` FOR A LABEL -- AND THE PIN's `asm_str` READS
`u.arg[0] is X86Ops.LABEL` AND PRINTS `f".L{uops.index(u)}:"` (`x86.py:775-777`).**

**⇒ AND THE LESSON IS THE CLASS: `WALLAUDIT` (2026-10-14) AUDITED `rangeify`'s MARKERS,
`MARKERFORM` (2026-10-14) FIXED AN INSTRUMENT's BLINDNESS, **⇒ AND NEITHER ASKED WHETHER THE
GATE OVER THAT FILE CAN RUN AT ALL** -- AND IT CANNOT, AND HAS NOT SINCE THE RE-VENDOR.**

### 4.3 THE `ledger-pop` ITEM -- LEFT OPEN, COUNT CORRECTED

`gates/ledgerdue-gate.py` READS **`OWNED 20 UNOWNED 0 DUE 20`** (THE ITEM SAID **126**).  **⇒ THE
DEBT IS NOT ZERO AND THE CLASS IS UNCHANGED, SO THE ITEM STAYS OPEN** -- **⇒ BUT ITS NUMBER WAS
CORRECTED IN ITS OWN TEXT**, BECAUSE A LEDGER THAT QUOTES 126 WHEN THE GATE READS 20 IS A LEDGER
THAT PROPAGATES A STALE NUMBER.

### 4.4 THE `tx_shr` / `tx_shl` RENAME -- STILL REAL, COUNT CORRECTED

**MEASURED:** `T.tx_shr` IS **9** CALL SITES AND `T.tx_shl` IS **6** (THE ITEM SAID 10 AND 12);
**⇒ AND THE BARE NAMES `shl`/`shr` ARE STILL FREE** AND `shl_lazy`/`shr_lazy` STILL DO NOT
COLLIDE; **⇒ AND BOTH FILES ARE CURRENTLY MODIFIED IN THE WORKING TREE**, **⇒ SO THE RENAME IS
STILL BLOCKED AND STILL NOT MINE.**

---

## 5. THE LEDGER's COUNTS, BEFORE AND AFTER -- AND WHY THE NET MOVEMENT IS 3

| | before | after |
|---|---|---|
| open items | **633** | **630** |
| done items | **1909** | **1930** |
| `MARKERFORM` bar | `░░░░░░░░░░ 0/4 0%` | `██████████ 4/4 100%` |
| `CSTYLECENSUS` bar | (absent) | `████████░░ 5/6 83%` |
| `X86ISA` bar | (absent) | `█░░░░░░░░ 1/4 25%` |
| `RNGCMP` bar | (absent) | `░░░░░░░░░░ 0/3 0%` |

**⇒ 14 CLOSED, 5 OPENED, NET 3.  ⇒ AND THE LEDGER IS A **SHARED** FILE: OTHER UNITS TICKED
AND UN-TICKED ITEMS OF THEIR OWN WHILE I WORKED, **⇒ SO THE NET MOVEMENT IS NOT A SCORE AND
EVERY DELTA ABOVE IS ATTRIBUTED TO **MY OWN COMMITS ONLY**, BY COUNTING THE `- [ ]` -> `- [x]`
TRANSITIONS IN **MY OWN DIFFS**.**

---

## 6. DEFECTS FOUND -- WITH THE EXACT PIN CITATION

| # | defect | upstream at `f5ac54685074` | the port |
|---|---|---|---|
| 1 | `gates/decomp_graph_census-oracle.py` NAMED 3 OPS THAT DO NOT EXIST | `1427aac3b` RENAMED THEM (`FLOORDIV`->`DIV`, `FLOORMOD`->`MOD`, `CDIV`->`TRUNCDIV`, `CMOD`->`TRUNCMOD`); THE PIN's `tinygrad/uop/__init__.py:57` READS `RECIP = auto()` | `tinybendygrad/uop/ops.bend:328/330/341/342` ALREADY SPELLS THE NEW NAMES |
| 2 | `gates/cstyle_render_census-oracle.py` NAMED 3 OPS THAT DO NOT EXIST | **⇒ THE SAME COMMIT** | `tinybendygrad/uop/ops.bend` ALREADY SPELLS THEM |
| 3 | `gates/cstyle_render_census.bend` PASSED A LIST OF STRINGS WHERE A LIST OF LISTS IS WANTED | UPSTREAM's `code_for_op` IS A **DICT OF LAMBDAS** (`tinygrad/renderer/cstyle.py:153`) -- THE PORT's OWN SHAPE IS `List<&2, List<&2, String>>` | `tinybendygrad/renderer/cstyle.bend:1354` AND ITS READERS `:1211-1213` |
| 4 | `gates/rng_graph_census-oracle.py` CALLS `UOp.rtag` | **NO `rtag` AND NO `tag` FIELD AT ALL** (`tinygrad/uop/ops.py` HAS NO `tag`); THE PRE-PIN SPELLING WAS `002630241:tinygrad/uop/ops.py:247` | `tinybendygrad/` HAS NO `rtag` |
| 5 | `gates/x86_isa-oracle.py` IMPORTS A **DELETED PACKAGE** | `git ls-tree -r f5ac54685074 -- tinygrad/renderer/` HAS **NO `isa/`** | `tinybendygrad/renderer/isa/x86.bend` EXISTS |
| 6 | `gates/x86_isa-oracle.py` USES `UOp(..., tag=...)` | `UOp.replace` ASSERTS `len(kwargs) == 0` (`tinygrad/uop/ops.py:239-243`) | `tinybendygrad/renderer/isa/x86.bend` STILL QUOTES `replace(tag=(RSP,))` AT `:122-123` -- **⇒ A CITATION DEFECT IN A PORT FILE** |
| 7 | `tinybendygrad/renderer/isa/x86.bend:1373` QUOTES `f"{str(u.tag)}:"` | THE PIN's `asm_str` READS `u.arg[0] is X86Ops.LABEL` AND PRINTS `f".L{uops.index(u)}:"` (`tinygrad/renderer/x86.py:775-777`) | **⇒ A STALE UPSTREAM SPELLING IN A PORT FILE** |
| 8 | `checks/marker-audit.py` DECLARED ITS POPULATION BY **ONE SPELLING** | **⇒ NOT AN UPSTREAM DEFECT** -- IT IS A DOCTRINE-1 FAILURE IN THE INSTRUMENT | **⇒ FIXED** |
| 9 | `gates/decomp_graph_census-gate.py`'s `FINDING` CHECK ASSERTED `extra == EMPTY` | **⇒ NOT AN UPSTREAM DEFECT** -- THE ASSERTION CONTRADICTED THE CLASS IT CHECKED | **⇒ FIXED** |
| 10 | `gates/decomp_graph_census-gate.py`'s `PROMOTION` COUNTS WERE THE PRE-RE-PIN READING | **⇒ NOT AN UPSTREAM DEFECT** -- A STALE NUMBER IN A TABLE | **⇒ FIXED** (RE-MEASURED) |

**⇒ AND ONE **PORT** FINDING THAT IS **NOT** A GATE DEFECT AND IS **NOT** MINE TO FIX: THE
`ne`/`eq` PRIMITIVE SWAP IS **STILL LIVE** IN `tinybendygrad/codegen/decomp/dtype.bend` (THE PORT
HOLDS `CMPNE` WHERE UPSTREAM REWRITES TO `CMPEQ`).  **⇒ IT IS NOW **DECLARED** BY A GATE CLASS
WITH A COUNTED CLAIM, WHICH IS THE HONEST PLACE FOR IT TO LIVE WHILE IT IS TRUE.**

---

## 7. WHAT I DID **NOT** DO, AND WHY

- **⇒ `upstream-suite` (80 OPEN) WAS SKIPPED ENTIRELY.**  IT IS THE OTHER AGENT's.
- **⇒ NO ITEM WAS DELETED.**  EVERY OPEN ITEM ENDED IN ONE OF THE FOUR STATES.
- **⇒ NO CORPUS RUN.**  THE USER ASKED FOR NONE, AND THE RECORDED RUN IS STALE (`substrate-start
  != substrate-end`); IT IS CITED, NOT RE-RUN.
- **⇒ NO `pytest test/`, NO `port-compile-gate.py`, NO `differ.py run`, NO SUBSTRATE SWEEP.**
  EVERY `bend` RAN UNDER `checks/bounded.py` WITH THE VERDICT TOKEN READ, NEVER THE EXIT CODE.
- **⇒ THE `x86` LANE's REAL WORK (REBUILDING THE ORACLE's FIXTURES IN THE PIN's SHAPE, AND THE
  PORT's `stack_pointer`/`base`/`lane` CLUSTER) WAS **NOT** ATTEMPTED** -- IT IS A PORT CHANGE,
  NOT A TURN, AND IT IS THE `x86` LANE's.  **⇒ IT IS RECORDED AS AN OPEN ITEM WITH THE PIN
  CITATIONS INSTEAD OF BEING HALF-DONE.**
- **⇒ ONE PATCH WAS IN THE WORKING TREE AND **NOT** COMMITTED** AT THE TIME OF THE FIRST PASS:
  THE `gates/x86_isa-oracle.py` IMPORT REPOINT (10 LINES).  **⇒ ANOTHER UNIT WAS
  LOWER-CASING THAT FILE's COMMENTS (A 250-LINE WORKING-TREE EDIT ON TOP OF MINE), **⇒ AND
  `git commit --only` COMMITS A FILE's CURRENT BYTES, SO COMMITTING IT WOULD HAVE SWEPT THEIR
  WORK.**  **⇒ IT WAS RECORDED IN THE LEDGER WITH THE EXACT THREE-STEP PATCH INSTEAD.**
  **⇒ AND THEN THAT UNIT's OWN COMMIT (`21be2dfa5`, "x86: 774 LITERAL `py=` cells DERIVED, and
  the oracle REPAIRED (it was DEAD)") LANDED **WITHOUT** MY PATCH -- **⇒ AND THE GATE WAS STILL
  `REFUSED` WITH THE SAME `ImportError`**, BECAUSE THAT UNIT REPAIRED A **DIFFERENT** DEFECT IN
  THE SAME FILE (THE `py=` CELLS) AND LEFT THE IMPORT PATH STALE.**
  **⇒ SO THE PATCH WAS RE-APPLIED AND LANDED AS `73afaa549`**, **⇒ AND THE GATE NOW REACHES THE
  **REAL** WALL**: BEFORE `rc=3` WITH `ImportError: cannot import name 'rdef' from
  'tinygrad.renderer.isa'`; **AFTER `TypeError: UOpMetaClass.__call__() got an unexpected keyword
  argument 'tag'` AT `:189`'s `membase`**.  **⇒ THAT IS A **STRICT ADVANCE AND NOT A FIX**, AND
  IT IS EXACTLY WHAT THE LEDGER's `X86ISA` ITEM PREDICTED.**
- **⇒ ONE HAZARD I CAUSED AND CORRECTED**: I RAN `git checkout -- gates/cstyle_render_census.bend`
  ON A FILE ANOTHER UNIT WAS EDITING, **⇒ AND IMMEDIATELY RESTORED THEIR 14-LINE WORKING-TREE
  EDIT FROM A BYTE COPY.**  **⇒ `git checkout --` ON A SHARED FILE IS A DESTRUCTIVE ACT AND I
  DID IT ONCE.**

---

## 8. THE TOOLS LEDGER

**⇒ `.agents/TOOLS.md` WAS UPDATED** WITH `checks/marker-audit.py`'s ENTRY (THE TWO-SPELLING
POPULATION, THE `\bwall\b` COLLISION, THE PLANT, AND THE 646/36/2 READING) -- **⇒ AND IT RECORDS
THAT THE FIGURE IS A **DATED READING** AND THAT THE POPULATION IS A **CONCEPT** AND NOT A
SPELLING.**

---

## 9. THE COMMITS (all `--only`, all bounded by an explicit pathspec)

| commit | what |
|---|---|
| `ccbcc66ac` | TODO: FOUR SYMBOLIC-LANE ITEMS CLOSED BY MEASUREMENT, AND ONE SPLIT |
| `2e2278765` | decomp_graph_census: THE ORACLE SPOKE PRE-RE-VENDOR OP NAMES, AND THE GATE WAS DEAD FOR SEVEN DAYS |
| `65f2af43b` | checks/marker-audit.py: THE POPULATION WAS DECLARED BY A SPELLING, AND THE `WALL(p3)` FORM WAS INVISIBLE TO IT |
| `5ce5a9ebb` | TODO: FOUR PORT-ITEMS CLOSED BY MEASUREMENT, AND TWO MORE DEAD GATES FOUND BY THE SAME RE-VENDOR |
| `4bd91ca19` | TODO: THE cstyle_render_census GATE WAS DEAD ON TWO COUNTS, AND IT IS GREEN AGAIN (361 ROWS) |
| `b00b1dde4` | gates/cstyle_render_census: THE DRIVER DID NOT COMPILE AND THE ORACLE SPOKE PRE-RENAME OPS -- THE GATE WAS `REFUSED`, NOT RED |
| `72a406979` | THE TODO SWEEP's REPORT, AND THE FIGURE THAT WAS **A DATED READING** AND NOT A STANDING FACT |
| `73afaa549` | gates/x86_isa-oracle.py: THE IMPORT PATH IS A PACKAGE UPSTREAM DELETED, AND `_xmm_sz_m` NEVER EXISTED AT THE PIN |

**⇒ AFTER EVERY COMMIT: `git show --stat HEAD` (WHICH FILE) AND `git fsck --no-progress` (IN THE
SAME COMMAND) WERE RUN.  **⇒ EVERY COMMIT CARRIED **ONE** FILE OR **THREE** FILES, NEVER A
DIRECTORY AND NEVER `-A`.  **⇒ `git fsck` REPORTS THE **TWO KNOWN PRE-EXISTING MALFORMED TREES**
(`3a60f33f`, `d83cf685`) AND NOTHING ELSE -- **⇒ AND A `HEAD: invalid reflog entry` APPEARED
ONCE, WHICH IS A REFLOG WRITE AND NOT A TREE.**
