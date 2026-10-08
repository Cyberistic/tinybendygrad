# ew_graph_census.bend -- A GRAPH CENSUS over every ported PUBLIC `ew_*` in
# `tinybendygrad/mixin/elementwise.bend`: each driven once, with its toposort OP SEQUENCE
# printed.
#
#   .venv/bin/python gates/ew_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED. `ew_<n>` is a row iff CPython's `tinygrad/mixin/elementwise.py`
# defines a METHOD `<n>(self` or `__<n>__(self` -- 43 of the file's 142 `ew_*` defs. The other
# 99 are the plumbing (`ew_join`, `ew_binop`, `ew_promote`, `ew_remint`, the gate's own
# printers, the fixtures). `promote` and `remint` are excluded by the SAME rule and for the
# same reason: they are not methods (`def promote(t)`, `def remint(u, dt)`), so their effect
# is only visible THROUGH a binop and is covered by `ew_promo_*` in the file's own gate.
#
# THE FIXTURE IS A THREADED ARENA, NOT `t4()` TWICE. This is the one place the census cannot
# copy `gates/tn_graph_census.bend` verbatim, and the reason is MEASURED. The `tn_*` layer
# merges two operand arenas by CONTENT (`O.Arena.merge`), so `tn_add(t4(), t4())` is sound
# however the operands were built. The `ew_*` layer merges by LENGTH (`ew_join` -> `ew_newer`),
# so two operands from two `Arena.empty()`s collapse to whichever node the longer arena holds
# at that index -- harmless when both nodes are the SAME `CONST 4` (which is why the sibling
# census's `t4()` twice worked), WRONG the moment they differ. `world()` builds CONST 4,
# CONST 7 and bool-True in ONE arena and hands out all three, which is the port's own contract
# ("a pair that is a prefix pair by construction") and the shape `gates/ew-consts.bend` drives
# through `ew_i32`. See the FINDING block at the foot for the sibling-arena measurement.
#
# WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
# anywhere in a graph is an index read out of range and always a defect. The sibling census
# found four ports this way; this one finds none, which is a measurement and not an absence.
#
# THE OP SEQUENCE IS PRINTED, NOT JUST THE VERDICT, because a graph can be wrong WITHOUT a
# NOOP: `ew_floor` builds a LEGAL index that names the constant `-1` where CPython names
# `b - 1`, and no bottom check can see it. That is the whole reason this lane exists next to
# the file's own value gate.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/elementwise.bend as E

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE WORLD: three nodes in ONE arena. `a` = CONST 4, `b` = CONST 7, `c` = bool True. Every
# row takes what it needs from here, so no row can accidentally hand an `ew_*` a sibling arena.
type Cw is Data:
  Cw{a: T.Tensor, b: T.Tensor, c: T.Tensor}

def Cw.a(x: Cw) -> T.Tensor:
  match x:
    case Cw{a, b, c}: a

def Cw.b(x: Cw) -> T.Tensor:
  match x:
    case Cw{a, b, c}: b

def Cw.c(x: Cw) -> T.Tensor:
  match x:
    case Cw{a, b, c}: c

def world() -> Cw:
  +n0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +n1 = O.UOp.const(O.Found.ar(n0), O.CInt{H.i64_of_i32(7)})
  +n2 = O.UOp.const(O.Found.ar(n1), O.CBool{True{}})
  +ar = O.Found.ar(n2)
  Cw{T.Tensor{ar, O.Found.i(n0), True{}, 0},
     T.Tensor{ar, O.Found.i(n1), True{}, 0},
     T.Tensor{ar, O.Found.i(n2), True{}, 0}}

# A MIXED-DTYPE FIXTURE, AND IT IS THE ONLY ONE THAT CAN SEE THE `mod` DISPATCH. `world()`
# holds three INT/BOOL consts, so `is_int(a) and is_int(b)` is True for every pair it can
# hand out and the float arm is unreachable. Here an INT and a FLOAT sit in ONE arena, which
# is the port's own contract (a prefix pair), and PROMOTION CHANGES THE ANSWER:
#
#   dtypes.is_int(int32)                      -> True     (the UNPROMOTED read)
#   is_int(f32) and is_int(f32) after promote -> False    (what CPython tests)
#
# so `int % float` must take the FLOAT arm. MEASURED in the oracle lane, where CPython is
# asked the same question.
def wmix() -> Cw:
  +n0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +n1 = O.UOp.const(O.Found.ar(n0), O.CFloat{2.5})
  Cw{T.Tensor{O.Found.ar(n1), O.Found.i(n0), True{}, 0},
     T.Tensor{O.Found.ar(n1), O.Found.i(n1), True{}, 0},
     T.Tensor{O.Found.ar(n1), O.Found.i(n0), True{}, 0}}

# --- unary ---------------------------------------------------------------
def sig_ew_bitwise_not() -> String:
  +w = world()
  +r = E.ew_bitwise_not(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_contiguous_backward() -> String:
  +w = world()
  +r = E.ew_contiguous_backward(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_detach() -> String:
  +w = world()
  +r = E.ew_detach(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_exp() -> String:
  +w = world()
  +r = E.ew_exp(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_exp2() -> String:
  +w = world()
  +r = E.ew_exp2(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_floor() -> String:
  +w = world()
  +r = E.ew_floor(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_log() -> String:
  +w = world()
  +r = E.ew_log(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_log10() -> String:
  +w = world()
  +r = E.ew_log10(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_log2() -> String:
  +w = world()
  +r = E.ew_log2(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_logical_not() -> String:
  +w = world()
  +r = E.ew_logical_not(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_neg() -> String:
  +w = world()
  +r = E.ew_neg(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_quick_gelu() -> String:
  +w = world()
  +r = E.ew_quick_gelu(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_reciprocal() -> String:
  +w = world()
  +r = E.ew_reciprocal(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_sigmoid() -> String:
  +w = world()
  +r = E.ew_sigmoid(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_silu() -> String:
  +w = world()
  +r = E.ew_silu(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_sin() -> String:
  +w = world()
  +r = E.ew_sin(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_sqrt() -> String:
  +w = world()
  +r = E.ew_sqrt(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_square() -> String:
  +w = world()
  +r = E.ew_square(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_swish() -> String:
  +w = world()
  +r = E.ew_swish(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_tanh() -> String:
  +w = world()
  +r = E.ew_tanh(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_trunc() -> String:
  +w = world()
  +r = E.ew_trunc(Cw.a(w))
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# --- binary --------------------------------------------------------------
def sig_ew_add() -> String:
  +w = world()
  +r = E.ew_add(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_bitwise_and() -> String:
  +w = world()
  +r = E.ew_bitwise_and(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_bitwise_or() -> String:
  +w = world()
  +r = E.ew_bitwise_or(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_bitwise_xor() -> String:
  +w = world()
  +r = E.ew_bitwise_xor(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_div() -> String:
  +w = world()
  +r = E.ew_div(Cw.a(w), E.ETen{Cw.b(w)}, False{}, E.RNone{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_eq() -> String:
  +w = world()
  +r = E.ew_eq(Cw.a(w), E.ETen{Cw.b(w)})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_fmod() -> String:
  +w = world()
  +r = E.ew_fmod(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_ge() -> String:
  +w = world()
  +r = E.ew_ge(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_gt() -> String:
  +w = world()
  +r = E.ew_gt(Cw.a(w), E.ETen{Cw.b(w)})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_lshift() -> String:
  +w = world()
  +r = E.ew_lshift(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_lt() -> String:
  +w = world()
  +r = E.ew_lt(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_maximum() -> String:
  +w = world()
  +r = E.ew_maximum(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_mod_mixed() -> String:
  +w = wmix()
  +r = E.ew_mod(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_fmod_mixed() -> String:
  +w = wmix()
  +r = E.ew_fmod(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_mod() -> String:
  +w = world()
  +r = E.ew_mod(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_mul() -> String:
  +w = world()
  +r = E.ew_mul(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_ne() -> String:
  +w = world()
  +r = E.ew_ne(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_pow() -> String:
  +w = world()
  +r = E.ew_pow(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_rshift() -> String:
  +w = world()
  +r = E.ew_rshift(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_sub() -> String:
  +w = world()
  +r = E.ew_sub(Cw.a(w), E.ETen{Cw.b(w)}, False{})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_threefry() -> String:
  +w = world()
  +r = E.ew_threefry(Cw.a(w), E.ETen{Cw.b(w)})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# --- ternary -------------------------------------------------------------
def sig_ew_masked_fill() -> String:
  +w = world()
  +r = E.ew_masked_fill(Cw.a(w), Cw.c(w), E.ETen{Cw.b(w)})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

def sig_ew_where() -> String:
  +w = world()
  +r = E.ew_where(Cw.c(w), E.ETen{Cw.a(w)}, E.ETen{Cw.b(w)})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# --- the one method that BUILDS a const ----------------------------------
def sig_ew_ufix() -> String:
  +w = world()
  +r = E.ew_ufix(Cw.a(w), E.ECon{O.CInt{H.i64_of_i32(7)}})
  O.Rng.sig(T.Tensor.ar(r), T.Tensor.u(r))

# DOES THE GRAPH CONTAIN A `NOOP`? `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP` in
# any row is an index read out of range and always a defect. The assertion is PYTHON-side and
# reads the LANE'S OWN OUTPUT (`gates/artifacts/ew_graph_census-gate/bd.out`) rather than a
# second derivation that could drift from it -- see the `checks=` argument in the gate. The
# sibling census DEFINES this predicate and never calls it; here it is wired.

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ew_add", sig_ew_add())
    b : Unit <- srow("ew_bitwise_and", sig_ew_bitwise_and())
    c : Unit <- srow("ew_bitwise_not", sig_ew_bitwise_not())
    d : Unit <- srow("ew_bitwise_or", sig_ew_bitwise_or())
    e : Unit <- srow("ew_bitwise_xor", sig_ew_bitwise_xor())
    f : Unit <- srow("ew_contiguous_backward", sig_ew_contiguous_backward())
    g : Unit <- srow("ew_detach", sig_ew_detach())
    h : Unit <- srow("ew_div", sig_ew_div())
    i : Unit <- srow("ew_eq", sig_ew_eq())
    j : Unit <- srow("ew_exp", sig_ew_exp())
    k : Unit <- srow("ew_exp2", sig_ew_exp2())
    l : Unit <- srow("ew_floor", sig_ew_floor())
    m : Unit <- srow("ew_fmod", sig_ew_fmod())
    n : Unit <- srow("ew_ge", sig_ew_ge())
    o : Unit <- srow("ew_gt", sig_ew_gt())
    p : Unit <- srow("ew_log", sig_ew_log())
    q : Unit <- srow("ew_log10", sig_ew_log10())
    r : Unit <- srow("ew_log2", sig_ew_log2())
    s : Unit <- srow("ew_logical_not", sig_ew_logical_not())
    t : Unit <- srow("ew_lshift", sig_ew_lshift())
    u : Unit <- srow("ew_lt", sig_ew_lt())
    v : Unit <- srow("ew_masked_fill", sig_ew_masked_fill())
    w : Unit <- srow("ew_maximum", sig_ew_maximum())
    x : Unit <- srow("ew_mod", sig_ew_mod())
    y : Unit <- srow("ew_mul", sig_ew_mul())
    z : Unit <- srow("ew_ne", sig_ew_ne())
    aa : Unit <- srow("ew_neg", sig_ew_neg())
    ab : Unit <- srow("ew_pow", sig_ew_pow())
    ac : Unit <- srow("ew_quick_gelu", sig_ew_quick_gelu())
    ad : Unit <- srow("ew_reciprocal", sig_ew_reciprocal())
    ae : Unit <- srow("ew_rshift", sig_ew_rshift())
    af : Unit <- srow("ew_sigmoid", sig_ew_sigmoid())
    ag : Unit <- srow("ew_silu", sig_ew_silu())
    ah : Unit <- srow("ew_sin", sig_ew_sin())
    ai : Unit <- srow("ew_sqrt", sig_ew_sqrt())
    aj : Unit <- srow("ew_square", sig_ew_square())
    ak : Unit <- srow("ew_sub", sig_ew_sub())
    al : Unit <- srow("ew_swish", sig_ew_swish())
    am : Unit <- srow("ew_tanh", sig_ew_tanh())
    an : Unit <- srow("ew_threefry", sig_ew_threefry())
    ao : Unit <- srow("ew_trunc", sig_ew_trunc())
    ap : Unit <- srow("ew_ufix", sig_ew_ufix())
    aq : Unit <- srow("ew_where", sig_ew_where())
    y : Unit <- srow("ew_mod_mixed", sig_ew_mod_mixed())
    z : Unit <- srow("ew_fmod_mixed", sig_ew_fmod_mixed())
    return Unit{}

# ===========================================================================
# FINDING: `ew_join` MERGES OPERAND ARENAS BY LENGTH, NOT BY CONTENT.
#
# MEASURED, two ways. (1) On the sibling fixture (`t4()` twice, exactly what
# `gates/tn_graph_census.bend` uses), `ew_add(t4(), ETen{t4()}, False{})` prints
# `2 Ops.ADD/2 Ops.CONST Ops.CONST` -- CORRECT only because both nodes are the same CONST 4.
# (2) A temporary probe row, `ew_add` against a `CInt 7` from its OWN `Arena.empty()`, printed
# `probe_sib_add=2 Ops.ADD/2 Ops.CONST Ops.CONST` where CPython's `t4().add(t7())` is
# `3 Ops.ADD/2 Ops.CONST Ops.CONST`: the 7 collapsed onto the 4. The census's first draft made
# the same collapse with three operands -- `ew_masked_fill=2 Ops.WHERE/3 Ops.CONST Ops.CONST
# Ops.CONST` against CPython's `3 Ops.WHERE/3 ...` -- because `ew_newer` picked a 1-node arena
# and rebased all three indices into it.
#
# THIS IS NOT A ROW AND IT IS NOT PINNED, and it is NOT SMOOTHED EITHER: it is recorded
# because the fair fixture above is exactly what HIDES it. The reachability is NOT established
# here and is left as the open half. The BINARY `ew_*` surface is NOT confined to this file:
#   `mixin/op.bend:986` `mo_isnan` calls `E.ew_ne(t, ETen{t})` -- the SAME tensor twice, which
#     is the harmless case; and
#   `mixin/rand.bend:428` `rd_tfb.three` calls `E.ew_threefry(x, ETen{rd_p64(...)})` -- TWO
#     operands built by two `mo_bin` chains, whose arena relationship this unit did NOT measure.
# The rest of `op.bend`'s use of `E.*` is the UNARY defs (`ew_exp2`, `ew_sqrt`, `ew_square`,
# `ew_reciprocal`, `ew_log2`, `ew_sin`, `ew_bitwise_not`, `ew_detach`) and the readers/helpers
# (`ew_of`, `ew_remint`, `ew_cast`, `ew_base`, `ew_is_const`, `ew_promote`, `ew_dtnm`), which
# take one tensor and cannot hit `ew_join` at all. So the finding is: `ew_join` merges by
# LENGTH and collapses two DISTINCT sibling nodes, `rd_tfb.three` is the one caller that could
# feed it two, and that is where a follow-up unit should look.
# ===========================================================================
