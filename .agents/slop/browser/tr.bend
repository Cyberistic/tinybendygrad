# .agents/slop/browser/tr.bend -- THE WHOLE INDEX EXPRESSION TREE, with CONST values, for every INDEX.
# Levels are FIXED (t0..t3) rather than recursive below t3, so no mutual recursion can form; each level only
# calls strictly-lower ones.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./fchainl.bend as CH

def cvp(c: O.Const) -> String:
  match c:
    case O.CInt{i}: U32.show(H.lo32(i))
    case _: "?"

def cva(arg: O.Arg) -> String:
  match arg:
    case O.APy{c}: cvp(c)
    case _: "?"

def cvn(isconst: Bool, +a: O.Arena, +n: U32) -> String:
  match isconst:
    case True{}: cva(O.Arena.arg(a, n))
    case False{}: RF.eng_op_name(O.Arena.op(a, n))

def cvv(+a: O.Arena, +n: U32) -> String:
  cvn(O.eq_op(O.Arena.op(a, n), O.OpsCONST{}), a, n)

def t0(+a: O.Arena, +n: U32) -> String: cvv(a, n)

def c1.go(+a: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t: c1.go(a, t, List.append(&2, String, acc, [t0(a, x)]))

def t1(+a: O.Arena, +n: U32) -> String:
  Bool.pick(String, U32.is_zero(O.Arena.nsrc(a, n)), cvv(a, n),
    String.concat([cvv(a, n), "(", String.join(c1.go(a, O.Arena.srcs(a, n), Nil{}), " "), ")"]))

def c2.go(+a: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t: c2.go(a, t, List.append(&2, String, acc, [t1(a, x)]))

def t2(+a: O.Arena, +n: U32) -> String:
  Bool.pick(String, U32.is_zero(O.Arena.nsrc(a, n)), cvv(a, n),
    String.concat([cvv(a, n), "(", String.join(c2.go(a, O.Arena.srcs(a, n), Nil{}), " "), ")"]))

def c3.go(+a: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t: c3.go(a, t, List.append(&2, String, acc, [t2(a, x)]))

def t3(+a: O.Arena, +n: U32) -> String:
  Bool.pick(String, U32.is_zero(O.Arena.nsrc(a, n)), cvv(a, n),
    String.concat([cvv(a, n), "(", String.join(c3.go(a, O.Arena.srcs(a, n), Nil{}), " "), ")"]))

def s1of(+a: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(a, n), 1n), 0)

def row.go(+a: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      row.go(a, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(a, n), O.OpsINDEX{}),
        List.append(&2, String, acc, [String.concat([U32.show(n), "=", t3(a, s1of(a, n))])]),
        acc))

def row() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +k = RR.rr_kernel_graph(a, RZ.RZProg.sink(q))
  +ka = O.Found.ar(k)
  String.join(row.go(ka, O.UOp.toposort(O.Arena.budget(ka), ka, O.Found.i(k)), Nil{}), "
")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["tr=", row()]))
