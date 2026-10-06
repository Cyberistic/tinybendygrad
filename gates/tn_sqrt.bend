# tn_sqrt.bend -- a small driver for `tn_sqrt` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_sqrt-gate.py
#
# FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_sqrt` and asks the shape/op/arg of the new node; the oracle calls CPython's
# `Tensor.sqrt` and asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{4}} tensor and apply sqrt. The new node's op IS OpsSQRT{}.
def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def row_sqrt_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sqrt(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSQRT{})

def row_sqrt_src() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sqrt(t)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)), [T.Tensor.u(t)])

def row_sqrt_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sqrt(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_sqrt_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sqrt(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSQRT{}))

def row_sqrt_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sqrt_op_is_sqrt", row_sqrt_op())
    b : Unit <- row("sqrt_src_is_input", row_sqrt_src())
    c : Unit <- row("sqrt_arg_is_anone", row_sqrt_arg())
    d : Unit <- row("sqrt_does_not_mutate_input", row_sqrt_pure())
    e : Unit <- row("sqrt_is_reachable", row_sqrt_reachable())
    return Unit{}
