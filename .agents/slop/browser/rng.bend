# .agents/slop/browser/rng.bend -- DOES THE RELU'S STORE HAVE A RANGE-MAP ENTRY, AND DOES ITS VALUE?
# `rr_ap_index_src` indexes a src only under `Bool.and(has, is_lt(i, dsrc_n))` where `has` is
# `ix_rngm_has(ctx.rngm, x)` for the CONSUMER x. The relu's read collapses to `INDEX(buf, 0)`, so either
# the STORE has no entry (and then the MAX inherits nothing) or the MAX has none. This row says which.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./fchainl.bend as CH

def kg3(+i: U32) -> O.Found:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_low(ar, SCH.sc_src0(ar, kk))

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def vsrc(+ar: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(ar, n), 1n), 0)

def rows.go(+ar: O.Arena, +rngm: IX.IxRMap, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      rows.go(ar, rngm, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsSTORE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":store=", Bool.show(IX.ix_rngm_has(rngm, n)),
                          ",val=", Bool.show(IX.ix_rngm_has(rngm, vsrc(ar, n)))] )]),
        acc))

def r2(p: (O.Arena & RR.RrMap), +root: U32) -> String:
  (+a, +m) = p
  +ctx = RR.RrMap.ctx(m)
  String.join(rows.go(a, IX.IxCtx.rngm(ctx), O.UOp.toposort(O.Arena.budget(a), a, root), Nil{}), " ")

def len2(+xs: List<&2, U32>) -> String: U32.show(U32.from_nat(List.length(&2, U32, xs)))
def b2(p: (O.Arena & RR.RrMap), +root: U32) -> String:
  (+a, +m) = p
  +ctx = RR.RrMap.ctx(m)
  +rm = IX.IxCtx.rngm(ctx)
  +st = U32.from_nat(497n)
  +v = vsrc(a, st)
  String.concat(["st=", U32.show(st), ":has=", Bool.show(IX.ix_rngm_has(rm, st)),
                 " val=", U32.show(v), ":has=", Bool.show(IX.ix_rngm_has(rm, v)),
                 " inp=", len2(RR.rr_ap_inp.of(IX.ix_rngm_get(rm, v))),
                 " bcast=", len2(RR.rr_ap_bcast(a, F.Folded.t(F.folded(a)), ctx, v,
                                    O.Arena.src0(a, v))),
                 " dsrcn=", U32.show(RR.rr_ap_dsrc_n(a, v))])

def bcast_row(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +root = O.Found.i(l)
  +tb = F.Folded.t(F.folded(a))
  b2(RR.rr_range_map(a, tb, root), root)


def rows(+i: U32) -> String:
  +l = kg3(i)
  +a = O.Found.ar(l)
  +root = O.Found.i(l)
  +tb = F.Folded.t(F.folded(a))
  r2(RR.rr_range_map(a, tb, root), root)

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["rng1=", rows(1)]))
    IO.print(String.concat(["b1=", bcast_row(1)]))
