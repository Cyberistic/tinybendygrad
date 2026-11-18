# symbolic.bend -- tinygrad/uop/symbolic.py. The REWRITER: four rule tables, the
# THE INVENTORY, def by def, against upstream's 475 Python lines. The state column is a
#   #  PY      KIND                  STATE
#   1  16      fold  simplify_pow        PARTIAL  (the int arms; the half exponent needs
#                                            an F32<->I64 compare helpers.bend cannot
#                                            express)
#   2  23      fold  fold_bitcast        PORTED   (truncate reaches only the six dtypes
#                                            Bend can state -- see below)
#   3  29      fold  fold_const_alu      PORTED   (exec_alu over U32 and F32)
#   4  31      fold  _quotient_base      PORTED   (index arithmetic + pop_const)
#   5  43      fold  fold_add_divmod_recombine  MISSING. This line said PORTED and there is
#                                             NO `def fold_add_divmod_recombine`: the census
#                                             lists it MISSING and `symclosure-gate` counts it
#                                             among `bodies.absent`. MEASURED 2026-11-03.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F
import ./render.bend as R
import ./../dtype.bend as D
import ./weak.bend as W
import ./movement.bend as M
import ./../codegen/decomp/transcendental.bend as T

# THE PRELUDE. Everything symbolic.py GETS FROM ELSEWHERE, in dependency order,
# THE SHAPE OF A RULE, and it is the one thing to get right. A rule is TWO defs:
def sy_ar(x: F.Folded) -> O.Arena: F.Folded.ar(x)

def sy_tb(x: F.Folded) -> F.Table: F.Folded.t(x)

# `UOp.dtype` -- ops.py:246, which is `fold.bend`'s table read, so it is a `Maybe`
def sy_dt(+x: F.Folded, +u: U32) -> Maybe<&2, S.Dt>:
  F.fold.dt(sy_ar(x), sy_tb(x), u)

def sy_dt_of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# `UPat.dtype`'s default IS `dtypes.void` (ops.py:1486), so a node the fold does
# not answer has the dtype a pattern with no dtype constraint would match.
def sy_dt1(+x: F.Folded, +u: U32) -> S.Dt: sy_dt_of(sy_dt(x, u))

def sy_dt_is(+x: F.Folded, +u: U32, want: S.Dt) -> Bool: F.dt_is(x, u, want)

def sy_op(+x: F.Folded, +u: U32) -> O.Op: O.Arena.op(F.Folded.ar(x), u)

def sy_src(+x: F.Folded, +u: U32, n: U32) -> U32: O.Arena.src(F.Folded.ar(x), u, n)

def sy_src0(+x: F.Folded, +u: U32) -> U32: O.Arena.src(F.Folded.ar(x), u, 0)

def sy_src1(+x: F.Folded, +u: U32) -> U32: O.Arena.src(F.Folded.ar(x), u, 1)

def sy_src2(+x: F.Folded, +u: U32) -> U32: O.Arena.src(F.Folded.ar(x), u, 2)

def sy_srcs(+x: F.Folded, +u: U32) -> List<&2, U32>: O.Arena.srcs(F.Folded.ar(x), u)

def sy_nsrc(+x: F.Folded, +u: U32) -> U32: O.Arena.nsrc(F.Folded.ar(x), u)

def sy_arg(+x: F.Folded, +u: U32) -> O.Arg: O.Arena.arg(F.Folded.ar(x), u)

def sy_nsrc_is(+x: F.Folded, +u: U32, n: U32) -> Bool: U32.is_eq(sy_nsrc(x, u), n)

def sy_nsrc_ge(+x: F.Folded, +u: U32, n: U32) -> Bool: U32.is_ge(sy_nsrc(x, u), n)

# `if uop.op in (...)` -- a membership test in an op SET, and `O.op_in` is ops.bend's own,
# so it is written once here and not per rule.
def sy_op_in(+x: F.Folded, +u: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, sy_op(x, u))

def sy_src_op_in(+x: F.Folded, +u: U32, n: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, O.Arena.op(F.Folded.ar(x), sy_src(x, u, n)))

def sy_is_op(+x: F.Folded, +u: U32, want: O.Op) -> Bool: O.eq_op(sy_op(x, u), want)

# THE OP-AND-SRC-COUNT PREFIX, ONCE, FOR EVERY RULE THAT USES IT.
# MEASURED 2026-11-10: 49 of this file's 109 `sym_*.pat` defs have the EXACT body
def sy_pat_is(+x: F.Folded, +u: U32, want: O.Op, n: U32, rest: Bool) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, want), sy_nsrc_is(x, u, n)), rest)

def sy_pat_ge(+x: F.Folded, +u: U32, want: O.Op, n: U32, rest: Bool) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, want), sy_nsrc_ge(x, u, n)), rest)

def sy_src_is_op(+x: F.Folded, +u: U32, n: U32, want: O.Op) -> Bool:
  O.eq_op(O.Arena.op(F.Folded.ar(x), sy_src(x, u, n)), want)

# the two-scrutinee group tests, as op sets. `GroupOp.Unary - {CAST, BITCAST}` and
def OP_CASTS() -> List<&2, O.Op>: [O.OpsCAST{}, O.OpsBITCAST{}]
# `GroupOp.Unary` -- NINE ops, and `GroupOp.Unary|{Ops.CAST, Ops.BITCAST}` IS
def OP_UNARY() -> List<&2, O.Op>:
  [O.OpsCAST{}, O.OpsBITCAST{}, O.OpsNEG{}, O.OpsRECIP{}, O.OpsEXP2{},
   O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsTRUNC{}]

def OP_CMP() -> List<&2, O.Op>: [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}]

def OP_SELF() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsXOR{}, O.OpsOR{}]

def OP_SHIFTS() -> List<&2, O.Op>: [O.OpsSHL{}, O.OpsSHR{}]

# `GroupOp.ALU - {Ops.THREEFRY}` -- TWENTY-SEVEN ops, and it is the op set of `symbolic.py:158`,
def OP_BINARY() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsMAX{}, O.OpsMUL{},
   O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsXOR{}]

def OP_ALU_NT() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsLOG2{},
   O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{},
   O.OpsRECIP{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSUB{},
   O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}]

# `up if bool(x) else None` -- the shape of most of symbolic.py's rule bodies. A `match`
def sy_tri(b: Bool, v: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match b:
    case True{}: v
    case False{}: None{}

def sy_tri_u(b: Bool, v: U32) -> Maybe<&1, U32>:
  sy_tri(b, Some{v})

def sy_tri_f(b: Bool, v: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match b:
    case True{}: v
    case False{}: None{}

# THE VALUE OF A CONST NODE, and `val` is ops.py:257 -- it reads THROUGH a CAST,
def sy_val1(a: O.Arg, op: O.Op) -> Maybe<&2, O.Const>:
  match a op:
    case O.APy{v} O.OpsCONST{}: Some{v}
    case _ _: None{}

# `UOp.val`'s CAST arm is `return self.src[0].val` (ops.py:252-257), NOT the cast's own
def sy_val2(+x: F.Folded, +u: U32) -> Maybe<&2, O.Const>:
  +s = sy_src0(x, u)
  Bool.pick(Maybe<&2, O.Const>, Bool.and(sy_nsrc_is(x, u, 1), sy_is_op(x, s, O.OpsCONST{})),
    sy_val1(sy_arg(x, s), sy_op(x, s)), None{})

def sy_val3(+x: F.Folded, +u: U32, +c: U32) -> Maybe<&2, O.Const>:
  sy_val1(sy_arg(x, c), sy_op(x, c))

def sy_val.dispatch(op: O.Op, a: O.Arg, +x: F.Folded, +u: U32) -> Maybe<&2, O.Const>:
  match op:
    case O.OpsCONST{}: sy_val1(a, op)
    case O.OpsCAST{}: sy_val2(x, u)
    case _: None{}

def sy_val(+x: F.Folded, +u: U32) -> Maybe<&2, O.Const>:
  sy_val.dispatch(sy_op(x, u), sy_arg(x, u), x, u)

def sy_is_invalid.go(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CInvalid{}}: True{}
    case _ : False{}

# `UOp.is_invalid` -- ops.py:267, `self.op is Ops.CONST and self.val is Invalid`
def sy_is_invalid(+x: F.Folded, +u: U32) -> Bool: sy_is_invalid.go(sy_val(x, u))

def sy_is_const(+x: F.Folded, +u: U32) -> Bool: sy_is_op(x, u, O.OpsCONST{})

def sy_is_invalid_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_const(x, u), sy_is_invalid(x, u))

# `bool(v)` for a PyConst, which is what `if c.val` reads in symbolic.py:127-128
def sy_truthy.go(v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: False{}
    case O.CBool{b}: b
    case O.CInt{i}: Bool.not(Cmp.is_eq(H.i64_cmp(H.i64_of_i32(0), i)))
    case O.CFloat{f}: F32.is_ne(f, 0.0)

def sy_val_truthy.go(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{v}: sy_truthy.go(v)
    case None{}: False{}

def sy_val_truthy(+x: F.Folded, +u: U32) -> Bool: sy_val_truthy.go(sy_val(x, u))

# THE DEFAULT VALUE OF A `Maybe<&1, O.Const>`, used where a `Data` record cannot
def sy_maybe_c2(m: Maybe<&2, O.Const>) -> O.Const:
  match m:
    case Some{v}: v
    case None{}: O.CInt{H.i64_of_i32(0)}

def sy_maybe_c(m: Maybe<&1, O.Const>) -> O.Const:
  match m:
    case Some{v}: v
    case None{}: O.CInt{H.i64_of_i32(0)}

# THE I64 -> U32 BIT PATTERN, and back. `H.i64_of_i32` sign-extends, so for a
def i64_bits(i: H.I64) -> U32: H.lo32(i)

# `truncate` -- dtype.py:297, and the table is where `exec_alu` and `const_like`
def sy_wrap_u(v: O.Const, +mask: U32) -> U32:
  match v:
    case O.CInt{i}: U32.and(H.lo32(i), mask)
    case _: 0

def sy_wrap_s(+u: U32, +half: U32, +wide: U32) -> H.I64:
  H.i64_sub(H.i64_of_i32(u),
    Bool.pick(H.I64, U32.is_lt(u, half), H.i64_of_i32(0), H.i64_of_i32(wide)))

def sy_trunc(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  match dt:
    case S.Dt{0, 1, S.CBool{}, _}: Some{O.CBool{sy_truthy.go(v)}}
    case S.Dt{0, 800, S.CWeakInt{}, _}: Some{v}
    case S.Dt{9, 800, S.CWeakFloat{}, _}: Some{v}
    case S.Dt{5, 32, S.CSint{}, _}: Some{v}
    case S.Dt{6, 32, S.CUint{}, _}: Some{v}
    case S.Dt{14, 32, S.CFloat{}, _}: Some{v}
    # THE TABLE IN `tinygrad/dtype.py:293` HAS EVERY INT WIDTH -- `int8..uint64` are all
    case S.Dt{_, 8, S.CSint{}, _}: Some{O.CInt{sy_wrap_s(sy_wrap_u(v, 255), 128, 256)}}
    case S.Dt{_, 16, S.CSint{}, _}: Some{O.CInt{sy_wrap_s(sy_wrap_u(v, 65535), 32768, 65536)}}
    case S.Dt{_, 64, S.CSint{}, _}: Some{v}
    case S.Dt{_, 8, S.CUint{}, _}: Some{O.CInt{H.i64_of_hi_lo(0, sy_wrap_u(v, 255))}}
    case S.Dt{_, 16, S.CUint{}, _}: Some{O.CInt{H.i64_of_hi_lo(0, sy_wrap_u(v, 65535))}}
    case S.Dt{_, 64, S.CUint{}, _}: Some{v}
    case _: None{}

# THE DTYPE A CONST'S VALUE DERIVES, which is `fold.bend`'s `cconst_dt` and is
def sy_needs_cast(dt: S.Dt, v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: Bool.not(O.eq_dt(dt, S.boolean()))
    case O.CBool{b}: Bool.not(O.eq_dt(dt, S.boolean()))
    case O.CInt{i}: Bool.not(O.eq_dt(dt, S.weakint()))
    case O.CFloat{f}: Bool.not(O.eq_dt(dt, S.weakfloat()))

# THE UOP SUGAR, and this is where the operator-layer wall lands. What is missing
def sy_alu1(ar: O.Arena, op: O.Op, x: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x]))

def sy_alu2(ar: O.Arena, op: O.Op, x: U32, y: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x, y]))

def sy_alu3(ar: O.Arena, op: O.Op, x: U32, y: U32, z: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x, y, z]))

def sy_where(ar: O.Arena, c: U32, t: U32, f: U32) -> U32:
  sy_alu3(ar, O.OpsWHERE{}, c, t, f)

# `-x` -- mixin/elementwise.py:79 is `x * (-1)` for a non-bool, and the rule at
# symbolic.py:122 is written that way, so this is the MUL and not a NEG node.
def sy_neg(+ar: O.Arena, x: U32) -> U32:
  sy_alu2(ar, O.OpsMUL{}, x, O.Found.i(O.UOp.const(ar, O.CInt{H.i64_of_i32(U32.sub(0, 1))})))

# `x.logical_not()` -- mixin/elementwise.py:57 AT THE PIN `f5ac54685074`, WHICH IS
def sy_logical_not(+ar: O.Arena, x: U32) -> U32:
  sy_alu2(ar, O.OpsCMPEQ{}, x, O.Found.i(O.UOp.const(ar, O.CBool{False{}})))

# `x != 0` -- THE TWO HALVES OF THE SAME RULE, AND BOTH ARE THE
# UPSTREAM's `__ne__` AT THE PIN IS `self.ne(x)` (`mixin/elementwise.py:
# 338-339`), AND `ne` IS `self.eq(x).logical_not()` (`:332-333`), AND `eq`
# IS `_binop(Ops.CMPEQ, x, False)` (`:335-336`) -- SO `x != 0` IS
# `logical_not(CMPEQ(x, 0))`, TWO NODES, AND NOT A CMPNE.
def sy_ne0(+ar: O.Arena, x: U32) -> U32:
  +eq = sy_alu2(ar, O.OpsCMPEQ{}, x, O.Found.i(O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})))
  sy_logical_not(ar, eq)

# `x.cast(dt)` -- mixin/dtype.py:19, `self if self.dtype == dt else
def sy_cast(ar: O.Arena, x: U32, dt: S.Dt) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{dt}, O.TNone{}))

def sy_bitcast(ar: O.Arena, x: U32, dt: S.Dt) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsBITCAST{}, [x], O.ADt{dt}, O.TNone{}))

# `x.trunc()` -- mixin/elementwise.py:470, a `TRUNC` node on the one src.
def sy_trunc_uop(ar: O.Arena, x: U32) -> U32:
  sy_alu1(ar, O.OpsTRUNC{}, x)

# `x.replace(src=...)` -- ops.py:252, with the op/arg/tag forwarded. Python's
def sy_replace_src(+ar: O.Arena, +u: U32, src: List<&2, U32>) -> U32:
  O.Found.i(O.UOp.new(ar, O.Arena.op(ar, u), src, O.Arena.arg(ar, u), O.Arena.tag(ar, u)))

# `UOp(Ops.NOOP)` -- symbolic.py:99, :459 and the fold at :454.
def sy_noop(ar: O.Arena) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{}))

# `UOp.const(b, dtype)` -- ops.py:631. `ops.bend`'s own `UOp.const` interns the
def sy_const_cast(needs: Bool, +ar: O.Arena, dt: S.Dt, c: U32) -> U32:
  match needs:
    case True{}: sy_cast(ar, c, dt)
    case False{}: c

def sy_const_put(+dt: S.Dt, +v: O.Const, +ar: O.Arena) -> U32:
  sy_const_cast(sy_needs_cast(dt, v), ar, dt, O.Found.i(O.UOp.const(ar, v)))

def sy_const_of(tv: Maybe<&1, O.Const>, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, U32>:
  match tv:
    case Some{v}: Some{sy_const_put(dt, v, ar)}
    case None{}: None{}

def sy_const(+ar: O.Arena, +dt: S.Dt, v: O.Const) -> Maybe<&1, U32>:
  sy_const_of(sy_trunc(dt, v), ar, dt)

# `UOp.const_like(b, dtype=None)` -- ops.py:603. The `_mop` half
def sy_const_like(+x: F.Folded, +u: U32, v: O.Const) -> Maybe<&1, U32>:
  sy_const(sy_ar(x), sy_dt1(x, u), v)

def sy_const_at(+x: F.Folded, +u: U32, dt: S.Dt, v: O.Const) -> Maybe<&1, U32>:
  sy_const(sy_ar(x), dt, v)

# `UOp.cconst(b, dtype)` -- ops.py:646, "a forced CAST for bool: .cast(bool)
def sy_cc_all.of(ok: Bool, +i: U32) -> Maybe<&1, U32>:
  match ok:
    case True{} : Some{i}
    case False{}: None{}

def sy_cc_all(+i: U32, +ar: O.Arena) -> Maybe<&1, U32>:
  sy_cc_all.of(U32.is_lt(i, O.Arena.next(ar)), i)

def sy_cc_build.go(ok: Bool, +f: O.Found, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, U32>:
  match ok:
    case False{}: None{}
    case True{} : sy_cc_all(sy_cast(O.Found.ar(f), O.Found.i(f), dt), ar)

def sy_cc_build(+f: O.Found, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, U32>:
  sy_cc_build.go(U32.is_lt(O.Found.i(f), O.Arena.next(ar)), f, ar, dt)

def sy_cconst_cast(tv: Maybe<&1, O.Const>, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, U32>:
  match tv:
    case Some{w}: sy_cc_build(O.UOp.const(ar, w), ar, dt)
    case None{}: None{}

def sy_cconst(+ar: O.Arena, +dt: S.Dt, v: O.Const) -> Maybe<&1, U32>:
  sy_cconst_cast(sy_trunc(dt, v), ar, dt)

# `UOp.ccast(dtype)` -- ops.py:640, `UOp.const(self.val, dtype) if self.op is
def sy_ccast.dispatch(is_const: Bool, v: Maybe<&2, O.Const>, ar: O.Arena, u: U32, dt: S.Dt) -> Maybe<&1, U32>:
  match is_const:
    case True{}: sy_cconst(ar, dt, sy_maybe_c2(v))
    case False{}: Some{sy_cast(ar, u, dt)}

def sy_ccast(+x: F.Folded, +u: U32, dt: S.Dt) -> Maybe<&1, U32>:
  sy_ccast.dispatch(sy_is_const(x, u), sy_val(x, u), sy_ar(x), u, dt)

# `UOp.usum(*us)` / `UOp.uprod(*us)` -- mixin/elementwise.py:40-41:
def sy_usum.op(orb: Bool) -> O.Op:
  match orb:
    case True{}: O.OpsOR{}
    case _: O.OpsADD{}

def sy_usum.go(t: List<&2, U32>, +ar: O.Arena, base: U32, +orb: Bool) -> U32:
  match t:
    case Nil{}: base
    case u <> r: sy_usum.go(r, ar, sy_alu2(ar, sy_usum.op(orb), base, u), orb)

def sy_usum(+ar: O.Arena, +base: U32, us: List<&2, U32>) -> U32:
  sy_usum.go(us, ar, base, F.dt_is(F.folded(ar), base, S.boolean()))

# `UOp.split_uop` -- ops.py:685,
type SplitSt is Data:
  SplitSt{todo: List<&2, U32>, acc: List<&2, U32>}

def SplitSt.todo(s: SplitSt) -> List<&2, U32>:
  match s:
    case SplitSt{todo, acc}: todo

def SplitSt.acc(s: SplitSt) -> List<&2, U32>:
  match s:
    case SplitSt{todo, acc}: acc

# one step: is `h` itself a `sep`? then its srcs join the worklist, else `h` is a term
# and joins the answer.
def sy_split.step(hit: Bool, ar: O.Arena, h: U32) -> SplitSt:
  match hit:
    case True{}: SplitSt{O.Arena.srcs(ar, h), Nil{}}
    case False{}: SplitSt{Nil{}, [h]}

def sy_split.at(+ar: O.Arena, +h: U32, want: O.Op) -> SplitSt:
  sy_split.step(O.eq_op(O.Arena.op(ar, h), want), ar, h)

def sy_split.done(acc: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, acc)

def sy_split.go(fuel: Nat, +ar: O.Arena, todo: List<&2, U32>, +want: O.Op, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel todo:
    case 0n Nil{}: sy_split.done(acc)
    case 0n _ <> _: sy_split.done(acc)
    case 1n+p Nil{}: sy_split.done(acc)
    case 1n+p h <> t:
      +st = sy_split.at(ar, h, want)
      sy_split.go(p, ar, List.append(&2, U32, t, SplitSt.todo(st)), want,
        List.append(&2, U32, acc, SplitSt.acc(st)))

def sy_split(+ar: O.Arena, u: U32, want: O.Op) -> List<&2, U32>:
  sy_split.go(U32.to_nat(O.Arena.next(ar)), ar, [u], want, Nil{})

# `identity_element` -- ops.py:61, `dt.const({ADD:0, MUL:1, MAX:dt.min}[op])`. It
def sy_ident_min.pick(m: Maybe<&2, U32>) -> Maybe<&1, O.Const>:
  match m:
    case Some{v}: Some{O.CInt{H.i64_of_i32(v)}}
    case None{}: None{}

def sy_ident_min(dt: S.Dt) -> Maybe<&1, O.Const>:
  sy_ident_min.pick(S.Dt.min(dt))

def sy_ident.go(op: O.Op, dt: S.Dt) -> Maybe<&1, O.Const>:
  match op:
    case O.OpsADD{}: Some{O.CInt{H.i64_of_i32(0)}}
    case O.OpsMUL{}: Some{O.CInt{H.i64_of_i32(1)}}
    case O.OpsMAX{}: sy_ident_min(dt)
    case _: None{}

def sy_ident(op: O.Op, dt: S.Dt) -> Maybe<&1, O.Const>:
  sy_ident.go(op, dt)

# `UOp.pop_const(op=Ops.ADD)` -- ops.py:1080,
type Popped is Data:
  Popped{t: U32, v: O.Const}

def sy_pop.second.go(m: Maybe<&1, O.Const>) -> Maybe<&1, Popped>:
  match m:
    case Some{v}: Some{Popped{0, v}}
    case None{}: None{}

def sy_pop.second(op: O.Op, dt: S.Dt) -> Maybe<&1, Popped>:
  sy_pop.second.go(sy_ident(op, dt))

# the taken half: `self.src[1].val`, and `val` reads THROUGH a CAST, so the popped value is
# the value of the committed const rather than of a pair.
def sy_pop.first.go(m: Maybe<&2, O.Const>, t: U32) -> Maybe<&1, Popped>:
  match m:
    case Some{v}: Some{Popped{t, v}}
    case None{}: None{}

def sy_pop.first(+x: F.Folded, +u: U32) -> Maybe<&1, Popped>:
  sy_pop.first.go(sy_val(x, sy_src1(x, u)), sy_src0(x, u))

def sy_pop.dispatch(hit: Bool, +x: F.Folded, +u: U32, want: O.Op, dt: S.Dt) -> Maybe<&1, Popped>:
  match hit:
    case True{}: sy_pop.first(x, u)
    case False{}: sy_pop.second(want, dt)

def sy_pop(+x: F.Folded, +u: U32, +want: O.Op) -> Maybe<&1, Popped>:
  sy_pop.dispatch(Bool.and(sy_is_op(x, u, want), sy_is_const(x, sy_src1(x, u))), x, u, want, sy_dt1(x, u))

def Popped.t(p: Popped) -> U32:
  match p:
    case Popped{t, v}: t

def Popped.v(p: Popped) -> O.Const:
  match p:
    case Popped{t, v}: v

# `exec_alu` -- ops.py:1433, and the answer is two lanes, `U32` and `F32`, with

# THE INVALID POISON. ops.py:1432 is
def sy_is_invalid_c(v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: True{}
    case _ : False{}

# `const_arg` -- symbolic.py:69-70,
def sy_const_arg.of(is_stack: Bool, m: Maybe<&2, O.Const>) -> Maybe<&2, O.Const>:
  match is_stack:
    case True{}: None{}
    case False{}: m

def sy_const_arg.go(fuel: Nat, is_stack: Bool, m: Maybe<&2, O.Const>) -> Maybe<&2, O.Const>:
  match fuel:
    case 0n: None{}
    case 1n+p: sy_const_arg.of(is_stack, m)

def sy_const_arg(+x: F.Folded, +u: U32) -> Maybe<&2, O.Const>:
  sy_const_arg.go(U32.to_nat(O.Arena.next(sy_ar(x))), sy_is_op(x, u, O.OpsSTACK{}), sy_val(x, u))

# THE TWO LANES, and each is a `Data` record because Bend has no tuple and no
type I3 is Data:
  I3{n: U32, a: U32, b: U32, c: U32}

def I3.a(+o: I3) -> U32:
  match o:
    case I3{n, a, b, c}: a

type F3 is Data:
  F3{n: U32, a: F32, b: F32, c: F32}

# THE INT LANE. `U32.add/sub/mul` wrap mod 2^32, which IS int32 and uint32 wrap;
def i32_lt(uns: Bool, +x: U32, +y: U32) -> Bool:
  Bool.pick(Bool, uns, U32.is_lt(x, y), Cmp.is_lt(H.i64_cmp(H.i64_of_i32(x), H.i64_of_i32(y))))

# the max, and it is not the min. The float lane's `f32_max` (below) is
# `Bool.pick(F32, F32.is_lt(x, y), y, x)` -- "y if x < y else x", which is max.
# this one had its comparison's operands the other way round, so it answered
# "y if y < x else x", WHICH IS min(x, y). MEASURED 2026-10-25 (the executor's
def i32_max(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, i32_lt(uns, x, y), y, x)

# `H.floordiv_i32` / `H.floormod_i32` ARE NOT USED because they are WRONG for a
def i32_fdiv.step(+q: U32, +r: U32, +y: U32) -> U32:
  Bool.pick(U32, Bool.and(Bool.not(U32.is_zero(r)), Bool.xor(H.i32_is_neg(r), H.i32_is_neg(y))), U32.sub(q, 1), q)

def i32_fdiv.go(zero: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, zero, 0, i32_fdiv.step(H.cdiv_i32_go(x, y), U32.sub(x, U32.mul(H.cdiv_i32_go(x, y), y)), y))

def i32_fdiv(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, uns, H.floordiv_u32(x, y), i32_fdiv.go(U32.is_zero(y), x, y))

def i32_fmod(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, uns, H.floormod_u32(x, y), U32.sub(x, U32.mul(i32_fdiv.go(U32.is_zero(y), x, y), y)))

def i32_cdiv(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, uns, H.cdiv_u32(x, y), H.cdiv_i32_go(x, y))

def i32_cmod(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, uns, H.cmod_u32(x, y), H.cmod_i32(x, y))

# `operator.rshift` is an ARITHMETIC shift for a negative int and Bend's two
def i32_shr(uns: Bool, +x: U32, +n: U32) -> U32:
  Bool.pick(U32, uns, U32.shrn(x, U32.to_nat(n)), H.asr(x, U32.to_nat(n)))

# `operator.lshift`, and THIS ONE DOES NOT FIT. Python's ints are mathematical,
# so `x << 40` is a 41-bit number and this lane has nowhere to put it. The answer
# is `None{}` rather than a wrapped one, because a wrapped answer is a WRONG
def i32_shl.big(big: Bool) -> Maybe<&1, U32>:
  match big:
    case True{}: None{}
    case False{}: Some{0}

def i32_shl(+big: Bool, x: U32, n: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, big, i32_shl.big(big), Some{U32.shln(x, U32.to_nat(n))})

# THE ANSWER OF THE INTEGER LANE. `O.Const` and its `CInt` live in `O`, so a
def i32_const.of(i: H.I64) -> O.Const: O.CInt{i}

def i32_const(v: U32) -> O.Const: i32_const.of(H.i64_of_i32(v))

# THE ZERO-EXTENSION, and it is the one that matters: `H.i64_of_hi_lo(0, v)` is a
def i64_of_c(uns: Bool, +v: U32) -> O.Const:
  Bool.pick(O.Const, uns, i32_const.of(H.i64_of_hi_lo(0, v)), i32_const(v))

# A COMPARISON answers a Python `bool`, and with `truncate_output=False` that
def sy_bool_c(b: Bool) -> O.Const: O.CBool{b}

def sy_trunc_i(uns: Bool, m: Maybe<&1, U32>) -> Maybe<&1, O.Const>:
  match m:
    case Some{v}: Some{i64_of_c(uns, v)}
    case None{}: None{}

def exec_alu_i32.bit(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsAND{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.and(a, b))}
    case O.OpsOR{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.or(a, b))}
    case O.OpsXOR{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.xor(a, b))}
    case O.OpsSHL{} I3{2, +a, +b, _}: sy_trunc_i(uns, i32_shl(U32.is_ge(b, 32), a, b))
    case O.OpsSHR{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_shr(uns, a, b))}
    case _ _: None{}

# `python_alu`'s COMPARISONS (ops.py:1416-1417) are `operator.lt`, `operator.eq` and
def exec_alu_i32.cmp(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsCMPLT{} I3{2, +a, +b, _}: Some{sy_bool_c(i32_lt(uns, a, b))}
    case O.OpsCMPEQ{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}
    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_ne(a, b))}
    case _ _: None{}

def exec_alu_i32.div(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsDIV{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_fdiv(uns, a, b))}
    case O.OpsMOD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_fmod(uns, a, b))}
    case O.OpsTRUNCDIV{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_cdiv(uns, a, b))}
    case O.OpsTRUNCMOD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_cmod(uns, a, b))}
    case _ _: None{}

def exec_alu_i32.arith(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsADD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.add(a, b))}
    case O.OpsSUB{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.sub(a, b))}
    case O.OpsMUL{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.mul(a, b))}
    case O.OpsMAX{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_max(uns, a, b))}
    case O.OpsMULACC{} I3{3, +a, +b, +c}: Some{i64_of_c(uns, U32.add(U32.mul(a, b), c))}
    case _ _: None{}

# `operator.neg` is `U32.sub(0, a)`, which is why NEG is in the integer table at all
# rather than being a float-only entry.
def exec_alu_i32.neg(+uns: Bool, +o: I3) -> Maybe<&1, O.Const>:
  match o:
    case I3{1, +a, _, _}: Some{i64_of_c(uns, H.i32_neg(a))}
    case _: None{}

def exec_alu_i32.where(+uns: Bool, +o: I3) -> Maybe<&1, O.Const>:
  match o:
    case I3{3, +a, +b, +c}: Some{i64_of_c(uns, Bool.pick(U32, U32.is_zero(a), c, b))}
    case _: None{}

def op_is_div(op: O.Op) -> Bool:
  O.op_in([O.OpsDIV{}, O.OpsMOD{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}], op)

def op_is_bit(op: O.Op) -> Bool:
  O.op_in([O.OpsAND{}, O.OpsOR{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}], op)

# THE INTEGER LADDER, and it is a chain of `Bool.pick` rather than a `match` on
def exec_alu_i32(+uns: Bool, +op: O.Op, +o: I3) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsNEG{}), exec_alu_i32.neg(uns, o),
    Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsWHERE{}), exec_alu_i32.where(uns, o),
      Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsTRUNC{}), Some{i64_of_c(uns, I3.a(o))},
        Bool.pick(Maybe<&1, O.Const>, O.GroupOp.comparison(op), exec_alu_i32.cmp(uns, op, o),
          Bool.pick(Maybe<&1, O.Const>, op_is_div(op), exec_alu_i32.div(uns, op, o),
            Bool.pick(Maybe<&1, O.Const>, op_is_bit(op), exec_alu_i32.bit(uns, op, o),
              exec_alu_i32.arith(uns, op, o)))))))

# THE FLOAT LANE, over `F32`. F32 arithmetic is a native intrinsic in Bend, so
def f32_inf() -> F32: F32.div(1.0, 0.0)

def f32_nan() -> F32: F32.sub(f32_inf(), f32_inf())

# `1/x if x != 0 else math.copysign(math.inf, x)` IS `F32.div(1.0, x)`: IEEE gives
def f32_recip(x: F32) -> F32: F32.div(1.0, x)

# `math.log2(x) if x > 0 else -inf if x == 0 else nan`, kept in Python's reading
def f32_log2(+x: F32) -> F32:
  Bool.pick(F32, F32.is_gt(x, 0.0), F32.log2(x),
    Bool.pick(F32, F32.is_eq(x, 0.0), F32.neg(f32_inf()), f32_nan()))

# `safe_exp2(x) = 2  x`, and the `except OverflowError: math.inf` is what
# `F32.pow` already returns.
def f32_exp2(x: F32) -> F32: F32.pow(2.0, x)

# `safe_pow`, and THE DIVERGENCE: Python raises ValueError for a negative base with
def f32_pow(x: F32, y: F32) -> F32: F32.pow(x, y)

def f32_sin(+x: F32) -> F32: Bool.pick(F32, H.f32_is_finite(x), F32.sin(x), f32_nan())

def f32_trunc(+x: F32) -> F32: Bool.pick(F32, H.f32_is_finite(x), F32.trunc(x), x)

# `max(a, b)` on Python floats is `a if a > b else b`, and `math.trunc` toward zero is
def f32_max(+x: F32, +y: F32) -> F32: Bool.pick(F32, F32.is_lt(x, y), y, x)

def f32_fdiv(+x: F32, +y: F32) -> F32: F32.floor(F32.div(x, y))

def f32_fmod(+x: F32, +y: F32) -> F32: F32.sub(x, F32.mul(F32.floor(F32.div(x, y)), y))

def f32_cdiv(x: F32, y: F32) -> F32: F32.trunc(F32.div(x, y))

def f32_cmod(+x: F32, +y: F32) -> F32: F32.sub(x, F32.mul(f32_cdiv(x, y), y))

def exec_alu_f32.unary(op: O.Op, a: F32) -> Maybe<&1, O.Const>:
  match op:
    case O.OpsLOG2{}: Some{O.CFloat{f32_log2(a)}}
    case O.OpsEXP2{}: Some{O.CFloat{f32_exp2(a)}}
    case O.OpsSQRT{}: Some{O.CFloat{F32.sqrt(a)}}
    case O.OpsRECIP{}: Some{O.CFloat{f32_recip(a)}}
    case O.OpsSIN{}: Some{O.CFloat{f32_sin(a)}}
    case O.OpsTRUNC{}: Some{O.CFloat{f32_trunc(a)}}
    case _: None{}

def exec_alu_f32.cmp(op: O.Op, a: F32, b: F32) -> Maybe<&1, O.Const>:
  match op:
    case O.OpsCMPLT{}: Some{sy_bool_c(F32.is_lt(a, b))}
    case O.OpsCMPEQ{}: Some{sy_bool_c(F32.is_eq(a, b))}
    case O.OpsCMPNE{}: Some{sy_bool_c(F32.is_ne(a, b))}
    case _: None{}

def exec_alu_f32.arith(op: O.Op, a: F32, b: F32) -> Maybe<&1, O.Const>:
  match op:
    case O.OpsADD{}: Some{O.CFloat{F32.add(a, b)}}
    case O.OpsSUB{}: Some{O.CFloat{F32.sub(a, b)}}
    case O.OpsMUL{}: Some{O.CFloat{F32.mul(a, b)}}
    case O.OpsMAX{}: Some{O.CFloat{f32_max(a, b)}}
    case O.OpsDIV{}: Some{O.CFloat{f32_fdiv(a, b)}}
    case O.OpsMOD{}: Some{O.CFloat{f32_fmod(a, b)}}
    case O.OpsTRUNCDIV{}: Some{O.CFloat{f32_cdiv(a, b)}}
    case O.OpsTRUNCMOD{}: Some{O.CFloat{f32_cmod(a, b)}}
    case O.OpsPOW{}: Some{O.CFloat{f32_pow(a, b)}}
    case _ : exec_alu_f32.cmp(op, a, b)

# `MULACC` is `(x*y)+z` and `WHERE` is `y if x else z`; only WHERE tests its
# the arms were the other way round. `Bool.pick(T, cond, then, else)` picks
# `then` WHEN `cond` HOLDS, SO `y if x else z` IS `pick(cond, y, z)` -- AND THIS
# LINE SAID `pick(cond, c, b)`, WHICH IS `z if x else y`. MEASURED 2026-10-26:
def f32_where(cond: Bool, b: F32, c: F32) -> F32: Bool.pick(F32, cond, b, c)

def exec_alu_f32.tern(op: O.Op, +a: F32, +b: F32, +c: F32) -> Maybe<&1, O.Const>:
  match op:
    case O.OpsMULACC{}: Some{O.CFloat{F32.add(F32.mul(a, b), c)}}
    case O.OpsWHERE{}: Some{O.CFloat{f32_where(F32.is_ne(a, 0.0), b, c)}}
    case _: None{}

def exec_alu_f32(+op: O.Op, +n: U32, +a: F32, +b: F32, c: F32) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, U32.is_eq(n, 1),
    Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsNEG{}), Some{O.CFloat{F32.neg(a)}},
      exec_alu_f32.unary(op, a)),
    Bool.pick(Maybe<&1, O.Const>, U32.is_eq(n, 3),
      exec_alu_f32.tern(op, a, b, c),
      exec_alu_f32.arith(op, a, b)))

# THE LANE SELECTOR. `python_alu[op](*operands)` is a PYTHON-NUMBER operation, so
def i64_big(+i: H.I64) -> Bool:
  Bool.or(H.i64_is_neg(i), Cmp.is_ge(H.i64_cmp(i, H.i64_of_i32(2147483647))))

# the inverted end, and it is this one. `i64_big` answers "does not fit" and
# `exec_alu.of2` reads `ci_fits` as "fits", which is what ops.py:1432's lane choice
def i64_fits_i32(i: H.I64) -> Bool: Bool.not(i64_big(i))

def ci_bits(v: O.Const) -> U32:
  match v:
    case O.CInt{i}: H.lo32(i)
    case O.CBool{b}: Bool.to_u32(b)
    case _ : 0

def ci_fits(v: O.Const) -> Bool:
  match v:
    case O.CInt{i}: i64_fits_i32(i)
    case O.CBool{b}: True{}
    case _ : False{}

def cf_of_i(bad: Bool, i: H.I64) -> Maybe<&1, F32>:
  match bad:
    case True{}: None{}
    case False{}: Some{U32.to_f32(H.lo32(i))}

def cf_of_i.go(+i: H.I64) -> Maybe<&1, F32>:
  cf_of_i(i64_big(i), i)

def cf(v: O.Const) -> Maybe<&1, F32>:
  match v:
    case O.CFloat{f}: Some{f}
    case O.CBool{b}: Some{U32.to_f32(Bool.to_u32(b))}
    case O.CInt{i}: cf_of_i.go(i)
    case _: None{}

def sy_maybe_f(m: Maybe<&1, F32>) -> F32:
  match m:
    case Some{v}: v
    case None{}: 0.0

# THE TRUNCATE LINE. ops.py:1434-1435 is
def exec_alu.trunc(trunc_it: Bool, dt: S.Dt, m: Maybe<&1, O.Const>) -> Maybe<&1, O.Const>:
  match trunc_it:
    case True{}: sy_trunc(dt, sy_maybe_c(m))
    case False{}: m

# `exec_alu` -- ops.py:1433, the scalar spine in Python's order, one def per
def exec_alu.poison1(op: O.Op, a: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), sy_is_invalid_c(a))

def exec_alu.poison2(op: O.Op, a: O.Const, b: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), Bool.or(sy_is_invalid_c(a), sy_is_invalid_c(b)))

def exec_alu.poison3(op: O.Op, a: O.Const, b: O.Const, c: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), Bool.or(sy_is_invalid_c(a), Bool.or(sy_is_invalid_c(b), sy_is_invalid_c(c))))

# the three facts one operand carries, as a `Data` record because a `Maybe<F32>` is
type Opr is Data:
  Opr{fits: Bool, bits: U32, f: F32}

def opr(+v: O.Const) -> Opr: Opr{ci_fits(v), ci_bits(v), sy_maybe_f(cf(v))}

def Opr.fits(o: Opr) -> Bool:
  match o:
    case Opr{fits, bits, f}: fits

def Opr.bits(o: Opr) -> U32:
  match o:
    case Opr{fits, bits, f}: bits

def Opr.f(o: Opr) -> F32:
  match o:
    case Opr{fits, bits, f}: f

def opr_f(v: O.Const) -> Bool: Opr.fits(opr(v))

# THE LANE CHOICE, and it is Python's `if ... else` in the order ops.py:1432-1435
# two lanes are still dead, both measured, and neither moves a row.
def exec_alu.pick(poison: Bool, ints: Bool, mi: Maybe<&1, O.Const>, fs: Bool, mf: Maybe<&1, O.Const>) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, poison, Some{O.CInvalid{}},
    Bool.pick(Maybe<&1, O.Const>, ints, mi,
      Bool.pick(Maybe<&1, O.Const>, fs, mf, None{})))

def exec_alu.of1(poison: Bool, +op: O.Op, dt: S.Dt, +a: O.Const) -> Maybe<&1, O.Const>:
  exec_alu.pick(poison, ci_fits(a), exec_alu_i32(S.Dt.is_unsigned(dt), op, I3{1, ci_bits(a), 0, 0}),
    opr_f(a), exec_alu_f32(op, 1, Opr.f(opr(a)), 0.0, 0.0))

def exec_alu.of2(poison: Bool, +op: O.Op, dt: S.Dt, +a: O.Const, +b: O.Const) -> Maybe<&1, O.Const>:
  exec_alu.pick(poison, Bool.and(ci_fits(a), ci_fits(b)),
    exec_alu_i32(S.Dt.is_unsigned(dt), op, I3{2, ci_bits(a), ci_bits(b), 0}),
    Bool.and(opr_f(a), opr_f(b)),
    exec_alu_f32(op, 2, Opr.f(opr(a)), Opr.f(opr(b)), 0.0))

def exec_alu.of3(poison: Bool, +op: O.Op, dt: S.Dt, +a: O.Const, +b: O.Const, +c: O.Const) -> Maybe<&1, O.Const>:
  exec_alu.pick(poison, Bool.and(ci_fits(a), Bool.and(ci_fits(b), ci_fits(c))),
    exec_alu_i32(S.Dt.is_unsigned(dt), op, I3{3, ci_bits(a), ci_bits(b), ci_bits(c)}),
    Bool.and(opr_f(a), Bool.and(opr_f(b), opr_f(c))),
    exec_alu_f32(op, 3, Opr.f(opr(a)), Opr.f(opr(b)), Opr.f(opr(c))))

def exec_alu1(+op: O.Op, +dt: S.Dt, +a: O.Const, trunc_it: Bool) -> Maybe<&1, O.Const>:
  exec_alu.trunc(trunc_it, dt, exec_alu.of1(exec_alu.poison1(op, a), op, dt, a))

def exec_alu2(+op: O.Op, +dt: S.Dt, +a: O.Const, +b: O.Const, trunc_it: Bool) -> Maybe<&1, O.Const>:
  exec_alu.trunc(trunc_it, dt, exec_alu.of2(exec_alu.poison2(op, a, b), op, dt, a, b))

def exec_alu3(+op: O.Op, +dt: S.Dt, +a: O.Const, +b: O.Const, +c: O.Const, trunc_it: Bool) -> Maybe<&1, O.Const>:
  exec_alu.trunc(trunc_it, dt, exec_alu.of3(exec_alu.poison3(op, a, b, c), op, dt, a, b, c))

#  phase 1 of symbolic used to live in ops, it's the most generic folding
# THE PATTERN VOCABULARY. Each of these is ONE `UPat` test from ops.py, and the
# rules below are written against them so a rule's TEXT is the rule and the
# vocabulary is the pattern. The first six are the `invalid_*` patterns
# symbolic.py:63-68 spells out. Invalid poisons the value: ops move inside the gate
def p_invalid(+x: F.Folded, +u: U32) -> Bool: sy_is_invalid_const(x, u)

# `invalid_gate` -- `UPat.var("cond").where(UPat.var("x"), invalid_pat)`, which is
# `WHERE(cond, x, CONST(Invalid))` and three srcs.
def p_gate(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), sy_is_invalid(x, sy_src2(x, u)))

# `UPat.cvar("gate")` IS `UPat(Ops.CONST)` (`ops.py:1492`, the one definition of `cvar`) and the
def p_cgate(+x: F.Folded, +u: U32) -> Bool: sy_is_const(x, sy_src0(x, u))

# `p_where_gate` is `invalid_gate` in a src SLOT rather than a node of its own, and it is
# the test every gate rule below reads.
def p_where_gate(+x: F.Folded, u: U32, n: U32) -> Bool: p_gate(x, sy_src(x, u, n))

def all_const.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_const.go(t, x, Bool.and(acc, sy_is_op(x, s, O.OpsCONST{})))

def all_const(+x: F.Folded, srcs: List<&2, U32>) -> Bool: all_const.go(srcs, x, True{})

# the two const spellings: Invalid carries no width, so it rides bare inside either.
def p_bare_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(sy_is_op(x, u, O.OpsCONST{}), Bool.and(sy_is_op(x, u, O.OpsSTACK{}), all_const(x, sy_srcs(x, u))))

def is_cast_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    sy_is_op(x, sy_src0(x, u), O.OpsCONST{}))

def p_cast_or_bad(+x: F.Folded, +s: U32) -> Bool:
  Bool.or(is_cast_const(x, s), p_invalid(x, s))

def all_cast_or_bad.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_cast_or_bad.go(t, x, Bool.and(acc, p_cast_or_bad(x, s)))

def all_cast_or_bad(+x: F.Folded, srcs: List<&2, U32>) -> Bool:
  all_cast_or_bad.go(srcs, x, True{})

# `casted_const` -- `UPat.any(p:=UPat(Ops.CAST, src=(UPat(Ops.CONST),)),
def p_casted_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(is_cast_const(x, u), Bool.and(sy_is_op(x, u, O.OpsSTACK{}), all_cast_or_bad(x, sy_srcs(x, u))))

def p_all_casted.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: p_all_casted.go(t, x, Bool.and(acc, p_casted_const(x, s)))

def p_all_casted(+x: F.Folded, u: U32) -> Bool: p_all_casted.go(sy_srcs(x, u), x, True{})

# `x == y` ON ARENA INDICES, which is `UOp.__eq__` because `UOp.__eq__` IS identity. This
# is the rebind check and it is LOAD-BEARING (header).
def p_same(a: U32, b: U32) -> Bool: U32.is_eq(a, b)

# THE SRC THAT IS NOT THE CONST, which is what every self-folding rule returns.
def p_nconst(+x: F.Folded, u: U32) -> U32:
  Bool.pick(U32, sy_is_op(x, sy_src0(x, u), O.OpsCONST{}), 1, 0)

def p_nc(+x: F.Folded, +u: U32) -> U32: sy_src(x, u, p_nconst(x, u))

# THE DTYPE SETS. `dtypes.ints` is a Python TUPLE (tinygrad/dtype.py:159, `uints + sints`)
def DTS_INTS() -> List<&2, S.Dt>:
  [S.uint8(), S.uint16(), S.uint32(), S.uint64(), S.int8(), S.int16(), S.int32(), S.int64()]

def DTS_SINTS() -> List<&2, S.Dt>: [S.int8(), S.int16(), S.int32(), S.int64()]

def DTS_INTISH() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, DTS_INTS(), [S.boolean()]), [S.weakint()])

def DTS_INTWEAK() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, DTS_INTS(), [S.weakint()])

# MEMBERSHIP IN A DTYPE LIST. `ops.bend` has `op_in` and no `dt_in`, and `fold.bend`'s
def dt_in(ds: List<&2, S.Dt>, +want: S.Dt) -> Bool:
  match ds:
    case Nil{}: False{}
    case d <> t: Bool.or(O.eq_dt(want, d), dt_in(t, want))

def dt_intish(d: S.Dt) -> Bool: dt_in(DTS_INTISH(), d)

def p_intish(x: F.Folded, u: U32) -> Bool: dt_intish(sy_dt1(x, u))

# `dtypes.ints + (dtypes.weakint,)` -- tinygrad/dtype.py:93 and :307, NINE of them.
def dt_intweak(d: S.Dt) -> Bool: dt_in(DTS_INTWEAK(), d)

def p_intweak(x: F.Folded, u: U32) -> Bool: dt_intweak(sy_dt1(x, u))

# A NODE'S `arg` DTYPE, which for a CAST is the node's own dtype. `UOp.dtype`
# (ops.py:246) reaches it through the fold; the three `cast(...)` rules below
def sy_arg_dt.of(a: O.Arg) -> Maybe<&1, S.Dt>:
  match a:
    case O.ADt{d}: Some{d}
    case _: None{}

def sy_arg_dt(x: F.Folded, u: U32) -> Maybe<&1, S.Dt>: sy_arg_dt.of(sy_arg(x, u))

def p_dt1(m: Maybe<&1, S.Dt>, want: S.Dt) -> Bool:
  match m:
    case Some{d}: O.eq_dt(d, want)
    case None{}: False{}

def p_dt_in(ds: List<&2, S.Dt>, m: Maybe<&1, S.Dt>) -> Bool:
  match m:
    case Some{d}: dt_in(ds, d)
    case None{}: False{}

# symbolic.py:32  `def fits(x, v): return x.dtype not in dtypes.sints or x.dtype.min <= v <= x.dtype.max`
def fits.lo(+mag: Maybe<&2, U32>, +v: H.I64) -> Bool:
  match mag:
    case Some{+m}: H.i64_le(H.i64_neg(True{}, H.i64_of_hi_lo(0, m)), v)
    case None{}: True{}

def fits.hi(+top: Maybe<&2, U32>, +v: H.I64) -> Bool:
  match top:
    case Some{+t}: H.i64_le(v, H.i64_of_hi_lo(0, t))
    case None{}: True{}

def fits.go(sint: Bool, +dt: S.Dt, +v: H.I64) -> Bool:
  match sint:
    case True{}: Bool.and(fits.lo(S.Dt.min(dt), v), fits.hi(S.Dt.max(dt), v))
    case False{}: True{}

def fits(+dt: S.Dt, +v: H.I64) -> Bool: fits.go(dt_in(DTS_SINTS(), dt), dt, v)

def p_bool(x: F.Folded, u: U32) -> Bool: sy_dt_is(x, u, S.boolean())

def p_weakint(x: F.Folded, u: U32) -> Bool: sy_dt_is(x, u, S.weakint())

# `dtypes.weaks` is `(weakint, weakfloat)`, and it is `S.Cls`'s two weak members -- the
# same spelling `spec.bend` uses for the same Python line.
def dt_weak(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_weak_of(d: S.Dt) -> Bool: dt_weak(S.Dt.cls(d))

def p_weak(x: F.Folded, u: U32) -> Bool: dt_weak_of(sy_dt1(x, u))

# `UPat.const(0)` is `UPat(Ops.CONST, arg=0)` and `UPat.const(True, dtypes.bool)` is the
# same with `True`, so "is this src the const 0" is ONE test.
def const_i64(m: Maybe<&2, O.Const>, n: H.I64) -> Bool:
  match m:
    case Some{O.CInt{i}}: Cmp.is_eq(H.i64_cmp(i, n))
    case _: False{}

def p_is_const_i(x: F.Folded, u: U32, n: H.I64) -> Bool: const_i64(sy_val(x, u), n)

def cb_true(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CBool{True{}}}: True{}
    case _: False{}

def cb_false(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CBool{False{}}}: True{}
    case _: False{}

def p_is_const_true(x: F.Folded, u: U32) -> Bool: cb_true(sy_val(x, u))

def p_is_const_false(x: F.Folded, u: U32) -> Bool: cb_false(sy_val(x, u))

def p_is_const_0(x: F.Folded, u: U32) -> Bool: p_is_const_i(x, u, H.i64_of_i32(0))

def p_is_const_1(x: F.Folded, u: U32) -> Bool: p_is_const_i(x, u, H.i64_of_i32(1))

def p_is_const_neg1(x: F.Folded, u: U32) -> Bool: p_is_const_i(x, u, H.i64_of_i32(4294967295))

# THE FAITHFUL `U32` BIT PATTERN OF A CONST, and `None{}` for a value that has
def I32_MIN() -> H.I64: H.i64_of_hi_lo(2147483648, 0)

def I32_MAX() -> H.I64: H.i64_of_i32(2147483647)

def i32_fits(+i: H.I64) -> Bool: Bool.and(H.i64_le(I32_MIN(), i), H.i64_le(i, I32_MAX()))

def const_i32.go(ok: Bool, bits: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: Some{bits}
    case False{}: None{}

def const_i32.cint(fits: Bool, +i: H.I64) -> Maybe<&1, U32>: const_i32.go(fits, H.lo32(i))

def const_i32(v: O.Const) -> Maybe<&1, U32>:
  match v:
    case O.CInt{+i}: const_i32.cint(i32_fits(i), i)
    case O.CBool{b}: Some{Bool.to_u32(b)}
    case _: None{}

# `-1` AS A `U32`, which is the right-hand side of both mask tests. A LITERAL and not a
# `neg`, so the reader cannot see a sign where there is none.
def ALL_ONES() -> U32: 4294967295

# `c.val == 0` / `== 1` / NEITHER, as ONE Nat, which is the three-way symbolic.py:136
def sy_cval3.go(v: O.Const) -> U32:
  match v:
    case O.CInvalid{}: 2
    case O.CBool{b}: Bool.pick(U32, b, 1, 0)
    case O.CInt{+i}: Bool.pick(U32, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(0))), 0,
      Bool.pick(U32, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(1))), 1, 2))
    case O.CFloat{+f}: Bool.pick(U32, F32.is_eq(f, 0.0), 0, Bool.pick(U32, F32.is_eq(f, 1.0), 1, 2))

def sy_cval3(m: Maybe<&2, O.Const>) -> U32:
  match m:
    case Some{v}: sy_cval3.go(v)
    case None{}: 2

# `c.val` as an I64, for the three rules that need the NUMBER rather than a truth value.
# Python's `c.val` is a PyConst; on the `CInt` lane it is an I64.
def sy_cint2(m: Maybe<&2, O.Const>) -> H.I64:
  match m:
    case Some{O.CInt{i}}: i
    case _: H.i64_of_i32(0)

def sy_cint(m: Maybe<&1, O.Const>) -> H.I64:
  match m:
    case Some{O.CInt{i}}: i
    case _: H.i64_of_i32(0)

def sy_is_cint(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CInt{i}}: True{}
    case _: False{}

# A CONST at a dtype, value already in range. `sy_const_put` rather than `sy_const`
def sp_const(dt: S.Dt, i: H.I64, +ar: O.Arena) -> U32: sy_const_put(dt, O.CInt{i}, ar)

def sp_const_i(dt: S.Dt, i: H.I64, +ar: O.Arena) -> U32: sp_const(dt, i, ar)

# `const_like(False, dtypes.bool)` and `const_like(0)`, which the zero-folding rules
def sp_false(+dt: S.Dt, +ar: O.Arena) -> U32:
  sy_const_cast(Bool.not(O.eq_dt(dt, S.boolean())), ar, dt, O.Found.i(O.UOp.const(ar, O.CBool{False{}})))

# `simplify_pow` -- symbolic.py:16-21. TWO of its FIVE arms are ported; the other
def sp_neg_pow(+x: F.Folded, +u: U32, i: H.I64) -> U32:
  sy_alu2(sy_ar(x), O.OpsPOW{}, sy_alu1(sy_ar(x), O.OpsRECIP{}, u),
    sp_const(sy_dt1(x, u), H.i64_sub(H.i64_of_i32(0), i), sy_ar(x)))

def sp_pow.cint(+i: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, H.i64_is_neg(i), Some{sp_neg_pow(x, u, i)},
    Bool.pick(Maybe<&1, U32>, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(0))),
      Some{sp_const(sy_dt1(x, u), H.i64_of_i32(1), sy_ar(x))}, None{}))

def simplify_pow.val(m: Maybe<&2, O.Const>, x: F.Folded, u: U32) -> Maybe<&1, U32>:
  match m:
    case Some{O.CInt{i}}: sp_pow.cint(i, x, u)
    case _: None{}

def simplify_pow(+x: F.Folded, u: U32, c: U32) -> Maybe<&1, U32>:
  simplify_pow.val(sy_val(x, c), x, u)

# `fold_bitcast` -- symbolic.py:23-26,
def fold_bitcast.v(m: Maybe<&2, O.Const>, +x: F.Folded, u: U32) -> Maybe<&1, U32>:
  match m:
    case Some{O.CInt{i}}: Some{sp_const(sy_dt1(x, u), i, sy_ar(x))}
    case _: None{}

def fold_bitcast.same(ok: Bool, m: Maybe<&2, O.Const>, x: F.Folded, u: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: fold_bitcast.v(m, x, u)
    case _: None{}

def fold_bitcast(+x: F.Folded, +u: U32, +c: U32) -> Maybe<&1, U32>:
  fold_bitcast.same(O.eq_dt(sy_dt1(x, u), sy_dt1(x, c)), sy_val(x, c), x, u)

# `fold_const_alu` -- symbolic.py:29,
def fca.raw(ok: Bool, m: Maybe<&1, O.Const>) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, ok, m, None{})

def fca.u1(+x: F.Folded, +u: U32, +v: Maybe<&2, O.Const>) -> Maybe<&1, O.Const>:
  fca.raw(Maybe.is_some(&2, O.Const, v), exec_alu1(sy_op(x, u), sy_dt1(x, u), sy_maybe_c2(v), False{}))

def fca.b2(+x: F.Folded, +u: U32, +v: Maybe<&2, O.Const>, w: Maybe<&2, O.Const>) -> Maybe<&1, O.Const>:
  fca.raw(Maybe.is_some(&2, O.Const, v), exec_alu2(sy_op(x, u), sy_dt1(x, u), sy_maybe_c2(v), sy_maybe_c2(w), False{}))

def fca.t3(+x: F.Folded, +u: U32, +v: Maybe<&2, O.Const>, w: Maybe<&2, O.Const>, z: Maybe<&2, O.Const>) -> Maybe<&1, O.Const>:
  fca.raw(Maybe.is_some(&2, O.Const, v), exec_alu3(sy_op(x, u), sy_dt1(x, u), sy_maybe_c2(v), sy_maybe_c2(w), sy_maybe_c2(z), False{}))

def fca.n(+n: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, U32.is_eq(n, 1), fca.u1(x, u, sy_const_arg(x, sy_src0(x, u))),
    Bool.pick(Maybe<&1, O.Const>, U32.is_eq(n, 2),
      fca.b2(x, u, sy_const_arg(x, sy_src0(x, u)), sy_const_arg(x, sy_src1(x, u))),
      Bool.pick(Maybe<&1, O.Const>, U32.is_eq(n, 3),
        fca.t3(x, u, sy_const_arg(x, sy_src0(x, u)), sy_const_arg(x, sy_src1(x, u)), sy_const_arg(x, sy_src2(x, u))), None{})))

def fold_const_alu(n: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_const_like(x, u, sy_maybe_c(fca.n(n, x, u)))

def fold_const_alu.at(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  fold_const_alu(sy_nsrc(x, u), x, u)

# the rules. a rule's captures are `src[k]` of the node it matched -- Python's compiled

# `INDEX(_, CONST(Invalid))`, and its `or_casted()` alternative
def p_index_bad(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsINDEX{}), sy_nsrc_ge(x, u, 2)), p_invalid(x, sy_src1(x, u)))

def p_index_bad_or_cast(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(p_index_bad(x, u), Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)), p_index_bad(x, sy_src0(x, u))))

# symbolic.py:80  (invalid_pat.broadcast(), lambda i: i)
def mint_ar(ar: O.Arena) -> O.Found: O.Found{ar, 0}

def mint_bin(+f: O.Found, op: O.Op, a: U32, b: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [a, b])

def mint_un(+f: O.Found, op: O.Op, a: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [a])

def mint_cast(+f: O.Found, a: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsCAST{}, [a], O.ADt{dt}, O.TNone{})

# `UOp.const(v, dt)` at an explicit arena, and `O.UOp.const` has already interned the BARE
def mint_cst(needs: Bool, +f: O.Found, dt: S.Dt) -> O.Found:
  match needs:
    case True{}: mint_cast(f, O.Found.i(f), dt)
    case False{}: f

def mint_const(+f: O.Found, v: O.Const, +dt: S.Dt) -> O.Found:
  mint_cst(sy_needs_cast(dt, v), f, dt)

# `x.replace(src=...)` at an explicit arena, with the op/arg/tag READ OUT OF THE FOLD
# because they are properties of the ORIGINAL node and not of the grown one.
def mint_replace(+f: O.Found, +x: F.Folded, +u: U32, src: List<&2, U32>) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.Arena.op(sy_ar(x), u), src, O.Arena.arg(sy_ar(x), u), O.Arena.tag(sy_ar(x), u))

# `x.logical_not()` at an explicit arena: `CMPNE(x, CONST(True))`, and the CONST is
# interned first because it is an argument.
# `x.logical_not()` on a BOOL node. At the pin this was `cast(bool).ne(True)` and built
# `CMPNE(x, CONST(True))`; at HEAD it is `cast(bool).eq(False)` and builds
# `CMPEQ(x, CONST(False))`. the name did not change and the node did -- see `symbolic.py:140`.
def mint_not(+f: O.Found, v: U32) -> O.Found:
  +c = O.UOp.const(O.Found.ar(f), O.CBool{False{}})
  mint_bin(c, O.OpsCMPEQ{}, v, O.Found.i(c))

# `x.ne(y)` AT THE PIN IS `x.eq(y).logical_not()` (mixin/elementwise.py:332-336 AT
def mint_ne(+f: O.Found, x: U32, y: U32) -> O.Found:
  +eq = mint_bin(f, O.OpsCMPEQ{}, x, y)
  mint_not(eq, O.Found.i(eq))

def mint_recip(+f: O.Found, v: U32) -> O.Found: mint_un(f, O.OpsRECIP{}, v)

# symbolic.py:462  ((UPat.var("x") * UPat.var("x")).reciprocal(),
def sym_462.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsRECIP{}, 1, Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsMUL{}), Bool.and(sy_nsrc_is(x, sy_src0(x, u), 2), Bool.and(p_same(sy_src0(x, sy_src0(x, u)), sy_src1(x, sy_src0(x, u))), p_weakint(x, u)))))
  # and the weakint guard, because upstream deleted this rule in `1b892575c` ("remove unsafe

def sym_462.put(+f: O.Found, v: U32) -> O.Found:
  +r = mint_recip(f, v)
  mint_bin(r, O.OpsMUL{}, O.Found.i(r), O.Found.i(r))

def sym_462.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_462.put(mint_ar(sy_ar(x)), sy_src0(x, sy_src0(x, u)))}
    case _     : None{}

def sym_462(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_462.hit(sym_462.pat(x, u), x, u)

# symbolic.py:439-442 -- `# this is symbolic 2.0` -- the SINK cleanup, upstream's
def p_sink_like(x: F.Folded, s: U32) -> Bool:
  sy_op_in(x, s, [O.OpsNOOP{}, O.OpsSTACK{}, O.OpsSINK{}, O.OpsAFTER{}])

def sink_srcs.of(+x: F.Folded, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, p_sink_like(x, s), sy_srcs(x, s), [s])

# `x.src if x.op in REMOVE_FROM_SINK_LIKE else (x,)` -- the LISTS stay unflattened
def any_sink_like(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_sink_like(t, x, Bool.or(acc, p_sink_like(x, s)))

def sink_srcs.go(srcs: List<&2, U32>, +x: F.Folded, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match srcs:
    case Nil{}: acc
    case s <> t: sink_srcs.go(t, x, List.append(&2, List<&2, U32>, acc, [sink_srcs.of(x, s)]))

def sym_444.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_op_in(x, u, [O.OpsSINK{}]), any_sink_like(sy_srcs(x, u), x, False{}))

def sym_444.put(srcs: List<&2, U32>, +ar: O.Arena, +u: U32) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, u), srcs, O.Arena.arg(ar, u), O.Arena.tag(ar, u))

def sym_444.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_444.put(H.flatten_u32(sink_srcs.go(sy_srcs(x, u), x, Nil{})), sy_ar(x), u)}
    case _     : None{}

def sym_444(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_444.hit(sym_444.pat(x, u), x, u)
# THE REST OF `symbolic_simple`, and every rule below was on the TODO list for a
# ---- THE PERMUTED-SRC FACT, and the one record six rules share ----
# `UPat.alu` (ops.py:1543) hands a COMMUTATIVE op a LIST `src`, and a list is
type Sw is Data:
  Sw{ok: Bool, a: U32, b: U32}

def Sw.ok(p: Sw) -> Bool:
  match p:
    case Sw{ok, a, b}: ok

def Sw.a(p: Sw) -> U32:
  match p:
    case Sw{ok, a, b}: a

def Sw.b(p: Sw) -> U32:
  match p:
    case Sw{ok, a, b}: b

def sw.a(t1: Bool, s0: U32, s1: U32) -> U32: Bool.pick(U32, t1, s1, s0)

def sw.b(t1: Bool, s0: U32, s1: U32) -> U32: Bool.pick(U32, t1, s0, s1)

def sw.of(t0: Bool, +t1: Bool, +s0: U32, +s1: U32) -> Sw:
  Sw{Bool.or(t0, t1), sw.a(t1, s0, s1), sw.b(t1, s0, s1)}

# `-x`, `x.const_like(v)`, `const_like(False, dt)` and `x.where(t, e)` — the four ANSWERS
def mint_neg(+f: O.Found, v: U32) -> O.Found:
  +m1 = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(U32.sub(0, 1))})
  mint_bin(m1, O.OpsMUL{}, v, O.Found.i(m1))

# THE SCRUTINEE IS A PARAMETER, not a call: Bend refuses a `match` on a computed value.
def mint_const_like.go(tv: Maybe<&1, O.Const>, +f: O.Found, dt: S.Dt) -> Maybe<&1, O.Found>:
  match tv:
    case Some{+w}: Some{mint_const(O.UOp.const(O.Found.ar(f), w), w, dt)}
    case None{}: None{}

def mint_const_like(+f: O.Found, +x: F.Folded, +u: U32, v: O.Const) -> Maybe<&1, O.Found>:
  mint_const_like.go(sy_trunc(sy_dt1(x, u), v), f, sy_dt1(x, u))

def mint_false(+f: O.Found, +dt: S.Dt) -> O.Found:
  mint_cst(Bool.not(O.eq_dt(dt, S.boolean())), O.UOp.const(O.Found.ar(f), O.CBool{False{}}), dt)

def mint_true(+f: O.Found, +dt: S.Dt) -> O.Found:
  mint_cst(Bool.not(O.eq_dt(dt, S.boolean())), O.UOp.const(O.Found.ar(f), O.CBool{True{}}), dt)

def mint_alu(+op: O.Op, +f: O.Found, +srcs: List<&2, U32>) -> O.Found:
  O.UOp.new(O.Found.ar(f), op, srcs, O.ANone{}, O.TNone{})

def mint_where(+f: O.Found, c: U32, t: U32, e: U32) -> O.Found:
  mint_alu(O.OpsWHERE{}, f, [c, t, e])

def sp_neg_pow_f.put(m: Maybe<&1, O.Found>, +r: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsPOW{}, O.Found.i(r), O.Found.i(c))}
    case None{}: None{}

def sp_neg_pow_f(+f: O.Found, +x: F.Folded, +u: U32, i: H.I64) -> Maybe<&1, O.Found>:
  +r = mint_recip(f, u)
  sp_neg_pow_f.put(mint_const_like(r, x, u, O.CInt{H.i64_sub(H.i64_of_i32(0), i)}), r)

def sp_pow.cint_f(+i: H.I64, +x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  Bool.pick(Maybe<&1, O.Found>, H.i64_is_neg(i), sp_neg_pow_f(f, x, u, i),
    Bool.pick(Maybe<&1, O.Found>, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(0))),
      mint_const_like(f, x, u, O.CInt{H.i64_of_i32(1)}), None{}))

def simplify_pow_f.val(m: Maybe<&2, O.Const>, +x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{O.CInt{i}}: sp_pow.cint_f(i, x, u, f)
    case _: None{}

def simplify_pow_f(+f: O.Found, +x: F.Folded, +u: U32, c: U32) -> Maybe<&1, O.Found>:
  simplify_pow_f.val(sy_val(x, c), x, u, f)

# `invalid_pat.broadcast()` is a stack whose srcs are all invalid, and the port tested
# only `src[0]`. MEASURED 2026-11-03: `(stack bad x)` answered `bad` where CPython answers
def all_invalid.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_invalid.go(t, x, Bool.and(acc, p_invalid(x, s)))

def sym_82.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_ge(x, u, O.OpsSTACK{}, 1, all_invalid.go(sy_srcs(x, u), x, True{}))

# the shape CONST, and it is a plain INT CONST and not a tuple. measured 2026-11-07 on
# `tinybendygrad/schedule/prepare.bend`'s `pr_shp1` USES FOR A *SHAPE* ARG, AND IT ANSWERED
def sym_82.shape(+f: O.Found, n: U32) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(n)})

def sym_82.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +inv = O.UOp.invalid(O.Found.ar(f))
  +sh = sym_82.shape(inv, sy_nsrc(x, u))
  O.UOp.new(O.Found.ar(sh), O.OpsEXPAND{}, [O.Found.i(inv), O.Found.i(sh)], O.ANone{}, O.TNone{})

def sym_82(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_82.pat(x, u),
    Some{sym_82.put(x, u, mint_ar(sy_ar(x)))})

# symbolic.py:81  (UPat(GroupOp.Unary|{CAST, BITCAST}, src=(invalid_pat,)), lambda i: i)
def sym_83.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_UNARY()), sy_nsrc_is(x, u, 1)), p_invalid(x, sy_src0(x, u)))

def sym_83(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_83.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:90  (invalid_pat.where(UPat(), UPat()), lambda i: i)
def sym_92.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, p_invalid(x, sy_src0(x, u)))

def sym_92(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_92.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:91  (invalid_gate.where(UPat.var("a"), UPat.var("b")),
def sym_93.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, p_where_gate(x, u, 0))

def sym_93.gate(x: F.Folded, u: U32) -> U32: sy_src0(x, u)

def sym_93.gx(x: F.Folded, u: U32) -> U32: sy_src1(x, u)

def sym_93.gi(x: F.Folded, u: U32) -> U32: sy_src2(x, u)

def sym_93.pick(cond: Bool, t: U32, f: U32) -> U32: Bool.pick(U32, cond, t, f)

# two wheres and both are new, so this rule is Found-family: `cond.where(x.where(a,b), i)`
# builds the inner gate first and the outer one on the arena the inner grew.
def sym_93.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}:
      +g = sym_93.gate(x, u)
      +inner = mint_where(mint_ar(sy_ar(x)), sym_93.gx(x, g), sy_src1(x, u), sy_src2(x, u))
      Some{mint_where(inner, sy_src0(x, g), O.Found.i(inner), sym_93.gi(x, g))}
    case _: None{}

def sym_93(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_93.hit(sym_93.pat(x, u), x, u)

# symbolic.py:99  (UPat(Ops.STORE, src=(UPat(Ops.INDEX, src=(UPat(), invalid_pat),
#                       allow_any_len=True).or_casted(), UPat())), lambda i: UOp(Ops.NOOP))
def sym_101.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsSTORE{}, 2, p_index_bad_or_cast(x, sy_src0(x, u)))

def sym_101.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_noop(sy_ar(x))})

def sym_101(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_101.hit(sym_101.pat(x, u), x, u)

# symbolic.py:100-101  (UPat(Ops.LOAD, src=(UPat(Ops.INDEX, ...).or_casted(),),
def sym_103.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_ge(x, u, O.OpsLOAD{}, 1, p_index_bad_or_cast(x, sy_src0(x, u)))

def sym_103.zero(x: F.Folded, u: U32) -> Maybe<&1, U32>:
  sy_const_like(x, u, O.CInt{H.i64_of_i32(0)})

def sym_103.one(x: F.Folded, u: U32) -> Bool: U32.is_eq(sy_nsrc(x, u), 1)

def sym_103.arm(one: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, one, sym_103.zero(x, u), Some{sy_src1(x, u)})

def sym_103.hit(hit: Bool, one: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, sym_103.arm(one, x, u))

def sym_103(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sym_103.hit(sym_103.pat(x, u), sym_103.one(x, u), x, u)

# symbolic.py:117  (UPat({ADD, XOR, OR}, src=[UPat.var("x"), UPat.const(0)]),
def sym_120.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_SELF()), sy_nsrc_is(x, u, 2)),
    Bool.or(p_is_const_0(x, sy_src0(x, u)), p_is_const_0(x, sy_src1(x, u))))

# `c0` says src[0] is the CONST, so the answer is src[1]; the two spellings of
def sym_120.pick(c0: Bool, a: U32, b: U32) -> Maybe<&1, U32>: Some{Bool.pick(U32, c0, a, b)}

def sym_120(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_120.pat(x, u), sym_120.pick(p_is_const_0(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u)))

# symbolic.py:120  (UPat.var("x") // UPat.var("x"), lambda x: x.const_like(1))
def sym_123.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsDIV{}, 2, p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_123.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(hit, mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(1)}))

def sym_123(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_123.hit(sym_123.pat(x, u), x, u)

# THE REBIND SHAPE, ONCE. `sym_126` (symbolic.py:123, `(x^y)^y`) and `sym_127`
def p_rebind2(+x: F.Folded, +op: O.Op, +u: U32) -> Bool:
  +m = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, op), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, m, op), Bool.and(sy_nsrc_is(x, m, 2), p_same(sy_src1(x, u), sy_src1(x, m)))))

# symbolic.py:123  ((UPat.var("x") ^ UPat.var("y")) ^ UPat.var("y"), lambda x,y: x)
def sym_126.pat(+x: F.Folded, +u: U32) -> Bool: p_rebind2(x, O.OpsXOR{}, u)

def sym_126(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_126.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})

def p_all_bare.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: p_all_bare.go(t, x, Bool.and(acc, p_bare_const(x, s)))

def p_all_bare(+x: F.Folded, u: U32) -> Bool: p_all_bare.go(sy_srcs(x, u), x, True{})

# symbolic.py:158  (UPat(GroupOp.ALU-{THREEFRY}, src=bare_const, name="a"),
def fold_const_alu_f(n: U32, +x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  mint_const_like(f, x, u, sy_maybe_c(fca.n(n, x, u)))

def fold_const_alu_f.at(+x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  fold_const_alu_f(sy_nsrc(x, u), x, u, f)

def sym_161.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.alu(sy_op(x, u)), Bool.not(O.eq_op(sy_op(x, u), O.OpsTHREEFRY{}))),
    p_all_bare(x, u))

def sym_161.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(hit, fold_const_alu_f.at(x, u, mint_ar(sy_ar(x))))

def sym_161(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_161.hit(sym_161.pat(x, u), x, u)

# `UOp.const_like(v)` carrying the arena, for a body that has the VALUE and not a `Const`:
def mint_const_v(m: Maybe<&2, O.Const>, +f: O.Found, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{v}: mint_const_like.go(sy_trunc(dt, v), f, dt)
    case None{}: None{}

# symbolic.py:155  (UPat(Ops.CAST, dtypes.all, name="root", src=(UPat.cvar("c"),)),
def sym_155.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCAST{}, 1, sy_is_const(x, sy_src0(x, u)))

def sym_155(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_155.pat(x, u), mint_const_v(sy_val(x, sy_src0(x, u)), mint_ar(sy_ar(x)), sy_dt1(x, u)))

# symbolic.py:157  (UPat(Ops.CAST, dtypes.all, name="root",
def sym_157.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCAST{}, 1, Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsCAST{}), Bool.and(sy_nsrc_is(x, sy_src0(x, u), 1), sy_is_const(x, sy_src0(x, sy_src0(x, u))))))

def sym_157(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_157.pat(x, u),
    mint_const_v(sy_val(x, sy_src0(x, sy_src0(x, u))), mint_ar(sy_ar(x)), sy_dt1(x, u)))

# symbolic.py:162 -- the CASTED spelling of `:161`. The two rules differ in the PATTERN only
# (`bare_const` against `casted_const`) and both answer `fold_const_alu`, which MINTs.
def sym_162.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.alu(sy_op(x, u)), Bool.not(O.eq_op(sy_op(x, u), O.OpsTHREEFRY{}))),
    p_all_casted(x, u))

def sym_162.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(hit, fold_const_alu_f.at(x, u, mint_ar(sy_ar(x))))

def sym_162(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_162.hit(sym_162.pat(x, u), x, u)

# THE THREE TESTS, one per discriminating shape. `p_const` for a cvar against a
def p_const(+x: F.Folded, +u: U32) -> Sw:
  sw.of(sy_is_const(x, sy_src0(x, u)), sy_is_const(x, sy_src1(x, u)), sy_src0(x, u), sy_src1(x, u))

def p_shl(+x: F.Folded, +u: U32) -> Sw:
  sw.of(sy_is_op(x, sy_src0(x, u), O.OpsSHL{}), sy_is_op(x, sy_src1(x, u), O.OpsSHL{}),
    sy_src0(x, u), sy_src1(x, u))

def p_cast(+x: F.Folded, +u: U32) -> Sw:
  sw.of(sy_is_op(x, sy_src0(x, u), O.OpsCAST{}), sy_is_op(x, sy_src1(x, u), O.OpsCAST{}),
    sy_src0(x, u), sy_src1(x, u))

# ---- a CAST's OWN dtype as a pattern constraint ----
# `UOp.dtype` (ops.py:246) reads a CAST's `arg`, and a PATTERN CONSTRAINT is not
def p_cast1(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsCAST{}), sy_nsrc_is(x, s, 1))

def p_cast_to(+x: F.Folded, +s: U32, ds: List<&2, S.Dt>) -> Bool:
  Bool.and(p_cast1(x, s), p_dt_in(ds, sy_arg_dt(x, s)))

def p_cast_at(+x: F.Folded, +s: U32, want: S.Dt) -> Bool:
  Bool.and(p_cast1(x, s), p_dt1(sy_arg_dt(x, s), want))

# ---- the SECOND rebind, and the shape it shares with `sym_126` ----
# symbolic.py:124  ((UPat.var() % UPat.var("y")).named("base") % UPat.var("y"),
def sym_127.pat(+x: F.Folded, +u: U32) -> Bool: p_rebind2(x, O.OpsMOD{}, u)

def sym_127(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_127.pat(x, u), Some{sy_src0(x, u)})

# ---- `x == True -> x` on a bool, and `CAST(bool -> ints+weakint) == cvar` ----
# symbolic.py:138  (UPat.var("x", dtype=dtypes.bool).eq(UPat.const(True, dtypes.bool)),
def sym_138.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPEQ{}, 2, Bool.and(sy_dt_is(x, u, S.boolean()), p_is_const_true(x, sy_src1(x, u))))

def sym_138(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_138.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:144  (UPat.var("x", dtype=dtypes.bool).cast(dtypes.wints).eq(UPat.cvar("c")),
def sym_144c.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPEQ{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), Bool.and(p_cast_to(x, Sw.a(p), DTS_INTWEAK()),
      sy_dt_is(x, sy_src0(x, Sw.a(p)), S.boolean()))))

# THE THREE ARMS AS INDICES, and each is ONE `Found` chain: `logical_not(x)`, then `x`, then the
# bare `CONST(False)` -- the last because `x.const_like(False)` is at `x`'s own dtype, which is bool.
def sym_144c.arm(+c3: U32, +b: U32, +f: O.Found) -> O.Found:
  Bool.pick(O.Found, U32.is_eq(c3, 0), mint_not(f, b),
    Bool.pick(O.Found, U32.is_eq(c3, 1), O.Found{O.Found.ar(f), b},
      mint_const(O.UOp.const(O.Found.ar(f), O.CBool{False{}}), O.CBool{False{}}, S.boolean())))

def sym_144c.hit(hit: Bool, c3: U32, +p: Sw, +x: F.Folded) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_144c.arm(c3, sy_src0(x, Sw.a(p)), mint_ar(sy_ar(x)))}
    case _: None{}

def sym_144c(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_cast(x, u)
  sym_144c.hit(sym_144c.pat(x, u, p), sy_cval3(sy_val(x, Sw.b(p))), p, x)

# symbolic.py:137  (UPat.var("x", dtype=dtypes.ints+(dtypes.bool, dtypes.weakint)).trunc(),
def sym_140.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsTRUNC{}, 1, p_intish(x, sy_src0(x, u)))

def sym_140(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_140.pat(x, u), Some{sy_src0(x, u)})

# ---- the two MASK rules, and the ONE record they share ----
# symbolic.py:144-145  ((UPat.var("x") & UPat.cvar("mask")) >> UPat.cvar("k"),
type Mc is Data:
  Mc{ok: Bool, m: U32, k: U32}

def Mc.ok(c: Mc) -> Bool:
  match c:
    case Mc{ok, m, k}: ok

def Mc.m(c: Mc) -> U32:
  match c:
    case Mc{ok, m, k}: m

def Mc.k(c: Mc) -> U32:
  match c:
    case Mc{ok, m, k}: k

# A `Maybe` is a `Type` with no `+` spelling, so "does it fit" and "what are its
def mc32.put(ok: Bool, m: Maybe<&1, U32>, k: Maybe<&1, U32>) -> Mc:
  Mc{ok, Maybe.default(&1, U32, m, 0), Maybe.default(&1, U32, k, 0)}

def mc32.mask(mo: Maybe<&2, O.Const>, k: Maybe<&1, U32>) -> Mc:
  match mo:
    case Some{v}: mc32.put(True{}, const_i32(v), k)
    case None{}: mc32.put(False{}, None{}, k)

def mc32.of(mo: Maybe<&2, O.Const>, ko: Maybe<&2, O.Const>) -> Mc:
  match ko:
    case Some{v}: mc32.mask(mo, const_i32(v))
    case None{}: mc32.mask(mo, None{})

# The mask is the `&`'s `a` and its `x` the `&`'s `b`, and the amount is the
# OUTER's src[1] because neither `SHR` nor `DIV` permutes.
def p_mask(+x: F.Folded, +u: U32, +op: O.Op, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, op), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsAND{}),
      Bool.and(sy_nsrc_is(x, sy_src0(x, u), 2), Sw.ok(p))))

def sym_147.gate(+c: Mc) -> Bool:
  Bool.and(Mc.ok(c), Bool.and(U32.is_le(Mc.k(c), 31),
    U32.is_eq(U32.or(Mc.m(c), U32.sub(U32.shln(1, U32.to_nat(Mc.k(c))), 1)), ALL_ONES())))

def sym_147.put(+k: U32, v: U32, +f: O.Found) -> O.Found:
  +c = mint_const(O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(k)}), O.CInt{H.i64_of_i32(k)}, S.weakint())
  mint_bin(c, O.OpsSHR{}, v, O.Found.i(c))

def sym_147.hit(gate: Bool, +c: Mc, v: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match gate:
    case True{}: Some{sym_147.put(Mc.k(c), v, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_147(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_const(x, sy_src0(x, u))
  +c = mc32.of(sy_val(x, Sw.a(p)), sy_val(x, sy_src1(x, u)))
  sym_147.hit(Bool.and(p_mask(x, u, O.OpsSHR{}, p), sym_147.gate(c)), c, Sw.b(p), x)

def sym_149.gate(+c: Mc) -> Bool:
  Bool.and(Mc.ok(c), Bool.and(U32.is_gt(Mc.k(c), 0),
    Bool.and(U32.is_eq(U32.and(Mc.k(c), U32.sub(Mc.k(c), 1)), 0),
      U32.is_eq(U32.or(Mc.m(c), U32.sub(Mc.k(c), 1)), ALL_ONES()))))

def sym_149.put(+k: U32, v: U32, +f: O.Found) -> O.Found:
  +c = mint_const(O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(k)}), O.CInt{H.i64_of_i32(k)}, S.weakint())
  mint_bin(c, O.OpsDIV{}, v, O.Found.i(c))

def sym_149.hit(gate: Bool, +c: Mc, v: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match gate:
    case True{}: Some{sym_149.put(Mc.k(c), v, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_149(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_const(x, sy_src0(x, u))
  +c = mc32.of(sy_val(x, Sw.a(p)), sy_val(x, sy_src1(x, u)))
  sym_149.hit(Bool.and(p_mask(x, u, O.OpsDIV{}, p), sym_149.gate(c)), c, Sw.b(p), x)

# ---- the weak-src PROMOTION, and it is a two-src fold ----
# symbolic.py:160-162  (UPat(GroupOp.Binary-{Ops.THREEFRY}, src=[casted_const, bare_const], name="a"),
def OP_BINARY_3F() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{}, O.OpsMOD{}]

# `dt = promo_dtype(a.src)` -- ops.py:120 -- and `F.promo_dtype` is the same lattice
# `least_upper_dtype` is, over the srcs' OWN dtypes.
def sy_promo(+x: F.Folded, +u: U32) -> S.Dt:
  F.promo_dtype([sy_dt1(x, sy_src0(x, u)), sy_dt1(x, sy_src1(x, u))])

def sym_163.pat.left(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(p_casted_const(x, sy_src0(x, u)), p_bare_const(x, sy_src1(x, u)))

def sym_163.pat.right(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(p_bare_const(x, sy_src0(x, u)), p_casted_const(x, sy_src1(x, u)))

def sym_163.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_nsrc_is(x, u, 2),
    Bool.and(Bool.not(O.eq_op(sy_op(x, u), O.OpsTHREEFRY{})),
      Bool.or(sym_163.pat.left(x, u), sym_163.pat.right(x, u))))

# A weak src is `ccast`ed at `dt` and a strong one is left alone. `sy_ccast`
def trunc_m.of(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>: sy_trunc(dt, v)

def trunc_m(dt: S.Dt, m: Maybe<&2, O.Const>) -> Maybe<&1, O.Const>:
  match m:
    case Some{v}: trunc_m.of(dt, v)
    case _: None{}

# `UOp.ccast(dt)` AT AN ARENA, and it is `sy_ccast` with the fold's STALE arena
def ccast_cst.of(m: Maybe<&1, O.Const>, +f: O.Found, dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{+v}: Some{mint_const(O.UOp.const(O.Found.ar(f), v), v, dt)}
    case _: None{}

def ccast_cst(v: Maybe<&2, O.Const>, +f: O.Found, +dt: S.Dt) -> Maybe<&1, O.Found>:
  ccast_cst.of(trunc_m(dt, v), f, dt)

def ccast_at.go(is_const: Bool, v: Maybe<&2, O.Const>, +f: O.Found, s: U32, dt: S.Dt) -> Maybe<&1, O.Found>:
  match is_const:
    case True{}: ccast_cst(v, f, dt)
    case _: Some{mint_cast(f, s, dt)}

def ccast_at(v: Maybe<&2, O.Const>, is_const: Bool, +f: O.Found, s: U32, dt: S.Dt) -> Maybe<&1, O.Found>:
  ccast_at.go(is_const, v, f, s, dt)

# ONE SRC COMMITTED AT `dt`, and the `weak` test is a `match` and NOT a `Bool.pick`
# because `Bool.pick` evaluates both arms -- a strong src would be committed on the
# way past, which is a dead node here and a WRONG rewrite if the arena ever grows.
def mint_keep(+f: O.Found, s: U32) -> O.Found: O.Found{O.Found.ar(f), s}

def sym_163.one(weak: Bool, v: Maybe<&2, O.Const>, is_const: Bool, s: U32, +f: O.Found, dt: S.Dt) -> Maybe<&1, O.Found>:
  match weak:
    case True{}: ccast_at(v, is_const, f, s, dt)
    case _: Some{mint_keep(f, s)}

def sym_163.at(+s: U32, +x: F.Folded, +f: O.Found, +dt: S.Dt) -> Maybe<&1, O.Found>:
  sym_163.one(dt_weak_of(sy_dt1(x, s)), sy_val(x, s), sy_is_const(x, s), s, f, dt)

# THE WHOLE REWRITE, and it is ONE def because the two srcs share an arena and a
def sym_163.put(a: U32, m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+b}: Some{mint_replace(b, x, u, [a, O.Found.i(b)])}
    case _: None{}

def sym_163.join(m: Maybe<&1, O.Found>, +s: U32, +x: F.Folded, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{+a}: sym_163.put(O.Found.i(a), sym_163.at(s, x, a, dt), x, u)
    case _: None{}

def sym_163.go(+f: O.Found, +x: F.Folded, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  sym_163.join(sym_163.at(sy_src0(x, u), x, f, dt), sy_src1(x, u), x, u, dt)

def sym_163.hit(gate: Bool, +x: F.Folded, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match gate:
    case True{}: sym_163.go(mint_ar(sy_ar(x)), x, u, dt)
    case _: None{}

def sym_163(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_163.hit(Bool.and(sym_163.pat(x, u), Bool.not(dt_weak_of(sy_promo(x, u)))), x, u, sy_promo(x, u))

# ---- the two THREEFRY unpack rules, and BOTH answer an EXISTING node ----
# symbolic.py:192  (((UPat.var(None, dtypes.uint64)<<32)
def p_shl32(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, s, O.OpsSHL{}), sy_nsrc_is(x, s, 2)),
    p_is_const_i(x, sy_src1(x, s), H.i64_of_i32(32)))

def p_or2(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsOR{}), sy_nsrc_is(x, s, 2))

def sym_196.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(p_dt1(sy_arg_dt(x, u), S.uint32()),
      Bool.and(p_or2(x, sy_src0(x, u)),
        Bool.and(Sw.ok(p), Bool.and(sy_dt_is(x, sy_src0(x, Sw.a(p)), S.uint64()),
          Bool.and(p_shl32(x, Sw.a(p)),
            Bool.and(p_cast_at(x, Sw.b(p), S.uint64()),
              sy_dt_is(x, sy_src0(x, Sw.b(p)), S.uint32()))))))))

def sym_196.hit(hit: Bool, +p: Sw, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_src0(x, Sw.b(p))})

def sym_196(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_shl(x, sy_src0(x, u))
  sym_196.hit(sym_196.pat(x, u, p), p, x, u)

def sym_197.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSHR{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_is_const_i(x, sy_src1(x, u), H.i64_of_i32(32)),
      Bool.and(p_or2(x, sy_src0(x, u)),
        Bool.and(Sw.ok(p), Bool.and(p_shl32(x, Sw.a(p)),
          Bool.and(p_cast_at(x, sy_src0(x, Sw.a(p)), S.uint64()),
            Bool.and(sy_dt_is(x, sy_src0(x, sy_src0(x, Sw.a(p))), S.uint32()),
              Bool.and(p_cast_at(x, Sw.b(p), S.uint64()),
                sy_dt_is(x, sy_src0(x, Sw.b(p)), S.uint32())))))))))

def sym_197.hit(hit: Bool, +p: Sw, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_src0(x, Sw.a(p))})

def sym_197(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_shl(x, sy_src0(x, u))
  sym_197.hit(sym_197.pat(x, u, p), p, x, u)

# ---- the last two RECIP rules, which are `sym_462`'s shape ----
# symbolic.py:463  ((UPat.var("x") * UPat.var("x") * UPat.var("x")).reciprocal(),
def p_mul3.a(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsMUL{}),
    Bool.and(sy_nsrc_is(x, s, 2), p_same(sy_src0(x, s), sy_src1(x, s))))

# `a` is the inner `MUL(v,v)` and `b` is the SIBLING, which is the leaf `v` and not
def p_mul3.ok(ok: Bool, +x: F.Folded, a: U32, b: U32) -> Bool: Bool.and(ok, p_same(sy_src0(x, a), b))

def p_mul3(+x: F.Folded, +u: U32) -> Sw:
  +i = sw.of(p_mul3.a(x, sy_src0(x, u)), p_mul3.a(x, sy_src1(x, u)), sy_src0(x, u), sy_src1(x, u))
  Sw{p_mul3.ok(Sw.ok(i), x, Sw.a(i), Sw.b(i)), Sw.a(i), Sw.b(i)}

# THE SHARED ENTRY TEST, and there is only ONE because the two rules' patterns
def p_recip1(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsRECIP{}),
    Bool.and(sy_nsrc_is(x, u, 1), Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsMUL{}),
      sy_nsrc_is(x, sy_src0(x, u), 2))))

# the shared entry for `:463` (`1/(x*x*x)`) and `:464` (`1/(x*c)`), and the weakint guard is
def p_recip2(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(p_recip1(x, u), Sw.ok(p)), p_weakint(x, u))

# THE TWO ANSWERS, both threaded. `:464`'s is `x.reciprocal()*x.reciprocal()*
def sym_463.put(v: U32, +f: O.Found) -> O.Found:
  +r = mint_recip(f, v)
  +m = mint_bin(r, O.OpsMUL{}, O.Found.i(r), O.Found.i(r))
  mint_bin(m, O.OpsMUL{}, O.Found.i(m), O.Found.i(r))

def sym_463.hit(hit: Bool, +p: Sw, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_463.put(Sw.b(p), mint_ar(sy_ar(x)))}
    case _: None{}

def sym_463(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_mul3(x, sy_src0(x, u))
  sym_463.hit(p_recip2(x, u, p), p, x, u)

# symbolic.py:464  ((UPat.var("x") * UPat.cvar("c")).reciprocal(),
def sym_464.put(v: U32, c: U32, +f: O.Found) -> O.Found:
  +r = mint_recip(f, v)
  +s = mint_recip(r, c)
  mint_bin(s, O.OpsMUL{}, O.Found.i(r), O.Found.i(s))

def sym_464.hit(hit: Bool, +p: Sw, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_464.put(Sw.b(p), Sw.a(p), mint_ar(sy_ar(x)))}
    case _: None{}

def sym_464(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_const(x, sy_src0(x, u))
  sym_464.hit(p_recip2(x, u, p), p, x, u)

# ---- the rules that were missing, in upstream's order ----

# `GroupOp.Binary - GroupOp.Comparison` -- SIXTEEN ops, and it is a `pdict` KEY, so
def OP_BINARY_NC() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsXOR{},
   O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{}, O.OpsAND{}, O.OpsSUB{}, O.OpsFDIV{},
   O.OpsPOW{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsTHREEFRY{}]

# `GroupOp.Idempotent` -- {AND, MAX, OR}, the three ops where `x op x` is `x`.
def OP_IDEMPOTENT() -> List<&2, O.Op>: [O.OpsAND{}, O.OpsMAX{}, O.OpsOR{}]

# THE CONST -1, and `p_is_const_neg1` is NOT it: that one compares the I64 to
def p_is_const_m1(x: F.Folded, u: U32) -> Bool:
  p_is_const_i(x, u, H.i64_sub(H.i64_of_i32(0), H.i64_of_i32(1)))

# THE SRC THAT IS THE CONST 1, and the OTHER one.  `p_const` picks "a src that is a
def p_one(+x: F.Folded, +u: U32) -> Sw:
  sw.of(p_is_const_1(x, sy_src0(x, u)), p_is_const_1(x, sy_src1(x, u)),
    sy_src0(x, u), sy_src1(x, u))

# symbolic.py:84  (UPat(GroupOp.Unary|{Ops.CAST, Ops.BITCAST}, src=(invalid_gate,), name="op"),
def sym_84.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_UNARY()), sy_nsrc_is(x, u, 1)), p_where_gate(x, u, 0))

# `mint_bitcast`, which is `mint_cast`'s sibling: the BITCAST node at an explicit
# dtype, interned into the arena the caller threads.
def mint_bitcast(+f: O.Found, a: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsBITCAST{}, [a], O.ADt{dt}, O.TNone{})

# the scrutinee is a parameter and not a computed value: Bend refuses a `match` on
def sym_84.is_cast(+x: F.Folded, +u: U32) -> Bool: O.eq_op(sy_op(x, u), O.OpsCAST{})

def sym_84.inner(+f: O.Found, +a: U32, +dt: S.Dt, +is_cast: Bool) -> O.Found:
  match is_cast:
    case True{}: mint_cast(f, a, dt)
    case _: mint_bitcast(f, a, dt)

def sym_84.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +g = sy_src0(x, u)
  +v = sy_src1(x, g)
  +i = sy_src2(x, g)
  +inner = sym_84.inner(f, v, sy_dt1(x, u), sym_84.is_cast(x, u))
  mint_where(inner, sy_src0(x, g), O.Found.i(inner), i)

def sym_84.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_84.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_84(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_84.hit(sym_84.pat(x, u), x, u)

# symbolic.py:89  (UPat(GroupOp.Binary-GroupOp.Comparison, src=[invalid_pat, UPat()]),
def sym_89.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_BINARY_NC()), sy_nsrc_is(x, u, 2)),
    Bool.or(p_invalid(x, sy_src0(x, u)), p_invalid(x, sy_src1(x, u))))

def sym_89(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_89.pat(x, u),
    Some{Bool.pick(U32, p_invalid(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))})

# symbolic.py:95  (UPat.var("cond").where(invalid_pat, UPat.var("val")),
def sym_95.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, p_invalid(x, sy_src1(x, u)))

def sym_95.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +n = mint_not(f, sy_src0(x, u))
  mint_where(n, O.Found.i(n), sy_src2(x, u), sy_src1(x, u))

def sym_95.hit(hit: Bool, val_bad: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}:
      match val_bad:
        case True{}: Some{O.Found{sy_ar(x), sy_src1(x, u)}}
        case _: Some{sym_95.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_95(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_95.hit(sym_95.pat(x, u), p_invalid(x, sy_src2(x, u)), x, u)

# symbolic.py:97  (UPat.var("a").where(invalid_gate, UPat.var("c")), lambda cond,i,x,a,c:
def sym_97.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, Bool.and(p_gate(x, sy_src1(x, u)), Bool.not(p_invalid(x, sy_src2(x, u)))))

def sym_97.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +g = sy_src1(x, u)
  +a = sy_src0(x, u)
  +n = mint_not(f, a)
  +o = mint_bin(n, O.OpsOR{}, O.Found.i(n), sy_src0(x, g))
  +w = mint_where(o, a, sy_src1(x, g), sy_src2(x, u))
  mint_where(w, O.Found.i(o), O.Found.i(w), sy_src2(x, g))

def sym_97.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_97.put(x, u, mint_ar(sy_ar(x)))}
    case _     : None{}

def sym_97(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_97.hit(sym_97.pat(x, u), x, u)

# symbolic.py:99  (UPat.var("a").where(UPat.var("b"), invalid_gate), lambda cond,i,x,a,b:
def sym_99.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, Bool.and(p_gate(x, sy_src2(x, u)), Bool.not(p_invalid(x, sy_src1(x, u)))))

def sym_99.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +g = sy_src2(x, u)
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  +o = mint_bin(f, O.OpsOR{}, a, sy_src0(x, g))
  +w = mint_where(o, a, b, sy_src1(x, g))
  mint_where(w, O.Found.i(o), O.Found.i(w), sy_src2(x, g))

def sym_99.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_99.put(x, u, mint_ar(sy_ar(x)))}
    case _     : None{}

def sym_99(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_99.hit(sym_99.pat(x, u), x, u)

# symbolic.py:121  (UPat({Ops.SHL, Ops.SHR}, src=(UPat.var("x"), UPat.const(0))), lambda x: x)
# shl and shr are not commutative, so the src is ordered and the CONST is at src[1].
def sym_121.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_SHIFTS()), sy_nsrc_is(x, u, 2)),
    p_is_const_0(x, sy_src1(x, u)))

def sym_121(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_121.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:122  (UPat.var("x") * 1, lambda x: x)
def sym_122.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)), Sw.ok(p))

def sym_122(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_one(x, u)
  sy_tri(sym_122.pat(x, u, p), Some{Sw.b(p)})

# symbolic.py:124  (UPat.var("x") // 1, lambda x: x)
# DIV IS NOT COMMUTATIVE, so the src is ORDERED.
def sym_124.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsDIV{}, 2, p_is_const_1(x, sy_src1(x, u)))

def sym_124(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_124.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:125  (UPat.var("x") // -1, lambda x: -x)
def sym_125.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsDIV{}, 2, p_is_const_m1(x, sy_src1(x, u)))

def sym_125(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_125.pat(x, u), Some{mint_neg(mint_ar(sy_ar(x)), sy_src0(x, u))})

# symbolic.py:130  (UPat.var("x", dtype=dtypes.bool) & UPat.cvar("c"),
def sym_130.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsAND{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), sy_dt_is(x, Sw.b(p), S.boolean())))

def sym_130.hit(hit: Bool, truthy: Bool, +p: Sw, +x: F.Folded) -> Maybe<&1, U32>:
  match hit:
    case True{}: Some{Bool.pick(U32, truthy, Sw.b(p), Sw.a(p))}
    case _: None{}

def sym_130(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sym_130.hit(sym_130.pat(x, u, p), sy_val_truthy(x, Sw.a(p)), p, x)

# symbolic.py:131  (UPat.var("x", dtype=dtypes.bool) | UPat.cvar("c"),
def sym_131.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsOR{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), sy_dt_is(x, Sw.b(p), S.boolean())))

def sym_131.hit(hit: Bool, truthy: Bool, +p: Sw, +x: F.Folded) -> Maybe<&1, U32>:
  match hit:
    case True{}: Some{Bool.pick(U32, truthy, Sw.a(p), Sw.b(p))}
    case _: None{}

def sym_131(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sym_131.hit(sym_131.pat(x, u, p), sy_val_truthy(x, Sw.a(p)), p, x)

# THE `!=`-AGAINST-`False` RULE IS GONE, AND THIS IS THE SEVENTH
# MEASURED AT THE PIN `f5ac54685074`: `tinygrad/uop/symbolic.py` HAS NO

# symbolic.py:133  (UPat(GroupOp.Idempotent, src=(UPat.var("x"), UPat.var("x"))), lambda x: x)
def sym_133.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_IDEMPOTENT()), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_133(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_133.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:135  (UPat.var("x", dtype=dtypes.bool).where(UPat.const(True, dtypes.bool),
def sym_135.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, Bool.and(p_is_const_true(x, sy_src1(x, u)), p_is_const_false(x, sy_src2(x, u))))

def sym_135(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_135.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:136  (UPat.var("x", dtype=dtypes.bool).where(UPat.const(False, dtypes.bool),
def sym_134.inner(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(sy_is_op(x, i, O.OpsCMPEQ{}),
    Bool.and(sy_nsrc_is(x, i, 2),
      Bool.and(p_is_const_false(x, sy_src1(x, i)), sy_dt_is(x, sy_src0(x, i), S.boolean()))))

def sym_134.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPEQ{}, 2, Bool.and(p_is_const_false(x, sy_src1(x, u)), sym_134.inner(x, u)))

def sym_134(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri_u(sym_134.pat(x, u), sy_src0(x, sy_src0(x, u)))

def sym_136.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsWHERE{}, 3, Bool.and(p_is_const_false(x, sy_src1(x, u)), p_is_const_true(x, sy_src2(x, u))))

def sym_136.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_not(f, sy_src0(x, u))

def sym_136.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_136.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_136(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_136.hit(sym_136.pat(x, u), x, u)

# symbolic.py:142  (UPat.var("x") < UPat.var("x"), lambda x: x.const_like(False, dtypes.bool))
def sym_142.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPLT{}, 2, p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_142(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_142.pat(x, u), Some{mint_false(mint_ar(sy_ar(x)), S.boolean())})

# symbolic.py:143  (UPat.var("x") % UPat.var("x"), lambda x: x.const_like(0))
# `%` IS MOD AND IT IS NOT COMMUTATIVE.
def sym_143.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMOD{}, 2, p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_143(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_143.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:144  (UPat.var("x") ^ UPat.var("x"), lambda x: x.const_like(0))
def sym_144.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsXOR{}, 2, p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_144(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_144.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:145  (UPat.var("x") & 0, lambda x: x.const_like(0))
# AND IS COMMUTATIVE, so the CONST 0 is at either side.
def sym_145.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsAND{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), p_is_const_0(x, Sw.a(p))))

def sym_145(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sy_tri(sym_145.pat(x, u, p), sy_const_like(x, Sw.b(p), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:155  (UPat.var("x", dtype=dtypes.ints+(dtypes.bool, dtypes.weakint))
def sym_151.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPEQ{}, 2, Bool.and(p_same(sy_src0(x, u), sy_src1(x, u)), p_intish(x, sy_src0(x, u))))

def sym_151(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_151.pat(x, u), Some{mint_true(mint_ar(sy_ar(x)), S.boolean())})

# symbolic.py:167  (UPat.var('x', dtype=dtypes.bool) * UPat.var('y', dtype=dtypes.bool),
def sym_167.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMUL{}, 2, Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_167.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsAND{}, sy_src0(x, u), sy_src1(x, u))

def sym_167.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_167.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_167(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_167.hit(sym_167.pat(x, u), x, u)

# symbolic.py:168  (UPat.var('x', dtype=dtypes.bool) + UPat.var('y', dtype=dtypes.bool),
def sym_168.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsADD{}, 2, Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_168.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsOR{}, sy_src0(x, u), sy_src1(x, u))

def sym_168.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_168.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_168(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_168.hit(sym_168.pat(x, u), x, u)

# symbolic.py:169  (UPat.var('x', dtype=dtypes.bool).maximum(UPat.var('y', dtype=dtypes.bool)),
def sym_169.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMAX{}, 2, Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_169.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsOR{}, sy_src0(x, u), sy_src1(x, u))

def sym_169.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_169.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_169(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_169.hit(sym_169.pat(x, u), x, u)

# symbolic.py:173  (UPat.var("x") / UPat.var("x"), lambda x: x.const_like(1))
def p_recip_of(+x: F.Folded, +u: U32, +first: Bool) -> Bool:
  +r = Bool.pick(U32, first, sy_src0(x, u), sy_src1(x, u))
  +o = Bool.pick(U32, first, sy_src1(x, u), sy_src0(x, u))
  Bool.and(sy_is_op(x, r, O.OpsRECIP{}),
    Bool.and(sy_nsrc_is(x, r, 1), p_same(sy_src0(x, r), o)))

def sym_173.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMUL{}, 2, Bool.or(p_recip_of(x, u, True{}), p_recip_of(x, u, False{})))

def sym_173.vsrc(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sy_is_op(x, sy_src0(x, u), O.OpsRECIP{}), sy_src1(x, u), sy_src0(x, u))

def sym_173(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_173.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sym_173.vsrc(x, u), O.CInt{H.i64_of_i32(1)}))

# symbolic.py:186  (UPat.var('x').cast(name="a").cast(name="b"),
def sym_186.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(Bool.and(sy_is_op(x, i, O.OpsCAST{}), sy_nsrc_is(x, i, 1)),
      Bool.and(O.eq_dt(sy_dt1(x, sy_src0(x, i)), sy_dt1(x, u)),
        D.can_lossless_cast(sy_dt1(x, u), sy_dt1(x, i)))))

def sym_186(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri_u(sym_186.pat(x, u), sy_src0(x, sy_src0(x, u)))

# symbolic.py:188  (UPat(Ops.BITCAST, name="b", src=(UPat.var('x').bitcast(),)),
def sym_188.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsBITCAST{}, 1, Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsBITCAST{}), sy_nsrc_is(x, sy_src0(x, u), 1)))

def sym_188(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_188.pat(x, u),
    Some{mint_bitcast(mint_ar(sy_ar(x)), sy_src0(x, sy_src0(x, u)), sy_dt1(x, u))})

# `y IS logical_not(x)`: AT THE PIN `logical_not()` IS `CMPEQ(x, CONST(False))` --
# `mixin/elementwise.py:57` AT `f5ac54685074` IS `self.cast(dtypes.bool).eq(False)`.
def p_not_of(+x: F.Folded, +n: U32, +v: U32) -> Bool:
  Bool.and(sy_is_op(x, n, O.OpsCMPEQ{}),
    Bool.and(sy_nsrc_is(x, n, 2),
      Bool.and(p_is_const_false(x, sy_src1(x, n)), p_same(sy_src0(x, n), v))))

# symbolic.py:243  (UPat.var("x", dtype=dtypes.bool) | UPat.var("x", dtype=dtypes.bool).logical_not(),
def sym_243.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsOR{}, 2, Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), Bool.or(p_not_of(x, sy_src0(x, u), sy_src1(x, u)), p_not_of(x, sy_src1(x, u), sy_src0(x, u)))))

def sym_243(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_243.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CBool{True{}}))

# symbolic.py:250  (UPat.var("x") + UPat.var("x"), lambda x: x*2)
def sym_250.build(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsMUL{}, sy_src0(x, u), O.Found.i(c))}
    case None{}: None{}

def sym_250.put(+x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  sym_250.build(mint_const_like(f, x, sy_src0(x, u), O.CInt{H.i64_of_i32(2)}), x, u)

def sym_250.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsADD{}, 2, p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_250(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_250.pat(x, u), sym_250.put(x, u, mint_ar(sy_ar(x))))

# symbolic.py:256  (UPat.var("cond", dtype=dtypes.bool).logical_not().where(UPat.var("t"), UPat.var("f")),
def sym_256.pat(+x: F.Folded, +u: U32) -> Bool:
  +g = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(p_not_of(x, g, sy_src0(x, g)),
      Bool.and(sy_nsrc_is(x, g, 2), Bool.not(p_invalid(x, sy_src2(x, u))))))

def sym_256(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +g = sy_src0(x, u)
  sy_tri_f(sym_256.pat(x, u),
    Some{mint_where(mint_ar(sy_ar(x)), sy_src0(x, g), sy_src2(x, u), sy_src1(x, u))})

# symbolic.py:262  a.where(b.where(c, d), d) -> (a&b).where(c, d)
def sym_262.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(Bool.and(sy_is_op(x, i, O.OpsWHERE{}), sy_nsrc_is(x, i, 3)),
      p_same(sy_src2(x, i), sy_src2(x, u))))

def sym_262(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sy_src1(x, u)
  +n = mint_bin(mint_ar(sy_ar(x)), O.OpsAND{}, sy_src0(x, u), sy_src0(x, i))
  sy_tri_f(sym_262.pat(x, u),
    Some{mint_where(n, O.Found.i(n), sy_src1(x, i), sy_src2(x, i))})

# symbolic.py:264  a.where(c, b.where(c, d)) -> (a|b).where(c, d)
def sym_264.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src2(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(Bool.and(sy_is_op(x, i, O.OpsWHERE{}), sy_nsrc_is(x, i, 3)),
      p_same(sy_src1(x, u), sy_src1(x, i))))

def sym_264(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sy_src2(x, u)
  +o = mint_bin(mint_ar(sy_ar(x)), O.OpsOR{}, sy_src0(x, u), sy_src0(x, i))
  sy_tri_f(sym_264.pat(x, u),
    Some{mint_where(o, O.Found.i(o), sy_src1(x, u), sy_src2(x, i))})

# symbolic.py:273  (UPat.var("a").where(UPat.var("b").where(UPat.var("c"), UPat.var("d")),
def sym_273.pat(+x: F.Folded, +u: U32) -> Bool:
  +w = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(Bool.and(sy_is_op(x, w, O.OpsWHERE{}), sy_nsrc_is(x, w, 3)),
      p_same(sy_src2(x, u), sy_src2(x, w))))

def sym_273(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +w = sy_src1(x, u)
  +n = mint_bin(mint_ar(sy_ar(x)), O.OpsAND{}, sy_src0(x, u), sy_src0(x, w))
  sy_tri_f(sym_273.pat(x, u),
    Some{mint_where(n, O.Found.i(n), sy_src1(x, w), sy_src2(x, w))})

# symbolic.py:271  (UPat.var("gate").where(UPat.var("x"), 0) != 0, lambda gate,x: gate & (x != 0))
#  `!=` is `eq(...).logical_not()` at HEAD, so the node is two `CMPEQ` levels and not one
def sym_271.inner(+x: F.Folded, +i: U32, +u: U32) -> Bool:
  +w = sy_src0(x, i)
  Bool.and(Bool.and(sy_is_op(x, i, O.OpsCMPEQ{}), sy_nsrc_is(x, i, 2)),
    Bool.and(p_is_const_0(x, sy_src1(x, i)),
      Bool.and(Bool.and(sy_is_op(x, w, O.OpsWHERE{}), sy_nsrc_is(x, w, 3)),
        p_is_const_0(x, sy_src2(x, w)))))

def sym_271.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPEQ{}, 2, Bool.and(p_is_const_false(x, sy_src1(x, u)), sym_271.inner(x, sy_src0(x, u), u)))

# THE MATCH IS THE FIRST STATEMENT: Bend refuses a `match` whose scrutinee is a parameter
# read after a local binder ("'m' can't be matched in this position").
def sym_271.build(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+z}:
      +w = sy_src0(x, sy_src0(x, u))
      +v = sy_src1(x, w)
      +n0 = mint_bin(z, O.OpsCMPEQ{}, v, O.Found.i(z))
      # the second chain grows from `n0`, not from `z`: two chains minted from the same base are
      # assigned the SAME indices for DIFFERENT nodes, and the render says so with a `?`.
      +n = mint_not(n0, O.Found.i(n0))
      Some{mint_bin(n, O.OpsAND{}, sy_src0(x, w), O.Found.i(n))}
    case None{}: None{}

def sym_271(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_271.pat(x, u),
    sym_271.build(mint_const_like(mint_ar(sy_ar(x)), x, sy_src1(x, sy_src0(x, u)), O.CInt{H.i64_of_i32(0)}), x, u))

# `x * CONST(c)` with the const at either side, which is `p_const`'s `Sw`.
def p_mul_c(+x: F.Folded, +m: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, m, O.OpsMUL{}), sy_nsrc_is(x, m, 2)), Sw.ok(p_const(x, m)))

def sym_245.vside(+x: F.Folded, +m: U32) -> U32: Sw.b(p_const(x, m))

def sym_245.cside(+x: F.Folded, +m: U32) -> U32: Sw.a(p_const(x, m))

# symbolic.py:245  (UPat.var("x") * UPat.cvar("c0") + UPat.var("x") * UPat.cvar("c1"),
def sym_245.pat(+x: F.Folded, +u: U32) -> Bool:
  +m0 = sy_src0(x, u)
  +m1 = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(p_mul_c(x, m0), p_mul_c(x, m1)),
      p_same(sym_245.vside(x, m0), sym_245.vside(x, m1))))

# the sum is a node and not a number: `c0 + c1` in Python is `UOp.__add__` on two CONSTs,
# which BUILDS `(add c0 c1)` and leaves the folding to a later pass. MEASURED: the fold-the-
def sym_245.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +m0 = sy_src0(x, u)
  +s = mint_bin(mint_ar(sy_ar(x)), O.OpsADD{}, sym_245.cside(x, m0), sym_245.cside(x, sy_src1(x, u)))
  Some{mint_bin(s, O.OpsMUL{}, sym_245.vside(x, m0), O.Found.i(s))}

# THE GUARD IS `fits(x, c0.vmin+c1.vmin)`, AND IT WAS MISSING. The coefficient sum is minted at
def sym_245.iv(m: Maybe<&2, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

def sym_245.sum(a: Maybe<&1, H.I64>, b: Maybe<&1, H.I64>) -> Maybe<&1, H.I64>:
  match a:
    case Some{+p}:
      match b:
        case Some{+q}: Some{H.i64_add(p, q)}
        case None{}: None{}
    case None{}: None{}

def sym_245.fit(m: Maybe<&1, H.I64>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+s}: fits(dt, s)
    case None{}: False{}

def sym_245.hit(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: sym_245.put(x, u)
    case _: None{}

def sym_245(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +m0 = sy_src0(x, u)
  +v = sym_245.vside(x, m0)
  sym_245.hit(Bool.and(sym_245.pat(x, u),
    sym_245.fit(sym_245.sum(sym_245.iv(sy_val(x, sym_245.cside(x, m0))),
                           sym_245.iv(sy_val(x, sym_245.cside(x, sy_src1(x, u))))),
                sy_dt1(x, v))), x, u)

# symbolic.py:247  (UPat.var("x") + UPat.var("x") * UPat.cvar("c"), lambda x,c: x*(c+1))
def sym_247.pp(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_mul_c(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_247.vv(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_mul_c(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_247.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.or(Bool.and(p_mul_c(x, a), Bool.and(Bool.not(p_mul_c(x, b)), p_same(sym_245.vside(x, a), b))),
            Bool.and(p_mul_c(x, b), Bool.and(Bool.not(p_mul_c(x, a)), p_same(sym_245.vside(x, b), a)))))

def sym_247.mk(m: Maybe<&1, O.Found>, +x: F.Folded, +p: U32, +v: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+k}:
      +s = mint_bin(k, O.OpsADD{}, sym_245.cside(x, p), O.Found.i(k))
      Some{mint_bin(s, O.OpsMUL{}, v, O.Found.i(s))}
    case None{}: None{}

# the guard `:256`/`:258` carry and this body did not:
def sym_247.iv(m: Maybe<&2, O.Const>, +dt: S.Dt) -> Bool:
  match m:
    case Some{O.CInt{i}}: fits(dt, H.i64_add(i, H.i64_of_i32(1)))
    case _: False{}

def sym_247.ok(+x: F.Folded, +u: U32) -> Bool:
  +p = sym_247.pp(x, u)
  +v = sym_247.vv(x, u)
  Bool.and(Bool.or(dt_in(DTS_INTWEAK(), sy_dt1(x, v)), p_is_const_neg1(x, sym_245.cside(x, p))),
           sym_247.iv(sy_val(x, sym_245.cside(x, p)), sy_dt1(x, v)))

def sym_247.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = sym_247.pp(x, u)
  +v = sym_247.vv(x, u)
  sym_247.mk(mint_const_like(mint_ar(sy_ar(x)), x, v, O.CInt{H.i64_of_i32(1)}), x, p, v)

def sym_247.hit(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: sym_247.put(x, u)
    case _: None{}

def sym_247(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_247.hit(Bool.and(sym_247.pat(x, u), sym_247.ok(x, u)), x, u)

def p_add2(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsADD{}), sy_nsrc_is(x, s, 2))

# `(y + x) + x -> y + x*2` (:251) and `(y + x) + x*c -> y + x*(c+1)` (:248) and
def sym_251.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_add2(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_251.z(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_add2(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_251.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.or(Bool.and(p_add2(x, a), Bool.or(p_same(sy_src0(x, a), b), p_same(sy_src1(x, a), b))),
            Bool.and(p_add2(x, b), Bool.or(p_same(sy_src0(x, b), a), p_same(sy_src1(x, b), a)))))

# `y` -- the inner ADD's OTHER operand, read against the shared node.
def sym_251.y(+x: F.Folded, +u: U32) -> U32:
  +s = sym_251.inner(x, u)
  +z = sym_251.z(x, u)
  Bool.pick(U32, p_same(sy_src0(x, s), z), sy_src1(x, s), sy_src0(x, s))

def sym_251.mk(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+k}:
      +z = sym_251.z(x, u)
      +d = mint_bin(k, O.OpsMUL{}, z, O.Found.i(k))
      Some{mint_bin(d, O.OpsADD{}, sym_251.y(x, u), O.Found.i(d))}
    case None{}: None{}

# the guard `:263` carries and this body did not: `fits(a, 2*x.vmin) and fits(a, 2*x.vmax)`.
def sym_251.fb(b: F.Bnd, +dt: S.Dt) -> Bool:
  match b:
    case F.BndInt{neg, mag}: fits(dt, H.i64_mul(H.i64_neg(neg, mag), H.i64_of_i32(2)))
    case _: Bool.not(dt_in(DTS_SINTS(), dt))

def sym_251.g1(m: Maybe<&2, F.Bnd>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+b}: sym_251.fb(b, dt)
    case None{}: False{}

def sym_251.ok(+x: F.Folded, +u: U32) -> Bool:
  +z = sym_251.z(x, u)
  +ar = sy_ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  +dt = sy_dt1(x, u)
  Bool.and(sym_251.g1(F.UOp.vmin(ar, bt, z), dt), sym_251.g1(F.UOp.vmax(ar, bt, z), dt))

def sym_251.hit(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}:
      sym_251.mk(mint_const_like(mint_ar(sy_ar(x)), x, sym_251.z(x, u), O.CInt{H.i64_of_i32(2)}), x, u)
    case _: None{}

def sym_251(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_251.hit(Bool.and(sym_251.pat(x, u), sym_251.ok(x, u)), x, u)

# symbolic.py:230 -- `commutative`, and it is a composition and not a rule of its own.
def sym_230.go(m: Maybe<&2, O.Found>) -> Maybe<&1, O.Found>:
  match m:
    case Some{f}: Some{f}
    case None{}: None{}

def sym_230(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_230.go(R.commutative(F.Folded.t(x), sy_ar(x), u))

# symbolic.py:248  ((UPat.var("y") + UPat.var("x")) + UPat.var("x") * UPat.cvar("c"),
def sym_248.prod(+x: F.Folded, +u: U32) -> U32:
  +i = sym_251.inner(x, u)
  Bool.pick(U32, p_mul_c(x, sym_251.z(x, u)), sym_251.z(x, u),
    Bool.pick(U32, p_mul_c(x, sy_src0(x, i)), sy_src0(x, i), sy_src1(x, i)))

def sym_248.v(+x: F.Folded, +u: U32) -> U32: sym_245.vside(x, sym_248.prod(x, u))

def sym_248.k(+x: F.Folded, +u: U32) -> U32: sym_245.cside(x, sym_248.prod(x, u))

def sym_248.has_src(+x: F.Folded, +s: U32, +v: U32) -> Bool:
  Bool.or(p_same(sy_src0(x, s), v), p_same(sy_src1(x, s), v))

# `y` -- the INNER add's src that is neither the shared operand nor the product.
def sym_248.y(+x: F.Folded, +u: U32) -> U32:
  +i = sym_251.inner(x, u)
  +v = sym_248.v(x, u)
  +p = sym_248.prod(x, u)
  +a = sy_src0(x, i)
  Bool.pick(U32, Bool.and(Bool.not(p_same(a, v)), Bool.not(p_same(a, p))), a, sy_src1(x, i))

def sym_248.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_251.inner(x, u)
  +z = sym_251.z(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_add2(x, i),
      Bool.or(Bool.and(p_mul_c(x, z), sym_248.has_src(x, i, sym_245.vside(x, z))),
              Bool.and(Bool.not(p_mul_c(x, z)),
                Bool.or(Bool.and(p_mul_c(x, sy_src0(x, i)), p_same(sym_245.vside(x, sy_src0(x, i)), z)),
                        Bool.and(p_mul_c(x, sy_src1(x, i)), p_same(sym_245.vside(x, sy_src1(x, i)), z)))))))

# the guard `:259`/`:261` carry and this body did not:
def sym_248.iv(m: Maybe<&2, O.Const>, +dt: S.Dt) -> Bool:
  match m:
    case Some{O.CInt{i}}: fits(dt, H.i64_add(i, H.i64_of_i32(1)))
    case _: False{}

def sym_248.fitc(c: O.Const, +dt: S.Dt) -> Bool:
  match c:
    case O.CInt{i}: fits(dt, i)
    case _: Bool.not(dt_in(DTS_SINTS(), dt))

def sym_248.bc(b: F.Bnd) -> O.Const:
  match b:
    case F.BndInt{neg, mag}: O.CInt{H.i64_neg(neg, mag)}
    case _: O.CInvalid{}

def sym_248.g1(m: Maybe<&2, O.Const>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+c}: sym_248.fitc(c, dt)
    case None{}: False{}

def sym_248.bm(m: Maybe<&2, F.Bnd>) -> Maybe<&2, O.Const>:
  match m:
    case Some{+b}: Some{sym_248.bc(b)}
    case None{}: None{}

def sym_248.g2(m: Maybe<&2, F.Bnd>, +dt: S.Dt) -> Bool:
  sym_248.g1(sym_248.bm(m), dt)

def sym_248.no_ov(+f: O.Found, +i: U32) -> Bool:
  +fd: F.Folded = F.folded(O.Found.ar(f))
  +bt = F.mm.sweep(F.Folded.ar(fd), F.Folded.t(fd))
  +dt = sy_dt1(fd, i)
  Bool.and(sym_248.g2(F.UOp.vmin(O.Found.ar(f), bt, i), dt),
           sym_248.g2(F.UOp.vmax(O.Found.ar(f), bt, i), dt))

def sym_248.done(ok: Bool, +d: O.Found, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{mint_bin(d, O.OpsADD{}, sym_248.y(x, u), O.Found.i(d))}
    case _: None{}

def sym_248.mk(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c1}:
      +v = sym_248.v(x, u)
      +c = sym_248.k(x, u)
      +s = mint_bin(c1, O.OpsADD{}, c, O.Found.i(c1))
      +d = mint_bin(s, O.OpsMUL{}, v, O.Found.i(s))
      sym_248.done(sym_248.no_ov(d, O.Found.i(d)), d, x, u)
    case None{}: None{}

def sym_248.hit(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}:
      sym_248.mk(mint_const_like(mint_ar(sy_ar(x)), x, sym_248.v(x, u), O.CInt{H.i64_of_i32(1)}), x, u)
    case _: None{}

def sym_248(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_248.hit(Bool.and(sym_248.pat(x, u),
    sym_248.iv(sy_val(x, sym_248.k(x, u)), sy_dt1(x, sym_248.v(x, u)))), x, u)

# two names and one body, because the census resolves a rule by the line its table row cites.
def sym_249(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_248(x, u)

# symbolic.py:246  ((UPat.var("y") + UPat.var("x") * UPat.cvar("c0")) + UPat.var("x") * UPat.cvar("c1"),
def sym_246.p2(+x: F.Folded, +u: U32) -> U32:
  +i = sym_251.inner(x, u)
  Bool.pick(U32, p_mul_c(x, sy_src0(x, i)), sy_src0(x, i), sy_src1(x, i))

def sym_246.y(+x: F.Folded, +u: U32) -> U32:
  +i = sym_251.inner(x, u)
  Bool.pick(U32, p_mul_c(x, sy_src0(x, i)), sy_src1(x, i), sy_src0(x, i))

def sym_246.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_251.inner(x, u)
  +z = sym_251.z(x, u)
  +p2 = sym_246.p2(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_add2(x, i),
      Bool.and(p_mul_c(x, z), Bool.and(p_mul_c(x, p2),
        p_same(sym_245.vside(x, z), sym_245.vside(x, p2))))))

# the guard `:255` carries and this body did not:
def sym_246.cv(m: Maybe<&2, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

def sym_246.add(m: Maybe<&1, H.I64>, n: Maybe<&1, H.I64>) -> Maybe<&1, H.I64>:
  match m:
    case Some{+a}:
      match n:
        case Some{+b}: Some{H.i64_add(a, b)}
        case None{}: None{}
    case None{}: None{}

def sym_246.fit(m: Maybe<&1, H.I64>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+s}: fits(dt, s)
    case None{}: False{}

def sym_246.done(ok: Bool, +d: O.Found, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{mint_bin(d, O.OpsADD{}, sym_246.y(x, u), O.Found.i(d))}
    case _: None{}

def sym_246.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +z = sym_251.z(x, u)
  +p2 = sym_246.p2(x, u)
  +s = mint_bin(mint_ar(sy_ar(x)), O.OpsADD{}, sym_245.cside(x, p2), sym_245.cside(x, z))
  +d = mint_bin(s, O.OpsMUL{}, sym_245.vside(x, z), O.Found.i(s))
  sym_246.done(Bool.and(sym_246.fit(sym_246.add(sym_246.cv(sy_val(x, sym_245.cside(x, p2))),
                                                 sym_246.cv(sy_val(x, sym_245.cside(x, z)))),
                                    sy_dt1(x, sym_245.vside(x, z))),
                        sym_248.no_ov(d, O.Found.i(d))), d, x, u)

def sym_246(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_246.pat(x, u), sym_246.mk(x, u))

# symbolic.py:254  (UPat.cvar("y") * (UPat.var("x", dtype=dtypes.weakint) + UPat.cvar("c")),
def sym_254.add_side(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, u))

def sym_254.y(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, u))

def sym_254.v(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, sym_254.add_side(x, u)))

def sym_254.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, sym_254.add_side(x, u)))

def sym_254.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sym_254.add_side(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p_const(x, u)),
      Bool.and(Bool.and(sy_is_op(x, a, O.OpsADD{}), sy_nsrc_is(x, a, 2)), Sw.ok(p_const(x, a)))))

def sym_254.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +y = sym_254.y(x, u)
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, y, sym_254.v(x, u))
  +m2 = mint_bin(m1, O.OpsMUL{}, y, sym_254.c(x, u))
  Some{mint_bin(m2, O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))}

def sym_254(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_254.pat(x, u), sym_254.mk(x, u))

# symbolic.py:266 and :269 -- two wheres under the same condition combine.
def p_where3(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsWHERE{}), sy_nsrc_is(x, s, 3))

def p_both_const(+x: F.Folded, +a: U32, +b: U32) -> Bool:
  Bool.and(sy_is_const(x, a), sy_is_const(x, b))

def sym_266.guard(+x: F.Folded, +a: U32, +b: U32) -> Bool:
  Bool.or(p_both_const(x, sy_src1(x, a), sy_src1(x, b)),
          p_both_const(x, sy_src2(x, a), sy_src2(x, b)))

def sym_266.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.and(O.GroupOp.binary(sy_op(x, u)), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(p_where3(x, a), p_where3(x, b)),
      Bool.and(p_same(sy_src0(x, a), sy_src0(x, b)), sym_266.guard(x, a, b))))

# the guard `:283` carries and this body did not: `no_overflow(m:=c.where(t+tt, f+ff))`.
def sym_266.done(ok: Bool, +w: O.Found) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{w}
    case _: None{}

def sym_266.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  +l = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sy_src1(x, a), sy_src1(x, b))
  +r = mint_bin(l, sy_op(x, u), sy_src2(x, a), sy_src2(x, b))
  +w = mint_where(r, sy_src0(x, a), O.Found.i(l), O.Found.i(r))
  sym_266.done(sym_248.no_ov(w, O.Found.i(w)), w)

def sym_266(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_266.pat(x, u), sym_266.mk(x, u))

# symbolic.py:269  ((UPat.var("y") + UPat.var("c").where(UPat.var("t"), UPat.var("f")))
def sym_269.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_add2(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_269.w2(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_add2(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

# `w1` -- the where INSIDE the add, and `y` the src beside it.
def sym_269.w1(+x: F.Folded, +u: U32) -> U32:
  +i = sym_269.inner(x, u)
  Bool.pick(U32, p_where3(x, sy_src0(x, i)), sy_src0(x, i), sy_src1(x, i))

def sym_269.y(+x: F.Folded, +u: U32) -> U32:
  +i = sym_269.inner(x, u)
  Bool.pick(U32, p_where3(x, sy_src0(x, i)), sy_src1(x, i), sy_src0(x, i))

def sym_269.pat(+x: F.Folded, +u: U32) -> Bool:
  +w1 = sym_269.w1(x, u)
  +w2 = sym_269.w2(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(p_add2(x, sym_269.inner(x, u)), p_where3(x, w1)),
      Bool.and(p_where3(x, w2),
        Bool.and(p_same(sy_src0(x, w1), sy_src0(x, w2)), sym_266.guard(x, w1, w2)))))

def sym_269.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +w1 = sym_269.w1(x, u)
  +w2 = sym_269.w2(x, u)
  +l = mint_bin(mint_ar(sy_ar(x)), O.OpsADD{}, sy_src1(x, w1), sy_src1(x, w2))
  +r = mint_bin(l, O.OpsADD{}, sy_src2(x, w1), sy_src2(x, w2))
  +c = mint_where(r, sy_src0(x, w1), O.Found.i(l), O.Found.i(r))
  Some{mint_bin(c, O.OpsADD{}, sym_269.y(x, u), O.Found.i(c))}

def sym_269(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_269.pat(x, u), sym_269.mk(x, u))

# symbolic.py:272  (UPat.var("c").where(UPat.var("t"), 0) + UPat.var("c").where(0, UPat.var("f")),
def sym_272.half(+x: F.Folded, +a: U32, +b: U32) -> Bool:
  Bool.and(Bool.and(p_where3(x, a), p_where3(x, b)),
    Bool.and(p_same(sy_src0(x, a), sy_src0(x, b)),
      Bool.and(p_is_const_0(x, sy_src2(x, a)), p_is_const_0(x, sy_src1(x, b)))))

def sym_272.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.or(sym_272.half(x, a, b), sym_272.half(x, b, a)))

def sym_272.a(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_272.half(x, sy_src0(x, u), sy_src1(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_272.b(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_272.half(x, sy_src0(x, u), sy_src1(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_272(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sym_272.a(x, u)
  sy_tri_f(sym_272.pat(x, u),
    Some{mint_where(mint_ar(sy_ar(x)), sy_src0(x, a), sy_src1(x, a), sy_src2(x, sym_272.b(x, u)))})

# symbolic.py:284 -- `x.alu(op, c1).alu(op, c2) -> x.alu(op, c1.alu(op, c2))`, ONE RULE PER
def assoc_op(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}: True{}
    case O.OpsMAX{}: True{}
    case O.OpsMUL{}: True{}
    case O.OpsOR{} : True{}
    case O.OpsXOR{}: True{}
    case _         : False{}

def sym_284.v(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, u))

def sym_284.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, u))

# `x.alu(op, c1)` -- AN ALU OF THE SAME OP WITH A CONST SIDE.
def sym_284.alu2c(+x: F.Folded, +s: U32, op: O.Op) -> Bool:
  Bool.and(Bool.and(O.eq_op(sy_op(x, s), op), sy_nsrc_is(x, s, 2)), Sw.ok(p_const(x, s)))

# the inner alu is the root's non-CONST side, and it is found by asking which side is an
# `alu2c`. Two `Bool.pick`s that agree, because both must answer for the same side.
def sym_284.inner(+x: F.Folded, +u: U32, op: O.Op) -> U32:
  Bool.pick(U32, sym_284.alu2c(x, sy_src0(x, u), op), sy_src0(x, u), sy_src1(x, u))

def sym_284.outer(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_284.alu2c(x, sy_src0(x, u), sy_op(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_284.pat(+x: F.Folded, +u: U32) -> Bool:
  +op = sy_op(x, u)
  +i = sym_284.inner(x, u, op)
  Bool.and(Bool.and(assoc_op(op), sy_nsrc_is(x, u, 2)),
    Bool.and(sym_284.alu2c(x, i, op), sy_is_const(x, sym_284.outer(x, u))))

def sym_284.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_284.inner(x, u, sy_op(x, u))
  # the root's other side is the constant itself: `outer` already answers the node, and
  # running `c` over it again read a CONST as an ALU and rendered a slot that does not exist.
  +k = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sym_284.c(x, i), sym_284.outer(x, u))
  Some{mint_bin(k, sy_op(x, u), sym_284.v(x, i), O.Found.i(k))}

# the guard these six arms were missing:
#   fits(x, exec_alu(f.op, dtypes.weakint, [c1.vmin, c2.vmin]))
# Two-stage folding replaces `(x op c1) op c2` with `x op (c1 op c2)` and computes the combined
# constant in WEAKINT. When that constant does not fit `x`'s dtype the rewrite changes the answer,
# so CPython refuses. MEASURED WITHOUT IT on int8: `(x+1)+127` folded to `x + (1+127)`, and 128 does
def sym_284.gk(m: Maybe<&1, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

def sym_284.gf(m: Maybe<&1, H.I64>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+s}: fits(dt, s)
    case None{}: False{}

def sym_284.guard(+x: F.Folded, +u: U32) -> Bool:
  +op = sy_op(x, u)
  +i = sym_284.inner(x, u, op)
  sym_284.gf(sym_284.gk(exec_alu2(op, S.weakint(), sy_maybe_c2(sy_val(x, sym_284.c(x, i))),
                                  sy_maybe_c2(sy_val(x, sym_284.outer(x, u))), True{})),
             sy_dt1(x, sym_284.v(x, i)))

def sym_284(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(Bool.and(sym_284.pat(x, u), sym_284.guard(x, u)), sym_284.mk(x, u))

# ---- `symbolic.py:129`, `fold_add_divmod_recombine` -----------------------------
# `pop_const(op)` -- ops.py:1082 -- DEFAULTS TO `ADD` AND NOT `MUL`: a node that does not pop
def pc_id(op: O.Op) -> H.I64:
  Bool.pick(H.I64, O.eq_op(op, O.OpsMUL{}), H.i64_of_i32(1), H.i64_of_i32(0))

def pc_v.go(m: Maybe<&1, O.Const>, op: O.Op) -> H.I64:
  match m:
    case Some{O.CInt{i}}: i
    case _: pc_id(op)

def pc_v(+ar: O.Arena, +i: U32, +op: O.Op) -> H.I64: pc_v.go(O.UOp.pop_const_val(ar, i, op), op)

def pc_n(+ar: O.Arena, +i: U32, op: O.Op) -> U32:
  Bool.pick(U32, O.UOp.pop_const_hits(ar, i, op), O.Arena.src0(ar, i), i)

def pc_cv.some(m: Maybe<&1, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

# the value of a CONST node itself. `pop_const_val` reads the second SRC of an alu, so on a
def cval.go(m: Maybe<&1, O.Const>) -> H.I64:
  match m:
    case Some{O.CInt{i}}: i
    case _: H.i64_of_i32(0)

def cval(+ar: O.Arena, +i: U32) -> H.I64: cval.go(O.UOp.ssimplify_val(ar, i))

def pc_cv(+ar: O.Arena, +i: U32, op: O.Op) -> Maybe<&1, H.I64>:
  Bool.pick(Maybe<&1, H.I64>,
    Bool.and(O.eq_op(O.Arena.op(ar, i), op),
             O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{})),
    pc_cv.some(O.UOp.ssimplify_val(ar, O.Arena.src(ar, i, 1))), None{})

# `_quotient_base(q, base, div)` -- divandmod.py:32-42: `base` or `base - k*div`, and the second
# MINTS. `k*div` is a PYTHON INT product, so the answer is one `SUB(base, CONST(k*div))`.
def qb.sub(m: Maybe<&1, O.Found>, +base: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsSUB{}, base, O.Found.i(c))}
    case None{}: None{}

def qb.res2(zero: Bool, +f: O.Found, +k: H.I64, +D: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match zero:
    case True{} : Some{O.Found{O.Found.ar(f), base}}
    case False{}: qb.sub(mint_const_like(f, x, base, O.CInt{H.i64_mul(k, D)}), base)

def qb.res(+f: O.Found, +k: H.I64, +D: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  qb.res2(Cmp.is_eq(H.i64_cmp(k, H.i64_of_i32(0))), f, k, D, base, x)

def qb.end2(ok: Bool, +ar: O.Arena, +s: H.I64, +base: U32, +t: H.I64, +D: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : qb.res(mint_ar(ar), H.i64_sub(H.i64_div(t, D), s), D, base, x)
    case False{}: None{}

def qb.end(+ar: O.Arena, +q0: U32, +base: U32, +s: H.I64, +num: U32, +a: H.I64, +D: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  +t = H.i64_add(H.i64_sub(pc_v(ar, num, O.OpsADD{}), pc_v(ar, O.Arena.src0(ar, q0), O.OpsADD{})), a)
  qb.end2(Bool.and(U32.is_eq(pc_n(ar, num, O.OpsADD{}), pc_n(ar, O.Arena.src0(ar, q0), O.OpsADD{})),
                   Cmp.is_eq(H.i64_cmp(H.i64_mod(t, D), H.i64_of_i32(0)))),
          ar, s, base, t, D, x)

def qb.b2(eq: Bool, +ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, num0: U32, a0: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  match eq:
    case True{} : qb.end(ar, q0, base, s, num0, a0, div, x)
    case False{}: None{}

def qb.b(+ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, +qv: H.I64, num0: U32, a0: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  qb.b2(Cmp.is_eq(H.i64_cmp(qv, div)), ar, q0, base, div, s, num0, a0, x)

def qb.a2(ok: Bool, +ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, +qv: H.I64, num0: U32, a0: H.I64, +c: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : qb.end(ar, q0, base, s, pc_n(ar, num0, O.OpsADD{}), c, H.i64_mul(c, div), x)
    case False{}: qb.b(ar, q0, base, div, s, qv, num0, a0, x)

def qb.a(+ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, +qv: H.I64, num0: U32, a0: H.I64, +c: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  qb.a2(Bool.and(Bool.not(H.i64_is_neg(div)), Cmp.is_eq(H.i64_cmp(qv, H.i64_mul(c, div)))),
        ar, q0, base, div, s, qv, num0, a0, c, x)

def qb.mc(mc: Maybe<&1, H.I64>, +ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, +qv: H.I64, num0: U32, a0: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  match mc:
    case Some{+c}: qb.a(ar, q0, base, div, s, qv, num0, a0, c, x)
    case None{}  : qb.b(ar, q0, base, div, s, qv, num0, a0, x)

def qb.mqv(mqv: Maybe<&1, H.I64>, +ar: O.Arena, +q0: U32, +base: U32, +div: H.I64, +s: H.I64, +x: F.Folded) -> Maybe<&1, O.Found>:
  match mqv:
    case Some{+qv}:
      +num0 = pc_n(ar, base, O.OpsADD{})
      qb.mc(pc_cv(ar, num0, O.OpsDIV{}), ar, q0, base, div, s, qv, num0, pc_v(ar, base, O.OpsADD{}), x)
    case None{}: None{}

def qb.go(+x: F.Folded, +q: U32, +base: U32, +div: H.I64) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +q0 = pc_n(ar, q, O.OpsADD{})
  qb.mqv(pc_cv(ar, q0, O.OpsDIV{}), ar, q0, base, div, pc_v(ar, q, O.OpsADD{}), x)

# `(b*mul).usum(*rest)` folds ADD left to right over the answer and the surviving terms.
def sym_129.rest(ts: List<&2, U32>, +it: U32, +v: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match ts:
    case Nil{}: acc
    case +t <> r:
      sym_129.rest(r, it, v, Bool.pick(List<&2, U32>, Bool.or(U32.is_eq(t, it), U32.is_eq(t, v)),
        acc, List.append(&2, U32, acc, [t])))

def sym_129.step(m: Maybe<&1, O.Found>, +t: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+a}: Some{mint_bin(a, O.OpsADD{}, O.Found.i(a), t)}
    case None{}: None{}

def sym_129.sum(ts: List<&2, U32>, +f: O.Found, +x: F.Folded, first: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match ts:
    case Nil{}: first
    case t <> rest: sym_129.sum(rest, f, x, sym_129.step(first, t))

def sym_129.on(m: Maybe<&1, O.Found>, rest: List<&2, U32>, +b: O.Found, +x: F.Folded, +d: U32, +mul: H.I64) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}:
      +p = mint_bin(c, O.OpsMUL{}, O.Found.i(b), O.Found.i(c))
      sym_129.sum(rest, p, x, Some{p})
    case None{}: None{}

def sym_129.build(b: Maybe<&1, O.Found>, rest: List<&2, U32>, +x: F.Folded, +mul: H.I64, +d: U32) -> Maybe<&1, O.Found>:
  match b:
    case Some{+f}: sym_129.on(mint_const_like(f, x, d, O.CInt{mul}), rest, f, x, d, mul)
    case None{}: None{}

def sym_129.mk2c(m: Maybe<&1, O.Found>, +rest: List<&2, U32>, +x: F.Folded, +b: O.Found, +mul: H.I64) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}:
      +r = mint_bin(c, O.OpsMOD{}, O.Found.i(b), O.Found.i(c))
      sym_129.build(Some{r}, rest, x, mul, O.Found.i(r))
    case None{}: None{}

def sym_129.mk2(m: Maybe<&1, O.Found>, +rest: List<&2, U32>, +x: F.Folded, +b: O.Found, +mul: H.I64, +div: H.I64, +d0: H.I64) -> Maybe<&1, O.Found>:
  match m:
    case Some{+z}: sym_129.mk2c(mint_const_like(z, x, O.Found.i(b), O.CInt{H.i64_mul(div, d0)}), rest, x, b, mul)
    case None{}: None{}

def sym_129.jalt3(b: Maybe<&1, O.Found>, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded, +d0: H.I64) -> Maybe<&1, O.Found>:
  match b:
    case Some{+f}: sym_129.mk2(Some{f}, sym_129.rest(terms, it, v, Nil{}), x, f, mul, div, d0)
    case None{}  : None{}

def sym_129.jalt2(go: Bool, +q: U32, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded, +d0: H.I64) -> Maybe<&1, O.Found>:
  match go:
    case True{} : sym_129.jalt3(qb.go(x, O.Arena.src0(F.Folded.ar(x), q), base, div), v, terms, it, div, mul, base, x, d0)
    case False{}: None{}

def sym_129.jalt1(md: Maybe<&1, H.I64>, +q: U32, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match md:
    case Some{+d0}: sym_129.jalt2(Bool.not(H.i64_is_neg(d0)), q, v, terms, it, div, mul, base, x, d0)
    case None{}   : None{}

def sym_129.jalt(+q: U32, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  sym_129.jalt1(pc_cv(F.Folded.ar(x), q, O.OpsMOD{}), q, v, terms, it, div, mul, base, x)

def sym_129.jqq(b: Maybe<&1, O.Found>, +q: U32, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match b:
    case Some{+f}: sym_129.build(Some{f}, sym_129.rest(terms, it, v, Nil{}), x, mul, base)
    case None{}  : sym_129.jalt(q, v, terms, it, div, mul, base, x)

def sym_129.jq(+v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  +q = pc_n(F.Folded.ar(x), v, O.OpsMUL{})
  sym_129.jqq(qb.go(x, q, base, div), q, v, terms, it, div, mul, base, x)

def sym_129.jok(ok: Bool, v: U32, terms: List<&2, U32>, it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : sym_129.jq(v, terms, it, div, mul, base, x)
    case False{}: None{}

def sym_129.jone(+v: U32, +terms: List<&2, U32>, +it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  sym_129.jok(Bool.and(Bool.not(U32.is_eq(v, it)),
                       Cmp.is_eq(H.i64_cmp(pc_v(ar, v, O.OpsMUL{}), H.i64_mul(div, mul)))),
              v, terms, it, div, mul, base, x)

def sym_129.keep2(m: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match m:
    case Some{+f}: Some{f}
    case None{}  : None{}

def sym_129.keep(acc: Maybe<&1, O.Found>, m: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match acc:
    case Some{+f}: Some{f}
    case None{}  : sym_129.keep2(m)

def sym_129.jloop(vs: List<&2, U32>, +terms: List<&2, U32>, +it: U32, +div: H.I64, +mul: H.I64, +base: U32, +x: F.Folded, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match vs:
    case Nil{}: acc
    case +v <> rest:
      sym_129.jloop(rest, terms, it, div, mul, base, x,
        sym_129.keep(acc, sym_129.jone(v, terms, it, div, mul, base, x)))

def sym_129.ione2(go: Bool, +u: U32, +mod: U32, +terms: List<&2, U32>, +x: F.Folded) -> Maybe<&1, O.Found>:
  match go:
    case True{}:
      +ar = F.Folded.ar(x)
      sym_129.jloop(terms, terms, u, cval(ar, O.Arena.src(ar, mod, 1)),
        pc_v(ar, u, O.OpsMUL{}), O.Arena.src0(ar, mod), x, None{})
    case False{}: None{}

def sym_129.ione(+u: U32, +terms: List<&2, U32>, +x: F.Folded) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +mod = pc_n(ar, u, O.OpsMUL{})
  sym_129.ione2(Bool.and(O.eq_op(O.Arena.op(ar, mod), O.OpsMOD{}),
                         O.eq_op(O.Arena.op(ar, O.Arena.src(ar, mod, 1)), O.OpsCONST{})),
                u, mod, terms, x)

def sym_129.iloop(ts: List<&2, U32>, +terms: List<&2, U32>, +x: F.Folded, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match ts:
    case Nil{}: acc
    case +u <> rest:
      sym_129.iloop(rest, terms, x, sym_129.keep(acc, sym_129.ione(u, terms, x)))

def sym_129.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsADD{}, 2, p_intweak(x, u))

def sym_129.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +terms = O.UOp.split_uop(U32.to_nat(O.Arena.next(F.Folded.ar(x))), F.Folded.ar(x), u, O.OpsADD{})
  sym_129.iloop(terms, terms, x, None{})

def sym_129(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_129.pat(x, u), sym_129.run(x, u))

def sy_is_float_const.go(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CFloat{f}}: True{}
    case _: False{}

def sy_is_float_const(+x: F.Folded, +u: U32) -> Bool: sy_is_float_const.go(sy_val(x, u))

def p_not_float_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.not(sy_is_float_const(x, u))

# symbolic.py:178  (UPat.var("x") * 0,
def sym_178.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), Bool.and(p_is_const_0(x, Sw.a(p)), p_not_float_const(x, Sw.b(p)))))

def sym_178(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sy_tri(sym_178.pat(x, u, p), sy_const_like(x, Sw.b(p), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:181  (UPat((Ops.CAST, Ops.BITCAST), name="root"),
def sym_181.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_CASTS()), sy_nsrc_is(x, u, 1)),
    O.eq_dt(sy_dt1(x, u), sy_dt1(x, sy_src0(x, u))))

def sym_181(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_181.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:183  (UPat(Ops.BITCAST, name="root",
def p_bool_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_const(x, u), sy_dt_is(x, u, S.boolean()))

def sym_183.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsBITCAST{}, 1, p_bool_const(x, sy_src0(x, u)))

def sym_183(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_183.pat(x, u), fold_bitcast(x, u, sy_src0(x, u)))

# symbolic.py:196  (UPat.var("x").cast(dtypes.bool), lambda x: x != 0)
def sym_189.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCAST{}, 1, p_cast_at(x, u, S.boolean()))

def sym_189.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +z = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(0)})
  +eq = mint_bin(z, O.OpsCMPEQ{}, sy_src0(x, u), O.Found.i(z))
  mint_not(eq, O.Found.i(eq))

def sym_189.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_189.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_189(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_189.hit(sym_189.pat(x, u), x, u)

# symbolic.py:191  (UPat.var("x").alu(Ops.POW, UPat.cvar("c")), simplify_pow)
def p_const_neg.go(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CInt{i}}: H.i64_is_neg(i)
    case _: False{}

def p_const_neg(+x: F.Folded, +u: U32) -> Bool: p_const_neg.go(sy_val(x, u))

def p_const_pos(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.not(p_const_neg(x, u)), Bool.not(p_is_const_0(x, u)))

# symbolic.py:253  (-1 * (UPat.var("x") + UPat.cvar("c")), lambda x,c: (-x)+(-c))
def sym_253.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_253.neg(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_253.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_253.inner(x, u)
  # the -1 is a requirement and not a side-check: the first version only said the inner side
  # order and `:254`'s case caught it.
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_is_const_neg1(x, sym_253.neg(x, u)),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)), Sw.ok(p_const(x, i)))))

def sym_253.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_253.inner(x, u)
  +n = sym_253.neg(x, u)
  +c = Sw.a(p_const(x, i))
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, Sw.b(p_const(x, i)), n)
  +m2 = mint_bin(m1, O.OpsMUL{}, c, n)
  Some{mint_bin(m2, O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))}

def sym_253(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_253.pat(x, u), sym_253.mk(x, u))

# symbolic.py:292  ((UPat.var("x", dtype=dtypes.weakint)//UPat.cvar("d"))<UPat.cvar("c"),
def sym_292.put(m: Maybe<&1, O.Found>, neg: Bool, +d: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+f}:
      match neg:
        case True{} : Some{mint_bin(f, O.OpsCMPLT{}, O.Found.i(f), d)}
        case False{}: Some{mint_bin(f, O.OpsCMPLT{}, d, O.Found.i(f))}
    case None{}: None{}

def sym_292.emit(v: H.I64, neg: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +d = sy_src0(x, sy_src0(x, u))
  sym_292.put(mint_const_like(mint_ar(sy_ar(x)), x, d, O.CInt{v}), neg, d)

def sym_292.d(ma: Maybe<&2, O.Const>, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ma:
    case Some{O.CInt{i}}: sym_292.emit(H.i64_mul(i, j), H.i64_is_neg(j), x, u)
    case _: None{}

def sym_292.c(mb: Maybe<&2, O.Const>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match mb:
    case Some{O.CInt{j}}: sym_292.d(sy_val(x, sy_src1(x, sy_src0(x, u))), j, x, u)
    case _: None{}

def sym_292.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  +d = sy_src1(x, i)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_cint(sy_val(x, sy_src1(x, u))),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsDIV{}), sy_nsrc_is(x, i, 2)),
        Bool.and(sy_is_cint(sy_val(x, d)), Bool.not(p_is_const_0(x, d))))))

def sym_292(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_292.pat(x, u), sym_292.c(sy_val(x, sy_src1(x, u)), x, u))

# symbolic.py:460  (UPat(Ops.STORE, src=(UPat(Ops.INDEX, name="index"),
def sym_460.pat(+x: F.Folded, +u: U32) -> Bool:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_op(x, k, O.OpsINDEX{}), sy_nsrc_ge(x, k, 2)),
      Bool.and(Bool.and(sy_is_op(x, v, O.OpsWHERE{}), sy_nsrc_is(x, v, 3)), p_invalid(x, sy_src2(x, v)))))

def sym_460.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  +g = mint_where(mint_ar(sy_ar(x)), sy_src0(x, v), sy_src1(x, k), sy_src2(x, v))
  +i = mint_bin(g, O.OpsINDEX{}, sy_src0(x, k), O.Found.i(g))
  Some{mint_bin(i, O.OpsSTORE{}, O.Found.i(i), sy_src1(x, v))}

def sym_460(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_460.pat(x, u), sym_460.mk(x, u))

# symbolic.py:471  (-1 * (UPat.var("x") + UPat.var("y")), lambda x,y: (-x)+(-y))
def sym_471.i(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_471.n(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_471.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_471.i(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_is_const_neg1(x, sym_471.n(x, u)),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        Bool.not(Sw.ok(p_const(x, i))))))

def sym_471.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_471.i(x, u)
  +n = sym_471.n(x, u)
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, sy_src0(x, i), n)
  +m2 = mint_bin(m1, O.OpsMUL{}, sy_src1(x, i), n)
  Some{mint_bin(m2, O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))}

def sym_471(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_471.pat(x, u), sym_471.mk(x, u))

# symbolic.py:473  ((UPat.var("x", dtypes.weakint) + UPat.var("y")) * UPat.cvar("c"),
def sym_473.inner(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, u))

def sym_473.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, u))

def sym_473.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_473.inner(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p_const(x, u)),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        p_weakint(x, sy_src0(x, i)))))

# the guard `:485` carries and this body did not:
def sym_473.fb(b: F.Bnd, +dt: S.Dt, +cv: H.I64) -> Bool:
  match b:
    case F.BndInt{neg, mag}: fits(dt, H.i64_mul(H.i64_neg(neg, mag), cv))
    # an INFINITE or floating bound: `fits` is `dtype not in sints or min <= v <= max`, so it holds
    case _: Bool.not(dt_in(DTS_SINTS(), dt))

def sym_473.g1(m: Maybe<&2, F.Bnd>, +dt: S.Dt, +cv: H.I64) -> Bool:
  match m:
    case Some{+b}: sym_473.fb(b, dt, cv)
    case None{}: False{}

def sym_473.cv0(m: Maybe<&2, O.Const>) -> H.I64:
  match m:
    case Some{O.CInt{i}}: i
    case _: H.i64_of_i32(1)

def sym_473.hit(ok: Bool, +m1: O.Found, +m2: O.Found) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{mint_bin(m2, O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))}
    case _: None{}

def sym_473.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_473.inner(x, u)
  +c = sym_473.c(x, u)
  +ar = sy_ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  +dt = sy_dt1(x, i)
  +cv = sym_473.cv0(sy_val(x, c))
  +ok = Bool.and(Bool.and(sym_473.g1(F.UOp.vmin(ar, bt, sy_src0(x, i)), dt, cv),
                          sym_473.g1(F.UOp.vmax(ar, bt, sy_src0(x, i)), dt, cv)),
                 Bool.and(sym_473.g1(F.UOp.vmin(ar, bt, sy_src1(x, i)), dt, cv),
                          sym_473.g1(F.UOp.vmax(ar, bt, sy_src1(x, i)), dt, cv)))
  +m1 = mint_bin(mint_ar(ar), O.OpsMUL{}, sy_src0(x, i), c)
  +m2 = mint_bin(m1, O.OpsMUL{}, sy_src1(x, i), c)
  sym_473.hit(ok, m1, m2)

def sym_473(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_473.pat(x, u), sym_473.mk(x, u))

# symbolic.py:467  (UPat.store(UPat(Ops.INDEX, name="index"), UPat.load(UPat(Ops.INDEX, name="index"))),
def p_load_of(+x: F.Folded, +s: U32, +k: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsLOAD{}),
    Bool.and(sy_nsrc_ge(x, s, 1), p_same(sy_src0(x, s), k)))

def sym_453.pat(+x: F.Folded, +u: U32) -> Bool:
  +k = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, k, O.OpsINDEX{}), p_load_of(x, sy_src1(x, u), k)))

# the answer is `AFTER(NOOP, index)` -- the INDEX and not the STORE's srcs. the old PIN's rule
def sym_453.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +n = O.UOp.new(sy_ar(x), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  Some{O.UOp.new(O.Found.ar(n), O.OpsAFTER{},
    List.append(&2, U32, [O.Found.i(n)], [sy_src0(x, u)]), O.ANone{}, O.TNone{})}

def sym_453(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_453.pat(x, u), sym_453.mk(x, u))

# symbolic.py:454  (UPat.store(UPat(Ops.INDEX, name="index"),
def sym_454.pat(+x: F.Folded, +u: U32) -> Bool:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_op(x, k, O.OpsINDEX{}), sy_nsrc_ge(x, k, 2)),
      Bool.and(Bool.and(sy_is_op(x, v, O.OpsWHERE{}), sy_nsrc_is(x, v, 3)),
        p_load_of(x, sy_src2(x, v), k))))

def sym_454.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  +z = O.UOp.new(sy_ar(x), O.OpsCONST{}, Nil{}, O.APy{O.CInvalid{}}, O.TNone{})
  +g = mint_where(z, sy_src0(x, v), sy_src1(x, k), O.Found.i(z))
  +i = mint_bin(g, O.OpsINDEX{}, sy_src0(x, k), O.Found.i(g))
  Some{mint_bin(i, O.OpsSTORE{}, O.Found.i(i), sy_src1(x, v))}

def sym_454(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_454.pat(x, u), sym_454.mk(x, u))

# symbolic.py:471  (UPat.store(UPat(Ops.INDEX, name="index"),
def sym_471x.pat(+x: F.Folded, +u: U32) -> Bool:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_op(x, k, O.OpsINDEX{}), sy_nsrc_ge(x, k, 2)),
      Bool.and(Bool.and(sy_is_op(x, v, O.OpsWHERE{}), sy_nsrc_is(x, v, 3)),
        p_load_of(x, sy_src1(x, v), k))))

def sym_471x.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +k = sy_src0(x, u)
  +v = sy_src1(x, u)
  +z = O.UOp.new(sy_ar(x), O.OpsCONST{}, Nil{}, O.APy{O.CInvalid{}}, O.TNone{})
  +n = mint_not(z, sy_src0(x, v))
  +g = mint_where(n, O.Found.i(n), sy_src1(x, k), O.Found.i(z))
  +i = mint_bin(g, O.OpsINDEX{}, sy_src0(x, k), O.Found.i(g))
  Some{mint_bin(i, O.OpsSTORE{}, O.Found.i(i), sy_src2(x, v))}

def sym_471x(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_471x.pat(x, u), sym_471x.mk(x, u))

# symbolic.py:280  (UPat.maximum(UPat.var("x"), UPat.var("y")),
def sym_280.bt(+x: F.Folded) -> F.BTable: F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))

def sym_280.ge(a: Maybe<&2, F.Bnd>, b: Maybe<&2, F.Bnd>) -> Bool:
  match a:
    case Some{+av}:
      match b:
        case Some{+bv}: Bool.not(F.bnd.lt(av, bv))
        case None{}: False{}
    case None{}: False{}

def sym_280.first(+x: F.Folded, +u: U32, +bt: F.BTable) -> Bool:
  +ar = F.Folded.ar(x)
  sym_280.ge(F.UOp.vmin(ar, bt, sy_src0(x, u)), F.UOp.vmax(ar, bt, sy_src1(x, u)))

# `a <= b` IS `NOT (b < a)`: the second guard is `x.vmax <= y.vmin`, and spelling it as
# `ge(x.vmax, y.vmin)` inverted it -- `(max x c200)` declined where CPython answers `c200`.
def sym_280.le(a: Maybe<&2, F.Bnd>, b: Maybe<&2, F.Bnd>) -> Bool:
  match a:
    case Some{+av}:
      match b:
        case Some{+bv}: Bool.not(F.bnd.lt(bv, av))
        case None{}: False{}
    case None{}: False{}

def sym_280.second(+x: F.Folded, +u: U32, +bt: F.BTable) -> Bool:
  +ar = F.Folded.ar(x)
  sym_280.le(F.UOp.vmax(ar, bt, sy_src0(x, u)), F.UOp.vmin(ar, bt, sy_src1(x, u)))

def sym_280.pick(+x: F.Folded, +u: U32, +bt: F.BTable) -> U32:
  Bool.pick(U32, sym_280.first(x, u, bt), sy_src0(x, u),
    Bool.pick(U32, sym_280.second(x, u, bt), sy_src1(x, u), sy_src0(x, u)))

def sym_280.pat(+x: F.Folded, +u: U32) -> Bool:
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMAX{}), sy_nsrc_is(x, u, 2)),
    Bool.or(sym_280.first(x, u, bt), sym_280.second(x, u, bt)))

def sym_280(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri_u(sym_280.pat(x, u), sym_280.pick(x, u, sym_280.bt(x)))

# A BOUND AS A CONST, `None{}` at infinity: a collapsed bound is a value and an infinite one is
# not. The sign is carried by `BndInt.neg` and the magnitude by `mag`, so the value is `-mag`.
def bnd_const(b: F.Bnd) -> Maybe<&2, O.Const>:
  match b:
    case F.BndInt{neg, +mag}: Some{O.CInt{Bool.pick(H.I64, neg, H.i64_sub(H.i64_of_i32(0), mag), mag)}}
    case F.BndFlt{v}: Some{O.CFloat{v}}
    case F.Bnd{i}: None{}

def p_const_or_cast(+x: F.Folded, +s: U32) -> Bool:
  Bool.or(sy_is_const(x, s), is_cast_const(x, s))

# each match is on its own parameter: Bend refuses a `match` whose scrutinee is a call, so the
# vmin and the vmax are read by two defs that take the `Maybe` they are handed.
def sym_276.same2(m: Maybe<&2, F.Bnd>, +a: F.Bnd) -> Bool:
  match m:
    case Some{+b}: F.bnd.eq(a, b)
    case None{}: False{}

def sym_276.same1(m: Maybe<&2, F.Bnd>, +ar: O.Arena, +bt: F.BTable, +u: U32) -> Bool:
  match m:
    case Some{+a}: sym_276.same2(F.UOp.vmax(ar, bt, u), a)
    case None{}: False{}

def sym_276.same(+ar: O.Arena, +bt: F.BTable, +u: U32) -> Bool:
  sym_276.same1(F.UOp.vmin(ar, bt, u), ar, bt, u)

def sym_276.vc(m: Maybe<&2, F.Bnd>) -> Maybe<&2, O.Const>:
  match m:
    case Some{+b}: bnd_const(b)
    case None{}: None{}

# symbolic.py:287  (UPat({Ops.CMPLT, Ops.CMPEQ, Ops.DIV, Ops.MOD, Ops.PARAM, Ops.SPECIAL},
def op_274(op: O.Op) -> Bool:
  match op:
    case O.OpsCMPLT{}   : True{}
    case O.OpsCMPEQ{}   : True{}
    case O.OpsDIV{}: True{}
    case O.OpsMOD{}: True{}
    case O.OpsPARAM{}   : True{}
    case O.OpsSPECIAL{} : True{}
    case _              : False{}

# TODO(p2): `(floormod x c1)` DOES NOT FIRE and CPython answers `c0`. MEASURED 2026-11-03:
def sym_274.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(op_274(sy_op(x, u)), Bool.not(O.eq_dt(sy_dt1(x, u), S.void()))),
    sym_276.same(F.Folded.ar(x), sym_280.bt(x), u))

def sym_274(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  sy_tri_f(sym_274.pat(x, u),
    mint_const_v(sym_276.vc(F.UOp.vmin(ar, bt, u)), mint_ar(ar), sy_dt1(x, u)))

# symbolic.py:276  (UPat(Ops.RANGE, src=(UPat.cvar().or_casted(),), name="x"),
def sym_276.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_ge(x, u, O.OpsRANGE{}, 1, Bool.and(p_const_or_cast(x, sy_src0(x, u)), sym_276.same(F.Folded.ar(x), sym_280.bt(x), u)))

def sym_276(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  sy_tri_f(sym_276.pat(x, u), mint_const_v(sym_276.vc(F.UOp.vmin(ar, bt, u)), mint_ar(ar), sy_dt1(x, u)))

# divandmod.py:101 -- `(x//c + a)//d -> (x + a*c)//(c*d)` for `c>0, d>0`.
# `div_and_mod_symbolic` is composed at the END of `sym` (`symbolic.py:326`:
def dm_101.i(+x: F.Folded, +u: U32) -> U32: sy_src0(x, u)

def dm_101.v(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, dm_101.i(x, u)))

def dm_101.a(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, dm_101.i(x, u)))

def dm_101.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = dm_101.i(x, u)
  +v = dm_101.v(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_const(x, sy_src1(x, u)), p_const_pos(x, sy_src1(x, u))),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        Bool.and(Sw.ok(p_const(x, i)),
          Bool.and(Bool.and(sy_is_op(x, v, O.OpsDIV{}), sy_nsrc_is(x, v, 2)),
            sy_is_const(x, sy_src1(x, v)))))))

def dm_101.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +v = dm_101.v(x, u)
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, dm_101.a(x, u), sy_src1(x, v))
  +s1 = mint_bin(m1, O.OpsADD{}, sy_src0(x, v), O.Found.i(m1))
  +m2 = mint_bin(s1, O.OpsMUL{}, sy_src1(x, v), sy_src1(x, u))
  Some{mint_bin(m2, O.OpsDIV{}, O.Found.i(s1), O.Found.i(m2))}

def dm_101(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(dm_101.pat(x, u), dm_101.mk(x, u))

# divandmod.py:103 -- `(x+c)//d -> (x + c%d)//d + c//d` and `(x+c)%d -> (x + c%d)%d`, for any
def dm_103.n(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, sy_src0(x, u)))

def dm_103.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, sy_src0(x, u)))

def dm_103.pat(+x: F.Folded, +u: U32) -> Bool:
  +n = sy_src0(x, u)
  Bool.and(Bool.or(sy_is_op(x, u, O.OpsDIV{}), sy_is_op(x, u, O.OpsMOD{})),
    Bool.and(Bool.and(sy_nsrc_is(x, u, 2), sy_is_const(x, sy_src1(x, u))),
      Bool.and(Bool.and(sy_is_op(x, n, O.OpsADD{}), sy_nsrc_is(x, n, 2)), Sw.ok(p_const(x, n)))))

def dm_103.quo2(m: Maybe<&1, O.Found>, +s1: O.Found, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+k}:
      +d = mint_bin(k, O.OpsDIV{}, O.Found.i(s1), sy_src1(x, u))
      Some{mint_bin(d, O.OpsADD{}, O.Found.i(d), O.Found.i(k))}
    case None{}: None{}

def dm_103.quo(+s1: O.Found, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_103.quo2(mint_const_like(s1, x, dm_103.n(x, u), O.CInt{H.i64_div(c, j)}), s1, x, u)

def dm_103.byop(is_mod: Bool, +s1: O.Found, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match is_mod:
    case True{} : Some{mint_bin(s1, O.OpsMOD{}, O.Found.i(s1), sy_src1(x, u))}
    case False{}: dm_103.quo(s1, c, j, x, u)

def dm_103.put(m: Maybe<&1, O.Found>, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32, +n: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+r}:
      # A MATCH CANNOT SCRUTINIZE A CALL: the op test is read into a `Bool` parameter first.
      dm_103.byop(sy_is_op(x, u, O.OpsMOD{}),
        mint_bin(r, O.OpsADD{}, dm_103.n(x, u), O.Found.i(r)), c, j, x, u)
    case None{}: None{}

# A LINEAR `Maybe` IS A `Type` AND NOT A `Data`, so it cannot be bound with `+` and read
# twice: the const is minted inside the call that consumes it.
def dm_103.mk(+c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_103.put(mint_const_like(mint_ar(sy_ar(x)), x, dm_103.n(x, u), O.CInt{H.i64_mod(c, j)}),
             c, j, x, u, sy_src0(x, u))

def dm_103.go(gate: Bool, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match gate:
    case True{} : dm_103.mk(c, j, x, u)
    case False{}: None{}

def dm_103.dv(m: Maybe<&2, O.Const>, +c: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{O.CInt{+j}}:
      dm_103.go(Bool.and(Bool.not(Cmp.is_eq(H.i64_cmp(j, H.i64_of_i32(0)))),
                          Bool.not(Cmp.is_eq(H.i64_cmp(H.i64_mod(c, j), c)))), c, j, x, u)
    case _: None{}

def dm_103.cv(m: Maybe<&2, O.Const>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{O.CInt{c}}: dm_103.dv(sy_val(x, sy_src1(x, u)), c, x, u)
    case _: None{}

def dm_103(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(dm_103.pat(x, u), dm_103.cv(sy_val(x, dm_103.c(x, u)), x, u))

# symbolic.py:458  (UPat(Ops.STORE, src=(UPat(), invalid_pat), name="x"),
def sym_458.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsSTORE{}, 2, p_invalid(x, sy_src1(x, u)))

def sym_458.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +n = O.UOp.new(sy_ar(x), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  # `NOOP.after(*srcs)` IS `AFTER(noop, *srcs)`: the NOOP is the FIRST SOURCE and the store's
  # own srcs follow it. The first version dropped it and answered `(after (index b c0) bad)`.
  Some{O.UOp.new(O.Found.ar(n), O.OpsAFTER{},
    List.append(&2, U32, [O.Found.i(n)], O.Arena.srcs(O.Found.ar(n), u)), O.ANone{}, O.TNone{})}

def sym_458(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_458.pat(x, u), sym_458.mk(x, u))

# symbolic.py:318  an AFTER waits only on the EFFECT ops; any other dependency is replaced by
def fence_op(op: O.Op) -> Bool:
  match op:
    case O.OpsRANGE{}   : True{}
    case O.OpsSTORE{}   : True{}
    case O.OpsCALL{}    : True{}
    case O.OpsBARRIER{} : True{}
    case O.OpsEND{}     : True{}
    case O.OpsBACKEDGE{}: True{}
    case O.OpsLINEAR{}  : True{}
    case O.OpsSTAGE{}   : True{}
    case _              : False{}

def sym_318.part(+x: F.Folded, +y: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, fence_op(sy_op(x, y)), [y], O.Arena.srcs(sy_ar(x), y))

# `List.concat` takes a LIST OF LISTS, so two flat lists join one element at a time. `push` is
def sym_318.push(ps: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: sym_318.push(t, List.append(&2, U32, acc, [p]))

def sym_318.gather(ys: List<&2, U32>, +x: F.Folded, +acc: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}: acc
    case y <> t: sym_318.gather(t, x, sym_318.push(sym_318.part(x, y), acc))

def sym_318.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsAFTER{}), sy_nsrc_ge(x, u, 1))

def sym_318.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +rest = O.Arena.srcs(sy_ar(x), u)
  Some{mint_replace(mint_ar(sy_ar(x)), x, u,
    List.append(&2, U32, [sy_src0(x, u)],
      H.dedup_u32(sym_318.gather(List.tail(&2, U32, rest), x, Nil{}))))}

def sym_318(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_318.pat(x, u), sym_318.mk(x, u))

# symbolic.py:322  (UPat((Ops.AFTER, Ops.END), src=(UPat.var("s"),)), lambda s: s)
def sym_322.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.or(sy_is_op(x, u, O.OpsAFTER{}), sy_is_op(x, u, O.OpsEND{})), sy_nsrc_is(x, u, 1))

def sym_322(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri_u(sym_322.pat(x, u), sy_src0(x, u))

# ---- `symbolic.py:302`, `canonicalize_simplex` ----------------------------------
# `(X < 1).ne(True)` where `X` is a sum: if every term is IRREDUCIBLE with `vmin >= 0` and at
def sym_302.irr(op: O.Op) -> Bool:
  match op:
    case O.OpsCONST{}  : True{}
    case O.OpsGETADDR{}: True{}
    case O.OpsPARAM{}  : True{}
    case O.OpsRANGE{}  : True{}
    case O.OpsSPECIAL{}: True{}
    case _             : False{}

# `u.op is MUL and u.src[1].op is CONST and u.src[1].val > 0`
def sym_302.posmul(+x: F.Folded, +u: U32) -> Bool:
  +ar = F.Folded.ar(x)
  Bool.and(Bool.and(O.eq_op(O.Arena.op(ar, u), O.OpsMUL{}),
                    O.eq_op(O.Arena.op(ar, O.Arena.src(ar, u, 1)), O.OpsCONST{})),
           Bool.not(H.i64_is_neg(cval(ar, O.Arena.src(ar, u, 1)))))

def sym_302.strip(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_302.posmul(x, u), O.Arena.src0(F.Folded.ar(x), u), u)

# `u.vmin >= 0` is `not (vmin < 0)`.
def sym_302.ge0(m: Maybe<&2, F.Bnd>) -> Bool:
  match m:
    case Some{+b}: Bool.not(F.bnd.lt(b, F.bnd_zero()))
    case None{}: False{}

def sym_302.ok(u: U32, +x: F.Folded, +bt: F.BTable) -> Bool:
  +v = sym_302.strip(x, u)
  Bool.and(sym_302.irr(O.Arena.op(F.Folded.ar(x), v)),
           sym_302.ge0(F.UOp.vmin(F.Folded.ar(x), bt, v)))

# the empty accumulator is a list and not a failure: `None{}` means "no terms yet", so the first
# term STARTS the list.
def sym_302.push2(acc: Maybe<&2, List<&2, U32>>, v: U32) -> Maybe<&2, List<&2, U32>>:
  match acc:
    case Some{+l}: Some{List.append(&2, U32, l, [v])}
    case None{}  : Some{[v]}

def sym_302.push(ok: Bool, v: U32, acc: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{} : sym_302.push2(acc, v)
    case False{}: None{}

def sym_302.vals(ts: List<&2, U32>, +x: F.Folded, +bt: F.BTable, acc: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match ts:
    case Nil{}: acc
    case +u <> rest:
      sym_302.vals(rest, x, bt, sym_302.push(sym_302.ok(u, x, bt), sym_302.strip(x, u), acc))

# `changed` -- at least ONE term was a positive constant multiple.
def sym_302.chg(ts: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match ts:
    case Nil{}: acc
    case +u <> rest: sym_302.chg(rest, x, Bool.or(acc, sym_302.posmul(x, u)))

def sym_302.onestep(acc: Maybe<&1, O.Found>, +f: O.Found, t: U32) -> Maybe<&1, O.Found>:
  match acc:
    case Some{+a}: Some{mint_bin(a, O.OpsADD{}, O.Found.i(a), t)}
    case None{}  : Some{O.Found{O.Found.ar(f), t}}

def sym_302.adds(ts: List<&2, U32>, +f: O.Found, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match ts:
    case Nil{}: acc
    case t <> rest: sym_302.adds(rest, f, sym_302.onestep(acc, f, t))

# `(newx < 1).ne(True)` is THREE nodes: the CONST 1, the CMPLT, and the CONST True under CMPNE.
def dt_or_weak(+x: F.Folded, +u: U32) -> S.Dt:
  Bool.pick(S.Dt, O.eq_dt(sy_dt1(x, u), S.void()), S.weakint(), sy_dt1(x, u))

def mint_cst_dt(+f: O.Found, +dt: S.Dt, +v: O.Const) -> Maybe<&1, O.Found>:
  Some{mint_cst(sy_needs_cast(dt, v), O.UOp.const(O.Found.ar(f), v), dt)}

def sym_302.ne3(m: Maybe<&1, O.Found>, +lt: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsCMPEQ{}, O.Found.i(lt), O.Found.i(c))}
    case None{}  : None{}

def sym_302.ne2(m: Maybe<&1, O.Found>, +x: F.Folded, +s: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}:
      +lt = mint_bin(c, O.OpsCMPLT{}, O.Found.i(s), O.Found.i(c))
      sym_302.ne3(mint_cst_dt(lt, S.boolean(), O.CBool{False{}}), lt)
    case None{}: None{}

def sym_302.ne1(m: Maybe<&1, O.Found>, +x: F.Folded) -> Maybe<&1, O.Found>:
  match m:
    case Some{+s}: sym_302.ne2(mint_cst_dt(s, dt_or_weak(x, O.Found.i(s)), O.CInt{H.i64_of_i32(1)}), x, s)
    case None{}  : None{}

def sym_302.go2(m: Maybe<&2, List<&2, U32>>, +x: F.Folded) -> Maybe<&1, O.Found>:
  match m:
    case Some{+ts}: sym_302.ne1(sym_302.adds(ts, mint_ar(F.Folded.ar(x)), None{}), x)
    case None{}   : None{}

def sym_302.emit(go: Bool, +ts: List<&2, U32>, +x: F.Folded) -> Maybe<&1, O.Found>:
  match go:
    case True{} : sym_302.go2(sym_302.vals(ts, x, sym_280.bt(x), None{}), x)
    case False{}: None{}

def sym_302.pat(+x: F.Folded, +u: U32) -> Bool:
  +l = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPEQ{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_op(x, l, O.OpsCMPLT{}), sy_nsrc_is(x, l, 2)),
      Bool.and(p_intweak(x, sy_src0(x, l)), p_is_const_false(x, sy_src1(x, u)))))

def sym_302.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +l = sy_src0(x, u)
  +ts = O.UOp.split_uop(U32.to_nat(O.Arena.next(F.Folded.ar(x))), F.Folded.ar(x), sy_src0(x, l), O.OpsADD{})
  sym_302.emit(sym_302.chg(ts, x, False{}), ts, x)

def sym_302(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_302.pat(x, u), sym_302.run(x, u))

# ---- `weak.py:89`, `pm_uncast_const` -------------------------------------------
def p_uncastable(+x: F.Folded, +s: U32) -> Bool:
  +ar = F.Folded.ar(x)
  Bool.and(Bool.and(sy_is_op(x, s, O.OpsCAST{}), sy_nsrc_is(x, s, 1)),
    Bool.and(Bool.not(dt_weak_of(sy_dt1(x, s))),
      Bool.and(sy_is_op(x, O.Arena.src0(ar, s), O.OpsCONST{}),
               dt_weak_of(sy_dt1(x, O.Arena.src0(ar, s))))))

def uc.step(ok: Bool, s: U32, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match ok:
    case True{} : List.append(&2, U32, acc, [O.Arena.src0(ar, s)])
    case False{}: List.append(&2, U32, acc, [s])

def uc.srcs(ss: List<&2, U32>, +ar: O.Arena, +x: F.Folded, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> rest: uc.srcs(rest, ar, x, uc.step(p_uncastable(x, s), s, ar, acc))

# `src != u.src` IS "AT LEAST ONE SRC WAS UNCASTABLE": the map only changes the entries that
def uc.any(ss: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case +s <> rest: uc.any(rest, x, Bool.or(acc, p_uncastable(x, s)))

def dt_list(ss: List<&2, U32>, +x: F.Folded, +acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ss:
    case Nil{}: acc
    case +s <> rest: dt_list(rest, x, List.append(&2, S.Dt, acc, [sy_dt1(x, s)]))

def uncast.fin(ok: Bool, +new: List<&2, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : Some{mint_replace(mint_ar(F.Folded.ar(x)), x, u, new)}
    case False{}: None{}

# EVERY MATCH IS ON ITS OWN PARAMETER: a `match` after a local binder is refused, so the `Dts`
# is read in one def and its `Bool` in another.
def uncast.check2(ok: Bool, +d: W.Dts, +new: List<&2, U32>, +old: List<&2, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}:
      uncast.fin(Bool.and(O.eq_dt(W.Dts.meet(d), F.promo_dtype(dt_list(old, x, Nil{}))),
                          O.eq_dt(W.Dts.result(d), sy_dt1(x, u))), new, x, u)
    case False{}: None{}

def uncast.check1(+d: W.Dts, +new: List<&2, U32>, +old: List<&2, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  uncast.check2(W.Dts.some(d), d, new, old, x, u)

def uncast.check(ok: Bool, +new: List<&2, U32>, +old: List<&2, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : uncast.check1(W.derived_dtypes(x, u, new), new, old, x, u)
    case False{}: None{}

def uncast.go(diff: Bool, ok: Bool, +new: List<&2, U32>, +old: List<&2, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match diff:
    case True{} : uncast.check(ok, new, old, x, u)
    case False{}: None{}

def uncast.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +old = O.Arena.srcs(ar, u)
  +new = uc.srcs(old, ar, x, Nil{})
  uncast.go(uc.any(old, x, False{}), True{}, new, old, x, u)

def uncast.pat(+x: F.Folded, +u: U32) -> Bool: O.GroupOp.broadcastable(sy_op(x, u))

def wk_89(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(uncast.pat(x, u), uncast.mk(x, u))

# ---- `movement.py:5-29`, `mop_cleanup` -- NINE RULES AND ONE TABLE ------------------
def mv.go(none: Bool, +h: M.Hop) -> Maybe<&1, O.Found>:
  match none:
    case True{} : None{}
    case False{}: Some{O.Found{M.hop_ar(h), M.hop_ix(h)}}

def mv.hit(+h: M.Hop) -> Maybe<&1, O.Found>:
  mv.go(O.UOp.is_none(M.hop_ix(h)), h)

def mv_run(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  mv.hit(M.hop_self(M.mp_dispatch(tag, F.Folded.t(x), F.Folded.ar(x), u), u))

def mv_7(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>  : mv_run(0, x, u)
def mv_10(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(1, x, u)
def mv_12(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(2, x, u)
def mv_14(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(3, x, u)
def mv_16(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(4, x, u)
def mv_18(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(5, x, u)
def mv_21(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(6, x, u)
def mv_24(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(7, x, u)
def mv_27(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found> : mv_run(8, x, u)

# ---- `symbolic.py:469`, `reduce_mul_chain` ----------------------------------------
def rm469.has(us: List<&2, U32>, +k: U32) -> Bool:
  match us:
    case Nil{}: False{}
    case h <> t: Bool.or(U32.is_eq(h, k), rm469.has(t, k))

# `all(r not in m_parents for r in r.src[1:])` -- no axis is below the factor.
def rm469.none_in(axes: List<&2, U32>, +ps: List<&2, U32>, acc: Bool) -> Bool:
  match axes:
    case Nil{}: acc
    case h <> t: rm469.none_in(t, ps, Bool.and(acc, Bool.not(rm469.has(ps, h))))

def rm469.ge0(m: Maybe<&2, F.Bnd>) -> Bool:
  match m:
    case Some{+b}: Bool.not(F.bnd.lt(b, F.bnd_zero()))
    case None{}: False{}

# `m not in r.src[1:] and all(r not in m_parents ...) and (r.arg[0] != MAX or m.vmin >= 0)`
def rm469.outside(rop: O.Op, +axes: List<&2, U32>, +x: F.Folded, +m: U32) -> Bool:
  +ar = F.Folded.ar(x)
  Bool.and(Bool.not(rm469.has(axes, m)),
    Bool.and(rm469.none_in(axes, O.UOp.backward_slice(O.Arena.budget(ar), ar, m), True{}),
      Bool.or(Bool.not(O.eq_op(rop, O.OpsMAX{})), rm469.ge0(F.UOp.vmin(ar, sym_280.bt(x), m)))))

type Rm469 is Data:
  Rm469{ins: List<&2, U32>, outs: List<&2, U32>}

def Rm469.ins(p: Rm469) -> List<&2, U32>:
  match p:
    case Rm469{ins, outs}: ins

def Rm469.outs(p: Rm469) -> List<&2, U32>:
  match p:
    case Rm469{ins, outs}: outs

def rm469.put(out: Bool, t: U32, +acc: Rm469) -> Rm469:
  match out:
    case True{} : Rm469{Rm469.ins(acc), List.append(&2, U32, Rm469.outs(acc), [t])}
    case False{}: Rm469{List.append(&2, U32, Rm469.ins(acc), [t]), Rm469.outs(acc)}

def rm469.part(ts: List<&2, U32>, +rop: O.Op, +axes: List<&2, U32>, +x: F.Folded, +acc: Rm469) -> Rm469:
  match ts:
    case Nil{}: acc
    case +t <> rest: rm469.part(rest, rop, axes, x, rm469.put(rm469.outside(rop, axes, x, t), t, acc))

def rm469.empty(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case _: False{}

# `functools.reduce(operator.mul, xs, 1)`: the accumulator is ALREADY the CONST 1.
def rm469.prod(xs: List<&2, U32>, +f: O.Found, acc: U32) -> O.Found:
  match xs:
    case Nil{}: f
    case +h <> t:
      +f2 = mint_bin(f, O.OpsMUL{}, acc, h)
      rm469.prod(t, f2, O.Found.i(f2))

# `prod(inside) if len(inside) else r.src[0].const_like(1)` -- `const_like` is the SRC's
# dtype and not `weakint`, so this is `mint_cst_dt` and not a bare CONST.
def rm469.first(+x: F.Folded, +u: U32, +ins: List<&2, U32>, +f: O.Found) -> Maybe<&1, O.Found>:
  match ins:
    case Nil{}: mint_cst_dt(f, sy_dt1(x, sy_src0(x, u)), O.CInt{H.i64_of_i32(1)})
    case _   : Some{rm469.prod(ins, f, O.Found.i(f))}

def rm469.rop(a: O.Arg) -> O.Op:
  match a:
    case O.AReduce{rop, num_axes}: rop
    case _: O.OpsNOOP{}

def rm469.ok(+rop: O.Op, +x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.or(O.eq_op(rop, O.OpsADD{}), O.eq_op(rop, O.OpsMAX{})),
           Bool.or(Bool.not(O.eq_op(rop, O.OpsMAX{})), Bool.not(S.Dt.is_unsigned(sy_dt1(x, u)))))

def rm469.emit4(+r: O.Found, +p: Rm469, +one: O.Found) -> Maybe<&1, O.Found>:
  +po = rm469.prod(Rm469.outs(p), r, O.Found.i(one))
  Some{mint_bin(po, O.OpsMUL{}, O.Found.i(r), O.Found.i(po))}

def rm469.emit3(f: Maybe<&1, O.Found>, +x: F.Folded, +u: U32, +axes: List<&2, U32>, +p: Rm469, +one: O.Found) -> Maybe<&1, O.Found>:
  match f:
    case Some{+v}: rm469.emit4(mint_replace(v, x, u, List.append(&2, U32, [O.Found.i(v)], axes)), p, one)
    case None{}: None{}

def rm469.emit(none: Bool, +x: F.Folded, +u: U32, +axes: List<&2, U32>, +p: Rm469, +one: O.Found) -> Maybe<&1, O.Found>:
  match none:
    case True{} : None{}
    case False{}: rm469.emit3(rm469.first(x, u, Rm469.ins(p), one), x, u, axes, p, one)

def rm469.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +axes = O.Arena.src_from(ar, u, 1)
  +ts = O.UOp.split_uop(O.Arena.budget(ar), ar, sy_src0(x, u), O.OpsMUL{})
  +p = rm469.part(ts, rm469.rop(sy_arg(x, u)), axes, x, Rm469{Nil{}, Nil{}})
  rm469.emit(rm469.empty(Rm469.outs(p)), x, u, axes, p, O.UOp.const(ar, O.CInt{H.i64_of_i32(1)}))

def rm469.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsREDUCE{}), sy_nsrc_ge(x, u, 2)),
           sy_is_op(x, sy_src0(x, u), O.OpsMUL{}))

def rm469.guard(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : rm469.run(x, u)
    case False{}: None{}

def sym_469(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(rm469.pat(x, u), rm469.guard(rm469.ok(rm469.rop(sy_arg(x, u)), x, u), x, u))

# ---- `symbolic.py:171`, bool MUL is AND -------------------------------------------
def c_f1(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CFloat{f}}: F32.is_eq(f, 1.0)
    case _: False{}

def p_is_const_f1(x: F.Folded, u: U32) -> Bool: c_f1(sy_val(x, u))

# `1 + x` carries whichever 1 the graph has. `UPat.const(1)` matches the value, so a weakint
def p_c1(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(p_is_const_i(x, u, H.i64_of_i32(1)), p_is_const_f1(x, u))

def sym_171.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMUL{}, 2, Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_171.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  Some{mint_bin(mint_ar(sy_ar(x)), O.OpsAND{}, sy_src0(x, u), sy_src1(x, u))}

def sym_171(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_171.pat(x, u), sym_171.put(x, u))

# ---- `symbolic.py:465-467`, the three `x/(1+x)` rules -----------------------------
def p_recip1p(+x: F.Folded, +d: U32, +v: U32) -> Bool:
  +a = sy_src0(x, d)
  Bool.and(Bool.and(sy_is_op(x, d, O.OpsRECIP{}), sy_nsrc_is(x, d, 1)),
    Bool.and(sy_is_op(x, a, O.OpsADD{}), Bool.and(sy_nsrc_is(x, a, 2),
      Bool.and(p_c1(x, sy_src0(x, a)), p_same(sy_src1(x, a), v)))))

# every mint reads the arena its last operand opened: `neg` is minted in `one`'s arena, so
def mint_one_sub(+f: O.Found, d: U32) -> O.Found:
  +one = O.UOp.const(O.Found.ar(f), O.CFloat{1.0})
  +neg = O.UOp.const(O.Found.ar(one), O.CFloat{F32.neg(1.0)})
  +m = mint_bin(neg, O.OpsMUL{}, d, O.Found.i(neg))
  mint_bin(m, O.OpsADD{}, O.Found.i(one), O.Found.i(m))

def sym_465.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMUL{}, 2, p_recip1p(x, sy_src1(x, u), sy_src0(x, u)))

def sym_465.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  Some{mint_one_sub(mint_ar(sy_ar(x)), sy_src1(x, u))}

def sym_465(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_465.pat(x, u), sym_465.put(x, u))

# `d * UPat.var("y")` is MUL(d, y) -- the reciprocal is SRC0 of the inner MUL.
def sym_466.pat(+x: F.Folded, +u: U32) -> Bool:
  +inner = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, inner, O.OpsMUL{}), Bool.and(sy_nsrc_is(x, inner, 2),
      p_recip1p(x, sy_src0(x, inner), sy_src0(x, u)))))

def sym_466.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +inner = sy_src1(x, u)
  +s = mint_one_sub(mint_ar(sy_ar(x)), sy_src0(x, inner))
  Some{mint_bin(s, O.OpsMUL{}, sy_src1(x, inner), O.Found.i(s))}

def sym_466(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_466.pat(x, u), sym_466.put(x, u))

# `d + UPat.var("y")` is ADD(d, y).
def sym_467.pat(+x: F.Folded, +u: U32) -> Bool:
  +inner = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, inner, O.OpsADD{}), Bool.and(sy_nsrc_is(x, inner, 2),
      p_recip1p(x, sy_src0(x, inner), sy_src0(x, u)))))

def sym_467.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +inner = sy_src1(x, u)
  +s = mint_one_sub(mint_ar(sy_ar(x)), sy_src0(x, inner))
  +m = mint_bin(s, O.OpsMUL{}, sy_src0(x, u), sy_src1(x, inner))
  Some{mint_bin(m, O.OpsADD{}, O.Found.i(s), O.Found.i(m))}

def sym_467(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_467.pat(x, u), sym_467.put(x, u))

# ---- `symbolic.py:309`, the long-to-int cast fold ---------------------------------
def dt_iw(+d: S.Dt) -> Bool: Bool.or(dt_in(DTS_INTS(), d), dt_intweak(d))

def mint_ccast.c(ar: O.Arena, m: Maybe<&2, O.Const>, dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{+v}: Some{O.UOp.cconst(ar, v, dt)}
    case None{}  : None{}

def mint_ccast.go(is_const: Bool, ar: O.Arena, u: U32, m: Maybe<&2, O.Const>, dt: S.Dt) -> Maybe<&1, O.Found>:
  match is_const:
    case True{} : mint_ccast.c(ar, m, dt)
    case False{}: Some{O.UOp.cast(ar, u, dt)}

# `x.ccast(b.dtype)`, with `x` the INNER src and `b` the OUTER cast.
def mint_ccast(+x: F.Folded, +v: U32, u: U32) -> Maybe<&1, O.Found>:
  mint_ccast.go(sy_is_const(x, v), sy_ar(x), v, sy_val(x, v), Maybe.default(&1, S.Dt, sy_arg_dt(x, u), S.void()))

def sym_309.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(Bool.and(sy_is_op(x, a, O.OpsCAST{}), sy_nsrc_is(x, a, 1)),
      Bool.and(dt_iw(sy_dt1(x, sy_src0(x, a))), dt_iw(sy_dt1(x, a)))))

def sym_309.go(ovf: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ovf:
    case True{} : None{}
    case False{}: mint_ccast(x, sy_src0(x, sy_src0(x, u)), u)

def sym_309.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_309.go(F.UOp.overflows(sy_ar(x), sym_280.bt(x), sy_src0(x, sy_src0(x, u)), sy_dt1(x, sy_src0(x, u))), x, u)

def sym_309(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_309.pat(x, u), sym_309.mk(x, u))

# ---- `symbolic.py:312`, "try to do math in int instead of long" -------------------
def dt_lw(+d: S.Dt) -> Bool: Bool.or(O.eq_dt(d, S.int64()), dt_intweak(d))

def sym_312.side(k: Bool, +f: O.Found, +ar: O.Arena, +s: U32) -> O.Found:
  match k:
    case True{} : O.UOp.const(O.Found.ar(f), O.CInt{cval(ar, s)})
    case False{}: O.UOp.cast(O.Found.ar(f), s, S.int32())

def sym_312.build(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = sy_ar(x)
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  +fa = sym_312.side(sy_is_const(x, a), mint_ar(ar), ar, a)
  +fb = sym_312.side(sy_is_const(x, b), fa, ar, b)
  +m = O.UOp.alu(O.Found.ar(fb), O.Arena.op(ar, u), [O.Found.i(fa), O.Found.i(fb)])
  Some{O.UOp.cast(O.Found.ar(m), O.Found.i(m), sy_dt1(x, u))}

def sym_312.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.binary(sy_op(x, u)), sy_nsrc_is(x, u, 2)),
    Bool.and(dt_lw(sy_dt1(x, sy_src0(x, u))), dt_lw(sy_dt1(x, sy_src1(x, u)))))

def sym_312.guard(+x: F.Folded, +u: U32) -> Bool:
  +ar = F.Folded.ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.or(O.eq_dt(sy_dt1(x, a), S.int64()), O.eq_dt(sy_dt1(x, b), S.int64())),
    Bool.and(Bool.not(F.UOp.overflows(ar, bt, u, S.int32())),
      Bool.and(Bool.not(F.UOp.overflows(ar, bt, a, S.int32())),
               Bool.not(F.UOp.overflows(ar, bt, b, S.int32())))))

def sym_312.go(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : sym_312.build(x, u)
    case False{}: None{}

def sym_312(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_312.pat(x, u), sym_312.go(sym_312.guard(x, u), x, u))

# ---- `symbolic.py:299`, `lt_folding` ----------------------------------------------
def bnd_i64.go(neg: Bool, +mag: H.I64) -> H.I64:
  match neg:
    case True{} : H.i64_neg(True{}, mag)
    case False{}: mag

# `Bnd` IS THREE VARIANTS, not two: `Bnd{inf}` is a bound at plus or minus infinity, and a
# number cannot state it -- so an infinite bound answers 0 here and `has_b`/`Ranged`'s callers
# do not reach it with a bound they trust. MEASURED: the two-arm version would not compile.
def bnd_i64(b: F.Bnd) -> H.I64:
  match b:
    case F.BndInt{neg, mag}: bnd_i64.go(neg, mag)
    case F.Bnd{inf}: H.i64_zero()
    case F.BndFlt{v}: H.i64_zero()

def vmin_i64(+ar: O.Arena, +bt: F.BTable, t: U32) -> H.I64:
  bnd_i64(Maybe.default(&2, F.Bnd, F.UOp.vmin(ar, bt, t), F.bnd_zero()))

def vmax_i64(+ar: O.Arena, +bt: F.BTable, t: U32) -> H.I64:
  bnd_i64(Maybe.default(&2, F.Bnd, F.UOp.vmax(ar, bt, t), F.bnd_zero()))

# a bound the sweep does not answer makes the FOLD unknown: reading an unknown bound as 0 would
# be a bound the comparison accepts.
def has_b(m: Maybe<&2, F.Bnd>) -> Bool:
  match m:
    case Some{+b}: True{}
    case None{}  : False{}

# `ceildiv(a, d)` on a signed `I64` with only a TRUNCATING divide. `(a+d-1)/d` is right for
# `a >= 0` and off by one below it, so the two signs are two arms.
def ceil_i64.go(neg: Bool, +a: H.I64, +d: H.I64) -> H.I64:
  match neg:
    case True{} : H.i64_neg(True{}, H.i64_div(H.i64_neg(True{}, a), d))
    case False{}: H.i64_div(H.i64_add(a, H.i64_sub(d, H.i64_one())), d)

def ceil_i64(+a: H.I64, +d: H.I64) -> H.I64: ceil_i64.go(H.i64_is_neg(a), a, d)

def is_1(+f: H.I64) -> Bool: Cmp.is_eq(H.i64_cmp(f, H.i64_of_i32(1)))

def is_gt1(+d: H.I64) -> Bool: Cmp.is_gt(H.i64_cmp(d, H.i64_of_i32(1)))

type Lt is Data:
  Lt{g: H.I64, lo: H.I64, hi: H.I64, ok: Bool, ps: List<&2, U32>, ns: List<&2, U32>}

def Lt.g(l: Lt) -> H.I64:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: g

def Lt.lo(l: Lt) -> H.I64:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: lo

def Lt.hi(l: Lt) -> H.I64:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: hi

def Lt.ok(l: Lt) -> Bool:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: ok

def Lt.ps(l: Lt) -> List<&2, U32>:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: ps

def Lt.ns(l: Lt) -> List<&2, U32>:
  match l:
    case Lt{g, lo, hi, ok, ps, ns}: ns

def lt299.plain(+u: U32, +l: Lt) -> Lt:
  Lt{Lt.g(l), Lt.lo(l), Lt.hi(l), Lt.ok(l), List.append(&2, U32, Lt.ps(l), [u]), Lt.ns(l)}

def lt299.bound(+l: Lt, lo: H.I64, hi: H.I64, ok: Bool) -> Lt:
  Lt{Lt.g(l), H.i64_add(Lt.lo(l), lo), H.i64_add(Lt.hi(l), hi),
     Bool.and(Lt.ok(l), ok), Lt.ps(l), Lt.ns(l)}

# `ns` holds the term and `ps` holds the popped node, and they are not interchangeable: the answer
# rebuilds `u*(f//d)` from the TERM and pops its factor again, while `p`'s bound is the POPPED
# node's. MEASURED, with the popped node in `ns` the answer read `mul x c0` -- `pc_v` on a bare
def lt299.scaled(f: H.I64, +t: U32, +l: Lt) -> Lt:
  Lt{H.gcd(Lt.g(l), f), Lt.lo(l), Lt.hi(l), Lt.ok(l), Lt.ps(l), List.append(&2, U32, Lt.ns(l), [t])}

def lt299.step(plain: Bool, f: H.I64, +t: U32, +u: U32, lo: H.I64, hi: H.I64, ok: Bool, +l: Lt) -> Lt:
  match plain:
    case True{} : lt299.bound(lt299.plain(u, l), lo, hi, ok)
    case False{}: lt299.scaled(f, t, l)

def lt299.scan(ts: List<&2, U32>, +ar: O.Arena, +bt: F.BTable, +l: Lt) -> Lt:
  match ts:
    case Nil{}: l
    case +t <> rest:
      +f = pc_v(ar, t, O.OpsMUL{})
      +u = pc_n(ar, t, O.OpsMUL{})
      lt299.scan(rest, ar, bt,
        lt299.step(is_1(f), f, t, u, vmin_i64(ar, bt, u), vmax_i64(ar, bt, u),
          Bool.and(has_b(F.UOp.vmin(ar, bt, u)), has_b(F.UOp.vmax(ar, bt, u))), l))

# `u*(f//d)` -- the const is the SECOND src, which is why `_binop(MUL)` builds `MUL(u, k)` and not
# the other way round. `i64_div` truncates and `d` divides `f` exactly, so it IS Python's `//`.
def lt299.mul(+d: H.I64, +t: U32, +ar: O.Arena) -> O.Found:
  +k = O.UOp.const(ar, O.CInt{H.i64_div(pc_v(ar, t, O.OpsMUL{}), d)})
  O.UOp.alu(O.Found.ar(k), O.OpsMUL{}, [pc_n(ar, t, O.OpsMUL{}), O.Found.i(k)])

type Bu is Data:
  Bu{us: List<&2, U32>, f: O.Found}

def Bu.us(b: Bu) -> List<&2, U32>:
  match b:
    case Bu{us, f}: us

def Bu.f(b: Bu) -> O.Found:
  match b:
    case Bu{us, f}: f

def lt299.bu(ts: List<&2, U32>, +d: H.I64, +ar: O.Arena, +b: Bu) -> Bu:
  match ts:
    case Nil{}: b
    case t <> rest:
      +m = lt299.mul(d, t, O.Found.ar(Bu.f(b)))
      lt299.bu(rest, d, ar, Bu{List.append(&2, U32, Bu.us(b), [O.Found.i(m)]), m})

# `UOp.usum(*xs)` -- a fold with ADD where the FIRST element starts it, so `has` is the emptiness.
type Ad is Data:
  Ad{has: Bool, i: U32, f: O.Found}

def Ad.has(a: Ad) -> Bool:
  match a:
    case Ad{has, i, f}: has

def Ad.i(a: Ad) -> U32:
  match a:
    case Ad{has, i, f}: i

def Ad.f(a: Ad) -> O.Found:
  match a:
    case Ad{has, i, f}: f

def lt299.ad.and(+a: Ad, +j: U32) -> Ad:
  +m = O.UOp.alu(O.Found.ar(Ad.f(a)), O.OpsADD{}, [Ad.i(a), j])
  Ad{True{}, O.Found.i(m), m}

def lt299.ad.one(has: Bool, +j: U32, +a: Ad) -> Ad:
  match has:
    case True{} : lt299.ad.and(a, j)
    case False{}: Ad{True{}, j, Ad.f(a)}

def lt299.adds(us: List<&2, U32>, +a: Ad) -> Ad:
  match us:
    case Nil{}: a
    case j <> rest: lt299.adds(rest, lt299.ad.one(Ad.has(a), j, a))

def lt299.hit(+a: Ad, +t: H.I64) -> Maybe<&1, O.Found>:
  +k = O.UOp.const(O.Found.ar(Ad.f(a)), O.CInt{t})
  Some{O.UOp.alu(O.Found.ar(k), O.OpsCMPLT{}, [Ad.i(a), O.Found.i(k)])}

def lt299.build(+ar: O.Arena, +l: Lt, +c: H.I64) -> Maybe<&1, O.Found>:
  +d = Lt.g(l)
  +b = lt299.bu(Lt.ns(l), d, ar, Bu{Nil{}, mint_ar(ar)})
  lt299.hit(lt299.adds(Bu.us(b), Ad{False{}, 0, Bu.f(b)}), ceil_i64(H.i64_sub(c, Lt.lo(l)), d))

def lt299.pass(ok: Bool, +ar: O.Arena, +l: Lt, +c: H.I64) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : lt299.build(ar, l, c)
    case False{}: None{}

def lt299.guard(+l: Lt, +c: H.I64) -> Bool:
  +d = Lt.g(l)
  Bool.and(Bool.and(Lt.ok(l), is_gt1(d)),
    Cmp.is_eq(H.i64_cmp(ceil_i64(H.i64_sub(c, Lt.lo(l)), d), ceil_i64(H.i64_sub(c, Lt.hi(l)), d))))

def lt299.mk(+ar: O.Arena, +l: Lt, +c: H.I64) -> Maybe<&1, O.Found>:
  lt299.pass(lt299.guard(l, c), ar, l, c)

def sym_299.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsCMPLT{}, 2, Bool.and(dt_intweak(sy_dt1(x, sy_src0(x, u))), sy_is_const(x, sy_src1(x, u))))

def sym_299.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = sy_ar(x)
  +l = lt299.scan(O.UOp.split_uop(O.Arena.budget(ar), ar, sy_src0(x, u), O.OpsADD{}), ar, sym_280.bt(x),
                  Lt{H.i64_zero(), H.i64_zero(), H.i64_zero(), True{}, Nil{}, Nil{}})
  lt299.mk(ar, l, cval(ar, sy_src1(x, u)))

def sym_299(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_299.pat(x, u), sym_299.run(x, u))

# ---- `symbolic.py:200`, a positive const to the power of x -------------------------
def sym_193.pos(c: O.Const) -> Bool:
  match c:
    case O.CInt{i}: Cmp.is_gt(H.i64_cmp(i, H.i64_of_i32(0)))
    case O.CFloat{f}: F32.is_gt(f, 0.0)
    case _: False{}

def sym_193.lg(c: O.Const) -> F32:
  match c:
    case O.CInt{i}: F32.log2(U32.to_f32(H.lo32(i)))
    case O.CFloat{f}: F32.log2(f)
    case _: 0.0

def sym_193.flt(+x: F.Folded, +u: U32) -> Bool:
  S.Cls.is_float(S.Dt.cls(sy_dt1(x, sy_src1(x, u))))

def sym_193.emit(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +k = O.UOp.const(sy_ar(x), O.CFloat{sym_193.lg(sy_maybe_c2(sy_val(x, sy_src0(x, u))))})
  +m = mint_bin(k, O.OpsMUL{}, sy_src1(x, u), O.Found.i(k))
  Some{mint_alu(O.OpsEXP2{}, m, [O.Found.i(m)])}

def sym_193.go3(f: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match f:
    case True{} : sym_193.emit(x, u)
    case False{}: None{}

def sym_193.go2(p: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match p:
    case True{} : sym_193.go3(sym_193.flt(x, u), x, u)
    case False{}: None{}

# the entry is the constant's positiveness and the exponent's floatness -- and not "is the
# CONST one", because upstream's current rule has no `c.val == 1` arm.
def sym_193.go1(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_193.go2(sym_193.pos(sy_maybe_c2(sy_val(x, sy_src0(x, u)))), x, u)

def sym_193.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsPOW{}, 2, sy_is_const(x, sy_src0(x, u)))

def sym_193(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_193.pat(x, u), sym_193.go1(x, u))

# ---- `transcendental.py:267`, `xpow_int` -------------------------------------------
def xi.mask(bits: U32) -> H.I64:
  H.i64_sub(H.i64_shl(H.i64_of_i32(1), U32.to_nat(bits)), H.i64_of_i32(1))

def xi.udt.by(bits: U32) -> Maybe<&2, S.Dt>:
  match bits:
    case 8: Some{S.uint8()}
    case 16: Some{S.uint16()}
    case 32: Some{S.uint32()}
    case 64: Some{S.uint64()}
    case _: None{}

def xi.udt.sleep(uns: Bool, +dt: S.Dt, bits: U32) -> Maybe<&2, S.Dt>:
  match uns:
    case True{} : Some{dt}
    case False{}: xi.udt.by(bits)

def xi.masked(+f: O.Found, v: U32, bits: U32) -> O.Found:
  +k = O.UOp.const(O.Found.ar(f), O.CInt{xi.mask(bits)})
  mint_bin(k, O.OpsAND{}, v, O.Found.i(k))

# `((exponent >> i) & 1).ne(0)` -- three nodes and two bare consts.
# AND `ne(0)` AT THE PIN IS `CMPEQ(CMPEQ(an, 0), False)` AND NOT `CMPNE(an, 0)`. SEE
def xi.cond(+f: O.Found, ex: U32, i: U32) -> O.Found:
  +ci = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(i)})
  +sh = mint_bin(ci, O.OpsSHR{}, ex, O.Found.i(ci))
  +o1 = O.UOp.const(O.Found.ar(sh), O.CInt{H.i64_of_i32(1)})
  +an = mint_bin(o1, O.OpsAND{}, O.Found.i(sh), O.Found.i(o1))
  +z = O.UOp.const(O.Found.ar(an), O.CInt{H.i64_of_i32(0)})
  mint_ne(z, O.Found.i(an), O.Found.i(z))

# ONE DEF, because the stop test and the step would otherwise call each other and Bend refuses
def xi.bitlen.n(n: Nat, +v: H.I64, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: Bool.pick(U32, H.i64_is_zero(v), acc, xi.bitlen.n(p, H.i64_shr(v, 1n), U32.add(acc, 1)))

def xi.bitlen(+v: H.I64) -> U32: xi.bitlen.n(64n, v, 0)

type Xs is Data:
  Xs{f: O.Found, ret: U32, sq: U32}

def Xs.f(s: Xs) -> O.Found:
  match s:
    case Xs{f, ret, sq}: f

def Xs.ret(s: Xs) -> U32:
  match s:
    case Xs{f, ret, sq}: ret

def Xs.sq(s: Xs) -> U32:
  match s:
    case Xs{f, ret, sq}: sq

def xi.step(i: U32, +s: Xs, +ex: U32, +bits: U32) -> Xs:
  +c = xi.cond(Xs.f(s), ex, i)
  +mu = mint_bin(c, O.OpsMUL{}, Xs.ret(s), Xs.sq(s))
  +an = xi.masked(mu, O.Found.i(mu), bits)
  +wh = mint_where(an, O.Found.i(c), O.Found.i(an), Xs.ret(s))
  Xs{wh, O.Found.i(wh), Xs.sq(s)}

def xi.sq1(+s: Xs, +bits: U32) -> Xs:
  +mu = mint_bin(Xs.f(s), O.OpsMUL{}, Xs.sq(s), Xs.sq(s))
  +an = xi.masked(mu, O.Found.i(mu), bits)
  Xs{an, Xs.ret(s), O.Found.i(an)}

def xi.squp(more: Bool, +s: Xs, +bits: U32) -> Xs:
  match more:
    case True{} : xi.sq1(s, bits)
    case False{}: s

def xi.loop(n: Nat, +i: U32, +s: Xs, +ex: U32, +bits: U32, +nb: U32) -> Xs:
  match n:
    case 0n: s
    case 1n+p:
      +s1 = xi.step(i, s, ex, bits)
      +s2 = xi.squp(U32.is_le(U32.add(i, U32.from_nat(1n)), U32.sub(nb, U32.from_nat(1n))), s1, bits)
      xi.loop(p, U32.add(i, U32.from_nat(1n)), s2, ex, bits, nb)

def xi.lo(ofl: Bool, +x: F.Folded, +u: U32) -> H.I64:
  match ofl:
    case True{} : bnd_i64(F.ovf.min_b(Maybe.default(&1, Bool, S.Cls.sgn(S.Dt.cls(sy_dt1(x, sy_src1(x, u)))), False{}),
                                 S.Dt.bits(sy_dt1(x, sy_src1(x, u)))))
    case False{}: vmin_i64(F.Folded.ar(x), sym_280.bt(x), sy_src1(x, u))

def xi.hi(ofl: Bool, +x: F.Folded, +u: U32) -> H.I64:
  match ofl:
    case True{} : bnd_i64(F.ovf.max_b(Maybe.default(&1, Bool, S.Cls.sgn(S.Dt.cls(sy_dt1(x, sy_src1(x, u)))), False{}),
                                 S.Dt.bits(sy_dt1(x, sy_src1(x, u)))))
    case False{}: vmax_i64(F.Folded.ar(x), sym_280.bt(x), sy_src1(x, u))

# `sb.eq(v)` AT THE PIN IS ONE NODE: `CMPEQ(x, v)`.
def xi.eq2(+f: O.Found, x: U32, v: H.I64) -> O.Found:
  +c = O.UOp.const(O.Found.ar(f), O.CInt{v})
  mint_bin(c, O.OpsCMPEQ{}, x, O.Found.i(c))

# `ret.const_like(1)` -- the node's OWN dtype, which for an i32 ret is `CAST(CONST 1)`.
def xi.one_like(+f: O.Found, dt: S.Dt) -> O.Found:
  +c = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(1)})
  O.UOp.cast(O.Found.ar(c), O.Found.i(c), dt)

def xi.bitcast(+f: O.Found, v: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsBITCAST{}, [v], O.ADt{dt}, O.TNone{})

# `(exponent < 0).where(neg, ret)`, and `neg` is the `eq(-1)/eq(1)` pair over the SIGNED bitcast
# of the base. Sequential locals and NO match, so the shapes stay in construction order.
def xi.tail(+r: O.Found, +x: F.Folded, +u: U32, +dt: S.Dt, +b: O.Found) -> Maybe<&1, O.Found>:
  +ex = sy_src1(x, u)
  +sb = xi.bitcast(r, O.Found.i(b), dt)
  +one = xi.one_like(sb, dt)
  +k1 = O.UOp.const(O.Found.ar(one), O.CInt{H.i64_of_i32(1)})
  +an = mint_bin(k1, O.OpsAND{}, ex, O.Found.i(k1))
  +z0 = O.UOp.const(O.Found.ar(an), O.CInt{H.i64_of_i32(0)})
  +nz = mint_ne(z0, O.Found.i(an), O.Found.i(z0))
  +n1 = O.UOp.const(O.Found.ar(nz), O.CInt{H.i64_neg(True{}, H.i64_of_i32(1))})
  +mo = mint_bin(n1, O.OpsMUL{}, O.Found.i(one), O.Found.i(n1))
  +in1 = mint_where(mo, O.Found.i(nz), O.Found.i(mo), O.Found.i(one))
  +e1 = xi.eq2(in1, O.Found.i(sb), H.i64_neg(True{}, H.i64_of_i32(1)))
  +e2 = xi.eq2(e1, O.Found.i(sb), H.i64_of_i32(1))
  +z1 = O.UOp.const(O.Found.ar(e2), O.CInt{H.i64_of_i32(0)})
  +el2 = mint_where(z1, O.Found.i(e2), O.Found.i(one), O.Found.i(z1))
  +ng = mint_where(el2, O.Found.i(e1), O.Found.i(in1), O.Found.i(el2))
  +z2 = O.UOp.const(O.Found.ar(ng), O.CInt{H.i64_of_i32(0)})
  +lt = mint_bin(z2, O.OpsCMPLT{}, ex, O.Found.i(z2))
  Some{mint_where(lt, O.Found.i(lt), O.Found.i(ng), O.Found.i(r))}

def xi.hi0(+v: H.I64) -> H.I64: Bool.pick(H.I64, H.i64_is_neg(v), H.i64_of_i32(0), v)

def xi.cast_or(d: S.Dt, +ar: O.Arena, +s: U32, +dt: S.Dt) -> O.Found:
  Bool.pick(O.Found, O.eq_dt(d, dt), O.Found{ar, s}, O.UOp.cast(ar, s, dt))

def xi.end(ge0: Bool, +r: O.Found, +x: F.Folded, +u: U32, +dt: S.Dt, +b: O.Found) -> Maybe<&1, O.Found>:
  match ge0:
    case True{} : Some{r}
    case False{}: xi.tail(r, x, u, dt, b)

def xi.build(+x: F.Folded, +u: U32, +dt: S.Dt, +ud: S.Dt) -> Maybe<&1, O.Found>:
  +b0 = xi.cast_or(sy_dt1(x, sy_src0(x, u)), sy_ar(x), sy_src0(x, u), dt)
  +bc = xi.bitcast(b0, O.Found.i(b0), ud)
  +one = xi.one_like(bc, ud)
  +bits = S.Dt.bits(dt)
  +edt = sy_dt1(x, sy_src1(x, u))
  +ofl = Bool.and(dt_in(DTS_INTS(), edt),
                  F.UOp.overflows(F.Folded.ar(x), sym_280.bt(x), sy_src1(x, u), edt))
  +lo = xi.lo(ofl, x, u)
  +hi = xi.hi(ofl, x, u)
  +nb = xi.bitlen(xi.hi0(hi))
  +s = xi.loop(U32.to_nat(nb), U32.from_nat(0n), Xs{one, O.Found.i(one), O.Found.i(bc)},
               sy_src1(x, u), bits, nb)
  +r = xi.bitcast(Xs.f(s), Xs.ret(s), dt)
  xi.end(Bool.not(H.i64_is_neg(lo)), r, x, u, dt, bc)

def xi.udt3(m: Maybe<&2, S.Dt>, +x: F.Folded, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{+du}: xi.build(x, u, dt, du)
    case None{}   : None{}

def xi.go(ok: Bool, +x: F.Folded, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match ok:
    case True{} : xi.udt3(xi.udt.sleep(S.Dt.is_unsigned(dt), dt, S.Dt.bits(dt)), x, u, dt)
    case False{}: None{}

# `xpow_int(base, exponent, dt)` -- `dt not in dtypes.ints` is the whole guard.
def xpow_int(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +dt = sy_dt1(x, u)
  xi.go(dt_in(DTS_INTS(), dt), x, u, dt)

# ---- `symbolic.py:451`, the pow rule ----------------------------------------------
def sym_451.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsPOW{}), sy_nsrc_is(x, u, 2))

def sym_451.go(i: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match i:
    case True{} : xpow_int(x, u)
    case False{}: Some{T.xpow(sy_ar(x), sy_src0(x, u), sy_src1(x, u), sy_dt1(x, sy_src1(x, u)))}

def sym_451(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_451.pat(x, u), sym_451.go(S.Cls.is_int(S.Dt.cls(sy_dt1(x, u))), x, u))

# ---- single-entry substitution -----------------------------------------------------
# `t.substitute({key: val})`, which is what `symbolic.py:235` needs, reached WITHOUT Bend's `Map`:
type Ky is Data:
  Ky{k: U32, n: U32}

def Ky.k(x: Ky) -> U32:
  match x:
    case Ky{k, n}: k

def Ky.n(x: Ky) -> U32:
  match x:
    case Ky{k, n}: n

type S1 is Data:
  S1{t: List<&2, Ky>, f: O.Found}

def S1.t(x: S1) -> List<&2, Ky>:
  match x:
    case S1{t, f}: t

def S1.f(x: S1) -> O.Found:
  match x:
    case S1{t, f}: f

type S1s is Data:
  S1s{l: List<&2, U32>, ch: Bool}

def S1s.l(x: S1s) -> List<&2, U32>:
  match x:
    case S1s{l, ch}: l

def S1s.ch(x: S1s) -> Bool:
  match x:
    case S1s{l, ch}: ch

# A MISSING ENTRY MEANS UNCHANGED, because every src is answered BEFORE its parent in the
# post-order list -- so the default is the old index itself.
def s1.get(tbl: List<&2, Ky>, +k: U32) -> U32:
  match tbl:
    case Nil{}: k
    case +h <> t: Bool.pick(U32, U32.is_eq(Ky.k(h), k), Ky.n(h), s1.get(t, k))

def s1.ss.add(+n: U32, s: U32, +acc: S1s) -> S1s:
  S1s{List.append(&2, U32, S1s.l(acc), [n]), Bool.or(S1s.ch(acc), Bool.not(U32.is_eq(n, s)))}

def s1.ss(ss: List<&2, U32>, +tbl: List<&2, Ky>, acc: S1s) -> S1s:
  match ss:
    case Nil{}: acc
    case +s <> t: s1.ss(t, tbl, s1.ss.add(s1.get(tbl, s), s, acc))

# the table comes in and the ARENA comes in separately, because a minted node's arena is the grown
# one and not the one the fold was handed.
def s1.put.t(tbl: List<&2, Ky>, +i: U32, +n: U32, +f: O.Found) -> S1:
  S1{List.append(&2, Ky, tbl, [Ky{i, n}]), f}

# op, arg and tag are PROPERTIES OF THE ORIGINAL and are read out of the fold's arena, which is what
# `mint_replace` does in this file for the same reason.
def s1.one.mint(+i: U32, +s: S1s, +st: S1) -> S1:
  +ar = O.Found.ar(S1.f(st))
  +m = O.UOp.new(ar, O.Arena.op(ar, i), S1s.l(s), O.Arena.arg(ar, i), O.Arena.tag(ar, i))
  s1.put.t(S1.t(st), i, O.Found.i(m), m)

def s1.one.ch(ch: Bool, +i: U32, +s: S1s, +st: S1) -> S1:
  match ch:
    case False{}: s1.put.t(S1.t(st), i, i, S1.f(st))
    case True{} : s1.one.mint(i, s, st)

# the KEY ITSELF is answered by `val` and never descended into.
def s1.one.eq(eq: Bool, +i: U32, +val: U32, +s: S1s, +st: S1) -> S1:
  match eq:
    case True{} : s1.put.t(S1.t(st), i, val, S1.f(st))
    case False{}: s1.one.ch(S1s.ch(s), i, s, st)

def s1.fold(ts: List<&2, U32>, +st: S1, +key: U32, +val: U32) -> S1:
  match ts:
    case Nil{}: st
    case +i <> rest:
      +s = s1.ss(O.Arena.srcs(O.Found.ar(S1.f(st)), i), S1.t(st), S1s{Nil{}, False{}})
      s1.fold(rest, s1.one.eq(U32.is_eq(i, key), i, val, s, st), key, val)

def s1.sub(+ar: O.Arena, +sink: U32, +key: U32, +val: U32) -> O.Found:
  +st = s1.fold(O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, sink), S1{Nil{}, mint_ar(ar)}, key, val)
  +n = s1.get(S1.t(st), sink)
  O.Found{O.Found.ar(S1.f(st)), n}

# the multi-entry form, and it is the first step to `:450`/`:451`. `s1.sub` takes one
def s1.find(tbl: List<&2, Ky>, +k: U32) -> Maybe<&2, U32>:
  match tbl:
    case Nil{}: None{}
    case +h <> t: Bool.pick(Maybe<&2, U32>, U32.is_eq(Ky.k(h), k), Some{Ky.n(h)}, s1.find(t, k))

def s1.multi.one(found: Maybe<&2, U32>, +i: U32, +s: S1s, +st: S1) -> S1:
  match found:
    case Some{+n}: s1.one.eq(True{}, i, n, s, st)
    case None{}: s1.one.eq(False{}, i, i, s, st)

# the replacement for a key, or the key itself -- the default `s1.get` gives, and it is what the
# multi walk substitutes IN PLACE of the key node.
def s1.multi.val(tbl: List<&2, Ky>, +k: U32) -> U32:
  s1.get(tbl, k)

def s1.multi.fold(ts: List<&2, U32>, +st: S1, +tbl: List<&2, Ky>) -> S1:
  match ts:
    case Nil{}: st
    case +i <> rest:
      +s = s1.ss(O.Arena.srcs(O.Found.ar(S1.f(st)), i), S1.t(st), S1s{Nil{}, False{}})
      s1.multi.fold(rest, s1.multi.one(s1.find(tbl, i), i, s, st), tbl)

# THE ENTRY: ONE walk, EVERY pair. `s1.sub` is this with a one-pair table, so it is KEPT as the
# one-pair spelling and this is the many-pair one.
def s1.multi(+ar: O.Arena, +sink: U32, +tbl: List<&2, Ky>) -> O.Found:
  +st = s1.multi.fold(O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, sink), S1{Nil{}, mint_ar(ar)}, tbl)
  # THE ROOT'S OWN REPLACEMENT: if the sink IS a key, the answer is that key's replacement and the
  # walk's copy of it is irrelevant.
  +n = Bool.pick(U32, Maybe.is_some(&2, U32, s1.find(tbl, sink)), s1.get(S1.t(st), sink), s1.get(S1.t(st), sink))
  O.Found{O.Found.ar(S1.f(st)), n}

# ---- `symbolic.py:259`, `fold_where_closure` ---------------------------------------
def sym_259.ix(bs: List<&2, U32>, +ar: O.Arena, acc: Bool) -> Bool:
  match bs:
    case Nil{}: acc
    case h <> t: sym_259.ix(t, ar, Bool.or(acc, O.eq_op(O.Arena.op(ar, h), O.OpsINDEX{})))

# `u.op_in_backward_slice_with_self(Ops.INDEX)` -- the node ITSELF included, which is why the
# reader is `backward_slice_with_self` and not `backward_slice`.
def sym_259.ixs(+x: F.Folded, +u: U32) -> Bool:
  +ar = F.Folded.ar(x)
  +fu = O.Arena.budget(ar)
  Bool.or(sym_259.ix(O.UOp.backward_slice_with_self(fu, ar, sy_src0(x, u)), ar, False{}),
    Bool.or(sym_259.ix(O.UOp.backward_slice_with_self(fu, ar, sy_src1(x, u)), ar, False{}),
             sym_259.ix(O.UOp.backward_slice_with_self(fu, ar, sy_src2(x, u)), ar, False{})))

def sym_259.occ(+x: F.Folded, +u: U32) -> Bool:
  +ar = F.Folded.ar(x)
  +bt = F.mm.sweep(F.Folded.ar(x), F.Folded.t(x))
  +fu = O.Arena.budget(ar)
  +c = sy_src0(x, u)
  Bool.or(F.UOp.bool_slice_has(fu, ar, bt, sy_src1(x, u), c),
          F.UOp.bool_slice_has(fu, ar, bt, sy_src2(x, u), c))

def sym_259.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +c = sy_src0(x, u)
  +bt = O.UOp.const(ar, O.CBool{True{}})
  +bf = O.UOp.const(O.Found.ar(bt), O.CBool{False{}})
  # the arena is the one the consts opened, not the one the graph was handed: an arena is a chain
  # of slots, so two chains minted from the SAME base assign the same indices to DIFFERENT nodes.
  +tt = s1.sub(O.Found.ar(bf), sy_src1(x, u), c, O.Found.i(bt))
  +ff = s1.sub(O.Found.ar(tt), sy_src2(x, u), c, O.Found.i(bf))
  Some{mint_where(ff, c, O.Found.i(tt), O.Found.i(ff))}

def sym_259.not_ix(ix: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ix:
    case True{} : None{}
    case False{}: sym_259.mk(x, u)

def sym_259.hit(occ: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match occ:
    case True{} : sym_259.not_ix(sym_259.ixs(x, u), x, u)
    case False{}: None{}

def sym_259.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3))

def sym_259(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_259.pat(x, u), sym_259.hit(sym_259.occ(x, u), x, u))

# symbolic.py:308  (UPat.var('x').cast(name="a").cast(name="b"),
def sym_308.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(Bool.and(sy_is_op(x, i, O.OpsCAST{}), sy_nsrc_is(x, i, 1)),
      D.can_lossless_cast(sy_dt1(x, sy_src0(x, i)), sy_dt1(x, i))))

def sym_308(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +v = sy_src0(x, sy_src0(x, u))
  sy_tri_f(sym_308.pat(x, u),
    Bool.pick(Maybe<&1, O.Found>, O.eq_dt(sy_dt1(x, v), sy_dt1(x, u)),
      Some{O.Found{sy_ar(x), v}},
      Some{mint_cast(mint_ar(sy_ar(x)), v, sy_dt1(x, u))}))

# symbolic.py:316  ((UPat.var("x", dtypes.weakint) + UPat.cvar("c")).cast(dtypes.sints, name="cast"),
def sym_316.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(p_dt_in(DTS_SINTS(), sy_arg_dt(x, u)),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        Bool.and(Sw.ok(p_const(x, i)), p_weakint(x, Sw.b(p_const(x, i)))))))

def sym_316.join(m: Maybe<&1, O.Found>, +c: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+k}: Some{mint_bin(k, O.OpsADD{}, O.Found.i(c), O.Found.i(k))}
    case None{}: None{}

def sym_316.add(+c: O.Found, +x: F.Folded, +u: U32, +i: U32) -> Maybe<&1, O.Found>:
  sym_316.join(mint_const_v(sy_val(x, Sw.a(p_const(x, i))), c, sy_dt1(x, u)), c)

def sym_316.put(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32, +i: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: sym_316.add(c, x, u, i)
    case None{}: None{}

def sym_316.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sy_src0(x, u)
  sym_316.put(Some{mint_cast(mint_ar(sy_ar(x)), Sw.b(p_const(x, i)), sy_dt1(x, u))}, x, u, i)

def sym_316(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_316.pat(x, u), sym_316.mk(x, u))

# symbolic.py:300  (UPat.var("x", dtypes.weakint)*-1 < UPat.var("y")*-1, lambda x,y: y<x)
def p_mul_neg1(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, s, O.OpsMUL{}), sy_nsrc_is(x, s, 2)),
    p_is_const_neg1(x, Sw.a(p_const(x, s))))

def p_mul_neg1.v(+x: F.Folded, +s: U32) -> U32: Sw.b(p_const(x, s))

def sym_300.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_mul_neg1(x, a), p_mul_neg1(x, b)))

def sym_300(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sy_src0(x, u)
  sy_tri_f(sym_300.pat(x, u),
    Some{mint_bin(mint_ar(sy_ar(x)), O.OpsCMPLT{}, p_mul_neg1.v(x, sy_src1(x, u)), p_mul_neg1.v(x, a))})

# symbolic.py:316  (UPat.var("x", dtypes.sints+(dtypes.weakint,))*-1 < UPat.cvar("c"),
def sym_316c.iv(m: Maybe<&2, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

def sym_316c.hit(ok: Bool, +val: H.I64, v: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match ok:
    case True{}:
      +f = mint_ar(sy_ar(x))
      +n1 = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_neg(True{}, H.i64_of_i32(1))})
      +c = O.UOp.const(O.Found.ar(n1), O.CInt{val})
      +m = mint_bin(c, O.OpsMUL{}, O.Found.i(c), O.Found.i(n1))
      Some{mint_bin(m, O.OpsCMPLT{}, O.Found.i(m), v)}
    case _: None{}

def sym_316c.mk(m: Maybe<&1, H.I64>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+val}:
      +v = p_mul_neg1.v(x, sy_src0(x, u))
      sym_316c.hit(fits(sy_dt1(x, v), H.i64_neg(True{}, val)), val, v, x)
    case None{}: None{}

def sym_316c.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_mul_neg1(x, sy_src0(x, u)), Sw.ok(p_const(x, u))))

def sym_316c(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_316c.mk(Bool.pick(Maybe<&1, H.I64>, sym_316c.pat(x, u), sym_316c.iv(sy_val(x, sy_src1(x, u))), None{}), x, u)

# `UPat(Ops.RANGE, src=UPat.var("end"), name="r")` -- a RANGE whose source is the node the other
# side repeats.
def p_range_of(+x: F.Folded, +r: U32, +e: U32) -> Bool:
  Bool.or(Bool.and(sy_is_op(x, r, O.OpsRANGE{}), sy_nsrc_ge(x, r, 1)),
    False{})

def sym_304.pat(+x: F.Folded, +u: U32) -> Bool:
  +r = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMOD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_range_of(x, r, sy_src1(x, u)), p_same(sy_src0(x, r), sy_src1(x, u))))

# symbolic.py:304  RANGE(end) % end is the RANGE itself: an index over its own upper bound.
def sym_304(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri_u(sym_304.pat(x, u), sy_src0(x, u))

# symbolic.py:305  RANGE(end) // end is 0, and the 0 is minted at the RANGE's dtype.
def sym_305.pat(+x: F.Folded, +u: U32) -> Bool:
  +r = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_range_of(x, r, sy_src1(x, u)), p_same(sy_src0(x, r), sy_src1(x, u))))

def sym_305(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_305.pat(x, u),
    mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:295  ((UPat.var("x") + UPat.cvar("c1")) + UPat.var("y"),
def sym_295.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_284.alu2c(x, sy_src0(x, u), sy_op(x, u)), sy_src0(x, u), sy_src1(x, u))

# the other side is the non-CONST part, and it is the side that is not the inner.
def sym_295.outer(+x: F.Folded, +u: U32, +i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_295.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_295.inner(x, u)
  Bool.and(Bool.and(sy_nsrc_is(x, u, 2), sym_284.alu2c(x, i, sy_op(x, u))),
    Bool.not(sy_is_const(x, sym_295.outer(x, u, i))))

# the guard `:309`/`:311` carry and this body did not: `no_overflow(m:=x op y)`, plus, for `*`,
def sym_295.fitc(c: O.Const, +dt: S.Dt) -> Bool:
  match c:
    case O.CInt{i}: fits(dt, i)
    case _: Bool.not(dt_in(DTS_SINTS(), dt))

def sym_295.ovm(m: Maybe<&2, O.Const>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+c}: sym_295.fitc(c, dt)
    case None{}: False{}

def sym_295.no_ov(+f: O.Found, +i: U32) -> Bool:
  +bt = sym_280.bt(F.folded(O.Found.ar(f)))
  +dt = sy_dt1(F.folded(O.Found.ar(f)), i)
  Bool.and(sym_295.ovm(sym_276.vc(F.UOp.vmin(O.Found.ar(f), bt, i)), dt),
           sym_295.ovm(sym_276.vc(F.UOp.vmax(O.Found.ar(f), bt, i)), dt))

def sym_295.opok(+x: F.Folded, +u: U32, +i: U32) -> Bool:
  Bool.or(O.eq_op(sy_op(x, u), O.OpsADD{}),
    Bool.or(dt_in(DTS_INTWEAK(), sy_dt1(x, sym_284.v(x, i))), p_is_const_neg1(x, sym_284.c(x, i))))

def sym_295.hit(ok: Bool, +s: O.Found, +x: F.Folded, +u: U32, +i: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{mint_bin(s, sy_op(x, u), O.Found.i(s), sym_284.c(x, i))}
    case _: None{}

def sym_295.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_295.inner(x, u)
  # the other side is the non-CONST part, and it is the side that is not the inner -- so the
  # answer is the same WHichever side the inner was on.
  +s = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sym_284.v(x, i), sym_295.outer(x, u, i))
  sym_295.hit(Bool.and(sym_295.opok(x, u, i), sym_295.no_ov(s, O.Found.i(s))), s, x, u, i)

def sym_295(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_295.pat(x, u), sym_295.mk(x, u))

# ONE BODY, TWO NAMES: `:296` is the same rule on `*`, and the op comes off the node.
def sym_296(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_295(x, u)

# symbolic.py:290  ((UPat.cvar("c0") + UPat.var("x", dtype=dtypes.sints+(dtypes.weakint,)))
def sym_290.pat(+x: F.Folded, +u: U32) -> Bool:
  +a = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_const(x, sy_src1(x, u)),
      Bool.and(Bool.and(sy_is_op(x, a, O.OpsADD{}), sy_nsrc_is(x, a, 2)),
        Bool.and(sy_is_const(x, sy_src0(x, a)), p_intish(x, sy_src1(x, a))))))

def sym_290.put(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32, +a: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+n}:
      +d = mint_bin(n, O.OpsMUL{}, sy_src0(x, a), O.Found.i(n))
      +s = mint_bin(d, O.OpsADD{}, sy_src1(x, u), O.Found.i(d))
      Some{mint_bin(s, O.OpsCMPLT{}, sy_src1(x, a), O.Found.i(s))}
    case None{}: None{}

# the guard `:304` carries and this body did not: `fits(x, c1.vmin-c0.vmin)`.
def sym_290.cv(m: Maybe<&2, O.Const>) -> Maybe<&1, H.I64>:
  match m:
    case Some{O.CInt{i}}: Some{i}
    case _: None{}

def sym_290.sub(m: Maybe<&1, H.I64>, n: Maybe<&1, H.I64>) -> Maybe<&1, H.I64>:
  match m:
    case Some{+p}:
      match n:
        case Some{+q}: Some{H.i64_sub(p, q)}
        case None{}: None{}
    case None{}: None{}

def sym_290.fit(m: Maybe<&1, H.I64>, +dt: S.Dt) -> Bool:
  match m:
    case Some{+v}: fits(dt, v)
    case None{}: False{}

def sym_290.hit(ok: Bool, +x: F.Folded, +u: U32, +a: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}:
      sym_290.put(mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, a), O.CInt{H.i64_of_i32(4294967295)}), x, u, a)
    case _: None{}

def sym_290.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sy_src0(x, u)
  sym_290.hit(sym_290.fit(sym_290.sub(sym_290.cv(sy_val(x, sy_src1(x, u))),
                                      sym_290.cv(sy_val(x, sy_src0(x, a)))),
                                 sy_dt1(x, sy_src1(x, a))), x, u, a)

def sym_290(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_290.pat(x, u), sym_290.mk(x, u))

# two constants with the same value, and the join of two `Maybe`s is a nested match because a
# `Data` payload cannot be compared through a `Type`.
def p_consteq.b(a: O.Const, mb: Maybe<&2, O.Const>) -> Bool:
  match mb:
    case Some{b}: O.eq_const(a, b)
    case _: False{}

def p_consteq.a(ma: Maybe<&2, O.Const>, mb: Maybe<&2, O.Const>) -> Bool:
  match ma:
    case Some{a}: p_consteq.b(a, mb)
    case _: False{}

def p_consteq(+x: F.Folded, +u: U32, +w: U32) -> Bool: p_consteq.a(sy_val(x, u), sy_val(x, w))

# symbolic.py:278  ((UPat.cvar("a") < UPat.var("b")).where(UPat.var("b"), UPat.cvar("c")),
def sym_278.pat(+x: F.Folded, +u: U32) -> Bool:
  +c = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(Bool.and(sy_is_op(x, c, O.OpsCMPLT{}), sy_nsrc_is(x, c, 2)),
      Bool.and(sy_is_const(x, sy_src0(x, c)),
        Bool.and(p_same(sy_src1(x, c), sy_src1(x, u)),
          Bool.and(sy_is_const(x, sy_src2(x, u)),
            p_consteq(x, sy_src0(x, c), sy_src2(x, u)))))))

def sym_278(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +c = sy_src0(x, u)
  sy_tri_f(sym_278.pat(x, u),
    Some{mint_bin(mint_ar(sy_ar(x)), O.OpsMAX{}, sy_src0(x, c), sy_src1(x, c))})

# symbolic.py:279  ((UPat.var("a") < UPat.cvar("b")).where(UPat.cvar("c"), UPat.var("a")),
def sym_279.pat(+x: F.Folded, +u: U32) -> Bool:
  +c = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(Bool.and(sy_is_op(x, c, O.OpsCMPLT{}), sy_nsrc_is(x, c, 2)),
      Bool.and(p_same(sy_src0(x, c), sy_src2(x, u)),
        Bool.and(sy_is_const(x, sy_src1(x, c)),
          Bool.and(sy_is_const(x, sy_src1(x, u)),
            p_consteq(x, sy_src1(x, c), sy_src1(x, u)))))))

def sym_279(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +c = sy_src0(x, u)
  sy_tri_f(sym_279.pat(x, u),
    Some{mint_bin(mint_ar(sy_ar(x)), O.OpsMAX{}, sy_src0(x, c), sy_src1(x, c))})

# symbolic.py:287  ((UPat.var("x") // UPat.cvar("c1")) // UPat.cvar("c2"),
def sym_287.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_const(x, sy_src1(x, u)),
      Bool.and(p_const_pos(x, sy_src1(x, u)),
        Bool.and(Bool.and(sy_is_op(x, i, O.OpsDIV{}), sy_nsrc_is(x, i, 2)),
          sy_is_const(x, sy_src1(x, i))))))

def sym_287.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sy_src0(x, u)
  +m = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, sy_src1(x, i), sy_src1(x, u))
  Some{mint_bin(m, O.OpsDIV{}, sy_src0(x, i), O.Found.i(m))}

def sym_287(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_287.pat(x, u), sym_287.mk(x, u))

def sym_191.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsPOW{}, 2, Bool.and(sy_is_const(x, sy_src1(x, u)), Bool.not(Bool.and(p_const_neg(x, sy_src1(x, u)), p_intweak(x, sy_src0(x, u))))))

def sym_191(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_191.pat(x, u), simplify_pow_f(mint_ar(sy_ar(x)), x, sy_src0(x, u), sy_src1(x, u)))

# THE REWRITER. `PatternMatcher.rewrite` -- ops.py:1603-1610:
# `spec.bend` writes this five more times than this file does because a dispatch
def sy_novel.hit(same: Bool, i: U32) -> Maybe<&1, U32>:
  match same:
    case True{}: None{}
    case _: Some{i}

def sy_novel.go(self: U32, m: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match m:
    case Some{+i}: sy_novel.hit(U32.is_eq(i, self), i)
    case _: None{}

def sy_novel(self: U32, m: Maybe<&1, U32>) -> Maybe<&1, U32>:
  sy_novel.go(self, m)

# FIRST-WINS. Keying on the ACCUMULATOR is what makes it first-wins: keying on the
# new answer is last-wins, and a rule that skips then erases every earlier verdict.
def sy_keep.go(acc: Maybe<&1, U32>, v: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match acc:
    case Some{i}: Some{i}
    case _: v

# THE TABLE. One entry per rule, in symbolic.py's order, so tag N is
# `(symbolic.py line, N)` by construction. `ops` is the op set `pdict` keys on and
# `rej` is `early_reject` -- the op of the pattern's FIRST src, and only when that
# src is a SINGLE-op UPat (ops.py:1475-1478).
def OP_INVALID() -> List<&2, O.Op>: [O.OpsCONST{}]

# `symbolic.py:201` -- `(UPat.var().where(UPat.var("val"), UPat.var("val")), lambda val: val)`.
# it comes before :202 in the table and the order is LOAD-bearing: `WHERE(CONST_gate, x, x)`
def sy_wself.of(is_where: Bool, differ: Bool, +v: U32) -> Maybe<&1, U32>:
  match is_where differ:
    case True{}  False{}: Some{v}
    case _       _      : None{}

def sy_wself(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_wself.of(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
              Bool.not(U32.is_eq(sy_src1(x, u), sy_src2(x, u))), sy_src1(x, u))

# `fold_const_where` -- symbolic.py:113, THE BODY OF THE RULE AT :202.
def sy_fcw_pick(truthy: Bool, +c0: U32, +c1: U32) -> U32:
  match truthy:
    case True{} : c0
    case False{}: c1

def sy_fcw_cast(go: Bool, ret: U32, +x: F.Folded, +u: U32, wd: S.Dt) -> Maybe<&1, U32>:
  match go:
    case False{}: Some{ret}
    case True{} : sy_ccast(x, ret, wd)

def sy_fcw_emit(hit: Bool, go: Bool, ret: U32, +x: F.Folded, +u: U32, wd: S.Dt) -> Maybe<&1, U32>:
  match hit:
    case False{}: None{}
    case True{} : sy_fcw_cast(go, ret, x, u, wd)

def sy_fcw(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +ret = sy_fcw_pick(sy_val_truthy(x, sy_src0(x, u)), sy_src1(x, u), sy_src2(x, u))
  sy_fcw_emit(p_cgate(x, u),
              Bool.and(sy_is_const(x, ret),
                       Bool.and(dt_weak_of(sy_dt1(x, ret)),
                                Bool.not(dt_weak_of(sy_dt1(x, u))))),
              ret, x, u, sy_dt1(x, u))

# `symbolic.py:174` -- `((UPat.var("x") * UPat.var("x2")) / UPat.var("x2"), lambda x,x2: x)`.
def sym_174.deep(+x: F.Folded, +a: U32, +b: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, a, O.OpsMUL{}), sy_nsrc_is(x, a, 2)),
    Bool.and(sy_is_op(x, b, O.OpsRECIP{}),
      Bool.and(U32.is_eq(sy_src0(x, b), sy_src1(x, a)),
        # the zero guard: `x2` is the divisor, and `(x * 0) / 0` is `0 / 0` and not `x`.
        Bool.not(p_is_const_0(x, sy_src1(x, a))))))

def sym_174.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_is(x, u, O.OpsMUL{}, 2, Bool.and(p_weakint(x, u), sym_174.deep(x, sy_src0(x, u), sy_src1(x, u))))
  # and the weakint guard, because upstream deleted the rule for the FLOAT reason:
  # and the port keeps the rule for the integers WHERE upstream's deletion leaves the
  # optimisation on the table -- so the port's rule is the guarded form of upstream's deleted one
  # AND NOT A DIVERGENCE.

def sym_174(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_174.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})

def valid_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsAND{}],   OP_INVALID()},   # 450
    O.PMEntry{1, [O.OpsWHERE{}], OP_INVALID()}]}  # 451

def sym_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSTACK{}],                   OP_INVALID(),                    },   # 89
    O.PMEntry{1, OP_UNARY(),                       OP_INVALID(),                    },   # 90
    O.PMEntry{2, OP_UNARY(),                       OP_INVALID(),                    },   # 91
    O.PMEntry{3, OP_BINARY(),                     [O.OpsWHERE{}],                  },   # 94
    O.PMEntry{4, OP_BINARY(),                     [O.OpsWHERE{}],                  },   # 95
    O.PMEntry{5, OP_BINARY_NC(),                   OP_INVALID(),                    },   # 96
    O.PMEntry{6, [O.OpsREDUCE{}],                   Nil{},                           },   # 97
    O.PMEntry{7, [O.OpsWHERE{}],                   OP_INVALID(),                    },   # 99
    O.PMEntry{8, [O.OpsWHERE{}],                   [O.OpsWHERE{}],                    },   # 100
    O.PMEntry{9, [O.OpsWHERE{}],                   Nil{},                           },   # 102
    O.PMEntry{10, [O.OpsWHERE{}], Nil{}, },   # 104
    O.PMEntry{11, [O.OpsWHERE{}], [O.OpsWHERE{}], },   # 106
    O.PMEntry{12, [O.OpsSTORE{}],                   OP_INVALID(),                    },   # 108
    O.PMEntry{13, [O.OpsLOAD{}],                    OP_INVALID(),                    },   # 110
    O.PMEntry{14, OP_SELF(),                        Nil{},                           },   # 126
    O.PMEntry{15, OP_SHIFTS(),                      Nil{},                           },   # 127
    O.PMEntry{16, [O.OpsMUL{}],                     Nil{},                           },   # 128
    O.PMEntry{17, [O.OpsDIV{}],                Nil{},                           },   # 129
    O.PMEntry{18, [O.OpsDIV{}],                Nil{},                           },   # 130
    O.PMEntry{19, [O.OpsDIV{}],                Nil{},                           },   # 131
    O.PMEntry{20, [O.OpsXOR{}],                     Nil{},                           },   # 132
    O.PMEntry{21, [O.OpsMOD{}],                [O.OpsMOD{}],               },   # 133
    O.PMEntry{22, [O.OpsADD{}], Nil{}, },   # 135
    O.PMEntry{23, [O.OpsAND{}],                     Nil{},                           },   # 136
    O.PMEntry{24, [O.OpsOR{}],                      Nil{},                           },   # 137
    O.PMEntry{25, [O.OpsCMPEQ{}], Nil{}, },   # 138
    O.PMEntry{26, OP_IDEMPOTENT(),                  Nil{},                           },   # 139
    O.PMEntry{27, [O.OpsCMPEQ{}], Nil{}, },   # 140
    O.PMEntry{28, [O.OpsWHERE{}],                   Nil{},                           },   # 141
    O.PMEntry{29, [O.OpsWHERE{}],                   Nil{},                           },   # 142
    O.PMEntry{30, [O.OpsCMPEQ{}],                   [O.OpsCAST{}, O.OpsCONST{}],     },   # 144
    O.PMEntry{31, [O.OpsTRUNC{}],                   Nil{},                           },   # 146
    O.PMEntry{32, [O.OpsCMPLT{}],                   Nil{},                           },   # 148
    O.PMEntry{33, [O.OpsMOD{}],                Nil{},                           },   # 149
    O.PMEntry{34, [O.OpsXOR{}],                     Nil{},                           },   # 150
    O.PMEntry{35, [O.OpsAND{}],                     Nil{},                           },   # 151
    O.PMEntry{36, [O.OpsSHR{}],                     [O.OpsAND{}, O.OpsCONST{}],      },   # 153
    O.PMEntry{37, [O.OpsCMPEQ{}],                   Nil{},                           },   # 155
    O.PMEntry{38, [O.OpsCAST{}], Nil{}, },   # 159
    O.PMEntry{39, [O.OpsCAST{}], Nil{}, },   # 161
    O.PMEntry{40, OP_ALU_NT(),                     Nil{},                           },   # 165
    O.PMEntry{41, OP_ALU_NT(), Nil{}, },   # 166
    O.PMEntry{42, OP_BINARY_3F(),                   Nil{},                           },   # 167
    O.PMEntry{43, [O.OpsMAX{}], Nil{}, },   # 171
    O.PMEntry{44, [O.OpsOR{}], Nil{}, },   # 171
    O.PMEntry{45, [O.OpsAND{}], Nil{}, },   # 171
    O.PMEntry{46, [O.OpsADD{}], Nil{}, },   # 171
    O.PMEntry{47, [O.OpsMUL{}], Nil{}, },   # 171
    O.PMEntry{48, [O.OpsXOR{}], Nil{}, },   # 171
    O.PMEntry{49, [O.OpsMUL{}], Nil{}, },   # 175
    O.PMEntry{50, [O.OpsADD{}],                     Nil{},                           },   # 176
    O.PMEntry{51, [O.OpsMAX{}],                     Nil{},                           },   # 177
    O.PMEntry{52, [O.OpsMUL{}],                     Nil{},                           },   # 179
    O.PMEntry{53, [O.OpsMUL{}],                     Nil{},                           },   # 181
    O.PMEntry{54, [O.OpsMUL{}],                     Nil{},                           },   # 185
    O.PMEntry{55, OP_CASTS(),                       Nil{},                           },   # 188
    O.PMEntry{56, [O.OpsBITCAST{}],                 Nil{},                           },   # 190
    O.PMEntry{57, [O.OpsCAST{}], Nil{}, },   # 193
    O.PMEntry{58, [O.OpsBITCAST{}], Nil{}, },   # 195
    O.PMEntry{59, [O.OpsCAST{}],                    Nil{},                           },   # 196
    O.PMEntry{60, [O.OpsPOW{}],                     Nil{},                           },   # 198
    O.PMEntry{61, [O.OpsPOW{}], Nil{}, },   # symbolic.py:200
    O.PMEntry{62, [O.OpsCAST{}],                    [O.OpsOR{}],                     },   # 203
    O.PMEntry{63, [O.OpsSHR{}],                     [O.OpsOR{}, O.OpsCONST{}],       },   # 204
    O.PMEntry{64, [O.OpsWHERE{}],                  Nil{},                           },   # 208
    O.PMEntry{65, [O.OpsWHERE{}],                  Nil{},                           },   # 209
    O.PMEntry{66, [O.OpsSHRINK{}], Nil{}, },   # movement.py:7
    O.PMEntry{67, [O.OpsRESHAPE{}], Nil{}, },   # movement.py:10
    O.PMEntry{68, [O.OpsRESHAPE{}], Nil{}, },   # movement.py:12
    O.PMEntry{69, [O.OpsPERMUTE{}], Nil{}, },   # movement.py:14
    O.PMEntry{70, [O.OpsSTACK{}], Nil{}, },   # movement.py:17
    O.PMEntry{71, [O.OpsINDEX{}], Nil{}, },   # movement.py:20
    O.PMEntry{72, [O.OpsINDEX{}], Nil{}, },   # movement.py:23
    O.PMEntry{73, [O.OpsINDEX{}], Nil{}, },   # movement.py:26
    O.PMEntry{74, [O.OpsADD{}, O.OpsAND{}, O.OpsCMPEQ{}, O.OpsCMPNE{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsOR{}, O.OpsXOR{}], Nil{}, },   # 237
    O.PMEntry{75, [O.OpsOR{}], Nil{}, },   # 250
    O.PMEntry{76, [O.OpsADD{}], Nil{}, },   # 253
    O.PMEntry{77, [O.OpsADD{}], Nil{}, },   # 254
    O.PMEntry{78, [O.OpsADD{}], Nil{}, },   # 256
    O.PMEntry{79, [O.OpsADD{}], Nil{}, },   # 258
    O.PMEntry{80, [O.OpsADD{}], Nil{}, },   # 260
    O.PMEntry{81, [O.OpsADD{}], Nil{}, },   # 262
    O.PMEntry{82, [O.OpsADD{}], Nil{}, },   # 263
    O.PMEntry{83, [O.OpsMUL{}], Nil{}, },   # 265
    O.PMEntry{84, [O.OpsWHERE{}], Nil{}, },   # 267
    O.PMEntry{85, [O.OpsWHERE{}], Nil{}, },   # symbolic.py:270
    O.PMEntry{86, [O.OpsCMPEQ{}], Nil{}, },   # 271
    O.PMEntry{87, [O.OpsWHERE{}], Nil{}, },   # 273
    O.PMEntry{88, [O.OpsWHERE{}], Nil{}, },   # 275
    O.PMEntry{89, [O.OpsWHERE{}], Nil{}, },   # 277
    O.PMEntry{90, OP_BINARY(), Nil{}, },   # 279
    O.PMEntry{91, [O.OpsADD{}], Nil{}, },   # 282
    O.PMEntry{92, [O.OpsADD{}], Nil{}, },   # 285
    O.PMEntry{93, [O.OpsCMPLT{}, O.OpsCMPEQ{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsPARAM{}, O.OpsSPECIAL{}], Nil{}, },   # 287
    O.PMEntry{94, [O.OpsRANGE{}], Nil{}, },   # 289
    O.PMEntry{95, [O.OpsWHERE{}], Nil{}, },   # 291
    O.PMEntry{96, [O.OpsWHERE{}], Nil{}, },   # 293
    O.PMEntry{97, [O.OpsMAX{}], Nil{}, },   # 295
    O.PMEntry{98, [O.OpsDIV{}], Nil{}, },   # 299
    O.PMEntry{99, [O.OpsCMPLT{}], Nil{}, },   # 303
    O.PMEntry{100, [O.OpsCMPLT{}], Nil{}, },   # 306
    O.PMEntry{101, [O.OpsADD{}], Nil{}, },   # 309
    O.PMEntry{102, [O.OpsMUL{}], Nil{}, },   # 310
    O.PMEntry{103, [O.OpsCMPLT{}], Nil{}, },   # symbolic.py:314
    O.PMEntry{104, [O.OpsCMPLT{}], Nil{}, },   # 315
    O.PMEntry{105, [O.OpsCMPLT{}], Nil{}, },   # 316
    O.PMEntry{106, [O.OpsCMPEQ{}], Nil{}, },   # 318
    O.PMEntry{107, [O.OpsMOD{}], Nil{}, },   # 320
    O.PMEntry{108, [O.OpsDIV{}], Nil{}, },   # 321
    O.PMEntry{109, [O.OpsCAST{}], Nil{}, },   # 324
    O.PMEntry{110, [O.OpsCAST{}], Nil{}, },   # symbolic.py:325
    O.PMEntry{111, OP_BINARY(), Nil{}, },   # symbolic.py:327
    O.PMEntry{112, [O.OpsCAST{}], Nil{}, },   # 332
    O.PMEntry{113, [O.OpsAFTER{}], Nil{}, },   # 334
    O.PMEntry{114, [O.OpsAFTER{}, O.OpsEND{}], Nil{}, },   # 338
    O.PMEntry{115, [O.OpsDIV{}], Nil{}, },   # divandmod.py:96
    O.PMEntry{116, [O.OpsDIV{}, O.OpsMOD{}], Nil{}, },   # divandmod.py:98
    O.PMEntry{117, [O.OpsDIV{}, O.OpsMOD{}], Nil{}, },   # divandmod.py:103
    O.PMEntry{118, [O.OpsADD{}, O.OpsAND{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsMAX{}, O.OpsMULACC{}, O.OpsMUL{}, O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsXOR{}, O.OpsWHERE{}], Nil{}, },   # weak.py:97
    O.PMEntry{119, [O.OpsPOW{}], Nil{}, },   # symbolic.py:465
    O.PMEntry{120, [O.OpsSTORE{}], Nil{}, },   # 467
    O.PMEntry{121, [O.OpsSTORE{}], Nil{}, },   # 468
    O.PMEntry{130, [O.OpsSTORE{}], Nil{}, },   # 471
    O.PMEntry{122, [O.OpsSTORE{}], Nil{}, },   # 474
    O.PMEntry{123, [O.OpsSTORE{}], Nil{}, },   # 476
    O.PMEntry{124, [O.OpsMUL{}], Nil{}, },   # symbolic.py:478
    O.PMEntry{125, [O.OpsMUL{}], Nil{}, },   # symbolic.py:479
    O.PMEntry{126, [O.OpsMUL{}], Nil{}, },   # symbolic.py:480
    O.PMEntry{127, [O.OpsREDUCE{}], Nil{}, },   # symbolic.py:482
    O.PMEntry{128, [O.OpsMUL{}], Nil{}, },   # 485
    O.PMEntry{129, [O.OpsSINK{}],                    Nil{},                           }]}   # 458

# `pm_remove_invalid` is a SEPARATE MATCHER in Python -- `codegen/__init__.py:367`
def rm_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsWHERE{}], OP_INVALID()},                            # 115
    O.PMEntry{1, [O.OpsSTACK{}], Nil{}}]}                                 # 116

# THE DECLARED LENGTHS, and they are a sum of unit counts so that a DROPPED table
def nats.go(xs: List<&2, Nat>, n: Nat) -> Nat:
  match xs:
    case Nil{}: n
    case a <> t: nats.go(t, Nat.add(n, a))

def nats(xs: List<&2, Nat>) -> Nat: nats.go(xs, 0n)

def rm_table_len() -> Nat: nats([1n, 1n])
def valid_table_len() -> Nat: nats([1n, 1n])

def sym_table_len() -> Nat:
  nats([1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n])

# THE DRIVER, twice. `sym_*` for the `sym` composition and `rm_*` for
def sym_dispatch.go(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match tag:
    case 1: sym_83(x, u)
    case 5: sym_89(x, u)
    case 7: sym_92(x, u)
    case 12: sym_101(x, u)
    case 13: sym_103(x, u)
    case 14: sym_120(x, u)
    case 15: sym_121(x, u)
    case 16: sym_122(x, u)
    case 18: sym_124(x, u)
    case 20: sym_126(x, u)
    case 21: sym_127(x, u)
    case 23: sym_130(x, u)
    case 24: sym_131(x, u)
    case 26: sym_133(x, u)
    case 27: sym_134(x, u)
    case 25: sym_138(x, u)
    case 28: sym_135(x, u)
    case 31: sym_140(x, u)
    case 35: sym_145(x, u)
    case 53: sym_174(x, u)
    case 54: sym_178(x, u)
    case 55: sym_181(x, u)
    case 56: sym_183(x, u)
    case 57: sym_186(x, u)
    case 62: sym_196(x, u)
    case 63: sym_197(x, u)
    case 64: sy_wself(x, u)
    case 97: sym_280(x, u)
    case 107: sym_304(x, u)
    case 114: sym_322(x, u)
    case _: None{}

def sym_dispatch(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sym_dispatch.go(tag, x, u)

def sym_try.pick(ok: Bool, tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: sy_novel(u, sym_dispatch(tag, x, u))
    case _: None{}

def sym_try(ts: O.PMEntrys, +x: F.Folded, +u: U32, +e: O.PMEntry) -> Maybe<&1, U32>:
  sym_try.pick(Bool.and(O.op_in(O.PMEntry.ops(e), O.Arena.op(sy_ar(x), u)),
                         O.pm_early(ts, sy_ar(x), u, O.PMEntry.rej(e))),
               O.PMEntry.tag(e), x, u)

def sym_scan(+ts: O.PMEntrys, +x: F.Folded, +u: U32, todo: List<&2, O.PMEntry>, acc: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match todo:
    case Nil{}: acc
    case e <> t: sym_scan(ts, x, u, t, sy_keep.go(acc, sym_try(ts, x, u, e)))

def sym_rewrite(+ts: O.PMEntrys, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sym_scan(ts, x, u, O.PMEntrys.es(ts), None{})

def sym(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sym_rewrite(sym_table(), x, u)

# the `Found` family -- the same table, the same order, and an answer that carries the arena.
# WHY IT EXISTS. `sym` answers `Maybe<&1, U32>`: an index and NO ARENA. A rule whose body MINTS
# therefore cannot answer at all -- it can only return an index into an arena the caller never
# sees. MEASURED: 55 of the 88 MISSING rules mint, so the majority of what is left is blocked by
def sy_lift(m: Maybe<&1, U32>, +ar: O.Arena) -> Maybe<&1, O.Found>:
  match m:
    case None{} : None{}
    case Some{i}: Some{O.Found{ar, i}}

# `UOp.const(v, dt)` AT AN EXPLICIT ARENA, carrying the arena `O.UOp.const` grew.
def sy_cconst_f.mk(+f: O.Found, dt: S.Dt) -> Maybe<&1, O.Found>:
  Some{mint_cast(f, O.Found.i(f), dt)}

def sy_cconst_f.go(tv: Maybe<&1, O.Const>, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, O.Found>:
  match tv:
    case Some{w}: sy_cconst_f.mk(O.UOp.const(ar, w), dt)
    case None{}: None{}

def sy_cconst_f(+ar: O.Arena, +dt: S.Dt, v: O.Const) -> Maybe<&1, O.Found>:
  sy_cconst_f.go(sy_trunc(dt, v), ar, dt)

# `UOp.ccast(dtype)` -- the CONST branch mints a const, the other branch casts the node. Both
# carry the arena here, which is the whole difference from `sy_ccast`.
def sy_ccast_f.of(is_const: Bool, v: Maybe<&2, O.Const>, +ar: O.Arena, +u: U32, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match is_const:
    case True{} : sy_cconst_f(ar, dt, sy_maybe_c2(v))
    case False{}: Some{mint_cast(O.Found{ar, u}, u, dt)}

def sy_ccast_f(+x: F.Folded, +u: U32, dt: S.Dt) -> Maybe<&1, O.Found>:
  sy_ccast_f.of(sy_is_const(x, u), sy_val(x, u), sy_ar(x), u, dt)

# `fold_const_where` answering with the arena -- `symbolic.py:202`'s `ccast` branch, which is the
def sy_fcw_f.cast(go: Bool, ret: U32, +x: F.Folded, +u: U32, dt: S.Dt) -> Maybe<&1, O.Found>:
  match go:
    case False{}: Some{O.Found{sy_ar(x), ret}}
    case True{} : sy_ccast_f(x, ret, dt)

def sy_fcw_f.emit(hit: Bool, go: Bool, ret: U32, +x: F.Folded, +u: U32, dt: S.Dt) -> Maybe<&1, O.Found>:
  match hit:
    case False{}: None{}
    case True{} : sy_fcw_f.cast(go, ret, x, u, dt)

def sy_fcw_f(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ret = sy_fcw_pick(sy_val_truthy(x, sy_src0(x, u)), sy_src1(x, u), sy_src2(x, u))
  sy_fcw_f.emit(p_cgate(x, u),
                Bool.and(sy_is_const(x, ret),
                         Bool.and(dt_weak_of(sy_dt1(x, ret)),
                                  Bool.not(dt_weak_of(sy_dt1(x, u))))),
                ret, x, u, sy_dt1(x, u))

# `symbolic.py:87` AND `:88` -- `invalid_gate` LIFTED THROUGH A BINARY OP.
def sy_uprod_cls(c: S.Cls) -> O.Op:
  match c:
    case S.CBool{}: O.OpsAND{}
    case _        : O.OpsMUL{}

def sy_uprod_op(d: S.Dt) -> O.Op:
  match d:
    case S.Dt{pri, bits, c, nm}: sy_uprod_cls(c)

# THE SHRINKING ARGUMENT COMES FIRST. Bend reads a self-call's arguments left to right and each
# must be passed UNCHANGED until one shrinks; `f` changes on every step (it is the arena the mint
# grew), so it cannot precede `xs`. MEASURED: with `(f, op, xs, acc)` the compiler answered
def sy_uprod_f(xs: List<&2, U32>, +f: O.Found, +op: O.Op, acc: U32) -> O.Found:
  match xs:
    case Nil{}  : f
    case x <> t :
      +f2 = mint_alu(op, f, [acc, x])
      sy_uprod_f(t, f2, op, O.Found.i(f2))

# The entry. `self` is the RECEIVER, so the op is read off ITS dtype and `rest` is `*uops`.
def sy_uprod(+x: F.Folded, +self: U32, rest: List<&2, U32>) -> Maybe<&1, O.Found>:
  Some{sy_uprod_f(rest, O.Found{sy_ar(x), self}, sy_uprod_op(sy_dt1(x, self)), self)}

# `invalid_gate` -- `WHERE(cond, x, Invalid)` and nothing looser.
def p_ig3(+x: F.Folded, +a: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, a, O.OpsWHERE{}), sy_nsrc_is(x, a, 3)),
           sy_is_invalid_const(x, sy_src2(x, a)))

def sym_87.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.binary(sy_op(x, u)), sy_nsrc_is(x, u, 2)),
           p_ig3(x, sy_src0(x, u)))

def sym_88.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.binary(sy_op(x, u)), sy_nsrc_is(x, u, 2)),
           p_ig3(x, sy_src1(x, u)))

# ONE BODY FOR THE PAIR: `(g, y)` in that order, the gate's `x` first inside the op for :87 and
def sym_87.mk(+f: O.Found, +op: O.Op, +g: U32, +y: U32) -> Maybe<&1, O.Found>:
  +ar = O.Found.ar(f)
  +f1 = mint_alu(op, f, [O.Arena.src(ar, g, 1), y])
  Some{mint_where(f1, O.Arena.src(ar, g, 0), O.Found.i(f1), O.Arena.src(ar, g, 2))}

# the pattern is the rule. `pat` existed and nothing called it, so both of these fired on
# EVERY binary op and rewrote it into `cond.where(x.alu(op,y), i)` with `cond`/`i` read out of
# whatever `src0` was. MEASURED 2026-11-03: `(cmpne (where gb x c0) c0)` answered
def sym_87(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_87.pat(x, u), sym_87.mk(O.Found{sy_ar(x), u}, sy_op(x, u), sy_src0(x, u), sy_src1(x, u)))

# `y.alu(op, x)` AND NOT `x.alu(op, y)`: the gate is src1 here, so the ROOT's src0 comes
def sym_88.mk(+f: O.Found, +op: O.Op, +g: U32, +y: U32) -> Maybe<&1, O.Found>:
  +ar = O.Found.ar(f)
  +f1 = mint_alu(op, f, [y, O.Arena.src(ar, g, 1)])
  Some{mint_where(f1, O.Arena.src(ar, g, 0), O.Found.i(f1), O.Arena.src(ar, g, 2))}

def sym_88(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_88.pat(x, u), sym_88.mk(O.Found{sy_ar(x), u}, sy_op(x, u), sy_src1(x, u), sy_src0(x, u)))

# ONE BODY FOR THE PAIR: `(g, y)` in that order, the gate's `x` first inside the op for :87 and
# the swapped pair for :88 -- which is exactly the two upstream lambdas.
# `symbolic.py:90` -- `(invalid_gate.reduce(allow_any_len=True, name="red"), lift_reduce_gate)`
type KS is Data:
  KS{keep: List<&2, U32>, lift: List<&2, U32>}

def KS.keep(x: KS) -> List<&2, U32>:
  match x:
    case KS{k, l}: k

def KS.lift(x: KS) -> List<&2, U32>:
  match x:
    case KS{k, l}: l

# `rr in c.ranges` for one reduce range `r`: the term's range SET against the node.
# not wired, and the reason is a tag and not a doubt. `:90`'s entry belongs between `:89`
# (tag 5, `OP_BINARY_NC`) and `:92` (tag 6), so inserting it makes it tag 6 and SHIFTS FORTY-FOUR
# TAGS by one -- and `MINT_TAGS`, `sym_mint_f`'s arms and the census's mapping all read tags. THE
# body below is therefore unreachable until that insertion, and it is committed unreachable on
# purpose: wiring it to `case 5` would dispatch `symbolic.py:89`'s nodes to THIS body, and `:89`
def sym_90.mem(+ar: O.Arena, +rt: F.RTable, +c: U32, +r: U32) -> Bool:
  F.mem_u32(F.Rng.rs(F.UOp.ranges(ar, rt, c)), r)

def sym_90.any(+ar: O.Arena, +rt: F.RTable, +c: U32, +rs: List<&2, U32>) -> Bool:
  match rs:
    case Nil{} : False{}
    case r <> t: Bool.or(sym_90.mem(ar, rt, c, r), sym_90.any(ar, rt, c, t))

def sym_90.put(hit: Bool, +c: U32, +acc: KS) -> KS:
  match hit:
    case True{} : KS{List.append(&2, U32, KS.keep(acc), [c]), KS.lift(acc)}
    case False{}: KS{KS.keep(acc), List.append(&2, U32, KS.lift(acc), [c])}

def sym_90.part(ts: List<&2, U32>, +rs: List<&2, U32>, +ar: O.Arena, +rt: F.RTable, +acc: KS) -> KS:
  match ts:
    case Nil{} : acc
    case +c <> t: sym_90.part(t, rs, ar, rt, sym_90.put(sym_90.any(ar, rt, c, rs), c, acc))

# `xs.upred(*rest)` from the FIRST element: `sy_uprod_f` folds `acc op x` over the tail.
# `keep[0].uprod(*keep[1:])` -- THE FIRST ELEMENT IS THE RECEIVER, so the answer's INDEX is
# `xs[0]` when the tail is empty and NOT the `Found` we were handed. MEASURED: seeding with `f`
def sym_90.up(xs: List<&2, U32>, +f: O.Found, +op: O.Op) -> O.Found:
  match xs:
    case Nil{} : f
    case +x <> t: sy_uprod_f(t, O.Found{O.Found.ar(f), x}, op, x)

def sym_90.rep(+ar: O.Arena, +red: U32, +in2: U32) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, red),
            List.append(&2, U32, [in2], O.Arena.src_from(ar, red, 1)),
            O.Arena.arg(ar, red), O.Arena.tag(ar, red))

def sym_90.inner(keep: List<&2, U32>, +f: O.Found, +op: O.Op, +ar: O.Arena, +xa: U32, +inv: U32) -> U32:
  match keep:
    case Nil{} : xa
    case _ <> _:
      +fw = sym_90.up(keep, f, op)
      O.Found.i(mint_where(fw, O.Found.i(fw), xa, inv))

def sym_90.out(lift: List<&2, U32>, +f: O.Found, +op: O.Op, +ar: O.Arena, +red: U32, +in2: U32, +inv: U32) -> Maybe<&1, O.Found>:
  match lift:
    case Nil{}: None{}
    case _ <> _:
      +fl = sym_90.up(lift, f, op)
      +fr = sym_90.rep(ar, red, in2)
      # BUILT IN `fr`'S ARENA AND NOT `fl`'S: `rep` minted, so `Found.ar(fr)` is the one that
      Some{mint_where(fr, O.Found.i(fl), O.Found.i(fr), inv)}

# `match` MAY NOT SCRUTINISE A CALL, so the arg crosses as a parameter -- the same shape as
# `sy_ccast.dispatch` and `sym_87.pat` elsewhere in this file.
def sym_90.zero.of(a: O.Arg) -> Bool:
  match a:
    case O.AReduce{rop, n}: U32.is_zero(n)
    case _               : False{}

def sym_90.zero(+x: F.Folded, +u: U32) -> Bool:
  sym_90.zero.of(sy_arg(x, u))

def sym_90.pat(+x: F.Folded, +u: U32) -> Bool:
  sy_pat_ge(x, u, O.OpsREDUCE{}, 1, sym_90.zero(x, u))

def sym_90.go(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case False{}: None{}
    case True{} :
      +ar = sy_ar(x)
      +rt = F.Ranged.rt(F.ranged(ar))
      # the gate is `red.src[0]`, and `cond`/`x`/`i` are its three srcs -- not the reduce's.
      # MEASURED: reading them off the REDUCE made `x` the reduce's RANGE and the answer
      +gate = sy_src0(x, u)
      +cond = sy_src0(x, gate)
      +xa   = sy_src1(x, gate)
      +inv  = sy_src2(x, gate)
      +ks = sym_90.part(O.UOp.split_uop(O.Arena.budget(ar), ar, cond, O.OpsAND{}),
                        O.Arena.src_from(ar, u, 1), ar, rt, KS{Nil{}, Nil{}})
      +in2 = sym_90.inner(KS.keep(ks), O.Found{ar, u}, O.OpsMUL{}, ar, xa, inv)
      sym_90.out(KS.lift(ks), O.Found{ar, u}, O.OpsMUL{}, ar, u, in2, inv)

def sym_90(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_90.go(sym_90.pat(x, u), x, u)

# the tags with a minting body. a list and not a predicate, because the dispatch below is a
# `match` on the tag and the list is what says which tags it must have an arm for.
def MINT_TAGS() -> List<&2, U32>: [0,2,3,4,6,8,9,10,11,17,19,22,29,30,32,33,34,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,58,59,60,61,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,98,99,100,101,102,103,104,105,106,108,109,110,111,112,113,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130]

# `nested_div` -- divandmod.py:23. AND IT IS THE NEXT UNPORTED ARM OF

# and the CONST's value out of a `Maybe<&2, O.Const>` -- and the `None` case is zero,
# WHICH IS THE PORT's OWN CONVENTION (`divandmod.bend`'s `dm_ival`).
def dm_nd_val.of(m: Maybe<&2, O.Const>) -> Maybe<&2, U32>:
  match m:
    case Some{O.CInt{i}}: Some{H.lo32(i)}
    case _: None{}

def dm_nd_val.go(v: Maybe<&2, U32>) -> U32:
  match v:
    case Some{n}: n
    case None{}: 0

def dm_nd_val(+x: F.Folded, +u: U32) -> U32:
  dm_nd_val.go(dm_nd_val.of(sy_val(x, u)))

# and the CONST's value as an `H.I64` -- and the port's own `UOp.divides` takes an `H.I64`
# DIVISOR (`ops.bend:7893`).
def dm_nd_val64.go(v: Maybe<&2, U32>) -> H.I64:
  match v:
    case Some{n}: H.i64_of_i32(n)
    case None{}: H.i64_of_i32(0)

def dm_nd_val64(+x: F.Folded, +u: U32) -> H.I64:
  dm_nd_val64.go(dm_nd_val.of(sy_val(x, u)))

# and the `k.vmin > 0` guard -- and it is an I64 comparison (measured 2026-11-09: the
def dm_nd_positive.go(v: H.I64) -> Bool:
  Cmp.is_le(H.i64_cmp(H.i64_of_i32(0), v))

# and the MOD's divisor: the MOD node is `d.src[0]` and its own SRC 1 is the MOD's
# divisor -- measured 2026-11-09: `sy_src1(x, u)` is the DIV's divisor and not the MOD's.
def dm_nd.moddiv(+x: F.Folded, +u: U32) -> U32:
  sy_src1(x, sy_src0(x, u))

# and the `k`: `x.src[1].divides(c)` -- and the port's own `UOp.divides` answers a
# `Dv{ok, f, i}` whose `f` is the quotient's node -- and for a CONST divisor the quotient is
# A CONST NODE (MEASURED: `ops.bend`'s `dv.const2` MINTS `CONST(val // v)`).
def dm_nd_k.go(d: O.Dv, ok: Bool) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{O.Dv.f(d)}
    case False{}: None{}

def dm_nd_k(+x: F.Folded, +u: U32, c: H.I64) -> Maybe<&1, O.Found>:
  +d = O.UOp.divides(U32.to_nat(O.Arena.next(sy_ar(x))), sy_ar(x), c, dm_nd.moddiv(x, u))
  dm_nd_k.go(d, O.Dv.ok(d))

# and the `k`'s positiveness, read off the `k`'s own node -- and the value is an `H.I64`,
# because the sign matters (measured 2026-11-09: the `lo32` read lost it).
def dm_nd_val_of.go(arg: O.Arg) -> H.I64:
  match arg:
    case O.APy{O.CInt{i}}: i
    case _: H.i64_of_i32(0)

def dm_nd_val_of(+k: O.Found) -> H.I64:
  dm_nd_val_of.go(O.Arena.arg(O.Found.ar(k), O.Found.i(k)))

def dm_nd_k.pos.go(k: Maybe<&1, O.Found>) -> Bool:
  match k:
    case Some{kk}: dm_nd_positive.go(dm_nd_val_of(kk))
    case None{}: False{}

# and the dividend: `x.src[0]` WHERE `x` is the MOD node (measured 2026-11-09: the
# port's answer read `(mod (div (mod x c8) c4) c2)` and upstream's reads `(mod (div x 4) c2)`).
def dm_nd.dividend(+x: F.Folded, +u: U32) -> U32:
  sy_src0(x, sy_src0(x, u))

# and the answer: `x.src[0] // y % k` -- and it is the port's own `mint_bin` twice:
def dm_nd_answer(+x: F.Folded, +u: U32, +k: O.Found) -> O.Found:
  +q = mint_bin(mint_ar(O.Found.ar(k)), O.OpsDIV{}, dm_nd.dividend(x, u), sy_src1(x, u))
  mint_bin(q, O.OpsMOD{}, O.Found.i(q), O.Found.i(k))

# and the arm's guards: `d.op is Ops.DIV` and `x.op is Ops.MOD` -- and `x` is `d.src[0]`
# and `y` is `d.src[1]` -- and the port's own `sy_is_op` reads an op.
def dm_nd.pat.go(isdiv: Bool, ismod: Bool) -> Bool:
  Bool.and(isdiv, ismod)

def dm_nd.pat(+x: F.Folded, +u: U32) -> Bool:
  dm_nd.pat.go(sy_is_op(x, u, O.OpsDIV{}),
              sy_is_op(x, sy_src0(x, u), O.OpsMOD{}))

# and the constant denominator guard: `y.op is Ops.CONST and y.val > 0` -- and `c` is
# `y`'s value -- and the port's own `sy_is_const` and `dm_nd_val` answer both halves.
def dm_nd.cst.go(isconst: Bool, c: U32) -> Bool:
  Bool.and(isconst, U32.is_gt(c, 0))

def dm_nd.cst(+x: F.Folded, +u: U32, c: U32) -> Bool:
  dm_nd.cst.go(sy_is_const(x, sy_src1(x, u)), c)

def dm_nd.k2(+k: O.Found, positive: Bool) -> Maybe<&1, O.Found>:
  match positive:
    case True{}: Some{k}
    case False{}: None{}

def dm_nd.k.go(k: Maybe<&1, O.Found>, positive: Bool) -> Maybe<&1, O.Found>:
  match k:
    case Some{kk}: dm_nd.k2(kk, positive)
    case None{}: None{}

def dm_nd.k(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_nd.k.go(dm_nd_k(x, u, dm_nd_val64(x, sy_src1(x, u))),
             dm_nd_k.pos.go(dm_nd_k(x, u, dm_nd_val64(x, sy_src1(x, u)))))

def dm_nd.mk2(+x: F.Folded, +u: U32, k: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match k:
    case Some{kk}: Some{dm_nd_answer(x, u, kk)}
    case None{}: None{}

def dm_nd.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_nd.mk2(x, u, dm_nd.k(x, u))

# and the rule -- and the constant denominator guard is the port's own
# `dm_103b`-shaped pattern -- and the arm's answer is the `Maybe` of a `Found`.
def dm_nd.pat2(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(dm_nd.pat(x, u),
           dm_nd.cst(x, u, dm_nd_val(x, sy_src1(x, u))))

def dm_nd(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(dm_nd.pat2(x, u), dm_nd.mk(x, u))

# and the arm's answer without the matcher's dispatch, so a row can ask the arm directly --
def dm_nd.ans(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_nd.mk(x, u)

# THE TABLE IS IN `.agents/slop/tables/uop-symbolic-7069.md` -- (THIS WAS A STACK OF 12 IDENTICAL SEPARATOR LINES -- MEASURED 2026-11-10 -- AND ONE

# and the CONST's value is 4 (the divisor) and 2 (the `k`) -- and every value is
def t_nd.isconst4.go(isconst: Bool, arg: O.Arg) -> Bool:
  match arg:
    case O.APy{O.CInt{i}}: Bool.and(isconst, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(4))))
    case _: False{}

def t_nd.isconst4(+ar: O.Arena, +i: U32) -> Bool:
  t_nd.isconst4.go(O.eq_op(O.Arena.op(ar, i), O.OpsCONST{}), O.Arena.arg(ar, i))

def t_nd.isconst2.go(isconst: Bool, arg: O.Arg) -> Bool:
  match arg:
    case O.APy{O.CInt{i}}: Bool.and(isconst, Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(2))))
    case _: False{}

def t_nd.isconst2(+ar: O.Arena, +i: U32) -> Bool:
  t_nd.isconst2.go(O.eq_op(O.Arena.op(ar, i), O.OpsCONST{}), O.Arena.arg(ar, i))

# and the answer's node is read once -- and its op and its srcs come off it
# (`ops.bend:1402`: `Arena.node(ar, i)` IS THE PORT's OWN SINGLE READ).
def t_nd.shape8(+f: O.Found, +ans: O.Node, a1: U32, d0: U32, d1: U32) -> Bool:
  +ar = O.Found.ar(f)
  Bool.and(Bool.and(O.eq_op(O.Node.op(ans), O.OpsMOD{}),
                    O.eq_op(O.Arena.op(ar, d0), O.OpsPARAM{})),
           Bool.and(t_nd.isconst4(ar, d1), t_nd.isconst2(ar, a1)))

def t_nd.shape7(+f: O.Found, +ans: O.Node, a1: U32, d0: U32, d1: U32) -> Bool:
  t_nd.shape8(f, ans, a1, d0, d1)

def t_nd.shape6(+f: O.Found, +ans: O.Node, a1: U32, +div: O.Node, div_srcs: List<&2, U32>) -> Bool:
  match div_srcs:
    case d0 <> d1 <> _:
      t_nd.shape7(f, ans, a1, d0, d1)
    case _: False{}

def t_nd.shape5(+f: O.Found, +ans: O.Node, ans_srcs: List<&2, U32>) -> Bool:
  match ans_srcs:
    case a0 <> a1 <> _:
      +div = O.Arena.node(O.Found.ar(f), a0)
      t_nd.shape6(f, ans, a1, div, O.Node.src(div))
    case _: False{}

def t_nd.shape.go2(+f: O.Found) -> Bool:
  match f:
    case O.Found{ar, i}:
      +nd = O.Arena.node(ar, i)
      t_nd.shape5(f, nd, O.Node.src(nd))

def t_nd.shape(+f: O.Found) -> Bool:
  t_nd.shape.go2(f)

def t_nd.shape.go(m: Maybe<&1, O.Found>) -> Bool:
  match m:
    case Some{f}: t_nd.shape.go2(f)
    case None{}: False{}

# and "did the arm fire" -- and `Maybe` has no `is_some` in the prelude (measured 2026-11-09:
def t_nd.some(m: Maybe<&1, O.Found>) -> Bool:
  match m:
    case Some{f}: True{}
    case None{}: False{}

def t_nd.graph(+k: H.I64, +c: H.I64) -> O.Found:
  +ar0 = O.Arena.empty()
  +fx = O.UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(20), 1, S.weakint())
  +ar1 = O.Found.ar(fx)
  +ck = O.UOp.const(ar1, O.CInt{k})
  +ar2 = O.Found.ar(ck)
  +cc = O.UOp.const(ar2, O.CInt{c})
  +ar3 = O.Found.ar(cc)
  +m = O.UOp.alu(ar3, O.OpsMOD{}, [O.Found.i(fx), O.Found.i(ck)])
  +ar4 = O.Found.ar(m)
  O.UOp.alu(ar4, O.OpsDIV{}, [O.Found.i(m), O.Found.i(cc)])

# and the `(x % 8) // 4` rewrite: a MOD of a DIV of `x` by the CONST `4`, modulo the CONST
# `2` -- AND THE `2` IS THE `k`, WHICH IS `8 // 4`.
def t_nd_rewrite() -> Bool:
  +f = t_nd.graph(H.i64_of_i32(8), H.i64_of_i32(4))
  +x = F.folded(O.Found.ar(f))
  +u = O.Found.i(f)
  t_nd.shape.go(dm_nd.ans(x, u))

# and the negative guard: `(x % -4) // 4` is not rewritten -- and the `k` is -1
# AND `k.vmin > 0` FAILS.
def t_nd_neg() -> Bool:
  +f = t_nd.graph(H.i64_neg(True{}, H.i64_of_i32(4)), H.i64_of_i32(4))
  +x = F.folded(O.Found.ar(f))
  +u = O.Found.i(f)
  Bool.not(t_nd.some(dm_nd.ans(x, u)))

# and the no-divide guard: `(x % 2) // 4` is not rewritten -- and `2` does not
# DIVIDE `4`.
def t_nd_nodiv() -> Bool:
  +f = t_nd.graph(H.i64_of_i32(2), H.i64_of_i32(4))
  +x = F.folded(O.Found.ar(f))
  +u = O.Found.i(f)
  Bool.not(t_nd.some(dm_nd.ans(x, u)))

# `divandmod.py:103` -- THE SLOW RULE, `(UPat((Ops.DIV, Ops.MOD), dtypes.weakint,

# and "is this node the CONST 1" over an arena and an INDEX -- and the port's own
def p_is_const_1_of.arg(arg: O.Arg) -> Bool:
  match arg:
    case O.APy{O.CInt{i}}: Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(1)))
    case _: False{}

def p_is_const_1_of.go(isconst: Bool, arg: O.Arg) -> Bool:
  match isconst:
    case True{}: p_is_const_1_of.arg(arg)
    case False{}: False{}

def p_is_const_1_of(+ar: O.Arena, +u: U32) -> Bool:
  p_is_const_1_of.go(O.eq_op(O.Arena.op(ar, u), O.OpsCONST{}), O.Arena.arg(ar, u))

# and the MUL by the identity FOLD -- and it is the `simplify` of the `gcd` -- and it
def dm_gcd_fold.pick3(+ar: O.Arena, +u: U32, r: Bool) -> U32:
  match r:
    case True{}: O.Arena.src(ar, u, 0)
    case False{}: u

def dm_gcd_fold.pick2(+ar: O.Arena, +u: U32, l: Bool, r: Bool) -> U32:
  match l:
    case True{}: O.Arena.src(ar, u, 1)
    case False{}: dm_gcd_fold.pick3(ar, u, r)

# and the FOLD's pick: the CONST 1 at `src[0]` leaves `src[1]` and vice versa -- and MUL is
# commutative -- and the CONST's value is read by the port's own `p_is_const_1_of`.
def dm_gcd_fold.pick(+ar: O.Arena, +u: U32, l: Bool, r: Bool) -> U32:
  dm_gcd_fold.pick2(ar, u, l, r)

# and the FOLD: a MUL with two srcs and a CONST 1 at either one folds to the other,
# AND EVERYTHING ELSE IS ITSELF.
def dm_gcd_fold.two(+ar: O.Arena, +u: U32, two: Bool, l: Bool, r: Bool) -> U32:
  match two:
    case True{}: dm_gcd_fold.pick(ar, u, l, r)
    case False{}: u

def dm_gcd_fold.go(+ar: O.Arena, +u: U32, ismul: Bool, two: Bool, l: Bool, r: Bool) -> U32:
  match ismul:
    case True{}: dm_gcd_fold.two(ar, u, two, l, r)
    case False{}: u

def dm_gcd_fold(+ar: O.Arena, +u: U32) -> U32:
  dm_gcd_fold.go(ar, u, O.eq_op(O.Arena.op(ar, u), O.OpsMUL{}),
                 U32.is_eq(O.Arena.nsrc(ar, u), 2),
                 p_is_const_1_of(ar, O.Arena.src(ar, u, 0)),
                 p_is_const_1_of(ar, O.Arena.src(ar, u, 1)))

# and the `all_uops`: `list(x.split_uop(Ops.ADD))` plus the denominator -- and
def dm_gcd_uops.go(+l: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match l:
    case Nil{}: acc
    case h <> t: dm_gcd_uops.go(t, List.append(&2, U32, acc, [h]))

def dm_gcd_uops(+ar: O.Arena, +num: U32, +den: U32) -> List<&2, U32>:
  dm_gcd_uops.go(sy_split(ar, num, O.OpsADD{}), List.append(&2, U32, Nil{}, [den]))

# and the `gcd`: `UOp.gcd(*all_uops, y).simplify()` -- and the port's `UOp.gcd` answers
# A `Found` AND THE `simplify` IS THE FOLD ABOVE.
def dm_gcd(+ar: O.Arena, +num: U32, +den: U32) -> U32:
  +g = O.UOp.gcd(ar, dm_gcd_uops(ar, num, den))
  dm_gcd_fold(O.Found.ar(g), O.Found.i(g))

# AND THE GUARD: `not (gcd.op is Ops.CONST and gcd.val==1)` -- AND A `gcd` OF 1 MEANS
def dm_gcd_is_one(+ar: O.Arena, +g: U32) -> Bool:
  p_is_const_1_of(ar, g)

# AND THE TWO `divide_exact` ANSWERS: `x.divide_exact(gcd)` AND
def dm_gcd_quo.go(d: O.Dq, ok: Bool) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: Some{O.Dq.f(d)}
    case False{}: None{}

def dm_gcd_quo(+ar: O.Arena, +num: U32, +g: U32) -> Maybe<&1, O.Found>:
  +d = O.UOp.divide_exact(ar, num, g)
  dm_gcd_quo.go(d, O.Dq.ok(d))

# AND THE `ret`: `x.divide_exact(gcd).alu(d.op, y.divide_exact(gcd))` -- AND `alu`
# puts `self` at `src[0]`, so the numerator's quotient is first -- and the `Found`s are
# destructured in the match, because a pattern binder is consumed once and two reads of it
# ARE TWO CONSUMPTIONS (MEASURED 2026-11-09: "expected : fa / observed : fa (consumed more than
def dm_gcd_ret.put(+ar: O.Arena, ai: U32, b: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match b:
    case Some{fb}: Some{O.UOp.alu(ar, O.OpsDIV{}, [ai, O.Found.i(fb)])}
    case None{}: None{}

def dm_gcd_ret.go2(f: O.Found, b: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match f:
    case O.Found{ar, i}: dm_gcd_ret.put(ar, i, b)

def dm_gcd_ret.go(a: Maybe<&1, O.Found>, b: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match a:
    case Some{f}: dm_gcd_ret.go2(f, b)
    case None{}: None{}

def dm_gcd_ret(+ar: O.Arena, +num: U32, +den: U32, +g: U32) -> Maybe<&1, O.Found>:
  dm_gcd_ret.go(dm_gcd_quo(ar, num, g), dm_gcd_quo(ar, den, g))

# and the arm: the guard and the answer -- and the `gcd` is computed once and passed
# ON.
def dm_gcd_arm.go(+ar: O.Arena, +d: U32, +g: U32, isone: Bool) -> Maybe<&1, O.Found>:
  match isone:
    case True{}: None{}
    case False{}: dm_gcd_ret(ar, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1), g)

def dm_gcd_arm(+ar: O.Arena, +d: U32) -> Maybe<&1, O.Found>:
  +g = dm_gcd(ar, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1))
  dm_gcd_arm.go(ar, d, g, dm_gcd_is_one(ar, g))

# and the rule: the slow rule -- and its pattern is any DIV or MOD node, and the
def dm_103b.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.or(sy_is_op(x, u, O.OpsDIV{}), sy_is_op(x, u, O.OpsMOD{})),
           Bool.and(sy_nsrc_is(x, u, 2), p_weakint(x, u)))

# and the two arms are first-wins -- and the `nested_div` arm is first because
# upstream's constant-denominator rules precede the variable-denominator fallback
# (`divandmod.py:19-21` and `:72-96`) -- and the port's own convention is a leaf over two
def dm_103b.mk.go(a: Maybe<&1, O.Found>, b: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match a:
    case Some{f}: Some{f}
    case None{}: b

def dm_103b.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_103b.mk.go(dm_nd(x, u), dm_gcd_arm(sy_ar(x), u))

def dm_103b(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(dm_103b.pat(x, u), dm_103b.mk(x, u))

def sym_mint_f(+tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match tag:
    case 0: sym_82(x, u)
    case 2: sym_84(x, u)
    case 3: sym_87(x, u)
    case 4: sym_88(x, u)
    case 6: sym_90(x, u)
    case 8: sym_93(x, u)
    case 9: sym_95(x, u)
    case 10: sym_97(x, u)
    case 11: sym_99(x, u)
    case 17: sym_123(x, u)
    case 19: sym_125(x, u)
    case 22: sym_129(x, u)
    case 29: sym_136(x, u)
    case 30: sym_144c(x, u)
    case 32: sym_142(x, u)
    case 33: sym_143(x, u)
    case 34: sym_144(x, u)
    case 36: sym_147(x, u)
    case 37: sym_151(x, u)
    case 38: sym_155(x, u)
    case 39: sym_157(x, u)
    case 40: sym_161(x, u)
    case 41: sym_162(x, u)
    case 42: sym_163(x, u)
    case 50: sym_168(x, u)
    case 51: sym_169(x, u)
    case 49: sym_171(x, u)
    case 52: sym_173(x, u)
    case 58: sym_188(x, u)
    case 59: sym_189(x, u)
    case 60: sym_191(x, u)
    case 61: sym_193(x, u)
    case 65: sy_fcw_f(x, u)
    case 66: mv_7(x, u)
    case 67: mv_10(x, u)
    case 68: mv_12(x, u)
    case 69: mv_14(x, u)
    case 70: mv_18(x, u)
    case 71: mv_21(x, u)
    case 72: mv_24(x, u)
    case 73: mv_27(x, u)
    case 74: sym_230(x, u)
    case 75: sym_243(x, u)
    case 76: sym_245(x, u)
    case 77: sym_246(x, u)
    case 78: sym_247(x, u)
    case 79: sym_248(x, u)
    case 80: sym_249(x, u)
    case 81: sym_250(x, u)
    case 82: sym_251(x, u)
    case 83: sym_254(x, u)
    case 84: sym_256(x, u)
    case 85: sym_259(x, u)
    case 86: sym_271(x, u)
    case 87: sym_273(x, u)
    case 88: sym_262(x, u)
    case 89: sym_264(x, u)
    case 90: sym_266(x, u)
    case 91: sym_269(x, u)
    case 92: sym_272(x, u)
    case 93: sym_274(x, u)
    case 94: sym_276(x, u)
    case 95: sym_278(x, u)
    case 96: sym_279(x, u)
    case 43: sym_284(x, u)
    case 44: sym_284(x, u)
    case 45: sym_284(x, u)
    case 46: sym_284(x, u)
    case 47: sym_284(x, u)
    case 48: sym_284(x, u)
    case 98: sym_287(x, u)
    case 99: sym_290(x, u)
    case 100: sym_292(x, u)
    case 101: sym_295(x, u)
    case 102: sym_296(x, u)
    case 103: sym_299(x, u)
    case 104: sym_300(x, u)
    case 105: sym_316c(x, u)
    case 106: sym_302(x, u)
    case 108: sym_305(x, u)
    case 109: sym_308(x, u)
    case 110: sym_309(x, u)
    case 111: sym_312(x, u)
    case 112: sym_316(x, u)
    case 113: sym_318(x, u)
    case 115: dm_101(x, u)
    case 116: dm_103(x, u)
    case 117: dm_103b(x, u)
    case 118: wk_89(x, u)
    case 119: sym_451(x, u)
    case 120: sym_453(x, u)
    case 130: sym_471x(x, u)
    case 121: sym_454(x, u)
    case 122: sym_458(x, u)
    case 123: sym_460(x, u)    case 124: sym_465(x, u)
    case 125: sym_466(x, u)
    case 126: sym_467(x, u)
    case 127: sym_469(x, u)    case 128: sym_473(x, u)
    case 129: sym_444(x, u)
    case _ : None{}

def sym_dispatch_f.pick(mint: Bool, +tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match mint:
    case True{} : sym_mint_f(tag, x, u)
    case False{}: sy_lift(sym_dispatch(tag, x, u), sy_ar(x))

def sym_dispatch_f(+tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_dispatch_f.pick(List.contains(U32, U32.is_eq, MINT_TAGS(), tag), tag, x, u)

# The `ret is not uop` test, `ops.py:1605`, on the FOUND's index.
def sy_novel_f.hit(same: Bool, +f: O.Found) -> Maybe<&1, O.Found>:
  match same:
    case True{}: None{}
    case _     : Some{f}

def sy_novel_f(+self: U32, m: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match m:
    case Some{+f}: sy_novel_f.hit(U32.is_eq(O.Found.i(f), self), f)
    case None{} : None{}

def sy_keep_f.go(acc: Maybe<&1, O.Found>, v: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match acc:
    case Some{f}: Some{f}
    case _      : v

def sym_try_f.pick(ok: Bool, +tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: sy_novel_f(u, sym_dispatch_f(tag, x, u))
    case _     : None{}

def sym_try_f(ts: O.PMEntrys, +x: F.Folded, +u: U32, +e: O.PMEntry) -> Maybe<&1, O.Found>:
  sym_try_f.pick(Bool.and(O.op_in(O.PMEntry.ops(e), O.Arena.op(sy_ar(x), u)),
                          O.pm_early(ts, sy_ar(x), u, O.PMEntry.rej(e))),
                 O.PMEntry.tag(e), x, u)

def sym_scan_f(+ts: O.PMEntrys, +x: F.Folded, +u: U32, todo: List<&2, O.PMEntry>, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match todo:
    case Nil{}  : acc
    case e <> t : sym_scan_f(ts, x, u, t, sy_keep_f.go(acc, sym_try_f(ts, x, u, e)))

def sym_rewrite_f(+ts: O.PMEntrys, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_scan_f(ts, x, u, O.PMEntrys.es(ts), None{})

def sym_f(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_rewrite_f(sym_table(), x, u)

# `pm_remove_invalid` -- symbolic.py:104-108, and BOTH rules are ported.
def rm_108.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_invalid(x, sy_src2(x, u)))

# `Maybe` is a `Type`, so it is read ONCE: the two facts `w.const_like(0)` needs --
# is there one, and what is it -- cross the boundary as a `Bool` and a `U32`.
def rm_108.ok(hit: Bool, ok: Bool, +x: F.Folded, +u: U32, z: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, Bool.and(hit, ok),
    Some{sy_replace_src(sy_ar(x), u, [sy_src0(x, u), sy_src1(x, u), z])}, None{})

def rm_108.of(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match z:
    case Some{v}: rm_108.ok(hit, True{}, x, u, v)
    case _: rm_108.ok(hit, False{}, x, u, 0)

def rm_108.put(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_108.of(hit, z, x, u)

def rm_108(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_108.put(rm_108.pat(x, u), sy_const_like(x, u, O.CInt{H.i64_of_i32(0)}), x, u)

# symbolic.py:106-107  (UPat(Ops.STACK, name="s"),
def any_invalid.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_invalid.go(t, x, Bool.or(acc, p_invalid(x, s)))

def rm_109.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTACK{}), sy_nsrc_ge(x, u, 1)), any_invalid.go(sy_srcs(x, u), x, False{}))

def rm_109.of(+x: F.Folded, +s: U32, dt: S.Dt, +ar: O.Arena) -> U32:
  Bool.pick(U32, p_invalid(x, s), sp_const(dt, H.i64_of_i32(0), ar), s)

def rm_109.go(srcs: List<&2, U32>, +x: F.Folded, +dt: S.Dt, +ar: O.Arena) -> List<&2, U32>:
  match srcs:
    case Nil{}: Nil{}
    case s <> t: List.append(&2, U32, rm_109.go(t, x, dt, ar), [rm_109.of(x, s, dt, ar)])

def rm_109.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_replace_src(sy_ar(x), u, rm_109.go(sy_srcs(x, u), x, sy_dt1(x, u), sy_ar(x)))})

def rm_109(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: rm_109.hit(rm_109.pat(x, u), x, u)

# THE SECOND DRIVER. `pm_remove_invalid` is a separate matcher in Python, so it is a
# separate table with its own tag space and its own dispatch -- the honest cost of
# not having first-class functions. Sharing `sym`'s driver would be a BUG rather
# than a saving: it would let `symbolic.py:91` claim the node and make
def rm_dispatch.go(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match tag:
    case 0: rm_108(x, u)
    case 1: rm_109(x, u)
    case _: None{}

def rm_dispatch(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_dispatch.go(tag, x, u)

def rm_try.pick(ok: Bool, tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: sy_novel(u, rm_dispatch(tag, x, u))
    case _: None{}

def rm_try(ts: O.PMEntrys, +x: F.Folded, +u: U32, +e: O.PMEntry) -> Maybe<&1, U32>:
  rm_try.pick(Bool.and(O.op_in(O.PMEntry.ops(e), O.Arena.op(sy_ar(x), u)),
                        O.pm_early(ts, sy_ar(x), u, O.PMEntry.rej(e))),
              O.PMEntry.tag(e), x, u)

def rm_scan(+ts: O.PMEntrys, +x: F.Folded, +u: U32, todo: List<&2, O.PMEntry>, acc: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match todo:
    case Nil{}: acc
    case e <> t: rm_scan(ts, x, u, t, sy_keep.go(acc, rm_try(ts, x, u, e)))

def rm_rewrite(+ts: O.PMEntrys, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_scan(ts, x, u, O.PMEntrys.es(ts), None{})

def pm_remove_invalid(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_rewrite(rm_table(), x, u)
# THE FIXTURES, and the ONE thing that had to be got right: EVERY construction
def f_new(+ar: O.Arena, op: O.Op, srcs: List<&2, U32>, a: O.Arg) -> O.Found:
  O.UOp.new(ar, op, srcs, a, O.TNone{})

def f_cast(+f: O.Found, dt: S.Dt) -> O.Found:
  f_new(O.Found.ar(f), O.OpsCAST{}, [O.Found.i(f)], O.ADt{dt})

def f_alu2(+f: O.Found, op: O.Op, b: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [O.Found.i(f), b])

def f_i(f: O.Found) -> U32: O.Found.i(f)

# THE FIXTURE's CONST, ONCE. MEASURED 2026-11-10: 28 FIXTURE LINES READ
def f_c(v: H.I64) -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{v})

def f_where(+ar: O.Arena, a: U32, b: U32, c: U32) -> O.Found:
  O.UOp.new(ar, O.OpsWHERE{}, [a, b, c], O.ANone{}, O.TNone{})

# `x + 0` with `x = CONST(7)`: 0 is `CONST(7)`, 1 is `CONST(0)`, 2 is the ADD.
def fx_add0() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  f_alu2(b, O.OpsADD{}, f_i(a))

# `x // x` with `x = CONST(7)`: 0 is `CONST(7)`, 1 is the DIV. The two srcs
# are the SAME node, which is the rebind the rule checks for.
def fx_samediv() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  f_alu2(a, O.OpsDIV{}, f_i(a))

# `x // y` for TWO DIFFERENT consts: 0 is `CONST(7)`, 1 is `CONST(2)`, 2 is the
# DIV. The SAME rule, and it must NOT fire.
def fx_diffdiv() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  f_alu2(b, O.OpsDIV{}, f_i(a))

# `CAST(bool, CONST(Invalid))`: 0 is the Invalid CONST, 1 is the CAST.
def fx_castbad() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInvalid{})
  f_cast(a, S.boolean())

# `CAST(bool, WHERE(c, x, CONST(Invalid)))`: 0 is `CONST(True)`, 1 is
# `CONST(7)`, 2 is the Invalid CONST, 3 is the WHERE, 4 is the CAST.
def fx_gatecast() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = O.UOp.const(O.Found.ar(b), O.CInvalid{})
  f_cast(f_where(O.Found.ar(c), f_i(a), f_i(b), f_i(c)), S.boolean())

# `WHERE(cond, x, CONST(Invalid))`, the node `sym`'s tag 2 AND `pm_remove_invalid`'s
def fx_where() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = O.UOp.const(O.Found.ar(b), O.CInvalid{})
  f_where(O.Found.ar(c), f_i(a), f_i(b), f_i(c))

# `STORE(INDEX(b, CONST(Invalid)), v)`: 0 is `CONST(2)`, 1 is the Invalid CONST,
# 2 is the INDEX, 3 is `CONST(9)`, 4 is the STORE, and tag 4 answers a NOOP at 5.
def fx_store() -> O.Found:
  +a = f_c(H.i64_of_i32(2))
  +b = O.UOp.const(O.Found.ar(a), O.CInvalid{})
  +c = f_alu2(b, O.OpsINDEX{}, f_i(a))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(9)})
  f_alu2(d, O.OpsSTORE{}, f_i(c))

# `ADD(CONST(5), CONST(6))`: 0 and 1 are the CONSTs and 2 is the ADD, so
# `fold_const_alu` has a CLOSED tree to evaluate -- which is the whole of
# `symbolic.py:158`'s claim.
def fx_alu() -> O.Found:
  +a = f_c(H.i64_of_i32(5))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(6)})
  f_alu2(b, O.OpsADD{}, f_i(a))

# `STACK(CONST(7), CONST(Invalid))`: 0 is `CONST(7)`, 1 is the Invalid CONST, 2 is
def fx_stack() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInvalid{})
  f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})

# `GROUP(CONST(7))`: 0 is `CONST(7)`, 1 is the GROUP, and tag 11 answers 0.
def fx_sink() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(3)})
  f_new(O.Found.ar(d), O.OpsSINK{}, [f_i(c), f_i(d)], O.ANone{})

# `SINK(AFTER(a), b)` -- THE SHAPE `fx_sink` IS NOT, and the fixture that makes
def fx_sinkgrp() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = f_new(O.Found.ar(b), O.OpsSINK{}, [f_i(a), f_i(b)], O.ANone{})
  +d = f_new(O.Found.ar(c), O.OpsAFTER{}, [f_i(a)], O.ANone{})
  f_new(O.Found.ar(d), O.OpsSINK{}, [f_i(d), f_i(b)], O.ANone{})

# THE NEGATIVE SIDE, and it is a real row rather than a compliment to the positive
def fx_sinkgrp0() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  f_new(O.Found.ar(b), O.OpsSINK{}, [f_i(a), f_i(b)], O.ANone{})

# `ADD(CONST(1), CONST(2**31))` at int32: the top ADD WRAPS to -2147483647.
def fx_i32() -> O.Found:
  +a = f_c(H.i64_of_i32(1))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_hi_lo(1, 0)})
  +c = f_alu2(b, O.OpsADD{}, f_i(a))
  f_cast(c, S.int32())

# THE TABLE IS IN `.agents/slop/tables/uop-symbolic-7750.md` -- ---- THE FIXTURES FOR TAGS 13..22, one per rule and a NEGATIVE one per rule whose
def f_bin(+ar: O.Arena, op: O.Op, a: U32, b: U32) -> O.Found:
  O.UOp.alu(ar, op, [a, b])

# `MOD(MOD(x, y), y)` over the SAME `y`: 1 is `CONST(7)`, 2 is `CONST(3)`,
def fx_mod() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(3)})
  +c = f_bin(O.Found.ar(b), O.OpsMOD{}, f_i(a), f_i(b))
  f_bin(O.Found.ar(c), O.OpsMOD{}, f_i(c), f_i(b))

# THE NEGATIVE, and it is the ONLY witness for the rebind check: 1, 2 and 3 are
def fx_mod2() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(3)})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(5)})
  +d = f_bin(O.Found.ar(c), O.OpsMOD{}, f_i(a), f_i(b))
  f_bin(O.Found.ar(d), O.OpsMOD{}, f_i(d), f_i(c))

# `CMPNE(CAST(x, weakint), CONST(c))` with `x` a BOOL-dtype node that is NOT a
# CONST -- `AND(CONST(True), CONST(False))` -- so the THREE arms of symbolic.py:136
def fx_ne.of(+ar: O.Arena, c: H.I64) -> O.Found:
  +a = O.UOp.const(ar, O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CBool{False{}})
  +d = O.UOp.new(O.Found.ar(b), O.OpsAND{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})
  +e = f_cast(d, S.weakint())
  +f = O.UOp.const(O.Found.ar(e), O.CInt{c})
  f_bin(O.Found.ar(f), O.OpsCMPNE{}, f_i(e), f_i(f))

def fx_ne0() -> O.Found: fx_ne.of(O.Arena.empty(), H.i64_of_i32(0))

def fx_ne1() -> O.Found: fx_ne.of(O.Arena.empty(), H.i64_of_i32(1))

def fx_ne2() -> O.Found: fx_ne.of(O.Arena.empty(), H.i64_of_i32(2))

# THE PERMUTED SIDE, and it is the row for the `Sw`: the CONST is at src[0] and the
def fx_ne0r() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CBool{False{}})
  +d = O.UOp.new(O.Found.ar(b), O.OpsAND{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})
  +e = f_cast(d, S.weakint())
  +f = O.UOp.const(O.Found.ar(e), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(f), O.OpsCMPNE{}, f_i(f), f_i(e))

# `TRUNC(CAST(CONST(7), int32))`: 1 is the CONST, 2 the CAST and 3 the TRUNC, and
def fx_trunc() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = f_cast(a, S.int32())
  f_new(O.Found.ar(b), O.OpsTRUNC{}, [f_i(b)], O.ANone{})

# THE NEGATIVE, and the dtype set is the whole claim: the same TRUNC over a
# `weakfloat` CONST, which is NOT in `dtypes.ints + (bool, weakint)`.
def fx_truncf() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CFloat{2.75})
  f_new(O.Found.ar(a), O.OpsTRUNC{}, [f_i(a)], O.ANone{})

# `(x & mask) >> k` with `k = 4` and `mask = -16`, so `mask | ((1 << 4) - 1)` is
def fx_shr() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(4)})
  f_bin(O.Found.ar(d), O.OpsSHR{}, f_i(c), f_i(d))

# THE NEGATIVE, and it is the GUARD: the same shape with `mask = 0`, so
# `0 | 15` is `15` and not `-1`.
def fx_shr0() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(4)})
  f_bin(O.Found.ar(d), O.OpsSHR{}, f_i(c), f_i(d))

# `(x & mask) // c` with `c = 16`, which is a power of two, and `mask = -16`. The
# same node shape as `fx_shr`, so the two rules are one fixture read twice.
def fx_fdivm() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(16)})
  f_bin(O.Found.ar(d), O.OpsDIV{}, f_i(c), f_i(d))

# THE NEGATIVE, and it is the POWER-OF-TWO half: `c = 15` is not one, so the rule
# must not fire even though `mask | (c-1)` is still `-1`.
def fx_fdivm0() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(15)})
  f_bin(O.Found.ar(d), O.OpsDIV{}, f_i(c), f_i(d))

# THE PROMOTION, and it is a TWO-SRC fold over `[casted_const, bare_const]`: 1 is
def fx_prom() -> O.Found:
  +a = f_c(H.i64_of_i32(3))
  +b = f_cast(a, S.int32())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(b), f_i(c))

# THE NEGATIVE, and it is the MEET: the same shape with the cast at `weakint`, so
def fx_prom0() -> O.Found:
  +a = f_c(H.i64_of_i32(3))
  +b = f_cast(a, S.weakint())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(b), f_i(c))

# the threefry unpack, low half: `CAST(SHL(z, 32) | CAST(y, uint64), uint32)` with
def fx_tflo() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = f_cast(a, S.uint32())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(9)})
  +d = f_cast(c, S.uint64())
  +e = O.UOp.const(O.Found.ar(d), O.CInt{H.i64_of_i32(32)})
  +f = f_bin(O.Found.ar(e), O.OpsSHL{}, f_i(d), f_i(e))
  +g = O.UOp.new(O.Found.ar(f), O.OpsCAST{}, [f_i(b)], O.ADt{S.uint64()}, O.TNone{})
  +h = f_bin(O.Found.ar(g), O.OpsOR{}, f_i(f), f_i(g))
  f_cast(h, S.uint32())

# the threefry unpack, high half: `shr(shl(CAST(x, uint64), 32) | CAST(z, uint64),
def fx_tfhi() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = f_cast(a, S.uint32())
  +c = f_cast(b, S.uint64())
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(32)})
  +e = f_bin(O.Found.ar(d), O.OpsSHL{}, f_i(c), f_i(d))
  +f = O.UOp.const(O.Found.ar(e), O.CInt{H.i64_of_i32(9)})
  +g = f_cast(f, S.uint32())
  +h = f_cast(g, S.uint64())
  +i = f_bin(O.Found.ar(h), O.OpsOR{}, f_i(e), f_i(h))
  f_bin(O.Found.ar(i), O.OpsSHR{}, f_i(i), f_i(d))

# `1/(x*x*x)`: 1 is `CONST(7)`, 2 is `MUL(1,1)`, 3 is `MUL(2,1)` and 4 the
def fx_recip3() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = f_bin(O.Found.ar(a), O.OpsMUL{}, f_i(a), f_i(a))
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(b), f_i(a))
  f_new(O.Found.ar(c), O.OpsRECIP{}, [f_i(c)], O.ANone{})

# THE NEGATIVE, and it is the SIBLING identity check: the inner MUL's two srcs are
def fx_recip3x() -> O.Found:
  +a = f_c(H.i64_of_i32(7))
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(a), f_i(a))
  +d = f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(c), f_i(b))
  f_new(O.Found.ar(d), O.OpsRECIP{}, [f_i(d)], O.ANone{})

# `1/(x*c)` with a NON-CONST `x`, so the rule's own two names are distinguishable:
def fx_recipc() -> O.Found:
  +a = f_c(H.i64_of_i32(9))
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(b), f_i(a))
  f_new(O.Found.ar(c), O.OpsRECIP{}, [f_i(c)], O.ANone{})

# THE SAME, WITH THE CONST AT src[0] -- the SECOND permutation, and the row that
def fx_recipc0() -> O.Found:
  +a = f_c(H.i64_of_i32(9))
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(a), f_i(b))
  f_new(O.Found.ar(c), O.OpsRECIP{}, [f_i(c)], O.ANone{})

def fx_of(f: O.Found) -> F.Folded: F.folded(O.Found.ar(f))
# THE GATE. `main` builds the fixtures above, folds each with `fold.bend`, runs the table
def eq_u(m: Maybe<&1, U32>, want: U32) -> Bool:
  match m:
    case Some{i}: U32.is_eq(i, want)
    case _: False{}

def i32_is(m: Maybe<&1, O.Const>, want: H.I64) -> Bool: Cmp.is_eq(H.i64_cmp(sy_cint(m), want))

def f32_of(m: Maybe<&1, O.Const>) -> F32:
  match m:
    case Some{O.CFloat{f}}: f
    case _: 0.0

def f32_is(m: Maybe<&1, O.Const>, want: F32) -> Bool: F32.is_eq(f32_of(m), want)

# THE COUNT ROWS. `len_sym`, `len_rm` and `rej` are COUNTS and not booleans,
def t_len_sym() -> U32:
  U32.add(U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(sym_table()))),
          U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(valid_table()))))

def t_len_rm() -> U32: U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(rm_table())))

# the upstream total, and it moved because `tinygrad/` was re-vendored.  The old
# MEASURED 2026-11-04 against `gates/symrules-census.py`'s AST walk of the SAME upstream:
def t_total() -> U32: 133

def t_skip() -> U32: U32.sub(t_total(), t_len_sym())

def rej_go(es: List<&2, O.PMEntry>, acc: Nat) -> Nat:
  match es:
    case Nil{}: acc
    case e <> t: rej_go(t, Nat.add(acc, Bool.pick(Nat, List.is_empty(&2, O.Op, O.PMEntry.rej(e)), 0n, 1n)))

def t_rej() -> U32: U32.from_nat(rej_go(O.PMEntrys.es(sym_table()), 0n))

def t_lay() -> U32: O.Arena.next(O.Found.ar(fx_add0()))

# A WALL THE GATE ITSELF STANDS ON, and it is the affine arena one more time.
def alu_eq(m: Maybe<&1, O.Const>) -> Bool: i32_is(m, H.i64_of_i32(11))

def alu_eq.go() -> Bool: alu_eq(exec_alu2(O.OpsADD{}, S.weakint(),
  O.CInt{H.i64_of_i32(5)}, O.CInt{H.i64_of_i32(6)}, False{}))

def t_alu() -> U32: Bool.to_u32(alu_eq.go())

def t_alu_rule() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, fold_const_alu.at(fx_of(fx_alu()), 3)))

# THE CONCRETE-DTYPE ROW. The same addition at int32, where `const_like` cannot
def f_cast_cast() -> Bool: sy_is_op(fx_of(fx_i32()), 4, O.OpsCAST{})

def t_alu_i32() -> U32: Bool.to_u32(f_cast_cast())

def t_alu_big() -> U32: Bool.to_u32(Maybe.is_none(&1, O.Const, exec_alu2(O.OpsADD{}, S.weakint(),
  O.CInt{H.i64_of_hi_lo(256, 0)}, O.CInt{H.i64_of_i32(1)}, False{})))

def t_alu_f32() -> U32: Bool.to_u32(f32_is(exec_alu_f32(O.OpsADD{}, 2, 1.5, 2.0, 0.0), 3.5))

def t_fdiv() -> U32: Bool.to_u32(f32_is(exec_alu_f32(O.OpsDIV{}, 2, 7.0, 2.0, 0.0), 3.0))

def t_fdiv_i() -> U32: Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsDIV{}, I3{2, 7, 2, 0}), H.i64_of_i32(3)))

def t_cdiv_i() -> U32: Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsTRUNCDIV{}, I3{2, 7, 2, 0}), H.i64_of_i32(3)))

# the integer lane's `max`, which was a `min` (see `i32_max`). the row is
def t_max_i() -> U32:
  Bool.to_u32(Bool.and(
    i32_is(exec_alu_i32(False{}, O.OpsMAX{}, I3{2, 3, 7, 0}), H.i64_of_i32(7)),
    i32_is(exec_alu_i32(False{}, O.OpsMAX{}, I3{2, 7, 3, 0}), H.i64_of_i32(7))))

def neg7() -> U32: H.i32_neg(7)

def t_cdiv_neg() -> U32:
  Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsTRUNCDIV{}, I3{2, neg7(), 2, 0}),
    H.i64_sub(H.i64_of_i32(0), H.i64_of_i32(3))))

def t_inval() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_castbad()), 2), 1))

def t_inval_st() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_store()), 5), 6))

def t_inval_n() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, sym(fx_of(fx_gatecast()), 5)))

def t_selfadd() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_add0()), 3), 1))

def t_rebind() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_samediv()), 2), 3))

# `rebind0` asks for ABSENCE, not for a particular index: `x // y` must not be
def t_rebind0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_diffdiv()), 3)))

# the second rebind, `(x^y)^y -> x` -- symbolic.py:123 -- with a fixture per side.
# The positive one shares its `y`; the negative one does not.
def fx_xor() -> O.Found:
  +a = f_c(H.i64_of_i32(5))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = f_new(O.Found.ar(b), O.OpsXOR{}, [f_i(a), f_i(b)], O.ANone{})
  f_alu2(c, O.OpsXOR{}, f_i(b))

def t_xorb() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_xor()), 4), 1))

def fx_xor2() -> O.Found:
  +a = f_c(H.i64_of_i32(5))
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(9)})
  +d = f_new(O.Found.ar(c), O.OpsXOR{}, [f_i(a), f_i(b)], O.ANone{})
  f_alu2(d, O.OpsXOR{}, f_i(c))

def t_xorb0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_xor2()), 5)))
# THE TAG-0 FIXTURE. `sym_82` is `STACK(CONST(Invalid), ...) -> the Invalid`, and
# `broadcast` is an `itertools.repeat`, so the STACK may have any arity >= 1.
def fx_bcast() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInvalid{})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})

def t_bcast() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_bcast()), 3), 1))

def t_sink() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_sink()), 5), 6))

# the same rule at a sink root, and the answer is a node that was already there,
def t_sinkgrp() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_sinkgrp()), 5), 3))

def t_sinkgrp0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_sinkgrp0()), 3)))

def t_rm_where() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_where()), 4), 5))

def t_rm_stack() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_stack()), 3), 4))

# THE FIRST-WINS FIXTURE. The overlapping pair is `sym_444` (`GROUP(x)` -> x) and

# ---- THE ROWS FOR TAGS 13..22, and the COUNT rows for the dtype sets. Every
def t_modb() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_mod()), 4), 3))

def t_modb0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_mod2()), 5)))

# the three arms of `sym_138`, and they answer three different nodes because `x` is
def t_ne0() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne0()), 6), 3))

def t_ne1() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne1()), 6), 7))

def t_ne2() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne2()), 6), 1))

# THE PERMUTED SIDE. `ne0r` asks for the SAME answer as `ne0` from a fixture whose
def t_ne0r() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne0r()), 6), 3))

def t_trunc() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_trunc()), 3), 2))

def t_trunc0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_truncf()), 2)))

# `shr` answers `SHR(x, CONST(4))` at 6 and NOT 5, which is the whole claim: the
def t_shr() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_shr()), 5), 6))

def t_shr0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_shr0()), 5)))

def t_fdivm() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_fdivm()), 5), 6))

def t_fdivm0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_fdivm0()), 5)))

# `promo_c` answers `MUL(CAST(3, int32), CAST(0, int32))` at 6: the weak src is
def t_promo_c() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_prom()), 4), 6))

# `promo_c0` used to ask "the port answers nothing", and it was a divergence from
# UPSTREAM DRESSED AS A PASS: upstream's `:163` refuses at a WEAK meet, so the scan
# CONTINUES and upstream's `:178` (`x * 0` -> 0) answers a CONST 0.  MEASURED
def t_promo_c0() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, sym(fx_of(fx_prom0()), 4)))

# `tflo` answers node 2 -- `y`, the node the CAST already sits over -- so the
# unpack MINTS NOTHING on the low side too.
def t_tflo() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_tflo()), 9), 2))

# `tfhi` answers node 3, which is `CAST(x, uint64)` -- the very node `x` sits
# under, because `mixin/dtype.py:19`'s `cast` is `self if self.dtype == dt else
def t_tfhi() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_tfhi()), 10), 3))

def t_tfhi_cast() -> U32: Bool.to_u32(sy_dt_is(fx_of(fx_tfhi()), 3, S.uint64()))

def t_recip3() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recip3()), 4), 7))

def t_recip3x() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_recip3x()), 5)))

# `recipc` AND `recipc0` ASK FOR THE SAME INDEX, and that is the claim: the answer
def t_recipc() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recipc()), 4), 7))

def t_recipc0() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recipc0()), 4), 7))

# THE THREE DTYPE-SET COUNTS, against CPython's own `len(dtypes.ints)`, which is
def dt_count.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case _ <> t: dt_count.go(t, Nat.add(n, 1n))

def t_ints_n() -> U32: U32.from_nat(dt_count.go(DTS_INTS(), 0n))

def t_intish_n() -> U32: U32.from_nat(dt_count.go(DTS_INTISH(), 0n))

def t_intweak_n() -> U32: U32.from_nat(dt_count.go(DTS_INTWEAK(), 0n))

# THE DECLARED-LENGTH ROWS, and they are what makes `sym_table_len` and
# `rm_table_len` live instead of decorative. Both were DEAD before this pass.
def t_len_dec() -> U32: Bool.to_u32(U32.is_eq(U32.from_nat(sym_table_len()), t_len_sym()))

def t_len_dec_rm() -> U32: Bool.to_u32(U32.is_eq(U32.from_nat(rm_table_len()), t_len_rm()))

# THE OP-SET COUNT for `sym_163`, and it is EIGHTEEN: `ops.bend`'s `GroupOp.binary`
def op_count.go(os: List<&2, O.Op>, n: Nat) -> Nat:
  match os:
    case Nil{}: n
    case _ <> t: op_count.go(t, Nat.add(n, 1n))

def t_bin3f_n() -> U32: U32.from_nat(op_count.go(OP_BINARY_3F(), 0n))

def promo_row() -> Bool: Bool.pick(Bool, p_weak(fx_of(fx_add0()), 1), True{}, False{})

def t_promo() -> U32: Bool.to_u32(promo_row())

# THE TABLE IS IN `.agents/slop/tables/uop-symbolic-8439.rows` -- NOT PORTED, one line each, and the WALL each one is behind. The Python line
def t_ig_src2.of(m: Maybe<&1, O.Found>) -> U32:
  match m:
    case None{}: 0
    case Some{+f}:
      +i = O.Found.i(f)
      +a2 = O.Found.ar(f)
      Bool.to_u32(Bool.and(U32.is_eq(O.Arena.nsrc(a2, i), 3),
                           sy_is_invalid_const(F.folded(a2), O.Arena.src(a2, i, 2))))

def t_ig_src2() -> U32:
  +gi  = f_c(H.i64_of_i32(1))
  +gt  = O.UOp.const(O.Found.ar(gi), O.CBool{True{}})
  +cx  = O.UOp.const(O.Found.ar(gt), O.CInt{H.i64_of_i32(2)})
  +cy  = O.UOp.const(O.Found.ar(cx), O.CInt{H.i64_of_i32(3)})
  +inv = O.UOp.const(O.Found.ar(cy), O.CInvalid{})
  +g   = O.UOp.new(O.Found.ar(inv), O.OpsWHERE{}, [O.Found.i(gt), O.Found.i(cx), O.Found.i(inv)], O.ANone{}, O.TNone{})
  +t87 = O.UOp.new(O.Found.ar(g), O.OpsADD{}, [O.Found.i(g), O.Found.i(cy)], O.ANone{}, O.TNone{})
  +fx  = F.folded(O.Found.ar(t87))
  t_ig_src2.of(sym_87(fx, O.Found.i(t87)))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

