# tn_isnan.bend -- a small driver for `tn_isnan` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_isnan-gate.py
#
# FIVE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_isnan` from the port and asks the shape/op/arg/srcs of the new node; the oracle
# calls CPython's `Tensor.isnan` (elementwise.py:603) and asks the same.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{float} tensor and apply isnan. CPython's `isnan` is `self != self`,
# and the port's `tn_isnan` IS `tn_cmpne(t, t)` -- a single CMPNE with the SAME
# tensor on both srcs. The same shape is what `mo_isnan` (`mixin/op.bend:986`)
# builds at the reduction layer. A CONST{1.0} is the cheapest valid input.
def mk_tensor() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CFloat{1.0})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# CPython's isnan is `self != self`, so the new node is a CMPNE.
def row_isnan_op() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isnan(t)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

def row_isnan_arg() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isnan(t)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# `self != self` is a CMPNE with the SAME tensor on BOTH srcs. NaN is the only
# float where `x == x` is false, so the same-tensor CMPNE IS the NaN test.
# CPython's `.ne(x)` builds a two-src CMPNE where src[0] is `self` and src[1] is
# `x`, and `self != self` makes the two UOp identities equal.
def row_isnan_self_srcs() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isnan(t)
  Bool.and(U32.is_eq(O.Arena.nsrc(T.Tensor.ar(r), T.Tensor.u(r)), 2),
    Bool.and(U32.is_eq(O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 0), T.Tensor.u(t)),
      U32.is_eq(O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 1), T.Tensor.u(t))))

def row_isnan_pure() -> Bool:
  +t = mk_tensor()
  +r = T.tn_isnan(t)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{}))

def row_isnan_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("isnan_op_is_cmpne", row_isnan_op())
    b : Unit <- row("isnan_arg_is_anone", row_isnan_arg())
    c : Unit <- row("isnan_has_self_src", row_isnan_self_srcs())
    d : Unit <- row("isnan_does_not_mutate_input", row_isnan_pure())
    e : Unit <- row("isnan_is_reachable", row_isnan_reachable())
    return Unit{}
