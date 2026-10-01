# decomp.bend -- tinygrad/codegen/decomp/op.py. The LOWERING DECOMPOSITIONS:
# `magicgu`/`fast_idiv`, `threefry2x32`, `floordiv_to_idiv`/`floormod_to_mod`,
# and the two rewrite tables that apply them.
#
# (The brief describes this unit as also carrying the transcendental expansions.
# It does not: those are `decomp/transcendental.py`, 277 lines, a different
# unit. `decomp/op.py` is 126 lines and has no transcendental in it. The
# inventory below is what is actually here.)
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against op.py's 126 lines.
#
#   #  PY       KIND    STATE
#   1  9-18     fold   magicgu                     PORTED IN SHAPE
#   2  20-34    fold   fast_idiv                   PORTED IN SHAPE, wall at :23
#   3  38-50    fold   threefry2x32                PORTED IN FULL
#   4  54-56    fold   floordiv_to_idiv            PORTED IN FULL
#   5  58-62    fold   floormod_to_mod             PORTED IN FULL
#   6  64       data   powers_of_two               PORTED for the 32-bit range
#   7  66-78    table  get_simplifying...          4 of 4 rules, both `ops` variants
#   8  81-126   table  get_late_rewrite...         16 of 18 rules, both variants
#
# `magicgu` and `fast_idiv` are PORTED IN SHAPE and that means: the loop, the
# guard ladder, the `dont_cast` recursion, the widen map and the `m*vmax <=
# dtype.max` test are all here and all reachable, and every one of them reports
# `None` from the ONE arithmetic primitive the substrate does not have. The
# measurement is in the `fast_idiv` block below and it is the whole of the wall:
# it is not a missing `mulhi64`, it is `_min_max` and a 65-bit `//`.
#
# ---------------------------------------------------------------------------
# TWO THINGS THAT ARE EASY TO INVERT, both measured against the real tables.
#
# 1. `powers_of_two.get(c, 0)` IS NOT A FUNCTION OF `c in powers_of_two`.
#    op.py:64 is `{2**i: i for i in range(64)}`, so `get(1, 0)` is `0` AND `1` IS
#    IN THE DICT`. The two lambdas read it differently: op.py:71 and op.py:88 and
#    op.py:92 and op.py:96 all spell `if (v := powers_of_two.get(c.val, 0))`,
#    which is a TRUTH test and `0` is falsy, while op.py:74 spells
#    `if c.val in powers_of_two`, which is a MEMBERSHIP test. So `x // 1` is NOT
#    rewritten and `x % 1` IS, on the same `c`. `dc_pow2` and `dc_is_pow2` are
#    two defs for that one dict and `s2`/`s5` are the two-sided row.
# 2. `Ops.MUL` AND `Ops.ADD` ARE `is_any` OVER BOTH ORDERS, because
#    `UPat.alu` (ops.py:1533) passes a LIST for an op in `GroupOp.Commutative`.
#    `dc_cside` is a THREE-armed disjunction and `dc_pick` is its mirror; a
#    matcher that reads src0 and src1 in one fixed order drops `l25` and `l26`
#    and typechecks.
#
# ---------------------------------------------------------------------------
# FOUR DIVERGENCES, stated rather than hidden.
#
# A. NO PROMOTION CASTS. `mixin/elementwise.py`'s `_broadcasted` inserts
#    `CAST(bool -> int)` before an `ADD`/`SUB`/`MUL` with a bool operand, and
#    `UOp.__init__`'s `dtype_from_uop` inserts `CAST(int -> bool)` on a
#    comparison. `ops.bend`'s `UOp.new` runs neither, so the trees here are the
#    ones Python prints with those CASTs deleted. This is `symbolic.bend`'s
#    wall 2 and `divandmod.bend`'s divergence A; the oracle erases them with the
#    same rule and nothing else.
# B. `x - y` IS `ADD(x, MUL(y, C(-1)))`, because `mixin/elementwise.py`'s
#    `__sub__` is `self + (other * -1)` and `ops.py`'s `UOp.__init__` does not
#    canonicalise it. `dc_sub` is that and NOT a `SUB` node, which is what
#    `out_s1` and `out_l10` are the rows for. An explicit `.alu(Ops.SUB, y)` --
#    op.py:106 -- IS a `SUB` node, and `out_l11` is the row.
# C. `powers_of_two` STOPS AT 2**31. The dict has 64 entries and the port's
#    `U32` cannot name `2**32` or above, so a 64-bit CONST divisor of `2**40`
#    is not a fixture this file can build. `s8` (`x // 2**31`) is the widest one
#    that is, and it is a real fixture.
# D. `_min_max` IS READ FOR A CONST AND A PARAM ONLY. See `dc_vmin`.
#
# ---------------------------------------------------------------------------
# THE PRINT-SHAPE. Two levels deep with CONST values printed, which is the whole
# tree for every rule here, so it is not a shortcut. A bool CONST prints as
# `C(1)` (the port has one integer Const type) and a float CONST through
# `H.f32_show`, which spells `1.0` as `1`. The oracle says both out loud.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE RESULT. A rule RETURNS THE ARENA, not a pair -- the shape `divandmod.bend`
# settled, for the same reason. The flag is a `U32` because a `Data` record
# cannot hold a `Maybe`, and the index is meaningless when the flag is 0.
# ===========================================================================
type Hit is Data:
  Hit{ar: O.Arena, i: U32, on: U32, tg: U32}

def Hit.ar(+x: Hit) -> O.Arena:
  match x:
    case Hit{ar, i, on, tg}: ar

def Hit.i(+x: Hit) -> U32:
  match x:
    case Hit{ar, i, on, tg}: i

def Hit.on(+x: Hit) -> U32:
  match x:
    case Hit{ar, i, on, tg}: on

def miss(+ar: O.Arena) -> Hit:
  Hit{ar, 0, 0, 0}

def dc_has.go(+v: U32) -> Bool:
  match v:
    case _: True{}

def dc_has(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{+v}: dc_has.go(v)
    case None{}: False{}

def dc_ival.go(m: Maybe<&2, U32>,+k: U32) -> U32:
  match m:
    case Some{+v}: v
    case None{}: k

def dc_ival(m: Maybe<&2, U32>) -> U32:
  dc_ival.go(m, 0)

# `UPat.const(1)` on op.py:125 matches `C(1.0)`, because Python's `1 == 1.0` and
# `UPat.match` (ops.py:1541) is `self.arg != uop.arg`. A port that only reads
# `CInt` would skip the FDIV rule on the very shape it is written for.
def dc_is_one.go(+v: O.Const) -> Bool:
  match v:
    case O.CInt{i}: U32.is_eq(H.lo32(i), 1)
    case O.CFloat{f}: F32.is_eq(f, 1.0)
    case O.CBool{b}: b
    case O.CInvalid{}: False{}

def dc_is_one.arg(+arg: O.Arg) -> Bool:
  match arg:
    case O.APy{v}: dc_is_one.go(v)
    case _: False{}

def dc_is_one(+ar: O.Arena,+u: U32) -> Bool:
  dc_is_one.arg(O.Arena.arg(ar, u))

# ===========================================================================
# `powers_of_two` -- op.py:64, and the two READS of it, which differ.
# `U32.log2` is a floor log, so the power-of-two test is the classic
# `c & (c - 1) == 0` and the exponent is that log. Capped at 2**31 by
# divergence C.
# ===========================================================================
def dc_pow2.bit(+c: U32) -> U32:
  U32.and(c, U32.sub(c, 1))

def dc_pow2.is(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 2), U32.is_zero(dc_pow2.bit(c)))

def dc_pow2.go(+ok: Bool, +c: U32) -> U32:
  match ok:
    case True{}: U32.from_nat(U32.log2(c))
    case False{}: 0

def dc_pow2(+c: U32) -> U32:
  dc_pow2.go(dc_pow2.is(c), c)

def dc_is_pow2.go(+ok: Bool, +c: U32) -> Bool:
  match ok:
    case True{}: True{}
    case False{}: U32.is_eq(c, 1)

def dc_is_pow2(+c: U32) -> Bool:
  dc_is_pow2.go(dc_pow2.is(c), c)

# `1 << k`, the `x.const_like(1<<n.val)` of op.py:121 and the `-c` of op.py:112
# and `c+1` of op.py:111 are all CONST VALUES, so this is a value and not a node.
def dc_powi(+n: U32) -> U32:
  U32.shln(1, U32.to_nat(n))

def dc_dt.uint(+c: S.Cls) -> Bool:
  match c:
    case S.CUint{}: True{}
    case _: False{}

def dc_dt.bool(+c: S.Cls) -> Bool:
  match c:
    case S.CBool{}: True{}
    case _: False{}

def dc_dt.flt(+c: S.Cls) -> Bool:
  match c:
    case S.CFloat{}: True{}
    case _: False{}

# ===========================================================================
# THE COMMUTATIVE SIDES. 0 = src0, 1 = src1, 2 = both or neither. A two-armed
# MATCH on the two `Bool`s, because a `match` may not scrutinise a computed
# value and the two tests are computed.
# ===========================================================================
def dc_side.go(+s0: Bool,+s1: Bool) -> U32:
  match s0 s1:
    case True{} False{}: 0
    case False{} True{}: 1
    case _ _: 2

def dc_pick(+ar: O.Arena,+u: U32,+which: U32) -> U32:
  match which:
    case 0: O.Arena.src0(ar, u)
    case _: O.Arena.src(ar, u, 1)

def dc_alu2(+ar: O.Arena,+op: O.Op,+x: U32,+y: U32) -> O.Found:
  O.UOp.alu(ar, op, [x, y])

def dc_alu3(+ar: O.Arena,+op: O.Op,+x: U32,+y: U32,+z: U32) -> O.Found:
  O.UOp.alu(ar, op, [x, y, z])

def dc_cast(+ar: O.Arena,+x: U32,+dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{dt}, O.TNone{})

def dc_cint(+ar: O.Arena,+v: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})

def dc_cflt(+ar: O.Arena,+v: F32) -> O.Found:
  O.UOp.const(ar, O.CFloat{v})

# `x + (y * -1)` -- `mixin/elementwise.py`'s `__sub__`. `C(-1)` is a CONST and
# not a NEG node: `-1` is a PyConst, and `MUL(x, UOp.const(-1))` is what
# `__mul__` builds.
def dc_m1(+ar: O.Arena,+y: U32) -> O.Found:
  +cm = dc_cint(ar, H.i32_neg(1))
  dc_alu2(O.Found.ar(cm), O.OpsMUL{}, y, O.Found.i(cm))

def dc_sub(+ar: O.Arena,+x: U32,+y: U32) -> O.Found:
  +m = dc_m1(ar, y)
  dc_alu2(O.Found.ar(m), O.OpsADD{}, x, O.Found.i(m))

# `x >> v` and `x << v` for a `v` that is a Python int, so the shift amount is a
# CONST and the node is SHR/SHL with a CONST src1.
def dc_shr(+ar: O.Arena,+x: U32,+v: U32) -> O.Found:
  +cv = dc_cint(ar, v)
  dc_alu2(O.Found.ar(cv), O.OpsSHR{}, x, O.Found.i(cv))

def dc_shl(+ar: O.Arena,+x: U32,+v: U32) -> O.Found:
  +cv = dc_cint(ar, v)
  dc_alu2(O.Found.ar(cv), O.OpsSHL{}, x, O.Found.i(cv))

# `x & (c - 1)` -- op.py:74's `c.val-1` is a Python int, so it is a CONST.
def dc_band(+ar: O.Arena,+x: U32,+k: U32) -> O.Found:
  +ck = dc_cint(ar, k)
  dc_alu2(O.Found.ar(ck), O.OpsAND{}, x, O.Found.i(ck))

def dc_cplus(+ar: O.Arena,+c: U32) -> O.Found:
  +c1 = dc_cint(ar, 1)
  dc_alu2(O.Found.ar(c1), O.OpsADD{}, c, O.Found.i(c1))

# ===========================================================================
# `(a < 0).ne(b < 0)` -- the tail of op.py:56 and the middle of op.py:62. `ne`
# on two bools is `CMPNE` and `<` against a PyConst 0 is `CMPLT(x, C(0))`.
# ===========================================================================
def dc_sgn(+a: O.Found,+b: U32) -> O.Found:
  +z = dc_cint(O.Found.ar(a), 0)
  +la = dc_alu2(O.Found.ar(z), O.OpsCMPLT{}, O.Found.i(a), O.Found.i(z))
  +lb = dc_alu2(O.Found.ar(la), O.OpsCMPLT{}, b, O.Found.i(z))
  dc_alu2(O.Found.ar(lb), O.OpsCMPNE{}, O.Found.i(la), O.Found.i(lb))

# `a.alu(CMOD, b).ne(0)`
def dc_cmod_ne(+ar: O.Arena,+a: U32,+b: U32) -> O.Found:
  +r = dc_alu2(ar, O.OpsCMOD{}, a, b)
  +z = dc_cint(O.Found.ar(r), 0)
  dc_alu2(O.Found.ar(z), O.OpsCMPNE{}, O.Found.i(r), O.Found.i(z))

# `x.vmax` for a CONST and a PARAM. `x.dtype.max` is `S.Dt.max`, and it answers
# `None{}` for every dtype WIDER THAN 32 BITS (spec.bend:207) -- which is not a
# gap here: Python's `min(x.vmax, x.dtype.max)` with a 64-bit `dtype.max` is
# `x.vmax`, because no `U32` range can reach 2**63. So `None` from `Dt.max`
# means "no tighter bound", and the min is total.
# `min` over two `Maybe`s, and `None` is IDENTITY -- "no tighter bound".
def dc_minopt.go(a: Maybe<&2, U32>, +w: U32) -> Maybe<&2, U32>:
  match a:
    case Some{+v}: Some{U32.min(v, w)}
    case None{}: None{}

def dc_minopt.put(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match b:
    case Some{+w}: dc_minopt.go(a, w)
    case None{}: a

# A PARAM's `vmax` is `arg.vmin_vmax[1]`, an `I64`, so the reader is its own def
# and not `dc_minopt`.
def dc_vmax.hi(m: Maybe<&2, O.PyRange>) -> Maybe<&2, U32>:
  match m:
    case Some{O.PyRange{lo, hi}}: Some{H.lo32(hi)}
    case None{}: None{}

def dc_vmax.const.go(m: Maybe<&2, U32>, lim: Maybe<&2, U32>) -> Maybe<&2, U32>:
  dc_minopt.put(m, lim)

def dc_vmax.param.go(+arg: O.Arg, lim: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match arg:
    case O.AParam{pa}: dc_minopt.put(dc_vmax.hi(O.ParamArg.vmin_vmax(pa)), lim)
    case _: None{}

# `min(x.vmax, x.dtype.max)` -- op.py:22's walrus.
def dc_dtmax(m: Maybe<&2, S.Dt>) -> Maybe<&2, U32>:
  match m:
    case Some{d}: S.Dt.max(d)
    case None{}: None{}

# `vmax < d` -- op.py:22. The answer is `x.const_like(0)`, which is a CONST and
# not a node, and which the fixture arena already holds so nothing grows.
def dc_idiv.zero(+ar: O.Arena,+x: U32,+d: U32,+small: Bool) -> Maybe<&2, O.Found>:
  match small:
    case True{}: Some{dc_cint(ar, 0)}
    case False{}: None{}

def dc_idiv.go(+ar: O.Arena,+x: U32,+d: U32,+bad: Bool,+small: Bool) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: dc_idiv.zero(ar, x, d, small)

def dc_tfg.pick(even: Bool, +a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  match even:
    case True{}: a
    case False{}: b

def dc_tf_half(+ar: O.Arena,+x: U32,+hi: Bool) -> O.Found:
  match hi:
    case True{}: dc_cast(O.Found.ar(dc_shr(ar, x, 32)), x, S.uint32())
    case False{}: dc_cast(ar, x, S.uint32())

# `(xr[1].cast(uint64) << 32) | xr[0].cast(uint64)` -- op.py:50. Two CASTS to
# uint64, a SHL and an OR. OR is commutative, so a matcher that fixed the order
# would be wrong; this builds the one Python builds.
def dc_tf_join(+ar: O.Arena,+hi: U32,+lo: U32) -> O.Found:
  +a = dc_cast(ar, hi, S.uint64())
  +b = dc_cast(O.Found.ar(a), lo, S.uint64())
  +s = dc_shl(O.Found.ar(b), O.Found.i(a), 32)
  dc_alu2(O.Found.ar(s), O.OpsOR{}, O.Found.i(s), O.Found.i(b))

# The `(hi, lo)` pair is bound ONCE and handed to one `H.i64_show` call, because
# `+p` needs its type to be `Data` and a `U32 & U32` pair is not.
def tf_split_str.go(m: Maybe<&1, U32 & U32>) -> String:
  match m:
    case Some{(h, l)}: H.i64_show(h, l)
    case None{}: "none"

# `len(u.src) == 2` -- the `strict_length` conjunct `UPat` carries whenever
# `src` is a tuple. Every rule in both tables has it, and it is what makes a
# three-src node skip.
def dc_isn2(+ar: O.Arena,+u: U32) -> Bool:
  U32.is_eq(O.Arena.nsrc(ar, u), 2)

# ===========================================================================
# THE LATE TABLE -- op.py:81-126. EIGHTEEN rules, and `disable_fast_idiv`
# REMOVES TWO of them (op.py:97's `if not disable_fast_idiv:` covers op.py:99
# and op.py:102) and renumbers the rest. So there are two tag spaces and both
# are measured: `nrules_l=18` and `nrules_l_noidiv=16`, and the reject sets
# `rejl0..rejl17` come from the eighteen-rule build.
#
# `0`  !x & !y      -> !(x|y)              op.py:85-86   AND    [CMPNE]
# `1`  x * 2**y     -> x << y              op.py:88      MUL    [CONST]
# `2`  u // 2**y    -> u >> y              op.py:91-92   CDIV   [CONST]
# `3`  x // 2**y    -> (x + (x<0 ? c-1:0)) >> y   op.py:94-96  CDIV [CONST]
# `4`  x // d       -> fast_idiv           op.py:99      CDIV   [CONST]
# `5`  x % d        -> x - d*fast_idiv     op.py:102-103 CMOD   [CONST]
# `6`  x * -1       -> x.alu(NEG)          op.py:105     MUL    [CONST]
# `7`  x + (-y)     -> x.alu(SUB, y)       op.py:106     ADD    [NEG]
# `8`  !(x < c)     -> c-1 < x             op.py:110     CMPNE  [CMPLT,CONST]
# `9`  !(c < x)     -> x < c+1             op.py:111     CMPNE  [CMPLT,CONST]
# `10` -x < y*c     -> y*(-c) < x          op.py:112     CMPLT  [MUL]
# `11` -x < c       -> -c < x              op.py:113     CMPLT  [CONST,MUL]
# `12` (c1<x)&(x<c2) -> x.eq(c1+1) if c1+1==c2-1  op.py:114-115 AND [CMPLT]
# `13` x.ne(y)      -> x.alu(CMPEQ, y)     op.py:117     CMPNE  [CMPNE,CONST]
# `14` a*b + c      -> a.alu(MULACC,b,c)   op.py:119     ADD    [MUL]
# `15` (x<<n) + c   -> x.alu(MULACC, 2**n, c)  op.py:121  ADD    [SHL]
# `16` x.reciprocal -> 1.0.alu(FDIV, x)    op.py:124     RECIP  []
# `17` a * (1/b)    -> a.alu(FDIV, b)      op.py:125     MUL    [FDIV]
#
# THE TWO RULES BOTH CLAIMING ONE NODE are `2`/`3`/`4`: `3` (the signed
# power-of-two CDIV) and `4` (`fast_idiv`) both claim `CDIV(x, 2**y)` and they
# answer DIFFERENTLY -- `3` is an ADD under a SHR and `4` is a MUL under a SHR.
# FIRST-WINS, and `l7`/`l8`/`l9` are the three sides: `l7` is int32 `// 4` and
# rule 3 answers, `l8` is the same on a non-negative numerator and STILL rule 3
# answers, and `l9` is `// 3` where rule 3 SKIPS on the power-of-two test and
# rule 4 answers. A last-wins scan moves `l7` and `l8` to rule 4's answer.
# ===========================================================================
def dc_l_tab(+fast: Bool) -> O.PMEntrys:
  match fast:
    case True{}: O.PMEntrys{[O.PMEntry{0,  [O.OpsAND{}],        [O.OpsCMPNE{}]},                  # 85
                           O.PMEntry{1,  [O.OpsMUL{}],        [O.OpsCONST{}]},                  # 88
                           O.PMEntry{2,  [O.OpsCDIV{}],       [O.OpsCONST{}]},                  # 91
                           O.PMEntry{3,  [O.OpsCDIV{}],       [O.OpsCONST{}]},                  # 94
                           O.PMEntry{6,  [O.OpsMUL{}],        [O.OpsCONST{}]},                  # 105
                           O.PMEntry{7,  [O.OpsADD{}],        [O.OpsNEG{}]},                    # 106
                           O.PMEntry{8,  [O.OpsCMPNE{}],      [O.OpsCMPLT{}, O.OpsCONST{}]},    # 110
                           O.PMEntry{9,  [O.OpsCMPNE{}],      [O.OpsCMPLT{}, O.OpsCONST{}]},    # 111
                           O.PMEntry{10, [O.OpsCMPLT{}],      [O.OpsMUL{}]},                    # 112
                           O.PMEntry{11, [O.OpsCMPLT{}],      [O.OpsCONST{}, O.OpsMUL{}]},      # 113
                           O.PMEntry{12, [O.OpsAND{}],        [O.OpsCMPLT{}]},                  # 114
                           O.PMEntry{13, [O.OpsCMPNE{}],      [O.OpsCMPNE{}, O.OpsCONST{}]},    # 117
                           O.PMEntry{14, [O.OpsADD{}],        [O.OpsMUL{}]},                    # 119
                           O.PMEntry{15, [O.OpsADD{}],        [O.OpsSHL{}]},                    # 121
                           O.PMEntry{16, [O.OpsRECIPROCAL{}], Nil{}},                           # 124
                           O.PMEntry{17, [O.OpsMUL{}],        [O.OpsFDIV{}]}]}                  # 125
    case False{}: O.PMEntrys{[O.PMEntry{0,  [O.OpsAND{}],        [O.OpsCMPNE{}]},                 # 85
                            O.PMEntry{1,  [O.OpsMUL{}],        [O.OpsCONST{}]},                 # 88
                            O.PMEntry{2,  [O.OpsCDIV{}],       [O.OpsCONST{}]},                 # 91
                            O.PMEntry{3,  [O.OpsCDIV{}],       [O.OpsCONST{}]},                 # 94
                            O.PMEntry{4,  [O.OpsCDIV{}],       [O.OpsCONST{}]},                 # 99
                            O.PMEntry{5,  [O.OpsCMOD{}],       [O.OpsCONST{}]},                 # 102
                            O.PMEntry{6,  [O.OpsMUL{}],        [O.OpsCONST{}]},                 # 105
                            O.PMEntry{7,  [O.OpsADD{}],        [O.OpsNEG{}]},                   # 106
                            O.PMEntry{8,  [O.OpsCMPNE{}],      [O.OpsCMPLT{}, O.OpsCONST{}]},   # 110
                            O.PMEntry{9,  [O.OpsCMPNE{}],      [O.OpsCMPLT{}, O.OpsCONST{}]},   # 111
                            O.PMEntry{10, [O.OpsCMPLT{}],      [O.OpsMUL{}]},                   # 112
                            O.PMEntry{11, [O.OpsCMPLT{}],      [O.OpsCONST{}, O.OpsMUL{}]},     # 113
                            O.PMEntry{12, [O.OpsAND{}],        [O.OpsCMPLT{}]},                 # 114
                            O.PMEntry{13, [O.OpsCMPNE{}],      [O.OpsCMPNE{}, O.OpsCONST{}]},   # 117
                            O.PMEntry{14, [O.OpsADD{}],        [O.OpsMUL{}]},                   # 119
                            O.PMEntry{15, [O.OpsADD{}],        [O.OpsSHL{}]},                   # 121
                            O.PMEntry{16, [O.OpsRECIPROCAL{}], Nil{}},                          # 124
                            O.PMEntry{17, [O.OpsMUL{}],        [O.OpsFDIV{}]}]}                 # 125

def dc_one(+which: U32) -> Bool:
  U32.is_lt(which, 2)

def dc_other(+ar: O.Arena,+u: U32,+which: U32) -> U32:
  match which:
    case 0: O.Arena.src(ar, u, 1)
    case _: O.Arena.src0(ar, u)

# Is node `s` a `CMPLT(a, b)`?
def dc_is_lt(+ar: O.Arena,+s: U32) -> Bool:
  Bool.and(O.op_is(ar, s, O.OpsCMPLT{}), dc_isn2(ar, s))

# ---- rule 0 -- op.py:85-86. `!x & !y -> !(x|y)`.
# The pattern is `UPat.var("x", dtypes.bool).logical_not() & ...`, so the AND's
# two srcs are each a `logical_not` -- a CMPNE against the bool CONST -- and the
# `dtypes.bool` conjunct is on `x`, the CMPNE's src0. THERE IS NO CAST AND THE
# READERS MAY NOT LOOK FOR ONE, on both sides and for one reason each: the
# PATTERN has none because `UPat.cast` (ops.py:1512) returns `self` when
# `self.match_dtype == (dtype,)`, which is what `UPat.var("x", dtypes.bool)`
# states, and the TREE has none because `mixin/dtype.py:19` is `self if
# self.dtype == dt else UOp(Ops.CAST, ...)` and `x` is a bool. A reader that
# steps through a CAST here reads `src0` of a PARAM -- the arena's bottom NOOP,
# index 0 -- and every fixture silently misses the rule.
def dc_l0.x(+ar: O.Arena,+u: U32) -> U32:
  O.Arena.src0(ar, O.Arena.src0(ar, u))

def dc_l0.y(+ar: O.Arena,+u: U32) -> U32:
  O.Arena.src0(ar, O.Arena.src(ar, u, 1))

# The scrutinee of the `logical_not`, which is `x` itself.
def dc_l0.x2(+ar: O.Arena,+s: U32) -> U32:
  O.Arena.src0(ar, s)

# ---- rule 1 -- op.py:88. `x * 2**y -> x << y`. MUL is an `is_any`, so the
# CONST may be EITHER src; `l1` and `l25` are the two sides. The lambda is
# `lambda c,x:` -- the captures are declared cvar-FIRST, which is why the
# fixture's `x` is `self.src0` in one and `self.src1` in the other.
def dc_l1.put(+ar: O.Arena,+x: U32,+v: U32) -> Maybe<&2, O.Found>:
  Some{dc_shl(ar, x, v)}

def dc_l5.mul(+ar: O.Arena,+self: U32,+q: O.Found) -> O.Found:
  +m = dc_alu2(ar, O.OpsMUL{}, O.Arena.src(ar, self, 1), O.Found.i(q))
  dc_sub(O.Found.ar(m), O.Arena.src0(ar, self), O.Found.i(m))

# Which side is the `NEG`, 2 for "both or neither". The reject set for this rule
# is `[NEG]` and it is NOT empty, so a wrong answer here changes which nodes the
# rule can see, and not only which answer it gives.
def dc_negside(+ar: O.Arena,+u: U32) -> U32:
  dc_side.go(O.op_is(ar, O.Arena.src0(ar, u), O.OpsNEG{}),
             O.op_is(ar, O.Arena.src(ar, u, 1), O.OpsNEG{}))

def dc_l7.x(+ar: O.Arena,+self: U32) -> U32:
  dc_other(ar, self, dc_negside(ar, self))

# `c1` and `c2` are the two CMPLTs' CONSTs and BOTH ARE TWO STEPS DEEP: the AND
# and the CMPLT. A third `src0` reads `src0` of a CONST, which is the arena's
# bottom NOOP (index 0), and `dc_val` of that is `None` -- so `dc_l12.val`
# compares `0 + 1 == c2.val - 1`, which is false for `l16` and the rule never
# answers. `c2` is the shape `c1` must have; the asymmetry was the whole bug.
def dc_l12.c1(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src0(ar, O.Arena.src0(ar, self))

def dc_l12.c2(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src(ar, O.Arena.src(ar, self, 1), 1)

# The `x` of the first conjunct. The IDENTITY CHECK is the `U32.is_eq` against
# the `x` of the second; without it the rule matches two distinct nodes.
def dc_l12.x(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src(ar, O.Arena.src0(ar, self), 1)

def dc_l13.x(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src0(ar, O.Arena.src0(ar, self))

def dc_l13.y(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src(ar, O.Arena.src0(ar, self), 1)

def dc_mulside(+ar: O.Arena,+u: U32) -> U32:
  dc_side.go(O.op_is(ar, O.Arena.src0(ar, u), O.OpsMUL{}),
             O.op_is(ar, O.Arena.src(ar, u, 1), O.OpsMUL{}))

def dc_l14.c(+ar: O.Arena,+self: U32) -> U32:
  dc_other(ar, self, dc_mulside(ar, self))

def dc_shlside(+ar: O.Arena,+u: U32) -> U32:
  dc_side.go(O.op_is(ar, O.Arena.src0(ar, u), O.OpsSHL{}),
             O.op_is(ar, O.Arena.src(ar, u, 1), O.OpsSHL{}))

def dc_l16.pat(+ar: O.Arena,+self: U32) -> Bool:
  O.op_is(ar, self, O.OpsRECIPROCAL{})

def dc_l16.one(+ar: O.Arena) -> U32:
  O.Found.i(dc_cflt(ar, 1.0))

def dc_fdside(+ar: O.Arena,+u: U32) -> U32:
  dc_side.go(O.op_is(ar, O.Arena.src0(ar, u), O.OpsFDIV{}),
             O.op_is(ar, O.Arena.src(ar, u, 1), O.OpsFDIV{}))

# ===========================================================================
# THE DISPATCH AND THE SCAN -- `spec.bend`'s shape, twice. `ops.bend` cannot
# call into this file, so each of the TWO tables gets its own dispatch and its
# own scan. This is NOT the six-fold duplication of `spec.bend`: each of its six
# tables has a different rule set, while the two `ops` VARIANTS of one table
# here have the SAME rules and differ only in which entries exist, so the scan
# takes the table as a parameter and is written once per Python function. A
# generic dispatch would need a closure, and a closure cannot be a `Data` field.
# ===========================================================================
def dc_s_fold.new(+ar: O.Arena, m: Maybe<&2, O.Found>,+tag: U32) -> Hit:
  match m:
    case Some{+f}: Hit{O.Found.ar(f), O.Found.i(f), 1, tag}
    case None{}: Hit{ar, 0, 0, 0}

# FIRST-WINS, keyed on the ACCUMULATOR -- `divandmod.bend`'s `dm_fold` again. A
# rule that hands back the node it was given does not fire (ops.py:1610's `ret
# is not uop`), and no rule here can: every one builds at least one node. So
# that half is unreachable rather than ported.
def dc_s_fold.go(+on: U32, +acc: Hit,+tag: U32, m: Maybe<&2, O.Found>) -> Hit:
  match on:
    case 1: acc
    case _: dc_s_fold.new(Hit.ar(acc), m, tag)

def dc_s_fold(+acc: Hit,+tag: U32, m: Maybe<&2, O.Found>) -> Hit:
  dc_s_fold.go(Hit.on(acc), acc, tag, m)

def dc_l_fold.new(+ar: O.Arena, m: Maybe<&2, O.Found>,+tag: U32) -> Hit:
  match m:
    case Some{+f}: Hit{O.Found.ar(f), O.Found.i(f), 1, tag}
    case None{}: Hit{ar, 0, 0, 0}

def dc_l_fold.go(+on: U32, +acc: Hit,+tag: U32, m: Maybe<&2, O.Found>) -> Hit:
  match on:
    case 1: acc
    case _: dc_l_fold.new(Hit.ar(acc), m, tag)

def dc_l_fold(+acc: Hit,+tag: U32, m: Maybe<&2, O.Found>) -> Hit:
  dc_l_fold.go(Hit.on(acc), acc, tag, m)

# `ParamArg` has thirteen fields in `ops.bend`'s declaration order, so this spells
# them out against ops.py:1015's `ParamArg(-1, dtype, name=name,
# vmin_vmax=(min_val,max_val), multiple_of=multiple_of, addrspace=AddrSpace.ALU)`.
def dcp.range(+dt: S.Dt,+mult: U32,+nm: String,+lo: U32,+vmax: U32) -> O.ParamArg:
  O.ParamArg{0, dt, Some{0}, Some{O.PyRange{H.i64_of_i32(lo), H.i64_of_i32(vmax)}},
             Some{mult}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def dcp(+dt: S.Dt,+mult: U32,+nm: String) -> O.ParamArg:
  dcp.range(dt, mult, nm, 0, 100)

def dc_lab.name(m: Maybe<&2, String>,+k: String) -> String:
  match m:
    case Some{+s}: String.concat(["P", s])
    case None{}: k

def dc_lab.bool(+b: Bool) -> String:
  match b:
    case True{}: "C(True)"
    case False{}: "C(False)"

def dc_rejlen(m: Maybe<&2, O.PMEntry>,+k: U32) -> U32:
  match m:
    case Some{+e}: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(e)))
    case None{}: k

def t_nrules_l() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(dc_l_tab(False{}))))

def t_nrules_noidiv() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(dc_l_tab(True{}))))

def row(+nm: String,+v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(+nm: String,+v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# WHICH rule fired. `tag_*` is the row that makes first-wins observable and not
# just on/off: rules 3 and 4 both claim `CDIV(x, 2**y)` and answer differently, and
# the `out_` row says which answer while the `tag_` row says it was the EARLIER
# rule. 0 means "nothing fired", which is unambiguous because the scan never
# reaches tag 0 without rule 0 firing.
def Hit.tg(+x: Hit) -> U32:
  match x:
    case Hit{ar, i, on, tg}: tg

# ===========================================================================
# `mixin/elementwise.py` IS NOT PORTED, so every operator below is the RAW
# `alu`. `dc_sub` is `__sub__`'s shape and NOT a SUB node -- divergence B.
# ===========================================================================
def dc_alu1(+ar: O.Arena,+op: O.Op,+x: U32) -> O.Found:
  O.UOp.alu(ar, op, [x])

# `c - 1` and `c + 1` for op.py:95 and op.py:110/111/115. `x < (UOp - 1)` is
# `__sub__`, so `c-1` is `ADD(c, MUL(1,-1))` and NOT a CONST, and `c+1` is
# `ADD(c, 1)`. `out_l12`/`out_l13`/`out_l16` are the rows and they show it.
def dc_cminus(+ar: O.Arena,+c: U32) -> O.Found:
  +c1 = dc_cint(ar, 1)
  +m = dc_m1(O.Found.ar(c1), O.Found.i(c1))
  dc_alu2(O.Found.ar(m), O.OpsADD{}, c, O.Found.i(m))

# `x.alu(op)` -- op.py:105, a UNARY alu and the only NEG in the file.
def dc_neg(+ar: O.Arena,+x: U32) -> O.Found:
  dc_alu1(ar, O.OpsNEG{}, x)

def dc_l5.build(+ar: O.Arena,+self: U32, m: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match m:
    case Some{+q}: Some{dc_l5.mul(ar, self, q)}
    case None{}: None{}

# ---- rule 6 -- op.py:105. `x * -1 -> x.alu(NEG)`. `MUL` is an `is_any`, and the
# operand is UNCONSTRAINED (no `dtypes` argument), so `l3` is the row. `-1` is a
# PyConst and the CONST is `C(-1)`; there is no `-1*x` and no NEG on the input.
def dc_l6.put(+ar: O.Arena,+x: U32) -> Maybe<&2, O.Found>:
  Some{dc_neg(ar, x)}

def dc_l7.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsADD{}),
    Bool.and(dc_isn2(ar, self), dc_one(dc_negside(ar, self))))

# THE IDENTITY CHECK, on its own so the mutation table has one row to move.
def dc_l12.same(+ar: O.Arena,+self: U32) -> Bool:
  U32.is_eq(dc_l12.x(ar, self), O.Arena.src0(ar, O.Arena.src(ar, self, 1)))

# ---- rule 13 -- op.py:117. `x.ne(y) -> x.alu(CMPEQ, y)`. The pattern is
# `UPat.var('x').ne(UPat.var('y')).logical_not()`, so it is a CMPNE whose scrutinee
# is a CMPNE and whose src1 is the bool CONST. NO dtype conjuncts.
def dc_l13.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_alu2(ar, O.OpsCMPEQ{}, dc_l13.x(ar, self), dc_l13.y(ar, self))}
    case False{}: None{}

def dc_l14.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsADD{}),
    Bool.and(dc_isn2(ar, self), dc_one(dc_mulside(ar, self))))

# ---- rule 16 -- op.py:124. `x.reciprocal() -> UOp.const(1.0).alu(FDIV, x)`. A
# UNARY pattern, so no `is_any` and no reject set.
def dc_l16.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_alu2(ar, O.OpsFDIV{}, dc_l16.one(ar), O.Arena.src0(ar, self))}
    case False{}: None{}

def dc_l16(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l16.go(F.Folded.ar(fx), self, dc_l16.pat(F.Folded.ar(fx), self))

def dc_l17.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsMUL{}),
    Bool.and(dc_isn2(ar, self), dc_one(dc_fdside(ar, self))))

# THE THREE COUNTS and the REJECT SETS. `dc_rejlen` is `List.length` over the
# entry's own reject set MINUS ONE, so an empty set prints 0, a one-entry set 1
# and a two-entry set 2 -- and `rejl8 = 2` is the row that says rules 8 and 9
# reject on BOTH `CMPLT` and `CONST`, which a "the reject set is the first src's
# op" simplification gets wrong.
# The EIGHTEEN-rule table, because `rejlN` is indexed by the tag of THAT one.
# `dc_l_tab(True{})` is the sixteen-rule build and its tags are renumbered, so
# reading it here shifts every reject row from `rejl6` on.
def dc_entry_l(+n: U32) -> Maybe<&2, O.PMEntry>:
  List.get(&2, O.PMEntry, O.PMEntrys.es(dc_l_tab(False{})), U32.to_nat(n))

# The join starts from the EMPTY string (`dc_rejstr.put`), so "is this the first
# name" is "is the accumulator still empty" -- and every name is at least two
# characters, so length 0 is not ambiguous with a real name.
def dc_rejstr.first(+acc: String) -> Bool:
  U32.is_eq(U32.from_nat(String.length(acc)), 0)

def dc_rejstr.put(+l: List<&2, O.Op>) -> String:
  match l:
    case Nil{}: "-"
    case _: ""

# The addend. `dc_l14.c` keys on a MUL and rule 15's other side is a SHL, so it
# needs its own name: reusing `dc_l14.c` hands back the SHL and `out_l21` then
# reads `MULACC(Pi, C(8), SHL(Pi, C(3)))`.
def dc_l15.c(+ar: O.Arena, +self: U32) -> U32:
  dc_other(ar, self, dc_shlside(ar, self))

# The src list is TWO OR THREE wide and which one depends on the op -- MULACC and
# WHERE are ternaries and the rest are binary. A fold over `Arena.srcs` would
# need a fuel walk, so the arity is a `Bool` and the list is unrolled to three,
# which covers every rule in both tables.
# `O.Arena.src(ar, u, 1)` on a ONE-src node is the arena's BOTTOM NOOP (index 0,
# from `O.Arena.empty()`), so the arity is read BEFORE any src is. `dc_isn2`
# guards the rules; the printer has to guard itself.
def dc_arity1(+ar: O.Arena, +u: U32) -> U32:
  U32.sub(U32.min(O.Arena.nsrc(ar, u), 3), 1)

# `x.ne(True)` / `(x < c).logical_not()` -- mixin/elementwise.py's `ne` and
# `logical_not`, which is `cast(bool).ne(True)`. The promotion CAST is not built
# (divergence A) so the CMPNE's src0 is read straight through.
# `x.ne(True)` -- mixin/elementwise.py:333, a CMPNE and nothing else. The
# `cast(dtypes.bool)` inside `logical_not` is NOT a node: `mixin/dtype.py:19` is
# `self if self.dtype == dt else UOp(Ops.CAST, ...)`, so on a bool the CAST is
# elided. Building one puts a CAST where Python has none (divergence A) AND makes
# rule 13 miss its own pattern -- that is the `l18` row.
def dc_ne(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  dc_alu2(ar, O.OpsCMPNE{}, x, y)

def dc_lnot(+ar: O.Arena, +x: U32) -> O.Found:
  +c = dc_cint(ar, 1)
  dc_ne(O.Found.ar(c), x, O.Found.i(c))

def dc_l0.put(+ar: O.Arena,+self: U32) -> Maybe<&2, O.Found>:
  +o = dc_alu2(ar, O.OpsOR{}, dc_l0.x(ar, self), dc_l0.y(ar, self))
  Some{dc_lnot(O.Found.ar(o), O.Found.i(o))}

def dc_l0.go(+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_l0.put(F.Folded.ar(fx), self)
    case False{}: None{}

# `x.eq(c1+1)` is `eq` = `ne(...).logical_not()` (mixin/elementwise.py:336), so
# it is `CMPNE(CMPNE(x, ADD(c1, C(1))), C(1))` -- TWO CMPNEs and an ADD that is
# NOT a folded CONST. `out_l16` is the row.
def dc_l12.build(+ar: O.Arena,+self: U32) -> O.Found:
  +s = dc_cplus(ar, dc_l12.c1(ar, self))
  +n = dc_alu2(O.Found.ar(s), O.OpsCMPNE{}, dc_l12.x(ar, self), O.Found.i(s))
  dc_lnot(O.Found.ar(n), O.Found.i(n))

def dc_l12.body(+ar: O.Arena,+self: U32,+val: Bool) -> Maybe<&2, O.Found>:
  match val:
    case True{}: Some{dc_l12.build(ar, self)}
    case False{}: None{}

# ---- rule 12 -- op.py:114-115. `(c1<x) & (x<c2) -> x.eq(c1+1)` if
# `c1.val+1 == c2.val-1`, and it is THE ONLY rule in either table with a NAME
# BOUND TWICE.
#
# `UPat.match` (ops.py:1540) is `store.setdefault(name, uop) is not uop` -> a
# rejection, and `upat.py` emits it as the literal `"{0} is {1}"`. So `x` must be
# the SAME NODE on both sides, and `l16`/`l17` are the two-sided row: `l16` binds
# it once and rewrites, `l17` binds it to two different PARAMs and does not. A
# port that omits the check matches `l17` too, and the answer it builds is
# WRONG -- it is `y.eq(c1+1)` with the `x` of neither side.
def dc_l12.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool,+val: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_l12.body(ar, self, val)
    case False{}: None{}

def dc_val.go(+v: O.Const) -> Maybe<&2, U32>:
  match v:
    case O.CInt{i}: Some{H.lo32(i)}
    case O.CFloat{f}: None{}
    case O.CBool{b}: None{}
    case O.CInvalid{}: None{}

def dc_val.arg(+arg: O.Arg) -> Maybe<&2, U32>:
  match arg:
    case O.APy{v}: dc_val.go(v)
    case _: None{}

def dc_vmax.const(+arg: O.Arg, lim: Maybe<&2, U32>) -> Maybe<&2, U32>:
  dc_vmax.const.go(dc_val.arg(arg), lim)

def dc_vmax_of.go(+op: O.Op, +arg: O.Arg, lim: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match op:
    case O.OpsCONST{}: dc_vmax.const(arg, lim)
    case O.OpsPARAM{}: dc_vmax.param.go(arg, lim)
    case _: None{}

def dc_vmax_of(+ar: O.Arena,+x: U32,+fx: F.Folded) -> Maybe<&2, U32>:
  dc_vmax_of.go(O.Arena.op(ar, x), O.Arena.arg(ar, x),
                dc_dtmax(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), x)))

# `dc_cside`'s answer turned back into a node: 0 -> src0, 1 -> src1, and 2 (both
# or neither) -> src0, which then fails the value test in every caller.
def dc_pick_side(+ar: O.Arena,+u: U32,+which: U32) -> U32:
  match which:
    case 1: O.Arena.src(ar, u, 1)
    case _: O.Arena.src0(ar, u)

def dc_l7.y(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src0(ar, dc_pick_side(ar, self, dc_negside(ar, self)))

def dc_l14.m(+ar: O.Arena,+self: U32) -> U32:
  dc_pick_side(ar, self, dc_mulside(ar, self))

def dc_l14.a(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src0(ar, dc_l14.m(ar, self))

def dc_l14.b(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src(ar, dc_l14.m(ar, self), 1)

def dc_l15.m(+ar: O.Arena,+self: U32) -> U32:
  dc_pick_side(ar, self, dc_shlside(ar, self))

def dc_l17.d(+ar: O.Arena,+self: U32) -> U32:
  dc_pick_side(ar, self, dc_fdside(ar, self))

def dc_l17.b(+ar: O.Arena,+self: U32) -> U32:
  O.Arena.src(ar, dc_l17.d(ar, self), 1)

def dc_l17.pat2(+ar: O.Arena,+self: U32) -> Bool:
  dc_is_one(ar, O.Arena.src0(ar, dc_l17.d(ar, self)))

# ---- rule 7 -- op.py:106. `x + (-y) -> x.alu(SUB, y)`. This is the ONE `SUB`
# node in the file, because it is an explicit `.alu(Ops.SUB, y)` and not `x - y`.
# ADD is an `is_any` and the NEG may be EITHER src.
def dc_l7.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_alu2(ar, O.OpsSUB{}, dc_l7.x(ar, self), dc_l7.y(ar, self))}
    case False{}: None{}

def dc_l7(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l7.go(F.Folded.ar(fx), self, dc_l7.pat(F.Folded.ar(fx), self))

# ---- rules 14 and 15 -- op.py:119 and op.py:121. `a*b + c -> a.alu(MULACC,b,c)`
# and `(x<<n) + c -> x.alu(MULACC, x.const_like(1<<n), c)`. Both are on an ADD, so
# both are `is_any` and the addend may be EITHER src; `l19`/`l20` are the two
# sides of rule 14.
def dc_l14.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_alu3(ar, O.OpsMULACC{}, dc_l14.a(ar, self),
                                    dc_l14.b(ar, self), dc_l14.c(ar, self))}
    case False{}: None{}

def dc_l14(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l14.go(F.Folded.ar(fx), self, dc_l14.pat(F.Folded.ar(fx), self))

# ---- rule 17 -- op.py:125. `a * (1/b) -> a.alu(FDIV, b)`. MUL is an `is_any` and
# the FDIV may be EITHER src. `UPat.const(1)` matches the float `1.0` because
# Python's `1 == 1.0`, so `dc_is_one` reads BOTH Const arms -- the one place a
# float CONST is matched as an integer.
def dc_l17.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_alu2(ar, O.OpsFDIV{}, dc_other(ar, self, dc_fdside(ar, self)),
                                    dc_l17.b(ar, self))}
    case False{}: None{}

def dc_l17.go2(+ar: O.Arena,+self: U32,+one: Bool) -> Maybe<&2, O.Found>:
  match one:
    case True{}: dc_l17.go(ar, self, dc_l17.pat(ar, self))
    case False{}: None{}

def dc_l17(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l17.go2(F.Folded.ar(fx), self, dc_l17.pat2(F.Folded.ar(fx), self))

# ===========================================================================
# THE DTYPE CONJUNCTS. `dtypes.ints` is the four SIGNED widths and it is NOT
# weakint, so `Cls.is_int` is the wrong test here -- it admits `CWeakInt`. One
# reader and a NAME, so a rule spells `dc_dt(fx, x, 0)`.
#   0 ints  1 uints  2 bool  3 floats
# ===========================================================================
# A nested `match c:` in every arm of `match want:` makes `c` a binder matched
# more than once, which Bend reads as a consumed binder. One def per class and
# one `match want` over those is the same four lines and it compiles.
def dc_dt.sint(+c: S.Cls) -> Bool:
  match c:
    case S.CSint{}: True{}
    case _: False{}

def dc_dt.cls(+c: S.Cls,+want: U32) -> Bool:
  match want:
    case 0: dc_dt.sint(c)
    case 1: dc_dt.uint(c)
    case 2: dc_dt.bool(c)
    case _: dc_dt.flt(c)

def dc_dt.of(m: Maybe<&2, S.Dt>,+want: U32) -> Bool:
  match m:
    case Some{+d}: dc_dt.cls(S.Dt.cls(d), want)
    case None{}: False{}

def dc_dt(+fx: F.Folded,+u: U32,+want: U32) -> Bool:
  dc_dt.of(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), u), want)

# ===========================================================================
# `_min_max` -- ops.py:1104. op.py's ONLY range read is
# `floordiv_to_idiv`'s and `floormod_to_mod`'s guard, and it is `a.vmin >= 0`,
# `b.vmin >= 0`, `a.vmax <= 0`, `b.vmax <= 0`.
#
#   * A CONST's `_min_max` IS `(val, val)` (ops.py:1127) and a PARAM's IS
#     `arg.vmin_vmax` (ops.py:1129). Both are plain field reads, so BOTH ends of
#     the guard are exact for the two node kinds the port can build, and
#     `out_s7` (a uint numerator, `vmin >= 0` on both, so the SHORT CDIV) is the
#     row that says the guard was read rather than assumed.
#   * Any other op needs the recursive `_min_max`, which is P3 and recorded at
#     `fold.bend:2176`. `dc_end` answers `False` there, which makes the guard
#     fail and sends the rule down the GENERAL path. That is Python's answer
#     whenever the guard is false, so the divergence is SOUND. It is
#     DIVERGENCE D and the alternative -- answering `True` -- would be a wrong
#     answer, not a conservative one.
# ===========================================================================
def dc_end.go(+le: Bool,+neg: Bool,+v: U32) -> Bool:
  match le:
    case True{}: Bool.or(neg, U32.is_zero(v))
    case False{}: Bool.not(neg)

def dc_const_end.go(m: Maybe<&2, U32>,+le: Bool) -> Bool:
  match m:
    case Some{+v}: dc_end.go(le, H.i32_is_neg(v), v)
    case None{}: False{}

def dc_const_end(+arg: O.Arg,+le: Bool) -> Bool:
  dc_const_end.go(dc_val.arg(arg), le)

def dc_range_end.put(+le: Bool,+lo: H.I64,+hi: H.I64) -> Bool:
  match le:
    case True{}: dc_end.go(True{}, H.i64_is_neg(hi), H.lo32(hi))
    case False{}: dc_end.go(False{}, H.i64_is_neg(lo), H.lo32(lo))

def dc_range_end.go(m: Maybe<&2, O.PyRange>,+le: Bool) -> Bool:
  match m:
    case Some{O.PyRange{lo, hi}}: dc_range_end.put(le, lo, hi)
    case None{}: False{}

def dc_param_end.go(+arg: O.Arg,+le: Bool) -> Bool:
  match arg:
    case O.AParam{pa}: dc_range_end.go(O.ParamArg.vmin_vmax(pa), le)
    case _: False{}

def dc_end.go2(+op: O.Op,+arg: O.Arg,+le: Bool) -> Bool:
  match op:
    case O.OpsCONST{}: dc_const_end(arg, le)
    case O.OpsPARAM{}: dc_param_end.go(arg, le)
    case _: False{}

# `x.vmin >= 0` (`le` False) and `x.vmax <= 0` (`le` True).
def dc_vmin(+ar: O.Arena,+u: U32) -> Bool:
  dc_end.go2(O.Arena.op(ar, u), O.Arena.arg(ar, u), False{})

def dc_vmax(+ar: O.Arena,+u: U32) -> Bool:
  dc_end.go2(O.Arena.op(ar, u), O.Arena.arg(ar, u), True{})

# `(a.vmin >= 0 and b.vmin >= 0) or (a.vmax <= 0 and b.vmax <= 0)` -- the guard
# op.py:55 and op.py:59 share, read on the ROOT of the pattern's two srcs.
def dc_both_nonneg(+ar: O.Arena,+a: U32,+b: U32) -> Bool:
  Bool.or(Bool.and(dc_vmin(ar, a), dc_vmin(ar, b)),
          Bool.and(dc_vmax(ar, a), dc_vmax(ar, b)))

# ===========================================================================
# `floordiv_to_idiv` -- op.py:54-56. The short arm is the WHOLE of `a.alu(CDIV,
# b)` and `out_s7` is its row; the general arm is
# `a.alu(CDIV,b) - (a.alu(CMOD,b).ne(0) & (a<0).ne(b<0))`, and because `&` on
# bools is `AND` and `-` is `dc_sub` the tree is `ADD(CDIV, MUL(AND, C(-1)))`.
# ===========================================================================
def dc_fd.gen(+ar: O.Arena,+a: U32,+b: U32) -> O.Found:
  +q = dc_alu2(ar, O.OpsCDIV{}, a, b)
  +nz = dc_cmod_ne(O.Found.ar(q), a, b)
  +s = dc_sgn(nz, b)
  +g = dc_alu2(O.Found.ar(s), O.OpsAND{}, O.Found.i(nz), O.Found.i(s))
  dc_sub(O.Found.ar(g), O.Found.i(q), O.Found.i(g))

def dc_fd.put(+ar: O.Arena,+a: U32,+b: U32,+short: Bool) -> O.Found:
  match short:
    case True{}: dc_alu2(ar, O.OpsCDIV{}, a, b)
    case False{}: dc_fd.gen(ar, a, b)

def floordiv_to_idiv(+ar: O.Arena,+a: U32,+b: U32) -> O.Found:
  dc_fd.put(ar, a, b, dc_both_nonneg(ar, a, b))

# `UPat.var("a")//UPat.var("b")` -- op.py:72. NO dtype conjunct and NO reject
# set, so a uint numerator and a float divisor both reach `floordiv_to_idiv`
# here, and `s7` is the row.
def dc_s1.put(+ar: O.Arena,+self: U32) -> Maybe<&2, O.Found>:
  Some{floordiv_to_idiv(ar, O.Arena.src0(ar, self), O.Arena.src(ar, self, 1))}

def dc_s1(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s1.put(F.Folded.ar(fx), self)

# ===========================================================================
# `floormod_to_mod` -- op.py:58-62. The comment at :61 is load-bearing and is
# KEPT: `where` and not `mul`, so the result cannot be fused into MULACC.
#   # use where instead of mul to avoid being fused into MULACC (which int64
#   #   long-decomp doesn't handle)
# The general arm is `r + (r.ne(0) & (a<0).ne(b<0)).where(b, b.const_like(0))`,
# and `b.const_like(0)` is `C(0)` -- a CONST and not a node.
# ===========================================================================
def dc_fm.gen(+ar: O.Arena,+a: U32,+b: U32) -> O.Found:
  +r = dc_alu2(ar, O.OpsCMOD{}, a, b)
  +nz = dc_cmod_ne(O.Found.ar(r), a, b)
  +s = dc_sgn(nz, b)
  +g = dc_alu2(O.Found.ar(s), O.OpsAND{}, O.Found.i(nz), O.Found.i(s))
  +z = dc_cint(O.Found.ar(g), 0)
  +w = dc_alu3(O.Found.ar(z), O.OpsWHERE{}, O.Found.i(g), b, O.Found.i(z))
  dc_alu2(O.Found.ar(w), O.OpsADD{}, O.Found.i(r), O.Found.i(w))

def dc_fm.put(+ar: O.Arena,+a: U32,+b: U32,+short: Bool) -> O.Found:
  match short:
    case True{}: dc_alu2(ar, O.OpsCMOD{}, a, b)
    case False{}: dc_fm.gen(ar, a, b)

def floormod_to_mod(+ar: O.Arena,+a: U32,+b: U32) -> O.Found:
  dc_fm.put(ar, a, b, dc_both_nonneg(ar, a, b))

# `UPat.var("a")%UPat.var("b")` -- op.py:75.
def dc_s3.put(+ar: O.Arena,+self: U32) -> Maybe<&2, O.Found>:
  Some{floormod_to_mod(ar, O.Arena.src0(ar, self), O.Arena.src(ar, self, 1))}

def dc_s3(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s3.put(F.Folded.ar(fx), self)

# ===========================================================================
# `magicgu` -- op.py:9-18. Hacker's Delight chapter 10: the smallest `s` with
# `2**s > nc*(d-1-(2**s-1)%d)`, and then `m = (2**s + d-1-(2**s-1)%d)//d`.
#
# PORTED IN SHAPE: the `nc`, the `nbits`, the `2*nbits+1` bound and the test are
# all here, as VALUES on a `U32`/`Nat` pair, so the loop shape is readable and
# the ONE thing missing is named rather than approximated.
#
# TODO(p3) op.py:9-18 `magicgu`. THE WALL, MEASURED, and it is NOT the one the
#   brief predicted. `2**s` must be materialised and COMPARED against
#   `nc*(d-1-((2**s-1)%d))`, and for a 32-bit `vmax` that product is 62 bits and
#   `2**s` is 63, so a 64-bit carrier is the minimum -- and for a uint32 `vmax`
#   they are 64 and 65 bits, which does not fit an UNSIGNED 64-bit word. So
#   `magicgu` needs, on top of each other:
#     * `i64_mul`  -- the 32x32 carry chain, plus the three-term add with a carry
#       out, because `nc * (d-1-...)` is a 32x32 product and `m*vmax` is a 33x32.
#     * `i64_div` and `i64_mod` by a 32-bit divisor -- a restoring divider, and
#       `(2**s - 1) % d` at `s = 2*nbits` is a 65-bit modulus.
#     * `i64_shl`  -- `2**s` for `s` up to `2*nbits = 64`.
#     * an UNSIGNED 64-bit compare -- `H.i64_cmp` (helpers.bend:1213) is SIGNED,
#       and `2**64` reads negative in it.
#     * a 65-bit third limb, for `2**64 + d`, which is the numerator of `m`.
#   `helpers.bend` has `i64_add`, `i64_sub`, `i64_cmp`, `i64_of_hi_lo` and
#   `data64`, and NONE of the four above. The measured widths, exhaustive over
#   every d < 2**16 and 20k random d per dtype:
#     int32   maxprod 62b  max2pow 63b  maxm 32b  max(m*vmax) 63b
#     uint32  maxprod 64b  max2pow 65b  maxm 33b  max(m*vmax) 65b
#   So the carry chain the brief proposed (`decomp.mulhi64`, four 32-bit
#   multiplies) is NECESSARY AND NOT SUFFICIENT: it is one of the five items
#   above, and on its own it unblocks nothing, because the first thing
#   `magicgu` does with the product is divide by `d`. The proposed addition to
#   `helpers.bend` is written out at the foot of this file.
#   The P3 phase that owns it is the one that adds `i64_mul`/`i64_div`/
#   `i64_mod`/`i64_shl` to `helpers.bend`; nothing in `decomp.py` changes when
#   they land, because this block is already the only caller.

# ===========================================================================
# `fast_idiv` -- op.py:20-34. THREE of the five guards are exact here and are
# PORTED, because the two they need are both available: `d.val` is a `U32` and
# `x.vmin`/`x.vmax` are readable for a CONST and a PARAM (see `dc_vmin`). The
# FOURTH line is the wall, and `dc_idiv`'s `None` there is the same reading
# `divandmod.bend` gives Python's `raise`: the condition is REPORTED and the
# ladder treats it as a skip, which is the only total answer a pure def has.
# ===========================================================================
# `d <= 0` for a CONST `d`, which is `d.val` and a SIGNED compare. `x.vmin < 0`
# is `not dc_vmin`.
def dc_idiv.bad(+ar: O.Arena,+x: U32,+d: U32) -> Bool:
  Bool.or(dc_end.go(True{}, H.i32_is_neg(d), d), Bool.not(dc_vmin(ar, x)))

# op.py:23 `m, s = magicgu(vmax, d)` is the WALL (see the block above), and so is
# op.py:24, op.py:26-27's `k` recursion and op.py:30-33's widen, which needs
# `ren.supported_dtypes()` and there is no `Renderer` in the port at all.
# `x.vmax < 0` is answered by `dc_vmin` for a CONST and a PARAM, which is what
# makes `l27`/`l28`/`l29` ported rows rather than stubs.
def dc_idiv(+ar: O.Arena,+x: U32,+d: U32,+small: Bool) -> Maybe<&2, O.Found>:
  dc_idiv.go(ar, x, d, dc_idiv.bad(ar, x, d), small)

# ===========================================================================
# `threefry2x32` -- op.py:38-50. FIVE groups of FOUR rounds, all 32-bit, and
# the only 64-bit step is the final `(xr[1] << 32) | xr[0]`, which is
# `H.i64_of_hi_lo` and NOT arithmetic. PORTED IN FULL, and it is the largest
# single piece of arithmetic in the file.
#
# THE TWO LOOPS ARE ONE RECURSION because they interleave in Python: the round
# loop is INNER and the `ks` update is the loop body's last line. `i` is not
# threaded -- `i` IS `5 - fuel` -- so `rotations[i % 2]` is "the odd list when
# `fuel` is even" and `ks[i % 3]` is an index into the three-element list.
#
# `xr[0], xr[1] = (x0 := xr[0] + xr[1]), x0 ^ ((xr[1] << r) + (xr[1] >> (32-r)))`
# is read as `new0 = old0 + old1` and `new1 = new0 ^ ((old1 << r) + (old1 >>
# (32-r)))`: Python evaluates the whole right-hand tuple before the assignment,
# so `xr[1]` on the right is the OLD one and `x0` is the NEW `xr[0]`. Getting
# that wrong is the one silent bug in the port, and `out_s9` cannot see it --
# which is why `grown_s9` and `tf_split` are here as well.
# ===========================================================================
type TFP is Data:
  TFP{f: O.Found, a: U32, b: U32}

def TFP.f(+x: TFP) -> O.Found:
  match x:
    case TFP{f, a, b}: f

def TFP.a(+x: TFP) -> U32:
  match x:
    case TFP{f, a, b}: a

def TFP.b(+x: TFP) -> U32:
  match x:
    case TFP{f, a, b}: b

def dc_tfr(+ar: O.Arena, +a: U32, +b: U32,+r: U32) -> TFP:
  +s = dc_alu2(ar, O.OpsADD{}, a, b)
  +l = dc_shl(O.Found.ar(s), b, r)
  +h = dc_shr(O.Found.ar(l), b, U32.sub(32, r))
  +t = dc_alu2(O.Found.ar(h), O.OpsADD{}, O.Found.i(l), O.Found.i(h))
  +x = dc_alu2(O.Found.ar(t), O.OpsXOR{}, O.Found.i(s), O.Found.i(t))
  TFP{x, O.Found.i(s), O.Found.i(x)}

# FOUR rounds. The rotation list has four entries and the count is fixed, so the
# fuel is 4 and the list is walked by its own head.
def dc_tfr4(fuel: Nat,+st: TFP, +rs: List<&2, U32>) -> TFP:
  match fuel:
    case 0n: st
    case 1n+p:
      match rs:
        case Nil{}: dc_tfr4(p, st, rs)
        case r <> t: dc_tfr4(p, dc_tfr(O.Found.ar(TFP.f(st)), TFP.a(st), TFP.b(st), r), t)

# `xr = [xr[0] + ks[i%3], xr[1] + ks[(i+1)%3] + i + 1]`. `i` is a `U32` because
# `List.get` wants a `Nat` and `i % 3` wants a `U32`.
def dc_tfg.keys.build(+st: TFP,+k0: U32,+k1: U32,+i: U32) -> TFP:
  +p = dc_alu2(O.Found.ar(TFP.f(st)), O.OpsADD{}, TFP.a(st), k0)
  +q = dc_alu2(O.Found.ar(p), O.OpsADD{}, TFP.b(st), k1)
  +ci = dc_cint(O.Found.ar(q), i)
  +r = dc_alu2(O.Found.ar(ci), O.OpsADD{}, O.Found.i(q), O.Found.i(ci))
  +c1 = dc_cint(O.Found.ar(r), 1)
  +s = dc_alu2(O.Found.ar(c1), O.OpsADD{}, O.Found.i(r), O.Found.i(c1))
  TFP{s, O.Found.i(p), O.Found.i(s)}

def dc_tfg.keys.put(+st: TFP, +ks: List<&2, U32>, i: U32, k0: U32,
                    m: Maybe<&2, U32>) -> TFP:
  match m:
    case Some{+k1}: dc_tfg.keys.build(st, k0, k1, i)
    case None{}: st

def dc_tfg.keys.next(+st: TFP, +ks: List<&2, U32>, +i: U32, +k0: U32) -> TFP:
  dc_tfg.keys.put(st, ks, i, k0,
                  List.get(&2, U32, ks, U32.to_nat(U32.mod(U32.add(i, 1), 3))))

def dc_tfg.keys.go(+st: TFP, +ks: List<&2, U32>,+i: U32, m: Maybe<&2, U32>) -> TFP:
  match m:
    case Some{+k0}: dc_tfg.keys.next(st, ks, i, k0)
    case None{}: st

def dc_tfg.keys(+st: TFP, +ks: List<&2, U32>,+i: U32) -> TFP:
  dc_tfg.keys.go(st, ks, i, List.get(&2, U32, ks, U32.to_nat(U32.mod(i, 3))))

# One group: the four rounds, then the `ks` update. `i` is the group index and it
# is THREADED rather than derived from the fuel: the fuel is the self-call's
# first argument and `dc_tfg.step` wants the group index in the same arm, and a
# value may not be consumed twice in one expression. `i + 1` is what the five
# groups increment and `U32.is_even` (base.bend:1542) is `i % 2`, so there is no
# `Nat` parity walk and no second countdown.
def dc_tfg.step(+st: TFP, +i: U32, +ks: List<&2, U32>, +a: List<&2, U32>,
                +b: List<&2, U32>) -> TFP:
  dc_tfg.keys(dc_tfr4(4n, st, dc_tfg.pick(U32.is_even(i), a, b)), ks, i)

# THE FIVE GROUPS. A `TFP` is a `Data` record and that is what lets the arena and
# both halves travel together: a `(Arena, U32, U32)` triple is not a Bend type and
# `dc_tfr` needs all three at once, once per group.
def dc_tfg(fuel: Nat, +st: TFP, +i: U32, +ks: List<&2, U32>, +a: List<&2, U32>,
          +b: List<&2, U32>) -> TFP:
  match fuel:
    case 0n: st
    case 1n+p: dc_tfg(p, dc_tfg.step(st, i, ks, a, b), U32.add(i, 1), ks, a, b)

# `ks` and the arena it was minted in travel together in a `Data` record: `dc_tfg`
# needs the list five times and the arena once, and a `(List, Arena)` pair return
# is not a Bend type.
type TFK is Data:
  TFK{f: O.Found, ks: List<&2, U32>}

def TFK.f(x: TFK) -> O.Found:
  match x:
    case TFK{f, ks}: f

def TFK.ks(x: TFK) -> List<&2, U32>:
  match x:
    case TFK{f, ks}: ks

# `ks = [key1, key0 ^ key1 ^ 0x1BD11BDA, key0]` -- op.py:44, and `ks[-1]` is
# `ks[2]`, so the initial pair is `[x0 + key0, x1 + key1]`. `0x1BD11BDA` is
# 468937178 and is a CONST; the two XORs are nodes.
def dc_tf_ks(+ar: O.Arena,+key0: U32,+key1: U32) -> TFK:
  +c = dc_cint(ar, 468937178)
  +t = dc_alu2(O.Found.ar(c), O.OpsXOR{}, key0, key1)
  +m = dc_alu2(O.Found.ar(t), O.OpsXOR{}, O.Found.i(t), O.Found.i(c))
  TFK{m, [key1, O.Found.i(m), key0]}

# `xr:list[UOp] = [x0 + ks[-1], x1 + ks[0]]` -- op.py:45. `ks[-1]` is `ks[2]`
# and `ks[0]` is `key1`, so the head pair is `[x0 + key0, x1 + key1]`. A list
# pattern and not `List.get`, so there is no `Maybe` to unwrap.
def dc_tf_init.build(+st: TFP, +k0: U32, +k1: U32) -> TFP:
  +p = dc_alu2(O.Found.ar(TFP.f(st)), O.OpsADD{}, TFP.a(st), k0)
  +q = dc_alu2(O.Found.ar(p), O.OpsADD{}, TFP.b(st), k1)
  TFP{q, O.Found.i(p), O.Found.i(q)}

def dc_tf_init.put(+st: TFP, +k0: U32, +ks: List<&2, U32>) -> TFP:
  match ks:
    case Nil{}: st
    case k1 <> _: dc_tf_init.build(st, k0, k1)

def dc_tf_init(+st: TFP, +ks: List<&2, U32>) -> TFP:
  match ks:
    case Nil{}: st
    case k0 <> t: dc_tf_init.put(st, k0, t)

# `threefry2x32` -- op.py:38-50, IN FULL. The only 64-bit step is `dc_tf_join`,
# which is a SHL and an OR and not arithmetic, so this whole function is 32-bit.
def threefry2x32(+ar: O.Arena,+x: U32,+key: U32) -> O.Found:
  +x0 = dc_tf_half(ar, x, False{})
  +x1 = dc_tf_half(O.Found.ar(x0), x, True{})
  +k0 = dc_tf_half(O.Found.ar(x1), key, False{})
  +k1 = dc_tf_half(O.Found.ar(k0), key, True{})
  +k = dc_tf_ks(O.Found.ar(k1), O.Found.i(k0), O.Found.i(k1))
  +st = dc_tf_init(TFP{TFK.f(k), O.Found.i(x0), O.Found.i(x1)}, TFK.ks(k))
  +r = dc_tfg(5n, st, 0, TFK.ks(k), [13, 15, 26, 6], [17, 29, 16, 24])
  dc_tf_join(O.Found.ar(TFP.f(r)), TFP.b(r), TFP.a(r))

# `UPat(Ops.THREEFRY, src=(UPat.var("x"), UPat.var("key")))` -- op.py:77. NO
# dtype conjunct and NO reject set: both srcs are untyped vars.
def dc_s4.put(+ar: O.Arena,+self: U32) -> Maybe<&2, O.Found>:
  Some{threefry2x32(ar, O.Arena.src0(ar, self), O.Arena.src(ar, self, 1))}

def dc_s4(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s4.put(F.Folded.ar(fx), self)

# THE 64-BIT SPLIT, as DATA rather than as a rewrite, so `tf_split` can check it
# without unfolding 153 nodes. `x.cast(uint32)` is `H.lo32` of the CONST's I64
# and `x >> 32` is `H.hi32`, because `CInt` HOLDS an `I64` and the port's
# 64-bit CONST is a two-word pair rather than a `U32` (divergence C's other
# half). For a `uint64` CONST that is exact; for a `uint32` one `hi32` is 0,
# which is also what Python's `>> 32` gives.
def tf_split.arg(+arg: O.Arg) -> Maybe<&1, U32 & U32>:
  match arg:
    case O.APy{O.CInt{i}}: Some{H.data64(i)}
    case _: None{}

def tf_split(+ar: O.Arena,+x: U32) -> Maybe<&1, U32 & U32>:
  tf_split.arg(O.Arena.arg(ar, x))

def tf_split_str(+ar: O.Arena,+x: U32) -> String:
  tf_split_str.go(tf_split(ar, x))

# ===========================================================================
# THE SIMPLIFYING TABLE -- op.py:66-78. FOUR rules, and the `ops` argument
# decides whether the first and the third exist at all, so the table is a
# FUNCTION of a Bool and the two variants are two `Data` values built by one
# `match`. That is `spec.bend`'s `+` composition in its smallest form: the tag
# means "(this table, index in THIS list)".
#
# `0` FLOORDIV(x:ints, c) -> x >> v if v            op.py:70-71
# `1` FLOORDIV(a, b)     -> floordiv_to_idiv        op.py:72
# `2` FLOORMOD(x:ints, c) -> x & (c-1) if c is 2**y op.py:74
# `3` FLOORMOD(a, b)     -> floormod_to_mod         op.py:75
# `4` THREEFRY(x, key)   -> threefry2x32            op.py:77
#
# The reject sets are MEASURED, not guessed: `rejs0..rejs3` in the gate.
# ===========================================================================
def dc_s_tab(+shifts: Bool,+threefry: Bool) -> O.PMEntrys:
  match threefry:
    case True{}: O.PMEntrys{[O.PMEntry{0, [O.OpsFLOORDIV{}],  [O.OpsCONST{}]},              # 70
                            O.PMEntry{1, [O.OpsFLOORDIV{}],  Nil{}},                       # 72
                            O.PMEntry{2, [O.OpsFLOORMOD{}],  [O.OpsCONST{}]},              # 74
                            O.PMEntry{3, [O.OpsFLOORMOD{}],  Nil{}},                       # 75
                            O.PMEntry{4, [O.OpsTHREEFRY{}],  Nil{}}]}                      # 77
    case False{}: O.PMEntrys{[O.PMEntry{0, [O.OpsFLOORDIV{}], [O.OpsCONST{}]},              # 70
                             O.PMEntry{1, [O.OpsFLOORDIV{}], Nil{}},                        # 72
                             O.PMEntry{2, [O.OpsFLOORMOD{}], [O.OpsCONST{}]},              # 74
                             O.PMEntry{3, [O.OpsFLOORMOD{}], Nil{}}]}                      # 75

def dc_entry_s(+n: U32) -> Maybe<&2, O.PMEntry>:
  List.get(&2, O.PMEntry, O.PMEntrys.es(dc_s_tab(False{}, False{})), U32.to_nat(n))

def t_nrules_s() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(dc_s_tab(False{}, False{}))))

def t_nrules_s3f() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(dc_s_tab(False{}, True{}))))

# ---- THE SHARED SIDE ALGEBRA, once. `dc_cside` asks "which side is the CONST";
# `dc_side_of` asks the same about any other predicate. Both are the THREE-armed
# disjunction of header note 2, and `divandmod.bend`'s mutation table says one
# family of fixtures cannot tell "which side is the CONST" from "which side is
# the other node" -- so `dc_other` is its own def and `l25`/`l26` are the rows
# that read the commutativity from the other direction.
def dc_side_of(+ar: O.Arena,+u: U32,+x0: Bool,+x1: Bool) -> U32:
  dc_side.go(x0, x1)

# ===========================================================================
# THE GATE, and what each row is FOR. Every row is a claim PYTHON FIXES, taken
# from `.agents/slop/dc-oracle.py`, which is the real `decomp.op` driven over the
# real `PatternMatcher`. Nothing here restates this file's own code.
#
#   nrules_s=4 / nrules_l=18 / nrules_l_noidiv=16   op.py:66 and op.py:81. THE
#                  COUNTS. `disable_fast_idiv` removes TWO rules and renumbers
#                  sixteen more, and a table that dropped the wrong one still has
#                  sixteen entries -- so `rejl6..rejl17` and `nrules_l_noidiv`
#                  are the pair that pins WHICH.
#   nrules_s_no3f=5   op.py:77's rule exists only when `Ops.THREEFRY not in ops`,
#                  so the five-rule variant is a DIFFERENT table and not this one
#                  plus a row.
#   rejN=...   the `early_reject` sets, MEASURED. A mis-spelled set shows up here
#                  and nowhere else, and rules 8/9's `[CMPLT, CONST]` and rule
#                  11's `[CONST, MUL]` are the two that a "the reject set is just
#                  the first src's op" simplification gets wrong.
#   on_<f>     did a rule fire. `0` IS Python's `None`.
#   tag_<f>    WHICH rule fired, so first-wins is observable and not just on/off.
#   out_<f>    the rewritten tree TWO LEVELS DEEP with CONST values printed.
#   grown_<f>  how many nodes the rewrite ADDED. PORT-INTERNAL (divergence A
#                  means Python's count differs) and here because it is the only
#                  NUMERIC discriminator between first-wins and last-wins.
#   tf_split   the 64-bit split `x.cast(uint32)` / `x >> 32` as DATA. `threefry2x32`
#                  is the largest arithmetic in the file and `out_s9` sees only
#                  its top two levels, so this is the row that says the halves
#                  were read in the right order.
#   nroots     how many roots the fixture arena holds. THE COUNT ROW: a fixture
#                  added or dropped moves it, and every `*_<f>` row is addressed
#                  THROUGH it, so a stale index cannot hide.
# ===========================================================================
type Gate is Data:
  Gate{ar: O.Arena, rs: List<&2, U32>, tf: U32}

def Gate.ar(+g: Gate) -> O.Arena:
  match g:
    case Gate{ar, rs, tf}: ar

def Gate.rs(+g: Gate) -> List<&2, U32>:
  match g:
    case Gate{ar, rs, tf}: rs

def Gate.tf(+g: Gate) -> U32:
  match g:
    case Gate{ar, rs, tf}: tf

def root(+g: Gate,+n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Gate.rs(g), U32.to_nat(n)), 0)

def nroots(+g: Gate) -> U32:
  U32.from_nat(List.length(&2, U32, Gate.rs(g)))

# THE FIXTURES. One arena; the roots are addressed BY INDEX through `root`, and
# `nroots` is their count, so a fixture added in the wrong place shows up as a
# moved row rather than a silently shorter table. THE ORDER IS THE ORACLE'S
# FIXTURE ORDER and changing it moves every `out_` row.
#
# THE NODE LIST, IN BINDING ORDER.
#  0 bottom NOOP
#  1 C(0)  2 C(1)  3 C(2)  4 C(3)  5 C(4)  6 C(5)  7 C(8)  8 C(-1)
#  9 C(2147483647)  10 C(2**31)  11 C(200)  12 C(1.0)
# 13 C(0x0123456789abcdef)  14 C(0xfedcba9876543210)
# 15 Pi int32 [-20,20]  16 Pz int32 [0,100]  17 Pu uint32 [0,40]  18 Pb bool
# 19 Pf float32  20 Pg float32  21 Pj int32 [-20,20]
# ROOTS, in the oracle's order, with the rule Python's scan picks:
#  s0 FLOORDIV(i,C4)            r0  SHR(i,2)
#  s1 FLOORDIV(i,C3)            r1  the general form
#  s2 FLOORDIV(i,C1)            r1  powers_of_two[1]==0 is FALSY
#  s3 FLOORMOD(i,C4)            r2  AND(i,3)
#  s4 FLOORMOD(i,C3)            r3  the general form
#  s5 FLOORMOD(i,C1)            r2  1 IS in powers_of_two
#  s6 FLOORMOD(i,C0)            r3  0 is not
#  s7 FLOORDIV(u,C3)            r1  uint is not dtypes.ints: the SHORT CDIV
#  s8 FLOORDIV(i,C(2**31))      r0  SHR(i,31)
#  l0 AND(!b,!b)                r0  the only `logical_not` rule
#  l1 MUL(i,C4)                 r1  SHL(i,2)
#  l2 MUL(i,C1)                 --  r1 skips (v=0) and r6 skips (!= -1)
#  l3 MUL(i,C-1)                r6  NEG(i)
#  l4 MUL(i,C(2**31-1))         --  a CONST, not a power of two
#  l5 MUL(i,C5)                 --  a CONST, not a power of two
#  l6 CDIV(u,C4)                r2  SHR(u,2)
#  l7 CDIV(i,C4)                r3  r3 BEATS r4
#  l8 CDIV(z,C4)                r3  the same, non-negative
#  l9 CDIV(z,C3)                r4  fast_idiv -- THE WALL, Python answers
#  l10 CMOD(z,C3)               r5  fast_idiv -- THE WALL, Python answers
#  l11 ADD(i,NEG(i))            r7  SUB(i,i): the one SUB node
#  l12 !(i<5)                   r8  CMPLT(ADD(5,MUL),i)
#  l13 !(5<i)                   r9  CMPLT(i,ADD(5,1))
#  l14 (-i)<(j*3)               r10 the only three-capture rule
#  l15 (-i)<5                   r11 -c < x
#  l16 (1<i)&(i<3)              r12 x.eq(2): x bound ONCE
#  l17 (1<i)&(j<3)              --  THE IDENTITY-CHECK ROW
#  l18 i.ne(j)                  r13 CMPEQ(i,j)
#  l19 (i*j)+i                  r14 MULACC(i,j,i)
#  l20 (i*j)+4                  r14 MULACC(i,j,4): the SWAPPED add
#  l21 (i<<3)+i                 r15 MULACC(i,8,i)
#  l22 f.reciprocal()           r16 FDIV(1.0,f)
#  l23 f*(1.0/g)                r17 FDIV(f,g)
#  l24 (1<i)&(i<4)              --  c1+1 != c2-1
#  l25 C4*i                     r1  SHL(i,2): the is_any, CONST on the LEFT
#  l26 (-1*i)<(3*j)             r10 both MULs flipped
#  l27 CDIV(z,C200)             r4  vmax 100 < 200 -> C(0)
#  l28 CDIV(z,C0)               --  d <= 0
#  l29 CDIV(i,C3)               --  x.vmin -20 < 0
#  tf THREEFRY(c13,c14)         r4  the OR/SHL head, in the FIVE-rule table
def fixtures() -> Gate:
  +a = O.Arena.empty()
  +c0 = dc_cint(a, 0)
  +c1 = dc_cint(O.Found.ar(c0), 1)
  +c2 = dc_cint(O.Found.ar(c1), 2)
  +c3 = dc_cint(O.Found.ar(c2), 3)
  +c4 = dc_cint(O.Found.ar(c3), 4)
  +c5 = dc_cint(O.Found.ar(c4), 5)
  +c8 = dc_cint(O.Found.ar(c5), 8)
  +cm1 = dc_cint(O.Found.ar(c8), H.i32_neg(1))
  +cbig = dc_cint(O.Found.ar(cm1), 2147483647)
  +c2p = dc_cint(O.Found.ar(cbig), 2147483648)
  +c200 = dc_cint(O.Found.ar(c2p), 200)
  +c1f = dc_cflt(O.Found.ar(c200), 1.0)
  +ctx = O.UOp.const(O.Found.ar(c1f), O.CInt{H.i64_of_hi_lo(19088743, 2309737967)})
  +ctk = O.UOp.const(O.Found.ar(ctx), O.CInt{H.i64_of_hi_lo(4277000088, 1985229328)})
  +pi = O.UOp.new(O.Found.ar(ctk), O.OpsPARAM{}, Nil{}, O.AParam{dcp.range(S.int32(), 1, "i", H.i32_neg(20), 20)}, O.TNone{})
  +pz = O.UOp.new(O.Found.ar(pi), O.OpsPARAM{}, Nil{}, O.AParam{dcp.range(S.int32(), 1, "z", 0, 100)}, O.TNone{})
  +pu = O.UOp.new(O.Found.ar(pz), O.OpsPARAM{}, Nil{}, O.AParam{dcp.range(S.uint32(), 1, "u", 0, 40)}, O.TNone{})
  +pb = O.UOp.new(O.Found.ar(pu), O.OpsPARAM{}, Nil{}, O.AParam{dcp.range(S.boolean(), 1, "b", 0, 1)}, O.TNone{})
  +pf = O.UOp.new(O.Found.ar(pb), O.OpsPARAM{}, Nil{}, O.AParam{dcp(S.single(), 1, "f")}, O.TNone{})
  +pg = O.UOp.new(O.Found.ar(pf), O.OpsPARAM{}, Nil{}, O.AParam{dcp(S.single(), 1, "g")}, O.TNone{})
  +pj = O.UOp.new(O.Found.ar(pg), O.OpsPARAM{}, Nil{}, O.AParam{dcp.range(S.int32(), 1, "j", H.i32_neg(20), 20)}, O.TNone{})
  # the intermediates, in the oracle's construction order
  +nb = dc_lnot(O.Found.ar(pj), O.Found.i(pb))
  +i5 = dc_alu2(O.Found.ar(nb), O.OpsCMPLT{}, O.Found.i(pi), O.Found.i(c5))
  +n8 = dc_lnot(O.Found.ar(i5), O.Found.i(i5))
  +c5i = dc_alu2(O.Found.ar(n8), O.OpsCMPLT{}, O.Found.i(c5), O.Found.i(pi))
  +n9 = dc_lnot(O.Found.ar(c5i), O.Found.i(c5i))
  +ng = dc_neg(O.Found.ar(n9), O.Found.i(pi))
  +im1 = dc_alu2(O.Found.ar(ng), O.OpsMUL{}, O.Found.i(pi), O.Found.i(cm1))
  +m1i = dc_alu2(O.Found.ar(im1), O.OpsMUL{}, O.Found.i(cm1), O.Found.i(pi))
  +j3 = dc_alu2(O.Found.ar(m1i), O.OpsMUL{}, O.Found.i(pj), O.Found.i(c3))
  +cj = dc_alu2(O.Found.ar(j3), O.OpsMUL{}, O.Found.i(c3), O.Found.i(pj))
  +l1i = dc_alu2(O.Found.ar(cj), O.OpsCMPLT{}, O.Found.i(c1), O.Found.i(pi))
  +li3 = dc_alu2(O.Found.ar(l1i), O.OpsCMPLT{}, O.Found.i(pi), O.Found.i(c3))
  +l1j = dc_alu2(O.Found.ar(li3), O.OpsCMPLT{}, O.Found.i(c1), O.Found.i(pj))
  +lj3 = dc_alu2(O.Found.ar(l1j), O.OpsCMPLT{}, O.Found.i(pj), O.Found.i(c3))
  +nj = dc_alu2(O.Found.ar(lj3), O.OpsCMPNE{}, O.Found.i(pi), O.Found.i(pj))
  +n10 = dc_lnot(O.Found.ar(nj), O.Found.i(nj))
  +ij = dc_alu2(O.Found.ar(n10), O.OpsMUL{}, O.Found.i(pi), O.Found.i(pj))
  +sh3 = dc_shl(O.Found.ar(ij), O.Found.i(pi), 3)
  +rc = dc_alu1(O.Found.ar(sh3), O.OpsRECIPROCAL{}, O.Found.i(pf))
  +fd = dc_alu2(O.Found.ar(rc), O.OpsFDIV{}, O.Found.i(c1f), O.Found.i(pg))
  +anb = dc_alu2(O.Found.ar(fd), O.OpsAND{}, O.Found.i(nb), O.Found.i(nb))
  # s0..s8
  +r0 = dc_alu2(O.Found.ar(anb), O.OpsFLOORDIV{}, O.Found.i(pi), O.Found.i(c4))
  +r1 = dc_alu2(O.Found.ar(r0), O.OpsFLOORDIV{}, O.Found.i(pi), O.Found.i(c3))
  +r2 = dc_alu2(O.Found.ar(r1), O.OpsFLOORDIV{}, O.Found.i(pi), O.Found.i(c1))
  +r3 = dc_alu2(O.Found.ar(r2), O.OpsFLOORMOD{}, O.Found.i(pi), O.Found.i(c4))
  +r4 = dc_alu2(O.Found.ar(r3), O.OpsFLOORMOD{}, O.Found.i(pi), O.Found.i(c3))
  +r5 = dc_alu2(O.Found.ar(r4), O.OpsFLOORMOD{}, O.Found.i(pi), O.Found.i(c1))
  +r6 = dc_alu2(O.Found.ar(r5), O.OpsFLOORMOD{}, O.Found.i(pi), O.Found.i(c0))
  +r7 = dc_alu2(O.Found.ar(r6), O.OpsFLOORDIV{}, O.Found.i(pu), O.Found.i(c3))
  +r8 = dc_alu2(O.Found.ar(r7), O.OpsFLOORDIV{}, O.Found.i(pi), O.Found.i(c2p))
  # l0..l9
  +r9 = dc_alu2(O.Found.ar(r8), O.OpsMUL{}, O.Found.i(pi), O.Found.i(c4))
  +ra = dc_alu2(O.Found.ar(r9), O.OpsMUL{}, O.Found.i(pi), O.Found.i(c1))
  +rb = dc_alu2(O.Found.ar(ra), O.OpsMUL{}, O.Found.i(pi), O.Found.i(cm1))
  +rc2 = dc_alu2(O.Found.ar(rb), O.OpsMUL{}, O.Found.i(pi), O.Found.i(cbig))
  +rd = dc_alu2(O.Found.ar(rc2), O.OpsMUL{}, O.Found.i(pi), O.Found.i(c5))
  +re = dc_alu2(O.Found.ar(rd), O.OpsCDIV{}, O.Found.i(pu), O.Found.i(c4))
  +rf = dc_alu2(O.Found.ar(re), O.OpsCDIV{}, O.Found.i(pi), O.Found.i(c4))
  +rg = dc_alu2(O.Found.ar(rf), O.OpsCDIV{}, O.Found.i(pz), O.Found.i(c4))
  +rh = dc_alu2(O.Found.ar(rg), O.OpsCDIV{}, O.Found.i(pz), O.Found.i(c3))
  +ri = dc_alu2(O.Found.ar(rh), O.OpsCMOD{}, O.Found.i(pz), O.Found.i(c3))
  +rj = dc_alu2(O.Found.ar(ri), O.OpsADD{}, O.Found.i(pi), O.Found.i(ng))
  +rk = dc_alu2(O.Found.ar(rj), O.OpsCMPLT{}, O.Found.i(im1), O.Found.i(j3))
  +rl = dc_alu2(O.Found.ar(rk), O.OpsCMPLT{}, O.Found.i(im1), O.Found.i(c5))
  # l16..l19
  +rm = dc_alu2(O.Found.ar(rl), O.OpsAND{}, O.Found.i(l1i), O.Found.i(li3))
  +rn = dc_alu2(O.Found.ar(rm), O.OpsAND{}, O.Found.i(l1i), O.Found.i(lj3))
  +ro = dc_alu2(O.Found.ar(rn), O.OpsADD{}, O.Found.i(ij), O.Found.i(pi))
  +rp = dc_alu2(O.Found.ar(ro), O.OpsADD{}, O.Found.i(ij), O.Found.i(c4))
  +rq = dc_alu2(O.Found.ar(rp), O.OpsADD{}, O.Found.i(sh3), O.Found.i(pi))
  +rr = dc_alu2(O.Found.ar(rq), O.OpsMUL{}, O.Found.i(pf), O.Found.i(fd))
  +rM = dc_alu2(O.Found.ar(rr), O.OpsMUL{}, O.Found.i(pf), O.Found.i(fd))
  +rC = dc_alu2(O.Found.ar(rM), O.OpsCMPLT{}, O.Found.i(pi), O.Found.i(c4))
  +rs = dc_alu2(O.Found.ar(rC), O.OpsAND{}, O.Found.i(l1i), O.Found.i(rC))
  +rt = dc_alu2(O.Found.ar(rs), O.OpsMUL{}, O.Found.i(c4), O.Found.i(pi))
  +ru = dc_alu2(O.Found.ar(rt), O.OpsCMPLT{}, O.Found.i(m1i), O.Found.i(cj))
  # l27..l29
  +rv = dc_alu2(O.Found.ar(ru), O.OpsCDIV{}, O.Found.i(pz), O.Found.i(c200))
  +rw = dc_alu2(O.Found.ar(rv), O.OpsCDIV{}, O.Found.i(pz), O.Found.i(c0))
  +rx = dc_alu2(O.Found.ar(rw), O.OpsCDIV{}, O.Found.i(pi), O.Found.i(c3))
  +tf = dc_alu2(O.Found.ar(rx), O.OpsTHREEFRY{}, O.Found.i(ctx), O.Found.i(ctk))
  Gate{O.Found.ar(tf), [O.Found.i(r0), O.Found.i(r1), O.Found.i(r2), O.Found.i(r3), O.Found.i(r4), O.Found.i(r5), O.Found.i(r6), O.Found.i(r7), O.Found.i(r8), O.Found.i(anb), O.Found.i(r9), O.Found.i(ra), O.Found.i(rb), O.Found.i(rc2), O.Found.i(rd), O.Found.i(re), O.Found.i(rf), O.Found.i(rg), O.Found.i(rh), O.Found.i(ri), O.Found.i(rj), O.Found.i(n8), O.Found.i(n9), O.Found.i(rk), O.Found.i(rl), O.Found.i(rm), O.Found.i(rn), O.Found.i(n10), O.Found.i(ro), O.Found.i(rp), O.Found.i(rq), O.Found.i(rc), O.Found.i(rr), O.Found.i(rs), O.Found.i(rt), O.Found.i(ru), O.Found.i(rv), O.Found.i(rw), O.Found.i(rx)], O.Found.i(tf)}

def t_grown.go(+s: Bool,+n: U32, +h: Hit) -> U32:
  U32.sub(O.Arena.next(Hit.ar(h)), O.Arena.next(Gate.ar(fixtures())))

# THE PRINTER. `dc_lab` prints a node's own name, `dc_sh1` one level of srcs and
# `dc_sh2` two. A CONST prints as a signed decimal and a bool CONST prints as
# `C(1)`, which is divergence 2 in the header.
def dc_show.go(+neg: Bool,+v: U32) -> String:
  match neg:
    case True{}: String.concat(["-", U32.show(H.i32_neg(v))])
    case False{}: U32.show(v)

def dc_show(+v: U32) -> String:
  dc_show.go(H.i32_is_neg(v), v)

def dc_lab.put(+arg: O.Arg,+k: String) -> String:
  match arg:
    case O.AParam{pa}: dc_lab.name(O.ParamArg.name(pa), k)
    case O.APy{O.CInt{i}}: String.concat(["C(", dc_show(H.lo32(i)), ")"])
    case O.APy{O.CFloat{f}}: String.concat(["C(", H.f32_show(f), ")"])
    case O.APy{O.CBool{b}}: dc_lab.bool(b)
    case O.APy{O.CInvalid{}}: "C(Invalid)"
    case _: k

def dc_lab.go(+op: O.Op,+arg: O.Arg,+k: String) -> String:
  match op:
    case O.OpsCONST{}: dc_lab.put(arg, k)
    case _: dc_lab.put(arg, k)

# `O.Ops.name` SPELLS the prefix (`"Ops.SHR"`), because it is a name in `ops.bend`'s
# namespace. The oracle prints the bare `SHHR`... the bare `SHR`, and so does the
# gate, so the prefix is dropped here rather than in the oracle: one strip, in the
# one place a name is printed.
def dc_opname(+op: O.Op) -> String:
  String.drop(O.Ops.name(op), 4n)

def dc_lab(+ar: O.Arena, +u: U32) -> String:
  dc_lab.go(O.Arena.op(ar, u), O.Arena.arg(ar, u), dc_opname(O.Arena.op(ar, u)))

def dc_sfx1.go(+ar: O.Arena, +u: U32, wide: Bool) -> String:
  match wide:
    case True{}: String.concat([dc_lab(ar, O.Arena.src0(ar, u)), ",",
                                dc_lab(ar, O.Arena.src(ar, u, 1)), ",",
                                dc_lab(ar, O.Arena.src(ar, u, 2))])
    case False{}: String.concat([dc_lab(ar, O.Arena.src0(ar, u)), ",",
                                dc_lab(ar, O.Arena.src(ar, u, 1))])

# THREE arms on the arity, because a ONE-src node's `src1` is the arena's BOTTOM
# NOOP and printing it would put `NOOP` in every unary rewrite. `dc_isn2` guards
# the rules; the printer has to guard itself.
def dc_sfx1.put(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dc_lab(ar, O.Arena.src0(ar, u))
    case 2: dc_sfx1.go(ar, u, True{})
    case _: dc_sfx1.go(ar, u, False{})

def dc_sfx1.of(+ar: O.Arena, +u: U32) -> String:
  dc_sfx1.put(ar, u, dc_arity1(ar, u))

def dc_sfx1(+ar: O.Arena, +u: U32) -> String:
  dc_sfx1.of(ar, u)

def dc_sh1.go(+ar: O.Arena,+u: U32,+leaf: Bool) -> String:
  match leaf:
    case True{}: dc_lab(ar, u)
    case False{}: String.concat([dc_lab(ar, u), "(", dc_sfx1(ar, u), ")"])

def dc_sh1(+ar: O.Arena, +u: U32) -> String:
  dc_sh1.go(ar, u, U32.is_zero(O.Arena.nsrc(ar, u)))

def dc_sfx2.go(+ar: O.Arena, +u: U32, wide: Bool) -> String:
  match wide:
    case True{}: String.concat([dc_sh1(ar, O.Arena.src0(ar, u)), ",",
                                dc_sh1(ar, O.Arena.src(ar, u, 1)), ",",
                                dc_sh1(ar, O.Arena.src(ar, u, 2))])
    case False{}: String.concat([dc_sh1(ar, O.Arena.src0(ar, u)), ",",
                                dc_sh1(ar, O.Arena.src(ar, u, 1))])

def dc_sfx2.put(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dc_sh1(ar, O.Arena.src0(ar, u))
    case 2: dc_sfx2.go(ar, u, True{})
    case _: dc_sfx2.go(ar, u, False{})

def dc_sfx2.of(+ar: O.Arena, +u: U32) -> String:
  dc_sfx2.put(ar, u, dc_arity1(ar, u))

def dc_sfx2(+ar: O.Arena, +u: U32) -> String:
  dc_sfx2.of(ar, u)

def dc_sh2.go(+ar: O.Arena,+u: U32,+leaf: Bool) -> String:
  match leaf:
    case True{}: dc_lab(ar, u)
    case False{}: String.concat([dc_lab(ar, u), "(", dc_sfx2(ar, u), ")"])

def dc_sh2(+ar: O.Arena, +u: U32) -> String:
  dc_sh2.go(ar, u, U32.is_zero(O.Arena.nsrc(ar, u)))

def t_out.put(+on: U32, +h: Hit) -> String:
  match on:
    case 0: "none"
    case _: dc_sh2(Hit.ar(h), Hit.i(h))

def t_tf_out.put(+on: U32, +h: Hit) -> String:
  match on:
    case 0: "none"
    case _: dc_sh2(Hit.ar(h), Hit.i(h))

# ===========================================================================
# CONST READS. A PyConst is a Python int/float/bool/Invalid and the port's
# `Const` is `CInt{I64}` or `CFloat{F32}`, so a float CONST is unreadable as an
# integer and that is DIVERGENCE D's other half: op.py's `c.val` on a float
# CONST does not exist either, because `UPat.cvar` without a dtype matches a
# CONST of any dtype and then `c.val` raises. `dc_val` answering `None` is the
# same skip, reported.
# ===========================================================================
def dc_val(+ar: O.Arena, +u: U32) -> Maybe<&2, U32>:
  dc_val.arg(O.Arena.arg(ar, u))

def dc_cside(+ar: O.Arena,+u: U32) -> U32:
  dc_side.go(dc_has(dc_val(ar, O.Arena.src0(ar, u))),
             dc_has(dc_val(ar, O.Arena.src(ar, u, 1))))

def dc_hit(+ar: O.Arena,+u: U32) -> Bool:
  dc_has(dc_val(ar, O.Arena.src(ar, u, 1)))

# Is node `s` a `CMPNE(_, C(1))`, i.e. a `logical_not` or a `!= True`? Used by
# rules 0, 8, 9 and 13. `ar.src0` is the scrutinee and `ar.src1` the bool CONST.
def dc_is_not(+ar: O.Arena,+s: U32) -> Bool:
  Bool.and(O.op_is(ar, s, O.OpsCMPNE{}),
    Bool.and(dc_isn2(ar, s), U32.is_eq(dc_ival(dc_val(ar, O.Arena.src(ar, s, 1))), 1)))

# `vmax < d` -- op.py:22. `dc_ival` on the `None` from `_min_max` is 0, and
# Python's `vmax` for a node whose `_min_max` is unreadable is ALSO not
# something this port can answer, so the guard reads the two arms the port CAN:
# a CONST and a PARAM. `dc_vmax_of` is that reader.
def dc_l4.small(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  U32.is_lt(dc_ival(dc_vmax_of(ar, O.Arena.src0(ar, self), fx)),
            dc_ival(dc_val(ar, O.Arena.src(ar, self, 1))))

def dc_l6.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_l6.put(ar, dc_other(ar, self, dc_cside(ar, self)))
    case False{}: None{}

def dc_const_side(+ar: O.Arena,+u: U32) -> U32:
  dc_pick_side(ar, u, dc_cside(ar, u))

# `c - 1 < x`, and `c-1` is `ADD(c, MUL(1,-1))` -- a NODE and not `C(4)`.
def dc_l8.build(+ar: O.Arena, +self: U32) -> O.Found:
  +cm = dc_cminus(ar, dc_const_side(ar, O.Arena.src0(ar, self)))
  dc_alu2(O.Found.ar(cm), O.OpsCMPLT{}, O.Found.i(cm),
                             O.Arena.src0(ar, O.Arena.src0(ar, self)))

# `x < c + 1`, and `c+1` is `ADD(c, 1)`.
def dc_l9.build(+ar: O.Arena, +self: U32) -> O.Found:
  +cp = dc_cplus(ar, dc_const_side(ar, O.Arena.src0(ar, self)))
  dc_alu2(O.Found.ar(cp), O.OpsCMPLT{}, O.Arena.src(ar, O.Arena.src0(ar, self), 1),
                             O.Found.i(cp))

# `dc_hit` reads src1 for a `binop(c, x)`; here the CONST is src0, so the two
# tests are separate defs rather than one with a side parameter. `dc_hit_l` is
# `dc_hit` on the CMPLT's OWN src0.
def dc_hit_l(+ar: O.Arena,+lt: U32) -> Bool:
  dc_has(dc_val(ar, O.Arena.src0(ar, lt)))

# `x` is the non-CONST side of the FIRST MUL.
def dc_l10.x(+ar: O.Arena,+self: U32) -> U32:
  dc_other(ar, O.Arena.src0(ar, self), dc_cside(ar, O.Arena.src0(ar, self)))

# The `cvar` side of a pattern whose cvar is `src1` -- `dc_hit` reads `src1` of
# the node itself, and so does this. ONLY FOR A NON-COMMUTATIVE OP: rule 15's
# `x.alu(SHL, cvar('n'))` has a fixed order, and rule 10's `y*c` does not, so a
# rule on a commutative op must use `dc_hit_s`. Getting that wrong is what kept
# `l26` from firing; see the mutation table.
def dc_hit_m(+ar: O.Arena,+m: U32) -> Bool:
  dc_has(dc_val(ar, O.Arena.src(ar, m, 1)))

# `-c < x`, and `-c` is `MUL(c, C(-1))` -- `UOp.__neg__` is `self * (-1)`.
def dc_l11.build(+ar: O.Arena, +self: U32) -> O.Found:
  +m = dc_m1(ar, O.Arena.src(ar, self, 1))
  dc_alu2(O.Found.ar(m), O.OpsCMPLT{}, O.Found.i(m), dc_l10.x(ar, self))

# `c1.val+1 == c2.val-1`. The two CONSTs are the AND's src0.src0 and src1.src1.
def dc_l12.val(+ar: O.Arena,+self: U32) -> Bool:
  U32.is_eq(U32.add(dc_ival(dc_val(ar, dc_l12.c1(ar, self))), 1),
            U32.sub(dc_ival(dc_val(ar, dc_l12.c2(ar, self))), 1))

def dc_l13.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(dc_is_not(ar, self), O.op_is(ar, O.Arena.src0(ar, self), O.OpsCMPNE{}))

def dc_l13(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l13.go(F.Folded.ar(fx), self, dc_l13.pat(F.Folded.ar(fx), self))

# `c.val - 1` -- op.py:74. The CONST's VALUE and not the log of it, which is what
# the `s3` row is for: `dc_cval` is the log and `dc_cminus1` is the mask, and
# using the log gives `x & 1` where Python gives `x & 3`.
def dc_cminus1(+ar: O.Arena, +u: U32) -> U32:
  U32.sub(dc_ival(dc_val(ar, O.Arena.src(ar, u, 1))), 1)

# THE SAME TWO READS for a COMMUTATIVE node, where the CONST may be EITHER src.
# `dc_cval`/`dc_hit` read `src1` because FLOORDIV and CDIV are not commutative, and
# a rule that reuses them on a MUL reads the OTHER operand: `l25` is
# `MUL(C(4), i)`, `dc_cval` there sees the PARAM, answers 0, and the rule skips.
def dc_cval_s(+ar: O.Arena, +u: U32) -> U32:
  dc_pow2(dc_ival(dc_val(ar, dc_const_side(ar, u))))

def dc_hit_s(+ar: O.Arena, +u: U32) -> Bool:
  dc_has(dc_val(ar, dc_const_side(ar, u)))

# `powers_of_two.get(c.val, 0)` and `c.val in powers_of_two` -- the TWO reads of
# op.py:64. `dc_cval` is the get (0 for "not a power of two" AND for `1`, which
# is what makes the `if v` lambdas skip on `c == 1`); `dc_hit` is the membership
# test. Getting them the same way round is the bug `s2`/`s5` exist to catch.
def dc_cval(+ar: O.Arena,+u: U32) -> U32:
  dc_pow2(dc_ival(dc_val(ar, O.Arena.src(ar, u, 1))))

# `UPat.var("x", dtypes.ints)//UPat.cvar("c")` -- op.py:70. FLOORDIV is NOT in
# `GroupOp.Commutative`, so there is no side question: the CONST is `src1` and
# the numerator is `src0`. The `dtypes.ints` conjunct is on the NUMERATOR and is
# load-bearing -- `s7` is a uint32 numerator and it SKIPS this rule.
def dc_s0.put(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_shr(ar, O.Arena.src0(ar, self), dc_cval(ar, self))}
    case False{}: None{}

def dc_l1.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_l1.put(ar, dc_other(ar, self, dc_cside(ar, self)), dc_cval_s(ar, self))
    case False{}: None{}

# ---- rule 2 -- op.py:91-92. `u // 2**y -> u >> y` for an UNSIGNED numerator.
# CDIV is not commutative, so the CONST is `src1` with no side question, and the
# `dtypes.uints` conjunct is what separates this rule from rule 3. `l6` is the
# row and `l7` is its negative: the same `// 4` on a SIGNED numerator skips here.
def dc_l2.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_shr(ar, O.Arena.src0(ar, self), dc_cval(ar, self))}
    case False{}: None{}

def dc_is_m1(+ar: O.Arena,+u: U32) -> Bool:
  U32.is_eq(dc_ival(dc_val(ar, dc_const_side(ar, u))), 4294967295)

# ---- rules 8 and 9 -- op.py:110-111. `!(x < c) -> c-1 < x` and
# `!(c < x) -> x < c+1`. The shared shape is
# `CMPNE(CMPLT(a, b), C(True))` and the two rules differ only in WHICH of `a`
# and `b` is the CONST. `c-1` is `ADD(c, MUL(1,-1))` and `c+1` is `ADD(c, 1)` --
# `out_l12` and `out_l13` are the rows and they show it, because a port that
# writes a plain CONST `C(4)` gets both of them wrong.
def dc_l8.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l8.build(ar, self)}
    case False{}: None{}

def dc_l9.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l9.build(ar, self)}
    case False{}: None{}

def dc_l10.body(+ar: O.Arena,+self: U32) -> O.Found:
  +m = dc_m1(ar, dc_const_side(ar, O.Arena.src(ar, self, 1)))
  +p = dc_alu2(O.Found.ar(m), O.OpsMUL{}, dc_other(ar, O.Arena.src(ar, self, 1), dc_cside(ar, O.Arena.src(ar, self, 1))), O.Found.i(m))
  dc_alu2(O.Found.ar(p), O.OpsCMPLT{}, O.Found.i(p), dc_l10.x(ar, self))

# The `c` of the MUL. `UPat.cvar("c")` is on `UPat.var("y", ...)*UPat.cvar("c")`,
# so which SIDE holds it is the `is_any` question of header note 2 and the reader
# has to be `dc_hit_s` -- the two are `y * c` and `c * y`. `dc_hit_m` reads
# `src1` only, which is right for rule 15's `x.alu(SHL, cvar('n'))` (SHL is not
# commutative) and wrong here: `l26` is `(C(-1) * i) < (C(3) * j)` with BOTH
# CONSTs on src0, so the fixed read sees the PARAM, says "no cvar", and the
# rule that Python answers `CMPLT(MUL(Pj,MUL),Pi)` for does not fire.
def dc_l10.val(+ar: O.Arena,+m: U32,+neg: Bool) -> Bool:
  match neg:
    case True{}: dc_is_m1(ar, m)
    case False{}: dc_hit_s(ar, m)

# ---- rule 11 -- op.py:113. `-x < c -> -c < x`. Same first MUL as rule 10 but the
# CMPLT's src1 is a bare CONST, which is what its reject set says
# (`[CONST, MUL]` against rule 10's `[MUL]`). `out_l15` is the row.
def dc_l11.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l11.build(ar, self)}
    case False{}: None{}

def dc_l15.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsADD{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_one(dc_shlside(ar, self)), dc_hit_m(ar, dc_l15.m(ar, self)))))

# `-1` is `4294967295` as a `U32`; `dc_ival` reads 0 for a side that is not a
# CONST, and `0 != -1`, so a `MUL` with no CONST side is rejected here.
def dc_l6.pat(+ar: O.Arena,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsMUL{}),
    Bool.and(dc_isn2(ar, self), dc_is_m1(ar, self)))

def dc_l6(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l6.go(F.Folded.ar(fx), self, dc_l6.pat(F.Folded.ar(fx), self))

# ---- rule 10 -- op.py:112. `-x < y*c -> y*(-c) < x`. THREE named captures and
# TWO `is_any` MULs, so both may be flipped; `l14` and `l26` are the two sides.
# The answer is `y * (-c)` where `-c` is `MUL(c, C(-1))` -- Python's `UOp.__neg__`
# is `self * (-1)` (mixin/elementwise.py:79) -- and `out_l14` is the row.
def dc_l10.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l10.body(ar, self)}
    case False{}: None{}

def dc_l15.body(+ar: O.Arena,+self: U32) -> O.Found:
  +p = dc_cint(ar, dc_powi(dc_ival(dc_val(ar, O.Arena.src(ar, dc_l15.m(ar, self), 1)))))
  dc_alu3(O.Found.ar(p), O.OpsMULACC{}, O.Arena.src0(ar, dc_l15.m(ar, self)),
                               O.Found.i(p), dc_l15.c(ar, self))

# `(x << n) + c`. The comment at op.py:120 is the reason this rule exists at
# all: MUL->SHL may run first, so the MULACC form has to be re-findable.
# `x.const_like(1<<n)` is a CONST -- a FOLDED one, because `1<<n.val` is a
# Python int and `const_like` mints it -- and `out_l21` is the row.
def dc_l15.go(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l15.body(ar, self)}
    case False{}: None{}

def dc_l15(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l15.go(F.Folded.ar(fx), self, dc_l15.pat(F.Folded.ar(fx), self))

def dc_s0.go(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s0.put(ar, self,
            Bool.and(dc_isn2(ar, self),
              Bool.and(dc_hit(ar, self),
                Bool.and(U32.is_ne(dc_cval(ar, self), 0), dc_dt(fx, O.Arena.src0(ar, self), 0)))))

def dc_s0(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s0.go(F.Folded.ar(fx), fx, self)

# One `logical_not` whose scrutinee IS the bool, with no CAST in between -- see
# the `dc_l0.x2` comment. The dtype conjunct and `dc_is_not` are the whole
# pattern; the `dtypes.bool` read is one `src0` from the CMPNE.
def dc_l0.one(+ar: O.Arena, +fx: F.Folded, +s: U32) -> Bool:
  Bool.and(dc_is_not(ar, s), dc_dt(fx, dc_l0.x2(ar, s), 2))

def dc_l1.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsMUL{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_one(dc_cside(ar, self)),
        Bool.and(U32.is_ne(dc_cval_s(ar, self), 0),
                 dc_dt(fx, dc_other(ar, self, dc_cside(ar, self)), 0)))))

def dc_l1(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l1.go(F.Folded.ar(fx), fx, self, dc_l1.pat(F.Folded.ar(fx), fx, self))

def dc_l2.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCDIV{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_hit(ar, self),
        Bool.and(U32.is_ne(dc_cval(ar, self), 0), dc_dt(fx, O.Arena.src0(ar, self), 1)))))

def dc_l2(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l2.go(F.Folded.ar(fx), fx, self, dc_l2.pat(F.Folded.ar(fx), fx, self))

def dc_l3.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCDIV{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_hit(ar, self),
        Bool.and(U32.is_ne(dc_cval(ar, self), 0), dc_dt(fx, O.Arena.src0(ar, self), 0)))))

def dc_l4.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCDIV{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_hit(ar, self), dc_dt(fx, O.Arena.src0(ar, self), 0))))

def dc_l5.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCMOD{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_hit(ar, self), dc_dt(fx, O.Arena.src0(ar, self), 0))))

# The pattern is `x < c`, so `dtypes.sints` is on the CMPLT's src0 and the CONST
# is its src1. Swapping the two makes `l12` and `l13` skip and moves nothing else.
def dc_l8.leg(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(dc_is_lt(ar, O.Arena.src0(ar, self)),
    Bool.and(dc_hit(ar, O.Arena.src0(ar, self)),
             dc_dt(fx, O.Arena.src0(ar, O.Arena.src0(ar, self)), 0)))

# The pattern is `c < x`, so the CONST is the CMPLT's src0 and `x` its src1.
def dc_l9.leg(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(dc_is_lt(ar, O.Arena.src0(ar, self)),
    Bool.and(dc_hit_l(ar, O.Arena.src0(ar, self)),
             dc_dt(fx, O.Arena.src(ar, O.Arena.src0(ar, self), 1), 0)))

# A `MUL(x, c)` on a sint. `neg` says whether the CONST must be `-1` (the `-x`
# side, rule 10's src0 and rule 11's) or may be ANY CONST (the `y*c` side).
def dc_l10.mul(+ar: O.Arena,+fx: F.Folded,+m: U32,+neg: Bool) -> Bool:
  Bool.and(O.op_is(ar, m, O.OpsMUL{}),
    Bool.and(dc_isn2(ar, m),
      Bool.and(dc_one(dc_cside(ar, m)),
        Bool.and(dc_l10.val(ar, m, neg), dc_dt(fx, dc_other(ar, m, dc_cside(ar, m)), 0)))))

def dc_l11.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCMPLT{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_has(dc_val(ar, O.Arena.src(ar, self, 1))),
               dc_l10.mul(ar, fx, O.Arena.src0(ar, self), True{}))))

def dc_l11(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l11.go(F.Folded.ar(fx), fx, self, dc_l11.pat(F.Folded.ar(fx), fx, self))

def dc_l12.leg2(+ar: O.Arena,+fx: F.Folded,+s: U32,+hi: Bool) -> Bool:
  match hi:
    case True{}: Bool.and(dc_has(dc_val(ar, O.Arena.src0(ar, s))),
                          dc_dt(fx, O.Arena.src(ar, s, 1), 0))
    case False{}: Bool.and(dc_has(dc_val(ar, O.Arena.src(ar, s, 1))),
                           dc_dt(fx, O.Arena.src0(ar, s), 0))

def dc_l0.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsAND{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_l0.one(ar, fx, O.Arena.src0(ar, self)),
               dc_l0.one(ar, fx, O.Arena.src(ar, self, 1)))))

def dc_l0(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l0.go(fx, self, dc_l0.pat(F.Folded.ar(fx), fx, self))

# `x` is the CMPLT's src1 and `c` its src0 -- the pattern is `x < c`.
def dc_l8.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(dc_is_not(ar, self), dc_l8.leg(ar, fx, self))

def dc_l8(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l8.go(F.Folded.ar(fx), fx, self, dc_l8.pat(F.Folded.ar(fx), fx, self))

# `x` is the CMPLT's src0 and `c` its src1 -- the pattern is `c < x`.
def dc_l9.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(dc_is_not(ar, self), dc_l9.leg(ar, fx, self))

def dc_l9(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l9.go(F.Folded.ar(fx), fx, self, dc_l9.pat(F.Folded.ar(fx), fx, self))

def dc_l10.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCMPLT{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_l10.mul(ar, fx, O.Arena.src0(ar, self), True{}),
               dc_l10.mul(ar, fx, O.Arena.src(ar, self, 1), False{}))))

def dc_l10(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l10.go(F.Folded.ar(fx), fx, self, dc_l10.pat(F.Folded.ar(fx), fx, self))

def dc_l12.leg.go(+ar: O.Arena,+fx: F.Folded,+s: U32,+hi: Bool,+lt: Bool) -> Bool:
  match lt:
    case True{}: dc_l12.leg2(ar, fx, s, hi)
    case False{}: False{}

# One conjunct. `hi` is True for `(c1 < x)` -- so the CONST is src0 -- and False
# for `(x < c2)` -- so it is src1.
def dc_l12.leg(+ar: O.Arena,+fx: F.Folded,+s: U32,+hi: Bool) -> Bool:
  dc_l12.leg.go(ar, fx, s, hi, dc_is_lt(ar, s))

def dc_l12.pat(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsAND{}),
    Bool.and(dc_isn2(ar, self),
      Bool.and(dc_l12.leg(ar, fx, O.Arena.src0(ar, self), True{}),
        Bool.and(dc_l12.leg(ar, fx, O.Arena.src(ar, self, 1), False{}),
                 dc_l12.same(ar, self)))))

def dc_l12(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l12.go(F.Folded.ar(fx), fx, self, dc_l12.pat(F.Folded.ar(fx), fx, self), dc_l12.val(F.Folded.ar(fx), self))

# ---- rules 4 and 5 -- op.py:99 and op.py:102-103. The two `fast_idiv` rules,
# and the two that the port CANNOT finish. `l9` and `l10` are the rows: Python
# answers `SHR(MUL(x,43),7)` and `x - 3*(x*43>>7)`, the port answers `None`,
# and the difference is the whole of the `magicgu` wall. `l27`/`l28`/`l29` are
# the rows for the three guards of `fast_idiv` that ARE ported.
def dc_l4.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_idiv(ar, O.Arena.src0(ar, self), dc_ival(dc_val(ar, O.Arena.src(ar, self, 1))),
                        dc_l4.small(ar, fx, self))
    case False{}: None{}

def dc_l4(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l4.go(F.Folded.ar(fx), fx, self, dc_l4.pat(F.Folded.ar(fx), fx, self))

def dc_l5.body(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l5.build(ar, self, dc_idiv(ar, O.Arena.src0(ar, self),
                                dc_ival(dc_val(ar, O.Arena.src(ar, self, 1))),
                                dc_l4.small(ar, fx, self)))

# `x - d * q` -- op.py:103, and `-` is `dc_sub` (divergence B). `MUL` is
# commutative, so `d * q` may be either order; Python writes `d * q`.
def dc_l5.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: dc_l5.body(ar, fx, self)
    case False{}: None{}

def dc_l5(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l5.go(F.Folded.ar(fx), fx, self, dc_l5.pat(F.Folded.ar(fx), fx, self))

# ---- rule 3 -- op.py:94-96. Signed `x // 2**y ->
# (x + (x<0 ? c-1 : 0)) >> y`.
#
# `l.const_like(l.vmin) if l.vmin == l.vmax else l` is the ONE `vmin == vmax`
# read in this file and it is the `_min_max` wall (ops.py:1104). It turns out
# NOT TO MATTER, and that is a finding rather than a convenience: `l` is
# `(x<0)`, a BOOL, so a folded `l` IS `UOp.const(vmin)`, and `l.const_like` of
# a CONST is that same CONST. BOTH arms of the ternary are the same node. So
# `dc_l3` reads `l` and the wall does not bite -- stated here because a reader
# will look for the `_min_max` and should find the argument for its absence.
def dc_l3.body(+ar: O.Arena,+self: U32) -> O.Found:
  +z = dc_cint(ar, 0)
  +l = dc_alu2(O.Found.ar(z), O.OpsCMPLT{}, O.Arena.src0(ar, self), O.Found.i(z))
  +cm = dc_cminus(O.Found.ar(l), O.Arena.src(ar, self, 1))
  +w = dc_alu3(O.Found.ar(cm), O.OpsWHERE{}, O.Found.i(l), O.Found.i(cm), O.Found.i(z))
  +s = dc_alu2(O.Found.ar(w), O.OpsADD{}, O.Arena.src0(ar, self), O.Found.i(w))
  dc_shr(O.Found.ar(s), O.Found.i(s), dc_cval(ar, self))

def dc_l3.go(+ar: O.Arena,+fx: F.Folded,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_l3.body(ar, self)}
    case False{}: None{}

def dc_l3(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_l3.go(F.Folded.ar(fx), fx, self, dc_l3.pat(F.Folded.ar(fx), fx, self))

def dc_l_apply.pick(+tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  match tag:
    case 0: dc_l_fold(acc, 0, dc_l0(fx, self))
    case 1: dc_l_fold(acc, 1, dc_l1(fx, self))
    case 2: dc_l_fold(acc, 2, dc_l2(fx, self))
    case 3: dc_l_fold(acc, 3, dc_l3(fx, self))
    case 4: dc_l_fold(acc, 4, dc_l4(fx, self))
    case 5: dc_l_fold(acc, 5, dc_l5(fx, self))
    case 6: dc_l_fold(acc, 6, dc_l6(fx, self))
    case 7: dc_l_fold(acc, 7, dc_l7(fx, self))
    case 8: dc_l_fold(acc, 8, dc_l8(fx, self))
    case 9: dc_l_fold(acc, 9, dc_l9(fx, self))
    case 10: dc_l_fold(acc, 10, dc_l10(fx, self))
    case 11: dc_l_fold(acc, 11, dc_l11(fx, self))
    case 12: dc_l_fold(acc, 12, dc_l12(fx, self))
    case 13: dc_l_fold(acc, 13, dc_l13(fx, self))
    case 14: dc_l_fold(acc, 14, dc_l14(fx, self))
    case 15: dc_l_fold(acc, 15, dc_l15(fx, self))
    case 16: dc_l_fold(acc, 16, dc_l16(fx, self))
    case 17: dc_l_fold(acc, 17, dc_l17(fx, self))
    case _: acc

def dc_l_apply(+tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dc_l_apply.pick(tag, fx, self, acc)

def dc_l_try.pick(+ok: Bool, +fx: F.Folded, +self: U32, +acc: Hit,+tag: U32) -> Hit:
  match ok:
    case True{}: dc_l_apply(tag, fx, self, acc)
    case False{}: acc

def dc_l_try(+e: O.PMEntry, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dc_l_try.pick(Bool.and(O.pm_claimed(O.PMEntry.ops(e), F.Folded.ar(fx), self),
                         O.pm_early(dc_l_tab(True{}), F.Folded.ar(fx), self,
                                    O.PMEntry.rej(e))),
                fx, self, acc, O.PMEntry.tag(e))

def dc_l_scan(+todo: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32,+acc: Hit) -> Hit:
  match todo:
    case Nil{}: acc
    case e <> t: dc_l_scan(t, fx, self, dc_l_try(e, fx, self, acc))

def late_rewrite_patterns(+disable_fast_idiv: Bool, +fx: F.Folded,+self: U32) -> Hit:
  dc_l_scan(O.PMEntrys.es(dc_l_tab(disable_fast_idiv)), fx, self, miss(F.Folded.ar(fx)))

def rw_l(+g: Gate,+n: U32) -> Hit:
  late_rewrite_patterns(False{}, F.folded(Gate.ar(g)), root(g, n))

# `UPat.var("x", dtypes.ints)%UPat.cvar("c")` -- op.py:74. The lambda tests
# MEMBERSHIP (`c.val in powers_of_two`), not the value, so `c == 1` DOES rewrite
# and gives `x & 0`. `s5` is the row and `s2` is its negative: the SAME `c` does
# NOT take the SHL rule, because that one tests the value.

def dc_s2.put(+ar: O.Arena,+self: U32,+ok: Bool) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: Some{dc_band(ar, O.Arena.src0(ar, self), dc_cminus1(ar, self))}
    case False{}: None{}

def dc_s2.go(+ar: O.Arena,+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s2.put(ar, self,
            Bool.and(dc_isn2(ar, self),
              Bool.and(dc_hit(ar, self),
                Bool.and(dc_is_pow2(dc_ival(dc_val(ar, O.Arena.src(ar, self, 1)))),
                 dc_dt(fx, O.Arena.src0(ar, self), 0)))))

def dc_s2(+fx: F.Folded,+self: U32) -> Maybe<&2, O.Found>:
  dc_s2.go(F.Folded.ar(fx), fx, self)

def dc_s_apply.pick(+tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  match tag:
    case 0: dc_s_fold(acc, 0, dc_s0(fx, self))
    case 1: dc_s_fold(acc, 1, dc_s1(fx, self))
    case 2: dc_s_fold(acc, 2, dc_s2(fx, self))
    case 3: dc_s_fold(acc, 3, dc_s3(fx, self))
    case 4: dc_s_fold(acc, 4, dc_s4(fx, self))
    case _: acc

def dc_s_apply(+tag: U32, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dc_s_apply.pick(tag, fx, self, acc)

def dc_s_try.pick(+ok: Bool, +fx: F.Folded, +self: U32, +acc: Hit,+tag: U32) -> Hit:
  match ok:
    case True{}: dc_s_apply(tag, fx, self, acc)
    case False{}: acc

def dc_s_try(+e: O.PMEntry, +fx: F.Folded, +self: U32, +acc: Hit) -> Hit:
  dc_s_try.pick(Bool.and(O.pm_claimed(O.PMEntry.ops(e), F.Folded.ar(fx), self),
                         O.pm_early(dc_s_tab(False{}, False{}), F.Folded.ar(fx), self,
                                    O.PMEntry.rej(e))),
                fx, self, acc, O.PMEntry.tag(e))

def dc_s_scan(+todo: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32,+acc: Hit) -> Hit:
  match todo:
    case Nil{}: acc
    case e <> t: dc_s_scan(t, fx, self, dc_s_try(e, fx, self, acc))

def simplifying_rewrite_patterns(+threefry: Bool, +fx: F.Folded,+self: U32) -> Hit:
  dc_s_scan(O.PMEntrys.es(dc_s_tab(False{}, threefry)), fx, self, miss(F.Folded.ar(fx)))

# ===========================================================================
# THE ROWS. A `None` is `none`; otherwise the tree TWO levels deep.
# ===========================================================================
def rw_s(+g: Gate,+n: U32) -> Hit:
  simplifying_rewrite_patterns(False{}, F.folded(Gate.ar(g)), root(g, n))

# A root index below 9 is a SIMPLIFYING fixture and at or above it a LATE one --
# the oracle's fixture order, and the reason the two tables need two readers.
def t_on.go(+s: Bool,+n: U32) -> U32:
  match s:
    case True{}: Hit.on(rw_s(fixtures(), n))
    case False{}: Hit.on(rw_l(fixtures(), n))

def t_on(+n: U32) -> U32:
  t_on.go(U32.is_lt(n, 9), n)

def t_hit.go(+s: Bool,+n: U32) -> Hit:
  match s:
    case True{}: rw_s(fixtures(), n)
    case False{}: rw_l(fixtures(), n)

def t_hit(+n: U32) -> Hit:
  t_hit.go(U32.is_lt(n, 9), n)

def t_tag(+n: U32) -> U32:
  Hit.tg(t_hit(n))

# `none` for "no rule fired" and the tag otherwise. The oracle prints `-1` and
# the index, so it prints `none` here too: one vocabulary for the two rows that
# say the same thing.
def t_tag.go(on: U32, +h: Hit) -> String:
  match on:
    case 0: "none"
    case _: U32.show(Hit.tg(h))

def t_tg_off(+n: U32) -> String:
  t_tag.go(Hit.on(t_hit(n)), t_hit(n))

def t_grown(+n: U32) -> U32:
  t_grown.go(U32.is_lt(n, 9), n, t_hit(n))

def tf_hit() -> Hit:
  simplifying_rewrite_patterns(True{}, F.folded(Gate.ar(fixtures())), Gate.tf(fixtures()))

def t_tf_grown() -> U32:
  U32.sub(O.Arena.next(Hit.ar(tf_hit())), O.Arena.next(Gate.ar(fixtures())))

# THE THREEFRY ROWS, in the FIVE-rule table, which is a DIFFERENT table.
def t_tf_on() -> U32:
  Hit.on(tf_hit())

def t_out(+n: U32) -> String:
  t_out.put(Hit.on(t_hit(n)), t_hit(n))

def t_tf_out() -> String:
  t_tf_out.put(Hit.on(tf_hit()), tf_hit())

def dc_rejstr.add(+acc: String, +nm: String, first: Bool) -> String:
  match first:
    case True{}: nm
    case False{}: String.concat([acc, ",", nm])

# The list is the FIRST argument and shrinks first, so the self-call is visibly
# decreasing (`t` is the tail and `l` is spent).
def dc_rejstr.step(+l: List<&2, O.Op>, +acc: String) -> String:
  match l:
    case Nil{}: acc
    case o <> t: dc_rejstr.step(t, dc_rejstr.add(acc, dc_opname(o), dc_rejstr.first(acc)))

def dc_rejstr(m: Maybe<&2, O.PMEntry>) -> String:
  match m:
    case Some{+e}: dc_rejstr.step(O.PMEntry.rej(e), dc_rejstr.put(O.PMEntry.rej(e)))
    case None{}: "-"

def t_rej(+n: U32) -> String:
  dc_rejstr(dc_entry_l(n))

def t_rejs(+n: U32) -> String:
  dc_rejstr(dc_entry_s(n))

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("nrules_s", t_nrules_s())
    b : Unit <- row("nrules_l", t_nrules_l())
    c : Unit <- row("nrules_l_noidiv", t_nrules_noidiv())
    d : Unit <- row("nrules_s_no3f", t_nrules_s3f())
    e : Unit <- row("nroots", nroots(fixtures()))
    g : Unit <- rows("tf_split", tf_split_str(Gate.ar(fixtures()), 13))
    h : Unit <- row("on_s9", t_tf_on())
    i : Unit <- rows("out_s9", t_tf_out())
    row("grown_s9", t_tf_grown())
    # the four SIMPLIFYING reject sets and the eighteen LATE ones
    j : Unit <- rows("rejs0", t_rejs(0))
    k : Unit <- rows("rejs1", t_rejs(1))
    l : Unit <- rows("rejs2", t_rejs(2))
    m : Unit <- rows("rejs3", t_rejs(3))
    n : Unit <- rows("rejl0", t_rej(0))
    o : Unit <- rows("rejl1", t_rej(1))
    p : Unit <- rows("rejl2", t_rej(2))
    q : Unit <- rows("rejl3", t_rej(3))
    r : Unit <- rows("rejl4", t_rej(4))
    s : Unit <- rows("rejl5", t_rej(5))
    t : Unit <- rows("rejl6", t_rej(6))
    u : Unit <- rows("rejl7", t_rej(7))
    v : Unit <- rows("rejl8", t_rej(8))
    w : Unit <- rows("rejl9", t_rej(9))
    x : Unit <- rows("rejl10", t_rej(10))
    y : Unit <- rows("rejl11", t_rej(11))
    z : Unit <- rows("rejl12", t_rej(12))
    a1 : Unit <- rows("rejl13", t_rej(13))
    b1 : Unit <- rows("rejl14", t_rej(14))
    c1 : Unit <- rows("rejl15", t_rej(15))
    d1 : Unit <- rows("rejl16", t_rej(16))
    e1 : Unit <- rows("rejl17", t_rej(17))
    # the SIMPLIFYING fixtures s0..s8
    f1 : Unit <- row("on_s0", t_on(0))
    g1 : Unit <- rows("out_s0", t_out(0))
    h1 : Unit <- rows("tag_s0", t_tg_off(0))
    i1 : Unit <- row("on_s1", t_on(1))
    j1 : Unit <- rows("out_s1", t_out(1))
    k1 : Unit <- rows("tag_s1", t_tg_off(1))
    l1 : Unit <- row("on_s2", t_on(2))
    m1 : Unit <- rows("out_s2", t_out(2))
    n1 : Unit <- rows("tag_s2", t_tg_off(2))
    o1 : Unit <- row("on_s3", t_on(3))
    p1 : Unit <- rows("out_s3", t_out(3))
    q1 : Unit <- rows("tag_s3", t_tg_off(3))
    r1 : Unit <- row("on_s4", t_on(4))
    s1 : Unit <- rows("out_s4", t_out(4))
    t1 : Unit <- rows("tag_s4", t_tg_off(4))
    u1 : Unit <- row("on_s5", t_on(5))
    v1 : Unit <- rows("out_s5", t_out(5))
    w1 : Unit <- rows("tag_s5", t_tg_off(5))
    x1 : Unit <- row("on_s6", t_on(6))
    y1 : Unit <- rows("out_s6", t_out(6))
    z1 : Unit <- rows("tag_s6", t_tg_off(6))
    a2 : Unit <- row("on_s7", t_on(7))
    b2 : Unit <- rows("out_s7", t_out(7))
    c2 : Unit <- rows("tag_s7", t_tg_off(7))
    d2 : Unit <- row("on_s8", t_on(8))
    rows("out_s8", t_out(8))
    # the LATE fixtures l0..l29
    row("on_l0", t_on(9))
    rows("out_l0", t_out(9))
    rows("tag_l0", t_tg_off(9))
    row("on_l1", t_on(10))
    rows("out_l1", t_out(10))
    rows("tag_l1", t_tg_off(10))
    row("on_l2", t_on(11))
    rows("out_l2", t_out(11))
    rows("tag_l2", t_tg_off(11))
    row("on_l3", t_on(12))
    rows("out_l3", t_out(12))
    rows("tag_l3", t_tg_off(12))
    row("on_l4", t_on(13))
    rows("out_l4", t_out(13))
    row("on_l5", t_on(14))
    rows("out_l5", t_out(14))
    row("on_l6", t_on(15))
    rows("out_l6", t_out(15))
    rows("tag_l6", t_tg_off(15))
    row("on_l7", t_on(16))
    rows("out_l7", t_out(16))
    rows("tag_l7", t_tg_off(16))
    row("on_l8", t_on(17))
    rows("out_l8", t_out(17))
    rows("tag_l8", t_tg_off(17))
    row("on_l9", t_on(18))
    rows("out_l9", t_out(18))
    rows("tag_l9", t_tg_off(18))
    row("on_l10", t_on(19))
    rows("out_l10", t_out(19))
    rows("tag_l10", t_tg_off(19))
    row("on_l11", t_on(20))
    rows("out_l11", t_out(20))
    rows("tag_l11", t_tg_off(20))
    row("on_l12", t_on(21))
    rows("out_l12", t_out(21))
    rows("tag_l12", t_tg_off(21))
    row("on_l13", t_on(22))
    rows("out_l13", t_out(22))
    rows("tag_l13", t_tg_off(22))
    row("on_l14", t_on(23))
    rows("out_l14", t_out(23))
    rows("tag_l14", t_tg_off(23))
    row("on_l15", t_on(24))
    rows("out_l15", t_out(24))
    rows("tag_l15", t_tg_off(24))
    row("on_l16", t_on(25))
    rows("out_l16", t_out(25))
    rows("tag_l16", t_tg_off(25))
    row("on_l17", t_on(26))
    rows("out_l17", t_out(26))
    row("on_l18", t_on(27))
    rows("out_l18", t_out(27))
    rows("tag_l18", t_tg_off(27))
    row("on_l19", t_on(28))
    rows("out_l19", t_out(28))
    rows("tag_l19", t_tg_off(28))
    row("on_l20", t_on(29))
    rows("out_l20", t_out(29))
    rows("tag_l20", t_tg_off(29))
    row("on_l21", t_on(30))
    rows("out_l21", t_out(30))
    rows("tag_l21", t_tg_off(30))
    row("on_l22", t_on(31))
    rows("out_l22", t_out(31))
    rows("tag_l22", t_tg_off(31))
    row("on_l23", t_on(32))
    rows("out_l23", t_out(32))
    rows("tag_l23", t_tg_off(32))
    row("on_l24", t_on(33))
    rows("out_l24", t_out(33))
    row("on_l25", t_on(34))
    rows("out_l25", t_out(34))
    rows("tag_l25", t_tg_off(34))
    row("on_l26", t_on(35))
    rows("out_l26", t_out(35))
    rows("tag_l26", t_tg_off(35))
    row("on_l27", t_on(36))
    rows("out_l27", t_out(36))
    rows("tag_l27", t_tg_off(36))
    row("on_l28", t_on(37))
    rows("out_l28", t_out(37))
    row("on_l29", t_on(38))
    rows("out_l29", t_out(38))
    # the GROWTH counts, which are the numeric discriminators
    row("grown_s0", t_grown(0))
    row("grown_s1", t_grown(1))
    row("grown_s7", t_grown(16))
    row("grown_l19", t_grown(28))
    row("grown_l27", t_grown(36))

def main() -> IO(Unit):
  gate()

# ===========================================================================
# THE MUTATION TABLE AND WHAT IS NOT DONE. Both are measured, and the second
# one is the honest half of the gate.
#
# THE MUTATIONS, by hand, one edit at a time, diffing the interpreted lane
# against `.agents/slop/dc-oracle.py`. A row only ONE mutation moves is a
# LOCALISED row; say so, because the table is not one-row-per-bug.
#
# | mutation | rows moved | what it catches |
# | --- | --- | --- |
# | `dc_s_fold.go` / `dc_l_fold.go`: first-wins -> last-wins | `tag_s0..s8`, `tag_l1`, `tag_l3`, `tag_l6..l8`, `tag_l11..l15`, `tag_l18..l23`, `tag_l25`, `tag_l27`, and every `out_` that follows one of those | `PatternMatcher.rewrite` returns the FIRST non-`None` (ops.py:1606). Keying the fold on the NEW verdict instead of the ACCUMULATOR is the classic wrong answer and `l7`/`l8`/`l9` are the fixtures that see it |
# | `dc_side.go`'s three arms -> the first two only | every `tag_` and `out_` of a commutative rule | header note 2: `UPat.alu` (ops.py:1533) is an `is_any` over BOTH orders for an op in `GroupOp.Commutative` |
# | `dc_cval` <- `dc_cval_s` on rules 1/6 (or drop `dc_cval_s`) | `on_l25`, `out_l25` | the commutative read: `MUL(C(4), i)` has the CONST on src0 and `dc_cval` reads src1 |
# | `dc_s2.pat`: `dc_is_pow2(dc_cval(...))` | `on_s5`, `out_s5` | op.py:64 read as a VALUE (`0`, and `1 -> 0` is falsy) rather than a MEMBERSHIP test |
# | `dc_s0.pat`: drop the `U32.is_ne(dc_cval(...), 0)` conjunct | `on_s2`, `out_s2` | the other half of the same pair: `x // 1` is NOT rewritten |
# | `dc_s0.pat` / `dc_s1`: drop the `dtypes.ints` conjunct | `on_s7`, `out_s7` | `dtypes.ints` is the four SIGNED widths and is NOT weakint, so `Cls.is_int` is the wrong test |
# | `dc_fd.gen` / `dc_fm.gen`: drop the `O.OpsAND{}` | `out_s1`, `out_s2`, `out_s4`, `out_s6` | op.py:56 ANDs `a.alu(CMOD,b).ne(0)` with `(a<0).ne(b<0)`; without the `&` the tree is a CMPNE of two CMPNEs |
# | `dc_sub` -> a real `SUB` node | `out_s1`, `out_s2`, `out_s4`, `out_s6`, `out_l10` | divergence B: `__sub__` is `self + (other * -1)` |
# | `dc_lnot`: re-insert the `cast(bool)` | `on_l0`, `out_l0`, `on_l18`, `out_l18` | `mixin/dtype.py:19` elides the CAST on a bool, and the port's `logical_not` must too or rule 13 cannot see its own pattern |
# | `dc_l8.leg` / `dc_l9.leg`: swap the two sides | `on_l12`, `out_l12`, `on_l13`, `out_l13` | `x < c` puts `x` on src0 and `c < x` puts it on src1; the two rules differ only there |
# | `dc_l15.c` -> `dc_l14.c` | `out_l21` | rule 15's addend is the non-SHL side and `dc_l14.c` keys on a MUL |
# | `dc_l12.same` -> `True{}` | `on_l16`, `out_l16` | THE IDENTITY CHECK. `l16` binds `x` once and `l17` binds it to two nodes; without the check the rule matches `l17` too and answers `y.eq(c1+1)` |
# | `dc_l12.val` -> `True{}` | `on_l16`, `out_l16` | `c1.val+1 == c2.val-1`; `l24` is the negative |
# | `dc_l0.x2` -> the second `src0` (re-read the `CAST`) | `on_l0`, `tag_l0`, `out_l0` | THE CAST-SKIP: `UPat.cast` (ops.py:1512) drops the node when the pattern already says `dtypes.bool` and `mixin/dtype.py:19` elides it on a bool, so the scrutinee of `logical_not` is ONE hop out. Two hops reads `src0` of a PARAM -- the bottom NOOP -- and `dc_dt` of that is not bool |
# | `dc_l0.x`/`dc_l0.y` -> the third `src0` | `out_l0` only | the same walk-off-the-end, and this is the row that SHOWS it: `out_l0` becomes `CMPNE(OR(NOOP,Pb),C(1))` while `on_l0` and `tag_l0` stay put, because the wrong node is only visible in the ANSWER |
# | `dc_l12.c1` -> the third `src0` | `on_l16`, `tag_l16`, `out_l16` | `c2` is two hops from the AND and `c1` is the same distance; the third `src0` read `src0` of a CONST, `dc_val` answered `None`, and `dc_ival` of that is 0 -- so the claim check compared `0 + 1 == c2.val - 1` |
# | `dc_l10.val` -> `dc_hit_m` on the `y*c` side | `on_l26`, `tag_l26`, `out_l26` | `UPat.var("y", ...)*UPat.cvar("c")` is an `is_any` over BOTH orders, so the `cvar` is not always `src1`; `dc_hit_s` reads `dc_const_side` and `l14` is the negative row (`out_l26` prints `CMPLT(MUL(Pj,MUL),Pi)`, both MULs in Python's own order) |
# | `dc_cval`/`dc_cminus1`: the log where the value is wanted | `out_s3` | `x & (c.val-1)` is `c.val - 1` and not `log2(c) - 1` |
# | `dc_sfx1.put`/`dc_sfx2.put`: two arms instead of three | `out_l3`, `out_l19`, `out_l20`, `out_l21` | a ONE-src node's `src1` is the arena's BOTTOM NOOP and printing it puts `NOOP` in every unary rewrite |
# | `dc_arity1`: `min(nsrc,3)` without the `- 1` | `out_l3`, `out_l19`, `out_l20`, `out_l21`, `out_s9` | the arity test itself |
# | `dc_entry_l` -> `dc_l_tab(True{})` | `rejl6..rejl17` | `disable_fast_idiv` renumbers the tags, so the reject rows must be read from the EIGHTEEN-rule table |
# | `dc_rejstr.first`: length 1 instead of 0 | every `rejs`/`rejl` row | the join's leading-comma bug |
# | `dc_tfg.pick`: always the `a` list | `grown_s9` only | `rotations[i % 2]` -- the list alternates, and the tree's SIZE is the only thing that sees it, because `out_s9` prints two levels of a 153-node tree |
# | `dc_tfr`: the OLD `xr[1]` on the right of the XOR | `grown_s9` | Python evaluates the whole right-hand tuple before the assignment |
# | `dc_tfg.step`: `i` instead of `i + 1` in the `ks` read | `grown_s9` | `ks[i%3]` and `ks[(i+1)%3]` are the two different entries |
# | `threefry2x32`: swap the two `dc_tf_half` calls | `tf_split`, `grown_s9` | `x.cast(u32)` is the LOW word and `x >> 32` the HIGH one |
#
# SEVEN ROWS DIFFER FROM PYTHON. Grouped by cause, and the causes are two:
#
# A. SIX ROWS ARE THE `magicgu` WALL, and they are SUPPOSED to differ:
#      on_l9 tag_l9 out_l9   Python: SHR(MUL(Pz,C(43)),C(7))
#      on_l10 tag_l10 out_l10 Python: ADD(Pz,MUL(MUL,C(-1)))
#    The port prints `none` because op.py:23 is P3. `dc_idiv` answers the three
#    guards that ARE ported -- `d <= 0` (`l28`), `x.vmin < 0` (`l29`) and
#    `vmax < d` (`l27`, which the port rewrites to `C(0)` and Python does too) --
#    and reports the fourth. This is `divandmod.bend`'s reading of Python's
#    `raise`: the condition is REPORTED and the ladder treats it as a skip.
#
# B. ONE ROW IS A PRINTER ARTEFACT and the port is RIGHT:
#      out_s9  bend OR(SHL(CAST,C(32)),CAST(ADD))  python OR(SHL(ADD,C(32)),ADD(ADD,XOR))
#    The oracle's `uncast` erases EVERY CAST whose arg differs from its src's
#    dtype, and `dc_tf_join`'s `cast(xr1, uint64)` is exactly such a CAST and is
#    NOT a promotion. The oracle's erasure rule is too coarse; the port's tree
#    is Python's tree. FIXING IT IS AN ORACLE FIX, not a port fix.
#
# ---------------------------------------------------------------------------
# THE THREE RULES THAT DID NOT FIRE, NOW DIAGNOSED. Nine rows, THREE readers,
# and ONE shape of mistake: a reader that steps one hop further than the tree is
# deep, or a predicate that reads a FIXED side where the op is commutative. Both
# land on the arena's bottom NOOP -- index 0, a node with no srcs and no dtype
# -- and both are invisible until a reader has to NAME a node, because every
# predicate before them still says TRUE. Each was bisected with a scratch probe
# printing the rule's own conjuncts one at a time; the decisive reading is
# named in each paragraph and the rows each fix moves are in the mutation table.
# Two of the three fixes are a `src0` DELETED and one is a reader swapped for the
# commutative one -- which is why the "which side is the CONST" machinery that
# the contradiction pointed at (`dc_cside`, `dc_const_side`, `dc_pick_side`) was
# right all along and had exactly one caller that did not use it.
#
#   rule 0  (op.py:85-86)  `dc_l0.x2` read a `CAST` that is in NEITHER the
#     pattern nor the tree. `UPat.cast` (ops.py:1512) returns `self` when the
#     pattern already says `dtypes.bool`, and `mixin/dtype.py:19` elides it on a
#     bool `x`, so `!x` is `CMPNE(x, C(True))` and the scrutinee is ONE hop.
#     Reading two hops gave `src0` of a PARAM -- the bottom NOOP -- so
#     `dc_dt(fx, noop, 2)` was False and `dc_l0.pat` was False. The same extra
#     hop was in `dc_l0.x`/`dc_l0.y`, and it is visible on its own: restoring it
#     leaves `on_l0` at 1 and prints `CMPNE(OR(NOOP,Pb),C(1))`. A reader that
#     walks off the end of a tree is the whole failure mode.
#   rule 12 (op.py:114-115)  `dc_l12.c1` had a THIRD `src0` where its sibling
#     `dc_l12.c2` has two. Both CONSTs are two steps from the AND, so the third
#     `src0` read `src0` of a CONST -- again the bottom NOOP -- `dc_val` of it
#     is `None`, `dc_ival` of `None` is 0, and `dc_l12.val` compared
#     `0 + 1 == c2.val - 1`, which is false. `dc_l12.pat` was TRUE throughout:
#     the rule was refused by its CLAIM CHECK, not its shape, which is why the
#     shape was never the suspect.
#   rule 10 (op.py:112)  `dc_l10.val`'s `y*c` conjunct was `dc_hit_m`, which
#     reads `src1`. `UPat.var("y", ...)*UPat.cvar("c")` is an `is_any` over both
#     orders, so `l26` (`C(3) * y`, CONST on src0) has no CONST on src1 and the
#     rule was refused. `dc_hit_s` reads `dc_const_side` and answers both sides.
#     THE CONTRADICTION THAT PINNED IT was `l1`/`l25` (rule 1, CONST either
#     side) firing through `dc_cval_s` and `l14`/`l26` (rule 10, CONST either
#     side) not: `dc_cside` and `dc_pick_side` were never wrong, only the one
#     rule that did not USE them. `l25` and `l26` are still the commutativity
#     rows from header note 2, and both now answer.
#
# WHAT NEXT, in the order the walls fall.
#   1. `i64_mul` / `i64_div` / `i64_mod` / `i64_shl` and an UNSIGNED 64-bit
#      compare in `helpers.bend` -- the `magicgu` block's five items. Nothing in
#      this file changes when they land: that block is already the only caller.
#   2. `UOp._min_max` (ops.py:1104) -- it does NOT bite here (see `dc_vmin`), and
#      finding that out was worth the three lines it took.
#   3. `Renderer.supported_dtypes()` (renderer/__init__.py:85) -- op.py:32, and
#      there is no `renderer` in the port at all.
#
# CLOSED. Item 4 was the three unfired rules; they are diagnosed and fixed above,
# and `nroots`-addressed rows `l0`/`l16`/`l26` now answer what Python answers.
# The lesson worth carrying to the next unit: a predicate chain that ends on a
# NODE READ is only as deep as the tree, and reading one hop too far lands on
# the bottom NOOP rather than on an error -- so the conjunct that refuses a
# fixture is the LAST one, not the first, and `out_*` printing a NOOP is the
# only honest witness.
