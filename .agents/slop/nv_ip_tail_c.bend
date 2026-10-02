# ---------------------------------------------------------------------------
# :602 `def bdf_as_int(s): return 0x000 if s.startswith("usb") or
# s.startswith("remote") else (int(s[5:7],16)<<8) | (int(s[8:10],16)<<3) |
# int(s[-1],16)`
#
# TWO hex PAIRS, one hex NIBBLE, and the last character is the one AFTER THE DOT.
# Two things this gets wrong if it is written the obvious way, and the rows
# `ip_bdf_*` reach both:
#   * `int(s[-1],16)` is `s[len-1]`, which for `0000:01:00.0` is `0` -- the digit
#     after the dot. Reading `s[10:12]` takes the FUNCTION and the dot instead.
#   * the guard is `usb` OR `remote`, not `usb` alone. The first version of this
#     had only `usb` and `as_int("remote")` printed 96158: `r`=114, `e`=101,
#     `m`=109, `o`=110 read as hex. `ip_bdf_remote` is that row.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# :389-399 init_libos_args. FIVE log buffers of 0x10000 at 0x10000 strides from
# ONE 2 MiB log allocation, then a sixth region for the RM args -- and the sixth
# has a different size (0x1000) and a different base. So the region table is
# `libos_size(i)` / `libos_pa(i)` with the `i < 5` arm, and `ip_libos_*` pins
# all six plus the total the memcpy at :399 writes.
#
# THE 64-BIT WALL IS HERE AND IT IS NOT OPTIONAL: `id8=int.from_bytes(
# bytes(f"LOG{name}", 'utf-8'), 'big')` is an EIGHT-BYTE name read as a big-endian
# integer. `int.from_bytes(b'LOGINIT','big')` is 0x4C4F47494E49544E, which does
# not fit a U32 and has no U32 spelling. What survives is that the name is eight
# bytes, the first is 'L' for all six, and the sixth name is `RMARGS` and not
# `LOG*` -- so `ip_libos_id8_bytes` is the row and `id8` is the seam.
#   # TODO(p3) support/nv/ip.py:395  id8=int.from_bytes(...)
# ---------------------------------------------------------------------------
def libos_n() -> U32: 6

# `pma.all_three_are_1` -- the row that says a value-only constant table is not
# enough for the PMA flags, because all three constants ARE the value 1 and only
# the SHIFT carries the meaning.
def pma.all_ones() -> Bool:
  Bool.and(pma.is_one("NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS"),
           Bool.and(pma.is_one("NVOS02_FLAGS_MAPPING_NO_MAP"),
                    pma.is_one("NVOS02_FLAGS_ALLOC_USER_READ_ONLY_YES")))

def pma.is_one(nm: String) -> Bool: U32.is_eq(Cn.v(const_of(nm)), 1)

# `over.fits` -- the 64-BIT WALL, stated as a predicate rather than as a
# comment. 24 GiB does not fit a U32 and no port of `init_wpr_meta` can hold it.
# THE 64-BIT WALL, WRITTEN DOWN TWICE BECAUSE BEND HAS NO HEX LITERALS.
#
# There is no `0x` syntax at all in Bend 2.0.34: `U32.show(0xffffffff)` is
#     expected : a numeric literal (NUMBER is U32, NUMBER n is Nat)
#     observed : 'x'
# with the caret on the `x`, so EVERY constant in this file is decimal and the
# header's `0x...` spellings are prose only. That is convenient here, because a
# real card's `vram_size` is 24 GiB -- five hex digits, larger than any U32 -- and
# it cannot be written down either way. `over.fits` asks the question with a
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

# ---------------------------------------------------------------------------
# :616-627 rpc_set_registry_table. `nameOffset = hdr_size + entries_size +
# len(data_bytes)` is a RUNNING SUM: the two entries are at 40 and 61, not at
# 40 and 40+21-by-stride-with-a-constant. `sizeof(PACKED_REGISTRY_ENTRY)` is 16
# and the header 8, so entries_size is 32 -- and the header's OWN `size` field is
# 8 + 32 + 42 = 82, which is the length of the whole record the GSP parses.
# `ip_reg_off0` / `ip_reg_off1` / `ip_reg_size` are the three rows and they are
# the reason the dict-at-:617 is a `List` here: two entries, two offsets.
# ---------------------------------------------------------------------------
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
def reg_type() -> U32: Cn.v(const_of("REGISTRY_TABLE_ENTRY_TYPE_DWORD"))
def reg_val() -> U32: 1

# ---------------------------------------------------------------------------
# :577-580 the PMA flags. THREE constants that are ALL the value 1 -- so the
# table a gate needs is (value, SHIFT) per flag, not value per flag. That is the
# one place in this file where a value-only constant table is not enough, and
# `ip_pma_all_three_are_1` is the row that says so.
# ---------------------------------------------------------------------------
def pma.phys() -> U32: U32.shln(Cn.v(const_of("NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS")), 4n)
def pma.nomap() -> U32: U32.shln(Cn.v(const_of("NVOS02_FLAGS_MAPPING_NO_MAP")), 30n)
def pma.ro(ro: U32) -> U32: U32.shln(ro, 21n)
def pma.flags() -> U32: U32.or(pma.phys(), pma.nomap())

# ---------------------------------------------------------------------------
# :357-362 the channel class table. The DEFAULT is Ampere's triple; `AD`
# overrides ONLY `compute_class`; `GB` overrides all three AND sets a different
# nvdec class. `chip_name[:2]` is a two-character PREFIX match, so `GA102` and
# `AD102` land on the default and `GB202` on the Blackwell row -- and a port that
# matched the whole name would miss all three.
# ---------------------------------------------------------------------------
def cls.gpfifo(+chip: String) -> U32:
  cls.gp2(chip, Cn.v(const_of("AMPERE_CHANNEL_GPFIFO_A")), Cn.v(const_of("BLACKWELL_CHANNEL_GPFIFO_A")))

def cls.gp2(+chip: String, ampere: U32, blackwell: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell, ampere)

def cls.compute(+chip: String) -> U32:
  cls.cp2(chip, Cn.v(const_of("AMPERE_COMPUTE_B")), Cn.v(const_of("BLACKWELL_COMPUTE_B")),
          Cn.v(const_of("ADA_COMPUTE_A")))

def cls.cp2(+chip: String, ampere: U32, blackwell: U32, ada: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell,
    Bool.pick(U32, String.starts_with(chip, "AD"), ada, ampere))

def cls.dma(+chip: String) -> U32:
  cls.dm2(chip, Cn.v(const_of("AMPERE_DMA_COPY_B")), Cn.v(const_of("BLACKWELL_DMA_COPY_B")))

def cls.dm2(+chip: String, ampere: U32, blackwell: U32) -> U32:
  Bool.pick(U32, String.starts_with(chip, "GB"), blackwell, ampere)

# :358 `.get(chip_name[:2])` -- the nvdec class is None for GA, which is the
# `viddec_class is None` the :562 `if hClass == self.viddec_class` guard needs,
# because `hClass == None` is False for every int.
def cls.viddec(+chip: String) -> U32:
  cls.vd2(chip, Cn.v(const_of("NVC9B0_VIDEO_DECODER")), Cn.v(const_of("NVCFB0_VIDEO_DECODER")))

def cls.vd2(+chip: String, ada: U32, gb: U32) -> U32:
  Bool.pick(U32, Bool.or(String.starts_with(chip, "AD"), String.starts_with(chip, "GB")),
            Bool.pick(U32, String.starts_with(chip, "GB"), gb, ada), 0)

# ---------------------------------------------------------------------------
# :629-661 run_cpu_seq's OPCODE TABLE, and :661 is the refusal. Nine opcodes,
# contiguous 0x0..0x8, with a WIDTH each -- and the width is what makes the walk
# a walk: `iter(memoryview(seq_buf[hdr_sz:]).cast('I')[:hdr.cmdIndex])` and then
# `next(cmd_iter)` that many times per op. The five register ops consume words;
# the four falcon ops consume none. `ip_seq_words` is the row, and it is
# `2,3,5,1,2,0,0,0,0` -- a table that said 1 for everything would consume a
# quarter of the program.
# ---------------------------------------------------------------------------
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

# THE LIST TAIL IS THE FIRST ARGUMENT AND THAT IS THE ONLY LEGAL ORDER. A
# self-call is read LEFT TO RIGHT and each argument must pass unchanged until one
# shrinks, so `seq_walk.go(seq_step(i, o), n, t, ...)` is refused with "expected
# : a decreasing self-call" -- the computed index sits IN FRONT of the tail that
# shrinks. The index rides along as the SECOND argument instead.
# THE FOLD MUST SKIP THE OPERANDS, NOT COUNT THEM, AND IT CANNOT DO IT IN ONE
# STEP. :633-651 iterates `cmd_iter` and calls `next(cmd_iter)` INSIDE each arm,
# so the loop only ever SEES an opcode -- but the buffer is a flat `U32` stream.
# The first version stepped the index correctly (`seq_step`) and still took `t`,
# ONE tail, so it read `0xdead` -- an OPERAND of the first `reg_write` -- as an
# opcode and stopped: `ip_seq_prog_consumed` printed 5 where CPython says 12.
#
# Dropping a VARIABLE number of tails in the self-call is refused: a self-call is
# read LEFT TO RIGHT and each argument must pass unchanged until one shrinks, so
# `seq_walk.go(seq.skip(t, o), ...)` is "expected : a decreasing self-call" even
# though `t` is passed unchanged INTO `seq.skip`. So the fold carries the skip
# COUNT as a second U32 and steps one tail at a time -- a two-state machine over
# (skip, head), three lines long, and the only shape the substrate allows.
def seq_walk(+ops: List<&2, U32>) -> Wk: seq_walk.go(ops, 0, 0, Nil{})

def seq_walk.go(+ops: List<&2, U32>, +i: U32, +skip: U32, +acc: List<&2, U32>) -> Wk:
  match ops:
    case Nil{}: Wk{acc, i}

    case o <> t: seq_walk.go(t, seq.at(i, skip, o), seq.next_skip(skip, o), seq.put(acc, skip, o))

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

# ---------------------------------------------------------------------------
# :328-344 kfsp_send_msg's framing. EIGHT bytes of header: `0xC0000000` then
# `0x7e | (0x10de << 8) | (nvmd << 24)`. The first word is BOTH bit 31 and bit
# 30 and is the same for every message; the second carries the function in its
# TOP byte and two magic constants below it. Then `buf = headers + buf + (4 -
# (len(buf) % 4)) * b'\x00'` -- pad to a multiple of FOUR, computed on the
# PAYLOAD length, not the total, so a 4-byte payload adds nothing and a 5-byte
# payload adds three.
# ---------------------------------------------------------------------------
def fsp_w0() -> U32: U32.or(U32.shln(1, 31n), U32.shln(1, 30n))
def fsp_w1(+nvmd: U32) -> U32: U32.or(U32.or(126, U32.shln(4318, 8n)), U32.shln(nvmd, 24n))
def fsp_hdr_len() -> U32: 8
def fsp_pad(+blen: U32) -> U32: U32.mod(U32.sub(4, U32.mod(blen, 4)), 4)
def fsp_tot(+blen: U32) -> U32: U32.add(U32.add(blen, fsp_hdr_len()), fsp_pad(blen))

# :332 `assert len(buf) < 0x400` -- 1024. `fsp_ok` is the arm that reaches the
# write; `ip_fsp_max_ok_payload` is the largest payload that does.
def fsp_max() -> U32: 1024
def fsp_ok(+tot: U32) -> Bool: U32.is_lt(tot, 1024)

# ---------------------------------------------------------------------------
# :530-531 rpc_alloc_memory's scalars, and :533's pte descriptor.
# `pte=(paddr >> 12)` is a PAGE NUMBER, and the packed payload is
# `8 * pageCount` bytes of pte descriptors after the 56-byte rpc header -- so
# `pageCount` and the payload length are two readings of the same list and
# `ip_am_payload` is the row that ties them.
# ---------------------------------------------------------------------------
def pte_shift(+paddr: U32) -> U32: U32.shrn(paddr, 12n)
def pte_mask(+n: U32) -> U32: U32.and(n, 65535)
def am_format() -> U32: 6
def am_pte_adjust() -> U32: 0
def am_idr() -> U32: Cn.v(const_of("NV_VGPU_PTEDESC_IDR_NONE"))
def am_hdr() -> U32: 56
def am_pte_sz() -> U32: 8
def am_payload(+npages: U32) -> U32: U32.add(am_hdr(), U32.mul(am_pte_sz(), npages))

# :526 `assert all(sz == 0x1000 for _, sz in paddrs)` -- the refusal, and the
# only one in this file that fires on a CALLER's data. `am_pages_ok` is the arm.
def am_page(+sz: U32) -> Bool: U32.is_eq(sz, 4096)
def am_pages_ok(+sz0: U32, +sz1: U32) -> Bool: Bool.and(am_page(sz0), am_page(sz1))

# ---------------------------------------------------------------------------
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
  U32.sub(ucode_desc_size, Cn.v(const_of("FALCON_UCODE_DESC_V3_SIZE_44")))

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

# the FIXTURE engine table as rows: 25 `size`/`align` pairs, folded. They are the
# inputs every `_ctx_info` reads, so `ip_ctx_<i>_size` / `ip_ctx_<i>_align` pin
# them INDIVIDUALLY -- a port that read the wrong INDEX would still produce a
# self-consistent `cfgs`, and only these rows would see it.
def ctx.rows() -> IO(Unit):
  do IO<Unit>:
    ctx.rows.go(ctx.idxlist())

def ctx.rows.go(+xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("ip_ctx_end=1")
    case i <> t:
      do IO<Unit>:
        urow(String.concat(["ip_ctx_", U32.show(i), "_size"]), ctx_eng(i))
        urow(String.concat(["ip_ctx_", U32.show(i), "_align"]), ctx_eng_align(i))
        ctx.rows.go(t)

# :500 the eight `cfgs_sizes`, folded out of the same table.
def ctx.cfg_rows() -> IO(Unit):
  do IO<Unit>:
    ctx.cfg_rows.go(ctx.keys3())

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


# :501-504 the table itself. `local` is True for index 1 ONLY, and `phys` is
# False for 3..6 and True for 9,10,11, while `virt` is False for 10 ONLY.
# :501-504. Keys 0,1,2 come from `engine[GRAPHICS]` and `engine[GRAPHICS_PATCH]`
# and 3..10 from `cfgs_sizes` -- and key 11 REUSES `cfgs_sizes[10]`, which is the
# `# NOTE: 11 reuses cfgs_sizes[10]` in the source. `U32.min(k, 10)` IS that
# reuse, so a table that recomputed 11 from engine 25 would be a different card
# and `ip_grctx_11_reuses_10` is the row.
def grctx.size(+k: U32) -> U32:
  Bool.pick(U32, U32.is_le(k, 2), grctx.early(k), cfgs(U32.min(k, 10)))

# `_ctx_info(idx, add=0)` is `round_up(engine[idx].size + add, align or
# engine[idx].alignment)`, and the GRAPHICS arm adds 0x40000 while the PATCH arm
# adds NOTHING -- so key 0's `add` and key 1's are different arguments.
def grctx.early(+k: U32) -> U32:
  grctx.early2(Bool.pick(U32, U32.is_eq(k, 0), 0, 16),
              Bool.pick(U32, U32.is_eq(k, 0), 262144, 0))

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
def grctx.keys() -> String: grctx.join(grctx.keylist())

# a TRAILING-COMMA-FREE join. The first version appended "," to every element
# including the last, so `ip_grctx_keys` printed `0,1,...,11,` against the
# oracle's `0,1,...,11` -- a real difference, and one that would have hidden a
# genuine off-by-one in the key list behind a formatting fault.
def grctx.join(+xs: List<&2, U32>) -> String: grctx.join1(xs, False{})

# ONE self-recursive def and NO `join2`. Writing the separator decision in a
# second def and calling it back from `join1` is mutual recursion and Bend
# refuses it -- the order tool reported it as a CYCLE (`join1 waits on join2`,
# `join2 waits on join1`), which is the honest reading. `join1` recurses on the
# TAIL and carries the "is this the first element" flag.
def grctx.join1(+xs: List<&2, U32>, first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> t: String.concat([grctx.tag(x, first), grctx.join1(t, True{})])

# the separator goes BEFORE every element that is NOT the first. The arms read
# backwards from the obvious because `Bool.pick` answers its TRUE arm first, and
# `Bool.pick(String, first, "", ",")` therefore put the comma FIRST and nothing
# after: `ip_grctx_keys` printed `,012345691011`.
def grctx.sep(first: Bool) -> String: Bool.pick(String, first, ",", "")

def grctx.tag(+x: U32, first: Bool) -> String: String.concat([grctx.sep(first), U32.show(x)])

# THE INSERTION ORDER OF THE DICT AT :501-504 -- and keys 7 and 8 ARE NOT IN IT.
# `**{x: GRBufDesc(cfgs_sizes[x], ...) for x in range(3, 7)}` covers 3,4,5,6 and
# then 9,10,11 are added by key; nothing ever adds 7 or 8. A port that walked
# 0..11 would emit two rows the source does not have, and `ip_grctx_keys` /
# `ip_grctx_11_reuses_10` are how the differ says so.
def grctx.keylist() -> List<&2, U32>:
  List.concat(&2, U32, [[0], [1], [2], [3], [4], [5], [6], [9], [10], [11]])

def grctx.reuses_10() -> U32: grctx.reuse(grctx.size(11), grctx.size(10))

def grctx.reuse(a: U32, b: U32) -> U32: Bool.pick(U32, U32.is_eq(a, b), 1, 0)

def grctx.local_n() -> U32: grctx.count_local(grctx.keylist(), 0)

def grctx.count_local(+xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case k <> t: grctx.count_local(t, bump(grctx.local(k), n))

def grctx.rows() -> IO(Unit):
  do IO<Unit>:
    grctx.walk(grctx.keylist())

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

def grctx.row(+k: U32) -> IO(Unit):
  srow(String.concat(["ip_grctx_", U32.show(k)]),
    String.join([U32.show(grctx.size(k)), U32.show(Bool.to_u32(grctx.phys(k))),
                 U32.show(Bool.to_u32(grctx.virt(k))), U32.show(Bool.to_u32(grctx.local(k)))], ","))

# :357-362 the class row, joined so a wrong ORDER inside it is a value change.
def cls.row(+chip: String) -> String:
  cls.join4(cls.gpfifo(chip), cls.compute(chip), cls.dma(chip), cls.viddec(chip))

def cls.join4(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  String.join([cls.one(a), cls.one(b), cls.one(c), cls.one(d)], ",")

def cls.one(+v: U32) -> String: Bool.pick(String, U32.is_eq(v, 0), "None", U32.show(v))

# :629-661 the opcode rows, joined.
# The nine opcodes as a LITERAL list rather than a counted range. A `Nat`
# countdown wants `case 0n:` then a `Con` arm, and `case m <> r:` after `case 0n:`
# is "a constructor of Nat (missing, or already matched)" while `case 1n+p:` is a
# PREFIX match that destroys the scrutinee. Nine explicit rows are cheaper than
# either, and `ip_seq_n` pins that there are nine of them.
def seq.ops() -> String: String.join(seq.opslist(), ",")

def seq.opslist() -> List<&2, String>:
  List.concat(&2, String, [[nib(0)], [nib(1)], [nib(2)], [nib(3)], [nib(4)],
                            [nib(5)], [nib(6)], [nib(7)], [nib(8)]])

def seq.names() -> String:
  seq.join5(seq.name(0), seq.name(1), seq.name(2), seq.name(3),
            String.join([seq.name(4), seq.name(5), seq.name(6), seq.name(7), seq.name(8)], ","))

def seq.wordlist() -> String:
  seq.join5(seq.words(0), seq.words(1), seq.words(2), seq.words(3),
            String.join([seq.words(4), seq.words(5), seq.words(6), seq.words(7), seq.words(8)], ","))

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

def seq.walk() -> Wk: seq_walk(seq_prog())
def seq.prog_n() -> U32: seq.count(Wk.ops(seq.walk()), 0)
def seq.prog_ops() -> String: seq.joinu(Wk.ops(seq.walk()), ",")

def seq.count(+xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case x <> t: seq.count(t, U32.add(n, 1))

# `hex8`, not `nib`: the walked OPS are 0x0..0x8 and `nib` answers them, but
# `hex8` is the spelling Python's `'%x'` has and it is the one the oracle used.
# `hex8`, not `nib`: the walked OPS are 0x0..0x8 and `nib` answers them, but
# `hex8` is the spelling Python's `'%x'` has and it is the one the oracle used.
# The separator goes BETWEEN, so the first element is special -- the version that
# appended it unconditionally printed `0,0,3,4,6,`.
def seq.joinu(+xs: List<&2, U32>, sep: String) -> String: seq.joinu1(xs, sep, False{})

def seq.joinu1(+xs: List<&2, U32>, +sep: String, first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> t: String.concat([seq.sep(sep, first), hex8(x), seq.joinu1(t, sep, True{})])

def seq.sep(+sep: String, first: Bool) -> String: Bool.pick(String, first, sep, "")

def door.bit30(+chip: String) -> Bool: String.starts_with(chip, "GB2")
