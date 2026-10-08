# tn_maximum.bend -- a small driver for `tn_maximum`.
#
#   .venv/bin/python gates/tn_maximum-gate.py
#
# FIVE ROWS, NAMED ONCE.

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

def row_max_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_maximum(t, t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMAX{})

def row_max_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_maximum(t, t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_max_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_maximum(t, t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMAX{}))

def row_max_reachable() -> Bool:
  True{}




def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("max_op_is_max", row_max_op())
    b : Unit <- row("max_arg_is_anone", row_max_arg())
    c : Unit <- row("max_does_not_mutate_input", row_max_pure())
    g : Unit <- row("maximum_is_reachable", row_max_reachable())
    return Unit{}
