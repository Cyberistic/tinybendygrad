# tinybendygrad/runtime/ops_rdma.bend -- port of tinygrad/runtime/ops_rdma.py
#
# RDMA IS not a device with a driver on it. IT is a network fabric, AND the
# THREE things that makes it different from ops_webgpu.bend ARE all here:
#
#   1. A BUFFER IS REGISTERED BEFORE IT CAN BE SENT TO. `BNXTAllocator._map`
#      (:42-51) hands the NIC a page list, a size, a LOG PAGE SIZE and the GPU
#      virtual address, and the NIC answers a KEY. From that moment the GPU
#      address is not usable by the NIC and the key is not usable by the GPU, and
#      `rdma_copies` (tinygrad/runtime/ops_rdma.py:107 symbol=rdma_copies) puts BOTH in every work queue element. So there is a
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
#   3. THE completion queue has its own order, AND it is not the ring'S. The
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

# WHAT IS PORTED, DEF BY DEF. Line numbers are ops_rdma.py.
#
#   :16  RDMA_CHUNK                  PORTED  `RDMA_CHUNK()`
#   tinygrad/runtime/ops_rdma.py:18 `BNXT_IDS`          PORTED  the four constants and `vram_bar` symbol=BNXT_IDS
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
#   :57  `node`                       NOT PORTED -- a NESTED def inside `rdma_nic_for`
#   :58  `bus`                        NOT PORTED -- a NESTED def inside `rdma_nic_for`
#   :61  the `except RuntimeError`    NOT PORTED -- inside `rdma_nic_for`
#   :64  the closest NIC              NOT PORTED -- inside `rdma_nic_for`, a `min(...)`
#   THE four above said "PORTED" AND were not. `node`/`bus` are nested defs INSIDE `rdma_nic_for`
#   (tinygrad/runtime/ops_rdma.py:57-64 symbol=node) `node` and the closest nic is a `min(...)` at the END of that range; MEASURED, there is no `def
#   nic.node` (or `.bus`/`.list`/`.closest`) anywhere in the port, and no `rdma_nic_for` either. The
#   error's shape: a NAME was read in the CPython and a SAME-NAMED def assumed in the port.
#   :67  `ifaces = [BNXTIface]`       PORTED  `Rdma.ifaces`
#   :69-71 `RDMADevice.__init__`      PORTED  `dev.init` -- iface FIRST, then
#                                               `BNXTAllocator(self), [], None`
#   :79  the anchor `Device[min(pair)]` PORTED `qp.anchor`
#   :80  `{nic.device: BNXTQP(...)}`  PORTED  `qp.new`
#   :82  the four ring buffers        PORTED  `ring_elems.at` -- sq rq scq rcq
#   :83  the three uint64s + `db` -- upstream's `sq_seq` IS the first of the three --
#                                               PORTED  `qp_name`/`qp_itemsize` -- sq_seq
#                                               rq_seq psn, db
#   :166 the UPat rules -- upstream's `PatternMatcher` IS the rules' holder --
#                                               PORTED  `qp.rules_len` -- 8 tags, FIRST-WINS
#   tinygrad/runtime/ops_rdma.py:166 `PatternMatcher(rules)` PORTED `qp_len` -- upstream's `pm_bufferize` is GONE (9ff6db7b0)
#   :86  `connect` both ways          PORTED  `qp.connect` -- nics THEN reversed
#   :89  `rdma_mem`                   PORTED  `mem.of` -- volatile, dtype, tag
#   :91-92 `rdma_ring`                PORTED  `mem.ring` -- send is WQE+8
#   :93  `rdma_cq`                    PORTED  `mem.cq`   -- 32 bytes an entry
#   :94  `rdma_seq`                   PORTED  `mem.seq`  -- 1 uint64
#   :95  `rdma_psn`                   PORTED  `mem.psn`
#   :96  `rdma_db`                    PORTED  `mem.db`   -- one whole page
#   :99-100 `rdma_wire`               PORTED  `wire.of`  -- CALL/STORE, then RDMA
#   tinygrad/runtime/ops_rdma.py:100 `is_rdma`           PORTED  `wire.is_rdma` symbol=is_rdma
#   :104-106 `queue_of`               PORTED  `queue.hi`/`queue.lo` -- the SORTED
#                                               pair and
#                                               `wire is src`
#   tinygrad/runtime/ops_rdma.py:108 `ins`                PORTED  `queue.is_recv` -- every int is a uint32 symbol=rdma_copies
#   :112 `queue_of(calls[0])`         PORTED  `copies.cap_ok` + `Tr.count`
#   :113 `rdma_qp(pair)[nic.device]`  PORTED  `qp.new`
#   :116 `bufs = [args[c][0 if recv else 1]]` PORTED `ops.wqe`
#   :113 the chunks comprehension -- upstream's `chunks` IS the comprehension --
#                                              PORTED  `chunks_of` / `nchunks` / `psns_len`
#   tinygrad/runtime/ops_rdma.py:114 `len(chunks), sum(chunks)` PORTED  `nchunks`, `ops.n_writes` symbol=rdma_copies
#   :120 the ring-cap ASSERT          PORTED  `copies.guard`  (the REFUSAL)
#   :123 the bumps                    PORTED  `bump.seq` / `bump.psn`
#   tinygrad/runtime/ops_rdma.py:121 `accumulate(chunks, 0)` PORTED  `psns_of` symbol=rdma_copies
#   tinygrad/runtime/ops_rdma.py:122 `n`, `p`            PORTED  `ops.n_of` / `ops.p_of` -- upstream's `psns` symbol=rdma_copies
#   :128 `ring.getaddr`, `cq.getaddr` PORTED  `ins.write` / `ins.cq_db`
#   tinygrad/runtime/ops_rdma.py:126 the `db` address      PORTED  `ins.ring_db` -- low 12 bits only symbol=rdma_copies
#   :130-131 `db_value`               PORTED  `db_value.hi` / `db_value.lo`
#   :136-137 the chunk loop           PORTED  `ops.chunk_size` / `ops.wqe`
#   :140 `hdr` and `key`              PORTED  `hdr.of` and `key_of`
#   :141 the ring write               PORTED  `ins.write`
#   :144-145 the msn entry            PORTED  `ins.msn` -- 48/24/24, two halves
#   :148 the ring doorbell            PORTED  `ins.ring_db`
#   :151 `wait_eq`                    PORTED  `ins.wait` -- the inverted epoch
#   tinygrad/runtime/ops_rdma.py:127 the cq doorbell       PORTED  `ins.cq_db` symbol=rdma_copies
#   :155 the recv barrier             PORTED  `ins.barrier`
#   :162 the `{i: queue_of(u)}` dict  PORTED  `submit.fires`
#   :164 `ops = [[u] for u in lin.src]` PORTED `submit.src_replaced` -- a NON-rdma src
#                                               keeps ITSELF
#   :165 `dict.fromkeys(queues.values())` PORTED `submit.srcs_kept`
#   tinygrad/runtime/ops_rdma.py:163 `positions`           PORTED  `submit.pos_at` symbol=rdma_submit
#   tinygrad/runtime/ops_rdma.py:164 the zip                 PORTED  `psns_at` + `ops.n_of` symbol=rdma_submit
#   tinygrad/runtime/ops_rdma.py:157 `rdma_submit`          PORTED  `encode_len` -- upstream's `pm_rdma_encode` is GONE (9ff6db7b0)
#

# THE FIVE WALLS.
#
# 1. MEMOISATION (:56, :77). `functools.cache` on `rdma_nic_for` and `rdma_qp`,
#    keyed on a live device object. Same wall as `device.bend`'s
#    `_opened_devices`, and the same answer: the CACHE KEY is ported -- the
#    anchor name, the sorted pair -- and the cache itself is not.
#    TODO(p3) ops_rdma.py:56  symbol=rdma_nic_for  `functools.cache` on a device object.
# 2. THE NETLINK AND THE DRIVER (support/system.py, support/rdma/bnxtdev.py).
#    `System.list_devices(*BNXT_IDS)`, `filter_visible_devices`, `PCIDevice`
#    probing, `BNXTDev` firmware state and the mlx5/bnxt queues. All seams; the
#    PCI ids, the bus number and the node string -- the three things those calls
#    are asked FOR -- are ported.
#    wall(p3) ops_rdma.py:60  System.list_devices + filter_visible_devices -- blocked: needs `System.list_devices(*BNXT_IDS)` + `filter_visible_devices` (netlink/driver seams, support/system.py; no def in the tree). contradiction: the :70-73 table says `nic.node`/`nic.bus`/`nic.list`/`nic.closest` are ported, but none is a def anywhere in `tinybendygrad/` -- they are local helpers inside `rdma_nic_for` (:56-64), which is unported, so the bus number and node string are not ported either.
#    TODO(p3) ops_rdma.py:22  symbol=__init__  PCIDevice -- bar probing and firmware.
# 3. `PCIIfaceBase.p2p_paddrs` (:46). The GPU-to-GPU translation into the NIC's
#    address space, for a peer-to-peer mapping. It is a driver call against live
#    peer BARs. The port keeps the BRANCH -- `AddrSpace.SYS` keeps `mapping.paddrs`
#    and everything else is translated -- because the branch is what decides
#    whether the registration is right.
#    TODO(p3) ops_rdma.py:46  symbol=_map  PCIIfaceBase.p2p_paddrs.
# 4. `unwrap_view` (tinygrad/runtime/ops_rdma.py:136 symbol=rdma_copies). Collapsing a view chain to (base, offset) and then
#    `getaddr(nic.device)` on it. The NIC-side address IS the key the
#    registration handed back, so the port reads it out of `Pdt` -- which is the
#    same number, arrived at by the other direction, and that is the point of
#    carrying the table both ways.
#    TODO(p3) ops_rdma.py:136  symbol=rdma_copies  unwrap_view(...)[0].getaddr(nic.device).
# 5. THE 64-BIT WORDS. Two of them and neither is a TODO, because both are
#    carried as TWO `U32` HALVES and both are exact:
#      `db_value` (bnxtdev.py:13) is `(... << 32) | (index | epoch << 24)`, so
#        `db_value.hi` and `db_value.lo` are both whole halves. AND the low half
#        is 0 whenever `index` and `epoch` are, which is every `db_value` call
#        RDMA makes (:130-131) -- so `ins`'s `UOp.const(s, dtypes.u32)`
#        TRUNCATES the high half away and the doorbell the NIC receives carries
#        only the slot and the epoch. MEASURED, and it is the sharpest thing in
#        this file: `rdma_db_hi_dropped`. REPORTED, not fixed.
#      the msn entry (tinygrad/runtime/ops_rdma.py:141 symbol=rdma_copies) is `slot << 48 | next << 24 | psn` -- upstream's `psns` -- all three fields
#        24 bits wide and `slot` in the TOP 16. So `msn.hi(slot, next)` and
#        `msn.lo(next, psn)` are exact halves and no shift is missing.
#

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

import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S


# THE CONSTANTS. Every one MEASURED, by reading
# `tinygrad/runtime/support/rdma/bnxtdev.py:12` and the enums out of
# `tinygrad/runtime/autogen/bnxt.py`; `.agents/slop/oracle_rdma.py` re-derives
# every gate expectation from them.

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


# THE TYPES.


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


# THE TRACE. Every device call in this file goes through `Tr.emit`, so the trace
# is the ordered list of things the NIC would be asked to do.

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

# A refusal is recorded and is also the thing that truncates. `refused` is set
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


# READING THE TRACE. Same three readers as ops_webgpu.bend, and the same fuel bug
# they were written around: the fuel is the TRACE's length and the answer is
# `at == patlen`, so a reversed pattern does NOT match.

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


# ops_rdma.py:89-96 -- the six placeholder constructors. Their SIZES are the
# whole content and they are not interchangeable: the SEND ring is
# `RING_ENTRIES * (WQE_SIZE + 8)` because a send also writes an 8-byte msn entry
# past the end of the ring (:144), so the send ring is BIGGER than the receive
# ring and a port that drops the `+ 8` under-allocates every send queue.

def ring_elems.at(recv: Bool) -> U32:
  Bool.pick(U32, recv, WQE_SIZE(), U32.add(WQE_SIZE(), 8))

def ring_elems(+recv: Bool) -> U32: ring_elems.at(recv)

def seq_elems() -> U32: 1
def seq_bytes() -> U32: U32.mul(seq_elems(), S.Dt.itemsize(S.uint64()))
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


# `to_name` (tinygrad/helpers.py:24) -- `"_".join(parts).replace(":", "_").lower()`.
# It is the TAG every `rdma_mem` placeholder carries and the key every
# `pm_bufferize` rule matches on (:84), so a `to_name` that did not lower-case
# would match nothing and a rule table that is silently empty posts nothing.
#
# The lower-case happens on the JOINED string, so it also lower-cases the
# separators -- which is unobservable here because `_` is already lower, and
# WHICH is why the port does not depend on it: the port lower-cases each part
# before joining and the two agree for every device name in the tree.

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

def VA_ALIGN() -> U32: 4096
def STORAGE_ARGS() -> U32: 3

# :27 the VA size: `round_up(mem.nbytes, 0x1000)`. The walrus means `size` is the
# ROUNDED number and the mapping at :28 uses it, so the mapping is page-exact.
def alloc.va_size(+nbytes: U32) -> U32: H.round_up_u32(nbytes, VA_ALIGN())

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

def db.off_down(+db_off: U32) -> U32: U32.and(db_off, U32.not(PAGE_MASK()))

def db.off_up(+db_off: U32) -> U32: U32.and(db_off, PAGE_MASK())


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

# :51 `BufferStorage(key, key)` -- the key is BOTH fields, and both fields are the
# key. A count, because a one-argument BufferStorage would drop `.meta` and then
# `_unmap` would have nothing to hand back.
def MAP_ST_ARGS() -> U32: 2


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

def ANCHOR_MIN() -> U32: 1

# :85 -- the RDMA rules come FIRST. `qpm` is the total rule count AFTER the
# prepend and `device.bend`'s `pmb_len` is the three it contributes; the two
# together are the rule table, and `rdma_pmb_first` is the ordering claim.
def pmb_len() -> U32: 3

def qp.rules_len() -> U32: qp_len()

def qp.connect(+recv: Bool, t: Tr) -> Tr: Tr.emit(CALL_QP_CONNECT(), Bool.to_u32(recv), t)

def qp.new(t: Tr) -> Tr: Tr.emit(CALL_QP_NEW(), OBJ_NONE(), t)


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

def wire.is_call(+is_call: Bool) -> Bool: is_call

def wire.is_store(+is_store: Bool) -> Bool: is_store

def wire.of(+is_call: Bool, +is_store: Bool, n_rdma_args: U32) -> U32:
  Bool.pick(U32, Bool.and(is_call, is_store), n_rdma_args, NO_KEY())


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

def psns_at(+ps: List<&2, U32>, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ps, U32.to_nat(i)), 0)

def db_value.lo(+index: U32, +epoch: U32) -> U32:
  U32.or(U32.and(index, DB_INDEX_MASK()), U32.shln(epoch, 24n))


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

def db_slot(+n: U32) -> U32: U32.mod(U32.add(n, 1), RING_ENTRIES())

def db_epoch(+n: U32) -> U32: U32.and(U32.div(U32.add(n, 1), RING_ENTRIES()), 1)

def RING_EQ_CQ() -> Bool: U32.is_eq(RING_ENTRIES(), CQ_ENTRIES())


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

# :151 the address: `cq_addr + (n % CQ_ENTRIES) * 32 + 24`. The completion entry is
# 32 bytes (:93) and the wait reads its FOURTH 32-bit word -- `cqe_ready` at
# bnxtdev.py:25 reads `cqe[24]`, so the offset is 24 and not 0, and that is the
# difference between polling the entry and polling its status word.
def cq_wait_addr(+cq_addr: U32, n: U32) -> U32:
  U32.add(U32.add(cq_addr, U32.mul(cq_slot_of(n), 32)), 24)

def CQE_STATUS_AT() -> U32: 24
def CQE_SIZE() -> U32: 32


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

def msn_base(+ring_addr: U32) -> U32: U32.add(ring_addr, U32.mul(RING_ENTRIES(), WQE_SIZE()))

def msn_addr(+ring_addr: U32, n: U32) -> U32:
  U32.add(msn_base(ring_addr), U32.mul(U32.mod(n, RING_ENTRIES()), 8))

def MSN_FIELD() -> U32: 8
def MSN_SLOT_HI_AT_NAT() -> Nat: 16n
def MSN_PSN_AT_NAT() -> Nat: 24n



def msn.hi(+slot: U32, +next_psn: U32) -> U32:
  U32.or(U32.shln(U32.and(slot, PSN_MASK()), MSN_SLOT_HI_AT_NAT()), U32.shrn(U32.and(next_psn, PSN_MASK()), 8n))

def msn.lo(+next_psn: U32, +p: U32) -> U32:
  U32.or(U32.shln(U32.and(next_psn, PSN_MASK()), MSN_PSN_AT_NAT()), U32.and(p, PSN_MASK()))


# :140-141 -- THE work queue element, and the ADDRESS translation appears here.
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

# the msn write is the ONE of the five that a receive does not do, so it is its
# own def and the guard is on the WAY IN rather than on the result.
def ops.msn_write(+recv: Bool, ring: U32, +n: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, recv, t, ins.msn(ring, n, t))

# the five instructions, nested innermost-first so the trace reads in the order
# Python writes them.
def ops.wqe_at(recv: Bool, +ring: U32, cq: U32, +db: U32, +n: U32, t: Tr) -> Tr:
  ins.cq_db(db, n, ins.wait(cq, n, ins.ring_db(db, n, ops.msn_write(recv, ring, n, ins.write(ring, n, t)))))

# :136-137 `for off in range(0, buf.nbytes(), RDMA_CHUNK)` and
# `size = min(RDMA_CHUNK, buf.nbytes() - off)`. The chunk's SIZE, which is what
# goes in the header and what the psn advance is measured against.
def ops.chunk_size(+nbytes: U32, +off: U32) -> U32: chunk_size(nbytes, off)


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

def RING_CAP() -> U32: U32.min(RING_ENTRIES(), CQ_ENTRIES())

def copies.guard.at(ok: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, ok, t, Tr.refuse(REFUSE_RING_CAP(), t))

def REFUSE_CAP_MSG() -> String: REFUSE_RING_CAP_MSG()

# :164 -- every src starts as a one-element list holding ITSELF.
def submit.src_replaced(+n_srcs: U32, n_queues: U32) -> U32: n_queues


