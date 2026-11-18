<!-- FROM: tinybendygrad/function.bend:1071 -->
# BLOCK:
# SECTION I -- THE OMISSIONS. One line each: what, where, and the phase that owns
# it. Nothing here is silently dropped, and every one names a wall rather than an
# effort.
#
# TODO(p3) ops.py:1228  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
#   is answered by `fn_add` and the NODE is not built. Owner: `uop/ops.bend`, and
#   the reason is structural: `param_like` reads `self.addrspace` and
#   `self.axis`, which are fold properties, so it belongs beside the fold and not
#   in a caller.
# TODO(p3) ops.py:514   `UOp.substitute` -- `uret.substitute(subs)` and
#   `uret.substitute({b: ...})`. It IS `graph_rewrite`, so it needs the matcher
#   machinery `uop/spec.bend` owns and a closure the port does not have.
# TODO(p3) ops.py:1272  `UOp.call_with_outputs` -- `uret.call_with_outputs(...)`.
#   It is the PROGRAM/CallInfo construction and it needs `grad_fxn`, which is a
#   Python callable; a function value in a record forces `Type`, not `Data`.
# DONE(p3) ops.py:245   `UOp.replace` -- PORTED at `ops.bend:2984` (gate `gates/replace-gate.py` rc=0 8/8 rows) and
#   `replace(arg=ParamArg{...})` is a single-arg call to a def that takes the new
#   arg as `Maybe<&2, Arg>`, and the identity case (no kwargs) is the row that
#   `gates/replace-gate.py`'s `identity_returns_self` pins (8 rows, 3 lanes, gate
#   rc=0, 2026-10-06). The seam ABOVE is `substitute` (still a TODO), and
#   `fn_renum` is the NUMBERING, which is the part with a behaviour.
# TODO(p3) function.py:53  `get_state_dict((args, kwargs))` -- `nn/state.bend` has
#   `get_state_dict(Obj)` and not the `(args, kwargs)` TUPLE wrapper, which is a
#   two-field `Data` record plus a `type(t) is Tensor` / `is UOp` filter.
# TODO(p3) function.py:61  `with Context(ALLOW_DEVICE_USAGE=getenv(..., 0))` --
#   `helpers.bend` has no `Context` (a thread-local contextvar stack) and
#   `getenv` is an effect. The `finally` that restores the depth is the same
#   shape as `fn_exit`, and `fn_enter`/`fn_exit` ARE ported and gated, so the
#   depth half of line 61 is not lost.
# TODO(p3) function.py:64  `self.fxn(*args, kwargs)` -- no function values in
#   Bend. The seam `mixin/tensor.bend` names for `_apply_uop` too.
# TODO(p3) function.py:51  `time.perf_counter()` -- an effect. `fn_trace` takes
#   the elapsed time as a PARAMETER, which is the injected-time discipline.
# TODO(p3) function.py:48  `__get__` -- `functools.partial(self.__call__, obj)`.
#   A descriptor is a Python protocol over `type.__getattribute__`; the closest
#   Bend shape is an explicit `fn_bind(obj)` at each call site and there is no
#   decorator machinery to hang it on.
# TODO(p3) function.py:82  `getattr(self.fxn, '__qualname__', None)` -- the name
#   of a Python callable. `fn_name` takes the name as a parameter, which is what
#   the gate does and what the seam forces.
# TODO(p3) ops.py:911  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
#   cluster (`mselect`, per-shard buffers). Neither op is reachable from a
#   `@function` body before the multi-device allocator exists. The walk and the
#   AFTER arm ARE ported above, as `fn_buf`.
#
# ONE UPSTREAM DIVERGENCE, found while building the oracle and NOT a port
# choice: `function.py:60` is `alloc_start = next(UOp.unique_num)` and
# `function.py:17` is `x.arg.slot < ctx[2]`, so `ctx[2]` must be an `int` or the
# comparison raises. `next()` on an `itertools.count` DOES answer an `int` here
# (`unique_num = itertools.count(0)`), so the code is correct -- but writing
# `cx[2] = UOp.unique_num` in an oracle, which is the obvious thing to write,
# raises `TypeError: '<' not supported between instances of 'int' and
# 'itertools.count'` on the first ALLOC with `bind_on_realize=True`. The port
# spells it as `Arena.next(ar) -> U32`, which cannot be got wrong, and the
# fixture builders below say so.
# SECTION J0 -- THE SEAM `examples/beautiful_mnist.ts` SHOULD CALL.
#
# That file's `@function_` decorator currently increments a global counter and
# delegates, and its own comment says "that file also tracks depth, and the count is
# what the curve block reports". The port of the depth half is here and it is FOUR
# defs and a record, so the seam is exact and small:
#
#   import ./function.bend as FN
#
#   @FN.TinyFunction                     # a `Fn` built by the factory, ported
#   def __call__(self, images, labels) -> number:
#     ...
#
# with `Fn.of` standing for the class `_function`, `fn_enter.of` for
# `_function.depth += 1`, `fn_exit` for the `finally: _function.depth -= 1`, and
# `Fn.depth` for the counter. The DECORATOR ITSELF is the seam: `fn_enter`/`fn_exit`
# are pure functions of a `Data` value, so a TypeScript class holds the `Fn` record
# as its field and calls the two, and nothing about the Python class survives except
# the field names. `function_`/`function.curried` are the two decorator spellings
# and they build the same value, which is what `fac_same` gates.
#
# what this seam does not replace, and it is the important half:
# `examples/beautiful_mnist.ts`'s `@TinyJit` is NOT this file. `TinyJit` is
# `tinygrad/engine/jit.py`, its spec match is
# `self.captured.expected_input_info != expected_input_info`, and its counter is
# `self.cnt` -- none of which is in `function.py` and none of which this port
# touches. `@function_` is the seam; `@TinyJit` belongs to whatever unit owns
# `engine/jit.py`.
# SECTION J -- THE GATE.
#
# EVERY ROW IS DERIVED FROM CPython. The oracle is
# `.venv/bin/python` on `tinygrad/function.py` with hand-built fixtures, and it
# is a SIDE-BY-SIDE script rather than a unit test, because the claims are
# `Bool`s and strings and a unit test framework would only hide the fact that
# both sides were run by hand.
#
# THE ROW CLASSES, and what each one is FOR:
#   iis_*   `is_implicit_storage`, one row per cell of the truth table. Twelve
#           cells because the predicate is a THREE-TERM disjunction over FOUR
#           fields and every fixture below is a cell, not a family.
#   add_*   `add_to_ctx`, including the `ctx[1]`-is-the-INVALID-set fact, which
#           is the line in this file a reader most likely gets wrong.
#   inv_*   `invalid_outputs`, one row per conjunct's negative.
#   renum_* `renumber_invalid_outputs`' numbering, with a FIXTURE WITH A GAP so
#           the counter and the toposort position cannot agree.
#   pctx_*  `pm_ctx`, both rules, with a SWAPPED-OPERAND fixture so the gate
#           carries a src-op SEQUENCE and not just a count and a root op.
#   bs_*    `backward_slice` vs `toposort`, which differ by exactly one node.
#   imp_*   the `allow_implicit=False` refusal TEXT, byte for byte.
#   ret_*   the un-tensor-return refusal TEXT, byte for byte.
#   dep_*   `_function.depth` entering and being RESTORED.
#   fac_*   both decorator spellings.
#   callu_* `dedup` keeping the FIRST occurrence.
#   trace_* the DEBUG print's indent and name.
# END BLOCK

# SECTION I -- THE OMISSIONS. One line each: what, where, and the phase that owns
# it. Nothing here is silently dropped, and every one names a wall rather than an
# effort.
#
# TODO(p3) ops.py:1228  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
#   is answered by `fn_add` and the NODE is not built. Owner: `uop/ops.bend`, and
#   the reason is structural: `param_like` reads `self.addrspace` and
#   `self.axis`, which are fold properties, so it belongs beside the fold and not
#   in a caller.
# TODO(p3) ops.py:514   `UOp.substitute` -- `uret.substitute(subs)` and
#   `uret.substitute({b: ...})`. It IS `graph_rewrite`, so it needs the matcher
#   machinery `uop/spec.bend` owns and a closure the port does not have.
# TODO(p3) ops.py:1272  `UOp.call_with_outputs` -- `uret.call_with_outputs(...)`.
#   It is the PROGRAM/CallInfo construction and it needs `grad_fxn`, which is a
#   Python callable; a function value in a record forces `Type`, not `Data`.
# DONE(p3) ops.py:245   `UOp.replace` -- PORTED at `ops.bend:2984` (gate `gates/replace-gate.py` rc=0 8/8 rows) and
#   `replace(arg=ParamArg{...})` is a single-arg call to a def that takes the new
#   arg as `Maybe<&2, Arg>`, and the identity case (no kwargs) is the row that
#   `gates/replace-gate.py`'s `identity_returns_self` pins (8 rows, 3 lanes, gate
#   rc=0, 2026-10-06). The seam ABOVE is `substitute` (still a TODO), and
#   `fn_renum` is the NUMBERING, which is the part with a behaviour.
# TODO(p3) function.py:53  `get_state_dict((args, kwargs))` -- `nn/state.bend` has
#   `get_state_dict(Obj)` and not the `(args, kwargs)` TUPLE wrapper, which is a
#   two-field `Data` record plus a `type(t) is Tensor` / `is UOp` filter.
# TODO(p3) function.py:61  `with Context(ALLOW_DEVICE_USAGE=getenv(..., 0))` --
#   `helpers.bend` has no `Context` (a thread-local contextvar stack) and
#   `getenv` is an effect. The `finally` that restores the depth is the same
#   shape as `fn_exit`, and `fn_enter`/`fn_exit` ARE ported and gated, so the
#   depth half of line 61 is not lost.
# TODO(p3) function.py:64  `self.fxn(*args, kwargs)` -- no function values in
#   Bend. The seam `mixin/tensor.bend` names for `_apply_uop` too.
# TODO(p3) function.py:51  `time.perf_counter()` -- an effect. `fn_trace` takes
#   the elapsed time as a PARAMETER, which is the injected-time discipline.
# TODO(p3) function.py:48  `__get__` -- `functools.partial(self.__call__, obj)`.
#   A descriptor is a Python protocol over `type.__getattribute__`; the closest
#   Bend shape is an explicit `fn_bind(obj)` at each call site and there is no
#   decorator machinery to hang it on.
# TODO(p3) function.py:82  `getattr(self.fxn, '__qualname__', None)` -- the name
#   of a Python callable. `fn_name` takes the name as a parameter, which is what
#   the gate does and what the seam forces.
# TODO(p3) ops.py:911  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
#   cluster (`mselect`, per-shard buffers). Neither op is reachable from a
#   `@function` body before the multi-device allocator exists. The walk and the
#   AFTER arm ARE ported above, as `fn_buf`.
#
# ONE UPSTREAM DIVERGENCE, found while building the oracle and NOT a port
# choice: `function.py:60` is `alloc_start = next(UOp.unique_num)` and
# `function.py:17` is `x.arg.slot < ctx[2]`, so `ctx[2]` must be an `int` or the
# comparison raises. `next()` on an `itertools.count` DOES answer an `int` here
# (`unique_num = itertools.count(0)`), so the code is correct -- but writing
# `cx[2] = UOp.unique_num` in an oracle, which is the obvious thing to write,
# raises `TypeError: '<' not supported between instances of 'int' and
# 'itertools.count'` on the first ALLOC with `bind_on_realize=True`. The port
# spells it as `Arena.next(ar) -> U32`, which cannot be got wrong, and the
# fixture builders below say so.
# SECTION J0 -- THE SEAM `examples/beautiful_mnist.ts` SHOULD CALL.
#
# That file's `@function_` decorator currently increments a global counter and
# delegates, and its own comment says "that file also tracks depth, and the count is
# what the curve block reports". The port of the depth half is here and it is FOUR
# defs and a record, so the seam is exact and small:
#
#   import ./function.bend as FN
#
#   @FN.TinyFunction                     # a `Fn` built by the factory, ported
#   def __call__(self, images, labels) -> number:
#     ...
#
# with `Fn.of` standing for the class `_function`, `fn_enter.of` for
# `_function.depth += 1`, `fn_exit` for the `finally: _function.depth -= 1`, and
# `Fn.depth` for the counter. The DECORATOR ITSELF is the seam: `fn_enter`/`fn_exit`
# are pure functions of a `Data` value, so a TypeScript class holds the `Fn` record
# as its field and calls the two, and nothing about the Python class survives except
# the field names. `function_`/`function.curried` are the two decorator spellings
# and they build the same value, which is what `fac_same` gates.
#
# what this seam does not replace, and it is the important half:
# `examples/beautiful_mnist.ts`'s `@TinyJit` is NOT this file. `TinyJit` is
# `tinygrad/engine/jit.py`, its spec match is
# `self.captured.expected_input_info != expected_input_info`, and its counter is
# `self.cnt` -- none of which is in `function.py` and none of which this port
# touches. `@function_` is the seam; `@TinyJit` belongs to whatever unit owns
# `engine/jit.py`.
# SECTION J -- THE GATE.
#
# EVERY ROW IS DERIVED FROM CPython. The oracle is
# `.venv/bin/python` on `tinygrad/function.py` with hand-built fixtures, and it
# is a SIDE-BY-SIDE script rather than a unit test, because the claims are
# `Bool`s and strings and a unit test framework would only hide the fact that
# both sides were run by hand.
#
# THE ROW CLASSES, and what each one is FOR:
#   iis_*   `is_implicit_storage`, one row per cell of the truth table. Twelve
#           cells because the predicate is a THREE-TERM disjunction over FOUR
#           fields and every fixture below is a cell, not a family.
#   add_*   `add_to_ctx`, including the `ctx[1]`-is-the-INVALID-set fact, which
#           is the line in this file a reader most likely gets wrong.
#   inv_*   `invalid_outputs`, one row per conjunct's negative.
#   renum_* `renumber_invalid_outputs`' numbering, with a FIXTURE WITH A GAP so
#           the counter and the toposort position cannot agree.
#   pctx_*  `pm_ctx`, both rules, with a SWAPPED-OPERAND fixture so the gate
#           carries a src-op SEQUENCE and not just a count and a root op.
#   bs_*    `backward_slice` vs `toposort`, which differ by exactly one node.
#   imp_*   the `allow_implicit=False` refusal TEXT, byte for byte.
#   ret_*   the un-tensor-return refusal TEXT, byte for byte.
#   dep_*   `_function.depth` entering and being RESTORED.
#   fac_*   both decorator spellings.
#   callu_* `dedup` keeping the FIRST occurrence.
#   trace_* the DEBUG print's indent and name.
