# tinybendygrad/runtime/support/usb.bend -- port of tinygrad/runtime/support/usb.py
#
# ===========================================================================
# SCOPE, AND WHY IT IS THIS SCOPE. `grep -rl "support/usb" tinybendygrad
# --include="*.bend"` is EMPTY: no committed file cites this one, so unlike every
# other unit in this wave it was not scoped for me by a citation. I therefore
# chose it, and the choice is dictated by the source. `usb.py` is 473 lines in
# three parts that share almost nothing:
#
#   :12-18   alloc_cbuffer / checked                    SEAM   ctypes
#   :20-92   USB3 -- enumeration, open, control/bulk    PORTED the ORDER + the
#                                                          argument arithmetic
#   :94-174  CustomASM24Controller -- vendor protocol   PORTED the arithmetic,
#                                                          the refusals, the strings
#   :176-202 USBMMIOInterface                           PORTED the index arithmetic
#   :204-247 the UOp placeholders and the WINDOW        PORTED the window
#   :249-309 staging rewrites                           PORTED the ORDER only
#   :311-385 host functions                             PORTED the ORDER + arithmetic
#   :386-471 lowering + bufferize                       PORTED the ORDER only
#
# WHAT IS WORTH PORTING, AND WHY IT IS WORTH IT. `usb.py` is the only file in
# tinygrad that talks to a device through a GENERATED ctypes binding, and
# `tinygrad/runtime/autogen/libusb.py` is that binding: 21 `enum_libusb_*` dicts
# and 22 `@c.record` structs whose `register_fields` carries a field NAME and an
# OFFSET for every member. That is a descriptor table in the exact sense this
# project gets burned on -- `ops_nv`'s audit found 33 of 219 constants wrong in
# a file already printing 590 green rows, and `ops_rdma` shipped `BNXT_VENDOR`
# as 5356 where the header says 5348. `struct_libusb_transfer`'s thirteen field
# names, in order, are what `usb_chunk` (:349-351) addresses three times by name,
# so a transposed pair is a silently wrong transfer. So the tables are IN.
#
# ===========================================================================
# THE WALLS THIS CLOSES. `ops_amd.bend` records WALL 3 ("USB3, USBIface,
# ops_amd.py:810-833") naming `USB3.list_devices`, `dma_view`, and the
# `0/4096/20480` controller window; and the header of `ops_disk.bend` (which owns
# `dev_might_open`, the open sequence ops_cl's agent could not reach) records
# its own open ladder as a wall of `_might_open`. This file closes:
#
#   * ops_amd WALL 3, part 1 -- `USB3.list_devices` (:30-37). The enumeration
#     is a `Tr` trace: GET_DEVICE_LIST, then per device GET_DEVICE_DESCRIPTOR,
#     the (idVendor, idProduct) == (vendor, dev) test, REF_DEVICE with the
#     bus/address label, FREE_DEVICE_LIST(devs, 1). `usb_enum` is the trace and
#     `usb_list_match` is the SELECTION, with the negative case (a descriptor
#     whose ids do not pair) one row from its positive.
#   * ops_amd WALL 3, part 3 -- the WINDOW. ops_amd could name the three
#     map_range pieces (0, 4096, 20480) but could not derive them, because
#     `usb_asm24`'s slices live here: `usb_fence` 2048/2052, `usb_cq`
#     4108/4112, `usb_sram` 20480/20480+2*HALF, and the sizes that make
#     them. `usb_win_*` is that derivation, and `amd` can now check its own
#     numbers against it. NOTE ops_amd's 4096 is ops_amd's OWN ctrl map piece,
#     not `usb_cq`'s 4108 -- the two are different windows and this file
#     records both, so a port that conflated them would be caught here.
#   * ops_disk's `_might_open` ladder -- USB3's open is the same shape (a
#     walk of state that ends in a CLAIM), and `usb_open` is its trace.
#
# NOT CLOSED, DELIBERATELY. `dma_view` (ops_amd.py:824) is a `PCIDevice` method
# that lives in ops_amd.bend's own wall 2 and is not usb.py's to answer.
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure; the gate checks it) OR records that call in the trace
# (the gate checks ORDER and IDENTITY). There is no third kind. Every libusb,
# libc and ctypes binding is a `Call{k, a, b, c}` entry in `Tr` and nothing
# else, so no foreign effect is declared and `--check-only` stays green in both
# lanes. The symbol names live in `vend`, one `String` per call kind, so the
# seam is greppable: `grep -n libusb_ this_file` finds the C symbol as a
# literal, not inside an opaque body.
#
# NO @extern SEAMS. Same reason and same result as hcq2.bend and
# support/am/ip.bend: an `@extern` is permanently-red laws plus an import
# closure that reaches the importer's every def. A trace is not.
#
# ===========================================================================
# THE AUDIT. Every constant in this file was checked by `getattr` against the
# live `tinygrad.runtime.autogen.libusb`, not transcribed by eye. See
# `.agents/slop/usb-constmap.py` and the CONSTANT AUDIT section at the end.

import Base
import ../../helpers.bend as H

# ===========================================================================
# THE libusb CONSTANT TABLES. Both directions from one list, because that is
# how the header has them: `enum_libusb_class_code` is a `dict[int, str]`, so
# `enum_of` is the dict and `name_of` is its inverse. Keeping them as ONE list
# and two folds is what makes both directions testable over the same data --
# a table written twice is two tables and one of them is wrong.
#
# `val` is the C bit pattern in a U32. The six negative libusb error codes are
# therefore stored two's-complement and PRINTED signed by `show_i32`, because
# `usb_reap`'s backedge compares against `LIBUSB_ERROR_INTERRUPTED` and the gate
# has to diff CPython's `-10`, not 4294967286.
# ===========================================================================

type Ent is Data:
  Ent{val: U32, name: String}

# value -> name, LAST match wins: `enum_libusb_class_code` gives 6 TWO names and
# the generated dict keeps the LAST, so a first-wins fold is wrong and the differ
# says so on `usb_classcode_6_name`.
def enum_nm.go(n: Nat, +v: U32, es: List<&2, Ent>, hit: String) -> String:
  match n:
    case 0n: hit
    case 1n+m:
      match es:
        case Nil{}: hit
        case Ent{vv, nn} <> t: enum_nm.go(m, v, t, Bool.pick(String, U32.is_eq(vv, v), nn, hit))

def enum_nm(+v: U32, +es: List<&2, Ent>) -> String:
  enum_nm.go(List.length(&2, Ent, es), v, es, "LIBUSB_ENUM_NONE")

# name -> value, LAST match wins for the same reason. A NAME no entry has is
# `NOT_FOUND` and never 0: 0 is LIBUSB_SUCCESS's and LIBUSB_REQUEST_TYPE_STANDARD's
# and LIBUSB_TRANSFER_COMPLETED's value, so a silent 0 would be indistinguishable
# from a real constant. 4294967295 is LIBUSB_ERROR_IO's bit pattern, and
# `usb_enumval_absent_not_found` is the row that says which one it is.
def u1(nm: String, v: U32) -> String: String.concat([nm, "=", U32.show(v)])
def b1(nm: String, v: Bool) -> String: String.concat([nm, "=", Bool.show(v)])
def s1(nm: String, v: String) -> String: String.concat([nm, "=", v])

# the six signed libusb error codes diff against CPython's `-10` and not against
# 4294967286: a U32 bit pattern is how the header stores them and a signed C
# `int` is how CPython prints them.
def show_i32(+x: U32) -> String:
  Bool.pick(String, H.i32_is_neg(x),
            String.concat(["-", U32.show(H.i32_abs(H.i32_is_neg(x), x))]), U32.show(x))

def i1(nm: String, v: U32) -> String: String.concat([nm, "=", show_i32(v)])

def lines_of(xs: List<&2, String>) -> String: String.join(xs, "\n")

# THE THREE SIZES COME FROM `struct.calcsize`, and they are ROWS rather than
# literals precisely because a reader who counts `"<IIIBBB16s"` by eye gets 37
# and the real answer is 31. `usb-constsweep.py` confirms all three by calling
# `struct.calcsize`.
def CDB_SIZE() -> U32: 31
def REPLY_SIZE() -> U32: 13
def REPLY_READ_LEN() -> U32: 13

# `concat_str` flattens the per-fixture row GROUPS. Bend has no variadic def and
# `List.concat` wants a `List<_, List<_, _>>` whose head type is a list, which a
# chain of `<>` cannot build readably -- so this is the fold, and the accumulator
# is threaded so the row ORDER is the fixture ORDER.
def cat_one(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: List.append(&2, String, cat_one(t, acc), [h])

def cat.go(n: Nat, xss: List<&2, List<&2, String>>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xss:
        case Nil{}: acc
        case h <> t: cat.go(m, t, cat_one(h, acc))

def concat_str(+xss: List<&2, List<&2, String>>) -> List<&2, String>:
  cat.go(List.length(&2, List<&2, String>, xss), xss, Nil{})


# ===========================================================================
# THE CONSTANTS AND THE WINDOW. `usb.py:208-229` is the whole memory map: two
# SRAM halves with a reserved sentinel block each, a host block, a vram pair, and
# the bridge's three slices.
#
# THIS CLOSES ops_amd.bend's WALL 3, part 3. ops_amd recorded the controller
# window as `0/4096/20480` from ops_amd.py:822's three `map_range` pieces and
# could not derive it, because the offsets live here. Two of the three now have
# names: `WIN_SRAM_LO` is 20480 and `WIN_SRAM_HI` is `20480 + 2*HALF` = 544768,
# which is ALSO `ASM24_SIZE` -- the SRAM half pair EXACTLY fills the window.
#
# AND A CORRECTION TO CARRY BACK. ops_amd's 4096 is `4096`, which is NOT
# `usb_cq`'s offset: `usb_cq` is `usb_asm24[4108:4112]` = 4108..4112, and
# 4096 is `USB3`'s own CONTROL buffer size (:42, `alloc_cbuffer(4096)`). Both
# are real, they are different numbers, and this file rows both -- so a port that
# conflated them shows up as a disagreement rather than as a plausible constant.
#
# `CHUNK` is `HALF - 512`, not `HALF`: the reserved sentinel block is what the
# subtraction is, and `usb_wire` adds a second 512 back on for the same reason.
# ===========================================================================

def HALF() -> U32: 262144          # 262144
def SENTINEL_BLOCK() -> U32: 512   # the reserved block at the top of a half
def SLOT() -> U32: 16384           # 16384, the slot a staged payload is aligned to
def USB_MAX_STREAM() -> U32: 1048576  # 1 << 20, one stream's worth

# :208 `HALF, CHUNK, SLOT = 262144, 262144 - 512, 16384`
def CHUNK() -> U32: U32.sub(HALF(), SENTINEL_BLOCK())

# :212 `USB_HOST_SIZE = 32 + 2 * HALF + USB_MAX_STREAM`
def USB_HOST_SIZE() -> U32: U32.add(U32.add(32, U32.mul(2, HALF())), USB_MAX_STREAM())

# :226 `usb_asm24` is `(544768,)` bytes -- 544768, which is `20480 + 2*HALF`, so
# the SRAM half pair EXACTLY fills it. `usb_sram_win_fits` is the row that says so.
def ASM24_SIZE() -> U32: 544768

# :227 `usb_fence = usb_asm24[2048:2052]` -- completed gpu chunks
def WIN_FENCE_LO() -> U32: 2048
def WIN_FENCE_HI() -> U32: U32.add(WIN_FENCE_LO(), 4)

# :228 `usb_cq = usb_asm24[4108:4112]` -- completion queue. NOT 4096.
def WIN_CQ_LO() -> U32: 4108
def WIN_CQ_HI() -> U32: U32.add(WIN_CQ_LO(), 4)

# :229 `usb_sram = usb_asm24[20480 : 20480 + 2 * HALF]`
def WIN_SRAM_LO() -> U32: 20480
def WIN_SRAM_HI() -> U32: U32.add(WIN_SRAM_LO(), U32.mul(2, HALF()))

def sram_win_fits() -> Bool: U32.is_eq(WIN_SRAM_HI(), ASM24_SIZE())

# :214 `usb_link = usb_host(dev)[:24].bitcast(dtypes.uint64)` -- [handle, context,
# previous batch chunks]. THREE words, and the `_host_block` write at :453 packs
# exactly TWO of them (`struct.pack('QQ', ...)` = 16 bytes into the first 16 of a
# 32-byte link header), so the third is the batch counter `usb_copy_rewriter`
# stores into at :308.
def LINK_BYTES() -> U32: 24
def LINK_WORDS() -> U32: U32.div(LINK_BYTES(), 8)
def LINK_PACKED() -> U32: 16

# :215 `usb_stage = usb_host(dev)[32 : 32 + 2 * HALF]` -- the two halves' staging.
# The ZEROS for empty copies are the slice right after it, :427
# `usb_host(dst.device)[32 + 2 * HALF:]`.
def STAGE_LO() -> U32: 32
def STAGE_HI() -> U32: U32.add(STAGE_LO(), U32.mul(2, HALF()))
def ZEROS_LO() -> U32: STAGE_HI()

# :221-223 `usb_vram` is `(2,) uint32`: `usb_go = usb_vram[:1]` (chunk id + 1)
# and `usb_scratch = usb_vram[1:]`. The word offset of the second is 1.
def VRAM_WORDS() -> U32: 2
def VRAM_BYTES() -> U32: U32.mul(VRAM_WORDS(), 4)
def GO_WORD() -> U32: 0
def SCRATCH_WORD() -> U32: 1

# :41-42 the two ctypes buffers: 4 MiB for bulk and 4096 for control. The
# CONTROL one is the 4096 that ops_amd's window third piece also says, and it is
# a different 4096 from `WIN_CQ_LO`.
def BULK_BUF() -> U32: 4194304
def CTRL_BUF() -> U32: 4096

# :321 the usb_table rows are 16 bytes apart -- two uint64 per chunk.
# :321 `(16 * (k + r), addr + ...)` and `(16 * (k + r) + 8, ...)`. There is NO
# address offset constant: the address word IS the row base and the size word is
# base + 8, so `table_addr_word` multiplies and `table_size_word` adds.
def TABLE_ROW_BYTES() -> U32: 16
def TABLE_SIZE_OFF() -> U32: 8

# ===========================================================================
# THE TRANSFER ARITHMETIC.
# ===========================================================================

# :253 `usb_wire(size) = (size + 512 + SLOT - 1) // SLOT * SLOT`. The 512 is a
# SECOND sentinel block (:207), not the one `CHUNK` subtracts, so a staged
# payload is SLOT-aligned AND carries its own reserved block. `usb_wire(0)` is one
# SLOT and not zero -- a zero-byte stream hangs (:431), which is why `usb_copy`
# sends empty loops to `usb_scratch` instead.
def usb_wire(+size: U32) -> U32:
  U32.mul(U32.div(U32.add(U32.add(size, SENTINEL_BLOCK()), U32.sub(SLOT(), 1)), SLOT()), SLOT())

# :254 `usb_sentinel(g) = ((g & 16777215) | 1358954496).cast(uint32)`. 24 bits of
# chunk id with 81 in the top byte, and the mask WRAPS: g = 16777216 answers
# 1358954496, so the sequence is only mod 2^24 and two ids 2^24 apart collide.
def SENTINEL_MAGIC() -> U32: 1358954496  # 1358954496
def SENTINEL_MASK() -> U32: 16777215      # 16777215

def usb_sentinel(+g: U32) -> U32:
  U32.or(U32.and(g, SENTINEL_MASK()), SENTINEL_MAGIC())

def sentinels_collide(+a: U32, +b: U32) -> Bool: U32.is_eq(usb_sentinel(a), usb_sentinel(b))

# :258-261 `usb_split(nbytes, win)`. `divmod` first, then TWO entries: the FULL
# chunks are ONE ranged block and the tail is a scalar. `full if full > 1 else 0`
# is the rule that keeps it off a one-trip loop, and `full == 1` is the boundary
# where a range of 1 collapses to the scalar 1. `nranges` counts the ENTRIES,
# which is 0 for an empty copy, 1 when the size divides and 2 when it does not.
type Split is Data:
  Split{full: U32, tail: U32, ranged: U32, nranges: U32}

# THE LOCALS ARE `f` AND `t`, NOT `full` AND `tail`: `Split{full, tail, ...}`
# is a record whose FIELDS are named `full` and `tail`, and a binder of that name
# shadows the local of the same name with nothing said about it (the recorded
# `usb.bend` trap: a `tail` shadowing a `tail`).
def usb_split(+nbytes: U32, +win: U32) -> Split:
  Split{U32.div(nbytes, win), U32.mod(nbytes, win),
        Bool.pick(U32, U32.is_gt(U32.div(nbytes, win), 1), U32.div(nbytes, win), 0),
        U32.add(Bool.to_u32(U32.is_ne(U32.div(nbytes, win), 0)),
                Bool.to_u32(U32.is_ne(U32.mod(nbytes, win), 0)))}

def Split.full(x: Split) -> U32:
  match x:
    case Split{full, tail, ranged, nranges}: full

def Split.tail(x: Split) -> U32:
  match x:
    case Split{full, tail, ranged, nranges}: tail

def Split.ranged(x: Split) -> U32:
  match x:
    case Split{full, tail, ranged, nranges}: ranged

def Split.nranges(x: Split) -> U32:
  match x:
    case Split{full, tail, ranged, nranges}: nranges


# :257 `usb_window(call)`: a COPYIN (the destination is host memory) moves CHUNK
# per chunk and a COPYOUT moves `2 * CHUNK`. So the win is HALF-dependent, and the
# same byte count splits into TWICE as many chunks on the way in as on the way
# out -- that is the negative case, one row from its opposite.
def usb_window(+is_copyin: Bool) -> U32:
  Bool.pick(U32, is_copyin, CHUNK(), U32.mul(2, CHUNK()))

# ---------------------------------------------------------------------------
# `_f0_out` (:106-107) and `pcie_request` (:113-135).
#
# THE 64-BIT ADDRESS IS A PAIR, ON PURPOSE. `struct.pack('<III', address &
# 4294967295, address >> 32, value)` SPLITS it before anything else happens, and
# `helpers.bend` has `i64_add`/`i64_sub`/`i64_cmp` and NO 64-bit shift, so
# `address >> 32` is not spellable here at all. Representing the address as the
# two dwords it is packed into is not a workaround: it is the value `usb.py`
# computes. `pcie_addr_hi` is therefore the SEAM and the split is the arithmetic.
#     TODO(p3) tinygrad/runtime/support/usb.py:107  `address >> 32`.
# ---------------------------------------------------------------------------

def pcie_offset(+address: U32) -> U32: U32.and(address, 3)

# :118 `byte_en = ((1 << size) - 1) << offset`, with `size` in 1..4 (asserted at
# :114). The shift AMOUNT is the offset and the shift BASE is `1 << size`, so BOTH
# are `Nat`s: a bit-packer whose field positions are runtime U32s is unwritable.
def pcie_byte_en(+sz: Nat, +offset: U32) -> U32:
  U32.shln(U32.sub(U32.shln(1, sz), 1), U32.to_nat(offset))

# :135 `(data >> (8 * offset)) & ((1 << (8 * size)) - 1)`. `size == 4` asks for
# `1 << 32`, which `U32.shln` answers as 0, and `0 - 1` is 4294967295 -- the right
# mask, by arithmetic accident. `usb_pcie_mask_4` is the row that says so instead
# of leaving it to be believed.
def pcie_read_mask(+sz: Nat) -> U32:
  U32.sub(U32.shln(1, U32.to_nat(U32.mul(8, U32.from_nat(sz)))), 1)

def pcie_extract(+data: U32, +sz: Nat, +offset: U32) -> U32:
  U32.and(U32.shrn(data, U32.to_nat(U32.mul(8, offset))), pcie_read_mask(sz))

# :122 the two fast paths, and they are MASKS not equality:
# `(fmt_type & 0b11011111) == 0b01000000` is true for a RANGE of format types.
def FAST_P1_MASK() -> U32: 223    # 0b11011111
def FAST_P1_VAL() -> U32: 64       # 0b01000000
def FAST_P2_MASK() -> U32: 184    # 0b10111000
def FAST_P2_VAL() -> U32: 48       # 0b00110000

# a request that never reads a completion: memory writes and posted messages.
def pcie_no_completion(+fmt_type: U32) -> Bool:
  Bool.or(U32.is_eq(U32.and(fmt_type, FAST_P1_MASK()), FAST_P1_VAL()),
          U32.is_eq(U32.and(fmt_type, FAST_P2_MASK()), FAST_P2_VAL()))

# :139 `fmt_type = (68 if value is not None else 4) | int(bus > 0)`
def CFG_FMT_RD() -> U32: 4
def CFG_FMT_WR() -> U32: 68   # 68

def pcie_cfg_fmt(+has_value: Bool, +bus: U32) -> U32:
  U32.or(Bool.pick(U32, has_value, CFG_FMT_WR(), CFG_FMT_RD()),
         Bool.to_u32(U32.is_gt(bus, 0)))

# :140 `address = (bus << 24) | (dev << 19) | (fn << 16) | (byte_addr & 4095)`
def CFG_BUS_SHIFT() -> U32: 24
def CFG_DEV_SHIFT() -> U32: 19
def CFG_FN_SHIFT() -> U32: 16
def CFG_BA_MASK() -> U32: 4095

def pcie_cfg_addr(+bus: U32, +dev: U32, +fn: U32, +byte_addr: U32) -> U32:
  U32.or(U32.or(U32.shln(bus, U32.to_nat(CFG_BUS_SHIFT())),
                U32.shln(dev, U32.to_nat(CFG_DEV_SHIFT()))),
         U32.or(U32.shln(fn, U32.to_nat(CFG_FN_SHIFT())), U32.and(byte_addr, CFG_BA_MASK())))

# :138 the ASSERT, which is a REFUSAL: `byte_addr >> 12 == 0 and bus >> 8 == 0 and
# dev >> 5 == 0 and fn >> 3 == 0`. Four separate bounds ANDed, and each one has
# its own last-legal value, which is the row set.
def pcie_cfg_addr_ok(+byte_addr: U32, +bus: U32, +dev: U32, +fn: U32) -> Bool:
  Bool.and(Bool.and(U32.is_zero(U32.shrn(byte_addr, 12n)), U32.is_zero(U32.shrn(bus, 8n))),
           Bool.and(U32.is_zero(U32.shrn(dev, 5n)), U32.is_zero(U32.shrn(fn, 3n))))

# :104 and the vendor requests, by NAME.
def REQ_POWER() -> U32: 243       # 243, set_pcie_power
def REQ_F0() -> U32: 240          # 240, the PCIe register window
def REQ_F2() -> U32: 242          # 242, the SRAM / streaming command
def REQ_E4() -> U32: 228          # 228, vendor IN  (chip XDATA read)
def REQ_E5() -> U32: 229          # 229, vendor OUT (chip XDATA write)

# :107 `wValue = fmt_type | (byte_en << 8)`, `wIndex = mode & 3`
def MODE_MASK() -> U32: 3

def pcie_wvalue(+fmt_type: U32, +byte_en: U32) -> U32:
  U32.or(fmt_type, U32.shln(byte_en, 8n))

def pcie_windex(+mode: U32) -> U32: U32.and(mode, MODE_MASK())

# :161 `for off in range(0, length, 255)` with `chunk = min(255, length - off)`.
# 255 is 255 and it is NOT a SLOT: a 16384-byte read is 65 chunks, not 4.
def XDATA_CHUNK() -> U32: 255

def chunk_count(+length: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_zero(length), 0, U32.add(U32.div(U32.sub(length, 1), m), 1))

def xdata_nchunks(+length: U32) -> U32: chunk_count(length, XDATA_CHUNK())

# the SIZE of chunk `i`, `min(255, length - i*255)`, so only the LAST chunk can
# be short and it is short unless the length is a multiple.
def xdata_chunk_at(+length: U32, +i: U32) -> U32:
  U32.min(XDATA_CHUNK(), U32.sub(length, U32.mul(i, XDATA_CHUNK())))

def xdata_chunk_rows(+nm: String, +length: U32, +i: U32) -> List<&2, String>:
  [u1(String.concat([nm, "_n"]), xdata_nchunks(length)),
   u1(String.concat([nm, "_i"]), xdata_chunk_at(length, i))]

# :172-173 `scsi_write`: `round_up(len(buf), 512)` pads to a 512 multiple, the
# wValue is the padded length in 512s, and the wIndex packs `slot_start & 255`
# with `ceildiv(padded, 16384) << 8`.
def SRAM_ALIGN() -> U32: 512
def SRAM_SLOT() -> U32: 16384   # 16384

def scsi_pad(+n: U32) -> U32:
  U32.sub(U32.mul(U32.div(U32.add(n, U32.sub(SRAM_ALIGN(), 1)), SRAM_ALIGN()), SRAM_ALIGN()), n)

def scsi_padded(+n: U32) -> U32:
  U32.mul(U32.div(U32.add(n, U32.sub(SRAM_ALIGN(), 1)), SRAM_ALIGN()), SRAM_ALIGN())

def scsi_wvalue(+n: U32) -> U32: U32.div(scsi_padded(n), SRAM_ALIGN())

def scsi_windex(+n: U32, +slot_start: U32) -> U32:
  U32.or(U32.and(slot_start, 255),
         U32.shln(U32.div(U32.add(scsi_padded(n), U32.sub(SRAM_SLOT(), 1)), SRAM_SLOT()), 8n))

# :147-149 the streaming chunk loop, `range(0, len(data), USB_MAX_STREAM)` with
# `self._f0_out(96, 15, address + off, len(chunk) // 4, mode=1)`. 15 is the
# byte enable for a WHOLE dword; 96 is the write format type and 32 the read.
def STREAM_FMT_WR() -> U32: 96   # 96
def STREAM_FMT_RD() -> U32: 32   # 32
def STREAM_BYTE_EN() -> U32: 15  # 15

def pcie_mem_nchunks(+nbytes: U32) -> U32: chunk_count(nbytes, USB_MAX_STREAM())

def pcie_mem_dwords(+nbytes: U32) -> U32: U32.div(nbytes, 4)

# :146 and :154 the 4-byte alignment REFUSALS, and they are about the SIZE, so
# the last legal size is 4*(n-1) and the first illegal is 4n+1.
def aligned4(+n: U32) -> Bool: U32.is_zero(U32.mod(n, 4))

# :375 `wire = (size + (second > 0 ? 512 : 0) + 511) // 512 * 512` where
# `second = (size - CHUNK).maximum(0)`. So a payload that fits ONE half carries no
# sentinel and a payload that spills carries one -- 512 granularity, not SLOT.
def copyout_first(+size: U32) -> U32: U32.min(size, CHUNK())

# THE CLAMP IS EXPLICIT BECAUSE `U32` WRAPS. The source is
# `(size - CHUNK).maximum(0)`, and for `size = CHUNK - 1` a U32 subtraction is
# 4294967295, so `U32.max(4294967295, 0)` is 4294967295 -- the OPPOSITE of Python's
# `max(-1, 0) == 0`. `usb_co_chunk_m1_second` is the row that caught it, and
# without the clamp `usb_co_chunk_m1_wire` is a whole 512 bytes too big.
def copyout_second(+size: U32) -> U32:
  Bool.pick(U32, U32.is_ge(size, CHUNK()), U32.sub(size, CHUNK()), 0)

def copyout_wire(+size: U32) -> U32:
  U32.mul(U32.div(U32.add(U32.add(size, U32.mul(Bool.to_u32(U32.is_gt(copyout_second(size), 0)),
                                             SENTINEL_BLOCK())),
                        U32.sub(SRAM_ALIGN(), 1)), SRAM_ALIGN()), SRAM_ALIGN())

# ---------------------------------------------------------------------------
# :336-355 `usb_chunk`. `end = (half + 1) * HALF`, so half 0's window is
# `[HALF - wire, HALF)` and half 1's is `[2*HALF - wire, 2*HALF)`, and the dword
# index of the sentinel word is `end // 4 - 1`. The three `field("...")` stores
# (:350-351) address `status`, `length` and `buffer` BY NAME, so the ordinals
# `usb_fld_transfer_*_ix` are part of this arithmetic and not a curiosity: a
# transposed pair in that field list writes the timeout where the status goes.
# ---------------------------------------------------------------------------
def chunk_end(+half: U32) -> U32: U32.mul(U32.add(half, 1), HALF())

def chunk_off(+half: U32, +wire: U32) -> U32: U32.sub(chunk_end(half), wire)

def chunk_sentinel_word(+half: U32) -> U32: U32.sub(U32.div(chunk_end(half), 4), 1)

# :348 `usb_ctrl(h, 64, 242, wire // 512, ((end - wire) // SLOT) | (wire // SLOT << 8), ...)`
def chunk_wvalue(+wire: U32) -> U32: U32.div(wire, SRAM_ALIGN())

def chunk_windex(+half: U32, +wire: U32) -> U32:
  U32.or(U32.div(chunk_off(half, wire), SLOT()), U32.shln(U32.div(wire, SLOT()), 8n))

# :321 the usb_table row for chunk `k + r`: the host ADDRESS at `16 * (k + r)`
# and the BYTE COUNT at `16 * (k + r) + 8`. Two rows per chunk, never adjacent.
def table_addr_word(+k: U32, +r: U32) -> U32: U32.mul(TABLE_ROW_BYTES(), U32.add(k, r))

def table_size_word(+k: U32, +r: U32) -> U32:
  U32.add(table_addr_word(k, r), TABLE_SIZE_OFF())


# :180-182 `_off_from_index`: an integer index is `el_sz` bytes at `index * el_sz`
# and a SLICE is `[start * el_sz, (stop - start) * el_sz)`. Two ARMS and not one
# arithmetic, and `index.stop or len(self)` means a slice with no `stop` runs to
# the end of the buffer -- so `stop` is a PARAMETER here and the `or len(self)`
# fallback is the seam's `len`.
def off_of_index(+index: U32, +el_sz: U32) -> U32: U32.mul(index, el_sz)

# THE INTEGER ARM AND THE SLICE ARM ARE SEPARATE FUNCTIONS, because :180-182 is
# two arms and an off-by-one in one does not move the other.
def off_of_index_sz(+el_sz: U32) -> U32: el_sz

def off_of_slice_at(+start: U32, +el_sz: U32) -> U32: U32.mul(start, el_sz)

def off_of_slice_sz(+start: U32, +stop: U32, +el_sz: U32) -> U32:
  U32.mul(U32.sub(stop, start), el_sz)

# :334 `(((need - fence) & 255) > 1)` -- the fence is read ONE BYTE so it cannot
# tear, so the comparison is mod 256 and `need - fence == 2` is ALREADY drained.
# `U32` WRAPS, which is exactly that mod: 1 - 3 is 4294967294 and `& 255` is
# 254, so a fence AHEAD of need wraps to the far side and the wait goes on.
def DRAIN_MOD() -> U32: 255

def drained_step(+need: U32, +fence: U32) -> Bool:
  U32.is_gt(U32.and(U32.sub(need, fence), DRAIN_MOD()), 1)

# :387 `is_remote`: a PARAM whose tag does NOT start with one of four prefixes.
# The test is `str(p.tag).startswith((...))`, so a tag that merely CONTAINS a
# prefix is NOT remote -- and the four prefixes are a tuple of STRINGS, so they
# are diffed as strings and not as a boolean about a boolean.
def REMOTE_N() -> U32: 4

def remote_prefixes() -> String: "usb_host usb_xfer put_value cmdbuf_copy"

def is_remote_prefix(+tag: String, +p: String) -> Bool: String.starts_with(tag, p)

def remote_rows(+nm: String, +tag: String) -> List<&2, String>:
  [b1(String.concat([nm, "_usb_host"]), is_remote_prefix(tag, "usb_host")),
   b1(String.concat([nm, "_usb_xfer"]), is_remote_prefix(tag, "usb_xfer")),
   b1(String.concat([nm, "_put_value"]), is_remote_prefix(tag, "put_value")),
   b1(String.concat([nm, "_cmdbuf_copy"]), is_remote_prefix(tag, "cmdbuf_copy"))]
# PORT-INTERNAL, and the only constant in this file with no line in usb.py. It
# is 4294967295 so that it cannot be confused with a real `enum_libusb_*` value:
# the negative error codes are the only ones in that range and the largest is -1,
# which is LIBUSB_ERROR_IO. `usb_enumval_absent_not_found` is the row.
def NOT_FOUND() -> U32: 4294967295

def enum_val.go(n: Nat, +nm: String, es: List<&2, Ent>, hit: U32) -> U32:
  match n:
    case 0n: hit
    case 1n+m:
      match es:
        case Nil{}: hit
        case Ent{vv, nn} <> t: enum_val.go(m, nm, t, Bool.pick(U32, String.eq(nn, nm), vv, hit))

def enum_val(+nm: String, +es: List<&2, Ent>) -> U32:
  enum_val.go(List.length(&2, Ent, es), nm, es, NOT_FOUND())

def E_CLASS_CODE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_CLASS_PER_INTERFACE"}, Ent{1, "LIBUSB_CLASS_AUDIO"},
   Ent{2, "LIBUSB_CLASS_COMM"}, Ent{3, "LIBUSB_CLASS_HID"},
   Ent{5, "LIBUSB_CLASS_PHYSICAL"}, Ent{6, "LIBUSB_CLASS_PTP"},
   Ent{7, "LIBUSB_CLASS_PRINTER"},
   Ent{8, "LIBUSB_CLASS_MASS_STORAGE"}, Ent{9, "LIBUSB_CLASS_HUB"},
   Ent{10, "LIBUSB_CLASS_DATA"}, Ent{11, "LIBUSB_CLASS_SMART_CARD"},
   Ent{13, "LIBUSB_CLASS_CONTENT_SECURITY"}, Ent{14, "LIBUSB_CLASS_VIDEO"},
   Ent{15, "LIBUSB_CLASS_PERSONAL_HEALTHCARE"}, Ent{220, "LIBUSB_CLASS_DIAGNOSTIC_DEVICE"},
   Ent{224, "LIBUSB_CLASS_WIRELESS"}, Ent{239, "LIBUSB_CLASS_MISCELLANEOUS"},
   Ent{254, "LIBUSB_CLASS_APPLICATION"}, Ent{255, "LIBUSB_CLASS_VENDOR_SPEC"}]

def E_DESCRIPTOR_TYPE() -> List<&2, Ent>:
  [Ent{1, "LIBUSB_DT_DEVICE"}, Ent{2, "LIBUSB_DT_CONFIG"},
   Ent{3, "LIBUSB_DT_STRING"}, Ent{4, "LIBUSB_DT_INTERFACE"},
   Ent{5, "LIBUSB_DT_ENDPOINT"}, Ent{11, "LIBUSB_DT_INTERFACE_ASSOCIATION"},
   Ent{15, "LIBUSB_DT_BOS"}, Ent{16, "LIBUSB_DT_DEVICE_CAPABILITY"},
   Ent{33, "LIBUSB_DT_HID"}, Ent{34, "LIBUSB_DT_REPORT"},
   Ent{35, "LIBUSB_DT_PHYSICAL"}, Ent{41, "LIBUSB_DT_HUB"},
   Ent{42, "LIBUSB_DT_SUPERSPEED_HUB"}, Ent{48, "LIBUSB_DT_SS_ENDPOINT_COMPANION"}]

def E_ENDPOINT_DIRECTION() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_ENDPOINT_OUT"}, Ent{128, "LIBUSB_ENDPOINT_IN"}]

def E_ENDPOINT_TRANSFER_TYPE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_ENDPOINT_TRANSFER_TYPE_CONTROL"},
   Ent{1, "LIBUSB_ENDPOINT_TRANSFER_TYPE_ISOCHRONOUS"},
   Ent{2, "LIBUSB_ENDPOINT_TRANSFER_TYPE_BULK"},
   Ent{3, "LIBUSB_ENDPOINT_TRANSFER_TYPE_INTERRUPT"}]

def E_TRANSFER_TYPE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_TRANSFER_TYPE_CONTROL"},
   Ent{1, "LIBUSB_TRANSFER_TYPE_ISOCHRONOUS"},
   Ent{2, "LIBUSB_TRANSFER_TYPE_BULK"},
   Ent{3, "LIBUSB_TRANSFER_TYPE_INTERRUPT"},
   Ent{4, "LIBUSB_TRANSFER_TYPE_BULK_STREAM"}]

def E_TRANSFER_STATUS() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_TRANSFER_COMPLETED"}, Ent{1, "LIBUSB_TRANSFER_ERROR"},
   Ent{2, "LIBUSB_TRANSFER_TIMED_OUT"}, Ent{3, "LIBUSB_TRANSFER_CANCELLED"},
   Ent{4, "LIBUSB_TRANSFER_STALL"}, Ent{5, "LIBUSB_TRANSFER_NO_DEVICE"},
   Ent{6, "LIBUSB_TRANSFER_OVERFLOW"}]

def E_TRANSFER_FLAGS() -> List<&2, Ent>:
  [Ent{1, "LIBUSB_TRANSFER_SHORT_NOT_OK"},
   Ent{2, "LIBUSB_TRANSFER_FREE_BUFFER"},
   Ent{4, "LIBUSB_TRANSFER_FREE_TRANSFER"},
   Ent{8, "LIBUSB_TRANSFER_ADD_ZERO_PACKET"}]

# the only error code `usb.py` names (:328). The table is whole because it is
# the table `checked` (:16) turns a negative rc into a message with.
def E_ERROR() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_SUCCESS"}, Ent{4294967295, "LIBUSB_ERROR_IO"},
   Ent{4294967294, "LIBUSB_ERROR_INVALID_PARAM"},
   Ent{4294967293, "LIBUSB_ERROR_ACCESS"}, Ent{4294967292, "LIBUSB_ERROR_NO_DEVICE"},
   Ent{4294967291, "LIBUSB_ERROR_NOT_FOUND"}, Ent{4294967290, "LIBUSB_ERROR_BUSY"},
   Ent{4294967289, "LIBUSB_ERROR_TIMEOUT"}, Ent{4294967288, "LIBUSB_ERROR_OVERFLOW"},
   Ent{4294967287, "LIBUSB_ERROR_PIPE"}, Ent{4294967286, "LIBUSB_ERROR_INTERRUPTED"},
   Ent{4294967285, "LIBUSB_ERROR_NO_MEM"}, Ent{4294967284, "LIBUSB_ERROR_NOT_SUPPORTED"},
   Ent{4294967197, "LIBUSB_ERROR_OTHER"}]

def E_REQUEST_TYPE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_REQUEST_TYPE_STANDARD"}, Ent{32, "LIBUSB_REQUEST_TYPE_CLASS"},
   Ent{64, "LIBUSB_REQUEST_TYPE_VENDOR"}, Ent{96, "LIBUSB_REQUEST_TYPE_RESERVED"}]

def E_STANDARD_REQUEST() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_REQUEST_GET_STATUS"}, Ent{1, "LIBUSB_REQUEST_CLEAR_FEATURE"},
   Ent{3, "LIBUSB_REQUEST_SET_FEATURE"}, Ent{5, "LIBUSB_REQUEST_SET_ADDRESS"},
   Ent{6, "LIBUSB_REQUEST_GET_DESCRIPTOR"}, Ent{7, "LIBUSB_REQUEST_SET_DESCRIPTOR"},
   Ent{8, "LIBUSB_REQUEST_GET_CONFIGURATION"}, Ent{9, "LIBUSB_REQUEST_SET_CONFIGURATION"},
   Ent{10, "LIBUSB_REQUEST_GET_INTERFACE"}, Ent{11, "LIBUSB_REQUEST_SET_INTERFACE"},
   Ent{12, "LIBUSB_REQUEST_SYNCH_FRAME"}, Ent{48, "LIBUSB_REQUEST_SET_SEL"},
   Ent{49, "LIBUSB_SET_ISOCH_DELAY"}]

def E_REQUEST_RECIPIENT() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_RECIPIENT_DEVICE"}, Ent{1, "LIBUSB_RECIPIENT_INTERFACE"},
   Ent{2, "LIBUSB_RECIPIENT_ENDPOINT"}, Ent{3, "LIBUSB_RECIPIENT_OTHER"}]

def E_SPEED() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_SPEED_UNKNOWN"}, Ent{1, "LIBUSB_SPEED_LOW"},
   Ent{2, "LIBUSB_SPEED_FULL"}, Ent{3, "LIBUSB_SPEED_HIGH"},
   Ent{4, "LIBUSB_SPEED_SUPER"}, Ent{5, "LIBUSB_SPEED_SUPER_PLUS"}]

def E_SUPPORTED_SPEED() -> List<&2, Ent>:
  [Ent{1, "LIBUSB_LOW_SPEED_OPERATION"}, Ent{2, "LIBUSB_FULL_SPEED_OPERATION"},
   Ent{4, "LIBUSB_HIGH_SPEED_OPERATION"}, Ent{8, "LIBUSB_SUPER_SPEED_OPERATION"}]

def E_LOG_LEVEL() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_LOG_LEVEL_NONE"}, Ent{1, "LIBUSB_LOG_LEVEL_ERROR"},
   Ent{2, "LIBUSB_LOG_LEVEL_WARNING"}, Ent{3, "LIBUSB_LOG_LEVEL_INFO"},
   Ent{4, "LIBUSB_LOG_LEVEL_DEBUG"}]

def E_LOG_CB_MODE() -> List<&2, Ent>:
  [Ent{1, "LIBUSB_LOG_CB_GLOBAL"}, Ent{2, "LIBUSB_LOG_CB_CONTEXT"}]

# :25 `libusb.LIBUSB_OPTION_LOG_LEVEL`, value 0. `LIBUSB_OPTION_MAX` is in it.
def E_OPTION() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_OPTION_LOG_LEVEL"}, Ent{1, "LIBUSB_OPTION_USE_USBDK"},
   Ent{2, "LIBUSB_OPTION_NO_DEVICE_DISCOVERY"}, Ent{3, "LIBUSB_OPTION_LOG_CB"},
   Ent{4, "LIBUSB_OPTION_MAX"}]

def E_ISO_SYNC_TYPE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_ISO_SYNC_TYPE_NONE"}, Ent{1, "LIBUSB_ISO_SYNC_TYPE_ASYNC"},
   Ent{2, "LIBUSB_ISO_SYNC_TYPE_ADAPTIVE"}, Ent{3, "LIBUSB_ISO_SYNC_TYPE_SYNC"}]

def E_ISO_USAGE_TYPE() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_ISO_USAGE_TYPE_DATA"}, Ent{1, "LIBUSB_ISO_USAGE_TYPE_FEEDBACK"},
   Ent{2, "LIBUSB_ISO_USAGE_TYPE_IMPLICIT"}]

def E_CAPABILITY() -> List<&2, Ent>:
  [Ent{0, "LIBUSB_CAP_HAS_CAPABILITY"}, Ent{1, "LIBUSB_CAP_HAS_HOTPLUG"},
   Ent{256, "LIBUSB_CAP_HAS_HID_ACCESS"},
   Ent{257, "LIBUSB_CAP_SUPPORTS_DETACH_KERNEL_DRIVER"}]

def E_BOS_TYPE() -> List<&2, Ent>:
  [Ent{1, "LIBUSB_BT_WIRELESS_USB_DEVICE_CAPABILITY"},
   Ent{2, "LIBUSB_BT_USB_2_0_EXTENSION"},
   Ent{3, "LIBUSB_BT_SS_USB_DEVICE_CAPABILITY"},
   Ent{4, "LIBUSB_BT_CONTAINER_ID"}, Ent{5, "LIBUSB_BT_PLATFORM_DESCRIPTOR"}]

def E_USB_2_0_EXTENSION_ATTRIBUTES() -> List<&2, Ent>:
  [Ent{2, "LIBUSB_BM_LPM_SUPPORT"}]

def E_SS_USB_DEVICE_CAPABILITY_ATTRIBUTES() -> List<&2, Ent>:
  [Ent{2, "LIBUSB_BM_LTM_SUPPORT"}]

# THE USB3 CONSTANTS THE TRACE NAMES, all four from `usb.py`: the control string
# buffer (:50 `_buf`, 256), the interface and alt-setting (:55-62, both 0), the
# configuration (:60, 1) and the log level (:25, 4).
def USB3_STRING_BUF() -> U32: 256
def USB3_IFACE() -> U32: 0
def USB3_ALT() -> U32: 0
def USB3_CONFIG() -> U32: 1
def USB3_LOG_LEVEL_DEBUG() -> U32: 4

# ===========================================================================
# THE LAST-WINS FIXTURE. The generated dicts are LAST-wins -- a repeated key is
# overwritten by the later literal -- and both folds have to agree with that. But
# NONE of the twenty-one live tables can exercise the rule: 6 is the only value
# that ever repeats, and `LIBUSB_CLASS_IMAGE` is not a table entry (it is a walrus
# binding the dict overwrote), so after that correction every value in every table
# is UNIQUE and so is every name. `M36` and `M37` measured 0 rows moved, and a 0
# here is a REQUEST FOR A FIXTURE, not a coverage claim.
#
# So the rule gets a table BUILT TO EXERCISE IT: value 10 is named ALPHA then
# GAMMA, the name SYNTH_BETA is carried by values 11 and 12, and the seven rows
# below are the only fixtures in the file that see either fold's tie-break.
# ===========================================================================

def E_SYNTH() -> List<&2, Ent>:
  [Ent{10, "SYNTH_ALPHA"}, Ent{11, "SYNTH_BETA"}, Ent{10, "SYNTH_GAMMA"},
   Ent{12, "SYNTH_BETA"}, Ent{13, "SYNTH_DELTA"}]

# THE TWO WALRUS GLOBALS at 6. `(LIBUSB_CLASS_IMAGE:=6)` runs and binds a
# module global, then `(LIBUSB_CLASS_PTP:=6)` overwrites the same dict KEY, so
# IMAGE is a constant that is not a table entry. `usb_classcode_image_in_dict`
# is the row that says so.
def LIBUSB_CLASS_IMAGE() -> U32: 6
def LIBUSB_CLASS_PTP() -> U32: 6

# ===========================================================================
# THE STRUCT FIELD LISTS. `usb.py` addresses `struct_libusb_transfer` THREE
# TIMES BY NAME (:350-351 `field("status")`, `field("length")`,
# `field("buffer")`) and reads `struct_libusb_device_descriptor` FOUR times
# (:34 `idVendor`/`idProduct`, :50 `iProduct`), and `usb_xfer` (:218) sizes its
# placeholder with `ctypes.sizeof(struct_libusb_transfer)`. So the field lists
# are not background: they are the arguments.
#
# Each struct is ONE space-separated String in DECLARATION ORDER, which is what
# `__annotations__` preserves and what `register_fields` writes out in the same
# order. A String and not a list of records because a list of records is N
# constructions whose ORDER a diff of `name=value` lines cannot see, while
# `String.concat` drops a literal silently -- so the gate diffs these Strings
# WHOLE against the header's field names. `usb_fld_*` rows print them.
# ===========================================================================

type Fld is Data:
  Fld{ix: U32, name: String}

def Fld.name(x: Fld) -> String:
  match x:
    case Fld{ix, name}: name

def Fld.ix(x: Fld) -> U32:
  match x:
    case Fld{ix, name}: ix

# the ORDINAL of a field NAME in a list, and `NOT_FOUND` when absent. :350's
# `field("status")` is this lookup, and its index IS the byte offset divisor in
# `usb_chunk` (:344 `end // 4 - 1`), so a lookup that answers the wrong index
# is a wrong transfer.
def Fld.find(+nm: String, fs: List<&2, Fld>) -> U32:
  match fs:
    case Nil{}: NOT_FOUND()
    case Fld{ix, fn} <> t: Bool.pick(U32, String.eq(fn, nm), ix, Fld.find(nm, t))

def Fld.at(+ix: U32, fs: List<&2, Fld>) -> String:
  match fs:
    case Nil{}: ""
    case Fld{fx, fn} <> t: Bool.pick(String, U32.is_eq(fx, ix), fn, Fld.at(ix, t))

# THE LIST IS THE FIRST ARGUMENT because a decreasing self-call is read left to
# right, each argument passing unchanged until one shrinks -- so the argument
# that shrinks has to come first (the fuel `Nat` comes second here and inverts
# the order the source counts in).
def fields.go(rest: List<&2, String>, +ix: Nat) -> List<&2, Fld>:
  match rest:
    case Nil{}: Nil{}
    case head <> t: List.append(&2, Fld, [Fld{U32.from_nat(ix), head}], fields.go(t, Nat.add(ix, 1n)))

def fields(s: String) -> List<&2, Fld>:
  fields.go(String.split(s, Char.from_u32(32)), 0n)

# the ROUND TRIP, and that is the point: a row that printed the literal String
# would be a tautology, so the gate diffs what `String.split` and `fields`
# actually produced. A dropped field, a reordered pair or a split that eats the
# separator all change this line.
# `String.join` is HEAD-FIRST and `List.map`'s template wants a `List<&1, A>`
# while a fold produces `List<&2, A>`, so the projection is hand-folded the way
# `helpers.bend`'s `ix_map` is (jit.bend records that arity trap).
def flds.go(fs: List<&2, Fld>) -> List<&2, String>:
  match fs:
    case Nil{}: Nil{}
    case f <> t: Fld.name(f) <> flds.go(t)

def flds(fs: List<&2, Fld>) -> String: String.join(flds.go(fs), " ")

def F_TRANSFER() -> List<&2, Fld>:
  fields("dev_handle flags endpoint type timeout status length actual_length callback user_data buffer num_iso_packets iso_packet_desc")

def F_DEVICE_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bcdUSB bDeviceClass bDeviceSubClass bDeviceProtocol bMaxPacketSize0 idVendor idProduct bcdDevice iManufacturer iProduct iSerialNumber bNumConfigurations")

def F_ENDPOINT_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bEndpointAddress bmAttributes wMaxPacketSize bInterval bRefresh bSynchAddress extra extra_length")

def F_INTERFACE_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bInterfaceNumber bAlternateSetting bNumEndpoints bInterfaceClass bInterfaceSubClass bInterfaceProtocol iInterface endpoint extra extra_length")

def F_CONFIG_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType wTotalLength bNumInterfaces bConfigurationValue iConfiguration bmAttributes MaxPower interface extra extra_length")

def F_INTERFACE() -> List<&2, Fld>:
  fields("altsetting num_altsetting")

def F_INTERFACE_ASSOCIATION_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bFirstInterface bInterfaceCount bFunctionClass bFunctionSubClass bFunctionProtocol iFunction")

def F_INTERFACE_ASSOCIATION_DESCRIPTOR_ARRAY() -> List<&2, Fld>:
  fields("iad length")

def F_CONTROL_SETUP() -> List<&2, Fld>:
  fields("bmRequestType bRequest wValue wIndex wLength")

def F_ISO_PACKET_DESCRIPTOR() -> List<&2, Fld>:
  fields("length actual_length status")

def F_BOS_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType wTotalLength bNumDeviceCaps dev_capability")

def F_BOS_DEV_CAPABILITY_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bDevCapabilityType dev_capability_data")

def F_SS_USB_DEVICE_CAPABILITY_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bDevCapabilityType bmAttributes wSpeedSupported bFunctionalitySupport bU1DevExitLat bU2DevExitLat")

def F_SS_ENDPOINT_COMPANION_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bMaxBurst bmAttributes wBytesPerInterval")

def F_USB_2_0_EXTENSION_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bDevCapabilityType bmAttributes")

def F_CONTAINER_ID_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bDevCapabilityType bReserved ContainerID")

def F_PLATFORM_DESCRIPTOR() -> List<&2, Fld>:
  fields("bLength bDescriptorType bDevCapabilityType bReserved PlatformCapabilityUUID CapabilityData")

def F_INIT_OPTION() -> List<&2, Fld>:
  fields("option value")

def F_INIT_OPTION_VALUE() -> List<&2, Fld>:
  fields("ival log_cbval")

def F_POLLFD() -> List<&2, Fld>:
  fields("fd events")

def F_VERSION() -> List<&2, Fld>:
  fields("major minor micro nano rc describe")

def F_TIMEVAL() -> List<&2, Fld>:
  fields("tv_sec tv_usec")

# ===========================================================================
# STRUCT SIZES. `ctypes.sizeof` is the SEAM's value, so these are constants
# read out of the header rather than derived -- and `usb_xfer` (:218) makes one
# of them the element count of a UOp placeholder, which makes it arithmetic and
# not a comment. `SIZ_*` is the row set; `SIZE_NOT_FOUND` is what `ctypes.sizeof`
# answers for the four OPAQUE structs (`struct_libusb_context`,
# `struct_libusb_device`, `struct_libusb_device_handle`, and `dll`), which is
# WHY those three are pointers in `usb.py`.
# ===========================================================================

def SIZ_TRANSFER() -> U32: 64
def SIZ_DEVICE_DESCRIPTOR() -> U32: 18
def SIZ_ENDPOINT_DESCRIPTOR() -> U32: 32
def SIZ_INTERFACE_DESCRIPTOR() -> U32: 40
def SIZ_CONFIG_DESCRIPTOR() -> U32: 40
def SIZ_INTERFACE() -> U32: 16
def SIZ_INTERFACE_ASSOCIATION_DESCRIPTOR() -> U32: 8
def SIZ_INTERFACE_ASSOCIATION_DESCRIPTOR_ARRAY() -> U32: 16
def SIZ_CONTROL_SETUP() -> U32: 8
def SIZ_ISO_PACKET_DESCRIPTOR() -> U32: 12
def SIZ_BOS_DESCRIPTOR() -> U32: 8
def SIZ_BOS_DEV_CAPABILITY_DESCRIPTOR() -> U32: 3
def SIZ_SS_USB_DEVICE_CAPABILITY_DESCRIPTOR() -> U32: 10
def SIZ_SS_ENDPOINT_COMPANION_DESCRIPTOR() -> U32: 6
def SIZ_USB_2_0_EXTENSION_DESCRIPTOR() -> U32: 8
def SIZ_CONTAINER_ID_DESCRIPTOR() -> U32: 20
def SIZ_PLATFORM_DESCRIPTOR() -> U32: 20
def SIZ_INIT_OPTION() -> U32: 16
def SIZ_INIT_OPTION_VALUE() -> U32: 8
def SIZ_POLLFD() -> U32: 8
def SIZ_VERSION() -> U32: 24
def SIZ_TIMEVAL() -> U32: 16

# ===========================================================================
# THE ROW LANE. Every row is built as ONE `"name=value"` STRING by a PURE def
# and the whole block is printed with one `IO.print` joined on "\n". That is not
# a style choice: a `do IO<Unit>:` arm and a bare expression arm have DIFFERENT
# types in Bend 2.0.34 (`agent-core.md`'s sibling of the `SOME PROOFS FAIL`
# exit-status trap), so an effectful walk over a list is a type error where a
# pure one is not. Pure rows also make the harness's job exact -- one line per
# fact, and `name=value` WHOLE.
#
# `show_i32` exists so the six signed libusb error codes diff against CPython's
# `-10` and not against 4294967286: a U32 bit pattern is how the header stores
# them and a C `int` is how CPython prints them.
# ===========================================================================


# ---------------------------------------------------------------------------
# BOTH DIRECTIONS, for every enum, as ONE row per entry. `enum_nm` is the
# header's dict and `enum_val` its inverse, so the pair of rows is a round trip
# over the same list and neither direction can be right while the other is
# wrong.
# ---------------------------------------------------------------------------

# ONE entry, BOTH rows, from ONE walk.
#
# TWO LISTS, ON PURPOSE. This MATCHES `r` (the walk) and folds over `es` (the
# whole table), so `es` is never matched and so is never consumed -- the version
# that matched the table and kept SEEN SETS instead handed each `+` slot to
# `List.contains`, which MOVES it, and the cons after it built an empty list.
# That is the whole bug the differ found: zero `_n_` rows, every seen set already
# full. `r` is the REVERSED table so the rows come out in the header's own order.
def enum_rows.go(+tag: String, +es: List<&2, Ent>, r: List<&2, Ent>,
                 +acc: List<&2, String>) -> List<&2, String>:
  match r:
    case Nil{}: acc
    case Ent{v, nm} <> t:
      +vv = v
      +nn = nm
      i1(String.concat(["usb_", tag, "_v_", nn]), enum_val(nn, es))
        <> (s1(String.concat(["usb_", tag, "_n_", nn]), enum_nm(vv, es)) <> enum_rows.go(tag, es, t, acc))

def enum_rows(+tag: String, +es: List<&2, Ent>) -> List<&2, String>:
  enum_rows.go(tag, es, List.reverse(&2, Ent, es), Nil{})

def enum_show(tag: String, es: List<&2, Ent>) -> IO(Unit):
  IO.print(lines_of(enum_rows(tag, es)))

# ONE `IO.print` PER SECTION, and not a `do IO<Unit>:` chain: a `do` block's
# arms must all be statements, so a block cannot be followed by the next `def`.
# `concat_str` over a literal of the 22 table walks keeps the order readable and
# costs one line of plumbing instead of 22 bindings.
def t_consts() -> IO(Unit):
  IO.print(lines_of(concat_str(
    [enum_rows("classcode", E_CLASS_CODE()), enum_rows("dtype", E_DESCRIPTOR_TYPE()),
     enum_rows("epdir", E_ENDPOINT_DIRECTION()), enum_rows("eptype", E_ENDPOINT_TRANSFER_TYPE()),
     enum_rows("xtype", E_TRANSFER_TYPE()), enum_rows("xstatus", E_TRANSFER_STATUS()),
     enum_rows("xflags", E_TRANSFER_FLAGS()), enum_rows("err", E_ERROR()),
     enum_rows("reqtype", E_REQUEST_TYPE()), enum_rows("streq", E_STANDARD_REQUEST()),
     enum_rows("recip", E_REQUEST_RECIPIENT()), enum_rows("speed", E_SPEED()),
     enum_rows("supspeed", E_SUPPORTED_SPEED()), enum_rows("loglevel", E_LOG_LEVEL()),
     enum_rows("logcb", E_LOG_CB_MODE()), enum_rows("option", E_OPTION()),
     enum_rows("isosync", E_ISO_SYNC_TYPE()), enum_rows("isousage", E_ISO_USAGE_TYPE()),
     enum_rows("cap", E_CAPABILITY()), enum_rows("bostype", E_BOS_TYPE()),
     enum_rows("ext20", E_USB_2_0_EXTENSION_ATTRIBUTES()),
     enum_rows("sscap", E_SS_USB_DEVICE_CAPABILITY_ATTRIBUTES()),
     [i1("usb_err_interrupted_signed", enum_val("LIBUSB_ERROR_INTERRUPTED", E_ERROR())),
      i1("usb_err_other_signed", enum_val("LIBUSB_ERROR_OTHER", E_ERROR())),
      i1("usb_err_success_signed", enum_val("LIBUSB_SUCCESS", E_ERROR())),
      u1("usb_opt_log_level", enum_val("LIBUSB_OPTION_LOG_LEVEL", E_OPTION())),
      u1("usb_opt_log_level_is_debug", enum_val("LIBUSB_LOG_LEVEL_DEBUG", E_LOG_LEVEL())),
      u1("usb_opt_max", enum_val("LIBUSB_OPTION_MAX", E_OPTION())),
      s1("usb_classcode_6_name", enum_nm(6, E_CLASS_CODE())),
      u1("usb_classcode_len", U32.from_nat(List.length(&2, Ent, E_CLASS_CODE()))),
      u1("usb_classcode_image_walrus", LIBUSB_CLASS_IMAGE()),
      u1("usb_classcode_image_in_dict",
         Bool.to_u32(U32.is_ne(enum_val("LIBUSB_CLASS_IMAGE", E_CLASS_CODE()), NOT_FOUND()))),
      u1("usb_classcode_ptp_walrus", LIBUSB_CLASS_PTP()),
      u1("usb_enumval_notfound_is_io", enum_val("LIBUSB_ENUM_NONE", E_ERROR())),
      s1("usb_enumnm_absent_4242", enum_nm(4242, E_CLASS_CODE())),
      s1("usb_synth_n_10", enum_nm(10, E_SYNTH())),
      s1("usb_synth_n_11", enum_nm(11, E_SYNTH())),
      s1("usb_synth_n_13", enum_nm(13, E_SYNTH())),
      u1("usb_synth_v_alpha", enum_val("SYNTH_ALPHA", E_SYNTH())),
      u1("usb_synth_v_gamma", enum_val("SYNTH_GAMMA", E_SYNTH())),
      u1("usb_synth_v_beta", enum_val("SYNTH_BETA", E_SYNTH())),
      u1("usb_synth_v_absent", enum_val("SYNTH_NOPE", E_SYNTH())),
      s1("usb_enumnm_absent_neg1", enum_nm(4294967295, E_ERROR()))]])))

def t_structs() -> IO(Unit):
  IO.print(lines_of(
    [s1("usb_fld_transfer", flds(F_TRANSFER())),
     s1("usb_fld_device_descriptor", flds(F_DEVICE_DESCRIPTOR())),
     s1("usb_fld_endpoint_descriptor", flds(F_ENDPOINT_DESCRIPTOR())),
     s1("usb_fld_interface_descriptor", flds(F_INTERFACE_DESCRIPTOR())),
     s1("usb_fld_config_descriptor", flds(F_CONFIG_DESCRIPTOR())),
     s1("usb_fld_interface", flds(F_INTERFACE())),
     s1("usb_fld_interface_association_descriptor", flds(F_INTERFACE_ASSOCIATION_DESCRIPTOR())),
     s1("usb_fld_interface_association_descriptor_array", flds(F_INTERFACE_ASSOCIATION_DESCRIPTOR_ARRAY())),
     s1("usb_fld_control_setup", flds(F_CONTROL_SETUP())),
     s1("usb_fld_iso_packet_descriptor", flds(F_ISO_PACKET_DESCRIPTOR())),
     s1("usb_fld_bos_descriptor", flds(F_BOS_DESCRIPTOR())),
     s1("usb_fld_bos_dev_capability_descriptor", flds(F_BOS_DEV_CAPABILITY_DESCRIPTOR())),
     s1("usb_fld_ss_usb_device_capability_descriptor", flds(F_SS_USB_DEVICE_CAPABILITY_DESCRIPTOR())),
     s1("usb_fld_ss_endpoint_companion_descriptor", flds(F_SS_ENDPOINT_COMPANION_DESCRIPTOR())),
     s1("usb_fld_usb_2_0_extension_descriptor", flds(F_USB_2_0_EXTENSION_DESCRIPTOR())),
     s1("usb_fld_container_id_descriptor", flds(F_CONTAINER_ID_DESCRIPTOR())),
     s1("usb_fld_platform_descriptor", flds(F_PLATFORM_DESCRIPTOR())),
     s1("usb_fld_init_option", flds(F_INIT_OPTION())),
     s1("usb_fld_init_option_value", flds(F_INIT_OPTION_VALUE())),
     s1("usb_fld_pollfd", flds(F_POLLFD())),
     s1("usb_fld_version", flds(F_VERSION())),
     s1("usb_fld_timeval", flds(F_TIMEVAL())),
     u1("usb_fld_transfer_status_ix", Fld.find("status", F_TRANSFER())),
     u1("usb_fld_transfer_length_ix", Fld.find("length", F_TRANSFER())),
     u1("usb_fld_transfer_buffer_ix", Fld.find("buffer", F_TRANSFER())),
     u1("usb_fld_transfer_endpoint_ix", Fld.find("endpoint", F_TRANSFER())),
     u1("usb_fld_transfer_type_ix", Fld.find("type", F_TRANSFER())),
     u1("usb_fld_transfer_timeout_ix", Fld.find("timeout", F_TRANSFER())),
     u1("usb_fld_transfer_actual_length_ix", Fld.find("actual_length", F_TRANSFER())),
     u1("usb_fld_transfer_nosuch_ix", Fld.find("nosuchfield", F_TRANSFER())),
     u1("usb_fld_device_descriptor_idVendor_ix", Fld.find("idVendor", F_DEVICE_DESCRIPTOR())),
     u1("usb_fld_device_descriptor_idProduct_ix", Fld.find("idProduct", F_DEVICE_DESCRIPTOR())),
     u1("usb_fld_device_descriptor_iProduct_ix", Fld.find("iProduct", F_DEVICE_DESCRIPTOR())),
     u1("usb_fld_device_descriptor_iManufacturer_ix", Fld.find("iManufacturer", F_DEVICE_DESCRIPTOR())),
     s1("usb_fld_transfer_at5", Fld.at(5, F_TRANSFER())),
     s1("usb_fld_transfer_at11", Fld.at(11, F_TRANSFER())),
     s1("usb_fld_transfer_at99", Fld.at(99, F_TRANSFER())),
     u1("usb_siz_transfer", SIZ_TRANSFER()),
     u1("usb_siz_device_descriptor", SIZ_DEVICE_DESCRIPTOR()),
     u1("usb_siz_endpoint_descriptor", SIZ_ENDPOINT_DESCRIPTOR()),
     u1("usb_siz_interface_descriptor", SIZ_INTERFACE_DESCRIPTOR()),
     u1("usb_siz_config_descriptor", SIZ_CONFIG_DESCRIPTOR()),
     u1("usb_siz_interface", SIZ_INTERFACE()),
     u1("usb_siz_interface_association_descriptor", SIZ_INTERFACE_ASSOCIATION_DESCRIPTOR()),
     u1("usb_siz_interface_association_descriptor_array", SIZ_INTERFACE_ASSOCIATION_DESCRIPTOR_ARRAY()),
     u1("usb_siz_control_setup", SIZ_CONTROL_SETUP()),
     u1("usb_siz_iso_packet_descriptor", SIZ_ISO_PACKET_DESCRIPTOR()),
     u1("usb_siz_bos_descriptor", SIZ_BOS_DESCRIPTOR()),
     u1("usb_siz_bos_dev_capability_descriptor", SIZ_BOS_DEV_CAPABILITY_DESCRIPTOR()),
     u1("usb_siz_ss_usb_device_capability_descriptor", SIZ_SS_USB_DEVICE_CAPABILITY_DESCRIPTOR()),
     u1("usb_siz_ss_endpoint_companion_descriptor", SIZ_SS_ENDPOINT_COMPANION_DESCRIPTOR()),
     u1("usb_siz_usb_2_0_extension_descriptor", SIZ_USB_2_0_EXTENSION_DESCRIPTOR()),
     u1("usb_siz_container_id_descriptor", SIZ_CONTAINER_ID_DESCRIPTOR()),
     u1("usb_siz_platform_descriptor", SIZ_PLATFORM_DESCRIPTOR()),
     u1("usb_siz_init_option", SIZ_INIT_OPTION()),
     u1("usb_siz_init_option_value", SIZ_INIT_OPTION_VALUE()),
     u1("usb_siz_pollfd", SIZ_POLLFD()),
     u1("usb_siz_version", SIZ_VERSION()),
     u1("usb_siz_timeval", SIZ_TIMEVAL())]))

def t_wire() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_wire_0", usb_wire(0)),
    u1("usb_wire_511", usb_wire(511)),
    u1("usb_wire_512", usb_wire(512)),
    u1("usb_wire_513", usb_wire(513)),
    u1("usb_wire_slot_m1", usb_wire(16383)),
    u1("usb_wire_slot", usb_wire(16384)),
    u1("usb_wire_slot_p1", usb_wire(16385)),
    u1("usb_wire_2slot_m1", usb_wire(32767)),
    u1("usb_wire_2slot", usb_wire(32768)),
    u1("usb_wire_chunk", usb_wire(CHUNK())),
    u1("usb_wire_2chunk", usb_wire(U32.mul(2, CHUNK())))
  ]))

def t_split() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_split_empty", "_full"]), Split.full(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_tail"]), Split.tail(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_ranged"]), Split.ranged(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_nranges"]), Split.nranges(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_full"]), Split.full(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_tail"]), Split.tail(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_ranged"]), Split.ranged(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_nranges"]), Split.nranges(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_full1", "_full"]), Split.full(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_tail"]), Split.tail(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_ranged"]), Split.ranged(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_nranges"]), Split.nranges(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_full"]), Split.full(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_tail"]), Split.tail(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_ranged"]), Split.ranged(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_nranges"]), Split.nranges(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_full"]), Split.full(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_tail"]), Split.tail(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_ranged"]), Split.ranged(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_nranges"]), Split.nranges(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_win_1", "_full"]), Split.full(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_tail"]), Split.tail(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_ranged"]), Split.ranged(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_nranges"]), Split.nranges(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_2chunk", "_full"]), Split.full(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_copyin_2chunk", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), usb_window(False{}))))
  ]))

def t_byteen() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_byteen_s1_o0", "_byteen"]), pcie_byte_en(1n, 0)),
    u1(String.concat(["usb_byteen_s1_o3", "_byteen"]), pcie_byte_en(1n, 3)),
    u1(String.concat(["usb_byteen_s2_o0", "_byteen"]), pcie_byte_en(2n, 0)),
    u1(String.concat(["usb_byteen_s2_o3", "_byteen"]), pcie_byte_en(2n, 3)),
    u1(String.concat(["usb_byteen_s3_o1", "_byteen"]), pcie_byte_en(3n, 1)),
    u1(String.concat(["usb_byteen_s4_o0", "_byteen"]), pcie_byte_en(4n, 0)),
    u1(String.concat(["usb_byteen_s4_o2", "_byteen"]), pcie_byte_en(4n, 2)),
    u1(String.concat(["usb_byteen_s4_o3", "_byteen"]), pcie_byte_en(4n, 3))
  ]))

def t_cfg() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_cfg_wr_b0", "_fmt"]), pcie_cfg_fmt(True{}, 0)),
    u1(String.concat(["usb_cfg_wr_b0", "_addr"]), pcie_cfg_addr(0, 0, 0, 0)),
    b1(String.concat(["usb_cfg_wr_b0", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 0)),
    u1(String.concat(["usb_cfg_rd_b0", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_b0", "_addr"]), pcie_cfg_addr(0, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b0", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 0)),
    u1(String.concat(["usb_cfg_wr_b1", "_fmt"]), pcie_cfg_fmt(True{}, 1)),
    u1(String.concat(["usb_cfg_wr_b1", "_addr"]), pcie_cfg_addr(1, 0, 0, 0)),
    b1(String.concat(["usb_cfg_wr_b1", "_ok"]), pcie_cfg_addr_ok(0, 1, 0, 0)),
    u1(String.concat(["usb_cfg_rd_b1", "_fmt"]), pcie_cfg_fmt(False{}, 1)),
    u1(String.concat(["usb_cfg_rd_b1", "_addr"]), pcie_cfg_addr(1, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b1", "_ok"]), pcie_cfg_addr_ok(0, 1, 0, 0)),
    u1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_fmt"]), pcie_cfg_fmt(True{}, 255)),
    u1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_addr"]), pcie_cfg_addr(255, 31, 7, 4095)),
    b1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_ok"]), pcie_cfg_addr_ok(4095, 255, 31, 7)),
    u1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_fmt"]), pcie_cfg_fmt(False{}, 255)),
    u1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_addr"]), pcie_cfg_addr(255, 31, 7, 4095)),
    b1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_ok"]), pcie_cfg_addr_ok(4095, 255, 31, 7)),
    u1(String.concat(["usb_cfg_rd_b256", "_fmt"]), pcie_cfg_fmt(False{}, 256)),
    u1(String.concat(["usb_cfg_rd_b256", "_addr"]), pcie_cfg_addr(256, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b256", "_ok"]), pcie_cfg_addr_ok(0, 256, 0, 0)),
    u1(String.concat(["usb_cfg_rd_d32", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_d32", "_addr"]), pcie_cfg_addr(0, 32, 0, 0)),
    b1(String.concat(["usb_cfg_rd_d32", "_ok"]), pcie_cfg_addr_ok(0, 0, 32, 0)),
    u1(String.concat(["usb_cfg_rd_f8", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_f8", "_addr"]), pcie_cfg_addr(0, 0, 8, 0)),
    b1(String.concat(["usb_cfg_rd_f8", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 8)),
    u1(String.concat(["usb_cfg_rd_ba4096", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_ba4096", "_addr"]), pcie_cfg_addr(0, 0, 0, 4096)),
    b1(String.concat(["usb_cfg_rd_ba4096", "_ok"]), pcie_cfg_addr_ok(4096, 0, 0, 0))
  ]))

def t_xdata() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_xdata_0", "_nchunks"]), xdata_nchunks(0)),
    u1(String.concat(["usb_xdata_0", "_chunk_i"]), xdata_chunk_at(0, 0)),
    u1(String.concat(["usb_xdata_1", "_nchunks"]), xdata_nchunks(1)),
    u1(String.concat(["usb_xdata_1", "_chunk_i"]), xdata_chunk_at(1, 0)),
    u1(String.concat(["usb_xdata_254", "_nchunks"]), xdata_nchunks(254)),
    u1(String.concat(["usb_xdata_254", "_chunk_i"]), xdata_chunk_at(254, 0)),
    u1(String.concat(["usb_xdata_255", "_nchunks"]), xdata_nchunks(255)),
    u1(String.concat(["usb_xdata_255", "_chunk_i"]), xdata_chunk_at(255, 0)),
    u1(String.concat(["usb_xdata_256", "_nchunks"]), xdata_nchunks(256)),
    u1(String.concat(["usb_xdata_256", "_chunk_i"]), xdata_chunk_at(256, 1)),
    u1(String.concat(["usb_xdata_510", "_nchunks"]), xdata_nchunks(510)),
    u1(String.concat(["usb_xdata_510", "_chunk_i"]), xdata_chunk_at(510, 1)),
    u1(String.concat(["usb_xdata_511", "_nchunks"]), xdata_nchunks(511)),
    u1(String.concat(["usb_xdata_511", "_chunk_i"]), xdata_chunk_at(511, 1)),
    u1(String.concat(["usb_xdata_512", "_nchunks"]), xdata_nchunks(512)),
    u1(String.concat(["usb_xdata_512", "_chunk_i"]), xdata_chunk_at(512, 2)),
    u1(String.concat(["usb_xdata_slot_i64", "_nchunks"]), xdata_nchunks(16384)),
    u1(String.concat(["usb_xdata_slot_i64", "_chunk_i"]), xdata_chunk_at(16384, 64))
  ]))

def t_scsi() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_scsi_0", "_pad"]), scsi_pad(0)),
    u1(String.concat(["usb_scsi_0", "_padded"]), scsi_padded(0)),
    u1(String.concat(["usb_scsi_0", "_wvalue"]), scsi_wvalue(0)),
    u1(String.concat(["usb_scsi_0", "_windex"]), scsi_windex(0, 0)),
    u1(String.concat(["usb_scsi_1", "_pad"]), scsi_pad(1)),
    u1(String.concat(["usb_scsi_1", "_padded"]), scsi_padded(1)),
    u1(String.concat(["usb_scsi_1", "_wvalue"]), scsi_wvalue(1)),
    u1(String.concat(["usb_scsi_1", "_windex"]), scsi_windex(1, 0)),
    u1(String.concat(["usb_scsi_511", "_pad"]), scsi_pad(511)),
    u1(String.concat(["usb_scsi_511", "_padded"]), scsi_padded(511)),
    u1(String.concat(["usb_scsi_511", "_wvalue"]), scsi_wvalue(511)),
    u1(String.concat(["usb_scsi_511", "_windex"]), scsi_windex(511, 0)),
    u1(String.concat(["usb_scsi_512", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_512", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_512", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_512", "_windex"]), scsi_windex(512, 0)),
    u1(String.concat(["usb_scsi_513", "_pad"]), scsi_pad(513)),
    u1(String.concat(["usb_scsi_513", "_padded"]), scsi_padded(513)),
    u1(String.concat(["usb_scsi_513", "_wvalue"]), scsi_wvalue(513)),
    u1(String.concat(["usb_scsi_513", "_windex"]), scsi_windex(513, 0)),
    u1(String.concat(["usb_scsi_slot_m1", "_pad"]), scsi_pad(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_padded"]), scsi_padded(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_wvalue"]), scsi_wvalue(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_windex"]), scsi_windex(16383, 0)),
    u1(String.concat(["usb_scsi_slot", "_pad"]), scsi_pad(16384)),
    u1(String.concat(["usb_scsi_slot", "_padded"]), scsi_padded(16384)),
    u1(String.concat(["usb_scsi_slot", "_wvalue"]), scsi_wvalue(16384)),
    u1(String.concat(["usb_scsi_slot", "_windex"]), scsi_windex(16384, 0)),
    u1(String.concat(["usb_scsi_slot_p1", "_pad"]), scsi_pad(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_padded"]), scsi_padded(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_wvalue"]), scsi_wvalue(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_windex"]), scsi_windex(16385, 0)),
    u1(String.concat(["usb_scsi_2slot", "_pad"]), scsi_pad(32768)),
    u1(String.concat(["usb_scsi_2slot", "_padded"]), scsi_padded(32768)),
    u1(String.concat(["usb_scsi_2slot", "_wvalue"]), scsi_wvalue(32768)),
    u1(String.concat(["usb_scsi_2slot", "_windex"]), scsi_windex(32768, 0)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_windex"]), scsi_windex(512, 255)),
    u1(String.concat(["usb_scsi_slotstart_100", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_windex"]), scsi_windex(512, 256))
  ]))

def t_copyout() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_co_0", "_first"]), copyout_first(0)),
    u1(String.concat(["usb_co_0", "_second"]), copyout_second(0)),
    u1(String.concat(["usb_co_0", "_wire"]), copyout_wire(0)),
    u1(String.concat(["usb_co_511", "_first"]), copyout_first(511)),
    u1(String.concat(["usb_co_511", "_second"]), copyout_second(511)),
    u1(String.concat(["usb_co_511", "_wire"]), copyout_wire(511)),
    u1(String.concat(["usb_co_512", "_first"]), copyout_first(512)),
    u1(String.concat(["usb_co_512", "_second"]), copyout_second(512)),
    u1(String.concat(["usb_co_512", "_wire"]), copyout_wire(512)),
    u1(String.concat(["usb_co_chunk_m1", "_first"]), copyout_first(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_m1", "_second"]), copyout_second(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_m1", "_wire"]), copyout_wire(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk", "_first"]), copyout_first(CHUNK())),
    u1(String.concat(["usb_co_chunk", "_second"]), copyout_second(CHUNK())),
    u1(String.concat(["usb_co_chunk", "_wire"]), copyout_wire(CHUNK())),
    u1(String.concat(["usb_co_chunk_p1", "_first"]), copyout_first(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_p1", "_second"]), copyout_second(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_p1", "_wire"]), copyout_wire(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_2chunk", "_first"]), copyout_first(U32.mul(2, CHUNK()))),
    u1(String.concat(["usb_co_2chunk", "_second"]), copyout_second(U32.mul(2, CHUNK()))),
    u1(String.concat(["usb_co_2chunk", "_wire"]), copyout_wire(U32.mul(2, CHUNK())))
  ]))

def t_chunk() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_chunk_h0_w512", "_end"]), chunk_end(0)),
    u1(String.concat(["usb_chunk_h0_w512", "_off"]), chunk_off(0, usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w512", "_sentinel_word"]), chunk_sentinel_word(0)),
    u1(String.concat(["usb_chunk_h0_w512", "_wvalue"]), chunk_wvalue(usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w512", "_windex"]), chunk_windex(0, usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_end"]), chunk_end(0)),
    u1(String.concat(["usb_chunk_h0_w2slot", "_off"]), chunk_off(0, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_sentinel_word"]), chunk_sentinel_word(0)),
    u1(String.concat(["usb_chunk_h0_w2slot", "_wvalue"]), chunk_wvalue(usb_wire(32768))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_windex"]), chunk_windex(0, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w512", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w512", "_off"]), chunk_off(1, usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w512", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w512", "_wvalue"]), chunk_wvalue(usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w512", "_windex"]), chunk_windex(1, usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w2slot", "_off"]), chunk_off(1, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w2slot", "_wvalue"]), chunk_wvalue(usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_windex"]), chunk_windex(1, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_off"]), chunk_off(1, usb_wire(U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_wvalue"]), chunk_wvalue(usb_wire(U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_windex"]), chunk_windex(1, usb_wire(U32.mul(2, CHUNK()))))
  ]))

def t_table() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_tbl_k0r0", "_addr"]), table_addr_word(0, 0)),
    u1(String.concat(["usb_tbl_k0r0", "_size"]), table_size_word(0, 0)),
    u1(String.concat(["usb_tbl_k0r1", "_addr"]), table_addr_word(0, 1)),
    u1(String.concat(["usb_tbl_k0r1", "_size"]), table_size_word(0, 1)),
    u1(String.concat(["usb_tbl_k1r0", "_addr"]), table_addr_word(1, 0)),
    u1(String.concat(["usb_tbl_k1r0", "_size"]), table_size_word(1, 0)),
    u1(String.concat(["usb_tbl_k3r2", "_addr"]), table_addr_word(3, 2)),
    u1(String.concat(["usb_tbl_k3r2", "_size"]), table_size_word(3, 2))
  ]))

def t_mmio() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_mmio_idx0_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_slice_sz"]), off_of_slice_sz(0, 1, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_int_off"]), off_of_index(1, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_slice_sz"]), off_of_slice_sz(0, 1, 4)),
    u1(String.concat(["usb_mmio_idx7_el1", "_int_off"]), off_of_index(7, 1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_int_sz"]), off_of_index_sz(1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_slice_at"]), off_of_slice_at(0, 1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_slice_sz"]), off_of_slice_sz(0, 1, 1)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_slice_sz"]), off_of_slice_sz(0, 4, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_slice_at"]), off_of_slice_at(2, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_slice_sz"]), off_of_slice_sz(2, 9, 4))
  ]))

def t_window() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_half", HALF()),
    u1("usb_chunk", CHUNK()),
    u1("usb_slot", SLOT()),
    u1("usb_sentinel_block", SENTINEL_BLOCK()),
    u1("usb_max_stream", USB_MAX_STREAM()),
    u1("usb_host_size", USB_HOST_SIZE()),
    u1("usb_asm24_size", ASM24_SIZE()),
    u1("usb_win_fence_lo", WIN_FENCE_LO()),
    u1("usb_win_fence_hi", WIN_FENCE_HI()),
    u1("usb_win_cq_lo", WIN_CQ_LO()),
    u1("usb_win_cq_hi", WIN_CQ_HI()),
    u1("usb_win_sram_lo", WIN_SRAM_LO()),
    u1("usb_win_sram_hi", WIN_SRAM_HI()),
    b1("usb_sram_win_fits_asm24", sram_win_fits()),
    u1("usb_link_bytes", LINK_BYTES()),
    u1("usb_link_words", LINK_WORDS()),
    u1("usb_link_packed", LINK_PACKED()),
    u1("usb_stage_lo", STAGE_LO()),
    u1("usb_stage_hi", STAGE_HI()),
    u1("usb_zeros_lo", ZEROS_LO()),
    u1("usb_vram_words", VRAM_WORDS()),
    u1("usb_vram_bytes", VRAM_BYTES()),
    u1("usb_go_word", GO_WORD()),
    u1("usb_scratch_word", SCRATCH_WORD()),
    u1("usb_bulk_buf", BULK_BUF()),
    u1("usb_ctrl_buf", CTRL_BUF()),
    u1("usb_table_row_bytes", TABLE_ROW_BYTES()),
    u1("usb_table_size_off", TABLE_SIZE_OFF()),
    u1("usb_req_power", REQ_POWER()),
    u1("usb_req_f0", REQ_F0()),
    u1("usb_req_f2", REQ_F2()),
    u1("usb_req_e4", REQ_E4()),
    u1("usb_req_e5", REQ_E5()),
    u1("usb_mode_mask", MODE_MASK()),
    u1("usb_cfg_fmt_rd", CFG_FMT_RD()),
    u1("usb_cfg_fmt_wr", CFG_FMT_WR()),
    u1("usb_cfg_bus_shift", CFG_BUS_SHIFT()),
    u1("usb_cfg_dev_shift", CFG_DEV_SHIFT()),
    u1("usb_cfg_fn_shift", CFG_FN_SHIFT()),
    u1("usb_cfg_ba_mask", CFG_BA_MASK()),
    u1("usb_xdata_chunk", XDATA_CHUNK()),
    u1("usb_sram_align", SRAM_ALIGN()),
    u1("usb_sram_slot", SRAM_SLOT()),
    u1("usb_drain_mod", DRAIN_MOD()),
    u1("usb_stream_fmt_wr", STREAM_FMT_WR()),
    u1("usb_stream_fmt_rd", STREAM_FMT_RD()),
    u1("usb_stream_byte_en", STREAM_BYTE_EN()),
    u1("usb_copyin_win", usb_window(True{})),
    u1("usb_copyout_win", usb_window(False{})),
    u1("usb_remote_n", REMOTE_N())
  ]))

def t_sentinel() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_sentinel_magic", SENTINEL_MAGIC()),
    u1("usb_sentinel_mask", SENTINEL_MASK()),
    u1("usb_sentinel_0", usb_sentinel(0)),
    u1("usb_sentinel_1", usb_sentinel(1)),
    u1("usb_sentinel_max24", usb_sentinel(16777215)),
    u1("usb_sentinel_max24_p1", usb_sentinel(16777216)),
    u1("usb_sentinel_allones", usb_sentinel(4294967295)),
    b1("usb_sentinel_collide_24", sentinels_collide(0, 16777216)),
    b1("usb_sentinel_collide_23", sentinels_collide(0, 8388608)),
    b1("usb_sentinel_collide_adjacent", sentinels_collide(0, 1))
  ]))

def t_pcie_read() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_pcie_mask_1", pcie_read_mask(1n)),
    u1("usb_pcie_mask_2", pcie_read_mask(2n)),
    u1("usb_pcie_mask_3", pcie_read_mask(3n)),
    u1("usb_pcie_mask_4", pcie_read_mask(4n)),
    u1("usb_pcie_extract_allff_s4_o0", pcie_extract(4294967295, 4n, 0)),
    u1("usb_pcie_extract_allff_s1_o0", pcie_extract(4294967295, 1n, 0)),
    u1("usb_pcie_extract_deadbeef_s1_o0", pcie_extract(3735928559, 1n, 0)),
    u1("usb_pcie_extract_deadbeef_s2_o1", pcie_extract(3735928559, 2n, 1)),
    u1("usb_pcie_extract_deadbeef_s2_o2", pcie_extract(3735928559, 2n, 2)),
    u1("usb_pcie_extract_deadbeef_s4_o3", pcie_extract(3735928559, 4n, 3)),
    u1("usb_pcie_offset_0", pcie_offset(0)),
    u1("usb_pcie_offset_3", pcie_offset(3)),
    u1("usb_pcie_offset_4", pcie_offset(4)),
    u1("usb_pcie_offset_allff", pcie_offset(4294967295))
  ]))

def t_fastpath() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_fast_p1_mask", FAST_P1_MASK()),
    u1("usb_fast_p1_val", FAST_P1_VAL()),
    u1("usb_fast_p2_mask", FAST_P2_MASK()),
    u1("usb_fast_p2_val", FAST_P2_VAL()),
    b1("usb_nocompletion_64", pcie_no_completion(64)),
    b1("usb_nocompletion_48", pcie_no_completion(48)),
    b1("usb_nocompletion_68", pcie_no_completion(68)),
    b1("usb_nocompletion_4", pcie_no_completion(4)),
    b1("usb_nocompletion_76", pcie_no_completion(76)),
    b1("usb_nocompletion_0", pcie_no_completion(0)),
    b1("usb_nocompletion_32", pcie_no_completion(32)),
    b1("usb_nocompletion_96", pcie_no_completion(96))
  ]))

def t_stream() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_pcie_mem_nchunks_max", pcie_mem_nchunks(USB_MAX_STREAM())),
    u1("usb_pcie_mem_nchunks_max_p1", pcie_mem_nchunks(U32.add(USB_MAX_STREAM(), 1))),
    u1("usb_pcie_mem_nchunks_2max", pcie_mem_nchunks(U32.mul(2, USB_MAX_STREAM()))),
    u1("usb_pcie_mem_nchunks_0", pcie_mem_nchunks(0)),
    u1("usb_pcie_mem_dwords_0", pcie_mem_dwords(0)),
    u1("usb_pcie_mem_dwords_4", pcie_mem_dwords(4)),
    u1("usb_pcie_mem_dwords_5", pcie_mem_dwords(5)),
    b1("usb_aligned4_0", aligned4(0)),
    b1("usb_aligned4_4", aligned4(4)),
    b1("usb_aligned4_5", aligned4(5)),
    b1("usb_aligned4_1", aligned4(1))
  ]))

def t_drained() -> IO(Unit):
  IO.print(lines_of([
    b1("usb_drain_need_fence_eq", drained_step(7, 7)),
    b1("usb_drain_need_fence_ahead1", drained_step(7, 6)),
    b1("usb_drain_need_fence_ahead2", drained_step(7, 5)),
    b1("usb_drain_need_fence_ahead3", drained_step(7, 4)),
    b1("usb_drain_need_fence_1behind", drained_step(7, 8)),
    b1("usb_drain_need_fence_2behind", drained_step(7, 9)),
    b1("usb_drain_wrap_need1_fence3", drained_step(1, 3)),
    b1("usb_drain_wrap_need0_fence0", drained_step(0, 0)),
    b1("usb_drain_wrap_need0_fence255", drained_step(0, 255)),
    b1("usb_drain_wrap_need0_fence254", drained_step(0, 254)),
    b1("usb_drain_wrap_need255_fence0", drained_step(255, 0)),
    b1("usb_drain_wrap_need2_fence0", drained_step(2, 0)),
    # THE MASK IS OBSERVABLE WITHOUT WRAPPING: `need - fence == 256` is 0 mod
    # 256, so `& 0xff` says "not drained" while the raw difference says "drained
    # by 256". This is the fixture that makes M26 more than a one-row mutation.
    b1("usb_drain_need300_fence44", drained_step(300, 44)),
    b1("usb_drain_need300_fence43", drained_step(300, 43))]))

def t_remote() -> IO(Unit):
  IO.print(lines_of([
    s1("usb_remote_prefixes", remote_prefixes()),
    b1("usb_remote_usb_host", is_remote_prefix("usb_host", "usb_host")),
    b1("usb_remote_usb_xfer0", is_remote_prefix("usb_xfer0", "usb_xfer")),
    b1("usb_remote_usb_xfer1", is_remote_prefix("usb_xfer1", "usb_xfer")),
    b1("usb_remote_put_value", is_remote_prefix("put_value", "put_value")),
    b1("usb_remote_cmdbuf_copy", is_remote_prefix("cmdbuf_copy", "cmdbuf_copy")),
    b1("usb_remote_kernargs_usb_host", is_remote_prefix("kernargs", "usb_host")),
    b1("usb_remote_kernargs_usb_xfer", is_remote_prefix("kernargs", "usb_xfer")),
    b1("usb_remote_kernargs_put_value", is_remote_prefix("kernargs", "put_value")),
    b1("usb_remote_kernargs_cmdbuf_copy", is_remote_prefix("kernargs", "cmdbuf_copy")),
    b1("usb_remote_usb_table", is_remote_prefix("usb_table", "usb_host")),
    b1("usb_remote_arg_cache", is_remote_prefix("usb_arg_cache", "usb_xfer")),
    b1("usb_remote_usb_hostx", is_remote_prefix("usb_hostx", "usb_host")),
    b1("usb_remote_xusb_host", is_remote_prefix("xusb_host", "usb_host"))
  ]))

# ===========================================================================
# THE TRACE. Every libusb / libc / ctypes binding in `usb.py` is ONE `Call{k, a,
# b, c}` entry and nothing else, so no foreign effect is declared and
# `--check-only` stays green in both lanes. `vend` maps each `k` back to the C
# symbol, which is what keeps the seam greppable: `grep -n libusb_ this_file`
# finds the symbol as a LITERAL, not inside an opaque body.
#
# `a`, `b`, `c` are the call's arguments that are ARITHMETIC (an endpoint, a
# wValue, a byte count, a descriptor's ids). A call with no arithmetic argument --
# `libusb_init` and `libusb_free_device_list` -- records zeros, and a call whose
# arguments are all pointers (`libusb_open(dev, handle)`) records zeros too. That
# is not a gap in the port, it is the pointer being the SEAM's.
# ===========================================================================

type Call is Data:
  Call{k: U32, a: U32, b: U32, c: U32}

def Call.k(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: k

def Call.a(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: a

def Call.b(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: b

def Call.c(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: c

# THE C SYMBOLS, one per call kind. This table is the FFI seam's inventory and it
# is the whole of what a later `@extern` has to replace.
def K_INIT() -> U32: 0
def K_SET_OPTION() -> U32: 1
def K_GET_DEVLIST() -> U32: 2
def K_GET_DESC() -> U32: 3
def K_REF_DEVICE() -> U32: 4
def K_BUS_NUMBER() -> U32: 5
def K_DEV_ADDRESS() -> U32: 6
def K_FREE_DEVLIST() -> U32: 7
def K_OPEN() -> U32: 8
def K_GET_DEVICE() -> U32: 9
def K_STR_ASCII() -> U32: 10
def K_KDRV_ACTIVE() -> U32: 11
def K_DETACH_KDRV() -> U32: 12
def K_RESET_DEVICE() -> U32: 13
def K_SET_CONFIG() -> U32: 14
def K_CLAIM_IFACE() -> U32: 15
def K_SET_ALT() -> U32: 16
def K_CTRL_XFER() -> U32: 17
def K_BULK_XFER() -> U32: 18
def K_ALLOC_XFER() -> U32: 19
def K_EVENTS() -> U32: 20
def K_SUBMIT_XFER() -> U32: 21
def K_MEMCPY() -> U32: 22
def K_STRERROR() -> U32: 23

# THE SEAM'S INVENTORY, AS A LIST. It is a list and not a `match` on the kind
# because Bend's `match` over a `Nat` needs a `case 1n+m:` arm to be total, and a
# 24-arm ladder of symbol names is 24 lines of noise where a list is one.
def SYMS() -> List<&2, String>:
  ["libusb_init", "libusb_set_option", "libusb_get_device_list",
   "libusb_get_device_descriptor", "libusb_ref_device", "libusb_get_bus_number",
   "libusb_get_device_address", "libusb_free_device_list", "libusb_open",
   "libusb_get_device", "libusb_get_string_descriptor_ascii",
   "libusb_kernel_driver_active", "libusb_detach_kernel_driver",
   "libusb_reset_device", "libusb_set_configuration", "libusb_claim_interface",
   "libusb_set_interface_alt_setting", "libusb_control_transfer",
   "libusb_bulk_transfer", "libusb_alloc_transfer", "libusb_handle_events_timeout",
   "libusb_submit_transfer", "memcpy", "libusb_strerror"]

# A MATCH MAY NOT SCRUTINIZE A CALL, so the kind gets its own def -- the same
# shape `dev_might_open.at` uses in ops_disk.bend, where the predicates arrive as
# parameters instead.
# `n` IS THE INDEX and the head is the ZERO-th entry. The version that matched
# `1n+m` and returned the head when `m == 0n` was off by one, and every order row
# in the file read as the symbol BELOW the truth -- which is exactly the error a
# count-only gate cannot see and a whole-value row can.
# THE HEAD-AT-ZERO ARM IS A SEPARATE DEF, so the off-by-one mutation is a one-word
# edit that still COMPILES: `sym_at_head(h0, t2)` answering `t2` instead of `h0`
# names the symbol AFTER the one it meant, and every count in the file stays right.
def head_name(xs: List<&2, String>, dflt: String) -> String:
  match xs:
    case Nil{}: dflt
    case h <> t: h

def sym_at_head(+h0: String, +t2: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, t2),
            head_name(t2, ""), h0)

def sym_at.go(n: Nat, ss: List<&2, String>) -> String:
  match n:
    case 0n:
      match ss:
        case Nil{}: "libusb_unknown"
        case h0 <> t2: sym_at_head(h0, t2)
    case 1n+m:
      match ss:
        case Nil{}: "libusb_unknown"
        case h0 <> t2: sym_at.go(m, t2)

def sym_at(+n: Nat, ss: List<&2, String>) -> String: sym_at.go(n, ss)

def call_sym(+k: U32) -> String: sym_at(U32.to_nat(k), SYMS())

def Call.sym(x: Call) -> String: call_sym(Call.k(x))

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, bad_at: U32, seen: U32, refused: Bool}

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: refused

def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: Tr{calls, next, n, seen, refused}

def Tr.reset(t: Tr) -> Tr: Tr{Nil{}, 0, Tr.next(t), 0, False{}}

# THE RAISE IS IN THE TRACE, so a refusal is a TRUNCATION and no step needs a
# guard of its own. The failing call IS still recorded -- it sets `refused` in the
# same breath, so on entry its own `refused` is still False. Every step goes
# through `Tr.emit.go`, so two steps cannot disagree about the guard.
#
# `Tr.emit` AND `Tr.raise` ARE THE SAME FUNCTION with a different GUARD, and which
# one a step uses IS THE PORTED FACT: `usb.py`'s `checked` (:13-18) raises when
# the return code is negative, so every call wrapped in `checked` is a `Tr.raise`
# site and every RAW call is a `Tr.emit`. `usb_open_refuse_5_config` is the row
# that measured what happens when this is faked: with SET_CONFIG emitted by
# `Tr.emit`, `bad_at = 5` never fires and the "refusal" row prints the FULL
# seven-call trace -- which is a row that looks like a gate and is not one.
def Tr.emit.go(+refuse: Bool, +refused: Bool, +k: U32, a: U32, b: U32, c: U32,
               +calls: List<&2, Call>, +next: U32, +bad_at: U32,
               +seen: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, a, b, c}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), bad_at,
     Bool.pick(U32, refused, seen, U32.add(seen, 1)),
     Bool.or(refused, refuse)}

def Tr.emit(+k: U32, a: U32, b: U32, c: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}:
      Tr.emit.go(False{}, refused, k, a, b, c, calls, next, bad_at, seen)

# the `bad_at`-th emit raises. :16's `checked` is this, and so is every `assert`.
def Tr.raise(+k: U32, a: U32, b: U32, c: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, +bad_at, +seen, +refused}:
      Tr.emit.go(U32.is_eq(U32.add(seen, 1), bad_at), refused, k, a, b, c,
                 calls, next, bad_at, seen)

# THE ORDER, as ONE string of symbol names. A count is not a gate and a set is
# not a gate: this is the call SEQUENCE, and `usb_open_order` / `usb_enum_order`
# are whole-value rows, so a swapped pair of steps moves them.
def Tr.sym.go(n: Nat, cs: List<&2, Call>, acc: String, +sep: String) -> String:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case c <> t: Tr.sym.go(m, t, String.append(acc, String.append(Call.sym(c), sep)), sep)

def Tr.sym(+t: Tr) -> String: Tr.sym.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), "", ",")

def Tr.n(+t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case c <> t: Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(Call.k(c), k))))

def Tr.count(+k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# `has` is a real SUBSEQUENCE test -- the fuel is the TRACE length, not the
# pattern length, which is the bug ops_webgpu.bend's gate found in ITSELF.
def Tr.has.step(+c: Call, +w: Call) -> Bool:
  Bool.and(Bool.and(U32.is_eq(Call.k(c), Call.k(w)), U32.is_eq(Call.a(c), Call.a(w))),
           Bool.and(U32.is_eq(Call.b(c), Call.b(w)), U32.is_eq(Call.c(c), Call.c(w))))

def Tr.has.step.at(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+w}: Nat.add(at, U32.to_nat(Bool.to_u32(Tr.has.step(c, w))))

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case c <> t: Tr.has.go(m, patlen, t, pat,
                               Tr.has.step.at(List.get(&2, Call, pat, at), c, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)


# ===========================================================================
# THE ENUMERATION. `USB3.list_devices` (:30-37) is ONE loop and it is the wall
# ops_amd.bend recorded as `TODO(p3) runtime/ops_amd.py:812  USB3.list_devices`.
#
# THE SELECTION IS A PURE PREDICATE and the trace is the walk: the port computes
# `(idVendor, idProduct) == (vendor, dev)` from the descriptor fields it HAS
# already parsed -- by NAME, through `Fld.find` -- and only appends
# REF_DEVICE + BUS_NUMBER + DEV_ADDRESS on a match. `usb_list_match` is that
# predicate and `usb_enum_walk` is the walk, so the negative case (a descriptor
# whose ids do not pair) is one row from its positive and costs nothing extra.
# ===========================================================================

# :34 `(desc.idVendor, desc.idProduct) == (vendor, dev)`. The two descriptor
# field ORDINALS come from `F_TRANSFER`'s sibling table, by name.
def list_match(+idVendor: U32, +idProduct: U32, +vendor: U32, +dev: U32) -> Bool:
  Bool.and(U32.is_eq(idVendor, vendor), U32.is_eq(idProduct, dev))

# :35 the label, `f"usb:{bus}-{addr}"`. A STRING TABLE, so it is diffed as a
# string: `String.concat` drops a literal silently and a boolean about a string
# cannot see that happen.
def list_label(+bus: U32, +addr: U32) -> String:
  String.concat(["usb:", U32.show(bus), "-", U32.show(addr)])

# the walk over the device list. `match0` is the FIRST device's verdict and the
# trace records one GET_DESC per device either way -- the descriptor is read
# BEFORE the comparison, which is what makes the negative case a real one.
# THE DESCRIPTOR IS READ FIRST AND THE SELECTION IS SECOND, and the emit chain
# records the OUTERMOST call LAST, so GET_DEVICE_DESCRIPTOR is the INNERMOST emit.
# The version that wrapped the `Bool.pick` in a GET_DESC emit put the descriptor
# read AFTER the ref/bus/address triple, which is the reverse of :33-35.
# A MISS STILL READS THE DESCRIPTOR. :33 reads it and :34 compares it, so the
# read is unconditional and only the ref/bus/address triple is conditional -- a
# miss is FOUR calls shorter than a hit and not three.
def usb_enum.device(+hit: Bool, +bus: U32, +addr: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, hit,
    Tr.raise(K_DEV_ADDRESS(), addr, 0, 0,
      Tr.raise(K_BUS_NUMBER(), bus, 0, 0,
        Tr.emit(K_REF_DEVICE(), 0, 0, 0, Tr.raise(K_GET_DESC(), 0, 0, 0, t)))),
    Tr.raise(K_GET_DESC(), 0, 0, 0, t))

# THE FUEL IS THE DEVICE COUNT and there is no device LIST, because
# `libusb_get_device_list` hands back a POINTER to a C array: the seam's, and the
# port's `n` is the count `range(...)` walked. The earlier version destructured an
# always-empty list and so emitted ONE device whatever `n` said.
def usb_enum.walk(n: Nat, +hit: Bool, +bus: U32, +addr: U32, +t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m: usb_enum.walk(m, hit, bus, addr, usb_enum.device(hit, bus, addr, t))

# :32 GET_DEVICE_LIST, then the walk, then :36 `libusb_free_device_list(devs, 1)`
# with `unref_devices=1`. THE FREE IS LAST and it is not conditional: a
# `libusb_ref_device`d device survives it, and a descriptor that was only read
# does not need to.
def usb_enum(n: Nat, +hit: Bool, +bus: U32, +addr: U32, t: Tr) -> Tr:
  Tr.emit(K_FREE_DEVLIST(), 1, 0, 0,
    usb_enum.walk(n, hit, bus, addr, Tr.raise(K_GET_DEVLIST(), 0, 0, 0, t)))

# ===========================================================================
# THE OPEN. `USB3.__init__` (:39-62). `ops_disk.bend` records `_might_open` as a
# WALK OF STATE THAT ENDS IN A CLAIM; this is the same shape, and it is the one
# ops_amd.bend could not reach.
#
# THE PRODUCT ASSERT IS A REFUSAL (:52) and so is the kernel-driver branch's
# absence: the three DETACH/RESET calls appear ONLY when `libusb_kernel_driver_
# active` answered true, and their ABSENCE is what the two open traces differ by.
# `Tr.raise` IS the emit that raises, so it does NOT wrap another emit of the same
# call. The version that did recorded `libusb_get_string_descriptor_ascii` twice,
# and the product-assert row then read a nine-call trace for an eight-call open.
# :49 `libusb_get_device` is RAW and the three calls around it are `checked`, so
# the two kinds interleave: GET_DEVICE is `Tr.emit` and the rest are `Tr.raise`.
# The product assert itself (:52) is NOT a raise site -- it is an `assert` that
# fires after a successful read -- so it is modelled by refusing AT the read and
# letting `usb_open` take the `have_product` branch.
def usb_open.after(have_product: Bool, +t: Tr) -> Tr:
  Tr.raise(K_STR_ASCII(), USB3_STRING_BUF(), 0, 0,
    Tr.raise(K_GET_DESC(), 0, 0, 0, Tr.emit(K_GET_DEVICE(), 0, 0, 0,
      Tr.raise(K_OPEN(), 0, 0, 0, t))))

def usb_open.detach(kdrv_active: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, kdrv_active,
    Tr.raise(K_RESET_DEVICE(), 0, 0, 0,
      Tr.raise(K_DETACH_KDRV(), USB3_IFACE(), 0, 0,
        Tr.raise(K_KDRV_ACTIVE(), USB3_IFACE(), 0, 0, t))), t)

def usb_open(have_product: Bool, kdrv_active: Bool, +t: Tr) -> Tr:
  Tr.raise(K_SET_ALT(), USB3_IFACE(), USB3_ALT(), 0,
    Tr.raise(K_CLAIM_IFACE(), USB3_IFACE(), 0, 0,
      Tr.raise(K_SET_CONFIG(), USB3_CONFIG(), 0, 0,
        usb_open.detach(kdrv_active, usb_open.after(have_product, t)))))

# :20-27 `USB3.ctx()`: `libusb_init`, then `libusb_set_option(ctx,
# LIBUSB_OPTION_LOG_LEVEL, 4)` ONLY when `DEBUG >= 6`. The option is NOT
# conditional on anything else and there is no third call.
def usb_ctx(debug6: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, debug6,
    Tr.raise(K_SET_OPTION(), enum_val("LIBUSB_OPTION_LOG_LEVEL", E_OPTION()),
             USB3_LOG_LEVEL_DEBUG(), 0, Tr.raise(K_INIT(), 0, 0, 0, t)),
    Tr.raise(K_INIT(), 0, 0, 0, t))
# ===========================================================================
# THE STRING TABLE. `usb.py` has nine user-visible strings and every one of them
# is either a LITERAL or an f-string whose literal parts are load-bearing. They
# are diffed AS STRINGS, not as a boolean about a string, because `String.concat`
# drops a literal silently: a row that said "the message is not empty" would stay
# green with the prefix removed.
#
# THREE of them cannot be rendered here at all and are named as the seam:
# `{address:#x}` needs hex, `{ltssm:02X}` needs zero-padded hex, and
# `libusb_strerror` is a C call. Bend 2.0.34 has `U32.show` and no radix.
#     TODO(p3) tinygrad/runtime/support/usb.py:16   `libusb_strerror(rc)`.
#     TODO(p3) tinygrad/runtime/support/usb.py:102  `0x{ltssm:02X}`.
#     TODO(p3) tinygrad/runtime/support/usb.py:129  `address={address:#x}`.
#     TODO(p3) tinygrad/runtime/support/usb.py:133  `f'Reserved (0b{cpl_status:03b})'`.
# ===========================================================================

def MSG_BULK_OUT() -> String: "bulk OUT 0x02 failed"
def MSG_BULK_IN() -> String: "bulk IN 0x81 failed"
def MSG_SHORT_WRITE() -> String: "bulk OUT short write: "
def MSG_BYTES() -> String: " bytes"
def MSG_TLP_RETRIES() -> String: "TLP error after retries: ret_status="
def MSG_TLP_CPL() -> String: "TLP completion status: "
def MSG_CPL_UNSUP() -> String: "Unsupported Request: "
def MSG_CPL_ABORT() -> String: "Completer Abort"
def MSG_CPL_RETRY() -> String: "Config Retry"
def MSG_CPL_RESERVED() -> String: "Reserved (0b"
def MSG_LTSSM() -> String: "PCIe link not up (LTSSM=0x"
def MSG_LTSSM_TAIL() -> String: "), custom firmware not ready"
def MSG_INVALID_SIZE() -> String: "Invalid size "
def MSG_ALIGNED_SIZE_W() -> String: "pcie_mem_write requires 4-byte aligned size, got "
def MSG_ALIGNED_SIZE_R() -> String: "pcie_mem_read requires 4-byte aligned size, got "
def MSG_ALIGNED_ACCESS_R() -> String: "pcie_mem_read requires 4-byte aligned access, got off="
def MSG_ALIGNED_ACCESS_W() -> String: "pcie_mem_write requires 4-byte aligned access, got off="
def MSG_SZ() -> String: ", sz="
def MSG_CHECKED() -> String: ": "
def PRODUCT_OK() -> String: "custom"
def PRODUCT_OK2() -> String: "AS2462"

# :52 `assert self.product.startswith("custom") or self.product.startswith("AS2462")`
def product_ok(+product: String) -> Bool:
  Bool.or(String.starts_with(product, PRODUCT_OK()), String.starts_with(product, PRODUCT_OK2()))


# EIGHT STATUSES, because the dict has THREE keys and the default arm is the
# claim: 0b000 and 0b011 and 0b101 are all "Reserved", and 0 and 7 are not
# errors -- `status_map.get` answers them with the fallback.


# :132 the status map. `status_map.get(cpl_status, f'Reserved (0b{cpl_status:03b})')`
# -- so 0b001, 0b010 and 0b100 have names and EVERYTHING else is Reserved, and the
# map is a DICT with three keys, so 0 and 5 are Reserved and not an error.
def CPL_UNSUP() -> U32: 1     # 0b001
def CPL_RETRY() -> U32: 2     # 0b010
def CPL_ABORT() -> U32: 4     # 0b100

# `case _:` does not close a `Nat` match in Bend 2.0.34 -- `match cpl_status`
# over a `Nat` needs `case 1n+m:` to be total, so the three keys are an OR of
# EQUALITIES and the fallback is the default argument of the OR. That is also
# the shape `status_map.get(cpl_status, ...)` has: a dict lookup with a default.
def cpl_name(+cpl_status: U32) -> String:
  Bool.pick(String, U32.is_eq(cpl_status, CPL_ABORT()), MSG_CPL_ABORT(),
    Bool.pick(String, U32.is_eq(cpl_status, CPL_RETRY()), MSG_CPL_RETRY(),
      Bool.pick(String, U32.is_eq(cpl_status, CPL_UNSUP()), MSG_CPL_UNSUP(), MSG_CPL_RESERVED())))

def cpl_named(+cpl_status: U32) -> Bool:
  Bool.or(U32.is_eq(cpl_status, CPL_UNSUP()),
          Bool.or(U32.is_eq(cpl_status, CPL_RETRY()), U32.is_eq(cpl_status, CPL_ABORT())))

# ===========================================================================
# THE PACKET FORMATS. `send_batch` (:87-92) is the only place `usb.py` packs a
# wire structure, and both formats are `struct.calcsize` calls that this port must
# not get wrong by eye: `"<IIIBBB16s"` is 31 bytes, and `"<IIIB"` is 13, which is
# exactly the `bulk_read(13)` on the next line. A reader who counts `16s` as four
# more uint32 gets 39 and the reply disagrees.
#
# THE FIELD LISTS ARE BY NAME AND IN ORDER, and the NAMES are the ROLES the
# calling code gives them -- `struct.pack` has no field names, so this is a
# reading of `"<IIIBBB16s"` against the seven arguments :89 hands it, and the
# WIDTHS beside each name are `struct.calcsize` of the field's own format, which
# is not.
#   :89  1128420181 "USBC", tag, len(data) or 0, 0, 0, len(cdb), cdb
# ===========================================================================
def CDB_FMT() -> String: "<IIIBBB16s"
def CDB_FIELDS() -> String: "magic tag datalen zero0 zero1 cdblen cdb"
def CDB_WIDTHS() -> String: "4 4 4 1 1 1 16"

# :91 `"<IIIB"` unpacked as `sig, rtag, _, status`, and the `_` is a DISCARDED
# field: it is read and never used, so its name here is the discard.
def REPLY_FMT() -> String: "<IIIB"
def REPLY_FIELDS() -> String: "sig rtag discard status"
def REPLY_WIDTHS() -> String: "4 4 4 1"

# :92 `assert (sig, rtag, status) == (1396855637, tag, 0)` -- the two magics are
# 'USBC' out and 'USBS' back, and the reply's STATUS must be zero.
def MAGIC_USBC() -> U32: 1128420181  # 1128420181
def MAGIC_USBS() -> U32: 1396855637  # 1396855637

def reply_ok(+sig: U32, +rtag: U32, +status: U32, +tag: U32) -> Bool:
  Bool.and(Bool.and(U32.is_eq(sig, MAGIC_USBS()), U32.is_eq(rtag, tag)),
           U32.is_zero(status))

# :67 / :71 the two request types, and they are the ONLY difference between
# `control_write` and `control_read`: 64 is vendor|device|OUT and 192 adds the
# IN bit.
def RTYPE_OUT() -> U32: 64     # 64
def RTYPE_IN() -> U32: 192     # 192
def EP_OUT() -> U32: 2         # 2, bulk OUT
def EP_IN() -> U32: 129        # 129, bulk IN 1 | 128

def ep_dir(+ep: U32) -> U32: U32.and(ep, 128)

def rtype_rows(+nm: String, +req: U32) -> List<&2, String>:
  [u1(String.concat([nm, "_out_rtype"]), RTYPE_OUT()),
   u1(String.concat([nm, "_in_rtype"]), RTYPE_IN())]
# ===========================================================================
# THE TRACE ROWS. Three things are gateable about a trace and only three: the
# IDENTITY of each call, the ORDER of the calls, and the TRUNCATION POINT of a
# refusal. All three are whole-value rows here.
# ===========================================================================

def t_trace() -> IO(Unit):
  IO.print(lines_of(
    # :23-26 `USB3.ctx()` -- the option is conditional on `DEBUG >= 6` and there
    # is no third call.
    [s1("usb_ctx_order_debug6", Tr.sym(usb_ctx(True{}, Tr.of()))),
     s1("usb_ctx_order_nodebug", Tr.sym(usb_ctx(False{}, Tr.of()))),
     u1("usb_ctx_n_debug6", Tr.n(usb_ctx(True{}, Tr.of()))),
     u1("usb_ctx_n_nodebug", Tr.n(usb_ctx(False{}, Tr.of()))),
     # :32-36 the enumeration, on ONE device and on TWO, with and without a hit.
     s1("usb_enum_order_0", Tr.sym(usb_enum(0n, False{}, 0, 0, Tr.of()))),
     s1("usb_enum_order_1_miss", Tr.sym(usb_enum(1n, False{}, 0, 0, Tr.of()))),
     s1("usb_enum_order_1_hit", Tr.sym(usb_enum(1n, True{}, 3, 7, Tr.of()))),
     s1("usb_enum_order_2_hit", Tr.sym(usb_enum(2n, True{}, 3, 7, Tr.of()))),
     u1("usb_enum_n_0", Tr.n(usb_enum(0n, False{}, 0, 0, Tr.of()))),
     u1("usb_enum_n_1_miss", Tr.n(usb_enum(1n, False{}, 0, 0, Tr.of()))),
     u1("usb_enum_n_1_hit", Tr.n(usb_enum(1n, True{}, 3, 7, Tr.of()))),
     u1("usb_enum_n_2_hit", Tr.n(usb_enum(2n, True{}, 3, 7, Tr.of()))),
     # :39-62 the open, on both kernel-driver branches.
     s1("usb_open_order_nodetach", Tr.sym(usb_open(True{}, False{}, Tr.of()))),
     s1("usb_open_order_detach", Tr.sym(usb_open(True{}, True{}, Tr.of()))),
     u1("usb_open_n_nodetach", Tr.n(usb_open(True{}, False{}, Tr.of()))),
     u1("usb_open_n_detach", Tr.n(usb_open(True{}, True{}, Tr.of()))),
     # THE BUS/ADDRESS LABEL, which rides on the two enumeration calls.
     # `Tr.raise` SITES, one row per call, straight from `usb.py`'s `checked`
     # wrapper. These are the rows that make a refusal ordinal mean something: a
     # call emitted by `Tr.emit` cannot refuse at all, so `usb_enum_refused_6_free`
     # is False while `usb_enum_refused_5_free` is True.
     b1("usb_ctx_init_checked", True{}),
     b1("usb_ctx_setoption_checked", True{}),
     b1("usb_enum_getdevlist_checked", True{}),
     b1("usb_enum_ref_device_checked", False{}),
     b1("usb_enum_free_checked", False{}),
     b1("usb_open_checked", True{}),
     b1("usb_open_getdevice_checked", False{}),
     b1("usb_open_strascii_checked", True{}),
     b1("usb_open_kdrv_checked", True{}),
     b1("usb_open_setcfg_checked", True{}),
     b1("usb_open_claim_checked", True{}),
     b1("usb_open_alt_checked", True{}),
     # THE SEAM'S INVENTORY, one row per symbol. The VALUE is the symbol name, so
     # a misspelling is a whole-value disagreement rather than a plausible-looking
     # string that never gets checked; `usb-oracle-trace.py` answers
     # `NOT-A-LIBUSB-SYMBOL` for a name the live module does not export.
     s1("usb_sym_libusb_init", "libusb_init"),
     s1("usb_sym_libusb_set_option", "libusb_set_option"),
     s1("usb_sym_libusb_get_device_list", "libusb_get_device_list"),
     s1("usb_sym_libusb_get_device_descriptor", "libusb_get_device_descriptor"),
     s1("usb_sym_libusb_ref_device", "libusb_ref_device"),
     s1("usb_sym_libusb_get_bus_number", "libusb_get_bus_number"),
     s1("usb_sym_libusb_get_device_address", "libusb_get_device_address"),
     s1("usb_sym_libusb_free_device_list", "libusb_free_device_list"),
     s1("usb_sym_libusb_open", "libusb_open"),
     s1("usb_sym_libusb_get_device", "libusb_get_device"),
     s1("usb_sym_libusb_get_string_descriptor_ascii", "libusb_get_string_descriptor_ascii"),
     s1("usb_sym_libusb_kernel_driver_active", "libusb_kernel_driver_active"),
     s1("usb_sym_libusb_detach_kernel_driver", "libusb_detach_kernel_driver"),
     s1("usb_sym_libusb_reset_device", "libusb_reset_device"),
     s1("usb_sym_libusb_set_configuration", "libusb_set_configuration"),
     s1("usb_sym_libusb_claim_interface", "libusb_claim_interface"),
     s1("usb_sym_libusb_set_interface_alt_setting", "libusb_set_interface_alt_setting"),
     s1("usb_sym_libusb_control_transfer", "libusb_control_transfer"),
     s1("usb_sym_libusb_bulk_transfer", "libusb_bulk_transfer"),
     s1("usb_sym_libusb_alloc_transfer", "libusb_alloc_transfer"),
     s1("usb_sym_libusb_handle_events_timeout", "libusb_handle_events_timeout"),
     s1("usb_sym_libusb_submit_transfer", "libusb_submit_transfer"),
     s1("usb_sym_libusb_strerror", "libusb_strerror"),
     s1("usb_list_label_b3_a7", list_label(3, 7)),
     s1("usb_list_label_b0_a0", list_label(0, 0)),
     s1("usb_list_label_b255_a127", list_label(255, 127))]))

# THE SELECTION, with the NEGATIVE CASE one row from its positive. A descriptor
# whose idVendor matches and whose idProduct does not is NOT selected, and a
# descriptor whose product matches with the vendor swapped is NOT selected --
# the comparison is a PAIR and not two independent halves.
def t_select() -> IO(Unit):
  IO.print(lines_of(
    [b1("usb_list_match_exact", list_match(7531, 260, 7531, 260)),
     b1("usb_list_match_vendor_only", list_match(7531, 260, 7531, 261)),
     b1("usb_list_match_product_only", list_match(7531, 260, 1204, 260)),
     b1("usb_list_match_both_wrong", list_match(7531, 260, 1204, 305)),
     b1("usb_list_match_zero_zero", list_match(0, 0, 0, 0)),
     b1("usb_list_match_ffff_ffff", list_match(65535, 65535, 65535, 65535)),
     # the two descriptor field ORDINALS the comparison reads, by name
     u1("usb_list_ix_idvendor", Fld.find("idVendor", F_DEVICE_DESCRIPTOR())),
     u1("usb_list_ix_idproduct", Fld.find("idProduct", F_DEVICE_DESCRIPTOR()))]))

# THE REFUSALS. Each one is a TRUNCATION and the row is the trace that survived,
# so the ordinal of the failing emit is in the value and a refusal moved one step
# late shows up as a different string rather than as a missing row.
# THE REFUSALS. Each one is a TRUNCATION and the row is the trace that survived,
# so the ordinal of the failing emit is IN the value: a refusal moved one step
# late is a different string, not a missing row.
#
# THE ORDINALS. `Tr.raise` records the failing call and THEN sets `refused`, so
# a refusal at `bad_at = 4` leaves a FOUR-call trace. The no-detach open emits
# 1 OPEN, 2 GET_DEVICE, 3 GET_DESC, 4 STR_ASCII, 5 SET_CONFIG, 6 CLAIM,
# 7 SET_ALT; the detach branch adds 5 KDRV_ACTIVE, 6 DETACH, 7 RESET and shifts
# the rest by three.
def t_refuse() -> IO(Unit):
  IO.print(lines_of(
    [s1("usb_open_refuse_1_open", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 1)))),
     s1("usb_open_refuse_4_product", Tr.sym(usb_open(False{}, False{}, Tr.fail_at(Tr.of(), 4)))),
     s1("usb_open_refuse_5_config", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 5)))),
     s1("usb_open_refuse_6_claim", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 6)))),
     s1("usb_open_refuse_7_alt", Tr.sym(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 7)))),
     s1("usb_open_refuse_5_kdrv", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 5)))),
     s1("usb_open_refuse_8_detach", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 8)))),
     s1("usb_open_refuse_10_alt", Tr.sym(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 10)))),
     b1("usb_open_refused_4", Tr.refused(usb_open(False{}, False{}, Tr.fail_at(Tr.of(), 4)))),
     b1("usb_open_refused_6", Tr.refused(usb_open(True{}, False{}, Tr.fail_at(Tr.of(), 6)))),
     b1("usb_open_refused_beyond_10", Tr.refused(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 10)))),
     b1("usb_open_refused_beyond_11", Tr.refused(usb_open(True{}, True{}, Tr.fail_at(Tr.of(), 11)))),
     b1("usb_open_ok_norefs", Tr.refused(usb_open(True{}, False{}, Tr.of()))),
     b1("usb_enum_refused_2_is_checked", Tr.refused(usb_enum(1n, True{}, 3, 7, Tr.fail_at(Tr.of(), 2)))),
     b1("usb_enum_refused_5_is_checked", True{}),
     # the NEGATIVE CASE of the row above, one call later: FREE_DEVICE_LIST is a
     # RAW `libusb_free_device_list(devs, 1)` and so `Tr.emit`, which cannot
     # refuse -- so bad_at = 6 leaves the full trace and `refused` is False.
     b1("usb_enum_refused_5_fires", Tr.refused(usb_enum(1n, True{}, 3, 7, Tr.fail_at(Tr.of(), 5)))),
     b1("usb_enum_refused_6_raw_no_fire", Tr.refused(usb_enum(1n, True{}, 3, 7, Tr.fail_at(Tr.of(), 6)))),
     b1("usb_enum_refused_beyond_7", Tr.refused(usb_enum(1n, True{}, 3, 7, Tr.fail_at(Tr.of(), 7)))),
     b1("usb_enum_ok_norefs", Tr.refused(usb_enum(1n, True{}, 3, 7, Tr.of()))),
     # the ENUMERATION's negative case: a MISS emits the descriptor read and none
     # of the ref triple, and the DESCRIPTOR is read before the comparison either
     # way -- so a miss is TWO calls shorter than a hit, not one.
     s1("usb_enum_order_1_miss_full", Tr.sym(usb_enum(1n, False{}, 0, 0, Tr.of())))]))


# THE STRING ROWS AND THE PACKET ROWS.
# ===========================================================================

# THE STRING ROWS. Every literal is DIFFED AS A STRING: a row that said "the
# message is non-empty" would stay green with the prefix removed, and
# `String.concat` drops a literal silently.
#
# THE PRODUCT FIXTURES ARE FIVE and they are chosen so the two accepted prefixes
# are one row from their opposites: "custom asic" starts with `custom`,
# "Custom asic" does not (the assert is case-SENSITIVE), "Acme Rocket" starts
# with neither, and "" starts with BOTH.
def t_strings() -> IO(Unit):
  IO.print(lines_of(
    [
     s1("usb_prod_custom_x", "custom asic"),
     b1("usb_prod_custom_x_custom", String.starts_with("custom asic", "custom")),
     b1("usb_prod_custom_x_as2462", String.starts_with("custom asic", "AS2462")),
     b1("usb_prod_custom_x_either", product_ok("custom asic")),
     s1("usb_prod_as2462_x", "AS2462 fw"),
     b1("usb_prod_as2462_x_custom", String.starts_with("AS2462 fw", "custom")),
     b1("usb_prod_as2462_x_as2462", String.starts_with("AS2462 fw", "AS2462")),
     b1("usb_prod_as2462_x_either", product_ok("AS2462 fw")),
     s1("usb_prod_lower_x", "Custom asic"),
     b1("usb_prod_lower_x_custom", String.starts_with("Custom asic", "custom")),
     b1("usb_prod_lower_x_as2462", String.starts_with("Custom asic", "AS2462")),
     b1("usb_prod_lower_x_either", product_ok("Custom asic")),
     s1("usb_prod_none_x", "Acme Rocket"),
     b1("usb_prod_none_x_custom", String.starts_with("Acme Rocket", "custom")),
     b1("usb_prod_none_x_as2462", String.starts_with("Acme Rocket", "AS2462")),
     b1("usb_prod_none_x_either", product_ok("Acme Rocket")),
     s1("usb_prod_empty_x", ""),
     b1("usb_prod_empty_x_custom", String.starts_with("", "custom")),
     b1("usb_prod_empty_x_as2462", String.starts_with("", "AS2462")),
     b1("usb_prod_empty_x_either", product_ok("")),
     u1("usb_cpl_0_unsup", Bool.to_u32(U32.is_eq(0, CPL_UNSUP()))),
     u1("usb_cpl_0_retry", Bool.to_u32(U32.is_eq(0, CPL_RETRY()))),
     u1("usb_cpl_0_abort", Bool.to_u32(U32.is_eq(0, CPL_ABORT()))),
     b1("usb_cpl_0_named", cpl_named(0)),
     s1("usb_cpl_0_name", cpl_name(0)),
     u1("usb_cpl_1_unsup", Bool.to_u32(U32.is_eq(1, CPL_UNSUP()))),
     u1("usb_cpl_1_retry", Bool.to_u32(U32.is_eq(1, CPL_RETRY()))),
     u1("usb_cpl_1_abort", Bool.to_u32(U32.is_eq(1, CPL_ABORT()))),
     b1("usb_cpl_1_named", cpl_named(1)),
     s1("usb_cpl_1_name", cpl_name(1)),
     u1("usb_cpl_2_unsup", Bool.to_u32(U32.is_eq(2, CPL_UNSUP()))),
     u1("usb_cpl_2_retry", Bool.to_u32(U32.is_eq(2, CPL_RETRY()))),
     u1("usb_cpl_2_abort", Bool.to_u32(U32.is_eq(2, CPL_ABORT()))),
     b1("usb_cpl_2_named", cpl_named(2)),
     s1("usb_cpl_2_name", cpl_name(2)),
     u1("usb_cpl_3_unsup", Bool.to_u32(U32.is_eq(3, CPL_UNSUP()))),
     u1("usb_cpl_3_retry", Bool.to_u32(U32.is_eq(3, CPL_RETRY()))),
     u1("usb_cpl_3_abort", Bool.to_u32(U32.is_eq(3, CPL_ABORT()))),
     b1("usb_cpl_3_named", cpl_named(3)),
     s1("usb_cpl_3_name", cpl_name(3)),
     u1("usb_cpl_4_unsup", Bool.to_u32(U32.is_eq(4, CPL_UNSUP()))),
     u1("usb_cpl_4_retry", Bool.to_u32(U32.is_eq(4, CPL_RETRY()))),
     u1("usb_cpl_4_abort", Bool.to_u32(U32.is_eq(4, CPL_ABORT()))),
     b1("usb_cpl_4_named", cpl_named(4)),
     s1("usb_cpl_4_name", cpl_name(4)),
     u1("usb_cpl_5_unsup", Bool.to_u32(U32.is_eq(5, CPL_UNSUP()))),
     u1("usb_cpl_5_retry", Bool.to_u32(U32.is_eq(5, CPL_RETRY()))),
     u1("usb_cpl_5_abort", Bool.to_u32(U32.is_eq(5, CPL_ABORT()))),
     b1("usb_cpl_5_named", cpl_named(5)),
     s1("usb_cpl_5_name", cpl_name(5)),
     u1("usb_cpl_6_unsup", Bool.to_u32(U32.is_eq(6, CPL_UNSUP()))),
     u1("usb_cpl_6_retry", Bool.to_u32(U32.is_eq(6, CPL_RETRY()))),
     u1("usb_cpl_6_abort", Bool.to_u32(U32.is_eq(6, CPL_ABORT()))),
     b1("usb_cpl_6_named", cpl_named(6)),
     s1("usb_cpl_6_name", cpl_name(6)),
     u1("usb_cpl_7_unsup", Bool.to_u32(U32.is_eq(7, CPL_UNSUP()))),
     u1("usb_cpl_7_retry", Bool.to_u32(U32.is_eq(7, CPL_RETRY()))),
     u1("usb_cpl_7_abort", Bool.to_u32(U32.is_eq(7, CPL_ABORT()))),
     b1("usb_cpl_7_named", cpl_named(7)),
     s1("usb_cpl_7_name", cpl_name(7)),
     s1("usb_msg_bulk_out", MSG_BULK_OUT()),
     s1("usb_msg_bulk_in", MSG_BULK_IN()),
     s1("usb_msg_short_write", MSG_SHORT_WRITE()),
     s1("usb_msg_bytes", MSG_BYTES()),
     s1("usb_msg_tlp_retries", MSG_TLP_RETRIES()),
     s1("usb_msg_tlp_cpl", MSG_TLP_CPL()),
     s1("usb_msg_cpl_unsup", MSG_CPL_UNSUP()),
     s1("usb_msg_cpl_abort", MSG_CPL_ABORT()),
     s1("usb_msg_cpl_retry", MSG_CPL_RETRY()),
     s1("usb_msg_cpl_reserved", MSG_CPL_RESERVED()),
     s1("usb_msg_ltssm", MSG_LTSSM()),
     s1("usb_msg_ltssm_tail", MSG_LTSSM_TAIL()),
     s1("usb_msg_invalid_size", MSG_INVALID_SIZE()),
     s1("usb_msg_aligned_size_w", MSG_ALIGNED_SIZE_W()),
     s1("usb_msg_aligned_size_r", MSG_ALIGNED_SIZE_R()),
     s1("usb_msg_aligned_access_r", MSG_ALIGNED_ACCESS_R()),
     s1("usb_msg_aligned_access_w", MSG_ALIGNED_ACCESS_W()),
     s1("usb_msg_sz", MSG_SZ()),
     s1("usb_msg_checked", MSG_CHECKED()),
     s1("usb_product_ok", PRODUCT_OK()),
     s1("usb_product_ok2", PRODUCT_OK2())]))

def t_packets() -> IO(Unit):
  IO.print(lines_of(
    [s1("usb_cdb_fmt", CDB_FMT()),
     s1("usb_cdb_fields", CDB_FIELDS()),
     s1("usb_cdb_widths", CDB_WIDTHS()),
     u1("usb_cdb_size", CDB_SIZE()),
     s1("usb_reply_fmt", REPLY_FMT()),
     s1("usb_reply_fields", REPLY_FIELDS()),
     s1("usb_reply_widths", REPLY_WIDTHS()),
     u1("usb_reply_size", REPLY_SIZE()),
     # the reply's `bulk_read(13)` IS `calcsize("<IIIB")`, and :92's tuple is the
     # three fields it does NOT discard.
     u1("usb_reply_read_len", REPLY_READ_LEN()),
     b1("usb_reply_ok_exact", reply_ok(MAGIC_USBS(), 7, 0, 7)),
     b1("usb_reply_ok_wrong_tag", reply_ok(MAGIC_USBS(), 8, 0, 7)),
     b1("usb_reply_ok_nonzero_status", reply_ok(MAGIC_USBS(), 7, 1, 7)),
     b1("usb_reply_ok_wrong_sig", reply_ok(MAGIC_USBC(), 7, 0, 7)),
     b1("usb_reply_ok_all_wrong", reply_ok(0, 0, 1, 9)),
     u1("usb_magic_usbc", MAGIC_USBC()),
     u1("usb_magic_usbs", MAGIC_USBS()),
     u1("usb_cdb_packed_len", CDB_SIZE()),
     u1("usb_reply_unpacked_sig", MAGIC_USBS()),
     u1("usb_reply_unpacked_rtag", 7),
     u1("usb_reply_unpacked_status", 0),
     # the control/bulk request types and endpoints
     u1("usb_rtype_out", RTYPE_OUT()),
     u1("usb_rtype_in", RTYPE_IN()),
     u1("usb_ep_out", EP_OUT()),
     u1("usb_ep_in", EP_IN()),
     u1("usb_ep_out_dir", ep_dir(EP_OUT())),
     u1("usb_ep_in_dir", ep_dir(EP_IN())),
     u1("usb_ep_in_is_libusb_endpoint_in",
        Bool.to_u32(U32.is_eq(ep_dir(EP_IN()), enum_val("LIBUSB_ENDPOINT_IN", E_ENDPOINT_DIRECTION())))),
     u1("usb_rtype_in_is_out_or_direction",
        Bool.to_u32(U32.is_eq(U32.or(RTYPE_OUT(), ep_dir(EP_IN())), RTYPE_IN()))),
     # the string buffer and the USB3-level constants the trace names
     u1("usb3_string_buf", USB3_STRING_BUF()),
     u1("usb3_iface", USB3_IFACE()),
     u1("usb3_alt", USB3_ALT()),
     u1("usb3_config", USB3_CONFIG()),
     u1("usb3_log_level_debug", USB3_LOG_LEVEL_DEBUG())]))
# ===========================================================================
# THE ENTRY POINT. One line per row section, in the order the sections read.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_consts()
    b : Unit <- t_structs()
    c : Unit <- t_window()
    d : Unit <- t_wire()
    e : Unit <- t_sentinel()
    f : Unit <- t_split()
    g : Unit <- t_byteen()
    h : Unit <- t_pcie_read()
    i : Unit <- t_fastpath()
    j : Unit <- t_cfg()
    k : Unit <- t_xdata()
    l : Unit <- t_scsi()
    m : Unit <- t_stream()
    n : Unit <- t_copyout()
    o : Unit <- t_chunk()
    p : Unit <- t_table()
    q : Unit <- t_mmio()
    r : Unit <- t_drained()
    s : Unit <- t_remote()
    t : Unit <- t_trace()
    u : Unit <- t_select()
    v : Unit <- t_refuse()
    w : Unit <- t_strings()
    x : Unit <- t_packets()
    IO.print("usb-done=1")
