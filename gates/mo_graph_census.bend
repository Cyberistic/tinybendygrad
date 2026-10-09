# mo_graph_census.bend -- THE GRAPH CENSUS over the public `mo_*` layer of
# `tinybendygrad/mixin/op.bend`. Every public def driven once, its toposort OP SEQUENCE
# printed in the same format CPython prints for the method it mirrors.
#
#   .venv/bin/python gates/mo_graph_census-gate.py
#
# WHY A CENSUS AND NOT A SAMPLE. `gates/mixin-op-gate.py` compares the twelve `op.py`
# RECIPES (`min`/`mean`/`var`/`std`/`logsumexp`/`softmax`/...) through the port's own
# `main`. This drives each ported def DIRECTLY and adds the REDUCE, ELEMENTWISE and
# MOVEMENT hoists the port spells here (`max`/`sum`/`prod`, `neg`/`sub`/`where`/`eq`/
# `isfinite`/`exp`/`log`/`reciprocal`/`div`/`_inverse`, `reshape`/`squeeze`/`permute`)
# which that gate only reaches INDIRECTLY through a recipe.
#
# THE PRINTER IS THE PORT'S OWN. `M.mo_sig_t` (op.bend:1146) is the census printer the
# port already ships; a second copy here would be a second contract. The fixtures are the
# port's own `M.mo_fx1d` / `M.mo_fx2d` / `M.mo_i1d`, which are the same BUFFER /
# BUFFER-RESHAPED nodes CPython's `Tensor([1.,2.,3.,4.], device='PYTHON')` builds.
#
# NOTHING IS EXECUTED. Every row is the signature of the LAZY graph, so no device is
# needed and the CPython lane is a `toposort()`.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/op.bend as M

# --- THE REDUCE HOIST (`mixin/reduce.py`), which `mixin-op-gate` only reaches through
# `mean`/`var`. `max0`/`sum0`/`prod0` are the one-line bodies of `max`/`sum`/`prod`.

def c_max0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("max0", M.mo_max(False{}, x, M.mo_ax(False{}, x, 0)))

def c_max0kd() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("max0kd", M.mo_max(True{}, x, M.mo_ax(False{}, x, 0)))

def c_sum0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("sum0", M.mo_sum(False{}, x, M.mo_ax(False{}, x, 0)))

def c_sum0kd() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("sum0kd", M.mo_sum(True{}, x, M.mo_ax(False{}, x, 0)))

def c_prod0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("prod0", M.mo_prod(False{}, x, M.mo_ax(False{}, x, 0)))

# --- THE ELEMENTWISE HOIST (`mixin/elementwise.py`), the unary half.

def c_neg0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("neg0", M.mo_neg(x))

def c_notb0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("notb0", M.mo_notb(x))

def c_eqc0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("eqc0", M.mo_eqc(x, O.CFloat{2.0}))

def c_isfinite0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("isfinite0", M.mo_isfinite(T.Tensor.ar(x), x))

def c_isnan0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("isnan0", M.mo_isnan(x))

def c_exp0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("exp0", M.mo_exp(x))

# A STRONG int32 SOURCE, and it is the fixture that separates the three casts: for a float32
# source all three fold and `exp0` prints `4 BUFFER/0 CONST/0 MUL/2 EXP2/1` on BOTH sides, so
# the wrong cast-back target was INVISIBLE. CPython's `Tensor([1,2,3,4]).exp()` is
# `5 BUFFER/0 CAST/1 CONST/0 MUL/2 EXP2/1`; the defect made the port print 6, the extra node
# being the CAST back to `int32` instead of to `least_upper_float(int32) = f32`.
def c_exp_i32() -> IO(Unit):
  +x = M.mo_i1d()
  M.mo_sig_t("exp_i32", M.mo_exp(x))

def c_log0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("log0", M.mo_log(x))

def c_recip0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("recip0", M.mo_recip(x))

def c_inverse0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("inverse0", M.mo_inverse(True{}, x))

# --- THE ELEMENTWISE HOIST, the binary half. The second operand is a CONST built in the
# FIRST operand's arena (`M.mo_const_t`), so the two nodes share one arena -- the rule the
# port's header spells: a build reads `Tensor.ar` of whatever it is handed.

def c_sub00() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("sub00", M.mo_sub(x, M.mo_const_t(x, O.CFloat{1.0})))

def c_div00() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("div00", M.mo_div(x, M.mo_const_t(x, O.CFloat{2.0})))

def c_where0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("where0", M.mo_where(M.mo_neqc(x, O.CFloat{0.0}), x, O.CFloat{0.0}))

# --- THE MOVEMENT HOIST (`mixin/movement.py`), the identity-tested wrappers.

def c_reshape0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("reshape0", M.mo_reshape(x, [M.mo_ki(2), M.mo_ki(2)]))

def c_permute0() -> IO(Unit):
  +x = M.mo_fx2d()
  M.mo_sig_t("permute0", M.mo_permute(x, [1, 0]))

def c_squeeze0() -> IO(Unit):
  +x = M.mo_fx1d()
  +y = M.mo_reshape(x, [M.mo_ki(1), M.mo_ki(4)])
  M.mo_sig_t("squeeze0", M.mo_squeeze(y, 0))

# --- THE `op.py` RECIPES. The twelve defs `mixin-op-gate` covers through the port's
# `main`, re-driven here so the census is one artifact over the whole layer.

def c_min0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("min0", M.mo_min(False{}, x, M.mo_ax(False{}, x, 0)))

def c_mean0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("mean0", M.mo_mean(False{}, x, M.mo_ax(False{}, x, 0)))

def c_var0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("var0", M.mo_var(False{}, 1, x, M.mo_ax(False{}, x, 0)))

def c_std0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("std0", M.mo_std(False{}, 1, x, M.mo_ax(False{}, x, 0)))

def c_varmean0_v() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("varmean0_v", M.VarMean.v(M.mo_var_mean(False{}, 1, x, M.mo_ax(False{}, x, 0))))

def c_varmean0_m() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("varmean0_m", M.VarMean.m(M.mo_var_mean(False{}, 1, x, M.mo_ax(False{}, x, 0))))

def c_stdmean0_s() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("stdmean0_s", M.StdMean.s(M.mo_std_mean(False{}, 1, x, M.mo_ax(False{}, x, 0))))

def c_stdmean0_m() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("stdmean0_m", M.StdMean.m(M.mo_std_mean(False{}, 1, x, M.mo_ax(False{}, x, 0))))

def c_norm0() -> IO(Unit):
  +x = M.mo_fx2d()
  M.mo_sig_t("norm0", M.mo_norm0(M.mo_ax(False{}, x, 0), x))

def c_lse0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("lse0", M.mo_logsumexp(False{}, x, M.mo_ax(False{}, x, 0)))

def c_lse0kd() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("lse0kd", M.mo_logsumexp(True{}, x, M.mo_ax(False{}, x, 0)))

def c_softmax0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("softmax0", M.mo_softmax(x, M.mo_ax(False{}, x, 0)))

def c_logsoftmax0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("logsoftmax0", M.mo_log_softmax(x, M.mo_ax(False{}, x, 0)))

def c_softmin0() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("softmin0", M.mo_softmin(x, M.mo_ax(False{}, x, 0)))

def c_softmax3_m() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("softmax3_m", M.Softmax3.m(M.mo_softmax3(x, M.mo_ax(False{}, x, 0))))

def c_softmax3_e() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("softmax3_e", M.Softmax3.e(M.mo_softmax3(x, M.mo_ax(False{}, x, 0))))

def c_softmax3_ss() -> IO(Unit):
  +x = M.mo_fx1d()
  M.mo_sig_t("softmax3_ss", M.Softmax3.ss(M.mo_softmax3(x, M.mo_ax(False{}, x, 0))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- c_max0()
    b : Unit <- c_max0kd()
    c : Unit <- c_sum0()
    d : Unit <- c_sum0kd()
    e : Unit <- c_prod0()
    f : Unit <- c_neg0()
    g : Unit <- c_notb0()
    h : Unit <- c_eqc0()
    i : Unit <- c_isfinite0()
    j : Unit <- c_isnan0()
    k : Unit <- c_exp0()
    k2 : Unit <- c_exp_i32()
    l : Unit <- c_log0()
    m : Unit <- c_recip0()
    n : Unit <- c_inverse0()
    n2 : Unit <- c_sub00()
    n3 : Unit <- c_div00()
    n4 : Unit <- c_where0()
    n5 : Unit <- c_reshape0()
    n6 : Unit <- c_permute0()
    n7 : Unit <- c_squeeze0()
    o : Unit <- c_min0()
    p : Unit <- c_mean0()
    q : Unit <- c_var0()
    r : Unit <- c_std0()
    s : Unit <- c_varmean0_v()
    t : Unit <- c_varmean0_m()
    u : Unit <- c_stdmean0_s()
    v : Unit <- c_stdmean0_m()
    w : Unit <- c_norm0()
    x : Unit <- c_lse0()
    y : Unit <- c_lse0kd()
    z : Unit <- c_softmax0()
    aa : Unit <- c_logsoftmax0()
    ab : Unit <- c_softmin0()
    ac : Unit <- c_softmax3_m()
    ad : Unit <- c_softmax3_e()
    ae : Unit <- c_softmax3_ss()
    return Unit{}
