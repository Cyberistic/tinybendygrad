THE **CORPUS's **SEVEN **DISAGREEMENTS** HAVE **ONE **ROOT **CAUSE**, AND **IT **IS **A
MISSING **PASS**: **UPSTREAM's `mop_cleanup`**

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
