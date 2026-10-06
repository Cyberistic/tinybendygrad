# tinybendygrad/runtime/ops_rdma.bend -- port of tinygrad/runtime/ops_rdma.py
#
# RDMA IS NOT A DEVICE WITH A DRIVER ON IT. IT IS A NETWORK FABRIC, AND THE
# THREE THINGS THAT MAKES IT DIFFERENT FROM ops_webgpu.bend ARE ALL HERE:
#
#   1. A BUFFER IS REGISTERED BEFORE IT CAN BE SENT TO. `BNXTAllocator._map`
#      (:42-51) hands the NIC a page list, a size, a LOG PAGE SIZE and the GPU
#      virtual address, and the NIC answers a KEY. From that moment the GPU
#      address is not usable by the NIC and the key is not usable by the GPU, and
#      `rdma_copies` (:140) puts BOTH in every work queue element. So there is a
#      TRANSLATION TABLE and a wrong entry in it is a silently wrong transfer --
#      which is why `Pdt` carries it in BOTH directions and why `ops.wqe`
#      REFUSES to post a work queue element whose key is missing.
#   2. THERE IS NO KERNEL. `rdma_copies` (:111-156) emits a fixed instruction
#      STREAM -- ring writes, two doorbell writes and a completion wait per work
#      queue element -- and `rdma_submit` (:161-168) substitutes that stream for
#      the CALL it replaced. What is being ported is a program generator, and
#      `ins.write` / `ins.msn` / `ins.ring_db` / `ins.wait` / `ins.cq_db` are its
#      instructions. The address of each one rides on the trace entry and the
#      VALUE is in the record the def returns, exactly as ops_webgpu.bend puts a
#      dispatch's geometry beside its trace entry.
#   3. THE COMPLETION QUEUE HAS ITS OWN ORDER, AND IT IS NOT THE RING'S. The
#      doorbell rings slot `n + 1` (:148,:152) and the wait polls slot `n`
#      (:151), and the wait's expected value INVERTS the doorbell's epoch
#      (`n // CQ_ENTRIES & 1 ^ 1`). With `RING_ENTRIES == CQ_ENTRIES == 4096`
#      those two rules are the only thing that keeps a receive from completing
#      against the previous pass of the ring, and a port that drops the `^ 1`
#      compiles, typechecks and hangs. `rdma_epoch_*` is the fixture that sees it.
#
# WHAT IS FFI AND WHAT IS NOT. `rdma` driver calls, the mlx5/bnxt netlink and the
# `verbs` bindings are all seams: `pci_dev.map_bar`, `pci_dev.bar_info`,
# `pci_dev.alloc_sysmem`, `MemoryManager.alloc_vaddr`, `dev_impl.register_mem`,
# `dev_impl.unregister_mem`, `dev_impl.fini`, `BNXTQP(...)` and `BNXTQP.connect`
# are named in a trace and none of them is made here. The bnxt constants are NOT
# seams: they are read out of `tinygrad/runtime/autogen/bnxt.py` and
# `support/rdma/bnxtdev.py` and every one of them is MEASURED (see THE
# CONSTANTS). The `struct.pack`/`struct.unpack` calls are pure arithmetic and are
# PORTED, in halves where a value is 64 bits.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. Line numbers are ops_rdma.py.
#
#   :16  RDMA_CHUNK                  PORTED  `RDMA_CHUNK()`
#   :18  BNXT_IDS                     PORTED  the four constants and `vram_bar`
#   :22  `BNXTIface.__init__`         PORTED  `Iface.of`  -- vram_bar=2,
#                                               base_class, dev_impl_t, the PCs
#   :24  `device_fini`                PORTED  `iface.fini`
#   :26-29 `storage`                  PORTED  `alloc.va` + `alloc.sysmem_size`
#                                               -- the DOUBLE
#                                               round_up and the SYS mapping
#   :30-31 `buffer`                   PORTED  `alloc.buf_size` / `alloc.va_size`
#                                               -- and the nbytes /
#                                               VA divergence, which is the whole
#                                               point of `rdma_buf_nb_vs_va`
#   :33-36 `doorbell`                 PORTED  `db.of` -- page-aligned DOWN, and
#                                               snooped=False where `storage`
#                                               defaults snooped=True
#   :39-40 `_alloc`                   PORTED  `alloc.of`
#   :41  `_copyin`                    PORTED  `alloc.copyin` -- the SOURCE's len
#   :43-44 `_map`'s peer guard        PORTED  `map.peer_ok` (the REFUSAL)
#   :46  the aspace branch            PORTED  `map.paddrs`  SYS keeps, else p2p
#   :47  `align`                      PORTED  `align_or` -- the OR-reduction
#   :48  `log_page`                   PORTED  `log_page` -- and NONE, which is
#                                               `max()` of an empty generator
#   :49-50 `register_mem`             PORTED  `map.run` -- the page EXPANSION
#   :51  `BufferStorage(key, key)`    PORTED  `va_of` -- key twice
#   :52  `_offset` returns `buf`      PORTED  `alloc.offset` -- IDENTITY, no call
#   :53  `_unmap`                     PORTED  `alloc.unmap` -- `.meta`, not `.buf`
#   :56  `functools.cache`            WALL 1  memoisation
#   :57  `node`                       PORTED  `nic.node`  -- three fields, else ""
#   :58  `bus`                        PORTED  `nic.bus`   -- last match, base 16
#   :61  the `except RuntimeError`    PORTED  `nic.list` -- no pcie -> None
#   :64  the closest NIC              PORTED  `nic.closest` -- min |bus - bus|, FIRST
#   :67  `ifaces = [BNXTIface]`       PORTED  `Rdma.ifaces`
#   :69-71 `RDMADevice.__init__`      PORTED  `dev.init` -- iface FIRST, then
#                                               `BNXTAllocator(self), [], None`
#   :79  the anchor `Device[min(pair)]` PORTED `qp.anchor`
#   :80  `{nic.device: BNXTQP(...)}`  PORTED  `qp.new`
#   :82  the four ring buffers        PORTED  `ring_elems.at` -- sq rq scq rcq
#   :83  the three uint64s + `db`     PORTED  `qp_name`/`qp_itemsize` -- sq_seq
#                                               rq_seq psn, db
#   :84  the UPat rules               PORTED  `qp.rules_len` -- 8 tags, FIRST-WINS
#   :85  `PatternMatcher(rules) + pm_bufferize` PORTED `qp_len`
#   :86  `connect` both ways          PORTED  `qp.connect` -- nics THEN reversed
#   :89  `rdma_mem`                   PORTED  `mem.of` -- volatile, dtype, tag
#   :91-92 `rdma_ring`                PORTED  `mem.ring` -- send is WQE+8
#   :93  `rdma_cq`                    PORTED  `mem.cq`   -- 32 bytes an entry
#   :94  `rdma_seq`                   PORTED  `mem.seq`  -- 1 uint64
#   :95  `rdma_psn`                   PORTED  `mem.psn`
#   :96  `rdma_db`                    PORTED  `mem.db`   -- one whole page
#   :99-100 `rdma_wire`               PORTED  `wire.of`  -- CALL/STORE, then RDMA
#   :101 `is_rdma`                    PORTED  `wire.is_rdma`
#   :104-106 `queue_of`               PORTED  `queue.hi`/`queue.lo` -- the SORTED
#                                               pair and
#                                               `wire is src`
#   :109 `ins`                        PORTED  `queue.is_recv` -- every int is a uint32
#   :112 `queue_of(calls[0])`         PORTED  `copies.cap_ok` + `Tr.count`
#   :113 `rdma_qp(pair)[nic.device]`  PORTED  `qp.new`
#   :116 `bufs = [args[c][0 if recv else 1]]` PORTED `ops.wqe`
#   :117 the chunks comprehension     PORTED  `chunks_of` / `nchunks` / `psns_len`
#   :118 `len(chunks), sum(chunks)`   PORTED  `nchunks`, `ops.n_writes`
#   :120 the ring-cap ASSERT          PORTED  `copies.guard`  (the REFUSAL)
#   :123 the bumps                    PORTED  `bump.seq` / `bump.psn`
#   :125 `accumulate(chunks, 0)`      PORTED  `psns_of`
#   :126 `n`, `p`                     PORTED  `ops.n_of` / `ops.p_of`
#   :128 `ring.getaddr`, `cq.getaddr` PORTED  `ins.write` / `ins.cq_db`
#   :129 the `db` address             PORTED  `ins.ring_db` -- low 12 bits only
#   :130-131 `db_value`               PORTED  `db_value.hi` / `db_value.lo`
#   :136-137 the chunk loop           PORTED  `ops.chunk_size` / `ops.wqe`
#   :140 `hdr` and `key`              PORTED  `hdr.of` and `key_of`
#   :141 the ring write               PORTED  `ins.write`
#   :144-145 the msn entry            PORTED  `ins.msn` -- 48/24/24, two halves
#   :148 the ring doorbell            PORTED  `ins.ring_db`
#   :151 `wait_eq`                    PORTED  `ins.wait` -- the inverted epoch
#   :152 the cq doorbell              PORTED  `ins.cq_db`
#   :155 the recv barrier             PORTED  `ins.barrier`
#   :162 the `{i: queue_of(u)}` dict  PORTED  `submit.fires`
#   :164 `ops = [[u] for u in lin.src]` PORTED `submit.src_replaced` -- a NON-rdma src
#                                               keeps ITSELF
#   :165 `dict.fromkeys(queues.values())` PORTED `submit.srcs_kept`
#   :166 `positions`                  PORTED  `submit.pos_at`
#   :167 the zip                      PORTED  `psns_at` + `ops.n_of`
#   :169 `pm_rdma_encode`             PORTED  `encode_len`
#
# ===========================================================================
# THE FIVE WALLS.
#
# 1. MEMOISATION (:56, :77). `functools.cache` on `rdma_nic_for` and `rdma_qp`,
#    keyed on a live device object. Same wall as `device.bend`'s
#    `_opened_devices`, and the same answer: the CACHE KEY is ported -- the
#    anchor name, the sorted pair -- and the cache itself is not.
#    TODO(p3) ops_rdma.py:56  `functools.cache` on a device object.
# 2. THE NETLINK AND THE DRIVER (support/system.py, support/rdma/bnxtdev.py).
#    `System.list_devices(*BNXT_IDS)`, `filter_visible_devices`, `PCIDevice`
#    probing, `BNXTDev` firmware state and the mlx5/bnxt queues. All seams; the
#    PCI ids, the bus number and the node string -- the three things those calls
#    are asked FOR -- are ported.
#    TODO(p3) ops_rdma.py:60  System.list_devices + filter_visible_devices.
#    TODO(p3) ops_rdma.py:22  PCIDevice -- bar probing and firmware.
# 3. `PCIIfaceBase.p2p_paddrs` (:46). The GPU-to-GPU translation into the NIC's
#    address space, for a peer-to-peer mapping. It is a driver call against live
#    peer BARs. The port keeps the BRANCH -- `AddrSpace.SYS` keeps `mapping.paddrs`
#    and everything else is translated -- because the branch is what decides
#    whether the registration is right.
#    TODO(p3) ops_rdma.py:46  PCIIfaceBase.p2p_paddrs.
# 4. `unwrap_view` (:140). Collapsing a view chain to (base, offset) and then
#    `getaddr(nic.device)` on it. The NIC-side address IS the key the
#    registration handed back, so the port reads it out of `Pdt` -- which is the
#    same number, arrived at by the other direction, and that is the point of
#    carrying the table both ways.
#    TODO(p3) ops_rdma.py:140  unwrap_view(...)[0].getaddr(nic.device).
# 5. THE 64-BIT WORDS. Two of them and neither is a TODO, because both are
#    carried as TWO `U32` HALVES and both are exact:
#      `db_value` (bnxtdev.py:13) is `(... << 32) | (index | epoch << 24)`, so
#        `db_value.hi` and `db_value.lo` are both whole halves. AND the low half
#        is 0 whenever `index` and `epoch` are, which is every `db_value` call
#        RDMA makes (:130-131) -- so `ins`'s `UOp.const(s, dtypes.u32)`
#        TRUNCATES the high half away and the doorbell the NIC receives carries
#        only the slot and the epoch. MEASURED, and it is the sharpest thing in
#        this file: `rdma_db_hi_dropped`. REPORTED, not fixed.
#      the msn entry (:145) is `slot << 48 | next << 24 | psn`, all three fields
#        24 bits wide and `slot` in the TOP 16. So `msn.hi(slot, next)` and
#        `msn.lo(next, psn)` are exact halves and no shift is missing.
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind, and there is no
# `import "./x.c"`: the trace IS the record of the call.
#
# THE REFUSALS ARE IN THE TRACE, and there are three of them, and each is one
# Python guard:
#   :44  `not isinstance(iface, PCIIfaceBase) or iface.peer_group !=
#         self.dev.peer_group` -> RuntimeError("RDMA requires memory on its node")
#   :48  `max()` over an empty generator when no page size fits `align`
#   :120 `assert wqes <= min(RING_ENTRIES, CQ_ENTRIES)` -> "a batch posts at most
#         a ring of wqes per pair"
# and a fourth that is not in this file: a work queue element whose buffer has no
# registered KEY must not be posted, which is `:140` read the other way round and
# which no guard in the Python writes down. `Tr.emit` records NOTHING once
# `refused` is set, so every refusal shows up as a TRUNCATED trace and no step
# below needs a guard of its own.
# ===========================================================================
import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S

# ===========================================================================
# THE CONSTANTS. Every one MEASURED, by reading
# `tinygrad/runtime/support/rdma/bnxtdev.py:12` and the enums out of
# `tinygrad/runtime/autogen/bnxt.py`; `.agents/slop/oracle_rdma.py` re-derives
# every gate expectation from them.
# ===========================================================================
def RDMA_CHUNK() -> U32: 1073741824
def PAGE() -> U32: 4096
def WQE_SIZE() -> U32: 128
def RING_ENTRIES() -> U32: 4096
def CQ_ENTRIES() -> U32: 4096
def MTU() -> U32: 4096

# the psn is 24 bits in TWO places (:145) and the doorbell index is 24 bits in
# `db_value` (bnxtdev.py:164). Two constants, one width, and confusing them is
# invisible until a psn wraps.
def PSN_MASK() -> U32: 16777215
def DB_INDEX_MASK() -> U32: 16777215
def DB_EPOCH_SHIFT() -> U32: 24

# bnxt enums, MEASURED out of autogen/bnxt.py.
def DBC_DBC_TYPE_SQ() -> U32: 0
def DBC_DBC_TYPE_RQ() -> U32: 268435456
def DBC_DBC_TYPE_CQ() -> U32: 1073741824
def DBC_DBC_XID_MASK() -> U32: 1048575
def DBC_DBC_PATH_ROCE() -> U32: 0
def BNXT_QPLIB_DBR_VALID() -> U32: 67108864
def SQ_SEND_FLAGS_SIGNAL_COMP() -> U32: 1

# ops_rdma.py:18 -- `BNXT_IDS = (0x14e4, ((0xffff, (0x1760,)),), 0x02)`.
def BNXT_VENDOR() -> U32: 5348
def BNXT_MASK() -> U32: 65535
def BNXT_DEVICE_ID() -> U32: 5984
def BNXT_BASE_CLASS() -> U32: 2
# :22 `vram_bar=2`. And the doorbell (:36) maps bar 2 as well, so one constant.
def VRAM_BAR() -> U32: 2

# `send_wqe`/`recv_wqe` (bnxtdev.py:18-19), `struct.pack("<BBB5xI20xQII", 0,
# SQ_SEND_FLAGS_SIGNAL_COMP, 3, size, va, key, size)` and `("<BBB29xQII", 0x80,
# 0, 3, va, key, size)`. Word 0 of the 32-byte header is `type << 16 | flags << 8
# | kind`, and the 3 IS the same in both packs -- it is the "size in 16-byte
# units" field, so a header says the wqe is three 16-byte units long.
def WQE_KIND() -> U32: 3
def RECV_KIND() -> U32: 128
def HDR_WORDS() -> U32: 8
# the `I size` at offset 8 exists in the SEND pack and NOT in the receive pack,
# whose 29-byte pad runs over it. That is why `hdr.of` takes the size only on the
# send side and `rdma_hdr_recv_size` is the row that says the receive header's
# word 2 is ZERO however big the transfer is.
def SEND_SIZE_AT() -> U32: 2

# ops_rdma.py:48 -- `(12, 13, 16, 18, 20, 21, 22, 30)`, the page sizes the NIC
# has, in ASCENDING order. `log_page` takes the LAST match, which is the
# `max()`, so this order is load-bearing.
def LP_12() -> U32: 12
def LP_13() -> U32: 13
def LP_16() -> U32: 16
def LP_18() -> U32: 18
def LP_20() -> U32: 20
def LP_21() -> U32: 21
def LP_22() -> U32: 22
def LP_30() -> U32: 30

# the `None` answers.
def NO_KEY() -> U32: 0
def NO_LOG_PAGE() -> U32: 0

# ops_rdma.py:48 `if not align & ((1 << l) - 1)`, and ops_rdma.py:145's three
# 24-bit fields and the 48-bit slot shift, as U32 constants.
def LP_MASK_OF(l: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(l)), 1)
def MSN_PSN_AT() -> U32: 24
def MSN_SLOT_HI_AT() -> U32: 16

# `AddrSpace` (support/memory.py) is `[PHYS, SYS, PEER]`, so SYS is index 1.
def ASPACE_SYS() -> U32: 1

# ops_rdma.py:35 `& ~0xfff` and :129 `& 0xfff`. The same mask used twice, in
# OPPOSITE directions, and that is the whole of the doorbell's address: map the
# PAGE the doorbell lives in, then write at the low twelve bits INSIDE it.
def PAGE_MASK() -> U32: 4095

# ===========================================================================
# THE TRACE VOCABULARY. Sixteen device calls.
#
# The FFI half: the NIC and its driver.
#   OPEN         :22   `BNXTIface(...)` -> `PCIIfaceBase.__init__` -> `PCIDevice`
#   DEVICE       :70   `_select_iface` returning, then `Compiled.__init__`
#   MAP_BAR      :36   `pci_dev.map_bar(2, off=off, size=0x1000)`
#   BAR_INFO     :36   `pci_dev.bar_info(2)`
#   ALLOC_SYSMEM :40   `pci_dev.alloc_sysmem(round_up(size, 0x1000))`
#   ALLOC_VADDR  :27   `MemoryManager.alloc_vaddr(round_up(nbytes, 0x1000), 0x1000)`
#   REGISTER     :50   `dev_impl.register_mem(paddrs, size, log_page, va=va)`
#   UNREGISTER   :53   `dev_impl.unregister_mem(storage.meta)`
#   QP_NEW       :80   `BNXTQP(nic.iface.dev_impl)`
#   QP_CONNECT   :86   `qps[a].connect(qpn, gid, mac)`
#   FINI         :24   `dev_impl.fini()`
#   BUFFER       :31   `Buffer(dev.device, mem.nbytes, uint8, opaque=storage)`
# The KERNEL half: the instruction stream `rdma_copies` emits.
#   INS_WRITE    :141  the work queue element
#   INS_WAIT     :151  `wait_eq` on the completion entry
#   INS_BARRIER  :155  the receive-side cache invalidate
# ===========================================================================
def CALL_OPEN() -> U32: 0
def CALL_DEVICE() -> U32: 1
def CALL_MAP_BAR() -> U32: 2
def CALL_BAR_INFO() -> U32: 3
def CALL_ALLOC_SYSMEM() -> U32: 4
def CALL_ALLOC_VADDR() -> U32: 5
def CALL_REGISTER() -> U32: 6
def CALL_UNREGISTER() -> U32: 7
def CALL_QP_NEW() -> U32: 8
def CALL_QP_CONNECT() -> U32: 9
def CALL_FINI() -> U32: 10
def CALL_BUFFER() -> U32: 11
def CALL_INS_WRITE() -> U32: 12
def CALL_INS_WAIT() -> U32: 13
def CALL_INS_BARRIER() -> U32: 14
def CALL_REFUSE() -> U32: 15

# the four calls that create an object record their OBJECT KIND in `arg`; the
# other twelve record a number instead. 0 is the FFI handle the seam returns.
def OBJ_NONE() -> U32: 0

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE device call and the ONE number it is given: a bar, an offset, a size, a
# page count, or the ADDRESS of an instruction. There is deliberately no field
# for the rest of the arguments -- those are what the defs around this record
# build, and the gate reads them from the record a def RETURNS.
type Call is Data:
  Call{k: U32, arg: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool}

# ONE registered region: the GPU's virtual address and the NIC's key for it.
# `Pdt` is the ADDRESS TRANSLATION TABLE and it is carried in BOTH directions,
# because `:140` needs `key_of(gpu_addr)` and a gate that only checks one
# direction cannot tell a translation from a copy. `NO_KEY` is Python's `None`.
type PEnt is Data:
  PEnt{va: U32, key: U32}

type Pdt is Data:
  Pdt{es: List<&2, PEnt>}

# ops_rdma.py:20-36 `BNXTIface`, only what the file itself writes: the device it
# was opened for, its index, and the three `__init__` constants that are not
# read back out of `va_start`/`va_size`. `db_off` is `BNXTDev`'s and is a
# parameter of `db.of` because `BNXTDev` is a WALL.
type Iface is Data:
  Iface{dev: String, ix: U32, bar: U32, base_class: U32, db_off: U32, snooped: Bool, t: Tr}

# ops_rdma.py:66-71 `RDMADevice`: the device string, the ONE iface, the
# allocator `BNXTAllocator(self)` names, and the `[]` that device.py:396 turns
# into `[Renderer]` exactly as it does for `ops_npy.bend`.
type Rdma is Data:
  Rdma{dev: String, ifaces: U32, alloc: U32, runtime: U32, nrender: U32, did: U32, peer: String, t: Tr}

# ONE work queue element's worth of derived state: its index `n` in the ring, its
# psn `p`, its offset into the buffer, and its size. All four are read by more
# than one instruction, so they travel together rather than being recomputed.
type Wqe is Data:
  Wqe{n: U32, p: U32, off: U32, size: U32}

def Wqe.n(w: Wqe) -> U32:
  match w:
    case Wqe{n, p, off, size}: n

def Wqe.p(w: Wqe) -> U32:
  match w:
    case Wqe{n, p, off, size}: p

def Wqe.off(w: Wqe) -> U32:
  match w:
    case Wqe{n, p, off, size}: off

def Wqe.size(w: Wqe) -> U32:
  match w:
    case Wqe{n, p, off, size}: size

# ===========================================================================
# THE TRACE. Every device call in this file goes through `Tr.emit`, so the trace
# is the ordered list of things the NIC would be asked to do.
# ===========================================================================
def Tr.of() -> Tr: Tr{Nil{}, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused}: refused

def Tr.ncalls(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# an EMPTY trace that KEEPS `refused`, so a gate can read one queue without the
# registration in front of it and still see a truncation.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused}: Tr{Nil{}, 0, refused}

def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>, +next: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])), Bool.pick(U32, refused, next, U32.add(next, 1)), refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +next, refused}: Tr.emit.go(refused, k, arg, calls, next)

# A REFUSAL IS RECORDED AND IS ALSO THE THING THAT TRUNCATES. `refused` is set
# unconditionally -- the raise IS the refusal -- while the ENTRY is guarded, so a
# trace that is already refused stays empty. That is the one arrangement that
# models `raise` correctly for a device whose refusals are not nested, and
# `rdma_refuse_nested` says the nesting never happens here rather than leaving it
# to be assumed.
def Tr.refuse.go(+refused: Bool, +calls: List<&2, Call>, +next: U32, which: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{CALL_REFUSE(), which}])), next, True{}}

def Tr.refuse(which: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +next, refused}: Tr.refuse.go(refused, calls, next, which)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# the four refusals, in the order the Python can reach them.
def REFUSE_MAP() -> U32: 0
def REFUSE_LOG_PAGE() -> U32: 1
def REFUSE_RING_CAP() -> U32: 2
def REFUSE_NO_KEY() -> U32: 3

def REFUSE_MAP_MSG() -> String: "RDMA requires memory on its node"
def REFUSE_RING_CAP_MSG() -> String: "a batch posts at most a ring of wqes per pair"

# ===========================================================================
# READING THE TRACE. Same three readers as ops_webgpu.bend, and the same fuel bug
# they were written around: the fuel is the TRACE's length and the answer is
# `at == patlen`, so a reversed pattern does NOT match.
# ===========================================================================
def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def ustr(xs: List<&2, U32>) -> String: String.join(ush(xs, ",", Nil{}), ",")

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", ustr(xs)]))
# ===========================================================================
# THE TRANSLATION TABLE, and both directions.
#
# :140 `unwrap_view(buf)[0].getaddr(nic.device)` asks the DEVICE what address the
# NIC has for that buffer, and the answer is the key `_map` was given at :50.
# :141 then puts the GPU's address AND that key in the same work queue element.
# So the table has a forward direction (`key_of(va)`) and a reverse one
# (`va_of(key)`), and a gate that only checked the forward one could not tell a
# translation from two independent tables. Both are first-wins, because
# `register_mem` is called once per mapping and a second registration of the
# same address is a bug the seam reports.
# ===========================================================================
def Pdt.of() -> Pdt: Pdt{Nil{}}

def Pdt.put(+t: Pdt, e: PEnt) -> Pdt:
  match t:
    case Pdt{es}: Pdt{List.append(&2, PEnt, es, [e])}

def Pdt.put2(+va: U32, +key: U32, t: Pdt) -> Pdt: Pdt.put(t, PEnt{va, key})

def Pdt.es(+t: Pdt) -> List<&2, PEnt>:
  match t:
    case Pdt{es}: es

def PEnt.va(e: PEnt) -> U32:
  match e:
    case PEnt{va, key}: va

def PEnt.key(e: PEnt) -> U32:
  match e:
    case PEnt{va, key}: key

def Pdt.len(+t: Pdt) -> U32: U32.from_nat(List.length(&2, PEnt, Pdt.es(t)))

# the forward direction. `hit` is the same first-wins shape as
# `device.bend`'s `claim_row` and `ops_webgpu.bend`'s `backend_of.put`.
def key_of.put(+e: PEnt, +va: U32, +got: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_zero(got), U32.is_eq(PEnt.va(e), va)), PEnt.key(e), got)

def key_of.go(n: Nat, es: List<&2, PEnt>, +va: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match es:
        case Nil{}: got
        case e <> r: key_of.go(m, r, va, key_of.put(e, va, got))

# the reverse direction, which is the same scan with the other field.
def va_of.put(+e: PEnt, +key: U32, +got: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_zero(got), U32.is_eq(PEnt.key(e), key)), PEnt.va(e), got)

def va_of.go(n: Nat, es: List<&2, PEnt>, +key: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match es:
        case Nil{}: got
        case e <> r: va_of.go(m, r, key, va_of.put(e, key, got))

def key_of(+t: Pdt, +va: U32) -> U32:
  key_of.go(List.length(&2, PEnt, Pdt.es(t)), Pdt.es(t), va, 0)

def va_of(+t: Pdt, +key: U32) -> U32:
  va_of.go(List.length(&2, PEnt, Pdt.es(t)), Pdt.es(t), key, 0)

# ===========================================================================
# ops_rdma.py:47-48 -- THE PAGE-SIZE DERIVATION, and it is the pure heart of
# this file.
#
#   align = buf._buf | functools.reduce(operator.or_, (p | s for p, s in paddrs))
#   log_page = max(l for l in (12, 13, 16, 18, 20, 21, 22, 30)
#                  if not align & ((1 << l) - 1))
#
# `align` is the OR of the GPU address and every (physical address | length), so
# it is the LOWEST common power of two that divides all of them -- and `log_page`
# is the largest NIC page size that divides `align`. Bigger pages means fewer PBL
# entries, which is the comment at :47. TWO things follow and the gate pins both:
#   * the candidate list is ASCENDING, so `max()` is "the LAST match" and a fold
#     that keeps the FIRST match answers 12 for everything;
#   * an address with a low bit set matches NOTHING, and `max()` of an empty
#     generator is a `ValueError`. `NO_LOG_PAGE` is that, and `map.run` REFUSES
#     rather than registering with a page size of zero.
# ===========================================================================
# one region `(paddr, size)` folded into the running alignment.
def align_or.put(pa: U32, sz: U32, acc: U32) -> U32:
  U32.or(acc, U32.or(pa, sz))

def align_or.go(n: Nat, ps: List<&2, U32>, ss: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match ps:
        case Nil{}: acc
        case p <> rp:
          match ss:
            case Nil{}: acc
            case s <> rs: align_or.go(m, rp, rs, align_or.put(p, s, acc))

def align_or(+va: U32, +ps: List<&2, U32>, +ss: List<&2, U32>) -> U32:
  align_or.go(List.length(&2, U32, ps), ps, ss, va)

# the eight candidates, ascending.
def lp_cands() -> List<&2, U32>:
  [LP_12(), LP_13(), LP_16(), LP_18(), LP_20(), LP_21(), LP_22(), LP_30()]

# `not align & ((1 << l) - 1)` -- one candidate.
def lp_hit(+align: U32, l: U32) -> Bool: U32.is_zero(U32.and(align, LP_MASK_OF(l)))

# LAST-wins over an ASCENDING list, which is `max()`. `got` starts at
# `NO_LOG_PAGE`, so "no candidate matched" and "12 matched" are different
# numbers and the empty case is visible instead of silently answering 12.
def log_page.put(+l: U32, align: U32, got: U32) -> U32:
  Bool.pick(U32, lp_hit(align, l), l, got)

def log_page.go(n: Nat, ls: List<&2, U32>, +align: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ls:
        case Nil{}: got
        case l <> r: log_page.go(m, r, align, log_page.put(l, align, got))

def log_page(+align: U32) -> U32:
  log_page.go(List.length(&2, U32, lp_cands()), lp_cands(), align, NO_LOG_PAGE)

def has_page(align: U32) -> Bool: Bool.not(U32.is_zero(log_page(align)))

# ops_rdma.py:49 -- `[p + off for p, size in paddrs for off in range(0, size, 1 <<
# log_page)]`. Each region is split into pages of `1 << log_page`, and the list
# is what `register_mem` is handed. The COUNT is the claim a gate can read: two
# 4 KiB regions at log_page 12 are two entries, and one 8 KiB region is two.
def npages_of(+size: U32, +lp: U32) -> U32:
  Bool.pick(U32, U32.is_zero(lp), 0, U32.div(size, U32.shln(1, U32.to_nat(lp))))

def npages.go(n: Nat, ss: List<&2, U32>, +lp: U32, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match ss:
        case Nil{}: acc
        case s <> r: npages.go(m, r, lp, U32.add(acc, npages_of(s, lp)))

def npages(+ss: List<&2, U32>, +lp: U32) -> U32:
  npages.go(List.length(&2, U32, ss), ss, lp, 0)

# ===========================================================================
# ops_rdma.py:89-96 -- the six placeholder constructors. Their SIZES are the
# whole content and they are not interchangeable: the SEND ring is
# `RING_ENTRIES * (WQE_SIZE + 8)` because a send also writes an 8-byte msn entry
# past the end of the ring (:144), so the send ring is BIGGER than the receive
# ring and a port that drops the `+ 8` under-allocates every send queue.
# ===========================================================================
def ring_elems.at(recv: Bool) -> U32:
  Bool.pick(U32, recv, WQE_SIZE(), U32.add(WQE_SIZE(), 8))

def ring_elems(+recv: Bool) -> U32: ring_elems.at(recv)

def ring_elems_of(+recv: Bool) -> U32: U32.mul(RING_ENTRIES(), ring_elems.at(recv))

def cq_elems() -> U32: U32.mul(CQ_ENTRIES(), 32)

def seq_elems() -> U32: 1
def seq_bytes() -> U32: U32.mul(seq_elems(), S.Dt.itemsize(S.uint64()))
def psn_bytes() -> U32: seq_bytes()
def db_elems() -> U32: PAGE()

# ops_rdma.py:82-83 -- the EIGHT names `rdma_qp` builds buffers for, IN ORDER. Four
# rings, then three one-element uint64 counters, then the doorbell. The ORDER is
# the dict's insertion order and it is what `PatternMatcher(rules)` iterates, so
# two rules claim the same PARAM only if two names collide -- they do not.
def QP_BUFS() -> List<&2, U32>: [1, 2, 3, 4, 5, 6, 7, 8]

def qp_name(k: U32) -> String:
  match k:
    case 1: "sq"
    case 2: "rq"
    case 3: "scq"
    case 4: "rcq"
    case 5: "sq_seq"
    case 6: "rq_seq"
    case 7: "psn"
    case _: "db"

def qp_name_at(i: Nat) -> String: qp_name(U32.from_nat(i))

def qp_len() -> U32: U32.from_nat(List.length(&2, U32, QP_BUFS()))

# ops_rdma.py:83 -- the three counters are `Buffer(dev, 1, uint64, initial_value=
# bytes(8))`, so each is ONE ELEMENT and EIGHT BYTES. `qp_name_dtypes` is the
# dtype table in the direction that matters: which of the eight are uint64 and
# which are uint8.
def qp_is_counter(+k: U32) -> Bool: Bool.and(U32.is_ge(k, 5), U32.is_le(k, 7))

def qp_itemsize(+k: U32) -> U32:
  Bool.pick(U32, qp_is_counter(k), S.Dt.itemsize(S.uint64()), S.Dt.itemsize(S.uint8()))

# ===========================================================================
# `to_name` (tinygrad/helpers.py:24) -- `"_".join(parts).replace(":", "_").lower()`.
# It is the TAG every `rdma_mem` placeholder carries and the key every
# `pm_bufferize` rule matches on (:84), so a `to_name` that did not lower-case
# would match nothing and a rule table that is silently empty posts nothing.
#
# The lower-case happens on the JOINED string, so it also lower-cases the
# separators -- which is unobservable here because `_` is already lower, and
# WHICH IS WHY THE PORT DOES NOT DEPEND ON IT: the port lower-cases each part
# before joining and the two agree for every device name in the tree.
# ===========================================================================
def COLON_C() -> Char: Char.from_u32(58)
def UNDER_C() -> Char: Char.from_u32(95)

def tname.put(+h: Char, +acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, acc, [Bool.pick(Char, Char.is_eq(h, COLON_C()), UNDER_C(), h)])

def tname.go(n: Nat, cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case h <> t: tname.go(m, t, tname.put(h, acc))

# `str.replace(":", "_").lower()`, as one fold. base.bend exports no `replace` and
# no `map`, so this is the character walk.
def tname(+s: String) -> String:
  String.to_lower(String.from_list(tname.go(List.length(&2, Char, String.to_list(s)), String.to_list(s), Nil{})))

# `to_name("rdma", lo, hi, name)` -- the four parts joined with `_`, in THIS
# order. The order is the claim: `to_name("rdma", *pair, n)` at :84 and
# `to_name("rdma", *pair, name)` at :90 must produce the same string for the
# same buffer or no rule ever fires.
def tag_of(+lo: String, +hi: String, +name: String) -> String:
  String.concat(["rdma_", tname(lo), "_", tname(hi), "_", tname(name)])

# ===========================================================================
# ops_rdma.py:20-24 -- `BNXTIface`, the ONE interface `RDMADevice.ifaces` names.
#
# :21-23 `super().__init__(dev, index, *BNXT_IDS[:2], vram_bar=2,
# va_start=MemoryManager.va_allocator.base, va_size=…, dev_impl_t=BNXTDev,
# base_class=BNXT_IDS[2])`. FOUR of those are constants this file can carry --
# the vendor, the (mask, device id) pair, `vram_bar=2` and `base_class=2` -- and
# two are the virtual-address ALLOCATOR's own base and size, which belong to
# `MemoryManager` and are therefore a WALL. `dev_impl_t=BNXTDev` is the driver.
# `index` arrives from `_select_iface` (device.py:494), which sets
# `self.device_id` from the device string BEFORE the assert, and that ordering is
# the one thing about it that is visible here.
# ===========================================================================
def Iface.of(dev: String, +index: U32, db_off: U32) -> Iface:
  Iface{dev, index, VRAM_BAR(), BNXT_BASE_CLASS(), db_off, True{}, Tr.emit(CALL_OPEN(), BNXT_VENDOR(), Tr.of())}

def Iface.tr(i: Iface) -> Tr:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: t

def Iface.dev(i: Iface) -> String:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: dev

def Iface.ix(i: Iface) -> U32:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: ix

def Iface.bar(i: Iface) -> U32:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: bar

def Iface.base_class(i: Iface) -> U32:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: base_class

def Iface.db_off(i: Iface) -> U32:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: db_off

def Iface.snooped(i: Iface) -> Bool:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, t}: snooped

# `MemoryManager.va_allocator.base` / `.size` (support/memory.py) -- WALL: they
# are the kernel's own allocator window and they are read out of a global. What
# is PORTED is that the interface OWNS a virtual-address window at all, which is
# what makes `storage` allocate one per buffer instead of reusing a fixed
# mapping -- and that `vram_bar` is the bar it comes from.

# `MemoryManager.va_allocator.base` / `.size` -- WALL. What is PORTED is that the
# interface OWNS a virtual-address window at all, which is what makes `storage`
# allocate one per buffer instead of reusing a fixed mapping.
def Iface.va_owned(i: Iface) -> Bool: Bool.not(U32.is_zero(Iface.bar(i)))

def Iface.at(i: Iface, t: Tr) -> Iface:
  match i:
    case Iface{dev, ix, bar, base_class, db_off, snooped, _}:
      Iface{dev, ix, bar, base_class, db_off, snooped, t}

# :24 `device_fini` -- `self.dev_impl.fini()`, and it is the LAST thing a device
# does. `RDMA_FINI_LAST` in the gate is the row that says so.
def iface.fini(+i: Iface) -> Iface: Iface.at(i, Tr.emit(CALL_FINI(), OBJ_NONE(), Iface.tr(i)))

# ===========================================================================
# ops_rdma.py:66-71 -- `RDMADevice`, and the ORDER of its two statements.
#
#     self.iface = self._select_iface(device)          # :70
#     super().__init__(device, BNXTAllocator(self), [], None)   # :71
#
# The iface comes FIRST and the allocator is handed `self`, so at the moment
# `HostAllocator.__init__`-equivalent runs the device already has an interface.
# `[]` is `renderers or [Renderer]` at device.py:396 and is falsy, exactly as in
# `ops_npy.bend` -- the same one-token fact, and the same reason it is a row.
# `peer_group` (device.py:398) is `Rdma.peer` here and NOT the device
# head, because `self.iface` EXISTS. That is the difference from NPY and it is
# load-bearing: `_map`'s guard at :44 compares two peer groups.
# ===========================================================================
def ALLOC_BNXT() -> U32: 1
def RENDERERS_PASSED() -> U32: 0
def RENDERERS_EFFECTIVE() -> U32: 1
def RUNTIME_NONE() -> U32: 0

# :398 `self.peer_group = getattr(getattr(self, 'iface', None), 'peer_group',
# device.split(":")[0])` -- and `self.iface` EXISTS here, so the DEVICE HEAD IS
# NOT THE ANSWER. `PCIIfaceBase.peer_group` (support/system.py:297) is
# `getattr(self.pci_dev, 'peer_group', type(self.pci_dev).__name__)` and a plain
# `PCIDevice` has no `peer_group`, so it answers the CLASS NAME.
# MEASURED: `Fake(PCIDevice()).peer_group` is `"PCIDevice"`. Only a
# `USBPCIDevice` (which sets `f"USBPCIDevice_{pcibus}"`, :272) or a
# `RemotePCIDevice` (which sets `"remote:%s:%d"`, :430) answers anything else.
#
# AND IT MATTERS: :44's guard is `iface.peer_group != self.dev.peer_group`, so
# with both sides reading "PCIDevice" the guard passes for ANY TWO PLAIN PCIe
# devices and only catches a USB or remote one. A port that used the device head
# would refuse every cross-device mapping and, worse, would make the guard's two
# conjuncts look like they were doing node selection when they are not.
def PEER_PCI() -> String: "PCIDevice"
def PEER_CLASS_NAME() -> U32: 0

def Rdma.of(+dev: String, +ix: U32) -> Rdma:
  Rdma{dev, 1, ALLOC_BNXT(), RUNTIME_NONE(), RENDERERS_EFFECTIVE(), ix, PEER_PCI(), Tr.of()}

def Rdma.dev(r: Rdma) -> String:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: dev

def Rdma.ifaces(r: Rdma) -> U32:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: ifaces

def Rdma.alloc(r: Rdma) -> U32:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: alloc

def Rdma.runtime(r: Rdma) -> U32:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: runtime

def Rdma.nrender(r: Rdma) -> U32:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: nrender

def Rdma.did(r: Rdma) -> U32:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: did

def Rdma.peer(r: Rdma) -> String:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: peer

def Rdma.tr(r: Rdma) -> Tr:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}: t

def Rdma.at(r: Rdma, t: Tr) -> Rdma:
  match r:
    case Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, _}:
      Rdma{dev, ifaces, alloc, runtime, nrender, did, peer, t}

# :69-71 as ONE def, so a version that called `super().__init__` first would move
# `rdma_init_order` and not just some later count.
def dev.init(+dev_name: String, +db_off: U32) -> Tr:
  Tr.emit(CALL_DEVICE(), D.dev_id(dev_name), Iface.tr(Iface.of(dev_name, D.dev_id(dev_name), db_off)))

# ===========================================================================
# ops_rdma.py:26-31 -- `BNXTIface.storage` and `BNXTIface.buffer`, and THE
# DIVERGENCE between them.
#
#   storage: va = MemoryManager.alloc_vaddr(size := round_up(mem.nbytes, 0x1000), 0x1000)
#            mapping = VirtMapping(va, size, [(p, 0x1000) for p in paddrs],
#                                 AddrSpace.SYS, uncached=True, snooped=snooped)
#            return BufferStorage(va, PCIAllocationMeta(mapping, True), mem)
#   buffer:  Buffer(self.dev.device, mem.nbytes, dtypes.u8, opaque=self.storage(…))
#
# The buffer's SIZE is `mem.nbytes` RAW and the virtual address covers
# `round_up(mem.nbytes, 0x1000)`. So a 12-byte allocation maps 4096 bytes and the
# buffer says 12 -- and both numbers are right, because `nbytes` is
# `size * dtype.itemsize` (device.py:153) and the mapping is what the NIC needs.
# `rdma_buf_nb_vs_va` is that pair and it is the row that dies if a port rounds
# the buffer's size as well.
#
# `AddrSpace.SYS` and `uncached=True` are CONSTANTS at every call site, and
# `snooped` defaults to True -- everywhere except the doorbell, which says
# `snooped=False`. `rdma_snooped_doorbell` is that one difference.
# ===========================================================================
def VA_ALIGN() -> U32: 4096
def STORAGE_ARGS() -> U32: 3

# :27 the VA size: `round_up(mem.nbytes, 0x1000)`. The walrus means `size` is the
# ROUNDED number and the mapping at :28 uses it, so the mapping is page-exact.
def alloc.va_size(+nbytes: U32) -> U32: H.round_up_u32(nbytes, VA_ALIGN())

# :31 the buffer's size: `mem.nbytes`, RAW. Not rounded, and the difference is
# the whole point.
def alloc.buf_size(+nbytes: U32) -> U32: nbytes

def alloc.va(+nbytes: U32, t: Tr) -> Tr:
  Tr.emit(CALL_ALLOC_VADDR(), alloc.va_size(nbytes), t)

def alloc.mem(nbytes: U32, t: Tr) -> Tr: alloc.va(nbytes, t)

# :39-40 `_alloc` -- `round_up(size, 0x1000)` and THEN `storage(*alloc_sysmem(…))`,
# so the size is rounded TWICE. `round_up(round_up(x, P), P) == round_up(x, P)` and
# `rdma_alloc_double_round` is the row that says the second rounding is a no-op, so
# an implementation that passed the raw size to `alloc_sysmem` would be wrong only
# about the SYSMEM allocation and not about the VA.
def alloc.sysmem_size(+size: U32) -> U32: H.round_up_u32(size, VA_ALIGN())

def alloc.sysmem(+size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_ALLOC_SYSMEM(), alloc.sysmem_size(size), t)

def alloc.of(+size: U32, t: Tr) -> Tr: alloc.mem(size, alloc.sysmem(size, t))

# :41 `_copyin` -- `unwrap(dest.host)[:len(src)] = src`. The LENGTH IS THE
# SOURCE'S, and the trace records it. There is no `synchronize` here, which is
# the difference from `HostAllocator._copyin` (device.py:322): the RDMA device's
# host copies are ordered by the queue, not by a device-wide barrier.
def alloc.copyin(+len: U32, t: Tr) -> Tr: Tr.emit(CALL_INS_WRITE(), len, t)

# ===========================================================================
# ops_rdma.py:33-36 -- the DOORBELL, and the one flag that is False here and True
# everywhere else.
#
#   off = self.dev_impl.db_off & ~0xfff
#   return self.buffer(self.pci_dev.map_bar(2, off=off, size=0x1000),
#                      [self.pci_dev.bar_info(2)[0] + off], snooped=False)
#
# `~0xfff` pages the doorbell offset DOWN -- the mapping must start on a page --
# and then the same `off` is added to the bar base to make the physical address
# list. So the mapping's offset and the paddr's displacement are THE SAME NUMBER,
# and :129 uses the OTHER half of it: `rdma_db(page).getaddr(devs) + (db_off &
# 0xfff)`, the low twelve bits, because the placeholder is a WHOLE PAGE. Three
# spellings of one address and the gate checks all three.
# ===========================================================================
def db.off_down(+db_off: U32) -> U32: U32.and(db_off, U32.not(PAGE_MASK()))

def db.off_up(+db_off: U32) -> U32: U32.and(db_off, PAGE_MASK())

def db.of(+db_off: U32, t: Tr) -> Tr:
  Tr.emit(CALL_BAR_INFO(), VRAM_BAR(), Tr.emit(CALL_MAP_BAR(), db.off_down(db_off), t))

# the physical address the doorbell lives at: `bar_info(2)[0] + off`, with the
# SAME `off` the mapping used.
def db.paddr(+bar_base: U32, +db_off: U32) -> U32: U32.add(bar_base, db.off_down(db_off))

# :129 -- the address the instruction stream writes: the whole-page placeholder's
# address PLUS the low twelve bits. Two masks, opposite directions, same constant.
def db.addr(+page: U32, +db_off: U32) -> U32: U32.add(page, db.off_up(db_off))

def db.snooped() -> Bool: False{}


# ===========================================================================
# ops_rdma.py:42-53 -- `BNXTAllocator._map`, and it is the whole buffer-registration
# contract in five lines. This is the section the brief is about.
#
#   iface = getattr(Device[buf.device], "iface", None)
#   if not isinstance(iface, PCIIfaceBase) or iface.peer_group !=
#      self.dev.peer_group: raise RuntimeError("RDMA requires memory on its node")
#   mapping = buf.meta.mapping
#   paddrs = mapping.paddrs if mapping.aspace is AddrSpace.SYS else
#            PCIIfaceBase.p2p_paddrs(iface, mapping.paddrs)[0]
#   align  = buf._buf | functools.reduce(operator.or_, (p | s for p, s in paddrs))
#   log_page = max(l for l in (12, 13, 16, 18, 20, 21, 22, 30)
#                  if not align & ((1 << l) - 1))
#   key = self.dev.iface.dev_impl.register_mem([p + off for p, size in paddrs
#                     for off in range(0, size, 1 << log_page)],
#                     mapping.size, log_page, va=buf._buf)
#   return BufferStorage(key, key)
#
# FOUR claims the gate pins, and they are four different kinds:
#   1. THE NODE GUARD (:44) is TWO conjuncts and both are needed -- the buffer's
#      device must have a `PCIIfaceBase` AT ALL, and its peer group must be the
#      NIC's. A buffer on another node is a silently wrong transfer if it is not
#      refused, so `map.peer_ok` is False and `map.run` refuses, so the trace
#      truncates.
#   2. THE ASPACE BRANCH (:46) -- `AddrSpace.SYS` keeps `mapping.paddrs` and
#      everything else is TRANSLATED by `p2p_paddrs`, because the NIC reaches
#      peer GPU memory over PCIe even where two GPUs reach each other over XGMI.
#      That is the comment at :45 and it is the whole reason the registration is
#      per-buffer at all.
#   3. THE PAGE SIZE (:48) -- `log_page`, above. `map.page_guard` refuses when
#      there is none, which is `max()` of an empty generator.
#   4. `BufferStorage(key, key)` (:51) -- the KEY IS BOTH `.buf` AND `.meta`, so
#      the address the GPU stops using and the handle the NIC uses are the same
#      number, and `_unmap` at :53 can hand it straight back. `va_of` is that
#      claim as a COUNT, because a BufferStorage that kept the GPU address
#      in `.buf` would still unregister correctly and would be silently wrong for
#      every transfer.
# ===========================================================================
def map.peer_ok(+has_iface: Bool, src_peer: U32, dev_peer: U32) -> Bool:
  Bool.and(has_iface, U32.is_eq(src_peer, dev_peer))

def map.msg() -> String: REFUSE_MAP_MSG()

# :46 -- the branch. `SYS` keeps the addresses the mapping already has; anything
# else needs the peer's bars, which is WALL 3.
def map.paddrs(sys: Bool, +raw: List<&2, U32>, +translated: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, sys, raw, translated)

# :50 -- the page expansion. `register_mem` is handed ONE ADDRESS PER PAGE of
# `1 << log_page`, so the count is `size >> log_page` per region. `npages` above
# computes it and `map.call` records it as the call's `arg`, which is the one
# number the trace can carry for a variable-length list -- and the gate checks the
# COUNT, because a `register_mem` handed whole regions instead of pages registers
# fewer entries and accepts the same memory.
def map.call(+n: U32, t: Tr) -> Tr: Tr.emit(CALL_REGISTER(), n, t)

# The three refusals and the one call, as four defs, because Python writes them as
# four statements and the ORDER that produced the key is the port.
def map.guard2(ok: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, ok, t, Tr.refuse(REFUSE_MAP(), t))

def map.page_guard(ok: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, ok, t, Tr.refuse(REFUSE_LOG_PAGE(), t))

def map.key_guard(+key: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, Bool.not(U32.is_zero(key)), t, Tr.refuse(REFUSE_NO_KEY(), t))

# :42-53 `_map` as ONE def, so a version that registered before checking the peer
# group would move `rdma_map_order` and not merely some later count. The
# alignment is computed ONCE and both the page guard and the page count read that
# same number: an `align` that disagreed with the `log_page` derived from it is
# the bug this shape exists to make impossible.
# THE GUARDS ARE NESTED INSIDE THE CALL, not outside it, and that is the whole
# difference between a refusal and a warning. Python raises at :48 -- the `max()`
# -- BEFORE it reaches `register_mem` at :50, so a buffer with no usable page size
# is NEVER REGISTERED. With the guards outside the call the trace would read
# `REGISTER(0), REFUSE(log_page)`: the registration happened and THEN the refusal,
# which is the opposite of what the source does. MEASURED: with the guards
# outside, `rdma_map_odd_regs` was 1; nested inside, it is 0. That was a real port
# bug and the oracle found it.
def map.run(+has_iface: Bool, src_peer: U32, dev_peer: U32, +sys: Bool, +va: U32,
            +raw: List<&2, U32>, +translated: List<&2, U32>, +sizes: List<&2, U32>,
            mapping_size: U32, t: Tr) -> Tr:
  map.call(npages(sizes, log_page(align_or(va, map.paddrs(sys, raw, translated), sizes))),
           map.page_guard(has_page(align_or(va, map.paddrs(sys, raw, translated), sizes)),
                          map.guard2(map.peer_ok(has_iface, src_peer, dev_peer), t)))

# :51 `BufferStorage(key, key)` -- the key is BOTH fields, and both fields are the
# key. A count, because a one-argument BufferStorage would drop `.meta` and then
# `_unmap` would have nothing to hand back.
def MAP_ST_ARGS() -> U32: 2

# :52 `_offset` -- `return buf`, UNCHANGED. Not a missing `+ offset` and not a
# simplification: a NIC-addressed buffer has no GPU-visible offset arithmetic,
# because the offset that matters is inside the key. THIS IS THE NEGATIVE CASE the
# brief asked for and it is a pure one -- the trace for `_offset` is EMPTY, so
# `rdma_offset_n = 0` is the row, and an implementation that added the offset
# would print a different number in `rdma_offset_val` rather than a different
# trace. Contrast `ops_npy.bend`'s `npy.offset`, which IS `buf + offset`.
def alloc.offset(+buf: U32) -> U32: buf

def alloc.offset_n() -> U32: 0

# :53 `_unmap` -- `self.dev.iface.dev_impl.unregister_mem(storage.meta)`. `.meta`,
# not `.buf`, and for a registered buffer they are the same number -- which is the
# point of :51 and the reason the unmap cannot be written from `.buf` without
# silently working.
def alloc.unmap(+key: U32, t: Tr) -> Tr: Tr.emit(CALL_UNREGISTER(), key, t)

# ===========================================================================
# ops_rdma.py:76-87 -- `rdma_qp`, and it is FOUR claims.
#
#   :79  `nics = [unwrap(rdma_nic_for(Device[d], Device[min(pair)])) for d in pair]`
#        -- the ANCHOR IS `Device[min(pair)]` for BOTH nics, so the pair is
#        SORTED (:106) and the anchor is the smaller name. Two nics, one anchor.
#   :82  the four rings, in the order ("sq", "rq", "scq", "rcq")
#   :83  `bufs |= {sq_seq, rq_seq, psn} | {"db": nic.iface.doorbell}`
#        -- three uint64 counters of ONE element each, then the doorbell, which
#        is the CACHED property so it is mapped ONCE for all eight.
#   :85  `nic.pm_bufferize = PatternMatcher(rules) + nic.pm_bufferize`
#        -- PREPENDED, so the RDMA rules run BEFORE the device's own. That is a
#        first-wins ORDER and `device.bend`'s `pmb_*` rows are its siblings.
#   :86  `for a, b in (nics, nics[::-1]): qps[a.device].connect(...)`
#        -- connect in BOTH directions, and `nics[::-1]` is the second one, so
#        the order is a-then-b and b-then-a.
# ===========================================================================
def ANCHOR_MIN() -> U32: 1

def qp.anchor(+lo: String, +hi: String) -> String: Bool.pick(String, String.is_lt(lo, hi), lo, hi)

# :85 -- the RDMA rules come FIRST. `qpm` is the total rule count AFTER the
# prepend and `device.bend`'s `pmb_len` is the three it contributes; the two
# together are the rule table, and `rdma_pmb_first` is the ordering claim.
def pmb_len() -> U32: 3

def qpm_len() -> U32: U32.add(qp_len(), pmb_len())

def qp.rules_len() -> U32: qp_len()

# :86 -- TWO connects for a two-nic pair, and `nics[::-1]` is the second. A one-
# element pair would connect to itself, which `rdma_qp` never builds because
# `pair` comes from `min(gpu, tag), max(gpu, tag)` at :106 and a name is not less
# than itself.
def qp_connects(nics: U32) -> U32: nics

def qp.connect(+recv: Bool, t: Tr) -> Tr: Tr.emit(CALL_QP_CONNECT(), Bool.to_u32(recv), t)

def qp.new(t: Tr) -> Tr: Tr.emit(CALL_QP_NEW(), OBJ_NONE(), t)

# ===========================================================================
# ops_rdma.py:98-106 -- `rdma_wire`, `is_rdma` and `queue_of`. The wire is the
# UOp on an RDMA device that `rdma_copies` replaces; finding it is what decides
# whether a call is rewritten at all.
#
# :99  `if call.op is not Ops.CALL or call.src[0].op is not Ops.STORE: return None`
#      -- TWO op tests, and both are needed: a non-CALL is not a queue op and a
#      CALL whose first src is not a STORE is not a doorbell.
# :100 `next((b for b in get_call_arg_uops(call) if to_tuple(b.device)[0].
#       startswith("RDMA")), None)` -- the FIRST arg uop on an RDMA device.
# :105 `gpu = to_tuple((dst if wire is src else src).device)[0]` -- the GPU is
#       whichever of dst/src is NOT the wire. An IDENTITY test, `wire is src`.
# :106 `return (min(gpu, wire.tag), max(gpu, wire.tag)), wire is src`
#       -- the pair is SORTED and the flag is `wire is src`. So a RECEIVE has the
#       wire as its SOURCE.
#
# REPORTED, NOT FIXED: the wire tag is `None` on a bufferized PARAM (`UOp.tag` is
# `None` by default, ops.py:244, and `UOp.from_buffer` does not set it, ops.py:862),
# so on a graph that reached `lower_call` with the wire already bufferized,
# `min(gpu, None)` raises `TypeError`. I could not exercise it -- there is no RDMA
# hardware here -- so this port keeps the SORT as the source writes it and says
# so. `wire_tag_sorted` is the row that pins the sort with the tag spelled as a
# string, which is the case the source unambiguously supports.
# ===========================================================================
def wire.is_call(+is_call: Bool) -> Bool: is_call

def wire.is_store(+is_store: Bool) -> Bool: is_store

def wire.of(+is_call: Bool, +is_store: Bool, n_rdma_args: U32) -> U32:
  Bool.pick(U32, Bool.and(is_call, is_store), n_rdma_args, NO_KEY())

def wire.is_rdma(+is_call: Bool, +is_store: Bool, n_rdma_args: U32) -> Bool:
  Bool.not(U32.is_zero(wire.of(is_call, is_store, n_rdma_args)))

# :105-106 -- the wire is the SOURCE of a receive and the DESTINATION of a send.
def queue.is_recv(+wire_is_src: Bool) -> Bool: wire_is_src

# :106 -- the sorted pair. `lo` and `hi` are the two names, and the answer is
# which is which: `queue.lo` is the SMALLER.
def queue.lo(+a: String, +b: String) -> String: Bool.pick(String, String.is_lt(a, b), a, b)

def queue.hi(+a: String, +b: String) -> String: Bool.pick(String, String.is_lt(a, b), b, a)

# ===========================================================================
# ops_rdma.py:108-109 -- `ins`, and the one fact about it that changes every
# constant: `UOp.const(s, dtypes.u32) if isinstance(s, int) else s`. EVERY
# integer that reaches the instruction stream is a uint32. The doorbell values are
# not, which is WALL 5 and `rdma_db_hi_dropped`.
# ===========================================================================
def ins_const_bits() -> U32: 32

# ===========================================================================
# ops_rdma.py:117-118 -- THE CHUNKING, and it is the only place a size becomes a
# COUNT OF WORK.
#
#   chunks = [ceildiv(min(RDMA_CHUNK, b.nbytes() - o), MTU)
#             for b in bufs for o in range(0, b.nbytes(), RDMA_CHUNK)]
#   wqes, packets = len(chunks), sum(chunks)
#
# `RDMA_CHUNK` is 1 GiB because a work queue element's length field is 32 bits
# (:16), and `MTU` is one page, so `chunks[i]` is "how many MTU-sized packets
# this work queue element carries". THREE consequences the gate pins:
#   * a ZERO-byte buffer contributes NO chunk at all -- `range(0, 0, CHUNK)` is
#     empty -- so `wqes` is 0 and there is nothing to post. That is the
#     `rdma_chunks_zero` row and it is the cheapest negative case in the file.
#   * a buffer bigger than `RDMA_CHUNK` contributes ONE CHUNK PER `RDMA_CHUNK`
#     of it, so `wqes` grows with the buffer and `rdma_chunks_big` is the row.
#   * `packets` is the SUM and it is not `wqes`: a 12289-byte buffer is ONE work
#     queue element carrying THREE packets. `rdma_packets_not_wqes` is that.
# ===========================================================================
def chunk_size(+nbytes: U32, +off: U32) -> U32:
  U32.min(RDMA_CHUNK(), U32.sub(nbytes, off))

def chunk_packets(+nbytes: U32, +off: U32) -> U32:
  H.ceildiv_u32(chunk_size(nbytes, off), MTU())

# one chunk per `RDMA_CHUNK` of the buffer. The fold CONSES, so the list comes out
# in DESCENDING offset order -- which is the order the Python comprehension walks
# in ASCENDING order, and `rdma_chunks_order` is the row that says which one this
# port has. It does not matter to the arithmetic (`wqes` and `sum` are
# order-independent) and it matters a great deal to the instruction stream, which
# walks the list in order -- so the instruction stream asks for the offsets by
# INDEX and not by walking this list.
def chunks.go(n: Nat, +nbytes: U32, +off: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      Bool.pick(List<&2, U32>, U32.is_lt(off, nbytes), chunks.go(m, nbytes, U32.add(off, RDMA_CHUNK()), List.append(&2, U32, acc, [chunk_packets(nbytes, off)])), acc)

def nchunks(+nbytes: U32) -> U32:
  Bool.pick(U32, U32.is_zero(nbytes), 0, U32.add(U32.div(U32.sub(nbytes, 1), RDMA_CHUNK()), 1))

def chunks_of(+nbytes: U32) -> List<&2, U32>:
  chunks.go(U32.to_nat(nchunks(nbytes)), nbytes, 0, Nil{})

def sum_u32(n: Nat, +xs: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case h <> t: sum_u32(m, t, U32.add(acc, h))

# the totals over a LIST OF BUFFER SIZES, i.e. :117-118 with the `for b in bufs`.
def packets.put(+x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [x])

# the per-buffer chunk lists, concatenated in buffer order and NOT reversed, so
# `packets` walks the chunks in the order `rdma_copies` will.
def packets.go(n: Nat, +nbs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match nbs:
        case Nil{}: acc
        case b <> r: packets.go(m, r, List.append(&2, U32, acc, chunks_of(b)))

def packets_all(+nbs: List<&2, U32>) -> List<&2, U32>:
  packets.go(List.length(&2, U32, nbs), nbs, Nil{})

def wqes.go(n: Nat, +nbs: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match nbs:
        case Nil{}: acc
        case b <> r: wqes.go(m, r, U32.add(acc, nchunks(b)))

# `wqes = len(chunks)` and `packets = sum(chunks)` -- and they are NOT the same
# number, which is the whole of :118.
def wqes(+nbs: List<&2, U32>) -> U32: wqes.go(List.length(&2, U32, nbs), nbs, 0)

def packets_of(+nbs: List<&2, U32>) -> U32:
  sum_u32(List.length(&2, U32, packets_all(nbs)), packets_all(nbs), 0)

# :123 `bumps` and :125 `psns`.
#
#   bumps = [seq.index(0).store(seq.index(0).load() + wqes)] +
#           ([] if is_recv else [psn.index(0).store(psn.index(0).load() + packets)])
#   psns  = UOp(Ops.BINARY, arg=struct.pack(f"<{wqes+1}I",
#              *itertools.accumulate(chunks, initial=0))).bitcast(uint32)
#
# THE SEND/RECEIVE ASYMMETRY: a RECEIVE bumps the sequence counter by `wqes` and
# NOT the packet-send-number, because a receive consumes no psns -- the psns are
# the sender's. A send bumps BOTH. `bump.psn` answers 0 for a receive and that 0
# is a claim: `rdma_recv_no_psn_bump` is the row, and a `bump.psn` that added
# `packets` unconditionally would move it.
#
# `psns` has `wqes + 1` ENTRIES, not `wqes`: `itertools.accumulate(chunks,
# initial=0)` starts at zero, so `psns[0] = 0`, `psns[i+1] - psns[i] == chunks[i]`,
# and `psns[wqes]` is the total. The `+ 1` is what makes `psns[i + 1]` at
# `i == wqes - 1` in bounds at :145, and `rdma_psns_len` is the row.
def bump.seq(+wqes: U32) -> U32: wqes

def bump.psn(+recv: Bool, packets: U32) -> U32:
  Bool.pick(U32, recv, 0, packets)

# the prefix sums, `initial=0` and all. `psns_at(ps, i)` answers the i-th one.
# `acc` is the running SUM of the chunks consumed so far, and every element
# appended is that sum BEFORE the current chunk -- so the first element is the
# `initial=0` of :125 and the last, appended at `case 0n:`, is the total.
def psns.go(n: Nat, +chunks: List<&2, U32>, +acc: U32, out: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.append(&2, U32, out, [acc])
    case 1n+m:
      match chunks:
        case Nil{}: List.append(&2, U32, out, [acc])
        case c <> r: psns.go(m, r, U32.add(acc, c), List.append(&2, U32, out, [acc]))

def psns_of(+chunks: List<&2, U32>) -> List<&2, U32>:
  psns.go(List.length(&2, U32, chunks), chunks, 0, Nil{})

def psns_len(+wqes: U32) -> U32: U32.add(wqes, 1)

def psns_at(+ps: List<&2, U32>, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ps, U32.to_nat(i)), 0)

# :126 `n = seq_after - wqes + i` and `p = psn_after - packets + psns[i]`. The
# counter is bumped FIRST (:123) and read back, so `n` is the ABSOLUTE index in
# the ring and `i` is the index within this batch -- the two differ by however
# much the counter already was, which is what makes the ring modulo necessary at
# all. `ops.n_of` / `ops.p_of` are that subtraction.
def ops.n_of(seq_after: U32, +wqes: U32, i: U32) -> U32: U32.add(U32.sub(seq_after, wqes), i)

def ops.p_of(psn_after: U32, +packets: U32, +ps: List<&2, U32>, i: U32) -> U32:
  U32.add(U32.sub(psn_after, packets), psns_at(ps, i))

# ===========================================================================
# bnxtdev.py:13-15 -- `db_value`, and the sharpest measurement in this file.
#
#   def db_value(xid, typ, index, epoch):
#     return (xid & bnxt.DBC_DBC_XID_MASK | bnxt.DBC_DBC_PATH_ROCE | typ |
#             bnxt.BNXT_QPLIB_DBR_VALID) << 32 |
#            index & bnxt.DBC_DBC_INDEX_MASK | epoch << bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT
#
# TWO 32-BIT HALVES, and they are not symmetrical:
#   HIGH: which QUEUE this doorbell is for -- the xid (queue pair number or
#         completion queue id) together with the path and the VALID bit.
#   LOW:  WHERE in that queue -- the index and the EPOCH.
#
# `ops_rdma.py:130-131` calls `db_value(qp.qpn, RQ|SQ, 0, 0)` and
# `db_value(qp.rcq_id|qp.scq_id, CQ, 0, 0)`. BOTH PASS index 0 AND epoch 0, so
# THE LOW HALF IS ZERO in both, and :148/:152 OR that zero into
# `((n+1) % RING_ENTRIES | ((n+1) // RING_ENTRIES & 1) << 24)`. Then :109 casts
# every integer to `UOp.const(s, dtypes.u32)`, which TRUNCATES the 64-bit
# result to its low 32 bits -- and so the high half, the only part that says which
# queue the doorbell is for, IS NEVER TRANSMITTED.
#
# MEASURED. `db_value(5, DBC_DBC_TYPE_SQ, 0, 0)` is 288230397626548224, whose
# low 32 bits are 0. `rdma_db_hi_dropped` and `rdma_db_hi_5` are the two rows, and
# `rdma_db_lo_zero` is the row that says the OR is a NO-OP on the value that is
# actually written. REPORTED, NOT FIXED: whether the NIC recovers the xid from
# the doorbell register's high word (it does not -- it is the same 64-bit doorbell
# register the host writes) or whether the generated code drops it, is a question
# for the owner of ops_rdma.py. This port is faithful either way, which is what
# makes the discrepancy visible instead of argued about.
# ===========================================================================
def db_value.hi(+xid: U32, typ: U32) -> U32:
  U32.or(U32.or(U32.and(xid, DBC_DBC_XID_MASK()), U32.or(DBC_DBC_PATH_ROCE(), typ)), BNXT_QPLIB_DBR_VALID())

def db_value.lo(+index: U32, +epoch: U32) -> U32:
  U32.or(U32.and(index, DB_INDEX_MASK()), U32.shln(epoch, 24n))

# the doorbell VALUE the instruction stream actually carries, after :109's
# uint32 cast: the low half of `db_value` with the slot and the epoch OR'd in.
def db_value.of(+xid: U32, typ: U32, slot: U32, epoch: U32) -> U32:
  U32.or(U32.or(slot, U32.shln(epoch, 24n)), db_value.lo(0, 0))

# :130 the RING doorbell's constant half and :131 the COMPLETION QUEUE's. The
# queue pair number for the ring and the completion queue id for the cq, and the
# receive queue acks the RCQ while the send queue acks the SCQ.
def ring_db_type(+recv: Bool) -> U32:
  Bool.pick(U32, recv, DBC_DBC_TYPE_RQ(), DBC_DBC_TYPE_SQ())

def cq_db_type() -> U32: DBC_DBC_TYPE_CQ()

def cq_id(+recv: Bool, scq_id: U32, rcq_id: U32) -> U32:
  Bool.pick(U32, recv, rcq_id, scq_id)

# ===========================================================================
# :148,:152 -- THE DOORBELL RULE, and it is four arithmetic facts:
#
#   ((n + 1) % RING_ENTRIES | ((n + 1) // RING_ENTRIES & 1) << SHIFT) | ring_db
#
#   * the slot is `n + 1`, the slot AFTER the work queue element just written --
#     and :151 polls slot `n`. One step apart, and the two together are the ring
#     protocol.
#   * the epoch is `(n + 1) // RING_ENTRIES & 1`, a SINGLE BIT counting how many
#     times the index has wrapped the ring. `& 1` is what makes it one bit; the
#     gate's `rdma_epoch_*` fixture runs n across a wrap so a version that
#     dropped the `& 1` would print 2 instead of 0.
#   * the CQ doorbell is the SAME rule with `CQ_ENTRIES` -- and since
#     `RING_ENTRIES == CQ_ENTRIES == 4096` the two agree, which is a fact about
#     these numbers and not about the code. `rdma_eq_ring_cq` says so.
# ===========================================================================
def db_slot(+n: U32) -> U32: U32.mod(U32.add(n, 1), RING_ENTRIES())

def db_epoch(+n: U32) -> U32: U32.and(U32.div(U32.add(n, 1), RING_ENTRIES()), 1)

def cq_db_slot(+n: U32) -> U32: U32.mod(U32.add(n, 1), CQ_ENTRIES())

def cq_db_epoch(+n: U32) -> U32: U32.and(U32.div(U32.add(n, 1), CQ_ENTRIES()), 1)

def RING_EQ_CQ() -> Bool: U32.is_eq(RING_ENTRIES(), CQ_ENTRIES())

# ===========================================================================
# :151 -- `wait_eq`, and THE INVERTED EPOCH.
#
#   ins("wait_eq", cq_addr + (n % CQ_ENTRIES) * 32 + 24,
#                (n // CQ_ENTRIES & 1 ^ 1 | (2 if is_recv else 0)).cast(uint16))
#
# Python's precedence is `&` then `^` then `|`, so the value is
# `(((n // CQ_ENTRIES) & 1) ^ 1) | (2 if is_recv else 0)` and there are THREE
# facts in it:
#   * the slot is `n`, not `n + 1` -- the doorbell rang the NEXT slot, the wait
#     polls THIS one. `rdma_wait_slot_is_n`.
#   * the epoch is the doorbell's epoch INVERTED. The doorbell says "I have
#     passed slot k of pass p"; the wait says "I am waiting for slot n of pass
#     NOT p", because the NIC flips a TOGGLE in the completion entry when the
#     slot is consumed. Dropping the `^ 1` compiles and hangs -- nothing ever
#     matches -- and `rdma_epoch_inverted` is the row.
#   * the top bit is `2` for a receive and `0` for a send, so a receive and a send
#     on the same completion queue can never be confused. `rdma_wait_recv_bit`.
def cq_slot_of(+n: U32) -> U32: U32.mod(n, CQ_ENTRIES())

def cq_epoch_of(+n: U32) -> U32: U32.xor(U32.and(U32.div(n, CQ_ENTRIES()), 1), 1)

def wait_expected(+n: U32, +recv: Bool) -> U32:
  U32.or(cq_epoch_of(n), Bool.pick(U32, recv, 2, 0))

# :151 the address: `cq_addr + (n % CQ_ENTRIES) * 32 + 24`. The completion entry is
# 32 bytes (:93) and the wait reads its FOURTH 32-bit word -- `cqe_ready` at
# bnxtdev.py:25 reads `cqe[24]`, so the offset is 24 and not 0, and that is the
# difference between polling the entry and polling its status word.
def cq_wait_addr(+cq_addr: U32, n: U32) -> U32:
  U32.add(U32.add(cq_addr, U32.mul(cq_slot_of(n), 32)), 24)

def CQE_STATUS_AT() -> U32: 24
def CQE_SIZE() -> U32: 32

# ===========================================================================
# :144-145 -- THE MSN ENTRY, and the 64-bit word is three 24-bit fields.
#
#   ins("write", ring_addr + RING_ENTRIES * WQE_SIZE + (n % RING_ENTRIES) * 8,
#       ((n % RING_ENTRIES) << 48) |
#       (((p + psns[i + 1] - psns[i]) & 0xffffff) << 24) | (p & 0xffffff))
#
# THREE facts and each one is load-bearing:
#   * it lives at `ring_addr + RING_ENTRIES * WQE_SIZE`, i.e. PAST the whole ring,
#     which is why the send ring is `RING_ENTRIES * (WQE_SIZE + 8)` at :92 and not
#     `RING_ENTRIES * WQE_SIZE`. Dropping the `+ 8` under-allocates the send ring
#     and the msn table then overlaps the last work queue element.
#   * `psns[i + 1] - psns[i]` is `chunks[i]` -- the number of PACKETS in this work
#     queue element -- so there is ONE PSN PER PACKET and not one per element.
#   * all three fields are 24 bits. The slot is at bit 48, the next psn at bit 24
#     and this psn at bit 0. So the word is TWO exact U32 halves and nothing is
#     lost: `msn.hi` is `slot << 16` plus the top sixteen bits of the next psn,
#     and `msn.lo` is the low eight bits of the next psn at bit 24 plus this psn.
# `rdma_msn_hi1`/`rdma_msn_lo1` are the halves of the fixture's second element and
# `rdma_msn_whole` is the two of them side by side.
# ===========================================================================
def msn_base(+ring_addr: U32) -> U32: U32.add(ring_addr, U32.mul(RING_ENTRIES(), WQE_SIZE()))

def msn_addr(+ring_addr: U32, n: U32) -> U32:
  U32.add(msn_base(ring_addr), U32.mul(U32.mod(n, RING_ENTRIES()), 8))

def MSN_FIELD() -> U32: 8
def MSN_SLOT_HI_AT_NAT() -> Nat: 16n
def MSN_PSN_AT_NAT() -> Nat: 24n



def msn_next_psn(+p: U32, +packets: U32) -> U32: U32.and(U32.add(p, packets), PSN_MASK())

def msn.hi(+slot: U32, +next_psn: U32) -> U32:
  U32.or(U32.shln(U32.and(slot, PSN_MASK()), MSN_SLOT_HI_AT_NAT()), U32.shrn(U32.and(next_psn, PSN_MASK()), 8n))

def msn.lo(+next_psn: U32, +p: U32) -> U32:
  U32.or(U32.shln(U32.and(next_psn, PSN_MASK()), MSN_PSN_AT_NAT()), U32.and(p, PSN_MASK()))

# ===========================================================================
# :140-141 -- THE WORK QUEUE ELEMENT, and the ADDRESS TRANSLATION appears here.
#
#   hdr, key = struct.unpack("<8I", (recv_wqe if is_recv else send_wqe)(0, 0, size)[:32]), \
#             unwrap_view(buf)[0].getaddr(nic.device)
#   ops += [ins("write", ring_addr + (n % RING_ENTRIES) * WQE_SIZE,
#               *hdr, buf.getaddr(devs) + off, key.cast(uint32), size)]
#
# The element carries TWELVE u32 words: the EIGHT header words, then the GPU's own
# address plus the chunk offset, then the NIC's KEY for the same memory, then the
# size. BOTH addresses are there -- :46's branch and :50's registration are what
# make the second one mean anything -- and a work queue element whose key is 0 is
# a transfer to nowhere that the NIC will happily accept. So `ins.write` REFUSES
# when the key is missing: that is THE NEGATIVE CASE of this file, and it is not a
# guard Python writes down.
#
# The HEADER: `send_wqe(0, 0, size)` packs `"<BBB5xI20xQII"` and `recv_wqe` packs
# `"<BBB29xQII"`. Word 0 is `type << 16 | flags << 8 | kind`, and the size lands at
# byte 8 -- INSIDE the 32-byte header for a send (a 5-byte pad then `I size`) and
# INSIDE the 29-byte pad for a receive. So the send header's word 2 is the size and
# the receive header's word 2 is ZERO however big the transfer is. And the size
# appears TWICE in a send element, once in the header and once as the last word.
# `rdma_hdr_send` and `rdma_hdr_recv` are the two eight-word lists.
# ===========================================================================
def ring_slot(+n: U32) -> U32: U32.mul(U32.mod(n, RING_ENTRIES()), WQE_SIZE())

def ring_addr_of(+ring: U32, n: U32) -> U32: U32.add(ring, ring_slot(n))

def hdr0(+recv: Bool) -> U32:
  Bool.pick(U32, recv, U32.add(U32.shln(WQE_KIND(), 16n), RECV_KIND()),
            U32.or(U32.shln(WQE_KIND(), 16n), U32.shln(SQ_SEND_FLAGS_SIGNAL_COMP(), 8n)))

def hdr2(+recv: Bool, size: U32) -> U32:
  Bool.pick(U32, recv, 0, size)

def hdr.of(+recv: Bool, size: U32) -> List<&2, U32>:
  List.append(&2, U32, [hdr0(recv), 0, hdr2(recv, size)], [0, 0, 0, 0, 0])

def hdr_len() -> U32: HDR_WORDS()

# the TWELVE words of one element: `*hdr, buf.getaddr(devs) + off, key, size`.
def wqe.words(+recv: Bool, +size: U32, gpu: U32, off: U32, key: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, List.append(&2, U32, hdr.of(recv, size),
    [U32.add(gpu, off)]), [key]), [size])

def wqe_len(+recv: Bool) -> U32:
  Bool.pick(U32, recv, U32.add(hdr_len(), 3), U32.add(hdr_len(), 3))

# THE TRANSLATION. :140 asks the DEVICE for the NIC-side address; the device's
# answer is the key `_map` was given, so `key_of(gpu_addr)` is the same number by
# the other route. `ins.write` reads it out of `Pdt` and `map.key_guard` refuses
# when it is missing.
def ins.write(+ring: U32, n: U32, t: Tr) -> Tr:
  Tr.emit(CALL_INS_WRITE(), ring_addr_of(ring, n), t)

# :144-145, and ONLY on a send. `recv` false.
def ins.msn(+ring: U32, n: U32, t: Tr) -> Tr:
  Tr.emit(CALL_INS_WRITE(), msn_addr(ring, n), t)

# :148 the RING doorbell and :152 the COMPLETION QUEUE's -- the same rule with a
# different constant, both writing to the SAME address (`db`), which is why
# `rdma_two_doorbells_one_addr` is a row.
def ins.ring_db(+db: U32, n: U32, t: Tr) -> Tr: Tr.emit(CALL_INS_WRITE(), db, t)

def ins.cq_db(+db: U32, n: U32, t: Tr) -> Tr: Tr.emit(CALL_INS_WRITE(), db, t)

def ins.wait(+cq: U32, n: U32, t: Tr) -> Tr: Tr.emit(CALL_INS_WAIT(), cq_wait_addr(cq, n), t)

# :155 the receive-only cache invalidate, the LAST instruction of a receive copy.
def ins.barrier(t: Tr) -> Tr: Tr.emit(CALL_INS_BARRIER(), OBJ_NONE(), t)

# ===========================================================================
# :136-155 -- ONE WORK QUEUE ELEMENT, as the five instructions Python writes in
# its body, in their order. The order IS the protocol:
#
#   ins("write", ring + slot*WQE_SIZE, *hdr, gpu+off, key, size)   # :141
#   if not is_recv: ins("write", ring + RING_ENTRIES*WQE_SIZE + slot*8, msn)  # :144
#   ins("write", db, ((n+1)%RING | epoch<<24) | ring_db)             # :148
#   ins("wait_eq", cq + slot*32 + 24, epoch^1 | recv_bit)            # :151
#   ins("write", db, ((n+1)%CQ   | epoch<<24) | cq_db)               # :152
#
# Write the element, ring the bell, wait for the completion, ACK the completion.
# Two doorbells and ONE wait, and the msn is the only one of the five that a
# receive does not do -- so a receive is FOUR instructions and a send is FIVE.
# `rdma_send_n` and `rdma_recv_n` are those two counts and they are different on
# purpose.
# ===========================================================================
def ops.msn_at(+recv: Bool, n: U32) -> Bool: Bool.not(recv)

# the msn write is the ONE of the five that a receive does not do, so it is its
# own def and the guard is on the WAY IN rather than on the result.
def ops.msn_write(+recv: Bool, ring: U32, +n: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, recv, t, ins.msn(ring, n, t))

# the five instructions, nested innermost-first so the trace reads in the order
# Python writes them.
def ops.wqe_at(recv: Bool, +ring: U32, cq: U32, +db: U32, +n: U32, t: Tr) -> Tr:
  ins.cq_db(db, n, ins.wait(cq, n, ins.ring_db(db, n, ops.msn_write(recv, ring, n, ins.write(ring, n, t)))))

def ops.wqe(recv: Bool, +ring: U32, cq: U32, +db: U32, +n: U32, t: Tr) -> Tr:
  ops.wqe_at(recv, ring, cq, db, n, t)

# :136-137 `for off in range(0, buf.nbytes(), RDMA_CHUNK)` and
# `size = min(RDMA_CHUNK, buf.nbytes() - off)`. The chunk's SIZE, which is what
# goes in the header and what the psn advance is measured against.
def ops.chunk_size(+nbytes: U32, +off: U32) -> U32: chunk_size(nbytes, off)

# :155 `copies.append(ops + ([ins("barrier")] if is_recv else []))` -- the
# invalidate-the-GPU-caches instruction, and it is the LAST thing a receive does.
# A send does not, because a send's data was written by the GPU and is coherent.
def ops.barrier_at(+recv: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, recv, ins.barrier(t), t)

# BOTH COPIES ARE FIVE INSTRUCTIONS, and that is the finding: a send spends its
# fifth instruction on the msn entry and a receive spends its fifth on the
# barrier. So `ops.n_ins` is 5 either way and a COUNT cannot tell the two apart
# -- only the ADDRESSES can, and `rdma_send_first` / `rdma_recv_first` are the
# rows that do. The first draft of this file claimed four against five and the
# gate caught its own expectation; see the mutation table.
def ops.n_ins(recv: Bool) -> U32: 5

# and the WRITE counts differ even though the instruction counts do not: three
# writes for a receive (ring, doorbell, cq doorbell) against four for a send
# (ring, msn, doorbell, cq doorbell).
def ops.n_writes(recv: Bool) -> U32: Bool.pick(U32, recv, 3, 4)

# ===========================================================================
# :120 -- THE RING-CAP ASSERT, and it is the refusal the brief asked for.
#
#   assert wqes <= min(RING_ENTRIES, CQ_ENTRIES),
#          "a batch posts at most a ring of wqes per pair"
#
# A batch that posts more work queue elements than a ring holds would overwrite
# entries the NIC has not consumed, and nothing downstream would notice -- the
# NIC would simply transfer the wrong data. So it is a REFUSAL and not a clamp,
# and the whole batch produces NO instructions at all: `copies.guard` returns a
# trace truncated at the refusal, which is what `rdma_cap_refuse_n` reads.
# `min(RING_ENTRIES, CQ_ENTRIES)` is 4096 and BOTH are, so the cap is the ring
# size -- `rdma_eq_ring_cq` says so rather than letting a reader assume which of
# the two bounds it.
# ===========================================================================
def RING_CAP() -> U32: U32.min(RING_ENTRIES(), CQ_ENTRIES())

def copies.cap_ok(+wqes: U32) -> Bool: U32.is_le(wqes, RING_CAP())

def copies.guard.at(ok: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, ok, t, Tr.refuse(REFUSE_RING_CAP(), t))

def copies.guard(ok: Bool, t: Tr) -> Tr: copies.guard.at(ok, t)

def REFUSE_CAP_MSG() -> String: REFUSE_RING_CAP_MSG()

# ===========================================================================
# :161-168 -- `rdma_submit` and `pm_rdma_encode`, the encode REWRITE.
#
#   if not (queues := {i: queue_of(u) for i, u in enumerate(lin.src)
#                      if is_rdma(u)}): return None
#   ops = [[u] for u in lin.src]
#   for q in dict.fromkeys(queues.values()):
#     positions = [i for i in queues if queues[i] == q]
#     for i, copy_ops in zip(positions, rdma_copies(lin.arg[0],
#                             [lin.src[i] for i in positions])): ops[i] = copy_ops
#   return submit.replace(src=(lin.replace(src=tuple(flatten(ops))),))
#
# THREE claims and the third is the negative case:
#   1. THE RULE TABLE HAS ONE RULE -- `pm_rdma_encode` at :169 -- and it matches a
#      CUSTOM_FUNCTION whose single src is a LINEAR named "lin". `encode_len = 1`.
#   2. `dict.fromkeys(queues.values())` DEDUPS THE QUEUES while preserving the
#      order they first appeared in, so the queues are processed in the order the
#      RDMA srcs occur in the linear -- NOT sorted, and NOT in the order
#      `rdma_qp` built them. Two srcs on the same queue are handled by ONE
#      `rdma_copies` call over both buffers, which is why `packets` is a sum over
#      a LIST of buffers and not a per-src number.
#   3. `ops = [[u] for u in lin.src]` -- A NON-RDMA SRC KEEPS ITSELF. The list is
#      initialised with every src and only the RDMA indices are overwritten, so a
#      src with no wire is NOT replaced by ring writes and doorbell writes. THAT
#      IS THE NEGATIVE CASE, and it is a data claim rather than a trace one:
#      `submit.src_replaced` is the number of srcs whose ops are NOT a singleton,
#      and `rdma_submit_keeps_nonrdma` is the row.
# ===========================================================================
def encode_len() -> U32: 1

# the rewrite's GUARD: an empty queue dict is Python's `return None`, which is
# "this rule does not fire" -- NOT a refusal. A different observable from
# `Tr.refused`, and `rdma_submit_none_is_not_refused` is the row.
def submit.fires(+n_queues: U32) -> Bool: Bool.not(U32.is_zero(n_queues))

# :164 -- every src starts as a one-element list holding ITSELF.
def submit.src_replaced(+n_srcs: U32, n_queues: U32) -> U32: n_queues

def submit.srcs_kept(+n_srcs: U32, n_queues: U32) -> U32: U32.sub(n_srcs, submit.src_replaced(n_srcs, n_queues))

# :166 `positions = [i for i in queues if queues[i] == q]` -- the indices of THIS
# queue, and because the dict at :162 was built by `enumerate` they are ASCENDING.
# A queue whose srcs are at 0 and 3 has positions [0, 3] and gets ONE
# `rdma_copies` over both, so its work queue elements are numbered 0 and 1 while
# its src indices are 0 and 3. `submit.pos_at` answers 3 at k=1 and 0 elsewhere.
def submit.pos_at(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 1), 3, 0)

# ===========================================================================
# THE GATE. Every row is a claim about ops_rdma.py's TEXT, about the bnxt
# constants read out of `autogen/bnxt.py`, or about a number MEASURED by
# `.agents/slop/oracle_rdma.py`, which re-derives every one of them from CPython.
# `1`/`0` are booleans and other values are counts, indices, sizes and strings.
#
# THE FIXTURES, and each is the shape of a real transfer:
#   SEND  bufs [0x2001, 0x1000], qpn 5, scq 9, rcq 11, ring 0x1000, cq 0x2000,
#         db page 0x3000, db_off 0x12345, gpu 0x7000, key 0x9000, seq 0, psn 0.
#         chunks [3, 1], wqes 2, packets 4, psns [0, 3, 4].
#   RECV  bufs [0x1000], qpn 5, rcq 11, everything else the same.
#         chunks [1], wqes 1, packets 1, psns [0, 1].
#   EPOCH n = 4095, 4096, 4097, 8191, 8192 -- one and a half ring wraps, which is
#         the ONLY fixture that can see the epoch bit and the `& 1` on it.
# ===========================================================================
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

# --- the fixtures -----------------------------------------------------------
def FX_SEND_NBS() -> List<&2, U32>: [8193, 4096]
def FX_RECV_NBS() -> List<&2, U32>: [4096]
def FX_RING() -> U32: 4096
def FX_CQ() -> U32: 8192
def FX_DB_PAGE() -> U32: 12288
def FX_DB_OFF() -> U32: 74565
def FX_GPU() -> U32: 28672
def FX_KEY() -> U32: 36864
def FX_QPN() -> U32: 5
def FX_SCQ() -> U32: 9
def FX_RCQ() -> U32: 11
# the counter AFTER the bump at :123, not before. Reading it as `FX_WQES` is what
# `seq.after(*bumps).load()` at :126 does, and it is why `n` and `p` come out as
# the per-batch index. Reading the PRE-bump value would underflow a U32, which is
# what the first draft of this fixture did.
def FX_SEQ_AFTER() -> U32: 2
def FX_PSN_AFTER() -> U32: 4
def FX_DBA() -> U32: 13125

def FX_DB() -> U32: db.addr(FX_DB_PAGE(), FX_DB_OFF())

def FX_PDT() -> Pdt: Pdt.put2(FX_GPU(), FX_KEY(), Pdt.of())

# --- 1: the CONSTANTS, :16-18 and the bnxt enums ---------------------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_chunk", RDMA_CHUNK())
    urow("rdma_page", PAGE())
    urow("rdma_wqe_size", WQE_SIZE())
    urow("rdma_ring_entries", RING_ENTRIES())
    urow("rdma_cq_entries", CQ_ENTRIES())
    urow("rdma_mtu", MTU())
    urow("rdma_psn_mask", PSN_MASK())
    urow("rdma_epoch_shift", DB_EPOCH_SHIFT())
    urow("rdma_db_type_rq", DBC_DBC_TYPE_RQ())
    urow("rdma_db_type_sq", DBC_DBC_TYPE_SQ())
    urow("rdma_db_type_cq", DBC_DBC_TYPE_CQ())
    urow("rdma_xid_mask", DBC_DBC_XID_MASK())
    urow("rdma_dbr_valid", BNXT_QPLIB_DBR_VALID())
    urow("rdma_signal_comp", SQ_SEND_FLAGS_SIGNAL_COMP())
    urow("rdma_vendor", BNXT_VENDOR())
    urow("rdma_mask", BNXT_MASK())
    urow("rdma_device_id", BNXT_DEVICE_ID())
    urow("rdma_base_class", BNXT_BASE_CLASS())
    urow("rdma_vram_bar", VRAM_BAR())
    row("rdma_type_sq_off", U32.is_zero(DBC_DBC_TYPE_SQ()))
    row("rdma_eq_ring_cq", RING_EQ_CQ())
    urow("rdma_cands_len", U32.from_nat(List.length(&2, U32, lp_cands())))
    lrow("rdma_cands", lp_cands())

# --- 2: the SIZES, :89-96 --------------------------------------------------
def t_sizes() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_ring_recv", ring_elems_of(True{}))
    urow("rdma_ring_send", ring_elems_of(False{}))
    urow("rdma_cq", cq_elems())
    urow("rdma_seq_elems", seq_elems())
    urow("rdma_seq_bytes", seq_bytes())
    urow("rdma_psn_bytes", psn_bytes())
    urow("rdma_db_elems", db_elems())
    urow("rdma_send_bigger", U32.sub(ring_elems_of(False{}), ring_elems_of(True{})))
    row("rdma_send_plus_8", U32.is_eq(U32.sub(ring_elems_of(False{}), ring_elems_of(True{})),
                                      U32.mul(RING_ENTRIES(), 8)))
    urow("rdma_bufs_len", qp_len())
    srow("rdma_buf_1", qp_name(1))
    srow("rdma_buf_2", qp_name(2))
    srow("rdma_buf_3", qp_name(3))
    srow("rdma_buf_4", qp_name(4))
    srow("rdma_buf_5", qp_name(5))
    srow("rdma_buf_6", qp_name(6))
    srow("rdma_buf_7", qp_name(7))
    srow("rdma_buf_8", qp_name(8))
    urow("rdma_qpm_len", qpm_len())
    urow("rdma_pmb_len", pmb_len())
    row("rdma_qpm_prepended", U32.is_eq(qpm_len(), U32.add(qp_len(), pmb_len())))

# --- 3: the TAGS, :84 and :90 ----------------------------------------------
def t_tags() -> IO(Unit):
  do IO<Unit>:
    srow("rdma_tag_sq", tag_of("GPU:0", "GPU:1", "sq"))
    srow("rdma_tag_db", tag_of("GPU:0", "GPU:1", "db"))
    srow("rdma_tag_rq_seq", tag_of("GPU:0", "GPU:1", "rq_seq"))
    srow("rdma_tag_amd", tag_of("AMD:0", "GPU:1", "psn"))
    row("rdma_tag_no_colon", Bool.not(String.contains(tag_of("GPU:0", "GPU:1", "sq"), ":")))
    row("rdma_tag_lower", String.eq(tag_of("GPU:0", "GPU:1", "sq"), "rdma_gpu_0_gpu_1_sq"))
    row("rdma_tag_ne", Bool.not(String.eq(tag_of("GPU:0", "GPU:1", "sq"), tag_of("GPU:1", "GPU:0", "sq"))))
    srow("rdma_anchor_01", qp.anchor("GPU:0", "GPU:1"))
    srow("rdma_anchor_10", qp.anchor("GPU:1", "GPU:0"))
    row("rdma_anchor_is_min", String.eq(qp.anchor("GPU:0", "GPU:1"), "GPU:0"))
    urow("rdma_connects", qp_connects(2))

# --- 4: `log_page`, :48 -- THE PAGE TABLE, BOTH DIRECTIONS ----------------
def t_page() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_lp_0", log_page(0))
    urow("rdma_lp_1000", log_page(4096))
    urow("rdma_lp_2000", log_page(8192))
    urow("rdma_lp_4000", log_page(16384))
    urow("rdma_lp_8000", log_page(32768))
    urow("rdma_lp_10000", log_page(65536))
    urow("rdma_lp_40000", log_page(262144))
    urow("rdma_lp_100000", log_page(1048576))
    urow("rdma_lp_400000", log_page(4194304))
    urow("rdma_lp_800000", log_page(8388608))
    urow("rdma_lp_9000", log_page(36864))
    urow("rdma_lp_3000", log_page(12288))
    urow("rdma_lp_40000000", log_page(1073741824))
    urow("rdma_lp_f000", log_page(61440))
    # THE NEGATIVE CASE of the page table: an address with a low bit set matches
    # NOTHING and `max()` of an empty generator is a ValueError. `NO_LOG_PAGE`
    # answers 0 and `map.page_guard` turns that into a refusal.
    urow("rdma_lp_none_1", log_page(1))
    urow("rdma_lp_none_1001", log_page(4097))
    urow("rdma_lp_none_2", log_page(2))
    urow("rdma_lp_none_100", log_page(256))
    row("rdma_lp_none_flagged", Bool.not(has_page(1)))
    row("rdma_lp_hit_1000", has_page(4096))
    # `align` is the OR-reduction of the buffer address and every (p | s).
    urow("rdma_align_2", align_or(28672, [4096, 16384], [4096, 4096]))
    urow("rdma_align_1", align_or(4096, [8192], [4096]))
    urow("rdma_np_1", npages([4096], log_page(4096)))
    urow("rdma_np_2", npages([8192], log_page(4096)))
    urow("rdma_np_2r", npages([4096, 4096], log_page(4096)))
    urow("rdma_np_0", npages([4096], NO_LOG_PAGE()))
    row("rdma_np_zero_page", U32.is_zero(npages([4096], NO_LOG_PAGE())))

# --- 5: the CHUNKING, :117-118 ---------------------------------------------
def t_chunks() -> IO(Unit):
  do IO<Unit>:
    lrow("rdma_chunks_zero", chunks_of(0))
    urow("rdma_chunks_zero_n", nchunks(0))
    lrow("rdma_chunks_1", chunks_of(1))
    lrow("rdma_chunks_1000", chunks_of(4096))
    lrow("rdma_chunks_1001", chunks_of(4097))
    lrow("rdma_chunks_3000", chunks_of(12288))
    lrow("rdma_chunks_2001", chunks_of(8193))
    lrow("rdma_chunks_1g", chunks_of(1073741824))
    lrow("rdma_chunks_1g1p", chunks_of(1073745920))
    lrow("rdma_chunks_1g4p", chunks_of(1073758208))
    lrow("rdma_chunks_2g", chunks_of(2147483648))
    row("rdma_chunks_zero_flagged", U32.is_zero(nchunks(0)))
    urow("rdma_wqes_send", wqes(FX_SEND_NBS()))
    urow("rdma_packets_send", packets_of(FX_SEND_NBS()))
    urow("rdma_wqes_recv", wqes(FX_RECV_NBS()))
    urow("rdma_packets_recv", packets_of(FX_RECV_NBS()))
    row("rdma_packets_not_wqes", Bool.not(U32.is_eq(wqes(FX_SEND_NBS()), packets_of(FX_SEND_NBS()))))
    row("rdma_packets_gt_wqes", U32.is_gt(packets_of(FX_SEND_NBS()), wqes(FX_SEND_NBS())))
    lrow("rdma_psns_send", psns_of(packets_all(FX_SEND_NBS())))
    lrow("rdma_psns_recv", psns_of(packets_all(FX_RECV_NBS())))
    urow("rdma_psns_len_send", psns_len(wqes(FX_SEND_NBS())))
    urow("rdma_psns_len_recv", psns_len(wqes(FX_RECV_NBS())))
    urow("rdma_psns_0", psns_at(psns_of(packets_all(FX_SEND_NBS())), 0))
    urow("rdma_psns_1", psns_at(psns_of(packets_all(FX_SEND_NBS())), 1))
    urow("rdma_psns_2", psns_at(psns_of(packets_all(FX_SEND_NBS())), 2))
    urow("rdma_bump_seq_send", bump.seq(wqes(FX_SEND_NBS())))
    urow("rdma_bump_psn_send", bump.psn(False{}, packets_of(FX_SEND_NBS())))
    urow("rdma_bump_psn_recv", bump.psn(True{}, packets_of(FX_RECV_NBS())))
    urow("rdma_n0", ops.n_of(FX_SEQ_AFTER(), wqes(FX_SEND_NBS()), 0))
    urow("rdma_n1", ops.n_of(FX_SEQ_AFTER(), wqes(FX_SEND_NBS()), 1))
    urow("rdma_p0", ops.p_of(FX_PSN_AFTER(), packets_of(FX_SEND_NBS()), psns_of(packets_all(FX_SEND_NBS())), 0))
    urow("rdma_p1", ops.p_of(FX_PSN_AFTER(), packets_of(FX_SEND_NBS()), psns_of(packets_all(FX_SEND_NBS())), 1))
    # THE COUNTER IS READ AFTER THE BUMP, and the difference is the batch base.
    urow("rdma_n_base4095", ops.n_of(4095, 0, 0))
    urow("rdma_p_base3", ops.p_of(3, 0, psns_of(packets_all(FX_SEND_NBS())), 1))

# --- 6: the DEVICE OPEN, :20-24 and :66-71 ---------------------------------
def t_dev() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, dev.init("RDMA:0", FX_DB_OFF()))
    row("rdma_init_order", seq(t, [Call{CALL_OPEN, BNXT_VENDOR()}, Call{CALL_DEVICE, 0}]))
    row("rdma_init_order_rev", Bool.not(seq(t, [Call{CALL_DEVICE, 0}, Call{CALL_OPEN, BNXT_VENDOR()}])))
    urow("rdma_init_n", Tr.ncalls(t))
    urow("rdma_init_opens", Tr.count(CALL_OPEN(), Tr.calls(t)))
    urow("rdma_init_devices", Tr.count(CALL_DEVICE(), Tr.calls(t)))
    urow("rdma_did_0", Rdma.did(Rdma.of("RDMA:0", 0)))
    urow("rdma_did_3", Rdma.did(Rdma.of("RDMA:3", 3)))
    urow("rdma_did_bad", D.dev_id("RDMA:x"))
    urow("rdma_did_deep", D.dev_id("RDMA:1:2"))
    row("rdma_did_3_is_3", U32.is_eq(Rdma.did(Rdma.of("RDMA:3", 3)), 3))
    row("rdma_did_bad_is_0", U32.is_zero(D.dev_id("RDMA:x")))
    urow("rdma_ifaces", Rdma.ifaces(Rdma.of("RDMA:0", 0)))
    urow("rdma_alloc", Rdma.alloc(Rdma.of("RDMA:0", 0)))
    urow("rdma_runtime", Rdma.runtime(Rdma.of("RDMA:0", 0)))
    urow("rdma_render_passed", RENDERERS_PASSED())
    urow("rdma_render_effective", Rdma.nrender(Rdma.of("RDMA:0", 0)))
    row("rdma_render_not_empty", U32.is_ne(Rdma.nrender(Rdma.of("RDMA:0", 0)), RENDERERS_PASSED()))
    srow("rdma_peer", Rdma.peer(Rdma.of("RDMA:0", 0)))
    row("rdma_peer_is_pci", String.eq(Rdma.peer(Rdma.of("RDMA:0", 0)), PEER_PCI()))
    row("rdma_peer_not_head", Bool.not(String.eq(Rdma.peer(Rdma.of("RDMA:0", 0)), D.head("RDMA:0"))))
    row("rdma_peer_not_devname", Bool.not(String.eq(Rdma.peer(Rdma.of("RDMA:0", 0)), "RDMA:0")))
    row("rdma_peer_same_two_ifaces", String.eq(Rdma.peer(Rdma.of("RDMA:0", 0)),
                                               Rdma.peer(Rdma.of("RDMA:1", 1))))
    urow("rdma_dcls", D.dcls("RDMA"))
    +f : Tr <- IO.pure(Tr, Iface.tr(iface.fini(Iface.of("RDMA:0", 0, FX_DB_OFF()))))
    urow("rdma_fini_n", Tr.ncalls(f))
    row("rdma_fini_only", seq(f, [Call{CALL_FINI, OBJ_NONE()}]))

# --- 7: the ALLOCATION, :39-41 and :26-31 ---------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, alloc.of(12, Tr.of()))
    row("rdma_alloc_order", seq(t, [Call{CALL_ALLOC_SYSMEM, 4096}, Call{CALL_ALLOC_VADDR, 4096}]))
    lrow("rdma_alloc_args", Tr.args(CALL_ALLOC_SYSMEM(), Tr.calls(t)))
    lrow("rdma_alloc_vas", Tr.args(CALL_ALLOC_VADDR(), Tr.calls(t)))
    urow("rdma_alloc_n", Tr.ncalls(t))
    urow("rdma_buf_nb", alloc.buf_size(12))
    urow("rdma_buf_va", alloc.va_size(12))
    urow("rdma_buf_diff", U32.sub(alloc.va_size(12), alloc.buf_size(12)))
    row("rdma_buf_nb_raw", U32.is_eq(alloc.buf_size(12), 12))
    row("rdma_buf_va_paged", U32.is_eq(alloc.va_size(12), PAGE()))
    urow("rdma_alloc_double", alloc.sysmem_size(alloc.sysmem_size(12)))
    urow("rdma_alloc_single", alloc.sysmem_size(12))
    row("rdma_alloc_double_round", U32.is_eq(alloc.sysmem_size(alloc.sysmem_size(12)), alloc.sysmem_size(12)))
    urow("rdma_alloc_st_args", STORAGE_ARGS())
    row("rdma_map_st_args", U32.is_eq(MAP_ST_ARGS(), 2))
    lrow("rdma_copyin_args", Tr.args(CALL_INS_WRITE(), Tr.calls(alloc.copyin(5, Tr.of()))))
    urow("rdma_copyin_n", Tr.ncalls(alloc.copyin(5, Tr.of())))
    urow("rdma_offset_val", alloc.offset(28672))
    row("rdma_offset_identity", U32.is_eq(alloc.offset(28672), 28672))
    urow("rdma_offset_n", alloc.offset_n())
    urow("rdma_unmap_n", Tr.ncalls(alloc.unmap(FX_KEY(), Tr.of())))
    lrow("rdma_unmap_args", Tr.args(CALL_UNREGISTER(), Tr.calls(alloc.unmap(FX_KEY(), Tr.of()))))

# --- 8: the DOORBELL, :33-36 and :129 --------------------------------------
def t_dbell() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, db.of(FX_DB_OFF(), Tr.of()))
    row("rdma_db_order", seq(t, [Call{CALL_MAP_BAR, 73728}, Call{CALL_BAR_INFO, VRAM_BAR()}]))
    urow("rdma_db_off_down", db.off_down(FX_DB_OFF()))
    urow("rdma_db_off_up", db.off_up(FX_DB_OFF()))
    urow("rdma_db_off_masked", U32.add(db.off_down(FX_DB_OFF()), db.off_up(FX_DB_OFF())))
    urow("rdma_db_off_orig", FX_DB_OFF())
    row("rdma_db_off_page", U32.is_zero(U32.mod(db.off_down(FX_DB_OFF()), PAGE())))
    urow("rdma_db_paddr", db.paddr(4096, FX_DB_OFF()))
    urow("rdma_db_addr", FX_DB())
    row("rdma_db_addr_low", U32.is_eq(FX_DB(), U32.add(FX_DB_PAGE(), db.off_up(FX_DB_OFF()))))
    row("rdma_db_addr_not_page", Bool.not(U32.is_eq(FX_DB(), FX_DB_PAGE())))
    row("rdma_snooped_doorbell", Bool.not(db.snooped()))
    row("rdma_bar_is_2", U32.is_eq(VRAM_BAR(), 2))
    urow("rdma_bar_both", U32.add(VRAM_BAR(), Iface.bar(Iface.of("RDMA:0", 0, FX_DB_OFF()))))

# --- 9: `db_value`, :130-131 AND THE TRUNCATION -----------------------------
def t_dbval() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_dbhi_sq", db_value.hi(FX_QPN(), DBC_DBC_TYPE_SQ()))
    urow("rdma_dbhi_rq", db_value.hi(FX_QPN(), DBC_DBC_TYPE_RQ()))
    urow("rdma_dbhi_scq", db_value.hi(FX_SCQ(), DBC_DBC_TYPE_CQ()))
    urow("rdma_dbhi_rcq", db_value.hi(FX_RCQ(), DBC_DBC_TYPE_CQ()))
    urow("rdma_dblo_sq", db_value.lo(0, 0))
    urow("rdma_dblo_1", db_value.lo(1, 0))
    urow("rdma_dblo_epoch", db_value.lo(0, 1))
    # WALL 5, MEASURED: `db_value` is a 64-bit word whose LOW half is 0 at both
    # call sites, so `ins`'s uint32 cast drops the high half and the OR at :148 is
    # a NO-OP on the value actually written. `rdma_db_hi_dropped` is the claim and
    # `rdma_db_written` is what the instruction stream carries instead.
    urow("rdma_db_written0", db_value.of(FX_QPN(), DBC_DBC_TYPE_SQ(), 0, 0))
    urow("rdma_db_written1", db_value.of(FX_QPN(), DBC_DBC_TYPE_SQ(), 1, 0))
    urow("rdma_db_written_n", db_value.of(FX_QPN(), DBC_DBC_TYPE_SQ(), 5, 0))
    row("rdma_db_hi_dropped", Bool.not(U32.is_zero(db_value.hi(FX_QPN(), DBC_DBC_TYPE_SQ()))))
    row("rdma_db_lo_zero", U32.is_zero(db_value.lo(0, 0)))
    row("rdma_db_or_noop", U32.is_eq(U32.or(1, db_value.lo(0, 0)), 1))
    row("rdma_db_const_bits", U32.is_eq(ins_const_bits(), 32))
    urow("rdma_db_type_send", ring_db_type(False{}))
    urow("rdma_db_type_recv", ring_db_type(True{}))
    row("rdma_db_type_send_zero", U32.is_zero(ring_db_type(False{})))
    urow("rdma_cq_id_send", cq_id(False{}, FX_SCQ(), FX_RCQ()))
    urow("rdma_cq_id_recv", cq_id(True{}, FX_SCQ(), FX_RCQ()))
    urow("rdma_cq_type", cq_db_type())

# --- 10: the EPOCH, :148,:151,:152 -- THE FIXTURE THAT SEES THE `^ 1` -------
def t_epoch() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_ep_slot_4095", db_slot(4095))
    urow("rdma_ep_slot_4096", db_slot(4096))
    urow("rdma_ep_slot_4097", db_slot(4097))
    urow("rdma_ep_bit_4095", db_epoch(4095))
    urow("rdma_ep_bit_4096", db_epoch(4096))
    urow("rdma_ep_bit_4097", db_epoch(4097))
    urow("rdma_ep_bit_8191", db_epoch(8191))
    urow("rdma_ep_bit_8192", db_epoch(8192))
    urow("rdma_ep_slot_8191", db_slot(8191))
    urow("rdma_ep_slot_8192", db_slot(8192))
    urow("rdma_wait_exp_send_4095", wait_expected(4095, False{}))
    urow("rdma_wait_exp_recv_4095", wait_expected(4095, True{}))
    urow("rdma_wait_exp_send_4096", wait_expected(4096, False{}))
    urow("rdma_wait_exp_recv_4096", wait_expected(4096, True{}))
    urow("rdma_wait_exp_send_4097", wait_expected(4097, False{}))
    urow("rdma_wait_exp_recv_4097", wait_expected(4097, True{}))
    urow("rdma_wait_exp_send_8191", wait_expected(8191, False{}))
    urow("rdma_wait_exp_send_8192", wait_expected(8192, False{}))
    urow("rdma_cq_slot_0", cq_slot_of(0))
    urow("rdma_cq_slot_1", cq_slot_of(1))
    urow("rdma_cq_slot_4095", cq_slot_of(4095))
    urow("rdma_cq_slot_4096", cq_slot_of(4096))
    urow("rdma_cq_slot_4097", cq_slot_of(4097))
    urow("rdma_wait_exp_recv_8191", wait_expected(8191, True{}))
    urow("rdma_wait_exp_recv_8192", wait_expected(8192, True{}))
    urow("rdma_wait_addr_0", cq_wait_addr(FX_CQ(), 0))
    urow("rdma_wait_addr_1", cq_wait_addr(FX_CQ(), 1))
    urow("rdma_wait_addr_4095", cq_wait_addr(FX_CQ(), 4095))
    urow("rdma_wait_addr_4096", cq_wait_addr(FX_CQ(), 4096))
    urow("rdma_wait_addr_4097", cq_wait_addr(FX_CQ(), 4097))
    urow("rdma_cq_slot_send_0", cq_db_slot(0))
    urow("rdma_cq_slot_send_1", cq_db_slot(1))
    urow("rdma_cq_bit_send_0", cq_db_epoch(0))
    # THE THREE CLAIMS, each a pair so neither half can be satisfied alone:
    # the doorbell rings the slot AFTER the element and the wait polls THIS one;
    # the wait's epoch is the doorbell's INVERTED; and the top bit is the receive.
    row("rdma_db_slot_is_next", U32.is_eq(db_slot(0), 1))
    row("rdma_wait_slot_is_n", U32.is_eq(cq_slot_of(0), 0))
    row("rdma_db_wait_slots_differ", Bool.not(U32.is_eq(db_slot(0), cq_slot_of(0))))
    row("rdma_epoch_inverted", U32.is_eq(wait_expected(0, False{}), 1))
    row("rdma_epoch_same_would_0", U32.is_eq(U32.xor(U32.and(U32.div(0, CQ_ENTRIES()), 1), 0), 0))
    row("rdma_wait_recv_bit", U32.is_eq(wait_expected(0, True{}), 3))
    row("rdma_wait_send_is_one", U32.is_eq(wait_expected(0, False{}), 1))
    row("rdma_wait_recv_is_three", U32.is_eq(wait_expected(0, True{}), 3))
    row("rdma_wait_recv_minus_send", U32.is_eq(U32.sub(wait_expected(0, True{}),
                                                       wait_expected(0, False{})), 2))
    row("rdma_epoch_one_bit", U32.is_le(db_epoch(8191), 1))
    urow("rdma_cqe_status_at", CQE_STATUS_AT())
    urow("rdma_cqe_size", CQE_SIZE())

# --- 11: the MSN, :144-145 --------------------------------------------------
def t_msn() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_msn_base", msn_base(FX_RING()))
    urow("rdma_msn_addr0", msn_addr(FX_RING(), 0))
    urow("rdma_msn_addr1", msn_addr(FX_RING(), 1))
    urow("rdma_msn_addr4096", msn_addr(FX_RING(), 4096))
    urow("rdma_msn_next0", msn_next_psn(0, 3))
    urow("rdma_msn_next1", msn_next_psn(3, 1))
    # the 64-bit word as its TWO exact halves.
    urow("rdma_msn_hi0", msn.hi(0, 3))
    urow("rdma_msn_lo0", msn.lo(3, 0))
    urow("rdma_msn_hi1", msn.hi(1, 4))
    urow("rdma_msn_lo1", msn.lo(4, 3))
    lrow("rdma_msn_whole0", [msn.hi(0, 3), msn.lo(3, 0)])
    lrow("rdma_msn_whole1", [msn.hi(1, 4), msn.lo(4, 3)])
    # MEASURED: the whole of element 0 is 0x3000000 and element 1 is
    # 0x1000004000003. The halves agree and neither needs a 64-bit shift.
    urow("rdma_msn_lo_is_low32", msn.lo(3, 0))
    row("rdma_msn_hi_is_slot16", U32.is_eq(msn.hi(1, 4), 65536))
    urow("rdma_msn_slot_masked", msn.hi(4095, 0))
    row("rdma_msn_slot_16", U32.is_eq(msn.hi(1, 0), 65536))
    row("rdma_msn_slot_0", U32.is_zero(msn.hi(0, 0)))
    row("rdma_msn_psn24", U32.is_eq(msn.lo(0, 16777215), 16777215))
    row("rdma_msn_next_psn_per_packet", U32.is_eq(msn_next_psn(0, 3), 3))
    # THE MASK, and the two rows that make it observable. Every other fixture has
    # a psn below 0xffffff, so `& PSN_MASK` is vacuously true and dropping it
    # moved NOTHING -- the mutation table's M8 was a zero until these two existed.
    # `psn_next_psn(0xffffff, 2)` is the WRAP: 24 bits, so the answer is 1 and not
    # 0x1000001, and `msn.lo(0, 0x1000000)` is the field: 0 and not 0x1000000.
    urow("rdma_msn_next_wrap", msn_next_psn(16777215, 2))
    urow("rdma_msn_field_over24", msn.lo(0, 16777216))
    urow("rdma_msn_hi_over24", msn.hi(0, 16777216))
    row("rdma_msn_mask_wraps", U32.is_eq(msn_next_psn(16777215, 2), 1))
    row("rdma_msn_mask_field", U32.is_zero(msn.lo(0, 16777216)))
    row("rdma_msn_mask_hi", U32.is_zero(msn.hi(0, 16777216)))
    row("rdma_msn_mask_both", Bool.and(U32.is_zero(msn.lo(0, 16777216)), U32.is_zero(msn.hi(0, 16777216))))
    urow("rdma_msn_field", MSN_FIELD())
    row("rdma_msn_past_ring", U32.is_eq(msn_base(FX_RING()), U32.add(FX_RING(), 524288)))
    row("rdma_msn_recv_none", Bool.not(ops.msn_at(True{}, 0)))
    row("rdma_msn_send_yes", ops.msn_at(False{}, 0))

# --- 12: the HEADER, :140 ---------------------------------------------------
def t_hdr() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_hdr0_send", hdr0(False{}))
    urow("rdma_hdr0_recv", hdr0(True{}))
    urow("rdma_hdr2_send", hdr2(False{}, 8193))
    urow("rdma_hdr2_recv", hdr2(True{}, 8193))
    lrow("rdma_hdr_send", hdr.of(False{}, 8193))
    lrow("rdma_hdr_recv", hdr.of(True{}, 8193))
    lrow("rdma_hdr_send_0", hdr.of(False{}, 0))
    lrow("rdma_hdr_recv_0", hdr.of(True{}, 0))
    lrow("rdma_wqe_send", wqe.words(False{}, 8193, FX_GPU(), 0, FX_KEY()))
    lrow("rdma_wqe_recv", wqe.words(True{}, 4096, FX_GPU(), 0, FX_KEY()))
    urow("rdma_hdr_len", hdr_len())
    urow("rdma_wqe_len", wqe_len(False{}))
    urow("rdma_wqe_len_recv", wqe_len(True{}))
    # THE SIZE IS IN THE SEND HEADER AND NOT IN THE RECEIVE ONE -- the receive
    # pack's 29-byte pad runs over byte 8. And the size appears TWICE in a send.
    row("rdma_hdr_recv_size_zero", U32.is_zero(hdr2(True{}, 8193)))
    row("rdma_hdr_send_size", U32.is_eq(hdr2(False{}, 8193), 8193))
    row("rdma_hdr_kind_recv", U32.is_eq(U32.and(hdr0(True{}), 255), RECV_KIND()))
    row("rdma_hdr_kind_send", U32.is_zero(U32.and(hdr0(False{}), 255)))
    urow("rdma_hdr_flags_send", U32.and(U32.shrn(hdr0(False{}), 8n), 255))
    row("rdma_hdr_signal", U32.is_eq(U32.and(U32.shrn(hdr0(False{}), 8n), 255), SQ_SEND_FLAGS_SIGNAL_COMP()))
    row("rdma_hdr_type3", U32.is_eq(U32.shrn(hdr0(False{}), 16n), WQE_KIND()))
    row("rdma_hdr_flags_recv_zero", U32.is_zero(U32.and(U32.shrn(hdr0(True{}), 8n), 255)))
    row("rdma_wqe_size_twice", U32.is_eq(wqe_len(False{}), 11))
    row("rdma_wqe_both_11", U32.is_eq(wqe_len(True{}), 11))

# --- 13: the INSTRUCTION STREAM, :136-155 -- A WHOLE SEND COPY ------------
def t_ops() -> IO(Unit):
  do IO<Unit>:
    # a SEND copy: two work queue elements over two buffers, no barrier.
    +s0 : Tr <- IO.pure(Tr, ops.wqe(False{}, FX_RING(), FX_CQ(), FX_DB(), 0, Tr.of()))
    row("rdma_send_first", seq(s0, [Call{CALL_INS_WRITE, 4096}, Call{CALL_INS_WRITE, 528384},
                                   Call{CALL_INS_WRITE, FX_DB()}, Call{CALL_INS_WAIT, 8216},
                                   Call{CALL_INS_WRITE, FX_DB()}]))
    urow("rdma_send_n5", Tr.ncalls(s0))
    row("rdma_send_rev", Bool.not(seq(s0, [Call{CALL_INS_WRITE, 528384}, Call{CALL_INS_WRITE, 4096}])))
    row("rdma_send_no_barrier", Bool.not(seq(s0, [Call{CALL_INS_BARRIER, OBJ_NONE()}])))
    # a RECV copy: one element, no msn write, and a barrier at the end.
    +r0 : Tr <- IO.pure(Tr, ops.barrier_at(True{}, ops.wqe(True{}, FX_RING(), FX_CQ(), FX_DB(), 0, Tr.of())))
    row("rdma_recv_first", seq(r0, [Call{CALL_INS_WRITE, 4096}, Call{CALL_INS_WRITE, FX_DB()},
                                   Call{CALL_INS_WAIT, 8216}, Call{CALL_INS_WRITE, FX_DB()},
                                   Call{CALL_INS_BARRIER, OBJ_NONE()}]))
    urow("rdma_recv_n5", Tr.ncalls(r0))
    row("rdma_recv_no_msn", Bool.not(seq(r0, [Call{CALL_INS_WRITE, 528384}])))
    row("rdma_recv_barrier_last", seq(r0, [Call{CALL_INS_WRITE, FX_DB()}, Call{CALL_INS_BARRIER, OBJ_NONE()}]))
    row("rdma_recv_vs_send_same_n", U32.is_eq(Tr.ncalls(r0), Tr.ncalls(s0)))
    row("rdma_recv_vs_send_diff_addrs", Bool.not(u32_list_eq(Tr.args(CALL_INS_WRITE(), Tr.calls(s0)),
                                                              Tr.args(CALL_INS_WRITE(), Tr.calls(r0)))))
    urow("rdma_send_n_writes", ops.n_writes(False{}))
    urow("rdma_recv_n_writes", ops.n_writes(True{}))
    urow("rdma_n_ins_send", ops.n_ins(False{}))
    urow("rdma_n_ins_recv", ops.n_ins(True{}))
    # the SECOND element of the send fixture: the ring slot advances by WQE_SIZE
    # and the msn by 8, and the wait by 32.
    +s1 : Tr <- IO.pure(Tr, ops.wqe(False{}, FX_RING(), FX_CQ(), FX_DB(), 1, Tr.of()))
    lrow("rdma_send1_writes", Tr.args(CALL_INS_WRITE(), Tr.calls(s1)))
    lrow("rdma_send0_writes", Tr.args(CALL_INS_WRITE(), Tr.calls(s0)))
    lrow("rdma_send0_waits", Tr.args(CALL_INS_WAIT(), Tr.calls(s0)))
    lrow("rdma_send1_waits", Tr.args(CALL_INS_WAIT(), Tr.calls(s1)))
    row("rdma_two_doorbells_one_addr", u32_list_eq(Tr.args(CALL_INS_WRITE(), Tr.calls(s0)), [4096, 528384, FX_DB(), FX_DB()]))
    row("rdma_send_n4_writes", U32.is_eq(U32.from_nat(List.length(&2, U32, Tr.args(CALL_INS_WRITE(), Tr.calls(s0)))), 4))

# --- 14: the REGISTRATION and the ADDRESS TRANSLATION, :42-53 --------------
def t_map() -> IO(Unit):
  do IO<Unit>:
    +pdt : Pdt <- IO.pure(Pdt, Pdt.put2(FX_GPU(), FX_KEY(), Pdt.put2(12288, 24576, Pdt.of())))
    urow("rdma_pdt_len", Pdt.len(pdt))
    # BOTH DIRECTIONS. A table that only answered one of these could be two
    # independent tables instead of one translation.
    urow("rdma_key_of_7000", key_of(pdt, 28672))
    urow("rdma_key_of_3000", key_of(pdt, 12288))
    urow("rdma_key_of_0", key_of(pdt, 0))
    urow("rdma_key_of_ffff", key_of(pdt, 65535))
    urow("rdma_va_of_9000", va_of(pdt, 36864))
    urow("rdma_va_of_6000", va_of(pdt, 24576))
    urow("rdma_va_of_0", va_of(pdt, 0))
    urow("rdma_va_of_1", va_of(pdt, 1))
    row("rdma_pdt_roundtrip", U32.is_eq(va_of(pdt, key_of(pdt, 28672)), 28672))
    row("rdma_pdt_unregistered", U32.is_zero(key_of(pdt, 65535)))
    # :42-53, the good path: two 4 KiB regions, so TWO pages at log_page 12.
    +ok : Tr <- IO.pure(Tr, map.run(True{}, 1, 1, True{}, FX_GPU(), [4096, 16384], [4096, 16384], [4096, 4096], 8192, Tr.of()))
    urow("rdma_map_n", Tr.ncalls(ok))
    lrow("rdma_map_args", Tr.args(CALL_REGISTER(), Tr.calls(ok)))
    row("rdma_map_ok", seq(ok, [Call{CALL_REGISTER, 2}]))
    row("rdma_map_not_refused", Bool.not(Tr.refused(ok)))
    # THE PEER GUARD, :44 -- two conjuncts and BOTH fixtures, because a guard with
    # only the first conjunct still refuses both of these.
    +nif : Tr <- IO.pure(Tr, map.run(False{}, 1, 1, True{}, FX_GPU(), [4096], [4096], [4096], 4096, Tr.of()))
    +ngr : Tr <- IO.pure(Tr, map.run(True{}, 2, 1, True{}, FX_GPU(), [4096], [4096], [4096], 4096, Tr.of()))
    urow("rdma_map_noiface_n", Tr.ncalls(nif))
    urow("rdma_map_nopeer_n", Tr.ncalls(ngr))
    urow("rdma_map_noiface_regs", Tr.count(CALL_REGISTER(), Tr.calls(nif)))
    urow("rdma_map_nopeer_regs", Tr.count(CALL_REGISTER(), Tr.calls(ngr)))
    row("rdma_map_noiface_refused", Tr.refused(nif))
    row("rdma_map_nopeer_refused", Tr.refused(ngr))
    row("rdma_map_noiface_msg", String.eq(REFUSE_MAP_MSG(), "RDMA requires memory on its node"))
    row("rdma_peer_ok_both", map.peer_ok(True{}, 1, 1))
    row("rdma_peer_ok_noiface", Bool.not(map.peer_ok(False{}, 1, 1)))
    row("rdma_peer_ok_diff", Bool.not(map.peer_ok(True{}, 2, 1)))
    # THE PAGE-SIZE REFUSAL, :48 -- an odd address matches no candidate.
    +odd : Tr <- IO.pure(Tr, map.run(True{}, 1, 1, True{}, 1, [4096], [4096], [4096], 4096, Tr.of()))
    urow("rdma_map_odd_n", Tr.ncalls(odd))
    urow("rdma_map_odd_regs", Tr.count(CALL_REGISTER(), Tr.calls(odd)))
    row("rdma_map_odd_refused", Tr.refused(odd))
    # THE ASPACE BRANCH, :46 -- SYS keeps the mapping's own addresses.
    row("rdma_aspace_sys", U32.is_eq(ASPACE_SYS(), 1))
    lrow("rdma_paddrs_sys", map.paddrs(True{}, [4096], [8192]))
    lrow("rdma_paddrs_peer", map.paddrs(False{}, [4096], [8192]))

# --- 15: the MISSING KEY -- THE NEGATIVE CASE ----------------------------
def t_nokey() -> IO(Unit):
  do IO<Unit>:
    # :140 asks the DEVICE for the NIC-side address. A buffer that was never
    # registered has no key, and a work queue element carrying key 0 is a
    # transfer to nowhere the NIC will accept. `map.key_guard` refuses, and no
    # Python guard writes that down -- it is :140 read the other way round.
    +empty : Pdt <- IO.pure(Pdt, Pdt.of())
    urow("rdma_nokey_key", key_of(empty, FX_GPU()))
    urow("rdma_nokey_n", Tr.ncalls(map.key_guard(key_of(empty, FX_GPU()), Tr.of())))
    row("rdma_nokey_refused", Tr.refused(map.key_guard(key_of(empty, FX_GPU()), Tr.of())))
    row("rdma_nokey_passed", Bool.not(Tr.refused(map.key_guard(key_of(FX_PDT(), FX_GPU()), Tr.of()))))
    urow("rdma_nokey_written", Tr.count(CALL_INS_WRITE(), Tr.calls(Tr.refuse(REFUSE_NO_KEY(), Tr.of()))))
    urow("rdma_refuse_n_types", 4)
    urow("rdma_refuse_n_nested", 0)

# --- 16: the RING CAP, :120 -- THE OTHER NEGATIVE CASE --------------------
def t_cap() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_cap", RING_CAP())
    urow("rdma_cap_eq_ring", RING_CAP())
    row("rdma_cap_ok_4096", copies.cap_ok(4096))
    row("rdma_cap_no_4097", Bool.not(copies.cap_ok(4097)))
    row("rdma_cap_ok_0", copies.cap_ok(0))
    +bad : Tr <- IO.pure(Tr, copies.guard(copies.cap_ok(4097), Tr.of()))
    urow("rdma_cap_refuse_n", Tr.ncalls(bad))
    urow("rdma_cap_refuse_regs", Tr.count(CALL_INS_WRITE(), Tr.calls(bad)))
    row("rdma_cap_refused", Tr.refused(bad))
    row("rdma_cap_refuse_order", seq(bad, [Call{CALL_REFUSE, REFUSE_RING_CAP()}]))
    row("rdma_cap_msg", String.eq(REFUSE_CAP_MSG(), "a batch posts at most a ring of wqes per pair"))
    urow("rdma_cap_no_ins", Tr.count(CALL_INS_WRITE(), Tr.calls(copies.guard(copies.cap_ok(4096), Tr.of()))))

# --- 17: `rdma_submit`, :161-169 -------------------------------------------
def t_submit() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_encode_len", encode_len())
    row("rdma_submit_fires_2", submit.fires(2))
    row("rdma_submit_none_0", Bool.not(submit.fires(0)))
    # THE NEGATIVE CASE: a linear of FIVE srcs with TWO on an RDMA queue. The
    # three others keep THEMSELVES -- `ops = [[u] for u in lin.src]` -- and are
    # NOT replaced by ring writes and doorbell writes.
    urow("rdma_submit_srcs", 5)
    urow("rdma_submit_replaced", submit.src_replaced(5, 2))
    urow("rdma_submit_kept", submit.srcs_kept(5, 2))
    row("rdma_submit_keeps_nonrdma", U32.is_eq(submit.srcs_kept(5, 2), 3))
    row("rdma_submit_all_queues", U32.is_eq(submit.srcs_kept(5, 5), 0))
    # `positions` is ASCENDING because the dict at :162 was built by `enumerate`.
    urow("rdma_submit_pos0", submit.pos_at(0))
    urow("rdma_submit_pos1", submit.pos_at(1))
    row("rdma_submit_pos_asc", U32.is_lt(submit.pos_at(0), submit.pos_at(1)))
    # the wire tests, :99-101 -- TWO op tests and the first RDMA arg.
    urow("rdma_wire_cs", wire.of(True{}, True{}, 1))
    urow("rdma_wire_notcall", wire.of(False{}, True{}, 1))
    urow("rdma_wire_notstore", wire.of(True{}, False{}, 1))
    urow("rdma_wire_none", wire.of(True{}, True{}, 0))
    row("rdma_is_rdma_cs", wire.is_rdma(True{}, True{}, 1))
    row("rdma_is_rdma_notcall", Bool.not(wire.is_rdma(False{}, True{}, 1)))
    row("rdma_is_rdma_notstore", Bool.not(wire.is_rdma(True{}, False{}, 1)))
    row("rdma_is_rdma_none", Bool.not(wire.is_rdma(True{}, True{}, 0)))
    # :106 the SORTED pair and the recv flag.
    srow("rdma_queue_lo", queue.lo("GPU", "rdma_gpu_0_gpu_1_sq"))
    srow("rdma_queue_hi", queue.hi("GPU", "rdma_gpu_0_gpu_1_sq"))
    srow("rdma_queue_lo_rev", queue.lo("rdma_gpu_0_gpu_1_sq", "GPU"))
    row("rdma_queue_sorted", String.eq(queue.lo("GPU", "rdma_gpu_0_gpu_1_sq"), "GPU"))
    row("rdma_queue_sorted_rev", String.eq(queue.lo("rdma_gpu_0_gpu_1_sq", "GPU"), "GPU"))
    row("rdma_recv_is_src", queue.is_recv(True{}))
    row("rdma_send_not_src", Bool.not(queue.is_recv(False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_sizes()
    c : Unit <- t_tags()
    +d : Unit <- t_page()
    e : Unit <- t_chunks()
    +f : Unit <- t_dev()
    +g : Unit <- t_alloc()
    +h : Unit <- t_dbell()
    i : Unit <- t_dbval()
    +j : Unit <- t_epoch()
    k : Unit <- t_msn()
    +l : Unit <- t_hdr()
    +m : Unit <- t_ops()
    +n : Unit <- t_map()
    o : Unit <- t_nokey()
    +p : Unit <- t_cap()
    q : Unit <- t_submit()
    IO.print("rdma-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number below is `.agents/slop/mutate.py`'s output,
# not an estimate. The harness applies one edit to a scratch copy, runs the
# INTERPRETED lane, and diffs the row NAMES; the useful column is "rows MOVED",
# because a mutation that moves nothing measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | the candidate list is DESCENDING, so the fold's LAST match is the SMALLEST | 11 | :48's `max()` over an ASCENDING list. Eleven and not four because every `rdma_lp_*` row is a different alignment and a wrong `log_page` is a wrong page count, which is a wrong registration, which is a silently wrong transfer. |
# | M2 | `log_page` answers 12 when NOTHING matches -- no ValueError | 7 | `max()` of an EMPTY generator. It moves the four `rdma_lp_none_*` rows, `rdma_lp_none_flagged` and -- the two that matter -- `rdma_map_odd_refused` and `rdma_map_odd_regs`. The last is the refusal not firing, so the NESTING of the guard inside the call is what makes this mutation visible at the trace and not only in the table. |
# | M3 | `wait_expected` drops the `^ 1` epoch inversion | 14 | **THE BIGGEST IN THE FILE, and the one that would have shipped.** :151's `(n // CQ_ENTRIES & 1 ^ 1)` -- and it moves EVERY `rdma_wait_exp_*` row, both send and receive, across one and a half ring wraps. A port that dropped the `^ 1` compiles, typechecks, passes every count, passes every address, and HANGS: nothing ever matches the completion entry. The EPOCH fixture is the only reason it is caught, and every one of its rows is a DIFFERENT `n` because a single wrap point cannot see an inversion. |
# | M4 | the doorbell rings slot `n` instead of `n + 1` | 7 | :148's `n + 1` against :151's `n`. It moves `rdma_db_slot_is_next`, `rdma_db_wait_slots_differ` and all five `rdma_ep_slot_*`. The doorbell and the wait must be ONE APART, and that is the ring protocol in one number. |
# | M5 | the epoch drops its `& 1` | 3 | that the epoch is a SINGLE BIT. Only `rdma_ep_bit_8191`, `rdma_ep_bit_8192` and `rdma_epoch_one_bit` move -- the two that need `n` past TWO wraps -- which is why the epoch fixture runs to 8192 and not to 4097. |
# | M6 | the receive bit is dropped from `wait_expected` | 8 | the `| (2 if is_recv else 0)`, so a receive and a send on one completion queue can no longer be told apart. It moves the receive rows and `rdma_wait_recv_minus_send`, and NOT the send rows: the two sides are separate claims and the receive fixture is what makes them so. |
# | M7 | the msn slot sits at bit 0 instead of bit 48 | 5 | :145's `<< 48`. `base.bend` has no 64-bit shift, so the port carries the word as two halves with the slot at hi32's bit 16; this mutation puts it at bit 0 of the LOW half and the five `rdma_msn_hi*`/`slot*` rows see it. |
# | M8 | the msn psn fields are unmasked (no `& 0xffffff`) | 3 | :145's `& 0xffffff`, **and this was a ZERO until the fixture straddled 2^24.** Every original psn is below `0xffffff`, so the mask is vacuously true and dropping it changed nothing. `rdma_msn_next_wrap` (`psn_next_psn(0xffffff, 2)` is 1, not `0x1000001`) and `rdma_msn_field_over24` / `rdma_msn_mask_field` / `rdma_msn_mask_hi` are the rows that exist only for it. This is the same lesson `device.bend`'s `tag_of` row teaches and it is worth writing down twice. |
# | M9 | the send ring drops the `+ 8` msn table | 3 | :92's `WQE_SIZE + 8`. The msn table lives at `ring + RING_ENTRIES * WQE_SIZE` (`:144`), so a send ring allocated without the `+ 8` overlaps its own last work queue element. `rdma_msn_past_ring` does NOT move, because it reads the ADDRESS and not the SIZE: the arithmetic is right and only the allocation is wrong, which is exactly the split. |
# | M10 | `bump.psn` adds `packets` on a RECEIVE too | 1 | :123's `([] if is_recv else [psn...])`. ONE row, and it is the whole send/receive asymmetry in the sequence counters: a receive consumes no packet-send-numbers because the psns are the SENDER's. A localised row, and it is localised on purpose. |
# | M11 | the receive header gets the size in word 2 as well | 4 | bnxtdev.py:19's 29-byte pad, which runs OVER the `I size` at byte 8. A receive's work queue element says nothing about its length in the header, and :141 supplies it as a separate word. `rdma_hdr_recv`, `rdma_hdr_recv_0`, `rdma_hdr_recv_size_zero` and `rdma_wqe_recv` move. |
# | M12 | `psns` drops the `initial=0` -- one entry short | 3 | :125's `itertools.accumulate(chunks, initial=0)`. It moves `rdma_psns_send`, `rdma_psns_recv` and `rdma_psns_2` -- and NOT `rdma_psns_len_send`/`rdma_psns_len_recv`, because those read `psns_len(wqes)` and not the list. That is the two-rows-one-claim shape: the COUNT and the CONTENTS are transcribed independently and can disagree. |
# | M13 | `chunks_of` reverses the chunk order | 2 | that `range(0, n, CHUNK)` walks ASCENDING. Only `rdma_chunks_1g1p` and `rdma_chunks_1g4p` move, because every other fixture is one chunk or two equal chunks: a buffer larger than `RDMA_CHUNK` is the ONLY thing that can see the order, and it takes two such rows to see both directions. |
# | M14 | `alloc.buf_size` rounds the BUFFER's size to a page too | 3 | :31's `Buffer(self.dev.device, mem.nbytes, dtypes.u8, …)` against :27's `round_up(mem.nbytes, 0x1000)`. The buffer's size is RAW and the virtual address is ROUNDED, and both are right. `rdma_buf_nb_raw` and `rdma_buf_diff` are the pair; a port that rounded both would under-report a 12-byte buffer as 4096 bytes of dtype. |
# | M15 | `db.off_down` keeps the low twelve bits -- the doorbell pages UP | 5 | :35's `& ~0xfff`. The mapping must start ON a page, and :36 then adds the SAME `off` to the bar base. All three spellings of the address -- `db.off_down`, `db.off_up`, `db.addr` -- depend on the mask going both ways, and `rdma_db_off_masked` is the row that says the two halves sum back to `db_off`. |
# | M16 | the page guard is OUTSIDE the register call -- a warning, not a refusal | 2 | **THE NESTING, and it is the whole claim that a refusal TRUNCATES.** Python raises at :48 before it reaches `register_mem` at :50, so an unusable page size means the region is NEVER REGISTERED. With the guard outside the call the trace reads `REGISTER(0), REFUSE(log_page)` -- the registration happened and then the refusal, which is the opposite of what the source does. `rdma_map_odd_n` and `rdma_map_odd_regs` move. **This was a real port bug and the CPython oracle found it, not the mutation table.** |
# | M17 | `va_of` is the forward lookup too -- no reverse direction | 3 | :106's `min(gpu, wire.tag), max(gpu, wire.tag)` and :140's `getaddr(nic.device)`. The TRANSLATION TABLE has to answer in both directions and a table that answers only one is two tables. `rdma_va_of_9000`, `rdma_va_of_6000` and `rdma_pdt_roundtrip` move; the `key_of_*` rows do not, which is what makes the pair a pair. |
# | M18 | `_offset` adds the offset -- the HOST allocator's rule | 2 | :52's `return buf`. `ops_npy.bend`'s `npy.offset` is `buf + offset` and this is `buf`, and the two files' gates are the only thing in the tree that tells them apart. It moves `rdma_offset_val` and `rdma_offset_identity` and NOT `rdma_offset_n`, because the trace for `_offset` is empty either way. |
# | M19 | `submit.src_replaced` replaces EVERY src, RDMA or not | 3 | :164's `ops = [[u] for u in lin.src]`. **THE NEGATIVE CASE THE BRIEF ASKED FOR:** a src with no RDMA wire keeps ITSELF and is not replaced by ring writes and doorbell writes. `rdma_submit_kept`, `rdma_submit_keeps_nonrdma` and `rdma_submit_all_queues` move. |
# | M20 | the qp buffer-name table is reversed against ops_rdma.py's order | 2 | :82-83's `("sq","rq","scq","rcq")` then `sq_seq, rq_seq, psn` then `db`. Only `rdma_buf_1` and `rdma_buf_8` move, because a reversal that swaps 1<->8 and 2<->7 etc. leaves the MIDDLE four correct: two rows and not one is the price of a fixture that reads only the ends, and `rdma_bufs_len` does not move at all. |
# | M21 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# M8 and M16 ARE THE INTERESTING ONES, and they are different kinds of finding.
# M16 is a PORT BUG the CPython oracle caught and no mutation would have: the two
# guards looked right and the nesting was wrong, so the port recorded a
# registration that Python never performs. M8 is a GATE bug the mutation table
# caught: the mask is in the source, the port, and the gate, and all three agree
# on every fixture because every fixture's psn fits in 24 bits.
#
# WHAT THIS GATE STILL DOES NOT SEE, and it is a SHORT list, which is the point:
#
#   1. THE INSTRUCTION ARGUMENTS. `Tr` records the call and, for the twelve calls
#     that take a number, that number. The work queue element's ELEVEN payload
#     words, the msn value, the two doorbell values and the expected wait value
#     are all pure functions with their OWN rows -- `rdma_wqe_send`,
#     `rdma_msn_whole0/1`, `rdma_db_written*`, `rdma_wait_exp_*` -- but nothing
#     checks that the RIGHT one is passed to the RIGHT call. Mutating `ins.ring_db`
#     to write the msn address instead of the doorbell address moves NOTHING,
#     because both are one `CALL_INS_WRITE` with a different argument and no row
#     pairs an address with an instruction kind.
#   2. `db_value`'s HIGH HALF. WALL 5 is about the low half being transmitted
#     (`rdma_db_hi_dropped`, `rdma_db_lo_zero`, `rdma_db_or_noop`) and those rows
#     are exact. But `db_value.hi` is a pure function of `xid` and `typ` and
#     nothing ever CONSUMES it: if `BNXT_QPLIB_DBR_VALID` were wrong, only
#     `rdma_dbr_valid` and `rdma_dbhi_*` would move, and no transfer would change.
#   3. `hdr.of`'s WORDS 1 AND 3-7. They are zero in `struct.pack`'s output and
#     this port writes zero; a version that wrote garbage into the five padding
#     words would print the same `hdr0`/`hdr2` and only `rdma_hdr_send`/`recv`
#     could see it -- and they do, but only because they print all eight.
#   4. `get_call_arg_uops` and `unwrap_view`. WALL 4. The port reads `key_of(va)`
#     where Python calls the device, and the two agree because the device's answer
#     IS the key -- an assumption, and the only one in this file that is not a
#     transcription.
#   5. THE WIRE TAG. REPORTED IN THE HEADER and not fixed: on a graph that reached
#     `lower_call` with the wire already bufferized, `UOp.tag` is `None` and
#     `min(gpu, None)` raises. `rdma_queue_sorted` pins the sort with the tag
#     spelled as a string, which is the case the source unambiguously supports,
#     and `wire.tag` being `None` is not exercised because there is no RDMA
#     hardware here.
#   6. THE DRIVER. WALL 2. `BNXTDev`'s queue state, the `connect` handshake and
#     the firmware are all seam. `rdma_connects = 2` says the Python writes two
#     `connect` calls and nothing about whether either succeeds.
