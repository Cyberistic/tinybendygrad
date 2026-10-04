# `graph_rewrite` — STAGE 4: what is unblocked, what is still blocked, and by what.

The question is which of the **fifteen** absent entry points of
`tinygrad/schedule/__init__.py:82-301` can now be written. "Can be written" here
means something checkable: **the entry point's OWN blocker is gone**, so what
remains is a wall this unit did not touch and a future unit can name.

Every row below is derived from `grw-census.py` and `grw-ctxclaim.py`, which
read the source. The blocker column is not copied from the port's headers; it is
what each entry point actually needs, checked against what exists.

## THE TEST USED

An entry point is UNBLOCKED-BY-THE-DISPATCHER when its only `graph_rewrite`
call now reaches a driver that runs. It is STILL BLOCKED when, after the
dispatcher, some second wall stands in front of it. The second walls that
exist are named here with the file that owns them.

---

## UNBLOCKED — 4 of 15

| # | entry point | line | what the dispatcher removed | what remains |
|---|---|---|---|---|
| 1 | `assert_all_same_devices` | 157 | it is a `pm_copy_from_store` rule, so it needs the driver | nothing structural. It is `dedup([x.device for x in ast.toposort() if ...])` + a raise. `ast.toposort()` exists (`uop/ops.bend`), `x.device` is `fold.bend`'s, `dedup` is set algebra `fold.bend` already has. **The only open item is the RAISE, which Bend has no exception for at this layer** — see below. |
| 2 | `copy_kernel_to_store` | 161 | same | `dst.store(src)` — `OpsSTORE`'s builder. Short of `_device` comparison. |
| 3 | `is_store_after` | 217 | nothing (it calls no rewrite) — it was never dispatcher-blocked | `u.unsharded_base` exists (`uop/ops.bend`) and `u.op is Ops.AFTER` is a dispatch. **The cheapest of the fifteen and it is not on the dispatcher's account at all** — it is here because the header counts it. |
| 4 | `contiguous_mops_to_view` | 199 | it calls `graph_rewrite(src, multi_pm)` at :206 with **no ctx**, so the ctx wall never applied | `multi_pm` (6 rules) and `src.contiguous_view()`. Both named walls, neither the ctx one. |

`CallifyCtx` (193) is a `@dataclass` with four mutable fields; it is a type, not
an entry point, and it is blocked on the `ctx` wall.

## UNBLOCKED, WITH A NAMED SECOND WALL — 4 of 15

| # | entry point | line | second wall | owner |
|---|---|---|---|---|
| 5 | `lower_sink_to_linear` | 124 | `create_schedule` + `get_kernel_graph` + `prepare_rangeify`. **All three are already ported** (`schedule/__init__.bend:1051`, `rangeify.bend`, `prepare.bend`) — so this one is the closest of the fifteen to writable. | the SCACHE: `schedule_cache` + `diskcache_get`/`diskcache_put`. **A cache, and failure mode 1 says a spec passed twice in one process measures the cache.** Not a wall; a gate obligation. |
| 6 | `simplify_copy_kernel` | 165 | `sym` + `pm_mops` + `pm_flatten_range` + `pm_simplify_ranges` — four rule tables, three of them ported in shape | the tables' completeness. **`ctx` is an empty dict literal here**, so the header's reason does not apply and never did. |
| 7 | `create_linear_with_vars` | 273 | `pm_schedule` → #5; `pm_resolve_linear_call` → #8; `pm_copy_from_store` → #1/#2/#6; then `memory_plan_rewrite` (`schedule/memory.bend:912`, EXISTS) | the `used_vars` / `var_vals` walk and `capturing`. **All three of its `graph_rewrite` calls pass no ctx**, so C3 never applied to it. |
| 8 | `resolve_linear_call` | 103 | the **mutable ctx**: `pm_post_sched_cache`'s `create_new_buffer` writes `ctx[0][b]`, and the port's workaround is to PRE-MINT the BUFFER and read `ctx[2]` | `apply_binds` / `UOp.substitute`, which is `graph_rewrite` with `_substitute` (`ops.py:532`, not ported — `uop/ops.bend` is another unit's) |

## STILL BLOCKED — 7 of 15, all on the MUTABLE-ACCUMULATOR ctx

`create_new_buffer` (90), `collect_stores` (220), `canonicalize_alloc` (235),
`canonicalize_call_body` (239), `replace_input_buffer` (248),
`transform_to_call` (261), and `contiguous_mops_to_view` (199, on the OTHER of
its two blockers).

Their `ctx` is a `CallifyCtx` holding `list`, `dict`, `set` and another `list`
(schedule/__init__.py:193-197), and a rule WRITES it mid-pass. The port's
`walk_rewrite` hands `ctx` to `pm_rewrite_m` by value (`List<&2, U32>`) and gets
a `Maybe<&2, U32>` back — there is no accumulator, and **adding one means
changing `pm_rewrite_m`'s signature in `uop/ops.bend`**, which this unit does not
own and which four other units' gates depend on.

**This is the header's reason, and for these seven it is CORRECT.** It is
recorded at seven of fifteen, not fifteen, and Stage 1 has the arithmetic.

---

## THE ORDER THIS IMPLIES

| rank | wall | how many of the 15 | owner |
|---|---|---|---|
| 1 | **LINEAR rule table** — the `UPat` compiler | most of them | `uop/upat.bend` + `uop/ops.bend` |
| 2 | ~~the dispatcher~~ — **DONE by this unit** | was all 15 | — |
| 3 | mutable-accumulator `ctx` | 7 of 15 | `uop/ops.bend`'s `pm_rewrite_m` |

The header at `schedule/__init__.bend:7-13` argues for rank 3 and names rank 2.
Rank 1 is bigger and is not in the header at all.

## WHAT ELSE IN THE TREE MOVED

`grw-census.py` counts 22 `TODO(p3)` markers whose own continuation names
`graph_rewrite` or `unified_rewrite` as the wall, across 14 files. Of those, 10
name a reason that is INDEPENDENT of `ctx`:

| file:line | the marker | why the dispatcher does not unblock it |
|---|---|---|
| `codegen/kernel.bend:99` | `ops.py:581 def index` | `UOp.replace`-with-a-NEW-OP and a product, not a rewrite |
| `function.bend:1078` | `ops.py:532 UOp.substitute` | needs the matcher machinery and a closure the port does not have |
| `mixin/rand.bend:795` | `mixin/rand.py:249 randperm` | a bitonic sort with four nested Python `for` loops |
| `schedule/multi.bend:3506` | `ops.py:520 ssimplify` | `mu_sym_dim()` is the marker and it is 0 |
| `uop/symbolic.bend:3054` | `symbolic.py:228 fold_where_closure` | `bool_slice` + `op_in_backward_slice_with_self` + substitute |
| `uop/symbolic.bend:3101` | `mixin/elementwise.py:50 logical_not` | BORROWED from another file |
| `uop/weak.bend:783` | `weak.py:98 cast_consts` | `UOp.cconst`, a rule that MINTS |
| `tensor.bend:996` | `tensor.py:549 __eq__` | elementwise `eq` |
| `tensor.bend:447` | `tensor.py:73 UOp.const` | an F32 literal |
| `uop/movement.bend:235` | `ops.py:581 def index` | the marker is stale |

**So of 22 walls that name the dispatcher, 10 are for OTHER walls and 12 are ctx
walls. The dispatcher's own removal unblocks the ctx walls' FIRST half and none
of the other ten.** That is the honest yield, and it is larger than "nothing"
and smaller than "22".

## TWO THINGS A FUTURE UNIT SHOULD KNOW THAT COST THIS ONE A SESSION

1. **A `Bend` def cannot RAISE, and three of these fifteen need to.** Upstream's
   `assert_all_same_devices` raises `RuntimeError`, `_states`' assert and
   `_split_after`'s `AssertionError` do too, and the cycle `RuntimeError` is the
   fixpoint's own observable. The port's answer here is a `Maybe`/`Bool` in the
   return value — which is what `Rewritten.capped` is — but a rule body has
   nowhere to put one. That is a LANGUAGE question, not a file question, and it
   is the same one `uop/ops.bend`'s own inventory already names.
2. **`grw-gate.sh` exits 2 when it compares zero rows.** If a future unit changes
   the row names, the gate says `NO PORT ROW` and exits non-zero rather than
   quietly agreeing on nothing.