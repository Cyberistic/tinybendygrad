# tinybendygrad/runtime/support/rdma/bnxtdev.bend -- port of
# tinygrad/runtime/support/rdma/bnxtdev.py
#
# THE BROADCOM NIC DRIVER. `ops_rdma.bend` is committed, green, and cites this
# file in its header and in its constant table; those citations are the scope,
# and they are CHECKED rather than assumed -- see THE CITATIONS below.
#
# WHAT SURVIVES, AND WHY THESE PARTS. The file is 237 lines of firmware
# driver, and the arithmetic in it is where a wrong constant becomes a
# silently wrong DMA:
#
#   1. THE DOORBELL AND THE RING (:13-15, :42-45, :162-164). `db_value` is a
#      64-bit word whose HIGH half says WHICH QUEUE and whose LOW half says
#      WHERE in it. There is no U64 in Bend 2.0.34, so the word is two U32
#      halves, and they are not symmetric -- see THE 64-BIT WORD.
#   2. THE PAGE TABLES (:27-37, `build_pbl`), BOTH DIRECTIONS. Forward is
#      `(level, base)` for a page list; reverse is the ENCODED ENTRY, whose
#      three flags land in the low 32 bits of a 64-bit physical address. This
#      is the table most likely to carry a wrong constant, so the entry is
#      gated both ways: encode from (paddr, flags) and decode back out.
#   3. THE LOGGING TABLE (:11, `BNXT_BACKING_STORE`) AND WHAT DRIVES IT
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
#   6. THE STRUCT FIELD LISTS, BY NAME AND IN ORDER, never by count. A wrong
#      field order is a silently wrong register write, and a count gate passes
#      it. `f_struct_*_NAMES` rows print all seven `struct_cq_base` fields in
#      source order, and `f_CQE_TOGGLE_FIELD` / `f_CQE_STATUS_FIELD` name the
#      two offsets bnxtdev.py reads BY HAND.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. Line numbers are bnxtdev.py.
#
#   :8-12 the five constant lines   PORTED  every value, both directions
#   :11  `BNXT_BACKING_STORE`      PORTED  nine (type, extra) pairs, in order
#   :13  `db_value`                PORTED  `db.hi` / `db.lo`, and the whole
#                                              64-bit word as two halves
#   :18  `send_wqe`                PORTED  the 8 words, the pack format and
#                                              the field list by name
#   :19  `recv_wqe`                PORTED  the 7 words -- and the `I size` at
#                                              byte 8 that the receive pack's
#                                              29-byte pad runs OVER
#   :20  `msn_entry`               PORTED  `msn.of` / `msn.hi` / `msn.lo`
#   :22  `ceildiv(size, MTU)`      PORTED  `msn.pkts`
#   :24  the 48/24/24 msn word     PORTED  the same shift amount is MEASURED
#                                              from `SQ_MSN_SEARCH_START_IDX_SFT`
#   :25  `cqe_ready`               PORTED  `cqe.ready`, off `cqe_type_toggle`
#   :27  `build_pbl`               PORTED  `pbl.level_of` / `pbl.entry` /
#                                              `pbl.decode`, encode AND decode
#   :33  the one-paddr shortcut    PORTED  `pbl.level_of(1) == 0`
#   :34  `assert len <= 512`       PORTED  the REFUSAL, a truncated trace
#   :42  `BNXTQueue.read`          PORTED  `q.read_off`, `q.read_len`
#   :44  `BNXTQueue.write`         PORTED  `q.write_off` -- and the `aux`
#                                              arm, which is a DIFFERENT base
#   :48  `entries or 0x1000//stride` PORTED `aq.entries_of`
#   :49  `(size:=entries*stride) + aux*entries*8` PORTED `aq.size_of`
#   :91  `setup_backing_store`     PORTED  `bs.fold` and its three derivations
#   :96  `counts[typ] = ...`       PORTED  `bs.count_of`, incl. the type-15
#                                              REUSE of `counts[0]`
#   :98  the instance bitmap walk  PORTED  `bs.instances`
#   :99  `ceildiv(n*size, 0x1000)*0x1000` PORTED `bs.alloc_bytes`
#   :102 the `ctx_init` sweep       PORTED  `bs.init_npos` / `bs.init_stride`
#   :107 the ALL_DONE flags        PORTED  `bs.flags_of`
#   :53  `BNXTDev.__init__`        PORTED  `dev.init`, the ordered trace
#   :56  the PCI_COMMAND write     PORTED  `pci.master_enable`
#   :57  `map_bar(0,'I')/(2,'Q')`  PORTED  `BAR0` / `BAR2`
#   :60  `hwrm("ver_get")`         PORTED  a WAIT, in `hwrm`
#   :62  `hwrm("func_reset")`      PORTED  the sequence counter, `hwrm.seq_of`
#   :64  `int.from_bytes(mac)`     PORTED  `dev.mac_of`, `dev.port_of`
#   :66  `db_off = kb * 1024`      PORTED  `dev.db_off_of` -- and it is a
#                                              BYTE offset divided by 8 for
#                                              the 64-bit doorbell bar
#   :71  `local_gid`               PORTED  `dev.local_gid`
#   :72  `>4I` reversed, `>3H`     PORTED  `dev.gid_words` / `dev.src_mac`
#   :76  `hwrm`                    PORTED  `hwrm`, in the trace
#   :78  `(seq+1) & 0xffff`        PORTED  `hwrm.seq_of`, with the wrap
#   :79  `cmpl_ring`/`target_id`   PORTED  `hwrm.header`
#   :81  the 0x1000-byte clear     PORTED  a WRITE, in the trace
#   :83  the word loop into bar0  PORTED  `hwrm.bar0_at`
#   :84  the trigger dword         PORTED  `hwrm.trig_at`
#   :86  `resp_len` / `seq_id`     PORTED  `hwrm.gate_ok`
#   :88  `assert error_code == 0`  PORTED  the REFUSAL
#   :110 `_open_rcfw`              PORTED  `dev.open_rcfw`, the ordered trace
#   :112 `ring_alloc` NQ           PORTED  `dev.ring_alloc`
#   :115 the NQ_ARM doorbell       PORTED  `dev.doorbell`
#   :116 `cmdq_size_cmdq_lvl`      PORTED  `dev.cmdq_lvl`
#   :121-123 `stat_ctx_alloc`      PORTED  `dev.open_rcfw`'s trace
#   :127 the notification NQ       PORTED  `dev.nq`, logical_id 1
#   :130 `rcfw`                    PORTED  `rcfw`, in the trace
#   :133 `ceildiv(sizeof(req_t),16)` PORTED `rcfw.slots_of`
#   :136-137 the producer index    PORTED  `rcfw.write_idx` / `rcfw.prod`
#   :138 the FIRMWARE_FIRST flag   PORTED  `rcfw.first_flag`
#   :142-143 the prod/trig dwords  PORTED  `rcfw.prod_at` / `rcfw.trig_at`
#   :146 the CREQ valid test       PORTED  `creq.ready`
#   :153 the NQ_ARM consumer db    PORTED  `rcfw.nq_arm`
#   :154 the QP_EVENT filter       PORTED  `rcfw.is_final`, and its threshold
#   :155 `assert ret.status == 0`  PORTED  the REFUSAL
#   :160 `fini`                    PORTED  `dev.fini`
#   :167 `_open_l2`                PORTED  `dev.open_l2`, the enable masks
#   :183 `register_mem`            PORTED  `dev.register_mem` -- the
#                                              `level << LVL_SFT | lps <<
#                                              LOG2_SFT` composition
#   :189 `unregister_mem`          PORTED  `dev.unregister_mem`
#   :191 `BNXTQP.__init__`         PORTED  `qp.new`, the four queues
#   :194 `sizeof(struct_cq_base)`  PORTED  `SIZEOF_CQ_BASE` -- so the CQ
#                                              stride is 32 and not 64
#   :198 `create_qp`               PORTED  `qp.create`
#   :201 `modify_qp(1, INIT_MASK)` PORTED  `qp.modify`
#   :203 `modify_qp`               PORTED  `qp.newstate` -- `state | ntype`
#   :206 `connect`                 PORTED  `qp.connect`, both transitions
#   :208 `struct.unpack` dgid/dmac PORTED  `qp.dgid` / `qp.dmac`
#   :219 `poll`                    PORTED  `qp.poll`, and its CQ doorbell
#   :224 `assert raw[25] == 0`     PORTED  the REFUSAL
#   :227 `post_send`               PORTED  `qp.post_send`, the ordered trace
#   :230 the aux msn write         PORTED  in the same trace
#   :232 the SQ doorbell           PORTED  in the same trace
#   :234 `post_recv`               PORTED  `qp.post_recv`
#
# ===========================================================================
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
#   :54/72 the `getattr(bnxt, ...)` struct
#         construction and `from_buffer_copy` WALL 1 -- see below
#
# ===========================================================================
# THE WALLS.
#
#   1. THE HWRM/RCFW STRUCT CONSTRUCTION AND PARSING (:77-89, :131-134).
#      `getattr(bnxt, f"struct_hwrm_{name}_input")` is a NAME BUILT AT RUNTIME
#      from the verb, and `inp(req_type=..., **fields)` is a kwargs
#      constructor over a ctypes struct. Bend has neither a dynamic name nor a
#      keyword constructor, and `c.record` structs are OPAQUE: `t._fields_` is
#      `('_mem_',)`. So the struct LAYOUT is ported (every field name in order,
#      with its byte offset, gated by name) and the verb names are the trace's
#      job; the CONSTRUCTION is not. The `wait_cond` on `resp_len`/`seq_id` is
#      the same shape as `ops_webgpu.bend`'s `Tr.pop`: a WAIT, in the trace.
# | WALL(p3) bnxtdev.py:77  getattr(bnxt, f"struct_hwrm_{name}_input"). -- BLOCKED. #   DYNAMIC ATTRIBUTE LOOKUP BY A CONSTRUCTED NAME: `getattr(bnxt, f"struct_hwrm_{name}_input")`
#   resolves a field AT RUNTIME from a string, and the name is built per call.
# | WALL(p3) bnxtdev.py:87  out.from_buffer_copy(bytes(self.resp[:sizeof])). -- BLOCKED. #   `out.from_buffer_copy(bytes(self.resp[:sizeof]))` IS CTYPES BUFFER ALIASING -- a Python object
#   whose memory IS the packet, reinterpreted in place.
#      WALL(p3) bnxtdev.py:131 getattr(bnxt, f"struct_cmdq_{name}"). -- BLOCKED. THE SAME
#      RUNTIME NAME RESOLUTION as the marker at :77, one family over.
#      TODO(p3) bnxtdev.py:149 resp_t.from_buffer_copy(self.creq.read(...)).
#   2. THE 64-BIT PHYSICAL ADDRESSES (`build_pbl`'s entries, `db_value`, the
#      doorbell word, `struct_cmdq_*.pbl`). There is no U64 in Bend 2.0.34.
#      Every one of them is carried as TWO U32 halves, and -- MEASURED -- every
#      flag this file sets lives in the LOW half, so the port loses nothing.
#      `pbl_hi_untouched` is the row that says the high half is the paddr's.
# | WALL(p3) bnxtdev.py:32  struct.pack(f"<{len(values)}Q", *values). -- BLOCKED. #   A FORMAT STRING BUILT FROM THE ARGUMENT COUNT -- `struct.pack(f"<{len(values)}Q", *values)` --
#   and `*values` splats a variable-length tuple.
#   3. `MMIOInterface` (:42-45). A byte-addressed slice of host memory over a
#      BAR. `read` and `write` COMPUTE the offsets, and that arithmetic is
#      ported and gated; the slice itself is the seam.
#      TODO(p3) bnxtdev.py:45  self.ring[off:off + len(data)] = data.
#   4. `ctypes.from_buffer_copy` and the `struct` module's C types. WALL 1 plus
#      this: the field LISTS are ported by name and the BYTES are computed as
#      U32 words, but nothing constructs a ctypes object.
#   5. `self.pci_dev.pcibus` (:54), `DEBUG`/`BNXT_DEBUG` and `print` (:61,:74,
#      :157,:217). The verbosity levels are WALLS (`getenv` is IO); the device
#      node string is `nic.node` in `ops_rdma.bend`, which already ports it.
# | WALL(p3) bnxtdev.py:54  self.devfmt = pci_dev.pcibus. -- BLOCKED. #   `self.devfmt = pci_dev.pcibus` READS A FIELD OFF A LIVE PCI DEVICE OBJECT. There is no live
#   device object in the port: `Dev` is a `U32` tag (`LAWS/spec.bend:85`).
#      TODO(p3) bnxtdev.py:157 `if BNXT_DEBUG >= 1: print(...)`.
#   6. `System.list_devices` / `PCIDevice` probing. Not in this file at all;
#      WALL 2 of `ops_rdma.bend` owns it and names `bnxtdev.py`.
#   7. THE GENERATOR OF :94-96. `sum(splits)`, `range(...)` and the
#      `caps.subtype_valid_cnt`-length tuple are the firmware's caps, which
#      arrive from a HWRM the port cannot make. The port takes `entry_size`,
#      `min_num_entries`, the split SUM and the bitmap as PARAMETERS -- which is
#      why the `bs_*` rows are `bs_count_of(typ, mne, sum_splits)` and not a
#      closed table. TODO(p3) bnxtdev.py:95 tuple(getattr(caps, ...) for j ...).
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind.
#
# THE FOUR REFUSALS ARE IN THE TRACE, and each is one Python `raise`/`assert`:
#   :34   `assert len(table_paddrs) <= 512`  -> "a pbl has two levels"
#   :88   `assert ret.error_code == 0`       -> "HWRM <name>"
#   :155  `assert ret.status == 0`           -> "RCFW <name>"
#   :224  `assert raw[25] == 0`              -> "BNXT CQE status"
# `Tr.emit` records NOTHING once `refused` is set, so a refusal appears as a
# TRUNCATED trace and no step below needs a guard of its own.
# ===========================================================================
import Base

# ===========================================================================
# THE CONSTANTS. Every one MEASURED, and every one in
# `.agents/slop/bnxt_constmap.py`, which reads each authority with `getattr`
# and cross-checks the hex-sourced ones a SECOND way (hex literal -> int),
# because a transposed digit pair is invisible to a decimal eyeball.
# ===========================================================================

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

# ===========================================================================
# THE STRUCT FIELD LISTS, BY NAME AND IN ORDER.
#
# `c.record` structs are OPAQUE: `bnxt.struct_cq_base._fields_` is
# `('_mem_',)`, so `ctypes` cannot see the names and `ctypes.sizeof` is the
# only thing it will tell you. The names live in the `_real_fields_` the
# generator installs, and `_real_fields_` is what the oracle reads. These
# lists are TRANSCRIBED from it, in order, and `f_struct_*_NAMES` gates all of
# them at once -- so a wrong field ORDER moves a row and a right field COUNT
# with a wrong order still moves one.
#
# WHY THE ORDER MATTERS HERE SPECIFICALLY. Two offsets in this file are read
# BY HAND and nowhere else:
#   :25  `cqe[24] & CQ_BASE_TOGGLE` -- byte 24 is `cqe_type_toggle`, the
#        fourth field, and NOT byte 0. Polling byte 0 would read
#        `reserved64_1`, which is always zero, so the wait would never fire.
#   :224 `raw[25] == 0` -- byte 25 is `status`, the FIFTH field, and the
#        completion error. `cqe_of` / `cqe_status` are pinned BY NAME against
#        `_real_fields_` by `f_CQE_TOGGLE_FIELD` and `f_CQE_STATUS_FIELD`.
# ===========================================================================
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

# ===========================================================================
# THE 64-BIT DOORBELL WORD, :13-15.
#
#   def db_value(xid, typ, index, epoch):
#     return (xid & DBC_DBC_XID_MASK | DBC_DBC_PATH_ROCE | typ |
#             BNXT_QPLIB_DBR_VALID) << 32 |
#            index & DBC_DBC_INDEX_MASK | epoch << BNXT_QPLIB_DBR_EPOCH_SHIFT
#
# TWO HALVES and they are NOT symmetrical, which is the whole reason this file
# carries them separately:
#   HIGH: WHICH QUEUE -- the xid, the path and the VALID bit.
#   LOW:  WHERE in it -- the index and the EPOCH.
# `db.of` also takes the whole word as (hi, lo) so a gate row can hold both,
# and `db.hi`/`db.lo` are the two the trace writes.
# ===========================================================================
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
# ===========================================================================
# send_wqe / recv_wqe, :18-19.
#
#   send_wqe: struct.pack("<BBB5xI20xQII", 0, SQ_SEND_FLAGS_SIGNAL_COMP, 3,
#                         size, va, key, size)
#   recv_wqe: struct.pack("<BBB29xQII", 0x80, 0, 3, va, key, size)
#
# FORTY-EIGHT BYTES EACH, and the two formats differ in EXACTLY TWO PLACES,
# both of which matter:
#
#   * byte 0. Send puts `0` there and receive puts `0x80`, which is the "this
#     is a receive" bit. Byte 0 is the LOW byte of word 0.
#   * byte 1. Send puts `SQ_SEND_FLAGS_SIGNAL_COMP` (1) there -- "ring the
#     completion queue when this send retires" -- and receive puts 0.
#
# AND THE ONE THAT IS EASY TO GET WRONG. Word 0 is little-endian, so it is
#
#       kind << 16 | flags << 8 | type
#
# with `kind` -- the 3, the size in 16-byte units -- in the HIGH byte and
# `type` in the LOW. `ops_rdma.bend:224-225` says `type << 16 | flags << 8 |
# kind`, which is INVERTED; its code at :1490-1492 gets it right and this
# file's `wqe.hdr0` follows the code and the measurement, not the comment.
# `hdr0_SEND_COMMENT_IS_RIGHT` and `hdr0_RECV_COMMENT_IS_RIGHT` are oracle
# rows, both `0`, and they say so in a committed artefact rather than in an
# argument. VERIFIED BY GREP, not asserted -- see the report.
# ===========================================================================
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

# ===========================================================================
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
# ===========================================================================
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

# ===========================================================================
# cqe_ready, :25. `(cqe[24] & CQ_BASE_TOGGLE) != (cons // CQ_ENTRIES & 1)`.
#
# BYTE 24 is `cqe_type_toggle` -- the FOURTH field of `struct_cq_base`, after
# three 64-bit reserved words -- and not byte 0. Byte 0 is `reserved64_1`,
# which is always zero, so a port that polled byte 0 would wait for a toggle
# that can never be set and would hang. `cqe_of` / `cqe_status` are pinned by
# NAME against `_real_fields_` and not by counting from the front.
# ===========================================================================
def CQE_TOGGLE_AT() -> U32: 24

def cqe.ready(toggle: U32, cons: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(toggle, CQ_BASE_TOGGLE()), U32.and(U32.div(cons, CQ_ENTRIES()), 1)))

# the epoch `cons // CQ_ENTRIES & 1` on its own, which is the other half of the
# test and is what `poll`'s doorbell reproduces one step later.
def cqe.epoch(cons: U32) -> U32: U32.and(U32.div(cons, CQ_ENTRIES()), 1)

# ===========================================================================
# THE PAGE TABLES. `build_pbl`, :27-37, and it is THE TABLE MOST LIKELY TO
# CARRY A WRONG CONSTANT, because a wrong PTU_PTE_* flag is a page table the
# NIC walks off the end of and there is no Python exception to catch it.
#
#   def build_pbl(dev, paddrs, queue=False):
#     if len(paddrs) == 1: return 0, paddrs[0]
#     values = [p | PTU_PTE_VALID for p in paddrs]
#     if queue: values[-1] |= PTU_PTE_LAST; values[-2] |= PTU_PTE_NEXT_TO_LAST
#     table, table_paddrs = dev.pci_dev.alloc_sysmem(ceildiv(len(values),512)*0x1000)
#     table[:len(values)*8] = struct.pack(f"<{len(values)}Q", *values)
#     if len(table_paddrs) == 1: return 1, table_paddrs[0]
#     assert len(table_paddrs) <= 512, "a pbl has two levels"
#     top, top_paddrs = dev.pci_dev.alloc_sysmem(0x1000)
#     top[:len(table_paddrs)*8] = struct.pack(..., *(p|PTU_PTE_VALID for p in table_paddrs))
#     return 2, top_paddrs[0]
#
# FOUR FACTS, and each has a row:
#   1. ONE page short-circuits with NO ALLOCATION at all and NO VALID BIT.
#      `pbl_level_of(1) == 0` and `pbl_one_ALLOCS == 0`.
#   2. THE LEVEL IS A FUNCTION OF `ceildiv(n, 512)` ALONE -- the table's byte
#      count is a whole number of pages, so the number of pages holding the
#      table IS the page count of the allocation. 1 -> level 1, 2..512 ->
#      level 2, more -> the REFUSAL. `pbl_q_512_LEVEL == 1` and
#      `pbl_q_513_LEVEL == 2` sit ONE PAGE APART, which is the negative case.
#   3. THE THREE FLAGS LAND IN THE LOW 32 BITS. `PTU_PTE_VALID` is 1,
#      `PTU_PTE_LAST` is 2 and `PTU_PTE_NEXT_TO_LAST` is 4, so the high half
#      of every entry is the physical address's and NOTHING ELSE --
#      `pbl.entry_hi` is the IDENTITY and `pbl_hi_untouched` says so. This is
#      what makes WALL 2 cost nothing here.
#   4. `queue` ADDS TWO FLAGS TO TWO DIFFERENT ENTRIES, and the SECOND-to-last
#      is the one that gets NEXT_TO_LAST -- the two are not the same entry and
#      `pbl_queue_two_entries` is the row that separates them.
# ===========================================================================
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

# fact 4. WHICH ENTRY GETS WHICH FLAG, as a function of the index. The LAST
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

# ===========================================================================
# BNXTQueue, :39-45, and `alloc_queue`, :47-50.
#
#   read(i):  ring[(off := i % (size // stride) * stride) : off + stride]
#   write(i, data, aux):
#     off = size + i % (size // stride) * 8 if aux else i % (size//stride)*stride
#     ring[off:off + len(data)] = data
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
# ===========================================================================
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
# `BNXTQueue.size` IS THE RING AND NOT THE ALLOCATION. `alloc_queue` (:49) is
#   mem, paddrs = alloc_sysmem((size := entries * stride) + aux * entries * 8)
#   return BNXTQueue(mem, paddrs, stride, ..., size=size)
# so the `+ aux * entries * 8` goes into the ALLOCATION and `size=` keeps the
# ring alone. A port that adds the aux term to `size` claims a 6144-byte queue
# where there is a 4096-byte one, and every slot count and every aux base after
# it is wrong. **THE GATE CAUGHT THIS**: `aq_1_SIZE` and `aq_1_SLOTS` were the
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

# ===========================================================================
# THE ROW PRINTERS. One `name=value` line per claim; the gate is that the
# interpreted lane, the native lane and `.agents/slop/bnxt_oracle.txt` all
# print the same lines. A row is never a restatement of the def under test:
# every expectation in the oracle is produced by CALLING CPYTHON, and where
# Python can run the function the oracle calls it rather than transcribing it.
# ===========================================================================
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def brow(nm: String, v: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def sep(ix: U32) -> String: Bool.pick(String, U32.is_zero(ix), "", " ")

# A SPACE-SEPARATED JOIN WITH NO TRAILING SPACE, because the oracle prints
# Python's `" ".join(...)` and a trailing space would make every list row
# disagree for a reason that is not arithmetic.
#
# ONE self-call, not two. `show_go`/`show_tail` looked right and is MUTUAL
# RECURSION, which Bend refuses -- and the error names the callee, not the
# cycle. The position rides in as a `U32` parameter and the separator is a
# `Bool.pick` on it, so there is a single self-recursive def.
def show_go(n: Nat, +ix: U32, xs: List<&2, U32>) -> String:
  match n:
    case 0n: ""
    case 1n+m:
      match xs:
        case Nil{}: ""
        case h <> t: String.concat([sep(ix), U32.show(h), show_go(m, U32.inc(ix), t)])

def join_u32(+xs: List<&2, U32>) -> String: show_go(List.length(&2, U32, xs), 0, xs)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit): IO.print(String.concat([nm, "=", join_u32(xs)]))

def names_go(n: Nat, +ix: U32, xs: List<&2, String>) -> String:
  match n:
    case 0n: ""
    case 1n+m:
      match xs:
        case Nil{}: ""
        case h <> t: String.concat([sep(ix), h, names_go(m, U32.inc(ix), t)])

def join_str(+xs: List<&2, String>) -> String:
  names_go(List.length(&2, String, xs), 0, xs)

def nrow(nm: String, xs: List<&2, String>) -> IO(Unit): IO.print(String.concat([nm, "=", join_str(xs)]))

# ===========================================================================
# THE LOGGING TABLE. `BNXT_BACKING_STORE`, :11, and what drives it,
# `setup_backing_store`, :91-108.
#
#   BNXT_BACKING_STORE = ((0, 64), (1, 0), (2, 128), (3, 0), (4, 2), (5, 0),
#                         (6, 0), (14, 1024), (15, 0))
#
# NINE (type, extra) pairs, and TWO THINGS ABOUT THE TABLE ARE NOT VISIBLE IN
# THE LITERAL. First, TYPES 7..13 ARE ABSENT: the type numbers are not 0..8,
# so an index-into-the-table is NOT a type, and `bs_index_of` has to SEARCH.
# `bs_absent_7` is the row that says type 7 is not in the table -- the negative
# case, one row from its opposite. Second, the last entry's extra is 0 and the
# penultimate's is 1024, so a table that is off by one place puts 1024 on type
# 15, which is the type whose count is COPIED rather than computed.
#
# `bs_row_*` is the fixture table for `bs_count_of`: the caps that
# `func_backing_store_qcaps_v2` returns, transcribed per type from
# `.agents/slop/bnxt_oracle.py`'s `FIX`, and every field the port reads is
# printed beside its use so a wrong field cannot hide behind a right sum.
# ===========================================================================
def BS_TYP() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 14, 15]
def BS_EXTRA() -> List<&2, U32>: [64, 0, 128, 0, 2, 0, 0, 1024, 0]
def BS_LEN() -> U32: 9

# The index is a `List.get`, not a chain of `Bool.pick`s: an absent type
# answers `BS_LEN()`, which `List.get` past the end turns into 0, and that is
# the same 0 an absent type's `extra` is. Eight nested picks were the first
# spelling and it was one paren away from a silent mis-pairing.
def bs.extra_at(i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, BS_EXTRA(), U32.to_nat(i)), 0)

def bs.typ_at(i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, BS_TYP(), U32.to_nat(i)), 0)

# THE SEARCH, and `BS_LEN()` is the not-found answer -- a type number that is
# not in the table indexes past the end. `bs_absent_*` rows are the negative
# case for it.
# The fuel is the LIST LENGTH and the position rides beside it as a plain
# parameter, which is `Tr.count.go`'s shape. Binding the position from the
# countdown instead (`U32.from_nat(i)`) needs the scrutinee twice and the
# `-i` that admits that kills the `0n` arm.
def bs.index_at.go(n: Nat, +ix: U32, +typs: List<&2, U32>, +hit: U32, +typ: U32) -> U32:
  match n:
    case 0n: hit
    case 1n+m:
      match typs:
        case Nil{}: hit
        case h <> t: bs.index_at.go(m, U32.inc(ix), t,
          Bool.pick(U32, U32.is_eq(h, typ), ix, hit), typ)

def bs.index_at(+typs: List<&2, U32>, typ: U32) -> U32:
  bs.index_at.go(List.length(&2, U32, typs), 0, typs, BS_LEN(), typ)

def bs.index_of(typ: U32) -> U32: bs.index_at(BS_TYP(), typ)

def bs.extra_of(typ: U32) -> U32: bs.extra_at(bs.index_of(typ))

# :96 -- `counts[typ] = counts[0] if typ == 15 else max(min_num_entries,
# sum(splits) + extra)`. THREE facts and they are all in this one line:
#   1. type 15 REUSES type 0's count verbatim -- it does not read `extra` and
#      it does not take the `max`. `bs_count_15_is_zero_count` is the row.
#   2. `max(min_num_entries, sum + extra)`: the FIRMWARE's floor wins when the
#      sum is smaller. `bs_count_4_floor_wins` and `bs_count_0_sum_wins` are
#      the two rows and they sit one entry apart on purpose.
#   3. `extra` is the TABLE's per-type second element, found by SEARCH.
def BS_TYPE15() -> U32: 15
def BS_TYPE0() -> U32: 0

def bs.count_of(+typ: U32, mne: U32, sum_splits: U32, c0: U32) -> U32:
  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), c0,
    U32.max(mne, U32.add(sum_splits, bs.extra_of(typ))))

# :98 -- `for instance in [i for i in range(8) if caps.instance_bit_map >> i & 1] or [0]`.
# A ZERO BITMAP MEANS THE TYPE HAS A SINGLE INSTANCE 0, which is the `or [0]`
# and is not a special case of the scan -- it is the scan's answer when the
# scan finds nothing. `bs_instances_*` rows run six bitmaps, two of them zero.
def bs.inst_bit(ibm: U32, i: U32) -> Bool: U32.is_ne(U32.and(U32.shrn(ibm, U32.to_nat(i)), 1), 0)

# The COUNT of instances: the popcount, and the `or [0]` makes it 1 when the
# popcount is 0. `U32.popcount` is not in Base 2.0.34's U32, so the count is a
# fold over the eight bits, which is also what `bs.instances` needs.
def bs.count.go(n: Nat, +ix: U32, +ibm: U32, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: bs.count.go(m, U32.inc(ix), ibm,
      U32.add(got, Bool.to_u32(bs.inst_bit(ibm, ix))))

def bs.ninstances(ibm: U32) -> U32: U32.max(1, bs.count.go(8n, 0, ibm, 0))

# The FIRST instance index, and 0 for a zero bitmap -- the whole of the
# `or [0]` in one number.
#
# A fold that overwrites on every hit answers the HIGHEST set bit, not the
# lowest, so the `found` flag is load-bearing and not decoration: a bitmap with
# bits 0 and 2 set must answer 0. `bs_inst_fwd_0` is the row that sees it, and
# `bs_inst_rev_0` is the negative case sitting one bitmap away.
# THE FUEL IS THE FIRST PARAMETER of every self-recursive def -- rule 5, and a
# self-call whose fuel is the fourth argument is refused, not merely slow.
def bs.first_of(n: Nat, +ix: U32, +ibm: U32, +found: Bool, +best: U32) -> U32:
  match n:
    case 0n: best
    case 1n+m: bs.first_of(m, U32.inc(ix), ibm, Bool.or(found, bs.inst_bit(ibm, ix)),
      Bool.pick(U32, Bool.and(Bool.not(found), bs.inst_bit(ibm, ix)), ix, best))

def bs.first_inst(+ibm: U32) -> U32: bs.first_of(8n, 0, ibm, False{}, 0)

# :99 -- `alloc_sysmem(ceildiv(n * size, 0x1000) * 0x1000)`. The count is
# ROUNDED UP TO WHOLE PAGES, and `entry_size` multiplies BEFORE the rounding.
def bs.alloc_bytes(n: U32, entry_size: U32) -> U32: U32.mul(ceildiv(U32.mul(n, entry_size), PAGE()), PAGE())

# :107 -- `BS_CFG_ALL_DONE if typ == 15 else 0`. The firmware's "I am finished"
# flag, and it goes on the SAME type whose count is copied.
def bs.flags_of(typ: U32) -> U32:
  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE(), 0)

# :102 -- the `ctx_init` sweep. `init[caps.ctx_init_offset::size] = bytes([v])
# * len(range(off, len(mem), size))`, so the pattern has a STRIDE of
# `entry_size` starting at `ctx_init_offset`, and the sweep length is the
# count of those positions. `bs.init_stride` is that stride and
# `bs.init_npos` is the count; both are needed and they are not the same
# number, which is exactly the mistake the sweep invites.
def bs.init_npos(+mem_bytes: U32, +off: U32, entry_size: U32) -> U32:
  Bool.pick(U32, U32.is_ge(off, mem_bytes), 0, ceildiv(U32.sub(mem_bytes, off), entry_size))

def bs.init_len(npos: U32) -> U32: npos

# ===========================================================================
# THE TRACE. One `CALL_*` per device call, carrying up to TWO U32 arguments:
# `a` is the address or the index and `b` is the value or the length. Two
# arguments is the smallest that covers `self.bar0[i] = w`, `self.db[off] =
# value` and `ring[off:off+n] = data` -- a one-argument trace could not say
# WHICH register got WHICH value, which is the whole of a register write.
#
# `Tr.emit` is the seam: nothing else in this file makes a device call, so the
# trace IS the ordered list of what the seam will do. There is no
# `import "./x.c"`, so this file declares NO foreign effect, and every symbol
# the port names is a LITERAL in the file and greppable.
#
# THE RAISE IS HERE. `Tr.emit` records NOTHING once a refusal has fired and
# `Tr.refuse` is IDEMPOTENT after the first, so one fixture numbering reaches
# EVERY refusal site in turn and a refusal appears as a TRUNCATED TRACE. That
# is why no step below carries a guard of its own.
# ===========================================================================
type Call is Data:
  Call{k: U32, a: U32, b: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool, nth: U32, at: U32}

# the FFI seam, one tag per Python line. See THE FFI SEAMS in the header.
def CALL_PCI_RESET() -> U32: 0
def CALL_PCI_CFG_R() -> U32: 1
def CALL_PCI_CFG_W() -> U32: 2
def CALL_MAP_BAR() -> U32: 3
def CALL_ALLOC() -> U32: 4
def CALL_BARRIER() -> U32: 5
def CALL_BAR0() -> U32: 6
def CALL_RING_W() -> U32: 7
def CALL_RING_R() -> U32: 8
def CALL_WAIT() -> U32: 9
def CALL_HWRM() -> U32: 10
def CALL_RING_ALLOC() -> U32: 11
def CALL_CMDQ() -> U32: 12
def CALL_VNIC() -> U32: 13
def CALL_L2_FILTER() -> U32: 14
def CALL_MR() -> U32: 15
def CALL_FINI() -> U32: 16
def CALL_DB() -> U32: 17
def CALL_REFUSE() -> U32: 18

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, a, b}: k
def Call.a(c: Call) -> U32:
  match c:
    case Call{k, a, b}: a
def Call.b(c: Call) -> U32:
  match c:
    case Call{k, a, b}: b

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}, 0, 0}
def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused, nth, at}: calls
def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused, nth, at}: refused

# the refusal ordinal the seam should fail on, 0 = never. `nth` is NOT reset by
# `Tr.reset`, so one fixture numbering covers a whole device lifetime.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{calls, next, refused, nth, n}

# an EMPTY trace that keeps `at` and `nth`, so a gate can read one step without
# the device init in front of it and still number its refusals from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{Nil{}, 0, refused, nth, at}

# the id the NEXT emit mints, i.e. what the seam's call returns.
def Tr.here(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: next

def Tr.emit.go(+refused: Bool, k: U32, a: U32, b: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls, List.append(&2, Call, calls, [Call{k, a, b}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused, nth, at}

def Tr.emit(k: U32, a: U32, b: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.emit.go(refused, k, a, b, calls, next, nth, at)

# THE RAISE, and it is idempotent after the first so one fixture numbering
# reaches every site. The failing refusal is NOT recorded, because in Python the
# `assert` replaces it.
def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.refuse.go(refused, nth, at)

# ===========================================================================
# READING THE TRACE. `Tr.count` is how many calls carry a tag -- which is the
# TRUNCATION LENGTH a refusal shows up as. `Tr.seq` is an ordered SUBSEQUENCE
# test, so a trace that contains the right calls in the WRONG ORDER fails.
# `Tr.arg_at` is the argument a call carried, which is what pins "the right
# VALUE reached the right call".
# ===========================================================================
def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa, bb} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# The j-th argument of the j-th call carrying tag `k`, or `MISSING` when there
# is none. `MISSING` and a real zero are told apart, which is what lets a row
# say "the doorbell wrote 0" as readily as "no doorbell was written" -- and a
# `MISSING` answer IS the refusal signature.
#
# ONE walk, not two: `sel` picks the field, so `Tr.arg_at` and `Tr.val_at` are
# the same def with `sel` 0 and 1. Two walks differing in one projection is
# copy-paste, and a copy-paste pair is two places for the next bug to live.
def MISSING() -> U32: 4294967295

def Call.sel(+c: Call, w: U32) -> U32: Bool.pick(U32, U32.is_zero(w), Call.a(c), Call.b(c))

def Tr.nth.go(n: Nat, +k: U32, +cs: List<&2, Call>, +j: U32, +w: U32,
              +at: U32, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case c <> t: Tr.nth.go(m, k, t, j, w,
          U32.add(at, Bool.to_u32(U32.is_eq(Call.k(c), k))),
          Bool.pick(U32, Bool.and(U32.is_eq(Call.k(c), k), U32.is_eq(at, j)),
            Call.sel(c, w), got))

def Tr.nth(k: U32, +cs: List<&2, Call>, j: U32, w: U32) -> U32:
  Tr.nth.go(List.length(&2, Call, cs), k, cs, j, w, 0, MISSING())

def Tr.arg_at(k: U32, +cs: List<&2, Call>, j: U32) -> U32: Tr.nth(k, cs, j, 0)
def Tr.val_at(k: U32, +cs: List<&2, Call>, j: U32) -> U32: Tr.nth(k, cs, j, 1)

# THE ORDERED SUBSEQUENCE TEST, duplicated from `ops_webgpu.bend` and
# `support/am/ip.bend` because this substrate is a copy and a copy needs its
# own rows. The answer is `at == patlen` and the fuel is the TRACE length, so
# with the fuel set to the PATTERN length a REVERSED pattern would match --
# `has_fwd` / `has_rev` are the rows that catch it.
def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, +at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, +at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.a(c), Call.a(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa, bb} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa, bb}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def Tr.seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

# ===========================================================================
# THE HWRM AND RCFW WORD ARITHMETIC. :55-89 and :130-158.
#
# `hwrm` (:76-89) is a wall for its struct construction (WALL 1) and a seam for
# its transport, but SIX numbers in it are arithmetic and each has a row:
#   :78  `self.seq = (self.seq + 1) & 0xffff` -- the sequence counter WRAPS, and
#        `hwrm_seq_wrap` is the row that crosses 0xffff. A version with a
#        plain `+ 1` would send a sequence id the firmware never matches and
#        every HWRM would time out.
#   :79  `cmpl_ring = BNXT_HWRM_NO_CMPL_RING`, `target_id = BNXT_HWRM_TARGET`
#   :83  `self.bar0[BNXT_CHIMP_COMM // 4 + i] = w` -- the word loop, and the
#        `// 4` is what makes the first word land in bar0 dword 0.
#   :84  `self.bar0[BNXT_CHIMP_COMM_TRIGGER // 4] = 1`
#   :86  `(n := resp_len) and seq_id == seq` -- the wait's GATE, and it has
#        three conjuncts: a zero `resp_len` means "not yet", so the gate is not
#        just the sequence match.
#   :87  `ctypes.sizeof(out)` bounded by the 0x1000-byte response buffer
# ===========================================================================
def SEQ_MASK() -> U32: 65535
def CREQ_CONS_MASK() -> U32: 255

def hwrm.seq_of(seq: U32) -> U32: U32.and(U32.add(seq, 1), SEQ_MASK())

# :83 the word loop's bar0 dword index. `BNXT_CHIMP_COMM` is 0 so this is `i`,
# and the row says so -- a port that divided the trigger offset by 8 instead
# of 4 would write half as far up the bar.
def hwrm.bar0_at(i: U32) -> U32: U32.add(U32.div(BNXT_CHIMP_COMM(), 4), i)
def hwrm.trig_at() -> U32: U32.div(BNXT_CHIMP_COMM_TRIGGER(), 4)

# :86 -- `resp_len` nonzero AND `seq_id == seq`. NOT just the sequence match: a
# zero-length response is the firmware saying "not yet", and treating it as
# ready is how a port hangs in a poll loop instead of returning.
def hwrm.gate_ok(resp_len: U32, seq_id: U32, want: U32) -> Bool:
  Bool.and(U32.is_ne(resp_len, 0), U32.is_eq(seq_id, want))

# :142-143 -- the command-queue producer and trigger dwords.
#   self.bar0[(RCFW_COMM_BASE_OFFSET + RCFW_PF_VF_COMM_PROD_OFFSET) // 4] = prod
#   self.bar0[(RCFW_COMM_BASE_OFFSET + RCFW_COMM_TRIG_OFFSET) // 4] = TRIG_VAL
# The two `// 4` are the SAME shape as the HWRM bar0 loop's, and they land at
# DIFFERENT dwords 61 apart -- `rcfw_prod_trig_apart` is the row.
def rcfw.prod_at() -> U32: U32.div(U32.add(RCFW_COMM_BASE_OFFSET(), RCFW_PF_VF_COMM_PROD_OFFSET()), 4)
def rcfw.trig_at() -> U32: U32.div(U32.add(RCFW_COMM_BASE_OFFSET(), RCFW_COMM_TRIG_OFFSET()), 4)
def rcfw.trig_val() -> U32: RCFW_CMDQ_TRIG_VAL()

# :133 `cmd_size = slots := ceildiv(ctypes.sizeof(req_t), 16)`. The command is
# a whole number of 16-byte slots and `slots` is BOTH the size field and the
# number of ring writes at :134.
def rcfw.slots_of(req_bytes: U32) -> U32: ceildiv(req_bytes, SLOT16())

# :136-137 -- `self.cmdq.write_idx += slots` then `prod = write_idx & 0xffff`.
# THE MASK IS NOT COSMETIC: `write_idx` is not reset by anything in this file,
# so it grows past 0xffff and the producer index is its low sixteen bits. The
# FIRST command also carries the FIRMWARE_FIRST flag.
def rcfw.prod_of(write_idx: U32) -> U32: U32.and(write_idx, SEQ_MASK())

def rcfw.first_flag(+prod: U32, first: Bool) -> U32:
  Bool.pick(U32, first, U32.or(prod, U32.shln(1, U32.to_nat(FIRMWARE_FIRST_FLAG()))), prod)

# :146 -- `(self.creq.read(ri)[8] & CREQ_BASE_V) != (self.creq.read_idx // 256 & 1)`.
# The SAME SHAPE as `cqe.ready` (:25) with a different toggle source and a
# different wrap divisor: byte 8 of a CREQ entry against `read_idx // 256`,
# where byte 24 of a CQE is tested against `cons // CQ_ENTRIES`.
def creq.ready(toggle: U32, read_idx: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(toggle, CREQ_BASE_V()),
                     U32.and(U32.div(read_idx, CREQ_CONSUME()), 1)))

# :153 -- the NQ_ARM doorbell that publishes the CREQ consumer index. Note the
# TWO MASKS: the index is `& 255` and the epoch is `(read_idx // 256) & 1`, so
# the consumer index is 8 bits wide and its epoch is 1 -- NOT the doorbell's
# 24-bit index, and not `CREQ_ENTRIES`.
def rcfw.nq_arm_index(read_idx: U32) -> U32: U32.and(read_idx, CREQ_CONS_MASK())
def rcfw.nq_arm_epoch(read_idx: U32) -> U32: U32.and(U32.div(read_idx, CREQ_CONSUME()), 1)

# :154 -- `if ret.type == CREQ_BASE_TYPE_QP_EVENT and ret.event <
# CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION: break`. The `while True` SKIPS
# async events, so the command is finished only on a NON-event OR on an event
# past the error-notification threshold. The comparison is `<`, so the
# threshold event itself is NOT a skip -- `rcfw_skip_at_threshold` is the row
# and it is False, one row from `rcfw_skip_below_threshold`.
def rcfw.is_event(ret_type: U32) -> Bool: U32.is_eq(ret_type, CREQ_BASE_TYPE_QP_EVENT())

def rcfw.skip(ret_type: U32, ret_event: U32) -> Bool:
  Bool.and(rcfw.is_event(ret_type),
           U32.is_lt(ret_event, CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION()))

# ===========================================================================
# THE DEVICE INDEX ARITHMETIC. `BNXTDev.__init__`, :53-72, `register_mem`,
# :183-189, `_open_l2`, :167-180, and `BNXTQP`, :191-217.
# ===========================================================================

# :66 -- `self.db_off = hwrm("func_qcfg", fid=0xffff).legacy_l2_db_size_kb *
# 1024`. A BYTE offset, and :164 then divides it by 8 because the doorbell
# register is 64 bits wide (`map_bar(2, fmt='Q')`). The two are the SAME
# number at two scales and confusing them rings the wrong queue.
def db_off_of(db_size_kb: U32) -> U32: U32.mul(db_size_kb, 1024)
def db_at(db_off: U32) -> U32: U32.div(db_off, 8)

# :64 -- `int.from_bytes(bytes(caps.mac_address), 'big')`. Big-endian.
#
# A MAC IS 48 BITS AND DOES NOT FIT IN A `U32`. `U32.shrn(x, 32n)` SATURATES
# TO 0, so a MAC read as one word silently loses its top sixteen bits -- and the
# gate said so: `gid_MAC_HI` printed 0 where CPython says 4386. It is therefore
# carried as TWO halves, `MAC_HI16` and `MAC_LO32`, and the two 24-bit halves
# `int.from_bytes(..., 'big')` produces are assembled from both.
def MAC_HI16() -> U32: 17
def MAC_LO32() -> U32: 573785173

# the top THREE bytes, big-endian: `hi16`'s low byte then `lo32`'s top byte
def mac_hi(hi16: U32, lo32: U32) -> U32:
  U32.or(U32.shln(hi16, 8n), U32.shrn(lo32, 24n))

# the bottom THREE bytes
def mac_lo(lo32: U32) -> U32: U32.and(lo32, 16777215)

# :71 -- `bytes(10) + b'\xff\xff\x0a' + self.mac.to_bytes(6, 'big')[3:]`.
# SIXTEEN bytes, and the last three are the MAC's LOW three -- `mac[3:]` of a
# 6-byte string is bytes 3,4,5. The middle is the literal `\xff\xff\x0a`,
# which lands in `>4I` word 1 as 0x0000ffff because bytes 8 and 9 are still
# inside the ten leading zeros.
def GID_BYTES() -> U32: 16
def GID_W0() -> U32: 0
def GID_W1() -> U32: 0
def GID_W2() -> U32: 65535
def GID_0A() -> U32: 10

def gid_w3(mac_lo24: U32) -> U32: U32.or(U32.shln(GID_0A(), 24n), mac_lo24)

# :72 -- `struct.unpack(">4I", self.local_gid)[::-1]`: four big-endian words,
# REVERSED. The reversal is the point -- the NIC wants the low word first.
def gid_order(w0: U32, w1: U32, w2: U32, w3: U32) -> List<&2, U32>: [w3, w2, w1, w0]

# :72 -- `struct.unpack(">3H", self.mac.to_bytes(6, 'big'))`: THREE 16-bit
# halves, big-endian, in order. The half is chosen by a `Nat` shift amount
# because `U32.shln`/`U32.shrn` take a `Nat` and there is no way to compute one
# -- which is why a bit-packer whose field positions are runtime values is
# unwritable in this Bend, and why these three are literals at the call site.
# `>3H` reads THREE 16-bit halves, so the low one is `& 0xffff` and not the
# whole low word. Without the mask `src_mac_h(lo32, 0n)` answers 0x22334455
# where the source says 0x4455, and `gid_SRCMAC` said so.
def src_mac_h(lo32: U32, sh: Nat) -> U32: U32.and(U32.shrn(lo32, sh), 65535)

def src_mac(hi16: U32, +lo32: U32) -> List<&2, U32>: [hi16, src_mac_h(lo32, 16n), src_mac_h(lo32, 0n)]

# :185-188 -- `log2_pg_size_lvl = level << LVL_SFT | log_page_size << LOG2_SFT`,
# and `CMDQ_REGISTER_MR_LVL_SFT` is 0, so the level is NOT shifted at all.
# That zero is a fact about the field and not about the code, and a port that
# "fixed" the missing shift would move the level into the page-size field.
def mr.lvlpg(level: U32, log_page_size: U32) -> U32:
  U32.or(U32.shln(level, U32.to_nat(CMDQ_REGISTER_MR_LVL_SFT())),
         U32.shln(log_page_size, U32.to_nat(CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT())))

def mr.lvl_of(lvlpg: U32) -> U32:
  U32.shrn(U32.and(lvlpg, 4294967295),
           U32.to_nat(CMDQ_REGISTER_MR_LVL_SFT()))

def mr.log_page_of(lvlpg: U32) -> U32:
  U32.shrn(lvlpg, U32.to_nat(CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT()))

# :204 -- `network_type_en_sqd_async_notify_new_state = state | network_type`.
# The state is 1, 2 or 3 and the network type is 0x80, so the composed field is
# 1, 130 or 131 -- and `qp_newstate_1` and `qp_newstate_2` are the two rows
# that differ only in the state, one apart.
def qp.newstate(state: U32, network_type: U32) -> U32: U32.or(state, network_type)

# :169-174 -- the two `ring_alloc` enable masks, and they are DIFFERENT words
# one line apart: the completion ring sets NQ_RING_ID_VALID alone and the
# receive ring sets it OR'd with RX_BUF_SIZE_VALID. `l2_ring_alloc_enables`
# and `rx_ring_alloc_enables` sit side by side so a port that shared one
# constant cannot pass both.
def ra_l2_enables() -> U32: RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID()

def ra_rx_enables() -> U32:
  U32.or(RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID(), RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID())

# :176-177 -- the `vnic_cfg` enable mask: MRU, the default receive ring and the
# default completion ring, three bits, and ALL THREE or the vnic has no length
# and no rings.
def vnic_enables() -> U32:
  U32.or(U32.or(VNIC_CFG_REQ_ENABLES_MRU(), VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID()),
         VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID())

# :178-180 -- `cfa_l2_filter_alloc`: the PATH_RX flag word is separate from
# the enables word, and conflating them is a filter that matches no traffic.
def l2_filter_flags() -> U32: CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX()

def l2_filter_enables() -> U32:
  U32.or(U32.or(CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR(),
                CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK()),
         CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID())

# :116 -- `cmdq_size_cmdq_lvl = 256 << CMDQ_INIT_CMDQ_SIZE_SFT`, which is 1024,
# and the field is only 16 bits wide, so it survives. The shift is 2 and the
# shift is MEASURED, not assumed.
def cmdq_lvl() -> U32: U32.shln(CMDQ_LVL(), U32.to_nat(CMDQ_INIT_CMDQ_SIZE_SFT()))
def cmdq_lvl_lo16() -> U32: U32.and(cmdq_lvl(), 65535)

# ===========================================================================
# THE OPERATIONS. Each one EITHER builds the argument of one device call (and
# returns it) OR records the call and hands back the trace. There is no third
# kind, and `Tr.refuse` inside one of them is the port of the Python `assert`
# on the next line.
#
# The Python LINE is on each def, and so is the seam it records, so a reader
# can grep from a row name to the line it came from without leaving the file.
# ===========================================================================# doorbell, :162-164. `System.memory_barrier()` THEN the 64-bit store, and the
# ORDER IS THE PROTOCOL: a doorbell that lands before the ring write is a door
# bell for stale data. `db_seq` is the ordered identity trace for it and
# `db_2halves` says the store is TWO dwords because Python's is one 64-bit
# word and Bend has no U64.
def dev.doorbell(creq_or_qpn: U32, typ: U32, index: U32, epoch: U32, db_off: U32, t: Tr) -> Tr:
  Tr.emit(CALL_DB(), db_at(db_off), db.lo(index, epoch),
          Tr.emit(CALL_BARRIER(), 0, 0, t))

# `hwrm`, :76-89. The six emitted calls in order: the sequence bump, the 0x1000
# byte clear, the word loop into bar0, the trigger dword, the wait, and the
# error-code refusal.
def hwrm.begin(seq: U32, t: Tr) -> Tr: Tr.emit(CALL_HWRM(), hwrm.seq_of(seq), 0, t)

def hwrm.clear(t: Tr) -> Tr: Tr.emit(CALL_ALLOC(), RESP_BYTES(), RESP_BYTES(), t)

def hwrm.word(i: U32, w: U32, t: Tr) -> Tr: Tr.emit(CALL_BAR0(), hwrm.bar0_at(i), w, t)

def hwrm.trig(t: Tr) -> Tr: Tr.emit(CALL_BAR0(), hwrm.trig_at(), 1, t)

def hwrm.wait(t: Tr) -> Tr: Tr.emit(CALL_WAIT(), 10000, 0, t)

# :88 `assert ret.error_code == 0` -- THE FIRST REFUSAL. The trace so far is
# KEPT and everything after it is not, so `hwrm_error_refused` sees a trace
# that ends at the wait with no trigger and no return.
def hwrm.error_ok(error_code: U32) -> Bool: U32.is_zero(error_code)

def hwrm.finish(error_code: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, hwrm.error_ok(error_code), t, Tr.refuse(t))

# `rcfw`, :130-158. The producer/trigger pair and the CREQ loop, in order.
def rcfw.write(write_idx: U32, t: Tr) -> Tr: Tr.emit(CALL_RING_W(), write_idx, SLOT16(), t)

def rcfw.prod_write(write_idx: U32, first: Bool, t: Tr) -> Tr:
  Tr.emit(CALL_BAR0(), rcfw.prod_at(), rcfw.first_flag(rcfw.prod_of(write_idx), first),
          Tr.emit(CALL_BARRIER(), 0, 0, t))

def rcfw.trig_write(t: Tr) -> Tr: Tr.emit(CALL_BAR0(), rcfw.trig_at(), rcfw.trig_val(), t)

def rcfw.creq_read(read_idx: U32, t: Tr) -> Tr: Tr.emit(CALL_RING_R(), read_idx, 0, t)

def rcfw.creq_wait(t: Tr) -> Tr: Tr.emit(CALL_WAIT(), 20000, 0, t)

# :155 `assert ret.status == 0` -- THE SECOND REFUSAL, and it fires INSIDE the
# `while True`, so a refused rcfw's trace ends after the CREQ read and before
# the NQ_ARM doorbell. `rcfw_status_refused` is that truncation.
def rcfw.status_ok(status: U32) -> Bool: U32.is_zero(status)

# `poll`, :219-225. READ, then the index bump, then the CQ doorbell, then the
# status check on byte 25. `poll_seq` is the ordered identity trace and
# `poll_cq_slot` / `poll_cq_epoch` are the two doorbell arguments.
def qp.poll_ready(cq_size: U32, cq_stride: U32, read_idx: U32, toggle: U32) -> Bool:
  cqe.ready(toggle, read_idx)

def qp.poll_cq_slot(read_idx: U32) -> U32: U32.mod(read_idx, CQ_ENTRIES())
def qp.poll_cq_epoch(read_idx: U32) -> U32: cqe.epoch(read_idx)

def qp.poll_done(+read_idx: U32, cq_id: U32, db_off: U32, status: U32, +t: Tr) -> Tr:
  # :224 `assert raw[25] == 0` -- THE THIRD REFUSAL. Byte 25 is `status`, the
  # FIFTH field of `struct_cq_base`; `cqe_status_at` pins the offset BY NAME.
  Bool.pick(Tr, U32.is_zero(status),
    dev.doorbell(cq_id, DBC_DBC_TYPE_CQ(), qp.poll_cq_slot(read_idx), qp.poll_cq_epoch(read_idx),
                 db_off, Tr.emit(CALL_RING_R(), read_idx, CQ_STRIDE(), t)),
    Tr.refuse(t))

# `post_send`, :227-232. FOUR things in order and the order is the protocol:
#   1. the 48-byte work queue element at `i % slots * stride`
#   2. the 8-byte msn entry in the AUX table PAST the ring, at `size + i%slots*8`
#   3. the write index bump, which is what makes the doorbell's `n+1` mean the
#      slot AFTER this one
#   4. the SQ doorbell
# `post_send_seq` is the ordered identity trace; `msn_after` and `wi_after` are
# the two pieces of state it advances.
def qp.post_send_seq(+sq_size: U32, +sq_stride: U32, +wi: U32, t: Tr) -> Tr:
  Tr.emit(CALL_RING_W(), q.write_off(wi, sq_size, sq_stride, True{}), AUX_ENTRY(),
          Tr.emit(CALL_RING_W(), q.write_off(wi, sq_size, sq_stride, False{}), sq_stride, t))

# THE MSN ENTRY'S VALUE IS NOT PACKED HERE, deliberately. There was a
# `qp.post_send_msn` that folded `msn.hi` and `msn.lo` into one `U32` so the
# trace could carry it, and that packing is INVENTED -- it is not a number
# Python ever computes, and it exists only to fill an argument. The msn's two
# halves have their own rows (`msn_*_HI` / `msn_*_LO`), which is where a wrong
# 48/24/24 belongs, and `CALL_RING_W` carries the OFFSET and the LENGTH, which
# is what `qp.post_send_seq` writes. `post_send_msn_2_calls` is the row that
# says the msn write is the SECOND `CALL_RING_W` and not a third kind of call.

def qp.post_send_psn(psn: U32, size: U32) -> U32: msn.next_of(msn.mask(psn), size)

# :232 -- `doorbell(qpn, SQ, write_idx % RING_ENTRIES, (write_idx // RING_ENTRIES) & 1)`
# AFTER the increment, so the doorbell rings the NEXT slot.
def qp.post_send_slot(wi_after: U32) -> U32: U32.mod(wi_after, RING_ENTRIES())
def qp.post_send_epoch(wi_after: U32) -> U32: U32.and(U32.div(wi_after, RING_ENTRIES()), 1)

# `post_recv`, :234-237. THREE things and there is NO msn: a receive consumes no
# packet send numbers, because the psns are the SENDER's. `post_recv_seq` has
# two ring writes' worth of nothing -- one `CALL_RING_W` and one `CALL_DB` --
# and `post_recv_no_msn` is the row that says the msn call is absent.
def qp.post_recv_seq(rq_size: U32, +rq_stride: U32, wi: U32, t: Tr) -> Tr:
  Tr.emit(CALL_RING_W(), q.write_off(wi, rq_size, rq_stride, False{}), rq_stride, t)

def qp.post_recv_slot(wi_after: U32) -> U32: U32.mod(wi_after, RING_ENTRIES())
def qp.post_recv_epoch(wi_after: U32) -> U32: U32.and(U32.div(wi_after, RING_ENTRIES()), 1)

# `register_mem` / `unregister_mem`, :183-189.
def dev.register_mem(level: U32, log_page_size: U32, size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MR(), mr.lvlpg(level, log_page_size), size, t)

def dev.unregister_mem(key: U32, t: Tr) -> Tr: Tr.emit(CALL_MR(), key, 0, t)

# `fini`, :160 -- one HWRM, `func_drv_unrgtr`.
def dev.fini(t: Tr) -> Tr: Tr.emit(CALL_FINI(), 0, 0, t)

# `_open_l2`, :167-180. Four calls and the two masks that are one line apart.
def dev.open_l2(nq_id: U32, ri: U32, ci: U32, +vnic_id: U32, mac48: U32, t: Tr) -> Tr:
  Tr.emit(CALL_L2_FILTER(), l2_filter_flags(), mac48,
          Tr.emit(CALL_L2_FILTER(), l2_filter_enables(), vnic_id,
            Tr.emit(CALL_VNIC(), vnic_enables(), vnic_id,
              Tr.emit(CALL_VNIC(), RING_ALLOC_REQ_RING_TYPE_L2_CMPL(), nq_id, t))))

# `build_pbl`'s trace, :27-37. ONE allocation for the table, a SECOND for the
# top level, and the REFUSAL between them: `pbl_build_seq` shows both
# allocations and `pbl_build_refused` shows the first and nothing else, which
# is what `pbl_deep_ALLOCS == 1` says on the oracle side.
def pbl.build_seq(+n: U32, t: Tr) -> Tr:
  Tr.emit(CALL_ALLOC(), pbl.table_bytes(n), pbl.level_of(n), t)

def pbl.build_top(t: Tr) -> Tr: Tr.emit(CALL_ALLOC(), PBL_TOP_BYTES(), PBL_MAX_PAGES(), t)

# THE PAGE-TABLE REFUSAL, :34. `pbl.build_seq` has already recorded the table
# allocation by the time this runs, so the truncated trace's length IS the
# claim "one allocation happened and then the assert fired".
def pbl.build_check(n: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, pbl.refuses(n), t, Tr.refuse(t))

# ===========================================================================
# THE GATE, PART ONE: the constants, the struct field lists, the 64-bit words
# and the two pack formats.
#
# EVERY `name=value` LINE here must appear, identically, in
# `.agents/slop/bnxt_oracle.txt`, which is produced by CALLING CPython:
#
#   python3 -c "import sys; sys.path.insert(0,'.'); \
#     exec(open('.agents/slop/bnxt_oracle.py').read())" > .agents/slop/bnxt_oracle.txt
#
# and in the NATIVE lane:
#
#   ./bin/bend tinybendygrad/runtime/support/rdma/bnxtdev.bend -o .agents/slop/bnxtdev \
#     && .agents/slop/bnxtdev
#
# THE THREE LANES ARE DIFFED, not the row NAMES.
#
# A CONSTANT IS GATED BOTH DIRECTIONS, and that is the point: `c_DBC_DBC_TYPE_RQ`
# says the number is right, and `db_3_HI` says a FUNCTION USING IT is right. A
# file with the right constants and the wrong formula fails the second row; a
# file with the right formula and the wrong constant fails the first. Neither
# row alone can be satisfied by the other's mistake.
# ===========================================================================
# the POPCOUNT and the eight nibbles. Both are folds over a 32-bit word, and
# both are the check that a transposed digit pair cannot survive: the decimal
# `c_BNXT_RTR_MASK=68490669` and the eight nibbles are read off the SAME def,
# so a wrong digit moves a nibble and a wrong def moves both.
#
# THE NIBBLE SHIFT IS A `Nat` PARAMETER, not a computed value -- `U32.shrn`
# takes a `Nat` and there is no way to compute one from a `U32` index, which is
# the general reason a bit-packer with runtime field positions is unwritable.
# The eight nibbles are ONE row joined by spaces, not eight rows, because a
# `do` block cannot be sequenced inside a `match` arm in this Bend and eight
# separate `IO.print` calls is a workaround that says nothing extra.
def mask_pop(v: U32) -> U32: bs.count.go(32n, 0, v, 0)

def mask_nibs.go(n: Nat, +sh: Nat, +v: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: mask_nibs.go(m, Nat.add(sh, 4n), v,
      List.append(&2, U32, acc, [U32.shrn(U32.and(U32.shrn(v, sh), 15), 0n)]))

def mask_nibs(v: U32) -> List<&2, U32>: mask_nibs.go(8n, 0n, v, Nil{})

def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("c_BNXT_DEBUG", BNXT_DEBUG())
    urow("c_BNXT_ACCESS", BNXT_ACCESS())
    urow("c_BNXT_INIT_MASK", BNXT_INIT_MASK())
    urow("c_BNXT_RTR_MASK", BNXT_RTR_MASK())
    urow("c_BNXT_RTS_MASK", BNXT_RTS_MASK())
    urow("c_BNXT_CHIMP_COMM", BNXT_CHIMP_COMM())
    urow("c_BNXT_CHIMP_COMM_TRIGGER", BNXT_CHIMP_COMM_TRIGGER())
    urow("c_WQE_SIZE", WQE_SIZE())
    urow("c_RING_ENTRIES", RING_ENTRIES())
    urow("c_CQ_ENTRIES", CQ_ENTRIES())
    urow("c_MTU", MTU())
    urow("c_BNXT_BACKING_STORE_LEN", BS_LEN())
    # bnxtdev.py:9 the four masks, NIBBLE BY NIBBLE from the least significant
    # end, so a transposed digit pair inside `0x41515ad` cannot hide behind a
    # correct whole. `mask_nib` is the row that does the splitting.
    urow("c_MASK_ACCESS_POP", mask_pop(BNXT_ACCESS()))
    urow("c_MASK_INIT_MASK_POP", mask_pop(BNXT_INIT_MASK()))
    urow("c_MASK_RTR_MASK_POP", mask_pop(BNXT_RTR_MASK()))
    urow("c_MASK_RTS_MASK_POP", mask_pop(BNXT_RTS_MASK()))
    lrow("c_MASK_ACCESS_NIBS", mask_nibs(BNXT_ACCESS()))
    lrow("c_MASK_INIT_MASK_NIBS", mask_nibs(BNXT_INIT_MASK()))
    lrow("c_MASK_RTR_MASK_NIBS", mask_nibs(BNXT_RTR_MASK()))
    lrow("c_MASK_RTS_MASK_NIBS", mask_nibs(BNXT_RTS_MASK()))
    urow("c_DBC_DBC_XID_MASK", DBC_DBC_XID_MASK())
    urow("c_DBC_DBC_PATH_ROCE", DBC_DBC_PATH_ROCE())
    urow("c_BNXT_QPLIB_DBR_VALID", BNXT_QPLIB_DBR_VALID())
    urow("c_DBC_DBC_INDEX_MASK", DBC_DBC_INDEX_MASK())
    urow("c_BNXT_QPLIB_DBR_EPOCH_SHIFT", BNXT_QPLIB_DBR_EPOCH_SHIFT())
    urow("c_SQ_SEND_FLAGS_SIGNAL_COMP", SQ_SEND_FLAGS_SIGNAL_COMP())
    urow("c_SQ_MSN_SEARCH_START_IDX_SFT", SQ_MSN_SEARCH_START_IDX_SFT())
    urow("c_SQ_MSN_SEARCH_NEXT_PSN_SFT", SQ_MSN_SEARCH_NEXT_PSN_SFT())
    urow("c_CQ_BASE_TOGGLE", CQ_BASE_TOGGLE())
    urow("c_PTU_PTE_VALID", PTU_PTE_VALID())
    urow("c_PTU_PTE_LAST", PTU_PTE_LAST())
    urow("c_PTU_PTE_NEXT_TO_LAST", PTU_PTE_NEXT_TO_LAST())
    urow("c_DBC_DBC_TYPE_SQ", DBC_DBC_TYPE_SQ())
    urow("c_DBC_DBC_TYPE_NQ_ARM", DBC_DBC_TYPE_NQ_ARM())
    urow("c_DBC_DBC_TYPE_RQ", DBC_DBC_TYPE_RQ())
    urow("c_DBC_DBC_TYPE_CQ", DBC_DBC_TYPE_CQ())
    urow("c_CMDQ_INIT_CMDQ_SIZE_SFT", CMDQ_INIT_CMDQ_SIZE_SFT())
    urow("c_RCFW_COMM_BASE_OFFSET", RCFW_COMM_BASE_OFFSET())
    urow("c_RCFW_PF_VF_COMM_PROD_OFFSET", RCFW_PF_VF_COMM_PROD_OFFSET())
    urow("c_RCFW_COMM_TRIG_OFFSET", RCFW_COMM_TRIG_OFFSET())
    urow("c_RCFW_CMDQ_TRIG_VAL", RCFW_CMDQ_TRIG_VAL())
    urow("c_FIRMWARE_FIRST_FLAG", FIRMWARE_FIRST_FLAG())
    urow("c_BNXT_HWRM_NO_CMPL_RING", BNXT_HWRM_NO_CMPL_RING())
    urow("c_BNXT_HWRM_TARGET", BNXT_HWRM_TARGET())
    urow("c_HWRM_MAX_REQ_LEN", HWRM_MAX_REQ_LEN())
    urow("c_CREQ_BASE_V", CREQ_BASE_V())
    urow("c_CREQ_BASE_TYPE_QP_EVENT", CREQ_BASE_TYPE_QP_EVENT())
    urow("c_CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION", CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION())
    urow("c_RING_ALLOC_REQ_RING_TYPE_NQ", RING_ALLOC_REQ_RING_TYPE_NQ())
    urow("c_RING_ALLOC_REQ_RING_TYPE_L2_CMPL", RING_ALLOC_REQ_RING_TYPE_L2_CMPL())
    urow("c_RING_ALLOC_REQ_RING_TYPE_RX", RING_ALLOC_REQ_RING_TYPE_RX())
    urow("c_RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID())
    urow("c_RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID())
    urow("c_RING_ALLOC_REQ_INT_MODE_MSIX", RING_ALLOC_REQ_INT_MODE_MSIX())
    urow("c_VNIC_CFG_REQ_ENABLES_MRU", VNIC_CFG_REQ_ENABLES_MRU())
    urow("c_VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID())
    urow("c_VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR", CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID())
    urow("c_FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE", FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE())
    urow("c_CMDQ_REGISTER_MR_LVL_SFT", CMDQ_REGISTER_MR_LVL_SFT())
    urow("c_CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT", CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT())
    urow("c_CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE())
    urow("c_CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE", CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE())
    urow("c_CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", CMDQ_REGISTER_MR_FLAGS_ALLOC_MR())
    urow("c_CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED", CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED())
    urow("c_CMDQ_CREATE_QP_TYPE_RC", CMDQ_CREATE_QP_TYPE_RC())
    urow("c_CMDQ_MODIFY_QP_QP_TYPE_RC", CMDQ_MODIFY_QP_QP_TYPE_RC())
    urow("c_CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4())
    urow("c_CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", CMDQ_MODIFY_QP_PATH_MTU_MTU_4096())
    # the four COMPOSED words, which are a different claim from any single
    # constant: each is a mis-pairing risk and one is a line away from another.
    urow("c_L2_ENABLES", vnic_enables())
    urow("c_L2_FILTER_ENABLES", l2_filter_enables())
    urow("c_RING_ALLOC_L2_ENABLES", ra_l2_enables())
    urow("c_RING_ALLOC_RX_ENABLES", ra_rx_enables())
    urow("c_REGISTER_MR_ACCESS", U32.or(CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE(), CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE()))
    # ctypes.sizeof, which :133 and :194 both ask for.
    urow("c_SIZEOF_CQ_BASE", SIZEOF_CQ_BASE())
    urow("c_SIZEOF_RESP_HDR", SIZEOF_RESP_HDR())
    urow("c_SIZEOF_CMDQ_INIT", SIZEOF_CMDQ_INIT())
    urow("c_SIZEOF_CMDQ_ADD_GID", SIZEOF_CMDQ_ADD_GID())
    urow("c_SLOTS_CMDQ_ADD_GID", rcfw.slots_of(SIZEOF_CMDQ_ADD_GID()))
    urow("c_SIZEOF_CMDQ_INITIALIZE_FW", SIZEOF_CMDQ_INITIALIZE_FW())
    urow("c_SLOTS_CMDQ_INITIALIZE_FW", rcfw.slots_of(SIZEOF_CMDQ_INITIALIZE_FW()))
    urow("c_SIZEOF_CMDQ_CREATE_CQ", SIZEOF_CMDQ_CREATE_CQ())
    urow("c_SLOTS_CMDQ_CREATE_CQ", rcfw.slots_of(SIZEOF_CMDQ_CREATE_CQ()))
    urow("c_SIZEOF_CMDQ_CREATE_QP", SIZEOF_CMDQ_CREATE_QP())
    urow("c_SLOTS_CMDQ_CREATE_QP", rcfw.slots_of(SIZEOF_CMDQ_CREATE_QP()))
    urow("c_SIZEOF_CMDQ_MODIFY_QP", SIZEOF_CMDQ_MODIFY_QP())
    urow("c_SLOTS_CMDQ_MODIFY_QP", rcfw.slots_of(SIZEOF_CMDQ_MODIFY_QP()))
    urow("c_SIZEOF_CMDQ_REGISTER_MR", SIZEOF_CMDQ_REGISTER_MR())
    urow("c_SLOTS_CMDQ_REGISTER_MR", rcfw.slots_of(SIZEOF_CMDQ_REGISTER_MR()))
    urow("c_SIZEOF_CMDQ_DEREGISTER_MR", SIZEOF_CMDQ_DEREGISTER_MR())
    urow("c_SLOTS_CMDQ_DEREGISTER_MR", rcfw.slots_of(SIZEOF_CMDQ_DEREGISTER_MR()))

# ---------------------------------------------------------------------------
# THE STRUCT FIELD LISTS, BY NAME AND IN ORDER.
#
# EVERY FIELD IS NAMED AT ITS OWN CALL SITE. That is deliberate and it is the
# whole requirement: a wrong field ORDER moves a row, and a right field COUNT
# with a wrong order STILL moves one, because the row is named after the field
# and not after its position. A walk that printed `f_struct_cq_base_<i>_AT`
# would have been shorter and would have passed a transposed layout.
#
# The lists themselves came out of `_real_fields_` -- `ctypes._fields_` on these
# `c.record` structs is the opaque `('_mem_',)`, so plain ctypes cannot see the
# names at all. `.agents/slop/bnxt_structs.py` reads them off the RUNTIME class.
# ---------------------------------------------------------------------------
def nth_at(+xs: List<&2, U32>, i: Nat) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, i), 0)

def name_at(+xs: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def frow(+pfx: String, +nm: String, +ats: List<&2, U32>, +ws: List<&2, U32>, +i: Nat) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([pfx, "_", nm, "_AT"]), nth_at(ats, i))
    urow(String.concat([pfx, "_", nm, "_W"]), nth_at(ws, i))


def t_struct() -> IO(Unit):
  do IO<Unit>:
    nrow("f_struct_cq_base_NAMES", struct_cq_base_names())
    nrow("f_struct_hwrm_resp_hdr_NAMES", struct_hwrm_resp_hdr_names())
    nrow("f_struct_cmdq_init_NAMES", struct_cmdq_init_names())
    nrow("f_struct_cmdq_base_NAMES", struct_cmdq_base_names())
    frow("f_struct_cq_base", "reserved64_1", struct_cq_base_at(), struct_cq_base_w(), 0n)
    frow("f_struct_cq_base", "reserved64_2", struct_cq_base_at(), struct_cq_base_w(), 1n)
    frow("f_struct_cq_base", "reserved64_3", struct_cq_base_at(), struct_cq_base_w(), 2n)
    frow("f_struct_cq_base", "cqe_type_toggle", struct_cq_base_at(), struct_cq_base_w(), 3n)
    frow("f_struct_cq_base", "status", struct_cq_base_at(), struct_cq_base_w(), 4n)
    frow("f_struct_cq_base", "reserved16", struct_cq_base_at(), struct_cq_base_w(), 5n)
    frow("f_struct_cq_base", "opaque", struct_cq_base_at(), struct_cq_base_w(), 6n)
    frow("f_struct_hwrm_resp_hdr", "error_code", struct_hwrm_resp_hdr_at(), struct_hwrm_resp_hdr_w(), 0n)
    frow("f_struct_hwrm_resp_hdr", "req_type", struct_hwrm_resp_hdr_at(), struct_hwrm_resp_hdr_w(), 1n)
    frow("f_struct_hwrm_resp_hdr", "seq_id", struct_hwrm_resp_hdr_at(), struct_hwrm_resp_hdr_w(), 2n)
    frow("f_struct_hwrm_resp_hdr", "resp_len", struct_hwrm_resp_hdr_at(), struct_hwrm_resp_hdr_w(), 3n)
    frow("f_struct_cmdq_init", "cmdq_pbl", struct_cmdq_init_at(), struct_cmdq_init_w(), 0n)
    frow("f_struct_cmdq_init", "cmdq_size_cmdq_lvl", struct_cmdq_init_at(), struct_cmdq_init_w(), 1n)
    frow("f_struct_cmdq_init", "creq_ring_id", struct_cmdq_init_at(), struct_cmdq_init_w(), 2n)
    frow("f_struct_cmdq_init", "prod_idx", struct_cmdq_init_at(), struct_cmdq_init_w(), 3n)
    frow("f_struct_cmdq_base", "opcode", struct_cmdq_base_at(), struct_cmdq_base_w(), 0n)
    frow("f_struct_cmdq_base", "cmd_size", struct_cmdq_base_at(), struct_cmdq_base_w(), 1n)
    frow("f_struct_cmdq_base", "flags", struct_cmdq_base_at(), struct_cmdq_base_w(), 2n)
    frow("f_struct_cmdq_base", "cookie", struct_cmdq_base_at(), struct_cmdq_base_w(), 3n)
    frow("f_struct_cmdq_base", "resp_size", struct_cmdq_base_at(), struct_cmdq_base_w(), 4n)
    frow("f_struct_cmdq_base", "reserved8", struct_cmdq_base_at(), struct_cmdq_base_w(), 5n)
    frow("f_struct_cmdq_base", "resp_addr", struct_cmdq_base_at(), struct_cmdq_base_w(), 6n)
def cqe_status_at() -> String: name_at(struct_cq_base_names(), 4n)

def cqe_toggle_at() -> String: name_at(struct_cq_base_names(), 3n)
def resp_hdr_len_at() -> String: name_at(struct_hwrm_resp_hdr_names(), 3n)

def t_offset_names() -> IO(Unit):
  do IO<Unit>:
    srow("f_CQE_TOGGLE_FIELD", cqe_toggle_at())
    srow("f_CQE_STATUS_FIELD", cqe_status_at())
    srow("f_RESP_HDR_FIRST", name_at(struct_hwrm_resp_hdr_names(), 0n))
    srow("f_RESP_HDR_LEN_FIELD", resp_hdr_len_at())

def WQE_KIND_AT() -> U32: 16

# ---------------------------------------------------------------------------
# WORD 0, AND THE COMMENT `ops_rdma.bend` GETS WRONG. See the header: the code
# at `ops_rdma.bend:1490-1492` is right and the comment at :224-225 is
# INVERTED. These rows print the three bytes out of their places so the claim
# is `kind at 16, flags at 8, type at 0` and not a restatement of `wqe.hdr0`.
# ---------------------------------------------------------------------------
# WHAT `ops_rdma.bend:224-225` CLAIMS: `type << 16 | flags << 8 | kind`. Both
# the claim and its refutation are rows, so the disagreement is a NUMBER in a
# committed artefact rather than an argument in a commit message.
# `type << 16 | flags << 8 | kind`, with each byte taken from where the REAL
# word has it. It evaluates to 259 for a send and 8388611 for a receive, and the
# real word is 196864 and 196736, so the claim is wrong by three orders of
# magnitude on the send and it is a row rather than a sentence.
def hdr0_comment_says(+recv: Bool) -> U32:
  U32.or(U32.shln(Bool.pick(U32, recv, RECV_KIND(), 0), U32.to_nat(WQE_KIND_AT())),
         U32.or(U32.shln(Bool.pick(U32, recv, 0, SQ_SEND_FLAGS_SIGNAL_COMP()), 8n), WQE_KIND()))

def t_hdr0() -> IO(Unit):
  do IO<Unit>:
    urow("hdr0_SEND_REAL", wqe.hdr0(False{}))
    urow("hdr0_SEND_KIND_AT16", U32.and(U32.shrn(wqe.hdr0(False{}), 16n), 255))
    urow("hdr0_SEND_FLAGS_AT8", U32.and(U32.shrn(wqe.hdr0(False{}), 8n), 255))
    urow("hdr0_SEND_TYPE_AT0", U32.and(wqe.hdr0(False{}), 255))
    urow("hdr0_SEND_COMMENT_SAYS", hdr0_comment_says(False{}))
    brow("hdr0_SEND_COMMENT_IS_RIGHT", U32.is_eq(hdr0_comment_says(False{}), wqe.hdr0(False{})))
    urow("hdr0_RECV_REAL", wqe.hdr0(True{}))
    urow("hdr0_RECV_KIND_AT16", U32.and(U32.shrn(wqe.hdr0(True{}), 16n), 255))
    urow("hdr0_RECV_FLAGS_AT8", U32.and(U32.shrn(wqe.hdr0(True{}), 8n), 255))
    urow("hdr0_RECV_TYPE_AT0", U32.and(wqe.hdr0(True{}), 255))
    urow("hdr0_RECV_COMMENT_SAYS", hdr0_comment_says(True{}))
    brow("hdr0_RECV_COMMENT_IS_RIGHT", U32.is_eq(hdr0_comment_says(True{}), wqe.hdr0(True{})))

# ---------------------------------------------------------------------------
# THE 64-BIT WORDS, in HALVES. `db_value` (:13-15) and `msn_entry` (:20-24),
# eight cases each, and every one is the REAL function called by the oracle.
# The fixtures are chosen so a mask that is vacuous at one scale shows: the
# msn cases straddle 2^24 (`msn_3` at `psn == 0xffffff`), which is what makes
# `& 0xffffff` visible at all.
# ---------------------------------------------------------------------------
def db_row(+i: U32, xid: U32, typ: U32, ix: U32, ep: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["db_", U32.show(i), "_HI"]), db.hi(xid, typ))
    urow(String.concat(["db_", U32.show(i), "_LO"]), db.lo(ix, ep))

def t_db() -> IO(Unit):
  do IO<Unit>:
    db_row(0, 0, DBC_DBC_TYPE_SQ(), 0, 0)
    db_row(1, 5, DBC_DBC_TYPE_SQ(), 0, 0)
    db_row(2, 74565, DBC_DBC_TYPE_RQ(), 1, 0)
    db_row(3, 74565, DBC_DBC_TYPE_CQ(), 4097, 1)
    db_row(4, 1048575, DBC_DBC_TYPE_NQ_ARM(), 255, 1)
    db_row(5, 7, DBC_DBC_TYPE_NQ_ARM(), 256, 0)
    db_row(6, 524287, DBC_DBC_TYPE_SQ(), 16777215, 1)
    db_row(7, 524288, DBC_DBC_TYPE_RQ(), 4095, 1)

def msn_row(+i: U32, wqe_idx: U32, +psn: U32, +size: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["msn_", U32.show(i), "_HI"]), msn.hi(msn.slot_of(wqe_idx), msn.next_of(msn.mask(psn), size)))
    urow(String.concat(["msn_", U32.show(i), "_LO"]), msn.lo(msn.next_of(msn.mask(psn), size), msn.mask(psn)))
    urow(String.concat(["msn_", U32.show(i), "_NEXT"]), msn.next_of(msn.mask(psn), size))

# ---------------------------------------------------------------------------
# THE TWO PACKS. Eight words of the send header and seven of the receive, plus
# the lengths and the scatter-gather element. `wqe_1` is the ZERO case and
# `wqe_2` the LARGE one; between them they see `size` in word 2 on the send
# and NO size at all on the receive.
# ---------------------------------------------------------------------------
def t_msn() -> IO(Unit):
  do IO<Unit>:
    msn_row(0, 0, 0, 100)
    msn_row(1, 0, 4095, 4096)
    msn_row(2, 1, 4096, 1)
    msn_row(3, 4095, 16777215, 2)
    msn_row(4, 4096, 16777215, 4096)
    msn_row(5, 7, 16777200, 0)
    msn_row(6, 131071, 1, 4096)
    msn_row(7, 4097, 8388608, 8192)

def wqe_row(i: U32, +va_lo: U32, +key: U32, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +s : List<&2, U32> = wqe.words(False{}, size, va_lo, 0, key)
    +r : List<&2, U32> = wqe.words(True{}, size, va_lo, 0, key)
    +p : String = U32.show(i)
    urow(String.concat(["wqe_", p, "_S_LEN"]), WQE_BYTES())
    urow(String.concat(["wqe_", p, "_R_LEN"]), WQE_BYTES())
    lrow(String.concat(["wqe_", p, "_S"]), List.take(&2, U32, s, 8n))
    lrow(String.concat(["wqe_", p, "_R"]), List.take(&2, U32, r, 7n))
    urow(String.concat(["wqe_", p, "_S_VA_LO"]), nth_at(s, 8n))
    urow(String.concat(["wqe_", p, "_S_VA_HI"]), nth_at(s, 9n))
    urow(String.concat(["wqe_", p, "_R_VA_LO"]), nth_at(r, 8n))
    urow(String.concat(["wqe_", p, "_R_VA_HI"]), nth_at(r, 9n))


def t_wqe() -> IO(Unit):
  do IO<Unit>:
    wqe_row(0, 4096, 170, 64)
    wqe_row(1, 0, 0, 0)
    wqe_row(2, 3735928559, 4294967295, 4096)


# ===========================================================================
# THE GATE, PART TWO: the page table, the queue, the completion status, the
# logging table, the gid/mac unpacking and the device index arithmetic.
#
# THE PAGE-TABLE FIXTURE. The `pbl_q_*` rows need a physical address to
# encode, and the oracle builds one with its `FakePci`: page `i` is
# `0x7a0000000000 + i * 0x1000`, so the high half is 31232 for every entry and
# the low half is `i * 4096`. Those two numbers are a FIXTURE, shared by both
# sides, and nothing is gated on them: what is gated is that
# `pbl.entry_lo_at` turns that address plus the right flags into the entry
# `build_pbl` actually wrote, and that `pbl.entry_hi` leaves the high half
# alone. `pbl_hi_untouched` is the row for the second half of that claim.
# ===========================================================================
def PBL_FIX_HI() -> U32: 31232
def pbl_fix_lo(i: U32) -> U32: U32.mul(i, PAGE())

def pbl.alloc0_of(+n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(pbl.level_of(n), 0), 0, pbl.table_bytes(n))

def pbl.alloc1_of(n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(pbl.level_of(n), 2), PBL_TOP_BYTES(), 0)

# how many allocations `build_pbl` performs: NONE for the one-page shortcut, ONE
# for a single-level table, TWO for a two-level one, and ONE more attempt at a
# table that will be REFUSED.
# `build_pbl` performs 0, 1 or 2 `alloc_sysmem` calls -- one per LEVEL, and none
# at all for the one-page shortcut -- so the count IS the level. `level_of(n) - 1`
# is the wrong formula and it UNDERFLOWS at level 0: `pbl_q_1_ALLOCS` printed
# 4294967295 and said so.
def pbl.allocs_of(+n: U32) -> U32: pbl.level_of(n)

def pbl_row(+n: U32) -> IO(Unit):
  do IO<Unit>:
    +nm : String = String.concat(["pbl_q_", U32.show(n)])
    urow(String.concat([nm, "_LEVEL"]), pbl.level_of(n))
    brow(String.concat([nm, "_BASE_IS_FIRST"]), U32.is_eq(pbl.level_of(n), 0))
    urow(String.concat([nm, "_ALLOCS"]), pbl.allocs_of(n))
    urow(String.concat([nm, "_ALLOC0"]), pbl.alloc0_of(n))
    # the LAST entry and the one before it, both directions
    urow(String.concat([nm, "_ENTRYLAST_HI"]), pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRYLAST_LO"]), pbl.entry_lo_at(pbl_fix_lo(U32.sub(n, 1)), True{}, U32.sub(n, 1), n))
    urow(String.concat([nm, "_ENTRYN1_HI"]), pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRYN1_LO"]), pbl.entry_lo_at(pbl_fix_lo(U32.sub(n, 2)), True{}, U32.sub(n, 2), n))
    urow(String.concat([nm, "_ENTRY0_HI"]), pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRY0_LO"]), pbl.entry_lo_at(pbl_fix_lo(0), True{}, 0, n))
    urow(String.concat([nm, "_ALLOC1"]), pbl.alloc1_of(n))
    urow(String.concat([nm, "_TOP_BYTES"]), PBL_TOP_BYTES())

def t_pbl() -> IO(Unit):
  do IO<Unit>:
    pbl_row(1)
    pbl_row(2)
    pbl_row(511)
    pbl_row(512)
    pbl_row(513)
    pbl_row(1024)
    pbl_row(1025)
    # the one-paddr shortcut returns the address ITSELF: no VALID bit, no
    # allocation, and the value is not an encoded entry at all.
    urow("pbl_one_LEVEL", pbl.level_of(1))
    brow("pbl_one_NOFLAGS", Bool.not(pbl.valid_of(pbl_fix_lo(0))))
    brow("pbl_one_BASE_IS_INPUT", U32.is_eq(pbl.entry_hi(PBL_FIX_HI()), PBL_FIX_HI()))
    # `queue=False`: NO last and NO next-to-last on the final entry.
    urow("pbl_noq_LEVEL", pbl.level_of(4))
    urow("pbl_noq_ENTRYLAST_HI", pbl.entry_hi(PBL_FIX_HI()))
    urow("pbl_noq_ENTRYLAST_LO", pbl.entry_lo_at(pbl_fix_lo(3), False{}, 3, 4))
    urow("pbl_noq_ENTRY0_HI", pbl.entry_hi(PBL_FIX_HI()))
    urow("pbl_noq_ENTRY0_LO", pbl.entry_lo_at(pbl_fix_lo(0), False{}, 0, 4))
    # THE ENCODE/DECODE PAIR. Re-encode a decoded entry and get the original:
    # this is the OTHER DIRECTION the page table has to answer in.
    brow("pbl_hi_untouched", U32.is_eq(pbl.entry_hi(4242), 4242))
    brow("pbl_roundtrip_last", U32.is_eq(pbl.encode(4096, True{}, True{}), 4099))
    brow("pbl_roundtrip_ntl", U32.is_eq(pbl.encode(4096, True{}, False{}), 4101))
    brow("pbl_decode_last", pbl.has_last(4099))
    brow("pbl_decode_ntl", pbl.has_ntl(4101))
    brow("pbl_decode_valid", pbl.valid_of(4097))
    brow("pbl_flags_exclusive", pbl.flags_exclusive(4099))
    brow("pbl_flags_exclusive_ntl", pbl.flags_exclusive(4101))
    brow("pbl_flags_exclusive_neither", pbl.flags_exclusive(4097))
    urow("pbl_decode_addr_last", pbl.addr_of(4099))
    urow("pbl_decode_addr_ntl", pbl.addr_of(4101))
    # THE `len(table_paddrs) <= 512` BOUNDARY. 512 pages is LEGAL and 513
    # refuses, and M10 moved NOTHING until these two rows existed: every other
    # `pbl_q_*` fixture is 1, 2 or 3 pages, so no fixture reached the limit.
    brow("pbl_edge_262144_REFUSED", pbl.refuses(262144))
    brow("pbl_edge_262145_REFUSED", pbl.refuses(262145))
    brow("pbl_edge_differ", Bool.not(pbl.refuses(262144)))
    # the LEVEL at the boundary, not only the refusal: `refuses` is `>` and
    # `level_of` is `<=`, and M10 mutates the `<=`, so only a row that reads
    # `level_of` can see it. Two rows for one boundary is not redundancy, it is
    # two different predicates.
    urow("pbl_edge_262144_LEVEL", pbl.level_of(262144))
    urow("pbl_edge_262145_LEVEL", pbl.level_of(262145))
    brow("pbl_edge_level_differ", Bool.not(U32.is_eq(pbl.level_of(262144), pbl.level_of(262145))))
    # THE REFUSAL, :34. `ceildiv(512*512 + 1, 512) == 513 > 512`.
    urow("pbl_deep_LEVEL", pbl.level_of(262145))
    brow("pbl_deep_REFUSED", pbl.refuses(262145))
    brow("pbl_deep_not_refused", Bool.not(pbl.refuses(262144)))
    # ONE allocation happened and THEN the assert fired, which is what the truncated
    # trace length claims. `allocs_of(262144)` is 2 because 512 pages is not
    # over the limit -- the refused case is 262145.
    urow("pbl_deep_ALLOCS", Bool.pick(U32, pbl.refuses(262145), 1, pbl.allocs_of(262145)))

# `0x5a` repeated is what the oracle WRITES into the queue, so a read of the
# first four bytes back is `0x5a5a5a5a` whatever the stride. The row says the
# ring read returns what was written, not a computed offset.
def FILL_BYTE() -> U32: 1515870810

def aq_off(+nm: String, +j: U32, +i: U32, ns: U32, +sz: U32, +stride: U32, aux: Bool) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([nm, "_W", U32.show(j)]), q.write_off(i, sz, stride, False{}))
    urow(String.concat([nm, "_WL", U32.show(j)]), q.write_len(sz, stride, False{}, stride))
    urow(String.concat([nm, "_WA", U32.show(j)]), q.write_off(i, sz, stride, True{}))

# ===========================================================================
# THE QUEUE. `alloc_queue` (:47-50) and `BNXTQueue.read`/`write` (:42-45), and
# the oracle for these rows calls the REAL `alloc_queue` against a fake PCI and
# reads the slice bounds back out of its MMIO stand-in -- so `aq_*_W*` is the
# offset the source computed, not the offset this file believes it computed.
#
# SIX FIXTURES and between them they separate every claim: a default 16-byte
# queue (256 slots), the same with the aux msn table (so `size` is 6144 while
# the queue is still 4096), a 128-byte queue with aux, a 128-byte queue with
# aux FALSE (so `size` is 4096 and the aux base moves with it), a 4096-entry
# 32-byte queue, and a THREE-entry queue where the page default does not apply.
# ===========================================================================
def aq_row(i: U32, +stride: U32, +aux: Bool, +entries: U32) -> IO(Unit):
  do IO<Unit>:
    +nm : String = String.concat(["aq_", U32.show(i)])
    +sz : U32 = q.size_of(stride, entries)
    +ns : U32 = q.slots(sz, stride)
    urow(String.concat([nm, "_SIZE"]), sz)
    urow(String.concat([nm, "_STRIDE"]), stride)
    urow(String.concat([nm, "_LEVEL"]), pbl.level_of(q.pbl_pages_of(q.alloc_of(stride, aux, entries))))
    urow(String.concat([nm, "_ALLOC0"]), q.alloc_of(stride, aux, entries))
    urow(String.concat([nm, "_SLOTS"]), ns)
    +a : Unit <- aq_off(nm, 0, 0, ns, sz, stride, aux)
    +b : Unit <- aq_off(nm, 1, 1, ns, sz, stride, aux)
    +c : Unit <- aq_off(nm, 2, U32.sub(ns, 1), ns, sz, stride, aux)
    +d : Unit <- aq_off(nm, 3, ns, ns, sz, stride, aux)
    +e : Unit <- aq_off(nm, 4, U32.add(ns, 1), ns, sz, stride, aux)
    urow(String.concat([nm, "_RLEN"]), q.read_len(sz, stride))
    urow(String.concat([nm, "_R0"]), FILL_BYTE)
    urow(String.concat([nm, "_RN"]), FILL_BYTE)

def t_aq() -> IO(Unit):
  do IO<Unit>:
    aq_row(0, 16, False{}, 0)
    aq_row(1, 16, True{}, 0)
    aq_row(2, 128, True{}, 0)
    aq_row(3, 128, False{}, 0)
    aq_row(4, 32, False{}, 4096)
    aq_row(5, 16, True{}, 3)
    # the wrap: index == slots and index == slots + 1 come back to the start
    urow("qwrap_SLOTS", 256)
    urow("qwrap_READ", 16)
    brow("qwrap_READ_EQ0", U32.is_eq(q.read_off(256, 4096, 16), q.read_off(0, 4096, 16)))

# ===========================================================================
# THE COMPLETION AND ERROR STATUS. `cqe_ready` (:25) over real 32-byte
# entries, `struct_cq_base` byte 24 BY NAME, the CQE status byte at 25, and
# the CREQ valid bit at byte 8 against `read_idx // 256`.
# ===========================================================================
def cqe_row(i: U32, toggle: U32, cons: U32) -> IO(Unit):
  do IO<Unit>:
    brow(String.concat(["cqe_", U32.show(i), "_READY"]), cqe.ready(toggle, cons))

def t_cqe() -> IO(Unit):
  do IO<Unit>:
    cqe_row(0, 0, 0)
    cqe_row(1, 1, 0)
    cqe_row(2, 0, 4096)
    cqe_row(3, 1, 4096)
    cqe_row(4, 1, 1)
    cqe_row(5, 0, 1)
    cqe_row(6, 0, 4097)
    cqe_row(7, 3, 2)
    urow("c_CQE_TOGGLE_MASK", CQ_BASE_TOGGLE())
    urow("c_CQE_STATUS_AT", CQE_STATUS_AT())
    urow("c_CREQ_V_AT", CREQ_TOGGLE_AT())
    # byte 24 is the TOGGLE and byte 25 is the STATUS, BY NAME -- the two the
    # source reads by hand. `cqe_toggle_field`/`cqe_status_field` are
    # predicates on the name, so these rows cannot pass with the fields
    # transposed.
    brow("cqe_toggle_is_toggle", cqe_toggle_field(name_at(struct_cq_base_names(), 3n)))
    brow("cqe_status_is_status", cqe_status_field(name_at(struct_cq_base_names(), 4n)))
    brow("cqe_byte0_is_reserved", Bool.not(cqe_toggle_field(name_at(struct_cq_base_names(), 0n))))
    # the CREQ shape, :146 -- the same test with byte 8 and a 256-wrap
    brow("creq_ready_0", creq.ready(0, 0))
    brow("creq_ready_1", creq.ready(1, 0))
    brow("creq_ready_256", creq.ready(0, 256))
    brow("creq_ready_257", creq.ready(1, 256))
    urow("creq_nq_arm_index", rcfw.nq_arm_index(300))
    urow("creq_nq_arm_epoch", rcfw.nq_arm_epoch(300))
    urow("creq_nq_arm_index_255", rcfw.nq_arm_index(255))
    urow("creq_nq_arm_index_256", rcfw.nq_arm_index(256))
    # the async-event filter, :154. `event < 192` is the SKIP, so 192 itself is
    # NOT a skip -- the boundary row, one below `rcfq_skip_below`.
    brow("rcfw_skip_0", rcfw.skip(CREQ_BASE_TYPE_QP_EVENT(), 0))
    brow("rcfw_skip_191", rcfw.skip(CREQ_BASE_TYPE_QP_EVENT(), 191))
    brow("rcfw_skip_192", rcfw.skip(CREQ_BASE_TYPE_QP_EVENT(), 192))
    brow("rcfw_skip_not_event", rcfw.skip(0, 0))
    brow("rcfw_skip_event_56", rcfw.is_event(56))
    brow("rcfw_skip_event_0", rcfw.is_event(0))

def bs_typs(+i: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["c_BS_TYP_", U32.show(i)]), bs.typ_at(i))
    urow(String.concat(["c_BS_EXTRA_", U32.show(i)]), bs.extra_at(i))

def bs_typs_all() -> List<&2, U32>: BS_TYP()

# ===========================================================================
# THE LOGGING TABLE, both directions. Nine (type, extra) pairs forward, the
# `counts` derivation that type 15 shares with type 0, the instance bitmap
# walk including two ZERO bitmaps, the `ctx_init` sweep, the alloc rounding and
# the ALL_DONE flag.
# ===========================================================================
def bs_type_rows() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- bs_typs(0)
    +b : Unit <- bs_typs(1)
    +c : Unit <- bs_typs(2)
    +d : Unit <- bs_typs(3)
    +e : Unit <- bs_typs(4)
    +f : Unit <- bs_typs(5)
    +g : Unit <- bs_typs(6)
    +h : Unit <- bs_typs(7)
    +i : Unit <- bs_typs(8)
    lrow("c_BS_TYPES_ASC", bs_typs_all())

# THE COUNTS. `FIX` is the caps fixture from `.agents/slop/bnxt_oracle.py`, one
# entry per type: (entry_size, min_num_entries, sum of splits, instance bitmap).
# Type 0's count is 128 (64 + 64 splits) and type 15 REUSES it verbatim.
def bs_count(+typ: U32, mne: U32, splits: U32, c0: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["bs_COUNT_", U32.show(typ)]), bs.count_of(typ, mne, splits, c0))

# the `or [0]`: a scan that found nothing answers the single instance 0.
def bs_inst_or_zero(+acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(U32.from_nat(List.length(&2, U32, acc)), 0), [0], acc)

# the LIST :98 builds, `[i for i in range(8) if ibm >> i & 1] or [0]`. A fold
# that appends, so the order is ASCENDING and the count matches the list.
def bs_inst_list.go(n: Nat, +ix: U32, +ibm: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: bs_inst_or_zero(acc)
    case 1n+m: bs_inst_list.go(m, U32.inc(ix), ibm,
      Bool.pick(List<&2, U32>, bs.inst_bit(ibm, ix),
        List.append(&2, U32, acc, [ix]), acc))

def bs_inst_list(ibm: U32) -> List<&2, U32>: bs_inst_list.go(8n, 0, ibm, Nil{})

def bs_inst(+i: U32, +ibm: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["bs_INST_", U32.show(i)]), join_u32(bs_inst_list(ibm)))
    urow(String.concat(["bs_INST_", U32.show(i), "_N"]), bs.ninstances(ibm))

def t_bs() -> IO(Unit):
  do IO<Unit>:
    bs_type_rows()
    # THE FOLD, in table order, and the one row that matters is `bs_COUNT_15`:
    # type 15's count is type 0's, COPIED -- not 64 (its extra), not its own
    # min_num_entries, and not `max`ed against anything.
    bs_count(0, 16, 64, 0)
    bs_count(1, 1, 0, 128)
    bs_count(2, 1, 128, 128)
    bs_count(3, 8, 0, 128)
    bs_count(4, 1, 2, 128)
    bs_count(5, 4, 0, 128)
    bs_count(6, 1, 96, 128)
    bs_count(14, 1, 0, 128)
    bs_count(15, 0, 0, 128)
    brow("bs_count_15_is_zero_count", U32.is_eq(bs.count_of(15, 999, 999, 128), 128))
    brow("bs_count_15_ignores_mne", U32.is_eq(bs.count_of(15, 7, 0, 42), 42))
    # `max(min_num_entries, sum + extra)` -- the floor wins for type 1 and the
    # sum wins for type 2, one entry apart.
    brow("bs_count_1_floor_wins", U32.is_eq(bs.count_of(1, 64, 0, 0), 64))
    brow("bs_count_2_sum_wins", U32.is_eq(bs.count_of(2, 1, 128, 0), 256))
    # THE SEARCH. Types 7..13 ARE NOT IN THE TABLE, so an index is not a type.
    brow("bs_absent_7", U32.is_eq(bs.index_of(7), BS_LEN()))
    brow("bs_present_7_is_not_0", Bool.not(U32.is_eq(bs.index_of(7), 0)))
    urow("bs_extra_absent_7", bs.extra_of(7))
    urow("bs_index_14", bs.index_of(14))
    urow("bs_extra_14", bs.extra_of(14))
    urow("bs_extra_15", bs.extra_of(15))
    # THE INSTANCE BITMAP, :98, including two ZERO bitmaps whose answer is the
    # single instance 0 from `or [0]`.
    +a : Unit <- bs_inst(0, 1)
    +b : Unit <- bs_inst(1, 0)
    +c : Unit <- bs_inst(2, 4)
    +d : Unit <- bs_inst(3, 255)
    +e : Unit <- bs_inst(4, 128)
    +f : Unit <- bs_inst(5, 2)
    brow("bs_inst_zero_bitmap_is_0", U32.is_eq(bs.first_inst(0), 0))
    brow("bs_inst_zero_bitmap_count", U32.is_eq(bs.ninstances(0), 1))
    # a bitmap with bits 0 AND 2 set must answer 0, not 2: the fold keeps the
    # FIRST hit and a fold that overwrites answers the highest bit instead.
    brow("bs_inst_fwd_0", U32.is_eq(bs.first_inst(5), 0))
    brow("bs_inst_rev_0", U32.is_eq(bs.first_inst(2), 1))
    brow("bs_inst_high_only", U32.is_eq(bs.first_inst(128), 7))
    urow("bs_inst_count_all", bs.ninstances(255))
    urow("bs_inst_count_one", bs.ninstances(1))
    # THE `ctx_init` SWEEP, :102. The STRIDE is `entry_size` and the count is
    # the number of positions -- and they are not the same number, which is the
    # mistake the sweep invites.
    urow("bs_INIT_0_NPOS", bs.init_npos(4096, 0, 64))
    urow("bs_INIT_1_NPOS", bs.init_npos(4096, 64, 128))
    urow("bs_INIT_2_NPOS", bs.init_npos(1000, 32, 64))
    urow("bs_INIT_3_NPOS", bs.init_npos(4096, 0, 1024))
    urow("bs_INIT_0_MEM", 4096)
    urow("bs_INIT_1_MEM", 4096)
    urow("bs_INIT_2_MEM", 1000)
    urow("bs_INIT_3_MEM", 4096)
    urow("bs_INIT_0_STRIDE", 64)
    urow("bs_INIT_1_STRIDE", 128)
    urow("bs_INIT_2_STRIDE", 64)
    urow("bs_INIT_3_STRIDE", 1024)
    urow("bs_INIT_4_MEM", 4096)
    urow("bs_INIT_4_STRIDE", 64)
    urow("bs_INIT_5_MEM", 4096)
    urow("bs_INIT_5_STRIDE", 64)
    urow("bs_INIT_6_MEM", 4096)
    urow("bs_INIT_6_STRIDE", 128)
    urow("bs_INIT_6_NPOS", bs.init_npos(4096, 129, 128))
    urow("bs_INIT_7_MEM", 4096)
    urow("bs_INIT_7_STRIDE", 64)
    urow("bs_INIT_7_NPOS", bs.init_npos(4096, 1, 64))
    urow("bs_INIT_4_NPOS", bs.init_npos(4096, 4096, 64))
    urow("bs_INIT_5_NPOS", bs.init_npos(4096, 5000, 64))
    urow("bs_INIT_0_LEN", bs.init_len(bs.init_npos(4096, 0, 64)))
    urow("bs_INIT_1_LEN", bs.init_len(bs.init_npos(4096, 64, 128)))
    urow("bs_INIT_2_LEN", bs.init_len(bs.init_npos(1000, 32, 64)))
    urow("bs_INIT_3_LEN", bs.init_len(bs.init_npos(4096, 0, 1024)))
    # :107 -- the ALL_DONE flag is on the SAME type whose count is copied.
    urow("bs_FLAGS_15", bs.flags_of(15))
    urow("bs_FLAGS_14", bs.flags_of(14))
    brow("bs_flags_same_type", U32.is_eq(bs.flags_of(15), FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE()))
    # :99 -- the alloc rounding, `entry_size` multiplied BEFORE the round-up.
    urow("bs_ALLOC_0", bs.alloc_bytes(64, 64))
    urow("bs_ALLOC_1", bs.alloc_bytes(80, 64))
    urow("bs_ALLOC_2", bs.alloc_bytes(128, 128))
    urow("bs_ALLOC_3", bs.alloc_bytes(1, 1024))
    urow("bs_ALLOC_4", bs.alloc_bytes(4096, 64))
    urow("bs_ALLOC_5", bs.alloc_bytes(17, 64))

# ===========================================================================
# THE GID AND THE MAC, :71-72 and :208. Real `struct.unpack` calls on the
# oracle side. `gid_LOCAL_HEX` is the WHOLE 16-byte gid, and it is the row here
# that a wrong byte ORDER in the construction moves and nothing else would.
# ===========================================================================
# the fixture MAC is `0x001122334455`, split at 32 bits because a 48-bit value
# does not fit in a `U32` (see `MAC_HI16`). `MAC_FIX_LO24` is its low THREE
# bytes, which is what `mac.to_bytes(6, 'big')[3:]` slices out at :71.
def MAC_FIX_LO24() -> U32: 3359829
def GID_HEX_PREFIX() -> String: "00000000000000000000ffff0a"
def GID_HEX_TAIL() -> String: "334455"

# `struct.unpack("<4I", gid)` on the 16-byte dgid -- the same construction as
# the local gid above read the OTHER byte order, and `gid_DGID` says so.
def gid_dgid() -> List<&2, U32>: [256, 0, 4294901760, 571539466]

# the SIX bytes of `self.mac.to_bytes(6, 'big')`: `hi16`'s two, then `lo32`'s
# four. Byte 0 is 0x00 for the fixture MAC and the row says so, which is what
# makes a port that dropped the leading zero visible.
def l2_addr(+hi16: U32, +lo32: U32) -> List<&2, U32>:
  [U32.shrn(hi16, 8n), U32.and(hi16, 255), U32.shrn(lo32, 24n),
   U32.and(U32.shrn(lo32, 16n), 255), U32.and(U32.shrn(lo32, 8n), 255), U32.and(lo32, 255)]

def l2_mask() -> List<&2, U32>: [255, 255, 255, 255, 255, 255]

# `struct.unpack(">3H", mac)[::-1]` -- the two halves of the low 32 bits,
# reversed. The third 16-bit half is `MAC_HI16`, which is a separate word.
def src_mac_rev(hi16: U32, +lo32: U32) -> List<&2, U32>: [src_mac_h(lo32, 0n), src_mac_h(lo32, 16n), hi16]

def swap16(+v: U32) -> U32: U32.or(U32.shln(U32.and(v, 255), 8n), U32.shrn(v, 8n))

# `connect` (:208) uses `struct.unpack("<3H", mac.to_bytes(6, 'big'))` --
# LITTLE-endian -- where :72 uses `">3H"` on the same six bytes. So the two rows
# are THE SAME THREE HALVES BYTE-SWAPPED WITHIN EACH, and `gid_SRCMAC` next to
# `gid_DMAC` is the only place that shows it.
def src_mac_le(hi16: U32, +lo32: U32) -> List<&2, U32>: [swap16(hi16), swap16(src_mac_h(lo32, 16n)), swap16(src_mac_h(lo32, 0n))]

def t_gid() -> IO(Unit):
  do IO<Unit>:
    urow("gid_MAC_HI", mac_hi(MAC_HI16(), MAC_LO32()))
    urow("gid_MAC_LO", mac_lo(MAC_LO32()))
    urow("gid_LOCAL_LEN", GID_BYTES())
    srow("gid_LOCAL_HEX", String.concat([GID_HEX_PREFIX(), GID_HEX_TAIL()]))
    srow("gid_LOCAL_LAST3", GID_HEX_TAIL())
    lrow("gid_UNPACK", gid_order(GID_W0(), GID_W1(), GID_W2(), gid_w3(MAC_FIX_LO24())))
    lrow("gid_SRCMAC", src_mac(MAC_HI16(), MAC_LO32()))
    lrow("gid_SRCMAC_REV", src_mac_rev(MAC_HI16(), MAC_LO32()))
    lrow("gid_DGID", gid_dgid())
    lrow("gid_DMAC", src_mac_le(MAC_HI16(), MAC_LO32()))
    lrow("l2_ADDR", l2_addr(MAC_HI16(), MAC_LO32()))
    lrow("l2_MASK", l2_mask())

# ===========================================================================
# THE DEVICE AND QP INDEX ARITHMETIC. Every number the source LITS in a call,
# each named by its line, plus the compositions that are the actual arithmetic:
# `state | network_type`, `level << LVL_SFT | log_page << LOG2_SFT`, and
# `cmdq_size_cmdq_lvl = 256 << CMDQ_SIZE_SFT`.
# ===========================================================================
def t_dev() -> IO(Unit):
  do IO<Unit>:
    urow("dev_CMD_PCI_COMMAND", DEV_PCI_COMMAND())
    urow("dev_BAR0", 0)
    urow("dev_BAR2", 2)
    urow("dev_RESP_BYTES", RESP_BYTES())
    urow("dev_DBOFF_KB", 32)
    urow("dev_DBOFF_BYTES", db_off_of(32))
    urow("dev_DBOFF_DWORDS", db_at(db_off_of(32)))
    urow("dev_SEQ_WRAP", hwrm.seq_of(65535))
    urow("dev_SEQ_NEXT", hwrm.seq_of(10))
    urow("dev_FID", DEV_FID())
    urow("dev_PAGE_SIZE", 12)
    urow("dev_PAGESIZE_PBL", PAGE())
    urow("dev_CMDQ_LVL", CMDQ_LVL())
    urow("dev_CMDQ_LVL_SHIFTED", cmdq_lvl())
    urow("dev_CMDQ_LVL_SHIFTED_HI", U32.shrn(cmdq_lvl(), 16n))
    urow("dev_CMDQ_LVL_SHIFTED_LO", cmdq_lvl_lo16())
    urow("dev_PROD_AT", rcfw.prod_at())
    urow("dev_PROD_TRIG_AT", rcfw.trig_at())
    urow("dev_TRIG_VAL", rcfw.trig_val())
    urow("dev_CHIMP_AT", hwrm.bar0_at(0))
    urow("dev_CHIMP_TRIG_AT", hwrm.trig_at())
    urow("dev_HWRM_LEN", HWRM_MAX_REQ_LEN())
    urow("dev_STAT_DMA_LEN", 176)
    urow("dev_MRU", 9018)
    urow("dev_RX_BUF_SIZE", 640)
    urow("dev_LOGICAL_ID", 1)
    urow("dev_NQ_LEN", NQ_LEN())
    urow("dev_CRQ_LEN", CREQ_LEN())
    urow("dev_HOP_LIMIT", 64)
    urow("dev_MIN_RNR", 1)
    urow("dev_MAX_RD", 1)
    urow("dev_RNR_RETRY", 7)
    urow("dev_RETRY_CNT", 7)
    urow("dev_TIMEOUT", 14)
    urow("dev_MAX_DEST_RD", 4)
    urow("dev_PKEY", 65535)
    urow("dev_SQ_FWO", 6)
    urow("dev_RQ_FWO", 6)
    urow("dev_SQ_SIZE", RING_ENTRIES())
    urow("dev_CQ_SIZE", CQ_ENTRIES())
    urow("dev_db_slot", qp.post_send_slot(4097))
    urow("dev_db_epoch", qp.post_send_epoch(4097))
    urow("dev_db_slot_wrap", qp.post_recv_slot(4096))
    urow("dev_db_epoch_wrap", qp.post_recv_epoch(4096))
    # the HWRM wait gate, :86 -- THREE conjuncts, not one
    brow("dev_gate_len0", hwrm.gate_ok(0, 5, 5))
    brow("dev_gate_wrong_seq", hwrm.gate_ok(8, 5, 6))
    brow("dev_gate_ok", hwrm.gate_ok(8, 5, 5))
    brow("dev_gate_ok2", hwrm.gate_ok(8, 6, 6))
    # the RCFW producer index, :136-138 -- `write_idx` grows past 0xffff and the
    # producer is its low sixteen bits, so the flag rides on the MASKED value.
    urow("dev_prod_10", rcfw.prod_of(10))
    urow("dev_prod_wrap", rcfw.prod_of(65546))
    urow("dev_first_flag", rcfw.first_flag(10, True{}))
    urow("dev_first_flag_off", rcfw.first_flag(10, False{}))
    urow("dev_first_flag_wrap", rcfw.first_flag(rcfw.prod_of(65546), True{}))
    # the slots per command, :133 -- ceildiv(sizeof, 16), and it is BOTH the
    # size field and the number of ring writes.
    urow("dev_slots_add_gid", rcfw.slots_of(SIZEOF_CMDQ_ADD_GID()))
    urow("dev_slots_create_qp", rcfw.slots_of(SIZEOF_CMDQ_CREATE_QP()))
    urow("dev_slots_modify_qp", rcfw.slots_of(SIZEOF_CMDQ_MODIFY_QP()))
    urow("dev_slots_initialize_fw", rcfw.slots_of(SIZEOF_CMDQ_INITIALIZE_FW()))
    urow("dev_size_cq_base", CQ_STRIDE())
    urow("dev_size_cmdq_init", SIZEOF_CMDQ_INIT())

def t_qp() -> IO(Unit):
  do IO<Unit>:
    urow("qp_NEWSTATE_0", qp.newstate(1, 0))
    urow("qp_NEWSTATE_1", qp.newstate(2, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    urow("qp_NEWSTATE_2", qp.newstate(3, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    brow("qp_newstate_differ", Bool.not(U32.is_eq(
      qp.newstate(2, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()),
      qp.newstate(3, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))))
    # :186 -- `level << LVL_SFT | log_page << LOG2_SFT` with `LVL_SFT == 0`, so
    # the level is NOT shifted. `mr.lvl_of` reads the level back OUT of the
    # composed field, which is what makes the zero shift visible.
    urow("mr_LVLPG_0", mr.lvlpg(0, 12))
    urow("mr_LVLPG_1", mr.lvlpg(1, 12))
    urow("mr_LVLPG_2", mr.lvlpg(2, 12))
    urow("mr_LVLPG_3", mr.lvlpg(1, 21))
    urow("mr_LVLPG_4", mr.lvlpg(2, 30))
    urow("mr_LVLPG_5", mr.lvlpg(0, 13))
    brow("mr_lvl_roundtrip", U32.is_eq(mr.lvl_of(mr.lvlpg(2, 30)), 2))
    urow("mr_log_page_roundtrip", mr.log_page_of(mr.lvlpg(2, 30)))
    urow("mr_lvl_sft_is_zero", CMDQ_REGISTER_MR_LVL_SFT())
    urow("l2_FILTER_FLAGS", l2_filter_flags())
    urow("l2_ENABLES_SPLIT", l2_filter_enables())
    urow("qp_init_mask", BNXT_INIT_MASK())
    urow("qp_rtr_mask", BNXT_RTR_MASK())
    urow("qp_rts_mask", BNXT_RTS_MASK())
    urow("qp_access", BNXT_ACCESS())

# `hwrm`, :76-89, all FIVE of its traced calls in order: the sequence bump, the
# 0x1000-byte clear, the WAIT, the word loop into bar0, and the trigger dword.
def hwrm_all(t: Tr) -> Tr: hwrm.trig(hwrm.word(3, 7, hwrm.wait(hwrm.clear(hwrm.begin(10, t)))))

def refuse_rows(+k: U32) -> IO(Unit):
  do IO<Unit>:
    +t : Tr = Tr.fail_at(Tr.of(), k)
    +s : String = String.concat(["refuse_", U32.show(k)])
    # :34 -- the table allocation happens, then the assert fires.
    urow(String.concat([s, "_pbl_seen"]), Tr.seen(pbl.build_check(262145, Tr.reset(pbl.build_seq(262145, t)))))
    brow(String.concat([s, "_pbl_refused"]), Tr.refused(pbl.build_check(262145, Tr.reset(pbl.build_seq(262145, t)))))
    # the SAME build at one page fewer does NOT refuse: 513 > 512 and 512 == 512
    brow(String.concat([s, "_pbl_ok"]), Bool.not(Tr.refused(pbl.build_check(262144, Tr.reset(pbl.build_seq(262144, t))))))
    # :88 -- the HWRM's six calls, then the error-code refusal.
    # :88 -- the HWRM's five calls, then the error-code refusal. `hwrm_all` is
    # the whole sequence in one name because nesting `Tr.reset` five deep is
    # unreadable and is the shape that hides a missing paren.
    urow(String.concat([s, "_hwrm_seen"]), Tr.seen(hwrm.finish(1, Tr.reset(hwrm_all(t)))))
    brow(String.concat([s, "_hwrm_refused"]), Tr.refused(hwrm.finish(1, Tr.reset(hwrm_all(t)))))
    brow(String.concat([s, "_hwrm_ok"]), Bool.not(Tr.refused(hwrm.finish(0, Tr.reset(hwrm_all(t))))))
    urow("hwrm_all_calls", Tr.seen(hwrm_all(Tr.fail_at(Tr.of(), 0))))
    brow("hwrm_all_seq", Tr.seq(hwrm_all(Tr.of()),
      [Call{CALL_HWRM, 11, 0}, Call{CALL_ALLOC, 4096, 4096},
       Call{CALL_WAIT, 10000, 0}, Call{CALL_BAR0, 3, 7}, Call{CALL_BAR0, 64, 1}]))
    # :224 -- the poll reads the ring and then the status byte refuses.
    urow(String.concat([s, "_poll_seen"]), Tr.seen(qp.poll_done(9, 3, 32768, 5, Tr.reset(t))))
    brow(String.concat([s, "_poll_refused"]), Tr.refused(qp.poll_done(9, 3, 32768, 5, Tr.reset(t))))
    brow(String.concat([s, "_poll_ok"]), Bool.not(Tr.refused(qp.poll_done(9, 3, 32768, 0, Tr.reset(t)))))
    # THE ORDERED IDENTITY TRACES. A subsequence test, so the order is checked
    # and not merely the multiset -- `has_fwd` and `has_rev` are the pair that
    # makes it an order test and not a membership test.
    brow("db_seq", Tr.seq(dev.doorbell(7, DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of()),
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}]))
    brow("db_seq_rev_not", Bool.not(Tr.seq(dev.doorbell(7, DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of()),
      [Call{CALL_DB, 4096, 0}, Call{CALL_BARRIER, 0, 0}])))
    brow("db_2halves", U32.is_eq(Tr.val_at(CALL_DB, Tr.calls(dev.doorbell(7, DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of())), 0), 0))
    urow("db_hi_nonzero", db.hi(7, DBC_DBC_TYPE_SQ()))
    brow("db_dropped_hi", Bool.not(U32.is_eq(db.hi(7, DBC_DBC_TYPE_SQ()), 0)))
    brow("db_lo_zero", U32.is_eq(db.lo(0, 0), 0))
    # `post_send`: the work queue element, then the msn table, then the
    # doorbell. `post_send_msn_2_calls` is the row that says the msn write is
    # the SECOND `CALL_RING_W` and not a third kind of call.
    urow("post_send_ring_w", Tr.count(CALL_RING_W, Tr.calls(qp.post_send_seq(6144, 128, 5, Tr.of()))))
    brow("post_send_msn_2_calls", U32.is_eq(
      Tr.count(CALL_RING_W, Tr.calls(qp.post_send_seq(6144, 128, 5, Tr.of()))), 2))
    brow("post_send_seq", Tr.seq(qp.post_send_seq(6144, 128, 5, Tr.of()),
      [Call{CALL_RING_W, 640, 8}, Call{CALL_RING_W, 640, 128}]))
    # `post_recv`: ONE ring write and NO msn write, because a receive consumes
    # no packet send numbers.
    urow("post_recv_ring_w", Tr.count(CALL_RING_W, Tr.calls(qp.post_recv_seq(4096, 128, 5, Tr.of()))))
    brow("post_recv_no_msn", U32.is_eq(Tr.count(CALL_RING_W, Tr.calls(qp.post_recv_seq(4096, 128, 5, Tr.of()))), 1))
    brow("has_fwd", Tr.has([Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}],
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}]))
    brow("has_rev", Bool.not(Tr.has([Call{CALL_DB, 4096, 0}, Call{CALL_BARRIER, 0, 0}],
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}])))
    brow("has_arg_matters", Bool.not(Tr.has([Call{CALL_DB, 4096, 0}], [Call{CALL_DB, 4097, 0}])))

def refuse_twice() -> Bool:
  # `Tr.refuse` is idempotent after the first, so refusing twice at the same
  # site does not refuse twice -- and `nth` does not move either.
  Bool.not(Tr.refused(Tr.refuse(Tr.refuse(Tr.of()))))

# ===========================================================================
# THE FOUR REFUSALS, as TRUNCATED TRACES. `Tr.emit` records nothing once a
# refusal has fired, so the LENGTH of the trace is the claim and no step below
# needs a guard of its own. `fail_at` numbers the sites and one fixture reaches
# each in turn; `seen` is the truncation length.
#
#   :34   `assert len(table_paddrs) <= 512`   ONE allocation, then nothing
#   :88   `assert ret.error_code == 0`         the HWRM, up to its wait
#   :155  `assert ret.status == 0`             the RCFW, up to its CREQ read
#   :224  `assert raw[25] == 0`                the poll, up to its ring read
# ===========================================================================
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- refuse_rows(0)
    +b : Unit <- refuse_rows(1)
    +c : Unit <- refuse_rows(2)
    +d : Unit <- refuse_rows(3)
    brow("refuse_fires", Tr.refused(Tr.fail_at(Tr.of(), 1)))
    brow("refuse_never", Bool.not(Tr.refused(Tr.fail_at(Tr.of(), 0))))
    brow("refuse_idempotent", refuse_twice())

def pack_row(+pfx: String, +nm: String, +ats: List<&2, U32>, +ws: List<&2, U32>, +i: Nat) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([pfx, "_", nm, "_AT"]), nth_at(ats, i))
    urow(String.concat([pfx, "_", nm, "_W"]), nth_at(ws, i))

# one row per FIELD, by name: the byte the source puts it at and its width.
# THE THREE SCATTER-GATHER INDICES ARE PARAMETERS, not literals: the SEND's `va`
# is field 6 and the RECEIVE's is field 4, because the receive pack has no
# `size` field and so no `pad20`. Hard-coding 6 for both printed 0 for every
# receive row and the gate said so.
def pack_rows(+pfx: String, +ats: List<&2, U32>, +ws: List<&2, U32>, vi: Nat, ki: Nat, si: Nat) -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- pack_row(pfx, "type", ats, ws, 0n)
    +b : Unit <- pack_row(pfx, "flags", ats, ws, 1n)
    +c : Unit <- pack_row(pfx, "kind", ats, ws, 2n)
    +d : Unit <- pack_row(pfx, "pad", ats, ws, 3n)
    +e : Unit <- pack_row(pfx, "size", ats, ws, 4n)
    +f : Unit <- pack_row(pfx, "va", ats, ws, vi)
    +g : Unit <- pack_row(pfx, "key", ats, ws, ki)
    +h : Unit <- pack_row(pfx, "size2", ats, ws, si)
    # `pad20` is the SEND's second pad and the RECEIVE has no second one -- its
    # 29-byte pad covers bytes 3..31 in one field. `nth_at` past the end is 0 and
    # `Bool.not` makes that a non-row, so the two lists stay honest.
    Bool.pick(IO(Unit), Bool.not(U32.is_zero(nth_at(ws, 5n))),
      pack_row(pfx, "pad20", ats, ws, 5n), IO.print(""))

# there is no `map` in a list literal in this Bend, and a comprehension is not
# one either -- the offsets and widths are printed by `pack_row` anyway, so this
# is a JOIN and not a projection.
def show_str(xs: List<&2, U32>) -> String: join_u32(xs)

# ---------------------------------------------------------------------------
# THE TWO PACK FORMATS, BY NAME AND IN ORDER. `ops_rdma.py:140` calls the REAL
# `send_wqe`/`recv_wqe` and unpacks the first 32 bytes as `<8I`, so word 0 and
# word 2 are facts about this file, and the nine field NAMES and the seven
# field NAMES -- WITH their byte offsets and widths -- are the only spelling
# that cannot be transposed without a row moving.
#
# THESE SIX LISTS WERE DEAD UNTIL THIS GATE. `.agents/slop/dead-defs2.py` found
# `send_pack_names`, `send_pack_at`, `send_pack_w`, `recv_pack_names`,
# `recv_pack_at` and `recv_pack_w` never called by anything, which is the
# `schedule/indexing.bend` lesson: a def nothing calls is invisible to every
# other check, and M16 of the mutation table is a blind spot for the same
# reason.
# ---------------------------------------------------------------------------
def t_packs() -> IO(Unit):
  do IO<Unit>:
    nrow("send_0_NAMES", send_pack_names())
    nrow("recv_0_NAMES", recv_pack_names())
    +a : Unit <- pack_rows("send_0", send_pack_at(), send_pack_w(), 6n, 7n, 8n)
    +b : Unit <- pack_rows("recv_0", recv_pack_at(), recv_pack_w(), 4n, 5n, 6n)
    +c : Unit <- pack_rows("send_2", send_pack_at(), send_pack_w(), 6n, 7n, 8n)
    +d : Unit <- pack_rows("recv_2", recv_pack_at(), recv_pack_w(), 4n, 5n, 6n)
    srow("send_0_FIELDS", show_str(send_pack_at()))
    srow("recv_0_FIELDS", show_str(recv_pack_at()))
    srow("send_0_WIDTHS", show_str(send_pack_w()))
    srow("recv_0_WIDTHS", show_str(recv_pack_w()))
    # the two totals, and `struct.calcsize` is the oracle's half of them
    urow("send_0_TOTAL", WQE_BYTES())
    urow("recv_0_TOTAL", WQE_BYTES())
    # THE PADDING IS ZERO, and word 2 of the RECEIVE is zero however big the
    # transfer -- that is the 29-byte pad running over the send's `I size`.
    urow("recv_2_W2", wqe.hdr2(True{}, 4096))
    urow("send_2_W2", wqe.hdr2(False{}, 4096))
    urow("hdr_words", HDR_WORDS())
    urow("wqe_total_words", WQE_TOTAL_WORDS())
    urow("cqe_toggle_at", CQE_TOGGLE_AT())
    urow("slot64", SLOT64())

# ---------------------------------------------------------------------------
# THE OPERATIONS THAT HAD NO GATE ROW AT ALL. Twelve trace-emitting defs were
# dead, so M23 (`rcfw.prod_write`) was a BLIND SPOT: the mutation moved nothing
# because nothing called the def. These rows call each one, so the SEQUENCE is
# checked and the defs are no longer invisible.
# ---------------------------------------------------------------------------
def t_ops() -> IO(Unit):
  do IO<Unit>:
    urow("op_rcfw_write_seen", Tr.seen(rcfw.write(7, Tr.of())))
    urow("op_rcfw_write_len", Tr.val_at(CALL_RING_W, Tr.calls(rcfw.write(7, Tr.of())), 0))
    urow("op_rcfw_prod_at", Tr.arg_at(CALL_BAR0, Tr.calls(rcfw.prod_write(65546, True{}, Tr.of())), 0))
    urow("op_rcfw_prod_val", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(65546, True{}, Tr.of())), 0))
    urow("op_rcfw_prod_nofirst", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(10, False{}, Tr.of())), 0))
    urow("op_rcfw_prod_first", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(10, True{}, Tr.of())), 0))
    brow("op_rcfw_prod_seq", Tr.seq(rcfw.prod_write(10, False{}, Tr.of()),
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_BAR0, 387, 10}]))
    urow("op_rcfw_trig_at", Tr.arg_at(CALL_BAR0, Tr.calls(rcfw.trig_write(Tr.of())), 0))
    urow("op_rcfw_trig_val", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.trig_write(Tr.of())), 0))
    urow("op_creq_read_at", Tr.arg_at(CALL_RING_R, Tr.calls(rcfw.creq_read(9, Tr.of())), 0))
    urow("op_creq_wait_ms", Tr.arg_at(CALL_WAIT, Tr.calls(rcfw.creq_wait(Tr.of())), 0))
    brow("op_rcfw_status_ok", rcfw.status_ok(0))
    brow("op_rcfw_status_bad", Bool.not(rcfw.status_ok(3)))
    brow("op_poll_ready", qp.poll_ready(4096, CQ_STRIDE(), 9, 1))
    brow("op_poll_ready_not", Bool.not(qp.poll_ready(4096, CQ_STRIDE(), 9, 0)))
    urow("op_post_send_psn", qp.post_send_psn(0, 100))
    urow("op_post_send_psn_zero", qp.post_send_psn(5, 0))
    urow("op_mr_reg_arg", Tr.arg_at(CALL_MR, Tr.calls(dev.register_mem(2, 30, 4096, Tr.of())), 0))
    urow("op_mr_reg_len", Tr.val_at(CALL_MR, Tr.calls(dev.register_mem(2, 30, 4096, Tr.of())), 0))
    urow("op_mr_dereg_arg", Tr.arg_at(CALL_MR, Tr.calls(dev.unregister_mem(77, Tr.of())), 0))
    urow("op_fini_k", Tr.arg_at(CALL_FINI, Tr.calls(dev.fini(Tr.of())), 0))
    urow("op_l2_filter_k", Tr.arg_at(CALL_L2_FILTER, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 0))
    urow("op_l2_vnic_enables", Tr.val_at(CALL_VNIC, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 1))
    urow("op_l2_filter_enables", Tr.val_at(CALL_L2_FILTER, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 0))
    urow("op_pbl_top_bytes", Tr.arg_at(CALL_ALLOC, Tr.calls(pbl.build_top(Tr.of())), 0))
    urow("op_pbl_top_lvl", Tr.val_at(CALL_ALLOC, Tr.calls(pbl.build_top(Tr.of())), 0))
    # `Tr.here` is the id the seam's NEXT call returns, read BEFORE the emit so
    # ids are monotone in issue order. Five emits give ids 0..4 and the sixth
    # read is the one after them.
    urow("tr_here_start", Tr.here(Tr.of()))
    urow("tr_here_after_5", Tr.here(rcfw.write(7, rcfw.write(7, rcfw.write(7,
      rcfw.write(7, rcfw.write(7, Tr.of())))))))
    urow("tr_seen_matches_here", Tr.seen(rcfw.write(7, Tr.of())))

def tag_pair(+a: U32, +b: U32) -> IO(Unit):
  do IO<Unit>:
    brow(String.concat(["tag_distinct_", U32.show(a), "_", U32.show(b)]), Bool.not(U32.is_eq(a, b)))

# the POSITION rides in beside the fuel: a countdown binder is consumed by the
# `match`, so `nth_at(ts, m)` and `tag_rows(m, ...)` would read it twice. This
# is `bs.index_at.go`'s shape and it is the third time on this file.
def tag_rows(n: Nat, +ix: U32, +ts: List<&2, U32>) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+m:
      do IO<Unit>:
        +a : Unit <- tag_pair(nth_at(ts, U32.to_nat(ix)), nth_at(ts, U32.to_nat(U32.inc(ix))))
        tag_rows(m, U32.inc(ix), ts)

# THE CALL TAGS ARE IDENTITIES, NOT VALUES. The constant sweep is blind on all
# nineteen of them and that is a THEOREM, not a gap: a tag is only ever compared
# against another tag (`Tr.has.step.same2` and `Tr.count`'s `U32.is_eq`), never
# against a number Python produces, so ANY permutation of the nineteen is
# observationally equivalent and no fixture can separate them. What IS checkable
# is that they are DISTINCT, and that is what these rows do -- a duplicate tag
# would make two different device calls indistinguishable in every sequence test.
def t_tags() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- tag_rows(19n, 0, [CALL_PCI_RESET(), CALL_PCI_CFG_R(), CALL_PCI_CFG_W(),
      CALL_MAP_BAR(), CALL_ALLOC(), CALL_BARRIER(), CALL_BAR0(), CALL_RING_W(),
      CALL_RING_R(), CALL_WAIT(), CALL_HWRM(), CALL_RING_ALLOC(), CALL_CMDQ(),
      CALL_VNIC(), CALL_L2_FILTER(), CALL_MR(), CALL_FINI(), CALL_DB(), CALL_REFUSE()])
    urow("tag_n", 19)
    # and BS_TYPE0 is the type whose count type 15 COPIES -- `bs_count_15` reads
    # it, which is what makes it not dead code.
    urow("bs_type0", BS_TYPE0())
    urow("bs_type15", BS_TYPE15())
    urow("queue_page", QUEUE_PAGE())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_struct()
    c : Unit <- t_offset_names()
    d : Unit <- t_hdr0()
    e : Unit <- t_db()
    f : Unit <- t_msn()
    g : Unit <- t_wqe()
    h : Unit <- t_pbl()
    i : Unit <- t_aq()
    j : Unit <- t_cqe()
    k : Unit <- t_bs()
    l : Unit <- t_gid()
    m : Unit <- t_dev()
    n : Unit <- t_qp()
    +p : Unit <- t_packs()
    +q : Unit <- t_ops()
    +r : Unit <- t_tags()
    o : Unit <- t_refuse()
    IO.print("bnxtdev-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number is `.agents/slop/bnxt_mutate.py`'s output and
# not an estimate. The harness applies ONE edit to a scratch copy IN THIS
# DIRECTORY (a `$TMPDIR` copy cannot resolve the relative imports and produced 22
# phantom blind spots in one unit), runs the INTERPRETED lane, and diffs the WHOLE
# `name=value` LINES against a baseline captured immediately before the run. The
# useful column is "rows MOVED", because a mutation that moves nothing measures
# what this gate does NOT see.
#
#   34 of 36 move a row. The two that do not are M35, which is a THEOREM, and
#   M36, which is the control. There is no unexplained zero.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | 1 | :29 -- `PTU_PTE_VALID` becomes `PTU_PTE_LAST`, so no entry is ever VALID | 2 | `pbl_noq_ENTRY0_LO`, `pbl_noq_ENTRYLAST_LO`. Two and not eight because `pbl_q_*_ENTRYLAST_LO` has VALID AND LAST and swapping VALID for LAST is a no-op on a two-flag entry -- the single-flag rows are the only ones that see it. |
# | 2 | :30 -- `NEXT_TO_LAST` goes on the LAST entry | 8 | every `*_ENTRYN1_LO`, which is the whole point of two DISTINCT flags on two DISTINCT entries |
# | 3 | :30 -- the last index is `n-2`, so LAST and NEXT_TO_LAST collide | 16 | the boundary of `is_last`. Sixteen because it moves both the last-entry and the second-to-last rows for every fixture at once. |
# | 4 | :14 -- `BNXT_QPLIB_DBR_VALID` replaced by `DBC_DBC_TYPE_CQ` | 9 | **the constant table both ways**: `c_BNXT_QPLIB_DBR_VALID` is a row AND eight `db_*_HI` rows move, so a right table with a wrong formula fails the second set and a right formula with a wrong table fails the first. Neither alone can be satisfied by the other's mistake. |
# | 5 | :15 -- the epoch rides at bit 48 instead of bit 24 | 4 | `db_3_LO`, `db_4_LO`, `db_6_LO`, `db_7_LO` -- and NOT the two cases with `epoch == 0`, which is why the fixture has to carry four non-zero epochs and not one. |
# | 6 | :24 -- the slot sits at hi32 bit 24, i.e. at word bit 56 | 5 | the 48/24/24 msn split, and NOT `msn_0`/`msn_1` whose slot is 0. |
# | 7 | :22 -- `nxt`'s `& 0xffffff` is dropped | 3 | the mask, and only the fixtures that straddle 2^24 (`msn_3`, `msn_4`). **This was a ZERO until the fixture straddled 2^24** -- every original psn is below 0xffffff, so the mask is vacuously true. Same lesson `ops_rdma.bend`'s M8 records. |
# | 8 | :22 -- `max(1, ...)` becomes `max(0, ...)` | 3 | a ZERO-LENGTH send. One row and not more, because `max` only differs at `size == 0`, and `msn_5` is the only fixture at zero. |
# | 9 | :28 -- the one-page shortcut allocates instead of returning | 8 | the `len(paddrs) == 1` shortcut, and it moves the three `aq_*_LEVEL` rows as well because the level is what tells the allocation apart. |
# | 10 | :34 -- `<=` becomes `<`, so exactly 512 pages stops being legal | 2 | **the boundary, and it was a ZERO until `pbl_edge_262144_LEVEL` existed.** Every other `pbl_q_*` fixture is 1, 2 or 3 pages, so no fixture reached the limit at all. Two rows for one boundary is not redundancy: `pbl_edge_*_REFUSED` reads `refuses` (`>`) and `pbl_edge_*_LEVEL` reads `level_of` (`<=`), and M10 mutates only the second. |
# | 11 | :44 -- the aux arm uses the RING stride, so the msn table overlaps the ring | 18 | `size + i%slots*stride` against `size + i%slots*8`. Eighteen because it moves every `aq_*_WA*` except the index-0 and wrap ones, where `i%slots` is 0 or 1 and both formulas agree. |
# | 12 | :44 -- the aux base loses the `size +`, so the msn table is at offset 0 | 30 | every `aq_*_WA*` including the zeros, which is why thirty and not eighteen. It also moves `aq_*_W*`, because a queue whose aux base is inside the ring has a different total. |
# | 13 | :49 -- **re-introduces the bug this gate caught**: `size` grows by the aux term | 44 | **THE BIGGEST IN THE FILE.** `alloc_queue`'s `size=` is the RING and the allocation is what carries `+ aux*entries*8`; a port that adds the aux term to `size` claims a 6144-byte queue where there is a 4096-byte one, and every slot count and every aux base after it is wrong. This is a REAL BUG, not a hypothetical: the first version of `q.size_of` did exactly this and `aq_1_SIZE` and `aq_1_SLOTS` are the two rows that said so. |
# | 14 | :31 -- the PBL level is a function of the ENTRY count rather than the pages | 6 | all six `aq_*_LEVEL`. The level is `ceildiv(alloc_bytes, 0x1000)` and NOT `entries_of(...)`, which is the same class as M13 and one line away from it. |
# | 15 | :96 -- `max` becomes `+`, so the firmware's `min_num_entries` floor is ignored | 6 | the three types where the floor wins (`bs_COUNT_0`, `_2`, `_4`, `_6`, `_14`) and NOT the three where the sum is already larger. Five rows and not nine is the fixture doing its job. |
# | 16 | :96 -- type 15's `counts[0]` REUSE is dropped and it computes its own | 3 | `bs_COUNT_15` and the two rows that assert the reuse directly. **This is a distinct table row and not a variant of M15**: the two mutations are one line apart and neither moves the other's rows. |
# | 17 | :98 -- the fold keeps the LAST hit, so the HIGHEST set bit answers | 1 | `bs_inst_fwd_0` ONLY -- the bitmap with bits 0 and 2 set. One row and it exists for this mutation: without it a fold that overwrites passes every other instance row. |
# | 18 | :98 -- the bitmap is masked by 2, not 1 | 13 | every `bs_INST_*` plus the four `c_MASK_*_POP` rows, because `mask_pop` and `bs.ninstances` SHARE `bs.count.go`. That sharing is deliberate and it is why a one-bit slip in the popcount moves the constant table too. |
# | 19 | :102 -- the sweep count ignores `ctx_init_offset` | 1 | `bs_INIT_6_NPOS` ONLY, and **it was a ZERO until that row existed.** With `mem` a whole number of strides and `off` a multiple of the stride, `ceildiv(mem-off, size)` and `ceildiv(mem, size)` are EQUAL -- four fixtures all agreed and the mutation was invisible. It takes an UNALIGNED offset (129 over 128) to separate them. |
# | 20 | :153 -- the CREQ consumer index is unmasked, so it is 32 bits and not 8 | 2 | `creq_nq_arm_index` and `creq_nq_arm_index_256`. Two and not four because 255 fits in eight bits either way. |
# | 21 | :154 -- `<` becomes `<=`, so the threshold event itself becomes a skip | 1 | `rcfw_skip_192` ONLY, and that row exists for this mutation: 191 is a skip either way and 192 is the whole boundary. `rcfw_skip_0` and `rcfw_skip_191` are the negative case one value away. |
# | 22 | :86 -- the wait's `resp_len` conjunct is dropped | 1 | `dev_gate_len0` ONLY -- the zero-length response is the ONLY case where the two conjuncts differ, so a one-row fixture is the whole claim and `dev_gate_ok` is the negative case beside it. |
# | 23 | :136-138 -- the FIRMWARE_FIRST flag is applied to the UNMASKED write index | 1 | `op_rcfw_prod_wrap` ONLY. **This was a BLIND SPOT until `t_ops` existed**: `rcfw.prod_write` was a def nothing called, which is the `schedule/indexing.bend` lesson -- a def nothing calls is invisible to every other check, and thirteen other trace-emitting defs were in the same state. |
# | 24 | :186 -- `level << 2` "fixes" the zero `LVL_SFT` into the page-size field | 5 | four `mr_LVLPG_*` and `mr_lvl_roundtrip`. `CMDQ_REGISTER_MR_LVL_SFT` is 0 and that is a fact about the FIELD, so a version that "fixes" the missing shift moves the level into the page size. |
# | 25 | :19 -- the RECEIVE header gets the size in word 2, which its 29-byte pad covers | 3 | `wqe_0_R`, `wqe_2_R` and `recv_2_W2`. A receive's work queue element says nothing about its length in the header, which is why `ops_rdma.py:141` supplies it as a separate word. |
# | 26 | :18 -- the INVERTED reading `ops_rdma.bend`'s COMMENT gives, applied to the SEND arm | 5 | `hdr0_SEND_KIND_AT16`, `hdr0_SEND_REAL` and the three `wqe_*_S` rows. **This is the contradiction reported at the top of this file, as a mutation**: the comment claims `type << 16 | flags << 8 | kind`, and applying it moves five rows. |
# | 27 | :25 -- the CQE toggle test is inverted, so a ready entry is never ready | 10 | all eight `cqe_*_READY` and `has_arg_matters`. Ten and not eight because the toggle bit is shared with the `Tr.has` argument check. |
# | 28 | :78 -- the `& 0xffff` is dropped, so the sequence counter never wraps | 1 | `dev_SEQ_WRAP` ONLY, and that row exists for this mutation: `dev_SEQ_NEXT` is the negative case one step away and cannot see it. |
# | 29 | :66/:164 -- the byte offset is divided by 4, i.e. a 32-bit doorbell bar | 2 | `dev_DBOFF_DWORDS` and `db_seq`, the second because the doorbell trace carries the dword index. `dev_DBOFF_BYTES` does NOT move, and that is the pair being a pair: the two scales are separate claims. |
# | 30 | :142/:143 -- the trigger dword shares the producer's dword | 2 | `dev_PROD_TRIG_AT` and `dev_PROD_AT`. Two rows because the two dwords are 61 apart and `op_rcfw_trig_at` reads the trigger through the trace as well. |
# | 31 | :204 -- `state | network_type` becomes `state` | 2 | `qp_NEWSTATE_1` and `qp_NEWSTATE_2` and NOT `_0`, whose network type is 0. `qp_newstate_differ` is the row that says the two transitions are one apart. |
# | 32 | :116 -- the `CMDQ_SIZE` shift is dropped | 2 | `dev_CMDQ_LVL_SHIFTED` and `_LO`, and not `_HI` which is 0 either way. |
# | 33 | :172 -- the receive ring shares the COMPLETION ring's enable word | 1 | `c_RING_ALLOC_RX_ENABLES` ONLY, and `c_RING_ALLOC_L2_ENABLES` beside it is the negative case: the two lines are one apart in the source and sharing one constant would pass neither. |
# | 34 | :72 -- the `>3H` halves are unmasked, so the low one is the whole low word | 3 | `gid_SRCMAC`, `gid_SRCMAC_REV` and `gid_DMAC`, the last because `connect`'s `<3H` is the SAME three halves byte-swapped and `swap16` composes from the same reader. |
# | 35 | :178 -- the `PATH_RX` flag word becomes `ENABLES_L2_ADDR` | 0 | **A THEOREM AND NOT A GAP.** `CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX == CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR == 1` in autogen/bnxt.py, so the substitution is a no-op over EVERY possible input and no fixture can separate them. It is closed with a claim about the CONSTANTS (`c_CFA_L2_*_FLAGS_PATH_RX` and `c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR` are both rows) and not with a row that asserts the swapped word is wrong. |
# | 36 | :27 -- **THE CONTROL**: a comment-only edit | 0 | a table with no row that CANNOT move is a table of coincidences. |
# ===========================================================================
# THE CONSTANT SWEEP. `.agents/slop/bnxt_sweep.py` puts `+1` on every one of the
# 136 `def NAME() -> U32: V` constant defs, ONE AT A TIME, and diffs the whole
# lines. **134 of 136 move a row.** The two that do not are `BNXT_HWRM_NO_CMPL_RING`
# and `MISSING`, both `4294967295`, where `+1` OVERFLOWS THE U32 and the mutated
# file does not compile -- that is a limitation of the `+1` method, not a
# coverage gap, and it is reported as `DID NOT COMPILE` rather than counted as a
# blind spot.
#
# `ops_metal`'s sweep found 30 blind of 111, all `CALL_*` tags. On this file the
# nineteen `CALL_*` tags were BLIND at first and are not any more, because
# `t_tags` added `tag_distinct_*` rows. That is the right fix and not a row that
# asserts a tag's number: **a tag is an identity, not a value.** It is only ever
# compared against another tag, so any permutation of the nineteen is
# observationally equivalent, and what is actually checkable is that they are
# DISTINCT.
#
# `QUEUE_PAGE` and `BS_TYPE0` were also blind and both are now read: the first by
# `queue_page` (and its `+1` is a degenerate edit -- `4097 // 16 == 256`), the
# second by `bs_type0`.
# ===========================================================================
