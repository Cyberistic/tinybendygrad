# tn_nary_arena.bend -- THE DEPTH GATE for the THREE-operand node.
#
#   .venv/bin/python gates/tn_nary_arena-gate.py
#
# TWELVE ROWS, THREE LANES. `tn_binop` (gates/tn_binop_arena.bend) covers the two-operand
# node. `OpsWHERE` has THREE operands that may live in three unrelated arenas, and that is a
# shape `tn_binop` cannot reach -- so it gets its own gate, built the same way: vary the
# DEPTH of each operand in its own arena and ask whether `src[k]` names the node the CALLER
# passed.
#
# WHY IT EXISTS. `tn_where` was `tn_alu(cond, WHERE, [Tensor.u(x), Tensor.u(y)])`, which read
# `x.u` and `y.u` in `cond.ar`. MEASURED with `y` at depth 1 in its own arena:
# `3 Ops.WHERE/3 Ops.CONST Ops.CONST Ops.NOOP` -- `src[2]` was the bottom. The one-line shape
# only passed at depth 0, where `y.u` happened to be a legal index in `cond.ar`. `tn_threefry`
# had the same defect with two operands and is fixed the same way.
#
# THE ROWS COMPARE `Op`, NOT INDICES, because comparing indices is the coincidence this gate
# family exists to expose: at depth 1 the caller's index and the index the node lands on can
# be the same number over different nodes.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def t_true() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def t_false() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{False{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# A derived operand: one step in its OWN arena, so its index is not 0. `tn_add` and not
# `tn_neg` -- `tn_neg` on a BOOL takes `tn_logical_not`'s arm and builds CMPNE, which would
# make the expected op ambiguous between "derived" and "negated".
def d0() -> T.Tensor: t_false()
def d1() -> T.Tensor: T.tn_add(t_false(), t_false())

# `src[k]` IS THE NODE THE CALLER PASSED AS OPERAND k. Each row names the EXPECTED OP rather
# than re-deriving the merge, and the operands are deliberately not all the same op --
# `CBool{True}` and `CBool{False}` are both CONST and a DERIVED operand is ADD -- so a row
# that picked up the wrong operand names the wrong op. `Ops.NOOP` is what an out-of-range
# read answers, and the `no_src_is_noop` rows say so on their own.
#
# THE ARENA AND THE INDEX ARE BOUND LOCALLY IN EVERY ROW rather than passed to a helper.
# That is not a style choice: bend reads a call's arguments LEFT TO RIGHT and consumes each
# once, so `O.Arena.op(ar, O.Arena.src(ar, i, k))` reads `ar` twice and is REFUSED with
# `ar (consumed more than once)`. MEASURED. `+ar` and `+i` in the row body sidestep it.
def src0_is_cond_d1() -> Bool:
  +r = T.tn_where(t_true(), t_false(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.OpsCONST{})

def src1_is_x_d1() -> Bool:
  +r = T.tn_where(t_true(), t_false(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{})

def src2_is_y_d1() -> Bool:
  +r = T.tn_where(t_true(), t_false(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 2)), O.OpsADD{})

def src0_is_cond_d0() -> Bool:
  +r = T.tn_where(t_true(), d0(), d0())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.OpsCONST{})

def src1_is_x_d0() -> Bool:
  +r = T.tn_where(t_true(), d0(), d0())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsCONST{})

def src2_is_y_d0() -> Bool:
  +r = T.tn_where(t_true(), d0(), d0())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 2)), O.OpsCONST{})

# ALL THREE AT DEPTH 1, which is the case no bare-const driver ever built.
def all_depth1() -> Bool:
  +r = T.tn_where(T.tn_add(t_true(), t_true()), T.tn_add(t_false(), t_false()),
    T.tn_add(t_false(), t_false()))
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.and(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.OpsADD{}),
    Bool.and(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsADD{}),
      O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 2)), O.OpsADD{})))

# NO SRC IS THE BOTTOM, at either depth.
def no_src_is_noop_d1() -> Bool:
  +r = T.tn_where(t_true(), t_false(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.not(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 2)), O.OpsNOOP{}))

def no_src_is_noop_d0() -> Bool:
  +r = T.tn_where(t_true(), t_false(), d0())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.not(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 2)), O.OpsNOOP{}))

# `tn_threefry` HAS TWO OPERANDS and the same defect, so it is measured here rather than in a
# gate of its own: at depth 1 its `src[1]` was the bottom.
def threefry_src1_is_mul_d1() -> Bool:
  +r = T.tn_threefry(t_true(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsADD{})

def threefry_src0_is_const_d1() -> Bool:
  +r = T.tn_threefry(t_true(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 0)), O.OpsCONST{})

def threefry_no_src_is_noop_d1() -> Bool:
  +r = T.tn_threefry(t_true(), d1())
  +ar = T.Tensor.ar(r)
  +i = T.Tensor.u(r)
  Bool.not(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, i, 1)), O.OpsNOOP{}))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("where_src0_is_caller_at_d1", src0_is_cond_d1())
    b : Unit <- row("where_src1_is_caller_at_d1", src1_is_x_d1())
    c : Unit <- row("where_src2_is_caller_at_d1", src2_is_y_d1())
    d : Unit <- row("where_src0_is_caller_at_d0", src0_is_cond_d0())
    e : Unit <- row("where_src1_is_caller_at_d0", src1_is_x_d0())
    f : Unit <- row("where_src2_is_caller_at_d0", src2_is_y_d0())
    g : Unit <- row("where_all_three_at_depth1", all_depth1())
    h : Unit <- row("where_no_src_is_noop_at_d1", no_src_is_noop_d1())
    i : Unit <- row("where_no_src_is_noop_at_d0", no_src_is_noop_d0())
    j : Unit <- row("threefry_src1_is_caller_at_d1", threefry_src1_is_mul_d1())
    k : Unit <- row("threefry_src0_is_caller_at_d1", threefry_src0_is_const_d1())
    l : Unit <- row("threefry_no_src_is_noop_at_d1", threefry_no_src_is_noop_d1())
    return Unit{}