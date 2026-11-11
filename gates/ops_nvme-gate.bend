# gates/ops_nvme-gate.bend -- the gate driver for `tinybendygrad/runtime/ops_nvme.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/ops_nvme.bend as P
def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def brow(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

def ssh(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ssh(t, x <> acc)

def slrow(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ssh(xs, Nil{}), ",")]))

# --- 1: the entry sizes and the queue's geometry ---------------------------
def t_sizes() -> IO(Unit):
  do IO<Unit>:
    # the two entry sizes. 64 and 16, and the queue's entry count is
    # `0x1000 // P.SQE` = 64 -- ONE PAGE, "so it's contiguous even without
    # an iommu".
    row("nvme_sqe", P.SQE())
    row("nvme_cqe", P.CQE())
    row("nvme_entries", P.QUEUE_ENTRIES())
    # the sqe's length in words. one row for it, and it is `nvme_sqe_len`
    # below -- the first draft had both `nvme_sqe_words` and `nvme_sqe_len`
    # printing the same number, which is a row that cannot be addressed.
    # the register offsets. the doorbells are at 4096 and every other
    # REGISTER IS BELOW IT.
    row("nvme_reg_cap", P.NVME_REG_CAP())
    row("nvme_reg_cc", P.NVME_REG_CC())
    row("nvme_reg_csts", P.NVME_REG_CSTS())
    row("nvme_reg_aqa", P.NVME_REG_AQA())
    row("nvme_reg_asq", P.NVME_REG_ASQ())
    row("nvme_reg_acq", P.NVME_REG_ACQ())
    row("nvme_reg_dbs", P.NVME_REG_DBS())
    # the pci identifier: the vendor, the mask, two device ids and the
    # base class. the device ids are a tuple and not a RANGE.
    row("nvme_vendor", P.NVME_VENDOR())
    row("nvme_mask", P.NVME_MASK())
    row("nvme_devid1", P.NVME_DEVICE_ID_1())
    row("nvme_devid2", P.NVME_DEVICE_ID_2())
    row("nvme_base_class", P.NVME_BASE_CLASS())
    # the OPcodes. the read opcode is 2 and it is the same number as the
    # create-sq opcode's neighbour, so the rows are separate.
    row("nvme_op_identify", P.nvme_admin_identify())
    row("nvme_op_set_features", P.nvme_admin_set_features())
    row("nvme_op_create_cq", P.nvme_admin_create_cq())
    row("nvme_op_create_sq", P.nvme_admin_create_sq())
    row("nvme_op_read", P.nvme_cmd_read())
    row("nvme_feat_num_queues", P.NVME_FEAT_NUM_QUEUES())

# --- 2: the doorbells ------------------------------------------------------
def t_doorbell() -> IO(Unit):
  do IO<Unit>:
    # the `2 * qid` stride. the admin queue is qid 0 and the first IO
    # queue is qid 1, so the first IO queue's doorbells are at 2 and
    # 3 -- not at 0 and 1. a port that uses `qid` for the submission one
    # PUTS IT IN THE ADMIN QUEUE'S PAIR.
    row("nvme_sq_db_q0", P.q.sq_db(0, 4))
    row("nvme_cq_db_q0", P.q.cq_db(0, 4))
    row("nvme_sq_db_q1", P.q.sq_db(1, 4))
    row("nvme_cq_db_q1", P.q.cq_db(1, 4))
    row("nvme_sq_db_q2", P.q.sq_db(2, 4))
    row("nvme_cq_db_q2", P.q.cq_db(2, 4))
    # the stride is the device's own, from the capacity register, and the
    # doorbell addresses MOVE with it. the strides are 4, 8, 16, 32 and 64
    # -- NEVER 1, BECAUSE IT IS `4 << n`.
    row("nvme_db_stride_cap0", P.cap_db_stride(0))
    row("nvme_db_stride_cap1", P.cap_db_stride(1))
    row("nvme_db_stride_cap2", P.cap_db_stride(2))
    row("nvme_db_stride_cap15", P.cap_db_stride(15))
    # the row name is the stride. the first draft printed
    # `nvme_sq_db_q1_s1` for `P.q.sq_db(1, 8)` -- a row whose name said stride
    # 1 and whose value was stride 8. a row whose name and value disagree
    # IS A ROW THAT CANNOT BE ADDRESSED.
    row("nvme_sq_db_q1_s1", P.q.sq_db(1, 1))
    row("nvme_sq_db_q1_s8", P.q.sq_db(1, 8))
    row("nvme_sq_db_q1_s16", P.q.sq_db(1, 16))
    # the capacity register's two words. the high WORD is the one with the
    # stride in it and the timeout is in the low WORD's top BYTE.
    row("nvme_cap_lo", 305419896)
    row("nvme_cap_hi", 4294967295)
    # the timeout. the multiplier is 500, so a capacity register of 0
    # gives a timeout of 0 -- which is "do not wait" and not "wait
    # FOREVER".
    # the fixtures must exercise BYTE 24, or the `* 500` is invisible.
    # the first draft used 0, 1, 255 and 4194304 -- and all four have
    # BYTE 24 clear, so all four timeouts were 0 and the multiplier
    # was not measured at all. a plant that drops the `* 500` moved zero
    # rows, and that is the class the tree already names: "a table with no
    # row that CANNOT move is a table of coincidences". THE FIXTURES ARE NOW
    # 0 (THE ZERO CASE), 1 AND 16777216 (BYTE 24 IS 1) AND 4278190080
    # (BYTE 24 IS 255).
    row("nvme_timeout_cap0", P.cap_timeout_ms(0))
    row("nvme_timeout_cap1", P.cap_timeout_ms(16777216))
    row("nvme_timeout_cap255", P.cap_timeout_ms(4278190080))
    row("nvme_timeout_cap_lo", P.cap_timeout_ms(1))

# --- 3: the command word and the phase -------------------------------------
def t_cmd() -> IO(Unit):
  do IO<Unit>:
    # the command WORD: the opcode in the low sixteen BITS and the slot
    # SHIFTED LEFT BY SIXTEEN.
    # the row name is (opcode, slot) and the first draft said
    # `nvme_cmd_w_2_0` for `P.cmd_word(2, 1)` -- a row whose name said slot 0
    # and whose value was slot 1. a row whose name and value disagree is
    # a row that cannot be addressed, which is the same defect as the
    # ELEVEN DUPLICATE NAMES IN `ops_nv.bend`.
    row("nvme_cmd_w_2_0", P.cmd_word(2, 0))
    row("nvme_cmd_w_2_1", P.cmd_word(2, 1))
    row("nvme_cmd_w_6_0", P.cmd_word(6, 0))
    row("nvme_cmd_w_6_5", P.cmd_word(6, 5))
    row("nvme_cmd_w_2_63", P.cmd_word(2, 63))
    # the slot is in the command WORD, so the command WORD for slot 63
    # is larger than 2^16 and a port that puts the slot somewhere ELSE
    # WRITES A DIFFERENT COMMAND.
    brow("nvme_cmd_slot_in_word", U32.is_gt(P.cmd_word(2, 63), 65536))
    # the tail. it starts at zero and advances modulo the entry count.
    row("nvme_tail_0", P.q.next_tail(0, P.QUEUE_ENTRIES()))
    row("nvme_tail_63", P.q.next_tail(63, P.QUEUE_ENTRIES()))
    row("nvme_tail_wraps", P.q.next_tail(63, P.QUEUE_ENTRIES()))
    # the phase inverts on the new tail. the phase starts at one --
    # not zero -- and it flips only when the new tail is zero, which is
    # the submit that wrapped the ring. a port that checked the old tail
    # FLIPS ONE SUBMIT EARLY.
    row("nvme_phase_start", P.Q.phase(P.Q.of()))
    row("nvme_phase_after_1", P.q.next_phase(1, 1))
    row("nvme_phase_after_63", P.q.next_phase(1, 63))
    row("nvme_phase_after_wrap", P.q.next_phase(1, 0))
    # and the phase is a bit, so it is 0 or 1 and never 2.
    brow("nvme_phase_is_bit", U32.is_le(P.q.next_phase(1, 0), 1))
    # the sqe's sixty-four bytes as sixteen words. the opcode is in WORD 0
    # and the prp address's high half is in WORD 4.
    lrow("nvme_sqe_words_0", P.sqe_words(2, 0, 0, 0, 0, 0, 0))
    lrow("nvme_sqe_words_1", P.sqe_words(2, 5, 7, 11, 13, 17, 19))
    row("nvme_sqe_len", U32.from_nat(List.length(&2, U32, P.sqe_words(2, 0, 0, 0, 0, 0, 0))))

# --- 4: the PRP table ------------------------------------------------------
def t_prp() -> IO(Unit):
  do IO<Unit>:
    # THE LIST PAGE COUNT. `ceildiv(len(pages) + 1, 256)` -- THE `+ 1`
    # is why a single page still gets a list page, and a read that exactly
    # FILLS 256 PAGES GETS TWO.
    row("nvme_prp_list_pages_0", P.prp_list_pages(0))
    row("nvme_prp_list_pages_1", P.prp_list_pages(1))
    row("nvme_prp_list_pages_255", P.prp_list_pages(255))
    row("nvme_prp_list_pages_256", P.prp_list_pages(256))
    row("nvme_prp_list_pages_257", P.prp_list_pages(257))
    row("nvme_prp_list_pages_512", P.prp_list_pages(512))
    # THE TABLE'S BYTES. `round_up(16 * len(pages), 0x1000)` -- SIXTEEN
    # bytes per page and rounded to a page.
    row("nvme_prp_table_bytes_1", P.prp_table_bytes(1))
    row("nvme_prp_table_bytes_64", P.prp_table_bytes(64))
    row("nvme_prp_table_bytes_256", P.prp_table_bytes(256))
    row("nvme_prp_table_bytes_257", P.prp_table_bytes(257))
    # the table's entry count is twice the page count, because each page
    # IS FOLLOWED BY A POINTER.
    row("nvme_prp_entries_1", P.prp_entry_count(1))
    row("nvme_prp_entries_256", P.prp_entry_count(256))
    # the pointer. the pointer is for page `p + 1`, so the pointer of
    # page 0 is the list slot of page 1 -- which is OFFSET 8, not 0.
    row("nvme_prp_ptr_0", P.prp_ptr(4096, 0))
    row("nvme_prp_ptr_1", P.prp_ptr(4096, 1))
    row("nvme_prp_ptr_255", P.prp_ptr(4096, 255))
    row("nvme_prp_ptr_256", P.prp_ptr(4096, 256))
    # AND THE LIST PAGE IT LIVES IN.
    row("nvme_prp_ptr_page_0", P.prp_ptr_page(0))
    row("nvme_prp_ptr_page_254", P.prp_ptr_page(254))
    row("nvme_prp_ptr_page_255", P.prp_ptr_page(255))
    row("nvme_prp_ptr_page_256", P.prp_ptr_page(256))
    # the pointer is never zero-OFFSET for the first page, which is the
    # rule that a port gets wrong by writing `p % 256` instead of
    # `(p + 1) % 256`.
    brow("nvme_prp_ptr_not_first", Bool.not(U32.is_eq(P.prp_ptr(4096, 0), 4096)))
    # the table's entries, as a flat list. the order is page, pointer,
    # page, pointer -- and the port's first two entries are the first page
    # and the pointer for the second page.
    lrow("nvme_prp_entries_list_2", P.prp_entries([100, 200], 4096))
    lrow("nvme_prp_entries_list_3", P.prp_entries([100, 200, 300], 4096))
    row("nvme_prp_entries_len_3", U32.from_nat(List.length(&2, U32, P.prp_entries([100, 200, 300], 4096))))

# --- 5: the identify -------------------------------------------------------
def t_ident() -> IO(Unit):
  do IO<Unit>:
    # `P.max_xfer = 0x1000 << min(ident[77] or 8, 8)`. THE `or 8` IS THE
    # python truthiness of a zero BYTE and the `min` is the cap. a mpsz
    # OF 16 IS CLAMPED TO 8, SO THE MAXIMUM TRANSFER IS 32 KiB.
    row("nvme_mpsz_or_0", P.mpsz_or_default(0))
    row("nvme_mpsz_or_8", P.mpsz_or_default(8))
    row("nvme_max_xfer_0", P.max_xfer(P.mpsz_or_default(0)))
    row("nvme_max_xfer_1", P.max_xfer(1))
    row("nvme_max_xfer_8", P.max_xfer(8))
    row("nvme_max_xfer_16", P.max_xfer(16))
    row("nvme_max_xfer_64", P.max_xfer(64))
    # the cap is the point: a drive that reports a bigger MPSz gets
    # 8, NOT 16 AND NOT 64.
    brow("nvme_max_xfer_capped", U32.is_eq(P.max_xfer(64), P.max_xfer(8)))
    # THE LBA SHIFT'S INDEX. `128 + 4 * (ident[26] & 0xf) + 2` -- THE `+ 2`
    # is the low BYTE of the four-BYTE entry, and a port that reads
    # `ident[128 + 4 * n]` READS THE HIGH BYTE.
    row("nvme_lba_ix_0", P.lba_shift_index(0))
    row("nvme_lba_ix_1", P.lba_shift_index(1))
    row("nvme_lba_ix_15", P.lba_shift_index(15))
    # and the shift itself, from an identify with a known lba format
    # DESCRIPTOR AT BYTE 26 AND A KNOWN ENTRY AT 130.
    row("nvme_lba_shift_0", P.lba_shift([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 12]))
    row("nvme_lba_shift_1", P.lba_shift([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 9]))
    # a BYTE past the end of the identify is zero, not a crash.
    row("nvme_ident_past_end", P.ident_byte([1, 2, 3], 10))
    row("nvme_ident_at", P.ident_byte([1, 2, 3], 1))
    # the device's SIZE: the low eight bytes of the identify, shifted left
    # BY THE LBA SHIFT.
    row("nvme_size_0", P.dev_size(1000, 0, 9))
    row("nvme_size_1", P.dev_size(1000, 0, 12))
    row("nvme_size_2", P.dev_size(1000, 0, 0))

# --- 6: the queue creation -------------------------------------------------
def t_create() -> IO(Unit):
  do IO<Unit>:
    # the qid is `len(self.queues) + 1` -- the admin queue is 0 and the
    # FIRST IO QUEUE IS 1.
    row("nvme_qid_0", P.new_qid(0))
    row("nvme_qid_1", P.new_qid(1))
    row("nvme_qid_3", P.new_qid(3))
    # the create's CDW10. the `- 1` is the zero-based SIZE and the qid is
    # IN THE LOW SIXTEEN.
    row("nvme_create_cdw10_64_1", P.create_cdw10(64, 1))
    row("nvme_create_cdw10_64_0", P.create_cdw10(64, 0))
    row("nvme_create_cdw10_1_1", P.create_cdw10(1, 1))
    # the `- 1` is LOAD-bearing: a queue of 64 entries is created with
    # the SIZE field 63, and a port that passes 64 creates a queue one
    # entry shorter than the device offers.
    row("nvme_create_size_field", U32.shrn(P.create_cdw10(64, 1), 16n))
    # the two CDW11s. the create-sq's is `P.q.qid << 16 | 1` and the
    # create-cq's is 1 -- the square bracket is the physical queue
    # number and the `1` is the enable flag.
    row("nvme_create_cq_cdw11", P.create_cq_cdw11())
    row("nvme_create_sq_cdw11_1", P.create_sq_cdw11(1))
    row("nvme_create_sq_cdw11_4", P.create_sq_cdw11(4))
    row("nvme_create_sq_qid", U32.shrn(P.create_sq_cdw11(4), 16n))
    brow("nvme_create_cq_sq_differ", Bool.not(U32.is_eq(P.create_cq_cdw11(), P.create_sq_cdw11(1))))

# --- 7: the copy stream ----------------------------------------------------
def t_copy() -> IO(Unit):
  do IO<Unit>:
    # the command count. ceildiv: a read of exactly one `P.max_xfer` is
    # ONE COMMAND, NOT TWO.
    row("nvme_cmds_0", P.cmds_for(0, 4096))
    row("nvme_cmds_1", P.cmds_for(1, 4096))
    row("nvme_cmds_4096", P.cmds_for(4096, 4096))
    row("nvme_cmds_4097", P.cmds_for(4097, 4096))
    row("nvme_cmds_8192", P.cmds_for(8192, 4096))
    row("nvme_cmds_8193", P.cmds_for(8193, 4096))
    # the `(full, rem)` split. the leftover is the last command and it is
    # SHORTER.
    row("nvme_full_4096", P.full_windows(4096, 4096))
    row("nvme_full_4097", P.full_windows(4097, 4096))
    row("nvme_full_8192", P.full_windows(8192, 4096))
    row("nvme_rem_4096", P.rem_bytes(4096, 4096))
    row("nvme_rem_4097", P.rem_bytes(4097, 4096))
    row("nvme_rem_8192", P.rem_bytes(8192, 4096))
    # the last command reads the leftover and every other command reads
    # a full window. a port that uses `P.max_xfer` for the last command reads
    # PAST THE END OF THE BUFFER.
    row("nvme_cmd_bytes_c0", P.cmd_bytes(0, 1, 100, 4096))
    row("nvme_cmd_bytes_c1", P.cmd_bytes(1, 1, 100, 4096))
    row("nvme_cmd_bytes_c2", P.cmd_bytes(2, 2, 100, 4096))
    # the wave stride is `P.q.entries - 1`, not `P.q.entries`. one slot is
    # left free so the ring's full and empty states are distinguishable.
    row("nvme_wave_stride_64", P.wave_stride(64))
    row("nvme_wave_stride_1", P.wave_stride(1))
    brow("nvme_wave_stride_leaves_one", U32.is_eq(P.wave_stride(64), 63))
    # the slot and the command INDEX. the slot is modulo the entry count
    # AND THE COMMAND INDEX IS NOT.
    row("nvme_wave_slot_0_0", P.wave_slot(0, 0, 0, 64))
    row("nvme_wave_slot_0_62", P.wave_slot(0, 0, 62, 64))
    row("nvme_wave_slot_0_63", P.wave_slot(0, 0, 63, 64))
    row("nvme_wave_slot_1_0", P.wave_slot(0, 1, 0, 64))
    row("nvme_wave_slot_1_62", P.wave_slot(0, 1, 62, 64))
    row("nvme_wave_cmd_0_0", P.wave_cmd(0, 0, 64))
    row("nvme_wave_cmd_1_0", P.wave_cmd(1, 0, 64))
    row("nvme_wave_cmd_1_62", P.wave_cmd(1, 62, 64))
    # the command INDEX is the absolute one and it is what multiplies
    # into the lba, so it must not be taken modulo.
    brow("nvme_wave_cmd_not_mod", Bool.not(U32.is_eq(P.wave_cmd(1, 0, 64), 1)))
    # the prp table's base. sixteen bytes per page and the OFFSET is the
    # DESTINATION'S PAGE INDEX.
    row("nvme_prp_base_0", P.prp_base(4096, 0))
    row("nvme_prp_base_1page", P.prp_base(4096, 4096))
    row("nvme_prp_base_2page", P.prp_base(4096, 8192))
    row("nvme_prp_page_off_3", P.prp_page_off(3))
    # the lba. the step is in blocks and not in bytes, so a port that
    # shifts bytes gets a lba a hundred and twenty eight times too big.
    row("nvme_lba0_0", P.lba0(0, 9))
    row("nvme_lba0_512", P.lba0(512, 9))
    row("nvme_lba_step_4096_9", P.lba_step(4096, 9))
    row("nvme_lba_step_4096_12", P.lba_step(4096, 12))
    row("nvme_lba_of_0", P.lba_of(0, 0, 4096, 9))
    row("nvme_lba_of_1", P.lba_of(0, 1, 4096, 9))
    row("nvme_lba_of_3", P.lba_of(0, 3, 4096, 9))
    # the page count of a command. ceildiv, so a command of 0x1001 bytes
    # IS TWO PAGES.
    row("nvme_cmd_pages_1", P.cmd_pages(1))
    row("nvme_cmd_pages_4096", P.cmd_pages(4096))
    row("nvme_cmd_pages_4097", P.cmd_pages(4097))
    row("nvme_cmd_pages_8192", P.cmd_pages(8192))
    # the third prp entry appears only when there are exactly two pages.
    # one page gets one entry, three pages get two, and exactly two gets
    # three -- so a port that writes `>= 2` gets the three-page case wrong.
    brow("nvme_third_prp_1page", Bool.not(P.has_third_prp(4096)))
    brow("nvme_third_prp_2page", P.has_third_prp(8192))
    brow("nvme_third_prp_3page", Bool.not(P.has_third_prp(12288)))
    brow("nvme_third_prp_0page", Bool.not(P.has_third_prp(0)))
    # the completion. the `+ 12` is the phase field's OFFSET inside the
    # cqe and the phase is bit 16 of the WORD at that OFFSET.
    row("nvme_cqe_phase_off", P.cqe_phase_off())
    row("nvme_cqe_phase_0", P.cqe_phase(0))
    row("nvme_cqe_phase_1", P.cqe_phase(65536))
    row("nvme_cqe_phase_2", P.cqe_phase(131072))
    # the status is above bit 17 and the ERROR message prints `dw3 >> 17`.
    row("nvme_cqe_status_0", P.cqe_status(0))
    row("nvme_cqe_status_1", P.cqe_status(131072))
    row("nvme_cqe_status_255", P.cqe_status(33554432))
    brow("nvme_cqe_ok", Bool.not(P.cqe_failed(0)))
    brow("nvme_cqe_failed", P.cqe_failed(131072))
    # the completion's slot is the last slot of the wave and the
    # DOORBELL'S VALUE IS THE SLOT AFTER IT.
    row("nvme_cqe_slot_0_0", P.cqe_slot(0, 0, 1, 64))
    row("nvme_cqe_slot_0_63", P.cqe_slot(0, 0, 63, 64))
    row("nvme_db_end_0_0", P.db_end(0, 0, 1, 64))
    row("nvme_db_end_0_63", P.db_end(0, 0, 63, 64))
    # the doorbell is the next slot to fill, not the last slot filled --
    # a port that rings the last slot hangs.
    brow("nvme_db_is_next_slot", Bool.not(U32.is_eq(P.db_end(0, 0, 63, 64), P.cqe_slot(0, 0, 63, 64))))
    # the waves. the last wave is `full % (entries - 1)` plus one IF there
    # is a leftover, and a read with no leftover has no extra wave.
    row("nvme_waves_0", P.wave_count(0, 64))
    row("nvme_waves_63", P.wave_count(63, 64))
    row("nvme_waves_64", P.wave_count(64, 64))
    row("nvme_waves_126", P.wave_count(126, 64))
    row("nvme_last_0", P.last_wave_size(0, 0, 64))
    row("nvme_last_63", P.last_wave_size(63, 0, 64))
    row("nvme_last_64", P.last_wave_size(64, 0, 64))
    row("nvme_last_64_rem", P.last_wave_size(64, 100, 64))
    # the `if last` is not cosmetic: a read of exactly `full` commands
    # has a last wave but no extra wave, and a read with nothing at all has
    # NO LAST WAVE.
    row("nvme_last_is_zero", Bool.to_u32(U32.is_zero(P.last_wave_size(0, 0, 64))))
    # THE LOOP. A LOOP OF ZERO ITERATIONS IS NO INSTRUCTIONS AT ALL.
    row("nvme_loop_0", P.loop_n(0))
    row("nvme_loop_1", P.loop_n(1))
    row("nvme_loop_63", P.loop_n(63))

# --- 8: the allocator and the interface ------------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # AN NVMe BUFFER IS NOT CACHED. `lru = False` AND EVERY `_alloc` IS A
    # FRESH DEVICE ALLOCATION.
    brow("nvme_lru_off", Bool.not(P.ALLOCATOR_LRU()))
    # the allocation is a zero handle and the real one happens in `_map`.
    row("nvme_alloc_handle", 0)
    # the preconditions on a read. three rules and each is a different kind.
    # THE DESTINATION MUST BE PAGE-ALIGNED.
    brow("nvme_align_page_0", P.aligned_page(0))
    brow("nvme_align_page_4096", P.aligned_page(4096))
    brow("nvme_align_page_1", Bool.not(P.aligned_page(1)))
    # the source must be block-aligned. the `|` is not `+` -- the or of
    # the OFFSET and the SIZE is zero modulo the block SIZE only IF both
    # ARE.
    brow("nvme_align_block_0", P.aligned_block(0, 4096, 12))
    brow("nvme_align_block_4096", P.aligned_block(4096, 4096, 12))
    brow("nvme_align_block_1", Bool.not(P.aligned_block(1, 4096, 12)))
    # a source that straddles a block boundary: the OFFSET is aligned and
    # the SIZE is not, and the or catches it WHERE a `+` would not.
    brow("nvme_align_block_straddle", Bool.not(P.aligned_block(4096, 8192, 12)))
    # THE READ MUST FIT.
    brow("nvme_fits_ok", P.fits_device(0, 4096, 8192))
    brow("nvme_fits_over", Bool.not(P.fits_device(4096, 8192, 8192)))
    # the device. there is no renderer -- an NVMe device executes no
    # KERNELS -- AND `synchronize` IS A NO-OP.
    row("nvme_renderers", P.dev.renderers())
    brow("nvme_synchronize_noop", P.dev.synchronize_is_noop())
    row("nvme_iface_count", P.dev.iface_count())
    slrow("nvme_iface_names", P.dev.iface_names())
    # the in-use assertion. both the mounted test and the holders test
    # must be empty, and a port that checked one would take a drive out from
    # UNDER THE FILESYSTEM.
    brow("nvme_in_use_free", P.in_use(False{}, False{}))
    brow("nvme_in_use_mounted", P.in_use(True{}, False{}))
    brow("nvme_in_use_holders", P.in_use(False{}, True{}))
    brow("nvme_in_use_both", P.in_use(True{}, True{}))
    # the dispatch. the absence is an answer -- a body with no NVMe call
    # is left alone, and a port that always rewrote would break every other
    # BACKEND.
    brow("nvme_submit_none", Bool.not(P.submit_applies(0)))
    brow("nvme_submit_some", P.submit_applies(1))
    brow("nvme_device_is_nvme", P.is_nvme_device("NVME:0"))
    brow("nvme_device_is_not_nvme", Bool.not(P.is_nvme_device("CUDA:0")))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_sizes()
    b : Unit <- t_doorbell()
    c : Unit <- t_cmd()
    d : Unit <- t_prp()
    e : Unit <- t_ident()
    f : Unit <- t_create()
    g : Unit <- t_copy()
    h : Unit <- t_alloc()
    IO.print("nvme-done=1")

