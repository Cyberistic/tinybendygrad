# VSLANE — PORT UPSTREAM's VECTORISED `exec_alu` (THE TUPLE BRANCH)

**OWNER:** subagent `vslane`. **STARTED:** 2026-10-26T15:33:01Z.
**REPO:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`, HEAD `3c8bf770c`.
**OWNED AND EDITED:** `tinybendygrad/uop/symbolic.bend`, `tinybendygrad/runtime/ops_python.bend`.
**NOT EDITED:** `tinygrad/`, `ops_bend.py`, `checks/`, `gates/`, `.agents/TODO.md`,
`.agents/TOOLS.md`, `AGENTS.md`, `.agents/slop/graphcmp.{py,bend}`,
`.agents/slop/convfix/`, `.agents/slop/execfix/`. **NOT COMMITTED.**

---

## SECTION 0 — THE ANSWER IN ONE PARAGRAPH

**THE TASK'S PREMISE IS MEASURED FALSE, AND THE 29 DIVERGENCES HAD **FOUR** CAUSES, NONE
OF WHICH IS THE VECTORISED ALU.** UPSTREAM's `exec_alu` TUPLE BRANCH
(`tinygrad/uop/ops.py:1423`) **NEVER FIRES ON THIS TREE's POPULATION**: wrapping upstream's
own `exec_alu` and running every fixture of `gates/ops_python_exec-fixtures.rows` counts
**192899** CALLS AND **0** OF THEM HAD A TUPLE OPERAND. **UPSTREAM's ALU IS SCALAR HERE
TOO**, so the port's scalar ALU was never the problem, and the port's VECTOR MODEL (a
vector LOAD's run of lanes in the arena, a STACK's run of srcs) was already upstream's.
**THE FOUR CAUSES WERE TWO ARITHMETIC INVERSIONs AND TWO VALUE-CONVERSIONs**, and all four
are now fixed: **`symbolic.bend`'s `f32_where` HAD ITS ARMS SWAPPED**; **`symbolic.bend`'s
`exec_alu_i32.cmp` IMPLEMENTED `CMPNE` AS `==`**; **`ops_python.bend`'s `Prog.cast.dt` KEPT
THE **FLOAT's** BIT PATTERN FOR A FLOAT-TO-INT CAST**; and **`ops_python.bend`'s STORE WROTE
THE VALUE'S OWN BITS WHERE UPSTREAM WRITES THE VALUE **CONVERTED TO THE BUFFER****.
**THE 153-FIXTURE CENSUS IS NOW 0 DIVERGENCES OF 365 ROWS (IT WAS 29), ALL 29 PINNED ROWS
NOW AGREE BY NAME, NOTHING REGRESSED, `gates/ops_bend_exec-e2e.py` IS STILL 7 MATCH, AND
REVERTING THE FOUR FIXES REPRODUCES THE 29 PRE-FIX ROWS BYTE FOR BYTE (29 of 29).**

---

## SECTION 1 — THE PREMISE, MEASURED FALSE

### 1.1 UPSTREAM's `exec_alu` DOES NOT TAKE THE TUPLE BRANCH ON THIS POPULATION

`tinygrad/uop/ops.py:1422-1430`:

```python
def exec_alu(op:Ops, dtype:DType, operands, truncate_output=True):
  if any(isinstance(x, tuple) for x in operands):
    count = max(len(x) for x in operands if isinstance(x, tuple))
    return tuple([exec_alu(op, dtype, [x[i] if isinstance(x, tuple) else x for x in operands]) for i in range(count)])
  if op in GroupOp.Binary and Invalid in operands: return Invalid
  alu = python_alu[op](*operands)
  if truncate_output and (truncate_fxn:=truncate.get(dtype)) is not None: return truncate_fxn(alu)
  return alu
```

**THE MEASUREMENT** — `.agents/slop/vslane/tuple_census.py` wraps upstream's OWN
`exec_alu` (imported at `tinygrad/runtime/ops_python.py:12`, called at `:158`) and runs the
tree's own fixture population:

```
# fixtures: 153
# exec_alu CALLS: 192899
# CALLS WHOSE OPERANDS CONTAIN A TUPLE (the branch's condition): 0
# OPS SEEN: ['ADD', 'AND', 'CDIV', 'CMOD', 'CMPEQ', 'CMPLT', 'CMPNE', 'EXP2', 'FLOORDIV',
#            'FLOORMOD', 'LOG2', 'MAX', 'MUL', 'MULACC', 'NEG', 'OR', 'POW', 'RECIPROCAL',
#            'SHL', 'SHR', 'SIN', 'SQRT', 'SUB', 'TRUNC', 'WHERE', 'XOR']
# OPS THAT SAW A TUPLE: []
```

**⇒ THE DENOMINATOR IS 192899 CALLS OVER 153 FIXTURES AND 26 DISTINCT ALU OPS, AND THE
TUPLE BRANCH FIRED **0** TIMES.** Reading: `.agents/slop/vslane/tuple-census.rows`.

**AND ON THE ONE FIXTURE THE TASK NAMED, `f32.sqrt.0`, THE CALLS ARE VISIBLE** —
`.agents/slop/vslane/trace_upstream.py` prints every call upstream makes:

```
exec_alu(SHL,   i32,  operands=(0, 2))            -> 0
exec_alu(CMPLT, bool, operands=(1.0, 0.0))        -> False
exec_alu(CMPNE, bool, operands=(1.0, 0.0))        -> True
exec_alu(WHERE, f32,  operands=(False, -1.0, 1.0)) -> 1.0
exec_alu(WHERE, f32,  operands=(True, 1.0, 0.0))  -> 1.0
exec_alu(MUL,   f32,  operands=(1.0, 1.0))        -> 1.0
exec_alu(SQRT,  f32,  operands=(1.0,))            -> 1.0
...
exec_alu(SQRT,  f32,  operands=(4.0,))            -> 2.0
```

**⇒ EVERY OPERAND IS A SCALAR. `any(isinstance(x, tuple) for x in operands)` IS FALSE FOR
EVERY CALL. UPSTREAM's ALU IS SCALAR IN THIS PACKET, AND SO IS THE PORT's. THE PORT WAS NOT
"SCALAR WHERE UPSTREAM IS VECTORISED".**

### 1.2 WHERE THE VECTOR LANES REALLY LIVE

`tinygrad/runtime/ops_python.py`'s `PythonProgram.__call__` keeps its arena in a LOCAL
`values` dict (`:60`), so `.agents/slop/vslane/trace_values.py` READS IT WITH `sys.settrace`
— upstream's own frame locals, no upstream edit, no re-implementation of a step. On
`f32.sqrt.0`:

```
values[SHRINK] = [(<memory at 0x…>, 0)]        # ops_python.py:114/120 -- the (memoryview, offset) TUPLE
values[LOAD]   = [[1.0], [2.0], [3.0], [4.0]]  # ops_python.py:142 -- ONE LIST PER VECTOR ELEMENT
values[INDEX]  = [1.0]                        # ops_python.py:117 -- A SCALAR
```

and every ALU op's value is `[<scalar>]`.

**⇒ THE LANES LIVE IN THE **LOAD** (`values[u] = [load(...) for j in range(load_sz)]`,
ops_python.py:142) AND IN THE **STACK** (`values[u] = src_values`, ops_python.py:135). THE
INDEX's ALU ARM (`ops_python.py:117`, `ret = [src_values[0][i][t] for t,i in
enumerate(src_values[1])]`) PICKS ONE ELEMENT OF THE LOAD'S RUN, AND THE ALU CONSUMES THAT
SCALAR.**

**⇒ THE PORT's SHAPE IS ALREADY UPSTREAM's**, and the port says so itself:
`tinybendygrad/runtime/ops_python.bend:697-702` ("A vector LOAD's value in Python is
`[[v]]*load_sz` … the FLAT run is `load_sz`"), `Prog.ld.at` writes `vs[slot(LOAD)+j]`
(`:2043`), `Prog.stack.copy` writes the STACK's srcs at `vs[slot(STACK)+k]` (`:1867`), and
`Prog.store.v` reads `vs[slot(STACK)+j]` (`:2107`).

**⇒ AND THE DECISIVE CROSS-CHECK: `f32.neg.0` HAS THE **SAME PACKET SHAPE** -- A VECTOR
LOAD, FOUR INDEXes, FOUR ALUs, A STACK, A VECTOR STORE -- AND IT **ALREADY AGREED** WITH
UPSTREAM BEFORE THIS UNIT TOUCHED ANYTHING. IT IS NOT ONE OF THE 29. ⇒ THE LOAD/INDEX/
STACK/STORE LANE WAS NOT THE BUG; THE BUG WAS IN THE **VALUES** THE LANE CARRIED.**

### 1.3 THE PIN FILE'S OWN DIAGNOSIS IS A HYPOTHESIS, AND IT IS WRONG

`gates/ops_python_exec-pins.rows:29-34` says:

> the VECTOR-STORE LANE family: the packet's STORE covers lanes 0-3 and CPython leaves
> lanes 4-7 untouched … So the port zeroes the lanes it should have computed. Same shape on
> sqrt, log2, exp2, recip, shl, shr, **maxpair**, cmod, ne, CMPNE, bitcast.

**⇒ "the port zeroes the lanes it should have computed" IS TRUE AS A SYMPTOM AND FALSE AS A
CAUSE.** The port does not zero the lanes; it COMPUTES them, and the computation's input is
already zero. **THIS IS THE THIRD TIME IN THIS TREE THAT A PIN FILE'S NAMED CAUSE WAS
WRONG** (the first two: `.agents/slop/execfix/REPORT.md`, `.agents/slop/convfix/REPORT.md`).

**⇒ AND THE PIN FILE's FAMILY LIST IS WRONG IN ITS DETAIL: `maxpair` IS **NOT** IN THE 29.**
The maxpair family was fixed earlier (the `--refresh` line at `pins.rows:36` DROPPED all 9
maxpair names). The 29 are:

| # | row | # | row | # | row |
|---|---|---|---|---|---|
| 1 | `alu.CMPNE.f.b0` | 11 | `f32.shr.0.b0` | 21 | `i32.sqrt.0.b0` |
| 2 | `bool.matmul.0.b0` | 12 | `f32.sqrt.0.b0` | 22 | `u32.cmod.0.b0` |
| 3 | `bool.ne.0.b0` | 13 | `i32.cmod.0.b0` | 23 | `u32.exp2.0.b0` |
| 4 | `bool.neg.0.b0` | 14 | `i32.exp2.0.b0` | 24 | `u32.log2.0.b0` |
| 5 | `bool.sub.0.b0` | 15 | `i32.log2.0.b0` | 25 | `u32.ne.0.b0` |
| 6 | `f32.bitcast.0.b0` | 16 | `i32.ne.0.b0` | 26 | `u32.recip.0.b0` |
| 7 | `f32.cmod.0.b0` | 17 | `i32.recip.0.b0` | 27 | `u32.shl.0.b0` |
| 8 | `f32.exp2.0.b0` | 18 | `i32.shl.0.b0` | 28 | `u32.shr.0.b0` |
| 9 | `f32.log2.0.b0` | 19 | `i32.shr.0.b0` | 29 | `u32.sqrt.0.b0` |
| 10 | `f32.recip.0.b0` | 20 | `i32.shl.0.b0` | | |

---

## SECTION 2 — THE POPULATION, THE BASELINE, AND THE INSTRUMENTS

**THE POPULATION** is the tree's own fixture file, READ IN PLACE AND NEVER WRITTEN:
`gates/ops_python_exec-fixtures.rows`, **153 records** (`@ <name> <gx> <gy> <gz> <vals…>`
then the packet verbatim).

| lane | instrument | command | rows | seconds |
|---|---|---|---|---|
| `bd` (the port) | `.agents/slop/execfix/census.py` (the tree's own) | `.venv/bin/python .agents/slop/execfix/census.py <exe> .agents/slop/vslane/census-base.rows` | **365** | **1235 s user / 27:02 wall** |
| `py` (the oracle) | `gates/ops_python_exec-gen.py` (the tree's own fixture generator and CPython lane, READ-ONLY — no `--write`) | `.venv/bin/python gates/ops_python_exec-gen.py > .agents/slop/vslane/oracle.rows` | **366** (365 + the `py-done=1` marker) | **2.5** |

**THE BASELINE DIFF (denominator: 365 port rows):**

```
DIVERGENCES: 29
```

**⇒ 29 DIVERGENCES, AND THEY ARE EXACTLY THE 29 NAMES IN `gates/ops_python_exec-pins.rows`
(lines 38-66). NO ROW DIVERGED OUTSIDE THE PINNED SET AND NO PINNED ROW WAS ALREADY
AGREEING.** Reading: `.agents/slop/vslane/census-base.rows`.

**THE INSTRUMENT I ADDED** — `.agents/slop/vslane/subset.py` — runs the tree's OWN
`execfix/census.py:run_one` (the same reader, the same spelling, the same
one-process-per-fixture contract) on a NAMED SUBSET, because the full census is 27 minutes
and a fix has to be measurable inside one unit. **THE POPULATION IS STILL THE TREE's OWN
FIXTURE FILE**; a subset is a subset of it and invents nothing, and a name that is not a
fixture is a REFUSAL (`rc=3`), not a silent skip.

---

## SECTION 3 — THE FOUR CAUSES, EACH MEASURED IN ISOLATION

### CAUSE #1 — `symbolic.bend`'s `f32_where` HAD ITS ARMS SWAPPED — **4 ROWS**

`tinybendygrad/uop/symbolic.bend:872` (before the fix):

```python
def f32_where(cond: Bool, b: F32, c: F32) -> F32: Bool.pick(F32, cond, c, b)
```

**UPSTREAM IS `ops.py:1419`: `Ops.WHERE: lambda x,y,z: y if x else z`.** `Bool.pick(T, cond,
then, else)` PICKS `then` WHEN `cond` HOLDS, so `y if x else z` IS `pick(cond, y, z)` — and
THE PORT SAID `pick(cond, c, z)`, WHICH IS `z if x else y`. **THE ARMS ARE SWAPPED.**

**THE MEASUREMENT** — `.agents/slop/vslane/alu.bend` (the template is
`.agents/slop/execfix/alu.bend`):

```
BEFORE: f32 WHERE(0.0,-1.0,1.0) = CFloat(bits=3212836864)   # -1.0
AFTER : f32 WHERE(0.0,-1.0,1.0) = CFloat(bits=1065353216)   #  1.0
```

**WHY IT MATTERS — THE PACKET, TRACED LINE BY LINE.** `f32.sqrt.0`'s packet
(`gates/ops_python_exec-fixtures.rows`, record `f32.sqrt.0`) is:

```
13: INDEX f32 k:idx:0 10 12      # the LOAD's lane 0 = 1.0
21: CONST weakfloat f:000080bf   # -1.0
22: CAST f32 - 21
23: CONST weakfloat f:00000000   #  0.0
24: CAST f32 - 23
25: CONST weakfloat f:0000803f   #  1.0
26: CAST f32 - 25
27: CMPLT bool - 13 24           # 1.0 <  0.0  -> False
28: CMPNE bool - 13 24           # 1.0 != 0.0  -> True
29: WHERE f32 - 27 22 26         # cond=False, y=-1.0, z= 1.0
30: WHERE f32 - 28 29 24         # cond=True,  y=  ,  z= 0.0
31: MUL   f32 - 13 30
32: SQRT  f32 - 31
51: STACK f32 - 32 38 44 50
53: STORE void k:vec:4 52 51
```

| uop | upstream | the port (before) | the port (after) |
|---|---|---|---|
| 27 | `False` | `False` | `False` |
| 28 | `True` | `True` | `True` |
| 29 | `1.0` | `-1.0` | `1.0` |
| 30 | `1.0` | `0.0` | `1.0` |
| 31 | `1.0` | `0.0` | `1.0` |
| 32 | `1.0` | `0.0` | `1.0` |

**⇒ THE PORT's `SQRT` READ A ZERO BECAUSE ITS `WHERE` READ THE WRONG ARM, NOT BECAUSE
ITS `SQRT` WAS WRONG. AND `abs` IS `WHERE(x < 0, -x, x)`, SO EVERY `sqrt`/`log2`/`exp2`/
`recip`/`shl`/`shr`/`cmod` OF A FLOAT TENSOR WAS AFFECTED — AND `x.abs()` IS THE SEED OF
EVERY ONE OF THEM IN `gates/ops_python_exec-gen.py`'s `SEEDS`.**

**THE 4 ROWS:** `f32.sqrt.0.b0`, `f32.log2.0.b0`, `f32.exp2.0.b0`, `f32.recip.0.b0`.
(`f32.cmod.0`, `f32.shl.0` AND `f32.shr.0` GO THROUGH THE SAME `abs` BUT ALSO THROUGH A
**CAST**, AND THE CAST IS CAUSE #3.)

**THE INTEGER LANE'S `WHERE` WAS RIGHT** — `exec_alu_i32.where` PICKS `c` WHEN
`U32.is_zero(a)`, WHICH IS "z IF x IS FALSY ELSE y", THE SAME SENTENCE WITH THE CONDITION
INVERTED. **⇒ ONLY THE FLOAT LANE WAS WRONG, AND ONLY THE FLOAT LANE'S ROWS.**

### CAUSE #2 — `symbolic.bend`'s `exec_alu_i32.cmp` IMPLEMENTED `CMPNE` AS `==` — **20 ROWS**

`tinybendygrad/uop/symbolic.bend:727` (before the fix):

```python
    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}
```

**UPSTREAM IS `ops.py:1416`: `Ops.CMPNE: operator.ne`.** `operator.ne` IS **NOT EQUAL**, AND
`U32.is_eq` IS **EQUAL**. **THE FLOAT LANE AT `exec_alu_f32.cmp` WAS RIGHT** (`F32.is_ne`),
so THE TWO LANES DISAGREED WITH EACH OTHER ON THE SAME OP.

**THE MEASUREMENT** — the same probe:

```
BEFORE: i32 CMPNE(0,1) = CBool(0)     # upstream: operator.ne(0, 1) is True
AFTER : i32 CMPNE(0,1) = CBool(1)
```

**WHY IT MATTERS — AND WHY IT IS 20 ROWS AND NOT 6.** `x != y` IS THE **SECOND HALF OF
`abs`**: TINYGRAD SPELLS `abs` AS `WHERE(x < 0, -x, x)` AND THAT WHERE'S CONDITION IS A
CMPNE. **⇒ THE WRONG COMPARISON MADE **EVERY** `abs` IN AN **INTEGER** KERNEL WRONG**, AND
WITH IT EVERY `sqrt`/`log2`/`exp2`/`recip`/`shl`/`shr`/`cmod` OF AN INTEGER TENSOR, AND EVERY
`!=` OF EVERY DTYPE.**

**THE PACKET, TRACED — `i32.sqrt.0`** (the INTEGER twin of `f32.sqrt.0`; note the WHERE is
`WHERE i32`, so the integer lane):

```
13: INDEX i32 k:idx:0 10 12      # 1
23: CMPLT bool - 13 12           # 1 <  0 -> False
24: CMPNE bool - 13 12           # 1 != 0 -> True   (the port said False: it computed ==)
25: WHERE i32 - 23 22 15         # cond=False -> z = 1
26: WHERE i32 - 24 25 12         # cond=True (upstream) -> y = 1 ; the port: cond=False -> z = 0
27: MUL   i32 - 13 26            # upstream 1*1 = 1 ; the port 1*0 = 0
28: CAST  f32 - 27               # 1.0 ; the port 0.0
47: SQRT  f32 - 28               # 1.0 ; the port 0.0
```

**THE 20 ROWS:** `i32.sqrt.0`, `i32.log2.0`, `i32.exp2.0`, `i32.recip.0`, `i32.shl.0`,
`i32.shr.0`, `i32.cmod.0`, `i32.ne.0`, `u32.sqrt.0`, `u32.log2.0`, `u32.exp2.0`,
`u32.recip.0`, `u32.shl.0`, `u32.shr.0`, `u32.cmod.0`, `u32.ne.0`, `bool.ne.0`,
`bool.neg.0`, `bool.sub.0`, `bool.matmul.0`.

### CAUSE #3 — `ops_python.bend`'s `Prog.cast.dt` KEPT THE **FLOAT's** BIT PATTERN FOR A
FLOAT-TO-INT CAST — **4 ROWS**

`tinybendygrad/runtime/ops_python.bend` (before the fix):

```python
      Bool.pick(Elem, S.Dt.is_float(src), elem_of(F32.bits(F32.trunc(f_of(e))), dst),
```

**UPSTREAM IS `ops_python.py:137-138`:**

```python
values[u] = [truncate.get(u.dtype, lambda dt: dt)(u.dtype.const(x)) for x in src_values[0]]
```

**AND `DType.const` (tinygrad/dtype.py:84) IS THE VALUE CONVERSION:**
`float(val)` FOR A FLOAT, `bool(val)` FOR A BOOL, AND **`int(val)`** FOR AN INTEGER —
**PYTHON'S TRUNCATION TOWARD ZERO**. `truncate.get` (dtype.py:289) IS THEN THE RANGE
(`ctypes.c_int32(...)`/`ctypes.c_uint32(...)`).

**⇒ THE PORT's ARM READ `F32.bits(F32.trunc(f_of(e)))`, WHICH IS THE BIT PATTERN OF THE
**FLOAT** 1.0 (0x3F800000) AND NOT THE **INTEGER** 1 (0x00000001) THAT `int(1.0)` IS.**

**THE MEASUREMENT** — `f32.bitcast.0`'s OUTPUT BUFFER 0:

| | bytes | as int32 |
|---|---|---|
| upstream | `01000000020000000300000004000000…` | `[1, 2, 3, 4, …]` |
| the port (before) | `0000803f0000004000004040000080…` | `[0x3f800000, 0x40000000, …]` — THE FLOATS' OWN BIT PATTERNS |

**⇒ AND THE SAME ARM IS WHAT `x.abs().cast(dtypes.int32)` GOES THROUGH**, so it ALSO broke
`f32.shl.0`, `f32.shr.0` AND `f32.cmod.0` — the seed `x.abs().cast(dtypes.int32) << 2`
reads `SHL(0x3f800000, 2)` IN THE PORT AND `SHL(1, 2)` UPSTREAM.

**THE 4 ROWS:** `f32.bitcast.0.b0`, `f32.shl.0.b0`, `f32.shr.0.b0`, `f32.cmod.0.b0`.

**⇒ AND THE TASK'S WARNING IS ANSWERED HERE: `bitcast` IS **NOT** AN ALU OP, IT IS A CAST,
AND IT IS **NOT** FIXED BY ANY `exec_alu` CHANGE. IT IS FIXED BY CAUSE #3, AND IT IS
CLOSED** (`f32.bitcast.0.b0` NOW AGREES).

### CAUSE #4 — `ops_python.bend`'s STORE WROTE THE VALUE'S OWN BITS WHERE UPSTREAM WRITES
THE VALUE **CONVERTED TO THE BUFFER** — **1 ROW**

**UPSTREAM'S `_store` (ops_python.py:29-33):**

```python
def _store(m, i, v, dtype: DType):
  if i < 0 or i >= len(m): raise IndexError(...)
  if (w:=m.nbytes // len(m)) >= dtype.itemsize: m[i] = to_storage_scalar(v, dtype)
  else: ...
```

**`m` IS THE BUFFER'S OWN MEMORYVIEW, AND ITS ELEMENT TYPE IS THE BUFFER'S OWN**
(`storage_fmt_for_dtype(u.dtype)`, ops_python.py:99). **⇒ THE WRITE IS `m[i] = v` INTO A
MEMORYVIEW OF THE BUFFER's TYPE, SO THE VALUE IS **CONVERTED TO THE BUFFER** AND IS NOT
WRITTEN AS ITS OWN BITS.**

**THE MEASUREMENT — `alu.CMPNE.f`**, WHOSE STORE WRITES A **BOOL** INTO AN **F32** BUFFER:

| | output buffer 0 | as f32 |
|---|---|---|
| upstream | `0000803f00000000` | `[1.0, 0.0]` — `m[0] = True` INTO A `'f'` MEMORYVIEW IS **1.0f** |
| the port (before) | `0100000000000000` | the **INTEGER** 1 |

**⇒ THE PORT STORED THE BOOL'S BIT PATTERN AND UPSTREAM STORED THE FLOAT 1.0.**

**THE 1 ROW:** `alu.CMPNE.f.b0`.

**⇒ AND THE CONVERSION IS **NOT** A SECOND CONVERSION: upstream's CAST IS
`truncate.get(u.dtype)(u.dtype.const(x))` AND upstream's STORE IS `m[i] = value` INTO A
MEMORYVIEW OF THE BUFFER's TYPE, AND FOR THE FOUR v1 LANES `DType.const` AND THE MEMORYVIEW
ARE THE SAME CONVERSION. ⇒ THE STORE **REUSES `Prog.cast.dt`** WITH THE BUFFER's DTYPE AS
THE TARGET, WHICH IS WHY `Buf` NOW CARRIES ITS DTYPE AS A FOURTH FIELD.**

---

## SECTION 4 — THE FIX, AND WHERE IT LIVES

| # | file | what changed |
|---|---|---|
| 1 | `tinybendygrad/uop/symbolic.bend:872` (`f32_where`) | `Bool.pick(F32, cond, c, b)` → **`Bool.pick(F32, cond, b, c)`** |
| 2 | `tinybendygrad/uop/symbolic.bend:727` (`exec_alu_i32.cmp`) | `U32.is_eq(a, b)` → **`U32.is_ne(a, b)`** |
| 3 | `tinybendygrad/runtime/ops_python.bend` (`Prog.cast.dt`) | the float→int arm reads **`f32_int_bits(f_of(e))`** — a new helper that is `int(x)` AS THE TWO's-COMPLEMENT BITS OF A 32-BIT INT |
| 4 | `tinybendygrad/runtime/ops_python.bend` (`Buf`, `Prog.store.bits`) | `Buf` GAINS ITS **DTYPE** AS A FOURTH FIELD, AND THE STORE WRITES **`Prog.store.bits`**, WHICH CONVERTS THE VALUE TO THE BUFFER's DTYPE **WITH `Prog.cast.dt`** |

**`f32_int_bits` AND WHY IT IS NOT `F32.to_u32`:** `F32.to_u32` TRUNCATES TOWARD ZERO —
WHICH IS HALF OF WHAT IS WANTED — BUT IT **CLAMPS A NEGATIVE TO ZERO**. MEASURED
(`.agents/slop/vslane/f32int.bend`): `F32.to_u32(-1.0)` IS `0` AND NOT `4294967295`, AND
`F32.to_u32(2.9)` IS `2` (SO IT TRUNCATES). ⇒ THE HELPER TAKES THE MAGNITUDE AND PUTS THE
SIGN BACK BY THE SUBTRACTION, WHICH IS THE TWO's COMPLEMENT OF THE MAGNITUDE.

**`Prog.store.bits` AND WHY IT IS THE IDENTITY IN THE COMMON CASE:**

```python
def Prog.store.bits(+p: Prog, +u: Uop, +j: U32) -> U32:
  Elem.bits(Prog.cast.dt(Buf.dt(Prog.buf(p, u)), Elem.dt(Prog.store.elem(p, u, j)),
    Prog.store.elem(p, u, j)))
```

**⇒ WHEN THE VALUE's DTYPE IS THE BUFFER's, `Prog.cast.dt` IS THE IDENTITY** (a float into
an f32 buffer is `F32.bits(F32.from_bits(b))`; an int into an int buffer is
`elem_of(Elem.bits(e), dst)`; a bool into a bool buffer is `Bool.to_u32(is_true)`), **SO THE
124 ROWS THAT ALREADY AGREED ARE BIT-IDENTICAL AFTER THE FIX — MEASURED, SECTION 5.**

---

## SECTION 5 — THE MEASUREMENTS AFTER THE FIX

### 5.1 THE FULL CENSUS — 153 FIXTURES, 365 ROWS

```
.venv/bin/python .agents/slop/execfix/census.py <exe> .agents/slop/vslane/census-after.rows
# 153 fixtures, 365 rows -> .agents/slop/vslane/census-after.rows
# 25:24.21 total
```

```
DIVERGENCES BEFORE: 29
DIVERGENCES AFTER : 0
REGRESSIONS (agreed before, diverge now): 0
PINNED ROWS THAT NOW AGREE: 29 of 29
key sets equal (oracle-minus-py-done vs after): True
```

**⇒ 0 DIVERGENCES OF 365 ROWS. NOTHING REGRESSED. EVERY ROW THE ORACLE AND THE PORT BOTH
PRODUCE IS BYTE-IDENTICAL.**

### 5.2 THE 29 PINNED ROWS THAT NOW AGREE, BY NAME

`alu.CMPNE.f.b0`, `bool.matmul.0.b0`, `bool.ne.0.b0`, `bool.neg.0.b0`, `bool.sub.0.b0`,
`f32.bitcast.0.b0`, `f32.cmod.0.b0`, `f32.exp2.0.b0`, `f32.log2.0.b0`, `f32.recip.0.b0`,
`f32.shl.0.b0`, `f32.shr.0.b0`, `f32.sqrt.0.b0`, `i32.cmod.0.b0`, `i32.exp2.0.b0`,
`i32.log2.0.b0`, `i32.ne.0.b0`, `i32.recip.0.b0`, `i32.shl.0.b0`, `i32.shr.0.b0`,
`i32.sqrt.0.b0`, `u32.cmod.0.b0`, `u32.exp2.0.b0`, `u32.log2.0.b0`, `u32.ne.0.b0`,
`u32.recip.0.b0`, `u32.shl.0.b0`, `u32.shr.0.b0`, `u32.sqrt.0.b0`.

### 5.3 THE E2E GATE (THE ONE GATE THE BRIEF ALLOWS)

```
.venv/bin/python gates/ops_bend_exec-e2e.py
== add4: bend=[11.0, 22.0, 33.0, 44.0] python=[11.0, 22.0, 33.0, 44.0] MATCH
== sum4: bend=10.0 python=10.0 MATCH
== addi32: bend=[2, 4, 6, 8] python=[2, 4, 6, 8] MATCH
== addu32: bend=[8, 9, 10, 11] python=[8, 9, 10, 11] MATCH
== cast: bend=[2.0, 3.0, 4.0, 5.0] python=[2.0, 3.0, 4.0, 5.0] MATCH
== cmp: bend=[False, False, True, True] python=[False, False, True, True] MATCH
== dot: bend=[[180.0, 200.0, 220.0, 240.0], …] python=[[180.0, 200.0, 220.0, 240.0], …] MATCH
# 7 match, 0 mismatch-or-refused
```

**⇒ STILL 7 MATCH. UNCHANGED.**

### 5.4 THE COMPILATION GATE

```
./bin/bend tinybendygrad/runtime/ops_python.bend --check-only   →  ALL PROOFS CHECK
./bin/bend tinybendygrad/uop/symbolic.bend --check-only         →  ALL PROOFS CHECK
```

---

## SECTION 6 — THE CONTROL: FOUR PLANTS, AND ONE JOINT PLANT

**THE PLANTS** (`.agents/slop/vslane/plant.py`) REVERT **ONE** FIX AT A TIME **IN A COPY** OF
THE PORT's OWN TREE (`.agents/slop/vslane/plant/tree/`) AND REBUILD IT WITH THE TREE's OWN
`bin/bend`. **THE PORT's FILES ARE NEVER TOUCHED** — THE COPY IS WHAT BREAKS. THE COPY IS A
WHOLE `tinybendygrad/` TREE BECAUSE `ops_python.bend`'s IMPORTS ARE RELATIVE.

```
.venv/bin/python .agents/slop/vslane/plant.py            # all four, then the joint one
```

| plant | the one line it reverts | rows that diverge again |
|---|---|---|
| `where` | `f32_where` → `Bool.pick(F32, cond, c, b)` | **4**: `f32.sqrt.0.b0`, `f32.log2.0.b0`, `f32.exp2.0.b0`, `f32.recip.0.b0` |
| `cmpne` | `exec_alu_i32.cmp`'s `CMPNE` → `U32.is_eq` | **6 of the 6 sampled**: `bool.matmul.0.b0`, `bool.ne.0.b0`, `bool.neg.0.b0`, `bool.sub.0.b0`, `i32.sqrt.0.b0`, `u32.ne.0.b0` |
| `cast` | `Prog.cast.dt`'s float→int arm → `F32.bits(F32.trunc(f_of(e)))` | **4**: `f32.bitcast.0.b0`, `f32.cmod.0.b0`, `f32.shl.0.b0`, `f32.shr.0.b0` |
| `store` | `Prog.store.bits` → `Elem.bits(Prog.store.elem(...))` | **1**: `alu.CMPNE.f.b0` |
| **`all`** | **ALL FOUR AT ONCE** | **29 of 29**, AND **ALL 29 ARE BYTE-IDENTICAL TO THE PRE-FIX BASELINE** |

**⇒ THE JOINT PLANT IS THE STRONGEST FORM: REVERTING THE FOUR FIXES REPRODUCES THE
PRE-FIX BEHAVIOUR **BYTE FOR BYTE** (29 of 29 rows identical to
`.agents/slop/vslane/census-base.rows`). THE FIX IS THE CAUSE.**

**⇒ AND EVERY PLANTED ROW'S BYTES ARE THE BASELINE's BYTES** for every row whose cause is
the only one that touches it (the `where`, `cmpne` and `store` plants). The `cast` plant's
`f32.cmod.0`, `f32.shl.0` AND `f32.shr.0` DIFFER from the baseline **BECAUSE THE `where`
FIX IS STILL APPLIED IN THAT PLANT's TREE** AND THE TWO BUGS INTERACT THROUGH THE `abs`
CHAIN — the baseline had `abs` = 0 AND the plant has `abs` = 1, so the CAST's input
DIFFERS. THAT IS THE PLANTS BEING INDEPENDENT, AND IT IS WHY THE JOINT PLANT EXISTS.

---

## SECTION 7 — WHAT THE PIN FILE AND THE GATE WILL NOW SAY

**`gates/ops_python_exec-pins.rows` IS NOT EDITED** (it is another instrument's file), AND
**IT IS NOW A LIST OF 29 STALE PINS.** `gates/ops_python_exec-gate.py:379-386`:

```python
stale = [l for l in sorted(pinned) if l in dpy and l in dbd and dpy[l] == dbd[l]]
if stale:
    for l in stale[:12]: print(f"  {l} PIN IS STALE -- …")
    print(f"  {len(stale)} pins are stale", file=sys.stderr)
    sys.exit(FAIL)
```

**⇒ WITH 0 DIVERGENCES, EVERY ONE OF THE 29 PINNED NAMES IS IN `stale`, SO THE GATE
PRINTS `29 pins are stale` AND **EXITS 1**. THAT IS THE GATE WORKING, AND IT IS THE
POINT.** **THE PINS FILE NEEDS `--refresh`, WHICH IS **NOT MINE TO RUN OR EDIT.**

**⇒ I DID NOT RUN `gates/ops_python_exec-gate.py`, AND THE REASON IS NAMED: ITS DEFAULT
IS `--jobs 6` (`gates/ops_python_exec-gate.py:291`) AND `lane_bd` RUNS **SIX** EXECUTOR
PROCESSES CONCURRENTLY (`:216`), WHICH THE BRIEF FORBIDS ("ONE bend process at a time").
THE CLAIM ABOVE IS DERIVED FROM THE GATE's OWN CODE AND FROM MY OWN MEASUREMENT OF BOTH
LANES' ROWS, NOT FROM A GATE RUN.**

**⇒ THE OTHER THREE GATE CHECKS ARE UNAFFECTED BY NAME:** `fixtures_hold` (the fixture file
is untouched), `population_hold` (the fixture names and the oracle's names are the same
153), and `coverage_hold` (the port's `Prog.dispatch` ARM TABLE IS UNCHANGED — I ADDED NO
ARM AND REMOVED NONE).

---

## SECTION 8 — WHAT I DID **NOT** CLOSE, SPECIFICALLY AND BY NAME

1. **`exec_alu`'s TUPLE BRANCH IS STILL NOT PORTED.** `symbolic.bend` STILL PORTS ONLY THE
   SCALAR SPINE, AND THAT IS CORRECT FOR THIS POPULATION: **192899 `exec_alu` CALLS, 0 WITH
   A TUPLE OPERAND** (SECTION 1.1). **IT IS DEAD CODE ON EVERY FIXTURE THIS TREE HAS, AND
   A KERNEL THAT PUTS A TUPLE IN AN ALU OPERAND — WHICH UPSTREAM PRODUCES FROM A
   TUPLE-VALUED CONST (`Ops.CONST` WITH A TUPLE `val`) — WOULD STILL DIVERGE.** NO FIXTURE
   IN THE TREE PRODUCES ONE, SO NO ROW IN THE TREE EXERCISES IT. **THE FIX WAS NOT TO
   PORT IT; THE FIX WAS TO STOP THE PORT'S SCALAR SPINE FROM BEING WRONG ABOUT SCALARS.**
2. **`symbolic.bend`'s OWN FOLD IS STILL DEAD FOR THE INTEGER LANE, AND THAT IS NOT MY
   SCOPE.** `ops_python.bend:630-642` NAMES IT: `symbolic.bend`'s `ci_fits` IS WIRED TO
   `i64_big`, WHICH ASKS "DOES **NOT** FIT", AND `exec_alu.of2` READS IT AS "FITS", SO
   `SY.exec_alu2(Ops.MUL, int32, [CInt(6), CInt(7)])` ANSWERS `None{}`. **⇒ THE DEVICE
   CALLS THE TWO LANES DIRECTLY AND IS RIGHT; THE **FOLD** IS STILL DEAD, AND A FOLD
   THAT NEVER FIRES IS A SAFE FOLD.** I DID NOT FIX IT BECAUSE IT IS A DIFFERENT SUBJECT
   (THE REWRITER, NOT THE EXECUTOR) AND IT IS ANOTHER UNIT'S.
3. **`i32_shl` STILL REFUSES A SHIFT OF 32 OR MORE** (`symbolic.bend`'s `i32_shl.big` →
   `None{}` → THE DEVICE'S `got` TURNS IT INTO **0**). UPSTREAM's `operator.lshift` IS
   **UNBOUNDED** AND IS THEN TRUNCATED BY `truncate.get(dtypes.int32)`, SO UPSTREAM ANSWERS
   THE WRAPPED VALUE AND THE PORT ANSWERS **0**. **NO FIXTURE REACHES IT** (THE SEEDS SHIFT
   BY 2), SO NO ROW EXERCISES IT. **NOT CLOSED.**
4. **AN OUT-OF-RANGE FLOAT-TO-INT CAST: UPSTREAM RAISES, THE PORT WRAPS.** UPSTREAM'S
   `truncate.get(dtypes.int32)` IS `ctypes.c_int32(x).value`, WHICH RAISES
   `OverflowError` FOR `|x| >= 2^31`; THE PORT'S `f32_int_bits` WRAPS MOD 2^32. **NO
   FIXTURE REACHES IT** (THE SEEDS' VALUES ARE 1..8). **NOT CLOSED, AND IT IS A
   DIVERGENCE, NOT A REFUSAL.**
5. **`bool(-0.0)` IS `False` UPSTREAM AND `True` IN THE PORT.** `Elem.is_true` TESTS THE
   **BITS** (`U32.is_ne(Elem.bits(e), 0)`), AND `-0.0`'s BITS ARE `0x80000000`. THE SAME
   SPELLING IS IN `Prog.cast.dt`'s BOOL ARM. **NO FIXTURE HAS A `-0.0`** (THE SEEDS ARE
   1..8 AND `0,1,2,…,7`), SO NO ROW EXERCISES IT. **NOT CLOSED.** (I DID NOT CHANGE
   `Elem.is_true` BECAUSE IT IS ALSO THE IF-GATE AND THE LOAD GATE, AND CHANGING IT IS A
   DIFFERENT, WIDER CLAIM.)
6. **`f32_shl`'s REFUSAL IS A ZERO IN THE DEVICE.** `got` (`ops_python.bend:584`) TURNS A
   `None{}` INTO `elem_of(0, dt)`, SO A LANE THAT DECLINES TO ANSWER **ANSWERS 0** INSTEAD
   OF REFUSING. **⇒ A `None{}` IN THE ALU IS A WRONG ANSWER, NOT A REFUSAL, AND THE DEVICE
   HAS NO WAY TO SAY "I DO NOT KNOW".** THIS IS THE SHAPE THAT MADE THE `f32_where` AND THE
   `CMPNE` BUGS INVISIBLE: THE SYMPTOM WAS A PLAUSIBLE ZERO.
7. **`ops_bend.executor()`'s CACHE KEY DOES NOT COVER THE IMPORTS.** MEASURED: THE KEY IS
   `sha256(f'{ops_python.bend.mtime_ns}:{ops_python.bend.size}')` (`ops_bend.py:167`), AND A
   CHANGE TO `tinybendygrad/uop/symbolic.bend` **ALONE** LEAVES A **STALE EXECUTOR** — I
   HAD TO `touch tinybendygrad/runtime/ops_python.bend` TO FORCE THE REBUILD AFTER FIXES #1
   AND #2. **⇒ ANY UNIT THAT FIXES AN IMPORTED `.bend` MUST TOUCH THE ENTRY POINT OR IT
   WILL MEASURE THE OLD BINARY.** (I DID NOT EDIT `ops_bend.py` — IT IS NOT MINE.)
8. **THE CONVOLUTION FAMILY IS NOT RE-MEASURED BY THIS UNIT.** `.agents/slop/convfix/REPORT.md`
   MEASURED IT, AND THE FULL 153-FIXTURE CENSUS (WHICH INCLUDES `f32.matmul.0`,
   `bool.matmul.0` AND THE OTHER MOVEMENT FIXTURES) IS 0 DIVERGENCES, **BUT THE CONV
   FIXTURES THEMSELVES ARE NOT IN THE TREE's FIXTURE FILE** AND I DID NOT RE-RUN
   `.agents/slop/convfix/probe.py`. **THE E2E GATE'S `dot` ROW IS THE ONE CONV-ADJACENT ROW
   I DID RE-MEASURE, AND IT MATCHES.**

---

## SECTION 9 — THE INSTRUMENTS THIS UNIT ADDED (all under `.agents/slop/vslane/`)

| file | what it is |
|---|---|
| `REPORT.md` | this file |
| `census-base.rows` | the port's 365 rows BEFORE the fix (`execfix/census.py`, 27:02) |
| `census-after.rows` | the port's 365 rows AFTER the fix (`execfix/census.py`, 25:24) |
| `census-fix12.rows` | the 29 pinned fixtures after fixes #1+#2 (3:22) |
| `census-fix1234.rows` | the 29 pinned fixtures after all four fixes (4:43) |
| `census-final.rows` | the 29 pinned fixtures with the FINAL bytes (5:00) |
| `oracle.rows` | the 366 oracle rows (`gates/ops_python_exec-gen.py`, 2.5 s) |
| `oracle.err` | the oracle's stderr |
| `subset.py` | the census on a NAMED SUBSET, using the tree's own `run_one` |
| `plant.py` | the four one-line PLANTS and the joint plant, over a COPY of the tree |
| `alu.bend` | the ALU lane probe (the template is `execfix/alu.bend`) |
| `f32int.bend` | what `F32.to_u32` actually does |
| `trace_upstream.py` | upstream's own `exec_alu` calls, one per ALU op of one fixture |
| `trace_values.py` | upstream's own `values` arena, read with `sys.settrace` |
| `tuple_census.py` | does the tuple branch ever fire? (192899 calls, 0 tuples) |
| `tuple-census.rows` | its reading |
| `rows.py` | the 29 rows with their packets and their two decoded answers |

## LOG

* 2026-10-26T15:33:01Z — report created, before any other action, as instructed.
* 2026-10-26T15:35Z — read `symbolic.bend` and `ops_python.bend`; found the port's own header
  at `ops_python.bend:124-130` naming the tuple branch as DEFERRED.
* 2026-10-26T15:45Z — baseline census run (153 fixtures, 365 rows, 27:02) and the oracle
  lane run (366 rows, 2.5 s). **29 divergences, exactly the 29 pinned names.**
* 2026-10-26T16:00Z — **upstream's `exec_alu` traced: the tuple branch NEVER FIRES for
  this family.** Upstream's ALU is scalar here too.
* 2026-10-26T16:10Z — upstream's `values` arena read with `sys.settrace`: the vector lanes
  live in the LOAD and the STACK, not in the ALU.
* 2026-10-26T16:20Z — the ALU lane probe answers: **`i32 CMPNE(0,1) = CBool(0)`** and
  **`f32 WHERE(0.0,-1.0,1.0) = CFloat(-1.0)`**. **TWO ALU CAUSES FOUND.**
* 2026-10-26T16:35Z — the `f32_where` and the `i32 CMPNE` fixes landed; the 29-fixture
  subset went from 29 divergences to **5**.
* 2026-10-26T17:05Z — the `Prog.cast.dt` fix and the STORE fix landed; the 29-fixture
  subset went to **0**.
* 2026-10-26T17:40Z — the FULL 153-fixture census: **0 divergences of 365 rows, 0
  regressions.** `gates/ops_bend_exec-e2e.py`: **7 match**.
* 2026-10-26T18:00Z — the four PLANTS and the JOINT PLANT: every plant puts its own rows
  back, and the joint plant reproduces the pre-fix rows **byte for byte (29 of 29)**.
* 2026-10-26T18:15Z — the tuple-branch census over the whole population: **192899 calls,
  0 tuples.**
* 2026-10-26T18:30Z — the headers of both files brought back into truth; both
  `--check-only` clean; the final subset run: **0 divergences**.
