# tn_lshift_rshift.bend -- a small driver for `tn_lshift` / `tn_rlshift` /
# `tn_rshift` / `tn_rrshift` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_lshift_rshift-gate.py
#
# EIGHT ROWS, NAMED ONCE.

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

def row_lshift_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_lshift(t, t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSHL{})

def row_lshift_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_lshift(t, t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_lshift_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_lshift(t, t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

def row_rlshift_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rlshift(t, t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSHL{})

def row_rlshift_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rlshift(t, t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rlshift_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rlshift(t, t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

def row_rshift_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rshift(t, t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSHR{})

def row_rshift_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rshift(t, t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rshift_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rshift(t, t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCONST{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lshift_op_is_shl", row_lshift_op())
    b : Unit <- row("lshift_arg_is_anone", row_lshift_arg())
    c : Unit <- row("lshift_does_not_mutate_input", row_lshift_pure())
    d : Unit <- row("rlshift_op_is_shl", row_rlshift_op())
    e : Unit <- row("rlshift_arg_is_anone", row_rlshift_arg())
    f : Unit <- row("rlshift_does_not_mutate_input", row_rlshift_pure())
    g : Unit <- row("rshift_op_is_shr", row_rshift_op())
    h : Unit <- row("rshift_arg_is_anone", row_rshift_arg())
    i : Unit <- row("rshift_does_not_mutate_input", row_rshift_pure())
    return Unit{}
