# .agents/slop/browser/p1.bend -- WHICH `rr_p1` ARM THE RELU'S STORE TAKES.
# `rr_p1.pick2(real = ix_rmap_has(rmap, x), zero = cnt == 0, one = cnt == 1, ...)`: `real` mints from the
# node's OWN shape (four kind-0 ranges for a store), `one` inherits its consumer's `out` -- and the relu's
# store's `out` decodes `1,1,0,0`, which `one` would explain exactly.
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

def kinds.go(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: kinds.go(tbl, t, List.append(&2, String, acc, [U32.show(IX.IxRange.kind(IX.ix_tbl_at(tbl, r)))]))

def kinds(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> String: String.join(kinds.go(tbl, rs, Nil{}), ",")

def oke(+e: IX.IxRngs, +tbl: List<&2, IX.IxRange>) -> String:
  String.concat([ids(IX.IxRngs.outp(e)), "/k=", kinds(tbl, IX.IxRngs.outp(e))])

def okay.pick(m: Maybe<&2, IX.IxRngs>, +tbl: List<&2, IX.IxRange>, +c: U32) -> String:
  match m:
    case Some{e}: String.concat([U32.show(c), ":", oke(e, tbl)])
    case _: String.concat([U32.show(c), ":none"])

def okay(+rm: IX.IxRMap, +tbl: List<&2, IX.IxRange>, +c: U32) -> String:
  okay.pick(IX.ix_rngm_get(rm, c), tbl, c)

def coutk.go(+rm: IX.IxRMap, +tbl: List<&2, IX.IxRange>, +cs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case c <> t: coutk.go(rm, tbl, t, List.append(&2, String, acc, [okay(rm, tbl, c)]))

def row2(p: (O.Arena & RR.RrMap), +n: U32, +sink: U32) -> String:
  (+a, +m) = p
  +ctx = RR.RrMap.ctx(m)
  +tbl = RR.RrMap.tbl(m)
  +rev = List.reverse(&2, U32, O.UOp.toposort(O.Arena.budget(a), a, sink))
  String.concat(["n=", U32.show(n),
                 " real=", Bool.show(IX.ix_rmap_has(IX.IxCtx.rmap(ctx), n)),
                 " cnt=", U32.show(U32.from_nat(List.length(&2, U32, RR.rr_cons(a, rev, n)))),
                 " cons=", String.join(coutk.go(IX.IxCtx.rngm(ctx), tbl, RR.rr_cons(a, rev, n), Nil{}), ";")])

def row(+n: U32) -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(a))
  row2(RR.rr_range_map(a, tb, sink), n, sink)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p1_85=", row(U32.from_nat(85n))]))
