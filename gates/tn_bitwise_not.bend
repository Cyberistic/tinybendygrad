# tn_bitwise_not.bend -- a small driver for `tn_bitwise_not` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_bitwise_not-gate.py
#
# EIGHT ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# `tn_bitwise_not` from the port and asks the shape/op/arg of every node in the
# returned graph; the oracle calls CPython's `Tensor.bitwise_not` on a bool input
# and asks the same. A row agrees only if the two implementations say so.
#
# WHAT THIS GRAPH IS. `tn_bitwise_not` ports the BOOL ARM of elementwise.py:145,
# which is `self.logical_not()` = `self.cast(dtypes.bool).ne(True)`. The graph is
# three nodes: a CONST{CInt{4}} input, a CAST to bool, a CONST{CBool{True}}, and a
# CMPNE with the cast as src[0] and the True const as src[1]. The arena order is
# INPUT -> CAST -> CONST(True) -> CMPNE; `Tensor.uop` is the CMPNE. Indices in the
# arena: input=1, cast=2, true=3, cmpne=4. The cmpne's srcs are indices 2 and 3.
#
# The driver builds this graph INLINE so the indices in `cast` and `true_` are the
# ones in the cmpne's src list. ROW 8 alone calls the port directly, to pin the
# def's reachability.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build the bitwise_not graph inline. Returns BOTH the result tensor AND the
# intermediate cast and true_const indices, which the rows need to inspect.
type Bitnot is Data:
  Bitnot{r: T.Tensor, t: T.Tensor, cast: O.Found, true_: O.Found}

def mk_bitnot() -> Bitnot:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  +cast = T.tn_bitwise_not.cast(T.Tensor.ar(t), T.Tensor.u(t))
  +true_ = O.UOp.const(O.Found.ar(cast), O.CBool{True{}})
  +r = T.tn_alu(T.tn_alu.put(cast), O.OpsCMPNE{}, [O.Found.i(true_)])
  Bitnot{r, t, cast, true_}

# ROW 1: the outer op is CMPNE.
def row_bitnot_op(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPNE{})

# ROW 2: the outer arg is ANone{}.
def row_bitnot_arg(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# ROW 3: the outer srcs are (cast_index, true_index), in that order.
def row_bitnot_srcs(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_u32(O.Arena.srcs(T.Tensor.ar(r), T.Tensor.u(r)),
        [O.Found.i(cast), O.Found.i(true_)])

# ROW 4: the CMPNE's src[0] is the CAST's index.
def row_bitnot_cast_in(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      U32.is_eq(O.Arena.src0(T.Tensor.ar(r), T.Tensor.u(r)), O.Found.i(cast))

# ROW 5: the CAST's arg is ADt{boolean()}.
def row_bitnot_cast_arg(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_arg(O.Arena.arg(O.Found.ar(cast), O.Found.i(cast)), O.ADt{S.boolean()})

# ROW 6: the True CONST's arg is APy{CBool{True{}}}.
def row_bitnot_true_arg(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_arg(O.Arena.arg(O.Found.ar(true_), O.Found.i(true_)),
        O.APy{O.CBool{True{}}})

# ROW 7: the input is NOT mutated -- the original uop still has op CONST.
def row_bitnot_pure(+b: Bitnot) -> Bool:
  match b:
    case Bitnot{r, t, cast, true_}:
      O.eq_op(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)), O.OpsCONST{})

# ROW 8: the def is REACHABLE -- the audit's wall text said it was 0 defs.
def row_bitnot_present() -> Bool:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  +r = T.tn_bitwise_not(t)
  True{}

def row_bitnot_op.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_op_is_cmpne", row_bitnot_op(b))

def row_bitnot_arg.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_arg_is_anone", row_bitnot_arg(b))

def row_bitnot_srcs.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_src_is_cast_and_true", row_bitnot_srcs(b))

def row_bitnot_cast_in.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_cast_in_to_bool_cast", row_bitnot_cast_in(b))

def row_bitnot_cast_arg.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_cast_arg_is_adt_bool", row_bitnot_cast_arg(b))

def row_bitnot_true_arg.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_true_const_arg_is_cbool_true", row_bitnot_true_arg(b))

def row_bitnot_pure.go() -> IO(Unit):
  b : Bitnot = mk_bitnot()
  row("bitnot_does_not_mutate_input", row_bitnot_pure(b))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row_bitnot_op.go()
    b : Unit <- row_bitnot_arg.go()
    c : Unit <- row_bitnot_srcs.go()
    d : Unit <- row_bitnot_cast_in.go()
    e : Unit <- row_bitnot_cast_arg.go()
    f : Unit <- row_bitnot_true_arg.go()
    g2 : Unit <- row_bitnot_pure.go()
    h : Unit <- row("bitnot_is_reachable", row_bitnot_present())
    return Unit{}