# divandmod.bend -- tinygrad/uop/divandmod.py.
# `div_and_mod_symbolic` is a three-entry `PatternMatcher`: two fast inline rules
# the walls are half stale, and measured (2026-11-06). the header used to say "the one
#   * `divides` -- the port has it (`ops.bend:7656`), a full recursion over ADD/MUL/CONST
#     carrying a `Dv`, and it answers the same as upstream's on four measured cases.
#   * `_min_max` -- THE PORT HAS `F.UOp.vmin`/`F.UOp.vmax` (`fold.bend:5344`/`5402`) AND THEY
#     MATCH UPSTREAM'S ON FIVE MEASURED CASES.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# THE ACCUMULATOR. These rules GROW the arena, so the answer is the arena AND a
# node index AND whether anything fired. A `Maybe` cannot be a FOLD'S ACCUMULATOR (it is
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

# `y.val` for an INTEGER CONST. A `Maybe` because `Arg` is the eighteen-armed
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

# `Some -> True`, and the value with a 0 for the `None` case. Two leaves, so the
# call sites below do not each re-match a `Maybe`.
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

# `dm_floordiv` / `dm_floormod` ARE NOT `H.`: `H.floordiv_i32`/`H.floormod_i32` add
def dm_floordiv.exact(exact: Bool, q: U32) -> U32:
  match exact:
    case True{}: q
    case False{}: U32.add(q, 1)

# truncate toward zero, then step down one more ONLY when the signs differ and
# the division was inexact -- which is Python's `//` and nowhere else.
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
# The division is over the MAGNITUDES -- `U32.div` is unsigned and `U32.mod` of a
def dm_floordiv(+x: U32, +y: U32) -> U32:
  dm_floordiv.put(U32.is_zero(y), H.cdiv_sign(x, y),
                  dm_floordiv.exact2(H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y)),
                  H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y))

def dm_floormod(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(dm_floordiv(x, y), y))

# `v > 0` for a SIGNED 32-bit constant. `U32.is_gt(v, 0)` is the UNSIGNED reading
def dm_pos(+v: U32) -> Bool:
  Bool.and(Bool.not(H.i32_is_neg(v)), Bool.not(U32.is_zero(v)))

# `len(u.src) == 2` -- the `strict_length` conjunct rules 0 and 1 carry.
def dm_isn2(ar: O.Arena, u: U32) -> Bool:
  U32.is_eq(O.Arena.nsrc(ar, u), 2)

# `x//c` as a SHAPE: a DIV whose divisor is a CONST. Rule 0's
# `UPat.var("x")//UPat.cvar("c")`, with the name bindings left to `dm_which`.
def dm_is_quot(+ar: O.Arena, +s: U32) -> Bool:
  Bool.and(O.op_is(ar, s, O.OpsDIV{}), dm_has(dm_val(ar, O.Arena.src(ar, s, 1))))

# WHICH side of the commutative ADD is the quotient: 0 = src0, 1 = src1,
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

# The DIVISOR. Python's message even names which of the two ops it was.
def dm_zero(+ar: O.Arena, +d: U32) -> Bool:
  dm_zero.op(O.Arena.op(ar, O.Arena.src(ar, d, 1)), O.Arena.arg(ar, O.Arena.src(ar, d, 1)))

# `x//y is constant` -- divandmod.py:12, and the arm is EXACT rather than
def dm_point.sub(ar: O.Arena, x: U32, y: U32, q: U32) -> O.Found:
  +qc = O.UOp.const(ar, O.CInt{H.i64_of_i32(q)})
  +m = O.UOp.alu(O.Found.ar(qc), O.OpsMUL{}, [O.Found.i(qc), y])
  O.UOp.alu(O.Found.ar(m), O.OpsSUB{}, [x, O.Found.i(m)])

# `xdiv.const_like(xdiv.vmin)`, the DIV half.
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

# Python has already RAISED by this line, so the lambda has no `d.val == 0` guard;
# it is here because it is what keeps `multiple_of % 0` out of the picture.
def dm_multiple_of(+ar: O.Arena, +d: U32) -> Bool:
  dm_multiple_of.go(O.Arena.op(ar, O.Arena.src0(ar, d)), O.Arena.arg(ar, O.Arena.src0(ar, d)),
                    dm_ival(dm_val(ar, O.Arena.src(ar, d, 1))))

# `d.const_like(0) if d.op is Ops.MOD else None` -- the tail of the lambda on
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

# Python's `if ...: return A` twice. A `Maybe<&2, T>` is a `Type`, so it cannot
# take a `+`; first-wins is a leaf over two parameters instead.
def dm_first2.go(b: Maybe<&2, O.Found>, c: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match b:
    case Some{f}: Some{f}
    case None{}: c

# `fold_divmod_general` -- divandmod.py:8-96. The `raise` is line 11 and it comes
# FIRST, so the zero test gates the other two arms.
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

# the two `is_any` alternatives, resolved: `which` names the `x//c` side and the
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

# `c.val` -- the CONST side is the OTHER side from `x`, so the two sides are
def dm_cval(+ar: O.Arena, +add: U32, which: U32) -> U32:
  dm_ival(dm_val(ar, dm_1.pick(O.Arena.src(ar, add, 1), O.Arena.src0(ar, add), which)))

# the two `is_any` alternatives, resolved: `which` names the CONST side `c` and the
# other side is `x`, which the Python writes FIRST whatever the input order.
def dm_1.make(+ar: O.Arena, op: O.Op, d: U32, +add: U32, which: U32, cm: U32, cq: U32) -> O.Found:
  dm_1.finish(ar, op, dm_1.pick(O.Arena.src0(ar, add), O.Arena.src(ar, add, 1), which), d, cm, cq)

# WHICH side of the commutative ADD is the `cvar("c")` CONST. The MIRROR of
# `dm_which`, and the same three arms: 0 = src0, 1 = src1, 2 = both or neither.
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

# `None if d.val==0 or c.val%d.val==c.val else <the rewrite>`. The first arm of
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

# `UPat.var("x", dtypes.weakint)`: the side of the commutative ADD that is NOT the
# `cvar("c")` CONST, which is `which`-selected because the pattern is an `is_any`.
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

# the table, the dispatch and the scan -- `spec.bend`'s shape, once. `ops.bend`
def dm_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsDIV{}], [O.OpsADD{}, O.OpsCONST{}]},                       # 101
             O.PMEntry{1, [O.OpsDIV{}, O.OpsMOD{}], [O.OpsADD{}, O.OpsCONST{}]},         # 103
             O.PMEntry{2, [O.OpsDIV{}, O.OpsMOD{}], Nil{}}]}                           # 108

# The first non-None wins, so `dm_fold` keys on the ACCUMULATOR; keying on the new
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

# THE GATE, and what each row is FOR. `1`/`0` is "a rule fired" / "the scan found
#   nrules=3       divandmod.py:98-109 is three entries. A COUNT.

# THE GATE'S PRINTER. `dm_sh2` prints a node TWO levels deep, and that is not a
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

# one level: `NAME(src0label,src1label)`
def dm_sh1.go(+ar: O.Arena, u: U32, s0: U32, s1: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dm_lab(ar, u)
    case _: String.concat([dm_lab(ar, u), "(", dm_lab(ar, s0), ",", dm_lab(ar, s1), ")"])

# a leaf is a node with no srcs -- a CONST, a PARAM, a SPECIAL. Printing its srcs
# would print the arena's BOTTOM node, which is what `U32.is_zero(nsrc)` keeps out.
def dm_sh1.put(+ar: O.Arena, +u: U32, s0: U32, s1: U32) -> String:
  dm_sh1.go(ar, u, s0, s1, U32.is_zero(O.Arena.nsrc(ar, u)))

def dm_sh1(+ar: O.Arena, +u: U32) -> String:
  dm_sh1.put(ar, u, O.Arena.src0(ar, u), O.Arena.src(ar, u, 1))

# two levels: the row
def dm_sh2.go(+ar: O.Arena, u: U32, s0: U32, s1: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dm_lab(ar, u)
    case _: String.concat([dm_lab(ar, u), "(", dm_sh1(ar, s0), ",", dm_sh1(ar, s1), ")"])

def dm_sh2.put(+ar: O.Arena, +u: U32, s0: U32, s1: U32) -> String:
  dm_sh2.go(ar, u, s0, s1, U32.is_zero(O.Arena.nsrc(ar, u)))

def dm_sh2(+ar: O.Arena, +u: U32) -> String:
  dm_sh2.put(ar, u, O.Arena.src0(ar, u), O.Arena.src(ar, u, 1))

# THE FIXTURES. One arena, and the roots are addressed BY INDEX rather than by a
# hand-kept record of indices: `Gate.rs` is the list `dm_root` indexes and
# `nroots` is the count, so a fixture added in the wrong place or a root dropped
# shows up as a moved row rather than as a silently shorter table. `ParamArg` has
# thirteen fields in `ops.bend`'s declaration order, so `dm_param` spells them out
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

# `vmax` is a parameter because the ZERO DIVISOR arm needs a PARAM whose declared

# THE NODE LIST, IN BINDING ORDER. 1-11 are the CONSTs, 12-18 the PARAMs, 19 on
# ROOTS, in the order `dm_root` indexes them, with the oracle's tree:
#  r00 t0_a   DIV(ADD(DIV(Px,C(3)),C(5)),C(7))
#             -> DIV(ADD(Px,MUL(C(5),C(3))),MUL(C(3),C(7)))
#  r01 t0_b   ... the SWAPPED add; the same answer
#  r02 t0_c   (x//3 + 10)//7 -> rule 0 AND rule 1 both fire, differently. FIRST-WINS.
#  r03 t0_neg //-7: rule 0 skips on d.vmin>0 and rule 1 answers -> ADD(...,C(-1))
#  r04 t0_d0  //0:  Python RAISES ZeroDivisionError. rule 0 skips, rule 1 skips on
#             d.val==0, rule 2 reports it. `on=0`.
#  r05 t1_fd  (Px+C(10))//7  -> ADD(DIV(ADD(Px,C(3)),C(7)),C(1))
#  r06 t1_fm  (Px+C(10))%7   -> MOD(ADD(Px,C(3)),C(7))
#  r07 t1_same (Px+C(3))//7   -> None: c%d == c
#  r08 t1_swap C(10)+Px       -> the same as r05: x goes FIRST
#  r09 t1_d1  //1             -> ADD(DIV(ADD(Px,C(0)),C(1)),C(10))
#  r10 t1_dn  //-7            -> ADD(DIV(ADD(Px,C(-4)),C(-7)),C(-2)). THE FLOOR ROW.
#  r11 t1_d0  //0             -> Python RAISES. `on=0`
#  r12 t1_i   int32 numerator -> None. THE WEAKINT-CONJUNCT ROW.
#  r13 t2_cst DIV(C(6),C(4))     -> CONST(1)
#  r14 t2_cst2 MOD(C(6),C(4))    -> SUB(C(6),MUL(C(1),C(4)))   [Python: ADD(MUL(MUL,-1))]
#  r15 t2_cn  DIV(C(-7),C(4))    -> CONST(-2). THE FLOOR ROW.
#  r16 t2_cm  MOD(C(-7),C(4))    -> SUB(C(-7),MUL(C(-2),C(4)))
#  r17 t2_pm  MOD(Pp,C(4))       -> CONST(0): multiple_of 4 % 4 == 0
#  r18 t2_p1  MOD(Pz,C(1))       -> CONST(0): multiple_of DEFAULTS to 1
#  r19 t2_pd  DIV(Pp,C(4))       -> None: the lambda returns None for DIV
#  r20 t2_p3  MOD(Pq,C(4))       -> None: 3 % 4 != 0
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
  # the eight MOD/DIV roots of the two Fast Inline Rules
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
  # the nine `fold_divmod_general` roots
  +r13 = O.UOp.alu(O.Found.ar(r12), O.OpsDIV{}, [O.Found.i(c6), O.Found.i(c4)])
  +r14 = O.UOp.alu(O.Found.ar(r13), O.OpsMOD{}, [O.Found.i(c6), O.Found.i(c4)])
  +r15 = O.UOp.alu(O.Found.ar(r14), O.OpsDIV{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r16 = O.UOp.alu(O.Found.ar(r15), O.OpsMOD{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r17 = O.UOp.alu(O.Found.ar(r16), O.OpsMOD{}, [O.Found.i(pp), O.Found.i(c4)])
  +r18 = O.UOp.alu(O.Found.ar(r17), O.OpsMOD{}, [O.Found.i(pz), O.Found.i(c1)])
  +r19 = O.UOp.alu(O.Found.ar(r18), O.OpsDIV{}, [O.Found.i(pp), O.Found.i(c4)])
  +r20 = O.UOp.alu(O.Found.ar(r19), O.OpsMOD{}, [O.Found.i(pq), O.Found.i(c4)])
  +r21 = O.UOp.alu(O.Found.ar(r20), O.OpsMOD{}, [O.Found.i(px), O.Found.i(c4)])
  # the arity row and the two zero-divisor rows
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

# `none` is Python's `None`. Otherwise the tree, TWO levels deep -- which is
# exactly Python's tree for every row this file rewrites, CASTs erased.
def t_out.go(on: U32, +h: Hit) -> String:
  match on:
    case 0: "none"
    case _: dm_sh2(Hit.ar(h), Hit.i(h))

def t_out.put(+h: Hit) -> String:
  t_out.go(Hit.on(h), h)

def t_out(g: Gate, n: U32) -> String: t_out.put(rw(g, n))

# how many nodes the rewrite ADDED. PORT-INTERNAL, because Python's count is one
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

# THE GATE MOVED TO `gates/divandmod-gate.bend`.
