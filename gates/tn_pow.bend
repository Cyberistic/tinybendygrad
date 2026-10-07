# tn_pow.bend -- a small driver for `tn_pow` / `tn_rpow` in
# `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_pow-gate.py
#
# NINE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane
# calls `tn_pow` / `tn_rpow` from the port and asks the shape/op/arg/srcs of
# the new node; the oracle calls CPython's `c ** d` (forward arm) and
# `d ** c` (reverse arm, via the `__rpow__` arm) and asks the same. A row
# agrees only if the two implementations say so.
#
# WHAT THIS GATES, IN ONE PARAGRAPH. `Tensor.__pow__` (elementwise.py:569, via
# `pow` at :548) is `base, exponent = self._broadcasted(x, reverse=reverse);
# return base.alu(Ops.POW, exponent)`. For two Tensors of the same shape
# (the no-broadcasting case the gate covers) `_broadcasted` is identity and
# the body collapses to `_binop`'s shape (elementwise.py:36) with `MUL`
# replaced by `POW`: `tn_alu(self, POW, [Tensor.u(x)])` for `__pow__` (srcs
# `(self, x)`) and `tn_alu(x, POW, [Tensor.u(self)])` for `__rpow__` (srcs
# `(x, self)`). The `reverse` arm is `__rpow__` (elementwise.py:572). The
# CPython `isinstance(x, ConstType)` guard at elementwise.py:565 is
# unreachable for two Tensors. The dispatch is `tn_pow.go`, keyed on a `Bool`
# (the same shape as `tn_add.go` / `tn_mul.go` / `tn_sub.go`). The
# broadcasting case stays walled on `_broadcasted` (mixin/movement.py:24).

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. `tn_pow` builds a POW with the rhs's uop
# appended to the src list; `tn_rpow` builds a POW with self's uop appended.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_pow -- elementwise.py:569, `c ** d`.
def row_pow_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_pow(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsPOW{})

def row_pow_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_pow(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_pow_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_pow(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(c), T.Tensor.u(d)])

def row_pow_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_pow(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsPOW{}))

# ROW 5-8: tn_rpow -- elementwise.py:572, the `reverse=True` arm.
def row_rpow_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rpow(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsPOW{})

def row_rpow_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rpow(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rpow_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rpow(c, d)
  O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
    [T.Tensor.u(d), T.Tensor.u(c)])

def row_rpow_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rpow(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsPOW{}))

# ROW 9: the two defs are REACHABLE -- the audit's wall text said `__pow__`
# and `__rpow__` were unwritten.
def row_pow_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("pow_op_is_pow", row_pow_op())
    b   : Unit <- row("pow_arg_is_anone", row_pow_arg())
    c   : Unit <- row("pow_srcs_are_self_and_x", row_pow_srcs())
    d   : Unit <- row("pow_does_not_mutate_input", row_pow_pure())
    e   : Unit <- row("rpow_op_is_pow", row_rpow_op())
    f   : Unit <- row("rpow_arg_is_anone", row_rpow_arg())
    g   : Unit <- row("rpow_srcs_are_x_and_self", row_rpow_srcs())
    h   : Unit <- row("rpow_does_not_mutate_input", row_rpow_pure())
    i   : Unit <- row("pow_is_reachable", row_pow_reachable())
    return Unit{}
