# divandmod.bend -- tinygrad/uop/divandmod.py.
#
# `div_and_mod_symbolic` is a three-entry `PatternMatcher`: two fast inline rules
# and `fold_divmod_general`. Upstream, four of the 109 lines are the matcher and
# eighty-nine are the big rule, so this file ports the matcher in full and the
# arms of `fold_divmod_general` it can reach, and the TODO block names every
# line of the rest with the wall behind it.
#
# the walls are half stale, and measured (2026-11-06). the header used to say "the one
# wall is `UOp._min_max`", and two of the three walls the TODO block named are gone:
#
#   * `divides` -- the port has it (`ops.bend:4157`), a full recursion over ADD/MUL/CONST
#     carrying a `Dv`, and it answers the same as upstream's on four measured cases.
#   * `_min_max` -- THE PORT HAS `F.UOp.vmin`/`F.UOp.vmax` AND THEY MATCH UPSTREAM'S ON
#     FIVE MEASURED CASES.
#   * `const_factor` -- THE PORT HAS IT (`ops.bend:3932`) AS A FULL GCD FOLD.
#
# what is actually left is scope and three shape problems, not missing primitives:
# `UOp.divide_exact` (which needs a multiset over `split_uop(MUL)` factors, and the port has
# no multiset and no `Map`), the cartesian product in `fold_divmod_congruence`, and the mutual
# recursion in `nest_by_factor`. the bodies are `F.Bnd` intervals rather than upstream's
# `PyConst`, so the arms' comparisons are over a `Maybe` bound.
#
# `fold_divmod_general` also RECURSES at :61 (`nest_by_factor` calls it on
# `x//div`), and Bend refuses mutual recursion, so even the shape of that rule is
# P3 and not only its arithmetic.
#
# FIVE DIVERGENCES, stated rather than hidden.
#   A. NO PROMOTION CASTs. Python's `UOp.__init__` runs `dtype_from_uop` and
#      `ops.bend`'s `UOp.new` does not, so the trees here are the ones Python
#      prints with CASTs erased. Same algebra, different node count -- which is
#      why no Python node count is a gate row and the `grown` rows are
#      PORT-INTERNAL.
#   B. NO SUB CANONICALISATION: `x - q*y` is `SUB` here and
#      `ADD(x, MUL(MUL(q,y), C(-1)))` in Python, because `symbolic.py`'s
#      `canonicalize` rewrites SUB. `out_r14`/`out_r16` are checked by VALUE.
#   C. NO CONSTANT FOLDING: `C(5)*C(3)` survives as a MUL here and `simplify()`
#      folds it in Python, so a folded MUL moves the `grown` count by one.
#   D. A NON-INT CONST IS NOT A `vmin`: `dm_val` reads `CInt` only, so rules 0 and
#      1 SKIP on a `CFloat` divisor where Python rewrites.
#   E. THE PORT's `UOp.gcd` ANSWERS A **BARE `CONST`** AND UPSTREAM's ANSWERS
#      AN **`EXPAND`**, BECAUSE UPSTREAM'S IS `uops[0].const_like(gcd)`
#      (ops.py:1037) AND A SIZED NODE's `const_like` IS AN `EXPAND`.  SO THE
#      PORT's `divide_by_gcd` ARM IS **OUT OF REACH** WHERE UPSTREAM's IS NOT,
#      AND THE PORT'S `factor_remainder` ARM IS **IN REACH** WHERE UPSTREAM'S
#      IS NOT -- **AND UPSTREAM'S `divide_by_gcd` ARM RAISES `AssertionError`
#      THERE**, MEASURED 2026-11-25.  THE DIVERGENCE IS **UPSTREAM'S BUG** AND
#      THE PORT's SHAPE IS THE ONE THAT DOES NOT CRASH.
#
# two things about the patterns that are easy to invert, both measured against the
# real `div_and_mod_symbolic`:
#
# 1. `Ops.ADD` IS COMMUTATIVE, so `UPat.cvar("c") + UPat.cvar("a")` is an `is_any`
#    over BOTH ORDERS -- `UPat.alu` (ops.py:1533) passes `list(asrc)` for an op in
#    `GroupOp.Commutative`. Both numerators are a TWO-WAY DISJUNCTION, and writing
#    one as a conjunction drops `r01` and `r08` and typechecks. `dm_which` is the
#    disjunction and `r01`/`r08` are its two-sided rows. Exactly one alternative
#    can ever match -- both sides cannot be a CONST and a `DIV(_, CONST)` at
#    once -- so no name is bound twice and there is not one identity check here.
# 2. the reject sets are not empty: `[ADD, CONST]`, `[ADD, CONST]`, `[]`, measured.
#    Rules 0 and 1 are `strict_length=True, required_len=2` and rule 2 is not, so a
#    THREE-src DIV falls to rule 2 and Python raises `ValueError` on
#    `x, y = d.src`. `r22` is that row: rule 2 still CLAIMS it, which is what
#    Python does before it raises.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# THE ACCUMULATOR. These rules GROW the arena, so the answer is the arena AND a
# node index AND whether anything fired. A `Maybe` cannot be a FOLD'S ACCUMULATOR (it is
# affine), and it is NOT true that it cannot be a `Data` field -- MEASURED, 20 in-tree
# `Data` records carry 38 `Maybe` fields. So the flag being a `U32` is NOT this reason; the
# independent one is below. The index is meaningless when the flag is 0, and
# 0 is the arena's BOTTOM node so it cannot serve as the sentinel either.
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

# `nested_div` -- divandmod.py:23-25.  `(x%(k*c))//c -> (x//c)%k`.
#
# AND IT IS **INSIDE** THE "Constant Denominator Rules" BLOCK AND SO IT IS
# **BEFORE** `remove_nested_mod` (divandmod.py:26), AND THE PORT's LADDER
# MUST KEEP THAT ORDER: `remove_nested_mod` IS A **MOD** ARM AND `nested_div`
# IS A **DIV** ARM, SO THEY DO NOT OVERLAP -- BUT THE ORDER IS UPSTREAM's AND
# THE PORT's LADDER FOLLOWS IT.
#
# AND IT IS **REACHABLE** AND MEASURED, AND THE ANSWER IS MEASURED ON CPYTHON
# AT THE PIN:
#   `(x%8)//4`  -> `MOD(DIV(x,c4),c2)`  -- AND `k` IS `8/4` = 2
#   `(x%8)//2`  -> `MOD(DIV(x,c2),c4)`
#   `(x%12)//4` -> `MOD(DIV(x,c4),c3)`
#   `(x%4)//2`  -> `MOD(DIV(x,c2),c2)`
#
# AND THE THREE FACTS UPSTREAM's LINE ASKS FOR (divandmod.py:23):
#   `d.op is Ops.DIV`   -- THE ROOT IS A DIVISION.
#   `x.op is Ops.MOD`   -- THE NUMERATOR IS A MODULATION.
#   `x.src[1].divides(c) IS NOT None` AND `k.vmin > 0` -- THE INNER MOD's
#     DIVISOR IS **DIVISIBLE BY** THE OUTER DIVISOR, AND THE QUOTIENT IS
#     **POSITIVE**.
#
# AND `divides` IS **THE PORT's `UOp.divides`**, WHICH ANSWERS UPSTREAM's SHAPE:
# A `Dv` WHOSE `ok` SAYS "DIVIDES" AND WHOSE `f` IS THE **QUOTIENT NODE**.
# MEASURED ON CPYTHON AT THE PIN: `c8.divides(4)` IS `CONST(2)`,
# `c8.divides(2)` IS `CONST(4)`, `c8.divides(3)` IS `None` AND
# `c8.divides(8)` IS `CONST(1)`.
#
# AND `k.vmin > 0` IS READ FROM THE **QUOTIENT NODE** AND NOT FROM A `vmin`
# FOLD, BECAUSE THE QUOTIENT IS A **CONST** AND A CONST's VALUE IS ITS `arg`.
# AND `k` IS `1` FOR `(x%8)//8` AND THE ARM STILL FIRES -- MEASURED: UPSTREAM
# ANSWERS `MOD(DIV(x,c8),c1)` -- BECAUSE UPSTREAM's TEST IS `k.vmin > 0` AND
# `1 > 0` IS TRUE.

# AND THE QUOTIENT, AND IT IS `x.src[1].divides(c)` WHERE `c` IS THE **OUTER**
# DIVISOR's VALUE.
def dm_nd.divides.go(ok: Bool, +d: O.Dv) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{O.Dv.f(d)}
    case False{}: None{}

def dm_nd.divides(+ar: O.Arena, +x: U32, c: H.I64) -> Maybe<&2, O.Found>:
  +d = O.UOp.divides(O.Arena.budget(ar), ar, c, O.Arena.src(ar, x, 1))
  dm_nd.divides.go(O.Dv.ok(d), d)

# AND THE OUTER DIVISOR's VALUE, AND IT IS A **CONST** AND NOT A VARIABLE --
# UPSTREAM's RULE IS INSIDE `if y.op is Ops.CONST and (c := y.val) > 0:`.
def dm_nd.cval(+ar: O.Arena, y: U32) -> H.I64:
  O.UOp.const_factor(O.Arena.budget(ar), ar, y)

def dm_nd.pos.go(isconst: Bool, v: H.I64) -> Bool:
  match isconst:
    case True{}: Bool.not(H.i64_is_zero(v))
    case False{}: False{}

# AND THE QUOTIENT IS POSITIVE, AND IT IS `k.vmin > 0` (divandmod.py:23).
def dm_nd.pos(+k: O.Found) -> Bool:
  dm_nd.pos.go(O.eq_op(O.Arena.op(O.Found.ar(k), O.Found.i(k)), O.OpsCONST{}),
               O.UOp.const_factor(O.Arena.budget(O.Found.ar(k)), O.Found.ar(k), O.Found.i(k)))

# AND THE ANSWER, AND IT IS `x.src[0] // y % k` (divandmod.py:23) -- **A DIV
# AND THEN A MOD**, AND NOT A MOD OF A DIV.
def dm_nd.answer(+ar: O.Arena, +x: U32, y: U32, +k: O.Found) -> O.Found:
  +q = O.UOp.alu(O.Found.ar(k), O.OpsDIV{}, [O.Arena.src0(ar, x), y])
  O.UOp.alu(O.Found.ar(q), O.OpsMOD{}, [O.Found.i(q), O.Found.i(k)])

def dm_nd.arm.go4(pos: Bool, +k: O.Found, +ar: O.Arena, +d: U32, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match pos:
    case True{}: Some{dm_nd.answer(O.Found.ar(k), x, y, k)}
    case False{}: None{}

def dm_nd.arm.go3(k: Maybe<&2, O.Found>, +ar: O.Arena, +d: U32, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match k:
    case Some{+kk}: dm_nd.arm.go4(dm_nd.pos(kk), kk, ar, d, x, y)
    case None{}: None{}

def dm_nd.arm.go2(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  +x = O.Arena.src0(ar, d)
  +y = O.Arena.src(ar, d, 1)
  +k = dm_nd.divides(ar, x, dm_nd.cval(ar, y))
  dm_nd.arm.go3(k, ar, d, x, y)

def dm_nd.arm.go1(ismod: Bool, +ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  match ismod:
    case True{}: dm_nd.arm.go2(ar, d)
    case False{}: None{}

def dm_nd.arm.go(isdiv: Bool, ismod: Bool, +ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  match isdiv:
    case True{}: dm_nd.arm.go1(ismod, ar, d)
    case False{}: None{}

# AND THE ARM, AND IT IS THE THREE FACTS AND THE ANSWER.
def dm_nd.arm(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  dm_nd.arm.go(O.eq_op(O.Arena.op(ar, d), O.OpsDIV{}),
               O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, d)), O.OpsMOD{}),
               ar, d)

# `remove_nested_mod in sum` -- divandmod.py:27-35.  `(a%4 + b)%2 -> (a+b)%2`.
#
# AND IT IS THE CLEANEST OF THE UNPORTED ARMS, AND THE REASON IS MEASURED:
# `fold_divmod_congruence` NEEDS THE CARTESIAN PRODUCT OF `itertools.product`
# OVER THE REMAINDER CHOICES, AND `nest_by_factor` RECURSES
# (`fold_divmod_general(x//div)`) AND BEND REFUSES MUTUAL RECURSION.  THIS ONE
# NEEDS `split_uop`, `divides` AND `usum`, AND THE PORT HAS THE FIRST TWO AND
# `usum` IS NOW IN `ops.bend`.
#
# AND THE THIRD WALL THIS PARAGRAPH ONCE NAMED IS **GONE**, AND IT IS GONE
# BECAUSE IT WAS **FALSE**: `UOp.divide_exact` NEEDS A MULTISET OVER
# `split_uop(MUL)` FACTORS AND THE PORT "HAS NO MULTISET" ✗ -- **AND THE PORT
# HAS ONE** ✓ (`Ctr` + `ctr_of` + `ctr_inter`, `ops.bend:3947-4016` ✓) AND
# `UOp.divide_exact` NOW **SUBTRACTS THE DIVISOR's FACTORS** ✓
# (`UOp.divide_exact.den.all`, `ops.bend:4386` ✓) BECAUSE UPSTREAM's
# `new_count` IS `Counter(num) - Counter(den)` ✓ (`ops.py:1044-1045` ✓) AND ITS
# TEST IS `all(v>=0 ...)` ✓ (`ops.py:1046` ✓).  MEASURED 2026-11-25: WITHOUT
# THAT HALF THE PORT ANSWERED `divide_exact(6x, y)` WITH A QUOTIENT WHERE
# UPSTREAM ANSWERS `None` ✓.
#
# AND THERE ARE **TWO** UNPORTED ARMS AND NOT THREE: UPSTREAM's `divandmod.py`
# HAS `fold_divmod_congruence` (`:42-49` ✓) AND `nest_by_factor` (`:51-65` ✓)
# AND **NO** `gcd_with_remainder` ✓ -- THE PORT's MARKER NAMED IT AND THE ARM
# WAS REMOVED UPSTREAM IN `7711bbac7` ("merge to fold_divmod_general",
# upstream PR #13359 ✓) ✓✓.  **A WORK QUEUE THAT NAMES WORK THAT IS NOT THERE
# IS A QUEUE THAT COUNTS WRONG** ✓.
#
# AND THE ARM IS FOUR FACTS, AND EACH IS A SEPARATE DEF SO A READER CAN SEE
# WHICH ONE IS FALSE:
#   * `d` IS A MOD (`divandmod.py:28`);
#   * `y` IS A CONST AND ITS VALUE IS **POSITIVE** (`divandmod.py:21`, THE
#     "CONSTANT DENOMINATOR RULES" PREFACE: "these rules strictly require y to
#     be a scalar constant > 0");
#   * EACH TERM `u` OF THE SUM IS A MOD WHOSE DIVISOR **DIVIDES** `c`
#     (`divandmod.py:29`), AND THEN THE TERM BECOMES ITS OWN **DIVIDEND**
#     (`u = u.src[0]`, `divandmod.py:30`);
#   * AND AT LEAST ONE TERM CHANGED (`divandmod.py:32`), OR THE ARM DOES NOT
#     FIRE.
#
# AND `pop_const` IS UPSTREAM'S `x.pop_const()` WITH ITS DEFAULT `op=Ops.ADD`
# (`ops.py:1029`): IT IS THE CONST ADDED ON THE RIGHT AND THE REMAINDER, AND
# THE PORT HAS IT AS `UOp.pop_const_node` (`ops.bend:4207`).
#
# AND THE ANSWER IS `(usum(new_xs) + const) % y` (`divandmod.py:33`), AND THE
# `+ const` IS AN ADD OF THE CONST TO THE SUM -- AND `const` IS **ZERO** WHEN
# `x` HAD NO CONST PART, AND UPSTREAM'S `identity_element(Ops.ADD, dt)` IS `0`
# (`ops.py:57`), SO THE PORT ADDS A ZERO CONST IN THAT CASE RATHER THAN
# SKIPPING THE ADD.  MEASURED: THE DENOTATION IS THE SAME EITHER WAY, AND THE
# PORT KEEPS THE ADD SO THE TREE MATCHES UPSTREAM's.

# AND THE TERMS, AND `split_uop(ADD)` IS UPSTREAM'S `x_peeled.split_uop(Ops.ADD)`
# (`divandmod.py:18`).
def dm_rnm.terms(+ar: O.Arena, x: U32) -> List<&2, U32>:
  # AND THE ARENA IS **THE PEELED NODE's OWN** AND NOT THE CALLER's, BECAUSE
  # `pop_const_node` GROWS THE ARENA AND THE CALLER's `+ar` BINDING IS THEN
  # STALE -- MEASURED 2026-11-24: THE TERMS CAME OUT IN THE WRONG ORDER
  # (`x, z, y` INSTEAD OF `x, y, z`) BECAUSE THE SPLIT READ A STALE ARENA.
  +px = O.UOp.pop_const_node(ar, x, O.OpsADD{})
  O.UOp.split_uop(O.Arena.budget(ar), ar, px, O.OpsADD{})

# AND THE CONST THAT CAME OFF `x`, AND IT IS THE **VALUE** AND NOT A NODE,
# BECAUSE `divandmod.py:33` ADDS IT AND `divandmod.py:21` COMPARES IT WITH
# ZERO.  MEASURED: `UOp.pop_const_val` READS THE `CInt` OF THE CONST SRC.
def dm_rnm.const.go(m: Maybe<&1, O.Const>) -> Maybe<&2, U32>:
  match m:
    case Some{v}: dm_val.go(v)
    case None{}: None{}

def dm_rnm.const(+ar: O.Arena, x: U32) -> Maybe<&2, U32>:
  dm_rnm.const.go(O.UOp.pop_const_val(ar, x, O.OpsADD{}))

# AND `u.src[1].divides(c)` -- `divandmod.py:29` -- AND IT IS THE PORT's
# `UOp.divides` WHICH ANSWERS UPSTREAM's SHAPE: A `Dv` WHOSE `ok` SAYS
# "DIVIDES" AND WHOSE `i` IS THE QUOTIENT NODE (`ops.bend:4182`).
def dm_rnm.divides(+ar: O.Arena, u: U32, c: H.I64) -> Bool:
  +d = O.UOp.divides(O.Arena.budget(ar), ar, c, O.Arena.src(ar, u, 1))
  O.Dv.ok(d)

# AND THE TERM BECOMES ITS OWN DIVIDEND, AND `changed` IS SET.  MEASURED: THE
# TWO ARE ONE FACT AND NOT TWO, BECAUSE THE ANSWER IS ONLY BUILT WHEN SOMETHING
# CHANGED (`divandmod.py:32`).
def dm_rnm.term.div.go(ok: Bool, +ar: O.Arena, u: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}: Some{O.Arena.src0(ar, u)}
    case False{}: None{}

def dm_rnm.term.div(+ar: O.Arena, +u: U32, c: H.I64) -> Maybe<&2, U32>:
  dm_rnm.term.div.go(dm_rnm.divides(ar, u, c), ar, u)

def dm_rnm.term(+ar: O.Arena, u: U32, c: H.I64, ismod: Bool) -> Maybe<&2, U32>:
  match ismod:
    case True{}: dm_rnm.term.div(ar, u, c)
    case False{}: None{}

# AND THE LIST OF TERMS, AND THE CHANGED FLAG, AND THEY ARE ONE RECORD BECAUSE
# A LIST AND A BOOL ARE TWO ANSWERS AND UPSTREAM'S LOOP CARRIES BOTH.
type Rnm is Data:
  Rnm{xs: List<&2, U32>, changed: Bool}

def Rnm.xs(x: Rnm) -> List<&2, U32>:
  match x:
    case Rnm{xs, changed}: xs

def Rnm.changed(x: Rnm) -> Bool:
  match x:
    case Rnm{xs, changed}: changed

# AND THE LOOP, AND IT IS A FOLD OVER THE TERMS WITH THE CHANGED FLAG AS THE
# ACCUMULATOR.
# AND THE FOLD IS ONE RECURSIVE DEF AND NOT TWO, BECAUSE BEND CHECKS DEFS IN
# FILE ORDER AND TWO RECURSIVE DEFS ARE MUTUAL RECURSION.  MEASURED: A FIRST
# DRAFT SPLIT IT INTO `dm_rnm.go` AND `dm_rnm.go.hit` AND THE SECOND CALLED
# THE FIRST, AND BEND SAID "a def whose body is implemented before the def is
# used".  **SO THE MATCH IS NOT THE RECURSIVE PART.**  THE HELPER RETURNS THE
# NEW TERM AND THE CHANGED FLAG, AND THE ONE FOLD CONSUMES THEM.
def dm_rnm.hit.go(m: Maybe<&2, U32>, u: U32) -> Rnm:
  match m:
    case Some{nu}: Rnm{[nu], True{}}
    case None{}: Rnm{[u], False{}}

def dm_rnm.hit(+ar: O.Arena, +u: U32, c: H.I64) -> Rnm:
  dm_rnm.hit.go(dm_rnm.term(ar, u, c, O.eq_op(O.Arena.op(ar, u), O.OpsMOD{})), u)

def dm_rnm.go(+ar: O.Arena, us: List<&2, U32>, +c: H.I64, +acc: Rnm) -> Rnm:
  match us:
    case Nil{}: acc
    case u <> t:
      +h = dm_rnm.hit(ar, u, c)
      dm_rnm.go(ar, t, c, Rnm{List.append(&2, U32, Rnm.xs(acc), Rnm.xs(h)),
                              Bool.or(Rnm.changed(h), Rnm.changed(acc))})

# AND THE ANSWER, `(usum(new_xs) + const) % y` -- `divandmod.py:33`.
def dm_rnm.const_of(+ar: O.Arena, const: Maybe<&2, U32>) -> O.Found:
  match const:
    case Some{v}: O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})
    case None{}: O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})

def dm_rnm.answer(+ar: O.Arena, xs: List<&2, U32>, const: Maybe<&2, U32>, y: U32) -> O.Found:
  +s = O.UOp.usum(ar, xs)
  +c = dm_rnm.const_of(O.Found.ar(s), const)
  +a = O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(s), O.Found.i(c)])
  O.UOp.alu(O.Found.ar(a), O.OpsMOD{}, [O.Found.i(a), y])

# AND THE ARM, AND IT IS THE LADDER OF THE FOUR FACTS.
def dm_rnm.put4(ch: Bool, +ar: O.Arena, r: Rnm, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match ch:
    case True{}: Some{dm_rnm.answer(ar, Rnm.xs(r), dm_rnm.const(ar, x), y)}
    case False{}: None{}

def dm_rnm.put3(+ar: O.Arena, cv: U32, +x: U32, y: U32) -> Maybe<&2, O.Found>:
  +r = dm_rnm.go(ar, dm_rnm.terms(ar, x), H.i64_of_i32(cv), Rnm{Nil{}, False{}})
  dm_rnm.put4(Rnm.changed(r), ar, r, x, y)

def dm_rnm.put2.go(pos: Bool, +ar: O.Arena, cv: U32, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match pos:
    case True{}: dm_rnm.put3(ar, cv, x, y)
    case False{}: None{}

def dm_rnm.put2(+ar: O.Arena, +d: U32, +cv: U32, +x: U32, y: U32) -> Maybe<&2, O.Found>:
  dm_rnm.put2.go(U32.is_gt(cv, 0), ar, cv, x, y)

def dm_rnm.put(+ar: O.Arena, +d: U32, op: O.Op, cy: Maybe<&2, U32>, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match op:
    case O.OpsMOD{}:
      match cy:
        case Some{cv}: dm_rnm.put2(ar, d, cv, x, y)
        case None{}: None{}
    case _: None{}

def dm_rnm(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  dm_rnm.put(ar, d, O.Arena.op(ar, d), dm_val(ar, O.Arena.src(ar, d, 1)),
             O.Arena.src0(ar, d), O.Arena.src(ar, d, 1))

# `divide_by_gcd` -- divandmod.py:72-77.  `x//y -> (x//gcd)//(y//gcd)`.
#
# AND THE **MOD HALF** IS THE SECOND ANSWER SHAPE AND NOT A VARIANT: UPSTREAM
# RETURNS `ret*gcd if d.op is Ops.MOD else ret` (divandmod.py:76), SO THE MOD's
# ANSWER IS THE RET MULTIPLIED BY THE GCD.  MEASURED 2026-11-24 ON CPYTHON AT
# THE PIN: `MOD(0, 2x)` ANSWERS `MUL(MOD(c0,MUL(x,c1)),c2)` AND `DIV(0, 2x)`
# ANSWERS `DIV(c0,MUL(x,c1))` -- **TWO DIFFERENT TREES FOR THE SAME GCD**, AND
# THE PORT's OWN `symbolic.bend` HAS **ONLY THE DIV HALF** (`dm_gcd_ret` BUILDS
# `O.OpsDIV{}` UNCONDITIONALLY), SO THE MOD HALF WAS MISSING THERE TOO.
#
# AND `simplify()` IS **NOT** NEEDED, AND THAT IS MEASURED: UPSTREAM CALLS
# `UOp.gcd(...).simplify()` AND THE PORT's `UOp.gcd` ALREADY ANSWERS
# UPSTREAM's SIMPLIFIED FORM -- MEASURED, ON `gcd(x, 2x)` UPSTREAM ANSWERS
# `(x*1.expand((4,)))` AND `simplify()` LEAVES IT ALONE, AND ON `gcd(0, 2x)`
# BOTH ANSWER `2`.  **SO THE `simplify` WALL IS MEASURED FALSE FOR THIS ARM.**
#
# AND `all_uops` IS `x`'s OWN ADD-SPLIT AND **NOT** THE PEELED ONE:
# `all_uops = list(x.split_uop(Ops.ADD))` (divandmod.py:70) AND THE COMMENT
# ABOVE IT SAYS "Reconstruct all uops including const for these checks" -- SO
# THE CONST IS IN AND `uops_no_const` (`:18`) IS NOT.

# AND THE TERMS, AND `y` IS THE LAST ONE.
def dm_dg_uops.go(+l: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match l:
    case Nil{}: acc
    case h <> t: dm_dg_uops.go(t, List.append(&2, U32, acc, [h]))

def dm_dg_uops(+ar: O.Arena, x: U32, y: U32) -> List<&2, U32>:
  dm_dg_uops.go(O.UOp.split_uop(O.Arena.budget(ar), ar, x, O.OpsADD{}),
               List.append(&2, U32, Nil{}, [y]))

# AND THE DIAGNOSTIC, AND IT IS TEMPORARY.
def dm_dg_diag_uops(+ar: O.Arena, x: U32, y: U32) -> U32:
  U32.from_nat(List.length(&2, U32, dm_dg_uops(ar, x, y)))

# AND THE GCD, AND THE PORT's `O.UOp.gcd` ANSWERS UPSTREAM's SHAPE.
def dm_dg_gcd(+ar: O.Arena, x: U32, y: U32) -> O.Found:
  O.UOp.gcd(ar, dm_dg_uops(ar, x, y))


# AND "THE GCD IS NOT ONE", AND UPSTREAM'S TEST IS `not (gcd.op is Ops.CONST and
# gcd.val==1)` (divandmod.py:74), AND THE PORT's OWN `dm_val` READS THE `CInt`
# AND IS WHAT THE TEST USES.
def dm_dg_is_one.go(isconst: Bool, v: Maybe<&2, U32>) -> Bool:
  match isconst:
    case True{}: U32.is_eq(dm_ival(v), 1)
    case False{}: False{}

def dm_dg_is_one(+ar: O.Arena, +g: U32) -> Bool:
  dm_dg_is_one.go(O.eq_op(O.Arena.op(ar, g), O.OpsCONST{}), dm_val(ar, g))

# AND THE QUOTIENT, AND `UOp.divide_exact` ANSWERS A `Dq` WHOSE `ok` IS "WE
# DIVIDED EXACTLY" (ops.py:1038, "WE AREN'T SURE" ANSWER AND NOT AN ERROR).
def dm_dg_quo.go(d: O.Dq, ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{O.Dq.f(d)}
    case False{}: None{}

def dm_dg_quo(+ar: O.Arena, num: U32, g: U32) -> Maybe<&2, O.Found>:
  +d = O.UOp.divide_exact(ar, num, g)
  dm_dg_quo.go(d, O.Dq.ok(d))

# AND THE RET, AND IT IS `x/gcd . op y/gcd` WITH THE **ROOT's OWN OP** -- AND
# THAT IS THE PART THE PORT's OWN `symbolic.bend` GOT WRONG, BECAUSE IT BUILT
# `O.OpsDIV{}` UNCONDITIONALLY.
def dm_dg_ret.put(+ar: O.Arena, ai: U32, b: Maybe<&2, O.Found>, op: O.Op) -> Maybe<&2, O.Found>:
  match b:
    case Some{fb}: Some{O.UOp.alu(ar, op, [ai, O.Found.i(fb)])}
    case None{}: None{}

def dm_dg_ret.go2(f: O.Found, b: Maybe<&2, O.Found>, op: O.Op) -> Maybe<&2, O.Found>:
  match f:
    case O.Found{ar, i}: dm_dg_ret.put(ar, i, b, op)

def dm_dg_ret.go(a: Maybe<&2, O.Found>, b: Maybe<&2, O.Found>, op: O.Op) -> Maybe<&2, O.Found>:
  match a:
    case Some{f}: dm_dg_ret.go2(f, b, op)
    case None{}: None{}

def dm_dg_ret(+ar: O.Arena, num: U32, den: U32, +g: U32, op: O.Op) -> Maybe<&2, O.Found>:
  dm_dg_ret.go(dm_dg_quo(ar, num, g), dm_dg_quo(ar, den, g), op)

# AND THE MOD's SECOND MULTIPLICATION, AND IT IS `ret*gcd` (divandmod.py:76).
def dm_dg_mul(+ar: O.Arena, +ret: O.Found, g: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(ret), O.OpsMUL{}, [O.Found.i(ret), g])

# AND THE ARM, AND IT IS THE GCD, THE "IS NOT ONE" TEST, AND THEN THE ANSWER
# IN THE ROOT's OWN SHAPE.
def dm_dg_arm.mod(ismod: Bool, +ar: O.Arena, +ret: O.Found, g: U32) -> Maybe<&2, O.Found>:
  match ismod:
    case True{}: Some{dm_dg_mul(O.Found.ar(ret), ret, g)}
    case False{}: Some{ret}

# AND A `Maybe` CANNOT BE A `+` BINDING -- IT IS NOT `Data` -- SO THE HIT IS
# SPLIT INTO TWO DEFS: ONE THAT MATCHES AND ONE THAT TAKES THE NODE.
def dm_dg_arm.hit2(+r: O.Found, ismod: Bool, +ar: O.Arena, g: U32) -> Maybe<&2, O.Found>:
  dm_dg_arm.mod(ismod, O.Found.ar(r), r, g)

def dm_dg_arm.hit(ret: Maybe<&2, O.Found>, ismod: Bool, +ar: O.Arena, g: U32) -> Maybe<&2, O.Found>:
  match ret:
    case Some{r}: dm_dg_arm.hit2(r, ismod, ar, g)
    case None{}: None{}

# AND THE ARENA IS **THE GCD's OWN** AND NOT THE CALLER's, AND THAT IS THE
# WHOLE BUG AND IT IS MEASURED: `O.UOp.gcd` GROWS THE ARENA AND ANSWERS IN THE
# GROWN ONE, SO A STALE `ar` READS THE ARENA's **BOTTOM NODE** -- AND THE
# BOTTOM NODE IS A NOOP, SO EVERY `Arena.op` READS "NOOP" AND EVERY
# `const_factor` ON AN ADD READS 1 INSTEAD OF ITS FACTORS.  MEASURED 2026-11-24:
# WITH A STALE ARENA THE WALK COLLECTED **ONE** NODE INSTEAD OF THREE AND
# `const_factor(2 + 2x)` ANSWERED **NOT 2**; WITH THE GCD's OWN ARENA IT
# ANSWERS 2 AND THE WALK COLLECTS THREE.
def dm_dg_arm.go(+ar: O.Arena, +d: U32, +g: O.Found, isone: Bool) -> Maybe<&2, O.Found>:
  match isone:
    case True{}: None{}
    case False{}:
      dm_dg_arm.hit(dm_dg_ret(ar, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1), O.Found.i(g),
                             O.Arena.op(ar, d)),
                    O.eq_op(O.Arena.op(ar, d), O.OpsMOD{}), ar, O.Found.i(g))

def dm_dg_arm(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  +g = dm_dg_gcd(ar, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1))
  dm_dg_arm.go(O.Found.ar(g), d, g, dm_dg_is_one(O.Found.ar(g), O.Found.i(g)))

# AND THE ARM THAT TAKES THE GCD's OWN FOUND, AND THE LADDER COMPUTES THE GCD
# **ONCE** BECAUSE BOTH THE `divide_by_gcd` ARM AND THE `factor_remainder` ARM
# READ NODES AND THE GCD **GROWS THE ARENA**.
def dm_dg_arm.g(+ar: O.Arena, +d: U32, +g: O.Found) -> Maybe<&2, O.Found>:
  dm_dg_arm.go(O.Found.ar(g), d, g, dm_dg_is_one(O.Found.ar(g), O.Found.i(g)))

# `factor_remainder` -- divandmod.py:78-91.  `(d*x+y)//d -> x+y//d`.
#
# AND IT IS THE **LAST** OF THE VARIABLE-DENOMINATOR RULES, AND IT IS THE ONE
# WITH THE MOST MOVING PARTS: TWO LISTS (`quo` AND `rem`), A `Maybe` FOR EACH
# TERM, AND A `vmin` OVER A SUM.
#
# AND **THE ARM IS REACHABLE** AND THAT IS MEASURED, AND THE MEASUREMENT CHANGES
# WHAT THE ARM's SHAPE IS.  MEASURED 2026-11-25 ON CPYTHON AT THE PIN:
# **THE DIVISOR MUST BE A VARIABLE AND NOT A CONST.**  UPSTREAM's OWN TEST
# SAYS SO: `test/null/test_uop_symbolic.py:584`
# `test_symbolic_factor_remainder_div` TESTS `(d*a+b)//d` WITH
# `d = Variable("d", 1, 10)` -- **A VARIABLE AND NOT A CONST.**  AND THE
# DIFFERENCE IS NOT COSMETIC:
#
#   * A CONST DIVISOR PUTS THE ARM BEHIND `divide_by_gcd` (divandmod.py:72-76),
#     WHOSE `gcd` IS `EXPAND(c1, c4)` -- **NOT** A `CONST` -- SO UPSTREAM's
#     GUARD `gcd.op is Ops.CONST and gcd.val==1` IS **FALSE** AND THE ARM
#     FIRES AND THEN `unwrap(x.divide_exact(gcd))` **RAISES**
#     `AssertionError`.  MEASURED: EVERY CONST-DIVISOR SHAPE I BUILT CRASHED
#     UPSTREAM (`DIV(2x+y,2)`, `DIV(3x+y,3)`, `DIV(6x+3,6)`, `MOD(2x+y,2)`,
#     AND EVERY CONST-ONLY NUMERATOR, WHICH THE `fold_divmod_congruence` ARM
#     CATCHES FIRST ANYWAY).
#   * A **VARIABLE** DIVISOR CONTRIBUTES NOTHING TO THE GCD, SO THE GCD IS
#     **1** -- AND A VARIABLE's `_shape` IS `()` (`UOp.variable` IS
#     `UOp(Ops.PARAM, src=(UOp(Ops.STACK),), ...)`, ops.py:973-975), SO
#     `x.const_like(0)` IS A **BARE `CONST 0`** AND NOT AN `EXPAND`.
#
# AND SO THE ARM's ANSWER, MEASURED ON CPYTHON AT THE PIN:
#   `(d*a+b)//d`   -> `ADD(DIV(ADD(ADD(c0,b),c0),d), ADD(c0,MUL(c1,a)))`
#   `(d*a+b)%d`    -> `MOD(ADD(ADD(c0,b),c0),d)`
#   `(d*a*20+b)//(5*d)` -> `ADD(DIV(ADD(ADD(c0,b),c0),MUL(d,c5)), ADD(c0,MUL(c4,a)))`
#
# AND **THE `sum` IS PYTHON's BUILTIN `sum` AND NOT `UOp.usum`**, AND THAT IS A
# DIFFERENCE WITH A VISIBLE ANSWER: PYTHON's `sum` STARTS WITH THE INT `0`,
# SO `sum([r0])` IS `ADD(c0, r0)`; `UOp.usum` (mixin/elementwise.py:40) STARTS
# WITH THE **FIRST ELEMENT**, SO IT IS `r0`.  UPSTREAM's `factor_remainder`
# USES THE BUILTIN (divandmod.py:89 `sum(rem)` AND :91 `sum(quo)`), AND THE
# `remove_nested_mod` ARM USES `UOp.usum` (divandmod.py:33) -- **TWO
# DIFFERENT SUMS IN ONE FILE**, AND THE PORT HAS BOTH.
#
# AND THE `quo`/`rem` LISTS ARE ONE RECORD BECAUSE UPSTREAM's LOOP CARRIES
# BOTH AND A TUPLE OF LISTS IS NOT A THING BEND HAS.

type Fr is Data:
  Fr{ar: O.Arena, quo: List<&2, U32>, rem: List<&2, U32>}

def Fr.ar(x: Fr) -> O.Arena:
  match x:
    case Fr{ar, quo, rem}: ar

def Fr.quo(x: Fr) -> List<&2, U32>:
  match x:
    case Fr{ar, quo, rem}: quo

def Fr.rem(x: Fr) -> List<&2, U32>:
  match x:
    case Fr{ar, quo, rem}: rem

# AND THE TERMS, AND IT IS `list(x.split_uop(Ops.ADD))` (divandmod.py:70) --
# **THE NUMERATOR's OWN ADD TERMS AND NOT THE `divide_by_gcd` LIST.**  THE
# `divide_by_gcd` ARM'S LIST IS `UOp.gcd(*all_uops, y)` (divandmod.py:73) AND
# SO IT **APPENDS `y`**, AND `factor_remainder` READS THE **SAME** `all_uops`
# (divandmod.py:81) **WITHOUT** THE `y`.  THE PORT HAS BOTH AND THE TWO ARE
# DIFFERENT FUNCTIONS: `dm_dg_uops` APPENDS `y` AND `dm_fr_terms` DOES NOT.
def dm_fr_terms.go(+l: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match l:
    case Nil{}: acc
    case h <> t: dm_fr_terms.go(t, List.append(&2, U32, acc, [h]))

def dm_fr_terms(+ar: O.Arena, x: U32) -> List<&2, U32>:
  dm_fr_terms.go(O.UOp.split_uop(O.Arena.budget(ar), ar, x, O.OpsADD{}), Nil{})

# AND PYTHON's `sum`, AND IT STARTS WITH THE INT `0`, AND THE INT BECOMES A
# `CONST 0` NODE THROUGH `ufix` (ops.py:579-580).
def dm_fr.sum.go(+l: List<&2, U32>, +acc: O.Found) -> O.Found:
  match l:
    case Nil{}: acc
    case h <> t: dm_fr.sum.go(t, O.UOp.alu(O.Found.ar(acc), O.OpsADD{}, [O.Found.i(acc), h]))

# AND THE FIRST TERM, AND PYTHON's `sum` STARTS WITH THE INT `0` AND SO THE
# FIRST TERM IS `ADD(c0, r0)` AND **NOT** `r0` -- AND THE EMPTY LIST IS THE
# BARE `c0`.  MEASURED 2026-11-25: A FIRST DRAFT FOLDED FROM THE `c0` AND
# ANSWERED `ADD(c0,c0)` FOR AN EMPTY LIST, AND THE PORT ANSWERED
# `ADD(c0,ADD(c0,c0))` WHERE UPSTREAM ANSWERS `ADD(c0,MUL(c1,a))`.
def dm_fr.sum.first(+l: List<&2, U32>, +z: O.Found) -> O.Found:
  match l:
    case Nil{}: z
    case h <> t: dm_fr.sum.go(t, O.UOp.alu(O.Found.ar(z), O.OpsADD{}, [O.Found.i(z), h]))

def dm_fr.sum(+ar: O.Arena, l: List<&2, U32>) -> O.Found:
  dm_fr.sum.first(l, O.UOp.const(ar, O.CInt{H.i64_of_i32(0)}))

# AND THE ZERO TERM, AND IT IS `x.const_like(0)` (divandmod.py:89) -- AND FOR A
# VARIABLE's NUMERATOR THE `_shape` IS `()` SO IT IS A **BARE `CONST 0`** AND
# NOT AN `EXPAND` (ops.py:572-574: `ret._mop(Ops.EXPAND, arg=self._shape) if
# self._shape and ...` -- AND `self._shape` IS FALSY FOR `()`).
def dm_fr.zero(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})

# AND THE `quo` TERM OF THE CONSTANT BRANCH, AND IT IS
# `u.divides(c)*(c//y.val)` FOR A DIV AND `u.const_like(0)` FOR A MOD
# (divandmod.py:85) -- **A MULTIPLICATION** -- AND THE FIRST DRAFT BUILT A
# **DIVISION**, AND MEASURED 2026-11-25 ON `(6a+b)//4` THE PORT ANSWERED A DEEP
# `ADD(c0, ADD(c0, ... ADD(c0,Pb),Pb)...)` NEST WHERE UPSTREAM ANSWERS
# `ADD(DIV(ADD(ADD(ADD(c0,MUL(MUL(a,c1),c2)),b),c0),c4),ADD(c0,MUL(MUL(a,c1),c1)))`.
def dm_fr.quo_of.go(isdiv: Bool, +ar: O.Arena, +d: O.Dv, c: H.I64, +y: H.I64) -> O.Found:
  match isdiv:
    case True{}:
      +cc = O.UOp.const(ar, O.CInt{H.i64_div(c, y)})
      O.UOp.alu(O.Found.ar(cc), O.OpsMUL{}, [O.Found.i(O.Dv.f(d)), O.Found.i(cc)])
    case False{}: dm_fr.zero(ar)

def dm_fr.quo_of(+ar: O.Arena, +d: O.Dv, c: H.I64, +y: H.I64, isdiv: Bool) -> O.Found:
  dm_fr.quo_of.go(isdiv, ar, d, c, y)

# AND THE `rem` TERM OF THE CONSTANT BRANCH, AND IT IS `u.divides(c)*(c%y.val)`
# (divandmod.py:84).
#
# AND `d`'s QUOTIENT INDEX IS READ IN `ar`, AND THAT IS CORRECT BECAUSE `ar`
# **CONTAINS** THE ARENA `UOp.divides` ANSWERED IN: AN ARENA IS APPEND-ONLY,
# SO A DESCENDANT READS EVERY ANCESTOR's INDEX AS THE SAME NODE.
def dm_fr.rem_of(+ar: O.Arena, +d: O.Dv, c: H.I64, +y: H.I64) -> O.Found:
  +cc = O.UOp.const(ar, O.CInt{H.i64_mod(c, y)})
  O.UOp.alu(O.Found.ar(cc), O.OpsMUL{}, [O.Found.i(O.Dv.f(d)), O.Found.i(cc)])

# AND THE **ARENA** IS **ONE CHAIN** AND NOT A TREE OF BRANCHES: EVERY NODE IS
# BUILT FROM THE PREVIOUS NODE's ARENA AND THE RECORD's ARENA IS THE **LAST**
# ONE.  MEASURED 2026-11-25: WITH THE `quo` TERM AND THE `rem` TERM BUILT IN
# **TWO BRANCHES** OF ONE ARENA THEY READ EACH OTHER's INDICES, AND AN INDEX
# THAT IS OUT OF RANGE READS THE ARENA's **BOTTOM NOOP NODE** -- AND THE PORT
# ANSWERED A DEEP NOOP CHAIN WHERE UPSTREAM ANSWERS A TREE.  THE PLANT's
# CASE 12 IS THIS RULE.
def dm_fr.term.go7(ok: Bool, +d: O.Dv, +ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isdiv: Bool, +acc: Fr, +cf: H.I64) -> Fr:
  match ok:
    case True{}:
      +q = dm_fr.quo_of(ar, d, cf, yv, isdiv)
      +r = dm_fr.rem_of(O.Found.ar(q), d, cf, yv)
      Fr{O.Found.ar(r), List.append(&2, U32, Fr.quo(acc), [O.Found.i(q)]),
                       List.append(&2, U32, Fr.rem(acc), [O.Found.i(r)])}
    case False{}: Fr{ar, Fr.quo(acc), List.append(&2, U32, Fr.rem(acc), [u])}

# AND THE ARENA IS **THE DIVIDES's OWN** AND NOT THE CALLER's, BECAUSE
# `UOp.divides` GROWS THE ARENA AND ANSWERS IN THE GROWN ONE, AND A STALE
# `ar` READS THE ARENA's **BOTTOM NOOP NODE**.
def dm_fr.term.go6(+ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isdiv: Bool, +acc: Fr, +cf: H.I64) -> Fr:
  +d = O.UOp.divides(O.Arena.budget(ar), ar, cf, u)
  dm_fr.term.go7(O.Dv.ok(d), d, O.Found.ar(O.Dv.f(d)), u, y, yv, isdiv, acc, cf)

def dm_fr.term.go5(equal: Bool, +ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isdiv: Bool, +acc: Fr, +cf: H.I64) -> Fr:
  match equal:
    case True{}: Fr{ar, Fr.quo(acc), List.append(&2, U32, Fr.rem(acc), [u])}
    case False{}: dm_fr.term.go6(ar, u, y, yv, isdiv, acc, cf)

# AND THE CONSTANT BRANCH's OWN TEST, AND IT IS `(c:=u.const_factor())%y.val!=c`
# -- SO THE CONST FACTOR MUST NOT DIVIDE THE DIVISOR.
def dm_fr.term.go4(+ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isdiv: Bool, +acc: Fr) -> Fr:
  +cf = O.UOp.const_factor(O.Arena.budget(ar), ar, u)
  dm_fr.term.go5(Cmp.is_eq(H.i64_cmp(H.i64_mod(cf, yv), cf)), ar, u, y, yv, isdiv, acc, cf)

def dm_fr.term.go3(+isconst: Bool, +ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isdiv: Bool, +acc: Fr) -> Fr:
  match isconst:
    case True{}: dm_fr.term.go4(ar, u, y, yv, isdiv, acc)
    case False{}: Fr{ar, Fr.quo(acc), List.append(&2, U32, Fr.rem(acc), [u])}

def dm_fr.term.go2(ok: Bool, +dq: O.Dq, +ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isconst: Bool, +isdiv: Bool, +acc: Fr) -> Fr:
  match ok:
    case True{}: Fr{ar, List.append(&2, U32, Fr.quo(acc), [O.Found.i(O.Dq.f(dq))]), Fr.rem(acc)}
    case False{}: dm_fr.term.go3(isconst, ar, u, y, yv, isdiv, acc)

# AND THE TERM's FATE, AND IT IS ONE OF THREE AND UPSTREAM's ORDER IS: THE
# EXACT DIVISION FIRST, THEN THE CONSTANT BRANCH, THEN `rem`.
def dm_fr.term.go(+ar: O.Arena, +u: U32, +y: U32, +yv: H.I64, +isconst: Bool, +isdiv: Bool, +acc: Fr) -> Fr:
  +dq = O.UOp.divide_exact(ar, u, y)
  dm_fr.term.go2(O.Dq.ok(dq), dq, O.Found.ar(O.Dq.f(dq)), u, y, yv, isconst, isdiv, acc)

# AND THE LOOP, AND IT IS A FOLD OVER THE TERMS WITH THE `quo`/`rem` RECORD AS
# THE ACCUMULATOR.
def dm_fr.go(+us: List<&2, U32>, +y: U32, +yv: H.I64, +isconst: Bool, +isdiv: Bool, +acc: Fr) -> Fr:
  match us:
    case Nil{}: acc
    case u <> t:
      +n = dm_fr.term.go(Fr.ar(acc), u, y, yv, isconst, isdiv, acc)
      dm_fr.go(t, y, yv, isconst, isdiv, n)

# AND THE ANSWER, AND IT IS `new_x%y` FOR A MOD AND `new_x//y+sum(quo)` FOR A
# DIV (divandmod.py:91) -- **AND THE `sum(quo)` IS NOT OPTIONAL**, AND A FIRST
# DRAFT DROPPED IT AND THE PORT ANSWERED A DIFFERENT TREE.
def dm_fr.answer.go(isdiv: Bool, +ar: O.Arena, +nx: O.Found, +quo: List<&2, U32>, y: U32) -> Maybe<&2, O.Found>:
  match isdiv:
    case True{}:
      +q = dm_fr.sum(O.Found.ar(nx), quo)
      +dv = O.UOp.alu(O.Found.ar(q), O.OpsDIV{}, [O.Found.i(nx), y])
      Some{O.UOp.alu(O.Found.ar(dv), O.OpsADD{}, [O.Found.i(dv), O.Found.i(q)])}
    case False{}:
      Some{O.UOp.alu(O.Found.ar(nx), O.OpsMOD{}, [O.Found.i(nx), y])}

def dm_fr.answer(+ar: O.Arena, +nx: O.Found, +quo: List<&2, U32>, y: U32, isdiv: Bool) -> Maybe<&2, O.Found>:
  dm_fr.answer.go(isdiv, ar, nx, quo, y)

# AND `y`'s VALUE, AND IT IS THE CONST's AND NOT A `Maybe` -- AND FOR A
# **VARIABLE** DIVISOR IT IS **NOT A CONST AT ALL**, SO `y.op is Ops.CONST` IS
# **FALSE** AND THE CONSTANT BRANCH OF THE ARM NEVER FIRES.  THAT IS EXACTLY
# WHY A VARIABLE DIVISOR REACHES THE ARM AT ALL.
def dm_fr.yval(+ar: O.Arena, y: U32) -> H.I64:
  O.UOp.const_factor(O.Arena.budget(ar), ar, y)

# AND THE `vmin` GUARD, AND IT IS `y.vmin<0 or x.vmin<0` (divandmod.py:79).
def dm_fr.neg3(b: F.Bnd) -> Bool:
  match b:
    case F.BndInt{neg, mag}: neg
    case _: False{}

def dm_fr.neg2(m: Maybe<&2, F.Bnd>) -> Bool:
  match m:
    case Some{b}: dm_fr.neg3(b)
    case None{}: False{}

# AND THE ARENA IS **THE TABLE's OWN** AND NOT THE CALLER's, BECAUSE
# `F.UOp.fold(ar)` GROWS THE ARENA AND ANSWERS IN THE GROWN ONE, AND A STALE
# `ar` READS THE ARENA's **BOTTOM NOOP NODE** -- AND THE `vmin` OF A NOOP IS
# **NOT NEGATIVE**, SO A STALE ARENA **SILENTLY PASSES THE GUARD**.  THIS IS
# MEASURED: THE FIRST DRAFT READ `F.UOp.vmin(ar, F.UOp.fold(ar), u)` AND THE
# PORT ANSWERED A STACK OF `DIV(c2,c2)` NODES.
def dm_fr.neg(+ar: O.Arena, u: U32) -> Bool:
  +fx = F.folded(ar)
  dm_fr.neg2(F.UOp.vmin(F.Folded.ar(fx), F.mm.sweep(F.Folded.ar(fx), F.Folded.t(fx)), u))

# AND THE `new_x.vmin<0` GUARD (divandmod.py:90), AND IT IS OVER THE **SUM**,
# SO IT NEEDS THE SUM's NODE.
def dm_fr.nxneg(+ar: O.Arena, +nx: O.Found) -> Bool:
  +fx = F.folded(O.Found.ar(nx))
  dm_fr.neg2(F.UOp.vmin(F.Folded.ar(fx), F.mm.sweep(F.Folded.ar(fx), F.Folded.t(fx)), O.Found.i(nx)))

def dm_fr.arm4(neg: Bool, +ar: O.Arena, +d: U32, +acc: Fr, y: U32, +nx: O.Found) -> Maybe<&2, O.Found>:
  match neg:
    case True{}: None{}
    case False{}: dm_fr.answer(O.Found.ar(nx), nx, Fr.quo(acc), y, O.eq_op(O.Arena.op(ar, d), O.OpsDIV{}))

# AND THE `new_x` SUM, AND IT IS `sum(rem)+x.const_like(0)` (divandmod.py:89).
def dm_fr.arm3(+ar: O.Arena, +d: U32, +acc: Fr, y: U32, x: U32) -> Maybe<&2, O.Found>:
  +s = dm_fr.sum(Fr.ar(acc), Fr.rem(acc))
  +z = dm_fr.zero(O.Found.ar(s))
  +nx = O.UOp.alu(O.Found.ar(z), O.OpsADD{}, [O.Found.i(s), O.Found.i(z)])
  dm_fr.arm4(dm_fr.nxneg(O.Found.ar(nx), nx), ar, d, acc, y, nx)

def dm_fr.arm2(noquo: Bool, +ar: O.Arena, +d: U32, +acc: Fr, y: U32, x: U32) -> Maybe<&2, O.Found>:
  match noquo:
    case True{}: None{}
    case False{}: dm_fr.arm3(ar, d, acc, y, x)

def dm_fr.arm.go2(+ar: O.Arena, +d: U32, +x: U32, +y: U32) -> Maybe<&2, O.Found>:
  +yv = dm_fr.yval(ar, y)
  +isconst = O.eq_op(O.Arena.op(ar, y), O.OpsCONST{})
  +terms = dm_fr_terms(ar, x)
  +acc = dm_fr.go(terms, y, yv, isconst,
                  O.eq_op(O.Arena.op(ar, d), O.OpsDIV{}), Fr{ar, Nil{}, Nil{}})
  dm_fr.arm2(U32.is_zero(U32.from_nat(List.length(&2, U32, Fr.quo(acc)))), ar, d, acc, y, x)

def dm_fr.arm.go1(neg: Bool, +ar: O.Arena, +d: U32, x: U32, y: U32) -> Maybe<&2, O.Found>:
  match neg:
    case True{}: None{}
    case False{}: dm_fr.arm.go2(ar, d, x, y)

def dm_fr.arm.go(xneg: Bool, yneg: Bool, +ar: O.Arena, +d: U32, x: U32, y: U32) -> Maybe<&2, O.Found>:
  dm_fr.arm.go1(Bool.or(xneg, yneg), ar, d, x, y)

# AND THE ARM, AND IT IS THE `y.vmin<0 OR x.vmin<0` GUARD, THE TERMS, THE
# `quo`/`rem` SPLIT, THE `if not quo` GUARD, THE `new_x` SUM, THE
# `new_x.vmin<0` GUARD, AND THE ANSWER.
def dm_fr.arm(+ar: O.Arena, +d: U32, +x: U32, +y: U32) -> Maybe<&2, O.Found>:
  dm_fr.arm.go(dm_fr.neg(ar, x), dm_fr.neg(ar, y), ar, d, x, y)

# ---- THE CONSTANT DENOMINATOR -- divandmod.py:19-21.
#
# AND THE WHOLE "** Constant Denominator Rules **" BLOCK (divandmod.py:19-70)
# IS INSIDE `if y.op is Ops.CONST and (c := y.val) > 0:` (divandmod.py:21), AND
# SO THE TWO ARMS BELOW INHERIT THAT GUARD AND MUST **NOT** ANSWER A VARIABLE
# DIVISOR.
#
# AND `c` IS READ BY `UOp.const_factor` (ops.py:1014-1017), WHICH ANSWERS A
# CONST's VALUE AND **1** FOR EVERYTHING ELSE -- SO THE `y.op is Ops.CONST` TEST
# IS SEPARATE AND NOT INFERRED FROM THE VALUE.
#
# AND THE VALUES ARE **U32** AND NOT `H.I64`, AND THE REASON IS MEASURED: A
# PLAIN PARAMETER IS **CONSUMED ONCE** IN BEND (MEASURED: "a (consumed more than
# once)"), AND THE DIVISOR IS READ IN SEVEN PLACES.  A `+` PARAMETER MAY BE
# READ MANY TIMES.  AND THE CONST's VALUE IS TRUNCATED TO 32 BITS BY `H.lo32` --
# WHICH IS WHAT `dm_val.go` ALREADY DOES FOR EVERY CONST IN THIS FILE -- AND
# THE PORT's OWN FLOOR HELPERS (`dm_floordiv`, `dm_floormod`, ABOVE) ARE 32-BIT
# AND TAKE `U32`s.
def dm_cd.isconst(+ar: O.Arena, +y: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, y), O.OpsCONST{})

def dm_cd.cval(+ar: O.Arena, +y: U32) -> U32:
  H.lo32(O.UOp.const_factor(O.Arena.budget(ar), ar, y))

def dm_cd.ok2(isconst: Bool, +c: U32) -> Bool:
  Bool.and(isconst, Bool.and(Bool.not(H.i32_is_neg(c)), Bool.not(U32.is_zero(c))))

def dm_cd.ok(+ar: O.Arena, +y: U32) -> Bool:
  dm_cd.ok2(dm_cd.isconst(ar, y), dm_cd.cval(ar, y))

# AND THE PEELED CONST, AND IT IS `x.pop_const()`'s SECOND HALF
# (divandmod.py:16) -- AND `UOp.pop_const_val` ANSWERS `None` WHEN NOTHING WAS
# PEELED, WHICH IS UPSTREAM's `identity_element(Ops.ADD, dt)` = **0**
# (ops.py:57).
def dm_pc.cv.go(c: O.Const) -> U32:
  match c:
    case O.CInt{i}: H.lo32(i)
    case _: 0

def dm_pc.cv(m: Maybe<&1, O.Const>) -> U32:
  match m:
    case Some{c}: dm_pc.cv.go(c)
    case None{}: 0

# ---- `exact division keeps the structure of x` -- divandmod.py:35-36.
# `(q*c+k)//c -> q+k//c`.
#
# AND IT IS **NOT** IN THE PORT's WORK QUEUE, AND THAT IS A DEFECT THIS SECTION
# FIXES: THE TODO BLOCK NAMED `:38-49` AND `:51-65` AND **NOTHING FOR `:36`**,
# SO THE ARM WAS MISSING **AND NOT EVEN COUNTED** -- AND A QUEUE THAT DOES NOT
# COUNT AN ARM IS A QUEUE THAT COUNTS WRONG.
#
# AND THE THREE FACTS UPSTREAM's LINE ASKS FOR (divandmod.py:36):
#   `d.op is Ops.DIV` -- THE ROOT IS A DIVISION.
#   `x_peeled.divides(c) IS NOT None` -- THE PEELED NUMERATOR IS EXACTLY
#     DIVISIBLE BY THE CONSTANT DIVISOR.
#   `const//c` -- AND IT IS A **FLOOR** DIVISION.
#
# AND THE ANSWER IS `q + const//c` (divandmod.py:36) AND `q` IS A **UOP** AND
# `const//c` IS AN **INT**, SO THE INT IS THE **SECOND** SRC OF THE ADD
# (elementwise.py:83 `add` -> `_broadcasted(x, reverse=False)` -> `lhs.alu(op,
# rhs)`) -- AND THAT IS THE **OPPOSITE** ORDER FROM `int + uop`.
def dm_ex.quot.go(ok: Bool, +d: O.Dv) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{O.Dv.f(d)}
    case False{}: None{}

# AND THE QUOTIENT, AND IT IS `x_peeled.divides(c)` (divandmod.py:36) -- AND THE
# PORT's `UOp.divides` ANSWERS UPSTREAM's SHAPE: A `Dv` WHOSE `ok` SAYS
# "DIVIDES" AND WHOSE `f` IS THE **QUOTIENT NODE**.
def dm_ex.quot(+ar: O.Arena, +px: U32, +c: U32) -> Maybe<&2, O.Found>:
  +d = O.UOp.divides(O.Arena.budget(ar), ar, H.i64_of_i32(c), px)
  dm_ex.quot.go(O.Dv.ok(d), d)

# AND THE ANSWER, AND IT IS `q + const//c` -- A UOP PLUS AN INT, SO THE INT IS
# THE **SECOND** SRC.
def dm_ex.answer(+ar: O.Arena, +q: O.Found, +cv: U32, +c: U32) -> O.Found:
  +cc = O.UOp.const(O.Found.ar(q), O.CInt{H.i64_of_i32(dm_floordiv(cv, c))})
  O.UOp.alu(O.Found.ar(cc), O.OpsADD{}, [O.Found.i(q), O.Found.i(cc)])

def dm_ex.arm.go2(q: Maybe<&2, O.Found>, +ar: O.Arena, +cv: U32, +c: U32) -> Maybe<&2, O.Found>:
  match q:
    case Some{+qq}: Some{dm_ex.answer(O.Found.ar(qq), qq, cv, c)}
    case None{}: None{}

def dm_ex.arm.go3(ok: Bool, q: Maybe<&2, O.Found>, +ar: O.Arena, +cv: U32, +c: U32) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dm_ex.arm.go2(q, ar, cv, c)
    case False{}: None{}

def dm_ex.arm.go1(isdiv: Bool, ok: Bool, +ar: O.Arena, +px: U32, +cv: U32, +c: U32) -> Maybe<&2, O.Found>:
  match isdiv:
    case True{}: dm_ex.arm.go3(ok, dm_ex.quot(ar, px, c), ar, cv, c)
    case False{}: None{}

# AND THE ARM, AND IT IS THE CONSTANT DENOMINATOR's GUARD, THE `d.op is Ops.DIV`
# TEST, THE `divides` TEST AND THE ANSWER -- AND `x_peeled` IS
# `x.pop_const()` (divandmod.py:16) WHICH THE PORT HAS AS `UOp.pop_const_node`.
def dm_ex.arm(+ar: O.Arena, +d: U32, +x: U32, +y: U32) -> Maybe<&2, O.Found>:
  +c = dm_cd.cval(ar, y)
  +cv = dm_pc.cv(O.UOp.pop_const_val(ar, x, O.OpsADD{}))
  +px = O.UOp.pop_const_node(ar, x, O.OpsADD{})
  dm_ex.arm.go1(O.eq_op(O.Arena.op(ar, d), O.OpsDIV{}),
                dm_cd.ok2(dm_cd.isconst(ar, y), c), ar, px, cv, c)

# `fold_divmod_general` -- divandmod.py:8-96. The `raise` is line 11 and it comes
def fold_divmod_general.go(+ar: O.Arena, +d: U32, zero: Bool) -> Maybe<&2, O.Found>:
  match zero:
    case True{}: None{}
    case False{}:
      +g = dm_dg_gcd(ar, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1))
      dm_first2.go(dm_point(ar, d), dm_first2.go(dm_multiple_of.arm(ar, d),
                     dm_first2.go(dm_nd.arm(ar, d),
                       dm_first2.go(dm_rnm(ar, d),
                         dm_first2.go(dm_ex.arm(ar, d, O.Arena.src0(ar, d), O.Arena.src(ar, d, 1)),
                           dm_first2.go(dm_dg_arm.g(O.Found.ar(g), d, g),
                                       dm_fr.arm(O.Found.ar(g), d, O.Arena.src0(O.Found.ar(g), d),
                                                 O.Arena.src(O.Found.ar(g), d, 1))))))))

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

#  1. Fast Inline Rules , rule 1 -- divandmod.py:98-100.
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

#  2. Slow Rules  -- divandmod.py:103, the one entry. The weakint conjunct is
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

#   nrules=3       divandmod.py:93-104 is three entries. A COUNT.
#   rej0=2 rej1=2 rej2=0   the `early_reject` sets, MEASURED against Python:
#   nroots=26      how many roots the fixture arena holds. THE COUNT ROW: a
#   zero_r04=1     divandmod.py:11 on a `CONST(0)` divisor. Python RAISES.
#   on_r13=1 out_r13=CONST(1)          `6//4`, divandmod.py:13's CONST/CONST arm.
#   out_r17=CONST(0)   divandmod.py:15: `Pp.multiple_of == 4` and `4 % 4 == 0`,
#   out_r18=CONST(0)   THE DEFAULT ROW: `Pz.multiple_of` is 1 (ops.py:1013) and
#   out_r19=DIV(DIV(Pp,CONST(4)),CONST(1))   `Pp//4`: THE **NEW** ARM
#     (`divide_by_gcd`, divandmod.py:72-77) ANSWERS IT, AND IT ANSWERED `none`
#     BEFORE THE ARM EXISTED.  **AND THE ROW IS PORT-ONLY AND UPSTREAM CANNOT
#     COMPUTE IT**: MEASURED 2026-11-24, THE FIXTURE's `Pp` IS A PARAM WITH
#     **NO SRCS**, AND UPSTREAM's `gcd` CALLS `uops[0].const_like(...)` WHICH
#     NEEDS A SHAPE, AND `_shape` ON A SRC-LESS PARAM **RAISES** `IndexError`
#     (ops.py:351 ASSERTS `len(self.src[0].as_shape) <= 1`).  **AND THE
#     PORT's GCD IS 4 AND NOT 1** BECAUSE THE PORT's `const_factor` READS A
#     PARAM's `multiple_of` (ops.bend:3891) AND UPSTREAM's `const_factor` FOR A
#     PARAM IS **1** (ops.py:1020) -- **AND `multiple_of` DOES NOT EXIST AT THE
#     PIN AT ALL** (MEASURED: `git show f5ac54685074:tinygrad/uop/ops.py | grep
#     -c multiple_of` ANSWERS **0**).  SO THE ARM FIRES HERE AND NOT UPSTREAM.
#     THE **DIFFERENTIAL** ROWS ARE ON SIZED PARAMs, WHERE UPSTREAM ANSWERS.
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
# TODO(p3) divandmod.py:15-17  symbol=fold_divmod_general  `# split uops for the rest of the processing` --
# TODO(p3) divandmod.py:13-15  symbol=fold_divmod_general  a FLOAT CONST -- `_min_max` returns PyConst and
#  Constant Denominator Rules  -- divandmod.py:21-70. These rules strictly
# DONE(p3) divandmod.py:23-25 `nested_div: (x%(k*c))//c -> (x//c)%k (requires k>0);
#   `x.src[1].divides(c)`. THE WALL THIS NAMED IS MEASURED FALSE (2026-11-06): `divides` IS
#   MEASURED CASES -- `(x*4).divides(4)` IS `MUL(x, 1)`, `(x*4+8).divides(4)` IS
#   PORTED (2026-11-25) AS `dm_nd.*`, AND IT NEEDS `divides` **ALONE**: `k` IS
#   `x.src[1].divides(c)` AND IT IS A **CONST** QUOTIENT, SO `k.vmin > 0` IS A CONST's
#   VALUE AND NOT A `vmin` FOLD.  **AND THE ARM IS **BEFORE** `remove_nested_mod`**
#   (divandmod.py:23 vs :26) AND THE PORT's LADDER KEEPS THAT ORDER.  **AND `k = 1`
#   STILL FIRES**, BECAUSE UPSTREAM's TEST IS `k.vmin > 0` AND `1 > 0` IS TRUE --
#   MEASURED 2026-11-25: UPSTREAM ANSWERS `MOD(DIV(x,c8),c1)`.
#   THE ROWS ARE `gates/divandmod-cases.rows`'s FIVE `nd_*` ROWS AND THE PLANT's
#   CASE 10 PROVES THE POSITIVE-QUOTIENT GUARD IS LOAD-BEARING.
# DONE(p3) divandmod.py:27-35 `remove_nested_mod in sum: (a%4 + b)%2 -> (a+b)%2` --
# DONE(p3) divandmod.py:72-77  symbol=fold_divmod_general  `divide_by_gcd: x//y ->
#   (x//gcd)//(y//gcd)` -- AND THE **MOD HALF** (`ret*gcd`) IS PORTED WITH IT,
#   AND THE DIFFERENTIAL GATE'S ROWS ARE `gates/divandmod-cases.rows`'s
#   `gcdmod_fires` AND `gcddiv_fires`.
# TODO(p3) divandmod.py:38-49  symbol=fold_divmod_general  `Shared decomposition for folding rules` and :42-49
#   THE ARM's SHAPE IS PORTED (`.agents/slop/loc/divandmod-cg-wip.bend`, THE
#   WORKING COPY) AND THE PRODUCT IS THE EASY HALF -- BEND REFUSES MUTUAL
#   RECURSION, SO THE PRODUCT IS **THE MASKS** OVER THE FACTORS
#   (`itertools.product`'s ORDER IS THE MASKS' ORDER) AND THE TWO CHOICES PER
#   FACTOR ARE `(r, r-c)` ON A TIE AND `min(r, r-c, key=abs)` OTHERWISE --
#   **AND THE WALL IS THE PORT's FOLD AND NOT A CARTESIAN PRODUCT.** MEASURED
#   2026-11-27: `F.UOp.vmin` ANSWERS `None` FOR A NODE WHOSE SRC0 IS AN ADD
#   (`ADD(ADD(MUL(Pa,c6),c2),c2)` HAS **NO BOUND** AND `ADD(MUL(Pa,c6),c2)`
#   **HAS** ONE), AND **A `None` BOUND READS AS "NOT NEGATIVE"**, SO THE
#   `factor_remainder` ARM's `new_x.vmin<0` GUARD (divandmod.py:90) IS
#   **VACUOUS** AND NO ROW TESTS IT.  AND `UOp.divides` PUTS ITS QUOTIENT IN A
#   **BRANCH** OF THE ARENA (ops.bend:4257), SO A NODE BUILT AFTERWARDS IN THE
#   CALLER's ARENA HAS A SRC THE FOLD'S ARENA DOES NOT CONTAIN AND THE FOLD
#   RESOLVES **NOTHING** DOWNSTREAM OF IT.
# TODO(p3) divandmod.py:51-65 `nest_by_factor: x//c -> (x//f)//(c//f),
#  Variable Denominator / Fallback Rules  -- divandmod.py:72-96. These rules
# PORTED: divandmod.py:78-96  `factor_remainder: (d*x+y)//d -> x+y//d` -- AND
#   THE ARM IS IN `tinybendygrad/uop/divandmod.bend` AS `dm_fr.*` AND THE
#   DIFFERENTIAL ROWS ARE `gates/divandmod-cases.rows`'s `fr_*` ROWS.  MEASURED
#   2026-11-25: A **CONST** DIVISOR PUTS THE ARM BEHIND `divide_by_gcd`
#   (divandmod.py:72-76) **WHEN THE GCD IS NOT A BARE `CONST`** -- AND THE GCD IS
#   `uops[0].const_like(gcd)` (ops.py:1037), SO IT IS A BARE `CONST` WHEN
#   `uops[0]`'s `_shape` IS `()` -- **A VARIABLE DERIVATION** -- **AND THEN THE ARM
#   **IS** REACHED**.  MEASURED 2026-11-25: `(6a+b)//4` REACHES IT AND ANSWERS
#   `ADD(DIV(ADD(ADD(ADD(c0,MUL(MUL(a,c1),c2)),b),c0),c4),ADD(c0,MUL(MUL(a,c1),c1)))`.
#   **AND THE PORT's `quo`/`rem` LISTS HOLD **INDICES** AND AN INDEX IS ONLY
#   MEANINGFUL IN **ITS OWN ARENA**, AND `UOp.divides` AND `UOp.alu` **GROW** THE
#   ARENA -- SO THE TWO LISTS' TERMS WERE BUILT IN **TWO BRANCHES** OF ONE ARENA
#   AND READ EACH OTHER's INDICES, AND A STALE ARENA READS THE ARENA's **BOTTOM
#   NOOP NODE**.  THE FIX IS **ONE CHAIN**: EVERY NODE IS BUILT FROM THE PREVIOUS
#   NODE's ARENA.  AND THE PLANT's CASE 12 PROVES IT IS LOAD-BEARING.
#   AND UPSTREAM's OWN TEST (`test/null/test_uop_symbolic.py:584`) USES
#   `d = Variable("d", 1, 10)`.
#   AND THE PORT's `UOp.gcd` STILL COUNTS THE **UNPEELED** TERMS WHERE
#   UPSTREAM COUNTS THE **PEELED** ONES, SO THE TWO GCDs DIFFER IN SHAPE ON A
#   TERM THAT IS NOT A CONST -- **AND THAT DIVERGENCE IS WHAT PUTS THE PORT's
#   `divide_by_gcd` ARM OUT OF REACH WHERE UPSTREAM's IS NOT.**
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

