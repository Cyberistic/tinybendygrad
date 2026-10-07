# tn_where.bend -- a small driver for `tn_where` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_where-gate.py
#
# EIGHT ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane
# calls `tn_where` from the port and asks the shape/op/arg/srcs of the new node;
# the oracle calls CPython's `Tensor.where` and asks the same. CPython's body is
# `x, y = self.ufix(x)._broadcasted(y); return self.alu(Ops.WHERE, x, y)`, and
# the no-broadcasting case is the gate: `_broadcasted` is identity for same-shape
# Tensors, so the graph is `tn_alu(cond, WHERE, [x, y])`.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def mk_bool() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def mk_int(seven: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(seven)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def row_where_op() -> Bool:
  +c = mk_bool()
  +x = mk_int(3)
  +y = mk_int(5)
  +r = T.tn_where(c, x, y)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{})

def row_where_arg() -> Bool:
  +c = mk_bool()
  +x = mk_int(3)
  +y = mk_int(5)
  +r = T.tn_where(c, x, y)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_where_srcs() -> Bool:
  +c = mk_bool()
  +x = mk_int(3)
  +y = mk_int(5)
  +r = T.tn_where(c, x, y)
  T.tn_where_srcs_are(r, c, x, y)

def row_where_pure() -> Bool:
  +c = mk_bool()
  +x = mk_int(3)
  +y = mk_int(5)
  +r = T.tn_where(c, x, y)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsWHERE{}))

def row_where_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("where_op_is_where", row_where_op())
    b : Unit <- row("where_arg_is_anone", row_where_arg())
    c : Unit <- row("where_srcs_are_cond_x_y", row_where_srcs())
    d : Unit <- row("where_does_not_mutate_input", row_where_pure())
    e : Unit <- row("where_is_reachable", row_where_reachable())
    return Unit{}
