# .agents/slop/browser/vmsp.bend -- WHAT THE LINEARIZER IS KEYED ON, for kernel 0.
# `vmsp` is the `vms` input (one length-prefixed section per node, the RANGE extents minus one) and
# `keys` is `LtKey.k` for every RANGE: `rc` must RISE with nesting so the outer loop sorts first.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./fchainl.bend as CH

def kg3(+i: U32) -> O.Found:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_low(ar, SCH.sc_src0(ar, kk))

def nums.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: nums.go(t, List.append(&2, String, acc, [U32.show(x)]))

def vm_rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  String.join(nums.go(DEV.vms(a, lst), Nil{}), " ")

def keys.go(+ar: O.Arena, +ks: List<&2, LIN.LtKey>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      keys.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, LIN.LtKey.i(k)), O.OpsRANGE{}),
        List.append(&2, String, acc, [String.concat([U32.show(LIN.LtKey.i(k)), ":", U32.show(LIN.LtKey.k(k))])]),
        acc))

def key_rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  String.join(keys.go(a, LIN.lt_sorted(LIN.lt_keys(a, lst, DEV.vms(a, lst))), Nil{}), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["keys0=", key_rows(0)]))
    IO.print(String.concat(["keys3=", key_rows(3)]))
