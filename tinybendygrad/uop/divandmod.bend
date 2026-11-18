# divandmod.bend -- tinygrad/uop/divandmod.py.
# `div_and_mod_symbolic` is a three-entry `PatternMatcher`: two fast inline rules
# the walls are half stale, and measured (2026-11-06). the header used to say "the one
#   * `divides` -- the port has it (`ops.bend:7656`), a full recursion over ADD/MUL/CONST
# what is actually left is scope and three shape problems, not missing primitives:
# `fold_divmod_general` also RECURSES at :61 (`nest_by_factor` calls it on
# FOUR DIVERGENCES, stated rather than hidden.
# two things about the patterns that are easy to invert, both measured against the
# 1. `Ops.ADD` IS COMMUTATIVE, so `UPat.cvar("c") + UPat.cvar("a")` is an `is_any`

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# affine), and it is NOT true that it cannot be a `Data` field -- MEASURED, 20 in-tree
type Hit is Data:
  Hit{ar: O.Arena, i: U32, on: U32}

def Hit.ar(x: Hit) -> O.Arena:
  match x:
    case Hit{ar, i, on}: ar

def Hit.i(x: Hit) -> U32:
  match x:
    case Hit{ar, i, on}: i

def Hit.on(x: Hit) -> U32:
  match x:
    case Hit{ar, i, on}: on

def miss(ar: O.Arena) -> Hit:
  Hit{ar, 0, 0}

def dm_val.go(v: O.Const) -> Maybe<&2, U32>:
  match v:
    case O.CInt{i}: Some{H.lo32(i)}
    case _: None{}

def dm_val.arg(arg: O.Arg) -> Maybe<&2, U32>:
  match arg:
    case O.APy{v}: dm_val.go(v)
    case _: None{}

def dm_val(ar: O.Arena, u: U32) -> Maybe<&2, U32>:
  dm_val.arg(O.Arena.arg(ar, u))

def dm_has.go(v: U32) -> Bool:
  match v:
    case _: True{}

def dm_has(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{v}: dm_has.go(v)
    case None{}: False{}

def dm_ival.go(m: Maybe<&2, U32>, k: U32) -> U32:
  match m:
    case Some{v}: v
    case None{}: k

def dm_ival(m: Maybe<&2, U32>) -> U32:
  dm_ival.go(m, 0)

def dm_floordiv.exact(exact: Bool, q: U32) -> U32:
  match exact:
    case True{}: q
    case False{}: U32.add(q, 1)

def dm_floordiv.trunc(neg: Bool, exact: Bool, q: U32) -> U32:
  match neg:
    case True{}: H.i32_neg(dm_floordiv.exact(exact, q))
    case False{}: q

def dm_floordiv.put(zero: Bool, neg: Bool, exact: Bool, ax: U32, ay: U32) -> U32:
  match zero:
    case True{}: 0
    case _: dm_floordiv.trunc(neg, exact, U32.div(ax, ay))

def dm_floordiv.exact2(ax: U32, ay: U32) -> Bool:
  U32.is_zero(U32.mod(ax, ay))
def dm_floordiv(+x: U32, +y: U32) -> U32:
  dm_floordiv.put(U32.is_zero(y), H.cdiv_sign(x, y),
                  dm_floordiv.exact2(H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y)),
                  H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y))

def dm_floormod(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(dm_floordiv(x, y), y))

def dm_pos(+v: U32) -> Bool:
  Bool.and(Bool.not(H.i32_is_neg(v)), Bool.not(U32.is_zero(v)))

def dm_isn2(ar: O.Arena, u: U32) -> Bool:
  U32.is_eq(O.Arena.nsrc(ar, u), 2)

def dm_is_quot(+ar: O.Arena, +s: U32) -> Bool:
  Bool.and(O.op_is(ar, s, O.OpsDIV{}), dm_has(dm_val(ar, O.Arena.src(ar, s, 1))))

def dm_which.go(s0: Bool, s1: Bool) -> U32:
  match s0 s1:
    case True{} False{}: 0
    case False{} True{}: 1
    case _ _: 2

def dm_which(+ar: O.Arena, +add: U32) -> U32:
  dm_which.go(dm_is_quot(ar, O.Arena.src0(ar, add)), dm_is_quot(ar, O.Arena.src(ar, add, 1)))

# `dtypes.weakint` -- `UPat.var("x", dtypes.weakint)` at divandmod.py:103 and the
def dm_weak.cls(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case _: False{}

def dm_weak.dt(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: dm_weak.cls(S.Dt.cls(d))
    case None{}: False{}

def dm_weak(+fx: F.Folded, u: U32) -> Bool:
  dm_weak.dt(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), u))

# `fold_divmod_general` -- divandmod.py:8, in Python's order. The other 60 lines

# `y.vmin==y.vmax==0` -- divandmod.py:11. A PARAM's range is a `PyRange{lo,hi}` of
def dm_zero.range(r: Maybe<&2, O.PyRange>) -> Bool:
  match r:
    case Some{O.PyRange{lo, hi}}: Bool.and(U32.is_zero(H.lo32(lo)), U32.is_zero(H.lo32(hi)))
    case None{}: False{}

def dm_zero.param(arg: O.Arg) -> Bool:
  match arg:
    case O.AParam{pa}: dm_zero.range(O.ParamArg.vmin_vmax(pa))
    case _: False{}

def dm_zero.op(op: O.Op, arg: O.Arg) -> Bool:
  match op:
    case O.OpsCONST{}: U32.is_zero(dm_ival(dm_val.arg(arg)))
    case O.OpsPARAM{}: dm_zero.param(arg)
    case _: False{}

def dm_zero(+ar: O.Arena, +d: U32) -> Bool:
  dm_zero.op(O.Arena.op(ar, O.Arena.src(ar, d, 1)), O.Arena.arg(ar, O.Arena.src(ar, d, 1)))

# `x//y is constant` -- divandmod.py:12, and the arm is EXACT rather than
# `x - xdiv.vmin*y`, the MOD half of divandmod.py:13.
def dm_point.sub(ar: O.Arena, x: U32, y: U32, q: U32) -> O.Found:
  +qc = O.UOp.const(ar, O.CInt{H.i64_of_i32(q)})
  +m = O.UOp.alu(O.Found.ar(qc), O.OpsMUL{}, [O.Found.i(qc), y])
  O.UOp.alu(O.Found.ar(m), O.OpsSUB{}, [x, O.Found.i(m)])

def dm_point.body(ar: O.Arena, op: O.Op, x: U32, y: U32, q: U32) -> O.Found:
  match op:
    case O.OpsDIV{}: O.UOp.const(ar, O.CInt{H.i64_of_i32(q)})
    case _: dm_point.sub(ar, x, y, q)

# divandmod.py:13, for CONST/CONST. `q` is the FLOOR quotient.
def dm_point.put(+ar: O.Arena, +d: U32, op: O.Op, q: U32) -> Maybe<&2, O.Found>:
  Some{dm_point.body(ar, op, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1), q)}

def dm_point.yes(ar: O.Arena, d: U32, op: O.Op, cx: Maybe<&2, U32>, cy: Maybe<&2, U32>, both: Bool) -> Maybe<&2, O.Found>:
  match both:
    case True{}: dm_point.put(ar, d, op, dm_floordiv(dm_ival(cx), dm_ival(cy)))
    case False{}: None{}

def dm_point.go(ar: O.Arena, d: U32, op: O.Op, +cx: Maybe<&2, U32>, +cy: Maybe<&2, U32>) -> Maybe<&2, O.Found>:
  dm_point.yes(ar, d, op, cx, cy, Bool.and(dm_has(cx), dm_has(cy)))

def dm_point(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  dm_point.go(ar, d, O.Arena.op(ar, d), dm_val(ar, O.Arena.src0(ar, d)), dm_val(ar, O.Arena.src(ar, d, 1)))

# PARAM // c is irreducible -- divandmod.py:15, and it is the last of the three
# 1 (ops.py:1013) and `1 % 1 == 0`, so `MOD(param, CONST(1))` rewrites to
def dm_multiple_of.mod(mult: Maybe<&2, U32>, y: U32) -> Bool:
  match mult:
    case Some{k}: U32.is_zero(dm_floormod(k, y))
    case None{}: False{}

def dm_multiple_of.param(arg: O.Arg, y: U32) -> Bool:
  match arg:
    case O.AParam{pa}: dm_multiple_of.mod(O.ParamArg.multiple_of(pa), y)
    case _: False{}

def dm_multiple_of.go(op: O.Op, arg: O.Arg, y: U32) -> Bool:
  match op:
    case O.OpsPARAM{}: dm_multiple_of.param(arg, y)
    case _: False{}

def dm_multiple_of(+ar: O.Arena, +d: U32) -> Bool:
  dm_multiple_of.go(O.Arena.op(ar, O.Arena.src0(ar, d)), O.Arena.arg(ar, O.Arena.src0(ar, d)),
                    dm_ival(dm_val(ar, O.Arena.src(ar, d, 1))))

# divandmod.py:15. DIV is the `None`, so the ladder below keys on it.
def dm_multiple_of.hit(ar: O.Arena, op: O.Op) -> Maybe<&2, O.Found>:
  match op:
    case O.OpsDIV{}: None{}
    case _: Some{O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})}

def dm_multiple_of.arm.go(+ar: O.Arena, d: U32, hit: Bool) -> Maybe<&2, O.Found>:
  match hit:
    case True{}: dm_multiple_of.hit(ar, O.Arena.op(ar, d))
    case False{}: None{}

def dm_multiple_of.arm(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  dm_multiple_of.arm.go(ar, d, dm_multiple_of(ar, d))

def dm_first2.go(b: Maybe<&2, O.Found>, c: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match b:
    case Some{f}: Some{f}
    case None{}: c

# `fold_divmod_general` -- divandmod.py:8-96. The `raise` is line 11 and it comes
def fold_divmod_general.go(+ar: O.Arena, +d: U32, zero: Bool) -> Maybe<&2, O.Found>:
  match zero:
    case True{}: None{}
    case False{}: dm_first2.go(dm_point(ar, d), dm_multiple_of.arm(ar, d))

def fold_divmod_general(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  fold_divmod_general.go(ar, d, dm_zero(ar, d))

#  1. Fast Inline Rules , rule 0 -- divandmod.py:101.
def dm_0.build(+ar: O.Arena, q: U32, a: U32, +c: U32, d: U32) -> O.Found:
  +ac = O.UOp.alu(ar, O.OpsMUL{}, [a, c])
  +s = O.UOp.alu(O.Found.ar(ac), O.OpsADD{}, [O.Arena.src0(ar, q), O.Found.i(ac)])
  +cd = O.UOp.alu(O.Found.ar(s), O.OpsMUL{}, [c, d])
  O.UOp.alu(O.Found.ar(cd), O.OpsDIV{}, [O.Found.i(s), O.Found.i(cd)])

def dm_0.make.go(+ar: O.Arena, d: U32, +s0: U32, +s1: U32, which: U32) -> O.Found:
  match which:
    case 0: dm_0.build(ar, s0, s1, O.Arena.src(ar, s0, 1), d)
    case _: dm_0.build(ar, s1, s0, O.Arena.src(ar, s1, 1), d)

def dm_0.make(+ar: O.Arena, d: U32, +add: U32, which: U32) -> O.Found:
  dm_0.make.go(ar, d, O.Arena.src0(ar, add), O.Arena.src(ar, add, 1), which)

def dm_0.pat.put(+ar: O.Arena, +d: U32, +add: U32, which: U32, op: Bool, self: U32) -> Bool:
  Bool.and(op, Bool.and(dm_isn2(ar, self), Bool.and(dm_has(dm_val(ar, d)),
    Bool.and(O.op_is(ar, add, O.OpsADD{}), Bool.and(dm_isn2(ar, add), U32.is_lt(which, 2))))))

def dm_0.armed(ar: O.Arena, d: U32, add: U32, which: U32, ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dm_0.make(ar, d, add, which)}
    case False{}: None{}

def dm_0.go(+ar: O.Arena, +d: U32, +add: U32, +which: U32, op: Bool, self: U32) -> Maybe<&2, O.Found>:
  dm_0.armed(ar, d, add, which, Bool.and(dm_0.pat.put(ar, d, add, which, op, self), dm_pos(dm_ival(dm_val(ar, d)))))

def dm_0.put(+ar: O.Arena, +self: U32) -> Maybe<&2, O.Found>:
  dm_0.go(ar, O.Arena.src(ar, self, 1), O.Arena.src0(ar, self),
          dm_which(ar, O.Arena.src0(ar, self)), O.op_is(ar, self, O.OpsDIV{}), self)

def dm_0(fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  dm_0.put(F.Folded.ar(fx), self)

#  1. Fast Inline Rules , rule 1 -- divandmod.py:103-105.
def dm_1.fd(ar: O.Arena, x: U32, d: U32, cm: U32, cq: U32) -> O.Found:
  +cmc = O.UOp.const(ar, O.CInt{H.i64_of_i32(cm)})
  +s = O.UOp.alu(O.Found.ar(cmc), O.OpsADD{}, [x, O.Found.i(cmc)])
  +q = O.UOp.alu(O.Found.ar(s), O.OpsDIV{}, [O.Found.i(s), d])
  +cqc = O.UOp.const(O.Found.ar(q), O.CInt{H.i64_of_i32(cq)})
  O.UOp.alu(O.Found.ar(cqc), O.OpsADD{}, [O.Found.i(q), O.Found.i(cqc)])

def dm_1.fm(ar: O.Arena, x: U32, d: U32, cm: U32) -> O.Found:
  +cmc = O.UOp.const(ar, O.CInt{H.i64_of_i32(cm)})
  +s = O.UOp.alu(O.Found.ar(cmc), O.OpsADD{}, [x, O.Found.i(cmc)])
  O.UOp.alu(O.Found.ar(s), O.OpsMOD{}, [O.Found.i(s), d])

def dm_1.finish(ar: O.Arena, op: O.Op, x: U32, d: U32, cm: U32, cq: U32) -> O.Found:
  match op:
    case O.OpsDIV{}: dm_1.fd(ar, x, d, cm, cq)
    case _: dm_1.fm(ar, x, d, cm)

def dm_1.pick(s0: U32, s1: U32, which: U32) -> U32:
  match which:
    case 1: s0
    case _: s1

def dm_cval(+ar: O.Arena, +add: U32, which: U32) -> U32:
  dm_ival(dm_val(ar, dm_1.pick(O.Arena.src(ar, add, 1), O.Arena.src0(ar, add), which)))

def dm_1.make(+ar: O.Arena, op: O.Op, d: U32, +add: U32, which: U32, cm: U32, cq: U32) -> O.Found:
  dm_1.finish(ar, op, dm_1.pick(O.Arena.src0(ar, add), O.Arena.src(ar, add, 1), which), d, cm, cq)

def dm_cside.go(s0: Bool, s1: Bool) -> U32:
  match s0 s1:
    case True{} False{}: 0
    case False{} True{}: 1
    case _ _: 2

def dm_cside(+ar: O.Arena, +add: U32) -> U32:
  dm_cside.go(dm_has(dm_val(ar, O.Arena.src0(ar, add))), dm_has(dm_val(ar, O.Arena.src(ar, add, 1))))

def dm_1.pat.put(+ar: O.Arena, +d: U32, +add: U32, which: U32, weak: Bool, self: U32) -> Bool:
  Bool.and(dm_isn2(ar, self), Bool.and(dm_has(dm_val(ar, d)),
    Bool.and(O.op_is(ar, add, O.OpsADD{}), Bool.and(dm_isn2(ar, add), Bool.and(U32.is_lt(which, 2), weak)))))

def dm_1.armed(ar: O.Arena, op: O.Op, d: U32, add: U32, which: U32, cm: U32, cq: U32, ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dm_1.make(ar, op, d, add, which, cm, cq)}
    case False{}: None{}

def dm_1.go2(+ar: O.Arena, op: O.Op, +d: U32, +add: U32, +which: U32, weak: Bool, self: U32, +dv: U32, +cv: U32) -> Maybe<&2, O.Found>:
  dm_1.armed(ar, op, d, add, which, dm_floormod(cv, dv), dm_floordiv(cv, dv),
             Bool.and(dm_1.pat.put(ar, d, add, which, weak, self),
                      Bool.not(Bool.or(U32.is_zero(dv), U32.is_eq(dm_floormod(cv, dv), cv)))))

def dm_1.go(+ar: O.Arena, op: O.Op, +d: U32, +add: U32, +which: U32, weak: Bool, self: U32) -> Maybe<&2, O.Found>:
  dm_1.go2(ar, op, d, add, which, weak, self, dm_ival(dm_val(ar, d)), dm_cval(ar, add, which))

def dm_weak_side(u: U32, ar: O.Arena, tb: F.Table) -> Bool:
  dm_weak.dt(F.fold.dt(ar, tb, u))

def dm_1.put2(+fx: F.Folded, +self: U32, +add: U32, +which: U32) -> Maybe<&2, O.Found>:
  dm_1.go(F.Folded.ar(fx), O.Arena.op(F.Folded.ar(fx), self), O.Arena.src(F.Folded.ar(fx), self, 1),
          add, which, dm_weak_side(dm_1.pick(O.Arena.src0(F.Folded.ar(fx), add), O.Arena.src(F.Folded.ar(fx), add, 1), which), F.Folded.ar(fx), F.Folded.t(fx)), self)

def dm_1.put(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  dm_1.put2(fx, self, O.Arena.src0(F.Folded.ar(fx), self), dm_cside(F.Folded.ar(fx), O.Arena.src0(F.Folded.ar(fx), self)))

def dm_1(fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  dm_1.put(fx, self)

#  2. Slow Rules  -- divandmod.py:108, the one entry. The weakint conjunct is
def dm_2.armed(fx: F.Folded, self: U32, weak: Bool) -> Maybe<&2, O.Found>:
  match weak:
    case True{}: fold_divmod_general(F.Folded.ar(fx), self)
    case False{}: None{}

def dm_2.put(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  dm_2.armed(fx, self, dm_weak(fx, self))
def dm_2(fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  dm_2.put(fx, self)

def dm_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsDIV{}], [O.OpsADD{}, O.OpsCONST{}]},                       # 101
             O.PMEntry{1, [O.OpsDIV{}, O.OpsMOD{}], [O.OpsADD{}, O.OpsCONST{}]},         # 103
             O.PMEntry{2, [O.OpsDIV{}, O.OpsMOD{}], Nil{}}]}                           # 108

def dm_fold.put(ar: O.Arena, +f: O.Found) -> Hit:
  Hit{O.Found.ar(f), O.Found.i(f), 1}

def dm_fold.new(ar: O.Arena, m: Maybe<&2, O.Found>) -> Hit:
  match m:
    case Some{f}: dm_fold.put(ar, f)
    case None{}: Hit{ar, 0, 0}

def dm_fold.go(on: U32, +acc: Hit, m: Maybe<&2, O.Found>) -> Hit:
  match on:
    case 1: acc
    case _: dm_fold.new(Hit.ar(acc), m)

def dm_fold(+acc: Hit, m: Maybe<&2, O.Found>) -> Hit:
  dm_fold.go(Hit.on(acc), acc, m)

def dm_apply.pick(tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  match tag:
    case 0: dm_fold(acc, dm_0(fx, self))
    case 1: dm_fold(acc, dm_1(fx, self))
    case 2: dm_fold(acc, dm_2(fx, self))
    case _: acc

def dm_apply(tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dm_apply.pick(tag, fx, self, acc)

def dm_try.pick(ok: Bool, +fx: F.Folded, +self: U32, +acc: Hit, tag: U32) -> Hit:
  match ok:
    case True{}: dm_apply(tag, fx, self, acc)
    case False{}: acc

def dm_try(+e: O.PMEntry, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dm_try.pick(Bool.and(O.pm_claimed(O.PMEntry.ops(e), F.Folded.ar(fx), self),
                       O.pm_early(dm_table(), F.Folded.ar(fx), self, O.PMEntry.rej(e))),
              fx, self, acc, O.PMEntry.tag(e))

def dm_scan(+todo: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, acc: Hit) -> Hit:
  match todo:
    case Nil{}: acc
    case e <> t: dm_scan(t, fx, self, dm_try(e, fx, self, acc))

# `PatternMatcher.rewrite` -- ops.py:1605. `ret is not uop` at ops.py:1610 is the
def div_and_mod_symbolic(+fx: F.Folded, self: U32) -> Hit:
  dm_scan(O.PMEntrys.es(dm_table()), fx, self, miss(F.Folded.ar(fx)))

#   nrules=3       divandmod.py:98-109 is three entries. A COUNT.
#   rej0=2 rej1=2 rej2=0   the `early_reject` sets, MEASURED against Python:
#   nroots=26      how many roots the fixture arena holds. THE COUNT ROW: a
#   zero_r04=1     divandmod.py:11 on a `CONST(0)` divisor. Python RAISES.
#   on_r13=1 out_r13=CONST(1)          `6//4`, divandmod.py:13's CONST/CONST arm.
#   out_r17=CONST(0)   divandmod.py:15: `Pp.multiple_of == 4` and `4 % 4 == 0`,
#   out_r18=CONST(0)   THE DEFAULT ROW: `Pz.multiple_of` is 1 (ops.py:1013) and
#   out_r19=none   `Pp//4`: divandmod.py:15 returns `None` for DIV.
#   out_r21=none   `Px%4`: past divandmod.py:15, i.e. behind the wall. Python
#    ops.py:1013 is load-bearing in a place no code comment mentions.

def dm_show.go(neg: Bool, v: U32) -> String:
  match neg:
    case True{}: String.concat(["-", U32.show(H.i32_neg(v))])
    case False{}: U32.show(v)

def dm_show(+v: U32) -> String:
  dm_show.go(H.i32_is_neg(v), v)

def dm_lab.name(m: Maybe<&2, String>, k: String) -> String:
  match m:
    case Some{s}: String.concat(["P", s])
    case None{}: k

def dm_lab.put(arg: O.Arg, k: String) -> String:
  match arg:
    case O.AParam{pa}: dm_lab.name(O.ParamArg.name(pa), k)
    case _: k

def dm_lab.of(arg: O.Arg, k: String) -> String:
  dm_lab.put(arg, k)

def dm_lab.go(op: O.Op, arg: O.Arg, k: String) -> String:
  match op:
    case O.OpsCONST{}: String.concat([k, "(", dm_show(dm_ival(dm_val.arg(arg))), ")"])
    case _: dm_lab.of(arg, k)

def dm_lab(+ar: O.Arena, +u: U32) -> String:
  dm_lab.go(O.Arena.op(ar, u), O.Arena.arg(ar, u), O.Ops.name(O.Arena.op(ar, u)))

def dm_sh1.go(+ar: O.Arena, u: U32, s0: U32, s1: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dm_lab(ar, u)
    case _: String.concat([dm_lab(ar, u), "(", dm_lab(ar, s0), ",", dm_lab(ar, s1), ")"])

def dm_sh1.put(+ar: O.Arena, +u: U32, s0: U32, s1: U32) -> String:
  dm_sh1.go(ar, u, s0, s1, U32.is_zero(O.Arena.nsrc(ar, u)))

def dm_sh1(+ar: O.Arena, +u: U32) -> String:
  dm_sh1.put(ar, u, O.Arena.src0(ar, u), O.Arena.src(ar, u, 1))

def dm_sh2.go(+ar: O.Arena, u: U32, s0: U32, s1: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dm_lab(ar, u)
    case _: String.concat([dm_lab(ar, u), "(", dm_sh1(ar, s0), ",", dm_sh1(ar, s1), ")"])

def dm_sh2.put(+ar: O.Arena, +u: U32, s0: U32, s1: U32) -> String:
  dm_sh2.go(ar, u, s0, s1, U32.is_zero(O.Arena.nsrc(ar, u)))

def dm_sh2(+ar: O.Arena, +u: U32) -> String:
  dm_sh2.put(ar, u, O.Arena.src0(ar, u), O.Arena.src(ar, u, 1))

# against ops.py:1015's `ParamArg(-1, dtype, name=name,
type Gate is Data:
  Gate{ar: O.Arena, rs: List<&2, U32>}

def Gate.ar(g: Gate) -> O.Arena:
  match g:
    case Gate{ar, rs}: ar

def Gate.rs(g: Gate) -> List<&2, U32>:
  match g:
    case Gate{ar, rs}: rs

def dm_root(g: Gate, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Gate.rs(g), U32.to_nat(n)), 0)

def nroots(g: Gate) -> U32:
  U32.from_nat(List.length(&2, U32, Gate.rs(g)))

def dm_rejlen.put(m: Maybe<&2, O.PMEntry>, k: U32) -> U32:
  match m:
    case Some{e}: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(e)))
    case None{}: k

def dm_rejlen(n: U32) -> U32:
  dm_rejlen.put(List.get(&2, O.PMEntry, O.PMEntrys.es(dm_table()), U32.to_nat(n)), 0)

def dm_param.range(dt: S.Dt, mult: U32, nm: String, lo: U32, vmax: U32) -> O.ParamArg:
  O.ParamArg{0, dt, Some{O.PyRange{H.i64_of_i32(lo), H.i64_of_i32(vmax)}},
             Some{mult}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}
def dm_param(dt: S.Dt, mult: U32, nm: String) -> O.ParamArg:
  dm_param.range(dt, mult, nm, 0, 100)


#  r21 t2_var MOD(Px,C(4))       -> None: past divandmod.py:15
def trees() -> Gate:
  +a = O.Arena.empty()
  +c0 = O.UOp.const(a, O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c3 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(3)})
  +c4 = O.UOp.const(O.Found.ar(c3), O.CInt{H.i64_of_i32(4)})
  +c5 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(5)})
  +c6 = O.UOp.const(O.Found.ar(c5), O.CInt{H.i64_of_i32(6)})
  +c7 = O.UOp.const(O.Found.ar(c6), O.CInt{H.i64_of_i32(7)})
  +c10 = O.UOp.const(O.Found.ar(c7), O.CInt{H.i64_of_i32(10)})
  +cm2 = O.UOp.const(O.Found.ar(c10), O.CInt{H.i64_of_i32(4294967294)})
  +cm4 = O.UOp.const(O.Found.ar(cm2), O.CInt{H.i64_of_i32(4294967292)})
  +cm7 = O.UOp.const(O.Found.ar(cm4), O.CInt{H.i64_of_i32(4294967289)})
  +px = O.UOp.new(O.Found.ar(cm7), O.OpsPARAM{}, Nil{}, O.AParam{dm_param(S.weakint(), 1, "x")}, O.TNone{})
  +pp = O.UOp.new(O.Found.ar(px), O.OpsPARAM{}, Nil{}, O.AParam{dm_param(S.weakint(), 4, "p")}, O.TNone{})
  +pq = O.UOp.new(O.Found.ar(pp), O.OpsPARAM{}, Nil{}, O.AParam{dm_param(S.weakint(), 3, "q")}, O.TNone{})
  +pz = O.UOp.new(O.Found.ar(pq), O.OpsPARAM{}, Nil{}, O.AParam{dm_param(S.weakint(), 1, "z")}, O.TNone{})
  +pi = O.UOp.new(O.Found.ar(pz), O.OpsPARAM{}, Nil{}, O.AParam{dm_param(S.int32(), 1, "i")}, O.TNone{})
  +py = O.UOp.new(O.Found.ar(pi), O.OpsPARAM{}, Nil{}, O.AParam{dm_param.range(S.weakint(), 1, "y", 0, 0)}, O.TNone{})
  +py05 = O.UOp.new(O.Found.ar(py), O.OpsPARAM{}, Nil{}, O.AParam{dm_param.range(S.weakint(), 1, "u", 0, 5)}, O.TNone{})
  +q3 = O.UOp.alu(O.Found.ar(py05), O.OpsDIV{}, [O.Found.i(px), O.Found.i(c3)])
  +a5 = O.UOp.alu(O.Found.ar(q3), O.OpsADD{}, [O.Found.i(q3), O.Found.i(c5)])
  +b5 = O.UOp.alu(O.Found.ar(a5), O.OpsADD{}, [O.Found.i(c5), O.Found.i(q3)])
  +a10 = O.UOp.alu(O.Found.ar(b5), O.OpsADD{}, [O.Found.i(q3), O.Found.i(c10)])
  +x10 = O.UOp.alu(O.Found.ar(a10), O.OpsADD{}, [O.Found.i(px), O.Found.i(c10)])
  +c10x = O.UOp.alu(O.Found.ar(x10), O.OpsADD{}, [O.Found.i(c10), O.Found.i(px)])
  +x3 = O.UOp.alu(O.Found.ar(c10x), O.OpsADD{}, [O.Found.i(px), O.Found.i(c3)])
  +i10 = O.UOp.alu(O.Found.ar(x3), O.OpsADD{}, [O.Found.i(pi), O.Found.i(c10)])
  +r00 = O.UOp.alu(O.Found.ar(i10), O.OpsDIV{}, [O.Found.i(a5), O.Found.i(c7)])
  +r01 = O.UOp.alu(O.Found.ar(r00), O.OpsDIV{}, [O.Found.i(b5), O.Found.i(c7)])
  +r02 = O.UOp.alu(O.Found.ar(r01), O.OpsDIV{}, [O.Found.i(a10), O.Found.i(c7)])
  +r03 = O.UOp.alu(O.Found.ar(r02), O.OpsDIV{}, [O.Found.i(a5), O.Found.i(cm7)])
  +r04 = O.UOp.alu(O.Found.ar(r03), O.OpsDIV{}, [O.Found.i(a5), O.Found.i(c0)])
  +r05 = O.UOp.alu(O.Found.ar(r04), O.OpsDIV{}, [O.Found.i(x10), O.Found.i(c7)])
  +r06 = O.UOp.alu(O.Found.ar(r05), O.OpsMOD{}, [O.Found.i(x10), O.Found.i(c7)])
  +r07 = O.UOp.alu(O.Found.ar(r06), O.OpsDIV{}, [O.Found.i(x3), O.Found.i(c7)])
  +r08 = O.UOp.alu(O.Found.ar(r07), O.OpsDIV{}, [O.Found.i(c10x), O.Found.i(c7)])
  +r09 = O.UOp.alu(O.Found.ar(r08), O.OpsDIV{}, [O.Found.i(x10), O.Found.i(c1)])
  +r10 = O.UOp.alu(O.Found.ar(r09), O.OpsDIV{}, [O.Found.i(x10), O.Found.i(cm7)])
  +r11 = O.UOp.alu(O.Found.ar(r10), O.OpsDIV{}, [O.Found.i(x10), O.Found.i(c0)])
  +r12 = O.UOp.alu(O.Found.ar(r11), O.OpsDIV{}, [O.Found.i(i10), O.Found.i(c7)])
  +r13 = O.UOp.alu(O.Found.ar(r12), O.OpsDIV{}, [O.Found.i(c6), O.Found.i(c4)])
  +r14 = O.UOp.alu(O.Found.ar(r13), O.OpsMOD{}, [O.Found.i(c6), O.Found.i(c4)])
  +r15 = O.UOp.alu(O.Found.ar(r14), O.OpsDIV{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r16 = O.UOp.alu(O.Found.ar(r15), O.OpsMOD{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r17 = O.UOp.alu(O.Found.ar(r16), O.OpsMOD{}, [O.Found.i(pp), O.Found.i(c4)])
  +r18 = O.UOp.alu(O.Found.ar(r17), O.OpsMOD{}, [O.Found.i(pz), O.Found.i(c1)])
  +r19 = O.UOp.alu(O.Found.ar(r18), O.OpsDIV{}, [O.Found.i(pp), O.Found.i(c4)])
  +r20 = O.UOp.alu(O.Found.ar(r19), O.OpsMOD{}, [O.Found.i(pq), O.Found.i(c4)])
  +r21 = O.UOp.alu(O.Found.ar(r20), O.OpsMOD{}, [O.Found.i(px), O.Found.i(c4)])
# TODO(p3) divandmod.py:13  symbol=fold_divmod_general  the RANGE HALF of `x//y` being a point -- PORTED for
#   CONST/CONST only, where `_min_max` (ops.py:1127) is four identical `a//b` and
#   MEASURED FALSE (2026-11-06): THE PORT HAS `F.UOp.vmin`/`F.UOp.vmax`
# TODO(p3) divandmod.py:17-19 `# split uops for the rest of the processing` --
# TODO(p3) divandmod.py:13-15  symbol=fold_divmod_general  a FLOAT CONST -- `_min_max` returns PyConst and
#  Constant Denominator Rules  -- divandmod.py:21-70. These rules strictly
# TODO(p3) divandmod.py:23-25 `nested_div: (x%(k*c))//c -> (x//c)%k (requires k>0);
#   `x.src[1].divides(c)`. THE WALL THIS NAMED IS MEASURED FALSE (2026-11-06): `divides` IS
#   MEASURED CASES -- `(x*4).divides(4)` IS `MUL(x, 1)`, `(x*4+8).divides(4)` IS
# TODO(p3) divandmod.py:27-35 `remove_nested_mod in sum: (a%4 + b)%2 -> (a+b)%2` --
# TODO(p3) divandmod.py:37  symbol=fold_divmod_general  `Shared decomposition for folding rules` and :41-48
# TODO(p3) divandmod.py:50-55  symbol=fold_divmod_general  `gcd_with_remainder: factor out common gcd from
# TODO(p3) divandmod.py:57-70 `nest_by_factor: x//c -> (x//f)//(c//f),
#  Variable Denominator / Fallback Rules  -- divandmod.py:72-96. These rules
# TODO(p3) divandmod.py:77-81  symbol=fold_divmod_general  `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)` and :83-96
# TODO(p3) divandmod.py:11  symbol=fold_divmod_general  the `raise` itself -- Python's
#   * `_min_max` (ops.py:1104) IS `fold.bend:7306` ("DONE(p3) ops.py:1094 def _min_max"), AND
#     the header above already said "the `_min_max` wall is measured FALSE (2026-11-06)".
#   1. `UOp.gcd` (ops.py:1073) AND `UOp.divide_exact` (ops.py:1079) -- AND THEY ARE ONE
#      HASHABLE BY IDENTITY (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND
#      CONTAINER AND NOT ABOUT A CAPABILITY.
#   2. `simplify` / `ssimplify` (ops.py:513/520) IS WHAT `fold_divmod_general` LINE 78
  +r22 = O.UOp.alu(O.Found.ar(r21), O.OpsDIV{}, [O.Found.i(x10), O.Found.i(c7), O.Found.i(c1)])
  +r23 = O.UOp.alu(O.Found.ar(r22), O.OpsDIV{}, [O.Found.i(px), O.Found.i(py)])
  +r24 = O.UOp.alu(O.Found.ar(r23), O.OpsMOD{}, [O.Found.i(px), O.Found.i(py)])
  +r25 = O.UOp.alu(O.Found.ar(r24), O.OpsDIV{}, [O.Found.i(px), O.Found.i(py05)])
  Gate{O.Found.ar(r25), [O.Found.i(r00), O.Found.i(r01), O.Found.i(r02), O.Found.i(r03), O.Found.i(r04), O.Found.i(r05), O.Found.i(r06), O.Found.i(r07), O.Found.i(r08), O.Found.i(r09), O.Found.i(r10), O.Found.i(r11), O.Found.i(r12), O.Found.i(r13), O.Found.i(r14), O.Found.i(r15), O.Found.i(r16), O.Found.i(r17), O.Found.i(r18), O.Found.i(r19), O.Found.i(r20), O.Found.i(r21), O.Found.i(r22), O.Found.i(r23), O.Found.i(r24), O.Found.i(r25)]}

# THE TABLE IS IN `.agents/slop/tables/uop-divandmod-858.md` -- NOT PORTED, one line each, with the WALL and the phase that owns it. The block
def fx(g: Gate) -> F.Folded:
  F.folded(Gate.ar(g))

def rw(+g: Gate, n: U32) -> Hit:
  div_and_mod_symbolic(fx(g), dm_root(g, n))

def t_on(g: Gate, n: U32) -> U32: Hit.on(rw(g, n))

def t_out.go(on: U32, +h: Hit) -> String:
  match on:
    case 0: "none"
    case _: dm_sh2(Hit.ar(h), Hit.i(h))

def t_out.put(+h: Hit) -> String:
  t_out.go(Hit.on(h), h)

def t_out(g: Gate, n: U32) -> String: t_out.put(rw(g, n))

def t_grown.put(+h: Hit, g: Gate) -> U32:
  U32.sub(O.Arena.next(Hit.ar(h)), O.Arena.next(Gate.ar(g)))

def t_grown(+g: Gate, n: U32) -> U32: t_grown.put(rw(g, n), g)

# `y.vmin==y.vmax==0` -- divandmod.py:11, which Python RAISES on.
def t_zero.put(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def t_zero(n: U32) -> U32:
  t_zero.put(dm_zero(Gate.ar(trees()), dm_root(trees(), n)))

def t_nrules() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(dm_table())))

def t_nroots() -> U32: nroots(trees())

