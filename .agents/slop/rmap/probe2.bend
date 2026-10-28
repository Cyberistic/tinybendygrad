# probe2.bend -- THE RANGE MAP's TABLE, AND THE MAP ITSELF.
#
#   ./bin/bend .agents/slop/rmap/probe2.bend
#
# ONE BEND PROCESS. ~2 s.

import Base

import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/indexing.bend as IX

def p_tbl.go(+xs: List<&2, IX.IxRange>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case e <> t:
      p_tbl.go(t, List.append(&2, String, acc,
        [String.concat(["k", U32.show(IX.IxRange.kind(e)), " i", U32.show(IX.IxRange.idx(e)),
                         " e", U32.show(IX.IxRange.ext(e))])]))

def p_us.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: p_us.go(t, List.append(&2, String, acc, [U32.show(x)]))

def p_map.go(+es: List<&2, IX.IxRngs>, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case e <> t:
      p_map.go(t, List.append(&2, String, acc,
        [String.concat(["n", U32.show(IX.IxRngs.n(e)), " in",
                         String.join(p_us.go(IX.IxRngs.inp(e), Nil{}), ","),
                         " out", String.join(p_us.go(IX.IxRngs.outp(e), Nil{}), ",")])]))

def p_map2.go(+es: List<&2, IX.IxReal>, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case e <> t:
      p_map2.go(t, List.append(&2, String, acc,
        [String.concat(["n", U32.show(IX.IxReal.n(e)), " list", Bool.show(IX.IxReal.islist(e))])]))

def p_all() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = RR.rr_range_map(ar, tb, sink)
  +b = RR.rr_run_rangeify(ar, tb, sink)
  +root = RR.rr_built(RR.RrB.rep(b), sink)
  String.concat(["ROOT ", U32.show(root), " op ", O.Ops.name.of(O.Arena.op(RR.RrB.ar(b), root)),
                 " repn ", U32.show(U32.from_nat(List.length(&2, U32, RR.RrB.rep(b)))),
                 " arn ", U32.show(O.Arena.next(RR.RrB.ar(b))), "\n",
                 "TABLE ", String.join(p_tbl.go(RR.RrMap.tbl(m), Nil{}), " | "), "\nMAP ",
                 String.join(p_map.go(IX.IxRMap.es(IX.IxCtx.rngm(RR.RrMap.ctx(m))), Nil{}), " | "),
                 "\nREALIZE ", String.join(p_map2.go(IX.IxMap.es(IX.IxCtx.rmap(RR.RrMap.ctx(m))), Nil{}), " | ")])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(p_all())

