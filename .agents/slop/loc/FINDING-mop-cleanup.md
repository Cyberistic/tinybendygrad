# THE **CORPUS's **SEVEN **DISAGREEMENTS** HAD **ONE **ROOT **CAUSE**, AND **IT **IS **THE
# **PERMUTE's **SHAPE **SPELLING**

**⚠ THIS **RECORD's **FIRST **HYPOTHESIS **("A **MISSING **`mop_cleanup` **PASS**") **WAS
**MEASURED **AND **FALSIFIED**, **AND **THE **FULL **RECORD **IS
**`.agents/slop/loc/FINDING-spelling-drift.md`** -- **AND **THE **SHORT **VERSION **IS:
**THE **PORT **WAS **NOT **MISSING **A **PASS**, **IT **WAS **BUILDING **THE **SAME **OPS
**WITH **A **DIFFERENT **SPELLING**, **AND **THE **SPELLING **HAD **DRIFTED **BETWEEN **THE
**PORT **AND **THE **INSTRUMENTS **THAT **MEASURE **IT**.**

**AND **THE **HYPOTHESIS **WAS **FALSIFIED **BY **READING **UPSTREAM's **`mop_cleanup`
**AT **THE **PIN**: **THAT **PASS **DOES **NOT **MOVE **A **SHAPE **OUT **OF **`arg`** **AT
**ALL** -- **IT **MERGES **PERMUTES**, **MERGES **RESHAPEs**, **REMOVES **NOOP **RESHAPEs**,
**MERGES **SHRINKs**, **AND **FOUR **INDEX **RULES**.  **AND **THE **PASS **THAT **EXISTS
**IN **THE **PORT** (`uop/movement.bend`'s **RULE **TABLE**, **24 **GATE **ROWS**) **IS **PINNED
**TO **THE **OLD **UPSTREAM**.**

**AND **THE **SEVEN **DISAGREEMENTS **HAD **THREE **ROOTS**, **ALL **THE **SAME **CLASS**
(**A **RULE **SPELLED **AGAINST **AN **OLDER **UPSTREAM**), **AND **THE **FINAL **STATE **IS**:
```
graphs=38  graphs-answered=38  graphs-agree=38  graphs-disagree=0
graphs-refused=0  byte-identical=38  expect-moved=0
plants-disagree=8 of 8  cross=1 of 1  controls=5 of 5  stable-pairs=5 of 5
selfcheck=# SELFCHECK: OK  oracle-selfcheck=# ORACLE SELFCHECK: OK
```

**THE **CORPUS **WAS **RE-RUN **TWICE **ON **2026-11-10** (THE **TREE **HAS **MOVED **A
LOT **SINCE **THE **LAST **RECORD**, **AND **THE **USER **ASKED **FOR **A **RE-RUN **ONCE
**THERE **WAS **SUBSTANTIAL **PROGRESS**), **AND **IT **READS **`graphs-agree=31`,
`graphs-disagree=7`** -- **THE **SAME **SEVEN**: `binblob`, `bw`, `commute`, `flip`, `gral`,
`matmul`, `reduce`.**

**AND **THE **SEVEN **HAVE **ONE **ROOT **CAUSE**, **AND **IT **IS **NOT **THE
`ne`/`eq` **INVERSION** (WHICH **IS **FIXED, **IN **BOTH **LAYERS**, **AND **WHOSE **FIX
**DID **NOT **MOVE **THE **CORPUS** -- **BECAUSE **THE **CORPUS **NEVER **WENT **THROUGH
**THE **LAYER **THAT **FIX **CHANGED**).**

### THE MEASUREMENT — `reduce`, THE SIMPLEST OF THE SEVEN

```
OPS REACHED: py=6 bend=6 of 76 upstream ops
  ALLOC 1/1  CONST 5/3  PERMUTE 1/1  REDUCE 1/1  RESHAPE 1/1  STACK 2/1

  py#9  STACK   dtype=weakint shape=(l0:2) arg=N  src=['7', '8']
  py#10 PERMUTE  dtype=f32     shape=(l0:8,l0:4) arg=N  src=['6', '9']
  bend#7 PERMUTE dtype=f32     shape=(l0:8,l0:4) arg=n(i1,i0) src=['6']
```

**THE **SAME **PERMUTATION**, **SPELLED **DIFFERENTLY: UPSTREAM **KEEPS **THE **SHAPE
**IN **`src[1]`** (A `STACK` OF **TWO **CONSTs**), **AND **THE **PORT **PUTS **IT **IN
**`arg`** (A **CONCRETE `n(i1,i0)`**).**

### AND UPSTREAM's OWN CODE SAYS WHERE THE PERMUTATION LIVES

**`tinygrad/uop/ops.py:768-773`:**
```python
def marg(self):
  match self.op:
    case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape
    case Ops.PAD | Ops.SHRINK: return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
    case Ops.PERMUTE: return self.src[1].as_shape
```

**`src[1]`, NOT `arg`.**

### AND THE PASS THAT PUTS IT THERE IS **MISSING FROM **THE **PORT

**`tinygrad/uop/movement.py` IS **28 **LINES** AND IS **ONE **PASS**: `mop_cleanup`. ITS
RULES INCLUDE:
- **"STACK on INDEX CONST"** -- A `STACK` OVER `INDEX` CONSTs IS THE SOURCE
- **"const INDEX into STACK is src"** -- `a.src[i.val]`

**MEASURED 2026-11-10: `rg 'mop_cleanup' tinybendygrad/` FINDS **NOTHING** -- **THE **PORT
**HAS **NO **`mop_cleanup` **AT **ALL**.** **AND **THAT **IS **WHY **THE **PORT's
**PERMUTE/RESHAPE/SHRINK **CARRY **THEIR **SHAPE **IN **`arg`** **INSTEAD **OF **`src[1]`**.

### AND THE PORT's OWN `ops.bend` NAMES THE SPELLING IT CHOSE

**`tinybendygrad/uop/ops.bend:1191`:**
```
#   tuple[int, ...]         ATuple     PERMUTE arg (`movement.py:231`), UNSHARD arg
```

**THE **PORT **FOLLOWED **UPSTREAM's **SOURCE **SPELLING** (`movement.py:231` **BUILDS **THE
`arg`**) **AND **NOT **UPSTREAM's **POST-`mop_cleanup` **GRAPH** (WHICH **IS **WHAT **THE
**CORPUS **COMPARES**).** **THE **PORT **IS **CORRECT **ON **THE **UNOPTIMISED **GRAPH** **AND
**DIFFERENT **ON **THE **OPTIMISED **ONE**, **AND **THE **DIFFERENCE **IS **A **WHOLE **MISSING
**PASS**.**

**AND THE **OTHER **SIX **DISAGREE **THE **SAME **WAY**: THE **MISMATCHED **OPS **ARE
**`REDUCE`, `RESHAPE`, `SHRINK`, `MUL`, `BINARY` **AND** `AFTER` -- **THE **OPS **WHOSE **SHAPE
**ARGUMENT **DIFFERS** -- **AND **THE **PORT **REACHES **THE **SAME **OP **SET**
(`OPS REACHED: py=6 bend=6`) **SO **IT **IS **NOT **A **MISSING **OP** -- **IT **IS **A
**DIFFERENT **ARGUMENT **SPELLING**.**

**AND **THE **`ne`/`eq` **INVERSION **FIX **STAYS**: **IT **IS **A **REAL **DEFECT** (UPSTREAM's
`logical_not` **IS** `CMPEQ(CAST(a), False)` **AND **THE **PORT **WAS** `CMPNE(CAST(a), True)`),
**AND **THE **PORT's **OWN `uop/symbolic.bend` **ALREADY **BUILT **THE `CMPEQ` **SPELLING**,
**SO **THE **TWO **HALVES **HAD **DRIFTED**.** **BUT **IT **WAS **NOT **THE **CORPUS's
**CAUSE**, **AND **SAYING **SO **IS **THE **HONEST **RECORD**.**
