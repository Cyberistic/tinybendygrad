<!-- FROM: tinybendygrad/runtime/ops_rdma.bend:41 -->
# BLOCK:
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
# END BLOCK

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
