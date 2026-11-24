# .agents/slop/browser/rs.bend -- count RESHAPEs in the PRE-APPLY graph. Zero means `mxw_reshape.go`
# never builds one, so `rz_input` returns the buffer and every AFTER's src0 is a 1-D PARAM.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./fchainl.bend as CH
import ./../../../tinybendygrad/tensor.bend as T

def nrs.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t: nrs.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, n), O.OpsRESHAPE{}),
                                        U32.add(acc, 1), acc))

def nms.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t: nms.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, n), O.OpsMSTACK{}),
                                        U32.add(acc, 1), acc))

def row() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +ns = O.UOp.toposort(O.Arena.budget(a), a, sink)
  String.concat(["reshape=", U32.show(nrs.go(a, ns, 0)), " mstack=", U32.show(nms.go(a, ns, 0)),
                 " nodes=", U32.show(U32.from_nat(List.length(&2, U32, ns)))])

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def rsr.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      rsr.go(ar, tb, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsRESHAPE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":d=", ids(IX.rr_dims(ar, tb, n)),
                          " s0=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, n)))])]),
        acc))

def shapes() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(a))
  String.join(rsr.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " ")

def s1of(+ar: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(ar, n), 1n), 0)

def aft2.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      aft2.go(ar, tb, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsAFTER{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ": s0=", RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, n))),
                          ":", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, n))),
                          " s1=", RF.eng_op_name(O.Arena.op(ar, s1of(ar, n))),
                          ":", ids(IX.rr_dims(ar, tb, s1of(ar, n))),
                          " eq=", Bool.show(U32.is_eq(O.Arena.src0(ar, n), O.Arena.src0(ar, s1of(ar, n))))])]),
        acc))

def afts() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(a))
  String.join(aft2.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " | ")

def h1row() -> String:
  +h = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +a = T.Tensor.ar(h)
  +tb = F.Folded.t(F.folded(a))
  String.concat(["h1op=", RF.eng_op_name(O.Arena.op(a, T.Tensor.u(h))),
                 " h1dims=", ids(IX.rr_dims(a, tb, T.Tensor.u(h)))])

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["rs=", row()]))
    _ : Unit <- IO.print(String.concat(["shapes=", shapes()]))
    _ : Unit <- IO.print(String.concat(["afts=", afts()]))
    IO.print(h1row())
