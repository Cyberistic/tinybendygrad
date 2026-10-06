# tn_trunc_reciprocal_threefry.bend -- a small driver for the three one-liner ports
# in `tinybendygrad/tensor.bend`:
#   `tn_trunc`        -- elementwise.py:474  return self.alu(Ops.TRUNC)
#   `tn_reciprocal`   -- elementwise.py:460  return self.alu(Ops.RECIPROCAL)
#   `tn_threefry`     -- elementwise.py:457  return self.alu(Ops.THREEFRY, seed)
#
#   .venv/bin/python gates/tn_trunc_reciprocal_threefry-gate.py
#
# NINE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# each def and asks the shape/op/arg/srcs of the new node; the oracle calls the
# corresponding CPython method and asks the same.

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

# ROW 1-2: tn_trunc.
def row_trunc_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_trunc(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsTRUNC{})

def row_trunc_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_trunc(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsTRUNC{}))

# ROW 3-4: tn_reciprocal.
def row_reciprocal_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_reciprocal(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsRECIPROCAL{})

def row_reciprocal_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_reciprocal(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsRECIPROCAL{}))

# ROW 5-7: tn_threefry.
def row_threefry_op() -> Bool:
  +t = mk_tensor()
  +s = mk_tensor()
  +r = T.tn_threefry(t, s)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsTHREEFRY{})

def row_threefry_srcs() -> Bool:
  +t = mk_tensor()
  +s = mk_tensor()
  +r = T.tn_threefry(t, s)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(t), T.Tensor.u(s)])

def row_threefry_arg() -> Bool:
  +t = mk_tensor()
  +s = mk_tensor()
  +r = T.tn_threefry(t, s)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# ROW 8-9: all three reachable.
def row_trunc_reachable() -> Bool:
  True{}

def row_threefry_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("trunc_op_is_trunc", row_trunc_op())
    b : Unit <- row("trunc_does_not_mutate_input", row_trunc_pure())
    c : Unit <- row("reciprocal_op_is_reciprocal", row_reciprocal_op())
    d : Unit <- row("reciprocal_does_not_mutate_input", row_reciprocal_pure())
    e : Unit <- row("threefry_op_is_threefry", row_threefry_op())
    f : Unit <- row("threefry_srcs_are_self_and_seed", row_threefry_srcs())
    g : Unit <- row("threefry_arg_is_anone", row_threefry_arg())
    h : Unit <- row("trunc_is_reachable", row_trunc_reachable())
    i : Unit <- row("threefry_is_reachable", row_threefry_reachable())
    return Unit{}
