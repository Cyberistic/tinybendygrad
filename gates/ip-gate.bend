# gates/ip-gate.bend -- the gate driver for `tinybendygrad/runtime/support/nv/ip.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/support/nv/ip.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))


# THREE rows per struct: nf, size, fields. nf and size are the record's own
# values and the field string is a SECOND transcription of the same struct, so a
# dropped name is caught by nf and a wrong offset only by the field row.
def st_rows.go(+xs: List<&2, P.St>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case s <> t:
      st_rows.go(t, List.append(&2, String, acc,
        [String.concat(["ip_st_", P.St.nm(s), "_nf=", U32.show(P.St.nf(s))]),
         String.concat(["ip_st_", P.St.nm(s), "_sz=", U32.show(P.St.size(s))]),
         String.concat(["ip_st_", P.St.nm(s), "=", P.St.fields(s)])]))


# ONE row per constant, in table order, asking for the value FROM THE NAME.
def cn_rows.go(+xs: List<&2, P.Cn>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case c <> t:
      cn_rows.go(t, List.append(&2, String, acc,
        [String.concat(["ip_c_", P.Cn.name(c), "=", U32.show(P.Cn.v(P.const_of(P.Cn.name(c))))])]))


# ONE row per dispatched (id, name), in table order.
def ce_rows.go(+xs: List<&2, P.Ce>, +pfx: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case c <> t:
      ce_rows.go(t, pfx, List.append(&2, String, acc,
        [String.concat([pfx, U32.show(P.Ce.id(c)), "=", P.Ce.name(c)])]))


def emit(xs: List<&2, String>) -> IO(Unit): IO.print(String.join(xs, "\n"))


# THE BOTH-DIRECTIONS ROWS, which is the half of "both directions" a per-table
# row cannot reach: `ip_c_<NAME>` asks the table for a value FROM A NAME, and
# these ask it for a NAME FROM A VALUE. They run `P.const_name`, which is
# FIRST-WINS -- and eight names share the value 1, so `ip_c_one_first` must
# answer the FIRST of them and `ip_c_one_n` must count all eight. A last-wins
# fold answers the eighth and counts one, which is a different pair of rows.
# `ip_d_lbl_*` are the three arms of :81 and each is picked so exactly one arm can
# fire: a function id, an event id, and ids in NEITHER table.
def t_names() -> IO(Unit):
  do IO<Unit>:
    urow("ip_c_one_n", P.const_name_n(1))
    srow("ip_c_one_first", P.const_name(1))
    urow("ip_c_n0_k", P.const_name_n(0))
    srow("ip_c_n0", P.const_name(0))
    urow("ip_c_n4_k", P.const_name_n(4))
    srow("ip_c_n4", P.const_name(4))
    urow("ip_c_n72_k", P.const_name_n(72))
    srow("ip_c_n72", P.const_name(72))
    urow("ip_c_n4097_k", P.const_name_n(4097))
    srow("ip_c_n4097", P.const_name(4097))
    urow("ip_c_n_big_k", P.const_name_n(545259819))
    srow("ip_c_n_big", P.const_name(545259819))
    urow("ip_c_n_miss_k", P.const_name_n(999999))
    srow("ip_c_n_miss", P.const_name(999999))
    srow("ip_d_lbl_fn", P.rpc_label(4))
    srow("ip_d_lbl_fn0", P.rpc_label(0))
    srow("ip_d_lbl_ev", P.rpc_label(4097))
    srow("ip_d_lbl_ev_max", P.rpc_label(4131))
    srow("ip_d_lbl_miss", P.rpc_label(4132))
    srow("ip_d_lbl_miss2", P.rpc_label(999))
    srow("ip_d_lbl_miss_hex", P.rpc_label(4135))
    urow("ip_d_arm_fn", P.rpc_arm(4))
    urow("ip_d_arm_ev", P.rpc_arm(4097))
    urow("ip_d_arm_miss", P.rpc_arm(4132))


def st_sum_fields.go(+xs: List<&2, P.St>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case s <> t: st_sum_fields.go(t, U32.add(n, P.St.nf(s)))


def st_sum_bytes.go(+xs: List<&2, P.St>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case s <> t: st_sum_bytes.go(t, U32.add(n, P.St.size(s)))


def st_names.go(+xs: List<&2, P.St>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case s <> t: st_names.go(t, String.concat([acc, String.concat([P.St.nm(s), ","])]))


def cn_names.go(+xs: List<&2, P.Cn>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case c <> t: cn_names.go(t, String.concat([acc, String.concat([P.Cn.name(c), ","])]))


def ce_min.go(+xs: List<&2, P.Ce>, +m: U32) -> U32:
  match xs:
    case Nil{}: m
    case c <> t: ce_min.go(t, U32.min(P.Ce.id(c), m))


def ce_max.go(+xs: List<&2, P.Ce>, +m: U32) -> U32:
  match xs:
    case Nil{}: m
    case c <> t: ce_max.go(t, U32.max(P.Ce.id(c), m))


# the id spaces must be DISJOINT or :81's second arm is dead code
def overlap.go(+a: List<&2, P.Ce>, +b: List<&2, P.Ce>, +n: U32) -> U32:
  match a:
    case Nil{}: n
    case c <> t: overlap.go(t, b, P.bump(P.ce_has(b, P.Ce.id(c)), n))


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


def q.of(+size: U32, +count: U32) -> Q:
  Q{0, size, 4096, count, 0, 1, 32, 4096, U32.mul(4096, count)}


def rm_ptcnt2(+queue_pte_cnt: U32) -> U32:
  U32.add(queue_pte_cnt, U32.div(ru(U32.mul(queue_pte_cnt, 8), 4096), 4096))


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



# :602 `def bdf_as_int(s): return 0x000 if s.startswith("usb") or
# s.startswith("remote") else (int(s[5:7],16)<<8) | (int(s[8:10],16)<<3) |
# int(s[-1],16)`
#
# TWO hex PAIRS, one hex NIBBLE, and the last character is the one AFTER the dot.
# Two things this gets wrong if it is written the obvious way, and the rows
# `ip_bdf_*` reach both:
#   * `int(s[-1],16)` is `s[len-1]`, which for `0000:01:00.0` is `0` -- the digit
#     after the dot. Reading `s[10:12]` takes the FUNCTION and the dot instead.
#   * the guard is `usb` OR `remote`, not `usb` alone. The first version of this
#     had only `usb` and `as_int("remote")` printed 96158: `r`=114, `e`=101,
#     `m`=109, `o`=110 read as hex. `ip_bdf_remote` is that row.

def chr_g(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 58), U32.sub(c, 48),
    Bool.pick(U32, U32.is_lt(c, 90), U32.sub(c, 55), U32.sub(c, 87)))


def chr_un(m: Maybe<&2, Char>) -> U32:
  match m:
    case Some{g}: chr_g(Char.to_u32(g))
    case None{}: 99


def chr_at(+s: String, n: U32) -> U32:
  chr_un(String.get(s, U32.to_nat(n)))


def hexpair(+s: String, a: U32, b: U32) -> U32:
  U32.add(U32.mul(chr_at(s, a), 16), chr_at(s, b))


def bdf.lo(s: String) -> U32: hexpair(s, 5, 6)

def bdf.mid(s: String) -> U32: hexpair(s, 8, 9)

def bdf.fn(+s: String) -> U32: chr_at(s, U32.sub(U32.from_nat(String.length(s)), 1))


def bdf.as_int(+s: String) -> U32:
  Bool.pick(U32, Bool.or(String.starts_with(s, "usb"), String.starts_with(s, "remote")), 0,
    U32.or(U32.or(U32.shln(bdf.lo(s), 8n), U32.shln(bdf.mid(s), 3n)), bdf.fn(s)))



# :389-399 init_libos_args. FIVE log buffers of 0x10000 at 0x10000 strides from
# ONE 2 MiB log allocation, then a sixth region for the RM args -- and the sixth
# has a different size (0x1000) and a different base. So the region table is
# `libos_size(i)` / `libos_pa(i)` with the `i < 5` arm, and `ip_libos_*` pins
# all six plus the total the memcpy at :399 writes.
#
# THE 64-BIT wall is here and it is not optional: `id8=int.from_bytes(
# bytes(f"LOG{name}", 'utf-8'), 'big')` is an EIGHT-BYTE name read as a big-endian
# integer. `int.from_bytes(b'LOGINIT','big')` is 0x4C4F47494E49544E, which does
# not fit a U32 and has no U32 spelling. What survives is that the name is eight
# bytes, the first is 'L' for all six, and the sixth name is `RMARGS` and not
# `LOG*` -- so `ip_libos_id8_bytes` is the row and `id8` is the seam.
#   # TODO(p3) support/nv/ip.py:395  symbol=init_libos_args  id8=int.from_bytes(...)

def libos_n() -> U32: 6


def pma.is_one(nm: String) -> Bool: U32.is_eq(P.Cn.v(P.const_of(nm)), 1)


# `over.fixtures_fit` -- the 64-BIT WALL, stated as a predicate rather than as a
# comment. 24 GiB does not fit a U32 and no port of `init_wpr_meta` can hold it.
# THE 64-BIT wall, WRITTEN down twice because BEND HAS no hex literals.
#
# There is no `0x` syntax at all in Bend 2.0.34: `U32.show(0xffffffff)` is
#     expected : a numeric literal (NUMBER is U32, NUMBER n is Nat)
#     observed : 'x'
# with the caret on the `x`, so EVERY constant in this file is decimal and the
# header's `0x...` spellings are prose only. That is convenient here, because a
# real card's `vram_size` is 24 GiB -- five hex digits, larger than any U32 -- and
# it cannot be written down either way. `over.fixtures_fit` asks it with a
# constant that fits and the oracle says a real 24 GiB card is above it;
# `ip_wpr_vram_max` is the ceiling the fixtures stop at.
# every fixture this gate uses is a VRAM that FITS a U32 -- the row that makes
# the wall's scope explicit rather than assumed.
def over.fixtures_fit() -> Bool:
  Bool.and(U32.is_le(1073741824, 4294967295),
           Bool.and(U32.is_le(2147483648, 4294967295), U32.is_le(4294967295, 4294967295)))


def rm_qptcnt(+queue_size: U32) -> U32: U32.div(U32.mul(queue_size, 2), 4096)

def libos_size(+i: U32) -> U32: Bool.pick(U32, U32.is_lt(i, 5), 65536, 4096)

def libos_stride() -> U32: 65536

def libos_log_base() -> U32: 2097152

# `sum(ctypes.sizeof(s) for s in libos_structs)` is the sum of the STRUCT SIZES --
# 6 * 32 = 192 -- and NOT the sum of the region sizes the table carries, which is
# 0x51000. The first version summed the regions and the differ said
# `ip_libos_total oracle: 192, port: 335872`. It is the length of the memcpy at
# :399, so the distinction is the whole point of the row.
def libos_total() -> U32: U32.mul(libos_n(), 32)


def libos_pa(+i: U32, rm_sysmem: U32) -> U32:
  Bool.pick(U32, U32.is_lt(i, 5),
            U32.add(libos_log_base(), U32.mul(libos_stride(), i)), rm_sysmem)


# the first byte of every one of the six names is 'L' for five of them and 'R'
# for `RMARGS`, and that ONE byte is the only part of `id8` a U32 can hold.
def libos_lead(+i: U32) -> U32: Bool.pick(U32, U32.is_lt(i, 5), 76, 82)



# :616-627 rpc_set_registry_table. `nameOffset = hdr_size + entries_size +
# len(data_bytes)` is a RUNNING SUM: the two entries are at 40 and 61, not at
# 40 and 40+21-by-stride-with-a-constant. `sizeof(PACKED_REGISTRY_ENTRY)` is 16
# and the header 8, so entries_size is 32 -- and the header's OWN `size` field is
# 8 + 32 + 42 = 82, which is the length of the whole record the GSP parses.
# `ip_reg_off0` / `ip_reg_off1` / `ip_reg_size` are the three rows and they are
# the reason the dict-at-:617 is a `List` here: two entries, two offsets.

def reg_hdr_size() -> U32: 8

def reg_entry_size() -> U32: 16

def reg_n() -> U32: 2

def reg_entries_size() -> U32: U32.mul(reg_entry_size(), reg_n())

def reg_data_len() -> U32: 42

# len('RMForcePcieConfigSave') + 1 for the NUL is TWENTY-TWO, not twenty-one:
# R-M-F-o-r-c-e-P-c-i-e-C-o-n-f-i-g-S-a-v-e is twenty-one letters and the NUL
# makes twenty-two. With 21 the second name lands at 61 and the GSP reads one
# byte of the first name as the end of it -- `ip_reg_RMSecBusResetEnable_off`
# (oracle 62) is the row.
def reg_len0() -> U32: 22

def reg_off0() -> U32: U32.add(U32.add(reg_hdr_size(), reg_entries_size()), 0)

def reg_off1() -> U32: U32.add(U32.add(reg_hdr_size(), reg_entries_size()), reg_len0())

def reg_size() -> U32: U32.add(U32.add(reg_hdr_size(), reg_entries_size()), reg_data_len())

def reg_type() -> U32: P.Cn.v(P.const_of("REGISTRY_TABLE_ENTRY_TYPE_DWORD"))

def reg_val() -> U32: 1



# :577-580 the PMA flags. THREE constants that are ALL the value 1 -- so the
# table a gate needs is (value, SHIFT) per flag, not value per flag. That is the
# one place in this file where a value-only constant table is not enough, and
# `ip_pma_all_three_are_1` is the row that says so.

def pma.phys() -> U32: U32.shln(P.Cn.v(P.const_of("NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS")), 4n)

def pma.nomap() -> U32: U32.shln(P.Cn.v(P.const_of("NVOS02_FLAGS_MAPPING_NO_MAP")), 30n)

def pma.ro(ro: U32) -> U32: U32.shln(ro, 21n)

def pma.flags() -> U32: U32.or(pma.phys(), pma.nomap())


def cls.gp2(+chip: String, ampere: U32, blackwell: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell, ampere)


def cls.cp2(+chip: String, ampere: U32, blackwell: U32, ada: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell,
    Bool.pick(U32, String.starts_with(chip, "AD"), ada, ampere))


def cls.dm2(+chip: String, ampere: U32, blackwell: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell, ampere)


def cls.vd2(+chip: String, ada: U32, gb: U32) -> U32:
  Bool.pick(U32, Bool.or(String.starts_with(chip, "AD"), String.starts_with(chip, "GB")),
            Bool.pick(U32, String.starts_with(chip, "GB"), gb, ada), 0)



# :629-661 run_cpu_seq's OPCODE TABLE, and :661 is the refusal. Nine opcodes,
# contiguous 0x0..0x8, with a WIDTH each -- and the width is what makes the walk
# a walk: `iter(memoryview(seq_buf[hdr_sz:]).cast('I')[:hdr.cmdIndex])` and then
# `next(cmd_iter)` that many times per op. The five register ops consume words;
# the four falcon ops consume none. `ip_seq_words` is the row, and it is
# `2,3,5,1,2,0,0,0,0` -- a table that said 1 for everything would consume a
# quarter of the program.

def seq_n() -> U32: 9

# THE WIDTH TABLE, and it is a TABLE. The obvious formula
# `3 - i + 1 for i < 4, 2 for i == 4, 0 otherwise` gives 4,3,2,1,2,0,0,0,0 -- and
# `ip_seq_words` says 2,3,5,1,2,0,0,0,0, because `reg_poll` at 0x2 consumes FIVE
# words (`addr, mask, val, _, _` at :639) and is the widest of the register ops.
# Getting that wrong makes the walk at :631 consume the wrong number of words and
# desynchronise every opcode after it.
def seq_words(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), 2,
    Bool.pick(U32, U32.is_eq(i, 1), 3,
      Bool.pick(U32, U32.is_eq(i, 2), 5,
        Bool.pick(U32, U32.is_eq(i, 3), 1, Bool.pick(U32, U32.is_eq(i, 4), 2, 0)))))


def seq_bad(op: U32) -> Bool: U32.is_gt(op, 8)


# the index the walk STOPS at travels in a RECORD with the ops, because the fold
# answers one value and a `let` is affine so the index cannot be bound outside.
# Same shape as `Found` in ops.bend and `ShapeRes` in helpers.bend.
type Wk is Data:
  Wk{ops: List<&2, U32>, i: U32}


def Wk.ops(w: Wk) -> List<&2, U32>:
  match w:
    case Wk{+ops, i}: ops


def Wk.i(w: Wk) -> U32:
  match w:
    case Wk{ops, +i}: i


# where the index is after this word: an OPERAND does not move it, a live OPCODE
# moves it past its own width, and a DEAD opcode freezes it (which is :661).
def seq.at(+i: U32, +skip: U32, +o: U32) -> U32:
  Bool.pick(U32, U32.is_gt(skip, 0), i, U32.add(U32.add(i, 1), seq_words(o)))


def seq.next_skip(+skip: U32, +o: U32) -> U32:
  Bool.pick(U32, U32.is_gt(skip, 0), U32.sub(skip, 1), seq_words(o))


# the recorded ops: an OPERAND is never recorded, and a DEAD opcode is never
# recorded either -- it is the refusal at :661 and there is nothing to write.
def seq.put(+acc: List<&2, U32>, +skip: U32, +o: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, Bool.or(U32.is_gt(skip, 0), seq_bad(o)), acc,
            List.append(&2, U32, acc, [o]))

# different widths, a delay, a save, and a zero-width falcon op.
def seq_prog() -> List<&2, U32>:
  List.concat(&2, U32, [[0, 4096, 57005], [0, 8192, 48879], [3, 1000], [4, 12288, 1], [6]])



# :328-344 kfsp_send_msg's framing. EIGHT bytes of header: `0xC0000000` then
# `0x7e | (0x10de << 8) | (nvmd << 24)`. The first word is BOTH bit 31 and bit
# 30 and is the same for every message; the second carries the function in its
# TOP byte and two magic constants below it. Then `buf = headers + buf + (4 -
# (len(buf) % 4)) * b'\x00'` -- pad to a multiple of FOUR, computed on the
# PAYLOAD length, not the total, so a 4-byte payload adds nothing and a 5-byte
# payload adds three.

def fsp_w0() -> U32: U32.or(U32.shln(1, 31n), U32.shln(1, 30n))

def fsp_w1(+nvmd: U32) -> U32: U32.or(U32.or(126, U32.shln(4318, 8n)), U32.shln(nvmd, 24n))

def fsp_hdr_len() -> U32: 8

def fsp_pad(+blen: U32) -> U32: U32.mod(U32.sub(4, U32.mod(blen, 4)), 4)

def fsp_tot(+blen: U32) -> U32: U32.add(U32.add(blen, fsp_hdr_len()), fsp_pad(blen))


# :332 `assert len(buf) < 0x400` -- 1024. `fsp_ok` is the arm that reaches the
# write; `ip_fsp_max_ok_payload` is the largest payload that does.
def fsp_max() -> U32: 1024

def fsp_ok(+tot: U32) -> Bool: U32.is_lt(tot, 1024)



# :530-531 rpc_alloc_memory's scalars, and :533's pte descriptor.
# `pte=(paddr >> 12)` is a PAGE NUMBER, and the packed payload is
# `8 * pageCount` bytes of pte descriptors after the 56-byte rpc header -- so
# `pageCount` and the payload length are two readings of the same list and
# `ip_am_payload` is the row that ties them.

def pte_shift(+paddr: U32) -> U32: U32.shrn(paddr, 12n)

def pte_mask(+n: U32) -> U32: U32.and(n, 65535)

def am_format() -> U32: 6

def am_pte_adjust() -> U32: 0

def am_idr() -> U32: P.Cn.v(P.const_of("NV_VGPU_PTEDESC_IDR_NONE"))

def am_hdr() -> U32: 56

def am_pte_sz() -> U32: 8

def am_payload(+npages: U32) -> U32: U32.add(am_hdr(), U32.mul(am_pte_sz(), npages))


# :526 `assert all(sz == 0x1000 for _, sz in paddrs)` -- the refusal, and the
# only one in this file that fires on a CALLER's data. `am_pages_ok` is the arm.
def am_page(+sz: U32) -> Bool: U32.is_eq(sz, 4096)

def am_pages_ok(+sz0: U32, +sz1: U32) -> Bool: Bool.and(am_page(sz0), am_page(sz1))



# `radix.npages` and `radix.offs` join a four-element U32 list, so the row is
# `l0,l1,l2,l3` and a wrong ORDER inside the join is a value change the differ
# sees. `radix.npages` is NOT the same four numbers as `radix.offs` -- one is
# page COUNTS and the other is byte OFFSETS -- and the rows are named apart so a
# port that returned offsets for both would still fail.
def ujoin(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  String.join([U32.show(a), U32.show(b), U32.show(c), U32.show(d)], ",")


def radix.npages(+n: U32) -> String: ujoin(radix_l0(n), radix_l1(n), radix_l2(n), radix_l3(n))

def radix.offs(+n: U32) -> String: ujoin(radix_off0(n), radix_off1(n), radix_off2(n), radix_off3(n))


# :30 `self.queue_mv = view.view(self.tx.entryOff, self.tx.msgSize *
# self.tx.msgCount)` -- the ring LENGTH, which is `msgSize*msgCount` and not
# `size`. `rp.hdr_len` / `rp.phdr_len` are `ctypes.sizeof` of the two structs and
# they are the constants of the checksum fold.
def rp.hdr_len() -> U32: 32

def rp.phdr_len() -> U32: 48


# :58 `max_payload = self.tx.msgSize * 16 - sizeof(GSP_MSG_QUEUE_ELEMENT) -
# sizeof(rpc_message_header_v)`
def rp.max_payload() -> U32: U32.sub(U32.sub(U32.mul(4096, 16), rp.phdr_len()), rp.hdr_len())


# :145 `self.frts_offset = self.nvdev.vram_size - 0x100000 - 0x100000`
def fl.frts_offset(+vram: U32) -> U32: U32.sub(U32.sub(vram, 1048576), 1048576)


# :141-143 the ucode descriptor's two size arithmetic steps.
def fl.desc_sig(+ucode_desc_size: U32) -> U32:
  U32.sub(ucode_desc_size, P.Cn.v(P.const_of("FALCON_UCODE_DESC_V3_SIZE_44")))


def fl.desc_img(+stored_size: U32) -> U32: ru(stored_size, 256)


# :498-504. `ctx_info(size, align, add=0)` and the fixture engine table.
# THE FIXTURE, and it is the same shape as the oracle's `ENG`: `size` is
# 0x1000 * (i - 16) for ids above 16 and a flat 0x1000 below, so ids 0..16 all
# report 4096 and id 24 reports 32768. The first version of this was
# `4096 * max(i, 1)` -- which reports 4096 * i, so id 14 printed 57344 against the
# oracle's 4096. `ip_ctx_14_size` is the row that caught it, and it is the reason
# the fixture is written ONCE on each side rather than twice on one.
# `U32.max(i, 17)` BEFORE the subtraction, not after: `U32.sub` is a `U32`
# subtraction and `15 - 16` wraps to 4294967295, so `max(i-16, 1)` printed
# 4294963200 for engine 15. Clamping first and subtracting after is the only
# order that does not underflow, and `ip_ctx_15_size` is the row.
def ctx_size(+i: U32) -> U32: U32.mul(4096, U32.sub(U32.max(i, 17), 16))


# :495 `_ctx_info = round_up(engine[idx].size + add, align or engine[idx].alignment)`
def ctx_info(+sz: U32, +al: U32, +add: U32) -> U32: ru(U32.add(sz, add), al)


def ctx_eng(+i: U32) -> U32: ctx_size(i)

def ctx_eng_align(+i: U32) -> U32: U32.mul(4096, Bool.pick(U32, U32.is_lt(i, 21), 1, 4))


# :500 `align=(2 << 20) if x == 5 else None` -- `x` is the KEY 3..10 and only
# key 5 is 2 MiB aligned. The `x == 5` arm is the whole reason this is a table
# and not a constant: keys 4 and 6 use the engine alignment.
def cfgs_align(+x: U32) -> U32: Bool.pick(U32, U32.is_eq(x, 5), 2097152, ctx_eng_align(U32.add(x, 14)))


def cfgs(+x: U32) -> U32: ctx_info(ctx_eng(U32.add(x, 14)), cfgs_align(x), 0)


def ctx.rows.go(+xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("ip_ctx_end=1")
    case i <> t:
      do IO<Unit>:
        urow(String.concat(["ip_ctx_", U32.show(i), "_size"]), ctx_eng(i))
        urow(String.concat(["ip_ctx_", U32.show(i), "_align"]), ctx_eng_align(i))
        ctx.rows.go(t)


def ctx.cfg_rows.go(+xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("ip_ctxcfg_end=1")
    case x <> t:
      do IO<Unit>:
        urow(String.concat(["ip_ctxcfg_", U32.show(x)]), cfgs(x))
        ctx.cfg_rows.go(t)


def ctx.idxlist() -> List<&2, U32>:
  List.concat(&2, U32, [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12],
                        [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24]])


def ctx.keys3() -> List<&2, U32>:
  List.concat(&2, U32, [[3], [4], [5], [6], [7], [8], [9], [10]])



def grctx.early2(+engine: U32, +add: U32) -> U32:
  ctx_info(ctx_eng(engine), ctx_eng_align(engine), add)


def grctx.phys(+k: U32) -> Bool:
  Bool.pick(Bool, U32.is_le(k, 2), True{}, Bool.pick(Bool, U32.is_ge(k, 9), True{}, False{}))


def grctx.virt(+k: U32) -> Bool: Bool.not(U32.is_eq(k, 10))

def grctx.local(+k: U32) -> Bool: U32.is_eq(k, 1)


# ip.py:10-11 `GRBufDesc: size:int; virt:bool; phys:bool; local:bool=False`.
# FOUR fields in THAT order -- `virt` BEFORE `phys`, and `local` defaulted. The
# constructor is called positionally throughout (:501-504), so a port that put
# `phys` first would compile, typecheck and swap every context buffer's flags.
def grctx.n() -> U32: 10

# the separator goes BEFORE every element that is NOT the first. The arms read
# backwards from the obvious because `Bool.pick` answers its TRUE arm first, and
# `Bool.pick(String, first, "", ",")` therefore put the comma FIRST and nothing
# after: `ip_grctx_keys` printed `,012345691011`.
def grctx.sep(first: Bool) -> String: Bool.pick(String, first, ",", "")


def grctx.tag(+x: U32, first: Bool) -> String: String.concat([grctx.sep(first), U32.show(x)])


# THE insertion order of the dict at :501-504 -- and keys 7 and 8 ARE not in it.
# `{x: GRBufDesc(cfgs_sizes[x], ...) for x in range(3, 7)}` covers 3,4,5,6 and
# then 9,10,11 are added by key; nothing ever adds 7 or 8. A port that walked
# 0..11 would emit two rows the source does not have, and `ip_grctx_keys` /
# `ip_grctx_11_reuses_10` are how the differ says so.
def grctx.keylist() -> List<&2, U32>:
  List.concat(&2, U32, [[0], [1], [2], [3], [4], [5], [6], [9], [10], [11]])


def grctx.reuse(a: U32, b: U32) -> U32: Bool.pick(U32, U32.is_eq(a, b), 1, 0)


def grctx.count_local(+xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case k <> t: grctx.count_local(t, P.bump(grctx.local(k), n))


def cls.one(+v: U32) -> String: Bool.pick(String, U32.is_eq(v, 0), "None", U32.show(v))


def seq.opslist() -> List<&2, String>:
  List.concat(&2, String, [[P.nib(0)], [P.nib(1)], [P.nib(2)], [P.nib(3)], [P.nib(4)],
                            [P.nib(5)], [P.nib(6)], [P.nib(7)], [P.nib(8)]])


def seq.join5(+a: String, +b: String, +c: String, +d: String, +e: String) -> String:
  String.join([a, b, c, d, e], ",")


def seq.name(+i: U32) -> String:
  Bool.pick(String, U32.is_eq(i, 0), "reg_write",
    Bool.pick(String, U32.is_eq(i, 1), "reg_modify",
      Bool.pick(String, U32.is_eq(i, 2), "reg_poll",
        Bool.pick(String, U32.is_eq(i, 3), "delay_us",
          Bool.pick(String, U32.is_eq(i, 4), "save_reg",
            Bool.pick(String, U32.is_eq(i, 5), "core_reset",
              Bool.pick(String, U32.is_eq(i, 6), "start_cpu",
                Bool.pick(String, U32.is_eq(i, 7), "wait_halted", "core_resume"))))))))


def seq.words(+i: U32) -> String: U32.show(seq_words(i))


def seq.count(+xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case x <> t: seq.count(t, U32.add(n, 1))


def seq.sep(+sep: String, first: Bool) -> String: Bool.pick(String, first, sep, "")


def door.bit30(+chip: String) -> Bool: String.starts_with(chip, "GB2")


def t_libos() -> IO(Unit):
  do IO<Unit>:
    urow("ip_libos_n", libos_n())
    urow("ip_libos_total", libos_total())
    urow("ip_libos_size_0", libos_size(0))
    urow("ip_libos_size_1", libos_size(1))
    urow("ip_libos_size_2", libos_size(2))
    urow("ip_libos_size_3", libos_size(3))
    urow("ip_libos_size_4", libos_size(4))
    urow("ip_libos_size_5", libos_size(5))
    urow("ip_libos_pa_0", libos_pa(0, 196608))
    urow("ip_libos_pa_1", libos_pa(1, 196608))
    urow("ip_libos_pa_2", libos_pa(2, 196608))
    urow("ip_libos_pa_3", libos_pa(3, 196608))
    urow("ip_libos_pa_4", libos_pa(4, 196608))
    urow("ip_libos_pa_5", libos_pa(5, 196608))
    urow("ip_libos_pa_base", libos_log_base())
    urow("ip_libos_kind", P.Cn.v(P.const_of("LIBOS_MEMORY_REGION_CONTIGUOUS")))
    urow("ip_libos_loc", P.Cn.v(P.const_of("LIBOS_MEMORY_REGION_LOC_SYSMEM")))
    urow("ip_libos_id8_bytes", 8)
    urow("ip_libos_id8_over_u32", 6)
    urow("ip_libos_id8_n", libos_n())
    urow("ip_libos_lead_0", libos_lead(0))
    urow("ip_libos_lead_1", libos_lead(1))
    urow("ip_libos_lead_2", libos_lead(2))
    urow("ip_libos_lead_3", libos_lead(3))
    urow("ip_libos_lead_4", libos_lead(4))
    urow("ip_libos_lead_5", libos_lead(5))


def t_reg() -> IO(Unit):
  do IO<Unit>:
    urow("ip_reg_hdr_size", reg_hdr_size())
    urow("ip_reg_entries_size", reg_entries_size())
    urow("ip_reg_n", reg_n())
    urow("ip_reg_data_len", reg_data_len())
    urow("ip_reg_len0", reg_len0())
    urow("ip_reg_off0", reg_off0())
    urow("ip_reg_off1", reg_off1())
    urow("ip_reg_size", reg_size())
    urow("ip_reg_payload", reg_entries_size())
    urow("ip_reg_msg_payload", reg_size())
    urow("ip_reg_type", reg_type())
    urow("ip_reg_RMForcePcieConfigSave_off", reg_off0())
    urow("ip_reg_RMForcePcieConfigSave_val", reg_val())
    urow("ip_reg_RMForcePcieConfigSave_type", reg_type())
    urow("ip_reg_RMForcePcieConfigSave_len", 4)
    urow("ip_reg_RMSecBusResetEnable_off", reg_off1())
    urow("ip_reg_RMSecBusResetEnable_val", reg_val())
    urow("ip_reg_RMSecBusResetEnable_type", reg_type())
    urow("ip_reg_RMSecBusResetEnable_len", 4)


def t_bdf() -> IO(Unit):
  do IO<Unit>:
    urow("ip_bdf_0000_01_00_0", bdf.as_int("0000:01:00.0"))
    urow("ip_bdf_0000_0a_00_0", bdf.as_int("0000:0a:00.0"))
    urow("ip_bdf_0000_ff_1f_7", bdf.as_int("0000:ff:1f.7"))
    urow("ip_bdf_usb", bdf.as_int("usb"))
    urow("ip_bdf_remote", bdf.as_int("remote"))
    urow("ip_bdf_0000_00_00_0", bdf.as_int("0000:00:00.0"))
    row("ip_bdf_usb_arm", String.starts_with("usb", "usb"))
    row("ip_bdf_remote_arm", String.starts_with("remote", "remote"))
    row("ip_bdf_remote_not_usb", Bool.not(String.starts_with("remote", "usb")))
    urow("ip_bdf_lo_ff", bdf.lo("0000:ff:1f.7"))
    urow("ip_bdf_mid_1f", bdf.mid("0000:ff:1f.7"))
    urow("ip_bdf_fn_7", bdf.fn("0000:ff:1f.7"))
    urow("ip_bdf_pair_00", hexpair("0000:00:00.0", 5, 6))


def t_fsp_pad(+blen: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_fsp_pad_", U32.show(blen)]), fsp_pad(blen))
    urow(String.concat(["ip_fsp_tot_", U32.show(blen)]), fsp_tot(blen))


# ELEVEN tags, AND eleven is the number of call sites this file emits. The list
# used to run to twenty with gaps -- `C_HANDLE`, `C_ALLOC_MEM` and six RPC-kind
# tags that nothing ever passed to `Tr.emit` -- and the gaps were load-bearing
# twice over: they kept the dead constants out of the dead-def audit, and
# `C_ALLOC_MEM` was passed to `rp.record` WHERE PYTHON PASSES A FUNCTION ID, so
# the alloc trace claimed to send function 8 and sent function 4. The tags are
# numbered densely because the gate prints them and a hole in a printed sequence
# is a hole nobody can read.
def C_RPC_SEND() -> U32: 0

def C_QUEUE_WRITE() -> U32: 1

def C_QUEUE_WP() -> U32: 2

def C_BARRIER() -> U32: 3

def C_QUEUE_HEAD() -> U32: 4

def C_WAIT_RESP() -> U32: 5

def C_RPC_RAISE() -> U32: 6

def C_FSP_EMEMC() -> U32: 7

def C_FSP_EMEMD() -> U32: 8

def C_FSP_TAIL() -> U32: 9

def C_FSP_HEAD() -> U32: 10


type Cx is Data:
  Cx{k: U32, a: U32, b: U32, c: U32}


def Cx.of(k: U32, a: U32, b: U32, c: U32) -> Cx:
  Cx{k, a, b, c}


def Cx.k(x: Cx) -> U32:
  match x:
    case Cx{+k, a, b, c}: k


def Cx.a(x: Cx) -> U32:
  match x:
    case Cx{k, +a, b, c}: a


def Cx.b(x: Cx) -> U32:
  match x:
    case Cx{k, a, +b, c}: b


def Cx.c(x: Cx) -> U32:
  match x:
    case Cx{k, a, b, +c}: c


# THE MACHINE STATE OF THE SEAM. `wp` and `seq` are the ring's own fields, so they
# live here rather than being recomputed per call; `handle` is the
# `itertools.count(0xcf000000)` from :348; `fail_at` is the call ordinal at which
# the seam reports a refusal (0 = never, which is every successful fixture).
type Tr is Data:
  Tr{calls: List<&2, Cx>, wp: U32, seq: U32, handle: U32, fail_at: U32, refused: Bool}


def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 3472883712, 0, False{}}

def Tr.of.wp(+wp: U32) -> Tr: Tr{Nil{}, wp, 0, 3472883712, 0, False{}}


def Tr.calls(t: Tr) -> List<&2, Cx>:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, refused}: calls


def Tr.wp(t: Tr) -> U32:
  match t:
    case Tr{calls, +wp, seq, handle, fail_at, refused}: wp


def Tr.seq(t: Tr) -> U32:
  match t:
    case Tr{calls, wp, +seq, handle, fail_at, refused}: seq


def Tr.handle(t: Tr) -> U32:
  match t:
    case Tr{calls, wp, seq, +handle, fail_at, refused}: handle


def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, wp, seq, handle, fail_at, +refused}: refused


def Tr.ncalls(t: Tr) -> U32:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, refused}: U32.from_nat(List.length(&2, Cx, calls))


# the refusal at `fail_at`, and the call ordinal the emit is ABOUT
def tr.hit(refused: Bool, fail_at: U32, n: U32) -> Bool:
  Bool.or(refused, U32.is_eq(U32.add(n, 1), fail_at))


# THE SEAM. `Bool.pick` answers its TRUE arm first and the untaken arm does not
# reach the answer, so the accumulator is computed by `tr.go` and the append is
# the CALL -- see the note on `P.bump`. The failing call IS appended; everything
# after it is not, which is what makes a refusal a truncation.
def Tr.emit.go(+k: U32, +a: U32, +b: U32, +c: U32, +calls: List<&2, Cx>, +n: U32,
               refused: Bool) -> List<&2, Cx>:
  Bool.pick(List<&2, Cx>, refused, calls, List.append(&2, Cx, calls, [Cx.of(k, a, b, c)]))


def tr.put2(+calls: List<&2, Cx>, +wp: U32, +seq: U32, +handle: U32, +fail_at: U32,
            +refused: Bool) -> Tr:
  Tr{calls, wp, seq, handle, fail_at, refused}


def Tr.fail_at(+t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, wp, seq, handle, +fail_at, refused}:
      Tr{calls, wp, seq, handle, n, refused}



# :38-55 `_send_rpc_record`, AND NOTHING ELSE. The five facts the trace carries
# are the five the Python computes, in the order Python computes them:
#
#   length    = len(msg) + 0x20                                  (:40)
#   elemCount = ceildiv(len(header) + len(msg) + 48, msgSize)    (:43)
#   total     = elemCount * msgSize                              (:45)
#   off/first = wp * msgSize, min(total, ring_len - wp * msgSize) (:48)
#   wp'       = (wp + elemCount) % msgCount                      (:51)
#
# and then `seq += 1` (:54) and `NV_PGSP_QUEUE_HEAD[0].write(0x0)` (:55), with a
# memory barrier between the pointer store and the doorbell (:52,:78).

type Rq is Data:
  Rq{func: U32, plen: U32, elem: U32, total: U32, off: U32, first: U32,
     wraps: Bool, wp: U32, seq: U32, cksum: U32, t: Tr}


def Rq.of(func: U32, plen: U32, elem: U32, total: U32, off: U32, first: U32,
         wraps: Bool, wp: U32, seq: U32, cksum: U32, t: Tr) -> Rq:
  Rq{func, plen, elem, total, off, first, wraps, wp, seq, cksum, t}


def Rq.func(r: Rq) -> U32:
  match r:
    case Rq{+func, plen, elem, total, off, first, wraps, wp, seq, cksum, t}: func


def Rq.plen(r: Rq) -> U32:
  match r:
    case Rq{func, +plen, elem, total, off, first, wraps, wp, seq, cksum, t}: plen


def Rq.elem(r: Rq) -> U32:
  match r:
    case Rq{func, plen, +elem, total, off, first, wraps, wp, seq, cksum, t}: elem


def Rq.total(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, +total, off, first, wraps, wp, seq, cksum, t}: total


def Rq.off(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, +off, first, wraps, wp, seq, cksum, t}: off


def Rq.first(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, +first, wraps, wp, seq, cksum, t}: first


def Rq.wp(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, +wp, seq, cksum, t}: wp


def Rq.seq(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, +seq, cksum, t}: seq


def Rq.cksum(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, seq, +cksum, t}: cksum


def Rq.tr(r: Rq) -> Tr:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, seq, cksum, +t}: t


# the wire LENGTH: `length=len(msg) + 0x20` at :40, where `msg` is the PAYLOAD.
def rp.length(+plen: U32) -> U32: U32.add(plen, 32)

def rp.msg_size() -> U32: 4096

def rp.msg_count() -> U32: 63

def rp.ring_len() -> U32: U32.mul(rp.msg_size(), rp.msg_count())

def rp.entry_off() -> U32: 4096


# :43 `elemCount = ceildiv(len(msg) + ctypes.sizeof(GSP_MSG_QUEUE_ELEMENT),
# self.tx.msgSize)` -- and `msg` at that point is `bytes(header) + payload`, so
# the 32-byte header is IN the numerator.  Dropping it does not change the answer
# for any of the seven requests (they all round up to one element either way) and
# it changes the answer for a payload near a message boundary.
def rp.elem(+plen: U32) -> U32: cdiv(U32.add(U32.add(plen, 32), 48), rp.msg_size())


def rp.total(+plen: U32) -> U32: U32.mul(rp.elem(plen), rp.msg_size())


# :48 `off, first = wp * msgSize, min(len(msg), len(queue_mv) - wp * msgSize)`
# and `len(queue_mv)` is `msgSize * msgCount` -- NOT the header's `size`.  On a
# real queue those differ by a page, so the ring length is its own row.
def rp.off(+wp: U32) -> U32: U32.mul(wp, rp.msg_size())

def rp.first(+total: U32, +wp: U32) -> U32:
  U32.min(total, U32.sub(rp.ring_len(), U32.mul(wp, rp.msg_size())))


def rp.wraps(+total: U32, +wp: U32) -> Bool: U32.is_lt(rp.first(total, wp), total)

def rp.wp_after(+wp: U32, +elem: U32) -> U32: U32.mod(U32.add(wp, elem), rp.msg_count())



# THE CHECKSUM, and this is the part of Stage D that is worth the file.
#
# :32-36 folds a 64-bit XOR over the u64 words of `bytes(phdr) + msg` and returns
# `hi32(c) ^ lo32(c)`.  Bend has no 64-bit integer -- and it does not need one:
# the accumulator is a XOR and `hi32 ^ lo32` COMMUTES with XOR over the words, so
# the whole thing collapses to TWO U32 folds over the 20 U32 words of
# `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#
# The payoff is that the fold needs the BYTE OFFSETS.  `checkSum` is the ninth
# U32 of the 48-byte element and `function` is the sixteenth of the 32-byte header,
# so a transposed pair or a wrong offset moves the row -- and a COUNT gate would
# see neither.  `ip_rp_<i>_cksum` is the row, and `ip_rp_<i>_w<k>` names every
# word so the offset ITSELF is a row too.
#
# What the fold cannot see is the hi/lo LABEL of a pair. `rp.finish` XORs the two
# accumulators together, so exchanging `rp.pickw`'s arms permutes the words between
# them and the total is unchanged -- that mutation moves zero rows, and that is
# arithmetic rather than a missing fixture. `rp.pair.hi`/`rp.pair.lo`, the first
# design, threaded a `{h, l}` record through the recursion instead of running two
# walks; `Bool.pick` drops its untaken arm, so a self-call inside an arm cannot
# carry state back out, and the record was deleted rather than fixed.
#
# The ONE thing that does not fold is the checksum slot ITSELF: :44 evaluates
# `bytes(phdr)` while `phdr.checkSum` is still zero, so the fold runs over a zero
# there and the value lands afterwards.  `rp.cksum.xor` reproduces that, and the
# `ip_rp_<i>_cksum` rows are the slot.

def rp.w_seq() -> U32: 9

def rp.w_elem() -> U32: 10

def rp.w_version() -> U32: 12

def rp.w_signature() -> U32: 13

def rp.w_length() -> U32: 14

def rp.w_function() -> U32: 15

def rp.w_result() -> U32: 16

def rp.w_result_private() -> U32: 17

def rp.nwords() -> U32: 20


def rp.sig() -> U32: P.Cn.v(P.const_of("NV_VGPU_MSG_SIGNATURE_VALID"))

def rp.pending() -> U32: P.Cn.v(P.const_of("NV_VGPU_MSG_RESULT_RPC_PENDING"))

def rp.hdr_version() -> U32: U32.shln(3, 24n)


# an index past the image reads the LAST word, so a caller that over-runs the
# twenty cannot address past them. `rp.nwords` is the authority for the count.
def rp.which(+i: U32) -> U32: U32.min(i, U32.sub(rp.nwords(), 1))



def rp.word2(+w: U32, +i: U32, +func: U32, +plen: U32, +seq: U32) -> U32:
  Bool.pick(U32, U32.is_eq(w, rp.w_seq()), seq,
    Bool.pick(U32, U32.is_eq(w, rp.w_elem()), rp.elem(plen),
      Bool.pick(U32, U32.is_eq(w, rp.w_version()), rp.hdr_version(),
        Bool.pick(U32, U32.is_eq(w, rp.w_signature()), rp.sig(),
          Bool.pick(U32, U32.is_eq(w, rp.w_length()), rp.length(plen),
            Bool.pick(U32, U32.is_eq(w, rp.w_function()), func,
              Bool.pick(U32, U32.is_eq(w, rp.w_result()), rp.pending(),
                Bool.pick(U32, U32.is_eq(w, rp.w_result_private()), rp.pending(), 0))))))))


# THE FOLD. `u64words` is the u64-aligned pair count: 80 bytes is TEN words, and
# word k is (lo = w[2k], hi = w[2k+1]) on little-endian.
def rp.nu64() -> U32: 10


# the u64 image, ten words, each a PAIR of U32s read little-endian. `pay` is the
# payload's contribution to the XOR and is the SEAM: it is 0 for a zero payload
# and whatever the bytes fold to otherwise.
type W64 is Data:
  W64{lo: U32, hi: U32}


# u64 word k is the PAIR (lo = the U32 at 8k, hi = the U32 at 8k+4) on
# little-endian, so the two halves are `word[2k]` and `word[2k+1]`. That is the
# WHOLE endianness assumption, and swapping it is invisible to `hi32(c) ^ lo32(c)`
# -- the XOR is symmetric -- so `ip_rp_<i>_cksum` is the row that would see it.
def rp.pickw(+p: Nat, +hi: Bool) -> U32:
  Bool.pick(U32, hi, U32.add(U32.mul(U32.from_nat(p), 2), 1), U32.mul(U32.from_nat(p), 2))


def rp.finish(+h: U32, +l: U32) -> U32: U32.xor(h, l)


def rp.wrapbit(+total: U32, +wp: U32) -> U32:
  Bool.pick(U32, rp.wraps(total, wp), 1, 0)


def tr.fail(+t: Tr) -> U32:
  match t:
    case Tr{calls, wp, seq, handle, +fail_at, refused}: fail_at


def rp.cont_more(+plen: U32) -> U32:
  Bool.pick(U32, U32.is_gt(plen, rp.max_payload),
            cdiv(U32.sub(plen, rp.max_payload), rp.max_payload), 0)


def rp.cont_func() -> U32: P.Cn.v(P.const_of("NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD"))


# the function `rpc_alloc_memory` SENDS -- a value from the module's `rpc_fns`
# table, NOT a trace tag. Passing `C_ALLOC_MEM()` here is how the alloc trace came
# to claim it sent function 8 while it sent 4.
def rpc.func_alloc() -> U32: P.Cn.v(P.const_of("NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY"))



# :526-536 `rpc_alloc_memory`. The :527 assert is the refusal: EVERY page must be
# 4 KiB, and a single 8 KiB page refuses the whole call.

def am.page_ok(+sz: U32) -> Bool: U32.is_eq(sz, 4096)

def am.pages_ok2(+sz0: U32, +sz1: U32) -> Bool: Bool.and(am.page_ok(sz0), am.page_ok(sz1))

def am.pages_ok4(+sz0: U32, +sz1: U32, +sz2: U32, +sz3: U32) -> Bool:
  Bool.and(am.pages_ok2(sz0, sz1), am.pages_ok2(sz2, sz3))


# the handle generator, :348 `itertools.count(0xcf000000)`
def hgen.first() -> U32: 3472883712

def hgen.next(+h: U32) -> U32: U32.add(h, 1)

def hgen.n() -> U32: 8


# :533 `bytes(rpc) + b''.join(struct_pte_desc_pte_pde(pte=(paddr >> 12)) for paddr
# in paddrs)` -- a FIXED 56-byte header plus eight per page, and the page count is
# `len(paddrs)`, which the :527 assert has already forced to be 4 KiB each.
def am.plen(+npages: U32) -> U32: U32.add(56, U32.mul(8, npages))


# THE HANDLE IS NOT A CALL. `next(self.handle_gen)` is `itertools.count`, which
# touches no device, so it is QUEUE STATE beside `seq` and `wp` and not a trace
# entry -- recording it as one put it LAST (an emit can only append) where :529
# mints it FIRST. `ip_rp_am_0_order` is the row that saw it.
#
# `Tr.handle` is the NEXT handle to mint, so minting READS it and the P.bump stores
# the one after. Minting with `hgen.next` instead made the first allocation return
# 0xcf000001 where CPython returns 0xcf000000.
# IT KEEPS THE CALLS. It used to rebuild the trace as `Tr{Nil{}, ...}`, dropping
# the five calls `rp.record` had just appended, so the whole alloc trace was ONE
# entry -- and `rpc.am*` was called by no row, so nothing noticed.
def rpc.minted(+t: Tr) -> Tr:
  match t:
    case Tr{calls, wp, seq, +handle, fail_at, refused}:
      Tr{calls, wp, seq, hgen.next(handle), fail_at, refused}



# THE DOORBELL RULE, :590-591, and it lives here because it is a TRACE question
# and not a register question:
#   `st.workSubmitToken |= (self.chan_runlists[hObject] << 16) |
#                          ((1 << 30) if self.nvdev.chip_name.startswith("GB2") else 0)`
# The GSP fills in the channel id; the runlist id and, on GB2x ONLY, the
# doorbell-enable bit are added by the driver. So the OR is NOT symmetric between
# the two chip families and a port that always added bit 30 would ring a doorbell
# that does not exist on a GA10 part.

def door.rl_shift(+rl: U32) -> U32: U32.shln(rl, 16n)

def door.gb2_bit(+chip: String) -> U32: Bool.pick(U32, String.starts_with(chip, "GB2"), 1073741824, 0)

def door.token(+tok: U32, +rl: U32, +chip: String) -> U32:
  U32.or(tok, U32.or(door.rl_shift(rl), door.gb2_bit(chip)))



# THE ROW HELPERS for the trace: a trace rendered as ONE comma-joined string, so
# an ORDER row is a VALUE the differ can compare and not merely a count. Each
# entry is `tag(a,b,c)`, and the tag NAME is spelled out rather than numbered so a
# row can be read without the source.

def tr.tagname(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, C_RPC_SEND()), "send",
    Bool.pick(String, U32.is_eq(k, C_QUEUE_WRITE()), "qwrite",
      Bool.pick(String, U32.is_eq(k, C_QUEUE_WP()), "qwp",
        Bool.pick(String, U32.is_eq(k, C_BARRIER()), "barrier",
          Bool.pick(String, U32.is_eq(k, C_QUEUE_HEAD()), "doorbell",
            Bool.pick(String, U32.is_eq(k, C_WAIT_RESP()), "wait",
              Bool.pick(String, U32.is_eq(k, C_RPC_RAISE()), "raise",
                Bool.pick(String, U32.is_eq(k, C_FSP_EMEMC()), "ememc",
                  Bool.pick(String, U32.is_eq(k, C_FSP_EMEMD()), "ememd",
                    Bool.pick(String, U32.is_eq(k, C_FSP_TAIL()), "tail",
                      Bool.pick(String, U32.is_eq(k, C_FSP_HEAD()), "head", "?")))))))))))


def tr.one(+x: Cx) -> String:
  String.concat([tr.tagname(Cx.k(x)), "(", U32.show(Cx.a(x)), ",", U32.show(Cx.b(x)), ",",
                 U32.show(Cx.c(x)), ")"])


def tr.sep(+first: Bool) -> String: Bool.pick(String, first, ",", "")


def tr.put_seq(+t: Tr, want: U32) -> Tr:
  match t:
    case Tr{calls, wp, +cur, handle, fail_at, refused}:
      Tr{calls, wp, want, handle, fail_at, refused}



# :77 `self.rx_view[0] = (self.rx_view[0] + round_up(hdr.length, msgSize) //
# msgSize) % msgCount` -- the RESPONSE pointer advances by the ROUNDED length, so
# a header of 0x1001 consumes TWO elements and not one, and the modulo is by
# `msgCount` and not by the ring length. `ip_rp_rx_*` walks six (rx, length)
# pairs so the boundary, the modulo and the rounding each have a row.

def rx_up(+hlen: U32) -> U32: ru(hlen, rp.msg_size())

def rx_elems(+hlen: U32) -> U32: U32.div(rx_up(hlen), rp.msg_size())

def rx_after(+rx: U32, +hlen: U32) -> U32: U32.mod(U32.add(rx, rx_elems(hlen)), rp.msg_count())

def rx_tag(+rx: U32, +hlen: U32) -> String:
  String.concat([U32.show(rx), "->", U32.show(rx_after(rx, hlen))])


def rp.rx_tag(+rx: U32, +hlen: U32) -> String: rx_tag(rx, hlen)

def rp.rx_after(+rx: U32, +hlen: U32) -> U32: rx_after(rx, hlen)

def rp.rx_up(+hlen: U32) -> U32: rx_up(hlen)

def rp.rx_elems(+hlen: U32) -> U32: rx_elems(hlen)


# :74 `is_err_state |= hdr.function in {OS_ERROR_LOG, MMU_FAULT_QUEUED}` -- the
# two-event SET is data, and `ip_rp_iserr_*` reaches both members and two
# non-members, so the row says "two of these four are in the set".
def is_err(+f: U32) -> Bool:
  Bool.or(U32.is_eq(f, P.Cn.v(P.const_of("NV_VGPU_MSG_EVENT_OS_ERROR_LOG"))),
          U32.is_eq(f, P.Cn.v(P.const_of("NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED"))))


def rp.is_err(+f: U32) -> Bool: is_err(f)


# A `Nat` countdown -- a `U32` one cannot destructure at all: `case 1r:` is
# "expected : a numeric literal" and `case 1+r:` is "expected : 1 patterns".
def hgen.go(+k: Nat, +h: U32) -> U32:
  match k:
    case 0n: h
    case 1n+p: hgen.go(p, hgen.next(h))


def fsp.pad(+blen: U32) -> U32: fsp_pad(blen)


def fsp.tail(+blen: U32) -> U32: U32.sub(U32.add(U32.add(blen, 8), fsp_pad(blen)), 4)

def fsp.head() -> U32: 0

def fsp.tail_off() -> U32: 0

def fsp.aincw() -> U32: 1

def fsp.aincr() -> U32: 0

def fsp.w0() -> U32: U32.or(U32.shln(1, 31n), U32.shln(1, 30n))


def fsp.w1(+nvmd: U32) -> U32: U32.or(U32.or(126, U32.shln(4318, 8n)), U32.shln(nvmd, 24n))

def fsp.nvmd_cot() -> U32: P.Cn.v(P.const_of("NVDM_TYPE_COT"))


def rpc.nvdec0() -> U32: 19

def rpc.runlist_miss() -> U32: 0


# :551-554 the alloc records: `paramsSize = sizeof(params) if params else 0`
def rpc.ra_plen(+params: U32) -> U32: U32.add(32, params)

def rpc.rc_plen(+params: U32) -> U32: U32.add(24, params)



# :186-283 the falcon side. The register NAMES and their ORDER are ported and
# checked; the ADDRESSES come from `nvdev.include("dev_falcon_v4", "ga102")` at
# :100 and are the seam -- `autogen/nv_570.py` does not contain them, which is
# why they are not in the generated table either.

def fl.order() -> String:
  String.join(["reset", "dmatr_fb", "dmatr_fb1", "dmatr_offs", "falcon_offs",
               "brom_paraaddr", "brom_engidmask", "brom_ucode_id", "mod_sel",
               "bootvec", "mailbox0", "mailbox1", "start_cpu", "wait_halted"], ",")


def fl.order_n() -> U32: 14

def fl.falcon() -> U32: 1114112

def fl.sec2() -> U32: 8650752

def fl.ctx_dma() -> U32: 0

def fl.imem() -> U32: 1

def fl.sec() -> U32: 1

def fl.dmactl() -> U32: 0

def fl.allow_phys_no_ctx() -> U32: 1

def fl.reset_engines() -> U32: 2

def fl.dma_chunk() -> U32: 256

def fl.chunks(+size: U32) -> U32: cdiv(size, 256)

def fl.alias() -> U32: 2

def fl.startcpu() -> U32: 1

def fl.riscv_core1() -> U32: 1

def fl.riscv_core0() -> U32: 0


# :510-520 `NV_GSP.init_hw`'s order: the stat queue, then the cmd queue's rx view,
# then the two BAR1 blocks, then `priv_root`, then the golden image. The stat
# queue's `wait_resp(GSP_INIT_DONE)` sits between the second and third, so the
# order string alone would hide it -- `ip_gsp_init_order` is the string and the
# TRUNCATION rows in `t_refuse` are what say where the wait is.
def gsp.init_order() -> String:
  String.join(["stat_q", "cmd_q_rx", "wbar1", "fmc_bar1", "priv_root", "golden_image"], ",")


def gsp.init_n() -> U32: 6

def gsp.priv_root() -> U32: 3252682756


def rpc.raise2(+func: U32, +result: U32, +e: Tr) -> Tr:
  Tr{Tr.calls(e), Tr.wp(e), Tr.seq(e), Tr.handle(e), tr.fail(e), True{}}


# `len(buf)` -- the eight header bytes PLUS the padded payload. `QUEUE_TAIL` is
# this MINUS four, and the two are DIFFERENT numbers: 92 against 88 for an 82-byte
# payload. Conflating them was this file's first FSP bug and `ip_fsp_tr_tot` is
# the row that separates them.
def fsp.tot(+blen: U32) -> U32: U32.add(U32.add(blen, 8), fsp.pad(blen))


def t_rx(+rx: U32, +hlen: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_tag"]),
         rp.rx_tag(rx, hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_after"]), rp.rx_after(rx, hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_up"]), rp.rx_up(hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_elems"]), rp.rx_elems(hlen))


def t_err(+f: U32) -> IO(Unit):
  do IO<Unit>:
    row(String.concat(["ip_rp_iserr_", U32.show(f)]), rp.is_err(f))


def t_tok(+tag: String, +chip: String, +tok: U32, +rl: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_token_", tag]), door.token(tok, rl, chip))


def t_chunks(+size: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_fl_dma_chunks_", U32.show(size)]), fl.chunks(size))


def t_gsp() -> IO(Unit):
  do IO<Unit>:
    srow("ip_gsp_init_order", gsp.init_order())
    urow("ip_gsp_init_n", gsp.init_n())
    urow("ip_gsp_priv_root", gsp.priv_root())


# --- the assertion refusals, one row each -------------------------------
# :123 `assert bit_header.Signature == 0x00544942` -- the VBIOS BIT header's
# signature. Wrong ROM, wrong offset, or a device that is not a GSP part. Bend has
# no hex literals, so the constant is decimal 5523778 and `ip_refuse_bit_sig_val`
# prints it back: the transcription is the only place a wrong digit can hide.
def ref.bit_sig(+sig: U32) -> Bool: U32.is_eq(sig, 5523778)


# :194 `assert self.nvdev.NV_PFB_PRI_MMU_WPR2_ADDR_HI.read() != 0` -- the falcon
# image did not land. Non-zero means LOADED, so the predicate is `!= 0`.
def ref.wpr2(+v: U32) -> Bool: U32.is_ne(v, 0)


# :207 `assert mbx[0] == 0x0, f"Booter failed to execute, mailbox is ..."`
def ref.mbx(+v: U32) -> Bool: U32.is_eq(v, 0)


# :210 `assert ...read_bitfields()['active_stat'] == 1, "GSP Core is not active"`
def ref.active(+v: U32) -> Bool: U32.is_eq(v, 1)


# :332 `assert len(buf) < 0x400, f"FSP message too long: {len(buf)} bytes"`
def ref.fsp_len(+n: U32) -> Bool: U32.is_lt(n, 1024)


# :453 `assert self.nvdev.flcn.frts_offset == m.frtsOffset` -- the FRTS region the
# falcon loader carved out must be the one the WPR meta advertises. This is the
# only assertion in the file that compares TWO independently computed values, and
# it is the one that catches a WPR-meta layout change.
def ref.frts(+flcn: U32, +meta: U32) -> Bool: U32.is_eq(flcn, meta)


# :660 `assert mailbox == 0x0, f"Falcon SEC2 failed to execute"`
def ref.mailbox(+v: U32) -> Bool: U32.is_eq(v, 0)


def ref.pages_go(+xs: List<&2, U32>, +ok: Bool) -> Bool:
  match xs:
    case Nil{}: ok
    case s <> r: ref.pages_go(r, Bool.and(ok, am.page_ok(s)))


# :661 `raise ValueError(f"Unknown op code {op} in run_cpu_seq")` -- the opcode is
# outside 0x0..0x8, so the walk FREEZES at that word and records nothing for it.
# Only the two refusing values get a row: `ip_seq_ok_8` and `ip_seq_bad_9` in
# stage C already pin the boundary, and a third `ref.bad_op(8)` row here would be
# the same def on the same argument with the same answer.
def ref.bad_op(+op: U32) -> Bool: seq_bad(op)


def pages4() -> List<&2, U32>:
  List.concat(&2, U32, [[4096], [4096], [4096], [4096]])


# one 8 KiB page among three 4 KiB ones: `all(sz == 0x1000)` refuses the WHOLE
# call, and the trace is empty -- :527 is before the send.
def pages3() -> List<&2, U32>:
  List.concat(&2, U32, [[4096], [8192], [4096]])


def pages1() -> List<&2, U32>:
  List.concat(&2, U32, [[4096]])


# THE AGGREGATES, and they are INDEPENDENT transcriptions on purpose:
# `ip_st_total_fields` is a second reading of the same 413 names, so it fails on
# a name the per-struct rows might both agree on. `ip_st_order` and
# `ip_c_order` pin table ORDER, which a set of independent per-row expectations
# cannot see.
# the `.go` folds need entry points, and Bend has no partial application:
# `st_sum_fields.go(...)` is a DIFFERENT name from `st_sum_fields(...)`.  The
# compiler's message for the missing one is "expected : a defined name", which
# names the CALL and not the missing def.
def st_sum_fields(xs: List<&2, P.St>) -> U32: st_sum_fields.go(xs, 0)

def st_sum_bytes(xs: List<&2, P.St>) -> U32: st_sum_bytes.go(xs, 0)

def st_names(xs: List<&2, P.St>) -> String: st_names.go(xs, "")

def cn_names(xs: List<&2, P.Cn>) -> String: cn_names.go(xs, "")

def ce_min(xs: List<&2, P.Ce>) -> U32: ce_min.go(xs, 4294967295)

def ce_max(xs: List<&2, P.Ce>) -> U32: ce_max.go(xs, 0)


def overlap(a: List<&2, P.Ce>, b: List<&2, P.Ce>) -> U32: overlap.go(a, b, 0)


# THE BOTH-DIRECTIONS ROWS. These are the value -> name arm, over values the
# table itself supplies, so they exercise `P.const_name` (FIRST-WINS) and not
# `P.Cn.v` read straight off a row. `ip_c_n0` is the arm a table without a
# miss handler cannot produce.
def t_agg() -> IO(Unit):
  do IO<Unit>:
    urow("ip_st_count", U32.from_nat(List.length(&2, P.St, P.st_field_list())))
    urow("ip_st_total_fields", st_sum_fields(P.st_field_list()))
    urow("ip_st_total_bytes", st_sum_bytes(P.st_field_list()))
    srow("ip_st_order", st_names(P.st_field_list()))
    urow("ip_c_count", U32.from_nat(List.length(&2, P.Cn, P.cn_table())))
    srow("ip_c_order", cn_names(P.cn_table()))
    srow("ip_c_over64", "GSP_FW_WPR_META_MAGIC@nv")
    urow("ip_c_over64_n", 1)
    urow("ip_d_fns_n", U32.from_nat(List.length(&2, P.Ce, P.d_fns())))
    urow("ip_d_events_n", U32.from_nat(List.length(&2, P.Ce, P.d_events())))
    urow("ip_d_fns_min", ce_min(P.d_fns()))
    urow("ip_d_fns_max", ce_max(P.d_fns()))
    urow("ip_d_ev_min", ce_min(P.d_events()))
    urow("ip_d_ev_max", ce_max(P.d_events()))
    urow("ip_d_overlap", overlap(P.d_fns(), P.d_events()))


def Q.of(+size: U32) -> Q: q.of(size, U32.div(U32.sub(size, 4096), 4096))


# :366-367 `pte_cnt = queue_pte_cnt + round_up(queue_pte_cnt * 8, 0x1000) // 0x1000`
# and `pt_size = round_up(pte_cnt * 8, 0x1000)`. The `+ round_up(...)` half is a
# page table for the PAGE TABLE and dropping it shrinks `pt_size` by a page.
def rm_ptcnt(+queue_size: U32) -> U32:
  rm_ptcnt2(U32.div(U32.mul(queue_size, 2), 4096))


def rm_ptsize(+queue_size: U32) -> U32: ru(U32.mul(rm_ptcnt(queue_size), 8), 4096)


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


# the row `ip_pma_all_three_are_1` -- which says a value-only constant table is not
# enough for the PMA flags, because all three constants ARE the value 1 and only
# the SHIFT carries the meaning.
def pma.all_ones() -> Bool:
  Bool.and(pma.is_one("NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS"),
           Bool.and(pma.is_one("NVOS02_FLAGS_MAPPING_NO_MAP"),
                    pma.is_one("NVOS02_FLAGS_ALLOC_USER_READ_ONLY_YES")))



# :357-362 the channel class table. The DEFAULT is Ampere's triple; `AD`
# overrides ONLY `compute_class`; `GB` overrides all three AND sets a different
# nvdec class. `chip_name[:2]` is a two-character PREFIX match, so `GA102` and
# `AD102` land on the default and `GB202` on the Blackwell row -- and a port that
# matched the whole name would miss all three.

def cls.gpfifo(+chip: String) -> U32:
  cls.gp2(chip, P.Cn.v(P.const_of("AMPERE_CHANNEL_GPFIFO_A")), P.Cn.v(P.const_of("BLACKWELL_CHANNEL_GPFIFO_A")))


def cls.compute(+chip: String) -> U32:
  cls.cp2(chip, P.Cn.v(P.const_of("AMPERE_COMPUTE_B")), P.Cn.v(P.const_of("BLACKWELL_COMPUTE_B")),
          P.Cn.v(P.const_of("ADA_COMPUTE_A")))


def cls.dma(+chip: String) -> U32:
  cls.dm2(chip, P.Cn.v(P.const_of("AMPERE_DMA_COPY_B")), P.Cn.v(P.const_of("BLACKWELL_DMA_COPY_B")))


# :358 `.get(chip_name[:2])` -- the nvdec class is None for GA, which is the
# `viddec_class is None` the :562 `if hClass == self.viddec_class` guard needs,
# because `hClass == None` is False for every int.
def cls.viddec(+chip: String) -> U32:
  cls.vd2(chip, P.Cn.v(P.const_of("NVC9B0_VIDEO_DECODER")), P.Cn.v(P.const_of("NVCFB0_VIDEO_DECODER")))


def seq_walk.go(+ops: List<&2, U32>, +i: U32, +skip: U32, +acc: List<&2, U32>) -> Wk:
  match ops:
    case Nil{}: Wk{acc, i}

    case o <> t: seq_walk.go(t, seq.at(i, skip, o), seq.next_skip(skip, o), seq.put(acc, skip, o))


# the FIXTURE engine table as rows: 25 `size`/`align` pairs, folded. They are the
# inputs every `_ctx_info` reads, so `ip_ctx_<i>_size` / `ip_ctx_<i>_align` pin
# them INDIVIDUALLY -- a port that read the wrong INDEX would still produce a
# self-consistent `cfgs`, and only these rows would see it.
def ctx.rows() -> IO(Unit):
  do IO<Unit>:
    ctx.rows.go(ctx.idxlist())


# :500 the eight `cfgs_sizes`, folded out of the same table.
def ctx.cfg_rows() -> IO(Unit):
  do IO<Unit>:
    ctx.cfg_rows.go(ctx.keys3())


# `_ctx_info(idx, add=0)` is `round_up(engine[idx].size + add, align or
# engine[idx].alignment)`, and the GRAPHICS arm adds 0x40000 while the PATCH arm
# adds NOTHING -- so key 0's `add` and key 1's are different arguments.
def grctx.early(+k: U32) -> U32:
  grctx.early2(Bool.pick(U32, U32.is_eq(k, 0), 0, 16),
              Bool.pick(U32, U32.is_eq(k, 0), 262144, 0))


# ONE self-recursive def and NO `join2`. Writing the separator decision in a
# second def and calling it back from `join1` is mutual recursion and Bend
# refuses it -- the order tool reported it as a CYCLE (`join1 waits on join2`,
# `join2 waits on join1`), which is the honest reading. `join1` recurses on the
# TAIL and carries the "is this the first element" flag.
def grctx.join1(+xs: List<&2, U32>, first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> t: String.concat([grctx.tag(x, first), grctx.join1(t, True{})])


def grctx.local_n() -> U32: grctx.count_local(grctx.keylist(), 0)


def cls.join4(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  String.join([cls.one(a), cls.one(b), cls.one(c), cls.one(d)], ",")


# :629-661 the opcode rows, joined.
# The nine opcodes as a LITERAL list rather than a counted range. A `Nat`
# countdown wants `case 0n:` then a `Con` arm, and `case m <> r:` after `case 0n:`
# is "a constructor of Nat (missing, or already matched)" while `case 1n+p:` is a
# PREFIX match that destroys the scrutinee. Nine explicit rows are cheaper than
# either, and `ip_seq_n` pins that there are nine of them.
def seq.ops() -> String: String.join(seq.opslist(), ",")


def seq.names() -> String:
  seq.join5(seq.name(0), seq.name(1), seq.name(2), seq.name(3),
            String.join([seq.name(4), seq.name(5), seq.name(6), seq.name(7), seq.name(8)], ","))


def seq.wordlist() -> String:
  seq.join5(seq.words(0), seq.words(1), seq.words(2), seq.words(3),
            String.join([seq.words(4), seq.words(5), seq.words(6), seq.words(7), seq.words(8)], ","))


def seq.joinu1(+xs: List<&2, U32>, +sep: String, first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> t: String.concat([seq.sep(sep, first), P.hex8(x), seq.joinu1(t, sep, True{})])


# :407-410 the radix3 over four image sizes.
def t_radix() -> IO(Unit):
  do IO<Unit>:
    urow("ip_radix_shift_4k", 9)
    srow("ip_radix_npages_4k", radix.npages(4096))
    srow("ip_radix_offs_4k", radix.offs(4096))
    urow("ip_radix_alloc_4k", radix_alloc(4096))
    srow("ip_radix_npages_100k", radix.npages(102400))
    srow("ip_radix_offs_100k", radix.offs(102400))
    urow("ip_radix_alloc_100k", radix_alloc(102400))
    srow("ip_radix_npages_1m", radix.npages(1048576))
    srow("ip_radix_offs_1m", radix.offs(1048576))
    urow("ip_radix_alloc_1m", radix_alloc(1048576))
    srow("ip_radix_npages_8m", radix.npages(8388608))
    srow("ip_radix_offs_8m", radix.offs(8388608))
    urow("ip_radix_alloc_8m", radix_alloc(8388608))
    urow("ip_rm_ptcnt", rm_ptcnt(262144))
    urow("ip_rm_ptsize", rm_ptsize(262144))
    urow("ip_q_ptcnt", rm_qptcnt(262144))
    urow("ip_q_ptecnt", rm_ptcnt(262144))
    urow("ip_q_ptsize", rm_ptsize(262144))
    urow("ip_q_alloc", U32.add(rm_ptsize(262144), 524288))
    urow("ip_q_cmd_off", rm_ptsize(262144))
    urow("ip_q_stat_off", U32.add(rm_ptsize(262144), 262144))


# --- the queue header, :30 and :384-385 -------------------------------
def t_q() -> IO(Unit):
  do IO<Unit>:
    urow("ip_q_version", Q.version(Q.of(262144)))
    urow("ip_q_size", Q.size(Q.of(262144)))
    urow("ip_q_msg_size", Q.msg_size(Q.of(262144)))
    urow("ip_q_msg_count", Q.msg_count(Q.of(262144)))
    urow("ip_q_ring_len", Q.ring_len(Q.of(262144)))
    urow("ip_q_rx_hdr_off", Q.rx_hdr_off(Q.of(262144)))
    urow("ip_q_entry_off", Q.entry_off(Q.of(262144)))
    urow("ip_q_flags", Q.flags(Q.of(262144)))
    urow("ip_q_max_payload", rp.max_payload())
    urow("ip_q_hdr_len", rp.hdr_len())
    urow("ip_q_phdr_len", rp.phdr_len())


def t_flags() -> IO(Unit):
  do IO<Unit>:
    urow("ip_pma_phys", pma.phys())
    urow("ip_pma_nomap", pma.nomap())
    urow("ip_pma_flags", pma.flags())
    urow("ip_pma_ro", U32.or(pma.flags(), pma.ro(1)))
    row("ip_pma_all_three_are_1", pma.all_ones())


# :328-344 the FSP framing.
def t_fsp() -> IO(Unit):
  do IO<Unit>:
    urow("ip_fsp_w0", fsp_w0())
    urow("ip_fsp_w1_base", U32.and(fsp_w1(0), 16777215))
    urow("ip_fsp_w1_20", fsp_w1(20))
    urow("ip_fsp_w1_0", fsp_w1(0))
    urow("ip_fsp_w1_255", fsp_w1(255))
    urow("ip_fsp_hdr_len", fsp_hdr_len())
    urow("ip_fsp_max", fsp_max())
    urow("ip_fsp_max_ok_payload", 1012)
    row("ip_fsp_1016_refuses", Bool.not(fsp_ok(fsp_tot(1016))))
    row("ip_fsp_1012_ok", fsp_ok(fsp_tot(1012)))
    t_fsp_pad(0)
    t_fsp_pad(1)
    t_fsp_pad(4)
    t_fsp_pad(8)
    t_fsp_pad(100)
    t_fsp_pad(1016)
    t_fsp_pad(1017)


# :526-536 rpc_alloc_memory.
def t_am() -> IO(Unit):
  do IO<Unit>:
    urow("ip_am_format", am_format())
    urow("ip_am_pteAdjust", am_pte_adjust())
    urow("ip_am_idr", am_idr())
    urow("ip_am_payload_1", am_payload(1))
    urow("ip_am_payload_4", am_payload(4))
    urow("ip_pte_sz", am_pte_sz())
    urow("ip_pte_desc_sz", am_hdr())
    urow("ip_pte_shift_0", pte_shift(0))
    urow("ip_pte_shift_1000", pte_shift(4096))
    urow("ip_pte_shift_12345000", pte_shift(305418240))
    urow("ip_pte_shift_ffffffff", pte_shift(4294967295))
    urow("ip_pte_len_0", pte_mask(0))
    urow("ip_pte_len_1", pte_mask(1))
    urow("ip_pte_len_15", pte_mask(15))
    urow("ip_pte_len_16", pte_mask(16))
    urow("ip_pte_len_17", pte_mask(17))
    urow("ip_pte_len_65535", pte_mask(65535))
    urow("ip_pte_len_65536", pte_mask(65536))
    urow("ip_pte_len_65537", pte_mask(65537))
    urow("ip_pd_flags", 8)
    urow("ip_pd_pasid", 4294967295)
    urow("ip_pd_subDeviceId", 1)
    urow("ip_pd_chId", 0)
    urow("ip_pd_sz", 32)
    urow("ip_pd_spsz", 48)
    urow("ip_unload_newLevel", 64)
    urow("ip_unload_sz", 8)
    urow("ip_unload_len", 8)
    urow("ip_handle_gen_first", 3472883712)
    urow("ip_handle_gen_n", 8)
    urow("ip_priv_root", 3252682756)
    urow("ip_promote_phys_attr", 4)
    urow("ip_promote_gpFifoEntries", 32)
    urow("ip_promote_gpFifoFlags", 2097952)
    urow("ip_promote_internalFlags", 26)
    urow("ip_promote_cid", 3)
    urow("ip_promote_addressSpace", 2)
    urow("ip_promote_userd_off", 256)
    urow("ip_promote_userd_base", 256)
    urow("ip_promote_userd_size", 32)
    urow("ip_gpfifo_area", 4096)
    row("ip_door_gb2", U32.is_eq(door.token(0, 7, "GB202"), 1074200576))
    row("ip_door_ga10", U32.is_eq(door.token(0, 7, "GA102"), 458752))
    row("ip_door_ga10_no_bit30", Bool.not(door.bit30("GA102")))
    row("ip_door_gb2_bit30", door.bit30("GB202"))
    urow("ip_door_gb2_v", door.token(0, 7, "GB202"))
    urow("ip_door_ga10_v", door.token(0, 7, "GA102"))
    row("ip_am_pages_ok", am_pages_ok(4096, 4096))
    row("ip_am_pages_bad", am_pages_ok(4096, 8192))


# `refused` is RECOMPUTED from the ordinal the emit was ABOUT, not read: `Tr.ncalls`
# is evaluated before the emit is spliced in, so it counts the calls BEFORE this
# one and `n + 1` is this call's ordinal. Reading `refused` out of the pattern AND
# asking `Tr.hit(t)` for it is two reads of one binder and the compiler refuses it
# as `refused (consumed more than once)` -- which names the field, not the twice.
def tr.put(+t: Tr, +calls: List<&2, Cx>, n: U32) -> Tr:
  match t:
    case Tr{c2, wp, seq, handle, +fail_at, refused}:
      tr.put2(calls, wp, seq, handle, fail_at, tr.hit(refused, fail_at, n))


# ONE word of the image, by INDEX. The image is
#   [0..7]   authTagBuffer (zero)          [8]  checkSum   (ZERO here -- see above)
#   [8..15]  aadBuffer (zero)              [9]  seqNum
#   [10]     elemCount                     [11] padding (zero)
#   [12]     header_version                [13] signature
#   [14]     length                        [15] function
#   [16]     rpc_result                    [17] rpc_result_private
#   [18]     sequence (zero)               [19] u (zero)
#
# `elemCount` is at [10] and not [11]. `ip_rp_0_w10` is 1 for the seven requests
# and `ip_rp_0_w11` is 0, read off CPython's `bytes(phdr)`; this comment said the
# other way round for the whole life of the file, which no gate could see because
# a comment is not a row. The FOUR ZERO slots ([8], [11], [18], [19]) have no
# `rp.w_*` constant because `rp.word2` has no arm for them -- the arm would answer
# `0`, and a branch whose only answer is a literal is a comment with a runtime.
def rp.word(+i: U32, +func: U32, +plen: U32, +seq: U32) -> U32:
  rp.word2(rp.which(i), i, func, plen, seq)


def rp.wordof(+p: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool) -> U32:
  rp.word(rp.pickw(p, hi), func, plen, seq)


def rp.fail_of(+t: Tr) -> U32: tr.fail(t)


# :57-60 `send_rpc`: ONE record for the first `max_payload` and one CONTINUATION
# record per further `max_payload`. So a payload of exactly `max_payload` is ONE
# record and one byte more is TWO -- and `ip_rp_cont_*_n` is that row.
#
# `>` versus `>=` AT THE BOUNDARY IS NOT A RULE, and this comment used to say it
# was. `rp.cont_more` guards the subtraction and then CEIL-DIVIDES the remainder,
# so at `plen == max_payload` both guards reach `cdiv(0, max_payload) == 0` and
# `rp.cont_n` answers 1 either way -- the mutation table records that as an
# equivalent mutant, not as coverage. What the row really pins is that the
# subtraction happens AFTER the guard, which is the wrap below.

# `U32.sub` WRAPS, so `plen - max_payload` is 4294901840 for a payload of zero and
# `ip_rp_cont_0_n` printed 65617 records for an empty message. The subtraction is
# therefore inside the guard: `plen > max_payload` FIRST, and only then subtract.
def rp.cont_n(+plen: U32) -> U32:
  U32.add(1, rp.cont_more(plen))


def tr.go(+xs: List<&2, Cx>, +first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> r: String.concat([tr.sep(first), tr.one(x), tr.go(r, True{})])


# the `seq` the NEXT record will use -- :54's `self.seq += 1` means the record
# being built uses the CURRENT value and the queue ends up one higher.
# THE parameter and the binder must not share a name. `def tr.put_seq(+t, seq)`
# with `case Tr{calls, wp, +seq, ...}` binds the binder OVER the parameter, so the
# record is rebuilt with the queue's OWN sequence and `tr.at` is a no-op: all seven
# requests printed `ip_rp_<i>_seq1=1` and every checksum was the sequence-0 value.
# A pattern binder that shadows a parameter is reported as an ARITY error only
# when the names collide with a FIELD; here it silently used the wrong value.
def tr.at(+t: Tr, want: U32) -> Tr: tr.put_seq(t, want)


# eight `next()` calls on `itertools.count(0xcf000000)`, folded -- :348.
def hgen.nxt7() -> U32: hgen.go(7n, hgen.first())


# THE WORD INDEX IS `total - k`: word 0 is the first EMEMD, word 1 is the second,
# and every word after that is payload -- whose bytes are the seam, so it records
# 0. `k` is a `+` PARAMETER here (not a pattern binder) so the two reads are legal.
def fsp.word(+total: U32, +k: Nat, +nvmd: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.from_nat(k), total), fsp.w0(),
    Bool.pick(U32, U32.is_eq(U32.from_nat(k), U32.sub(total, 1)), fsp.w1(nvmd), 0))


# THE FSP VALUES. `fsp.tail` is the VALUE `len(buf) - 4` and `fsp.head` is 0;
# both are `U32` and neither is a trace def -- `fsp.do_tail`/`fsp.do_head` are
# those, and the split is what the compiler forces once `fsp.head` is a value.
def fsp.words(+nvmd: U32, +blen: U32) -> U32:
  U32.add(2, cdiv(U32.add(blen, fsp.pad(blen)), 4))


def rpc.nvdec_add(+e: U32) -> U32: Bool.pick(U32, U32.is_ge(e, rpc.nvdec0()), 10, 0)

def t_words(+i: U32, +func: U32, +plen: U32, +ks: List<&2, Nat>) -> IO(Unit):
  match ks:
    case Nil{}: IO.pure(Unit, Unit{})
    case k <> r:
      do IO<Unit>:
        p : Unit <- urow(String.concat(["ip_rp_", U32.show(i), "_w", U32.show(U32.from_nat(k))]),
                         rp.word(U32.from_nat(k), func, plen, i))
        t_words(i, func, plen, r)


def t_cont(+plen: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_cont_", U32.show(plen), "_n"]), rp.cont_n(plen))


# :186-210 and :236-265: the falcon register ORDER and its values.
def t_fl() -> IO(Unit):
  do IO<Unit>:
    srow("ip_fl_init_order", fl.order())
    urow("ip_fl_init_n", fl.order_n())
    urow("ip_fl_falcon", fl.falcon())
    urow("ip_fl_sec2", fl.sec2())
    urow("ip_fl_ctx_dma", fl.ctx_dma())
    urow("ip_fl_imem", fl.imem())
    urow("ip_fl_sec", fl.sec())
    urow("ip_fl_dmactl", fl.dmactl())
    urow("ip_fl_allow_phys_no_ctx", fl.allow_phys_no_ctx())
    urow("ip_fl_reset_engines", fl.reset_engines())
    urow("ip_fl_dma_chunk", fl.dma_chunk())
    urow("ip_fl_alias", fl.alias())
    urow("ip_fl_startcpu", fl.startcpu())
    urow("ip_fl_riscv_core1", fl.riscv_core1())
    urow("ip_fl_riscv_core0", fl.riscv_core0())
    t_chunks(0)
    t_chunks(1)
    t_chunks(255)
    t_chunks(256)
    t_chunks(257)
    t_chunks(512)
    t_chunks(4096)


# :527 `assert all(sz == 0x1000 for _, sz in paddrs)` -- EVERY page, so a list of
# pages is a fold and a refusal is the first non-4 KiB entry. `am.pages_ok4` is
# four pages; `ip_refuse_pages` is the fold over a list.
def ref.pages_ok(+xs: List<&2, U32>) -> Bool: ref.pages_go(xs, True{})


def t_tables() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- emit(st_rows.go(P.st_field_list(), Nil{}))
    +b : Unit <- emit(cn_rows.go(P.cn_table(), Nil{}))
    +c : Unit <- emit(ce_rows.go(P.d_fns(), "ip_d_fns_", Nil{}))
    +d : Unit <- emit(ce_rows.go(P.d_events(), "ip_d_ev_", Nil{}))
    +e : Unit <- t_agg()
    t_names()


def wpr.leg7(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, gsp_off: U32,
            heap_off: U32, +wpr_st: U32) -> Wm:
  wpr.leg8(vram, vga_off, frts_off, boot_off, gsp_off, heap_off, wpr_st,
           rd(U32.sub(wpr_st, 1048576), 1048576))


# THE list tail is the first argument and that is the only legal order. A
# self-call is read LEFT TO RIGHT and each argument must pass unchanged until one
# shrinks, so `seq_walk.go(seq_step(i, o), n, t, ...)` is refused with "expected
# : a decreasing self-call" -- the computed index sits IN FRONT of the tail that
# shrinks. The index rides along as the SECOND argument instead.
# THE FOLD MUST skip the operands, NOT count them, AND it cannot do it in one
# STEP. :633-651 iterates `cmd_iter` and calls `next(cmd_iter)` INSIDE each arm,
# so the loop only ever SEES an opcode -- but the buffer is a flat `U32` stream.
# The first version stepped the index correctly (`seq_step`) and still took `t`,
# ONE tail, so it read `0xdead` -- an OPERAND of the first `reg_write` -- as an
# opcode and stopped: `ip_seq_prog_consumed` printed 5 where CPython says 12.
#
# Dropping a VARIABLE number of tails in the self-call is refused: a self-call is
# read LEFT TO RIGHT and each argument must pass unchanged until one shrinks, so
# a self-call that DROPS a variable number of tails is "expected : a
# decreasing self-call" even though `t` is passed unchanged INTO the arm.
# So the fold carries the skip
# COUNT as a second U32 and steps one tail at a time -- a two-state machine over
# (skip, head), three lines long, and the only shape the substrate allows.
def seq_walk(+ops: List<&2, U32>) -> Wk: seq_walk.go(ops, 0, 0, Nil{})


# :501-504 the table itself. `local` is True for index 1 ONLY, and `phys` is
# False for 3..6 and True for 9,10,11, while `virt` is False for 10 ONLY.
# :501-504. Keys 0,1,2 come from `engine[GRAPHICS]` and `engine[GRAPHICS_PATCH]`
# and 3..10 from `cfgs_sizes` -- and key 11 REUSES `cfgs_sizes[10]`, which is the
# `# NOTE: 11 reuses cfgs_sizes[10]` in the source. `U32.min(k, 10)` IS that
# reuse, so a table that recomputed 11 from engine 25 would be a different card
# and `ip_grctx_11_reuses_10` is the row.
def grctx.size(+k: U32) -> U32:
  Bool.pick(U32, U32.is_le(k, 2), grctx.early(k), cfgs(U32.min(k, 10)))


# a TRAILING-COMMA-FREE join. The first version appended "," to every element
# including the last, so `ip_grctx_keys` printed `0,1,...,11,` against the
# oracle's `0,1,...,11` -- a real difference, and one that would have hidden a
# genuine off-by-one in the key list behind a formatting fault.
def grctx.join(+xs: List<&2, U32>) -> String: grctx.join1(xs, False{})


def grctx.reuses_10() -> U32: grctx.reuse(grctx.size(11), grctx.size(10))


def grctx.row(+k: U32) -> IO(Unit):
  srow(String.concat(["ip_grctx_", U32.show(k)]),
    String.join([U32.show(grctx.size(k)), U32.show(Bool.to_u32(grctx.phys(k))),
                 U32.show(Bool.to_u32(grctx.virt(k))), U32.show(Bool.to_u32(grctx.local(k)))], ","))


# :357-362 the class row, joined so a wrong ORDER inside it is a value change.
def cls.row(+chip: String) -> String:
  cls.join4(cls.gpfifo(chip), cls.compute(chip), cls.dma(chip), cls.viddec(chip))


def seq.walk() -> Wk: seq_walk(seq_prog())

def seq.prog_n() -> U32: seq.count(Wk.ops(seq.walk()), 0)

# `P.hex8`, not `P.nib`: the walked OPS are 0x0..0x8 and `P.nib` answers them, but
# `P.hex8` is the spelling Python's `'%x'` has and it is the one the oracle used.
# `P.hex8`, not `P.nib`: the walked OPS are 0x0..0x8 and `P.nib` answers them, but
# `P.hex8` is the spelling Python's `'%x'` has and it is the one the oracle used.
# The separator goes BETWEEN, so the first element is special -- the version that
# appended it unconditionally printed `0,0,3,4,6,`.
def seq.joinu(+xs: List<&2, U32>, sep: String) -> String: seq.joinu1(xs, sep, False{})


# --- the three helpers, :366-367 and :409 ------------------------------
def t_prims() -> IO(Unit):
  do IO<Unit>:
    urow("ip_ru_0_1000", ru(0, 4096))
    urow("ip_ru_1_1000", ru(1, 4096))
    urow("ip_ru_4095_1000", ru(4095, 4096))
    urow("ip_ru_4096_1000", ru(4096, 4096))
    urow("ip_ru_4097_1000", ru(4097, 4096))
    urow("ip_rd_0_1000", rd(0, 4096))
    urow("ip_rd_1_1000", rd(1, 4096))
    urow("ip_rd_4095_1000", rd(4095, 4096))
    urow("ip_rd_4096_1000", rd(4096, 4096))
    urow("ip_rd_4097_1000", rd(4097, 4096))
    urow("ip_cdiv_0_1000", cdiv(0, 4096))
    urow("ip_cdiv_1_1000", cdiv(1, 4096))
    urow("ip_cdiv_4096_1000", cdiv(4096, 4096))
    urow("ip_cdiv_4097_1000", cdiv(4097, 4096))
    urow("ip_ru_5_4", ru(5, 4))
    urow("ip_ru_21_21", ru(21, 21))
    urow("ip_rd_21_21", rd(21, 21))
    urow("ip_rd_5_4", rd(5, 4))
    urow("ip_cdiv_5_4", cdiv(5, 4))
    t_radix()


# :357-362 the class table.
def t_cls() -> IO(Unit):
  do IO<Unit>:
    srow("ip_cls_GA", cls.row("GA102"))
    srow("ip_cls_AD", cls.row("AD102"))
    srow("ip_cls_GB", cls.row("GB202"))
    urow("ip_cls_ga_like_n", 1)
    urow("ip_cls_viddec_ada", P.Cn.v(P.const_of("NVC9B0_VIDEO_DECODER")))
    urow("ip_cls_viddec_gb", P.Cn.v(P.const_of("NVCFB0_VIDEO_DECODER")))
    urow("ip_cls_nvdec0", P.Cn.v(P.const_of("NV2080_ENGINE_TYPE_NVDEC0")))
    row("ip_cls_GA_viddec_none", U32.is_eq(cls.viddec("GA102"), 0))
    row("ip_cls_AD_viddec_set", Bool.not(U32.is_eq(cls.viddec("AD102"), 0)))


def Tr.emit(+k: U32, +a: U32, +b: U32, +c: U32, +t: Tr) -> Tr:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, +refused}:
      tr.put(t, Tr.emit.go(k, a, b, c, calls, 0, refused), Tr.ncalls(t))


def rp.acc4(+acc: U32, +p: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool) -> U32:
  U32.xor(acc, rp.wordof(p, func, plen, seq, hi))


def rp.put_wp2(+e: Tr, +wp: U32) -> Tr:
  Tr{Tr.calls(e), wp, Tr.seq(e), Tr.handle(e), rp.fail_of(e), Tr.refused(e)}


# :55 `NV_PGSP_QUEUE_HEAD[0].write(0x0)` -- the LAST call, after the sequence.
def rp.door(+e: Tr) -> Tr: Tr.emit(C_QUEUE_HEAD(), 0, 0, 0, e)


def rp.bumped2(+seq: U32, +handle: U32, +e: Tr, +s2: U32) -> Tr:
  Tr{Tr.calls(e), Tr.wp(e), s2, handle, rp.fail_of(e), Tr.refused(e)}


def tr.show(+t: Tr) -> String: tr.go(Tr.calls(t), False{})


def fsp.put(+t: Tr, +w: U32) -> Tr: Tr.emit(C_FSP_EMEMD(), w, 0, 0, t)


def fsp.do_head(+t: Tr) -> Tr: Tr.emit(C_FSP_HEAD(), 0, 0, 0, t)



# :557 `self.chan_runlists[obj] = self.runlists.get((e := params.engineType) +
# 10 * (e >= nv_gpu.NV2080_ENGINE_TYPE_NVDEC0), 0)` -- the NVDEC0 ADDEND. The
# runlist is looked up under the engine type NORMALISED by ten for NVDEC0, so a
# port that forgot the addend would read runlist 19 where the driver wrote 29,
# and the error is a silently wrong runlist rather than a fault. `ip_rp_runlist_key_*`
# walks the boundary at 18/19/20.

def rpc.runlist_key(+e: U32) -> U32: U32.add(e, rpc.nvdec_add(e))

# :87-91 `wait_resp` -- and :91 is the refusal. `C_WAIT_RESP` is the call and
# `C_RPC_RAISE` is the raise; the raise TRUNCATES, so a timeout shows up as a
# trace that stops at the wait and needs no guard of its own downstream.
def rpc.wait(+func: U32, +t: Tr) -> Tr: Tr.emit(C_WAIT_RESP(), func, 0, 0, t)


# :84 `raise RuntimeError(f"RPC call {hdr.function} failed with result
# {hdr.rpc_result}")` -- the trace is truncated from here and `refused` is set, so
# every later `Tr.emit` is a no-op.
def rpc.raise(+func: U32, +result: U32, +t: Tr) -> Tr:
  rpc.raise2(func, result, Tr.emit(C_RPC_RAISE(), func, result, 0, t))


# THE TWENTY U32 WORDS of `bytes(phdr) + header`, one row each. The folded
# checksum cannot see the hi/lo split -- `hi32(c) ^ lo32(c)` is symmetric, so
# swapping which word of a pair is `hi` leaves the answer alone, and a mutation
# that does that (`rp.pickw` with its arms exchanged) moves ZERO rows. These rows
# are what make it visible: they name the word at each index, so an exchanged
# pair moves twenty rows instead of none.
def t_req_words(+i: U32, +func: U32, +plen: U32) -> IO(Unit):
  do IO<Unit>:
    t_words(i, func, plen, List.range(U32.to_nat(rp.nwords())))


# `ip_tr_<i>_order` is the FIVE calls of :49-55 in order -- record, the two queue
# copies, the write pointer, the barrier, the doorbell. It is the row that says
# the doorbell comes AFTER the pointer store.
def t_req_order(+i: U32, +r: Rq) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["ip_tr_", U32.show(i), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_tr_", U32.show(i), "_n"]), Tr.ncalls(Rq.tr(r)))


# --- :57-60 the CONTINUATION SPLIT, and :62-85 the response read ----------
# A payload of exactly `max_payload` is ONE record and one byte more is TWO.
def t_trace_rx() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_cont_first_func", 72)
    urow("ip_rp_cont_func", rp.cont_func())
    t_cont(0)
    t_cont(1)
    t_cont(65455)
    t_cont(65456)
    t_cont(65457)
    t_cont(130912)
    t_cont(130913)
    urow("ip_rp_rx_off_hdr", 48)
    urow("ip_rp_rx_off_msg", 80)
    t_rx(0, 32)
    t_rx(0, 4096)
    t_rx(0, 4097)
    t_rx(5, 8192)
    t_rx(62, 32)
    t_rx(62, 16384)
    urow("ip_rp_result_ok", 0)
    urow("ip_rp_result_bad", 4294967295)
    urow("ip_rp_sig", rp.sig())
    urow("ip_rp_pending", rp.pending())
    urow("ip_rp_hdr_version", rp.hdr_version())
    urow("ip_rp_len_bias", 32)
    urow("ip_rp_err_lo", P.Cn.v(P.const_of("NV_VGPU_MSG_EVENT_OS_ERROR_LOG")))
    urow("ip_rp_err_hi", P.Cn.v(P.const_of("NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED")))
    t_err(4102)
    t_err(4101)
    t_err(4097)
    t_err(4)


def t_rl(+e: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_runlist_key_", U32.show(e)]), rpc.runlist_key(e))


# :90-91 `self.cmd_q.wait_resp(cmd)` then, on timeout,
# `raise RuntimeError(f"Timeout waiting for RPC response for command {cmd}")`.
# The wait is a CALL (:90) and the raise is the next one (:91), so the trace holds
# both and stops there -- `rpc.wait` records the wait and `rpc.raise` records the
# refusal that truncates everything after it.
def ref.timeout(+func: U32, +t: Tr) -> Tr: rpc.raise(func, 4294967295, rpc.wait(func, t))


def wpr.leg6(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, +gsp_off: U32,
            +heap_off: U32) -> Wm:
  wpr.leg7(vram, vga_off, frts_off, boot_off, gsp_off, heap_off,
           rd(U32.sub(heap_off, 4096), 1048576))


def grctx.keys() -> String: grctx.join(grctx.keylist())


# A `match` arm holds ONE term, so the row and the recursion need a `do IO<Unit>`
# block -- and a `do IO<Unit>` block can only BIND an `IO`, which is why both of
# these are bare statements and neither is a `<-` binding.
def grctx.walk(+xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("ip-grctx_end=1")
    case k <> t:
      do IO<Unit>:
        grctx.row(k)
        grctx.walk(t)


def seq.prog_ops() -> String: seq.joinu(Wk.ops(seq.walk()), ",")


# :629-661 the cpu-sequencer opcode table and the walk.
def t_seq() -> IO(Unit):
  do IO<Unit>:
    urow("ip_seq_n", seq_n())
    srow("ip_seq_ops", seq.ops())
    srow("ip_seq_names", seq.names())
    srow("ip_seq_words", seq.wordlist())
    urow("ip_seq_first_ok", 0)
    urow("ip_seq_last_ok", 8)
    urow("ip_seq_first_bad", 9)
    urow("ip_seq_gap_at", 9)
    urow("ip_seq_hdr_size", 40)
    urow("ip_seq_prog_cmdindex", 12)
    srow("ip_seq_prog_ops", seq.prog_ops())
    urow("ip_seq_prog_n", seq.prog_n())
    urow("ip_seq_prog_consumed", Wk.i(seq.walk()))
    row("ip_seq_prog_aligned", U32.is_eq(Wk.i(seq.walk()), 12))
    row("ip_seq_bad_9", seq_bad(9))
    row("ip_seq_ok_8", Bool.not(seq_bad(8)))


# THE folds carry no state, AND that is the point. The first version threaded
# `h` and `l` -- the two partial XORs -- as parameters, and the self-call could
# never supply them: they are consumed by the accumulator in the computed
# argument and the call is left partial ("observed : @+l:U32 -> U32"). So the fold
# is RECOMPUTED from scratch at each step: the words are a pure function of
# `(func, plen, seq)`, the XOR is associative and commutative, and
# `c ^ (a ^ b) == (c ^ a) ^ b`, so folding from zero every time gives the same
# answer with nothing to thread. `rp.fold` is six lines because there is no state.
# Two `Nat` countdown folds, each with ONE U32 accumulator, over the same ten u64
# words -- and `hi32(c) ^ lo32(c)` is `fold(hi) ^ fold(lo)` because XOR COMMUTES
# with the split. That is what makes a 64-bit checksum computable with no 64-bit
# integer, and it is why the fold is six lines instead of eight. So there are two
# `Nat` countdown folds, each with ONE U32 accumulator, over the same ten u64
# words -- and `hi32(c) ^ lo32(c)` is `fold(hi) ^ fold(lo)` because XOR COMMUTES
# with the split. That is what makes a 64-bit checksum computable with no 64-bit
# integer, and it is why the fold is five lines instead of eight.
def rp.fold(+k: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool, +acc: U32) -> U32:
  match k:
    case 0n: acc
    case 1n+p: rp.fold(p, func, plen, seq, hi, rp.acc4(acc, p, func, plen, seq, hi))



# THE queue fields do not advance past a refusal. Without this the trace is
# truncated but `wp` and `seq` still move -- `ip_refuse_at1_wp` printed 1 against a
# trace holding only the send, which is not what Python does: the statements after
# a `raise` do not execute. So the store is a `Bool.pick` on `refused`, and that is
# the ONLY guard in the file -- it lives in the one def that owns the store.
#
# THE ARMS WERE SWAPPED ONCE, and the first oracle could not see it. It tabulated
# `wp` as "moves if fail_at < 3" and the port -- carrying `refused` in the wrong
# arm -- printed exactly that, so all five rows agreed and the guard was doing the
# precise opposite of its comment. The oracle now EXECUTES the body with the fault
# raised and reads `tx.writePtr` off the struct, and the rows invert. A hand-typed
# table of expected values reproduces a port's mistake whenever the mistake and the
# table are the same mistake.
def rp.put_wp(+e: Tr, +wp: U32) -> Tr:
  rp.put_wp2(e, Bool.pick(U32, Tr.refused(e), Tr.wp(e), wp))


# :54 `self.seq += 1` -- and past a refusal the sequence does NOT advance, for the
# same reason the write pointer does not: the statements after a `raise` do not
# execute. `rp.bumped` exists because `Bool.pick` answers the arm it takes and the
# other arm never reaches the answer, so a self-call placed INSIDE an arm is
# silently dropped -- the accumulator has to be computed first and the rebuild
# second. The queue fields are `+` PARAMETERS for the same reason the compiler
# cannot re-read one binder twice.
def rp.bumped(+seq: U32, +handle: U32, +e: Tr) -> Tr:
  rp.bumped2(seq, handle, e, Bool.pick(U32, Tr.refused(e), seq, U32.add(seq, 1)))


# :534 `send_rpc` then :535 `wait_resp` -- and the record's fields are CARRIED
# through, so this is the one place the wait's own `wp`/`seq` (which the record
# advanced) must not be read off the pre-wait trace.
def rpc.am3(+hdev: U32, +hclass: U32, +npages: U32, +r: Rq) -> Rq:
  Rq.of(Rq.func(r), Rq.plen(r), Rq.elem(r), Rq.total(r), Rq.off(r), Rq.first(r),
        rp.wraps(Rq.total(r), Tr.wp(Rq.tr(r))), Rq.wp(r), Rq.seq(r), Rq.cksum(r),
        rpc.minted(rpc.wait(rpc.func_alloc(), Rq.tr(r))))


def fsp.do_tail(+t: Tr) -> Tr: fsp.do_head(Tr.emit(C_FSP_TAIL(), 0, 0, 0, t))


# --- :557 the runlist key and :590-591 the doorbell ----------------------
def t_trace_seqs() -> IO(Unit):
  do IO<Unit>:
    t_rl(0)
    t_rl(1)
    t_rl(4)
    t_rl(18)
    t_rl(19)
    t_rl(20)
    urow("ip_rp_runlist_miss", rpc.runlist_miss())
    t_tok("gb2", "GB202", 4660, 7)
    t_tok("ga10", "GA102", 4660, 7)
    t_tok("rl0", "GA102", 4660, 0)
    t_tok("rl31", "GB202", 4660, 31)
    urow("ip_rp_token_shift", 16)
    urow("ip_rp_token_bit30", 1073741824)
    row("ip_rp_chip_gb2", String.starts_with("GB202", "GB2"))
    row("ip_rp_chip_ga10", String.starts_with("GA102", "GB2"))
    t_fl()
    t_gsp()


def wpr.leg5(+vram: U32, vga_off: U32, frts_off: U32, boot_off: U32, +gsp_off: U32) -> Wm:
  wpr.leg6(vram, vga_off, frts_off, boot_off, gsp_off,
           rd(U32.sub(gsp_off, 135266304), 1048576))


def grctx.rows() -> IO(Unit):
  do IO<Unit>:
    grctx.walk(grctx.keylist())


# :498-504 the graphics-context buffer table.
def t_ctx() -> IO(Unit):
  do IO<Unit>:
    urow("ip_ctx_eng", P.Cn.v(P.const_of("NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS")))
    urow("ip_ctx_patch", P.Cn.v(P.const_of("NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS_PATCH")))
    urow("ip_ctx_patch_plus14", U32.add(P.Cn.v(P.const_of("NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS_PATCH")), 14))
    urow("ip_ctx_eng_n", 25)
    urow("ip_ctxcfg_n", 8)
    ctx.rows()
    ctx.cfg_rows()
    srow("ip_grctx_keys", grctx.keys())
    urow("ip_grctx_n", grctx.n())
    row("ip_grctx_11_reuses_10", Bool.not(U32.is_eq(grctx.reuses_10(), 0)))
    urow("ip_grctx_local_n", grctx.local_n())
    grctx.rows()


def rp.cksum.xor(+func: U32, +plen: U32, +seq: U32) -> U32:
  rp.finish(rp.fold(U32.to_nat(rp.nu64()), func, plen, seq, True{}, 0),
            rp.fold(U32.to_nat(rp.nu64()), func, plen, seq, False{}, 0))


# :54 `self.seq += 1` -- between the BARRIER and the DOORBELL, and that position is
# load-bearing: `ip_refuse_at5_seq` is 1 and `ip_refuse_at4_seq` is 0, so a refusal
# at the doorbell leaves the sequence already advanced (:54 ran) and a refusal at
# the barrier leaves it not (:54 did not). Rung the doorbell before bumping would
# have made both rows 0 and the position unfalsifiable.
def rp.bump(+e: Tr) -> Tr: rp.door(rp.bumped(Tr.seq(e), Tr.handle(e), e))


# THE countdown is the first argument -- a self-call is read LEFT to right and
# each argument must pass unchanged until one shrinks, so putting `t` (which the
# emit rebuilds) in front of the shrinking `p` is "expected : a decreasing
# self-call". The queue is threaded last and the emit is its argument.
# THE COUNTDOWN IS A `U32` AND IT IS A PARAMETER, not a pattern binder. The index
# is needed twice -- once as the countdown handed to the self-call and once to
# index the word table -- and a `Nat` pattern BINDER cannot be read twice (there
# is no `case 1n+ +p:` spelling), while a `+k` PARAMETER can. So the count is a
# `U32` matched with `case 0:` / `case 1+r:` and the countdown argument comes first
# so the self-call is DECREASING.
def fsp.ememd(+nvmd: U32, +total: U32, +k: Nat, +t: Tr) -> Tr:
  match k:
    case 0n: fsp.do_tail(t)
    case 1n+p: fsp.ememd(nvmd, total, p, fsp.put(t, fsp.word(total, k, nvmd)))


def wpr.leg4(+vram: U32, +vga_off: U32, +frts_off: U32, +boot_off: U32, radix3_sz: U32) -> Wm:
  wpr.leg5(vram, vga_off, frts_off, boot_off, rd(U32.sub(boot_off, radix3_sz), 65536))


# --- everything else ----------------------------------------------------
def t_misc() -> IO(Unit):
  do IO<Unit>:
    t_libos()
    t_reg()
    t_bdf()
    t_flags()
    t_ctx()
    t_cls()
    t_seq()
    t_fsp()
    t_am()


# :52 `System.memory_barrier()` -- between the pointer store and the doorbell.
def rp.barrier(+e: Tr) -> Tr: rp.bump(Tr.emit(C_BARRIER(), 0, 0, 0, e))


def fsp.tr3(+nvmd: U32, +blen: U32, +t: Tr, +e: Tr) -> Tr:
  fsp.ememd(nvmd, fsp.words(nvmd, blen), U32.to_nat(fsp.words(nvmd, blen)), e)


def wpr.leg3(+vram: U32, +vga_off: U32, +frts_off: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg4(vram, vga_off, frts_off, U32.sub(frts_off, boot_sz), radix3_sz)


def rp.wp3(+elem: U32, +wp: U32, +seq: U32, e: Tr) -> Tr:
  rp.barrier(rp.put_wp(e, rp.wp_after(wp, elem)))


def fsp.tr2(+nvmd: U32, +blen: U32, +t: Tr) -> Tr:
  fsp.tr3(nvmd, blen, t, Tr.emit(C_FSP_EMEMC(), fsp.tail_off(), fsp.aincw(), fsp.aincr(), t))


def wpr.leg2(+vram: U32, +vga_off: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg3(vram, vga_off, U32.sub(vga_off, 1048576), boot_sz, radix3_sz)


# :51 `self.tx_view[writePtr] = (wp + phdr.elemCount) % self.tx.msgCount` -- the
# pointer store, which must happen BEFORE the doorbell or the GSP reads a stale
# index.  `ip_tr_<i>_order` is the row that says so.
def rp.wp2(+elem: U32, +t: Tr) -> Tr:
  rp.wp3(elem, Tr.wp(t), Tr.seq(t), Tr.emit(C_QUEUE_WP(), rp.wp_after(Tr.wp(t), elem), elem,
                                           rp.msg_count(), t))



# :328-344 `kfsp_send_msg`, in trace order: EMEMC, one EMEMD per word, TAIL,
# HEAD. `QUEUE_TAIL` is `len(buf) - 4` -- the padded total MINUS the last header
# word -- and `QUEUE_HEAD` is 0. The EMEMD count is the padded word count, which
# is what `ip_fsp_tr_*_nwords` pins; a port that wrote one EMEMD per PAYLOAD
# byte would write four times as many.

def fsp.trace(+nvmd: U32, +blen: U32) -> Tr: fsp.tr2(nvmd, blen, Tr.of())


# --- :328-344 the FSP framing, in trace order ---------------------------
# EMEMC, one EMEMD per word, TAIL, HEAD -- and `QUEUE_TAIL` is
# `len(buf) - 4`, the padded total MINUS the last header word.
def t_trace_fsp() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, fsp.trace(fsp.nvmd_cot(), 82))
    srow("ip_fsp_tr_order", tr.show(t))
    urow("ip_fsp_tr_nwords", fsp.words(20, 82))
    urow("ip_fsp_tr_tot", fsp.tot(82))
    urow("ip_fsp_tr_tail_val", fsp.tail(82))
    urow("ip_fsp_tr_w0", fsp.w0())
    urow("ip_fsp_tr_w1", fsp.w1(fsp.nvmd_cot()))
    urow("ip_fsp_tr_nvmd_cot", fsp.nvmd_cot())
    urow("ip_fsp_tr_aincw1", fsp.aincw())
    urow("ip_fsp_tr_aincr0", fsp.aincr())
    urow("ip_fsp_tr_tail_off", fsp.tail_off())
    urow("ip_fsp_tr_head_off", fsp.head())
    +t2 : Tr <- IO.pure(Tr, fsp.trace(0, 82))
    srow("ip_fsp_tr_0_order", tr.show(t2))
    urow("ip_fsp_tr_0_nwords", fsp.words(0, 82))
    urow("ip_fsp_tr_0_tot", fsp.tot(82))
    urow("ip_fsp_tr_0_w0", fsp.w0())
    urow("ip_fsp_tr_0_w1", fsp.w1(0))


# THE LEGACY CHAIN, read DOWNWARD. Two of the subtrahends are BYTE lengths of
# firmware images (`boot_sz`, `radix3_sz`) and the other six are constants, so
# the whole thing is exact -- but every step needs the one above it and Bend
# refuses mutual recursion, so the chain is eight defs that each thread one more
# parameter. That is the substrate's price and `spec.bend` pays the same one for
# its six scans.
def wpr.leg(+vram: U32, boot_sz: U32, radix3_sz: U32) -> Wm:
  wpr.leg2(vram, U32.sub(vram, 1048576), boot_sz, radix3_sz)


def t_wpr_one(+tag: String, +vram: U32) -> IO(Unit):
  do IO<Unit>:
    +l : Wm <- IO.pure(Wm, wpr.leg(vram, 1785856, 102400))
    +f : Wm <- IO.pure(Wm, wpr.fmc())
    urow(String.concat(["ip_wpr_", tag, "_leg_nf"]), wm_nf(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_vgaWorkspaceOffset"]), wm_vga_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_frtsOffset"]), wm_frts_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_bootBinOffset"]), wm_boot_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwOffset"]), wm_gsp_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwHeapOffset"]), wm_heap_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwWprStart"]), wm_wpr_st(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_nonWprHeapOffset"]), wm_nonwpr_off(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwRsvdStart"]), wm_rsvd(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwWprEnd"]), wm_wpr_end(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_fbSize"]), wm_fb(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_frtsSize"]), wm_frts_sz(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_vgaWorkspaceSize"]), wm_vga_ws(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_gspFwHeapSize"]), wm_heap_sz(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_nonWprHeapSize"]), wm_nonwpr_sz(l))
    urow(String.concat(["ip_wpr_", tag, "_leg_pmuReservedSize"]), 0)
    urow(String.concat(["ip_wpr_", tag, "_fmc_nf"]), wm_nf(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_vgaWorkspaceOffset"]), wm_vga_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_frtsOffset"]), wm_frts_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_bootBinOffset"]), wm_boot_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwOffset"]), wm_gsp_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwHeapOffset"]), wm_heap_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwWprStart"]), wm_wpr_st(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_nonWprHeapOffset"]), wm_nonwpr_off(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwRsvdStart"]), wm_rsvd(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwWprEnd"]), wm_wpr_end(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_fbSize"]), wm_fb(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_frtsSize"]), wm_frts_sz(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_vgaWorkspaceSize"]), wm_vga_ws(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_gspFwHeapSize"]), wm_heap_sz(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_nonWprHeapSize"]), wm_nonwpr_sz(f))
    urow(String.concat(["ip_wpr_", tag, "_fmc_pmuReservedSize"]), 25296896)


def rp.trace3(+cks: U32, +elem: U32, +total: U32, +func: U32, +t1: Tr, +t2: Tr) -> Tr:
  rp.wp2(elem, t2)


# --- :434-455 init_wpr_meta, both branches, three VRAM sizes ----------
# `ip_wpr_*_nf` is the row that makes the fmc branch's zeros legible: 26 fields
# set on the legacy branch and 16 on the fmc one, NONE of which is an offset.
def t_wpr() -> IO(Unit):
  do IO<Unit>:
    t_wpr_one("1g", 1073741824)
    t_wpr_one("2g", 2147483648)
    t_wpr_one("max", 4294967295)
    urow("ip_wpr_vram_max", 4294967295)
    row("ip_wpr_fixtures_fit", over.fixtures_fit())
    urow("ip_wpr_sz", 256)
    urow("ip_wpr_common_n", 11)
    urow("ip_wpr_boot_sz", 1785856)
    urow("ip_wpr_radix3_sz", 102400)
    urow("ip_wpr_magic_lo", 924475571)
    urow("ip_wpr_magic_hi", 3694833185)
    urow("ip_frts_off_1g", fl.frts_offset(1073741824))
    urow("ip_frts_off_2g", fl.frts_offset(2147483648))
    urow("ip_frts_off_max", fl.frts_offset(4294967295))
    urow("ip_desc_sig_total", fl.desc_sig(1088))
    urow("ip_desc_img_256", fl.desc_img(32768))


def rp.trace2(+cks: U32, +elem: U32, +total: U32, +func: U32, t0: Tr, +t1: Tr) -> Tr:
  rp.trace3(cks, elem, total, func, t1, Tr.emit(C_QUEUE_WRITE(), rp.off(Tr.wp(t1)),
                                                 rp.first(total, Tr.wp(t1)),
                                                 rp.wrapbit(total, Tr.wp(t1)), t1))


def t_arith() -> IO(Unit):
  do IO<Unit>:
    t_prims()
    t_q()
    t_wpr()
    t_misc()


def rp.trace(+cks: U32, +elem: U32, +total: U32, +func: U32, +t: Tr) -> Tr:
  rp.trace2(cks, elem, total, func, t, Tr.emit(C_RPC_SEND(), func, elem, total, t))


def rp.rec4(+cks: U32, +elem: U32, +total: U32, +func: U32, +plen: U32, +t: Tr) -> Rq:
  Rq.of(func, plen, elem, total, rp.off(Tr.wp(t)), rp.first(total, Tr.wp(t)),
        rp.wraps(total, Tr.wp(t)), rp.wp_after(Tr.wp(t), elem), U32.add(Tr.seq(t), 1), cks,
        rp.trace(cks, elem, total, func, t))


def rp.rec3(+cks: U32, +elem: U32, +total: U32, +func: U32, +plen: U32, +pay: U32, +t: Tr) -> Rq:
  rp.rec4(U32.xor(cks, pay), elem, total, func, plen, t)


def rp.rec2(+elem: U32, +total: U32, +func: U32, +plen: U32, +pay: U32, +t: Tr) -> Rq:
  rp.rec3(rp.cksum.xor(func, plen, Tr.seq(t)), elem, total, func, plen, pay, t)



# THE RECORD, :38-55, and it appends FIVE calls in Python's order.

def rp.record(+func: U32, +plen: U32, +pay: U32, t: Tr) -> Rq:
  rp.rec2(rp.elem(plen), rp.total(plen), func, plen, pay, t)


def rpc.am2(+hdev: U32, +hclass: U32, +npages: U32, +t: Tr) -> Rq:
  rpc.am3(hdev, hclass, npages, rp.record(rpc.func_alloc(), am.plen(npages), 0, t))


def t_req(+i: U32, +func: U32, +plen: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(func, plen, 0, tr.at(Tr.of(), i)))
    urow(String.concat(["ip_rp_", U32.show(i), "_func"]), Rq.func(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_plen"]), Rq.plen(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_length"]), rp.length(plen))
    urow(String.concat(["ip_rp_", U32.show(i), "_elem"]), Rq.elem(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_total"]), Rq.total(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_cksum"]), Rq.cksum(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_seq0"]), i)
    urow(String.concat(["ip_rp_", U32.show(i), "_seq1"]), Rq.seq(r))
    t_req_order(i, r)
    t_req_words(i, func, plen)


def t_elem(+plen: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(103, plen, 0, Tr.of()))
    urow(String.concat(["ip_rp_elem_", U32.show(plen)]), Rq.elem(r))


def t_wp(+wp: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(103, 32, 0, Tr.of.wp(wp)))
    srow(String.concat(["ip_rp_w", U32.show(wp), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_off"]), Rq.off(r))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_first"]), Rq.first(r))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_wraps"]), rp.wrapbit(Rq.total(r), wp))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_wp"]), Rq.wp(r))


# `rpc_alloc_memory` is the ONE of the seven that is not a bare `send_rpc`: it
# mints a handle at :529, sends, and then WAITS at :535. The order row is what
# says the handle is minted before the send and that the wait is a call of its
# own -- and `ip_rp_am_0_order`'s seventh entry is that wait.
def t_alloc(+npages: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rpc.am2(1, 1, npages, Tr.of()))
    srow(String.concat(["ip_rp_am_", U32.show(npages), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_plen"]), Rq.plen(r))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_elem"]), Rq.elem(r))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_n"]), Tr.ncalls(Rq.tr(r)))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_next"]), Tr.handle(Rq.tr(r)))
    urow("ip_rp_am_format", 6)
    urow("ip_rp_am_pteAdjust", 0)
    urow("ip_rp_am_idr", P.Cn.v(P.const_of("NV_VGPU_PTEDESC_IDR_NONE")))
    urow("ip_rp_page_size", 4096)
    row("ip_rp_page_ok", am.page_ok(4096))
    row("ip_rp_page_bad", am.page_ok(8192))
    row("ip_rp_pages_ok", am.pages_ok4(4096, 4096, 4096, 4096))
    row("ip_rp_pages_bad", am.pages_ok4(4096, 4096, 4096, 8192))
    urow("ip_rp_ra_hdr", 32)
    urow("ip_rp_rc_hdr", 24)
    urow("ip_rp_pd_hdr", 48)
    urow("ip_rp_pd_params", 32)
    urow("ip_rp_unload_hdr", 8)
    urow("ip_rp_ra_plen_0", rpc.ra_plen(0))
    urow("ip_rp_rc_plen_0", rpc.rc_plen(0))
    urow("ip_rp_flags0", 0)
    urow("ip_rp_cls_vaspace", P.Cn.v(P.const_of("FERMI_VASPACE_A")))
    urow("ip_rp_cls_device", P.Cn.v(P.const_of("NV01_DEVICE_0")))
    urow("ip_rp_cls_subdev", P.Cn.v(P.const_of("NV20_SUBDEVICE_0")))
    urow("ip_rp_cls_root", P.Cn.v(P.const_of("NV1_ROOT")))
    row("ip_rp_cls_root_is_0", U32.is_eq(P.Cn.v(P.const_of("NV1_ROOT")), 0))
    urow("ip_rp_pd_flags", 8)
    urow("ip_rp_pd_pasid", 4294967295)
    urow("ip_rp_pd_sub", 1)
    urow("ip_rp_pd_chid", 0)
    urow("ip_rp_si_mirror_base", 557056)
    urow("ip_rp_si_fmc_base", 598016)
    urow("ip_rp_si_mirror_size", 4096)
    urow("ip_rp_si_passthru", 1)
    urow("ip_rp_si_hdr", 928)
    urow("ip_rp_si_bar", 3)
    urow("ip_rp_si_cfg_vendor", 0)
    urow("ip_rp_si_cfg_subsys", 44)
    urow("ip_rp_si_cfg_rev", 8)


def t_ref_at(+n: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(72, 928, 0, Tr.fail_at(Tr.of(), n)))
    +t : Tr <- IO.pure(Tr, Rq.tr(r))
    +k : String <- IO.pure(String, String.concat(["ip_refuse_at", U32.show(n), "_"]))
    urow(String.concat([k, "n"]), Tr.ncalls(t))
    srow(String.concat([k, "order"]), tr.show(t))
    row(String.concat([k, "flag"]), Tr.refused(t))
    urow(String.concat([k, "wp"]), Tr.wp(t))
    urow(String.concat([k, "seq"]), Tr.seq(t))


# `fail_at = 0` is the clean fixture, and it is the CONTROL: it prints the same
# order as `ip_tr_0_order` and nothing is flagged. A gate with no non-movement
# fixture has a `match`'s catch-all arm that is dead code.
def t_ref_clean() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, Rq.tr(rp.record(72, 928, 0, Tr.fail_at(Tr.of(), 0))))
    urow("ip_refuse_at0_n", Tr.ncalls(t))
    srow("ip_refuse_at0_order", tr.show(t))
    row("ip_refuse_at0_flag", Tr.refused(t))
    urow("ip_refuse_at0_wp", Tr.wp(t))
    urow("ip_refuse_at0_seq", Tr.seq(t))
    srow("ip_refuse_control", tr.show(t))
    urow("ip_refuse_control_wp", Tr.wp(t))
    urow("ip_refuse_control_seq", Tr.seq(t))


# The timeout fires on a queue that has ALREADY sent REQ0, so the sequence the
# earlier record established is 1 and the refusal must leave it at 1. A fixture
# starting from a zero sequence would print 0 here and could not tell "carried"
# from "never moved" -- which is the same reason the old hand-written row used 3:
# an arbitrary seed makes a carry-unchanged row pass by accident.
def t_refuse_timeout() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, ref.timeout(4097, Rq.tr(rp.record(72, 928, 0, Tr.of()))))
    srow("ip_refuse_timeout_order", tr.show(t))
    urow("ip_refuse_timeout_n", Tr.ncalls(t))
    row("ip_refuse_timeout_flag", Tr.refused(t))
    urow("ip_refuse_timeout_seq", Tr.seq(t))
    urow("ip_refuse_timeout_wp", Tr.wp(t))


# --- the seven requests, one row group each ------------------------------
def t_trace_reqs() -> IO(Unit):
  do IO<Unit>:
    t_req(0, 72, 928)
    t_req(1, 73, 82)
    t_req(2, 4, 64)
    t_req(3, 103, 32)
    t_req(4, 76, 24)
    t_req(5, 54, 48)
    t_req(6, 47, 8)


# `elemCount` is the ONLY place the 32-byte header shows up in the arithmetic, and
# for all seven requests it does not: they are small enough that `plen + 48` and
# `plen + 80` round to the same element count. The header matters only in the band
# `4096k - 79 <= plen <= 4096k - 49`, so 4016/4017 and 4047/4048 are the fixtures --
# and `ip_rp_elem_4017` is the row a port that dropped the header loses.
def t_trace_elem() -> IO(Unit):
  do IO<Unit>:
    t_elem(4016)
    t_elem(4017)
    t_elem(4047)
    t_elem(4048)
    t_elem(16336)
    t_elem(16337)


# --- the write pointer and the wrap, :48-51 -----------------------------
# The ring length is `msgSize*msgCount` and NOT the header's `size`, and on a real
# queue those differ by a page -- so the wrap boundary is a ROW, not a comment.
def t_trace_wp() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_ring_len", rp.ring_len())
    row("ip_rp_ring_ne_size", U32.is_ne(rp.ring_len(), 262144))
    urow("ip_rp_msg_count", rp.msg_count())
    urow("ip_rp_entry_off", rp.entry_off())
    urow("ip_rp_maxpayload", rp.max_payload())
    t_wp(0)
    t_wp(1)
    t_wp(31)
    t_wp(62)
    t_wp(61)
    t_wp(63)


# --- :348 the handle generator, :526-536 alloc, :594-599 pdir ------------
def t_trace_handles() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_handle_first", hgen.first())
    urow("ip_rp_handle_n", hgen.n())
    urow("ip_rp_handle_7", hgen.nxt7())
    urow("ip_rp_am_hdr", 56)
    urow("ip_rp_am_pte", 8)
    urow("ip_rp_am_payload_1", am.plen(1))
    urow("ip_rp_am_payload_4", am.plen(4))
    t_alloc(0)
    t_alloc(4)


# --- the trace truncations -------------------------------------------------
# ONE fixture per refusal ordinal. `fail_at` is the call ordinal the seam refuses,
# 0 = never, and the suite walks 1..5 -- which is every call a single RPC record
# makes, so `at5` refuses at the LAST call and the trace is complete-but-flagged.
def t_refuse_trace() -> IO(Unit):
  do IO<Unit>:
    t_ref_at(1)
    t_ref_at(2)
    t_ref_at(3)
    t_ref_at(4)
    t_ref_at(5)
    t_ref_clean()


def t_refuse_asserts() -> IO(Unit):
  do IO<Unit>:
    row("ip_refuse_bit_sig", ref.bit_sig(5523778))
    row("ip_refuse_bit_sig_bad", ref.bit_sig(5523779))
    urow("ip_refuse_bit_sig_val", 5523778)
    row("ip_refuse_wpr2", ref.wpr2(1))
    row("ip_refuse_wpr2_bad", ref.wpr2(0))
    row("ip_refuse_mbx", ref.mbx(0))
    row("ip_refuse_mbx_bad", ref.mbx(1))
    row("ip_refuse_active", ref.active(1))
    row("ip_refuse_active_bad", ref.active(0))
    # the row NAME is the PAYLOAD and the argument is `len(buf)` -- the framed
    # length `fsp.tot`, which is 8 + payload + pad and so always a multiple of 4.
    # Naming the rows by the framed length instead (as the first version did)
    # made `ip_refuse_fsp_1019` a row for a length the shape cannot produce, and
    # collapsed 1011 and 1012 onto one name. The pair 1011/1012 and the pair
    # 1015/1016 are the ones that show the pad is applied BEFORE the comparison.
    row("ip_refuse_fsp_80", ref.fsp_len(fsp.tot(80)))
    row("ip_refuse_fsp_84", ref.fsp_len(fsp.tot(84)))
    row("ip_refuse_fsp_1011", ref.fsp_len(fsp.tot(1011)))
    row("ip_refuse_fsp_1012", ref.fsp_len(fsp.tot(1012)))
    row("ip_refuse_fsp_1015", ref.fsp_len(fsp.tot(1015)))
    row("ip_refuse_fsp_1016", ref.fsp_len(fsp.tot(1016)))
    row("ip_refuse_frts", ref.frts(2145386496, 2145386496))
    row("ip_refuse_frts_bad", ref.frts(2145386496, 2145386497))
    row("ip_refuse_mailbox", ref.mailbox(0))
    row("ip_refuse_mailbox_bad", ref.mailbox(1))
    row("ip_refuse_pages_ok", ref.pages_ok(pages4()))
    row("ip_refuse_pages_bad", ref.pages_ok(pages3()))
    row("ip_refuse_pages_one", ref.pages_ok(pages1()))
    row("ip_refuse_bad_op_9", ref.bad_op(9))
    row("ip_refuse_bad_op_57005", ref.bad_op(57005))
    t_refuse_timeout()


def t_trace() -> IO(Unit):
  do IO<Unit>:
    t_trace_reqs()
    t_trace_elem()
    t_trace_wp()
    t_trace_rx()
    t_trace_handles()
    t_trace_seqs()
    t_trace_fsp()


def t_refuse() -> IO(Unit):
  do IO<Unit>:
    t_refuse_trace()
    t_refuse_asserts()


def main() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- t_tables()
    +b : Unit <- t_arith()
    +c : Unit <- t_trace()
    +d : Unit <- t_refuse()
    IO.print("ip-done=1")
