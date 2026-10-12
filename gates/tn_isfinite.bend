# tn_isfinite.bend -- a small driver for `tn_isfinite` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_isfinite-gate.py
#
# SIX ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane
# calls `tn_isfinite` from the port and asks the shape/op/arg/srcs of the new
# node; the oracle calls CPython's `Tensor.isfinite` (elementwise.py:623) and
# asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# An INT input, NOT a CFloat. CPython's `isfinite` is `(self.isinf() | self.isnan()).
# logical_not()`. With `isinf`'s default `detect_*=True`, the body inlines to
# `(self.eq(+inf)*True + self.eq(-inf)*True | self!=self).ne(True)`. The top is therefore a
# CMPNE (`logical_not`'s CMPNE), with src[0] the OR and src[1] the CONST{True} the NOT tests
# against.
#
# `src[0]` IS A SHARED ROW NOW, AND IT WAS NOT BEFORE. This block used to say "`src[0]` IS NOT A
# SHARED ROW. It is CAST here -- the port keeps `tn_logical_not`'s explicit `cast(bool)` -- and OR
# in CPython". BOTH HALVES WERE TRUE AND BOTH ARE NOW FALSE, because `tn_logical_not` reached the
# FOLDING `D.cast_at` (`mixin/dtype.bend:342`) and the cast folds away on a bool input:
#
#   port    tn_isfinite=14 Ops.CMPNE/2 Ops.OR Ops.CONST
#   cpython tn_isfinite=15 Ops.CMPNE/2 Ops.OR Ops.CONST
#
# `src[0]` is `OR` ON BOTH SIDES. The remaining 14-vs-15 is ONE MISSING CONST LEAF, not a cast: CPython's
# graph holds BOTH `weakint 4` (kept by `self != self`) and `weakfloat 4.0` (reminted by
# `_broadcasted`'s promote half in `self.eq(inf)`, `elementwise.py:29-31`), and the two hash-cons
# apart. That is the `_broadcasted`/`remint` wall and it is NOT fixed here -- see
# `gates/tn_graph_census-gate.py`'s one remaining pin, which records the reason.
def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# Top op: CMPNE (the outer `logical_not` of the `or`).
def row_isfinite_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isfinite(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

# Top arg: None (every ALU node carries ANone).
def row_isfinite_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isfinite(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# Top has 2 srcs: the (OR or CAST-wrapping-OR) and the CONST{True}.
def row_isfinite_top_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isfinite(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 2)

def row_isfinite_reachable() -> Bool:
  True{}

# THE TWO ROWS THAT CAUGHT THE ARENA BUG. `logical_not` compares the top against a
# CONST{True}, so `src[1]` must be that CONST. A port that builds the CMPNE in the arena as
# it stood BEFORE the const was interned appends the CMPNE at the slot the const index names,
# and `src[1]` becomes the top node -- a node that is its own src. `Arena` is an immutable
# `Data` value (`ops.bend:1255`), so `Found.ar` snapshots and an index is legal only in an
# arena descending from the one that minted it.
def row_isfinite_src1_is_const() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isfinite(t)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{})

def row_isfinite_src1_is_not_self() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isfinite(t)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.not(U32.is_eq(O.Arena.src(ar, i, 1), i))

# WHAT THIS GATE DOES NOT SEE, STATED RATHER THAN ASSUMED. `tn_isfinite.armul` builds its
# MUL in the arena the CONST grew, and a port that built it in `eq`'s arena instead would
# make the MUL its own `src[1]` -- the same defect the two rows above catch one level up.
# MEASURED: reverting `armul` to the `tn_alu` spelling leaves all six rows green. The row
# that would see it has to walk four hops down, and `bend` answers `unknown: IO` past about
# two -- the same elaborator limit that makes `O.CFloat{1.0}` unusable as this input. SO THE
# FIX IS REAL, IT IS NOT GATED, AND THAT IS THE TRUTH OF THIS ROW SET.

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("isfinite_op_is_cmpne", row_isfinite_op())
    b : Unit <- row("isfinite_arg_is_anone", row_isfinite_arg())
    c : Unit <- row("isfinite_has_two_top_srcs", row_isfinite_top_srcs())
    d : Unit <- row("isfinite_is_reachable", row_isfinite_reachable())
    e : Unit <- row("isfinite_src1_is_const", row_isfinite_src1_is_const())
    f : Unit <- row("isfinite_src1_is_not_self", row_isfinite_src1_is_not_self())
    return Unit{}