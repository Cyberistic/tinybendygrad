<!-- FROM: tinybendygrad/schedule/__init__.bend:2096 -->
# BLOCK:
# THE two walls that remain, each with `file:line`, and each NOT a `graph_rewrite`:
#
# 10. `canonicalize_call_body` -- __init__.py:235-236. NO ctx. IT IS A ONE-LINE
#     BODY whose one line is the rewriter:
#         c.replace(src=(graph_rewrite(c.body, pm_canonicalize_alloc,
#                                     init_ctx=CallifyCtx, bottom_up=True),)+c.src[1:])
#     The `c.replace(src=(X,)+c.src[1:])` half is `cks_rep` above and is PORTED;
#     the `graph_rewrite` half is the bottom_up engine over `PMEntrys`, which is
#     `uop/ops.bend`'s `pm_rewrite_m` and is not exported. There is no ctx work
#     left to do here -- `CallifyCtx` exists above -- so the wall is the ENGINE.
#     TODO(p3) __init__.py:236  symbol=canonicalize_call_body  -- `graph_rewrite(..., bottom_up=True)` -- no
#     bottom_up entry point; `ops.bend` has the top-down scan only.
#
# 11. `replace_input_buffer` -- __init__.py:244-246. NEEDS ctx, and it is the
#     ONLY ctx body left, so it is the last C2 item:
#         ctx.replacements.append(b)
#         return b.param_like(len(ctx.replacements)-1)
#     The append is one `List.append` and the `len` is one `List.length`; the
#     mint is the wall. `UOp.param_like` is `TODO(p3) ops.py:1228  symbol=UOp.param_like` in
#     `uop/ops.bend:4371` -- named, unported, and named as a TODO, so this is a
#     recorded deferral and not a gap I found.
#     TODO(p3) ops.py:1228  symbol=UOp.param_like  -- no port. Blocks this body.
#
# 12. `contiguous_mops_to_view` -- __init__.py:195-211. It is the one of the
#     twelve that `06-UNBLOCKED.md` found passes NO ctx on any call, and that is
#     right about the CALL SITES but not about the SIGNATURE: :203 recurses with
#     `ctx` and :209 writes `ctx.views.add(view)`. So it needs ctx, weakly --
#     `if ctx is not None` at :209 makes the write optional.
#     It is the LARGEST of the twelve (17 lines) and every one of its five
#     helpers is missing or walled:
#     TODO(p3) __init__.py:197  symbol=contiguous_mops_to_view  -- `all_int(c.shape)` -- `c.shape` needs `fold.bend`'s
#       `UOp.shape` and a whole-arena `Table`; `all_int` itself is
#       `helpers.bend`'s `all_int_nest` over a `Nest`.
#     TODO(p3) ops.py:762  `src.base` is ported; the `while buf.op is BITCAST`
#       peel is `UOp.base` with BITCAST added and is NOT a reader here.
#     TODO(p3) __init__.py:202  symbol=contiguous_mops_to_view  -- `graph_rewrite(src, multi_pm)` --
#       `schedule/multi.py`'s table.
#     TODO(p3) ops.py    `src.contiguous_view()` -- ABSENT from the tree. This is
#       the binding one: `:206` returns None when it is None, so without it the
#       rule has no fallthrough case and answering anything else would be a
#       fabrication.
#     wall(p3) __init__.py:208  `buf[a:b]` (shrink) and `.bitcast` -- blocked: needs `UOp.shrink` (tinygrad/uop/ops.py:192, `apply_movement_op`), the shrink builder `rangeify.bend` records as a wall; `.bitcast` is not missing -- it is `mixin/dtype.bend`'s `bitcast_at` (:372), which mints `OpsBITCAST`.
#     TODO(p3) __init__.py:210  symbol=contiguous_mops_to_view  -- `.reshape` -- `mixin/movement.bend`'s.
#     TODO(p3) __init__.py:204  symbol=contiguous_mops_to_view  -- `.unshard` -- ABSENT from the tree.
#
# 13. `create_linear_with_vars` -- __init__.py:268-296. NO ctx, and it is the
#     TOP: five `graph_rewrite` passes at :271, :274, :277 plus the two at :236
#     and :262 inside the bodies above, `capturing[0].add_linear` at :292,
#     `memory_plan_rewrite` at :296, `used_vars` at :280 (which needs
#     `UOp.variables`, the same reader arm 3 of `apply_binds` needs) and the
#     `RuntimeError` bind-mismatch check at :287. Porting it before any of the
#     five matchers it calls would be a name with no body.
#     WALL(p3) __init__.py:271  `pm_schedule` -> `lower_sink_to_linear` (ported
#       above) but the PASS is a rewriter -- BLOCKED: needs the `pm_schedule` PatternMatcher + its `graph_rewrite` pass; the rule body `lower_sink_to_linear` IS ported (:1362) and `pm_schedule` has no def in the tree.
#     WALL(p3) __init__.py:274  `pm_resolve_linear_call` -> `resolve_linear_call`
#       (in `ops.bend`) + `pm_flatten_linear` from `engine/realize.py` -- BLOCKED: needs `resolve_linear_call`, which has NO DEF anywhere in the tree; the :1549 note that tag 42 holds it is FALSE (tag 42 is `_pm_resolve_params`, ops.bend:4290 symbol=pm_r_rp_m.slot), and `pm_flatten_linear` is absent too.
#     WALL(p3) __init__.py:277  `pm_copy_from_store` -> the two bodies above plus
#       `assert_all_same_devices`, and the PASS is a rewriter -- BLOCKED: needs the `pm_copy_from_store` PatternMatcher + `graph_rewrite` pass. The THREE rule bodies are ALL ported (`cks_*` :1407, `simplify_copy_kernel` :1466, `assert_all_same_devices` :1527); only the PASS is absent.
#     TODO(p3) __init__.py:280  symbol=create_linear_with_vars  -- `used_vars` -- `UOp.variables`.
#     TODO(p3) schedule/memory.py:19  symbol=memory_plan_rewrite  -- `memory_plan_rewrite` -- `schedule/memory.py`.
#
