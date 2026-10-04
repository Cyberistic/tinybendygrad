# spec.bend -- tinygrad/uop/spec.py. The graph VALIDATOR: six rule tables, three
# helpers, and `type_verify`.
#
# WHAT THIS FILE IS. `spec.py` is not a rewriter. It answers, for ONE node, "is
# this node legal in the graph I am validating", and it does that with the SAME
# machinery `ops.py` uses to rewrite a graph: a `PatternMatcher` is a table of
# `(UPat, lambda)` pairs and `rewrite` returns the FIRST non-`None`. So every rule
# here is a top-level def and every table is a list of tags, which is the compiled
# form `upat.py` emits -- see `ops.bend`'s `pm_rewrite`.
#
# THE ANSWER IS THREE-VALUED. Python's rule bodies return `True`, `False`, or
# `None`, and `None` means "this rule has no opinion, keep scanning":
#
#     ret = check_spec.rewrite(uop)          # spec.py:42
#     if ret is not True: raise RuntimeError
#
# so `VTrue` is the only passing answer and BOTH `VFalse` and `VSkip` fail. They are
# not the same: the fold is FIRST-WINS, so a `VFalse` stops the scan and a `VSkip`
# lets the next rule try, and getting it backwards refuses the node for the wrong
# reason without the accepting rule ever running.
#
# WHY SIX DISPATCHES. `spec.py` has six tables, each its own `PatternMatcher`, and
# `ops.bend` cannot call a def in this file, so each gets its own dispatch and its
# own scan: `sh_*`, `te_*`, `pr_*`, `hq_*`, `fu_*`, `kg_*`. A generic dispatch needs
# a closure, and a closure cannot be a `Data` field, so the ~5 lines of driver per
# table are duplicated six times rather than abstracted.
#
# WHAT IS SHARED AND WHAT IS NOT. Shared: the property readers (`sp_*`), the
# `early_reject` subset test, the op-set membership test, and the `ler` fold --
# none dispatch on a tag, so one copy is right. Duplicated per table: `try`, `go`,
# `scan`, `rewrite`, `dispatch`, the table, and the verifier fold.
#
# THE TAG SPACES ARE PER TABLE, starting at 0, and each rule carries its `spec.py`
# line. `spec_tensor` and friends are `PatternMatcher(...) + spec_shared`, so a tag
# means "(table, index in THAT table's own list)" -- see the `+` composition note on
# `fu_table`.
#
# ---------------------------------------------------------------------------
# TWO FACTS THAT ARE EASY TO INVERT, both measured against `spec.py`.
#
# 1. `early_reject` IS A NECESSARY CONDITION, not a veto, despite the name:
#    `ops.py:1617` is `if not early_reject.issubset(ler): continue`, so the rule
#    FIRES when the op set IS a subset of `ler`, and an empty set is a subset of
#    everything, which is why most rules always fire. It is built from the ops of
#    the pattern's FIRST src (`ops.py:1483`), and for a pattern whose first src is
#    an `is_any` the ops are `None` and the set is empty. `spec.py`'s four
#    non-empty sets -- `sh_15`, `te_18`..`te_21`, `pr_7`, `kg_2` -- are every one
#    already implied by the rule's own src-op test, so the `backedge_ok` and
#    `prog4_ok` rows exist to catch a MISSPELLED set, which would silently skip a
#    rule that should have fired.
#
# 2. A NAME BOUND TWICE MUST EMIT AN IDENTITY CHECK (`upat.py:100-105` builds it
#    as a literal `"{0} is {1}"`, and `mixin/gradient.py:101` and
#    `schedule/__init__.py:182` both depend on it). The only name bound twice in
#    THIS file is `uidx`, in `sh_27`..`sh_30`, and both bindings are in the two
#    ALTERNATIVES of one `is_any` -- `is_any` copies the store per alternative, so
#    they never meet and no `is` is emitted. Adding one would be a bug: it would
#    turn `LOAD(INDEX(...))` and `LOAD(CAST(INDEX(...)))` into a conjunction. The
#    rows `hcq_plain` and `hcq_after` are the two-sided check.
# ---------------------------------------------------------------------------

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F
# ===========================================================================
# THE TWO-ARM TURNING WHEEL.
#
# `sp_tri` is `C if b else None`, the only shape in `spec.py` that produces a
# non-`Bool` answer, and `sp_vd` turns the tri-state into a verdict. `VSkip` is
# the honest spelling of Python's `None`: the fold is first-wins, so a `VFalse`
# where Python wrote `None` would stop the scan and the rule that was supposed to
# accept the node would never run.
# ===========================================================================
def sp_tri.of(b: Bool, v: Bool) -> Maybe<&1, Bool>:
  match b:
    case True{}: Some{v}
    case False{}: None{}

def sp_tri(b: Bool, v: Bool) -> Maybe<&1, Bool>:
  sp_tri.of(b, v)

def sp_vd.go(m: Maybe<&1, Bool>) -> O.Verdict:
  match m:
    case Some{True{}}: O.VTrue{}
    case Some{False{}}: O.VFalse{}
    case None{}: O.VSkip{}

def sp_vd(m: Maybe<&1, Bool>) -> O.Verdict:
  sp_vd.go(m)

def show_v.go(v: O.Verdict) -> U32:
  match v:
    case O.VTrue{}: 1
    case O.VFalse{}: 0
    case O.VSkip{}: 9

def show_v(v: O.Verdict) -> U32:
  show_v.go(v)

# ===========================================================================
# THE PROPERTY READERS. Every one of them is a read of the FOLD, not of the node,
# because a node's dtype/shape/device/base/addrspace are derived properties and
# `fold.bend` is the only well-founded way to answer them: Bend refuses the mutual
# recursion Python breaks with `recursive_property`'s memo (ops.py:218).
#
# A `Data` record parameter is NOT implicitly copyable -- two reads of `fx` in one
# expression need `+fx`, exactly like a `List`.
# ===========================================================================
def sp_ar(fx: F.Folded) -> O.Arena: F.Folded.ar(fx)

def sp_tb(fx: F.Folded) -> F.Table: F.Folded.t(fx)

def sp_dt(+fx: F.Folded, self: U32) -> Maybe<&2, S.Dt>:
  F.fold.dt(sp_ar(fx), sp_tb(fx), self)

def dt_eq.go(m: Maybe<&2, S.Dt>, want: S.Dt) -> Bool:
  match m:
    case Some{d}: O.eq_dt(d, want)
    case None{}: False{}

def dt_eq(m: Maybe<&2, S.Dt>, want: S.Dt) -> Bool:
  dt_eq.go(m, want)

def sp_dt_is(+fx: F.Folded, self: U32, want: S.Dt) -> Bool:
  dt_eq(sp_dt(fx, self), want)

# `dtypes.weaks` -- tinygrad/dtype.py:160 -- is `(weakint, weakfloat)`, and the only two
# members of `Cls` that are neither concrete-signed nor concrete-unsigned.
def weak_cls.go(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_cls.go(m: Maybe<&2, S.Dt>) -> S.Cls:
  match m:
    case Some{d}: S.Dt.cls(d)
    case None{}: S.CVoid{}

def dt_cls(m: Maybe<&2, S.Dt>) -> S.Cls:
  dt_cls.go(m)

def weak_dt(m: Maybe<&2, S.Dt>) -> Bool:
  weak_cls.go(dt_cls(m))

def sp_is_weak(+fx: F.Folded, self: U32) -> Bool:
  weak_dt(sp_dt(fx, self))

def dt_float.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: S.Dt.is_float(d)
    case None{}: False{}

def dt_float(m: Maybe<&2, S.Dt>) -> Bool:
  dt_float.go(m)

def sp_is_float(+fx: F.Folded, self: U32) -> Bool:
  dt_float(sp_dt(fx, self))

def dt_int.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: S.Dt.is_int(d)
    case None{}: False{}

def dt_int(m: Maybe<&2, S.Dt>) -> Bool:
  dt_int.go(m)

def sp_is_int(+fx: F.Folded, self: U32) -> Bool:
  dt_int(sp_dt(fx, self))

# `x.shape == ()` -- `spec.py:90`, the ONLY line in spec.py that writes it. The
# fold's shape is a double `Maybe`: the outer is "the table has no entry", the inner
# is ops.py's `_shape` returning `None` for a node that has no shape at all.
def shp_of.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case None{}: None{}

def shp_of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  shp_of.go(m)

def sp_shape(+fx: F.Folded, self: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  F.fold.shape(sp_ar(fx), sp_tb(fx), self)

def shp_empty.go(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{Nil{}}: True{}
    case _: False{}

def shp_empty(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  shp_empty.go(m)

def sp_is_scalar(+fx: F.Folded, self: U32) -> Bool:
  shp_empty(shp_of(sp_shape(fx, self)))

# `x.shape == y.shape`, which is `spec.py:165` and `spec.py:184`'s `all_same`.
def sp_shape_same.go(a: Maybe<&2, List<&2, O.Sint>>, b: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match a b:
    case Some{x} Some{y}: F.eq_sints(x, y)
    case _ _: False{}

def sp_shape_same(+fx: F.Folded, j: U32, k: U32) -> Bool:
  sp_shape_same.go(shp_of(sp_shape(fx, j)), shp_of(sp_shape(fx, k)))

# `x.base` -- ops.py:782. `Some{b}` is the node `base` resolves to.
def sp_base(+fx: F.Folded, self: U32) -> Maybe<&1, U32>:
  F.fold.base(sp_ar(fx), sp_tb(fx), self)

# `x.is_invalid` -- ops.py:265, `self.op is Ops.CONST and self.val is Invalid`.
# The fold is not consulted: the test is on the node's OWN arg, which is why this
# reader is total where `sp_base` is not.
def is_invalid_of(a: O.Arg, op: O.Op) -> Bool:
  match a op:
    case O.APy{O.CInvalid{}} O.OpsCONST{}: True{}
    case _ _: False{}

def is_invalid_at(+ar: O.Arena, +self: U32) -> Bool:
  is_invalid_of(O.Arena.arg(ar, self), O.Arena.op(ar, self))

def sp_is_invalid(fx: F.Folded, self: U32) -> Bool:
  is_invalid_at(sp_ar(fx), self)

def sp_base_invalid.pick(b: Maybe<&1, U32>, ar: O.Arena) -> Bool:
  match b:
    case Some{i}: is_invalid_at(ar, i)
    case None{}: False{}

def sp_base_invalid.of(b: Maybe<&1, U32>, ar: O.Arena) -> Bool:
  sp_base_invalid.pick(b, ar)

# `x.base.is_invalid` -- `matches_dtype` (spec.py:47) and four rule bodies. A node
# the fold has not answered has no base, and the test is then False.
def sp_base_invalid(+fx: F.Folded, self: U32) -> Bool:
  sp_base_invalid.of(sp_base(fx, self), sp_ar(fx))

def sp_md.go(same: Bool, base_bad: Bool) -> Bool:
  Bool.or(same, base_bad)

# `matches_dtype(x, dt)` -- spec.py:47, spelled out once and reused by every rule
# that says it. `x.dtype == dt or x.base.is_invalid`.
def sp_md(+fx: F.Folded, +self: U32, want: S.Dt) -> Bool:
  sp_md.go(sp_dt_is(fx, self, want), sp_base_invalid(fx, self))

def sp_mdw.go(same: Bool, weak: Bool) -> Bool:
  Bool.or(same, weak)

# `matches_dtype(x, dt) or x.dtype in dtypes.weaks` -- spec.py:62, :67, :75.
def sp_mdw(+fx: F.Folded, +self: U32, want: S.Dt) -> Bool:
  sp_mdw.go(sp_md(fx, self, want), sp_is_weak(fx, self))

def sp_dev(+fx: F.Folded, self: U32) -> Maybe<&2, Maybe<&2, S.Dev>>:
  F.fold.device(sp_ar(fx), sp_tb(fx), self)

def dev_of.go(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{d}: d
    case None{}: None{}

def dev_of(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  dev_of.go(m)

def sp_addr(+fx: F.Folded, self: U32) -> Maybe<&2, Maybe<&2, S.Addr>>:
  F.fold.addr(sp_ar(fx), sp_tb(fx), self)

def addr_of.go(m: Maybe<&2, Maybe<&2, S.Addr>>) -> Maybe<&2, S.Addr>:
  match m:
    case Some{d}: d
    case None{}: None{}

def addr_of(m: Maybe<&2, Maybe<&2, S.Addr>>) -> Maybe<&2, S.Addr>:
  addr_of.go(m)

def addr_eq.go(got: Maybe<&2, S.Addr>, want: S.Addr) -> Bool:
  match got:
    case Some{a}: O.eq_addr(a, want)
    case None{}: False{}

def addr_eq(got: Maybe<&2, S.Addr>, want: S.Addr) -> Bool:
  addr_eq.go(got, want)

def sp_nsrc(+fx: F.Folded, self: U32) -> U32:
  O.Arena.nsrc(sp_ar(fx), self)

def nsrc_is(+fx: F.Folded, self: U32, n: U32) -> Bool:
  U32.is_eq(sp_nsrc(fx, self), n)

# `sp_arg` exists so the eighteen-way `Arg` match below is one def per question
# rather than a match inside every rule that asks one.
def sp_arg(+fx: F.Folded, self: U32) -> O.Arg:
  O.Arena.arg(sp_ar(fx), self)

def arg_dt.go(a: O.Arg) -> Bool:
  match a:
    case O.ADt{dt}: True{}
    case _: False{}

# ===========================================================================
# THE `Arg` QUESTIONS. `spec.py` asks `isinstance(x.arg, ...)` about eight
# different Python types, and `Arg` already names all eighteen, so each question
# is one constructor arm and the wall is gone: there is no `isinstance`, only a
# `match` the compiler checks against the full set.
# ===========================================================================
# `isinstance(x.arg, DType)` -- spec.py:79. `ADt` IS the DType arm.
def arg_dt(a: O.Arg) -> Bool:
  arg_dt.go(a)

def arg_str.go(a: O.Arg) -> Bool:
  match a:
    case O.AStr{s}: True{}
    case _: False{}

# `isinstance(x.arg, str)` -- spec.py:161, :224, :236. At THE PIN this list was five
# long and started at :110; at HEAD :110 reads `isinstance(x.arg, CustomFunction)`
# and the CUSTOM_FUNCTION rule that was at :161 in `spec_tensor` is deleted, so
# `arg_str` is a SPECIAL and REWRITE_ERROR question and nothing else. The pin's
# numbers are kept because this file is a pin port everywhere `sh_22` is not.
def arg_str(a: O.Arg) -> Bool:
  arg_str.go(a)

def arg_customfunction.go(a: O.Arg) -> Bool:
  match a:
    case O.ACustom{cf}: True{}
    case _: False{}

# `isinstance(x.arg, CustomFunction)` -- spec.py:110. `ACustom` IS that class and it
# is the only constructor that is, so the whole body is one arm. `cf` is bound and
# not read because the question is the TYPE, not the value -- CPython measured
# `CustomFunction("f") == CustomFunction("g", dtypes.uint64)` as False, so the value
# distinguishes but the rule does not ask about it.
def arg_customfunction(a: O.Arg) -> Bool:
  arg_customfunction.go(a)

def arg_blob.go(a: O.Arg) -> Bool:
  match a:
    case O.ABlob{n}: True{}
    case _: False{}

# `isinstance(x.arg, bytes)` -- spec.py:96. Only the length is ever read, and
# `ABlob` carries it.
def arg_blob(a: O.Arg) -> Bool:
  arg_blob.go(a)

def arg_none.go(a: O.Arg) -> Bool:
  match a:
    case O.ANone{}: True{}
    case _: False{}

# `x.arg is None` -- spec.py:86, :88, :89, :113, :242, :243.
def arg_none(a: O.Arg) -> Bool:
  arg_none.go(a)

def arg_const_invalid.go(a: O.Arg) -> Bool:
  match a:
    case O.APy{O.CInvalid{}}: True{}
    case _: False{}

# `x.arg == Invalid` -- spec.py:217, on a CONST. The whole check.
def arg_const_invalid(a: O.Arg) -> Bool:
  arg_const_invalid.go(a)

def arg_axis.go(a: O.Arg) -> Maybe<&1, O.AxisType>:
  match a:
    case O.ARange{ids, at}: Some{at}
    case _: None{}

# `int(rng.arg[-1])`... no: `isinstance(rng.arg[-1], AxisType)` -- spec.py:82.
# `ARange` is Python's `(axis_id, axis_type)` tuple already split, so the axis
# type IS a field and the whole of spec.py:81-82's lambda is this arm plus a
# non-empty `ids`.
def arg_axis(a: O.Arg) -> Maybe<&1, O.AxisType>:
  arg_axis.go(a)

def arg_ids.go(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ARange{ids, at}: Some{ids}
    case _: None{}

# spec.py:81's `len(rng.arg) >= 2` -- the tuple is `(ids..., axis_type)`, so the
# tuple is at least 2 long exactly when there is at least one axis id.
def arg_ids(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  arg_ids.go(a)

def arg_ink.go(a: O.Arg) -> Bool:
  match a:
    case O.AInk{ins, dt}: True{}
    case _: False{}

# `isinstance(x.arg, tuple) and len(x.arg) == 2 and isinstance(x.arg[0], str)
# and isinstance(x.arg[1], DType)` -- spec.py:107, and spec.py:122's same shape
# without the `arg[0]` half. `AInk` IS that pair, and it is the only constructor
# that is.
def arg_ink(a: O.Arg) -> Bool:
  arg_ink.go(a)

def arg_wmma.go(a: O.Arg) -> Bool:
  match a:
    case O.AWmma{dims, dt, threads, tc}: True{}
    case _: False{}

# `isinstance(x.arg, tuple) and len(x.arg) == 4` -- spec.py:137, WMMA's
# `(dims, DType, threads, tc_upcast_axes)`.
def arg_wmma(a: O.Arg) -> Bool:
  arg_wmma.go(a)

def arg_call.go(a: O.Arg) -> Maybe<&2, S.Dt>:
  match a:
    case O.ACall{ci}: Some{O.CallInfo.dtype(ci)}
    case _: None{}

# `isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype` -- spec.py:113. The
# `isinstance` half is the arm; the `dtype is` half is the comparison below.
def arg_call(a: O.Arg) -> Maybe<&2, S.Dt>:
  arg_call.go(a)

def arg_param.go(a: O.Arg) -> Maybe<&1, O.ParamArg>:
  match a:
    case O.AParam{pa}: Some{pa}
    case _: None{}

# `isinstance(x.arg, ParamArg)` -- spec.py:93, :148, :151, :158, :217, :264,
# :265, :267. One arm, and it hands back the payload every one of those rules
# then reads.
def arg_param(a: O.Arg) -> Maybe<&1, O.ParamArg>:
  arg_param.go(a)

def arg_reduce_op.go(a: O.Arg) -> Maybe<&1, O.Op>:
  match a:
    case O.AReduce{rop, num_axes}: Some{rop}
    case _: None{}

# `isinstance(red.arg, tuple) and len(red.arg) == 2 and red.arg[0] in
# GroupOp.Reduce` -- spec.py:169, :176. `AReduce` is that pair.
def arg_reduce_op(a: O.Arg) -> Maybe<&1, O.Op>:
  arg_reduce_op.go(a)

def arg_allred_dev.go(a: O.Arg) -> Maybe<&2, S.Dev>:
  match a:
    case O.AAllred{rop, dev}: Some{dev}
    case _: None{}

# `isinstance(red.arg, tuple) and len(red.arg) == 2 and is_device(red.arg[1])` --
# spec.py:177. `AAllred` is that pair.
def arg_allred_dev(a: O.Arg) -> Maybe<&2, S.Dev>:
  arg_allred_dev.go(a)

def arg_dev.go(a: O.Arg) -> Maybe<&2, S.Dev>:
  match a:
    case O.ADev{dev}: Some{dev}
    case _: None{}

# `is_device(x.arg)` where the arg IS the device -- spec.py:174 (`COPY`),
# :230 (`GETADDR`). `ADev` is exactly `str|tuple[str, ...]`.
def arg_dev(a: O.Arg) -> Maybe<&2, S.Dev>:
  arg_dev.go(a)

def arg_tuple.go(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ATuple{ys}: Some{ys}
    case _: None{}

# `x.arg` for UNSHARD is `tuple[int, ...]` of sharding axes (spec.py:184) and for
# MSELECT it is the single device index (spec.py:186); both are `ATuple`.
def arg_tuple(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  arg_tuple.go(a)

def arg_const_int.of(a: O.Arg) -> Maybe<&2, H.I64>:
  match a:
    case O.APy{O.CInt{i}}: Some{i}
    case _: None{}

# `int(x.val)` for the CONST bound spec.py:186's `x.arg < len(...)` reads, and
# the RANGE end spec.py:33's `int(rng.vmax)` reduces to (see `valid_device_range`).
def arg_const_int(a: O.Arg) -> Maybe<&2, H.I64>:
  arg_const_int.of(a)

# ===========================================================================
# THE FOLDS OVER A NODE'S SRCS. One def each, threaded `Bool` accumulator, self-call
# on the TAIL. Python's `all(... for s in u.src)` and `any(...)` become the same
# shape here; there is no early exit, which is a cost and not a semantic change.
# ===========================================================================
def all_void(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_void(t, fx, Bool.and(acc, sp_dt_is(fx, s, S.void())))

def any_float(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_float(t, fx, Bool.or(acc, sp_is_float(fx, s)))

def any_base_invalid(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_base_invalid(t, fx, Bool.or(acc, sp_base_invalid(fx, s)))

def all_mdw(srcs: List<&2, U32>, +fx: F.Folded, +want: S.Dt, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_mdw(t, fx, want, Bool.and(acc, sp_mdw(fx, s, want)))

def sp_int_or_bad(+fx: F.Folded, +s: U32) -> Bool:
  Bool.or(sp_is_int(fx, s), sp_base_invalid(fx, s))

def all_int_or_base_invalid(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_int_or_base_invalid(t, fx, Bool.and(acc, sp_int_or_bad(fx, s)))

def all_int(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_int(t, fx, Bool.and(acc, sp_is_int(fx, s)))

def sp_range_int(+fx: F.Folded, +s: U32) -> Bool:
  Bool.and(O.op_is(sp_ar(fx), s, O.OpsRANGE{}), sp_is_int(fx, s))

# `u.op is Ops.RANGE and dtypes.is_int(u.dtype)` -- spec.py:86.
def all_range_int(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_range_int(t, fx, Bool.and(acc, sp_range_int(fx, s)))

def any_const(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_const(t, fx, Bool.or(acc, O.op_is(sp_ar(fx), s, O.OpsCONST{})))

# `O.op_is` generalised to an op SET, for the two rules that ask `x.op in (...)`.
def sp_op_in(+fx: F.Folded, s: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, O.Arena.op(sp_ar(fx), s))

def sp_const_or_param(+fx: F.Folded, s: U32) -> Bool:
  sp_op_in(fx, s, [O.OpsCONST{}, O.OpsPARAM{}])

def all_const_or_param(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_const_or_param(t, fx, Bool.and(acc, sp_const_or_param(fx, s)))

# `all_same(x.src)` -- helpers.py, on NODE INDICES. tinygrad compares UOp objects
# and UOp equality IS identity, so the index comparison is the same test. Python's
# `all_same([])` is True and then `x.src[0]` raises, so an EMPTY src has no answer
# and `mstack_body` skips rather than inventing a src[0].
def all_same(srcs: List<&2, U32>, +head: U32, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_same(t, head, Bool.and(acc, U32.is_eq(s, head)))

def all_same_head.go(srcs: List<&2, U32>) -> U32:
  match srcs:
    case s <> t: s
    case _: 0

def all_same_head(srcs: List<&2, U32>) -> U32:
  all_same_head.go(srcs)

def shp_len_is(srcs: List<&2, U32>, n: U32) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, U32, srcs)), n)

def sp_src0(+fx: F.Folded, self: U32) -> U32:
  O.Arena.src0(sp_ar(fx), self)

def i64_is(n: U32, v: H.I64) -> Bool:
  Cmp.is_eq(H.i64_cmp(H.i64_of_i32(n), v))

def valid_device_range.val(is_rng: Bool, is_dev_axis: Bool, end: Maybe<&2, H.I64>, ndev: U32) -> Maybe<&1, Bool>:
  match end:
    case Some{n}: Some{Bool.and(Bool.and(is_rng, is_dev_axis), i64_is(ndev, n))}
    case _: sp_tri(Bool.and(is_rng, is_dev_axis), True{})

def valid_device_range.axi(op: O.Op, ax: Maybe<&1, O.AxisType>, end: Maybe<&2, H.I64>, ndev: U32) -> Maybe<&1, Bool>:
  match ax:
    case Some{a}: valid_device_range.val(O.eq_op(op, O.OpsRANGE{}), O.eq_axis(a, O.AXIS_DEVICE{}), end, ndev)
    case _: Some{False{}}

def valid_device_range.cmp(op: O.Op, ax: Maybe<&1, O.AxisType>, end: Maybe<&2, H.I64>, ndev: U32) -> Maybe<&1, Bool>:
  valid_device_range.axi(op, ax, end, ndev)

def valid_device_range.end(+rng: U32, +fx: F.Folded, ndev: U32) -> Maybe<&1, Bool>:
  valid_device_range.cmp(O.Arena.op(sp_ar(fx), rng), arg_axis(sp_arg(fx, rng)), arg_const_int(sp_arg(fx, sp_src0(fx, rng))), ndev)

def valid_device_range.one(srcs: List<&2, U32>, +fx: F.Folded, ndev: U32) -> Maybe<&1, Bool>:
  match srcs:
    case r <> Nil{}: valid_device_range.end(r, fx, ndev)
    case _: Some{False{}}

def valid_device_range.n(srcs: List<&2, U32>, +fx: F.Folded, ndev: U32) -> Maybe<&1, Bool>:
  valid_device_range.one(srcs, fx, ndev)

def validate_index.tie(two: Bool, bad: Bool) -> Maybe<&1, Bool>:
  match two bad:
    case False{} _: Some{True{}}
    case True{} True{}: Some{True{}}
    case True{} False{}: None{}

def validate_index.of(n: U32, bad: Bool) -> Maybe<&1, Bool>:
  validate_index.tie(U32.is_eq(n, 2), bad)

# ===========================================================================
# `validate_index` -- spec.py:11-27.
#
#     if len(uidx.src) != 2: return True
#     buf, idx = uidx.src
#     if idx.is_invalid: return True
#     if gate is None: gate = UOp.const(True)
#     if not CHECK_OOB or is_image_shape(buf._shape): return True
#     sz = buf.max_numel()
#     if 0<=idx.vmin and idx.vmax<sz: return True
#     return validate_index_with_z3(sz, idx, gate)
#
# The first two returns are ported and they are both `True`, so they are the whole
# of what this port can state. Everything past them needs one of four things it does
# not have: `CHECK_OOB`, `max_numel` (a product over `shape` with `ssimplify` in it),
# `vmin`/`vmax` (`_min_max`, ops.py:1104) and z3 (`tinygrad/uop/validate.py`, not
# ported at all). So the answer is `None` -- "no opinion" -- and the scan runs on,
# which is NOT the same as accepting: `type_verify` fails on a `VSkip` exactly as it
# fails on a `VFalse`.
# ===========================================================================
def validate_index(+fx: F.Folded, +uidx: U32) -> Maybe<&1, Bool>:
  validate_index.of(sp_nsrc(fx, uidx), is_invalid_at(sp_ar(fx), sp_src0(fx, uidx)))

# ===========================================================================
# `early_reject` -- a NECESSARY CONDITION, and see the header for why the direction
# matters. `ler` is Python's `uop.__dict__['_src_ops']`, CACHED ON THE UOP; there is
# no mutable uop here, so it is rebuilt per rule, and that is the one place this port
# is slower than the thing it ports. It folds over ALL of `src`, which is what
# Python's set comprehension does -- `ops.bend`'s `pm_ler` reads only `src[0]` and
# `src[1]`, and that is wrong for `te_21` (spec.py:198), whose reject set is all four
# of a PROGRAM's srcs. `prog4_ok` in the gate is the row that shows the difference.
# ===========================================================================
def sp_ler.go(srcs: List<&2, U32>, +ar: O.Arena, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match srcs:
    case Nil{}: acc
    case s <> t: sp_ler.go(t, ar, List.append(&2, O.Op, acc, [O.Arena.op(ar, s)]))

def sp_ler(+ar: O.Arena, self: U32) -> List<&2, O.Op>:
  sp_ler.go(O.Arena.srcs(ar, self), ar, Nil{})

def sp_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(O.op_in(have, o), sp_early.go(have, t))

def sp_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  sp_early.go(sp_ler(ar, self), rej)

def sp_claimed(ops: List<&2, O.Op>, ar: O.Arena, self: U32) -> Bool:
  O.op_in(ops, O.Arena.op(ar, self))

# ===========================================================================
# THE FOLDS AND READERS THE RULES SHARE. A rule body is Python's lambda with
# `self` spelled out, and these are the pieces it reaches for. `sp_src0` is
# `sp_src(.., 0)` because `src[0]` is written most.
# ===========================================================================
def sp_src(fx: F.Folded, self: U32, n: U32) -> U32:
  O.Arena.src(sp_ar(fx), self, n)

def sp_srcs(fx: F.Folded, self: U32) -> List<&2, U32>:
  O.Arena.srcs(sp_ar(fx), self)

def sp_src_from(fx: F.Folded, self: U32, k: U32) -> List<&2, U32>:
  O.Arena.src_from(sp_ar(fx), self, k)

def sp_op(fx: F.Folded, self: U32, want: O.Op) -> Bool:
  O.op_is(sp_ar(fx), self, want)

def sp_src_op(+fx: F.Folded, self: U32, n: U32, want: O.Op) -> Bool:
  O.op_is(sp_ar(fx), sp_src(fx, self, n), want)

def sp_src_in(+fx: F.Folded, self: U32, n: U32, ops: List<&2, O.Op>) -> Bool:
  sp_op_in(fx, sp_src(fx, self, n), ops)

def sp_src_dt(+fx: F.Folded, self: U32, n: U32, want: S.Dt) -> Bool:
  sp_dt_is(fx, sp_src(fx, self, n), want)

def nsrc_ge(fx: F.Folded, self: U32, n: U32) -> Bool:
  Bool.not(U32.is_lt(sp_nsrc(fx, self), n))

# A node's own dtype, as a VALUE, for the rules that compare two NODES' dtypes with
# each other rather than with a literal. Two unstated dtypes are both the absence of
# one, so `void` is the right answer for both; `sp_dt_is` is the other reader and it
# answers `False` for an unstated dtype, which is right against a LITERAL the
# pattern named.
def sp_dt_v.go(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

def sp_dt_v(fx: F.Folded, self: U32) -> S.Dt:
  sp_dt_v.go(sp_dt(fx, self))

def shp_eq.go(+fx: F.Folded, j: U32, k: U32) -> Bool:
  sp_shape_same(fx, j, k)

def shp_eq(fx: F.Folded, j: U32, k: U32) -> Bool:
  shp_eq.go(fx, j, k)

def all_same_shapes.go(srcs: List<&2, U32>, +fx: F.Folded, +head: U32, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_same_shapes.go(t, fx, head, Bool.and(acc, shp_eq(fx, head, s)))

def all_same_shapes(fx: F.Folded, +srcs: List<&2, U32>) -> Bool:
  all_same_shapes.go(srcs, fx, all_same_head(srcs), True{})

def sp_vb.go(b: Bool) -> O.Verdict:
  match b:
    case True{}: O.VTrue{}
    case False{}: O.VFalse{}

# `C if b else None` where C is ITSELF tri-state -- which is spec.py:127's shape,
# `validate_index(uidx, gate) if matches_dtype(alt, load.dtype) else False`, except
# that `validate_index` answers `None` when it cannot decide, and a `None` under a
# taken guard is still a `None`.
def sp_tri_v.go(b: Bool, v: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  match b:
    case True{}: v
    case False{}: None{}

def sp_tri_v(b: Bool, v: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  sp_tri_v.go(b, v)

def sp_vb(b: Bool) -> O.Verdict:
  sp_vb.go(b)

# `or_casted()` / `or_bitcasted()` / `or_after()` are `UPat.any`, and `is_any`
# compiles to a DISJUNCTION (upat.py:18-20), so `X or CAST(X)` is exactly
# `X or (CAST and X)`. That is also why no identity check is emitted for the doubled
# `uidx` name: the two bindings are in the two ALTERNATIVES and never meet.
#
# THE WRAPPER TEST IS THE NODE'S OWN OP, not its src's: `or_casted` wraps the node,
# so reading src[0] for the op instead asks whether the node's CHILD is the wrapper.
def alt_of(plain: Bool, wrapped: Bool, inner: Bool) -> Bool:
  Bool.or(plain, Bool.and(wrapped, inner))

# `UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted()` -- spec.py:125-130.
def IDX() -> List<&2, O.Op>: [O.OpsINDEX{}, O.OpsSHRINK{}]

def uidx_or_casted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_op_in(fx, s, IDX()), sp_op(fx, s, O.OpsCAST{}), sp_op_in(fx, sp_src0(fx, s), IDX()))

# `UPat(...).or_after()` -- the wrap is `UPat(Ops.AFTER, src=(X,), allow_any_len=True)`.
def after_or(+fx: F.Folded, +s: U32, +ops: List<&2, O.Op>) -> Bool:
  alt_of(sp_op_in(fx, s, ops), sp_op(fx, s, O.OpsAFTER{}), sp_op_in(fx, sp_src0(fx, s), ops))

def OP_PARAMISH() -> List<&2, O.Op>:
  [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsAFTER{}]

# `UPat(...).or_bitcasted()` -- spec.py:211.
def buf_or_bitcasted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_op_in(fx, s, OP_PARAMISH()), sp_op(fx, s, O.OpsBITCAST{}), sp_op_in(fx, sp_src0(fx, s), OP_PARAMISH()))

# `UPat(Ops.CONST).or_casted()` -- spec.py:211's third src.
def const_or_casted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_src_op(fx, s, 0, O.OpsCONST{}), sp_src_op(fx, s, 0, O.OpsCAST{}), sp_op_in(fx, sp_src0(fx, s), [O.OpsCONST{}]))

# ===========================================================================
# `spec_shared` -- spec.py:49-138. Thirty-three rules, and the three every other
# table ends with. The op set is `pdict`'s key and `rej` is `early_reject`; the
# rule's own op/dtype/arity/src tests are the pattern and its body is the lambda.
# ===========================================================================
# spec.py:51  (UPat(Ops.SINK, dtypes.void), lambda: True) -- no `src`, so NO arity test.
def sh_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSINK{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:54  (UPat(Ops.NOOP), lambda: True) -- TODO: remove this
def sh_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsNOOP{}), O.VTrue{})

# "not a float and not a bool", which is exactly the `else int(val)` arm's reach.
def c_holds_int(+c: S.Cls) -> Bool:
  Bool.and(Bool.not(S.Cls.is_float(c)), Bool.not(S.Cls.is_bool(c)))

def val_kind_ok.go(a: O.Arg, c: S.Cls) -> Bool:
  match a:
    case O.APy{O.CInvalid{}}: True{}
    case O.APy{O.CBool{b}}: S.Cls.is_bool(c)
    case O.APy{O.CFloat{f}}: S.Cls.is_float(c)
    case O.APy{O.CInt{i}}: c_holds_int(c)
    case _: False{}

def val_kind_ok(a: O.Arg, c: S.Cls) -> Bool:
  val_kind_ok.go(a, c)

def sh_2.tri.of(bad: Bool, a: O.Arg, d: S.Dt) -> Maybe<&1, Bool>:
  Some{Bool.or(bad, val_kind_ok(a, S.Dt.cls(d)))}

# tinygrad/dtype.py:84 is the whole of the second disjunct:
#     ConstFloat(truncate.get(self, float)(float(val))) if is_float(self)
#       else bool(val) if is_bool(self) else int(val)
# so `type(val)` survives `dtype.const` exactly when the value's kind matches the
# dtype's class: a float value needs a float dtype, a bool needs bool, and an int
# needs NEITHER (a bool or float dtype would hand back a `bool` or a `ConstFloat`).
# A CONST's dtype is DERIVED from its value, so on a well-formed arena the second
# disjunct is unreachable -- which is a fact about the RULE, not about this port,
# and `const_ok` in the gate is the row that says so.
def sh_2.tri(+fx: F.Folded, +self: U32) -> Maybe<&1, Bool>:
  sh_2.tri.of(sp_is_invalid(fx, self), sp_arg(fx, self), sp_dt_v(fx, self))

# spec.py:57  (UPat(Ops.CONST, src=(), name="x"), lambda x: x.is_invalid or
#              type(x.val) is type(x.dtype.const(x.val)))
def sh_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsCONST{}), nsrc_is(fx, self, 0)), sp_vd(sh_2.tri(fx, self)))

def sh_3.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsSTACK{}), sp_dt_is(fx, self, S.void())), nsrc_is(fx, self, 0))

# spec.py:60  (UPat(Ops.STACK, dtypes.void, src=()), lambda: True)
def sh_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_3.pat(fx, self), O.VTrue{})

def sh_4.body.of(sames: Bool, dts: Bool) -> Bool:
  Bool.and(sames, dts)

def sh_4.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_4.body.of(all_same_shapes(fx, sp_srcs(fx, self)), all_mdw(sp_srcs(fx, self), fx, sp_dt_v(fx, self), True{}))

# spec.py:61  (UPat(Ops.STACK, src=(UPat(),), allow_any_len=True, name="s"),
#              lambda s: all_same([x.shape for x in s.src]) and
#                        all(matches_dtype(x, s.dtype) or x.dtype in dtypes.weaks for x in s.src))
def sh_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSTACK{}), nsrc_ge(fx, self, 1)), sp_vb(sh_4.body(fx, self)))

def sh_5.pat.of(op: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(g, n))

def sh_5.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_5.pat.of(sp_op(fx, self, O.OpsWHERE{}), sp_src_dt(fx, self, 0, S.boolean()), nsrc_is(fx, self, 3))

# spec.py:66  (UPat(Ops.WHERE, name="w", src=(UPat(dtype=dtypes.bool), UPat(), UPat())),
#              lambda w: all(matches_dtype(s, w.dtype) or s.dtype in dtypes.weaks for s in w.src[1:]))
def sh_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_5.pat(fx, self), sp_vb(all_mdw(sp_src_from(fx, self, 1), fx, sp_dt_v(fx, self), True{})))

def sh_6.pat.of(op: Bool, d: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, n))

def sh_6.body.of(x: Bool, y: Bool) -> Bool:
  Bool.or(x, y)

def sh_6.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_6.body.of(sp_mdw(fx, sp_src(fx, self, 0), sp_dt_v(fx, sp_src(fx, self, 1))),
               sp_mdw(fx, sp_src(fx, self, 1), sp_dt_v(fx, sp_src(fx, self, 0))))

# `GroupOp.Comparison` as an op SET: `GroupOp.comparison` is a Bool over one op, so
# the set is the three members and this is its `any`.
def sh_6.pat.ops(fx: F.Folded, self: U32) -> Bool:
  sp_op_in(fx, self, [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}])

def sh_6.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_6.pat.of(sh_6.pat.ops(fx, self), sp_dt_is(fx, self, S.boolean()), nsrc_is(fx, self, 2))

# spec.py:68  (UPat(GroupOp.Comparison, dtype=dtypes.bool, src=(UPat.var("x"), UPat.var("y"))),
#              lambda x,y: matches_dtype(x, y.dtype) or matches_dtype(y, x.dtype) or
#                           x.dtype in dtypes.weaks or y.dtype in dtypes.weaks)
# `matches_dtype(x, y.dtype) or matches_dtype(y, x.dtype)` is the same SET as
# `matches_dtype(x, y.dtype) or weak(x) or weak(y)`, because `x.dtype == y.dtype`
# is symmetric and each side contributes its own `base.is_invalid`; so this is
# `mdw(x, y.dtype) or mdw(y, x.dtype)` and no third reading is needed.
def sh_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_6.pat(fx, self), sp_vb(sh_6.body(fx, self)))

# `c.dtype in (dtypes.u32, dtypes.weakint)` -- tinygrad/dtype.py:141 aliases `uint` to
# `uint32`, so this is two concrete dtypes and not a class test.
def sp_is_uint_or_weak.go(+m: Maybe<&2, S.Dt>) -> Bool:
  Bool.or(dt_eq.go(m, S.uint32()), dt_eq.go(m, S.weakint()))

def sp_is_uint_or_weak(fx: F.Folded, c: U32) -> Bool:
  sp_is_uint_or_weak.go(sp_dt(fx, c))

def sh_8.body.of(+fx: F.Folded, +c: U32, +x: U32, a: S.Dt) -> Bool:
  Bool.or(Bool.or(sp_md(fx, c, a), sp_is_uint_or_weak(fx, c)), sp_base_invalid(fx, x))

def sh_8.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_8.body.of(fx, sp_src(fx, self, 1), sp_src(fx, self, 0), sp_dt_v(fx, self))

def OP_BITS() -> List<&2, O.Op>:
  [O.OpsAND{}, O.OpsOR{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}]

# spec.py:70  (UPat((Ops.AND, Ops.OR, Ops.XOR, Ops.SHL, Ops.SHR), name="x"),
#              lambda x: False if any(dtypes.is_float(s.dtype) for s in x.src) else None)
# THE FIRST RULE THAT CLAIMS A SHL, and it is the one that carries the `False`, which
# is load-bearing: `sh_8` claims a SHL too and would answer `True`.
def sh_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, OP_BITS()), sp_vd(sp_tri(any_float(sp_srcs(fx, self), fx, False{}), False{})))

def OP_SHIFTS() -> List<&2, O.Op>:
  [O.OpsSHL{}, O.OpsSHR{}]

# spec.py:71  (UPat((Ops.SHL, Ops.SHR), src=(UPat.var("x"), UPat.var("c")), name="a"),
#              lambda a,x,c: matches_dtype(c, a.dtype) or c.dtype in (dtypes.u32, dtypes.weakint)
#                           or x.base.is_invalid)
# `dtypes.u32` is the ALIAS for uint32 (tinygrad/dtype.py:141), so the pair is
# `(uint32, weakint)` and not a "some unsigned width" test.
def sh_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_SHIFTS()), nsrc_is(fx, self, 2)), sp_vb(sh_8.body(fx, self)))

def OP_IDIVS() -> List<&2, O.Op>:
  [O.OpsCDIV{}, O.OpsCMOD{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}]

def sh_9.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.or(sp_is_int(fx, self), any_base_invalid(sp_srcs(fx, self), fx, False{}))

# spec.py:73  (UPat((Ops.CDIV, Ops.CMOD, Ops.FLOORDIV, Ops.FLOORMOD), name="x"),
#              lambda x: None if dtypes.is_int(x.dtype) or any(s.base.is_invalid for s in x.src)
#                        else False)
# `None` rather than `False`, which is load-bearing for every later rule for these ops.
def sh_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, OP_IDIVS()), sp_vd(sp_tri(sh_9.body(fx, self), False{})))

# spec.py:75  (UPat(GroupOp.ALU, name="x"),
#              lambda x: all(matches_dtype(y, x.dtype) or y.dtype in dtypes.weaks for y in x.src))
def sh_10(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(O.GroupOp.alu(O.Arena.op(sp_ar(fx), self)), sp_vb(all_mdw(sp_srcs(fx, self), fx, sp_dt_v(fx, self), True{})))

def sh_11.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(sp_op_in(fx, self, [O.OpsBITCAST{}, O.OpsCAST{}]), nsrc_is(fx, self, 1))

# spec.py:78  (UPat((Ops.BITCAST, Ops.CAST), src=(UPat(),), name="x"), lambda x: isinstance(x.arg, DType))
def sh_11(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_11.pat(fx, self), sp_vb(arg_dt(sp_arg(fx, self))))

def ids_nonempty.go(ids: Maybe<&2, List<&2, U32>>) -> Bool:
  match ids:
    case Some{h <> t}: True{}
    case _: False{}

def ids_nonempty(a: O.Arg) -> Bool:
  ids_nonempty.go(arg_ids(a))

# spec.py:81  (UPat(Ops.RANGE, src=(UPat(),), allow_any_len=True, name="rng"),
#              lambda rng: isinstance(rng.arg, tuple) and len(rng.arg) >= 2 and
#                all(isinstance(ra, int) for ra in rng.arg[0:-1]) and isinstance(rng.arg[-1], AxisType))
# `ARange` IS Python's `(axis_id, axis_type)` tuple already split, so the `isinstance`
# is the arm, `len(arg) >= 2` is a non-empty `ids`, and `all(isinstance(ra, int))`
# is `List<&2, U32>` being well-formed.
def sh_12(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsRANGE{}), nsrc_ge(fx, self, 1)), sp_vb(ids_nonempty(sp_arg(fx, self))))

def sh_13.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(nsrc_ge(fx, self, 1), all_int_or_base_invalid(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:83  (UPat(Ops.INDEX, name="x"),
#              lambda x: len(x.src)>0 and all(dtypes.is_int(y.dtype) or y.base.is_invalid
#                            for y in x.src[1:]) or None)
# `None` rather than `False`, which is load-bearing for every later rule for INDEX.
def sh_13(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsINDEX{}), sp_vd(sp_tri(sh_13.body(fx, self), True{})))

def sh_14.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsEND{}), sp_src_dt(fx, self, 0, S.void())), nsrc_ge(fx, self, 1))

def sh_14.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(arg_none(sp_arg(fx, self)), all_range_int(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:86  (UPat(Ops.END, src=(UPat(dtype=dtypes.void),), allow_any_len=True, name="x"),
#              lambda x: x.arg is None and all(u.op is Ops.RANGE and dtypes.is_int(u.dtype)
#                            for u in x.src[1:]))
def sh_14(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_14.pat(fx, self), sp_vb(sh_14.body(fx, self)))

def sh_15.pat.of(op: Bool, d: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, n)))

def sh_15.src(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(sp_src_op(fx, self, 1, O.OpsRANGE{}), sp_src_dt(fx, self, 1, S.void()))

def sh_15.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_15.pat.of(sp_op(fx, self, O.OpsBACKEDGE{}), sp_dt_is(fx, self, S.void()),
               sh_15.src(fx, self), nsrc_is(fx, self, 3))

def sh_15.body.pick(no_arg: Bool, scalar: Bool, cond_bad: Bool) -> Bool:
  Bool.and(no_arg, Bool.and(scalar, Bool.not(cond_bad)))

def sh_15.body.go(a: O.Arg, +cond: U32, +fx: F.Folded) -> Bool:
  sh_15.body.pick(arg_none(a), sp_is_scalar(fx, cond), sp_base_invalid(fx, cond))

def sh_15.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_15.body.go(sp_arg(fx, self), sp_src(fx, self, 2), fx)

# spec.py:89  (UPat(Ops.BACKEDGE, dtypes.void,
#                    src=(UPat(), UPat(Ops.RANGE, dtypes.void), UPat(dtype=dtypes.bool)), name="x"),
#              lambda x: x.arg is None and x.src[2].shape == () and not x.src[2].base.is_invalid)
# ONE OF ONLY FOUR NON-EMPTY `early_reject` SETS: `src[0]` of the pattern is
# `UPat(Ops.RANGE, dtypes.void)`, a single-op upat, so `rej` is `[RANGE]`.
def sh_15(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_15.pat(fx, self), sp_vb(sh_15.body(fx, self)))

def is_param.go(pa: Maybe<&1, O.ParamArg>) -> Bool:
  match pa:
    case Some{p}: True{}
    case _: False{}

def is_param(a: O.Arg) -> Bool:
  is_param.go(arg_param(a))

# spec.py:92  (UPat(Ops.PARAM, src=(), name="x"), lambda x: isinstance(x.arg, ParamArg))
def sh_16(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 0)), sp_vb(is_param(sp_arg(fx, self))))

def sh_17.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(is_param(sp_arg(fx, self)), addr_eq(addr_of(sp_addr(fx, self)), S.ALocal{}))

# spec.py:93  (UPat(Ops.BUFFER, src=(), name="x"),
#              lambda x: isinstance(x.arg, ParamArg) and x.addrspace in (AddrSpace.REG, AddrSpace.LOCAL))
def sh_17(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBUFFER{}), nsrc_is(fx, self, 0)), sp_vb(sh_17.body(fx, self)))

def is_reg_or_local.go(+m: Maybe<&2, S.Addr>) -> Bool:
  Bool.or(addr_eq.go(m, S.AReg{}), addr_eq.go(m, S.ALocal{}))

def is_reg_or_local(m: Maybe<&2, S.Addr>) -> Bool:
  is_reg_or_local.go(m)

def sh_18.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsBINARY{}), sp_dt_is(fx, self, S.uint8())), nsrc_is(fx, self, 0))

# spec.py:95  (UPat(Ops.BINARY, dtypes.u8, src=(), name="x"), lambda x: isinstance(x.arg, bytes))
def sh_18(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_18.pat(fx, self), sp_vb(arg_blob(sp_arg(fx, self))))

# spec.py:98  (UPat(Ops.GROUP, dtypes.void, src=UPat(dtype=dtypes.void)), lambda: True)
# `src=UPat(..)` is `itertools.repeat`, so the pattern is "EVERY src is void" and
# the arity is unbounded -- upat.py:59 adds a `len(src) != 0` clause only when the
# inner pattern BINDS a name, and this one does not.
def sh_19(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsGROUP{}), sp_dt_is(fx, self, S.void())), sp_vb(all_void(sp_srcs(fx, self), fx, True{})))

def OP_AFTER20() -> List<&2, O.Op>:
  [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsSTAGE{}, O.OpsINDEX{},
   O.OpsAFTER{}, O.OpsUNSHARD{}, O.OpsBITCAST{}, O.OpsINS{},
   O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]

# spec.py:101 (UPat(Ops.AFTER, src=(UPat(Movement|PARAM|BUFFER|ALLOC|STAGE|INDEX|AFTER|
#                     UNSHARD|BITCAST|INS),), allow_any_len=True), lambda: True)
def sh_20(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsAFTER{}), nsrc_ge(fx, self, 1)), sp_vb(sp_src_in(fx, self, 0, OP_AFTER20())))

# spec.py:106 (UPat((Ops.CUSTOMI, Ops.CUSTOM), name="x"),
#              lambda x: isinstance(x.arg, tuple) and len(x.arg) == 2 and
#                isinstance(x.arg[0], str) and isinstance(x.arg[1], DType))
# `AInk` IS that pair, and it is the only constructor that is, so all four
# conjuncts are one arm.
def sh_21(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, [O.OpsCUSTOMI{}, O.OpsCUSTOM{}]), sp_vb(arg_ink(sp_arg(fx, self))))

# THE WALL IS CLOSED, and it closed the only way it could: by the `Arg` datatype
# growing a constructor. `uop/ops.bend` carries `CustomFunction` (ops.py:1394
# upstream) with `Arg`'s `ACustom` arm, so `isinstance(x.arg, CustomFunction)` is
# one compiler-checked arm here instead of a `str` test standing in for it.
#
# THE STALENESS WAS INVISIBLE TO EVERY COUNT, which is the part worth keeping. At the
# pin `spec.py:110` read `lambda x: isinstance(x.arg, str)`; at HEAD it reads
# `isinstance(x.arg, CustomFunction)`. `sh_len` is 33 at the pin and 33 at HEAD, so
# the table-size rows could not notice, and NO OTHER ROW READ THE ARG'S TYPE. Same
# class as the dtype rename in `uop/fold.bend` -- a value a pattern matches on moving
# under a green gate -- except here not even the arm was wrong-looking: it compiled,
# it ran, it answered a different question. A count cannot see a body change.
#
# AND IT WAS NOT ONE LINE. Upstream deleted `spec_tensor`'s fourth rule with it (see
# THE TWENTY-THIRD TENSOR RULE), which moved `te_len` and `fu_len`; the rule that
# SURVIVED had to change its own predicate. Both rows below move, in OPPOSITE
# directions, which is what makes the pair worth having: under the pin's body
# `cf_arg_ok` was 0 and `cf_arg_str` was 1, and under HEAD's they are 1 and 0.
# spec.py:110 (UPat(Ops.CUSTOM_FUNCTION, name="x", allow_any_len=True), lambda x: isinstance(x.arg, CustomFunction))
def sh_22(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsCUSTOM_FUNCTION{}), sp_vb(arg_customfunction(sp_arg(fx, self))))

def sh_23.body_op.go(op: O.Op) -> Bool:
  O.GroupOp.opaque_call_bodies(op)

def sh_23.body_op(+fx: F.Folded, self: U32) -> Bool:
  sh_23.body_op.go(O.Arena.op(sp_ar(fx), sp_src(fx, self, 0)))

def sh_23.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsCALL{}), sh_23.body_op(fx, self)), nsrc_ge(fx, self, 1))

def sh_23.body.pick(ci: Maybe<&2, S.Dt>, d: Maybe<&2, S.Dt>) -> Bool:
  match ci d:
    case Some{a} Some{b}: O.eq_dt(a, b)
    case _ _: False{}

def sh_23.body.go(ci: Maybe<&2, S.Dt>, d: Maybe<&2, S.Dt>) -> Bool:
  sh_23.body.pick(ci, d)

def sh_23.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_23.body.go(arg_call(sp_arg(fx, self)), sp_dt(fx, self))

# spec.py:112 (UPat(Ops.CALL, src=(UPat(tuple(OPAQUE_CALL_BODIES)),), allow_any_len=True, name="x"),
#              lambda x: isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype)
def sh_23(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_23.pat(fx, self), sp_vb(sh_23.body(fx, self)))

# spec.py:116 (UPat(Ops.PYLITERAL), lambda: True) -- pattern-compiler IR
def sh_24(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsPYLITERAL{}), O.VTrue{})

# spec.py:119 (UPat(Ops.BARRIER, dtypes.void), lambda: True) -- TODO: spec_program only
def sh_25(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBARRIER{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:122 (UPat(Ops.INS, name="x"),
#              lambda x: isinstance(x.arg, tuple) and len(x.arg) == 2 and isinstance(x.arg[1], DType))
def sh_26(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsINS{}), sp_vb(arg_ink(sp_arg(fx, self))))

def sh_27.pat.of(op: Bool, u: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, n))

def sh_27.uidx(+fx: F.Folded, self: U32) -> Bool:
  uidx_or_casted(fx, sp_src(fx, self, 0))

def sh_27.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_27.pat.of(sp_op(fx, self, O.OpsLOAD{}), sh_27.uidx(fx, self), nsrc_is(fx, self, 1))

# spec.py:125 (UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted().load(), validate_index)
# `uidx` is bound in BOTH `is_any` alternatives, which is the SAFE duplicate the
# header describes: no identity check, and `uidx_or_casted` is a disjunction.
def sh_27(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_27.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_28.pat.of(op: Bool, u: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, Bool.and(g, n)))

def sh_28.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_28.pat.of(sp_op(fx, self, O.OpsLOAD{}), sh_27.uidx(fx, self), sp_src_dt(fx, self, 2, S.boolean()), nsrc_is(fx, self, 3))

def sh_28.body(+fx: F.Folded, +self: U32) -> Bool:
  sp_md(fx, sp_src(fx, self, 1), sp_dt_v(fx, self))

# spec.py:126 (... .load(UPat.var("alt"), UPat.var("gate", dtype=dtypes.bool), name="load"),
#              lambda uidx,gate,alt,load: validate_index(uidx, gate)
#                                           if matches_dtype(alt, load.dtype) else False)
def sh_28(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_28.pat(fx, self), sp_vd(sp_tri_v(sh_28.body(fx, self), validate_index(fx, sp_src(fx, self, 0)))))

def sh_29.pat.of(op: Bool, u: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, n))

def sh_29.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_29.pat.of(sp_op(fx, self, O.OpsSTORE{}), sh_27.uidx(fx, self), nsrc_is(fx, self, 2))

# spec.py:128 (UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted().store(UPat()), validate_index)
def sh_29(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_29.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_30.pat.of(op: Bool, u: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, Bool.and(g, n)))

def sh_30.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_30.pat.of(sp_op(fx, self, O.OpsSTORE{}), sh_27.uidx(fx, self), sp_src_dt(fx, self, 2, S.boolean()), nsrc_is(fx, self, 3))

# spec.py:129 (... .store(UPat(), UPat.var("gate", dtype=dtypes.bool)), validate_index)
def sh_30(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_30.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_31.pat.of(op: Bool, d: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, n))

def sh_31.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_31.pat.of(sp_op(fx, self, O.OpsSTORE{}), sp_dt_is(fx, self, S.void()), nsrc_is(fx, self, 2))

def sh_31.tri.of(x: O.Op) -> Maybe<&1, Bool>:
  match x:
    case O.OpsBUFFER{}: Some{True{}}
    case O.OpsALLOC{}: Some{True{}}
    case O.OpsPARAM{}: Some{True{}}
    case O.OpsSTAGE{}: Some{True{}}
    case O.OpsINDEX{}: None{}
    case O.OpsBITCAST{}: None{}
    case O.OpsAFTER{}: None{}
    case O.OpsUNSHARD{}: None{}
    case O.OpsDETACH{}: None{}
    case O.OpsRESHAPE{}: None{}
    case O.OpsEXPAND{}: None{}
    case O.OpsPERMUTE{}: None{}
    case O.OpsPAD{}: None{}
    case O.OpsSHRINK{}: None{}
    case O.OpsFLIP{}: None{}
    case _: Some{False{}}

def sh_31.tri.go(x: O.Op) -> Maybe<&1, Bool>:
  sh_31.tri.of(x)

def sh_31.tri(+fx: F.Folded, self: U32) -> Maybe<&1, Bool>:
  sh_31.tri.go(O.Arena.op(sp_ar(fx), sp_src(fx, self, 0)))

# spec.py:133 (UPat(Ops.STORE, dtypes.void, (UPat(name="x"), UPat())),
#              lambda x: True if (b:=x.storage_base).op in {BUFFER, ALLOC, PARAM, STAGE}
#                        else None if b.op is INDEX else False)
#
# `storage_base` (ops.py:801) is `base` with UNSHARD, BITCAST and AFTER stripped,
# and `base` (ops.py:785) is `src[0].base` for a movement op or a DETACH. It is a
# `while` over three ops, so it is NOT a fold this port has, and the rule is
# therefore only decided for the nodes where `b is x` -- which is every op except
# a movement, DETACH, BITCAST, AFTER and UNSHARD. For the rest the answer is
# `None` (Python's own `None` for the INDEX case) and the scan runs on. So a
# STORE into a RESHAPE of a BUFFER is not verified by this rule; it is not
# REJECTED either, because `type_verify` fails only when NO rule answers. See the
# TODO on `storage_base`.
def sh_31(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_31.pat(fx, self), sp_vd(sh_31.tri(fx, self)))

# spec.py:137 (UPat(Ops.WMMA, src=(UPat(), UPat(), UPat()), name="x"),
#              lambda x: isinstance(x.arg, tuple) and len(x.arg) == 4)
def sh_32(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsWMMA{}), nsrc_is(fx, self, 3)), sp_vb(arg_wmma(sp_arg(fx, self))))

def OP_ALU.go() -> List<&2, O.Op>:
  [O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsNEG{},
   O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{},
   O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{},
   O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

def OP_ALU() -> List<&2, O.Op>:
  OP_ALU.go()

# ---------------------------------------------------------------------------
# THE TABLE. One entry per rule, in `spec.py`'s order, so tag N is `(spec.py
# line, N)` by construction and `sh_table_len` in the gate checks the count.
# `ops` is the op set `pdict` keys on and `rej` is `early_reject` -- NON-EMPTY at
# tag 15 only, and see the header for why that set decides nothing.
# ---------------------------------------------------------------------------
def shared_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0,  [O.OpsSINK{}],               Nil{}},   # 51
    O.PMEntry{1,  [O.OpsNOOP{}],               Nil{}},   # 54
    O.PMEntry{2,  [O.OpsCONST{}],              Nil{}},   # 57
    O.PMEntry{3,  [O.OpsSTACK{}],              Nil{}},   # 60
    O.PMEntry{4,  [O.OpsSTACK{}],              Nil{}},   # 61
    O.PMEntry{5,  [O.OpsWHERE{}],              Nil{}},   # 66
    O.PMEntry{6,  [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}], Nil{}},  # 68
    O.PMEntry{7,  OP_BITS(),                   Nil{}},   # 70
    O.PMEntry{8,  OP_SHIFTS(),                 Nil{}},   # 71
    O.PMEntry{9,  OP_IDIVS(),                  Nil{}},   # 73
    O.PMEntry{10, OP_ALU(),                    Nil{}},   # 75
    O.PMEntry{11, [O.OpsBITCAST{}, O.OpsCAST{}], Nil{}}, # 78
    O.PMEntry{12, [O.OpsRANGE{}],              Nil{}},   # 81
    O.PMEntry{13, [O.OpsINDEX{}],              Nil{}},   # 83
    O.PMEntry{14, [O.OpsEND{}],                Nil{}},   # 85
    O.PMEntry{15, [O.OpsBACKEDGE{}],           [O.OpsRANGE{}]},  # 88
    O.PMEntry{16, [O.OpsPARAM{}],              Nil{}},   # 92
    O.PMEntry{17, [O.OpsBUFFER{}],             Nil{}},   # 93
    O.PMEntry{18, [O.OpsBINARY{}],             Nil{}},   # 95
    O.PMEntry{19, [O.OpsGROUP{}],              Nil{}},   # 98
    O.PMEntry{20, [O.OpsAFTER{}],              Nil{}},   # 101
    O.PMEntry{21, [O.OpsCUSTOMI{}, O.OpsCUSTOM{}], Nil{}},# 106
    O.PMEntry{22, [O.OpsCUSTOM_FUNCTION{}],    Nil{}},   # 110
    O.PMEntry{23, [O.OpsCALL{}],               Nil{}},   # 112
    O.PMEntry{24, [O.OpsPYLITERAL{}],          Nil{}},   # 116
    O.PMEntry{25, [O.OpsBARRIER{}],            Nil{}},   # 119
    O.PMEntry{26, [O.OpsINS{}],                Nil{}},   # 122
    O.PMEntry{27, [O.OpsLOAD{}],               Nil{}},   # 125
    O.PMEntry{28, [O.OpsLOAD{}],               Nil{}},   # 126
    O.PMEntry{29, [O.OpsSTORE{}],              Nil{}},   # 128
    O.PMEntry{30, [O.OpsSTORE{}],              Nil{}},   # 129
    O.PMEntry{31, [O.OpsSTORE{}],              Nil{}},   # 133
    O.PMEntry{32, [O.OpsWMMA{}],               Nil{}}]}  # 137

# ===========================================================================
# THE DRIVER, and it is duplicated five more times. See the header for why.
# ===========================================================================
def sh_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: sh_0(fx, self)
    case 1: sh_1(fx, self)
    case 2: sh_2(fx, self)
    case 3: sh_3(fx, self)
    case 4: sh_4(fx, self)
    case 5: sh_5(fx, self)
    case 6: sh_6(fx, self)
    case 7: sh_7(fx, self)
    case 8: sh_8(fx, self)
    case 9: sh_9(fx, self)
    case 10: sh_10(fx, self)
    case 11: sh_11(fx, self)
    case 12: sh_12(fx, self)
    case 13: sh_13(fx, self)
    case 14: sh_14(fx, self)
    case 15: sh_15(fx, self)
    case 16: sh_16(fx, self)
    case 17: sh_17(fx, self)
    case 18: sh_18(fx, self)
    case 19: sh_19(fx, self)
    case 20: sh_20(fx, self)
    case 21: sh_21(fx, self)
    case 22: sh_22(fx, self)
    case 23: sh_23(fx, self)
    case 24: sh_24(fx, self)
    case 25: sh_25(fx, self)
    case 26: sh_26(fx, self)
    case 27: sh_27(fx, self)
    case 28: sh_28(fx, self)
    case 29: sh_29(fx, self)
    case 30: sh_30(fx, self)
    case 31: sh_31(fx, self)
    case 32: sh_32(fx, self)
    case _: O.VSkip{}

def sh_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  sh_dispatch.go(tag, fx, self)

def sh_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: sh_dispatch(tag, fx, self)
    case False{}: O.VSkip{}

def sh_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  sh_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def sh_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: sh_scan(ts, fx, self, t, O.pm_keep(acc, sh_try(ts, fx, self, e)))

def sh_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  sh_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def shared_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  sh_rewrite(shared_table(), fx, self)

# ===========================================================================
# THE PARAMARG FACTS, GATHERED ONCE. A `Maybe` is a `Type` -- Bend's affine
# handler -- so it can be read ONCE, and the four answers spec.py's BUFFER, ALLOC
# and PARAM rules ask for have to travel together; and a `Data` record cannot
# hold a `Maybe` FIELD, so the device's three states are a third `Data` type
# rather than a `Maybe<Dev>`. `Arg` and `ParamArg` already name every field, so
# `isinstance(x.arg, ParamArg)`, `isinstance(x.arg.size, int)` and
# `x.arg.buffer is not None` are ONE `match` and there is no `isinstance`
# anywhere in this file.
# ===========================================================================
type DevOpt is Data:
  DNo{}
  DOne{tag: U32}
  DMany{tags: List<&2, U32>}

def valid_device_range.pick(d: DevOpt, srcs: List<&2, U32>, +fx: F.Folded) -> Maybe<&1, Bool>:
  match d:
    case DOne{tag}: sp_tri(True{}, shp_len_is(srcs, 0))
    case DMany{tags}: valid_device_range.n(srcs, fx, U32.from_nat(List.length(&2, U32, tags)))
    case _: Some{True{}}

def valid_device_range.go(d: DevOpt, srcs: List<&2, U32>, +fx: F.Folded) -> Maybe<&1, Bool>:
  valid_device_range.pick(d, srcs, fx)

# ===========================================================================
# `valid_device_range` -- spec.py:33.
#     if not isinstance(device, tuple): return len(src) == 0
#     if len(src) != 1: return False
#     rng = src[0]
#     return rng.op is Ops.RANGE and rng.axis_type is AxisType.DEVICE and \
#            int(rng.vmax)+1 == len(device)
#
# THE `vmax` HALF, and it IS PORTABLE. ops.py:1147 says a RANGE's `vmax` is
# `(src[0]-1).vmax`, and for a CONST end `src[0]` the one-above-minimum makes that
# `n - 1` for an int CONST `n`, so `int(rng.vmax)+1 == len(device)` is EXACTLY
# `src[0]'s value == len(device)` -- a read of the arg. A NON-constant range end is
# the one case it does not cover, and there `None` is the answer.
# ===========================================================================
def valid_device_range(d: DevOpt, srcs: List<&2, U32>, +fx: F.Folded) -> Maybe<&1, Bool>:
  valid_device_range.go(d, srcs, fx)

# `ok` is the `isinstance(x.arg, ParamArg)`; the rest are the fields, already
# reduced to the question each rule asks of them.
type Pa is Data:
  Pa{ok: Bool, size: Bool, dev: DevOpt, buf: Bool, vrange: Bool}

def Pa.ok.go(p: Pa) -> Bool:
  match p:
    case Pa{ok, size, dev, buf, vrange}: ok

def Pa.ok(p: Pa) -> Bool:
  Pa.ok.go(p)

def Pa.size.go(p: Pa) -> Bool:
  match p:
    case Pa{ok, size, dev, buf, vrange}: size

def Pa.size(p: Pa) -> Bool:
  Pa.size.go(p)

def Pa.dev.go(p: Pa) -> DevOpt:
  match p:
    case Pa{ok, size, dev, buf, vrange}: dev

def Pa.dev(p: Pa) -> DevOpt:
  Pa.dev.go(p)

def Pa.buf.go(p: Pa) -> Bool:
  match p:
    case Pa{ok, size, dev, buf, vrange}: buf

def Pa.buf(p: Pa) -> Bool:
  Pa.buf.go(p)

def Pa.vrange.go(p: Pa) -> Bool:
  match p:
    case Pa{ok, size, dev, buf, vrange}: vrange

def Pa.vrange(p: Pa) -> Bool:
  Pa.vrange.go(p)

def is_some_u32.go(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{x}: True{}
    case _: False{}

def is_some_u32(m: Maybe<&2, U32>) -> Bool:
  is_some_u32.go(m)

def is_some_range.go(m: Maybe<&2, O.PyRange>) -> Bool:
  match m:
    case Some{x}: True{}
    case _: False{}

def is_some_range(m: Maybe<&2, O.PyRange>) -> Bool:
  is_some_range.go(m)

def dev_opt.pick(m: Maybe<&2, S.Dev>) -> DevOpt:
  match m:
    case Some{S.D1{tag}}: DOne{tag}
    case Some{S.Dn{tags}}: DMany{tags}
    case _: DNo{}

def dev_opt.go(m: Maybe<&2, S.Dev>) -> DevOpt:
  dev_opt.pick(m)

def dev_opt(m: Maybe<&2, S.Dev>) -> DevOpt:
  dev_opt.go(m)

def pa_of.all(size: Maybe<&2, U32>, vmin_vmax: Maybe<&2, O.PyRange>, device: Maybe<&2, S.Dev>, buffer: Maybe<&2, U32>) -> Pa:
  Pa{True{}, is_some_u32(size), dev_opt(device), is_some_u32(buffer), is_some_range(vmin_vmax)}

def pa_of.pick(m: Maybe<&1, O.ParamArg>) -> Pa:
  match m:
    case Some{O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}}:
      pa_of.all(size, vmin_vmax, device, buffer)
    case _: Pa{False{}, False{}, DNo{}, False{}, False{}}

def pa_of.go(m: Maybe<&1, O.ParamArg>) -> Pa:
  pa_of.pick(m)

def pa_of(fx: F.Folded, self: U32) -> Pa:
  pa_of.go(arg_param(sp_arg(fx, self)))

# `is_device` over the three states: `DNo` is Python's `None`, and
# `isinstance(None, str)` and `isinstance(None, tuple)` are both False.
def dopt_is.go(d: DevOpt) -> Bool:
  match d:
    case DNo{}: False{}
    case _: True{}

def dopt_is(d: DevOpt) -> Bool:
  dopt_is.go(d)

def sp_dev_is(+fx: F.Folded, s: U32) -> Bool:
  dopt_is(dev_opt(dev_of(sp_dev(fx, s))))

# `all(isinstance(s.device, str) for s in x.src)` -- spec.py:184, :271. A `D1`
# IS a device name and a `Dn` is a tuple of them, so "is a str" and "is a tuple of
# strs" are both just "is a `Some`": the name-ness is `Device.tag`'s job and that
# is P6. See the `is_device` note below.
def all_dev(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_dev(t, fx, Bool.and(acc, sp_dev_is(fx, s)))

# ===========================================================================
# `is_device` -- spec.py:140.
#     def is_device(d): return isinstance(d, str) or (isinstance(d, tuple) and
#                                            all(isinstance(s, str) for s in d))
#
# WHAT THIS PORT CAN STATE, PLAINLY. Python's `device` is `str | tuple[str, ...]`
# and `S.Dev` is `D1{tag} | Dn{tags}`: `D1` is the `str` case and `Dn` is the
# `tuple` case, so the two `isinstance` tests are the two constructors and the
# `all(...)` is the `List` being well-formed. Both are TRUE of every `S.Dev` BY
# CONSTRUCTION, so `is_device` is total on a `Dev` and only the `None` case is a
# question, which Python answers False and so do I.
# WHAT IT CANNOT STATE: that a `U32` tag really names a `str`. The tag is an
# interned device NAME and the table that interns it is `Device.tag`, which is P6,
# so the string-ness is an invariant this port INHERITS rather than CHECKS.
# ===========================================================================
def is_device(m: Maybe<&2, S.Dev>) -> Bool:
  dopt_is(dev_opt(m))

def dopt_none.pick(d: DevOpt) -> Bool:
  match d:
    case DNo{}: True{}
    case _: False{}

def dopt_none.go(d: DevOpt) -> Bool:
  dopt_none.pick(d)

def dopt_none(d: DevOpt) -> Bool:
  dopt_none.go(d)

def some_list.go(a: Maybe<&2, List<&2, U32>>) -> Bool:
  match a:
    case Some{x}: True{}
    case _: False{}

def some_list(a: Maybe<&2, List<&2, U32>>) -> Bool:
  some_list.go(a)

# `facts and valid_device_range(...)`, and the `None` when the range is
# undecidable: a `None` under a taken guard is still a `None`, so the conjunction
# collapses to a two-arm match rather than a fold.
def sp_and_vdr.go(facts: Bool, vdr: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  match vdr:
    case Some{v}: Some{Bool.and(facts, v)}
    case _: None{}

def sp_and_vdr(facts: Bool, vdr: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  sp_and_vdr.go(facts, vdr)

def OP_FUN1() -> List<&2, O.Op>:
  [O.OpsSIN{}, O.OpsLOG2{}, O.OpsEXP2{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}]

# ===========================================================================
# `spec_tensor` -- spec.py:143-202. Twenty-three rules, then `+ spec_shared`.
# `PatternMatcher.__add__` is `functools.cache`d list concatenation (ops.py:1597),
# so the table is this list FOLLOWED BY `shared_table()`'s, in that order, and the
# tag space restarts at 0.
# ===========================================================================
# spec.py:144 (UPat((Ops.SIN, Ops.LOG2, Ops.EXP2, Ops.SQRT, Ops.RECIPROCAL), src=(UPat(),), name="u"),
#              lambda u: dtypes.is_float(u.dtype) or u.src[0].base.is_invalid)
def te_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_FUN1()), nsrc_is(fx, self, 1)),
            sp_vb(Bool.or(sp_is_float(fx, self), sp_base_invalid(fx, sp_src(fx, self, 0)))))

def te_1.facts(+p: Pa) -> Bool:
  Bool.and(Pa.size(p), Bool.and(dopt_is(Pa.dev(p)), Pa.buf(p)))

def te_1.body.of(+p: Pa, srcs: List<&2, U32>, fx: F.Folded) -> Maybe<&1, Bool>:
  sp_and_vdr(te_1.facts(p), valid_device_range(Pa.dev(p), srcs, fx))

def te_1.body(+fx: F.Folded, +self: U32) -> Maybe<&1, Bool>:
  te_1.body.of(pa_of(fx, self), sp_srcs(fx, self), fx)

# spec.py:148 (UPat(Ops.BUFFER, name="buf"), lambda buf: isinstance(buf.dtype, DType) and
#              isinstance(buf.arg.size, int) and is_device(buf.arg.device) and
#              buf.arg.buffer is not None and valid_device_range(buf.arg.device, buf.src)
#              if isinstance(buf.arg, ParamArg) and buf.addrspace is AddrSpace.GLOBAL else None)
# `isinstance(buf.dtype, DType)` is vacuous: `S.Dt` IS the port's DType.
def te_1.guard(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Pa.ok(pa_of(fx, self)), addr_eq(addr_of(sp_addr(fx, self)), S.AGlobal{}))

def te_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsBUFFER{}), sp_vd(sp_tri_v(te_1.guard(fx, self), te_1.body(fx, self))))

def te_2.size_ok(+present: Bool) -> Bool:
  Bool.or(Bool.not(present), present)

# `isinstance(x.arg, ParamArg)`, `x.arg.buffer is None` and
# `x.arg.size is None or isinstance(x.arg.size, int)`. The last is a TAUTOLOGY in
# this port -- `size` is `Maybe<U32>` and "is an int" is "is not None" -- and it is
# written out anyway, so no conjunct is silently dropped.
def te_2.facts(+p: Pa) -> Bool:
  Bool.and(Pa.ok(p), Bool.and(Bool.not(Pa.buf(p)), te_2.size_ok(Pa.size(p))))

def te_2.addr.pick(is_global: Bool, in_set: Bool, none: Bool, named: Bool) -> Bool:
  Bool.and(in_set, Bool.or(none, Bool.and(is_global, named)))

def is_global_or_local_or_reg.go(+a: Maybe<&2, S.Addr>) -> Bool:
  Bool.or(addr_eq.go(a, S.AGlobal{}), is_reg_or_local.go(a))

def is_global_or_local_or_reg(a: Maybe<&2, S.Addr>) -> Bool:
  is_global_or_local_or_reg.go(a)

# `buf.addrspace in (GLOBAL, LOCAL, REG)` and
# `(buf.arg.device is None or (buf.addrspace is GLOBAL and is_device(buf.arg.device)))`.
def te_2.addr(+a: Maybe<&2, S.Addr>, +p: Pa) -> Bool:
  te_2.addr.pick(addr_eq.go(a, S.AGlobal{}), is_global_or_local_or_reg(a), dopt_none(Pa.dev(p)), dopt_is(Pa.dev(p)))

def te_2.body.pin(facts: Bool, vdr: Maybe<&1, Bool>) -> Bool:
  match vdr:
    case Some{v}: Bool.and(facts, v)
    case _: False{}

def te_2.body.of(+p: Pa, a: Maybe<&2, S.Addr>, vdr: Maybe<&1, Bool>) -> Bool:
  te_2.body.pin(Bool.and(te_2.facts(p), te_2.addr(a, p)), vdr)

def te_2.body(+fx: F.Folded, +self: U32) -> Bool:
  te_2.body.of(pa_of(fx, self), addr_of(sp_addr(fx, self)), valid_device_range(Pa.dev(pa_of(fx, self)), sp_srcs(fx, self), fx))

# spec.py:151 (UPat(Ops.ALLOC, name="buf"), lambda buf: isinstance(buf.arg, ParamArg) and
#              buf.addrspace in (AddrSpace.GLOBAL, AddrSpace.LOCAL, AddrSpace.REG) and
#              buf.arg.buffer is None and (buf.arg.size is None or isinstance(buf.arg.size, int)) and
#              (buf.arg.device is None or (buf.addrspace is AddrSpace.GLOBAL and
#                                         is_device(buf.arg.device))) and
#              valid_device_range(buf.arg.device, buf.src))
#
# NO TERNARY, so the lambda's answer is a plain `Bool` and a wrong ALLOC is `False`
# and not `None` -- the fold STOPS on it. And an undecidable `valid_device_range`
# has to be one or the other, and it is `False`: `True` would accept a
# multi-device ALLOC whose range this port has not checked, and a validator that
# accepts what it has not checked is worse than one that refuses.
def te_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsALLOC{}), sp_vb(te_2.body(fx, self)))

def te_3.guard.of(rng: Bool, alu: Bool, scalar: Bool) -> Bool:
  Bool.and(rng, Bool.and(alu, scalar))

def te_3.guard(+fx: F.Folded, +self: U32) -> Bool:
  te_3.guard.of(Pa.vrange(pa_of(fx, self)), addr_eq(addr_of(sp_addr(fx, self)), S.Aalu{}), sp_is_scalar(fx, self))

def te_3.body(fx: F.Folded, self: U32) -> Bool:
  dopt_none(Pa.dev(pa_of(fx, self)))

# spec.py:158 (UPat(Ops.PARAM, src=(), name="buf"), lambda buf: buf.arg.device is None if buf.is_variable else None)
# `is_variable` (ops.py:1018) is a PARAM with a ParamArg carrying a value range,
# the ALU addrspace AND a scalar shape -- all four, and all four are here.
def te_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 0)),
            sp_vd(sp_tri(te_3.guard(fx, self), te_3.body(fx, self))))

# spec.py:161 (UPat(Ops.SPECIAL, src=(UPat(dtype=dtypes.weakint),), name="s"), lambda s: isinstance(s.arg, str))
def te_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op(fx, self, O.OpsSPECIAL{}), sp_src_dt(fx, self, 0, S.weakint())), nsrc_is(fx, self, 1)),
            sp_vb(arg_str(sp_arg(fx, self))))

def OP_REEXP() -> List<&2, O.Op>:
  [O.OpsRESHAPE{}, O.OpsEXPAND{}]

# spec.py:164 (UPat((Ops.RESHAPE, Ops.EXPAND), src=(UPat(), UPat())), lambda: True)
def te_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_REEXP()), nsrc_is(fx, self, 2)), O.VTrue{})

def OP_PADSHRINK() -> List<&2, O.Op>:
  [O.OpsPAD{}, O.OpsSHRINK{}]

# spec.py:165 (UPat((Ops.PAD, Ops.SHRINK), src=(UPat(), UPat(), UPat()), name="x"),
#              lambda x: x.src[1].shape == x.src[2].shape)
def te_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_PADSHRINK()), nsrc_is(fx, self, 3)),
            sp_vb(sp_shape_same(fx, sp_src(fx, self, 1), sp_src(fx, self, 2))))

def OP_PERMFLIP() -> List<&2, O.Op>:
  [O.OpsPERMUTE{}, O.OpsFLIP{}]

# spec.py:166 (UPat((Ops.PERMUTE, Ops.FLIP), name="mv", src=(UPat(),)), lambda mv: isinstance(mv.arg, tuple))
def te_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_PERMFLIP()), nsrc_is(fx, self, 1)),
            sp_vb(some_list(arg_tuple(sp_arg(fx, self)))))

def te_8.body.pick(rop: Maybe<&1, O.Op>, widths: Bool) -> Bool:
  match rop:
    case Some{r}: Bool.and(O.GroupOp.reduce(r), widths)
    case _: False{}

def te_8.body.of(rop: Maybe<&1, O.Op>, widths: Bool) -> Bool:
  te_8.body.pick(rop, widths)

# `dtypes.ints` is `uints + sints` and `dtypes.weakint` is the weak sibling, so
# `(weakint, int)` is `is_int` plus `CWeakInt` -- and `S.Dt.is_int` already
# answers exactly `weakint | uint | sint`, so the whole disjunct is `is_int`.
def sp_int_or_weak(fx: F.Folded, s: U32) -> Bool:
  sp_is_int(fx, s)

def all_ints_or_weak(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_ints_or_weak(t, fx, Bool.and(acc, sp_int_or_weak(fx, s)))

def te_8.body(+fx: F.Folded, +self: U32) -> Bool:
  te_8.body.of(arg_reduce_op(sp_arg(fx, self)), all_ints_or_weak(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:169 (UPat(Ops.REDUCE, src=(UPat(),), allow_any_len=True, name="x"),
#              lambda x: isinstance(x.arg, tuple) and len(x.arg) == 2 and
#                x.arg[0] in GroupOp.Reduce and isinstance(x.arg[1], int) and
#                all(y.dtype in (dtypes.weakint, dtypes.i32) for y in x.src[1:]))
# `AReduce` IS that pair and `num_axes: U32` IS the `isinstance(..., int)`, so the
# `all(y.dtype in (weakint, int))` is the one left -- and `dtypes.i32` is the four
# signed widths PLUS the four unsigned (tinygrad/dtype.py:159), so it is `dtypes.ints`.
def te_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsREDUCE{}), nsrc_ge(fx, self, 1)), sp_vb(te_8.body(fx, self)))

def te_9.rest(+fx: F.Folded, +self: U32) -> Maybe<&1, Bool>:
  valid_device_range(dev_opt(arg_dev(sp_arg(fx, self))), sp_src_from(fx, self, 1), fx)

# spec.py:177 (UPat(Ops.COPY, name="copy", src=(UPat(),), allow_any_len=True), lambda copy:
#                is_device(copy.arg) and not is_disk_device(copy.arg) and
#                valid_device_range(copy.arg, copy.src[1:]))
#
# `is_disk_device` is `tinygrad/device.py`, which is P6 -- there is no device to
# ask. So the FIRST conjunct is decided and the SECOND IS NOT, and this rule answers
# `False` when the arg is not a device and `None` when it is, and `None` fails
# `type_verify` exactly as `False` does. See the TODO on `is_disk_device`.
def te_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsCOPY{}), nsrc_ge(fx, self, 1)),
            sp_vd(sp_tri_v(is_device(arg_dev(sp_arg(fx, self))), te_9.rest(fx, self))))

def te_10.body.pick(rop: Maybe<&1, O.Op>, dev: Bool) -> Bool:
  match rop:
    case Some{r}: Bool.and(O.GroupOp.reduce(r), dev)
    case _: False{}

def te_10.body.of(rop: Maybe<&1, O.Op>, dev: Bool) -> Bool:
  te_10.body.pick(rop, dev)

# `AAllred` is `(Ops, str|tuple)` and `AReduce` is `(Ops, int)`, and an ALLREDUCE's
# arg is the `AAllred`, so its `arg[0]` needs its own reader.
def arg_reduce_op_of_allred.go(a: O.Arg) -> Maybe<&1, O.Op>:
  match a:
    case O.AAllred{rop, dev}: Some{rop}
    case _: None{}

def arg_reduce_op_of_allred(a: O.Arg) -> Maybe<&1, O.Op>:
  arg_reduce_op_of_allred.go(a)

def te_10.body(+fx: F.Folded, +self: U32) -> Bool:
  te_10.body.of(arg_reduce_op_of_allred(sp_arg(fx, self)), is_device(arg_allred_dev(sp_arg(fx, self))))

# spec.py:176 (UPat(Ops.ALLREDUCE, name="red", src=(UPat(),)),
#              lambda red: isinstance(red.arg, tuple) and len(red.arg) == 2 and
#                red.arg[0] in GroupOp.Reduce and is_device(red.arg[1]))
def te_10(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsALLREDUCE{}), nsrc_is(fx, self, 1)), sp_vb(te_10.body(fx, self)))

def len_of(a: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, a))

def te_11.body.pick(ys: Maybe<&2, List<&2, U32>>, n: U32, weak: Bool) -> Bool:
  match ys:
    case Some{a}: Bool.and(U32.is_eq(n, U32.add(1, len_of(a))), weak)
    case _: False{}

def te_11.body.of(ys: Maybe<&2, List<&2, U32>>, n: U32, weak: Bool) -> Bool:
  te_11.body.pick(ys, n, weak)

def all_weak(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_weak(t, fx, Bool.and(acc, sp_is_weak(fx, s)))

def te_11.body(+fx: F.Folded, +self: U32) -> Bool:
  te_11.body.of(arg_tuple(sp_arg(fx, self)), sp_nsrc(fx, self), all_weak(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:181 (UPat(Ops.UNSHARD, name="multi"), lambda multi: len(multi.src) == 1+len(multi.arg)
#                and all(isinstance(a, int) for a in multi.arg)
#                and all(r.dtype in dtypes.weaks for r in multi.src[1:]))
# `all(isinstance(a, int) for a in multi.arg)` is `List<&2, U32>` being
# well-formed, so it is the TYPE and not a test.
def te_11(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsUNSHARD{}), sp_vb(te_11.body(fx, self)))

def mselect_lt.pick(a: List<&2, U32>, tags: List<&2, U32>) -> Bool:
  match a:
    case k <> _: U32.is_lt(k, len_of(tags))
    case _: False{}

def mselect_lt(a: List<&2, U32>, tags: List<&2, U32>) -> Bool:
  mselect_lt.pick(a, tags)

def mselect_ok.pick(d: Maybe<&2, S.Dev>, ys: Maybe<&2, List<&2, U32>>) -> Bool:
  match d ys:
    case Some{S.Dn{tags}} Some{a}: mselect_lt(a, tags)
    case _ _: False{}

def mselect_ok.of(d: Maybe<&2, S.Dev>, ys: Maybe<&2, List<&2, U32>>) -> Bool:
  mselect_ok.pick(d, ys)

def mselect_ok(+fx: F.Folded, +self: U32) -> Bool:
  mselect_ok.of(dev_of(sp_dev(fx, sp_src(fx, self, 0))), arg_tuple(sp_arg(fx, self)))

# spec.py:183 (UPat(Ops.MSELECT, name="x"),
#              lambda x: isinstance(x.src[0].device, tuple) and x.arg < len(x.src[0].device))
# `x.arg` is a bare int in Python; `Arg` has no bare-int constructor and
# `ops.bend` models MSELECT's arg as `ATuple`, so the index is its one element.
def te_12(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSELECT{}), sp_vb(mselect_ok(fx, self)))

def mstack_body.of(named: Bool, +srcs: List<&2, U32>, head_none: Bool) -> Bool:
  Bool.or(named, Bool.and(all_same(srcs, all_same_head(srcs), True{}), head_none))

def mstack_body(+fx: F.Folded, +self: U32) -> Bool:
  mstack_body.of(all_dev(sp_srcs(fx, self), fx, True{}), sp_srcs(fx, self),
    dopt_none(dev_opt(dev_of(sp_dev(fx, sp_src(fx, self, 0))))))

# spec.py:184 (UPat(Ops.MSTACK, name="x"),
#              lambda x: all(isinstance(s.device, str) for s in x.src)
#                        or (all_same(x.src) and x.src[0].device is None))
def te_13(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSTACK{}), sp_vb(mstack_body(fx, self)))

def OP_DETACH() -> List<&2, O.Op>:
  [O.OpsDETACH{}, O.OpsCONTIGUOUS_BACKWARD{}]

# spec.py:187 (UPat((Ops.DETACH, Ops.CONTIGUOUS_BACKWARD), src=(UPat(),), arg=None), lambda: True)
# `arg=None` in a `UPat` is NOT `self.arg is None` -- `upat.py:27` emits a clause
# only `if self.arg is not None` -- so it is a no-op here and the rule is an arity
# test and `True`.
def te_14(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_DETACH()), nsrc_is(fx, self, 1)), O.VTrue{})

# spec.py:190 (UPat(Ops.STAGE, src=(UPat(),), allow_any_len=True), lambda: True)
def te_15(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSTAGE{}), nsrc_ge(fx, self, 1)), O.VTrue{})

# spec.py:193 (UPat(Ops.LINEAR, dtypes.void), lambda: True)
def te_16(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsLINEAR{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:194 (UPat(Ops.SOURCE, dtypes.void, src=()), lambda: True)
def te_17(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op(fx, self, O.OpsSOURCE{}), sp_dt_is(fx, self, S.void())), nsrc_is(fx, self, 0)), O.VTrue{})

# the pipeline PREFIX, and it is cumulative: a 2-src PROGRAM has SINK and LINEAR, a
# 4-src one has all four. Positions at or past the arity are never asked about --
# `Arena.src` answers the bottom's op for an index past the end, so a shared "test
# all four" would fail a 1-src PROGRAM on a src it does not have.
def prog1(fx: F.Folded, self: U32) -> Bool:
  sp_src_op(fx, self, 0, O.OpsSINK{})

def prog2.of(a: Bool, b: Bool) -> Bool:
  Bool.and(a, b)

def prog2(+fx: F.Folded, +self: U32) -> Bool:
  prog2.of(prog1(fx, self), sp_src_op(fx, self, 1, O.OpsLINEAR{}))

def prog3(+fx: F.Folded, +self: U32) -> Bool:
  prog2.of(prog2(fx, self), sp_src_op(fx, self, 2, O.OpsSOURCE{}))

def prog4(+fx: F.Folded, +self: U32) -> Bool:
  prog2.of(prog3(fx, self), sp_src_op(fx, self, 3, O.OpsBINARY{}))

def prog_pat.of(op: Bool, d: Bool, n: Bool, srcs: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(n, srcs)))

def prog_pat(+fx: F.Folded, +self: U32, n: U32, srcs: Bool) -> Bool:
  prog_pat.of(sp_op(fx, self, O.OpsPROGRAM{}), sp_dt_is(fx, self, S.void()), nsrc_is(fx, self, n), srcs)

def te_18(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(prog_pat(fx, self, 1, prog1(fx, self)), O.VTrue{})

def te_19(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(prog_pat(fx, self, 2, prog2(fx, self)), O.VTrue{})

def te_20(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(prog_pat(fx, self, 3, prog3(fx, self)), O.VTrue{})

def te_21(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(prog_pat(fx, self, 4, prog4(fx, self)), O.VTrue{})

# ---------------------------------------------------------------------------
# THE TAG SHIFT, and it exists because `+` concatenates entry LISTS. ops.py:1597
# is `PatternMatcher(self.patterns+more.patterns)`, so `spec_tensor`'s entries are
# its own 23 followed by `spec_shared`'s 33, and the two index spaces COLLIDE:
# tag 0 would name `te_0` and `sh_0` at once. Python does not care, because a rule
# there is a closure and a dispatch is a call on it; here a tag NAMES A DEF, so
# the indices have to be made unique before the lists are joined. One shift and one
# fold, rather than a second thirty-three-line table per composed matcher.
# ---------------------------------------------------------------------------
def bump.one(+n: U32, e: O.PMEntry) -> O.PMEntry:
  match e:
    case O.PMEntry{tag, ops, rej}: O.PMEntry{U32.add(n, tag), ops, rej}

def bump.go2(es: List<&2, O.PMEntry>, +n: U32, acc: List<&2, O.PMEntry>) -> O.PMEntrys:
  match es:
    case Nil{}: O.PMEntrys{acc}
    case e <> t: bump.go2(t, n, List.append(&2, O.PMEntry, acc, [bump.one(n, e)]))

def bump.go(+n: U32, es: List<&2, O.PMEntry>, acc: List<&2, O.PMEntry>) -> O.PMEntrys:
  bump.go2(es, n, acc)

def bump(n: U32, ts: O.PMEntrys) -> O.PMEntrys:
  bump.go(n, O.PMEntrys.es(ts), Nil{})

# ---------------------------------------------------------------------------
# THE TWENTY-THIRD TENSOR RULE -- RESOLVED 2026-10-03, AND THE ROOT CAUSE IS NOT
# WHAT THE OLD TEXT SAID. It is kept because the OLD TEXT was wrong in an instructive
# way, and because the reason it was wrong is the one thing a reader needs here.
#
# THE OLD TEXT claimed `tensor_own()` was "CPython's 22 tensor rules plus a DUPLICATE of
# one of the 33 shared ones" -- i.e. a rule the port's author added by mistake. THAT IS
# WRONG, and the pin settles it:
#
#     git show 6c3d401cf324:tinygrad/uop/spec.py     # OUR PIN
#
# At the pin, `spec_tensor`'s fourth rule WAS `Ops.CUSTOM_FUNCTION`, at spec.py:161, and
# it took THREE lines -- a blank, the comment `# custom function`, and the rule. At HEAD
# it is GONE, and upstream's `spec_shared` CUSTOM_FUNCTION rule changed with it:
#
#     PIN   (UPat(Ops.CUSTOM_FUNCTION, name="x", allow_any_len=True),
#            lambda x: isinstance(x.arg, str))
#     HEAD  (UPat(Ops.CUSTOM_FUNCTION, name="x", allow_any_len=True),
#            lambda x: isinstance(x.arg, CustomFunction))
#
# So upstream stopped giving a CUSTOM_FUNCTION a `str` arg and started giving it a
# `CustomFunction` object stating the return dtype. The tensor rule that asserted
# `isinstance(x.arg, str)` became FALSE for every such node, so it was DELETED rather than
# left to reject. The port was CORRECT at the pin and upstream moved -- which is why the
# old text called the count a DUPLICATE: from HEAD it looks exactly like one.
#
# THE THREE-LINE TELL WAS THE CLUE AND IT WAS READ BACKWARDS. Every `# NN` on the rows
# from row 4 down was three too high -- 164 for a rule now at 161, 167 for 164, and so on
# to 201 for 198 -- and rows 0..3 were exact. Three extra lines inside `spec_tensor`,
# below row 3, is the deletion itself. The port read that as "the citations drifted", when
# the citations were the only thing still remembering the pin. `.agents/slop/
# spec-citations.py` now derives every one of them from spec.py's AST (`--check` to
# verify), so they cannot drift again; it rewrote 51 of them across `tensor_own`,
# `program_own` and `hcq_own`, and NO GATE ROW MOVED, which is what a comment-only change
# should look like.
#
# WHAT THE DELETION WAS WORTH. `tensor_table()` was 23 + 33 = 56 and is now 22 + 33 = 55,
# which is CPython's. `te_len` moved 56 -> 55 and `fu_len` 71 -> 70, and both were RED
# before and are green now, read from `.agents/slop/rebase-oracle-spec.py` calling the real
# `tinygrad.uop.spec`. A CUSTOM_FUNCTION node is no longer scanned twice either -- once by
# `sh_22` and again by `te_4` -- which changed no ANSWER, because first-wins made the
# second unreachable.
#
# THE DELETE WAS NOT ONE LINE, AND THAT IS THE PART TO CARRY AWAY. Renaming the rule defs
# and renumbering the table was the easy half. THREE THINGS ELSE READ THE SAME NUMBERS and
# had to move with it, and each of the three failed SILENTLY -- compiled, ran, raised
# nothing, and answered a different question:
#
#   * `te_dispatch.go`'s ladder still read `case N: te_(N-1)` for every N from 5 up, so
#     tag 5 answered `te_4` and tag 21 answered `te_20`. Renaming the right-hand sides of
#     a `match` does NOT renumber its left-hand arms, and that is precisely the trap in
#     agent-core.md: a tag that stops selecting the rule it was written for lands on a
#     DIFFERENT rule.
#   * `full_table.go`'s bumps went to 26 / 59 / 68 while `fu_dispatch.of` still subtracted
#     27 / 60 / 69, so every tag past `full_own`'s four entered the wrong table.
#   * `t_tag_rej` read `entry_at(tensor_own(), 22)` for the four-src PROGRAM rule, which
#     had moved to 21 -- so it read the three-src rule's reject set instead, which is 3
#     where the row demands 4. That one the row caught.
#
# `spec-offsets.py` now checks all fourteen offsets against the table sizes AND checks that
# every dispatch ladder reads `case N: _N` pairwise. Those three bugs are why it exists.
# ---------------------------------------------------------------------------
# THE TABLE. `spec.py:199` is `])+spec_shared`, so this list is followed by
# `shared_table()`'s, in that order. The `# NN` on each row is the spec.py line the rule
# came from, DERIVED from spec.py's AST rather than transcribed.
# ---------------------------------------------------------------------------
def tensor_own() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0,  OP_FUN1(),                    Nil{}},   # 144
    O.PMEntry{1,  [O.OpsBUFFER{}],              Nil{}},   # 148
    O.PMEntry{2,  [O.OpsALLOC{}],               Nil{}},   # 151
    O.PMEntry{3,  [O.OpsPARAM{}],               Nil{}},   # 158
    O.PMEntry{4,  [O.OpsSPECIAL{}],             Nil{}},   # 161
    O.PMEntry{5,  OP_REEXP(),                   Nil{}},   # 164
    O.PMEntry{6,  OP_PADSHRINK(),               Nil{}},   # 165
    O.PMEntry{7,  OP_PERMFLIP(),                Nil{}},   # 166
    O.PMEntry{8,  [O.OpsREDUCE{}],              Nil{}},   # 169
    O.PMEntry{9, [O.OpsCOPY{}],                Nil{}},   # 174
    O.PMEntry{10, [O.OpsALLREDUCE{}],           Nil{}},   # 176
    O.PMEntry{11, [O.OpsUNSHARD{}],             Nil{}},   # 181
    O.PMEntry{12, [O.OpsMSELECT{}],             Nil{}},   # 183
    O.PMEntry{13, [O.OpsMSTACK{}],              Nil{}},   # 184
    O.PMEntry{14, OP_DETACH(),                  Nil{}},   # 187
    O.PMEntry{15, [O.OpsSTAGE{}],               Nil{}},   # 190
    O.PMEntry{16, [O.OpsLINEAR{}],              Nil{}},   # 193
    O.PMEntry{17, [O.OpsSOURCE{}],              Nil{}},   # 194
    O.PMEntry{18, [O.OpsPROGRAM{}],             [O.OpsSINK{}]},                     # 195
    O.PMEntry{19, [O.OpsPROGRAM{}],             [O.OpsSINK{}, O.OpsLINEAR{}]},      # 196
    O.PMEntry{20, [O.OpsPROGRAM{}],             [O.OpsSINK{}, O.OpsLINEAR{}, O.OpsSOURCE{}]},       # 197
    O.PMEntry{21, [O.OpsPROGRAM{}],             [O.OpsSINK{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{}]}]}  # 198

def tensor_table() -> O.PMEntrys:
  O.PMEntrys{List.append(&2, O.PMEntry, O.PMEntrys.es(tensor_own()), O.PMEntrys.es(bump(22, shared_table())))}

def te_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: te_0(fx, self)
    case 1: te_1(fx, self)
    case 2: te_2(fx, self)
    case 3: te_3(fx, self)
    case 4: te_4(fx, self)
    case 5: te_5(fx, self)
    case 6: te_6(fx, self)
    case 7: te_7(fx, self)
    case 8: te_8(fx, self)
    case 9: te_9(fx, self)
    case 10: te_10(fx, self)
    case 11: te_11(fx, self)
    case 12: te_12(fx, self)
    case 13: te_13(fx, self)
    case 14: te_14(fx, self)
    case 15: te_15(fx, self)
    case 16: te_16(fx, self)
    case 17: te_17(fx, self)
    case 18: te_18(fx, self)
    case 19: te_19(fx, self)
    case 20: te_20(fx, self)
    case 21: te_21(fx, self)
    case _: sh_dispatch(U32.sub(tag, 22), fx, self)

def te_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  te_dispatch.go(tag, fx, self)

def te_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: te_dispatch(tag, fx, self)
    case _: O.VSkip{}

def te_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  te_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def te_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: te_scan(ts, fx, self, t, O.pm_keep(acc, te_try(ts, fx, self, e)))

def te_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  te_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def tensor_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  te_rewrite(tensor_table(), fx, self)

# `GroupOp.All` is every op, so the "claim" is just "there is an op here", which is
# what `Arena.op` answers for a live index.
def pr_0.claims(fx: F.Folded, self: U32) -> Bool:
  Bool.not(O.UOp.is_none(self))

def pr_0.body(fx: F.Folded, self: U32) -> Bool:
  Bool.not(sp_op(fx, self, O.OpsCAST{}))

# ===========================================================================
# `spec_program` -- spec.py:205-228. Nine rules, then `+ spec_shared`.
# "these ops can exist in programs but not the tensor spec. example: LOAD"
# ===========================================================================
# spec.py:204 (UPat(GroupOp.All, name="x"),
#              lambda x: False if x.op is not Ops.CAST and any(s.op is Ops.CONST for s in x.src) else None)
# A CONST under anything but a CAST is not allowed in a program: every width is
# stated by the CAST, and a bare CONST is a vconst that survived lowering.
def pr_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_0.claims(fx, self), sp_vd(sp_tri(pr_0.body(fx, self), False{})))

# spec.py:205 (UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks), lambda: False)
# `dtypes.weaks` is a TWO-element set, so upat.py:35 emits `dtype in {weakint,
# weakfloat}` -- a class test, and the only weak node in a program is illegal.
def pr_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(pr_0.claims(fx, self), sp_is_weak(fx, self)), O.VFalse{})

def pr_2.pat.of(op: Bool, b: Bool, c: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(b, Bool.and(c, n)))

def pr_2.pat(+fx: F.Folded, +self: U32) -> Bool:
  pr_2.pat.of(sp_op(fx, self, O.OpsSHRINK{}), buf_or_bitcasted(fx, sp_src(fx, self, 0)),
              const_or_casted(fx, sp_src(fx, self, 2)), nsrc_is(fx, self, 3))

# spec.py:208 (UPat(Ops.SHRINK, src=(UPat((Ops.PARAM, Ops.BUFFER, Ops.ALLOC, Ops.AFTER))
#                     .or_bitcasted(), UPat(), UPat.cvar().or_casted())), lambda: True)
def pr_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_2.pat(fx, self), O.VTrue{})

# spec.py:211 (UPat(GroupOp.Movement), lambda: False)
# movement ops are not allowed in programs. A REPLACEMENT, not a skip: a RESHAPE in
# a program graph is wrong even though `spec_tensor` accepts one.
def pr_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(O.GroupOp.movement(O.Arena.op(sp_ar(fx), self)), O.VFalse{})

def OP_BA() -> List<&2, O.Op>:
  [O.OpsBUFFER{}, O.OpsALLOC{}]

# spec.py:214 (UPat((Ops.BUFFER, Ops.ALLOC), name="x"),
#              lambda x: isinstance(x.arg, ParamArg) and x.addrspace in (AddrSpace.REG, AddrSpace.LOCAL))
def pr_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, OP_BA()), sp_vb(Bool.and(Pa.ok(pa_of(fx, self)), is_reg_or_local(addr_of(sp_addr(fx, self))))))

# spec.py:217 (UPat(Ops.CONST, arg=Invalid), lambda: False)
def pr_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsCONST{}), arg_const_invalid(sp_arg(fx, self))), O.VFalse{})

def pr_6.pat.of(op: Bool, d: Bool, g: Bool, i: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(g, Bool.and(i, n))))

def OP_CIS() -> List<&2, O.Op>:
  [O.OpsCAST{}, O.OpsINDEX{}, O.OpsSHRINK{}]

def pr_6.pat(+fx: F.Folded, +self: U32) -> Bool:
  pr_6.pat.of(sp_op(fx, self, O.OpsIF{}), sp_dt_is(fx, self, S.void()),
              sp_src_dt(fx, self, 0, S.boolean()), sp_src_in(fx, self, 1, OP_CIS()), nsrc_is(fx, self, 2))

# spec.py:220 (UPat(Ops.IF, dtype=dtypes.void,
#                    src=(UPat(dtype=dtypes.bool), UPat((Ops.CAST, Ops.INDEX, Ops.SHRINK)))), lambda: True)
def pr_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_6.pat(fx, self), O.VTrue{})

def pr_7.pat.of(op: Bool, d: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, n)))

def pr_7.pat(+fx: F.Folded, +self: U32) -> Bool:
  pr_7.pat.of(sp_op(fx, self, O.OpsENDIF{}), sp_dt_is(fx, self, S.void()),
              sp_src_op(fx, self, 0, O.OpsIF{}), nsrc_is(fx, self, 1))

# spec.py:221 (UPat(Ops.ENDIF, dtype=dtypes.void, src=(UPat(Ops.IF),)), lambda: True)
# the second non-empty `early_reject`: `src[0]` is a single-op upat, so `[IF]`.
def pr_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_7.pat(fx, self), O.VTrue{})

# spec.py:224 (UPat(Ops.SPECIAL, src=(UPat(dtype=dtypes.i32),), name="s"), lambda s: isinstance(s.arg, str))
# SPECIAL is weakint before index lowering (spec.py:164) and int32 after (here).
def pr_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op(fx, self, O.OpsSPECIAL{}), sp_src_dt(fx, self, 0, S.int32())), nsrc_is(fx, self, 1)),
            sp_vb(arg_str(sp_arg(fx, self))))

# `GroupOp.All` is the whole enum, and `Arena.op` answers `Op`, so the set is
# every constructor `ops.bend` declares. Writing it out is the alternative to a
# `Bool`-per-op predicate, and it is what `pdict` does anyway.
def OP_ALL() -> List<&2, O.Op>:
  [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{},
   O.OpsPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{},
   O.OpsPYLITERAL{}, O.OpsSINK{}, O.OpsAFTER{}, O.OpsGROUP{}, O.OpsSTACK{}, O.OpsGETADDR{},
   O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{},
   O.OpsBITCAST{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{},
   O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{},
   O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{},
   O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{},
   O.OpsEND{}, O.OpsENDIF{}, O.OpsBACKEDGE{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{},
   O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}, O.OpsCOPY{}, O.OpsMSELECT{},
   O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{},
   O.OpsPAD{}, O.OpsFLIP{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}]

def OP_MOVE() -> List<&2, O.Op>:
  [O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]

def program_own() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, OP_ALL(),                   Nil{}},   # 204
    O.PMEntry{1, OP_ALL(),                   Nil{}},   # 205
    O.PMEntry{2, [O.OpsSHRINK{}],            Nil{}},   # 208
    O.PMEntry{3, OP_MOVE(),                  Nil{}},   # 211
    O.PMEntry{4, OP_BA(),                    Nil{}},   # 214
    O.PMEntry{5, [O.OpsCONST{}],             Nil{}},   # 217
    O.PMEntry{6, [O.OpsIF{}],                Nil{}},   # 220
    O.PMEntry{7, [O.OpsENDIF{}],             [O.OpsIF{}]},   # 221
    O.PMEntry{8, [O.OpsSPECIAL{}],           Nil{}}]}  # 224

def program_table() -> O.PMEntrys:
  O.PMEntrys{List.append(&2, O.PMEntry, O.PMEntrys.es(program_own()), O.PMEntrys.es(bump(9, shared_table())))}

def pr_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: pr_0(fx, self)
    case 1: pr_1(fx, self)
    case 2: pr_2(fx, self)
    case 3: pr_3(fx, self)
    case 4: pr_4(fx, self)
    case 5: pr_5(fx, self)
    case 6: pr_6(fx, self)
    case 7: pr_7(fx, self)
    case 8: pr_8(fx, self)
    case _: sh_dispatch(U32.sub(tag, 9), fx, self)

def pr_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  pr_dispatch.go(tag, fx, self)

def pr_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: pr_dispatch(tag, fx, self)
    case _: O.VSkip{}

def pr_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  pr_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def pr_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: pr_scan(ts, fx, self, t, O.pm_keep(acc, pr_try(ts, fx, self, e)))

def pr_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  pr_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def program_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  pr_rewrite(program_table(), fx, self)

def hq_0.pat.of(op: Bool, d: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, n)))

def OP_HCQ0() -> List<&2, O.Op>:
  [O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsPARAM{}, O.OpsSHRINK{}, O.OpsBITCAST{},
   O.OpsMSTACK{}, O.OpsMSELECT{}, O.OpsLINEAR{}]

def hq_0.pat(+fx: F.Folded, +self: U32) -> Bool:
  hq_0.pat.of(sp_op(fx, self, O.OpsGETADDR{}), sp_dt_is(fx, self, S.uint64()),
              after_or(fx, sp_src(fx, self, 0), OP_HCQ0()), nsrc_is(fx, self, 1))

# ===========================================================================
# `spec_hcq` -- spec.py:230-235. Two rules, then `+ spec_shared`. The device
# queues: a GETADDR takes a device and a PROGRAM takes the bound buffers.
# ===========================================================================
# spec.py:228 (UPat(Ops.GETADDR, dtypes.u64, name="x",
#                    src=(UPat((BUFFER, ALLOC, PARAM, SHRINK, BITCAST, MSTACK, MSELECT, LINEAR))
#                         .or_after(),)), lambda x: is_device(x.arg))
#
# The `or_after` is a DISJUNCTION (`after_or`), and `hcq_plain` / `hcq_after` are
# the two gate rows that check it stayed one: a conjunction would accept only
# `GETADDR(AFTER(...))` and reject the bare `GETADDR(BUFFER)` that real graphs
# have in bulk.
def hq_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(hq_0.pat(fx, self), sp_vb(is_device(arg_dev(sp_arg(fx, self)))))

def hq_1.pat.of(op: Bool, d: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, n)))

def OP_HCQ1() -> List<&2, O.Op>:
  [O.OpsBUFFER{}, O.OpsPARAM{}]

def hq_1.pat(+fx: F.Folded, +self: U32) -> Bool:
  hq_1.pat.of(sp_op(fx, self, O.OpsPROGRAM{}), sp_dt_is(fx, self, S.void()),
              after_or(fx, sp_src(fx, self, 0), OP_HCQ1()), nsrc_is(fx, self, 1))

# spec.py:231 (UPat(Ops.PROGRAM, dtypes.void, src=(UPat((Ops.BUFFER, Ops.PARAM)).or_after(),)),
#              lambda: True)
def hq_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(hq_1.pat(fx, self), O.VTrue{})

def hcq_own() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsGETADDR{}],  Nil{}},   # 228
    O.PMEntry{1, [O.OpsPROGRAM{}], Nil{}}]}  # 231

def hcq_table() -> O.PMEntrys:
  O.PMEntrys{List.append(&2, O.PMEntry, O.PMEntrys.es(hcq_own()), O.PMEntrys.es(bump(2, shared_table())))}

def hq_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: hq_0(fx, self)
    case 1: hq_1(fx, self)
    case _: sh_dispatch(U32.sub(tag, 2), fx, self)

def hq_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  hq_dispatch.go(tag, fx, self)

def hq_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: hq_dispatch(tag, fx, self)
    case _: O.VSkip{}

def hq_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  hq_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def hq_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: hq_scan(ts, fx, self, t, O.pm_keep(acc, hq_try(ts, fx, self, e)))

def hq_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  hq_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def hcq_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  hq_rewrite(hcq_table(), fx, self)

# ===========================================================================
# `spec_full` -- spec.py:238-250. Four rules, then
# `+ spec_tensor + spec_program + spec_hcq`, and each of those is its own list
# followed by `spec_shared` again.
#
# PYTHON'S LITERAL LIST IS 137 ENTRIES AND FOUR OF THIS FILE'S BLOCKS ARE
# 4 + 23 + 33 + 9 + 2 = 71. THE OTHER 66 ARE DEAD: `spec_shared` appears three times
# in `spec_full`'s 137 and only the FIRST is reachable, because the fold is
# first-wins -- a rule that skipped in the first block skips again in the second,
# and a rule that answered has already stopped the fold. `full_len` in the gate is
# the row that states the count.
# ===========================================================================
# spec.py:239 (UPat(Ops.REWRITE_ERROR, dtypes.void, name="x"), lambda x: isinstance(x.arg, str))
def fu_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsREWRITE_ERROR{}), sp_dt_is(fx, self, S.void())),
            sp_vb(arg_str(sp_arg(fx, self))))

def fu_1.pat.of(op: Bool, d: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, n))

def fu_1.pat(+fx: F.Folded, +self: U32) -> Bool:
  fu_1.pat.of(sp_op(fx, self, O.OpsEND{}), sp_src_dt(fx, self, 0, S.void()), nsrc_ge(fx, self, 2))

def fu_1.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(arg_none(sp_arg(fx, self)), all_int(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:242 (UPat(Ops.END, src=(UPat(dtype=dtypes.void), UPat()), allow_any_len=True, name="x"),
#              lambda x: x.arg is None and all(dtypes.is_int(u.dtype) for u in x.src[1:]))
# `spec_full`'s END is WEAKER than `spec_shared`'s (spec.py:85): it drops the
# `op is RANGE` half. So a well-formed END matches BOTH, `fu_1` comes first, and
# its verdict is the one that stands.
def fu_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(fu_1.pat(fx, self), sp_vb(fu_1.body(fx, self)))

# spec.py:246 (UPat(Ops.AFTER, src=(UPat(),), allow_any_len=True), lambda: True)
# "allow any AFTER": this is the INTERMEDIATE spec, where everything should have
# been deleted by now, so it is deliberately the loosest of the three AFTER rules.
def fu_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsAFTER{}), nsrc_ge(fx, self, 1)), O.VTrue{})

# spec.py:249 (UPat((Ops.LOAD, Ops.STORE)), lambda: True) -- all loads/stores
def fu_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, [O.OpsLOAD{}, O.OpsSTORE{}]), O.VTrue{})

def full_table.go(a: List<&2, O.PMEntry>, b: List<&2, O.PMEntry>, c: List<&2, O.PMEntry>, d: List<&2, O.PMEntry>, e: List<&2, O.PMEntry>) -> O.PMEntrys:
  O.PMEntrys{List.append(&2, O.PMEntry, a, List.append(&2, O.PMEntry, b, List.append(&2, O.PMEntry, c, List.append(&2, O.PMEntry, d, e))))}

def full_own() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsREWRITE_ERROR{}], Nil{}},   # 239
    O.PMEntry{1, [O.OpsEND{}],             Nil{}},   # 242
    O.PMEntry{2, [O.OpsAFTER{}],           Nil{}},   # 246
    O.PMEntry{3, [O.OpsLOAD{}, O.OpsSTORE{}], Nil{}}]}  # 249

def full_table() -> O.PMEntrys:
  full_table.go(O.PMEntrys.es(full_own()), O.PMEntrys.es(bump(4, tensor_own())),
    O.PMEntrys.es(bump(26, shared_table())), O.PMEntrys.es(bump(59, program_own())),
    O.PMEntrys.es(bump(68, hcq_own())))

def fu_block.last(c: Bool) -> U32:
  match c:
    case True{}: 3
    case _: 4

def fu_block.rest(b: Bool, c: Bool) -> U32:
  match b:
    case True{}: 2
    case _: fu_block.last(c)

def fu_block.pick(a: Bool, b: Bool, c: Bool) -> U32:
  match a:
    case True{}: 1
    case _: fu_block.rest(b, c)

# WHICH BLOCK, as a number rather than as a Bool per boundary. A `match` may not
# scrutinise a call, so the three comparisons have to cross a def boundary as three
# Bools and be re-joined here -- and joining them as a number is what lets the
# dispatch below be a four-arm `match` instead of a nine-def ladder.
def fu_block.go(+tag: U32) -> U32:
  fu_block.pick(U32.is_lt(tag, 27), U32.is_lt(tag, 60), U32.is_lt(tag, 69))

def fu_block(tag: U32) -> U32:
  fu_block.go(tag)

# the tag spaces of the four blocks, each with its own dispatch and its base
# subtracted: 4-25 `spec_tensor` (22 own + 33 shared), 26-58 `spec_shared`,
# 59-67 `spec_program` (9 own), 68-69 `spec_hcq` (2 own).
#
# EVERY NUMBER HERE IS SPELLED TWICE -- once as the `bump(N, ...)` that builds the table
# and once as the `U32.sub(tag, N)` below -- and NOTHING TIES THE TWO TOGETHER. Deleting
# one rule rebased `full_table.go` to 26 / 59 / 68 and left these four still at 27 / 60 /
# 69, so every tag past `full_own`'s four entered the WRONG table's dispatch. It compiled,
# it ran, and it raised nothing. `.agents/slop/spec-offsets.py` checks all fourteen
# offsets against the table sizes AND checks that every ladder reads `case N: _N`.
def fu_dispatch.of(blk: U32, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match blk:
    case 1: te_dispatch(U32.sub(tag, 4), fx, self)
    case 2: sh_dispatch(U32.sub(tag, 26), fx, self)
    case 3: pr_dispatch(U32.sub(tag, 59), fx, self)
    case _: hq_dispatch(U32.sub(tag, 68), fx, self)

def fu_dispatch.go(+tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: fu_0(fx, self)
    case 1: fu_1(fx, self)
    case 2: fu_2(fx, self)
    case 3: fu_3(fx, self)
    case _: fu_dispatch.of(fu_block(tag), tag, fx, self)

def fu_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  fu_dispatch.go(tag, fx, self)

def fu_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: fu_dispatch(tag, fx, self)
    case _: O.VSkip{}

def fu_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  fu_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def fu_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: fu_scan(ts, fx, self, t, O.pm_keep(acc, fu_try(ts, fx, self, e)))

def fu_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  fu_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def full_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  fu_rewrite(full_table(), fx, self)

# ===========================================================================
# `spec_kernel_graph` -- spec.py:254-280. Thirteen rules and NOTHING appended:
# this is the only table with no `+ spec_shared`, and the gate row `noop_kg` is
# what checks it. A NOOP is legal in every other table and is a `VSkip` here, so
# the row moves the moment a `spec_shared` block is concatenated onto this one.
# ===========================================================================
# spec.py:256 (UPat(Ops.SINK, dtypes.void), lambda: True)
def kg_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSINK{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:258 (UPat(Ops.CONST, src=()), lambda: True) -- vconsts and shape args
def kg_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsCONST{}), nsrc_is(fx, self, 0)), O.VTrue{})

def kg_2.pat.of(op: Bool, i: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(i, n))

def kg_2.inner.of(is_const: Bool, n: U32) -> Bool:
  Bool.and(is_const, U32.is_eq(n, 0))

def kg_2.inner(+fx: F.Folded, +self: U32) -> Bool:
  kg_2.inner.of(sp_src_op(fx, self, 0, O.OpsCONST{}), O.Arena.nsrc(sp_ar(fx), sp_src(fx, self, 0)))

def kg_2.pat(+fx: F.Folded, +self: U32) -> Bool:
  kg_2.pat.of(sp_op(fx, self, O.OpsCAST{}), kg_2.inner(fx, self), nsrc_is(fx, self, 1))

# spec.py:259 (UPat(Ops.CAST, src=(UPat(Ops.CONST, src=()),)), lambda: True)
# the third non-empty `early_reject`: the inner CONST is a single-op upat, so `[CONST]`.
# "a 0-size/bound reduce keeps its const casted" is the whole comment.
def kg_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(kg_2.pat(fx, self), O.VTrue{})

# spec.py:260 (UPat(Ops.STACK, name="s"),
#              lambda s: all(x.op in (Ops.CONST, Ops.PARAM) for x in s.src) or None)
def kg_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsSTACK{}), sp_vd(sp_tri(all_const_or_param(sp_srcs(fx, self), fx, True{}), True{})))

# spec.py:264 (UPat(Ops.PARAM, src=(), name="x"), lambda x: isinstance(x.arg, ParamArg))
def kg_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 0)), sp_vb(Pa.ok(pa_of(fx, self))))

def kg_5.holder.pin(is_global: Bool, small: Bool, buf: Bool) -> Bool:
  match is_global:
    case True{}: buf
    case _: small

def kg_5.holder.pick(is_global: Bool, small: Bool, buf: Bool) -> Bool:
  kg_5.holder.pin(is_global, small, buf)

# the ternary again: GLOBAL wants a buffer, LOCAL and REG do not.
def kg_5.holder(+a: Maybe<&2, S.Addr>, p: Pa) -> Bool:
  kg_5.holder.pick(addr_eq.go(a, S.AGlobal{}), is_reg_or_local.go(a), Pa.buf(p))

def kg_5.body.pin(facts: Bool, vdr: Maybe<&1, Bool>) -> Bool:
  match vdr:
    case Some{v}: Bool.and(facts, v)
    case _: False{}

def kg_5.body.of(+p: Pa, a: Maybe<&2, S.Addr>, vdr: Maybe<&1, Bool>) -> Bool:
  kg_5.body.pin(Bool.and(Pa.ok(p), kg_5.holder(a, p)), vdr)

def kg_5.body(+fx: F.Folded, +self: U32) -> Bool:
  kg_5.body.of(pa_of(fx, self), addr_of(sp_addr(fx, self)),
               valid_device_range(Pa.dev(pa_of(fx, self)), sp_srcs(fx, self), fx))

# spec.py:265 (UPat(Ops.BUFFER, name="x"), lambda x: isinstance(x.arg, ParamArg) and
#              valid_device_range(x.arg.device, x.src) and
#              (x.arg.buffer is not None if x.addrspace is AddrSpace.GLOBAL
#                            else x.addrspace in (AddrSpace.LOCAL, AddrSpace.REG)))
def kg_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsBUFFER{}), sp_vb(kg_5.body(fx, self)))

def kg_6.body.pin(facts: Bool, vdr: Maybe<&1, Bool>) -> Bool:
  match vdr:
    case Some{v}: Bool.and(facts, v)
    case _: False{}

def kg_6.body.of(+p: Pa, a: Maybe<&2, S.Addr>, vdr: Maybe<&1, Bool>) -> Bool:
  kg_6.body.pin(Bool.and(Pa.ok(p), Bool.and(addr_eq.go(a, S.AGlobal{}), Bool.not(Pa.buf(p)))), vdr)

def kg_6.body(+fx: F.Folded, +self: U32) -> Bool:
  kg_6.body.of(pa_of(fx, self), addr_of(sp_addr(fx, self)),
               valid_device_range(Pa.dev(pa_of(fx, self)), sp_srcs(fx, self), fx))

# spec.py:267 (UPat(Ops.ALLOC, name="x"), lambda x: isinstance(x.arg, ParamArg) and
#              x.addrspace is AddrSpace.GLOBAL and x.arg.buffer is None and
#              valid_device_range(x.arg.device, x.src))
def kg_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsALLOC{}), sp_vb(kg_6.body(fx, self)))

# spec.py:269 (UPat(Ops.BITCAST), lambda: True)
def kg_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsBITCAST{}), O.VTrue{})

# spec.py:271 (UPat(Ops.MSTACK, name="x"),
#              lambda x: all(isinstance(s.device, str) for s in x.src)
#                        or (all_same(x.src) and x.src[0].device is None))
# the same body as spec.py:187, and `mstack_body` is that body -- one def, two rules,
# because the two are textually the same expression and a port that wrote it twice
# would be a port with two things to keep in step.
def kg_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSTACK{}), sp_vb(mstack_body(fx, self)))

# spec.py:272 (UPat(Ops.MSELECT, name="x"),
#              lambda x: isinstance(x.src[0].device, tuple) and x.arg < len(x.src[0].device))
def kg_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSELECT{}), sp_vb(mselect_ok(fx, self)))

def kg_10.axis.go(ax: Maybe<&1, O.AxisType>) -> Bool:
  match ax:
    case Some{at}: O.eq_axis(at, O.AXIS_DEVICE{})
    case _: False{}

def kg_10.axis(a: O.Arg) -> Bool:
  kg_10.axis.go(arg_axis(a))

# spec.py:274 (UPat(Ops.RANGE, name="r"), lambda r: r.axis_type is AxisType.DEVICE)
# "open DEVICE ranges are bound per device at launch (e.g. the range on a
# multi-device BUFFER/ALLOC)". `ARange` carries the axis type as a field, so this
# is the arg and nothing else.
def kg_10(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsRANGE{}), sp_vb(kg_10.axis(sp_arg(fx, self))))

def kg_11.pat.of(op: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(s, n))

def kg_11.pat(+fx: F.Folded, +self: U32) -> Bool:
  kg_11.pat.of(sp_op(fx, self, O.OpsCALL{}), sh_23.body_op(fx, self), nsrc_ge(fx, self, 1))

# spec.py:276 (UPat(Ops.CALL, src=(UPat(tuple(OPAQUE_CALL_BODIES)),), allow_any_len=True), lambda: True)
def kg_11(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(kg_11.pat(fx, self), O.VTrue{})

def kg_12.pat.of(op: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(s, n))

def OP_AFTER12() -> List<&2, O.Op>:
  [O.OpsPARAM{}, O.OpsAFTER{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsMSTACK{}, O.OpsMSELECT{},
   O.OpsBITCAST{}, O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]

def kg_12.pat(+fx: F.Folded, +self: U32) -> Bool:
  kg_12.pat.of(sp_op(fx, self, O.OpsAFTER{}), sp_src_in(fx, self, 0, OP_AFTER12()), nsrc_ge(fx, self, 1))

# spec.py:278 (UPat(Ops.AFTER, src=(UPat(Movement|PARAM|AFTER|BUFFER|ALLOC|MSTACK|MSELECT|
#                     BITCAST|RESHAPE),), allow_any_len=True), lambda: True)
def kg_12(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(kg_12.pat(fx, self), O.VTrue{})

def kernel_graph_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0,  [O.OpsSINK{}],      Nil{}},          # 256
    O.PMEntry{1,  [O.OpsCONST{}],     Nil{}},          # 258
    O.PMEntry{2,  [O.OpsCAST{}],      [O.OpsCONST{}]}, # 259
    O.PMEntry{3,  [O.OpsSTACK{}],     Nil{}},          # 260
    O.PMEntry{4,  [O.OpsPARAM{}],     Nil{}},          # 264
    O.PMEntry{5,  [O.OpsBUFFER{}],    Nil{}},          # 265
    O.PMEntry{6,  [O.OpsALLOC{}],     Nil{}},          # 267
    O.PMEntry{7,  [O.OpsBITCAST{}],   Nil{}},          # 269
    O.PMEntry{8,  [O.OpsMSTACK{}],    Nil{}},          # 271
    O.PMEntry{9,  [O.OpsMSELECT{}],   Nil{}},          # 272
    O.PMEntry{10, [O.OpsRANGE{}],     Nil{}},          # 274
    O.PMEntry{11, [O.OpsCALL{}],      Nil{}},          # 276
    O.PMEntry{12, [O.OpsAFTER{}],     Nil{}}]}         # 278

def kg_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match tag:
    case 0: kg_0(fx, self)
    case 1: kg_1(fx, self)
    case 2: kg_2(fx, self)
    case 3: kg_3(fx, self)
    case 4: kg_4(fx, self)
    case 5: kg_5(fx, self)
    case 6: kg_6(fx, self)
    case 7: kg_7(fx, self)
    case 8: kg_8(fx, self)
    case 9: kg_9(fx, self)
    case 10: kg_10(fx, self)
    case 11: kg_11(fx, self)
    case 12: kg_12(fx, self)
    case _: O.VSkip{}

def kg_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  kg_dispatch.go(tag, fx, self)

def kg_try.pick(ok: Bool, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match ok:
    case True{}: kg_dispatch(tag, fx, self)
    case _: O.VSkip{}

def kg_try(ts: O.PMEntrys, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> O.Verdict:
  kg_try.pick(Bool.and(sp_claimed(O.PMEntry.ops(e), sp_ar(fx), self),
                       sp_early(sp_ar(fx), self, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), fx, self)

def kg_scan(+ts: O.PMEntrys, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>, acc: O.Verdict) -> O.Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: kg_scan(ts, fx, self, t, O.pm_keep(acc, kg_try(ts, fx, self, e)))

def kg_rewrite(+ts: O.PMEntrys, fx: F.Folded, self: U32) -> O.Verdict:
  kg_scan(ts, fx, self, O.PMEntrys.es(ts), O.VSkip{})

def kernel_graph_rewrite(fx: F.Folded, self: U32) -> O.Verdict:
  kg_rewrite(kernel_graph_table(), fx, self)

def topo_budget.f.go(xs: List<&2, O.Node>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case nd <> t: topo_budget.f.go(t, U32.add(acc, U32.from_nat(List.length(&2, U32, O.Node.src(nd)))))

# ===========================================================================
# `type_verify` -- spec.py:36. It walks `ast.toposort()` and raises on the first
# node no rule answers `True`, and Bend has no `raise`, so this answers the node
# that failed instead: `None` is "the whole graph is legal" and `Some{i}` is the
# index the caller has to look at. `O.UOp.toposort` takes a fuel `Nat` and the
# budget below is the exact bound -- one entry per zero-src node plus one per edge.
#
# `SPEC > 1` and `test_pyrender` (spec.py:37) and the `DEBUG >= 3` print
# (spec.py:43) are not here. See the TODO block.
# ===========================================================================
def topo_budget.f(xs: List<&2, O.Node>, acc: U32) -> U32:
  topo_budget.f.go(xs, acc)

def topo_budget(+fx: F.Folded) -> Nat:
  U32.to_nat(U32.add(1, U32.add(O.Arena.next(sp_ar(fx)), topo_budget.f(O.Arena.nodes(sp_ar(fx)), 0))))

# ONE FOLD PER TABLE, and the duplication is the same one as the dispatch: the step
# has to call a table's `rewrite` and there is no way to name "a table's rewrite".
# `Some{j}` short-circuits, which is Python's `raise`.
def bad.pick(v: O.Verdict, i: U32) -> Maybe<&2, U32>:
  match v:
    case O.VTrue{}: None{}
    case _: Some{i}

def sh_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(sh_rewrite(ts, fx, i), i)

def sh_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: sh_verify.go(ts, fx, t, sh_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def sh_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  sh_verify.go(ts, fx, rest, None{})

def te_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(te_rewrite(ts, fx, i), i)

def te_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: te_verify.go(ts, fx, t, te_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def te_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  te_verify.go(ts, fx, rest, None{})

def pr_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(pr_rewrite(ts, fx, i), i)

def pr_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: pr_verify.go(ts, fx, t, pr_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def pr_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  pr_verify.go(ts, fx, rest, None{})

def hq_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(hq_rewrite(ts, fx, i), i)

def hq_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: hq_verify.go(ts, fx, t, hq_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def hq_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  hq_verify.go(ts, fx, rest, None{})

def fu_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(fu_rewrite(ts, fx, i), i)

def fu_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: fu_verify.go(ts, fx, t, fu_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def fu_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  fu_verify.go(ts, fx, rest, None{})

def kg_bad(fx: F.Folded, ts: O.PMEntrys, +i: U32) -> Maybe<&2, U32>:
  bad.pick(kg_rewrite(ts, fx, i), i)

def kg_verify.go(+ts: O.PMEntrys, +fx: F.Folded, rest: List<&2, U32>, bad: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match rest bad:
    case Nil{} _: bad
    case i <> t None{}: kg_verify.go(ts, fx, t, kg_bad(fx, ts, i))
    case _ <> t Some{j}: Some{j}

def kg_verify(ts: O.PMEntrys, fx: F.Folded, rest: List<&2, U32>) -> Maybe<&2, U32>:
  kg_verify.go(ts, fx, rest, None{})

# THE SIX ENTRY POINTS Python gets from passing a different `check_spec`.
def verify_shared(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  sh_verify(shared_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

def verify_tensor(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  te_verify(tensor_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

def verify_program(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  pr_verify(program_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

def verify_hcq(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  hq_verify(hcq_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

def verify_full(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  fu_verify(full_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

def verify_kernel_graph(+fx: F.Folded, sink: U32) -> Maybe<&2, U32>:
  kg_verify(kernel_graph_table(), fx, O.UOp.toposort(topo_budget(fx), sp_ar(fx), sink))

# `ParamArg` for a GLOBAL BUFFER of `int32` with a size and a device. `ops.bend`
# lays the thirteen fields out in declaration order and this is that order.
def buf_param() -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
             False{}, None{}, Some{0}, False{}, None{}}

# ===========================================================================
# THE FIXTURES. Two hand-built arenas, and the gate below is a set of claims
# ABOUT them that Python specifies. Every row is one the gate could get WRONG: a
# table count, a tag's op set, a verdict Python fixes, or the first-wins ordering
# between two rules that both claim one node. A row that merely restates the code
# is not in this file.
#
# THE LANDMARKS ARE RESOLVED, NOT COUNTED, and that is not tidiness. The first
# version of this gate hard-coded `22` and `23` for the two GETADDRs and
# `hcq_plain` printed 1 -- for the WRONG REASON: node 22 is the AFTER, so the hcq
# table fell through to `spec_shared`'s AFTER rule and answered `True` without
# `hq_0` ever running. A row that points at the wrong node is a row that cannot
# fail, and it is the exact trap of "build the fixture so two rules both claim the
# same node". `Land` is the fix: the builder hands back the indices it made.
# ===========================================================================
type Land is Data:
  Land{fx: F.Folded, k: U32, noop: U32, sink: U32, fsub: U32, isub: U32, stack: U32,
       shl_f: U32, shl_i: U32, backedge: U32, prog: U32, ga_plain: U32, ga_after: U32}

def land.put(fx: F.Folded, k: U32, noop: U32, sink: U32, fsub: U32, isub: U32, stack: U32,
             shl_f: U32, shl_i: U32, backedge: U32, prog: U32, ga_plain: U32, ga_after: U32) -> Land:
  Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}

# the node list, in binding order, and the comment above says what each one is.
#  1 CONST(3)            a CONST's dtype FOLLOWS its value, which is why `sh_2`'s
#  2 NOOP                type-correspondence arm is unreachable (see `sh_2`)
#  3 SINK(void, [2])
#  4 CONST(7.0)   CFloat
#  5 CONST(8.0)   CFloat
#  6 FSUB = SUB(4, 5)     float32
#  7 CONST(11)    CInt
#  8 CAST(CONST(3), int32) int32 -- the only way to get a non-weak int in this port
#  9 ISUB = SUB(8, 7)     int32
# 10 STACK(void, [6, 9])  float32  -- one float and one int, so `sh_4` REJECTS it
# 11 SHL(FSUB, CONST(1))  the float shift: `sh_7` says `False`, `sh_8` says `True`
# 12 SHL(ISUB, CONST(1))  the int shift, where `sh_7` SKIPS
# 13 RANGE(void, [2], AXIS_WEAK)     built by `UOp.loop`: a void RANGE, because
#                                     `_shape`'s RANGE arm takes `src[0].dtype`
# 14 COND = CONST(True)   bool, shape (), not Invalid
# 15 BACKEDGE(void, [1, 13, 14])     the one rule here with a non-empty `rej`
# 16 LINEAR(void, [2])
# 17 SOURCE(void, [])
# 18 BINARY(uint8, [])    ABlob
# 19 PROGRAM(void, [3, 16, 17, 18])  a FOUR-src PROGRAM: its `rej` is all four
# 20 SPECIAL              the BUFFER's range stand-in
# 21 BUFFER(int32, [20])  on device tag 0, GLOBAL, with a size and a buffer
# 22 AFTER(21)
# 23 GETADDR(uint64, [21])  ADev{D1{0}}    the `or_after` BARE alternative
# 24 GETADDR(uint64, [22])  ADev{D1{0}}    the `or_after` WRAPPED alternative
def main_arena() -> Land:
  +n1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +n2 = O.UOp.new(O.Found.ar(n1), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsSINK{}, [O.Found.i(n2)], O.ANone{}, O.TNone{})
  +n4 = O.UOp.const(O.Found.ar(n3), O.CFloat{7.0})
  +n5 = O.UOp.const(O.Found.ar(n4), O.CFloat{8.0})
  +n6 = O.UOp.alu(O.Found.ar(n5), O.OpsSUB{}, [O.Found.i(n4), O.Found.i(n5)])
  +n7 = O.UOp.const(O.Found.ar(n6), O.CInt{H.i64_of_i32(11)})
  +n8 = O.UOp.new(O.Found.ar(n7), O.OpsCAST{}, [O.Found.i(n1)], O.ADt{S.int32()}, O.TNone{})
  +n9 = O.UOp.alu(O.Found.ar(n8), O.OpsSUB{}, [O.Found.i(n8), O.Found.i(n7)])
  +n10 = O.UOp.new(O.Found.ar(n9), O.OpsSTACK{}, [O.Found.i(n6), O.Found.i(n9)], O.ANone{}, O.TNone{})
  +n11 = O.UOp.alu(O.Found.ar(n10), O.OpsSHL{}, [O.Found.i(n6), O.Found.i(n1)])
  +n12 = O.UOp.alu(O.Found.ar(n11), O.OpsSHL{}, [O.Found.i(n9), O.Found.i(n1)])
  +n13 = O.UOp.loop(O.Found.ar(n12), 0)
  +n14 = O.UOp.const(O.Found.ar(n13), O.CBool{True{}})
  +n15 = O.UOp.backedge(O.Found.ar(n14), O.Found.i(n1), O.Found.i(n13), O.Found.i(n14))
  +n16 = O.UOp.new(O.Found.ar(n15), O.OpsLINEAR{}, [O.Found.i(n2)], O.ANone{}, O.TNone{})
  +n17 = O.UOp.new(O.Found.ar(n16), O.OpsSOURCE{}, Nil{}, O.ANone{}, O.TNone{})
  +n18 = O.UOp.new(O.Found.ar(n17), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  +n19 = O.UOp.new(O.Found.ar(n18), O.OpsPROGRAM{}, [O.Found.i(n3), O.Found.i(n16), O.Found.i(n17), O.Found.i(n18)], O.AProgram{O.ProgramInfo.of()}, O.TNone{})
  +n20 = O.UOp.special(O.Found.ar(n19), O.Found.i(n1), "0")
  +n21 = O.UOp.new(O.Found.ar(n20), O.OpsBUFFER{}, [O.Found.i(n20)], O.AParam{buf_param()}, O.TNone{})
  +n22 = O.UOp.new(O.Found.ar(n21), O.OpsAFTER{}, [O.Found.i(n21)], O.ANone{}, O.TNone{})
  +n23 = O.UOp.new(O.Found.ar(n22), O.OpsGETADDR{}, [O.Found.i(n21)], O.ADev{S.D1{0}}, O.TNone{})
  +n24 = O.UOp.new(O.Found.ar(n23), O.OpsGETADDR{}, [O.Found.i(n22)], O.ADev{S.D1{0}}, O.TNone{})
  land.put(F.folded(O.Found.ar(n24)), O.Found.i(n1), O.Found.i(n2), O.Found.i(n3), O.Found.i(n6),
    O.Found.i(n9), O.Found.i(n10), O.Found.i(n11), O.Found.i(n12), O.Found.i(n15),
    O.Found.i(n19), O.Found.i(n23), O.Found.i(n24))

def Land.fx.go(x: Land) -> F.Folded:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: fx

def Land.fx(x: Land) -> F.Folded:
  Land.fx.go(x)

def Land.k.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: k

def Land.k(x: Land) -> U32:
  Land.k.go(x)

def Land.noop.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: noop

def Land.noop(x: Land) -> U32:
  Land.noop.go(x)

def Land.sink.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: sink

def Land.sink(x: Land) -> U32:
  Land.sink.go(x)

def Land.stack.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: stack

def Land.stack(x: Land) -> U32:
  Land.stack.go(x)

def Land.shl_f.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: shl_f

def Land.shl_f(x: Land) -> U32:
  Land.shl_f.go(x)

def Land.shl_i.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: shl_i

def Land.shl_i(x: Land) -> U32:
  Land.shl_i.go(x)

def Land.backedge.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: backedge

def Land.backedge(x: Land) -> U32:
  Land.backedge.go(x)

def Land.prog.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: prog

def Land.prog(x: Land) -> U32:
  Land.prog.go(x)

def Land.ga_plain.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: ga_plain

def Land.ga_plain(x: Land) -> U32:
  Land.ga_plain.go(x)

def Land.ga_after.go(x: Land) -> U32:
  match x:
    case Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}: ga_after

def Land.ga_after(x: Land) -> U32:
  Land.ga_after.go(x)

type Mdev is Data:
  Mdev{fx: F.Folded, buf: U32}

def Mdev.fx.go(x: Mdev) -> F.Folded:
  match x:
    case Mdev{fx, buf}: fx

def Mdev.fx(x: Mdev) -> F.Folded:
  Mdev.fx.go(x)

def Mdev.buf.go(x: Mdev) -> U32:
  match x:
    case Mdev{fx, buf}: buf

def Mdev.buf(x: Mdev) -> U32:
  Mdev.buf.go(x)

def mdev_param() -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.Dn{[0, 1]}},
             False{}, None{}, Some{0}, False{}, None{}}

# THE TWO MULTI-DEVICE ARENAS, and they are separate on purpose: the rows they feed
# differ by ONE THING -- the RANGE's axis type -- and a fixture that differed by
# anything else would not be testing `valid_device_range`.  0 bottom, 1 CONST(2),
# 2 RANGE over it, 3 BUFFER(int32, [2]) on two devices with a size and a buffer.
def main_mdev(ax: O.AxisType) -> Mdev:
  +d1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})
  +d2 = O.UOp.range_end(O.Found.ar(d1), O.Found.i(d1), [0], ax)
  +d3 = O.UOp.new(O.Found.ar(d2), O.OpsBUFFER{}, [O.Found.i(d2)], O.AParam{mdev_param()}, O.TNone{})
  Mdev{F.folded(O.Found.ar(d3)), O.Found.i(d3)}

# ===========================================================================
# THE ROWS. `1` is `VTrue`, `0` is `VFalse`, `9` is `VSkip` -- a real answer and
# not a failure. Every value here is DERIVABLE from `spec.py`, and the table at
# the bottom of this file says which line of `spec.py` fixes each one.
# ===========================================================================
def tbl_len(ts: O.PMEntrys) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(ts)))

# the six table sizes, counted from `spec.py` and NOT from this file: shared 33,
# tensor 22+33, program 9+33, hcq 2+33, full 4+22+33+9+2, kernel_graph 13. The
# tensor figure was 23+33 and was WRONG until 2026-10-03 -- see THE TWENTY-THIRD
# TENSOR RULE above for the deletion that took it to 22.
def t_sh_len() -> U32: tbl_len(shared_table())

def t_te_len() -> U32: tbl_len(tensor_table())

def t_pr_len() -> U32: tbl_len(program_table())

def t_hq_len() -> U32: tbl_len(hcq_table())

def t_fu_len() -> U32: tbl_len(full_table())

def t_kg_len() -> U32: tbl_len(kernel_graph_table())

def entry_at.of(hit: Maybe<&2, O.PMEntry>) -> O.PMEntry:
  match hit:
    case Some{e}: e
    case _: O.PMEntry{999, Nil{}, Nil{}}

def entry_at(ts: O.PMEntrys, n: U32) -> O.PMEntry:
  entry_at.of(List.get(&2, O.PMEntry, O.PMEntrys.es(ts), U32.to_nat(n)))

def if_b.go(b: Bool) -> U32:
  match b:
    case True{}: 1
    case _: 0

def if_b(b: Bool) -> U32:
  if_b.go(b)

def rej_is(got: List<&2, O.Op>, want: List<&2, O.Op>) -> Bool:
  O.eq_op_list(got, want)

def rej_len(e: O.PMEntry) -> U32:
  U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(e)))

# `spec.py:57` is `UPat(Ops.CONST, ...)` and its `src=()` gives an EMPTY
# `early_reject`; a rule transcribed onto the wrong line fails this.
def t_tag_const.of(claimed: Bool, rej: List<&2, O.Op>) -> U32:
  if_b(Bool.and(claimed, U32.is_eq(U32.from_nat(List.length(&2, O.Op, rej)), 0)))

def t_tag_const() -> U32:
  t_tag_const.of(O.op_in(O.PMEntry.ops(entry_at(shared_table(), 2)), O.OpsCONST{}),
                 O.PMEntry.rej(entry_at(shared_table(), 2)))

# the reject sets that NAME A SOURCE OP, and the one that names ALL of a four-src
# PROGRAM's sources. A misspelling makes the rule skip a node it should accept,
# and no other row would notice.
def t_tag_rej.of(a: Bool, b: U32) -> U32:
  if_b(Bool.and(a, U32.is_eq(b, 4)))

def t_tag_rej() -> U32:
  t_tag_rej.of(rej_is(O.PMEntry.rej(entry_at(shared_table(), 15)), [O.OpsRANGE{}]),
               rej_len(entry_at(tensor_own(), 21)))

# spec.py:51 -- a SINK is `True` in `spec_shared`, with no arity test.
def t_sink_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.sink(main_arena())))

# spec.py:54 -- a NOOP is `True` in every table EXCEPT `spec_kernel_graph`, which is
# not composed with `spec_shared`. Two rows for one node, and the second is the one
# that catches a `+ spec_shared` appearing where spec.py has no `+`.
def t_noop_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.noop(main_arena())))

def t_noop_kg() -> U32: show_v(kernel_graph_rewrite(Land.fx(main_arena()), Land.noop(main_arena())))

# spec.py:57 -- `sh_2`. See `sh_2` for why its second disjunct cannot be made to
# fail here, so this row is about the op, the arity and the `or`.
def t_const_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.k(main_arena())))

# spec.py:62 -- a STACK whose srcs are one float and one int is REJECTED, because
# the STACK's dtype is `least_upper(float32, int32) = float32` and int32 is neither
# that nor weak.
def t_stack_dt() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.stack(main_arena())))

# spec.py:70 vs :71. BOTH claim a SHL and they DISAGREE: `sh_7` says `False` for a
# float shift and `sh_8` says `True`. First-wins is the row; last-wins prints 1
# here, and accepting a float shift is exactly the bug this catches.
def t_shl_wins() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.shl_f(main_arena())))

# the control: the int shift, where `sh_7` SKIPS because no src is a float, so
# `sh_8` is the rule that answers. If this row ever equals `t_shl_wins` then the two
# rules are not both being tried.
def t_shl_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.shl_i(main_arena())))

# spec.py:110 -- `sh_22`, and the row that COULD NOT BE WRITTEN while `sh_22` was the
# pin's `isinstance(x.arg, str)`. THE FIXTURE IS A LOCAL ARENA rather than two more
# `main_arena` fields: `Land` is a thirteen-field record read POSITIONALLY by thirteen
# `case Land{...}` accessors, so two fixtures there are twenty-six positional edits --
# the same class of edit this file's own `te_dispatch.go` note is about.
def t_cf_arg_ok() -> U32:
  +n = O.UOp.custom_function(O.Arena.empty(), "sel_registerName", Nil{}, S.void())
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# THE NEGATIVE, and it is not a hypothetical node: upstream's constructor takes
# `arg: Any`, so `UOp(Ops.CUSTOM_FUNCTION, arg="sel_registerName")` is constructible,
# and CPython measured `spec_shared.rewrite` on it as False.
# `dtype_from_uop` would RAISE on that node -- `'str' object has no attribute 'dtype'`,
# measured -- so this row can never become a dtype row; it is the arg-TYPE row, and
# `fold.bend`'s unconditional `(void, None)` for CUSTOM_FUNCTION is what lets the port
# answer it where CPython cannot.
#
# THE TWO ROWS MOVE IN OPPOSITE DIRECTIONS and that is the whole reason there are two.
# Under the pin's body `cf_arg_ok` was 0 (a `CustomFunction` is not a `str`) and
# `cf_arg_str` was 1; at HEAD they are 1 and 0. ONE row could not tell "the arm was
# swapped for the right one" from "the arm was swapped for one that accepts anything".
def t_cf_arg_str() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsCUSTOM_FUNCTION{}, Nil{}, O.AStr{"sel_registerName"}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# `sh_22`'s OP GATE, and the row for it, which the pair above cannot be: both fixtures
# ARE CUSTOM_FUNCTIONs, so deleting `sp_op(fx, self, O.OpsCUSTOM_FUNCTION{})` from
# `sh_22` leaves both answers untouched. This node is the one that separates them --
# an AFTER (no src) carrying a `CustomFunction` arg, which upstream cannot build and
# which is therefore purely adversarial. `sh_20` needs `len(src) >= 1`, so no rule
# claims it and the honest answer is `VSkip` = 9.
# CPython AGREES, and that is what makes this a row and not an artifact of the port:
# `spec_shared.rewrite(UOp(Ops.AFTER, src=(), arg=CustomFunction("f")))` is None.
# MEASURED, not assumed: a NOOP with the same arg is CLAIMED (1) by an earlier rule,
# which is why this row has a control -- same arg, different op, opposite answer.
def t_cf_arg_after() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsAFTER{}, Nil{}, O.ACustom{O.CustomFunction.of("f")}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

def t_cf_arg_noop() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ACustom{O.CustomFunction.of("f")}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# spec.py:88 -- the BACKEDGE, and the only rule here whose `rej` is non-empty AND
# whose verdict depends on it being spelled right.
def t_backedge_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.backedge(main_arena())))

# spec.py:198 -- a FOUR-src PROGRAM. `te_21`'s `rej` is all four of its src ops, so
# `ler` has to fold over ALL of `src`: a two-element `ler` can never contain four
# ops and this rule would never fire.
def t_prog4_ok() -> U32: show_v(tensor_rewrite(Land.fx(main_arena()), Land.prog(main_arena())))

# spec.py:231 -- the `or_after` DISJUNCTION, both ways. A conjunction would accept
# only `GETADDR(AFTER(BUFFER))` and reject the bare `GETADDR(BUFFER)` that spec.py's
# `is_any` matches; the first row is the bare one.
def t_hcq_plain() -> U32: show_v(hcq_rewrite(Land.fx(main_arena()), Land.ga_plain(main_arena())))

def t_hcq_after() -> U32: show_v(hcq_rewrite(Land.fx(main_arena()), Land.ga_after(main_arena())))

# spec.py:33 -- `int(rng.vmax)+1 == len(device)`, with `device` a two-name tuple and
# the range's end a CONST(2). `_min_max` reduces a RANGE's `vmax` to
# `(src[0]-1).vmax`, so this is `2 == 2`.
def t_multidev_ok() -> U32: show_v(tensor_rewrite(Mdev.fx(main_mdev(O.AXIS_DEVICE{})), Mdev.buf(main_mdev(O.AXIS_DEVICE{}))))

# the same BUFFER with the RANGE on the GLOBAL axis: `rng.axis_type is DEVICE`
# fails, so `te_1` answers `False` and the fold STOPS.
def t_multidev_bad() -> U32: show_v(tensor_rewrite(Mdev.fx(main_mdev(O.AXIS_GLOBAL{})), Mdev.buf(main_mdev(O.AXIS_GLOBAL{}))))

# ===========================================================================
# NOT PORTED, one line each, and the WALL each one is behind. The Python line
# numbers are `spec.py`'s, so this list diffs against `spec.py` line for line and
# `grep "TODO(p3)" tinybendygrad/uop/spec.bend` is the work queue.
#
# THE FOUR THAT ARE GENUINELY UNAVAILABLE, and they are all P3 or later.
# ===========================================================================
# TODO(p3) spec.py:286 def pyrender_globals -- imports `tinygrad.codegen.opt`,
#   `tinygrad.schedule.rangeify` and `tinygrad.renderer` into a dict of names and
#   is `@functools.cache`d. WALL: none of the three modules is ported, and the
#   thing they exist to feed does not exist here at all -- see spec.py:292. P3/VIZ.
# TODO(p3) spec.py:292 def eval_pyrender -- `exec` of GENERATED SOURCE. WALL: the
#   point of `upat.py` is to EMIT Python, and this port emits defs instead, so the
#   pyrender round-trip has no representation: there is no source to exec and no
#   AST to compare it against. P3/VIZ.
# TODO(p3) spec.py:296 def test_pyrender -- renders a UOp to source and compares
#   the re-evaluated AST BY IDENTITY, recursing over parents on a mismatch. WALL:
#   the whole feature is a debug view and it rests on the two above. P3/VIZ.
# TODO(p3) spec.py:37  type_verify's `SPEC > 1` arm -- calls `test_pyrender(lst[-1])`
#   and `SPEC` is a `ContextVar`, i.e. a process-wide mutable that Bend has no
#   home for. WALL: the call is the one above; the flag is the configuration
#   module `helpers.bend` lists as P6. P3/VIZ.
# TODO(p3) spec.py:26  validate_index_with_z3 -- `from tinygrad.uop.validate import
#   validate_index_with_z3`, and `tinygrad/uop/validate.py` is not ported. WALL: a
#   solver over a z3 encoding of the index expression; Bend has no z3. P3.
# TODO(p3) spec.py:7   is_disk_device -- `from tinygrad.device import is_disk_device`
#   and `tinygrad/device.py` is not ported: there is no device, so "is this device
#   a DISK" has nothing to ask. The only reader is `te_9` (spec.py:177) and the
#   wall is stated there. P6.
# ===========================================================================
#
# THE REST ARE NOT UNAVAILABLE, THEY ARE BEHIND A PROPERTY FOLD, and each one names
# the fold that owns it so the phase is unambiguous.
# ===========================================================================
# TODO(p3) spec.py:11  def validate_index -- the first two returns
#   (`len(uidx.src) != 2` and `idx.is_invalid`) are PORTED and both are `True`.
#   Everything past them needs `CHECK_OOB` (a `ContextVar`), `buf.max_numel()` (a
#   product over `shape` with `ssimplify` in it), `idx.vmin`/`idx.vmax` (`_min_max`,
#   ops.py:1104, the largest piece `fold.bend` defers) and z3. The answer is `None`,
#   so an out-of-bounds INDEX is rejected as "no rule answered" rather than as out
#   of bounds. WALL: `_min_max`. P3, with `SPEC` for the flag.
# TODO(p3) spec.py:30  def valid_device_range -- PORTED, INCLUDING the `vmax + 1`
#   half, because `_min_max`'s RANGE arm reduces it to the end CONST. What it
#   cannot state is a NON-constant range end: there is no number to compare and the
#   answer is `None`. WALL: the symbolic half of `_min_max`. P3.
# TODO(p3) spec.py:35  def type_verify -- PORTED as six folds that return the
#   OFFENDING NODE, because Bend has no `raise` and a validator that cannot report
#   is a validator nobody can use. The two lines not here are the `SPEC > 1` arm
#   and the `DEBUG >= 3` print. WALL: P3/VIZ for both.
# TODO(p3) spec.py:133 lambda x: `b := x.storage_base` -- a `while` over BITCAST,
#   AFTER and UNSHARD on top of `base`, so it is not a fold this port has. `sh_31`
#   IS ported for every node where `b is x` -- the common case, a STORE straight
#   into a BUFFER -- and answers `None` for a view of a view. A STORE into a
#   RESHAPE of a BUFFER is therefore unverified by `sh_31`; it is not REJECTED,
#   because `type_verify` fails only when no rule answers. WALL: `storage_base`,
#   which is `base` plus a seventh `Derived` field. P3.
# TODO(p3) spec.py:57  lambda x: `type(x.val) is type(x.dtype.const(x.val))` --
#   PORTED as the class correspondence `DType.const` (tinygrad/dtype.py:79) actually
#   tests, and it is UNREACHABLE on a well-formed arena, because a CONST's dtype is
#   DERIVED from its value. `const_ok` in the gate says so. WALL: if
#   `dtype.bend` becomes importable, `truncate` (tinygrad/dtype.py:295) is the half that is
#   a C effect. P3.
# TODO(p3) spec.py:148 lambda buf: `isinstance(buf.dtype, DType)` -- vacuous in this
#   port, because `S.Dt` IS the DType. NO ACTION; recorded so the conjunct is not
#   mistaken for a missing check.
# ===========================================================================
#
# WHAT NEXT, in the order the walls fall.
#   1. `_min_max` (ops.py:1104) unblocks `validate_index`'s body, `valid_device_range`
#      for a symbolic end, and `shard_shape`. It is the largest single unlock in
#      the fold and three of the six TODOs above are behind it.
#   2. `storage_base` (ops.py:801) unblocks `sh_31`'s deferred arm.
#   3. `Device.tag` (P6) makes `is_device`'s string-ness CHECKABLE rather than
#      INHERITED, and `is_disk_device` answers with it.
#   4. `SPEC` / `test_pyrender` (P3/VIZ) close `type_verify` and give the pyrender
#      round-trip a reason to exist at all.
# ===========================================================================
# THE GATE, and what each row is FOR. `1` is `VTrue`, `0` is `VFalse`, `9` is
# `VSkip` -- and a `VSkip` is a real answer, not a failure: it is what a rule says
# when the pattern does not apply, and `type_verify` rejects it exactly as it
# rejects a `False`.
#
#   sh_len=33    spec.py:50-138 is 33 entries. A count, so a MISSING rule shows.
#   te_len=55    22 own (spec.py:143-199) + 33 shared. It PRINTED 56 and its
#                expectation was 56, so the row was GREEN over the wrong answer --
#                the row asserts the table's own length and the table was the thing in
#                question. Both moved 2026-10-03; see THE TWENTY-THIRD TENSOR RULE.
#   pr_len=42    9 own (spec.py:202-225) + 33 shared.
#   hq_len=35    2 own (spec.py:227-232) + 33 shared.
#   fu_len=70    4 + 22 + 33 + 9 + 2 -- NOT 136, and `full_table`'s header says why
#                the other 66 are UNREACHABLE rather than merely redundant.
#   kg_len=13    spec.py:251-277 is 13 entries and NOTHING is appended.
#   tag_const=1  spec.py:57 is `UPat(Ops.CONST, ...)` with an EMPTY reject set.
#   tag_rej=1    spec.py:89's reject set is `[RANGE]` and spec.py:198's is all four
#                of a PROGRAM's srcs. Both are the only places a MISSPELLED reject
#                set shows up, and nothing else would notice.
#   sink_ok=1    spec.py:51 -- a void SINK, with no arity test at all.
#   noop_ok=1    spec.py:54 -- a NOOP is legal in `spec_shared`.
#   noop_kg=9    ... and a `VSkip` in `spec_kernel_graph`, the ONLY table spec.py
#                does not compose with `spec_shared`. Two rows, one node, and the
#                second is the one that catches a `+ spec_shared` appearing where
#                spec.py has none.
#   const_ok=1   spec.py:57. See the TODO on spec.py:57: this row cannot be made to
#                fail on a dtype mismatch, because a CONST's dtype follows its
#                value. It is about the op, the arity and the `or`.
#   stack_dt=0   spec.py:62 -- one float src and one int src is REJECTED, because
#                the STACK's dtype is `least_upper(float32, int32) = float32`.
#   shl_wins=0   spec.py:70 vs :71. Both claim a SHL and they DISAGREE, so this row
#                is FIRST-WINS: `sh_7` says `False` for a float shift and `sh_8`
#                says `True`, and the fold must keep the earlier one.
#   shl_ok=1     the control for the row above: the int shift, where `sh_7` SKIPS
#                and `sh_8` answers. Equal numbers here mean only one rule ran.
#   backedge_ok=1  spec.py:89 -- the rule whose reject set is non-empty AND whose
#                verdict depends on that set being spelled right.
#   prog4_ok=1   spec.py:198 -- a FOUR-src PROGRAM. Its reject set is all four src
#                ops, so `ler` MUST fold over every src: a two-src `ler` can never
#                contain four ops and the rule would silently never fire.
#   hcq_plain=1  spec.py:228, the BARE `or_after` alternative: `GETADDR(BUFFER)`.
#   hcq_after=1  spec.py:228, the WRAPPED alternative: `GETADDR(AFTER(BUFFER))`. A
#                conjunction instead of a disjunction would drop the first and keep
#                the second, which is a real mistake to make.
#   multidev_ok=1  spec.py:33 -- `int(rng.vmax)+1 == len(device)` with a two-name
#                tuple and a CONST(2) end. `_min_max` reduces a RANGE's `vmax` to
#                `(src[0]-1).vmax`, so this is `2 == 2`.
#   multidev_bad=0 the same BUFFER with the RANGE on the GLOBAL axis, so
#                `rng.axis_type is DEVICE` fails and `te_1` STOPS the fold.
# ===========================================================================
#
# MUTATIONS, all re-run 2026-09-30 against this file. A row that only one mutation
# moves is a LOCALISED row; the rest are load-bearing together, and this table is
# not one-row-per-bug and should not read as if it were.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `sp_early.go`'s subset test `and` -> `or` | NONE | 0 |
# | `sh_scan`'s `pm_keep(acc, v)` -> `pm_keep(v, acc)` (last-wins) | `shl_wins` | 1 |
# | `te_scan`'s, the same fold over the TENSOR table | NONE | 0 |
# | `sp_ler` reads only `src[0]` and `src[1]` (ops.bend's `pm_ler`) | `prog4_ok` | 1 |
# | `alt_of`'s `or` -> `and` (`is_any` as a conjunction) | `hcq_plain`, `hcq_after` | 2 |
# | `sp_vd`'s `Some{False}` -> `VSkip` | `shl_wins`, `multidev_bad` | 2 |
# | `sp_vb`'s `False` -> `VSkip` | `stack_dt` | 1 |
# | `sp_tri.of`'s `Some{v}` -> `None{}` | `shl_wins` | 1 |
# | `sp_tri_v.go`'s taken `v` -> `None{}` | `multidev_ok`, `multidev_bad` | 2 |
#
# ADDED 2026-10-03, for the twenty-third-rule deletion. 12 mutations, 5 localised,
# 7 blind spots -- and every blind spot is a FIXTURE-COVERAGE fact, not a gate defect,
# which is the good kind to have and the kind that must still be written down.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | re-insert the deleted `CUSTOM_FUNCTION` rule as `tensor_own` tag 4 | `te_len`, `fu_len`, `tag_rej` | 3 |
# | `t_tag_rej` reads `entry_at(tensor_own(), 20)` instead of 21 | `tag_rej` | 1 |
# | `sh_scan` last-wins | `shl_wins` | 1 |
# | `alt_of` conjunction | `hcq_plain`, `hcq_after` | 2 |
# | `sp_vd`'s `Some{False}` -> `VSkip` | `shl_wins`, `multidev_bad` | 2 |
# | `full_table`'s hcq bump 68 -> 69 | NONE | 0 |
# | `fu_dispatch.of`'s shared offset 26 -> 27 | NONE | 0 |
# | `te_dispatch.go`'s shared handoff 22 -> 21 | NONE | 0 |
# | `tensor_table`'s shared bump 22 -> 23 | NONE | 0 |
# | `te_dispatch.go` ladder: `case 5: te_4` | NONE | 0 |
# | `te_dispatch.go` ladder: `case 4: te_5` | NONE | 0 |
# | `te_scan` last-wins | NONE | 0 |
#
# THE FIRST ROW IS THE ONE THAT ANSWERS "WAS THE DELETION WORTH MAKING": three rows, not
# two. `tag_rej` joins `te_len` and `fu_len` because re-inserting the rule pushes the
# four-src PROGRAM rule from index 21 back to 22, and `t_tag_rej` reads index 21 -- so the
# deletion is witnessed by a row that reads a rule's CONTENT, not only by two that count
# entries. Before the deletion that row read the three-src rule's reject set, which is
# where it would have gone wrong.
#
# THE FOUR TAG-SPACE BLIND SPOTS SHARE ONE REASON AND IT IS WORTH NAMING. Nothing in the
# gate drives `full_table()` or the tensor-to-shared HANDOFF on any fixture, so every
# offset in `full_table.go` and `fu_dispatch.of` and `te_dispatch.go`'s `case _` arm is
# ungated: `fu_len` counts entries and `bump` does not change how many there are. Two of
# those offsets were WRONG for part of this session -- `fu_dispatch.of` said 27 / 60 / 69
# while `full_table.go` said 26 / 59 / 68 -- and no row noticed, because no row could.
# That is why the offsets moved to `spec-offsets.py`, which checks all fourteen against
# the table sizes and checks every ladder reads `case N: _N`: a mutation the gate cannot
# see is exactly what a checker outside the gate is for. A fixture with both a tensor and
# a program op would close two of the four; the two handoff rows need a node that no
# tensor rule claims, which is a different fixture again.
#
# THE THREE `te_dispatch.go` LADDER BLIND SPOTS ARE PURE COVERAGE. `Land` has no SPECIAL
# node and no RESHAPE/EXPAND node, so `te_4` and `te_5` have no row that can reach them,
# and shifting either arm is invisible. `te_scan`'s first-wins is blind for the same kind
# of reason: no tensor fixture has two rules claiming one node with DISAGREEING answers,
# which is precisely the property `shl_wins` was built to give the shared table. Adding
# the missing nodes is fixture work, and saying so is more useful than a row that cannot
# fail.
#
# THE FIRST ROW IS THE INTERESTING ONE, and it is a NEGATIVE result worth keeping.
# Flipping the subset test's `and` for its `or` moves NOTHING, and that is the
# MEASURED PROOF of a claim this file's header makes: every non-empty
# `early_reject` set in `spec.py` is ALREADY IMPLIED by its rule's own src-op test,
# so `early_reject` never decides a verdict in these six tables. It is not dead
# weight in Python either -- it is a fast pre-filter -- but in a port where a rule
# is a def and the pattern's own tests run anyway, it decides nothing. What it
# DOES still catch is a MISSPELLED set: a wrong op turns a necessary condition into
# a false one and the rule then skips a node it should accept. `backedge_ok` and
# `prog4_ok` are the rows for that, and neither mutation above touches them because
# neither changes WHICH set is WRITTEN.
#
# THE SECOND ROW IS THE CORRECTION, and it is the same shape as the `keep` mutation
# in `compiled-matcher-shape.bend`: one row, and it is the row that exists for it.
# `shl_wins` is a first-wins discriminator because the fixture was built so that
# TWO rules claim one node and they DISAGREE -- `sh_7`'s `False` against `sh_8`'s
# `True`. A fixture where both agree could not tell first-wins from a conjunction,
# and that is the trap of "build the fixture so two rules both claim the same node".
#
# THE THIRD ROW IS A REPORT ABOUT `ops.bend`, and it is the reason this file needed
# its own `sp_ler`. `ops.bend`'s `pm_ler` reads `src[0]` and `src[1]` and appends,
# so it can only ever see two ops; `spec.py:201`'s reject set is FOUR ops long, so
# under `ops.bend`'s `pm_ler` `te_21` can NEVER fire and a four-src PROGRAM is
# unverified. `spec.py:31` and `:32` are safe by accident -- `len(src) == 0` and
# `len(src) == 1`. `sp_ler` here folds over EVERY src, which is what Python's
# `{u.op for u in uop.src}` does. REPORTED, NOT FIXED: `ops.bend` is not this file's.
# ===========================================================================
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sh_len", t_sh_len())
    b : Unit <- row("te_len", t_te_len())
    c : Unit <- row("pr_len", t_pr_len())
    d : Unit <- row("hq_len", t_hq_len())
    e : Unit <- row("fu_len", t_fu_len())
    f : Unit <- row("kg_len", t_kg_len())
    g : Unit <- row("tag_const", t_tag_const())
    h : Unit <- row("tag_rej", t_tag_rej())
    i : Unit <- row("sink_ok", t_sink_ok())
    j : Unit <- row("noop_ok", t_noop_ok())
    k : Unit <- row("noop_kg", t_noop_kg())
    l : Unit <- row("const_ok", t_const_ok())
    m : Unit <- row("stack_dt", t_stack_dt())
    n : Unit <- row("shl_wins", t_shl_wins())
    o : Unit <- row("shl_ok", t_shl_ok())
    p : Unit <- row("cf_arg_ok", t_cf_arg_ok())
    q : Unit <- row("cf_arg_str", t_cf_arg_str())
    r : Unit <- row("cf_arg_after", t_cf_arg_after())
    r2 : Unit <- row("cf_arg_noop", t_cf_arg_noop())
    r3 : Unit <- row("backedge_ok", t_backedge_ok())
    s : Unit <- row("prog4_ok", t_prog4_ok())
    t : Unit <- row("hcq_plain", t_hcq_plain())
    u : Unit <- row("hcq_after", t_hcq_after())
    row("multidev_ok", t_multidev_ok())
    row("multidev_bad", t_multidev_bad())
