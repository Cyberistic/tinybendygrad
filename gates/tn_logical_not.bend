# tn_logical_not.bend -- a small driver for `tn_logical_not` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_logical_not-gate.py
#
# SEVEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_logical_not` from the port and asks the shape/op/arg/srcs of the new node; the
# oracle calls CPython's `Tensor.logical_not` and asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CBool{True}} tensor and apply logical_not. The graph is
# CAST(boolean) + CONST(True) + CMPNE, same shape as `tn_bitwise_not`.
def mk_bool_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def row_logical_not_op() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_logical_not(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

def row_logical_not_arg() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_logical_not(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_logical_not_pure() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_logical_not(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{}))

def row_logical_not_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("logical_not_op_is_cmpne", row_logical_not_op())
    b : Unit <- row("logical_not_arg_is_anone", row_logical_not_arg())
    c : Unit <- row("logical_not_does_not_mutate_input", row_logical_not_pure())
    d : Unit <- row("logical_not_is_reachable", row_logical_not_reachable())
    return Unit{}
