# .agents/slop/browser/rs.bend -- count RESHAPEs in the PRE-APPLY graph. Zero means `mxw_reshape.go`
# never builds one, so `rz_input` returns the buffer and every AFTER's src0 is a 1-D PARAM.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./fchainl.bend as CH

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

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["rs=", row()]))
