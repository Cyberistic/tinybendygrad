# probe3.bend -- ISOLATE THE keepdim GAP, IN ONE ARENA.
#
# THE FIRST TWO VERSIONS OF THIS FILE WERE WRONG INSTRUMENTS, NOT RESULTS, and both for
# the same reason: `base243()`, `keep241()` and `red_over_reshape()` each started from
# `O.Arena.empty()`, so the RESHAPE was built in `keep241`'s arena while its src was an
# index minted in a SIBLING one, and the fold cannot resolve that. `tensor.bend`'s own
# rule ("an index is legal only in an arena DESCENDING FROM the one that minted it") and
# `O.Arena.merge` are the two ways out; EVERYTHING IS BUILT IN ONE ARENA HERE, which is
# `graphcmp.bend`'s `matmul_of(+ar: O.Arena)` shape.
#
# THREE CASES, ALL OVER THE SAME `(2,4,3)` BUFFER:
#   reduce axis 0  keepdim target (1,4,3)  products 12 vs 12  REDUCE src is a RESHAPE  CONTROL
#   reduce axis 0  keepdim target (2,4,1)  products 12 vs  8  REDUCE src is a RESHAPE  products differ
#   reduce axis 2  keepdim target (2,4,1)  products  8 vs  8  REDUCE src is a PERMUTE  the candidate's case
# If the CONTROL reads and the third does not, the arm is refused on the PERMUTE UNDER THE
# REDUCE and not on the product arithmetic.
import Base
import ./tinybendygrad/helpers.bend as H
import ./tinybendygrad/LAWS/spec.bend as S
import ./tinybendygrad/uop/ops.bend as O
import ./tinybendygrad/uop/fold.bend as F
import ./tinybendygrad/tensor.bend as T
import ./tinybendygrad/mixin/op.bend as M

def base243(+ar: O.Arena) -> O.Found:
  +b = O.UOp.new.param(ar, O.OpsBUFFER{}, Some{24},
    O.AParam{O.ParamArg{0, S.single(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(2)})
  +c4 = O.UOp.const(O.Found.ar(c2), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(s), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(s)], O.ANone{}, O.TNone{})

# `keep(ar, a, b, c)` -- a three-element STACK, which is the `1 if i in axis else s` of
# reduce.py:18 written out; `mo_keep_ds` needs a `T.Tensor` and this file holds a `U32`.
def keep(+ar: O.Arena, a: U32, b: U32, c: U32) -> O.Found:
  +ca = O.UOp.const(ar, O.CInt{H.i64_of_i32(a)})
  +cb = O.UOp.const(O.Found.ar(ca), O.CInt{H.i64_of_i32(b)})
  +cc = O.UOp.const(O.Found.ar(cb), O.CInt{H.i64_of_i32(c)})
  O.UOp.new(O.Found.ar(cc), O.OpsSTACK{}, [O.Found.i(ca), O.Found.i(cb), O.Found.i(cc)], O.ANone{}, O.TNone{})

# AXIS 0. The port's REDUCE drops `num_axes` from the HEAD, so axis 0 needs no PERMUTE.
def case_axis0(a: U32, b: U32, c: U32) -> O.Found:
  +r = base243(O.Arena.empty())
  +red = O.UOp.new(O.Found.ar(r), O.OpsREDUCE{}, [O.Found.i(r)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  +k = keep(O.Found.ar(red), a, b, c)
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(red), O.Found.i(k)], O.ANone{}, O.TNone{})

# AXIS 2. THE ONLY WAY THE PORT CAN REACH IT IS THROUGH A PERMUTE((2,0,1)).
def case_axis2() -> O.Found:
  +r = base243(O.Arena.empty())
  +p = O.UOp.new(O.Found.ar(r), O.OpsPERMUTE{}, [O.Found.i(r)], O.ATuple{[2, 0, 1]}, O.TNone{})
  +red = O.UOp.new(O.Found.ar(p), O.OpsREDUCE{}, [O.Found.i(p)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  +k = keep(O.Found.ar(red), 2, 4, 1)
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(red), O.Found.i(k)], O.ANone{}, O.TNone{})

def sh(nm: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat([nm, " root_shape=[",
    M.mo_shape.go(M.mo_dims(F.folded(O.Found.ar(f)), O.Found.i(f)), ""), "]"]))

def t_control() -> IO(Unit): sh("axis0__target143__prod_12_vs_12", case_axis0(1, 4, 3))
def t_products() -> IO(Unit): sh("axis0__target241__prod_12_vs_8", case_axis0(2, 4, 1))
def t_permute() -> IO(Unit): sh("axis2__target241__prod_8_vs_8", case_axis2())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_control()
    b : Unit <- t_products()
    c : Unit <- t_permute()
    IO.print("done=1")
