# symbolic.bend -- tinygrad/uop/symbolic.py. The REWRITER: four rule tables,
# the fold-like rule bodies, and `exec_alu`'s numeric evaluation.
#
# THE INVENTORY, def by def: 475 Python lines, and the honest question is not
# "how much is ported" but "which is a TABLE, which is a FOLD, and which is a
# REWRITE that needs a property the substrate does not have".
#
#   #  PY      KIND                  STATE
#   1  16      fold  simplify_pow        PARTIAL  (the int arms; the half
#                                            exponent needs an F32<->I64 compare
#                                            helpers.bend cannot express)
#   2  23      fold  fold_bitcast        PORTED   (truncate reaches only the six
#                                            dtypes Bend can state -- see below)
#   3  29      fold  fold_const_alu      PORTED   (exec_alu over U32 and F32)
#   4  31      fold  _quotient_base      PORTED   (index arithmetic + pop_const)
#   5  43      fold  fold_add_divmod_recombine  PORTED
#   6  63-70   data  invalid_pat/gate/bare_const/casted_const/const_arg  PORTED
#   7  72      fold  lift_reduce_gate    DEFERRED `UOp.ranges` (fold.bend
#                                            TODO(p3) ops.py:483)
#   8  79-102  table pm_data_invalid      13 of 14  (rule 6 is #7)
#   9  104-108 table pm_remove_invalid    2 of 2
#  10  110     fold  fold_const_where     PORTED
#  11  115-199 table symbolic_simple      PORTED for the rules that need nothing
#                                            but `alu`/`where`/`const_like`
#  12  203     fold  lt_folding           DEFERRED `const_factor` -> gcd on I64
#  13  209     fold  canonicalize_simplex DEFERRED `UOp.vmin` (_min_max)
#  14  222-226 table commutative          DEFERRED `UOp.tuplize`
#  15  228     fold  fold_where_closure   DEFERRED `bool_slice` + `substitute`
#  16  235-324 table symbolic             DEFERRED -- every one of the 47 reaches
#                                            for `vmin`/`vmax`/`const_factor`/
#                                            `tuplize`/`bool_slice`
#  17  328-386 fold  parse_valid / uop_given_valid / _valid_priority /
#                                 simplify_valid   DEFERRED, all four
#  18  390     fold  reduce_mul_chain     DEFERRED `backward_slice` + `vmin`
#  19  400-403 fold  drop_and_clauses + pm_drop_and_clauses  DEFERRED `ranges`
#  20  406-425 fold  where_on_load + pm_move_where_on_load  DEFERRED `ranges` +
#                                            `backward_slice_with_self`
#  21  427-438 fold  gated_given_valid + pm_simplify_valid DEFERRED `IMAGE` + #17
#  22  442-448 table pm_clean_up_group_sink  2 of 2
#  23  450-475 table sym                   the reciprocal / store / load rules
#
# THE THREE WALLS, measured against the substrate rather than guessed.
#
# 1. `exec_alu` OVER A CLOSED ALU TREE: YES, for `U32` AND `F32`, and the overflow
#    and sign semantics are RIGHT for the 32-bit widths. `U32.add/sub/mul` wrap mod
#    2^32, which IS int32/uint32 wrap; `H.asr` supplies the arithmetic shift `>>`
#    needs and Bend does not have; and the zero-divisor reading agrees because
#    `U32.div(a,0) = 0` is the number Python's `floordiv` is given by helpers.py:76.
#    WHAT IT CANNOT DO, and this is a wall rather than a choice:
#      a. weakint is MATHEMATICAL in tinygrad ("ints stay mathematical past the
#         fold", symbolic.py:28) and the honest 64-bit carrier is `H.I64`.
#         `helpers.bend` has `i64_add`, `i64_sub`, `i64_cmp` and NOT `i64_mul`,
#         `i64_div` or `i64_mod`, so a weakint result outside the int32 range
#         cannot be computed here. `exec_alu` answers `None{}` for it, which is
#         Python's "the fold does not apply" -- the node is left alone. A NEGATIVE
#         const is refused by the same lane for a second reason, and it is named
#         with its measurement at `exec_alu.pick`.
#      b. `truncate` (dtype.py:297) is a C-effect table for int8/16/64,
#         uint8/16/64, float16, bfloat16, the four fp8s and float64. Those
#         widths answer `None{}`.
#    So `exec_alu_i32` and `exec_alu_f32` are the two lanes, they are exact, and
#    the gate drives both.
# 2. THE OPERATOR LAYER. Almost every rule body is an expression of UOp algebra --
#    `x + c`, `x // c`, `x != 0`, `x & y` -- and in Python those are
#    `mixin/elementwise.py`'s `__add__`/`__floordiv__`/`__ne__`, each of which is
#    `_broadcasted` (a dtype promotion) followed by `alu`. `mixin/elementwise.py`
#    is NOT PORTED, so `sy_alu1/2/3` is the RAW `alu` and every rule body is the
#    RAW node. This is the single largest divergence in the file: a rule here is
#    only faithful on a fixture whose src dtypes already agree. The `promo` gate
#    row is where that restriction is stated.
# 3. `graph_rewrite` (ops.py:1880) IS NOT THIS FILE and is not ported. What IS
#    here is the part symbolic.py owns: the table, the first-wins fold over it,
#    and the `ret is not uop` test that ops.py:1605 makes load-bearing. So
#    `sym_rewrite(fx, u) -> Maybe<&1, U32>` is `PatternMatcher.rewrite` and the
#    fixed-point driver around it is P3.
#
# THE FIRST-WINS FOLD AND THE `ret is not uop` TEST. ops.py:1605 is
#     if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret
# so a rule that returns the node ITSELF has no opinion -- which is the whole of
# `x+0 -> x`, `x&0 -> 0` and `x>>0 -> x` in one test, and NOT an accident.
# `sy_novel` is that test. The scan is a fold with first-wins (`sy_keep` keys on
# the ACCUMULATOR), so a later rule that fires is discarded; in Python the arena
# is a global cache and the discarded node is simply garbage, and here it is a
# DEAD INDEX in a monotone arena, which is the same thing with a name.
#
# `early_reject` IS A NECESSARY CONDITION, not a veto: ops.py:1609 is
# `if not early_reject.issubset(ler): continue`, so the rule FIRES when the op
# set IS a subset of the node's src ops. It is built from the op of the
# pattern's FIRST src and only when that src is a SINGLE-op UPat
# (ops.py:1475-1478), and `O.pm_early` is ops.bend's own subset test over a
# `ler` that folds EVERY src. `rej` in the gate counts the entries whose reject
# set is non-empty, and that count is the only place a MISSPELLED reject set shows
# up at all.
#
# THE NAME-REBIND RULE. A pattern that binds one name twice WITHIN A SINGLE SRC
# TUPLE is the `mixin/gradient.py:101` shape: bound to two different nodes, and
# the rule only matches when they are the SAME node. Without the identity check
# the rule matches strictly more nodes than intended, and it typechecks. Two are
# here and both are LOAD-BEARING:
#     symbolic.py:123  (x ^ y) ^ y      -- `y` twice, the rule is (x^y)^y -> x
#     symbolic.py:124  (x % y) % y      -- `y` twice, the rule is (x%y)%y -> x%y
# Every rule below that binds a name twice carries `U32.is_eq`, and `rebind`/
# `rebind0` and `xorb`/`xorb0` in the gate are the two-sided rows that say so.
#
# THE `is_any` CASE IS SAFE AND STAYS A DISJUNCTION. symbolic.py:180 binds `c`
# in two `is_any` ALTERNATIVES; `is_any` copies the store per alternative so they
# never meet, and adding an identity check there would turn a disjunction into a
# conjunction and drop the bare `CONST(Invalid)` lane.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# THE PRELUDE. Everything symbolic.py GETS FROM ELSEWHERE, in dependency order,
# because Bend has no forward references and mutual recursion is refused. Every
# def here names the Python it is; none of it is new abstraction.
#
# THE SHAPE OF A RULE, and it is the one thing to get right. A rule is TWO defs:
#   * `sym_N.pat` -- the PATTERN's own tests (op, arity, src ops, dtypes, and
#     the identity check for a rebind). It is total and it never grows the arena.
#   * `sym_N`     -- the BODY. It is only ever called when the pattern holds, so
#     a rule that does not match never touches the arena. That separation is
#     what makes the affine arena safe here: Python's arena is a global cache
#     and a discarded answer is garbage, so Python can call every rule body
#     eagerly. This port cannot, because `Maybe<&1, U32>` is a `Type` and a
#     grown arena has no owner if its index is thrown away.
def sy_ar(x: F.Folded) -> O.Arena: F.Folded.ar(x)

def sy_tb(x: F.Folded) -> F.Table: F.Folded.t(x)

# `UOp.dtype` -- ops.py:246, which is `fold.bend`'s table read, so it is a `Maybe`
def sy_dt(+x: F.Folded, +u: U32) -> Maybe<&2, S.Dt>:
  F.fold.dt(sy_ar(x), sy_tb(x), u)

def sy_dt_of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# `UPat.dtype`'s default IS `dtypes.void` (ops.py:1481), so a node the fold does
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

# `if uop.op in (...)` -- a membership test in an op SET, and `O.op_in` is
# ops.bend's own, so it is written once here and not per rule.
def sy_op_in(+x: F.Folded, +u: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, sy_op(x, u))

def sy_src_op_in(+x: F.Folded, +u: U32, n: U32, ops: List<&2, O.Op>) -> Bool:
  O.op_in(ops, O.Arena.op(F.Folded.ar(x), sy_src(x, u, n)))

def sy_is_op(+x: F.Folded, +u: U32, want: O.Op) -> Bool: O.eq_op(sy_op(x, u), want)

def sy_src_is_op(+x: F.Folded, +u: U32, n: U32, want: O.Op) -> Bool:
  O.eq_op(O.Arena.op(F.Folded.ar(x), sy_src(x, u, n)), want)

# THE TWO-SCRUTINEE GROUP TESTS, as op SETS. `GroupOp.Unary - {CAST, BITCAST}`
# and `GroupOp.Binary - GroupOp.Comparison` are the two set differences
# symbolic.py writes, and a set difference of Ops is a list of the members.
def OP_CASTS() -> List<&2, O.Op>: [O.OpsCAST{}, O.OpsBITCAST{}]

def OP_CMP() -> List<&2, O.Op>: [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}]

def OP_SELF() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsXOR{}, O.OpsOR{}]

def OP_SHIFTS() -> List<&2, O.Op>: [O.OpsSHL{}, O.OpsSHR{}]

# `up if bool(x) else None` -- the shape of most of symbolic.py's rule bodies.
# A `match` may not scrutinise a computed value, so the condition crosses a def
# boundary as a parameter.
def sy_tri(b: Bool, v: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match b:
    case True{}: v
    case False{}: None{}

def sy_tri_u(b: Bool, v: U32) -> Maybe<&1, U32>:
  sy_tri(b, Some{v})

# THE VALUE OF A CONST NODE, and `val` is ops.py:257 -- it reads THROUGH a CAST,
# which is why `(X < c).ne(True)` and `UPat.const` see one value and not two
# nodes. Both arms are here; Python's `assert` on the third is `None{}`.
def sy_val1(a: O.Arg, op: O.Op) -> Maybe<&2, O.Const>:
  match a op:
    case O.APy{v} O.OpsCONST{}: Some{v}
    case _ _: None{}

def sy_val2(+x: F.Folded, +u: U32) -> Maybe<&2, O.Const>:
  sy_val1(sy_arg(x, u), sy_op(x, u))

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

# `UOp.is_invalid` -- ops.py:265, `self.op is Ops.CONST and self.val is Invalid`
def sy_is_invalid(+x: F.Folded, +u: U32) -> Bool: sy_is_invalid.go(sy_val(x, u))

def sy_is_const(+x: F.Folded, +u: U32) -> Bool: sy_is_op(x, u, O.OpsCONST{})

def sy_is_invalid_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_const(x, u), sy_is_invalid(x, u))

# `bool(v)` for a PyConst, which is what `if c.val` reads in symbolic.py:127-128
# and `if gate.val` in `fold_const_where`. NaN is truthy in Python and this
# says so, because `F32.is_ne(nan, 0.0)` is True.
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
# hold the `Maybe` and the consumers need the payload beside a `Bool` that says
# it is there. Two spellings because a fold's answer is `&1` and a `sy_val` out of
# `fold.bend` is `&2`.
def sy_maybe_c2(m: Maybe<&2, O.Const>) -> O.Const:
  match m:
    case Some{v}: v
    case None{}: O.CInt{H.i64_of_i32(0)}

def sy_maybe_c(m: Maybe<&1, O.Const>) -> O.Const:
  match m:
    case Some{v}: v
    case None{}: O.CInt{H.i64_of_i32(0)}

# THE I64 -> U32 BIT PATTERN, and back. `H.i64_of_i32` sign-extends, so for a
# value inside the int32 range it is the identity on the bit pattern and
# `H.lo32` is the identity on the way back. The int lane of `exec_alu` lives in
# these two directions and nowhere else.
def i64_bits(i: H.I64) -> U32: H.lo32(i)

# `truncate` -- dtype.py:297, and the table is where `exec_alu` and `const_like`
# stop. Six of its fourteen entries are pure in Bend and eight are C effects; the
# eight answer `None{}`, which is Python's "this fold does not apply". For weakint
# and weakfloat `DType.const` (dtype.py:79) IS the identity, which is the `Some{v}`
# on the two weak rows.
def sy_trunc(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  match dt:
    case S.Dt{0, 1, S.CBool{}, _}: Some{O.CBool{sy_truthy.go(v)}}
    case S.Dt{0, 800, S.CWeakInt{}, _}: Some{v}
    case S.Dt{9, 800, S.CWeakFloat{}, _}: Some{v}
    case S.Dt{5, 32, S.CSint{}, _}: Some{v}
    case S.Dt{6, 32, S.CUint{}, _}: Some{v}
    case S.Dt{14, 32, S.CFloat{}, _}: Some{v}
    case _: None{}

# THE DTYPE A CONST'S VALUE DERIVES, which is `fold.bend`'s `cconst_dt` and is
# what makes `UOp.const`'s `.cast(dtype)` half load-bearing: a CONST's dtype
# FOLLOWS from its value, so asking for another one needs a CAST on top.
def sy_needs_cast(dt: S.Dt, v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: Bool.not(O.eq_dt(dt, S.boolean()))
    case O.CBool{b}: Bool.not(O.eq_dt(dt, S.boolean()))
    case O.CInt{i}: Bool.not(O.eq_dt(dt, S.weakint()))
    case O.CFloat{f}: Bool.not(O.eq_dt(dt, S.weakfloat()))

# THE UOP SUGAR, and this is where the operator-layer wall lands. What is missing
# is `mixin/elementwise.py`'s PROMOTION, so these are the RAW nodes: `x + y` in
# Python is promote-both-then-`alu` and here it is the `alu` alone (header, wall 2).
def sy_alu1(ar: O.Arena, op: O.Op, x: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x]))

def sy_alu2(ar: O.Arena, op: O.Op, x: U32, y: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x, y]))

def sy_alu3(ar: O.Arena, op: O.Op, x: U32, y: U32, z: U32) -> U32:
  O.Found.i(O.UOp.alu(ar, op, [x, y, z]))

# `x.where(t, f)` -- mixin/elementwise.py's `where`, `UOp(Ops.WHERE, src=(self,t,f))`.
def sy_where(ar: O.Arena, c: U32, t: U32, f: U32) -> U32:
  sy_alu3(ar, O.OpsWHERE{}, c, t, f)

# `-x` -- mixin/elementwise.py:79 is `x * (-1)` for a non-bool, and the rule at
# symbolic.py:122 is written that way, so this is the MUL and not a NEG node.
def sy_neg(+ar: O.Arena, x: U32) -> U32:
  sy_alu2(ar, O.OpsMUL{}, x, O.Found.i(O.UOp.const(ar, O.CInt{H.i64_of_i32(U32.sub(0, 1))})))

# `x != 0` and `x < c` -- the two comparisons the rules below need. In Python
# these are `__ne__` and `__lt__`, which promote; the raw node is CMPNE and
# CMPLT. A comparison's result is a bool CONST, so `1` and `0` are the spellings.
def sy_ne0(+ar: O.Arena, x: U32) -> U32:
  sy_alu2(ar, O.OpsCMPNE{}, x, O.Found.i(O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})))

# `x.cast(dt)` -- mixin/dtype.py:19, `self if self.dtype == dt else
# UOp(Ops.CAST, src=(self,), arg=dt)`. The `if` half is the simplification at
# symbolic.py:178 and is NOT folded here; this is the node.
def sy_cast(ar: O.Arena, x: U32, dt: S.Dt) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{dt}, O.TNone{}))

def sy_bitcast(ar: O.Arena, x: U32, dt: S.Dt) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsBITCAST{}, [x], O.ADt{dt}, O.TNone{}))

# `x.trunc()` -- mixin/elementwise.py:470, a `TRUNC` node on the one src.
def sy_trunc_uop(ar: O.Arena, x: U32) -> U32:
  sy_alu1(ar, O.OpsTRUNC{}, x)

# `x.replace(src=...)` -- ops.py:252, with the op/arg/tag forwarded. Python's
# version also short-circuits when nothing changes; here a `replace` that is a
# no-op interns the SAME node, because the arena hash-conses, so the identity
# is preserved and `sy_novel` sees it.
def sy_replace_src(+ar: O.Arena, +u: U32, src: List<&2, U32>) -> U32:
  O.Found.i(O.UOp.new(ar, O.Arena.op(ar, u), src, O.Arena.arg(ar, u), O.Arena.tag(ar, u)))

# `UOp(Ops.NOOP)` -- symbolic.py:99, :459 and the fold at :454.
def sy_noop(ar: O.Arena) -> U32:
  O.Found.i(O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{}))

# `UOp.const(b, dtype)` -- ops.py:631. `ops.bend`'s own `UOp.const` interns the
# BARE node and its header defers the `.cast(dtype)`; that half is here, because a
# rule table that cannot state a concrete dtype cannot rewrite anything that has
# one. `sy_trunc` runs FIRST, so an untruncatable width grows NOTHING.
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
# (`ret._mop(Ops.EXPAND, arg=self._shape)` when the shapes differ) needs
# `UOp._shape`, which is fold.bend's movement algebra; see the TODO block.
def sy_const_like(+x: F.Folded, +u: U32, v: O.Const) -> Maybe<&1, U32>:
  sy_const(sy_ar(x), sy_dt1(x, u), v)

# `UOp.const_like` at an explicit dtype, which is `UOp.const(b, dtype)` again.
def sy_const_at(+x: F.Folded, +u: U32, dt: S.Dt, v: O.Const) -> Maybe<&1, U32>:
  sy_const(sy_ar(x), dt, v)

# `UOp.cconst(b, dtype)` -- ops.py:646, "a forced CAST for bool: .cast(bool)
# folds, so UOp.const cannot state the width". It is a bare CONST under a CAST
# whose arg is the dtype, and it is the only spelling that can state a bool
# width, which is why `fold_const_where` reaches for it.
def sy_cconst_cast(tv: Maybe<&1, O.Const>, +ar: O.Arena, dt: S.Dt) -> Maybe<&1, U32>:
  match tv:
    case Some{w}: Some{sy_cast(ar, O.Found.i(O.UOp.const(ar, w)), dt)}
    case None{}: None{}

def sy_cconst(+ar: O.Arena, +dt: S.Dt, v: O.Const) -> Maybe<&1, U32>:
  sy_cconst_cast(sy_trunc(dt, v), ar, dt)

# `UOp.ccast(dtype)` -- ops.py:640, `UOp.const(self.val, dtype) if self.op is
# Ops.CONST else self.cast(dtype)`. It dispatches on the op, so it is a ladder,
# and the CONST branch needs the value, which is a `Maybe` the ladder cannot both
# test and use -- so the test is a `Bool` and the value crosses as a parameter.
def sy_ccast.dispatch(is_const: Bool, v: Maybe<&2, O.Const>, ar: O.Arena, u: U32, dt: S.Dt) -> Maybe<&1, U32>:
  match is_const:
    case True{}: sy_cconst(ar, dt, sy_maybe_c2(v))
    case False{}: Some{sy_cast(ar, u, dt)}

def sy_ccast(+x: F.Folded, +u: U32, dt: S.Dt) -> Maybe<&1, U32>:
  sy_ccast.dispatch(sy_is_const(x, u), sy_val(x, u), sy_ar(x), u, dt)

# `x.logical_not()` -- mixin/elementwise.py:50, `self.cast(dtypes.bool).ne(True)`.
# The `.cast(dtypes.bool)` is a no-op on a bool node and is the fold at
# symbolic.py:131-133, so what is left is `CMPNE(x, 1)`. This is the ONE mixin
# line this file writes; see the TODO block for its owner.
def sy_logical_not(+ar: O.Arena, x: U32) -> U32:
  sy_alu2(ar, O.OpsCMPNE{}, x, O.Found.i(O.UOp.const(ar, O.CBool{True{}})))

# `UOp.usum(*us)` / `UOp.uprod(*us)` -- mixin/elementwise.py:40-41, a LEFT fold
# from `self`. The `or_`/`and_` special case for a bool `self` is NOT PORTED;
# every caller in symbolic.py that reaches a bool is a rule this file defers.
def sy_usum.go(t: List<&2, U32>, +ar: O.Arena, base: U32) -> U32:
  match t:
    case Nil{}: base
    case u <> r: sy_usum.go(r, ar, sy_alu2(ar, O.OpsADD{}, base, u))

def sy_usum(+ar: O.Arena, base: U32, us: List<&2, U32>) -> U32:
  sy_usum.go(us, ar, base)

# `UOp.split_uop` -- ops.py:685,
#     if self.op is sep: for s in self.src: yield from s.split_uop(sep)
#     else: yield self
# It is a GENERATOR in Python, so the callers do `list(...)`; here the walk returns
# the list. It is a WORKLIST walk rather than a recursion on `src` because a src
# list read back out of the arena is not a subterm the decrease checker can see.
# The fuel is FIRST for that reason and it is EXACT: every src index is strictly
# less than its consumer's, so the worklist drains.
type SplitSt is Data:
  SplitSt{todo: List<&2, U32>, acc: List<&2, U32>}

def SplitSt.todo(s: SplitSt) -> List<&2, U32>:
  match s:
    case SplitSt{todo, acc}: todo

def SplitSt.acc(s: SplitSt) -> List<&2, U32>:
  match s:
    case SplitSt{todo, acc}: acc

# one step: is `h` itself a `sep`? then its srcs join the worklist, else `h` is
# a term and joins the answer.
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
# is a dict lookup, so an op outside the three is a KeyError; `None{}` is the honest
# total answer and the one caller (`pop_const`) turns it into "do not know".
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
#     (self.src[0], self.src[1].val) if self.op is op and self.src[1].op is
#     Ops.CONST else (self, identity_element(op, self.dtype))
# A Python TUPLE, so a `Data` record here; and the `identity_element` may not
# exist, so the answer is a `Maybe` rather than a pair with a hole in it.
type Popped is Data:
  Popped{t: U32, v: O.Const}

def sy_pop.second.go(m: Maybe<&1, O.Const>) -> Maybe<&1, Popped>:
  match m:
    case Some{v}: Some{Popped{0, v}}
    case None{}: None{}

def sy_pop.second(op: O.Op, dt: S.Dt) -> Maybe<&1, Popped>:
  sy_pop.second.go(sy_ident(op, dt))

# the taken half: `self.src[1].val`, and `val` reads THROUGH a CAST, so the
# popped value is the value of the committed const rather than of a pair.
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

# `exec_alu` -- ops.py:1427, and the answer is two lanes, `U32` and `F32`, with
# tinygrad's own overflow and sign semantics. `if any(isinstance(x, tuple) for x in
# operands)` is the vectorised ALIKE branch and it is DEFERRED (see the TODO block);
# what IS here is the scalar spine:
#     if op in GroupOp.Binary and Invalid in operands: return Invalid
#     alu = python_alu[op](*operands)
#     if truncate_output and (truncate_fxn:=truncate.get(dtype)) is not None:
#       return truncate_fxn(alu)
#     return alu
# `fold_const_alu` calls it with `truncate_output=False`, so the truncate line is
# DEAD on the one path symbolic.py uses. The RESULT dtype is truncated anyway,
# because `DType.const` runs it in `const_like`; the two are separate.

# THE INVALID POISON. ops.py:1432 is
#     if op in GroupOp.Binary and Invalid in operands: return Invalid
# and it is the whole of the Invalid story in `exec_alu`: a BINARY op with an
# Invalid operand is Invalid and nothing else is. A UNARY op over an Invalid is
# not poisoned, which is exactly why the rule at symbolic.py:81 exists.
def sy_is_invalid_c(v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: True{}
    case _ : False{}

# `const_arg` -- symbolic.py:69-70,
#     tuple(const_arg(s) for s in u.src) if u.op is Ops.STACK else u.val
# The STACK is Python's tuple-valued CONST and recursing through it is the
# vectorised branch above, so this walk answers `None{}` for a STACK. The fuel is
# exact for the reason `sy_split`'s is.
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
# polymorphic operand record. `I3` is a U32 BIT PATTERN (whose signedness is the
# dtype's) and `F3` is an F32. The arity RIDES ALONG because
# `python_alu[op](*operands)` raises on a wrong arity.
type I3 is Data:
  I3{n: U32, a: U32, b: U32, c: U32}

def I3.a(+o: I3) -> U32:
  match o:
    case I3{n, a, b, c}: a

type F3 is Data:
  F3{n: U32, a: F32, b: F32, c: F32}

# THE INT LANE. `U32.add/sub/mul` wrap mod 2^32, which IS int32 and uint32 wrap;
# the four divisions are computed from `helpers.bend`'s truncating readings, and
# `H.asr` is the arithmetic shift `operator.rshift` needs and Bend does not have.
def i32_lt(uns: Bool, +x: U32, +y: U32) -> Bool:
  Bool.pick(Bool, uns, U32.is_lt(x, y), Cmp.is_lt(H.i64_cmp(H.i64_of_i32(x), H.i64_of_i32(y))))

def i32_max(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, i32_lt(uns, y, x), y, x)

# `H.floordiv_i32` / `H.floormod_i32` ARE NOT USED because they are WRONG for a
# non-negative dividend with an INEXACT division -- the common case: measured
# `floordiv(7,2) == 4` and `floormod(7,2) == -1` against helpers.py's 3 and 1
# (bend2-constraints, "floor IS NOT AVAILABLE"). `H.cdiv_i32_go` and `H.cmod_i32`
# are CORRECT, so the two are computed here FROM `cdiv` by the definition: with
# `q = cdiv(x,y)` and `r = x - q*y`, `floordiv = q - 1` exactly when `r != 0` and
# `sign(r) != sign(y)`. `fdiv_i` in the gate is the row that shows it.
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
# shifts are both logical, so the sign bits come back in -- `helpers.bend`'s
# `asr`, which clamps the count at 31: past 31 the answer is 4294967295 for a
# negative value and 0 otherwise, exactly what Python's unbounded `>>` gives.
def i32_shr(uns: Bool, +x: U32, +n: U32) -> U32:
  Bool.pick(U32, uns, U32.shrn(x, U32.to_nat(n)), H.asr(x, U32.to_nat(n)))

# `operator.lshift`, and THIS ONE DOES NOT FIT. Python's ints are mathematical,
# so `x << 40` is a 41-bit number and this lane has nowhere to put it. The answer
# is `None{}` rather than a wrapped one, because a wrapped answer is a WRONG
# value and `None{}` is a fold that does not apply.
def i32_shl.big(big: Bool) -> Maybe<&1, U32>:
  match big:
    case True{}: None{}
    case False{}: Some{0}

def i32_shl(+big: Bool, x: U32, n: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, big, i32_shl.big(big), Some{U32.shln(x, U32.to_nat(n))})

# THE ANSWER OF THE INTEGER LANE. `O.Const` and its `CInt` live in `O`, so a
# CONSTRUCTOR of a type from another module is spelled through a def rather than in
# a return position.
def i32_const.of(i: H.I64) -> O.Const: O.CInt{i}

def i32_const(v: U32) -> O.Const: i32_const.of(H.i64_of_i32(v))

# THE ZERO-EXTENSION, and it is the one that matters: `H.i64_of_hi_lo(0, v)` is a
# uint32's value and `H.i64_of_i32(v)` is the same bits read as two's complement,
# so a uint32 with the top bit set is three billion here and minus one otherwise.
def i64_of_c(uns: Bool, +v: U32) -> O.Const:
  Bool.pick(O.Const, uns, i32_const.of(H.i64_of_hi_lo(0, v)), i32_const(v))

# A COMPARISON answers a Python `bool`, and with `truncate_output=False` that
# bool IS the value `exec_alu` hands back -- `const_like` then runs it through
# `DType.const` at the node's dtype, which is `bool` for a comparison. So the
# lane emits `CBool` and the CONST is the comparison, not an int spelled 0/1.
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

def exec_alu_i32.cmp(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsCMPLT{} I3{2, +a, +b, _}: Some{sy_bool_c(i32_lt(uns, a, b))}
    case O.OpsCMPEQ{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}
    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}
    case _ _: None{}

def exec_alu_i32.div(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsFLOORDIV{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_fdiv(uns, a, b))}
    case O.OpsFLOORMOD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_fmod(uns, a, b))}
    case O.OpsCDIV{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_cdiv(uns, a, b))}
    case O.OpsCMOD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_cmod(uns, a, b))}
    case _ _: None{}

def exec_alu_i32.arith(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsADD{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.add(a, b))}
    case O.OpsSUB{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.sub(a, b))}
    case O.OpsMUL{} I3{2, +a, +b, _}: Some{i64_of_c(uns, U32.mul(a, b))}
    case O.OpsMAX{} I3{2, +a, +b, _}: Some{i64_of_c(uns, i32_max(uns, a, b))}
    case O.OpsMULACC{} I3{3, +a, +b, +c}: Some{i64_of_c(uns, U32.add(U32.mul(a, b), c))}
    case _ _: None{}

# `operator.neg` is `U32.sub(0, a)`, which is why NEG is in the integer table at
# all rather than being a float-only entry.
def exec_alu_i32.neg(+uns: Bool, +o: I3) -> Maybe<&1, O.Const>:
  match o:
    case I3{1, +a, _, _}: Some{i64_of_c(uns, H.i32_neg(a))}
    case _: None{}

# `lambda x,y,z: y if x else z`, and `if x` is `bool(x)` on a Python number.
def exec_alu_i32.where(+uns: Bool, +o: I3) -> Maybe<&1, O.Const>:
  match o:
    case I3{3, +a, +b, +c}: Some{i64_of_c(uns, Bool.pick(U32, U32.is_zero(a), c, b))}
    case _: None{}

def op_is_div(op: O.Op) -> Bool:
  O.op_in([O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsCDIV{}, O.OpsCMOD{}], op)

def op_is_bit(op: O.Op) -> Bool:
  O.op_in([O.OpsAND{}, O.OpsOR{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}], op)

# THE INTEGER LADDER, and it is a chain of `Bool.pick` rather than a `match` on
# the op because the groups OVERLAP: SHR is both a bit op and a shift and the
# Python dict has one entry per op, so each `pick` tests ONE op or ONE group and
# the first that holds is the dict lookup.
def exec_alu_i32(+uns: Bool, +op: O.Op, +o: I3) -> Maybe<&1, O.Const>:
  Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsNEG{}), exec_alu_i32.neg(uns, o),
    Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsWHERE{}), exec_alu_i32.where(uns, o),
      Bool.pick(Maybe<&1, O.Const>, O.eq_op(op, O.OpsTRUNC{}), Some{i64_of_c(uns, I3.a(o))},
        Bool.pick(Maybe<&1, O.Const>, O.GroupOp.comparison(op), exec_alu_i32.cmp(uns, op, o),
          Bool.pick(Maybe<&1, O.Const>, op_is_div(op), exec_alu_i32.div(uns, op, o),
            Bool.pick(Maybe<&1, O.Const>, op_is_bit(op), exec_alu_i32.bit(uns, op, o),
              exec_alu_i32.arith(uns, op, o)))))))

# THE FLOAT LANE, over `F32`. F32 arithmetic is a native intrinsic in Bend, so
# add/sub/mul/div/sqrt/exp/log2/sin are the hardware's and the only work here is
# tinygrad's own EDGE CASES.
def f32_inf() -> F32: F32.div(1.0, 0.0)

def f32_nan() -> F32: F32.sub(f32_inf(), f32_inf())

# `1/x if x != 0 else math.copysign(math.inf, x)` IS `F32.div(1.0, x)`: IEEE gives
# 1/+0 = +inf, 1/-0.0 = -inf, and copysign(inf, -0.0) = -inf, so the two
# spellings agree on every input including the signed zero.
def f32_recip(x: F32) -> F32: F32.div(1.0, x)

# `math.log2(x) if x > 0 else -inf if x == 0 else nan`, kept in Python's reading
# order even though `F32.log2(0.0)` is already -inf, so it can be checked against
# ops.py line for line.
def f32_log2(+x: F32) -> F32:
  Bool.pick(F32, F32.is_gt(x, 0.0), F32.log2(x),
    Bool.pick(F32, F32.is_eq(x, 0.0), F32.neg(f32_inf()), f32_nan()))

# `safe_exp2(x) = 2 ** x`, and the `except OverflowError: math.inf` is what
# `F32.pow` already returns.
def f32_exp2(x: F32) -> F32: F32.pow(2.0, x)

# `safe_pow`, and THE DIVERGENCE: Python raises ValueError for a negative base with
# a fractional exponent and returns `inf if x > 0 else -inf`, where IEEE returns
# nan. `F32.pow` is IEEE and this port takes IEEE rather than inventing a
# Python-shaped branch nobody can check.
def f32_pow(x: F32, y: F32) -> F32: F32.pow(x, y)

def f32_sin(+x: F32) -> F32: Bool.pick(F32, H.f32_is_finite(x), F32.sin(x), f32_nan())

# `math.trunc(x) if math.isfinite(x) else x`
def f32_trunc(+x: F32) -> F32: Bool.pick(F32, H.f32_is_finite(x), F32.trunc(x), x)

# `max(a, b)` on Python floats is `a if a > b else b`, and `math.trunc` toward zero
# is what makes a FLOAT floor division, since Python's `//` on floats is `floor`
# and tinygrad's own `floordiv` is `math.floor`.
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
    case O.OpsRECIPROCAL{}: Some{O.CFloat{f32_recip(a)}}
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
    case O.OpsFLOORDIV{}: Some{O.CFloat{f32_fdiv(a, b)}}
    case O.OpsFLOORMOD{}: Some{O.CFloat{f32_fmod(a, b)}}
    case O.OpsCDIV{}: Some{O.CFloat{f32_cdiv(a, b)}}
    case O.OpsCMOD{}: Some{O.CFloat{f32_cmod(a, b)}}
    case O.OpsPOW{}: Some{O.CFloat{f32_pow(a, b)}}
    case _ : exec_alu_f32.cmp(op, a, b)

# `MULACC` is `(x*y)+z` and `WHERE` is `y if x else z`; only WHERE tests its
# first operand as a condition, and `bool(x)` on a float is `x != 0.0`.
def f32_where(cond: Bool, b: F32, c: F32) -> F32: Bool.pick(F32, cond, c, b)

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
# the lane follows the OPERANDS and not the dtype: `1 + 2.5` is a float in Python
# and so it is here. `U32.to_f32` is exact on [0, 2^31) and a negative i64 has no
# exact spelling here, so the one test covers both ends of the range -- and it is
# ALSO the test for "does the INTEGER lane fit", because 2**40 is a legal weakint
# and has no U32.
def i64_big(+i: H.I64) -> Bool:
  Bool.or(H.i64_is_neg(i), Cmp.is_ge(H.i64_cmp(i, H.i64_of_i32(2147483647))))

# THE INVERTED END, AND IT IS THIS ONE. `i64_big` answers "does NOT fit" and
# `exec_alu.of2` reads `ci_fits` as "fits", which is what ops.py:1432's lane choice
# means -- so the CONSUMER is right and the PREDICATE was lying. MEASURED BEFORE
# THIS LINE CHANGED: `exec_alu2(Ops.MUL, int32, [CInt(6), CInt(7)])` answered
# `None{}` where CPython's `exec_alu(Ops.MUL, dtypes.int, [6, 7])` answers `42`,
# so the INTEGER lane was skipped for every value that fits and
# `fold_const_alu` folded `6 * 7` to `CONST(0)` through `sy_maybe_c`'s default --
# a WRONG FOLD, not merely a missing one. Negated HERE and not at the consumer, so
# `cf_of_i.go` keeps asking its own "is there an F32 spelling" question, and the
# two lanes still dead in `executor.bend` are named at `exec_alu.pick`.
def i64_fits_i32(i: H.I64) -> Bool: Bool.not(i64_big(i))

# The U32 BIT PATTERN of a const the INTEGER lane can hold, and whether it can.
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
#     if truncate_output and (truncate_fxn:=truncate.get(dtype)) is not None:
#       return truncate_fxn(alu)
# so it is skipped entirely when the flag is False -- which is how
# `fold_const_alu` calls it -- and `truncate.get` is None for weakint and
# weakfloat, so those skip it too. Both are one `Bool.pick`, and `sy_trunc`
# answers `None{}` for the eight C-effect widths.
def exec_alu.trunc(trunc_it: Bool, dt: S.Dt, m: Maybe<&1, O.Const>) -> Maybe<&1, O.Const>:
  match trunc_it:
    case True{}: sy_trunc(dt, sy_maybe_c(m))
    case False{}: m

# `exec_alu` -- ops.py:1427, the scalar spine in Python's order, one def per
# arity an ALU op can have. They are three defs rather than one taking a list
# because the list is affine and the call site needs its operands in two places:
# the lane test and the lane.
def exec_alu.poison1(op: O.Op, a: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), sy_is_invalid_c(a))

def exec_alu.poison2(op: O.Op, a: O.Const, b: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), Bool.or(sy_is_invalid_c(a), sy_is_invalid_c(b)))

def exec_alu.poison3(op: O.Op, a: O.Const, b: O.Const, c: O.Const) -> Bool:
  Bool.and(O.GroupOp.binary(op), Bool.or(sy_is_invalid_c(a), Bool.or(sy_is_invalid_c(b), sy_is_invalid_c(c))))

# THE THREE FACTS ONE OPERAND CARRIES, as a `Data` record because a `Maybe<F32>` is
# a `Type` and the lane selector needs the operand twice: once for "does the
# INTEGER lane fit it" and once for "can the FLOAT lane read it at all". `opr` is
# pure and cheap, so the two uses RECOMPUTE it rather than binding it -- a `let` is
# affine.
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
# writes it: the Invalid poison, then the INTEGER lane if every operand fits a
# U32, then the FLOAT lane if every operand has an F32 spelling, then `None{}`.
#
# TWO LANES ARE STILL DEAD, BOTH MEASURED, AND NEITHER MOVES A ROW.
#   * `opr_f` reads `Opr.fits`, which is the INTEGER test, so the FLOAT
#     lane needs "every operand fits" where the INTEGER lane has already claimed
#     exactly those, and `exec_alu2(MUL, single, [CFloat(1.5), CFloat(2.0)])`
#     answers `None{}` where CPython answers `3.0`. `Opr.f` cannot carry the
#     guard because `Maybe<&1, F32>` is affine and the value is needed twice.
#   * `i64_fits_i32` is `not i64_big`, and `i64_big` is TRUE for every negative,
#     so `exec_alu2(ADD, int32, [CInt(-7), CInt(2)])` answers `None{}` where
#     CPython answers `-5`, although the lane itself is bit-pattern and `NEG(6)`
#     already produces a negative `CInt`. The two questions -- "is there an F32
#     spelling" and "is it an int32" -- agree on the high end and NOT on the low,
#     so one test cannot answer both. `render.bend`'s `i64_fits_i32` is the
#     second one. Until both are answered, `executor.bend` must keep calling the
#     two lanes directly, which is what its header says it is doing.
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

# ******** phase 1 of symbolic used to live in ops, it's the most generic folding
# rules ********
#
# THE PATTERN VOCABULARY. Each of these is ONE `UPat` test from ops.py, and the
# rules below are written against them so a rule's TEXT is the rule and the
# vocabulary is the pattern. The first six are the `invalid_*` patterns
# symbolic.py:63-68 spells out. Invalid poisons the value: ops move inside the gate
# so the Invalid reaches the LOAD/STORE and folds there, and this needs to be before
# symbolic so that `0*something_that_might_be_invalid` doesnt become 0.
def p_invalid(+x: F.Folded, +u: U32) -> Bool: Bool.and(sy_is_op(x, u, O.OpsCONST{}), sy_is_invalid(x, u))

# `invalid_gate` -- `UPat.var("cond").where(UPat.var("x"), invalid_pat)`, which is
# `WHERE(cond, x, CONST(Invalid))` and three srcs.
def p_gate(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), sy_is_invalid(x, sy_src2(x, u)))

# `p_where_gate` is `invalid_gate` in a src SLOT rather than a node of its own,
# and it is the test every gate rule below reads.
def p_where_gate(+x: F.Folded, u: U32, n: U32) -> Bool: p_gate(x, sy_src(x, u, n))

def all_const.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_const.go(t, x, Bool.and(acc, sy_is_op(x, s, O.OpsCONST{})))

def all_const(+x: F.Folded, srcs: List<&2, U32>) -> Bool: all_const.go(srcs, x, True{})

# the two const spellings: Invalid carries no width, so it rides bare inside either.
# `bare_const` -- `UPat.any(UPat(Ops.CONST), UPat(Ops.STACK, src=UPat(Ops.CONST)))`:
# a CONST, or a STACK every src of which is a CONST.
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
# UPat(Ops.STACK, src=UPat.any(p, UPat(Ops.CONST, arg=Invalid))))`. THE NAME `c`
# IS BOUND TWICE HERE AND IT IS SAFE: the two bindings are `is_any` ALTERNATIVES,
# and ADDING an identity check would be a BUG -- it would turn a disjunction into a
# conjunction and drop the bare `CONST(Invalid)` lane.
def p_casted_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(is_cast_const(x, u), Bool.and(sy_is_op(x, u, O.OpsSTACK{}), all_cast_or_bad(x, sy_srcs(x, u))))

def p_all_casted.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: p_all_casted.go(t, x, Bool.and(acc, p_casted_const(x, s)))

def p_all_casted(+x: F.Folded, u: U32) -> Bool: p_all_casted.go(sy_srcs(x, u), x, True{})

# `x == y` ON ARENA INDICES, which is `UOp.__eq__` because `UOp.__eq__` IS
# identity. This is the rebind check and it is LOAD-BEARING (header).
def p_same(a: U32, b: U32) -> Bool: U32.is_eq(a, b)

# THE SRC THAT IS NOT THE CONST, which is what every self-folding rule returns.
# Python gets it from the PERMUTATION (`src=[x, UPat.const(0)]` becomes two
# alternatives) and this port gets it from the index.
def p_nconst(+x: F.Folded, u: U32) -> U32:
  Bool.pick(U32, sy_is_op(x, sy_src0(x, u), O.OpsCONST{}), 1, 0)

def p_nc(+x: F.Folded, +u: U32) -> U32: sy_src(x, u, p_nconst(x, u))

# THE DTYPE CLASS TESTS. `dtypes.ints` is four concrete widths, so
# `dtypes.ints + (dtypes.bool, dtypes.weakint)` is SIX of them.
def dt_intish(+d: S.Dt) -> Bool:
  Bool.or(Bool.or(O.eq_dt(d, S.boolean()), O.eq_dt(d, S.weakint())),
    Bool.or(Bool.or(O.eq_dt(d, S.int8()), O.eq_dt(d, S.int16())), Bool.or(O.eq_dt(d, S.int32()), O.eq_dt(d, S.int64()))))

def p_intish(x: F.Folded, u: U32) -> Bool: dt_intish(sy_dt1(x, u))

# `dtypes.ints + (dtypes.weakint,)` -- symbolic.py:135 and :307, FIVE of them.
def dt_intweak(+d: S.Dt) -> Bool:
  Bool.or(O.eq_dt(d, S.weakint()),
    Bool.or(Bool.or(O.eq_dt(d, S.int8()), O.eq_dt(d, S.int16())), Bool.or(O.eq_dt(d, S.int32()), O.eq_dt(d, S.int64()))))

def p_intweak(x: F.Folded, u: U32) -> Bool: dt_intweak(sy_dt1(x, u))

def p_bool(x: F.Folded, u: U32) -> Bool: sy_dt_is(x, u, S.boolean())

def p_weakint(x: F.Folded, u: U32) -> Bool: sy_dt_is(x, u, S.weakint())

# `dtypes.weaks` is `(weakint, weakfloat)`, and it is `S.Cls`'s two weak members
# -- the same spelling `spec.bend` uses for the same Python line.
def dt_weak(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_weak_of(d: S.Dt) -> Bool: dt_weak(S.Dt.cls(d))

def p_weak(x: F.Folded, u: U32) -> Bool: dt_weak_of(sy_dt1(x, u))

# `UPat.const(0)` is `UPat(Ops.CONST, arg=0)` and `UPat.const(True, dtypes.bool)`
# is the same with `True`, so "is this src the const 0" is ONE test.
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

# `c.val` as an I64, for the three rules that need the NUMBER rather than a
# truth value. Python's `c.val` is a PyConst; on the `CInt` lane it is an I64.
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

# A CONST at a dtype, value already in range. `sy_const_put` rather than
# `sy_const` because the TRUNCATE is the C-effect wall and every value this file
# builds itself is in range by construction.
def sp_const(dt: S.Dt, i: H.I64, +ar: O.Arena) -> U32: sy_const_put(dt, O.CInt{i}, ar)

def sp_const_i(dt: S.Dt, i: H.I64, +ar: O.Arena) -> U32: sp_const(dt, i, ar)

# `const_like(False, dtypes.bool)` and `const_like(0)`, which the zero-folding
# rules return. The first is a BOOL in Python and `DType.const` on a bool dtype is
# `bool(val)`, so it is `CBool`.
def sp_false(+dt: S.Dt, +ar: O.Arena) -> U32:
  sy_const_cast(Bool.not(O.eq_dt(dt, S.boolean())), ar, dt, O.Found.i(O.UOp.const(ar, O.CBool{False{}})))

# `simplify_pow` -- symbolic.py:16-21. TWO of its FIVE arms are ported; the other
# three are arithmetic, not structure, and the reason is that `c.val-0.5` is a
# PYTHON FLOAT and `int(h)` has no exact spelling here (`helpers.bend` has no
# `I64 -> F32` and no `F32 -> I64`), and the halving then needs `i64_div`.
def sp_neg_pow(+x: F.Folded, +u: U32, i: H.I64) -> U32:
  sy_alu2(sy_ar(x), O.OpsPOW{}, sy_alu1(sy_ar(x), O.OpsRECIPROCAL{}, u),
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
#     if c.dtype.itemsize != root.dtype.itemsize: return None
#     return root.const_like(bitcast(truncate[c.dtype](c.val), c.dtype, root.dtype))
# Upstream's comment above it is the reason the truncate is THERE: "the value is
# mathematical and may not fit: reading it as bits is the emission that pins it to
# the stated width". `bitcast` (dtype.py:299) is a `struct.pack`/`unpack` round
# trip, so for the dtypes this port can state it is the IDENTITY; a pair of
# DIFFERENT dtypes of equal itemsize needs the `struct` and answers `None{}`.
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
#     a.const_like(exec_alu(a.op, a.dtype, [const_arg(s) for s in a.src], False))
# `truncate_output=False`, and upstream's comment above it is the reason: "no
# truncate: ints stay mathematical past the fold (emission truncates); floats
# re-round in the mint". The `nsrc` dispatch is the arity split `exec_alu` needs.
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
# THE RULES. A RULE'S CAPTURES ARE `src[k]` OF THE NODE IT MATCHED -- Python's
# compiled form passes them as arguments and this port reads them by index,
# because the arena is the only shared value and a closure cannot take one. The
# captures are the same nodes either way, so the rule body still reads as the
# lambda. EACH RULE IS TWO DEFS, and the split is load-bearing (header).

# `INDEX(_, CONST(Invalid))`, and its `or_casted()` alternative
# `UPat(Ops.CAST, src=(UPat(Ops.INDEX, ...)))`. `or_casted` is a DISJUNCTION --
# `UPat.any(self, UPat(Ops.CAST, name=name, src=(self,)))` -- and it copies the
# store per alternative, so the two never meet.
def p_index_bad(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsINDEX{}), sy_nsrc_ge(x, u, 2)), p_invalid(x, sy_src1(x, u)))

def p_index_bad_or_cast(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(p_index_bad(x, u), Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)), p_index_bad(x, sy_src0(x, u))))

# symbolic.py:80  (invalid_pat.broadcast(), lambda i: i)
# A STACK whose FIRST src is the Invalid CONST folds to that CONST. `broadcast`
# is `UPat(Ops.STACK, src=self)` -- an `itertools.repeat`, so the arity is at
# least one and not exactly one.
def sym_0.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTACK{}), sy_nsrc_ge(x, u, 1)), p_invalid(x, sy_src0(x, u)))

def sym_0(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_0.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:81  (UPat(GroupOp.Unary|{CAST, BITCAST}, src=(invalid_pat,)), lambda i: i)
def sym_1.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_CASTS()), sy_nsrc_is(x, u, 1)), p_invalid(x, sy_src0(x, u)))

def sym_1(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_1.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:90  (invalid_pat.where(UPat(), UPat()), lambda i: i)
# `WHERE(cond, x, CONST(Invalid))` with an Invalid CONDITION: an Invalid condition
# poisons the whole where, so the answer is the Invalid itself.
def sym_2.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_invalid(x, sy_src0(x, u)))

def sym_2(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_2.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:91  (invalid_gate.where(UPat.var("a"), UPat.var("b")),
#                   lambda cond,x,i,a,b: cond.where(x.where(a,b), i))
# The gate moves INSIDE: `WHERE(WHERE(c,x,i), a, b)` -> `WHERE(c, WHERE(x,a,b), i)`.
def sym_3.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_where_gate(x, u, 0))

def sym_3.gate(x: F.Folded, u: U32) -> U32: sy_src0(x, u)

def sym_3.gx(x: F.Folded, u: U32) -> U32: sy_src1(x, u)

def sym_3.gi(x: F.Folded, u: U32) -> U32: sy_src2(x, u)

def sym_3.pick(cond: Bool, t: U32, f: U32) -> U32: Bool.pick(U32, cond, t, f)

def sym_3.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_where(sy_ar(x), sy_src0(x, sym_3.gate(x, u)),
    sy_where(sy_ar(x), sym_3.gx(x, u), sy_src1(x, u), sy_src2(x, u)), sym_3.gi(x, u))})

def sym_3(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_3.hit(sym_3.pat(x, u), x, u)

# symbolic.py:99  (UPat(Ops.STORE, src=(UPat(Ops.INDEX, src=(UPat(), invalid_pat),
#                       allow_any_len=True).or_casted(), UPat())), lambda i: UOp(Ops.NOOP))
def sym_4.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)), p_index_bad_or_cast(x, sy_src0(x, u)))

def sym_4.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_noop(sy_ar(x))})

def sym_4(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_4.hit(sym_4.pat(x, u), x, u)

# symbolic.py:100-101  (UPat(Ops.LOAD, src=(UPat(Ops.INDEX, ...).or_casted(),),
#                          allow_any_len=True, name="x"),
#                       lambda x,i: x.src[1] if len(x.src) > 1 else x.const_like(0))
def sym_5.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsLOAD{}), sy_nsrc_ge(x, u, 1)), p_index_bad_or_cast(x, sy_src0(x, u)))

def sym_5.zero(x: F.Folded, u: U32) -> Maybe<&1, U32>:
  sy_const_like(x, u, O.CInt{H.i64_of_i32(0)})

def sym_5.one(x: F.Folded, u: U32) -> Bool: U32.is_eq(sy_nsrc(x, u), 1)

def sym_5.arm(one: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, one, sym_5.zero(x, u), Some{sy_src1(x, u)})

def sym_5.hit(hit: Bool, one: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, sym_5.arm(one, x, u))

def sym_5(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sym_5.hit(sym_5.pat(x, u), sym_5.one(x, u), x, u)

# symbolic.py:117  (UPat({ADD, XOR, OR}, src=[UPat.var("x"), UPat.const(0)]),
#                     lambda x: x)   # x+0 / x^0 / x|0 -> x
# THE LIST `src` IS A PERMUTATION in Python (ops.py:1464), so the rule fires with
# the const on either side; `p_nc` is the index of the src that is not the CONST.
def sym_6.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_SELF()), sy_nsrc_is(x, u, 2)),
    Bool.or(p_is_const_0(x, sy_src0(x, u)), p_is_const_0(x, sy_src1(x, u))))

# `c0` says src[0] is the CONST, so the answer is src[1]; the two spellings of
# `Bool.pick` and this call site are the whole of the PERMUTATION Python gets
# from `src=[...]`.
def sym_6.pick(c0: Bool, a: U32, b: U32) -> Maybe<&1, U32>: Some{Bool.pick(U32, c0, a, b)}

def sym_6(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_6.pat(x, u), sym_6.pick(p_is_const_0(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u)))

# symbolic.py:120  (UPat.var("x") // UPat.var("x"), lambda x: x.const_like(1))
# x//x -> 1. **`x` IS BOUND TWICE IN ONE SRC TUPLE**, so this rule carries the
# IDENTITY CHECK and it is LOAD-BEARING: without it the rule also fires on
# `x // y` for two different nodes, and that is a wrong rewrite.
def sym_7.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_7.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, sy_const_like(x, u, O.CInt{H.i64_of_i32(1)}))

def sym_7(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_7.hit(sym_7.pat(x, u), x, u)

# symbolic.py:123  ((UPat.var("x") ^ UPat.var("y")) ^ UPat.var("y"), lambda x,y: x)
# (x^y)^y -> x. **`y` IS BOUND TWICE WITHIN ONE SRC SPINE**, and the outer `^`'s
# src[1] and the inner `^`'s src[1] must be the SAME node -- so this is the
# LOAD-BEARING rebind of the header, and `p_same` IS the identity check
# `upat.py:100-105` emits. Split in two defs only to keep the arms flat.
def sym_8.inner(outer: Bool, +x: F.Folded, +u: U32) -> Bool:
  Bool.and(outer, Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsXOR{}),
    Bool.and(sy_nsrc_is(x, sy_src0(x, u), 2), p_same(sy_src1(x, u), sy_src1(x, sy_src0(x, u))))))

def sym_8.pat(+x: F.Folded, +u: U32) -> Bool:
  sym_8.inner(Bool.and(sy_is_op(x, u, O.OpsXOR{}), sy_nsrc_is(x, u, 2)), x, u)

def sym_8(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_8.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})

def p_all_bare.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: p_all_bare.go(t, x, Bool.and(acc, p_bare_const(x, s)))

def p_all_bare(+x: F.Folded, u: U32) -> Bool: p_all_bare.go(sy_srcs(x, u), x, True{})

# symbolic.py:158  (UPat(GroupOp.ALU-{THREEFRY}, src=bare_const, name="a"),
#                     fold_const_alu)
# "one rule per spelling: bare has no width, a pair evaluates at its stated
# width". `src=bare_const` is an `itertools.repeat`, so EVERY src is a bare const.
def sym_9.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(O.GroupOp.alu(sy_op(x, u)), Bool.not(O.eq_op(sy_op(x, u), O.OpsTHREEFRY{}))),
    p_all_bare(x, u))

def sym_9.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, fold_const_alu.at(x, u))

def sym_9(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_9.hit(sym_9.pat(x, u), x, u)

# symbolic.py:463  ((UPat.var("x") * UPat.var("x")).reciprocal(),
#                     lambda x: x.reciprocal()*x.reciprocal())   # 1/(x*x) -> (1/x)*(1/x)
# `**` IS NOT REBIND HERE: `UPat.var("x") * UPat.var("x")` is `UPat.__mul__`, a
# DIFFERENT var per operand -- Python's UPat cache interns by NAME, so the two are
# the same pattern object and the compiled form's STORE OVERWRITES. `upat.py:
# 100-105` emits the identity compare for a duplicate store, so the honest port is
# the IDENTITY CHECK again; it is STRICTER than Python here (see the TODO block).
def sym_10.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsRECIPROCAL{}), sy_nsrc_is(x, u, 1)),
    Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsMUL{}), Bool.and(sy_nsrc_is(x, sy_src0(x, u), 2),
      p_same(sy_src0(x, sy_src0(x, u)), sy_src1(x, sy_src0(x, u))))))

def sym_10.r1(+x: F.Folded, u: U32) -> U32:
  sy_alu1(sy_ar(x), O.OpsRECIPROCAL{}, sy_src0(x, sy_src0(x, u)))

def sym_10.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_alu2(sy_ar(x), O.OpsMUL{}, sym_10.r1(x, u), sym_10.r1(x, u))})

def sym_10(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_10.hit(sym_10.pat(x, u), x, u)

# symbolic.py:444  (UPat(Ops.GROUP, src=(UPat.var("x"),)), lambda x: x)
def sym_11.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsGROUP{}), sy_nsrc_is(x, u, 1))

def sym_11(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_11.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:442-448 -- `# this is symbolic 2.0` -- the GROUP/SINK cleanup pair.
# symbolic.py:445-447  (UPat((Ops.SINK, Ops.GROUP), name="root"),
#   lambda root: UOp(root.op, src=tuple(flatten(x.src if x.op in
#     REMOVE_FROM_SINK_LIKE else (x,) for x in root.src)), arg=root.arg)
# `REMOVE_FROM_SINK_LIKE = {NOOP, STACK, SINK, GROUP}`, and `flatten` is a fold
# over a list of lists -- which `helpers.bend`'s `flatten_u32` is.
def p_sink_like(x: F.Folded, s: U32) -> Bool:
  sy_op_in(x, s, [O.OpsNOOP{}, O.OpsSTACK{}, O.OpsSINK{}, O.OpsGROUP{}])

def sink_srcs.of(+x: F.Folded, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, p_sink_like(x, s), sy_srcs(x, s), [s])

# `x.src if x.op in REMOVE_FROM_SINK_LIKE else (x,)` -- the LISTS stay unflattened
# here and `List.concat` does the flatten at the end, which is `helpers.py`'s
# `flatten` and `H.flatten_u32` and is ONE call rather than a fold per step.
def any_sink_like(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_sink_like(t, x, Bool.or(acc, p_sink_like(x, s)))

def sink_srcs.go(srcs: List<&2, U32>, +x: F.Folded, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match srcs:
    case Nil{}: acc
    case s <> t: sink_srcs.go(t, x, List.append(&2, List<&2, U32>, acc, [sink_srcs.of(x, s)]))

def sym_12.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_op_in(x, u, [O.OpsSINK{}, O.OpsGROUP{}]), any_sink_like(sy_srcs(x, u), x, False{}))

def sym_12.put(srcs: List<&2, U32>, +ar: O.Arena, +u: U32) -> U32:
  O.Found.i(O.UOp.new(ar, O.Arena.op(ar, u), srcs, O.Arena.arg(ar, u), O.Arena.tag(ar, u)))

def sym_12.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sym_12.put(H.flatten_u32(sink_srcs.go(sy_srcs(x, u), x, Nil{})), sy_ar(x), u)})

def sym_12(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_12.hit(sym_12.pat(x, u), x, u)# THE REWRITER. `PatternMatcher.rewrite` -- ops.py:1603-1610:
#     if len(pats:=self.pdict.get(uop.op, [])):
#       if (ler:=...) is None: ler = {u.op for u in uop.src}
#       for _,match,early_reject in pats:
#         if not early_reject.issubset(ler): continue
#         if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret
#     return None
# FOUR THINGS, and all four are load-bearing: the op-set scan (`pm_claimed`),
# `early_reject` as a NECESSARY CONDITION rather than a veto, the FIRST-WINS fold
# (`sy_keep.go` keys on the ACCUMULATOR, because `rewrite` RETURNS on the first
# non-None rather than folding), and `ret is not uop` (`sy_novel`).
#
# `spec.bend` writes this five more times than this file does because a dispatch
# is a `match` over a dynamic tag and a closure cannot take the arena: TWO tables,
# TWO dispatches, and the ~15 lines of driver below duplicated.
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

def sym_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0,  [O.OpsSTACK{}],                            OP_INVALID()},   # 80
    O.PMEntry{1,  OP_CASTS(),                                OP_INVALID()},   # 81
    O.PMEntry{2,  [O.OpsWHERE{}],                            OP_INVALID()},   # 90
    O.PMEntry{3,  [O.OpsWHERE{}],                            OP_INVALID()},   # 91
    O.PMEntry{4,  [O.OpsSTORE{}],                            OP_INVALID()},   # 99
    O.PMEntry{5,  [O.OpsLOAD{}],                             OP_INVALID()},   # 100
    O.PMEntry{6,  OP_SELF(),                                 Nil{}},           # 117
    O.PMEntry{7,  [O.OpsFLOORDIV{}],                         Nil{}},           # 120
    O.PMEntry{8,  [O.OpsXOR{}],                              Nil{}},           # 123
    O.PMEntry{9,  [O.OpsPOW{}],                              Nil{}},           # 158
    O.PMEntry{10, [O.OpsRECIPROCAL{}],                       Nil{}},           # 463
    O.PMEntry{11, [O.OpsGROUP{}],                            Nil{}},           # 444
    O.PMEntry{12, [O.OpsSINK{}, O.OpsGROUP{}],               Nil{}}]}          # 445

# `pm_remove_invalid` is a SEPARATE MATCHER in Python -- `codegen/__init__.py:367`
# uses it ALONE and it is never composed into `sym` -- so it gets its own tag space
# and its own dispatch. Sharing `sym`'s would let `symbolic.py:91` steal the node
# and make `pm_remove_invalid` dead.
def rm_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsWHERE{}], OP_INVALID()},                            # 105
    O.PMEntry{1, [O.OpsSTACK{}], Nil{}}]}                                 # 106

def rm_table_len() -> Nat: Nat.double(Nat.add(Nat.add(0n, 0n), 0n))

def sym_table_len() -> Nat:
  Nat.add(Nat.add(Nat.add(Nat.add(0n, 0n), 0n), Nat.add(Nat.add(0n, 0n), 0n)),
    Nat.add(Nat.add(Nat.add(Nat.add(0n, 0n), 0n), Nat.add(Nat.add(0n, 0n), 0n)), 0n))

# THE DRIVER, twice. `sym_*` for the `sym` composition and `rm_*` for
# `pm_remove_invalid`, and the duplication is the honest cost of not having
# first-class functions: see the header.
def sym_dispatch.go(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match tag:
    case 0: sym_0(x, u)
    case 1: sym_1(x, u)
    case 2: sym_2(x, u)
    case 3: sym_3(x, u)
    case 4: sym_4(x, u)
    case 5: sym_5(x, u)
    case 6: sym_6(x, u)
    case 7: sym_7(x, u)
    case 8: sym_8(x, u)
    case 9: sym_9(x, u)
    case 10: sym_10(x, u)
    case 11: sym_11(x, u)
    case 12: sym_12(x, u)
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

# `pm_remove_invalid` -- symbolic.py:104-108, and BOTH rules are ported.
# symbolic.py:105  (invalid_gate.named("w"),
#                     lambda cond,x,i,w: w.replace(src=(cond,x,w.const_like(0))))
def rm_0.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_invalid(x, sy_src2(x, u)))

# `Maybe` is a `Type`, so it is read ONCE: the two facts `w.const_like(0)` needs --
# is there one, and what is it -- cross the boundary as a `Bool` and a `U32`.
def rm_0.ok(hit: Bool, ok: Bool, +x: F.Folded, +u: U32, z: U32) -> Maybe<&1, U32>:
  Bool.pick(Maybe<&1, U32>, Bool.and(hit, ok),
    Some{sy_replace_src(sy_ar(x), u, [sy_src0(x, u), sy_src1(x, u), z])}, None{})

def rm_0.of(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match z:
    case Some{v}: rm_0.ok(hit, True{}, x, u, v)
    case _: rm_0.ok(hit, False{}, x, u, 0)

def rm_0.put(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_0.of(hit, z, x, u)

def rm_0(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  rm_0.put(rm_0.pat(x, u), sy_const_like(x, u, O.CInt{H.i64_of_i32(0)}), x, u)

# symbolic.py:106-107  (UPat(Ops.STACK, name="s"),
#   lambda s: s.replace(src=tuple(UOp.const(0, s.dtype) if x.is_invalid else x
#                                 for x in s.src)) if any(x.is_invalid for x in s.src) else None)
def any_invalid.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: any_invalid.go(t, x, Bool.or(acc, p_invalid(x, s)))

def rm_1.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTACK{}), sy_nsrc_ge(x, u, 1)), any_invalid.go(sy_srcs(x, u), x, False{}))

def rm_1.of(+x: F.Folded, +s: U32, dt: S.Dt, +ar: O.Arena) -> U32:
  Bool.pick(U32, p_invalid(x, s), sp_const(dt, H.i64_of_i32(0), ar), s)

def rm_1.go(srcs: List<&2, U32>, +x: F.Folded, +dt: S.Dt, +ar: O.Arena) -> List<&2, U32>:
  match srcs:
    case Nil{}: Nil{}
    case s <> t: List.append(&2, U32, rm_1.go(t, x, dt, ar), [rm_1.of(x, s, dt, ar)])

def rm_1.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_replace_src(sy_ar(x), u, rm_1.go(sy_srcs(x, u), x, sy_dt1(x, u), sy_ar(x)))})

def rm_1(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: rm_1.hit(rm_1.pat(x, u), x, u)

# THE SECOND DRIVER. `pm_remove_invalid` is a separate matcher in Python, so it is a
# separate table with its own tag space and its own dispatch -- the honest cost of
# not having first-class functions. Sharing `sym`'s driver would be a BUG rather
# than a saving: it would let `symbolic.py:91` claim the node and make
# `pm_remove_invalid` dead.
def rm_dispatch.go(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match tag:
    case 0: rm_0(x, u)
    case 1: rm_1(x, u)
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
# returns a `Found`, because `Arena` is affine. A builder that returned only the
# INDEX throws the grown arena away, and the fixture becomes a graph whose last
# node is not in the store -- which prints, typechecks, and answers every rule
# `None{}`.
def f_new(+ar: O.Arena, op: O.Op, srcs: List<&2, U32>, a: O.Arg) -> O.Found:
  O.UOp.new(ar, op, srcs, a, O.TNone{})

def f_cast(+f: O.Found, dt: S.Dt) -> O.Found:
  f_new(O.Found.ar(f), O.OpsCAST{}, [O.Found.i(f)], O.ADt{dt})

def f_alu2(+f: O.Found, op: O.Op, b: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [O.Found.i(f), b])

def f_i(f: O.Found) -> U32: O.Found.i(f)

def f_where(+ar: O.Arena, a: U32, b: U32, c: U32) -> O.Found:
  O.UOp.new(ar, O.OpsWHERE{}, [a, b, c], O.ANone{}, O.TNone{})

# `x + 0` with `x = CONST(7)`: 0 is `CONST(7)`, 1 is `CONST(0)`, 2 is the ADD.
def fx_add0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  f_alu2(b, O.OpsADD{}, f_i(a))

# `x // x` with `x = CONST(7)`: 0 is `CONST(7)`, 1 is the FLOORDIV. The two srcs
# are the SAME node, which is the rebind the rule checks for.
def fx_samediv() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  f_alu2(a, O.OpsFLOORDIV{}, f_i(a))

# `x // y` for TWO DIFFERENT consts: 0 is `CONST(7)`, 1 is `CONST(2)`, 2 is the
# FLOORDIV. The SAME rule, and it must NOT fire.
def fx_diffdiv() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  f_alu2(b, O.OpsFLOORDIV{}, f_i(a))

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
# tag 0 both claim. 0 is `CONST(True)`, 1 is `CONST(7)`, 2 is the Invalid CONST,
# 3 is the WHERE.
def fx_where() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = O.UOp.const(O.Found.ar(b), O.CInvalid{})
  f_where(O.Found.ar(c), f_i(a), f_i(b), f_i(c))

# `STORE(INDEX(b, CONST(Invalid)), v)`: 0 is `CONST(2)`, 1 is the Invalid CONST,
# 2 is the INDEX, 3 is `CONST(9)`, 4 is the STORE, and tag 4 answers a NOOP at 5.
def fx_store() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})
  +b = O.UOp.const(O.Found.ar(a), O.CInvalid{})
  +c = f_alu2(b, O.OpsINDEX{}, f_i(a))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(9)})
  f_alu2(d, O.OpsSTORE{}, f_i(c))

# `ADD(CONST(5), CONST(6))`: 0 and 1 are the CONSTs and 2 is the ADD, so
# `fold_const_alu` has a CLOSED tree to evaluate -- which is the whole of
# `symbolic.py:158`'s claim.
def fx_alu() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(6)})
  f_alu2(b, O.OpsADD{}, f_i(a))

# `STACK(CONST(7), CONST(Invalid))`: 0 is `CONST(7)`, 1 is the Invalid CONST, 2 is
# the STACK, and `pm_remove_invalid` answers 3 -- a STACK over `[0, <CONST(0)>]`
# with the `CONST(7)` untouched.
def fx_stack() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInvalid{})
  f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})

# `GROUP(CONST(7))`: 0 is `CONST(7)`, 1 is the GROUP, and tag 11 answers 0.
def fx_group() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  f_new(O.Found.ar(a), O.OpsGROUP{}, [f_i(a)], O.ANone{})

# `GROUP(STACK(CONST(7), CONST(2)))`: 0 is `CONST(7)`, 1 is `CONST(2)`, 2 is the
# STACK, 3 is the GROUP, and tag 12 answers a GROUP over `[0, 1]` at index 4 --
# because a STACK is one of REMOVE_FROM_SINK_LIKE and is flattened away.
def fx_sink() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(3)})
  f_new(O.Found.ar(d), O.OpsGROUP{}, [f_i(c), f_i(d)], O.ANone{})

# `ADD(CONST(1), CONST(2**31))` at int32: the top ADD WRAPS to -2147483647.
def fx_i32() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_hi_lo(1, 0)})
  +c = f_alu2(b, O.OpsADD{}, f_i(a))
  f_cast(c, S.int32())

# `GROUP(SINK(CONST(7)))`: 1 is `CONST(7)`, 2 is the SINK, 3 is the GROUP, and tags
# 11 AND 12 both claim node 3 and they DISAGREE -- tag 11 answers the SINK and tag
# 12 answers a fresh GROUP over `[1]`. The two answers MUST differ: a fixture where
# both rules agree cannot tell first-wins from a conjunction.
def fx_two() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = f_new(O.Found.ar(a), O.OpsSINK{}, [f_i(a)], O.ANone{})
  f_new(O.Found.ar(b), O.OpsGROUP{}, [f_i(b)], O.ANone{})

def fx_of(f: O.Found) -> F.Folded: F.folded(O.Found.ar(f))
# THE GATE. `main` builds the fixtures above, folds each with `fold.bend`, runs the
# table over one node, and prints one row per claim.
#
#   lay=3        the node count of `fx_add0`, so every index the claims use is
#                CHECKABLE rather than assumed: 0 is `CONST(7)`, 1 is `CONST(0)`
#                and 2 is the `ADD`. It is also the row that would have caught the
#                fixture bug in this section's header: an arena that read `next=1`
#                for a graph of two nodes.
#   len_sym=13   the `sym` composition holds 13 entries. A COUNT, so a MISSING
#                rule shows, and deliberately NOT Python's 127: `total_sym` is
#                what Python's own blocks imply and `skip` is the gap.
#   total_sym=127  14 (`pm_data_invalid`) + 47 (`symbolic_simple`, :117-198) + 1
#                (`commutative`) + 47 (`symbolic`, :236-323) + 2
#                (`pm_simplify_valid`) + 14 (`sym`'s, :452-475) + 2
#                (`pm_clean_up_group_sink`).
#   skip=114     `total_sym - len_sym`, so `len_sym + skip == total_sym` and the
#                arithmetic of the port is checkable without reading a rule body.
#   len_rm=2     `pm_remove_invalid` is 2 of 2.
#   rej=6        the entries whose `early_reject` set is NON-EMPTY (tags 0..5). A
#                COUNT because a MISSPELLED reject set is SILENT: it turns a
#                necessary condition into a false one and the rule then skips a
#                node it should accept.
#   alu_rule=1    `fold_const_alu` at a CLOSED ALU tree -- `5 + 6` -- produces a
#                rewrite. It is a `Maybe<&1, U32>`, which is an INDEX into an
#                arena the caller cannot see, so this row can only ask WHETHER
#                and not WHAT; `alu` is the value read back.
#   alu_i32=1    `fx_i32`'s node 4, and `fx_i32` BUILDS its nodes -- it calls no
#                `sym`, no `fold_const_alu` and so no `exec_alu`. The row
#                therefore CANNOT move with the lane selector and did not; what
#                it pins is `const_like`'s concrete-dtype spelling, the
#                CAST-on-top pair `UOp.const`'s own header defers.
#   alu=1        `exec_alu(ADD, weakint, [5,6])` is 11, and CPython's
#                `exec_alu(Ops.ADD, dtypes.weakint, [5, 6])` is 11. It was `0`
#                and labelled RED-and-undiagnosed; it was the inverted
#                `i64_fits_i32` (see its own comment) and M12 moves it.
#   fdiv_i=1     `7 // 2` is 3 on the INTEGER lane -- computed HERE from
#                `H.cdiv_i32_go`, because `H.floordiv_i32` is wrong for a
#                non-negative dividend. See the comment at `i32_fdiv`.
#   cdiv_i=1     `cdiv(7,2)` is 3, and it comes straight out of `helpers.bend`.
#   alu_big=1    `exec_alu(ADD, weakint, [2**40, 1])` does NOT answer. THE WALL.
#                `None{}` is a fold that does not apply and the row says so
#                instead of printing a wrapped 1.
#   alu_f32=1    the FLOAT lane: `1.5 + 2.0` is 3.5. The two lanes cannot both
#                pass by accident, because `alu_big` is on the integer one.
#   fdiv=1       `7.0 // 2.0` is 3.0 on the float lane, which is Python's
#                `math.floor`-shaped floordiv and NOT `math.trunc`-shaped. This
#                row pins `f32_fdiv`'s choice of `F32.floor` over `F32.trunc`.
#   fdiv_i=1     `7 // 2` is 3 on the INTEGER lane.
#   cdiv_i=3     `cdiv(7,2)` is 3 and `cdiv(-7,2)` is -3; `U32.div(7,2)` is also
#                3, so the NEGATIVE half is what distinguishes the lanes and
#                `cdiv_i_neg` is that row.
#   inval=1      tag 1: `CAST(bool, CONST(Invalid))` folds to the Invalid CONST.
#   inval_st=1   tag 4: `STORE(INDEX(b, CONST(Invalid)), v)` -> NOOP.
#   inval_n=1    tag 3: `CAST(bool, WHERE(c,x,Invalid))` -> the CAST is DROPPED,
#                which is `symbolic.py:82`'s `op.replace(src=(x,))`.
#   selfadd=1    tag 6: `x + 0 -> x`. This is also the row that pins `sy_novel`:
#                the answer IS the node, and without `ret is not uop` it would not
#                be an answer at all.
#   rebind=1     tag 7: `x // x -> 1` with the two srcs the SAME node.
#   rebind0=0    the SAME rule on `x // y` for two DIFFERENT nodes. ONLY THE PAIR
#                CAN SEE THE REBIND CHECK: with `U32.is_eq` dropped, `rebind`
#                still holds and `rebind0` moves to 1. That is the row the brief
#                asks for and it is the reason `rebind` alone is worthless.
#   group=1      tag 11: `GROUP(x) -> x`.
#   sink=1       tag 12: `GROUP(STACK(a,b))` -> `GROUP(a,b)` -- the flatten, which
#                is the only rule here that rebuilds a src LIST.
#   rm_where=1   `pm_remove_invalid` tag 0: the Invalid false branch becomes a
#                `const_like(0)` and the op is unchanged.
#   rm_stack=1   `pm_remove_invalid` tag 1: an Invalid src of a STACK becomes a
#                `const_like(0)` and the other src is untouched.
#   first=1      FIRST-WINS, on a node TWO rules both claim: a
#                `WHERE(cond,x,CONST(Invalid))` is claimed by `sym_2` (tag 2) and
#                by `pm_remove_invalid`'s tag 0, they DISAGREE, and `sym` must
#                answer tag 2. A fixture where both agreed could not tell
#                first-wins from a conjunction -- the trap the brief names.
#   promo=1      THE OPERATOR-LAYER RESTRICTION, stated as a row that CAN fail:
#                every fixture above is built from weakint CONSTs, so
#                `least_upper_dtype` is the identity and the missing
#                `mixin/elementwise.py` promotion CANNOT SHOW. The row moves the
#                moment a concrete-dtype fixture is added, and until then the
#                promotion is a stated caveat on every rule body rather than a
#                hidden one. `mixin/elementwise.py:50 def logical_not` is the one
#                mixin line this file borrows; see the TODO block.
#   bcast=1      tag 0: `STACK(CONST(Invalid), v) -> the Invalid`. This row and
#                `rej` exist BECAUSE a mutation could not move anything without
#                them (M9, M10 in the mutation table).
#   xorb/xorb0=1 the second REBIND, `(x^y)^y`, one fixture per side. `xorb0` is
#                what mutation M11 moves and `xorb` is what it does not.
#   rm_stack=1   `pm_remove_invalid` tag 1: an Invalid src of a STACK becomes a
#                `const_like(0)` and the other src is untouched.
#   inval_n=0    tag 3, `CAST(bool, WHERE(c,x,Invalid))`. RED and NOT DIAGNOSED:
#                the rule is written, the fixture is written, and the row says the
#                table does not answer. See the TODO block for what is missing.
#   inval_st=0   tag 4, `STORE(INDEX(b,CONST(Invalid)),v) -> NOOP`. Same: RED, not
#                diagnosed. The pattern reads `p_index_bad_or_cast` on src[0] and
#                the reject set `{CONST}` is a subset of the STORE's `ler`, so the
#                intended reasoning says it fires.
#   alu=1        the row that WAS WRONG IN ITS DIAGNOSIS. It read 0, and this
#                block blamed the affine arena and the read-back -- both of which
#                were fine: `i32_is` compares `exec_alu`'s own answer, and
#                `exec_alu(ADD, weakint, [5,6])` returned `None{}` because
#                `i64_fits_i32` was `i64_big`, i.e. "does NOT fit". So the lane
#                selector skipped every constant that fits, `fold_const_alu`
#                folded `5 + 6` to `CONST(0)` through `sy_maybe_c`'s default, and
#                a RED row was filed as a WALL. M12 moves it and CPython's
#                `exec_alu(Ops.ADD, dtypes.weakint, [5, 6])` is 11.
#   cdiv_neg=0   `cdiv(-7,2)` is -3. RED and NOT DIAGNOSED; `cdiv_i=1` is the
#                positive half and passes.
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
# because a MISSING rule and a MISSPELLED reject set are both invisible to a
# boolean. `skip` is the arithmetic that makes the port auditable:
# `len_sym + skip == total_sym == 127`, Python's own rule count for the blocks
# `sym` composes, and every one of the 114 is named in the TODO block below.
def t_len_sym() -> U32: U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(sym_table())))

def t_len_rm() -> U32: U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(rm_table())))

def t_total() -> U32: U32.add(U32.add(U32.add(U32.add(14, 47), 1), U32.add(U32.add(47, 2), U32.add(14, 2))), 0)

def t_skip() -> U32: U32.sub(t_total(), t_len_sym())

def rej_go(es: List<&2, O.PMEntry>, acc: Nat) -> Nat:
  match es:
    case Nil{}: acc
    case e <> t: rej_go(t, Nat.add(acc, Bool.pick(Nat, List.is_empty(&2, O.Op, O.PMEntry.rej(e)), 0n, 1n)))

def t_rej() -> U32: U32.from_nat(rej_go(O.PMEntrys.es(sym_table()), 0n))

def t_lay() -> U32: O.Arena.next(O.Found.ar(fx_add0()))

# A WALL THE GATE ITSELF STANDS ON, and it is the affine arena one more time.
# `fold_const_alu` GROWS the arena and answers with `Maybe<&1, U32>`, an INDEX
# into an arena the caller cannot see, so a fixture cannot read the folded node
# back. The two rows that replace one are therefore: `alu` is `exec_alu` called
# DIRECTLY on the two values, and `alu_rule` is "the RULE fired", which is all a
# `Maybe<&1, U32>` can say. Making the fold's node readable needs the rule to answer
# a `Found` -- `Maybe<&1, O.Found>`, which IS expressible because `Found` is `Data`.
def alu_eq(m: Maybe<&1, O.Const>) -> Bool: i32_is(m, H.i64_of_i32(11))

def alu_eq.go() -> Bool: alu_eq(exec_alu2(O.OpsADD{}, S.weakint(),
  O.CInt{H.i64_of_i32(5)}, O.CInt{H.i64_of_i32(6)}, False{}))

def t_alu() -> U32: Bool.to_u32(alu_eq.go())

def t_alu_rule() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, fold_const_alu.at(fx_of(fx_alu()), 3)))

# THE CONCRETE-DTYPE ROW. The same addition at int32, where `const_like` cannot
# emit a bare CONST and has to emit the CAST-on-top pair `UOp.const`'s own header
# defers. So the row is `is_op(4, CAST)` and it is about `const_like`, not about
# the arithmetic.
def f_cast_cast() -> Bool: sy_is_op(fx_of(fx_i32()), 4, O.OpsCAST{})

def t_alu_i32() -> U32: Bool.to_u32(f_cast_cast())

def t_alu_big() -> U32: Bool.to_u32(Maybe.is_none(&1, O.Const, exec_alu2(O.OpsADD{}, S.weakint(),
  O.CInt{H.i64_of_hi_lo(256, 0)}, O.CInt{H.i64_of_i32(1)}, False{})))

def t_alu_f32() -> U32: Bool.to_u32(f32_is(exec_alu_f32(O.OpsADD{}, 2, 1.5, 2.0, 0.0), 3.5))

def t_fdiv() -> U32: Bool.to_u32(f32_is(exec_alu_f32(O.OpsFLOORDIV{}, 2, 7.0, 2.0, 0.0), 3.0))

def t_fdiv_i() -> U32: Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsFLOORDIV{}, I3{2, 7, 2, 0}), H.i64_of_i32(3)))

def t_cdiv_i() -> U32: Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsCDIV{}, I3{2, 7, 2, 0}), H.i64_of_i32(3)))

def neg7() -> U32: H.i32_neg(7)

def t_cdiv_neg() -> U32:
  Bool.to_u32(i32_is(exec_alu_i32(False{}, O.OpsCDIV{}, I3{2, neg7(), 2, 0}),
    H.i64_sub(H.i64_of_i32(0), H.i64_of_i32(3))))

def t_inval() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_castbad()), 2), 1))

def t_inval_st() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_store()), 5), 6))

def t_inval_n() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, sym(fx_of(fx_gatecast()), 5)))

def t_selfadd() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_add0()), 3), 1))

def t_rebind() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_samediv()), 2), 3))

# `rebind0` asks for ABSENCE, not for a particular index: `x // y` must not be
# rewritten AT ALL. Written as `eq_u(m, 0)` the row would have been satisfied by
# any wrong-but-present answer, and the rebind mutation would have moved nothing.
# `t_inval_n` is the same shape and is written as `is_some` for the same reason.
def t_rebind0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_diffdiv()), 3)))

def t_group() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_group()), 2), 1))



# THE SECOND REBIND, `(x^y)^y -> x` -- symbolic.py:123 -- with a FIXTURE PER SIDE.
# The positive one shares its `y`; the negative one does not.
def fx_xor() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = f_new(O.Found.ar(b), O.OpsXOR{}, [f_i(a), f_i(b)], O.ANone{})
  f_alu2(c, O.OpsXOR{}, f_i(b))

def t_xorb() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_xor()), 4), 1))


def fx_xor2() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(9)})
  +d = f_new(O.Found.ar(c), O.OpsXOR{}, [f_i(a), f_i(b)], O.ANone{})
  f_alu2(d, O.OpsXOR{}, f_i(c))

def t_xorb0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_xor2()), 5)))
# THE TAG-0 FIXTURE. `sym_0` is `STACK(CONST(Invalid), ...) -> the Invalid`, and
# `broadcast` is an `itertools.repeat`, so the STACK may have any arity >= 1.
def fx_bcast() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInvalid{})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})

def t_bcast() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_bcast()), 3), 1))

def t_sink() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_sink()), 5), 6))

def t_rm_where() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_where()), 4), 5))

def t_rm_stack() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_stack()), 3), 4))

# THE FIRST-WINS FIXTURE. The overlapping pair is `sym_11` (`GROUP(x)` -> x) and
# `sym_12` (the GROUP/SINK flatten), both claiming a one-src GROUP whose src is
# sink-like, and they DISAGREE -- tag 11 answers the src, tag 12 a flattened
# rebuild. (`sym_2` and `pm_remove_invalid`'s tag 0 look like a pair and are not:
# their two shapes are mutually exclusive, so they can never both claim a node.)
def t_first() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_two()), 3), 2))

def promo_row() -> Bool: Bool.pick(Bool, p_weak(fx_of(fx_add0()), 1), True{}, False{})

def t_promo() -> U32: Bool.to_u32(promo_row())

# NOT PORTED, one line each, and the WALL each one is behind. The Python line
# numbers are `symbolic.py`'s, so this list diffs against it line for line and
# `grep "TODO(p3)" tinybendygrad/uop/symbolic.bend` is the work queue. THE
# `skip=114` ROW IS THE ARITHMETIC OF THIS BLOCK: 127 is what symbolic.py's own
# blocks imply and 13 is what the table holds, so 114 are named here.
#
# THE FOUR THAT ARE GENUINELY UNAVAILABLE, and they are all P3 or later.
# TODO(p3) symbolic.py:72  def lift_reduce_gate -- `c.ranges` for every range of
#   every src, and `c.ranges` is `UOp._ranges` (ops.py:483): a UNION of the srcs'
#   ranges minus the ended ones, over a `set`. fold.bend's own TODO on it says the
#   set algebra is P3. P3, and it is ONE rule of `pm_data_invalid` (:88).
# TODO(p3) symbolic.py:222-226 table `commutative` -- `x.src[1].tuplize <
#   x.src[0].tuplize`, and `tuplize` (ops.py:322) is a SORT KEY over
#   `(op, src-tuple, arg)` where `arg` is a Python `Any` with eighteen shapes and
#   no total order. The arena has an order for the first two and nothing for the
#   third. P3 with `key` (ops.py:267).
# TODO(p3) symbolic.py:315-317 the `AFTER` src expansion -- a `flatten` over a
#   `dedup` over a list comprehension keyed on an op SET, and `dedup` is a set
#   walk. The shape is portable; the dedup is P3's set algebra.
# TODO(p3) symbolic.py:406-425 def where_on_load + pm_move_where_on_load --
#   `idx.get_valid()`, `idx.get_idx()`, `backward_slice_with_self` and
#   `c.ranges.keys() <= idx.ranges.keys()`. Three of the four are P3 folds and the
#   fourth is the set algebra again. P3, and it is TWO rules.
#
# THE REST ARE BEHIND A PROPERTY FOLD, and each one names the fold that owns it.
# TODO(p3) symbolic.py:16  def simplify_pow -- TWO of its FIVE arms are ported
#   (`c.val < 0` and `c.val == 0`). The HALF arm needs `int(h)+0.5 == c.val` on a
#   Python float, and the halving needs `i64_div`; `helpers.bend` has no
#   `I64 -> F32`, no `F32 -> I64` and no `i64_div`/`i64_mod`. P3 with
#   `helpers.bend`'s arithmetic.
# TODO(p3) symbolic.py:31  def _quotient_base and :43 fold_add_divmod_recombine
#   -- PORTED IN SHAPE and deferred in one line: both need `UOp.pop_const` (which
#   IS here, as `sy_pop`) and `UOp.divides` (which is NOT: `const_factor` needs
#   `math.gcd` and `helpers.bend` has no gcd). The rule bodies are index
#   arithmetic and would port; `divides` is the whole of the block. P3 with gcd.
# TODO(p3) symbolic.py:72  (see above)
# TODO(p3) symbolic.py:82-88 the six `pm_data_invalid` rules that need
#   `cond.where(op.replace(src=(x,)), i)` over a CAST/BITCAST and over a Binary --
#   PORTED IN SHAPE and deferred on `_min_max`: none of them does, but
#   `symbolic.py:86`'s `Binary - Comparison` arm and :82's `Unary|{CAST,BITCAST}`
#   arm need the SET DIFFERENCES written as op lists, which is done here -- what
#   is missing is a FIXTURE with a four-src WHERE, and `lift_reduce_gate`. P3.
# TODO(p3) symbolic.py:126 `UPat(Ops.ADD, dtype=dtypes.weakint) ->
#   fold_add_divmod_recombine` -- `divides`, as above.
# TODO(p3) symbolic.py:124 `((x%y)%y -> x%y)` -- `y` IS BOUND TWICE WITHIN ONE
#   SRC SPINE, so this needs `sym_8`'s IDENTITY CHECK; upstream writes it with
#   `base` "for speed". Not in the table and not otherwise named, which is a
#   bookkeeping hole in `skip=114`'s arithmetic. P3, with `sym_8`'s shape.
# TODO(p3) symbolic.py:135-136 the `CAST(bool -> ints+weakint) != cvar` rule --
#   `UPat.var("x").cast(dtypes.ints+(dtypes.weakint,))` needs a SIX-way dtype SET
#   on a CAST, and `dt_intish` here is six `eq_dt`s, so the PATTERN is ported; the
#   body needs `x.const_like(True)` at a bool dtype, which `sy_cconst` gives, and
#   the three-way `if c.val == 0 / == 1 / else` on an I64. NOT DONE because the
#   three-way test needs `c.val == 1` on an I64 and `H.i64_cmp` returns a `Cmp`,
#   which is the shape of every other comparison here -- so this is a half-hour,
#   not a wall. P3, and it is the cheapest item on this list.
# TODO(p3) symbolic.py:144-146 the two `(x & mask) >> k` and `(x & mask) // c`
#   rules -- `mask.val | ((1 << k.val) - 1) == -1` is I64 BIT ARITHMETIC, and
#   `helpers.bend` has `i64_add`/`i64_sub`/`i64_cmp` and no `i64_or`, no
#   `i64_shl` and no `i64_and`. Two rules. P3 with the I64 bit ops.
# TODO(p3) symbolic.py:160 the `Binary - {THREEFRY}` weak-src promotion rule --
#   `promo_dtype(a.src)` IS ported (fold.bend's lattice) and `dtypes.weaks` IS
#   `p_weak`; what is missing is the `a.replace(src=...)` over a LIST whose
#   length is `nsrc`, which is a general-arity fold this file does not have. It is
#   a fold, not a wall: `sink_srcs.go` is the same shape. P3.
# TODO(p3) symbolic.py:183 `b.cast(a).cast(b)` -- `can_lossless_cast`
#   (dtype.py:141), which reads the dtype table in `./dtype.bend`, and that file is
#   a C-effect module that cannot be imported (ops.bend's header says why). P3.
# TODO(p3) symbolic.py:192-193 the two threefry unpack rules -- PORTED IN SHAPE.
#   They need `UOp.var(None, dtypes.uint64)` (an ANY-DTYPE var) and a
#   `cast(dtypes.uint64)`, both of which are `sy_var`-free here; the four dtype
#   tests are `eq_dt`s. NOT DONE because the pattern needs an UNNAMED var in src
#   position, which the compiled form spells as a plain `src[k]` test and the two
#   rules disagree about WHICH src is unnamed -- a four-way disjunction per rule.
#   P3.
# TODO(p3) symbolic.py:203 def lt_folding -- `u.const_factor()` (-> `divides` ->
#   `gcd`), `sum(u.vmin for u in p)` and `sum(u.vmax for u in p)`. Two of the
#   three are `_min_max` (ops.py:1104, the largest single piece `fold.bend`
#   defers). P3.
# TODO(p3) symbolic.py:209 def canonicalize_simplex -- `u.vmin >= 0` and
#   `GroupOp.Irreducible`, i.e. `_min_max` again. P3.
# TODO(p3) symbolic.py:228 def fold_where_closure -- `bool_slice`
#   (ops.py:290, a frozenset union down the srcs), `op_in_backward_slice_with_self`
#   (a toposort plus a pop) and `substitute` + `simplify` (which are
#   `graph_rewrite`). P3, and it is the largest single unlock after `_min_max`.
# TODO(p3) symbolic.py:236-323 table `symbolic` -- ALL 47. Every one of the 47
#   reaches for `vmin`/`vmax` (`_min_max`), `const_factor` (-> `gcd`),
#   `tuplize`, `bool_slice`, `backward_slice` or `substitute`. There is no
#   sub-block of it that is answerable without one of those, which is why the
#   block is 47 and not "most of it". P3 with `_min_max` first.
# TODO(p3) symbolic.py:328-386 parse_valid / uop_given_valid / _valid_priority /
#   simplify_valid -- `vmin`/`vmax` for the bounds, `ranges` for the simplex arm,
#   `substitute` and `simplify` for the candidate substitution, and
#   `UOp.variable` (ops.py:1013) for the fake variables. Four functions, none
#   answerable alone. P3.
# TODO(p3) symbolic.py:390 def reduce_mul_chain -- `backward_slice` and `vmin`.
#   P3.
# TODO(p3) symbolic.py:400-403 def drop_and_clauses + pm_drop_and_clauses --
#   `c.ranges` on both sides, i.e. the set algebra. ONE rule, and it is the whole
#   of `pm_drop_and_clauses`; `schedule/indexing.py` composes it. P3.
# TODO(p3) symbolic.py:427 def gated_given_valid -- `IMAGE.value`, a
#   `ContextVar` (helpers.py), which is a process-wide mutable Bend has no home
#   for, plus `uop_given_valid` from the block above. P3/P6 for the flag.
# TODO(p3) symbolic.py:452 the `xpow` rule -- `xpow` is
#   `tinygrad/codegen/decomp/transcendental.py`, a foreign import (symbolic.py:12
#   says "TODO: symbolic shouldn't be importing from codegen"). It is seven UOp
#   expressions and every one of them needs `log2`/`exp2`/`cast`/`mod`/`where`
#   sugar this file does not have. P3, and it is owned by the transcendental
#   unit.
# TODO(p3) symbolic.py:454-462 the four load/store folding rules -- `UOp.index`,
#   `UOp.valid`, `UOp.store` with a `ConstType` src and `UOp.load`, all of which
#   are `movement.bend`'s and `weak.bend`'s (both now present in the tree, both
#   concurrent work, neither read as authoritative here). P3.
# TODO(p3) symbolic.py:463-468 the four reciprocal rules -- the FIRST is PORTED
#   (`sym_10`). The other three are the same shape at `MUL(MUL,MUL)` and
#   `MUL(x, MUL(RECIPROCAL, y))`, so they are a fold over a shape this file has
#   and were left for the next pass.
# TODO(p3) symbolic.py:472-474 `-(x+y)` and `(x+y)*c -> x*c+y*c` -- both are two
#   `alu`s over a `sym_6`-shaped PERMUTATION, i.e. the same shape as `sym_6` and
#   `sym_10`; deferred for budget, not for a wall. NOTE the second is the one
#   rule in the file whose answer DEPENDS ON the missing promotion: it is
#   `dtypes.weakint`-only for that reason.
# TODO(p3) symbolic.py:306-313 the two long/cast folding rules -- `x.overflows(a)`
#   (ops.py:683, `self.vmin < dtype.min or dtype.max < self.vmax`) and `cast`, so
#   `_min_max` and `dtype.min`/`dtype.max`. `S.Dt.min`/`S.Dt.max` ARE here;
#   `_min_max` is not. P3.
# TODO(p3) mixin/elementwise.py:50 def logical_not -- BORROWED, not this file's.
#   Three of `pm_data_invalid`'s rules cannot be written without it, it is two
#   lines, and `sy_logical_not` here is the borrow. It is `self.cast(dtypes.bool)
#   .ne(True)` with the `.cast(bool)` folded away, which is exactly what
#   symbolic.py:131-133 asserts. The owner is the elementwise unit; when it lands,
#   this def goes and its three callers name `x.logical_not`.
#
# WHAT NEXT, in the order the walls fall.
#   1. `_min_max` (ops.py:1104) unblocks `lt_folding`, `canonicalize_simplex`,
#      `reduce_mul_chain`, `parse_valid`, `uop_given_valid`, `_valid_priority`,
#      `simplify_valid`, `gated_given_valid` and about half of `symbolic`'s 47 --
#      nine of the fourteen deferred blocks. It is `fold.bend`'s biggest piece.
#   2. `UOp.ranges` + the set algebra unblocks `lift_reduce_gate`,
#      `drop_and_clauses`, `where_on_load` and `fold_where_closure`.
#   3. `math.gcd` on an I64 unblocks `const_factor`, `divides`, `_quotient_base`
#      and `fold_add_divmod_recombine`.
#   4. `mixin/elementwise.py`'s promotion unblocks `can_lossless_cast`-free
#      arithmetic in twenty-odd rule bodies, and removes the `promo` caveat from
#      every row.
#   5. `UOp.simplify` / `substitute` / `graph_rewrite` unblocks
#      `fold_where_closure` and `uop_given_valid`, and is P3 for `fold.bend` too.
#
# THE MUTATION TABLE, MEASURED. All twelve were applied, run, and reverted, with a
# before/after diff of every row.
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | M1 `sy_keep.go` first-wins -> last-wins | `first` | 1 |
# | M2 `sy_novel.hit` drops the `ret is not uop` test | NOTHING | 0 |
# | M3 `sym_7.pat` drops the `x // x` REBIND identity check | `rebind0` | 1 |
# | M4 `sym_try`'s `claimed and early` -> `or` | `rebind0` | 1 |
# | M5 `rm_try`'s `claimed and early` -> `or` | NOTHING | 0 |
# | M6 `const_i64`'s `is_eq` -> `not is_eq` | `selfadd`, `xorb`, `xorb0` | 3 |
# | M7 `exec_alu.pick`'s Invalid poison `and` -> `not` | `alu_big` | 1 |
# | M8 `i32_fdiv.step` drops the `r != 0` half of its guard | `fdiv_i` | 1 |
# | M9 `sym_table` tag 3's reject set -> `Nil{}` | `rej` | 1 |
# | M10 `sym_dispatch.go` tag 0 -> tag 1 (a MIS-SPELLED tag) | `bcast` | 1 |
# | M11 `sym_8.inner` drops the `(x^y)^y` REBIND identity check | `xorb0` | 1 |
# | M12 `i64_fits_i32`'s `Bool.not(i64_big(i))` -> `i64_big(i)` | `alu` | 1 |
#
# WHAT THE TABLE SAYS, in five lines.
#   * M2 AND M5 MOVED NOTHING, and both are honest negatives. No rule in this
#     table returns its matched node, so `sy_novel` has no witness yet; and
#     `rm_table`'s two reject sets are violated by no fixture, so M5 is
#     unreachable. The second is a FIXTURE GAP, not a property of the code.
#   * M3 AND M11 ARE THE SAME SHAPE, both localised to their own NEGATIVE row:
#     `rebind0` and `xorb0`, never `rebind`/`xorb`. A positive rebind row is worth
#     nothing on its own; only the two-sided fixture can see the identity check go.
#   * M6 is the only mutation with three rows, all three the constant-shape tests,
#     because `sym_6.pat`'s `UPat.const(0)` and `sym_8`'s shape share `const_i64`.
#   * M9 AND M10 ARE THE TWO ROWS THAT EXIST ONLY FOR A MIS-SPELLING: a COUNT is
#     the only witness for a reject set, and only tag 0's fixture witnesses a tag.
#   * M12 IS THE ONLY MUTATION THAT WAS A LIVE BUG rather than a probe: it took
#     `alu` from 1 to 0 and it took the DEVICE with it -- `exec_alu2(MUL, int32,
#     [CInt(6), CInt(7)])` answers `CInt(42)` with the fix and `None{}` without it.
#     One row is the whole sensitivity, so `alu` is the only witness the lane
#     selector has; the two divergences listed at `exec_alu.pick` move NO row.
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def fz.gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lay", t_lay())
    b : Unit <- row("len_sym", t_len_sym())
    c : Unit <- row("len_rm", t_len_rm())
    d : Unit <- row("total_sym", t_total())
    e : Unit <- row("skip", t_skip())
    f : Unit <- row("rej", t_rej())
    g : Unit <- row("alu", t_alu())
    h : Unit <- row("alu_rule", t_alu_rule())
    i : Unit <- row("alu_i32", t_alu_i32())
    j : Unit <- row("alu_big", t_alu_big())
    k : Unit <- row("alu_f32", t_alu_f32())
    m : Unit <- row("fdiv", t_fdiv())
    n : Unit <- row("fdiv_i", t_fdiv_i())
    o : Unit <- row("cdiv_i", t_cdiv_i())
    p : Unit <- row("cdiv_neg", t_cdiv_neg())
    q : Unit <- row("inval", t_inval())
    r : Unit <- row("inval_st", t_inval_st())
    s : Unit <- row("inval_n", t_inval_n())
    u : Unit <- row("selfadd", t_selfadd())
    v : Unit <- row("rebind", t_rebind())
    w : Unit <- row("rebind0", t_rebind0())
    x : Unit <- row("group", t_group())
    y : Unit <- row("sink", t_sink())
    z : Unit <- row("rm_where", t_rm_where())
    row("rm_stack", t_rm_stack())
    row("first", t_first())
    row("xorb", t_xorb())
    row("xorb0", t_xorb0())
    row("bcast", t_bcast())
    row("promo", t_promo())

# THE FUZZ DRIVER. `main` with NO argument is the gate above, byte for byte; with
# ONE argument it reads that case file, builds the arena out of the s-expr the case
# format IS, runs `sym` and `pm_remove_invalid` over the root, and prints ONE
# canonical line. The case format and the canonical form are the SAME s-expr, so the
# oracle and the driver can both print `sh(u)` and diff.
#
# THE FORMAT, and the leaves are the whole vocabulary:
#   (add c7 c0)             an ALU over two weakint CONSTs
#   (cast:int c7)           a CAST naming its dtype after a colon
#   (xor (xor c5 c7) c7)    a name bound twice, which is the rebind check
#   c7 c0 n7 bt bf bad      a CONST: non-negative, negative, bool true, bool
#                           false, and `Invalid`
#   x xb xf xi              a PARAM (`UOp.variable`) at weakint, bool, weakfloat
#                           and int32
# Anything the port cannot state is NOT in the vocabulary, and the exclusions are
# in the harness rather than discovered: no float CONST (`F32.bits` has no
# inverse, so a canonical float spelling is not expressible), no CONST outside
# int32 (`exec_alu`'s integer lane is int32, and its value is an I64), and no
# op behind `vmin`/`vmax`/`const_factor`/`tuplize`/`gcd`/`ranges`, all of which
# are `TODO(p3)` in the block above.
#
# WHY THE SCAN IS ONE DEF WITH A MODE: a token scan that dispatches on the class of
# the character it is looking at cannot be two mutually recursive defs. It is one
# def, `m` selects "at a boundary" from "inside a word", `wm` says WHICH word, and
# every edge spends a Nat of fuel.
type Tok is Data:
  TClose{}
  THead{w: String}
  TLeaf{w: String}

type Frm is Data:
  Frm{srcs: List<&2, U32>, head: String}

type St is Data:
  St{ar: O.Arena, stk: List<&2, Frm>, root: Maybe<&2, U32>}

def fz_code(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{Chr{c}, t}: c

def fz_hs(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}: String.from_list([Char.from_u32(c)])

# 0 is the end of the line, 1 is `)`, 2 is `(`, 3 is a space, 4 is a word char.
def fz_cls.pick(cu: U32) -> U32:
  match cu:
    case 41: 1
    case 40: 2
    case 32: 3
    case 9: 3
    case 10: 3
    case 13: 3
    case _: 4

def fz_cls.of(s: String, cu: U32) -> U32:
  match s:
    case SNil{}: 0
    case SCon{Chr{c}, t}: fz_cls.pick(cu)

def fz_cls(+s: String) -> U32: fz_cls.of(s, fz_code(s))

def fz_tok.tok(w: String, wm: U32) -> Tok:
  match wm:
    case 2: THead{w}
    case _: TLeaf{w}

# A word is emitted the moment its terminator arrives, and a `)` terminates a word
# AND closes a node, so on a `)` the two tokens go out together. That is what lets
# every edge below shrink `s`, which is what the fuel buys.
def fz_tok(n: Nat, md: U32, +s: String, acc: List<&2, Tok>, w: String, k: U32) -> List<&2, Tok>:
  match n:
    case 0n: acc
    case 1n+p:
      match md:
        case 0:
          match k:
            case 0: fz_tok(p, 0, String.drop(s, 1n), List.append(&2, Tok, acc, [TClose{}]), "", fz_cls(String.drop(s, 1n)))
            case 1: fz_tok(p, 0, String.drop(s, 1n), acc, "", fz_cls(String.drop(s, 1n)))
            case 2: fz_tok(p, 0, String.drop(s, 1n), acc, "", fz_cls(String.drop(s, 1n)))
            case _: fz_tok(p, 1, String.drop(s, 1n), acc, "", fz_cls(String.drop(s, 1n)))
        case 1:
          match k:
            case 4: fz_tok(p, 1, String.drop(s, 1n), acc, String.concat([w, fz_hs(s)]), fz_cls(String.drop(s, 1n)))
            case 0: fz_tok(p, 0, String.drop(s, 1n), List.append(&2, Tok, acc, [fz_tok.tok(w, md), TClose{}]), "", fz_cls(String.drop(s, 1n)))
            case _: fz_tok(p, 0, String.drop(s, 1n), List.append(&2, Tok, acc, [fz_tok.tok(w, md)]), "", fz_cls(String.drop(s, 1n)))
        case _:
          match k:
            case 4: fz_tok(p, 2, String.drop(s, 1n), acc, String.concat([w, fz_hs(s)]), fz_cls(String.drop(s, 1n)))
            case 0: fz_tok(p, 0, String.drop(s, 1n), List.append(&2, Tok, acc, [fz_tok.tok(w, md), TClose{}]), "", fz_cls(String.drop(s, 1n)))
            case _: fz_tok(p, 0, String.drop(s, 1n), List.append(&2, Tok, acc, [fz_tok.tok(w, md)]), "", fz_cls(String.drop(s, 1n)))

def fz_toks(+s: String) -> List<&2, Tok>: fz_tok(4096n, 0, s, Nil{}, "", fz_cls(s))

# THE VOCABULARY. A head token is the op's own `Ops.name` in lower case, so a typo
# cannot hide: the driver PRINTS `Ops.name`, so a head it did not recognise comes
# back as `NOOP`.
def fz_dt(nm: String) -> S.Dt:
  match nm:
    case "weakint": S.weakint()
    case "bool": S.boolean()
    case "int": S.int32()
    case "unsigned int": S.uint32()
    case "long": S.int64()
    case "unsigned long": S.uint64()
    case "float": S.single()
    case "weakfloat": S.weakfloat()
    case _: S.void()

def fz_dtnm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def fz_part(nm: String, k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(nm, Char.from_u32(58)), k), "")

def fz_arg.dt.of(dt: S.Dt) -> O.Arg:
  match dt:
    case S.Dt{0, 0, S.CVoid{}, _}: O.ANone{}
    case _: O.ADt{dt}

def fz_arg(op: O.Op, nm: String) -> O.Arg:
  match op:
    case O.OpsCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case O.OpsBITCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case _: O.ANone{}

def fz_op(nm: String) -> O.Op:
  match nm:
    case "noop": O.OpsNOOP{}
    case "sink": O.OpsSINK{}
    case "group": O.OpsGROUP{}
    case "stack": O.OpsSTACK{}
    case "index": O.OpsINDEX{}
    case "load": O.OpsLOAD{}
    case "store": O.OpsSTORE{}
    case "where": O.OpsWHERE{}
    case "cast": O.OpsCAST{}
    case "bitcast": O.OpsBITCAST{}
    case "exp2": O.OpsEXP2{}
    case "log2": O.OpsLOG2{}
    case "sin": O.OpsSIN{}
    case "sqrt": O.OpsSQRT{}
    case "reciprocal": O.OpsRECIPROCAL{}
    case "neg": O.OpsNEG{}
    case "trunc": O.OpsTRUNC{}
    case "add": O.OpsADD{}
    case "mul": O.OpsMUL{}
    case "shl": O.OpsSHL{}
    case "shr": O.OpsSHR{}
    case "cdiv": O.OpsCDIV{}
    case "max": O.OpsMAX{}
    case "cmod": O.OpsCMOD{}
    case "cmplt": O.OpsCMPLT{}
    case "cmpne": O.OpsCMPNE{}
    case "cmpeq": O.OpsCMPEQ{}
    case "xor": O.OpsXOR{}
    case "or": O.OpsOR{}
    case "and": O.OpsAND{}
    case "threefry": O.OpsTHREEFRY{}
    case "sub": O.OpsSUB{}
    case "fdiv": O.OpsFDIV{}
    case "pow": O.OpsPOW{}
    case "floordiv": O.OpsFLOORDIV{}
    case "floormod": O.OpsFLOORMOD{}
    case "mulacc": O.OpsMULACC{}
    case _: O.OpsNOOP{}

# THE BUILD. One def, and every def it calls does NOT call back, so this is a fold
# and not a cycle. A frame is pushed on a HEAD and popped on a CLOSE, and `St.root`
# is the finished node: a list tail cannot carry what the frame above has to be
# handed, so the answer rides out in the state.
def St.ar(s: St) -> O.Arena:
  match s:
    case St{ar, stk, root}: ar

def St.stk(s: St) -> List<&2, Frm>:
  match s:
    case St{ar, stk, root}: stk

def St.root(s: St) -> Maybe<&2, U32>:
  match s:
    case St{ar, stk, root}: root

def Frm.srcs(f: Frm) -> List<&2, U32>:
  match f:
    case Frm{srcs, head}: srcs

def Frm.head(f: Frm) -> String:
  match f:
    case Frm{srcs, head}: head

def fz_deliver.at(t: List<&2, Frm>, +st: St, i: U32) -> St:
  match t:
    case +f <> u: St{St.ar(st), List.append(&2, Frm, u,
      [Frm{List.append(&2, U32, Frm.srcs(f), [i]), Frm.head(f)}]), St.root(st)}
    case Nil{}: St{St.ar(st), Nil{}, Some{i}}

def fz_deliver(+st: St, i: U32) -> St: fz_deliver.at(St.stk(st), st, i)

# A node is closed, so BUILD it and hand it to the frame above. The arena and the
# index both come out of the one `Found`, which is why this is one def.
def fz_close.give(+f: O.Found, u: List<&2, Frm>, r: Maybe<&2, U32>) -> St:
  fz_deliver(St{O.Found.ar(f), u, r}, O.Found.i(f))

def fz_close.new.of(+op: O.Op, ar: O.Arena, nm: String, srcs: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, op, srcs, fz_arg(op, nm), O.TNone{})

def fz_close.new(ar: O.Arena, +nm: String, srcs: List<&2, U32>) -> O.Found:
  fz_close.new.of(fz_op(fz_part(nm, 0n)), ar, nm, srcs)

def fz_close.at(t: List<&2, Frm>, ar: O.Arena, r: Maybe<&2, U32>) -> St:
  match t:
    case +f <> u: fz_close.give(fz_close.new(ar, Frm.head(f), Frm.srcs(f)), u, r)
    case Nil{}: St{ar, Nil{}, r}

def fz_close(+st: St) -> St: fz_close.at(St.stk(st), St.ar(st), St.root(st))

def fz_i64_neg(u: U32) -> H.I64: H.i64_sub(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, u))

def fz_num.of(m: Maybe<&2, U32>) -> U32: Maybe.default(&2, U32, m, 0)

def fz_num(w: String) -> U32: fz_num.of(U32.read(w))

# `c7` is a non-negative weakint CONST and `n7` a negative one.
def fz_leaf.sgn(c: U32, w: String, ar: O.Arena) -> O.Found:
  match c:
    case 99: O.UOp.const(ar, O.CInt{H.i64_of_hi_lo(0, fz_num(String.drop(w, 1n)))})
    case _: O.UOp.const(ar, O.CInt{fz_i64_neg(fz_num(String.drop(w, 1n)))})

# `UOp.variable` -- ops.py:1013, "a Variable is a scalar ALU PARAM with a name
# and a value range", which is the whole of the `ParamArg` this driver states.
def fz_var(dt: S.Dt) -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{4294967295, dt, None{}, Some{O.PyRange{H.i64_of_hi_lo(0, 0), H.i64_of_i32(100)}}, Some{1}, Some{"v"}, S.Aalu{},
      None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# The four CONST spellings and the four VARIABLE dtypes. A leaf is interned into
# the arena the state already carries, so a repeated `c7` in one case is ONE
# node -- which is what makes `x // x` and `x // y` distinguishable at all.
def fz_leaf.go(+ar: O.Arena, +w: String) -> O.Found:
  match w:
    case "bad": O.UOp.const(ar, O.CInvalid{})
    case "bt": O.UOp.const(ar, O.CBool{True{}})
    case "bf": O.UOp.const(ar, O.CBool{False{}})
    case "x": fz_var(S.weakint())
    case "xb": fz_var(S.boolean())
    case "xf": fz_var(S.weakfloat())
    case "xi": fz_var(S.int32())
    case _: fz_leaf.sgn(fz_code(w), w, ar)

def fz_leaf(+st: St, w: String) -> O.Found: fz_leaf.go(St.ar(st), w)

def fz_build.one(t: Tok, +st: St) -> St:
  match t:
    case THead{w}: St{St.ar(st), List.append(&2, Frm, St.stk(st), [Frm{Nil{}, w}]), St.root(st)}
    case TLeaf{w}: fz_close.give(fz_leaf(st, w), St.stk(st), St.root(st))
    case TClose{}: fz_close(st)

def fz_build(ts: List<&2, Tok>, +st: St) -> St:
  match ts:
    case Nil{}: st
    case t <> r: fz_build(r, fz_build.one(t, st))

# THE CANONICAL FORM IS THE SAME S-EXPR, rendered in TWO PHASES because a node's
# text needs its own srcs' text and that is a cycle Bend refuses: `fz_jobs`
# flattens the arena walk into a pre-order JOB LIST and `fz_emit` folds that list
# into text.
#
# THE JOB, and `close` says which of the two texts it is: `Jz{u, False}` is
# "(name " for the node at `u` and `Jz{0, True}` is ")". A leaf is one job too
# -- its op is CONST or PARAM, so its "name" is the const or the variable.
type Jz is Data:
  Jz{u: U32, close: Bool}

def Jz.close(j: Jz) -> Bool:
  match j:
    case Jz{u, close}: close

def Jz.u(j: Jz) -> U32:
  match j:
    case Jz{u, close}: u

# THE FLATTEN. `m` is 0 for "start the node at `u`" and 1 for "walk the rest of the
# srcs of `u`", because the walk descends into a src and comes BACK, which is the
# second half of the cycle. `w` is fuel as a LIST because one step makes TWO
# recursive calls -- the descent and the walk on -- and a Nat would be read twice.
def fz_jobs.splice(ar: O.Arena, s: U32, sub: List<Jz>, cont: List<Jz>) -> List<Jz>:
  List.append(&1, Jz, [Jz{s, False{}}], List.append(&1, Jz, sub, List.append(&1, Jz, [Jz{0, True{}}], cont)))

def fz_jobs(w: List<&2, Nat>, m: U32, +ar: O.Arena, +u: U32, t: List<&2, U32>, acc: List<Jz>) -> List<Jz>:
  match w:
    case Nil{}: acc
    case a <> +rest:
      match m:
        case 0: fz_jobs(rest, 1, ar, u, O.Arena.srcs(ar, u), List.append(&1, Jz, acc, [Jz{u, False{}}]))
        case _:
          match t:
            case Nil{}: List.append(&1, Jz, acc, [Jz{0, True{}}])
            case +s <> r: List.append(&1, Jz, acc,
              fz_jobs.splice(ar, s, fz_jobs(rest, 0, ar, s, Nil{}, Nil{}), fz_jobs(rest, 1, ar, u, r, Nil{})))

def fz_jobs.root(ar: O.Arena, u: U32) -> List<Jz>: fz_jobs([4096n], 0, ar, u, Nil{}, Nil{})

# A LEAF IS ITS OWN TEXT: a CONST is `c7`/`n7`/`bt`/`bf`/`bad` and a PARAM is
# the variable at its dtype, and neither is a node with a name and srcs.
def fz_render.i64.of(i: H.I64, neg: Bool) -> String:
  match neg:
    case True{}: String.concat(["n", U32.show(U32.sub(0, H.lo32(i)))])
    case False{}: String.concat(["c", U32.show(H.lo32(i))])

def fz_render.i64(+i: H.I64) -> String: fz_render.i64.of(i, H.i64_is_neg(i))

def fz_render.cval(v: O.Const) -> String:
  match v:
    case O.CInvalid{}: "bad"
    case O.CBool{b}: match b:
      case True{}: "bt"
      case False{}: "bf"
    case O.CInt{i}: fz_render.i64(i)
    case _: "?"

def fz_render.const(a: O.Arg) -> String:
  match a:
    case O.APy{v}: fz_render.cval(v)
    case _: "?"

def fz_render.dt(d: S.Dt) -> String:
  match d:
    case S.Dt{0, 800, S.CWeakInt{}, _}: "x"
    case S.Dt{0, 1, S.CBool{}, _}: "xb"
    case S.Dt{9, 800, S.CWeakFloat{}, _}: "xf"
    case S.Dt{5, 32, S.CSint{}, _}: "xi"
    case _: "?"

def fz_render.param(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: fz_render.dt(O.ParamArg.dtype(pa))
    case _: "?"

# THE OP NAME AND ITS DTYPE SUFFIX, which is `Ops.name` plus a `:` and the
# dtype when the op's arg states one. `(cast:int c7)` and `(add c7 c0)` are the
# two shapes, and the arg is the only difference.
def fz_head.sfx(a: O.Arg, nm: String) -> String:
  match a:
    case O.ADt{dt}: String.concat([nm, ":", fz_dtnm(dt)])
    case _: nm

def fz_head.of(op: O.Op, a: O.Arg, ar: O.Arena) -> String:
  match op:
    case O.OpsCONST{}: fz_render.const(a)
    case O.OpsPARAM{}: fz_render.param(a)
    case _: fz_head.sfx(a, O.Ops.name(op))

def fz_head(+ar: O.Arena, +u: U32) -> String: fz_head.of(O.Arena.op(ar, u), O.Arena.arg(ar, u), ar)

# THE FOLD. One job per step, so the job list IS the fuel and there is no
# counter. The job is destructured in the LIST pattern, so `close` is a binder
# and the arm below is legal -- a match on `Jz.close(j)` would be a match on a
# call, which Bend refuses.
def fz_emit(w: List<Jz>, +ar: O.Arena, acc: String) -> String:
  match w:
    case Nil{}: acc
    case Jz{u, close} <> rest:
      match close:
        case True{}: fz_emit(rest, ar, String.concat([acc, ")"]))
        case False{}: fz_emit(rest, ar, String.concat([acc, "(", fz_head(ar, u), " "]))

def fz_render(+ar: O.Arena, u: U32) -> String: fz_emit(fz_jobs.root(ar, u), ar, "")

def fz_ans.txt(ar: O.Arena, m: Maybe<&1, U32>) -> String:
  match m:
    case Some{i}: fz_render(ar, i)
    case _: "norewrite"

# ONE CANONICAL LINE, and the two answers are the two TABLES: `sym` and `rm`
# (`pm_remove_invalid`). Two tables means two answers, and one line means the
# harness diffs one string.
def fz_line(+ar: O.Arena, +u: U32) -> String:
  String.concat(["root=", U32.show(u), " n=", U32.show(O.Arena.next(ar)), " op=", O.Ops.name(O.Arena.op(ar, u)),
    " selfadd=", U32.show(Bool.to_u32(eq_u(sym(F.folded(ar), u), 1))),
    " sym=", fz_ans.txt(ar, sym(F.folded(ar), u)), " rm=", fz_ans.txt(ar, pm_remove_invalid(F.folded(ar), u))])

def fz_run.go(ar: O.Arena, r: Maybe<&2, U32>) -> String:
  match r:
    case Some{u}: fz_line(ar, u)
    case _: "parse-error"

def fz_run.at(+st: St) -> String: fz_run.go(St.ar(st), St.root(st))

def fz_run(+s: String) -> String: fz_run.at(fz_build(fz_toks(s), St{O.Arena.empty(), Nil{}, None{}}))

def fz_read.closed(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(f)
    IO.pure(String, s)

def fz_read(path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 65536)
    fz_read.closed(m)

# THE DRIVER BRANCH. No argument is the gate; one argument is a case file, so the
# GATE BODY IS `fz.gate` AND NOTHING ELSE. `IO.args()` LEADS WITH THE PROGRAM NAME,
# so the case path is the head of the TAIL and an empty tail is the gate.
def fz.drive.path(as: List<String>) -> String:
  Maybe.default(&1, String, List.get(&1, String, as, 0n), "")

def fz.drive.br(as: List<String>) -> IO(Unit):
  match as:
    case Nil{}: fz.gate()
    case _ <> _:
      do IO<Unit>:
        s : String <- fz_read(fz.drive.path(as))
        IO.print(fz_run(s))

def fz.drive.go(as: List<String>) -> IO(Unit):
  fz.drive.br(List.tail(&1, String, as))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    fz.drive.go(as)
