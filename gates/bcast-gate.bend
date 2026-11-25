# bcast-gate.bend -- THE DRIVER for `_broadcast_to`, the dance `mixin/bcast.bend` hoisted.
#
# The rows are `name=<result op>/<src0 op>/<src0 dims>/<perm>`: the PERMUTE the dance mints,
# the EXPAND under it (CPython's `expand` is `PERMUTE(EXPAND(x')).shape == the NEW dims only --
# measured, and the wrong form here (one EXPAND carrying the FULL target) has `src0 op ==
# EXPAND` and `src0 dims` of `len(dst) + len(src)` dims, which no row below can agree with),
# the EXPAND's own dims, and the PERMUTE's stack values.
#
# THE SOURCE IS A RESHAPE OF A BUFFER so its fold shape is readable without a device, which is
# the same construction the fixture uses (`mxw_reshape.go` wraps `mxw_buf`).
import Base
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/schedule/indexing.bend as IX
import ./../tinybendygrad/schedule/rangeify.bend as RF
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/bcast.bend as BC
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H

def bg.prod.go(+ds: List<&2, U32>, +acc: U32) -> U32:
  match ds:
    case Nil{}: acc
    case d <> t: bg.prod.go(t, U32.mul(acc, d))

def bg.prod(+ds: List<&2, U32>) -> U32: bg.prod.go(ds, 1)

def bg.dims.go(+ds: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ds:
    case Nil{}: String.join(acc, "x")
    case d <> t: bg.dims.go(t, List.append(&2, String, acc, [U32.show(d)]))

def bg.dims(+ar: O.Arena, +u: U32) -> String:
  bg.dims.go(IX.rr_dims(ar, F.Folded.t(F.folded(ar)), u), Nil{})

def bg.sym.of(m: Maybe<&1, O.Sint>) -> String:
  match m:
    case Some{O.SI{+v}}: H.i64_text(v)
    case Some{O.SU{+s}}: U32.show(s)
    case None{}: "?"

def bg.syms.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: String.join(acc, "-")
    case h <> t: bg.syms.go(ar, t, List.append(&2, String, acc, [bg.sym.of(F.sym_dim(ar, h))]))

def bg.stack(+ar: O.Arena, +u: U32) -> String:
  +s1 = O.Arena.src(ar, u, 1)
  bg.syms.go(ar, O.Arena.srcs(ar, s1), Nil{})

# ONE PAIR. `x` is the source TENSOR's node, reshaped to `src`; the dance runs on it.
def bg.pair(name: String, +src: List<&2, U32>, +dst: List<&2, U32>) -> String:
  +b = MX.mxw_buf(O.Arena.empty(), 0, bg.prod(src))
  +x = MX.mxw_reshape(b, src)
  +f = BC.bcast(T.Tensor.ar(x), T.Tensor.u(x), dst)
  +ar = O.Found.ar(f)
  +r = O.Found.i(f)
  +e = O.Arena.src(ar, r, 0)
  String.concat([name, "=", RF.eng_op_name(O.Arena.op(ar, r)), "/",
                 RF.eng_op_name(O.Arena.op(ar, e)), "/", bg.dims(ar, e)])

def bg.rows() -> List<&2, String>:
  [bg.pair("b_rank_up", [3], [2, 3]),
   bg.pair("b_size1", [2, 1], [2, 3]),
   bg.pair("b_both", [1, 1], [2, 3]),
   bg.pair("b_id", [2, 3], [2, 3])]

def bg.dump() -> String: String.join(bg.rows(), "\n")

def main() -> IO(Unit):
  IO.print(bg.dump())
