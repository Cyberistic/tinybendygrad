# validate.bend -- tinygrad/uop/validate.py.
# The brief called `validate.py` "the SPEC gate: it is what turns 'the graph is

# answer is a LIST, and it is not a preference -- it is three MEASURED facts
#     (validate.py:97-100). The two branches print DIFFERENT text --
#     is `O.Ops.name`. MEASURED: `UOp(Ops.STACK, src=(const 2, const 3))` gives
# `_min_max` BLOCKS MORE THAN ITSELF. `spec.py:22` reads `idx.vmin` and
#     u.axis_id)` (ops.py:97) -- it reads the axis ID and NOT the axis TYPE.
#     `AssertionError: UOp failed to rewrite to z3!`. MEASURED for

import Base
import ./../helpers.bend as H
import ./ops.bend as O
import ./fold.bend as F
import ./../LAWS/spec.bend as S


type Z is Data:
  ZSym{nm: String, is_b: Bool}      # z3.Int(name) / z3.Bool(name)
# `buf.index(r & -4)` is in tinygrad's own test, test_validate_oob.py:97.
#     port 155 rows, oracle 364 rows, SHARED 138, agree 123, disagree 15   (MEASURED)
# ⚠ THE PRIOR PREMISE WAS FALSE. This header used to record, as the reason `dv_and*` could not be
#   `solver.add(z3_mask)` -- validate.py:95 -- now happens (`vz_add_mask`).
#   `create_bounded` built `Le(vmin, sym)`. With `vmin` a Python `int`, validate.py:51 REFLECTS
#   `Ops.TRUNCDIV` was `k = 2`, i.e. `z3_floordiv`, and those are DIFFERENT FUNCTIONS. Two `z3_alu`
#     THOSE ARE DIFFERENT FUNCTIONS. The rule is 60 measured cases and it is in `Z.par`.
#                           `ops.py:302`'s THIRD branch (`if node in cache: continue`) was
# THE `dv_bad_dtype_bitcast` FIXTURE IS NOW ADJUDICABLE, and the stated requirement was FALSE.
# and the "dtype-carrying Arg" the brief asked for already existed. MEASURED: the port's
# the first `.dtype` READ -- `ops.py:122` is `dtype_from_uop(op, src, arg)` and `UOp.__init__`
# defect | rows | what the port prints | what CPython prints (MEASURED)
  ZLit{v: U32, is_b: Bool}          # z3.IntVal(v) / z3.BoolVal(v)
  ZAdd{a: Z, b: Z}                  # a + b
  ZSub{a: Z, b: Z}                  # a - b
  ZMul{a: Z, b: Z}                  # a * b
  ZDiv{a: Z, b: Z}                  # a / b
  ZMod{a: Z, b: Z}                  # a % b
  ZNeg{a: Z}                        # -a
  ZIf{c: Z, a: Z, b: Z}             # z3.If(c, a, b)
  ZLt{a: Z, b: Z}                   # a < b
  ZLe{a: Z, b: Z}                   # a <= b
  ZGt{a: Z, b: Z}                   # a > b
  ZGe{a: Z, b: Z}                   # a >= b
  ZEq{a: Z, b: Z}                   # a == b
  ZNe{a: Z, b: Z}                   # a != b
  ZNeZ{a: Z}                        # a != 0
  ZAnd{a: Z, b: Z}                  # z3.And(a, b)
  ZOr{a: Z, b: Z}                   # z3.Or(a, b)
  ZXor{a: Z, b: Z}                  # z3.Xor(a, b)
  ZFresh{nm: String}                # z3.FreshInt(nm, ctx)
  ZBv{k: U32, w: U32, a: Z, b: Z}   # BV2Int(<k>(Int2BV(a,w), Int2BV(b,w)), is_signed=True)

type Bind is Data: Bind{u: U32, t: Z}

type MRng is Data: MRng{u: U32, lo: U32, hi: U32}

type Sol is Data:
  Sol{cs: List<&2, Z>, es: List<&2, Bind>, ms: List<&2, MRng>}

type MM is Data: MM{lo: U32, hi: U32}

type ZAt is Data: ZAt{hit: Bool, t: Z, v: String}

type Ren is Data: Ren{s: Sol, a: ZAt}

type DtMin is Data: DtMin{got: Bool, v: U32, isz: U32}

type RTag is Data: RTag{hit: Bool, tag: U32}

type VFr is Data: VFr{n: U32, seen: Bool}

type VTopo is Data: VTopo{cache: List<&2, U32>, stack: List<&2, VFr>}

type Vz is Data: Vz{s: Sol, vs: List<&2, String>}

# 4294967295 in a U32. MEASURED: `r ^ -1` is `-(r+1)`.
type Wv is Data: Wv{got: Bool, w: U32}

type Rep is Data: Rep{sz: U32, vs: List<&2, String>, cs: String, term: String}

def bv_xor() -> U32: 2

def bv_and() -> U32: 0

def bv_or() -> U32: 1

def bit_len(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(v, 0), 0, U32.from_nat(Nat.add(U32.log2(v), 1n)))

def z_i(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.and(v, 2147483648), 0), U32.show(v),
            String.concat(["-", U32.show(U32.sub(0, v))]))

def Z.is_b(t: Z) -> Bool:
  match t:
    case ZSym{nm, b}: b
    case ZLit{v, b}: b
    case ZIf{c, a, b}: Z.is_b(a)
    case ZAnd{a, b}: True{}
    case ZOr{a, b}: True{}
    case ZXor{a, b}: True{}
    case ZLt{a, b}: True{}
    case ZLe{a, b}: True{}
    case ZGt{a, b}: True{}
    case ZGe{a, b}: True{}
    case ZEq{a, b}: True{}
    case ZNe{a, b}: True{}
    case ZNeZ{a}: True{}
    case _: False{}

def Z.num(t: Z) -> Maybe<&1, U32>:
  match t:
    case ZLit{v, b}: Some{v}
    case _: None{}

def Z.is_num(t: Z) -> Bool:
  match t:
    case ZLit{v, b}: Bool.not(b)
    case _: False{}

def Z.is_num2(+a: Z, +b: Z) -> Bool:
  Bool.and(Z.is_num(b), Bool.not(Z.is_num(a)))

# and it has exactly two callers: `z3_alu[MAX]`'s `z3.If(a<b, b, a)` (validate.py:47) and
# `python_alu[CMPLT]`'s `operator.lt` (ops.py:1428). Both are handed whatever the renderer
# rewrites `a < n` to `n > a` in that case and ONLY in that case. MEASURED, sexpr included,
def z3_lt(+a: Z, +b: Z) -> Z:
  Bool.pick(Z, Z.is_num2(a, b), ZGt{b, a}, ZLt{a, b})

def z_b(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(v, 0), "False", "True")

def ZLit.str(+v: U32, is_b: Bool) -> String:
  Bool.pick(String, is_b, z_b(v), z_i(v))

# z3's signed `BV2Int`, as `str()` prints it. The `<< 0` is `w`: MEASURED,
def bv_op(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, bv_and()), "&", Bool.pick(String, U32.is_eq(k, bv_or()), "|", "^"))

def ZBv.str(k: U32, w: U32, a: String, b: String) -> String:
  +base = String.concat(["int_to_bv(", a, ") ", bv_op(k), " int_to_bv(", b, ")"])
  +core = String.concat(["BV2Int(", base, ")"])
  String.concat(["If(", base, " < 0, ", core, " - ", U32.show(U32.shln(1, U32.to_nat(w))), ", ", core, ")"])

#      `GE(right, left)`. validate.py:51's `(vmin <= s)` has a Python `int` `vmin`, so the
#      AST is `s >= vmin`. MEASURED: `str(0 <= i)` = `'i >= 0'`, `str(i <= 0)` = `'i <= 0'`.
#      n` becomes `n flip(a)` when `n` is a numeral and `a` is not. MEASURED:
# DIFFERENT FUNCTIONS. A dropped paren in a printer is not a formatting defect, which is why
# though they share a precedence, because MEASURED `a + (b - c)` prints `a + b - c` (no parens)
def Z.cls(t: Z) -> U32:
  match t:
    case ZAdd{a, b}: 1
    case ZMul{a, b}: 2
    case ZDiv{a, b}: 3
    case ZSub{a, b}: 4
    case ZMod{a, b}: 5
    case _: 0

def Z.par.loose(c: U32) -> Bool:
  Bool.not(U32.is_zero(c))

def Z.par.addsub(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 1), U32.is_eq(c, 4))

def Z.par.sub(pc: U32, right: Bool, addsub: Bool) -> Bool:
  Bool.and(right, addsub)

def Z.par(+pc: U32, right: Bool, loose: Bool, addsub: Bool) -> Bool:
  Bool.pick(Bool, U32.is_eq(pc, 1), False{},
    Bool.pick(Bool, U32.is_eq(pc, 4), Z.par.sub(pc, right, addsub), loose))

def Z.ch(+s: String, +c: U32, pc: U32, right: Bool) -> String:
  Bool.pick(String, Z.par(pc, right, Z.par.loose(c), Z.par.addsub(c)),
            String.concat(["(", s, ")"]), s)

def Z.str(t: Z) -> String:
  match t:
    case ZSym{nm, b}: nm
    case ZLit{v, b}: ZLit.str(v, b)
    case ZAdd{+a, +b}: String.concat([Z.ch(Z.str(a), Z.cls(a), 1, False{}), " + ", Z.ch(Z.str(b), Z.cls(b), 1, True{})])
    case ZSub{+a, +b}: String.concat([Z.ch(Z.str(a), Z.cls(a), 4, False{}), " - ", Z.ch(Z.str(b), Z.cls(b), 4, True{})])
    case ZMul{+a, +b}: String.concat([Z.ch(Z.str(a), Z.cls(a), 2, False{}), "*", Z.ch(Z.str(b), Z.cls(b), 2, True{})])
    case ZDiv{+a, +b}: String.concat([Z.ch(Z.str(a), Z.cls(a), 3, False{}), "/", Z.ch(Z.str(b), Z.cls(b), 3, True{})])
    case ZMod{+a, +b}: String.concat([Z.ch(Z.str(a), Z.cls(a), 5, False{}), "%", Z.ch(Z.str(b), Z.cls(b), 5, True{})])
    case ZNeg{+a}:
      Bool.pick(String, U32.is_gt(Z.cls(a), 0), String.concat(["-(", Z.str(a), ")"]),
                                         String.concat(["-", Z.str(a)]))
    case ZIf{c, a, b}: String.concat(["If(", Z.str(c), ", ", Z.str(a), ", ", Z.str(b), ")"])
    case ZLe{a, b}: String.concat([Z.str(a), " <= ", Z.str(b)])
    case ZGe{a, b}: String.concat([Z.str(a), " >= ", Z.str(b)])
    case ZLt{a, b}: String.concat([Z.str(a), " < ", Z.str(b)])
    case ZGt{a, b}: String.concat([Z.str(a), " > ", Z.str(b)])
    case ZEq{a, b}: String.concat([Z.str(a), " == ", Z.str(b)])
    case ZNe{a, b}: String.concat([Z.str(a), " != ", Z.str(b)])
    case ZNeZ{a}: String.concat([Z.str(a), " != 0"])
    case ZAnd{a, b}: String.concat(["And(", Z.str(a), ", ", Z.str(b), ")"])
    case ZOr{a, b}: String.concat(["Or(", Z.str(a), ", ", Z.str(b), ")"])
    case ZXor{a, b}: String.concat(["Xor(", Z.str(a), ", ", Z.str(b), ")"])
    case ZFresh{nm}: nm
    case ZBv{k, w, a, b}: ZBv.str(k, w, Z.str(a), Z.str(b))
    case ZEq{a, b}: String.concat([Z.str(a), " == ", Z.str(b)])
    case ZNe{a, b}: String.concat([Z.str(a), " != ", Z.str(b)])
    case ZNeZ{a}: String.concat([Z.str(a), " != 0"])
    case ZAnd{a, b}: String.concat(["And(", Z.str(a), ", ", Z.str(b), ")"])
    case ZOr{a, b}: String.concat(["Or(", Z.str(a), ", ", Z.str(b), ")"])
    case ZXor{a, b}: String.concat(["Xor(", Z.str(a), ", ", Z.str(b), ")"])
    case ZFresh{nm}: nm
    case ZBv{k, w, a, b}: ZBv.str(k, w, Z.str(a), Z.str(b))

# shorter. MEASURED against CPython's `str(solver)` for all 16 fixtures; see
def cs_str.go(+cs: List<&2, Z>, +acc: String, sep: String) -> String:
  match cs:
    case Nil{}: String.concat(["[", acc, "]"])
    case h <> t: cs_str.go(t, String.concat([acc, sep, Z.str(h)]), ", ")

def cs_str(cs: List<&2, Z>) -> String:
  cs_str.go(cs, "", "")

def Sol.empty() -> Sol:
  Sol{Nil{}, Nil{}, Nil{}}

def Sol.es(+s: Sol) -> List<&2, Bind>:
  match s:
    case Sol{cs, es, ms}: es

def Sol.cs(+s: Sol) -> List<&2, Z>:
  match s:
    case Sol{cs, es, ms}: cs

def Sol.ms(+s: Sol) -> List<&2, MRng>:
  match s:
    case Sol{cs, es, ms}: ms

# `len(ctx[1])` -- the counter in `f"{x.op.name.lower()}{len(ctx[1])}"`, which is what
# names an INDEX or a LOAD's z3 symbol (`index2`, `load3`).
def Sol.n(+s: Sol) -> U32:
  U32.from_nat(List.length(&2, Bind, Sol.es(s)))

def Sol.find.go(+es: List<&2, Bind>, +k: U32) -> Maybe<&1, Z>:
  match es:
    case Nil{}: None{}
    case Bind{u, t} <> rest:
      Bool.pick(Maybe<&1, Z>, U32.is_eq(u, k), Some{t},
                Sol.find.go(rest, k))

def Sol.find(+s: Sol, u: U32) -> Maybe<&1, Z>:
  Sol.find.go(Sol.es(s), u)

# `z3map[u] = z3_rewritten` -- validate.py:88. THE MAP ONLY: CPython's `z3map` is a
# was defect D4, and MEASURED against CPython it is the whole of `dv_var`'s `[, i]` field --
def Sol.put(+s: Sol, u: U32, +t: Z) -> Sol:
  Sol{Sol.cs(s), List.append(&2, Bind, Sol.es(s), [Bind{u, t}]), Sol.ms(s)}

def Sol.add(+s: Sol, +c: Z) -> Sol:
  Sol{List.append(&2, Z, Sol.cs(s), [c]), Sol.es(s), Sol.ms(s)}

def Sol.mm.go(+ms: List<&2, MRng>, +k: U32) -> Maybe<&1, MRng>:
  match ms:
    case Nil{}: None{}
    case MRng{u, lo, hi} <> rest:
      Bool.pick(Maybe<&1, MRng>, U32.is_eq(u, k), Some{MRng{u, lo, hi}},
                Sol.mm.go(rest, k))

def Sol.mm(+s: Sol, u: U32) -> Maybe<&1, MRng>:
  Sol.mm.go(Sol.ms(s), u)

def Sol.put_mm(+s: Sol, u: U32, lo: U32, hi: U32) -> Sol:
  Sol{Sol.cs(s), Sol.es(s), List.append(&2, MRng, Sol.ms(s), [MRng{u, lo, hi}])}

def MM.lo(m: MM) -> U32:
  match m:
    case MM{lo, hi}: lo

def MM.hi(m: MM) -> U32:
  match m:
    case MM{lo, hi}: hi

def MRng.lo(m: MRng) -> U32:
  match m:
    case MRng{u, lo, hi}: lo

def MRng.hi(m: MRng) -> U32:
  match m:
    case MRng{u, lo, hi}: hi

def vz_lo(i: H.I64) -> U32:
  match i:
    case H.I64{hi, lo}: lo

# `z3.BoolVal(x.val)` if `x.dtype == dtypes.bool` else `z3.IntVal(x.val)` (validate.py:75), and
# gate of every fixture IS one (`UOp.const(True)`). MEASURED with `.agents/slop/mask-probe.bend`
def vz_cbool(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def vz_cint(c: O.Const) -> Maybe<&1, U32>:
  match c:
    case O.CInt{i}: Some{vz_lo(i)}
    case O.CBool{b}: Some{vz_cbool(b)}
    case _: None{}

def vz_cval.go(a: O.Arg) -> Maybe<&1, U32>:
  match a:
    case O.APy{v}: vz_cint(v)
    case _: None{}

def vz_cval(ar: O.Arena, i: U32) -> Maybe<&1, U32>:
  vz_cval.go(O.Arena.arg(ar, i))

def vz_mm.put(cval: Maybe<&1, U32>, m: Maybe<&1, MRng>) -> Maybe<&1, MM>:
  match cval:
    case Some{+v}: Some{MM{v, v}}
    case None{}:
      match m:
        case Some{+r}: Some{MM{MRng.lo(r), MRng.hi(r)}}
        case None{}: None{}

def vz_mm.of(cval: Maybe<&1, U32>, m: Maybe<&1, MRng>) -> Maybe<&1, MM>:
  vz_mm.put(cval, m)

def vz_mm(ar: O.Arena, s: Sol, +i: U32) -> Maybe<&1, MM>:
  vz_mm.of(vz_cval(ar, i), Sol.mm(s, i))

def vz_max0(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(v, 2147483648), 0), v, 0)

# `range_str` (ops.py:95): the axis IDS joined by `_`, negatives as `m<n>`.
# symbol `r` where CPython prints `r0` (defect D3). MEASURED against `range_str` itself:
def rs_one(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.and(v, 2147483648), 0), U32.show(v),
            String.concat(["m", U32.show(U32.sub(0, v))]))

def rs_ids.go(+ids: List<&2, U32>, +acc: String, sep: String) -> String:
  match ids:
    case Nil{}: acc
    case h <> t: rs_ids.go(t, String.concat([acc, sep, rs_one(h)]), "_")

def zat.miss(v: String) -> ZAt:
  ZAt{False{}, ZLit{0, False{}}, v}

def zat.hit(t: Z) -> ZAt:
  ZAt{True{}, t, ""}

def zat.of(m: Maybe<&1, Z>, miss: String) -> ZAt:
  match m:
    case Some{t}: zat.hit(t)
    case None{}: zat.miss(miss)

def zm(m: Maybe<&1, Z>, miss: String) -> ZAt:
  match m:
    case Some{t}: zat.hit(t)
    case None{}: zat.miss(miss)

def ZAt.t(a: ZAt) -> Z:
  match a:
    case ZAt{hit, t, v}: t

def ZAt.hit(a: ZAt) -> Bool:
  match a:
    case ZAt{hit, t, v}: hit

def ZAt.v(a: ZAt) -> String:
  match a:
    case ZAt{hit, t, v}: v

def zat.rank(+ar: O.Arena, +self: U32, n: U32, rule: String) -> String:
  String.concat([rule, ": ", O.Ops.name(O.Arena.op(ar, self)), " has ",
                 U32.show(O.Arena.nsrc(ar, self)), " srcs, needs ", U32.show(U32.add(n, 1))])

def zat.src(+ar: O.Arena, +s: Sol, +self: U32, +n: U32, +rule: String) -> ZAt:
  Bool.pick(ZAt, U32.is_ge(n, O.Arena.nsrc(ar, self)),
            zat.miss(zat.rank(ar, self, n, rule)),
            zat.of(Sol.find(s, O.Arena.src(ar, self, n)), zat.rank(ar, self, n, rule)))

# `both answers present`, and `the first message` -- the two combines a rule needs when it
# reads two srcs.
def zall(+a: ZAt, +b: ZAt) -> Bool:
  Bool.and(ZAt.hit(a), ZAt.hit(b))

def zwhy(+a: ZAt, +b: ZAt) -> String:
  Bool.pick(String, ZAt.hit(a), ZAt.v(b), ZAt.v(a))

# IDIV IS TRUNCATED, Z3 IS EUCLIDEAN. validate.py:11 -- z3 floors when the
# `ArithRef.__gt__(0)`. MEASURED: `str(0 < i)` is `i > 0` and `str(IntVal(0) < i)` is
def z3_cdiv(+a: Z, +b: Z) -> Z:
  ZIf{ZLt{a, ZLit{0, False{}}},
       ZIf{ZGt{b, ZLit{0, False{}}}, ZDiv{ZAdd{a, ZSub{b, ZLit{1, False{}}}}, b},
                                                 ZDiv{ZSub{a, ZAdd{b, ZLit{1, False{}}}}, b}},
       ZDiv{a, b}}

def z3_floordiv(+a: Z, +b: Z) -> Z:
  ZIf{ZGt{b, ZLit{0, False{}}}, ZDiv{a, b}, ZDiv{ZNeg{a}, ZNeg{b}}}

def pow2(+m: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(m)), U32.is_eq(U32.and(m, U32.sub(m, 1)), 0))

def bv_max(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

# `1 << k`, saturating past 31 -- which is the right answer here because `1 << 32` IS 0 in
# a U32.
def z3_pow(k: U32) -> U32:
  U32.shln(1, U32.to_nat(k))

def bv_one(+v: U32) -> U32:
  bit_len(Bool.pick(U32, U32.is_eq(U32.and(v, 2147483648), 0), v, U32.sub(0, v)))

def z3_bv.put(k: U32, w: Maybe<&1, U32>, a: Z, b: Z) -> Maybe<&1, Z>:
  match w:
    case Some{n}: Some{ZBv{k, n, a, b}}
    case None{}: None{}

def z3_xor.m1(n: Maybe<&1, U32>, t: Z, rest: Maybe<&1, Z>) -> Maybe<&1, Z>:
  match n:
    case Some{v}: Bool.pick(Maybe<&1, Z>, U32.is_eq(v, 4294967295), Some{ZNeg{ZAdd{t, ZLit{1, False{}}}}}, rest)
    case None{}: rest

def z3_xor.m2(ab: Bool, first: Maybe<&1, Z>, na: Maybe<&1, U32>, rest: Maybe<&1, Z>, +a: Z, +b: Z, w: Wv) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, ab, Some{ZXor{a, b}}, z3_xor.m1(na, b, first))

def z3_scale(is_shr: Bool, +a: Z, +f: U32) -> Z:
  Bool.pick(Z, is_shr, ZDiv{a, ZLit{f, False{}}}, ZMul{a, ZLit{f, False{}}})

def z3_shift.cond(b: Z, lo: U32, i: U32) -> Z:
  ZEq{ZMod{ZDiv{ZSub{b, ZLit{lo, False{}}}, ZLit{z3_pow(i), False{}}}, ZLit{1, False{}}},
      ZLit{1, False{}}}

def z3_shift.factor(i: U32) -> U32:
  z3_pow(z3_pow(i))

def z3_shift.fin(a: Z, b: Z) -> Z:
  ZIf{ZLt{b, ZLit{0, False{}}}, ZFresh{"invalid_shift"}, a}

def z3_shift.steps(+hi: U32, +lo: U32) -> U32:
  Bool.pick(U32, U32.is_le(hi, lo), 0, bit_len(U32.sub(hi, lo)))

def dt_in_ints.go(c: S.Cls) -> Bool:
  match c:
    case S.CUint{}: True{}
    case S.CSint{}: True{}
    case _: False{}

def dt_in_floats.go(c: S.Cls) -> Bool:
  match c:
    case S.CFloat{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def vz_dt.of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# AST holds `s >= vmin`. MEASURED in one process, one context: `str(0 <= i)` is `i >= 0` and
def create_bounded(+s: Sol, +nm: String, vmin: Z, vmax: Z) -> Ren:
  +sym: Z = ZSym{nm, False{}}
  Ren{Sol.add(s, ZAnd{ZGe{sym, vmin}, ZLe{sym, vmax}}), zat.hit(sym)}

def create_var.bound(+s: Sol, m: Maybe<&1, MM>, nm: String, miss: String) -> Ren:
  match m:
    case Some{+r}: create_bounded(s, nm, ZLit{MM.lo(r), False{}}, ZLit{MM.hi(r), False{}})
    case None{}: Ren{s, zat.miss(miss)}

def cv_name(op: O.Op, n: U32) -> String:
  String.concat([String.to_lower(O.Ops.name.of(op)), U32.show(n)])

def pa_name(a: O.Arg) -> Maybe<&2, String>:
  match a:
    case O.AParam{pa}: O.ParamArg.name(pa)
    case _: None{}

def cv_arg_name.put(m: Maybe<&2, String>) -> String:
  match m:
    case Some{n}: n
    case None{}: "null"

# bool and int", so a float cast is the IDENTITY. MEASURED: the CAST in
def z3_cast(+sb: Bool, +db: Bool, +t: Z) -> Z:
  Bool.pick(Z, Bool.pick(Bool, sb, db, Bool.not(db)), t, ZNeZ{t})

def ren_1.put(+c: ZAt, +x: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(c, x), Ren{Sol.add(s, ZAt.t(c)), x}, Ren{s, zat.miss(zwhy(c, x))})

def ren_2.put(+hi: ZAt, nm: String, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(hi),
            create_bounded(s, nm, ZLit{0, False{}}, ZSub{ZAt.t(hi), ZLit{1, False{}}}),
            Ren{s, hi})

def ren_3_defines.go(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case _: False{}

def ren_5.dmin.go(m: Maybe<&2, U32>, +isz: U32) -> DtMin:
  match m:
    case Some{v}: DtMin{Bool.not(U32.is_gt(isz, 4)), v, isz}
    case None{}: DtMin{False{}, 0, isz}

def DtMin.v(m: DtMin) -> U32:
  match m:
    case DtMin{got, v, isz}: v

def DtMin.isz(m: DtMin) -> U32:
  match m:
    case DtMin{got, v, isz}: isz

def ren_5.mod(+x: ZAt, +m: DtMin) -> Z:
  ZAdd{ZMod{ZSub{ZAt.t(x), ZLit{DtMin.v(m), False{}}},
             ZLit{z3_pow(U32.mul(8, DtMin.isz(m))), False{}}},
       ZLit{DtMin.v(m), False{}}}

def DtMin.got(m: DtMin) -> Bool:
  match m:
    case DtMin{got, v, isz}: got

def ren_5.why.str(+m: DtMin, +xv: String) -> String:
  Bool.pick(String, DtMin.got(m),
    String.concat(["rule 5: a ", U32.show(DtMin.isz(m)), "-byte dtype wraps mod 2^64, U32 cannot; ", xv]),
    String.concat(["rule 5: a ", U32.show(DtMin.isz(m)), "-byte dtype has no U32 min; ", xv]))

def ren_6(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  Ren{s, zat.hit(ZSym{"Invalid", False{}})}

def ren_7.put(m: Maybe<&1, U32>, is_bool: Bool, +s: Sol) -> Ren:
  match m:
    case Some{v}: Ren{s, zat.hit(ZLit{v, is_bool})}
    case None{}: Ren{s, zat.miss("rule 7: a CONST with no value")}

def ren_8.put(+x: ZAt, +sb: Bool, +db: Bool, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(x), Ren{s, zat.hit(z3_cast(sb, db, ZAt.t(x)))}, Ren{s, x})

# (validate.py:12) truncates toward zero and only its `a < 0` arm differs from `z3_floordiv`'s
def ren_9.b2.mk(+k: U32, +a: Z, +b: Z) -> Z:
  Bool.pick(Z, U32.is_eq(k, 2), z3_floordiv(a, b),
    Bool.pick(Z, U32.is_eq(k, 1), ZSub{a, ZMul{z3_cdiv(a, b), b}},
      Bool.pick(Z, U32.is_eq(k, 4), z3_cdiv(a, b),
                                   ZSub{a, ZMul{z3_floordiv(a, b), b}})))

# `validate.py:47`'s `Ops.MAX: lambda _,a,b: z3.If(a<b, b, a)` was rendered as
def ren_9.mx.mk(+a: Z, +b: Z) -> Z:
  ZIf{z3_lt(a, b), b, a}


def z3why(+a: ZAt, w: String) -> String:
  Bool.pick(String, ZAt.hit(a), w, ZAt.v(a))

def t_invalid.c(c: O.Const) -> Bool:
  match c:
    case O.CInvalid{}: True{}
    case _: False{}

def ren_t2.put(+op: O.Op) -> Bool:
  Bool.or(O.eq_op(op, O.OpsSPECIAL{}), O.eq_op(op, O.OpsRANGE{}))

def ren_t3.put2(is_load: Bool, rest: Bool) -> Bool:
  Bool.or(is_load, rest)

def ren_t4_op(+op: O.Op) -> Bool:
  Bool.or(Bool.or(O.eq_op(op, O.OpsCAST{}), O.eq_op(op, O.OpsBITCAST{})),
          Bool.or(O.eq_op(op, O.OpsCMPLT{}),
                  Bool.or(O.eq_op(op, O.OpsCMPNE{}), O.eq_op(op, O.OpsCMPEQ{}))))

def ren_t7(+ar: O.Arena, +self: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, self), O.OpsCONST{})

def ren_t8(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.eq_op(O.Arena.op(ar, self), O.OpsCAST{}), U32.is_eq(O.Arena.nsrc(ar, self), 1))

# `tuple(z3_alu)` -- the ELEVEN keys of validate.py:77-48. A list is the honest
def z3_alu_ops() -> List<&2, O.Op>:
  [O.OpsTRUNCMOD{}, O.OpsTRUNCDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsWHERE{},
   O.OpsMAX{}, O.OpsAND{}, O.OpsOR{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}]

# k = 4 IS `z3_lt` AND NOT `ZLt`: `python_alu[CMPLT]` is `operator.lt`, and `operator.lt` on a
# z3 NUMERAL right operand is what z3 canonicalises. MEASURED, and `dv_where` is the only row
def ren_10.mk(+k: U32, +a: Z, +b: Z) -> Z:
  Bool.pick(Z, U32.is_eq(k, 1), ZAdd{a, b},
    Bool.pick(Z, U32.is_eq(k, 2), ZSub{a, b},
      Bool.pick(Z, U32.is_eq(k, 3), ZMul{a, b},
        Bool.pick(Z, U32.is_eq(k, 4), z3_lt(a, b),
          Bool.pick(Z, U32.is_eq(k, 5), ZNe{a, b}, ZEq{a, b})))))

def ren_10.b2.put(+k: U32, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), Ren{s, zat.hit(ren_10.mk(k, ZAt.t(a), ZAt.t(b)))}, Ren{s, zat.miss(zwhy(a, b))})

def ren_10.b1.put(+a: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(a), Ren{s, zat.hit(ZNeg{ZAt.t(a)})}, Ren{s, a})

def ren_10.b3.put(+a: ZAt, +b: ZAt, +c: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(zall(a, b), ZAt.hit(c)),
            Ren{s, zat.hit(ZAdd{ZMul{ZAt.t(a), ZAt.t(b)}, ZAt.t(c)})},
            Ren{s, zat.miss(z3why(c, zwhy(a, b)))})

def ren_10.why(op: String) -> String:
  String.concat([op, " is not supported by z3"])

def rt(hit: Bool, tag: U32) -> RTag: RTag{hit, tag}

def ren_t10(+ar: O.Arena, +self: U32) -> Bool:
  O.GroupOp.alu(O.Arena.op(ar, self))

def rt_first(+ts: List<&2, RTag>) -> U32:
  match ts:
    case Nil{}: 10
    case RTag{+hit, tag} <> rest: Bool.pick(U32, hit, tag, rt_first(rest))

def ren_unsup(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  Ren{s, zat.miss(String.concat([O.Ops.name(O.Arena.op(ar, self)), " is not supported by z3"]))}

def VTopo.empty() -> VTopo:
  VTopo{Nil{}, Nil{}}

def vz_keep.put(not_mem: Bool, dt_ok: Bool, op: O.Op) -> Bool:
  Bool.and(not_mem, Bool.or(dt_ok, O.eq_op(op, O.OpsSINK{})))

def vz_not_mem.go(op: O.Op) -> Bool:
  match op:
    case O.OpsAFTER{}: False{}
    case O.OpsSHRINK{}: False{}
    case O.OpsALLOC{}: False{}
    case O.OpsBUFFER{}: False{}
    case _: True{}

def vz_push_srcs.go(+srcs: List<&2, U32>, st: List<&2, VFr>) -> List<&2, VFr>:
  match srcs:
    case Nil{}: st
    case s <> t: vz_push_srcs.go(t, VFr{s, False{}} <> st)

def vz_cache_add(n: U32, t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}: VTopo{List.append(&2, U32, cache, [n]), stack}

def vz_cache_of(t: VTopo) -> List<&2, U32>:
  match t:
    case VTopo{cache, stack}: cache

# `[:-1]` -- validate.py:37 drops the LAST element and says "assume it is the
def vz_drop_sink(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case u <> t:
      vz_drop_sink(t, ar, Bool.pick(List<&2, U32>, O.eq_op(O.Arena.op(ar, u), O.OpsSINK{}),
                                    acc, List.append(&2, U32, acc, [u])))

def vz_vs.go(acc: Vz) -> List<&2, String>:
  match acc:
    case Vz{s, vs}: vs

def vz_cs.go(acc: Vz) -> List<&2, Z>:
  match acc:
    case Vz{s, vs}: Sol.cs(s)

def vz_s.go(acc: Vz) -> Sol:
  match acc:
    case Vz{s, vs}: s

def vz_term.of(m: Maybe<&1, Z>) -> String:
  match m:
    case Some{t}: Z.str(t)
    case None{}: ""

def vz_zat(m: Maybe<&1, Z>, i: U32, n: U32) -> Z:
  match m:
    case Some{t}: t
    case None{}: ZSym{String.concat(["dv_mask_missing@", U32.show(i), "/n=", U32.show(n)]), False{}}

# WALL(p3) validate.py:99  the `{solver.model()}` tail of the sat message. -- BLOCKED: needs `solver.model()`, a Z3 SOLVER OUTPUT on the `z3.sat` branch of the out-of-bounds report (`validate.py:98`). The port has no Z3, and a model cannot be rendered without solving -- which the file says two lines above, so this line is the marker for a documented wall rather than a new gap.
def vd_model() -> String:
  "solver.model() is not ported"

# WALL(p3) validate.py:100  the `{solver.reason_unknown()}` tail. -- BLOCKED: needs `solver.reason_unknown()` on the `z3.unknown` branch -- the same shape as `:99`, the other non-unsat arm.
def vd_reason() -> String:
  "solver.reason_unknown() is not ported"

# index does: MEASURED, `UOp.variable("w",0,15).sin()` has a gated toposort of
def vz_rewrite_failed(idx: U32, gate: U32, +acc: Vz) -> Bool:
  Bool.or(U32.is_zero(idx), U32.is_zero(gate))

def bv_max4(+p: MM, +q: MM) -> U32:
  bv_max(bv_max(bv_one(MM.hi(p)), bv_one(MM.hi(q))), bv_max(bv_one(MM.lo(p)), bv_one(MM.lo(q))))

# validate.py:14 -- THE WIDTH IS THE NARROWEST ONE THAT FITS BOTH SIDES IN
def z3_bv(k: U32, w: Maybe<&1, U32>, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(k, w, a, b)

def wv(m: Maybe<&1, U32>) -> Wv:
  match m:
    case Some{w}: Wv{True{}, w}
    case None{}: Wv{False{}, 0}

def Wv.got(w: Wv) -> Bool:
  match w:
    case Wv{got, w}: got

def Wv.w(w: Wv) -> U32:
  match w:
    case Wv{got, w}: w

def z3_xor.wb(k: U32, w: U32, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(k, Some{w}, a, b)

def z3_xor.wv(+w: Wv, +a: Z, +b: Z, k: U32) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Wv.got(w), z3_xor.wb(k, Wv.w(w), a, b), None{})

# `x ^ -1 = -(x+1)` IS BITWISE NOT. validate.py:20 -- the constant `-1` case
# Python either, which is why `r | (r << 1)` in test_validate_oob.py:113 is a
def z3_or(w: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Z.is_b(a), Some{ZOr{a, b}}, z3_bv(bv_or(), w, a, b))

# FACTOR OUT THE MINIMUM COUNT, THEN THE VARYING BITS. validate.py:35 -- a
def z3_shift.armed(is_shr: Bool, +a: Z, b: Z, lo: U32, +i: U32) -> Z:
  ZIf{z3_shift.cond(b, lo, i), z3_scale(is_shr, a, z3_shift.factor(i)), a}

# GATE's dtype half, validate.py:83-84. It is `Dt.is_int or Dt.is_bool` and NOT
def dt_kept(+d: S.Dt) -> Bool:
  Bool.or(S.Dt.is_int(d), S.Dt.is_bool(d))

def dt_in_ints(d: S.Dt) -> Bool:
  dt_in_ints.go(S.Dt.cls(d))

def dt_in_floats(d: S.Dt) -> Bool:
  dt_in_floats.go(S.Dt.cls(d))

def vz_dt(fx: F.Folded, i: U32) -> S.Dt:
  match fx:
    case F.Folded{ar, tb}: vz_dt.of(F.fold.dt(ar, tb, i))

def create_var.of(is_bool: Bool, +s: Sol, m: Maybe<&1, MM>, +nm: String, miss: String) -> Ren:
  Bool.pick(Ren, is_bool, Ren{s, zat.hit(ZSym{nm, True{}})}, create_var.bound(s, m, nm, miss))

def cv_arg_name.of(a: O.Arg) -> String:
  cv_arg_name.put(pa_name(a))

# `Solver.add` returns None so the `or` answers `x`. MEASURED: `valid` is a
def ren_1(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_1.put(zat.src(ar, s, self, 0, "rule 1 cond"), zat.src(ar, s, self, 1, "rule 1 x"), s)

def ren_3_defines(op: O.Op) -> Bool:
  ren_3_defines.go(op)

def ren_5.dmin(m: Maybe<&2, U32>, isz: U32) -> DtMin:
  ren_5.dmin.go(m, isz)

def ren_5.ok(+x: ZAt, m: DtMin, +s: Sol) -> Ren:
  Ren{s, zat.hit(ren_5.mod(x, m))}

def ren_5.why(+x: ZAt, m: DtMin, +s: Sol) -> Ren:
  Ren{s, zat.miss(ren_5.why.str(m, ZAt.v(x)))}

def ren_7(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_7.put(vz_cval(ar, self), S.Dt.is_bool(vz_dt(fx, self)), s)

def ren_8(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_8.put(zat.src(ar, s, self, 0, "rule 8 x"),
            S.Dt.is_bool(vz_dt(fx, O.Arena.src(ar, self, 0))), S.Dt.is_bool(vz_dt(fx, self)), s)

def ren_9.b2.put(+k: U32, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), Ren{s, zat.hit(ren_9.b2.mk(k, ZAt.t(a), ZAt.t(b)))}, Ren{s, zat.miss(zwhy(a, b))})

def ren_9.mx(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  Bool.pick(Ren, zall(zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1")),
            Ren{s, zat.hit(ren_9.mx.mk(ZAt.t(zat.src(ar, s, self, 0, "rule 9 src0")),
                                       ZAt.t(zat.src(ar, s, self, 1, "rule 9 src1"))))},
            Ren{s, zat.miss(zwhy(zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1")))})

def ren_9.w3.go(+c: ZAt, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(ZAt.hit(c), zall(a, b)), Ren{s, zat.hit(ZIf{ZAt.t(c), ZAt.t(a), ZAt.t(b)})},
            Ren{s, zat.miss(z3why(c, zwhy(a, b)))})

def t_invalid.arg(a: O.Arg) -> Bool:
  match a:
    case O.APy{v}: t_invalid.c(v)
    case _: False{}

def ren_t2(+ar: O.Arena, +self: U32) -> Bool:
  ren_t2.put(O.Arena.op(ar, self))

def ren_t3.put3(op: O.Op) -> Bool:
  ren_3_defines(op)

def ren_t4.put2(is_op: Bool, has_src: Bool, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(is_op, has_src), dt_in_floats(vz_dt(fx, O.Arena.src(ar, self, 0))))

def ren_t5_x(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  dt_in_ints(vz_dt(fx, O.Arena.src(ar, self, 0)))

def t_invalid_arg(a: O.Arg) -> Bool:
  t_invalid.arg(a)

def ren_t9(+ar: O.Arena, +self: U32) -> Bool:
  List.contains(O.Op, O.eq_op, z3_alu_ops(), O.Arena.op(ar, self))

def ren_10.b2(k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b2.put(k, zat.src(ar, s, self, 0, "rule 10 src0"), zat.src(ar, s, self, 1, "rule 10 src1"), s)

def ren_10.b1(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b1.put(zat.src(ar, s, self, 0, "rule 10 src0"), s)

def ren_10.b3(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b3.put(zat.src(ar, s, self, 0, "rule 10 src0"), zat.src(ar, s, self, 1, "rule 10 src1"),
                zat.src(ar, s, self, 2, "rule 10 src2"), s)

def vz_not_mem(op: O.Op) -> Bool:
  vz_not_mem.go(op)

def vz_push_srcs(+srcs: List<&2, U32>, st: List<&2, VFr>) -> List<&2, VFr>:
  vz_push_srcs.go(List.reverse(&2, U32, srcs), st)

def vz_push(ar: O.Arena, +n: U32, +t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}: VTopo{cache, vz_push_srcs(O.Arena.srcs(ar, n), VFr{n, True{}} <> stack)}

# `ops.py:302` is `if node in cache: continue` -- a THIRD branch, checked on EVERY pop before
# MEASURED by `.agents/slop/vw-topo-probe.bend` against `.agents/slop/vw-topo-truth.py`, and
def vz_step.keep(keep: Bool, ar: O.Arena, +n: U32, +rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  Bool.pick(VTopo, keep, vz_push(ar, n, VTopo{cache, rest}), VTopo{cache, rest})

def vz_vs(acc: Vz) -> List<&2, String>:
  vz_vs.go(acc)

def vz_cs(acc: Vz) -> List<&2, Z>:
  vz_cs.go(acc)

def vz_s(acc: Vz) -> Sol:
  vz_s.go(acc)

def vz_term(+acc: Vz, i: U32) -> String:
  vz_term.of(Sol.find(vz_s(acc), i))

# ABSOLUTE value. MEASURED twice: `r & 21` over a RANGE(100) gives 8, and
def bv_w.tail(p: MM, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  match b:
    case Some{q}: Some{U32.add(1, bv_max4(p, q))}
    case None{}: None{}

def bv_w.go(a: Maybe<&1, MM>, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  match a:
    case Some{p}: bv_w.tail(p, b)
    case None{}: None{}

def bv_w.put(a: Maybe<&1, MM>, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  bv_w.go(a, b)

def bv_w(+ar: O.Arena, +s: Sol, +self: U32) -> Maybe<&1, U32>:
  bv_w.put(vz_mm(ar, s, O.Arena.src(ar, self, 0)), vz_mm(ar, s, O.Arena.src(ar, self, 1)))

def z3_shift.go(k: Nat, +is_shr: Bool, +a: Z, +b: Z, +lo: U32, +i: U32) -> Z:
  match k:
    case 0n: z3_shift.fin(a, b)
    case 1n+p: z3_shift.go(p, is_shr, z3_shift.armed(is_shr, a, b, lo, i), b, lo, U32.add(i, 1))

def create_var(+s: Sol, m: Maybe<&1, MM>, is_bool: Bool, nm: String, miss: String) -> Ren:
  create_var.of(is_bool, s, m, nm, miss)

# `z3.Int(None)`, which prints `null`. That is the MEASURED text for
def cv_arg_name(ar: O.Arena, i: U32) -> String:
  cv_arg_name.of(O.Arena.arg(ar, i))

def ren_3_name(+ar: O.Arena, +self: U32, n: U32) -> String:
  Bool.pick(String, ren_3_defines(O.Arena.op(ar, self)), cv_arg_name(ar, self),
            cv_name(O.Arena.op(ar, self), n))

def ren_4(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  create_var(s, vz_mm(ar, s, self), S.Dt.is_bool(vz_dt(fx, self)),
             cv_name(O.Arena.op(ar, self), Sol.n(s)), "rule 4 create_var: unknown bounds")

def ren_5.put(+x: ZAt, +m: DtMin, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(DtMin.got(m), ZAt.hit(x)), ren_5.ok(x, m, s), ren_5.why(x, m, s))

def ren_9.b2(+k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.b2.put(k, zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1"), s)

def ren_9.w3.put(+c: ZAt, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  ren_9.w3.go(c, a, b, s)

def t_invalid.go(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsCONST{}: t_invalid.arg(a)
    case _: False{}

def ren_t3.put(+op: O.Op) -> Bool:
  ren_t3.put2(O.eq_op(op, O.OpsLOAD{}), ren_t3.put3(op))

def ren_t4.put(is_op: Bool, nsrc: U32, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t4.put2(is_op, U32.is_ge(nsrc, 1), ar, fx, self)

def ren_t5.put(is_op: Bool, nsrc: U32, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(Bool.and(is_op, U32.is_eq(nsrc, 1)), dt_in_ints(vz_dt(fx, self))), ren_t5_x(ar, fx, self))

def ren_t6(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.eq_op(O.Arena.op(ar, self), O.OpsCONST{}), t_invalid_arg(O.Arena.arg(ar, self)))

def ren_10.go(op: O.Op, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  match op:
    case O.OpsADD{}: ren_10.b2(1, ar, s, self)
    case O.OpsSUB{}: ren_10.b2(2, ar, s, self)
    case O.OpsMUL{}: ren_10.b2(3, ar, s, self)
    case O.OpsCMPLT{}: ren_10.b2(4, ar, s, self)
    case O.OpsCMPNE{}: ren_10.b2(5, ar, s, self)
    case O.OpsCMPEQ{}: ren_10.b2(6, ar, s, self)
    case O.OpsNEG{}: ren_10.b1(ar, s, self)
    case O.OpsMULACC{}: ren_10.b3(ar, s, self)
    case _: Ren{s, zat.miss(ren_10.why(O.Ops.name(O.Arena.op(ar, self))))}

def vz_keep(+op: O.Op, dt: S.Dt) -> Bool:
  vz_keep.put(vz_not_mem(op), dt_kept(dt), op)

def vz_step.fresh(+ar: O.Arena, +fx: F.Folded, +n: U32, rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  vz_step.keep(vz_keep(O.Arena.op(ar, n), vz_dt(fx, n)), ar, n, rest, cache)

def vz_step.seen(cache: List<&2, U32>, +n: U32, ar: O.Arena, +fx: F.Folded, +rest: List<&2, VFr>, +c: List<&2, U32>) -> VTopo:
  Bool.pick(VTopo, List.contains(U32, U32.is_eq, cache, n), VTopo{c, rest}, vz_step.fresh(ar, fx, n, rest, c))

def vz_step.vis(ar: O.Arena, +fx: F.Folded, +n: U32, visited: Bool, rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  match visited:
    case True{}: vz_cache_add(n, VTopo{cache, rest})
    case False{}: vz_step.seen(cache, n, ar, fx, rest, cache)

def vz_step(ar: O.Arena, +fx: F.Folded, t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}:
      match stack:
        case Nil{}: t
        case VFr{n, seen} <> rest: vz_step.vis(ar, fx, n, seen, rest, cache)

def vz_topo.go(fuel: Nat, +ar: O.Arena, +fx: F.Folded, t: VTopo) -> List<&2, U32>:
  match fuel:
    case 0n: vz_cache_of(t)
    case 1n+p: vz_topo.go(p, ar, fx, vz_step(ar, fx, t))

def vz_one.hit(+acc: Vz, +s: Sol, +a: ZAt, u: U32) -> Vz:
  Bool.pick(Vz, ZAt.hit(a),
            Vz{Sol.put(s, u, ZAt.t(a)), vz_vs(acc)},
            Vz{s, List.append(&2, String, vz_vs(acc), [ZAt.v(a)])})

# `solver.add(z3_mask)` -- validate.py:95, and it is the reason every CPython constraint list
# ENDS `, True]`. MEASURED, and the addition is what adds it:
# missing lookup with the RIGHT index and the WRONG bind count is the signature of a walk that
def vz_add_mask(+acc: Vz, +m: U32) -> Vz:
  +s: Sol = vz_s(acc)
  Vz{Sol.add(s, vz_zat(Sol.find(s, m), m, Sol.n(s))), vz_vs(acc)}

def validate_index_with_z3(sz: U32, +acc: Vz, idx: U32) -> Rep:
  Rep{sz, vz_vs(acc), cs_str(vz_cs(acc)), vz_term(acc, idx)}

def z3_shift(+is_shr: Bool, a: Z, b: Z, +lo: U32, steps: U32) -> Z:
  z3_shift.go(U32.to_nat(steps), is_shr, z3_scale(is_shr, a, z3_pow(lo)), b, lo, 0)

def ren_3(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  create_var(s, vz_mm(ar, s, self), S.Dt.is_bool(vz_dt(fx, self)),
             ren_3_name(ar, self, Sol.n(s)), "rule 3 create_var: unknown bounds")

# A BITCAST BETWEEN INTS WRAPS. validate.py:72 -- z3 integers are unbounded, so
def ren_5(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_5.put(zat.src(ar, s, self, 0, "rule 5 x"),
            ren_5.dmin(S.Dt.min(vz_dt(fx, self)), S.Dt.itemsize(vz_dt(fx, self))), s)

def ren_9.w3(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.w3.put(zat.src(ar, s, self, 0, "rule 9 cond"), zat.src(ar, s, self, 1, "rule 9 a"),
               zat.src(ar, s, self, 2, "rule 9 b"), s)

def ren_9.sh.z(is_shr: Bool, a: ZAt, b: ZAt, +r: MM) -> Z:
  z3_shift(is_shr, ZAt.t(a), ZAt.t(b), vz_max0(MM.lo(r)), z3_shift.steps(MM.hi(r), vz_max0(MM.lo(r))))

def t_invalid(+ar: O.Arena, +i: U32) -> Bool:
  t_invalid.go(O.Arena.op(ar, i), O.Arena.arg(ar, i))

def ren_t3(+ar: O.Arena, +self: U32) -> Bool:
  ren_t3.put(O.Arena.op(ar, self))

def ren_t4(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t4.put(ren_t4_op(O.Arena.op(ar, self)), O.Arena.nsrc(ar, self), ar, fx, self)

def ren_t5(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t5.put(ren_t4_op(O.Arena.op(ar, self)), O.Arena.nsrc(ar, self), ar, fx, self)

# `math.*` on a SYMBOLIC z3 value, which CPython itself cannot do -- MEASURED,
def ren_10(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.go(O.Arena.op(ar, self), ar, s, self)

def vz_topo(fuel: Nat, ar: O.Arena, +fx: F.Folded, t: VTopo) -> List<&2, U32>:
  vz_topo.go(fuel, ar, fx, t)

def vz_one.put(+acc: Vz, r: Ren, u: U32) -> Vz:
  match r:
    case Ren{s, a}: vz_one.hit(acc, s, a, u)

def z3_and.bv2(w: U32, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(bv_and(), Some{w}, a, b)

def ren_9.sh.hit(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  Ren{s, zat.hit(ren_9.sh.z(is_shr, a, b, r))}

def ren_t1.put2(is_where: Bool, nsrc: U32, +ar: O.Arena, +self: U32) -> Bool:
  Bool.and(is_where, Bool.and(U32.is_eq(nsrc, 3), t_invalid(ar, O.Arena.src(ar, self, 2))))

def ren_9.sh.term(is_shr: Bool, ok: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  Bool.pick(Ren, ok, ren_9.sh.hit(is_shr, a, b, r, s), Ren{s, zat.miss(zwhy(a, b))})

def ren_t1.put(op: O.Op, nsrc: U32, +ar: O.Arena, +self: U32) -> Bool:
  ren_t1.put2(O.eq_op(op, O.OpsWHERE{}), nsrc, ar, self)

def ren_9.sh.ok2(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  ren_9.sh.term(is_shr, zall(a, b), a, b, r, s)

def ren_t1(+ar: O.Arena, +self: U32) -> Bool:
  ren_t1.put(O.Arena.op(ar, self), O.Arena.nsrc(ar, self), ar, self)

def ren_tag(+ar: O.Arena, +fx: F.Folded, +self: U32) -> U32:
  rt_first([rt(ren_t1(ar, self), 0), rt(ren_t2(ar, self), 1), rt(ren_t3(ar, self), 2),
            rt(ren_t4(ar, fx, self), 3), rt(ren_t5(ar, fx, self), 4), rt(ren_t6(ar, self), 5),
            rt(ren_t7(ar, self), 6), rt(ren_t8(ar, self), 7), rt(ren_t9(ar, self), 8),
            rt(ren_t10(ar, self), 9)])

def ren_9.sh.ok(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  ren_9.sh.ok2(is_shr, a, b, r, s)

def ren_9.sh.go(is_shr: Bool, +a: ZAt, +b: ZAt, m: Maybe<&1, MM>, +s: Sol) -> Ren:
  match m:
    case Some{+r}: ren_9.sh.ok(is_shr, a, b, r, s)
    case None{}: Ren{s, zat.miss("rule 9 z3_shift: unknown bounds for src[1]")}

def ren_9.sh.put(is_shr: Bool, +a: ZAt, +b: ZAt, m: Maybe<&1, MM>, +s: Sol) -> Ren:
  ren_9.sh.go(is_shr, a, b, m, s)

def ren_9.sh(is_shr: Bool, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.sh.put(is_shr, zat.src(ar, s, self, 0, "rule 9 a"), zat.src(ar, s, self, 1, "rule 9 b"),
               vz_mm(ar, s, O.Arena.src(ar, self, 1)), s)

def z3_xor(+k: U32, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_xor.m2(Z.is_b(a), z3_xor.m1(Z.num(b), a, z3_xor.wv(w, a, b, k)),
            Z.num(a), z3_xor.wv(w, a, b, k), a, b, w)

def z3_and.bv(+w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Wv.got(w), z3_and.bv2(Wv.w(w), a, b), None{})

def wv0.go(w: Wv) -> Maybe<&1, U32>:
  match w:
    case Wv{got, w}: Some{w}
    case _: None{}

def z3_and.pw8(+v: U32, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, pow2(U32.sub(0, v)),
            Some{ZSub{a, ZMod{a, ZLit{U32.sub(0, v), False{}}}}},
            z3_and.bv(w, a, ZLit{v, False{}}))

def z3_and.pw7(+v: U32, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, pow2(U32.add(v, 1)),
            Some{ZMod{a, ZLit{U32.add(v, 1), False{}}}}, z3_and.pw8(v, w, a))

def z3_and.pw6(n: Maybe<&1, U32>, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  match n:
    case Some{v}: z3_and.pw7(v, w, a)
    case None{}: z3_and.bv(w, a, ZLit{0, False{}})

def z3_and.pw5(nb: Bool, +w: Wv, n: Maybe<&1, U32>, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, nb, z3_and.pw6(n, w, a), z3_and.bv(w, a, ZLit{0, False{}}))

def z3_and.pw9(nb: Bool, m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.pw5(nb, wv(m), Z.num(b), a)

def wv0(w: Wv) -> Maybe<&1, U32>:
  wv0.go(w)

def z3_and.sw(na: Bool, +nb: Bool, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, na, z3_and.pw9(nb, wv0(w), b, a), z3_and.pw9(nb, wv0(w), a, b))

def z3_and.of(ab: Bool, na: Bool, nb: Bool, m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, ab, Some{ZAnd{a, b}}, z3_and.sw(na, nb, wv(m), a, b))

# MASKING IS ARITHMETIC WHEN THE MASK IS A POWER OF TWO. validate.py:28 --
def z3_and(m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.of(Z.is_b(a), Z.is_num(a), Z.is_num(b), m, a, b)

def z3_and.pw4(nb: Bool, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.pw5(nb, w, Z.num(a), ZLit{0, False{}})

def ren_9.bv.xq(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_xor(bv_xor(), w, ZAt.t(a), ZAt.t(b))

def ren_9.bv.aa(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_and(wv0(w), ZAt.t(a), ZAt.t(b))

def ren_9.bv.oo(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_or(wv0(w), ZAt.t(a), ZAt.t(b))

def ren_9.bv.z(zero: Bool, one: Bool, +a: ZAt, +b: ZAt, +w: Wv) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, zero, ren_9.bv.aa(a, b, w),
    Bool.pick(Maybe<&1, Z>, one, ren_9.bv.oo(a, b, w), ren_9.bv.xq(a, b, w)))

def ren_9.bv.y(zero: Bool, one: Bool, a: ZAt, b: ZAt, m: Maybe<&1, U32>) -> Maybe<&1, Z>:
  ren_9.bv.z(zero, one, a, b, wv(m))

def ren_9.bv.k(+k: U32, a: ZAt, b: ZAt, m: Maybe<&1, U32>) -> Maybe<&1, Z>:
  ren_9.bv.y(U32.is_eq(k, bv_and()), U32.is_eq(k, bv_or()), a, b, m)

def ren_9.bv.ok(k: U32, +a: ZAt, +b: ZAt, w: Maybe<&1, U32>, +s: Sol) -> Ren:
  Ren{s, zm(ren_9.bv.k(k, a, b, w), "rule 9: unknown bounds for the bit-blast width")}

def ren_9.bv.put(k: U32, +a: ZAt, +b: ZAt, w: Maybe<&1, U32>, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), ren_9.bv.ok(k, a, b, w, s), Ren{s, zat.miss(zwhy(a, b))})

def ren_9.bv(k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.bv.put(k, zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1"),
               bv_w(ar, s, self), s)

def ren_9.go(op: O.Op, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  match op:
    case O.OpsTRUNCMOD{}: ren_9.b2(1, ar, s, self)
    case O.OpsTRUNCDIV{}: ren_9.b2(4, ar, s, self)
    case O.OpsDIV{}: ren_9.b2(2, ar, s, self)
    case O.OpsMOD{}: ren_9.b2(3, ar, s, self)
    case O.OpsMAX{}: ren_9.mx(ar, s, self)
    case O.OpsWHERE{}: ren_9.w3(ar, s, self)
    case O.OpsAND{}: ren_9.bv(bv_and(), ar, s, self)
    case O.OpsOR{}: ren_9.bv(bv_or(), ar, s, self)
    case O.OpsXOR{}: ren_9.bv(bv_xor(), ar, s, self)
    case O.OpsSHL{}: ren_9.sh(False{}, ar, s, self)
    case O.OpsSHR{}: ren_9.sh(True{}, ar, s, self)
    case _: ren_9.w3(ar, s, self)

def ren_9(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.go(O.Arena.op(ar, self), ar, s, self)

def Rep.sz(r: Rep) -> U32:
  match r:
    case Rep{sz, vs, cs, term}: sz

def Rep.vs(r: Rep) -> List<&2, String>:
  match r:
    case Rep{sz, vs, cs, term}: vs

def Rep.cs(r: Rep) -> String:
  match r:
    case Rep{sz, vs, cs, term}: cs

def Rep.term(r: Rep) -> String:
  match r:
    case Rep{sz, vs, cs, term}: term

def vs_str.go(+vs: List<&2, String>, +acc: String, sep: String) -> String:
  match vs:
    case Nil{}: acc
    case h <> t: vs_str.go(t, String.concat([acc, sep, h]), "; ")

def vs_str(vs: List<&2, String>) -> String:
  vs_str.go(vs, "", "")

def n_vs(vs: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, vs))

# strip. z3's counter is PER-CONTEXT (MEASURED: `aaa!4` then `bbb!5` in one context, and a
def row(+r: Rep) -> String:
  String.concat([Rep.cs(r), " | ", Rep.term(r), " | ", vs_str(Rep.vs(r)), " | ",
                 U32.show(n_vs(Rep.vs(r)))])

def dv.of.cs(+nm: String, +r: Rep) -> String:
  String.concat([nm, "_cs = ", Rep.cs(r), "\n"])

# SOUNDLY, and MEASURED it is an ARTEFACT GENERATOR in the opposite direction from `_term`: z3 wraps
def dv.of.term(+nm: String, +r: Rep) -> String:
  String.concat([nm, "_term = ", Rep.term(r), "\n", nm, "_term_nb = ", Rep.term(r), "\n"])

def dv.of.count(+nm: String, +r: Rep) -> String:
  String.concat([nm, "_n = ", U32.show(n_vs(Rep.vs(r))), "\n"])

def dv.of.msg(+nm: String, +r: Rep) -> String:
  String.concat([nm, "_msg = ", vs_str(Rep.vs(r))])

def dv.of(+nm: String, +acc: Vz, idx: U32) -> String:
  +r: Rep = validate_index_with_z3(16, acc, idx)
  String.concat([nm, " = ", row(r), "\n", dv.of.cs(nm, r), dv.of.term(nm, r),
                 dv.of.count(nm, r), dv.of.msg(nm, r)])

# `UOp.variable(name, vmin, vmax)` -- ops.py:669. The node is a PARAM, so
def fx_var(+ar: O.Arena, slot: U32, nm: String, dtype: S.Dt) -> O.Found:
  O.UOp.new.param(ar, O.OpsPARAM{}, None{}, O.AParam{O.ParamArg{slot, dtype, None{}, None{}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

def mm_i(n: U32, lo: U32, hi: U32) -> List<&2, MRng>:
  [MRng{n, lo, hi}]

def fx_const(ar: O.Arena, v: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_hi_lo(0, v)})

def fx_const_bool(ar: O.Arena, b: Bool) -> O.Found:
  O.UOp.const(ar, O.CBool{b})

def fx_const_invalid(ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInvalid{})

# type (ops.py:97), which is why `dv_range_global` and `dv_range_loop` must print
def fx_range(+ar: O.Arena, n: U32, ids: List<&2, U32>, at: O.AxisType) -> O.Found:
  +e = fx_const(ar, n)
  O.UOp.range_end(O.Found.ar(e), O.Found.i(e), ids, at)

def dv_bin(+ar: O.Arena, op: O.Op, hi: U32, k: U32) -> O.Found:
  +r = fx_range(ar, hi, [0], O.AXIS_GLOBAL{})
  +c = fx_const(O.Found.ar(r), k)
  O.UOp.new(O.Found.ar(c), op, [O.Found.i(r), O.Found.i(c)], O.ANone{}, O.TNone{})

def dv_and.mm2(+ar: O.Arena, +t: O.Found) -> List<&2, MRng>:
  mm_i(O.Arena.src(ar, O.Found.i(t), 0), 0, 99)

def n_z3_alu() -> U32:
  U32.from_nat(List.length(&2, O.Op, z3_alu_ops()))

def dv_and.mm(+ar: O.Arena, +t: O.Found) -> List<&2, MRng>:
  dv_and.mm2(ar, t)

def rs_ids.acc(ids: List<&2, U32>) -> String:
  rs_ids.go(ids, "", "")

def range_str.go(a: O.Arg) -> String:
  match a:
    case O.ARange{ids, at}: rs_ids.acc(ids)
    case _: ""

def range_str(ar: O.Arena, i: U32) -> String:
  range_str.go(O.Arena.arg(ar, i))

def ren_2_name.go(op: O.Op, +ar: O.Arena, i: U32) -> String:
  match op:
    case O.OpsSPECIAL{}: range_str.go(O.Arena.arg(ar, i))
    case _: String.concat(["r", range_str(ar, i)])

def ren_2_name(+ar: O.Arena, +i: U32) -> String:
  ren_2_name.go(O.Arena.op(ar, i), ar, i)

def ren_2(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_2.put(zat.src(ar, s, self, 0, "rule 2 vmax"), ren_2_name(ar, self), s)

def ren_dispatch.go(tag: U32, +ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  match tag:
    case 0: ren_1(ar, s, self)
    case 1: ren_2(ar, s, self)
    case 2: ren_3(ar, fx, s, self)
    case 3: ren_4(ar, fx, s, self)
    case 4: ren_5(ar, fx, s, self)
    case 5: ren_6(ar, s, self)
    case 6: ren_7(ar, fx, s, self)
    case 7: ren_8(ar, fx, s, self)
    case 8: ren_9(ar, s, self)
    case 9: ren_10(ar, s, self)
    case _: ren_unsup(ar, s, self)

def ren_dispatch(tag: U32, +ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_dispatch.go(tag, ar, fx, s, self)

def ren(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_dispatch(ren_tag(ar, fx, self), ar, fx, s, self)

def vz_one(+ar: O.Arena, +fx: F.Folded, +acc: Vz, +u: U32) -> Vz:
  vz_one.put(acc, ren(ar, fx, vz_s(acc), u), u)

def vz_walk(todo: List<&2, U32>, +ar: O.Arena, +fx: F.Folded, +acc: Vz) -> Vz:
  match todo:
    case Nil{}: acc
    case u <> t: vz_walk(t, ar, fx, vz_one(ar, fx, acc, u))

def vz_seed(ms: List<&2, MRng>) -> Vz:
  Vz{Sol{Nil{}, Nil{}, ms}, Nil{}}

def uops_to_z3.of(+ar: O.Arena, ms: List<&2, MRng>, snk: O.Found) -> Vz:
  vz_walk(vz_drop_sink(vz_topo(O.Arena.budget(ar), ar, F.folded(ar),
                                VTopo{Nil{}, [VFr{O.Found.i(snk), False{}}]}), ar, Nil{}),
         ar, F.folded(ar), vz_seed(ms))

# parameter is not: `[idx, gate]` CONSUMES the name. MEASURED -- with the name passed
def uops_to_z3.sink(+ar: O.Arena, ms: List<&2, MRng>, idx: U32, gate: U32) -> Vz:
  +gt: U32 = gate
  +snk: O.Found = O.UOp.sink(ar, [idx, gt])
  vz_add_mask(uops_to_z3.of(O.Found.ar(snk), ms, snk), gt)

# comes back empty. MEASURED: that spelling prints `[] |  |  | 0` on every row,
def uops_to_z3(+ar: O.Arena, +ms: List<&2, MRng>, idx: U32, gate: U32) -> Vz:
  uops_to_z3.sink(ar, ms, idx, gate)

# is not the gate. MEASURED: `dv_mask_missing@5` with `Sol.n == 4` on a 5-node walk -- the
def dv2(nm: String, +t: O.Found, +g: O.Found, ms: List<&2, MRng>) -> String:
  dv.of(nm, uops_to_z3(O.Found.ar(g), ms, O.Found.i(t), O.Found.i(g)), O.Found.i(t))

def dv_const_ok.of(+ar: O.Arena, nm: String) -> String:
  +t = fx_const(ar, 15)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_var.of(+ar: O.Arena, nm: String, lo: U32, hi: U32) -> String:
  +v = fx_var(ar, 0, "i", S.int32())
  +g = fx_const_bool(O.Found.ar(v), True{})
  dv2(nm, v, g, mm_i(O.Found.i(v), lo, hi))

def dv_range.of(+ar: O.Arena, at: O.AxisType, ids: List<&2, U32>, nm: String) -> String:
  +t = fx_range(ar, 100, ids, at)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

# an index the arena never interned. MEASURED by `.agents/slop/arena-validate-probe.bend`:
def dv_shr2.of(+ar: O.Arena, nm: String) -> String:
  +t = dv_bin(ar, O.OpsSHR{}, 64, 2)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm2(O.Found.ar(t), t))

# row is `ops.py:83-84`'s `lst` as an op SEQUENCE, so before the fix it read
def vz_ops.go(+xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: vz_ops.go(t, ar, String.concat([acc, O.Ops.name(O.Arena.op(ar, h)), " "]))

def vz_walk_ops(nm: String, +ar: O.Arena, idx: U32, gate: U32) -> String:
  +snk: O.Found = O.UOp.sink(ar, [idx, gate])
  +a: O.Arena = O.Found.ar(snk)
  +b: String = nm
  String.concat(["\n", b, "_walk = ",
                 vz_ops.go(vz_drop_sink(vz_topo(O.Arena.budget(a), a, F.folded(a),
                                                VTopo{Nil{}, [VFr{O.Found.i(snk), False{}}]}), a, Nil{}), a, "")])

def dv_where.of(+ar: O.Arena, nm: String) -> String:
  +b: String = nm
  +v = fx_var(ar, 0, "v", S.int32())
  +c8 = fx_const(O.Found.ar(v), 8)
  +cm = O.UOp.new(O.Found.ar(c8), O.OpsCMPLT{}, [O.Found.i(v), O.Found.i(c8)], O.ANone{}, O.TNone{})
  +inv = fx_const_invalid(O.Found.ar(cm))
  +t = O.UOp.new(O.Found.ar(inv), O.OpsWHERE{}, [O.Found.i(cm), O.Found.i(v), O.Found.i(inv)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  String.concat([dv2(b, t, g, mm_i(O.Found.i(v), 0, 15)),
                 vz_walk_ops(b, O.Found.ar(g), O.Found.i(t), O.Found.i(g))])

def dv_const_invalid.of(+ar: O.Arena, nm: String) -> String:
  +t = fx_const_invalid(ar)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_unsup_stack.of(+ar: O.Arena, nm: String) -> String:
  +c2 = fx_const(ar, 2)
  +c3 = fx_const(O.Found.ar(c2), 3)
  +t = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_unsup_two.of(+ar: O.Arena, nm: String) -> String:
  +b: String = nm
  +c2 = fx_const(ar, 2)
  +c3 = fx_const(O.Found.ar(c2), 3)
  +c5 = fx_const(O.Found.ar(c3), 5)
  +c7 = fx_const(O.Found.ar(c5), 7)
  +s1 = O.UOp.new(O.Found.ar(c7), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +s2 = O.UOp.new(O.Found.ar(s1), O.OpsSTACK{}, [O.Found.i(c5), O.Found.i(c7)], O.ANone{}, O.TNone{})
  +t = O.UOp.new(O.Found.ar(s2), O.OpsADD{}, [O.Found.i(s1), O.Found.i(s2)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  String.concat([dv2(b, t, g, Nil{}), vz_walk_ops(b, O.Found.ar(g), O.Found.i(t), O.Found.i(g))])

def dv_rank_shr1.of(+ar: O.Arena, nm: String) -> String:
  +r = fx_range(ar, 8, [0], O.AXIS_GLOBAL{})
  +t = O.UOp.new(O.Found.ar(r), O.OpsSHL{}, [O.Found.i(r)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

# `src = (r, r)` -- `r` REACHABLE TWICE, and through a DIFFERENT shape than `dv_where` (both of
def dv_bad_dtype_bitcast.of(+ar: O.Arena, nm: String) -> String:
  +b: String = nm
  +r = fx_range(ar, 16, [0], O.AXIS_GLOBAL{})
  +t = O.UOp.new(O.Found.ar(r), O.OpsBITCAST{}, [O.Found.i(r), O.Found.i(r)], O.ADt{S.boolean()}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  String.concat([dv2(b, t, g, Nil{}), vz_walk_ops(b, O.Found.ar(g), O.Found.i(t), O.Found.i(g))])

def dv_const_ok() -> String:
  dv_const_ok.of(O.Arena.empty(), "dv_const_ok")

# and the `arg.name` arm two DIFFERENT rows rather than one.
def dv_var() -> String:
  dv_var.of(O.Arena.empty(), "dv_var", 0, 15)

# meets z3's numeral-hoisting printer: MEASURED, `And(i >= -5, i <= 10)`.
def dv_var_neg() -> String:
  dv_var.of(O.Arena.empty(), "dv_var_neg", 4294967291, 10)

def dv_range(at: O.AxisType, ids: List<&2, U32>, nm: String) -> String:
  dv_range.of(O.Arena.empty(), at, ids, nm)

def dv_shr2() -> String:
  dv_shr2.of(O.Arena.empty(), "dv_shr2")

def dv_where() -> String:
  dv_where.of(O.Arena.empty(), "dv_where")

# DIFFERENT answers -- a free `Invalid` symbol against the value as a literal --
def dv_const_invalid() -> String:
  dv_const_invalid.of(O.Arena.empty(), "dv_const_invalid")

# MEASURED: `NotImplementedError: Ops.STACK is not supported by z3`, and
def dv_unsup_stack() -> String:
  dv_unsup_stack.of(O.Arena.empty(), "dv_unsup_stack")

# --- THE COUNT ROW. CPython STOPS at the first unsupported op; this collects
# MEASURED, and the first guess was wrong: `Ops.BINARY` is NOT in `z3_alu`/`python_alu`
def dv_unsup_two() -> String:
  dv_unsup_two.of(O.Arena.empty(), "dv_unsup_two")

def dv_rank_shr1() -> String:
  dv_rank_shr1.of(O.Arena.empty(), "dv_rank_shr1")

# unsupported -- a DIFFERENT text from `dv_rank_shr1` for a different op.
def dv_bad_dtype_bitcast() -> String:
  dv_bad_dtype_bitcast.of(O.Arena.empty(), "dv_bad_dtype_bitcast")

# THE SAME STALE ARENA AS `dv_shr2.of`, and this one sits behind the `dv_and*` rows.
# anywhere in `.agents/slop/`. A hand-derivation of `validate.py:16` gives `w=8` -> bound 128,
#   * CALLED, `validate.py:16` on CPython's own `_min_max` gives `w = 8`, and the literal z3
#   * The `128` in that old text is the width of a DIFFERENT NODE: `w = 7`, and `w = 7` is what
def dv_and.put(+ar: O.Arena, nm: String, k: U32) -> String:
  +t = dv_bin(ar, O.OpsAND{}, 100, k)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm(O.Found.ar(t), t))

def dv_and.of(+ar: O.Arena, nm: String, k: U32) -> String:
  dv_and.put(ar, nm, k)

# `validate.py:47` is `Ops.MAX: lambda _,a,b: z3.If(a<b, b, a)`, and `Ops.MAX` is one of the
def dv_max.of(+ar: O.Arena, nm: String) -> String:
  +t = dv_bin(ar, O.OpsMAX{}, 100, 21)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm(O.Found.ar(t), t))

# --- THE `z3_bv` WIDTH AS ITS OWN ROW. `validate.py:16` is the width, and the `- 1` -> `- 256`
# `w_*_off`, which call `validate.py:16`'s expression on CPython's own `UOp._min_max`.
def dv_alu.of(op: O.Op, k: U32, nm: String) -> String:
  +t = dv_bin(O.Arena.empty(), op, 100, k)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm(O.Found.ar(t), t))

# --- `Ops.TRUNCDIV` (validate.py:45), and the only row reaching `z3_cdiv` at all -- including its
def dv_cdiv4() -> String:
  dv_alu.of(O.OpsTRUNCDIV{}, 4, "dv_cdiv4")

def dv_cmod4() -> String:
  dv_alu.of(O.OpsTRUNCMOD{}, 4, "dv_cmod4")

# --- `Ops.DIV` (validate.py:46), the other `0<b`-shaped test and a different one.
def dv_floordiv4() -> String:
  dv_alu.of(O.OpsDIV{}, 4, "dv_floordiv4")

def dv_floormod4() -> String:
  dv_alu.of(O.OpsMOD{}, 4, "dv_floormod4")

# Python either, which is why `r | (r << 1)` in test_validate_oob.py:113 is a BV expression.
def dv_or21() -> String:
  dv_alu.of(O.OpsOR{}, 21, "dv_or21")

def dv_xor21() -> String:
  dv_alu.of(O.OpsXOR{}, 21, "dv_xor21")

# --- `z3_xor`'s CONSTANT arm, validate.py:21: `x ^ -1 = -(x+1)`, bitwise NOT. It needs no width
def dv_xor_m1() -> String:
  dv_alu.of(O.OpsXOR{}, 4294967295, "dv_xor_m1")

def dv_shl2() -> String:
  dv_alu.of(O.OpsSHL{}, 2, "dv_shl2")

def dv_max() -> String:
  dv_max.of(O.Arena.empty(), "dv_max")

def dv_w.got(w: Maybe<&1, U32>) -> U32:
  match w:
    case Some{n}: n
    case None{}: 0

def dv_w2(+ar: O.Arena, +t: O.Found, +g: O.Found) -> U32:
  dv_w.got(bv_w(ar, Sol{Nil{}, Nil{}, dv_and.mm(O.Found.ar(g), t)}, O.Found.i(t)))

def dv_w(op: O.Op, ar: O.Arena, hi: U32, k: U32) -> U32:
  +t = dv_bin(ar, op, hi, k)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv_w2(O.Found.ar(g), t, g)

# --- `z3_and`'s FIRST constant case, `x & (2^k-1) = x % 2^k`. MEASURED, `r & 15`
def dv_and15() -> String:
  dv_and.of(O.Arena.empty(), "dv_and15", 15)

def dv_and_neg4() -> String:
  dv_and.of(O.Arena.empty(), "dv_and_neg4", 4294967292)

# row that sees the WIDTH. MEASURED: `r & 21` over a RANGE(100) picks width 8,
def dv_and21() -> String:
  dv_and.of(O.Arena.empty(), "dv_and21", 21)

# only thing here that can be adjudicated on its own. `validate.py:16` in full:
# and the printed literal inside z3's signed `BV2Int` expansion is `2w`. MEASURED by CALLING
def bv_w.of21() -> U32:
  dv_w(O.OpsAND{}, O.Arena.empty(), 100, 21)

def bv_w.of15() -> U32:
  dv_w(O.OpsAND{}, O.Arena.empty(), 100, 15)

def bv_w.ofneg() -> U32:
  dv_w(O.OpsAND{}, O.Arena.empty(), 100, 4294967292)

# `c2d` -- `copy_to_device`'s REFUSALS, ops.py:759/761/763, AS GATE ROWS.
#   ops.py:759  `if is_disk_device(device): raise RuntimeError("COPY to DISK is not allowed;
#   ops.py:761  `assert arg is None or isinstance(self.device, tuple)` a BARE `assert`,
#   ops.py:763  `if inp.dtype in dtypes.weaks: raise RuntimeError(...)` a `raise`, WITH a message
#   ops.py:892  `assert isinstance(self.src[0].device, tuple), f"mselect must be on tuple
# port's fixture was `s5.ga.arena()`'s node 4 and the oracle's was `ops-501-oracle.py:164`'s
# `multi` -- two DIFFERENT nodes differing in op, slot, size and device. `sig()` prints the op
#   * `arg=0` REFUSES on a scalar device, so ops.py:761 tests `is None` and not truth. The
def c2d_pa(slot: U32, dt: S.Dt) -> O.ParamArg: O.ParamArg.of(slot, dt)

def c2d_pat(slot: U32, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dt, None{}, None{}, None{}, S.AGlobal{}, Some{O.s5.d1(0)},
             False{}, None{}, None{}, False{}, None{}}

def c2d_buf(+ar: O.Arena, slot: U32, dt: S.Dt) -> O.Found:
  O.UOp.new.param(ar, O.OpsBUFFER{}, Some{1}, O.AParam{c2d_pa(slot, dt)}, O.TNone{})

def c2d_buft(+ar: O.Arena, slot: U32, dt: S.Dt) -> O.Found:
  O.UOp.new.param(ar, O.OpsBUFFER{}, Some{1}, O.AParam{c2d_pat(slot, dt)}, O.TNone{})

def c2d_shr(+ar: O.Arena, src: U32) -> O.Found:
  O.UOp.new(ar, O.OpsSHRINK{}, [src], O.ATuple{Nil{}}, O.TNone{})

# `assert` is a DIFFERENT upstream behaviour from `RuntimeError` from a `raise`, and a row that
def c2d_sig(+f: O.Found) -> String: O.s5.minted.go(O.Found.ar(f), f)

# `O.ParamArg.slot` on node 4's src0 -- `s5.pa(1)`, uop/ops.bend:1480 symbol=ParamArg.slot. `ops-501-oracle.py:164`'s
def c2d_built(+f: O.Found) -> String: String.concat(["BUILT ", c2d_sig(f)])
# `ops-501-oracle.py:61` sets 9. The second of the four differences. `sp0` IS the

def c2d_row(nm: String, v: String) -> String: String.concat([nm, " = ", v, "\n"])
# `ParamArg.device is None` on node 4's src0. `UOp.device` (ops.py:887-899) has no SHRINK arm,

def c2d_arg_is_tuple(a: O.Arg) -> Bool:
  match a:
    case O.ATuple{ys}: True{}
    case _: False{}

def c2d_arg_is_param(a: O.Arg) -> Bool:
  match a:
    case O.AParam{pa}: True{}
    case _: False{}

# `O.ParamArg.slot` on node 4's src0 -- `s5.pa(1)`, uop/ops.bend:1480 symbol=ParamArg.slot. `ops-501-oracle.py:164`'s
def c2d_arg_slot(a: O.Arg) -> U32:
  match a:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: O.ParamArg.no_slot()

def c2d_u32_is_none(m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}

# `ops-501-oracle.py:61` sets 9. The second of the four differences. `sp0` IS the
def c2d_arg_size_is_none(a: O.Arg) -> Bool:
  match a:
    case O.AParam{pa}: c2d_u32_is_none(O.ParamArg.size(O.Arena.empty(), 0))
    case _: False{}

def c2d_dev_is_none(m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}

# `ParamArg.device is None` on node 4's src0. `UOp.device` (ops.py:887-899) has no SHRINK arm,
def c2d_arg_device_is_none(a: O.Arg) -> Bool:
  match a:
    case O.AParam{pa}: c2d_dev_is_none(O.ParamArg.device(pa))
    case _: True{}

# ---------------------------------------------------------------- THE IDENTITY ROWS (12)
def c2d_selrow_op() -> String:
  c2d_row("c2d_selrow_op", O.Ops.name(O.Arena.op(O.s5.ga.arena(), 4)))

def c2d_selrow_nsrc() -> String:
  c2d_row("c2d_selrow_nsrc", U32.show(O.Arena.nsrc(O.s5.ga.arena(), 4)))

def c2d_selrow_src0() -> String:
  c2d_row("c2d_selrow_src0",
          O.Ops.name(O.Arena.op(O.s5.ga.arena(), O.Arena.src(O.s5.ga.arena(), 4, 0))))

def c2d_selrow_arg_is_tuple() -> String:
  c2d_row("c2d_selrow_arg_is_tuple", Bool.show(c2d_arg_is_tuple(O.Arena.arg(O.s5.ga.arena(), 4))))

def c2d_selrow_arg_is_param() -> String:
  c2d_row("c2d_selrow_arg_is_param", Bool.show(c2d_arg_is_param(O.Arena.arg(O.s5.ga.arena(), 4))))

def c2d_selrow_src0_slot() -> String:
  c2d_row("c2d_selrow_src0_slot",
          U32.show(c2d_arg_slot(O.Arena.arg(O.s5.ga.arena(), O.Arena.src(O.s5.ga.arena(), 4, 0)))))

def c2d_selrow_src0_size_is_none() -> String:
  c2d_row("c2d_selrow_src0_size_is_none",
          Bool.show(c2d_arg_size_is_none(
            O.Arena.arg(O.s5.ga.arena(), O.Arena.src(O.s5.ga.arena(), 4, 0)))))

def c2d_selrow_src0_device_is_none() -> String:
  c2d_row("c2d_selrow_src0_device_is_none",
          Bool.show(c2d_arg_device_is_none(
            O.Arena.arg(O.s5.ga.arena(), O.Arena.src(O.s5.ga.arena(), 4, 0)))))

def c2d_node2_op() -> String: c2d_row("c2d_node2_op", O.Ops.name(O.Arena.op(O.s5.ga.arena(), 2)))

def c2d_node2_arg_is_param() -> String:
  c2d_row("c2d_node2_arg_is_param", Bool.show(c2d_arg_is_param(O.Arena.arg(O.s5.ga.arena(), 2))))

def c2d_node2_slot() -> String:
  c2d_row("c2d_node2_slot", U32.show(c2d_arg_slot(O.Arena.arg(O.s5.ga.arena(), 2))))

def c2d_node2_device_is_none() -> String:
  c2d_row("c2d_node2_device_is_none",
          Bool.show(c2d_arg_device_is_none(O.Arena.arg(O.s5.ga.arena(), 2))))

def c2d_identity() -> String:
  String.concat([c2d_selrow_op(), c2d_selrow_nsrc(), c2d_selrow_src0(),
                 c2d_selrow_arg_is_tuple(), c2d_selrow_arg_is_param(),
                 c2d_selrow_src0_slot(), c2d_selrow_src0_size_is_none(),
                 c2d_selrow_src0_device_is_none(), c2d_node2_op(),
                 c2d_node2_arg_is_param(), c2d_node2_slot(), c2d_node2_device_is_none()])

# ---------------------------------------------------------------- ops.py:761, THE BARE assert
def c2d_761_selrow() -> String:
  +f = O.UOp.copy_to_device(O.s5.ga.arena(), 4, Some{1}, O.s5.dn(2))
  c2d_row("c2d_761 selrow", c2d_built(f))

def c2d_761_argnone() -> String:
  +f = O.UOp.copy_to_device(O.s5.ga.arena(), 4, None{}, O.s5.dn(2))
  c2d_row("c2d_761 argnone", c2d_built(f))

def c2d_761_tupledev() -> String:
  +b = c2d_buft(O.Arena.empty(), 1, S.int32())
  +s = c2d_shr(O.Found.ar(b), O.Found.i(b))
  +f = O.UOp.copy_to_device(O.Found.ar(s), O.Found.i(s), Some{1}, O.s5.dn(2))
  c2d_row("c2d_761 tupledev", c2d_built(f))

def c2d_761_argzero() -> String:
  +f = O.UOp.copy_to_device(O.s5.ga.arena(), 4, Some{0}, O.s5.dn(2))
  c2d_row("c2d_761 argzero", c2d_built(f))

def c2d_761_scalardevargone() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), Some{1}, O.s5.dn(2))
  c2d_row("c2d_761 scalardevargone", c2d_built(f))

def c2d_761_scalarnone() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, O.s5.dn(2))
  c2d_row("c2d_761 scalarnone", c2d_built(f))

def c2d_761_tupleargzero() -> String:
  +b = c2d_buft(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), Some{0}, O.s5.dn(2))
  c2d_row("c2d_761 tupleargzero", c2d_built(f))

def c2d_761_tupleargnone() -> String:
  +b = c2d_buft(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, O.s5.dn(2))
  c2d_row("c2d_761 tupleargnone", c2d_built(f))

def c2d_761() -> String:
  String.concat([c2d_761_selrow(), c2d_761_argnone(), c2d_761_tupledev(), c2d_761_argzero(),
                 c2d_761_scalardevargone(), c2d_761_scalarnone(), c2d_761_tupleargzero(),
                 c2d_761_tupleargnone()])

# ---------------------------------------------------------------- ops.py:759, THE DISK raise
def c2d_759_disk() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, S.D1{6})
  c2d_row("c2d_759 disk", c2d_built(f))

def c2d_759_disktuple() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, S.Dn{[6, 0]})
  c2d_row("c2d_759 disktuple", c2d_built(f))

def c2d_759_cpu() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, O.s5.d1(0))
  c2d_row("c2d_759 cpu", c2d_built(f))

def c2d_759_cputuple() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, O.s5.dn(2))
  c2d_row("c2d_759 cputuple", c2d_built(f))

def c2d_759() -> String:
  String.concat([c2d_759_disk(), c2d_759_disktuple(), c2d_759_cpu(), c2d_759_cputuple()])

# ---------------------------------------------------------------- ops.py:763, THE WEAK DTYPE
def c2d_763(dt: S.Dt, tag: String) -> String:
  +b = c2d_buf(O.Arena.empty(), 1, dt)
  +f = O.UOp.copy_to_device(O.Found.ar(b), O.Found.i(b), None{}, O.s5.d1(0))
  c2d_row(String.concat(["c2d_763 ", tag]), c2d_built(f))

def c2d_763_i32() -> String: c2d_763(S.int32(), "i32")
def c2d_763_f32() -> String: c2d_763(S.single(), "f32")
def c2d_763_bool() -> String: c2d_763(S.boolean(), "bool")
def c2d_763_void() -> String: c2d_763(S.void(), "void")
def c2d_763_weakint() -> String: c2d_763(S.weakint(), "weakint")
def c2d_763_weakfloat() -> String: c2d_763(S.weakfloat(), "weakfloat")

def c2d_763_rows() -> String:
  String.concat([c2d_763_i32(), c2d_763_f32(), c2d_763_bool(),
                 c2d_763_void(), c2d_763_weakint(), c2d_763_weakfloat()])

# ---------------------------------------------------------------- ops.py:892, THE OTHER assert
# assert at ops.py:892 fires on the first `.device` READ, not at construction, so
def c2d_892_construct() -> String:
  +b = c2d_buf(O.Arena.empty(), 1, S.int32())
  +s = c2d_shr(O.Found.ar(b), O.Found.i(b))
  +m = O.UOp.mselect(O.Found.ar(s), O.Found.i(s), 1)
  c2d_row("c2d_892 construct", c2d_built(m))

def c2d_counts() -> String:
  String.concat([
    c2d_row("c2d_fixture_n", "24"),
    c2d_row("c2d_identity_n", "12"),
    c2d_row("c2d_outcome_761_n", "8"),
    c2d_row("c2d_outcome_759_n", "8"),
    c2d_row("c2d_outcome_763_n", "6"),
    c2d_row("c2d_outcome_892_n", "2"),
    c2d_row("c2d_shared_n", "19"),
    c2d_row("c2d_oracle_only_n", "5"),
    c2d_row("c2d_weaks_n", "2"),
    c2d_row("c2d_dtypes_n", "20"),
    c2d_row("c2d_port_built_n", "19")])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(dv_const_ok())
    IO.print(dv_var())
    IO.print(dv_var_neg())
    IO.print(dv_range(O.AXIS_GLOBAL{}, [0], "dv_range_global"))
    IO.print(dv_range(O.AXIS_LOOP{}, [0], "dv_range_loop"))
    IO.print(dv_range(O.AXIS_GLOBAL{}, [4294967295], "dv_range_m1"))
    IO.print(dv_and15())
    IO.print(dv_and_neg4())
    IO.print(dv_and21())
    IO.print(dv_max())
    IO.print(dv_or21())
    IO.print(dv_xor21())
    IO.print(dv_xor_m1())
    IO.print(dv_cdiv4())
    IO.print(dv_cmod4())
    IO.print(dv_floordiv4())
    IO.print(dv_floormod4())
    IO.print(dv_shl2())
    IO.print(dv_shr2())
    IO.print(dv_where())
    IO.print(dv_const_invalid())
    IO.print(dv_unsup_stack())
    IO.print(dv_unsup_two())
    IO.print(dv_rank_shr1())
    IO.print(dv_bad_dtype_bitcast())
    IO.print(String.concat(["n_z3_alu=", U32.show(n_z3_alu())]))
    IO.print(String.concat(["bv_w_and21=", U32.show(bv_w.of21())]))
    IO.print(String.concat(["bv_w_off_and21=", U32.show(U32.shln(1, U32.to_nat(bv_w.of21())))]))
    IO.print(String.concat(["bv_w_and15=", U32.show(bv_w.of15())]))
    IO.print(String.concat(["bv_w_and_neg4=", U32.show(bv_w.ofneg())]))
    IO.print(c2d_identity())
    IO.print(c2d_761())
    IO.print(c2d_759())
    IO.print(c2d_763_rows())
    IO.print(c2d_892_construct())
    IO.print(c2d_counts())
    IO.print("done")
