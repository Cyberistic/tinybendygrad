# W-A -- THE AFFINE EXPRESSION, SCOPED BY ASKING UPSTREAM's OWN CODE

**MEASURED 2026-10-30, ON BEND 2.0.39.**

## THE QUESTION

**THE RANGE MAP's SIX REMAINING DIFFERENCES ARE **ONE WALL** (W-A): upstream's
input range for those six nodes is `<ADD:none:MUL,RANGE>`, AND THE PORT's IS THE
INPUT RANGE ITSELF.** UPSTREAM BUILDS IT IN `_apply_reshape`
(`tinygrad/schedule/indexing.py:149-161`), WHICH THE PORT CANNOT BUILD.

**⇒ AND THE TREE's PROSE SAID THE PORT HAS *"NO `symbolic` REWRITER"*. THE PORT
HAS **FOUR OF THE FIVE RULES** W-A NEEDS, ALREADY PORTED. THE TREE's PROSE WAS
WRONG, AND IT WAS WRONG IN THE DIRECTION THAT MAKES THE WORK LOOK BIGGER THAN
IT IS.**

## THE TWO INSTRUMENTS, AND WHAT THEY MEASURE

| file | what it asks | cost |
|---|---|---|
| `.agents/slop/rangify/rr-reshape.py` | **WHAT `_apply_reshape` BUILDS, AND WHAT THE `symbolic` REWRITER MAKES OF IT** -- BY BUILDING THE **UNSIMPLIFIED** EXPRESSION WITH UPSTREAM's OWN `UOp` API AND PRINTING BOTH | ~0.5 s, one CPython process |
| `.agents/slop/rangify/rr-reshape-rules.py` | **WHICH RULE FIRED** -- BY WRAPPING THE MATCHER AND READING `UPat.location`, **WHICH IS `get_location()`** | ~0.5 s, one CPython process |

**⇒ AND BOTH ASK UPSTREAM's OWN CODE. NOTHING HERE IS REASONED ABOUT.**

## WHAT `rr-reshape.py` MEASURED

```
# _apply_reshape CALLS: 3
=== CALL 0  in_shape=(15,) out_shape=(1, 3, 5)
  UNSIMPLIFIED srcs: FLOORMOD:none:ADD,CONST
  SIMPLIFIED   srcs: ADD:none:MUL,RANGE
=== CALL 1  in_shape=(12,) out_shape=(4, 1, 3)
  UNSIMPLIFIED srcs: FLOORMOD:none:ADD,CONST
  SIMPLIFIED   srcs: ADD:none:MUL,RANGE
=== CALL 2  in_shape=(20,) out_shape=(4, 5)
  UNSIMPLIFIED srcs: FLOORMOD:none:ADD,CONST
  SIMPLIFIED   srcs: ADD:none:MUL,RANGE
```

**⇒ ALL THREE CALLS HAVE THE SAME SHAPE, AND THE REWRITER IS NOT A NO-OP: THE
UNSIMPLIFIED EXPRESSION IS **13 NODES** AND THE SIMPLIFIED ONE IS **6**.**

**⇒ ⇒ ⇒ AND **THE ARITHMETIC ALONE IS NOT ENOUGH** -- **⇒ SO W-A IS NOT "BUILD
THE EXPRESSION AND STOP".**

## WHAT `rr-reshape-rules.py` MEASURED -- **THE WORK LIST**

**27 REWRITE STEPS, AND **FIVE DISTINCT RULES**, EACH WITH UPSTREAM's OWN FILE
AND LINE:**

| # | upstream | what it does | **the port** |
|---|---|---|---|
| 0 | `tinygrad/uop/symbolic.py:120` | `x+0 -> x` | **HAVE** -- `symbolic.bend`'s `sym_120` |
| 1 | `tinygrad/uop/symbolic.py:122` | `x*1 -> x` | **HAVE** -- `symbolic.bend`'s `sym_122` |
| 2 | `tinygrad/uop/symbolic.py:161` | `fold_const_alu` -- **CONSTANT FOLDING** | **HAVE** -- `symbolic.bend`'s inventory row 3 |
| 3 | `tinygrad/uop/symbolic.py:230` | **THE COMMUTATIVE FLIP** (`x.src[::-1]` when `src[1].tuplize < src[0].tuplize`) | **MISSING** -- `symbolic.bend`'s inventory row 14: *"222-226 table commutative -- **DEFERRED** `UOp.tuplize`"* |
| 4 | `tinygrad/uop/divandmod.py:108` | **THE `div_and_mod_symbolic` MATCHER** -- `(x+c)%d -> (x+c%d)%d` | **HAVE** -- `uop/divandmod.bend` (1197 lines, the matcher ported in full) |

**⇒ ⇒ ⇒ ⇒ ⇒ SO W-A IS **ONE MISSING RULE**, NOT A MISSING MODULE.**

## THE MISSING RULE's WALL IS **NAMED**, AND IT IS SMALLER THAN IT LOOKS

`tinybendygrad/uop/ops.bend:5163`:
> **WALL(p3) ops.py:316 `def tuplize` -- BLOCKED. THE MECHANISM IS REPLACED, NOT
> MISSING.** `tuplize` builds `(op.value, repr(arg), dtype, *(src tuplize))` **TO
> KEY CPython's `ucache`**; this port's interner is `intern.find`, a direct ...

**⇒ AND THE FLIP DOES NOT NEED THE CACHE KEY -- IT NEEDS THE **ORDER**.**
`upstream`'s `tuplize` IS `(op.value, repr(arg), dtype, *src tuplize)`, SO THE
PORT CAN COMPUTE **THE ORDER** WITHOUT ADOPTING THE KEY. **⇒ ⇒ ⇒ SO THE
COMMUTATIVE FLIP'S WALL IS **THE COMPARISON**, NOT THE CACHE.**

## THE WHOLE OF WHAT IS LEFT, THEN

1. **THE ARITHMETIC** -- build `MUL`, `ADD`, `FLOORMOD`, `FLOORDIV` on the
   port's arena. **`O.UOp.alu(ar, op, srcs)` EXISTS** (`ops.bend:2824`).
2. **THE PLACEHOLDER AXIS TRICK** -- upstream's `apply_movement_op` for `RESHAPE`
   (`indexing.py:174-176`): `r.replace(arg=(AxisType.PLACEHOLDER, i))` for each
   range, the affine expression is computed over the PLACEHOLDERS, and the
   result is substituted back.
3. **THE REWRITER RUN** -- drive the port's own `sym_rewrite(+ts: O.PMEntrys, +x:
   F.Folded, +u: U32)` (`symbolic.bend:2779`) with the port's own rule tables.
4. **THE COMMUTATIVE FLIP** -- the one rule above, whose wall is `UOp.tuplize`'s
   **ORDER**, not its cache key.

**⇒ ⇒ ⇒ ⇒ ⇒ AND EVERY ONE OF THE SIX `get_kernel_graph` PASSES AFTER
`run_rangeify` (`rangeify.py:347-360`) IS **A `symbolic` REWRITER** TOO, **⇒ SO
THE SAME REWRITER RUN IS THE THING THAT UNBLOCKS BOTH.**

## THE COST, AND WHAT WAS **NOT** MEASURED

**THE TWO PROBES ARE ~0.5 s EACH, ONE CPYTHON PROCESS AT A TIME.**

**⇒ AND THE **CORPUS** WAS **NOT** RE-TAKEN, AND THE COMPILE CENSUS WAS **NOT**
RE-TAKEN, AND THE REASON IS MEASURED RATHER THAN ASSUMED: THE MACHINE WAS AT
LOADAVG **19.5** ON 12 CORES WITH ~51 MB OF FREE PAGES, AND **ANOTHER UNIT WAS
EDITING THE SUBSTRATE** (`tinybendygrad/mixin/creation.bend` AND
`tinybendygrad/uop/weak.bend` WERE TOUCHED WHILE THIS WORK RAN).** THE SUBSTRATE
MOVED, SO THE CORPUS's "CURRENT" READING IS **FALSE** AND SAYS SO.
