# gates/allreduce-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/allreduce.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/allreduce.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def red_row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
# --- the selection, allreduce.py:13-16 --------------------------------------
# ndev=2 is the empirical "only 2 nodes" arm and RING is ON: NAIVE. This is the row
# that says `ndev > 2` is really tested.
def k_96_s3() -> U32: P.red_eq(P.Chk.s(P.red_at(P.red_bounds_of(96, 4), 3)), 96)
# --- the node-local branch, allreduce.py:22-28 ------------------------------
# `concrete and hdev > 0 and ndev % hdev == 0` -- and hdev=3 on ndev=8 is the row
# that says the modulus is tested.
def hv_4() -> U32: P.red_if(P.red_hdev_fires(8, 4))
# THE SAME ROW, one element above the threshold, which IS ring. Together with
# `sel_thr` this pins the comparison and not just its result.
def sel_thr1() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(256001), 4, P.red_c_on())), 1)
# `concrete and` IN `use_all2all`, not only in `use_ring`. `sel_sym` uses RING=2 and
# ALL2ALL=0, so it says nothing about the all2all expression -- measured: dropping
# `concrete` from `red_a2` moved nothing until this row existed. A symbolic shape
# with ALL2ALL FORCED is still NAIVE.
# and `concrete` itself, so the reason above is the test and not the threshold.
def sel_sym_c() -> U32:
  P.red_if(P.Sel.concrete(P.red_sel(P.red_shsym(300000), 4, P.red_c_r2())))
# a symbolic dim also zeroes `numel`, because `dim_of` counts `SS{..}` as 0.
def k_100_s1() -> U32: P.red_eq(P.Chk.s(P.red_at(P.red_bounds_of(100, 4), 1)), 28)
def ch_100_l() -> U32: P.red_eq(P.Ch.left(P.red_chunk(100, 4)), 1)
def hv_cs2_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_cs_of(1000, 2)))
# THE GATE DOCUMENT. `1` is True, `0` is False, and a COUNT row prints the count.
# Every value is CPython's: `.agents/slop/notes/sched-allreduce-truth.py` ran
# `allreduce.py:13-15`, `:22-28` and `:36-38` verbatim and printed them.
#
#   sel_two=1 sel_big=1 sel_three=1 sel_small=1
#     the four corners of the empirical claim at allreduce.py:11-15. ndev=2 is NAIVE,
#     ndev=3 and ndev=4 at 300k are RING, and 100 elements at ndev=4 is NAIVE.
#   sel_a2_1=1 sel_a2_0=1
#     ALL2ALL 1 is enough ("on, subject to the empirical test") and ALL2ALL 0 is not.
#   sel_a2_force=1 sel_r2_force=1
#     `>= 2` forces, under the threshold AND at ndev=2. Both overrides ignore both
#     empirical conditions, which is what the `>= 2` is for.
#   sel_both=1
#     RING 2 with ALL2ALL 2 is ALL2ALL: the `and not use_all2all` inside `use_ring`.
#   sel_sym=1 sel_sym_c=0 sel_sym_n=1
#     a SYMBOLIC dim is not concrete, so a FORCED ring still falls back to NAIVE;
#     `sel_sym_c` is the reason (0 = not concrete) and `sel_sym_n` says `numel` is 0.
#   sel_two_big=1
#     ndev=2 at 300k with RING on: still NAIVE. This is the ONLY row that tells
#     `ndev > 2` from `ndev >= 2` -- `sel_two` cannot, because its size test fails
#     anyway and both readings give NAIVE. Measured: that mutation moved nothing until
#     this row existed.
#   sel_thr=1 sel_thr1=1
#     exactly 256000 is NAIVE and 256001 is RING, so the comparison is `>` and not
#     `>=`. Same story: the mutation moved nothing until `sel_thr` existed.
#   sel_sym_a2=1
#     a symbolic shape with ALL2ALL FORCED is NAIVE. `sel_sym` uses RING=2 and
#     ALL2ALL=0, so it says nothing about `use_all2all`'s own `concrete and`.
#   sel_numel=1  `prod(shape)` over two dims.
#   f_100=1 f_128=1 f_96=1 f_odd=1
#     `factor`, the LARGEST of [32,16,8,4,2] dividing numel, else 1. 100 is the row
#     that matters: the five factors are NESTED, so a last-match fold answers 2.
#   ch_100=1 ch_100_l=1 ch_128_l=1 ch_96_l=1
#     `base, left = divmod(numel // factor, ndev)`. `ch_96_l` is the big remainder.
#   k_*_n and k_*_s/_e
#     the chunk BOUNDS, in order, for numel=100/ndev=4 (28 then three 24s), numel=96
#     (three 32s and a ZERO-LENGTH fourth -- the degenerate bound is a row) and
#     ndev=7 and ndev=8 and ndev=3, which are not powers of two.
#   hv_4=1 hv_3=1 hv_0=1
#     `hdev > 0 and ndev % hdev == 0`, with hdev=3 on ndev=8 as the divisor row.
#   hv_boxes4=1 hv_boxes2=1  `len(boxes) == ndev // hdev`.
#   hv_cs_* hv_cs2_n
#     `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`.
#
# MUTATIONS, all re-run against this file. Reproduce with
# `.agents/slop/tools/mutate-allreduce.py`. Not one row per bug: several rows are
# load-bearing TOGETHER, and three of these mutations moved NOTHING until a fixture
# was added for them, which is the point of running the table at all.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `red_worth`'s `and` -> `or` (either the device count or... | sel_small, sel_two_big, sel_thr | 3 |
# | `red_worth`'s `numel > thr` -> `numel >= thr` (the thre... | sel_thr | 1 |
# | `red_worth`'s `ndev > 2` -> `ndev >= 2` (the two-node e... | sel_two_big | 1 |
# | `red_ge2`/`red_ge1`'s `2` -> `1` (the force overrides b... | sel_two, sel_small, sel_two_big, sel_thr | 4 |
# | `red_ring3`'s `not a2` -> `a2` (ring and all2all can bo... | sel_big, sel_three, sel_r2_force, sel_thr1 | 4 |
# | `red_a2` drops the `concrete and` (a symbolic shape sti... | sel_sym_a2 | 1 |
# | `red_all_int`'s `and` -> `or` (one int dim is enough to... | sel_sym, sel_sym_c, sel_sym_a2 | 3 |
# | `red_mode`'s ALL2ALL arm 2 -> 1 (all2all and ring print... | sel_a2_1, sel_a2_force, sel_both | 3 |
# | `red_factor`'s keep-first `Bool.not(found)` -> `True{}`... | f_100, f_128, f_96, f_odd, ch_100, ch_100_l, ch_96_l, k_100_e0, k_100_s1, k_96_s3 | 10 |
# | `red_factor_factors`'s 32 -> 8 (the granularity ladder ... | f_128, f_96, ch_96_l, k_96_s3 | 4 |
# | `red_bump`'s `is_lt(k, left)` -> `is_lt(k, left+1)` (on... | k_100_e1, k_100_e3, k_96_e3, k_7_e6 | 4 |
# | `red_bounds`'s running start `add` -> `sub` (the bounds... | k_100_s0, k_100_e0, k_100_s1, k_100_e1, k_100_e3, k_7_e6 | 6 |
# | `red_bounds`'s start 0 -> `numel` (the accumulate start... | k_100_s0, k_100_e0, k_100_s1, k_100_e1, k_100_e3, k_96_s3, k_96_e3, k_7_e6 | 8 |
# | `red_hdev_fires` drops `hdev > 0` (a zero hdev divides ... | hv_3 | 1 |
# | `red_boxes`'s `div` -> `mod` (the box count is the rema... | hv_boxes4, hv_boxes2 | 2 |
# | `red_cs.k`'s `k+1` -> `k` (every cs bound pair collapse... | hv_cs_e0, hv_cs_e3 | 2 |
#
# the three that moved nothing, and what they cost. Each is now a row.
#   * `ndev > 2` -> `ndev >= 2`: `sel_two` alone cannot see it, because its size test
#     already fails. `sel_two_big` exists for this and only this.
#   * `numel > thr` -> `numel >= thr`: no fixture sat ON the threshold. `sel_thr` and
#     `sel_thr1` sit either side of it.
#   * `red_a2` dropping `concrete and`: every symbolic fixture had ALL2ALL off, so
#     the expression was unobservable. `sel_sym_a2` forces ALL2ALL on a symbolic
#     shape.
# An all-True gate says which cases you covered and nothing about the rest; three of
# the sixteen mutations here were invisible to the fixture set as first written, and
# none of them was a false alarm.
# NOT PORTED, one line each, and the WALL each one is behind.
#
# THE THREE REDUCTION GRAPHS -- every one of `allreduce.py:18-66`. `buf.pad_to`,
# `buf.contiguous`, `buf.reshape`, `.mselect`, `.copy_to_device`, `.shrink`, `.pad`,
# `UOp.mstack`, `UOp.usum`, `.alu`, `.allreduce` and `.reshape` are ops.py:614 through
# :853 and every one is a `TODO(p3)` in `ops.bend`. What IS here is the decision that
# picks between them (`red_sel`), the chunk boundaries each one is built from
# (`red_bounds_of`), the node-local branch's boxes and cut points (`red_boxes`,
# `red_cs_of`) and the two flags that change the shape rather than the choice. The
# WALL is not one thing but thirteen: graph construction is not ported at all, so
# this file can say WHICH reduction and HOW it is cut and not WHAT it is made of.
# `schedule/multi.py`'s `copy_multi` needs the same builders for the same reasons.
# `create_allreduce_function` -- allreduce.py:68-75. `UOp.unique_num`, `ParamArg`,
# `UOp.device_range_src`, `UOp.call`, `.param_like`, `.sink`, `.after` and
# `UOp.new_buffer` (ops.py:853, a P6 device). P3/P6.
# `ALLREDUCE_CAST` -- `multi.py:116`, and `Cfg.cast` carries the flag so the caller
#   can read it; the cast it guards is `local.cast(orig).allreduce(op, ...)` and
#   `allreduce` is the wall above.
# `DEBUG >= 2` print -- allreduce.py:16. WALL: `DEBUG` is a `ContextVar`, P6, and
#   `red_mode` already answers the question it would print.
# `assert isinstance(numel, int)` -- allreduce.py:35. Asserted by construction: the
#   chunking is only reached when `concrete` is True, which is `red_sel`'s first
#   term.
# `assert not remaining` in `multi.py:114` is `multi.py`'s, not this file's.
# what the other files need from here.
#   * `schedule/multi.py`'s `replace_allreduce` / `_early_allreduce` call
#     `handle_allreduce`, and `_early_allreduce` is exactly
#     `(UPat(Ops.ALLREDUCE, src=(UPat.var("buf"),), name="red"), handle_allreduce)`.
#     The BUFFER side is the thing multi.py cannot build, so that one rule's body is
#     the wall above. Its `red.arg` is the `AAllred{rop, dev}` arg.
#   * `schedule/__init__.py` owns the allocator-shaped side of nothing here -- all of
#     `schedule/memory.bend` -- but both files are read by the SAME planner pass, so
#     the caller must run `memory_plan_rewrite` and then `red_sel`: a planned buffer
#     is not yet a plannable one until it knows which reduction its buffer will take.
#   * NOTHING ELSE IS PUBLIC. `red_head` is duplicated in `schedule/memory.bend` as
#     `mem_head`; hoisting it into `helpers.bend` is the right home and is not this
#     unit's file.
# under the threshold with RING on: NAIVE. Together with `sel_big` this is the
# `numel > 256000` half of the empirical claim.
def sel_small() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(100), 4, P.red_c_on())), 0)
# RING off and ALL2ALL 1 with a big numel: ALL2ALL. `>= 1` is "on, subject to the
# empirical test", and this is the row that says ALL2ALL 1 is enough.
def k_96_e3() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_bounds_of(96, 4), 3)), 96)
# ndev=7, which does not divide numel evenly even after the factor: 4 chunks of 16
# and 3 of 12. The row for `ndev` not being a power of two.
def sel_three() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 3, P.red_c_on())), 1)
# under the threshold with RING on: NAIVE. Together with `sel_big` this is the
# `numel > 256000` half of the empirical claim.
# --- the chunking, allreduce.py:36-38 ---------------------------------------
# `factor` is the LARGEST of [32,16,8,4,2] dividing numel. 100 is divisible by 4 and
# not by 8, so 4 -- and the five factors are nested, so a last-match fold would say 2.
def f_100() -> U32: P.red_eq(P.red_factor_of(100), 4)
# THE BOUNDS. numel=100 ndev=4 factor=4 base=6 left=1 -> one 28-byte chunk and three
# 24s. `k_100_n` is the COUNT and `k_100_*` the four bounds in order; a chunking that
# lost the `left` remainder would still produce four chunks, so only the bounds say it.
def k_100_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_bounds_of(100, 4)))
def hv_cs_s0() -> U32: P.red_eq(P.Chk.s(P.red_at(P.red_cs_of(1000, 4), 0)), 0)
# ndev=4, 300k elements, RING on: RING. And `ndev=3` is also RING, so the test is
# `> 2` and not `>= 4`.
def sel_big() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 4, P.red_c_on())), 1)
def f_128() -> U32: P.red_eq(P.red_factor_of(128), 32)
def sel_both() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 4, P.red_c_both())), 2)
# a SYMBOLIC dim is not concrete, so even a forced RING falls back to NAIVE. The
# `concrete and` in both expressions, which is the row for it.
# `concrete and` IN `use_all2all`, not only in `use_ring`. `sel_sym` uses RING=2 and
# ALL2ALL=0, so it says nothing about the all2all expression -- measured: dropping
# `concrete` from `red_a2` moved nothing until this row existed. A symbolic shape
# with ALL2ALL FORCED is still NAIVE.
def sel_sym_a2() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_shsym(300000), 4, P.red_c_a2f())), 0)
# --- the chunking, allreduce.py:36-38 ---------------------------------------
# `factor` is the LARGEST of [32,16,8,4,2] dividing numel. 100 is divisible by 4 and
# not by 8, so 4 -- and the five factors are nested, so a last-match fold would say 2.
def k_100_e3() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_bounds_of(100, 4), 3)), 100)
# numel=96 ndev=4 factor=32 base=0 left=3 -> THREE 32s and a zero-length fourth.
# The degenerate bound is the row: a chunking that "fixed" it would change the ring.
# a symbolic dim also zeroes `numel`, because `dim_of` counts `SS{..}` as 0.
def sel_sym_n() -> U32:
  P.red_eq(P.red_numel(P.red_shsym(300000)), 0)
# THE `>` ROW. Exactly `RING_ALLREDUCE_THRESHOLD` is NOT greater than it, so a large
# linear right at 256000 is still NAIVE. Measured: mutating `numel > thr` to
# `numel >= thr` moved NOTHING until this row existed.
def sel_thr() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(256000), 4, P.red_c_on())), 0)
# THE SAME ROW, one element above the threshold, which IS ring. Together with
# `sel_thr` this pins the comparison and not just its result.
# --- the selection, allreduce.py:13-16 --------------------------------------
# ndev=2 is the empirical "only 2 nodes" arm and RING is ON: NAIVE. This is the row
# that says `ndev > 2` is really tested.
def sel_two() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(100), 2, P.red_c_on())), 0)
# ndev=4, 300k elements, RING on: RING. And `ndev=3` is also RING, so the test is
# `> 2` and not `>= 4`.
def hv_cs_e3() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_cs_of(1000, 4), 3)), 1000)
# numel=96 ndev=4 factor=32 base=0 left=3 -> THREE 32s and a zero-length fourth.
# The degenerate bound is the row: a chunking that "fixed" it would change the ring.
def k_96_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_bounds_of(96, 4)))
def f_odd() -> U32: P.red_eq(P.red_factor_of(101), 1)
# `base, left = divmod(numel // factor, ndev)`
# `boxes = [range(b, b+hdev) for b in range(0, ndev, hdev)]` -- the count only.
def hv_boxes4() -> U32: P.red_eq(P.red_boxes(8, 4), 2)
# RING off, ALL2ALL 0, big: NAIVE. With `sel_a2_1` this is the `>= 1` boundary.
def sel_a2_0() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 4, P.red_c_off())), 0)
# ALL2ALL 2 FORCES it, under the threshold and at ndev=2. The override ignores both
# empirical conditions, which is the whole point of `>= 2`.
# ndev=8 and ndev=3, for the same reason on the other side.
def k_8_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_bounds_of(320, 8)))
# RING off and ALL2ALL 1 with a big numel: ALL2ALL. `>= 1` is "on, subject to the
# empirical test", and this is the row that says ALL2ALL 1 is enough.
def sel_a2_1() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 4, P.red_c_a2())), 2)
# RING off, ALL2ALL 0, big: NAIVE. With `sel_a2_1` this is the `>= 1` boundary.
# THE `> 2` ROW. `sel_two` uses a SMALL numel, so it cannot tell `ndev > 2` from
# `ndev >= 2` -- both are NAIVE there because the size test fails anyway. This one
# is ndev=2 at a size where ring WOULD fire, and it is the row that says the "only
# 2 nodes" arm is a device-count test and not a side effect of the size test.
def sel_two_big() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(300000), 2, P.red_c_on())), 0)
# THE `>` ROW. Exactly `RING_ALLREDUCE_THRESHOLD` is NOT greater than it, so a large
# linear right at 256000 is still NAIVE. Measured: mutating `numel > thr` to
# `numel >= thr` moved NOTHING until this row existed.
def f_96() -> U32: P.red_eq(P.red_factor_of(96), 32)
def k_100_e0() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_bounds_of(100, 4), 0)), 28)
# ndev=7, which does not divide numel evenly even after the factor: 4 chunks of 16
# and 3 of 12. The row for `ndev` not being a power of two.
def k_7_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_bounds_of(100, 7)))
# ALL2ALL 2 FORCES it, under the threshold and at ndev=2. The override ignores both
# empirical conditions, which is the whole point of `>= 2`.
def sel_a2_force() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(100), 2, P.red_c_a2f())), 2)
# RING 2 FORCES ring. And RING 2 with ALL2ALL 2 is ALL2ALL, because `use_ring`'s own
# expression carries `and not use_all2all` -- the row for that `not`.
def ch_96_l() -> U32: P.red_eq(P.Ch.left(P.red_chunk(96, 4)), 3)
# THE BOUNDS. numel=100 ndev=4 factor=4 base=6 left=1 -> one 28-byte chunk and three
# 24s. `k_100_n` is the COUNT and `k_100_*` the four bounds in order; a chunking that
# lost the `left` remainder would still produce four chunks, so only the bounds say it.
def k_7_e6() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_bounds_of(100, 7), 6)), 100)
# ndev=8 and ndev=3, for the same reason on the other side.
def ch_128_l() -> U32: P.red_eq(P.Ch.left(P.red_chunk(128, 4)), 0)
def hv_0() -> U32: P.red_if(Bool.not(P.red_hdev_fires(8, 0)))
# `boxes = [range(b, b+hdev) for b in range(0, ndev, hdev)]` -- the count only.
# `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`
def hv_cs_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_cs_of(1000, 4)))
def k_100_s0() -> U32: P.red_eq(P.Chk.s(P.red_at(P.red_bounds_of(100, 4), 0)), 0)
# a SYMBOLIC dim is not concrete, so even a forced RING falls back to NAIVE. The
# `concrete and` in both expressions, which is the row for it.
def sel_sym() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_shsym(300000), 4, P.red_c_r2())), 0)
# and `concrete` itself, so the reason above is the test and not the threshold.
def k_100_e1() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_bounds_of(100, 4), 1)), 52)
def hv_cs_e0() -> U32: P.red_eq(P.Chk.e(P.red_at(P.red_cs_of(1000, 4), 0)), 250)
# `base, left = divmod(numel // factor, ndev)`
def ch_100() -> U32: P.red_eq(P.Ch.base(P.red_chunk(100, 4)), 6)
def hv_boxes2() -> U32: P.red_eq(P.red_boxes(8, 2), 4)
# `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`
def k_3_n() -> U32: U32.from_nat(List.length(&2, P.Chk, P.red_bounds_of(1000, 3)))
# --- the node-local branch, allreduce.py:22-28 ------------------------------
# `concrete and hdev > 0 and ndev % hdev == 0` -- and hdev=3 on ndev=8 is the row
# that says the modulus is tested.
def hv_3() -> U32: P.red_if(Bool.not(P.red_hdev_fires(8, 3)))
def sel_numel() -> U32:
  P.red_eq(P.red_numel(P.red_sh2(1000, 2)), 2000)
# THE `> 2` ROW. `sel_two` uses a SMALL numel, so it cannot tell `ndev > 2` from
# `ndev >= 2` -- both are NAIVE there because the size test fails anyway. This one
# is ndev=2 at a size where ring WOULD fire, and it is the row that says the "only
# 2 nodes" arm is a device-count test and not a side effect of the size test.
# RING 2 FORCES ring. And RING 2 with ALL2ALL 2 is ALL2ALL, because `use_ring`'s own
# expression carries `and not use_all2all` -- the row for that `not`.
def sel_r2_force() -> U32:
  P.red_eq(P.red_mode(P.red_sel(P.red_sh1(100), 2, P.red_c_r2())), 1)
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- red_row("sel_two", sel_two())
    _ : Unit <- red_row("sel_big", sel_big())
    _ : Unit <- red_row("sel_three", sel_three())
    _ : Unit <- red_row("sel_small", sel_small())
    _ : Unit <- red_row("sel_a2_1", sel_a2_1())
    _ : Unit <- red_row("sel_a2_0", sel_a2_0())
    _ : Unit <- red_row("sel_a2_force", sel_a2_force())
    _ : Unit <- red_row("sel_r2_force", sel_r2_force())
    _ : Unit <- red_row("sel_both", sel_both())
    _ : Unit <- red_row("sel_sym", sel_sym())
    _ : Unit <- red_row("sel_sym_c", sel_sym_c())
    _ : Unit <- red_row("sel_sym_n", sel_sym_n())
    _ : Unit <- red_row("sel_numel", sel_numel())
    _ : Unit <- red_row("sel_two_big", sel_two_big())
    _ : Unit <- red_row("sel_thr", sel_thr())
    _ : Unit <- red_row("sel_thr1", sel_thr1())
    _ : Unit <- red_row("sel_sym_a2", sel_sym_a2())
    _ : Unit <- red_row("f_100", f_100())
    _ : Unit <- red_row("f_128", f_128())
    _ : Unit <- red_row("f_96", f_96())
    _ : Unit <- red_row("f_odd", f_odd())
    _ : Unit <- red_row("ch_100", ch_100())
    _ : Unit <- red_row("ch_100_l", ch_100_l())
    _ : Unit <- red_row("ch_128_l", ch_128_l())
    _ : Unit <- red_row("ch_96_l", ch_96_l())
    _ : Unit <- red_row("k_100_n", k_100_n())
    _ : Unit <- red_row("k_100_s0", k_100_s0())
    _ : Unit <- red_row("k_100_e0", k_100_e0())
    _ : Unit <- red_row("k_100_s1", k_100_s1())
    _ : Unit <- red_row("k_100_e1", k_100_e1())
    _ : Unit <- red_row("k_100_e3", k_100_e3())
    _ : Unit <- red_row("k_96_n", k_96_n())
    _ : Unit <- red_row("k_96_s3", k_96_s3())
    _ : Unit <- red_row("k_96_e3", k_96_e3())
    _ : Unit <- red_row("k_7_n", k_7_n())
    _ : Unit <- red_row("k_7_e6", k_7_e6())
    _ : Unit <- red_row("k_8_n", k_8_n())
    _ : Unit <- red_row("k_3_n", k_3_n())
    _ : Unit <- red_row("hv_4", hv_4())
    _ : Unit <- red_row("hv_3", hv_3())
    _ : Unit <- red_row("hv_0", hv_0())
    _ : Unit <- red_row("hv_boxes4", hv_boxes4())
    _ : Unit <- red_row("hv_boxes2", hv_boxes2())
    _ : Unit <- red_row("hv_cs_n", hv_cs_n())
    _ : Unit <- red_row("hv_cs_s0", hv_cs_s0())
    _ : Unit <- red_row("hv_cs_e0", hv_cs_e0())
    _ : Unit <- red_row("hv_cs_e3", hv_cs_e3())
    _ : Unit <- red_row("hv_cs2_n", hv_cs2_n())
    IO.print("")
    IO.print("")
