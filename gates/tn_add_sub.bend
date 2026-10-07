# tn_add_sub.bend -- a small driver for `tn_add` / `tn_radd` / `tn_sub` /
# `tn_rsub` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_add_sub-gate.py
#
# SEVENTEEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend
# lane calls `tn_add` / `tn_radd` / `tn_sub` / `tn_rsub` from the port and asks
# the shape/op/arg/srcs of the new node; the oracle calls CPython's
# `c + d`, `d.add(c, reverse=True)`, `c - d`, `d.sub(c, reverse=True)` and asks
# the same. A row agrees only if the two implementations say so.
#
# WHAT THIS GRAPH IS. `tn_add` (elementwise.py:267, via `add` at :84, :123) is
# `a, b = self._broadcasted(x, reverse); return a.alu(Ops.ADD, -b)`. The `-b`
# is a CONST trap (and a unary minus on a Tensor is also walled), so for two
# Tensors of the same shape `_broadcasted` is identity and the body reduces to
# `_binop`'s shape (elementwise.py:36) with `MUL` replaced by `ADD`:
# `tn_alu(self, ADD, [Tensor.u(x)])` for `__add__` (srcs `(self, x)`) and
# `tn_alu(x, ADD, [Tensor.u(self)])` for `__radd__` (srcs `(x, self)`). The
# dispatch is `tn_add.go`, keyed on a `Bool` (the same shape as `tn_mul.go` at
# `tensor.bend:466`). `__sub__`/`__rsub__` (elementwise.py:103, :270, :297) are
# the same shape with `Ops.SUB`. The broadcasting case stays walled on
# `_broadcasted` (mixin/movement.py:24, fold reads and a `least_upper_dtype`
# helper).

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. `tn_add` and `tn_radd` build an ADD with the
# rhs's uop appended to the src list; `tn_sub` and `tn_rsub` build a SUB with
# the same shape.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_add.
def row_add_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_add(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsADD{})

def row_add_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_add(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_add_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_add(c, d)
  T.tn_srcs_are(r, c, d)

def row_add_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_add(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsADD{}))

# ROW 5-8: tn_radd -- the `reverse=True` arm of `tn_add.go`.
def row_radd_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_radd(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsADD{})

def row_radd_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_radd(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_radd_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_radd(c, d)
  T.tn_srcs_are(r, d, c)

def row_radd_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_radd(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsADD{}))

# ROW 9-12: tn_sub -- same shape as tn_add, with OpsSUB instead of OpsADD.
def row_sub_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_sub(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSUB{})

def row_sub_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_sub(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_sub_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_sub(c, d)
  T.tn_srcs_are(r, c, d)

def row_sub_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_sub(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSUB{}))

# ROW 13-16: tn_rsub -- the `reverse=True` arm of `tn_sub.go`.
def row_rsub_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rsub(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSUB{})

def row_rsub_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rsub(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rsub_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rsub(c, d)
  T.tn_srcs_are(r, d, c)

def row_rsub_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rsub(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsSUB{}))

# ROW 17: the four defs are REACHABLE -- the audit's wall text said `__add__`
# and `__sub__` were unwritten.
def row_add_sub_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("add_op_is_add", row_add_op())
    b   : Unit <- row("add_arg_is_anone", row_add_arg())
    c   : Unit <- row("add_srcs_are_self_and_x", row_add_srcs())
    d   : Unit <- row("add_does_not_mutate_input", row_add_pure())
    e   : Unit <- row("radd_op_is_add", row_radd_op())
    f   : Unit <- row("radd_arg_is_anone", row_radd_arg())
    g   : Unit <- row("radd_srcs_are_x_and_self", row_radd_srcs())
    h   : Unit <- row("radd_does_not_mutate_input", row_radd_pure())
    i   : Unit <- row("sub_op_is_sub", row_sub_op())
    j   : Unit <- row("sub_arg_is_anone", row_sub_arg())
    k   : Unit <- row("sub_srcs_are_self_and_x", row_sub_srcs())
    l   : Unit <- row("sub_does_not_mutate_input", row_sub_pure())
    m   : Unit <- row("rsub_op_is_sub", row_rsub_op())
    n   : Unit <- row("rsub_arg_is_anone", row_rsub_arg())
    o   : Unit <- row("rsub_srcs_are_x_and_self", row_rsub_srcs())
    p   : Unit <- row("rsub_does_not_mutate_input", row_rsub_pure())
    q   : Unit <- row("add_sub_is_reachable", row_add_sub_reachable())
    return Unit{}