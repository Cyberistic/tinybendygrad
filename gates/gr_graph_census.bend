# gr_graph_census.bend -- A GRAPH CENSUS over the ported `pm_gradient` RULE TABLE in
# `tinybendygrad/mixin/gradient.bend`: each graph-producing rule driven once through the
# REAL matcher (`gr_rewrite`), with the DEEP toposort OP SEQUENCE of every gradient it
# answers printed in the format CPython's `pm_gradient.rewrite` produces.
#
#   .venv/bin/python gates/gr_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED, AND IT IS THE TABLE'S OWN DECLARATION.
#
#   grep -o '^def gr[a-z_0-9]*' tinybendygrad/mixin/gradient.bend | sort -u    # 48 names
#
# The 48 are the 33 RULES `gr_0`..`gr_32` (one per entry of CPython's compiled `pm_gradient`),
# the four `gr_29_*` sub-defs, the ten dispatcher helpers (`gr_table`, `gr_dispatch`,
# `gr_rewrite`, `gr_scan`, `gr_try`, `gr_claimed`, `gr_rej`, `gr_ler`, `gr_e27`,
# `gr_e29`) and the node-builder `grecip`. The RULES are discovered against CPython's own
# table, not a list here: `sum(len(v) for v in pm_gradient.pdict.values())` is 33 -- the
# OP-KEYED compiled table, which is what the port's `gr_table()` answers and what the file's
# own `t_claims` pins (`len(pm_gradient.patterns)` is 32, the raw list).
#
# A rule is a ROW iff it ANSWERS A GRAPH. Of the 33:
#   17 build at least one non-hole gradient: 0,1,2,3,4,5,6,9,10,11,12,13,16,18,26,29,31
#    3 answer only holes, so there is no toposort to print: 7 CMPLT, 8 CMPNE, 32 BITCAST
#   13 are `GSkip{}` WALLS (no graph, TODO(p3)): 14,15,17,19,20,21,22,23,24,25,27,28,30
# The 3 all-holes rules and the 13 walls FALL OUT and are counted here: 16 of 33 dropped.
# `gr_0_r` is one VARIANT row (the CAST rule with a NON-identity target dtype); the other
# 16 are one row per rule. 17 rules -> 18 rows. THE WALK (`compute_gradient`/`_deepwalk`,
# driven through the port's own `dag_*` readers) adds 14 rows: 18 + 14 = 32.
#
# THE PRINTER IS THE DEEP TOPOSORT SEQUENCE, NOT `O.Rng.sig`, AND THE REASON IS MEASURED.
# `Rng.sig` prints the node COUNT, the root op, the root nsrc and the SRC op sequence, and
# that is BLIND here: `gr_10`'s slot 0 (the POW `dx`) is missing the `e *` factor AND its
# `e-1` is spelled `1-e`, and CPython's tree differs -- yet BOTH print
# `15 Ops.MUL/2 Ops.CAST Ops.WHERE`, because the port's extra `CAST(CONST 0.0)` and its
# missing `MUL(e, POW)` CANCEL in the COUNT. The deep sequence (`<count> <op>/<nsrc> ...`
# over the whole toposort, `mo_sig`'s format) shows the tree, and the oracle reproduces it
# with one `toposort()` join. NOTHING IS EXECUTED.
#
# THE FIXTURE IS THIS FILE'S OWN, AND THE OPERANDS ARE DISTINCT. `gradient.bend`'s own
# `fix()` uses `n1 = CONST 1.0` for EVERY operand, so its POW exponent `e` IS the `1` the
# rule subtracts and `gsub(o, e)` is indistinguishable from `gsub(e, o)` -- a src-swap the
# fixture cannot see. Here `ctx` is 1.0, the base `b` is 3.0 and the exponent `e` is 4.0,
# all distinct, so an operand swap moves a row. One arena holds every node.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/mixin/gradient.bend as G

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE DEEP PRINTER. `mo_sig.of` (op.bend:1141) is the same string; it is SPELLED here
# rather than imported because importing `op.bend` alongside `gradient.bend` is a second
# port file's worth of tables for one six-line fold, and `mo_sig` reads a `T.Tensor` while
# a gradient is an arena and an index.
def dsig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: dsig.go(t, ar, String.concat([acc,
      O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u)), " "]))

def dsig(+ar: O.Arena, i: U32) -> String:
  +xs = O.UOp.toposort(O.Arena.budget(ar), ar, i)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " ", dsig.go(xs, ar, "")])

# ONE SLOT'S SIGNATURE. `+r` because `gs_ar` and `gs_get` are two reads of one `GRes`.
def jsig(+r: G.GRes, k: Nat) -> String:
  dsig(G.gs_ar(r), G.gs_get(r, k))

# ===========================================================================
# THE FIXTURE -- ONE arena, every node, operands DISTINCT. The field names are the RULE
# TAGS ("which rule does this node hit") plus `c1` (the ctx seed).
# ===========================================================================
type W is Data:
  W{ar: O.Arena, c1: U32, t0: U32, t0r: U32, t1: U32, t2: U32, t3: U32, t4: U32, t5: U32,
    t6: U32, t9: U32, t10: U32, t11: U32, t12: U32, t13: U32, t16: U32, t18: U32, t26: U32,
    t29: U32, t31: U32}

def W.ar(x: W) -> O.Arena:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: ar
def W.c1(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: c1
def W.t0(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t0
def W.t0r(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t0r
def W.t1(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t1
def W.t2(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t2
def W.t3(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t3
def W.t4(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t4
def W.t5(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t5
def W.t6(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t6
def W.t9(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t9
def W.t10(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t10
def W.t11(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t11
def W.t12(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t12
def W.t13(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t13
def W.t16(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t16
def W.t18(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t18
def W.t26(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t26
def W.t29(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t29
def W.t31(x: W) -> U32:
  match x:
    case W{ar, c1, t0, t0r, t1, t2, t3, t4, t5, t6, t9, t10, t11, t12, t13, t16, t18, t26, t29, t31}: t31

# `c1` = CONST 1.0 (the ctx), `c3` = CONST 3.0, `c4` = CONST 4.0, `ci` = a BARE weakint 4.
# `t0` is `CAST(c1, int32)` -- the src dtype is c1's f32, so `ctx.cast(f32)` is IDENTITY and
# CPython folds it; `t0r` is `CAST(ci, int32)` -- the src dtype is weakint, so the cast is
# REAL and both lanes must build it. Both are rows, and the pair separates the fold from
# the rule.
def world() -> W:
  +c1 = G.gconst(O.Arena.empty(), O.CFloat{1.0})
  +c3 = G.gconst(O.Found.ar(c1), O.CFloat{3.0})
  +c4 = G.gconst(O.Found.ar(c3), O.CFloat{4.0})
  +ci = G.gconst_raw(O.Found.ar(c4), O.CInt{H.i64_of_i32(4)})
  +t0 = G.gcast(O.Found.ar(ci), O.Found.i(c1), S.int32())
  +t0r = G.gcast(O.Found.ar(t0), O.Found.i(ci), S.int32())
  +t1 = G.grecip(O.Found.ar(t0r), O.Found.i(c3))
  +t2 = G.gsin(O.Found.ar(t1), O.Found.i(c3))
  +t3 = G.glog2(O.Found.ar(t2), O.Found.i(c3))
  +t4 = G.gexp2(O.Found.ar(t3), O.Found.i(c3))
  +t5 = G.gsqrt(O.Found.ar(t4), O.Found.i(c3))
  +t6 = G.gtrunc(O.Found.ar(t5), O.Found.i(c3))
  +t9 = G.gadd(O.Found.ar(t6), O.Found.i(c3), O.Found.i(c4))
  +t10 = G.gpow(O.Found.ar(t9), O.Found.i(c3), O.Found.i(c4))
  +t11 = G.gnew(O.Found.ar(t10), O.OpsMAX{}, [O.Found.i(c3), O.Found.i(c4)], O.ANone{})
  +t12 = G.gmul(O.Found.ar(t11), O.Found.i(c3), O.Found.i(c4))
  +t13 = G.gwhere(O.Found.ar(t12), O.Found.i(c1), O.Found.i(c3), O.Found.i(c4))
  +t16 = G.gnew(O.Found.ar(t13), O.OpsSTAGE{}, [O.Found.i(c3)], O.ANone{})
  +t18 = G.gnew(O.Found.ar(t16), O.OpsEXPAND{}, [O.Found.i(c3)], O.ANone{})
  +t26 = O.UOp.sink(O.Found.ar(t18), [O.Found.i(c3), O.Found.i(c4)])
  +s29 = G.gnew(O.Found.ar(t26), O.OpsSTORE{}, [O.Found.i(G.fx_buf(O.Found.ar(t26), 0)), O.Found.i(c3)], O.ANone{})
  +t29 = G.gnew(O.Found.ar(s29), O.OpsAFTER{}, [O.Found.i(G.fx_buf(O.Found.ar(t26), 0)), O.Found.i(s29)], O.ANone{})
  +t31 = G.gnew(O.Found.ar(t29), O.OpsSTORE{}, [O.Found.i(c3), O.Found.i(c4)], O.ANone{})
  W{O.Found.ar(t31), O.Found.i(c1), O.Found.i(t0), O.Found.i(t0r), O.Found.i(t1), O.Found.i(t2),
    O.Found.i(t3), O.Found.i(t4), O.Found.i(t5), O.Found.i(t6), O.Found.i(t9), O.Found.i(t10),
    O.Found.i(t11), O.Found.i(t12), O.Found.i(t13), O.Found.i(t16), O.Found.i(t18), O.Found.i(t26),
    O.Found.i(t29), O.Found.i(t31)}

# ===========================================================================
# THE ROWS. One def per rule, driven through `G.gr_rewrite` (the real first-wins scan
# over `gr_table()`). The slot list is the rule's OWN non-hole slots; `gs_get` on a hole
# answers 0, so a wrong slot would print the NOOP bottom and `no_noop` at the foot fails.
# ===========================================================================
def sig_gr_0() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t0(w)), 0n)

def sig_gr_0_r() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t0r(w)), 0n)

def sig_gr_1() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t1(w)), 0n)

def sig_gr_2() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t2(w)), 0n)

def sig_gr_3() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t3(w)), 0n)

def sig_gr_4() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t4(w)), 0n)

def sig_gr_5() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t5(w)), 0n)

def sig_gr_6() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t6(w)), 0n)

def sig_gr_9() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t9(w))
  String.concat([jsig(r, 0n), " | ", jsig(r, 1n)])

def sig_gr_10() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t10(w))
  String.concat([jsig(r, 0n), " | ", jsig(r, 1n)])

def sig_gr_11() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t11(w))
  String.concat([jsig(r, 0n), " | ", jsig(r, 1n)])

def sig_gr_12() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t12(w))
  String.concat([jsig(r, 0n), " | ", jsig(r, 1n)])

def sig_gr_13() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t13(w))
  String.concat([jsig(r, 1n), " | ", jsig(r, 2n)])

def sig_gr_16() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t16(w)), 0n)

def sig_gr_18() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t18(w)), 0n)

# SINK's answer is `ctx.src`, so the ctx is a SINK -- what `compute_gradient` seeds a SINK
# node's gradient with (`UOp.sink(*grad_args)`).
def sig_gr_26() -> String:
  +w = world()
  +r = G.gr_rewrite(G.gr_table(), W.ar(w), W.t26(w), W.t26(w))
  String.concat([jsig(r, 0n), " | ", jsig(r, 1n)])

def sig_gr_29() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t29(w)), 1n)

def sig_gr_31() -> String:
  +w = world()
  jsig(G.gr_rewrite(G.gr_table(), W.ar(w), W.c1(w), W.t31(w)), 1n)

# ===========================================================================
# THE WALK -- `compute_gradient` (gradient.py:116-145) and `_deepwalk` (:109-114). The port
# already ships these readers (`dag_*`), so the census DRIVES THEM rather than reimplementing
# them; the CPython lane is `compute_gradient`/`_deepwalk` on the same DAG. This is the half
# of the layer the rule rows above cannot see: the ACCUMULATE (`grads[k] = grads[k] + v`,
# gradient.py:134-138) is reached only by a node with TWO parents, and `dag_grad_a` answers
# `5 root=ADD/2` where a fresh insert answers the MUL. `dag`'s DAG is the file's own fixture.
# ===========================================================================
def sig_walk_sig() -> String: G.dag_walk_sig()
def sig_walk_inpath() -> String: G.dag_inpath()
def sig_walk_keys() -> String: G.dag_keys()
def sig_walk_grad_a() -> String: G.dag_grad_a(G.walk_dag())
def sig_walk_grad_b() -> String: G.dag_grad_b(G.walk_dag())
def sig_walk_grad_c() -> String: G.dag_grad_c(G.walk_dag())
def sig_walk_grad_p() -> String: G.dag_grad_p(G.walk_dag())
def sig_walk_grad_q() -> String: G.dag_grad_q(G.walk_dag())
def sig_walk_grad_r() -> String: G.dag_grad_r(G.walk_dag())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("gr_0", sig_gr_0())
    b : Unit <- srow("gr_0_r", sig_gr_0_r())
    c : Unit <- srow("gr_1", sig_gr_1())
    d : Unit <- srow("gr_2", sig_gr_2())
    e : Unit <- srow("gr_3", sig_gr_3())
    f : Unit <- srow("gr_4", sig_gr_4())
    g : Unit <- srow("gr_5", sig_gr_5())
    h : Unit <- srow("gr_6", sig_gr_6())
    i : Unit <- srow("gr_9", sig_gr_9())
    j : Unit <- srow("gr_10", sig_gr_10())
    k : Unit <- srow("gr_11", sig_gr_11())
    l : Unit <- srow("gr_12", sig_gr_12())
    m : Unit <- srow("gr_13", sig_gr_13())
    n : Unit <- srow("gr_16", sig_gr_16())
    o : Unit <- srow("gr_18", sig_gr_18())
    p : Unit <- srow("gr_26", sig_gr_26())
    q : Unit <- srow("gr_29", sig_gr_29())
    r : Unit <- srow("gr_31", sig_gr_31())
    s : Unit <- srow("walk_sig", sig_walk_sig())
    t : Unit <- srow("walk_inpath", sig_walk_inpath())
    u : Unit <- srow("walk_keys", sig_walk_keys())
    v : Unit <- srow("walk_grad_a", sig_walk_grad_a())
    w : Unit <- srow("walk_grad_b", sig_walk_grad_b())
    x : Unit <- srow("walk_grad_c", sig_walk_grad_c())
    y : Unit <- srow("walk_grad_p", sig_walk_grad_p())
    z : Unit <- srow("walk_grad_q", sig_walk_grad_q())
    aa : Unit <- srow("walk_grad_r", sig_walk_grad_r())
    ab : Unit <- srow("walk_walk_n", U32.show(G.dag_walk_n()))
    ac : Unit <- srow("walk_grads_n", U32.show(G.dag_grads_n()))
    ad : Unit <- srow("walk_skip_n", U32.show(G.dag_skip_n()))
    ae : Unit <- srow("walk_hole_n", U32.show(G.dag_hole_n()))
    af : Unit <- srow("walk_n_inpath", U32.show(G.dag_n_inpath()))
    return Unit{}
