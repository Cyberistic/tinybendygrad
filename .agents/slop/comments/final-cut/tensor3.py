import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/tensor.bend"

# **THE **THIRD **PASS**: **THE **265-LINE **BLOCK**, **⇒⇒† AND **EVERY **`TODO(p3)` **MARKER
# **STAYS** (**`checks/marker-audit.py` **READS **THE **MARKER **AND **ITS **REASON**, **⇒⇒† AND
# **THE **GATE'S **CITATION **LEDGER **READS **THE **UPSTREAM **LINE **THE **MARKER **NAMES**),
# **⇒⇒† AND **THE **ESSAY **AROUND **THEM **IS **CUT**.
EDITS = [
  (1689, 1953, """#   tensor.py:534  __iadd__        assign + elementwise.py:101 (Ops.ADD)
#   tensor.py:535  __isub__        assign + elementwise.py sub (Ops.SUB)
#   tensor.py:536  __imul__        assign + elementwise.py:143 (Ops.MUL)
#   tensor.py:537  __itruediv__    assign + elementwise.py div (Ops.FDIV)
#   tensor.py:538  __ifloordiv__   assign + elementwise.py floordiv
#   tensor.py:539  __ipow__        assign + elementwise.py pow (Ops.POW)
#   tensor.py:540  __iand__        assign + elementwise.py:171 (Ops.AND)
#   tensor.py:541  __ior__         assign + elementwise.py:185 (Ops.OR)
#   tensor.py:542  __ixor__        assign + elementwise.py:200 (Ops.XOR)
#   tensor.py:543  __ilshift__     assign + elementwise.py:353 (Ops.SHL)
#   tensor.py:544  __irshift__     assign + elementwise.py:364 (Ops.SHR)
#   tensor.py:545  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
#   tensor.py:549  __eq__          elementwise.py eq (Ops.CMPEQ)
#
# The `Ops` each names is the whole of the port that is tensor.py's, and it is here as a table
# rather than as twelve defs because twelve defs that each call a `TODO` wall would be twelve
# lines that say the same thing. `_binop` (elementwise.py:36) is `lhs, rhs = self._broadcasted(x,
# reverse); return lhs.alu(op, rhs)`, and fold.bend already has `least_upper_dtypes` and
# `bcast_shape`, so the ONE line that is missing is `_broadcast_to` (mixin/movement.py:128) --
# which is why the `__i*__` are not ported even though `alu` is.
#
# THE `__i*__` BLOCKER, and it is the same for all eleven: in-place mutation, and Bend has no
# such form. The operator is fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs
# a mutable target. Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So
# Python's `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:534  __iadd__        assign + elementwise.py:101 (Ops.ADD) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:535  __isub__        assign + elementwise.py sub (Ops.SUB) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:536  __imul__        assign + elementwise.py:143 (Ops.MUL) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:537  __itruediv__    assign + elementwise.py div (Ops.FDIV) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:538  __ifloordiv__   assign + elementwise.py floordiv -- the `__i*__` blocker above.
# TODO(p3) tensor.py:539  __ipow__        assign + elementwise.py pow (Ops.POW) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:540  __iand__        assign + elementwise.py:171 (Ops.AND) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:541  __ior__         assign + elementwise.py:185 (Ops.OR) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:542  __ixor__        assign + elementwise.py:200 (Ops.XOR) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:543  __ilshift__     assign + elementwise.py:353 (Ops.SHL) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:544  __irshift__     assign + elementwise.py:364 (Ops.SHR) -- the `__i*__` blocker above.
# TODO(p3) tensor.py:545  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
# TODO(p3) tensor.py:549  __eq__          elementwise.py eq (Ops.CMPEQ)
#   -- blocked. `==` is the TYPE comparison in BEND, not a value one: bend guide:632 --
#   "Equality of values is a call, `T.is_eq(a, b)`; `==` is only the type." So `__eq__` has no
#   operator to be, and the port names `T.is_eq` where it needs the comparison. This is NOT the
#   `__i*__` blocker: there the operator exists and the assignment does not; here it is reversed.
#
# THE REALIZE PATH -- tensor.py:167-225, the foreign seam, and the whole of it is three
# `TODO(p3)`s. They are here, in Python's order and with the wall each CALL names, because "the
# realize path is a wall" is only useful if the next reader can see which call in each body is
# the wall.
#
# `linear_with_vars` (tensor.py:167-210), 44 lines, the calls in order:
#   :167 `@rewrite_group(...)`                              P3, WALL 3
#   :171 `graph_rewrite(sink, PatternMatcher([]))`         P3, WALL 3
#   :173 `u.dtype in dtypes.weaks and u.device is not None` PORTED (fold)
#   :176 `{x.base for x in sink.src}`                        PORTED (fold)
#   :178 `x.op in {STAGE, DETACH, CONTIGUOUS_BACKWARD}`      PORTED (op_in)
#   :179 `x.storage_base`                                   P3, ops.py:801
#   :184 `x.replace(src=...)`                                P3, ops.py:310
#   :185 `UOp.new_buffer`                                    WALL 2
#   :186 `u.needs_storage()`                                 P3, ops.py:780
#   :192 `src.is_virtual or src.on_disk() or src.has_buffer_identity()`   P3
#   :194 `contiguous_mops_to_view(None, u, src)`             SCHEDULE
#   :196 `UOp.new_buffer(...).reshape(...).shrink_to(...)`   WALL 2
#   :197 `src.axis`                                          P3, ops.py:718
#   :198 `buf.unshard(src.axis)`                             P3, ops.py:692
#   :204 `graph_rewrite(u.src[0], pm_drop_after)`            P3, WALL 3
#   :207 `UOp.sink(...).substitute(becomes_map, walk=True)`  P3, WALL 3
#   :210 `create_linear_with_vars(sink)`                     SCHEDULE
#
# THE FOUR UPSTREAM WHY-S OF THIS BODY, and none of them is visible in the calls list above:
#   tensor.py:170 -- "weakness ends where storage begins". A WEAK dtype (half, bfloat16, an
#   fp8) has no bytes to store, so `u.device is not None` together with a weak dtype is the
#   refusal "cannot realize a weak dtype; cast to a concrete dtype first".
#   tensor.py:173 -- "The outputs and the ALLOCs beneath their wrappers get bound storage, so
#   all aliases share storage and call dependencies." The consequence is an ALIASING invariant:
#   two tensors that view the same base must land in the same storage, or a write through one
#   would not be seen by the other. That is why it is a SET and not a per-output list.
#   tensor.py:179 -- "Rebuild in dependency order: replacement values already reference the other
#   outputs' storage." The walk is over `sink.toposort()` and the `tensor_map` accumulates
#   REPLACEMENTS, so a node is replaced by a version whose srcs are already the replaced
#   versions. That is why the map is consulted for the srcs (`tensor_map.get(s, s)`) rather
#   than the originals.
#   tensor.py:200 -- "Realized outputs become the storage their AFTER sequenced a store into.
#   Compose with tensor_map before updating Tensors so map values reference final storage." The
#   composition order matters: `becomes_map` is substituted INTO `tensor_map` FIRST, so a map
#   value that mentions another output refers to that output's FINAL storage rather than its
#   pre-drop form.
# TODO(p3) tensor.py:167  linear_with_vars -- SCHEDULE (`create_linear_with_vars`,
# `contiguous_mops_to_view`, `is_store_after`) + WALL 3 + WALL 2 + P3's
# `storage_base`, `needs_storage`, `is_virtual`, `on_disk`, `has_buffer_identity`,
# `max_shard_shape`, `axis`, `replace`, `unshard`.
#
# `schedule_linear` (tensor.py:212-216) is three lines on top of it, so it is the SAME wall and
# not a second one.
# TODO(p3) tensor.py:212  schedule_linear -- `linear_with_vars`, unchanged.
#
# `realize` (tensor.py:219-225) is `to_realize = [x for x in (self,)+lst if
# x.uop.base.needs_storage()]`, then `run_linear`. The filter is P3 (`needs_storage`,
# ops.py:780) and the run is the engine.
# TODO(p3) tensor.py:219  realize -- P3's `needs_storage` and `engine/realize.py`'s
# `run_linear`. The `@disable_gc()` decorator is `contextlib`, a P6 effect, and is not a def.
#
# THE DEVICE HALF. Every one of these is WALL 2, and they are listed rather than left out
# because THE LIST IS THE DELIVERABLE: this is the exact set of tensor.py's methods that a
# Tensor-shaped port cannot have until there is a `Buffer`.
# TODO(p3) tensor.py:38   _fromnp      -- `UOp.new_buffer` + `buffer.allocate`
# TODO(p3) tensor.py:153  as_param     -- `UOp.param_like` is ops.py:1239, P3
# TODO(p3) tensor.py:156  call         -- `UOp.call_with_output` + a `grad_fxn` kwarg
# TODO(p3) tensor.py:159  custom_kernel -- `UOp.custom_kernel`
# TODO(p3) tensor.py:276  _buffer      -- `x.realize().uop.buffer`
# TODO(p3) tensor.py:283  _data        -- `memoryview`
# TODO(p3) tensor.py:287  data         -- WALL 2, and `dtypes.fmt` with it
# TODO(p3) tensor.py:306  tolist       -- WALL 2, and the `_tolist` recursion is a
#                                         nested-forward tree printer, which
#                                         bend2-constraints records as refused
# TODO(p3) tensor.py:328  numpy        -- WALL 2, and numpy is a foreign module
# TODO(p3) tensor.py:344  clone        -- `UOp.clone` is ops.py:882, `empty_like` plus
#                                         `after(store(src.cast))`, so the AFTER/STORE
#                                         spine is ported above and only the
#                                         `empty_like` is missing
# TODO(p3) tensor.py:353  to           -- `canonicalize_device`, `is_disk_device`,
#                                         `empty_like`, `clone`, `copy_to_device`
# TODO(p3) tensor.py:369  to_          -- `to` + `replace`
# TODO(p3) tensor.py:377  shard        -- `UOp.shard` is ops.py:757 and `_resolve_dim`
#                                         is mixin/movement.py. Upstream's own
#                                         comment at tensor.py:366 is the reason the
#                                         CLONE is not optional: "a shard of a load
#                                         from a creation device (disk/npy/python)
#                                         wants the copy to persist, so it inserts a
#                                         clone". A CREATION DEVICE is one that
#                                         materialises on demand -- a file, an
#                                         in-memory blob -- and its contents are
#                                         GONE once the load is consumed, so a
#                                         shard of one has to COPY rather than
#                                         view. `self.uop.on_creation_device()`
#                                         is the test and `UOp.clone` is the copy.
# TODO(p3) tensor.py:395  shard_       -- `shard` + `replace`
# TODO(p3) tensor.py:401  shard_like   -- `shard` + `to`
# TODO(p3) tensor.py:412  from_blob    -- an external pointer
# TODO(p3) tensor.py:426  from_url     -- `helpers.fetch`
# TODO(p3) tensor.py:442  manual_seed  -- class-level mutable state
# TODO(p3) tensor.py:460  _next_counter -- the same, plus slicing and `assign`
# TODO(p3) tensor.py:502  __setitem__  -- `backward_slice`, `is_realized`,
#                                         `_base_buffer_is_realized` and
#                                         mixin/elementwise.py's `_getitem`
# TODO(p3) tensor.py:530  __delitem__  -- `raise TypeError`, and `__bool__`'s wall
# TODO(p3) tensor.py:553  decode_hevc_frame -- `Variable.unbound` and
#                                         `Ops.CUSTOM_FUNCTION`
#
# AND THE METADATA HALF, which is a third thing: tensor.py:567-589 is a `contextvars`-free
# mutable class (`_ContextVar`), a decorator (`_metadata_wrapper`) and a REFLECTION loop that
# wraps every Tensor method with it. Bend has no `setattr`, no `inspect` and no mutable class
# state, and the metadata itself is `all_metadata[new_uop] = (metadata,)` at tensor.py:106.
# TODO(p3) ops.py:208  symbol=all_metadata  -- ops.bend has the READER
#                                             (`O.UOp.metadata`, uop/ops.bend:2748 symbol=UOp.metadata) and no
#                                             writer, because the writer needs a scope
#                                             threaded through `_apply_uop`
#
# THE METADATA LANE -- tensor.py:567-589 AT THE PIN. The port's three markers named 570, 578 and
# 588, and all three are two lines late: the function names are all right and the line numbers
# are not. The pin's lines, in full:
#
#   567  # this tracks the tensor.py METADATA, contextvars.ContextVar was
#   568  class _ContextVar(Generic[T]):
#   569    def __init__(self, default:T): self.state:T = default
#   570    def get(self) -> T: return self.state
#   571    def set(self, x:T) -> T:
#   572      ret, self.state = self.state, x
#   573      return ret
#   574  _METADATA: _ContextVar[Metadata|None] = _ContextVar(default=None)
#   576  def _metadata_wrapper(fn: Callable[P, T]) -> Callable[P, T]:
#   577    def _wrapper(*args: P.args, kwargs: P.kwargs) -> T:
#   578      if TRACEMETA < 1 or _METADATA.get() is not None: return fn(*args, kwargs)
#   579      token = _METADATA.set(Metadata(name=fn.__name__))
#   580      with cpu_profile(TracingKey(fn.__name__), "USER"):
#   581        ret = fn(*args, **kwargs)
#   582      _METADATA.set(token)
#   583      return ret
#   584    return _wrapper
#   586  if TRACEMETA >= 1:
#   587    for name, fn in inspect.getmembers(Tensor, inspect.isfunction):
#   588      if name in ["__class__", "__del__", "__init__", "__new__", "__repr__", "backward", "sequential", "gradient"]: continue
#   589      setattr(Tensor, name, functools.wraps(fn)(_metadata_wrapper(fn)))
#
# SO: `570` is the pin's `def get`, and the CLASS is at 568; `578` is the pin's guard, and the
# DEF is at 576; `588` is the pin's skip test, and the loop's HEAD is at 586. The drift is the
# SAME +2 for all three, so this block was written against a tensor.py TWO LINES SHORTER above 568.
#
# WHAT IS PORTABLE, and what the port gives up:
#
#   * THE CELL (`_ContextVar`) is a MUTABLE class with ONE field. Bend has no mutable class
#     state, so the port's cell is a VALUE -- WALL 1's idiom applied to a module global.
#     Upstream's `set` RETURNS THE OLD STATE, and that return is the TOKEN the wrapper restores,
#     so the port's `set` returns it too: THE PAIR IS (NEXT, OLD).
#   * THE WRAPPER (`_metadata_wrapper`) is a CLOSURE: it RETURNS a def. Bend has no function
#     values, so the port's wrapper is the SCOPE and the CALL is the caller's. Everything the
#     wrapper DECIDES -- the guard, the install, the token, the restore -- is here.
#   * THE LOOP (586-589) is a REFLECTION: `inspect.getmembers` plus `setattr` on the class. Bend
#     has neither, so the LOOP is not portable and its CONTENT is: the list of methods the loop
#     SKIPS. That list is not decoration -- `__init__` is in it, and that is why a plain
#     `Tensor(5)` carries NO metadata while a tensor built by `alu` carries `alu`.
#
# THE DIVERGENCE THAT MATTERS, and it is the one the edge rows are about: upstream's cell is ONE
# MODULE GLOBAL, so the metadata of one call IS the metadata another call sees. The port's cell is
# a VALUE, so two lanes are two cells and one lane's state CANNOT leak into another's.
#
# and the state is absent or it is a `Metadata`, and there is no third thing. Upstream's cell
# holds `Metadata|None` and `None` IS its default, so "never set" and "explicitly set to None"
# are the SAME state -- a port that told them apart would DIVERGE. And an EMPTY NAME is a SET
# state, not an absent one: `tn_meta_enter_empty` is the row that says so."""),
]

apply(F, EDITS)
