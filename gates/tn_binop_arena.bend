# tn_binop_arena.bend -- THE DEPTH GATE for the arena rule `tn_binop` states.
#
#   .venv/bin/python gates/tn_binop_arena-gate.py
#
# NINE ROWS, THREE LANES. This gate asks ONE question of `tn_add`: does `src[1]` name the
# operand the CALLER passed, when that operand sits at depth N in its own arena?
#
# WHY IT EXISTS. The 18 reverse-dispatch binops build with `tn_alu(lhs, OP, [rhs.u])`, which
# builds in `lhs.ar` and reads `rhs.u` THERE. Every other binop gate in this directory makes
# both operands bare consts from `O.Arena.empty()`, so both land at index 0 and the read is
# right BY COINCIDENCE -- `0` is a legal index in `lhs.ar`. MEASURED over `gates/*.bend`:
# 30 call sites pass two operands and every one is a two-bare-const pair, depth 0.
#
# `src1_is_caller_operand` IS THE ROW THAT IS NOT A CHANGE-DETECTOR: it is the only row
# in the binop gate family that asks whether the operand IDENTITY survived. It answered 0 at
# depths 1 and 2 while every other row in this directory answered 1, which is the whole
# reason it exists; it answers 1 at every depth now that the merge re-mints the index.
#
# THE WALL IS CLOSED, AND THE CLOSURE IS VISIBLE IN THESE ROWS RATHER THAN IN A CLAIM.
# They used to read `src1_is_caller_operand_at1=0` and `src1_is_caller_operand_at2=0` with
# `src1_op_is_noop_at2=1` -- the sibling-arena corruption, pinned on both sides. `O.Arena.merge`
# (`ops.bend`, beside `UOp.new`) re-interns the right operand's arena into the left one's and
# re-mints its index, so all three now answer what CPython answers and the `diverges` this
# gate used to declare are GONE. A divergence list that is EMPTIED by a fix is the only kind
# of divergence list worth having.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def const_at(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# rhs at depth 0: a bare const. `Tensor.u(rhs)` is 0.
def d0() -> T.Tensor: const_at(5)
# rhs at depth 1: one `tn_neg` in its own arena, so `Tensor.u(rhs)` is 1.
def d1() -> T.Tensor: T.tn_neg(const_at(5))
# rhs at depth 2: two `tn_neg`s, so `Tensor.u(rhs)` is 2 -- out of range for `lhs.ar`.
def d2() -> T.Tensor: T.tn_neg(T.tn_neg(const_at(5)))

# THE IDENTITY ROW, one per depth, AND IT MUST COMPARE OPS NOT INDICES. Comparing indices
# is the trap this gate exists to expose: at depth 1 `Tensor.u(rhs)` is 1 and
# `Arena.src(ar, i, 1)` is ALSO 1 -- the ADD's own slot -- so an index comparison answers 1
# at every depth while the graph is corrupt. MEASURED. The node is what has to match.
def src1_is_caller_operand.at0() -> Bool:
  +c = const_at(3)
  +d = d0()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.Arena.op(T.Tensor.ar(d), T.Tensor.u(d)))

def src1_is_caller_operand.at1() -> Bool:
  +c = const_at(3)
  +d = d1()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.Arena.op(T.Tensor.ar(d), T.Tensor.u(d)))

def src1_is_caller_operand.at2() -> Bool:
  +c = const_at(3)
  +d = d2()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.Arena.op(T.Tensor.ar(d), T.Tensor.u(d)))

# THE OP ROWS, which say WHAT src[1] actually is. Depth 0 is a CONST, depth 1 is the ADD
# itself, depth 2 is the NOOP bottom. CPython answers CONST, MUL, MUL on the same three.
def src1_op_is_const.at0() -> Bool:
  +c = const_at(3)
  +d = d0()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{})

def src1_op_is_the_add.at1() -> Bool:
  +c = const_at(3)
  +d = d1()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  U32.is_eq(O.Arena.src(ar, i, 1), i)

def src1_op_is_noop.at2() -> Bool:
  +c = const_at(3)
  +d = d2()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsNOOP{})

# src[0] IS ALWAYS RIGHT, at every depth: `lhs.u` is 0 and `tn_alu` prepends it into the
# node it builds in `lhs.ar`. These three rows say so, so the gate is not read as "tn_add is
# broken" -- it is "tn_add reads `rhs.u` in the wrong arena".
def src0_is_caller_lhs.at0() -> Bool:
  +c = const_at(3)
  +d = d0()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)))

def src0_is_caller_lhs.at1() -> Bool:
  +c = const_at(3)
  +d = d1()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)))

def src0_is_caller_lhs.at2() -> Bool:
  +c = const_at(3)
  +d = d2()
  +r = T.tn_add(c, d)
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("src1_is_caller_operand_at0", src1_is_caller_operand.at0())
    b : Unit <- row("src1_is_caller_operand_at1", src1_is_caller_operand.at1())
    c : Unit <- row("src1_is_caller_operand_at2", src1_is_caller_operand.at2())
    d : Unit <- row("src1_op_is_const_at0", src1_op_is_const.at0())
    e : Unit <- row("src1_op_is_noop_at2", src1_op_is_noop.at2())
    f : Unit <- row("src0_is_caller_lhs_at0", src0_is_caller_lhs.at0())
    g : Unit <- row("src0_is_caller_lhs_at1", src0_is_caller_lhs.at1())
    h : Unit <- row("src0_is_caller_lhs_at2", src0_is_caller_lhs.at2())
    return Unit{}