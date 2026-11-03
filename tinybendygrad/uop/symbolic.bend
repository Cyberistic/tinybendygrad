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
#   5  43      fold  fold_add_divmod_recombine  MISSING. This line said PORTED and there is
#                                             NO `def fold_add_divmod_recombine`: the census
#                                             lists it MISSING and `symclosure-gate` counts it
#                                             among `bodies.absent`. MEASURED 2026-11-03.
#   6  63-70   data  invalid_pat/gate/bare_const/casted_const/const_arg  PORTED
#   7  72      fold  lift_reduce_gate    MISSING, AND THE STATED REASON WAS FALSE. It said
#                                             "DEFERRED `UOp.ranges`", and `UOp.ranges` IS
#                                             PORTED (`fold.bend:5271`, with the `rg_self` row
#                                             that makes the prepend visible). THE TWO REAL
#                                             BLOCKERS, MEASURED 2026-11-03:
#                                               1. `UOp.uprod` -- elementwise.py:41,
#                                                  `reduce(and_ if dtype is bool else mul,
#                                                   uops, self)`. ABSENT.
#                                               2. ~~`c.ranges` needs an `RTable` BUILT INSIDE A
#                                                  RULE BODY~~ -- **THIS WAS FALSE AND THE
#                                                  MEASUREMENT THAT REFUTED IT IS ONE GREP:
#                                                  `fold.bend:5293` `def ranged(+ar: O.Arena)
#                                                  -> Ranged` IS the builder**, and
#                                                  `Ranged.rt` hands back the `RTable`.
#                                                  `fold.bend:5589` already uses it that way
#                                                  in its own rows. SO `c.ranges` IS REACHABLE
#                                                  FROM A RULE BODY AND `:90` HAS **NO
#                                                  REMAINING BLOCKER** -- `uprod` landed last
#                                                  turn and the table was never missing.
#   8  79-102  table pm_data_invalid      13 of 14  (rule 6 is #7)
#   9  104-108 table pm_remove_invalid    2 of 2
#  10  113     fold  fold_const_where     MISSING. This line said `PORTED` and named line
#                                            110, and BOTH WERE WRONG: `fold_const_where` is
#                                            at 113 (`110` is `pm_remove_invalid`'s first
#                                            rule) and no `def fold_const_where` exists in
#                                            this file -- three mentions, all comments. The
#                                            ONE rule that calls it, `symbolic.py:202`, is
#                                            MISSING in `gates/symrules.rows` too, so the
#                                            absence is not hidden by an inlining.
#  11  115-199 table symbolic_simple      23 of 47 PORTED. The 23 are every rule
#                                            whose substrate need is `alu`, `where`,
#                                            `const_like`, a `U32` bit pattern,
#                                            or a PERMUTED src list -- and "a
#                                            permuted src list" was the wall ten of
#                                            them were deferred behind, and it is
#                                            `Sw`.
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
#  23  450-475 table sym                   3 of 5 reciprocal rules PORTED
#                                            (`sym_462` at :463 `reciprocal`,
#                                            `sym_463` at :464 `reciprocal`,
#                                            `sym_464` at :465 `reciprocal`) --
#                                            the three `1-d` ones and the
#                                            store/load four are not
#
# WHAT THE LAST PASS FOUND, and two of the three are NOT walls.
#   * `UPat.alu` (ops.py:608 symbol=alu) hands a COMMUTATIVE op a LIST src, and a list is
#     every permutation (ops.py:1417). So a `CMPNE`, `AND`, `OR` or `MUL` pattern
#     arrives with its two captured names on either side, and the question a rule
#     has to answer is "which src is the CONST" and NOT "src[0]". `Sw` is that
#     question and SIX rules share it. Every `early_reject` in the table was read
#     out of CPython's own `UPat.early_reject` for the pattern at that line, not
#     derived by reading ops.py.
#   * A rule body that MINTS must not re-read `sy_ar(x)`: the fold's arena is stale
#     the moment the first node is interned into it, so the second node lands on
#     the slot the first one took and the answer names a node the rule did not
#     build. `mint_*` is the threaded answer and every minting rule below uses it.
#     `sym_93` and `sym_462` re-read `sy_ar(x)` and are the two rules in this file
#     whose answer index is therefore NOT gated -- stated here rather than left.
#   * `dtypes.ints` is EIGHT concrete widths, not four. The dtype-set helpers here
#     answered SIX and FIVE, which is an UNDER-approximation: a rule gated on one
#     skips a node Python rewrites, silently. `ints_n`/`intish_n`/`intweak_n` are
#     the rows and the oracle is CPython's own `len(dtypes.ints)`.
#
# THE THREE WALLS, measured against the substrate rather than guessed.
#
# 1. `exec_alu` OVER A CLOSED ALU TREE: YES, for `U32` AND `F32`, and the overflow
#    and sign semantics are RIGHT for the 32-bit widths. `U32.add/sub/mul` wrap mod
#    2^32, which IS int32/uint32 wrap; `H.asr` supplies the arithmetic shift `>>`
#    needs and Bend does not have; and the zero-divisor reading agrees because
#    `U32.div(a,0) = 0` is the number Python's `floordiv` is given by tinygrad/helpers.py:77.
#    WHAT IT CANNOT DO, and this is a wall rather than a choice:
#      a. weakint is MATHEMATICAL in tinygrad ("ints stay mathematical past the
#         fold", symbolic.py:29 -- upstream's comment names `mathematical`) and the
#         honest 64-bit carrier is `H.I64`.
#         `helpers.bend` has `i64_add`, `i64_sub`, `i64_cmp` and NOT `i64_mul`,
#         `i64_div` or `i64_mod`, so a weakint result outside the int32 range
#         cannot be computed here. `exec_alu` answers `None{}` for it, which is
#         Python's "the fold does not apply" -- the node is left alone. A NEGATIVE
#         const is refused by the same lane for a second reason, and it is named
#         with its measurement at `exec_alu.pick`.
#      b. `truncate` (tinygrad/dtype.py:289) is
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
# 3. `graph_rewrite` (ops.py:1886 symbol=graph_rewrite) IS NOT THIS FILE and is not ported. What IS
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
# `early_reject` IS A NECESSARY CONDITION, not a veto: ops.py:1604 is
# `if not early_reject.issubset(ler): continue`, so the rule FIRES when the op
# set IS a subset of the node's src ops. It is built from the op of the
# pattern's FIRST src and only when that src is a SINGLE-op UPat
# (ops.py:1467-1470 -- upstream builds `early_reject` there), and `O.pm_early` is
# ops.bend's own subset test over a
# `ler` that folds EVERY src. `rej` in the gate counts the entries whose reject
# set is non-empty, and that count is the only place a MISSPELLED reject set shows
# up at all.
#
# THE NAME-REBIND RULE. A pattern that binds one name twice WITHIN A SINGLE SRC
# TUPLE is the `mixin/gradient.py:101` shape: bound to two different nodes, and
# the rule only matches when they are the SAME node. Without the identity check
# the rule matches strictly more nodes than intended, and it typechecks. FOUR are
# here and all FOUR are LOAD-BEARING:
#     symbolic.py:126  (x ^ y) ^ y      -- `y` twice, the rule is (x^y)^y -> x
#     symbolic.py:127  (x % y) % y      -- `y` twice, the rule is (x%y)%y -> x%y
#     symbolic.py:462  (x * x).recip()  -- `x` twice, `sym_462`, upstream's `reciprocal` rule
#     symbolic.py:463  (x*x*x).recip()  -- `x` THREE times, so TWO compares
# The first TWO share one shape, so they share one def: `p_rebind2` is "`op` over
# `op` over two srcs whose src[1] is the SAME node both times", and `sym_126`/
# `sym_127` are that def at two ops. `rebind`/`rebind0`, `xorb`/`xorb0`,
# `modb`/`modb0` and `recip3`/`recip3x` are the two-sided rows that say so, and a
# POSITIVE rebind row is worth nothing on its own -- only the pair sees the check
# go.
#
# THE `UPat.any` CASE IS SAFE AND STAYS A DISJUNCTION. symbolic.py:183 -- upstream's
# `UPat.any` IS the disjunction, and it binds `c` in two ALTERNATIVES, and
# the port's `is_any` copies the store per alternative so they
# never meet, and adding an identity check there would turn a disjunction into a
# conjunction and drop the bare `CONST(Invalid)` lane.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F
import ./render.bend as R
import ./../dtype.bend as D
import ./weak.bend as W
import ./movement.bend as M

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
# `GroupOp.Unary` -- NINE ops, and `GroupOp.Unary|{Ops.CAST, Ops.BITCAST}` IS
# those nine: the `|` is a set union and CAST and BITCAST are already in
# Unary.  Upstream's `:83` and `:84` therefore fire on ALL NINE, and a two-op
# set is a NARROWING that makes the port skip nodes upstream rewrites.
def OP_UNARY() -> List<&2, O.Op>:
  [O.OpsCAST{}, O.OpsBITCAST{}, O.OpsNEG{}, O.OpsRECIPROCAL{}, O.OpsEXP2{},
   O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsTRUNC{}]


def OP_CMP() -> List<&2, O.Op>: [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}]

def OP_SELF() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsXOR{}, O.OpsOR{}]

def OP_SHIFTS() -> List<&2, O.Op>: [O.OpsSHL{}, O.OpsSHR{}]

# `GroupOp.ALU - {Ops.THREEFRY}` -- TWENTY-SEVEN ops, and it is the op set of `symbolic.py:158`,
# `:159` and `:161`. THE PORT'S BODY FOR :161 ALREADY TESTS IT (`sym_161.pat` asks
# `O.GroupOp.alu(op) && op != THREEFRY`) AND THE TABLE ENTRY LISTED ONE OP -- so the rule was
# correct and UNREACHABLE for twenty-six of its twenty-seven inputs. A NARROW row is exactly
# that shape: the table says PORTED and the rule fires on a twenty-seventh of upstream's nodes.
# `GroupOp.Binary` -- NINETEEN ops, and it is the op set of `symbolic.py:87` and `:88`, the two
# rules that lift an `invalid_gate` out of a binary operand. Spelled out because `PMEntry.ops` is
# a LIST and `O.GroupOp.binary` is a PREDICATE -- the same reason `OP_ALU_NT` is.
def OP_BINARY() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsMAX{}, O.OpsMUL{},
   O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsXOR{}]

def OP_ALU_NT() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsLOG2{},
   O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{},
   O.OpsRECIPROCAL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSUB{},
   O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}]

# `up if bool(x) else None` -- the shape of most of symbolic.py's rule bodies.
# A `match` may not scrutinise a computed value, so the condition crosses a def
# boundary as a parameter.
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
# which is why `(X < c).ne(True)` and `UPat.const` see one value and not two
# nodes. Both arms are here; Python's `assert` on the third is `None{}`.
def sy_val1(a: O.Arg, op: O.Op) -> Maybe<&2, O.Const>:
  match a op:
    case O.APy{v} O.OpsCONST{}: Some{v}
    case _ _: None{}

# `UOp.val`'s CAST arm is `return self.src[0].val` (ops.py:252-257), NOT the cast's own
# arg: a CAST's arg is its TARGET DTYPE, so reading it answered `None{}` for every
# `CAST(CONST(v))` -- and `fold_const_alu` then folded at nothing and answered 0.
# MEASURED 2026-11-03: `(add (cast:i32 c1) (cast:i32 c2))` answered `(cast:i32 c0)` where
# CPython answers `(cast:i32 c3)`.
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
# **THE ARENA-THREADING TRAP, LIVE AND UNTIL NOW UNREACHED.** `UOp.const` and `sy_cast` both
# MINT, and this def keeps only `Found.i` while dropping `Found.ar` -- then hands the index to
# `sy_cast` with the OLD arena. The answer is an index into an arena nobody holds.
#
# IT WAS INVISIBLE BECAUSE THE DEF HAD NO CALLER. `fold_const_where` (rule :202, wired last
# turn) is the first, and the probe that was supposed to CONFIRM the cast branch instead found
# `fcw=node=7 op=NOOP dt=void` on a graph whose last node is 7 -- the first free slot read as
# a node. FIVE OTHER DEFS in this session carried the same shape (`variables`, `unbound`,
# `wr.rebuild.one`, `ca_ans_ar`, the `nv` fixture); this is the sixth.
#
# THE FIX IS A REFUSAL AND NOT A SIGNATURE CHANGE: `sym_table` answers `Maybe<&1, U32>`, an
# index and no arena, so a MINTING rule cannot be expressed there at all -- the port says so in
# `ops.bend` about `pm_rewrite_m`. So this def answers `None{}` for any index it cannot vouch
# for, which leaves the node alone instead of returning garbage. A rule that declines is a
# NARROW the census can show; a rule that answers a stale index is a wrong graph.
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

# `exec_alu` -- ops.py:1433, and the answer is two lanes, `U32` and `F32`, with
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

# THE MAX, AND IT IS NOT THE MIN. The float lane's `f32_max` (below) is
# `Bool.pick(F32, F32.is_lt(x, y), y, x)` -- "y if x < y else x", which is max.
# THIS ONE HAD ITS COMPARISON'S OPERANDS THE OTHER WAY ROUND, so it answered
# "y if y < x else x", WHICH IS min(x, y). MEASURED 2026-10-25 (the executor's
# `max` lane, `tinybendygrad/runtime/ops_python.bend`): `i32_max(3, 7)` and
# `i32_max(7, 3)` BOTH ANSWERED 3, and a `max(axis=0)` over a 4x4 int32 tensor
# ANSWERED THE FIRST ROW. UPSTREAM'S OWN TABLE IS `python_alu[Ops.MAX] = max`
# (tinygrad/uop/ops.py, and `PythonRenderer.code_for_op` points at that table),
# SO THE ORACLE SAYS `max` AND THE PORT WAS WRONG.
def i32_max(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, i32_lt(uns, x, y), y, x)

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

# `python_alu`'s COMPARISONS (ops.py:1416-1417) are `operator.lt`, `operator.eq` and
# `operator.ne`, so CMPNE IS **NOT EQUAL** and NOT "equal" -- and this line said
# `U32.is_eq`, WHICH IS **EQUAL**. MEASURED 2026-10-26 (the executor's
# "vector-store lane" family): `SY.exec_alu_i32(False, OpsCMPNE, I3{2, 0, 1, 0})`
# ANSWERED `CBool(0)` WHERE CPython's `exec_alu(Ops.CMPNE, dtypes.i32, [0, 1])`
# ANSWERS `True` (`operator.ne(0, 1)`). THE FLOAT LANE AT `exec_alu_f32.cmp` WAS
# RIGHT (`F32.is_ne`) AND THIS ONE WAS NOT, SO THE TWO LANES DISAGREED WITH EACH
# OTHER ON THE SAME OP.
#
# WHY IT MATTERS: `x != y` IS THE `abs` LOWERING'S SECOND HALF -- tinygrad spells
# `abs` AS `WHERE(x < 0, -x, x)` AND THAT WHERE'S CONDITION IS A CMPNE -- SO THE
# WRONG COMPARISON MADE **EVERY** `abs` IN AN INTEGER KERNEL WRONG, AND WITH IT
# EVERY `sqrt`/`log2`/`exp2`/`recip`/`shl`/`shr`/`cmod` OF AN INTEGER TENSOR.
# MEASURED: 20 of the 29 pinned rows in `gates/ops_python_exec-pins.rows`.
def exec_alu_i32.cmp(+uns: Bool, op: O.Op, o: I3) -> Maybe<&1, O.Const>:
  match op o:
    case O.OpsCMPLT{} I3{2, +a, +b, _}: Some{sy_bool_c(i32_lt(uns, a, b))}
    case O.OpsCMPEQ{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}
    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_ne(a, b))}
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
#
# **THE ARMS WERE THE OTHER WAY ROUND.** `Bool.pick(T, cond, then, else)` PICKS
# `then` WHEN `cond` HOLDS, SO `y if x else z` IS `pick(cond, y, z)` -- AND THIS
# LINE SAID `pick(cond, c, b)`, WHICH IS `z if x else y`. MEASURED 2026-10-26:
# `SY.exec_alu_f32(OpsWHERE, 3, 0.0, -1.0, 1.0)` ANSWERED `CFloat(-1.0)` WHERE
# CPython's `exec_alu(Ops.WHERE, dtypes.f32, [0.0, -1.0, 1.0])` ANSWERS `1.0`.
#
# WHY IT MATTERS: `abs` IS `WHERE(x < 0, -x, x)` AND `abs` IS THE FIRST HALF OF
# EVERY `sqrt`/`log2`/`exp2`/`recip`/`shl`/`shr`/`cmod` OF A FLOAT TENSOR, SO THE
# SWAPPED ARMS MADE EVERY ONE OF THEM READ A ZERO AND ANSWER 0.0. MEASURED: the
# executor's `f32.sqrt.0` ANSWERED `[0, 0, 0, 0, <unchanged>]` WHERE UPSTREAM
# ANSWERS `[1.0, 1.4142135, 1.7320508, 2.0, <unchanged>]` -- 7 of the 29 pinned
# rows in `gates/ops_python_exec-pins.rows`.
#
# THE INTEGER LANE AT `exec_alu_i32.where` WAS RIGHT, AND IT IS RIGHT **BECAUSE IT
# INVERTS THE CONDITION INSTEAD**: IT PICKS `c` WHEN `U32.is_zero(a)`, WHICH IS
# "z IF x IS FALSY ELSE y" -- THE SAME SENTENCE. THIS LANE PICKS THE CONDITION
# ITSELF, SO ITS ARMS ARE THE PLAIN ONES.
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
# `None{}` where CPython's `exec_alu(Ops.MUL, dtypes.i32, [6, 7])` answers `42`,
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

# `exec_alu` -- ops.py:1433, the scalar spine in Python's order, one def per
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
# `p_invalid` CALLS `sy_is_invalid_const` rather than re-spelling it. The two were
# the same expression under two names -- `sy_is_const` IS `sy_is_op(x, u, Ops.CONST{})`
# by its own def -- and the pattern layer carried the copy while the named helper sat
# unread. `grep -c sy_is_invalid_const` answered 1 (its own `def` line) and the whole
# class-(h) sweep found it; `p_invalid` is the only call site that wanted it.
def p_invalid(+x: F.Folded, +u: U32) -> Bool: sy_is_invalid_const(x, u)

# `invalid_gate` -- `UPat.var("cond").where(UPat.var("x"), invalid_pat)`, which is
# `WHERE(cond, x, CONST(Invalid))` and three srcs.
def p_gate(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), sy_is_invalid(x, sy_src2(x, u)))

# `UPat.cvar("gate")` IS `UPat(Ops.CONST)` (`ops.py:1492`, the one definition of `cvar`) and the
# port was missing the clause: `fold_const_where` fired on ANY `where(gate, c0, c1)` and answered a
# BRANCH. MEASURED 2026-11-03: `(where xb x y)` answered `y` where CPython answers `norewrite` --
# A PATTERN CLAUSE THAT IS NOT A TEST IS THE ONE SHAPE THE BODY CANNOT SEE, because the body reads
# `gate.val` and only a CONST has one.
def p_cgate(+x: F.Folded, +u: U32) -> Bool: sy_is_const(x, sy_src0(x, u))

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

# THE DTYPE SETS. `dtypes.ints` is a Python TUPLE (tinygrad/dtype.py:159, `uints + sints`)
# and the three places symbolic.py spells it are three different tuples, so it is
# three LISTS here and not one predicate: `dtypes.ints` is EIGHT concrete widths,
# `ints + (bool, weakint)` is TEN and `ints + (weakint,)` is NINE. The previous
# spelling in this file was SIX and FIVE, which is an UNDER-approximation: a rule
# gated on it SKIPS a node Python rewrites, and the skip is silent.
def DTS_INTS() -> List<&2, S.Dt>:
  [S.uint8(), S.uint16(), S.uint32(), S.uint64(), S.int8(), S.int16(), S.int32(), S.int64()]

# `dtypes.sints` -- the four SIGNED ints, which is `:316`'s cast target.
def DTS_SINTS() -> List<&2, S.Dt>: [S.int8(), S.int16(), S.int32(), S.int64()]



def DTS_INTISH() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, DTS_INTS(), [S.boolean()]), [S.weakint()])

def DTS_INTWEAK() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, DTS_INTS(), [S.weakint()])

# MEMBERSHIP IN A DTYPE LIST. `ops.bend` has `op_in` and no `dt_in`, and
# `fold.bend`'s `least_upper_dtypes` is a MEET rather than a search, so this is
# the one place a dtype set is walked.
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
# need it as a PATTERN CONSTRAINT, which is a read of the `arg` and no fold.
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

# THE FAITHFUL `U32` BIT PATTERN OF A CONST, and `None{}` for a value that has
# none. `i64_fits_i32` is the int32 test `exec_alu`'s lane selector already uses,
# so the two mask rules below and the integer lane agree on what "this constant
# fits" means. A CONST outside the int32 range answers `None{}` -- a fold that
# does not apply -- and NOT a wrapped answer, because a wrapped one is a wrong
# value. The two rules that need it are 64-BIT tests in Python (`:144` masks to
# `-1`, which is 64 ones) and are stated on the 32-bit lane here, which is exact
# for every mask a weak CONST of int32 range can carry.
# THE INT32 RANGE TEST, and it is NOT `i64_fits_i32`. That predicate is
# `not i64_big` and `i64_big` is TRUE for every NEGATIVE -- `exec_alu.pick`'s own
# comment says so -- so it answers "does not fit" for `-16`, which IS an int32, and
# `const_i32` would refuse every negative mask. This one is the actual
# `dtypes.int32` interval, and `const_i32`'s claim is that the `U32` BIT PATTERN is
# faithful for every value it accepts.
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

# `-1` AS A `U32`, which is the right-hand side of both mask tests. A LITERAL and
# not a `neg`, so the reader cannot see a sign where there is none.
def ALL_ONES() -> U32: 4294967295

# `c.val == 0` / `== 1` / NEITHER, as ONE Nat, which is the three-way symbolic.py:136
# branches on. Python's `==` on a `PyConst` crosses bool/int/float -- `False == 0`
# and `True == 1` -- so the bool arm is the SAME reading as the int one and not a
# special case. `0` is zero, `1` is one, `2` is neither, and `Invalid` is neither
# because `InvalidType` is not a number and its `==` is object identity.
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
# ---- THE ARENA-THREADED MINTS, and they are the fix for a trap this file's own
# ---- header names and that every rule below walks into. A rule body must NOT
# ---- re-read `sy_ar(x)`: the fold's arena is STALE the moment the first node is
# ---- interned into it, so a second `O.UOp.new(Found.ar(f), ...)` puts the next
# ---- node on the slot the first one took and the answer names a node that is not
# ---- the one the rule built. `Found` is ops.bend's arena-and-index record and is
# ---- `Data`, so a CHAIN of them carries the arena with no second parameter list --
# ---- the same move `weak.bend`'s `Walk` makes and the same trap `f_bin` states for
# ---- the fixtures. `sym_93`/`sym_462` re-read `sy_ar(x)` and are NOT gated on their
# ---- answer index; everything here is.
def mint_ar(ar: O.Arena) -> O.Found: O.Found{ar, 0}

def mint_bin(+f: O.Found, op: O.Op, a: U32, b: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [a, b])

def mint_un(+f: O.Found, op: O.Op, a: U32) -> O.Found:
  O.UOp.alu(O.Found.ar(f), op, [a])

def mint_cast(+f: O.Found, a: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsCAST{}, [a], O.ADt{dt}, O.TNone{})

# `UOp.const(v, dt)` at an explicit arena, and `O.UOp.const` has already interned
# the BARE const into `f`'s arena -- so the CAST on top reads `Found.ar(f)` AFTER
# that intern and lands on the right slot.
def mint_cst(needs: Bool, +f: O.Found, dt: S.Dt) -> O.Found:
  match needs:
    case True{}: mint_cast(f, O.Found.i(f), dt)
    case False{}: f

def mint_const(+f: O.Found, v: O.Const, +dt: S.Dt) -> O.Found:
  mint_cst(sy_needs_cast(dt, v), f, dt)

# `x.replace(src=...)` at an explicit arena, with the op/arg/tag READ OUT OF THE
# FOLD because they are properties of the ORIGINAL node and not of the grown one.
def mint_replace(+f: O.Found, +x: F.Folded, +u: U32, src: List<&2, U32>) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.Arena.op(sy_ar(x), u), src, O.Arena.arg(sy_ar(x), u), O.Arena.tag(sy_ar(x), u))

# `x.logical_not()` at an explicit arena: `CMPNE(x, CONST(True))`, and the CONST is
# interned first because it is an argument.
def mint_not(+f: O.Found, v: U32) -> O.Found:
  +c = O.UOp.const(O.Found.ar(f), O.CBool{True{}})
  mint_bin(c, O.OpsCMPNE{}, v, O.Found.i(c))

# `x.reciprocal()` at an explicit arena.
def mint_recip(+f: O.Found, v: U32) -> O.Found: mint_un(f, O.OpsRECIPROCAL{}, v)

# symbolic.py:462  ((UPat.var("x") * UPat.var("x")).reciprocal(),
#                     lambda x: x.reciprocal()*x.reciprocal())   # 1/(x*x) -> (1/x)*(1/x)
# `**` IS NOT REBIND HERE: `UPat.var("x") * UPat.var("x")` is `UPat.__mul__`, a
# DIFFERENT var per operand -- Python's UPat cache interns by NAME, so the two are
# the same pattern object and the compiled form's STORE OVERWRITES. `upat.py:
# 100-105` emits the identity compare for a duplicate store, so the honest port is
# the IDENTITY CHECK again; it is STRICTER than Python here (see the TODO block).
def sym_462.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsRECIPROCAL{}), sy_nsrc_is(x, u, 1)),
    Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsMUL{}), Bool.and(sy_nsrc_is(x, sy_src0(x, u), 2),
      p_same(sy_src0(x, sy_src0(x, u)), sy_src1(x, sy_src0(x, u))))))

def sym_462.put(+f: O.Found, v: U32) -> O.Found:
  +r = mint_recip(f, v)
  mint_bin(r, O.OpsMUL{}, O.Found.i(r), O.Found.i(r))

def sym_462.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_462.put(mint_ar(sy_ar(x)), sy_src0(x, sy_src0(x, u)))}
    case _     : None{}

def sym_462(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_462.hit(sym_462.pat(x, u), x, u)

# symbolic.py:439-442 -- `# this is symbolic 2.0` -- the SINK cleanup, upstream's
# `pm_clean_up_group_sink`. Upstream deleted the GROUP half of the root set with
# the op, so the root is `Ops.SINK` ALONE.
#   lambda root: UOp(root.op, src=tuple(flatten(x.src if x.op in
#     REMOVE_FROM_SINK_LIKE else (x,) for x in root.src)), arg=root.arg)
# `REMOVE_FROM_SINK_LIKE = {NOOP, STACK, SINK, AFTER}` -- GROUP is GONE and AFTER is
# IN, which is a REPLACEMENT rather than a deletion -- and `flatten` is a fold
# over a list of lists -- which `helpers.bend`'s `flatten_u32` is.
def p_sink_like(x: F.Folded, s: U32) -> Bool:
  sy_op_in(x, s, [O.OpsNOOP{}, O.OpsSTACK{}, O.OpsSINK{}, O.OpsAFTER{}])

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
# reason that turned out NOT to be a wall. They are grouped by the substrate fact
# each group needed, because that is the order the checks run in, and a group
# heading names the fact rather than the rule.
#
# ---- THE PERMUTED-SRC FACT, and the one record six rules share ----
# `UPat.alu` (ops.py:1543) hands a COMMUTATIVE op a LIST `src`, and a list is
# every permutation (ops.py:1464). `GroupOp.Commutative` is `{MUL, MAX, CMPNE,
# CMPEQ, XOR, OR, AND, ADD}`, so six of the rules below -- `:135`'s `!=`,
# `:144`/`:146`'s `&`, `:192`/`:193`'s `|`, `:465`'s `*` -- arrive with their two
# captured names on either side. `upat.py:151` tries the FIRST permutation first,
# so "src[1] matches the test" WINS when both do, and that is the `Bool.pick` order
# in `sw.a`. `a` is the src that matched and `b` the other, and each rule reads
# its own two names off them.
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
# the rules below build, each at the arena its caller threads. They are the `Found` twins of
# `sy_neg`, `sy_const_like`, `sp_false` and `sy_where`, which answer a bare INDEX into an
# arena they grow and then throw away.
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



# `invalid_pat.broadcast()` IS A STACK WHOSE SRCS ARE ALL INVALID, and the port tested
# only `src[0]`. MEASURED 2026-11-03: `(stack bad x)` answered `bad` where CPython answers
# `norewrite` -- a rule that fires on a stack it must not touch.
def all_invalid.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: all_invalid.go(t, x, Bool.and(acc, p_invalid(x, s)))

def sym_82.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTACK{}), sy_nsrc_ge(x, u, 1)),
    all_invalid.go(sy_srcs(x, u), x, True{}))

def sym_82(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_82.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:81  (UPat(GroupOp.Unary|{CAST, BITCAST}, src=(invalid_pat,)), lambda i: i)
def sym_83.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_UNARY()), sy_nsrc_is(x, u, 1)), p_invalid(x, sy_src0(x, u)))

def sym_83(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_83.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:90  (invalid_pat.where(UPat(), UPat()), lambda i: i)
# `WHERE(cond, x, CONST(Invalid))` with an Invalid CONDITION: an Invalid condition
# poisons the whole where, so the answer is the Invalid itself.
def sym_92.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_invalid(x, sy_src0(x, u)))

def sym_92(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri(sym_92.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:91  (invalid_gate.where(UPat.var("a"), UPat.var("b")),
#                   lambda cond,x,i,a,b: cond.where(x.where(a,b), i))
# The gate moves INSIDE: `WHERE(WHERE(c,x,i), a, b)` -> `WHERE(c, WHERE(x,a,b), i)`.
def sym_93.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)), p_where_gate(x, u, 0))

def sym_93.gate(x: F.Folded, u: U32) -> U32: sy_src0(x, u)

def sym_93.gx(x: F.Folded, u: U32) -> U32: sy_src1(x, u)

def sym_93.gi(x: F.Folded, u: U32) -> U32: sy_src2(x, u)

def sym_93.pick(cond: Bool, t: U32, f: U32) -> U32: Bool.pick(U32, cond, t, f)

# TWO WHERES AND BOTH ARE NEW, so this rule is Found-family: `cond.where(x.where(a,b), i)`
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
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)), p_index_bad_or_cast(x, sy_src0(x, u)))

def sym_101.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(hit, Some{sy_noop(sy_ar(x))})

def sym_101(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sym_101.hit(sym_101.pat(x, u), x, u)

# symbolic.py:100-101  (UPat(Ops.LOAD, src=(UPat(Ops.INDEX, ...).or_casted(),),
#                          allow_any_len=True, name="x"),
#                       lambda x,i: x.src[1] if len(x.src) > 1 else x.const_like(0))
def sym_103.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsLOAD{}), sy_nsrc_ge(x, u, 1)), p_index_bad_or_cast(x, sy_src0(x, u)))

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
#                     lambda x: x)   # x+0 / x^0 / x|0 -> x
# THE LIST `src` IS A PERMUTATION in Python (ops.py:1464), so the rule fires with
# the const on either side; `p_nc` is the index of the src that is not the CONST.
def sym_120.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_SELF()), sy_nsrc_is(x, u, 2)),
    Bool.or(p_is_const_0(x, sy_src0(x, u)), p_is_const_0(x, sy_src1(x, u))))

# `c0` says src[0] is the CONST, so the answer is src[1]; the two spellings of
# `Bool.pick` and this call site are the whole of the PERMUTATION Python gets
# from `src=[...]`.
def sym_120.pick(c0: Bool, a: U32, b: U32) -> Maybe<&1, U32>: Some{Bool.pick(U32, c0, a, b)}

def sym_120(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_120.pat(x, u), sym_120.pick(p_is_const_0(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u)))

# symbolic.py:120  (UPat.var("x") // UPat.var("x"), lambda x: x.const_like(1))
# x//x -> 1. **`x` IS BOUND TWICE IN ONE SRC TUPLE**, so this rule carries the
# IDENTITY CHECK and it is LOAD-BEARING: without it the rule also fires on
# `x // y` for two different nodes, and that is a wrong rewrite.
def sym_123.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_123.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(hit, mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(1)}))

def sym_123(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_123.hit(sym_123.pat(x, u), x, u)

# THE REBIND SHAPE, ONCE. `sym_126` (symbolic.py:123, `(x^y)^y`) and `sym_127`
# (symbolic.py:124, `(x%y)%y`) are the same shape with a different op: `op` over
# `op` over two srcs, where the OUTER's src[1] and the INNER's src[1] must be the
# SAME node because the name is bound twice within one src spine.
# `mixin/upat.py:100-105` emits that identity compare for a duplicate store and
# it is LOAD-BEARING in both rules -- without it each rule also fires on two
# unrelated nodes, which is a wrong rewrite that typechecks. The inner node is
# bound to `+m` because the shape names it three times.
def p_rebind2(+x: F.Folded, +op: O.Op, +u: U32) -> Bool:
  +m = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, op), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, m, op), Bool.and(sy_nsrc_is(x, m, 2), p_same(sy_src1(x, u), sy_src1(x, m)))))

# symbolic.py:123  ((UPat.var("x") ^ UPat.var("y")) ^ UPat.var("y"), lambda x,y: x)
# (x^y)^y -> x. THE REBIND OF THE HEADER, and the answer is the inner node's
# src[0] -- `x`, not the inner node.
def sym_126.pat(+x: F.Folded, +u: U32) -> Bool: p_rebind2(x, O.OpsXOR{}, u)

def sym_126(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_126.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})

def p_all_bare.go(srcs: List<&2, U32>, +x: F.Folded, acc: Bool) -> Bool:
  match srcs:
    case Nil{}: acc
    case s <> t: p_all_bare.go(t, x, Bool.and(acc, p_bare_const(x, s)))

def p_all_bare(+x: F.Folded, u: U32) -> Bool: p_all_bare.go(sy_srcs(x, u), x, True{})

# symbolic.py:158  (UPat(GroupOp.ALU-{THREEFRY}, src=bare_const, name="a"),
#                     fold_const_alu)
# "one rule per spelling: bare has no width, a pair evaluates at its stated
# width". `src=bare_const` is an `itertools.repeat`, so EVERY src is a bare const.
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
# `:155`/`:157` read it out of a `CONST` node, so the `Maybe` crosses the boundary and the
# truncation happens inside.
def mint_const_v(m: Maybe<&2, O.Const>, +f: O.Found, +dt: S.Dt) -> Maybe<&1, O.Found>:
  match m:
    case Some{v}: mint_const_like.go(sy_trunc(dt, v), f, dt)
    case None{}: None{}

# symbolic.py:155  (UPat(Ops.CAST, dtypes.all, name="root", src=(UPat.cvar("c"),)),
#                     lambda root, c: root.const_like(c.val))
# A CAST OF A CONST IS THAT CONST AT THE CAST'S DTYPE -- the node DISAPPEARS, which is why the
# answer is minted: `root.const_like` names the cast's dtype and not the constant's.
def sym_155.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)), sy_is_const(x, sy_src0(x, u)))

def sym_155(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_155.pat(x, u), mint_const_v(sy_val(x, sy_src0(x, u)), mint_ar(sy_ar(x)), sy_dt1(x, u)))

# symbolic.py:157  (UPat(Ops.CAST, dtypes.all, name="root",
#                    src=(UPat(Ops.CAST, dtypes.all, src=(UPat(Ops.CONST, name="c"),)),)),
#                    lambda root,c: root.const_like(c.val))
# THE COMMITTED PAIR: two casts in a row collapse to the OUTERMOST dtype in one step.
def sym_157.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsCAST{}),
      Bool.and(sy_nsrc_is(x, sy_src0(x, u), 1), sy_is_const(x, sy_src0(x, sy_src0(x, u))))))

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
# bare var (`:144`, `:146`, `:465`), `p_shl` for the `(x<<32) | CAST` pair
# (`:192`, `:193`), `p_cast` for the CAST against a cvar (`:135`).
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
# worth a fold round-trip: `p_cast1` reads the `arg` directly.
def p_cast1(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsCAST{}), sy_nsrc_is(x, s, 1))

def p_cast_to(+x: F.Folded, +s: U32, ds: List<&2, S.Dt>) -> Bool:
  Bool.and(p_cast1(x, s), p_dt_in(ds, sy_arg_dt(x, s)))

def p_cast_at(+x: F.Folded, +s: U32, want: S.Dt) -> Bool:
  Bool.and(p_cast1(x, s), p_dt1(sy_arg_dt(x, s), want))

# ---- the SECOND rebind, and the shape it shares with `sym_126` ----
# symbolic.py:124  ((UPat.var() % UPat.var("y")).named("base") % UPat.var("y"),
#                     lambda base,y: base)        # (x%y)%y -> x%y
# `FLOORMOD` is NOT commutative, so there is ONE permutation and the shape is
# `p_rebind2`'s verbatim. `base` is `.named("base")` on the INNER node, so the
# answer is that node -- `src[0]` here and NOT `src[0]`'s src[0] as in `sym_126`.
def sym_127.pat(+x: F.Folded, +u: U32) -> Bool: p_rebind2(x, O.OpsFLOORMOD{}, u)

def sym_127(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_127.pat(x, u), Some{sy_src0(x, u)})

# ---- `CAST(bool -> ints+weakint) != cvar` and its three-way body ----
# symbolic.py:135-136  (UPat.var("x", dtype=dtypes.bool).cast(dtypes.ints+(dtypes.weakint,))
#                         != UPat.cvar("c"),
#   lambda x,c: x if c.val == 0 else x.logical_not() if c.val == 1 else x.const_like(True))
# `!=` IS commutative, so the CAST is a `Sw`'s `a` and the cvar its `b`.
# `x.const_like(True)` is a BOOL const because `x`'s dtype is bool, and
# `x.logical_not()` is the `CMPNE(x, CONST(True))` this file already spells.
def sym_138.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), Bool.and(p_cast_to(x, Sw.a(p), DTS_INTWEAK()),
      sy_dt_is(x, sy_src0(x, Sw.a(p)), S.boolean()))))

# THE THREE ARMS AS INDICES, and each is ONE `Found` chain: `x`, then
# `CMPNE(x, CONST(True))` and then the bare `CONST(True)` -- the last because
# `x.const_like(True)` is at `x`'s own dtype, which is bool.
def sym_138.arm(+c3: U32, +b: U32, +f: O.Found) -> O.Found:
  Bool.pick(O.Found, U32.is_eq(c3, 0), O.Found{O.Found.ar(f), b},
    Bool.pick(O.Found, U32.is_eq(c3, 1), mint_not(f, b),
      mint_const(O.UOp.const(O.Found.ar(f), O.CBool{True{}}), O.CBool{True{}}, S.boolean())))

def sym_138.hit(hit: Bool, c3: U32, +p: Sw, +x: F.Folded) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_138.arm(c3, sy_src0(x, Sw.a(p)), mint_ar(sy_ar(x)))}
    case _: None{}

def sym_138(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_cast(x, u)
  sym_138.hit(sym_138.pat(x, u, p), sy_cval3(sy_val(x, Sw.b(p))), p, x)

# symbolic.py:137  (UPat.var("x", dtype=dtypes.ints+(dtypes.bool, dtypes.weakint)).trunc(),
#                     lambda x: x)                # x.trunc() -> x, ints only
# The TRUNC's OWN dtype is unconstrained -- `UPat(Ops.TRUNC, src=(x,))` states
# none -- so the guard is on the src alone and `early_reject` is EMPTY.
def sym_140.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsTRUNC{}), sy_nsrc_is(x, u, 1)), p_intish(x, sy_src0(x, u)))

def sym_140(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_140.pat(x, u), Some{sy_src0(x, u)})

# ---- the two MASK rules, and the ONE record they share ----
# symbolic.py:144-145  ((UPat.var("x") & UPat.cvar("mask")) >> UPat.cvar("k"),
#   lambda x,mask,k: x >> k.val if mask.val | ((1 << k.val) - 1) == -1 else None)
# symbolic.py:146-147  ((UPat.var("x") & UPat.cvar("mask")) // UPat.cvar("c"),
#   lambda x,mask,c: x // c.val if c.val > 0 and c.val & (c.val-1) == 0 and
#                          mask.val | (c.val-1) == -1 else None)
# Python's `-1` is 64 ones and both tests are 64-BIT. Here they are the int32 lane
# `const_i32` states, which is exact for every constant that HAS a `U32`; and the
# shift amount is held to `0 <= k <= 31`, because `U32.shln` saturates to 0 past 31
# where Python's `1 << 32` is `2**32`. `k > 31` is the ONLY place the two readings
# part company, so it answers "no rewrite" rather than a wrong shift.
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
# bits" cross as two parameters. `mc32` is `rm_108`'s move, hoisted because BOTH mask
# rules need it and neither owns it.
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
# OUTER's src[1] because neither `SHR` nor `FLOORDIV` permutes.
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
  mint_bin(c, O.OpsFLOORDIV{}, v, O.Found.i(c))

def sym_149.hit(gate: Bool, +c: Mc, v: U32, +x: F.Folded) -> Maybe<&1, O.Found>:
  match gate:
    case True{}: Some{sym_149.put(Mc.k(c), v, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_149(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = p_const(x, sy_src0(x, u))
  +c = mc32.of(sy_val(x, Sw.a(p)), sy_val(x, sy_src1(x, u)))
  sym_149.hit(Bool.and(p_mask(x, u, O.OpsFLOORDIV{}, p), sym_149.gate(c)), c, Sw.b(p), x)

# ---- the weak-src PROMOTION, and it is a two-src fold ----
# symbolic.py:160-162  (UPat(GroupOp.Binary-{Ops.THREEFRY}, src=[casted_const, bare_const], name="a"),
#   lambda a: a.replace(src=tuple(s.ccast(dt) if s.dtype in dtypes.weaks else s for s in a.src))
#             if (dt:=promo_dtype(a.src)) not in dtypes.weaks else None)
# `GroupOp.Binary` IS TWO SRCS -- `GroupOp.ternary` is WHERE and MULACC -- so the
# replace is a two-arm choice and NOT a general-arity fold. The op set is a list
# because `pdict` keys on it, and `ops.bend`'s `GroupOp.binary` has NINETEEN
# members of which THREEFRY is the excluded one. `early_reject` is EMPTY, because
# both captured sides are `UPat.any(...)` and an `is_any` pattern has no op of its
# own for ops.py:1478 to read.
def OP_BINARY_3F() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}]

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
# answers `None{}` at a SEALED dtype -- float16, bfloat16 and the four fp8s, whose
# `DType.const` is `dtype.bend`'s C-effect seam -- and this port REFUSES the
# rewrite there rather than committing an unrounded CONST. That is `weak.bend`'s
# `wk_blocked` policy applied to a rule that lives here, and `promo_sealed` is the
# row that states it.
# `sy_trunc` ON A `Maybe`, because the rebuild of a CONST at `dt` is `DType.const`
# and that is a C-effect seam at float16, bfloat16 and the four fp8s.
def trunc_m.of(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>: sy_trunc(dt, v)

def trunc_m(dt: S.Dt, m: Maybe<&2, O.Const>) -> Maybe<&1, O.Const>:
  match m:
    case Some{v}: trunc_m.of(dt, v)
    case _: None{}

# `UOp.ccast(dt)` AT AN ARENA, and it is `sy_ccast` with the fold's STALE arena
# replaced by the one the caller threads. A CONST is REBUILT at `dt` and everything
# else is CAST, and the rebuild is the arm that refuses at a sealed dtype.
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
# A STRONG SRC PASSED THROUGH, and it is a def so the record's field order is
# written once: `Found{ar, i}`.
def mint_keep(+f: O.Found, s: U32) -> O.Found: O.Found{O.Found.ar(f), s}

def sym_163.one(weak: Bool, v: Maybe<&2, O.Const>, is_const: Bool, s: U32, +f: O.Found, dt: S.Dt) -> Maybe<&1, O.Found>:
  match weak:
    case True{}: ccast_at(v, is_const, f, s, dt)
    case _: Some{mint_keep(f, s)}

def sym_163.at(+s: U32, +x: F.Folded, +f: O.Found, +dt: S.Dt) -> Maybe<&1, O.Found>:
  sym_163.one(dt_weak_of(sy_dt1(x, s)), sy_val(x, s), sy_is_const(x, s), s, f, dt)

# THE WHOLE REWRITE, and it is ONE def because the two srcs share an arena and a
# `Maybe` cannot carry one: src0 is committed first and its `Found` is the arena
# src1 is committed into. The nested `match` IS the sealed-dtype refusal -- either
# src unable to commit answers "no rewrite" rather than a wrong node.
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
#                      | UPat.var('y', dtypes.uint32).cast(dtypes.uint64)).cast(dtypes.uint32),
#                    lambda y: y)
# symbolic.py:193-194  (((UPat.var('x', dtypes.uint32).cast(dtypes.uint64)<<32)
#                      | UPat.var(None, dtypes.uint32).cast(dtypes.uint64))>>32,
#                    lambda x: x.cast(dtypes.uint64))
# `UPat.var(None, dtype)` is an UNNAMED var and it is still DTYPE-CONSTRAINED, so
# there is no disjunction about which src is unnamed: the dtype pins it and the
# body's var is the one the OTHER branch's dtype does not pin. That is why the
# TODO called this a four-way disjunction and why it is not one. The SHL's OWN
# dtype is UNCONSTRAINED -- `UPat.alu` takes the node's `match_dtype` from the
# LAST src, and the shift amount is a `cvar` with no dtype -- so the uint64 test
# is on the SHL's src[0], which is where the pattern put it.
#
# `<<32` is `mixin/elementwise.py`'s `lshift`, which is `_binop(SHL, 32)`, so the
# amount is `ufix(32)` = `cvar(arg=32)` at src[1] and SHL does not permute. And
# `:193`'s answer `x.cast(dtypes.uint64)` is the very node `x` sits under, because
# `mixin/dtype.py:19`'s `cast` is `self if self.dtype == dt else UOp(Ops.CAST,...)`
# and `x`'s dtype is uint32 -- so the rule MINTS NOTHING, and `sy_cast` is not
# called. That is a claim the gate's `tf_hi_new` row makes.
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

# ---- the last two RECIPROCAL rules, which are `sym_462`'s shape ----
# symbolic.py:463  ((UPat.var("x") * UPat.var("x") * UPat.var("x")).reciprocal(),
#                     lambda x: x.reciprocal()*x.reciprocal()*x.reciprocal())
# THREE copies of one name, so `upat.py:100-105` emits the identity compare twice
# and all three srcs must be the same node -- `sym_462`'s note is the reason: the
# store is written once and overwritten, so the honest port checks all three. The
# outer `*` IS commutative, so the inner `MUL` is a `Sw`'s `a` and the leaf its
# `b`; and `x.reciprocal()*x.reciprocal()*x.reciprocal()` is LEFT-ASSOCIATIVE, so
# the answer is `MUL(MUL(R,R),R)` for EITHER permutation.
def p_mul3.a(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsMUL{}),
    Bool.and(sy_nsrc_is(x, s, 2), p_same(sy_src0(x, s), sy_src1(x, s))))

# `a` is the inner `MUL(v,v)` and `b` is the SIBLING, which is the leaf `v` and not
# the inner -- so the identity check is the inner's own src against the sibling, and
# `p_mul3.a` has already checked that the inner's two srcs are the same node.
def p_mul3.ok(ok: Bool, +x: F.Folded, a: U32, b: U32) -> Bool: Bool.and(ok, p_same(sy_src0(x, a), b))

def p_mul3(+x: F.Folded, +u: U32) -> Sw:
  +i = sw.of(p_mul3.a(x, sy_src0(x, u)), p_mul3.a(x, sy_src1(x, u)), sy_src0(x, u), sy_src1(x, u))
  Sw{p_mul3.ok(Sw.ok(i), x, Sw.a(i), Sw.b(i)), Sw.a(i), Sw.b(i)}

# THE SHARED ENTRY TEST, and there is only ONE because the two rules' patterns
# differ in NOTHING but which `Sw` they build: both are `RECIPROCAL(MUL(..))` with
# two srcs, and the third clause that tells them apart is the `Sw`'s `ok`. Writing
# it once is also what makes `sym_463`/`sym_464` each gated on the same predicate
# their pattern spells, which is `bend2-constraints`' RF6.
def p_recip1(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsRECIPROCAL{}),
    Bool.and(sy_nsrc_is(x, u, 1), Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsMUL{}),
      sy_nsrc_is(x, sy_src0(x, u), 2))))

def p_recip2(+x: F.Folded, +u: U32, +p: Sw) -> Bool: Bool.and(p_recip1(x, u), Sw.ok(p))

# THE TWO ANSWERS, both threaded. `:464`'s is `x.reciprocal()*x.reciprocal()*
# x.reciprocal()` -- LEFT-ASSOCIATIVE, so `MUL(MUL(R,R),R)` -- and `:465`'s is
# `MUL(R(x), R(c))` with the CONST second because `Sw` picked it out of either src
# position.
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
#                     lambda x,c: x.reciprocal()*c.reciprocal())   # 1/(x*c) -> (1/x)*(1/c)
# `x` and `c` are DIFFERENT names, so there is no identity check -- the rule fires
# on `1/(x*c)` for any pair -- and the `*` is commutative, so which src is `c` is a
# `Sw`. When BOTH are CONSTs the first permutation wins, which is what `Sw`
# says, and `sym_161` has already folded the closed tree by then.
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

# ---- THE RULES THAT WERE MISSING, IN UPSTREAM'S ORDER ----
#
# Every rule below is upstream's, at the pin `5c2bf39d6c4b`, and every one of them
# was MISSING: the port's table named 22 of upstream's 139 and the other 117 were
# not ported at all.  `gates/symrules.rows` is the census that says which, and it is
# the census that says which are missing NOW.
#
# THE ORDER IS UPSTREAM'S, because the table is FIRST-WINS: two rules that both match
# a node, and the answer depends on which one the table lists first.  Upstream's
# order is its COMPOSITION order (`sym = symbolic + pm_simplify_valid + ... +
# pm_clean_up_group_sink`), so the rules below are in that order and NOT in line
# order.
#
# THE PORT'S IDIOM, restated because it is what makes a rule look like its
# neighbours: A RULE IS TWO DEFS -- `sym_NNN.pat`, the PATTERN's own tests, and
# `sym_NNN`, the BODY.  The captures are `src[k]` of the node that matched, because
# the arena is the only shared value and a closure cannot take one.  The body answers
# a `Maybe<&1, U32>`, an INDEX into the arena, and `sy_tri` is the "the pattern held,
# and here is the answer" spelling.
#
# AND THE THING THAT IS EASY TO GET WRONG: **A RULE THAT FIRES WHERE UPSTREAM'S DOES
# NOT IS A WRONG KERNEL, AND A RULE THAT DOES NOT FIRE IS A SILENCE.**  So every
# pattern below states the op set, the arity, the dtype set and the IDENTITY CHECK
# that upstream's pattern states, and `gates/symrules-oracle.py` is the CPython
# oracle that says what upstream's rule answers on a graph that MUST fire and on a
# graph that must NOT.

# `GroupOp.Binary - GroupOp.Comparison` -- SIXTEEN ops, and it is a `pdict` KEY, so
# a dropped op makes the rule unfireable and a spurious one makes it fire where
# Python does not.  `GroupOp.Binary` is NINETEEN and `GroupOp.Comparison` is THREE.
def OP_BINARY_NC() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsXOR{},
   O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{}, O.OpsAND{}, O.OpsSUB{}, O.OpsFDIV{},
   O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsTHREEFRY{}]

# `GroupOp.Idempotent` -- {AND, MAX, OR}, the three ops where `x op x` is `x`.
def OP_IDEMPOTENT() -> List<&2, O.Op>: [O.OpsAND{}, O.OpsMAX{}, O.OpsOR{}]

# THE CONST -1, and `p_is_const_neg1` is NOT it: that one compares the I64 to
# 4294967295, which is the U32 bit pattern.  `simplify_pow`'s `-1` and
# `x // -1`'s `-1` are the I64 -1, and the two are different numbers.
def p_is_const_m1(x: F.Folded, u: U32) -> Bool:
  p_is_const_i(x, u, H.i64_sub(H.i64_of_i32(0), H.i64_of_i32(1)))

# THE SRC THAT IS THE CONST 1, and the OTHER one.  `p_const` picks "a src that is a
# CONST", which is NOT the same thing when BOTH srcs are consts -- and upstream's
# permutation tries the FIRST one first, so the answer is the one that is NOT the 1.
def p_one(+x: F.Folded, +u: U32) -> Sw:
  sw.of(p_is_const_1(x, sy_src0(x, u)), p_is_const_1(x, sy_src1(x, u)),
    sy_src0(x, u), sy_src1(x, u))

# symbolic.py:84  (UPat(GroupOp.Unary|{Ops.CAST, Ops.BITCAST}, src=(invalid_gate,), name="op"),
#                   lambda cond,x,op,i: cond.where(op.replace(src=(x,)), i))
# **THIS RULE IS THE ONE THAT COMES BEFORE `:189`, AND IT TAKES THE NODE FROM IT.**
# `CAST(bool, WHERE(cond, x, Invalid))` is claimed by upstream's `:84` (the gate
# lifts INSIDE the cast) and by upstream's `:189` (a cast to bool is `x != 0`), and
# upstream answers the FIRST one.  A port that has `:189` and not `:84` answers
# `x != 0` where upstream answers the lifted gate -- **a rule that fires where
# upstream's does not, on a graph where upstream's does.**  That is the ORDER arm of
# the plant, and it is the arm nobody writes.
def sym_84.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_UNARY()), sy_nsrc_is(x, u, 1)), p_where_gate(x, u, 0))

# `mint_bitcast`, which is `mint_cast`'s sibling: the BITCAST node at an explicit
# dtype, interned into the arena the caller threads.
def mint_bitcast(+f: O.Found, a: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsBITCAST{}, [a], O.ADt{dt}, O.TNone{})

# THE SCRUTINEE IS A PARAMETER AND NOT A COMPUTED VALUE: Bend refuses a `match` on
# a computed value and on a local binder, and says "give it its own def" -- which is
# a def whose PARAMETER is the bool.
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
#                   lambda i: i)
# A COMPARISON is excluded, so `x == Invalid` is NOT this rule -- and the src is a
# LIST, so the Invalid is at either position.
def sym_89.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_BINARY_NC()), sy_nsrc_is(x, u, 2)),
    Bool.or(p_invalid(x, sy_src0(x, u)), p_invalid(x, sy_src1(x, u))))

def sym_89(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_89.pat(x, u),
    Some{Bool.pick(U32, p_invalid(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))})

# symbolic.py:95  (UPat.var("cond").where(invalid_pat, UPat.var("val")),
#                   lambda cond, i, val: cond.logical_not().where(val, i)
#                     if not val.is_invalid else i)
# `where(cond, Invalid, val)` -> `where(!cond, val, Invalid)`, and the `else i` arm
# is the Invalid ITSELF, so a val that is ALSO Invalid answers the Invalid.  The NOT
# is `CMPNE(cond, CONST(True))` -- `mixin/elementwise.py`'s `logical_not` is
# `self.cast(bool).ne(True)` and the cast is a no-op on a bool -- and that is the
# port's `mint_not`.
def sym_95.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    p_invalid(x, sy_src1(x, u)))

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
#                    (a.logical_not()|cond).where(a.where(x,c), i) if not c.is_invalid else None)
# THE GATE MOVES OUT OF THE BRANCH AND INTO THE CONDITION: `a.where(cond.where(x, Invalid), c)`
# becomes `(~a|cond).where(a.where(x, c), Invalid)`. The `if not c.is_invalid` arm is the same
# guard as `:95`'s: when the surviving branch is Invalid too, `:95` has already taken the node.
def sym_97.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(p_gate(x, sy_src1(x, u)), Bool.not(p_invalid(x, sy_src2(x, u)))))

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
#                    (a|cond).where(a.where(b, x), i) if not b.is_invalid else None)
# THE MIRROR of `:97` -- the gate is the ELSE branch, so the lift is OR alone.
def sym_99.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(p_gate(x, sy_src2(x, u)), Bool.not(p_invalid(x, sy_src1(x, u)))))

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
# SHL AND SHR ARE NOT COMMUTATIVE, so the src is ORDERED and the CONST is at src[1].
def sym_121.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_SHIFTS()), sy_nsrc_is(x, u, 2)),
    p_is_const_0(x, sy_src1(x, u)))

def sym_121(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_121.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:122  (UPat.var("x") * 1, lambda x: x)
# `*` IS `UPat.alu(MUL, ...)` and MUL IS COMMUTATIVE, so the src is a LIST and the
# CONST 1 is at either position.
def sym_122.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)), Sw.ok(p))

def sym_122(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_one(x, u)
  sy_tri(sym_122.pat(x, u, p), Some{Sw.b(p)})

# symbolic.py:124  (UPat.var("x") // 1, lambda x: x)
# FLOORDIV IS NOT COMMUTATIVE, so the src is ORDERED.
def sym_124.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    p_is_const_1(x, sy_src1(x, u)))

def sym_124(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_124.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:125  (UPat.var("x") // -1, lambda x: -x)
# `-x` IS `x * (-1)` -- `mixin/elementwise.py`'s `neg` is `self * (-1)` for a
# non-bool -- and that is the port's `sy_neg`.
def sym_125.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    p_is_const_m1(x, sy_src1(x, u)))

def sym_125(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_125.pat(x, u), Some{mint_neg(mint_ar(sy_ar(x)), sy_src0(x, u))})

# symbolic.py:130  (UPat.var("x", dtype=dtypes.bool) & UPat.cvar("c"),
#                    lambda x,c: x if c.val else c)
# AND IS COMMUTATIVE, so the CONST is at either side, and the BOOL is the other one.
# The answer is the bool when the const is TRUTHY and the const when it is FALSY.
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
#                    lambda x,c: c if c.val else x)
# THE OTHER ARM of `:130`: the const wins when it is truthy.
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

# symbolic.py:132  (UPat.var("x", dtype=dtypes.bool) != UPat.const(False, dtypes.bool),
#                    lambda x: x)
# `!=` IS `ne` AND CMPNE IS COMMUTATIVE, so the CONST is at either side.  The NODE's
# dtype is bool, and the CONST is the bool FALSE -- not the int 0.
def sym_132.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), Bool.and(sy_dt_is(x, u, S.boolean()), p_is_const_false(x, Sw.a(p)))))

def sym_132(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sy_tri(sym_132.pat(x, u, p), Some{Sw.b(p)})

# symbolic.py:133  (UPat(GroupOp.Idempotent, src=(UPat.var("x"), UPat.var("x"))), lambda x: x)
# THE NAME IS BOUND TWICE, so the IDENTITY CHECK is load-bearing: without it the
# rule also fires on `x AND y` for two different nodes, and that is a wrong rewrite
# that typechecks.  `Idempotent` is {AND, MAX, OR} and the src is a TUPLE, so the
# order is fixed.
def sym_133.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_IDEMPOTENT()), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_133(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_133.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:135  (UPat.var("x", dtype=dtypes.bool).where(UPat.const(True, dtypes.bool),
#                                                           UPat.const(False, dtypes.bool)),
#                    lambda x: x)
# WHERE IS NOT COMMUTATIVE, so the three srcs are ORDERED: the bool, then the TRUE,
# then the FALSE.
def sym_135.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(p_is_const_true(x, sy_src1(x, u)), p_is_const_false(x, sy_src2(x, u))))

def sym_135(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_135.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:136  (UPat.var("x", dtype=dtypes.bool).where(UPat.const(False, dtypes.bool),
#                                                           UPat.const(True, dtypes.bool)),
#                    lambda x: x.logical_not())
# THE COMPLEMENT of `:135`, and the answer is `CMPNE(x, CONST(True))` -- the
# `.cast(bool)` in `logical_not` is a no-op on a bool node, which is the one mixin
# line this file writes.
# symbolic.py:134  (UPat.var("x", dtype=dtypes.bool).logical_not().logical_not(), lambda x: x)
# `logical_not` IS `CMPNE(x, CONST(True))` on a bool node, so the node is
# `CMPNE(CMPNE(x, True), True)` and the answer is `x` -- an index the arena already holds, so
# this one stays in the index lane.
def sym_134.inner(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(sy_is_op(x, i, O.OpsCMPNE{}),
    Bool.and(sy_nsrc_is(x, i, 2),
      Bool.and(p_is_const_true(x, sy_src1(x, i)), sy_dt_is(x, sy_src0(x, i), S.boolean()))))

def sym_134.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_is_const_true(x, sy_src1(x, u)), sym_134.inner(x, u)))

def sym_134(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri_u(sym_134.pat(x, u), sy_src0(x, sy_src0(x, u)))

def sym_136.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
    Bool.and(p_is_const_false(x, sy_src1(x, u)), p_is_const_true(x, sy_src2(x, u))))

def sym_136.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_not(f, sy_src0(x, u))

def sym_136.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_136.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_136(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_136.hit(sym_136.pat(x, u), x, u)

# symbolic.py:142  (UPat.var("x") < UPat.var("x"), lambda x: x.const_like(False, dtypes.bool))
# `<` IS CMPLT AND CMPLT IS NOT COMMUTATIVE, so the src is ORDERED -- and the name is
# bound twice, so the IDENTITY CHECK is load-bearing.
def sym_142.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_142(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_142.pat(x, u), Some{mint_false(mint_ar(sy_ar(x)), S.boolean())})

# symbolic.py:143  (UPat.var("x") % UPat.var("x"), lambda x: x.const_like(0))
# `%` IS FLOORMOD AND IT IS NOT COMMUTATIVE.
def sym_143.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORMOD{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_143(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_143.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:144  (UPat.var("x") ^ UPat.var("x"), lambda x: x.const_like(0))
# XOR IS COMMUTATIVE, so the src is a LIST -- but the two srcs are the SAME pattern
# object, so `UPat.__init__`'s `all_same` check collapses the permutations to one and
# the IDENTITY CHECK is what is left.
def sym_144.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsXOR{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

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

# symbolic.py:151  (UPat.var("x", dtype=dtypes.ints+(dtypes.bool, dtypes.weakint))
#                       != UPat.var("x"), lambda x: x.const_like(False, dtypes.bool))
# THE DTYPE SET IS TEN -- `dtypes.ints` is EIGHT and `bool` and `weakint` make it
# TEN -- and `p_intish` is that set.  THE NODE's dtype is the constrained one,
# because `UPat.alu` takes the match dtype from the LAST src.
def sym_151.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_same(sy_src0(x, u), sy_src1(x, u)), p_intish(x, sy_src0(x, u))))

def sym_151(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_151.pat(x, u), Some{mint_false(mint_ar(sy_ar(x)), S.boolean())})

# symbolic.py:167  (UPat.var('x', dtype=dtypes.bool) * UPat.var('y', dtype=dtypes.bool),
#                     lambda x,y: x&y)
# MUL IS COMMUTATIVE, so the two bools are at either order, and the answer is the
# AND of them.  THE ANSWER'S OWN ORDER IS FIXED: `x&y` is `alu(AND, y)`, so the
# first src is `x` and the second is `y`, and the port keeps the src order.
def sym_167.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_167.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsAND{}, sy_src0(x, u), sy_src1(x, u))

def sym_167.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_167.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_167(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_167.hit(sym_167.pat(x, u), x, u)

# symbolic.py:168  (UPat.var('x', dtype=dtypes.bool) + UPat.var('y', dtype=dtypes.bool),
#                     lambda x,y: x|y)
# THE COMPLEMENT of `:167`: bool ADD is bool OR.
def sym_168.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_168.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsOR{}, sy_src0(x, u), sy_src1(x, u))

def sym_168.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_168.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_168(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_168.hit(sym_168.pat(x, u), x, u)

# symbolic.py:169  (UPat.var('x', dtype=dtypes.bool).maximum(UPat.var('y', dtype=dtypes.bool)),
#                     lambda x,y: x|y)
# `maximum` IS `alu(MAX, ...)` AND MAX IS COMMUTATIVE.
def sym_169.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMAX{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_169.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  mint_bin(f, O.OpsOR{}, sy_src0(x, u), sy_src1(x, u))

def sym_169.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_169.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_169(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_169.hit(sym_169.pat(x, u), x, u)

# symbolic.py:173  (UPat.var("x") / UPat.var("x"), lambda x: x.const_like(1))
# `/` ON A PATTERN WITH NO DTYPE IS NOT A DIVISION: `mixin/elementwise.py`'s `div`
# takes the FLOAT branch when the dtype is not known, and the float branch is
# `a.alu(MUL, b.recip())`.  So the shape is `MUL(x, RECIPROCAL(x))`.  MUL IS
# COMMUTATIVE, so the RECIPROCAL is at either side, and the name is bound twice, so
# the IDENTITY CHECK is load-bearing.
# THE RECIPROCAL AND ITS PARTNER, and the side is a `Bool` and not an index: a
# PLAIN PARAMETER IN BEND IS A LINEAR RESOURCE and it is CONSUMED ONCE, so an
# index that names two different srcs would be consumed twice.
def p_recip_of(+x: F.Folded, +u: U32, +first: Bool) -> Bool:
  +r = Bool.pick(U32, first, sy_src0(x, u), sy_src1(x, u))
  +o = Bool.pick(U32, first, sy_src1(x, u), sy_src0(x, u))
  Bool.and(sy_is_op(x, r, O.OpsRECIPROCAL{}),
    Bool.and(sy_nsrc_is(x, r, 1), p_same(sy_src0(x, r), o)))

def sym_173.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.or(p_recip_of(x, u, True{}), p_recip_of(x, u, False{})))

def sym_173.vsrc(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sy_is_op(x, sy_src0(x, u), O.OpsRECIPROCAL{}), sy_src1(x, u), sy_src0(x, u))

def sym_173(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_173.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sym_173.vsrc(x, u), O.CInt{H.i64_of_i32(1)}))

# symbolic.py:186  (UPat.var('x').cast(name="a").cast(name="b"),
#                     lambda x,a,b: x if x.dtype == b.dtype and can_lossless_cast(b.dtype, a.dtype) else None)
# A CAST THAT RETURNS TO ITS OWN WIDTH: `b` is the OUTER dtype, `a` the inner one, and the
# guard is `can_lossless_cast(b, a)` -- b's values must survive a round trip through a.
# The answer is `x` itself, so this rule stays in the index lane.
def sym_186.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(Bool.and(sy_is_op(x, i, O.OpsCAST{}), sy_nsrc_is(x, i, 1)),
      Bool.and(O.eq_dt(sy_dt1(x, sy_src0(x, i)), sy_dt1(x, u)),
        D.can_lossless_cast(sy_dt1(x, u), sy_dt1(x, i)))))

def sym_186(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri_u(sym_186.pat(x, u), sy_src0(x, sy_src0(x, u)))

# symbolic.py:188  (UPat(Ops.BITCAST, name="b", src=(UPat.var('x').bitcast(),)),
#                     lambda x,b: x.bitcast(b.dtype))
# A BITCAST IS NOT A CONVERSION, so two of them COMPOSE into one at the OUTER dtype.
def sym_188.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsBITCAST{}), sy_nsrc_is(x, u, 1)),
    Bool.and(sy_is_op(x, sy_src0(x, u), O.OpsBITCAST{}), sy_nsrc_is(x, sy_src0(x, u), 1)))

def sym_188(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_188.pat(x, u),
    Some{mint_bitcast(mint_ar(sy_ar(x)), sy_src0(x, sy_src0(x, u)), sy_dt1(x, u))})

# `y IS logical_not(x)`: `CMPNE(x, CONST(True))`, which is what `mixin/elementwise.py`'s
# `logical_not` is on a bool node (`self.cast(bool).ne(True)`, and the cast is a no-op).
def p_not_of(+x: F.Folded, +n: U32, +v: U32) -> Bool:
  Bool.and(sy_is_op(x, n, O.OpsCMPNE{}),
    Bool.and(sy_nsrc_is(x, n, 2),
      Bool.and(p_is_const_true(x, sy_src1(x, n)), p_same(sy_src0(x, n), v))))

# symbolic.py:243  (UPat.var("x", dtype=dtypes.bool) | UPat.var("x", dtype=dtypes.bool).logical_not(),
#                     lambda x: x.const_like(True))
# OR IS COMMUTATIVE, so the complement is at either src and the test is the same node twice.
def sym_243.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsOR{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()),
      Bool.or(p_not_of(x, sy_src0(x, u), sy_src1(x, u)), p_not_of(x, sy_src1(x, u), sy_src0(x, u)))))

def sym_243(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_243.pat(x, u), mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CBool{True{}}))

# symbolic.py:250  (UPat.var("x") + UPat.var("x"), lambda x: x*2)
# `x*2` IS `MUL(x, CONST(2))`: the 2 is a Python int, so it interns at the OPERAND's dtype
# and not at the ADD's, which is the reading that cost three rules earlier today.
def sym_250.build(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsMUL{}, sy_src0(x, u), O.Found.i(c))}
    case None{}: None{}

def sym_250.put(+x: F.Folded, +u: U32, +f: O.Found) -> Maybe<&1, O.Found>:
  sym_250.build(mint_const_like(f, x, sy_src0(x, u), O.CInt{H.i64_of_i32(2)}), x, u)

def sym_250.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))

def sym_250(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_250.pat(x, u), sym_250.put(x, u, mint_ar(sy_ar(x))))

# symbolic.py:256  (UPat.var("cond", dtype=dtypes.bool).logical_not().where(UPat.var("t"), UPat.var("f")),
#                     lambda cond, t, f: cond.where(f,t) if not f.is_invalid else None)
# A NEGATED GATE SWAPS THE ARMS. `fold_const_where` (`:202`) has already taken the const-gate
# case, and the `if not f.is_invalid` arm is `:95`'s guard again.
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
# THE TWO ARMS ARE ONE NODE, so the inner gate and the outer else branch are the same `d`
# and the two conditions AND: a value survives iff both gates pass.
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
# THE MIRROR of `:262`, and the shared node is the TRUE BRANCH OF BOTH: `UPat.where(b, c, d)`
# puts its second argument in the TRUE slot, so `c` is `src[1]` on each side and NOT the inner
# condition. The two gates OR, because the value is kept when either one takes this branch.
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

# symbolic.py:260  (UPat.var("gate").where(UPat.var("x"), 0) != 0, lambda gate,x: gate & (x != 0))
# A GATED VALUE COMPARED AGAINST THE ELSE BRANCH: `gate ? x : 0` is non-zero exactly when the
# gate holds AND `x` is non-zero, so the gate moves out of the comparison and the two AND.
def sym_260.pat(+x: F.Folded, +u: U32) -> Bool:
  +w = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_is_const_0(x, sy_src1(x, u)),
      Bool.and(Bool.and(sy_is_op(x, w, O.OpsWHERE{}), sy_nsrc_is(x, w, 3)),
        p_is_const_0(x, sy_src2(x, w)))))

# THE MATCH IS THE FIRST STATEMENT: Bend refuses a `match` whose scrutinee is a parameter
# read after a local binder ("'m' can't be matched in this position").
def sym_260.build(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+z}:
      +w = sy_src0(x, u)
      +v = sy_src1(x, w)
      +n = mint_bin(z, O.OpsCMPNE{}, v, O.Found.i(z))
      Some{mint_bin(n, O.OpsAND{}, sy_src0(x, w), O.Found.i(n))}
    case None{}: None{}

def sym_260(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_260.pat(x, u),
    sym_260.build(mint_const_like(mint_ar(sy_ar(x)), x, sy_src1(x, sy_src0(x, u)), O.CInt{H.i64_of_i32(0)}), x, u))

# `x * CONST(c)` with the const at either side, which is `p_const`'s `Sw`.
def p_mul_c(+x: F.Folded, +m: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, m, O.OpsMUL{}), sy_nsrc_is(x, m, 2)), Sw.ok(p_const(x, m)))

def sym_245.vside(+x: F.Folded, +m: U32) -> U32: Sw.b(p_const(x, m))

def sym_245.cside(+x: F.Folded, +m: U32) -> U32: Sw.a(p_const(x, m))

# symbolic.py:245  (UPat.var("x") * UPat.cvar("c0") + UPat.var("x") * UPat.cvar("c1"),
#                     lambda x,c0,c1: x*(c0+c1))
# TWO PRODUCTS OF THE SAME OPERAND COLLAPSE: the coefficients ADD, and the sum is a CONST
# because both are. THE CONSTS ARE ADDED AT THEIR OWN DTYPE and the product is taken at the
# OPERAND's, which is the reading that has cost three rules already today.
def sym_245.pat(+x: F.Folded, +u: U32) -> Bool:
  +m0 = sy_src0(x, u)
  +m1 = sy_src1(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(p_mul_c(x, m0), p_mul_c(x, m1)),
      p_same(sym_245.vside(x, m0), sym_245.vside(x, m1))))

# THE SUM IS A NODE AND NOT A NUMBER: `c0 + c1` in Python is `UOp.__add__` on two CONSTs,
# which BUILDS `(add c0 c1)` and leaves the folding to a later pass. MEASURED: the fold-the-
# value version answered `(mul x c3)` where CPython answers `(mul x (add c1 c2))`.
def sym_245.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +m0 = sy_src0(x, u)
  +s = mint_bin(mint_ar(sy_ar(x)), O.OpsADD{}, sym_245.cside(x, m0), sym_245.cside(x, sy_src1(x, u)))
  Some{mint_bin(s, O.OpsMUL{}, sym_245.vside(x, m0), O.Found.i(s))}

def sym_245(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_245.pat(x, u), sym_245.put(x, u))

# symbolic.py:247  (UPat.var("x") + UPat.var("x") * UPat.cvar("c"), lambda x,c: x*(c+1))
# ADD IS COMMUTATIVE, so the bare operand and the product are at either src and `p_mul_c`
# is what tells them apart. `c+1` IS A NODE -- `(add c c1)` -- for `:245`'s reason.
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

def sym_247.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +p = sym_247.pp(x, u)
  +v = sym_247.vv(x, u)
  sym_247.mk(mint_const_like(mint_ar(sy_ar(x)), x, v, O.CInt{H.i64_of_i32(1)}), x, p, v)

def sym_247(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_247.pat(x, u), sym_247.put(x, u))

def p_add2(+x: F.Folded, +s: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsADD{}), sy_nsrc_is(x, s, 2))

# `(y + x) + x -> y + x*2` (:251) and `(y + x) + x*c -> y + x*(c+1)` (:248) and
# `(y + x*c) + x -> y + x*(c+1)` (:249). ONE SHAPE, THREE GUARDS: the inner ADD is at
# either root src (ADD is commutative), one of its srcs is the ROOT's other src, and the
# pair differs only in whether the inner's other operand is the bare `x` or a product.
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

def sym_251(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_251.pat(x, u),
    sym_251.mk(mint_const_like(mint_ar(sy_ar(x)), x, sym_251.z(x, u), O.CInt{H.i64_of_i32(2)}), x, u))

# symbolic.py:230 -- `commutative`, and IT IS A COMPOSITION AND NOT A RULE OF ITS OWN.
#
#     symbolic = symbolic_simple + commutative + PatternMatcher([... :243 and on ...])
#
# so it sits BETWEEN `symbolic_simple` (through `:202`) and phase 2, and the ORDER is what
# makes it visible: it rewrites first, which is why a phase-2 rule is stated on the operand
# order `commutative` LEAVES BEHIND. The port kept it as a standalone def in `render.bend`
# and composed it NOWHERE, so the whole lane disagreed with CPython on any commutative node
# whose operands sort backwards -- MEASURED 2026-11-03 on `(add (add y x) x)`: CPython
# answers `(add x (add y x))` (`:230` flipping the outer ADD) and the port answered
# `(add y (mul x c2))` (`:251` reading the order `:230` had already changed).
def sym_230.go(m: Maybe<&2, O.Found>) -> Maybe<&1, O.Found>:
  match m:
    case Some{f}: Some{f}
    case None{}: None{}

def sym_230(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_230.go(R.commutative(F.Folded.t(x), sy_ar(x), u))

# symbolic.py:248  ((UPat.var("y") + UPat.var("x")) + UPat.var("x") * UPat.cvar("c"),
#                     lambda x,y,c: y+x*(c+1))
# symbolic.py:249  ((UPat.var("y") + UPat.var("x") * UPat.cvar("c")) + UPat.var("x"),
#                     lambda x,y,c: y+x*(c+1))
# ONE SHAPE WITH THE PRODUCT ON ONE OF TWO SIDES: the ROOT's other src is `x*c` in `:248`
# and `x` in `:249`, so `sym_248.prod` names whichever slot holds the product and the rest of
# the body reads through it. THE PATTERN IS NOT `:251`'s -- `:251` requires the inner add's
# src to BE the root's other src, and here the shared node is the product's VAR side.
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

def sym_248.mk(m: Maybe<&1, O.Found>, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c1}:
      +v = sym_248.v(x, u)
      +c = sym_248.k(x, u)
      +s = mint_bin(c1, O.OpsADD{}, c, O.Found.i(c1))
      +d = mint_bin(s, O.OpsMUL{}, v, O.Found.i(s))
      Some{mint_bin(d, O.OpsADD{}, sym_248.y(x, u), O.Found.i(d))}
    case None{}: None{}

def sym_248(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_248.pat(x, u),
    sym_248.mk(mint_const_like(mint_ar(sy_ar(x)), x, sym_248.v(x, u), O.CInt{H.i64_of_i32(1)}), x, u))

# TWO NAMES AND ONE BODY, because the census resolves a rule by the LINE its table row cites.
def sym_249(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_248(x, u)

# symbolic.py:246  ((UPat.var("y") + UPat.var("x") * UPat.cvar("c0")) + UPat.var("x") * UPat.cvar("c1"),
#                     lambda x,y,c0,c1: y+x*(c0+c1))
# BOTH SIDES ARE PRODUCTS OF THE SAME OPERAND -- `:245`'s two coefficients, plus a `y` that
# rides along. The sum of the coefficients is a NODE, for `:245`'s reason.
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

def sym_246.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +z = sym_251.z(x, u)
  +p2 = sym_246.p2(x, u)
  +s = mint_bin(mint_ar(sy_ar(x)), O.OpsADD{}, sym_245.cside(x, p2), sym_245.cside(x, z))
  +d = mint_bin(s, O.OpsMUL{}, sym_245.vside(x, z), O.Found.i(s))
  Some{mint_bin(d, O.OpsADD{}, sym_246.y(x, u), O.Found.i(d))}

def sym_246(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_246.pat(x, u), sym_246.mk(x, u))

# symbolic.py:254  (UPat.cvar("y") * (UPat.var("x", dtype=dtypes.weakint) + UPat.cvar("c")),
#                     lambda x,y,c: (y*x)+(y*c))
# A CONSTANT DISTRIBUTES OVER A SUM. `cvar` on the multiplier is load-bearing: a VARIABLE
# times a sum does not distribute, because it would grow the graph instead of shrinking it.
# MUL and ADD are both commutative, so `p_const`'s `Sw` finds the const side of each.
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

# symbolic.py:266 and :269 -- TWO WHERES UNDER THE SAME CONDITION COMBINE.
#
#     alu(c.where(t,f), c.where(tt,ff)) -> c.where(t.alu(tt), f.alu(ff))
#
# and `:269` is the ASSOCIATIVE variation with a `y` riding along on the left. THE GUARD IS
# WHY THIS TERMINATES: it fires only when BOTH true branches or BOTH false branches are
# CONSTANTS, so the two ALUs it builds are the ones `fold_const_alu` will fold and the pair
# cannot keep rewriting itself.
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

def sym_266.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sy_src0(x, u)
  +b = sy_src1(x, u)
  +l = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sy_src1(x, a), sy_src1(x, b))
  +r = mint_bin(l, sy_op(x, u), sy_src2(x, a), sy_src2(x, b))
  Some{mint_where(r, sy_src0(x, a), O.Found.i(l), O.Found.i(r))}

def sym_266(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_266.pat(x, u), sym_266.mk(x, u))

# symbolic.py:269  ((UPat.var("y") + UPat.var("c").where(UPat.var("t"), UPat.var("f")))
#                     + UPat.var("c").where(UPat.var("tt"), UPat.var("ff")),
#                    lambda y,c,t,tt,f,ff: y+c.where(t+tt, f+ff) if ... else None)
# THE ASSOCIATIVE VARIATION of `:266`: the same two wheres, but one of them is already inside
# an ADD, so the sum joins the WHERE and the `y` stays outside. Same guard, same reason.
# THE ROOT HAS ONE ADD SRC AND ONE WHERE SRC: the ADD carries `y` and the first where, so
# the side is chosen by `p_add2` and not by the where test.
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
#                     lambda c,t,f: c.where(t, f))
# TWO HALF-GATES OVER ONE CONDITION SUM TO THE WHOLE GATE: each side is zero exactly where the
# other takes over. ADD is commutative, so either order is the same rule with the arms swapped.
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
# MEMBER OF `GroupOp.Associative` (ADD AND MAX MUL OR XOR), which is FIVE census rows and ONE
# body. It repeats `:133`'s shape at two levels and it TERMINATES because each step moves one
# constant inside another: two CONSTS become one node and the outer ALU loses a level.
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

# THE INNER ALU IS THE ROOT'S NON-CONST SIDE, and it is found by asking which side IS an
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
  # THE ROOT'S OTHER SIDE IS THE CONSTANT ITSELF: `outer` already answers the node, and
  # running `c` over it again read a CONST as an ALU and rendered a slot that does not exist.
  +k = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sym_284.c(x, i), sym_284.outer(x, u))
  Some{mint_bin(k, sy_op(x, u), sym_284.v(x, i), O.Found.i(k))}

def sym_284(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_284.pat(x, u), sym_284.mk(x, u))


# ---- `symbolic.py:129`, `fold_add_divmod_recombine` -----------------------------
#
# `pop_const(op)` -- ops.py:1082 -- DEFAULTS TO `ADD` AND NOT `MUL`: a node that does not pop
# answers `(self, identity_element(op, dtype))`, and the identity is 0 for ADD and 1 for MUL. That
# default is load-bearing here: `_quotient_base` builds `t = xa + a - pa` from ADD-pops, so `a`
# and `xa` are ZEROS on nodes that are not ADDs, and a port defaulting to MUL would compute
# `t = 1` and refuse every graph the rule is for.
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

# THE VALUE OF A CONST NODE ITSELF. `pop_const_val` reads the SECOND SRC of an ALU, so on a
# CONST it answers nothing and `pc_id` then hands back the ADD/MUL identity -- which made the
# divisor 0.
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
      qb.mc(pc_cv(ar, num0, O.OpsFLOORDIV{}), ar, q0, base, div, s, qv, num0, pc_v(ar, base, O.OpsADD{}), x)
    case None{}: None{}

def qb.go(+x: F.Folded, +q: U32, +base: U32, +div: H.I64) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +q0 = pc_n(ar, q, O.OpsADD{})
  qb.mqv(pc_cv(ar, q0, O.OpsFLOORDIV{}), ar, q0, base, div, pc_v(ar, q, O.OpsADD{}), x)

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
      +r = mint_bin(c, O.OpsFLOORMOD{}, O.Found.i(b), O.Found.i(c))
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
  sym_129.jalt1(pc_cv(F.Folded.ar(x), q, O.OpsFLOORMOD{}), q, v, terms, it, div, mul, base, x)

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
  sym_129.ione2(Bool.and(O.eq_op(O.Arena.op(ar, mod), O.OpsFLOORMOD{}),
                         O.eq_op(O.Arena.op(ar, O.Arena.src(ar, mod, 1)), O.OpsCONST{})),
                u, mod, terms, x)

def sym_129.iloop(ts: List<&2, U32>, +terms: List<&2, U32>, +x: F.Folded, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match ts:
    case Nil{}: acc
    case +u <> rest:
      sym_129.iloop(rest, terms, x, sym_129.keep(acc, sym_129.ione(u, terms, x)))

def sym_129.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsADD{}), sy_nsrc_is(x, u, 2)), p_intweak(x, u))

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
#                    lambda x: x.const_like(float("nan") if x.op is Ops.CONST
#                                          and isinstance(x.val, float)
#                                          and (math.isnan(x.val) or math.isinf(x.val)) else 0))
# THE NAN ARM: `0 * nan` IS nan AND NOT ZERO, and upstream says so.  THE PORT REFUSES
# THE WHOLE RULE WHEN `x` IS A FLOAT CONST -- a refusal is a SILENCE and a wrong 0
# is a WRONG KERNEL, and the port cannot tell a NaN from a non-zero float with the
# helpers it has.  A CONST THAT IS NOT A FLOAT is not a NaN and not an Inf, so the
# 0 arm is the port's answer.
def sym_178.pat(+x: F.Folded, +u: U32, +p: Sw) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p), Bool.and(p_is_const_0(x, Sw.a(p)), p_not_float_const(x, Sw.b(p)))))

def sym_178(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  +p = p_const(x, u)
  sy_tri(sym_178.pat(x, u, p), sy_const_like(x, Sw.b(p), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:181  (UPat((Ops.CAST, Ops.BITCAST), name="root"),
#                    lambda root: root.src[0] if root.dtype == root.src[0].dtype else None)
# A CAST TO ITS OWN DTYPE IS THE SRC, and the test is the DTYPE and not the op: a
# BITCAST to the same dtype is the identity too.
def sym_181.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_op_in(x, u, OP_CASTS()), sy_nsrc_is(x, u, 1)),
    O.eq_dt(sy_dt1(x, u), sy_dt1(x, sy_src0(x, u))))

def sym_181(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_181.pat(x, u), Some{sy_src0(x, u)})

# symbolic.py:183  (UPat(Ops.BITCAST, name="root",
#                        src=(UPat.any(UPat(Ops.CONST, dtypes.bool, name="c"),
#                                     UPat(Ops.CAST, src=(UPat(Ops.CONST),), name="c")),)),
#                    fold_bitcast)
# `fold_bitcast` IS PORTED -- `fold_bitcast` is a def in this file -- and it had NO
# TABLE ENTRY, so it was a rule that could not run.  THE PATTERN IS A DISJUNCTION of
# a bool CONST and a CAST of a CONST, and the body's own itemsize test is what
# decides.
def p_bool_const(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_const(x, u), sy_dt_is(x, u, S.boolean()))

def sym_183.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsBITCAST{}), sy_nsrc_is(x, u, 1)),
    p_bool_const(x, sy_src0(x, u)))

def sym_183(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_183.pat(x, u), fold_bitcast(x, u, sy_src0(x, u)))

# symbolic.py:189  (UPat.var("x").cast(dtypes.bool), lambda x: x != 0)
# A CAST TO bool IS A COMPARISON AGAINST ZERO, and the CAST's OWN dtype is the
# constraint -- `p_cast_at` reads the arg, which is the pattern constraint and not
# worth a fold round-trip.
def sym_189.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCAST{}), sy_nsrc_is(x, u, 1)),
    p_cast_at(x, u, S.boolean()))

def sym_189.put(+x: F.Folded, +u: U32, +f: O.Found) -> O.Found:
  +z = O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(0)})
  mint_bin(z, O.OpsCMPNE{}, sy_src0(x, u), O.Found.i(z))

def sym_189.hit(hit: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match hit:
    case True{}: Some{sym_189.put(x, u, mint_ar(sy_ar(x)))}
    case _: None{}

def sym_189(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sym_189.hit(sym_189.pat(x, u), x, u)

# symbolic.py:191  (UPat.var("x").alu(Ops.POW, UPat.cvar("c")), simplify_pow)
# `simplify_pow` IS PORTED -- it is a def in this file -- and it had NO TABLE ENTRY,
# so it was a rule that could not run.  **AND THE ONE ARM THAT HAD TO BE ADDED IS
# THE DANGEROUS ONE**: upstream's `simplify_pow` REFUSES a negative exponent over an
# int (`if c.val < 0 and dtypes.is_int(x.dtype): return None`), and the port's
# `simplify_pow` does not, so wiring the body as it stands would make the port
# REWRITE WHERE UPSTREAM DOES NOT.  `p_intweak` is upstream's `dtypes.is_int` --
# `dtypes.ints + (dtypes.weakint,)`, NINE -- and the guard is here.
def p_const_neg.go(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CInt{i}}: H.i64_is_neg(i)
    case _: False{}

def p_const_neg(+x: F.Folded, +u: U32) -> Bool: p_const_neg.go(sy_val(x, u))

def p_const_pos(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.not(p_const_neg(x, u)), Bool.not(p_is_const_0(x, u)))

# symbolic.py:253  (-1 * (UPat.var("x") + UPat.cvar("c")), lambda x,c: (-x)+(-c))
# THE NEGATION DISTRIBUTES OVER A SUM ONE CONSTANT AT A TIME. `-v` is `v * -1` -- `__neg__` is
# `self * -1` -- so each ANSWER product is `MUL(v, CONST(-1))` with `v` FIRST, and the constant's
# negation is a NODE: `(mul c2 n1)`, not a folded -2.
def sym_253.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src1(x, u), sy_src0(x, u))

def sym_253.neg(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, p_is_const_neg1(x, sy_src0(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_253.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_253.inner(x, u)
  # THE -1 IS A REQUIREMENT AND NOT A SIDE-CHECK: the first version only said the INNER side
  # was not -1, so every `c * (x + c2)` distributed through THIS rule with the wrong operand
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
#                    lambda x,d,c: (x<c.val*d.val) if d.val > 0 else (x>c.val*d.val) if d.val < 0 else None)
# A DIVISION MOVES ACROSS THE COMPARISON AS A MULTIPLICATION, and the SIGN of the divisor says
# which way it points. `c.val*d.val` is TWO PYTHON INTS multiplied, so the product is ONE const
# node and not a MUL: CPython answers `(cmplt x c36)`.
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
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsFLOORDIV{}), sy_nsrc_is(x, i, 2)),
        Bool.and(sy_is_cint(sy_val(x, d)), Bool.not(p_is_const_0(x, d))))))

def sym_292(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_292.pat(x, u), sym_292.c(sy_val(x, sy_src1(x, u)), x, u))


# symbolic.py:460  (UPat(Ops.STORE, src=(UPat(Ops.INDEX, name="index"),
#                                       UPat.var("cond").where(UPat.var("val"), invalid_pat))),
#                    lambda index, cond, val, i: UOp.store(index.src[0].index(index.src[1].valid(cond)), val))
# A GATED STORE MOVES THE GATE INTO THE INDEX: `x.valid(cond)` is `cond.where(x, Invalid)`, so
# the INDEX's second src is gated and the STORE's value becomes the UNGATED `val`.
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
# `:253` TAKES THE SUM WITH A CONSTANT; this is the SAME RULE for a sum of two variables, and
# the two are disjoint by construction: `:253` requires a constant side and this one refuses it.
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
#                     lambda x,y,c: x*c+y*c)
# A CONSTANT MULTIPLIER DISTRIBUTES OVER A SUM, and the answer keeps the CONSTANT SECOND in
# each product -- `x*c` and not `c*x`.
def sym_473.inner(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, u))

def sym_473.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, u))

def sym_473.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_473.inner(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Sw.ok(p_const(x, u)),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        p_weakint(x, sy_src0(x, i)))))

def sym_473.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_473.inner(x, u)
  +c = sym_473.c(x, u)
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, sy_src0(x, i), c)
  +m2 = mint_bin(m1, O.OpsMUL{}, sy_src1(x, i), c)
  Some{mint_bin(m2, O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))}

def sym_473(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_473.pat(x, u), sym_473.mk(x, u))

# symbolic.py:453  (UPat.store(UPat(Ops.INDEX, name="index"), UPat.load(UPat(Ops.INDEX, name="index")),
#                                name="x"), lambda index,x: UOp(Ops.NOOP).after(*x.src))
# STORING BACK THE VALUE THAT WAS JUST LOADED FROM THE SAME INDEX IS A NO-OP, and the effect
# becomes `NOOP.after(*x.src)` -- the store's OWN srcs, NOOP first.
def p_load_of(+x: F.Folded, +s: U32, +k: U32) -> Bool:
  Bool.and(sy_is_op(x, s, O.OpsLOAD{}),
    Bool.and(sy_nsrc_ge(x, s, 1), p_same(sy_src0(x, s), k)))

def sym_453.pat(+x: F.Folded, +u: U32) -> Bool:
  +k = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_op(x, k, O.OpsINDEX{}), p_load_of(x, sy_src1(x, u), k)))

def sym_453.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +n = O.UOp.new(sy_ar(x), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  Some{O.UOp.new(O.Found.ar(n), O.OpsAFTER{},
    List.append(&2, U32, [O.Found.i(n)], O.Arena.srcs(O.Found.ar(n), u)), O.ANone{}, O.TNone{})}

def sym_453(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_453.pat(x, u), sym_453.mk(x, u))

# symbolic.py:454  (UPat.store(UPat(Ops.INDEX, name="index"),
#                    UPat.var("gate").where(UPat.var("alt"), UPat.load(UPat(Ops.INDEX, name="index")))),
#                    lambda index, gate, alt: UOp.store(index.src[0].index(index.src[1].valid(gate)), alt))
# THE GATED-READ-MODIFY-WRITE: the gate belongs on the INDEX, so the load's own index is gated
# and the store carries the ungated `alt`. `:460` is the same shape with an Invalid else-branch.
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

# symbolic.py:280  (UPat.maximum(UPat.var("x"), UPat.var("y")),
#                     lambda x,y: x if x.vmin >= y.vmax else y if x.vmax <= y.vmin else None)
# A MAXIMUM IS DECIDED BY THE BOUNDS when one side's WHOLE RANGE is past the other's: `max(x, y)`
# is `x` when `y` can never exceed `x`, and `y` when `x` never can. `x.vmin >= y.vmax` is
# `not (x.vmin < y.vmax)`, and the bounds come from fold.bend's sweep.
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
  +bt = sym_280.bt(x)
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

# EACH MATCH IS ON ITS OWN PARAMETER: Bend refuses a `match` whose scrutinee is a CALL, so the
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

# symbolic.py:274  (UPat({Ops.CMPLT, Ops.CMPNE, Ops.FLOORDIV, Ops.FLOORMOD, Ops.PARAM, Ops.SPECIAL},
#                          name="x"),
#                    lambda x: x.const_like(x.vmin) if x.dtype is not dtypes.void and x.vmin == x.vmax
#                              else None)
# AN ALU OR A PARAM WHOSE WHOLE RANGE IS ONE VALUE IS THAT VALUE -- `(x % 1)` is always 0 and
# `(x < c0)` is always false, and the answer is `x.const_like(vmin)`. `:276` is the RANGE half of
# the same idea with its own pattern, and both read the bounds from fold.bend's sweep.
def op_274(op: O.Op) -> Bool:
  match op:
    case O.OpsCMPLT{}   : True{}
    case O.OpsCMPNE{}   : True{}
    case O.OpsFLOORDIV{}: True{}
    case O.OpsFLOORMOD{}: True{}
    case O.OpsPARAM{}   : True{}
    case O.OpsSPECIAL{} : True{}
    case _              : False{}

# TODO(p2): `(floormod x c1)` DOES NOT FIRE and CPython answers `c0`. MEASURED 2026-11-03:
# `(cmplt x c0)` fires (`bf`) and `(floormod x c2)` declines, so the rule and its guard are
# wired; the missing half is fold.bend's sweep, which does not collapse FLOORMOD's range to
# `[0, 0]` the way it collapses CMPLT's. The case file states the two that agree, and this row
# is the wall the third one sits on -- the fix belongs in `uop/fold.bend`, not here.
def sym_274.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(op_274(sy_op(x, u)), Bool.not(O.eq_dt(sy_dt1(x, u), S.void()))),
    sym_276.same(F.Folded.ar(x), sym_280.bt(x), u))

def sym_274(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +bt = sym_280.bt(x)
  sy_tri_f(sym_274.pat(x, u),
    mint_const_v(sym_276.vc(F.UOp.vmin(ar, bt, u)), mint_ar(ar), sy_dt1(x, u)))

# symbolic.py:276  (UPat(Ops.RANGE, src=(UPat.cvar().or_casted(),), name="x"),
#                    lambda x: x.const_like(x.vmin) if x.vmin == x.vmax else None)
# A RANGE OF LENGTH ONE IS A CONSTANT: `vmin == vmax` means the index can only be that value, so
# the RANGE folds to `x.const_like(vmin)`. `(range c1)` is `0..0` and answers `c0`.
def sym_276.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsRANGE{}), sy_nsrc_ge(x, u, 1)),
    Bool.and(p_const_or_cast(x, sy_src0(x, u)),
      sym_276.same(F.Folded.ar(x), sym_280.bt(x), u)))

def sym_276(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = F.Folded.ar(x)
  +bt = sym_280.bt(x)
  sy_tri_f(sym_276.pat(x, u), mint_const_v(sym_276.vc(F.UOp.vmin(ar, bt, u)), mint_ar(ar), sy_dt1(x, u)))


# divandmod.py:101 -- `(x//c + a)//d -> (x + a*c)//(c*d)` for `c>0, d>0`.
#
# `div_and_mod_symbolic` is composed at the END of `sym` (`symbolic.py:326`:
# `])+div_and_mod_symbolic+pm_uncast_const`), so these rules sit after `:473` in the table and
# FIRST-WINS still holds. The guard is `d.vmin > 0`, and `d` is a CONST, so its bound is its
# value.
def dm_101.i(+x: F.Folded, +u: U32) -> U32: sy_src0(x, u)

def dm_101.v(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, dm_101.i(x, u)))

def dm_101.a(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, dm_101.i(x, u)))

def dm_101.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = dm_101.i(x, u)
  +v = dm_101.v(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_const(x, sy_src1(x, u)), p_const_pos(x, sy_src1(x, u))),
      Bool.and(Bool.and(sy_is_op(x, i, O.OpsADD{}), sy_nsrc_is(x, i, 2)),
        Bool.and(Sw.ok(p_const(x, i)),
          Bool.and(Bool.and(sy_is_op(x, v, O.OpsFLOORDIV{}), sy_nsrc_is(x, v, 2)),
            sy_is_const(x, sy_src1(x, v)))))))

def dm_101.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +v = dm_101.v(x, u)
  +m1 = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, dm_101.a(x, u), sy_src1(x, v))
  +s1 = mint_bin(m1, O.OpsADD{}, sy_src0(x, v), O.Found.i(m1))
  +m2 = mint_bin(s1, O.OpsMUL{}, sy_src1(x, v), sy_src1(x, u))
  Some{mint_bin(m2, O.OpsFLOORDIV{}, O.Found.i(s1), O.Found.i(m2))}

def dm_101(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(dm_101.pat(x, u), dm_101.mk(x, u))

# divandmod.py:103 -- `(x+c)//d -> (x + c%d)//d + c//d` and `(x+c)%d -> (x + c%d)%d`, for any
# `d != 0`, and only when `c % d != c` (otherwise the constant is already inside the range and
# the rewrite would loop).
def dm_103.n(+x: F.Folded, +u: U32) -> U32: Sw.b(p_const(x, sy_src0(x, u)))

def dm_103.c(+x: F.Folded, +u: U32) -> U32: Sw.a(p_const(x, sy_src0(x, u)))

def dm_103.pat(+x: F.Folded, +u: U32) -> Bool:
  +n = sy_src0(x, u)
  Bool.and(Bool.or(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_is_op(x, u, O.OpsFLOORMOD{})),
    Bool.and(Bool.and(sy_nsrc_is(x, u, 2), sy_is_const(x, sy_src1(x, u))),
      Bool.and(Bool.and(sy_is_op(x, n, O.OpsADD{}), sy_nsrc_is(x, n, 2)), Sw.ok(p_const(x, n)))))

def dm_103.quo2(m: Maybe<&1, O.Found>, +s1: O.Found, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+k}:
      +d = mint_bin(k, O.OpsFLOORDIV{}, O.Found.i(s1), sy_src1(x, u))
      Some{mint_bin(d, O.OpsADD{}, O.Found.i(d), O.Found.i(k))}
    case None{}: None{}

def dm_103.quo(+s1: O.Found, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  dm_103.quo2(mint_const_like(s1, x, dm_103.n(x, u), O.CInt{H.i64_div(c, j)}), s1, x, u)

def dm_103.byop(is_mod: Bool, +s1: O.Found, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match is_mod:
    case True{} : Some{mint_bin(s1, O.OpsFLOORMOD{}, O.Found.i(s1), sy_src1(x, u))}
    case False{}: dm_103.quo(s1, c, j, x, u)

def dm_103.put(m: Maybe<&1, O.Found>, +c: H.I64, +j: H.I64, +x: F.Folded, +u: U32, +n: U32) -> Maybe<&1, O.Found>:
  match m:
    case Some{+r}:
      # A MATCH CANNOT SCRUTINIZE A CALL: the op test is read into a `Bool` parameter first.
      dm_103.byop(sy_is_op(x, u, O.OpsFLOORMOD{}),
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
#                     lambda i,x: UOp(Ops.NOOP).after(*x.src))
# A STORE WHOSE VALUE IS INVALID STORES NOTHING: the node becomes `NOOP.after(*srcs)`, which is
# an AFTER over a fresh NOOP and the store's own srcs -- the effect keeps its dependencies and
# loses its write.
def sym_458.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsSTORE{}), sy_nsrc_is(x, u, 2)),
    p_invalid(x, sy_src1(x, u)))

def sym_458.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +n = O.UOp.new(sy_ar(x), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  # `NOOP.after(*srcs)` IS `AFTER(noop, *srcs)`: the NOOP is the FIRST SOURCE and the store's
  # own srcs follow it. The first version dropped it and answered `(after (index b c0) bad)`.
  Some{O.UOp.new(O.Found.ar(n), O.OpsAFTER{},
    List.append(&2, U32, [O.Found.i(n)], O.Arena.srcs(O.Found.ar(n), u)), O.ANone{}, O.TNone{})}

def sym_458(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_458.pat(x, u), sym_458.mk(x, u))

# symbolic.py:318  an AFTER waits only on the EFFECT ops; any other dependency is replaced by
# ITS OWN SRCS, and the result is deduped:
#   x.replace(src=(x.src[0],)+tuple(dedup(flatten([(y,) if y.op in FENCE else y.src
#                                                   for y in x.src[1:]]))))
# so a plain value in the tail expands to what it depends on and a fence stays whole.
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
# defined first because `gather` calls it -- the other order is mutual recursion, which Bend
# refuses.
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
# AN AFTER OR AN END WITH ONE SRC IS THAT SRC -- the node is a fence and a fence over nothing
# is nothing. The answer is an index the arena already holds, so this stays in the index lane.
def sym_322.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.or(sy_is_op(x, u, O.OpsAFTER{}), sy_is_op(x, u, O.OpsEND{})), sy_nsrc_is(x, u, 1))

def sym_322(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri_u(sym_322.pat(x, u), sy_src0(x, u))

# symbolic.py:324  (UPat(Ops.END, name="x"),
#                    lambda x: x.replace(src=(x.src[0],)+tuple(r for r in x.src[1:] if r.op is not Ops.CONST)))
# A RANGE THAT WAS SUBBED FOR A CONST IS GONE FROM THE END's tail: the CONST is kept out and
# everything else stays. `replace` MINTS, so this is a Found body.
# ONE DEF AND NOT TWO: `step` and `keep` calling each other is MUTUAL RECURSION, which Bend
# refuses outright -- the file header says so. `Bool.pick` over a `List<&2, U32>` is legal
# because an unrestricted list is `Data` and not a linear `Type`.
def sym_324.keep(ss: List<&2, U32>, +x: F.Folded, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> t:
      sym_324.keep(t, x, Bool.pick(List<&2, U32>, sy_is_op(x, s, O.OpsCONST{}), acc,
        List.append(&2, U32, acc, [s])))

def sym_324.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsEND{}), sy_nsrc_ge(x, u, 1))

def sym_324.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +rest = O.Arena.srcs(sy_ar(x), u)
  Some{mint_replace(mint_ar(sy_ar(x)), x, u,
    List.append(&2, U32, [sy_src0(x, u)], sym_324.keep(List.tail(&2, U32, rest), x, Nil{})))}

def sym_324(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_324.pat(x, u), sym_324.mk(x, u))

# ---- `symbolic.py:302`, `canonicalize_simplex` ----------------------------------
#
# `(X < 1).ne(True)` where `X` is a sum: if every term is IRREDUCIBLE with `vmin >= 0` and at
# least one is a POSITIVE constant multiple, the coefficients do not change the SIGN of the sum,
# so `a0*x0 + a1*x1 < 1` is `x0 + x1 < 1` for non-negative ints. `GroupOp.Irreducible` is
# `{CONST, GETADDR, PARAM, RANGE, SPECIAL}`.
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

# THE EMPTY ACCUMULATOR IS A LIST AND NOT A FAILURE: `None{}` means "no terms yet", so the first
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
# THE SUM HAS NO DTYPE IN THE ARENA -- its arg is `ANone` -- so `mint_const_like`'s `sy_dt1` read
# `void` and `sy_trunc` refused. The dtype here is the OPERAND's, and `void` falls back to
# `weakint`, which is what the rule's own pattern assumes.
def dt_or_weak(+x: F.Folded, +u: U32) -> S.Dt:
  Bool.pick(S.Dt, O.eq_dt(sy_dt1(x, u), S.void()), S.weakint(), sy_dt1(x, u))

def mint_cst_dt(+f: O.Found, +dt: S.Dt, +v: O.Const) -> Maybe<&1, O.Found>:
  Some{mint_cst(sy_needs_cast(dt, v), O.UOp.const(O.Found.ar(f), v), dt)}

def sym_302.ne3(m: Maybe<&1, O.Found>, +lt: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}: Some{mint_bin(c, O.OpsCMPNE{}, O.Found.i(lt), O.Found.i(c))}
    case None{}  : None{}

def sym_302.ne2(m: Maybe<&1, O.Found>, +x: F.Folded, +s: O.Found) -> Maybe<&1, O.Found>:
  match m:
    case Some{+c}:
      +lt = mint_bin(c, O.OpsCMPLT{}, O.Found.i(s), O.Found.i(c))
      sym_302.ne3(mint_cst_dt(lt, S.boolean(), O.CBool{True{}}), lt)
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
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPNE{}), sy_nsrc_is(x, u, 2)),
    Bool.and(Bool.and(sy_is_op(x, l, O.OpsCMPLT{}), sy_nsrc_is(x, l, 2)),
      Bool.and(p_intweak(x, sy_src0(x, l)), p_is_const_1(x, sy_src1(x, l)))))

def sym_302.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +l = sy_src0(x, u)
  +ts = O.UOp.split_uop(U32.to_nat(O.Arena.next(F.Folded.ar(x))), F.Folded.ar(x), sy_src0(x, l), O.OpsADD{})
  sym_302.emit(sym_302.chg(ts, x, False{}), ts, x)

def sym_302(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_302.pat(x, u), sym_302.run(x, u))

# ---- `weak.py:89`, `pm_uncast_const` -------------------------------------------
#
# `(UPat(GroupOp.Broadcastable, name="u"), uncast_const)` and it is composed at the END of `sym`
# (`symbolic.py:326`: `])+div_and_mod_symbolic+pm_uncast_const`), so its row is last.
#
#   src = tuple(s.src[0] if s.op is CAST and s.dtype not in weaks and s.src[0].op is CONST
#                              and s.src[0].dtype in weaks else s for s in u.src)
#   if src == u.src or (dts := derived_dtypes(u, src)) is None
#      or dts[0] != promo_dtype(u.src) or dts[1] is not u.dtype: return None
#   return u.replace(src=src)
#
# THE DROP MUST CHANGE NOTHING THE CONSUMER DERIVES: neither the operands' meet nor the node's
# own dtype. That is the whole guard, and all four of its readings are landed (`derived_dtypes`
# and `Dts` in `weak.bend`, `promo_dtype` in `fold.bend`).
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
# pass `p_uncastable`, so a list comparison adds nothing but a second way to be wrong -- and Bend
# will not take two list patterns in one `case` anyway.
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
#
# `mop_cleanup` is composed INTO `sym` (`symbolic.py:117-118`: `symbolic_simple = pm_data_invalid +
# mop_cleanup + PatternMatcher([...])`... measured: the movement table sits between
# `symbolic_simple`'s own rules and `commutative`, which is where the census puts it). Its NINE
# rules were already ported in `uop/movement.bend` -- `mop_table`, `mp_dispatch`, `Hop` -- and the
# only thing missing was the COMPOSITION: nothing in `sym_table` named them, so the census called
# all nine MISSING while the bodies sat one file away, gated and mutated.
#
# `mp_try` is what `sym_try_f` already does (ops and early-reject), so the body here is the half
# after it: `hop_self(mp_dispatch(tag, tb, ar, self), self)` -- keep the arena, drop the answer if
# it IS self -- and `Hop.at == UOp.is_none` is Python's `None`.
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
#
#   (UPat(Ops.MUL).reduce(name="r", allow_any_len=True), reduce_mul_chain)
#
# A REDUCE whose FIRST src is a MUL, any number of srcs: the factors of that MUL which do
# NOT depend on the reduced axes can be pulled OUT of the reduce, because `sum(x*m)` is
# `sum(x)*m` when `m` is constant over the axis. `MAX` is the same rewrite only when the
# multiply is monotone, so `vmin >= 0` is required there, and an UNSIGNED multiply wraps,
# which is the guard that has nothing to do with the factors at all.
#
# `prod` IS NOT `upod` FROM 1: `helpers.py:14` is `reduce(operator.mul, x, 1)`, so every
# product here starts from a weak CONST 1 -- `1*i0*i1`, three nodes for two factors, and the
# oracle's answer carries all three.
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
#
#   (UPat.var('x', dtype=bool) * UPat.var('y', dtype=bool), lambda x,y: x&y)
#
# "prevents other rules to rewrite bool ADD/MUL incorrectly": a MUL over two bools IS an
# AND, and `x & y` builds exactly that -- `_broadcasted` leaves both operands alone because
# bool is neither weak nor castable to a narrower width.
def c_f1(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{O.CFloat{f}}: F32.is_eq(f, 1.0)
    case _: False{}

def p_is_const_f1(x: F.Folded, u: U32) -> Bool: c_f1(sy_val(x, u))

# `1 + x` CARRIES WHICHEVER 1 THE GRAPH HAS. `UPat.const(1)` matches the VALUE, so a weakint
# `c1` and a weakfloat `1.0` are the same pattern -- and the fixture writes `c1` while
# CPython's own `1 + xf` promotes it. One predicate asks both, or the rule fires on one side.
def p_c1(+x: F.Folded, +u: U32) -> Bool:
  Bool.or(p_is_const_i(x, u, H.i64_of_i32(1)), p_is_const_f1(x, u))

def sym_171.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_dt_is(x, sy_src0(x, u), S.boolean()), sy_dt_is(x, sy_src1(x, u), S.boolean())))

def sym_171.put(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  Some{mint_bin(mint_ar(sy_ar(x)), O.OpsAND{}, sy_src0(x, u), sy_src1(x, u))}

def sym_171(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_171.pat(x, u), sym_171.put(x, u))

# ---- `symbolic.py:465-467`, the three `x/(1+x)` rules -----------------------------
#
#   x * ((1+x).reciprocal().named("d"))      -> 1-d
#   x * ((1+x).reciprocal().named("d")*y)    -> y*(1-d)
#   x * ((1+x).reciprocal().named("d")+y)    -> (1-d)+x*y
#
# `1 + x` IS ADD(CONST 1, x) -- the CONST is SRC0, which is what `UPat.__radd__` writes --
# and `d` is the NAMED subexpression, so the body REUSES the node the pattern matched.
#
# `1 - d` IS NOT A SUB: `elementwise.py:129` is `a.alu(Ops.ADD, -b)` and `-b` is
# `mul(b, -1)`, so the answer is `ADD(CONST 1.0, MUL(d, CONST -1.0))` -- FOUR nodes, and a
# `SUB` here would be a different graph that no later rule makes equal.
def p_recip1p(+x: F.Folded, +d: U32, +v: U32) -> Bool:
  +a = sy_src0(x, d)
  Bool.and(Bool.and(sy_is_op(x, d, O.OpsRECIPROCAL{}), sy_nsrc_is(x, d, 1)),
    Bool.and(sy_is_op(x, a, O.OpsADD{}), Bool.and(sy_nsrc_is(x, a, 2),
      Bool.and(p_c1(x, sy_src0(x, a)), p_same(sy_src1(x, a), v)))))

# EVERY MINT READS THE ARENA ITS LAST OPERAND OPENED: `neg` is minted in `one`'s arena, so
# the MUL must be built in `neg`'s and not in `one`'s -- measured, the other way the MUL's
# second src is an index the arena it was built in does not hold, and the answer renders `?`.
def mint_one_sub(+f: O.Found, d: U32) -> O.Found:
  +one = O.UOp.const(O.Found.ar(f), O.CFloat{1.0})
  +neg = O.UOp.const(O.Found.ar(one), O.CFloat{F32.neg(1.0)})
  +m = mint_bin(neg, O.OpsMUL{}, d, O.Found.i(neg))
  mint_bin(m, O.OpsADD{}, O.Found.i(one), O.Found.i(m))

def sym_465.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
           p_recip1p(x, sy_src1(x, u), sy_src0(x, u)))

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
#
#   (UPat.var('x', ints+(weakint,)).cast(ints+(weakint,), name="a").cast(name="b"),
#     lambda x,a,b: x.ccast(b.dtype) if not x.overflows(a.dtype) else None)
#
# TWO CASTS WHERE ONE DOES THE SAME: the intermediate `a` is safe to drop when `x`'s whole
# RANGE fits `a.dtype`, which is `overflows` and nothing else. `ccast` is the FORCED cast --
# ops.py:640 says why -- so the answer is a CONST under a CAST for a const and a plain CAST
# for a node, and `UOp.cast`/`UOp.cconst` are the two arms.
#
# THE SET IS `dtypes.ints + (weakint,)` AND NOT "ANY WEAK": `dt_weak_of` is TRUE for
# `weakfloat` too, and the first version used it -- MEASURED, that fired on
# `(cast:i16 (cast:i8 xf))`, which CPython leaves alone, and `symrules-oracle --compare`
# named the case. `dt_intweak` is the weak HALF of the set and nothing else.
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
#
#   (UPat(GroupOp.Binary, src=(UPat.var("x", (long, weakint)), UPat.var("y", (long, weakint))), name="u"),
#     lambda u,x,y: (CONST(x.val) if x is CONST else x.cast(int)).alu(u.op, ...same for y).cast(u.dtype)
#     if long in (x.dtype, y.dtype) and not any(v.overflows(int) for v in (u,x,y)) else None)
#
# NINETEEN OPS IN ONE RULE, because it is `GroupOp.Binary` and the op is CARRIED, not matched:
# `u.op` goes straight into the answer. The three `overflows` guards are the whole promise --
# the arithmetic is done at i32 and cast back, which is only the same number when nothing wraps.
# A CONST operand is rebuilt as a BARE weakint CONST rather than cast, because `x.cast(int)` on
# a const would be a CAST node where upstream writes the value.
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
  +bt = sym_280.bt(x)
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
#
#   (UPat.var("x", weakint) < UPat.cvar("c"), lambda x,c: lt_folding(x, c.val))
#
#   p, np = partition([u.pop_const(Ops.MUL) for u in x.split_uop(Ops.ADD)], lambda uf: uf[1] == 1)
#   if np and (d:=gcd(*[int(f) for _,f in np])) > 1
#      and (t:=ceildiv(c-sum(u.vmin for u,_ in p), d)) == ceildiv(c-sum(u.vmax for u,_ in p), d):
#     return usum(*[u*(f//d) for u,f in np]) < t
#
# `d*y+p < c` is `y < ceildiv(c-p, d)`, so the fold is legal exactly when that bound is the SAME
# at `p.vmin` and `p.vmax`. IT DOES NOT NEED `const_factor`: `pop_const(MUL)` answers the factor
# directly, which an earlier note in this tree got wrong.
#
# THE GCD IS OVER `np` AND NOT OVER EVERY TERM, and that is the one thing the partition is for: a
# `p` term's factor is 1, and folding it in would make every gcd 1 and every fold decline.
# A `BndInt` is SIGN + MAGNITUDE, so the signed value is one branch -- and `Bool.pick` will not
# take `H.I64` as its type argument here, so the branch is a `match` on a `Bool` parameter.
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

# A BOUND THE SWEEP DOES NOT ANSWER MAKES THE FOLD UNKNOWN: reading an unknown bound as 0 would
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

# `ns` HOLDS THE TERM AND `ps` HOLDS THE POPPED NODE, and they are not interchangeable: the answer
# rebuilds `u*(f//d)` from the TERM and pops its factor again, while `p`'s bound is the POPPED
# node's. MEASURED, with the popped node in `ns` the answer read `mul x c0` -- `pc_v` on a bare
# PARAM is the MUL identity 1, and `1//2` is 0.
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
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsCMPLT{}), sy_nsrc_is(x, u, 2)),
    Bool.and(dt_intweak(sy_dt1(x, sy_src0(x, u))), sy_is_const(x, sy_src1(x, u))))

def sym_299.run(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = sy_ar(x)
  +l = lt299.scan(O.UOp.split_uop(O.Arena.budget(ar), ar, sy_src0(x, u), O.OpsADD{}), ar, sym_280.bt(x),
                  Lt{H.i64_zero(), H.i64_zero(), H.i64_zero(), True{}, Nil{}, Nil{}})
  lt299.mk(ar, l, cval(ar, sy_src1(x, u)))

def sym_299(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_299.pat(x, u), sym_299.run(x, u))

# ---- `symbolic.py:193`, a positive const to the power of x -------------------------
#
#   (UPat.cvar("c").alu(Ops.POW, UPat.var("x")),
#     lambda c,x: c if c.val == 1
#       else (x*math.log2(c.val)).exp2() if c.val > 0 and dtypes.is_float(x.dtype) else None)
#
# `c**x` is `exp2(x*log2(c))` and `1**x` is `1` -- and the `1` is the CONST NODE ITSELF, not a
# rebuilt one, so the const arm answers an index it did not mint.
#
# BOTH CONST CLASSES ARE READ, because `UPat.cvar` matches a VALUE and a float const is one: a
# `CInt` reaches `F32` through `U32.to_f32` and a `CFloat` is already the number. A version that
# read only `CInt` would answer `exp2(x*log2(0))` for a float const.
def sym_193.is1(c: O.Const) -> Bool:
  match c:
    case O.CInt{i}: Cmp.is_eq(H.i64_cmp(i, H.i64_of_i32(1)))
    case O.CFloat{f}: F32.is_eq(f, 1.0)
    case _: False{}

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

def sym_193.go1(one: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match one:
    case True{} : Some{O.Found{sy_ar(x), sy_src0(x, u)}}
    case False{}: sym_193.go2(sym_193.pos(sy_maybe_c2(sy_val(x, sy_src0(x, u)))), x, u)

def sym_193.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsPOW{}), sy_nsrc_is(x, u, 2)),
           sy_is_const(x, sy_src0(x, u)))

def sym_193(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_193.pat(x, u), sym_193.go1(sym_193.is1(sy_maybe_c2(sy_val(x, sy_src0(x, u)))), x, u))

# symbolic.py:308  (UPat.var('x').cast(name="a").cast(name="b"),
#                     lambda x,a,b: x.cast(b.dtype) if can_lossless_cast(x.dtype, a.dtype) else None)
# IF THE INTERMEDIATE CAST DOES NOT NARROW, the pair is ONE cast to the outer dtype. `:186`
# (which answers `x` itself) runs first because it is EARLIER in the list; this is the rest.
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
#                     lambda x,c,cast: x.cast(cast.dtype)+cast.const_like(c.val))
# A SIGNED CAST PUSHES THROUGH THE SUM: the variable takes the cast and the constant is rebuilt
# at the CAST's dtype -- `cast.const_like(c.val)`, so the value is the CONSTANT's and the dtype
# is the cast's. The constant is at either side of the ADD, so `p_const`'s `Sw` finds it.
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
# NEGATING BOTH SIDES FLIPS THE COMPARISON. `-1 * v` IS `MUL(CONST(-1), v)`, so each side is a
# MUL whose const side is -1 and the answer swaps the two operands.
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

# `UPat(Ops.RANGE, src=UPat.var("end"), name="r")` -- a RANGE whose source is the node the other
# side repeats.
def p_range_of(+x: F.Folded, +r: U32, +e: U32) -> Bool:
  Bool.or(Bool.and(sy_is_op(x, r, O.OpsRANGE{}), sy_nsrc_ge(x, r, 1)),
    False{})

def sym_304.pat(+x: F.Folded, +u: U32) -> Bool:
  +r = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORMOD{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_range_of(x, r, sy_src1(x, u)), p_same(sy_src0(x, r), sy_src1(x, u))))

# symbolic.py:304  RANGE(end) % end is the RANGE itself: an index over its own upper bound.
def sym_304(+x: F.Folded, +u: U32) -> Maybe<&1, U32>: sy_tri_u(sym_304.pat(x, u), sy_src0(x, u))

# symbolic.py:305  RANGE(end) // end is 0, and the 0 is minted at the RANGE's dtype.
def sym_305.pat(+x: F.Folded, +u: U32) -> Bool:
  +r = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(p_range_of(x, r, sy_src1(x, u)), p_same(sy_src0(x, r), sy_src1(x, u))))

def sym_305(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_305.pat(x, u),
    mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, u), O.CInt{H.i64_of_i32(0)}))

# symbolic.py:295  ((UPat.var("x") + UPat.cvar("c1")) + UPat.var("y"),
#                     lambda x,c1,y: (x+y)+c1 if y.op is not Ops.CONST else None)
# symbolic.py:296  the same for `*`.
# THE CONSTANT MOVES TO THE END so the two-variable part can fold: `(x + c1) + y` becomes
# `(x + y) + c1`. Both ops are commutative, so the constant is at either side of the INNER alu
# and the guard is that `y` is NOT one -- otherwise the rule would fire forever.
def sym_295.inner(+x: F.Folded, +u: U32) -> U32:
  Bool.pick(U32, sym_284.alu2c(x, sy_src0(x, u), sy_op(x, u)), sy_src0(x, u), sy_src1(x, u))

def sym_295.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sym_295.inner(x, u)
  +y = sym_284.outer(x, u)
  Bool.and(Bool.and(sy_nsrc_is(x, u, 2), sym_284.alu2c(x, i, sy_op(x, u))),
    Bool.not(sy_is_const(x, y)))

def sym_295.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sym_295.inner(x, u)
  +s = mint_bin(mint_ar(sy_ar(x)), sy_op(x, u), sym_284.v(x, i), sym_284.outer(x, u))
  Some{mint_bin(s, sy_op(x, u), O.Found.i(s), sym_284.c(x, i))}

def sym_295(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_295.pat(x, u), sym_295.mk(x, u))

# ONE BODY, TWO NAMES: `:296` is the same rule on `*`, and the op comes off the node.
def sym_296(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>: sym_295(x, u)

# symbolic.py:290  ((UPat.cvar("c0") + UPat.var("x", dtype=dtypes.sints+(dtypes.weakint,)))
#                     < UPat.cvar("c1"), lambda x,c0,c1: x<(c1-c0))
# THE CONSTANT MOVES ACROSS THE COMPARISON. `c1-c0` is `c1 + (c0 * -1)` -- `__sub__` is
# `self + other*-1` for a UOp -- so the answer carries THREE nodes and not a folded number,
# which is what CPython's `(add c5 (mul c1 n1))` says.
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

def sym_290.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +a = sy_src0(x, u)
  m = mint_const_like(mint_ar(sy_ar(x)), x, sy_src0(x, a), O.CInt{H.i64_of_i32(4294967295)})
  sym_290.put(m, x, u, a)

def sym_290(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_290.pat(x, u), sym_290.mk(x, u))

# TWO CONSTANTS WITH THE SAME VALUE, and the join of two `Maybe`s is a nested match because a
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
#                     lambda a,b,c: UOp.maximum(a,b) if a.val == c.val else None)
# `a < b ? b : a` IS `max(a, b)` when the else branch is the SAME VALUE as `a` -- the identity
# is on the VALUE and not on the node, because the two branches may be two CONST slots.
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
#                     lambda a,b,c: UOp.maximum(a,b) if b.val == c.val else None)
# THE MIRROR: here the CMPLT's second src is the constant and the WHERE's TRUE branch repeats
# its value.
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
#                     lambda x,c1,c2: x//(c1*c2) if c2.vmin>0 else None)
# TWO DIVISIONS BY CONSTANTS COMPOSE INTO ONE, and the guard is `c2 > 0`: a NEGATIVE divisor
# would flip the rounding of the inner division, so the product is only the composition when
# the OUTER divisor is positive.
def sym_287.pat(+x: F.Folded, +u: U32) -> Bool:
  +i = sy_src0(x, u)
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_const(x, sy_src1(x, u)),
      Bool.and(p_const_pos(x, sy_src1(x, u)),
        Bool.and(Bool.and(sy_is_op(x, i, O.OpsFLOORDIV{}), sy_nsrc_is(x, i, 2)),
          sy_is_const(x, sy_src1(x, i))))))

def sym_287.mk(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +i = sy_src0(x, u)
  +m = mint_bin(mint_ar(sy_ar(x)), O.OpsMUL{}, sy_src1(x, i), sy_src1(x, u))
  Some{mint_bin(m, O.OpsFLOORDIV{}, sy_src0(x, i), O.Found.i(m))}

def sym_287(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_287.pat(x, u), sym_287.mk(x, u))

def sym_191.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsPOW{}), sy_nsrc_is(x, u, 2)),
    Bool.and(sy_is_const(x, sy_src1(x, u)),
      Bool.not(Bool.and(p_const_neg(x, sy_src1(x, u)), p_intweak(x, sy_src0(x, u))))))

def sym_191(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_191.pat(x, u), simplify_pow_f(mint_ar(sy_ar(x)), x, sy_src0(x, u), sy_src1(x, u)))

# THE REWRITER. `PatternMatcher.rewrite` -- ops.py:1603-1610:
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

# `symbolic.py:201` -- `(UPat.var().where(UPat.var("val"), UPat.var("val")), lambda val: val)`.
# A conditional with the SAME node in both branches is the node. NO NEW BODY and no minting:
# the answer is already in the arena, which is why the rule is one line upstream and one
# predicate here.
#
# IT COMES BEFORE :202 IN THE TABLE AND THE ORDER IS LOAD-BEARING: `WHERE(CONST_gate, x, x)`
# matches BOTH rules, and upstream's first-wins gives it to this one. A table that put :202
# first would fold the gate away and keep the branches, which is the same answer here but by a
# longer route -- and on a gate that is NOT a const only this rule fires, so the order is what
# makes the pair total.
def sy_wself.of(is_where: Bool, differ: Bool, +v: U32) -> Maybe<&1, U32>:
  match is_where differ:
    case True{}  False{}: Some{v}
    case _       _      : None{}

def sy_wself(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_wself.of(Bool.and(sy_is_op(x, u, O.OpsWHERE{}), sy_nsrc_is(x, u, 3)),
              Bool.not(U32.is_eq(sy_src1(x, u), sy_src2(x, u))), sy_src1(x, u))

# `fold_const_where` -- symbolic.py:113, THE BODY OF THE RULE AT :202.
#
#     ret = c0 if gate.val else c1
#     return ret.ccast(w.dtype) if ret.op is Ops.CONST and ret.dtype in dtypes.weaks
#                                  and w.dtype not in dtypes.weaks else ret
#
# THE POINT OF IT IS THE DTYPE. Folding a strong-dtype WHERE whose surviving branch is a WEAK
# const must KEEP the strong dtype, or the fold silently narrows the result. So the `ccast` is
# guarded on BOTH sides: the branch is weak AND the WHERE is not.
#
# `sy_ccast` HAD NO CALLER BEFORE THIS -- ported (`symbolic.bend:456`) and unreachable, which is
# a body with no rule; this rule is its first. `sy_val_truthy` is `bool(gate.val)` (its own
# comment cites symbolic.py:127-128) and `dt_weak_of` is `dtype in dtypes.weaks`.
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
#
# `/` IS `* reciprocal()`, so the pattern is `MUL(MUL(x, x2), RECIPROCAL(x2))` and the rule is
# THREE tests deep: the root is a MUL, its `src[0]` is a MUL, and its `src[1]` is the RECIPROCAL
# of `src[0]`'s OWN `src[1]`. THE `x2` IS ONE NAMED VAR IN TWO PLACES, so the identity test is
# the pattern and not a guard.
#
# THE ANSWER IS `x` -- AN EXISTING NODE -- so this rule is one of the few in the 88 that the
# index-only family CARRIES AS IS. That is measured and not assumed: `gates/symclosure-gate.py`
# pins `wall.sym_rewrite_index_only True` and 55 of the 88 mint, so a rule that RETURNS A NODE
# ALREADY IN THE ARENA is the shape that can be added without the family change.
def sym_174.deep(+x: F.Folded, +a: U32, +b: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, a, O.OpsMUL{}), sy_nsrc_is(x, a, 2)),
    Bool.and(sy_is_op(x, b, O.OpsRECIPROCAL{}),
             U32.is_eq(sy_src0(x, b), sy_src1(x, a))))

def sym_174.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsMUL{}), sy_nsrc_is(x, u, 2)),
    sym_174.deep(x, sy_src0(x, u), sy_src1(x, u)))

def sym_174(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_174.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})

def sym_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSTACK{}],                   OP_INVALID(),                    },   # 82
    O.PMEntry{1, OP_UNARY(),                       OP_INVALID(),                    },   # 83
    O.PMEntry{2, OP_UNARY(),                       OP_INVALID(),                    },   # 84
    O.PMEntry{3, OP_BINARY(),                     [O.OpsWHERE{}],                  },   # 87
    O.PMEntry{4, OP_BINARY(),                     [O.OpsWHERE{}],                  },   # 88
    O.PMEntry{5, OP_BINARY_NC(),                   OP_INVALID(),                    },   # 89
    O.PMEntry{6, [O.OpsREDUCE{}],                   Nil{},                           },   # 90
    O.PMEntry{7, [O.OpsWHERE{}],                   OP_INVALID(),                    },   # 92
    O.PMEntry{8, [O.OpsWHERE{}],                   [O.OpsWHERE{}],                    },   # 93
    O.PMEntry{9, [O.OpsWHERE{}],                   Nil{},                           },   # 95
    O.PMEntry{10, [O.OpsWHERE{}], Nil{}, },   # 97
    O.PMEntry{11, [O.OpsWHERE{}], [O.OpsWHERE{}], },   # 99
    O.PMEntry{12, [O.OpsSTORE{}],                   OP_INVALID(),                    },   # 101
    O.PMEntry{13, [O.OpsLOAD{}],                    OP_INVALID(),                    },   # 103
    O.PMEntry{14, OP_SELF(),                        Nil{},                           },   # 120
    O.PMEntry{15, OP_SHIFTS(),                      Nil{},                           },   # 121
    O.PMEntry{16, [O.OpsMUL{}],                     Nil{},                           },   # 122
    O.PMEntry{17, [O.OpsFLOORDIV{}],                Nil{},                           },   # 123
    O.PMEntry{18, [O.OpsFLOORDIV{}],                Nil{},                           },   # 124
    O.PMEntry{19, [O.OpsFLOORDIV{}],                Nil{},                           },   # 125
    O.PMEntry{20, [O.OpsXOR{}],                     Nil{},                           },   # 126
    O.PMEntry{21, [O.OpsFLOORMOD{}],                [O.OpsFLOORMOD{}],               },   # 127
    O.PMEntry{22, [O.OpsADD{}], Nil{}, },   # 129
    O.PMEntry{23, [O.OpsAND{}],                     Nil{},                           },   # 130
    O.PMEntry{24, [O.OpsOR{}],                      Nil{},                           },   # 131
    O.PMEntry{25, [O.OpsCMPNE{}],                   Nil{},                           },   # 132
    O.PMEntry{26, OP_IDEMPOTENT(),                  Nil{},                           },   # 133
    O.PMEntry{27, [O.OpsCMPNE{}], Nil{}, },   # 134
    O.PMEntry{28, [O.OpsWHERE{}],                   Nil{},                           },   # 135
    O.PMEntry{29, [O.OpsWHERE{}],                   Nil{},                           },   # 136
    O.PMEntry{30, [O.OpsCMPNE{}],                   [O.OpsCAST{}, O.OpsCONST{}],     },   # 138
    O.PMEntry{31, [O.OpsTRUNC{}],                   Nil{},                           },   # 140
    O.PMEntry{32, [O.OpsCMPLT{}],                   Nil{},                           },   # 142
    O.PMEntry{33, [O.OpsFLOORMOD{}],                Nil{},                           },   # 143
    O.PMEntry{34, [O.OpsXOR{}],                     Nil{},                           },   # 144
    O.PMEntry{35, [O.OpsAND{}],                     Nil{},                           },   # 145
    O.PMEntry{36, [O.OpsSHR{}],                     [O.OpsAND{}, O.OpsCONST{}],      },   # 147
    O.PMEntry{37, [O.OpsFLOORDIV{}],                [O.OpsAND{}, O.OpsCONST{}],      },   # 149
    O.PMEntry{38, [O.OpsCMPNE{}],                   Nil{},                           },   # 151
    O.PMEntry{39, [O.OpsCAST{}], Nil{}, },   # 155
    O.PMEntry{40, [O.OpsCAST{}], Nil{}, },   # 157
    O.PMEntry{41, OP_ALU_NT(),                     Nil{},                           },   # 161
    O.PMEntry{42, [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{}, O.OpsRECIPROCAL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSUB{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}], Nil{}, },   # 162
    O.PMEntry{43, OP_BINARY_3F(),                   Nil{},                           },   # 163
    O.PMEntry{44, [O.OpsMUL{}],                     Nil{},                           },   # 167
    O.PMEntry{45, [O.OpsADD{}],                     Nil{},                           },   # 168
    O.PMEntry{46, [O.OpsMAX{}],                     Nil{},                           },   # 169
    O.PMEntry{47, [O.OpsMUL{}], Nil{}, },   # symbolic.py:171
    O.PMEntry{48, [O.OpsMUL{}],                     Nil{},                           },   # 173
    O.PMEntry{49, [O.OpsMUL{}],                     Nil{},                           },   # 174
    O.PMEntry{50, [O.OpsMUL{}],                     Nil{},                           },   # 178
    O.PMEntry{51, OP_CASTS(),                       Nil{},                           },   # 181
    O.PMEntry{52, [O.OpsBITCAST{}],                 Nil{},                           },   # 183
    O.PMEntry{53, [O.OpsCAST{}], Nil{}, },   # 186
    O.PMEntry{54, [O.OpsBITCAST{}], Nil{}, },   # 188
    O.PMEntry{55, [O.OpsCAST{}],                    Nil{},                           },   # 189
    O.PMEntry{56, [O.OpsPOW{}],                     Nil{},                           },   # 191
    O.PMEntry{57, [O.OpsPOW{}], Nil{}, },   # symbolic.py:193
    O.PMEntry{58, [O.OpsCAST{}],                    [O.OpsOR{}],                     },   # 196
    O.PMEntry{59, [O.OpsSHR{}],                     [O.OpsOR{}, O.OpsCONST{}],       },   # 197
    O.PMEntry{60, [O.OpsWHERE{}],                  Nil{},                           },   # 201
    O.PMEntry{61, [O.OpsWHERE{}],                  Nil{},                           },   # 202
    O.PMEntry{62, [O.OpsSHRINK{}], Nil{}, },   # movement.py:7
    O.PMEntry{63, [O.OpsRESHAPE{}], Nil{}, },   # movement.py:10
    O.PMEntry{64, [O.OpsRESHAPE{}], Nil{}, },   # movement.py:12
    O.PMEntry{65, [O.OpsPERMUTE{}], Nil{}, },   # movement.py:14
    O.PMEntry{66, [O.OpsPERMUTE{}], Nil{}, },   # movement.py:16
    O.PMEntry{67, [O.OpsSTACK{}], Nil{}, },   # movement.py:18
    O.PMEntry{68, [O.OpsINDEX{}], Nil{}, },   # movement.py:21
    O.PMEntry{69, [O.OpsINDEX{}], Nil{}, },   # movement.py:24
    O.PMEntry{70, [O.OpsINDEX{}], Nil{}, },   # movement.py:27
    O.PMEntry{71, [O.OpsADD{}, O.OpsAND{}, O.OpsCMPEQ{}, O.OpsCMPNE{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsOR{}, O.OpsXOR{}], Nil{}, },   # 230
    O.PMEntry{72, [O.OpsOR{}], Nil{}, },   # 243
    O.PMEntry{73, [O.OpsADD{}], Nil{}, },   # 245
    O.PMEntry{74, [O.OpsADD{}], Nil{}, },   # 246
    O.PMEntry{75, [O.OpsADD{}], Nil{}, },   # 247
    O.PMEntry{76, [O.OpsADD{}], Nil{}, },   # 248
    O.PMEntry{77, [O.OpsADD{}], Nil{}, },   # 249
    O.PMEntry{78, [O.OpsADD{}], Nil{}, },   # 250
    O.PMEntry{79, [O.OpsADD{}], Nil{}, },   # 251
    O.PMEntry{80, [O.OpsMUL{}], Nil{}, },   # 253
    O.PMEntry{81, [O.OpsMUL{}], Nil{}, },   # 254
    O.PMEntry{82, [O.OpsWHERE{}], Nil{}, },   # 256
    O.PMEntry{83, [O.OpsCMPNE{}], Nil{}, },   # 260
    O.PMEntry{84, [O.OpsWHERE{}], Nil{}, },   # 262
    O.PMEntry{85, [O.OpsWHERE{}], Nil{}, },   # 264
    O.PMEntry{86, [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsXOR{}], Nil{}, },   # 266
    O.PMEntry{87, [O.OpsADD{}], Nil{}, },   # 269
    O.PMEntry{88, [O.OpsADD{}], Nil{}, },   # 272
    O.PMEntry{89, [O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsPARAM{}, O.OpsSPECIAL{}], Nil{}, },   # 274
    O.PMEntry{90, [O.OpsRANGE{}], Nil{}, },   # 276
    O.PMEntry{91, [O.OpsWHERE{}], Nil{}, },   # 278
    O.PMEntry{92, [O.OpsWHERE{}], Nil{}, },   # 279
    O.PMEntry{93, [O.OpsMAX{}], Nil{}, },   # 280
    O.PMEntry{94, [O.OpsMAX{}], Nil{}, },   # 284
    O.PMEntry{95, [O.OpsOR{}], Nil{}, },   # 284
    O.PMEntry{96, [O.OpsAND{}], Nil{}, },   # 284
    O.PMEntry{97, [O.OpsADD{}], Nil{}, },   # 284
    O.PMEntry{98, [O.OpsMUL{}], Nil{}, },   # 284
    O.PMEntry{99, [O.OpsFLOORDIV{}], Nil{}, },   # 287
    O.PMEntry{100, [O.OpsCMPLT{}], Nil{}, },   # 290
    O.PMEntry{101, [O.OpsCMPLT{}], Nil{}, },   # 292
    O.PMEntry{102, [O.OpsADD{}], Nil{}, },   # 295
    O.PMEntry{103, [O.OpsMUL{}], Nil{}, },   # 296
    O.PMEntry{104, [O.OpsCMPLT{}], Nil{}, },   # symbolic.py:299
    O.PMEntry{105, [O.OpsCMPLT{}], Nil{}, },   # 300
    O.PMEntry{106, [O.OpsCMPNE{}], Nil{}, },   # 302
    O.PMEntry{107, [O.OpsFLOORMOD{}], Nil{}, },   # 304
    O.PMEntry{108, [O.OpsFLOORDIV{}], Nil{}, },   # 305
    O.PMEntry{109, [O.OpsCAST{}], Nil{}, },   # 308
    O.PMEntry{110, [O.OpsCAST{}], Nil{}, },   # symbolic.py:309
    O.PMEntry{111, [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsXOR{}], Nil{}, },   # symbolic.py:312
    O.PMEntry{112, [O.OpsCAST{}], Nil{}, },   # 316
    O.PMEntry{113, [O.OpsAFTER{}], Nil{}, },   # 318
    O.PMEntry{114, [O.OpsAFTER{}, O.OpsEND{}], Nil{}, },   # 322
    O.PMEntry{115, [O.OpsEND{}], Nil{}, },   # 324
    O.PMEntry{116, [O.OpsFLOORDIV{}], Nil{}, },   # divandmod.py:101
    O.PMEntry{117, [O.OpsFLOORDIV{}, O.OpsFLOORMOD{}], Nil{}, },   # divandmod.py:103
    O.PMEntry{118, [O.OpsADD{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsMAX{}, O.OpsMULACC{}, O.OpsMUL{}, O.OpsOR{}, O.OpsPOW{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsWHERE{}, O.OpsXOR{}], Nil{}, },   # weak.py:89
    O.PMEntry{119, [O.OpsSTORE{}], Nil{}, },   # 453
    O.PMEntry{120, [O.OpsSTORE{}], Nil{}, },   # 454
    O.PMEntry{121, [O.OpsSTORE{}], Nil{}, },   # 458
    O.PMEntry{122, [O.OpsSTORE{}], Nil{}, },   # 460
    O.PMEntry{123, [O.OpsRECIPROCAL{}],              Nil{},                           },   # 462
    O.PMEntry{124, [O.OpsRECIPROCAL{}],              [O.OpsMUL{}],                    },   # 463
    O.PMEntry{125, [O.OpsRECIPROCAL{}],              [O.OpsMUL{}],                    },   # 464
    O.PMEntry{126, [O.OpsMUL{}], Nil{}, },   # symbolic.py:465
    O.PMEntry{127, [O.OpsMUL{}], Nil{}, },   # symbolic.py:466
    O.PMEntry{128, [O.OpsMUL{}], Nil{}, },   # symbolic.py:467
    O.PMEntry{129, [O.OpsREDUCE{}], Nil{}, },   # symbolic.py:469
    O.PMEntry{130, [O.OpsMUL{}], Nil{}, },   # 471
    O.PMEntry{131, [O.OpsMUL{}], Nil{}, },   # 473
    O.PMEntry{132, [O.OpsSINK{}],                    Nil{},                           }]}   # 444

# `pm_remove_invalid` is a SEPARATE MATCHER in Python -- `codegen/__init__.py:367`
# uses it ALONE and it is never composed into `sym` -- so it gets its own tag space
# and its own dispatch. Sharing `sym`'s would let `symbolic.py:91` steal the node
# and make `pm_remove_invalid` dead.
def rm_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsWHERE{}], OP_INVALID()},                            # 108
    O.PMEntry{1, [O.OpsSTACK{}], Nil{}}]}                                 # 109

# THE DECLARED LENGTHS, and they are a sum of unit counts so that a DROPPED table
# entry shows. The transcription is the LIST and the fold is `nats`, so a dropped
# entry and a dropped list element are the same edit; and `tab_len` in the gate is
# the row that says the two agree. Both of these defs were DEAD before this pass,
# and a count nothing checks is a comment with a type.
def nats.go(xs: List<&2, Nat>, n: Nat) -> Nat:
  match xs:
    case Nil{}: n
    case a <> t: nats.go(t, Nat.add(n, a))

def nats(xs: List<&2, Nat>) -> Nat: nats.go(xs, 0n)

def rm_table_len() -> Nat: nats([1n, 1n])

def sym_table_len() -> Nat:
  nats([1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n,
        1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n, 1n])

# THE DRIVER, twice. `sym_*` for the `sym` composition and `rm_*` for
# `pm_remove_invalid`, and the duplication is the honest cost of not having
# first-class functions: see the header.
def sym_dispatch.go(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match tag:
    case 0: sym_82(x, u)
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
    case 25: sym_132(x, u)
    case 26: sym_133(x, u)
    case 27: sym_134(x, u)
    case 28: sym_135(x, u)
    case 31: sym_140(x, u)
    case 35: sym_145(x, u)
    case 49: sym_174(x, u)
    case 50: sym_178(x, u)
    case 51: sym_181(x, u)
    case 52: sym_183(x, u)
    case 53: sym_186(x, u)
    case 58: sym_196(x, u)
    case 59: sym_197(x, u)
    case 60: sy_wself(x, u)
    case 93: sym_280(x, u)
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

# ===========================================================================
# THE `Found` FAMILY -- the SAME TABLE, the SAME ORDER, and an answer that CARRIES THE ARENA.
#
# WHY IT EXISTS. `sym` answers `Maybe<&1, U32>`: an index and NO ARENA. A rule whose body MINTS
# therefore cannot answer at all -- it can only return an index into an arena the caller never
# sees. MEASURED: 55 of the 88 MISSING rules mint, so the majority of what is left is blocked by
# the ANSWER TYPE and not by the rule. `gates/symclosure-gate.py` pins that as
# `wall.sym_rewrite_index_only True`.
#
# THIS IS ADDITIVE AND NOT A REWRITE, and the shape is the port's own `pm_rewrite_m` /
# `pm_rewrite_f` pair in `ops.bend`: one table, two scanners, and the scanner is chosen by what
# its rules answer. The 54 index-only bodies are UNTOUCHED -- `sy_lift` wraps them against the
# CALLER's arena, which is exact for a body that does not mint (a mint would have to be visible
# in `Arena.next`, and `sy_lift` does not read it).
#
# THE ORDER IS ONE SCAN AND NOT TWO PASSES. Minting rules sit INTERLEAVED with index-only ones in
# upstream's first-wins order (`:87` before `:120`, `:202` after `:197`), so a "minting pass
# first" would be right for `:87` and wrong for `:202`. `sym_dispatch_f` picks the family PER
# ENTRY and `sym_scan_f` keeps the same fold.
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
# one claim this lane could not keep. `go` false means the branch already has the strong dtype,
# so the answer is that branch and nothing is minted.
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

# ===========================================================================
# `symbolic.py:87` AND `:88` -- `invalid_gate` LIFTED THROUGH A BINARY OP.
#
#     (UPat(GroupOp.Binary, src=(invalid_gate, UPat.var("y")), name="alu"),
#      lambda cond,x,y,alu,i: cond.where(x.alu(alu.op,y), i))              # :87
#     (UPat(GroupOp.Binary, src=(UPat.var("y"), invalid_gate), name="alu"),
#      lambda cond,x,y,alu,i: cond.where(y.alu(alu.op,x), i))              # :88
#
# `invalid_gate` IS `WHERE(cond, x, Invalid)`, so the rule moves the gate OUT of the operand and
# around the op: `(cond ? x : Invalid) + y` becomes `cond ? (x + y) : Invalid`. THE ORDER OF THE
# TWO OPERANDS IS THE ONLY DIFFERENCE BETWEEN THE PAIR, and it is not cosmetic -- `:88` builds
# `y.alu(op, x)` with `y` FIRST, because `y` was the LEFT operand of the binary node.
#
# BOTH MINT, so both belong to the `Found` family: the `_f` bodies below carry the arena through
# `mint_alu`/`mint_where`. THE PATTERNS DO NOT MINT, which is the file's own RULE/pattern split.
# `UOp.uprod` -- mixin/elementwise.py:41:
#
#     reduce(operator.and_ if self.dtype is dtypes.bool else operator.mul, argfix(*uops), self)
#
# THREE THINGS AND ONLY ONE OF THEM IS OBVIOUS. The receiver is the INITIAL VALUE (so a
# one-element `uprod` answers the receiver and mints nothing), the fold is LEFT to right (so the
# shape is `((self op a) op b)` and not the other grouping), and **THE OP IS `AND` WHEN THE
# RECEIVER IS BOOL AND `MUL` OTHERWISE** -- a port that always folds `MUL` is right on every int
# case and silently wrong on every bool one, which is why the probe below runs BOTH.
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
# "a decreasing self-call ... observed : sy_uprod_f".
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
# the swapped pair for :88 -- which is exactly the two upstream lambdas. It takes a `Found`
# because it MINTS, and the reads are ARENA reads for the same reason.
def sym_87.mk(+f: O.Found, +op: O.Op, +g: U32, +y: U32) -> Maybe<&1, O.Found>:
  +ar = O.Found.ar(f)
  +f1 = mint_alu(op, f, [O.Arena.src(ar, g, 1), y])
  Some{mint_where(f1, O.Arena.src(ar, g, 0), O.Found.i(f1), O.Arena.src(ar, g, 2))}

# THE PATTERN IS THE RULE. `pat` existed and NOTHING CALLED IT, so both of these fired on
# EVERY binary op and rewrote it into `cond.where(x.alu(op,y), i)` with `cond`/`i` read out of
# whatever `src0` was. MEASURED 2026-11-03: `(cmpne (where gb x c0) c0)` answered
# `(where gb (cmpne x c0) c0)` -- `:87` claiming a CMPNE whose src is not a gate at all.
# The index lane hid it: `sym` has no arms for these tags, so only `symf` could see the answer.
def sym_87(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_87.pat(x, u), sym_87.mk(O.Found{sy_ar(x), u}, sy_op(x, u), sy_src0(x, u), sy_src1(x, u)))

# `y.alu(op, x)` AND NOT `x.alu(op, y)`: the gate is src1 here, so the ROOT's src0 comes
# FIRST in the answer and the gate's src1 second. MEASURED 2026-11-03: sharing `:87`'s body
# emitted `(add x y)` where CPython emits `(add y x)`.
def sym_88.mk(+f: O.Found, +op: O.Op, +g: U32, +y: U32) -> Maybe<&1, O.Found>:
  +ar = O.Found.ar(f)
  +f1 = mint_alu(op, f, [y, O.Arena.src(ar, g, 1)])
  Some{mint_where(f1, O.Arena.src(ar, g, 0), O.Found.i(f1), O.Arena.src(ar, g, 2))}

def sym_88(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  sy_tri_f(sym_88.pat(x, u), sym_88.mk(O.Found{sy_ar(x), u}, sy_op(x, u), sy_src1(x, u), sy_src0(x, u)))

# ONE BODY FOR THE PAIR: `(g, y)` in that order, the gate's `x` first inside the op for :87 and
# the swapped pair for :88 -- which is exactly the two upstream lambdas.
# ===========================================================================
# `symbolic.py:90` -- `(invalid_gate.reduce(allow_any_len=True, name="red"), lift_reduce_gate)`
# and the body at `:72`:
#
#   def lift_reduce_gate(red, cond, x, i):
#     if red.arg[1] != 0: return None
#     keep, lift = partition(cond.split_uop(Ops.AND),
#                            lambda c: any(rr in c.ranges for r in red.src[1:] for rr in r.ranges))
#     inner = keep[0].uprod(*keep[1:]).where(x, i) if keep else x
#     return lift[0].uprod(*lift[1:]).where(red.replace(src=(inner,)+red.src[1:]), i) if lift else None
#
# A REDUCE moves inside the gate clauses WITHOUT its ranges, because the ranges invalidate every
# lane at once and so the gate lifts out around the reduce.
#
# `F.ranged(ar)` IS BUILT HERE AND NOT IN THE SCAN. It folds the WHOLE ARENA, so building it per
# candidate node would be quadratic; this body runs only when the pattern matched, and the pattern
# is a REDUCE, so it is built once per reduce and not once per node. `fold.bend:5293` is the
# builder and `fold.bend:5589` already uses it this way.
type KS is Data:
  KS{keep: List<&2, U32>, lift: List<&2, U32>}

def KS.keep(x: KS) -> List<&2, U32>:
  match x:
    case KS{k, l}: k

def KS.lift(x: KS) -> List<&2, U32>:
  match x:
    case KS{k, l}: l

# `rr in c.ranges` for one reduce range `r`: the term's range SET against the node.
# NOT WIRED, AND THE REASON IS A TAG AND NOT A DOUBT. `:90`'s entry belongs BETWEEN `:89`
# (tag 5, `OP_BINARY_NC`) and `:92` (tag 6), so inserting it makes it tag 6 and SHIFTS FORTY-FOUR
# TAGS by one -- and `MINT_TAGS`, `sym_mint_f`'s arms and the census's mapping all read tags. THE
# BODY BELOW IS THEREFORE UNREACHABLE UNTIL THAT INSERTION, and it is committed unreachable on
# purpose: wiring it to `case 5` would dispatch `symbolic.py:89`'s nodes to THIS body, and `:89`
# is a different rule. MEASURED: tag 5 is `# 89`, not `# 90`.
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
# made a one-element list answer the REDUCE ITSELF and the probe read
# `WHERE<REDUCE,WHERE,NOOP>` where the first src should have been the gate.
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
      # holds the reduce `mint_where` is about to wrap. Seeding from `fl` -- the arena BEFORE that
      # mint -- is the arena-threading trap, and MEASURED it printed `WHERE<CONST,WHERE,CONST>`
      # where CPython answers `WHERE<CONST,REDUCE,CONST>`.
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
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsREDUCE{}), sy_nsrc_ge(x, u, 1)), sym_90.zero(x, u))

def sym_90.go(ok: Bool, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case False{}: None{}
    case True{} :
      +ar = sy_ar(x)
      +rt = F.Ranged.rt(F.ranged(ar))
      # THE GATE IS `red.src[0]`, AND `cond`/`x`/`i` ARE ITS THREE SRCS -- NOT THE REDUCE's.
      # MEASURED: reading them off the REDUCE made `x` the reduce's RANGE and the answer
      # `WHERE<WHERE,WHERE,NOOP>` where CPython answers `WHERE<CONST,REDUCE,CONST>`.
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


# THE TAGS WITH A MINTING BODY. A LIST and not a predicate, because the dispatch below is a
# `match` on the tag and the list is what says which tags it must have an arm for.
def MINT_TAGS() -> List<&2, U32>: [2, 3, 4, 6, 8, 9, 10, 11, 17, 19, 22, 29, 30, 32, 33, 34, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 54, 55, 56, 57, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 108, 109, 110, 111, 112, 113, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]

def sym_mint_f(+tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match tag:
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
    case 30: sym_138(x, u)
    case 32: sym_142(x, u)
    case 33: sym_143(x, u)
    case 34: sym_144(x, u)
    case 36: sym_147(x, u)
    case 37: sym_149(x, u)
    case 38: sym_151(x, u)
    case 39: sym_155(x, u)
    case 40: sym_157(x, u)
    case 41: sym_161(x, u)
    case 42: sym_162(x, u)
    case 43: sym_163(x, u)
    case 44: sym_167(x, u)
    case 45: sym_168(x, u)
    case 46: sym_169(x, u)
    case 47: sym_171(x, u)
    case 48: sym_173(x, u)
    case 54: sym_188(x, u)
    case 55: sym_189(x, u)
    case 56: sym_191(x, u)
    case 57: sym_193(x, u)
    case 61: sy_fcw_f(x, u)
    case 62: mv_7(x, u)
    case 63: mv_10(x, u)
    case 64: mv_12(x, u)
    case 65: mv_14(x, u)
    case 66: mv_16(x, u)
    case 67: mv_18(x, u)
    case 68: mv_21(x, u)
    case 69: mv_24(x, u)
    case 70: mv_27(x, u)
    case 71: sym_230(x, u)
    case 72: sym_243(x, u)
    case 73: sym_245(x, u)
    case 74: sym_246(x, u)
    case 75: sym_247(x, u)
    case 76: sym_248(x, u)
    case 77: sym_249(x, u)
    case 78: sym_250(x, u)
    case 79: sym_251(x, u)
    case 80: sym_253(x, u)
    case 81: sym_254(x, u)
    case 82: sym_256(x, u)
    case 83: sym_260(x, u)
    case 84: sym_262(x, u)
    case 85: sym_264(x, u)
    case 86: sym_266(x, u)
    case 87: sym_269(x, u)
    case 88: sym_272(x, u)
    case 89: sym_274(x, u)
    case 90: sym_276(x, u)
    case 91: sym_278(x, u)
    case 92: sym_279(x, u)
    case 94: sym_284(x, u)
    case 95: sym_284(x, u)
    case 96: sym_284(x, u)
    case 97: sym_284(x, u)
    case 98: sym_284(x, u)
    case 99: sym_287(x, u)
    case 100: sym_290(x, u)
    case 101: sym_292(x, u)
    case 102: sym_295(x, u)
    case 103: sym_296(x, u)
    case 104: sym_299(x, u)
    case 105: sym_300(x, u)
    case 106: sym_302(x, u)
    case 108: sym_305(x, u)
    case 109: sym_308(x, u)
    case 110: sym_309(x, u)
    case 111: sym_312(x, u)
    case 112: sym_316(x, u)
    case 113: sym_318(x, u)
    case 115: sym_324(x, u)
    case 116: dm_101(x, u)
    case 117: dm_103(x, u)
    case 118: wk_89(x, u)
    case 119: sym_453(x, u)
    case 120: sym_454(x, u)
    case 121: sym_458(x, u)
    case 122: sym_460(x, u)
    case 123: sym_462(x, u)
    case 124: sym_463(x, u)
    case 125: sym_464(x, u)
    case 126: sym_465(x, u)
    case 127: sym_466(x, u)
    case 128: sym_467(x, u)
    case 129: sym_469(x, u)
    case 130: sym_471(x, u)
    case 131: sym_473(x, u)
    case 132: sym_444(x, u)
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
# symbolic.py:105  (invalid_gate.named("w"),
#                     lambda cond,x,i,w: w.replace(src=(cond,x,w.const_like(0))))
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
#   lambda s: s.replace(src=tuple(UOp.const(0, s.dtype) if x.is_invalid else x
#                                 for x in s.src)) if any(x.is_invalid for x in s.src) else None)
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
# `pm_remove_invalid` dead.
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
# `SINK(STACK(CONST(7), CONST(2)))`: 0 is `CONST(7)`, 1 is `CONST(2)`, 2 is the
# STACK, 3 is the SINK, and tag 11 answers a SINK over `[0, 1]` -- because a
# STACK is one of REMOVE_FROM_SINK_LIKE and is flattened away. The root was a
# GROUP when the root set was `(Ops.SINK, Ops.GROUP)`; upstream narrowed it.
def fx_sink() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(3)})
  f_new(O.Found.ar(d), O.OpsSINK{}, [f_i(c), f_i(d)], O.ANone{})

# `SINK(AFTER(a), b)` -- THE SHAPE `fx_sink` IS NOT, and the fixture that makes
# `eq_u` a SHAPE claim and not a SLOT claim. `fx_sink`'s root is a SINK whose
# sink-like src is a STACK; here the root is a SINK and the sink-like src is an
# AFTER, so the flatten runs on a NESTED sink-like src and the root's op is
# carried over -- neither of which `fx_sink` does. And node 3 is the ANSWER,
# `SINK(a, b)`, INTERNED BEFORE THE REWRITE: `sym_444` rebuilds the src list, asks
# `UOp.new`, and interning is structural equality (`intern.find` over op, src,
# arg, tag), so a correct answer HITS the node already there and answers 3. A
# wrong src list, or a dropped src, mints a fresh node at 6 and answers 6, and
# `sink`'s own `eq_u(..., 6)` cannot tell those two apart -- it reads a SLOT.
def fx_sinkgrp() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = f_new(O.Found.ar(b), O.OpsSINK{}, [f_i(a), f_i(b)], O.ANone{})
  +d = f_new(O.Found.ar(c), O.OpsAFTER{}, [f_i(a)], O.ANone{})
  f_new(O.Found.ar(d), O.OpsSINK{}, [f_i(d), f_i(b)], O.ANone{})

# THE NEGATIVE SIDE, and it is a real row rather than a compliment to the positive
# one -- but the guard it was filed under is NOT the one it witnesses. `sym.rewrite`
# of CPython's `SINK(a, b)` is `None`, so the shape is right; what M20 measured is
# that `sym_444.pat`'s `any_sink_like` half is REDUNDANT and not merely untested:
# with no sink-like src the rebuild is byte-identical to the input, `UOp.new`
# INTERNS it back onto the same slot, and `sy_novel`'s `ret is not uop` swallows
# it. So dropping that half moves NOTHING (M20), and no fixture can make it move.
# CPython carries the same redundancy for the same reason -- `rewrite` also tests
# `ret is not uop`. What THIS row does witness is the OTHER half: M22, taking
# `any_sink_like` AND `sink_srcs.of`'s per-src pick together, moves `sinkgrp0`
# and `sinkgrp` and nothing else. A guard is only pinned once every half of the
# test it shares with is taken, so the two-sided pair is what makes the shape
# claimable at all.
def fx_sinkgrp0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  f_new(O.Found.ar(b), O.OpsSINK{}, [f_i(a), f_i(b)], O.ANone{})

# `ADD(CONST(1), CONST(2**31))` at int32: the top ADD WRAPS to -2147483647.
def fx_i32() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_hi_lo(1, 0)})
  +c = f_alu2(b, O.OpsADD{}, f_i(a))
  f_cast(c, S.int32())

# ---- THE FIXTURES FOR TAGS 13..22, one per rule and a NEGATIVE one per rule whose
# ---- identity check or guard is load-bearing. Every index is stated so a row that
# ---- reads a wrong one says so.
#
# `f_bin` IS THE FIXTURE-HALF OF A TRAP THIS FILE'S HEADER NAMES and that bit three
# of the fixtures below before it was written down. A node must be interned in an
# arena that ALREADY HOLDS every src it names: `f_alu2(+f, op, b)` builds in
# `Found.ar(f)`, so `f_alu2(c, op, f_i(d))` with `d` minted after `c` puts the node
# on the slot `d` was about to take and gives it a SELF-EDGE -- the node count comes
# out one short, the last node answers `nsrc = 0`, and the row silently asks about
# a node that does not exist. `f_bin` takes the arena, so the last construction in
# every fixture names it explicitly.
def f_bin(+ar: O.Arena, op: O.Op, a: U32, b: U32) -> O.Found:
  O.UOp.alu(ar, op, [a, b])

# `FLOORMOD(FLOORMOD(x, y), y)` over the SAME `y`: 1 is `CONST(7)`, 2 is `CONST(3)`,
# 3 is the inner FLOORMOD and 4 the outer, and tag 13 answers the inner node at 3.
# `sym_126`'s shape with a different op, and the answer is `base` -- NOT `x`, which is
# node 1 -- so `modb` and `xorb` are not the same claim.
def fx_mod() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(3)})
  +c = f_bin(O.Found.ar(b), O.OpsFLOORMOD{}, f_i(a), f_i(b))
  f_bin(O.Found.ar(c), O.OpsFLOORMOD{}, f_i(c), f_i(b))

# THE NEGATIVE, and it is the ONLY witness for the rebind check: 1, 2 and 3 are
# `CONST(7)`, `CONST(3)` and `CONST(5)`, 4 is the inner and 5 the outer, and the two
# `y`s are different nodes. `modb` holds with the check dropped; `modb0` is what
# moves.
def fx_mod2() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(3)})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(5)})
  +d = f_bin(O.Found.ar(c), O.OpsFLOORMOD{}, f_i(a), f_i(b))
  f_bin(O.Found.ar(d), O.OpsFLOORMOD{}, f_i(d), f_i(c))

# `CMPNE(CAST(x, weakint), CONST(c))` with `x` a BOOL-dtype node that is NOT a
# CONST -- `AND(CONST(True), CONST(False))` -- so the THREE arms of symbolic.py:136
# answer THREE DIFFERENT NODES and one boolean row cannot stand in for three index
# rows. 1 is `CONST(True)`, 2 `CONST(False)`, 3 the AND (dtype bool), 4 the CAST,
# 5 `CONST(c)` and 6 the CMPNE.
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
# CAST at src[1], so the rule must still find both. `c.val == 0` again, so the
# answer is `x` at 3 -- which is what makes `ne0r` and `ne0` INTERCHANGEABLE as a
# pair and not as singles.
def fx_ne0r() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = O.UOp.const(O.Found.ar(a), O.CBool{False{}})
  +d = O.UOp.new(O.Found.ar(b), O.OpsAND{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})
  +e = f_cast(d, S.weakint())
  +f = O.UOp.const(O.Found.ar(e), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(f), O.OpsCMPNE{}, f_i(f), f_i(e))

# `TRUNC(CAST(CONST(7), int32))`: 1 is the CONST, 2 the CAST and 3 the TRUNC, and
# the answer is the CAST at 2 -- the TRUNC's own dtype is unconstrained upstream, so
# a row that asserted the ANSWER's dtype would be asserting something else. The
# TRUNC is built with `f_new` and not `f_alu2` because it has ONE src.
def fx_trunc() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = f_cast(a, S.int32())
  f_new(O.Found.ar(b), O.OpsTRUNC{}, [f_i(b)], O.ANone{})

# THE NEGATIVE, and the dtype set is the whole claim: the same TRUNC over a
# `weakfloat` CONST, which is NOT in `dtypes.ints + (bool, weakint)`.
def fx_truncf() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CFloat{2.75})
  f_new(O.Found.ar(a), O.OpsTRUNC{}, [f_i(a)], O.ANone{})

# `(x & mask) >> k` with `k = 4` and `mask = -16`, so `mask | ((1 << 4) - 1)` is
# `-1`: 1 is `CONST(7)`, 2 the `CONST(-16)` mask, 3 the AND, 4 the `CONST(4)` and
# 5 the SHR. The answer is `SHR(x, CONST(4))`, and the `CONST(4)` is ALREADY node 4
# because `sp_const(weakint, ...)` folds to a bare CONST and the arena hash-conses.
def fx_shr() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(4)})
  f_bin(O.Found.ar(d), O.OpsSHR{}, f_i(c), f_i(d))

# THE NEGATIVE, and it is the GUARD: the same shape with `mask = 0`, so
# `0 | 15` is `15` and not `-1`.
def fx_shr0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(4)})
  f_bin(O.Found.ar(d), O.OpsSHR{}, f_i(c), f_i(d))

# `(x & mask) // c` with `c = 16`, which is a power of two, and `mask = -16`. The
# same node shape as `fx_shr`, so the two rules are one fixture read twice.
def fx_fdivm() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(16)})
  f_bin(O.Found.ar(d), O.OpsFLOORDIV{}, f_i(c), f_i(d))

# THE NEGATIVE, and it is the POWER-OF-TWO half: `c = 15` is not one, so the rule
# must not fire even though `mask | (c-1)` is still `-1`.
def fx_fdivm0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(4294967280)})
  +c = f_bin(O.Found.ar(b), O.OpsAND{}, f_i(a), f_i(b))
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(15)})
  f_bin(O.Found.ar(d), O.OpsFLOORDIV{}, f_i(c), f_i(d))

# THE PROMOTION, and it is a TWO-SRC fold over `[casted_const, bare_const]`: 1 is
# the bare `CONST(3)`, 2 is `CAST(CONST(3), int32)` -- a `casted_const` at a
# CONCRETE dtype, which is the only way the meet leaves `dtypes.weaks` -- 3 is the
# bare `CONST(0)` and 4 the MUL. It is a MUL and not an ADD because `sym_120`
# (`x + 0`) claims the ADD FIRST and would answer 3 instead.
def fx_prom() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +b = f_cast(a, S.int32())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(b), f_i(c))

# THE NEGATIVE, and it is the MEET: the same shape with the cast at `weakint`, so
# `promo_dtype` is weak and upstream's `:163` REFUSES -- so the scan continues and
# upstream's `:178` answers a CONST 0.  `Python answers None` WAS THE CLAIM HERE
# AND IT WAS FALSE; the oracle is `gates/symrules-oracle.py` and it says `c0`.
def fx_prom0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +b = f_cast(a, S.weakint())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(b), f_i(c))

# THE THREEFRY UNPACK, LOW HALF: `CAST(SHL(z, 32) | CAST(y, uint64), uint32)` with
# `z` at uint64 and `y` at uint32. 1 is `CONST(7)`, 2 `CAST(1, uint32)`, 3
# `CONST(9)`, 4 `CAST(3, uint64)`, 5 the `CONST(32)`, 6 the SHL, 7 `CAST(2, uint64)`,
# 8 the OR and 9 the outer CAST. The answer is `y` at 2, and it is a node that was
# ALREADY THERE.
def fx_tflo() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = f_cast(a, S.uint32())
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(9)})
  +d = f_cast(c, S.uint64())
  +e = O.UOp.const(O.Found.ar(d), O.CInt{H.i64_of_i32(32)})
  +f = f_bin(O.Found.ar(e), O.OpsSHL{}, f_i(d), f_i(e))
  +g = O.UOp.new(O.Found.ar(f), O.OpsCAST{}, [f_i(b)], O.ADt{S.uint64()}, O.TNone{})
  +h = f_bin(O.Found.ar(g), O.OpsOR{}, f_i(f), f_i(g))
  f_cast(h, S.uint32())

# THE THREEFRY UNPACK, HIGH HALF: `SHR(SHL(CAST(x, uint64), 32) | CAST(z, uint64),
# 32)`. 1 is `CONST(7)`, 2 `CAST(1, uint32)`, 3 `CAST(2, uint64)`, 4 the
# `CONST(32)`, 5 the SHL, 6 `CONST(9)`, 7 `CAST(6, uint32)`, 8 `CAST(7, uint64)`,
# 9 the OR and 10 the SHR. The answer is node 3 -- the node `x` sits under -- and
# `tfhi_cast` is the row that says it is the uint64 CAST and not something else.
def fx_tfhi() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
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
# RECIPROCAL. The answer is `MUL(MUL(R,R),R)` over the SAME `R`, so it is three new
# nodes and NOT the arity the fixture has.
def fx_recip3() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = f_bin(O.Found.ar(a), O.OpsMUL{}, f_i(a), f_i(a))
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(b), f_i(a))
  f_new(O.Found.ar(c), O.OpsRECIPROCAL{}, [f_i(c)], O.ANone{})

# THE NEGATIVE, and it is the SIBLING identity check: the inner MUL's two srcs are
# the same node and the outer's other src is NOT it, so a rule that checked only the
# inner would fire here. The sibling is an `ADD` and NOT a CONST on purpose -- a
# CONST sibling would make `:465`'s `MUL(x, cvar)` match, and then this row would be
# testing `sym_464` and not `sym_463`. That is the FIRST version of this fixture and
# `recip3x` read 0, which is how the trap was found.
def fx_recip3x() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(a), f_i(a))
  +d = f_bin(O.Found.ar(c), O.OpsMUL{}, f_i(c), f_i(b))
  f_new(O.Found.ar(d), O.OpsRECIPROCAL{}, [f_i(d)], O.ANone{})

# `1/(x*c)` with a NON-CONST `x`, so the rule's own two names are distinguishable:
# 1 is `CONST(9)`, 2 is the weakint `ADD(1,1)` -- the weak non-const node -- 3 is
# `MUL(2,1)` and 4 the RECIPROCAL. The answer is `MUL(R(2), R(1))`.
def fx_recipc() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(9)})
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(b), f_i(a))
  f_new(O.Found.ar(c), O.OpsRECIPROCAL{}, [f_i(c)], O.ANone{})

# THE SAME, WITH THE CONST AT src[0] -- the SECOND permutation, and the row that
# says `Sw` picks the cvar and not the position. The answer is the SAME NODE as
# `fx_recipc`'s, because `MUL` is commutative in the pattern and not in the arena.
def fx_recipc0() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(9)})
  +b = O.UOp.new(O.Found.ar(a), O.OpsADD{}, [f_i(a), f_i(a)], O.ANone{}, O.TNone{})
  +c = f_bin(O.Found.ar(b), O.OpsMUL{}, f_i(a), f_i(b))
  f_new(O.Found.ar(c), O.OpsRECIPROCAL{}, [f_i(c)], O.ANone{})

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
#   total_sym=139  UPSTREAM'S rule count for the blocks `sym` composes, at the pin
#                `5c2bf39d6c4b`.  IT WAS 127 until this pass, because `tinygrad/`
#                was re-vendored forward on 2026-10-20 and the count was a
#                TRANSCRIPTION of the previous revision's blocks -- and a
#                transcription of a count is a number that stops being true while
#                the sentence keeps looking like a measurement.  The
#                decomposition is upstream's own COMPOSITION, and the ONE
#                generator rule (`:284`) is FIVE rules, not one.
#   skip=117     `total_sym - len_sym`, so `len_sym + skip == total_sym` and the
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
#                is the only rule here that rebuilds a src LIST. IT READS A SLOT:
#                the answer is a FRESH node at 6, and `eq_u(..., 6)` is satisfied by
#                any wrong src list that also mints one. `sinkgrp` is that row.
#   sinkgrp      tag 12 at a SINK root, `SINK(GROUP(a), b)` -- the shape `fx_sink`
#                is not (a nested sink-like src, and the root's OP carried over).
#                The fixture INTERNS the answer `SINK(a, b)` before the rewrite, so
#                interning is structural equality and the row pins the src LIST.
#                M17 drops one src and moves this row and NOT `sink`.
#   sinkgrp0     `SINK(a, b)` with no sink-like src, which CPython also refuses
#                (`sym.rewrite` is `None`). M22 is the only mutation that moves it,
#                and it takes BOTH halves of the sink-like test -- M20 alone moves
#                nothing because `sy_novel` swallows an identical rebuild.
#   rm_where=1   `pm_remove_invalid` tag 0: the Invalid false branch becomes a
#                `const_like(0)` and the op is unchanged.
#   rm_stack=1   `pm_remove_invalid` tag 1: an Invalid src of a STACK becomes a
#                `const_like(0)` and the other src is untouched.
#   first=1      FIRST-WINS, on a node TWO rules both claim: a
#                `WHERE(cond,x,CONST(Invalid))` is claimed by `sym_92` (tag 2) and
#                by `pm_remove_invalid`'s tag 0, they DISAGREE, and `sym` must
#                answer tag 2. A fixture where both agreed could not tell
#                first-wins from a conjunction -- the trap the brief names.
#   modb/modb0   tag 13, symbolic.py:124. `(x%y)%y -> x%y` over the SAME `y`, and
#                the negative is the ONLY witness for the rebind check `p_rebind2`
#                holds. A positive rebind row is worth nothing on its own.
#   ne0/ne1/ne2  tag 14, symbolic.py:135-136. The THREE arms, and they answer THREE
#   /ne0r        DIFFERENT NODES (3, 7 and 1) because `x` is a bool-dtype node that
#                is NOT a CONST -- a const `x` would make arms 0 and 2 the same
#                index and one row could not tell them apart. `ne0r` is the
#                PERMUTED side: the CONST at src[0], the CAST at src[1], and the
#                same answer. A rule that read the CAST out of src[0] would answer
#                None here and `ne0r` would move while `ne0` stayed.
#   trunc/trunc0 tag 15, symbolic.py:137. `x.trunc() -> x` at an int, and the SAME
#                TRUNC over a weakfloat CONST, which is not in
#                `dtypes.ints + (bool, weakint)`. The dtype SET is the whole claim.
#   shr/shr0     tag 16, symbolic.py:144. `(x & mask) >> k` -> `x >> k` when
#   fdivm/fdivm0 `mask | ((1 << k) - 1) == -1`, answered at 6 and NOT 5 -- the
#                answer is `SHR(x, CONST(4))` and the amount is the ALREADY-INTERNED
#                node 4. `shr0` is `mask = 0` and `fdivm0` is a NON-power-of-two `c`,
#                so the two rules' two guards are two rows.
#   promo_c/_0   tag 18, symbolic.py:160. The weak src is committed at the meet and
#                the strong one is left alone. It is a MUL and not an ADD because
#                `sym_120` claims `x + 0` FIRST. `promo_c0` is the same shape with the
#                cast at weakint, where the meet is weak and Python answers None.
#   tflo/tfhi    tags 19/20, symbolic.py:192/194. BOTH answer a node that was
#   /tfhi_cast   ALREADY THERE -- `tfhi = 3` IS the no-mint claim, and `tfhi_cast`
#                says the node is the uint64 CAST rather than something else.
#   recip3/      tag 21, symbolic.py:464. `1/(x*x*x)` -> `MUL(MUL(R,R),R)`, three new
#   recip3x      nodes and not the arity the fixture has. `recip3x`'s sibling is an
#                `ADD` and NOT a CONST ON PURPOSE: a CONST sibling makes `:465`'s
#                `MUL(x, cvar)` match and the row would be testing `sym_464`. That
#                was the first version of the fixture and `recip3x` read 0, which
#                is how the trap was found.
#   recipc/      tag 22, symbolic.py:465. `1/(x*c)` -> `MUL(R(x), R(c))`, and BOTH
#   recipc0      rows ask for the SAME INDEX from two fixtures with the const on
#                opposite sides -- which IS the claim, because `Sw` picks the cvar
#                rather than the position.
#   ints_n=8     THE THREE DTYPE-SET COUNTS, and `dtypes.ints` is EIGHT. The
#   intish_n=10  helpers here answered six and five before this pass. A COUNT
#   intweak_n=9  because a mis-spelled entry in a list is invisible to any boolean
#                over one dtype; the oracle is CPython's own `len(dtypes.ints)`.
#   bin3f_n=18   `GroupOp.Binary - {THREEFRY}` is EIGHTEEN, and the set is a `pdict`
#                KEY: a dropped op makes a rule unfireable and a spurious one makes
#                it fire where Python does not. Neither shows in a per-op boolean.
#   len_dec      THE DECLARED LENGTH equals the table's, and `len_dec_rm` is the same
#                for `rm_table`. Both `sym_table_len`/`rm_table_len` were DEAD defs
#                before this pass and a count nothing checks is a comment with a
#                type.
#   promo=1      THE OPERATOR-LAYER RESTRICTION, stated as a row that CAN fail:
#                every fixture above is built from weakint CONSTs, so
#                `least_upper_dtype` is the identity and the missing
#                `mixin/elementwise.py` promotion CANNOT SHOW. The row moves the
#                moment a concrete-dtype fixture is added -- AND ONE NOW EXISTS:
#                `fx_prom` is `MUL(CAST(3, int32), CONST(0))`, so the meet is int32
#                and `sym_163`'s answer is committed AT int32. `promo_c` is that
#                fixture and it is still `weakint`-only inside, because the rule
#                builds the promoted node out of the two CAPTURED srcs and the
#                capture does not promote. So the row has NOT moved, and the reason
#                is now a sentence rather than a shrug. `mixin/elementwise.py:50
#                def logical_not` is the one mixin line this file borrows.
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

# THE UPSTREAM TOTAL, AND IT MOVED BECAUSE `tinygrad/` WAS RE-VENDORED.  The old
# arithmetic was `14 + 47 + 1 + 47 + 2 + 14 + 2` = 127, which was upstream's rule
# count at the PREVIOUS pin.  The count at the pin `5c2bf39d6c4b` is 139, and the
# decomposition is upstream's own COMPOSITION -- `sym = symbolic + pm_simplify_valid
# + PatternMatcher([...]) + pm_clean_up_group_sink` -- so the parts are:
#   14 `pm_data_invalid` + 48 `symbolic_simple`'s own + 9 `mop_cleanup` +
#    1 `commutative` + 46 `symbolic`'s own (41 source lines, and the ONE
#      generator at :284 is FIVE rules because `GroupOp.Associative` has five
#      members -- a grep counts one) + 3 `div_and_mod_symbolic` +
#    1 `pm_uncast_const` + 2 `pm_simplify_valid` + 14 `sym`'s own +
#    1 `pm_clean_up_group_sink`
# `gates/symrules-census.py` DERIVES that number from upstream's AST and
# CROSS-CHECKS it against the live matcher, and `gates/symrules.rows` is the
# table it prints.  This arithmetic is the port's own copy of it.
def t_total() -> U32: U32.add(U32.add(U32.add(U32.add(14, 48), 9), 1), U32.add(U32.add(46, 3), U32.add(U32.add(1, 2), U32.add(14, 1))))

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

# THE INTEGER LANE'S `max`, WHICH WAS A `min` (see `i32_max`). THE ROW IS
# SYMMETRIC ON PURPOSE: `max(3, 7)` AND `max(7, 3)` MUST BOTH BE 7, AND A `min`
# ANSWERS 3 FOR BOTH -- SO A ONE-SIDED ROW WOULD PASS ON THE BUG.
def t_max_i() -> U32:
  Bool.to_u32(Bool.and(
    i32_is(exec_alu_i32(False{}, O.OpsMAX{}, I3{2, 3, 7, 0}), H.i64_of_i32(7)),
    i32_is(exec_alu_i32(False{}, O.OpsMAX{}, I3{2, 7, 3, 0}), H.i64_of_i32(7))))

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
# THE TAG-0 FIXTURE. `sym_82` is `STACK(CONST(Invalid), ...) -> the Invalid`, and
# `broadcast` is an `itertools.repeat`, so the STACK may have any arity >= 1.
def fx_bcast() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CInvalid{})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  f_new(O.Found.ar(b), O.OpsSTACK{}, [f_i(a), f_i(b)], O.ANone{})

def t_bcast() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_bcast()), 3), 1))

def t_sink() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_sink()), 5), 6))

# THE SAME RULE AT A SINK ROOT, and the answer is a node that was ALREADY THERE,
# so this row pins `sym_444`'s src LIST and not the slot it happened to land on.
# `sinkgrp0` is its other side and the only witness for the `any_sink_like` half.
def t_sinkgrp() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_sinkgrp()), 5), 3))

def t_sinkgrp0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_sinkgrp0()), 3)))

def t_rm_where() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_where()), 4), 5))

def t_rm_stack() -> U32: Bool.to_u32(eq_u(pm_remove_invalid(fx_of(fx_stack()), 3), 4))

# THE FIRST-WINS FIXTURE. The overlapping pair is `sym_444` (`GROUP(x)` -> x) and
# `sym_444` (the GROUP/SINK flatten), both claiming a one-src GROUP whose src is
# sink-like, and they DISAGREE -- tag 11 answers the src, tag 12 a flattened
# rebuild. (`sym_92` and `pm_remove_invalid`'s tag 0 look like a pair and are not:
# their two shapes are mutually exclusive, so they can never both claim a node.)

# ---- THE ROWS FOR TAGS 13..22, and the COUNT rows for the dtype sets. Every
# ---- answer index below was read off a run, not assumed, and each negative row
# ---- exists because its rule's GUARD is load-bearing rather than incidental.
def t_modb() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_mod()), 4), 3))

def t_modb0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_mod2()), 5)))

# THE THREE ARMS OF `sym_138`, and they answer THREE DIFFERENT NODES because `x` is
# a bool-dtype node that is NOT a CONST -- so `c.val == 0` answers `x` (3),
# `c.val == 1` answers a fresh `CMPNE(x, CONST(True))` (7) and the else arm answers
# the already-interned `CONST(True)` (1). A single row could not tell them apart.
def t_ne0() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne0()), 6), 3))

def t_ne1() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne1()), 6), 7))

def t_ne2() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne2()), 6), 1))

# THE PERMUTED SIDE. `ne0r` asks for the SAME answer as `ne0` from a fixture whose
# CONST is at src[0], so a rule that read the CAST out of src[0] unconditionally
# would answer `None` here and `ne0r` would move while `ne0` stayed.
def t_ne0r() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_ne0r()), 6), 3))

def t_trunc() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_trunc()), 3), 2))

def t_trunc0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_truncf()), 2)))

# `shr` answers `SHR(x, CONST(4))` at 6 and NOT 5, which is the whole claim: the
# AND's non-const src is `x` and the shift amount is the ALREADY-INTERNED node 4,
# because `sp_const(weakint, ...)` folds to a bare CONST.
def t_shr() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_shr()), 5), 6))

def t_shr0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_shr0()), 5)))

def t_fdivm() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_fdivm()), 5), 6))

def t_fdivm0() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_fdivm0()), 5)))

# `promo_c` answers `MUL(CAST(3, int32), CAST(0, int32))` at 6: the weak src is
# committed at the meet and the strong one is left alone. It is a MUL and not an
# ADD because `sym_120` (`x + 0`) claims the ADD FIRST and would answer 3.
def t_promo_c() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_prom()), 4), 6))

# `promo_c0` USED TO ASK "the port answers NOTHING", and IT WAS A DIVERGENCE FROM
# UPSTREAM DRESSED AS A PASS: upstream's `:163` refuses at a WEAK meet, so the scan
# CONTINUES and upstream's `:178` (`x * 0` -> 0) answers a CONST 0.  MEASURED
# against `tinygrad.uop.symbolic.sym` at the pin: `MUL(CAST(CONST(3), weakint),
# CONST(0))` answers `c0` and NOT `None`.  **THE ROW NOW ASKS THE RIGHT QUESTION --
# THE PORT REWRITES -- AND IT IS GREEN FOR UPSTREAM'S REASON AND NOT THE PORT'S.**
# The answer is a node in the arena the rewrite GREW, and the port's renderer reads
# an index against the arena it was HANDED, so the row cannot pin the index; the
# ORACLE (`gates/symrules-oracle.py`) is what pins the answer, and it says `c0`.
def t_promo_c0() -> U32: Bool.to_u32(Maybe.is_some(&1, U32, sym(fx_of(fx_prom0()), 4)))

# `tflo` answers node 2 -- `y`, the node the CAST already sits over -- so the
# unpack MINTS NOTHING on the low side too.
def t_tflo() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_tflo()), 9), 2))

# `tfhi` answers node 3, which is `CAST(x, uint64)` -- the very node `x` sits
# under, because `mixin/dtype.py:19`'s `cast` is `self if self.dtype == dt else
# UOp(Ops.CAST,...)` and `x`'s dtype is uint32. `tfhi_cast` is that claim as a
# dtype rather than as an index.
def t_tfhi() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_tfhi()), 10), 3))

def t_tfhi_cast() -> U32: Bool.to_u32(sy_dt_is(fx_of(fx_tfhi()), 3, S.uint64()))

def t_recip3() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recip3()), 4), 7))

def t_recip3x() -> U32: Bool.to_u32(Maybe.is_none(&1, U32, sym(fx_of(fx_recip3x()), 5)))

# `recipc` AND `recipc0` ASK FOR THE SAME INDEX, and that is the claim: the answer
# is `MUL(R(x), R(c))` whichever way round the two srcs arrive, because `Pair`
# picks the CONST rather than the position.
def t_recipc() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recipc()), 4), 7))

def t_recipc0() -> U32: Bool.to_u32(eq_u(sym(fx_of(fx_recipc0()), 4), 7))

# THE THREE DTYPE-SET COUNTS, against CPython's own `len(dtypes.ints)`, which is
# EIGHT, and `ints + (bool, weakint)` = TEN and `ints + (weakint,)` = NINE. A COUNT
# because a MISSPELLED entry in a list is invisible to any boolean over one dtype,
# and it is a count over the LIST rather than over a predicate so that a DROPPED
# entry and a DUPLICATED one both move it. These three lists REPLACED a pair of
# hand-written `Bool.or` chains that answered SIX and FIVE.
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
# has NINETEEN and the excluded one is THREEFRY. A COUNT because the set is a
# `pdict` KEY, so a dropped op makes a rule UNFIREABLE and a spurious one makes it
# fire where Python does not -- and a boolean over one op sees neither.
def op_count.go(os: List<&2, O.Op>, n: Nat) -> Nat:
  match os:
    case Nil{}: n
    case _ <> t: op_count.go(t, Nat.add(n, 1n))

def t_bin3f_n() -> U32: U32.from_nat(op_count.go(OP_BINARY_3F(), 0n))

def promo_row() -> Bool: Bool.pick(Bool, p_weak(fx_of(fx_add0()), 1), True{}, False{})

def t_promo() -> U32: Bool.to_u32(promo_row())

# NOT PORTED, one line each, and the WALL each one is behind. The Python line
# numbers are `symbolic.py`'s, so this list diffs against it line for line and
# `grep "TODO(p3)" tinybendygrad/uop/symbolic.bend` is the work queue. THE
# `skip=104` ROW IS THE ARITHMETIC OF THIS BLOCK: 127 is what symbolic.py's own
# blocks imply and 23 is what the table holds, so 104 are named here, and
# `len_dec` is the row that says the DECLARED length and the table agree -- which
# is what makes `sym_table_len` live rather than a comment with a type.
#
# CLOSED SINCE THE LAST PASS, and the two sentences under each are what the closure
# cost, because the WALL each was filed behind turned out SMALLER than its note
# said. That is the finding, and it is the reason this block is shorter.
#   :124, :135, :136, :144, :146, :160, :192, :194, :464, :465 -- PORTED as `sym_127`
#   through `sym_464`, TEN rules, THIRTY gate rows, and the ONE fact they all needed
#   was `UPat.alu`'s commutative LIST src (`Sw`). `modb`/`modb0` is `:124` and
#   `recip3`/`recip3x` is `:464`; the two `recipc` rows are the SAME INDEX from two
#   fixtures, which is the claim that the answer does not depend on the src order.
#   The two I64 mask tests are on the int32 lane `const_i32` states, which is exact
#   for every constant that HAS a `U32`; the shift amount is additionally held to
#   `0 <= k <= 31`, because `U32.shln` saturates to 0 past 31 where Python's
#   `1 << 32` is `2**32`. That is the ONLY place the two readings part company and
#   it answers "no rewrite" rather than a wrong shift -- `shr0` says so.
#   :192 AND :194 BOTH answer nodes that were ALREADY THERE, so both mint nothing:
#   :194's `x.cast(uint64)` IS the node `x` sits under, because `mixin/dtype.py:19`'s
#   `cast` is `self if self.dtype == dt else UOp(Ops.CAST, ...)`. `tflo`, `tfhi`
#   and `tfhi_cast` are the three rows and `tfhi = 3` IS the no-mint claim.
#   :160 REFUSES at a SEALED dtype -- `DType.const` is a C-effect seam at float16,
#   bfloat16 and the four fp8s -- rather than committing an unrounded CONST. Python
#   rewrites there. `weak.bend`'s `wk_blocked` is the same policy applied to a rule
#   that lives here, and `promo_c0` is the row for the case that IS answered.
#   AND `dtypes.ints` is EIGHT concrete widths, not four: the dtype-set helpers
#   here answered SIX and FIVE, which is an UNDER-approximation -- a rule gated on
#   one skips a node Python rewrites, silently. See the header. `ints_n`,
#   `intish_n` and `intweak_n` are the rows and the oracle is CPython's own
#   `len(dtypes.ints)`.
#   :192/:194 were filed as needing "a four-way disjunction per rule" because the
#   two rules disagree about WHICH src is the UNNAMED var. THEY DO NOT. A `UPat.var`
#   with no name is still DTYPE-CONSTRAINED, so the dtype pins it; what IS true is
#   that the `|` permutes, so the SHL is `Sw`'s `a` -- one disjunction, shared, and
#   `p_shl` is it.
#   :463-468 is now 3 of 5. What is left of it is `:466`-`:468`, and those are
#   behind the PROMOTION and not behind an engine: each answer is `1 - d`, which is
#   `mixin/elementwise.py`'s `__rsub__` = `SUB(CONST(1), d)` AT THE PROMOTED DTYPE,
#   so a float `d` and a weakint `1` meet in the lattice this file does not have.
#
# THE FOUR THAT ARE GENUINELY UNAVAILABLE, and they are all P3 or later.
# TODO(p3) symbolic.py:207 def lt_folding -- `u.const_factor()` (-> `divides` ->
#   `gcd`), `sum(u.vmin for u in p)` and `sum(u.vmax for u in p)`. Two of the
#   three are `_min_max` (ops.py:1104, the largest single piece `fold.bend`
#   defers). P3.
# TODO(p3) symbolic.py:214 def canonicalize_simplex -- `u.vmin >= 0` and
#   `GroupOp.Irreducible`, i.e. `_min_max` again. P3.
# TODO(p3) symbolic.py:233 def fold_where_closure -- `bool_slice`
#   (ops.py:290, a frozenset union down the srcs), `op_in_backward_slice_with_self`
#   (a toposort plus a pop) and `substitute` + `simplify` (which are
#   `graph_rewrite`). P3, and it is the largest single unlock after `_min_max`.
# TODO(p3) symbolic.py:240-325  symbol=symbolic  -- ALL 47. Every one of the 47
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
# TODO(p3) symbolic.py:451  symbol=sym  the `xpow` rule -- `xpow` is
#   `tinygrad/codegen/decomp/transcendental.py`, a foreign import (symbolic.py:12
#   says "TODO: symbolic shouldn't be importing from codegen"). It is seven UOp
#   expressions and every one of them needs `log2`/`exp2`/`cast`/`mod`/`where`
#   sugar this file does not have. P3, and it is owned by the transcendental
#   unit.
# TODO(p3) symbolic.py:454-462 the four load/store folding rules -- `UOp.index`,
#   `UOp.valid`, `UOp.store` with a `ConstType` src and `UOp.load`, all of which
#   are `movement.bend`'s and `weak.bend`'s (both now present in the tree, both
#   concurrent work, neither read as authoritative here). P3.
# TODO(p3) symbolic.py:465-467  symbol=sym  the three `1 - d` reciprocal rules -- and the wall is
#   the PROMOTION, not an engine. `:472`'s `-(x+y)` and `:474`'s `(x+y)*c` below are
#   the same two facts. `1 - d` is `mixin/elementwise.py`'s `__rsub__` =
#   `SUB(CONST(1), d)` AT THE PROMOTED DTYPE.
# TODO(p3) symbolic.py:472-474 `-(x+y)` and `(x+y)*c -> x*c+y*c` -- after this pass
#   the reason is sharper than "budget". `:472` is `-1 * (x + y)` and `__rmul__`
#   puts the CONST at src[0], so the pattern is a PERMUTATION of `sym_120`'s; and
#   `:474`'s answer DEPENDS ON the missing promotion for a second reason beyond
#   the caveat, because `x*c` with a weakint `x` and an int32 `c` meets at int32
#   and `mul` commits BOTH. Both are one `Sw` and one `mint_*` chain away and
#   neither is a wall; they are the next two rows of this table.
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
#   0. NOTHING NEW IS NEEDED to write the next twenty rules of `symbolic_simple`.
#      `Sw`, `Mc`, `const_i32`, `i32_fits`, `p_or2`, `p_shl32` and the `mint_*`
#      chain are the substrate the remaining rules want and they are all here, so
#      the next items in that block are a DTYPE question and not an engine one.
#   1. `_min_max` (ops.py:1104) unblocks `lt_folding`, `canonicalize_simplex`,
#      `reduce_mul_chain`, `parse_valid`, `uop_given_valid`, `_valid_priority`,
#      `simplify_valid`, `gated_given_valid` and about half of `symbolic`'s 47 --
#      nine of the fourteen deferred blocks. It is `fold.bend`'s biggest piece.
#   2. **`UOp.ranges` IS PORTED** (`fold.bend:5271`), so this line was false; what
#      `lift_reduce_gate` actually needs is `UOp.uprod` and an `RTable` buildable in a rule
#      body -- see row 7 above. The set algebra does unblock
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
# | M3 `sym_123.pat` drops the `x // x` REBIND identity check | `rebind0` | 1 |
# | M4 `sym_try`'s `claimed and early` -> `or` | `rebind0` | 1 |
# | M5 `rm_try`'s `claimed and early` -> `or` | NOTHING | 0 |
# | M6 `const_i64`'s `is_eq` -> `not is_eq` | `selfadd`, `xorb`, `xorb0` | 3 |
# | M7 `exec_alu.pick`'s Invalid poison `and` -> `not` | `alu_big` | 1 |
# | M8 `i32_fdiv.step` drops the `r != 0` half of its guard | `fdiv_i` | 1 |
# | M9 `sym_table` tag 3's reject set -> `Nil{}` | `rej` | 1 |
# | M10 `sym_dispatch.go` tag 0 -> tag 1 (a MIS-SPELLED tag) | `bcast` | 1 |
# | M11 `p_rebind2` drops the REBIND identity check -- ONE edit, and it is the
# |    reason `sym_126` and `sym_127` share the def | `xorb0`, `modb0` | 2 |
# | M12 `i64_fits_i32`'s `Bool.not(i64_big(i))` -> `i64_big(i)` | `alu` | 1 |
# | M13 `p_mul3.ok` drops the `MUL(MUL(v,v),v)` SIBLING identity check (`sym_463`)
# |    | `recip3x` | 1 |
# | M14 `sym_464.pat`'s `Sw.ok(p)` -> `True{}` -- the cvar test of `:465` | NOTHING,
# |    and it is a REAL GAP: with the test gone, `recipc0`'s fixture has BOTH srcs
# |    CONST and `sw.a`'s "first permutation wins" pick is all that is left, so the
# |    answer is the same index and nothing moves. `recipc`/`recipc0` are therefore
# |    a claim about the ANSWER and NOT about the guard. The guard's own row would be
# |    one over a `MUL(var, var)` fixture, which `:465` must not match |
# | M15 `sym_147.gate`'s `U32.is_le(Mc.k(c), 31)` -> `U32.is_le(Mc.k(c), 63)` |
# |    NOTHING on these fixtures, because `U32.shln` saturates at 31 and `k = 4` is
# |    inside both ranges. The row that would see it needs a `k = 32` fixture, so
# |    the honest statement is that the guard is UNTESTED and not that it works |
# | M16 `mint_bin`'s arena read `O.Found.ar(f)` -> a re-read of `sy_ar(x)`, i.e. the
# |    un-threaded mint `sym_93` and `sym_462` still use | NOTHING HERE, and the
# |    measurement is the point: with the FIXTURES also un-threaded (`f_alu2`'s
# |    `Found.ar(f)`) three of them answered a node one short and `Arena.next` came
# |    out LOW. A node count is the ONLY thing that sees a stale arena, and every
# |    index in the gate above is therefore a claim about a threaded mint |
# | M17 `sym_444.hit`'s flattened src list -> `List.tail`, so the FIRST src is dropped
# |    and the rule still fires | `sinkgrp` | 1 | **AND `sink` DID NOT MOVE.** This
# |    is the row the pair was added for: `sink` reads a SLOT (`eq_u(..., 6)`), a
# |    wrong src list mints a fresh node and still lands on 6, and `sinkgrp` answers
# |    the PRE-INTERNED `SINK(a, b)` so a wrong list cannot hit it |
# | M18 `sink_srcs.of`'s `Bool.pick` -> `[s]`, the flatten removed | `sink`,
# |    `sinkgrp` | 2 |
# | M21 `sink_srcs.of` always flattens | `sinkgrp` | 1 | one half of M22, and `sink`
# |    does not move for the reason M17 gives |
# | M20 `sym_444.pat` drops `any_sink_like` alone | NOTHING | 0 | **AN HONEST NEGATIVE
# |    AND THE INTERESTING ONE**: the rebuild of a sink-like-free SINK is
# |    byte-identical to its input, `UOp.new` interns it back onto the same slot and
# |    `sy_novel` swallows it, so that half of the test is REDUNDANT rather than
# |    merely untested. CPython's `if any(...) else None` is redundant the same way,
# |    because `rewrite` also tests `ret is not uop`. No fixture can move it |
# | M22 M20 AND M21 together, both halves of the sink-like test | `sinkgrp`,
# |    `sinkgrp0` | 2 | so `sinkgrp0` is not vacuous -- but it takes TWO edits, which
# |    is the price of a guard that shares a test with the body |
#
# WHAT THE TABLE SAYS, in five lines.
#   * M2 AND M5 MOVED NOTHING, and both are honest negatives. No rule in this
#     table returns its matched node, so `sy_novel` has no witness yet; and
#     `rm_table`'s two reject sets are violated by no fixture, so M5 is
#     unreachable. The second is a FIXTURE GAP, not a property of the code.
#   * M11 IS THE ONE MUTATION THAT MOVES TWO ROWS, and it moves them because
#     `p_rebind2` is SHARED by `sym_126` and `sym_127`: one edit removes the identity
#     check for `(x^y)^y` AND for `(x%y)%y`. That is the whole argument for hoisting
#     the shape, measured rather than asserted.
#   * M16 MOVED NOTHING HERE and its measurement is the useful part: the un-threaded
#     mint produced a node count that was LOW, and a node count is the only symptom
#     a stale arena has. `Arena.next` on a fixture is a row nobody had thought to
#     want, and it is what found three broken fixtures.
#   * M3 AND M11 ARE THE SAME SHAPE, both localised to their own NEGATIVE row:
#     `rebind0` and `xorb0`, never `rebind`/`xorb`. A positive rebind row is worth
#     nothing on its own; only the two-sided fixture can see the identity check go.
#   * M6 is the only mutation with three rows, all three the constant-shape tests,
#     because `sym_120.pat`'s `UPat.const(0)` and `sym_126`'s shape share `const_i64`.
#   * M9 AND M10 ARE THE TWO ROWS THAT EXIST ONLY FOR A MIS-SPELLING: a COUNT is
#     the only witness for a reject set, and only tag 0's fixture witnesses a tag.
#   * M12 IS THE ONLY MUTATION THAT WAS A LIVE BUG rather than a probe: it took
#     `alu` from 1 to 0 and it took the DEVICE with it -- `exec_alu2(MUL, int32,
#     [CInt(6), CInt(7)])` answers `CInt(42)` with the fix and `None{}` without it.
#     One row is the whole sensitivity, so `alu` is the only witness the lane
#     selector has; the two divergences listed at `exec_alu.pick` move NO row.
# THE ROW `:87`/`:88` DID NOT HAVE. Both bodies carry the gate's OWN `src[2]` (the `Invalid`
# const) into the answer, and that was RIGHT BY CONSTRUCTION -- the body passes
# `O.Arena.src(ar, g, 2)` -- with no row saying so. A CLAIM THAT RESTS ON THE SHAPE OF THE CODE
# THAT MAKES IT IS NOT A MEASUREMENT, so this builds `(cond ? x : Invalid) + y`, rewrites it, and
# asks whether the ANSWER's third src is the invalid const.
def t_ig_src2.of(m: Maybe<&1, O.Found>) -> U32:
  match m:
    case None{}: 0
    case Some{+f}:
      +i = O.Found.i(f)
      +a2 = O.Found.ar(f)
      Bool.to_u32(Bool.and(U32.is_eq(O.Arena.nsrc(a2, i), 3),
                           sy_is_invalid_const(F.folded(a2), O.Arena.src(a2, i, 2))))

def t_ig_src2() -> U32:
  +gi  = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
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
    row("max_i", t_max_i())
    p : Unit <- row("cdiv_neg", t_cdiv_neg())
    q : Unit <- row("inval", t_inval())
    r : Unit <- row("inval_st", t_inval_st())
    s : Unit <- row("inval_n", t_inval_n())
    u : Unit <- row("selfadd", t_selfadd())
    v : Unit <- row("rebind", t_rebind())
    w : Unit <- row("rebind0", t_rebind0())
    y : Unit <- row("sink", t_sink())
    z : Unit <- row("rm_where", t_rm_where())
    row("rm_stack", t_rm_stack())
    row("xorb", t_xorb())
    row("xorb0", t_xorb0())
    row("bcast", t_bcast())
    row("sinkgrp", t_sinkgrp())
    row("sinkgrp0", t_sinkgrp0())
    row("promo", t_promo())
    row("modb", t_modb())
    row("modb0", t_modb0())
    row("ne0", t_ne0())
    row("ne1", t_ne1())
    row("ne2", t_ne2())
    row("ne0r", t_ne0r())
    row("trunc", t_trunc())
    row("trunc0", t_trunc0())
    row("shr", t_shr())
    row("shr0", t_shr0())
    row("fdivm", t_fdivm())
    row("fdivm0", t_fdivm0())
    row("promo_c", t_promo_c())
    row("promo_c0", t_promo_c0())
    row("tflo", t_tflo())
    row("tfhi", t_tfhi())
    row("tfhi_cast", t_tfhi_cast())
    row("recip3", t_recip3())
    row("recip3x", t_recip3x())
    row("recipc", t_recipc())
    row("recipc0", t_recipc0())
    row("ints_n", t_ints_n())
    row("intish_n", t_intish_n())
    row("intweak_n", t_intweak_n())
    row("bin3f_n", t_bin3f_n())
    row("len_dec", t_len_dec())
    row("len_dec_rm", t_len_dec_rm())
    row("ig87_src2", t_ig_src2())

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

def fz_cls.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 0
    case Chr{u} <> _t: fz_cls.pick(u)

def fz_cls(+cs: List<&2, Char>) -> U32: fz_cls.at(cs)

def fz_tok.tok(w: String, hd: U32) -> Tok:
  match hd:
    case 1: THead{w}
    case _: TLeaf{w}

# THE SCANNER, AND IT IS THE THIRD SHAPE OF IT IN THIS FILE. `hd` is a flag that
# says the NEXT word is a node HEAD: `(` sets it, every other character clears it,
# and a word is emitted the moment its terminator arrives -- a `)` emits the word AND
# a close together, and the end of the line emits the word and STOPS.
#
# THE TWO SHAPES IT REPLACED, and both are the same fault read two ways. The mode
# `md` was the class of the word just EMITTED and had exactly one edge INTO 2 -- its
# own self-loop -- so with the scan starting at `md = 0` the value 2 was UNREACHABLE
# and `fz_tok.tok`'s `THead` arm was dead code: every op name in a case file arrived
# as a leaf. MEASURED on `(add c7 c0)` before the fix, `fz_run` answered
# `root=1 n=2 op=Ops.CONST selfadd=0 sym=norewrite rm=norewrite` -- a CONST where the
# s-expr says ADD. The second shape then emitted one `TClose` per unit of fuel on the
# empty tail, which is 4096 closes for a 12-character input and a lane whose cost is
# set by its fuel rather than by its case. `hd` has neither fault, and it is the same
# algorithm `gates/sym_graph_census.bend`'s `tk.at` runs, which is the copy MEASURED
# there -- the duplication is named rather than left to be rediscovered.
def fz_tk.put(w: String, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  match hd:
    case 1: List.append(&2, Tok, acc, [THead{w}])
    case _: List.append(&2, Tok, acc, [TLeaf{w}])

def fz_tk.flush(w: List<&2, Char>, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  match w:
    case Nil{}: acc
    case _: fz_tk.put(String.from_list(w), hd, acc)

def fz_tk.close(w: List<&2, Char>, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  List.append(&2, Tok, fz_tk.flush(w, hd, acc), [TClose{}])

# THE PARAMETER ORDER IS LOAD-BEARING: Bend matches parameters in DECLARATION order, so
# a def that matches its fuel may not then match a parameter declared before it. `n`
# is first for exactly that reason and the class comes second for the same one.
def fz_tok(n: Nat, k: U32, +s: List<&2, Char>, acc: List<&2, Tok>, w: List<&2, Char>, +hd: U32) -> List<&2, Tok>:
  match n:
    case 0n: fz_tk.flush(w, hd, acc)
    case 1n+p:
      match k:
        case 0: fz_tk.flush(w, hd, acc)
        case 1: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), fz_tk.close(w, hd, acc), Nil{}, hd)
        case 2: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), acc, Nil{}, 1)
        case 3: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), fz_tk.flush(w, hd, acc), Nil{}, 0)
        case _: match s:
          case Nil{}: fz_tk.flush(w, hd, acc)
          case c <> t: fz_tok(p, fz_cls(t), t, acc, List.append(&2, Char, w, [c]), hd)

def fz_toks(+s: String) -> List<&2, Tok>:
  fz_tok(4096n, fz_cls(String.to_list(s)), String.to_list(s), Nil{}, Nil{}, 0)

# THE VOCABULARY. A head token is the op's own `Ops.name` in lower case, so a typo
# cannot hide: the driver PRINTS `Ops.name`, so a head it did not recognise comes
# back as `NOOP`.
# THE DTYPE SET THE CASE FILE CAN NAME, and it is the whole of `spec.bend`'s, because a
# pattern's dtype constraint is written in the FIXTURE: `:186` asks `can_lossless_cast(b, a)`
# and a corpus that could only say `i32` could not state a lossless or a lossy pair at all.
def fz_dt(nm: String) -> S.Dt:
  match nm:
    case "weakint": S.weakint()
    case "bool": S.boolean()
    case "i8": S.int8()
    case "u8": S.uint8()
    case "i16": S.int16()
    case "u16": S.uint16()
    case "i32": S.int32()
    case "u32": S.uint32()
    case "i64": S.int64()
    case "u64": S.uint64()
    case "f16": S.half()
    case "bf16": S.bfloat16()
    case "f32": S.single()
    case "f64": S.double()
    case "weakfloat": S.weakfloat()
    case _: S.void()

def fz_dtnm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def fz_part(nm: String, k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(nm, Char.from_u32(58)), k), "")

def fz_op(nm: String) -> O.Op:
  match nm:
    case "noop": O.OpsNOOP{}
    case "sink": O.OpsSINK{}
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
    case "range": O.OpsRANGE{}
    case "after": O.OpsAFTER{}
    case "end": O.OpsEND{}
    case "barrier": O.OpsBARRIER{}
    case "reduce": O.OpsREDUCE{}
    case "param": O.OpsPARAM{}
    case "shrink": O.OpsSHRINK{}
    case "reshape": O.OpsRESHAPE{}
    case "permute": O.OpsPERMUTE{}
    case "mulacc": O.OpsMULACC{}
    # TODO(p2): AN UNKNOWN OP NAME IS A SILENT NOOP, so a misspelt fixture builds the wrong
    # graph and reports `norewrite`. Reproduced 2026-11-03 on `(range c8)`, which the reader
    # could not name and turned into a NOOP instead of refusing. The fix is a `Maybe` answer
    # through `fz_build`, and the case file should never be able to state an op nobody has.
    case _: O.OpsNOOP{}

def fz_arg.dt.of(dt: S.Dt) -> O.Arg:
  match dt:
    case S.Dt{0, 0, S.CVoid{}, _}: O.ANone{}
    case _: O.ADt{dt}

# A REDUCE'S SUFFIX IS ITS ROP AND NOT A DTYPE, and it is the one op whose arg is a PAIR:
# `(reduce:add x (range c8))` states `AReduce{OpsADD, 1}`, with the axis count read off the
# srcs because `num_axes` IS `len(srcs)-1` -- `UPat(...).reduce()` writes `(op, 0)` and a real
# graph writes the count. A suffix-less `(reduce ...)` is `ANone`, which is Python's `arg=None`.
# A `match` CANNOT SCRUTINISE A COMPUTED VALUE, so the suffix is handed to its own def.
def fz_arg.rop2(r: String, n: U32) -> O.Arg:
  match r:
    case "": O.ANone{}
    case _ : O.AReduce{fz_op(r), U32.sub(n, 1)}

def fz_arg.rop(nm: String, n: U32) -> O.Arg: fz_arg.rop2(fz_part(nm, 1n), n)

def fz_arg(op: O.Op, nm: String, n: U32) -> O.Arg:
  match op:
    case O.OpsCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case O.OpsBITCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case O.OpsREDUCE{}: fz_arg.rop(nm, n)
    case _: O.ANone{}


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
    # THE UPDATED FRAME GOES BACK ON TOP for the same reason `fz_build.one`'s head arm
    # does: appending it to `u` moved it BELOW the frames still open, so the next leaf
    # was delivered to the parent. MEASURED on `(sink (group x) c2)` with the head arm
    # fixed and this one not, the root answered `op=Ops.GROUP` where the s-expr says
    # SINK -- the GROUP was still on the stack when the last `)` closed it again.
    case +f <> u: St{St.ar(st), List.append(&2, Frm, [Frm{List.append(&2, U32, Frm.srcs(f), [i]), Frm.head(f)}], u), St.root(st)}
    case Nil{}: St{St.ar(st), Nil{}, Some{i}}

def fz_deliver(+st: St, i: U32) -> St: fz_deliver.at(St.stk(st), st, i)

# A node is closed, so BUILD it and hand it to the frame above. The arena and the
# index both come out of the one `Found`, which is why this is one def.
def fz_close.give(+f: O.Found, u: List<&2, Frm>, r: Maybe<&2, U32>) -> St:
  fz_deliver(St{O.Found.ar(f), u, r}, O.Found.i(f))

def fz_close.new.of(+op: O.Op, ar: O.Arena, nm: String, +srcs: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, op, srcs, fz_arg(op, nm, U32.from_nat(List.length(&2, U32, srcs))), O.TNone{})

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

# `UOp.variable` -- ops.py:1055, "a Variable is a scalar ALU PARAM with a name
# and a value range", which is the whole of the `ParamArg` this driver states.
# THE NAME AND THE ARENA ARE PARAMETERS, and both used to be literals: `Some{"v"}`
# and `O.Arena.empty()`. A case file therefore could not say `x` AND `y`, and the
# rebind rules -- `(x^y)^y` (symbolic.py:123), `(x%y)%y` (:124), `(x*x*x).recip()`
# (:464) -- carry an IDENTITY CHECK as their whole guard, so a corpus that cannot
# name two variables cannot state a positive and a negative for any of them. The
# arena mattered too: minting every variable into `Arena.empty()` put each one at
# the same index, so `x` and `y` would have been ONE node.
def fz_var(+ar: O.Arena, +nm: String, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{O.ParamArg.no_slot(), dt, Some{O.PyRange{H.i64_of_hi_lo(0, 0), H.i64_of_i32(100)}}, Some{1}, Some{nm}, S.Aalu{},
      None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# The four CONST spellings and the four VARIABLE dtypes. A leaf is interned into
# the arena the state already carries, so a repeated `c7` in one case is ONE
# node -- which is what makes `x // x` and `x // y` distinguishable at all.
def fz_leaf.var(+ar: O.Arena, +w: String, dt: S.Dt) -> O.Found: fz_var(ar, w, dt)

# `x` weakint, `xb` bool, `xf` weakfloat, `xi` int32 -- the dtype is the LAST
# character and the NAME is the whole word, so `x` and `y` are two variables at ONE
# dtype and `xi` is a third node whose dtype is int32. `y` at bool is `yb`.
def fz_lastu.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case Chr{u} <> _: u

def fz_lastu(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case _ <> t: fz_lastu.at(t)

def fz_vdt.at(u: U32) -> S.Dt:
  match u:
    case 98: S.boolean()
    case 102: S.weakfloat()
    case 105: S.int32()
    case _: S.weakint()

def fz_vdt(w: List<&2, Char>) -> S.Dt: fz_vdt.at(fz_lastu(w))

# THE CONST/VARIABLE SPLIT IS THE HEAD CHARACTER, and it is `c`/`n`/one of the three
# fixed spellings rather than a fixed list of names -- so `x` and `y` are two
# variables at ONE dtype and `c7`/`n7` stay the two int CONSTs. `fz_code` is the head.
def fz_is_cst(+w: String) -> Bool:
  Bool.or(String.eq(w, "bt"), Bool.or(String.eq(w, "bf"),
    Bool.or(String.eq(w, "bad"), Bool.or(U32.is_eq(fz_code(w), 99), U32.is_eq(fz_code(w), 110)))))

def fz_leaf.go.at(cst: Bool, +ar: O.Arena, +w: String) -> O.Found:
  match cst:
    case True{}:
      match w:
        case "bad": O.UOp.const(ar, O.CInvalid{})
        case "bt": O.UOp.const(ar, O.CBool{True{}})
        case "bf": O.UOp.const(ar, O.CBool{False{}})
        case _: fz_leaf.sgn(fz_code(w), w, ar)
    case _: fz_leaf.var(ar, w, fz_vdt(String.to_list(w)))

def fz_leaf.go(+ar: O.Arena, +w: String) -> O.Found: fz_leaf.go.at(fz_is_cst(w), ar, w)

def fz_leaf(+st: St, w: String) -> O.Found: fz_leaf.go(St.ar(st), w)

def fz_build.one(t: Tok, +st: St) -> St:
  match t:
    # A FRAME GOES ON TOP, and `List.append(&2, Frm, [f], St.stk(st))` is the whole of
    # "on top": appending the new frame to the END put it BELOW the open ones, so every
    # case with NESTING built a different graph. MEASURED on `(xor (xor x c5) c5)`
    # before/after, `O.Arena.srcs` on the root read `2 3 2` and reads `3 2`: the inner
    # XOR had been given NO src and the outer three, one of them its own output. The
    # flat cases (`(add c7 c0)`, `(group x)`) were right either way, which is why one
    # corpus row out of two looked healthy.
    case THead{w}: St{St.ar(st), List.append(&2, Frm, [Frm{Nil{}, w}], St.stk(st)), St.root(st)}
    case TLeaf{w}: fz_close.give(fz_leaf(st, w), St.stk(st), St.root(st))
    case TClose{}: fz_close(st)

def fz_build(ts: List<&2, Tok>, +st: St) -> St:
  match ts:
    case Nil{}: st
    case t <> r: fz_build(r, fz_build.one(t, st))

# THE CANONICAL FORM IS THE SAME S-EXPR, and `x.op.name.lower()` is why `render.bend`'s
# `op_lower` is imported: `Ops.name` is the `Ops.MUL` form and the oracle spells `mul`.
#
# THE ORDER IS FREE, and that is the point: hash-consing puts a node's srcs BEFORE it, so
# slot `i`'s text reads only slots `< i` and ONE left-to-right pass renders every node
# exactly once. The job-list this replaces pushed each child's open frame AND the child's
# own frame and closed every leaf, so `(reciprocal (mul x x))` printed
# `(mul (reciprocal (reciprocal xx))))` -- MEASURED 2026-11-03, and the reason no case had
# ever compared a non-leaf answer.
def fz_render.i64.of(i: H.I64, neg: Bool) -> String:
  match neg:
    case True{}: String.concat(["n", U32.show(U32.sub(0, H.lo32(i)))])
    case False{}: String.concat(["c", U32.show(H.lo32(i))])

def fz_render.i64(+i: H.I64) -> String: fz_render.i64.of(i, H.i64_is_neg(i))

# `bad` IS THE ORACLE'S WORD FOR `NOT AN INT AND NOT A BOOL`, and a FLOAT const is one:
# `symrules-oracle.py`'s `sh()` answers it for anything that is neither, because the canonical
# form states an int and a bool and nothing else. MEASURED: the oracle prints `bad` for the
# `1.0` and `-1.0` that `1-d` builds, so the port must print the same word or the two answers
# are two spellings of one graph. **THE CONSTANT'S VALUE IS NOT COMPARED** -- `1.0` and `-1.0`
# render alike on BOTH sides, so a rule that swapped them would still agree. TODO(p2): render
# the float, on both sides, in one commit.
def fz_render.cval(v: O.Const) -> String:
  match v:
    case O.CBool{b}: match b:
      case True{}: "bt"
      case False{}: "bf"
    case O.CInt{i}: fz_render.i64(i)
    case _: "bad"

def fz_render.const(a: O.Arg) -> String:
  match a:
    case O.APy{v}: fz_render.cval(v)
    case _: "?"

def fz_pname(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "?"

# A LEAF IS ITS OWN TEXT, and a PARAM PRINTS ITS NAME rather than its dtype. The
# dtype glyph `x`/`xb`/`xf`/`xi` was a stand-in for a name that did not exist, and
# with the name now in `ParamArg` it is the wrong text: two variables at ONE dtype
# would render as the same string and a canonical form that cannot tell `x` from `y`
# cannot carry a rebind rule's answer.
def fz_render.param(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: fz_pname(O.ParamArg.name(pa))
    case _: "?"

# THE OP NAME AND ITS DTYPE SUFFIX, which is `Ops.name` plus a `:` and the
# dtype when the op's arg states one. `(cast:int c7)` and `(add c7 c0)` are the
# two shapes, and the arg is the only difference.
def fz_head.sfx(a: O.Arg, nm: String) -> String:
  match a:
    case O.ADt{dt}: String.concat([nm, ":", fz_dtnm(dt)])
    case O.AReduce{rop, num_axes}: String.concat([nm, ":", R.op_lower(rop)])
    case _: nm

def fz_head.of(op: O.Op, a: O.Arg, ar: O.Arena) -> String:
  match op:
    case O.OpsCONST{}: fz_render.const(a)
    case O.OpsPARAM{}: fz_render.param(a)
    case _: fz_head.sfx(a, R.op_lower(op))

def fz_head(+ar: O.Arena, +u: U32) -> String: fz_head.of(O.Arena.op(ar, u), O.Arena.arg(ar, u), ar)

# A LEAF IS NOT A NODE WITH NO SRCS. `fz_head` answers a CONST's value and a PARAM's name
# for those two ops and the op's own name for every other, so the emitter has to ask WHICH
# rather than infer it from the src list: it opened a `(` and a space for them too, and
# `(add c7 c0)` came back as `(add (c7 ) (c0 ))`. MEASURED on `(add c7 c0)`.
def fz_leafop(+op: O.Op) -> Bool:
  Bool.or(O.eq_op(op, O.OpsCONST{}), O.eq_op(op, O.OpsPARAM{}))

def fz_txt(acc: List<&2, String>, s: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, acc, U32.to_nat(s)), "?")

def fz_srcs(ss: List<&2, U32>, +ar: O.Arena, +seen: List<&2, String>, out: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: out
    case s <> t: fz_srcs(t, ar, seen, List.append(&2, String, out, [fz_txt(seen, s)]))

def fz_node(leaf: Bool, +ar: O.Arena, +u: U32, seen: List<&2, String>) -> String:
  match leaf:
    case True{}: fz_head(ar, u)
    case _: String.concat(["(", fz_head(ar, u), " ",
      String.join(fz_srcs(O.Arena.srcs(ar, u), ar, seen, Nil{}), " "), ")"])

# THE SHRINKING ARGUMENT IS FIRST, because Bend reads a self-call's arguments left to
# right and refuses one that grows before it shrinks (`bend2-constraints` RF1).
def fz_all(slots: List<&2, Nat>, +i: Nat, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match slots:
    case Nil{}: acc
    case _ <> rest:
      +k = U32.from_nat(i)
      fz_all(rest, Nat.add(i, 1n), ar,
        List.append(&2, String, acc, [fz_node(fz_leafop(O.Arena.op(ar, k)), ar, k, acc)]))

def fz_render(+ar: O.Arena, u: U32) -> String:
  fz_txt(fz_all(List.replicate(Nat, U32.to_nat(O.Arena.next(ar)), 1n), 0n, ar, Nil{}), u)

def fz_ans.txt(ar: O.Arena, m: Maybe<&1, U32>) -> String:
  match m:
    case Some{i}: fz_render(ar, i)
    case _: "norewrite"

# THE FOUND LANE, and it is a THIRD answer rather than a replacement: `sym` answers at an
# index into the arena it was given, so a rule that MINTS (`sy_alu*` and `UOp.new` both
# grow it) leaves that index past the end and `sym` renders a slot that does not exist --
# `(Ops.NOOP`, measured on `:462`/`:463`/`:464`/`:444`. `sym_f` carries the grown arena, so
# this is the only lane in which a minting rule's answer can be COMPARED with CPython's.
# MEASURED 2026-11-03: 55 of the 84 unported rules mint, so this is the lane the rest of
# `symbolic.py` is ported in.
def fz_ans.f(ar: O.Arena, m: Maybe<&1, O.Found>) -> String:
  match m:
    case Some{+f}: fz_render(O.Found.ar(f), O.Found.i(f))
    case _: "norewrite"

# ONE CANONICAL LINE, and the two answers are the two TABLES: `sym` and `rm`
# (`pm_remove_invalid`). Two tables means two answers, and one line means the
# harness diffs one string. `symf` is the SAME `sym` table answered through the Found
# family, so the two lanes differ only in whether the arena the answer lives in is
# threaded out -- and for a non-minting rule they print the same string.
def fz_line(+ar: O.Arena, +u: U32) -> String:
  String.concat(["root=", U32.show(u), " n=", U32.show(O.Arena.next(ar)), " op=", O.Ops.name(O.Arena.op(ar, u)),
    " selfadd=", U32.show(Bool.to_u32(eq_u(sym(F.folded(ar), u), 1))),
    " sym=", fz_ans.txt(ar, sym(F.folded(ar), u)), " rm=", fz_ans.txt(ar, pm_remove_invalid(F.folded(ar), u)),
    " symf=", fz_ans.f(ar, sym_f(F.folded(ar), u))])

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

# THE CASE FILE IS A LIST OF GRAPHS, one per line as `name|<s-expr>`, and a `#` line is
# prose. ONE LINE OUT PER CASE, because `gates/symrules-oracle.py --compare` matches the two
# sides BY POSITION -- and the NAME IS THE CASE FILE'S, not the driver's: the driver reads the
# text after the `|` and prints an answer, nothing else. Before this the driver parsed the
# WHOLE FILE as one graph, so a 50-case lane returned ONE answer and the comparison could
# never be made at all (MEASURED 2026-11-03: `printed 0 rows and the case file has 50 cases`).
def fz.drive.expr(+l: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(l, '|'), 1n), l)

def fz.drive.skip(+l: String) -> Bool:
  Bool.or(String.eq(l, ""), String.starts_with(l, "#"))

def fz.drive.lines(ls: List<&2, String>, +acc: String) -> String:
  match ls:
    case Nil{}: acc
    case l <> t:
      +s = String.trim(l)
      fz.drive.lines(t, Bool.pick(String, fz.drive.skip(s), acc,
        String.concat([acc, fz_run(fz.drive.expr(s)), "\n"])))

def fz.drive.br(as: List<String>) -> IO(Unit):
  match as:
    case Nil{}: fz.gate()
    case _ <> _:
      do IO<Unit>:
        s : String <- fz_read(fz.drive.path(as))
        IO.print(fz.drive.lines(String.lines(s), ""))

def fz.drive.go(as: List<String>) -> IO(Unit):
  fz.drive.br(List.tail(&1, String, as))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    fz.drive.go(as)
