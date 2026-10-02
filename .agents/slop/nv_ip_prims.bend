# ===========================================================================
# STAGE C -- THE ALLOCATOR ARITHMETIC.
#
# tinygrad's `round_up` / `round_down` / `ceildiv` are three defs here and they
# are the SAME three expressions Python uses, so a row can be wrong about the
# arithmetic and not only about the order of the calls. `nv_ip_oracle.py` asserts
# its own copies against `tinygrad.helpers` at five probes before it computes
# anything, which is what makes `ip_ru_*` and `ip_rd_*` a real cross-check
# rather than a transcription compared with itself.
# ===========================================================================

# THE DIVISION FORM, not the bit trick. `(x + m - 1) & ~(m - 1)` is the textbook
# round_up and it is WRONG for a non-power-of-two `m`: `round_up(21, 21)` is
# `(41 // 21) * 21 == 21` and the bit version is `41 & ~20 == 41`.
# `ip_ru_21_21` is the row -- without it the WPR ladder and the radix would look
# correct (every one of their moduli IS a power of two) and the helper would be
# wrong for every caller that is not.
def ru(+x: U32, +m: U32) -> U32: U32.mul(U32.div(U32.add(x, U32.sub(m, 1)), m), m)
def rd(+x: U32, +m: U32) -> U32: U32.mul(U32.div(x, m), m)
def cdiv(+a: U32, +b: U32) -> U32: U32.div(U32.add(a, U32.sub(b, 1)), b)

# :384-385 `self.cmd_q_view[:ctypes.sizeof(nv.msgqTxHeader)] = bytes(nv.msgqTxHeader(
# version=0, size=queue_size, entryOff=0x1000, msgSize=0x1000,
# msgCount=(queue_size - 0x1000) // 0x1000, writePtr=0, flags=1,
# rxHdrOff=ctypes.sizeof(nv.msgqTxHeader)))`
#
# ONE record in FIELD ORDER, and the ring length is `msgSize*msgCount` and NOT
# `size` -- `Q.ring_len` is the row that says so, because it is the number the
# wrap test at :48 measures against and a port that used `size` would wrap one
# message early on every queue whose header and ring disagree (they always do:
# 0x40000 against 0x3f000).
type Q is Data:
  Q{version: U32, size: U32, msg_size: U32, msg_count: U32, wp: U32, flags: U32,
    rx_hdr_off: U32, entry_off: U32, ring_len: U32}

def Q.ring_len(q: Q) -> U32:
  match q:
    case Q{version, size, msg_size, msg_count, wp, flags, rx_hdr_off, entry_off, +ring_len}: ring_len

def Q.msg_size(q: Q) -> U32:
  match q:
    case Q{version, size, +msg_size, msg_count, wp, flags, rx_hdr_off, entry_off, ring_len}: msg_size

def Q.msg_count(q: Q) -> U32:
  match q:
    case Q{version, size, msg_size, +msg_count, wp, flags, rx_hdr_off, entry_off, ring_len}: msg_count

def Q.size(q: Q) -> U32:
  match q:
    case Q{version, +size, msg_size, msg_count, wp, flags, rx_hdr_off, entry_off, ring_len}: size

def Q.rx_hdr_off(q: Q) -> U32:
  match q:
    case Q{version, size, msg_size, msg_count, wp, flags, +rx_hdr_off, entry_off, ring_len}: rx_hdr_off

def Q.entry_off(q: Q) -> U32:
  match q:
    case Q{version, size, msg_size, msg_count, wp, flags, rx_hdr_off, +entry_off, ring_len}: entry_off

def Q.version(q: Q) -> U32:
  match q:
    case Q{+version, size, msg_size, msg_count, wp, flags, rx_hdr_off, entry_off, ring_len}: version

def Q.flags(q: Q) -> U32:
  match q:
    case Q{version, size, msg_size, msg_count, wp, +flags, rx_hdr_off, entry_off, ring_len}: flags

def Q.of(+size: U32) -> Q: q.of(size, U32.div(U32.sub(size, 4096), 4096))

def q.of(+size: U32, +count: U32) -> Q:
  Q{0, size, 4096, count, 0, 1, 32, 4096, U32.mul(4096, count)}

# :366-367 `pte_cnt = queue_pte_cnt + round_up(queue_pte_cnt * 8, 0x1000) // 0x1000`
# and `pt_size = round_up(pte_cnt * 8, 0x1000)`. The `+ round_up(...)` half is a
# page table for the PAGE TABLE and dropping it shrinks `pt_size` by a page.
def rm_ptcnt(+queue_size: U32) -> U32:
  rm_ptcnt2(U32.div(U32.mul(queue_size, 2), 4096))

def rm_ptcnt2(+queue_pte_cnt: U32) -> U32:
  U32.add(queue_pte_cnt, U32.div(ru(U32.mul(queue_pte_cnt, 8), 4096), 4096))

def rm_ptsize(+queue_size: U32) -> U32: ru(U32.mul(rm_ptcnt(queue_size), 8), 4096)

# :407-408 the radix3. `LIBOS_MEMORY_REGION_RADIX_PAGE_LOG2 - 3` is 9, and the
# `-1` BEFORE the shift is what makes level 0 count LEVELS rather than pages --
# without it every level would be the same size.
def radix_step(+n: U32) -> U32: U32.add(U32.shrn(U32.sub(n, 1), 9n), 1)
def radix_l3(+n: U32) -> U32: U32.div(ru(n, 4096), 4096)
def radix_l2(+n: U32) -> U32: radix_step(radix_l3(n))
def radix_l1(+n: U32) -> U32: radix_step(radix_l2(n))
def radix_l0(+n: U32) -> U32: radix_step(radix_l1(n))

# :410 `offsets = [sum(npages[:i]) * 0x1000 for i in range(4)]` -- a PREFIX SUM,
# so `offs[0]` is 0 and `offs[3]` is the image start.
def radix_off0(+n: U32) -> U32: 0
def radix_off1(+n: U32) -> U32: U32.mul(radix_l0(n), 4096)
def radix_off2(+n: U32) -> U32: U32.add(radix_off1(n), U32.mul(radix_l1(n), 4096))
def radix_off3(+n: U32) -> U32: U32.add(radix_off2(n), U32.mul(radix_l2(n), 4096))
def radix_alloc(+n: U32) -> U32: U32.add(radix_off3(n), n)

# ---------------------------------------------------------------------------
# :434-455 init_wpr_meta. `Wm` is the EIGHT offsets the legacy branch computes
# plus the sizes both branches set, and `nf` is how many fields the branch sets --
# because the `fmc_boot` branch sets a DIFFERENT six and NONE of them is an
# offset. Without `nf` its rows would be six zeros that read like a card with
# every region at address zero. `ip_wpr_1g_leg_nf` is 25 and `ip_wpr_1g_fmc_nf`
# is 16, and the first version of this record said 26 because it counted
# `common` as twelve -- one field too many, and the count row is the only thing
# that could see it.
#
# THE 64-BIT WALL IS THE FIXTURES, not the code. `vram_size` for any real card is
# at least 4 GiB and this chain SUBTRACTS from it, so every offset exceeds 2**32
# and none of it fits a U32. The ladder is ported in BYTES over fixtures that DO
# fit (1 GiB, 2 GiB, and the largest U32), which is what makes the CHAIN
# checkable -- eight `round_down`s and two byte subtractions -- and the real card
# is the seam. `ip_wpr_vram_max` is the ceiling and
# `ip_wpr_vram_max` says the wall out loud.
#   # TODO(p3) support/nv/ip.py:448  init_wpr_meta's offsets for a real card
# ---------------------------------------------------------------------------
type Wm is Data:
  Wm{nf: U32, vga_ws: U32, vga_off: U32, frts_sz: U32, frts_off: U32,
     boot_off: U32, gsp_off: U32, heap_sz: U32, heap_off: U32, wpr_st: U32,
     nonwpr_sz: U32, nonwpr_off: U32, rsvd: U32, wpr_end: U32, fb: U32}

def wm_vga_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, +vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: vga_off

def wm_frts_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, +frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: frts_off

def wm_boot_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, +boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: boot_off

def wm_gsp_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, +gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: gsp_off

def wm_heap_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, +heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: heap_off

def wm_wpr_st(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, +wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: wpr_st

def wm_nonwpr_off(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, +nonwpr_off, rsvd, wpr_end, fb}: nonwpr_off

def wm_rsvd(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, +rsvd, wpr_end, fb}: rsvd

def wm_wpr_end(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, +wpr_end, fb}: wpr_end

def wm_fb(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, +fb}: fb

def wm_nf(m: Wm) -> U32:
  match m:
    case Wm{+nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: nf

def wm_frts_sz(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, +frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: frts_sz

def wm_heap_sz(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, +heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: heap_sz

def wm_nonwpr_sz(m: Wm) -> U32:
  match m:
    case Wm{nf, vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, +nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: nonwpr_sz

def wm_vga_ws(m: Wm) -> U32:
  match m:
    case Wm{nf, +vga_ws, vga_off, frts_sz, frts_off, boot_off, gsp_off, heap_sz, heap_off, wpr_st, nonwpr_sz, nonwpr_off, rsvd, wpr_end, fb}: vga_ws

# THE LEGACY CHAIN, read DOWNWARD. Two of the subtrahends are BYTE lengths of
# firmware images (`boot_sz`, `radix3_sz`) and the other six are constants, so
# the whole thing is exact -- but every step needs the one above it and Bend
# refuses mutual recursion, so the chain is eight defs that each thread one more
# parameter. That is the substrate's price and `spec.bend` pays the same one for
# its six scans.
def wpr.leg(+vram: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg2(vram, U32.sub(vram, 1048576), boot_sz, radix3_sz)

def wpr.leg2(+vram: U32, +vga_off: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg3(vram, vga_off, U32.sub(vga_off, 1048576), boot_sz, radix3_sz)

def wpr.leg3(+vram: U32, +vga_off: U32, +frts_off: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg4(vram, vga_off, frts_off, U32.sub(frts_off, boot_sz), radix3_sz)

def wpr.leg4(+vram: U32, +vga_off: U32, +frts_off: U32, +boot_off: U32, radix3_sz: U32) -> Wm:
  wpr.leg5(vram, vga_off, frts_off, boot_off, rd(U32.sub(boot_off, radix3_sz), 65536))

def wpr.leg5(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, +gsp_off: U32) -> Wm:
  wpr.leg6(vram, vga_off, frts_off, boot_off, gsp_off,
           rd(U32.sub(gsp_off, 135266304), 1048576))

def wpr.leg6(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, +gsp_off: U32,
            +heap_off: U32) -> Wm:
  wpr.leg7(vram, vga_off, frts_off, boot_off, gsp_off, heap_off,
           rd(U32.sub(heap_off, 4096), 1048576))

def wpr.leg7(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, gsp_off: U32,
            heap_off: U32, +wpr_st: U32) -> Wm:
  wpr.leg8(vram, vga_off, frts_off, boot_off, gsp_off, heap_off, wpr_st,
           rd(U32.sub(wpr_st, 1048576), 1048576))

# THE LAST STEP, and the two bugs it cost are both worth writing down.
#
# 1. Its eight parameters are each read TWICE in the `Wm{...}` literal, so each
#    one needs `+` -- and the message for a missing `+` on the seventh of eight is
#    `expected : Wm, observed : @+wpr_st:U32 -> Wm`, i.e. the compiler reads the
#    call as PARTIALLY APPLIED and quotes the type of the parameter it choked on.
# 2. Splitting it into `leg8`/`leg9` does NOT help if `leg8` then passes its
#    parameters through unchanged: the same message comes back. The record has to
#    be built where the parameters are `+`, and `leg8` has to exist only to keep
#    the line short.
def wpr.leg8(vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, gsp_off: U32,
            heap_off: U32, wpr_st: U32, rsvd: U32) -> Wm:
  wpr.leg9(vram, vga_off, frts_off, boot_off, gsp_off, heap_off, wpr_st, rsvd)

def wpr.leg9(+vram: U32, +vga_off: U32, +frts_off: U32, +boot_off: U32, +gsp_off: U32,
             +heap_off: U32, +wpr_st: U32, +rsvd: U32) -> Wm:
  Wm{25, 1048576, vga_off, 1048576, frts_off, boot_off, gsp_off, 135266304,
     heap_off, wpr_st, 1048576, rsvd, rsvd, vga_off, vram}

# :444-445 the `fmc_boot` branch sets SIX fields and NONE of them is an offset,
# so all eight offsets are 0 here -- and `nf` (16 against 26) is what says "this
# branch computed nothing positional" instead of "this card has its regions at
# address zero".
def wpr.fmc() -> Wm:
  Wm{16, 131072, 0, 1048576, 0, 0, 0, 141557760, 0, 0, 2228224, 0, 0, 0, 0}
