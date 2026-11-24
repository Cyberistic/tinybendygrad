# .agents/slop/browser/rm.bend -- THE ONE BOOL: is the relu's WHERE (node 84) a REALIZE point?
# `rr_p1.pick2` reads `IX.ix_rmap_has(rmap, x)` FIRST, and the real arm mints `rr_new.all(shape)` and
# returns -- so a true here means 44,45,46,47 came from `rr_p1.real` and neither `one` nor `p2` ran.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./fchainl.bend as CH

def rm2(p: (O.Arena & RR.RrMap)) -> String:
  (+a, +m) = p
  +rm = IX.IxCtx.rmap(RR.RrMap.ctx(m))
  String.concat(["r84=", Bool.show(IX.ix_rmap_has(rm, U32.from_nat(84n))),
                 " r85=", Bool.show(IX.ix_rmap_has(rm, U32.from_nat(85n))),
                 " r83=", Bool.show(IX.ix_rmap_has(rm, U32.from_nat(83n))),
                 " r78=", Bool.show(IX.ix_rmap_has(rm, U32.from_nat(78n))),
                 " r82=", Bool.show(IX.ix_rmap_has(rm, U32.from_nat(82n)))])

def rm_row() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  rm2(RR.rr_range_map(a, F.Folded.t(F.folded(a)), sink))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["rm=", rm_row()]))
