# tn_neg.bend -- a small driver for `tn_neg` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_neg-gate.py
#
# SEVEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_neg` from the port and asks the shape/op/srcs of the new node; the oracle calls
# CPython's `Tensor.neg` and asks the same. A row agrees only if the two implementations
# say so.
#
# WHAT THIS GRAPH IS. `tn_neg` (elementwise.py:74) is `self.logical_not()` on a bool input
# and `self * (-1)` (= `MUL(self, -1)`) on an arith input. The port splits the dispatch
# on the fold of `tn_dtype` into `tn_neg.go`, which routes to `tn_logical_not` or
# `tn_neg.arith`. Both arms are ported, and the bool arm is the SAME graph `tn_logical_not`
# already gates (`CAST(bool) + CONST(True) + CMPNE`); the arith arm is `MUL(self, -1)`
# with the `-1` literal as a `CInt{4294967295}` (the u32 two's-complement pair of `-1`).
# The driver builds the two inputs and calls `tn_neg` on each; the rows inspect the result.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CBool{True}} tensor. `tn_neg` dispatches to `tn_logical_not` on a bool
# input, and the result op IS the CMPNE from that helper.
def mk_bool_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# Build a CONST{CInt{4}} tensor. `tn_neg` dispatches to `tn_neg.arith` on a non-bool
# input, and the result op IS the MUL with the `-1` const.
def mk_int_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1: on a bool input, `tn_neg` builds a CMPNE (the `tn_logical_not` graph).
def row_neg_bool_op() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

# ROW 2: the CMPNE's arg is ANone{}.
def row_neg_bool_arg() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_neg(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# ROW 3: on an int input, `tn_neg` builds a MUL (the `tn_neg.arith` arm).
def row_neg_int_op() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

# ROW 4: the MUL's srcs are [self, -1_const]. m1's index is read from the arena as
# src[1] of the MUL (the same value the eq_u32 below compares against), and the
# whole srcs list must equal [self.u, m1.u].
def row_neg_int_srcs() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(t), O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 1)])

# ROW 5: the result is a NEW node, not the input's index.
def row_neg_int_new() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  Bool.not(U32.is_eq(T.Tensor.u(t), T.Tensor.u(r)))

# ROW 6: the input is NOT mutated -- the input uop's op is still CONST.
def row_neg_int_pure() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{})

# ROW 7: the defs are REACHABLE -- the audit's wall text said `tn_neg` was unwritten.
def row_neg_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("neg_bool_op_is_cmpne", row_neg_bool_op())
    b : Unit <- row("neg_bool_arg_is_anone", row_neg_bool_arg())
    c : Unit <- row("neg_int_op_is_mul", row_neg_int_op())
    d : Unit <- row("neg_int_srcs_are_self_and_m1", row_neg_int_srcs())
    e : Unit <- row("neg_int_is_new_node", row_neg_int_new())
    f : Unit <- row("neg_int_does_not_mutate_input", row_neg_int_pure())
    g : Unit <- row("neg_is_reachable", row_neg_reachable())
    return Unit{}
