# .agents/slop/browser/linp.bend -- THE LINEARIZED STATEMENT ORDER, with op names, next to the C.
# `body_kus` renders exactly the list `LIN.linearize` returns, so if a CAST appears before its RANGE here
# and after it in the C, the loss is in the renderer; if it appears LATE here, the loss is in `lt_keys`.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./fchainl.bend as CH

def kg3(+i: U32) -> O.Found:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_low(ar, SCH.sc_src0(ar, kk))

def names.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t: names.go(ar, t, List.append(&2, String, acc, [RF.eng_op_name(O.Arena.op(ar, n))]))

def lin_row(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  +lin = LIN.linearize(a, lst, DEV.vms(a, lst), O.Found.i(l))
  String.join(names.go(a, lin, Nil{}), ",")

def knames.go(+ks: List<&2, C.KU>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: knames.go(t, List.append(&2, String, acc, [RF.eng_op_name(C.KU.op(k))]))

def ku_row2(p: (O.Arena & List<&2, C.KU>)) -> String:
  (+a, +ks) = p
  String.join(knames.go(ks, Nil{}), ",")

def ku_row(+i: U32) -> String:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  b = DEV.body_kus(ar, kk)
  ku_row2(b)

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["lin0=", lin_row(0)]))
    IO.print(String.concat(["ku0=", ku_row(0)]))
