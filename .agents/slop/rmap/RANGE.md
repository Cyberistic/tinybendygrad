# THE RANGE MAP — **THE MEASUREMENT, AND THE **ONE** DISCREPANCY THAT IS LEFT**

## WHAT LANDED

**⇒ `tinybendygrad/schedule/rangify.bend` (119 DEFS) AND `tinybendygrad/schedule/indexing.bend`
CARRY **THE RANGE MAP** — UPSTREAM's `ctx.range_map`, THE `(INPUT RANGES, OUTPUT RANGES)`
PAIR PER NODE — WHICH IS **THE HALF UPSTREAM DELETES AFTER USING IT**
(`del ctx.realize_map[s]`, `indexing.py:88`).**

**⇒ ⇒ AND THE PORT'S OWN **CONTEXT TYPE** IS UPSTREAM's `IndexingContext` FIELD FOR FIELD:
`IxCtx{rmap: IxMap, nrem: IxSet, rngm: IxRMap, ridx: U32}` (`indexing.bend:196`) IS
`realize_map`, `non_removable`, `range_map`, `range_idx` (`indexing.py:11-17`).**
**⇒ ⇒ ⇒ SO **THE PORT HAD THE **DATA STRUCTURES** AND NOT THE **ALGORITHM THAT FILLS THEM** —
AND THE ALGORITHM IS NOW THERE.**

## THE MEASUREMENT, AGAINST **UPSTREAM's OWN CALL**

**⇒ THE ORACLE (`.agents/slop/rangify/rr-oracle.py`) **SPIES ON UPSTREAM's OWN
`tinygrad.schedule.indexing.run_rangeify`** **AND ON THE `IndexingContext` IT MUTATES**, ON A
REAL PROGRAM (`(4,5) = (4,3) @ (3,5)`), AND PRINTS UPSTREAM's OWN `realize_map`,
`range_map` AND THE 27-NODE OUTPUT. **⇒ SO NOTHING IS TRANSCRIBED.**

**⇒ AND THE COMPARISON IS `.agents/slop/rmap/cmp.py` (MINE, 2026-10-28), WHICH READS THE
ORACLE'S PUBLISHED ROWS AND THE PORT's OWN ROWS AND COMPARES THEM **ENTRY BY ENTRY** ON THE
**NODE ID** AND THE **INPUT** AND **OUTPUT** AXIS LISTS — **⇒ AND THE PORT's OWN DUMP
SPELLING IS THE ORACLE's, SO THERE IS **NO TRANSLATOR**.**

```
OK  C1 the realize map AGREE (denominator=1 node)
    C2 the range map: 5 of 11 entries AGREE (denominator=11), 6 DIFFER
        agree : [16, 17, 18, 19, 20]
        differ: [1, 5, 7, 11, 13, 15]
```

**⇒ ⇒ ⇒ SO **5 OF 11 AGREE** — AND **THE 5 THAT AGREE ARE EXACTLY THE **FIVE** NODES THAT
**HAVE NO `_apply_reshape` IN THEIR INPUT RANGES** (`#16 PERMUTE`, `#17 MUL`, `#18 PERMUTE`,
`#19 REDUCE`, `#20 STORE`).**

## ⇒ ⇒ ⇒ AND **ALL SIX DIFFERENCES ARE **ONE** WALL, AND IT IS **NAMED**

**⇒ UPSTREAM'S INPUT RANGE FOR THOSE SIX NODES IS AN **AFFINE EXPRESSION**
`<ADD:none:MUL,RANGE>` — **⇒ AND UPSTREAM BUILDS IT IN `_apply_reshape`
(`indexing.py:155-167`), WHICH IS **THE WALL, IN FULL** (`indexing.bend:735`).**

**⇒ ⇒ AND THE PORT'S OWN ANSWER IS **THE INPUT RANGE ITSELF** — **⇒ AND THAT IS WHAT
`rangify.bend`'s OWN HEADER ALREADY SAYS** (`:66-70`): *"EXPRESSION IN CPython
(`ADD:none:MUL,RANGE`) AND THE PORT CANNOT BUILD IT (W-A: `UOp.sink`, `usum`, `%`, `//` AND A
`symbolic` REWRITER)".***

**⇒ ⇒ ⇒ SO THE DIFFERENCE IS **NOT** A BUG IN THE RANGE MAP's **ALGORITHM** — IT IS **THE
MISSING `symbolic` REWRITER**, **⇒ AND THE PORT CANNOT BUILD AN AFFINE EXPRESSION AT ALL,
SO **ITS ANSWER IS THE NEXT BEST THING AND IT SAYS SO.****

**⇒ ⇒ ⇒ AND **THE COMPARISON **NAMES** THE SIX THAT DIFFER AND PRINTS **BOTH** SIDES FOR EACH
— **⇒ BECAUSE A COMPARISON THAT HUNTS FOR A GREEN VERDICT IS NOT A COMPARISON.**

## ⇒ ⇒ ⇒ AND **A SECOND, SMALLER DISCREPANCY, MEASURED 2026-10-29 — **THREE **EXTRA**
ENTRIES IN THE PORT, ALL **CONST** NODES

**⇒ MEASURED, THE PORT'S RANGE MAP HAS **14** ENTRIES AND UPSTREAM'S HAS **11**, AND **THE
THREE EXTRA ARE **EXACTLY** THE `CONST` NODES AT TOPOSORT POSITIONS **0**, **6** AND **12**:**

| | the port | upstream |
|---|---|---|
| the keys | `0, 1, 5, 6, 7, 11, 12, 13, 15, 16, 17, 18, 19, 20` | `1, 5, 7, 11, 13, 15, 16, 17, 18, 19, 20` |
| the extras | **`0`, `6`, `12`** — ALL `CONST` | — |

**⇒ ⇒ AND **THE RULE THAT DECIDES IT IS **UPSTREAM's `continue`**, AND IT IS MEASURED BY
READING UPSTREAM's OWN LOOP (`indexing.py:199-306`) AGAINST **UPSTREAM's OWN CAPTURED
CONTEXT** (THE ORACLE'S):**

```python
consumer_rngs = [broadcast_rngs(c, x, rctx.range_map[c][0]) for c in consumer_map[x] if c in rctx.range_map]
if x in rctx.realize_map: ...
elif len(consumer_rngs) == 0:
  continue                      # <<< THIS SKIPS `rctx.range_map[x] = (rngs, out_rngs)` AT :306
```

**⇒ ⇒ ⇒ AND **THE `continue` IS **THE WHOLE DIFFERENCE**, AND IT IS MEASURED **ON UPSTREAM's
OWN GRAPH**: A **CONST** HAS **NO CONSUMER THAT IS IN THE RANGE MAP** — **⇒ AND THE CAPTURE
SHOWS IT DIRECTLY:**
```
#   #0   in_rm=False consumers=[]
#   #2   in_rm=False consumers=[(4, 'STACK'), (10, 'STACK')]
#   #6   in_rm=False consumers=[]
```
**⇒ ⇒ ⇒ ⇒ SO **A CONST'S CONSUMERS ARE `STACK`s, AND A `STACK` IS **NOT** IN THE RANGE MAP
(ITS KEYS ARE `[1, 5, 7, 11, 13, 15, 16, 17, 18, 19, 20]` — **NO `STACK`**), **⇒ ⇒ ⇒ SO
UPSTREAM'S `consumer_rngs` IS EMPTY FOR EVERY CONST AND EVERY CONST GETS **NO** ENTRY.**

**⇒ ⇒ ⇒ ⇒ **⇒ AND THIS IS **THE THIRD** DEFECT OF **THE SAME CLASS** IN THIS LANE, AND THE
CLASS IS NOW MEASURED **THREE** TIMES: **A DEF (OR A BRANCH) THAT NOTHING READS IS NOT A
DEF THAT WORKS.**
1. `F.rng_width`'s `None{}` FOR AN AFTER-BOUND RANGE — **AND IT READ LIKE A VALUE OF ZERO
   IN THE `vms` TABLE** (MEASURED: EVERY VMAX WAS ZERO WHILE THE TABLE's LENGTH WAS RIGHT).
2. `eng_op_name`'s `OTHER` FOR EVERY OP OUTSIDE A TEN-OP TABLE — **AND IT READ LIKE "AN OP I
   DO NOT KNOW" WHERE THE PORT's OWN `Ops.name.of` KNOWS ALL 75.**
3. **⇒ AND NOW: THE PORT's RANGE MAP GIVES **THREE CONSTs** AN ENTRY WHERE UPSTREAM GIVES
   **NONE**, **⇒ ⇒ ⇒ SO **THE PORT's CONSUMER TEST IS **NOT** "THE CONSUMER IS IN THE RANGE
   MAP"** (WHICH IS UPSTREAM's) **BUT "**THE CONSUMER **COUNT** IS NON-ZERO**"** — **⇒ ⇒ ⇒
   AND THE CONSTs' CONSUMERS ARE `STACK`s, **⇒ ⇒ ⇒ ⇒ ⇒ SO **THE PORT MUST **COUNT THE
   RANGES**, NOT THE CONSUMERS** — **⇒ ⇒ ⇒ ⇒ ⇒ **AND `broadcast_rngs` IS WHAT FILTERS A
   CONSUMER's RANGES DOWN TO NONE** (UPSTREAM's `if j >= nleft` **DROPS** EVERY RANGE FOR A
   CONST, **⇒ MEASURED DIRECTLY**: FOR A CONST (SHAPE `()`) CONSUMED BY A `STACK` (SHAPE
   `(2,)`), `nleft = 2 - 0 = 2`, THE RANGE TUPLE HAS **ONE** ELEMENT (`j = 0`), AND
   `0 >= 2` IS **FALSE** — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ SO **UPSTREAM'S `consumer_rngs` IS `[]` AND THE
   CONST GETS **NO** ENTRY**, AND **THE PORT MUST REPRODUCE THAT EXACTLY**.)**

**⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND NOTE: **THE PORT's `broadcast_rngs` ALREADY HAS THE `j >= nleft`
FILTER** (`indexing.bend`'s `ix_br_one`, WHICH IS CORRECT) **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ SO THE
FIX IS **THE CALL SITE'S ARGUMENT ORDER**, WHICH IS ALREADY CORRECT (`op` = THE CONSUMER's OP,
`src` = **THE NODE's** SHAPE, `x` = **THE CONSUMER's** SHAPE — **⇒ AND `ix_bax_nleft(src, x)`
COMPUTES `len(x) - len(src)` = UPSTREAM's `len(x.shape) - len(src.shape)`**). **⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ **⇒ SO **THE REMAINDER IS **THE **COUNT** OF THE **RANGES** RATHER THAN THE
**CONSUMERS** — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND THAT IS **ONE LINE** IN
`rangify.bend`'s `rr_p1`, WHERE `cnt` IS COMPUTED FROM `rr_cons_rngs` (THE **CONSUMERS**)
INSTEAD OF FROM `rr_one_rngs` (THE **RANGES**).****

## ⇒ ⇒ ⇒ AND **THE THREE DEAD-CODE DEFECTS THE RANGE-MAP WORK FOUND** — ALL THREE WERE
**ALREADY FIXED** BY ANOTHER UNIT WHILE THIS ONE RAN, AND **THE REPORT BELOW IS THE
EVIDENCE THAT THEY WERE REAL**:
1. `broadcast_rngs` WAS **INVERTED** (IT KEPT THE RANGE WHERE UPSTREAM **REPLACES** IT WITH
   A `CONST(0)`, AND DROPPED IT WHERE UPSTREAM KEEPS IT) — **⇒ AND IT HAD **NO ROW**:
   `indexing.bend`'s `main()` READS NONE OF IT — **⇒ ⇒ ⇒ AND IT IS NOW FIXED
   (`indexing.bend`'s `ix_br_one` KEEPS `r` IFF `j >= nleft`, WITH THE `j == nleft` CASE
   KEPT).**
2. `IxRngs` HAD **NO KEY** (`{inp, outp}`) AND `ix_rngm_k` READ THE NODE ID **"BY
   CONVENTION" — OUT OF THE `inp` LIST'S HEAD** — **⇒ ⇒ ⇒ SO **THE RANGE MAP WAS
   **UNLOOKABLE**.** **⇒ ⇒ ⇒ AND IT NOW HAS ONE: `IxRngs{n: U32, inp: ..., outp: ...}`.**
3. `ix_new_range` PUT A **RAW VALUE** WHERE A NODE INDEX BELONGS — **⇒ ⇒ ⇒ AND IT NOW PUTS
   A NODE (`uop/ops.bend:2522` `UOp.make.intern`, SO ONE RANGE IS ONE NODE).**

**⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND ALL THREE WERE **DEAD CODE** — NO CALLER OUTSIDE
`indexing.bend` — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ SO **THEY WERE NEVER EXERCISED, WHICH IS WHY
ALL THREE WERE INVISIBLE**, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND THAT IS **THE SAME CLASS** AS
THE `rng_width` DEFECT AND THE `OTHER` OP-NAME DEFECT.**

## THE PAYOFF, AND IT IS **NOT** YET

**⇒ MEASURED: `rr_lin_n=0` — **THE PORT's OWN `schedule()` STILL ANSWERS **ZERO** KERNELS.**
**⇒ ⇒ AND THE **CENSUS** SAYS WHY: THE PORT's RANGEIFIED GRAPH HAS **45 NODES** AND
UPSTREAM's HAS **27**, **⇒ AND THE PORT's STILL HAS `PERMUTE` WHERE UPSTREAM HAS `RANGE`.**

**⇒ ⇒ ⇒ SO **THE RANGE MAP IS **THE FIRST HALF** OF STAGE 1, AND **THE APPLY REWRITE IS
**THE SECOND HALF**, AND **NEITHER IS ENOUGH ALONE** — **⇒ AND THE MEASUREMENT NOW SAYS
EXACTLY WHAT THE APPLY NEEDS: **THE RANGE MAP's **ENTRIES** (WITH THE CONSTS FIXED) AND **THE
`symbolic` REWRITER** FOR THE AFFINE EXPRESSIONS.**

## THE COST

**ONE BEND PROCESS AT A TIME THROUGHOUT. THE COMPARISON IS ~2 s.**
