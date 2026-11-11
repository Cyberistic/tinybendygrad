# weak.bend -- tinygrad/uop/weak.py: the four `PatternMatcher` tables that commit
# weak dtypes at lowering boundaries. 5 of weak.py's 9 defs and 3 of its 8 rules.
#
# TWO DEPENDENCIES, measured. `dtype.bend` is unreachable to any importer (it prints a
# foreign-code notice for `Dt.bf16`, `Dt.fp16`, the `fp8_*` and the `i64_*`/`float_to_*`
# helpers), so `strong_dtype` and `weak_dtype` are spelled HERE, as `fold.bend` did for
# `least_upper_dtype`. `least_upper_dtype` is `F.promo_dtype`. `dtype_from_uop` over a
# chosen src list is NOT a wall: `F.dt_shape` is `dtype_from_uop` with its src half
# factored out as `List<Derived>`, and `Derived` is `Data`, so a fold rebuilds one per
# hypothetical src (`wk_derived`/`wk_dtype_at` below). Asking the fold about a node that
# does not exist would need a scratch arena and a second Kahn worklist per query.
#
# `UOp._min_max` (ops.py:1104-1158) IS LANDED, and the reader that joins it to
# `commit_dtype` is landed with it. `fold.bend:3165 symbol=mm.u64.of` once recorded the
# sweep as the biggest single piece left in that half of ops.py and named what was missing
# (`i64_mul`, `i64_div`, `i64_mod`; there is no F32 min/max) -- all of which now exist, and
# the arithmetic core is at `fold.bend:3165 symbol=mm.u64.of` under a "when helpers.bend
# grows them these defs go there" notice that has been kept.
#
# SO the nine markers below that say "`commit_dtype` IS missing" ARE out of date, and the
# wall was never a LANGUAGE limit. It was an IMPORT TOPOLOGY: the arithmetic is
# `D.commit_dtype` in `mixin/dtype.bend`, which does not import this file, and `wk_dt` is
# here -- so one call could not be written. `wk_commit_dtype` is that call, and
# `gates/wk-cd-gate.py` is its gate: 7 rows, three lanes, 7 identical and NO divergence
# (the `cd_none` divergence -- a PARAM with no `vmin_vmax`, where the sweep had no interval
# to report -- is CLOSED: `commit_dtype.weak` now supplies the widest int64 range when
# bounds are unavailable, and `commit_int` answers `i64` the way CPython's does). The nine
# markers are now blocked on their own RULE BODIES and not on a reader.
#
# AND THE FIVE READERS BELOW -- `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` /
# `wk_is_virtual` / `wk_commit_dtype` -- HAVE CALLERS, and the CALLERS ARE GATES.
# `gates/wk-eval-gate.py` (22 rows, three lanes) reads the three `_eval` readers and
# `gates/wk-isvirt-gate.py` (5 rows, three lanes) reads `wk_is_virtual`. A DEF WITH NO
# CALLER IN `tinybendygrad/` IS NOT A DEAD DEF: a GATE is a caller, and a corpus that
# measures reachability over the PORT ALONE will call a gated reader unreachable.
#
# WHAT THE GATE HAS TO CONTAIN, because the obvious fixture proves nothing: a PARAM whose
# dtype is int32 answers `i32` on EVERY row, because the weakint branch is not taken. And
# with `default_int = int32` the ladder's first rung swallows every range inside int32. So
# the rows that discriminate are the ranges int32 CANNOT hold, and a gate without them
# would pass a reader that always answered `i32`.
#
# THE SECOND WALL is `DType.const` (tinygrad/dtype.py:79-84) for
# fp8s, whose `truncate` entry is a C-effect seam. `wk_sealed` names those six dtypes and
# `wk_blocked` turns "this rule wants a sealed `dt.const`" into "no answer" -- which is
# `fold.bend`'s stated policy: the fold reports the absence and the caller decides.

import Base
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./ops.bend as O
import ./fold.bend as F
import ./../mixin/dtype.bend as D

# `dtypes.weaks` (dtype.py:160) is `(weakint, weakfloat)`, the two members of `S.Cls`
# that are neither concrete-signed nor concrete-unsigned.

def weak_cls(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_weak(d: S.Dt) -> Bool:
  weak_cls(S.Dt.cls(d))

# strong_dtype -- dtype.py:169-170, `{weakint: default_int, weakfloat:
# default_float}.get(dtype, dtype)`. weak.py calls dtype.bend's version with no defaults,
# so they are `S.int32()`/`S.single()` here.
def strong_dtype.cls(cls: S.Cls, di: S.Dt, df: S.Dt, d: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakInt{}: di
    case S.CWeakFloat{}: df
    case _: d

# weak_dtype -- dtype.py:175-176, `weakfloat if is_float(dtype) else weakint if
# is_int(dtype) else dtype`. The predicate is load-bearing: `is_float`/`is_int` cover
# EVERY concrete width as well, so a concrete float really does become weakfloat.
def weak_dtype.int(dt: S.Dt, isint: Bool) -> S.Dt:
  match isint:
    case True{}: S.weakint()
    case False{}: dt

def weak_dtype.of(isfloat: Bool, isint: Bool, dt: S.Dt) -> S.Dt:
  match isfloat:
    case True{}: S.weakfloat()
    case False{}: weak_dtype.int(dt, isint)

# What is left after the two predicates is `void` and `bool`, and `bool` is neither.
def weak_dtype.cls(+cls: S.Cls, dt: S.Dt) -> S.Dt:
  weak_dtype.of(S.Cls.is_float(cls), S.Cls.is_int(cls), dt)

def weak_dtype(+d: S.Dt) -> S.Dt:
  weak_dtype.cls(S.Dt.cls(d), d)

# The four dtypes whose `truncate` entry is the C-effect seam, matched on the record
# so this is `promo_mask`'s "twenty short arms" style and no `nm` string is compared.
def wk_sealed(d: S.Dt) -> Bool:
  match d:
    case S.Dt{12, 16, S.CFloat{}, _}: True{}    # float16
    case S.Dt{13, 16, S.CFloat{}, _}: True{}    # bfloat16
    case S.Dt{10, 8, S.CFloat{}, _}: True{}     # fp8 e4m3, e4m3fnuz
    case S.Dt{11, 8, S.CFloat{}, _}: True{}     # fp8 e5m2, e5m2fnuz
    case _: False{}

# `ops.bend:1895 symbol=eq_cls.sel` HAD SIX arms and was missing `CWeakFloat`, so
# `eq_cls(CWeakFloat{}, CWeakFloat{})` was False (measured), which also made two
# structurally identical `CAST(..., weakfloat)` nodes fail to hash-cons. ops.bend is
# READ-ONLY to this port, so this is a workaround: the one-line fix is a
# `case S.CWeakFloat{}` arm in `eq_cls.sel`, and then `wk_eq_dt` becomes `O.eq_dt` -- AND that arm has since landed, so the copy below is KEPT because `ops.bend` was read-only when it was written, not because the wall is still there.

# The class as a NUMBER, so the comparison is one `U32.is_eq`. The seven values are the
# declaration order of `S.Cls`, and they are this file's own: `wk_eq_cls` is the only
# place a `Cls` is given a number.
def wk_eq_cls(c: S.Cls) -> U32:
  match c:
    case S.CVoid{}: 0
    case S.CWeakInt{}: 1
    case S.CBool{}: 2
    case S.CUint{}: 3
    case S.CSint{}: 4
    case S.CFloat{}: 5
    case _: 6

def wk_eq_dt.nm(ok: Bool, k: U32, +nm: String, +y: S.Dt) -> Bool:
  match y:
    case S.Dt{p2, b2, c2, n2}:
      Bool.and(ok, Bool.and(U32.is_eq(k, wk_eq_cls(c2)), String.eq(nm, n2)))

def wk_eq_dt.go(p: Bool, b: Bool, +x: S.Dt, +y: S.Dt) -> Bool:
  match x:
    case S.Dt{pri, bits, cls, nm}: wk_eq_dt.nm(Bool.and(p, b), wk_eq_cls(cls), nm, y)

# dtype.py's `DType.__eq__` is the dataclass tuple `(priority, bitsize, name, fmt)`
# and `fmt` is derivable from the class, so `(pri, bits, cls, nm)` is the same value.
def wk_eq_dt(+x: S.Dt, +y: S.Dt) -> Bool:
  wk_eq_dt.go(U32.is_eq(S.Dt.pri(x), S.Dt.pri(y)), U32.is_eq(S.Dt.bits(x), S.Dt.bits(y)), x, y)

# THE READERS. Every dtype read is a read of the FOLD, because a node's dtype is a
# derived property and `fold.bend` is the only well-founded way to answer it: Bend refuses
# the mutual recursion Python breaks with `recursive_property`. `wk_dt` answers `void` for
# a node the fold has not settled, which is dtype.bend's own "no dtype" and a LATTICE
# BOTTOM, so it poisons a `promo_mask` rather than reading as something else; `wk_ready`
# refuses such a node, so the default is never observable.

def wk_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

# `commit_dtype` (dtype.py:16) -- `commit_int(self._uop.vmin, self._uop.vmax, default_int)
# if self.dtype is weakint else self.dtype` -- AS A NODE-LEVEL READER.
#
# what nine of this file's markers said and what none of them got right about WHY:
#   * `D.commit_dtype` is ported (`mixin/dtype.bend`), and takes the node's dtype and its
#     two bounds ALREADY RESOLVED -- CPython's own signature wants them separately, so the
#     port's is not a workaround for anything.
#   * `UOp.vmin` / `UOp.vmax` are ported (`uop/fold.bend`), over the sweep's `BTable`,
#     and return the sweep's `Bnd`.
# What was missing is ONE call that joins them, and it could not be written where the
# arithmetic lives: `mixin/dtype.bend` does not import `uop/weak.bend` and `wk_dt` is here.
# MEASURED, the edge this file adds -- `weak.bend -> mixin/dtype.bend` -- closes NO cycle:
# `ops.bend`, `fold.bend` and `spec.bend` all do NOT import `weak.bend`.
#
# SO the wall was never a language limit. It was an IMPORT topology, and a wall is written
# as a property of the language and read as one.
# `BndInt` is the only arm that COMMITS: `commit_int` takes two ints, so an infinite
# bound and a FLOAT bound have no integer to offer and answer nothing. That is a decision
# and not an omission -- the arm is unreachable for the nodes these nine markers are about
# (a PARAM's bounds are ints) and answering a wrong integer for an infinite one would be
# the failure mode this port has catalogueued all session.
def wk_bnd_i64.of(b: F.Bnd) -> Maybe<&1, H.I64>:
  match b:
    case F.BndInt{neg, mag}: Some{H.i64_neg(neg, mag)}
    case _: None{}

def wk_bnd_i64(m: Maybe<&2, F.Bnd>) -> Maybe<&1, H.I64>:
  match m:
    case Some{b}: wk_bnd_i64.of(b)
    case _: None{}

# `__float__` NEEDS THE OTHER HALF OF `Bnd`, which is `BndFlt{v}` rather than `BndInt{neg,mag}`
# -- a separate reader rather than a flag on this one, because the two arms return different
# types and a `Maybe<(I64, F32)>` would make every caller match a tuple to get one number.
def wk_bnd_f32.of(b: F.Bnd) -> Maybe<&1, F32>:
  match b:
    case F.BndFlt{v}: Some{v}
    case _: None{}

def wk_bnd_f32(m: Maybe<&2, F.Bnd>) -> Maybe<&1, F32>:
  match m:
    case Some{b}: wk_bnd_f32.of(b)
    case _: None{}

# `UOp._eval` -- tinygrad/uop/ops.py:521. THREE CHECKS, IN PYTHON'S ORDER:
#
#   1. assert self.dtype in dtype                 -- the caller's dtype SET
#   2. if vmin != vmax: raise ValueError          -- the bounds must be a SINGLE number
#   3. assert isinstance(vmin, expected_type)     -- the value's Python type
#
# AND CHECK 3 IS IMPLIED BY CHECK 1 HERE rather than merely resembling it: `Cls` IS the type of
# the value, so a bound reading as an integer cannot sit under `CFloat` and one reading as a
# float cannot sit under `CSint`. The gate pins both halves on the SAME node -- `dt_is_float` on
# an int CONST is `False` while `wk_bnd_f32` on that node is `None` -- so they are shown to agree
# per cell rather than assumed to.
#
# ONE body per value TYPE, THREE callers. CPython spells the dunders as three one-liners differing
# only in the tuple and the type; here they differ only in the classifier and the bound reader.
#
# THE bounds are re-READ rather than held, and that is forced by linearity rather than chosen: a
# `case Some{a}` binder is consumed ONCE, so "compare the two bounds and then return one of them"
# cannot hold `vmin` in a binder across the comparison. `bt` and `i` are parameters and may be
# read repeatedly -- `wk_commit_dtype` above already reads each of them twice -- so asking the
# sweep a second time is free and the comparison happens on values that are never held.
def wk_same(lo: Maybe<&1, H.I64>, hi: Maybe<&1, H.I64>) -> Bool:
  match lo, hi:
    case Some{a}, Some{b}: O.eq_i64(a, b)
    case _, _: False{}

def wk_same_f(lo: Maybe<&1, F32>, hi: Maybe<&1, F32>) -> Bool:
  match lo, hi:
    case Some{a}, Some{b}: F32.is_eq(a, b)
    case _, _: False{}

# THE bounds are re-READ, NEVER held. A `Maybe` holding an I64 by value is LINEAR -- a `case`
# binder consumes it once, and so does a plain parameter -- so "compare the two bounds and then
# return one of them" cannot keep the value in hand across the comparison. A `+` PARAMETER may be
# read as many times as the expression needs, which is what `wk_commit_dtype` below does with all
# three of its, so asking the sweep again is what a copy would have bought.
#
# MEASURED, because the rule is the opposite of the obvious reading of `+`: a def with a PLAIN
# parameter is refused at two uses, and the same def with `+` on that parameter compiles at five.
def wk_eval_int(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, H.I64>:
  Bool.pick(Maybe<&1, H.I64>,
            Bool.and(D.dt_is_int(wk_dt(fx, i)),
                     wk_same(wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                             wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})

def wk_eval_float(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, F32>:
  Bool.pick(Maybe<&1, F32>,
            Bool.and(D.dt_is_float(wk_dt(fx, i)),
                     wk_same_f(wk_bnd_f32(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                               wk_bnd_f32(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_f32(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})

def wk_eval_bool(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, H.I64>:
  Bool.pick(Maybe<&1, H.I64>,
            Bool.and(D.dt_is_bool(wk_dt(fx, i)),
                     wk_same(wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                             wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})
# `UOp.is_virtual` -- ops.py:902. `self.device is None or self.dtype in dtypes.weaks`, which is
# ONE LINE in CPython and TWO CLAIMS here, because the port's device is a `Maybe<Dev>` rather
# than a `str|None` and "absent" has to be said as a Bool to go into an `or`.
#
# THE NESTED Maybe IS NOT A TYPO. `F.fold.device` answers `Maybe<Maybe<Dev>>` -- the outer is
# "does this node carry a device at all" and the inner is "is it there", and `wk_dev_of` above
# flattens them for the callers that want a device. `is_virtual` wants them SEPARATE, because
# flattening first would lose the one case it is asking about.
def no_dev(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Bool:
  match m:
    case Some{s}:
      match s:
        case Some{d}: False{}
        case _: True{}
    case _: True{}

def wk_is_virtual(+fx: F.Folded, +i: U32) -> Bool:
  Bool.or(no_dev(F.fold.device(F.Folded.ar(fx), F.Folded.t(fx), i)),
          D.md_weak(wk_dt(fx, i)))

# `UOp.param` -- ops.py:1229, THE SHAPE-LESS ARM. The THIRD def to arrive here rather than in
# `ops.bend`, and the reason is the third distinct one:
#
#   * `_eval` and the three dunders -- `ops.bend` cannot NAME `fold.bend`'s bounds.
#   * `param_noshape` -- `ops.bend` cannot IMPORT `dtype.bend`, because its fp16/bf16/i64 C
#     effects make the checker exit 1 for ANY importer, so `md_weak` (`mixin/dtype.bend:124
#     symbol=md_weak`) is unreachable from there. The file says so in its own header and it
#     is TRUE: a two-line file that imports `dtype.bend` and does nothing else prints the same fourteen lines.
#
# So the rule is not "these three were misfiled" but "a def needing a dtype PREDICATE or a BOUND
# lives downstream of `ops.bend`", and this file imports ops, fold and dtype already.
#
# CPython's `param` is three arms; the other two want `prod(to_max_shape(shape))` plus a `view_as`
# RESHAPE, and `view_as` is ABSENT from the port (so is `unique_num`, which the other arm wants).
def wk_param_noshape(+ar: O.Arena, slot: U32, +dt: S.Dt, vmm: Maybe<&2, O.PyRange>) -> Maybe<&1, O.Found>:
  Bool.pick(Maybe<&1, O.Found>, Bool.not(D.md_weak(dt)),            Some{O.UOp.new.param(ar, O.OpsPARAM{}, None{}, O.AParam{O.ParamArg{slot, dt, vmm, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})},            None{})

# `S.int32()` IS CPython'S `default_int=None` SET TO int32, which is what
# `absorb_weak_src` and `lower_weak_node` pass (`s.commit_dtype(dtypes.i32)`), and it is
# spelled here rather than taken as a parameter because all nine callers want the same one.
def wk_commit_dtype(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, S.Dt>:
  D.commit_dtype(wk_dt(fx, i),
    wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
    wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)), S.int32())

def wk_known.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: True{}
    case None{}: False{}

def wk_known(+fx: F.Folded, i: U32) -> Bool:
  wk_known.go(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i))

def wk_srcs(fx: F.Folded, self: U32) -> List<&2, U32>:
  O.Arena.srcs(F.Folded.ar(fx), self)

def wk_src0(fx: F.Folded, self: U32) -> U32:
  O.Arena.src0(F.Folded.ar(fx), self)

def wk_src1(fx: F.Folded, self: U32) -> U32:
  O.Arena.src(F.Folded.ar(fx), self, 1)

def wk_op_is(fx: F.Folded, self: U32, want: O.Op) -> Bool:
  O.eq_op(O.Arena.op(F.Folded.ar(fx), self), want)

def wk_is_weak(fx: F.Folded, i: U32) -> Bool:
  dt_weak(wk_dt(fx, i))

def wk_is_weak_const(+fx: F.Folded, +i: U32) -> Bool:
  Bool.and(wk_op_is(fx, i, O.OpsCONST{}), wk_is_weak(fx, i))

# `[x.dtype for x in src]`
def wk_dt_list.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ss:
    case Nil{}: acc
    case s <> t: wk_dt_list.go(fx, t, List.append(&2, S.Dt, acc, [wk_dt(fx, s)]))

def wk_dt_list(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, S.Dt>:
  wk_dt_list.go(fx, ss, Nil{})

# promo_dtype -- ops.py:120, which the port hoisted into `fold.bend`.
# THE HOIST IS `promo_dtype` AT fold.bend:298 symbol=promo_dtype. THE `symbol=` IS ON
# ITS own line because a `.py` CITATION on the same line takes it and is judged
# AGAINST UPSTREAM's `promo_dtype` INSTEAD OF THE PORT's.
def wk_meet(+fx: F.Folded, ss: List<&2, U32>) -> S.Dt:
  F.promo_dtype(wk_dt_list(fx, ss))

# `any(...)` over the srcs, as a fold with the answer THREADED, so the walk stays one
# self-call: a `None` returned from the middle of a self-call would need a def that
# returns to the self-call, and that is mutual recursion, which Bend refuses
# (fold.bend's `Kahn.gather` note).
def wk_any_weak.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_any_weak.go(fx, t, Bool.or(acc, wk_is_weak(fx, s)))

def wk_any_weak(+fx: F.Folded, ss: List<&2, U32>) -> Bool:
  wk_any_weak.go(fx, ss, False{})

def wk_any_weak_const.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_any_weak_const.go(fx, t, Bool.or(acc, wk_is_weak_const(fx, s)))

def wk_any_weak_const(+fx: F.Folded, ss: List<&2, U32>) -> Bool:
  wk_any_weak_const.go(fx, ss, False{})

# `wk_ready`: "the fold has answered this node and every src a rule would read". One
# place, called by the driver, so no individual rule repeats the check and the `void`
# default is never observable.
def wk_ready.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_ready.go(fx, t, Bool.and(acc, wk_known(fx, s)))

def wk_ready(+fx: F.Folded, +self: U32) -> Bool:
  wk_ready.go(fx, wk_srcs(fx, self), wk_known(fx, self))

# `dtype_from_uop` OVER A CHOSEN src LIST. `F.fold.shape`/`device`/`addr` answer
# `Maybe<&2, Maybe<&2, T>>`: the OUTER Maybe is "the fold did not answer this node" and
# the INNER one is Python's own `None` (`_shape` is `tuple|None`). `Derived` wants the
# inner one, so each pair is unwrapped once here.

def wk_shape_of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_dev_of(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_addr_of(m: Maybe<&2, Maybe<&2, S.Addr>>) -> Maybe<&2, S.Addr>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_ended_of(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  Maybe.default(&2, List<&2, U32>, m, Nil{})

def wk_derived(+fx: F.Folded, +i: U32) -> F.Derived:
  F.Derived{wk_dt(fx, i),
    wk_shape_of(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), i)),
    wk_dev_of(F.fold.device(F.Folded.ar(fx), F.Folded.t(fx), i)),
    wk_addr_of(F.fold.addr(F.Folded.ar(fx), F.Folded.t(fx), i)),
    Maybe.default(&1, U32, F.fold.base(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
    Maybe.default(&1, U32, F.fold.unbase(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
    Maybe.default(&1, U32, F.fold.sbase(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
    wk_ended_of(F.fold.ended(F.Folded.ar(fx), F.Folded.t(fx), i))}

def wk_deriveds.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, F.Derived>) -> List<&2, F.Derived>:
  match ss:
    case Nil{}: acc
    case s <> t: wk_deriveds.go(fx, t, List.append(&2, F.Derived, acc, [wk_derived(fx, s)]))

def wk_deriveds(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, F.Derived>:
  wk_deriveds.go(fx, ss, Nil{})

def wk_dtshape_dt(m: Maybe<&2, F.DtShape>) -> Maybe<&2, S.Dt>:
  match m:
    case Some{F.DtShape{dt, shape}}: Some{dt}
    case None{}: None{}

# dtype_from_uop(u.op, src, u.arg) with the node's OWN op and arg and a src list of
# my choosing. `None` is Python's `raise RuntimeError`, which `dt_shape` reports the
# same way and which `derived_dtypes` turns into "not derived".
def wk_dtype_at(+fx: F.Folded, +self: U32, dss: List<&2, F.Derived>) -> Maybe<&2, S.Dt>:
  wk_dtshape_dt(F.dt_shape(F.Folded.ar(fx), self, O.Arena.op(F.Folded.ar(fx), self),
    O.Arena.arg(F.Folded.ar(fx), self), dss))

# `DType.const` -- dtype.py:79-84.
#
#   Invalid passes through; a float destination is
#   `truncate.get(self, float)(float(val))`, which is the IDENTITY for float32 / float64
#   / weakfloat and `float_to_fp16` / `float_to_bf16` / `fp8_to_float(float_to_fp8(x))`
#   for float16, bfloat16 and the four fp8s; a bool destination is `bool(val)`; an int
#   destination is `int(val)`.
#
# So those four C-effect dtypes are the whole of the wall and `wk_sealed` names them. The
# int arm is `c_intN(x).value`, which RAISES on overflow in Python; a U32 cannot see that
# difference for a value a weak CONST can hold, so `wk_dt_const` is total where Python is
# not, and that is the only reading this file makes.

# `(lo as f32) + (hi_signed as f32) * 2^32`: exact for every |v| <= 2^24 and monotone
# above it, which is what `float(val)` needs for a CONST.
# `float(val)`: `wk_dt_const.fpure` (below) is its only caller, and `wk_gate` in
# .agents/slop/ is its gate.
#
# IT is a chunky algorithm and not a two-TERM sum, and the reason is the whole content of
# this rewrite. The previous form was
#
#     lo + (neg ? U32.to_f32(hi) - 2**32 : U32.to_f32(hi)) * 2**32
#
# which needs `hi` EXACTLY. `U32.to_f32` is CORRECT -- it is a Bend primitive, gated 12/12
# against CPython over 0..4294967295 -- and it cannot be: f32 has 24 mantissa bits, so
# `U32.to_f32(0xFFFFFFFF)` is 2**32, not 4294967295. So for any negative value the high
# term collapsed to 0 and the answer became `U32.to_f32(lo)` alone. MEASURED: -1 and -2 BOTH
# converted to 4294967296.0, and -2**32 converted to 0.0.
#
# f32 represents every integer below 2**24 EXACTLY, so the magnitude is carried in three
# 24-bit (well, 24/24/16) chunks and combined with exact powers of two. Each `c * 2**24`
# has at most 24 significant bits and is therefore exact, so the only rounding steps are
# the two additions -- and they happen in increasing order of significance, which is what
# makes the result CORRECTLY ROUNDED rather than merely close:
#
#     x = c2 * 2**48 + c1 * 2**24 + c0        c0, c1 < 2**24   c2 < 2**16
#     v = ((c2 * 2**24) + c1) * 2**24 + c0
#
# The chunks are cut from the MAGNITUDE's two's complement bits, and `i64_neg` gives those
# for every value INCLUDING int64.min: negating 0x8000000000000000 is a no-op, and the
# no-op value IS 2**63, which is exactly int64.min's magnitude. So there is no special case
# and no 65th bit -- the one place a two's complement port usually needs an exception, it
# does not, and that is worth stating because it is not obvious.
def wk_i64_to_f32.c0(lo: U32) -> F32: U32.to_f32(U32.and(lo, 16777215))

def wk_i64_to_f32.c1(hi: U32, lo: U32) -> F32:
  # bits 24..47: the low 8 from `lo`'s top byte and the high 16 from `hi`'s bottom half.
  U32.to_f32(U32.or(U32.and(U32.shrn(lo, 24n), 255), U32.shln(U32.and(hi, 65535), 8n)))

def wk_i64_to_f32.c2(hi: U32) -> F32:
  # bits 48..63: the top half of `hi`, 16 bits.
  U32.to_f32(U32.and(U32.shrn(hi, 16n), 65535))

def wk_i64_to_f32.hi(+hi: U32, +lo: U32) -> F32:
  F32.mul(F32.add(F32.mul(wk_i64_to_f32.c2(hi), 16777216.0), wk_i64_to_f32.c1(hi, lo)), 16777216.0)

def wk_i64_to_f32.sgn(neg: Bool, +v: F32) -> F32:
  Bool.pick(F32, neg, F32.neg(v), v)

def wk_i64_to_f32.put(neg: Bool, +hi: U32, +lo: U32) -> F32:
  wk_i64_to_f32.sgn(neg, F32.add(wk_i64_to_f32.hi(hi, lo), wk_i64_to_f32.c0(lo)))

def wk_i64_to_f32.go(+neg: Bool, +x: H.I64) -> F32:
  +m = H.i64_neg(neg, x)
  wk_i64_to_f32.put(neg, H.hi32(m), H.lo32(m))

def wk_i64_to_f32(+x: H.I64) -> F32:
  wk_i64_to_f32.go(H.i64_is_neg(x), x)

# `float(val)`: the identity `truncate.get(self, float)` for every unsealed float.
def wk_dt_const.fpure(v: O.Const) -> O.Const:
  match v:
    case O.CInvalid{}: O.CInvalid{}
    case O.CBool{b}: O.CFloat{U32.to_f32(Bool.to_u32(b))}
    case O.CInt{i}: O.CFloat{wk_i64_to_f32(i)}
    case O.CFloat{f}: O.CFloat{f}

def wk_dt_const.bool(v: O.Const) -> Maybe<&1, O.Const>:
  match v:
    case O.CInvalid{}: Some{O.CInvalid{}}
    case O.CBool{b}: Some{O.CBool{b}}
    case O.CInt{i}: Some{O.CBool{Bool.not(U32.is_zero(H.lo32(i)))}}
    case O.CFloat{f}: Some{O.CBool{Bool.not(U32.is_zero(F32.to_u32(f)))}}

def wk_dt_const.int(v: O.Const) -> Maybe<&1, O.Const>:
  match v:
    case O.CInvalid{}: Some{O.CInvalid{}}
    case O.CBool{b}: Some{O.CInt{H.i64_of_i32(Bool.to_u32(b))}}
    case O.CInt{i}: Some{O.CInt{i}}
    case O.CFloat{f}: Some{O.CInt{H.i64_of_i32(F32.to_u32(F32.trunc(f)))}}

# `ConstFloat(truncate...) if is_float else bool(val) if is_bool else int(val)`.
# The order is dtype.py's and it matters: `is_float` is tested first and bool is not a
# float, while `is_int` INCLUDES weakint so the int arm covers every concrete integer
# and `weakint` itself.
# a `match` may only scrutinise a PARAMETER or a binder, and the seal test is a call,
# so it arrives as the def's FIRST parameter.
def wk_dt_const.sealed_pick.go(sealed: Bool, v: O.Const) -> Maybe<&1, O.Const>:
  match sealed:
    case True{}: None{}
    case False{}: Some{wk_dt_const.fpure(v)}

def wk_dt_const.sealed_pick(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  wk_dt_const.sealed_pick.go(wk_sealed(dt), v)

def wk_dt_const.cls(cls: S.Cls, dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  match cls:
    case S.CFloat{}: wk_dt_const.sealed_pick(dt, v)
    case S.CWeakFloat{}: Some{wk_dt_const.fpure(v)}
    case S.CBool{}: wk_dt_const.bool(v)
    case _: wk_dt_const.int(v)

def wk_dt_const(+dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  wk_dt_const.cls(S.Dt.cls(dt), dt, v)

# `wk_blocked`: this rule wants a `dt.const` at a sealed dtype. `bare` is
# `derived_dtypes(...) is not None`; when it holds only a weak CONST src reaches
# `dt.const` (every other weak src goes through `cast`), and when it does not hold
# EVERY weak src does. That is `not bare or any weak CONST src`, which is the whole
# predicate.
def wk_blocked.of(sealed: Bool, bare: Bool, ss: List<&2, U32>, +fx: F.Folded) -> Bool:
  match sealed:
    case True{}: Bool.or(Bool.not(bare), wk_any_weak_const(fx, ss))
    case False{}: False{}

def wk_blocked(+fx: F.Folded, dt: S.Dt, bare: Bool, ss: List<&2, U32>) -> Bool:
  wk_blocked.of(wk_sealed(dt), bare, ss, fx)

# THE walks that grow the arena. `Walk` is a `Data` record because a rule may read the
# arena as often as it likes and each walk step needs the arena and the rebuilt src list
# together, the same reason fold.bend's `Sized` and spec.bend's `Pa` are records. Two
# fields, two accessors, three rules: that is the reuse, not a new abstraction.

type Walk is Data:
  Walk{ar: O.Arena, srcs: List<&2, U32>}

def Walk.ar(w: Walk) -> O.Arena:
  match w:
    case Walk{ar, srcs}: ar

def Walk.srcs(w: Walk) -> List<&2, U32>:
  match w:
    case Walk{ar, srcs}: srcs

def walk_seed(ar: O.Arena) -> Walk:
  Walk{ar, Nil{}}

def walk_step(w: Walk, +hit: O.Found) -> Walk:
  Walk{O.Found.ar(hit), List.append(&2, U32, Walk.srcs(w), [O.Found.i(hit)])}

def walk_keep(+w: Walk, s: U32) -> Walk:
  Walk{Walk.ar(w), List.append(&2, U32, Walk.srcs(w), [s])}

# THE NODE BUILDERS. `UOp.replace` IS the hash-consing constructor `UOp(op, src=..., kwargs)`,
# so it is `UOp.new` here, and Python's `ret is u` is `UOp.make`'s interning handing back
# the same index -- which is why the identity check below is exactly Python's `is`.
def replace_in(+ar: O.Arena, +self: U32, +src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, self), src, O.Arena.arg(ar, self), O.Arena.tag(ar, self))

# TWO spellings, AND the difference is LOAD-BEARING. A walk that made nodes carries a GROWN
# arena, and the closing `replace` has to be interned in THAT arena or it names a `src` index
# the original arena does not have. Only `uncast_const` -- whose walk is pure, because
# dropping a CAST names `s.src[0]` and mints nothing -- may reach for the fold's own.
def wk_replace(+fx: F.Folded, +self: U32, +src: List<&2, U32>) -> O.Found:
  replace_in(F.Folded.ar(fx), self, src)

def replace_walk(+w: Walk, +fx: F.Folded, +self: U32) -> O.Found:
  replace_in(Walk.ar(w), self, Walk.srcs(w))

# A `Maybe` this file can answer, because `wk_blocked` has already refused the sealed
# case. The `None` arm is unreachable on every path that gets here and is the dead
# default `fold.bend:630` writes for the same reason.
def wk_const_of.pick(m: Maybe<&1, O.Const>) -> O.Const:
  match m:
    case Some{c}: c
    case None{}: O.CInvalid{}

def wk_const_of(m: Maybe<&1, O.Const>) -> O.Const:
  wk_const_of.pick(m)

# mixin/dtype.py:36 `cast`: `self if self.dtype == (dt := to_dtype(dtype)) else
# self._uop.alu(Ops.CAST, arg=dt)`. ops.bend:2020's `UOp.alu` takes no arg, so the
# CAST is spelled with `UOp.new` and the `ADt` arg.
def wk_cast_at.of(same: Bool, +fx: F.Folded, self: U32, +dt: S.Dt) -> O.Found:
  match same:
    case True{}: O.Found{F.Folded.ar(fx), self}
    case False{}: O.UOp.new(F.Folded.ar(fx), O.OpsCAST{}, [self], O.ADt{dt}, O.TNone{})

def wk_cast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  wk_cast_at.of(wk_eq_dt(wk_dt(fx, self), dt), fx, self, dt)

# ops.py:632-638 `UOp.const`: `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`
# -- the bare CONST the fold derives a dtype from, PLUS the CAST. `ops.bend:3050 symbol=UOp.const`
# has the bare half; `.cast` folds away at exactly bool/weakint/weakfloat, so for those three
# Python has ONE node and this has two, which `ops.bend:3050 symbol=UOp.const`'s own doc comment
# documents. Spelling the CAST unconditionally is what `UOp.const`'s own shape does.
def wk_const_at(+fx: F.Folded, +dt: S.Dt, cv: Maybe<&1, O.Const>) -> O.Found:
  wk_cast_at.of(False{}, fx, O.Found.i(O.UOp.const(F.Folded.ar(fx), wk_const_of(cv))), dt)

# ops.py:640 `ccast`: `UOp.const(self.val, dtype) if self.op is Ops.CONST else
# self.cast(dtype)` -- "cast, EXCEPT for CONST, in which case rebuild a new CONST".
def cconst_val(arg: O.Arg) -> Maybe<&1, O.Const>:
  match arg:
    case O.APy{v}: Some{v}
    case _: None{}

def wk_ccast.val(+fx: F.Folded, +self: U32) -> O.Const:
  wk_const_of(cconst_val(O.Arena.arg(F.Folded.ar(fx), self)))

def wk_ccast.of(isconst: Bool, +fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  match isconst:
    case True{}: wk_const_at(fx, dt, wk_dt_const(dt, wk_ccast.val(fx, self)))
    case False{}: wk_cast_at(fx, self, dt)

def wk_ccast(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  wk_ccast.of(O.eq_op(O.Arena.op(F.Folded.ar(fx), self), O.OpsCONST{}), fx, self, dt)

# `remint` -- elementwise.py:12.
#     return u.ccast(dt) if u.op is Ops.CONST else u.replace(src=(remint(u.src[0], dt),)+u.src[1:])
#
# WHY it lives here and not in `mixin/elementwise.bend`. `tensor.bend` NEEDS it, and that is
# not a preference. CPython's `self.eq(inf)` runs `_broadcasted`'s `promote`
# (elementwise.py:29-31), whose weak-CONST arm IS `remint` -- "keep weak CONST weak, might
# lift weakint -> weakfloat". So `self.eq(+inf)` REMINTS `self` and `self != self` does not,
# the two hash-cons APART, and the graph holds `CONST weakfloat 4.0` AND `CONST weakint 4`.
# MEASURED, `.venv/bin/python` on `Tensor(UOp(Ops.CONST, arg=4)).isfinite()`: 15 nodes, five
# CONST leaves. A port that reuses one `CInt{4}` for both halves is 14. `mixin/elementwise.bend`
# IMPORTS `tensor.bend`, so a `remint` there was unreachable FROM `tensor.bend` -- an import
# cycle, not a decision.
#
# AND this is the lowest module that can hold it, which is a measurement and not a taste:
# `wk_dt_const`, `wk_const_of` and `replace_in` are the three things it needs and all three
# are here; `helpers.bend`, `LAWS/spec.bend`, `uop/ops.bend` and `uop/fold.bend` are all
# BELOW `weak.bend` in the import order (`weak.bend` imports every one of them), so none of
# them can see `wk_dt_const` without re-introducing the cycle this move removes. The graph
# `wk_remint -> {wk_dt_const, wk_const_of, replace_in} -> {uop/ops, LAWS/spec}` has no other
# sink.
#
# `W.wk_remint` IS CALLED BY `mixin/elementwise.bend` (`ew_promote.b`) AND BY `tensor.bend`
# (`tn_isfinite.promote`), and `mixin/op.bend:485 symbol=mo_remint.at` reaches it as
# `E.ew_remint` -- the ONE-LINE FORWARDER left at the old name is deliberate: it is the only
# external call site of the six defs below, and renaming it would have meant editing a file
# this move does not otherwise touch. MEASURED with `grep -rn
# 'ew_remint|ew_ccast|ew_const_bare|ew_const_val|ew_src0|ew_is_c0'` over `tinybendygrad/` and `gates/`: `ew_remint` at `mixin/op.bend:485` and at
# `mixin/elementwise.bend`'s own `ew_promote.b`, and NOTHING for the other five. The
# `ew_src0_rev`/`ew_src0_fwd` names in `mixin/elementwise.bend` are ROW LABELS of an unrelated
# `ew_opname_src` probe, `gates/ew_graph_census.bend` names `ew_remint` only in prose, and
# `gates/ew-explog-gate.py:37`'s `ew_const_bare` is prose.

# ops.py:637 says it: ".cast folds away at exactly the dtypes a CONST derives
# (bool/weakint/weakfloat): bare there, the pair everywhere else". So a CONST rebuilt at a
# weak dtype or at bool is ONE node, and everywhere else it is a CAST over a CONST. That is
# the whole difference between `UOp.const(v, dt)` here and in CPython, and it is why a remint
# prints one node and not two. IT IS NOT `wk_cast_at`'s fold: that one compares the node's
# own DERIVED dtype against `dt`, so it would mint a CAST for `remint(CONST weakfloat 4.0,
# weakint)` where Python builds a bare `CONST weakint 4`. Measured difference, so the
# predicate is spelled here rather than borrowed.
def wk_remint.folds(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, S.CWeakInt{}, nm}: True{}
    case S.Dt{pri, bits, S.CWeakFloat{}, nm}: True{}
    case S.Dt{pri, bits, S.CBool{}, nm}: True{}
    case _: False{}

def wk_remint.mkconst(bare: Bool, +dt: S.Dt, +made: O.Found) -> O.Found:
  match bare:
    case True{}: made
    case False{}: O.UOp.new(O.Found.ar(made), O.OpsCAST{}, [O.Found.i(made)], O.ADt{dt}, O.TNone{})

# `UOp.const(val, dt)` -- ops.py:629-635. `wk_bare_const` is the same value truncation and
# the same two nodes, but it builds in the arena the CALLER'S `Folded` names rather than the
# one this walk has grown, so it is the wrong store here; the truncation itself is
# `wk_dt_const`, and `wk_ccast.val` IS the `ew_const_val` this used to carry --
# `wk_const_of(cconst_val(Arena.arg(ar, self)))` is that function under another name, so
# nothing was duplicated by naming it.
def wk_remint.cast(+ar: O.Arena, u: U32, +dt: S.Dt) -> O.Found:
  v = wk_const_of(wk_dt_const(dt, wk_ccast.val(F.folded(ar), u)))
  wk_remint.mkconst(wk_remint.folds(dt), dt, O.UOp.new(ar, O.OpsCONST{}, Nil{}, O.APy{v}, O.TNone{}))

# `u.op is Ops.CONST` -- the leaf test, and THE TOP-LEVEL ONE ONLY. The recursive arm tests
# `u.src[0]`'s op and that is a DIFFERENT question: merging the two into one predicate is
# what put a four-deep `replace` chain in `tn_isfinite`'s graph (MEASURED: 18 nodes, four
# `CONST/1` nodes chained above the const, where CPython has one leaf CONST). The two were
# `ew_is_c0` and `ew_src0` and they stay two.
def wk_remint.isc(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsCONST{})

# `u.replace(src=(...)+u.src[1:])`. `replace_in` IS `UOp.replace` -- the hash-consing
# constructor read straight off the arena. The tail is `O.Arena.src_from(ar, u, 1)`, NOT
# `src_to`: `src_to` keeps the first `k` and `src_from` drops the first `k`, so `src_to(_, 1)`
# is the WHOLE list for a one-src node and the replacement silently gains a src. Measured --
# `DETACH` came out with arity 2 and two CONSTs where CPython has arity 1 and one. The head
# goes back IN FRONT, which is `List.append(&2, U32, [head], tail)`; the other order compiles
# and silently relocates it to the end.
#
# AND THE STORE IS `child`'s, NOT `ar`'s. The recursive call that produced `child` may have
# minted a CONST one step deeper, so `child`'s index is valid only in the arena IT grew;
# handing `replace_in` the pre-recursion `ar` names an index one past its end. Measured on
# `ew_remint_recurse`, which printed `1 BUFFER/0` -- a one-node graph, with the arity still
# right. Same rule as `replace_walk`: the arena comes from whatever LAST built.
def wk_remint.put(+child: O.Found, +ar: O.Arena, +u: U32) -> O.Found:
  replace_in(O.Found.ar(child), u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_from(ar, u, 1)))

# It recurses on `u.src[0]` and it GROWS the arena, so it is one self-recursive def with the
# FUEL FIRST and it threads `+O.Arena`. `wk_remint.put` is a leaf, so the self-call can be an
# ARGUMENT of a `case` arm and there is no mutual recursion -- which is the only way Bend can
# express `a.alu(op, f(b))` at all.
def wk_remint.go(fuel: Nat, isc: Bool, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  match fuel isc:
    case 0n _        : O.Found{ar, u}
    case 1n+p True{} : wk_remint.cast(ar, u, dt)
    case 1n+p False{}: wk_remint.put(wk_remint.go(p, wk_remint.isc(ar, O.Arena.src0(ar, u)), ar, O.Arena.src0(ar, u), dt), ar, u)

def wk_remint(fuel: Nat, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  wk_remint.go(fuel, wk_remint.isc(ar, u), ar, u, dt)

# THE PYTHON, in weak.py's order. Every rule body here is `(Folded, U32) ->
# Maybe<&2, Found>`: Python's `UOp -> UOp|None` arrives whole, as the arena the rewrite
# built AND the index it named. A rule GROWS the arena, so the fold the caller holds is
# stale the moment one fires; `wk_rewrite` re-folds ONCE, at the end, rather than each rule
# re-folding for itself.
#
# `(is there an answer, meet, result)` is a `Data` record and not a `Maybe`:
# `derived_dtypes`'s answer is read twice by `commit_srcs_at` (once for `bare`, once for
# the pair) and a `Maybe` is affine with no `+` spelling.

type Dts is Data:
  Dts{dts_some: Bool, meet: S.Dt, result: S.Dt}

def Dts.some(d: Dts) -> Bool:
  match d:
    case Dts{dts_some, meet, result}: dts_some

def Dts.meet(d: Dts) -> S.Dt:
  match d:
    case Dts{dts_some, meet, result}: meet

def Dts.result(d: Dts) -> S.Dt:
  match d:
    case Dts{dts_some, meet, result}: result

def derived_dtypes.hold(ok: Bool, meet: S.Dt, result: S.Dt) -> Dts:
  match ok:
    case True{}: Dts{True{}, meet, result}
    case False{}: Dts{False{}, S.void(), S.void()}

def derived_dtypes.put(ok: Bool, meet: S.Dt, result: Maybe<&2, S.Dt>) -> Dts:
  derived_dtypes.hold(ok, meet, Maybe.default(&2, S.Dt, result, S.void()))

# derived_dtypes -- weak.py:11-14.
#
#   if u.op not in GroupOp.Broadcastable or (meet:=promo_dtype(src)) in
#      dtypes.weaks or (result:=dtype_from_uop(u.op, src, u.arg)) in
#      dtypes.weaks: return None
#   return meet, result
#
# the concrete dtypes u commits its srcs at: the operands' meet and u's own derived dtype,
# None if either is weak.
# `GroupOp.Broadcastable` is `Binary | Ternary`, ops.bend:563 `GroupOp.broadcastable`.
# Both guards are `dtypes.weaks`; Python's `tuple[DType,DType]|None` is `Dts` with
# `dts_some`.
def derived_dtypes(+fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Dts:
  derived_dtypes.put(Bool.and(O.GroupOp.broadcastable(O.Arena.op(F.Folded.ar(fx), self)),
      Bool.not(dt_weak(wk_meet(fx, ss)))),
    wk_meet(fx, ss),
    wk_dtype_at(fx, self, wk_deriveds(fx, ss)))

# `UOp.const(dt.const(s.val))` -- the bare CONST with NO dtype, so no CAST on top.
def wk_bare_const(+fx: F.Folded, +s: U32, +dt: S.Dt) -> O.Found:
  O.UOp.const(F.Folded.ar(fx), wk_const_of(wk_dt_const(dt, wk_ccast.val(fx, s))))

# commit_srcs_at -- weak.py:16-20.
#
#   bare = derived_dtypes(u, u.src) is not None
#   src = tuple(s if s.dtype not in dtypes.weaks else
#               UOp.const(dt.const(s.val)) if bare and s.op is Ops.CONST else
#               s.ccast(dt) for s in u.src)
#   return None if (ret := u.replace(src=src)) is u else ret
#
# the root re-derives: a shift's dtype is its lhs's, so committing the lhs commits the
# node too. And the `bare and CONST` arm reads like a no-op because it very nearly IS one:
# `UOp.const(dt.const(s.val))` is `UOp.const` with NO dtype, so `dtype is None ->
# dtypes.from_py(val)` hands the src's own weak dtype BACK and the node hash-conses to `s`
# itself. It differs only when the weak src's VALUE changes class, and it rounds at the
# sealed dtypes, which `wk_blocked` refuses.

def commit_srcs_at.bare(isbare: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match isbare:
    case True{}: walk_step(w, wk_bare_const(fx, s, dt))
    case False{}: walk_step(w, wk_ccast(fx, s, dt))

def commit_srcs_at.weak(w: Walk, bare: Bool, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  commit_srcs_at.bare(Bool.and(bare, wk_is_weak_const(fx, s)), w, s, fx, dt)

def commit_srcs_at.pick(notweak: Bool, bare: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match notweak:
    case True{}: walk_keep(w, s)
    case False{}: commit_srcs_at.weak(w, bare, s, fx, dt)

def commit_srcs_at.on(w: Walk, bare: Bool, +fx: F.Folded, +s: U32, +dt: S.Dt) -> Walk:
  commit_srcs_at.pick(Bool.not(wk_is_weak(fx, s)), bare, w, s, fx, dt)

def commit_srcs_at.go(ss: List<&2, U32>, w: Walk, +fx: F.Folded, +dt: S.Dt, +bare: Bool) -> Walk:
  match ss:
    case Nil{}: w
    case s <> t: commit_srcs_at.go(t, commit_srcs_at.on(w, bare, fx, s, dt), fx, dt, bare)

# `None if (ret := u.replace(src=src)) is u else ret`
def commit_srcs_at.same(alike: Bool, w: Walk, hit: O.Found) -> Maybe<&2, O.Found>:
  match alike:
    case True{}: None{}
    case False{}: Some{hit}

def commit_srcs_at.fin(+w: Walk, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  commit_srcs_at.same(U32.is_eq(O.Found.i(replace_walk(w, fx, self)), self), w,
    replace_walk(w, fx, self))

def commit_srcs_at.gate(blocked: Bool, dts: Dts, +fx: F.Folded, +self: U32, +ss: List<&2, U32>, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match blocked:
    case True{}: None{}
    case False{}: commit_srcs_at.fin(commit_srcs_at.go(ss, walk_seed(F.Folded.ar(fx)), fx, dt, Dts.some(dts)), fx, self)

def commit_srcs_at.ans(+dts: Dts, +fx: F.Folded, +self: U32, +ss: List<&2, U32>, +dt: S.Dt) -> Maybe<&2, O.Found>:
  commit_srcs_at.gate(wk_blocked(fx, dt, Dts.some(dts), ss), dts, fx, self, ss, dt)

def commit_srcs_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  commit_srcs_at.ans(derived_dtypes(fx, self, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self), dt)

# commit_weak_srcs -- weak.py:22-24.
#
#   if not any(s.dtype in dtypes.weaks for s in u.src) or
#      (dt:=least_upper_dtype(*(s.dtype for s in u.src))) in dtypes.weaks: return None
#   return commit_srcs_at(u, dt)
#
# The meet is `promo_dtype(src)` verbatim (ops.py:120 is `least_upper_dtype` over the
# operand dtypes), so `wk_meet` is dtype.py:193 through `fold.bend`.

def commit_weak_srcs.bad(+fx: F.Folded, +ss: List<&2, U32>) -> Bool:
  Bool.or(Bool.not(wk_any_weak(fx, ss)), dt_weak(wk_meet(fx, ss)))

def commit_weak_srcs.ans(bad: Bool, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: commit_srcs_at(fx, self, wk_meet(fx, ss))

def commit_weak_srcs(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  commit_weak_srcs.ans(commit_weak_srcs.bad(fx, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self))

# uncast_const -- weak.py:80-87.
#
# drop the CAST off a committed const where the consumer re-derives it anyway, so
# bare-CONST rules keep matching. the drop must change nothing the consumer derives:
# neither the operands' meet nor the node's own dtype.
#
#   src = tuple(s.src[0] if s.op is Ops.CAST and s.dtype not in dtypes.weaks and
#               s.src[0].op is Ops.CONST and s.src[0].dtype in dtypes.weaks else s
#               for s in u.src)
#   if src == u.src or (dts:=derived_dtypes(u, src)) is None or
#      dts[0] != promo_dtype(u.src) or dts[1] is not u.dtype: return None
#   return u.replace(src=src)
#
# A PURE walk: dropping a CAST names `s.src[0]`, which is already in the arena, so no node
# is made and no accumulator is needed. And the predicate a weak CAST over a const is not
# a commit, it is still resolving -- so the drop is allowed.

def uncast_const.hit(+fx: F.Folded, +s: U32) -> Bool:
  Bool.and(Bool.and(wk_op_is(fx, s, O.OpsCAST{}), Bool.not(wk_is_weak(fx, s))),
    wk_is_weak_const(fx, wk_src0(fx, s)))

def uncast_const.put.go(hit: Bool, +fx: F.Folded, +s: U32) -> U32:
  match hit:
    case True{}: wk_src0(fx, s)
    case False{}: s

def uncast_const.put(+fx: F.Folded, +s: U32) -> U32:
  uncast_const.put.go(uncast_const.hit(fx, s), fx, s)

def uncast_const.walk.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: uncast_const.walk.go(fx, t, List.append(&2, U32, acc, [uncast_const.put(fx, s)]))

def uncast_const.walk(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, U32>:
  uncast_const.walk.go(fx, ss, Nil{})

def uncast_const.reach(bad: Bool) -> Bool:
  bad

def uncast_const.bad(+src: List<&2, U32>, +ss: List<&2, U32>, +dts: Dts, +fx: F.Folded, +self: U32) -> Bool:
  uncast_const.reach(Bool.or(Bool.or(H.u32_list_eq(src, ss), Bool.not(Dts.some(dts))),
    Bool.or(Bool.not(wk_eq_dt(Dts.meet(dts), wk_meet(fx, ss))), Bool.not(wk_eq_dt(Dts.result(dts), wk_dt(fx, self))))))

def uncast_const.ans(bad: Bool, +src: List<&2, U32>, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: Some{wk_replace(fx, self, src)}

def uncast_const(+src: List<&2, U32>, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Maybe<&2, O.Found>:
  uncast_const.ans(uncast_const.bad(src, ss, derived_dtypes(fx, self, src), fx, self), src, fx, self)

def uncast_const_fx(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  uncast_const(uncast_const.walk(fx, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self))

# commit_weak_consts -- weak.py:7-8. The FIRST def in weak.py, and the only one whose
# caller (`cast_consts`, weak.py:94) is behind `_min_max`, so it has no caller in this
# port. It is here because it is a def in the Python and it is fully portable; a dead def
# in a mechanical port is the file's shape, not a leftover.
#
#   return u if dt is None else u.replace(src=tuple(s.ccast(dt) if
#     s.op is Ops.CONST and s.dtype in dtypes.weaks else s for s in u.src))
#
# the decomps and float emulation commit bare consts at a dtype another src already states.
# `dt:DType|None` is read once PER SRC and a `Maybe` is affine with no `+` spelling, so it
# travels as an `ODt`: a `Bool` plus the value, the same move fold.bend's `Sized` and
# spec.bend's `Pa` make.

type ODt is Data:
  ODt{od_some: Bool, od_dt: S.Dt}

def ODt.some(d: ODt) -> Bool:
  match d:
    case ODt{od_some, od_dt}: od_some

def ODt.dt(d: ODt) -> S.Dt:
  match d:
    case ODt{od_some, od_dt}: od_dt

def od_of.pick(m: Maybe<&1, S.Dt>) -> ODt:
  match m:
    case Some{d}: ODt{True{}, d}
    case None{}: ODt{False{}, S.void()}

def od_of(m: Maybe<&1, S.Dt>) -> ODt:
  od_of.pick(m)

def commit_weak_consts.pick(isconst_weak: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match isconst_weak:
    case True{}: walk_step(w, wk_ccast(fx, s, dt))
    case False{}: walk_keep(w, s)

def commit_weak_consts.on(w: Walk, +fx: F.Folded, +s: U32, +dt: S.Dt) -> Walk:
  commit_weak_consts.pick(Bool.and(wk_op_is(fx, s, O.OpsCONST{}), wk_is_weak(fx, s)), w, s, fx, dt)

def commit_weak_consts.go(ss: List<&2, U32>, w: Walk, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match ss:
    case Nil{}: w
    case s <> t: commit_weak_consts.go(t, commit_weak_consts.on(w, fx, s, dt), fx, dt)

# `u if dt is None else u.replace(src=...)`. The branch is on `dt is None` and the WALK
# IS INSIDE THE TRUE ARM, because Bend is STRICT: passing the walk as an argument would
# evaluate it on the identity arm too, grow the arena, and return the grown one here.
# `cwc_none_nodes` in the gate is the row that notices.
# Python returns a UOp on BOTH arms, and `u` is the node itself when `dt is None`, so
# the answer is `Found{ar, self}` there and the rewritten node otherwise. `Found` rather
# than a bare `Arena` because a caller that cannot see the new index cannot tell a
# rewrite from a no-op -- which is exactly what `cwc_b_single` needed.
def commit_weak_consts.walked(some: Bool, dt: ODt, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> O.Found:
  match some:
    case True{}: replace_walk(commit_weak_consts.go(ss, walk_seed(F.Folded.ar(fx)), fx, ODt.dt(dt)), fx, self)
    case False{}: O.Found{F.Folded.ar(fx), self}

# THE pm_commit_weak RULE 1 LAMBDA -- weak.py:37-38, the one rule here with no def of its
# own in the file (Python spells it as a lambda over a UPat):
#
#   lambda u: u.replace(src=(u.src[0], u.src[1].ccast(u.src[0].dtype), *u.src[2:]))
#
# NOTE the pattern is `src=(UPat(), UPat(dtype=dtypes.weaks), ...)`, so the pattern
# REQUIRES the src to be weak; the body then commits it at src[0]'s dtype, and a weak
# CONST src that is already there is the no-op Python's own hash-consing produces. The
# pattern's first src is a bare `UPat`, so `early_reject` is empty.

def wk_store_cast.bad.of(sealed: Bool, isconst: Bool) -> Bool:
  Bool.and(sealed, isconst)

# `ccast` on src[1] reaches `dt.const` only when src[1] IS a CONST; otherwise it is
# `cast`, which `wk_blocked` does not gate. `dt` is src[0]'s dtype.
def wk_store_cast.bad(+fx: F.Folded, +self: U32) -> Bool:
  wk_store_cast.bad.of(wk_sealed(wk_dt(fx, wk_src0(fx, self))), wk_op_is(fx, wk_src1(fx, self), O.OpsCONST{}))

def wk_store_cast.srcs(+fx: F.Folded, +self: U32, +dt: S.Dt, mid: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [wk_src0(fx, self)], [mid]),
    O.Arena.src_from(F.Folded.ar(fx), self, 2))

def wk_store_cast.hit(bad: Bool, +hit: O.Found, +fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: Some{replace_in(O.Found.ar(hit), self, wk_store_cast.srcs(fx, self, dt, O.Found.i(hit)))}

# `(u.src[0], u.src[1].ccast(u.src[0].dtype), *u.src[2:])`, interned in the arena
# `wk_ccast` grew and not in the fold's own.
def wk_store_cast.ans(bad: Bool, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.hit(bad, wk_ccast(fx, wk_src1(fx, self), wk_dt(fx, wk_src0(fx, self))),
    fx, self, wk_dt(fx, wk_src0(fx, self)))

def wk_store_cast(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.ans(wk_store_cast.bad(fx, self), fx, self)

# THE TABLES. Tag N is weak.py's own index in `pm_<name>`'s list, so a GAP is a BLOCKED
# RULE and not a renumbering. `ops` is the set `pdict` keys on and `rej` is
# `early_reject`, which ops.py:1609 reads as `if not rej.issubset(ler): continue` -- a
# NECESSARY CONDITION, so an empty set always passes. All three ported rules have a bare
# `UPat()` as the pattern's FIRST src or no src pattern at all, so every `rej` here is
# empty and none of the three is ever decided by the subset test: `rej_all_empty` counts
# them, and the mutation table records what flipping the test does.

# GroupOp.Broadcastable == GroupOp.Binary | GroupOp.Ternary
# (tinygrad/uop/__init__.py:110).
def OP_BC() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

# pm_commit_weak -- weak.py:35-41. THREE rules in Python; TWO here. It rides every round
# that can mint a weak const, and must reach fixpoint before pm_lower_weak below defaults
# one.
#
# no CONST arm: a concrete CAST over a weak CONST is already committed, minted that way by
# UOp.const
def wk_commit_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, OP_BC(),        Nil{}},   # 36  commit_weak_srcs
    O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]}  # 38  the STORE lambda
# TODO(p3) weak.py:40  pm_commit_weak rule 2 -- (UPat(Ops.CAST, src=(UPat(GroupOp.ALU, dtype=dtypes.weaks,
#   name="u"),), name="c"), cast_weak_srcs) -- `cast_weak_srcs` reads
#   `u.commit_dtype(dtypes.i32)` and `s.commit_dtype(dtypes.i32)`, which is
#   `commit_int(vmin, vmax)`, which is `UOp._min_max`. See the TODO on that def.

# _lower_weak_ops -- weak.py:45, PORTED. It is a MODULE CONSTANT and the only
# portable thing in this file's queue: `GroupOp.Binary | GroupOp.Unary | {WHERE,
# RANGE, STACK, SPECIAL}`. `ops.bend`'s `GroupOp.binary` has NINETEEN members,
# `GroupOp.unary` has SEVEN, and the four named extras are FOUR, so the set is
# THIRTY. It is written as a LIST because `GroupOp` is a `match` and a `match`
# cannot be or'd into another, and it is a COUNT in the gate because a set that is
# a subset test is invisible to any per-op boolean: a dropped op makes
# `lower_weak_node` skip a node and a spurious one makes it rewrite one.
def LOWER_OPS() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{},
   O.OpsNEG{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsRANGE{}, O.OpsSTACK{}, O.OpsSPECIAL{}]

# pm_uncast_const -- weak.py:89. ONE rule in Python; ONE here.
def wk_uncast_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, OP_BC(), Nil{}}]}   # 89

# THE DRIVER. A rule answers `Maybe<&2, Found>`, and `Found` is ops.bend's arena-and-index
# record, so Python's `UOp -> UOp|None` arrives whole. The engine, not this file, re-folds:
# a rule that fires has grown the arena, so `graph_rewrite` owns the loop that rebuilds it.
#
# `spec.bend` writes six scans, one per table, because its `try` names a dispatch; here the
# only per-table difference is WHICH of the two already-written dispatches a tag goes to,
# and a `Bool` selects between them. The two dispatches and the tables stay separate.
#
# `wk_keep` is first-wins, the same shape as ops.bend:4088 `pm_keep`: a `Some` accumulator
# keeps what it holds and discards a later hit.

def wk_keep.take(acc: Maybe<&2, O.Found>, v: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match acc:
    case Some{f}: Some{f}
    case None{}: v

def wk_keep(acc: Maybe<&2, O.Found>, v: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  wk_keep.take(acc, v)

# pm_commit_weak's dispatch. Tag 2 is weak.py:40 and is the `# TODO(p3)` above.
def wk_commit_dispatch.go(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match tag:
    case 0: commit_weak_srcs(fx, self)
    case 1: wk_store_cast(fx, self)
    case _: None{}

def wk_commit_dispatch(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  wk_commit_dispatch.go(tag, fx, self)

# pm_uncast_const's dispatch.
def wk_uncast_dispatch.go(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match tag:
    case 0: uncast_const_fx(fx, self)
    case _: None{}

def wk_uncast_dispatch(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  wk_uncast_dispatch.go(tag, fx, self)

def wk_pick(which: Bool, tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match which:
    case True{}: wk_commit_dispatch(tag, fx, self)
    case False{}: wk_uncast_dispatch(tag, fx, self)

def wk_fire(ok: Bool, which: Bool, +fx: F.Folded, +self: U32, tag: U32) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: wk_pick(which, tag, fx, self)
    case False{}: None{}

def wk_try(ts: O.PMEntrys, which: Bool, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> Maybe<&2, O.Found>:
  wk_fire(Bool.and(O.pm_claimed(O.PMEntry.ops(e), F.Folded.ar(fx), self),
    O.pm_early(ts, F.Folded.ar(fx), self, O.PMEntry.rej(e))), which, fx, self, O.PMEntry.tag(e))

def wk_scan(+ts: O.PMEntrys, +which: Bool, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>,
  acc: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match todo:
    case Nil{}: acc
    case e <> t: wk_scan(ts, which, fx, self, t, wk_keep(acc, wk_try(ts, which, fx, self, e)))

# `pm_<name>.rewrite`. `wk_ready` is Python's `None` for a node the fold could not answer,
# and it is HERE rather than in each rule so no rule repeats the check.
def pm_go(ready: Bool, m: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match ready:
    case True{}: m
    case False{}: None{}
