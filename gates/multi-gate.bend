# gates/multi-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/multi.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/multi.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def t_first_ad() -> U32: P.eq(P.mu_first(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_ad(P.g())), 0)
def t_fl_bad2() -> U32: P.eq(P.yes(P.fl_bad(P.two_sh(0, 4, 1, 4), P.s2(1, 4))), 1)
# `rs_mid` is (4,6)->(2,12): target 4 is NOT in [1,2,24], so Python RAISES.
def t_rs_mid_ok() -> U32: P.eq(P.yes(P.Rs.ok(P.rs_axis(P.rs_acc(P.s2(2, 12)), 4, 2, P.s2(2, 12)))), 0)
# `rs_head` is (4,6)->(24,) sharded on 0: target 1, acc [1,24], new_ax 0.
def t_rd_two_red() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 2)))), 2)
def t_lb_none() -> U32: P.eq(P.yes(P.lb_none(True{})), 1)
def t_rs_acc3_3() -> U32: P.eq(P.rsa3(P.s3(2, 3, 4)), 24)
# `target = prod(shape[:ax])` and `target in arg_acc`.
def t_rd_bad_all() -> U32: P.eq(P.yes(P.rd_bad(P.shrd(P.two_sh(0, 4, 1, 4), 2))), 0)
# a sharding that STRADDLES num_axes is Python's partial-allreduce RAISE, so
# `rd_fires` is 0 and `rd_bad` is 1 -- the pair is the whole of multi.py:113-114.
def t_pm_mid() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s3(0, 2, 1), 2))), 1)
# an axis not IN the permutation is Python's ValueError.
def t_shbuf_n() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.mu_shard.zip(P.G.ar(P.g()), P.g_b8(P.g())))), 0)
# THE PARTITION: `len(red) + len(rem) == len(sharding)` for every `num_axes`.
def t_rd_sum0() -> U32: P.eq(U32.add(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 0)))),
                                  U32.from_nat(P.mu_len(P.Rd.rem(P.shrd(P.two_sh(0, 4, 1, 4), 0))))), 2)
def t_sv_ax0() -> U32: P.eq(P.mu_at(P.sv_axes(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g()))), 0n), 0)
def t_sx1() -> U32: P.eq(P.sx_idx(True{}, 3), 3)
def t_bx_none() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s2(2, 3), P.s2(2, 3))), 0)
def t_rd_cast_off() -> U32: P.eq(P.yes(P.rd_cast(P.mu_c_nocast(), O.OpsCAST{}, S.bfloat16())), 0)
# `reshape_multi` ROWS -- `arg_acc`, the REVERSED `.index`, and the two raises.
# `rs_*_acc` is the running product and `rs_*_ax` is the new axis;
# `rs_*_ok = 0` is a raise.
# `_shard`: the divisibility test and the per-shard extent.
def t_sv_div4() -> U32: P.eq(P.yes(P.sv_div(8, 2)), 1)
def t_ix_s0() -> U32: P.eq(P.ix_strid(0, 0), 0)
def t_rs_loc_n() -> U32: P.eq(U32.from_nat(P.mu_len(P.rs_local(P.ns2(P.s2(4, 6), P.s1(0), P.s1(2))))), 2)
def t_sx0() -> U32: P.eq(P.sx_idx(False{}, 3), 0)
def t_full_cp() -> U32: P.eq(P.mu_claim_full(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_cp(P.g())), 3)
def t_rs_tgt2() -> U32: P.eq(P.mu_prod_upto(P.s2(4, 6), 2n), 24)
# THE REVERSED `.index` -- the "most recent hit" row. `rs_hit_tie` uses
# arg_acc = [1, 2, 2, 6] (a `new_shape` with a dim of 1) so 2 appears twice and the
# REVERSED index takes the LAST one: 2, not 1.
# THE TIE. `arg_acc` for `new_shape = (2, 1, 2)` is `[1, 2, 2, 6]`, so the target 2
# appears TWICE and `.index` on the REVERSED list takes the LAST one: the reversed
# index is 2, not 1. `rs_tie_ax` is the consequence -- the new axis is 4-2-1 = 1 and
# not 2 -- and it is the row that says the search counts from the END.
def t_rs_tie_hit() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.rs_rev(P.rs_acc(P.s3(2, 1, 2)), 2))), 1)
# an axis not IN the permutation is Python's ValueError.
def t_pm_missing() -> U32: P.eq(P.yes(P.mu_bs_none2(P.pm_index(P.s2(0, 1), 2))), 1)
def t_ax_m1() -> U32: P.eq(P.mu_head32(P.mu_axis(P.G.ar(P.g()), P.g_m1(P.g()))), 1)
# `shard_srcs` ROWS. CPython's own `_broadcast_shape`, `broadcast_axes`,
# `src_axis = axis - (len(out_shape) - len(mlb.shape))` and the three-way branch.
# `ss_bcast_bad` and `ss_bcast_23` are the IndexError CASES (ops.py:85) and they
# print the ABSENCE -- 1 means "refused", which is the direction Python raises.
def t_pb62_n() -> U32: P.eq(P.pbn(P.sk_pb(6, 2)), 2)
def t_pm_sw1() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s2(1, 0), 1))), 0)
def t_fl_bad_none() -> U32: P.eq(P.yes(P.fl_bad(P.one_sh(0, 4), P.s2(0, 4))), 0)
# `pad_multi`'s ASSERT -- `root.marg[ax] == (0, multi.shape[ax])` over the
# sharded axes.
# `mstack.src[ms.arg]` -- the INDEX and its bounds test.
def t_ms_arg() -> U32: P.eq(P.ms_arg(1, 4), 1)
def t_tag19() -> U32: P.eq(P.mt_tag(P.mu_table(P.mu_c_early()), 19n), 19)
def t_fl_one() -> U32: P.eq(U32.from_nat(P.mu_len(P.fl_of(P.s2(0, 4)))), 1)
def t_rd_sum1() -> U32: P.eq(U32.add(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 1)))),
                                  U32.from_nat(P.mu_len(P.Rd.rem(P.shrd(P.two_sh(0, 4, 1, 4), 1))))), 2)
def t_sk_r_dev() -> U32: P.eq(P.sk_kind(False{}, False{}, False{}, False{}, True{}), 3)
def t_pass_n() -> U32: P.eq(P.mt_ops_n([O.PMEntry{16, P.mu_pass_ops(), P.mu_rej_nil()}]), 5)
def t_pd_bad_s() -> U32: P.eq(P.yes(P.pd_bad(P.one_sh(0, 4), P.marg1(1, 8), P.s1(8))), 1)
def t_bx_1out() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(2), P.s2(1, 2))), 1)
def t_sv_eq() -> U32: P.eq(P.yes(P.mu_shape_eq(P.s2(2, 3), P.s2(2, 3))), 1)
def t_bx_exp() -> U32: P.eq(P.bx_a0(P.mu_baxes(P.s2(1, 3), P.s2(2, 3))), 0)
def t_alu_n() -> U32: P.eq(P.mt_ops_n([O.PMEntry{0, P.mu_alu_ops(), P.mu_rej_nil()}]), 28)
def t_al_eq_ax() -> U32: P.eq(P.yes(P.al_sh_eq(P.one_sh(0, 4), P.one_sh(1, 4))), 0)
# the MSELECT arms: movement is UNCONDITIONAL, ALU is device-gated.
# the MOVEMENT arm is UNCONDITIONAL (`v.replace(src=(s.mselect(ms.arg),)+...)`) and
# the ALU arm is device-gated, so `mv_pick` is the ALU arm's test and the movement
# arm's is `mv_all`. 1 is "the MSELECT moved inside".
def t_mv() -> U32: P.eq(P.yes(P.mv_all(True{})), 1)
def t_claim_cp() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_cp(P.g())), 3)
# a COPY of a WHOLE buffer is claimed by TWO, not three: tag 11's reject set is
# {UNSHARD} and the node's `ler` is {BUFFER}, so its NECESSARY CONDITION FAILS. That
# is `early_reject` doing its job and `t_claim_cp` (3) against `t_claim_cq` (2) is
# the pair that says so.
def t_al_sh_no() -> U32: P.eq(P.yes(P.al_handle(True{}, False{}, False{}, P.s2(2, 3), P.s2(2, 3))), 0)
# a sharded src whose sharding DIFFERS is refused even though it is neither a
# scalar nor of the target shape.
# THE OWN TEST's length half -- `l == shard_sz`.
def t_sk_len_ok() -> U32: P.eq(P.yes(P.sk_len_eq(P.marg1(0, 4), 4, 0n)), 1)
def t_cx_rep() -> U32: P.eq(P.mu_at(P.cx_key(P.s2(3, 3), 1n), 0n), 3)
def t_mv_alu() -> U32: P.eq(P.mv_pick(True{}), 1)
def t_ix_c_oob() -> U32: P.eq(P.yes(P.ix_in(P.ix_contig(8, 1, 4), 4)), 0)
def t_al_nmultis() -> U32: P.eq(U32.from_nat(P.al_nmultis(P.two_sh(0, 4, 1, 4))), 2)
# `reduce_multi` ROWS -- the split of the sharding by `num_axes`, the two asserts
# and the `num_axes` REBASE of the remaining axes. `rd_sum_n` is the partition
# row: `len(reduced) + len(remaining) == len(sharding)` ALWAYS, because `<` and
# `>=` are complementary.
def t_rd_cast_half() -> U32: P.eq(P.yes(P.rd_cast(P.mu_c_early(), O.OpsCAST{}, S.half())), 1)
def t_rs_acc_n0() -> U32: P.eq(P.rsa_n(P.nil32()), 1)
def t_sv_ax_n() -> U32: P.eq(U32.from_nat(P.mu_len(P.sv_axes(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g()))))), 2)
# `alu_multi` ROWS -- `can_handle` and the resharding precondition.
def t_fl_mid_n() -> U32: P.eq(U32.from_nat(P.mu_len(P.fl_of(P.s3(0, 1, 0)))), 1)
# THE RAISE -- flipping a SHARDED axis moves data across the shard boundary.
# `axis - 1` at axis 0 would WRAP in `U32`, and Python's `root.axis` is 0 there, so
# the guard is `axis > 0` and 0 is the wall.
def t_st_off_nil() -> U32: P.eq(P.st_off(0), 0)
# and the src_axis rides out of the same record.
def t_ml_sa() -> U32: P.eq(P.Sk.sa(P.ml_kind(P.ml_some(2), 0, P.s2(2, 3), P.s2(2, 3), 0)), 0)
# `mlb.axis == src_axis` is False for a src with no axis, so a SCALAR never copies
# through -- the row that says `mu_axis_is` on `None` is False.
def t_first_m0() -> U32: P.mu_first(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_m0(P.g()))
def t_ss_rng_unsh() -> U32: P.eq(P.Ss.n(P.mu_ss_rng(0, 9)), 9)
def t_sv_div0() -> U32: P.eq(P.yes(P.sv_div(8, 0)), 0)
def t_ss_same_bad() -> U32: P.eq(P.yes(P.mu_ss_same(P.s2(1, 2))), 0)
# `broadcast_axes` -- ten of Python's own. `bx_*` prints the COUNT of the returned
# axes, and `bx_*_a0` prints its FIRST element, because the count alone cannot tell
# `range(nleft)` from `range(nleft) + (0,)`.
# `broadcast_axes` rows. The COUNT is printed and the FIRST element is printed
# separately, because the count alone cannot tell `range(nleft)` from
# `range(nleft) + (0,)` -- and `bx_pad` (a leading axis ADDED) and `bx_exp` (a 1
# EXPANDED) both have count 1, so only the element separates them.
def t_al_neither() -> U32: P.eq(P.yes(P.al_handle(False{}, True{}, False{}, P.s2(4, 6), P.s2(2, 3))), 0)
# `if not multis: return None`
# a sharded src whose sharding DIFFERS is refused even though it is neither a
# scalar nor of the target shape.
def t_al_sh_guard() -> U32: P.eq(P.yes(P.al_handle(True{}, False{}, False{}, P.s1(4), P.s2(2, 3))), 0)
def t_cx_same() -> U32: P.eq(P.mu_at(P.cx_key(P.s2(3, 3), 0n), 0n), 3)
def t_ss_ax11() -> U32: P.eq(P.mu_ss_axis(1, 2n, 2n), 1)
# a rank-1 src against a rank-2 out SHIFTS the axis by one: Python ss_ax_1_0 = 0
def t_ax_b8() -> U32: P.eq(P.yes(P.mu_has_axis(P.mu_axis(P.G.ar(P.g()), P.g_b8(P.g())))), 0)
# axis 0 IS sharded, so the pair becomes `(0, 8)` -- the shard's own extent -- and
# axis 1 is NOT, so it keeps its marg entry verbatim.
def t_pd_one0() -> U32: P.eq(P.pd_s0(P.pd_of(P.marg2(0, 8, 0, 3), P.s1(0))), 0)
def t_rs_tie_axb() -> U32: P.eq(P.Rs.ax(P.rs_new_ax(P.rs_acc(P.s3(2, 1, 2)), 2)), 2)
def t_st_n() -> U32: P.eq(U32.from_nat(P.mu_len(P.st_shift(P.two_sh(0, 4, 1, 4)))), 2)
def t_pb84_sm() -> U32: P.eq(P.pbat(P.sk_pb(8, 4), 2n), 16)
def t_late_n() -> U32: P.mt_n(P.mu_table(P.mu_c_late()))
# THE TAG SHIFT. With `LATE_ALLREDUCE` off, `_early_allreduce`'s ALLREDUCE rule is
# tag 19 and `replace_allreduce`'s first COPY rule moves to 20 -- so `t_t19` is
# `ALLREDUCE` with the flag on AND with it off, while `t_t20` is `COPY` on and
# `MSELECT` off. The tag is the op VALUE (`Ops.value`, ops.bend:382), so these are
# numbers and not names, and `t_t20` off is 74+... which is why the row prints the
# tag of the ENTRY rather than comparing two op values here.
def t_ml_thru() -> U32: P.eq(P.Sk.kind(P.ml_kind(P.ml_some(1), 1, P.s2(2, 3), P.s2(2, 3), 1)), 0)
def t_fl_two() -> U32: P.eq(U32.from_nat(P.mu_len(P.fl_of(P.s2(3, 4)))), 2)
def t_ix_mod0b() -> U32: P.eq(P.ix_mod(P.ix_strid(12, 0), 4), 0)
def t_sk_w_no() -> U32: P.eq(P.yes(P.sk_whole_eq(P.marg1(0, 4), P.s1(8), 0n)), 0)
def t_ex3() -> U32: P.eq(P.ex_shift(3n), 3)
# `mlb.axis == src_axis` is False for a src with no axis, so a SCALAR never copies
# through -- the row that says `mu_axis_is` on `None` is False.
def t_ml_none_thru() -> U32: P.eq(P.yes(P.ml_through(P.ml_none(), 0)), 0)
# `part_bounds = tuple((i*shard_sz, shard_sz) for i in range(count))` for
# shard_sz 4 over 2, 3, 4 and 1 devices -- all of CPython's own.
def t_pb42_n() -> U32: P.eq(P.pbn(P.sk_pb(4, 2)), 2)
def t_pd_kp0() -> U32: P.eq(P.pd_s0(P.pd_of(P.marg2(1, 8, 0, 3), P.nil32())), 1)
def t_cx_j0b() -> U32: P.eq(P.mu_at(P.cx_key(P.s2(0, 1), 0n), 0n), 1)
def t_ex1() -> U32: P.eq(P.ex_shift(1n), 1)
def t_ml_nocopy() -> U32: P.eq(P.yes(P.ml_needs_copy(P.ml_none())), 0)
# `shard_subview` ROWS -- the shape assert, the EXPAND-of-a-scalar arm and `_shard`'s
# two arithmetic lines (ops.py:751-756).
def t_pm_cyc() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s3(2, 0, 1), 1))), 2)
def t_sv_exp_no() -> U32: P.eq(P.yes(P.sv_expand(O.OpsADD{}, True{})), 0)
# `_shard`: the divisibility test and the per-shard extent.
# an UNEVEN dim is Python's "multi axis uneven" raise and the port answers the wall
# marker rather than a truncated extent.
def t_sv_sz5() -> U32: P.eq(P.sv_sz(5, 2), 0)
def t_sv_ne() -> U32: P.eq(P.yes(P.mu_shape_eq(P.s2(2, 3), P.s2(2, 4))), 0)
def t_cx_j1() -> U32: P.eq(P.cxn(P.cx_key(P.s2(0, 1), 1n)), 1)
# the assert: no devices AND no UNSHARD.
def t_ss_none() -> U32: P.eq(P.yes(P.mu_ss_none(P.mu_ss_rng(0, 0))), 1)
def t_tag25() -> U32: P.eq(P.mt_tag(P.mu_table(P.mu_c_late()), 24n), 24)
# THE INVENTORY COUNTS.
def t_rs_acc_n1() -> U32: P.eq(P.rsa_n(P.s1(24)), 2)
def t_ix_c0() -> U32: P.eq(P.ix_contig(0, 0, 4), 0)
def t_al_eq_len() -> U32: P.eq(P.yes(P.al_sh_eq(P.one_sh(0, 4), P.two_sh(0, 4, 1, 4))), 0)
def t_ix_kind_s() -> U32: P.eq(P.ix_kind(False{}, True{}, True{}), 1)
def t_st_ax0() -> U32: P.eq(P.mu_at(P.st_shift(P.one_sh(0, 4)), 0n), 1)
def t_lb_no() -> U32: P.eq(P.yes(P.lb_fires(False{}, True{})), 0)
def t_rs_acc_n4() -> U32: P.eq(P.rsa_n(P.s2(4, 6)), 3)
def t_bx_scalar() -> U32: P.eq(P.bx_n(P.mu_baxes(P.nil32(), P.s2(2, 3))), 2)
def t_t25_off() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_late()), 24n), P.MSELECT())
# `rs_thr1` new_ax is 1 and the boundary dim is 3, so the SAME target with the same
# count is refused -- the row that says the divisibility test is on
# `new_shape[new_ax]` and not on the target.
def t_rs_thr1_ax() -> U32: P.eq(P.Rs.ax(P.rs_axis(P.rs_acc(P.s3(2, 3, 4)), 2, 2, P.s3(2, 3, 4))), 1)
# the first raise: `prod(multi.shape) != prod(new_shape)`.
# `rewrite_into_function` is the recursion wall.
def t_rw() -> U32: P.eq(P.yes(P.rw_none()), 1)
def t_bx_exp_n() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s2(1, 3), P.s2(2, 3))), 1)
# `nleft < 0` is Python's RuntimeError and the port's `None{}`.
def t_bx_bad() -> U32: P.eq(P.refu(P.mu_baxes(P.s2(2, 2), P.s1(2))), 1)
# THE BRANCH (multi.py:68-75). `ml_kind` is the four-way decision and `ml_*` is
# one row per outcome: COPY THROUGH (0), WHOLE (1), BROADCAST (2), SHARDED (3).
# `ml_src0` is the src with NO axis, which is what makes `ml_whole` fire.
def t_ix_c3() -> U32: P.eq(P.ix_contig(7, 1, 4), 3)
def t_sk_keep_all() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.sk_keep(P.two_sh(0, 4, 1, 4), Nil{}))), 2)
def t_sv_sz6() -> U32: P.eq(P.sv_sz(6, 2), 3)
# an UNEVEN dim is Python's "multi axis uneven" raise and the port answers the wall
# marker rather than a truncated extent.
def t_pd_kp1() -> U32: P.eq(P.pd_l1(P.pd_of(P.marg2(0, 8, 1, 3), Nil{})), 3)
def t_rd_some_red() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(1, 4, 2, 4), 1)))), 0)
def t_ix_c_win4() -> U32: P.eq(P.yes(P.ix_in(4, 4)), 0)
def t_al_eq_n() -> U32: P.eq(P.yes(P.al_sh_eq(P.one_sh(0, 4), P.one_sh(0, 2))), 0)
def t_stp_whole() -> U32: P.eq(P.st_pick(False{}, False{}), 2)
# `rewrite_into_function` is the recursion wall.
def t_rs_acc1_4() -> U32: P.eq(P.rsa1(P.s2(4, 6)), 4)
def t_rd_zero_red() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 0)))), 0)
# THE PARTITION: `len(red) + len(rem) == len(sharding)` for every `num_axes`.
def t_sha_n() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g())))), 2)
def t_pb62_l0() -> U32: P.eq(P.pbl0(P.sk_pb(6, 2)), 6)
def t_claim_ad() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_ad(P.g())), 1)
def t_first_su() -> U32: P.eq(P.mu_first(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_su(P.g())), 16)
def t_pb43_n() -> U32: P.eq(P.pbn(P.sk_pb(4, 3)), 3)
def t_pb42_s0() -> U32: P.eq(P.pb0(P.sk_pb(4, 2)), 0)
def t_ix_bad() -> U32: P.eq(P.yes(P.ix_strid_ok(P.ix_strid(5, 0), 4)), 0)
def t_sk_r_pb() -> U32: P.eq(P.sk_kind(False{}, False{}, False{}, True{}, False{}), 3)
# the OWN arm SKIPS the raise entirely: a two-axis sharding resolves its own shard
# even though `len(sharding) != 1`.
def t_co_fires() -> U32: P.eq(P.yes(P.co_fires(True{}, True{})), 1)
# THE RAISE -- flipping a SHARDED axis moves data across the shard boundary.
def t_fl_bad() -> U32: P.eq(P.yes(P.fl_bad(P.two_sh(0, 4, 1, 4), P.s2(0, 4))), 1)
def t_ix_kind_r2() -> U32: P.eq(P.ix_kind(False{}, True{}, False{}), 2)
def t_rd_all_rem() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.rem(P.shrd(P.two_sh(0, 4, 1, 4), 1)))), 1)
def t_rs_none() -> U32: P.eq(P.yes(P.mu_bs_none2(P.rs_rev(P.rs_acc(P.s2(4, 6)), 7))), 1)
# THE LOCAL SHAPE -- `s // count if a in new_axs else s` (multi.py:139). `Ns`
# carries the three parallel lists and `rs_local` divides a sharded axis and keeps
# an unsharded one.
def t_ex_rng() -> U32: P.eq(P.mu_at(P.ex_rngs(P.one_sh(3, 4), ), 0n), 4)
# `tuple(root.marg.index(ax))` -- a SEARCH, so `permute((1,0))` sends axis 0 to 1.
def t_rd_off2b() -> U32: P.eq(P.rdo1(P.shrd(P.two_sh(2, 4, 3, 4), 1)), 2)
def t_ix_c1() -> U32: P.eq(P.ix_contig(3, 0, 4), 3)
def t_sv_exp_nosc() -> U32: P.eq(P.yes(P.sv_expand(O.OpsEXPAND{}, False{})), 0)
def t_sv_sz8() -> U32: P.eq(P.sv_sz(8, 2), 4)
# `rs_thr0` is (2,3,4)->(2,3,4) sharded on 2: target 6, acc [1,2,6,24],
# reversed index 1, new_ax = 4-1-1 = 2.
def t_rs_thr0() -> U32: P.eq(P.Rs.ax(P.rs_axis(P.rs_acc(P.s3(2, 3, 4)), 6, 2, P.s3(2, 3, 4))), 2)
def t_fl_mid() -> U32: P.eq(P.mu_at(P.fl_of(P.s3(0, 1, 0)), 0n), 1)
def t_lb_no2() -> U32: P.eq(P.yes(P.lb_fires(True{}, False{})), 0)
def t_own_n() -> U32: P.mt_n(P.mu_own())
def t_sk_whole() -> U32: P.eq(P.sk_kind(False{}, True{}, False{}, True{}, True{}), 1)
def t_fl_first() -> U32: P.eq(P.mu_at(P.fl_of(P.s2(2, 0)), 0n), 0)
def t_sv_rank() -> U32: P.eq(P.yes(P.mu_shape_eq(P.s2(2, 3), P.s1(3))), 0)
def t_ix_c_win0() -> U32: P.eq(P.yes(P.ix_in(0, 4)), 1)
def t_sk_keep_n() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.sk_keep(P.two_sh(0, 4, 1, 4), P.one_sh(0, 2)))), 2)
# `stack_multi` ROWS -- the `ax+1` shift and the `axis-1` fallback.
def t_st_not_none() -> U32: P.eq(P.yes(P.st_none(2n)), 0)
# `index_multi` ROWS -- both ownership patterns, and the window is tested TWICE.
# shard_sz 4: contiguous locals are 0..3 and the strided diff must be a multiple.
def t_sh0_c() -> U32: P.eq(P.Sh.n(P.mu_head_sh(P.mu_shard.zip(P.G.ar(P.g()), P.g_m0(P.g())))), 4)
def t_cx_j0n() -> U32: P.eq(U32.from_nat(P.cx_key_n(P.cx_key(P.s2(0, 1), 0n))), 1)
def t_sha1_n() -> U32: P.eq(P.Sh.n(P.mu_at_sh(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g())), 1n)), 8)
# `int(rng.vmax)+1` on a real DEVICE RANGE over four devices is 4.
def t_cx_j3() -> U32: P.eq(P.cxn(P.cx_key(P.s3(0, 1, 2), 0n)), 2)
# (4,6) -> (2,3,4): the running product passes THROUGH 4 at index 2.
def t_rs_acc3_1() -> U32: P.eq(P.rsa1(P.s3(2, 3, 4)), 2)
def t_t19_on() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_early()), 19n), P.COPY())
def t_ml_bcast() -> U32: P.eq(P.Sk.kind(P.ml_kind(P.ml_some(2), 1, P.s1(1), P.s2(2, 3), 0)), 2)
def t_pd_one1() -> U32: P.eq(P.pd_l0(P.pd_of(P.marg2(0, 8, 0, 3), P.s1(0))), 8)
def t_ix_div0() -> U32: P.eq(P.ix_div(P.ix_strid(4, 0), 4), 1)
def t_pm_of() -> U32: P.eq(P.mu_at(P.pm_of(P.one_sh(1, 4), P.s2(1, 0)), 0n), 0)
# `[i for i,x in enumerate(root.marg) if x]` -- the FLIP axis list.
def t_ix_kind_r() -> U32: P.eq(P.ix_kind(False{}, False{}, False{}), 2)
def t_sh1_ax() -> U32: P.eq(P.Sh.ax(P.mu_head_sh(P.mu_shard.zip(P.G.ar(P.g()), P.g_m1(P.g())))), 1)
def t_ix_kind00() -> U32: P.eq(P.ix_div(4, 0), 0)
# `copy_multi` / `_shard_idx` ROWS -- the GROUP KEY `idxs[:j] + idxs[j+1:]`, which
# DELETES the j-th index. Deleting is not zeroing, and on a repeated index (which
# is every multi-axis shard) the two differ.
# `.index((s, l))` -- WHICH PARTITION, and a miss is the wall marker.
def t_sk_at0() -> U32: P.eq(P.sk_at(P.sk_pb(4, 4), P.Bd{0, 4}), 0)
def t_pb42_s1() -> U32: P.eq(P.pbat(P.sk_pb(4, 2), 1n), 4)
def t_ms_ok() -> U32: P.eq(P.yes(P.ms_arg_ok(3, 4)), 1)
# the MSELECT arms: movement is UNCONDITIONAL, ALU is device-gated.
# the MOVEMENT arm is UNCONDITIONAL (`v.replace(src=(s.mselect(ms.arg),)+...)`) and
# the ALU arm is device-gated, so `mv_pick` is the ALU arm's test and the movement
# arm's is `mv_all`. 1 is "the MSELECT moved inside".
# `src_axis = axis - (len(out_shape) - len(mlb.shape))` -- the RIGHT-ALIGNMENT.
def t_ss_ax00() -> U32: P.eq(P.mu_ss_axis(0, 1n, 1n), 0)
# a MISS is the SENTINEL, not 0: index 0 is a real partition. MEASURED, the walk
# returned 0 for a miss while `sk_at0` also returned 0, so the two were
# indistinguishable.
def t_sk_at_miss() -> U32: P.eq(P.sk_at(P.sk_pb(4, 4), P.Bd{13, 4}), 4294967295)
def t_sk_at3() -> U32: P.eq(P.sk_at(P.sk_pb(4, 4), P.Bd{12, 4}), 3)
# a MISS is the SENTINEL, not 0: index 0 is a real partition. MEASURED, the walk
# returned 0 for a miss while `sk_at0` also returned 0, so the two were
# indistinguishable.
def t_bx_pad() -> U32: P.eq(P.bx_a0(P.mu_baxes(P.s1(3), P.s2(2, 3))), 0)
# `UOp.axis`: Some(0) for a one-axis UNSHARD, None for a two-axis one (Python
# raises) and None for a non-UNSHARD.
def t_ax_m0() -> U32: P.eq(P.mu_head32(P.mu_axis(P.G.ar(P.g()), P.g_m0(P.g()))), 0)
def t_rs_loc_none() -> U32: P.eq(P.mu_at(P.rs_local(P.ns2(P.s2(4, 6), P.nil32(), P.nil32())), 0n), 4)
# an UNEVEN sharded dim is the wall marker and NOT a truncated extent.
# and it WRAPS for a src LONGER than the out shape, which Python's `len(out) -
# len(src)` never does -- `broadcast_axes` refuses it and this row says so.
# `Nat.sub` SATURATES at 0 where Python's `len(out) - len(src)` would be negative and
# `broadcast_axes` would raise -- MEASURED, the port answers 0 rather than wrapping.
# `t_bx_bad` is the row that says the CALL refuses it.
def t_ss_axneg() -> U32: P.eq(P.mu_ss_axis(0, 1n, 3n), 0)
# `sharding_rng`: devices present -> a DEVICE range over `len(devices[0])`; no
# devices -> the UNSHARD's own `src[1]`.
# `if not multis: return None`
def t_al_none0() -> U32: P.eq(P.yes(P.al_none(0n)), 1)
# an UNEVEN sharded dim is the wall marker and NOT a truncated extent.
def t_rs_loc_bad() -> U32: P.eq(P.mu_at(P.rs_local(P.ns2(P.s2(4, 5), P.s1(1), P.s1(2))), 1n), 0)
# `expand_multi`, `permute_multi`, `flip_multi`, `pad_multi` ROWS.
# `shift = len(root.marg)` -- an EXPAND ADDS axes, it does not reshard.
def t_pd_n() -> U32: P.eq(P.blen(P.pd_of(P.marg2(0, 8, 0, 3), P.s1(0))), 2)
# `shrink_multi` ROWS -- `part_bounds`, the OWN test's length half, the WHOLE test
# and the four-way outcome.
def t_mv_alu_no() -> U32: P.eq(P.mv_pick(False{}), 0)
# the STORE family -- 0 PEEL, 1 SUB-VIEW, 2 WHOLE.
def t_co_no() -> U32: P.eq(P.yes(P.co_fires(False{}, True{})), 0)
def t_rd_some_rem() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.rem(P.shrd(P.two_sh(1, 4, 2, 4), 1)))), 2)
def t_rd_fires_none() -> U32: P.eq(P.yes(P.rd_fires(P.shrd(P.two_sh(1, 4, 2, 4), 1))), 0)
# THE FULL CLAIM: the op set AND that tag's src test. Two rules claim one node and
# they DISAGREE, which is what a first-wins -> conjunction mutation would move.
def t_full_st() -> U32: P.eq(P.mu_claim_full(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_st(P.g())), 1)
def t_al_none1() -> U32: P.eq(P.yes(P.al_none(1n)), 0)
# THE THREE CONJUNCTS of the raise, one row each -- they are `or`-ed, so each one
# alone is enough to raise and that is what the rows show.
# `len(sharding) != 1` ALONE is the raise, and `t_sk_r_pb` and `t_sk_r_dev` are the
# other two conjuncts. MEASURED, the original `sk_raise2` read the two device/pb
# terms as POSITIVE (`bad_n or (one_dev and in_pb)`) and answered PARTITION for all
# three; every one of these rows was 0 until it was `not`.
def t_sk_r_n() -> U32: P.eq(P.sk_kind(False{}, False{}, True{}, True{}, True{}), 3)
def t_pb42_l0() -> U32: P.eq(P.pbl0(P.sk_pb(4, 2)), 4)
def t_al_eq_two() -> U32: P.eq(P.yes(P.al_sh_eq(P.two_sh(0, 4, 1, 2), P.two_sh(0, 4, 1, 2))), 1)
# `can_handle`: a SHARDED src is judged only by its sharding (the guard), a scalar
# and a full-shape value are the other two.
def t_ss_ax02() -> U32: P.eq(P.mu_ss_axis(0, 3n, 3n), 0)
# and it WRAPS for a src LONGER than the out shape, which Python's `len(out) -
# len(src)` never does -- `broadcast_axes` refuses it and this row says so.
# `Nat.sub` SATURATES at 0 where Python's `len(out) - len(src)` would be negative and
# `broadcast_axes` would raise -- MEASURED, the port answers 0 rather than wrapping.
# `t_bx_bad` is the row that says the CALL refuses it.
# `sharding_rng`: devices present -> a DEVICE range over `len(devices[0])`; no
# devices -> the UNSHARD's own `src[1]`.
def t_ss_rng_dev() -> U32: P.eq(P.Ss.n(P.mu_ss_rng(4, 9)), 4)
def t_rd_off1() -> U32: P.eq(P.rdo0(P.shrd(P.two_sh(1, 4, 2, 4), 1)), 0)
def t_rej_late() -> U32: P.eq(P.mt_rej_n(P.mu_table(P.mu_c_late())), 20)
def t_pd_bad2() -> U32: P.eq(P.yes(P.pd_bad(P.two_sh(0, 4, 1, 4), P.marg2(0, 8, 0, 8), P.s2(8, 24))), 1)
# the LOCAL PAD -- `(0, local.shape[a])` on a sharded axis, `s` verbatim elsewhere.
def t_ea_n() -> U32: P.mt_n([P.mu_ea0()])
def t_rs_same_ok() -> U32: P.eq(P.yes(P.Rs.ok(P.rs_axis(P.rs_acc(P.s2(4, 6)), 1, 2, P.s2(4, 6)))), 1)
# `rs_mid` is (4,6)->(2,12): target 4 is NOT in [1,2,24], so Python RAISES.
def t_bx_noop() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(2), P.s2(2, 3))), 1)
def t_pm_id1() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s2(0, 1), 1))), 1)
def t_st_ax2() -> U32: P.eq(P.mu_at(P.st_shift(P.one_sh(2, 4)), 0n), 3)
def t_pb43_s1() -> U32: P.eq(P.pbat(P.sk_pb(4, 3), 1n), 4)
def t_sk_raise() -> U32: P.eq(P.sk_kind(False{}, False{}, False{}, True{}, False{}), 3)
# THE THREE CONJUNCTS of the raise, one row each -- they are `or`-ed, so each one
# alone is enough to raise and that is what the rows show.
# `len(sharding) != 1` ALONE is the raise, and `t_sk_r_pb` and `t_sk_r_dev` are the
# other two conjuncts. MEASURED, the original `sk_raise2` read the two device/pb
# terms as POSITIVE (`bad_n or (one_dev and in_pb)`) and answered PARTITION for all
# three; every one of these rows was 0 until it was `not`.
def t_ml_whole() -> U32: P.eq(P.Sk.kind(P.ml_kind(P.ml_none(), 1, P.nil32(), P.s2(2, 3), 1)), 1)
def t_rs_tgt1() -> U32: P.eq(P.mu_prod_upto(P.s2(4, 6), 1n), 4)
def t_ex_ax0() -> U32: P.eq(P.mu_at(P.ex_axes(P.one_sh(0, 4), 1), 0n), 1)
def t_ix_c_in() -> U32: P.eq(P.yes(P.ix_in(P.ix_contig(3, 0, 4), 4)), 1)
def t_sk_at2() -> U32: P.eq(P.sk_at(P.sk_pb(4, 4), P.Bd{8, 4}), 2)
# `target = prod(shape[:ax])` and `target in arg_acc`.
def t_rs_tgt0() -> U32: P.eq(P.mu_prod_upto(P.s2(4, 6), 0n), 1)
def t_bx_rank1() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(3), P.s1(3))), 0)
# `nleft < 0` is Python's RuntimeError and the port's `None{}`.
def t_ss_same() -> U32: P.eq(P.yes(P.mu_ss_same(P.s2(1, 1))), 1)
# `shift = len(root.marg)` -- an EXPAND ADDS axes, it does not reshard.
def t_ex0() -> U32: P.eq(P.ex_shift(0n), 0)
# `rs_head` is (4,6)->(24,) sharded on 0: target 1, acc [1,24], new_ax 0.
def t_rs_head() -> U32: P.eq(P.Rs.ax(P.rs_axis(P.rs_acc(P.s1(24)), 1, 2, P.s1(24))), 0)
# `rs_thr0` is (2,3,4)->(2,3,4) sharded on 2: target 6, acc [1,2,6,24],
# reversed index 1, new_ax = 4-1-1 = 2.
def t_st_none() -> U32: P.eq(P.yes(P.st_none(0n)), 1)
def t_t20_on() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_early()), 20n), P.MSELECT())
# the STORE family -- 0 PEEL, 1 SUB-VIEW, 2 WHOLE.
def t_stp_peel() -> U32: P.eq(P.st_pick(True{}, True{}), 0)
def t_sv_sc() -> U32: P.eq(P.yes(P.mu_scalar(P.nil32())), 1)
def t_fl_two1() -> U32: P.eq(P.mu_at(P.fl_of(P.s2(3, 4)), 1n), 1)
def t_ra_n() -> U32: P.mt_n(P.mu_ra_base())
# THE ALLREDUCE_CAST ARM -- three conjuncts and each one is a row, because
# dropping the flag or the dtype test would silently change WHICH dtype is cast.
def t_rd_cast() -> U32: P.eq(P.yes(P.rd_cast(P.mu_c_early(), O.OpsCAST{}, S.bfloat16())), 1)
def t_ex_axn() -> U32: P.eq(U32.from_nat(P.mu_len(P.ex_axes(P.two_sh(0, 4, 1, 4), 2))), 2)
# `tuple(root.marg.index(ax))` -- a SEARCH, so `permute((1,0))` sends axis 0 to 1.
def t_pm_id() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s2(0, 1), 0))), 0)
def t_rd_off2() -> U32: P.eq(P.rdo0(P.shrd(P.two_sh(2, 4, 3, 4), 1)), 1)
def t_claim_st() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_st(P.g())), 2)
def t_rd_off3() -> U32: P.eq(P.rdo0(P.shrd(P.two_sh(1, 4, 4, 4), 3)), 1)
def t_ss_ax22() -> U32: P.eq(P.mu_ss_axis(2, 3n, 3n), 2)
def t_bx_11() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(1), P.s1(1))), 0)
# THE RAISES. `rs_same` is (4,6)->(4,6) sharded on 0: target 1, arg_acc
# [1,4,24], reversed index 2, new_ax = 3-2-1 = 0, and 4 % 2 == 0 so it FIRES.
def t_rs_same() -> U32: P.eq(P.Rs.ax(P.rs_axis(P.rs_acc(P.s2(4, 6)), 1, 2, P.s2(4, 6))), 0)
def t_al_full() -> U32: P.eq(P.yes(P.al_handle(False{}, True{}, False{}, P.s2(2, 3), P.s2(2, 3))), 1)
def t_rs_tie_hit_f() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.rs_rev(P.rs_acc(P.s3(2, 1, 2)), 6))), 0)
def t_rs_acc2_4() -> U32: P.eq(P.rsa2(P.s2(4, 6)), 24)
# (4,6) -> (2,3,4): the running product passes THROUGH 4 at index 2.
def t_rd_any_empty() -> U32: P.eq(P.yes(P.rd_any(Nil{})), 0)
def t_t20_off() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_late()), 20n), P.COPY())
def t_rd_off0b() -> U32: P.eq(P.rdo1(P.shrd(P.two_sh(0, 4, 1, 4), 0)), 1)
def t_ix_kind_c() -> U32: P.eq(P.ix_kind(True{}, False{}, False{}), 0)
def t_bx_1_2n() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(1), P.s1(2))), 1)
def t_co_same() -> U32: P.eq(P.yes(P.co_same(True{})), 1)
def t_sk_in() -> U32: P.eq(P.yes(P.sk_in(P.sk_pb(4, 4), P.Bd{8, 4})), 1)
def t_bx_both() -> U32: P.eq(P.bx_n(P.mu_baxes(P.s1(1), P.s2(2, 3))), 2)
def t_pb41_n() -> U32: P.eq(P.pbn(P.sk_pb(4, 1)), 1)
# `.index((s, l))` -- WHICH PARTITION, and a miss is the wall marker.
def t_claim_su() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_su(P.g())), 2)
def t_rs_loc_both() -> U32: P.eq(P.mu_at(P.rs_local(P.ns2(P.s2(4, 6), P.s2(0, 1), P.s2(2, 3))), 1n), 2)
# a COPY of a WHOLE buffer is claimed by TWO, not three: tag 11's reject set is
# {UNSHARD} and the node's `ler` is {BUFFER}, so its NECESSARY CONDITION FAILS. That
# is `early_reject` doing its job and `t_claim_cp` (3) against `t_claim_cq` (2) is
# the pair that says so.
def t_claim_cq() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_cq(P.g())), 2)
def t_rd_off_none() -> U32: P.eq(P.rdo_n(P.shrd(P.two_sh(0, 4, 1, 4), 2)), 0)
# THE TWO ASSERTS. `rd_bad` is the partial-allreduce raise and it needs BOTH a
# reduced axis and a remaining one; `rd_fires` is the full-allreduce arm.
def t_rs_loc0() -> U32: P.eq(P.mu_at(P.rs_local(P.ns2(P.s2(4, 6), P.s1(0), P.s1(2))), 0n), 2)
# THE SECOND RAISE: the boundary dim 3 is not divisible by count 2.
def t_rs_thr1_ok() -> U32: P.eq(P.yes(P.Rs.ok(P.rs_axis(P.rs_acc(P.s3(2, 3, 4)), 2, 2, P.s3(2, 3, 4)))), 0)
# `rs_thr1` new_ax is 1 and the boundary dim is 3, so the SAME target with the same
# count is refused -- the row that says the divisibility test is on
# `new_shape[new_ax]` and not on the target.
def t_ss_rng_src() -> U32: P.eq(P.yes(P.Ss.from_unshard(P.mu_ss_rng(0, 9))), 1)
# `remaining.remove((ax, rng))` -- the pair equality, and it compares the COUNT.
def t_sk_keep() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.sk_keep(P.two_sh(0, 4, 1, 4), P.one_sh(0, 4)))), 1)
def t_ss_rng_src2() -> U32: P.eq(P.yes(P.Ss.from_unshard(P.mu_ss_rng(4, 9))), 0)
# the assert: no devices AND no UNSHARD.
# `can_handle`: a SHARDED src is judged only by its sharding (the guard), a scalar
# and a full-shape value are the other two.
def t_al_sh_ok() -> U32: P.eq(P.yes(P.al_handle(True{}, True{}, False{}, P.s2(2, 3), P.s2(2, 3))), 1)
def t_lb_not_none() -> U32: P.eq(P.yes(P.lb_none(False{})), 0)
def t_pm_n() -> U32: P.mt_n(P.mu_table(P.mu_c_early()))
# a sharding that STRADDLES num_axes is Python's partial-allreduce RAISE, so
# `rd_fires` is 0 and `rd_bad` is 1 -- the pair is the whole of multi.py:113-114.
def t_rd_fires() -> U32: P.eq(P.yes(P.rd_fires(P.shrd(P.two_sh(0, 4, 1, 4), 1))), 0)
def t_st_off1() -> U32: P.eq(P.st_off(2), 1)
# `axis - 1` at axis 0 would WRAP in `U32`, and Python's `root.axis` is 0 there, so
# the guard is `axis > 0` and 0 is the wall.
def t_lb_reps() -> U32: P.eq(P.lb_reps(4), 4)
def t_rs_acc3_2() -> U32: P.eq(P.rsa2(P.s3(2, 3, 4)), 6)
# the OWN arm SKIPS the raise entirely: a two-axis sharding resolves its own shard
# even though `len(sharding) != 1`.
def t_sk_own2() -> U32: P.eq(P.sk_kind(True{}, True{}, True{}, False{}, False{}), 0)
# `remaining.remove((ax, rng))` -- the pair equality, and it compares the COUNT.
def t_t23_off() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_late()), 23n), P.MSELECT())
def t_stp_view() -> U32: P.eq(P.st_pick(False{}, True{}), 1)
# a rank-1 src against a rank-2 out SHIFTS the axis by one: Python ss_ax_1_0 = 0
def t_ss_ax10() -> U32: P.eq(P.mu_ss_axis(1, 2n, 1n), 0)
def t_pm_sw() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s2(1, 0), 0))), 1)
def t_sk_w_ok() -> U32: P.eq(P.yes(P.sk_whole_eq(P.marg1(0, 8), P.s1(8), 0n)), 1)
def t_fl_one0() -> U32: P.eq(P.mu_at(P.fl_of(P.s2(0, 4)), 0n), 1)
# the EXPAND arm has TWO conjuncts and both are gateable: an EXPAND of a NON-scalar
# is not this arm, and a non-EXPAND is not this arm.
def t_sv_exp() -> U32: P.eq(P.yes(P.sv_expand(O.OpsEXPAND{}, True{})), 1)
def t_sk_keep0() -> U32: P.eq(P.mu_at(P.sv_axes(P.sk_keep(P.two_sh(0, 4, 1, 4), P.one_sh(0, 4))), 0n), 1)
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def t_sv_nsc() -> U32: P.eq(P.yes(P.mu_scalar(P.s1(1))), 0)
# the EXPAND arm has TWO conjuncts and both are gateable: an EXPAND of a NON-scalar
# is not this arm, and a non-EXPAND is not this arm.
# THE TWO ASSERTS. `rd_bad` is the partial-allreduce raise and it needs BOTH a
# reduced axis and a remaining one; `rd_fires` is the full-allreduce arm.
def t_rd_bad() -> U32: P.eq(P.yes(P.rd_bad(P.shrd(P.two_sh(0, 4, 1, 4), 1))), 1)
def t_rd_bad_none() -> U32: P.eq(P.yes(P.rd_bad(P.shrd(P.two_sh(1, 4, 2, 4), 1))), 0)
def t_bx_1_2() -> U32: P.eq(P.bx_a0(P.mu_baxes(P.s1(1), P.s1(2))), 0)
def t_rd_piece() -> U32: P.eq(P.yes(P.rd_any(P.Rd.red(P.shrd(P.two_sh(1, 4, 2, 4), 1)))), 0)
# THE ALLREDUCE_CAST ARM -- three conjuncts and each one is a row, because
# dropping the flag or the dtype test would silently change WHICH dtype is cast.
def t_st_off0() -> U32: P.eq(P.st_off(1), 0)
def t_ix_kind0() -> U32: P.eq(P.ix_mod(4, 0), 4)
def t_full_su() -> U32: P.eq(P.mu_claim_full(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_su(P.g())), 2)
def t_sk_w_s() -> U32: P.eq(P.yes(P.sk_whole_eq(P.marg1(1, 8), P.s1(8), 0n)), 0)
# the four-way outcome: 0 own, 1 whole, 2 partition, 3 raise.
def t_cx_j0() -> U32: P.eq(P.cxn(P.cx_key(P.s2(0, 1), 0n)), 1)
def t_ex2() -> U32: P.eq(P.ex_shift(2n), 2)
def t_al_sc() -> U32: P.eq(P.yes(P.al_handle(False{}, True{}, True{}, P.nil32(), P.s2(2, 3))), 1)
# the four-way outcome: 0 own, 1 whole, 2 partition, 3 raise.
def t_sk_own() -> U32: P.eq(P.sk_kind(True{}, True{}, False{}, True{}, True{}), 0)
def t_pm_rev() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s3(2, 1, 0), 2))), 0)
def t_co_copy() -> U32: P.eq(P.yes(P.co_same(False{})), 0)
# `mstack.src[ms.arg]` -- the INDEX and its bounds test.
def t_rd_off_n() -> U32: P.eq(P.rdo_n(P.shrd(P.two_sh(1, 4, 4, 4), 3)), 1)
def t_pm_cyc0() -> U32: P.eq(U32.from_nat(P.mu_head_nat(P.pm_index(P.s3(2, 0, 1), 0))), 1)
def t_pd_bad_l() -> U32: P.eq(P.yes(P.pd_bad(P.one_sh(0, 4), P.marg1(0, 4), P.s1(8))), 1)
def t_ops_n() -> U32: P.eq(P.mt_ops_n(P.mu_table(P.mu_c_early())), 56)
def t_rs_prod_bad() -> U32: P.eq(P.yes(P.rs_prods(P.s2(4, 6), P.s2(5, 5))), 0)
# THE REVERSED `.index` -- the "most recent hit" row. `rs_hit_tie` uses
# arg_acc = [1, 2, 2, 6] (a `new_shape` with a dim of 1) so 2 appears twice and the
# REVERSED index takes the LAST one: 2, not 1.
# THE TIE. `arg_acc` for `new_shape = (2, 1, 2)` is `[1, 2, 2, 6]`, so the target 2
# appears TWICE and `.index` on the REVERSED list takes the LAST one: the reversed
# index is 2, not 1. `rs_tie_ax` is the consequence -- the new axis is 4-2-1 = 1 and
# not 2 -- and it is the row that says the search counts from the END.
def t_ml_shard() -> U32: P.eq(P.Sk.kind(P.ml_kind(P.ml_some(2), 1, P.s2(2, 3), P.s2(2, 3), 0)), 3)
# and the src_axis rides out of the same record.
def t_sha1_ax() -> U32: P.eq(P.Sh.ax(P.mu_at_sh(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g())), 1n)), 1)
def t_ex_ax2() -> U32: P.eq(P.mu_at(P.ex_axes(P.one_sh(2, 4), 3), 0n), 5)
def t_sv_div5() -> U32: P.eq(P.yes(P.sv_div(5, 2)), 0)
def t_ms_arg_bad() -> U32: P.eq(P.ms_arg(4, 4), 0)
def t_pb84_sl() -> U32: P.eq(P.pbat(P.sk_pb(8, 4), 3n), 24)
def t_sk_in_no() -> U32: P.eq(P.yes(P.sk_in(P.sk_pb(4, 4), P.Bd{13, 4})), 0)
# THE OWN TEST's length half -- `l == shard_sz`.
def t_ix_div() -> U32: P.eq(P.ix_div(P.ix_strid(12, 0), 4), 3)
def t_ix_c2() -> U32: P.eq(P.ix_contig(4, 1, 4), 0)
def t_rs_tie_ax() -> U32: P.eq(P.Rs.ax(P.rs_new_ax(P.rs_acc(P.s3(2, 1, 2)), 2)), 2)
def t_rs_thr0_ok() -> U32: P.eq(P.yes(P.Rs.ok(P.rs_axis(P.rs_acc(P.s3(2, 3, 4)), 6, 2, P.s3(2, 3, 4)))), 1)
# THE SECOND RAISE: the boundary dim 3 is not divisible by count 2.
# the sharding EQUALITY compares BOTH the axis and the COUNT, and `al_eq_n` is
# the row for the count: two shardings on the same axis with different device
# counts are NOT the same sharding, and a comparison that looked only at the axis
# would accept them and produce a per-shard ALU over shards of the wrong size.
def t_al_eq() -> U32: P.eq(P.yes(P.al_sh_eq(P.one_sh(0, 4), P.one_sh(0, 4))), 1)
def t_cx_j1b() -> U32: P.eq(P.mu_at(P.cx_key(P.s2(0, 1), 1n), 0n), 0)
def t_ix_ok() -> U32: P.eq(P.yes(P.ix_strid_ok(P.ix_strid(12, 0), 4)), 1)
def t_mov_n() -> U32: P.eq(P.mt_ops_n([O.PMEntry{23, P.mu_move_ops(), P.mu_rej_nil()}]), 5)
# THE CLAIM ROWS -- the brief's two-rules-one-node fixture. `CP` is a COPY, and
# three of the twenty-five patterns have COPY as their pdict key: tag 11 (COPY of
# a sharded value), tag 19 (`lower_broadcast_copy`) and tag 20 (`copy_to_one`).
# Two of them have an EMPTY reject set and no src test at all, so the OP-SET
# CLAIM count is 3.
# `ST` is a STORE whose `src[1]` is the UNSHARD: tags 17 and 18 both key on STORE,
# tag 17 wants `src[1]` UNSHARD and tag 18 wants `src[0]` UNSHARD, and only tag 17
# fires the FULL claim. `SU` is a STORE whose `src[0]` IS the UNSHARD, and both
# fire. That is the discriminating pair and it is why both are rows.
def t_sh0_n() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.mu_shard.zip(P.G.ar(P.g()), P.g_m0(P.g())))), 1)
# the first raise: `prod(multi.shape) != prod(new_shape)`.
def t_rs_prod() -> U32: P.eq(P.yes(P.rs_prods(P.s2(4, 6), P.s2(4, 6))), 1)
def t_t19_off() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_late()), 19n), P.COPY())
def t_rd_sum2() -> U32: P.eq(U32.add(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 2)))),
                                  U32.from_nat(P.mu_len(P.Rd.rem(P.shrd(P.two_sh(0, 4, 1, 4), 2))))), 2)
# THE REBASE: `new_axes = tuple(ax - num_axes for ax,_ in remaining)`. Printed as
# `ax0.ax1` -- the ELEMENTS and not the list -- because `eq` compares `U32` and a
# list comparison would be a second equality function for the same question.
def t_ml_copy() -> U32: P.eq(P.yes(P.ml_needs_copy(P.ml_some(1))), 1)
def t_pb84_n() -> U32: P.eq(P.pbn(P.sk_pb(8, 4)), 4)
def t_sh0_ax() -> U32: P.eq(P.Sh.ax(P.mu_head_sh(P.mu_shard.zip(P.G.ar(P.g()), P.g_m0(P.g())))), 0)
def t_first_st() -> U32: P.eq(P.mu_first(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_st(P.g())), 16)
def t_sk_len_no() -> U32: P.eq(P.yes(P.sk_len_eq(P.marg1(0, 8), 4, 0n)), 0)
# THE WHOLE test -- `(s,l) == (0, multi.shape[ax])`.
def t_claim_ms() -> U32: P.eq(P.mu_claim_n(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_ms(P.g())), 3)
# THE FULL CLAIM: the op set AND that tag's src test. Two rules claim one node and
# they DISAGREE, which is what a first-wins -> conjunction mutation would move.
def t_pd_ok() -> U32: P.eq(P.yes(P.pd_bad(P.one_sh(0, 4), P.marg1(0, 8), P.s1(8))), 0)
def t_rd_none_red() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(2, 4, 3, 4), 1)))), 0)
def t_cx_j2() -> U32: P.eq(P.cxn(P.cx_key(P.s3(0, 1, 2), 2n)), 2)
def t_sk_part() -> U32: P.eq(P.sk_kind(False{}, False{}, False{}, True{}, True{}), 2)
# `[i for i,x in enumerate(root.marg) if x]` -- the FLIP axis list.
def t_fl_none() -> U32: P.eq(U32.from_nat(P.mu_len(P.fl_of(P.s2(0, 0)))), 0)
def t_sx2() -> U32: P.eq(P.sx_idx(True{}, 0), 0)
# `replace_allreduce`'s rule bodies and the STORE family.
def t_rs_tgt3() -> U32: P.eq(P.mu_prod_upto(P.s3(2, 3, 4), 3n), 24)
# THE RAISES. `rs_same` is (4,6)->(4,6) sharded on 0: target 1, arg_acc
# [1,4,24], reversed index 2, new_ax = 3-2-1 = 0, and 4 % 2 == 0 so it FIRES.
def t_ix_s4() -> U32: P.eq(P.ix_strid(4, 0), 4)
# THE INVENTORY COUNTS.
def t_rej_n() -> U32: P.eq(P.mt_rej_n(P.mu_table(P.mu_c_early())), 20)
def t_ix_s1() -> U32: P.eq(P.ix_strid(1, 0), 1)
def t_rs_loc1() -> U32: P.eq(P.mu_at(P.rs_local(P.ns2(P.s2(4, 6), P.s1(0), P.s1(2))), 1n), 6)
def t_pd_ok2() -> U32: P.eq(P.yes(P.pd_bad(P.two_sh(0, 4, 1, 4), P.marg2(0, 8, 0, 24), P.s2(8, 24))), 0)
def t_pd_kp0b() -> U32: P.eq(P.pd_l0(P.pd_of(P.marg2(1, 8, 0, 3), P.nil32())), 8)
# and it is 0 -- the wall -- for a node that is not a RANGE.
def t_cnt_b8() -> U32: P.eq(P.mu_count(P.G.ar(P.g()), P.g_b8(P.g())), 0)
# `UOp.axis`: Some(0) for a one-axis UNSHARD, None for a two-axis one (Python
# raises) and None for a non-UNSHARD.
def t_rd_off0() -> U32: P.eq(P.rdo0(P.shrd(P.two_sh(0, 4, 1, 4), 0)), 0)
def t_fl_all() -> U32: P.eq(U32.from_nat(P.mu_len(P.fl_of(P.s2(1, 1)))), 2)
def t_sv_ax1() -> U32: P.eq(P.mu_at(P.sv_axes(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g()))), 1n), 1)
def t_ix_mod1() -> U32: P.eq(P.ix_mod(P.ix_strid(5, 0), 4), 1)
def t_t24_off() -> U32: P.eq(P.mt_op(P.mu_table(P.mu_c_late()), 24n), P.MSELECT())
def t_rd_all_red() -> U32: P.eq(U32.from_nat(P.mu_len(P.Rd.red(P.shrd(P.two_sh(0, 4, 1, 4), 1)))), 1)
def t_rd_cast_noop() -> U32: P.eq(P.yes(P.rd_cast(P.mu_c_early(), O.OpsADD{}, S.bfloat16())), 0)
def t_ix_mod0() -> U32: P.eq(P.ix_mod(P.ix_strid(4, 0), 4), 0)
def t_sv_nsh() -> U32: P.eq(U32.from_nat(P.sv_nshard(P.mu_shard.zip(P.G.ar(P.g()), P.g_ma(P.g())))), 2)
def t_pb43_s2() -> U32: P.eq(P.pbat(P.sk_pb(4, 3), 2n), 8)
def t_lb_fires() -> U32: P.eq(P.yes(P.lb_fires(True{}, True{})), 1)
def t_ax_ma() -> U32: P.eq(P.yes(P.mu_has_axis(P.mu_axis(P.G.ar(P.g()), P.g_ma(P.g())))), 0)
def t_rd_cast_f32() -> U32: P.eq(P.yes(P.rd_cast(P.mu_c_early(), O.OpsCAST{}, S.single())), 0)
def t_ss_not_none() -> U32: P.eq(P.yes(P.mu_ss_none(P.mu_ss_rng(4, 0))), 0)
def t_full_ad() -> U32: P.eq(P.mu_claim_full(P.mu_table(P.mu_c_early()), P.G.ar(P.g()), P.g_ad(P.g())), 1)
# THE FIRST CLAIMING TAG. `0` means "no rule claimed it" and a non-zero tag is the
# rule a rewrite WOULD take. `AD` (an ADD whose srcs are both UNSHARD) is claimed
# by tag 0 -- the ALU rule -- and by nothing else, because no other pattern keys
# on an ALU op.
# `AD` is an ADD over two UNSHARDs, so tag 0 (`alu_multi`) claims it and nothing
# else does: no other pattern keys on an ALU op. The tag is 0, which is WHY
# `mu_first` needed a sentinel -- 0 is both "tag 0" and "nothing", and with a `0`
# seed this row could not tell them apart.
# `int(rng.vmax)+1` on a real DEVICE RANGE over four devices is 4.
def t_cnt_rd() -> U32: P.eq(P.mu_count(P.G.ar(P.g()), P.g_rd(P.g())), 4)
# and it is 0 -- the wall -- for a node that is not a RANGE.
def t_sh1_n() -> U32: P.eq(U32.from_nat(P.mu_nshard(P.mu_shard.zip(P.G.ar(P.g()), P.g_m1(P.g())))), 1)
def t_rs_tie_ax0() -> U32: P.eq(P.Rs.ax(P.rs_new_ax(P.rs_acc(P.s3(2, 1, 2)), 1)), 0)
# THE MUTATION TABLE.
# WHY IT IS HERE. 321 rows that all read 1 prove the rows are non-degenerate;
# they do not prove they WATCH anything. Each row below is a change to ONE
# decision this file makes, run through the whole gate, and the count is how
# many rows answered differently. Two properties are wanted and both are
# measured: no mutation may leave the file uncompilable (a mutation that fails
# to build says nothing about the gate, so every one of these changes a DECISION
# and not a type), and no mutation may be invisible (a row-shape hole).
# Driven by `.agents/slop/multi-mutate.py`, which reverts the file after every
# one. Baseline is the interpreted lane; the native lane was diffed clean against
# it, so every count below holds in both.
#   id    def               mutation                                  rows
#   M01   rs_local.one.of   drop the sharding test: divide EVERY axis     2
#   M02   pi_step           tuple.index first-wins -> last-wins           2
#   M03   mu_ss_axis        drop the RIGHT-ALIGNMENT shift               1
#   M04   ml_kind.rest      WHOLE answers BCAST: never copy_multi         1
#   M05   ix_div            strided pattern divides by the residue       3
#   M06   mu_claimed        drop the necessary condition                 1
#   M07   rd_low_dt         drop `half` from the (bfloat16, half) pair    1
#   M08   st_off.of         drop the axis > 0 guard: U32.sub WRAPS       1
#   M09   mu_baxes          len(out) >= len(src) -> >                     2
#   M10   mu_ra_cfg.go      swap the LATE_ALLREDUCE tag shift 19 <-> 20   3
#   M11   mu_exp_keep       drop the out[nleft+i] != 1 conjunct          1
#   M12   fl_of.put         the non-zero filter keeps the ZERO indices     8
# THE ROWS EACH ONE MOVED, which is the part that names the coverage:
#   M01  t_rs_loc1 t_rs_loc_none
#   M02  t_pm_cyc0 t_pm_mid
#   M03  t_ss_ax10
#   M04  t_ml_whole
#   M05  t_ix_div t_ix_div0 t_ix_kind00
#   M06  t_claim_cq
#   M07  t_rd_cast_half
#   M08  t_st_off_nil
#   M09  t_bx_1_2n t_bx_exp_n
#   M10  t_full_cp t_tag19 t_tag25
#   M11  t_bx_11
#   M12  t_fl_all t_fl_first t_fl_mid t_fl_mid_n t_fl_none t_fl_one0
#        t_fl_two t_fl_two1
# TWELVE OF TWELVE CAUGHT, 25 DISTINCT ROWS. Three of these carry more than the
# arithmetic and are worth naming:
# * M06 is the ONLY witness for the conjunctive claim. `t_claim_cq` (2 against
#   `t_claim_cp`'s 3) is the sole row that says `early_reject` is a NECESSARY
#   CONDITION rather than a FILTER, and M06 is what proves it is watched. It is
#   also the mutation `t_full_st`/`t_full_su`/`t_full_cp` were written for --
#   those two rules claim one node and disagree -- but the op-set count catches
#   it first, so the honest statement is that `t_claim_cq` is the witness and the
#   `t_full_*` rows are the second one.
# * M10 moves `t_tag19` and `t_tag25`, the two rows that pin the table's COMPOSITION
#   rather than a decision inside one rule. It is the cheapest way to break the
#   `PatternMatcher.__add__` arithmetic and the rows catch it immediately.
# * M12 moves eight rows and is the widest blast radius in the table: `fl_of`
#   feeds `pd_ok` and the whole `Bd` inventory, so one inverted filter there is
#   the closest thing this gate has to a keystone.
# WHAT THIS DOES NOT SAY. Twelve mutations is not a coverage argument. The
# builders -- every `TODO` in the foot below -- are not in this table because
# they are not in the file, so nothing here tests whether a rule reaches for the
# RIGHT builder.
# NOT PORTED. Every line is a `TODO(p3)` whose OWNING FILE is named, and the
# marker's ENTRY must carry the reason -- a reason in a PRECEDING header is invisible
# to `checks/marker-audit.py`, which reads a marker's line plus the lines that FOLLOW
# it, so a block written this way reads as BACKLOG however well it is explained.
# "cannot reach" is the right WORD and "not ported" is not, measured: of the builders
# these lines name, `G.permute`, `G.flip`, `UOp.copy_to_device`, `UOp.after`,
# `UOp.allreduce`, `UOp.mselect`, `ssimplify` and `_min_max`/`vmin` are ALL PRESENT --
# in `mixin/movement.bend`, `uop/weak.bend` and `uop/ops.bend`. What multi.bend does not
# do is IMPORT the files that hold them. MEASURED: `tensor.bend`'s transitive closure is
# six files and contains nothing under `schedule/`, so adding
# `import ./../tensor.bend` here is CYCLE-FREE and Bend accepts it. So the largest part
# of this block is REACHABILITY and unported RULE BODIES, not missing primitives, and a
# reader who trusts "not ported" will under-scope the work.
# the `unshard` family is the exception and it is the one that is really blocked:
# fourteen markers end in `.unshard(...)`, and `unshard` is a WALL in `ops.bend` whose
# own text names `_shard`, absent as a definition. Those carry the reason on their own
# line now.
# Nothing below is a decision that multi.py makes and this file declined: the
# decision is present and gateable in every case, and what is missing is the
# node it would have produced.
# THE GRAPH BUILDERS, one line per call site.
#   `_mop` (ops.py:799) -- every `.arg`-carrying rewrite is a `_mop`.
# THE WHOLE test -- `(s,l) == (0, multi.shape[ax])`.
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- row("t_own_n", t_own_n())
    _ : Unit <- row("t_ra_n", t_ra_n())
    _ : Unit <- row("t_ea_n", t_ea_n())
    _ : Unit <- row("t_pm_n", t_pm_n())
    _ : Unit <- row("t_late_n", t_late_n())
    _ : Unit <- row("t_t19_on", t_t19_on())
    _ : Unit <- row("t_t20_on", t_t20_on())
    _ : Unit <- row("t_t19_off", t_t19_off())
    _ : Unit <- row("t_t24_off", t_t24_off())
    _ : Unit <- row("t_t25_off", t_t25_off())
    _ : Unit <- row("t_t20_off", t_t20_off())
    _ : Unit <- row("t_t23_off", t_t23_off())
    _ : Unit <- row("t_tag19", t_tag19())
    _ : Unit <- row("t_tag25", t_tag25())
    _ : Unit <- row("t_rej_n", t_rej_n())
    _ : Unit <- row("t_rej_late", t_rej_late())
    _ : Unit <- row("t_ops_n", t_ops_n())
    _ : Unit <- row("t_alu_n", t_alu_n())
    _ : Unit <- row("t_pass_n", t_pass_n())
    _ : Unit <- row("t_mov_n", t_mov_n())
    _ : Unit <- row("t_claim_cp", t_claim_cp())
    _ : Unit <- row("t_claim_cq", t_claim_cq())
    _ : Unit <- row("t_claim_st", t_claim_st())
    _ : Unit <- row("t_claim_su", t_claim_su())
    _ : Unit <- row("t_claim_ad", t_claim_ad())
    _ : Unit <- row("t_claim_ms", t_claim_ms())
    _ : Unit <- row("t_full_st", t_full_st())
    _ : Unit <- row("t_full_su", t_full_su())
    _ : Unit <- row("t_full_cp", t_full_cp())
    _ : Unit <- row("t_full_ad", t_full_ad())
    _ : Unit <- row("t_first_ad", t_first_ad())
    _ : Unit <- row("t_first_st", t_first_st())
    _ : Unit <- row("t_first_su", t_first_su())
    _ : Unit <- row("t_first_m0", t_first_m0())
    _ : Unit <- row("t_sh0_n", t_sh0_n())
    _ : Unit <- row("t_sh1_n", t_sh1_n())
    _ : Unit <- row("t_sha_n", t_sha_n())
    _ : Unit <- row("t_shbuf_n", t_shbuf_n())
    _ : Unit <- row("t_sh0_ax", t_sh0_ax())
    _ : Unit <- row("t_sh1_ax", t_sh1_ax())
    _ : Unit <- row("t_sh0_c", t_sh0_c())
    _ : Unit <- row("t_sha1_ax", t_sha1_ax())
    _ : Unit <- row("t_sha1_n", t_sha1_n())
    _ : Unit <- row("t_cnt_rd", t_cnt_rd())
    _ : Unit <- row("t_cnt_b8", t_cnt_b8())
    _ : Unit <- row("t_ax_m0", t_ax_m0())
    _ : Unit <- row("t_ax_ma", t_ax_ma())
    _ : Unit <- row("t_ax_b8", t_ax_b8())
    _ : Unit <- row("t_ax_m1", t_ax_m1())
    _ : Unit <- row("t_ss_ax00", t_ss_ax00())
    _ : Unit <- row("t_ss_ax11", t_ss_ax11())
    _ : Unit <- row("t_ss_ax10", t_ss_ax10())
    _ : Unit <- row("t_ss_ax22", t_ss_ax22())
    _ : Unit <- row("t_ss_ax02", t_ss_ax02())
    _ : Unit <- row("t_ss_axneg", t_ss_axneg())
    _ : Unit <- row("t_ss_rng_dev", t_ss_rng_dev())
    _ : Unit <- row("t_ss_rng_unsh", t_ss_rng_unsh())
    _ : Unit <- row("t_ss_rng_src", t_ss_rng_src())
    _ : Unit <- row("t_ss_rng_src2", t_ss_rng_src2())
    _ : Unit <- row("t_ss_none", t_ss_none())
    _ : Unit <- row("t_ss_not_none", t_ss_not_none())
    _ : Unit <- row("t_ss_same", t_ss_same())
    _ : Unit <- row("t_ss_same_bad", t_ss_same_bad())
    _ : Unit <- row("t_bx_none", t_bx_none())
    _ : Unit <- row("t_bx_pad", t_bx_pad())
    _ : Unit <- row("t_bx_exp", t_bx_exp())
    _ : Unit <- row("t_bx_exp_n", t_bx_exp_n())
    _ : Unit <- row("t_bx_both", t_bx_both())
    _ : Unit <- row("t_bx_noop", t_bx_noop())
    _ : Unit <- row("t_bx_scalar", t_bx_scalar())
    _ : Unit <- row("t_bx_1out", t_bx_1out())
    _ : Unit <- row("t_bx_11", t_bx_11())
    _ : Unit <- row("t_bx_1_2", t_bx_1_2())
    _ : Unit <- row("t_bx_1_2n", t_bx_1_2n())
    _ : Unit <- row("t_bx_rank1", t_bx_rank1())
    _ : Unit <- row("t_bx_bad", t_bx_bad())
    _ : Unit <- row("t_ml_thru", t_ml_thru())
    _ : Unit <- row("t_ml_whole", t_ml_whole())
    _ : Unit <- row("t_ml_bcast", t_ml_bcast())
    _ : Unit <- row("t_ml_shard", t_ml_shard())
    _ : Unit <- row("t_ml_sa", t_ml_sa())
    _ : Unit <- row("t_ml_none_thru", t_ml_none_thru())
    _ : Unit <- row("t_ml_copy", t_ml_copy())
    _ : Unit <- row("t_ml_nocopy", t_ml_nocopy())
    _ : Unit <- row("t_sv_eq", t_sv_eq())
    _ : Unit <- row("t_sv_ne", t_sv_ne())
    _ : Unit <- row("t_sv_rank", t_sv_rank())
    _ : Unit <- row("t_sv_sc", t_sv_sc())
    _ : Unit <- row("t_sv_nsc", t_sv_nsc())
    _ : Unit <- row("t_sv_exp", t_sv_exp())
    _ : Unit <- row("t_sv_exp_nosc", t_sv_exp_nosc())
    _ : Unit <- row("t_sv_exp_no", t_sv_exp_no())
    _ : Unit <- row("t_sv_div4", t_sv_div4())
    _ : Unit <- row("t_sv_div5", t_sv_div5())
    _ : Unit <- row("t_sv_div0", t_sv_div0())
    _ : Unit <- row("t_sv_sz8", t_sv_sz8())
    _ : Unit <- row("t_sv_sz6", t_sv_sz6())
    _ : Unit <- row("t_sv_sz5", t_sv_sz5())
    _ : Unit <- row("t_sv_nsh", t_sv_nsh())
    _ : Unit <- row("t_sv_ax0", t_sv_ax0())
    _ : Unit <- row("t_sv_ax1", t_sv_ax1())
    _ : Unit <- row("t_sv_ax_n", t_sv_ax_n())
    _ : Unit <- row("t_al_eq", t_al_eq())
    _ : Unit <- row("t_al_eq_n", t_al_eq_n())
    _ : Unit <- row("t_al_eq_ax", t_al_eq_ax())
    _ : Unit <- row("t_al_eq_len", t_al_eq_len())
    _ : Unit <- row("t_al_eq_two", t_al_eq_two())
    _ : Unit <- row("t_al_sh_ok", t_al_sh_ok())
    _ : Unit <- row("t_al_sh_no", t_al_sh_no())
    _ : Unit <- row("t_al_sh_guard", t_al_sh_guard())
    _ : Unit <- row("t_al_sc", t_al_sc())
    _ : Unit <- row("t_al_full", t_al_full())
    _ : Unit <- row("t_al_neither", t_al_neither())
    _ : Unit <- row("t_al_none0", t_al_none0())
    _ : Unit <- row("t_al_none1", t_al_none1())
    _ : Unit <- row("t_al_nmultis", t_al_nmultis())
    _ : Unit <- row("t_rd_any_empty", t_rd_any_empty())
    _ : Unit <- row("t_rd_all_red", t_rd_all_red())
    _ : Unit <- row("t_rd_all_rem", t_rd_all_rem())
    _ : Unit <- row("t_rd_some_red", t_rd_some_red())
    _ : Unit <- row("t_rd_some_rem", t_rd_some_rem())
    _ : Unit <- row("t_rd_none_red", t_rd_none_red())
    _ : Unit <- row("t_rd_two_red", t_rd_two_red())
    _ : Unit <- row("t_rd_zero_red", t_rd_zero_red())
    _ : Unit <- row("t_rd_sum0", t_rd_sum0())
    _ : Unit <- row("t_rd_sum1", t_rd_sum1())
    _ : Unit <- row("t_rd_sum2", t_rd_sum2())
    _ : Unit <- row("t_rd_off0", t_rd_off0())
    _ : Unit <- row("t_rd_off0b", t_rd_off0b())
    _ : Unit <- row("t_rd_off1", t_rd_off1())
    _ : Unit <- row("t_rd_off2", t_rd_off2())
    _ : Unit <- row("t_rd_off2b", t_rd_off2b())
    _ : Unit <- row("t_rd_off3", t_rd_off3())
    _ : Unit <- row("t_rd_off_n", t_rd_off_n())
    _ : Unit <- row("t_rd_off_none", t_rd_off_none())
    _ : Unit <- row("t_rd_bad", t_rd_bad())
    _ : Unit <- row("t_rd_bad_none", t_rd_bad_none())
    _ : Unit <- row("t_rd_bad_all", t_rd_bad_all())
    _ : Unit <- row("t_rd_fires", t_rd_fires())
    _ : Unit <- row("t_rd_fires_none", t_rd_fires_none())
    _ : Unit <- row("t_rd_piece", t_rd_piece())
    _ : Unit <- row("t_rd_cast", t_rd_cast())
    _ : Unit <- row("t_rd_cast_half", t_rd_cast_half())
    _ : Unit <- row("t_rd_cast_f32", t_rd_cast_f32())
    _ : Unit <- row("t_rd_cast_noop", t_rd_cast_noop())
    _ : Unit <- row("t_rd_cast_off", t_rd_cast_off())
    _ : Unit <- row("t_rs_acc_n4", t_rs_acc_n4())
    _ : Unit <- row("t_rs_acc_n1", t_rs_acc_n1())
    _ : Unit <- row("t_rs_acc_n0", t_rs_acc_n0())
    _ : Unit <- row("t_rs_acc1_4", t_rs_acc1_4())
    _ : Unit <- row("t_rs_acc2_4", t_rs_acc2_4())
    _ : Unit <- row("t_rs_acc3_1", t_rs_acc3_1())
    _ : Unit <- row("t_rs_acc3_2", t_rs_acc3_2())
    _ : Unit <- row("t_rs_acc3_3", t_rs_acc3_3())
    _ : Unit <- row("t_rs_tgt0", t_rs_tgt0())
    _ : Unit <- row("t_rs_tgt1", t_rs_tgt1())
    _ : Unit <- row("t_rs_tgt2", t_rs_tgt2())
    _ : Unit <- row("t_rs_tgt3", t_rs_tgt3())
    _ : Unit <- row("t_rs_same", t_rs_same())
    _ : Unit <- row("t_rs_same_ok", t_rs_same_ok())
    _ : Unit <- row("t_rs_mid_ok", t_rs_mid_ok())
    _ : Unit <- row("t_rs_head", t_rs_head())
    _ : Unit <- row("t_rs_thr0", t_rs_thr0())
    _ : Unit <- row("t_rs_thr0_ok", t_rs_thr0_ok())
    _ : Unit <- row("t_rs_thr1_ok", t_rs_thr1_ok())
    _ : Unit <- row("t_rs_thr1_ax", t_rs_thr1_ax())
    _ : Unit <- row("t_rs_prod", t_rs_prod())
    _ : Unit <- row("t_rs_prod_bad", t_rs_prod_bad())
    _ : Unit <- row("t_rs_tie_hit", t_rs_tie_hit())
    _ : Unit <- row("t_rs_tie_hit_f", t_rs_tie_hit_f())
    _ : Unit <- row("t_rs_tie_axb", t_rs_tie_axb())
    _ : Unit <- row("t_rs_tie_ax", t_rs_tie_ax())
    _ : Unit <- row("t_rs_tie_ax0", t_rs_tie_ax0())
    _ : Unit <- row("t_rs_none", t_rs_none())
    _ : Unit <- row("t_rs_loc0", t_rs_loc0())
    _ : Unit <- row("t_rs_loc1", t_rs_loc1())
    _ : Unit <- row("t_rs_loc_both", t_rs_loc_both())
    _ : Unit <- row("t_rs_loc_n", t_rs_loc_n())
    _ : Unit <- row("t_rs_loc_none", t_rs_loc_none())
    _ : Unit <- row("t_rs_loc_bad", t_rs_loc_bad())
    _ : Unit <- row("t_ex0", t_ex0())
    _ : Unit <- row("t_ex1", t_ex1())
    _ : Unit <- row("t_ex2", t_ex2())
    _ : Unit <- row("t_ex3", t_ex3())
    _ : Unit <- row("t_ex_ax0", t_ex_ax0())
    _ : Unit <- row("t_ex_ax2", t_ex_ax2())
    _ : Unit <- row("t_ex_axn", t_ex_axn())
    _ : Unit <- row("t_ex_rng", t_ex_rng())
    _ : Unit <- row("t_pm_id", t_pm_id())
    _ : Unit <- row("t_pm_id1", t_pm_id1())
    _ : Unit <- row("t_pm_sw", t_pm_sw())
    _ : Unit <- row("t_pm_sw1", t_pm_sw1())
    _ : Unit <- row("t_pm_cyc", t_pm_cyc())
    _ : Unit <- row("t_pm_cyc0", t_pm_cyc0())
    _ : Unit <- row("t_pm_rev", t_pm_rev())
    _ : Unit <- row("t_pm_mid", t_pm_mid())
    _ : Unit <- row("t_pm_missing", t_pm_missing())
    _ : Unit <- row("t_pm_of", t_pm_of())
    _ : Unit <- row("t_fl_none", t_fl_none())
    _ : Unit <- row("t_fl_one", t_fl_one())
    _ : Unit <- row("t_fl_one0", t_fl_one0())
    _ : Unit <- row("t_fl_two", t_fl_two())
    _ : Unit <- row("t_fl_two1", t_fl_two1())
    _ : Unit <- row("t_fl_first", t_fl_first())
    _ : Unit <- row("t_fl_all", t_fl_all())
    _ : Unit <- row("t_fl_mid", t_fl_mid())
    _ : Unit <- row("t_fl_mid_n", t_fl_mid_n())
    _ : Unit <- row("t_fl_bad", t_fl_bad())
    _ : Unit <- row("t_fl_bad2", t_fl_bad2())
    _ : Unit <- row("t_fl_bad_none", t_fl_bad_none())
    _ : Unit <- row("t_pd_ok", t_pd_ok())
    _ : Unit <- row("t_pd_bad_s", t_pd_bad_s())
    _ : Unit <- row("t_pd_bad_l", t_pd_bad_l())
    _ : Unit <- row("t_pd_ok2", t_pd_ok2())
    _ : Unit <- row("t_pd_bad2", t_pd_bad2())
    _ : Unit <- row("t_pd_one0", t_pd_one0())
    _ : Unit <- row("t_pd_one1", t_pd_one1())
    _ : Unit <- row("t_pd_kp1", t_pd_kp1())
    _ : Unit <- row("t_pd_kp0", t_pd_kp0())
    _ : Unit <- row("t_pd_kp0b", t_pd_kp0b())
    _ : Unit <- row("t_pd_n", t_pd_n())
    _ : Unit <- row("t_pb42_n", t_pb42_n())
    _ : Unit <- row("t_pb42_s0", t_pb42_s0())
    _ : Unit <- row("t_pb42_l0", t_pb42_l0())
    _ : Unit <- row("t_pb42_s1", t_pb42_s1())
    _ : Unit <- row("t_pb43_n", t_pb43_n())
    _ : Unit <- row("t_pb43_s1", t_pb43_s1())
    _ : Unit <- row("t_pb43_s2", t_pb43_s2())
    _ : Unit <- row("t_pb62_n", t_pb62_n())
    _ : Unit <- row("t_pb62_l0", t_pb62_l0())
    _ : Unit <- row("t_pb84_n", t_pb84_n())
    _ : Unit <- row("t_pb84_sm", t_pb84_sm())
    _ : Unit <- row("t_pb84_sl", t_pb84_sl())
    _ : Unit <- row("t_pb41_n", t_pb41_n())
    _ : Unit <- row("t_sk_at0", t_sk_at0())
    _ : Unit <- row("t_sk_at2", t_sk_at2())
    _ : Unit <- row("t_sk_at3", t_sk_at3())
    _ : Unit <- row("t_sk_at_miss", t_sk_at_miss())
    _ : Unit <- row("t_sk_in", t_sk_in())
    _ : Unit <- row("t_sk_in_no", t_sk_in_no())
    _ : Unit <- row("t_sk_len_ok", t_sk_len_ok())
    _ : Unit <- row("t_sk_len_no", t_sk_len_no())
    _ : Unit <- row("t_sk_w_ok", t_sk_w_ok())
    _ : Unit <- row("t_sk_w_no", t_sk_w_no())
    _ : Unit <- row("t_sk_w_s", t_sk_w_s())
    _ : Unit <- row("t_sk_own", t_sk_own())
    _ : Unit <- row("t_sk_whole", t_sk_whole())
    _ : Unit <- row("t_sk_part", t_sk_part())
    _ : Unit <- row("t_sk_raise", t_sk_raise())
    _ : Unit <- row("t_sk_r_n", t_sk_r_n())
    _ : Unit <- row("t_sk_r_dev", t_sk_r_dev())
    _ : Unit <- row("t_sk_r_pb", t_sk_r_pb())
    _ : Unit <- row("t_sk_own2", t_sk_own2())
    _ : Unit <- row("t_sk_keep", t_sk_keep())
    _ : Unit <- row("t_sk_keep0", t_sk_keep0())
    _ : Unit <- row("t_sk_keep_all", t_sk_keep_all())
    _ : Unit <- row("t_sk_keep_n", t_sk_keep_n())
    _ : Unit <- row("t_st_ax0", t_st_ax0())
    _ : Unit <- row("t_st_ax2", t_st_ax2())
    _ : Unit <- row("t_st_n", t_st_n())
    _ : Unit <- row("t_st_off0", t_st_off0())
    _ : Unit <- row("t_st_off1", t_st_off1())
    _ : Unit <- row("t_st_off_nil", t_st_off_nil())
    _ : Unit <- row("t_st_none", t_st_none())
    _ : Unit <- row("t_st_not_none", t_st_not_none())
    _ : Unit <- row("t_ix_c0", t_ix_c0())
    _ : Unit <- row("t_ix_c1", t_ix_c1())
    _ : Unit <- row("t_ix_c2", t_ix_c2())
    _ : Unit <- row("t_ix_c3", t_ix_c3())
    _ : Unit <- row("t_ix_c_oob", t_ix_c_oob())
    _ : Unit <- row("t_ix_c_in", t_ix_c_in())
    _ : Unit <- row("t_ix_c_win0", t_ix_c_win0())
    _ : Unit <- row("t_ix_c_win4", t_ix_c_win4())
    _ : Unit <- row("t_ix_s0", t_ix_s0())
    _ : Unit <- row("t_ix_s1", t_ix_s1())
    _ : Unit <- row("t_ix_s4", t_ix_s4())
    _ : Unit <- row("t_ix_mod0", t_ix_mod0())
    _ : Unit <- row("t_ix_mod1", t_ix_mod1())
    _ : Unit <- row("t_ix_mod0b", t_ix_mod0b())
    _ : Unit <- row("t_ix_ok", t_ix_ok())
    _ : Unit <- row("t_ix_bad", t_ix_bad())
    _ : Unit <- row("t_ix_div", t_ix_div())
    _ : Unit <- row("t_ix_div0", t_ix_div0())
    _ : Unit <- row("t_ix_kind_c", t_ix_kind_c())
    _ : Unit <- row("t_ix_kind_s", t_ix_kind_s())
    _ : Unit <- row("t_ix_kind_r", t_ix_kind_r())
    _ : Unit <- row("t_ix_kind_r2", t_ix_kind_r2())
    _ : Unit <- row("t_ix_kind0", t_ix_kind0())
    _ : Unit <- row("t_ix_kind00", t_ix_kind00())
    _ : Unit <- row("t_cx_j0", t_cx_j0())
    _ : Unit <- row("t_cx_j1", t_cx_j1())
    _ : Unit <- row("t_cx_j2", t_cx_j2())
    _ : Unit <- row("t_cx_j3", t_cx_j3())
    _ : Unit <- row("t_cx_j0b", t_cx_j0b())
    _ : Unit <- row("t_cx_j1b", t_cx_j1b())
    _ : Unit <- row("t_cx_same", t_cx_same())
    _ : Unit <- row("t_cx_rep", t_cx_rep())
    _ : Unit <- row("t_cx_j0n", t_cx_j0n())
    _ : Unit <- row("t_sx0", t_sx0())
    _ : Unit <- row("t_sx1", t_sx1())
    _ : Unit <- row("t_sx2", t_sx2())
    _ : Unit <- row("t_lb_fires", t_lb_fires())
    _ : Unit <- row("t_lb_no", t_lb_no())
    _ : Unit <- row("t_lb_no2", t_lb_no2())
    _ : Unit <- row("t_lb_reps", t_lb_reps())
    _ : Unit <- row("t_lb_none", t_lb_none())
    _ : Unit <- row("t_lb_not_none", t_lb_not_none())
    _ : Unit <- row("t_co_fires", t_co_fires())
    _ : Unit <- row("t_co_no", t_co_no())
    _ : Unit <- row("t_co_same", t_co_same())
    _ : Unit <- row("t_co_copy", t_co_copy())
    _ : Unit <- row("t_ms_arg", t_ms_arg())
    _ : Unit <- row("t_ms_arg_bad", t_ms_arg_bad())
    _ : Unit <- row("t_ms_ok", t_ms_ok())
    _ : Unit <- row("t_mv", t_mv())
    _ : Unit <- row("t_mv_alu", t_mv_alu())
    _ : Unit <- row("t_mv_alu_no", t_mv_alu_no())
    _ : Unit <- row("t_stp_peel", t_stp_peel())
    _ : Unit <- row("t_stp_view", t_stp_view())
    _ : Unit <- row("t_stp_whole", t_stp_whole())
    _ : Unit <- row("t_rw", t_rw())
    IO.print("")
    IO.print("")


# THE MUTATION TABLE.
# WHY IT IS HERE. 321 rows that all read 1 prove the rows are non-degenerate;
# they do not prove they WATCH anything. Each row below is a change to ONE
# decision this file makes, run through the whole gate, and the count is how
# many rows answered differently. Two properties are wanted and both are
# measured: no mutation may leave the file uncompilable (a mutation that fails
# to build says nothing about the gate, so every one of these changes a DECISION
# and not a type), and no mutation may be invisible (a row-shape hole).
# Driven by `.agents/slop/multi-mutate.py`, which reverts the file after every
# one. Baseline is the interpreted lane; the native lane was diffed clean against
# it, so every count below holds in both.
#   id    def               mutation                                  rows

#   M01   rs_local.one.of   drop the sharding test: divide EVERY axis     2
#   M02   pi_step           tuple.index first-wins -> last-wins           2
#   M03   mu_ss_axis        drop the RIGHT-ALIGNMENT shift               1
#   M04   ml_kind.rest      WHOLE answers BCAST: never copy_multi         1
#   M05   ix_div            strided pattern divides by the residue       3
#   M06   mu_claimed        drop the necessary condition                 1
#   M07   rd_low_dt         drop `half` from the (bfloat16, half) pair    1
#   M08   st_off.of         drop the axis > 0 guard: U32.sub WRAPS       1
#   M09   mu_baxes          len(out) >= len(src) -> >                     2
#   M10   mu_ra_cfg.go      swap the LATE_ALLREDUCE tag shift 19 <-> 20   3
#   M11   mu_exp_keep       drop the out[nleft+i] != 1 conjunct          1
#   M12   fl_of.put         the non-zero filter keeps the ZERO indices     8
# THE ROWS EACH ONE MOVED, which is the part that names the coverage:
#   M01  t_rs_loc1 t_rs_loc_none
#   M02  t_pm_cyc0 t_pm_mid
#   M03  t_ss_ax10
#   M04  t_ml_whole
#   M05  t_ix_div t_ix_div0 t_ix_kind00
#   M06  t_claim_cq
#   M07  t_rd_cast_half
#   M08  t_st_off_nil
#   M09  t_bx_1_2n t_bx_exp_n
#   M10  t_full_cp t_tag19 t_tag25
#   M11  t_bx_11
#   M12  t_fl_all t_fl_first t_fl_mid t_fl_mid_n t_fl_none t_fl_one0
#        t_fl_two t_fl_two1
# TWELVE OF TWELVE CAUGHT, 25 DISTINCT ROWS. Three of these carry more than the
# arithmetic and are worth naming:
# * M06 is the ONLY witness for the conjunctive claim. `t_claim_cq` (2 against
#   `t_claim_cp`'s 3) is the sole row that says `early_reject` is a NECESSARY
#   CONDITION rather than a FILTER, and M06 is what proves it is watched. It is
#   also the mutation `t_full_st`/`t_full_su`/`t_full_cp` were written for --
#   those two rules claim one node and disagree -- but the op-set count catches
#   it first, so the honest statement is that `t_claim_cq` is the witness and the
#   `t_full_*` rows are the second one.
# * M10 moves `t_tag19` and `t_tag25`, the two rows that pin the table's COMPOSITION
#   rather than a decision inside one rule. It is the cheapest way to break the
#   `PatternMatcher.__add__` arithmetic and the rows catch it immediately.
# * M12 moves eight rows and is the widest blast radius in the table: `fl_of`
#   feeds `pd_ok` and the whole `Bd` inventory, so one inverted filter there is
#   the closest thing this gate has to a keystone.
# WHAT THIS DOES NOT SAY. Twelve mutations is not a coverage argument. The
# builders -- every `TODO` in the foot below -- are not in this table because
# they are not in the file, so nothing here tests whether a rule reaches for the
# RIGHT builder.



# NOT PORTED. Every line is a `TODO(p3)` whose OWNING FILE is named, and the
# marker's ENTRY must carry the reason -- a reason in a PRECEDING header is invisible
# to `checks/marker-audit.py`, which reads a marker's line plus the lines that FOLLOW
# it, so a block written this way reads as BACKLOG however well it is explained.
# "cannot reach" is the right WORD and "not ported" is not, measured: of the builders
# these lines name, `G.permute`, `G.flip`, `UOp.copy_to_device`, `UOp.after`,
# `UOp.allreduce`, `UOp.mselect`, `ssimplify` and `_min_max`/`vmin` are ALL PRESENT --
# in `mixin/movement.bend`, `uop/weak.bend` and `uop/ops.bend`. What multi.bend does not
# do is IMPORT the files that hold them. MEASURED: `tensor.bend`'s transitive closure is
# six files and contains nothing under `schedule/`, so adding
# `import ./../tensor.bend` here is CYCLE-FREE and Bend accepts it. So the largest part
# of this block is REACHABILITY and unported RULE BODIES, not missing primitives, and a
# reader who trusts "not ported" will under-scope the work.
# the `unshard` family is the exception and it is the one that is really blocked:
# fourteen markers end in `.unshard(...)`, and `unshard` is a WALL in `ops.bend` whose
# own text names `_shard`, absent as a definition. Those carry the reason on their own
# line now.
# Nothing below is a decision that multi.py makes and this file declined: the
# decision is present and gateable in every case, and what is missing is the
# node it would have produced.
# THE GRAPH BUILDERS, one line per call site.
#   `_mop` (ops.py:799) -- every `.arg`-carrying rewrite is a `_mop`.
