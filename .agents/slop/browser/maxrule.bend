# THE MAX -> (a<b).where(b,a) RULE, measured on its own: does the late table CLAIM a
# MAX, and is its answer the CMPLT+WHERE upstream builds (decomp/op.py:83)?
import Base
import ./../../../tinybendygrad/codegen/decomp/op.bend as DC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/rangify.bend as RF
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H

def mx_ar() -> O.Found:
  +a = O.UOp.cconst(O.Arena.empty(), O.CInt{H.i64_of_i32(3)}, S.int32())
  +b = O.UOp.cconst(O.Found.ar(a), O.CInt{H.i64_of_i32(7)}, S.int32())
  O.UOp.alu(O.Found.ar(b), O.OpsMAX{}, [O.Found.i(a), O.Found.i(b)])

def mx() -> String:
  +f = mx_ar()
  +ar = O.Found.ar(f)
  +m = O.Found.i(f)
  +h = DC.late_rewrite_patterns(False{}, F.folded(ar), m)
  String.concat(["on=", U32.show(DC.Hit.on(h)), " tg=", U32.show(DC.Hit.tg(h)),
                 " ans=", RF.rr_node_str(DC.Hit.ar(h), DC.Hit.i(h)),
                 " srcs=", RF.rr_node_str(DC.Hit.ar(h), O.Arena.src0(DC.Hit.ar(h), DC.Hit.i(h))),
                 ",", RF.rr_node_str(DC.Hit.ar(h), O.Arena.src(DC.Hit.ar(h), DC.Hit.i(h), 1)),
                 " in=", RF.rr_node_str(DC.Hit.ar(h), O.Arena.src0(DC.Hit.ar(h), O.Arena.src0(DC.Hit.ar(h), DC.Hit.i(h))))])

# THE ORDER IS A CLAIM, SO IT IS AN IDENTITY TEST AND NOT A PRINTED VALUE: the answer's
# WHERE must take `b` first and `a` second, and its condition must be `a < b` with the
# operands in THAT order (CMPLT does not commute).
def mx_shape() -> String:
  +f = mx_ar()
  +ar0 = O.Found.ar(f)
  +a = O.Arena.src0(ar0, O.Found.i(f))
  +b = O.Arena.src(ar0, O.Found.i(f), 1)
  +h = DC.late_rewrite_patterns(False{}, F.folded(ar0), O.Found.i(f))
  +x = DC.Hit.ar(h)
  +w = DC.Hit.i(h)
  +c = O.Arena.src0(x, w)
  String.concat(["is_where=", Bool.show(O.eq_op(O.Arena.op(x, w), O.OpsWHERE{})),
                 " c0_is_cmplt=", Bool.show(O.eq_op(O.Arena.op(x, c), O.OpsCMPLT{})),
                 " cmp_is(a,b)=", Bool.show(Bool.and(U32.is_eq(O.Arena.src0(x, c), a), U32.is_eq(O.Arena.src(x, c, 1), b))),
                 " where_is(b,a)=", Bool.show(Bool.and(U32.is_eq(O.Arena.src(x, w, 1), b), U32.is_eq(O.Arena.src(x, w, 2), a)))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["mx=", mx()]))
    IO.print(String.concat(["shape=", mx_shape()]))
