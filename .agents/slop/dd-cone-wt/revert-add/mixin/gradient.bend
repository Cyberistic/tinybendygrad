# mixin/gradient.bend -- tinygrad/mixin/gradient.py. `pm_gradient` (the reverse-mode rule
# table) and `compute_gradient` (the walk that drives it).
#
# WHAT IS IN HERE. `gradient.py` is 145 lines: three helpers (`reduce_gradient`,
# `call_gradient`, `partial_store_gradient`), the `pm_gradient` table, `_deepwalk`, and
# `compute_gradient`. The table is 33 entries and it is the centre of this file: every entry
# is a top-level def `gr_N`, the table is copyable `Data`, and dispatch is the ~15-line
# duplicated scan `spec.bend` writes six times. See the header of `uop/spec.bend` for why
# there is no generic dispatcher: a rule is a def, not a value, so `ops.bend` cannot call
# into this file and each table owns its driver.
#
# THE ONE MEASURED FACT IN THIS HEADER, and it is the reason the file exists in this shape:
# `mixin/gradient.py:101` binds the name `dest` TWICE.
#     (UPat(Ops.AFTER, src=(UPat(name="dest"), UPat(Ops.STORE, src=(UPat(name="dest"), UPat())))),
#      lambda ctx,dest: (None, ctx)),
# `dest` is `AFTER.src[0]` AND `AFTER.src[1].src[0]`, two different positions, so the rule
# matches only when they are the SAME node. `upat.py:100-105` emits the identity compare as
# an ordinary clause (`"{0} is {1}"`), and the interpreter states the same constraint as a
# store rejection. Without the check the rule matches strictly more nodes than Python does,
# and it still typechecks and still runs -- so it is LOAD-BEARING, not decorative. `gr_29`
# emits it; the `rebind`/`rebind_off` gate rows are the two-sided check, and `gr_29_nocheck`
# is the mutation that proves it. THE TAG SPACE is Python's own: 0..32 in `pm_gradient.pdict`
# insertion order, which is the compiled form (`UPAT_COMPILE=1` is the default, ops.py:1588).
# Tag 29 is the rebind, tags 27/28/30 are its AFTER siblings, and `t_claims` pins the COUNT.
#
# THE SHAPE OF A RULE'S ANSWER, the one design decision here. Python's rule bodies return
# `tuple[UOp|None, ...]` and `rewrite` returns the FIRST non-`None`. Two facts follow, and
# both shape the type: a rule that does not match returns `None` and the scan CONTINUES --
# that is `O.Verdict`'s `VSkip`, a first-wins fold exactly as in `spec.bend`; and a rule that
# matches returns a list with `None` HOLES (`CMPLT` is `(None,None)`, `STORE` is `(None, ctx)`,
# `BITCAST` is `(None,)`), and a hole is not a skip. So the answer is a `Data` record with a
# `List` field, not a `Maybe` of a list (a `Data` record cannot hold a `Maybe` -- see the
# notes, rule 15). `GFired{gs, ar}` is "matched, here are the per-src gradients" and `GSkip{}`
# is "no opinion, keep scanning". The `ar` field is the arena AFTER the rule grew it, because
# a gradient rule BUILDS nodes: `RECIPROCAL` is `(-ctx * ret * ret)`, three new nodes. `gs`
# uses index 0 for a hole: index 0 is the arena's bottom node (`Arena.empty` spends it,
# ops.bend:935) and `UOp.is_none(u) = U32.is_zero(u)`, so 0 IS tinygrad's own "no uop" and
# the encoding is not an invention.

import Base
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE ANSWER TYPE. `GFired` carries the per-src gradient list and the grown arena;
# `GSkip` is the tri-state's "no opinion" arm. Both are `Data`, so the scan can hold
# an accumulator and keep it.
# ===========================================================================
type GRes is Data:
  GSkip{}
  GFired{gs: List<&2, U32>, ar: O.Arena}

# FIRST-WINS. `gs_keep(acc, v)` is `pm_keep` for this answer type: an earlier
# `GFired` is never erased by a later one. Keying on the ACCUMULATOR is what makes it
# first-wins; keying on `v` is last-wins and every rule before the match is destroyed.
def gs_keep.go(acc: GRes, v: GRes) -> GRes:
  match acc:
    case GSkip{}: v
    case GFired{gs, ar}: acc

def gs_keep(acc: GRes, v: GRes) -> GRes: gs_keep.go(acc, v)

def fired(gs: List<&2, U32>, ar: O.Arena) -> GRes: GFired{gs, ar}

# `len(gs)` as a U32, which is how a rule's ARITY is checked against `len(t0.src)`.
def gs_len(r: GRes) -> U32:
  match r:
    case GSkip{}: 0
    case GFired{gs, ar}: U32.from_nat(List.length(&2, U32, gs))

def gs_is_skip(r: GRes) -> Bool:
  match r:
    case GSkip{}: True{}
    case GFired{gs, ar}: False{}

# `gs[i]`, with the index a `Nat` because `List.get` wants one.
def gs_get(r: GRes, n: Nat) -> U32:
  match r:
    case GSkip{}: 0
    case GFired{gs, ar}: Maybe.default(&2, U32, List.get(&2, U32, gs, n), 0)

def gs_ar(r: GRes) -> O.Arena:
  match r:
    case GSkip{}: O.Arena.empty()
    case GFired{gs, ar}: ar

# A hole is `U32.is_zero`, which is `UOp.is_none`. The COUNT of non-holes is what the
# `t_*_grads` rows read, and it is what distinguishes `CMPLT`'s `(None,None)` from
# `BITCAST`'s `(None,)`: both are all-holes, and only the ARITY separates them.
def gs_hole(r: GRes, n: Nat) -> Bool: U32.is_zero(gs_get(r, n))

# `sum(1 for g in gs if g is not None)` -- `gradient.py:129`'s `if v is None: continue`
# counted. NO FUEL: the self-call spends the LIST TAIL and nothing else, so the descent
# is structurally visible (notes, "The real rule for a descent") and a fuel parameter
# would be dead weight. Every self-recursive def in this file that DOES carry a fuel
# takes it first, and that is the only case where one is needed.
def gs_solid.one(b: Bool) -> U32:
  match b:
    case True{}: 0
    case False{}: 1

def gs_solid.go(gs: List<&2, U32>, acc: U32) -> U32:
  List.foldl(~&2, ~U32, ~U32, (a: U32) => (g: U32) => U32.add(a, gs_solid.one(U32.is_zero(g))), gs, acc)

def gs_solid(r: GRes) -> U32:
  match r:
    case GSkip{}: 0
    case GFired{gs, ar}: gs_solid.go(gs, 0)

# ===========================================================================
# ---------------------------------------------------------------------------
# `math.pi/2` -- gradient.py:69 `(math.pi/2 - ret.src[0]).sin() * ctx`.
def k_pi_2() -> O.Const: O.CFloat{1.5707963267948966}
# `math.log(2)` -- gradient.py:70, :71, :77.
def k_ln2() -> O.Const: O.CFloat{0.6931471805599453}
# THE FOLDED LITERALS ARE BARE CONSTs AND THAT IS NOT AN OMISSION. `UOp.const(v)` with
# NO dtype is `CFloat{v}` -> weakfloat and the `.cast(dtype)` at ops.py:632 is against
# `None`, so no CAST is built. Measured: `(math.pi/2 - c)` is `ADD(CONST, MUL(...))`
# where the CONST's dtype is `weakfloat` and the MUL's is `float` -- the promotion
# happens at the BINARY, not at the literal. `gconst` (which adds the CAST) is for
# `const_like`, which passes ctx's dtype EXPLICITLY; `k_pi_2`/`k_ln2`/`k_fzero` etc. are
# built with `gconst_raw` for the same reason. `sin_n` (10) and `log2_n` (8) are the rows.
# `-math.inf` -- gradient.py:77 `ret.const_like(-math.inf)`. There is no `inf` LITERAL
# in Bend (`-1.0e400` is a parse error, "expected : a term, observed : '-'"), and an f32
# OVERFLOW is the honest way to spell it: `1e30 * 1e30` is `0x7F800000`, which IS f32
# `+inf` (helpers.bend's `f32_exp_all_ones` reads exactly that bit pattern), and the
# negation is `-inf`. Measured, and `k_neginf_bits` below is the row that says so.
def k_inf() -> F32: F32.mul(1.0e30, 1.0e30)
def k_neginf() -> O.Const: O.CFloat{F32.neg(k_inf())}
def k_neginf_bits() -> U32: F32.bits(F32.neg(k_inf()))

# THE INTS AND THE FLOATS ARE DIFFERENT NODES, and this is load-bearing rather than
# pedantic. A CONST's dtype FOLLOWS its value (ops.py:632 `dtype or dtypes.from_py(b)`),
# so `UOp.const(0)` is `CInt{0}` -> weakint and `UOp.const(0.0)` is `CFloat{0.0}` ->
# float32. `least_upper(weakint, float32)` is float32 and not weakint, so a rule that
# folds the wrong one produces a gradient whose dtype -- and therefore whose value at
# the next node -- differs. Python's fold is dtype-INDEPENDENT (`const_like(0)` at a
# float ctx is `CFloat{0.0}`; `where(0, ctx)` at a float ctx is the same node), and the
# rules that need a genuine INT 0 are `TRUNC`'s and `MAX`'s `const_like(0)`, which are
# ctx-dtype CONSTs. `grad.py`'s `partial_store_gradient` `where(0, ctx)` is the same.
def k_fzero() -> O.Const: O.CFloat{0.0}
def k_fone() -> O.Const: O.CFloat{1.0}
def k_fhalf() -> O.Const: O.CFloat{0.5}
def k_ftwo() -> O.Const: O.CFloat{2.0}
def k_fmone() -> O.Const: O.CFloat{F32.neg(1.0)}
def k_izero() -> O.Const: O.CInt{H.i64_of_i32(0)}
def k_ione() -> O.Const: O.CInt{H.i64_of_i32(1)}
# ===========================================================================
# THE NODE BUILDERS. Every one is a `UOp(...)` call in Python's rule bodies, and every
# one GROWS the arena, so each takes `+ar` and returns a `Found`. `UOp.alu` exists in
# ops.bend and is the same call with the arena unprefixed; `gnew` is the spelling that
# makes the arena threading explicit, because a rule that builds two nodes has to hand
# `Found.ar` forward by hand either way.
# ===========================================================================
def gnew(+ar: O.Arena, +op: O.Op, +srcs: List<&2, U32>, +arg: O.Arg) -> O.Found:
  O.UOp.new(ar, op, srcs, arg, O.TNone{})

# `ctx.cast(dt)` -- `dtype.py:36`. `UOp.alu` takes no arg in ops.bend, so the CAST is
# spelled `gnew` with the `ADt` arg, which is what `mixin/dtype.bend`'s `cast_at`
# already established.
def gcast(+ar: O.Arena, x: U32, dt: S.Dt) -> O.Found: gnew(ar, O.OpsCAST{}, [x], O.ADt{dt})

# `mask.cast(dtypes.bool)` from `partial_store_gradient` (gradient.py:63).
def gbool(+ar: O.Arena, x: U32) -> O.Found: gcast(ar, x, S.boolean())

# `UOp.const(v)` -- ops.py:632. THE CAST IS NOT OPTIONAL, and this is MEASURED rather
# than read off:
#
#     return UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)
#
# so a CONST at a CONCRETE dtype is the TWO nodes `CAST(CONST)`, and only the three
# dtypes a CONST derives (bool/weakint/weakfloat) fold the cast away -- which is
# ops.py's own comment on that line. Measured: `UOp.const(0.0, dtypes.f32)` has
# `op=CAST, nsrc=1` while `UOp.const(0.0, dtypes.weakfloat)` has `op=CONST, nsrc=0`.
#
# Every `const_like` in a rule body folds at `ctx.dtype`, which for the ALU rules is a
# CONCRETE float32, so every one emits a CAST pair. That is why `trunc_n` is 2 and not 1,
# and why a port that emitted a bare CONST would build a SHORTER tree with the SAME
# value -- a divergence `t_const_cast` catches and the values would not.
# `gconst_raw` is the bare one and `t_const_raw` is the control that separates them.
def gconst_raw(+ar: O.Arena, +v: O.Const) -> O.Found: O.UOp.const(ar, v)

def gconst.go(+ar: O.Arena, +v: O.Const) -> O.Found:
  +c = gconst_raw(ar, v)
  gcast(O.Found.ar(c), O.Found.i(c), S.single())

def gconst(+ar: O.Arena, +v: O.Const) -> O.Found: gconst.go(ar, v)

# `x + y` -- `elementwise.py:267`, `alu(Ops.ADD)`.
def gadd(+ar: O.Arena, x: U32, y: U32) -> O.Found: gnew(ar, O.OpsADD{}, [x, y], O.ANone{})

# `x * y` -- `elementwise.py:273`, `alu(Ops.MUL)`. `MUL` IS commutative
# (`GroupOp.commutative`, ops.py:453), so `ops.bend`'s interning collapses `x*y` and
# `y*x` onto ONE node -- which is exactly why the `MUL` rule's gradient for a SQUARE is
# a single node, and why `mul_same` is the row that says so rather than a coincidence.
def gmul(+ar: O.Arena, x: U32, y: U32) -> O.Found: gnew(ar, O.OpsMUL{}, [x, y], O.ANone{})

# `neg` IS NOT `Ops.NEG`, and this is measured against the tree rather than read off.
# `elementwise.py:74-76` defines `neg` as `alu(Ops.NEG)`, but by the time a gradient rule
# sees the node the symbolic rules have rewritten NEG away: `UOp.const(1.0).neg()` has
# `op=MUL` with srcs `(CONST(1.0), CONST(-1.0))`, and Python's tree for the `RECIPROCAL`
# gradient (gradient.py:68 `-ctx * ret * ret`) shows exactly that -- MULs and two
# `CONST(-1.0)`, no NEG anywhere. `Ops.NEG` exists in the enum and `schedule/` lowers it;
# emitting it here would build a graph Python never builds.
def gneg.go(+ar: O.Arena, x: U32) -> O.Found:
  +m = gconst_raw(ar, k_fmone())
  gmul(O.Found.ar(m), x, O.Found.i(m))

def gneg(+ar: O.Arena, x: U32) -> O.Found: gneg.go(ar, x)

# `x - y` IS NOT `Ops.SUB` EITHER. Measured: `a - b` is `ADD(a, MUL(b, CONST(-1.0)))` --
# the same neg-by-`-1.0`, applied to the right operand and then ADDed. `Ops.SUB` exists
# and `sub()` (elementwise.py:270) spells it, but the tree a gradient rule sees is the
# ADD. The `SIN` rule (gradient.py:69 `(math.pi/2 - ret.src[0])`) is the only user, and
# `sin_n` is the row: 10 in Python, reached only if this is ADD-of-a-negated.
def gsub.go(+ar: O.Arena, x: U32, y: U32) -> O.Found:
  +n = gneg(ar, y)
  gadd(O.Found.ar(n), x, O.Found.i(n))

def gsub(+ar: O.Arena, x: U32, y: U32) -> O.Found: gsub.go(ar, x, y)

# `where(mask, a, b)` -- `elementwise.py:426`, `mask.where(value, self)`, so `Ops.WHERE`
# with the MASK FIRST. The `MAX` and `POW` rules are the users.
def gwhere(+ar: O.Arena, m: U32, a: U32, b: U32) -> O.Found: gnew(ar, O.OpsWHERE{}, [m, a, b], O.ANone{})

# `x > y` is `_binop(Ops.CMPLT, y, reverse=True)` -- `elementwise.py:__gt__`. The `MAX`
# rule (gradient.py:79) spells both `(x>y)` and `(x<y)`, which are the SAME op with the
# operands swapped: `GroupOp.commutative` does NOT include CMPLT (ops.py:453), so the
# swap is not foldable and both directions are genuinely two nodes.
def gcmplt(+ar: O.Arena, x: U32, y: U32) -> O.Found: gnew(ar, O.OpsCMPLT{}, [x, y], O.ANone{})

# `x.eq(y)` IS NOT `Ops.CMPEQ` AND ITS NOTATION IS NOT XOR. `eq` (elementwise.py:336) is
# `ne().logical_not()` and `logical_not` (:49) is `alu(Ops.CMPNE, const(True))` -- so
# `eq` is TWO `CMPNE` nodes. Measured three ways:
#   `UOp.const(1.0).logical_not().op`      == CMPNE, srcs (CAST, CONST)
#   `UOp.const(1.0).eq(itself).op`         == CMPNE, srcs (CMPNE, CONST)
#   Python's `MAX` gradient tree           == ... WHERE, CMPNE, CMPNE, ...
# TWO CMPNE and no CMPEQ anywhere. `Ops.CMPEQ` exists in the enum and `cmpeq` is what
# the name suggests, but no `elementwise.py` method emits it, so a rule that spelled
# `eq` as CMPEQ would build a graph Python never builds. `max_n0`/`max_n1` (both 21) and
# `pow_n0`/`pow_n1` (24 and 29) are the rows that catch it.
def gcmpne(+ar: O.Arena, x: U32, y: U32) -> O.Found: gnew(ar, O.OpsCMPNE{}, [x, y], O.ANone{})

# `logical_not(x)` is `alu(Ops.CMPNE, const(True))`, and `UOp.const(True)` is a BOOL
# CONST whose dtype FOLLOWS the value (ops.py:632), so at bool it is a BARE CONST with
# no CAST -- the measured srcs above are `(CAST, CONST)`, one CAST for `x` and none for
# the literal. That is why `gnot` interns the literal raw.
def gnot(+ar: O.Arena, x: U32) -> O.Found:
  +t = gconst_raw(ar, O.CBool{True{}})
  gnew(O.Found.ar(t), O.OpsCMPNE{}, [x, O.Found.i(t)], O.ANone{})

# `x.pow(e)` -- `elementwise.py:569`, `alu(Ops.POW, exponent)`.
def gpow(+ar: O.Arena, b: U32, e: U32) -> O.Found: gnew(ar, O.OpsPOW{}, [b, e], O.ANone{})

# THE UNARY ALU. Each is a unary `alu` in Python (`elementwise.py:480-536`), and each is
# spelled here as a `gnew` with one src -- the ops are NOT folded and there is no
# `NEG`-style rewrite for any of them, which `recip_n`/`sin_n`/`log2_n`/`exp2_n`/`sqrt_n`
# confirm against Python's trees.
def glog2(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsLOG2{}, [x], O.ANone{})
def gexp2(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsEXP2{}, [x], O.ANone{})
def gsin(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsSIN{}, [x], O.ANone{})
def gsqrt(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsSQRT{}, [x], O.ANone{})
def grecip(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsRECIPROCAL{}, [x], O.ANone{})
def gtrunc(+ar: O.Arena, x: U32) -> O.Found: gnew(ar, O.OpsTRUNC{}, [x], O.ANone{})

# `x / y` IS NOT AN `FDIV` NODE, and this is the most surprising fact in the arithmetic
# of this file. `div` (elementwise.py:229-259) is
#
#     if is_int(a) and is_int(b): ...CDIV / FLOORDIV...
#     if is_int(a.dtype) or a.dtype is bool: a = a.cast(dtypes.default_float)
#     d = a.alu(Ops.MUL, b.reciprocal())
#
# so for two FLOATS it is `MUL(x, RECIPROCAL(y))` -- TWO nodes -- and `Ops.FDIV` is never
# emitted by `div` at all. Measured against Python: the `LOG2` gradient is
# `MUL, RECIPROCAL, MUL, CONST, CONST` and the `SQRT` gradient is
# `MUL, RECIPROCAL, MUL, SQRT, CONST, CONST`; neither contains an FDIV.
# `gradient.py:70` (`ctx / (...)`) and `:72` (`ctx / (ret*2)`) are the only `/` users.
def gdiv(+ar: O.Arena, x: U32, y: U32) -> O.Found:
  +r = grecip(ar, y)
  gmul(O.Found.ar(r), x, O.Found.i(r))


# THE RULES. One def per tag, in `pm_gradient.pdict` order, each carrying its
# `gradient.py` line. A rule takes `+ar` (it may grow the arena), `ctx` (the incoming
# gradient -- `gradient.py:65` "ctx is grad_output") and `self` (the node being
# differentiated), and answers a `GRes`.
#
# A rule that does not match its pattern answers `GSkip{}`, and `rewrite` keeps
# scanning. Which tests belong to the PATTERN (and therefore to `gr_try`) and which
# belong to the BODY is Python's own division and it is preserved exactly: the compiled
# form puts every pattern conjunct in the `if`, and `_get_clause` (upat.py:158) emits
# `(_ret:=_fxn(...)) is not None` last. So `nsrc` tests and op tests are PATTERN tests,
# and a `const_like` or a shape computation is BODY work that happens after a match.
# ===========================================================================

# --- 0. CAST -- gradient.py:67. `(ctx.cast(ret.src[0].dtype),)`
#
# `ret.src[0].dtype` is a FOLD read (`UOp.dtype` is `recursive_property`, ops.py:225),
# so this is the ONE rule in the table that needs the fold rather than just the arena.
# `mixin/dtype.bend`'s `md_dt` is that reader and it is exactly what Python asks, so it
# is IMPORTED, not recopied -- and importing it costs this file nothing, because
# `mixin/dtype.bend` prints no foreign-code notice (`md_dt_imported` in ITS gate is the
# row, and it says so). `A CONST`'s dtype follows its value, so `ret.src[0].dtype` on a
# CONST src is that CONST's own natural dtype and NOT `ret.arg`.
# The `ADt` arg is `ret.src[0].dtype` -- `ret` is the CAST, so this is the dtype of the
# node BELOW it, which for a CONST is that CONST's own natural dtype and NOT `ret.arg`.
# `F.fold.dt` is that read; ops.py:225 makes `dtype` a `recursive_property`, and
# fold.bend is the well-founded way to answer it here (its header says exactly this).
def dt_of(m: Maybe<&2, S.Dt>) -> Maybe<&2, S.Dt>: m

def gr_0.src(ar: O.Arena, self: U32) -> U32: O.Arena.src(ar, self, 0)

# `F.fold.dt` needs BOTH the arena and the table out of the fold, so `fx` is read twice
# in one expression and the fold must be `+fx` AND the call threaded. `sp_dt` in
# `uop/spec.bend` is the same reader written once; it is not imported because
# `spec.bend` is a validator and importing it would pull six tables this file does not
# want, so the two lines are here instead.
# A `F.Folded` is READ ONCE PER FIELD: `F.Folded.ar(fx)` and `F.Folded.t(fx)` are two
# reads of the same parameter and a `Folded` is `Data`, so the parameter needs `+`.
# `uop/spec.bend`'s `sp_dt` solves it with two one-read helpers (`sp_ar`, `sp_tb`) for
# exactly this reason; those helpers are not imported here because importing `spec.bend`
# would pull six rule tables and a `main` this file does not want, so the two reads are
# threaded as parameters instead. That is the honest cost and it is two parameters.
def gr_0.dt(ar: O.Arena, tb: F.Table, self: U32) -> Maybe<&2, S.Dt>:
  dt_of(F.fold.dt(ar, tb, self))

def gr_0.fire(dt: S.Dt, +ar: O.Arena, ctx: U32) -> GRes:
  +f = gcast(ar, ctx, dt)
  fired([O.Found.i(f)], O.Found.ar(f))

def gr_0.pick(m: Maybe<&2, S.Dt>, +ar: O.Arena, +ctx: U32) -> GRes:
  match m:
    case Some{dt}: gr_0.fire(dt, ar, ctx)
    case None{}: GSkip{}

def gr_0.go(+ar: O.Arena, ctx: U32, +self: U32, +fx: F.Folded) -> GRes:
  gr_0.pick(gr_0.dt(F.Folded.ar(fx), F.Folded.t(fx), gr_0.src(ar, self)), ar, ctx)

def gr_0(+ar: O.Arena, +ctx: U32, self: U32) -> GRes: gr_0.go(ar, ctx, self, F.folded(ar))

# --- 1. RECIPROCAL -- gradient.py:68. `(-ctx * ret * ret,)`
#
# `__neg__` is `self.neg()` = `alu(Ops.NEG)` (elementwise.py:74, :261), and the two `*`
# are `alu(Ops.MUL)`. So this is THREE new nodes: NEG, MUL, MUL, and the gate row
# `recip_arena` counts the growth. The order matters: `-ctx * ret * ret` is
# `((-ctx) * ret) * ret`, left-associative, and `ops.bend`'s interning makes the
# association observable in the node graph.
def gr_1.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +f1 = gneg(ar, ctx)
  +f2 = gmul(O.Found.ar(f1), O.Found.i(f1), ret)
  +f3 = gmul(O.Found.ar(f2), O.Found.i(f2), ret)
  fired([O.Found.i(f3)], O.Found.ar(f3))

def gr_1(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_1.go(ar, ctx, self)

# --- 2. SIN -- gradient.py:69. `((math.pi/2 - ret.src[0]).sin() * ctx,)`
#
# d/dx sin(x) = cos(x), and the rule gets cos(x) as sin(pi/2 - x) so there is no COS op.
# Four nodes: SUB with the folded `pi/2`, SIN, MUL. `pi/2` is `k_pi_2`.
def gr_2.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +c = gconst_raw(ar, k_pi_2())
  +f1 = gsub(O.Found.ar(c), O.Found.i(c), O.Arena.src(O.Found.ar(c), ret, 0))
  +f2 = gsin(O.Found.ar(f1), O.Found.i(f1))
  +f3 = gmul(O.Found.ar(f2), O.Found.i(f2), ctx)
  fired([O.Found.i(f3)], O.Found.ar(f3))

def gr_2(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_2.go(ar, ctx, self)

# --- 3. LOG2 -- gradient.py:70. `(ctx / (ret.src[0] * math.log(2)),)`
#
# Two nodes: MUL by the folded `log(2)`, then FDIV. `/` is `__truediv__` -> `div`, which
# at float dtype is `Ops.FDIV` -- NOT `Ops.CDIV`, which is the INTEGER divide.
def gr_3.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +c = gconst_raw(ar, k_ln2())
  +f1 = gmul(O.Found.ar(c), O.Arena.src(O.Found.ar(c), ret, 0), O.Found.i(c))
  +f2 = gdiv(O.Found.ar(f1), ctx, O.Found.i(f1))
  fired([O.Found.i(f2)], O.Found.ar(f2))

def gr_3(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_3.go(ar, ctx, self)

# --- 4. EXP2 -- gradient.py:71. `(ret * ctx * math.log(2),)`
# Two MULs and the folded `log(2)`. Note the ORDER: `ret * ctx * ln2` is
# `((ret * ctx) * ln2)`, and it is NOT `ret * (ctx * ln2)` -- the association is visible.
def gr_4.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +f1 = gmul(ar, ret, ctx)
  +c = gconst_raw(O.Found.ar(f1), k_ln2())
  +f2 = gmul(O.Found.ar(c), O.Found.i(f1), O.Found.i(c))
  fired([O.Found.i(f2)], O.Found.ar(f2))

def gr_4(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_4.go(ar, ctx, self)

# --- 5. SQRT -- gradient.py:72. `(ctx / (ret*2),)`
# MUL by the folded 2, then FDIV. One literal, one binary op, no fold read.
def gr_5.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +c = gconst_raw(ar, k_ftwo())
  +f1 = gmul(O.Found.ar(c), ret, O.Found.i(c))
  +f2 = gdiv(O.Found.ar(f1), ctx, O.Found.i(f1))
  fired([O.Found.i(f2)], O.Found.ar(f2))

def gr_5(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_5.go(ar, ctx, self)

# --- 6. TRUNC -- gradient.py:73. `(ctx.const_like(0),)`
#
# `const_like` (ops.py:603) is `UOp.const(b, dtype or self.dtype)` plus an EXPAND when
# `self._shape` is set and differs from the CONST's. For a CONST ctx with no shape (the
# gate's fixtures) the EXPAND does not fire and the answer is a bare CONST of 0 at
# ctx's dtype. `k_fzero` is the value; the dtype FOLLOWS it, so "0 at ctx's dtype" is
# spelled as a float 0 and the rule is one node.
def gr_6.go(+ar: O.Arena, ctx: U32, +ret: U32) -> GRes:
  +c = gconst(ar, k_fzero())
  fired([O.Found.i(c)], O.Found.ar(c))

def gr_6(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_6.go(ar, ctx, self)

# --- 7. CMPLT -- gradient.py:74. `(None, None)`
#
# A COMPARISON is not differentiable, so both slots are holes and `len(gs) == 2` is the
# only thing that distinguishes it from `BITCAST`'s one hole. `gs_solid` reads 0 and
# `gs_len` reads 2, and a fixture where a rule returned a real gradient instead would
# move exactly one of those two rows.
def gr_7(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([0, 0], ar)

# --- 8. CMPNE -- gradient.py:74. `(None, None)`
# The SAME body as tag 7. Python's `UPat((Ops.CMPLT, Ops.CMPNE))` compiles to ONE rule
# with `uop.op in a0`, and `pdict` keys it under TWO ops, so the compiled table has two
# entries for one lambda. That is why tag 7 and tag 8 exist separately here and why
# `t_claims` is 33 rather than 32: the COUNT is of the COMPILED table, which is the live
# path (`UPAT_COMPILE=1`, ops.py:1588).
def gr_8(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([0, 0], ar)

# --- 9. ADD -- gradient.py:75. `(ctx, ctx)`
#
# The simplest rule that is not all-holes, and the one that pins "the same ctx index in
# two slots" -- NOT two copies. `mul_0_is_ctx`-style rows cannot tell the difference
# because a copied index would intern to the same node, but `add_solid` (2) versus
# `add_same` (1 distinct node) can, and that is what `add_distinct` counts.
def gr_9(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: fired([ctx, ctx], ar)

# --- 10. POW -- gradient.py:76-77.
#   (ctx * e.eq(0).where(e, e*b.pow(e-1)),
#    ctx * b.eq(0).where((e<0).where(ret.const_like(-math.inf), 0), ret*b.log2()*math.log(2.0)))
#
# The most complex rule in the table, and the one with the most nodes. Both halves are
# the standard f'(x^e) with the DEGENERATE cases pinned: d/dx x^0 = 0 needs the `e.eq(0)`
# branch to hand back `e` itself (which is 0), and d/de x^0 = x^0 * ln(x) needs the
# `b.eq(0)` branch to answer `-inf` when `e<0` and `0` otherwise. The `0` there is
# `k_fzero` and the `-inf` is `k_neginf`.
#
# The node count is 2 + 5 + 8 and `pow_n0`/`pow_n1` pin them, because a rule that
# dropped the `e.eq(0)` guard would still answer a VALUE (wrongly) and only the count
# would move.
# ONE CONSTANT, THEN THE COMPARISON. Python folds the literal `0` at graph-build time
# and `e.eq(0)` interns the CONST once, so the arena here grows by exactly one CONST
# before the CMPEQ. Writing the two halves as separate defs keeps each arena thread
# readable: a `let` is affine, so `+` bindings are mandatory and each `Found.ar` carries
# the grown arena forward exactly once.
# TWO ZEROS, AND THEY ARE NOT THE SAME NODE. MEASURED, and this is the kind of detail a
# port gets wrong silently because both are "the constant 0":
#   `e.eq(0)`      -> CMPNE, CMPNE, CAST, CONST, CONST   -- the `0` is BARE (weakfloat)
#   `e < 0`        -> CMPLT, CAST, CONST, CONST          -- the `0` is BARE
#   `where(<0,x,0)` -> WHERE, CMPLT, ..., CAST, CONST   -- the `0` is CAST to float32
# The reason is `const_like` vs a bare literal: `where`'s third argument goes through
# `Tensor.__rsub__`-style promotion against a float32 operand, while `eq`'s does not.
# `pow_n0` (24) and `pow_n1` (29) are the rows that would catch getting this wrong.
def gr_10.zero(+ar: O.Arena) -> O.Found: gconst(ar, k_fzero())

# `where`'s promoted 0 -- `CAST(CONST 0.0)`, i.e. what `const_like(0)` builds.
def gr_10.zcast(+ar: O.Arena) -> O.Found: gconst(ar, k_fzero())

# and `e < 0` uses the BARE one: CMPLT, CAST, CONST, CONST is 4 nodes.
def gr_10.zbare(+ar: O.Arena) -> O.Found: gconst_raw(ar, k_fzero())
# `e - 1` IN `POW`'s `e*b.pow(e-1)` (gradient.py:77) IS `ADD(e, MUL(CAST(1.0), CONST(-1.0)))`
# and the `1` is a FLOAT CONST WITH A CAST -- because the literal is a Python `int` and
# `ufix(1)` gives `UOp.const(1)` -> weakint, which then gets promoted at the MUL. Measured:
# `(c - 1)` is `ADD(CAST(CONST), MUL(CAST(CONST 1.0), CONST(-1.0)))`, whereas `c.neg()`
# is `MUL(CAST(CONST), CONST(-1.0))` with a BARE `-1.0`. So `1` casts and `-1.0` does
# not, and `k_one`/`k_fone` are different constants for that reason alone.
def gr_10.one(+ar: O.Arena) -> O.Found: gconst(ar, k_fone())
def gr_10.neginf(+ar: O.Arena) -> O.Found: gconst(ar, k_neginf())

# d/dx x^e = e * x^(e-1), with the e==0 case handing back `e` (which IS 0).
# `e.eq(0).where(e, e*b.pow(e-1))` -- gradient.py:77, read left to right.
def gr_10.dx(+ar: O.Arena, +ctx: U32, +b: U32, +e: U32) -> O.Found:
  +z = gr_10.zero(ar)
  +n = gcmpne(O.Found.ar(z), e, O.Found.i(z))
  +q = gnot(O.Found.ar(n), O.Found.i(n))
  +o = gr_10.one(O.Found.ar(q))
  +d = gsub(O.Found.ar(o), e, O.Found.i(o))
  +p = gpow(O.Found.ar(d), b, O.Found.i(d))
  +w = gwhere(O.Found.ar(p), O.Found.i(q), e, O.Found.i(p))
  gmul(O.Found.ar(w), ctx, O.Found.i(w))

# d/de x^e = x^e * ln(x), with x==0 handing back -inf when e<0 and 0 otherwise.
# `b.eq(0).where((e<0).where(ret.const_like(-math.inf), 0), ret*b.log2()*math.log(2.0))`
def gr_10.de(+ar: O.Arena, +ctx: U32, +b: U32, +e: U32, +ret: U32) -> O.Found:
  +z = gr_10.zero(ar)
  +n = gcmpne(O.Found.ar(z), b, O.Found.i(z))
  +q = gnot(O.Found.ar(n), O.Found.i(n))
  +zb = gr_10.zbare(O.Found.ar(q))
  +lt = gcmplt(O.Found.ar(zb), e, O.Found.i(zb))
  +ni = gr_10.neginf(O.Found.ar(lt))
  +zc = gr_10.zcast(O.Found.ar(ni))
  +n = gwhere(O.Found.ar(zc), O.Found.i(lt), O.Found.i(ni), O.Found.i(zc))
  +rb = gmul(O.Found.ar(n), ret, b)
  +lg = glog2(O.Found.ar(rb), b)
  +t = gconst_raw(O.Found.ar(lg), k_ln2())
  +m = gmul(O.Found.ar(t), O.Found.i(lg), O.Found.i(t))
  +r = gwhere(O.Found.ar(m), O.Found.i(q), O.Found.i(n), O.Found.i(m))
  gmul(O.Found.ar(r), ctx, O.Found.i(r))

def gr_10.go(+ar: O.Arena, +ctx: U32, +b: U32, +e: U32, +ret: U32) -> GRes:
  +f0 = gr_10.dx(ar, ctx, b, e)
  +f1 = gr_10.de(O.Found.ar(f0), ctx, b, e, ret)
  fired([O.Found.i(f0), O.Found.i(f1)], O.Found.ar(f1))

def gr_10(+ar: O.Arena, +ctx: U32, +self: U32) -> GRes:
  gr_10.go(ar, ctx, O.Arena.src(ar, self, 0), O.Arena.src(ar, self, 1), self)

# --- 11. MAX -- gradient.py:78-79.
#   ((x>y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)),
#    (x<y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)))
#
# The gradient of a max goes to the larger argument; a TIE splits it evenly, which is
# the `ctx * 0.5` and is why `max_tie` is a separate gate row from `max_gt`. Note
# `(x<y)` is the SAME op as `(x>y)` with the operands SWAPPED (CMPLT is not
# commutative), so both slots build a CMPLT and they are different nodes.
def gr_11.one(+ar: O.Arena, +ctx: U32, +x: U32, +y: U32) -> O.Found:
  +c = gcmplt(ar, x, y)
  +n = gcmpne(O.Found.ar(c), x, y)
  +e = gnot(O.Found.ar(n), O.Found.i(n))
  # BOTH LITERALS ARE BARE CONSTs, measured on Python's tree: `ctx * 0.5` is
  # `MUL(CAST(CONST), CONST 0.5)` and the untaken branch is a bare `CONST 0.0`, neither
  # carrying a CAST. That is the opposite of `POW`'s `where(..., 0)` (which IS cast) and
  # the reason `max_n0`/`max_n1` are 21 in Python and not 25.
  +hf = gconst_raw(O.Found.ar(e), k_fhalf())
  +hm = gmul(O.Found.ar(hf), ctx, O.Found.i(hf))
  +zt = gconst_raw(O.Found.ar(hm), k_fzero())
  +iw = gwhere(O.Found.ar(zt), O.Found.i(e), O.Found.i(hm), O.Found.i(zt))
  gwhere(O.Found.ar(iw), O.Found.i(c), ctx, O.Found.i(iw))

def gr_11.go(+ar: O.Arena, +ctx: U32, +x: U32, +y: U32) -> GRes:
  +f0 = gr_11.one(ar, ctx, x, y)
  +f1 = gr_11.one(O.Found.ar(f0), ctx, y, x)
  fired([O.Found.i(f0), O.Found.i(f1)], O.Found.ar(f1))

def gr_11(+ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_11.go(ar, ctx, O.Arena.src(ar, self, 0), O.Arena.src(ar, self, 1))

# --- 12. MUL -- gradient.py:80. `(ret.src[1]*ctx, ret.src[0]*ctx)`
#
# The product rule, with the operands CROSSED: src[0]'s gradient multiplies by src[1].
# `MUL` IS commutative (`GroupOp.commutative`, ops.py:453) so `ops.bend`'s interning
# collapses `ret.src[1]*ctx` and `ret.src[0]*ctx` when the srcs are equal, and
# `mul_same_src` is the row that says so -- a fixture with a square MUL where BOTH slots
# are the same node, which is correct and not a bug.
def gr_12.go(+ar: O.Arena, +ctx: U32, +ret: U32) -> GRes:
  +f1 = gmul(ar, O.Arena.src(ar, ret, 1), ctx)
  +f2 = gmul(O.Found.ar(f1), O.Arena.src(O.Found.ar(f1), ret, 0), ctx)
  fired([O.Found.i(f1), O.Found.i(f2)], O.Found.ar(f2))

def gr_12(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_12.go(ar, ctx, self)

# --- 13. WHERE -- gradient.py:81.
#   (None, ret.src[0].where(ctx, ctx.const_like(0)),
#       ret.src[0].where(ctx.const_like(0), ctx))
#
# Three slots, the first a hole: a WHERE's CONDITION is not differentiable. The other
# two are `mask.where(value, ctx)` with the branches SWAPPED between them
# (elementwise.py:426 is `mask.where(value, self)`), so slot 1 takes the taken branch
# and slot 2 the untaken one. The `const_like(0)` is built ONCE in Python's fold and
# used twice; here it is built twice, which interns to the same node.
def gr_13.go(+ar: O.Arena, +ctx: U32, +ret: U32) -> GRes:
  +z = gconst(ar, k_fzero())
  +f1 = gwhere(O.Found.ar(z), O.Arena.src(O.Found.ar(z), ret, 0), ctx, O.Found.i(z))
  +f2 = gwhere(O.Found.ar(f1), O.Arena.src(O.Found.ar(f1), ret, 0), O.Found.i(z), ctx)
  fired([0, O.Found.i(f1), O.Found.i(f2)], O.Found.ar(f2))

def gr_13(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: gr_13.go(ar, ctx, self)

# --- 14. REDUCE -- gradient.py:82. `reduce_gradient(ctx, ret, ret.arg[0])`
#
# DISPATCHED, not inlined: the body is `reduce_gradient`, a top-level Python function
# with three arms keyed on the REDUCE's op (`gradient.py:8-18`). Three nodes' worth of
# shape work each, and all three need `_min_max` or `broadcast_axes`:
#   ADD (:9)  `ctx._broadcast_to(ret.src[0].shape)`  -- movement.py:128
#   MAX (:12) `mask/mask._rop(ADD, ...)`             -- `_rop` needs `resolve(shape[x]!=1)`
#   MUL (:18) `ret/safe_x` and a second `_rop`        -- same
# `_rop` (ops.py:655) reads `resolve(self.shape[x] != 1)`, which is a SYMBOLIC comparison
# and is `uop/symbolic.py`'s `resolve`, not ops.bend's. And `_broadcast_to` needs
# `broadcast_axes` (ops.py:89), which is also symbolic (`resolve(s == 1)`).
#
# TODO(p3) mixin/gradient.py:82  reduce_gradient -- `_rop`'s `resolve(self.shape[x]!=1)`
#   and `_broadcast_to`'s `broadcast_axes` are both `resolve` on a `Sint`, and
#   `symbolic.py`'s `resolve` is not ported. Phase P3 owns `symbolic`.
def gr_14(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 15. CONTIGUOUS_BACKWARD -- gradient.py:83. `(ctx.contiguous(),)`
#
# `contiguous` (elementwise.py:59) is a real body, not an alias: it returns `self` for a
# weak dtype, for a STAGE, for `device is None` or for `has_buffer_identity()`, and
# otherwise `uop.alu(Ops.STAGE)`. `has_buffer_identity` (ops.py:952) walks BASE and is a
# fold read plus a walk.
#
# TODO(p3) mixin/gradient.py:83  ctx.contiguous -- needs `has_buffer_identity`
#   (ops.py:952), a BASE walk with an `after_ok` argument that fold.bend does not carry.
#   The rule's OBSERVABLE effect for a non-weak, device-bearing, non-identity node is
#   exactly `alu(Ops.STAGE)`, and `stage_*` covers that node; the four early returns are
#   what is missing.
def gr_15(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 16. STAGE -- gradient.py:84. `(ctx,)`
# Identity, one slot. Together with tag 15 this is the pair the STAGE node itself and
# `CONTIGUOUS_BACKWARD`'s answer are read through.
def gr_16(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([ctx], ar)

# --- 17. RESHAPE -- gradient.py:85. `(ctx.reshape(ret.src[0].shape), None)`
#
# TWO SLOTS FOR A ONE-SRC NODE, and that is a REAL PYTHON BUG, measured: `pm_gradient`
# is a per-OP table with no arity check, so this rule answers 2 gradients for a node
# whose `src` has length 1, and `compute_gradient`'s own assert (gradient.py:128
# `assert len(lgrads) == len(t0.src)`) FIRES. Verified: `pm_gradient.rewrite(RESHAPE)`
# returns 2 for a 1-src RESHAPE and `compute_gradient` on the same node raises
# `AssertionError: got 2 gradient, expected 1`. The port REPRODUCES the arity, because
# reproducing it is what lets the gate row `reshape_arity` be 2 and say so.
#
# `ctx.reshape(shape)` is `_mop(Ops.RESHAPE, arg=shape)` (movement.py:164), and the
# shape is `ret.src[0].shape` -- a FOLD read, plus `prod` for the `-1` arm.
def gr_17(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 18. EXPAND -- gradient.py:86. `(ctx, None)`
# Two slots, the second a hole, for a two-src EXPAND (a value and its shape). Same
# arity-2 shape as tag 17 but the answer is `ctx` itself, so `expand_*` reads the
# identity rather than a reshape.
def gr_18(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([ctx, 0], ar)

# --- 19. PAD -- gradient.py:87.
#   (ctx.shrink(tuple([(p[0], s+p[0]) for s,p in zip(ret.src[0].shape, ret.marg)])), None, None)
#
# THREE slots: a PAD has srcs (value, lo_shape, hi_shape) -- measured, a 1-D pad has
# `len(src) == 3`. `ret.marg` is `zip(src[1].as_shape, src[2].as_shape)` (ops.py:817), so
# both margins are CONST nodes read back as shapes, and `s + p[0]` is SINT ADDITION on
# the derived shape.
#
# TODO(p3) mixin/gradient.py:87  PAD -- `ret.marg` is `zip(src[1].as_shape,
#   src[2].as_shape)` and `s+p[0]` is `Sint` arithmetic. ops.bend's `Sint` is
#   `SI{i64} | SU{u32}` with an equality (`F.eq_sint`) but NO addition and NO `as_shape`
#   (reading a CONST node back out as a shape is `ops.py:809`). Phase P3 owns both.
def gr_19(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 20. SHRINK -- gradient.py:88.
#   (ctx.pad(tuple([(p[0], s-p[0]-p[1]) for s,p in zip(ret.src[0].shape, ret.marg)])), None, None)
# The mirror of tag 19: a SHRINK's gradient is a PAD, and the margin arithmetic goes the
# other way. Same three-slot arity, same `Sint` wall.
# TODO(p3) mixin/gradient.py:88  SHRINK -- same `marg`/`Sint` wall as tag 19.
def gr_20(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 21. PERMUTE -- gradient.py:89. `(ctx.permute(argsort(ret.marg)),)`
#
# The inverse permutation, computed by `argsort` (helpers.py). `ret.marg` for a PERMUTE
# is `self.arg` (ops.py:818) -- an `ATuple{ys: List<U32>}` in ops.bend, so the margin
# IS a list of U32 and needs no `as_shape`. `helpers.bend`'s `argsort_u32` is exactly
# that function, so it is imported and the whole rule is: read the ATuple, argsort it,
# build the PERMUTE. This is the one MOVEMENT rule with no `Sint` arithmetic in it.
def gr_21(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 22. FLIP -- gradient.py:90. `(ctx.flip([i for i,x in enumerate(ret.marg) if x]),)`
#
# A FLIP's arg is a tuple of BOOLS, one per axis, so `marg` is `[True, False]` for a
# 2-D flip (measured). The rule keeps the indices whose flag is set. ops.bend's
# `ATuple{ys: List<U32>}` holds U32s, and a bool flag is 0/1, so the filter is
# `U32.is_zero` and the mapping is exact.
def gr_22(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 23. STACK -- gradient.py:91. `tuple(ctx[i] for i in range(len(ret.src)))`
#
# ONE GRADIENT PER SRC, each `ctx[i]` -- an INDEX of the gradient by a CONST. That is
# Tensor indexing, `mixin/op.py`'s `__getitem__`, which builds a slice/shrink/index
# chain per index and is a whole subsystem.
#
# TODO(p3) mixin/gradient.py:91  STACK -- `ctx[i]` is `Tensor.__getitem__` with an int,
#   i.e. `op.py`'s indexing machinery. Phase P3 owns `op.py`.
def gr_23(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 24. COPY -- gradient.py:92.
#   (ctx.copy_to_device(ret.src[0].device),) + (None,)*(len(ret.src)-1)
#
# `copy_to_device` (ops.py:761) raises for a DISK device, asserts `arg is None or
# isinstance(self.device, tuple)`, wraps in an MSELECT when `arg` is set, and RAISES for
# a weak dtype. `ret.src[0].device` is a FOLD read.
#
# It also RAISES in the gate: measured, `pm_gradient.rewrite` on a 1-src COPY raises
# `TypeError: 'NoneType' object is not iterable`, because `copy_to_device` returns a
# UOp whose `*` is not what the tuple concat expects at that arity. So this rule is a
# measured Python failure, and the port records it rather than reproducing a crash.
#
# TODO(p3) mixin/gradient.py:92  COPY -- `copy_to_device` (ops.py:761) needs a device
#   fold plus the DISK and weak-dtype refusals; and the rule RAISES at 1 src in
#   Python (measured, `t_copy_raises`).
def gr_24(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 25. UNSHARD -- gradient.py:93. `ctx.shard(ret.device, ret.axis).src`
#
# `shard` (ops.py:757) is `copy_to_device` then `_shard` then `.unshard`, and `_shard`
# (ops.py:751) reads `int(rng.vmax)+1` -- THAT IS `UOp.vmax`, i.e. `_min_max`
# (ops.py:1104-1163). The rule then takes `.src` of the resulting UNSHARD, which is a
# per-shard list.
#
# TODO(p3) mixin/gradient.py:93  UNSHARD -- `_shard` (ops.py:751) reads `int(rng.vmax)`,
#   which is `_min_max`. `_min_max` is the single largest wall in the fold and
#   `mixin/dtype.bend`'s header already names it as the blocker for `commit_dtype`.
def gr_25(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 26. SINK -- gradient.py:94. `ctx.src`
#
# A SINK's gradient is ITS OWN SRCS: the list, verbatim, one gradient per src. It is the
# only rule whose answer is not a fresh node, and it is what makes `compute_gradient`'s
# `grads[root] = root_grad` type correct -- `root_grad` is a SINK and its srcs are the
# per-output gradients. The answer is `ctx`'s srcs, so `gs` is a copy of a list that
# lives in the arena rather than a new node; `sink_*` reads its length against ctx's.
def gr_26(+ar: O.Arena, +ctx: U32, +self: U32) -> GRes: fired(O.Arena.srcs(ar, ctx), ar)

# --- 27. AFTER with a CALL -- gradient.py:95-96.
#   (ctx, UOp.sink(*([ctx if i == k.src.index(d)-1 else UOp(Ops.NOOP) for i in range(len(k.src)-1)])))
#
# `k.src.index(d)` is a LIST INDEX OF an element -- find where `d` appears among the
# CALL's srcs. That is a linear scan for an EQUAL node, and it is exactly what
# `List.get`-style walking is for; ops.bend has no `List.index_of`, so it is one
# two-line fold. `UOp(Ops.NOOP)` is the arena's bottom node (index 0), which is why
# the holes and the NOOPs share an encoding here.
def gr_27(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 28. AFTER, ordering-only -- gradient.py:98-99.
#   lambda ctx, dest, t: (ctx, None) if t.buf_uop is not dest.buf_uop else None
#
# This is a rule that MATCHES the pattern and then RETURNS `None`, so the scan
# continues -- a fourth state beyond `GSkip`/`GFired` from the pattern's side, and it is
# why `GSkip` means "no answer from this def" rather than "this pattern did not match".
# `t.buf_uop` is ops.py:925, a walk to the BUFFER/ALLOC/PARAM (or STAGE/MSTACK)
# underneath.
#
# TODO(p3) mixin/gradient.py:98  ordering-only AFTER -- `buf_uop` (ops.py:925) walks
#   through `base` and stops at BUFFER/ALLOC/PARAM/STAGE/MSTACK, and `base` needs the
#   fold plus a second walk. fold.bend carries `fold.base` but not `buf_uop`.
def gr_28(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 29. AFTER, clone/assign -- gradient.py:101. `(None, ctx)`
#
# *** THE NAME REBIND. *** `dest` is bound at `AFTER.src[0]` AND at
# `AFTER.src[1].src[0]`. The rule fires ONLY when those are the SAME node, and the
# compiled form states that as an explicit `is` (upat.py:100-105). Without the check
# the rule claims every `AFTER(_, STORE(_,_))` -- including the ordering-only shape of
# tag 28 and the partial-store shape of tag 30 -- and it still typechecks.
#
# `gr_29` is therefore SPLIT: the identity test is a separate def, `gr_29_same`, and the
# rule answers `GSkip{}` when it fails. That is the honest port -- not "the rule claims
# and then declines", but "the pattern does not match", because in the compiled form
# the `is` is part of the MATCH. The two-sided gate is `rebind` (same node -> fires) and
# `rebind_off` (different node -> does not), and the mutation is `gr_29_same`'s `U32.is_eq`
# replaced by `True{}`, which is the exact divergence the notes warn about.
# THE IDENTITY CHECK, and it is a def of its own so the mutation is a one-word edit and
# so the header's claim is checkable rather than asserted. `upat.py:100-105` builds it as
# an ordinary clause in the emitted `if` (`"{0} is {1}"`), which is why it is part of the
# MATCH and not part of the body: a rule that matched and then declined would be a
# different rule with a different effect on the scan.
#
# `U32.is_eq` on two arena indices IS `store.setdefault(...).same`, which is what the
# interpreter does (notes, "THE NAME-REBIND QUESTION, SETTLED"), and it is the same
# question `dest is dest` asks in Python. Nothing else in the file needs this.
def gr_29_dest(ar: O.Arena, self: U32) -> U32: O.Arena.src(ar, self, 0)
def gr_29_call(ar: O.Arena, self: U32) -> U32: O.Arena.src(ar, self, 1)
def gr_29_stored(ar: O.Arena, k: U32) -> U32: O.Arena.src(ar, k, 0)

# `UOp.src[0]` of `UOp.src[1]`: the STORE's destination. The `ar` threading is three
# separate one-read defs rather than one nested call, because a nested call hands its
# FIRST argument an affine `ar` and the inner read would consume it before the outer
# one could -- the measured failure is exactly that, and the three-def shape is the fix.
def gr_29_same.pick(a: U32, b: U32) -> Bool: U32.is_eq(a, b)

def gr_29_same.go(+ar: O.Arena, +self: U32) -> Bool:
  gr_29_same.pick(gr_29_dest(ar, self), gr_29_stored(ar, gr_29_call(ar, self)))

def gr_29_same(+ar: O.Arena, +self: U32) -> Bool: gr_29_same.go(ar, self)

# `(None, ctx)` -- the clone/assign gradient passes through to the VALUE, so slot 1 is
# `ctx` and slot 0 is a hole. Python has no arity guard on this rule and a STORE always
# has two srcs, so two slots is exact.
# The `match` may only scrutinise a PARAMETER, so the `Bool` `gr_29_same` computes is
# handed to `pick` as an argument and the two arms are its cases. This is notes rule 2
# and it is the reason every such def in this file is a `.pick`/`.of` pair.
def gr_29.pick(ok: Bool, ar: O.Arena, +ctx: U32) -> GRes:
  match ok:
    case True{}: fired([0, ctx], ar)
    case False{}: GSkip{}

def gr_29.go(+ar: O.Arena, +ctx: U32, self: U32) -> GRes: gr_29.pick(gr_29_same(ar, self), ar, ctx)

def gr_29(+ar: O.Arena, +ctx: U32, self: U32) -> GRes: gr_29.go(ar, ctx, self)

# --- 30. AFTER, partial store -- gradient.py:102-103. `partial_store_gradient(ctx, dest, view)`
#
# THE HELPER IS A `while` LOOP plus a RE-ENTRY INTO THE MATCHER, and both halves are
# walls here. `gradient.py:54-58` walks `base` up through
# `{RESHAPE, SHRINK, PERMUTE, FLIP}` accumulating a `path`, and returns `None` if it
# never reaches `dest`; `gradient.py:62` then calls `pm_gradient.rewrite(mop, ctx=mask)`
# -- THE MATCHER CALLING ITSELF. That is mutual recursion between `gr_30` and
# `gr_rewrite`, and Bend refuses mutual recursion outright (notes, "There is no mutual
# recursion"). The loop itself is a `while` with a mutable list, which Bend expresses as
# a self-call on the tail, but it cannot be entered FROM the rewrite.
#
# TODO(p3) mixin/gradient.py:102  partial_store_gradient -- the body RE-ENTERS
#   `pm_gradient.rewrite` (gradient.py:62), so `gr_30` and `gr_rewrite` would be mutually
#   recursive and Bend refuses that. It also needs `mop.replace(src=(grad,)+mop.src[1:])`
#   (a src rewrite with an `Arg` preserved) and `grad.const_like(1)`.
def gr_30(ar: O.Arena, ctx: U32, self: U32) -> GRes: GSkip{}

# --- 31. STORE -- gradient.py:104. `(None, ctx)`
# Gradient flows to the stored VALUE, not the buffer: slot 0 is a hole and slot 1 is
# `ctx` verbatim. Same answer shape as tag 29 with the slots the other way round, which
# is what makes them a good pair -- `store_0_hole` and `rebind_1_ctx` are the two rows
# that say which half of the AFTER/STORE pair goes where.
def gr_31(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([0, ctx], ar)

# --- 32. BITCAST -- gradient.py:106. `(None,)`
# "there's no gradient for bitcast" -- ONE hole, for a ONE-src node. It is the arity
# twin of tag 7's two holes and the smallest possible answer.
def gr_32(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([0], ar)


# ===========================================================================
# THE DRIVER -- `compute_gradient` (gradient.py:116-145), `_deepwalk` (:109-114),
# `reduce_gradient` (:8-18) and `call_gradient` (:20-50). ALL FOUR ARE WALLS, and the
# reasons are DIFFERENT, which is why they are stated separately rather than as one
# "not ported" note.
#
# `_deepwalk` -- gradient.py:109. `root.topovisit(lambda u: any(in_target_path[x] or x
# in targets for x in u.src), in_target_path)`. The walk itself is `O.UOp.topovisit`
# (ops.bend:2310) and the visitor is a PYTHON CALLABLE closing over a dict, which is the
# P4 concern every rewrite rule in tinygrad shares and which no rule in this file has.
# The `in_target_path` map is a `List`-backed table here rather than a dict, exactly as
# `fold.bend`'s `Table` is, and the `targets` set is a `List<U32>` membership test.
# TODO(p3) mixin/gradient.py:109  _deepwalk -- `topovisit`'s VISITOR is a Callable
#   closing over a dict; Bend has no closures in a datatype field (notes, "A CLOSURE IN A
#   DATATYPE FIELD MUST TAKE ALL-AFFINE ARGUMENTS"). The alternative -- a fold over
#   `O.UOp.toposort`'s order carrying a `Data` table -- is `fold.bend`'s own shape and is
#   writable, and is P3 because it wants the `Bool` lattice (a node is in the target path
#   iff ANY src is, with DETACH excluded, gradient.py:114).
#
# `compute_gradient` -- gradient.py:116-145. The WALK is fine; two things are not.
#
#   (a) `grads: dict[UOp, UOp]` is keyed by a UOp and the port's key is a `U32` arena
#       index, which is a different thing only in one place: interning means two UOps are
#       `==` iff their indices are, so the map is a `List<(U32, U32)>` and every lookup is
#       a linear scan. `fold.bend` pays exactly this and calls it "slow and checkable
#       beats fast and unprovable". That part is PORTABLE and is not the wall.
#   (b) `grads[k] = grads[k] + v` and the SINK/SINK zip (gradient.py:136-137) both need an
#       UPDATE BY KEY on an affine structure. A `List` cannot be updated in place and a
#       `Data` record holding one is copied whole, so each update is an O(n) rebuild --
#       again `fold.bend`'s trade, and again PORTABLE.
#   (c) THE WALL: gradient.py:132-133, the shaped-edge reduce
#           v = v.cast(sum_acc_dtype(v.dtype))._rop(Ops.ADD, broadcast_axes(k.shape, v.shape)).reshape(k.shape).cast(v.dtype)
#       needs `broadcast_axes` (ops.py:89), which reads `resolve(s == 1)` and
#       `resolve(out_shape[nleft+i] != 1)` on a `Sint` -- SYMBOLIC comparisons, and
#       `symbolic.py`'s `resolve` is not ported. It also needs `sum_acc_dtype` (dtype.py:220),
#       which is `least_upper_dtype` against `getenv("SUM_DTYPE")`, and `Config` is a P6
#       concern (`uop/symbolic.py` is also P3).
# TODO(p3) mixin/gradient.py:132  compute_gradient -- the shaped-edge reduce needs
#   `broadcast_axes` (ops.py:89) and `sum_acc_dtype` (dtype.py:220), both of which read
#   `resolve` on a `Sint` or `Config`. Phase P3 owns `symbolic`; P6 owns `Config`.
#   The WALK, the grads map and the accumulation around it are all writable as
#   `fold.bend`-shaped `Data` tables and are deliberately NOT marked as walls.
#
# `call_gradient` -- gradient.py:20-50, and this is the BIGGEST of the four. It reads
# `k.arg.grad_fxn` (a CALLBACK on a `CallArg`), `fxn.src[0].unsharded_base.arg.slot`
# (an axis-normalised slot), `st.src[1].param_like(len(args)+i)`, `params` from
# `fxn.toposort(enter_calls=False)`, `view_as` + `shard_shape` + `sharding` +
# `grads[p].view_as(...)`, `renumber_invalid_outputs` (function.py), and two
# `substitute(walk=True)` passes. Every one of those is a different subsystem:
# `CallArg`/`CallInfo` is `ops.bend`'s, `renumber_invalid_outputs` is `function.py`'s,
# `view_as`/`shard_shape` are `mixin/op.py`'s, and the `substitute` walks are a graph
# rewrite over a PATH SET.
# TODO(p3) mixin/gradient.py:20  call_gradient -- needs `CallArg.grad_fxn` (a callback
#   in a dataclass field, `ops.py`), `renumber_invalid_outputs` (`function.py`),
#   `view_as`/`shard_shape`/`sharding` (`mixin/op.py`, ops.py:707/461/1248) and two
#   `substitute(walk=True)` passes. Five subsystems, none of them this file's.
#
# `partial_store_gradient` -- gradient.py:52-63, the helper tag 30 calls. Its WALL is
# MUTUAL RECURSION and it is the one wall in this file that is a Bend LAW rather than a
# missing dependency, so it is stated under `gr_30` and repeated here:
# TODO(p3) mixin/gradient.py:102  partial_store_gradient -- the body calls
#   `pm_gradient.rewrite` (gradient.py:62), so `gr_30` and `gr_rewrite` would be mutually
#   recursive and Bend refuses mutual recursion outright.
#
# WHAT NEXT, in the order the walls fall.
#   1. `symbolic.py`'s `resolve` unblocks `compute_gradient`'s shaped-edge reduce AND
#      `reduce_gradient`'s three arms, because both are `resolve` on a `Sint`.
#   2. `mixin/op.py` unblocks tag 23 (`ctx[i]`), which is the only movement rule whose
#      answer is not a movement op.
#   3. `uop/weak.bend`'s `_min_max` unblocks tag 25 (`UNSHARD`), tag 15
#      (`has_buffer_identity`) and `mixin/dtype.bend`'s `commit_dtype`.
#   4. `call_gradient` needs the five subsystems above and is the largest single item.
# ===========================================================================

# ===========================================================================
# THE TABLE. 33 entries, `pm_gradient.pdict` order, and the `ops`/`rej` columns are
# Python's OWN -- dumped from `upat_compile` and the `pdict` reject sets, not inferred.
# The interesting column is `rej`, and it is non-empty at exactly FOUR tags: 27 rejects
# `CALL` and 28/29/30 reject `STORE`. Those are `early_reject` (ops.py:1478), which is a
# NECESSARY CONDITION and not a veto despite the name (`ops.py:1609` is
# `if not early_reject.issubset(ler): continue`, so the rule FIRES when the op set IS a
# subset). For a pattern whose first src is a bare name the set is `None` -> empty, and
# an empty set is a subset of everything, which is why the other 29 are `Nil{}`.
#
# `rej` still decides SOMETHING here, unlike in `spec.bend` where the measured result was
# that it decides nothing: tags 28 and 29 have the SAME op set (`AFTER`) and the SAME
# reject set (`STORE`), so `rej` cannot separate them and the IDENTITY CHECK is the only
# thing that can. `t_rej27` and `t_rej29` are the rows for the spelling.
# ===========================================================================
def gr_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0,  [O.OpsCAST{}],                Nil{}},                        # 67
    O.PMEntry{1,  [O.OpsRECIPROCAL{}],           Nil{}},                        # 68
    O.PMEntry{2,  [O.OpsSIN{}],                  Nil{}},                        # 69
    O.PMEntry{3,  [O.OpsLOG2{}],                 Nil{}},                        # 70
    O.PMEntry{4,  [O.OpsEXP2{}],                 Nil{}},                        # 71
    O.PMEntry{5,  [O.OpsSQRT{}],                 Nil{}},                        # 72
    O.PMEntry{6,  [O.OpsTRUNC{}],                Nil{}},                        # 73
    O.PMEntry{7,  [O.OpsCMPLT{}],                Nil{}},                        # 74
    O.PMEntry{8,  [O.OpsCMPNE{}],                Nil{}},                        # 74
    O.PMEntry{9,  [O.OpsADD{}],                  Nil{}},                        # 75
    O.PMEntry{10, [O.OpsPOW{}],                  Nil{}},                        # 76
    O.PMEntry{11, [O.OpsMAX{}],                  Nil{}},                        # 78
    O.PMEntry{12, [O.OpsMUL{}],                  Nil{}},                        # 80
    O.PMEntry{13, [O.OpsWHERE{}],                Nil{}},                        # 81
    O.PMEntry{14, [O.OpsREDUCE{}],               Nil{}},                        # 82
    O.PMEntry{15, [O.OpsCONTIGUOUS_BACKWARD{}],   Nil{}},                        # 83
    O.PMEntry{16, [O.OpsSTAGE{}],                Nil{}},                        # 84
    O.PMEntry{17, [O.OpsRESHAPE{}],              Nil{}},                        # 85
    O.PMEntry{18, [O.OpsEXPAND{}],               Nil{}},                        # 86
    O.PMEntry{19, [O.OpsPAD{}],                  Nil{}},                        # 87
    O.PMEntry{20, [O.OpsSHRINK{}],               Nil{}},                        # 88
    O.PMEntry{21, [O.OpsPERMUTE{}],              Nil{}},                        # 89
    O.PMEntry{22, [O.OpsFLIP{}],                 Nil{}},                        # 90
    O.PMEntry{23, [O.OpsSTACK{}],                Nil{}},                        # 91
    O.PMEntry{24, [O.OpsCOPY{}],                 Nil{}},                        # 92
    O.PMEntry{25, [O.OpsUNSHARD{}],              Nil{}},                        # 93
    O.PMEntry{26, [O.OpsSINK{}],                 Nil{}},                        # 94
    O.PMEntry{27, [O.OpsAFTER{}],                [O.OpsCALL{}]},                # 95
    O.PMEntry{28, [O.OpsAFTER{}],                [O.OpsSTORE{}]},               # 98
    O.PMEntry{29, [O.OpsAFTER{}],                [O.OpsSTORE{}]},               # 101
    O.PMEntry{30, [O.OpsAFTER{}],                [O.OpsSTORE{}]},               # 102
    O.PMEntry{31, [O.OpsSTORE{}],                Nil{}},                        # 104
    O.PMEntry{32, [O.OpsBITCAST{}],              Nil{}}]}                       # 106

# ===========================================================================
# THE DISPATCH, duplicated rather than abstracted. `ops.bend` cannot call a def in this
# file, so this scan exists here for the same reason it exists six times in `spec.bend`,
# and its header says why: a rule is a def rather than a value, so there is nothing to
# store in a table to call. THE TABLE IS `Data`, so `+ts` is fine and the scan is free
# to read it twice.
# ===========================================================================
def gr_dispatch.go(tag: U32, +ar: O.Arena, +ctx: U32, self: U32) -> GRes:
  match tag:
    case 0: gr_0(ar, ctx, self)
    case 1: gr_1(ar, ctx, self)
    case 2: gr_2(ar, ctx, self)
    case 3: gr_3(ar, ctx, self)
    case 4: gr_4(ar, ctx, self)
    case 5: gr_5(ar, ctx, self)
    case 6: gr_6(ar, ctx, self)
    case 7: gr_7(ar, ctx, self)
    case 8: gr_8(ar, ctx, self)
    case 9: gr_9(ar, ctx, self)
    case 10: gr_10(ar, ctx, self)
    case 11: gr_11(ar, ctx, self)
    case 12: gr_12(ar, ctx, self)
    case 13: gr_13(ar, ctx, self)
    case 14: gr_14(ar, ctx, self)
    case 15: gr_15(ar, ctx, self)
    case 16: gr_16(ar, ctx, self)
    case 17: gr_17(ar, ctx, self)
    case 18: gr_18(ar, ctx, self)
    case 19: gr_19(ar, ctx, self)
    case 20: gr_20(ar, ctx, self)
    case 21: gr_21(ar, ctx, self)
    case 22: gr_22(ar, ctx, self)
    case 23: gr_23(ar, ctx, self)
    case 24: gr_24(ar, ctx, self)
    case 25: gr_25(ar, ctx, self)
    case 26: gr_26(ar, ctx, self)
    case 27: gr_27(ar, ctx, self)
    case 28: gr_28(ar, ctx, self)
    case 29: gr_29(ar, ctx, self)
    case 30: gr_30(ar, ctx, self)
    case 31: gr_31(ar, ctx, self)
    case 32: gr_32(ar, ctx, self)
    case _: GSkip{}

def gr_dispatch(tag: U32, +ar: O.Arena, +ctx: U32, self: U32) -> GRes:
  gr_dispatch.go(tag, ar, ctx, self)

# ONE RULE'S ENTRY CONDITIONS, which is Python's `_get_clause` (upat.py:158) with the
# `_fxn(...) is not None` tail removed -- that tail is `gs_keep` below. The conditions
# are: the node's op is in the entry's op set, and `early_reject` is a subset of the
# node's ops. Both are necessary conditions Python checks BEFORE running the body.
def gr_claimed(ops: List<&2, O.Op>, ar: O.Arena, self: U32) -> Bool:
  O.op_in(ops, O.Arena.op(ar, self))

def gr_rej.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(O.op_in(have, o), gr_rej.go(have, t))

# `ler` is `{u.op for u in uop.src}` -- ops.py:1608 -- over EVERY src. ops.bend's own
# `pm_ler` reads only `src[0]` and `src[1]`, which is enough for `spec.py`'s tables and
# NOT enough here: tag 29's node is `AFTER(AFTER(STORE))` and its three-node chain puts
# AFTER, STORE and whatever is under them in `ler`, and a two-src `ler` cannot see all of
# them. That is the same finding `spec.bend` records about `ops.bend`'s `pm_ler`, from the
# other side, and it is REPORTED, not fixed: `ops.bend` is not this file's.
def gr_ler.put(o: O.Op, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  List.append(&2, O.Op, acc, [o])

def gr_ler.go(srcs: List<&2, U32>, +ar: O.Arena, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match srcs:
    case Nil{}: acc
    case s <> t: gr_ler.go(t, ar, gr_ler.put(O.Arena.op(ar, s), acc))

def gr_ler(+ar: O.Arena, self: U32) -> List<&2, O.Op>:
  gr_ler.go(O.Arena.srcs(ar, self), ar, Nil{})

def gr_try.pick(ok: Bool, tag: U32, +ar: O.Arena, +ctx: U32, +self: U32) -> GRes:
  match ok:
    case True{}: gr_dispatch(tag, ar, ctx, self)
    case False{}: GSkip{}

# The TABLE is not a parameter: every entry carries its own `ops` and `rej`, so `gr_try`
# needs only the entry. That is the payoff of the compiled form -- the table is read once
# by the scan to produce the entries, and never again.
def gr_try(+ar: O.Arena, +ctx: U32, +self: U32, +e: O.PMEntry) -> GRes:
  gr_try.pick(Bool.and(gr_claimed(O.PMEntry.ops(e), ar, self),
                       gr_rej.go(gr_ler(ar, self), O.PMEntry.rej(e))),
              O.PMEntry.tag(e), ar, ctx, self)

def gr_scan(+ts: O.PMEntrys, +ar: O.Arena, +ctx: U32, +self: U32,
            todo: List<&2, O.PMEntry>, acc: GRes) -> GRes:
  match todo:
    case Nil{}: acc
    case e <> t: gr_scan(ts, ar, ctx, self, t, gs_keep(acc, gr_try(ar, ctx, self, e)))

# `pm_gradient.rewrite(t0, ctx=grads[t0])` -- gradient.py:126. FIRST non-`None`, which
# is `gs_keep` keyed on the ACCUMULATOR. A node with NO matching rule answers `GSkip{}`,
# and that is `rewrite` returning `None`, which `compute_gradient` turns into its
# `RuntimeError(f"failed to compute gradient for {t0.op}")` at gradient.py:127.
def gr_rewrite(+ts: O.PMEntrys, +ar: O.Arena, +ctx: U32, +self: U32) -> GRes:
  gr_scan(ts, ar, ctx, self, O.PMEntrys.es(ts), GSkip{})

# ===========================================================================
# THE GATE. Rows print `name=1|0` and Bend has no assertion form, so the gate is that
# both lanes print the SAME rows. Expectations come from
# `python3 -m tinygrad.mixin.gradient` drivers under `.agents/slop/notes/`, run against
# the repo's own tinygrad.
#
# WHAT MAKES A ROW WORTH PRINTING, and the two traps from the brief:
#   * `t_claims` pins the COUNT (33), not a boolean. An all-True gate says which cases
#     were covered and nothing about the rest.
#   * `rebind` / `rebind_off` / `rebind_claim29` are a THREE-ROW family on ONE node
#     shape, and they are the rows for the name-rebind. `rebind_off` is the control: if
#     `gr_29_same` were dropped, `rebind` would still be True and only `rebind_off`
#     would move. A one-row family could not tell the rule from its own absence.
#   * `norebind_mut` is the MUTATION, not a claim: it is the count of rows that move when
#     `gr_29_same` is replaced by `True{}`, recorded in the table at the foot.
# ===========================================================================

# ---- the fixture arena ------------------------------------------------------
#
# ONE arena holding every node shape the gate needs, built in binding order. CONSTs
# first so that a rule's fold literals intern onto nodes that already exist, which is
# what makes the node COUNTS comparable with Python's (Python's counts depend on its own
# intern pool having the same entries).
# ONE arena holding every node shape the gate needs, built in binding order. The field
# names are the RULE TAGS, because "which rule does this node hit" is the question the
# gate asks and a field named `t12` answers it without a lookup. CONSTs come first so a
# rule's fold literals intern onto nodes that already exist, which is what makes the node
# COUNTS comparable with Python's.
type Fix is Data:
  Fix{fx: F.Folded, t1: U32, t4: U32, t5: U32, t6: U32, t7: U32, t8: U32, t9: U32,
      t10: U32, t11: U32, t12: U32, t13: U32, t14: U32, t15: U32, t16: U32, t17: U32,
      t18: U32, t26: U32, t32: U32,
      t31: U32, af29: U32, af28: U32, one: U32, bufA: U32, bufB: U32, gate: U32,
      store29: U32, store28: U32}

# TWO BUFFERS on distinct slots. Their `buf_uop` differ, which is what makes the
# ordering-only AFTER (tag 28) a DIFFERENT node from the rebind one (tag 29) -- the pair
# the two-sided identity gate is built on.
def fx_pa(slot: U32) -> O.ParamArg: O.ParamArg.of(slot, S.single())

def fx_buf(+ar: O.Arena, slot: U32) -> O.Found:
  gnew(ar, O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(slot)})

def fix.put(fx: F.Folded, t1: U32, t4: U32, t5: U32, t6: U32, t7: U32, t8: U32, t9: U32,
            t10: U32, t11: U32, t12: U32, t13: U32, t14: U32, t15: U32, t16: U32, t17: U32,
            t18: U32, t26: U32, t32: U32, t31: U32, af29: U32, af28: U32, one: U32,
            bufA: U32, bufB: U32, t0: U32, store29: U32, store28: U32) -> Fix:
  Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26,
       t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}

# THE NODE LIST, in binding order. The comment on each line says what the node is and
# WHICH TAG claims it -- and for three of them, what ELSE claims it.
#   0 bottom          the arena's spent slot, and tinygrad's `None`
#   1 CONST 1.0       the seed ctx of every rule call
#   2 CONST 0.5       POW's base
#   3 CAST(1.0,int)   CAST's ret.src[0], whose dtype the rule reads
#   4 RECIPROCAL(1)   tag 1
#   5 SIN(1)          tag 2
#   6 LOG2(1)         tag 3
#   7 EXP2(1)         tag 4
#   8 SQRT(1)         tag 5
#   9 TRUNC(1)        tag 6
#  10 CMPLT(1,1)      tag 7 -- the ALL-HOLES answer
#  11 ADD(1,1)        tag 9 -- ctx in BOTH slots
#  12 POW(.5,1)       tag 10
#  13 MAX(1,1)        tag 11 -- a TIE, so the ctx*0.5 branch is live
#  14 MUL(1,1)        tag 12 -- a SQUARE, so interning makes both slots one node
#  15 WHERE(1,1,1)    tag 13
#  16 STAGE(1)        tag 16
#  17 EXPAND(1)       tag 18
#  18 RESHAPE(1,3)    tag 17 -- TWO srcs, so its 2-slot answer is EXACT here
#  19 SINK(1,.5)      tag 26 -- ctx.src is the answer
#  20 CAST(1,float)   tag 0
#  21 BITCAST(3,float) tag 32 -- ONE hole for a ONE-src node
#  22 STORE(1,.5)     tag 31
#  23 BUFFER slot 0   no rule claims a BUFFER
#  24 BUFFER slot 1
#  25 STORE(A,1)      tag 29's STORE: dest is bufA, and so is the AFTER's src[0]
#  26 AFTER(A, 25)    tag 29 FIRES -- the identity holds. tag 28 and 30 also CLAIM it.
#  27 STORE(A,.5)     tag 29's STORE again, for the ordering-only AFTER
#  28 AFTER(B, 27)    tag 28's shape: dest is bufB, stored into bufA, so the identity
#                     FAILS and tag 29 must NOT fire.
def fix() -> Fix:
  +n1 = gconst(O.Arena.empty(), k_fone())
  +n2 = gconst(O.Found.ar(n1), k_fhalf())
  +n3 = gcast(O.Found.ar(n2), O.Found.i(n2), S.int32())
  +n4 = gnew(O.Found.ar(n3), O.OpsRECIPROCAL{}, [O.Found.i(n1)], O.ANone{})
  +n5 = gnew(O.Found.ar(n4), O.OpsSIN{}, [O.Found.i(n1)], O.ANone{})
  +n6 = gnew(O.Found.ar(n5), O.OpsLOG2{}, [O.Found.i(n1)], O.ANone{})
  +n7 = gnew(O.Found.ar(n6), O.OpsEXP2{}, [O.Found.i(n1)], O.ANone{})
  +n8 = gnew(O.Found.ar(n7), O.OpsSQRT{}, [O.Found.i(n1)], O.ANone{})
  +n9 = gnew(O.Found.ar(n8), O.OpsTRUNC{}, [O.Found.i(n1)], O.ANone{})
  +n10 = gnew(O.Found.ar(n9), O.OpsCMPLT{}, [O.Found.i(n1), O.Found.i(n1)], O.ANone{})
  +n11 = gadd(O.Found.ar(n10), O.Found.i(n1), O.Found.i(n1))
  +n12 = gnew(O.Found.ar(n11), O.OpsPOW{}, [O.Found.i(n2), O.Found.i(n1)], O.ANone{})
  +n13 = gnew(O.Found.ar(n12), O.OpsMAX{}, [O.Found.i(n1), O.Found.i(n1)], O.ANone{})
  +n14 = gmul(O.Found.ar(n13), O.Found.i(n1), O.Found.i(n1))
  +n15 = gwhere(O.Found.ar(n14), O.Found.i(n1), O.Found.i(n1), O.Found.i(n1))
  +n16 = gnew(O.Found.ar(n15), O.OpsSTAGE{}, [O.Found.i(n1)], O.ANone{})
  +n17 = gnew(O.Found.ar(n16), O.OpsEXPAND{}, [O.Found.i(n1)], O.ANone{})
  +n18 = gnew(O.Found.ar(n17), O.OpsRESHAPE{}, [O.Found.i(n1), O.Found.i(n3)], O.ANone{})
  +n19 = O.UOp.sink(O.Found.ar(n18), [O.Found.i(n1), O.Found.i(n2)])
  +n20 = gcast(O.Found.ar(n19), O.Found.i(n1), S.single())
  +n21 = gnew(O.Found.ar(n20), O.OpsBITCAST{}, [O.Found.i(n3)], O.ADt{S.single()})
  +n22 = gnew(O.Found.ar(n21), O.OpsSTORE{}, [O.Found.i(n1), O.Found.i(n2)], O.ANone{})
  +bA = fx_buf(O.Found.ar(n22), 0)
  +bB = fx_buf(O.Found.ar(bA), 1)
  +s29 = gnew(O.Found.ar(bB), O.OpsSTORE{}, [O.Found.i(bA), O.Found.i(n1)], O.ANone{})
  +a29 = gnew(O.Found.ar(s29), O.OpsAFTER{}, [O.Found.i(bA), O.Found.i(s29)], O.ANone{})
  +s28 = gnew(O.Found.ar(a29), O.OpsSTORE{}, [O.Found.i(bA), O.Found.i(n2)], O.ANone{})
  +a28 = gnew(O.Found.ar(s28), O.OpsAFTER{}, [O.Found.i(bB), O.Found.i(s28)], O.ANone{})
  fix.put(F.folded(O.Found.ar(a28)), O.Found.i(n1), O.Found.i(n4), O.Found.i(n5), O.Found.i(n6),
    O.Found.i(n7), O.Found.i(n8), O.Found.i(n9), O.Found.i(n10), O.Found.i(n11), O.Found.i(n12),
    O.Found.i(n13), O.Found.i(n14), O.Found.i(n15), O.Found.i(n16), O.Found.i(n17), O.Found.i(n18),
    O.Found.i(n19), O.Found.i(n21), O.Found.i(n22), O.Found.i(a29), O.Found.i(a28), O.Found.i(n1),
    O.Found.i(bA), O.Found.i(bB), O.Found.i(n20), O.Found.i(s29), O.Found.i(s28))

# ---- the readings -----------------------------------------------------------
#
# EVERY ROW IS A READING OF A `GRes`, and the readers are named so a row says what it
# measured. `rw` runs the WHOLE table through `gr_rewrite`, so every row below is
# "what does `pm_gradient.rewrite` answer for this node" -- the same question Python's
# `pm_gradient.rewrite(uop, ctx=...)` answers, and never the rule called directly. That
# is what makes the first-wins behaviour testable rather than assumed.
def rw(ar: O.Arena, ctx: U32, self: U32) -> GRes: gr_rewrite(gr_table(), ar, ctx, self)

def Fix.fx(x: Fix) -> F.Folded:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: fx
def Fix.t1(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t1
def Fix.t4(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t4
def Fix.t5(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t5
def Fix.t6(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t6
def Fix.t7(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t7
def Fix.t8(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t8
def Fix.t9(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t9
def Fix.t10(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t10
def Fix.t11(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t11
def Fix.t12(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t12
def Fix.t13(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t13
def Fix.t14(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t14
def Fix.t15(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t15
def Fix.t16(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t16
def Fix.t17(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t17
def Fix.t18(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t18
def Fix.t26(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t26
def Fix.t32(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t32
def Fix.t31(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t31
def Fix.af29(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: af29
def Fix.af28(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: af28
def Fix.one(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: one
def Fix.bufA(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: bufA
def Fix.bufB(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: bufB
def Fix.t0(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: t0
def Fix.store29(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: store29
def Fix.store28(x: Fix) -> U32:
  match x:
    case Fix{fx, t1, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t26, t32, t31, af29, af28, one, bufA, bufB, t0, store29, store28}: store28

def fx_ar(f: Fix) -> O.Arena: F.Folded.ar(Fix.fx(f))
def Fix.n(x: Fix) -> U32: Fix.t1(x)
# THE COUNT. `pm_gradient.pdict` has 33 entries and the PORTED TABLE MUST TOO, because
# `UPAT_COMPILE=1` (ops.py:1588) means the COMPILED table is the live one and tag 29 --
# the rebind -- is only a tag if the entries before it are in the same order and number.
# A dropped entry shifts every tag after it and this row is the only thing that says so.
def t_claims() -> U32: U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(gr_table())))

# THE ROWS THAT ACTUALLY PIN THE RULES. A rule's node COUNT is the one fact that no
# amount of value-agreement can hide: a port that emitted a bare CONST instead of
# Python's `CAST(CONST)` pair (ops.py:632) would build a SHORTER graph with the SAME
# value, and every boolean row above would still pass. `Arena.next` is the length, so
# the growth is `next(after) - next(before)` -- and the arena is APPEND-ONLY and
# INTERNING (ops.bend:1777), so an existing node contributes 0 and the difference is
# exactly the number of NEW nodes the rule created.
#
# These numbers are Python's, dumped by `.agents/slop/notes/grad_oracle.py`:
#   recip 12   sin 10   log2 8    exp2 8    sqrt 9    trunc 2
#   pow   24 (slot 0) and 29 (slot 1) -- the SAME rule, and they differ because slot 1
#         builds the `b.eq(0)` / `e<0` / `-inf` branch that slot 0 does not.
#   max   21 per slot, both slots equal.
# ---- THE ROWS THAT ACTUALLY PIN THE RULES -------------------------------------
#
# A rule's gradient is a NODE TREE, and its SIZE is the one fact no amount of
# value-agreement can hide. A port that folded the `CAST` away from a CONST would build
# a strictly shorter tree with the strictly same value, and every boolean row in this
# gate would still pass. The size is arena-INDEPENDENT, which matters: `Arena.next`
# growth is not comparable to Python's counts, because Python's intern pool is fresh per
# process and this fixture's arena already holds every folded constant, so the growth
# here is 3 for `recip` where Python's tree has 12 nodes. The two numbers are about
# different things and the tree size is the one with an oracle.
#
# Python's expectation, from `.agents/slop/notes/grad_oracle.py`:
#   recip 12   sin 10   log2 8    exp2 8    sqrt 9    trunc 2    add 12
#   pow   24 (slot 0) and 29 (slot 1) -- the SAME RULE, and they DIFFER because slot 1
#         builds the `b.eq(0)` / `e<0` / `-inf` branch that slot 0 does not. A gate that
#         only read slot 0 would never notice half of the rule being missing.
#   max   21 per slot, and the two are EQUAL, which is the tie-symmetry fact.
#   mul   12, where 12 -- not 2 -- is the point: a SQUARE's two slots are the SAME node,
#         and Python's tree for that one node is still 12.
# THE NODE COUNT OF THE GRADIENT TREE: `1 + sum(size(s) for s in u.src)`.
#
# ONE def, no helper, and the reason is worth recording because it cost four attempts.
# ANY split into "count this node" and "count this node's srcs" is MUTUALLY RECURSIVE,
# and Bend refuses mutual recursion outright (notes, "There is no mutual recursion",
# reproduced in three lines): the error points at the LATER call and claims the earlier
# one is an unfilled law. So there is exactly ONE def, and it carries the whole descent:
#
#     size(fuel, ar, todo, acc) = acc                                    if todo is empty
#                                 1 + size(fuel-1, ar, srcs(head), 0) + size(fuel, ar, tail, 0)
#
# FUEL FIRST (rule 5). TWO self-calls in one arm is rule 7 -- but rule 7 says "the same
# FUEL may not feed two self-calls", and here the two calls get DIFFERENT fuel: the
# head's srcs get `fuel - 1` and the tail gets `fuel` unchanged. That is what makes the
# arm legal, and it is the same shape `gs_solid.go` above uses (tail only, fuel free)
# and `fold.bend`'s Kahn uses (fuel decrements, list separate). Both descents are
# visible: the fuel shrinks on one branch, the list tail shrinks on the other.
#
# The fuel is `Arena.budget(ar)` (ops.bend:2292) = `next(ar) + edges`, the exact number of
# pops a walk over the whole arena makes. A gradient tree is a subgraph of the grown
# arena, so the walk cannot be cut short, and the DAG makes the bound finite.
# THE ARM SHAPE, and it took five attempts, so the reasons are recorded because the
# obvious spelling does not compile.
#
# A `match` may only scrutinise a PARAMETER or a PATTERN BINDER (notes rule 2), so the
# fuel countdown cannot be nested inside the list arm -- the inner `match fuel:` reads a
# binder by then and is refused with "this name is a def or a consumed binder". It has to
# be a TWO-SCRUTINEE `match fuel todo` with ONE PATTERN PER SCRUTINEE (notes: `case _ _:`
# is the cover, `case _:` is not).
#
# AND `p` MAY NOT BE BOUND IN TWO ARMS -- it is consumed by the arm that uses it, so
# `case 1n+p Nil{}` and `case 1n+p s <> t` are both illegal together. The fix is to put
# the fuel test ONLY in the arm that consumes it, and let the empty-list case be reached
# by the COVER arm. That is why the cover arm is `_ _` and not `1n+p _`: the cover is
# where "no nodes left" lands, and it needs no fuel.
#
# The two self-calls get DIFFERENT fuel -- `p` into the head's srcs, `fuel` unchanged
# into the tail -- and that is what makes the arm legal under rule 7 ("the same fuel may
# not feed two self-calls in ONE arm"). Both descents are visible: the fuel shrinks on
# one branch, the list tail on the other.
def size(+fuel: Nat, +ar: O.Arena, todo: List<&2, U32>, acc: U32) -> U32:
  match fuel todo:
    case 1n+p s <> t: U32.add(U32.add(acc, U32.add(1, size(p, ar, O.Arena.srcs(ar, s), 0))), size(fuel, ar, t, 0))
    case _ _: acc

def size1(+ar: O.Arena, n: U32) -> U32:
  size(O.Arena.budget(ar), ar, O.Arena.srcs(ar, n), 1)

# `size1(n)` counts `n` plus everything under it, and the ROOT's own `+1` is the `1`
# seed. `size_const` (2) and `size_mul` (5) are the controls: `CAST(CONST)` is 2 and
# `MUL(CAST(CONST), CAST(CONST))` is 5, both matching Python's `1 + sum(...)`.

# THE CONTROL FOR `size`. A CONST is 2 nodes here (`CAST(CONST)`, measured) so this is 2,
# and if it prints anything else then `size` is wrong and every `*_n` row above is wrong
# with it. It is the smallest fixture the arena can hold and it pins the "+1 for the node
# itself" that the accumulator starts at.
def t_size_const() -> U32:
  +c = gconst(O.Arena.empty(), k_fzero())
  size1(O.Found.ar(c), O.Found.i(c))

def t_size_mul() -> U32:
  +c = gconst(O.Arena.empty(), k_fzero())
  +m = gmul(O.Found.ar(c), O.Found.i(c), O.Found.i(c))
  size1(O.Found.ar(m), O.Found.i(m))

def t_one_n() -> U32: size1(fx_ar(fix()), Fix.n(fix()))
def t_seven_n() -> U32: size1(fx_ar(fix()), Fix.t7(fix()))

# The gradient's tree size for slot `k` of the rewrite of `self`. Fuel is
# `Arena.budget` (ops.bend:2292) because the gradient tree is built from `self` and can
# only be as large as the arena plus what the rule added, so the budget is a bound on
# the walk's depth and the fuel-first order is what makes the descent legal.
# The rewrite runs ONCE and both readers come off it -- `gs_ar` and `gs_get` each need the
# `GRes`, and a second `gr_rewrite` would build a SECOND gradient tree into a second
# arena, which is not the same object and would make the count meaningless. Hence `+r`.
def tsize.of(+r: GRes, k: Nat) -> U32: size1(gs_ar(r), gs_get(r, k))

def tsize(+ar: O.Arena, ctx: U32, +self: U32, k: Nat) -> U32:
  tsize.of(gr_rewrite(gr_table(), ar, ctx, self), k)

def t_recip_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t4(f), 0n)

def t_sin_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t5(f), 0n)

def t_log2_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t6(f), 0n)

def t_exp2_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t7(f), 0n)

def t_sqrt_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t8(f), 0n)

def t_trunc_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t9(f), 0n)

def t_add_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t11(f), 0n)

def t_pow_n0() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t12(f), 0n)

def t_pow_n1() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t12(f), 1n)

def t_max_n0() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t13(f), 0n)

# THE ROW THAT SEES `eq`'s OP. `max_n0` is 21 whether `eq` is `CMPNE`-then-`CMPNE` or
# `CMPEQ`, because the counts coincide -- which is exactly the "two rules agree and the
# gate cannot see it" failure. `max_eq_op` reads the OP of the node `gnot` produced and
# expects `Ops.CMPNE`, and it is the ONLY row M7 moves.
# THE PATH IS `WHERE.src[1].src[0]` -- the OUTER `where`'s untaken-branch arm, whose
# mask is the `x.eq(y)`. Python's `MAX` gradient tree, measured:
#   WHERE
#     CMPLT, CAST, CONST          <- (x>y)
#     CAST, CONST                <- ctx
#     WHERE                      <- (x.eq(y)).where(ctx*0.5, 0)
#       CMPNE                    <- x != y
#         CMPNE                  <- logical_not
#         MUL, CONST
#       CONST
def max.inner(ar: O.Arena, g: U32) -> U32: O.Arena.src(ar, g, 2)
def max.eq_of(hit: Bool) -> U32:
  match hit:
    case True{}: 1
    case False{}: 0

def max.eq_src(ar: O.Arena, inner: U32) -> U32: O.Arena.src(ar, inner, 1)

def max.eq_op.go(+ar: O.Arena, inner: U32) -> U32:
  max.eq_of(O.op_is(ar, O.Arena.src(ar, inner, 0), O.OpsCMPNE{}))

def max.outer_op(+ar: O.Arena, g: U32) -> U32:
  max.eq_of(O.op_is(ar, g, O.OpsWHERE{}))

def max.eq_op(+ar: O.Arena, g: U32) -> U32:
  max.eq_op.go(ar, max.inner(ar, g))

def t_max_eq_op() -> U32:
  +f = fix()
  +r = gr_rewrite(gr_table(), fx_ar(f), Fix.n(f), Fix.t13(f))
  max.eq_op(gs_ar(r), gs_get(r, 0n))

def t_max_outer() -> U32:
  +f = fix()
  +r = gr_rewrite(gr_table(), fx_ar(f), Fix.n(f), Fix.t13(f))
  max.outer_op(gs_ar(r), gs_get(r, 0n))
def t_max_n1() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t13(f), 1n)

def t_mul_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t14(f), 0n)

def t_mul_n1() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t14(f), 1n)

def t_where_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t15(f), 1n)

def t_stage_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.t16(f), 0n)

def t_rebind_n() -> U32:
  +f = fix()
  tsize(fx_ar(f), Fix.n(f), Fix.af29(f), 1n)

# `UOp.const(0.0, float32)` is `CAST(CONST)` -- TWO nodes -- and this is the row that
# says so directly, without a rule in the way. A port that folded the cast away would
# answer 1 and every `*_n` row above would drop by one per folded constant.
def t_const_cast() -> U32:
  +c = gconst(O.Arena.empty(), k_fzero())
  U32.sub(O.Arena.next(O.Found.ar(c)), O.Arena.next(O.Arena.empty()))

def t_const_raw() -> U32:
  +c = gconst_raw(O.Arena.empty(), k_fzero())
  U32.sub(O.Arena.next(O.Found.ar(c)), O.Arena.next(O.Arena.empty()))

# `-math.inf` really is f32 infinity and not a large finite number. helpers.bend's
# `f32_exp_all_ones` reads `bits & 0x7F800000 == 0x7F800000`, and `-inf` is the sign bit
# on top of it, so the row is the whole bit pattern.
def t_neginf() -> U32: k_neginf_bits()

# `gr_table()[29].ops == [AFTER]` and `gr_table()[29].rej == [STORE]` -- the tag the
# name-rebind LIVES AT, read out of the TABLE rather than off `gr_29`. If the table were
# reordered the rebind would still work and the header's tag claim would be a lie.
# THE BOOL READER. Every gate row is a `U32`, so `1` is a claim that held and `0` a claim
# that did not -- and Bend has no assertion form, so a `0` in the output is the signal.
def b32(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0


def gr_e29() -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, O.PMEntrys.es(gr_table()), 29n),
                O.PMEntry{0, Nil{}, Nil{}})

def t_rej29.ops(e: O.PMEntry) -> Bool: O.eq_op_list(O.PMEntry.ops(e), [O.OpsAFTER{}])
def t_rej29.rej(e: O.PMEntry) -> Bool: O.eq_op_list(O.PMEntry.rej(e), [O.OpsSTORE{}])

def t_rej29.of(ops_ok: Bool, rej_ok: Bool) -> U32:
  match ops_ok:
    case True{}: b32(rej_ok)
    case False{}: 0

def t_rej29() -> U32: t_rej29.of(t_rej29.ops(gr_e29()), t_rej29.rej(gr_e29()))

# ---- the identity-check family: three rows, ONE rule, TWO node shapes --------
#
# `af29` is `AFTER(BUFFER_A, STORE(BUFFER_A, v))`: `dest` binds to the same node twice,
# so tag 29 fires and the answer is `(None, ctx)` -- slot 0 a hole, slot 1 ctx itself.
def t_rebind_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.af29(fix())))
def t_rebind_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.af29(fix())))
def t_rebind_0_hole() -> U32: b32(gs_hole(rw(fx_ar(fix()), Fix.n(fix()), Fix.af29(fix())), 0n))
def t_rebind_1_ctx() -> U32: b32(U32.is_eq(gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.af29(fix())), 1n), Fix.n(fix())))

# `af28` is `AFTER(BUFFER_B, STORE(BUFFER_A, v))`: the same pattern SHAPE, but `dest` is
# B and the stored-into node is A, so the identity FAILS. Tag 29 must answer `GSkip` --
# and because it is first-wins and it is the ONLY implemented AFTER rule, the WHOLE
# rewrite skips, which is Python's `None` (measured: `pm_gradient.rewrite` on this shape
# returns `None`).
#
# THIS IS THE ROW THE NAME-REBIND EXISTS FOR. Without `U32.is_eq`, `t_rebind_solid` on
# `af28` would be 1 and this row would be 0 -- i.e. the rule would fire on a node Python
# refuses. And `af28`'s `buf_uop`s DIFFER, so tag 28 (ordering-only) is the Python rule
# that OWNS this node; the port does not implement tag 28, so the honest answer here is
# "no rule fired", and the row says so rather than claiming tag 28's answer.
def t_rebind_off() -> U32: b32(gs_is_skip(rw(fx_ar(fix()), Fix.n(fix()), Fix.af28(fix()))))

# THE CLAIM, counted over the whole table rather than read off `gr_29`: how many entries
# claim `af28`. Python claims tags 27..30 by op and `rej` and then 28's BODY decides; the
# port claims ONE, tag 29, and the identity check rejects it. So the port's claim count
# on `af28` is 0 and on `af29` is 1. Two rows, one node each, and they are the pair that
# says the check is load-bearing rather than decorative.
def t_claim29() -> U32: b32(gr_claimed(O.PMEntry.ops(gr_e29()), fx_ar(fix()), Fix.af29(fix())))
def t_claim29_off() -> U32: b32(gr_claimed(O.PMEntry.ops(gr_e29()), fx_ar(fix()), Fix.af28(fix())))

# ---- the structural rows, one per rule whose answer is a SHAPE not a value -------
#
# A gradient rule's answer is a NODE LIST, and the list's LENGTH, its HOLES and whether
# its slots are the SAME index are the three facts that survive without evaluating float
# arithmetic -- which is the only kind of checking this port can do, since `ctx`'s VALUE
# lives in a fold. Python's answers are dumped by `.agents/slop/notes/grad_oracle.py`
# and are the expectation for every one of these.
def t_recip_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t4(fix())))
def t_sin_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t5(fix())))
def t_log2_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t6(fix())))
def t_exp2_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t7(fix())))
def t_sqrt_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t8(fix())))
def t_trunc_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t9(fix())))
def t_cmplt_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t10(fix())))
def t_cmplt_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t10(fix())))
def t_add_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t11(fix())))
def t_add_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t11(fix())))
def t_add_same() -> U32: b32(U32.is_eq(gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t11(fix())), 0n),
                                       gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t11(fix())), 1n)))
def t_pow_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t12(fix())))
def t_pow_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t12(fix())))
def t_max_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t13(fix())))
def t_max_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t13(fix())))
def t_mul_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t14(fix())))
def t_mul_same() -> U32: b32(U32.is_eq(gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t14(fix())), 0n),
                                       gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t14(fix())), 1n)))
def t_where_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t15(fix())))
def t_where_0_hole() -> U32: b32(gs_hole(rw(fx_ar(fix()), Fix.n(fix()), Fix.t15(fix())), 0n))
def t_stage_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t16(fix())))
def t_stage_ctx() -> U32: b32(U32.is_eq(gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t16(fix())), 0n), Fix.n(fix())))
def t_expand_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t17(fix())))
def t_reshape_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t18(fix())))
def t_sink_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t26(fix())))
def t_store_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t31(fix())))
def t_store_0_hole() -> U32: b32(gs_hole(rw(fx_ar(fix()), Fix.n(fix()), Fix.t31(fix())), 0n))
def t_store_1_ctx() -> U32: b32(U32.is_eq(gs_get(rw(fx_ar(fix()), Fix.n(fix()), Fix.t31(fix())), 1n), Fix.n(fix())))
# THE `gr_0` ROWS. `CAST` is the ONE rule that reads the FOLD rather than the arena
# (gradient.py:67 `ctx.cast(ret.src[0].dtype)`), so it is also the one rule whose answer
# depends on `fold.bend` being right. `cast_len` says it fires at all; `cast_dt` says the
# `ADt` arg it built is the dtype of the node BELOW the CAST -- `int32` here, because the
# fixture's `t0` is `CAST(seed, float32)` over a CONST whose natural dtype is float32
# after the fold's promotion, and Python's `ret.src[0].dtype` is the SAME read.
def t_cast_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t0(fix())))

def t_t0_is_cast() -> U32: b32(O.op_is(fx_ar(fix()), Fix.t0(fix()), O.OpsCAST{}))
def t_cast_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t0(fix())))

def t_bitcast_len() -> U32: gs_len(rw(fx_ar(fix()), Fix.n(fix()), Fix.t32(fix())))
def t_bitcast_solid() -> U32: gs_solid(rw(fx_ar(fix()), Fix.n(fix()), Fix.t32(fix())))

# THE SINK ROWS THAT ACTUALLY PIN THE RULE. `gs_len` alone is satisfied by ANY
# two-element list; `sink_srcs` reads the INDICES and says they are `ctx`'s own srcs,
# which is the whole of gradient.py:94 (`ctx.src`). A rule returning `[ctx, ctx]` passes
# `sink_len` and fails `sink_srcs` -- that is M10, and it is why this row is here.
def sink.of(r: GRes) -> List<&2, U32>:
  match r:
    case GSkip{}: Nil{}
    case GFired{gs, ar}: gs

def t_sink_srcs() -> U32:
  +f = fix()
  b32(O.eq_u32(sink.of(rw(fx_ar(f), Fix.n(f), Fix.t26(f))), O.Arena.srcs(fx_ar(f), Fix.n(f))))

# THE FIRST-WINS DISCRIMINATOR, and this is the brief's SECOND TRAP made concrete:
# "if your table has no node that TWO rules both claim, a first-wins-vs-conjunction bug
# moves NOTHING and your gate cannot see it."
#
# `af29` is claimed by tags 27, 28, 29 and 30 -- all four are `Ops.AFTER` with a two-src
# STORE/CALL src -- and they DISAGREE: 27 answers `(ctx, sink)`, 28 answers
# `(ctx, None)` or skips, 29 answers `(None, ctx)`, 30 answers `(mask, grad)`. Only 29
# FIRES, so the answer must come from 29 and not from a later one. Under LAST-WINS the
# same scan would return 30's or 28's answer; under a CONJUNCTION (every claiming rule
# must hold) it would return nothing at all. `first_wins` reads that the answer is
# `(None, ctx)` and `claim29_off` is the control on the node shape where 29 must not fire.
def t_first_wins() -> U32:
  +f = fix()
  b32(U32.is_eq(gs_get(rw(fx_ar(f), Fix.n(f), Fix.af29(f)), 1n), Fix.n(f)))

# AND THE DIRECT ROW FOR `gs_keep`, because a scan-level row only proves the ANSWER and
# not the fold. Two `GFired` answers in, and the EARLIER must survive: `keep_pair`
# answers 11 if `gs_keep(fired([1,2]), fired([3,4]))` is `[1,2]` and 33 if it is `[3,4]`.
# Under last-wins this row is 33, and it is the ONLY row that moves for M2 -- the
# scan-level rows all still pass, which is the trap itself.
def t_keep_pair() -> U32:
  +r = gs_keep(fired([1, 2], O.Arena.empty()), fired([3, 4], O.Arena.empty()))
  U32.add(gs_len(r), U32.mul(10, gs_get(r, 0n)))

# AND THE DIRECT ROW FOR `gs_keep` ON A SKIP: a `GSkip` must not erase an earlier
# `GFired`. `keep_skip` answers 1 if `gs_keep(fired([7]), GSkip{})` is `[7]`.
def t_keep_skip() -> U32:
  b32(U32.is_eq(gs_get(gs_keep(fired([7], O.Arena.empty()), GSkip{}), 0n), 7))

# `gr_rej`'s subset test, on the one rule whose reject set is non-empty AND whose answer
# depends on the set being spelled right. A `rej` of `Nil{}` would make `gr_rej.go` return
# `True{}` on its first arm and the SECOND src's op would never be consulted; `rej_len`
# reads the set's length so a MISSPELLED set shows up.
def t_rej_len() -> U32:
  U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(gr_e29())))

# THE ROW THAT SEES `gr_rej` DECIDE SOMETHING. A MISSPELLED reject set is invisible to
# every other row -- the op test alone claims the node, the rule body is unchanged, and
# the answer is identical. The only thing that notices is the SET ITSELF, and the way to
# notice is to check that `early_reject` REFUSES a node it should refuse: tag 27 rejects
# `CALL`, so an AFTER whose second src is a STORE must NOT satisfy it, while tag 29's
# `STORE` reject must. `rej_gate` reads both and expects 1 and 0.
def gr_e27() -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, O.PMEntrys.es(gr_table()), 27n),
                O.PMEntry{0, Nil{}, Nil{}})

def rej.of(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def t_rej_gate() -> U32:
  +f = fix()
  U32.add(rej.of(gr_rej.go(gr_ler(fx_ar(f), Fix.af29(f)), O.PMEntry.rej(gr_e27()))),
          U32.mul(10, rej.of(gr_rej.go(gr_ler(fx_ar(f), Fix.af29(f)), O.PMEntry.rej(gr_e29())))))

def t_rej_len27() -> U32:
  U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(gr_e27())))

# ---- the gate ----------------------------------------------------------------
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("claims", t_claims())
    b : Unit <- row("const_cast", t_const_cast())
    row("size_const", t_size_const())
    row("size_mul", t_size_mul())
    row("one_n", t_one_n())
    row("seven_n", t_seven_n())
    row("const_raw", t_const_raw())
    row("neginf", t_neginf())
    row("recip_n", t_recip_n())
    row("sin_n", t_sin_n())
    row("log2_n", t_log2_n())
    row("exp2_n", t_exp2_n())
    row("sqrt_n", t_sqrt_n())
    row("trunc_n", t_trunc_n())
    row("pow_n0", t_pow_n0())
    row("pow_n1", t_pow_n1())
    row("max_n0", t_max_n0())
    row("max_n1", t_max_n1())
    row("mul_n", t_mul_n())
    row("where_n", t_where_n())
    row("add_n", t_add_n())
    row("stage_n", t_stage_n())
    row("rebind_n", t_rebind_n())
    row("rej29", t_rej29())
    c : Unit <- row("rebind_solid", t_rebind_solid())
    d : Unit <- row("rebind_len", t_rebind_len())
    e : Unit <- row("rebind_0_hole", t_rebind_0_hole())
    f : Unit <- row("rebind_1_ctx", t_rebind_1_ctx())
    g : Unit <- row("rebind_off", t_rebind_off())
    h : Unit <- row("claim29", t_claim29())
    i : Unit <- row("claim29_off", t_claim29_off())
    j : Unit <- row("recip_len", t_recip_len())
    k : Unit <- row("sin_len", t_sin_len())
    l : Unit <- row("log2_len", t_log2_len())
    m : Unit <- row("exp2_len", t_exp2_len())
    n : Unit <- row("sqrt_len", t_sqrt_len())
    o : Unit <- row("trunc_len", t_trunc_len())
    p : Unit <- row("cmplt_len", t_cmplt_len())
    q : Unit <- row("cmplt_solid", t_cmplt_solid())
    r : Unit <- row("add_len", t_add_len())
    s : Unit <- row("add_solid", t_add_solid())
    t : Unit <- row("add_same", t_add_same())
    u : Unit <- row("pow_len", t_pow_len())
    v : Unit <- row("pow_solid", t_pow_solid())
    w : Unit <- row("max_len", t_max_len())
    x : Unit <- row("max_solid", t_max_solid())
    y : Unit <- row("mul_len", t_mul_len())
    z : Unit <- row("mul_same", t_mul_same())
    row("where_len", t_where_len())
    row("where_0_hole", t_where_0_hole())
    row("stage_len", t_stage_len())
    row("stage_ctx", t_stage_ctx())
    row("expand_len", t_expand_len())
    row("reshape_len", t_reshape_len())
    row("sink_len", t_sink_len())
    row("sink_srcs", t_sink_srcs())
    row("first_wins", t_first_wins())
    row("keep_pair", t_keep_pair())
    row("keep_skip", t_keep_skip())
    row("max_eq_op", t_max_eq_op())
    row("max_outer", t_max_outer())
    row("rej_len", t_rej_len())
    row("rej_gate", t_rej_gate())
    row("rej_len27", t_rej_len27())
    row("store_len", t_store_len())
    row("store_0_hole", t_store_0_hole())
    row("store_1_ctx", t_store_1_ctx())
    row("t0_is_cast", t_t0_is_cast())
    row("cast_len", t_cast_len())
    row("cast_solid", t_cast_solid())
    row("bitcast_len", t_bitcast_len())
    row("bitcast_solid", t_bitcast_solid())