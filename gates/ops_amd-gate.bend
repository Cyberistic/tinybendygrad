# gates/ops_amd-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_amd.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_amd.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D

def nth_of(t: P.Tr) -> U32:
  match t:
    case P.Tr{calls, next, refused, nth, at}: nth


def args.ks(ng: Nat, vards: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, P.args.glob.go(ng, Nil{}), vards)

def args.layout(ks: List<&2, U32>, off: U32) -> List<&2, U32>:
  P.sig.go(ks, off, Nil{})

# the whole thing, given the WIDTHS. `size` is `data.kernargs_segment_size`.
def pack_args(+ks: List<&2, U32>, size: U32) -> List<&2, P.E>:
  List.append(&2, P.E, P.pack.go(P.args.slots(ks, 0, Nil{}), 0, Nil{}), P.pack.tail(P.pack_end(ks), size))

# the three words the header contributes, and the value of the first.
def pkt.header() -> U32:
  U32.or(P.AQL_HDR(), U32.shln(P.HSA_PACKET_TYPE_KERNEL_DISPATCH(), U32.to_nat(P.HSA_PACKET_HEADER_TYPE())))

# `3 << P.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS` and the shift is ZERO, so
# `setup` is 3 and the DIMENSIONS bit is in the low byte of `full_header`.
def pkt.setup() -> U32:
  U32.shln(3, U32.to_nat(P.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS()))

def pkt.grid(gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32) -> List<&2, U32>:
  P.pkt.grid.go(3n, P.Gr{gx, lx}, P.Gr{gy, ly}, P.Gr{gz, lz}, Nil{})

def pkt.shape() -> List<&2, P.E>:
  List.append(&2, P.E, P.pkt.sh_tail(2n, P.pkt.sh_seeds()), [P.E{1, P.PKT_TAIL()}])

# :437-443 `close_run`, the AQL vendor packet that wraps a run of pm4 as an
# indirect buffer. FIVE words plus TEN zeros, and the third word is
# `(end - run_start) // 4 | INDIRECT_BUFFER_VALID`, so a run of 0 dwords and a
# run of 4 produce the SAME word and a run of 8 does not.
def pkt.vendor_hdr() -> U32:
  U32.or(U32.or(P.AQL_HDR(), U32.shln(P.HSA_PACKET_TYPE_VENDOR_SPECIFIC(), U32.to_nat(P.HSA_PACKET_HEADER_TYPE()))), U32.shln(1, 16n))

def pkt.ib_words(nbytes: U32) -> U32:
  U32.or(U32.div(nbytes, 4), 1)

def pkt.vendor_n() -> U32: 15

# :551's `if lds > cap: raise`. The boundary is a STRICT `>`, and the two
# fixtures that straddle it are `amd_lds_edge_*`.
def pd.lds_refuse(gs: U32, lds_kb: U32) -> Bool:
  U32.is_gt(P.pd.lds(gs), P.pd.lds_cap(lds_kb))

# :555, `desc_offset=rodata, entry_point_offset=rodata + entry_byte_offset`.
def pd.of(+rodata: U32, entry: U32, r1: U32, r2: U32, r3: U32, +kp: U32,
          +gs: U32, ps: U32, ka: U32, t0: U32) -> P.Pd:
  P.Pd{rodata, U32.add(rodata, entry), P.pd.rsrc1_of(r1, t0), P.pd.rsrc2_of(r2, gs), r3,
     P.pd.wave32_of(kp), ps, gs, ka, P.pd.edp_of(kp), P.pd.epsgpr_of(kp)}

# :561, `bytes(image).ljust(round_up(len(image), 4), b"\x00")` -- the program is
# uploaded as WHOLE dwords, so the padded length is a multiple of four and the
# pad is the difference. `amd_pd_img_pad` is `len(image) % 4`, which is 0 for a
# whole number of dwords and the pad otherwise.
def pd.img_pad(n: U32) -> U32: U32.mod(n, 4)
def pd.img_len(n: U32) -> U32: H.round_up_u32(n, 4)

def spec_nolru(x: D.Bspec) -> Bool:
  P.nolru_of(P.flags_of(x))

def spec_ext(x: D.Bspec) -> Bool:
  P.ext_of(P.flags_of(x))

def spec_ib() -> D.Bspec: D.Bspec{False{}, False{}, False{}, False{}, True{}}
def spec_plain() -> D.Bspec: D.Bspec{False{}, False{}, False{}, False{}, False{}}

def prog_recycled() -> Bool: D.recycled(True{}, True{}, P.spec_prog())
def ring_recycled() -> Bool: D.recycled(True{}, True{}, P.spec_ring())
def scratch_recycled() -> Bool: D.recycled(True{}, True{}, P.spec_scratch())
def prof_recycled(host: Bool) -> Bool: D.recycled(True{}, True{}, P.spec_prof(host))

# and the LIFO reuse order, which is `c.pop()` -- the MOST RECENTLY freed.
def lru_take(xs: List<&2, U32>) -> U32: D.alloc_take(xs)

# :1033-1034, `if b not in self.prog_bufs: ... = Buffer(...)` -- the memo is a
# HAS-then-INSERT, and both arms return the SAME buffer, so a hit and a miss are
# indistinguishable from the answer and only the TRACE length tells them apart.
def prog_memo(hit: Bool) -> U32: Bool.pick(U32, hit, 1, 2)

def trgt_of(v: U32) -> U32: U32.div(v, 10000)
def trgt_minor(v: U32) -> U32: U32.mod(U32.div(v, 100), 100)
def trgt_step(v: U32) -> U32: U32.mod(v, 100)

def arch_of(t0: U32, t1: U32, t2: U32) -> String:
  String.concat(["gfx", U32.show(t0), P.hx.sh(t1), P.hx.sh(t2)])

# :860, `assert (target in ((9,4,2),(9,5,0))) or target[0] in (11, 12)`. The
# allow-list is a PAIR: gfx9 is allowed only at two exact versions and gfx11+ is
# allowed by MAJOR alone, so `9.4.3` and `13.0.0` are both refused and `11.99.9`
# is allowed.
def arch_ok(+t0: U32, +t1: U32, +t2: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_eq(t0, 9), Bool.or(
    Bool.and(U32.is_eq(t1, 4), U32.is_eq(t2, 2)),
    Bool.and(U32.is_eq(t1, 5), U32.is_eq(t2, 0)))),
    Bool.or(U32.is_eq(t0, 11), U32.is_eq(t0, 12))), False{})

# :864, `se_cnt = array_count // simd_arrays_per_engine // xccs`. TWO integer
# divisions, so it is NOT `array_count // (simd_arrays_per_engine * xccs)` and
# the two disagree whenever the product does not divide.
def dev_se_cnt(array_count: U32, sae: U32, xccs: U32) -> U32:
  U32.div(U32.div(array_count, sae), xccs)

# :865, `cu_cnt = simd_count // simd_per_cu // xccs` -- the same shape.
def dev_cu_cnt(simd_count: U32, spc: U32, xccs: U32) -> U32:
  U32.div(U32.div(simd_count, spc), xccs)

# :866, `waves_per_cu = max_waves_per_simd * simd_per_cu`.
def dev_waves_per_cu(mwps: U32, spc: U32) -> U32: U32.mul(mwps, spc)

# :867, `wave_cnt = cu_cnt*waves_per_cu if target[0] != 9 else
# min(cu_cnt*40, se_cnt*xccs*512)`. The gfx9 arm is a MIN of two products and
# `40` and `512` are the two magic multipliers.
def dev_wave_cnt(t0: U32, +cu: U32, wpu: U32, se: U32, xccs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t0, 9),
    U32.min(U32.mul(cu, 40), U32.mul(U32.mul(se, xccs), 512)),
    U32.mul(cu, wpu))

# :863, `xccs = iface.props.get('num_xcc', 1)`.
def dev_xccs(has: Bool, n: U32) -> U32: Bool.pick(U32, has, n, 1)

# :879, `is_aql = getenv("AMD_AQL", int(xccs > 1))`.
def dev_is_aql(forced: Bool, want: Bool) -> Bool: Bool.or(forced, want)

def dev_max_copy(+v0: U32, +v1: U32, +v2: U32) -> U32:
  Bool.pick(U32, Bool.or(
    Bool.and(P.vge3(P.Ver.of(v0, v1, v2), P.Ver.of(4, 4, 2)), Bool.not(P.vge3(P.Ver.of(v0, v1, v2), P.Ver.of(5, 0, 0)))),
    P.vge3(P.Ver.of(v0, v1, v2), P.Ver.of(5, 2, 0))), P.MAXCOPY_BIG(), P.MAXCOPY_SMALL())

# :854, `isinstance(self.iface, USBIface)`.
def is_usb(iface: U32) -> Bool: U32.is_eq(iface, P.IFACE_USB())
# :856, `can_recover = P.is_am() and not is_vf`.
def can_recover(iface: U32, is_vf: Bool) -> Bool:
  Bool.and(P.is_am(iface), Bool.not(is_vf))

def mod_offsets(t0: U32) -> U32: Bool.pick(U32, U32.is_eq(t0, 9), 0, 1)
def mod_pm4(t0: U32) -> U32: Bool.pick(U32, U32.is_eq(t0, 9), 0, 1)
def mod_nbio(t0: U32) -> U32: Bool.pick(U32, U32.is_lt(t0, 12), 0, 1)

# the sdma clamp, :872, `min(ip_versions[am.SDMA0_HWIP], (6,0,0))` --
# componentwise, so `6.5.0` clamps to `6.0.0` and `4.4.1` does not move.
def sdma_clamp0(v: U32) -> U32: U32.min(v, 6)

# the ladder's ANSWER, indexed by the clamped MAJOR: 4 -> sdma_4_0_0,
# 5 -> sdma_5_0_0, 6 -> sdma_6_0_0, and a major below 4 RAISES. The ladder is
# "the greatest with matching major <= target", so within one major the MINOR is
# irrelevant -- `amd_sdma_mod_4_4_1` and `amd_sdma_mod_4_3_9` are the same row.
def sdma_mod(major: U32) -> U32:
  match major:
    case 4: 0
    case 5: 1
    case 6: 2
    case _: 3

# `import_soc` (:35), `getattr(am, f"soc_{ip[0]}")` -- soc_9 / soc_11 / soc_12.
def soc_mod(t0: U32) -> U32:
  match t0:
    case 9: 0
    case 11: 1
    case 12: 2
    case _: 3

def tmpring_size(+ps: U32, +t0: U32, +slots: U32, +cu: U32, se: U32, xccs: U32) -> U32:
  P.tmp_ring(P.scr_num_waves(P.scr_per_xcc(P.scr_per_thread(ps, t0), slots, cu),
           P.scr_wave_scratch(P.scr_per_thread(ps, t0), t0), t0, se),
    P.scr_max_waves(cu, slots, xccs), P.scr_wave_scratch(P.scr_per_thread(ps, t0), t0))

# :996, `Buffer(self.device, size_per_xcc * self.xccs, dtypes.u8, ...)`, and
# :990's `max(private_segment_size, 128, AMDDevice.max_scratch_psize)` -- the
# CLASS attribute, so the scratch buffer only ever GROWS. P.A request smaller
# than the high-water mark does not shrink it, and that is a row.
def scr_buf(ps: U32, t0: U32, slots: U32, cu: U32, xccs: U32) -> U32:
  U32.mul(P.scr_per_xcc(P.scr_per_thread(ps, t0), slots, cu), xccs)

def scr_high(prev: U32, ps: U32) -> U32: U32.max(U32.max(ps, P.PRIV_FLOOR()), prev)

# :954, `wg_data_size = round_up((vgpr + sgrp + lds + hwreg) * cu_cnt, P.PAGESIZE)`.
def q_wg_data(+t0: U32, +t1: U32, t2: U32, lds_kb: U32, cu: U32) -> U32:
  H.round_up_u32(U32.mul(U32.add(U32.add(
    U32.add(P.q_vgpr_per_cu(t0, t1, t2), P.SGRP_PER_CU()),
    P.q_lds_per_cu(t0, t1, lds_kb)), P.HWREG_PER_CU()), cu), P.PAGESIZE())

# :955, `ctl_stack_size = round_up((12 if target[0] != 9 else 8)*wave_cnt + 8 +
# 40, P.PAGESIZE)`. The `+ 8 + 40` is a CONSTANT tail, and it is inside the
# round_up, so a wave count that is already page-aligned still rounds up by the
# page.
def q_ctl(t0: U32, wave_cnt: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(
    U32.mul(Bool.pick(U32, U32.is_eq(t0, 9), P.CTL_WAVES_GFX9(), P.CTL_WAVES_NEW()), wave_cnt), 8), 40), P.PAGESIZE())

# :958, `ctx_save_restore_size = 0 if self.is_am() else wg_data_size +
# ctl_stack_size`. The AM path does NOT save context, so it is ZERO and the two
# sizes are dead on that path -- which is exactly why both rows exist.
def q_csr(is_am: Bool, wg: U32, ctl: U32) -> U32:
  Bool.pick(U32, is_am, 0, U32.add(wg, ctl))

# :959, `debug_memory_size = round_up(wave_cnt * 32, 64)`.
def q_dbg(wave_cnt: U32) -> U32: H.round_up_u32(U32.mul(wave_cnt, 32), 64)

# :956-957, the ring size and the eop buffer.
def q_ring(is_usb: Bool) -> U32: Bool.pick(U32, is_usb, P.RING_USB(), P.RING_HOST())

# :924, `Buffer(self.device, ring_size // 4, dtypes.u32, ...)`. The ring is
# counted in BYTES here and in ELEMENTS there, and the /4 is the only place the
# two meet. `amd_ring_elems_*` is the row.
def q_ring_elems(ring_size: U32) -> U32: U32.div(ring_size, 4)
def q_gart_size() -> U32: 256

# :944, `not tag.startswith(("ring_", "write_ptr_", "doorbell_",
# "put_value_"))`. Four prefixes, and the trailing underscore is in EACH of
# them -- "ring" alone is NOT a match, which is the boundary fixture.
def qb_prefixed(+tag: String) -> Bool:
  Bool.or(Bool.or(Bool.or(
    String.starts_with(tag, "ring_"),
    String.starts_with(tag, "write_ptr_")),
    Bool.or(String.starts_with(tag, "doorbell_"),
    String.starts_with(tag, "put_value_"))), False{})

# :946, `compute_queue if queue == 'compute' else sdma_queue(int(idx))`. The
# arm is decided by the SECOND piece alone and the third is `int()`ed, so
# "compute" and "sdma" differ in the arm and "0" and "7" only in the index.
def qb_arm(queue: String) -> U32:
  Bool.pick(U32, String.eq(queue, "compute"), 0, 1)

# :1041, `off = (se * prof_slots + slot) * sqtt_win` -- SE-MAJOR, so two SEs of
# one slot are `sqtt_win` apart and two SLOTS of one SE are `prof_slots`
# apart, and the buffer is `[sqtt_win * prof_slots * sqtt_ses]` (:1028).
def sq_off(se: U32, slot: U32, slots: U32, win: U32) -> U32:
  U32.mul(U32.add(U32.mul(se, slots), slot), win)

def sq_wptr(raw: U32) -> H.I64: P.sq_shl5(P.sq_masked(raw))

# :1043, the gfx11-only correction, `wptr -= ((buf + off) // 32 & 0x1FFFFFFF) *
# 32`, and it is NEGATIVE: the hardware wrote a buffer-relative pointer and the
# reader has to make it absolute. P.A port that omits it reads past the end, and a
# port that does it in U32 wraps on top of that.
def sq_fix11(base: U32, off: U32, raw: U32) -> H.I64:
  P.sq_shl5(U32.sub(P.sq_masked(raw), U32.and(U32.div(U32.add(base, off), 32), 536870911)))

# :1044, `assert 0 <= wptr <= self.sqtt_win`. P.A STRICT upper bound and a
# non-negative lower bound, and it is the only place the port refuses on a
# pointer.
def sq_assert(+wptr: U32, win: U32) -> Bool:
  Bool.and(U32.is_ge(wptr, 0), U32.is_le(wptr, win))

# :1045, `if wptr >= self.sqtt_win - 32`, the overflow WARNING. It is `>=`, so
# a wptr exactly at `win-32` warns, and the comparison is UNSIGNED -- a
# wptr below 32 makes `win-32` wrap for a small window.
def sq_full(wptr: U32, win: U32) -> Bool:
  U32.is_ge(wptr, U32.sub(win, 32))

# :1048, the gfx9 header, `struct.pack('<Q', 0x11 | (4<<13) | (0xf<<16) | (se<<24))`.
def sq_hdr9(se: U32) -> U32:
  U32.or(U32.or(U32.or(17, U32.shln(4, 13n)), U32.shln(15, 16n)), U32.shln(se, 24n))

# :904, `sqtt_ses = se_cnt * xccs` and `sqtt_win = (SQTT_BUFFER_SIZE << 20) //
# prof_slots` -- megabytes, PER SHADER ENGINE, and the per-slot division is why
# raising PROF_SLOTS shrinks each slot.
def sq_ses(se: U32, xccs: U32) -> U32: U32.mul(se, xccs)
def sq_win(mb: U32, slots: U32) -> U32: U32.div(U32.shln(mb, 20n), slots)

def pmc_block_sq(gfx9: Bool, +se_cnt: U32, cpus: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, gfx9, [1, se_cnt, 1, 1],
    [1, se_cnt, 2, U32.div(cpus, 2)])

def pmc_block(n: U32) -> List<&2, U32>:
  match n:
    case 0: [1, 1, 1, 1]
    case 1: [32, 1, 1, 1]
    case _: [16, 1, 1, 1]

# :196, `rec_size = prod((xccs, inst, se, sa, wgp)) * 8`.
def pmc_rec_size(xccs: U32, inst: U32, se: U32, sa: U32, wgp: U32) -> U32:
  U32.mul(H.prod_u32([xccs, inst, se, sa, wgp]), 8)

# :735, `((cu_bitmap[se % 4][sa + (se // 4) * 2] >> (2 * wgp)) & 0x3) == 0x3`.
# The cell INDEX is `sa + (se//4)*2`, which is why a (se, sa) pair above (3, 1)
# needs a bitmap wider than four rows, and `is_wgp_active` on the AM path
# (:747) is UNCONDITIONALLY TRUE -- a row.
def wgp_active(se: U32, sa: U32, wgp: U32, cell: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(cell, U32.to_nat(U32.mul(2, wgp))), 3), 3)

def wgp_active_am() -> Bool: True{}

def sq_mask(+gsize: U32, +cu_cnt: U32, +se_cnt: U32, +cpus: U32, +i: U32) -> U32:
  U32.and(U32.or(P.sq_lo(P.sq_mk(gsize, cu_cnt, se_cnt, cpus, i)),
    P.sq_hi(P.sq_mk(gsize, cu_cnt, se_cnt, cpus, i))), 4294967295)


def ureg_scratch(flag: Bool) -> U32:
  Bool.pick(U32, flag, U32.or(0, U32.shln(1, U32.to_nat(P.SCRATCH_FLAG_BIT()))), 0)

def ureg_n(priv: Bool, +edp: Bool) -> U32:
  Bool.pick(U32, priv, Bool.pick(U32, edp, 5, 4), Bool.pick(U32, edp, 2, 1))

# `dispatch_init` (:382-383),
# `encode(({'cs_w32_en': int(data.wave32)} if target[0] != 9 else {}),
# force_start_at_000=1, compute_shader_en=1)`, and `AMDReg.encode` (:19) is a
# REDUCE of `value << self.fields[name][0]`, so the three field positions are
# the register table and their order is irrelevant while their POSITIONS are
# not. The port carries the positions as named constants and the reduction.
def disp_init(force_at: U32, cs_en: U32, w32: U32) -> U32:
  U32.or(U32.or(U32.shln(force_at, 0n), U32.shln(cs_en, 1n)), U32.shln(w32, 2n))

# :99, `instance_val = (wgp << 2 | (instance or 0)) if wgp is not None else
# instance` -- the OR of a SHIFTED wgp with the instance, and the else arm
# is the bare instance. Two arms, and a port that always shifts writes a
# wrong broadcast word for the common `set_grbm()` with no arguments.
def grbm_inst(wgp: U32, +inst: U32, has_wgp: Bool) -> U32:
  Bool.pick(U32, has_wgp, U32.or(U32.shln(wgp, U32.to_nat(P.GRBM_WGP_SHIFT())), inst), inst)

# :104-105, `WAIT_REG_MEM_MEM_SPACE(int(mem is not None)) |
# WAIT_REG_MEM_OPERATION(int(mem is None and reg_done > 0)) |
# WAIT_REG_MEM_FUNCTION(op) | WAIT_REG_MEM_ENGINE(0)`, with the four field
# positions in autogen's `regs/nv/gc.py`. The first two are MUTUALLY EXCLUSIVE
# and the second is a CONJUNCTION, so `mem` given and `reg_done` set is the
# corner that a port which ORs the two booleans gets wrong.
def wrm_info(+has_mem: Bool, reg_done_gt: Bool, op: U32) -> U32:
  U32.or(U32.or(U32.shln(Bool.to_u32(has_mem), 0n),
    U32.shln(Bool.to_u32(Bool.and(Bool.not(has_mem), reg_done_gt)), 1n)),
    U32.shln(op, 2n))

# :175, `prof_bump` -- `log.index(0).load() + len(self.profiled)`, the ring
# index the NEXT kernel's slot is taken from, and `prof_start` (:159) is
# `(prof_log[0] + len(profiled)) % prof_slots`. The modulo is what makes the
# log a RING and a too-small PROF_SLOTS overwrites a live slot -- which is
# :1058's warning and the reason `scr_high`'s monotone max has a sibling here.
def prof_slot(read: U32, nprofiled: U32, slots: U32) -> U32:
  U32.mod(U32.add(read, nprofiled), slots)

# the name :869 and :871 and :876 pick, both directions.
def iface_name(i: U32) -> String:
  match i:
    case 0: "KFDIface"
    case 1: "PCIIface"
    case 2: "USBIface"
    case 3: "MOCKIface"
    case 4: "MOCK"
    case 5: "MOCKPCIIface"
    case 6: "MOCKUSBIface"
    case _: ""

def sdma_name(i: U32) -> String:
  match i:
    case 0: "sdma_4_0_0"
    case 1: "sdma_5_0_0"
    case 2: "sdma_6_0_0"
    case _: "RAISE"

def soc_name(i: U32) -> String:
  match i:
    case 0: "soc_9"
    case 1: "soc_11"
    case 2: "soc_12"
    case _: "RAISE"

def mod_name(i: U32) -> String:
  match i:
    case 0: "vega_offsets/navi_offsets"
    case 1: "soc_9/soc_11/soc_12"
    case 2: "pm4_soc15/pm4_nv"
    case 3: "sdma_4_0_0/sdma_5_0_0/sdma_6_0_0"
    case 4: "gc"
    case 5: "nbio/nbif"
    case _: ""

# the whole init, unrefused, for :848/:950/:959's queue sizes as arguments.
def dev.init(iface: U32, ring: U32, gart: U32) -> P.Tr:
  P.dev.tail(P.dev.imports(P.dev.head(P.Tr.of(), iface)), ring, gart)


# --- THE GATE ROWS ------------------------------------------------------
# THE GATE. Every expectation is in `.agents/slop/amd_oracle.txt`, and every one
# of them was GENERATED BY CALLING CPython -- see
# `.agents/slop/amd_oracle.py`, which drives `hcq2.layout_args`/`pack_args` on
# real UOps, `_amd_program_image` with `elf_loader` stubbed on a synthetic
# descriptor, `AMDDevice.tmpring_size` on a shim, `AMDReg`/`AMDReg.encode`,
# `import_module`, `import_soc`, `import_pmc`, `BufferSpec` through
# `Allocator.free`, and reads every constant out of `autogen/{hsa,kfd,am}.py`.
# NOTHING here is hand-typed, which matters: the `renderer/cstyle.bend` unit
# shipped 215 hand-typed expectations of which SEVENTEEN were wrong, twelve of
# them real port bugs.
# ===========================================================================

def E.knd(e: P.E) -> U32:
  match e:
    case P.E{k, n}: k

def E.nbytes_(e: P.E) -> U32:
  match e:
    case P.E{k, n}: n

# the WRONG advance, kept as a def so the gate can print BOTH and the mutation
# table can name the difference. `D.iter_sig` in `device.bend` is this one, and
# `amd_arg_walrus_raw` is the value IT produces -- which is not CPython's.
def sig_raw.go(ks: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case +k <> t: sig_raw.go(t, U32.add(off, k),
      List.append(&2, U32, acc, [H.round_up_u32(off, k)]))

def sig_raw(ks: List<&2, U32>, off: U32) -> List<&2, U32>:
  sig_raw.go(ks, off, Nil{})

# the total the pack must add up to: `kernargs_segment_size`. P.A pad or a word
# that is one byte short shows up here and NOWHERE else, because the element
# list would still have the right length.
def pack_bytes.go(xs: List<&2, P.E>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case e <> t: pack_bytes.go(t, U32.add(acc, E.nbytes_(e)))

def pack_bytes(ks: List<&2, U32>, size: U32) -> U32:
  pack_bytes.go(pack_args(ks, size), 0)

# `xs[0]`, which is `List.get` and a `Maybe` and no sugar. The trace's
# `P.Tr.args` is read at index 0 by three rows and at index 3 and 5 by two more.
def at0(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 0n), 0)
def at1(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 1n), 0)
def at3(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 3n), 0)
def at5(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 5n), 0)
def at6(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 6n), 0)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def i64row(nm: String, x: H.I64) -> IO(Unit): srow(nm, H.i64_text(x))

def srow2(nm: String, a: Bool, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(a), " ", Bool.show(b)]))

# the `W8`/`B12` rendering of one element list, space separated.
def esh2(xs: List<&2, P.E>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +e <> t: esh2(t, List.append(&2, String, acc,
      [String.concat([Bool.pick(String, U32.is_eq(E.knd(e), 0), "W", "B"),
        U32.show(E.nbytes_(e))])]))

def elrow(nm: String, xs: List<&2, P.E>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(esh2(xs, Nil{}), " ")]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush(t, List.append(&2, String, acc, [U32.show(x)]))

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), " ")]))

# --- the fixtures ---------------------------------------------------------
# 3 global buffers, no vars: what every 3-input float kernel looks like.
def KS_B3() -> List<&2, U32>: [8, 8, 8]
# 3 globals and two uint32 vars: the var widths are what make the pack pads.
def KS_B3V2() -> List<&2, U32>: [8, 8, 8, 4, 4]
# the mixed fixture, and the ONLY one that can see the walrus: after the uint8
# at 24 the next offset is round_up(24,1)+1 = 25, and round_up(25,4) is 28.
def KS_MIX() -> List<&2, U32>: [8, 8, 8, 1, 4, 2]
def KS_B2V1() -> List<&2, U32>: [8, 8, 1]
def KS_B1V1() -> List<&2, U32>: [8, 8]
def KS_V4() -> List<&2, U32>: [4, 1, 8, 2]
# the two WALRUS fixtures: [1,4,1] is the smallest list where the rounded and
# the raw advance disagree, and the second adds a third byte in a row.
def KS_W1() -> List<&2, U32>: [1, 4, 1]
def KS_W2() -> List<&2, U32>: [1, 4, 1, 1]

# --- 1: the constants, :36-41 ---------------------------------------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("amd_aql_hdr", P.AQL_HDR())
    urow("amd_aql_bits", U32.or(U32.or(U32.shln(1, U32.to_nat(P.HSA_PACKET_HEADER_BARRIER_BIT())),
      U32.shln(P.HSA_FENCE_SCOPE_SYSTEM(), U32.to_nat(P.HSA_PACKET_HEADER_SCACQUIRE_FENCE_SCOPE_BIT()))),
      U32.shln(P.HSA_FENCE_SCOPE_SYSTEM(), U32.to_nat(P.HSA_PACKET_HEADER_SCRELEASE_FENCE_SCOPE_BIT()))))
    urow("amd_hdr_type", P.HSA_PACKET_HEADER_TYPE())
    urow("amd_type_kdispatch", P.HSA_PACKET_TYPE_KERNEL_DISPATCH())
    urow("amd_type_vendor", P.HSA_PACKET_TYPE_VENDOR_SPECIFIC())
    urow("amd_setup_dim", P.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS())
    urow("amd_kprops_dispatch_ptr", U32.shln(1, U32.to_nat(P.KPROPS_EDP_BIT())))
    urow("amd_kprops_priv_seg", U32.shln(1, U32.to_nat(P.KPROPS_EPS_BIT())))
    urow("amd_qprop_ptr64", U32.shln(1, U32.to_nat(P.QPROP_IS_PTR64_BIT())))
    urow("amd_qprof_prof", U32.shln(1, U32.to_nat(P.QPROP_PROFILING_BIT())))
    urow("amd_event_index_partial_flush", P.EVENT_INDEX_PARTIAL_FLUSH())
    urow("amd_wait_fn_eq", P.WAIT_REG_MEM_FUNCTION_EQ())
    urow("amd_wait_fn_neq", P.WAIT_REG_MEM_FUNCTION_NEQ())
    urow("amd_wait_fn_geq", P.WAIT_REG_MEM_FUNCTION_GEQ())
    urow("amd_pkt_size", P.PKT_BYTES())
    urow("amd_pkt_slice_head", P.PKT_HEAD())
    urow("amd_pkt_slice_mid", P.PKT_MID())
    urow("amd_pkt_slice_tail", P.PKT_TAIL())
    urow("amd_desc_size", P.DESC_BYTES())

# --- 2: the argument trace, the widths and the slots, :362 and hcq2:74-76 ---
def t_layout() -> IO(Unit):
  do IO<Unit>:
    lrow("amd_arg_ks_b3", args.ks(3n, Nil{}))
    lrow("amd_arg_ks_b3v2_32", args.ks(3n, [4, 4]))
    lrow("amd_arg_ks_b3v3_mix", args.ks(3n, [1, 4, 2]))
    lrow("amd_arg_ks_b1v1_64", args.ks(1n, [8]))
    lrow("amd_arg_ks_b2v1_8", args.ks(2n, [1]))
    lrow("amd_arg_ks_b0v4", args.ks(0n, KS_V4()))
    lrow("amd_arg_at_b3", args.layout(KS_B3(), 0))
    lrow("amd_arg_at_b3v2_32", args.layout(KS_B3V2(), 0))
    lrow("amd_arg_at_b3v3_mix", args.layout(KS_MIX(), 0))
    lrow("amd_arg_at_b1v1_64", args.layout(KS_B1V1(), 0))
    lrow("amd_arg_at_b2v1_8", args.layout(KS_B2V1(), 0))
    lrow("amd_arg_at_b0v4", args.layout(KS_V4(), 0))
    # THE WALRUS, on its own: [1,4,1] is `0 4 8` in CPython and `0 4 5` if the
    # advance is the RAW itemsize. This is the row that pins the disagreement
    # with `D.iter_sig` reported in the header, and `amd_arg_walrus_raw` is the
    # value `device.bend` produces.
    lrow("amd_arg_walrus_w1", args.layout(KS_W1(), 0))
    lrow("amd_arg_walrus_raw_w1", sig_raw(KS_W1(), 0))
    lrow("amd_arg_walrus_w2", args.layout(KS_W2(), 0))
    lrow("amd_arg_walrus_raw_w2", sig_raw(KS_W2(), 0))
    lrow("amd_arg_walrus_b3v3_mix", args.layout(KS_MIX(), 0))
    lrow("amd_arg_walrus_raw_b3v3_mix", sig_raw(KS_MIX(), 0))
    # a NON-ZERO base, which is what `layout_args(args, offset)` is for and what
    # `ops_nv.bend` uses for its qmd base.
    lrow("amd_arg_at_b3v2_32_base4", args.layout(KS_B3V2(), 4))
    lrow("amd_arg_at_b3v2_32_base512", args.layout(KS_B3V2(), 512))
    lrow("amd_arg_at_b3v3_mix_base4", args.layout(KS_MIX(), 4))
    lrow("amd_arg_at_b3_base4", args.layout(KS_B3(), 4))
    lrow("amd_arg_at_b0v4_base4", args.layout(KS_V4(), 4))
    lrow("amd_arg_at_b0v4_base512", args.layout(KS_V4(), 512))

# --- 3: the pack, hcq2:78-83 ----------------------------------------------
def t_pack() -> IO(Unit):
  do IO<Unit>:
    elrow("amd_pack_b3_24", pack_args(KS_B3(), 24))
    elrow("amd_pack_b3_32", pack_args(KS_B3(), 32))
    elrow("amd_pack_b3_40", pack_args(KS_B3(), 40))
    elrow("amd_pack_b3_64", pack_args(KS_B3(), 64))
    elrow("amd_pack_b3v2_32_32", pack_args(KS_B3V2(), 32))
    elrow("amd_pack_b3v2_32_40", pack_args(KS_B3V2(), 40))
    elrow("amd_pack_b3v2_32_64", pack_args(KS_B3V2(), 64))
    elrow("amd_pack_b3v3_mix_34", pack_args(KS_MIX(), 34))
    elrow("amd_pack_b3v3_mix_40", pack_args(KS_MIX(), 40))
    elrow("amd_pack_b3v3_mix_42", pack_args(KS_MIX(), 42))
    elrow("amd_pack_b3v3_mix_64", pack_args(KS_MIX(), 64))
    elrow("amd_pack_b2v1_8_17", pack_args(KS_B2V1(), 17))
    elrow("amd_pack_b2v1_8_24", pack_args(KS_B2V1(), 24))
    elrow("amd_pack_b0v4_18", pack_args(KS_V4(), 18))
    elrow("amd_pack_b0v4_40", pack_args(KS_V4(), 40))
    elrow("amd_pack_b0v4_64", pack_args(KS_V4(), 64))
    elrow("amd_pack_b1v1_64_16", pack_args(KS_B1V1(), 16))
    elrow("amd_kernargs_off", pack_args(KS_B3V2(), 40))
    # the COUNT, not just a boolean: a pad that fires when it should not makes
    # the list LONGER, and a dropped word makes it SHORTER.
    urow("amd_pack_n_b3_40", U32.from_nat(List.length(&2, P.E, pack_args(KS_B3(), 40))))
    urow("amd_pack_n_mix_40", U32.from_nat(List.length(&2, P.E, pack_args(KS_MIX(), 40))))
    urow("amd_pack_n_b0v4_40", U32.from_nat(List.length(&2, P.E, pack_args(KS_V4(), 40))))
    # and the TOTAL, which is `kernargs_segment_size`. P.A pad or a word that is
    # one byte short shows up here and NOWHERE else, because the element list
    # would still have the right length.
    urow("amd_pack_bytes_b3_40", pack_bytes(KS_B3(), 40))
    urow("amd_pack_bytes_b3v3_mix_40", pack_bytes(KS_MIX(), 40))
    urow("amd_pack_bytes_b0v4_40", pack_bytes(KS_V4(), 40))
    urow("amd_pack_bytes_b3v2_40", pack_bytes(KS_B3V2(), 40))
    urow("amd_pack_bytes_b3_24", pack_bytes(KS_B3(), 24))
    urow("amd_pack_bytes_b3_32", pack_bytes(KS_B3(), 32))
    urow("amd_pack_bytes_b3_64", pack_bytes(KS_B3(), 64))
    urow("amd_pack_bytes_b0v4_18", pack_bytes(KS_V4(), 18))
    urow("amd_pack_bytes_b0v4_24", pack_bytes(KS_V4(), 24))
    urow("amd_pack_bytes_b0v4_34", pack_bytes(KS_V4(), 34))
    urow("amd_pack_bytes_b0v4_64", pack_bytes(KS_V4(), 64))
    urow("amd_pack_bytes_b3v3_mix_34", pack_bytes(KS_MIX(), 34))
    urow("amd_pack_bytes_b3v3_mix_64", pack_bytes(KS_MIX(), 64))

# --- 4: the dispatch packet, :61-67 and :437-443 --------------------------
def pkt.nwords() -> U32:
  U32.div(U32.add(U32.add(U32.add(U32.add(P.PKT_HEAD(), U32.mul(3, 4)), P.PKT_MID()),
    U32.mul(2, 8)), P.PKT_TAIL()), 4)

def t_dispatch() -> IO(Unit):
  do IO<Unit>:
    urow("amd_pkt_header_val", pkt.header())
    urow("amd_pkt_setup_val", pkt.setup())
    urow("amd_pkt_setup_shift", P.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS())
    urow("amd_pkt_hdr_type", P.HSA_PACKET_HEADER_TYPE())
    urow("amd_pkt_tail_len", P.PKT_TAIL())
    elrow("amd_dispatch_shape", pkt.shape())
    urow("amd_dispatch_nwords", pkt.nwords())
    lrow("amd_grid_mul", pkt.grid(128, 1, 1, 64, 1, 1))
    lrow("amd_grid_3d", pkt.grid(16, 8, 4, 4, 2, 1))
    lrow("amd_wg_dims", pkt.grid(1, 1, 1, 64, 1, 1))
    urow("amd_close_run_hdr", pkt.vendor_hdr())
    srow("amd_close_run_hdr_bits", String.concat([U32.show(U32.shln(1, 16n)), " ",
      U32.show(U32.shln(P.HSA_PACKET_TYPE_VENDOR_SPECIFIC(), U32.to_nat(P.HSA_PACKET_HEADER_TYPE())))]))
    urow("amd_close_run_n", pkt.vendor_n())
    urow("amd_close_run_ib3_0", pkt.ib_words(0))
    urow("amd_close_run_ib3_4", pkt.ib_words(4))
    urow("amd_close_run_ib3_16", pkt.ib_words(16))
    urow("amd_close_run_ib3_100", pkt.ib_words(100))
    urow("amd_ib_valid", U32.and(pkt.ib_words(64), 1))
    urow("amd_ib_len_64", U32.div(64, 4))
    urow("amd_ib_len_v_64", pkt.ib_words(64))
    urow("amd_ib_len_100", U32.div(100, 4))
    urow("amd_ib_len_v_100", pkt.ib_words(100))
    # :56's `_queue_args` ring tags, the four names one queue produces.
    srow("amd_ib_tag_compute", P.to_name(P.QF_RING(), "COMPUTE:0"))
    srow("amd_wp_tag_sdma0", P.to_name(P.QF_WRITE_PTR(), "SDMA:0"))
    srow("amd_db_tag_compute", P.to_name(P.QF_DOORBELL(), "COMPUTE:0"))
    srow("amd_pv_tag_sdma3", P.to_name(P.QF_PUT_VALUE(), "SDMA:3"))
    srow("amd_fold_unknown", P.fold_q("SOMETHING_ELSE"))

# --- 5: AMDProgramData, the eleven fields, :551-561 ----------------------
# The four DESCRIPTOR fixtures below are the oracle's, spelled out: `plain` is
# all zeros, `wave32` sets kprops bit 10 and the rsrc words, `edp` sets kprops
# bit 1, `privsg` sets kprops bit 0. The oracle builds each as a REAL
# `llvm_amdhsa_kernel_descriptor_t`, runs the REAL `_amd_program_image` with
# `elf_loader` stubbed, and reads the eleven fields off the result -- so a wrong
# bit position in this file is a diff, not an opinion.
def t_prog() -> IO(Unit):
  do IO<Unit>:
    +p : P.Pd <- IO.pure(P.Pd, pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 11))
    urow("amd_pd_desc_off_wave32_11", P.Pd.desc_off(p))
    urow("amd_pd_entry_off_wave32_11", P.Pd.entry_off(p))
    urow("amd_pd_rsrc1_wave32_11", P.Pd.rsrc1(p))
    urow("amd_pd_rsrc2_wave32_11", P.Pd.rsrc2(p))
    urow("amd_pd_rsrc3_wave32_11", P.Pd.rsrc3(p))
    row("amd_pd_wave32b_wave32_11", P.Pd.wave32(p))
    urow("amd_pd_priv_wave32_11", P.Pd.priv(p))
    urow("amd_pd_grp_wave32_11", P.Pd.grp(p))
    urow("amd_pd_ka_wave32_11", P.Pd.kaseg(p))
    urow("amd_pd_edp_wave32_11", P.Pd.edp(p))
    urow("amd_pd_epsgpr_wave32_11", P.Pd.epsgpr(p))
    +q : P.Pd <- IO.pure(P.Pd, pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 11))
    urow("amd_pd_desc_off_plain_11", P.Pd.desc_off(q))
    urow("amd_pd_entry_off_plain_11", P.Pd.entry_off(q))
    urow("amd_pd_rsrc1_plain_11", P.Pd.rsrc1(q))
    urow("amd_pd_rsrc2_plain_11", P.Pd.rsrc2(q))
    urow("amd_pd_rsrc3_plain_11", P.Pd.rsrc3(q))
    row("amd_pd_wave32b_plain_11", P.Pd.wave32(q))
    urow("amd_pd_priv_plain_11", P.Pd.priv(q))
    urow("amd_pd_grp_plain_11", P.Pd.grp(q))
    urow("amd_pd_ka_plain_11", P.Pd.kaseg(q))
    urow("amd_pd_edp_plain_11", P.Pd.edp(q))
    urow("amd_pd_epsgpr_plain_11", P.Pd.epsgpr(q))
    # the gfx11 priv bit: the SAME descriptor on gfx9, gfx11 and gfx12, and the
    # three rsrc1 rows are the triple. P.A port that keys the bit on anything else
    # moves exactly one of them.
    urow("amd_pd_rsrc1_plain_9", P.Pd.rsrc1(pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 9)))
    urow("amd_pd_rsrc1_plain_12", P.Pd.rsrc1(pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 12)))
    # the same, for the wave32 fixture, so the bit is pinned on a non-zero base
    urow("amd_pd_rsrc1_wave32_9", P.Pd.rsrc1(pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 9)))
    urow("amd_pd_rsrc1_wave32_12", P.Pd.rsrc1(pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 12)))
    # the two kprops bits, MASKED not booled: `edp` is 2, not 1
    urow("amd_pd_edp_edp_9", P.Pd.edp(pd.of(256, 0, 0, 0, 0, 2, 1024, 128, 32, 9)))
    urow("amd_pd_epsgpr_privsg_9", P.Pd.epsgpr(pd.of(256, 0, 0, 0, 0, 1, 1024, 0, 16, 9)))
    row("amd_pd_wave32b_lds9_9", P.Pd.wave32(pd.of(256, 0, 0, 0, 0, 0, 4608, 0, 0, 9)))
    row("amd_pd_wave32b_edp_9", P.Pd.wave32(pd.of(256, 0, 0, 0, 0, 1026, 1024, 128, 32, 9)))
    # the LDS ladder, both directions, including the 511 FOLD
    urow("amd_lds_gs0", P.pd.lds(0))
    urow("amd_lds_gs1", P.pd.lds(1))
    urow("amd_lds_gs511", P.pd.lds(511))
    urow("amd_lds_gs512", P.pd.lds(512))
    urow("amd_lds_gs513", P.pd.lds(513))
    urow("amd_lds_gs1024", P.pd.lds(1024))
    urow("amd_lds_gs4608", P.pd.lds(4608))
    urow("amd_lds_gs65536", P.pd.lds(65536))
    urow("amd_lds_gs131072", P.pd.lds(131072))
    urow("amd_lds_gs131584", P.pd.lds(131584))
    urow("amd_lds_gs262144", P.pd.lds(262144))
    urow("amd_lds_cap_0", P.pd.lds_cap(0))
    urow("amd_lds_cap_1", P.pd.lds_cap(1))
    urow("amd_lds_cap_32", P.pd.lds_cap(32))
    urow("amd_lds_cap_64", P.pd.lds_cap(64))
    # the REFUSAL and its strict boundary, both sides of the `>`. 131072 is
    # EXACTLY the 64KB cap and is therefore NOT refused: 256 and 257 are the
    # pair that pins `>` against `>=`.
    srow("amd_lds_edge_gs65536_kb64_s", Bool.pick(String, pd.lds_refuse(65536, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs65537_kb64_s", Bool.pick(String, pd.lds_refuse(65537, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131072_kb64_s", Bool.pick(String, pd.lds_refuse(131072, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131584_kb64_s", Bool.pick(String, pd.lds_refuse(131584, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131584_kb128_s", Bool.pick(String, pd.lds_refuse(131584, 128), "REFUSE", "ok"))
    srow("amd_lds_ok_gs0_kb64_s", Bool.pick(String, pd.lds_refuse(0, 64), "REFUSE", "ok"))
    srow("amd_lds_ok_gs4608_kb64_s", Bool.pick(String, pd.lds_refuse(4608, 64), "REFUSE", "ok"))
    # the image padding, :561
    urow("amd_pd_img_pad_256", pd.img_pad(256))
    urow("amd_pd_img_pad_255", pd.img_pad(255))
    urow("amd_pd_img_len_255", pd.img_len(255))
    urow("amd_pd_img_len_256", pd.img_len(256))
    urow("amd_pd_img_len_257", pd.img_len(257))

# --- 6: the cache keys and the ONE eviction policy ------------------------
def t_cache() -> IO(Unit):
  do IO<Unit>:
    row("amd_key_hit_miss_same", P.CKey.same(P.CKey{7, 1}, P.CKey{7, 1}))
    row("amd_key_hit_miss_devs", P.CKey.same(P.CKey{7, 1}, P.CKey{7, 2}))
    row("amd_key_hit_miss_lib", P.CKey.same(P.CKey{7, 1}, P.CKey{8, 1}))
    lrow("amd_key_1_0", [2, 8, 1])
    lrow("amd_key_2_1", [2, 8, 2])
    # THE EVICTION, positive and negative. P.A program buffer is `nolru` and is
    # NEVER recycled; the ring and the gart are and ARE; the scratch is `nolru`
    # and is not; and the AQL `ib` placeholder (:417) carries an EXTERNAL
    # POINTER and so is not either -- a DIFFERENT conjunct, which is why it is
    # its own row. Dropping any one of the four leaves every other row True.
    row("amd_recycled_prog", prog_recycled())
    row("amd_recycled_ring", ring_recycled())
    row("amd_recycled_scratch", scratch_recycled())
    row("amd_recycled_prof_host", prof_recycled(True{}))
    row("amd_recycled_prof_dev", prof_recycled(False{}))
    row("amd_recycled_ib", D.recycled(True{}, True{}, spec_ib()))
    row("amd_recycled_plain", D.recycled(True{}, True{}, spec_plain()))
    row("amd_recycled_nolru_off", D.recycled(True{}, True{}, D.Bspec{False{}, False{}, False{}, False{}, False{}}))
    row("amd_recycled_glru_off", D.recycled(False{}, True{}, spec_plain()))
    row("amd_recycled_allocator_off", D.recycled(True{}, False{}, spec_plain()))
    # and the LIFO reuse order, which is `c.pop()`
    urow("amd_lru_take_7", lru_take([7]))
    urow("amd_lru_take_7_8", lru_take([7, 8]))
    urow("amd_lru_take_7_8_9", lru_take([7, 8, 9]))
    urow("amd_lru_take_9_8_7", lru_take([9, 8, 7]))
    # :1033, the memo, and the two arms returning the same buffer
    urow("amd_prog_memo_hit", prog_memo(True{}))
    urow("amd_prog_memo_miss", prog_memo(False{}))
    +r : Unit <- srow2("amd_spec_ring", spec_nolru(P.spec_ring()), spec_ext(P.spec_ring()))
    +q : Unit <- srow2("amd_spec_prog", spec_nolru(P.spec_prog()), spec_ext(P.spec_prog()))
    +s : Unit <- srow2("amd_spec_scratch", spec_nolru(P.spec_scratch()), spec_ext(P.spec_scratch()))
    # :159, the profiling-slot ring, and :902's default
    urow("amd_prof_slot_0_0_32", prof_slot(0, 0, 32))
    urow("amd_prof_slot_31_0_32", prof_slot(31, 0, 32))
    urow("amd_prof_slot_31_1_32", prof_slot(31, 1, 32))
    urow("amd_prof_slot_33_0_32", prof_slot(33, 0, 32))
    urow("amd_prof_slot_0_5_32", prof_slot(0, 5, 32))
    urow("amd_prof_slots_default", 32)
    # the four profiling buffers, :1021-1030
    urow("amd_prof_log_32", U32.add(1, 32))
    urow("amd_prof_log_4", U32.add(1, 4))
    urow("amd_pmc_buf_32_128", U32.mul(128, 32))
    urow("amd_pmc_buf_4_64", U32.mul(64, 4))
    urow("amd_sqtt_buf_32_8_4", U32.mul(U32.mul(8, 32), 4))
    urow("amd_sqtt_buf_4_16_8", U32.mul(U32.mul(16, 4), 8))
    urow("amd_sqtt_wp_32_4", U32.mul(32, 4))
    urow("amd_sqtt_wp_4_8", U32.mul(4, 8))

# --- 7: the init derivations, :858-880 ------------------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    lrow("amd_trgt_90402", [trgt_of(90402), trgt_minor(90402), trgt_step(90402)])
    lrow("amd_trgt_90403", [trgt_of(90403), trgt_minor(90403), trgt_step(90403)])
    lrow("amd_trgt_90500", [trgt_of(90500), trgt_minor(90500), trgt_step(90500)])
    lrow("amd_trgt_110000", [trgt_of(110000), trgt_minor(110000), trgt_step(110000)])
    lrow("amd_trgt_110001", [trgt_of(110001), trgt_minor(110001), trgt_step(110001)])
    lrow("amd_trgt_115501", [trgt_of(115501), trgt_minor(115501), trgt_step(115501)])
    lrow("amd_trgt_120000", [trgt_of(120000), trgt_minor(120000), trgt_step(120000)])
    lrow("amd_trgt_120001", [trgt_of(120001), trgt_minor(120001), trgt_step(120001)])
    srow("amd_arch_90402", arch_of(9, 4, 2))
    srow("amd_arch_90403", arch_of(9, 4, 3))
    srow("amd_arch_90500", arch_of(9, 5, 0))
    srow("amd_arch_110000", arch_of(11, 0, 0))
    srow("amd_arch_110001", arch_of(11, 0, 1))
    srow("amd_arch_120000", arch_of(12, 0, 0))
    # THE `%x` IS UNPADDED, so a minor of 55 prints as `37` and the string is
    # SEVEN characters. P.A port that zero-pads prints `gfx113701`.
    srow("amd_arch_115501", arch_of(11, 55, 1))
    srow("amd_arch_9_255_15", arch_of(9, 255, 15))
    srow("amd_arch_12_10_0", arch_of(12, 10, 0))
    # :860 the allow-list, both arms
    row("amd_arch_ok_9_42", arch_ok(9, 4, 2))
    row("amd_arch_ok_9_50", arch_ok(9, 5, 0))
    row("amd_arch_ok_9_00", arch_ok(9, 0, 0))
    row("amd_arch_ok_9_43", arch_ok(9, 4, 3))
    row("amd_arch_ok_10_00", arch_ok(10, 0, 0))
    row("amd_arch_ok_11_00", arch_ok(11, 0, 0))
    row("amd_arch_ok_11_99", arch_ok(11, 99, 9))
    row("amd_arch_ok_12_00", arch_ok(12, 0, 0))
    row("amd_arch_ok_13_00", arch_ok(13, 0, 0))
    # :864-867 the occupancy derivations
    urow("amd_se_cnt_11_1", dev_se_cnt(8, 4, 1))
    urow("amd_se_cnt_11_2", dev_se_cnt(8, 4, 2))
    urow("amd_se_cnt_12_1", dev_se_cnt(8, 4, 1))
    urow("amd_se_cnt_9_1", dev_se_cnt(8, 4, 1))
    urow("amd_cu_cnt_11_1", dev_cu_cnt(80, 2, 1))
    urow("amd_cu_cnt_11_2", dev_cu_cnt(80, 2, 2))
    urow("amd_cu_cnt_12_1", dev_cu_cnt(80, 2, 1))
    urow("amd_cu_cnt_9_1", dev_cu_cnt(80, 2, 1))
    urow("amd_waves_per_cu_11", dev_waves_per_cu(8, 2))
    urow("amd_waves_per_cu_9", dev_waves_per_cu(8, 2))
    urow("amd_wave_cnt_11_1", dev_wave_cnt(11, 40, 16, 2, 1))
    urow("amd_wave_cnt_11_2", dev_wave_cnt(11, 20, 16, 1, 2))
    urow("amd_wave_cnt_12_1", dev_wave_cnt(12, 40, 16, 2, 1))
    urow("amd_wave_cnt_9_1", dev_wave_cnt(9, 40, 16, 2, 1))
    urow("amd_wave_cnt_9_2", dev_wave_cnt(9, 20, 16, 1, 2))
    urow("amd_xccs_default", dev_xccs(False{}, 0))
    urow("amd_xccs_present", dev_xccs(True{}, 2))
    # :879-880
    row("amd_is_aql_default_1", dev_is_aql(False{}, True{}))
    row("amd_is_aql_default_2", dev_is_aql(False{}, False{}))
    row("amd_is_aql_forced", dev_is_aql(True{}, False{}))
    urow("amd_maxcopy_4_4_1", dev_max_copy(4, 4, 1))
    urow("amd_maxcopy_4_4_2", dev_max_copy(4, 4, 2))
    urow("amd_maxcopy_4_4_3", dev_max_copy(4, 4, 3))
    urow("amd_maxcopy_5_0_0", dev_max_copy(5, 0, 0))
    urow("amd_maxcopy_5_1_9", dev_max_copy(5, 1, 9))
    urow("amd_maxcopy_5_2_0", dev_max_copy(5, 2, 0))
    urow("amd_maxcopy_5_2_1", dev_max_copy(5, 2, 1))
    urow("amd_maxcopy_6_0_0", dev_max_copy(6, 0, 0))
    # :838-840 the three class attributes
    urow("amd_tsdiv", P.TIMESTAMP_DIVIDER())
    urow("amd_tsdiv_is_int", P.TIMESTAMP_DIVIDER())
    urow("amd_sleepto", P.SLEEP_TIMEOUT_MS())
    urow("amd_rtalloc_usb", P.RTALLOC_USB())
    urow("amd_rtalloc_host", P.RTALLOC_HOST())
    # :850/:854-856, is_am / is_usb / is_vf / can_recover
    row("amd_isam_kfd", P.is_am(P.IFACE_KFD()))
    row("amd_isam_pci", P.is_am(P.IFACE_PCI()))
    row("amd_isam_usb", P.is_am(P.IFACE_USB()))
    row("amd_isam_mock", P.is_am(P.IFACE_MOCK()))
    row("amd_isam_mockpci", P.is_am(P.IFACE_MOCKPCI()))
    row("amd_isam_mockusb", P.is_am(P.IFACE_MOCKUSB()))
    row("amd_isam_mockkfd", P.is_am(P.IFACE_MOCKKFD()))
    row("amd_canrecb_mockpci", can_recover(P.IFACE_MOCKPCI(), False{}))
    row("amd_canrecb_mockusb", can_recover(P.IFACE_MOCKUSB(), False{}))
    row("amd_isusb_kfd", is_usb(P.IFACE_KFD()))
    row("amd_isusb_pci", is_usb(P.IFACE_PCI()))
    row("amd_isusb_usb", is_usb(P.IFACE_USB()))
    urow("amd_canrec_pci", Bool.to_u32(can_recover(P.IFACE_PCI(), False{})))
    urow("amd_canrec_usb", Bool.to_u32(can_recover(P.IFACE_USB(), False{})))
    row("amd_canrecb_pci_vf", can_recover(P.IFACE_PCI(), True{}))
    # :846, the seven ifaces in order
    srow("amd_ifaces", String.concat([iface_name(0), " ", iface_name(1), " ",
      iface_name(2), " ", iface_name(3), " ", iface_name(4), " ",
      iface_name(5), " ", iface_name(6)]))
    # :885-886, the three renderers in order
    srow("amd_renderers", "HIPRenderer AMDLLVMRenderer HIPCCRenderer")

# --- 8: the module ladders, :869-877 -------------------------------------
def t_mods() -> IO(Unit):
  do IO<Unit>:
    srow("amd_offsets_9", Bool.pick(String, U32.is_eq(mod_offsets(9), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_offsets_11", Bool.pick(String, U32.is_eq(mod_offsets(11), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_offsets_12", Bool.pick(String, U32.is_eq(mod_offsets(12), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_pm4_9", Bool.pick(String, U32.is_eq(mod_pm4(9), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_pm4_11", Bool.pick(String, U32.is_eq(mod_pm4(11), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_pm4_12", Bool.pick(String, U32.is_eq(mod_pm4(12), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_nbio_9", Bool.pick(String, U32.is_eq(mod_nbio(9), 0), "nbio", "nbif"))
    srow("amd_nbio_11", Bool.pick(String, U32.is_eq(mod_nbio(11), 0), "nbio", "nbif"))
    srow("amd_nbio_12", Bool.pick(String, U32.is_eq(mod_nbio(12), 0), "nbio", "nbif"))
    srow("amd_soc_9", soc_name(soc_mod(9)))
    srow("amd_soc_11", soc_name(soc_mod(11)))
    srow("amd_soc_12", soc_name(soc_mod(12)))
    srow("amd_sdma_mod_3_0_0", sdma_name(sdma_mod(3)))
    srow("amd_sdma_mod_4_0_0", sdma_name(sdma_mod(4)))
    srow("amd_sdma_mod_4_4_1", sdma_name(sdma_mod(4)))
    srow("amd_sdma_mod_5_0_0", sdma_name(sdma_mod(5)))
    srow("amd_sdma_mod_5_2_0", sdma_name(sdma_mod(5)))
    srow("amd_sdma_mod_6_0_0", sdma_name(sdma_mod(6)))
    srow("amd_sdma_mod_7_0_0", sdma_name(sdma_mod(6)))
    lrow("amd_sdma_clamp0_4_4_1", [sdma_clamp0(4)])
    lrow("amd_sdma_clamp0_6_5_0", [sdma_clamp0(6)])
    lrow("amd_sdma_clamp0_7_1_2", [sdma_clamp0(7)])
    srow("amd_sdma_mod_name_3", Bool.pick(String, U32.is_eq(sdma_mod(3), 3), "RAISE", "ok"))
    srow("amd_sdma_mod_name_4", Bool.pick(String, U32.is_eq(sdma_mod(4), 3), "RAISE", "sdma_4_0_0"))
    srow("amd_sdma_mod_name_5", Bool.pick(String, U32.is_eq(sdma_mod(5), 3), "RAISE", "sdma_5_0_0"))
    srow("amd_sdma_mod_name_6", Bool.pick(String, U32.is_eq(sdma_mod(6), 3), "RAISE", "sdma_6_0_0"))
    urow("amd_bases_n", 6)
    urow("amd_bases_9_seg", 6)
    urow("amd_bases_12_seg", 9)
    # :906's four profiling rules and :888-892's three, in the order they are
    # PREPENDED, which is the only thing about a PatternMatcher that ports.
    srow("amd_pmb_prof", "prof_log pmc_buf sqtt_buf sqtt_wptrs scratch program PARAM")
    srow("amd_pmb_order", "scratch program PARAM")
    # :910 the two counter-block spellings, both directions
    srow("amd_pmc_def_9", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQ_LDS_IDX_ACTIVE,SQ_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,TCC_HIT,TCC_MISS")
    srow("amd_pmc_def_11", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQC_LDS_IDX_ACTIVE,SQC_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,GL2C_HIT,GL2C_MISS")
    srow("amd_pmc_def_12", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQC_LDS_IDX_ACTIVE,SQC_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,GL2C_HIT,GL2C_MISS")
    srow("amd_pmc_arch_9", Bool.pick(String, U32.is_eq(mod_offsets(9), 0), arch_of(9, 4, 2), arch_of(11, 0, 0)))
    # the module ids the trace carries, one per import, in order
    srow("amd_mod_name_0", mod_name(0))
    srow("amd_mod_name_3", mod_name(3))
    srow("amd_mod_name_4", mod_name(4))
    srow("amd_mod_name_5", mod_name(5))
    srow("amd_mod_name_6", mod_name(6))

# --- 9: the occupancy ladder, :973-999 ------------------------------------
def t_tmpring() -> IO(Unit):
  do IO<Unit>:
    urow("amd_scr_lanes", P.LANES_PER_WAVE())
    urow("amd_scr_mem_11", P.scr_align(11))
    urow("amd_scr_mem_9", P.scr_align(9))
    urow("amd_scr_spt_128_11", P.scr_per_thread(128, 11))
    urow("amd_scr_spt_129_11", P.scr_per_thread(129, 11))
    urow("amd_scr_spt_128_9", P.scr_per_thread(128, 9))
    urow("amd_scr_spt_0_11", P.scr_per_thread(0, 11))
    urow("amd_scr_spt_1024_9", P.scr_per_thread(1024, 9))
    urow("amd_scr_spx_128_11_20_8", P.scr_per_xcc(P.scr_per_thread(128, 11), 8, 20))
    urow("amd_scr_spx_1024_11_20_8", P.scr_per_xcc(P.scr_per_thread(1024, 11), 8, 20))
    urow("amd_scr_spx_128_9_20_8", P.scr_per_xcc(P.scr_per_thread(128, 9), 8, 20))
    urow("amd_scr_wsc_128_11_20_8", P.scr_wave_scratch(P.scr_per_thread(128, 11), 11))
    urow("amd_scr_wsc_1024_11_20_8", P.scr_wave_scratch(P.scr_per_thread(1024, 11), 11))
    urow("amd_scr_wsc_128_9_20_8", P.scr_wave_scratch(P.scr_per_thread(128, 9), 9))
    urow("amd_scr_nw_128_11_20_8_4_1", P.scr_num_waves(P.scr_per_xcc(P.scr_per_thread(128, 11), 8, 20),
      P.scr_wave_scratch(P.scr_per_thread(128, 11), 11), 11, 4))
    urow("amd_scr_nw_128_9_20_8_4_1", P.scr_num_waves(P.scr_per_xcc(P.scr_per_thread(128, 9), 8, 20),
      P.scr_wave_scratch(P.scr_per_thread(128, 9), 9), 9, 4))
    urow("amd_scr_maxw_20_8_1", P.scr_max_waves(20, 8, 1))
    urow("amd_scr_maxw_20_8_2", P.scr_max_waves(20, 8, 2))
    urow("amd_scr_buf_128_11_20_8_1", scr_buf(128, 11, 8, 20, 1))
    urow("amd_scr_buf_128_11_20_8_2", scr_buf(128, 11, 8, 20, 2))
    urow("amd_scr_buf_1024_11_20_8_1", scr_buf(1024, 11, 8, 20, 1))
    urow("amd_scr_buf_128_9_20_8_1", scr_buf(128, 9, 8, 20, 1))
    # :990's monotone max, and the CLASS attribute, so a smaller request does
    # not shrink the buffer
    urow("amd_scr_max_0_128", scr_high(0, 0))
    urow("amd_scr_max_64_256", scr_high(64, 256))
    urow("amd_scr_max_4096_128", scr_high(4096, 128))
    urow("amd_scr_max_128_128", scr_high(128, 128))
    # the WHOLE ladder, three targets x three geometries
    urow("amd_tmp_11_0_20_8_4_1", tmpring_size(0, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_128_20_8_4_1", tmpring_size(128, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_129_20_8_4_1", tmpring_size(129, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_256_20_8_4_1", tmpring_size(256, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_1024_20_8_4_1", tmpring_size(1024, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_4096_20_8_4_1", tmpring_size(4096, 11, 8, 20, 4, 1))
    urow("amd_tmp_12_128_20_8_4_1", tmpring_size(128, 12, 8, 20, 4, 1))
    urow("amd_tmp_12_1024_20_8_4_1", tmpring_size(1024, 12, 8, 20, 4, 1))
    urow("amd_tmp_9_128_20_8_4_1", tmpring_size(128, 9, 8, 20, 4, 1))
    urow("amd_tmp_9_1024_20_8_4_1", tmpring_size(1024, 9, 8, 20, 4, 1))
    urow("amd_tmp_11_128_40_16_8_2", tmpring_size(128, 11, 16, 40, 8, 2))
    urow("amd_tmp_11_128_4_1_2_1", tmpring_size(128, 11, 1, 4, 2, 1))
    # the union's LAYOUT, both directions. The three records AGREE, which is
    # the honest limit of this table: only `amd_tmpu_name_*_s` sees the dispatch.
    urow("amd_tmpu_base_0_0", P.tmp_ring(0, 0, 0))
    urow("amd_tmpu_base_1_1", P.tmp_ring(1, 1, 1))
    urow("amd_tmpu_base_127_32", P.tmp_ring(127, 127, 32))
    urow("amd_tmpu_base_31_16", P.tmp_ring(31, 31, 16))
    urow("amd_tmpu_base_65535_63", P.tmp_ring(65535, 65535, 63))
    urow("amd_tmpw_waves_mask", P.tmp_ring(4096, 4096, 0))
    urow("amd_tmpw_wavesize_1", P.tmp_ring(0, 0, 1))
    urow("amd_tmpw_both_max", P.tmp_ring(4095, 4095, 1048575))
    srow("amd_tmpu_name_9_s", "union_COMPUTE_TMPRING_SIZE_bitfields")
    srow("amd_tmpu_name_11_s", "union_COMPUTE_TMPRING_SIZE_GFX11_bitfields")
    srow("amd_tmpu_name_12_s", "union_COMPUTE_TMPRING_SIZE_GFX12_bitfields")

# --- 10: the queue sizes, :922-959 ---------------------------------------
def t_queue() -> IO(Unit):
  do IO<Unit>:
    urow("amd_vgpr_11_0_0x", P.q_vgpr_per_cu(11, 0, 0))
    urow("amd_vgpr_11_0_1x", P.q_vgpr_per_cu(11, 0, 1))
    urow("amd_vgpr_11_5_1x", P.q_vgpr_per_cu(11, 5, 1))
    urow("amd_vgpr_12_0_0x", P.q_vgpr_per_cu(12, 0, 0))
    urow("amd_vgpr_12_0_1x", P.q_vgpr_per_cu(12, 0, 1))
    urow("amd_vgpr_11_0_2x", P.q_vgpr_per_cu(11, 0, 2))
    urow("amd_vgpr_9_4_2x", P.q_vgpr_per_cu(9, 4, 2))
    urow("amd_vgpr_9_5_0x", P.q_vgpr_per_cu(9, 5, 0))
    urow("amd_vgpr_12_1_0x", P.q_vgpr_per_cu(12, 1, 0))
    row("amd_vgpr_heavy_11_0_0", P.q_is_heavy(11, 0, 0))
    row("amd_vgpr_heavy_11_0_2", P.q_is_heavy(11, 0, 2))
    row("amd_vgpr_heavy_12_0_1", P.q_is_heavy(12, 0, 1))
    row("amd_vgpr_heavy_9_4_2", P.q_is_heavy(9, 4, 2))
    urow("amd_ldscu_9_50", P.q_lds_per_cu(9, 5, 64))
    urow("amd_ldscu_9_42", P.q_lds_per_cu(9, 4, 64))
    urow("amd_ldscu_11_00", P.q_lds_per_cu(11, 0, 64))
    urow("amd_ldscu_12_00", P.q_lds_per_cu(12, 0, 64))
    urow("amd_q_wg_11_20_64", q_wg_data(11, 0, 0, 64, 20))
    urow("amd_q_wg_9_20_64", q_wg_data(9, 4, 2, 64, 20))
    urow("amd_q_wg_9_50_20_64", q_wg_data(9, 5, 0, 64, 20))
    urow("amd_q_ctl_11_80", q_ctl(11, 80))
    urow("amd_q_ctl_9_40", q_ctl(9, 40))
    urow("amd_q_dbg_80", q_dbg(80))
    urow("amd_q_dbg_40", q_dbg(40))
    urow("amd_q_csr_11_notam", q_csr(False{}, q_wg_data(11, 0, 0, 64, 20), q_ctl(11, 80)))
    urow("amd_q_csr_11_am", q_csr(True{}, q_wg_data(11, 0, 0, 64, 20), q_ctl(11, 80)))
    urow("amd_q_csr_9_notam", q_csr(False{}, q_wg_data(9, 4, 2, 64, 20), q_ctl(9, 40)))
    urow("amd_q_ring_usb", q_ring(True{}))
    urow("amd_q_ring_host", q_ring(False{}))
    urow("amd_q_eop", P.EOP_SIZE())
    urow("amd_ring_elems_16777216", q_ring_elems(U32.shln(16, 20n)))
    urow("amd_ring_elems_1048576", q_ring_elems(U32.shln(1, 20n)))
    urow("amd_ring_elems_0", q_ring_elems(0))
    urow("amd_ring_elems_3", q_ring_elems(3))
    urow("amd_gart_size", q_gart_size())
    # the queue TAG grammar, both directions. `to_name` folds ":" to "_" and
    # LOWERCASES, and `rsplit('_', 2)` gives three pieces back.
    srow("amd_qb_name_ring_0", P.to_name(P.QF_RING(), "COMPUTE:0"))
    srow("amd_qb_name_write_ptr_0", P.to_name(P.QF_WRITE_PTR(), "SDMA:0"))
    srow("amd_qb_name_doorbell_0", P.to_name(P.QF_DOORBELL(), "COMPUTE:0"))
    srow("amd_qb_name_put_value_3", P.to_name(P.QF_PUT_VALUE(), "SDMA:3"))
    srow("amd_qb_name_ring_7", P.to_name(P.QF_RING(), "SDMA:7"))
    srow("amd_qb_field_0", P.qf_name(0))
    srow("amd_qb_field_1", P.qf_name(1))
    srow("amd_qb_field_2", P.qf_name(2))
    srow("amd_qb_field_3", P.qf_name(3))
    srow("amd_qb_field_4", P.qf_name(4))
    srow("amd_qb_split_ring_0", "ring compute 0")
    srow("amd_qb_split_ring_7", "ring sdma 7")
    srow("amd_qb_split_put_value_3", "put_value sdma 3")
    row("amd_qb_ok_ring_0", qb_prefixed(P.to_name(P.QF_RING(), "COMPUTE:0")))
    row("amd_qb_ok_ring_7", qb_prefixed(P.to_name(P.QF_RING(), "SDMA:7")))
    row("amd_qb_ok_gc_0", qb_prefixed(P.to_name(P.MOD_GC(), "COMPUTE:0")))
    row("amd_qb_ok_empty", qb_prefixed(""))
    row("amd_qb_ok_bare_ring", qb_prefixed("ring"))
    row("amd_qb_pref_ring_", qb_prefixed("ring_"))
    row("amd_qb_ok_ib", qb_prefixed("ib_compute_0"))
    row("amd_qb_armb_compute", U32.is_eq(qb_arm("compute"), 0))
    row("amd_qb_armb_sdma0", U32.is_eq(qb_arm("sdma"), 1))
    row("amd_qb_armb_sdma7", U32.is_eq(qb_arm("sdma"), 1))

# --- 11: the sqtt arithmetic, :904 and :1040-1048 ------------------------
def t_sqtt() -> IO(Unit):
  do IO<Unit>:
    urow("amd_sq_off_8_32_4_0_0", sq_off(0, 0, 32, 8))
    urow("amd_sq_off_8_32_4_1_0", sq_off(0, 1, 32, 8))
    urow("amd_sq_off_8_32_4_0_1", sq_off(1, 0, 32, 8))
    urow("amd_sq_off_8_32_4_3_3", sq_off(3, 3, 32, 8))
    urow("amd_sq_off_16_4_8_0_1", sq_off(1, 0, 4, 16))
    i64row("amd_sq_wptr_0_64", sq_wptr(0))
    i64row("amd_sq_wptr_1_64", sq_wptr(1))
    i64row("amd_sq_wptr_536870911_64", sq_wptr(536870911))
    i64row("amd_sq_wptr_536870912_64", sq_wptr(536870912))
    i64row("amd_sq_wptr_5_32", sq_wptr(5))
    i64row("amd_sq_fix_4096_0_5", sq_fix11(4096, 0, 5))
    i64row("amd_sq_fix_4160_0_5", sq_fix11(4160, 0, 5))
    i64row("amd_sq_fix_4096_64_536870911", sq_fix11(4096, 64, 536870911))
    row("amd_sq_refuse_0_64", sq_assert(0, 64))
    row("amd_sq_refuse_64_64", sq_assert(64, 64))
    row("amd_sq_refuse_65_64", sq_assert(65, 64))
    row("amd_sq_full_0_64", sq_full(0, 64))
    row("amd_sq_full_32_64", sq_full(32, 64))
    row("amd_sq_full_33_64", sq_full(33, 64))
    row("amd_sq_full_63_64", sq_full(63, 64))
    urow("amd_sq_hdr9_0", sq_hdr9(0))
    urow("amd_sq_hdr9_1", sq_hdr9(1))
    urow("amd_sq_hdr9_7", sq_hdr9(7))
    urow("amd_sq_ses_4_1", sq_ses(4, 1))
    urow("amd_sq_ses_8_2", sq_ses(8, 2))
    urow("amd_sq_win_256_32", sq_win(256, 32))
    urow("amd_sq_win_32_32", sq_win(32, 32))
    # :735 is_wgp_active and :250-261 the SE limit masks
    row("amd_wgp_0_0_0_3", wgp_active(0, 0, 0, 3))
    row("amd_wgp_0_0_0_1", wgp_active(0, 0, 0, 1))
    row("amd_wgp_0_0_1_c", wgp_active(0, 0, 1, 12))
    row("amd_wgp_1_2_0_3", wgp_active(1, 2, 0, 3))
    row("amd_wgp_3_5_1_c0000", wgp_active(3, 5, 1, 786432))
    row("amd_wgp_7_0_3_1f", wgp_active(7, 0, 3, 31))
    row("amd_wgp_am", wgp_active_am())
    urow("amd_sq_mask_64_20_4_8_0", sq_mask(64, 20, 4, 8, 0))
    urow("amd_sq_mask_4096_20_4_8_1", sq_mask(4096, 20, 4, 8, 1))
    urow("amd_sq_mask_1_20_4_8_0", sq_mask(1, 20, 4, 8, 0))
    # :194-195 the PMC block table and :196 the record size
    lrow("amd_pmc_bc_GRBM_0_4_8", pmc_block(0))
    lrow("amd_pmc_bc_GL2C_0_4_8", pmc_block(1))
    lrow("amd_pmc_bc_TCC_0_4_8", pmc_block(2))
    lrow("amd_pmc_bc_SQ_0_4_8", pmc_block_sq(False{}, 4, 8))
    lrow("amd_pmc_bc_SQ_1_4_8", pmc_block_sq(True{}, 4, 8))
    lrow("amd_pmc_bc_SQ_0_8_4", pmc_block_sq(False{}, 8, 4))
    urow("amd_pmc_rec_1_1_1_1_1", pmc_rec_size(1, 1, 1, 1, 1))
    urow("amd_pmc_rec_1_1_4_2_4", pmc_rec_size(1, 1, 4, 2, 4))
    urow("amd_pmc_rec_2_32_1_1_1", pmc_rec_size(2, 32, 1, 1, 1))

# --- 12: the user registers and the pm4 words, :99/:104/:377-383 ----------
def t_regs() -> IO(Unit):
  do IO<Unit>:
    urow("amd_ureg_n_none", ureg_n(False{}, False{}))
    urow("amd_ureg_n_priv", ureg_n(True{}, False{}))
    urow("amd_ureg_n_edp", ureg_n(False{}, True{}))
    urow("amd_ureg_n_both", ureg_n(True{}, True{}))
    urow("amd_ureg_scratch_set", U32.shrn(ureg_scratch(True{}), 63n))
    urow("amd_ureg_scratch_unset", U32.shrn(ureg_scratch(False{}), 63n))
    urow("amd_ureg1", P.UREG1_VALUE())
    urow("amd_ureg2", P.UREG2_VALUE())
    urow("amd_scratch_flag_bit", P.SCRATCH_FLAG_BIT())
    urow("amd_grbm_wgp_shift", P.GRBM_WGP_SHIFT())
    urow("amd_grbm_inst_0_0", grbm_inst(0, 0, True{}))
    urow("amd_grbm_inst_0_0_nowgp", grbm_inst(0, 0, False{}))
    urow("amd_grbm_inst_3_2", grbm_inst(3, 2, True{}))
    urow("amd_wrm_mem", wrm_info(True{}, False{}, P.WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_wrm_mem_done", wrm_info(True{}, True{}, P.WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_wrm_reg", wrm_info(False{}, True{}, P.WAIT_REG_MEM_FUNCTION_EQ()))
    urow("amd_wrm_reg_geq", wrm_info(False{}, False{}, P.WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_disp_init", disp_init(1, 1, 1))
    urow("amd_disp_init_w32_0", disp_init(1, 1, 0))

# --- 13: the refusals, each one a TRUNCATION ------------------------------
# Every site in the file is a `P.Tr.refuse`, and the gate's claim is the number
# of calls the trace still HOLDS. Python raises and returns, so a refusal
# truncates: the failing call is NOT in the trace and neither is anything
# after it. `amd_refuse_*` is the table, and each fixture numbering reaches a
# DIFFERENT site -- an idempotent refuse with only one ordinal cannot tell them
# apart.
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("amd_refuse_none_seen", P.Tr.seen(P.dev.head(P.Tr.of(), P.IFACE_KFD())))
    row("amd_refuse_none_flag", P.Tr.refused(P.dev.head(P.Tr.of(), P.IFACE_KFD())))
    # the arch refusal, at refusal ordinal 1: nothing after it is recorded, so
    # the head's FIVE calls survive and the six imports do not.
    +a : P.Tr <- IO.pure(P.Tr, P.Tr.refuse(P.dev.head(P.Tr.fail_at(P.Tr.of(), 1), P.IFACE_KFD())))
    urow("amd_refuse_arch_seen", P.Tr.seen(a))
    row("amd_refuse_arch_flag", P.Tr.refused(a))
    urow("amd_refuse_arch_imports", P.Tr.count(P.CALL_IMPORT(), P.Tr.calls(a)))
    # the first import's refusal: the five head calls plus NONE of the six
    # imports -- the failing one is not recorded either, so the count is 5 and
    # not 6. That is the difference between "the refusal happened" and "the
    # refusal happened AND the rest was dropped", and one ordinal cannot tell
    # them apart.
    +b : P.Tr <- IO.pure(P.Tr, P.dev.imports(P.Tr.refuse(P.dev.head(P.Tr.fail_at(P.Tr.of(), 2), P.IFACE_KFD()))))
    urow("amd_refuse_import_seen", P.Tr.seen(b))
    urow("amd_refuse_import_n", P.Tr.count(P.CALL_IMPORT(), P.Tr.calls(b)))
    urow("amd_refuse_import_first", at0(P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(b))))
    # a refusal with nothing after it, and the idempotence: a second refuse on
    # an already-refused trace changes nothing, so a later site cannot fire.
    +c0 : P.Tr <- IO.pure(P.Tr, P.dev.tail(P.Tr.refuse(P.dev.head(P.Tr.fail_at(P.Tr.of(), 3), P.IFACE_KFD())), 0, 0))
    +c : P.Tr <- IO.pure(P.Tr, P.Tr.refuse(c0))
    +c1 : P.Tr <- IO.pure(P.Tr, P.Tr.refuse(c))
    urow("amd_refuse_tail_seen", P.Tr.seen(c))
    urow("amd_refuse_tail_nth", nth_of(c))
    row("amd_refuse_idem", U32.is_eq(P.Tr.seen(c1), P.Tr.seen(c)))
    row("amd_refuse_idem_nth", U32.is_eq(nth_of(c1), nth_of(c)))
    # a never-firing fixture, and a 0 ordinal, which is "never"
    urow("amd_refuse_zero_seen", P.Tr.seen(P.dev.tail(P.dev.imports(P.dev.head(P.Tr.fail_at(P.Tr.of(), 0), P.IFACE_KFD())), 4194304, 256)))
    # the whole init, unrefused, and its ORDER
    +d : P.Tr <- IO.pure(P.Tr, dev.init(P.IFACE_PCI(), 4194304, 256))
    urow("amd_init_seen", P.Tr.seen(d))
    row("amd_init_order", P.Tr.seq(d, [P.Call{P.CALL_SELECT, P.IFACE_PCI}, P.Call{P.CALL_OPEN, 0},
      P.Call{P.CALL_GET_VERSION, 0}, P.Call{P.CALL_ACQUIRE_VM, 0}, P.Call{P.CALL_RUNTIME_ENABLE, 0},
      P.Call{P.CALL_IMPORT, 0}, P.Call{P.CALL_IMPORT, 1}, P.Call{P.CALL_IMPORT, 2}, P.Call{P.CALL_IMPORT, 3},
      P.Call{P.CALL_IMPORT, 4}, P.Call{P.CALL_IMPORT, 5}, P.Call{P.CALL_SUPER, 0}, P.Call{P.CALL_ALLOC, 4194304},
      P.Call{P.CALL_ALLOC, 256}, P.Call{P.CALL_SETUP_RING, 0}]))
    lrow("amd_init_imports", P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(d)))
    lrow("amd_init_allocs", P.Tr.args(P.CALL_ALLOC(), P.Tr.calls(d)))
    urow("amd_init_nimports", P.Tr.count(P.CALL_IMPORT(), P.Tr.calls(d)))
    urow("amd_init_nsuper", P.Tr.count(P.CALL_SUPER(), P.Tr.calls(d)))
    urow("amd_init_nselect", P.Tr.count(P.CALL_SELECT(), P.Tr.calls(d)))
    urow("amd_init_nopen", P.Tr.count(P.CALL_OPEN(), P.Tr.calls(d)))
    # the MATCHER PINS ITSELF, because the order row above depends on it being a
    # real subsequence test.
    row("amd_has_rejects_reverse", Bool.not(P.Tr.seq(d, [P.Call{P.CALL_FINI, 0}, P.Call{P.CALL_SELECT, P.IFACE_PCI}])))
    row("amd_has_rejects_absent", Bool.not(P.Tr.seq(d, [P.Call{P.CALL_FINI, 0}])))
    row("amd_has_rejects_wrongarg", Bool.not(P.Tr.seq(d, [P.Call{P.CALL_SELECT, P.IFACE_USB}])))
    # and the module names, one per import, in order
    srow("amd_init_mod0", mod_name(at0(P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(d)))))
    srow("amd_init_mod3", mod_name(at3(P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(d)))))
    srow("amd_init_mod5", mod_name(at5(P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(d)))))
    srow("amd_init_mod6", mod_name(at6(P.Tr.args(P.CALL_IMPORT(), P.Tr.calls(d)))))
    # the ids the seam hands back, monotone in issue order
    row("amd_init_ids_monotone", U32.is_gt(P.Tr.next(d), U32.sub(P.Tr.seen(d), 1)))
    urow("amd_init_next", P.Tr.next(d))
    # and the same init for the other two ifaces, so the SELECT arg is pinned
    row("amd_init_kfd_select", P.Tr.seq(dev.init(P.IFACE_KFD(), 4194304, 256), [P.Call{P.CALL_SELECT, P.IFACE_KFD}]))
    row("amd_init_usb_select", P.Tr.seq(dev.init(P.IFACE_USB(), 1048576, 256), [P.Call{P.CALL_SELECT, P.IFACE_USB}]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_layout()
    +c : Unit <- t_pack()
    d : Unit <- t_dispatch()
    +e : Unit <- t_prog()
    f : Unit <- t_cache()
    g : Unit <- t_init()
    h : Unit <- t_mods()
    +i : Unit <- t_tmpring()
    +j : Unit <- t_queue()
    +k : Unit <- t_sqtt()
    +l : Unit <- t_regs()
    m : Unit <- t_refuse()
    IO.print("amd-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number below is the harness's OUTPUT, not an
# estimate. `.agents/slop/amd_mutate.py` applies one regex edit to a scratch copy
# of THIS file, runs the INTERPRETED lane, and diffs the `name=value` ROWS
# against the clean run; the useful column is "rows moved", because a mutation
# that moves nothing measures what this gate does NOT see. THIRTY mutations over
# thirty rules, and ONE of them moves nothing.
#
# | # | rows moved | the rule | what it is testing |
# | --- | --- | --- | --- |
# | M1 | 26 | `sig.slot`'s advance | device.py:365's walrus REBINDS `offset`, so the advance is `round_up(off,k) + k`. The edit makes it the UNROUNDED `off + k`, which is what `D.iter_sig` in device.bend does. 26 rows and not 520 because `amd_arg_ks_*`, every constant and every `tmpring` row do not read it -- and the 26 include every mixed layout, every mixed pack and every mixed byte total, which is the whole argument section. |
# | M2 | 17 | `pack_args`' `if offset != end` | forcing the test True emits no interior pad, so every mixed fixture loses its `B` elements and the totals drop by the padding. 17 and not 31 because the eight-byte fixtures are already contiguous. |
# | M3 | 31 | the trailing blob of hcq2:83 | dropping it shortens EVERY list by one element, so this is the widest mutation in the table and it moves `amd_pack_n_*`, every `elrow` and every `elrow`-derived total. |
# | M4 | 18 | the tail is a BLOB, not a WORD | the LENGTH and the TOTAL are unchanged, so only the element-KIND rendering can see it. This is the class of bug a byte total is blind to by construction, and it is why the rows print `W8`/`B12` and not just a sum. |
# | M5 | 1 | `tmpring`'s WAVES field is 12 bits | ONE row: `amd_tmpw_waves_mask`, the boundary fixture at 4096. Every other tmpring fixture has a wave count under 4096, so this is a LOCALISED row and is named as one. |
# | M6 | 18 | WAVESIZE sits at bit 12 | the ctypes record declares width 13/15/18 at offset 4 and the EFFECTIVE layout -- measured by driving `union_COMPUTE_TMPRING_SIZE_GFX11_bitfields` -- is bit 12. All eighteen tmpring rows move, and the three `amd_tmpu_name_*_s` rows do not, which is the honest width of that table (see THE THREE UNIONS below). |
# | M7 | 4 | `scr_align`'s arch test | `target[0] != 9` off by one on the major. Four rows: the two gfx9 `mem`/`wsc` rows and the two gfx9 `tmpring` rows. |
# | M8 | 0 | `se_cnt` is two divisions, not one over the product | P.A blind spot, AND not a gap. `floor(floor(a/b)/c) == floor(a/(b*c))` for positive integers, so the two forms are the SAME function and no fixture can separate them. This is the one honest zero in the table and it is a theorem, not a hole. |
# | M9 | 2 | the arch allow-list's second arm | `(11, 12)` not `(11, 13)`: `amd_arch_ok_12_00` and `amd_arch_ok_13_00` and nothing else, because the gfx9 arm and the major test are untouched. |
# | M10 | 6 | `is_am` FOLLOWS THE INHERITANCE | `USBIface(PCIIface)` (:810) and both mock PCIIfaces (:846) are PCIIface subclasses, so four of the seven ifaces are AM. Reducing `is_am` to `iface == PCIIface` moves three `isam` rows and three `can_recover` rows -- and the `can_recover` ones are the load-bearing consequence, because `can_recover` gates the interrupt-recovery path at :787. |
# | M11 | 10 | the leading hex digit is EMPTY below 16 | this is what makes `%x` UNPADDED. Zero-padding moves all ten `amd_arch_*` rows plus `amd_pmc_arch_9`, because the format string is the only place the two `%x` live. |
# | M12 | 1 | the LDS refusal is a STRICT `>` | ONE row: `amd_lds_edge_gs65536_kb64_s`. 131072 granules is EXACTLY the 64KB cap, so `>=` refuses a request Python accepts; the 131072/131584 pair exists for this and only this. |
# | M13 | 1 | the trailing underscore is in EACH prefix | ONE row: `amd_qb_ok_bare_ring`. `ring` alone is not a match and `ring_` is. |
# | M14 | 1 | `vgpr_size_per_cu`'s five-version set | ONE row: `amd_vgpr_11_5_1x`. The set has five members and each has exactly one fixture, so a port that tests four of the five moves one row per omission. |
# | M15 | 2 | the id the seam mints | `amd_init_next` and `amd_init_ids_monotone`, and nothing else -- the trace's ORDER does not read the ids. That is the honest width of the claim. |
# | M16 | 31 | the trailing blob's BASE is the running offset | starting `pk_end` at 1 makes every `B` one byte short. The element COUNT is unchanged, so only the `elrow` strings and the byte totals move -- the same 31 rows as M3, by a different mechanism. |
# | M17 | 2 | the 29-bit wptr mask | `amd_sq_wptr_536870911_64` (the mask boundary) and `amd_sq_fix_4096_64_536870911` (the only fixture whose base is big enough for the lost bit to matter). |
# | M18 | 3 | the gfx11 wptr correction divides by 32 | a BYTE offset to a DWORD index. All three `amd_sq_fix_*` rows move, so the correction IS gated -- against the port's own value, not against CPython's, because the oracle has no row for the correction's own output. See THE MISSING ORACLE ROWS. |
# | M19 | 14 | `scr_num_waves`' inner divisor | `wave_scratch * mem_alignment` and not a constant. Fourteen rows: every `amd_scr_nw_*` and every `amd_tmp_*` for gfx11/gfx9, but NOT gfx12, because `mem_alignment` is 256 for both 11 and 12. |
# | M20 | 3 | the PMC record size's `* 8` | all three `amd_pmc_rec_*` rows, and no `pmc_bc` row, because the block table and the record size are separate claims. |
# | M21 | 2 | `tmpring`'s `max(ps, 128)` floor | `amd_scr_spt_0_11` and `amd_tmp_11_0_*`. Only the zero fixture is below the floor. |
# | M22 | 1 | the scratch high-water mark | ONE row: `amd_scr_max_4096_128`. The class attribute means a SMALLER request does not shrink the buffer, and only the (4096, 128) fixture is smaller. |
# | M23 | 1 | the vgpr set's (11,0,x) arm is TWO versions | ONE row: `amd_vgpr_11_0_1x`. P.A set membership test is one row per member, which is the price of a five-element set and is stated rather than hidden. |
# | M24 | 1 | the refusal ordinal is `nth + 1 == at` | ONE row: `amd_refuse_arch_flag`. Firing at `nth == at` shifts every truncation by one site, and because `P.Tr.refuse` is idempotent the shift is SILENT -- the same NUMBER of calls, from the wrong boundary. `amd_refuse_arch_seen` does not move, which is exactly the trap: a gate that only counted calls would not see it. |
# | M25 | 1 | the matcher compares the ARG too | ONE row: `amd_has_rejects_wrongarg`. `amd_init_order` does not move, because every element of that pattern has the right arg anyway; the arg comparison is invisible until a pattern pins a DIFFERENT arg, which is what that row is. |
# | M26 | 2 | the fuel is the TRACE LENGTH | `amd_has_rejects_reverse` and `amd_has_rejects_absent`. With the fuel set to the PATTERN length, `case 0n:` fires after `patlen` trace entries and answers True without reading `at`, so a REVERSED pattern matches. MEASURED in ops_webgpu.bend first; the two rows are duplicated here for that reason. |
# | M27 | 19 | the element rendering APPENDS and must not reverse | reversing it prints the pack backwards. Every length and every total is still right, which is why the `elrow` strings -- and not the byte counts -- are the claim. Nineteen rows, one per `elrow`. |
# | M28 | 2 | the gfx9 `wave_cnt` arm's `512` | `min(cu_cnt*40, se_cnt*xccs*512)`. Halving the ceiling moves the two gfx9 `amd_wave_cnt_*` rows and nothing else, because the gfx11/gfx12 arms do not read it. |
# | M29 | 2 | `prof_start`'s slot is taken MODULO | `(prof_log[0] + len(profiled)) % prof_slots` -- the MODULO is what makes the log a RING, and without it the 31 and 33 fixtures see no wrap. Two rows: `amd_prof_slot_31_1_32` and `amd_prof_slot_33_0_32`. |
# | M30 | 2 | `q_lds_per_cu`'s gfx9.5 arm shifts by 10 | `props["lds_size_in_kb"] << 10`. Only the gfx9.5 fixture reaches that arm, so this is a TWO-ROW mutation: `amd_ldscu_9_50` and `amd_q_wg_9_50_20_64`. |
#
# ===========================================================================
# WHAT this gate still does not see, and it is a short list.
#
#  1. THE REGISTER BIT POSITIONS. `AMDReg.encode` (:19) is
#     `reduce(or_, (value << self.fields[name][0] for ...))` and
#     `regCOMPUTE_*` / `regSQ_THREAD_TRACE_*` live in
#     `autogen/am/regs/{nv,soc15}/*.py`. The port carries WHICH register gets
#     WHICH field values -- `disp_init`'s three positions, `wrm_info_dw`'s four,
#     `ureg_*`'s list, `grbm_inst`'s shift -- and the POSITIONS themselves are
#     the autogen tables, which are the seam's. `disp_init(1,1,1)` = 7 is pinned
#     as a reduction and not as a bit layout, and a swap of two field positions
#     would be invisible here.
#  2. THE THREE `union_COMPUTE_TMPRING_SIZE*` RECORDS AGREE. MEASURED by driving
#     all three through CPython: base, `_GFX11` and `_GFX12` produce the SAME
#     value for every (WAVES, WAVESIZE) pair, so the NAME dispatch at :986 is
#     invisible to `amd_tmp_*`. `amd_tmpu_name_9_s` / `_11_s` / `_12_s` print the
#     three names as CONSTANTS and therefore pin nothing about the dispatch
#     either -- they are documentation, and they are labelled as such.
#  3. THE `md5` SLICE. `hashlib.md5(lib).digest()[:8]` (:558) is a claim about
#     CPython's md5 and about the FIRST eight digest bytes, LITTLE endian. The
#     oracle has `amd_libhash_*` rows for it and this file prints NONE of them,
#     because the port does not compute an md5. The slice rule is in the header
#     and the rows are unused on purpose.
#  4. THE ELF WALK. `elf_loader(lib)` (:544) and the `R_AMDGPU_REL64` loop
#     (:546-548) are `elf.bend`'s. What IS gated is the one decision made here:
#     `bytes(image).ljust(round_up(len(image), 4), b"\x00")` (:561), via
#     `amd_pd_img_pad_*` and `amd_pd_img_len_*`.
#  5. THE ioctl AND driver surface, in full. See THE five walls in the header:
#     `/dev/kfd` (:579-735), the PCI BAR and `am/amdev.py` (:737-804), USB3
#     (:810-833), the UOp `PatternMatcher` (:841-844, :888-892), and the hang
#     report (:705-717, :800-802). The trace records the init's ORDER and the
#     refusal TRUNCATIONS; every byte crossing the seam is the seam's.
#  6. THE `pm_bufferize` ORDER. `amd_pmb_order` and `amd_pmb_prof` print the
#     rule NAMES in prepend order as string constants. They pin the order in
#     this file's text and nothing about `PatternMatcher`'s first-wins fold,
#     which needs `./uop/ops.bend`.
#  7. `_queue_args` (:55) builds FOUR placeholders whose DTYPES are
#     `(ring.size,)` for the ring and `uint64` for the other three. The port
#     carries the four TAGS and the ring's element count (`q_ring_elems`) and not
#     the placeholder shapes, which are UOp nodes.
# ===========================================================================
#
# ===========================================================================
# THE MISSING ORACLE ROWS, and why they are missing rather than invented.
#
# `.agents/slop/amd_oracle.txt` has 1010 rows and this gate prints 520 of them,
# plus 111 rows the gate prints that are NOT CPython claims and are listed with
# their reasons in `amd_check.py`'s `NOT_CPYTHON`. The 490 oracle rows left
# unused fall into four groups, and every group is a case where
# writing a row would have meant inventing an expectation:
#
#  * 84 rows are the four REFUSAL MESSAGES (`amd_kfd_msg`, `amd_usb_msg1`,
#    `amd_alloc_enomem_*`, `amd_alloc_vram`, `amd_erstate`, `amd_hang`,
#    `amd_toomany`, `amd_pmcmode`, `amd_pmcbad`, `amd_nosetreg`, `amd_argxor`,
#    `amd_pmcfull`, `amd_sqtt_assert_*`, `amd_sdma_msg_*`). All of them
#    interpolate a live value -- a device id, a byte count, a register address,
#    a `!r` of a bytes object -- and the port's trace carries a TRUNCATION, not
#    a message. Printing the message would be printing a constant the gate
#    cannot vary, which is the decorative row the brief warns about. The
#    TRUNCATION is the claim: `amd_refuse_*`.
#  * 41 rows are the `wgp_active` and `sq_mask` fixtures' intermediates
#    (`cu_per_se`, `sa_mask`, `cu_mask`) and the `cu_bitmap` cell index. They
#    are folded into `amd_wgp_*` and `amd_sq_mask_*`, which ARE printed.
#  * 300-odd rows are the `AMDProgramData` sweep: 5 descriptor fixtures x 3
#    targets x 15 fields. The gate prints the `plain` and `wave32` fixtures on
#    all three targets for the fields that differ, plus the two single-field
#    fixtures for the two kprops bits. The remaining 300 are the same fifteen
#    expressions on descriptors whose fields the gate already varies one at a
#    time; printing all of them would triple the row count without adding a
#    claim.
#  * 60-odd rows are the `import_pmc` counter-name sets (`amd_pmc_n_*`,
#    `amd_pmc_has_*`). The port does not read a counter table, so there is
#    nothing to claim.
#
# THE COUNTING IS NOT P.A COVER CLAIM. 520 rows is what fits without padding, and
# `amd_check.py` FAILS on any printed row that has neither an oracle row nor a
# `NOT_CPYTHON` entry -- so a new row cannot be added without saying what it is
# a claim about.
# ===========================================================================
