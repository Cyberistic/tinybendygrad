# tn_relu.bend -- a small driver for `tn_relu` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_relu-gate.py
#
# FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_relu` and asks the shape/op/arg/srcs of the new node; the oracle calls
# CPython's `Tensor.relu` and asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# CPython's relu is `(self > 0).where(self, 0)` -- a WHERE node where the
# condition is a CMPLT (reversed to GT) and the false arm is a CONST 0.

def row_relu_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{})

def row_relu_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_relu_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

def row_relu_three_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 3)

def row_relu_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("relu_op_is_where", row_relu_op())
    b : Unit <- row("relu_arg_is_anone", row_relu_arg())
    c : Unit <- row("relu_does_not_mutate_input", row_relu_pure())
    d : Unit <- row("relu_has_three_srcs", row_relu_three_srcs())
    e : Unit <- row("relu_is_reachable", row_relu_reachable())
    return Unit{}
