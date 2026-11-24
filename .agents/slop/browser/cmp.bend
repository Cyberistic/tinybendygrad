# .agents/slop/browser/cmp.bend -- THE KEY EACH CAST RECEIVES, which is the two rows the last note asked
# for in one: `k = rc*65536 + len*4096 + po*64 + tb`, and `len` IS the number of ranges `vms` gave the
# node (it is `List.length(VM.vs(vm))`). So decoding `len` from `k` answers "what did the section say"
# without printing the section. A cast of the outer range must decode `len 2`; a `len 4` means the
# consumer-intersection kept ENDs it should have dropped.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./fchainl.bend as CH

def kg3(+i: U32) -> O.Found:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_low(ar, SCH.sc_src0(ar, kk))

def cgo.go(+ar: O.Arena, +ks: List<&2, LIN.LtKey>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      cgo.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, LIN.LtKey.i(k)), O.OpsCAST{}),
        List.append(&2, String, acc, [String.concat([U32.show(LIN.LtKey.i(k)), "=", U32.show(LIN.LtKey.k(k))])]),
        acc))

def rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  String.join(cgo.go(a, LIN.lt_keys(a, lst, DEV.vms(a, lst)), Nil{}), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["cmp0=", rows(0)]))
