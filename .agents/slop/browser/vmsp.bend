# .agents/slop/browser/vmsp.bend -- THE ENDS OF KERNEL 3, with the EXTENT of each range they close.
# `rr_ap_end_src` decides which ranges an END closes; if the STORE's END (the one whose toposort reaches
# both ENDs) closes the 49-range, the nest is `49 > 10` and the renderer and the linearizer are both
# innocent -- the store is inside the reduce loop and outside the output loop, which is why it cannot see
# `cast1`.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./fchainl.bend as CH
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN

def kg3(+i: U32) -> O.Found:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_low(ar, SCH.sc_src0(ar, kk))

def nends.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t: nends.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, n), O.OpsEND{}), U32.add(acc, 1), acc))

def nends(+ar: O.Arena, +n: U32) -> U32:
  nends.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, n), 0)

def xs.go(+ar: O.Arena, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: xs.go(ar, t, List.append(&2, String, acc,
      [String.concat([U32.show(r), "@", U32.show(DEV.rg_ext(ar, r))])]))

def ends.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      ends.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsEND{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":ends=", U32.show(nends(ar, n)), ",closed=",
                          String.join(xs.go(ar, O.Arena.src_from(ar, n, 1), Nil{}), ",")])]),
        acc))

def rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  String.join(ends.go(a, O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l)), Nil{}), " ")

def tbgo.go(+ar: O.Arena, +ns: List<&2, U32>, +lst: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      tbgo.go(ar, t, lst, Bool.pick(List<&2, String>,
        O.eq_op(O.Arena.op(ar, n), O.OpsRANGE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":", U32.show(DEV.rg_ext(ar, n)), ":tb=", U32.show(LIN.lt_tb(ar, n, lst)),
                          ":k=", U32.show(LIN.lt_key(1, 1, 25, LIN.lt_tb(ar, n, lst)))])]),
        acc))

def tbs(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  String.join(tbgo.go(a, lst, lst, Nil{}), " ")

def knames.go(+ks: List<&2, C.KU>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: knames.go(t, List.append(&2, String, acc, [RF.eng_op_name(C.KU.op(k))]))

def ku2(p: (O.Arena & List<&2, C.KU>)) -> String:
  (+a, +ks) = p
  String.join(knames.go(ks, Nil{}), ",")

def ku_row(+i: U32) -> String:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  ku2(DEV.body_kus(ar, kk))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["e3=", rows(3)]))
    _ : Unit <- IO.print(String.concat(["tb3=", tbs(3)]))
    IO.print(String.concat(["ku3=", ku_row(3)]))
