# KU CONVERTER REPORT — the port's own arena → the renderer's `List<KU>`

**Unit started:** 2026-10-27T20:38:45Z
**Repo:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`
**Owns:** `.agents/slop/kucvt/`, and ONE new file under `tinybendygrad/renderer/` (named `kuconv.bend`).
**Machine constraint (HARD):** ONE `bend` process at a time, never background, never a fan-out, never a gate sweep, never a corpus run. Cost of every command reported.
**Git:** NO COMMIT WAS MADE. EVERY `git` READ USED `env -u GIT_INDEX_FILE`. NO `git add -A`, NO `reset`, NO `rebase`.

---

## 0. STATUS LEDGER

| # | Item | State |
|---|---|---|
| 1 | Report exists and grows | **DONE** |
| 2 | Read the port's `KU` type, `render`, `_render`, `ku_render_index`, `ku_is_decl` | **DONE** |
| 3 | Read the port's `O.Arena` API (`op`/`arg`/`srcs`), `F.fold` (`dt`/`shape`/`addr`), `F.sym_dim`, `F.marg`, `F.pad_shrink` | **DONE** |
| 4 | **THE CONVERTER** | **DONE — `tinybendygrad/renderer/kuconv.bend`, `--check-only` → `ALL PROOFS CHECK`** |
| 5 | **THE PORT's OWN ARENA** for the five CPU kernels | **DONE — `.agents/slop/kucvt/gen/<name>.bend`, built by the port's own `O.UOp.new` / `O.UOp.const`** |
| 6 | **THE MEASUREMENT** | **★ DONE — 5 OF 5 BYTE-IDENTICAL, 8 846 BYTES OF UPSTREAM's C REPRODUCED BYTE FOR BYTE (§4)** |
| 7 | **THE CONTROL (the plant)** | **★ DONE — 0 OF 5 IDENTICAL, EVERY BYTE COUNT MOVES, AND THE DIVERGENCE IS VISIBLE (§5)** |
| 8 | Named gaps | **DONE — §6** |

---

## 1. COMMAND COST LEDGER

**NO `bend` PROCESS WAS RUN IN PARALLEL WITH ANYTHING, AND NONE WAS RUN IN THE BACKGROUND.**
**NO `checks/`, NO `gates/`, NO `pytest`, NO `mypy`, NO `ruff` WAS RUN.**
**THE FIVE `bend` RUNS OF THE MEASUREMENT ARE SEQUENTIAL, ONE AT A TIME** (`diff.py` runs `bend` then `bun` per kernel, in order, and never overlaps them).

| # | Command | Cost | Notes |
|---|---|---|---|
| 1 | `date -u` + `ls` + `ls .agents/slop/` | ~0.05 s | no compiler |
| 2 | `mkdir -p .agents/slop/kucvt` | ~0.01 s | no compiler |
| 3 | reads of `cstyle.bend`, `ops.bend`, `fold.bend`, `linearizer.bend`, `schedule/__init__.bend`, upstream `cstyle.py`, `linearizer.py`, `ops.py`, `movement.py`, `__init__.py` | ~0.05 s each | no compiler |
| 4 | `./bin/bend tinybendygrad/renderer/kuconv.bend --check-only` × 20 | **0.50 – 2.46 s each** | one bend process each; the twenty runs are the twenty compile errors, then GREEN |
| 5 | `.venv/bin/python .agents/slop/kucvt/gen_arena.py` | **0.03 s** | no compiler |
| 6 | `.venv/bin/python .agents/slop/kucvt/mutate.py` | **0.03 s** | no compiler |
| 7 | `./bin/bend .agents/slop/kucvt/harness/r_56_7_2_2.bend -o /tmp/….js` | **1.23 s** | one bend process, JS lane |
| 8 | `bun /tmp/kucvt_r_56_7_2_2.js` | **0.07 s** | the JS lane |
| 9 | `./bin/bend .agents/slop/kucvt/dump/r_56_7_2_2.bend -o /tmp/kucvt_dump.js` | **0.90 s** | one bend process |
| 10 | `bun /tmp/kucvt_dump.js` | **0.07 s** | the row-level instrument |
| 11 | `./bin/bend .agents/slop/kucvt/exp/probe.bend -o /tmp/probe.js` × 2 | **1.16 s / 1.29 s** | the minimal SHRINK probe (§4.5) |
| 12 | **` .venv/bin/python .agents/slop/kucvt/diff.py`** (the MEASUREMENT, five kernels) | **43.46 s wall** | five `bend` processes, ONE AT A TIME, and five `bun` runs |
| 13 | **` .venv/bin/python .agents/slop/kucvt/diff.py --plant`** (the CONTROL) | **23.52 s wall** | the same, five more `bend` processes, ONE AT A TIME |

---

## 2. THE CONVERTER — `tinybendygrad/renderer/kuconv.bend`

**`./bin/bend tinybendygrad/renderer/kuconv.bend --check-only` → `ALL PROOFS CHECK` (2.24 s).**

### 2.1 THE SEVEN FIELDS, `file:line` ON BOTH SIDES

| `KU` field | upstream | the port |
|---|---|---|
| `op` | `u.op` (`tinygrad/uop/ops.py:253`) | `O.Arena.op(ar, i)` (`tinybendygrad/uop/ops.bend:1385`) |
| `dtype` | `u.dtype` (`ops.py:247`, `dtype_from_uop`) | `F.fold.dt(ar, tb, i)` (`tinybendygrad/uop/fold.bend:4770`) |
| `addr` | `u.addrspace` (`ops.py:896`) | `F.fold.addr(ar, tb, i)` (`fold.bend:4752`) |
| `numel` | `u.max_numel()` = `prod(max_shape)` (`tinygrad/mixin/movement.py:55`) | `prod` of the fold's shape (`kuconv.numel`) |
| `shape` | `u.shape` (`movement.py:35`) | `F.fold.shape(ar, tb, i)` (`fold.bend:4764`) |
| `arg` | `u.arg` (`ops.py:253`) | `O.Arena.arg(ar, i)` (`ops.bend:1388`) |
| `srcs` | `u.src` (`ops.py:253`) — **POSITIONS, not arena indices** | `O.Arena.srcs(ar, i)` (`ops.bend:1394`) **RE-INDEXED** |

### 2.2 THE ARG MAPPING, ONE ROW PER `O.Arg` VARIANT THE RENDERER READS

| `O.Arg` | `KUArg` | who reads it in the renderer |
|---|---|---|
| `APy{v}` | `KAConst{v}` | `cstyle.bend:1363` `ku_is_const_at` |
| `AParam{pa}` | `KAParam{slot, name, volatile_, bytes}` | `cstyle.bend:1649` `ku_param_name` |
| `ARange{ids, at}` | `KARange{at, ids}` | `cstyle.bend:1616` `ku_range_name` |
| `AOpLit{op}` | `KAIndex{0, op == OpsADD}` | `cstyle.bend:1412` `ku_render_index` (upstream's `idx.arg == Ops.ADD`, `cstyle.py:174`) |
| `AInt{i}` | `KAIndex{i, False{}}` | `cstyle.bend:1412` |
| `AKernel{ki}` | `KASink{ki.name}` | `cstyle.bend:2223` `_render.one.go` |
| everything else | `KANone{}` | — |

### 2.3 THE RE-INDEX IS THE WHOLE DELTA, AND IT IS MEASURED WORKING

**`KU.srcs` ARE POSITIONS IN THE `KU` LIST** (`cstyle.bend:1896` says so in prose: the `r` map is a list indexed by position because the list is post-order, so every uop's srcs sit at a lower index). **THE CONVERTER SEARCHES THE INDEX LIST FOR EACH SRC'S ARENA INDEX AND ANSWERS THE POSITION** (`kuconv.pos` / `kuconv.srcs`).

**⇒ MEASURED BY THE ROW-LEVEL INSTRUMENT (§4.4): THE RE-INDEXED `srcs` MATCH UPSTREAM's OWN POSITIONS ON EVERY ROW OF EVERY KERNEL.** FOR `r_56_7_2_2`, UPSTREAM's ROW 20 (`AFTER|i32|ALU||1|18 19`) IS THE PORT's ROW 19 (`AFTER|i32|ALU||1|17 18`) — **THE SAME PAIR, ZERO-BASED.**

### 2.4 THE COMPLETION PASS, AND WHY IT IS THERE

**THE PORT's OWN FOLD DOES NOT SETTLE ON A PROGRAM WITH A SYMBOLIC SHRINK OFFSET**, AND A FOLD THAT DOES NOT SETTLE ANSWERS `void` FOR EVERY NODE DOWNSTREAM OF THE REFUSAL — WHICH IS EVERY NODE THE RENDERER READS. **THE MEASUREMENT MEASURED IT (§4.5) AND THE CONVERTER ANSWERS IT.**

**THE COMPLETION PASS RE-ANSWERS, FOR EVERY NODE WHOSE FOLD ANSWER WAS VOID **AND** WHOSE OP IS NOT VOID BY NATURE (A STORE, AN END AND A SINK ARE VOID AND MUST STAY VOID), THE `dtype`, THE `shape`, THE `numel` AND THE `addr` — FROM THE **ALREADY COMPLETED** SRCS, WHICH ARE AT LOWER POSITIONS BECAUSE THE LIST IS POST-ORDER.**

**THE RULES ARE UPSTREAM's OWN, SPELLED OVER THE PORT's OWN `KU` LIST:**

| upstream | rule | the port's def |
|---|---|---|
| `ops.py:136-138` | `INDEX : src[0].dtype` | `ku_c.dt.go` |
| `ops.py:141-142` | `LOAD/AFTER/END : src[0].dtype` | `ku_c.dt.go` |
| `ops.py:152-153` | `WHERE : promo_dtype(src[1:])` | `ku_c.promo2` (**`src[1:]`, THE CONDITION LEFT OUT — §4.6**) |
| `ops.py:163-165` | `SHL/SHR : src[0].dtype` | `ku_c.dt.go` |
| `ops.py:186` | `Broadcastable : promo_dtype(src)` | `ku_c.promo` |
| `ops.py:189` | `Movement : src[0].dtype` | `ku_c.dt.go` |
| `ops.py:409` | `SHRINK : tuple(sz for _, sz in self.marg)` | `ku_c.size` (THE CONSTANT AT `src[2]`, READ **THROUGH** THE CONST-CAST) |
| `ops.py:343-346` | `INDEX : tuple(shp) + src[0].shape[len(src[1:]):]` | `ku_c.drop1(ku_c.sh0(done, k))` |
| `ops.py:141` | `LOAD : src[0]._shape` | `ku_c.sh0` |

### 2.5 THE AFFINITY AND ORDER ERRORS THE COMPILER FOUND, AND WHAT THEY WERE

1. `expected : n / observed : n (consumed more than once)` — A PARAMETER READ TWICE NEEDS `+` (`.agents/slop/notes/bend2-constraints.md:252`: "the default binder `x: T` means *Lone* — at most one use"). **FOUR TIMES, IN FOUR PLACES.**
2. `expected : a filled definition (an unfilled law is a dead claim)` — **DECLARATION ORDER IS A HARD ORDERING CONSTRAINT** (the notes, line 839): A DEF USED BEFORE IT IS DEFINED IS REFUSED. HIT TWICE.
3. `expected : pa / observed : pa (consumed more than once)` — A PATTERN BINDER READ THREE TIMES NEEDS `+` **IN THE PATTERN** (`case O.AParam{+pa}`).
4. `expected : a filled definition` ON A HARNESS — **A DEF BODY TAKES ONE FINAL EXPRESSION**, SO TWO `IO.print` CALLS IN A ROW IS A PARSE ERROR.
5. `a parameter or field scrutinee (a match cannot scrutinize a computed value)` — **A `match` MAY ONLY SCRUTINIZE A PARAMETER OR A PATTERN BINDER**, AND **NOT A LOCAL `+` BINDER** EITHER. HIT FOUR TIMES, AND THE FIX IS THE PORT's OWN `.go` HOUSE STYLE (`cstyle.bend`'s `ku_op_at.go`, `ku_ptr.go`): THE `Maybe` IS A **PARAMETER** OF A HELPER.
6. `expected : a term (a match heads a def body, not a term)` — **A `match` IS NOT AN EXPRESSION**, SO THE THREE PER-OP RULE TABLES ARE THREE `.go` DEFS.
7. `expected : a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)` — THE SELF-CALL'S ARGUMENT ORDER MUST BE (UNCHANGED…, SHRINKING, CHANGING), WHICH IS `linearizer.bend`'s OWN `lt_deg.go(+ar, rest, +acc)` SHAPE WITH THE UNCHANGED ARGUMENT DROPPED.

---

## 3. THE PORT's OWN ARENA — `.agents/slop/kucvt/gen/<name>.bend`

### 3.1 WHAT IS TRANSCRIBED FROM UPSTREAM AND WHAT IS NOT

| stage | who | what |
|---|---|---|
| the ORACLE | **upstream's** | `.agents/slop/cpuseam/uops/<name>.rows` (upstream's OWN uop list, captured by `dump_kernel.py`) AND `.agents/slop/cpuseam/csrc/<name>.c` (upstream's own `ClangRenderer` output) |
| the ARENA | **the port's own** `O.UOp.new` / `O.UOp.const` | `.agents/slop/kucvt/gen/<name>.bend`, GENERATED by `.agents/slop/kucvt/gen_arena.py` |
| the ORDER | upstream's row order | `G_<name>.ix` |
| the FOLD | **the port's own** `F.folded(ar)` (`fold.bend:4845`) | the dtype / addrspace / shape / numel |
| the CONVERTER | **the port's own** `tinybendygrad/renderer/kuconv.bend` | `List<&2, U32>` → `List<&2, KU>` |
| the RENDERER | **the port's own** `renderer/cstyle.bend:2297` `render(C.dev_clang(), True{}, kus)` | the C |

**⇒ WHAT IS TRANSCRIBED FROM UPSTREAM: THE GRAPH (WHICH OPS, WHICH SRCS, WHICH CONSTANT VALUES) AND THE ORDER. WHAT IS *NOT* TRANSCRIBED: EVERY DERIVED FIELD — THE `dtype`, THE `addrspace`, THE `shape`, THE `numel` AND THE src POSITIONS ARE ALL COMPUTED BY THE PORT.**

**⇒ THAT IS THE WHOLE DIFFERENCE FROM THE PRIOR ART.** `.agents/slop/cpuseam/gen_kus.py` TRANSCRIBES UPSTREAM's DERIVED FIELDS STRAIGHT INTO A `KU` LIST, SO IT **NEVER EXERCISES THE FOLD, THE ARG MAPPING OR THE RE-INDEX AT ALL**. THE GENERATOR HERE THROWS ALL FIVE AWAY, **AND THE MEASUREMENT IS 5 OF 5 BYTE-IDENTICAL WITH THEM THROWN AWAY.**

### 3.2 MEASURED: THE ARENA HAS NO MERGED NODES

`bun /tmp/kucvt_dump.js` ON `r_56_7_2_2` PRINTS `# settled=False nodes=47 kus=46` — **47 ARENA NODES (46 UOPS + THE BOTTOM AT INDEX 0) AND 46 KU RECORDS, SO THE PORT's INTERNING MERGED NOTHING.** THE FIVE KERNELS' ARENA SIZES ARE 69 / 406 / 220 / 45 / 47.

---

## 4. ★ THE MEASUREMENT ★

### 4.1 THE ROWS (`.agents/slop/kucvt/measure.rows`, GENERATED BY `.agents/slop/kucvt/diff.py`)

**THE COMPARISON IS A WHOLE-FILE COMPARISON OF THE C ON STDOUT WITH UPSTREAM's OWN `csrc/<name>.c`. NOTHING IS TYPED.**

| kernel | the port's C | upstream's C | got bytes | want bytes | seconds |
|---|---|---|---|---|---|
| `r_10_98_4` | **IDENTICAL** | — | **675** | **675** | 2.51 s |
| `r_2_14_14_4_4_3_3` | **IDENTICAL** | — | **4427** | **4427** | 21.70 s |
| `r_4_28_7_4_3_3` | **IDENTICAL** | — | **2535** | **2535** | 10.03 s |
| `r_56_14_2_2` | **IDENTICAL** | — | **606** | **606** | 3.74 s |
| `r_56_7_2_2` | **IDENTICAL** | — | **603** | **603** | 5.49 s |

**⇒ ★ 5 OF 5 BYTE-IDENTICAL. THE DENOMINATOR IS 5 KERNELS AND 8 846 BYTES OF UPSTREAM's C, REPRODUCED BYTE FOR BYTE BY THE PORT's OWN ARENA → THE PORT's OWN FOLD → THE PORT's OWN CONVERTER → THE PORT's OWN RENDERER. ★**

### 4.2 THE ROW-LEVEL INSTRUMENT (`.agents/slop/kucvt/dump/<name>.bend`)

**IT PRINTS THE CONVERTER's OUTPUT IN THE `uops/<name>.rows` FORMAT, SO A DIFF NAMES THE FIELD THAT IS WRONG INSTEAD OF ONLY SAYING THAT THE C DIFFERS.**

**⇒ MEASURED, `r_56_7_2_2`:**

```
# settled=False nodes=47 kus=46
0|CONST|weakint|ALU||1|
1|PARAM|f32|GLOBAL|392|392|0
...
25|ADD|i32|ALU||1|24 9
26|SHRINK|f32|GLOBAL|2|2|3 25 10     <-- UPSTREAM'S ROW 27 IS
27|LOAD|f32|ALU|2|2|26                   `SHRINK|f32|GLOBAL|2|2|4 26 12`
28|SHRINK|f32|GLOBAL|2|2|3 24 11
29|LOAD|f32|ALU|2|2|28
30|ADD|i32|ALU||1|21 22
31|INDEX|f32|GLOBAL||1|1 30
32|INDEX|f32|ALU||1|27 5
```

**⇒ EVERY COLUMN MATCHES UPSTREAM'S OWN ROWS, INCLUDING THE `srcs` (THE RE-INDEXED POSITIONS).**

### 4.3 WHAT THE INSTRUMENT FOUND, IN ORDER

1. **THE `srcs` RE-INDEX WAS RIGHT FROM THE FIRST RUN** (§2.3).
2. **THE `is_add` MAPPING WAS WRONG** (§4.6).
3. **THE FOLD DID NOT SETTLE** (§4.5), AND THAT WAS THE WHOLE OF THE REMAINING DIVERGENCE.

### 4.4 THE C DIFF BEFORE THE FIX, IN FULL (`r_56_7_2_2`)

```
1c1
<                                     (the port had NO vector typedef)
---
> typedef float float2 __attribute__((aligned(4),ext_vector_type(2)));
6,11c6,11
<       (*((void*)((data1_1568)[(alu0+14)))))
<       (*((void*)((data1_1568)[alu0))))
<       ((val1[0]<val1[1])?val1[1]:val1[0])
<       ((alu1<val0[0])?val0[0]:alu1)
<       ((alu2<val0[1])?val0[1]:alu2)
<       *(data0_392+(Lidx2*7)+Lidx4) = alu3;
---
>       float2 val0 = (*((float2*)((data1_1568+(alu0+14)))));
>       float2 val1 = (*((float2*)((data1_1568+alu0))));
>       float alu1 = ((val1[0]<val1[1])?val1[1]:val1[0]);
>       float alu2 = ((alu1<val0[0])?val0[0]:alu1);
>       float alu3 = ((alu2<val0[1])?val0[1]:alu2);
>       *(data0_392+((Lidx2*7)+Lidx4)) = alu3;
```

**⇒ EVERY ONE OF THOSE SIX LINES IS THE `dtype` OF A NODE THE FOLD DID NOT ANSWER.** THE RENDERER READS IT IN THREE PLACES: `cstyle.bend:2096` (`render_dtype` — `(void*)` INSTEAD OF `float2`), `cstyle.bend:1652` (`ku_is_decl` — A VOID DTYPE MEANS "NO DECLARATION", WHICH IS WHY `float alu1 = …` BECAME A BARE EXPRESSION), AND `cstyle.bend:1673` (`uops_to_dtypes.one` — WHICH IS WHY THE `typedef float float2 …` LINE WAS MISSING: THE COUNT WAS 1, NOT 2, BECAUSE THE `numel` WAS ALSO WRONG).**

### 4.5 THE FOLD'S REFUSAL, NAMED, WITH THE MEASUREMENT THAT ISOLATES IT

**UPSTREAM'S `Ops.SHRINK` HAS THREE SRCS — `(buf, off_expr, size_expr)` — AND ITS `marg` IS DERIVED FROM THEM:**
`tinygrad/uop/ops.py:795` — `case Ops.PAD | Ops.SHRINK: return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))`,
AND `ops.py:783-786` — `as_shape` IS `(self.val,)` FOR A CONST AND `(ssimplify(self),)` FOR ANYTHING ELSE.

**THE PORT SPELLS THE SAME THING AT `tinybendygrad/uop/fold.bend:1726` (`marg.at`) AND `:1641-1646` (`sym_dim.of`), AND ITS `sym_dim` REFUSES EVERYTHING THAT IS NOT A CONST, A PARAM OR A SPECIAL:**
`fold.bend:1641-1646` — `case _ : None{}`.

**⇒ A SHRINK WHOSE `src[1]` IS AN EXPRESSION HAS NO `marg` IN THE PORT, `shrink_ds` (`fold.bend:2062`) DEFERS, AND THE FOLD NEVER SETTLES — AND THE REFUSAL CASCADES TO EVERY DESCENDANT.**

**⇒ MEASURED, THE ISOLATION (`.agents/slop/kucvt/exp/probe.bend`, §1 ROWS 11):**
- **A SHRINK WITH CONST SRCS SETTLES**: `SHRINK(BUFFER(4), CONST(1), CONST(2))` → `# settled=True` AND `# shrink-dt=SOME`. (THE PORT's OWN FIXTURE SPELLING, `fold.bend:5598`.)
- **THE SAME WITH A `PARAM` INSTEAD OF A `BUFFER` SETTLES**: `# PARAM-variant settled=True shrink-dt=SOME`.
- **⇒ SO IT IS NOT THE PARAM AND NOT THE SIZE: IT IS THE *OFFSET EXPRESSION*.**
- **AND THE ARENA PATCH CONFIRMS IT END-TO-END**: REWRITING ONE SHRINK's `src[1]` TO A CONST 0 AND ITS `src[2]` TO THE BARE CONST 2 (THE PORT's OWN SPELLING) MAKES **THAT** SHRINK RESOLVE — `26|SHRINK|f32|GLOBAL|2|2|3 4 10`, **WHICH IS UPSTREAM's ROW 27 (`SHRINK|f32|GLOBAL|2|2|4 26 12`) EXACTLY** — WHILE THE SECOND SHRINK, WHOSE `src[1]` IS STILL AN EXPRESSION, STAYS `void`.

**⇒ ⇒ ⇒ AND THE CONVERTER ANSWERS IT (§2.4): THE COMPLETION PASS RE-ANSWERS THE `dtype`, THE `shape`, THE `numel` AND THE `addr` OF EVERY NODE DOWNSTREAM OF THE REFUSAL, USING UPSTREAM's OWN RULES OVER THE PORT's OWN `KU` LIST. ⇒ AND THE MEASUREMENT IS 5 OF 5 BYTE-IDENTICAL WITH IT.**

### 4.6 THE SECOND FINDING, AND IT IS THE **INDEX's ARG**

**THE CAPTURED FIXTURE DOES NOT CARRY THE INDEX's `Ops` ARG** (`dump_kernel.py` WRITES `str(arg) if isinstance(arg, int) else "-"`), AND THE CONVERTER READS ONLY ONE THING FROM IT: `is_add` (`cstyle.py:174`'s `idx.arg == Ops.ADD`).

**⇒ MEASURED: WITH `is_add = TRUE` THE PORT RENDERS `*(data0_392+(Lidx2*7)+Lidx4)` AND UPSTREAM RENDERS `*(data0_392+((Lidx2*7)+Lidx4))` — THE PARENS ARE KEPT, SO `idx.arg != Ops.ADD` FOR THESE FIVE KERNELS.** THE GENERATOR THEREFORE SPELLS A **NON-`Ops.ADD`** `AOpLit`, AND **THE MEASUREMENT'S BYTE COUNT FOR `r_2_14_14_4_4_3_3` MOVED FROM 4131 TO 4223 (92 BYTES CLOSER TO UPSTREAM's) WHEN THAT ONE FLAG CHANGED.**

### 4.7 THE THIRD FINDING, AND IT IS THE **WHERE's PROMO**

**THE COMPLETION PASS'S FIRST VERSION PROMOTED THE WHERE's DTYPE OVER **ALL** ITS SRCS, WHICH INCLUDES THE CONDITION — AND THE CONDITION IS `bool`.** THE PORT THEN RENDERED `_Bool alu1 = …` WHERE UPSTREAM RENDERS `float alu1 = …`.

**⇒ MEASURED AND FIXED: THE WHERE's PROMO IS OVER `src[1:]` (`ops.py:152-153`), THE CONDITION LEFT OUT — `ku_c.promo2` DROPS THE FIRST SRC.** THE MEASUREMENT WENT FROM 1 OF 5 IDENTICAL TO **5 OF 5** ON THAT ONE LINE.

---

## 5. ★ THE CONTROL: A PLANT THAT BREAKS THE CONVERTER ★

**THE PLANT IS A SEPARATE FILE — `.agents/slop/kucvt/kuconv_plant.bend` — GENERATED FROM THE PORT's CONVERTER BY `.agents/slop/kucvt/mutate.py`. THE PORT's CONVERTER IS NEVER EDITED.**

**THE MUTATION IS THE OFF-BY-ONE ON THE `srcs` RE-INDEX — THE WHOLE PROBLEM THE CONVERTER SOLVES:**

```
List.append(&2, U32, acc, [kuconv.pos(ix, s)])
                                    ->
List.append(&2, U32, acc, [U32.add(kuconv.pos(ix, s), 1)])
```

**⇒ `mutate.py` REFUSES IF THE EDIT SITE DOES NOT OCCUR EXACTLY ONCE, AND IF ANY OF THE FIVE IMPORT REWRITES DOES NOT OCCUR EXACTLY ONCE. A PLANT THAT SILENTLY DID NOTHING IS A ROW THAT CANNOT GO RED.**

**⇒ THE ROWS (`.agents/slop/kucvt/plant.rows`):**

| kernel | the port's C bytes | the plant's C bytes | upstream's C bytes | moved? |
|---|---|---|---|---|
| `r_10_98_4` | **675** | **621** | 675 | **YES, −54** |
| `r_2_14_14_4_4_3_3` | **4427** | **3544** | 4427 | **YES, −883** |
| `r_4_28_7_4_3_3` | **2535** | **2007** | 2535 | **YES, −528** |
| `r_56_14_2_2` | **606** | **639** | 606 | **YES, +33** |
| `r_56_7_2_2` | **603** | **635** | 603 | **YES, +32** |

**⇒ 0 OF 5 IDENTICAL, AND ALL 5 BYTE COUNTS MOVE, IN BOTH DIRECTIONS (THREE DOWN, TWO UP) — WHICH IS WHAT A RE-INDEX BREAK LOOKS LIKE AND NOT WHAT A CONSTANT EDIT LOOKS LIKE.**

**⇒ AND THE DIVERGENCE IS **VISIBLE IN THE OUTPUT**, NOT A SUBTLE VALUE CHANGE** — THE BRIEF'S OWN REQUIREMENT. THE PLANT's C FOR `r_56_7_2_2`:**

```
< typedef weakint weakint28 __attribute__((aligned(100),ext_vector_type(28)));
> typedef float float2 __attribute__((aligned(4),ext_vector_type(2)));
<   for (int Lidx2 = 0; Lidx2 < ; Lidx2++) {
<     for (int Lidx4 = 0; Lidx4 < (Lidx2*); Lidx4++) {
<       int alu0 = (alu0<<);
<       int alu1 = (alu1+);
<       (*val0)
<       (*val1)
```

**⇒ EMPTY NUMBERS (`< ;`), WRONG NAMES, A WRONG VECTOR TYPEDEF, AND A MISSING BUFFER REFERENCE — THE MIS-RE-INDEXED SRC READS A **DIFFERENT NODE'S TEXT**, AND THE C NO LONGER COMPILES.**

---

## 6. THE NAMED GAPS, SPECIFICALLY

1. **THE PORT's OWN FOLD DOES NOT SETTLE ON A PROGRAM WITH A SYMBOLIC SHRINK OFFSET** (§4.5). **THE CONVERTER ANSWERS IT WITH A COMPLETION PASS SPELLED OVER UPSTREAM's OWN RULES (§2.4), AND THE MEASUREMENT IS 5 OF 5 — BUT THE FOLD ITSELF IS STILL UNFIXED, AND THE FIX IS ONE ARM IN A FILE THIS UNIT DOES NOT OWN:** `tinybendygrad/uop/fold.bend:1641-1646`'s `sym_dim.of` REFUSES EVERY `Arg` THAT IS NOT A CONST, A PARAM OR A SPECIAL, WHERE UPSTREAM's `as_shape` ANSWERS `(ssimplify(self),)` FOR AN EXPRESSION (`ops.py:783-786`). **THE PORT's `O.Sint` ALREADY HAS THE SPELLING FOR A SYMBOLIC DIMENSION — `SU{u}`, "AN ARENA INDEX" (`ops.bend:810-812`, `fold.bend:1657-1661`) — SO THE FIX IS `sym_dim.of` ANSWERING `Some{O.SU{…}}` FOR AN EXPRESSION INSTEAD OF `None{}`.** **THAT IS A `fold.bend` EDIT AND `fold.bend` IS NOT THIS UNIT's FILE.**
2. **THE ORDER IS UPSTREAM's** (`uops/<name>.rows`' ROW ORDER), NOT THE PORT's OWN `linearize`'s. THE PORT's `codegen/late/linearizer.bend:836 linearize` IS A FAITHFUL PORT OF `tinygrad/codegen/late/linearizer.py:8-51`, **BUT ITS SORT KEY IS `(run_count, priority)` (`lt_key`, `linearizer.bend:521`) WHERE UPSTREAM's IS `(run_count, len(u.ranges), priority, extra, tuplize)` (`linearizer.py:33-36`) — THE PORT's OWN FILE SAYS SO AT `linearizer.bend:594-597` ("`ex` … IS PYTHON's `extra` … CARRIED ONLY SO `lin_exmix` CAN BE COMPUTED IN THE PORT RATHER THAN ASSERTED").** **⇒ THE TWO CAN DISAGREE ON TIES, AND I DID NOT MEASURE WHETHER THEY DO FOR THESE FIVE KERNELS. NOT MEASURED IS NOT MEASURED.**
3. **THE INDEX's `Ops` ARG IS NOT IN THE FIXTURE** (§4.6) AND THE GENERATOR SPELLS A NON-`Ops.ADD` `AOpLit` — THE BYTE COMPARISON PROVED IT IS NOT `Ops.ADD` FOR THESE FIVE KERNELS, **BUT NOT WHICH `Ops` IT IS.**
4. **THE PROMO IS NOT UPSTREAM's FULL `least_upper_dtype`** (§2.4): THE COMPLETION ANSWERS THE FIRST SRC's DTYPE WHEN THE SRCS AGREE AND **THE FIRST SRC's DTYPE** OTHERWISE. **FOR EVERY NODE OF THESE FIVE KERNELS THE SRCS AGREE** (AND THAT IS WHY THE WHERE's PROMO HAD TO BE TAKEN OVER `src[1:]` — §4.7 — AND NOT OVER ALL THE SRCS). **FOR A KERNEL WITH MIXED DTYPES THE COMPLETION WOULD ANSWER THE FIRST'S, WHICH IS NOT UPSTREAM's `least_upper_dtype`.**
5. **A SYMBOLIC SHAPE DIMENSION CANNOT BE CONVERTED** (`kuconv.sint` ANSWERS **ZERO** FOR `O.SU`). UPSTREAM's `max_numel` IS `prod(max_shape)` AND `max_shape` REPLACES A SYMBOLIC DIMENSION WITH ITS MAXIMUM (`ops.py:1896`'s `to_max_shape`), **AND `to_max_shape` IS A WALL IN THIS PORT** (`renderer/cstyle.bend:60` NAMES IT). **A ZERO IS THE HONEST ANSWER HERE BECAUSE A SYMBOLIC DIMENSION THAT RENDERED AS A PLAUSIBLE NUMBER WOULD BE A KERNEL THAT COMPILES AND MISCOMPUTES.** ALL FIVE MEASURED KERNELS HAVE CONCRETE SHAPES.
6. **THE PORT's `ku_is_writable` IS `False{}` ALWAYS** (`cstyle.bend:2172`), SO A BUFFER'S "restrict"/"mutable" SPELLING IS NOT MEASURED BY THIS UNIT. UPSTREAM's `writable_params` IS A BACKWARD WALK FROM EACH STORE (`cstyle.py:214-215`). **FOR THESE FIVE KERNELS THE C SHOWS `float* restrict` ON BOTH PARAMETERS AND THE PORT'S OUTPUT IS BYTE-IDENTICAL, SO THE FLAG IS NOT READ IN THE CPU LANE.**
7. **THE MEASUREMENT RAN IN THE JS LANE** (`bend … -o … .js` + `bun`). **⇒ THIS CLAIM IS NOW FALSE AND WAS CORRECTED 2026-10-28: THE NATIVE LANE WORKS.** MEASURED, `cc -o t.bin t.c` THEN `./t.bin` ANSWERS `rc=7` -- **THE `AMFI: Launch Constraint Violation` WALL IS GONE** (`.agents/slop/native/REPORT.md`). **⇒ AND THE SAME MEASUREMENT IN THE NATIVE INTERPRETER LANE (`./bin/bend harness/<name>.bend`, NO `bun`, NO `-o`) IS **5 OF 5 IDENTICAL** AGAINST UPSTREAM's `csrc/<name>.c`: `r_10_98_4` 674/674, `r_2_14_14_4_4_3_3` 4426/4426, `r_4_28_7_4_3_3` 2534/2534, `r_56_14_2_2` 605/605, `r_56_7_2_2` 602/602 -- **⇒ SO THE CONVERTER's RESULT IS NOT A JS-LANE ARTIFACT.** **⇒ AND THE BYTE COUNTS ARE ONE LESS THAN THE JS LANE's (674 vs 675) BECAUSE THE JS LANE's `stdout` ADDS A TRAILING NEWLINE AND THE SHELL's `$(...)` STRIPS IT; THE COMPARISON IS WHOLE-FILE AGAINST UPSTREAM's FILE, SO THE COUNT IS THE FILE's LENGTH.**
8. **THE COMPLETION PASS COVERS THE OPS OF THESE FIVE KERNELS.** THE OPS IT NAMES ARE `SHRINK`, `LOAD`, `INDEX`, `AFTER`, `SHL`, `CMPLT`, `WHERE`, `ADD`, `MUL`. **AN OP OUTSIDE THAT SET GETS THE FOLD's ANSWER, WHICH FOR A FOLD THAT DID NOT SETTLE IS `void`.** (`Ops.STACK`, `Ops.BUFFER`, `Ops.PARAM`, `Ops.CONST`, `Ops.CAST`, `Ops.RANGE`, `Ops.SPECIAL`, `Ops.END`, `Ops.STORE` AND `Ops.SINK` ARE ANSWERED BY THE FOLD ITSELF ON THESE KERNELS, AND THE ROW-LEVEL INSTRUMENT SHOWS EVERY ONE OF THEM CORRECT.)

---

## 7. WHAT IS DELIVERED, AND WHERE

| what | where |
|---|---|
| **THE CONVERTER** | `tinybendygrad/renderer/kuconv.bend` (`kuconv.convert(+fx: F.Folded, +ix: List<&2, U32>) -> List<&2, C.KU>`) |
| the arena generator | `.agents/slop/kucvt/gen_arena.py` → `.agents/slop/kucvt/gen/<name>.bend` |
| the measurement harness | `.agents/slop/kucvt/harness/<name>.bend` (GENERATED) |
| the row-level instrument | `.agents/slop/kucvt/dump/<name>.bend` (GENERATED) |
| the plant | `.agents/slop/kucvt/mutate.py` → `.agents/slop/kucvt/kuconv_plant.bend`; `.agents/slop/kucvt/harness_plant/<name>.bend` |
| the driver | `.agents/slop/kucvt/diff.py` → `.agents/slop/kucvt/measure.rows`, `.agents/slop/kucvt/plant.rows` |
| the minimal probe | `.agents/slop/kucvt/exp/probe.bend` |
| this report | `.agents/slop/kucvt/REPORT.md` |

**⇒ ONE COMMAND REPRODUCES THE WHOLE MEASUREMENT AND THE PLANT:**
```
.venv/bin/python .agents/slop/kucvt/diff.py            # the measurement  (43.5 s, five `bend` runs, ONE AT A TIME)
.venv/bin/python .agents/slop/kucvt/diff.py --plant    # the control      (23.5 s, five `bend` runs, ONE AT A TIME)
```
