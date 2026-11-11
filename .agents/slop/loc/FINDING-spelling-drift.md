# The tree's three instruments disagreed with CPython, and all three were stale in the SAME direction

**MEASURED 2026-11-11.** This is the finding that took the corpus from
`graphs-agree=31, graphs-disagree=7, graphs-refused=5` to
`graphs-agree=38, graphs-disagree=0, graphs-refused=0`.

## THE CLASS

**A RULE SPELLED AGAINST AN OLDER UPSTREAM, AND THE SPELLING HAD DRIFTED BETWEEN THE PORT
AND THE INSTRUMENTS THAT MEASURE IT.**

**⇒ AND **THE **DRIFT **IS **NOT **DETECTABLE **BY **COMPARING **THE **TREE **TO **ITSELF**:
**THE **PORT **AND **THE **DRIVER **AND **THE **ORACLE **ALL **SAID **THE **SAME **STALE
**THING**, **SO **THEY **AGREED **WITH **EACH **OTHER **AND **DISAGREED **WITH **CPYTHON**.**

## THE THREE INSTANCES

### 1. THE PERMUTE's ORDER IS IN `src[1]`

**⇒ UPSTREAM's **`_mop` (`ops.py:784,790-791`)** **BUILDS **A **PERMUTE **AS
`UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)`**, **⇒ AND **`marg` (`ops.py:772`)
**IS ** `case Ops.PERMUTE: return self.src[1].as_shape`**, **⇒ AND **`mop_cleanup`'s
"merge **PERMUTEs" **RULE **IS **A **TWO-SRC **PATTERN**
(`UPat(Ops.PERMUTE, src=(UPat(Ops.PERMUTE, name="x2"), UPat()), name="x")`)** -- **WHICH
**ONLY **MATCHES **A **PERMUTE **THAT **HAS **AN **`src[1]`**.

**⇒ THE **PORT **SPELLED **THE **ORDER **IN **`arg`** (`ATuple{ys}`)** AT **TWELVE
**CONSTRUCTION **SITES**, **AND **READ **IT **BACK **FROM **`arg`** (`order_arg`)** -- **AND
**THE **RESHAPE **ALREADY **HAD **THE **RIGHT **READER** (`marg`**, **WHICH **READS
**`src[1]`**)**, **⇒ AND **THE **TWO **HALVES **OF **ONE **RULE **HAD **DRIFTED **APART**.

**⇒ AND **THE **PORT's **OWN **RULE **TABLE **WAS **PINNED **TO **AN **OLDER **UPSTREAM**:
**THE **PORT's **`mp_3` **QUOTED **`lambda x,x2: x2.replace(arg=tuple(x2.arg[i] for i in
x.arg))`** **AND **UPSTREAM's **CURRENT **RULE **IS
**`lambda x,x2: x2.src[0].permute(tuple(x2.marg[i] for i in x.marg))`**.

**⇒ AND **THE **READER **WAS **ALSO **WRONG **IN **A **SECOND **WAY, **AND **THAT **WAS
**CAUGHT **ONLY **BY **THE **CORPUS**: **AN **EARLIER **REVISION **OF **`perm_ds` **PASSED
**`marg(ar, i)` **AS **THE **SOURCE's **DIMS**, **AND **`marg` **IS **`src[1].as_shape`**
-- **WHICH **FOR **A **PERMUTE **IS **THE **ORDER**, **NOT **THE **SOURCE's **SHAPE**.  **⇒ SO
**THE **SHAPE **CAME **OUT **AS **THE **ORDER **PERMUTED **BY **THE **ORDER**:
**CPYTHON's **`matmul` **PERMUTE **IS **`(l0:1,l0:5,l0:3)`** **AND **THE **PORT's **WAS
**`(l0:0,l0:1,l0:2)`**.

### 2. THE `eq`/`ne`/`logical_not` FAMILY WAS SIX HALVES OF ONE RULE

**⇒ AT **THE **PIN **`f5ac54685074`**:**
```
mixin/elementwise.py:49-57    logical_not  IS  self.cast(dtypes.bool).eq(False)
mixin/elementwise.py:332-333  ne           IS  self.eq(x).logical_not()
mixin/elementwise.py:335-336  eq           IS  self._binop(Ops.CMPEQ, x, False)
mixin/elementwise.py:338-339  __ne__       IS  self.ne(x)
```
**⇒ SO **NO **OF **THEM **IS **A **`CMPNE`, **AND **UPSTREAM's **OWN **NEGATION
**DETECTION **KEYS **ON **THE **`CMPEQ` **SPELLING** (`uop/symbolic.py:349`: `neg = v.op is
Ops.CMPEQ and v.src[1].op is Ops.CONST and v.src[1].val == 0`)** -- **⇒ **A **`CMPNE` **IS
**NOT **EVEN **A **NEGATION **AS **UPSTREAM **KNOWS **IT**, **AND **SO **THE **OLD **SPELLING
**COULD **NOT **HAVE **MATCHED **ANY **OF **THE **RULES **THAT **KEY **ON **A **NEGATION**.

**⇒ AND **THE **PORT's **HALVES **WERE**: **A **`CMPNE`**, **A **DOUBLE **NEGATION**
(`eq` **= `not(not(CMPNE(x, y)))`**), **A **`CMPNE`-AGAINST-`True`**, **A **`CMPNE`**, **A
**`CMPNE`** -- **AND **TWO **OF **THEM **WERE **ALREADY **RIGHT**.

**⇒ AND **UPSTREAM's **OWN **GRADIENT **AT **THE **PIN **CONFIRMS **IT
**INDEPENDENTLY**: **`mixin/gradient.py:12` **IS ** `mask = ret.src[0].eq(ret).cast(...)`,
**`:16` **IS ** `is_zero:=(x:=ret.src[0]).eq(0)`, **`:78` **IS ** `(x.eq(y)).where(ctx, ...)`,
**AND **`:73` **IS ** `(UPat((Ops.CMPLT, Ops.CMPEQ)), lambda: (None, None))` -- **⇒ AND **NO
**`CMPNE` **ANYWHERE **IN **THE **MAX **OR **POW **GRADIENT**.

**⇒ AND **THE **PORT's **OWN **COMMENT **CLAIMED **THE **OPPOSITE **AND **WAS **FALSE **AT
**THE **PIN**: **"no **`elementwise.py` **method **emits **[`Ops.CMPEQ`]**, **so **a **rule
**that **spelled **`eq` **as **CMPEQ **would **build **a **graph **Python **never **builds"**.

### 3. THE CORPUS's OWN DRIVER AND ORACLE WERE SPELLED THE SAME OLD WAY

**⇒ `.agents/slop/graphcmp.bend`'s **`g_commute` **BUILT **A **RAW **`CMPNE`**, **AND
**`.agents/slop/graphcmp.py`'s **`g_commute` **DOCSTRING **SAID **THE **SAME **THING
("**`a != b` **-> **CMPNE**" **AND **"`(Tensor.empty(4,3) == Tensor.empty(4,3)).uop` **emits
**CMPNE **CONST **CMPNE** **rather **than **a **CMPEQ**")**.

**⇒ AND **THE **DOCSTRING **WAS **A **LIE, **MEASURED**:**
```
>>> a = Tensor.empty(4,3).uop; b = Tensor.empty(4,3).uop; n = a != b
the != node: Ops.CMPEQ
  src: Ops.CMPEQ srcs: [Ops.RESHAPE, Ops.RESHAPE]
  src: Ops.CONST srcs: []
```

**⇒ AND **THE **CLASS **IS **THE **THING **THAT **WILL **HAPPEN **AGAIN**: **AN **INSTRUMENT
**THAT **HAND-BUILDS **THE **NODES **IT **COMPARES **IS **PINNED **TO **A **SPELLING**, **AND
**A **SPELLING **ROTS**.  **⇒ AND **THE **`commute` **GRAPH **AGREED **WITH **A **STALE
**INSTRUMENT **AND **THE **CORPUS **COULD **NOT **SEE **THE **DRIFT **AT **ALL** -- **UNTIL
**THE **PORT's **OWN **`eq`/`ne` **FAMILY **WAS **SPELLED **THE **PIN's **WAY, **AND **THE
**TWO **HALVES **DISAGREED.**

**⇒ A **PAIR **OF **AGREEING **INSTRUMENTS **IS **NOT **A **WITNESS, **AND **ONLY **THE
**CPYTHON **SIDE **IS **THE **WITNESS.**

## THE FOURTH INSTANCE, WHICH IS A **GATE'S** OWN VACUOUSNESS

**⇒ THE **SIX **`eq`/`ne`/`logical_not` **GATES **ASKED **"IS **THE **OP **CMPNE?**"** -- **AND
**AFTER **THE **PORT's **FAMILY **MOVED **TO **THE **PIN's **SPELLING**, **BOTH **SIDES
**ANSWERED **"NO"**, **⇒ AND **THE **ROW **COMPARED **TWO **"NO"s **AND **ANSWERED **1**.

**⇒ THAT **IS **THE **FAILURE **THE **TREE's **RULES **NAME**: **"A **ROW **THAT **CANNOT **GO
**RED **IS **WORSE **THAN **NO **ROW"**.

**⇒ AND **THE **FIX **IS **THE **POSITIVE **FORM**: **THE **ROWS **NOW **ASK **"IS **THE **OP
**`CMPEQ`**?**, **AND **`tn_neg` **GAINED **`neg_bool_src1_is_const_false`**, **WHICH **ASKS
**THE **`CMPEQ`'s **`src[1]`'s **VALUE** -- **⇒ AND **A **`CMPEQ` **AGAINST **`True` **AND **A
**`CMPEQ` **AGAINST **`False` **ARE **THE **SAME **OP**, **⇒ AND **SO **THE **OP **ROW **ALONE
**CANNOT **DISTINGUISH **THEM**, **AND **THE **VALUE **IS **THE **WHOLE **DIFFERENCE.**

## AND THE BEND CONSTRAINTS THAT THE FIXES HIT (ALL MEASURED)

- **A MATCH **CANNOT **SCRUTINISE **A **COMPUTED **VALUE** -- "give it its own def".
- **BEND **SPENDS **A **BINDER **WHEN **IT **READS **IT** -- "consumed more than once".
- **A **RECURSIVE **CALL's **ARGUMENTS **MUST **EACH **BE **SMALLER **THAN **THE **MATCHED
  **EXPRESSION** -- "a call smaller than ...".
- **DEFS **ARE **CHECKED **IN **FILE **ORDER** -- "defs are checked in file order".
- **A **CROSS-FILE **`Found` **CANNOT **BE **BOUND **AND **READ **TWICE**, **⇒ AND **THE
  **INDEX **FORM **(`U32`) **IS **THE **ONE **A **CROSS-FILE **CALLER **WANTS**.
- **AND **A **SUB-NAMESPACE **(`shape_arg.of`) **IS **NOT **VISIBLE **FROM **ANOTHER **FILE**
  -- "a defined name" -- **⇒ AND **THE **FLAT **NAME **IS **THE **SECOND **FORM**.

## AND WHAT THE FIX COST IN DUPLICATION

**⇒ THE **PORT **HAD **THREE **COPIES **OF **THE **SHAPE-ARG **BUILDING**, **BECAUSE **EVERY
**FILE **THAT **NEEDED **IT **COULD **NOT **SEE **THE **OTHERS**: **`mixin/movement.bend`'s
**`G.stkN`**, **`mixin/gradient.bend`'s **`gstkN`** (**AND **THE **COPY **IS **THE **POINT**:
**`mixin/gradient.bend` **CANNOT **IMPORT **`mixin/movement.bend`**, **BECAUSE
**`mixin/movement.bend` **IMPORTS **`tensor.bend` **AND **`tensor.bend` **IMPORTS
**`mixin/gradient.bend`**)**, **AND **`uop/ops.bend`'s **THE **SCALAR
**`shape_to_shape_arg`**.

**⇒ AND **`uop/ops.bend` **IS **THE **ONE **FILE **EVERY **ONE **OF **THEM **CAN **SEE** --
**⇒ AND **SO **THE **TUPLE **FORM **IS **THERE** **AND **THE **OTHER **TWO **CALL **IT**,
**AND **THE **DUPLICATION **IS **THE **DEFECT **AND **NOT **THE **COPY**.**
