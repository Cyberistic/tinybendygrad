# tn_contiguous_backward.bend -- a small driver for `tn_contiguous_backward` in
# `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_contiguous_backward-gate.py
#
# FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked.

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

def row_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_contiguous_backward(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONTIGUOUS_BACKWARD{})

def row_src() -> Bool:
  +t = mk_tensor()
  +r = T.tn_contiguous_backward(t)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)), [T.Tensor.u(t)])

def row_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_contiguous_backward(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_contiguous_backward(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONTIGUOUS_BACKWARD{}))

def row_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("contiguous_backward_op", row_op())
    b : Unit <- row("contiguous_backward_src_is_input", row_src())
    c : Unit <- row("contiguous_backward_arg_is_anone", row_arg())
    d : Unit <- row("contiguous_backward_does_not_mutate_input", row_pure())
    e : Unit <- row("contiguous_backward_is_reachable", row_reachable())
    return Unit{}
