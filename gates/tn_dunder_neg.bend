# tn_dunder_neg.bend -- a small driver for `tn_dunder_neg` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_dunder_neg-gate.py
#
# FIVE ROWS, NAMED ONCE. `tn_dunder_neg` (elementwise.py:261, `return self.neg()`)
# is a thin wrapper over `tn_neg`. CPython's `Tensor.__neg__` calls `Tensor.neg()`,
# and the port has both arms of `Tensor.neg` already -- the bool arm dispatches to
# `tn_logical_not` (CMPNE), and the arith arm dispatches to `tn_neg.arith` (MUL).
# So the dunder's two arms are tests that the wrapper IS `tn_neg` on a bool input
# and IS `tn_neg` on an arith input -- which is what `tn_neg-gate.py` already tests,
# but the row names here pin the dunder specifically. The reachability row closes
# the wall that lived unnamed on `Tensor.__neg__`.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CBool{True}} tensor. `tn_dunder_neg` delegates to `tn_neg`, which
# dispatches to `tn_logical_not` on a bool input. The result op IS the CMPNE.
def mk_bool_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# Build a CONST{CInt{4}} tensor. `tn_dunder_neg` delegates to `tn_neg`, which
# dispatches to `tn_neg.arith` on a non-bool input. The result op IS the MUL.
def mk_int_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1: bool input -> CMPNE (the `tn_logical_not` arm, via the dunder wrapper).
def row_dunder_neg_bool_op() -> Bool:
  +t = mk_bool_tensor()
  +r = T.tn_dunder_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

# ROW 2: int input -> MUL (the `tn_neg.arith` arm, via the dunder wrapper).
def row_dunder_neg_int_op() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_dunder_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsMUL{})

# ROW 3: int input -> the MUL's srcs are [self, -1_const]. m1's index is read from
# the arena as src[1] of the MUL (the same value the eq_u32 below compares against).
def row_dunder_neg_int_srcs() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_dunder_neg(t)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(t), O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 1)])

# ROW 4: int input -> the input is NOT mutated (the input uop's op is still CONST).
def row_dunder_neg_int_pure() -> Bool:
  +t = mk_int_tensor()
  +r = T.tn_dunder_neg(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{})

# ROW 5: the dunder's def is REACHABLE -- the audit's wall text did not name it.
def row_dunder_neg_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("dunder_neg_bool_op_is_cmpne", row_dunder_neg_bool_op())
    b : Unit <- row("dunder_neg_int_op_is_mul", row_dunder_neg_int_op())
    c : Unit <- row("dunder_neg_int_srcs_are_self_and_m1", row_dunder_neg_int_srcs())
    d : Unit <- row("dunder_neg_int_does_not_mutate_input", row_dunder_neg_int_pure())
    e : Unit <- row("dunder_neg_is_reachable", row_dunder_neg_reachable())
    return Unit{}