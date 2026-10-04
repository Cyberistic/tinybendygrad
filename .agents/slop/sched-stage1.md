# STAGE 1 -- CPython's `create_schedule`, recorded field by field

Oracle: `.agents/slop/sched-oracle.py` (run twice, `--twice`).
Recorded output: `.agents/slop/sched-oracle.txt`.

    env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python \
      .agents/slop/sched-oracle.py --twice > .agents/slop/sched-oracle.txt

**DENOMINATOR: 6 specs attempted, 6 produced a schedule, 12 `create_schedule`
calls, 12/12 deterministic across two runs. Plus 1 control.**

## THE ORACLE DOES NOT TRANSCRIBE THE PIPELINE -- IT SPIES

`create_schedule(sched_sink)`'s argument is the SINK-OF-AFTERS that
`get_kernel_graph(prepare_rangeify(function))` builds
(`schedule/__init__.py:135`). Rather than transcribe that three-stage pipeline,
`sched-oracle.py` replaces the module-global `create_schedule` that
`lower_sink_to_linear` looks up, then drives `Tensor.schedule_linear()`
(`tensor.py:212`) -- the entry `create_linear_with_vars` sits behind. So every
`sink` recorded here is the REAL sched_sink tinygrad itself hands to
`create_schedule`, and every `lin` is the REAL `UOp(Ops.LINEAR, ...)`.

## TWO SPEC COUNTS, BOTH MEASURED

1. **`create_schedule` is only reachable on a schedule-cache MISS.** The first
   `--twice` run reported `DETERMINISTIC=False` on 4 of 7 blocks, each diff
   being the entire run-1 block *deleted* in run 2. Cause:
   `schedule_cache` (`__init__.py:122`) is a module global keyed by
   `function.key`, read at `:130` **before** `create_schedule` is reached at
   `:135`. The second identical spec in one process is a cache hit, so
   `create_schedule` is never called. Fixed by `_reset()` clearing
   `SCHED.schedule_cache` before each spec. **A harness that runs a spec twice in
   one process measures the cache on the second call, not the function.**
2. **Every spec makes TWO `create_schedule` calls**, and call `#0` is always the
   same thing: `sink_n=1`, `SINK`, `nsrc=0`, `sink_ops=[('SINK', 1)]`,
   `lin_nsrc=0`. That is `transform_to_call`'s `UOp.sink(*ctx.stores)` with an
   empty `ctx.stores` (`:267`) reaching `lower_sink_to_linear` before the real
   stores are collected, or the equivalent probe `lower_sink_to_linear` makes on
   a body with no kernel. It is a REAL call and it is reported as one; the
   per-call counts are `specs x 2`, and the `#1` rows are the real schedules.

## `create_schedule` VALIDATES NOTHING -- THREE SILENT EMPTYS, ALL MEASURED

This is the single most load-bearing finding of the stage, and it is exactly the
shape the brief warns about ("a port that silently returns a wrong schedule is
worse than one that refuses"):

| input | what CPython answers | raises? |
|---|---|---|
| `SINK` with zero AFTERs (every spec, call `#0`) | `UOp(Ops.LINEAR, src=())` | no |
| an `AFTER` rather than a SINK-OF-AFTERS (the control) | `UOp(Ops.LINEAR, src=())` | no |
| a real sched_sink | the schedule | no |

The control is the one `graphcmp-p14-sched.py:40` actually calls:
`create_schedule((Tensor.empty(4,5).realize().assign(t)).uop)`. It answers
`lin_nsrc=0`. Reason: the assign's `.uop` is the AFTER itself, not a
SINK-OF-AFTERS, so `_split_after` drops its `STORE` (`__init__.py:26` -- STORE
is neither CALL/END nor AFTER), `kernels` is empty, the Kahn queue at `:68` has
no seed, and the loop at `:70` never runs. **`lin_op == LINEAR` is NOT evidence
that a schedule was built**, and no row in the port's gate can tell the three
cases apart today -- see Stage 2.

## THE RECORDED ASTS

`sink_n` = `len(sink.toposort(gate_kernel_sink))`, `sink_ops` = the census of
that gated walk. `lin_*` describe the LINEAR. `lin_ksrc` is the per-kernel src
op SEQUENCE in LINEAR order (the row that decides the linearization -- the port
calls it `fx*_ops`). `lin_kmark` is the port's `gate.mark`: the op of the STORE's
value, not a digit, because these are real graphs and the values are real.

| spec | sink_n | sink_op | sink_nsrc | sink_ops | lin_op | lin_nsrc | lin_ksrc | lin_knsrc | lin_ktop | lin_kmark | lin_kinfo |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `matmul` | 6 | SINK | 1 | AFTER 1, CALL 1, PARAM 3, SINK 1 | LINEAR | 1 | SINK,P,P,P | 4 | SINK | `<REDUCE>` | `test` |
| `matmul_sym` | 6 | SINK | 1 | AFTER 1, CALL 1, PARAM 3, SINK 1 | LINEAR | 1 | SINK,P,P,P | 4 | SINK | `<MAX>` | `test` |
| `conv` | 6 | SINK | 1 | AFTER 1, CALL 1, PARAM 3, SINK 1 | LINEAR | 1 | SINK,P,P,P | 4 | SINK | `<CAST>` | `test` |
| `elementwise` | 7 | SINK | 1 | AFTER 1, CALL 1, PARAM 4, SINK 1 | LINEAR | 1 | SINK,P,P,P,P | 5 | SINK | `<MAX>` | `test` |
| `multi` | **9** | SINK | **2** | AFTER 2, CALL 2, PARAM 4, SINK 1 | LINEAR | **2** | SINK,P,P,P / SINK,P,P | **4, 3** | SINK,SINK | `<REDUCE>`,`<MAX>` | `test`,`test` |
| `chain` | 5 | SINK | 1 | AFTER 1, CALL 1, PARAM 2, SINK 1 | LINEAR | 1 | SINK,P,P | 3 | SINK | `<MUL>` | `test` |
| CONTROL `WRONGINPUT_after` | 23 | **AFTER** | 2 | AFTER 1, ALLOC 2, BUFFER 1, CONST 4, MUL 1, PERMUTE 2, REDUCE 1, RESHAPE 5, STACK 5, STORE 1 | LINEAR | **0** | -- | -- | -- | -- | -- |

`lin_nnodes` (the LINEAR's own toposort size): matmul 28, matmul_sym 31, conv 64,
elementwise 27, multi 44, chain 19, control 1.

## WHAT THESE SPECS DO NOT COVER, STATED AS A DENOMINATOR

- **Kernel COUNT is 1 on five of six specs.** Only `multi` schedules two. So the
  ordering work -- the Kahn loop at `:66-80`, the WAR pass at `:59-65`, the
  zero-degree seed order at `:68` -- is exercised by exactly **1 of 6** specs.
  The port's `fx1`/`fx2`/`fx5` fixtures (2 and 3 kernels) cover it; the real
  pipeline barely does at these sizes.
- **No MSELECT and no MSTACK** appears in any `sink_ops` census, so `_states`'s
  MSTACK expansion (`__init__.py:21`) and `buf_uop`'s MSELECT arm (`ops.py:925`)
  are unreachable from these six. Measured, not assumed: grep the censuses.
- **`lin_kmark` is never a bare CONST.** All six are `<REDUCE>`/`<MAX>`/
  `<CAST>`/`<MUL>`, i.e. the STORE's value is a rewritten expression, never a
  literal. The port's `gate.digit` (`schedule/__init__.bend:1251`) handles only
  1/2/3 and returns 0 otherwise, so **`gate.marks` is 0 on every real graph** and
  its `fx*_marks` rows only ever see hand-built fixtures. That is a real gap in
  the existing gate and it is reported here rather than papered over.
- **No BUFFER in a sched_sink.** Every real `sink_ops` has PARAMs, never
  BUFFER/ALLOC, because `get_kernel_graph` has already bufferized. `buf_uop`'s
  BUFFER arm -- the arm the port's `bufuop_A1` row tests -- is not reached from
  a real spec either.

## THE PORT ALREADY HAS `create_schedule`

The brief's premise is that "not one of upstream's 19 entry points is present"
and lists `create_schedule` among the absent. **That is wrong for
`create_schedule`.** `tinybendygrad/schedule/__init__.bend:1051` has it, under
the name `schedule`, and the header at `:3-5` says so. It is not a stub: 71 gate
rows print on a 0.98 s run and every one was checked. The real gap is
`__init__.py:82-301`, which the same header defers at `:7-13`. See Stage 3.