# op_graph_census.bend -- A GRAPH CENSUS over the GRAPH-BUILDING defs of
# `tinybendygrad/nn/optim.bend` (1453 lines, CPython `tinygrad/nn/optim.py`, 179 lines).
#
#   .venv/bin/python gates/op_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED, AND THE RULE IS STATED IN THE GATE. The file has 176 defs:
#
#   grep -o '^def [a-z]*[a-z_0-9]*' tinybendygrad/nn/optim.bend | sed 's/def //' \
#     | sed 's/[_.].*//' | sort | uniq -c      # 176 names in 15 groups (op 107, t 23, st 10, ...)
#
# A def is a ROW iff it BUILDS A GRAPH and MIRRORS A NAMED CPYTHON EXPRESSION. The file's
# graph-building surface is the `op_*`/`op_*.*` defs whose body reaches a node write
# (`T.tn_alu` / `T.tn_rop` / `T.tn_assign_store` / `T.tn_const`), directly or through another
# such builder. That set is 24 ROWS here. Everything else FALLS OUT:
#   * 51 of the 107 `op_*` defs reach NO node write inside this file and are the READERS --
#     they return a list / number / record: `op_filter`, `op_acc`, `op_last`, `op_pos`,
#     `op_lr_ok`, `op_param_dtype`, `op_lr_dtype`, `op_nop`, `op_zg`, `op_set_params`,
#     `op_zero_grad`, `op_group`, `op_grad_zero`, `op_sched`, `op_slice`, `op_ndim`,
#     `op_axes`, `op_1mb`, `op_ar`, `op_with_arena`, `op_last_ar` (the rest of the 51 are
#     their `.go`/`.of`/`.push` halves). `op_cast` is a row whose NODE is built in
#     tensor.bend's `tn_cast`, so it is counted here and driven as a row.
#   * the pure `.node`/fixture/printers and the `g_*`/`st_*`/`t_*`/`sig`/`us`/`row`/`main`
#     plumbing (69 non-`op_` defs). A `.node` def is the parameterised half of its wrapper and
#     is reached THROUGH it; the fixtures are this file's own.
# 24 graph rows + 4 VALUE rows = 28. The four value rows are the layer's own non-graph claims
# (`params`/`bufs`/`acc`/`nop`) and they are kept because a graph census that dropped the one
# part of the layer that was already correct would lose the control.
#
# THE PRINTER IS THE DEEP TOPOSORT PLUS EACH NODE'S ARG, AND THE ARG IS NOT DECORATION.
# `O.Rng.sig` prints the node COUNT, the root op, the root nsrc and the SRC op sequence -- it
# does NOT print an ARG, and the layer's headline defect hides EXACTLY there: the trust-ratio
# guards compare against `CONST 1.0` where CPython compares against `CONST 0.0`
# (`op_cmplt1`, optim.bend:801). The two graphs are the SAME op sequence
# (`... CMPLT/2 ... CONST/0 ...`), so NO op-level printer can see it. Every node therefore
# prints `<op>/<nsrc>:<arg>` -- `f<bits>` for a float CONST (`F32.bits`), `b<bool>` for a
# bool, `-` otherwise -- and the oracle prints the same from `ConstFloat.bits` re-encoded to
# f32. THIS IS THE `md_*` CENSUS'S ` arg=` SUFFIX, made per-node.
#
# THE FIXTURE IS ONE ARENA, the safe shape `gates/ew_graph_census.bend` records. FOUR
# BUFFERs (`t` the parameter, `g` the gradient, `b` the momentum buffer, `lr` the learning
# rate) are built in ONE `Arena.empty()` chain and handed out. The file's own `g_step()`
# builds its four in THREE sibling arenas (`st_t.ar(O.Arena.empty())` is called three times),
# which happens to line up because each sibling builds the same prefix -- a coincidence, not a
# contract, and this file does not rely on it.
#
# NOTHING IS EXECUTED. Every row is the signature of a LAZY graph, so no device is needed and
# the CPython lane is a `toposort()`.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/nn/optim.bend as Op

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# --- THE ARG, AS A VALUE. `Arena.arg` is total, so a non-`APy` arg prints `-`. A `match`
# cannot scrutinise a computed value (Bend refuses it by name), so the arg arrives as a
# parameter and `const_arg` does the inner match.
def const_arg(c: O.Const) -> String:
  match c:
    case O.CFloat{f}: String.concat(["f", U32.show(F32.bits(f))])
    case O.CBool{b}: String.concat(["b", Bool.show(b)])
    case O.CInt{i}: "i"
    case O.CInvalid{}: "inv"

def arg_of(a: O.Arg) -> String:
  match a:
    case O.APy{c}: const_arg(c)
    case _: "-"

def dsig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: dsig.go(t, ar, String.concat([acc,
      O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u)), ":",
      arg_of(O.Arena.arg(ar, u)), " "]))

def dsig(+ar: O.Arena, i: U32) -> String:
  +xs = O.UOp.toposort(O.Arena.budget(ar), ar, i)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " ", dsig.go(xs, ar, "")])

def dsig_t(+t: T.Tensor) -> String:
  dsig(T.Tensor.ar(t), T.Tensor.u(t))

# ===========================================================================
# THE FIXTURE: four BUFFERs in ONE arena.
# ===========================================================================
type Fx is Data:
  Fx{ar: O.Arena, t: U32, g: U32, b: U32, lr: U32}

def Fx.ar(x: Fx) -> O.Arena:
  match x:
    case Fx{ar, t, g, b, lr}: ar
def Fx.t(x: Fx) -> U32:
  match x:
    case Fx{ar, t, g, b, lr}: t
def Fx.g(x: Fx) -> U32:
  match x:
    case Fx{ar, t, g, b, lr}: g
def Fx.b(x: Fx) -> U32:
  match x:
    case Fx{ar, t, g, b, lr}: b
def Fx.lr(x: Fx) -> U32:
  match x:
    case Fx{ar, t, g, b, lr}: lr

def fx() -> Fx:
  +n0 = Op.pbuf(O.Arena.empty(), 0, 2, S.single())
  +n1 = Op.pbuf(O.Found.ar(n0), 1, 2, S.single())
  +n2 = Op.pbuf(O.Found.ar(n1), 2, 2, S.single())
  +n3 = Op.pbuf(O.Found.ar(n2), 3, 2, S.single())
  Fx{O.Found.ar(n3), O.Found.i(n0), O.Found.i(n1), O.Found.i(n2), O.Found.i(n3)}

def wrap(f: Fx, u: U32) -> T.Tensor:
  T.tn_wrap_uop(Fx.ar(f), u)

def st_of(+f: Fx) -> Op.St:
  Op.St{Fx.ar(f), Fx.t(f), Fx.g(f), Fx.b(f), Fx.lr(f)}

# ===========================================================================
# THE GRAPH ROWS. One def per ported builder, driven once.
# ===========================================================================

# `t.detach()` -- elementwise.py:43, `self.alu(Ops.DETACH)`.
def p_detach() -> String:
  +f = fx()
  dsig_t(Op.op_detach(Fx.ar(f), Fx.t(f)))

# `_apply_update` -- optim.py:60, `t.detach() - up.to(t.device)` (the `.to` is a device wall,
# dropped by the port's header).
def p_apply() -> String:
  +f = fx()
  dsig_t(Op.op_apply(Op.op_detach(Fx.ar(f), Fx.t(f)), Fx.g(f)))

# `self * self` -- elementwise.py:575 `square`.
def p_square() -> String:
  +f = fx()
  dsig_t(Op.op_square(Fx.ar(f), Fx.t(f)))

# `t / g` -- elementwise.py:250, `a.alu(Ops.MUL, b.reciprocal())`.
def p_div() -> String:
  +f = fx()
  dsig_t(Op.op_div(Fx.t(f), wrap(f, Fx.g(f))))

# `t.sqrt()` -- elementwise.py:480.
def p_sqrt() -> String:
  +f = fx()
  dsig_t(Op.op_sqrt(wrap(f, Fx.t(f))))

# `t.reciprocal()` -- elementwise.py:460.
def p_recip() -> String:
  +f = fx()
  dsig_t(Op.op_recip(wrap(f, Fx.t(f))))

# `-t` -- elementwise.py `__neg__`.
def p_neg() -> String:
  +f = fx()
  dsig_t(Op.op_neg(wrap(f, Fx.t(f))))

# `t.sum()` -- reduce.py:20, every axis.
def p_sum() -> String:
  +f = fx()
  dsig_t(Op.op_sum(Fx.ar(f), Fx.t(f)))

# `t.square().sum().sqrt()` -- optim.py:113 (without the DETACH).
def p_normsq() -> String:
  +f = fx()
  dsig_t(Op.op_normsq(wrap(f, Fx.t(f))))

# `g.cast(t.dtype)` -- mixin/dtype.py, optim.py:128.
def p_cast() -> String:
  +f = fx()
  dsig_t(Op.op_cast(wrap(f, Fx.t(f)), S.single()))

# `q.where(x, 1.0)` -- elementwise.py:426.
def p_where() -> String:
  +f = fx()
  dsig_t(Op.op_where(Op.op_cmplt1(Fx.ar(f), wrap(f, Fx.t(f))), wrap(f, Fx.g(f)), 1.0))

# THE GUARD `r > 0` -- optim.py:115. The port's `op_cmplt1` builds `CONST 1.0`; CPython
# builds `CONST 0.0`. The arg suffix is the only thing that can see it.
def p_guard() -> String:
  +f = fx()
  dsig_t(Op.op_cmplt1(Fx.ar(f), wrap(f, Fx.t(f))))

# `wd * t.detach()` -- optim.py:117.
def p_mulf() -> String:
  +f = fx()
  dsig_t(Op.op_mulf(Fx.ar(f), 0.1, wrap(f, Fx.t(f))))

# `g + wd * t.detach()` -- optim.py:117.
def p_prewd() -> String:
  +f = fx()
  dsig_t(Op.op_prewd(Fx.ar(f), Fx.g(f), Fx.t(f), 0.1))

# THE TRUST RATIO -- optim.py:113-115.
def p_trust() -> String:
  +f = fx()
  dsig_t(Op.op_trust(Fx.ar(f), Fx.t(f), Fx.g(f), 0.0, 0.001))

# `g * r * self.lr` with tcoef=0 so `r = 1.0` -- optim.py:116, :119.
def p_lars0() -> String:
  +f = fx()
  dsig_t(Op.op_lars0(st_of(f)))

# `self.b[i].assign(self.momentum * self.b[i] + g)` -- optim.py:121.
def p_mom() -> String:
  +f = fx()
  dsig_t(Op.op_mom(Fx.ar(f), Fx.b(f), Fx.g(f), 0.9))

# `g + self.momentum * self.b[i]` -- optim.py:122.
def p_nesterov() -> String:
  +f = fx()
  dsig_t(Op.op_nesterov(Fx.ar(f), Fx.g(f), Fx.b(f), 0.9, True{}))

# `g + self.wd * self.lr * t.detach()` -- optim.py:127.
def p_postwd() -> String:
  +f = fx()
  dsig_t(Op.op_postwd(Fx.ar(f), Fx.g(f), Fx.t(f), Fx.lr(f), 0.1))

# `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` -- optim.py:167.
def p_mstep() -> String:
  +f = fx()
  dsig_t(Op.op_mstep(Fx.ar(f), Fx.b(f), Fx.g(f), 0.9))

# `(self.b2 * self.v[i] + (1.0 - self.b2) * (g * g)).cast(...)` -- optim.py:168.
def p_vstep() -> String:
  +f = fx()
  dsig_t(Op.op_vstep(Fx.ar(f), Fx.b(f), Fx.g(f), 0.999))

# `m_hat = self.m[i] / (1.0 - self.b1_t)` -- optim.py:169.
def p_mhat() -> String:
  +f = fx()
  dsig_t(Op.op_mhat(Fx.ar(f), Fx.b(f), Fx.lr(f)))

# `v_hat = self.v[i] / (1.0 - self.b2_t)` -- optim.py:170.
def p_vhat() -> String:
  +f = fx()
  dsig_t(Op.op_vhat(Fx.ar(f), Fx.b(f), Fx.lr(f)))

# `(self.lr * r * up).cast(t.dtype)` -- optim.py:178.
def p_lamb_up() -> String:
  +f = fx()
  +up = wrap(f, Fx.b(f))
  +r = T.tn_const(Fx.ar(f), O.CFloat{1.0})
  dsig_t(Op.op_lamb_up(up, r, wrap(f, Fx.lr(f))))

# ===========================================================================
# THE FOUR VALUE ROWS -- the file's own non-graph claims.
# ===========================================================================
def us.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: us.go(t, String.concat([acc, U32.show(h), ","]))

def us(xs: List<&2, U32>) -> String:
  us.go(xs, "")

# THE NUMELS, not the arena indices: the oracle has no arena, so the row prints the SAME
# number both lanes can answer -- `t.numel()`. The map is spelled HERE and not taken from
# `op_nop.sizes`, which conses the RECURSIVE result first and therefore reverses its input
# (`op_nop.sizes([1,2])` answers `[numel(2), numel(1)]`); `op_nop.arm`'s `map_nzs` reverses a
# second time so `op_nop` is right, but the bare reader is not.
def numels.go(+ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: numels.go(ar, t, List.append(&2, U32, acc, [Op.op_numel_u(ar, x)]))

def numels(+ar: O.Arena, xs: List<&2, U32>) -> List<&2, U32>:
  numels.go(ar, xs, Nil{})

def p_params() -> String:
  +ts = Op.g_all(O.Arena.empty())
  us(numels(Op.op_last_ar(ts, O.Arena.empty()), Op.op_filter.of(True{}, ts)))

def p_bufs() -> String:
  +ts = Op.g_all(O.Arena.empty())
  us(numels(Op.op_last_ar(ts, O.Arena.empty()), Op.op_filter.of(False{}, ts)))

def p_acc() -> String:
  us(Op.op_acc(Op.g_two(O.Arena.empty())))

def nop_names.go(ns: List<&2, Op.NewOpt>, acc: String) -> String:
  match ns:
    case Nil{}: acc
    case +n <> t: nop_names.go(t, String.concat([acc, Op.nop_name(n), ":",
      U32.show(Op.nop_n(n)), ","]))

def p_nop() -> String:
  nop_names.go(Op.op_nop(Op.g_opt.grown(Op.g_two(O.Arena.empty()))), "")

def main() -> IO(Unit):
  do IO<Unit>:
    a0 : Unit <- srow("params", p_params())
    a1 : Unit <- srow("bufs", p_bufs())
    a2 : Unit <- srow("acc", p_acc())
    a3 : Unit <- srow("nop", p_nop())
    b0 : Unit <- srow("detach", p_detach())
    b1 : Unit <- srow("apply", p_apply())
    b2 : Unit <- srow("square", p_square())
    b3 : Unit <- srow("div", p_div())
    b4 : Unit <- srow("sqrt", p_sqrt())
    b5 : Unit <- srow("recip", p_recip())
    b6 : Unit <- srow("neg", p_neg())
    b7 : Unit <- srow("sum", p_sum())
    b8 : Unit <- srow("normsq", p_normsq())
    b9 : Unit <- srow("cast", p_cast())
    c0 : Unit <- srow("where", p_where())
    c1 : Unit <- srow("guard", p_guard())
    c2 : Unit <- srow("mulf", p_mulf())
    c3 : Unit <- srow("prewd", p_prewd())
    c4 : Unit <- srow("trust", p_trust())
    c5 : Unit <- srow("lars0", p_lars0())
    c6 : Unit <- srow("mom", p_mom())
    c7 : Unit <- srow("nesterov", p_nesterov())
    c8 : Unit <- srow("postwd", p_postwd())
    c9 : Unit <- srow("mstep", p_mstep())
    d0 : Unit <- srow("vstep", p_vstep())
    d1 : Unit <- srow("mhat", p_mhat())
    d2 : Unit <- srow("vhat", p_vhat())
    d3 : Unit <- srow("lamb_up", p_lamb_up())
    return Unit{}
