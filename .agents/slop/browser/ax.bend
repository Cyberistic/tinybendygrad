# .agents/slop/browser/ax.bend -- THE ADD'S SRC LIST WITH VALUES, for every INDEX's expression.
# All eight expressions are `TRUNCMOD>ADD>RANGE>CONST` (row 46), so the difference must be the CONSTANT the RANGE
# is multiplied by. This prints each ADD's srcs as `op=value`.
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

def one.go(+a: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t: one.go(a, t, List.append(&2, String, acc, [cvv(a, x)]))

def one(+a: O.Arena, +n: U32) -> String:
  String.join(one.go(a, O.Arena.srcs(a, n), Nil{}), ",")

def d(+a: O.Arena, +n: U32) -> U32: O.Arena.src0(a, n)

def s1of(+a: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(a, n), 1n), 0)

def row.go(+a: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      row.go(a, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(a, n), O.OpsINDEX{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), "[", one(a, d(a, s1of(a, n))), "]"])]),
        acc))

def row() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +k = RR.rr_kernel_graph(a, RZ.RZProg.sink(q))
  +ka = O.Found.ar(k)
  String.join(row.go(ka, O.UOp.toposort(O.Arena.budget(ka), ka, O.Found.i(k)), Nil{}), " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["ax=", row()]))
