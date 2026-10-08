# tn_binop_sweep.bend -- ONE ROW PER BINOP, all at DEPTH 1.
#
#   .venv/bin/python gates/tn_binop_sweep-gate.py
#
# A SWEEP, NOT A SAMPLE. `gates/tn_binop_arena-gate.py` varies the DEPTH of `tn_add` and
# nothing else, so a sibling regression in any of the other sixteen would be invisible. Every
# reverse-dispatch binop routes through `tn_binop` -- VERIFIED by reading, `awk` over
# `tinybendygrad/tensor.bend` prints sixteen `.go` bodies plus `tn_max`, and every one of the
# seventeen is a `tn_binop(lhs, rhs, O.OpsX{})` line -- and this gate proves it for each.
#
# THE RIGHT OPERAND IS `3 + 3` IN ITS OWN ARENA AT EVERY ROW, so its index is NOT 0 and an
# un-merged read lands on the slot the node itself takes. Each row asserts TWO facts in one
# name: `src[1]` is the caller's ADD, and `src[1]` is not the node being built. Both facts
# held at depth 0 for every one of these ports, which is why they were green while four of
# them were corrupt.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def lhs() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# THE RIGHT OPERAND AT DEPTH 1, in its own arena. Its op is OpsADD{} so a row can name the
# expected op rather than re-derive the merge -- and OpsADD is not any of the seventeen ops
# under test except `tn_add`, so a row that picked up the wrong node names the wrong op.
def rhs() -> T.Tensor:
  T.tn_add(lhs(), lhs())

# ONE ROW PER BINOP: `src[1]` IS THE CALLER'S NODE AND IS NOT THE NODE BEING BUILT. The
# expected op is a PARAMETER, not a constant, because the two controls below ask the same
# question about a BARE CONST and OpsADD would be the wrong answer for them -- a control that
# is 0 for the wrong reason is not a control.
def sweep(+r: T.Tensor, want: O.Op) -> Bool:
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.and(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), want),
    Bool.not(U32.is_eq(O.Arena.src(ar, i, 1), i)))


def tn_add.sweep() -> Bool:
  sweep(T.tn_add(lhs(), rhs()), O.OpsADD{})


def tn_and.sweep() -> Bool:
  sweep(T.tn_and(lhs(), rhs()), O.OpsADD{})


def tn_cmplt.sweep() -> Bool:
  sweep(T.tn_cmplt(lhs(), rhs()), O.OpsADD{})


def tn_cmpne.sweep() -> Bool:
  sweep(T.tn_cmpne(lhs(), rhs()), O.OpsADD{})


def tn_fdiv.sweep() -> Bool:
  sweep(T.tn_fdiv(lhs(), rhs()), O.OpsADD{})


def tn_lshift.sweep() -> Bool:
  sweep(T.tn_lshift(lhs(), rhs()), O.OpsADD{})


def tn_max.sweep() -> Bool:
  sweep(T.tn_max(lhs(), rhs()), O.OpsADD{})


def tn_maximum.sweep() -> Bool:
  sweep(T.tn_maximum(lhs(), rhs()), O.OpsADD{})


def tn_mod.sweep() -> Bool:
  sweep(T.tn_mod(lhs(), rhs()), O.OpsADD{})


def tn_mul.sweep() -> Bool:
  sweep(T.tn_mul(lhs(), rhs()), O.OpsADD{})


def tn_or.sweep() -> Bool:
  sweep(T.tn_or(lhs(), rhs()), O.OpsADD{})


def tn_pow.sweep() -> Bool:
  sweep(T.tn_pow(lhs(), rhs()), O.OpsADD{})


def tn_rshift.sweep() -> Bool:
  sweep(T.tn_rshift(lhs(), rhs()), O.OpsADD{})


def tn_shl.sweep() -> Bool:
  sweep(T.tn_shl(lhs(), rhs()), O.OpsADD{})


def tn_shr.sweep() -> Bool:
  sweep(T.tn_shr(lhs(), rhs()), O.OpsADD{})


# `tn_sub` IS THE ONE ROW WITH A DIFFERENT SHAPE, and the reason is CPython's: `Tensor.sub`
# (elementwise.py:103) is `a.alu(Ops.ADD, -b)`, so `src[1]` is `MUL(x, -1)` and not `x`. The
# arena question is unchanged -- is `src[1]` the node the caller named and is it not the node
# being built -- so only the expected OP differs.
def tn_sub.sweep() -> Bool:
  sweep(T.tn_sub(lhs(), rhs()), O.OpsMUL{})


def tn_xor.sweep() -> Bool:
  sweep(T.tn_xor(lhs(), rhs()), O.OpsADD{})


# THE CONTROLS. Depth 0 is what every other binop gate in this directory builds, and it is
# what made all seventeen look correct.
def control_depth0() -> Bool:
  sweep(T.tn_add(lhs(), lhs()), O.OpsCONST{})

def control_same_tensor() -> Bool:
  sweep(T.tn_mul(lhs(), lhs()), O.OpsCONST{})

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("tn_add_src1_is_the_callers_operand", tn_add.sweep())
    b : Unit <- row("tn_and_src1_is_the_callers_operand", tn_and.sweep())
    c : Unit <- row("tn_cmplt_src1_is_the_callers_operand", tn_cmplt.sweep())
    d : Unit <- row("tn_cmpne_src1_is_the_callers_operand", tn_cmpne.sweep())
    e : Unit <- row("tn_fdiv_src1_is_the_callers_operand", tn_fdiv.sweep())
    f : Unit <- row("tn_lshift_src1_is_the_callers_operand", tn_lshift.sweep())
    g : Unit <- row("tn_max_src1_is_the_callers_operand", tn_max.sweep())
    h : Unit <- row("tn_maximum_src1_is_the_callers_operand", tn_maximum.sweep())
    i : Unit <- row("tn_mod_src1_is_the_callers_operand", tn_mod.sweep())
    j : Unit <- row("tn_mul_src1_is_the_callers_operand", tn_mul.sweep())
    k : Unit <- row("tn_or_src1_is_the_callers_operand", tn_or.sweep())
    l : Unit <- row("tn_pow_src1_is_the_callers_operand", tn_pow.sweep())
    m : Unit <- row("tn_rshift_src1_is_the_callers_operand", tn_rshift.sweep())
    n : Unit <- row("tn_shl_src1_is_the_callers_operand", tn_shl.sweep())
    o : Unit <- row("tn_shr_src1_is_the_callers_operand", tn_shr.sweep())
    p : Unit <- row("tn_sub_src1_is_the_callers_operand", tn_sub.sweep())
    q : Unit <- row("tn_xor_src1_is_the_callers_operand", tn_xor.sweep())
    r : Unit <- row("control_depth0", control_depth0())
    s : Unit <- row("control_same_tensor", control_same_tensor())
    return Unit{}
