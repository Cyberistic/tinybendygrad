# .agents/slop/browser/vmsp.bend -- IS THE LOOP NEST IN THE GRAPH?
# `linearizer.py:19` orders a RANGE by `prod(vmax+1 for r in u.ranges)` and ops.py:471-472 makes that set
# `{self} | enclosing`. If an inner END is reachable from the outer one, the nest is a DAG edge and
# `enclosing` needs no stack walk. If every END reaches only itself, the nesting is implicit in the
# RANGE/END stream and has to be rebuilt -- and that is what decides the next unit.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/runtime/device.bend as DEV
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

def ncls(+ar: O.Arena, +n: U32) -> String:
  U32.show(U32.from_nat(List.length(&2, U32, O.Arena.src_from(ar, n, 1))))

def ends.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      ends.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsEND{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":ends=", U32.show(nends(ar, n)), ",closed=", ncls(ar, n)])]),
        acc))

def ends(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  String.join(ends.go(a, O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l)), Nil{}), " ")

def keys.go(+ar: O.Arena, +ks: List<&2, LIN.LtKey>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      keys.go(ar, t, List.append(&2, String, acc,
        [String.concat([U32.show(LIN.LtKey.i(k)), ":", U32.show(LIN.LtKey.k(k))])]))

def key_rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +lst = O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(l))
  String.join(keys.go(a, LIN.lt_sorted(LIN.lt_keys(a, lst, DEV.vms(a, lst))), Nil{}), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["ends0=", ends(0)]))
    _ : Unit <- IO.print(String.concat(["keys0=", key_rows(0)]))
    IO.print(String.concat(["ends3=", ends(3)]))
