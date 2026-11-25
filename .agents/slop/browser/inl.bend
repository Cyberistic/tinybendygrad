# .agents/slop/browser/inl.bend -- ONE CONSTRUCTION, ALL NUMBERS, ONE ARENA.
# Every retracted hypothesis in this file died because two of its numbers came from different constructions.
# This builds the conv->relu prefix of the chain EXACTLY as `fchain_prog` does and prints, from the LAST
# arena only: h1's uop, the relu operand's uop, the relu value's uop, and two levels of the value's src0.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def opd(+a: O.Arena, +n: U32) -> String:
  String.concat([U32.show(n), "=", RF.eng_op_name(O.Arena.op(a, n)), ":",
                 ids(IX.rr_dims(a, F.Folded.t(F.folded(a)), n))])

def s0(+a: O.Arena, +n: U32) -> U32: O.Arena.src0(a, n)
def s00(+a: O.Arena, +n: U32) -> U32: O.Arena.src0(a, O.Arena.src0(a, n))

def chain() -> String:
  +h1 = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(h1), 1, 784, [1, 1, 28, 28])
  +w1 = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +c1 = T.tn_mul(MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2]), MX.mxw_reshape.go(w1, [1, 1, 1, 2, 1, 2]))
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +a1 = RZ.rz_after(h1, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  +h2 = RZ.rz_input(O.Found.ar(a1), 3, 196, [1, 1, 14, 14])
  +v1 = MX.mxw_reshape(T.tn_new(T.Tensor.ar(h2), O.Found.i(a1)), [1, 1, 14, 14])
  +rl = T.tn_relu(v1)
  +a = T.Tensor.ar(rl)
  String.concat(["h1=", opd(a, T.Tensor.u(h1)),
                 " | a1=", opd(a, O.Found.i(a1)),
                 " | v1=", opd(a, T.Tensor.u(v1)),
                 " | relu=", opd(a, T.Tensor.u(rl)),
                 " | relu.s0=", opd(a, s0(a, T.Tensor.u(rl))),
                 " | relu.s00=", opd(a, s00(a, T.Tensor.u(rl)))])

def prog() -> RZ.RZProg:
  +h1 = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(h1), 1, 784, [1, 1, 28, 28])
  +w1 = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +c1 = T.tn_mul(MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2]), MX.mxw_reshape.go(w1, [1, 1, 1, 2, 1, 2]))
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +a1 = RZ.rz_after(h1, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  +h2 = RZ.rz_input(O.Found.ar(a1), 3, 196, [1, 1, 14, 14])
  +v1 = MX.mxw_reshape(T.tn_new(T.Tensor.ar(h2), O.Found.i(a1)), [1, 1, 14, 14])
  +a2 = RZ.rz_after(h2, T.tn_relu(v1))
  +snk = O.UOp.sink(O.Found.ar(a2), [O.Found.i(a1), O.Found.i(a2)])
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def whr.go(+a: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      whr.go(a, tb, t, Bool.pick(List<&2, String>,
        Bool.or(O.eq_op(O.Arena.op(a, n), O.OpsWHERE{}), O.eq_op(O.Arena.op(a, n), O.OpsAFTER{})),
        List.append(&2, String, acc,
          [String.concat([RF.eng_op_name(O.Arena.op(a, n)), " ", opd(a, n),
                          " s0=", opd(a, s0(a, n)), " s00=", opd(a, s00(a, n))])]),
        acc))

def rebuilt() -> String:
  +q = RZ.rz_rebuild(prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +tb = F.Folded.t(F.folded(a))
  String.join(whr.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, RZ.RZProg.sink(q)), Nil{}), " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["inl=", chain()]))
    IO.print(String.concat(["reb=", rebuilt()]))
