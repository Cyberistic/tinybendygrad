# .agents/slop/browser/sk2.bend -- THE APPLY'S OWN RANGE TABLE, per END.
# `rr_kernel_graph.map` returns the graph AND the map it was built from, so `ix_rngm_get` here answers what the
# apply wrote for each END -- the one thing three instruments could not see.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./fchainl.bend as CH

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def mo(m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: ids(IX.IxRngs.outp(e))
    case _: "-"

def mi(m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: ids(IX.IxRngs.inp(e))
    case _: "-"

def row.go(+ar: O.Arena, +tb: F.Table, +rm: IX.IxRMap, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      row.go(ar, tb, rm, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, x), O.OpsEND{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(x), ":out=", mo(IX.ix_rngm_get(rm, x)),
                          " inp=", mi(IX.ix_rngm_get(rm, x)),
                          " ended=", ids(Maybe.default(&2, List<&2, U32>, F.UOp.ended_ranges(ar, tb, x), Nil{}))])]),
        acc))

def rows2(p: (O.Found & RR.RrMap)) -> String:
  (+f, +m) = p
  +ar = O.Found.ar(f)
  +tb = F.Folded.t(F.folded(ar))
  String.join(row.go(ar, tb, IX.IxCtx.rngm(RR.RrMap.ctx(m)),
                     O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(f)), Nil{}), " | ")

# THE KERNEL IS BUILT FROM THE REBUILT GRAPH: `rz_rebuild` runs BEFORE `rr_kernel_graph`, so a probe that
# starts from `fchain_prog()` cannot see anything `rz_rebuild`'s rules do.
def rows() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  rows2(RR.rr_kernel_graph.map(RZ.RZProg.ar(q), RZ.RZProg.sink(q)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["sk2=", rows()]))
