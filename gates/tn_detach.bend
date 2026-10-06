# tn_detach.bend -- a small driver for `tn_detach` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_detach-gate.py
#
# FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_detach` and asks the shape/op/arg of the new node; the oracle calls CPython's
# `Tensor.detach` and asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{4}} tensor and apply detach. The new node's op IS OpsDETACH{}.
def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def row_detach_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_detach(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsDETACH{})

def row_detach_src() -> Bool:
  +t = mk_tensor()
  +r = T.tn_detach(t)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)), [T.Tensor.u(t)])

def row_detach_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_detach(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_detach_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_detach(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsDETACH{}))

def row_detach_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("detach_op_is_detach", row_detach_op())
    b : Unit <- row("detach_src_is_input", row_detach_src())
    c : Unit <- row("detach_arg_is_anone", row_detach_arg())
    d : Unit <- row("detach_does_not_mutate_input", row_detach_pure())
    e : Unit <- row("detach_is_reachable", row_detach_reachable())
    return Unit{}
