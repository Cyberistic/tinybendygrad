# .agents/slop/browser/eq.bend -- `rz_after` vs the SAME construction written out by hand.
# `UOp.store(ar, self, val, gate)` is `[self, val]`; `UOp.after(ar, self, srcs)` is `[self] ++ srcs`. If the
# hand-built AFTER's `src0` equals `Tensor.u(h1)` and `rz_after`'s does not, the loss is in `rz_after`;
# if BOTH differ, the tensor coming out of `rz_input` is not what its own `h1op=RESHAPE` row suggested.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/tensor.bend as T

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def opd(+a: O.Arena, +n: U32) -> String:
  String.concat([RF.eng_op_name(O.Arena.op(a, n)), ":", ids(IX.rr_dims(a, F.Folded.t(F.folded(a)), n))])

def row() -> String:
  +h1 = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +dst = T.Tensor.u(h1)
  +a0 = T.Tensor.ar(h1)
  +st = O.UOp.store(a0, dst, dst, None{})
  +aft = O.UOp.after(O.Found.ar(st), dst, [O.Found.i(st)])
  +aft2 = RZ.rz_after(h1, T.tn_new(a0, dst))
  +ar = O.Found.ar(aft2)
  String.concat(["dst=", opd(T.Tensor.ar(h1), dst),
                 " | hand: src0=", opd(O.Found.ar(aft), O.Arena.src0(O.Found.ar(aft), O.Found.i(aft))),
                 " eq=", Bool.show(U32.is_eq(O.Arena.src0(O.Found.ar(aft), O.Found.i(aft)), dst)),
                 " | rz_after: src0=", opd(ar, O.Arena.src0(ar, O.Found.i(aft2))),
                 " eq=", Bool.show(U32.is_eq(O.Arena.src0(ar, O.Found.i(aft2)), dst))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["eq=", row()]))
