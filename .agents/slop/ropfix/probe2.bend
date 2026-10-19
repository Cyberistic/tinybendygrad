# probe2.bend -- WHY `sum(-1, keepdim=True)` HAS NO SHAPE READING AFTER THE CANDIDATE.
#
# It is a NODE-BY-NODE dump: op, folded shape and src count for every live index in
# topological order. The point is to NAME the first node whose shape stops being
# answerable, because "the row printed nothing" is a symptom and the fold's arm is the
# cause. The dump is built as ONE `String` and printed once, because a `match` arm is one
# expression and a print plus a recursion is two.
import Base
import ./tinybendygrad/helpers.bend as H
import ./tinybendygrad/LAWS/spec.bend as S
import ./tinybendygrad/uop/ops.bend as O
import ./tinybendygrad/uop/fold.bend as F
import ./tinybendygrad/tensor.bend as T
import ./tinybendygrad/mixin/op.bend as M

def fx243() -> T.Tensor:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{24},
    O.AParam{O.ParamArg{0, S.single(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  +x = T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))
  +r = T.tn_mop(T.Tensor.ar(x), T.Tensor.u(x), O.OpsRESHAPE{},
    T.ADims{[M.mo_ki(2), M.mo_ki(4), M.mo_ki(3)]})
  T.tn_new(O.Found.ar(r), O.Found.i(r))

def dump.go(+xs: List<&2, U32>, +ar: O.Arena, +fx: F.Folded) -> String:
  match xs:
    case Nil{}: ""
    case +u <> t: String.concat(["node ", U32.show(u), " ", O.Ops.name.of(O.Arena.op(ar, u)),
      " shape=[", M.mo_shape.go(M.mo_dims(fx, u), ""), "] nsrc=", U32.show(O.Arena.nsrc(ar, u)),
      "\n", dump.go(t, ar, fx)])

def dump(nm: String, +x: T.Tensor) -> IO(Unit):
  +fx = F.folded(T.Tensor.ar(x))
  IO.print(String.concat([nm, " root=", U32.show(T.Tensor.u(x)), "\n",
    dump.go(O.UOp.toposort(O.Arena.budget(T.Tensor.ar(x)), T.Tensor.ar(x), T.Tensor.u(x)),
      T.Tensor.ar(x), fx)]))

def t_keepdim() -> IO(Unit):
  +x = fx243()
  dump("keepdim", M.mo_sum(True{}, x, [2]))

def t_plain() -> IO(Unit):
  +x = fx243()
  dump("plain", M.mo_sum(False{}, x, [2]))

# BISECT. `mo_sum` is `cast -> mo_reduce -> keep`, and `mo_reduce.keep` is `mo_reshape(r,
# mo_keep_ds(src, axis))`. These three rows peel that apart over the SAME fixture, so the
# first one that loses the shape names the step. `probe3.bend` already showed the fold
# READS the hand-built `RESHAPE(REDUCE(PERMUTE(RESHAPE(B,(2,4,3)))), (2,4,1))`, so a row
# here that is empty is a defect in `mixin/op.bend`'s own path and not in the fold.
def t_a_keep_ds_only() -> IO(Unit):
  +x = fx243()
  dump("A_reshape_of_src_to_keepds", M.mo_reshape(x, M.mo_keep_ds(x, [2])))

def t_b_reduce_then_reshape() -> IO(Unit):
  +x = fx243()
  +f = T.tn_rop(T.Tensor.ar(x), T.Tensor.u(x), O.OpsADD{}, [2])
  +r = T.tn_new(O.Found.ar(f), O.Found.i(f))
  dump("B_rop_then_reshape", M.mo_reshape(r, M.mo_keep_ds(x, [2])))

def t_c_reduce_then_keep() -> IO(Unit):
  +x = fx243()
  +f = T.tn_rop(T.Tensor.ar(x), T.Tensor.u(x), O.OpsADD{}, [2])
  +r = T.tn_new(O.Found.ar(f), O.Found.i(f))
  dump("C_rop_then_keep", M.mo_reduce.keep(True{}, x, r, [2]))

def t_d_sum_keepdim() -> IO(Unit):
  +x = fx243()
  dump("D_mo_sum_keepdim", M.mo_sum(True{}, x, [2]))

# `mo_keep_ds` IS `reduce.py:18`'s `1 if i in axis else s for i,s in enumerate(self.shape)`,
# and it is the ONE input of the keepdim RESHAPE that this candidate does not touch. It is
# printed here because the empty keepdim row is a PRODUCT MISMATCH and a product mismatch
# means one of the two sides is wrong -- so the target has to be read, not assumed.
def kd_one(c: O.Const) -> String:
  match c:
    case O.CInt{i}: String.concat(["(", U32.show(H.lo32(i)), ")"])
    case _: "(?)"

def kd_go(+cs: List<&2, O.Const>, acc: String) -> String:
  match cs:
    case Nil{}: acc
    case c <> t: kd_go(t, String.concat([acc, kd_one(c)]))

def kd_row(nm: String, +x: T.Tensor, axis: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", kd_go(M.mo_keep_ds(x, axis), "")]))

def t_keep_ds0() -> IO(Unit):
  +x = fx243()
  kd_row("keepds_axis0", x, [0])

def t_keep_ds1() -> IO(Unit):
  +x = fx243()
  kd_row("keepds_axis1", x, [1])

def t_keep_ds2() -> IO(Unit):
  +x = fx243()
  kd_row("keepds_axis2", x, [2])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_keep_ds0()
    b : Unit <- t_keep_ds1()
    c : Unit <- t_keep_ds2()
    d : Unit <- t_keepdim()
    e : Unit <- t_plain()
    IO.print("done=1")
