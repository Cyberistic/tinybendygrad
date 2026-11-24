# .agents/slop/browser/ix.bend -- THE INDEX NODES OF THE APPLIED GRAPH, BY STRUCTURE ONLY.
# A range map lookup misses on this graph (ids are pre-apply), but a NODE'S SRCS are in the same arena, so
# this needs no map at all: an INDEX that carries ranges has them as srcs 1..n. `[PARAM]` alone = the collapse
# happened BEFORE the expression was built.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./fchainl.bend as CH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF

def ops.go(+a: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: ops.go(a, t, List.append(&2, String, acc, [RF.eng_op_name(O.Arena.op(a, s))]))

# THE EXPRESSION CHAIN: INDEX -> src1 (the index expr) -> its src0 -> its src0. The conv's inner must be a
# multi-term ALU; a bare CONST names the collapse.
def s1of(+a: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(a, n), 1n), 0)

def e(+a: O.Arena, +n: U32) -> String: RF.eng_op_name(O.Arena.op(a, n))

def d(+a: O.Arena, +n: U32) -> U32: O.Arena.src0(a, n)

def chain2(+a: O.Arena, +m: U32) -> String:
  Bool.pick(String, U32.is_zero(O.Arena.nsrc(a, m)), "",
    String.concat([e(a, d(a, m)), ">", e(a, d(a, d(a, m)))]))

def chain(+a: O.Arena, +n: U32) -> String:
  Bool.pick(String, U32.is_zero(O.Arena.nsrc(a, n)), "nosrc",
    String.concat([e(a, d(a, n)), ">", chain2(a, d(a, n))]))

def row.go(+a: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      row.go(a, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(a, n), O.OpsINDEX{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":", U32.show(O.Arena.nsrc(a, n)), ":",
                          String.join(ops.go(a, O.Arena.srcs(a, n), Nil{}), ","),
                          " :: ", chain(a, s1of(a, n))])]),
        acc))

def row() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +k = RR.rr_kernel_graph(a, sink)
  +ka = O.Found.ar(k)
  String.join(row.go(ka, O.UOp.toposort(O.Arena.budget(ka), ka, O.Found.i(k)), Nil{}), " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["ix=", row()]))
