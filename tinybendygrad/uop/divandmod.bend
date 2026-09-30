# divandmod.bend -- tinygrad/uop/divandmod.py.
#
# WHAT THIS FILE IS. A `PatternMatcher` of three rules that folds FLOORDIV and
# FLOORMOD when the divisor is a constant, plus the one big helper rule 2 calls.
# 109 Python lines, and the honest shape of them is that FOUR are the matcher and
# EIGHTY-NINE are `fold_divmod_general`, and `fold_divmod_general` is the wall.
#
# ---------------------------------------------------------------------------
# THE BRIEF'S PREMISE IS WRONG IN THREE PLACES. All three were measured before a
# line of this file was written, because two of them decide whether the file is
# possible at all. They are recorded here so nobody re-derives them.
#
# 1. THERE IS NO `divmod_legal` AND NO `fast_divmod` IN THIS REPO.
#    `rg -n 'fast_divmod|divmod_legal' tinygrad/ test/` is EMPTY. The magic
#    multiplier code is `fast_idiv` and it lives in `tinygrad/codegen/decomp/
#    op.py`, a different unit. So the multiply-high question this file was meant
#    to answer does not arise here -- and the ANSWER, for whoever takes `fast_idiv`,
#    is at the end of this block. Do not go looking for a multiply-high below.
#
# 2. THERE IS NO `graph_rewrite` IN THIS FILE EITHER. `divandmod.py` builds a
#    `PatternMatcher` and stops; `symbolic.py:7` is what imports it. So the "a
#    rule RETURNS THE ARENA" engine shape does not apply to the TABLE and this
#    file uses the same first-wins scan `uop/spec.bend` uses. The one thing the
#    engine shape's RULE still buys here is the ACCUMULATOR: `Hit` carries the
#    arena beside the answer, because these rules GROW the arena and a scan
#    returning only a node index would throw the growth away.
#
# 3. THE MATH IS *MOSTLY* SOLVED, IN `helpers.bend`, AND TWO OF THE HELPERS ARE
#    BUGGY. `divandmod.py` is FLOOR arithmetic end to end, so this was the first
#    thing measured and it is the headline. All four facts below were measured
#    with `./bin/bend`:
#
#      * `U32.div` / `U32.mod` are UNSIGNED TRUNCATING with `U32.div(a,0) = 0`
#        and `U32.mod(a,0) = a`.
#      * `H.cdiv_i32_go` is TRUNCATE and correct (`-1 / 2 == 0`, `6 / 4 == 1`).
#      * **`H.floordiv_i32` AND `H.floormod_i32` ARE WRONG.** `6 // 4 == 2`,
#        `10 // 3 == 4`, `1000 // 7 == 143`, `6 % 4 == -2`, `1000 % 7 == -1`,
#        where Python says 1, 3, 142, 2, 6. They are correct for a NEGATIVE
#        dividend and for an EXACT division and wrong (off by +1) otherwise, and
#        a non-negative inexact division is the case `divandmod.py` is ALL about:
#        `_min_max`'s CDIV/FLOORDIV/FLOORMOD arms and every constant-folded
#        `//`. `helpers.bend:1097` `floordiv_i32.trunc.exact` adds one whenever
#        the division is inexact and IGNORES `neg`. THE FIX IS ONE LINE and
#        `dm_floordiv` / `dm_floormod` below are that fix with the removal
#        condition written down. REPORTED, NOT FIXED, per the brief:
#        `helpers.bend` is another unit's. If it is not fixed, every other unit
#        that divides is silently wrong in the same way.
#      * `U32.mul` TRUNCATES to 32 bits: `U32.mul(4000000000, 3) == 3410065408`,
#        the low half of 12000000000. `U32.shl` / `U32.shr` / `shln` / `shrn` are
#        all LOGICAL; `H.asr` was meant to be the arithmetic one and IS ALSO BROKEN --
#        it is `shrn(v,n) | shrn(shrn(v,31),n)`, and `shrn(v,31)` is the sign
#        BIT, so the second term is 0 for every `n >= 1` and `H.asr(-1,1)` prints
#        2147483647 where the answer is 4294967295. It is UNUSED and UNTESTED in
#        `helpers.bend` and this file does not use it, so nothing here is wrong
#        -- but it is a live bug in a shared file. REPORTED, NOT FIXED, per the
#        brief. FIXED 2026-10-01 in helpers.bend: the form this comment
#        originally recommended was WRONG -- it ORs in a single sign bit, not a
#        run of n ones (right only at n=1 by luck); the fill must be the whole
#        word `0 - shrn(v,31)`, count clamped at 31, as `H.asr` now does.
#
#    ** THE `fast_idiv` ANSWER, SINCE IT WAS ASKED FOR. `Word.mul` is the only
#    widening multiply in Bend 2 and `base.bend` does NOT export `Word`'s
#    constructors -- `match Word.mul(64n, ...)` is refused with "a declared
#    constructor (unknown: Word.Nil)" from outside the file. So a magic
#    multiplier is a WALL, not a TODO, and it is a wall of ONE export: either
#    `Word` and `WCon` become public, or the port writes the 64-bit product as
#    four `U32` multiplies and a carry chain (`U32.mul` already truncates, so it
#    composes). `H.I64{hi,lo}` exists with `i64_add` / `i64_sub` / `i64_cmp` and
#    NOT `i64_mul` -- the same wall one level up, already recorded for `_min_max`
#    at `fold.bend:2180`.
# ---------------------------------------------------------------------------
#
# ---------------------------------------------------------------------------
# THE ONE WALL, AND IT IS NOT A BENCH LIMITATION. It is `_min_max`.
#
# `fold_divmod_general` is 89 lines and 60 of them are interval arithmetic over
# symbolic UOps: `y.vmin==y.vmax==0`, `(x//y).vmin == (x//y).vmax`,
# `sum(r*v for ...).vmin//c == rem.vmax//c`, `new_x.vmin >= 0`, `x.vmin >= 0`,
# `0 <= b.vmin and b.vmax < div`. `UOp._min_max` (ops.py:1104) is P3 and NOT
# WRITTEN: `fold.bend:2176-2184` records it and names the reason -- PyConst is
# `int|float|bool|Invalid`, `helpers.bend` has `i64_add`/`i64_sub`/`i64_cmp` and
# NOT `i64_mul`/`i64_div`/`i64_mod`, the arms read `self.dtype.min`/
# `self.dtype.max` (dtype.bend, unimportable, and it is the C-effect seam) and
# `self.src[0].buf_uop` (a `while` over five ops). It is the largest single piece
# left in that half of ops.py. P3, not expressible today.
#
# SO THIS FILE PORTS THE PART THAT IS DERIVABLE AND NAMES THE REST. Three arms of
# `fold_divmod_general` survive and each survives for a stated reason:
#
#   * `divandmod.py:11` `if y.vmin==y.vmax==0: raise ZeroDivisionError(...)` -- a
#     CONST's `_min_max` IS `(val, val)` (ops.py:1151) and a PARAM's IS
#     `arg.vmin_vmax` (ops.py:1144), so BOTH cases of that test are one `arg`
#     read. PORTED as a `Bool` because Bend has no `raise`; the rows are that the
#     flag is SET on exactly the nodes where Python raises, which the oracle
#     confirms for a `CONST(0)` divisor, for a `PARAM` whose range is `(0,0)`, and
#     NOT for a divisor of 7.
#   * `divandmod.py:13` `if (xdiv:=x//y).vmin == xdiv.vmax: return x - xdiv.vmin*y
#     if d.op is Ops.FLOORMOD else xdiv.const_like(xdiv.vmin)` -- for two CONSTs
#     `_min_max` is the four-way min/max of `a//b, a//b, a//b, a//b` (ops.py:1127),
#     the single point `floordiv(a,b)`, so the test is ALWAYS true there and this
#     arm is EXACT rather than conservative on CONST/CONST. Outside CONST/CONST it
#     needs the range and is a TODO. `r15` and `v2n_-1000` (`-7 // 4 == -2`,
#     `-1000 // 4 == -250`) are the rows, and both are FLOOR.
#   * `divandmod.py:15` `x.op is Ops.PARAM and y.op is Ops.CONST and
#     x.arg.multiple_of % y.val == 0` -- NO RANGE AT ALL, `arg.multiple_of` is a
#     field read. PORTED IN FULL, and the DEFAULT is load-bearing:
#     `UOp.variable`'s `multiple_of` defaults to 1 (ops.py:1013) and `1 % 1 == 0`,
#     so `FLOORMOD(param, CONST(1))` rewrites to `CONST(0)`. `r18` is that row and
#     it is the row a wrong default moves.
#
# The other two walls behind the remaining 60 lines are `const_factor` / `divides`
# / `gcd` (ops.py:1058/1067/1083 -- P3, `fold.bend:2174`; `divides` needs `gcd` and
# `gcd` needs a `Counter` fold) and `simplify` / `ssimplify` (ops.py:513/520 --
# P3, `fold.bend:2140`).
#
# ---------------------------------------------------------------------------
# TWO THINGS ABOUT THE PATTERNS THAT ARE EASY TO INVERT, both measured against the
# real `div_and_mod_symbolic` with `PYTHONPATH=. python3`.
#
# 1. `Ops.ADD` IS COMMUTATIVE, SO `UPat.cvar("c") + UPat.cvar("a")` IS AN
#    `is_any` OVER BOTH ORDERS. `UPat.alu` (ops.py:1533-1536) passes
#    `list(asrc) if op in GroupOp.Commutative else asrc`, and ADD is in
#    `GroupOp.Commutative`. Both rules' numerators are therefore a TWO-WAY
#    DISJUNCTION, and writing it as a conjunction -- "src0 is the CONST" -- drops
#    `r01` and `r08` and typechecks. `dm_which` is the disjunction, and `r01` /
#    `r08` are the two-sided rows for it. Exactly one alternative can ever match
#    (both sides cannot be a CONST and a `FLOORDIV(_, CONST)` at once), so there
#    is no store to disambiguate and NO name is bound twice, which is why there
#    is not one `U32.is_eq` identity check in this file.
#
# 2. THE REJECT SETS ARE NOT EMPTY. `ops.py:1475-1478` builds `early_reject` from
#    the ops of the pattern's FIRST src, and that first src is the `is_any` --
#    whose members DO have single-element op sets. Measured: rules 0 and 1 reject
#    on `[ADD, CONST]`; rule 2 rejects on `[]` because its `src` is `None`. Rules 0
#    and 1 are also `strict_length=True, required_len=2` and rule 2 is
#    `strict_length=False, required_len=0`, so a THREE-src FLOORDIV cannot match
#    rules 0 or 1: it falls to rule 2, whose `x, y = d.src` makes Python raise
#    `ValueError: too many values to unpack`. `r22` is that row: rule 2 still
#    CLAIMS it, which is what Python does before it raises.
#
# ---------------------------------------------------------------------------
# WHERE THIS FILE DIVERGES FROM PYTHON. All four, stated rather than hidden.
#
# A. NO PROMOTION CASTs. Python's `UOp.__init__` runs `dtype_from_uop`, so `a*c`
#    with a weakint `a` and an int32 `c` is `CAST(MUL(C(5),C(3)))`. `ops.bend`'s
#    `UOp.new` is `UOp.make` and nothing else -- dtype is the P3 fold -- so this
#    file's trees have no CAST. `dm_str` prints the tree Python prints with CASTs
#    erased, and the oracle erases them too. The ALGEBRA is unchanged; the NODE
#    COUNT is not, which is why no Python node count is a gate row and why the
#    `grown` rows below are PORT-INTERNAL counts.
# B. NO SUB CANONICALISATION. `x - q*y` is `SUB(x, MUL(q,y))` here and
#    `ADD(x, MUL(MUL(q,y), C(-1)))` in Python, because `symbolic.py`'s
#    `canonicalize` rewrites SUB. `r14` and `r16` are the two rows where that is
#    visible, and both are checked by VALUE rather than by shape.
# C. NO CONSTANT FOLDING. `C(5)*C(3)` survives as a MUL here and `simplify()`
#    folds it to `C(15)` in Python, so the two "new nodes" counts differ by one
#    per folded MUL and cannot be compared across the two implementations.
# D. A NON-INT CONST IS NOT A `vmin`. `UPat.cvar` accepts a `CFloat` and Python's
#    `d.vmin > 0` then compares a float. `dm_val` reads `CInt` only, so a float
#    CONST makes rules 0 and 1 SKIP where Python would rewrite. That is the
#    `_min_max` PyConst wall at miniature size and it is the same TODO.
# ---------------------------------------------------------------------------

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# ===========================================================================
# THE ACCUMULATOR. `PatternMatcher.rewrite` returns the FIRST non-None, and these
# rules GROW the arena, so the answer is the arena AND a node index AND whether
# anything fired. A `Maybe` cannot be a field of a `Data` record (bend2-constraints
# rule 15), so the flag is a `U32` and the index is meaningless when it is 0 --
# and 0 is the arena's BOTTOM node, so it cannot serve as the sentinel either.
# ===========================================================================
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

# ===========================================================================
# THE SHARED READERS. `dm_val` is `y.val` for an INTEGER CONST. It is a `Maybe`
# because `Arg` is the eighteen-armed `Any` Python spells when one field holds
# eighteen unrelated things, and because every caller must ASK whether a node is
# a CONST before it can read it.
# ===========================================================================
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

# `v > 0` for a SIGNED 32-bit constant. `U32.is_gt(v, 0)` is the UNSIGNED reading
# and rule 0's guard is `d.vmin > 0` with `d` possibly `C(-7)`, so the sign test is
# the whole of it.
# ===========================================================================
# `dm_floordiv` / `dm_floormod` -- AND WHY THEY ARE NOT `H.` HERE.
#
# `H.floordiv_i32` and `H.floormod_i32` ARE WRONG for a non-negative dividend
# with an INEXACT division, which is the only case `divandmod.py` cares about.
# Measured, with `./bin/bend` against `helpers.bend`:
#
#     expr            Bend     Python
#     6 // 4            2         1
#     10 // 3           4         3
#     1000 // 7       143       142
#     6 % 4            -2         2
#     1000 % 7          -1         6
#     -7 // 4           -2        -2     correct
#     -7 % 4             1         1     correct
#     4 // 4            1         1     correct (exact)
#     cdiv_i32_go(6,4)  1         1     correct
#
# `helpers.bend:1097` `floordiv_i32.trunc.exact` adds one whenever the division is
# INEXACT and ignores `neg`, so the sign is only ever applied correctly by luck of
# the arithmetic. THE FIX IS ONE LINE, in that def: the `False{}` arm must be
# `put(neg, U32.add(q,1))` only when `neg`, and `put(neg, q)` otherwise -- which
# is what `dm_floordiv.trunc` below already does.
#
# REPORTED, NOT FIXED, per the brief: `helpers.bend` is another unit's. DELETE
# `dm_floordiv` / `dm_floormod` AND CALL THE `H.` VERSIONS WHEN THAT ONE-LINE
# FIX LANDS; nothing else in this file changes. The two defs are here because a
# gate that pins wrong numbers is worse than no gate.
# ===========================================================================
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
# negative is not a divisibility test -- and the sign is reapplied by `trunc`.
# `H.floordiv_i32` does exactly this and its ONLY defect is the `+1` above.
def dm_floordiv(+x: U32, +y: U32) -> U32:
  dm_floordiv.put(U32.is_zero(y), H.cdiv_sign(x, y),
                  dm_floordiv.exact2(H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y)),
                  H.i32_abs(H.i32_is_neg(x), x), H.i32_abs(H.i32_is_neg(y), y))


def dm_floormod(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(dm_floordiv(x, y), y))

def dm_pos(+v: U32) -> Bool:
  Bool.and(Bool.not(H.i32_is_neg(v)), Bool.not(U32.is_zero(v)))

# `len(u.src) == 2` -- the `strict_length` conjunct rules 0 and 1 carry.
def dm_isn2(ar: O.Arena, u: U32) -> Bool:
  U32.is_eq(O.Arena.nsrc(ar, u), 2)

# `x//c` as a SHAPE: a FLOORDIV whose divisor is a CONST. Rule 0's
# `UPat.var("x")//UPat.cvar("c")`, with the name bindings left to `dm_which`.
def dm_is_quot(+ar: O.Arena, +s: U32) -> Bool:
  Bool.and(O.op_is(ar, s, O.OpsFLOORDIV{}), dm_has(dm_val(ar, O.Arena.src(ar, s, 1))))

# WHICH side of the commutative ADD is the quotient: 0 = src0, 1 = src1,
# 2 = "not the pattern". The 2 is the both-or-neither arm, and it is what a
# conjunction would have silently turned into a match.
def dm_which.go(s0: Bool, s1: Bool) -> U32:
  match s0 s1:
    case True{} False{}: 0
    case False{} True{}: 1
    case _ _: 2

def dm_which(+ar: O.Arena, +add: U32) -> U32:
  dm_which.go(dm_is_quot(ar, O.Arena.src0(ar, add)), dm_is_quot(ar, O.Arena.src(ar, add, 1)))

# `dtypes.weakint` -- `UPat.var("x", dtypes.weakint)` at divandmod.py:103 and the
# ROOT's `dtypes.weakint` at :108. `spec.bend` has this test privately; it is four
# lines and a `Cls` constructor is a legal binder, so it is written again here
# rather than reaching into another unit's privates.
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

# ===========================================================================
# `fold_divmod_general` -- divandmod.py:8. Three arms ported, in Python's order;
# the other 60 lines are the `_min_max` / `divides` / `simplify` wall. Python's
# `raise` at line 11 is a `Bool` here: `dm_zero` REPORTS it and the ladder treats
# it as a skip, which is the only total reading a pure def has.
# ===========================================================================

# `y.vmin == y.vmax == 0` -- divandmod.py:11. A PARAM's range is a
# `PyRange{lo,hi}` of two `I64` and the test is BOTH ends zero, so it is NOT
# `vmin == vmax`: a PARAM with range (5,5) is a 5, not a zero.
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

# `x - xdiv.vmin*y`, the FLOORMOD half of divandmod.py:13.
def dm_point.sub(ar: O.Arena, x: U32, y: U32, q: U32) -> O.Found:
  +qc = O.UOp.const(ar, O.CInt{H.i64_of_i32(q)})
  +m = O.UOp.alu(O.Found.ar(qc), O.OpsMUL{}, [O.Found.i(qc), y])
  O.UOp.alu(O.Found.ar(m), O.OpsSUB{}, [x, O.Found.i(m)])

# `xdiv.const_like(xdiv.vmin)`, the FLOORDIV half.
def dm_point.body(ar: O.Arena, op: O.Op, x: U32, y: U32, q: U32) -> O.Found:
  match op:
    case O.OpsFLOORDIV{}: O.UOp.const(ar, O.CInt{H.i64_of_i32(q)})
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

# `x.arg.multiple_of % y.val == 0` -- divandmod.py:15. No range, so PORTED IN FULL.
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

# `d.const_like(0) if d.op is Ops.FLOORMOD else None` -- the tail of the lambda on
# divandmod.py:15. FLOORDIV is the `None`, so the ladder below keys on it.
def dm_multiple_of.hit(ar: O.Arena, op: O.Op) -> Maybe<&2, O.Found>:
  match op:
    case O.OpsFLOORDIV{}: None{}
    case _: Some{O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})}

def dm_multiple_of.arm.go(+ar: O.Arena, d: U32, hit: Bool) -> Maybe<&2, O.Found>:
  match hit:
    case True{}: dm_multiple_of.hit(ar, O.Arena.op(ar, d))
    case False{}: None{}

def dm_multiple_of.arm(+ar: O.Arena, +d: U32) -> Maybe<&2, O.Found>:
  dm_multiple_of.arm.go(ar, d, dm_multiple_of(ar, d))

# Python's `if ...: return A` twice. A `Maybe<&2, T>` cannot take a `+`
# (bend2-constraints rule 4), so first-wins is a leaf over two parameters.
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

# ===========================================================================
# RULE 0 -- divandmod.py:101, the first of the ** 1. Fast Inline Rules **.
# `(x//c+a)//d -> (x+a*c)//(c*d) for c>0, d>0`. The Python guard is `d.vmin>0` and
# `d` is a `cvar`, so `d.vmin` IS `d.val` and the range machinery this rule looks
# like it needs is one signed compare: `dm_pos`.
# ===========================================================================
def dm_0.build(+ar: O.Arena, q: U32, a: U32, +c: U32, d: U32) -> O.Found:
  +ac = O.UOp.alu(ar, O.OpsMUL{}, [a, c])
  +s = O.UOp.alu(O.Found.ar(ac), O.OpsADD{}, [O.Arena.src0(ar, q), O.Found.i(ac)])
  +cd = O.UOp.alu(O.Found.ar(s), O.OpsMUL{}, [c, d])
  O.UOp.alu(O.Found.ar(cd), O.OpsFLOORDIV{}, [O.Found.i(s), O.Found.i(cd)])

# the two `is_any` alternatives, resolved: `which` names the `x//c` side and the
# other side is `a`. The Python is `(x//c + a)`, so `x` is that side's src0 and
# `c` its src1 -- the COMMUTATIVE rewrite puts `x` first whatever the input order.
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
          dm_which(ar, O.Arena.src0(ar, self)), O.op_is(ar, self, O.OpsFLOORDIV{}), self)

def dm_0(fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  dm_0.put(F.Folded.ar(fx), self)

# ===========================================================================
# RULE 1 -- divandmod.py:103-105, the second Fast Inline Rule.
# `(x+c)//d -> (x+c%d)//d + c//d ; (x+c)%d -> (x+c%d)%d`, and the `cvar("x")` there
# is `UPat.var("x", dtypes.weakint)`, so the weakint conjunct is on the NUMERATOR
# and the ROOT is unconstrained. That is load-bearing and `r12` is the row: the
# same tree with an int32 numerator is not rewritten at all.
#
# The guard is a two-armed `or`: `d.val==0` OR `c.val%d.val==c.val`, and the first
# arm is the ZERO DIVISOR, which Python reports by raising in rule 2 and this file
# reports as `dm_zero`. `H.floormod_i32` and `H.floordiv_i32` are FLOOR, which is
# what makes `10 % -7 == -4` and `10 // -7 == -2`; `r10` and `v1n_-1000` are those
# two numbers and a truncating port gets 3 and -1.
# ===========================================================================
def dm_1.fd(ar: O.Arena, x: U32, d: U32, cm: U32, cq: U32) -> O.Found:
  +cmc = O.UOp.const(ar, O.CInt{H.i64_of_i32(cm)})
  +s = O.UOp.alu(O.Found.ar(cmc), O.OpsADD{}, [x, O.Found.i(cmc)])
  +q = O.UOp.alu(O.Found.ar(s), O.OpsFLOORDIV{}, [O.Found.i(s), d])
  +cqc = O.UOp.const(O.Found.ar(q), O.CInt{H.i64_of_i32(cq)})
  O.UOp.alu(O.Found.ar(cqc), O.OpsADD{}, [O.Found.i(q), O.Found.i(cqc)])

def dm_1.fm(ar: O.Arena, x: U32, d: U32, cm: U32) -> O.Found:
  +cmc = O.UOp.const(ar, O.CInt{H.i64_of_i32(cm)})
  +s = O.UOp.alu(O.Found.ar(cmc), O.OpsADD{}, [x, O.Found.i(cmc)])
  O.UOp.alu(O.Found.ar(s), O.OpsFLOORMOD{}, [O.Found.i(s), d])

def dm_1.finish(ar: O.Arena, op: O.Op, x: U32, d: U32, cm: U32, cq: U32) -> O.Found:
  match op:
    case O.OpsFLOORDIV{}: dm_1.fd(ar, x, d, cm, cq)
    case _: dm_1.fm(ar, x, d, cm)

def dm_1.pick(s0: U32, s1: U32, which: U32) -> U32:
  match which:
    case 1: s0
    case _: s1

# `c.val` -- the CONST side is the OTHER side from `x`, so the two sides are
# swapped going in. Getting this wrong makes `cv` 0 and then `c%d == c` is true
# and rule 1 skips on every numerator.
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
# that `or` is the ZERO DIVISOR, which Python reports by raising in rule 2; the
# second is "the multiple of d is already out", which is a SKIP.
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

# ===========================================================================
# RULE 2 -- divandmod.py:108, the ** 2. Slow Rules ** entry. The weakint
# conjunct is on the ROOT here (contrast rule 1, where it is on the numerator),
# and there is no arity constraint, so a three-src FLOORDIV still gets here.
# ===========================================================================
def dm_2.armed(fx: F.Folded, self: U32, weak: Bool) -> Maybe<&2, O.Found>:
  match weak:
    case True{}: fold_divmod_general(F.Folded.ar(fx), self)
    case False{}: None{}

def dm_2.put(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  dm_2.armed(fx, self, dm_weak(fx, self))
# ===========================================================================
# RULE 2 -- divandmod.py:108, the ** 2. Slow Rules ** entry. The weakint
# conjunct is on the ROOT here (contrast rule 1, where it is on the numerator),
# and there is no arity constraint, so a three-src FLOORDIV still gets here.
# ===========================================================================
def dm_2(fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  dm_2.put(fx, self)

# ===========================================================================
# THE TABLE, THE DISPATCH AND THE SCAN -- `spec.bend`'s shape, once.
# `ops.bend` cannot call a def in this file, so its `pm_dispatch` cannot grow a
# case for a rule that lives here, and this file gets its own scan. `ops.bend`'s
# `pm_ler` IS a fold over the src count now, so `O.pm_claimed` and `O.pm_early`
# are used as they are and NOT re-derived; the report that said otherwise, in
# `spec.bend`'s mutation table, is stale.
# ===========================================================================
def dm_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsFLOORDIV{}], [O.OpsADD{}, O.OpsCONST{}]},                       # 101
             O.PMEntry{1, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], [O.OpsADD{}, O.OpsCONST{}]},         # 103
             O.PMEntry{2, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], Nil{}}]}                           # 108

# The first non-None wins, so `dm_fold` keys on the ACCUMULATOR. Keying on the new
# answer is last-wins, and `r02` is the row that tells the two apart: rule 0 grows
# the arena by 4 and rule 1 by 3, and their trees differ.
# `+f` here, not a bare binder: a `Maybe` pattern binder CANNOT be read twice
# (measured -- it is the one case where rule 3 of bend2-constraints bites a
# binder rather than a parameter), so `f` becomes a `Data` parameter.
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
# one thing this scan does NOT reproduce: a rule that hands back the node it was
# given does not fire. No rule here can do that -- every rewrite builds at least
# one new node -- so the case is unreachable rather than ported.
def div_and_mod_symbolic(+fx: F.Folded, self: U32) -> Hit:
  dm_scan(O.PMEntrys.es(dm_table()), fx, self, miss(F.Folded.ar(fx)))

# ===========================================================================
# THE GATE, and what each row is FOR. `1`/`0` is "a rule fired" / "the scan found
# nothing", and `0` IS Python's `None`. `none` is the same answer as a string. An
# `out_*` row is the rewritten tree TWO LEVELS DEEP with CONST VALUES printed, and
# `.agents/slop/dm-oracle.py` prints Python's answer in the same shape -- so a row
# is a before/after a reviewer can diff by eye against a real interpreter run.
#
#   nrules=3       divandmod.py:98-109 is three entries. A COUNT.
#   rej0=2 rej1=2 rej2=0   the `early_reject` sets, MEASURED against Python:
#                  `[ADD, CONST]`, `[ADD, CONST]`, `[]`. Only a MISSPELLED set
#                  shows up here and nowhere else.
#   nroots=26      how many roots the fixture arena holds. THE COUNT ROW: a
#                  fixture added or dropped moves it, and every `r*` row is
#                  addressed THROUGH it, so a stale index cannot hide.
#   zero_r04=1     divandmod.py:11 on a `CONST(0)` divisor. Python RAISES.
#   zero_r11=1     the same, and the `or` in rule 1's guard is why rule 1 SKIPS.
#   zero_r23=1     a PARAM whose declared range is the POINT 0. Python RAISES.
#   zero_r25=0     a PARAM whose range is (0,5): `vmin==0` but `vmax!=0`, so
#                  Python does NOT raise. THE ROW for `y.vmin==y.vmax==0` being a
#                  CONJUNCTION -- the mutation table shows the `vmax` half being
#                  dropped moves this row and NOTHING else.
#   zero_r05=0 zero_r15=0   the control for the three above: an ordinary divisor
#                  of 7 and of 4 is not a zero divisor.
#   on_r00=1       rule 0 fires: `(Px//3 + 5)//7`.
#   out_r00        `FLOORDIV(ADD(Px,MUL),MUL(CONST(3),CONST(7)))` -- rule 0's
#                  answer, and `MUL(C(3),C(7))` is the `(c*d)` term.
#   on_r01=1 out_r01   the SWAPPED add, `(5 + Px//3)//7`. THE ROW for `ADD` being
#                  commutative: a conjunction here drops r01 and r08 and
#                  typechecks.
#   on_r02=1 grown_r02=4 out_r02   THREE rules claim this node -- rule 0, rule 1
#                  (its `x` is a `FLOORDIV`, which `UPat.var` allows) and rule 2
#                  (the root is weakint) -- and rules 0 and 1 answer DIFFERENTLY.
#                  FIRST-WINS, and `grown_r02` is the numeric witness: rule 0 adds
#                  four nodes and rule 1 adds three, so last-wins reads 3 and a
#                  conjunction reads 7. This is the row the brief's "build the
#                  fixture so two rules both claim the same node" asks for.
#   on_r03=1 out_r03   `(Px//3 + 5)//-7`. Rule 0 SKIPS because `d.vmin > 0` fails
#                  and rule 1 answers with `C(-2)` and `C(-1)`: `5 % -7 == -2`
#                  and `5 // -7 == -1`, FLOOR on a negative divisor. This and
#                  `out_r10` are the FLOOR rows.
#   on_r04=0       `//0`. Rule 0 skips on `d.vmin>0`, rule 1 skips on `d.val==0`,
#                  and rule 2 REPORTS the zero divisor. Python RAISES.
#   on_r05=1 out_r05 grown_r05=1   `(Px+10)//7` -> `ADD(FLOORDIV(ADD(Px,C(3)),
#                  C(7)),C(1))`. `grown_r05` is 1 and not 4 because the fixture
#                  already contains `ADD(Px,C(3))` and `FLOORDIV(...,C(7))` as
#                  r07, so `UOp.make` interns both: the count is PORT-INTERNAL and
#                  the low number is the interning working.
#   on_r06=1 out_r06 grown_r06=1   `(Px+10)%7` -> `FLOORMOD(ADD(Px,C(3)),C(7))`,
#                  EXACTLY Python's tree, and with NO `+ C(0)` because Python's
#                  ternary omits the `+ c//d` term in the FLOORMOD arm.
#   on_r07=0 out_r07=none   `(Px+3)//7`: `c.val%d.val == c.val`, so rule 1 SKIPS
#                  and rule 2 skips. THE ROW for the second arm of that `or`.
#   on_r08=1 out_r08   `(10 + Px)//7` gives r05's answer: the commutative rewrite
#                  puts `x` FIRST whatever the input order.
#   on_r09=1 out_r09   `(Px+10)//1` -> `ADD(FLOORDIV(...,C(1)),C(10))`: `10%1=0`
#                  and `10//1=10`.
#   on_r10=1 out_r10   `(Px+10)//-7` -> `C(-4)` and `C(-2)`. THE FLOOR ROW: a
#                  truncating port prints 3 and -1.
#   on_r11=0       `(Px+10)//0`. Python RAISES.
#   on_r12=0 out_r12=none   THE WEAKINT-CONJUNCT ROW: the same tree with an int32
#                  numerator. Rule 1's `UPat.var("x", dtypes.weakint)` is on the
#                  NUMERATOR, not on the root.
#   on_r13=1 out_r13=CONST(1)          `6//4`, divandmod.py:13's CONST/CONST arm.
#   out_r14=SUB(CONST(6),MUL(CONST(1),CONST(4)))   `6%4`. Python writes
#                  `ADD(C(6),MUL(MUL(C(1),C(4)),C(-1)))` -- divergence B, the same
#                  algebra with SUB not canonicalised.
#   out_r15=CONST(-2)  `-7//4`. FLOOR again.
#   out_r16=SUB(CONST(-7),MUL(CONST(-2),CONST(4)))  `-7%4 == 1`.
#   out_r17=CONST(0)   divandmod.py:15: `Pp.multiple_of == 4` and `4 % 4 == 0`,
#                  so `Pp % 4` folds to `CONST(0)`.
#   out_r18=CONST(0)   THE DEFAULT ROW: `Pz.multiple_of` is 1 (ops.py:1013) and
#                  `1 % 1 == 0`, so `Pz % 1` folds to `CONST(0)`. A port that
#                  reads `multiple_of` as `None` misses this entirely, and the
#                  mutation table shows it moving five rows.
#   out_r19=none   `Pp//4`: divandmod.py:15 returns `None` for FLOORDIV.
#   out_r20=none   `Pq%4`: `3 % 4 != 0`.
#   out_r21=none   `Px%4`: past divandmod.py:15, i.e. behind the wall. Python
#                  returns `None` too, so this row cannot tell the two apart --
#                  `on_r13` is the row that CAN, and the mutation table shows why.
#   on_r22=0       a THREE-src FLOORDIV. Rules 0 and 1 are `strict_length` so
#                  they skip; rule 2 claims it and Python then raises
#                  `ValueError: too many values to unpack` on `x, y = d.src`.
#   on_r23=0 on_r24=0   the two zero-divisor roots, which Python raises on.
#   on_r25=0 out_r25=none   the (0,5)-range divisor.
#   grown_r00=4 grown_r01=4   rule 0's shape: MUL, ADD, MUL, FLOORDIV, all new.
# ---------------------------------------------------------------------------
#
# MUTATIONS, all re-run 2026-09-30 against this file by
# `.agents/slop/tools/mutate-dm.py`, which applies one edit, runs the INTERPRETED
# lane, diffs the rows against this baseline and restores. A row that only ONE
# mutation moves is a LOCALISED row; the rest are load-bearing together, and this
# table is not one-row-per-bug and should not read as if it were.
#
# | mutation | rows moved | how many |
# | --- | --- | --- |
# | `dm_fold.go` first-wins -> last-wins | `grown_r02`, `on_r00`, `on_r01`, `on_r02`, `on_r03`, `on_r05`, `on_r06`, `on_r08`, `on_r09`, `on_r10`, `out_r00`, `out_r01`, `out_r02`, `out_r03`, ... | 19 |
# | `dm_which.go`'s disjunction -> always src0 | `grown_r05`, `grown_r06`, `on_r03`, `on_r06`, `on_r07`, `on_r10`, `on_r12`, `out_r01`, `out_r03`, `out_r05`, `out_r06`, `out_r07`, `out_r08`, `out_r09`, ... | 16 |
# | `dm_cside.go`'s disjunction -> always src0 | the SAME sixteen | 16 |
# | `dm_floordiv.trunc`: re-introduce the `helpers.bend` bug (+1 when not neg) | `grown_r05`, `grown_r06`, `on_r07`, `out_r05`, `out_r06`, `out_r07`, `out_r08`, `out_r13`, `out_r14` | 9 |
# | `dm_floordiv.exact`: drop the +1 (floor toward zero) | `on_r03`, `out_r03`, `out_r10`, `out_r15`, `out_r16` | 5 |
# | `dm_0.pat.put`: arity conjunct on the divisor, not the root | `grown_r00`, `grown_r01`, `grown_r02`, `on_r00`, `on_r01`, `out_r00`, `out_r01`, `out_r02` | 8 |
# | `dm_1.pat.put`: arity conjunct on the divisor, not the root | 23 rows, incl. every `out_r0x` | 23 |
# | `dm_1.pat.put`: drop the weakint conjunct | `on_r12`, `out_r12` | 2 |
# | `dm_weak.cls`: `CWeakFloat` instead of `CWeakInt` | 21 rows | 21 |
# | `dm_pos`: unsigned reading of `d.vmin > 0` | `out_r03` | 1 |
# | `dm_1.finish`: FLOORDIV and FLOORMOD branches swapped | `out_r03`, `out_r05`, `out_r06`, `out_r08`, `out_r09`, `out_r10` | 6 |
# | `dm_zero.range`: `vmin == 0` only, the `vmax` half dropped | `zero_r25` | 1 |
# | `dm_multiple_of.mod`: an unset `multiple_of` read as 1 | `grown_r05`, `grown_r06`, `on_r07`, `on_r22`, `on_r25`, `out_r03`, `out_r05`, `out_r06`, `out_r07`, `out_r08`, `out_r09`, `out_r10`, `out_r17`, `out_r18`, ... | 18 |
# | `dm_table`: rule 2 given a reject set | `rej2`, `on_r13`, `out_r13`, `out_r14`, `out_r15`, `out_r16`, `out_r17`, `out_r18` | 8 |
# | `dm_table`: rule 2 given FLOORDIV only | `out_r14`, `out_r16`, `out_r17`, `out_r18` | 4 |
# | `dm_point`: truncating instead of floor | `out_r15`, `out_r16` | 2 |
# | `dm_multiple_of.hit`: answer FLOORDIV as well | `out_r19` | 1 |
# | `dm_cval`: read the `x` side instead of the `c` side | 14 rows | 14 |
#
# FOUR THINGS WORTH READING TWICE.
#
# 1. `dm_which.go` and `dm_cside.go` MOVE THE SAME SIXTEEN ROWS. They are the two
#    halves of the same mistake -- collapsing a commutative `is_any` into a
#    conjunction -- and the gate cannot tell them apart, because from the outside
#    "which side is the CONST" and "which side is the quotient" are the same
#    question. That is a LIMITATION OF THIS GATE, not a coincidence: two rules,
#    one disjunction each, and one fixture family cannot separate them. Fixing it
#    needs a fixture where the quotient is on src1 AND the CONST is also on src1,
#    i.e. `(x//c + d)//e` with `c != d`.
#
# 2. `dm_pos` AND `dm_zero.range` MOVE ONE ROW EACH, and both of those rows exist
#    for exactly that mutation: `out_r03` is the only row with a NEGATIVE
#    divisor, and `zero_r25` is the only row with a `vmin == 0 < vmax` divisor.
#    A localised row that is not the row the mutation was written for is the
#    failure mode `spec.bend` describes; these two are the other side of it.
#
# 3. `dm_point`: TRUNCATING instead of floor moves `out_r15` and `out_r16` but
#    NOTHING in rule 0 or rule 1 -- because every `c` and `d` those two rules see
#    is positive, or is negative on BOTH sides. The two rows that carry the floor
#    semantics for `fold_divmod_general` are the only ones that move, which is why
#    the FLOOR rows are `out_r10` and `out_r15` and not a single combined row.
#
# 4. `dm_multiple_of.mod`: reading an unset `multiple_of` as 1 moves EIGHTEEN
#    rows, more than any other mutation. That is the `multiple_of: int = 1`
#    default at ops.py:1013 being load-bearing in a place no comment mentions,
#    and it is the widest single effect in this file.

# ===========================================================================
# THE GATE'S PRINTER. `dm_sh2` prints a node TWO levels deep, and that is not a
# shortcut: it is the depth at which it reproduces Python's trees EXACTLY for
# every rewriting row in this file (rule 0's answer has depth 2, rule 1's has
# depth 2, `dm_point.sub`'s has depth 2), because CONST VALUES are printed, not
# just op names -- so `r10`'s `-4` and `-2` ARE the floor-semantics rows and a
# truncating port prints 3 and -1.
#
# WHY NOT A REAL RECURSIVE PRINTER. It needs `print(node) -> srcs -> print`, and
# Bend refuses mutual recursion outright; a list fold over `Arena.srcs` does not
# help, because the fold's element step is the recursive call. And a fuel cannot
# rescue it either -- a binop spends one fuel on TWO self-calls, which is
# bend2-constraints rule 5. So the depth is a PARAMETER of the printer, not of
# the walk, and it is exactly as deep as the answers need.
#
# A PARAM prints as `P<name>` from `ParamArg.name`, a field both languages read,
# and NOT an interning counter, which would need a table threaded through for no
# gain. CASTs are absent (divergence A in the header) and the oracle erases them.
# ===========================================================================
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


# ===========================================================================
# THE FIXTURES. One arena, and the roots are addressed BY INDEX rather than by a
# hand-kept record of indices -- `Gate.rs` is the list `dm_root` indexes and
# `nroots` is the count, so a fixture added in the wrong place or a root dropped
# shows up as a moved row rather than as a silently shorter table. That is the
# "pin a COUNT, not just a boolean" row the brief asks for.
#
# `ParamArg` has thirteen fields and `ops.bend` lays them out in declaration
# order, so `param` spells them out; the shape is ops.py:1015's
# `ParamArg(-1, dtype, name=name, vmin_vmax=(min_val,max_val),
# multiple_of=multiple_of, addrspace=AddrSpace.ALU)`.
# ===========================================================================
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
  O.ParamArg{0, dt, Some{0}, Some{O.PyRange{H.i64_of_i32(lo), H.i64_of_i32(vmax)}},
             Some{mult}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}
def dm_param(dt: S.Dt, mult: U32, nm: String) -> O.ParamArg:
  dm_param.range(dt, mult, nm, 0, 100)

# `vmax` is a parameter because the ZERO DIVISOR arm needs a PARAM whose declared
# range is the POINT 0 -- `UOp.variable('y',0,0)` -- and that is the ONLY way
# `y.vmin == y.vmax == 0` holds for a non-CONST divisor.

# THE NODE LIST, IN BINDING ORDER. 1-11 are the CONSTs, 12-18 the PARAMs, 19 on
# are the intermediates and then the roots. The comment on each root is the
# oracle's answer. THE LAST ARENA THREADED IS THE THING TO RE-READ: `py05` is
# built from `Found.ar(py)` and every node after it is built from `Found.ar(py05)`,
# because an index is only meaningful in the arena that produced it and `+` does
# not enforce that (see bend2-constraints, rule 4 of the 2026-09-30 divandmod set).
#  0 bottom NOOP (Arena.empty)
#  1 CONST 0    2 CONST 1    3 CONST 3    4 CONST 4    5 CONST 5    6 CONST 6
#  7 CONST 7    8 CONST 10   9 CONST -2  10 CONST -4  11 CONST -7
# 12 PARAM "x" weakint multiple_of 1     13 PARAM "p" weakint multiple_of 4
# 14 PARAM "q" weakint multiple_of 3     15 PARAM "z" weakint multiple_of 1
# 16 PARAM "i" int32   multiple_of 1     17 PARAM "y" weakint range (0,0)
# 18 PARAM "u" weakint range (0,5)
# 19 FLOORDIV(Px,C(3))                     the `x//c`
# 20 ADD(19,C(5))  21 ADD(C(5),19)  22 ADD(19,C(10))  23 ADD(Px,C(10))  24 ADD(Px,C(3))
# 25 ADD(C(10),Px)  26 ADD(Pi,C(10))
# 27..52 the twenty-six roots, in `dm_root` order
#
# ROOTS, in the order `dm_root` indexes them, with the oracle's tree:
#  r00 t0_a   FLOORDIV(ADD(FLOORDIV(Px,C(3)),C(5)),C(7))
#             -> FLOORDIV(ADD(Px,MUL(C(5),C(3))),MUL(C(3),C(7)))
#  r01 t0_b   ... the SWAPPED add; the same answer
#  r02 t0_c   (x//3 + 10)//7 -> rule 0 AND rule 1 both fire, differently. FIRST-WINS.
#  r03 t0_neg //-7: rule 0 skips on d.vmin>0 and rule 1 answers -> ADD(...,C(-1))
#  r04 t0_d0  //0:  Python RAISES ZeroDivisionError. rule 0 skips, rule 1 skips on
#             d.val==0, rule 2 reports it. `on=0`.
#  r05 t1_fd  (Px+C(10))//7  -> ADD(FLOORDIV(ADD(Px,C(3)),C(7)),C(1))
#  r06 t1_fm  (Px+C(10))%7   -> FLOORMOD(ADD(Px,C(3)),C(7))
#  r07 t1_same (Px+C(3))//7   -> None: c%d == c
#  r08 t1_swap C(10)+Px       -> the same as r05: x goes FIRST
#  r09 t1_d1  //1             -> ADD(FLOORDIV(ADD(Px,C(0)),C(1)),C(10))
#  r10 t1_dn  //-7            -> ADD(FLOORDIV(ADD(Px,C(-4)),C(-7)),C(-2)). THE FLOOR ROW.
#  r11 t1_d0  //0             -> Python RAISES. `on=0`
#  r12 t1_i   int32 numerator -> None. THE WEAKINT-CONJUNCT ROW.
#  r13 t2_cst FLOORDIV(C(6),C(4))     -> CONST(1)
#  r14 t2_cst2 FLOORMOD(C(6),C(4))    -> SUB(C(6),MUL(C(1),C(4)))   [Python: ADD(MUL(MUL,-1))]
#  r15 t2_cn  FLOORDIV(C(-7),C(4))    -> CONST(-2). THE FLOOR ROW.
#  r16 t2_cm  FLOORMOD(C(-7),C(4))    -> SUB(C(-7),MUL(C(-2),C(4)))
#  r17 t2_pm  FLOORMOD(Pp,C(4))       -> CONST(0): multiple_of 4 % 4 == 0
#  r18 t2_p1  FLOORMOD(Pz,C(1))       -> CONST(0): multiple_of DEFAULTS to 1
#  r19 t2_pd  FLOORDIV(Pp,C(4))       -> None: the lambda returns None for FLOORDIV
#  r20 t2_p3  FLOORMOD(Pq,C(4))       -> None: 3 % 4 != 0
#  r21 t2_var FLOORMOD(Px,C(4))       -> None: past divandmod.py:15
#  r22 n_3src FLOORDIV(ADD(Px,C(10)),C(7),C(1)) -> rule 2 CLAIMS it; Python then
#             RAISES ValueError on `x, y = d.src`
#  r23 y0_fd  FLOORDIV(Px,Py0)         -> rule 2's zero test on a PARAM range (0,0).
#             Python RAISES ZeroDivisionError.
#  r24 y0_fm  FLOORMOD(Px,Py0)         -> the same, modulo
#  r25 y05    FLOORDIV(Px,Pu) where Pu's range is (0,5) -- `vmin == 0` but `vmax`
#             is not, so Python does NOT raise and `zero_r25` is 0. THE ROW for
#             `y.vmin==y.vmax==0` being a CONJUNCTION and not `vmin==0`: with the
#             vmax half dropped, the mutation table shows this row moving and
#             nothing else.
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
  +q3 = O.UOp.alu(O.Found.ar(py05), O.OpsFLOORDIV{}, [O.Found.i(px), O.Found.i(c3)])
  +a5 = O.UOp.alu(O.Found.ar(q3), O.OpsADD{}, [O.Found.i(q3), O.Found.i(c5)])
  +b5 = O.UOp.alu(O.Found.ar(a5), O.OpsADD{}, [O.Found.i(c5), O.Found.i(q3)])
  +a10 = O.UOp.alu(O.Found.ar(b5), O.OpsADD{}, [O.Found.i(q3), O.Found.i(c10)])
  +x10 = O.UOp.alu(O.Found.ar(a10), O.OpsADD{}, [O.Found.i(px), O.Found.i(c10)])
  +c10x = O.UOp.alu(O.Found.ar(x10), O.OpsADD{}, [O.Found.i(c10), O.Found.i(px)])
  +x3 = O.UOp.alu(O.Found.ar(c10x), O.OpsADD{}, [O.Found.i(px), O.Found.i(c3)])
  +i10 = O.UOp.alu(O.Found.ar(x3), O.OpsADD{}, [O.Found.i(pi), O.Found.i(c10)])
  # the eight FLOORMOD/FLOORDIV roots of the two Fast Inline Rules
  +r00 = O.UOp.alu(O.Found.ar(i10), O.OpsFLOORDIV{}, [O.Found.i(a5), O.Found.i(c7)])
  +r01 = O.UOp.alu(O.Found.ar(r00), O.OpsFLOORDIV{}, [O.Found.i(b5), O.Found.i(c7)])
  +r02 = O.UOp.alu(O.Found.ar(r01), O.OpsFLOORDIV{}, [O.Found.i(a10), O.Found.i(c7)])
  +r03 = O.UOp.alu(O.Found.ar(r02), O.OpsFLOORDIV{}, [O.Found.i(a5), O.Found.i(cm7)])
  +r04 = O.UOp.alu(O.Found.ar(r03), O.OpsFLOORDIV{}, [O.Found.i(a5), O.Found.i(c0)])
  +r05 = O.UOp.alu(O.Found.ar(r04), O.OpsFLOORDIV{}, [O.Found.i(x10), O.Found.i(c7)])
  +r06 = O.UOp.alu(O.Found.ar(r05), O.OpsFLOORMOD{}, [O.Found.i(x10), O.Found.i(c7)])
  +r07 = O.UOp.alu(O.Found.ar(r06), O.OpsFLOORDIV{}, [O.Found.i(x3), O.Found.i(c7)])
  +r08 = O.UOp.alu(O.Found.ar(r07), O.OpsFLOORDIV{}, [O.Found.i(c10x), O.Found.i(c7)])
  +r09 = O.UOp.alu(O.Found.ar(r08), O.OpsFLOORDIV{}, [O.Found.i(x10), O.Found.i(c1)])
  +r10 = O.UOp.alu(O.Found.ar(r09), O.OpsFLOORDIV{}, [O.Found.i(x10), O.Found.i(cm7)])
  +r11 = O.UOp.alu(O.Found.ar(r10), O.OpsFLOORDIV{}, [O.Found.i(x10), O.Found.i(c0)])
  +r12 = O.UOp.alu(O.Found.ar(r11), O.OpsFLOORDIV{}, [O.Found.i(i10), O.Found.i(c7)])
  # the nine `fold_divmod_general` roots
  +r13 = O.UOp.alu(O.Found.ar(r12), O.OpsFLOORDIV{}, [O.Found.i(c6), O.Found.i(c4)])
  +r14 = O.UOp.alu(O.Found.ar(r13), O.OpsFLOORMOD{}, [O.Found.i(c6), O.Found.i(c4)])
  +r15 = O.UOp.alu(O.Found.ar(r14), O.OpsFLOORDIV{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r16 = O.UOp.alu(O.Found.ar(r15), O.OpsFLOORMOD{}, [O.Found.i(cm7), O.Found.i(c4)])
  +r17 = O.UOp.alu(O.Found.ar(r16), O.OpsFLOORMOD{}, [O.Found.i(pp), O.Found.i(c4)])
  +r18 = O.UOp.alu(O.Found.ar(r17), O.OpsFLOORMOD{}, [O.Found.i(pz), O.Found.i(c1)])
  +r19 = O.UOp.alu(O.Found.ar(r18), O.OpsFLOORDIV{}, [O.Found.i(pp), O.Found.i(c4)])
  +r20 = O.UOp.alu(O.Found.ar(r19), O.OpsFLOORMOD{}, [O.Found.i(pq), O.Found.i(c4)])
  +r21 = O.UOp.alu(O.Found.ar(r20), O.OpsFLOORMOD{}, [O.Found.i(px), O.Found.i(c4)])
  # the arity row and the two zero-divisor rows
  +r22 = O.UOp.alu(O.Found.ar(r21), O.OpsFLOORDIV{}, [O.Found.i(x10), O.Found.i(c7), O.Found.i(c1)])
  +r23 = O.UOp.alu(O.Found.ar(r22), O.OpsFLOORDIV{}, [O.Found.i(px), O.Found.i(py)])
  +r24 = O.UOp.alu(O.Found.ar(r23), O.OpsFLOORMOD{}, [O.Found.i(px), O.Found.i(py)])
  +r25 = O.UOp.alu(O.Found.ar(r24), O.OpsFLOORDIV{}, [O.Found.i(px), O.Found.i(py05)])
  Gate{O.Found.ar(r25), [O.Found.i(r00), O.Found.i(r01), O.Found.i(r02), O.Found.i(r03), O.Found.i(r04), O.Found.i(r05), O.Found.i(r06), O.Found.i(r07), O.Found.i(r08), O.Found.i(r09), O.Found.i(r10), O.Found.i(r11), O.Found.i(r12), O.Found.i(r13), O.Found.i(r14), O.Found.i(r15), O.Found.i(r16), O.Found.i(r17), O.Found.i(r18), O.Found.i(r19), O.Found.i(r20), O.Found.i(r21), O.Found.i(r22), O.Found.i(r23), O.Found.i(r24), O.Found.i(r25)]}

# ===========================================================================
# NOT PORTED, one line each, with the WALL and the phase that owns it. The
# block is the same shape `ops.bend` and `fold.bend` use.
# ===========================================================================
# TODO(p3) divandmod.py:13 the RANGE HALF of `x//y` being a point -- PORTED for
#   CONST/CONST only, where `_min_max` (ops.py:1127) is four identical `a//b` and
#   the test is always true. Outside CONST/CONST it needs `_min_max`. WALL:
#   `UOp._min_max`, P3. See fold.bend:2178.
# TODO(p3) divandmod.py:13-15 a FLOAT CONST -- `_min_max` returns PyConst and
#   `dm_val` reads `CInt` only, so rules 0 and 1 SKIP on a `CFloat` divisor where
#   Python rewrites. WALL: PyConst (float | bool | Invalid), P3.
# TODO(p3) divandmod.py:17-19 `x.pop_const()` and `split_uop(Ops.ADD)` -- both are
#   op-shape walks over a fuel-bound src list and neither has a caller once line
#   23 is gone, so neither is written. WALL: none -- these ARE expressible; they
#   are P3 for SCOPE, not for impossibility, and they land with line 23.
# TODO(p3) divandmod.py:23-25 `nested_div`, needs `x.src[1].divides(c)`.
#   WALL: `divides` (ops.py:1067) needs `gcd` (ops.py:1083) needs a `Counter`
#   fold. fold.bend:2174.
# TODO(p3) divandmod.py:28-35 `remove_nested_mod` -- `divides`, same wall.
# TODO(p3) divandmod.py:37-48 `fold_divmod_congruence` -- the WORST one.
#   `itertools.product` over per-term sign choices, then
#   `sum(r*v for r,v in zip(...)).vmin//c == rem.vmax//c`. It is interval
#   arithmetic over a symbolic SUM, so it needs `_min_max` on a node the fold has
#   never built, AND a cartesian product, AND `min(r, r-c, key=abs)`. WALL:
#   `_min_max`; the product is a fold over a `List<List<U32>>` and Bend has no
#   cartesian product and no `min` over three with a key function. P3.
# TODO(p3) divandmod.py:50-55 `gcd_with_remainder` -- `math.gcd(*factors, c)`,
#   `divides`, `.simplify()` and `new_x.vmin >= 0`. WALL: `gcd`, `_min_max`,
#   `simplify`. `math.gcd` over a VARIADIC fold is a fold over a list, which is
#   expressible; the rest is not.
# TODO(p3) divandmod.py:57-70 `nest_by_factor` -- the set comprehension
#   `{abs(f) for u, f in zip(...) if ...}` is a set (an ORDERED fold with a dedup
#   step), then a RECURSIVE call to `fold_divmod_general(x//div)` (mutual
#   recursion, refused), then `backward_slice` twice for the `min(results, key=
#   len(slice))`. WALL: mutual recursion (Bend refuses it outright, so the port
#   needs the pass/fold structure `fold.bend` uses for the OTHER direction),
#   `backward_slice` (a set walk, fold.bend:2130), and `_min_max`. P3, and the
#   largest single omission in this file.
# TODO(p3) divandmod.py:75-96 `divide_by_gcd` and `factor_remainder` --
#   `UOp.gcd(*all_uops, y)`, `.simplify()`, `divide_exact` (which needs `divides`),
#   `const_factor` (a `Counter` fold), `u.divides(c)*(c%y.val)` and `y.vmin<0` /
#   `x.vmin<0`. WALL: `gcd`, `const_factor`, `simplify`, `_min_max`. P3.
# TODO(p3) divandmod.py:11 the `raise` itself -- Python's
#   `ZeroDivisionError(f"{'Division' if d.op is Ops.FLOORDIV else 'Mod'} by zero
#   trying to rewrite {x.alu(d.op, y)}")` needs a `raise` and an f-string over a
#   UOp. `dm_zero` REPORTS the condition and `zero_r04`/`zero_r11`/`zero_r23` are
#   the rows; rendering the message is the caller's job, exactly as `fold.bend`
#   does for `UOp.shape`'s `if (ret:=self._shape) is None: raise`. NO ACTION
#   beyond P3 at the call site.
# ---------------------------------------------------------------------------
#
# WHAT NEXT, in the order the walls fall.
#   1. `_min_max` (ops.py:1104) unblocks `dm_point`'s range half, the `x.vmin>=0`
#      and `b.vmin/b.vmax` guards in `nest_by_factor` and `factor_remainder`, and
#      the float-CONST cases in BOTH Fast Inline Rules. It is the unlock for
#      FIVE of the nine TODOs above.
#   2. `const_factor` / `divides` / `gcd` (ops.py:1058/1067/1083) unblock
#      `nested_div`, `remove_nested_mod` and `gcd_with_remainder` -- three more,
#      and they are all one `Counter` fold.
#   3. `simplify` / `ssimplify` (ops.py:513/520) is what `fold_divmod_general`
#      line 78 calls on `UOp.gcd(...)`, and `ops.bend` records it as the largest
#      single unlock in ITS half too.
#   4. Only after those three does `fold_divmod_congruence` become a question,
#      and only after THAT does the cartesian product need a shape.

# ===========================================================================
# THE ROWS. Every one is a claim PYTHON FIXES: a table count, a reject-set
# length, a `vmin == vmax == 0` flag, a rewritten tree, an arena-growth count,
# or a fired/skipped flag. Nothing here restates the code.
# ===========================================================================
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
# lower per folded CONST MUL (divergence C), and it is here because it is the
# only NUMERIC discriminator between first-wins and last-wins on `r02`: rule 0
# adds four (MUL, ADD, MUL, FLOORDIV) and rule 1 adds three (ADD, FLOORDIV, ADD
# -- its two CONSTs are already interned). So `r02` reads 4 under first-wins and
# 3 under last-wins, and a conjunction would give 7.
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

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("nrules", t_nrules())
    b : Unit <- row("rej0", dm_rejlen(0))
    c : Unit <- row("rej1", dm_rejlen(1))
    d : Unit <- row("rej2", dm_rejlen(2))
    e : Unit <- row("nroots", t_nroots())
    # the ZERO DIVISOR, which Python raises on
    f : Unit <- row("zero_r04", t_zero(4))
    g0 : Unit <- row("zero_r11", t_zero(11))
    h : Unit <- row("zero_r23", t_zero(23))
    i : Unit <- row("zero_r05", t_zero(5))
    j : Unit <- row("zero_r15", t_zero(15))
    # the twenty-five roots: did a rule fire, and to what
    k : Unit <- row("on_r00", t_on(trees(), 0))
    l : Unit <- rows("out_r00", t_out(trees(), 0))
    m : Unit <- row("on_r01", t_on(trees(), 1))
    n : Unit <- rows("out_r01", t_out(trees(), 1))
    o : Unit <- row("on_r02", t_on(trees(), 2))
    p : Unit <- rows("out_r02", t_out(trees(), 2))
    q : Unit <- row("grown_r02", t_grown(trees(), 2))
    r : Unit <- row("on_r03", t_on(trees(), 3))
    s : Unit <- rows("out_r03", t_out(trees(), 3))
    t : Unit <- row("on_r04", t_on(trees(), 4))
    u : Unit <- row("on_r05", t_on(trees(), 5))
    v : Unit <- rows("out_r05", t_out(trees(), 5))
    w : Unit <- row("on_r06", t_on(trees(), 6))
    x : Unit <- rows("out_r06", t_out(trees(), 6))
    y : Unit <- row("on_r07", t_on(trees(), 7))
    z : Unit <- rows("out_r07", t_out(trees(), 7))
    a1 : Unit <- row("on_r08", t_on(trees(), 8))
    b1 : Unit <- rows("out_r08", t_out(trees(), 8))
    c1 : Unit <- row("on_r09", t_on(trees(), 9))
    d1 : Unit <- rows("out_r09", t_out(trees(), 9))
    e1 : Unit <- row("on_r10", t_on(trees(), 10))
    f1 : Unit <- rows("out_r10", t_out(trees(), 10))
    g1 : Unit <- row("on_r11", t_on(trees(), 11))
    h1 : Unit <- row("on_r12", t_on(trees(), 12))
    i1 : Unit <- rows("out_r12", t_out(trees(), 12))
    j1 : Unit <- row("on_r13", t_on(trees(), 13))
    k1 : Unit <- rows("out_r13", t_out(trees(), 13))
    l1 : Unit <- rows("out_r14", t_out(trees(), 14))
    m1 : Unit <- rows("out_r15", t_out(trees(), 15))
    n1 : Unit <- rows("out_r16", t_out(trees(), 16))
    o1 : Unit <- rows("out_r17", t_out(trees(), 17))
    p1 : Unit <- rows("out_r18", t_out(trees(), 18))
    q1 : Unit <- rows("out_r19", t_out(trees(), 19))
    r1 : Unit <- rows("out_r20", t_out(trees(), 20))
    s1 : Unit <- rows("out_r21", t_out(trees(), 21))
    t1 : Unit <- row("on_r22", t_on(trees(), 22))
    u1 : Unit <- row("on_r23", t_on(trees(), 23))
    v1 : Unit <- row("on_r24", t_on(trees(), 24))
    # the growth counts that pin each rule's SHAPE as well as its answer
    w1 : Unit <- row("grown_r00", t_grown(trees(), 0))
    x1 : Unit <- row("grown_r05", t_grown(trees(), 5))
    y1 : Unit <- row("grown_r06", t_grown(trees(), 6))
    row("grown_r01", t_grown(trees(), 1))
    row("zero_r25", t_zero(25))
    row("on_r25", t_on(trees(), 25))
    rows("out_r25", t_out(trees(), 25))

# ===========================================================================
# THE FUZZ DRIVER. NO ARGUMENT IS THE GATE ABOVE, UNCHANGED; ONE ARGUMENT IS A
# CASE FILE, and the case is ONE LINE `op|a|b` -- a CONST/CONST tree the same way
# the gate's `r13`..`r16` fixtures build theirs. `sz.bend`'s `main` and
# `upat.bend`'s `dispatch` read their argument the same way, and for the same
# reason: the dispatch is on the SHAPE of the argument list, so a missing case
# file cannot be mistaken for a case.
#
# THE CANONICAL LINE IS THE FOLD'S DENOTATION, not its tree, and that is a
# decision with a reason. `dm_point` answers a CONST/CONST FLOORDIV with
# `CONST q` and a CONST/CONST FLOORMOD with `SUB(x, MUL(q, y))` (divergence B:
# Python writes the same number as `ADD(MUL(MUL, C(-1)))`), so a tree-shaped
# line would compare Python's canonicalisation against this file's -- a
# divergence the header already states, restated every case. The DENOTATION is
# the same integer on both sides and is the only line that does not re-report a
# known divergence, so it is the line. `nofold` is Python's `None`; `RAISED`
# is its `ZeroDivisionError` at divandmod.py:11, which this file reports as the
# Bool `dm_zero` and the header already pins at `zero_r04`/`zero_r11`/`zero_r23`.
# ===========================================================================

# `op` -- the four ops the case format spells. CDIV/CMOD are here because they
# are REAL Ops that the table does NOT claim, so a case naming one must print
# `nofold` on both sides: it is the row that says the table's op set is
# {FLOORDIV, FLOORMOD} and not something wider. FDIV is the float one, for the
# same reason.
def dmc.op(s: String) -> O.Op:
  match s:
    case "FLOORDIV": O.OpsFLOORDIV{}
    case "FLOORMOD": O.OpsFLOORMOD{}
    case "CDIV": O.OpsCDIV{}
    case "CMOD": O.OpsCMOD{}
    case "FDIV": O.OpsFDIV{}
    case _: O.OpsFLOORDIV{}

# a signed decimal literal as a `U32` bit pattern. `a` and `b` are int32 in
# both languages and this file has no signed type, so the case's decimal is read
# as a magnitude and NEGATED here -- `H.i32_neg` is `U32.sub(0, x)`, which is
# the two's complement Python writes. A leading `-` is the only sign, which is
# all the generator emits.
def dmc.num.chars(cs: List<&2, Char>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case c <> t: dmc.num.chars(t, U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(c), 48)))

def dmc.num.of(s: String) -> U32:
  dmc.num.chars(String.to_list(s), 0)

def dmc.num.put(neg: Bool, v: U32) -> U32:
  match neg:
    case True{}: H.i32_neg(v)
    case False{}: v

def dmc.num.go(neg: Bool, s: String) -> U32:
  match neg:
    case True{}: dmc.num.put(True{}, dmc.num.of(String.drop(s, 1n)))
    case False{}: dmc.num.of(s)

def dmc.num(+s: String) -> U32:
  dmc.num.go(String.starts_with(s, "-"), s)

def dmc.nth(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "0"

def dmc.field(fs: List<&2, String>, k: U32) -> String:
  dmc.nth(List.get(&2, String, fs, U32.to_nat(k)))

# THE ARENA: two CONSTs and the op node, in binding order, exactly the shape
# `trees()` builds for `r13`..`r16`. The last arena threaded is the one that
# produced the index, so every node after `c0` is built from `Found.ar` of the
# node before it.
def dmc.arena(op: O.Op, a: U32, b: U32) -> O.Found:
  +ar = O.Arena.empty()
  +ca = O.UOp.const(ar, O.CInt{H.i64_of_i32(a)})
  +cb = O.UOp.const(O.Found.ar(ca), O.CInt{H.i64_of_i32(b)})
  O.UOp.alu(O.Found.ar(cb), op, [O.Found.i(ca), O.Found.i(cb)])

# THE DENOTATION of a folded node, read off the tree the port ANSWERED with. A
# CONST is its own value; the `SUB(x, MUL(q, y))` `dm_point.sub` builds is
# `x - q*y`. `q` is READ from the port's own interned node, never re-derived
# here, so a port that folded the wrong quotient denotates the wrong number.
#
# THE ARITHMETIC IS 32-BIT AND PYTHON'S IS NOT, and that is the point: tinygrad
# CONSTs are mathematical Python ints, so `1 % -2147483648` is 1 while this
# file's `MUL(-1, INT_MIN)` is already 2^31 before the SUB. Both sides'
# TREES denote the same integer -- `1 - 2147483648 == -2147483647` -- and the
# oracle evaluates the tree in Python's unbounded ints precisely so this line
# compares denotations and not arithmetic widths.
def dmc.den.const(ar: O.Arena, i: U32) -> U32:
  dm_ival(dm_val(ar, i))

def dmc.den.mul(+ar: O.Arena, +m: U32) -> U32:
  U32.mul(dmc.den.const(ar, O.Arena.src0(ar, m)), dmc.den.const(ar, O.Arena.src(ar, m, 1)))

def dmc.den.sub(+ar: O.Arena, +d: U32) -> U32:
  U32.sub(dmc.den.const(ar, O.Arena.src0(ar, d)), dmc.den.mul(ar, O.Arena.src(ar, d, 1)))

def dmc.den.go(op: O.Op, ar: O.Arena, i: U32) -> U32:
  match op:
    case O.OpsCONST{}: dmc.den.const(ar, i)
    case O.OpsSUB{}: dmc.den.sub(ar, i)
    case _: 0

def dmc.den(+ar: O.Arena, +i: U32) -> U32:
  dmc.den.go(O.Arena.op(ar, i), ar, i)

# THE TWO CANONICAL ANSWERS, plus the one Python REFUSES. `CONST n` is a folded
# value and `nofold` is its `None`. `RAISED` is its `ZeroDivisionError` at
# divandmod.py:11: this file has no `raise` and reports the condition as the
# Bool `dm_zero`, which the gate pins at `zero_r04`/`zero_r11`/`zero_r23`, so
# `RAISED` is a distinct word and not a synonym for `nofold`.
def dmc.out.hit.go(on: U32, v: U32) -> String:
  match on:
    case 0: "nofold"
    case _: String.concat(["CONST ", dm_show(v)])

def dmc.out.hit(+h: Hit) -> String:
  dmc.out.hit.go(Hit.on(h), dmc.den(Hit.ar(h), Hit.i(h)))

def dmc.out(zero: Bool, +h: Hit) -> String:
  match zero:
    case True{}: "RAISED"
    case _: dmc.out.hit(h)

# The zero test is reported ONLY where Python reaches `fold_divmod_general` at
# all, which is where RULE 2 claims the node: divandmod.py:11 is inside
# `fold_divmod_general` and rule 2 is its only caller. A CMOD root is claimed by
# nobody, so Python answers `None` there and never raises -- asking `dm_zero`
# about it would print `RAISED` for a node Python does not look at, which is the
# HARNESS re-reporting its own mistake and not the port's. The op set is READ
# from `dm_table()` rather than spelled here, so a wider rule 2 moves the word
# with it instead of silently disagreeing with it.
def dmc.two.go(m: Maybe<&2, O.PMEntry>) -> List<&2, O.Op>:
  match m:
    case Some{e}: O.PMEntry.ops(e)
    case None{}: Nil{}

def dmc.two() -> List<&2, O.Op>:
  dmc.two.go(List.get(&2, O.PMEntry, O.PMEntrys.es(dm_table()), 2n))

def dmc.of.put.go(zero: Bool, +h: Hit) -> String:
  dmc.out(zero, h)

def dmc.of.put.reach(+f: O.Found) -> Bool:
  O.pm_claimed(dmc.two(), O.Found.ar(f), O.Found.i(f))

# the case: `op|a|b`, one line. The zero test is on the ROOT, which is the index
# the scan was given, and it runs on the arena the scan ran on.
def dmc.of.put(+f: O.Found) -> String:
  dmc.of.put.go(Bool.and(dmc.of.put.reach(f), dm_zero(O.Found.ar(f), O.Found.i(f))),
                div_and_mod_symbolic(F.folded(O.Found.ar(f)), O.Found.i(f)))

def dmc.of(+fs: List<&2, String>) -> String:
  dmc.of.put(dmc.arena(dmc.op(dmc.field(fs, 0)),
                       dmc.num(dmc.field(fs, 1)),
                       dmc.num(dmc.field(fs, 2))))

def dmc.run(p: String) -> IO(Unit):
  do IO<Unit>:
    s : String <- H.printable(p, 1)
    IO.print(dmc.of(String.split(s, '|')))

def dispatch(ps: List<&1, String>) -> IO(Unit):
  match ps:
    case Nil{}: gate()
    case p <> _: dmc.run(p)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    u : Unit <- dispatch(List.tail(&1, String, as))
    IO.pure(Unit, u)
