# spec.bend -- tinygrad/uop/spec.py. The graph VALIDATOR: six rule tables, three
# WHAT THIS FILE IS. `spec.py` is not a rewriter. It answers, for ONE node, "is
# THE ANSWER IS THREE-VALUED. Python's rule bodies return `True`, `False`, or
#     ret = check_spec.rewrite(uop)          # spec.py:42
# so `VTrue` is the only passing answer and BOTH `VFalse` and `VSkip` fail. They are
# WHY SIX DISPATCHES. `spec.py` has six tables, each its own `PatternMatcher`, and
# WHAT IS SHARED AND WHAT IS NOT. Shared: the property readers (`sp_*`), the
# the tag spaces are per table, starting at 0, and each rule carries its `spec.py`

#    `ops.py:1701` is `if not early_reject.issubset(ler): continue`, so the rule
#    the pattern's FIRST src (`ops.py:1483`), and for a pattern whose first src is
# 2. a name bound twice must emit an identity check (`upat.py:100-105` builds it
#    as a literal `"{0} is {1}"`, and `mixin/gradient.py:101` and
#    `schedule/__init__.py:182` both depend on it). The only name bound twice in

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F


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

# recursion Python breaks with `recursive_property`'s memo (ops.py:218).

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

# `x.is_invalid` -- ops.py:267, `self.op is Ops.CONST and self.val is Invalid`.
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

# `x.base.is_invalid` -- `matches_dtype` (spec.py:48) and four rule bodies. A node
def sp_base_invalid(+fx: F.Folded, self: U32) -> Bool:
  sp_base_invalid.of(sp_base(fx, self), sp_ar(fx))

def sp_md.go(same: Bool, base_bad: Bool) -> Bool:
  Bool.or(same, base_bad)

# `matches_dtype(x, dt)` -- spec.py:47, spelled out once and reused by every rule
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

# `sp_arg` exists so the eighteen-way `Arg` match below is one def per question rather
# than a match inside every rule that asks one.
def sp_arg(+fx: F.Folded, self: U32) -> O.Arg:
  O.Arena.arg(sp_ar(fx), self)

def arg_dt.go(a: O.Arg) -> Bool:
  match a:
    case O.ADt{dt}: True{}
    case _: False{}

# `isinstance(x.arg, DType)` -- spec.py:79. `ADt` IS the DType arm.
def arg_dt(a: O.Arg) -> Bool:
  arg_dt.go(a)

def arg_str.go(a: O.Arg) -> Bool:
  match a:
    case O.AStr{s}: True{}
    case _: False{}

# `isinstance(x.arg, str)` -- tinygrad/uop/spec.py:236, :224, :236. At THE PIN this list was five
def arg_str(a: O.Arg) -> Bool:
  arg_str.go(a)

def arg_customfunction.go(a: O.Arg) -> Bool:
  match a:
    case O.ACustom{cf}: True{}
    case _: False{}

# `isinstance(x.arg, CustomFunction)` -- spec.py:111. `ACustom` IS that class and it
def arg_customfunction(a: O.Arg) -> Bool:
  arg_customfunction.go(a)

def arg_blob.go(a: O.Arg) -> Bool:
  match a:
    case O.ABlob{n}: True{}
    case _: False{}

# `isinstance(x.arg, bytes)` -- spec.py:96. Only the length is ever read, and
def arg_blob(a: O.Arg) -> Bool:
  arg_blob.go(a)

def arg_none.go(a: O.Arg) -> Bool:
  match a:
    case O.ANone{}: True{}
    case _: False{}

# `x.arg is None` -- tinygrad/uop/spec.py:87, :88, :89, :113, :242, :243.
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
# type IS a field and the whole of spec.py:81-82's lambda is this arm plus a
def arg_axis(a: O.Arg) -> Maybe<&1, O.AxisType>:
  arg_axis.go(a)

def arg_ids.go(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ARange{ids, at}: Some{ids}
    case _: None{}

# spec.py:81's `len(rng.arg) >= 2` -- the tuple is `(ids..., axis_type)`, so the
def arg_ids(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  arg_ids.go(a)

def arg_ink.go(a: O.Arg) -> Bool:
  match a:
    case O.AInk{ins, dt}: True{}
    case _: False{}

# and isinstance(x.arg[1], DType)` -- spec.py:107, and spec.py:122's same shape
def arg_ink(a: O.Arg) -> Bool:
  arg_ink.go(a)

def arg_wmma.go(a: O.Arg) -> Bool:
  match a:
    case O.AWmma{dims, dt, threads, tc}: True{}
    case _: False{}

# `isinstance(x.arg, tuple) and len(x.arg) == 4` -- spec.py:137, WMMA's
def arg_wmma(a: O.Arg) -> Bool:
  arg_wmma.go(a)

def arg_call.go(a: O.Arg) -> Maybe<&2, S.Dt>:
  match a:
    case O.ACall{ci}: Some{O.CallInfo.dtype(ci)}
    case _: None{}

# spec.py:113 `lambda x: isinstance(x.arg, CallInfo)` -- the WHOLE rule at HEAD. The
def arg_call(a: O.Arg) -> Maybe<&2, S.Dt>:
  arg_call.go(a)

def arg_param.go(a: O.Arg) -> Maybe<&1, O.ParamArg>:
  match a:
    case O.AParam{pa}: Some{pa}
    case _: None{}

# `isinstance(x.arg, ParamArg)` -- spec.py:93, :148, :151, :158, :217, :264,
def arg_param(a: O.Arg) -> Maybe<&1, O.ParamArg>:
  arg_param.go(a)

def arg_reduce_op.go(a: O.Arg) -> Maybe<&1, O.Op>:
  match a:
    case O.AReduce{rop, num_axes}: Some{rop}
    case _: None{}

# GroupOp.Reduce` -- spec.py:169, :176. `AReduce` is that pair.
def arg_reduce_op(a: O.Arg) -> Maybe<&1, O.Op>:
  arg_reduce_op.go(a)

def arg_allred_dev.go(a: O.Arg) -> Maybe<&2, S.Dev>:
  match a:
    case O.AAllred{rop, dev}: Some{dev}
    case _: None{}

# spec.py:177. `AAllred` is that pair.
def arg_allred_dev(a: O.Arg) -> Maybe<&2, S.Dev>:
  arg_allred_dev.go(a)

def arg_dev.go(a: O.Arg) -> Maybe<&2, S.Dev>:
  match a:
    case O.ADev{dev}: Some{dev}
    case _: None{}

# `is_device(x.arg)` where the arg IS the device -- spec.py:174 (`COPY`),
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

# `u.op is Ops.RANGE and dtypes.is_int(u.dtype)` -- spec.py:87.
def all_range_int(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_range_int(t, fx, Bool.and(acc, sp_range_int(fx, s)))

def any_const(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_const(t, fx, Bool.or(acc, O.op_is(sp_ar(fx), s, O.OpsCONST{})))

def sp_op_in(+fx: F.Folded, s: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, O.Arena.op(sp_ar(fx), s))

def sp_const_or_param(+fx: F.Folded, s: U32) -> Bool:
  sp_op_in(fx, s, [O.OpsCONST{}, O.OpsPARAM{}])

def all_const_or_param(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_const_or_param(t, fx, Bool.and(acc, sp_const_or_param(fx, s)))

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

# `validate_index` -- spec.py:11-27.
# `vmin`/`vmax` (`_min_max`, ops.py:1104) and z3 (`tinygrad/uop/validate.py`, not

def validate_index(+fx: F.Folded, +uidx: U32) -> Maybe<&1, Bool>:
  validate_index.of(sp_nsrc(fx, uidx), is_invalid_at(sp_ar(fx), sp_src0(fx, uidx)))

# `src[1]`, and that is wrong for `te_21` (spec.py:198), whose reject set is all four

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

# the folds and readers the rules share. a rule body is Python's lambda with `self`

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
def sp_tri_v.go(b: Bool, v: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  match b:
    case True{}: v
    case False{}: None{}

def sp_tri_v(b: Bool, v: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  sp_tri_v.go(b, v)

def sp_vb(b: Bool) -> O.Verdict:
  sp_vb.go(b)

# compiles to a DISJUNCTION (upat.py:18-20), so `X or CAST(X)` is exactly
def alt_of(plain: Bool, wrapped: Bool, inner: Bool) -> Bool:
  Bool.or(plain, Bool.and(wrapped, inner))

# `UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted()` -- spec.py:125-130.
def IDX() -> List<&2, O.Op>: [O.OpsINDEX{}, O.OpsSHRINK{}]

def uidx_or_casted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_op_in(fx, s, IDX()), sp_op(fx, s, O.OpsCAST{}), sp_op_in(fx, sp_src0(fx, s), IDX()))

def after_or(+fx: F.Folded, +s: U32, +ops: List<&2, O.Op>) -> Bool:
  alt_of(sp_op_in(fx, s, ops), sp_op(fx, s, O.OpsAFTER{}), sp_op_in(fx, sp_src0(fx, s), ops))

def OP_PARAMISH() -> List<&2, O.Op>:
  [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsAFTER{}]

# `UPat(...).or_bitcasted()` -- spec.py:208.
def buf_or_bitcasted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_op_in(fx, s, OP_PARAMISH()), sp_op(fx, s, O.OpsBITCAST{}), sp_op_in(fx, sp_src0(fx, s), OP_PARAMISH()))

# `UPat.cvar().or_casted()` -- spec.py:208's third src. `UPat.cvar()` IS `UPat(Ops.CONST)`
# (ops.py:1505), so `955037870`'s `UPat(Ops.CONST).or_casted()` and `ded106b18`'s
def const_or_casted(+fx: F.Folded, +s: U32) -> Bool:
  alt_of(sp_src_op(fx, s, 0, O.OpsCONST{}), sp_src_op(fx, s, 0, O.OpsCAST{}), sp_op_in(fx, sp_src0(fx, s), [O.OpsCONST{}]))

# `spec_shared` -- spec.py:49-138. Thirty-three rules, and the three every other
# spec.py:51  (UPat(Ops.SINK, dtypes.void), lambda: True) -- no `src`, so NO arity test.
def sh_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSINK{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:54  (UPat(Ops.NOOP), lambda: True) -- TODO: remove this
def sh_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsNOOP{}), O.VTrue{})

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
def sh_2.tri(+fx: F.Folded, +self: U32) -> Maybe<&1, Bool>:
  sh_2.tri.of(sp_is_invalid(fx, self), sp_arg(fx, self), sp_dt_v(fx, self))

# spec.py:57  (UPat(Ops.CONST, src=(), name="x"), lambda x: x.is_invalid or
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
def sh_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsSTACK{}), nsrc_ge(fx, self, 1)), sp_vb(sh_4.body(fx, self)))

def sh_5.pat.of(op: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(g, n))

def sh_5.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_5.pat.of(sp_op(fx, self, O.OpsWHERE{}), sp_src_dt(fx, self, 0, S.boolean()), nsrc_is(fx, self, 3))

# spec.py:66  (UPat(Ops.WHERE, name="w", src=(UPat(dtype=dtypes.bool), UPat(), UPat())),
def sh_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_5.pat(fx, self), sp_vb(all_mdw(sp_src_from(fx, self, 1), fx, sp_dt_v(fx, self), True{})))

def sh_6.pat.of(op: Bool, d: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, n))

def sh_6.body.of(x: Bool, y: Bool) -> Bool:
  Bool.or(x, y)

def sh_6.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_6.body.of(sp_mdw(fx, sp_src(fx, self, 0), sp_dt_v(fx, sp_src(fx, self, 1))),
               sp_mdw(fx, sp_src(fx, self, 1), sp_dt_v(fx, sp_src(fx, self, 0))))

# `GroupOp.Comparison` as an op SET: `GroupOp.comparison` is a Bool over one op, so the
# set is the three members and this is its `any`.
def sh_6.pat.ops(fx: F.Folded, self: U32) -> Bool:
  sp_op_in(fx, self, [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}])

def sh_6.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_6.pat.of(sh_6.pat.ops(fx, self), sp_dt_is(fx, self, S.boolean()), nsrc_is(fx, self, 2))

# spec.py:68  (UPat(GroupOp.Comparison, dtype=dtypes.bool, src=(UPat.var("x"), UPat.var("y"))),
def sh_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_6.pat(fx, self), sp_vb(sh_6.body(fx, self)))

# `c.dtype in (dtypes.u32, dtypes.weakint)` -- tinygrad/dtype.py:141 aliases `uint` to
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
def sh_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, OP_BITS()), sp_vd(sp_tri(any_float(sp_srcs(fx, self), fx, False{}), False{})))

def OP_SHIFTS() -> List<&2, O.Op>:
  [O.OpsSHL{}, O.OpsSHR{}]

# spec.py:71  (UPat((Ops.SHL, Ops.SHR), src=(UPat.var("x"), UPat.var("c")), name="a"),
# `dtypes.u32` is the ALIAS for uint32 (tinygrad/dtype.py:141), so the pair is
def sh_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_SHIFTS()), nsrc_is(fx, self, 2)), sp_vb(sh_8.body(fx, self)))

def OP_IDIVS() -> List<&2, O.Op>:
  [O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsDIV{}, O.OpsMOD{}]

def sh_9.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.or(sp_is_int(fx, self), any_base_invalid(sp_srcs(fx, self), fx, False{}))

# spec.py:73  (UPat((Ops.TRUNCDIV, Ops.TRUNCMOD, Ops.DIV, Ops.MOD), name="x"),
def sh_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, OP_IDIVS()), sp_vd(sp_tri(sh_9.body(fx, self), False{})))

# spec.py:75  (UPat(GroupOp.ALU, name="x"),
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
def sh_12(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsRANGE{}), nsrc_is(fx, self, 1)), sp_vb(ids_nonempty(sp_arg(fx, self))))

def sh_13.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(nsrc_ge(fx, self, 1), all_int_or_base_invalid(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:83  (UPat(Ops.INDEX, name="x"),
def sh_13(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsINDEX{}), sp_vd(sp_tri(sh_13.body(fx, self), True{})))

def sh_14.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsEND{}), sp_src_dt(fx, self, 0, S.void())), nsrc_ge(fx, self, 1))

def sh_14.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(arg_none(sp_arg(fx, self)), all_range_int(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:86  (UPat(Ops.END, src=(UPat(dtype=dtypes.void),), allow_any_len=True, name="x"),
def sh_14(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_14.pat(fx, self), sp_vb(sh_14.body(fx, self)))

def sh_15.pat.of(op: Bool, d: Bool, s: Bool, c: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, Bool.and(c, n))))

def sh_15.src(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(sp_src_op(fx, self, 1, O.OpsRANGE{}), sp_src_dt(fx, self, 1, S.void()))

def sh_15.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_15.pat.of(sp_op(fx, self, O.OpsBACKEDGE{}), sp_dt_is(fx, self, S.void()),
               sh_15.src(fx, self), sp_src_dt(fx, self, 2, S.boolean()), nsrc_is(fx, self, 3))

def sh_15.body.pick(no_arg: Bool, scalar: Bool, cond_bad: Bool) -> Bool:
  Bool.and(no_arg, Bool.and(scalar, Bool.not(cond_bad)))

def sh_15.body.go(a: O.Arg, +cond: U32, +fx: F.Folded) -> Bool:
  sh_15.body.pick(arg_none(a), sp_is_scalar(fx, cond), sp_base_invalid(fx, cond))

def sh_15.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_15.body.go(sp_arg(fx, self), sp_src(fx, self, 2), fx)

# spec.py:89  (UPat(Ops.BACKEDGE, dtypes.void,
def sh_15(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_15.pat(fx, self), sp_vb(sh_15.body(fx, self)))

def is_param.go(pa: Maybe<&1, O.ParamArg>) -> Bool:
  match pa:
    case Some{p}: True{}
    case _: False{}

def is_param(a: O.Arg) -> Bool:
  is_param.go(arg_param(a))

# spec.py:92  (UPat(Ops.PARAM, src=(p_size,), name="x"), lambda x: isinstance(x.arg, ParamArg))
def sh_16(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 1)), sp_vb(is_param(sp_arg(fx, self))))

def is_reg_or_local.go(+m: Maybe<&2, S.Addr>) -> Bool:
  Bool.or(addr_eq.go(m, S.AReg{}), addr_eq.go(m, S.ALocal{}))

def is_reg_or_local(m: Maybe<&2, S.Addr>) -> Bool:
  is_reg_or_local.go(m)

def sh_17.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(is_param(sp_arg(fx, self)), is_reg_or_local(addr_of(sp_addr(fx, self))))

# spec.py:93  (UPat(Ops.BUFFER, src=(p_size,), name="x"),
def sh_17(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBUFFER{}), nsrc_is(fx, self, 1)), sp_vb(sh_17.body(fx, self)))

def sh_18.pat(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(sp_op(fx, self, O.OpsBINARY{}), sp_dt_is(fx, self, S.uint8())), nsrc_is(fx, self, 0))

# spec.py:95  (UPat(Ops.BINARY, dtypes.u8, src=(), name="x"), lambda x: isinstance(x.arg, bytes))
def sh_18(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_18.pat(fx, self), sp_vb(arg_blob(sp_arg(fx, self))))

def OP_AFTER19() -> List<&2, O.Op>:
  [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsSTAGE{}, O.OpsINDEX{},
   O.OpsAFTER{}, O.OpsUNSHARD{}, O.OpsBITCAST{}, O.OpsINS{},
   O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{},
   O.OpsCONST{}, O.OpsCAST{}, O.OpsNOOP{}, O.OpsSTACK{}]

# spec.py:101 (UPat(Ops.AFTER, src=(UPat(Movement|PARAM|BUFFER|ALLOC|STAGE|INDEX|AFTER|
# where upstream answers None -- and that made upstream's rule 20 (spec.py:104, an
# ACCEPTS. MEASURED on `AFTER(ADD(1, 2))`: upstream's `spec_shared` says 1, and
def sh_19.pat.of(op: Bool, n: Bool, s: Bool) -> Bool:
  Bool.and(op, Bool.and(n, s))

def sh_19.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_19.pat.of(sp_op(fx, self, O.OpsAFTER{}), nsrc_ge(fx, self, 1), sp_src_in(fx, self, 0, OP_AFTER19()))

def sh_19(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_19.pat(fx, self), O.VTrue{})

# spec.py:104 (UPat(Ops.AFTER, src=(UPat(GroupOp.ALU),), allow_any_len=True, name="x"),
def sh_20.alu.go(op: O.Op) -> Bool:
  O.GroupOp.alu(op)

def sh_20.alu(+fx: F.Folded, self: U32) -> Bool:
  sh_20.alu.go(O.Arena.op(sp_ar(fx), sp_src(fx, self, 0)))

def sh_20.pat.of(op: Bool, n: Bool, a: Bool) -> Bool:
  Bool.and(op, Bool.and(n, a))

def sh_20.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_20.pat.of(sp_op(fx, self, O.OpsAFTER{}), nsrc_ge(fx, self, 1), sh_20.alu(fx, self))

def sh_20(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_20.pat(fx, self), sp_vb(sp_is_scalar(fx, sp_src(fx, self, 0))))

# spec.py:106 (UPat((Ops.CUSTOMI, Ops.CUSTOM), name="x"),
def sh_21(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op_in(fx, self, [O.OpsCUSTOMI{}, O.OpsCUSTOM{}]), sp_vb(arg_ink(sp_arg(fx, self))))

# growing a constructor. `uop/ops.bend` carries `CustomFunction` (ops.py:1394
# pin `spec.py:110` read `lambda x: isinstance(x.arg, str)`; at HEAD it reads
# SURVIVED had to change its own predicate. Both rows below move, in OPPOSITE
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

# spec.py:113 (UPat(Ops.CALL, src=(UPat(tuple(OPAQUE_CALL_BODIES)),), allow_any_len=True, name="x"),
def sh_23(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_23.pat(fx, self), sp_vb(sh_23.body(fx, self)))

# spec.py:116 (UPat(Ops.PYLITERAL), lambda: True) -- pattern-compiler IR
def sh_24(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsPYLITERAL{}), O.VTrue{})

# spec.py:119 (UPat(Ops.BARRIER, dtypes.void), lambda: True) -- TODO: spec_program only
def sh_25(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBARRIER{}), sp_dt_is(fx, self, S.void())), O.VTrue{})

# spec.py:122 (UPat(Ops.INS, name="x"),
def sh_26(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsINS{}), sp_vb(arg_ink(sp_arg(fx, self))))

# spec.py:125 (UPat(Ops.STORE, src=(UPat(name="t"), UPat(name="v")), allow_any_len=True),
# goes on. `matches_dtype` is `sp_md` and `weak_dtype` is upstream's `dtype.py:175`,
def weak_dtype_spec.go(c: S.Cls, d: S.Dt) -> S.Dt:
  match c:
    case S.CWeakFloat{}: S.weakfloat()
    case S.CFloat{}: S.weakfloat()
    case S.CWeakInt{}: S.weakint()
    case S.CUint{}: S.weakint()
    case S.CSint{}: S.weakint()
    case _: d

def weak_dtype_spec(+d: S.Dt) -> S.Dt:
  weak_dtype_spec.go(S.Dt.cls(d), d)

def sh_27.pat.of(op: Bool, n: Bool) -> Bool:
  Bool.and(op, n)

def sh_27.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_27.pat.of(sp_op(fx, self, O.OpsSTORE{}), nsrc_ge(fx, self, 2))

def sh_27.body.go(+t: U32, +v: U32, +fx: F.Folded) -> Bool:
  Bool.or(sp_md(fx, v, sp_dt_v(fx, t)),
          sp_dt_is(fx, v, weak_dtype_spec(sp_dt_v(fx, t))))

def sh_27.body(+fx: F.Folded, +self: U32) -> Bool:
  sh_27.body.go(sp_src(fx, self, 0), sp_src(fx, self, 1), fx)

def sh_27.verdict(b: Bool) -> O.Verdict:
  match b:
    case True{}: O.VSkip{}
    case False{}: O.VFalse{}

def sh_27(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_27.pat(fx, self), sh_27.verdict(sh_27.body(fx, self)))

def sh_28.pat.of(op: Bool, u: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, n))

def sh_28.uidx(+fx: F.Folded, self: U32) -> Bool:
  uidx_or_casted(fx, sp_src(fx, self, 0))

def sh_28.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_28.pat.of(sp_op(fx, self, O.OpsLOAD{}), sh_28.uidx(fx, self), nsrc_is(fx, self, 1))

# spec.py:125 (UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted().load(), validate_index)
def sh_28(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_28.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_29.pat.of(op: Bool, u: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, Bool.and(g, n)))

def sh_29.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_29.pat.of(sp_op(fx, self, O.OpsLOAD{}), sh_28.uidx(fx, self), sp_src_dt(fx, self, 2, S.boolean()), nsrc_is(fx, self, 3))

def sh_29.body(+fx: F.Folded, +self: U32) -> Bool:
  sp_md(fx, sp_src(fx, self, 1), sp_dt_v(fx, self))

# spec.py:126 (... .load(UPat.var("alt"), UPat.var("gate", dtype=dtypes.bool), name="load"),
def sh_29(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_29.pat(fx, self), sp_vd(sp_tri_v(sh_29.body(fx, self), validate_index(fx, sp_src(fx, self, 0)))))

def sh_30.pat.of(op: Bool, u: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, n))

def sh_30.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_30.pat.of(sp_op(fx, self, O.OpsSTORE{}), sh_28.uidx(fx, self), nsrc_is(fx, self, 2))

# spec.py:128 (UPat((Ops.INDEX, Ops.SHRINK), name="uidx").or_casted().store(UPat()), validate_index)
def sh_30(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_30.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_31.pat.of(op: Bool, u: Bool, g: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(u, Bool.and(g, n)))

def sh_31.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_31.pat.of(sp_op(fx, self, O.OpsSTORE{}), sh_28.uidx(fx, self), sp_src_dt(fx, self, 2, S.boolean()), nsrc_is(fx, self, 3))

# spec.py:129 (... .store(UPat(), UPat.var("gate", dtype=dtypes.bool)), validate_index)
def sh_31(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_31.pat(fx, self), sp_vd(validate_index(fx, sp_src(fx, self, 0))))

def sh_32.pat.of(op: Bool, d: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, n))

def sh_32.pat(+fx: F.Folded, +self: U32) -> Bool:
  sh_32.pat.of(sp_op(fx, self, O.OpsSTORE{}), sp_dt_is(fx, self, S.void()), nsrc_is(fx, self, 2))

def sh_32.tri.of(x: O.Op) -> Maybe<&1, Bool>:
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
    case _: Some{False{}}

def sh_32.tri.go(x: O.Op) -> Maybe<&1, Bool>:
  sh_32.tri.of(x)

def sh_32.tri(+fx: F.Folded, self: U32) -> Maybe<&1, Bool>:
  sh_32.tri.go(O.Arena.op(sp_ar(fx), sp_src(fx, self, 0)))

# spec.py:133 (UPat(Ops.STORE, dtypes.void, (UPat(name="x"), UPat())),
# `storage_base` (ops.py:801) is `base` with UNSHARD, BITCAST and AFTER stripped,
# and `base` (ops.py:785) is `src[0].base` for a movement op or a DETACH. It is a
def sh_32(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sh_32.pat(fx, self), sp_vd(sh_32.tri(fx, self)))

# spec.py:137 (UPat(Ops.WMMA, src=(UPat(), UPat(), UPat()), name="x"),
def sh_33(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsWMMA{}), nsrc_is(fx, self, 3)), sp_vb(arg_wmma(sp_arg(fx, self))))

def OP_ALU.go() -> List<&2, O.Op>:
  [O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{}, O.OpsNEG{},
   O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsTRUNCDIV{}, O.OpsMAX{},
   O.OpsTRUNCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

def OP_ALU() -> List<&2, O.Op>:
  OP_ALU.go()


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
    O.PMEntry{19, [O.OpsAFTER{}],              Nil{}},   # 101
    O.PMEntry{20, [O.OpsAFTER{}],              Nil{}},   # 104
    O.PMEntry{21, [O.OpsCUSTOMI{}, O.OpsCUSTOM{}], Nil{}},# 106
    O.PMEntry{22, [O.OpsCUSTOM_FUNCTION{}],    Nil{}},   # 110
    O.PMEntry{23, [O.OpsCALL{}],               Nil{}},   # 112
    O.PMEntry{24, [O.OpsPYLITERAL{}],          Nil{}},   # 116
    O.PMEntry{25, [O.OpsBARRIER{}],            Nil{}},   # 119
    O.PMEntry{26, [O.OpsINS{}],                Nil{}},   # 122
    O.PMEntry{27, [O.OpsSTORE{}],              Nil{}},   # 125
    O.PMEntry{28, [O.OpsLOAD{}],               Nil{}},   # 125
    O.PMEntry{29, [O.OpsLOAD{}],               Nil{}},   # 126
    O.PMEntry{30, [O.OpsSTORE{}],              Nil{}},   # 128
    O.PMEntry{31, [O.OpsSTORE{}],              Nil{}},   # 129
    O.PMEntry{32, [O.OpsSTORE{}],              Nil{}},   # 133
    O.PMEntry{33, [O.OpsWMMA{}],               Nil{}}]}  # 137


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
    case 33: sh_33(fx, self)
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

# `valid_device_range` -- spec.py:33.
# THE `vmax` HALF, and it IS PORTABLE. ops.py:1147 says a RANGE's `vmax` is

def valid_device_range(d: DevOpt, srcs: List<&2, U32>, +fx: F.Folded) -> Maybe<&1, Bool>:
  valid_device_range.go(d, srcs, fx)

# `ok` is the `isinstance(x.arg, ParamArg)`; the rest are the fields, already reduced
# to the question each rule asks of them.
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

# folded arena and the node's own index -- for the same reason `graphcmp.py:703`'s
def pa_of.pick(m: Maybe<&1, O.ParamArg>, size: Maybe<&2, U32>) -> Pa:
  match m:
    case Some{O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}}:
      pa_of.all(size, vmin_vmax, device, buffer)
    case _: Pa{False{}, False{}, DNo{}, False{}, False{}}

def pa_of.go(m: Maybe<&1, O.ParamArg>, size: Maybe<&2, U32>) -> Pa:
  pa_of.pick(m, size)

def pa_of(+fx: F.Folded, +self: U32) -> Pa:
  pa_of.go(arg_param(sp_arg(fx, self)), O.ParamArg.size(F.Folded.ar(fx), self))

def dopt_is.go(d: DevOpt) -> Bool:
  match d:
    case DNo{}: False{}
    case _: True{}

def dopt_is(d: DevOpt) -> Bool:
  dopt_is.go(d)

def sp_dev_is(+fx: F.Folded, s: U32) -> Bool:
  dopt_is(dev_opt(dev_of(sp_dev(fx, s))))

# `all(isinstance(s.device, str) for s in x.src)` -- spec.py:184, :271. A `D1`
def all_dev(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_dev(t, fx, Bool.and(acc, sp_dev_is(fx, s)))

# `is_device` -- spec.py:140.
# string end to end, so there is no index for a tag to be checked against: `uop/ops.py:34`
# types `ParamArg.device` as `str|tuple[str, ...]|None`, `device.py:20`'s `ALL_DEVICES` is
# a `list[str]`, `device.py:29`'s device table is `__getitem__(self, ix: str)` -- STRING-
# KEYED -- and `device.py:25`'s only memo over a device name is `@functools.cache` on
# 10, PYTHON 13, everything else 0) built for `ALLOW_DEVICE_USAGE` at `device.py:31`, so

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

def sp_and_vdr.go(facts: Bool, vdr: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  match vdr:
    case Some{v}: Some{Bool.and(facts, v)}
    case _: None{}

def sp_and_vdr(facts: Bool, vdr: Maybe<&1, Bool>) -> Maybe<&1, Bool>:
  sp_and_vdr.go(facts, vdr)

def OP_FUN1() -> List<&2, O.Op>:
  [O.OpsSIN{}, O.OpsLOG2{}, O.OpsEXP2{}, O.OpsSQRT{}, O.OpsRECIP{}]

# `spec_tensor` -- spec.py:143-202. Twenty-three rules, then `+ spec_shared`.
# `PatternMatcher.__add__` is `functools.cache`d list concatenation (ops.py:1597),
# spec.py:144 (UPat((Ops.SIN, Ops.LOG2, Ops.EXP2, Ops.SQRT, Ops.RECIP), src=(UPat(),), name="u"),
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
def te_1.guard(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Pa.ok(pa_of(fx, self)), addr_eq(addr_of(sp_addr(fx, self)), S.AGlobal{}))

def te_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBUFFER{}), nsrc_ge(fx, self, 1)),
             sp_vd(sp_tri_v(te_1.guard(fx, self), te_1.body(fx, self))))

def te_2.size_ok(+present: Bool) -> Bool:
  Bool.or(Bool.not(present), present)

def te_2.facts(+p: Pa) -> Bool:
  Bool.and(Pa.ok(p), Bool.and(Bool.not(Pa.buf(p)), te_2.size_ok(Pa.size(p))))

def te_2.addr.pick(is_global: Bool, in_set: Bool, none: Bool, named: Bool) -> Bool:
  Bool.and(in_set, Bool.or(none, Bool.and(is_global, named)))

def is_global_or_local_or_reg.go(+a: Maybe<&2, S.Addr>) -> Bool:
  Bool.or(addr_eq.go(a, S.AGlobal{}), is_reg_or_local.go(a))

def is_global_or_local_or_reg(a: Maybe<&2, S.Addr>) -> Bool:
  is_global_or_local_or_reg.go(a)

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
def te_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsALLOC{}), nsrc_ge(fx, self, 1)), sp_vb(te_2.body(fx, self)))

def te_3.guard.of(rng: Bool, alu: Bool, scalar: Bool) -> Bool:
  Bool.and(rng, Bool.and(alu, scalar))

def te_3.guard(+fx: F.Folded, +self: U32) -> Bool:
  te_3.guard.of(Pa.vrange(pa_of(fx, self)), addr_eq(addr_of(sp_addr(fx, self)), S.Aalu{}), sp_is_scalar(fx, self))

def te_3.body(fx: F.Folded, self: U32) -> Bool:
  dopt_none(Pa.dev(pa_of(fx, self)))

# spec.py:160 (UPat(Ops.PARAM, src=(UPat(Ops.STACK, src=()),), name="buf"), lambda buf: buf.arg.device is None if buf.is_variable else None)
# `is_variable` (ops.py:1018) is a PARAM with a ParamArg carrying a value range,
def te_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 1)),
            sp_vd(sp_tri(te_3.guard(fx, self), te_3.body(fx, self))))

# spec.py:161 (UPat(Ops.SPECIAL, src=(UPat(dtype=dtypes.weakint),), name="s"), lambda s: isinstance(s.arg, str))
def te_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op(fx, self, O.OpsSPECIAL{}), sp_src_dt(fx, self, 0, S.weakint())), nsrc_is(fx, self, 1)),
            sp_vb(arg_str(sp_arg(fx, self))))

def OP_REEXP() -> List<&2, O.Op>:
  [O.OpsRESHAPE{}, O.OpsEXPAND{}]

def te_5.dtype(+fx: F.Folded, +s: U32) -> Bool:
  Bool.or(sp_is_int(fx, s), sp_dt_is(fx, s, S.void()))

# spec.py:166 (UPat((Ops.RESHAPE, Ops.EXPAND), src=(UPat(), UPat(dtype=dtypes.ints+(dtypes.weakint, dtypes.void)))), lambda: True)
def te_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op_in(fx, self, OP_REEXP()), nsrc_is(fx, self, 2)),
                   te_5.dtype(fx, sp_src(fx, self, 1))), O.VTrue{})

def OP_PADSHRINK() -> List<&2, O.Op>:
  [O.OpsPAD{}, O.OpsSHRINK{}]

# spec.py:165 (UPat((Ops.PAD, Ops.SHRINK), src=(UPat(), UPat(), UPat()), name="x"),
def te_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_PADSHRINK()), nsrc_is(fx, self, 3)),
            sp_vb(sp_shape_same(fx, sp_src(fx, self, 1), sp_src(fx, self, 2))))

def OP_PERMFLIP() -> List<&2, O.Op>:
  [O.OpsPERMUTE{}]

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

def sp_int_or_weak(fx: F.Folded, s: U32) -> Bool:
  sp_is_int(fx, s)

def all_ints_or_weak(srcs: List<&2, U32>, +fx: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_ints_or_weak(t, fx, Bool.and(acc, sp_int_or_weak(fx, s)))

def te_8.body(+fx: F.Folded, +self: U32) -> Bool:
  te_8.body.of(arg_reduce_op(sp_arg(fx, self)), all_ints_or_weak(sp_src_from(fx, self, 1), fx, True{}))

# spec.py:169 (UPat(Ops.REDUCE, src=(UPat(),), allow_any_len=True, name="x"),
# signed widths PLUS the four unsigned (tinygrad/dtype.py:159), so it is `dtypes.ints`.
def te_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsREDUCE{}), nsrc_ge(fx, self, 1)), sp_vb(te_8.body(fx, self)))

def te_9.rest(+fx: F.Folded, +self: U32) -> Maybe<&1, Bool>:
  valid_device_range(dev_opt(arg_dev(sp_arg(fx, self))), sp_src_from(fx, self, 1), fx)

# spec.py:177 (UPat(Ops.COPY, name="copy", src=(UPat(),), allow_any_len=True), lambda copy:
def te_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsCOPY{}), nsrc_ge(fx, self, 1)),
            sp_vd(sp_tri_v(is_device(arg_dev(sp_arg(fx, self))), te_9.rest(fx, self))))

def te_10.body.pick(rop: Maybe<&1, O.Op>, dev: Bool) -> Bool:
  match rop:
    case Some{r}: Bool.and(O.GroupOp.reduce(r), dev)
    case _: False{}

def te_10.body.of(rop: Maybe<&1, O.Op>, dev: Bool) -> Bool:
  te_10.body.pick(rop, dev)

# `AAllred` is `(Ops, str|tuple)` and `AReduce` is `(Ops, int)`, and an ALLREDUCE's arg
# is the `AAllred`, so its `arg[0]` needs its own reader.
def arg_reduce_op_of_allred.go(a: O.Arg) -> Maybe<&1, O.Op>:
  match a:
    case O.AAllred{rop, dev}: Some{rop}
    case _: None{}

def arg_reduce_op_of_allred(a: O.Arg) -> Maybe<&1, O.Op>:
  arg_reduce_op_of_allred.go(a)

def te_10.body(+fx: F.Folded, +self: U32) -> Bool:
  te_10.body.of(arg_reduce_op_of_allred(sp_arg(fx, self)), is_device(arg_allred_dev(sp_arg(fx, self))))

# spec.py:176 (UPat(Ops.ALLREDUCE, name="red", src=(UPat(),)),
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
def te_12(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSELECT{}), sp_vb(mselect_ok(fx, self)))

def mstack_body.of(named: Bool, +srcs: List<&2, U32>, head_none: Bool) -> Bool:
  Bool.or(named, Bool.and(all_same(srcs, all_same_head(srcs), True{}), head_none))

def mstack_body(+fx: F.Folded, +self: U32) -> Bool:
  mstack_body.of(all_dev(sp_srcs(fx, self), fx, True{}), sp_srcs(fx, self),
    dopt_none(dev_opt(dev_of(sp_dev(fx, sp_src(fx, self, 0))))))

# spec.py:184 (UPat(Ops.MSTACK, name="x"),
def te_13(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSTACK{}), sp_vb(mstack_body(fx, self)))

def OP_DETACH() -> List<&2, O.Op>:
  [O.OpsDETACH{}, O.OpsCONTIGUOUS_BACKWARD{}]

# spec.py:187 (UPat((Ops.DETACH, Ops.CONTIGUOUS_BACKWARD), src=(UPat(),), arg=None), lambda: True)
# `arg=None` in a `UPat` is NOT `self.arg is None` -- `upat.py:27` emits a clause
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

# THE TAG SHIFT, and it exists because `+` concatenates entry LISTS. ops.py:1597

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

# WRONG, and the pin settles it:
# At the pin, `spec_tensor`'s fourth rule WAS `Ops.CUSTOM_FUNCTION`, at spec.py:161, and
# `isinstance(x.arg, str)` became FALSE for every such node, so it was DELETED rather than
#     DIFFERENT rule.
# THE TABLE. `spec.py:199` is `])+spec_shared`, so this list is followed by

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

def pr_0.claims(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.not(O.UOp.is_none(self)), Bool.not(O.GroupOp.defines(O.Arena.op(sp_ar(fx), self))))

def pr_0.body(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.not(sp_op(fx, self, O.OpsCAST{})), any_const(sp_srcs(fx, self), fx, False{}))

# `spec_program` -- spec.py:205-228. Nine rules, then `+ spec_shared`.
# spec.py:204 (UPat(GroupOp.All-GroupOp.Defines, name="x"),
# (tinygrad/uop/__init__.py:114, `Defines = {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}`),
def pr_0(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_0.claims(fx, self), sp_vd(sp_tri(pr_0.body(fx, self), False{})))

# spec.py:205 (UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks), lambda: False)
# `dtypes.weaks` is a TWO-element set, so upat.py:35 emits `dtype in {weakint,
def pr_1.claims(+fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.not(O.UOp.is_none(self)), Bool.not(sp_op(fx, self, O.OpsCONST{})))

def pr_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(pr_1.claims(fx, self), sp_is_weak(fx, self)), O.VFalse{})

def pr_2.pat.of(op: Bool, b: Bool, c: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(b, Bool.and(c, n)))

def pr_2.pat(+fx: F.Folded, +self: U32) -> Bool:
  pr_2.pat.of(sp_op(fx, self, O.OpsSHRINK{}), buf_or_bitcasted(fx, sp_src(fx, self, 0)),
              const_or_casted(fx, sp_src(fx, self, 2)), nsrc_is(fx, self, 3))

# spec.py:208 (UPat(Ops.SHRINK, src=(UPat((Ops.PARAM, Ops.BUFFER, Ops.ALLOC, Ops.AFTER))
def pr_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_2.pat(fx, self), O.VTrue{})

# spec.py:211 (UPat(GroupOp.Movement), lambda: False)
def pr_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(O.GroupOp.movement(O.Arena.op(sp_ar(fx), self)), O.VFalse{})

def OP_BA() -> List<&2, O.Op>:
  [O.OpsBUFFER{}, O.OpsALLOC{}]

# spec.py:214 (UPat((Ops.BUFFER, Ops.ALLOC), name="x"),
def pr_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op_in(fx, self, OP_BA()), nsrc_is(fx, self, 1)),
             sp_vb(Bool.and(Pa.ok(pa_of(fx, self)), is_reg_or_local(addr_of(sp_addr(fx, self))))))

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
def pr_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_6.pat(fx, self), O.VTrue{})

def pr_7.pat.of(op: Bool, d: Bool, s: Bool, n: Bool) -> Bool:
  Bool.and(op, Bool.and(d, Bool.and(s, n)))

def pr_7.pat(+fx: F.Folded, +self: U32) -> Bool:
  pr_7.pat.of(sp_op(fx, self, O.OpsENDIF{}), sp_dt_is(fx, self, S.void()),
              sp_src_op(fx, self, 0, O.OpsIF{}), nsrc_is(fx, self, 1))

# spec.py:221 (UPat(Ops.ENDIF, dtype=dtypes.void, src=(UPat(Ops.IF),)), lambda: True)
def pr_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(pr_7.pat(fx, self), O.VTrue{})

# spec.py:224 (UPat(Ops.SPECIAL, src=(UPat(dtype=dtypes.i32),), name="s"), lambda s: isinstance(s.arg, str))
# SPECIAL is weakint before index lowering (spec.py:164) and int32 after (here).
def pr_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(Bool.and(sp_op(fx, self, O.OpsSPECIAL{}), sp_src_dt(fx, self, 0, S.int32())), nsrc_is(fx, self, 1)),
            sp_vb(arg_str(sp_arg(fx, self))))

def OP_ALL() -> List<&2, O.Op>:
  [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{},
   O.OpsPARAM{}, O.OpsREFPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{},
   O.OpsPYLITERAL{}, O.OpsSINK{}, O.OpsAFTER{}, O.OpsSTACK{}, O.OpsGETADDR{},
   O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{},
   O.OpsBITCAST{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{},
   O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsTRUNCDIV{},
   O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{},
   O.OpsEND{}, O.OpsENDIF{}, O.OpsBACKEDGE{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{},
   O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}, O.OpsCOPY{}, O.OpsMSELECT{},
   O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{},
   O.OpsPAD{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}]

def OP_MOVE() -> List<&2, O.Op>:
  [O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{}]

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

# `spec_hcq` -- spec.py:230-235. Two rules, then `+ spec_shared`. The device
# spec.py:228 (UPat(Ops.GETADDR, dtypes.u64, name="x",
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

# `spec_full` -- spec.py:238-250. Four rules, then
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
# `spec_full`'s END is WEAKER than `spec_shared`'s (spec.py:85): it drops the
def fu_1(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(fu_1.pat(fx, self), sp_vb(fu_1.body(fx, self)))

# spec.py:246 (UPat(Ops.AFTER, src=(UPat(),), allow_any_len=True), lambda: True)
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
    O.PMEntrys.es(bump(26, shared_table())), O.PMEntrys.es(bump(60, program_own())),
    O.PMEntrys.es(bump(69, hcq_own())))

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

# GETADDR rule (`spec.py:230`) went to `spec_shared`'s SINK rule (`spec.py:50`) and
# `spec_program`'s first rule (`spec.py:206`) to no rule at all, so `fu_rewrite` answered
# False. MEASURED: `gates/specreach-map.rows`, three cells and all of the key `sf`.
def fu_block.go(+tag: U32) -> U32:
  fu_block.pick(U32.is_lt(tag, 26), U32.is_lt(tag, 60), U32.is_lt(tag, 69))

def fu_block(tag: U32) -> U32:
  fu_block.go(tag)

# 27 / 60 / 69, so every tag past `full_own`'s four entered the WRONG table's dispatch;
def fu_dispatch.of(blk: U32, tag: U32, +fx: F.Folded, +self: U32) -> O.Verdict:
  match blk:
    case 1: te_dispatch(U32.sub(tag, 4), fx, self)
    case 2: sh_dispatch(U32.sub(tag, 26), fx, self)
    case 3: pr_dispatch(U32.sub(tag, 60), fx, self)
    case _: hq_dispatch(U32.sub(tag, 69), fx, self)

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

# `spec_kernel_graph` -- spec.py:254-280. Thirteen rules and NOTHING appended:
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
def kg_2(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(kg_2.pat(fx, self), O.VTrue{})

# spec.py:260 (UPat(Ops.STACK, name="s"),
def kg_3(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsSTACK{}), sp_vd(sp_tri(all_const_or_param(sp_srcs(fx, self), fx, True{}), True{})))

# spec.py:263 (UPat(Ops.PARAM, src=(p_size,), name="x"), lambda x: isinstance(x.arg, ParamArg))
def kg_4(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsPARAM{}), nsrc_is(fx, self, 1)), sp_vb(Pa.ok(pa_of(fx, self))))

def kg_5.holder.pin(is_global: Bool, small: Bool, buf: Bool) -> Bool:
  match is_global:
    case True{}: buf
    case _: small

def kg_5.holder.pick(is_global: Bool, small: Bool, buf: Bool) -> Bool:
  kg_5.holder.pin(is_global, small, buf)

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
def kg_5(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsBUFFER{}), nsrc_ge(fx, self, 1)), sp_vb(kg_5.body(fx, self)))

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
def kg_6(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(sp_op(fx, self, O.OpsALLOC{}), nsrc_ge(fx, self, 1)), sp_vb(kg_6.body(fx, self)))

# spec.py:269 (UPat(Ops.BITCAST), lambda: True)
def kg_7(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsBITCAST{}), O.VTrue{})

# spec.py:271 (UPat(Ops.MSTACK, name="x"),
# the same body as spec.py:187, and `mstack_body` is that body -- one def, two rules,
def kg_8(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSTACK{}), sp_vb(mstack_body(fx, self)))

# spec.py:272 (UPat(Ops.MSELECT, name="x"),
def kg_9(+fx: F.Folded, +self: U32) -> O.Verdict:
  O.pm_when(sp_op(fx, self, O.OpsMSELECT{}), sp_vb(mselect_ok(fx, self)))

def kg_10.axis.go(ax: Maybe<&1, O.AxisType>) -> Bool:
  match ax:
    case Some{at}: O.eq_axis(at, O.AXIS_DEVICE{})
    case _: False{}

def kg_10.axis(a: O.Arg) -> Bool:
  kg_10.axis.go(arg_axis(a))

# spec.py:274 (UPat(Ops.RANGE, name="r"), lambda r: r.axis_type is AxisType.DEVICE)
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
   O.OpsBITCAST{}, O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPERMUTE{}, O.OpsPAD{}, O.OpsSHRINK{}]

def kg_12.pat(+fx: F.Folded, +self: U32) -> Bool:
  kg_12.pat.of(sp_op(fx, self, O.OpsAFTER{}), sp_src_in(fx, self, 0, OP_AFTER12()), nsrc_ge(fx, self, 1))

# spec.py:278 (UPat(Ops.AFTER, src=(UPat(Movement|PARAM|AFTER|BUFFER|ALLOC|MSTACK|MSELECT|
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

# `type_verify` -- spec.py:36. It walks `ast.toposort()` and raises on the first
# `SPEC > 1` and `test_pyrender` (spec.py:37) and the `DEBUG >= 3` print
# (spec.py:43) are not here. See the TODO block.

def topo_budget.f(xs: List<&2, O.Node>, acc: U32) -> U32:
  topo_budget.f.go(xs, acc)

def topo_budget(+fx: F.Folded) -> Nat:
  U32.to_nat(U32.add(1, U32.add(O.Arena.next(sp_ar(fx)), topo_budget.f(O.Arena.nodes(sp_ar(fx)), 0))))

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

# `ParamArg` for a GLOBAL BUFFER of `int32` with a size and a device. `ops.bend` lays the
# thirteen fields out in declaration order and this is that order.
def buf_param() -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
             False{}, None{}, Some{0}, False{}, None{}}

# ABOUT them that Python specifies. Every row is one the gate could get WRONG: a
# `hcq_plain` printed 1 -- for the WRONG REASON: node 22 is the AFTER, so the hcq

type Land is Data:
  Land{fx: F.Folded, k: U32, noop: U32, sink: U32, fsub: U32, isub: U32, stack: U32,
       shl_f: U32, shl_i: U32, backedge: U32, prog: U32, ga_plain: U32, ga_after: U32}

def land.put(fx: F.Folded, k: U32, noop: U32, sink: U32, fsub: U32, isub: U32, stack: U32,
             shl_f: U32, shl_i: U32, backedge: U32, prog: U32, ga_plain: U32, ga_after: U32) -> Land:
  Land{fx, k, noop, sink, fsub, isub, stack, shl_f, shl_i, backedge, prog, ga_plain, ga_after}

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
  # the BINARY whose arg is `b"abcd"`: `ABlob` holds the BYTES, because ops.py:201's
  # (`binary_n`, spec.py:96's `isinstance(x.arg, bytes)`), and it is still 4.
  +n18 = O.UOp.new(O.Found.ar(n17), O.OpsBINARY{}, Nil{}, O.ABlob{[97, 98, 99, 100]}, O.TNone{})
  +n19 = O.UOp.new(O.Found.ar(n18), O.OpsPROGRAM{}, [O.Found.i(n3), O.Found.i(n16), O.Found.i(n17), O.Found.i(n18)], O.AProgram{O.ProgramInfo.of()}, O.TNone{})
  +n20 = O.UOp.special(O.Found.ar(n19), O.Found.i(n1), "0")
  +n21 = O.UOp.new.param(O.Found.ar(n20), O.OpsBUFFER{}, Some{4}, O.AParam{buf_param()}, O.TNone{})
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
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.Dn{[0, 1]}},
             False{}, None{}, Some{0}, False{}, None{}}

def main_mdev(ax: O.AxisType) -> Mdev:
  +d1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})
  +d2 = O.UOp.range_end(O.Found.ar(d1), O.Found.i(d1), [0], ax)
  +d3 = O.UOp.new.param(O.Found.ar(d2), O.OpsBUFFER{}, Some{4}, O.AParam{mdev_param()}, O.TNone{})
  Mdev{F.folded(O.Found.ar(d3)), O.Found.i(d3)}


def tbl_len(ts: O.PMEntrys) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(ts)))

# tensor figure was 23+33 and was WRONG until 2026-10-03 -- see THE TWENTY-THIRD
# was 33 and was WRONG until 2026-10-22, when upstream's two rules (spec.py:104
# and spec.py:125) were added to this table and took it to 34.
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
def t_tag_const.of(claimed: Bool, rej: List<&2, O.Op>) -> U32:
  if_b(Bool.and(claimed, U32.is_eq(U32.from_nat(List.length(&2, O.Op, rej)), 0)))

def t_tag_const() -> U32:
  t_tag_const.of(O.op_in(O.PMEntry.ops(entry_at(shared_table(), 2)), O.OpsCONST{}),
                 O.PMEntry.rej(entry_at(shared_table(), 2)))

def t_tag_rej.of(a: Bool, b: U32) -> U32:
  if_b(Bool.and(a, U32.is_eq(b, 4)))

def t_tag_rej() -> U32:
  t_tag_rej.of(rej_is(O.PMEntry.rej(entry_at(shared_table(), 15)), [O.OpsRANGE{}]),
               rej_len(entry_at(tensor_own(), 21)))

# tinygrad/uop/spec.py:52 -- a SINK is `True` in `spec_shared`, with no arity test.
def t_sink_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.sink(main_arena())))

# spec.py:54 -- a NOOP is `True` in every table EXCEPT `spec_kernel_graph`, which is
def t_noop_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.noop(main_arena())))

def t_noop_kg() -> U32: show_v(kernel_graph_rewrite(Land.fx(main_arena()), Land.noop(main_arena())))

# spec.py:57 -- `sh_2`. See `sh_2` for why its second disjunct cannot be made to
def t_const_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.k(main_arena())))

# spec.py:62 -- a STACK whose srcs are one float and one int is REJECTED, because
def t_stack_dt() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.stack(main_arena())))

# spec.py:70 vs :71. BOTH claim a SHL and they DISAGREE: `sh_7` says `False` for a
def t_shl_wins() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.shl_f(main_arena())))

def t_shl_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.shl_i(main_arena())))

# spec.py:110 -- `sh_22`, and the row that COULD NOT BE WRITTEN while `sh_22` was the
def t_cf_arg_ok() -> U32:
  +n = O.UOp.custom_function(O.Arena.empty(), "sel_registerName", Nil{}, S.void())
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# THE TWO ROWS MOVE IN OPPOSITE DIRECTIONS and that is the whole reason there are two.
def t_cf_arg_str() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsCUSTOM_FUNCTION{}, Nil{}, O.AStr{"sel_registerName"}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# MEASURED, not assumed: a NOOP with the same arg is CLAIMED (1) by an earlier rule,
def t_cf_arg_after() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsAFTER{}, Nil{}, O.ACustom{O.CustomFunction.of("f")}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

def t_cf_arg_noop() -> U32:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ACustom{O.CustomFunction.of("f")}, O.TNone{})
  show_v(shared_rewrite(F.folded(O.Found.ar(n)), O.Found.i(n)))

# spec.py:88 -- the BACKEDGE, and the only rule here whose `rej` is non-empty AND
def t_backedge_ok() -> U32: show_v(shared_rewrite(Land.fx(main_arena()), Land.backedge(main_arena())))

# spec.py:198 -- a FOUR-src PROGRAM. `te_21`'s `rej` is all four of its src ops, so
def t_prog4_ok() -> U32: show_v(tensor_rewrite(Land.fx(main_arena()), Land.prog(main_arena())))

# spec.py:231 -- the `or_after` DISJUNCTION, both ways. A conjunction would accept
def t_hcq_plain() -> U32: show_v(hcq_rewrite(Land.fx(main_arena()), Land.ga_plain(main_arena())))

def t_hcq_after() -> U32: show_v(hcq_rewrite(Land.fx(main_arena()), Land.ga_after(main_arena())))

# spec.py:34 -- `int(rng.vmax)+1 == len(device)`, with `device` a two-name tuple and
def t_multidev_ok() -> U32: show_v(tensor_rewrite(Mdev.fx(main_mdev(O.AXIS_DEVICE{})), Mdev.buf(main_mdev(O.AXIS_DEVICE{}))))

def t_multidev_bad() -> U32: show_v(tensor_rewrite(Mdev.fx(main_mdev(O.AXIS_GLOBAL{})), Mdev.buf(main_mdev(O.AXIS_GLOBAL{}))))

# TODO(p3) upat.py:173  symbol=upat_compile  -- the pyrender GLOBALS: NOT IN
# TODO(p3) upat.py:181  symbol=upat_compile  -- the pyrender EVAL: NOT IN
# TODO(p3) render.py:65  symbol=render_uir  -- the pyrender TEST: NOT IN
# TODO(p3) spec.py:37  type_verify's `SPEC > 1` arm -- GONE from upstream at this
# TODO(p3) spec.py:26  validate_index_with_z3 -- `from tinygrad.uop.validate import
# TODO(p3) device.py:71  symbol=is_disk_device  -- `from tinygrad.device import is_disk_device`
#   a DISK" has nothing to ask. The only reader is `te_9` (spec.py:177) and the
# TODO(p3) spec.py:11  def validate_index -- the first two returns
#   ops.py:1104, the largest piece `fold.bend` defers) and z3. The answer is `None`,
# TODO(p3) spec.py:30  def valid_device_range -- PORTED, INCLUDING the `vmax + 1`
# TODO(p3) spec.py:35  def type_verify -- PORTED as six folds that return the
# TODO(p3) spec.py:136  symbol=spec_shared  lambda x: `b := x.storage_base` -- a `while` over BITCAST,
# TODO(p3) spec.py:56  lambda x: `type(x.val) is type(x.dtype.const(x.val))` --
#   PORTED as the class correspondence `DType.const` (tinygrad/dtype.py:79) actually
#   `dtype.bend` becomes importable, `truncate` (tinygrad/dtype.py:295) is the half that is
# TODO(p3) spec.py:151 lambda buf: `isinstance(buf.dtype, DType)` -- vacuous in this
#   1. `_min_max` (ops.py:1104) unblocks `validate_index`'s body, `valid_device_range`
#   2. `storage_base` (ops.py:801) unblocks `sh_32`'s deferred arm.
#      `ParamArg.device` (`uop/ops.py:34`) is a `str` and `device.py:29`'s is
#   sh_len=33    spec.py:50-138 is 33 entries. A count, so a MISSING rule shows.
#   te_len=55    22 own (spec.py:143-199) + 33 shared. It PRINTED 56 and its
#   pr_len=42    9 own (spec.py:202-225) + 33 shared.
#   hq_len=35    2 own (spec.py:227-232) + 33 shared.
#   kg_len=13    spec.py:251-277 is 13 entries and NOTHING is appended.
#   tag_const=1  spec.py:57 is `UPat(Ops.CONST, ...)` with an EMPTY reject set.
#   tag_rej=1    spec.py:89's reject set is `[RANGE]` and spec.py:198's is all four
#   sink_ok=1    spec.py:51 -- a void SINK, with no arity test at all.
#   noop_ok=1    spec.py:54 -- a NOOP is legal in `spec_shared`.
#   const_ok=1   spec.py:57. See the TODO on spec.py:57: this row cannot be made to
#   stack_dt=0   spec.py:62 -- one float src and one int src is REJECTED, because
#   shl_wins=0   spec.py:70 vs :71. Both claim a SHL and they DISAGREE, so this row
#   backedge_ok=1  spec.py:89 -- the rule whose reject set is non-empty AND whose
#   prog4_ok=1   spec.py:198 -- a FOUR-src PROGRAM. Its reject set is all four src
#   hcq_plain=1  spec.py:228, the BARE `or_after` alternative: `GETADDR(BUFFER)`.
#   hcq_after=1  spec.py:228, the WRAPPED alternative: `GETADDR(AFTER(BUFFER))`. A
#   multidev_ok=1  spec.py:33 -- `int(rng.vmax)+1 == len(device)` with a two-name
# those offsets were WRONG for part of this session -- `fu_dispatch.of` said 27 / 60 / 69
# every tag past `full_own`'s four entered the WRONG table's dispatch, and dropping the
# GROUP rule (2026-10-18) left a HOLE at tag 58 on top of that. The cost was MEASURED and
# grades the cells `gates/specreach-map.rows` prints. MEASURED: with the thresholds put
# MEASURED PROOF of a claim this file's header makes: every non-empty
# so it can only ever see two ops; `spec.py:201`'s reject set is FOUR ops long, so
# unverified. `spec.py:31` and `:32` are safe by accident -- `len(src) == 0` and
