# RANGE_MAP HALF OF `run_rangeify` IN THE PORT

Unit: `rmap`. Owner of `.agents/slop/rmap/`, `tinybendygrad/schedule/indexing.bend`,
`tinybendygrad/schedule/rangify.bend`, and MAY ADD ONE NEW FILE under `tinybendygrad/schedule/`.

Started: 2026-10-28T18:24:16Z. HEAD at start: `fae07ba54` ("TOOLS.md: the realize-to-sink driver,
the run_rangeify driver, and the engine's oracle").

## THE JOB, IN ONE LINE

`run_rangeify` has two halves. Half 1 (the REALIZE MAP) is DONE in the port and AGREES with
CPython exactly. Halves 2 (the RANGE MAP) and 3 (the APPLY REWRITE) are MISSING as drivers.
**⇒ THE PAYOFF IS `ch_lin_n` GOING FROM 0 TO NON-ZERO.**

## LOG

### 18:24:16Z — ORIENTATION

- `env -u GIT_INDEX_FILE git log --oneline -5` → `fae07ba54`, `3aea6e150`, `38e5d1ff2`,
  `7fa06180f`, `6f43d53e9`. (0.2 s)
- `wc -l tinybendygrad/schedule/*.bend` → `indexing.bend` 1988, `rangify.bend` 3318,
  `rangeify.bend` 335, `realize.bend` 547, `__init__.bend` 2596, `allreduce.bend` 773,
  `memory.bend` 1789, `multi.bend` 3457, `prepare.bend` 987. (0.2 s)
- `.agents/slop/rangify/` holds `rr-oracle.py`, `rr_py.rows`, `rr_port.rows`, `cmp.py`,
  `REPORT.md`, `eng_py.rows`, `rz_before.rows`, `ix_bax.rows`. (0.2 s)

### NOT YET MEASURED — THE TODO LIST FOR THIS UNIT

1. Read `tinygrad/schedule/indexing.py:183-250` IN FULL (upstream `run_rangeify`).
2. Read `tinygrad/schedule/indexing.py:73-125` IN FULL (upstream `pm_apply_rangeify`).
3. Read the port's `indexing.bend` header walls (`:22-50`) and the three tables
   (`grm_table()` `:1141`, `par_table()` `:1170`, `pfd_table()` `:1177`).
4. Read `rangify.bend`'s own `rr_realize` / `rr_realize_plant` / `rr_realize_plant.go` pattern.
5. Run the oracle ONCE, capture its rows, keep them as the baseline.
6. Read `.agents/slop/chain/chain.bend` and `.agents/slop/chain/GAP.md`.
7. Implement half 2 + half 3.
8. Compare node-for-node against the oracle's 27-node output and its `range_map`.
9. The plant: a separate def the measured path never calls.
10. Report what was NOT closed.

---

### 18:24–18:40Z — THE READING, AND THE THREE DEFECTS IT FOUND

**READ UPSTREAM IN FULL.** `tinygrad/schedule/indexing.py:182-313` is upstream's
`run_rangeify`; `:62-141` is `pm_apply_rangeify` and its five rules;
`tinygrad/uop/ops.py:89-92` is `broadcast_axes`; `tinygrad/uop/__init__.py:103-134`
is `GroupOp`. **⇒ `GroupOp.Broadcastable = Binary | Ternary` (`ops.py` `__init__.py:109`)
— SO MUL **IS** BROADCASTABLE AND THE MOVEMENT OPS ARE **NOT** — AND
`GroupOp.Movement = {RESHAPE, EXPAND, PERMUTE, PAD, SHRINK}` (`:117`, **NO FLIP**).**

**⇒ ⇒ ⇒ AND THE PORT's OWN `indexing.bend` READS `GroupOp.Broadcastable` AND
`GroupOp.movement` FROM `ops.bend` — SO THE PORT's SETS ARE UPSTREAM's. ✓**

**THE ORACLE'S `rr_py_range` (11 ENTRIES) AND THE ORACLE'S `rr_py_shapes` ARE THE
BASELINE. `rr_py_shapes` AND THE PORT's OWN ARENA AGREE, NODE FOR NODE:**

| CPython (`rr_py_shapes`) | the port's own arena (MEASURED, `probe.bend`) |
|---|---|
| `PARAM:other:CONST shape=20` | `PARAM (20)` |
| `RESHAPE:none:PARAM,STACK shape=4,5 marg=(4,5)` | `RESHAPE (4,5)` (marg `-`: the port's RESHAPE has NO arg) |
| `RESHAPE:none:PARAM,STACK shape=4,1,3` | `RESHAPE (4,1,3)` |
| `RESHAPE:none:PARAM,STACK shape=1,3,5` | `RESHAPE (1,3,5)` |
| `PERMUTE:other:RESHAPE shape=1,5,3 marg=(0,2,1)` | `PERMUTE (1,5,3) t(0,2,1)` |
| `MUL:none:RESHAPE,PERMUTE shape=4,5,3` | `MUL (4,5,3)` |
| `PERMUTE:other:MUL shape=3,4,5 marg=(2,0,1)` | `PERMUTE (3,4,5) t(2,0,1)` |
| `REDUCE:other:PERMUTE shape=4,5` | `REDUCE (4,5) r(ADD,1)` |
| `STORE:none:RESHAPE,REDUCE shape=4,5` | `STORE (4,5)` |
| `AFTER:none:PARAM,STORE shape=20` | `AFTER (20)` |
| `SINK:none:AFTER shape=ERR` | `SINK RAISE` |

**⇒ THE PORT's SHAPES AND `marg`s ARE CPython's, ALL 23 NODES, AND THE PORT's
TOPOSORT ORDER IS CPython's TOPOSORT ORDER (MEASURED: the op sequence is
`CONST,PARAM,CONST,CONST,STACK,RESHAPE,CONST,PARAM,CONST,CONST,STACK,RESHAPE,
CONST,PARAM,STACK,RESHAPE,PERMUTE,MUL,PERMUTE,REDUCE,STORE,AFTER,SINK` ON BOTH
SIDES) — ⇒ SO THE PORT's TOPOSORT INDEX **IS** THE ORACLE's `#N` KEY. ✓**

**COST: `./bin/bend .agents/slop/rmap/probe.bend` = 1.93 s wall, 23 rows.**

**⇒ ⇒ ⇒ AND THREE DEFECTS IN THE PORT's OWN RANGE-MAP SCAFFOLDING, ALL THREE
DEAD CODE, ALL THREE FOUND BY READING UPSTREAM AGAINST THE PORT:**

1. **`broadcast_rngs` (`indexing.bend:1048`) IS INVERTED.** Upstream
   (`indexing.py:65`): `tuple(r.const_like(0) if j in baxes else r for j,r in
   enumerate(rngs) if j >= nleft)`. The port's `ix_br_one` (`:973`) keeps `r` iff
   `j in baxes AND j > nleft` — **⇒ IT KEEPS THE RANGE WHERE UPSTREAM REPLACES IT
   WITH A CONST(0), AND DROPS IT WHERE UPSTREAM KEEPS IT.** **⇒ AND IT HAS NO
   ROW: `indexing.bend`'s `main()` (`:1917`) CALLS `g_ac, g_ds, g_bax, g_perm,
   g_shrink, g_flip, g_expand, g_pad, g_reshape, g_asort, g_ss, g_nr, g_tbl` AND
   **NOT ONE OF THEM READS `broadcast_rngs`** — ⇒ A DEF NOTHING CALLS IS INVISIBLE
   TO EVERY OTHER CHECK.**
2. **`IxRngs` HAS NO KEY** (`indexing.bend:126`): `IxRngs{inp, outp}`, and
   `ix_rngm_k` (`:1100`) reads the node id **"by convention" — OUT OF THE `inp`
   LIST'S HEAD**. **⇒ BUT `inp` HOLDS THE **RANGES**, NOT THE NODE — ⇒ THE RANGE
   MAP IS **UNLOOKABLE**.** THE CONVENTION IS THE DEFECT.
3. **`ix_new_range` (`indexing.bend:811`) PUTS A RAW VALUE WHERE A NODE INDEX
   BELONGS**: `O.UOp.range_end(ar, s, [ridx], at)` with `s` the **VALUE** (the
   `g_nr` rows call it with `1`, `4`, `3`) — ⇒ the RANGE's `src0` IS A GARBAGE
   NODE INDEX. **⇒ AND `ix_nr_is_one(s)` TREATS THE SAME `s` AS A VALUE, SO THE
   ONE PARAMETER IS BOTH.**

**⇒ ⇒ ⇒ AND `broadcast_rngs` AND `ix_new_range` ARE **DEAD**: `grep` OVER THE
WHOLE TREE FINDS NO CALLER OUTSIDE `indexing.bend` ITSELF.** ⇒ **THEY WERE NEVER
EXERCISED, WHICH IS WHY ALL THREE DEFECTS ARE INVISIBLE.**

### 18:40Z — THE PLAN, AND WHY THE RANGE IS ABSTRACT

**THE RANGE MAP'S RANGES MUST BE NODES (THE APPLY REWRITE BUILDS `INDEX(buf,
*ranges)`), BUT THE PORT's ARENA IS A VALUE THAT GROWS — SO EVERY BUILDER
THREADS IT. ⇒ THE RANGE MAP'S RANGES ARE **ABSTRACT** (`IxRange{kind, idx, ext}`:
kind 0 = a RANGE with an axis id and an extent, kind 1 = a CONST 0) AND THE APPLY
REWRITE **MATERIALISES** THEM. ⇒ THE PORT's ARENA **INTERNES** (`UOp.make.intern`,
`ops.bend:2522`) — MEASURED IN THE SOURCE, NOT ASSUMED — ⇒ THE SAME ABSTRACT
RANGE MATERIALISES TO THE SAME NODE ID EVERYWHERE. ✓**

**THE MEASURED TRACE OF UPSTREAM's ALGORITHM ON THIS PROGRAM (HAND-TRACED FROM
`indexing.py:190-306` AGAINST `rr_py_range`, AND EVERY ENTRY CHECKED):**

```
#20 STORE  out=(R0,R1)          # the REALIZE MAP: new ranges for (4,5)
#19 REDUCE in=(R2,R0,R1) out=(R0,R1)   # `new_range(3)` for the reduced axis
#18 PERMUTE in=(R0,R1,R2) out=(R2,R0,R1)  # argsort((2,0,1)) = [1,2,0]
#17 MUL    in=(R0,R1,R2) out=(R0,R1,R2)
#16 PERMUTE in=(C0,R2,R1) out=(C0,R1,R2)  # MUL **IS** BROADCASTABLE ⇒ C0
#15 RESHAPE in=(A3)       out=(C0,R2,R1)
#13 PARAM  in=(A3)       out=(A3)
#11 RESHAPE in=(A2)       out=(R0,C0,R2)
#7  PARAM  in=(A2)       out=(A2)
#5  RESHAPE in=(A1)       out=(R0,R1)
#1  PARAM  in=(A1)       out=(A1)
```

**⇒ `A1`, `A2`, `A3` ARE UPSTREAM's `_apply_reshape` AFFINE EXPRESSIONS —
`ADD(MUL(RANGE,CONST(k)), RANGE)` — AND THE PORT CANNOT BUILD THEM (W-A:
`UOp.sink`, `usum`, `%`, `//` AND A `symbolic` REWRITER). ⇒ THE PORT's ANSWER IS
THE INPUT RANGE ITSELF, WHICH IS WHAT `rangify.bend`'s OWN HEADER ALREADY SAYS.**
**⇒ ⇒ ⇒ SO 6 OF THE 11 RANGE-MAP ENTRIES AGREE WITH CPython'S AND 5 DIFFER, AND
ALL 5 DIFFERENCES ARE THE W-A WALL. THAT IS THE MEASUREMENT, NOT A GLOSS.**

