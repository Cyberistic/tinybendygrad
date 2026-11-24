# .agents/slop/browser/klp.bend -- WHY A CAST THAT SITS NEXT TO ITS RANGE RENDERS INSIDE THE INNERMOST BODY.
# `cstyle.py:261-266` decides inline-vs-statement from `child_count`: a CAST with `cc == 1` has its TEXT
# stored (no statement) and a CAST with `cc > 1` gets `int castN = ...` AT ITS POSITION. If the four casts
# report `cc == 1` here, the statement the C shows is emitted later, by whoever first needs a name.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./fchainl.bend as CH

def kus0(+i: U32) -> (O.Arena & List<&2, C.KU>):
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_kus(ar, kk)

def row.go(+ks: List<&2, C.KU>, +all: List<&2, List<&2, C.KU>>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      row.go(t, all, Bool.pick(List<&2, String>,
        O.eq_op(C.KU.op(k), O.OpsCAST{}),
        List.append(&2, String, acc,
          [String.concat(["cc=", U32.show(C.KU.cc(k)), ",inline=",
                          Bool.show(C.ku_inline(C.KU.op(k), k, all)), ",numel=", U32.show(C.KU.numel(k))])]),
        acc))

def rows2(p: (O.Arena & List<&2, C.KU>)) -> String:
  (+a, +ks) = p
  String.join(row.go(ks, C.chunks_of(ks), Nil{}), " | ")

def rows(+i: U32) -> String:
  c = kus0(i)
  rows2(c)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["casts0=", rows(0)]))
