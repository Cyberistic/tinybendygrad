# uop-ops comparison — `tinygrad/uop/ops.py` → `tinybendygrad/uop/ops.bend`

Read with the Bend file. Line numbers are the **Python's**, so every row diffs
against `ops.py` with `sed -n`. `bend` is the def name in
`tinybendygrad/uop/ops.bend`; `.sel` / `.go` / `.node` suffixes are the helper
ladders the representation forces (a computed value cannot be a `match`
scrutinee, so the value gets its own def whose *parameter* is the scrutinee).

## Summary

| | count |
| --- | --- |
| ops.py defs / methods / dataclasses, all inventoried | 238 rows |
| **faithful** (same shape, same name, same comment) | 3 |
| **adapted** (same meaning, different shape; the def carries the reason) | 27 |
| **MISSING** (inventoried as `# TODO(p3) ops.py:N`, not written) | 205 |
| of the MISSING: **blocked** by the two Bend rules below | ~110 |
| of the MISSING: **P6 / P8 / hardware** (Buffer, pickle, `exec`, `sys._getframe`, `atexit`, `os.execv`) | ~55 |
| of the MISSING: **not blocked**, just not reached — the honest remainder | ~40 |
| **extra** (the port has something ops.py does not) | 5 |
| Bend defs / types in the file | 220 defs, 20 types, 2611 lines |
| `@unsafe` | 0 |
| `--check-only` | `ALL PROOFS CHECK`, exit 0 |

The 205 MISSING rows are not a stub and not an oversight. They fall into three
kinds and the table says which on every row, because the difference matters:
**blocked** (a Bend rule or a later phase's hardware), **not blocked** (the
def is writable today and I did not write it — the honest remainder, and every
such row is a TODO with its line number), and **partial** (`UOp.const`,
`UOp.topovisit`, `KernelInfo.function_name`, which are written and are wrong in
a stated way).

The blocked half is one wall, and it is the finding this unit exists to
produce. See `spec/ops.md` and the `# THE INVENTORY` block at the head of the
Bend file.

## The two constraints behind every MISSING row

**A — a self-call must pass a field of its own parameter.** The arena's "field"
is a `U32` read back out of a store, which the checker cannot see as a subterm.
Measured, in `/tmp/bt/e.bend`:

```
def f(u: U32) -> U32:
  match u:
    case 0: 0
    case _: f(U32.sub(u, 1))
#| - expected : a decreasing self-call (arguments are read left to right: each
#|             passed unchanged until one shrinks)
```

Every property fold over the graph is a recursion of this shape. `toposort` is
*not* affected, because its recursion is on a **worklist** — a list tail of its
own parameter, with the node being visited as a payload — and that is written
and green.

**B — mutual recursion is refused**, and tinygrad's folds are a cycle:
`dtype_from_uop` reads `src[0]._shape` (INDEX's image test) while `_shape` reads
`src[0].dtype` (BITCAST's itemsize ratio), and `simplify()` calls
`graph_rewrite`, whose rules call `dtype` and `shape`. Python breaks that cycle
with the `recursive_property` memo on `node.__dict__`; this port has no memo
(header point 5), so the cycle is unbreakable as written.

## The table

| ops.py | line | bend | verdict |
| --- | --- | --- | --- |
| `class AxisType` | 17 | `type AxisType` | adapted — an `Enum` becomes a datatype; the constructor order *is* the `auto()` value, which is why `AxisType.value` exists |
| `AxisType.__repr__` | 18 | `AxisType.name` | adapted — `__repr__` returns `str(self)`, which is `AxisType.name` |
| `class ParamArg` | 23 | `type ParamArg` | adapted — 13 fields, 9 `\|None` become 9 `Maybe`; `buffer` and `device` are named as the two the port re-encodes, with the reason on the def |
| `ParamArg.__repr__` | 41 | *(none)* | MISSING — B/A. It formats `size` only when it is set and skips nine fields at their defaults; it needs `dt_name`, which is available, so this row is **extra work not blocked** — the honest note is that it was not reached |
| `axis_letters` | 49 | `axis_letters` | faithful |
| `axis_colors` | 51 | `axis_colors` | faithful |
| `axis_to_pos` | 55 | `axis_to_pos` (`type Pos`) | adapted — the dict holds negative ints and Bend has no signed integer, so the value is `Pos{neg, mag}` |
| `range_start` | 58 | `range_start` | faithful |
| `identity_element` | 61 | *(none)* | MISSING — needs `dt.min` (dtype.py) which is in `./dtype.bend`; **not blocked**, simply not reached |
| `resolve` | 64 | *(none)* | MISSING — A/B. Calls `x.simplify()` and reads `.vmin`/`.vmax` |
| `_suop` | 71 | *(none)* | MISSING — A/B. Its `uop_fxn` argument is a Python callable |
| `smax` | 74 | *(none)* | MISSING — A/B, and `*lst` is a variadic |
| `smin` | 75 | *(none)* | MISSING — as `smax` |
| `srender` | 76 | *(none)* | MISSING — A/B. `x.render()` is the renderer (P5/P8) |
| `_align_left` | 77 | *(none)* | MISSING — **not blocked**; a pure shape fold, not reached |
| `_broadcast_shape` | 80 | *(none)* | MISSING — **not blocked**; a pure shape fold, not reached |
| `broadcast_axes` | 89 | *(none)* | MISSING — as `_broadcast_shape`; also reads `resolve` |
| `ssimplify` | 94 | *(none)* | MISSING — A/B |
| `sym_infer` | 95 | *(none)* | MISSING — **blocked twice**: A/B, and `_sym_fxn` `exec`s generated Python, which Bend has no equivalent of |
| `range_str` | 97 | *(none)* | MISSING — **not blocked** once `axis_id`/`axis_type` are; reads `Ops.ADD`-level data only |
| `multirange_str` | 101 | *(none)* | MISSING — as `range_str`, plus `sorted` by `x.arg` |
| `shape_to_shape_arg` | 106 | *(none)* | MISSING — reads `UOp.const` (ported) and `dtypes.is_int`; **not blocked**, not reached |
| `consumer_map_from_toposort` | 112 | *(none)* | MISSING — as `toposort`; the `dict[UOp, dict[UOp, None]]` is a `List` of pairs |
| `promo_dtype` | 120 | *(none)* | MISSING — A/B. Reads `x.dtype` per src; the port's version takes the dtypes as a parameter, which is what breaks the dtype/shape cycle |
| `dtype_from_uop` | 124 | *(none)* | MISSING — A/B, and it is one arm of the cycle. Its 25 arms are the spec's dtype column; LAWS/spec.bend already proves that column over a tree |
| `class UOpMetaClass` | 196 | *(none)* | adapted — the metaclass's `__call__` is the arena |
| `UOpMetaClass.__call__` | 198 | `intern.find`, `intern.put`, `intern.get`, `UOp.make`, `UOp.of`, `UOp.new`, `UOp.new.of` | adapted — the ucache is a linear scan of the arena; the `SPEC > 1` block is NOT PORTED (P3) |
| `all_metadata` | 215 | *(none)* | extra — Python's `WeakKeyDictionary` side table. The port's node has no metadata field at all, so this is a **documented loss**: `UOp.metadata` exists and the constructor's `metadata=` keyword does not |
| `class recursive_property` | 218 | *(none)* | MISSING — header point 5. Its memo is dropped; the cost is exponential in DAG depth and it is stated |
| `recursive_property.__init__` | 219 | *(none)* | MISSING — as `recursive_property` |
| `recursive_property.__get__` | 223 | *(none)* | MISSING — as `recursive_property`; the `for node in x.toposort(gate=...)` fill loop is a second graph walk |
| `class _UOpTuple` | 228 | *(none)* | MISSING — P3, with `UOp.tuplize`, which consumes it |
| `_UOpTuple.__eq__` | 232 | *(none)* | MISSING — as `_UOpTuple`. **The port gets this for free**: a `List<&2, U32>` of arena indices compares by index, and the type comment on `Found` records why |
| `_UOpTuple.__ne__` | 233 | *(none)* | MISSING — as `_UOpTuple` |
| `class UOp` | 240 | `type Node`, `type Arena`, `type Found` | adapted — the dataclass becomes a store; a UOp is a `U32` index |
| `UOp.dtype` | 246 | *(none)* | MISSING — A/B. One arm of the dtype/shape cycle |
| `UOp.__del__` | 247 | *(none)* | MISSING — **deliberately**: the arena is monotone, so nothing is evicted. Recorded where `intern` is |
| `UOp.__reduce__` | 251 | *(none)* | MISSING — pickle; Bend has no code objects |
| `UOp.replace` | 252 | *(none)* | MISSING — **not blocked**; it is `intern` on a new key |
| `UOp.rtag` | 257 | *(none)* | MISSING — as `replace` |
| `UOp.val` | 259 | *(none)* | MISSING — as `replace`; it reads `self.arg` and `self.src[0]` |
| `UOp.is_invalid` | 265 | *(none)* | MISSING — as `val` |
| `UOp.key` | 267 | *(none)* | MISSING — A/B, and `hashlib.sha256` over the render (P3/P6) |
| `UOp.__repr__` | 269 | *(none)* | MISSING — P8; it is `pretty_print` from `uop/render.py` |
| `UOp.argstr` | 272 | *(none)* | MISSING — **not blocked**; it is a match over the `Arg` constructors, and `Arg` is ported |
| `UOp.tagstr` | 275 | *(none)* | MISSING — **not blocked** |
| `UOp.backward_slice` | 278 | *(none)* | MISSING — as `toposort` |
| `UOp.backward_slice_with_self` | 284 | *(none)* | MISSING — as `backward_slice` |
| `UOp.op_in_backward_slice_with_self` | 285 | *(none)* | MISSING — as `backward_slice` |
| `UOp._bool_slice` | 290 | *(none)* | MISSING — A/B |
| `UOp.bool_slice` | 293 | *(none)* | MISSING — A/B, plus the "self is added outside the cache" NOTE, which is a memo design decision this port does not face |
| `UOp.toposort` | 295 | `UOp.toposort`, `UOp.toposort_nocalls`, `toposort`, `Topo.*`, `Arena.push_srcs*` | adapted — the `while stack:` loop is a fuel countdown whose recursion is on the worklist. The `gate` argument is NOT PORTED (a Python callable; the two call sites that pass one are P3/P4). `enter_calls` becomes `_nocalls` |
| `UOp.topovisit` | 309 | `UOp.topovisit` | adapted — inventory + shape; the `visitor` callable is NOT PORTED, and the def currently answers the toposort order. **Recorded as a partial**, not as faithful |
| `UOp.tuplize` | 322 | *(none)* | MISSING — P3, with `_UOpTuple` |
| `UOp._shape` | 329 | *(none)* | MISSING — A/B. The other arm of the dtype/shape cycle, and 35 arms |
| `UOp.shape` | 456 | *(none)* | MISSING — as `_shape`; the Python `raise` is the `Maybe` |
| `UOp.shard_shape` | 461 | *(none)* | MISSING — as `_shape` |
| `UOp.max_shard_shape` | 467 | *(none)* | MISSING — as `_shape`, plus `to_max_shape` |
| `UOp.ended_ranges` | 470 | *(none)* | MISSING — A/B |
| `UOp._ranges` | 483 | *(none)* | MISSING — A/B. A `dict[UOp, None]` keyed by an index is a `List<U32>` |
| `UOp.ranges` | 497 | *(none)* | MISSING — as `_ranges` |
| `UOp.axis_id` | 502 | *(none)* | MISSING — **not blocked**; it is `self.arg[0:-1]`, and `ARange` is ported |
| `UOp.axis_type` | 507 | *(none)* | MISSING — as `axis_id` |
| `UOp.simplify` | 513 | *(none)* | MISSING — A/B, and the `symbolic` matcher is `uop/symbolic.py` (P3) |
| `UOp.ssimplify` | 520 | *(none)* | MISSING — A/B |
| `UOp._eval` | 523 | *(none)* | MISSING — A/B, plus `expected_type: Type[T]` has no Bend analogue |
| `UOp.__bool__` | 529 | *(none)* | MISSING — as `_eval` |
| `UOp.__int__` | 530 | *(none)* | MISSING — as `_eval` |
| `UOp.__float__` | 531 | *(none)* | MISSING — as `_eval` |
| `UOp.substitute` | 532 | *(none)* | MISSING — A/B. It takes a `PatternMatcher` and an `extra_pm`, and calls `graph_rewrite` |
| `UOp.__index__` | 539 | *(none)* | MISSING — as `_eval` |
| `UOp.trace_num` | 544 | *(none)* | MISSING — A/B, and it reads `ucount`/`uop_fields`, the tracing tables |
| `UOp.sink` | 559 | `UOp.sink` | adapted — the `**kwargs` are gone (header: they carry op/arg/tag) and the return is `Found` |
| `UOp.group` | 561 | `UOp.group`, `UOp.group.of` | adapted — as `UOp.sink`; the one-element branch is the ladder's middle arm |
| `UOp.body` | 565 | *(none)* | MISSING — **not blocked**; it is `self.src[0]` guarded by the op |
| `UOp.is_inline_call` | 570 | *(none)* | MISSING — as `body`, plus `self.arg.precompile` |
| `UOp.has_unbound_outputs` | 573 | *(none)* | MISSING — as `unsharded_base` |
| `UOp.unbound_outputs` | 578 | *(none)* | MISSING — as `has_unbound_outputs` |
| `UOp.index` | 581 | *(none)* | MISSING — **not blocked**; the Python body is `UOp(Ops.INDEX, src=(self,)+new_srcs, **kwargs)`, and `UOp.new` is ported |
| `UOp.__getitem__` | 585 | *(none)* | MISSING — P7; it is `mixin/op.py`'s view path and `_normalize_indices` |
| `UOp._uop` | 600 | *(none)* | MISSING — **not blocked**; it returns `self` |
| `UOp._wrap_uop` | 602 | *(none)* | MISSING — as `_uop` |
| `UOp.const_like` | 603 | *(none)* | MISSING — A/B, plus `_shape` |
| `UOp.vconst_like` | 606 | *(none)* | MISSING — A/B |
| `UOp.ufix` | 609 | *(none)* | MISSING — **not blocked** |
| `UOp.broadcast` | 612 | `UOp.broadcast`, `UOp.broadcast.go`, `UOp.replicate*` | adapted — `*count` is a `U32`; the `(self,)*count` is its own fold |
| `UOp.load` | 615 | *(none)* | MISSING — **not blocked**; it is one `UOp.new` |
| `UOp.store` | 616 | *(none)* | MISSING — as `load`, plus `const_like` |
| `UOp.end` | 619 | `UOp.end`, `UOp.end.go` | adapted |
| `UOp.backedge` | 620 | `UOp.backedge` | adapted — the three srcs are three `U32` parameters instead of a varargs tuple |
| `UOp.after` | 621 | `UOp.after`, `UOp.after.go` | adapted |
| `UOp.without_after` | 623 | *(none)* | MISSING — **not blocked** |
| `UOp.barrier` | 624 | *(none)* | MISSING — **not blocked** |
| `UOp.ins` | 625 | *(none)* | MISSING — as `barrier`, plus `self.dtype` |
| `UOp.contract` | 626 | *(none)* | MISSING — A/B, plus `itertools.product` and `substitute` |
| `UOp.alu` | 630 | `UOp.alu` | adapted |
| `UOp.const` | 632 | `UOp.const` | adapted — **partial**, and the def says so. The `dtype=` resolution (`from_py`), the `truncate`, and the `.cast` on top are NOT PORTED, so this interns a bare CONST and a CONST of int32 is one node here and two in Python |
| `UOp.ccast` | 640 | *(none)* | MISSING — as `const`, plus `cast` |
| `UOp.cconst` | 643 | *(none)* | MISSING — as `const` |
| `UOp.range` | 645 | `UOp.range_end` | adapted — the `end` is a `U32` index because `sint_to_uop` is `UOp.const`; the `dtype=`/`src=` keywords are gone |
| `UOp.loop` | 648 | `UOp.loop`, `UOp.loop.go` | adapted |
| `UOp.special` | 650 | `UOp.special` | adapted — as `UOp.range_end` |
| `UOp.wmma` | 652 | *(none)* | MISSING — **not blocked**; it is one `UOp.new` with an `AWmma` arg, and the dtype comment ("stored in the arg because bitcast rewrites change src dtypes") is on the `AWmma` def |
| `UOp._rop` | 655 | *(none)* | MISSING — A/B, plus `resolve` and `permute` |
| `UOp.invalid` | 666 | *(none)* | MISSING — as `UOp.const` |
| `UOp.valid` | 667 | *(none)* | MISSING — as `const_like` |
| `UOp.get_idx` | 668 | *(none)* | MISSING — as `UOp.stack`, which is a mixin (P7) |
| `UOp.get_valid` | 671 | *(none)* | MISSING — as `get_idx` |
| `UOp.reduce` | 674 | *(none)* | MISSING — **not blocked** |
| `UOp.bufferize` | 679 | *(none)* | MISSING — **not blocked** |
| `UOp.allreduce` | 680 | *(none)* | MISSING — **not blocked** |
| `UOp.overflows` | 683 | *(none)* | MISSING — A/B (`vmin`/`vmax`) |
| `UOp.split_uop` | 685 | *(none)* | MISSING — **not blocked**; a generator, which becomes a fold |
| `UOp.unshard` | 692 | *(none)* | MISSING — A/B, plus `UOp.range` (ported) |
| `UOp.sharding` | 707 | *(none)* | MISSING — **not blocked** |
| `UOp.bounds` | 712 | *(none)* | MISSING — A/B, plus `itertools.pairwise`/`accumulate` |
| `UOp.axis` | 718 | *(none)* | MISSING — A/B, and 30 lines of `dedup`/`SHRINK`/`RESHAPE` case analysis |
| `UOp._shard` | 751 | *(none)* | MISSING — A/B |
| `UOp.shard` | 757 | *(none)* | MISSING — as `_shard` |
| `UOp.copy_to_device` | 761 | *(none)* | MISSING — as `_shard`, plus `is_disk_device` (P6) |
| `UOp.store_call` | 769 | *(none)* | MISSING — P6; the executable bulk transfer is a device entry point |
| `UOp.mselect` | 772 | *(none)* | MISSING — **not blocked** |
| `UOp.mstack` | 773 | `UOp.mstack`, `UOp.mstack.go` | adapted |
| `UOp.metadata` | 775 | `UOp.metadata` | adapted — Python reads `all_metadata`, which the port does not have, so this is the identity on the `Maybe` the constructor would have stored |
| `UOp.on_disk` | 778 | *(none)* | MISSING — as `device` (A/B) |
| `UOp.on_creation_device` | 779 | *(none)* | MISSING — as `on_disk` |
| `UOp.needs_storage` | 780 | *(none)* | MISSING — as `on_disk` |
| `UOp.base` | 785 | *(none)* | MISSING — **not blocked**; it is a `match` on the op |
| `UOp.unsharded_base` | 792 | *(none)* | MISSING — as `base` |
| `UOp.storage_base` | 801 | *(none)* | MISSING — as `base`, and it is a `while` loop |
| `UOp.as_shape` | 808 | *(none)* | MISSING — A/B (`ssimplify`) |
| `UOp.marg` | 814 | *(none)* | MISSING — A/B, and `as_shape` |
| `UOp._mop` | 821 | *(none)* | MISSING — A/B, and `shape_to_shape_arg` + `simplify` |
| `UOp.getaddr` | 844 | *(none)* | MISSING — **not blocked** |
| `UOp.device_range_src` | 849 | *(none)* | MISSING — **not blocked**; it is `UOp.range` (ported) |
| `UOp.new_buffer` | 853 | *(none)* | MISSING — P6; `Buffer`/`MultiBuffer` |
| `UOp.from_buffer` | 860 | *(none)* | MISSING — P6 |
| `UOp.empty_like` | 864 | *(none)* | MISSING — A/B, plus `UOp.empty` (P7 mixin) |
| `UOp._frompy` | 870 | *(none)* | MISSING — P6, and `struct.pack` over a ctypes struct |
| `UOp.clone` | 882 | *(none)* | MISSING — P6 |
| `UOp.device` | 890 | *(none)* | MISSING — A/B. Ten arms, and it is the second half of the device cycle |
| `UOp.is_virtual` | 905 | *(none)* | MISSING — A/B, and it reads `device` and `dtype` |
| `UOp.addrspace` | 910 | *(none)* | MISSING — A/B |
| `UOp.buf_uop` | 925 | *(none)* | MISSING — A/B, and it is a `while` loop |
| `UOp.contiguous_view` | 934 | *(none)* | MISSING — A/B, plus `pm_mops` (P4) |
| `UOp.contiguous_view_offset` | 950 | *(none)* | MISSING — as `contiguous_view` |
| `UOp.has_buffer_identity` | 952 | *(none)* | MISSING — **not blocked** |
| `UOp._base_buffer_is_realized` | 959 | *(none)* | MISSING — as `has_buffer_identity`, and it is a `while` |
| `UOp._buffer_view` | 966 | *(none)* | MISSING — P6 |
| `UOp.buffer` | 972 | *(none)* | MISSING — P6 |
| `UOp.realized` | 997 | *(none)* | MISSING — P6 |
| `UOp.is_realized` | 1008 | *(none)* | MISSING — P6 |
| `class KernelInfo` | 1340 | `type KernelInfo` | adapted — `estimates` is NOT PORTED (P5 renderer) and the def says so |
| `KernelInfo.function_name` | 1347 | `KernelInfo.function_name` | adapted — **partial**: `to_function_name` is NOT PORTED (it needs `ansistrip`, a helpers.py regex already listed as not-ported), so this is the name unchanged |
| `class ProgramInfo` | 1350 | `type ProgramInfo` | adapted — `target` is NOT PORTED (P6, and helpers.bend already lists `Target` there) |
| `ProgramInfo.launch_dims` | 1359 | *(none)* | MISSING — A/B, via `sym_infer` |
| `ProgramInfo.vals` | 1364 | *(none)* | MISSING — A/B, and `k.expr` |
| `ProgramInfo.from_sink` | 1369 | *(none)* | MISSING — as `launch_dims`; the `Target()` default goes with the field |
| `OPAQUE_CALL_BODIES` | 1389 | `GroupOp.opaque_call_bodies` | adapted — a `set` of ops becomes a ladder |
| `class CallInfo` | 1392 | `type CallInfo` | adapted — `grad_fxn` and `aux` dropped, both named on the def with the reason |
| `CallInfo.__reduce__` | 1400 | *(none)* | MISSING — pickle |
| `CallInfo.__repr__` | 1401 | `CallInfo.repr`, `CallInfo.repr_name`, `CallInfo.repr_body` | adapted — the `grad_fxn` half goes with the field; moved below the equality block because it reads `eq_dt` |
| `safe_exp2` | 1408 | *(none)* | MISSING — **not blocked**; F32 has no `**` and Bend has no pow-with-overflow, so it is a ladder on the sign of the exponent |
| `safe_pow` | 1412 | *(none)* | MISSING — as `safe_exp2`; the `complex` case is a Python-only outcome |
| `python_alu` | 1417 | *(none)* | MISSING — **not blocked**; 27 lambdas become a match ladder over `F32`/`U32` |
| `exec_alu` | 1427 | *(none)* | MISSING — as `python_alu`, plus `truncate` |
| `get_location` | 1438 | *(none)* | MISSING — `sys._getframe`; P8 |
| `class UPat` | 1447 | *(none)* | MISSING — P3, with `uop/upat.py`; the dataclass's 11 fields are portable, its `permutations`/`repeat` and its `functools.cache`d statics are not |
| `UPat.__init__` | 1449 | *(none)* | MISSING — as `UPat` |
| `UPat.dtype` | 1480 | *(none)* | MISSING — as `UPat` |
| `UPat.__reduce__` | 1482 | *(none)* | MISSING — pickle |
| `UPat.named` | 1485 | *(none)* | MISSING — as `UPat` |
| `UPat.any` | 1489 | *(none)* | MISSING — as `UPat` |
| `UPat.or_casted` | 1490 | *(none)* | MISSING — as `UPat` |
| `UPat.or_bitcasted` | 1491 | *(none)* | MISSING — as `UPat` |
| `UPat.or_after` | 1492 | *(none)* | MISSING — as `UPat` |
| `UPat.var` | 1496 | *(none)* | MISSING — as `UPat`; a `functools.cache`d static |
| `UPat.cvar` | 1499 | *(none)* | MISSING — as `UPat` |
| `UPat.const` | 1501 | *(none)* | MISSING — as `UPat` |
| `UPat.f` | 1504 | *(none)* | MISSING — as `UPat` |
| `UPat.sink` | 1507 | *(none)* | MISSING — **not blocked**; `UOp.sink` is ported |
| `UPat.index` | 1509 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.cast` | 1511 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.bitcast` | 1514 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.load` | 1515 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.store` | 1516 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.reduce` | 1517 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.broadcast` | 1521 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.after` | 1522 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.end` | 1523 | *(none)* | MISSING — as `UPat.sink` |
| `UPat.backedge` | 1524 | *(none)* | MISSING — as `UPat.sink` |
| `UPat._broadcasted` | 1526 | *(none)* | MISSING — as `UPat` |
| `UPat.ufix` | 1529 | *(none)* | MISSING — as `UPat` |
| `UPat.__floordiv__` | 1530 | *(none)* | MISSING — as `UPat`; an operator overload |
| `UPat.__rfloordiv__` | 1531 | *(none)* | MISSING — as `UPat` |
| `UPat.mod` | 1532 | *(none)* | MISSING — as `UPat` |
| `UPat.alu` | 1533 | *(none)* | MISSING — as `UPat` |
| `UPat.match` | 1537 | *(none)* | MISSING — P3, with `UPat`; the `list[dict[str, UOp]]` return is a list of bind-lists |
| `deconstruct_function` | 1556 | *(none)* | MISSING — Python code objects; rules become top-level defs dispatched by a tag |
| `upat_interpret` | 1566 | *(none)* | MISSING — as `deconstruct_function` |
| `upat_deferred_compile` | 1580 | *(none)* | MISSING — P3, `uop/upat.py` |
| `class PatternMatcher` | 1587 | *(none)* | MISSING — P3, with the rewrite engine |
| `PatternMatcher.__init__` | 1588 | *(none)* | MISSING — as `PatternMatcher` |
| `PatternMatcher.__reduce__` | 1600 | *(none)* | MISSING — pickle |
| `PatternMatcher.__add__` | 1603 | *(none)* | MISSING — as `PatternMatcher` |
| `PatternMatcher.rewrite` | 1605 | *(none)* | MISSING — A/B. The `pdict` is a `List` of rules per op (Bend's `Map` is string-keyed) and the `match` is a Python callable |
| `TRACK_MATCH_STATS`, `REWRITE_STACK_LIMIT`, `match_stats` | 1615-1617 | *(none)* | MISSING — a process-wide `ContextVar`; the port threads a record, as `helpers.bend` does for `Flags` |
| `ucount`, `uop_fields` | 1620-1621 | *(none)* | MISSING — P8; the tracing tables |
| `class TrackedGraphRewrite` | 1624 | *(none)* | MISSING — P8 |
| `tracked_keys`, `tracked_ctxs`, `_name_cnt` | 1634-1636 | *(none)* | MISSING — P8 |
| `CAPTURE_PROCESS_REPLAY` / `replay_capture` / `save_to_diskcache` | 1638-1644 | *(none)* | MISSING — pickle to a disk cache; P6 |
| `add_trace_group` | 1646 | *(none)* | MISSING — P8 |
| `active_group`, `active_rewrites` | 1650-1651 | *(none)* | MISSING — P8 |
| `rewrite_group` | 1652 | *(none)* | MISSING — P8, and it is a decorator over `sys._getframe` |
| `class TrackedPatternMatcher` | 1698 | *(none)* | MISSING — P3, and its `try/except` becomes a value |
| `TrackedPatternMatcher.rewrite` | 1699 | *(none)* | MISSING — as `TrackedPatternMatcher` |
| `class RewriteTrace` | 1727 | *(none)* | MISSING — P8 |
| `print_match_stats` | 1733 | *(none)* | MISSING — P8 |
| `launch_viz` | 1749 | *(none)* | MISSING — P8, and it `os.execv`s |
| `SENTINEL` | 1763 | *(none)* | MISSING — the dict's "value is a Maybe with 3 states" collapses to `Maybe` plus one `Nothing` sentinel in the value type, which is a P3 design note |
| `class BottomUpGate` | 1764 | *(none)* | MISSING — an exception; a Bend def cannot raise, so it becomes a `Maybe` the driver inspects |
| `class RewriteContext` | 1765 | *(none)* | MISSING — A/B. The `while` loops in both its methods are fuel, and the `waitlist` dict is a list of pairs |
| `RewriteContext.pm_rewrite` | 1775 | *(none)* | MISSING — as `RewriteContext`; the `pm` is a Python callable |
| `RewriteContext.cached_bpm_rewrite` | 1777 | *(none)* | MISSING — as `RewriteContext` |
| `RewriteContext.walk_rewrite` | 1782 | *(none)* | MISSING — as `toposort`, which IS ported: the same worklist shape with a `replace` dict beside the stack |
| `RewriteContext.unified_rewrite` | 1808 | *(none)* | MISSING — A/B, and it is the deepest of them: a `deque` of `(node, stage, node)` triples, a `waitlist`, a fixed-point loop, and a stall error |
| `graph_rewrite` | 1879 | *(none)* | MISSING — A/B, and the `@rewrite_group` decorator |
| `sint_to_uop` | 1885 | *(none)* | MISSING — **not blocked**; it is `UOp.const(x, dtype)`, ported |
| `to_max_shape` | 1886 | *(none)* | MISSING — A/B, via `vmax` |
| `_substitute` | 1888 | *(none)* | MISSING — P3, a `PatternMatcher` |
| `_pm_resolve_params` | 1889 | *(none)* | MISSING — as `_substitute` |
| `resolve_returned_after` | 1891 | *(none)* | MISSING — A/B |
| `remove_all_tags` | 1896 | *(none)* | MISSING — as `resolve_returned_after` |
| `pm_drop_after` | 1899 | *(none)* | MISSING — as `remove_all_tags` |
| `gate_kernel_sink` | 1901 | *(none)* | MISSING — **not blocked**; it is a match on the op and a match on the arg |
| `contiguous_bitcast_index` | 1907 | *(none)* | MISSING — A/B |
| `pm_contiguous_view_offset` | 1915 | *(none)* | MISSING — P3, a `PatternMatcher` |
| `sint`, `Variable`, `ConstLike` | 1925-1928 | `type Sint` | adapted — the aliases become datatypes; `Variable = UOp` and `ConstLike = ConstType\|Variable\|tuple[...]` are the two record types `SInt` and `Const` already carry |

## One deviation from the brief, and why

`./../dtype.bend` is **not** imported. The gate says "must reach zero errors",
and importing it makes that unreachable for any file: its fp16/bf16/fp8/i64 C
effects are foreign code, so the checker prints `14 defs rely on unsafe or
foreign code` and exits 1. A two-line file that imports `dtype.bend` and does
nothing else prints the same fourteen lines, so the notice is a property of
`dtype.bend`, not of this file. `Dt` therefore comes from `./LAWS/spec.bend`,
which is the ONE datatype and is what `dtype.bend` itself uses. The two
`dtype.py` functions `ops.py` needs and `dtype.bend` has —
`least_upper_dtype` and `DType.min`/`DType.max` — land with the folds that call
them, and the import comes back with the notice.

## extra — the port has something ops.py does not

| bend def | why it exists |
| --- | --- |
| `ABad{}` | the arena's bottom. Python's `self.src[0]` on an empty src raises IndexError; a Bend fold cannot raise, so the miss is one inert value. It is the **only** Arg constructor Python does not have |
| `Found` | the `Arena & U32` pair as a `Data` record, because a pair is a `Type` and cannot carry a `+` |
| `UOp.make` + `UOp.of` | the constructor is two calls on the same key, because a pair can only be destructured when it is a *parameter* |
| `Ops.value` | Python's `FastEnum` is both a name and a number, and `UOp.tuplize` uses the number |
| `Arena.src_from` / `Arena.src_to` | `self.src[1:]` and `self.src[:k]`, which `range_start`, `ended_ranges` and `src_without_body` all slice |

## Edge cases checked

| Python edge case | survives? | where |
| --- | --- | --- |
| empty `srcs` (`UOp.group()`, `UOp.after()`, `UOp.end()`, `UOp.mstack()`) | yes | `UOp.group.of`'s `Nil{}` arm makes a GROUP; the three `.go` ladders hand the arena back |
| one-element `srcs` | yes | `UOp.group.of`'s middle arm returns the node itself, which is the Python's `if len(srcs) == 1: return srcs[0]` |
| `count == 1` in `broadcast` | yes | `UOp.broadcast.go`'s `isone` arm |
| `None` UOp | yes, as index 0 | `UOp.is_none`; `Arena.empty` starts with the bottom at 0 |
| `IndexError` on a short `src` | yes, as 0 | `Arena.src`'s `Maybe.default(..., 0)` |
| an index that was never interned | yes, as the bottom | `Arena.node` |
| a cycle in the graph | yes | `t_cycle` and `t_cycle_terminates` in `main` |
| `True == 1` as dict keys | yes | `t_dtype_key`: `APy{CBool{True{}}}` and `APy{CInt{1}}` are two nodes, because `type(arg)` is the Arg constructor |
| the same key twice | yes | `t_hashcons`: one node, the same index |
| `REWRITE_STACK_LIMIT` / an infinite rewrite loop | the fuel | `toposort`'s `case 0n:`; the same for `unified_rewrite` when it is written |
