# probe_lin.bend -- WHAT THE PORT's LINEARIZER HANDS THE RENDERER, NODE BY NODE.
#
# THE QUESTION THE RENDERED C ASKS. `execfull.bend` renders `(data1_12+idx)` -- a POINTER
# expression -- where the multiplication needs a VALUE, so the C is `float* * float*` and
# `cc` refuses it. `*(data0_20+idx)` (the STORE) is dereferenced correctly, so the deref
# exists ONE PATH OVER.  Three candidates: the linearizer (did it build a LOAD?), kuconv
# (did it map a LOAD to a non-LOAD KU?), cstyle (did it drop the `*`?).
#
# THIS FILE SEPARATES THEM: it prints `OP[src indices]` for every LINEARIZED node.
import Base
import ./../../../tinybendygrad/runtime/device.bend as D
import ./../../../tinybendygrad/schedule/rangify.bend as P
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./../../../tinybendygrad/uop/ops.bend as O

def row(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def src_names.go(+ss: List<&2, U32>) -> List<&2, String>:
  match ss:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, String, [U32.show(h)], src_names.go(t))

def dump_one.go(+ar: O.Arena, +u: U32) -> String:
  String.concat([O.Ops.name.of(O.Arena.op(ar, u)), "[",
                 String.join(src_names.go(O.Arena.srcs(ar, u)), ","), "]"])

def dump_go(+xs: List<&2, U32>, +ar: O.Arena, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: dump_go(t, ar, List.append(&2, String, acc, [dump_one.go(ar, h)]))

def lin_dump() -> String:
  +q = RZ.rz_built()
  +g = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l0 = D.schedule(O.Found.ar(g), O.Found.i(g))
  +ars = O.Found.ar(l0)
  +root = SCH.sc_src0(ars, SCH.sc_src0(ars, O.Found.i(l0)))
  +l = D.body_low(ars, root)
  +a2 = O.Found.ar(l)
  +b2 = O.Found.i(l)
  +lst = O.UOp.toposort(O.Arena.budget(a2), a2, b2)
  +lin = LIN.linearize(a2, lst, Nil{}, b2)
  String.join(dump_go(lin, a2, Nil{}), " ")

def main() -> IO(Unit):
  do IO<Unit>:
    row("lin", lin_dump())
