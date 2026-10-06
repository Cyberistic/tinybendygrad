# function.bend -- tinygrad/function.py:113. The `@function` decorator: the
# implicit-input capture that turns a traced graph into a CALL, and the two
# refusals that guard it.
#
# ---------------------------------------------------------------------------
# THE BRIEF DESCRIBES A DIFFERENT FILE, and that is the first thing to say.
#
# The unit was specified as `tinygrad/function.py:113` -- and the file at that
# path IS 113 lines, so the name and the line count are right -- but the
# description given with it ("the `total_nan_replace` rewrite", "`JitMatchError`",
# "`argx`-style input spec handling", "`TinyJit.__call__` with its `input_spec`
# matching, `count`, `misc`, `vars`") names the OLD `engine/jit.py`. Measured:
#     rg -n "JitMatchError|total_nan_replace|assigned_vars" tinygrad/  -> no hits
#     rg -n "class TinyJit" tinygrad/                                 -> engine/jit.py
# and `tinygrad/engine/jit.py` in THIS checkout has none of those names either:
# its match is `self.captured.expected_input_info != expected_input_info`, its
# counter is `self.cnt`, and it raises `JitError`, not `JitMatchError`.
#
# So this file ports what `function.py` actually contains and says so in the
# gate, rather than inventing rows for a `TinyJit` that is not here. What
# survives of the brief's gate plan is the METHOD, applied to the predicates this
# file really has: `is_implicit_storage` is a pure refusal predicate over
# (op, slot, bind_on_realize, alloc_start) and is gated cell by cell against
# CPython; `add_to_ctx` and the `allow_implicit` message are gated beside
# CPython's exact strings; and the node-count gate carries op AND src-op
# SEQUENCE in one string, because a gate with a count and a root op is
# measurably blind to swapped operands (see `pctx_swapped` and mutation M7).
#
# ---------------------------------------------------------------------------
# WHAT IS PORTED, AND THAT IS THE WHOLE LIST:
#
#   function.py:9-13    `add_to_ctx`               the capture, and its refusal
#   function.py:15-17   `is_implicit_storage`      the predicate, in full
#   function.py:19-25   `pm_ctx`                   two rules, as a `Data` table
#   function.py:27-31   `invalid_outputs`          the STORE filter, in full
#   function.py:33-36   `renumber_invalid_outputs` the NUMBERING, in full
#   function.py:41-48   `_function.__init__/__get__`   the four flags, the depth
#   function.py:50-98   `_function.__call__`       every PORTED branch; see Section H
#   function.py:101-113 `function` + two overloads both decorator spellings
#
# WHAT IS A SEAM, with the owner and the Python line, at Section I:
#   `UOp.param_like`  ops.py:1239       `UOp.substitute`  ops.py:532
#   `UOp.call_with_outputs` ops.py:1272  `UOp.replace`     ops.py:245
#   `get_state_dict((args, kwargs))`     `Context(...)`    `time.perf_counter`
#   `self.fxn(*args, **kwargs)`          `__get__`         `functools.partial`
#
# ---------------------------------------------------------------------------
# THE LAZY BEHAVIOUR, STATED HONESTLY, because the brief asked for it and the
# two answers are not the same.
#
# `TinyJit`'s laziness lives in `engine/jit.py`, not here: `cnt` 0 is the eager
# pass, `cnt == 1` is the capture, `cnt >= 2` replays. WHAT IS LAZY HERE IS THE
# CAPTURE ITSELF, and it is lazy in a way that needs no counter at all -- it
# needs a REFUSAL. `pm_ctx` fires only on nodes the traced body did not name, so
# a graph with no caller-owned storage produces no capture and the CALL's input
# list is exactly the argument list. The port expresses that as a `Bool` per node
# (`Fired.ok`), not as a mode.
#
# A CAPTURED VARIABLE BECOMES A `Data` FIELD, and this is forced. Python's
# rewrite rule is a closure over `ctx` and does `ctx[0].append(x)` -- it MUTATES
# a list it captured. A `Data` record can be shared across functions but its
# PARAMETER is still read-at-most-once, and `+` cannot be spelled on a `Maybe`
# or on a pattern binder, so a rule that both appends and answers a `Maybe` node
# is not writable. So `FnCtx` carries the list, `Fired` carries the flag and the
# GROWN ctx together, and the rewrite is a fold:
#
#     fn_scan(xs, ar, c)  ==  for x in xs: fired = fn_rule(x, ar, c); if fired.ok: c = fired.ctx
#
# which is the shape every port in this tree uses for "a fold that must answer
# both a thing and a fact about it" (`Dts{some, meet, result}` in `weak.bend`,
# `Marg{o, n}` in `movement.bend`). It is not a workaround for a missing
# feature; it is what a node-indexed fold with no mutable local has to be.
#
# A SPEC MISMATCH BECOMES A TYPED REFUSAL RATHER THAN AN EXCEPTION, and this
# file has exactly one such thing and it is NOT a spec match. `TinyJit` has the
# spec match. `function.py` has two refusals and both are ANSWERABLE IN THE
# PURE DOMAIN, so both are values here rather than failures:
#
#   * an un-tensor return is `FnRet{kind, n}` -- a three-valued answer with no
#     error channel, because the third case is not an error in this port, it is a
#     fact about the return that `fn_ret_msg` then SPELLS.
#   * the implicit-buffer refusal is `fn_implicit_msg`, which BUILDS CPython's
#     exact `RuntimeError` text and returns it as a `String`. A gate row that
#     builds the message and compares it byte for byte is a stronger test than a
#     gate row that raises, because it also pins the ORDERING of the numbered
#     lines -- and the ordering is the part `enumerate` gets wrong first.
#
# And the third refusal -- the one that IS a spec mismatch, `x.buf_uop in
# ctx[1]` -- is the most load-bearing line in the file and it is not obvious
# from the code: `ctx[1]` is `invalid_outputs(uret)` (function.py:80), the set
# of FRESH WRITE-ONLY SCRATCH buffers, NOT the set of already-captured buffers.
# So `add_to_ctx` does NOT deduplicate. Measured in CPython:
#     add_to_ctx(ctx, b) -> PARAM slot 0, ctx[0] = [BUFFER]
#     add_to_ctx(ctx, b) -> PARAM slot 1, ctx[0] = [BUFFER, BUFFER]
# Rows `add_again`, `add_len` and `add_refused` exist to make that
# unmissable, and mutation M1 is the one that would turn it back into the
# reading a reader assumes.
import Base
import ./helpers.bend as H
import ./LAWS/spec.bend as S
import ./uop/ops.bend as O
import ./uop/fold.bend as F
import ./tensor.bend as T
import ./mixin/movement.bend as MX

# ===========================================================================
# SECTION 0 -- THE NODE HANDLE. Every def below that needs a node more than once
# in ONE EXPRESSION takes an `O.Found` rather than `(arena, index)`, and this is
# the whole reason.
#
# A `U32` is affine and `+` is REFUSED on it (measured: `device.bend` rule 3,
# `codegen/opt` rule 10.3), so `0 < a <= b` is unwritable as written and so is
# `op(ar, u)` next to `arg(ar, u)` next to `shape(ar, u)`. `O.Found` IS
# `(Arena & U32)`, its two readers are NON-CONSUMING (measured: `divandmod.bend`
# section 4 -- "three reads of one `+Found` check"), and `Found` is `Data`, so
# `+f: O.Found` is a refcount and not a copy. Every `(ar, u)` pair in this file
# is therefore an `O.Found`, which is also what the rest of the tree threads.
def fn_u(+f: O.Found) -> U32:
  O.Found.i(f)

def fn_op(+f: O.Found) -> O.Op:
  O.Arena.op(O.Found.ar(f), O.Found.i(f))

def fn_arg(+f: O.Found) -> O.Arg:
  O.Arena.arg(O.Found.ar(f), O.Found.i(f))

def fn_srcs(+f: O.Found) -> List<&2, U32>:
  O.Arena.srcs(O.Found.ar(f), O.Found.i(f))

def fn_src0(+f: O.Found) -> U32:
  O.Arena.src0(O.Found.ar(f), O.Found.i(f))

def fn_nsrc(+f: O.Found) -> U32:
  O.Arena.nsrc(O.Found.ar(f), O.Found.i(f))

def fn_src(+f: O.Found, n: U32) -> U32:
  O.Arena.src(O.Found.ar(f), O.Found.i(f), n)

# ===========================================================================
# SECTION A -- `is_implicit_storage` (function.py:15-17) and the readers it
# needs. This is the file's only PURE predicate and it is ported in full.
#
#     return (x.is_variable and x.arg.slot == -1) or x.op is Ops.BUFFER or \
#            (x.op is Ops.ALLOC and x.arg.bind_on_realize and x.arg.slot < ctx[2])
#
# with Python's own comment kept above it:
#     # Variables are caller-provided values (slot -1); positional scalar params
#     # (slot >= 0) are already captured
#
# `-1` IS `4294967295` IN A `U32`, and the ROW NAMES say so, because a gate that
# prints `0` next to a comment saying `-1` is a gate that needs mental
# arithmetic to read. The VALUE is `O.ParamArg.no_slot()`, named once in the file
# that owns the field; this is the local spelling `function.py` code reads best
# against, kept because renaming the call sites is churn with no gate value.
def FN_NEG1() -> U32: O.ParamArg.no_slot()

# `x.arg.slot`. `ParamArg` always HAS a slot, so this is a two-arm read, and the
# non-ParamArg arm answers `FN_NEG1()` -- the same value a node with no slot at
# all gets. That is deliberate and it is not a weakening: `is_variable` already
# requires `isinstance(self.arg, ParamArg)`, so the two agree wherever the
# predicate can be True.
def fn_slot.of(arg: O.Arg) -> U32:
  match arg:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: FN_NEG1()

# `arg.bind_on_realize` -- the ALLOC conjunct's middle term.
def fn_bor.of(arg: O.Arg) -> Bool:
  match arg:
    case O.AParam{pa}: O.ParamArg.bind_on_realize(pa)
    case _: False{}

def fn_slot(+f: O.Found) -> U32:
  fn_slot.of(fn_arg(f))

# `_shape == ()` -- the last conjunct of `UOp.is_variable` (ops.py:1018), and the
# only one that needs the fold. An UNANSWERED node is not a scalar, which is the
# honest answer and not a hole: `List.is_empty` on the fold's answer is total.
def fn_scalar.of(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{ds}: List.is_empty(&2, O.Sint, ds)
    case None{}: False{}

def fn_bor(+f: O.Found) -> Bool:
  fn_bor.of(fn_arg(f))

# `arg.vmin_vmax is not None`. `case Some{}` IS REFUSED (a one-field pattern must
# name its binder), so this is a `Maybe` MATCH whose ANSWER is a `Bool` -- the
# answer has to be a `Bool` because `Maybe` is a `Type` and cannot be a `Data`
# field. The `_` arm is the one that matters: `None` means no value range, and
# that is the negative row `iis_var_novmin`.
def fn_has_vv.lo(r: O.PyRange) -> Bool:
  match r:
    case O.PyRange{+lo, hi}: Bool.or(U32.is_zero(H.lo32(lo)), Bool.not(U32.is_zero(H.lo32(lo))))

def fn_scalar(+f: O.Found) -> Bool:
  fn_scalar.of(T.tn_dims(T.tn_new(O.Found.ar(f), O.Found.i(f))))

# the `+lo` above is `device.bend` rule 3: a `U32` read twice in ONE expression
# takes the `+` on the pattern BINDER, because a `+` cannot be spelled on a
# `U32` parameter.
def fn_has_vv.of(m: Maybe<&2, O.PyRange>) -> Bool:
  match m:
    case Some{+r}: fn_has_vv.lo(r)
    case _: False{}

def fn_alu.of(a: S.Addr) -> Bool:
  match a:
    case S.Aalu{}: True{}
    case _: False{}
def fn_alu(pa: O.ParamArg) -> Bool:
  fn_alu.of(O.ParamArg.addrspace(pa))


def fn_has_vv(pa: O.ParamArg) -> Bool:
  fn_has_vv.of(O.ParamArg.vmin_vmax(pa))

# `UOp.is_variable` -- ops.py:1018, in full:
#     return self.op is Ops.PARAM and isinstance(self.arg, ParamArg) and \
#            self.arg.vmin_vmax is not None and self.arg.addrspace is AddrSpace.ALU \
#            and self._shape == ()
# The two-scrutinee match is rule 5 of the eleven: a `match` kills every name
# bound earlier in the same body, so the op and the arg are read TOGETHER or not
# at all.
def fn_isvar.pa(+pa: O.ParamArg, zero: Bool) -> Bool:
  Bool.and(fn_has_vv(pa), Bool.and(zero, fn_alu(pa)))

def fn_isvar.of(+op: O.Op, arg: O.Arg, zero: Bool) -> Bool:
  match op arg:
    case O.OpsPARAM{} O.AParam{pa}: fn_isvar.pa(pa, zero)
    case _ _: False{}

# THE PREDICATE. Three disjuncts, Python's order. `fn_buf`'s walk is NOT one of
# them: `is_implicit_storage` looks at the node itself.
def fn_isvar(+f: O.Found) -> Bool:
  fn_isvar.of(fn_op(f), fn_arg(f), fn_scalar(f))
def fn_implicit.var(+f: O.Found) -> Bool:
  Bool.and(fn_isvar(f), U32.is_eq(fn_slot(f), FN_NEG1()))


def fn_implicit.alloc(+f: O.Found, start: U32) -> Bool:
  Bool.and(O.eq_op(fn_op(f), O.OpsALLOC{}),
           Bool.and(fn_bor(f), U32.is_lt(fn_slot(f), start)))

def fn_implicit(+f: O.Found, start: U32) -> Bool:
  Bool.or(fn_implicit.var(f),
          Bool.or(O.eq_op(fn_op(f), O.OpsBUFFER{}), fn_implicit.alloc(f, start)))

# ===========================================================================
# SECTION B -- `UOp.buf_uop` (ops.py:925). `ops.bend` carries it as
# `# TODO(p3) ops.py:925  def buf_uop`, and it is not optional here: it is the
# identity `add_to_ctx` refuses on and the value `invalid_outputs` collects. It
# is ported locally and the owner is named above, which is what `mixin/rand.bend`
# does for `op_pad`/`op_shr`.
#
#     def buf_uop(self):
#       if self.op in {Ops.BUFFER, Ops.ALLOC, Ops.PARAM}: return self
#       if self.op is Ops.MSELECT: ...            # multi-device, P6
#       if self.op is Ops.MSTACK:  ...            # multi-device, P6
#       if self.base.op is Ops.AFTER: return self.base.src[0].buf_uop.base
#       s = self
#       while len(s.src) and s.op not in {BUFFER, ALLOC, PARAM, STAGE, MSTACK}: s = s.src[0]
#       return s
#
# TWO ARMS ARE OMITTED and both are the SAME wall: the multi-device cluster.
# `MSELECT` needs `mselect` and `MSTACK` needs a per-shard `buf_uop` list, and
# neither op is reachable from a `@function` body until the multi-device
# allocator exists. Marked at Section I.
def fn_buf_stop(+op: O.Op, has_src: Bool) -> Bool:
  Bool.or(Bool.not(has_src),
          Bool.or(O.eq_op(op, O.OpsBUFFER{}),
                  Bool.or(O.eq_op(op, O.OpsALLOC{}),
                          Bool.or(O.eq_op(op, O.OpsPARAM{}), O.eq_op(op, O.OpsSTAGE{})))))

# The walk. `while len(s.src) and s.op not in {...}: s = s.src[0]` -- so the STOP
# test is the ONE `match` and the descent is a self-call whose shrinking
# argument is the LIST, which is why `xs` is the first parameter (measured:
# `sz.bend`'s `sz.rows(rest, acc)`; a self-call may not pass a computed argument
# in front of the shrinking one).
#
# `self.base.op is Ops.AFTER` -> `self.base.src[0].buf_uop.base` is THE SAME
# walk with no extra guard, and that is not a shortcut: for every node `buf_uop`
# can ANSWER (BUFFER/ALLOC/PARAM/STAGE, none of which is a movement op and none
# is a DETACH) `fold.bend`'s `base_of.steps` returns the node ITSELF, so an
# AFTER's base IS the AFTER and `.base` is the identity. It is also what makes
# `fn_realized` below a faithful reading rather than a weakening.
def fn_buf.go(xs: List<&2, U32>, +ar: O.Arena, u: U32) -> U32:
  match xs:
    case Nil{}: u
    case _ <> t: fn_buf.go(t, ar, O.Arena.src0(ar, u))

def fn_buf.pick(stop: Bool, me: U32, walked: U32) -> U32:
  Bool.pick(U32, stop, me, walked)

# `u` would be read TWICE -- once in the `Bool.pick`'s true arm and once in the
# self-call -- and a `U32` cannot be read twice in one expression. So the node
# travels as an `O.Found` and the two reads are `fn_u(g)`, which is legal on a
# `+` record. This is the same split `divandmod.bend` rule 1 asks for, reached
# from the affinity side rather than the scrutinee side.
def fn_buf.node(+op: O.Op, +src: List<&2, U32>, +g: O.Found) -> U32:
  fn_buf.pick(fn_buf_stop(op, List.is_empty(&2, U32, src)), fn_u(g),
              fn_buf.go(src, O.Found.ar(g), fn_u(g)))

def fn_buf(+f: O.Found) -> U32:
  fn_buf.node(fn_op(f), fn_srcs(f), f)

# ===========================================================================
# SECTION C -- `add_to_ctx` (function.py:9-13).
#
#     def add_to_ctx(ctx, x:UOp):
#       if x.buf_uop in ctx[1]: return None
#       ret = x.param_like(len(ctx[0]))
#       ctx[0].append(x)
#       return ret
#
# `ctx` IS `(call_uops, invalid_outputs(uret), alloc_start)` (function.py:80), so
#     * `ctx[0]` is a list that GROWS under the rewrite,
#     * `ctx[1]` is a SET OF INVALID BUFFERS, and it is NOT the captured set,
#     * `ctx[2]` is `UOp.unique_num` at entry, i.e. `Arena.next` at that moment.
# `added` and `slot` are the answer of the LAST call, which is how a record
# carries a fact and a value together (no `Maybe` field, no sentinel).
type FnCtx is Data:
  FnCtx{us: List<&2, U32>, inv: List<&2, U32>, start: U32, added: Bool, slot: U32}

# `x.buf_uop in ctx[1]`. This is `List.contains`, NOT a local fold: Bend's `Map`
# is string-keyed and a UOp is a `U32`, and `H.dedup_u32` already spells the
# membership the same way. Writing a local one cost three defs and refused twice
# on the way -- `x` is a `U32` read twice in one expression -- which is the
# "reimplements something base.bend already provides" reviewer rejection, caught
# by the compiler instead of by a reviewer.

def fn_ctx_n(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))


def FnCtx.of2(start: U32) -> FnCtx:
  FnCtx{Nil{}, Nil{}, start, False{}, 0}

def FnCtx.us(+c: FnCtx) -> List<&2, U32>:
  match c:
    case FnCtx{us, inv, start, added, slot}: us


def FnCtx.start(+c: FnCtx) -> U32:
  match c:
    case FnCtx{us, inv, start, added, slot}: start

def FnCtx.added(+c: FnCtx) -> Bool:
  match c:
    case FnCtx{us, inv, start, added, slot}: added

def FnCtx.slot(+c: FnCtx) -> U32:
  match c:
    case FnCtx{us, inv, start, added, slot}: slot

# EVERY `FnCtx` writer is a `.of` taking the BOUND FIELDS, and every field is
# used once. A writer that re-reads the record (`FnCtx.n(c)` inside the arm that
# destructures `c`) is refused: `c` is consumed by the pattern and the binder it
# would have been read through is a `U32` read twice. Five `.of` defs is the
# price and it buys a record that can be read from anywhere.
def FnCtx.n(+c: FnCtx) -> U32:
  match c:
    case FnCtx{us, inv, start, added, slot}: fn_ctx_n(us)

def FnCtx.hold.of(us: List<&2, U32>, inv: List<&2, U32>, start: U32, slot: U32) -> FnCtx:
  FnCtx{us, inv, start, True{}, slot}

def FnCtx.hold(+c: FnCtx, slot: U32) -> FnCtx:
  match c:
    case FnCtx{us, inv, start, added, slot0}: FnCtx.hold.of(us, inv, start, slot)

# ONE BUILDER, because the two arms differ ONLY in `added`: the slot is
# `len(ctx[0])` on both, and `ctx[0]` does not grow on the refusal arm (CPython
# returns `None` and appends nothing, which is the PAIR of rows `add_refused`
# and `add_ref_len`). That is a fact about the code rather than a simplification,
# and the row `add_ref_slot` is the one that would see it change.
#
# The capture arm is `x.param_like(len(ctx[0]))`, a SEAM (tinygrad/function.py:11), so the
# SLOT is what the port answers and the NODE is `TODO(p3)`; the slot is the whole
# of what the gate can check, and `param_like`'s own behaviour (an ALU PARAM keeps
# its shape and drops name/val) is ops.bend's business, not this file's.
# `ctx[0].append(x)` -- and it APPENDS. `List.append(acc, [x])` is `acc ++ [x]`
# (measured: `schedule/memory.py` section A), which is the right end here because
# the slot an appended node gets is `len(ctx[0])`: the list's ORDER IS THE SLOT
# NUMBERING. A prepend would be a correct set and a wrong port. The first version
# of this def built the record without the append at all, and every `add_*` row
# read 0 -- which is the silent half of the arena/slot family.
# `hit` IS THE REFUSAL, so the append is the FALSE arm -- and `Bool.pick(-A, c, a,
# b)` answers `a` when `c` is TRUE, so writing it the other way round appends on
# exactly the nodes `add_to_ctx` must NOT capture. It was written that way first
# and `add_first` read `0 0 0` while `add_ref_len` read 1: the two rows together
# named the inversion, which is the argument for having a NEGATIVE row per
# predicate rather than only a positive one.
def fn_add.grow(+hit: Bool, +us: List<&2, U32>, x: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, hit, us, List.append(&2, U32, us, [x]))

def fn_add.make.of(+hit: Bool, +us: List<&2, U32>, +inv: List<&2, U32>, start: U32, x: U32) -> FnCtx:
  FnCtx{fn_add.grow(hit, us, x), inv, start, Bool.not(hit), fn_ctx_n(us)}

# `fn_add` is a `Bool.pick` over the two arms and both arms rebuild the record, so
# the fields travel as PARAMETERS instead of being read back off `c`. `c` is
# consumed by the destructuring `match`, `start` is a `U32` the second read would
# duplicate, and `ar`/`x` are read once each -- the affinity half of
# `divandmod.bend` rule 1.
# the node travels as an `O.Found` because `x` is a `U32` read twice -- once to
# test `x.buf_uop in ctx[1]` and once to append -- and `+` is refused on a `U32`.
def fn_add.of(+ar: O.Arena, +us: List<&2, U32>, +inv: List<&2, U32>, start: U32, +g: O.Found) -> FnCtx:
  fn_add.make.of(List.contains(U32, U32.is_eq, inv, fn_buf(g)), us, inv, start, fn_u(g))

def fn_add.of2(+ar: O.Arena, +us: List<&2, U32>, +inv: List<&2, U32>, start: U32, x: U32) -> FnCtx:
  fn_add.of(ar, us, inv, start, O.Found{ar, x})

def fn_add(+ar: O.Arena, +c: FnCtx, x: U32) -> FnCtx:
  match c:
    case FnCtx{us, inv, start, added, slot}: fn_add.of2(ar, us, inv, start, x)

# ===========================================================================
# SECTION D -- `UOp.is_realized` (ops.py:1008), read through `buf_uop`.
#
#     return self.base.realized is not None
#
# and this is a FAITHFUL reading, not a shortcut, and the argument is one line:
# `buf_uop` answers only BUFFER/ALLOC/PARAM/STAGE (and MSTACK, omitted), and
# `fold.bend`'s `base_of.steps` returns the node ITSELF for all four, because
# none of them is a movement op and none is a DETACH. So for a node `buf_uop`
# names, `base` is that node, `realized` is `arg.buffer`, and `ParamArg.buffer` is
# exactly that field.
# `buffer` is a `Maybe<&2, U32>` and `+` cannot be spelled on a `Maybe`, so the
# always-True arm reads the payload through a `+` BINDER (measured: `weak.bend`
# rule 2). `U32.is_zero(b) or not` is total, so this names no sentinel.
def fn_realized.buf(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{+b}: Bool.or(U32.is_zero(b), Bool.not(U32.is_zero(b)))
    case _: False{}

def fn_realized.pa(pa: O.ParamArg) -> Bool:
  fn_realized.buf(O.ParamArg.buffer(pa))

def fn_realized.of(arg: O.Arg) -> Bool:
  match arg:
    case O.AParam{pa}: fn_realized.pa(pa)
    case _: False{}

# ===========================================================================
# SECTION E -- `invalid_outputs` (function.py:27-31) and
# `renumber_invalid_outputs` (function.py:33-36).
#
#     # invalids() returns fresh write-only scratch: a clone storing CONST(Invalid)
#     # don't capture it as an input; only skip fresh buffers, not realized ones
#     return {u.src[0].buf_uop for u in uret.backward_slice_with_self
#             if u.op is Ops.STORE and u.src[1].base.is_invalid and not u.src[0].buf_uop.is_realized}
#
# `backward_slice_with_self` is `{self, **backward_slice}` (ops.py:284) and
# `backward_slice` is `toposort(enter_calls=False)` minus self (ops.py:278), so
# the pair is EXACTLY the toposort. That is why `fn_bslice` exists, and the
# difference between the two walks is exactly one node -- which is what rows
# `bs_self` and `bs_nself` pin, and it is the only thing that can see a rule
# written over the wrong one of the two.
# THE FILTER IS THREE DEFS AND ONE RECORD, and the record is the whole answer.
# `h` is read TWICE in the step -- once in `U32.is_eq(h, self)` and once in the
# `h <> acc` prepend -- and a `U32` read twice in one expression is UNWRITABLE,
# and `self` is read both in the step and in the self-call. So both travel in a
# `Data` record, the step takes `+` on all THREE pattern binders (the documented
# spelling for "two reads in one expression": `device.bend` rule 3,
# `renderer/cstyle.bend` rule 4), and the walk carries the record so `self` is
# read from ONE place. `acc` is a `List` and DOES take `+` on a parameter even
# though it is `Type`-kinded.
type BsSt is Data:
  BsSt{h: U32, self: U32, acc: List<&2, U32>}

def fn_realized(+f: O.Found) -> Bool:
  fn_realized.of(fn_arg(f))

def BsSt.self(s: BsSt) -> U32:
  match s:
    case BsSt{h, self, acc}: self

def BsSt.acc(s: BsSt) -> List<&2, U32>:
  match s:
    case BsSt{h, self, acc}: acc

def fn_bslice.of(s: BsSt) -> BsSt:
  match s:
    case BsSt{+h, +self, +acc}: BsSt{h, self, Bool.pick(List<&2, U32>, U32.is_eq(h, self), acc, h <> acc)}

def fn_bslice.go(xs: List<&2, U32>, +s: BsSt) -> List<&2, U32>:
  match xs:
    case Nil{}: BsSt.acc(s)
    case h <> t: fn_bslice.go(t, fn_bslice.of(BsSt{h, BsSt.self(s), BsSt.acc(s)}))

def fn_bslice.of2(+f: O.Found) -> List<&2, U32>:
  fn_bslice.go(O.UOp.toposort_nocalls(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)),
               BsSt{O.Found.i(f), O.Found.i(f), Nil{}})

def fn_bslice(+f: O.Found) -> List<&2, U32>:
  fn_bslice.of2(f)

# `u.src[1].base.is_invalid`. `F.fold.base` answers `Maybe<&1, U32>` and
# `F.is_invalid` reads the node's OWN arg, so the base index goes through a `.of`
# (a `match` may not scrutinise a call) and an UNANSWERED base is not invalid --
# `None` is the honest answer, and `inv_unknown` is the row that would see it.
def fn_valinv.put(+ar: O.Arena, b: U32) -> Bool:
  F.is_invalid(ar, b)

def fn_valinv.of(m: Maybe<&1, U32>, +ar: O.Arena) -> Bool:
  match m:
    case Some{+b}: fn_valinv.put(ar, b)
    case _: False{}

# `F.fold.base` wants the `Table` out of the `Folded`, so the fold is taken ONCE
# and its table is read once. `fn_valinv` reads no node and mints none, so a
# `+fx` here is sound -- the `+`-on-a-`Folded` staleness rule in
# `mixin/rand.bend` applies to defs that BUILD, and this one does not.
def fn_valinv.of2(+fx: F.Folded, +ar: O.Arena, u: U32) -> Bool:
  fn_valinv.of(F.fold.base(ar, F.Folded.t(fx), u), ar)

def fn_valinv(+f: O.Found) -> Bool:
  fn_valinv.of2(F.folded(O.Found.ar(f)), O.Found.ar(f), fn_src(f, 1))

def fn_isstore.of(+op: O.Op, n: U32) -> Bool:
  Bool.and(O.eq_op(op, O.OpsSTORE{}), U32.is_ge(n, 2))

# the three conjuncts are read into their own `Bool`s because a `match` may not
# scrutinise a call and `Bool.and` is not short-circuiting -- so all three run,
# and each one is a total read.
def fn_store_hit.buf(+f: O.Found) -> Bool:
  fn_realized(O.Found{O.Found.ar(f), fn_buf(O.Found{O.Found.ar(f), fn_src0(f)})})

def fn_isstore(+f: O.Found) -> Bool:
  fn_isstore.of(fn_op(f), fn_nsrc(f))

def fn_store_hit.go(store: Bool, inval: Bool, real: Bool) -> Bool:
  Bool.and(store, Bool.and(inval, Bool.not(real)))

def fn_store_hit(+f: O.Found) -> Bool:
  fn_store_hit.go(fn_isstore(f), fn_valinv(f), fn_store_hit.buf(f))

# `fn_inv_go` is a `List`-tail fold whose accumulator is a `List`, and
# `List.append(acc, [x])` APPENDS (measured: `schedule/memory.py` section A), so
# the answer is in toposort order -- which is the order `renumber` needs.
# The node travels as an `O.Found` rather than as an index because `u` is a
# `U32` read twice in `fn_inv_put` (once to test the STORE conjunct and once to
# emit `src[0].buf_uop`) and `+` is refused on a `U32`.
def fn_inv_ins(+ar: O.Arena, +g: O.Found, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [fn_buf(O.Found{O.Found.ar(g), fn_src0(g)})])

def fn_inv_put(+ar: O.Arena, +g: O.Found, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, fn_store_hit(g), fn_inv_ins(ar, g, acc), acc)

def fn_inv_go(xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case u <> t: fn_inv_go(t, ar, fn_inv_put(ar, O.Found{ar, u}, acc))

def fn_invalid(+f: O.Found) -> List<&2, U32>:
  fn_inv_go(O.UOp.toposort_nocalls(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)),
            O.Found.ar(f), Nil{})

# `enumerate(x for x in uret.toposort(enter_calls=False) if x in invalid)` -- the
# NUMBERING, which is all of `renumber_invalid_outputs` that is pure. `i` counts
# the invalid buffers in TOPOSORT order, and the substitution itself is a SEAM
# (`UOp.substitute` IS `graph_rewrite`, ops.py:532). `n` is INCREMENTED for every
# node, which is a real difference from a counter over the invalid ones only and
# row `renum_one` is what separates them: on a graph whose toposort is
# [src0, STORE] the two spellings answer 0 and 0, and on
# [src0, src1, STORE] they answer 0 and 1.
# THE COUNTER, THE MEMBERSHIP TEST AND THE PREPEND ALL TOUCH `n`, AND `n` IS A
# `U32`. So the walk's state is a `Data` record, the emit takes `+` on all three
# pattern binders, and the pick takes the flag as a PARAMETER rather than
# computing it beside the `n` it tests. This is the "a fold that must answer
# both a thing and a fact about it rides in the STATE" shape from
# `mixin/rand.bend`, and it is the only reason `renumber_invalid_outputs` is
# five defs.
type Ren is Data:
  Ren{n: U32, inv: List<&2, U32>, acc: List<&2, U32>}



def Ren.acc(r: Ren) -> List<&2, U32>:
  match r:
    case Ren{n, inv, acc}: acc

def fn_renum.slot(+hit: Bool, n: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, hit, List.append(&2, U32, acc, [n]), acc)

# THE COUNTER ADVANCES ONLY ON A HIT, and that is the whole content of
# `renumber_invalid_outputs`. Python writes
#     enumerate(x for x in uret.toposort(enter_calls=False) if x in invalid)
# -- the FILTER IS INSIDE `enumerate`, so `i` counts the INVALID nodes and not
# the toposort positions. The first version of this def incremented on every
# node, which is the reading a transliteration produces, and the gate caught it:
# on `SINK(STORE, ADD(a1,a1), STORE)` CPython's two slots are `0|1` and the
# buggy counter answered `0|3`. Row `renum_gap` is the ONLY row that sees it --
# `renum_two` answers `0|1` under BOTH counters, because on that fixture the two
# invalid nodes sit at toposort positions 0 and 1 and the counters coincide.
def fn_renum.hit(+inv: List<&2, U32>, u: U32) -> Bool:
  List.contains(U32, U32.is_eq, inv, u)

def fn_renum.step.of(hit: Bool) -> U32:
  match hit:
    case True{}: 1
    case False{}: 0

def fn_renum.step(hit: Bool) -> U32:
  fn_renum.step.of(hit)

def fn_renum.emit(+r: Ren, +g: O.Found) -> Ren:
  match r:
    case Ren{+n, +inv, +acc}: Ren{U32.add(n, fn_renum.step(fn_renum.hit(inv, fn_u(g)))), inv,
                                  fn_renum.slot(fn_renum.hit(inv, fn_u(g)), n, acc)}

def fn_renum.go(xs: List<&2, U32>, +ar: O.Arena, +r: Ren) -> Ren:
  match xs:
    case Nil{}: r
    case h <> t: fn_renum.go(t, ar, fn_renum.emit(r, O.Found{ar, h}))

def fn_renum.go2(+f: O.Found, inv: List<&2, U32>) -> List<&2, U32>:
  Ren.acc(fn_renum.go(O.UOp.toposort(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)),
                     O.Found.ar(f), Ren{0, inv, Nil{}}))

def fn_renum(+f: O.Found, inv: List<&2, U32>) -> List<&2, U32>:
  fn_renum.go2(f, inv)

# ===========================================================================
# SECTION F -- `pm_ctx` (function.py:19-25), as a `Data` rule table and THIS
# file's own dispatch. `ops.bend` cannot call into here, so the scan and the tag
# dispatch are duplicated -- `spec.bend` does it six times and says so in its
# header, and the header's instruction not to invent a generic dispatch
# abstraction is followed literally.
#
#     pm_ctx = PatternMatcher([
#       # Capture caller-owned storage, not allocations created while tracing this function.
#       (UPat((Ops.BUFFER, Ops.ALLOC, Ops.PARAM), name="x"), lambda ctx,x: add_to_ctx(ctx,x) if is_implicit_storage(ctx, x) else None),
#       (UPat((Ops.AFTER, Ops.STAGE), name="x"), lambda ctx,x: add_to_ctx(ctx,x) if
#        not any(p.op is Ops.PARAM and p.arg.slot >= 0 for p in x.backward_slice) and
#        any(is_implicit_storage(ctx, b) for b in x.toposort(enter_calls=False)) else None),
#     ])
#
# BOTH PATTERNS ARE `UPat((...))`, which is `is_any` over the op TUPLE, so the
# table's `ops` IS the tuple and `rej` is empty (neither pattern has a src
# constraint at all, so no `early_reject` survives compilation). `pctx_swapped`
# exists because a gate carrying a tag and an op set and no SRC SEQUENCE is
# blind to a swapped operand pair, and that is measured rather than assumed.
def pm_ctx() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsPARAM{}], Nil{}},
              O.PMEntry{1, [O.OpsAFTER{}, O.OpsSTAGE{}], Nil{}}]}

# rule 1's first conjunct, `not any(p.op is Ops.PARAM and p.arg.slot >= 0 for p
# in x.backward_slice)`. A fold over the BACKWARD SLICE -- the toposort MINUS
# SELF, and the difference from the second conjunct is exactly one node.
def fn_r1.notparam.of(isparam: Bool, slot: U32) -> Bool:
  Bool.not(Bool.and(isparam, U32.is_ge(slot, 0)))

def fn_r1.notparam(+f: O.Found) -> Bool:
  fn_r1.notparam.of(O.eq_op(fn_op(f), O.OpsPARAM{}), fn_slot(f))

def fn_r1.noparam(xs: List<&2, U32>, +ar: O.Arena) -> Bool:
  match xs:
    case Nil{}: True{}
    case u <> t: Bool.and(fn_r1.notparam(O.Found{ar, u}), fn_r1.noparam(t, ar))

# rule 1's second conjunct, `any(is_implicit_storage(ctx, b) for b in
# x.toposort(enter_calls=False))`. A fold over the toposort WITH self.
# `start` is a `U32` and the arm reads it twice, so the flag rides in a `Data`
# record with the arena -- the `Flags{glru, lru}` shape from
# `renderer/cstyle.bend` rule 6, and the same reason.
type FnSt is Data:
  FnSt{ar: O.Arena, start: U32}

def FnSt.ar(s: FnSt) -> O.Arena:
  match s:
    case FnSt{ar, start}: ar

def FnSt.start(s: FnSt) -> U32:
  match s:
    case FnSt{ar, start}: start

def fn_r1.some(xs: List<&2, U32>, +s: FnSt) -> Bool:
  match xs:
    case Nil{}: False{}
    case u <> t: Bool.or(fn_implicit(O.Found{FnSt.ar(s), u}, FnSt.start(s)), fn_r1.some(t, s))

def fn_r1.noparam2(+f: O.Found) -> Bool:
  fn_r1.noparam(fn_bslice(f), O.Found.ar(f))

def fn_r1.some2(+f: O.Found, s: FnSt) -> Bool:
  fn_r1.some(O.UOp.toposort_nocalls(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)), s)

def fn_r1.of2(first: Bool, second: Bool) -> Bool:
  Bool.and(first, second)

def fn_r1(+f: O.Found, s: FnSt) -> Bool:
  fn_r1.of2(fn_r1.noparam2(f), fn_r1.some2(f, s))

# `Fired` -- the fact and the value together, because a `Maybe` cannot be a
# `Data` field and `+` cannot be spelled on one.
type Fired is Data:
  Fired{ok: Bool, ctx: FnCtx}

def Fired.of(ok: Bool, +c: FnCtx) -> Fired:
  Fired{ok, c}

def Fired.ok(f: Fired) -> Bool:
  match f:
    case Fired{ok, ctx}: ok

def Fired.ctx(f: Fired) -> FnCtx:
  match f:
    case Fired{ok, ctx}: ctx

# BOTH RULES SHARE `fn_r0.of3`: the predicate decides `hit` and `fn_add` is the
# SAME def for both rules, which is Python's one `add_to_ctx` at the end of two
# lambdas. Nothing is duplicated here except the `Bool.pick`, because both arms
# have to be evaluated (Bend is strict) and the ctx must survive the arm that did
# not fire.
def fn_r0.of3(+hit: Bool, +ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  Fired.of(hit, Bool.pick(FnCtx, hit, fn_add(ar, c, fn_u(g)), c))

def fn_r0(+ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  fn_r0.of3(fn_implicit(g, FnCtx.start(c)), ar, c, g)

def fn_rule1(+ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  fn_r0.of3(fn_r1(g, FnSt{ar, FnCtx.start(c)}), ar, c, g)

# THE DISPATCH, and the tag ladder ends in `case _:` because `case 0:` claims its
# successors (measured; the diagnostic says nothing useful about it).
def fn_dispatch.go(tag: U32, +ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  match tag:
    case 0: fn_r0(ar, c, g)
    case _: fn_rule1(ar, c, g)

def fn_dispatch(tag: U32, +ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  fn_dispatch.go(tag, ar, c, g)

def fn_try(claimed: Bool, tag: U32, +ar: O.Arena, +c: FnCtx, +g: O.Found) -> Fired:
  match claimed:
    case True{}: fn_dispatch(tag, ar, c, g)
    case _: Fired.of(False{}, c)

# THE REWRITE -- `graph_rewrite(uret, pm_ctx, ..., bottom_up=True)`. `bottom_up`
# is the toposort REVERSED, which is what `fn_scan` walks, and it matters: the
# rule reads a node's own subgraph, so a node is judged after its srcs are. The
# rules are FIRST-WINS (Python's `PatternMatcher.rewrite` returns the first
# non-None), and `fn_scan.keep` is the fold that makes it so.
def fn_scan.keep(+c: FnCtx, +f: Fired) -> FnCtx:
  Bool.pick(FnCtx, Fired.ok(f), Fired.ctx(f), c)

# `u` is read three times in the arm -- the claim test, the `Found` for the rule
# and the self-call -- so the node travels as an `O.Found` (`+` is refused on a
# `U32`). The rules are a `Data` list so the walk is copyable and the SAME table
# can be walked twice; that is the payoff the compiled form buys.
def fn_scan.put.go(todo: List<&2, O.PMEntry>, +g: O.Found, +ar: O.Arena, +c: FnCtx) -> FnCtx:
  match todo:
    case Nil{}: c
    case +e <> t: fn_scan.put.go(t, g, ar, fn_scan.keep(c, fn_try(O.pm_claimed(O.PMEntry.ops(e), ar, fn_u(g)),
                                                                O.PMEntry.tag(e), ar, c, g)))

def fn_scan.put2(+g: O.Found, +ar: O.Arena, +c: FnCtx, rules: O.PMEntrys) -> FnCtx:
  fn_scan.put.go(O.PMEntrys.es(rules), g, ar, c)

def fn_scan(xs: List<&2, U32>, +ar: O.Arena, +c: FnCtx, +rules: O.PMEntrys) -> FnCtx:
  match xs:
    case Nil{}: c
    case u <> t: fn_scan(t, ar, fn_scan.put2(O.Found{ar, u}, ar, c, rules), rules)

def fn_pm_ctx(+f: O.Found, +c: FnCtx) -> FnCtx:
  fn_scan(List.reverse(&2, U32, O.UOp.toposort(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f))),
          O.Found.ar(f), c, pm_ctx())

# ===========================================================================
# SECTION G -- `_function` (function.py:39-98) and `function` (101-113).
#
# `_function` is a CLASS with five instance fields and one CLASS field:
#     depth = 0
#     def __init__(self, fxn, *, precompile, precompile_backward, allow_implicit, grad_fxn):
#     def __get__(self, obj, objtype=None): return functools.partial(self.__call__, obj) if obj is not None else self
#
# `depth` is CLASS-level, so it is SHARED across instances, and it is the reason
# the DEBUG print at function.py:93 indents by it. Bend has no class-level
# state, so it is a threaded parameter -- and threading it is not a workaround,
# it is the only way to make "two instances share one counter" a TYPE-CHECKED
# fact rather than a global nobody can see. `grad_fxn` is a Python callable, so
# it is NOT a field: a function value in a record forces `Type`, not `Data`.
type Fn is Data:
  Fn{precompile: Bool, precompile_backward: Bool, allow_implicit: Bool, depth: U32}

def Fn.of() -> Fn:
  Fn{False{}, False{}, False{}, 0}

def Fn.depth(+f: Fn) -> U32:
  match f:
    case Fn{precompile, precompile_backward, allow_implicit, depth}: depth

def Fn.precompile(+f: Fn) -> Bool:
  match f:
    case Fn{precompile, precompile_backward, allow_implicit, depth}: precompile

def Fn.allow_implicit(+f: Fn) -> Bool:
  match f:
    case Fn{precompile, precompile_backward, allow_implicit, depth}: allow_implicit

def fn_enter.of(+f: Fn, d: U32) -> Fn:
  match f:
    case Fn{precompile, precompile_backward, allow_implicit, depth}:
      Fn{precompile, precompile_backward, allow_implicit, U32.add(d, 1)}

# `_function.depth += 1`, the first half of the `with Context(...)` block.
# `_function.depth -= 1` in the `finally`. The row that says the counter is
# RESTORED and not merely incremented is `dep_exit` -- a port that leaked the
# depth would still pass `dep_enter`.
def fn_exit.of(+f: Fn, d: U32) -> Fn:
  match f:
    case Fn{precompile, precompile_backward, allow_implicit, depth}:
      Fn{precompile, precompile_backward, allow_implicit, U32.sub(d, 1)}

def fn_enter(+f: Fn) -> Fn:
  fn_enter.of(f, Fn.depth(f))

# function.py:67-72. `isinstance(ret, Tensor)` / a tuple of Tensors / ELSE. The
# `else` is a `RuntimeError` in Python and a three-valued ANSWER here, and the
# message is built so a gate can compare it with CPython byte for byte.
type FnRet is Data:
  FnRet{kind: U32, n: U32}

def fn_exit(+f: Fn) -> Fn:
  fn_exit.of(f, Fn.depth(f))

def fn_ret.kind(r: FnRet) -> U32:
  match r:
    case FnRet{kind, n}: kind


# `f"function return type {type(ret)} not supported"`. CPython prints the CLASS,
# and the classes a traced body can return that are not Tensors are the two the
# gate uses: `int` and `NoneType`. The port's `type(ret)` is a `U32` KIND, so the
# spelling is a table and the table has exactly the entries the gate needs. It is
# a table and not a computed name because the name of a Python type is not a
# value this port has; a `Maybe` kind would be the answer if the port had type
# objects, and it does not.

def fn_ret_name.of(kind: U32) -> String:
  match kind:
    case 0: "<class 'int'>"
    case _: "<class 'NoneType'>"
def fn_ret_name(kind: U32) -> String:
  fn_ret_name.of(kind)
def fn_ret_msg(r: FnRet) -> String:
  String.concat(["function return type ", fn_ret_name(fn_ret.kind(r)), " not supported"])





# ===========================================================================
# SECTION H -- `__call__` (function.py:50-98), the PORTED branches, in order.
#
#   51     st = time.perf_counter()                        SEAM  (effect)
#   53     params = get_state_dict(...)                     SEAM  ((args, kwargs) shape)
#   56     call_uops = dedup([... for t in params if ...])  PORTED (fn_call_uops)
#   60-66  with Context(ALLOW_DEVICE_USAGE=...): depth++    SEAM  (Context) + PORTED (fn_enter)
#   67-72  the return-kind test                             PORTED (FnRet)
#   75-76  subs = {x: x.param_like(i) ...}; uret.substitute  SEAM  (param_like, substitute)
#   79-81  num_explicit; graph_rewrite(pm_ctx); renumber    PORTED (fn_pm_ctx, fn_renum)
#   82     name = __qualname__                              SEAM  (fn_name takes a String)
#   83-87  the allow_implicit refusal                       PORTED (fn_implicit_msg)
#   89-90  UOp.call_with_outputs(...)                       SEAM  (ops.py:1272)
#   92-93  the DEBUG>=2 print, indented by depth            PORTED (fn_trace)
#   95-98  tuple(Tensor(o) for o in outs)                  SEAM  (Tensor from an OUTSIDE)
#
# NOT `H.dedup_u32`, AND THE REASON IS MEASURED. `H.dedup_u32.go` is
# `dedup_u32.put(List.contains(U32, U32.is_eq, r, x), x, r)` and `put` is
# `case False{}: h <> r` -- a PREPEND -- so `H.dedup_u32([1, 7, 1])` answers
# `[7, 1]`, THE REVERSE. For a membership set that is indistinguishable from
# correct and no row in the tree would notice; for `call_uops` it is fatal,
# because the list's ORDER IS THE SLOT NUMBERING:
# `subs = {x: x.param_like(i) for i,x in enumerate(call_uops)}` and
# `is_implicit_storage` compares a slot against `alloc_start`.
# REPORTED, NOT FIXED: `helpers.bend` is read-only to this unit. Row `callu_ops`
# is the row that sees it -- it prints the OP SEQUENCE of the answer and not just
# its length, because a length is identical either way.
type Dedup is Data:
  Dedup{r: List<&2, U32>}

def Dedup.r(d: Dedup) -> List<&2, U32>:
  match d:
    case Dedup{r}: r

def Dedup.of(+g: O.Found, +d: Dedup) -> Dedup:
  Dedup{Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, Dedup.r(d), fn_u(g)),
                  Dedup.r(d), List.append(&2, U32, Dedup.r(d), [fn_u(g)]))}

# ONE RECURSIVE DEF, and the split into `.of`/`.of2` was refused as MUTUAL
# RECURSION. `x` is read once here (it is handed to `put`) and once inside `put`,
# and the accumulator is a `Data` record because a fold that must answer both a
# list and a fact about it rides in the STATE.
def fn_call_uops.put(x: U32, +d: Dedup) -> Dedup:
  Dedup.of(O.Found{O.Arena.empty(), x}, d)

def fn_call_uops.of(xs: List<&2, U32>, +d: Dedup) -> Dedup:
  match xs:
    case Nil{}: d
    case x <> t: fn_call_uops.of(t, fn_call_uops.put(x, d))


def fn_call_uops(us: List<&2, U32>) -> List<&2, U32>:
  Dedup.r(fn_call_uops.of(us, Dedup{Nil{}}))

# function.py:83-87, the `allow_implicit=False` refusal, and its TEXT.
#     implicit_buffers = [x for x in call_uops[num_explicit:] if x.op in {Ops.BUFFER, Ops.ALLOC}]
#     buf_strs = '\n  '.join(f"{i}: dtype={b.dtype}, size={b.max_numel()}, device={b.device}" ...)
#     raise RuntimeError(f"function {name} has {len(implicit_buffers)} implicit buffer(s), but allow_implicit=False\n  {buf_strs}")
#
# `num_explicit` IS `len(call_uops)` BEFORE the rewrite (function.py:79) and
# `call_uops` GROWS under `pm_ctx` (function.py:80 threads the same list), so the
# refusal set is the TAIL the rewrite APPENDED and not the argument list. That is
# the least obvious line in the file and it is the row `imp_tail`: a port that
# read `call_uops[:num_explicit]` would have the arguments, which is empty when
# nothing was captured, and every refusal row would print a message with a
# zero-line body.
# THE SLICE, AND IT IS A POSITIONAL ONE. CPython is
# `[x for x in call_uops[num_explicit:] if ...]`, and `num_explicit` is a COUNT
# (`len(call_uops)` before the rewrite), so the tail is "everything after the first
# `num_explicit` ELEMENTS". The first version of this filter compared the
# `num_explicit` against the NODE INDEX -- a count against a position -- and
# `imp_tail` read `1/1` where CPython's slice reads `1/0`. `List.drop` is the
# slice, so it is used directly and the hand-written filter is gone: two fewer
# defs, one of which was wrong.
def fn_imp_hit.of(+g: O.Found, +ar: O.Arena) -> Bool:
  Bool.or(O.eq_op(fn_op(g), O.OpsBUFFER{}), O.eq_op(fn_op(g), O.OpsALLOC{}))

def fn_imp_hit(+g: O.Found, +ar: O.Arena) -> Bool:
  fn_imp_hit.of(g, ar)

def fn_imp_put(+ar: O.Arena, +g: O.Found, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, fn_imp_hit(g, ar), List.append(&2, U32, acc, [fn_u(g)]), acc)

def fn_imp_take(xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case u <> t: fn_imp_take(t, ar, fn_imp_put(ar, O.Found{ar, u}, acc))

def fn_implicit_bufs(+ar: O.Arena, c: FnCtx, num_explicit: U32) -> List<&2, U32>:
  fn_imp_take(List.drop(&2, U32, FnCtx.us(c), U32.to_nat(num_explicit)), ar, Nil{})

def fn_imp_dt.of(dt: S.Dt) -> String:
  String.concat(["dtypes.", T.dt_name(dt)])

# `device=` is CPython's `str(b.device)`, and a DEVICE-LESS buffer prints `None`
# on both sides -- which is why the gate's fixtures are device-less: the port's
# `S.Dev` is an interned TAG, so `tn_repr.devname` would print the tag where
# CPython prints `METAL`, and that row would be the one row in this file whose
# two sides could not be compared. `tn_repr.devname` already answers `"None"`.
def fn_imp_dev(+f: O.Found) -> String:
  T.tn_repr.devname(T.tn_dev(T.tn_new(O.Found.ar(f), O.Found.i(f))))

def fn_imp_dt(+f: O.Found) -> String:
  fn_imp_dt.of(T.tn_repr.dt(T.tn_new(O.Found.ar(f), O.Found.i(f))))

# `max_numel` is a product of a shape, so a node the fold cannot answer has no
# size. `FN_NOSZ` is `4294967295` and the ROW NAME carries it, because a gate
# that prints `0` for a missing size is indistinguishable from a zero-size buffer.
def FN_NOSZ() -> U32: 4294967295

# `b.max_numel()` IS THE PRODUCT OF THE SHAPE, and `T.tn_len` is NOT that --
# `tensor.bend`'s `tn_len.first` answers `self.shape[0]`, and worse it answers
# `O.SInt.u(d)`, a SINT's ARENA INDEX, not its value, so it printed 0 for every
# one-dimensional fixture. So the product is folded here, over `O.Sint`, and a
# BOUND dim answers `FN_NOSZ` rather than 0.
def fn_imp_dim.of(d: O.Sint) -> U32:
  match d:
    case O.SI{i}: H.lo32(i)
    case _: FN_NOSZ()

def fn_imp_dim(d: O.Sint) -> U32:
  fn_imp_dim.of(d)

def fn_imp_sz.go(ds: List<&2, O.Sint>, acc: U32) -> U32:
  List.foldl(~&2, ~O.Sint, ~U32, (a: U32) => (d: O.Sint) => U32.mul(a, fn_imp_dim(d)), ds, acc)

def fn_imp_sz.of2(ds: List<&2, O.Sint>) -> U32:
  fn_imp_sz.go(ds, 1)

def fn_imp_sz.of(m: Maybe<&2, List<&2, O.Sint>>) -> U32:
  match m:
    case Some{ds}: fn_imp_sz.of2(ds)
    case _: FN_NOSZ()

def fn_imp_sz(+f: O.Found) -> U32:
  fn_imp_sz.of(T.tn_dims(T.tn_new(O.Found.ar(f), O.Found.i(f))))


def fn_imp_row.of(+f: O.Found, i: U32) -> String:
  String.concat([U32.show(i), ": dtype=", fn_imp_dt(f), ", size=", U32.show(fn_imp_sz(f)),
                 ", device=", fn_imp_dev(f)])


def fn_imp_row.of2(+f: O.Found, i: U32) -> String:
  fn_imp_row.of(f, i)

# `\n  '.join(...)` and the join is at the END, on a `List` built with
# `List.append` (measured: `schedule/memory.py` section A -- `List.append` is
# `xs ++ ys`, so the accumulator must APPEND for the order to come out right).
# THE `enumerate` COUNTER RIDES IN THE ACCUMULATOR, and that is not style. `i` is
# a `U32` read twice in one expression (once as the row's number, once as the next
# index), and `go` -> `put` -> `go` is the MUTUAL RECURSION Bend refuses
# (`mixin/divandmod.bend` rule 2). The escape is a step that does NOT recurse --
# `fn_imp_emit` only grows the record -- with the recursion left in `go`. It is
# `Ren` again, one section down, and the shape recurs because the constraint does.
type Imp is Data:
  Imp{n: U32, rows: List<&2, String>}

def Imp.n(st: Imp) -> U32:
  match st:
    case Imp{n, rows}: n

def Imp.rows(st: Imp) -> List<&2, String>:
  match st:
    case Imp{n, rows}: rows

def fn_imp_emit(+st: Imp, row: String) -> Imp:
  match st:
    case Imp{+n, +rows}: Imp{U32.add(n, 1), List.append(&2, String, rows, [row])}

def fn_imp_body.go(+ar: O.Arena, xs: List<&2, U32>, +st: Imp) -> Imp:
  match xs:
    case Nil{}: st
    case u <> t: fn_imp_body.go(ar, t, fn_imp_emit(st, fn_imp_row.of2(O.Found{ar, u}, Imp.n(st))))

def fn_imp_body(+ar: O.Arena, xs: List<&2, U32>) -> String:
  # `\n  '.join(...)` and the join is at the END, on a `List` built with
  # `List.append` APPENDING (measured: `schedule/memory.py` section A -- 
  # `List.append(a, A, xs, ys)` is `xs ++ ys`, so an accumulator must append).
  String.join(Imp.rows(fn_imp_body.go(ar, xs, Imp{0, Nil{}})), "\n  ")

def fn_implicit_msg.of(+bs: List<&2, U32>, name: String, +ar: O.Arena) -> String:
  String.concat(["function ", name, " has ", U32.show(fn_ctx_n(bs)),
                 " implicit buffer(s), but allow_implicit=False", "\n  ", fn_imp_body(ar, bs)])

# function.py:93. `f"{uret.key.hex()[:8]} in {(time.perf_counter()-st)*1000:8.2f} ms: {name}"`
# indented by `"  " * _function.depth`. The `key` is an opaque `UOpMetaClass`
# hash and the clock is an effect, so this row pins the ONE part that is a pure
# function of the port's state: the INDENT and the NAME, with the key and the
# elapsed time as PARAMETERS (the injected-time discipline).
# `"  " * _function.depth`. A `U32` CANNOT DESCEND as a self-call (measured:
# `uop/fold.bend` rule 5 -- "expected : a decreasing self-call", and
# `U32.sub(d, 1)` is not a subterm of `d`), so the depth is converted to a `Nat`
# once and the countdown is destructured as `Succ{p}`, which IS the strict
# subterm the decrease check looks for. The spelling is `helpers.bend:399`'s.
def fn_trace.indent.go(d: Nat, +acc: List<&2, String>) -> List<&2, String>:
  match d:
    case 0n: acc
    case Succ{p}: fn_trace.indent.go(p, List.append(&2, String, acc, ["  "]))

def fn_implicit_msg(name: String, +ar: O.Arena, +c: FnCtx, +num_explicit: U32) -> String:
  fn_implicit_msg.of(fn_implicit_bufs(ar, c, num_explicit), name, ar)

def fn_trace.ind.of(depth: U32, acc: List<&2, String>) -> String:
  String.concat(fn_trace.indent.go(U32.to_nat(depth), acc))

def fn_trace.ind(depth: U32) -> String:
  fn_trace.ind.of(depth, Nil{})

def fn_trace.of(depth: U32, key8: String, ms: String, name: String) -> String:
  String.concat([fn_trace.ind(depth), "function ", key8, " in ", ms, " ms: ", name])

def fn_name(has: Bool, nm: String, dflt: String) -> String:
  Bool.pick(String, has, nm, dflt)
# ===========================================================================
# SECTION I -- THE OMISSIONS. One line each: what, where, and the phase that owns
# it. Nothing here is silently dropped, and every one names a wall rather than an
# effort.
#
# TODO(p3) ops.py:1239  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
#   is answered by `fn_add` and the NODE is not built. Owner: `uop/ops.bend`, and
#   the reason is structural: `param_like` reads `self.addrspace` and
#   `self.axis`, which are fold properties, so it belongs beside the fold and not
#   in a caller.
# TODO(p3) ops.py:532   `UOp.substitute` -- `uret.substitute(subs)` and
#   `uret.substitute({b: ...})`. It IS `graph_rewrite`, so it needs the matcher
#   machinery `uop/spec.bend` owns and a closure the port does not have.
# TODO(p3) ops.py:1272  `UOp.call_with_outputs` -- `uret.call_with_outputs(...)`.
#   It is the PROGRAM/CallInfo construction and it needs `grad_fxn`, which is a
#   Python callable; a function value in a record forces `Type`, not `Data`.
# TODO(p3) ops.py:245   `UOp.replace` -- `b.replace(op=ALLOC, arg=replace(b.arg,
#   slot=i, buffer=None, bind_on_realize=False))`. `ParamArg` is a `Data` record
#   of thirteen fields, so the `replace` is a thirteen-field literal: it is
#   WRITABLE and it is not written here because `substitute` is the seam ABOVE it
#   and a builder with no caller is a lie. `fn_renum` is the NUMBERING, which is
#   the part with a behaviour.
# TODO(p3) function.py:53  `get_state_dict((args, kwargs))` -- `nn/state.bend` has
#   `get_state_dict(Obj)` and not the `(args, kwargs)` TUPLE wrapper, which is a
#   two-field `Data` record plus a `type(t) is Tensor` / `is UOp` filter.
# TODO(p3) function.py:61  `with Context(ALLOW_DEVICE_USAGE=getenv(..., 0))` --
#   `helpers.bend` has no `Context` (a thread-local contextvar stack) and
#   `getenv` is an effect. The `finally` that restores the depth is the same
#   shape as `fn_exit`, and `fn_enter`/`fn_exit` ARE ported and gated, so the
#   depth half of line 61 is not lost.
# TODO(p3) function.py:64  `self.fxn(*args, **kwargs)` -- no function values in
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
# TODO(p3) ops.py:925  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
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
# ===========================================================================
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
# WHAT THIS SEAM DOES **NOT** REPLACE, and it is the important half:
# `examples/beautiful_mnist.ts`'s `@TinyJit` is NOT this file. `TinyJit` is
# `tinygrad/engine/jit.py`, its spec match is
# `self.captured.expected_input_info != expected_input_info`, and its counter is
# `self.cnt` -- none of which is in `function.py` and none of which this port
# touches. `@function_` is the seam; `@TinyJit` belongs to whatever unit owns
# `engine/jit.py`.
# ===========================================================================
# ===========================================================================
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
# ===========================================================================

def fn_trace(depth: U32, key8: U32, ms: U32, name: String) -> String:
  fn_trace.of(depth, U32.show(key8), U32.show(ms), name)

# -- the fixture builders ----------------------------------------------------
#
# `ParamArg` is a thirteen-field `Data` record and `ParamArg.of` fixes nine of
# them, so a fixture that needs `bind_on_realize` or a value range builds the
# literal. `volatile` is a RESERVED WORD in Bend 2.0.34 (measured, rule 25) and
# is the ninth field, so it is `False{}` here with the field's own name.
def fx_pa(slot: U32, dt: S.Dt, size: Maybe<&2, U32>, vv: Maybe<&2, O.PyRange>,
          addr: S.Addr, bor: Bool, buf: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{slot, dt, size, vv, None{}, None{}, addr, None{}, False{}, None{}, buf, bor, None{}}

def fx_node(+ar: O.Arena, +op: O.Op, srcs: List<&2, U32>, arg: O.Arg) -> O.Found:
  O.UOp.new(ar, op, srcs, arg, O.TNone{})

# a realized BUFFER: `buffer` is `Some`, which is `is_realized` and is the whole
# of the third conjunct of `invalid_outputs`.
def fx_buf.of(+ar: O.Arena, slot: U32, size: U32, buf: Maybe<&2, U32>) -> O.Found:
  fx_node(ar, O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(slot, S.single(), Some{size}, None{}, S.AGlobal{}, False{}, buf)})

# a device-less BUFFER, which is what the `imp_*` rows need: CPython prints
# `str(None)` and `tn_repr.devname` prints `"None"`, so the two sides agree.
def fx_nbuf_on(+ar: O.Arena, slot: U32, size: U32) -> O.Found:
  fx_buf.of(ar, slot, size, Some{0})

def fx_nbuf(slot: U32, size: U32) -> O.Found:
  fx_nbuf_on(O.Arena.empty(), slot, size)

def fx_buf(slot: U32, size: U32, buf: Maybe<&2, U32>) -> O.Found:
  fx_buf.of(O.Arena.empty(), slot, size, buf)

def fx_alloc.of(+ar: O.Arena, slot: U32, bor: Bool) -> O.Found:
  fx_node(ar, O.OpsALLOC{}, Nil{}, O.AParam{fx_pa(slot, S.single(), Some{4}, None{}, S.AGlobal{}, bor, None{})})

# a scalar ALU PARAM carrying a value range: `size = None` is what makes the
# fold answer `()` and the node a `Variable`.
def fx_scalar.of(+ar: O.Arena, slot: U32, vv: Maybe<&2, O.PyRange>, addr: S.Addr, size: Maybe<&2, U32>) -> O.Found:
  fx_node(ar, O.OpsPARAM{}, Nil{}, O.AParam{fx_pa(slot, S.int32(), size, vv, addr, False{}, None{})})

def fx_alloc(slot: U32, bor: Bool) -> O.Found:
  fx_alloc.of(O.Arena.empty(), slot, bor)

def fx_vrange() -> Maybe<&2, O.PyRange>:
  Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(9)}}

def fx_scalar(slot: U32, vv: Maybe<&2, O.PyRange>, addr: S.Addr, size: Maybe<&2, U32>) -> O.Found:
  fx_scalar.of(O.Arena.empty(), slot, vv, addr, size)

# `CONST(Invalid)` -- `fold.bend`'s `is_invalid` is the reader.
def fx_inval(+ar: O.Arena) -> O.Found:
  fx_node(ar, O.OpsCONST{}, Nil{}, O.APy{O.CInvalid{}})

def fx_ci(+ar: O.Arena, v: U32) -> O.Found:
  fx_node(ar, O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(v)}})

def fx_store.of(+ar: O.Arena, b: U32, v: U32) -> O.Found:
  fx_node(ar, O.OpsSTORE{}, [b, v], O.ANone{})

def fx_sink(+ar: O.Arena, srcs: List<&2, U32>) -> O.Found:
  fx_node(ar, O.OpsSINK{}, srcs, O.ANone{})

def fx_store(+ar: O.Arena, b: U32, v: U32) -> O.Found:
  fx_store.of(ar, b, v)

def fx_after.of(+ar: O.Arena, d: U32, g: U32) -> O.Found:
  fx_node(ar, O.OpsAFTER{}, [d, g], O.ANone{})

def fx_add(+ar: O.Arena, x: U32, y: U32) -> O.Found:
  fx_node(ar, O.OpsADD{}, [x, y], O.ANone{})

def fx_after(+ar: O.Arena, d: U32, g: U32) -> O.Found:
  fx_after.of(ar, d, g)

# the boolean printer every row uses. `Bool` has no `U32.show` (measured:
# `mixin/movement.bend` rule 3), so this is the one conversion and it is hoisted.
def b2u(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def bshow(b: Bool) -> String:
  U32.show(b2u(b))


# -- the ctx printer ---------------------------------------------------------
def ctx_ops.go(+ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case u <> t: ctx_ops.go(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, u))]))

def ctx_ops(ar: O.Arena, c: FnCtx) -> String:
  String.join(ctx_ops.go(ar, FnCtx.us(c), Nil{}), "|")




# THE REWRITE IN BOTH DIRECTIONS, and the reason there are two rows per fixture
# is MEASURED, not stylistic. CPython's `graph_rewrite(..., bottom_up=True)`
# answers `captured=AFTER` for `AFTER(BUFFER, ALLOC)`, which is only reachable if
# the AFTER is judged BEFORE its own srcs; rule 0 (which claims the BUFFER) and
# rule 1 (which claims the AFTER) then both fire on the same graph and the ORDER
# decides which lands in `ctx[0]`. `fn_pm_ctx` walks the REVERSED toposort --
# srcs first -- so it answers `captured=BUFFER`. Both are printed, because a gate
# that only printed one of them would be hiding a divergence rather than
# measuring it, and `pctx_order` is the row that names it.
def fn_pm_ctx_top(+f: O.Found, +c: FnCtx) -> FnCtx:
  fn_scan(O.UOp.toposort(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)), O.Found.ar(f), c, pm_ctx())

def pctx_row(c0: FnCtx, +bot: FnCtx, +top: FnCtx, +ar: O.Arena) -> String:
  String.concat(["bot=", U32.show(FnCtx.n(bot)), "/", ctx_ops(ar, bot),
                 " top=", U32.show(FnCtx.n(top)), "/", ctx_ops(ar, top)])

def pctx_of(+c0: FnCtx, +f: O.Found) -> String:
  pctx_row(c0, fn_pm_ctx(f, c0), fn_pm_ctx_top(f, c0), O.Found.ar(f))

# ===========================================================================
# SECTION K -- THE ROWS. One `String.concat` per row, one `IO.print` per row,
# and every expected value is a CPython answer measured by the oracle beside this
# file. The ROW CLASS is in the name, so a mutation table can name what moved.
# ===========================================================================

def fx_aft(+ar: O.Arena, d: U32, g: U32) -> O.Found:
  fx_node(ar, O.OpsAFTER{}, [d, g], O.ANone{})
def fx_buf_param_on(+ar: O.Arena, slot: U32) -> O.Found:
  fx_node(ar, O.OpsPARAM{}, Nil{}, O.AParam{fx_pa(slot, S.single(), Some{4}, None{}, S.AGlobal{}, False{}, None{})})
def fx_buf_param(slot: U32) -> O.Found:
  fx_buf_param_on(O.Arena.empty(), slot)

# ---- A: `is_implicit_storage`, one row per cell ------------------------------
# A realized BUFFER. CPython: `True` (`x.op is Ops.BUFFER`).
def iis_buf() -> String:
  +f = fx_buf(0, 4, Some{0})
  String.concat(["iis_buf=", bshow(fn_implicit(f, 0))])

# slot 0 < alloc_start 1 with `bind_on_realize=True`. CPython: `True`.
def iis_alloc_lt() -> String:
  +f = fx_alloc(0, True{})
  String.concat(["iis_alloc_lt=", bshow(fn_implicit(f, 1))])

# slot 1 is NOT < alloc_start 1. CPython: `False`. The `<` and not the `<=`.
def iis_alloc_ge() -> String:
  +f = fx_alloc(1, True{})
  String.concat(["iis_alloc_ge=", bshow(fn_implicit(f, 1))])

# slot 5, alloc_start 0. CPython: `False`.
def iis_alloc_far() -> String:
  +f = fx_alloc(5, True{})
  String.concat(["iis_alloc_far=", bshow(fn_implicit(f, 0))])

# `bind_on_realize=False` wins over a generous alloc_start. CPython: `False`.
def iis_alloc_nobor() -> String:
  +f = fx_alloc(0, False{})
  String.concat(["iis_alloc_nobor=", bshow(fn_implicit(f, 9))])

# slot 4294967295 IS `-1`, with a value range, ALU and no size. CPython: `True`.
def iis_var_m1() -> String:
  +f = fx_scalar(FN_NEG1(), fx_vrange(), S.Aalu{}, None{})
  String.concat(["iis_var_4294967295=", bshow(fn_implicit(f, 0))])

# the SAME node with slot 0. CPython: `False`. "positional scalar params are
# already captured" -- this row IS that comment, and the row name says `p0`.
def iis_var_p0() -> String:
  +f = fx_scalar(0, fx_vrange(), S.Aalu{}, None{})
  String.concat(["iis_var_p0=", bshow(fn_implicit(f, 0))])

# no value range. CPython: `False`.
def iis_var_novmin() -> String:
  +f = fx_scalar(FN_NEG1(), None{}, S.Aalu{}, None{})
  String.concat(["iis_var_novmin=", bshow(fn_implicit(f, 0))])

# a value range, ALU, but `size=4`, so `_shape == (4,)` and NOT `()`. CPython:
# `False`. This is the ONLY row that can see the shape conjunct of
# `UOp.is_variable`, and `fn_scalar` is the only reason the fold is imported.
def iis_var_1d() -> String:
  +f = fx_scalar(FN_NEG1(), fx_vrange(), S.Aalu{}, Some{4})
  String.concat(["iis_var_1d=", bshow(fn_implicit(f, 0))])

# `addrspace=REG` is not ALU. CPython: `False`.
def iis_var_reg() -> String:
  +f = fx_scalar(FN_NEG1(), fx_vrange(), S.AReg{}, None{})
  String.concat(["iis_var_reg=", bshow(fn_implicit(f, 0))])

# a CONST. CPython: `False`.
def iis_const() -> String:
  +f = fx_ci(O.Arena.empty(), 7)
  String.concat(["iis_const=", bshow(fn_implicit(f, 0))])

# a PARAM with NO value range: `is_variable` is False, so the slot cannot make it
# implicit. CPython: `False`. This is the row that separates "slot is -1" from
# "node is a Variable".
def iis_param_buf() -> String:
  +f = fx_buf_param(0)
  String.concat(["iis_param_buf=", bshow(fn_implicit(f, 0))])

# ---- B: `add_to_ctx`, and the `ctx[1]`-is-the-INVALID-set fact ---------------
# `inv` EMPTY: one add answers slot 0 and the SECOND add on the SAME buffer
# answers slot 1 with `ctx[0]` length 2. CPython: `0 1 2`.
def add_first() -> String:
  +g = fx_buf(0, 4, Some{0})
  +c1 = fn_add(O.Found.ar(g), FnCtx.of2(9), fn_u(g))
  +c2 = fn_add(O.Found.ar(g), c1, fn_u(g))
  String.concat(["add_first=", U32.show(FnCtx.slot(c1)), " add_again=", U32.show(FnCtx.slot(c2)),
                 " add_len=", U32.show(FnCtx.n(c2))])

# `inv` HOLDING the buffer: CPython answers `None` and `ctx[0]` does NOT grow.
# The port's `added` is `Bool.not(hit)` and the slot is `len(ctx[0])` on BOTH
# arms -- `add_ref_slot` is the row for that, and it is the reason `fn_add` has
# one builder instead of two.
def add_refused() -> String:
  +g = fx_buf(0, 4, Some{0})
  +c = fn_add(O.Found.ar(g), FnCtx{Nil{}, [fn_u(g)], 9, False{}, 0}, fn_u(g))
  String.concat(["add_refused=", bshow(FnCtx.added(c)), " add_ref_len=", U32.show(FnCtx.n(c)),
                 " add_ref_slot=", U32.show(FnCtx.slot(c))])

# ---- C: `invalid_outputs`, one row per conjunct's negative -------------------
# BOUNDED ARITY INSTEAD OF A COUNTDOWN, and this is not laziness: a countdown
# over a `U32` is not a decreasing self-call, and three graphs is three
# straight-line builders (`uop/fold.bend`'s "bounded arity sidesteps it
# entirely and needs no fuel at all"). Every builder takes the arena as an
# ARGUMENT and returns the `Found`, because a builder that returns an index
# throws the grown arena away (measured: `mixin/rand.bend` rule 5).
def fx_inv1.of(+ar: O.Arena, +b: O.Found, +v: O.Found) -> O.Found:
  # THE ARENA THE STORE RETURNED, NOT THE ONE THAT WENT IN. Passing `ar` on to
  # `fx_sink` builds a SINK whose src is not in its own store, so every reader of
  # that STORE answers `Arena.bottom` and the graph is one node that reads as a
  # NOOP. It typechecks, it runs, and the toposort answers 0 -- the whole family of
  # silent arena bugs, in the fixture rather than in the port.
  +s = fx_store.of(ar, fn_u(b), fn_u(v))
  fx_sink(O.Found.ar(s), [fn_u(s)])

def fx_inv1(+b: O.Found, +v: O.Found) -> O.Found:
  fx_inv1.of(O.Found.ar(v), b, v)
def fx_inv2.of2(+ar: O.Arena, +s1: O.Found, +b: O.Found, +v: O.Found) -> O.Found:
  +a2 = fx_alloc.of(ar, 2, True{})
  +s2 = fx_store.of(O.Found.ar(a2), fn_u(a2), fn_u(v))
  fx_sink(O.Found.ar(s2), [fn_u(s1), fn_u(s2)])


def fx_inv2.of(+ar: O.Arena, +b: O.Found, +v: O.Found) -> O.Found:
  +s1 = fx_store.of(ar, fn_u(b), fn_u(v))
  fx_inv2.of2(O.Found.ar(s1), s1, b, v)

def fx_inv2(+b: O.Found, +v: O.Found) -> O.Found:
  fx_inv2.of(O.Found.ar(v), b, v)


# THE GAP GRAPH: `SINK(STORE(a1,Invalid), ADD(a1,a1), STORE(a2,Invalid))`. The two
# invalid buffers sit at toposort positions 0 and 4, so a counter over the WHOLE
# toposort answers `0|4` while CPython answers `0|1`. `renum_gap` is the only row
# that separates them; `renum_two` answers `0|1` under both, which is exactly the
# "a mutation that moves nothing is information about the GATE" case.
def fx_gap.of2(+ar: O.Arena, +s1: O.Found, +m: O.Found, +b: O.Found, +v: O.Found) -> O.Found:
  +a2 = fx_alloc.of(ar, 2, True{})
  +s2 = fx_store.of(O.Found.ar(a2), fn_u(a2), fn_u(v))
  fx_sink(O.Found.ar(s2), [fn_u(s1), fn_u(m), fn_u(s2)])

def fx_gap.of(+ar: O.Arena, +b: O.Found, +v: O.Found) -> O.Found:
  +s1 = fx_store.of(ar, fn_u(b), fn_u(v))
  +m = fx_add(O.Found.ar(s1), fn_u(b), fn_u(b))
  fx_gap.of2(O.Found.ar(m), s1, m, b, v)

def fx_gap(+b: O.Found, +v: O.Found) -> O.Found:
  fx_gap.of(O.Found.ar(v), b, v)


# `SINK(STORE(ALLOC(1,bor), CONST(Invalid)))`. CPython: 1 -- the ALLOC, because it
# is not realized.
def inv_one() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  String.concat(["inv_one=", U32.show(fn_ctx_n(fn_invalid(fx_inv1(b, v))))])

# the SAME graph with a VALID const in src[1]. CPython: 0. The `is_invalid`
# conjunct, and the row a port that dropped it would fail.
def inv_ok() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_ci(O.Found.ar(b), 7)
  String.concat(["inv_ok=", U32.show(fn_ctx_n(fn_invalid(fx_inv1(b, v))))])

# two invalid buffers. CPython: 2.
def inv_two() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  String.concat(["inv_two=", U32.show(fn_ctx_n(fn_invalid(fx_inv2(b, v))))])

# a REALIZED buffer storing CONST(Invalid). CPython: 0 -- "only skip fresh
# buffers, not realized ones". This is the third conjunct, and reading it needs
# `fn_buf`'s walk AND `fn_realized` to agree that the node IS its own base.
def inv_real() -> String:
  +g = fx_buf(0, 4, Some{0})
  +v = fx_inval(O.Found.ar(g))
  +s = fx_store.of(O.Found.ar(v), fn_u(g), fn_u(v))
  +k = fx_sink(O.Found.ar(s), [fn_u(s)])
  String.concat(["inv_real=", U32.show(fn_ctx_n(fn_invalid(k)))])

# A NON-STORE node whose `src[1]` IS `CONST(Invalid)` and whose `src[0]` IS a fresh
# buffer: CPython answers 0, and so must the port -- the `op is Ops.STORE` conjunct
# is doing the work. Without this fixture M12 (dropping the conjunct) moved NOTHING:
# every other node in the `inv_*` graphs either has `nsrc < 2` or a `src[1]` that is
# not a CONST, so the dropped term was vacuously true everywhere. A conjunct needs a
# fixture on which it is the ONLY thing standing between the answer and the wrong one.
def inv_notstore() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  +m = fx_add(O.Found.ar(v), fn_u(b), fn_u(v))
  String.concat(["inv_notstore=", U32.show(fn_ctx_n(fn_invalid(fx_sink(O.Found.ar(m), [fn_u(m)]))))])

# ---- D: `renumber_invalid_outputs`, the NUMBERING ---------------------------
# ONE invalid buffer. CPython: slot 0.
def fn_slots.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: fn_slots.go(t, List.append(&2, String, acc, [U32.show(h)]))

def fn_slots(xs: List<&2, U32>) -> List<&2, String>:
  fn_slots.go(xs, Nil{})
def fn_slots_row(+g: O.Found) -> String:
  String.concat([String.join(fn_slots(fn_renum(g, fn_invalid(g))), "|"),
                 "@", U32.show(fn_ctx_n(O.UOp.toposort(O.Arena.budget(O.Found.ar(g)), O.Found.ar(g), fn_u(g))))])

def renum_one() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  +g = fx_inv1(b, v)
  String.concat(["renum_one=", fn_slots_row(g)])

# TWO, adjacent in the toposort. CPython: `0|1` -- and the buggy "count the whole
# toposort" counter ALSO answers `0|1` here, so this row does NOT pin the filter.
def renum_two() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  String.concat(["renum_two=", fn_slots_row(fx_inv2(b, v))])

# THE GAP. CPython: `0|1`; the toposort positions of the same two buffers are 0
# and 4. This is the row that pins "the filter is inside the enumerate", and it
# is the row that found the bug in the first version of `fn_renum`.
def renum_gap() -> String:
  +b = fx_alloc(1, True{})
  +v = fx_inval(O.Found.ar(b))
  String.concat(["renum_gap=", fn_slots_row(fx_gap(b, v))])




# `slots@positions`, so each row carries BOTH numbers and the difference between
# them is in the output rather than in a comment.






# AND THE WRAPPER TAKES THE LAST BUILT NODE'S ARENA, not the first's: `b` is
# interned before `v`, so `O.Found.ar(b)` does not CONTAIN `v` and the next node
# lands at the index `v` already holds. Two builds from the same base are SIBLING
# arenas of equal length, and "the ar of the first argument" picks the wrong one
# (`mixin/elementwise.bend`, the second half of rule 6). The symptom here was a
# STORE whose `src[1]` read back as ITSELF -- the graph `SINK(STORE(b, STORE))` --
# and every `inv_*` row read 0.
#
# ---- E: `pm_ctx`, both rules, and the ORDER that decides between them -------
# The table's own shape: two entries, the op TUPLES as written, `rej` empty.
def pctx_ops.go(ops: List<&2, O.Op>, +acc: List<&2, String>) -> List<&2, String>:
  match ops:
    case Nil{}: acc
    case o <> t: pctx_ops.go(t, List.append(&2, String, acc, [O.Ops.name(o)]))

def pctx_ops(ops: List<&2, O.Op>) -> List<&2, String>:
  pctx_ops.go(ops, Nil{})

def pctx_table.one(i: U32, +e: O.PMEntry) -> String:
  String.concat([U32.show(i), ":", String.join(pctx_ops(O.PMEntry.ops(e)), "/")])

# The index rides in a `Data` record because it is a `U32` read twice -- once as
# the entry number and once as the next index -- which is `Imp`'s shape in
# Section H and `Ren`'s in Section E. The SAME record answers three different
# walks in this file; that is the recurrence of the constraint, not a coincidence.
type Ix is Data:
  Ix{i: U32, acc: List<&2, String>}


def Ix.acc(x: Ix) -> List<&2, String>:
  match x:
    case Ix{i, acc}: acc

def Ix.grow(+e: O.PMEntry, x: Ix) -> Ix:
  match x:
    case Ix{+i, +acc}: Ix{U32.add(i, 1), List.append(&2, String, acc, [pctx_table.one(i, e)])}

def pctx_table.go(es: List<&2, O.PMEntry>, x: Ix) -> Ix:
  match es:
    case Nil{}: x
    case +e <> t: pctx_table.go(t, Ix.grow(e, x))

def pctx_table.put(x: Ix) -> List<&2, String>:
  Ix.acc(x)

def pctx_table.of(ts: O.PMEntrys) -> String:
  String.join(pctx_table.put(pctx_table.go(O.PMEntrys.es(ts), Ix{0, Nil{}})), " ")

def pctx_table() -> String:
  pctx_table.of(pm_ctx())




# A realized BUFFER alone: CPython captures 1 node, `BUFFER` -- rule 0.
def pctx_buf() -> String:
  +g = fx_buf(0, 4, Some{0})
  String.concat(["pctx_buf=", pctx_of(FnCtx.of2(0), g)])

# A FRESH ALLOC (`bind_on_realize=False`) alone: CPython captures NOTHING. This is
# the "not allocations created while tracing this function" comment, and it is the
# negative that stops `pctx_buf` from being read as "every buffer is captured".
def pctx_fresh() -> String:
  +g = fx_alloc(0, False{})
  String.concat(["pctx_fresh=", pctx_of(FnCtx.of2(0), g)])

# `ADD(ALLOC, CONST)` over a FRESH alloc: CPython captures NOTHING, so the root op
# and the node count are the only things this fixture reports -- and the two
# operands carry DIFFERENT ops, which is what makes the swap below visible at all.
# An earlier version of this pair used two ALLOCs and printed
# `srcops=Ops.ALLOC|Ops.ALLOC` on BOTH rows, which is the blind spot the brief warns
# about reproduced in the fixture rather than in the gate: a srcop SEQUENCE of two
# identical names carries no order.
def pctx_add01() -> String:
  +f0 = fx_alloc(0, False{})
  +c = fx_ci(O.Found.ar(f0), 7)
  +g = fx_add(O.Found.ar(c), fn_u(f0), fn_u(c))
  String.concat(["pctx_add01=", MX.mxw_sig(O.Found.ar(g), fn_u(g)), " ", pctx_of(FnCtx.of2(0), g)])

# THE SAME graph with the two operands SWAPPED. `mxw_sig`'s `srcops=` is the
# ONLY part of these two rows that differs, and that is the whole point: a gate
# carrying a node count and a root op is measurably blind to this, and the two
# rows are what make it not blind.
def pctx_add10() -> String:
  +f0 = fx_alloc(0, False{})
  +c = fx_ci(O.Found.ar(f0), 7)
  +g = fx_add(O.Found.ar(c), fn_u(c), fn_u(f0))
  String.concat(["pctx_add10=", MX.mxw_sig(O.Found.ar(g), fn_u(g)), " ", pctx_of(FnCtx.of2(0), g)])

# `AFTER(f0, PARAM(slot 0))`: CPython captures NOTHING, because `-1 >= 0` in
# Python AND `0 >= 0`, so the first conjunct of rule 1 refuses every PARAM in the
# backward slice. The two rows below are that conjunct's two-sided pair.
def pctx_aft_p0() -> String:
  +b = fx_alloc(0, False{})
  +p = fx_buf_param_on(O.Found.ar(b), 0)
  String.concat(["pctx_aft_p0=", pctx_of(FnCtx.of2(0), fx_aft(O.Found.ar(p), fn_u(b), fn_u(p)))])

# the SAME graph with the PARAM's slot at `4294967295`, i.e. `-1`. CPython STILL
# captures nothing: `p.arg.slot >= 0` is TRUE for `-1`, so the slot does not
# rescue the node. This row is the one that would catch a port that tested
# `slot == -1` here instead of `slot >= 0`.
def pctx_aft_m1() -> String:
  +b = fx_alloc(0, False{})
  +p = fx_buf_param_on(O.Found.ar(b), FN_NEG1())
  String.concat(["pctx_aft_4294967295=", pctx_of(FnCtx.of2(0), fx_aft(O.Found.ar(p), fn_u(b), fn_u(p)))])



# `AFTER(BUFFER, fresh ALLOC)`: CPython captures 1 node, and the captured node is
# `AFTER` -- which is only reachable if the AFTER is judged BEFORE its own srcs,
# because rule 0 would otherwise replace the BUFFER with a slot-0 PARAM and then
# rule 1's first conjunct would refuse. `fn_pm_ctx` walks the REVERSED toposort,
# so it answers `BUFFER`. BOTH are printed: `pctx_order` names the divergence
# rather than hiding it, because the order is the only thing that decides which
# of the two rules wins on this graph.
def pctx_aft_buf() -> String:
  +b = fx_buf(0, 4, Some{0})
  +f0 = fx_alloc.of(O.Found.ar(b), 1, False{})
  String.concat(["pctx_aft_buf=", pctx_of(FnCtx.of2(0), fx_aft(O.Found.ar(f0), fn_u(b), fn_u(f0)))])

# `AFTER(BUFFER, PARAM(slot 0))`: rule 1's FIRST conjunct refuses, because
# `p.arg.slot >= 0` holds for a slot-0 PARAM in the backward slice, so rule 0 alone
# fires and ONE node is captured. This row exists because M14 -- writing the test as
# `slot == -1`, which is the reading a reader assumes from the `is_implicit_storage`
# comment -- moved NOTHING while `pctx_aft_p0` and `pctx_aft_4294967295` were the only
# two rule-1 fixtures: for slot 0 the mutant refuses nothing and the second conjunct
# then fails, and for slot -1 both refuse. The fix is a fixture whose SECOND
# conjunct is TRUE, so the first one is the only thing that can refuse it.
def pctx_aft_slot0() -> String:
  +g = fx_buf(0, 4, Some{0})
  +p = fx_buf_param_on(O.Found.ar(g), 0)
  String.concat(["pctx_aft_slot0=", pctx_of(FnCtx.of2(0), fx_aft(O.Found.ar(p), fn_u(g), fn_u(p)))])

# ---- `backward_slice` vs `toposort`: exactly one node apart ------------------
# CPython's `backward_slice` is `toposort(enter_calls=False)` minus self
# (ops.py:278). A one-src node's slice is EMPTY and its toposort has 1, so the
# pair is what pins `fn_bslice`'s filter rather than its walk.
def bs_n() -> String:
  +b = fx_alloc(0, True{})
  +v = fx_inval(O.Found.ar(b))
  +k = fx_aft(O.Found.ar(v), fn_u(b), fn_u(v))
  String.concat(["bs_n=", U32.show(fn_ctx_n(fn_bslice(k))),
                 " bs_top=", U32.show(fn_ctx_n(O.UOp.toposort_nocalls(O.Arena.budget(O.Found.ar(k)), O.Found.ar(k), fn_u(k))))])

# ---- F: the two refusals, byte for byte -------------------------------------
# `type(ret)` for the two non-Tensor returns a traced body can produce. CPython:
#     function return type <class 'int'> not supported
def fn_ret_of(k: U32) -> FnRet:
  FnRet{k, 1}

def ret_int() -> String:
  String.concat(["ret_int=|", fn_ret_msg(fn_ret_of(0))])

# `NoneType`, the return of a body that fell off the end.
def ret_none() -> String:
  String.concat(["ret_none=|", fn_ret_msg(fn_ret_of(2))])

# The `allow_implicit=False` refusal. `ctx[0]` holds ONE caller-owned BUFFER (the
# argument) at index 0 and the rewrite APPENDED a second at index 1, so
# `num_explicit=1` and the TAIL is the appended node. CPython:
#     function f5 has 1 implicit buffer(s), but allow_implicit=False
#       0: dtype=dtypes.f32, size=4, device=None
def imp_one.of(+g: O.Found) -> String:
  String.concat(["imp_one=|", fn_implicit_msg.of([fn_u(g)], "f5", O.Found.ar(g))])

def imp_one() -> String:
  imp_one.of(fx_nbuf(0, 4))


# TWO implicit buffers, so the NUMBERED LINES and their ORDER are pinned -- and
# that is the part `enumerate` gets wrong first. CPython:
#     function f5 has 2 implicit buffer(s), but allow_implicit=False
#       0: dtype=dtypes.f32, size=4, device=None
#       1: dtype=dtypes.f32, size=4, device=None
def imp_two.of(+g0: O.Found, +g1: O.Found) -> String:
  String.concat(["imp_two=|", fn_implicit_msg.of([fn_u(g0), fn_u(g1)], "f5", O.Found.ar(g0))])

def imp_two() -> String:
  imp_two.of(fx_nbuf(0, 4), fx_nbuf(1, 4))


# THE REFUSAL SET IS THE TAIL, NOT THE HEAD. With `num_explicit=0` on a ctx
# holding one buffer the whole list is implicit; with `num_explicit=1` it is
# empty. CPython's `call_uops[num_explicit:]` is a slice on a list the rewrite
# has ALREADY GROWN, and this row is that slice -- a port reading
# `call_uops[:num_explicit]` would print `1/1` here and `0` in every other row.
def imp_tail.of2(+g: O.Found, +c: FnCtx) -> String:
  String.concat(["imp_tail=", U32.show(fn_ctx_n(fn_implicit_bufs(O.Found.ar(g), c, 0))),
                 "/", U32.show(fn_ctx_n(fn_implicit_bufs(O.Found.ar(g), c, 1)))])

def imp_tail.of(+g: O.Found) -> String:
  imp_tail.of2(g, fn_add(O.Found.ar(g), FnCtx{Nil{}, Nil{}, 0, False{}, 0}, fn_u(g)))

def imp_tail() -> String:
  imp_tail.of(fx_nbuf(0, 4))



# ---- G: `_function.depth` entering and being RESTORED -----------------------
# CPython: `_function.depth` is 0 before the call and 0 after it, and 2 inside
# two nested `@function`s. `dep_exit` is the row that says the `finally` runs --
# a port that leaked the depth would still pass `dep_enter`.
def dep_enter() -> String:
  String.concat(["dep_enter=", U32.show(Fn.depth(fn_enter(Fn.of())))])

def dep_exit() -> String:
  String.concat(["dep_exit=", U32.show(Fn.depth(fn_exit(fn_enter(Fn.of()))))])

# TWO INSTANCES SHARE ONE COUNTER, which is what the CLASS-level field means. The
# value is read off a DIFFERENT `Fn` than the one entered, so a port that stored
# the depth per instance would answer 1.
def dep_shared.of3(a: Fn, b: Fn) -> Fn:
  fn_exit(a)

def dep_shared.of2(a: Fn, b: Fn) -> Fn:
  dep_shared.of3(fn_enter(a), b)

def dep_shared.of(a: Fn, b: Fn) -> Fn:
  dep_shared.of2(fn_enter(a), b)

def dep_shared() -> String:
  String.concat(["dep_shared=", U32.show(Fn.depth(dep_shared.of(Fn.of(), Fn.of())))])




# function.py:101-113. BOTH SPELLINGS, and the difference is which argument is
# `None`: `@function` passes the function, `@function(...)` passes `None` and
# answers a lambda that takes it. The lambda is the WALL -- no function values in
# Bend -- so the two spellings build the SAME `Fn` and `fac_same` is the row that
# says so, which is Python's own `if fxn is None` in one comparison.
def function_(precompile: Bool, precompile_backward: Bool, allow_implicit: Bool) -> Fn:
  Fn{precompile, precompile_backward, allow_implicit, 0}

def function.curried(precompile: Bool, precompile_backward: Bool, allow_implicit: Bool) -> Fn:
  function_(precompile, precompile_backward, allow_implicit)

# ---- H: both decorator spellings -------------------------------------------
# `@function` and `@function(...)` build the SAME `Fn` from the same flags.
# CPython: `function(f, precompile=True)` and `function(precompile=True)(f)` have
# equal `(precompile, precompile_backward, allow_implicit, grad_fxn)`.
# EQUALITY AND NOT CONJUNCTION. The flags are `False` by default, so a
# conjunction of two `Fn`s compares "both have precompile" and answers `False` for
# two IDENTICAL `Fn`s -- which is the shape of the `flipped Bool.pick` defect in
# `renderer/wgsl.bend`. `Bool.eq` is the predicate; `Bool.and` is not, and the two
# differ on every row whose expected answer is 0.
def fac_eq.pair(x: Bool, y: Bool) -> Bool:
  Bool.pick(Bool, Bool.xor(x, y), False{}, True{})

def fac_eq.of(+a: Fn, +b: Fn) -> Bool:
  Bool.and(fac_eq.pair(Fn.precompile(a), Fn.precompile(b)),
           fac_eq.pair(Fn.allow_implicit(a), Fn.allow_implicit(b)))

def fac_eq(a: Fn, b: Fn) -> Bool:
  fac_eq.of(a, b)

def fac_same() -> String:
  String.concat(["fac_same=", bshow(fac_eq(function_(True{}, False{}, False{}),
                                         function.curried(True{}, False{}, False{})))])

# the flags themselves, so a port that SHUFFLED the four columns moves this row
# and not `fac_same` (which compares like with like)
def fac_flags() -> String:
  String.concat(["fac_flags=", bshow(Fn.precompile(function_(True{}, False{}, True{}))),
                 bshow(Fn.allow_implicit(function_(True{}, False{}, True{})))])

# a FRESH instance's depth is 0 even after another was entered and left, because
# the counter is CLASS state and the class is at zero again
def fac_fresh() -> String:
  String.concat(["fac_fresh=", U32.show(Fn.depth(function_(False{}, False{}, False{})))])

# THE PAIR THAT DIFFERS, and `fac_same` alone could not see M16: two `Fn`s with
# `precompile=True` and `precompile=False` are UNEQUAL, and a comparison written as
# a conjunction answers `True` for the `True` half alone. `fac_same` compares two
# IDENTICAL `Fn`s, where conjunction and equality agree -- which is the
# "a mutation that moves nothing is information about the GATE" case, twice over.
def fac_diff() -> String:
  String.concat(["fac_diff=", bshow(fac_eq(function_(True{}, False{}, False{}),
                                         function_(False{}, False{}, False{})))])

# ---- I: `dedup` keeping the FIRST occurrence -------------------------------
# CPython: `dedup([BUFFER, ALLOC, BUFFER])` has length 2 and is `BUFFER|ALLOC`.
def callu_ops.of3(+g: O.Found, +xs: List<&2, U32>, n: U32) -> String:
  String.concat(["callu_ops=", U32.show(n), "/",
                 ctx_ops(O.Found.ar(g), FnCtx{xs, Nil{}, 0, False{}, 0})])

def callu_ops.of2(+g: O.Found, +xs: List<&2, U32>) -> String:
  callu_ops.of3(g, xs, U32.from_nat(List.length(&2, U32, xs)))

def callu_ops.of(+g: O.Found) -> String:
  callu_ops.of2(g, fn_call_uops([fn_u(g), 7, fn_u(g)]))

def callu_ops() -> String:
  callu_ops.of(fx_buf(0, 4, Some{0}))




# ---- J: the DEBUG print's indent and name ----------------------------------
# CPython: `"  "*depth + f"function {key[:8]} in {ms:8.2f} ms: {name}"`. The key
# and the clock are seams, so they are PARAMETERS here and the row pins the two
# parts that are pure functions of the port's own state.
def trace0() -> String:
  String.concat(["trace0=|", fn_trace(0, 3735928559, 12, "f5")])

def trace2() -> String:
  String.concat(["trace2=|", fn_trace(2, 3735928559, 12, "f5")])

# THE NAME FALLBACK: `getattr(self.fxn, '__qualname__', None) or
# type(self.fxn).__qualname__`. Two-sided, because a port that dropped the `or`
# would answer the wrong string for a callable with no `__qualname__`.
def fn_name_row() -> String:
  String.concat(["fn_name=", fn_name(True{}, "f5", "fn"), "/", fn_name(False{}, "f5", "<lambda>")])

# THE TABLE, so the two op TUPLES are in the output and a rule that lost an op is
# visible without reading the source. CPython: `0:BUFFER/ALLOC/PARAM 1:AFTER/STAGE`.
def pctx_tablerow() -> String:
  String.concat(["pctx_table=", pctx_table()])

# THE TEMPLATE, so `FnCtx`'s three fields are in the output too.
def ctx_row() -> String:
  String.concat(["ctx_empty=", U32.show(FnCtx.n(FnCtx.of2(0))),
                 " ctx_start=", U32.show(FnCtx.start(FnCtx.of2(7)))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(pctx_tablerow())
    IO.print(iis_buf())
    IO.print(iis_alloc_lt())
    IO.print(iis_alloc_ge())
    IO.print(iis_alloc_far())
    IO.print(iis_alloc_nobor())
    IO.print(iis_var_m1())
    IO.print(iis_var_p0())
    IO.print(iis_var_novmin())
    IO.print(iis_var_1d())
    IO.print(iis_var_reg())
    IO.print(iis_const())
    IO.print(iis_param_buf())
    IO.print(add_first())
    IO.print(add_refused())
    IO.print(inv_one())
    IO.print(inv_ok())
    IO.print(inv_two())
    IO.print(inv_real())
    IO.print(inv_notstore())
    IO.print(renum_one())
    IO.print(renum_two())
    IO.print(renum_gap())
    IO.print(pctx_buf())
    IO.print(pctx_fresh())
    IO.print(pctx_add01())
    IO.print(pctx_add10())
    IO.print(pctx_aft_p0())
    IO.print(pctx_aft_m1())
    IO.print(pctx_aft_buf())
    IO.print(pctx_aft_slot0())
    IO.print(bs_n())
    IO.print(imp_tail())
    IO.print(imp_one())
    IO.print(imp_two())
    IO.print(ret_int())
    IO.print(ret_none())
    IO.print(dep_enter())
    IO.print(dep_exit())
    IO.print(dep_shared())
    IO.print(fac_same())
    IO.print(fac_flags())
    IO.print(fac_fresh())
    IO.print(fac_diff())
    IO.print(callu_ops())
    IO.print(trace0())
    IO.print(trace2())
    IO.print(fn_name_row())
    IO.print(ctx_row())

# ===========================================================================
# SECTION L -- THE MEASURED MUTATION TABLE.
#
# Run: `python3 <oracle-dir>/fn/mutate.py`, which writes each edit to
# `tinybendygrad/_mut_tmp.bend`, re-checks, re-runs, and diffs the rows. Every
# mutation below was MEASURED on 2026-10-02, not asserted. `moved == 0` on live
# code means a MISSING ROW, and two rows below were added because a mutation moved
# nothing.
#
# | id | mutation | rows moved |
# | --- | --- | --- |
# | M1 | `add_to_ctx` refuses on `ctx[0]` instead of `ctx[1]` | **2** `add_first` `add_refused` |
# | M2 | the ALLOC arm drops `bind_on_realize` | 1 `iis_alloc_nobor` |
# | M3 | the ALLOC arm uses `<=` not `<` | 1 `iis_alloc_ge` |
# | M4 | `is_variable` drops `_shape == ()` | 1 `iis_var_1d` |
# | M5 | `is_variable` drops `addrspace is ALU` | 1 `iis_var_reg` |
# | M6 | `is_variable` drops `vmin_vmax is not None` | 1 `iis_var_novmin` |
# | M7 | `renumber` counts the WHOLE toposort | 2 `renum_two` `renum_gap` |
# | M8 | `add_to_ctx` appends on the REFUSAL arm | **6** `add_first` `add_refused` `imp_tail` `pctx_buf` `pctx_aft_buf` `pctx_aft_slot0` |
# | M9 | the `num_explicit:` slice becomes a whole-list filter | 1 `imp_tail` |
# | M10 | `dedup` PREPENDS instead of appending | 1 `callu_ops` |
# | M11 | `invalid_outputs` drops `not is_realized` | 1 `inv_real` |
# | M12 | `invalid_outputs` drops `op is STORE` | 1 `inv_notstore` |
# | M13 | rule 0's op TUPLE loses `PARAM` | 1 `pctx_table` |
# | M14 | rule 1 tests `slot == -1` not `slot >= 0` | 1 `pctx_aft_slot0` |
# | M15 | `fn_exit` does not restore the depth | 2 `dep_exit` `dep_shared` |
# | M16 | `fac_same` compares by CONJUNCTION | 1 `fac_diff` |
# | M17 | the DEBUG trace drops the depth indent | 1 `trace2` |
# | M18 | the `__qualname__` fallback is dropped | 1 `fn_name` |
# | M19 | the refusal message drops the `dtypes.` prefix | 2 (`imp_one` `imp_two`) |
# | M20 | the per-buffer line drops its index | 2 (`imp_one` `imp_two`) |
#
# TWO MUTATIONS MOVED NOTHING AT FIRST, and BOTH ARE THE SAME LESSON.
#
# **M14** (`slot == -1` instead of `slot >= 0`) moved nothing over the two rule-1
# fixtures that existed. For slot `0` the mutant stops refusing, and then the SECOND
# conjunct fails because the rest of the graph holds nothing implicit; for slot `-1`
# both spellings refuse. So the two fixtures were both refused for different
# reasons and neither could see the difference. The fix is `pctx_aft_slot0`, whose
# slice holds a caller-owned BUFFER, so the SECOND conjunct is TRUE and the first is
# the only thing that can refuse it -- "put the decision in a parameter and make the
# other conjunct vacuously true" is the same sentence the notes reach for a fold.
#
# **M16** (conjunction for equality) moved nothing over `fac_same`, which compares
# two IDENTICAL `Fn`s where the two spellings agree. The fix is `fac_diff`, a pair
# that DIFFERS. A comparison row needs a positive and a negative case; a comparison
# of two equal values is a restatement of the reader, which is the thing the gate
# exists to prevent.
#
# M8 IS THE BLAST-RADIUS ROW: one inverted `Bool.pick` in `add_to_ctx` moves six
# rows across three row CLASSES (`add_*`, `imp_*`, `pctx_*`), because `add_to_ctx` is
# reached from the capture, from the refusal filter and from the rule table. The
# notes' "a shared predicate has a shared blast radius" is measured here rather than
# quoted.
#
# AND THE ROWS THAT ARE **NOT** COVERED BY ANY MUTATION, which is the honest
# negative list. `pctx_aft_buf`'s captured COUNT is the one number in this gate that
# is KNOWN to disagree with CPython (`bot=2` where CPython answers 1), and no
# mutation here can move it: the divergence is the `param_like`/`substitute` seam --
# CPython's `add_to_ctx` REPLACES the node, so a later rule 0 sees a slot-0 PARAM
# and refuses, while the port answers the flag and grows the list. That is a
# consequence of the seam list in Section I and it is not fixable in this file.
# `bs_n`, `ctx_row` and `dep_enter`/`fac_fresh` are structural rows with no live
# predicate behind them, and they are labelled as such rather than counted as
# coverage.
