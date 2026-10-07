# tn_relu6.bend -- a small driver for `tn_relu6` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_relu6-gate.py
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

# CPython's relu6 is `((r := self.relu()) < 6).where(r, 6)`. The relu and the
# `6` are both ported (`tn_relu` builds a WHERE; `O.UOp.const` builds the 6).

def row_relu6_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu6(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{})

def row_relu6_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu6(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_relu6_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu6(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

def row_relu6_three_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_relu6(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 3)

def row_relu6_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("relu6_op_is_where", row_relu6_op())
    b : Unit <- row("relu6_arg_is_anone", row_relu6_arg())
    c : Unit <- row("relu6_does_not_mutate_input", row_relu6_pure())
    d : Unit <- row("relu6_has_three_srcs", row_relu6_three_srcs())
    e : Unit <- row("relu6_is_reachable", row_relu6_reachable())
    return Unit{}
