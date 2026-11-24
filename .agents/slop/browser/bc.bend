# .agents/slop/browser/bc.bend -- `rr_ap_bcast`'s ranges for each store's VALUE, with the apply's real table.
# For the relu in the FLAT state `dims(x) = dims(s) = 196`, so `ix_bax_nleft = 0` and ALL FOUR of the store's
# ranges must reach the INDEX. If `bcast` is empty while the store's set is four, the loss is here.
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

def vsrc(+ar: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(ar, n), 1n), 0)

def rn(+xs: List<&2, U32>) -> String: U32.show(U32.from_nat(List.length(&2, U32, xs)))

def row.go(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +ns: List<&2, U32>,
           +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      +v = vsrc(ar, n)
      +s0 = O.Arena.src0(ar, v)
      row.go(ar, tb, ctx, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsSTORE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":st-inp=", rn(RR.rr_ap_inp.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), n))),
                          " v=", U32.show(v), ":rngs=", rn(RR.rr_ap_bcast(ar, tb, ctx, v, s0)),
                          "=", ids(RR.rr_ap_bcast(ar, tb, ctx, v, s0)),
                          " vdims=", rn(IX.rr_dims(ar, tb, v)), " sdims=", rn(IX.rr_dims(ar, tb, s0))])]),
        acc))

def rows2(p: (O.Found & RR.RrMap)) -> String:
  (+f, +m) = p
  +ar = O.Found.ar(f)
  +tb = F.Folded.t(F.folded(ar))
  String.join(row.go(ar, tb, RR.RrMap.ctx(m),
                     O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(f)), Nil{}), " | ")

def rows() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  rows2(RR.rr_kernel_graph.map(RZ.RZProg.ar(q), RZ.RZProg.sink(q)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["bc=", rows()]))
