# .agents/slop/browser/gd.bend -- WHAT `sk_open` SEES AT EACH END, for whatever AFTER shape the scaffold built.
# `sk_open = F.Rng.ok(ranges) && sk_axs(ranges - ended - afts)`, so the three counts beside it are the whole
# comparison: the range-map set, the ended set, and `sk_aft`'s contribution.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./fchainl.bend as CH

def n2(+xs: List<&2, U32>) -> String: U32.show(U32.from_nat(List.length(&2, U32, xs)))

# `sk_open`'s OWN expression: `F.UOp.ranges(F.Ranged.ar(g), F.Ranged.rt(g), self)` with `g = F.ranged(ar)`.
# Using `rng_sweep(ar, folded(ar))` instead was the whole reason the first version of this row read `rngs=0`.
def rg(+ar: O.Arena, +e: U32) -> List<&2, U32>:
  +g = F.ranged(ar)
  F.Rng.rs(F.UOp.ranges(F.Ranged.ar(g), F.Ranged.rt(g), e))

def rngs(+ar: O.Arena, +tb: F.Table, +e: U32) -> List<&2, U32>:
  rg(ar, e)

def row.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      row.go(ar, tb, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, x), O.OpsEND{}),
        List.append(&2, String, acc,
          [String.concat(["gate=", Bool.show(RF.sk_open(ar, x)),
                          " rngs=", n2(rngs(ar, tb, x)),
                          " ended=", n2(rngs(ar, tb, O.Arena.src0(ar, x)))])]),
        acc))

def rows() -> String:
  +k = CH.kg()
  +a = O.Found.ar(k)
  +tb = F.Folded.t(F.folded(a))
  String.join(row.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(k)), Nil{}), " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["gd=", rows()]))
