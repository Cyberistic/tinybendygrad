import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./../mixin/op.bend as M
import ./../mixin/movement.bend as MX
import ./../mixin/creation.bend as CR
import ./../nn/layers.bend as NL
import ./../nn/pool.bend as PO

# THE MERGE POINT -- `mixin/movement.bend:1332 mxw_dims_of`, the shape of ANY
# node. THE FOLD CANNOT ANSWER A MOVEMENT NODE (`uop/fold.bend:1620-1626`
# DEFERS the six movement ops), so THIS is the instrument and `px_fold` is
# only a second opinion.
def px_decl(+t: T.Tensor) -> String:
  MX.mx_show(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)))

# EVERY NODE, IN THE TOPOSORT, WITH ITS OP AND ITS SHAPE. THE DEFECT LIVES IN
# AN INTERMEDIATE: the final RESHAPE's marg is the TARGET in the broken tree
# AND in the fixed one, so a probe that reads only the final node CANNOT SEE
# IT. The EXPAND node's shape is `tuple(self.marg) + ps` (ops.py:397) and it
# is where the wrong marg shows.
def px_line(nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, " final=", px_decl(t)]))

# THE MARG OF THE EXPAND NODE, IN VALUES. `mixin/movement.bend`'s `mxm_marg`
# reads the marg of a movement node and `MxMarg.ds` reads its dims, which for
# an EXPAND is the marg's VALUES -- so this is CPython's `arg` read off the
# port's own node.
def px_is_exp(+ar: O.Arena, u: U32) -> Bool: O.eq_op(O.Arena.op(ar, u), O.OpsEXPAND{})

def px_is_perm(+ar: O.Arena, u: U32) -> Bool: O.eq_op(O.Arena.op(ar, u), O.OpsPERMUTE{})

def px_marg.of(exp: Bool, +ar: O.Arena, u: U32) -> List<&2, U32>:
  match exp:
    case True{}: MX.MxMarg.ds(MX.mxm_marg(ar, u))
    case _: Nil{}

def px_exp_lines.go(+ar: O.Arena, +us: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match us:
    case Nil{}: acc
    case u <> t:
      px_exp_lines.go(ar, t, Bool.pick(List<&2, String>, px_is_exp(ar, u),
        List.append(&2, String, acc, [String.concat(["expand marg=",
          MX.mx_show(px_marg.of(px_is_exp(ar, u), ar, u)), " shape=",
          MX.mx_show(MX.mxw_dims_of(ar, u))])]),
        acc))

def px_perm_lines.go(+ar: O.Arena, +us: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match us:
    case Nil{}: acc
    case u <> t:
      px_perm_lines.go(ar, t, Bool.pick(List<&2, String>, px_is_perm(ar, u),
        List.append(&2, String, acc, [String.concat(["permute shape=",
          MX.mx_show(MX.mxw_dims_of(ar, u))])]),
        acc))


def px_dump(nm: String, +t: T.Tensor) -> IO(Unit):
  +ar = T.Tensor.ar(t)
  +us = O.UOp.toposort(O.Arena.budget(ar), ar, T.Tensor.u(t))
  +es = px_exp_lines.go(ar, us, Nil{})
  +ps = px_perm_lines.go(ar, us, Nil{})
  IO.print(String.concat([nm, " final=", px_decl(t), " | ", String.join(es, " | "),
    " | ", String.join(ps, " | ")]))

def px_t(ns: List<&2, U32>, slot: U32, size: U32) -> T.Tensor:
  MX.mxw_reshape(MX.mxw_buf(O.Arena.empty(), slot, size), ns)

# --- CASE 1: the conv2d expand. CPython op.py:1600-1601 --------------------
# `x.reshape(bs, groups, cin, 1, *oyx, *HW).expand(bs, groups, cin, rcout, *oyx, *HW)`
# source (bs, groups, cin, 1, oy, ox, kh, kw) -> target (bs, groups, cin, rcout, oy, ox, kh, kw)
# CPython's marg for that expand is (rcout,) -- ops.py:397 `tuple(self.marg) + ps`.
def px_case_conv() -> IO(Unit):
  +p = px_t([1, 1, 4, 14, 14, 3, 3], 0, 9408)
  +e = NL.nn_expand(MX.mxw_reshape(p, [1, 1, 4, 1, 14, 14, 3, 3]),
    [1, 1, 4, 8, 14, 14, 3, 3])
  do IO<Unit>: px_dump("case1_conv_expand", e)

# --- CASE 2: `repeat` -- movement.py:576-604 --------------------------------
# CPython: `self.reshape(unsq).expand(ex).reshape(fin)`.
# source (bs, cin, 1, H, 1, W) -> target (bs, cin, r0, H, r1, W); CPython's
# marg is (r0, r1) -- the REPEAT COUNTS, not the whole target.
def px_case_repeat() -> IO(Unit):
  +t = px_t([1, 64, 58, 58], 0, 215296)
  +r = NL.nn_repeat(t, [1, 64, 58, 58], [1, 1, 4, 4])
  do IO<Unit>: px_dump("case2_repeat", r)

# --- CASE 3: the REPEAT chain WITHOUT the final reshape ---------------------
# `nn_repeat`'s last step is a RESHAPE, and a RESHAPE's marg is the TARGET, so
# case2's FINAL shape is right in the broken tree AND in the fixed one. This
# case is `repeat` up to the expand, which is where the wrong marg lives.
def px_case_repeat_mid() -> IO(Unit):
  +t = px_t([1, 64, 58, 58], 0, 215296)
  +u = MX.mxw_reshape(t, [1, 64, 1, 58, 1, 58])
  +r = NL.nn_expand(u, [1, 64, 4, 58, 4, 58])
  do IO<Unit>: px_dump("case3_repeat_mid", r)

# --- CASE 4: `_pool`'s repeat -- movement.py:624 ---------------------------
# source (b0, b1, 1, i0, 1, i1) -> target (b0, b1, kk0, i0, kk1, i1);
# CPython's marg is (kk0, kk1).
def px_case_pool() -> IO(Unit):
  +t = px_t([1, 64, 58, 58], 0, 215296)
  +r = PO.pool_maxpool(t, PO.W4{1, 64, 58, 58, 3, 3, 2, 2, 1, 1})
  do IO<Unit>: px_dump("case4_pool_maxpool", r)

# --- CASE 5: the 0-dim source -- creation.py:85 `const(v, dt).expand(shape)`
# A 0-dim source has EVERY dim left-added, so CPython's marg IS the whole
# target. This case must NOT MOVE.
def px_case_scalar() -> IO(Unit):
  +c = CR.cr_const_of(O.Arena.empty(), O.CFloat{0.0}, S.single())
  +e = CR.cr_expand(c, [2, 3, 4])
  do IO<Unit>: px_dump("case5_scalar_expand", e)

# --- CASE 6: the LEFT-ADDED case -- the target is WIDER than the source -----
# CPython: `Tensor.zeros(4).expand(2, 3, 4)` -> marg (2, 3), the LEFT-ADDED
# dims ONLY, and NO squeeze and NO permute.
def px_case_left() -> IO(Unit):
  +c = CR.cr_const_of(O.Arena.empty(), O.CFloat{0.0}, S.single())
  +z = MX.mxw_reshape(c, [4])
  +e = CR.cr_expand(z, [2, 3, 4])
  do IO<Unit>: px_dump("case6_left_added", e)

# --- CASE 7: a 1 in the MIDDLE, no left added ------------------------------
# CPython: `Tensor.zeros(2, 1, 5).expand(2, 3, 5)` -> marg (3,) and a permute.
def px_case_middle() -> IO(Unit):
  +c = CR.cr_const_of(O.Arena.empty(), O.CFloat{0.0}, S.single())
  +z = MX.mxw_reshape(c, [2, 1, 5])
  +e = CR.cr_expand(z, [2, 3, 5])
  do IO<Unit>: px_dump("case7_middle_one", e)

# --- CASE 8: the WHOLE conv2d graph -- the one existing row that moves ------
# `nn/layers.bend`'s `dbg_conv_sig` counts this graph's nodes, so the delta is
# measured here on the SAME graph.
def px_case_conv2d.of(m: Maybe<&2, T.Tensor>) -> IO(Unit):
  match m:
    case Some{c}: px_line("case8_conv2d", c)
    case None{}: IO.print("case8_conv2d NONE")

def px_case_conv2d() -> IO(Unit):
  +x = px_t([1, 3, 32, 32], 0, 3072)
  +w = px_t([8, 3, 3, 3], 1, 216)
  do IO<Unit>: px_case_conv2d.of(NL.nn_conv2d(x, w, 1, 1, 1, 1, None{}, None{}))

def main() -> IO(Unit):
  do IO<Unit>:
    px_case_conv()
    px_case_repeat()
    px_case_repeat_mid()
    px_case_pool()
    px_case_scalar()
    px_case_left()
    px_case_middle()
    px_case_conv2d()
