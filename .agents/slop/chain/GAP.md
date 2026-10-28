# THE `Device` LANE's PAYOFF, AND THE **EXACT** GAP THAT IS LEFT

## THE CHAIN, AND EVERY HOP IS THE PORT's OWN

```
the port's own program          (realize.bend's `rz_built`,  MEASURED 23/23 AGREE)
  -> the port's own sink of AFTERs  (realize.bend's `rz_sink`)
  -> the port's own run_rangeify     (rangify.bend's `rr_*`,  MEASURED: the realize map AGREES)
  -> the port's own engine           (rangeify.bend's `eng_*`, SEVEN STAGES)
  -> the port's own schedule()       (schedule/__init__.bend:1139)
  -> THE KERNEL COUNT                (`.agents/slop/chain/chain.bend`'s `ch_lin_n`)
```

**⇒ MEASURED: `ch_lin_n=0` — THE PORT's OWN `schedule()` STILL ANSWERS **ZERO** KERNELS
FOR **THE PORT's OWN PROGRAM**, **⇒ SO THE CHAIN IS **NOT** YET CLOSED.**

## ⇒ ⇒ AND THE GAP IS **NOW MEASURED TO THE NODE**, AND IT IS **ONE STAGE**

**⇒ THE PORT's ENGINE'S OUTPUT (AFTER ALL SEVEN STAGES) HAS **114 NODES** AND **UPSTREAM's
`get_kernel_graph` OUTPUT HAS **27**.** AND THE CENSUS IS THE TELL:**

| op | the port's engine | upstream's |
|---|---|---|
| `PARAM` | 3 | **6** |
| `CONST` | 3 | 6 |
| `MUL` | 1 | **4** |
| `RANGE` | **0** | **3** |
| `INDEX` | **0** | **3** |
| `ADD` | **0** | **3** |
| `REDUCE` | 1 | 1 |
| `PERMUTE` | **2** | **0** |
| `STORE` | 1 | 1 |
| `AFTER` | 1 | 1 |
| `SINK` | 1 | **2** |
| `END` | **0** | **1** |
| `CALL` | **0** | **1** |

**⇒ ⇒ ⇒ SO **THE PORT's ENGINE HAS NOT APPLIED THE RANGEIFY AT ALL**: THE GRAPH STILL HAS
**`PERMUTE`** (WHICH UPSTREAM's RANGEIFY **REPLACES** WITH A `RANGE`) AND **NO `RANGE`,
NO `INDEX`, NO `ADD`, NO `END` AND NO `CALL` (WHICH ARE WHAT THE RANGEIFY **PRODUCES**).**

**⇒ ⇒ AND **THAT IS EXACTLY WHAT STAGE 1 IS** — `run_rangeify`, **"convert movement ops to
ranges"** (`rangeify.py:344`) — **⇒ AND THE PORT's OWN `rangeify.bend:2810` SAYS IT IS
**NOT PORTED**: `Stg{0, Nil{}},  # 1  run_rangeify -- rangeify.py:344 -- NOT PORTED`.**

**⇒ ⇒ ⇒ SO **THE GAP IS **NOT** "THE ENGINE IS WRONG" AND **NOT** "THE SCHEDULER IS WRONG"**:
IT IS **THAT STAGE 1 — **THE RANGEIFY ITSELF** — IS NOT PORTED AS A DRIVER.** **⇒ AND THE
PORT'S OWN `schedule/indexing.bend` **ALREADY HAS ALL THREE OF `run_rangeify`'s TABLES**
(`grm_table()` AT `:1141`, `par_table()` AT `:1170`, `pfd_table()` AT `:1177`) **⇒ AND
`rangify.bend` (LANDED 2026-10-28) **ALREADY FILLS THE REALIZE MAP** AND IT **AGREES WITH
CPython's** — **⇒ ⇒ ⇒ SO WHAT IS MISSING IS **THE APPLY HALF**: UPSTREAM's
`pm_apply_rangeify` REWRITE, WHICH TURNS THE REALIZE MAP INTO THE RANGEIFIED GRAPH.**

## THE MEASUREMENT THAT PROVES IT, AND IT IS **THE PORT's OWN ROWS**

**⇒ THE PORT's `rangify.bend`'s OWN ROWS SHOW THE REALIZE MAP IS RIGHT AND THE GRAPH IS
NOT TRANSFORMED:**
```
rr_realize=STORE:none:RESHAPE,REDUCE:none      # == CPython's rr_py_realize, EXACTLY
rr_in=SINK:none:AFTER;AFTER:none:PARAM,STORE;...   # == CPython's rr_py_in, 23/23 NODES
```
**⇒ ⇒ SO **THE PORT HAS THE **MAP** AND NOT THE **TRANSFORMATION** — WHICH IS **EXACTLY
THE HALF UPSTREAM DELETES AFTER USING IT** (`del ctx.realize_map[s]`, `indexing.py:88`,
**WHICH THE PORT'S OWN ORACLE NOTE WARNS ABOUT**).**

## THE NAMED WALLS ON THE APPLY HALF, FROM THE PORT's OWN FILES

**⇒ `schedule/indexing.bend`'s HEADER NAMES **THREE** WALLS IN `run_rangeify`'s APPLY HALF:**
1. **`BufferizeOpts`** (`indexing.py:56-61`) IS A FROZEN DATACLASS READ AT `indexing.py:6-7`,
   AND **`ops.bend`'s `Arg` HAS NO CONSTRUCTOR FOR A STAGE's ARG AT ALL** — **⇒ SO
   `s.device`, `s.removable` AND `s.addrspace` ARE ALL WALLS.**
2. **`_apply_reshape`** (`indexing.py:155-167`) IS **THE WALL**, IN FULL (`indexing.bend:735`).
3. **`apply_movement_op`'s `RESHAPE` ARM** IS THE SAME WALL (`indexing.bend:582`).

**⇒ AND `indexing.bend` SAYS WHICH ARMS **ARE** PORTED: **PERMUTE IS FULLY PORTED** (A PURE
REORDERING), **EXPAND IS FULLY PORTED** (A TAIL DROP), AND **SHRINK, FLIP AND PAD HAVE THEIR
DECISION PORTED AND THEIR ARITHMETIC NAMED** (`a+off`, `(s-1)-a`, `r-off` ALL BUILD A NODE
THROUGH THE SYMBOLIC SIMPLIFY, WHICH IS W3 PLUS W2).**

**⇒ ⇒ SO **THE APPLY HALF IS NOT A FRESH AMOUNT OF WORK EITHER: **ITS TABLES ARE THERE,
ITS PERMUTE/EXPAND ARMS ARE PORTED, AND ITS THREE WALLS ARE **NAMED**.****

## AND ONE THING THE MEASUREMENT FIXED: THE DUMP SAID "OTHER" WHERE THE PORT KNEW THE NAME

**⇒ THE ENGINE's `eng_op_name` HAD A **TEN**-OP TABLE AND AN `OTHER` FALLBACK, **⇒ AND ON A
REAL PROGRAM THE OUTPUT WAS FULL OF `OTHER` — SEVEN OF THEM — WHERE UPSTREAM SAYS `PARAM`,
`RANGE`, `MUL`, `INDEX`, `ADD`, `REDUCE`, `PERMUTE`.** **⇒ ⇒ ⇒ SO **THE DUMP WAS SAYING
"AN OP I DO NOT KNOW" WHERE THE PORT's OWN `Ops.name.of` (`ops.bend:287`) **KNOWS ALL 75 OPS**
— **⇒ AND THE `OTHER` ARM NOW SPELLS THE REAL NAME, SO **THE GAP IS VISIBLE INSTEAD OF
HIDDEN BEHIND A PLACEHOLDER.****

**⇒ AND THIS IS **THE SECOND TIME IN THIS SESSION** THAT A PLACEHOLDER ARM HID A REAL GAP:
THE FIRST WAS `rng_width`'s `None{}` FOR AN AFTER-BOUND RANGE (WHICH I FIXED, AND THE FIX
CHANGED **ZERO** OF THE FOLD's 340 GATE ROWS). **⇒ ⇒ ⇒ SO **A PLACEHOLDER IS NOT A
MEASUREMENT, AND A ROW THAT PRINTS "OTHER" IS A ROW THAT CANNOT GO RED.**

## THE COST

**ONE BEND PROCESS AT A TIME. THE CHAIN MEASUREMENT IS ~4 s.**
