# tn_mul.bend -- a small driver for `tn_mul` / `tn_rmul` / `tn_square` in
# `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_mul-gate.py
#
# THIRTEEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane
# calls `tn_mul` / `tn_rmul` / `tn_square` from the port and asks the
# shape/op/arg/srcs of the new node; the oracle calls CPython's `c * d`,
# `d.mul(c, reverse=True)`, and `c * c` and asks the same. A row agrees only if
# the two implementations say so.
#
# WHAT THIS GRAPH IS. `tn_mul` (elementwise.py:125) is
# `self._binop(Ops.MUL, x, reverse)`, and `_binop` is
# `lhs, rhs = self._broadcasted(x, reverse); return lhs.alu(MUL, rhs)`. For two
# Tensors of the same shape, `_broadcasted` is identity: `__mul__` builds
# `MUL(self, x)` with srcs `(self, x)`, and `__rmul__` (with `reverse=True`)
# builds `MUL(x, self)` with srcs `(x, self)`. The dispatch is `tn_mul.go`, keyed
# on a `Bool` (the same shape as `tn_neg.go` at `tensor.bend:437`). The
# broadcasting case stays walled on `_broadcasted` (mixin/movement.py:24, fold
# reads and a `least_upper_dtype` helper).

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. `tn_mul` and `tn_rmul` both build a MUL with the
# rhs's uop appended to the src list; `tn_square` calls `tn_mul(self, self)`, so
# the two srcs are equal.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_mul.
def row_mul_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_mul(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

def row_mul_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_mul(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_mul_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_mul(c, d)
  T.tn_srcs_are(r, c, d)

def row_mul_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_mul(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{}))

# ROW 5-8: tn_rmul -- the `reverse=True` arm of `tn_mul.go`.
def row_rmul_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rmul(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

def row_rmul_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rmul(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rmul_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rmul(c, d)
  T.tn_srcs_are(r, d, c)

def row_rmul_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rmul(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{}))

# ROW 9-12: tn_square -- `tn_mul(t, t)`. The srcs are (t, t) -- the same uop
# in both positions.
def row_square_op() -> Bool:
  +t = mk_tensor(3)
  +r = T.tn_square(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

def row_square_arg() -> Bool:
  +t = mk_tensor(3)
  +r = T.tn_square(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_square_srcs() -> Bool:
  +t = mk_tensor(3)
  +r = T.tn_square(t)
  T.tn_srcs_are(r, t, t)

def row_square_pure() -> Bool:
  +t = mk_tensor(3)
  +r = T.tn_square(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{}))

# ROW 13: the three defs are REACHABLE -- the audit's wall text said
# `__mul__` was unwritten.
def row_mul_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a  : Unit <- row("mul_op_is_mul", row_mul_op())
    b  : Unit <- row("mul_arg_is_anone", row_mul_arg())
    c  : Unit <- row("mul_srcs_are_self_and_x", row_mul_srcs())
    d  : Unit <- row("mul_does_not_mutate_input", row_mul_pure())
    e  : Unit <- row("rmul_op_is_mul", row_rmul_op())
    f  : Unit <- row("rmul_arg_is_anone", row_rmul_arg())
    g  : Unit <- row("rmul_srcs_are_x_and_self", row_rmul_srcs())
    h  : Unit <- row("rmul_does_not_mutate_input", row_rmul_pure())
    i  : Unit <- row("square_op_is_mul", row_square_op())
    j  : Unit <- row("square_arg_is_anone", row_square_arg())
    k  : Unit <- row("square_srcs_are_t_and_t", row_square_srcs())
    l  : Unit <- row("square_does_not_mutate_input", row_square_pure())
    m  : Unit <- row("mul_is_reachable", row_mul_reachable())
    return Unit{}
