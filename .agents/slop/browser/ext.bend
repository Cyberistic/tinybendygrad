# .agents/slop/browser/ext.bend -- THE EXTENT OF EVERY `out` POSITION, and the ENDs' own range lists.
# The fold that CPython performs (`_apply_reshape` with the size-1 axes as `*0` terms, which its
# `symbolic` then removes) is driven by the EXTENTS. This prints them, plus each END's src ops,
# so the port's four-entry `out` and its two-ended END can be read in one row.
# `rng.bend` read `inp=0 bcast=0` for the relu value in one row and `inp=44,45,46,47` in another, for the same
# node on the same PRE-apply graph. Both forms are printed here, side by side, for the same entry.
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

def sinp(+e: IX.IxRngs) -> String:
  String.concat(["Some/", ids(IX.IxRngs.inp(e)), "/n=", U32.show(IX.IxRngs.n(e))])

def some_inp(m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: sinp(e)
    case _: "None"

def exts.go(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: exts.go(tbl, t, List.append(&2, String, acc, [U32.show(IX.IxRange.ext(IX.ix_tbl_at(tbl, r)))]))

def exts(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> String:
  String.join(exts.go(tbl, rs, Nil{}), ",")

def oext(+tbl: List<&2, IX.IxRange>, m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: exts(tbl, IX.IxRngs.outp(e))
    case _: "-"

def ends.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t: ends.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsEND{}),
      List.append(&2, String, acc, [String.concat([U32.show(n), "/", U32.show(O.Arena.nsrc(ar, n))])]), acc))

def kinds.go(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: kinds.go(tbl, t, List.append(&2, String, acc, [U32.show(IX.IxRange.kind(IX.ix_tbl_at(tbl, r)))]))

def kinds(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> String:
  String.join(kinds.go(tbl, rs, Nil{}), ",")

def outk(+tbl: List<&2, IX.IxRange>, m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: kinds(tbl, IX.IxRngs.outp(e))
    case _: "-"

def row.go(+ar: O.Arena, +tb: F.Table, +rm: IX.IxRMap, +m2: RR.RrMap, +ns: List<&2, U32>,
           +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      +v = vsrc(ar, n)
      row.go(ar, tb, rm, m2, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsSTORE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ": v=", U32.show(v),
                          " stinp=", ids(RR.rr_ap_inp.of(IX.ix_rngm_get(rm, n))),
                          " entry=", some_inp(IX.ix_rngm_get(rm, v)),
                          " vdims=", ids(IX.rr_dims(ar, tb, v)),
                          " sdims=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, v))),
                          " bcast=", ids(RR.rr_ap_bcast(ar, tb, RR.RrMap.ctx(m2), v, O.Arena.src0(ar, v))),
                          " kinds=", kinds(RR.RrMap.tbl(m2), RR.rr_ap_bcast(ar, tb, RR.RrMap.ctx(m2), v, O.Arena.src0(ar, v))),
                          " outk=", outk(RR.RrMap.tbl(m2), IX.ix_rngm_get(IX.IxCtx.rngm(RR.RrMap.ctx(m2)), v)),
                          " outext=", oext(RR.RrMap.tbl(m2), IX.ix_rngm_get(IX.IxCtx.rngm(RR.RrMap.ctx(m2)), v))])]),
        acc))

def rr2(p: (O.Arena & RR.RrMap), +sink: U32) -> String:
  (+a, +m) = p
  +tb = F.Folded.t(F.folded(a))
  +lst = O.UOp.toposort(O.Arena.budget(a), a, sink)
  String.concat([String.join(row.go(a, tb, IX.IxCtx.rngm(RR.RrMap.ctx(m)), m, lst, Nil{}), " | "),
                 " ENDS=", String.join(ends.go(a, lst, Nil{}), ",")])

def rows() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  rr2(RR.rr_range_map(a, F.Folded.t(F.folded(a)), sink), sink)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["ext=", rows()]))
