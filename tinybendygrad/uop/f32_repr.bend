# f32_repr.bend -- `repr(float)` FOR AN F32, COMPUTED EXACTLY.

# cstyle.py:27 is `f"{c.val}f"`, i.e. `repr`, so the two disagree on the bytes of a rendered
# constant. MEASURED on `exp(x)`, whose multiplier is log2e:
#     bottom of the f64's 52. MEASURED: 3.598600411231027e16 is exactly the bound and CPython

import Base
import ./../helpers.bend as H


def i64u(+x: U32) -> H.I64: H.i64_of_i32(x)
def i64n(+n: U32) -> H.I64: H.i64_neg(True{}, H.i64_of_i32(n))

def nat_of64(+x: H.I64) -> Nat: U32.to_nat(H.lo32(x))


def ds_of.go(s: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}: acc
    case SCon{h, t}: ds_of.go(t, U32.sub(Char.to_u32(h), 48) <> acc)

def ds_of(+s: String) -> List<&2, U32>: List.reverse(&2, U32, ds_of.go(s, Nil{}))

def ds_str.go(ds: List<&2, U32>, +acc: List<&2, Char>) -> List<&2, Char>:
  match ds:
    case Nil{}: acc
    case h <> t: ds_str.go(t, Char.from_u32(U32.add(48, h)) <> acc)

def ds_str(+ds: List<&2, U32>) -> String:
  String.from_list(List.reverse(&2, Char, ds_str.go(ds, Nil{})))


def big_mul.put(z: Bool, +c: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match z:
    case True{}: acc
    case False{}: c <> acc

def big_mul.go(ds: List<&2, U32>, +k: U32, +c: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}: big_mul.put(U32.is_zero(c), c, acc)
    case h <> t:
      +v = U32.add(U32.mul(h, k), c)
      big_mul.go(t, k, U32.div(v, 10), U32.mod(v, 10) <> acc)

def big_mul(+k: U32, +ds: List<&2, U32>) -> List<&2, U32>:
  big_mul.go(List.reverse(&2, U32, ds), k, 0, Nil{})

def big_n(+k: U32, +f: Nat, +ds: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: ds
    case 1n+g: big_n(k, g, big_mul(k, ds))

def add1.end(z: Bool) -> List<&2, U32>:
  match z:
    case True{}: Nil{}
    case False{}: [1]

def add1.go(ds: List<&2, U32>, +carry: U32) -> List<&2, U32>:
  match ds:
    case Nil{}: add1.end(U32.is_zero(carry))
    case h <> t:
      +v = U32.add(h, carry)
      U32.mod(v, 10) <> add1.go(t, U32.div(v, 10))

def big_add1(+ds: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, add1.go(List.reverse(&2, U32, ds), 1))

def sub1.go(ds: List<&2, U32>, +brw: U32) -> List<&2, U32>:
  match ds:
    case Nil{}: Nil{}
    case h <> t:
      +v = U32.sub(U32.add(h, 10), brw)
      U32.mod(v, 10) <> sub1.go(t, U32.sub(1, U32.div(v, 10)))

def big_sub1(+ds: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, sub1.go(List.reverse(&2, U32, ds), 1))

def blen.go(f: Nat, +x: U32, +n: U32) -> U32:
  match f:
    case 0n: n
    case 1n+g: blen.go(g, U32.shrn(x, 1n), U32.add(n, Bool.pick(U32, U32.is_zero(x), 0, 1)))

def blen(+x: U32) -> U32: blen.go(32n, x, 0)

def is_pow2(+m: U32) -> Bool:
  U32.is_eq(m, U32.shln(1, Nat.sub(U32.to_nat(blen(m)), 1n)))


type Scaled is Data:
  Scaled{+dg: List<&2, U32>, +ex: H.I64}

def scale.go(neg: Bool, +ds: List<&2, U32>, +t: H.I64) -> Scaled:
  match neg:
    case True{}: Scaled{big_n(5, nat_of64(H.i64_neg(True{}, t)), ds), t}
    case False{}: Scaled{big_n(2, nat_of64(t), ds), i64u(0)}

def scale(+ds: List<&2, U32>, +t: H.I64) -> Scaled:
  scale.go(H.i64_is_neg(t), ds, t)

def dec2(+m: U32, +e: H.I64) -> Scaled:
  scale(ds_of(U32.show(m)), e)


def bound.num(+plus: Bool, +num: List<&2, U32>) -> List<&2, U32>:
  match plus:
    case True{}: big_add1(num)
    case False{}: big_sub1(num)

def bound.step.go(pw: Bool) -> U32:
  match pw:
    case True{}: 55
    case False{}: 54

def bound.step(+m: U32) -> U32: bound.step.go(is_pow2(m))

def bound.scale(+plus: Bool, +num: List<&2, U32>, +t: H.I64) -> Scaled:
  scale(num, t)

def bound(+m: U32, +e: H.I64, +plus: Bool, +step: U32) -> Scaled:
  +b = blen(m)
  +num = big_n(2, U32.to_nat(U32.sub(step, b)), ds_of(U32.show(m)))
  bound.scale(plus, bound.num(plus, num), H.i64_sub(H.i64_add(e, i64u(b)), i64u(step)))


def shead(+s: String) -> Char:
  match s:
    case SNil{}: '0'
    case SCon{h, t}: h

def stail(+s: String) -> String:
  match s:
    case SNil{}: SNil{}
    case SCon{h, t}: t

def all0.go(+s: String, +acc: Bool) -> Bool:
  match s:
    case SNil{}: acc
    case SCon{h, t}: all0.go(t, Bool.and(acc, U32.is_eq(Char.to_u32(h), 48)))

def all0(+s: String) -> Bool: all0.go(s, True{})

def last_dig.go(+s: String, +acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{h, t}: last_dig.go(t, U32.sub(Char.to_u32(h), 48))

def last_dig(+s: String) -> U32: last_dig.go(s, 0)

def pad_n(+s: String, +n: Nat) -> String: String.append(s, String.repeat("0", n))

def pad_a(lt: Bool, +a: String, +b: String) -> String:
  match lt:
    case True{}: pad_n(a, Nat.sub(String.length(b), String.length(a)))
    case False{}: a

def keep(+acc: Cmp, c: Cmp) -> Cmp:
  match acc:
    case EQ{}: c
    case _: acc

def str_cmp.go(+a: String, +b: String, +acc: Cmp) -> Cmp:
  match a b:
    case SNil{} SNil{}: acc
    case SNil{} SCon{h, t}: keep(acc, LT{})
    case SCon{h, t} SNil{}: keep(acc, GT{})
    case SCon{ha, ta} SCon{hb, tb}:
      str_cmp.go(ta, tb, keep(acc, U32.cmp(Char.to_u32(ha), Char.to_u32(hb))))

def str_cmp(+a: String, +b: String) -> Cmp: str_cmp.go(a, b, EQ{})

def dec_pos(+s: String, +e: H.I64) -> H.I64:
  H.i64_add(i64u(U32.from_nat(String.length(s))), e)

def dec_cmp.ord(h: Cmp, +a: String, +b: String) -> Cmp:
  match h:
    case LT{}: LT{}
    case GT{}: GT{}
    case EQ{}: str_cmp(pad_a(Nat.is_lt(String.length(a), String.length(b)), a, b),
      pad_a(Nat.is_lt(String.length(b), String.length(a)), b, a))

def dec_cmp(+a: String, +ae: H.I64, +b: String, +be: H.I64) -> Cmp:
  dec_cmp.ord(H.i64_cmp(dec_pos(a, ae), dec_pos(b, be)), a, b)


def dp_of(+d: String, +e: H.I64) -> H.I64:
  H.i64_add(e, i64u(U32.from_nat(String.length(d))))

def fmt.fixed(+dp: H.I64) -> Bool:
  Bool.and(H.i64_le(i64n(3), dp), H.i64_le(dp, i64u(16)))

def fmt.sci.exp.put(pad: Bool, +s: String) -> String:
  match pad:
    case True{}: String.concat(["0", s])
    case False{}: s

def fmt.sci.exp(+n: Nat) -> String: fmt.sci.exp.put(Nat.is_lt(n, 10n), Nat.show(n))

def fmt.sci.dot(gt: Bool, +d: String) -> String:
  match gt:
    case True{}: String.concat([".", String.drop(d, 1n)])
    case False{}: ""

def fmt.sci.sign(neg: Bool) -> String:
  match neg:
    case True{}: "-"
    case False{}: "+"

def fmt.sci(+d: String, +dp: H.I64) -> String:
  +ex = H.i64_sub(dp, i64u(1))
  String.concat([String.take(d, 1n), fmt.sci.dot(Nat.is_le(2n, String.length(d)), d),
    "e", fmt.sci.sign(H.i64_is_neg(ex)), fmt.sci.exp(nat_of64(H.i64_abs(ex)))])

def fmt_fix.ge(ge: Bool, +d: String, +dp: H.I64) -> String:
  match ge:
    case True{}: String.concat([d, String.repeat("0", Nat.sub(nat_of64(dp), String.length(d))), ".0"])
    case False{}: String.concat([String.take(d, nat_of64(dp)), ".", String.drop(d, nat_of64(dp))])

def fmt_fix.le(le: Bool, +d: String, +dp: H.I64) -> String:
  match le:
    case True{}: String.concat(["0.", String.repeat("0", nat_of64(H.i64_neg(True{}, dp))), d])
    case False{}: fmt_fix.ge(Nat.is_le(String.length(d), nat_of64(dp)), d, dp)

def fmt.go(fixed: Bool, +d: String, +dp: H.I64) -> String:
  match fixed:
    case True{}: fmt_fix.le(H.i64_le(dp, i64u(0)), d, dp)
    case False{}: fmt.sci(d, dp)

def fmt(+d: String, +e: H.I64) -> String:
  +dp = dp_of(d, e)
  fmt.go(fmt.fixed(dp), d, dp)


type Ctx is Data:
  Ctx{+d: String, +e: H.I64, +lo: String, +le: H.I64, +hi: String, +he: H.I64, +neg: Bool}

def Ctx.d(c: Ctx) -> String:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: d

def Ctx.e(c: Ctx) -> H.I64:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: e

def Ctx.lo(c: Ctx) -> String:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: lo

def Ctx.le(c: Ctx) -> H.I64:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: le

def Ctx.hi(c: Ctx) -> String:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: hi

def Ctx.he(c: Ctx) -> H.I64:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: he

def Ctx.neg(c: Ctx) -> Bool:
  match c:
    case Ctx{d, e, lo, le, hi, he, neg}: neg

def sign_of.go(neg: Bool) -> String:
  match neg:
    case True{}: "-"
    case False{}: ""

def sign_of(+c: Ctx) -> String: sign_of.go(Ctx.neg(c))

def not_lt(c: Cmp) -> Bool:
  match c:
    case LT{}: False{}
    case _: True{}

def not_gt(c: Cmp) -> Bool:
  match c:
    case GT{}: False{}
    case _: True{}

def inside(+d: String, +e: H.I64, +c: Ctx) -> Bool:
  Bool.and(not_lt(dec_cmp(d, e, Ctx.lo(c), Ctx.le(c))),
    not_gt(dec_cmp(d, e, Ctx.hi(c), Ctx.he(c))))

def pick_one.go(ok: Bool, +d: String, +e: H.I64, +c: Ctx) -> Maybe<&2, String>:
  match ok:
    case True{}: Some{String.concat([sign_of(c), fmt(d, e)])}
    case False{}: None{}

def pick_one(+d: String, +e: H.I64, +c: Ctx) -> Maybe<&2, String>:
  pick_one.go(inside(d, e, c), d, e, c)

def inc_head(+h: String) -> String: ds_str(big_add1(ds_of(h)))

def cut(+up: String, +p: Nat) -> String: String.take(up, p)

def cut_e(carried: Bool, +ce: H.I64) -> H.I64:
  match carried:
    case True{}: H.i64_add(ce, i64u(1))
    case False{}: ce

def pref.eq(tie: Bool, +last: U32) -> Bool:
  match tie:
    case False{}: True{}
    case True{}: U32.is_eq(U32.mod(last, 2), 1)

def pref.go(c: Cmp, tie: Bool, +last: U32) -> Bool:
  match c:
    case GT{}: True{}
    case LT{}: False{}
    case EQ{}: pref.eq(tie, last)

def pref(+r: String, +h: String) -> Bool:
  pref.go(U32.cmp(U32.sub(Char.to_u32(shead(r)), 48), 5), all0(stail(r)), last_dig(h))

def step.two1(m: Maybe<&2, String>, +h: String, +ce: H.I64, +c: Ctx) -> Maybe<&2, String>:
  match m:
    case Some{x}: Some{x}
    case None{}: pick_one(h, ce, c)

def step.two2(m: Maybe<&2, String>, +upd: String, +upe: H.I64, +c: Ctx) -> Maybe<&2, String>:
  match m:
    case Some{x}: Some{x}
    case None{}: pick_one(upd, upe, c)

def step.ord(upf: Bool, +h: String, +ce: H.I64, +upd: String, +upe: H.I64, +c: Ctx) -> Maybe<&2, String>:
  match upf:
    case True{}: step.two1(pick_one(upd, upe, c), h, ce, c)
    case False{}: step.two2(pick_one(h, ce, c), upd, upe, c)

def step.long(+p: Nat, +c: Ctx) -> Maybe<&2, String>:
  +d = Ctx.d(c)
  +h = String.take(d, p)
  +r = String.drop(d, p)
  +ce = H.i64_add(Ctx.e(c), i64u(U32.from_nat(Nat.sub(String.length(d), p))))
  +up = inc_head(h)
  step.ord(pref(r, h), h, ce, cut(up, p), cut_e(Nat.is_gt(String.length(up), p), ce), c)

def step.go(short: Bool, +p: Nat, +c: Ctx) -> Maybe<&2, String>:
  match short:
    case True{}: pick_one(Ctx.d(c), Ctx.e(c), c)
    case False{}: step.long(p, c)

def step(+p: Nat, +c: Ctx) -> Maybe<&2, String>:
  step.go(Nat.is_le(String.length(Ctx.d(c)), p), p, c)

def search(+f: Nat, +m: Maybe<&2, String>, +c: Ctx) -> String:
  match f m:
    case f0 Some{x}: x
    case 0n None{}: String.concat([sign_of(c), fmt(Ctx.d(c), Ctx.e(c))])
    case 1n+g None{}: search(g, step(Nat.sub(18n, f), c), c)


def sign_of2(neg: Bool) -> String:
  match neg:
    case True{}: "-"
    case False{}: ""

def repr.special(isinf: Bool, +neg: Bool) -> String:
  match isinf:
    case True{}: String.concat([sign_of2(neg), "inf"])
    case False{}: "nan"

def repr.mant.go(sub: Bool, +frac: U32) -> U32:
  match sub:
    case True{}: frac
    case False{}: U32.or(frac, 8388608)

def repr.mant(+be: U32, +frac: U32) -> U32: repr.mant.go(U32.is_zero(be), frac)

def repr.exp.go(sub: Bool, +be: U32) -> H.I64:
  match sub:
    case True{}: i64n(149)
    case False{}: H.i64_sub(i64u(be), i64u(150))

def repr.exp(+be: U32) -> H.I64: repr.exp.go(U32.is_zero(be), be)

type ME is Data:
  ME{+m: U32, +e: H.I64}

def tz(+m: U32) -> Nat: Nat.sub(U32.to_nat(blen(U32.and(m, U32.sub(0, m)))), 1n)

def strip(+m: U32, +e: H.I64) -> ME:
  +k = tz(m)
  ME{U32.shrn(m, k), H.i64_add(e, i64u(U32.from_nat(k)))}

type Bounds is Data:
  Bounds{+lod: List<&2, U32>, +loe: H.I64, +hid: List<&2, U32>, +hie: H.I64}

def mk_bounds.hi(hb: Scaled, +lod: List<&2, U32>, +loe: H.I64) -> Bounds:
  match hb:
    case Scaled{dg, ex}: Bounds{lod, loe, dg, ex}

def mk_bounds(lb: Scaled, hb: Scaled) -> Bounds:
  match lb:
    case Scaled{dg, ex}: mk_bounds.hi(hb, dg, ex)

def repr_num.go(b: Bounds, +dg: List<&2, U32>, +ex: H.I64, +neg: Bool) -> String:
  match b:
    case Bounds{lod, loe, hid, hie}:
      search(17n, None{}, Ctx{ds_str(dg), ex, ds_str(lod), loe, ds_str(hid), hie, neg})

def repr_num.dec(sc: Scaled, +m: U32, +e: H.I64, +neg: Bool) -> String:
  match sc:
    case Scaled{dg, ex}:
      repr_num.go(mk_bounds(bound(m, e, False{}, bound.step(m)), bound(m, e, True{}, 54)), dg, ex, neg)

def repr_num.strip(me: ME, +neg: Bool) -> String:
  match me:
    case ME{m, e}: repr_num.dec(dec2(m, e), m, e, neg)

def repr_num(+m0: U32, +e0: H.I64, +neg: Bool) -> String:
  repr_num.strip(strip(m0, e0), neg)

def repr.zero(z: Bool, +frac: U32, +be: U32, +neg: Bool) -> String:
  match z:
    case True{}: String.concat([sign_of2(neg), "0.0"])
    case False{}: repr_num(repr.mant(be, frac), repr.exp(be), neg)

def repr.go(special: Bool, +frac: U32, +be: U32, +neg: Bool) -> String:
  match special:
    case True{}: repr.special(U32.is_zero(frac), neg)
    case False{}: repr.zero(U32.is_zero(U32.or(be, frac)), frac, be, neg)

def repr(+x: F32) -> String:
  +b = F32.bits(x)
  +neg = Bool.not(U32.is_zero(U32.and(b, 2147483648)))
  +be = U32.and(U32.shrn(b, 23n), 255)
  +frac = U32.and(b, 8388607)
  repr.go(U32.is_eq(be, 255), frac, be, neg)
