# `run_rangeify` DRIVER IN THE PORT — REPORT

**UNIT:** land `run_rangeify`'s DRIVER in the port (the last link in the port's own `Device` lane).
**OWNED:** `.agents/slop/rangify/`, `tinybendygrad/schedule/{indexing,realize,rangeify}.bend`, + ONE new file under `tinybendygrad/schedule/`.
**NO COMMIT.** `env -u GIT_INDEX_FILE` for every git read. One bend process at a time.

## THE GAP, IN ONE LINE

Upstream's pipeline (`tinygrad/schedule/__init__.py:132`):
`linear = create_schedule(get_kernel_graph(prepare_rangeify(function)))`
and `get_kernel_graph` (`tinygrad/schedule/rangeify.py:341-376`) BEGINS with
`tsink = run_rangeify(tsink, bool(DEBUG_RANGEIFY))` — "convert movement ops to ranges".
The port's own engine marks that stage `Stg{0, Nil{}}` — "run_rangeify — NOT PORTED"
(`tinybendygrad/schedule/rangeify.bend:2810`).

## STATUS LOG

### T+0 — ORIENT (3 s, 5 s, 0 s)
- `pwd` = `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`
- `git log --oneline -5`:
  - `6f43d53e9` the port's own realize-to-sink driver: 23 nodes AGREE with CPython, and the seam is ONE LINE
  - `ac3b0278a` the Device lane's complete map: stages 4-9 are GREEN, and 1-3 are named
  - `8d7bc5700` the engine had NO oracle at all, and the port's own fixtures are not upstream's input shape
  - `8933ecd8b` the gate row that was missing: rng_after, and it goes RED on the old code
  - `60e36e23f` the fold's rng_width refused every AFTER-bound RANGE, so every vmax was zero
- `tinybendygrad/schedule/` = `__init__.bend` (131235 B) `allreduce.bend` `indexing.bend` (89553 B)
  `memory.bend` `multi.bend` `prepare.bend` `rangeify.bend` (182247 B) `realize.bend` (24969 B, mtime Oct 28 16:41)

### T+2m — THE PORT'S OWN STATE, MEASURED (3.4 s, 1.7 s)
`BEND_NO_TELEMETRY=1 ./bin/bend tinybendygrad/schedule/realize.bend` →
- `rz_nodes=23` — the port's own sink is 23 nodes.
- `rz_dump=SINK:none:AFTER;AFTER:none:PARAM,STORE;PARAM:other:CONST;CONST:cother:;STORE:none:RESHAPE,REDUCE;…`
  — **the port's own 23-node sink.**
- `rz_lin_n=0` — **the port's own `schedule()` answers ZERO kernels.** THE BASELINE.
- `rz_params=0:20,1:12,2:15` · `rz_consts=20,4,5,12,1,3,15`
- `rz_eng=eng_rz_s0=0;84;…` … `eng_rz_s6=59;114;SINK:none:AFTER;AFTER:none:OTHER,STORE;…`
  — **the port's own engine, on the port's own sink: stage 3 moves 27 nodes, stage 6 moves 59, and the SHAPE is unchanged**
  (`AFTER(…, STORE)`, not `AFTER(…, END)`). ⇒ the engine alone cannot give the scheduler a kernel.

### T+6m — THE ORACLE, AND WHAT IT ACTUALLY SAYS
`.agents/slop/engine/eng-oracle.py` (read-only, NOT mine) spies on upstream's `get_kernel_graph`:
`eng_py_in_nodes=23`, `eng_py_out_nodes=9`, output census `AFTER CALL CONST PARAM SINK`.

**⇒ BUT `eng_py_out_nodes=9` IS NOT THE 9 NODES A DUMP SHOWS.** MEASURED, upstream's
`UOp.toposort` (`tinygrad/uop/ops.py:289-301`) walks `node.src_without_body`, and for a
CALL that is `src[1:]` — **so the CALL's BODY is not in the toposort.** The 9 are
`SINK, AFTER, PARAM, CONST, CALL, PARAM, PARAM, PARAM`; the dump's 32 entries are the
same graph with the body descended into. The `9` is a toposort count, not a node count.

### T+12m — THE REAL TARGET: CPython's OWN `run_rangeify`, NOT `get_kernel_graph`
**⇒ THE 9-NODE OUTPUT IS THE WRONG TARGET FOR THIS UNIT.** `get_kernel_graph` is SEVEN
stages; `run_rangeify` is stage 1. The target for a `run_rangeify` driver is stage 1's
output, and it is a DIFFERENT graph.

`.agents/slop/rangify/rr-oracle.py` (MINE, new) spies on upstream's own
`tinygrad.schedule.indexing.run_rangeify` and on the `IndexingContext` it mutates:

```
rr_py_in_nodes=23
rr_py_out_nodes=27
rr_py_out=SINK:none:AFTER;AFTER:none:PARAM,END;PARAM:other:CONST;CONST:cother:;
          END:none:STORE,RANGE,RANGE;STORE:none:INDEX,REDUCE;INDEX:none:PARAM,ADD;
          ADD:none:MUL,RANGE;MUL:none:RANGE,CONST;RANGE:other:CONST;CONST:cother:;
          CONST:cother:;RANGE:other:CONST;REDUCE:other:MUL,RANGE;MUL:none:INDEX,INDEX;
          INDEX:none:PARAM,ADD;PARAM:other:CONST;CONST:cother:;ADD:none:MUL,RANGE;
          MUL:none:RANGE,CONST;CONST:cother:;RANGE:other:CONST;INDEX:none:PARAM,ADD;
          PARAM:other:CONST;CONST:cother:;ADD:none:MUL,RANGE;MUL:none:RANGE,CONST
# the output census: ['ADD','AFTER','CONST','END','INDEX','MUL','PARAM','RANGE','REDUCE','SINK','STORE']
rr_py_realize_n=1
rr_py_realize=STORE:none:RESHAPE,REDUCE:none
rr_py_range_n=11
rr_py_range=MUL:none:RESHAPE,PERMUTE:[R0,R1,R2]->[R0,R1,R2];
            PARAM:other:CONST:[<ADD>]->[<ADD>];PARAM:other:CONST:[<ADD>]->[<ADD>];
            PARAM:other:CONST:[<ADD>]->[<ADD>];PERMUTE:other:MUL:[R0,R1,R2]->[R2,R0,R1];
            PERMUTE:other:RESHAPE:[<CONST>,R2,R1]->[<CONST>,R1,R2];
            REDUCE:other:PERMUTE:[R2,R0,R1]->[R0,R1];
            RESHAPE:none:PARAM,STACK:[<ADD>]->[<CONST>,R2,R1];
            RESHAPE:none:PARAM,STACK:[<ADD>]->[R0,<CONST>,R2];
            RESHAPE:none:PARAM,STACK:[<ADD>]->[R0,R1];
            STORE:none:RESHAPE,REDUCE:[R0,R1]->[R0,R1]
rr_py_nonremovable_n=0
```

**⇒ ⇒ SO CPython's `run_rangeify` OUTPUT IS `SINK(AFTER(PARAM, END))` — WITH AN `END`,
NOT A `CALL`.** And the port's `schedule()` counts an `END` as a kernel:
`sc_is_kernel` (`tinybendygrad/schedule/__init__.bend:274`) is
`sc_is(ar, i, O.OpsCALL{}) or sc_is(ar, i, O.OpsEND{})`.

**⇒ ⇒ ⇒ SO `run_rangeify` IS ENOUGH TO MOVE `rz_lin_n` OFF ZERO — the `END` upstream's
stage 6 (`split_kernels`) later turns into a `CALL` is ALREADY a kernel to the port's
own scheduler.** THIS IS THE PAYOFF, AND IT IS MEASURED, NOT ASSUMED.

### T+14m — A CAPTURE BUG IN MY OWN ORACLE, FOUND AND FIXED
The first run of `rr-oracle.py` printed `rr_py_realize_n=0`. MEASURED cause: upstream's
`run_rangeify` is called **TWICE** by `t.schedule_linear()` — once on a sink with no
STORE (so `pm_generate_realize_map` fires nothing) and once on the 23-node sink. The
captures are now CLEARED per `run_rangeify` call. **⇒ AND THE PORT'S OWN DRIVER MUST
NOT MAKE THE SAME MISTAKE: THE REALIZE MAP IS DELETED BY THE APPLY REWRITE**
(`del ctx.realize_map[s]`, `indexing.py:88`), so the map read AFTER the run is EMPTY
and measures nothing. The map is captured **before** the apply rewrite.
