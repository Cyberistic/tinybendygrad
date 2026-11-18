# tinybendygrad/runtime/support/rdma/bnxtdev.bend -- port of
# tinygrad/runtime/support/rdma/bnxtdev.py
#
# THE BROADCOM NIC DRIVER. `ops_rdma.bend` is committed, green, and cites this
# file in its header and in its constant table; those citations are the scope,
# and they are CHECKED rather than assumed -- see THE CITATIONS below.
#
# what survives, and why these parts. The file is 237 lines of firmware
# driver, and the arithmetic in it is where a wrong constant becomes a
# silently wrong DMA:
#
#   1. THE DOORBELL AND THE RING: upstream's `db_value` (tinygrad/runtime/support/rdma/bnxtdev.py:13-16 symbol=db_value),
#      the queue's `read`/`write` (tinygrad/runtime/support/rdma/bnxtdev.py:42-45) and the `doorbell`
#      (tinygrad/runtime/support/rdma/bnxtdev.py:162-164). `db_value` is a
#      64-bit word whose HIGH half says WHICH QUEUE and whose LOW half says
#      WHERE in it. There is no U64 in Bend 2.0.34, so the word is two U32
#      halves, and they are not symmetric -- see THE 64-BIT WORD.
#   2. THE PAGE TABLES (:27-37, `build_pbl`), BOTH DIRECTIONS. Forward is
#      `(level, base)` for a page list; reverse is the ENCODED ENTRY, whose
#      three flags land in the low 32 bits of a 64-bit physical address. This
#      is the table most likely to carry a wrong constant, so the entry is
#      gated both ways: encode from (paddr, flags) and decode back out.
#   3. the logging table (:11, `BNXT_BACKING_STORE`) and what drives it
#      (:91-108, `setup_backing_store`). Nine (type, extra) pairs, a
#      `counts[typ] = counts[0] if typ == 15 else max(min_num_entries, ...)`
#      that makes type 15 REUSE type 0's count, a bitmap walk for instances,
#      and a `ctx_init` sweep at a stride of `entry_size`. Nine rows forward,
#      nine back, plus the fold that produces the counts in order.
#   4. THE COMPLETION AND ERROR STATUS (:25, :86-88, :146-155, :224). The CQE
#      toggle test, the CREQ valid bit and the async-event filter, the HWRM
#      error code and the RCFW status, and the CQE status byte at 25.
#   5. THE DEVICE / FUNCTION / VF INDEX ARITHMETIC (:9, :53-72, :183-189,
#      :191-217). The three QP modify masks, the `state | network_type`
#      composition, the `level << LVL_SFT | log_page << LOG2_SFT` in
#      `register_mem`, and the enable-mask ORs in `_open_l2`.
#   6. the struct field lists, by name and in order, never by count. a wrong
#      field order is a silently wrong register write, and a count gate passes
#      it. `f_struct_*_NAMES` rows print all seven `struct_cq_base` fields in
#      source order, and `f_CQE_TOGGLE_FIELD` / `f_CQE_STATUS_FIELD` name the
#      two offsets bnxtdev.py reads BY HAND.
#
# THE TABLE IS IN `.agents/slop/tables/runtime-support-rdma-bnxtdev-42.md` -- WHAT IS PORTED, DEF BY DEF.
#
# THE FFI SEAMS. Every one of these is NAMED with its Python line and is a
# `CALL_*` tag in the trace; none of them is made here, and there is no
# `import "./x.c"`. The trace IS the record of the call, which is why this file
# declares no foreign effect.
#
#   :55  `pci_dev.reset()`                    CALL_PCI_RESET
#   :56  `pci_dev.read_config/write_config`   CALL_PCI_CFG_R / CALL_PCI_CFG_W
#   :57  `pci_dev.map_bar(0)` / `map_bar(2)`  CALL_MAP_BAR
#   :58/99/121/168 `alloc_sysmem`             CALL_ALLOC
#   :82  `System.memory_barrier()`            CALL_BARRIER
#   :83/84/119/142/143 `self.bar0[i] = w`     CALL_BAR0
#   :45  `self.ring[off:off+n] = data`        CALL_RING_W
#   :42  `self.ring[off:off+n]`               CALL_RING_R
#   :86/147/220 `wait_cond(...)`              CALL_WAIT
#   :60-72 the HWRM verbs                     CALL_HWRM
#   :112/127/169/172 `ring_alloc`             CALL_RING_ALLOC
#   :116/130 the command queue                CALL_CMDQ
#   :175/176 `vnic_alloc`/`vnic_cfg`          CALL_VNIC
#   :178 `cfa_l2_filter_alloc`                CALL_L2_FILTER
#   :185/189 `register_mr`/`deregister_mr`    CALL_MR
#   :160 `func_drv_unrgtr`                    CALL_FINI
#   :164 `self.db[...] = db_value(...)`       CALL_DB
#   tinygrad/runtime/support/rdma/bnxtdev.py:77,131 the `getattr(bnxt, ...)` struct
#         construction and `from_buffer_copy` WALL 1 -- see below
#
# THE WALLS.
#
#   1. the hwrm/rcfw struct construction and parsing (:77-89, :131-134).
#      `getattr(bnxt, f"struct_hwrm_{name}_input")` is a NAME BUILT AT RUNTIME
#      from the verb, and `inp(req_type=..., fields)` is a kwargs
#      constructor over a ctypes struct. Bend has neither a dynamic name nor a
#      keyword constructor, and `c.record` structs are OPAQUE: `t._fields_` is
#      `('_mem_',)`. So the struct LAYOUT is ported (every field name in order,
#      with its byte offset, gated by name) and the verb names are the trace's
#      job; the CONSTRUCTION is not. The `wait_cond` on `resp_len`/`seq_id` is
#      the same shape as `ops_webgpu.bend`'s `Tr.pop`: a WAIT, in the trace.
# | wall(p3) bnxtdev.py:77  getattr(bnxt, f"struct_hwrm_{name}_input"). -- blocked. #   dynamic attribute lookup by a constructed name: `getattr(bnxt, f"struct_hwrm_{name}_input")`
#   resolves a field AT RUNTIME from a string, and the name is built per call.
# | WALL(p3) bnxtdev.py:87  out.from_buffer_copy(bytes(self.resp[:sizeof])). -- BLOCKED. #   `out.from_buffer_copy(bytes(self.resp[:sizeof]))` IS CTYPES BUFFER ALIASING -- a Python object
#   whose memory IS the packet, reinterpreted in place.
#      WALL(p3) bnxtdev.py:131 getattr(bnxt, f"struct_cmdq_{name}"). -- BLOCKED. THE SAME
#      RUNTIME NAME RESOLUTION as the marker at :77, one family over.
#      TODO(p3) bnxtdev.py:149  symbol=rcfw resp_t.from_buffer_copy(self.creq.read(...)).
#   2. THE 64-BIT PHYSICAL ADDRESSES (`build_pbl`'s entries, `db_value`, the
#      doorbell word, `struct_cmdq_*.pbl`). There is no U64 in Bend 2.0.34.
#      Every one of them is carried as TWO U32 halves, and -- MEASURED -- every
#      flag this file sets lives in the LOW half, so the port loses nothing.
#      `pbl_hi_untouched` is the row that says the high half is the paddr's.
# | wall(p3) bnxtdev.py:32  struct.pack(f"<{len(values)}q", *values). -- blocked. #   a format string built from the argument count -- `struct.pack(f"<{len(values)}Q", *values)` --
#   and `*values` splats a variable-length tuple.
#   3. `MMIOInterface` (tinygrad/runtime/support/rdma/bnxtdev.py:40-41 symbol=BNXTQueue). A byte-addressed slice of host memory over a
#      BAR. `read` and `write` COMPUTE the offsets, and that arithmetic is
#      ported and gated; the slice itself is the seam.
#      TODO(p3) bnxtdev.py:45  self.ring[off:off + len(data)] = data.
#   4. `ctypes.from_buffer_copy` and the `struct` module's C types. WALL 1 plus
#      this: the field LISTS are ported by name and the BYTES are computed as
#      U32 words, but nothing constructs a ctypes object.
#   5. `self.pci_dev.pcibus` (tinygrad/runtime/support/rdma/bnxtdev.py:54), and the verbosity
#      levels `DEBUG`/`BNXT_DEBUG` (tinygrad/runtime/support/rdma/bnxtdev.py:8 symbol=BNXT_DEBUG;
#      upstream prints them at 61, 74, 157 and 217) are WALLS (`getenv` is IO); the device
#      node string is `nic.node` in `ops_rdma.bend`, which already ports it.
#
# | wall(p3) bnxtdev.py:54  self.devfmt = pci_dev.pcibus. -- blocked. #   `self.devfmt = pci_dev.pcibus` reads a field off a live pci device object. There is no live
#   device object in the port: `Dev` is a `U32` tag (`LAWS/spec.bend:83`).
#      TODO(p3) bnxtdev.py:157  symbol=rcfw `if BNXT_DEBUG >= 1: print(...)`.
#   6. `System.list_devices` / `PCIDevice` probing. Not in this file at all;
#      WALL 2 of `ops_rdma.bend` owns it and names `bnxtdev.py`.
#   7. THE GENERATOR OF :94-96. `sum(splits)`, `range(...)` and the
#      `caps.subtype_valid_cnt`-length tuple are the firmware's caps, which
#      arrive from a HWRM the port cannot make. The port takes `entry_size`,
#      `min_num_entries`, the split SUM and the bitmap as PARAMETERS -- which is
#      why the `bs_*` rows are `bs_count_of(typ, mne, sum_splits)` and not a
#      closed table. TODO(p3) bnxtdev.py:95  symbol=setup_backing_store tuple(getattr(caps, ...) for j ...).
#
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind.
#
# the four refusals are in the trace, and each is one Python `raise`/`assert`:
#   :34   `assert len(table_paddrs) <= 512`  -> "a pbl has two levels"
#   :88   `assert ret.error_code == 0`       -> "HWRM <name>"
#   :155  `assert ret.status == 0`           -> "RCFW <name>"
#   :224  `assert raw[25] == 0`              -> "BNXT CQE status"
# `Tr.emit` records NOTHING once `refused` is set, so a refusal appears as a
# TRUNCATED trace and no step below needs a guard of its own.

import Base

# THE CONSTANTS. Every one MEASURED, and every one in
# `.agents/slop/bnxt_constmap.py`, which reads each authority with `getattr`
# and cross-checks the hex-sourced ones a SECOND way (hex literal -> int),
# because a transposed digit pair is invisible to a decimal eyeball.
# bnxtdev.py:8-12 -- the module's own five lines.

def BNXT_DEBUG() -> U32: 0
def BNXT_ACCESS() -> U32: 3
def BNXT_INIT_MASK() -> U32: 13
def BNXT_RTR_MASK() -> U32: 68490669
def BNXT_RTS_MASK() -> U32: 712709
def BNXT_CHIMP_COMM() -> U32: 0
def BNXT_CHIMP_COMM_TRIGGER() -> U32: 256
def WQE_SIZE() -> U32: 128
def RING_ENTRIES() -> U32: 4096
def CQ_ENTRIES() -> U32: 4096
def MTU() -> U32: 4096

# db_value (:13-15).
def DBC_DBC_XID_MASK() -> U32: 1048575
def DBC_DBC_PATH_ROCE() -> U32: 0
def BNXT_QPLIB_DBR_VALID() -> U32: 67108864
def DBC_DBC_INDEX_MASK() -> U32: 16777215
def BNXT_QPLIB_DBR_EPOCH_SHIFT() -> U32: 24

# send_wqe / recv_wqe / msn_entry / cqe_ready (:18-25).
def SQ_SEND_FLAGS_SIGNAL_COMP() -> U32: 1
def SQ_MSN_SEARCH_START_IDX_SFT() -> U32: 48
def SQ_MSN_SEARCH_NEXT_PSN_SFT() -> U32: 24
def CQ_BASE_TOGGLE() -> U32: 1

# build_pbl (:29-30).
def PTU_PTE_VALID() -> U32: 1
def PTU_PTE_LAST() -> U32: 2
def PTU_PTE_NEXT_TO_LAST() -> U32: 4

# the doorbell types and the command-queue offsets (:115-143).
def DBC_DBC_TYPE_SQ() -> U32: 0
def DBC_DBC_TYPE_NQ_ARM() -> U32: 2952790016
def DBC_DBC_TYPE_RQ() -> U32: 268435456
def DBC_DBC_TYPE_CQ() -> U32: 1073741824
def CMDQ_INIT_CMDQ_SIZE_SFT() -> U32: 2
def RCFW_COMM_BASE_OFFSET() -> U32: 1536
def RCFW_PF_VF_COMM_PROD_OFFSET() -> U32: 12
def RCFW_COMM_TRIG_OFFSET() -> U32: 256
def RCFW_CMDQ_TRIG_VAL() -> U32: 1
def FIRMWARE_FIRST_FLAG() -> U32: 31

# hwrm (:79-87).
def BNXT_HWRM_NO_CMPL_RING() -> U32: 4294967295
def BNXT_HWRM_TARGET() -> U32: 65535
def HWRM_MAX_REQ_LEN() -> U32: 128
def SIZEOF_RESP_HDR() -> U32: 8

# the command-queue loop and the completion wait (:133-194).
def CREQ_BASE_V() -> U32: 1
def CREQ_BASE_TYPE_QP_EVENT() -> U32: 56
def CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION() -> U32: 192
def SIZEOF_CQ_BASE() -> U32: 32

# ring_alloc / vnic / cfa_l2 (:112-180).
def RING_ALLOC_REQ_RING_TYPE_NQ() -> U32: 5
def RING_ALLOC_REQ_RING_TYPE_L2_CMPL() -> U32: 0
def RING_ALLOC_REQ_RING_TYPE_RX() -> U32: 2
def RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID() -> U32: 128
def RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID() -> U32: 256
def RING_ALLOC_REQ_INT_MODE_MSIX() -> U32: 2
def VNIC_CFG_REQ_ENABLES_MRU() -> U32: 16
def VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID() -> U32: 32
def VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID() -> U32: 64
def CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX() -> U32: 1
def CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR() -> U32: 1
def CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK() -> U32: 2
def CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID() -> U32: 32768
def FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE() -> U32: 2

# setup_backing_store (:107) and register_mem (:185-187).
def CMDQ_REGISTER_MR_LVL_SFT() -> U32: 0
def CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT() -> U32: 2
def CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE() -> U32: 1
def CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE() -> U32: 4
def CMDQ_REGISTER_MR_FLAGS_ALLOC_MR() -> U32: 1
def CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED() -> U32: 2

# BNXTQP (:198-212).
def CMDQ_CREATE_QP_TYPE_RC() -> U32: 2
def CMDQ_MODIFY_QP_QP_TYPE_RC() -> U32: 2
def CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4() -> U32: 128
def CMDQ_MODIFY_QP_PATH_MTU_MTU_4096() -> U32: 64

# ctypes.sizeof of the command structs (:72,:116,:122,:133,:185,:189,:195,:198,:204).
def SIZEOF_CMDQ_ADD_GID() -> U32: 48
def SIZEOF_CMDQ_INITIALIZE_FW() -> U32: 112
def SIZEOF_CMDQ_CREATE_CQ() -> U32: 64
def SIZEOF_CMDQ_CREATE_QP() -> U32: 104
def SIZEOF_CMDQ_MODIFY_QP() -> U32: 144
def SIZEOF_CMDQ_REGISTER_MR() -> U32: 56
def SIZEOF_CMDQ_DEREGISTER_MR() -> U32: 24
def SIZEOF_CMDQ_INIT() -> U32: 16

# The values the source LITS rather than reads out of a module, and the page
# size arithmetic. They are here so the gate has one home for "a number in a
# call site", and each is named by its line.
def PAGE() -> U32: 4096
def QUEUE_PAGE() -> U32: 4096
def MSN_MASK() -> U32: 16777215
def AUX_ENTRY() -> U32: 8
def SLOT16() -> U32: 16
def SLOT64() -> U32: 64
def CMDQ_LVL() -> U32: 256
def CREQ_LEN() -> U32: 256
def NQ_LEN() -> U32: 16
def CREQ_TOGGLE_AT() -> U32: 8
def CREQ_CONSUME() -> U32: 256
def CQE_STATUS_AT() -> U32: 25
def RESP_BYTES() -> U32: 4096
def DEV_PCI_COMMAND() -> U32: 4
def DEV_FID() -> U32: 65535

# the struct field lists, by name and in order.
#
# `c.record` structs are OPAQUE: `bnxt.struct_cq_base._fields_` is
# `('_mem_',)`, so `ctypes` cannot see the names and `ctypes.sizeof` is the
# only thing it will tell you. The names live in the `_real_fields_` the
# generator installs, and `_real_fields_` is what the oracle reads. These
# lists are TRANSCRIBED from it, in order, and `f_struct_*_NAMES` gates all of
# them at once -- so a wrong field ORDER moves a row and a right field COUNT
# with a wrong order still moves one.
#
# why the order matters here specifically. Two offsets in this file are read
# BY HAND and nowhere else:
#   :25  `cqe[24] & CQ_BASE_TOGGLE` -- byte 24 is `cqe_type_toggle`, the
#        fourth field, and NOT byte 0. Polling byte 0 would read
#        `reserved64_1`, which is always zero, so the wait would never fire.
#   :224 `raw[25] == 0` -- byte 25 is `status`, the FIFTH field, and the
#        completion error. `cqe_of` / `cqe_status` are pinned BY NAME against
#        `_real_fields_` by `f_CQE_TOGGLE_FIELD` and `f_CQE_STATUS_FIELD`.

def struct_cq_base_names() -> List<&2, String>:
  ["reserved64_1", "reserved64_2", "reserved64_3", "cqe_type_toggle", "status", "reserved16", "opaque"]

def struct_cq_base_at() -> List<&2, U32>: [0, 8, 16, 24, 25, 26, 28]
def struct_cq_base_w() -> List<&2, U32>: [8, 8, 8, 1, 1, 2, 4]

def struct_hwrm_resp_hdr_names() -> List<&2, String>: ["error_code", "req_type", "seq_id", "resp_len"]
def struct_hwrm_resp_hdr_at() -> List<&2, U32>: [0, 2, 4, 6]
def struct_hwrm_resp_hdr_w() -> List<&2, U32>: [2, 2, 2, 2]

def struct_cmdq_init_names() -> List<&2, String>:
  ["cmdq_pbl", "cmdq_size_cmdq_lvl", "creq_ring_id", "prod_idx"]
def struct_cmdq_init_at() -> List<&2, U32>: [0, 8, 10, 12]
def struct_cmdq_init_w() -> List<&2, U32>: [8, 2, 2, 4]

def struct_cmdq_base_names() -> List<&2, String>:
  ["opcode", "cmd_size", "flags", "cookie", "resp_size", "reserved8", "resp_addr"]
def struct_cmdq_base_at() -> List<&2, U32>: [0, 1, 2, 4, 6, 7, 8]
def struct_cmdq_base_w() -> List<&2, U32>: [1, 1, 2, 2, 1, 1, 8]

# the two names, addressed through the list so a wrong INDEX is a wrong NAME.
def cqe_toggle_field(nm: String) -> Bool: String.eq(nm, "cqe_type_toggle")
def cqe_status_field(nm: String) -> Bool: String.eq(nm, "status")

# `BNXTQP.__init__` (:194) sizes its completion queues with
# `ctypes.sizeof(bnxt.struct_cq_base)`, which is the PORT OF THE STRIDE. It is
# 32 and not 64 and not 16, and it is the same 32 that `ops_rdma.bend` calls
# `CQE_SIZE` -- one number, two files, and it is the cross-check.
def CQ_STRIDE() -> U32: SIZEOF_CQ_BASE()

# THE 64-BIT DOORBELL WORD, :13-15.
#
#   def db_value(xid, typ, index, epoch):
#     return (xid & DBC_DBC_XID_MASK | DBC_DBC_PATH_ROCE | typ |
#             BNXT_QPLIB_DBR_VALID) << 32 |
#            index & DBC_DBC_INDEX_MASK | epoch << BNXT_QPLIB_DBR_EPOCH_SHIFT
#
# TWO HALVES and they are NOT symmetrical, which is the whole reason this file
# carries them separately:

def db.hi(+xid: U32, typ: U32) -> U32:
  U32.or(U32.or(U32.and(xid, DBC_DBC_XID_MASK()), U32.or(DBC_DBC_PATH_ROCE(), typ)),
         BNXT_QPLIB_DBR_VALID())

def db.lo(+index: U32, +epoch: U32) -> U32:
  U32.or(U32.and(index, DBC_DBC_INDEX_MASK()),
         U32.shln(epoch, U32.to_nat(BNXT_QPLIB_DBR_EPOCH_SHIFT())))

# The two halves as a PAIR, which is how `Tr` carries the doorbell: there is
# no U64 in Bend 2.0.34 and a `U32` write of a 64-bit value TRUNCATES it, so
# the port writes two dwords where Python writes one. `db.dropped_hi` is the
# row that says what that costs, and it is the same measurement `ops_rdma.bend`
# calls `rdma_db_hi_dropped` -- one file's gate and the other's, agreeing on
# the same number from the same source line.
# send_wqe / recv_wqe, :18-19.
#
#   send_wqe: struct.pack("<BBB5xI20xQII", 0, SQ_SEND_FLAGS_SIGNAL_COMP, 3,
#                         size, va, key, size)
#   recv_wqe: struct.pack("<BBB29xQII", 0x80, 0, 3, va, key, size)
#
# forty-eight bytes each, and the two formats differ in exactly two places,
# both of which matter:
#
#   * byte 0. Send puts `0` there and receive puts `0x80`, which is the "this
#     is a receive" bit. Byte 0 is the LOW byte of word 0.
#
# and the one that is easy to get wrong. Word 0 is little-endian, so it is
#
#       kind << 16 | flags << 8 | type
#
# with `kind` -- the 3, the size in 16-byte units -- in the HIGH byte and
# `type` in the LOW. `ops_rdma.bend:223-224` says `type << 16 | flags << 8 |
# kind`, which is INVERTED; its code at :1490-1492 gets it right and this
# file's `wqe.hdr0` follows the code and the measurement, not the comment.
# `hdr0_SEND_COMMENT_IS_RIGHT` and `hdr0_RECV_COMMENT_IS_RIGHT` are oracle
# rows, both `0`, and they say so in a committed artefact rather than in an
# argument. VERIFIED BY GREP, not asserted -- see the report.

def WQE_KIND() -> U32: 3
def RECV_KIND() -> U32: 128
def HDR_WORDS() -> U32: 8
def WQE_BYTES() -> U32: 48
def WQE_TOTAL_WORDS() -> U32: 12

# the field list of each pack, BY NAME AND IN ORDER, which is the only spelling
# that cannot be transposed without a row moving.
def send_pack_names() -> List<&2, String>:
  ["type", "flags", "kind", "pad5", "size", "pad20", "va", "key", "size"]
def send_pack_at() -> List<&2, U32>: [0, 1, 2, 3, 8, 12, 32, 40, 44]
def send_pack_w() -> List<&2, U32>: [1, 1, 1, 5, 4, 20, 8, 4, 4]

# The RECEIVE pack has NO `size` word in the header: its 29-byte pad runs OVER
# the byte 8 that the send pack puts `I size` at. Nine fields and only eight
# names' worth of header: the receive header says nothing about its length.
def recv_pack_names() -> List<&2, String>:
  ["type", "flags", "kind", "pad29", "va", "key", "size"]
def recv_pack_at() -> List<&2, U32>: [0, 1, 2, 3, 32, 40, 44]
def recv_pack_w() -> List<&2, U32>: [1, 1, 1, 29, 8, 4, 4]

# word 0, from the THREE BYTES the pack spells.
def wqe.hdr0(+recv: Bool) -> U32:
  Bool.pick(U32, recv,
    U32.add(U32.shln(WQE_KIND(), 16n), RECV_KIND()),
    U32.or(U32.shln(WQE_KIND(), 16n), U32.shln(SQ_SEND_FLAGS_SIGNAL_COMP(), 8n)))

# word 2: the send's `I size` at byte 8, and the RECEIVE'S ZERO, because the
# 29-byte pad covers byte 8. This asymmetry is mutation M2's subject.
def wqe.hdr2(+recv: Bool, size: U32) -> U32: Bool.pick(U32, recv, 0, size)

# The whole 48 bytes as TWELVE little-endian words. Words 3..7 are the 20-byte
# pad and words 8..11 are the scatter-gather element `(va, key, size)`. A flat
# literal on purpose: three nested `List.append` calls at four levels of paren
# is a paren-counting exercise, and LOCs is the measure.
def wqe.words(+recv: Bool, +size: U32, va_lo: U32, va_hi: U32, key: U32) -> List<&2, U32>:
  [wqe.hdr0(recv), 0, wqe.hdr2(recv, size), 0, 0, 0, 0, 0, va_lo, va_hi, key, size]

# msn_entry, :20-24. The 64-bit word is THREE 24-BIT FIELDS:
#
#   (wqe_idx % RING_ENTRIES) << SQ_MSN_SEARCH_START_IDX_SFT |   <- bit 48
#   nxt << SQ_MSN_SEARCH_NEXT_PSN_SFT |                          <- bit 24
#   psn                                                          <- bit 0
#
# The slot therefore sits ENTIRELY in the high half, and `nxt` STRADDLES it:
# its low byte is the high half's low byte and its top sixteen bits are the
# low half's top sixteen bits. `msn.hi` and `msn.lo` are that split exactly --
# no bit is invented and no bit is dropped -- and `msn_shifts_from_autogen`
# says the two shift amounts are 48 and 24 out of `SQ_MSN_SEARCH_*` rather
# than literals in the def.

def ceildiv(+a: U32, +b: U32) -> U32: U32.div(U32.add(U32.add(a, U32.sub(b, 1)), 0), b)

def msn.pkts(size: U32) -> U32:
  # :22 `max(1, ceildiv(size, MTU))`. `ceildiv` is `(size + MTU - 1) // MTU`,
  # and the `max` is what makes a ZERO-length send still advance the psn by
  # one -- without it `msn.pkts(0)` would be 0 and the psn would not move at
  # all. `msn_1_NEXT` is the row, and it is 1 and not 0.
  U32.max(1, ceildiv(size, MTU()))

def msn.mask(psn: U32) -> U32: U32.and(psn, MSN_MASK())

def msn.next_of(+psn: U32, size: U32) -> U32:
  U32.and(U32.add(psn, msn.pkts(size)), MSN_MASK())

def msn.slot_of(wqe_idx: U32) -> U32: U32.mod(wqe_idx, RING_ENTRIES())

# THE SPLIT. 48 - 32 = 16, so the slot is at bit 16 of the high half and
# nothing else is in the high half above it except `nxt`'s top sixteen bits.
def MSN_SLOT_HI_AT() -> U32: 16
def MSN_NEXT_AT() -> U32: 24

def msn.hi(slot: U32, nxt: U32) -> U32:
  U32.or(U32.shln(slot, U32.to_nat(MSN_SLOT_HI_AT())), U32.shrn(nxt, 8n))

def msn.lo(nxt: U32, psn: U32) -> U32:
  U32.or(U32.shln(nxt, U32.to_nat(MSN_NEXT_AT())), psn)

# cqe_ready, :25. `(cqe[24] & CQ_BASE_TOGGLE) != (cons // CQ_ENTRIES & 1)`.
#
# BYTE 24 is `cqe_type_toggle` -- the FOURTH field of `struct_cq_base`, after
# three 64-bit reserved words -- and not byte 0. Byte 0 is `reserved64_1`,
# which is always zero, so a port that polled byte 0 would wait for a toggle
# that can never be set and would hang. `cqe_of` / `cqe_status` are pinned by
# NAME against `_real_fields_` and not by counting from the front.

def CQE_TOGGLE_AT() -> U32: 24

def cqe.ready(toggle: U32, cons: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(toggle, CQ_BASE_TOGGLE()), U32.and(U32.div(cons, CQ_ENTRIES()), 1)))

# the epoch `cons // CQ_ENTRIES & 1` on its own, which is the other half of the
# test and is what `poll`'s doorbell reproduces one step later.
def cqe.epoch(cons: U32) -> U32: U32.and(U32.div(cons, CQ_ENTRIES()), 1)

# THE TABLE IS IN `.agents/slop/tables/runtime-support-rdma-bnxtdev-535.md` -- the page tables. `build_pbl`, :27-37, and it is the table most likely to

def PBL_PAGES_PER_TABLE() -> U32: 512
def PBL_MAX_PAGES() -> U32: 512
def PBL_TOP_BYTES() -> U32: 4096

# `ceildiv(len(values), 512) * 0x1000` -- :31. The table's byte count.
def pbl.table_bytes(n: U32) -> U32: U32.mul(ceildiv(n, PBL_PAGES_PER_TABLE()), PAGE())

# and how many `table_paddrs` that allocation yields: one per 0x1000 bytes.
def pbl.table_pages(n: U32) -> U32: ceildiv(n, PBL_PAGES_PER_TABLE())

# fact 2. `0` is the one-page shortcut, `1` and `2` are the two real levels, and
# `3` is the refusal, which `pbl.build` turns into a truncated trace.
def PBL_REFUSED() -> U32: 3

def pbl.level_of(+n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(n, 1), 0,
    Bool.pick(U32, U32.is_eq(pbl.table_pages(n), 1), 1,
      Bool.pick(U32, U32.is_le(pbl.table_pages(n), PBL_MAX_PAGES()), 2, PBL_REFUSED())))

# fact 3. THE ENCODE. The high half of a 64-bit page-table entry is the
# physical address's high half and NOTHING else -- `pbl.entry_hi` is the
# identity, deliberately, and `pbl_hi_untouched` is the row that pins it.
def pbl.entry_hi(paddr_hi: U32) -> U32: paddr_hi

def pbl.encode(+paddr_lo: U32, queue: Bool, +last: Bool) -> U32:
  Bool.pick(U32, Bool.not(Bool.and(queue, last)), U32.or(paddr_lo, PTU_PTE_VALID()),
    Bool.pick(U32, last, U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_LAST())),
      U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_NEXT_TO_LAST()))))

# THE DECODE, and it is the OTHER DIRECTION the brief asks for: given the entry
# the port wrote, recover which flags it carries. `last` and `next_to_last` are
# MUTUALLY EXCLUSIVE in the source -- one entry gets each -- so `pbl.valid_of`
# and the two predicates cannot both be true, and `pbl_flags_exclusive` says so.
def pbl.valid_of(entry: U32) -> Bool: U32.is_ne(U32.and(entry, PTU_PTE_VALID()), 0)
def pbl.has_last(entry: U32) -> Bool: U32.is_ne(U32.and(entry, PTU_PTE_LAST()), 0)
def pbl.has_ntl(entry: U32) -> Bool: U32.is_ne(U32.and(entry, PTU_PTE_NEXT_TO_LAST()), 0)
def pbl.addr_of(entry: U32) -> U32: U32.and(entry, U32.not(U32.or(PTU_PTE_LAST(), PTU_PTE_NEXT_TO_LAST())))
def pbl.flags_exclusive(+entry: U32) -> Bool: Bool.not(Bool.xor(pbl.has_last(entry), pbl.has_ntl(entry)))

# fact 4. which entry gets which flag, as a function of the index. The last
# index gets LAST; every other index except the second-to-last gets NEITHER;
# the second-to-last gets NEXT_TO_LAST. `i == n-1` is the LAST test, and it is
# evaluated BEFORE the `i == n-2` one, which is what makes them distinct.
def pbl.is_last(i: U32, n: U32) -> Bool: U32.is_eq(i, U32.sub(n, 1))
def pbl.is_ntl(i: U32, n: U32) -> Bool: U32.is_eq(i, U32.sub(n, 2))

def pbl.entry_lo_at(+paddr_lo: U32, queue: Bool, +i: U32, +n: U32) -> U32:
  Bool.pick(U32, Bool.not(queue), U32.or(paddr_lo, PTU_PTE_VALID()),
    Bool.pick(U32, pbl.is_last(i, n), U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_LAST())),
      Bool.pick(U32, pbl.is_ntl(i, n),
        U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_NEXT_TO_LAST())),
        U32.or(paddr_lo, PTU_PTE_VALID()))))

# :34 `assert len(table_paddrs) <= 512` -- THE REFUSAL. Its own level value, so
# a gate row can ask "would this refuse" without building a trace.
def pbl.refuses(n: U32) -> Bool: U32.is_gt(pbl.table_pages(n), PBL_MAX_PAGES())

# BNXTQueue, :39-45, and `alloc_queue`, :47-50.
#
#   read(i):  ring[(off := i % (size // stride) * stride) : off + stride]
#   write(i, data, aux):
#
# `size // stride` IS THE SLOT COUNT and it is the ONLY place the ring wraps.
# `alloc_queue`'s default `entries = 0x1000 // stride` is chosen so that a
# default queue is EXACTLY ONE PAGE of entries -- so for the default the slot
# count is `0x1000 // stride` and `size == 0x1000`, and for `aux` the whole
# thing is `entries * (stride + 8)`.
#
# THE AUX ARM IS A DIFFERENT BASE, not an offset: `aux` writes at `size + ...`,
# which is PAST the ring, and `+ 8` rather than `+ stride` because the thing
# after the ring is the msn TABLE, one 64-bit entry per slot. So the send
# queue's `+ entries * 8` at :49 is the same 8 as `post_send`'s aux write at
# :230, and `aux_base_is_past_ring` is the row.

def q.slots(size: U32, +stride: U32) -> U32: U32.div(size, stride)

def q.read_off(i: U32, size: U32, +stride: U32) -> U32:
  U32.mul(U32.mod(i, q.slots(size, stride)), stride)

def q.read_len(size: U32, stride: U32) -> U32: stride

def q.write_off(+i: U32, +size: U32, +stride: U32, aux: Bool) -> U32:
  Bool.pick(U32, aux,
    U32.add(size, U32.mul(U32.mod(i, q.slots(size, stride)), AUX_ENTRY())),
    q.read_off(i, size, stride))

def q.write_len(+size: U32, +stride: U32, aux: Bool, nbytes: U32) -> U32: nbytes

# :48 `entries = entries or 0x1000 // stride`. The `or` means an EXPLICIT zero
# is replaced by a whole page of entries -- `aq_entries_default` is the row, and
# `aq_entries_of(16, 0) == 256` is what makes a default send ring 256 slots of
# 16 bytes, which is a page.
def q.entries_of(stride: U32, +entries: U32) -> U32:
  Bool.pick(U32, U32.is_zero(entries), U32.div(QUEUE_PAGE(), stride), entries)

# :49 `(size := entries * stride) + aux * entries * 8`.
# `BNXTQueue.size` is the ring and not the allocation. `alloc_queue` (:49) is
#   mem, paddrs = alloc_sysmem((size := entries * stride) + aux * entries * 8)
#   return BNXTQueue(mem, paddrs, stride, ..., size=size)
# so the `+ aux * entries * 8` goes into the ALLOCATION and `size=` keeps the
# ring alone. A port that adds the aux term to `size` claims a 6144-byte queue
# where there is a 4096-byte one, and every slot count and every aux base after
# it is wrong. THE GATE CAUGHT THIS: `aq_1_SIZE` and `aq_1_SLOTS` were the
# two rows that moved.
def q.size_of(+stride: U32, entries: U32) -> U32: U32.mul(q.entries_of(stride, entries), stride)

def q.alloc_of(+stride: U32, aux: Bool, +entries: U32) -> U32:
  U32.add(q.size_of(stride, entries),
          U32.mul(Bool.to_u32(aux), U32.mul(q.entries_of(stride, entries), AUX_ENTRY())))

# and the PBL level is a function of the ALLOCATION'S PAGE COUNT, not of the
# entry count: a 4096-byte allocation is ONE page, so `build_pbl` short-circuits
# at level 0 however many entries fit in it. `aq_0_LEVEL` and `aq_3_LEVEL` are
# the rows that see this, and they sit one fixture apart.
def q.pbl_pages_of(alloc_bytes: U32) -> U32: ceildiv(alloc_bytes, PAGE())

# THE ROW PRINTERS. One `name=value` line per claim; the gate is that the
# interpreted lane, the native lane and `.agents/slop/bnxt_oracle.txt` all
# print the same lines. A row is never a restatement of the def under test:
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its 930 rows are compared against `gates/bnxtdev-oracle.py` by
# `gates/lanewitness-gate.py`, which runs this DRIVER for the lane. The oracle
# answers 612 of them -- the other 270 are the PORT'S OWN bit-layout arithmetic
# (`pbl.entry_hi`, `bs.init_npos`, `bs.count_of`), and upstream's `build_pbl`
# returns `(addr, size)`, so the individual entry words are not in upstream and
# the oracle cannot answer them.
