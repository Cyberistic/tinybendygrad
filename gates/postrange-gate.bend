# gates/postrange-gate.bend -- the gate driver for `tinybendygrad/codegen/opt/postrange.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/opt/postrange.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# `apply_opt` and `P.opt_ok` take the RESOLVED amount, so a fixture states the
# amount Python would have resolved `0` to. `plus_opt(i)` is the four actions
# `get_kernel_actions` accepts on the 1-axis kernel, by their `enumerate` index.
def plus_pair(i: U32) -> O.OPTARG:
  match i:
    case 1: O.OA_SPLIT{O.SPL{4, O.AXIS_UPCAST{}, None{}}}
    case 11: O.OA_SPLIT{O.SPL{2, O.AXIS_UPCAST{}, None{}}}
    case 121: O.OA_SPLIT{O.SPL{4, O.AXIS_LOCAL{}, None{}}}
    case _: O.OA_SPLIT{O.SPL{2, O.AXIS_LOCAL{}, None{}}}

def plus_opt(i: U32) -> O.OPT:
  O.OPT{O.OPS_SPLIT{}, 0, plus_pair(i)}

def plus_ok.of(+o: O.OPT, s: P.Sched) -> Bool:
  P.opt_ok.at(s, P.Q.of(0, P.opt_amt(O.OPT.arg(o)), P.opt_target(O.OPT.arg(o))))

def plus_ok(i: U32) -> Bool:
  plus_ok.of(plus_opt(i), P.plus_sched())

# `count_bools` -- `sum(bs)`. The `P.hit` Bool is an ACCUMULATOR and not a separate
# dispatch def: a `P.hit: Bool` helper that re-calls the walk is a MUTUAL
# RECURSION and is refused, which is the shape bend2-constraints.md calls "a
# `found: Bool` accumulator is the only spelling that compiles". `n` is a `U32`
# so it is never `+` -- it is read once per arm.
def count_add(h: Bool, n: U32) -> U32:
  match h:
    case True{}: U32.add(n, 1)
    case False{}: n

def count_bools(bs: List<&2, Bool>, n: U32) -> U32:
  match bs:
    case Nil{}: n
    case h <> t: count_bools(t, count_add(h, n))

# `plus_n` -- how many of the four pass `P.opt_ok`, i.e. CPython's
# `get_kernel_actions(include_0=False)` count of 4. It is a COUNT and not four
# Booleans so a mutation that drops one of the six CONJUNCTS can move it, and
# `ok_i*` pin each candidate individually so a mutation that drops a whole
# CANDIDATE moves one of those.
def plus_n() -> U32:
  count_bools([plus_ok(1), plus_ok(11), plus_ok(121), plus_ok(129)], 0)

# `ok_local_red` -- the DROPPED conjunct. `apply_opt` reaches the `reduces`
# check when `new_type is LOCAL or rng.axis_type is REDUCE`, and CPython
# ACCEPTS a LOCAL split of the reduce axis on the 16x32 kernel, so the check is
# vacuous there. This row builds that opt and reports `P.opt_ok`'s verdict, which
# is 1 -- and it is the row a mutation that ADDS a fake reduce-conjunct moves.
def ok_local_red() -> U32:
  P.b2u(P.opt_ok.at(P.reduce_sched(), P.Q.of(1, 16, O.AXIS_LOCAL{})))

# `ok_axis_oob` -- `check(0 <= opt.axis < self.shape_len)` is NOT in `P.opt_ok.at`
# (it is `P.opt_axis_ok`, a separate arm, because TC skips it). This row is the
# FALSE arm, built by asking about an axis one past the end.
def ok_axis_oob() -> U32:
  P.b2u(P.opt_axis_ok(P.reduce_sched(), 2))

# `ok_tc_any` -- the `-1` chain. `P.REN.python()` has `n_tc = 0`, and a TC opt with
# `any = True` must still PASS the bound check, because `-1 < 0`. This row is 1
# and a mutation that drops the `Bool.or(a.any, ...)` moves it to 0 -- which is
# the bug where every TC candidate is rejected on a device with no tensor cores.
def ok_tc_any() -> U32:
  P.b2u(P.opt_ok.tc(O.TC{True{}, 0, 2, 1}, P.plus_sched(), P.n_opts(P.plus_sched())))

# `ok_tc_sel` -- the SAME check with `any = False` and `P.sel = 0`, `n_tc = 0`.
# `0 < 0` is False, so this is 0. The pair pins that `any` is doing the work and
# not the magnitude.
def ok_tc_sel() -> U32:
  P.b2u(P.opt_ok.tc(O.TC{False{}, 0, 2, 1}, P.plus_sched(), P.n_opts(P.plus_sched())))

# `ok_tc_lvl` -- `check(0 <= tc_opt <= 2)`, the FALSE arm at lvl 3.
def ok_tc_lvl() -> U32:
  P.b2u(P.opt_ok.tc(O.TC{True{}, 0, 3, 1}, P.plus_sched(), P.n_opts(P.plus_sched())))

# `ok_tc_use` -- `check(0 < use_tensor_cores <= 2)`, the FALSE arm at use 3.
def ok_tc_use() -> U32:
  P.b2u(P.opt_ok.tc(O.TC{True{}, 0, 2, 3}, P.plus_sched(), P.n_opts(P.plus_sched())))

# `ok_tc_first` -- `check(len(self.applied_opts) == 0)`. `P.Sched.split` appends,
# so a scheduler with one opt must REJECT a TC. This row is the False arm, and
# it is the row that moves if `P.Sched.split` stops appending.
def ok_tc_first() -> U32:
  P.b2u(P.opt_ok.tc(O.TC{True{}, 0, 2, 1}, P.Sched.split(P.plus_sched(), P.SPLIT_OPT(0, 2, O.AXIS_UPCAST{}, False{})), P.n_opts(P.Sched.split(P.plus_sched(), P.SPLIT_OPT(0, 2, O.AXIS_UPCAST{}, False{})))))

# `ul_plus` / `ul_red` -- `get_kernel_actions`' `up`/`lcl` on each fixture.
# CPython: after a successful SPLIT the products are over the NEW axis types,
# and on the 16x32 kernel every accepted candidate leaves `up = 1` (no
# UPCAST/UNROLL survives except the UNROLL splits, which give up = 16 or 4) and
# `lcl` at most 32. These two rows pin the accumulation, not the filter.
def ul_plus_up() -> U32:
  P.up_go(P.Sched.rngs(P.Sched.split(P.plus_sched(), P.SPLIT_OPT(0, 2, O.AXIS_LOCAL{}, False{}))), 1)

def ul_red_up() -> U32:
  P.up_go(P.Sched.rngs(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(1, 16, O.AXIS_UNROLL{}, False{}))), 1)

def ul_red_lcl() -> U32:
  P.lcl_go(P.Sched.rngs(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 1)

# `split_fs0` -- `shift_to` RESIZES the split axis. A 16-long axis split by 4 is
# 4, and the NEW range is the 4. So `full_shape` after
# `split(reduce, 0, 4, LOCAL)` is `[4, 4, 32]` -- not `[16, 4, 32]`, which is the
# mistake a mutation that appends the new rng without resizing the old one makes.
# the sizes AFTER the split, one row each, so a mutation that resizes wrongly
# moves the row for the size it moved and not the others
def split_fs_len() -> U32:
  U32.from_nat(List.length(&2, U32, P.Sched.full_shape(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{})))))

def fs_at(fs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, fs, n), 0)

def split_fs_0() -> U32:
  fs_at(P.Sched.full_shape(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 0n)

def split_fs_2() -> U32:
  fs_at(P.Sched.full_shape(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 2n)

def nolocal_sched() -> P.Sched:
  P.Sched.of(P.REN.nolocal(), [P.RNG{0, O.AXIS_GLOBAL{}, 4}])

def dsp_sched() -> P.Sched:
  P.Sched.of(P.REN.dsp(), [P.RNG{0, O.AXIS_GLOBAL{}, 128}])

# the six conjuncts, one row each, so a mutation that drops one is localised.
# Every `False` arm is a fixture CPython also rejects, and the reason is the
# message `apply_opt` would have raised.
def ck_tgt_bad() -> U32:
  # unroll on a global axis: "AxisType.upcast is from (global, local, weak)"
  P.b2u(P.ck_tgt(P.reduce_sched(), 0, O.AXIS_UNROLL{}))

def ck_tgt_ok() -> U32:
  # UNROLL on the REDUCE axis: P.split_targets[UNROLL] is (REDUCE, LOCAL)
  P.b2u(P.ck_tgt(P.reduce_sched(), 1, O.AXIS_UNROLL{}))

def ck_amt_0() -> U32:
  # amt == 0 is legal -- it means "the whole axis", and `apply_opt` resolves it
  P.b2u(P.ck_amt(0))

def ck_amt_1() -> U32:
  # amt == 1 is the ONLY rejected amount on the value half
  P.b2u(P.ck_amt(1))

def ck_amt_4() -> U32:
  P.b2u(P.ck_amt(4))

def ck_local_bad() -> U32:
  # `ClangRenderer.has_local is False`, MEASURED -- so LOCAL is unavailable
  P.b2u(P.ck_local(nolocal_sched(), O.AXIS_LOCAL{}))

def ck_local_ok() -> U32:
  # the same check on UPCAST is vacuous, which is why it is `Bool.or`
  P.b2u(P.ck_local(nolocal_sched(), O.AXIS_UPCAST{}))

def ck_unroll_32() -> U32:
  P.b2u(P.ck_unroll(O.AXIS_UNROLL{}, 32))

def ck_unroll_33() -> U32:
  P.b2u(P.ck_unroll(O.AXIS_UNROLL{}, 33))

def ck_unroll_up() -> U32:
  # `new_type is not UNROLL` short-circuits the bound entirely
  P.b2u(P.ck_unroll(O.AXIS_UPCAST{}, 33))

def ck_upcast_16() -> U32:
  P.b2u(P.ck_upcast(P.plus_sched(), O.AXIS_UPCAST{}, 16))

def ck_upcast_17() -> U32:
  # "don't upcast more than 16" -- and NOT a DSP, so the exemption does not fire
  P.b2u(P.ck_upcast(P.plus_sched(), O.AXIS_UPCAST{}, 17))

def ck_upcast_dsp() -> U32:
  # the DSP exemption: 128 is legal there, and 0 elsewhere
  P.b2u(P.ck_upcast(dsp_sched(), O.AXIS_UPCAST{}, 128))

def ck_div_4() -> U32:
  P.b2u(P.ck_div(P.plus_sched(), 0, 4))

def ck_div_3() -> U32:
  # "3 can't divide 4" -- the `divides(amount) is None` arm of `shift_to`
  P.b2u(P.ck_div(P.plus_sched(), 0, 3))

# the `rngs` sort order, and why it needs a row. `P.pos_key` is the only thing
# that separates LOCAL from UPCAST, and every other fixture on this file has at
# most ONE of the two -- a `P.Sched` that has been split once has two rngs of the
# SAME new type, and `List.sort` is STABLE, so a tie between them is invisible.
# `lu_sched` hands the sort an UPSCAST-first list and the row reads index 1: if
# `P.pos_key` tied them the answer would be 8 and not 4, which is the bug a
# mutation that collapses the two ranks ships.
def lu_sched() -> P.Sched:
  P.Sched.of(P.REN.python(), [P.RNG{0, O.AXIS_UPCAST{}, 8}, P.RNG{0, O.AXIS_LOCAL{}, 4}])

def lu_at(n: Nat) -> U32:
  fs_at(P.Sched.full_shape(lu_sched()), n)

# A SIZE-1 AXIS. Every other fixture has all sizes > 1, so `P.dim_go`'s `P.gt1`
# conjunct is invisible to them: `upcastable_unit` is 1 not 2, and it is the row
# that a mutation dropping `P.gt1` moves. CPython agrees -- `upcastable_dims`
# filters on `s > 1`, and a size-1 axis is a SPECIAL the launcher expanded, not
# an axis the scheduler may split.
def unit_sched() -> P.Sched:
  P.Sched.of(P.REN.python(), [P.RNG{0, O.AXIS_GLOBAL{}, 1}, P.RNG{0, O.AXIS_GLOBAL{}, 4}])

def upcastable_unit() -> U32:
  U32.from_nat(List.length(&2, U32, P.Sched.upcastable_dims(unit_sched())))

# `P.max_id` AFTER A SPLIT. `opt_range`'s `count(start=max+1)` exists so a fresh
# range can never TIE an existing id, and a tie is invisible to every other row
# here because no fixture has two rngs with the same id. `maxid_fresh` is 1 after
# splitting, and it is the row a mutation that reuses `P.max_id` moves.
def maxid_fresh() -> U32:
  P.Sched.max_id(P.Sched.split(P.reduce_sched(), P.SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("plus_shape_len", P.Sched.shape_len(P.plus_sched()))
    b : Unit <- row("plus_n", plus_n())
    c : Unit <- row("ok_i1", P.b2u(plus_ok(1)))
    d : Unit <- row("ok_i11", P.b2u(plus_ok(11)))
    e : Unit <- row("ok_i121", P.b2u(plus_ok(121)))
    f : Unit <- row("ok_i129", P.b2u(plus_ok(129)))
    g : Unit <- row("ok_local_red", ok_local_red())
    h : Unit <- row("ok_axis_oob", ok_axis_oob())
    i : Unit <- row("ok_tc_any", ok_tc_any())
    j : Unit <- row("ok_tc_sel", ok_tc_sel())
    k : Unit <- row("ok_tc_lvl", ok_tc_lvl())
    l : Unit <- row("ok_tc_use", ok_tc_use())
    m : Unit <- row("ok_tc_first", ok_tc_first())
    n : Unit <- row("upcastable_plus", U32.from_nat(List.length(&2, U32, P.Sched.upcastable_dims(P.plus_sched()))))
    o : Unit <- row("unrollable_red", U32.from_nat(List.length(&2, U32, P.Sched.unrollable_dims(P.reduce_sched()))))
    p : Unit <- row("axes_global_red", U32.from_nat(List.length(&2, U32, P.Sched.axes_of(P.reduce_sched(), [O.AXIS_GLOBAL{}]))))
    q : Unit <- row("upcast_size_plus", P.Sched.upcast_size(P.plus_sched()))
    r : Unit <- row("upcasted_plus", P.Sched.upcasted(P.plus_sched()))
    s : Unit <- row("group_red", P.Sched.group_for_reduces(P.reduce_sched()))
    t : Unit <- row("ul_plus_up", ul_plus_up())
    u : Unit <- row("ul_red_up", ul_red_up())
    v : Unit <- row("ul_red_lcl", ul_red_lcl())
    w : Unit <- row("split_len", split_fs_len())
    w2 : Unit <- row("split_fs0", split_fs_0())
    w3 : Unit <- row("split_fs2", split_fs_2())
    x : Unit <- row("pos_red", P.pos_key(O.AXIS_REDUCE{}))
    y : Unit <- row("pos_dev", P.pos_key(O.AXIS_DEVICE{}))
    z : Unit <- row("opsval_swap", O.OPTOPS.value(O.OPS_SWAP{}))
    st : Unit <- row("stgt_local", U32.from_nat(List.length(&2, O.AxisType, P.split_targets(O.AXIS_LOCAL{}))))
    s2 : Unit <- row("ck_tgt_bad", ck_tgt_bad())
    s3 : Unit <- row("ck_tgt_ok", ck_tgt_ok())
    s4 : Unit <- row("ck_amt_0", ck_amt_0())
    s5 : Unit <- row("ck_amt_1", ck_amt_1())
    s6 : Unit <- row("ck_amt_4", ck_amt_4())
    s7 : Unit <- row("ck_local_bad", ck_local_bad())
    s8 : Unit <- row("ck_local_ok", ck_local_ok())
    s9 : Unit <- row("ck_unroll_32", ck_unroll_32())
    s10 : Unit <- row("ck_unroll_33", ck_unroll_33())
    s11 : Unit <- row("ck_unroll_up", ck_unroll_up())
    s12 : Unit <- row("ck_upcast_16", ck_upcast_16())
    s13 : Unit <- row("ck_upcast_17", ck_upcast_17())
    s14 : Unit <- row("ck_upcast_dsp", ck_upcast_dsp())
    s15 : Unit <- row("ck_div_4", ck_div_4())
    s16 : Unit <- row("ck_div_3", ck_div_3())
    s17 : Unit <- row("lu0", lu_at(0n))
    s18 : Unit <- row("lu1", lu_at(1n))
    s19 : Unit <- row("upcastable_unit", upcastable_unit())
    row("maxid_fresh", maxid_fresh())

# THE MEASURED MUTATION TABLE. Every line is a one-token edit, re-run through
# `./bin/bend`, and the rows that MOVED are listed. 20 mutations, 20 localised;
# none is a no-op and none moves every row, so the table has real shape.
#
#   mutation                                        rows that moved

#   drop `P.split_targets` membership                  ck_tgt_bad
#   `amt != 1` inverted to `amt <= 1`                ck_amt_0
#   drop `check(has_local)`                          ck_local_bad
#   UNROLL bound 32 -> 33                            ck_unroll_33
#   drop the DSP upcast exemption                    ck_upcast_dsp
#   invert the divisibility test                     plus_n ok_i1 ok_i11 ok_i121
#                                                     ok_i129 ok_local_red
#                                                     ck_div_4 ck_div_3
#   `tc_select` bound always True                    ok_tc_sel
#   `tc_opt` bound 2 -> 3                            ok_tc_lvl
#   keep only `use > 0`, drop `use <= 2`             ok_tc_use
#   drop `tc-must-be-first`                          ok_tc_first
#   `shift_to` does not resize the old axis          ul_red_up ul_red_lcl
#                                                     split_fs0
#   new rng reuses `P.max_id`                          maxid_fresh
#   `up` fold drops UNROLL                           ul_red_up
#   `lcl` fold drops LOCAL                           ul_red_lcl
#   `P.pos_key`: LOCAL and UPCAST tie                  lu0 lu1
#   `P.pos_key`: REDUCE sorts before LOCAL             split_fs0 split_fs2 pos_red
#   `dim` filter drops the `s > 1` half              upcastable_unit
#   `P.put_at` replaces index 0 not the axis           ul_red_up
#   `axes_of` filter always keeps                    axes_global_red
#                                                     upcasted_plus group_red
#   `OptOps.value` order shifted                     opsval_swap
#
# two of these found real bugs while the table was being built, which is the
# argument for building it rather than asserting the gate bites:
#   * the `match rs P.hit:` accumulator form used by FIVE folds tested the P.hit of
#     the PREVIOUS element and appended unconditionally, so `axes_of` answered 2
#     for a kernel with one global axis and `count_bools([T,T,T,T])` answered 3.
#     The gate row `axes_global_red` is what made it visible.
#   * `P.split_new` had lost its `+ 1`, so a fresh range REUSED an existing
#     `axis_id`. Every other row was blind to it because no fixture had two rngs
#     with the same id -- which is exactly the trap brief-port.md's GATE
#     DISCIPLINE warns about, and `maxid_fresh` is the row that closes it.
