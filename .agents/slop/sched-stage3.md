# STAGE 3 -- the 19 entry points, and the rewrite engine

## THE HEADLINE, WHICH CONTRADICTS THE BRIEF'S PREMISE

The brief says "`not one of upstream's 19 entry points is present`" and lists
`create_schedule` among the absent. **By NAME that is literally true and it is
the port's fault, not a wall.** By MEANING it is false for four of them:

`tinybendygrad/schedule/__init__.bend` ports `__init__.py:14-80` **in full** --
the three pure helpers and `create_schedule` -- under `sc_`-prefixed names.
The port's own header says so at `:3-5`:

    # THE PORTED PART IS __init__.py:14-80, and it is the WHOLE of the schedule
    # linearizer: the three pure helpers and `create_schedule`, the engine's first
    # real consumer.

So the hole is not "the port cannot turn a spec into a scheduled program". **It
can, and Stage 2 measures it agreeing with CPython on 60 of 60 fields over six
real graphs.** The hole is `__init__.py:82-301`, which the same header defers at
`:7-13`.

## THE TABLE. 4 PRESENT, 15 ABSENT, DENOMINATOR 19

`present = the port's own def for that upstream body`. `rows = gate rows in
`schedule/__init__.bend` that exercise it`.

| # | upstream (`__init__.py`) | port def (`schedule/__init__.bend`) | present | rows | name kept? |
|---|---|---|---|---|---|
| 1 | `_unwrap_src` :14-16 | `sc_unwrap` :300 (+ `unwrap.go` :292) | YES | 6 | no (`sc_` prefix) |
| 2 | `_states` :19-23 | `sc_states` :376 | YES | 3 | no (`sc_`) |
| 3 | `_split_after` :25-30 | `sc_split` :421, `Split` :385 | YES | 8 | no (`sc_`) |
| 4 | **`create_schedule` :32-80** | **`schedule` :1051**, `linear` :1048 | **YES** | **22 + 60 new** | **no (`schedule`)** |
| 5 | `create_new_buffer` :90-94 | -- | ABSENT | 0 | -- |
| 6 | `resolve_linear_call` :103-115 | -- | ABSENT | 0 | -- |
| 7 | `lower_sink_to_linear` :124-151 | -- | ABSENT | 0 | -- |
| 8 | `assert_all_same_devices` :157-159 | -- | ABSENT | 0 | -- |
| 9 | `copy_kernel_to_store` :161-163 | -- | ABSENT | 0 | -- |
| 10 | `simplify_copy_kernel` :165-172 | -- | ABSENT | 0 | -- |
| 11 | `CallifyCtx` :192-197 | -- | ABSENT | 0 | -- |
| 12 | `contiguous_mops_to_view` :199-215 | -- | ABSENT | 0 | -- |
| 13 | `is_store_after` :217-218 | -- | ABSENT | 0 | -- |
| 14 | `collect_stores` :220-221 | -- | ABSENT | 0 | -- |
| 15 | `canonicalize_alloc` :235-237 | -- | ABSENT | 0 | -- |
| 16 | `canonicalize_call_body` :239-240 | -- | ABSENT | 0 | -- |
| 17 | `replace_input_buffer` :248-250 | -- | ABSENT | 0 | -- |
| 18 | `transform_to_call` :261-270 | -- | ABSENT | 0 | -- |
| 19 | `create_linear_with_vars` :273-301 | -- | ABSENT | 0 | -- |

**Denominator: 19 entry points. 4 present (21%), 15 absent (79%).** The split is
exact and total: the 4 present are the whole of `:14-80`, the 15 absent are the
whole of `:82-301`. Nothing is half-done.

**`create_schedule`'s 22 own rows plus 60 new ones.** The 22 are `fx1_*`, `fx2_*`,
`fx3_*`, `fx5_*` and the `unwrap_*`/`split_*`/`states_*`/`bufuop_*`/`bv_*`/`bs_*`
families on hand-built fixtures. The 60 new are Stage 2's, over six CPython-built
graphs, and they are in `.agents/slop/sched-fixture.bend` rather than in the
schedule file -- see "WHERE THE NEW ROWS LIVE" below.

## THE NAMING DEVIATION, WHICH IS THE OWNER'S RULE AND NOT A WALL

Agent-core: "DEF NAMES MATCH UPSTREAM EXACTLY, WHEREVER POSSIBLE ... port
`Schedule.kernelize` as `kernelize`, not `sch_kernelize`. Do not invent a prefix
to avoid a collision." All four ported defs deviate: `sc_unwrap`,
`sc_states`, `sc_split`, and `create_schedule` -> **`schedule`**. `schedule` is
also the name of the owner-level module family, so the collision is real and the
rule says the fix is to SPLIT THE FILES, not to rename. **Upstream
`create_schedule` is available as a Bend identifier** -- it is not `match` or
`where`, the only two reserved words (agent-core, measured over 2,419 of 2,421
names) -- so `schedule` bought nothing.

I did NOT rename. Three reasons, stated so the coordinator can overrule:
1. Renaming `schedule` -> `create_schedule` touches 22 gate rows and the header's
   own prose, in a file five other units cite by line.
2. `.agents/slop/` are **DO NOT TOUCH** for this session, and I cannot measure the
   rename's effect on the differ without editing `graphcmp.bend`.
3. It is a pure rename with no semantic content; it is worth one commit on its own
   rather than being buried in a port.

**The recommendation is a one-line rename plus a `sc_` sweep, as its own commit.**

## WHAT ALREADY EXISTS -- THE REWRITER, AND IT IS MOSTLY THERE

The brief says to find the rewrite engine before writing anything. It exists, in
`tinybendygrad/codegen/__init__.bend` (330 lines):

| upstream | port | state |
|---|---|---|
| `graph_rewrite` (ops.py:1790 dispatcher) | `codegen/__init__.bend:180` | **WALL -- returns `(ar, (None{}, empty map))`. It does nothing.** |
| `walk_rewrite` (the MLIR single pass) | `:146`, with `wr.go` | **WORKS.** Gate green: `new_sink=8 repl=PARAM(0)->PARAM(99), PARAM(1)->PARAM(100), ALLOC->BUFFER, SINK->SINK` |
| `unified_rewrite` (the fixpoint) | `:176` | **WALL -- calls `walk_rewrite` once.** The comment at `:150-160` is honest about this. |
| `RewriteContext` | `:141-145` | `ctx: List<&2, U32>`, untyped, documented as the wall-passing shape |
| `remove_all_tags` (ops.py:1905) | -- | absent here, used at `:267` |
| `memory_plan_rewrite` (memory.py) | `schedule/memory.bend:912` | present |

So: **do not reimplement a rewriter.** `walk_rewrite` is a working single-pass
engine over `O.PMEntrys` with a rebuild, and `__init__.py:82-301` is a
`graph_rewrite` over that same table. The missing pieces are the two
**dispatcher** walls, not the engine.

### THIS CORRECTS THE PORT'S OWN DEFERAL REASON

`schedule/__init__.bend:7-13` gives the reason `:82-301` is deferred:

> every rule in it is a `graph_rewrite` over the arena with a PYTHON `ctx` DICT,
> and `graph_rewrite`'s engine pass needs the rule table to be LINEAR while these
> rules need the ctx to be a MUTABLE accumulator threaded through the pass.
> `pm_callify_ctx_collect` is the clearest case: its ctx is a `CallifyCtx` holding
> a `list`, a `dict`, a `set` and another `list`.

That reason is **half the wall**. The other half is larger and not mentioned:
`graph_rewrite` at `codegen/__init__.bend:180-181` is a stub that returns
`None{}`, so every one of the 15 absent entry points is blocked on the dispatcher
regardless of what its `ctx` looks like. And the "ctx must be a mutable
accumulator" constraint is already half-satisfied -- `walk_rewrite` takes
`ctx: List<&2, U32>` and threads it through every rule body.

**The concrete next step, smallest first:** `graph_rewrite`'s five-line stub at
`codegen/__init__.bend:180` is the load-bearing wall for 15 of 19 entry points. It
is not in `DO NOT TOUCH`. It is 1 of 3 files' worth of work and it unblocks more
than anything else in `schedule/__init__.py`.

## THE DEPENDENCIES OF THE 15, MEASURED

Every one of these is called by an absent entry point, and every one is absent:

| called by | needs | port |
|---|---|---|
| `:135` `lower_sink_to_linear` | `get_kernel_graph` | **ABSENT** |
| `:135` | `prepare_rangeify` | **ABSENT** |
| `:135`, `:267` | `multi_pm` | **ABSENT** |
| `:169` `simplify_copy_kernel` | `pm_mops` | **ABSENT** |
| `:120` `resolve_linear_call` | `pm_flatten_linear` | **ABSENT** |
| `:154` `lower_sink_to_linear` | `pm_schedule` | **ABSENT** |
| `:124-151` | `schedule_cache` (a module global) | **ABSENT** |
| `:301` `create_linear_with_vars` | `memory_plan_rewrite` | present (`schedule/memory.bend:912`) |
| `prepare.bend` (54 KB) | -- | exists but exports none of these names |

## WHERE THE NEW ROWS LIVE, AND WHY NOT IN THE SCHEDULE FILE

Stage 2's 60 rows are in `.agents/slop/sched-fixture.bend`, GENERATED by
`.agents/slop/sched-fixture.py`, and are compared by `.agents/slop/sched-cmp.py`.
They are not in `tinybendygrad/schedule/__init__.bend` for two reasons:

1. **`sched-fixture.bend` imports `./../../tinybendygrad/schedule/__init__.bend`
  **, so making it import the fixture would be a cycle. Bend has no
   `include`.
2. The 60 rows are a **function of CPython's output**, so the file that holds
   them must be REGENERATED whenever the spec set changes. That is what the
   generator is for. Hand-copying them into the schedule file would make them
   typed expectations, which is the failure mode agent-core's table is built on.

The schedule file's OWN 71 rows are unaffected and still green:
`./bin/bend tinybendygrad/schedule/__init__.bend` prints 71 `name=value` lines in
0.98 s.

## THE DIFFER'S 85-NODE TAX: BEFORE 85, AFTER 85. IT DID NOT DROP.

Measured, per graph, by counting `O.UOp.new`/`O.UOp.const`/`O.UOp.range_end` in
`graphcmp.bend`:

| graph | hand-written nodes | what it should be |
|---|---|---|
| `g_lin` (`:859-921`) | **46** | `full_rewrite_to_sink(schedule_linear(matmul))` |
| `g_loop` (`:927-964`) | **25** | `hcq_fence(...)` |
| `g_gate` (`:972-1000`) | **14** | `pm_linearize_cleanups` over a gated STORE |
| **total** | **85** | |

**After this unit: 85. Unchanged.** Not one node was removed, and here is the
exact reason, with the wall at `file:line`.

`g_lin`'s replacement expression needs two functions and BOTH are absent:

1. `schedule_linear` needs the **sched_sink**, which is
   `get_kernel_graph(prepare_rangeify(function))` (`__init__.py:135`) where
   `function` is `transform_to_call`'s CALL body (`:261-270`). All three are
   absent, and `transform_to_call` is absent because `pm_callify_ctx_collect`'s
   `ctx` is a `CallifyCtx` **and** `graph_rewrite` is a stub.
2. `full_rewrite_to_sink` (`codegen/__init__.py:273`) is **absent as a callable**.
   `codegen/kernel.bend:71` records it as `PORTED AS THE PASS LIST`, and that is
   literally true -- it is a comment. There is no `def` for it, no `to_sink`, no
   `kernelize`. And the specific things `g_lin`'s hand-written nodes encode are
   `sym` + `pm_simplify_ranges` output: `graphcmp.bend:856-857` says the row reads
   `CONST weakint l0:4` followed by `CAST i32 Di32`, and `:867-874` records that a
   hand-guessed `ARange{[2, 1], WEAK}` was WRONG against the measured
   `ARange{[2], WEAK}` and moved eight nodes. Those rewrites are the port's
   `full_rewrite_to_sink`, and there is no callable to call.

So `full_rewrite_to_sink(schedule_linear(matmul))` cannot be written today, and
the reason is not "we hand-wrote it". It is **two named dispatchers, both
stubs** -- `graph_rewrite` at `codegen/__init__.bend:180` and
`full_rewrite_to_sink`, which does not exist.

### WHAT DID LAND INSTEAD, AND IT IS THE PART THAT TRANSFERS

`sched-emit.py` + `sched-fixture.py` + `sched-cmp.py` remove the need to
hand-write a graph **for any sched_sink CPython can build**. Concretely:

- Before: a new scheduled graph cost ~46 hand-written `O.UOp.new` lines, each one
  a chance at the `ARange{[2,1]}` bug, and it needed its own oracle.
- After: a new spec is a function in `sched-oracle.py`'s `SPECS` list. The
  emitter builds the arena, the gate rows are generated, and the comparator
  recomputes CPython independently. **Zero hand-written nodes per new spec.**

That does not remove the 85. It removes the *tax on every future one*, and it is
the input Stage 2 needed to be possible at all -- which is the reason the brief's
premise ("`lin` is upstream's `schedule_linear(matmul)`, hand-transcribed") was
worth acting on even though the conclusion was different.

### THE 43 UNREACHED OPS: THIS UNIT'S CONTRIBUTION

Stage 2 builds six real kernel graphs the differ does not have. What they reach
that the differ's `lin` does not, measured from the emitted censuses
(`sched-stage1.md`):

- **`AFTER`** -- present in all six sched_sinks, and the differ's `g_lin` has
  **no AFTER at all** (its nodes are `PARAM CONST CAST RANGE MUL ADD INDEX LOAD
  STORE END SINK`, verified by reading `graphcmp.bend:859-921`). AFTER is the node
  `create_schedule` exists to consume.
- **`RANGE` with a split axis, `CAST`, `CMPNE`/`CMPLT`, `AND`, `MAX`, `CONST` of
  `Bool`** -- `conv` reaches all of them; `conv` was the differ's one unreached
  spec family with a real reduction.
- **`CONST weakint` + `RANGE(WEAK)` + `PARAM(addrspace=ALU, vmin_vmax, val)`** --
  the bound-Variable shape, reached by `matmul_sym`. The differ's graphs have no
  ALU PARAM.

That is progress on the differ's coverage, stated as a count of OPS not graphs,
and it is **not** the same as the differ's rows: these are 60 rows in a new file
that nothing in the differ reads.