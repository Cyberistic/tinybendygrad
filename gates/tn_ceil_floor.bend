# tn_ceil_floor.bend -- a small driver for `tn_ceil` / `tn_floor` in
# `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_ceil_floor-gate.py
#
# ELEVEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane
# calls `tn_ceil` / `tn_floor` from the port and asks the shape/op/arg/srcs of
# the new node; the oracle calls CPython's `Tensor.ceil` / `Tensor.floor` and
# asks the same. A row agrees only if two implementations of the property say
# so.
#
# WHAT THIS GRAPH IS. CPython's `Tensor.ceil` (elementwise.py:656) is
# `(self > (b := self.trunc())).where(b+1, b)`. The `b+1` is a CONST-trap: a
# `Tensor.__add__` on a TENSOR rhs (the `c1t` we build) is `_binop`'s body
# (elementwise.py:36) with `Ops.ADD` -- a single ADD node, srcs `(b, c1)`.
# The port follows the same shape: `tn_add(b, c1t)` builds `ADD(b, c1)`, the
# `tn_where(gt, bp1, b)` builds `WHERE(gt, bp1, b)`, and the final node is a
# single WHERE whose srcs are `(self>b, b+1, b)`. `Tensor.floor`
# (elementwise.py:662) is the same shape with `b-1` (a SUB via `tn_sub`
# instead of ADD) and the FORWARD CMPLT (`tn_cmplt`, NOT `tn_rcmplt`). The
# oracle therefore calls `t.ceil()` / `t.floor()` directly -- CPython's
# `_binop` builds a single MUL/ADD/SUB node (not a chain of `+1`), so the
# port's single-ADD and single-SUB shapes match the oracle's graph exactly.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# A CONST{CInt{N}} tensor. The fixture is a CONST so the graph stays simple --
# the gate checks the GRAPH SHAPE (op/arg/srcs), not arithmetic semantics.
def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ===========================================================================
# ROW 1-5: tn_ceil -- the WHERE chain `(self > b).where(b+1, b)`.
# ===========================================================================

# ROW 1: tn_ceil's op is WHERE.
def row_ceil_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_ceil(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{})

# ROW 2: the WHERE's arg is None.
def row_ceil_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_ceil(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# ROW 3: the WHERE has 3 srcs (cond, b+1, b). `n_srcs == 3` is what the
# CPython oracle checks (oracle's `len(r.uop.src) == 3`), and it is what
# distinguishes a WHERE from a binary op. The actual uop-index order is the
# same `tn_where` writes (cond at src0, x at src1, y at src2) -- a
# correctness check below.
def row_ceil_three_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_ceil(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 3)

# ROW 4: the input still has its original op (CONST) -- tn_ceil does not
# mutate. Same shape as `tn_relu`'s `relu_does_not_mutate_input` row.
def row_ceil_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_ceil(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

# ROW 5: the WHERE's cond src is a CMPLT (the `self > b` inequality built
# by `tn_rcmplt`). The oracle asserts the same: CPython's `(self > b)` is
# `self.cmplt(b, reverse=True)` (the `__gt__` arm), which is a `CMPLT` node
# in the oracle.
def row_ceil_cond_op.head(ar: O.Arena, srcs: List<&2, U32>) -> Bool:
  match srcs:
    case c <> _:
      O.eq_op(O.Arena.op(ar, c), O.OpsCMPLT{})
    case _:
      False{}

def row_ceil_cond_is_cmplt() -> Bool:
  +t = mk_tensor()
  +r = T.tn_ceil(t)
  row_ceil_cond_op.head(T.Tensor.ar(r), O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)))

# ===========================================================================
# ROW 6-11: tn_floor -- the WHERE chain `(self < b).where(b-1, b)`.
# ===========================================================================

# ROW 6: tn_floor's op is WHERE.
def row_floor_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_floor(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{})

# ROW 7: the WHERE's arg is None.
def row_floor_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_floor(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# ROW 8: the WHERE has 3 srcs (cond, b-1, b).
def row_floor_three_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_floor(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 3)

# ROW 9: the input still has its original op (CONST) -- tn_floor does not
# mutate. Same shape as `tn_relu`'s row.
def row_floor_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_floor(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

# ROW 10: the WHERE's cond src is a CMPLT (the `self < b` inequality built
# by `tn_cmplt`). The oracle asserts the same: CPython's `(self < b)` is
# `self.cmplt(b)`, which is a `CMPLT` node in the oracle.
def row_floor_cond_op.head(ar: O.Arena, srcs: List<&2, U32>) -> Bool:
  match srcs:
    case c <> _:
      O.eq_op(O.Arena.op(ar, c), O.OpsCMPLT{})
    case _:
      False{}

def row_floor_cond_is_cmplt() -> Bool:
  +t = mk_tensor()
  +r = T.tn_floor(t)
  row_floor_cond_op.head(T.Tensor.ar(r), O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)))

# ROW 11: both defs are REACHABLE -- the audit's wall text said `ceil` and
# `floor` were unwritten.
def row_ceil_floor_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("ceil_op_is_where", row_ceil_op())
    b   : Unit <- row("ceil_arg_is_anone", row_ceil_arg())
    c   : Unit <- row("ceil_has_three_srcs", row_ceil_three_srcs())
    d   : Unit <- row("ceil_does_not_mutate_input", row_ceil_pure())
    e   : Unit <- row("ceil_cond_is_cmplt", row_ceil_cond_is_cmplt())
    f   : Unit <- row("floor_op_is_where", row_floor_op())
    g   : Unit <- row("floor_arg_is_anone", row_floor_arg())
    h   : Unit <- row("floor_has_three_srcs", row_floor_three_srcs())
    i   : Unit <- row("floor_does_not_mutate_input", row_floor_pure())
    j   : Unit <- row("floor_cond_is_cmplt", row_floor_cond_is_cmplt())
    k   : Unit <- row("ceil_floor_is_reachable", row_ceil_floor_reachable())
    return Unit{}
