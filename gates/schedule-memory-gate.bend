# gates/schedule-memory-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/memory.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/memory.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def p_count() -> String:
  +r = P.mem_plan(P.proj_of())
  String.concat(["COUNT bufs=", U32.show(P.mem_len(P.Planned.bs(r))),
                 " arenas=", U32.show(P.mem_len2(P.Planned.azs(r)))])
# --- the collect walk, memory.py:7-10 ---------------------------------------
# A BUFFER collects itself: CPython `_collect_bufs(A)` == [A].
# the DISK/CL/WEBGPU prefix test, as a tag set. CPython: DISK False.
def w_cp_disk() -> U32:
  P.mem_if(Bool.not(P.mem_can_plan(P.Walk.fx(P.walk_of()), P.Proj.at(P.proj_of(), 6), Nil{}, P.unpl())))
# a TUPLE device whose members are both fine: ("CPU","METAL") was True.
# --- `nbytes` and `buf_hold`, memory.py:38 and :42 --------------------------
# `round_up(max_numel() * itemsize, 256)`, and int32 is 4 bytes. These four are
# the sizes; they differ from each other so a shared constant cannot pass them.
def p_nb_b2() -> U32: P.mem_eq(P.mem_nbytes(P.Proj.fx(P.proj_of()), P.Proj.at(P.proj_of(), 1)), 8192)
def p_e2_f() -> U32: P.mem_eq(P.mem_nb_f(P.Proj.at(P.proj_of(), 4), P.mem_scan_tc(P.proj_of())), 2)
# `last_appearance[b] = i` is unconditional, so D2 -- read by BOTH k2 and k3 --
# ends at 3 while E2, read only by k2, ends at 2. This pair is the whole reason
# `last_appearance` is not just the last `first`.
def p_d2_l() -> U32: P.mem_eq(P.mem_nb_l(P.Proj.at(P.proj_of(), 3), P.mem_scan_tc(P.proj_of())), 3)
def p_ev3_o0() -> U32: P.mem_eq(P.Ev.o(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 5)), 0)
# held: `if b in held_bufs: return False`
def w_cp_held() -> U32:
  P.mem_if(Bool.not(P.mem_can_plan(P.Walk.fx(P.walk_of()), P.Walk.a(P.walk_of()), [P.Walk.a(P.walk_of())], P.unpl())))
# the DISK/CL/WEBGPU prefix test, as a tag set. CPython: DISK False.
# a BUFFER on the tuple device ("CPU","METAL") = tags 2 and 3, which is the
# fixture CPython's `cp_mdev` (True) and `cp_mdev_cl` (False) were run against.
# --- `_can_plan`, memory.py:12-16 -------------------------------------------
def w_cp_plain() -> U32:
  P.mem_if(P.mem_can_plan(P.Walk.fx(P.walk_of()), P.Walk.a(P.walk_of()), Nil{}, P.unpl()))
# held: `if b in held_bufs: return False`
# the lane keys themselves: (CPU,1) then (CPU,0). Without `cp` both lanes would
# collide and `mem_lanes` would answer ONE lane with the sum of both -- so these
# two rows and `p_nlanes` are the whole `_key` contract.
def p_lane0cp() -> U32: P.mem_eq(P.Lane.cp(P.Peak.ln(P.mem_pk_at(P.mem_peaks(P.plan_plan(P.Proj.fx(P.proj_of())), P.Scan.cp(P.mem_scan_of(P.proj_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.proj_of()))), 0))), 1)
def p_c2_f() -> U32: P.mem_eq(P.mem_nb_f(P.Proj.at(P.proj_of(), 2), P.mem_scan_tc(P.proj_of())), 1)
def p_ev3_b2() -> U32: P.mem_eq(P.Ev.b(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 7)), 7)
# THE SAME AT INDEX 2, where a copy buffer's close (B2, whose hold pushed it to
# `last + 1 + 1 = 2`) meets two compute opens. `ev2` is the row that pins
# `buf_hold`: without the hold B2's close would land at index 1 and move.
# --- the collect walk, memory.py:7-10 ---------------------------------------
# A BUFFER collects itself: CPython `_collect_bufs(A)` == [A].
def w_buf() -> U32:
  P.mem_eq(P.mem_col(P.walk_of(), P.Walk.a(P.walk_of())), 1)
# ...and it is the BUFFER, not the MSELECT it is wrapped in.
# `arena_sizes = {key: round_up(peak, block_size)}` -- 10240 and 1536 are already
# multiples of 256 here, so this pair pins the LANE COUNT and the ordering, and
# `p_peak*` pins the arithmetic underneath.
def p_azs_n() -> U32: P.mem_naz(P.Planned.azs(P.mem_plan(P.proj_of())))
def p_nb_c2() -> U32: P.mem_eq(P.mem_nbytes(P.Proj.fx(P.proj_of()), P.Proj.at(P.proj_of(), 2)), 2048)
# --- the lifetime scan, memory.py:28-33 -------------------------------------
# the COUNT: five buffers are plannable. Seven exist; A2 is a STORE dest and DK is
# on DISK, so both are out. A count is the row that catches a MISSING filter.
def p_nbufs() -> U32:
  P.mem_len(P.mem_scan_bs(P.proj_of()))
# THE TOUCH COUNT, and this row exists because `Scan.tc` IS NOT
# `first_appearance`. `mem_tc_add` appends on EVERY touch, so `Scan.tc` has one
# `Bf` per (buffer, kernel) pair while CPython's `first_appearance` is a dict with
# one entry per DISTINCT buffer -- and the fixture's buffer B is touched by two
# kernels, so the two counts differ by exactly one.
#
# THIS IS NOT A PORT BUG, and the row is what says so. memory.py:60 prints
# `len(first_appearance)`, and this file's counterpart for that number is
# `p_nbufs` -- `Scan.bs`, THE DISTINCT LIST, built by `mem_bs_add` which is
# append-IF-ABSENT -- not `Planned.tc`. Measured: `p_nbufs=5` and `p_tcn=6`.
# Everything that reads a lifetime (`mem_first_i`, `mem_last_i`, `mem_hold2`,
# `mem_events`) folds over `Scan.bs` and looks the buffer up in `Scan.tc`, so the
# touch list is a strict SUPERSET that answers the same questions: it is CPython's
# `first_appearance` and `last_appearance` FUSED, which is why `Bf` is one record
# and not two. Renaming `tc` to `fa` would make the row look closed and change no
# answer, so the pair is printed instead.
# ...and it is the BUFFER, not the MSELECT it is wrapped in.
def w_buf_is() -> U32:
  P.mem_all(P.mem_col_of(P.walk_of(), P.Walk.a(P.walk_of())), P.Walk.a(P.walk_of()))
# MSELECT recurses: `_collect_bufs(A.mselect(0))` == [A], still the buffer.
def p_ev3_o1() -> U32: P.mem_eq(P.Ev.o(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 6)), 0)
# ONE ARENA PER LANE, and the lane COUNT is 2 here: ("CPU", 0) for the compute
# buffers and ("CPU", 1) for the copy buffers. The split is the whole point of
# the `_key` comment on avoiding copy->compute->copy, so the count is the row.
def p_nlanes() -> U32: P.mem_npk(P.mem_peaks(P.plan_plan(P.Proj.fx(P.proj_of())), P.Scan.cp(P.mem_scan_of(P.proj_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.proj_of()))))
# the lane order is the event order, and the first event belongs to a COPY
# buffer (B2), so lane 0 is ("CPU", 1) and lane 1 is ("CPU", 0). Python's
# `defaultdict` creates `peaks[_key(buf)]` on the first event and `dict` keeps that
# insertion order, and `arena_sizes` iterates it -- so this file's lane 0 is the
# copy lane. Getting the two the other way round is the mistake a reader makes and
# `p_lane*cp` is the row that says so.
#
# lane 0, the COPY lane: B2 at offset 0 (8192 raw) and C2 at 8192 (2048 raw), and
# `buf_hold` keeps them apart, so the peak is their SUM: 10240.
def p_a2_absent() -> U32:
  P.mem_absent(P.mem_scan_bs(P.proj_of()), P.Proj.at(P.proj_of(), 0))
# --- `nbytes` and `buf_hold`, memory.py:38 and :42 --------------------------
# `round_up(max_numel() * itemsize, 256)`, and int32 is 4 bytes. These four are
# the sizes; they differ from each other so a shared constant cannot pass them.
# and the planner agrees: this linear's whole budget is 512 and it is one arena.
def u_tot() -> U32: P.mem_eq(P.Planned.tot(P.mem_plan(P.unaligned_of())), 1024)
def p_ev2_o1() -> U32: P.mem_eq(P.Ev.o(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 3)), 1)
def p_azs1() -> U32: P.mem_eq(P.Asz.sz(P.mem_asz_at(P.Planned.azs(P.mem_plan(P.proj_of())), 1)), 1536)
# CPython's rewrite of this same graph produced 5 BITCASTs (one per plannable
# buffer) and 2 arenas. The Bend port cannot build the BITCASTs -- `new_buffer`
# and `substitute` are the wall -- so this row pins the plan's OWN count, which is
# the number the caller needs in order to build them.
# THE SAME AT INDEX 2, where a copy buffer's close (B2, whose hold pushed it to
# `last + 1 + 1 = 2`) meets two compute opens. `ev2` is the row that pins
# `buf_hold`: without the hold B2's close would land at index 1 and move.
def p_ev2_o0() -> U32: P.mem_eq(P.Ev.o(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 2)), 0)
# THE TOUCH COUNT, and this row exists because `Scan.tc` IS NOT
# `first_appearance`. `mem_tc_add` appends on EVERY touch, so `Scan.tc` has one
# `Bf` per (buffer, kernel) pair while CPython's `first_appearance` is a dict with
# one entry per DISTINCT buffer -- and the fixture's buffer B is touched by two
# kernels, so the two counts differ by exactly one.
#
# THIS IS NOT A PORT BUG, and the row is what says so. memory.py:60 prints
# `len(first_appearance)`, and this file's counterpart for that number is
# `p_nbufs` -- `Scan.bs`, THE DISTINCT LIST, built by `mem_bs_add` which is
# append-IF-ABSENT -- not `Planned.tc`. Measured: `p_nbufs=5` and `p_tcn=6`.
# Everything that reads a lifetime (`mem_first_i`, `mem_last_i`, `mem_hold2`,
# `mem_events`) folds over `Scan.bs` and looks the buffer up in `Scan.tc`, so the
# touch list is a strict SUPERSET that answers the same questions: it is CPython's
# `first_appearance` and `last_appearance` FUSED, which is why `Bf` is one record
# and not two. Renaming `tc` to `fa` would make the row look closed and change no
# answer, so the pair is printed instead.
def p_tcn() -> U32:
  P.mem_len3(P.mem_scan_tc(P.proj_of()))
# the copy-buffer COUNT is 2 (B2, C2): only kernels whose BODY is a STORE.
# `for i, si in enumerate(linear.src)` -- first appearance index per buffer
def p_b2_f() -> U32: P.mem_eq(P.mem_nb_f(P.Proj.at(P.proj_of(), 1), P.mem_scan_tc(P.proj_of())), 0)
def p_ev2_b1() -> U32: P.mem_eq(P.Ev.b(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 3)), 5)
# the first and last events overall: an open at 0 and a close at 4.
# the copy-buffer COUNT is 2 (B2, C2): only kernels whose BODY is a STORE.
def p_ncopy() -> U32:
  P.mem_len(P.Scan.cp(P.mem_scan_of(P.proj_of())))
# `for i, si in enumerate(linear.src)` -- first appearance index per buffer
# CPython's rewrite of this same graph produced 5 BITCASTs (one per plannable
# buffer) and 2 arenas. The Bend port cannot build the BITCASTs -- `new_buffer`
# and `substitute` are the wall -- so this row pins the plan's OWN count, which is
# the number the caller needs in order to build them.
def p_nplan() -> U32: P.mem_len(P.Planned.bs(P.mem_plan(P.proj_of())))
def p_ev3_b1() -> U32: P.mem_eq(P.Ev.b(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 6)), 6)
# a tuple device whose SECOND member is CL: ("CPU","CL:1") was False, so `all`
# is over every member and not just the first. Tags 2 and 3, tag 3 is in `unpl`.
def w_cp_mdev_cl() -> U32:
  P.mem_if(Bool.not(P.mem_can_plan(P.Walk.fx(P.walk_of()), P.Walk.mc(P.walk_of()), Nil{}, P.unpl())))
# --- the lifetime scan, memory.py:28-33 -------------------------------------
# the COUNT: five buffers are plannable. Seven exist; A2 is a STORE dest and DK is
# on DISK, so both are out. A count is the row that catches a MISSING filter.
def p_nb_d2() -> U32: P.mem_eq(P.mem_nbytes(P.Proj.fx(P.proj_of()), P.Proj.at(P.proj_of(), 3)), 1024)
def p_azs0() -> U32: P.mem_eq(P.Asz.sz(P.mem_asz_at(P.Planned.azs(P.mem_plan(P.proj_of())), 0)), 10240)
def p_ev3_b0() -> U32: P.mem_eq(P.Ev.b(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 5)), 4)
# the first and last events overall: an open at 0 and a close at 4.
def p_ev_first() -> U32: P.mem_eq(P.Ev.i(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 0)), 0)
def p_nb_e2() -> U32: P.mem_eq(P.mem_nbytes(P.Proj.fx(P.proj_of()), P.Proj.at(P.proj_of(), 4)), 512)
# `buf_hold = last - first + 1` for a COPY buffer only. B2 is 0..0 so it is 1, and
# D2 is not a copy buffer so it is 0 -- two rows for the same conditional.
# --- the EMPTY plan, memory.py:34 ------------------------------------------
# `if not first_appearance: return linear`. A LINEAR whose one kernel has no
# plannable args leaves the table empty, and that empty table IS the early
# return. Without this row every fixture above is all-True and says nothing about
# the branch.
def e_nbufs() -> U32: P.mem_len(P.mem_scan_bs(P.empty_of()))
# THE GATE DOCUMENT. `1` is True, `0` is False, and a COUNT row prints the count.
# Every value is CPython's: `.agents/slop/notes/sched-mem-truth.py` printed them
# for the SAME two graphs and this file's fixtures are rebuilt from that output.
#
#   w_buf=1 w_buf_is=1 w_msel=1 w_mstack=1 w_store=1 w_const=1
#     `_collect_bufs`: a BUFFER collects ITSELF and nothing else does; an MSTACK
#     of two MSELECTs of ONE buffer collects it TWICE, which is the row a dedupe
#     would fail and CPython's `['A','A']` is the oracle for.
#   w_cp_plain=1 w_cp_held=1 w_cp_disk=1 w_cp_mdev=1 w_cp_mdev_cl=1
#     `_can_plan`: not held, and no device in the unplannable tag set. `w_cp_mdev_cl`
#     is the row that `all` runs over EVERY member of a tuple device and not just
#     the first -- Python's `("CPU","CL:1")` was False.
#   p_nbufs=5 p_ncopy=2
#     the two COUNTS. Five plannable buffers out of seven (A2 is a STORE dest,
#     DK is on DISK), two of them copy buffers.
#   p_b2_f=1 p_c2_f=1 p_d2_f=1 p_e2_f=1 p_f2_f=1
#     `first_appearance` = 0,1,2,2,3.
#   p_d2_l=1 p_e2_l=1
#     `last_appearance` = 3 for D2 and 2 for E2. THE PAIR: D2 is read by both k2
#     and k3 and E2 by k2 only, so `last` is not a copy of `first` and the two
#     rows are what say the scan visits a buffer more than once.
#   p_a2_absent=1
#     the STORE dest never reaches `first_appearance`.
#   p_nb_b2=1 p_nb_c2=1 p_nb_d2=1 p_nb_e2=1
#     `round_up(max_numel * itemsize, 256)` = 8192, 2048, 1024, 512.
#   p_hold_b2=1 p_hold_d2=1
#     `buf_hold` = 1 for a COPY buffer and 0 for a compute buffer.
#   p_nev=10
#     the event COUNT: two per buffer. A buffer read by four kernels contributes
#     TWO events, not eight -- that is the opens-over-the-distinct-list row.
#   p_ev3_i=1 p_ev3_o0=1 p_ev3_b0=1 p_ev3_o1=1 p_ev3_b1=1 p_ev3_o2=1 p_ev3_b2=1
#   p_ev2_o0=1 p_ev2_b0=1 p_ev2_o1=1 p_ev2_b1=1
#   p_ev_first=1 p_ev_last=1
#     THE ORDER, which is the part a count cannot see. Index 3 holds three events
#     -- two closes and one open -- so it is BOTH the close-before-open row AND a
#     three-way tie, and it is where a broken comparator and an unstable sort
#     would both show. Index 2 is the `buf_hold` row: B2's close is pushed to
#     index 2 by its hold of 1, where it meets two compute opens.
#   p_tot=1
#     `total_memory = sum(nbytes) * 2` = 24064.
#   p_nlanes=2 p_lane0cp=1 p_lane1cp=1
#     ONE ARENA PER LANE, and the lane ORDER is the event order -- the first event
#     belongs to a copy buffer, so lane 0 is ("CPU",1) and lane 1 is ("CPU",0).
#   p_peak0=1 p_peak1=1
#     10240 for the copy lane (two buffers that do not overlap: their SUM) and
#     1536 for the compute lane (F2 reuses E2's freed block, so it is NOT the
#     sum). `p_peak1` is the only row that says the ALLOCATOR's answer was used
#     rather than re-derived.
#   p_azs_n=2 p_azs0=1 p_azs1=1
#     `arena_sizes`, same order.
#   p_nplan=5
#     the plan's own buffer count -- what CPython's rewrite turned into 5 BITCASTs.
#   u_raw=1 u_nb=1 u_tot=1 u_nlanes=1
#     the UNALIGNED fixture: 100 int32 = 400 bytes raw, 512 after `round_up`.
#   e_nbufs=0
#     `if not first_appearance: return linear` (memory.py:34). Every other fixture
#     is all-True and says nothing about this branch.
#
# MUTATIONS, all re-run against this file. This is not one row per bug: several
# rows are load-bearing TOGETHER, and one row is LOCALISED.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `mem_ev_cmp`'s differing-index arm `is_le(ai,bi)` -> `F... | p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs0, p_azs1 | 16 |
# | `mem_bs_add` appends UNCONDITIONALLY -- the distinct list stops deduping, so `Scan.bs` becomes a touch list too | p_nbufs, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_tot, p_nplan, COUNT bufs | 11 |
# |   ...and `p_tcn` did NOT move, which is the whole point of the pair. It read 6 before the mutation and 6 after, while `p_nbufs` went 5 -> 6 and collided with it. So `p_nbufs` is `len(first_appearance)` and is load-bearing across eleven rows; `p_tcn` is a DIFFERENT quantity that merely happens to be one larger. `Scan.tc` is not `first_appearance` and the gate now says so in two numbers instead of a comment. | | |
# | the open's `o` 1 -> 0, i.e. OPEN and CLOSE share a key ... | p_ev3_b0, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1 | 7 |
# | `mem_hold.of`'s copy arm `add(d,1)` -> `d` (buf_hold of... | p_hold_b2, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1 | 8 |
# | `mem_hold.of`'s non-copy arm 0 -> `d` (every buffer get... | p_hold_d2, p_ev_last | 2 |
# | `mem_key.cp.of`'s copy arm 1 -> 0 (the two lanes collid... | p_nlanes, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs1, COUNT bufs | 7 |
# | `mem_collect.is_multi`'s MSTACK arm -> False{} (MSTACK ... | w_mstack | 1 |
# | `mem_collect.is_buf`'s True -> False{} (a BUFFER no lon... | w_buf, w_buf_is, w_msel, w_mstack, p_nbufs, p_ncopy, p_c2_f, p_d2_f, p_e2_f, p_f2_f, p_d2_l, p_e2_l, p_hold_b2, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_tot, p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, p_nplan, u_tot, u_nlanes, COUNT bufs | 40 |
# | `mem_kern_cp3`'s STORE arm `mem_cp_add` -> `cp` (no buf... | p_ncopy, p_hold_b2, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_nlanes, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs1, COUNT bufs | 16 |
# | `mem_kept.one`'s keep arm -> acc (the `_can_plan` filte... | p_nbufs, p_ncopy, p_c2_f, p_d2_f, p_e2_f, p_f2_f, p_d2_l, p_e2_l, p_hold_b2, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_tot, p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, p_nplan, u_tot, u_nlanes, COUNT bufs | 36 |
# | `mem_args.of`'s `src_from(.., si, 1)` -> `.., si, 0` (t... | NONE | 0 |
# | `mem_off.go`'s hit arm -> acc (every offset reads 0, so... | p_peak0, p_peak1, p_azs0, p_azs1 | 4 |
# | `mem_nbytes`'s `round_up(..)` -> the raw size (block ro... | u_nb, u_tot | 2 |
# | `mem_nbytes`'s block_size 256 -> 512 (the round is stil... | p_tot | 1 |
# | `mem_raw`'s `U32.mul` -> `U32.add` (itemsize applied as... | p_nb_b2, p_nb_c2, p_nb_d2, p_nb_e2, p_tot, p_peak0, p_peak1, p_azs0, p_azs1, u_raw, u_nb, u_tot | 12 |
# | `mem_peak_one`'s hit arm `max(acc,v)` -> `v` (the peak ... | p_peak1, p_azs1 | 2 |
# | `mem_lane_in.of`'s seed `False{}` -> `True{}` (every la... | p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, u_nlanes, COUNT bufs | 10 |
# | `mem_last_one`'s hit arm `v` -> `acc` (last_appearance ... | p_d2_l, p_e2_l, p_ev3_i, p_ev3_o0, p_ev3_b1, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_last | 10 |
# | `mem_first_i.seen`'s keep-first arm `acc` -> `v` (first... | p_d2_f, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev2_b1 | 5 |
# | `mem_touch.one`'s `mem_bs_add` -> append unconditionall... | p_nbufs, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_tot, p_nplan, COUNT bufs | 11 |
# | `mem_scan`'s kernel fuel -> `+ 1n` (one step past the e... | NONE | 0 |
#
# the two that MOVE nothing are both worth reading.
#
# `mem_args.one`'s `src_from(ar, si, 1)` -> `src_from(ar, si, 0)` moves NOTHING, and
# that is an EQUIVALENCE rather than a gap: `si.src[0]` is a kernel SINK's BODY and
# a body is never a BUFFER, so `_collect_bufs` answers `[]` for it either way and
# the two slices collect the same buffers. Python's `si.src[1:]` is therefore not
# observable in this file, and the port keeps it because it is the line.
#
# `mem_scan`'s fuel `len` -> `len + 1` moves NOTHING, and that is a SAFETY PROPERTY
# rather than a gap: one step past the end pops the arena's BOTTOM node, a NOOP with
# no srcs, so `mem_args.of` collects nothing and the step is a no-op. `fuel = len` is
# therefore the correct choice AND the forgiving one.
#
# `mem_collect.is_multi`'s MSTACK arm is the one LOCALISED row in the table:
# `w_mstack` and nothing else moves, because `w_mstack` is the only fixture with
# an MSTACK. That is the honest cost of one fixture per shape, and it is why the
# collect rows are a family and not a single row.
# NOT PORTED, one line each, and the WALL each one is behind.
#
# `TLSFAllocator` -- `tinygrad/runtime/support/memory.py:23`, imported at
#   memory.py:5. A mutable Python object: `self.blocks` is a dict of linked-list
#   tuples whose `alloc` splits and `free` coalesces IN PLACE, with two levels of
#   buckets keyed by `size.bit_length()`. Bend has no mutable state and no
#   first-class functions, so it could only be a fold threading a `Data` state
#   through every event -- roughly 300 lines, of a file that is not this unit's,
#   whose output is an INPUT here. The seam is drawn where the wall is: `mem_offs`
#   carries the allocator's ANSWERS (and `mem_total_memory` is the budget this
#   file asks it for), and the gate feeds it CPython's own `TLSFAllocator`. So the
#   lane of every event, the high-water marks, the block rounding, the lane count
#   and the arena sizes are all here and gated; the OFFSETS are not computed here.
#   P6/runtime owns the allocator.
# `linear.substitute(replace_map, name="memory plan", walk=True)` -- memory.py:62.
#   Needs `UOp.substitute` (ops.py:532) and `UOp.new_buffer` (ops.py:853, a P6
#   device call). `mem_offs` plus `Planned.azs` is everything the caller needs to
#   build the map: one arena per lane and one offset per buffer. P3.
# `NO_MEMORY_PLANNER` -- memory.py:21, a `ContextVar`. WALL: no `Config` in Bend;
#   it is a `helpers.bend` P6 flag. The caller returns its input unchanged when it
#   is set, which is what the early return on an empty plan already does.
# `DEBUG >= 1` print -- memory.py:59-60. WALL: `DEBUG` is a `ContextVar`, P6, and
#   Bend has no `Config`; the two numbers it would print (`sum(nbytes.values())`
#   and `Planned.tot`'s halves) are `p_nb_*` and `p_tot` in this gate already.
# `held_bufs: set[UOp] | None` -- memory.py:20. PORTED, as a `List<&2, U32>` and a
#   `List.contains`, because Bend's `Map` is string-keyed. The `None` default is
#   the `Nil{}` the caller passes.
# `LaneKey = tuple[str, int]` -- memory.py:18. PORTED as `Lane{dev: S.Dev, cp:
#   U32}`, which is the same pair with the device as the `U32` tag the runtime
#   interns; `mem_eq_ln` is the `==` and `mem_lanes` is the `set`.
# WHAT `schedule/__init__.py` NEEDS FROM THIS FILE. It is the only caller, and
# nothing here imports it -- the two files meet at the CALL SITE and nowhere else.
#
#   Plan{fx, held, unpl}
#     `fx` is `F.folded(ar)`; `held` and `unpl` are the two lists of device-tag
#     indices. `unpl` IS the P6 device table's answer to "which device names start
#     with DISK / CL / WEBGPU" -- that test cannot be done here because a device is
#     a tag, not a name.
#   memory_plan_rewrite(pl, linear, offs) -> Planned{tc, bs, evs, tot, azs}
#     `tc` the flat touch list `{b, i}` newest-first, `bs` the distinct buffers in
#     first-insertion order (= Python's `first_appearance` key order), `evs` the
#     SORTED event stream (two per buffer, closes before opens at one index), `tot`
#     the allocator budget, `azs` one arena size per lane in lane order.
#   THE CALLER OWNS THE ALLOCATOR. It runs the events, calls its allocator's
#   `alloc`/`free` per event, and hands the offsets back. `offs` is
#   `List<&2, Off>{b, offset}`.
#   THE CALLER OWNS THE SUBSTITUTE. With `offs` and `azs` it can build
#   `arenas = {lane: new_buffer(lane.dev, lane.size, int8)}` and
#   `replace_map = {b: arenas[bs[lane(b)]][off:off+b.nbytes()].bitcast(b.dtype)}`
#   and call `linear.substitute(replace_map, name="memory plan", walk=True)`.
#   `bs` EMPTY is `if not first_appearance: return linear` -- return the linear
#   unchanged and do not allocate.
#   NOTHING ELSE IS PUBLIC. `mem_ok_dev` (the DISK/CL/WEBGPU test) is useful to the
#   other two files in this directory and is worth calling directly.
# 512 = round_up(400, 256). THE row for `block_size`.
def u_nb() -> U32: P.mem_eq(P.mem_nbytes(P.Proj.fx(P.unaligned_of()), P.Proj.at(P.unaligned_of(), 0)), 512)
# and the planner agrees: this linear's whole budget is 512 and it is one arena.
# --- the events, memory.py:43-44 --------------------------------------------
# the COUNT: two per buffer, no more and no fewer.
def p_nev() -> U32: P.mem_nev(P.Planned.evs(P.mem_plan(P.proj_of())))
# THE ORDER AT ONE INDEX. CPython: (3,F,C2) (3,F,E2) (3,T,F2). Two closes and one
# open all at index 3, and the CLOSES COME FIRST because the key is (i, is_open)
# with False < True. A port that sorted opens first would free after the next
# alloc and change every arena size. The two closes then keep C2 before E2, which
# is the sort's STABILITY and not the key -- and `ev3` is a THREE-WAY tie, so a
# first-wins-vs-conjunction bug in the comparator moves all three of these rows.
# a TUPLE device whose members are both fine: ("CPU","METAL") was True.
def w_cp_mdev() -> U32:
  P.mem_if(P.mem_can_plan(P.Walk.fx(P.walk_of()), P.Walk.md(P.walk_of()), Nil{}, P.unpl()))
# a tuple device whose SECOND member is CL: ("CPU","CL:1") was False, so `all`
# is over every member and not just the first. Tags 2 and 3, tag 3 is in `unpl`.
# a STORE is not a buffer and does not recurse: [] in CPython.
def w_store() -> U32:
  P.mem_eq(P.mem_col(P.walk_of(), P.Walk.st(P.walk_of())), 0)
# a CONST is not a buffer either: [] in CPython.
def u_nlanes() -> U32: P.mem_npk(P.mem_peaks(P.plan_plan(P.Proj.fx(P.unaligned_of())), P.Scan.cp(P.mem_scan_of(P.unaligned_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.unaligned_of()))))
# --- the EMPTY plan, memory.py:34 ------------------------------------------
# `if not first_appearance: return linear`. A LINEAR whose one kernel has no
# plannable args leaves the table empty, and that empty table IS the early
# return. Without this row every fixture above is all-True and says nothing about
# the branch.
# the lane order is the event order, and the first event belongs to a COPY
# buffer (B2), so lane 0 is ("CPU", 1) and lane 1 is ("CPU", 0). Python's
# `defaultdict` creates `peaks[_key(buf)]` on the first event and `dict` keeps that
# insertion order, and `arena_sizes` iterates it -- so this file's lane 0 is the
# copy lane. Getting the two the other way round is the mistake a reader makes and
# `p_lane*cp` is the row that says so.
#
# lane 0, the COPY lane: B2 at offset 0 (8192 raw) and C2 at 8192 (2048 raw), and
# `buf_hold` keeps them apart, so the peak is their SUM: 10240.
def p_peak0() -> U32: P.mem_eq(P.Peak.p(P.mem_pk_at(P.mem_peaks(P.plan_plan(P.Proj.fx(P.proj_of())), P.Scan.cp(P.mem_scan_of(P.proj_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.proj_of()))), 0)), 10240)
# lane 1, the COMPUTE lane: 1536, and NOT the sum of 1024 + 512 + 256. F2 reuses
# E2's freed block at 1024, so the high-water mark is the larger of the two
# overlapping pairs and this row is the only thing in the gate that says the
# allocator's answer was used rather than re-derived.
def p_ev_last() -> U32: P.mem_eq(P.Ev.i(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 9)), 4)
# --- the allocator seam, memory.py:45 and :48-53 ----------------------------
# `total_memory = sum(nbytes.values()) * 2` -- 12032 doubled.
def p_f2_f() -> U32: P.mem_eq(P.mem_nb_f(P.Proj.at(P.proj_of(), 5), P.mem_scan_tc(P.proj_of())), 3)
# `last_appearance[b] = i` is unconditional, so D2 -- read by BOTH k2 and k3 --
# ends at 3 while E2, read only by k2, ends at 2. This pair is the whole reason
# `last_appearance` is not just the last `first`.
# THE ORDER AT ONE INDEX. CPython: (3,F,C2) (3,F,E2) (3,T,F2). Two closes and one
# open all at index 3, and the CLOSES COME FIRST because the key is (i, is_open)
# with False < True. A port that sorted opens first would free after the next
# alloc and change every arena size. The two closes then keep C2 before E2, which
# is the sort's STABILITY and not the key -- and `ev3` is a THREE-WAY tie, so a
# first-wins-vs-conjunction bug in the comparator moves all three of these rows.
def p_ev3_i() -> U32: P.mem_eq(P.Ev.i(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 5)), 3)
# --- the allocator seam, memory.py:45 and :48-53 ----------------------------
# `total_memory = sum(nbytes.values()) * 2` -- 12032 doubled.
def p_tot() -> U32: P.mem_eq(P.Planned.tot(P.mem_plan(P.proj_of())), 24064)
# ONE ARENA PER LANE, and the lane COUNT is 2 here: ("CPU", 0) for the compute
# buffers and ("CPU", 1) for the copy buffers. The split is the whole point of
# the `_key` comment on avoiding copy->compute->copy, so the count is the row.
def p_ev2_b0() -> U32: P.mem_eq(P.Ev.b(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 2)), 3)
# MSELECT recurses: `_collect_bufs(A.mselect(0))` == [A], still the buffer.
def w_msel() -> U32:
  P.mem_eq(P.mem_col(P.walk_of(), P.Walk.msel(P.walk_of())), 1)
# MSTACK recurses over EVERY src and does NOT dedupe: CPython printed [A, A]
# for MSTACK(MSEL, MSEL) of one buffer. A dedupe here would be a real difference,
# because `si_bufs` flows into `copy_bufs.update` and into the lifetime upsert.
def mem_row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
# memory.py:59-60, the row `DEBUG >= 1` prints, as ONE row: the naive plan is one
# arena per buffer and the planned one is one arena per LANE. CPython on this
# fixture: `{len(first_appearance)} -> {len(arenas)} bufs` = 5 -> 2, and
# `omem`/`nmem` = 12032/11776 bytes, so the DEBUG line fires. The byte pair is
# `p_nb_*` (12032 summed) and `p_azs0`/`p_azs1` (10240 + 1536 = 11776) above.
def p_ev3_o2() -> U32: P.mem_eq(P.Ev.o(P.mem_ev_at(P.Planned.evs(P.mem_plan(P.proj_of())), 7)), 1)
# `buf_hold = last - first + 1` for a COPY buffer only. B2 is 0..0 so it is 1, and
# D2 is not a copy buffer so it is 0 -- two rows for the same conditional.
def p_hold_b2() -> U32:
  P.mem_eq(P.mem_hold2(P.Proj.at(P.proj_of(), 1), P.mem_scan_tc(P.proj_of()), P.Scan.cp(P.mem_scan_of(P.proj_of()))), 1)
def p_e2_l() -> U32: P.mem_eq(P.mem_nb_l(P.Proj.at(P.proj_of(), 4), P.mem_scan_tc(P.proj_of())), 2)
# A2 is never collected: it is a kernel SINK's src[0], and only src[1:] is walked.
# 400 = 100 int32 elements. The control row: it says what is being rounded, so a
# mutation of `mem_raw` cannot hide behind a coincidence.
def u_raw() -> U32: P.mem_eq(P.mem_raw(P.Proj.fx(P.unaligned_of()), P.Proj.at(P.unaligned_of(), 0)), 400)
# 512 = round_up(400, 256). THE row for `block_size`.
# a CONST is not a buffer either: [] in CPython.
def w_const() -> U32:
  P.mem_eq(P.mem_col(P.walk_of(), P.Walk.k(P.walk_of())), 0)
# a BUFFER on the tuple device ("CPU","METAL") = tags 2 and 3, which is the
# fixture CPython's `cp_mdev` (True) and `cp_mdev_cl` (False) were run against.
# --- `_can_plan`, memory.py:12-16 -------------------------------------------
# MSTACK recurses over EVERY src and does NOT dedupe: CPython printed [A, A]
# for MSTACK(MSEL, MSEL) of one buffer. A dedupe here would be a real difference,
# because `si_bufs` flows into `copy_bufs.update` and into the lifetime upsert.
def w_mstack() -> U32:
  P.mem_eq(P.mem_col(P.walk_of(), P.Walk.mstack(P.walk_of())), 2)
# a STORE is not a buffer and does not recurse: [] in CPython.
def p_hold_d2() -> U32:
  P.mem_eq(P.mem_hold2(P.Proj.at(P.proj_of(), 3), P.mem_scan_tc(P.proj_of()), P.Scan.cp(P.mem_scan_of(P.proj_of()))), 0)
# --- the events, memory.py:43-44 --------------------------------------------
# the COUNT: two per buffer, no more and no fewer.
# lane 1, the COMPUTE lane: 1536, and NOT the sum of 1024 + 512 + 256. F2 reuses
# E2's freed block at 1024, so the high-water mark is the larger of the two
# overlapping pairs and this row is the only thing in the gate that says the
# allocator's answer was used rather than re-derived.
def p_peak1() -> U32: P.mem_eq(P.Peak.p(P.mem_pk_at(P.mem_peaks(P.plan_plan(P.Proj.fx(P.proj_of())), P.Scan.cp(P.mem_scan_of(P.proj_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.proj_of()))), 1)), 1536)
# the lane keys themselves: (CPU,1) then (CPU,0). Without `cp` both lanes would
# collide and `mem_lanes` would answer ONE lane with the sum of both -- so these
# two rows and `p_nlanes` are the whole `_key` contract.
def p_d2_f() -> U32: P.mem_eq(P.mem_nb_f(P.Proj.at(P.proj_of(), 3), P.mem_scan_tc(P.proj_of())), 2)
def p_lane1cp() -> U32: P.mem_eq(P.Lane.cp(P.Peak.ln(P.mem_pk_at(P.mem_peaks(P.plan_plan(P.Proj.fx(P.proj_of())), P.Scan.cp(P.mem_scan_of(P.proj_of())), P.mem_offs(), P.Planned.evs(P.mem_plan(P.proj_of()))), 1))), 0)
# `arena_sizes = {key: round_up(peak, block_size)}` -- 10240 and 1536 are already
# multiples of 256 here, so this pair pins the LANE COUNT and the ordering, and
# `p_peak*` pins the arithmetic underneath.
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- mem_row("w_buf", w_buf())
    _ : Unit <- mem_row("w_buf_is", w_buf_is())
    _ : Unit <- mem_row("w_msel", w_msel())
    _ : Unit <- mem_row("w_mstack", w_mstack())
    _ : Unit <- mem_row("w_store", w_store())
    _ : Unit <- mem_row("w_const", w_const())
    _ : Unit <- mem_row("w_cp_plain", w_cp_plain())
    _ : Unit <- mem_row("w_cp_held", w_cp_held())
    _ : Unit <- mem_row("w_cp_disk", w_cp_disk())
    _ : Unit <- mem_row("w_cp_mdev", w_cp_mdev())
    _ : Unit <- mem_row("w_cp_mdev_cl", w_cp_mdev_cl())
    _ : Unit <- mem_row("p_nbufs", p_nbufs())
    _ : Unit <- mem_row("p_tcn", p_tcn())
    _ : Unit <- mem_row("p_ncopy", p_ncopy())
    _ : Unit <- mem_row("p_b2_f", p_b2_f())
    _ : Unit <- mem_row("p_c2_f", p_c2_f())
    _ : Unit <- mem_row("p_d2_f", p_d2_f())
    _ : Unit <- mem_row("p_e2_f", p_e2_f())
    _ : Unit <- mem_row("p_f2_f", p_f2_f())
    _ : Unit <- mem_row("p_d2_l", p_d2_l())
    _ : Unit <- mem_row("p_e2_l", p_e2_l())
    _ : Unit <- mem_row("p_a2_absent", p_a2_absent())
    _ : Unit <- mem_row("p_nb_b2", p_nb_b2())
    _ : Unit <- mem_row("p_nb_c2", p_nb_c2())
    _ : Unit <- mem_row("p_nb_d2", p_nb_d2())
    _ : Unit <- mem_row("p_nb_e2", p_nb_e2())
    _ : Unit <- mem_row("p_hold_b2", p_hold_b2())
    _ : Unit <- mem_row("p_hold_d2", p_hold_d2())
    _ : Unit <- mem_row("p_nev", p_nev())
    _ : Unit <- mem_row("p_ev3_i", p_ev3_i())
    _ : Unit <- mem_row("p_ev3_o0", p_ev3_o0())
    _ : Unit <- mem_row("p_ev3_b0", p_ev3_b0())
    _ : Unit <- mem_row("p_ev3_o1", p_ev3_o1())
    _ : Unit <- mem_row("p_ev3_b1", p_ev3_b1())
    _ : Unit <- mem_row("p_ev3_o2", p_ev3_o2())
    _ : Unit <- mem_row("p_ev3_b2", p_ev3_b2())
    _ : Unit <- mem_row("p_ev2_o0", p_ev2_o0())
    _ : Unit <- mem_row("p_ev2_b0", p_ev2_b0())
    _ : Unit <- mem_row("p_ev2_o1", p_ev2_o1())
    _ : Unit <- mem_row("p_ev2_b1", p_ev2_b1())
    _ : Unit <- mem_row("p_ev_first", p_ev_first())
    _ : Unit <- mem_row("p_ev_last", p_ev_last())
    _ : Unit <- mem_row("p_tot", p_tot())
    _ : Unit <- mem_row("p_nlanes", p_nlanes())
    _ : Unit <- mem_row("p_peak0", p_peak0())
    _ : Unit <- mem_row("p_peak1", p_peak1())
    _ : Unit <- mem_row("p_lane0cp", p_lane0cp())
    _ : Unit <- mem_row("p_lane1cp", p_lane1cp())
    _ : Unit <- mem_row("p_azs_n", p_azs_n())
    _ : Unit <- mem_row("p_azs0", p_azs0())
    _ : Unit <- mem_row("p_azs1", p_azs1())
    _ : Unit <- mem_row("p_nplan", p_nplan())
    _ : Unit <- mem_row("u_raw", u_raw())
    _ : Unit <- mem_row("u_nb", u_nb())
    _ : Unit <- mem_row("u_tot", u_tot())
    _ : Unit <- mem_row("u_nlanes", u_nlanes())
    _ : Unit <- mem_row("e_nbufs", e_nbufs())
    IO.print(p_count())
