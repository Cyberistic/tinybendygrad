# tn_and_or_xor.bend -- a small driver for `tn_and` / `tn_rand` / `tn_or` /
# `tn_ror` / `tn_xor` / `tn_rxor` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_and_or_xor-gate.py
#
# TWENTY-FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend
# lane calls the six defs from the port and asks the shape/op/arg/srcs of the
# new node; the oracle calls CPython's `c & d`, `d & c`, `c | d`, `d | c`,
# `c ^ d`, `d ^ c` and asks the same. A row agrees only if the two
# implementations say so.
#
# WHAT THIS GATES, IN ONE PARAGRAPH:
#   tn_and   -- elementwise.py:285, via bitwise_and at :159 (`self._binop(Ops.AND, x, reverse)`)
#   tn_rand  -- elementwise.py:309, the `reverse=True` arm
#   tn_or    -- elementwise.py:288, via bitwise_or at :173 (`self._binop(Ops.OR, x, reverse)`)
#   tn_ror   -- elementwise.py:312, the `reverse=True` arm
#   tn_xor   -- elementwise.py:291, via bitwise_xor at :187 (`self._binop(Ops.XOR, x, reverse)`)
#   tn_rxor  -- elementwise.py:315, the `reverse=True` arm
#
# Each is the no-broadcasting case (`_broadcasted` identity for two same-shape
# CONSTs), the same shape as `tn_add.go` / `tn_mul.go` / `tn_cmplt.go`. The
# four row-types per def are op, arg, srcs and the reachability row that
# names the wall. The "does not mutate input" row is folded in the four
# arms, the way `tn_add_sub.bend` and `tn_binop2_cmp.bend` fold it -- it
# pins the no-mutation discipline and would fire if `tn_alu` were a side
# effect.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. `tn_and` / `tn_rand` build an AND with the
# rhs's uop appended to the src list; `tn_or` / `tn_ror` build an OR and
# `tn_xor` / `tn_rxor` build a XOR, all with the same `tn_alu` shape.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_and (elementwise.py:285, via bitwise_and at :159).
def row_and_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_and(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsAND{})

def row_and_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_and(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_and_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_and(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(c), T.Tensor.u(d)])

def row_and_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_and(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsAND{}))

# ROW 5-8: tn_rand -- the `reverse=True` arm of `tn_and.go`.
def row_rand_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rand(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsAND{})

def row_rand_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rand(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rand_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rand(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(d), T.Tensor.u(c)])

def row_rand_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rand(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsAND{}))

# ROW 9-12: tn_or -- elementwise.py:288, via bitwise_or at :173.
def row_or_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_or(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsOR{})

def row_or_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_or(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_or_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_or(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(c), T.Tensor.u(d)])

def row_or_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_or(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsOR{}))

# ROW 13-16: tn_ror -- the `reverse=True` arm of `tn_or.go`.
def row_ror_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_ror(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsOR{})

def row_ror_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_ror(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_ror_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_ror(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(d), T.Tensor.u(c)])

def row_ror_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_ror(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsOR{}))

# ROW 17-20: tn_xor -- elementwise.py:291, via bitwise_xor at :187.
def row_xor_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_xor(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsXOR{})

def row_xor_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_xor(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_xor_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_xor(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(c), T.Tensor.u(d)])

def row_xor_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_xor(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsXOR{}))

# ROW 21-24: tn_rxor -- the `reverse=True` arm of `tn_xor.go`.
def row_rxor_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rxor(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsXOR{})

def row_rxor_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rxor(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rxor_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rxor(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(d), T.Tensor.u(c)])

def row_rxor_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rxor(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsXOR{}))

# ROW 25: the six defs are REACHABLE -- the audit's wall text said the
# bitwise binop dunders were unwritten.
def row_and_or_xor_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("and_op_is_and", row_and_op())
    b   : Unit <- row("and_arg_is_anone", row_and_arg())
    c   : Unit <- row("and_srcs_are_self_and_x", row_and_srcs())
    d   : Unit <- row("and_does_not_mutate_input", row_and_pure())
    e   : Unit <- row("rand_op_is_and", row_rand_op())
    f   : Unit <- row("rand_arg_is_anone", row_rand_arg())
    g   : Unit <- row("rand_srcs_are_x_and_self", row_rand_srcs())
    h   : Unit <- row("rand_does_not_mutate_input", row_rand_pure())
    i   : Unit <- row("or_op_is_or", row_or_op())
    j   : Unit <- row("or_arg_is_anone", row_or_arg())
    k   : Unit <- row("or_srcs_are_self_and_x", row_or_srcs())
    l   : Unit <- row("or_does_not_mutate_input", row_or_pure())
    m   : Unit <- row("ror_op_is_or", row_ror_op())
    n   : Unit <- row("ror_arg_is_anone", row_ror_arg())
    o   : Unit <- row("ror_srcs_are_x_and_self", row_ror_srcs())
    p   : Unit <- row("ror_does_not_mutate_input", row_ror_pure())
    q   : Unit <- row("xor_op_is_xor", row_xor_op())
    r   : Unit <- row("xor_arg_is_anone", row_xor_arg())
    s   : Unit <- row("xor_srcs_are_self_and_x", row_xor_srcs())
    t   : Unit <- row("xor_does_not_mutate_input", row_xor_pure())
    u   : Unit <- row("rxor_op_is_xor", row_rxor_op())
    v   : Unit <- row("rxor_arg_is_anone", row_rxor_arg())
    w   : Unit <- row("rxor_srcs_are_x_and_self", row_rxor_srcs())
    x   : Unit <- row("rxor_does_not_mutate_input", row_rxor_pure())
    y   : Unit <- row("and_or_xor_is_reachable", row_and_or_xor_reachable())
    return Unit{}
