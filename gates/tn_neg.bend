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

# ROW 4, REWRITTEN. It USED TO compare `r.srcs` against
# `[T.Tensor.u(t), O.Arena.src(ar, u, 1)]` -- that is, against src[1] ITSELF. The row
# asserted nothing about src[1] and answered 1 over the corrupt graph, while the oracle's
# `r_int.uop.src == (c_int, c_m1)` asserted the truth and also answered 1, so the two lanes
# "agreed" without testing the same property. A tautological row is worse than no row: it
# looks like coverage. This one asks what its NAME claims -- src[0] is `self` and src[1] is
# the `-1` CONST.
def row_neg_int_srcs() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.and(U32.is_eq(O.Arena.src(ar, i, 0), T.Tensor.u(t)),
    O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{}))

# ROW 3: on an int input, `tn_neg` builds a MUL (the `tn_neg.arith` arm).
def row_neg_int_op() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

# ROW 4: the MUL's srcs are [self, -1_const]. m1's index is read from the arena as
# src[1] of the MUL (the same value the eq_u32 below compares against), and the
# whole srcs list must equal [self.u, m1.u].
# ROW 4b: NO SRC IS THE BOTTOM, and NO SRC IS THE MUL ITSELF. `Ops.NOOP` is what an
# out-of-range read answers, so a src that reads NOOP is an index minted in an arena that is
# LONGER than the one the node was built in -- which is exactly the defect this row was
# written for. Before the fix `tn_neg.arith` built its MUL in `Tensor.ar(t)` and read
# `O.Found.i(m1)` there, so src[1] WAS the MUL: `1 Ops.MUL/2 Ops.CONST Ops.MUL`.
def row_neg_int_src1_is_not_self() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_neg(t)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.not(U32.is_eq(O.Arena.src(ar, i, 1), i))

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
    h : Unit <- row("neg_int_src1_is_not_self", row_neg_int_src1_is_not_self())
    e : Unit <- row("neg_int_is_new_node", row_neg_int_new())
    f : Unit <- row("neg_int_does_not_mutate_input", row_neg_int_pure())
    g : Unit <- row("neg_is_reachable", row_neg_reachable())
    return Unit{}
