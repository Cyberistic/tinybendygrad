# tn_bitwise_not.bend -- a driver for `tn_bitwise_not` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_bitwise_not-gate.py
#
# SEVEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_bitwise_not` from the port and asks the shape/op/arg of every node in the
# returned graph; the oracle calls CPython's `Tensor.bitwise_not` on a bool input
# and asks the same. A row agrees only if the two implementations say so.
#
# THE FIRST VERSION OF THIS DRIVER NEVER CALLED `tn_bitwise_not`. `mk_bitnot` built the
# graph INLINE -- `tn_bitwise_not.cast` then `tn_alu` -- so seven of the eight rows were
# a gate on a raw CAST helper and the ALU builder, and only row 8 reached the def its
# name claims. Its fixture was `CInt{4}`, a SIGNED const, while the rows asserted the
# BOOL arm's shape. So the population was not the subject: the instrument's name and its
# rows disagreed, which is the failure this tree's first doctrine is about.
#
# AND THE ORACLE WAS HAND-BUILT TO MATCH, so both lanes were wrong together and compared
# `1 == 1`. Switching the oracle to the real `Tensor.bitwise_not` is what exposed it:
# on a bool input CPython's `cast(dtypes.bool)` FOLDS (`mixin/dtype.py:36` returns
# `self` when the dtype matches), so CPython's bool arm is `CMPNE(CONST, CONST)` with
# NO CAST -- and the port already agrees, because its bool arm is `tn_logical_not`,
# which goes through the folding `D.cast_at`.
#
# WHAT THIS GRAPH IS. `elementwise.py:156-157` is a THREE-arm dispatch on dtype:
#
#   if self.dtype == dtypes.bool: return self.logical_not()
#   return (self ^ self.dtype.max) if dtypes.is_unsigned(self.dtype) else (self ^ -1)
#
# Rows 1-6 take the FIRST arm on a BOOL fixture. Row 7 is the only one positioned to see
# the third, because every other row is bool-fixture.
#
# THE GRAPH ON A BOOL INPUT IS TWO NODES. Input CONST{CBool{True}}, a second
# CONST{CBool{True}}, and the CMPNE with the two as srcs -- the `cast` folds away, so
# `src[0]` IS the input. Row 4 is that fold, and it is the row that would have caught a
# regression to the raw cast.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# A bool CONST input, and `tn_bitwise_not` applied to it. `Bitnot.reached` is the `Maybe`
# the three-arm dispatch returns: `None` means the fold could not answer the dtype or
# `Dt.max` refused an unsigned, and every row below then reads False.
#
# THERE WAS AN EIGHTH ROW, `bitnot_bool_arm_is_reached`, AND IT WAS DROPPED RATHER THAN PINNED.
# It asked whether the dispatch returns `Some`, which is a fact about the PORT's `Maybe`
# return type and has NO CPython counterpart -- so the oracle side of it could only be a
# constant, and a row whose oracle is a constant is the same defect one row down. `None` is
# still a FAIL in every remaining row, which is what that row was for.
type Bitnot is Data:
  Bitnot{reached: Maybe<&2, T.Tensor>, t: T.Tensor}

def mk_bitnot() -> Bitnot:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  Bitnot{T.tn_bitwise_not(t), t}

def bnot(+r: T.Tensor) -> Bool:
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

# ROW 1: the outer op is CMPNE.
def row_op(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}:
      match m:
        case Some{+r}: bnot(r)
        case None{}: False{}

# ROW 2: the outer arg is ANone{}, because `ne` passes no arg.
def row_arg(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}:
      match m:
        case Some{+r}: O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})
        case None{}: False{}

def src1_is_true_const(+r: T.Tensor) -> Bool:
  +ar = T.Tensor.ar(r)
  O.eq_arg(O.Arena.arg(ar, O.Arena.src(ar, T.Tensor.u(r), 1)), O.APy{O.CBool{True{}}})

# ROW 3: the srcs are the INPUT and the True CONST.
def row_srcs(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}:
      match m:
        case Some{+r}: src1_is_true_const(r)
        case None{}: False{}

# ROW 4: THE IDENTITY CAST FOLDED. `src[0]` IS the input uop, so `cast(dtypes.bool)`
# minted nothing -- the port reaches the folding `D.cast_at` (`mixin/dtype.bend:342`),
# which is the fix this row exists to keep.
def row_cast_folded(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}:
      match m:
        case Some{+r}: U32.is_eq(O.Arena.src0(T.Tensor.ar(r), T.Tensor.u(r)), T.Tensor.u(t))
        case None{}: False{}

def row_input_is_bool.go(dt: Maybe<&2, S.Dt>) -> Bool:
  match dt:
    case Some{+d}: S.Dt.is_bool(d)
    case None{}: False{}

# ROW 5: the fold's PRECONDITION -- the input really is bool. Without this, row 5 would
# pass for the wrong reason (a non-bool input folds to nothing only by coincidence).
# `.go` exists because `match` cannot scrutinise a computed value.
def row_input_is_bool(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}: row_input_is_bool.go(T.tn_dtype(t))

# ROW 6: the input is NOT mutated -- it still has op CONST.
def row_pure(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{m, t}: O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{})

# ROW 7: THE THIRD ARM. `CInt{4}` is weakint and SIGNED, so CPython takes `self ^ -1`
# (`elementwise.py:157`) and the top op must be XOR, not CMPNE. This is the only row on a
# non-bool fixture; `None` is `Dt.max`'s refusal and is a FAIL, not a skip.
def row_signed_xor.go(m: Maybe<&2, T.Tensor>) -> Bool:
  match m:
    case Some{+t}: O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsXOR{})
    case None{}: False{}

def row_signed_xor() -> Bool:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  row_signed_xor.go(T.tn_bitwise_not(t))

# EACH ROW BUILDS ITS OWN FIXTURE. `bend`'s `let` is AFFINE, so a `Bitnot` consumed by one
# row cannot be handed to a second; the six bool rows each call `mk_bitnot()`.
def row_op.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_op_is_cmpne", row_op(b))

def row_arg.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_arg_is_anone", row_arg(b))

def row_srcs.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_srcs_are_input_and_true", row_srcs(b))

def row_cast_folded.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_identity_cast_folded", row_cast_folded(b))

def row_is_bool.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_input_is_bool", row_input_is_bool(b))

def row_pure.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_does_not_mutate_input", row_pure(b))

def main() -> IO(Unit):
  do IO<Unit>:
    a1 : Unit <- row_op.go()
    a2 : Unit <- row_arg.go()
    a3 : Unit <- row_srcs.go()
    a4 : Unit <- row_cast_folded.go()
    a5 : Unit <- row_is_bool.go()
    a6 : Unit <- row_pure.go()
    a7 : Unit <- row("bitnot_signed_takes_xor_arm", row_signed_xor())
    return Unit{}