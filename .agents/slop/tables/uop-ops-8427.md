<!-- FROM: tinybendygrad/uop/ops.bend:8427 -->
# BLOCK:
# NOT PORTED -- tinygrad/uop/ops.py, and why. One line each, the same shape
# helpers.bend and dtype.bend use, and each with the phase that owns it.
#
# The Python-object machinery, all of which needs a runtime Bend does not have:
#   `UOpMetaClass.ucache` and its `weakref` eviction -- replaced by the arena
#     itself (`intern`), so this is not a loss but the mechanism is different.
#   `UOp.__del__`, `UOp.__reduce__`, `CallInfo.__reduce__`, `UPat.__reduce__` --
#     pickling and refcount-driven cache eviction. The arena is monotone and has
#     no destruction, so nothing is evicted and nothing needs pickling.
#   `_UOpTuple` -- a tuple subclass whose `__eq__` is identity, "so that tuple <
#     doesn't rescan deep equal prefixes with O(n) value equality at every level
#     of the walk". A `List` of `U32` arena indices has that property for free,
#     which is `UOp.tuplize`'s return type here (P3, with the sort it feeds).
#   `hashlib.sha256` in `UOp.key` -- a digest over the render. `key` is P3 with
#     the cache it keys; the C effect would be `tinygrad/runtime/`'s.
#   `pickle` in `deconstruct_function` and `PatternMatcher.__reduce__` -- Bend
#     has no code objects to pickle, and the rules become top-level defs
#     dispatched by a tag, which is what the master plan already prescribes.
#   `exec` in `_sym_fxn` -- it builds Python source from the graph and runs it
#     with a namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`.
#     Bend has no `eval` and no generated code, so `sym_infer` needs either a C
#     effect that compiles a lambda or a tree-walking interpreter. P3/P6.
#   `sys._getframe` in `get_location` and in `rewrite_group` -- a pattern's
#     source location. That is CPython's frame stack, and every `UPat` carries
#     a `location` that the viz and `print_match_stats` read. Rebuilt in P8 on
#     the `IO.now` clock, the same answer helpers.bend gives for the profiler.
#   `time.perf_counter` in `TrackedPatternMatcher.rewrite` -- the per-rule
#     timing. Same clock story as `cpu_profile` in helpers.bend; P8.
#   `atexit` + `diskcache_put` in `save_to_diskcache` and `print_match_stats` --
#     a pickled `RewriteTrace` on disk for the viz. The sqlite/pickle cache is
#     P6, and the viz is P8.
#   `os.execv` in `launch_viz` -- re-exec into `viz/serve.py`. P8.
#   `collections.Counter` in `gcd` and `divide_exact`, and `itertools` in
#     `split_uop`, `contract`, `broadcast_axes`, `argfix` and `_align_left` --
#     folds over Python iterables. Each becomes a Bend fold; P3, with the
#     symbolic helpers they serve.
#   `functools.reduce(operator.and_, ...)` in `gcd` -- the same.
#   `operator.neg/add/sub/mul/ne/lt/xor/or_/and_/rshift/lshift/max` in
#     `python_alu`, and `math.*` in `safe_exp2`/`safe_pow` -- the `python_alu`
#     table. F32 arithmetic is native in Bend and `F32.is_eq`/`is_lt` exist, so
#     this table is a match ladder; P3, with `exec_alu` (whose `tuple` operand
#     case is a vectorised ALIKE branch).
#   `math.inf` in `identity_element` and `_min_max` -- Bend cannot name an
#     infinity in a U32, so it is `F32.div(1, 0)`; the ONE place dtype.py's
#     `dt.min` for a float needs the seam, and `identity_element` above spells
#     it out.
#   `Buffer`/`MultiBuffer` in `UOp.buffer`, `UOp.realized`, `UOp._buffer_view`,
#     `new_buffer`, `from_buffer`, `_frompy`, `to_elf`, `TinyELF` and
#     `canonicalize_device` -- the device memory layer. P6, and `ParamArg.buffer`
#     is the slot they all read.
#   `Estimates` in `KernelInfo` -- PORTED 2026-10-30 as a FIELD, in
#     `renderer/estimates.bend`. What is NOT PORTED is the VALUE: upstream's
#     only writer is `codegen/__init__.py:446` and `do_estimates` is a WALL in
#     `codegen/kernel.bend`, so every `KernelInfo` the port builds carries
#     `estimates=None`.
#   `CustomFunction` -- PORTED 2026-10-03, at ops.py's own position (between
#     `OPAQUE_CALL_BODIES` and `CallInfo`), together with `Arg`'s `ACustom` arm,
#     `eq_customfunction` and `UOp.custom_function`. The old text here said it was
#     PORTABLE but unreachable and so would "land with" the P6 hcq2 work; it landed
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)`
#     needs the datatype and `spec.bend`'s `sh_22` is stale until it has one. Being
#     P6 only ever described the CALLERS, never the type.
#     what is still open is the other half, and it is not optional: upstream moved
#     `CallInfo.dtype` into `CustomFunction.dtype`, so a CALL's return dtype now
#     lives on its CUSTOM_FUNCTION body (`dtype_from_uop`'s CALL arm is
#     `return src[0].dtype`). `CallInfo` here STILL HAS `dtype`, and it is still
#     read by `eq_callinfo` and by `uop/spec.bend`'s `arg_call`/`sh_23`. So the
#     re-cut is a SEPARATE change with its own blast radius, not a field delete:
#     `sh_23` compares a DECLARED dtype against the node's own, and under HEAD
#     there is no declared dtype to compare -- the CALL's dtype IS its body's. P3,
#     with `dtype_from_uop`.
#     MEASURED 2026-10-06, so the next reader does not have to re-derive it: the
#     eleven-site, seven-file delete is APPLIED AND GREEN in a scratch copy of this
#     tree, it moves `--graph loop`'s `arg` chunk to CPython's bytes, and it closes
#     HALF the row -- `dtype` and `shape` stay `?` because `fold.bend` never settles
#     that node, which is a second defect. See the `CallInfo` block above for the
#     `git log -S` pin, and `spec.bend`'s own `arg_call` comment for its stale half.
#   `UPat.custom_function(fn, kwargs)` -- ops.py:1509 upstream, still NOT PORTED. A
#     `PatternMatcher` rule constructor, so it lands with `uop/upat.py`.
#   `UOp.param_like(slot, name=None)` -- ops.py:1241 upstream. `name` was added so a
#     scalar argument can be bound by NAME while its slot and value stay out of the
#     schedule cache key. P6, with the hcq call sites that use it.
#   `UOp.contiguous_view()`'s new tail -- upstream now returns a BITCAST SLICE
#     (`b.src[0].flatten()[...]`) where the pin returned `(b.rtag(None), offset)`, and
#     it computes the offset with `strides_for_shape` instead of a
#     `pm_contiguous_view_offset` matcher. P3 with `symbolic.bend`; the matcher form is
#     NOT PORTED for the reason the pattern compiler is, below.
#   `grad_fxn` in `CallInfo` and `uopfunc` -- a Python function object; a Bend
#     closure is single-use and is a `Type`, so it cannot be a `Data` field.
#     The reverse-mode plumbing is `tinygrad/nn/gradient.py`, P7.
#   `aux` in `CallInfo` and `trace_num` -- the per-call side channel, written by
#     the hcq paths in `tinygrad/runtime/ops_*.py`, which are out of scope.
#   `uopfunc`'s `inspect.signature(fn).bind(...)` -- Python reflection over a
#     function object, used to turn uop arguments into params. P7 with the mixin.
#   `is_any`, `custom_early_reject`, `allow_any_len`, `permutations` and
#     `functools.repeat` in `UPat.__init__`, and `upat_compile` -- the pattern
#     COMPILER (`tinygrad/uop/upat.py`). `UPat` is PORTED (see ops.py:1447, with
#     a pattern arena of its own); the COMPILER is a separate file whose output is
#     a def per rule, so the machinery here dispatches a tag rather than calling
#     a compiled function pointer. `permutations` at arity >= 3 is the one part
#     of `__init__` not ported, and it is unreachable from ops.py.
#   `upat_interpret`'s `types.FunctionType(*deconstruct_function(fxn))` and
#     `inspect.signature(real_fxn).parameters` -- rebuilding a Python function
#     from its code object. Same answer as above: rules are top-level defs.
#   `REWRITE_STACK_LIMIT` and the `BottomUpGate` exception in
#     `RewriteContext.unified_rewrite` -- the stack limit is a fuel budget here
#     (the same `case 0n:` the walks use) and the gate is a value, because a
#     Bend def cannot raise. `BottomUpGate` therefore becomes a `Maybe` result
#     the driver inspects; P3, with the engine.
#   `ops.py`'s `SPEC > 1` block in `UOpMetaClass.__call__` -- `spec_full.rewrite`,
#     `created._shape` and `test_pyrender`. That is `tinygrad/uop/spec.py`, P3,
#     and `dtype_from_uop`'s `None` is the check in the form this port states.
#   `Ops` reverse lookup (`Ops("ADD")`) and `AxisType` reverse lookup -- not
#     called by ops.py; `AxisType.of` is here anyway because `range_str` needs
#     a name and a test needs a name.
# END BLOCK

# NOT PORTED -- tinygrad/uop/ops.py, and why. One line each, the same shape
# helpers.bend and dtype.bend use, and each with the phase that owns it.
#
# The Python-object machinery, all of which needs a runtime Bend does not have:
#   `UOpMetaClass.ucache` and its `weakref` eviction -- replaced by the arena
#     itself (`intern`), so this is not a loss but the mechanism is different.
#   `UOp.__del__`, `UOp.__reduce__`, `CallInfo.__reduce__`, `UPat.__reduce__` --
#     pickling and refcount-driven cache eviction. The arena is monotone and has
#     no destruction, so nothing is evicted and nothing needs pickling.
#   `_UOpTuple` -- a tuple subclass whose `__eq__` is identity, "so that tuple <
#     doesn't rescan deep equal prefixes with O(n) value equality at every level
#     of the walk". A `List` of `U32` arena indices has that property for free,
#     which is `UOp.tuplize`'s return type here (P3, with the sort it feeds).
#   `hashlib.sha256` in `UOp.key` -- a digest over the render. `key` is P3 with
#     the cache it keys; the C effect would be `tinygrad/runtime/`'s.
#   `pickle` in `deconstruct_function` and `PatternMatcher.__reduce__` -- Bend
#     has no code objects to pickle, and the rules become top-level defs
#     dispatched by a tag, which is what the master plan already prescribes.
#   `exec` in `_sym_fxn` -- it builds Python source from the graph and runs it
#     with a namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`.
#     Bend has no `eval` and no generated code, so `sym_infer` needs either a C
#     effect that compiles a lambda or a tree-walking interpreter. P3/P6.
#   `sys._getframe` in `get_location` and in `rewrite_group` -- a pattern's
#     source location. That is CPython's frame stack, and every `UPat` carries
#     a `location` that the viz and `print_match_stats` read. Rebuilt in P8 on
#     the `IO.now` clock, the same answer helpers.bend gives for the profiler.
#   `time.perf_counter` in `TrackedPatternMatcher.rewrite` -- the per-rule
#     timing. Same clock story as `cpu_profile` in helpers.bend; P8.
#   `atexit` + `diskcache_put` in `save_to_diskcache` and `print_match_stats` --
#     a pickled `RewriteTrace` on disk for the viz. The sqlite/pickle cache is
#     P6, and the viz is P8.
#   `os.execv` in `launch_viz` -- re-exec into `viz/serve.py`. P8.
#   `collections.Counter` in `gcd` and `divide_exact`, and `itertools` in
#     `split_uop`, `contract`, `broadcast_axes`, `argfix` and `_align_left` --
#     folds over Python iterables. Each becomes a Bend fold; P3, with the
#     symbolic helpers they serve.
#   `functools.reduce(operator.and_, ...)` in `gcd` -- the same.
#   `operator.neg/add/sub/mul/ne/lt/xor/or_/and_/rshift/lshift/max` in
#     `python_alu`, and `math.*` in `safe_exp2`/`safe_pow` -- the `python_alu`
#     table. F32 arithmetic is native in Bend and `F32.is_eq`/`is_lt` exist, so
#     this table is a match ladder; P3, with `exec_alu` (whose `tuple` operand
#     case is a vectorised ALIKE branch).
#   `math.inf` in `identity_element` and `_min_max` -- Bend cannot name an
#     infinity in a U32, so it is `F32.div(1, 0)`; the ONE place dtype.py's
#     `dt.min` for a float needs the seam, and `identity_element` above spells
#     it out.
#   `Buffer`/`MultiBuffer` in `UOp.buffer`, `UOp.realized`, `UOp._buffer_view`,
#     `new_buffer`, `from_buffer`, `_frompy`, `to_elf`, `TinyELF` and
#     `canonicalize_device` -- the device memory layer. P6, and `ParamArg.buffer`
#     is the slot they all read.
#   `Estimates` in `KernelInfo` -- PORTED 2026-10-30 as a FIELD, in
#     `renderer/estimates.bend`. What is NOT PORTED is the VALUE: upstream's
#     only writer is `codegen/__init__.py:446` and `do_estimates` is a WALL in
#     `codegen/kernel.bend`, so every `KernelInfo` the port builds carries
#     `estimates=None`.
#   `CustomFunction` -- PORTED 2026-10-03, at ops.py's own position (between
#     `OPAQUE_CALL_BODIES` and `CallInfo`), together with `Arg`'s `ACustom` arm,
#     `eq_customfunction` and `UOp.custom_function`. The old text here said it was
#     PORTABLE but unreachable and so would "land with" the P6 hcq2 work; it landed
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)`
#     needs the datatype and `spec.bend`'s `sh_22` is stale until it has one. Being
#     P6 only ever described the CALLERS, never the type.
#     what is still open is the other half, and it is not optional: upstream moved
#     `CallInfo.dtype` into `CustomFunction.dtype`, so a CALL's return dtype now
#     lives on its CUSTOM_FUNCTION body (`dtype_from_uop`'s CALL arm is
#     `return src[0].dtype`). `CallInfo` here STILL HAS `dtype`, and it is still
#     read by `eq_callinfo` and by `uop/spec.bend`'s `arg_call`/`sh_23`. So the
#     re-cut is a SEPARATE change with its own blast radius, not a field delete:
#     `sh_23` compares a DECLARED dtype against the node's own, and under HEAD
#     there is no declared dtype to compare -- the CALL's dtype IS its body's. P3,
#     with `dtype_from_uop`.
#     MEASURED 2026-10-06, so the next reader does not have to re-derive it: the
#     eleven-site, seven-file delete is APPLIED AND GREEN in a scratch copy of this
#     tree, it moves `--graph loop`'s `arg` chunk to CPython's bytes, and it closes
#     HALF the row -- `dtype` and `shape` stay `?` because `fold.bend` never settles
#     that node, which is a second defect. See the `CallInfo` block above for the
#     `git log -S` pin, and `spec.bend`'s own `arg_call` comment for its stale half.
#   `UPat.custom_function(fn, kwargs)` -- ops.py:1509 upstream, still NOT PORTED. A
#     `PatternMatcher` rule constructor, so it lands with `uop/upat.py`.
#   `UOp.param_like(slot, name=None)` -- ops.py:1241 upstream. `name` was added so a
#     scalar argument can be bound by NAME while its slot and value stay out of the
#     schedule cache key. P6, with the hcq call sites that use it.
#   `UOp.contiguous_view()`'s new tail -- upstream now returns a BITCAST SLICE
#     (`b.src[0].flatten()[...]`) where the pin returned `(b.rtag(None), offset)`, and
#     it computes the offset with `strides_for_shape` instead of a
#     `pm_contiguous_view_offset` matcher. P3 with `symbolic.bend`; the matcher form is
#     NOT PORTED for the reason the pattern compiler is, below.
#   `grad_fxn` in `CallInfo` and `uopfunc` -- a Python function object; a Bend
#     closure is single-use and is a `Type`, so it cannot be a `Data` field.
#     The reverse-mode plumbing is `tinygrad/nn/gradient.py`, P7.
#   `aux` in `CallInfo` and `trace_num` -- the per-call side channel, written by
#     the hcq paths in `tinygrad/runtime/ops_*.py`, which are out of scope.
#   `uopfunc`'s `inspect.signature(fn).bind(...)` -- Python reflection over a
#     function object, used to turn uop arguments into params. P7 with the mixin.
#   `is_any`, `custom_early_reject`, `allow_any_len`, `permutations` and
#     `functools.repeat` in `UPat.__init__`, and `upat_compile` -- the pattern
#     COMPILER (`tinygrad/uop/upat.py`). `UPat` is PORTED (see ops.py:1447, with
#     a pattern arena of its own); the COMPILER is a separate file whose output is
#     a def per rule, so the machinery here dispatches a tag rather than calling
#     a compiled function pointer. `permutations` at arity >= 3 is the one part
#     of `__init__` not ported, and it is unreachable from ops.py.
#   `upat_interpret`'s `types.FunctionType(*deconstruct_function(fxn))` and
#     `inspect.signature(real_fxn).parameters` -- rebuilding a Python function
#     from its code object. Same answer as above: rules are top-level defs.
#   `REWRITE_STACK_LIMIT` and the `BottomUpGate` exception in
#     `RewriteContext.unified_rewrite` -- the stack limit is a fuel budget here
#     (the same `case 0n:` the walks use) and the gate is a value, because a
#     Bend def cannot raise. `BottomUpGate` therefore becomes a `Maybe` result
#     the driver inspects; P3, with the engine.
#   `ops.py`'s `SPEC > 1` block in `UOpMetaClass.__call__` -- `spec_full.rewrite`,
#     `created._shape` and `test_pyrender`. That is `tinygrad/uop/spec.py`, P3,
#     and `dtype_from_uop`'s `None` is the check in the form this port states.
#   `Ops` reverse lookup (`Ops("ADD")`) and `AxisType` reverse lookup -- not
#     called by ops.py; `AxisType.of` is here anyway because `range_str` needs
#     a name and a test needs a name.
