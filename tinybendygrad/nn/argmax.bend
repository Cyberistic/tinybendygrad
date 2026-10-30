# `nn/argmax.bend` -- upstream's `Tensor.argmax` RECIPE, ported, IN TWO FORMS.
#
# WHAT UPSTREAM IS. `tinygrad/mixin/op.py:863-887`:
#
#     m   = self.eq(self.max(axis=axis, keepdim=True))
#     idx = m * type(self).arange(self.shape[axis], 0, -1).reshape(...)
#     return (self.shape[axis] - idx.max(axis=axis, keepdim=keepdim)).cast(dtypes.int32)
#
# `arange(n, 0, -1)` is `[n, n-1, ..., 1]`, so `idx[j]` is `n - j` where the value at
# `j` IS a maximum and `0` where it is not, so `idx.max` picks the LARGEST `n - j`
# among the maxima, which is the SMALLEST `j` among them -- THE FIRST OCCURRENCE.
# **THE TIE-BREAKING RULE IS A CONSEQUENCE OF THE FORMULA, NOT AN ASSERTION ABOUT IT.**
#
# THE TWO FORMS, AND WHY THERE ARE TWO.
#
#   * THE LIST FORM (`nn_argmax`, below) is the RECIPE AS A FORMULA ON THE VALUES. It
#     has an ANSWER, and the six rows are UPSTREAM'S ANSWERS, re-checked against
#     CPython in `.venv`: **0 disagreements of 6.**
#   * THE GRAPH FORM (`nn_argmax_g`, below) is the RECIPE AS A UOP GRAPH -- the four
#     nodes upstream builds -- and it has a SHAPE and a DTYPE but NO VALUE, because
#     THE PORT BUILDS GRAPHS AND HAS NO EXECUTOR.
#
# **AND THE GRAPH FORM IS BUILDABLE ONLY BECAUSE OF A FIX IN `mixin/rand.bend`, AND THE
# FIX IS THE WHOLE OF THE STORY.** MEASURED 2026-10-23, `.agents/slop/nnargmax2/`:
# the port's `arange` chain contained TWO nodes whose products disagree with their
# source's, so `uop/fold.bend`'s `reshape_ds` -- which is upstream's `ops.py:499-503`
# INCLUDING ITS `raise` -- REFUSED them, and a node whose source has no shape has no
# shape either, so THE WHOLE ARANGE GRAPH WAS UNREADABLE. `mixin/rand.bend`'s
# `op_expand_lead` and `op_pool1.sh` are the two sites and both are FIXED. **BEFORE
# THE FIX THE ARANGE'S ROOT READ `SHAPE[]`; AFTER IT READS `SHAPE[4]`.**
#
# `am_pick` IS THE MASK-TIMES-COUNTER (`idx[j]`), `am_max` IS `self.max`, AND `am_best`
# IS `idx.max`. `Bool.pick` AND NOT `match` ON A COMPUTED VALUE: `match` MAY NOT
# SCRUTINISE A CALL (BEND'S RULE 1), AND `tinybendygrad/uop/ops.bend:8991 symbol=fs.pinfo.of` IS THE
# TREE'S OWN COUNTER-EXAMPLE OF WHAT THAT COSTS -- A `match` ON A CALL THERE POISONED
# EVERY FILE THAT IMPORTS `uop/ops.bend`.
#
# SCOPE, STATED SO NOBODY INVENTS A WIDER CLAIM: THE LIST FORM IS A 1-D F32 FORMULA
# AND THE GRAPH FORM IS A 1-D F32 GRAPH. Upstream's `argmax` takes an AXIS and any
# dtype. A generalisation is a WIDENING OF THIS FILE, NOT A NEW IDEA, AND IT IS NOT
# DONE HERE. **THE GRAPH FORM'S REMAINING DIVERGENCES FROM UPSTREAM'S GRAPH ARE NAMED
# IN `.agents/slop/nnargmax2/REPORT.md` AND THEY ARE NOT CLOSED HERE.**

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../uop/weak.bend as W
import ./../tensor.bend as T
import ./../mixin/op.bend as M
import ./../mixin/movement.bend as MX
import ./../mixin/elementwise.bend as E
import ./../mixin/rand.bend as RD
import ./layers.bend as L

# ===========================================================================
# THE LIST FORM -- THE RECIPE AS A FORMULA ON THE VALUES.
# ===========================================================================

# `idx[j]` -- `n - j` where `v[j]` is a maximum, `0` where it is not.
def nn_argmax.pick(eq: Bool, j: U32, n: U32) -> U32: Bool.pick(U32, eq, U32.sub(n, j), 0)

# `self.max(axis=axis)` -- the running maximum. THE ACCUMULATOR IS THE SECOND
# PARAMETER and the list is the first, because Bend's termination check reads the
# arguments LEFT TO RIGHT and stops at the first one that is a smaller part of its
# parameter; the ones after it are free.
def nn_argmax.max.go(vals: List<&2, F32>, +acc: F32) -> F32:
  match vals:
    case Nil{}: acc
    case +v <> t: nn_argmax.max.go(t, Bool.pick(F32, F32.is_gt(v, acc), v, acc))

# `self.max(axis=axis)` -- seeded from the head, so no `-inf` constant is needed and an
# all-`-inf` list still answers the head.
def nn_argmax.head_max(vals: List<&2, F32>) -> F32:
  match vals:
    case Nil{}: 0.0
    case +v <> t: nn_argmax.max.go(t, v)

# `idx.max(axis=axis)` -- the running maximum of the masked counter. `j` IS THE
# POSITION, carried as an accumulator, because upstream's `arange` is exactly that
# counter and the port has no `arange` to borrow.
def nn_argmax.best(vals: List<&2, F32>, +mx: F32, +j: U32, +n: U32, +acc: U32) -> U32:
  match vals:
    case Nil{}: acc
    case +v <> t:
      nn_argmax.best(t, mx, U32.add(j, 1), n,
        Bool.pick(U32, U32.is_gt(acc, nn_argmax.pick(F32.is_eq(v, mx), j, n)), acc,
          nn_argmax.pick(F32.is_eq(v, mx), j, n)))

# `Tensor.argmax(axis=0)` on a 1-D tensor -- `mixin/op.py:863`.
def nn_argmax(+vals: List<&2, F32>) -> U32:
  +n = U32.from_nat(List.length(&2, F32, vals))
  +best = nn_argmax.best(vals, nn_argmax.head_max(vals), 0, n, 0)
  U32.sub(n, best)

# THE ROWS. The `want` IS UPSTREAM'S OWN ANSWER, NOT THIS FILE'S OUTPUT.
def nn_argmax.row(nm: String, vals: List<&2, F32>, want: U32) -> IO(Unit):
  IO.print(String.concat([nm, " got=", U32.show(nn_argmax(vals)), " want=", U32.show(want)]))

# ===========================================================================
# THE GRAPH FORM -- THE RECIPE AS THE FOUR NODES UPSTREAM BUILDS.
#
# `mixin/op.py:863-888`, ONE DEF PER NODE, IN UPSTREAM'S ORDER:
#   1  `m   = self.eq(self.max(axis=axis, keepdim=True))`      -> `nn_argmax_g.m`
#   2  `idx = m * type(self).arange(self.shape[axis], 0, -1)`  -> `nn_argmax_g.idx`
#   3  `idx.max(axis=axis, keepdim=keepdim)`                   -> `nn_argmax_g.imx`
#   4  `(self.shape[axis] - idx.max(...)).cast(dtypes.int32)`  -> `nn_argmax_g.out`
#
# THE `.reshape(self.shape[axis], *[1]*(self.ndim-axis-1))` OF NODE 2 IS A NO-OP FOR A
# 1-D SOURCE -- `[n]` IS ALREADY `[n]` -- SO THE 1-D FORM IS THE SAME RECIPE AND THE
# RESHAPE IS NOT BUILT. **THE WIDENING IS NAMED IN THE SCOPE PARAGRAPH ABOVE.**
# ===========================================================================

# THE `n` -- `self.shape[axis]` -- IS CARRIED IN A RECORD AND NOT IN A `U32`, BECAUSE
# A `U32` IS CONSUMED ONCE AND `n` IS NEEDED TWICE: ONCE FOR THE `arange` AND ONCE FOR
# THE SUBTRACTION. THE TREE'S OWN SPELLING OF THIS IS `mixin/rand.bend`'s `U1`
# (`mixin/rand.bend:270-274`), AND IT IS THE SAME FACT AND THE SAME FIX.
type AN is Data:
  AN{v: U32}

def AN.v(q: AN) -> U32:
  match q:
    case AN{v}: v

# NODE 1a -- `self.max(axis=axis, keepdim=True)`. `nn_reduce` IS `nn/layers.bend`'s
# `_rop` (ops.py:630-639) WITH THE PERMUTE RESTORED, and it is CALLED.
def nn_argmax_g.mx(+t: T.Tensor) -> T.Tensor: L.nn_reduce(t, [0], O.OpsMAX{}, True{})

# NODE 1b -- `self.eq(...)`. UPSTREAM'S `eq` IS A `CMPEQ` (`mixin/elementwise.py`), AND
# THE PORT SPELLS IT `NOT(CMPNE)` IN `mixin/op.bend:628 symbol=mo_eqc`'s `mo_eqc` -- SO THE `CMPEQ`
# IS BUILT DIRECTLY HERE AND THE `NOT` IS NOT BUILT, WHICH IS UPSTREAM'S GRAPH AND NOT
# THE PORT'S OWN SPELLING.
def nn_argmax_g.m(+t: T.Tensor, +mx: T.Tensor) -> T.Tensor: M.mo_bin(t, O.OpsCMPEQ{}, mx)

# NODE 2a -- `type(self).arange(self.shape[axis], 0, -1)`. IT IS `mixin/rand.bend`'s
# `op_arange_neg`, WHICH IS UPSTREAM'S `arange` WITH `step = -1` AND THE `dtype` OF
# `commit_int(1, n)` (op.py:190) -- MEASURED IN CPYTIN: `int32`.
def nn_argmax_g.ar(+ar: O.Arena, +q: AN, +dev: S.Dev) -> T.Tensor:
  RD.op_arange_neg(ar, AN.v(q), dev)

# NODE 2b -- `m * arange`.
def nn_argmax_g.idx(+m: T.Tensor, +a: T.Tensor) -> T.Tensor: M.mo_bin(m, O.OpsMUL{}, a)

# NODE 3 -- `idx.max(axis=axis, keepdim=keepdim)`.
def nn_argmax_g.imx(+idx: T.Tensor) -> T.Tensor: L.nn_reduce(idx, [0], O.OpsMAX{}, False{})

# NODE 4a -- `self.shape[axis] - idx.max(...)`. UPSTREAM'S `__rsub__`
# (`mixin/elementwise.py:296`) IS `self.sub(x, True)`, AND `sub` IS
# `a.alu(Ops.ADD, -b)` (elementwise.py:122) WITH THE OPERANDS REVERSED, SO IT IS
# `n + (-imx)` AND NOT `n - imx` -- THE PORT'S `mo_sub` IS EXACTLY THAT AND IS CALLED.
def nn_argmax_g.sub(+imx: T.Tensor, n: U32) -> T.Tensor:
  M.mo_sub(M.mo_const_t(imx, O.CInt{H.i64_of_i32(n)}), imx)

# NODE 4b -- `.cast(dtypes.int32)`.
def nn_argmax_g.out(+imx: T.Tensor, +q: AN) -> T.Tensor:
  M.mo_cast_t(nn_argmax_g.sub(imx, AN.v(q)), S.int32())

# THE WHOLE GRAPH, AND THE ARENA IS `t`'s.
def nn_argmax_g(+t: T.Tensor, +q: AN, +dev: S.Dev) -> T.Tensor:
  +mx = nn_argmax_g.mx(t)
  +m = nn_argmax_g.m(t, mx)
  +a = nn_argmax_g.ar(T.Tensor.ar(t), q, dev)
  +idx = nn_argmax_g.idx(m, a)
  +imx = nn_argmax_g.imx(idx)
  nn_argmax_g.out(imx, q)

# ===========================================================================
# THE READERS THE GRAPH ROWS USE. **THEY DO NOT USE `nn/layers.bend`'s `nn_shape`,
# AND THAT IS THE POINT.**
#
# `nn_shape` (nn/layers.bend:94) IS `nn_u32(M.mo_dims(F.folded(...)))`, AND `mo_dims`
# (mixin/op.bend:281) ANSWERS `Nil{}` FOR THREE DIFFERENT THINGS: A NODE THE FOLD
# CANNOT RESOLVE, A NODE WITH NO SHAPE, AND A NODE WHOSE SHAPE IS THE EMPTY LIST --
# A 0-dim SHAPE. `nn_u32` (nn/layers.bend:100 symbol=nn_u32) MAPS `Nil{}` BACK TO
# `Some{[]}`, SO
# `nn_shape` CANNOT TELL A REFUSAL FROM A 0-dim SHAPE. **UPSTREAM'S `imx` IS 0-dim,
# SO A READER THAT CONFLATES THE TWO WOULD PRINT `()` FOR A REFUSAL AND THE ROW WOULD
# PASS ON NOTHING.** THE READER BELOW ASKS `F.fold.shape` (uop/fold.bend:4827 symbol=fold.shape), WHICH
# ANSWERS THE DOUBLE `Maybe`: THE OUTER IS "THE NODE IS IN THE FOLD'S TABLE" AND THE
# INNER IS "THE NODE HAS A SHAPE", AND THE TWO ARE NOT THE SAME QUESTION.
# ===========================================================================

# THE SHAPE AS CPYTHON PRINTS IT: `()` FOR A 0-dim SHAPE, `(4,)` FOR A 1-dim ONE AND
# `(1, 3)` FOR A 2-dim ONE. **THE COUNT AND THE STRING ARE BUILT IN ONE WALK**, BECAUSE A
# `List` IS CONSUMED WHEN IT IS READ AND THE COUNT AND THE ELEMENTS ARE THE SAME LIST.
# THE RECORD IS THE TREE'S OWN SPELLING OF "TWO ANSWERS OUT OF ONE WALK" -- IT IS
# `mixin/rand.bend`'s `PK` AND `uop/fold.bend`'s `Sized`/`Shapes`.
type SP is Data:
  SP{s: String, n: U32}

def SP.s(q: SP) -> String:
  match q:
    case SP{s, n}: s

def SP.n(q: SP) -> U32:
  match q:
    case SP{s, n}: n

def nn_argmax_g.shp.end(acc: SP) -> String:
  match acc:
    case SP{s, n}: String.concat(["(", s, Bool.pick(String, U32.is_eq(n, 1), ",", ""), ")"])

def nn_argmax_g.shp.go(+ds: List<&2, O.Sint>, +acc: SP) -> String:
  match ds:
    case Nil{}: nn_argmax_g.shp.end(acc)
    case O.SI{i} <> rest:
      nn_argmax_g.shp.go(rest, SP{
        String.concat([SP.s(acc), Bool.pick(String, U32.is_eq(SP.n(acc), 0), "", ", "), U32.show(H.lo32(i))]),
        U32.add(SP.n(acc), 1)})
    case _: "SYMBOLIC"

def nn_argmax_g.shp.inner(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case None{}: "NO-SHAPE"
    case Some{ds}: nn_argmax_g.shp.go(ds, SP{"", 0})

def nn_argmax_g.shp.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "NO-TABLE"
    case Some{inner_m}: nn_argmax_g.shp.inner(inner_m)

def nn_argmax_g.shp(+t: T.Tensor) -> String:
  +fx = F.folded(T.Tensor.ar(t))
  nn_argmax_g.shp.of(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), T.Tensor.u(t)))

def nn_argmax_g.dt(+t: T.Tensor) -> String:
  +fx = F.folded(T.Tensor.ar(t))
  E.ew_dtnm(W.wk_dt(fx, T.Tensor.u(t)))

# ===========================================================================
# THE GRAPH ROWS. **EVERY `want` IS CPYTHON'S OWN SHAPE OR DTYPE FOR THAT NODE** --
# READ OFF `.agents/slop/nnargmax2/oracle_argmax.py`, WHICH ASKS CPYTIN ITSELF. NONE
# OF THEM IS COPIED FROM THE PORT'S OUTPUT.
#
#   cp_t     = (4,) dt=dtypes.f32
#   cp_mx    = (1,) dt=dtypes.f32
#   cp_m     = (4,) dt=dtypes.bool
#   cp_ar    = (4,) dt=dtypes.i32
#   cp_idx   = (4,) dt=dtypes.i32
#   cp_imx   = ()   dt=dtypes.i32
#   cp_res   = ()   dt=dtypes.i32
#   cp_out   = ()   dt=dtypes.i32
#
# **THE DTYPE NAMES ARE TRANSLATED ONCE AND THE TRANSLATION IS THE WHOLE OF IT:**
# CPython prints `dtypes.f32` / `dtypes.i32` / `dtypes.bool` AND THE PORT'S
# `mixin/elementwise.bend`'s `ew_dtnm` PRINTS `f32` / `i32` / `bool`. THE SAME THREE
# DTYPES, SPELLED THE PORT'S WAY, BECAUSE A ROW THAT PRINTS `dtypes.f32` ON ONE SIDE
# AND `f32` ON THE OTHER IS NOT A ROW.
# ===========================================================================

def nn_argmax_g.row(nm: String, got: String, want: String) -> IO(Unit):
  L.nn_row.line(nm, got, want)

def nn_argmax_g.rows() -> IO(Unit):
  +t = L.nn_row.t([4], 0, 4)
  +q: AN = AN{4}
  +mx = nn_argmax_g.mx(t)
  +m = nn_argmax_g.m(t, mx)
  +a = nn_argmax_g.ar(T.Tensor.ar(t), q, S.D1{0})
  +idx = nn_argmax_g.idx(m, a)
  +imx = nn_argmax_g.imx(idx)
  +out = nn_argmax_g.out(imx, q)
  do IO<Unit>:
    nn_argmax_g.row("g_t_shape", nn_argmax_g.shp(t), "(4,)")
    nn_argmax_g.row("g_t_dt", nn_argmax_g.dt(t), "f32")
    nn_argmax_g.row("g_mx_shape", nn_argmax_g.shp(mx), "(1,)")
    nn_argmax_g.row("g_mx_dt", nn_argmax_g.dt(mx), "f32")
    nn_argmax_g.row("g_m_shape", nn_argmax_g.shp(m), "(4,)")
    nn_argmax_g.row("g_m_dt", nn_argmax_g.dt(m), "bool")
    nn_argmax_g.row("g_ar_shape", nn_argmax_g.shp(a), "(4,)")
    nn_argmax_g.row("g_ar_dt", nn_argmax_g.dt(a), "i32")
    nn_argmax_g.row("g_idx_shape", nn_argmax_g.shp(idx), "(4,)")
    nn_argmax_g.row("g_idx_dt", nn_argmax_g.dt(idx), "i32")
    nn_argmax_g.row("g_imx_shape", nn_argmax_g.shp(imx), "()")
    nn_argmax_g.row("g_imx_dt", nn_argmax_g.dt(imx), "i32")
    nn_argmax_g.row("g_out_shape", nn_argmax_g.shp(out), "()")
    nn_argmax_g.row("g_out_dt", nn_argmax_g.dt(out), "i32")

def main() -> IO(Unit):
  do IO<Unit>:
    nn_argmax.row("argmax_unique", [1.0, 7.0, 3.0, 2.0], 1)
    nn_argmax.row("argmax_tie3", [5.0, 5.0, 5.0], 0)
    nn_argmax.row("argmax_tie2", [1.0, 9.0, 9.0, 2.0], 1)
    nn_argmax.row("argmax_tie_last", [9.0, 1.0, 9.0], 0)
    nn_argmax.row("argmax_neg", [F32.sub(0.0, 3.0), F32.sub(0.0, 1.0), F32.sub(0.0, 7.0)], 1)
    nn_argmax.row("argmax_zero", [0.0, 0.0, 1.0, 0.0], 2)
    nn_argmax_g.rows()
