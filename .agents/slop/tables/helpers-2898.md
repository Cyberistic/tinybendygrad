<!-- FROM: tinybendygrad/helpers.bend:2898 -->
# BLOCK:
# NOT PORTED -- tinygrad/helpers.py, and why
#
# The 64-bit signed div/mod (ceildiv64, cdiv64, cmod64, floordiv64, floormod64)
# and the 64-bit integer truncation are C effects, not pure defs: a signed
# 64-bit quotient and a 2^64-1 bound have no U32 encoding. They are declared in
# ./dtype.bend next to the runtime/dtype.c that implements them.
#
# The ContextVar variable LIST is 3 of 61 (the count is measured at the top of this
# NOOPT, DEV, CACHELEVEL, ...) is phase P6: they need FIELDS on the record, and the
# save/restore MECHANIC they need is already ported above -- `Context.__enter__`
# snapshots named keys and `Context.__exit__` writes them back, so P6 is a wider
# `Flags` and a wider `Flags.snap1.go` dispatch, not a new mechanism.
#
# `Target` and `Target.parse` are PORTED ABOVE: `Target` is the record upstream's
# `helpers.py:198` defines, and `Target.parse` is the DEV string parser. What is
# still phase P6 is the DEV ContextVar itself, which is what a `Target` points at.
# `classproperty` is a descriptor: it makes an attribute read as a function.
# Bend has no descriptors, no class of methods and no `getattr`, and every
# ported def here is a top-level function, so there is nothing for it to
# attach to.
# `fromimport(mod, frm)` is a dynamic import. The set of modules is not known
# until the whole port exists, and Bend's imports are leading lines resolved
# before any def runs, so this becomes a compile-time import in the file that
# needs the name.
# `canonicalize_strides` and `strides_for_shape` are `functools.cache`d over
# tuples and belong to shape.bend, which owns the layout IR.
# `getenv` is ported here as `getenv_str` (the `type(default) is str` arm) and
# `getenv_int` (the `int` arm), because Flags and the dtype defaults need the first
# and `DEBUG` needs the second; between them they keep Python's
# `type(default)(os.getenv(key, default))` shape.
# `get_child`, `word_wrap`, `pad_bytes`, `pluralize`, `polyN`,
# `to_function_name`, `select_by_name`, `select_first_inited`,
# `suppress_finalizing`, `panic`, `stderr_log` and `temp` are string, regex and
# reflection helpers for the interpreter-facing surfaces (viz, the object
# dumper, the error printer). They are ported with the module that uses them.
# `is_numpy_ndarray` is a type-identity test against numpy, and numpy is a C
# effect; it is a predicate on the interop layer, not on a Bend value.
# The sqlite disk cache (cache_dir, CACHEDB, db_connection, diskcache_clear,
# diskcache_get, diskcache_put, diskcache, _db_tables, _db_connection, VERSION)
# is a persistent object store with pickle values. Bend has no pickle and no
# object graph to store, so the cache becomes the C-effect arena of P6 and this
# is replaced rather than ported.
# The HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir) is urllib plus a
# temp file plus an atomic rename. It is I/O of exactly the kind the master
# plan puts in runtime/, and its only callers are the weight downloaders.
# The ctypes helpers (from_mv, to_mv, mv_address, to_char_p_p, flat_mv) wrap a
# Python address into a memoryview. Bend's `Array<T>` is already a reference-
# counted buffer, so the arena in P6 owns the memory and these become the
# arena's accessors rather than a port of the casts.
# `trange` IS ported above, as the `range(n)` and the total that `tqdm(range(n),
# total=n)` is. What is left of `tqdm` is its terminal progress bar: ANSI redraw, a
# width from shutil.get_terminal_size and a rate heuristic, plus `disable`, `desc`,
# `unit`, `unit_scale`, `rate`, `n` and `i`. It is pure presentation over a loop the
# caller already owns; the port prints a line per kernel instead (viz.bend, P8).
# `t.__enter__`/`t.__exit__` are the same close-the-bar pair as `Timing` above, which
# IS ported, so the only reason `tqdm` is not is the bar itself.
# `copyreg.pickle(types.CodeType/ModuleType)`, `_serialize_code`,
# `_reconstruct_code` and `_serialize_module` make Python objects picklable.
# Bend has no code objects and no modules to pickle.
# The cProfile-backed `Profiling`, `perf_counter_us`, `TracingKey`,
# `ProfileEvent`, `ProfileRangeEvent`, `ProfilePointEvent`, `cpu_events`,
# `cpu_profile`, `profile_marker` and `_format_fcn` are the Python profiler.
# The events are real behaviour (viz.bend asserts on them) but the data source
# is CPython's own frame stack, which does not exist in Bend; they are rebuilt
# in P8 on the IO.now clock, which is why `Timing` above is ported and
# `Profiling` is not.
# `GlobalCounters` is ported above as `Counters`: six fields, `init`, `reset`, five
# bumps and the per-device dict, threaded like the arena rather than global. Its
# remaining gap is `time_sum_s`, which needs an F32 add that `base.bend` does not
# have (`F32.add` is a law at references/bend/bend2/base.bend:1681
# symbol=F32.add), so in P4 the engine's clock writes
# that one field. Nothing else in the class is outstanding.
# `disable_gc` and the DEBUG_GC `gc.callbacks` hook control CPython's collector.
# Bend's collector is the reference count in the runtime, which no def can
# switch off, so these have no meaning here.
# `count` and `Metadata` are tiny value helpers with no caller in the two files
# this phase ports: `Metadata` rides on UOp (P3) and `count` is Python's own
# itertools.count spelled out.
#
