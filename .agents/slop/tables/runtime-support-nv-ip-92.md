<!-- FROM: tinybendygrad/runtime/support/nv/ip.bend:92 -->
# BLOCK:
# THE SEAMS, named with their Python lines. These are FFI, not logic.
#
#   * every `ctypes` struct construction, and `bytes(x)`: the field VALUES are
#     real ctypes writes into a real buffer. This port reproduces the layouts
#     (THE LAYOUTS) and the U32-representable field values, and the ctypes
#     marshalling itself is the seam.
#       # TODO(p3) support/nv/ip.py:39  symbol=_send_rpc_record  rpc_message_header_v(...)
#       # TODO(p3) support/nv/ip.py:43  symbol=_send_rpc_record  GSP_MSG_QUEUE_ELEMENT(...)
#       # TODO(p3) support/nv/ip.py:146  symbol=prep_ucode FWSECLIC_READ_VBIOS_DESC(...)
#       # TODO(p3) support/nv/ip.py:147  symbol=prep_ucode FWSECLIC_FRTS_REGION_DESC(...)
#       # TODO(p3) support/nv/ip.py:374  symbol=init_rm_args MESSAGE_QUEUE_INIT_ARGUMENTS(...)
#       # TODO(p3) support/nv/ip.py:394  symbol=init_libos_args LibosMemoryRegionInitArgument(...)
#       # TODO(p3) support/nv/ip.py:438  symbol=init_wpr_meta GspFwWprMeta(common, ...)
#       # TODO(p3) support/nv/ip.py:530 rpc_alloc_memory_v(...)
#       # TODO(p3) support/nv/ip.py:551  symbol=rpc_rm_alloc rpc_gsp_rm_alloc_v(...)
#       # TODO(p3) support/nv/ip.py:582  symbol=rpc_rm_control rpc_gsp_rm_control_v(...)
#       # TODO(p3) support/nv/ip.py:595  symbol=rpc_set_page_directory struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_...
#       # TODO(p3) support/nv/ip.py:597 rpc_set_page_directory_v(...)
#       # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info GspSystemInfo(...)
#       # TODO(p3) support/nv/ip.py:612 rpc_unloading_guest_driver_v(...)
#       # TODO(p3) support/nv/ip.py:622  symbol=rpc_set_registry_table PACKED_REGISTRY_ENTRY(...)
#       # TODO(p3) support/nv/ip.py:626  symbol=rpc_set_registry_table PACKED_REGISTRY_TABLE(...)
#
#   * the `/dev/nvidia*` fds and the `nvdev` register file. `nvdev.include(...)`
#     (:99-105), `nvdev.wreg`/`rreg` (:231,:637), every `NV_P*` register, the
#     `mmio` views (:111) and `_alloc_boot_mem` (:167) are device memory this
#     file cannot reach.
#       # TODO(p3) support/nv/ip.py:99   self.nvdev.include("dev_gsp", "ga102")
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  self.nvdev.mmio[0x300000//4:...]
#       # TODO(p3) support/nv/ip.py:167  symbol=__patch  self.nvdev._alloc_boot_mem(...)
#       # TODO(p3) support/nv/ip.py:199  symbol=init_hw  self.nvdev.NV_PGSP_FALCON_MAILBOX0.write
#
#   * `fetch_fw` (:174,:303,:402,:429) and `elf_loader` (:303) -- firmware
#     download and ELF parsing. The offsets read OUT of their results are
#     arithmetic and are ported (`prep_booter`, `init_gsp_image`,
#     `init_boot_binary_image`); the download and the parse are the seam.
#       # TODO(p3) support/nv/ip.py:174  symbol=prep_booter  fetch_fw(... "booter_load-570.144.bin" ...)
#       # TODO(p3) support/nv/ip.py:303  symbol=init_fmc_image  elf_loader(fetch_fw(... "fmc-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:402  symbol=init_gsp_image  elf_loader(fetch_fw(... "gsp-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:429  symbol=init_boot_binary_image  fetch_fw(... "bootloader-570.144.bin" ...)
#
#   * `wait_cond` (:22,:96,:213,:277,:288,:326,:640), `time.sleep` (:274,:641)
#     and `System.memory_barrier` (:52,:63,:78). `System.memory_barrier` IS a
#     trace call -- it is `C_BARRIER`, and its POSITION between the pointer store
#     and the doorbell is what `ip_tr_<i>_order` pins. `wait_resp` (:87-91) is a
#     trace call too (`C_WAIT_RESP`, then `C_RPC_RAISE` on the timeout). The
#     POLLING LOOPS are not: `wait_cond` and `time.sleep` are the seam, and no
#     trace tag claims to be either of them.
#       # TODO(p3) support/nv/ip.py:22  symbol=__init__   wait_cond(... "RPC queue not initialized")
#       # TODO(p3) support/nv/ip.py:52  symbol=_send_rpc_record   System.memory_barrier()  [PORTED: C_BARRIER]
#       # TODO(p3) support/nv/ip.py:274  time.sleep(0.1)
#       # TODO(p3) support/nv/ip.py:640  symbol=run_cpu_seq  wait_cond(lambda a, m: ...)
#
#   * the VBIOS scan (:110-143). It walks a firmware image with a
#     `match/case` over two code types and then walks three token tables; the
#     WALKS are over bytes this file does not have. The one thing ported is the
#     arithmetic that survives without the bytes -- `frts_offset` (:145),
#     `desc_v3` size arithmetic (tinygrad/runtime/support/nv/ip.py:139-143) -- and the refusal
#     at tinygrad/runtime/support/nv/ip.py:123 (`bit_header`).
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  the PCI expansion ROM walk
#       # TODO(p3) support/nv/ip.py:123  assert bit_header.Signature == 0x00544942
#
# THE WALLS. Three, and each is named with the line that owns it.
#
# 1. THE 64-BIT WALL, in three separate places, and they are not the same place.
#    `base.bend` exports no 64-bit integer, so:
#      - `GSP_FW_WPR_META_MAGIC` = 15869187694674993331 (:442). ONE of the 65
#        integer constants ip.py names does not fit a U32. `ip_c_over64` names
#        it; it is not ported, and the WPR meta builder records the field as the
#        seam's.
#      - `maxUserVa=0x7ffffffff000` (:608) and the four `gpuPhys*Addr` fields of
#        `GspSystemInfo` (:605). Their OFFSETS and WIDTHS are in the layout table
#        -- 8-byte fields at their byte offsets -- and their VALUES are the
#        seam's. `GspSystemInfo` is 48 fields and 928 bytes and the port knows
#        all of that.
#      - `_checksum` (:32-36) sums u64 words. This one is NOT a wall and the
#        reason is the whole reason the checksum gate is worth having: the
#        accumulator is a XOR and `hi32(x) ^ lo32(x)` COMMUTES with XOR over the
#        words, so the whole checksum collapses to two U32 folds over the
#        TWENTY U32 words of `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#        `rp.cksum.xor` does that, and it needs the byte OFFSETS -- so it fails
#        on a wrong field order and a wrong offset, which a count gate would not.
#        It does NOT fail on a wrong endianness, because XOR is commutative: the
#        mutation table records the exchange of `rp.pickw`'s arms as an equivalent
#        mutant, and the comment above `rp.pickw` says so where a reader needs it.
#
#    Two more 64-bit facts live where they bite rather than here, because each is
#    one arithmetic chain and not a type boundary:
#      - `init_wpr_meta` (:434-455) SUBTRACTS from `vram_size`, so every offset it
#        computes exceeds 2**32 for any real card. See THE FIXTURES beside
#        `wpr.leg4` and `ip_wpr_vram_max`.
#      - `id8=int.from_bytes(bytes(f"LOG{name}", 'utf-8'), 'big')` (:395) is an
#        EIGHT-BYTE name read big-endian. See the note beside `libos` and
#        `ip_libos_id8_bytes`.
#      # TODO(p3) support/nv/ip.py:442  symbol=init_wpr_meta  GSP_FW_WPR_META_MAGIC
#      # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info  GspSystemInfo.gpuPhysAddr / maxUserVa
#
# 2. THE DICT WALL, and it is a soft one. `self.chan_runlists` (:348),
#    `self.runlists` (:475), `self.grctx_bufs` (:501), `ctxbufs` (:457) and the
#    `table` in `rpc_set_registry_table` (:617) are Python dicts, so they are
#    INSERTION-ORDERED, and two of them are read with a MISS HANDLER that
#    returns a default (`self.runlists.get(..., 0)` :557,
#    `(bufs or {}).get(buf, ...) :461`). That site is upstream's `promote_ctx`
#    (tinygrad/runtime/support/nv/ip.py:457 symbol=promote_ctx), and the port's
#    `List` here is the same information
#    plus an explicit key list, and every miss is an explicit arm. What is lost
#    is dict ITERATION order under mutation, which none of these sites relies on.
#
# 3. THE GENERATOR WALL. `self.nvdev.include("dev_gsp", "ga102")` (:99-105)
#    pulls a device REGISTER MAP at run time, and that map is where
#    `NV_PFALCON_FALCON_DMATRFCMD_SIZE_256B`, `..._MEM_TYPE_PHYSICAL` and
#    `NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K` come from -- `autogen/nv_570.py`
#    is not enough for them. So those three constants are NOT PORTED here and
#    NOT in `nv_ip_tables.bend`: they belong to whoever ports `ops_nv.py`'s
#    register table, and `fl.dma_chunk` takes its bit positions as parameters
#    for exactly that reason.
#      # TODO(p3) support/nv/ip.py:242  symbol=execute_hs  NV_PFALCON_FALCON_DMATRFCMD.encode(...)
#      # TODO(p3) support/nv/ip.py:253  symbol=execute_hs  NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K
#      # TODO(p3) support/nv/ip.py:99   the register map `include` produces
#
# CTYPES SHAPING is not a wall and is named once: `(FALCON_APPLICATION_INTERFACE_ENTRY_V1
# * hdr.entryCount)(...)` at :156 spells "an array of n descriptors", so the
# layout of `FALCON_APPLICATION_INTERFACE_ENTRY_V1` is one row of the table and
# the array is a `List`. `memoryview(...).cast('I'/'Q')` (tinygrad/runtime/support/nv/ip.py:306) is the
# same statement about width.
#
# END BLOCK

# THE SEAMS, named with their Python lines. These are FFI, not logic.
#
#   * every `ctypes` struct construction, and `bytes(x)`: the field VALUES are
#     real ctypes writes into a real buffer. This port reproduces the layouts
#     (THE LAYOUTS) and the U32-representable field values, and the ctypes
#     marshalling itself is the seam.
#       # TODO(p3) support/nv/ip.py:39  symbol=_send_rpc_record  rpc_message_header_v(...)
#       # TODO(p3) support/nv/ip.py:43  symbol=_send_rpc_record  GSP_MSG_QUEUE_ELEMENT(...)
#       # TODO(p3) support/nv/ip.py:146  symbol=prep_ucode FWSECLIC_READ_VBIOS_DESC(...)
#       # TODO(p3) support/nv/ip.py:147  symbol=prep_ucode FWSECLIC_FRTS_REGION_DESC(...)
#       # TODO(p3) support/nv/ip.py:374  symbol=init_rm_args MESSAGE_QUEUE_INIT_ARGUMENTS(...)
#       # TODO(p3) support/nv/ip.py:394  symbol=init_libos_args LibosMemoryRegionInitArgument(...)
#       # TODO(p3) support/nv/ip.py:438  symbol=init_wpr_meta GspFwWprMeta(common, ...)
#       # TODO(p3) support/nv/ip.py:530 rpc_alloc_memory_v(...)
#       # TODO(p3) support/nv/ip.py:551  symbol=rpc_rm_alloc rpc_gsp_rm_alloc_v(...)
#       # TODO(p3) support/nv/ip.py:582  symbol=rpc_rm_control rpc_gsp_rm_control_v(...)
#       # TODO(p3) support/nv/ip.py:595  symbol=rpc_set_page_directory struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_...
#       # TODO(p3) support/nv/ip.py:597 rpc_set_page_directory_v(...)
#       # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info GspSystemInfo(...)
#       # TODO(p3) support/nv/ip.py:612 rpc_unloading_guest_driver_v(...)
#       # TODO(p3) support/nv/ip.py:622  symbol=rpc_set_registry_table PACKED_REGISTRY_ENTRY(...)
#       # TODO(p3) support/nv/ip.py:626  symbol=rpc_set_registry_table PACKED_REGISTRY_TABLE(...)
#
#   * the `/dev/nvidia*` fds and the `nvdev` register file. `nvdev.include(...)`
#     (:99-105), `nvdev.wreg`/`rreg` (:231,:637), every `NV_P*` register, the
#     `mmio` views (:111) and `_alloc_boot_mem` (:167) are device memory this
#     file cannot reach.
#       # TODO(p3) support/nv/ip.py:99   self.nvdev.include("dev_gsp", "ga102")
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  self.nvdev.mmio[0x300000//4:...]
#       # TODO(p3) support/nv/ip.py:167  symbol=__patch  self.nvdev._alloc_boot_mem(...)
#       # TODO(p3) support/nv/ip.py:199  symbol=init_hw  self.nvdev.NV_PGSP_FALCON_MAILBOX0.write
#
#   * `fetch_fw` (:174,:303,:402,:429) and `elf_loader` (:303) -- firmware
#     download and ELF parsing. The offsets read OUT of their results are
#     arithmetic and are ported (`prep_booter`, `init_gsp_image`,
#     `init_boot_binary_image`); the download and the parse are the seam.
#       # TODO(p3) support/nv/ip.py:174  symbol=prep_booter  fetch_fw(... "booter_load-570.144.bin" ...)
#       # TODO(p3) support/nv/ip.py:303  symbol=init_fmc_image  elf_loader(fetch_fw(... "fmc-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:402  symbol=init_gsp_image  elf_loader(fetch_fw(... "gsp-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:429  symbol=init_boot_binary_image  fetch_fw(... "bootloader-570.144.bin" ...)
#
#   * `wait_cond` (:22,:96,:213,:277,:288,:326,:640), `time.sleep` (:274,:641)
#     and `System.memory_barrier` (:52,:63,:78). `System.memory_barrier` IS a
#     trace call -- it is `C_BARRIER`, and its POSITION between the pointer store
#     and the doorbell is what `ip_tr_<i>_order` pins. `wait_resp` (:87-91) is a
#     trace call too (`C_WAIT_RESP`, then `C_RPC_RAISE` on the timeout). The
#     POLLING LOOPS are not: `wait_cond` and `time.sleep` are the seam, and no
#     trace tag claims to be either of them.
#       # TODO(p3) support/nv/ip.py:22  symbol=__init__   wait_cond(... "RPC queue not initialized")
#       # TODO(p3) support/nv/ip.py:52  symbol=_send_rpc_record   System.memory_barrier()  [PORTED: C_BARRIER]
#       # TODO(p3) support/nv/ip.py:274  time.sleep(0.1)
#       # TODO(p3) support/nv/ip.py:640  symbol=run_cpu_seq  wait_cond(lambda a, m: ...)
#
#   * the VBIOS scan (:110-143). It walks a firmware image with a
#     `match/case` over two code types and then walks three token tables; the
#     WALKS are over bytes this file does not have. The one thing ported is the
#     arithmetic that survives without the bytes -- `frts_offset` (:145),
#     `desc_v3` size arithmetic (tinygrad/runtime/support/nv/ip.py:139-143) -- and the refusal
#     at tinygrad/runtime/support/nv/ip.py:123 (`bit_header`).
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  the PCI expansion ROM walk
#       # TODO(p3) support/nv/ip.py:123  assert bit_header.Signature == 0x00544942
#
# THE WALLS. Three, and each is named with the line that owns it.
#
# 1. THE 64-BIT WALL, in three separate places, and they are not the same place.
#    `base.bend` exports no 64-bit integer, so:
#      - `GSP_FW_WPR_META_MAGIC` = 15869187694674993331 (:442). ONE of the 65
#        integer constants ip.py names does not fit a U32. `ip_c_over64` names
#        it; it is not ported, and the WPR meta builder records the field as the
#        seam's.
#      - `maxUserVa=0x7ffffffff000` (:608) and the four `gpuPhys*Addr` fields of
#        `GspSystemInfo` (:605). Their OFFSETS and WIDTHS are in the layout table
#        -- 8-byte fields at their byte offsets -- and their VALUES are the
#        seam's. `GspSystemInfo` is 48 fields and 928 bytes and the port knows
#        all of that.
#      - `_checksum` (:32-36) sums u64 words. This one is NOT a wall and the
#        reason is the whole reason the checksum gate is worth having: the
#        accumulator is a XOR and `hi32(x) ^ lo32(x)` COMMUTES with XOR over the
#        words, so the whole checksum collapses to two U32 folds over the
#        TWENTY U32 words of `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#        `rp.cksum.xor` does that, and it needs the byte OFFSETS -- so it fails
#        on a wrong field order and a wrong offset, which a count gate would not.
#        It does NOT fail on a wrong endianness, because XOR is commutative: the
#        mutation table records the exchange of `rp.pickw`'s arms as an equivalent
#        mutant, and the comment above `rp.pickw` says so where a reader needs it.
#
#    Two more 64-bit facts live where they bite rather than here, because each is
#    one arithmetic chain and not a type boundary:
#      - `init_wpr_meta` (:434-455) SUBTRACTS from `vram_size`, so every offset it
#        computes exceeds 2**32 for any real card. See THE FIXTURES beside
#        `wpr.leg4` and `ip_wpr_vram_max`.
#      - `id8=int.from_bytes(bytes(f"LOG{name}", 'utf-8'), 'big')` (:395) is an
#        EIGHT-BYTE name read big-endian. See the note beside `libos` and
#        `ip_libos_id8_bytes`.
#      # TODO(p3) support/nv/ip.py:442  symbol=init_wpr_meta  GSP_FW_WPR_META_MAGIC
#      # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info  GspSystemInfo.gpuPhysAddr / maxUserVa
#
# 2. THE DICT WALL, and it is a soft one. `self.chan_runlists` (:348),
#    `self.runlists` (:475), `self.grctx_bufs` (:501), `ctxbufs` (:457) and the
#    `table` in `rpc_set_registry_table` (:617) are Python dicts, so they are
#    INSERTION-ORDERED, and two of them are read with a MISS HANDLER that
#    returns a default (`self.runlists.get(..., 0)` :557,
#    `(bufs or {}).get(buf, ...) :461`). That site is upstream's `promote_ctx`
#    (tinygrad/runtime/support/nv/ip.py:457 symbol=promote_ctx), and the port's
#    `List` here is the same information
#    plus an explicit key list, and every miss is an explicit arm. What is lost
#    is dict ITERATION order under mutation, which none of these sites relies on.
#
# 3. THE GENERATOR WALL. `self.nvdev.include("dev_gsp", "ga102")` (:99-105)
#    pulls a device REGISTER MAP at run time, and that map is where
#    `NV_PFALCON_FALCON_DMATRFCMD_SIZE_256B`, `..._MEM_TYPE_PHYSICAL` and
#    `NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K` come from -- `autogen/nv_570.py`
#    is not enough for them. So those three constants are NOT PORTED here and
#    NOT in `nv_ip_tables.bend`: they belong to whoever ports `ops_nv.py`'s
#    register table, and `fl.dma_chunk` takes its bit positions as parameters
#    for exactly that reason.
#      # TODO(p3) support/nv/ip.py:242  symbol=execute_hs  NV_PFALCON_FALCON_DMATRFCMD.encode(...)
#      # TODO(p3) support/nv/ip.py:253  symbol=execute_hs  NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K
#      # TODO(p3) support/nv/ip.py:99   the register map `include` produces
#
# CTYPES SHAPING is not a wall and is named once: `(FALCON_APPLICATION_INTERFACE_ENTRY_V1
# * hdr.entryCount)(...)` at :156 spells "an array of n descriptors", so the
# layout of `FALCON_APPLICATION_INTERFACE_ENTRY_V1` is one row of the table and
# the array is a `List`. `memoryview(...).cast('I'/'Q')` (tinygrad/runtime/support/nv/ip.py:306) is the
# same statement about width.
#
