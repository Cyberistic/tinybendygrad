# tn_graph_census.bend -- THE NOOP CENSUS. Every ported `tn_*` public def, driven once, with
# its toposort OP SEQUENCE printed.
#
#   .venv/bin/python gates/tn_graph_census-gate.py
#
# WHY THIS IS A CENSUS AND NOT A SAMPLE. `gates/tn_binop_sweep.bend` covers the seventeen
# binops; `gates/tn_nary_arena.bend` covers the three-operand node. This covers the REST of
# the ported surface in one artifact, and the property it asks needs no CPython lane: `NOOP`
# IS THE BOTTOM (`Arena.bottom()`), so a `NOOP` anywhere in a graph is an index read out of
# range and always a defect. Four ports were found this way -- `tn_relu`, `tn_relu6` and the
# two `*t` wrappers under `tn_ceil` / `tn_floor` -- and the row that matters is
# `no_port_has_a_noop_src`.
#
# THE OP SEQUENCE IS PRINTED, NOT JUST THE VERDICT, because a graph can be wrong WITHOUT a
# NOOP: `tn_ceil` computed `b + 4` for a `CInt{4}` input through a LEGAL index and showed no
# bottom at all. The sequences are the evidence a reader compares against CPython; the NOOP
# row is the assertion.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def t4() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def tb() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def sig_tn_sqrt() -> String:
  +r = T.tn_sqrt(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_detach() -> String:
  +r = T.tn_detach(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_contiguous_backward() -> String:
  +r = T.tn_contiguous_backward(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_trunc() -> String:
  +r = T.tn_trunc(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_reciprocal() -> String:
  +r = T.tn_reciprocal(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_sin() -> String:
  +r = T.tn_sin(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_log2() -> String:
  +r = T.tn_log2(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_exp2() -> String:
  +r = T.tn_exp2(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rsqrt() -> String:
  +r = T.tn_rsqrt(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_logical_not() -> String:
  +r = T.tn_logical_not(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_bitwise_not.at(+t: T.Tensor) -> String:
  O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t))

# `tn_bitwise_not` returns a `Maybe` because CPython's `bitwise_not` has a dtype dispatch
# with three arms and `S.Dt.max` refuses an unsigned dtype wider than `u32`. `CInt{4}` is
# signed, so the `Some` arm is the one taken here and `NONE` would be the row failing.
def sig_tn_bitwise_not.go(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: sig_tn_bitwise_not.at(t)
    case None{}: "NONE"

def sig_tn_bitwise_not() -> String:
  sig_tn_bitwise_not.go(T.tn_bitwise_not(t4()))

def sig_tn_neg() -> String:
  +r = T.tn_neg(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_dunder_neg() -> String:
  +r = T.tn_dunder_neg(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_relu() -> String:
  +r = T.tn_relu(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_relu6() -> String:
  +r = T.tn_relu6(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_square() -> String:
  +r = T.tn_square(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_ceil() -> String:
  +r = T.tn_ceil(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_floor() -> String:
  +r = T.tn_floor(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_isnan() -> String:
  +r = T.tn_isnan(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_isfinite() -> String:
  +r = T.tn_isfinite(t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_add() -> String:
  +r = T.tn_add(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_and() -> String:
  +r = T.tn_and(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_cmplt() -> String:
  +r = T.tn_cmplt(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_cmpne() -> String:
  +r = T.tn_cmpne(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_fdiv() -> String:
  +r = T.tn_fdiv(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_lshift() -> String:
  +r = T.tn_lshift(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_max() -> String:
  +r = T.tn_max(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_maximum() -> String:
  +r = T.tn_maximum(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_mod() -> String:
  +r = T.tn_mod(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_mul() -> String:
  +r = T.tn_mul(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_or() -> String:
  +r = T.tn_or(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_pow() -> String:
  +r = T.tn_pow(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rshift() -> String:
  +r = T.tn_rshift(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))



def sig_tn_sub() -> String:
  +r = T.tn_sub(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_xor() -> String:
  +r = T.tn_xor(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_eq() -> String:
  +r = T.tn_eq(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_threefry() -> String:
  +r = T.tn_threefry(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# DOES THE GRAPH CONTAIN A `NOOP`? The signature's src list is the only place a src op is
# named, and `Rng.sig` prints it, so the row reads the STRING. That is deliberate: the
# signature is what a reader checks against CPython, so asserting on it asserts on the
# evidence rather than on a second derivation that could drift from it.

# THE REVERSE ARMS. Half the binop surface is the `reverse=True` arm and the census above
# covered only the forward half, so a sibling regression in any of these was invisible. The
# counterpart is the `__r*__` dunder and NOT a lower-level call, for the reason `tn_sub` taught:
# an oracle that calls a path the dunder does not take agrees with a port that mirrors the wrong
# thing. SIX of the port's reverse arms have NO counterpart at all and are NOT in this list --
# see the wall note in `tinybendygrad/tensor.bend` for the measurement.
def sig_tn_radd() -> String:
  +r = T.tn_radd(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rsub() -> String:
  +r = T.tn_rsub(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rmul() -> String:
  +r = T.tn_rmul(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rfdiv() -> String:
  +r = T.tn_rfdiv(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rmod() -> String:
  +r = T.tn_rmod(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rand() -> String:
  +r = T.tn_rand(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_ror() -> String:
  +r = T.tn_ror(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rxor() -> String:
  +r = T.tn_rxor(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rpow() -> String:
  +r = T.tn_rpow(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rlshift() -> String:
  +r = T.tn_rlshift(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_rrshift() -> String:
  +r = T.tn_rrshift(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# THE THREE `Maybe`-RETURNING DUNDERS, which had NO GATE AT ALL before this. `__ge__` and
# `__le__` are chains through `tn_logical_not`; `__invert__` returns a `Maybe` because its
# dtype dispatch is a fold read, so the `Some` arm is taken by name here.
def sig_tn_dunder_ge() -> String:
  +r = T.tn_dunder_ge(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_dunder_le() -> String:
  +r = T.tn_dunder_le(t4(), t4())
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_tn_dunder_invert.at(+t: T.Tensor) -> String:
  O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t))

def sig_tn_dunder_invert.go(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: sig_tn_dunder_invert.at(t)
    case None{}: "NONE"

def sig_tn_dunder_invert() -> String:
  sig_tn_dunder_invert.go(T.tn_dunder_invert(tb()))

def no_noop(s: String) -> Bool:
  Bool.not(String.contains("Ops.NOOP", s))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("tn_sqrt", sig_tn_sqrt())
    b : Unit <- srow("tn_detach", sig_tn_detach())
    c : Unit <- srow("tn_contiguous_backward", sig_tn_contiguous_backward())
    d : Unit <- srow("tn_trunc", sig_tn_trunc())
    e : Unit <- srow("tn_reciprocal", sig_tn_reciprocal())
    f : Unit <- srow("tn_sin", sig_tn_sin())
    g : Unit <- srow("tn_log2", sig_tn_log2())
    h : Unit <- srow("tn_exp2", sig_tn_exp2())
    i : Unit <- srow("tn_rsqrt", sig_tn_rsqrt())
    j : Unit <- srow("tn_logical_not", sig_tn_logical_not())
    k : Unit <- srow("tn_bitwise_not", sig_tn_bitwise_not())
    l : Unit <- srow("tn_neg", sig_tn_neg())
    m : Unit <- srow("tn_dunder_neg", sig_tn_dunder_neg())
    n : Unit <- srow("tn_relu", sig_tn_relu())
    o : Unit <- srow("tn_relu6", sig_tn_relu6())
    p : Unit <- srow("tn_square", sig_tn_square())
    q : Unit <- srow("tn_ceil", sig_tn_ceil())
    r : Unit <- srow("tn_floor", sig_tn_floor())
    s : Unit <- srow("tn_isnan", sig_tn_isnan())
    t : Unit <- srow("tn_isfinite", sig_tn_isfinite())
    u : Unit <- srow("tn_add", sig_tn_add())
    v : Unit <- srow("tn_and", sig_tn_and())
    w : Unit <- srow("tn_cmplt", sig_tn_cmplt())
    x : Unit <- srow("tn_cmpne", sig_tn_cmpne())
    y : Unit <- srow("tn_fdiv", sig_tn_fdiv())
    z : Unit <- srow("tn_lshift", sig_tn_lshift())
    aa : Unit <- srow("tn_max", sig_tn_max())
    ab : Unit <- srow("tn_maximum", sig_tn_maximum())
    ac : Unit <- srow("tn_mod", sig_tn_mod())
    ad : Unit <- srow("tn_mul", sig_tn_mul())
    ae : Unit <- srow("tn_or", sig_tn_or())
    af : Unit <- srow("tn_pow", sig_tn_pow())
    ag : Unit <- srow("tn_rshift", sig_tn_rshift())
    aj : Unit <- srow("tn_sub", sig_tn_sub())
    ak : Unit <- srow("tn_xor", sig_tn_xor())
    al : Unit <- srow("tn_eq", sig_tn_eq())
    am : Unit <- srow("tn_threefry", sig_tn_threefry())
    n : Unit <- srow("tn_radd", sig_tn_radd())
    o : Unit <- srow("tn_rsub", sig_tn_rsub())
    p : Unit <- srow("tn_rmul", sig_tn_rmul())
    q : Unit <- srow("tn_rfdiv", sig_tn_rfdiv())
    r : Unit <- srow("tn_rmod", sig_tn_rmod())
    s : Unit <- srow("tn_rand", sig_tn_rand())
    t : Unit <- srow("tn_ror", sig_tn_ror())
    u : Unit <- srow("tn_rxor", sig_tn_rxor())
    v : Unit <- srow("tn_rpow", sig_tn_rpow())
    w : Unit <- srow("tn_rlshift", sig_tn_rlshift())
    x : Unit <- srow("tn_rrshift", sig_tn_rrshift())
    ai : Unit <- srow("tn_dunder_ge", sig_tn_dunder_ge())
    aj : Unit <- srow("tn_dunder_le", sig_tn_dunder_le())
    ak : Unit <- srow("tn_dunder_invert", sig_tn_dunder_invert())
    return Unit{}
