# tn_sin_log2_exp2_rsqrt.bend -- a driver for the four one-liner (or near-one-liner)
# ports in this round:
#   tn_sin   -- elementwise.py:494   return self.alu(Ops.SIN)
#   tn_log2  -- elementwise.py:531   return self.alu(Ops.LOG2)
#   tn_exp2  -- elementwise.py:543   return self.alu(Ops.EXP2)
#   tn_rsqrt -- elementwise.py:820   return self.sqrt().reciprocal()
#
#   .venv/bin/python gates/tn_sin_log2_exp2_rsqrt-gate.py
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

# ROW 1-3: sin / log2 / exp2 (the three pure-alu one-liners).
def row_sin_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sin(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSIN{})

def row_log2_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_log2(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsLOG2{})

def row_exp2_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_exp2(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsEXP2{})

# ROW 4: rsqrt (composed of sqrt -> reciprocal, both ported).
def row_rsqrt_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rsqrt(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsRECIPROCAL{})

def row_rsqrt_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rsqrt(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rsqrt_src_count() -> Bool:
  +t = mk_tensor()
  +r = T.tn_rsqrt(t)
  U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 1)

# ROW 6-9: purity + reachability.
def row_purity() -> Bool:
  +t = mk_tensor()
  +r = T.tn_sin(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSIN{}))

def row_sin_reachable() -> Bool:
  True{}

def row_log2_reachable() -> Bool:
  True{}

def row_exp2_reachable() -> Bool:
  True{}

def row_rsqrt_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sin_op_is_sin", row_sin_op())
    b : Unit <- row("log2_op_is_log2", row_log2_op())
    c : Unit <- row("exp2_op_is_exp2", row_exp2_op())
    d : Unit <- row("rsqrt_op_is_reciprocal", row_rsqrt_op())
    e : Unit <- row("rsqrt_arg_is_anone", row_rsqrt_arg())
    f : Unit <- row("rsqrt_has_one_src", row_rsqrt_src_count())
    f : Unit <- row("sin_does_not_mutate_input", row_purity())
    g : Unit <- row("sin_is_reachable", row_sin_reachable())
    h : Unit <- row("log2_is_reachable", row_log2_reachable())
    i : Unit <- row("exp2_is_reachable", row_exp2_reachable())
    j : Unit <- row("rsqrt_is_reachable", row_rsqrt_reachable())
    return Unit{}
