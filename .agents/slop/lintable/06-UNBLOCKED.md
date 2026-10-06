# WHAT ACTUALLY UNBLOCKED — measured, with the denominator

## THE DENOMINATOR — 15 DEFS, AND THE AUDIT'S FIGURE IS RIGHT

`tinygrad/schedule/__init__.py:82-301`, the region the header defers. Counted from
the file, not taken on trust:

```
$ awk 'NR>=82 && NR<=301 && /^def |^  def /' tinygrad/schedule/__init__.py | wc -l
15
```

**15 defs.** My first pass said 14 because it matched only `^def ` and missed
`apply_binds` (`:110`), which is **INDENTED** — a nested def inside
`resolve_linear_call`. A count taken with a pattern that ignores indentation is short
by exactly the nested ones, so the audit's 15 is the right denominator and I report
against it.

| # | name | line | | # | name | line |
|---|---|---|---|---|---|---|
| 1 | `create_new_buffer` | 90 | | 9 | `is_store_after` | 217 |
| 2 | `resolve_linear_call` | 103 | | 10 | `collect_stores` | 220 |
| 3 | `apply_binds` (nested) | 110 | | 11 | `canonicalize_alloc` | 235 |
| 4 | `lower_sink_to_linear` | 124 | | 12 | `canonicalize_call_body` | 239 |
| 5 | `assert_all_same_devices` | 157 | | 13 | `replace_input_buffer` | 248 |
| 6 | `copy_kernel_to_store` | 161 | | 14 | `transform_to_call` | 261 |
| 7 | `simplify_copy_kernel` | 165 | | 15 | `create_linear_with_vars` | 273 |
| 8 | `contiguous_mops_to_view` | 199 | | | | |

The region also holds **7 `PatternMatcher` literals** — `pm_post_sched_cache` `:96`,
`pm_resolve_linear_call` `:117`, `pm_schedule` `:153`, `pm_copy_from_store` `:174`,
`pm_callify_ctx_collect` `:224`, `pm_canonicalize_alloc` `:242`, `pm_replace_buf`
`:252`. They are not defs and so are not in the 15, but `pm_post_sched_cache` is where
two of the four ported rules are **inlined**, so it is counted separately.

## THE THREE DEFS THAT NAMED A RULE I PORTED — 3 of 15

```
$ awk 'NR>=82 && NR<=301' tinygrad/schedule/__init__.py | grep -nE 'remove_all_tags|arg\.slot|ctx\[0\]\.get'
 10:  if (ret:=ctx[0].get(b, None)) is None:
 17:  (UPat(Ops.PARAM, name="x"), lambda ctx,x: ctx[1][x.arg.slot] if x.arg.slot >= 0 else None),
 32:    subs = {v:binds[v.arg.slot] for s in si.src for v in s.variables() if v.arg.slot in binds}
155:  if b.arg.slot >= 0 and b not in ctx.allocs: ...
186:  ret = graph_rewrite(..., pm_canonicalize_alloc+pm_replace_buf+remove_all_tags, ctx=ctx, ...)
```

Four hits, in **three defs** plus the table literal. That is the whole set.

| name | line | which rule of the four | what the table now supplies | what still blocks it |
|---|---|---|---|---|
| `transform_to_call` | `:261`, uses the rule at **`:267`** | **`remove_all_tags`** (ops.py:1904), by name | the rule body, as tag 41, reachable through `pm_rewrite_f` — a family that did not exist | its ctx is a `CallifyCtx` and it composes three tables, so **C2 is untouched** |
| `resolve_linear_call` | `:103` | **`_pm_resolve_params`** (ops.py:1897), inlined at `:98` as `ctx[1][x.arg.slot] if x.arg.slot >= 0 else None` | the full-slot body, as tag 42 — the pre-existing tag 3 answered slots 0 and 1 **only** | its ctx is the 2-tuple `({}, srcs)`, so **C2 is untouched** |
| `create_new_buffer` | `:90`, body at `:91` | **`_substitute`** (ops.py:1896), as `ctx[0].get(b, None)` | BOTH halves the rule needs and neither existed: a **node-keyed map ctx** (family `_sub`) and a **minting answer** (family `_f`) | `b.device`, `b.max_numel`, `UOp.new_buffer` are `fold.bend`'s and `buffer.bend`'s |

Plus, **outside the 15**, the table literal `pm_post_sched_cache` (`:96`) — whose two
rules ARE the two above, and which a caller would now build from tags 42 and 41 rather
than re-inlining both bodies.

## THE TWELVE THAT WERE NEVER BLOCKED BY THE TABLE — 12 of 15

`apply_binds`, `lower_sink_to_linear`, `assert_all_same_devices`, `copy_kernel_to_store`,
`simplify_copy_kernel`, `contiguous_mops_to_view`, `is_store_after`, `collect_stores`,
`canonicalize_alloc`, `canonicalize_call_body`, `replace_input_buffer`,
`create_linear_with_vars`. They are waiting on:

- **their own rule bodies** — `pm_schedule`, `pm_callify_ctx_collect`,
  `pm_replace_buf`, `pm_copy_from_store` and `pm_canonicalize_alloc` are rules about
  SCHEDULING and CALLIFY, and nothing in `uop/ops.py` holds them;
- **`CallifyCtx`** — a dataclass carrying a list, a dict, a set and another list.
  That is clause **C2**, and this unit did not touch it;
- **their signatures** — `is_store_after`, `assert_all_same_devices` and
  `canonicalize_call_body` are plain functions with no table at all.

## TREE-WIDE REACHABILITY, WHICH IS THE OTHER HALF OF THE ANSWER

The value of the table is not confined to `schedule/`. Measured over all of `tinygrad/`:

| rule | ops.py | live consumers outside `uop/ops.py` |
|---|---|---|
| `remove_all_tags` | 1904 | `schedule/__init__.py:267` |
| `_substitute` | 1896 | `codegen/simplify.py:32` — `graph_rewrite(u, _substitute+symbolic+…, ctx={r0:…, r1:…})`, a `dict[UOp,UOp]` ctx, which is tag 43's exact shape |
| `pm_drop_after` | 1907 | `tensor.py:204` — `graph_rewrite(u.src[0], pm_drop_after, bottom_up=True)`, a **no-ctx** call, which is tag 40's exact shape |
| `_pm_resolve_params` | 1897 | **zero** call sites; reached only through the hand-inlined copy at `schedule/__init__.py:98` |

So **3 of the 4 rules have a live caller in the tree, and 2 of those 3 callers are
exact type matches for the families this unit added.** `tensor.py:204` in particular
needs nothing but a rule body that returns `src[0]` — which is tag 40, three lines.

## THE HONEST BOTTOM LINE

- **The table went from three reachable bodies to five** (`pm_dispatch_m`: 0, 1, 2, 3, 4,
  **40**, **42**), **plus two families that did not exist** — a String-keyed map ctx and
  the first `Maybe<&2, Found>` answer in the file.
- **3 of the 15 deferred defs** had the table as a blocker and no longer do, plus
  `pm_post_sched_cache` outside the 15.
- **The header's C3 claim is now WEAKER than it was, not stronger**: the table is not
  the wall. Of the 15, **12 were never behind it.**
- **This partly inverts the priority argument.** The audit said "LINEAR TABLE →
  DISPATCHER → ctx". The table and the dispatcher are now both in `ops.bend`, and
  **the table was never the binding constraint on 12 of the 15** — so the remaining
  order is **rule bodies → ctx**, and the `CallifyCtx` dataclass is the next thing to
  measure, not the table.