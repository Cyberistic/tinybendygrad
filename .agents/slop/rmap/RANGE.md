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
BAD C2 the range map: 1 of 14 entries AGREE (denominator=14), 10 DIFFER, 3 MISSING
      agree : [20]
      differ: [1, 5, 7, 11, 13, 15, 16, 17, 18, 19]
      missing: [0, 6, 12]
```

**⇒ ⇒ ⇒ SO **1 OF 14 AGREE** — AND **THAT IS **THE **CORRECTED** MEASUREMENT.**

**⇒ ⇒ ⇒ AND THE CORRECTION IS A **FINDING**, NOT A TYPO: **THE READING THIS FILE
USED TO QUOTE ("5 of 11 entries AGREE (denominator=11), 6 DIFFER", `agree : [16, 17,
18, 19, 20]`) **IS **NOT** WHAT `.agents/slop/rmap/cmp.py` PRINTS — **NOT ON THIS
TREE**, **NOT AT `33399e872`** (THE COMMIT THAT QUOTED IT), **AND NOT AT
`33399e872^`** (WHERE THE RANGE MAP HAD NOT LANDED YET: `0 of 11, 11 MISSING`).
**⇒ ⇒ ⇒ SO **THE QUOTED READING WAS **NEVER** THE INSTRUMENT'S OUTPUT ON **ANY**
TREE IN **THE WHOLE HISTORY**, **⇒ ⇒ ⇒ AND THAT IS **EXACTLY** THE CLASS
`AGENTS.md` NAMES: **A GOVERNING DOCUMENT THAT CARRIES A FALSE CLAIM PROPAGATES
INTO EVERY BRIEF THAT CITES IT.****

**⇒ ⇒ ⇒ AND THE **TEN** DIFFERENCES ARE **TWO** WALLS, NOT ONE:**

| the entries | the wall |
|---|---|
| **1, 5, 7, 11, 13, 15** | **W-A — THE AFFINE EXPRESSION.** Upstream's input range for those six is `<ADD:none:MUL,RANGE>`, built by `_apply_reshape` (`indexing.py:155-167`). |
| **16, 17, 18, 19** | **W-D — THE `R2` AXIS.** Upstream's `R2` is **A `RANGE`**; the port's is **A `CONST 0`** (`<CONST:cother:>`). **⇒ AND THIS IS **NOT** THE `_apply_reshape` WALL** — **⇒ AND IT IS **THE PORT's `new_range` MAKING **A `CONST 0`** WHERE UPSTREAM MAKES **A `RANGE`**, **⇒ AND THE PORT's OWN `rr_new.one` DECIDES "ONE" BY THE **EXTENT** (`ix_nr_is_one(e)`) **⇒ AND UPSTREAM DECIDES BY `resolve(s != 1)`** (`indexing.py:21`). |

**⇒ ⇒ ⇒ AND THE PORT'S OWN MAP HAS **THREE ENTRIES CPYTHON DOES NOT HAVE**
(`missing : [0, 6, 12]` — THE THREE CONSTs), **⇒ AND UPSTREAM GIVES **A CONST**
**NO RANGE-MAP ENTRY AT ALL** (`indexing.py:306`'s `continue`), **⇒ ⇒ ⇒ AND THE
DENOMINATOR IS **THE UNION**, **⇒ AND THAT IS WHY IT IS **14** AND NOT **11**.**


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

**⇒ MEASURED, THE PORT's RANGE MAP HAS **14** ENTRIES AND UPSTREAM's HAS **11**, AND **THE
THREE EXTRA ARE **EXACTLY** THE `CONST` NODES AT TOPOSORT POSITIONS **0**, **6** AND **12**:
| | the port | upstream |
|---|---|---|
| the keys | `0, 1, 5, 6, 7, 11, 12, 13, 15, 16, 17, 18, 19, 20` | `1, 5, 7, 11, 13, 15, 16, 17, 18, 19, 20` |
| the extras | **`0`, `6`, `12`** — ALL `CONST` | — |

**⇒ ⇒ AND **THE RULE THAT DECIDES IT IS **UPSTREAM's `continue`**, AND IT IS MEASURED BY
READING UPSTREAM's OWN LOOP (`indexing.py:199-306`) AGAINST **UPSTREAM's OWN CAPTURED
CONTEXT** (THE ORACLE'S):**
```python
consumer_rngs = [broadcast_rngs(c, x, rctx.range_map[c][0]) for c in consumer_map[x] if c in rctx.range_map]
...
elif len(consumer_rngs) == 0:
  continue                      # <<< THIS SKIPS `rctx.range_map[x] = (rngs, out_rngs)` AT :306
```
**⇒ ⇒ ⇒ AND **THE CAPTURE SHOWS IT DIRECTLY, ON UPSTREAM's OWN GRAPH:**
```
#   #0   in_rm=False consumers=[]
#   #2   in_rm=False consumers=[(4, 'STACK'), (10, 'STACK')]
#   #6   in_rm=False consumers=[]
```
**⇒ ⇒ ⇒ ⇒ SO A **CONST** HAS **NO CONSUMER THAT IS IN THE RANGE MAP** — **⇒ AND A `STACK` IS
**NOT** A RANGE MAP KEY (THE KEYS ARE `[1, 5, 7, 11, 13, 15, 16, 17, 18, 19, 20]` — **NO
`STACK`**) — **⇒ ⇒ ⇒ ⇒ SO UPSTREAM'S `consumer_rngs` IS EMPTY FOR EVERY CONST AND EVERY CONST
GETS **NO** ENTRY.**

**⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND **THE PORT'S OWN `broadcast_rngs` ALREADY HAS THE `j >= nleft`
FILTER** (`indexing.bend`'s `ix_br_one`, WHICH IS **CORRECT**), **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ SO THE
REMAINDER IS **THE **COUNT** THE PORT MAKES: **THE PORT COUNTS THE **CONSUMERS** AND
UPSTREAM COUNTS THE **RANGE TUPLES THAT SURVIVE `broadcast_rngs`'s FILTER** (`indexing.py:223`
BUILDS A LIST OF **TUPLE**S, ONE PER CONSUMER, AND **A CONSUMER WHOSE FILTERED LIST IS EMPTY
CONTRIBUTES AN **EMPTY TUPLE** — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND `len()` OF THAT LIST IS STILL
THE NUMBER OF **CONSUMERS**!) — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ SO THE DIFFERENCE IS **NOT** THE
COUNT **BUT** THAT UPSTREAM'S LIST IS BUILT WITH A **GENERATOR EXPRESSION** WHOSE ELEMENT IS
`broadcast_rngs(...)` — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND UPSTREAM'S `elif len(consumer_rngs) == 0`
IS ABOUT **THE LIST BEING EMPTY**, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND UPSTREAM'S LIST IS **NOT** EMPTY
FOR A CONST (IT HAS ONE EMPTY TUPLE), **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ SO **UPSTREAM'S CONST
**DOES** REACH `range_map[x] = (rngs, out_rngs)`** — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ AND **THE
ORACLE'S 11 ENTRIES SAY OTHERWISE**, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ SO THE DIFFERENCE IS **WHERE
THE EMPTY TUPLE'S RANGES GO**, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ AND THAT IS `rngs = out_rngs` FOLLOWED
BY `rngs = apply_movement_op(...)` AND **THE `ending_ranges` ARITHMETIC** — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
**⇒ **⇒ AND THE PORT'S ANSWER FOR THOSE IS **THE **TABLE's** RANGE LIST, WHICH IS **NOT** EMPTY,
**⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ AND THAT IS **THE PORT's ANSWER**, WHICH IS THE **NEXT BEST
THING** FOR A NODE WITH NO RANGES — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ AND IT IS **NOT** THE SAME AS
UPSTREAM's EMPTY TUPLE, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ AND THE PORT's OWN HEADER SAYS SO FOR
THE **OTHER** SIX (THE `_apply_reshape` WALL) — **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒ **⇒ **⇒ SO THIS IS
**A SECOND PLACE WHERE THE PORT's ANSWER IS **THE NEXT BEST THING**, **⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **⇒
**⇒ AND IT IS **NAMED** HERE RATHER THAN HIDDEN.**

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
