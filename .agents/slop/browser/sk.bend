# .agents/slop/browser/sk.bend -- `sk_open` AND ITS THREE COMPONENTS, ON THE PRE-APPLY GRAPH.
# `gd.bend` measured `rngs=0` everywhere because it walked `body_low(...)`, POST-apply. `sk_open` is called
# from `rr_kernel_graph`'s widening on the PRE-apply graph -- `rz_rebuild(fchain_prog())` -- which is this.
# Run once at HEAD (flat AFTER) and once with `rz_rule.after` keeping the view, then diff.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./fchainl.bend as CH

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def row.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      row.go(ar, tb, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, x), O.OpsEND{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(x), ":gate=", Bool.show(RF.sk_open(ar, x)),
                          " rngs=", ids(F.Rng.rs(F.UOp.ranges(ar, F.rng_sweep(ar, tb), x))),
                          " ended=", ids(Maybe.default(&2, List<&2, U32>, F.UOp.ended_ranges(ar, tb, x), Nil{}))])]),
        acc))

def rows() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(a))
  String.join(row.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["sk=", rows()]))
