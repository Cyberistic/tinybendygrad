# tinybendygrad/runtime/support/am/amdev.bend -- port of tinygrad/runtime/support/am/amdev.py
#
# THE DEVICE SIDE OF `/dev/kfd`, which is NOT the /dev/kfd surface. `ops_amd.py:579-735`
# is the /dev/kfd one and `ops_amd.bend` records it as its WALL 1; what `amdev.py` is
# is the BAR, the REGISTER WINDOW and the FIRMWARE -- the `AMDev` the other file
# instantiates. `ops_amd.bend` records this file's part as its WALL 2 ("PCI / amdev",
# :737-804), and the four TODOs it lists for it are answered at the foot below.
#
# AND IT IS NOT MOSTLY FFI. 421 Python lines, of which the genuinely opaque part is
# `fetch_fw` (a download), the ctypes `from_address`/`from_buffer` marshalling, the
# `mmio`/`pci_dev` accesses and `wait_cond` -- all of which is a SEAM. What is left is
# the part that decides what the device is told, and that is what this file ports:
#
#   * the FIRMWARE DESCRIPTOR LADDER (:30-109) -- which ucode blocks are handed to the
#     PSP, at what OFFSET and what SIZE, in what ORDER, with which `GFX_FW_TYPE_*` id,
#     across the `header_version_major` and `header_version_minor` and `ip_ver` ladders.
#     A wrong entry here loads the wrong firmware: a silently wrong register write's
#     firmware analogue.
#   * the struct field lists, by name and in order (:33 :47 :57 :68 :86 :91 :365-395),
#     with their BYTE OFFSETS. This is the best gate in the project and the thing that
#     has repeatedly caught real bugs: `ops_cl`'s unit found `Sig`'s field names
#     INVERTED, which made a correct computation look wrong.
#   * the DISCOVERY WALK (:356-397) -- the die/IP nesting, the `ip_offset` stride
#     (8 + 8-or-4 per base address), the `hw_id_map` gate, and the HARVEST table parse.
#   * (tinygrad/runtime/support/am/amdev.py:402 symbol=hwid_names) `hwid_names` and
#     (tinygrad/runtime/support/am/amdev.py:382 symbol=_run_discovery) `hw_id_map` -- TWO-WAY TABLES, both directions.
#   * the REGISTER ARITHMETIC that is 64-BIT and therefore where a `U32` would be a
#     silently wrong register write: `indirect_wreg_pcie`'s `1 << 34` (tinygrad/runtime/support/am/amdev.py:342 symbol=indirect_wreg_pcie) and
#     `rlcg_rw`'s `(addr | 1<<28) << 32 | val` (:320), plus `ucode_start`'s `<< 32` (:82).
#   * the REQUEST TRACES -- the VF mailbox protocol (`_vf_mailbox_request`, tinygrad/runtime/support/am/amdev.py:268-281 symbol=_vf_mailbox_request),
#     `_read_vram` (tinygrad/runtime/support/am/amdev.py:349-357 symbol=_read_vram),
#     the ASPM capability walk (tinygrad/runtime/support/am/amdev.py:147-154 symbol=_disable_aspm) -- upstream's `_disable_aspm` --, `indirect_wreg`/`_pcie`, and the boot order.
#   * the AID ALIVE-MASK (:417-421), the palloc ladder (:233), the reserved-vram ladder
#     (:397) and the module ladder (:405-407).
#   * every REFUSAL, as a TRUNCATION of the trace.
#

# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind. That is what puts every `raise` and every `assert` into the trace: a
# refusal records NOTHING further, so it appears as a TRUNCATION and no step
# needs a guard of its own.
#
# This is the `ops_webgpu.bend` / `ip.bend` lane and the reason `--check-only`
# says ALL PROOFS CHECK with no foreign effect: the seam is `Tr.emit`, not a
# `def ... -> IO(R)` over two `import "./x.c"` lines.
#
# every constant and every `py=` expectation below came from CPYTHON, never from
# a header. The oracle is `.agents/slop/amdev_oracle.py` (1472 rows) with
# `.agents/slop/amdev_fw.py` and `.agents/slop/amdev_drv.py`, and it is STRONG
# rather than transcribed in the three places that matter:
#
#   * `AMFirmware.__init__` is INVOKED over synthetic-but-real ctypes images, so
#     the descriptor list, its order, its offsets, its sizes and its
#     `GFX_FW_TYPE_*` ids are amdev.py's own output. The `load_fw` class
#     selection (:116) is amdev.py's own `getattr` off the image's common header.
#   * `AMDev._disable_aspm`, `_read_vram`, `indirect_rreg`, `indirect_wreg`,
#     `indirect_wreg_pcie`, `rlcg_rw` and `_vf_mailbox_request` are INVOKED with
#     a recording `self`, so those traces are amdev.py's own too.
#   * `AMDev._run_discovery` is INVOKED over a sparse vram holding a real
#     `struct_binary_header` / `struct_ip_discovery_header` / `struct_die_header` /
#     `struct_ip_v4`, so the ip_ver table, the base-address walk and the harvest
#     parse are amdev.py's own.
#
# IT ALREADY CAUGHT THREE THINGS, all in this file's own reading of itself:
#   * :67's `([('PFP',1),('ME',1)] if ip_ver[GC] >= (12,0,0) else []) + [('MEC',1)]`
#     loads MEC UNCONDITIONALLY; only PFP and ME are version-gated.
#   * the code arm at :78 reads `hdr.ucode_size_bytes`, which in
#     `struct_gfx_firmware_header_v2_0` is the struct's OWN member and NOT the
#     common header's -- a fixture that set only the common one yields a
#     ZERO-LENGTH descriptor, silently.
#   * tinygrad/runtime/support/am/amdev.py:364's window is `(10 << 10)` bytes -- upstream's `tmr_size` -- so a `table_list[].offset` past it
#     reads back as version 0_0 rather than as an error.
import ../../../helpers.bend as H

# THE CONSTANTS, and where each one was read.
# :162 `self.mmio[am.mmRCC_IOV_FUNC_IDENTIFIER] & 1` -- the VF bit.
def MMIOV_FUNC_IDENTIFIER() -> U32: 3557
# :163 the 2-byte mailbox view at the control register's byte offset.
def NV_MAIBOX_CONTROL_TRN_OFFSET_BYTE() -> U32: 14712
# :272 `self.mmio[am.mmMAILBOX_MSGBUF_TRN_DW0 + i]` for i in 0..3.
def MAILBOX_MSGBUF_TRN_DW0() -> U32: 3670
# :278 `self.mmio[am.mmMAILBOX_MSGBUF_RCV_DW0]`.
def MAILBOX_MSGBUF_RCV_DW0() -> U32: 3674
# :164/:257/:266-267 the two mailbox requests, and :279 the READY the PF writes.
def IDH_REQ_GPU_INIT_ACCESS() -> U32: 1
def IDH_REQ_GPU_FINI_ACCESS() -> U32: 3
def IDH_READY_TO_ACCESS_GPU() -> U32: 1
# :271/:275 the three `wait_cond` timeouts, in ms.
def MAILBOX_CLEAR_MS() -> U32: 1000
def MAILBOX_ACK_TIMEDOUT() -> U32: 500
def MAILBOX_MSG_TIMEDOUT() -> U32: 15000
# :131/:133 the two PTE bits, and :135/:136 the two level ids.
def AMDGPU_PTE_VALID() -> U32: 1
def AMDGPU_PTE_SYSTEM() -> U32: 2
def AMDGPU_VM_PTB() -> U32: 3
def AMDGPU_VM_PDB2() -> U32: 0
# :366/:389/:395 the three table ids, and the four signatures of :367/:390.
def IP_DISCOVERY() -> U32: 0
def HARVEST_INFO() -> U32: 2
def GC() -> U32: 1
def BINARY_SIGNATURE() -> U32: 673256455
def DISCOVERY_TABLE_SIGNATURE() -> U32: 1396985929
def HARVEST_TABLE_SIGNATURE() -> U32: 1448231240
# :379 `for hw_ip in range(1, am.MAX_HWIP)` -- the UPPER bound, exclusive.
def MAX_HWIP() -> U32: 35
#
# amdev.py:387 -- "HARV(EST) table: harvested instances must be excluded (like
# amdgpu_discovery_harvest_ip)". A HARVESTED INSTANCE IS ONE THE SILICON DOES
# NOT HAVE: the manufacturer disabled it, and the discovery table still
# DESCRIBES it. So the harvest table's presence in the blob is what says which
# described instances are real, and anything the table names must be EXCLUDED
# from the live set. Upstream's parenthetical names the equivalent in the
# kernel driver -- `amdgpu_discovery_harvest_ip` -- so this is the same
# convention as the kernel's, not a tinygrad invention.
# amdev.py:388 -- "layout: u32 signature, u16 version, u16 size, then 32 entries
# of {hw_id:u16, inst:u8, rsv:u8}". THE ENTRY IS A PACKED WORD and the port's
# `HARVEST_BYTES` (136 = 8 + 32*4) is that layout: an eight-byte header (the
# signature and the version/size pair) and THIRTY-TWO four-byte entries. Each
# entry carries the HARDWARE ID in its low sixteen bits and the INSTANCE in the
# next eight, and the hw_id is looked up in the INVERSE of `hw_id_map` -- so
# the harvest table names instances by hw_id and the discovery names them by
# hw_ip, and the inverse is what joins them.
# the HWIP ids :380 indexes `hw_id_map` with, and :405-407 names modules by.
def MP0_HWIP() -> U32: 15
def MP1_HWIP() -> U32: 16
def GC_HWIP() -> U32: 1
def HDP_HWIP() -> U32: 2
def MMHUB_HWIP() -> U32: 12
def OSSSYS_HWIP() -> U32: 23
def NBIO_HWIP() -> U32: 14
def SDMA0_HWIP() -> U32: 3
# :194/:205 the PCIe command register and its bus-master bit.
def PCI_COMMAND() -> U32: 4
def PCI_COMMAND_MASTER() -> U32: 4
# :145 `AMDev.Version`, written to regSCRATCH_REG7 at :222 and read at :183/:189.
def AMDEV_VERSION() -> U32: 2684354573
# :359 the one FIXED discovery register -- "query memory size without known ip
# bases", :357. It is a local, not a `am` constant.
#
# amdev.py:358 -- "NOTE: Fixed register to query memory size without known ip
# bases to find the discovery table." THE CHICKEN-AND-EGG IS EXPLICIT: the
# discovery table's LOCATION depends on the memory size, and the memory size
# has to be read from a register whose ADDRESS would normally come from the
# discovery table. So one register is FIXED -- a constant address, not one
# computed from a base -- and it breaks the cycle. The port's
# `MMRCC_CONFIG_MEMSIZE` is that constant, and the fact that it is a LOCAL
# (`mmRCC_CONFIG_MEMSIZE = 0xde3`, a local in `_run_discovery`) rather than an
# `am` enum member is upstream's own statement that it is not part of the IP
# discovery tables.
def MMRCC_CONFIG_MEMSIZE() -> U32: 3555
# :362 `tmr_offset, tmr_size = self.vram_size - (64 << 10), (10 << 10)`.
def TMR_OFF_KB() -> U32: 64
def TMR_SZ_KB() -> U32: 10
# :360 `<< 20` -- the memory size is in MiB.
def VRAM_SHIFT() -> U32: 20
# :232 the MemoryManager's seven literal arguments.
def VA_BITS() -> U32: 48
def BOOT_SIZE() -> U32: 3145728
# :397 the two reserved-vram sizes.
def RESERVED_BIG() -> U32: 402653184
def RESERVED_SMALL() -> U32: 67108864
# :128/:134 `paddr & 0x0000FFFFFFFFF000` -- 52 address bits, so a U32 cannot hold
# the value this masks TO and `set_entry` writes an I64.
def PTE_ADDR_MASK_LO() -> U32: 4294963200
def PTE_ADDR_MASK_HI() -> U32: 65535
# :352 the VRAM window's `(caddr & 0x7FFFFFFF) | 0x80000000` and its :351/:353 peers.
def VRAM_WIN_FLAG() -> U32: 2147483648
def VRAM_WIN_MASK() -> U32: 2147483647
def RREG_LO() -> U32: 0
def RREG_HI() -> U32: 6
def RREG_DATA() -> U32: 1
# :53 the walrus target `__P2S_TABLE_ID_X:=0x50325358`, matched against
# `p2stable.id`.
def P2S_TABLE_ID_X() -> U32: 1345475416
# :150/:151/:154 the ASPM capability walk.
def ASPM_CAP0() -> U32: 52
def ASPM_MASK() -> U32: 252
def ASPM_LINK_CAP() -> U32: 16
def ASPM_LNKCTL() -> U32: 16
def ASPM_LNKCTL_MASK() -> U32: 4294967292
# :320 `0x1 << 28 if read else 0`, :322's poll mask and :324's error mask.
def RLCG_READ_BIT() -> U32: 1
def RLCG_READ_SHIFT() -> U32: 28
def RLCG_RSV_MASK() -> U32: 1048575
def RLCG_ERR_MASK() -> U32: 251658240
# :341 `((aid & 0b11) << 32) | (1 << 34)`, and :343's `& 0xff`.
def PCIE_AID_MASK() -> U32: 3
def PCIE_AID_SHIFT() -> U32: 32
def PCIE_EXT_SHIFT() -> U32: 34
def PCIE_HI_MASK() -> U32: 255
# :348/:350 the `_read_vram` alignment and step.
def VRAM_WIN_STEP() -> U32: 4
# :390 `8 + 32*4` and the 32 entries of the harvest table.
def HARVEST_BYTES() -> U32: 136
def HARVEST_ENTS() -> U32: 32
# :417-421 the AID alive-mask set, and :419's group width.
def AID_ALIVE_F() -> U32: 15
def AID_ALIVE_3() -> U32: 3
def AID_ALIVE_C() -> U32: 12
def AID_GROUP() -> U32: 4
# :272 `(req, 0, 0, 0)` -- the mailbox word count.
def MAILBOX_NWORDS() -> Nat: 4n
# :125-126 `AddrSpace.SYS` / `AddrSpace.PHYS`, and :136's `lv >=` on them.
def ADDRSPACE_SYS() -> U32: 2
def ADDRSPACE_PHYS() -> U32: 1
# :231 `[12, 21, 30, 39]`, and the :233 palloc top level (PDB2 is 0, so `9*(3-0)`).
def VA_SHIFT0() -> U32: 12
def VA_SHIFT1() -> U32: 21
def VA_SHIFT2() -> U32: 30
def VA_SHIFT3() -> U32: 39
def PALLOC_NLV() -> U32: 27
def PALLOC_LEN() -> Nat: 28n
def PALLOC_BIG_I() -> U32: 9
def PALLOC_SMALL() -> U32: 4096
def PALLOC_BIG() -> U32: 2097152

# the struct field lists, by name and in order, with their byte offsets.
# `names` is `_real_fields_`; `offs` is the generator's own `register_fields`,
# which lists the SCALAR members ONLY -- a nested struct or an array is in the
# first list and not the second, and the scalars are INTERSPERSED among those
# rather than gathered at the front. So the load-bearing claim is that
# `onnames` is `names` FILTERED to the scalars, in order, and `offs` rises
# strictly: that is what says the layout is packed in declaration order, and
# an INVERTED list breaks it while a field COUNT would not.
# :33 :47 :57 :68 :86 :91 -- load_fw's version probe and every image's first member
def sf.common_firmware_header.names() -> List<&2, String>: ["size_bytes", "header_size_bytes", "header_version_major", "header_version_minor", "ip_version_major", "ip_version_minor", "ucode_version", "ucode_size_bytes", "ucode_array_offset_bytes", "crc32"]
def sf.common_firmware_header.offs() -> List<&2, U32>: [0, 4, 8, 10, 12, 14, 16, 20, 24, 28]
def sf.common_firmware_header.onnames() -> List<&2, String>: ["size_bytes", "header_size_bytes", "header_version_major", "header_version_minor", "ip_version_major", "ip_version_minor", "ucode_version", "ucode_size_bytes", "ucode_array_offset_bytes", "crc32"]
def sf.common_firmware_header.n() -> U32: 10
def sf.common_firmware_header.nscalar() -> U32: 10
def sf.common_firmware_header.size() -> U32: 32
def sf.common_firmware_header.maxoff() -> U32: 28

# :365 the discovery image's root; table_list is indexed by IP_DISCOVERY/HARVEST_INFO/GC
def sf.binary_header.names() -> List<&2, String>: ["binary_signature", "version_major", "version_minor", "binary_checksum", "binary_size", "table_list"]
def sf.binary_header.offs() -> List<&2, U32>: [0, 4, 6, 8, 10]
def sf.binary_header.onnames() -> List<&2, String>: ["binary_signature", "version_major", "version_minor", "binary_checksum", "binary_size"]
def sf.binary_header.n() -> U32: 6
def sf.binary_header.nscalar() -> U32: 5
def sf.binary_header.size() -> U32: 60
def sf.binary_header.maxoff() -> U32: 10

# :366 :372 :375 the die walk and the base_addr_64_bit flag that sets the stride
def sf.ip_discovery_header.names() -> List<&2, String>: ["signature", "version", "size", "id", "num_dies", "die_info", "padding", "base_addr_64_bit", "reserved", "reserved2"]
def sf.ip_discovery_header.offs() -> List<&2, U32>: [0, 4, 6, 8, 12, 79]
def sf.ip_discovery_header.onnames() -> List<&2, String>: ["signature", "version", "size", "id", "num_dies", "reserved2"]
def sf.ip_discovery_header.n() -> U32: 10
def sf.ip_discovery_header.nscalar() -> U32: 6
def sf.ip_discovery_header.size() -> U32: 80
def sf.ip_discovery_header.maxoff() -> U32: 79

# :373 :375 the per-die IP count, and the size that starts the IP array
def sf.die_header.names() -> List<&2, String>: ["die_id", "num_ips"]
def sf.die_header.offs() -> List<&2, U32>: [0, 2]
def sf.die_header.onnames() -> List<&2, String>: ["die_id", "num_ips"]
def sf.die_header.n() -> U32: 2
def sf.die_header.nscalar() -> U32: 2
def sf.die_header.size() -> U32: 4
def sf.die_header.maxoff() -> U32: 2

# :377 :380 :382 ONE discovered IP: its hw_id, its instance, and its (major,minor,revision)
def sf.ip_v4.names() -> List<&2, String>: ["hw_id", "instance_number", "num_base_address", "major", "minor", "revision"]
def sf.ip_v4.offs() -> List<&2, U32>: [0, 2, 3, 4, 5, 6]
def sf.ip_v4.onnames() -> List<&2, String>: ["hw_id", "instance_number", "num_base_address", "major", "minor", "revision"]
def sf.ip_v4.n() -> U32: 6
def sf.ip_v4.nscalar() -> U32: 6
def sf.ip_v4.size() -> U32: 7
def sf.ip_v4.maxoff() -> U32: 6

# :395-396 the GC table, re-read as struct_gc_info_v{major}_{minor}
def sf.gc_info_v1_0.names() -> List<&2, String>: ["header", "gc_num_se", "gc_num_wgp0_per_sa", "gc_num_wgp1_per_sa", "gc_num_rb_per_se", "gc_num_gl2c", "gc_num_gprs", "gc_num_max_gs_thds", "gc_gs_table_depth", "gc_gsprim_buff_depth", "gc_parameter_cache_depth", "gc_double_offchip_lds_buffer", "gc_wave_size", "gc_max_waves_per_simd", "gc_max_scratch_slots_per_cu", "gc_lds_size", "gc_num_sc_per_se", "gc_num_sa_per_se", "gc_num_packer_per_sc", "gc_num_gl2a"]
def sf.gc_info_v1_0.offs() -> List<&2, U32>: [0, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72, 76, 80, 84]
def sf.gc_info_v1_0.onnames() -> List<&2, String>: ["header", "gc_num_se", "gc_num_wgp0_per_sa", "gc_num_wgp1_per_sa", "gc_num_rb_per_se", "gc_num_gl2c", "gc_num_gprs", "gc_num_max_gs_thds", "gc_gs_table_depth", "gc_gsprim_buff_depth", "gc_parameter_cache_depth", "gc_double_offchip_lds_buffer", "gc_wave_size", "gc_max_waves_per_simd", "gc_max_scratch_slots_per_cu", "gc_lds_size", "gc_num_sc_per_se", "gc_num_sa_per_se", "gc_num_packer_per_sc", "gc_num_gl2a"]
def sf.gc_info_v1_0.n() -> U32: 20
def sf.gc_info_v1_0.nscalar() -> U32: 20
def sf.gc_info_v1_0.size() -> U32: 88
def sf.gc_info_v1_0.maxoff() -> U32: 84

# :37 ONE entry of the SOS bin array; the four members are read at :38-39
def sf.psp_fw_bin_desc.names() -> List<&2, String>: ["fw_type", "fw_version", "offset_bytes", "size_bytes"]
def sf.psp_fw_bin_desc.offs() -> List<&2, U32>: [0, 4, 8, 12]
def sf.psp_fw_bin_desc.onnames() -> List<&2, String>: ["fw_type", "fw_version", "offset_bytes", "size_bytes"]
def sf.psp_fw_bin_desc.n() -> U32: 4
def sf.psp_fw_bin_desc.nscalar() -> U32: 4
def sf.psp_fw_bin_desc.size() -> U32: 16
def sf.psp_fw_bin_desc.maxoff() -> U32: 12

# :51 one soft-pptable entry; :53 matches `id` against the P2S magic
def sf.smc_soft_pptable_entry.names() -> List<&2, String>: ["id", "ppt_offset_bytes", "ppt_size_bytes"]
def sf.smc_soft_pptable_entry.offs() -> List<&2, U32>: [0, 4, 8]
def sf.smc_soft_pptable_entry.onnames() -> List<&2, String>: ["id", "ppt_offset_bytes", "ppt_size_bytes"]
def sf.smc_soft_pptable_entry.n() -> U32: 3
def sf.smc_soft_pptable_entry.nscalar() -> U32: 3
def sf.smc_soft_pptable_entry.size() -> U32: 12
def sf.smc_soft_pptable_entry.maxoff() -> U32: 8

# :33-36 psp_fw_bin_count and, when header_version_minor == 1, psp_aux_fw_bin_index
def sf.psp_firmware_v2_1.names() -> List<&2, String>: ["header", "psp_fw_bin_count", "psp_aux_fw_bin_index", "psp_fw_bin"]
def sf.psp_firmware_v2_1.offs() -> List<&2, U32>: [0, 32, 36]
def sf.psp_firmware_v2_1.onnames() -> List<&2, String>: ["header", "psp_fw_bin_count", "psp_aux_fw_bin_index"]
def sf.psp_firmware_v2_1.n() -> U32: 4
def sf.psp_firmware_v2_1.nscalar() -> U32: 3
def sf.psp_firmware_v2_1.size() -> U32: 56
def sf.psp_firmware_v2_1.maxoff() -> U32: 36

# :47-51 pptable_count and pptable_entry_offset; the v1_0 prefix is at 0
def sf.smc_firmware_v2_1.names() -> List<&2, String>: ["v1_0", "pptable_count", "pptable_entry_offset"]
def sf.smc_firmware_v2_1.offs() -> List<&2, U32>: [0, 36, 40]
def sf.smc_firmware_v2_1.onnames() -> List<&2, String>: ["v1_0", "pptable_count", "pptable_entry_offset"]
def sf.smc_firmware_v2_1.n() -> U32: 3
def sf.smc_firmware_v2_1.nscalar() -> U32: 3
def sf.smc_firmware_v2_1.size() -> U32: 44
def sf.smc_firmware_v2_1.maxoff() -> U32: 40

# :57-60 the v1 arm: header.ucode_array_offset_bytes and header.ucode_size_bytes
def sf.sdma_firmware_v1_0.names() -> List<&2, String>: ["header", "ucode_feature_version", "ucode_change_version", "jt_offset", "jt_size"]
def sf.sdma_firmware_v1_0.offs() -> List<&2, U32>: [0, 32, 36, 40, 44]
def sf.sdma_firmware_v1_0.onnames() -> List<&2, String>: ["header", "ucode_feature_version", "ucode_change_version", "jt_offset", "jt_size"]
def sf.sdma_firmware_v1_0.n() -> U32: 5
def sf.sdma_firmware_v1_0.nscalar() -> U32: 5
def sf.sdma_firmware_v1_0.size() -> U32: 48
def sf.sdma_firmware_v1_0.maxoff() -> U32: 44

# :62-63 the v2 arm: ctl_ucode_offset/size THEN ctx_ucode_size_bytes, both the struct's OWN members
def sf.sdma_firmware_v2_0.names() -> List<&2, String>: ["header", "ucode_feature_version", "ctx_ucode_size_bytes", "ctx_jt_offset", "ctx_jt_size", "ctl_ucode_offset", "ctl_ucode_size_bytes", "ctl_jt_offset", "ctl_jt_size"]
def sf.sdma_firmware_v2_0.offs() -> List<&2, U32>: [0, 32, 36, 40, 44, 48, 52, 56, 60]
def sf.sdma_firmware_v2_0.onnames() -> List<&2, String>: ["header", "ucode_feature_version", "ctx_ucode_size_bytes", "ctx_jt_offset", "ctx_jt_size", "ctl_ucode_offset", "ctl_ucode_size_bytes", "ctl_jt_offset", "ctl_jt_size"]
def sf.sdma_firmware_v2_0.n() -> U32: 9
def sf.sdma_firmware_v2_0.nscalar() -> U32: 9
def sf.sdma_firmware_v2_0.size() -> U32: 64
def sf.sdma_firmware_v2_0.maxoff() -> U32: 60

# :68-75 the v1 arm: ucode_size_bytes - jt_size*4 for code, then ucode_off + jt_offset*4 for JT
def sf.gfx_firmware_v1_0.names() -> List<&2, String>: ["header", "ucode_feature_version", "jt_offset", "jt_size"]
def sf.gfx_firmware_v1_0.offs() -> List<&2, U32>: [0, 32, 36, 40]
def sf.gfx_firmware_v1_0.onnames() -> List<&2, String>: ["header", "ucode_feature_version", "jt_offset", "jt_size"]
def sf.gfx_firmware_v1_0.n() -> U32: 4
def sf.gfx_firmware_v1_0.nscalar() -> U32: 4
def sf.gfx_firmware_v1_0.size() -> U32: 44
def sf.gfx_firmware_v1_0.maxoff() -> U32: 40

# :78-82 the v2 arm: its OWN ucode_size_bytes, data_offset/size, and the 64-bit ucode_start_addr
def sf.gfx_firmware_v2_0.names() -> List<&2, String>: ["header", "ucode_feature_version", "ucode_size_bytes", "ucode_offset_bytes", "data_size_bytes", "data_offset_bytes", "ucode_start_addr_lo", "ucode_start_addr_hi"]
def sf.gfx_firmware_v2_0.offs() -> List<&2, U32>: [0, 32, 36, 40, 44, 48, 52, 56]
def sf.gfx_firmware_v2_0.onnames() -> List<&2, String>: ["header", "ucode_feature_version", "ucode_size_bytes", "ucode_offset_bytes", "data_size_bytes", "data_offset_bytes", "ucode_start_addr_lo", "ucode_start_addr_hi"]
def sf.gfx_firmware_v2_0.n() -> U32: 8
def sf.gfx_firmware_v2_0.nscalar() -> U32: 8
def sf.gfx_firmware_v2_0.size() -> U32: 60
def sf.gfx_firmware_v2_0.maxoff() -> U32: 56

# :86-88 IMU_I at iram and IMU_D at iram_offset + iram_size
def sf.imu_firmware_v1_0.names() -> List<&2, String>: ["header", "imu_iram_ucode_size_bytes", "imu_iram_ucode_offset_bytes", "imu_dram_ucode_size_bytes", "imu_dram_ucode_offset_bytes"]
def sf.imu_firmware_v1_0.offs() -> List<&2, U32>: [0, 32, 36, 40, 44]
def sf.imu_firmware_v1_0.onnames() -> List<&2, String>: ["header", "imu_iram_ucode_size_bytes", "imu_iram_ucode_offset_bytes", "imu_dram_ucode_size_bytes", "imu_dram_ucode_offset_bytes"]
def sf.imu_firmware_v1_0.n() -> U32: 5
def sf.imu_firmware_v1_0.nscalar() -> U32: 5
def sf.imu_firmware_v1_0.size() -> U32: 48
def sf.imu_firmware_v1_0.maxoff() -> U32: 44

# :95-97 the three LIST_SRM_CNTL/LIST_GPM_MEM/LIST_SRM_MEM save-restore pairs
def sf.rlc_firmware_v2_1.names() -> List<&2, String>: ["v2_0", "reg_list_format_direct_reg_list_length", "save_restore_list_cntl_ucode_ver", "save_restore_list_cntl_feature_ver", "save_restore_list_cntl_size_bytes", "save_restore_list_cntl_offset_bytes", "save_restore_list_gpm_ucode_ver", "save_restore_list_gpm_feature_ver", "save_restore_list_gpm_size_bytes", "save_restore_list_gpm_offset_bytes", "save_restore_list_srm_ucode_ver", "save_restore_list_srm_feature_ver", "save_restore_list_srm_size_bytes", "save_restore_list_srm_offset_bytes"]
def sf.rlc_firmware_v2_1.offs() -> List<&2, U32>: [0, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 148, 152]
def sf.rlc_firmware_v2_1.onnames() -> List<&2, String>: ["v2_0", "reg_list_format_direct_reg_list_length", "save_restore_list_cntl_ucode_ver", "save_restore_list_cntl_feature_ver", "save_restore_list_cntl_size_bytes", "save_restore_list_cntl_offset_bytes", "save_restore_list_gpm_ucode_ver", "save_restore_list_gpm_feature_ver", "save_restore_list_gpm_size_bytes", "save_restore_list_gpm_offset_bytes", "save_restore_list_srm_ucode_ver", "save_restore_list_srm_feature_ver", "save_restore_list_srm_size_bytes", "save_restore_list_srm_offset_bytes"]
def sf.rlc_firmware_v2_1.n() -> U32: 14
def sf.rlc_firmware_v2_1.nscalar() -> U32: 14
def sf.rlc_firmware_v2_1.size() -> U32: 156
def sf.rlc_firmware_v2_1.maxoff() -> U32: 152

# :100-101 the IRAM and DRAM_BOOT pairs
def sf.rlc_firmware_v2_2.names() -> List<&2, String>: ["v2_1", "rlc_iram_ucode_size_bytes", "rlc_iram_ucode_offset_bytes", "rlc_dram_ucode_size_bytes", "rlc_dram_ucode_offset_bytes"]
def sf.rlc_firmware_v2_2.offs() -> List<&2, U32>: [0, 156, 160, 164, 168]
def sf.rlc_firmware_v2_2.onnames() -> List<&2, String>: ["v2_1", "rlc_iram_ucode_size_bytes", "rlc_iram_ucode_offset_bytes", "rlc_dram_ucode_size_bytes", "rlc_dram_ucode_offset_bytes"]
def sf.rlc_firmware_v2_2.n() -> U32: 5
def sf.rlc_firmware_v2_2.nscalar() -> U32: 5
def sf.rlc_firmware_v2_2.size() -> U32: 172
def sf.rlc_firmware_v2_2.maxoff() -> U32: 168

# :104-107 the P and V pairs
def sf.rlc_firmware_v2_3.names() -> List<&2, String>: ["v2_2", "rlcp_ucode_version", "rlcp_ucode_feature_version", "rlcp_ucode_size_bytes", "rlcp_ucode_offset_bytes", "rlcv_ucode_version", "rlcv_ucode_feature_version", "rlcv_ucode_size_bytes", "rlcv_ucode_offset_bytes"]
def sf.rlc_firmware_v2_3.offs() -> List<&2, U32>: [0, 172, 176, 180, 184, 188, 192, 196, 200]
def sf.rlc_firmware_v2_3.onnames() -> List<&2, String>: ["v2_2", "rlcp_ucode_version", "rlcp_ucode_feature_version", "rlcp_ucode_size_bytes", "rlcp_ucode_offset_bytes", "rlcv_ucode_version", "rlcv_ucode_feature_version", "rlcv_ucode_size_bytes", "rlcv_ucode_offset_bytes"]
def sf.rlc_firmware_v2_3.n() -> U32: 9
def sf.rlc_firmware_v2_3.nscalar() -> U32: 9
def sf.rlc_firmware_v2_3.size() -> U32: 204
def sf.rlc_firmware_v2_3.maxoff() -> U32: 200

# `hwid_names` (:400) is `{v: k.removesuffix('_HWID') ...}`, a value -> NAME
# table, and :382 never uses it -- so the port carries the reverse name ->
# value too, because a firmware blob's hw_id is a VALUE and a diagnostic's
# is a name. the collision is the point: uvd_hwid and vcn_hwid are both 12,
# so the comprehension DROPS UVD, and `hwid_names` has 77 entries for 78 keys.
def hwid.names() -> List<&2, String>: ["MP1", "MP2", "THM", "SMUIO", "FUSE", "CLKA", "PWR", "GC", "UVD", "VCN", "AUDIO_AZ", "ACP", "DCI", "DMU", "DCO", "DIO", "XDMA", "DCEAZ", "DAZ", "SDPMUX", "NTB", "VPE", "IOHC", "L2IMU", "VCE", "MMHUB", "ATHUB", "DBGU_NBIO", "DFX", "DBGU0", "DBGU1", "OSSSYS", "HDP", "SDMA0", "SDMA1", "ISP", "DBGU_IO", "DF", "CLKB", "FCH", "DFX_DAP", "L1IMU_PCIE", "L1IMU_NBIF", "L1IMU_IOAGR", "L1IMU3", "L1IMU4", "L1IMU5", "L1IMU6", "L1IMU7", "L1IMU8", "L1IMU9", "L1IMU10", "L1IMU11", "L1IMU12", "L1IMU13", "L1IMU14", "L1IMU15", "WAFLC", "FCH_USB_PD", "SDMA2", "SDMA3", "PCIE", "PCS", "DDCL", "SST", "LSDMA", "IOAGR", "NBIF", "IOAPIC", "SYSTEMHUB", "NTBCCP", "UMC", "SATA", "USB", "CCXSEC", "XGMI", "XGBE", "MP0"]
def hwid.vals() -> List<&2, U32>: [1, 2, 3, 4, 5, 6, 10, 11, 12, 12, 13, 14, 15, 271, 16, 272, 17, 18, 274, 19, 20, 21, 24, 28, 32, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 80, 89, 90, 91, 100, 108, 124, 128, 144, 150, 168, 170, 176, 200, 216, 255]
def hwid.nkeys() -> U32: 78
def hwid.ndistinct() -> U32: 77
def hwid.ncollision() -> U32: 1
def hwid.collision() -> U32: 12
def hwid.collision_names() -> List<&2, String>: ["UVD", "VCN"]

# `hw_id_map` (:380) is hw_ip -> hw_id and is read as `am.hw_id_map[hw_ip]
# == ip.hw_id`. :391 builds its INVERSE for the harvest table, and 108 is in
# BOTH 14 (NBIO) and 26 (NBIF), so the inverse's 108 is whichever comes last.
def hwip.hwips() -> List<&2, U32>: [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 32, 33, 34]
def hwip.ids() -> List<&2, U32>: [11, 41, 42, 43, 68, 69, 91, 34, 35, 108, 255, 1, 12, 32, 21, 46, 271, 40, 4, 10, 108, 3, 6, 150, 200, 15, 70, 44]
def hwip.n() -> U32: 28
def hwip.inv_n() -> U32: 27
def hwip.inv_108() -> U32: 26
def hwip.dupvals() -> List<&2, U32>: [108]
def hwip.max() -> U32: 34
def hwip.in_range() -> U32: 28

# THE VERSION LADDER. :46 `!=`, :48/:85 `>= (11,0,0)`, :67/:406 `>= (12,0,0)`
# and `(13,0,12)`, :407 `in {(4,4,2), (4,4,4)}`, :397 `[:2] in {(9,4), (9,5)}`.
# A version is THREE `U32`, never a packed word: `ops_amd`'s agent found
# `dev_max_copy` comparing a three-part COMPONENTWISE where ops_amd.py:880
# compares LEXICOGRAPHICALLY, and three of its eight fixtures disagreed.
# THE TAIL. `(an,ax) >= (bn,bx)` is decided by the second components when the
# first agree, so `ge3` never has to hold two triples at once and no parameter is
# read twice.
def v.ge2(+an: U32, +ax: U32, +bn: U32, +bx: U32) -> Bool:
  Bool.or(U32.is_gt(an, bn), Bool.and(U32.is_eq(an, bn), U32.is_ge(ax, bx)))

def v.ge3(+am: U32, +an: U32, +ax: U32, +bm: U32, +bn: U32, +bx: U32) -> Bool:
  Bool.or(U32.is_gt(am, bm), Bool.and(U32.is_eq(am, bm), v.ge2(an, ax, bn, bx)))

# `a < b` is the negation of `>=` and NOT a separate compare: the order is total,
# so the two agree on every input, and there is no third case to get wrong.
def v.lt3(am: U32, an: U32, ax: U32, bm: U32, bn: U32, bx: U32) -> Bool:
  Bool.not(v.ge3(am, an, ax, bm, bn, bx))

def v.eq3(am: U32, an: U32, ax: U32, bm: U32, bn: U32, bx: U32) -> Bool:
  Bool.and(Bool.and(U32.is_eq(am, bm), U32.is_eq(an, bn)), U32.is_eq(ax, bx))

def v.ne3(am: U32, an: U32, ax: U32, bm: U32, bn: U32, bx: U32) -> Bool:
  Bool.not(v.eq3(am, an, ax, bm, bn, bx))

def v.p2_is(+a: U32, +b: U32, x: U32, y: U32) -> Bool:
  Bool.and(U32.is_eq(a, x), U32.is_eq(b, y))

# :397 `self.ip_ver[am.GC_HWIP][:2] in {(9,4), (9,5)}` -- the ONLY compare in the
# file that throws the revision away, and it is the one that decides whether the
# device reserves 384MB or 64MB.
def v.p2_in_94_95(+maj: U32, +min: U32) -> Bool:
  Bool.or(v.p2_is(maj, min, 9, 4), v.p2_is(maj, min, 9, 5))

# :28 `'_'.join(map(str, adev.ip_ver[hwip]))` -- the FILENAME the blob is keyed by.
# `fmt_ver` is what makes `psp_11_0_0_sos.bin` out of (11,0,0), and a wrong
# separator makes `load_fw` fetch a blob that does not exist.
def v.fmt2(+maj: U32, +min: U32) -> String:
  String.concat([U32.show(maj), "_", U32.show(min)])

def v.fmt3(+maj: U32, +min: U32, +rev: U32) -> String:
  String.concat([U32.show(maj), "_", U32.show(min), "_", U32.show(rev)])

# :397's ladder, as a number, so the row is a VALUE and not a boolean.
def v.reserved(maj: U32, min: U32, rev: U32) -> U32:
  Bool.pick(U32, v.p2_in_94_95(maj, min), RESERVED_BIG(), RESERVED_SMALL())

# THE TRACE. `Tr.emit` is the seam: every register access, every config read and
# write, every mailbox store and every poll in this file goes through it, so the
# trace is the ordered list of hardware the seam will perform.
#
# FOUR FIELDS, not ip.bend's two. A `read_config` is (op, addr, WIDTH) and a
# `write_config` is (op, addr, WIDTH, VALUE); with two fields the width is lost
# and the ASPM walk's `read_config(cap + 0x10, 2)` becomes indistinguishable from
# the 1-byte reads it is surrounded by, which is the whole difference between the
# three-read walk and the four-event one. `ip.bend` has no config reads and no
# widths, so `b` could be 0 there -- the shapes are compatible, not competing.
#
# THE RAISE. `Tr.emit` records NOTHING once a refusal has fired, so a refusal
# shows up in the trace as a TRUNCATION and no step below needs a guard of its
# own. `Tr.refuse` is idempotent after the first, and `nth`/`at` let one fixture
# numbering reach EVERY refusal site in turn.

type Call is Data:
  Call{k: U32, a: U32, b: U32, c: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, refused: Bool, nth: U32, at: U32}

def Tr.of() -> Tr: Tr{Nil{}, False{}, 0, 0}
def Tr.of.at(n: U32) -> Tr: Tr{Nil{}, False{}, 0, n}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, refused, nth, at}: calls

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, refused, nth, at}: refused

def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, refused, nth, at}: Tr{calls, refused, nth, n}

def Tr.here(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

def Tr.emit.go(+refused: Bool, k: U32, a: U32, b: U32, c: U32, +calls: List<&2, Call>,
               nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
    List.append(&2, Call, calls, [Call{k, a, b, c}])), refused, nth, at}

def Tr.emit(k: U32, a: U32, b: U32, c: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +refused, nth, at}: Tr.emit.go(refused, k, a, b, c, calls, nth, at)

# THE RAISE. Records nothing, and is idempotent after the first.
def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
    Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, +refused, +nth, +at}: Tr.refuse.go(refused, nth, at)

# THE OPERATIONS. Each is one FFI call, and the id is what the gate matches on.

def OP_CFG_RD() -> U32: 0
def OP_CFG_WR() -> U32: 1
def OP_MB_RD() -> U32: 2
def OP_MB_WR() -> U32: 3
def OP_MM_RD() -> U32: 4
def OP_MM_WR() -> U32: 5
def OP_WREG() -> U32: 6
def OP_RREG() -> U32: 7
def OP_PAIR_LO() -> U32: 8
def OP_PAIR_HI() -> U32: 9
def OP_REG_WR() -> U32: 10
def OP_REG_RD() -> U32: 11
def OP_WAIT() -> U32: 12

# the registers the trace names. A register is a NAME in amdev.py and an index
# here, and the index is the trace's whole identity -- which is why the table is
# ordered by the SOURCE line that first mentions each one.
# :316 the two GRBM gateway selection registers.
def REG_GRBM_GFX_CNTL() -> U32: 0
def REG_GRBM_GFX_INDEX() -> U32: 1
# :322/:326 the two scratch registers the gateway answers through.
def REG_SCRATCH_REG0() -> U32: 2
def REG_SCRATCH_REG1() -> U32: 3
# :317 the two scratch registers the GRBM shortcut selects between.
def REG_SCRATCH_REG2() -> U32: 4
def REG_SCRATCH_REG3() -> U32: 5
# :321 the spare interrupt that kicks the gateway.
def REG_RLC_SPARE_INT() -> U32: 6
# :333/:337 the indirect index/data pair.
def REG_RSMU_INDEX() -> U32: 7
def REG_RSMU_DATA() -> U32: 8
# :342-345 the PCIe indirect index/data pair and its high half.
def REG_PCIE_INDEX2() -> U32: 9
def REG_PCIE_INDEX2_HI() -> U32: 10
def REG_PCIE_DATA2() -> U32: 11

def Tr.rd_cfg(addr: U32, size: U32, t: Tr) -> Tr: Tr.emit(OP_CFG_RD(), addr, size, 0, t)
def Tr.wr_cfg(addr: U32, size: U32, val: U32, t: Tr) -> Tr: Tr.emit(OP_CFG_WR(), addr, size, val, t)
def Tr.mb_rd(slot: U32, t: Tr) -> Tr: Tr.emit(OP_MB_RD(), slot, 0, 0, t)
def Tr.mb_wr(slot: U32, val: U32, t: Tr) -> Tr: Tr.emit(OP_MB_WR(), slot, 0, val, t)
def Tr.mm_rd(addr: U32, t: Tr) -> Tr: Tr.emit(OP_MM_RD(), addr, 4, 0, t)
def Tr.mm_wr(addr: U32, val: U32, t: Tr) -> Tr: Tr.emit(OP_MM_WR(), addr, 4, val, t)
def Tr.wreg(reg: U32, val: U32, t: Tr) -> Tr: Tr.emit(OP_WREG(), reg, 4, val, t)
def Tr.rreg(reg: U32, t: Tr) -> Tr: Tr.emit(OP_RREG(), reg, 4, 0, t)
def Tr.pair(slot: U32, val: U32, t: Tr) -> Tr: Tr.emit(Bool.pick(U32, U32.is_eq(slot, 0), OP_PAIR_LO(), OP_PAIR_HI()), 0, 4, val, t)
def Tr.reg_wr(reg: U32, val: U32, t: Tr) -> Tr: Tr.emit(OP_REG_WR(), reg, 4, val, t)
def Tr.reg_rd(reg: U32, t: Tr) -> Tr: Tr.emit(OP_REG_RD(), reg, 4, 0, t)
def Tr.wait(value: U32, tmo: U32, t: Tr) -> Tr: Tr.emit(OP_WAIT(), value, tmo, 0, t)

# `wait_cond`'s PREDICATE is a hardware read, and it happens BEFORE the poll:
# `wait_cond(lambda: self.vf_mailbox[0] & 2, ...)` reads the mailbox and
# `wait_cond(lambda: self.mmio[RCV_DW0], ...)` reads the mmio window. A trace
# that omits them is one entry short per poll, and :275's `& 2` is the only
# reason the read is safe to make before the answer arrives.
def mb.poll_mask() -> U32: 2
def mb.poll(slot: U32, mm: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, mm, Tr.mm_rd(MAILBOX_MSGBUF_RCV_DW0(), t), Tr.mb_rd(slot, t))

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, a, b, c}: k

def Call.a(c: Call) -> U32:
  match c:
    case Call{k, a, b, c}: a

def Call.b(c: Call) -> U32:
  match c:
    case Call{k, a, b, c}: b

def Call.c(c: Call) -> U32:
  match c:
    case Call{k, a, b, c}: c

# READING THE TRACE. `Tr.count` is how many entries carry a tag, `Tr.n` is how
# many there are AT ALL -- and the second is the TRUNCATION LENGTH a refusal
# shows up as. `Tr.seq` is a real subsequence test, with the matcher fuel set to
# the TRACE length: ops_webgpu's M23 measured that setting it to the PATTERN
# length makes it answer True to everything, which left eight order rows
# decorative.

def Tr.n(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa, bb, cc} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# the entries' `a`, in order, for one tag -- the ADDRESSES, which is what the
# `_read_vram` window and the ASPM chain are made of.
def Tr.addrs.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa, bb, cc} <> t: Tr.addrs.go(m, k, t,
          Bool.pick(List<&2, U32>, U32.is_eq(kk, k),
            List.append(&2, U32, acc, [aa]), acc))

def Tr.addrs(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.addrs.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.vals.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa, bb, cc} <> t: Tr.vals.go(m, k, t,
          Bool.pick(List<&2, U32>, U32.is_eq(kk, k),
            List.append(&2, U32, acc, [cc]), acc))

def Tr.vals(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.vals.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.sizes.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa, bb, cc} <> t: Tr.sizes.go(m, k, t,
          Bool.pick(List<&2, U32>, U32.is_eq(kk, k),
            List.append(&2, U32, acc, [bb]), acc))

def Tr.sizes(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.sizes.go(List.length(&2, Call, cs), k, cs, Nil{})

# THE MATCHER. Both fields are compared, so a pattern pins the IDENTITY of each
# entry and not only its kind, and the fuel is the TRACE length.
def Tr.seq.step.same(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.seq.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.seq.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.seq.step.hit(Tr.seq.step.same(Call.k(c), Call.k(want), Call.a(c), Call.a(want)), at)

def Tr.seq.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa, bb, cc} <> t:
          Tr.seq.go(m, patlen, t, pat, Tr.seq.step(List.get(&2, Call, pat, at), Call{kk, aa, bb, cc}, at))

def Tr.seq(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.seq.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

# `:147-154` `_disable_aspm` -- THE PCI CAPABILITY WALK. The one loop in this
# file that is bounded by something other than a counter: `seen` exists because
# "a dead link can return 0xff pointers forever" (:150).
#
# THE UPSTREAM WHY OF THE WHOLE ROUTINE, kept because the routine's NAME says
# what it does and the comment says WHY IT IS SAFE TO DO AT ALL:
#   amdev.py:148 -- "L1 across retimers makes reads oscillate to 0xffffffff;
#   power on defaults it enabled." ASPM is a POWER STATE, and the specific
#   failure is a RETIMER: a retimer is a redriver on the PCIe link and its L1
#   (link idle) handling makes READS OSCILLATE -- a read comes back as
#   0xffffffff some of the time and the right value other times. That is a
#   DATA CORRUPTION failure, not a power failure, so ASPM is disabled for a
#   correctness reason and not for a battery reason.
#   amdev.py:149 -- "Clearing the GPU endpoint alone suffices: L1 only engages
#   when both ends of the link enable it." THE WALK IS SYMMETRIC AND THE WRITE
#   IS NOT: the hardware only enters L1 when BOTH ends enable it, so clearing
#   the GPU's side is ENOUGH and the peer's side need not be touched. That is
#   why the routine walks the capability chain on the GPU side only and writes
#   once, at the end.
#
# The walk is `cap, seen = read_config(0x34, 1) & 0xfc, set()` then
# `while cap and cap not in seen and read_config(cap, 1) != 0x10`, whose body
# sets `cap = read_config(cap + 1, 1) & 0xfc`. The values `read_config` answers
# are the SEAM's, so the fixture supplies them as two parallel lists: `links` is
# what `read_config(cap, 1)` says and `nexts` is what `read_config(cap + 1, 1)`
# says. `Tr.count(OP_CFG_RD(), ...)` is what the trace reads back.
# `:147-154` `_disable_aspm` -- THE PCI CAPABILITY WALK, and the one loop in
# this file bounded by something other than a counter. `seen` exists because
# "a dead link can return 0xff pointers forever" (:150), and it is the reason
# the walk has a STATE rather than a count.
#
#   cap, seen = self.pci_dev.read_config(0x34, 1) & 0xfc, set()
#   while cap and cap not in seen and self.pci_dev.read_config(cap, 1) != 0x10:
#     seen.add(cap)
#     cap = self.pci_dev.read_config(cap + 1, 1) & 0xfc
#   if cap and cap not in seen:
#     self.pci_dev.write_config_flush(cap + 0x10, self.pci_dev.read_config(cap + 0x10, 2) & ~3, 2)
#
# The values `read_config` answers are the SEAM's, so the fixture supplies them as
# two parallel lists: `links` is what `read_config(cap, 1)` says and `nexts` is
# what `read_config(cap + 1, 1)` says. The port walks those and emits the reads.
# `seen` membership. A dead chain repeats a cap, and this is what stops it.
def aspm.seen.go(n: Nat, +c: U32, cs: List<&2, U32>, hit: Bool) -> Bool:
  match n:
    case 0n: hit
    case 1n+m:
      match cs:
        case Nil{}: hit
        case h <> t: aspm.seen.go(m, c, t, Bool.or(hit, U32.is_eq(h, c)))

def aspm.seen(c: U32, +cs: List<&2, U32>) -> Bool:
  aspm.seen.go(List.length(&2, U32, cs), c, cs, False{})

def aspm.seen_add(+seen: List<&2, U32>, cap: U32) -> List<&2, U32>:
  List.append(&2, U32, seen, [cap])

# the seam's answer at step `i`; 0 once the fixture runs out.
def aspm.at(+xs: List<&2, U32>, +i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, i), 0)

# THE CONDITION, left to right: `cap` non-zero, then `cap not in seen`, then the
# LINK CAPABILITY read. This is the WHOLE of :151's condition.
def aspm.more(+links: List<&2, U32>, +seen: List<&2, U32>, +cap: U32, i: Nat) -> Bool:
  Bool.and(Bool.and(U32.is_ne(cap, 0), Bool.not(aspm.seen(cap, seen))),
    U32.is_ne(aspm.at(links, i), ASPM_LINK_CAP()))

# the three things the body does, each gated by the condition. a `Bool.pick`
# selects a VALUE and both arms are evaluated, which is exactly right here: the
# trace IS a value, so `rd_cfg(cap,1, rd_cfg(cap+1,1,t))` costs nothing when the
# walk is over -- the branch is not taken, the extra `Tr` is simply discarded.
# `cap` is the decreasing argument, so `advance` must leave it alone when the walk
# stops, and that is the whole difference between the two fixtures.
def aspm.take(+seen: List<&2, U32>, more: Bool, +cap: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, more, aspm.seen_add(seen, cap), seen)

def aspm.advance(+nexts: List<&2, U32>, more: Bool, +cap: U32, i: Nat) -> U32:
  Bool.pick(U32, more, U32.and(aspm.at(nexts, i), ASPM_MASK()), cap)

# PYTHON SHORT-CIRCUITS. `while cap and cap not in seen and
# read_config(cap, 1) != 0x10` -- the read is the THIRD conjunct, so when `cap` is
# zero or already seen the register is NEVER read. The first version emitted the
# probe unconditionally and answered four reads where CPython answers three; the
# gate caught it on `ama_aspm_chain_n`. So the two tests that guard the read are
# SEPARATE from the test that guards the body.
def aspm.pre(+links: List<&2, U32>, +seen: List<&2, U32>, +cap: U32, i: Nat) -> Bool:
  Bool.and(U32.is_ne(cap, 0), Bool.not(aspm.seen(cap, seen)))

def aspm.probe(+nexts: List<&2, U32>, pre: Bool, more: Bool, +cap: U32, i: Nat, +t: Tr) -> Tr:
  # THE ORDER IS cap THEN cap + 1, and `Bool.pick`'s arm is a VALUE, so the
  # `cap + 1` read is built first and lands LAST in the trace. Getting that
  # backwards is invisible whenever `more` is false -- `ama_aspm_link` reads one
  # address per probe -- and shows up only on `ama_aspm_chain`, which is exactly
  # the fixture that has two reads in one step.
  # `List.append(xs, [x])` is `xs ++ [x]`, and the INNER call is evaluated first, so
  # the argument that reads LAST must be the OUTER one. `cap` is therefore the
  # inner read and `cap + 1` the outer, which is the reverse of the obvious
  # spelling and is why `ama_aspm_chain` -- the only fixture with two reads in one
  # step -- is the only row that sees it.
  Bool.pick(Tr, pre, Bool.pick(Tr, more,
    Tr.rd_cfg(U32.add(cap, 1), 1, Tr.rd_cfg(cap, 1, t)),
    Tr.rd_cfg(cap, 1, t)), t)

# THE WALK. `fuel` is the only countdown and it is the FIRST parameter. The
# `seen` list GROWS, so it is a later argument than `cap` -- the order the
# decrease check accepts (bend2-constraints "1922").
#
# THE FUEL IS THE PROBE COUNT, and that is a fact about the fixture rather than an
# approximation: `links`/`nexts` are the seam's answers, so the fixture supplies
# one entry per probe and the last one FAILS the condition -- which is what makes
# Python's `while` stop there. Running out of fuel mid-walk is the seam giving up,
# and `Go` below records the cap at which it did.
def aspm.go(fuel: Nat, +links: List<&2, U32>, +nexts: List<&2, U32>, +seen: List<&2, U32>,
            +cap: U32, +i: Nat, +t: Tr) -> Go:
  match fuel:
    case 0n: Go{cap, seen, t}
    case 1n+m:
      +pre = aspm.pre(links, seen, cap, i)
      +more = aspm.more(links, seen, cap, i)
      aspm.go(m, links, nexts, aspm.take(seen, more, cap),
        aspm.advance(nexts, more, cap, i), Nat.add(i, 1n),
        aspm.probe(nexts, pre, more, cap, i, t))

# THE RESULT: where the walk stopped, what it saw on the way, and the trace.
# `cap == 0` is not a special case -- it is just a cap, and :154's guard reads it.
# `seen` rides along because the FINAL guard needs it and a self-call cannot hand
# back two things.
type Go is Data:
  Go{cap: U32, seen: List<&2, U32>, t: Tr}

# THE FINAL WRITE (:154), guarded by `cap and cap not in seen`. A chain that ran to
# `cap == 0` writes NOTHING, and `aspm_link` versus `aspm_chain` is that guard --
# not the walk, which both fixtures run to the same depth.
# :154 `self.pci_dev.write_config_flush(cap + 0x10,
# self.pci_dev.read_config(cap + 0x10, 2) & ~3, 2)`. The `& ~3` CLEARS THE TWO
# ASPM bits and writes everything else back; writing the mask itself would clear
# every other bit of Link Control, which is a different and much larger bug, so
# the port masks the register's OWN value. `raw` is the seam's answer and the mask
# is :154's -- the first version wrote the mask itself and the gate caught it
# because `ama_aspm_link_val_0` answered 4294967292 instead of 65532.
def aspm.flush(g: Go, raw: U32) -> Tr:
  match g:
    case Go{+cap, +seen, +t}:
      Bool.pick(Tr, Bool.and(U32.is_ne(cap, 0), Bool.not(aspm.seen(cap, seen))),
        Tr.wr_cfg(U32.add(cap, ASPM_LNKCTL()), 2, U32.and(raw, ASPM_LNKCTL_MASK()),
          Tr.rd_cfg(U32.add(cap, ASPM_LNKCTL()), 2, t)),
        t)

def aspm.cap_of(g: Go) -> U32:
  match g:
    case Go{cap, seen, t}: cap

def aspm.seen_of(+g: Go) -> List<&2, U32>:
  match g:
    case Go{cap, +seen, t}: seen

def aspm.t_of(g: Go) -> Tr:
  match g:
    case Go{cap, seen, +t}: t

# THE WHOLE OF `_disable_aspm`, in order: read the first cap, walk, then write.
# `aspm.flush` takes `Go` as a PARAMETER, which is the only place a `match` may
# scrutinise a record this file computed.
def aspm.walk(first: U32, +links: List<&2, U32>, +nexts: List<&2, U32>, raw: U32, t: Tr) -> Tr:
  aspm.flush(aspm.go(List.length(&2, U32, links), links, nexts, Nil{},
    U32.and(first, ASPM_MASK()), 0n, Tr.rd_cfg(ASPM_CAP0(), 1, t)), raw)

# `:268-281` `_vf_mailbox_request` -- THE MAILBOX PROTOCOL, and the most
# order-sensitive thing in the file. A VF may only touch engines inside an access
# window (:255), so the sequence IS the contract:
#
#   vf_mailbox[0] = 0                                    # drop TRN_MSG_VALID
#   wait_cond(vf_mailbox[0] & 2, value=0, timeout_ms=1000, msg=...)
#   for i, val in enumerate((req, 0, 0, 0)): mmio[TRN_DW0 + i] = val
#   vf_mailbox[0] = 1                                    # set TRN_MSG_VALID
#   wait_cond(vf_mailbox[0] & 2, value=2, timeout_ms=NV_MAILBOX_POLL_ACK_TIMEDOUT, ...)
#   vf_mailbox[0] = 0
#   if wait_ready:
#     wait_cond(mmio[RCV_DW0], value=IDH_READY_TO_ACCESS_GPU, timeout_ms=NV_MAILBOX_POLL_MSG_TIMEDOUT, ...)
#     vf_mailbox[1] = 2                                 # ack
#   return req + 1
#
# Every one of the eleven (or nine) trace entries is a hardware store, and the
# FOUR MSGBUF words are a `(req, 0, 0, 0)` tuple at consecutive addresses -- which
# is why `mb_init` and `mb_norw` are both nine-plus-two and not the same length.
# THE FOUR WORDS :272 writes, as ADDRESSES: `MAILBOX_MSGBUF_TRN_DW0 + i` for
# i in 0..3. Walking the ADDRESS rather than the index is what lets the countdown
# be read once, and it is the same four words.
def mb.first() -> U32: MAILBOX_MSGBUF_TRN_DW0()
def mb.last() -> U32: U32.add(MAILBOX_MSGBUF_TRN_DW0(), 3)

# only the FIRST word carries the request, and that is the whole request
# encoding: `(req, 0, 0, 0)` is a tuple whose tail is constant.
def mb.word_of(req: U32, addr: U32) -> U32:
  Bool.pick(U32, U32.is_eq(addr, mb.first()), req, 0)

# THE FOUR MSGBUF STORES, in order, with the request in the first word. `i` is
# the NAT countdown -- the countdown IS the count, so there is no separate
# `range`, and :272's `enumerate` is exactly this.
# THE COUNTDOWN IS THE FIRST PARAMETER, so the decrease is found before the
# computed address -- a self-call with a computed argument in FRONT of the
# shrinking one is not decreasing, and the error is worth the reordering.
def mb.msgbuf(i: Nat, +req: U32, +addr: U32, +t: Tr) -> Tr:
  match i:
    case 0n: t
    case 1n+m: mb.msgbuf(m, req, U32.add(addr, 1), Tr.mm_wr(addr, mb.word_of(req, addr), t))

# THE PROTOCOL. `wait_ready` is a PARAMETER and not a branch, because the `if`
# at :277 selects a VALUE (the trace) rather than choosing a def to call.
# the POLL VALUE each `wait_cond` waits FOR, which is NOT always the mask: :271
# waits for `vf_mailbox[0] & 2` to be ZERO and :275 waits for it to be TWO.
def MB_WAIT_CLEAR() -> U32: 0
def MB_WAIT_ACK() -> U32: 2
def MB_WAIT_READY() -> U32: 1

# :276-280: `vf_mailbox[0] = 0` happens UNCONDITIONALLY, and only the ready wait and
# the `vf_mailbox[1] = 2` ack are behind `if wait_ready:`. So the FALSE arm is not
# "do nothing" -- it is the same `mb[0] = 0`, which is one entry and the whole
# difference between `amb_init_n` and `amb_norw_n`.
def mb.req(wait_ready: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, wait_ready,
    Tr.mb_wr(1, 2,
      Tr.wait(MB_WAIT_READY(), MAILBOX_MSG_TIMEDOUT(),
        mb.poll(0, True{}, Tr.mb_wr(0, 0, t)))),
    Tr.mb_wr(0, 0, t))

# THE WHOLE OF `_vf_mailbox_request`, in order.
def mb.request(+req: U32, wait_ready: Bool, +t: Tr) -> Tr:
  mb.msgbuf(MAILBOX_NWORDS(), req, mb.first(),
    mb.req(wait_ready,
      Tr.wait(MB_WAIT_ACK(), MAILBOX_ACK_TIMEDOUT(),
        Tr.mb_wr(0, 1,
          mb.poll(0, False{},
            Tr.mb_wr(0, 0,
              mb.poll(0, False{},
                Tr.wait(MB_WAIT_CLEAR(), MAILBOX_CLEAR_MS(), t))))))))

# :281 `return req + 1` -- the LEASE ID, and the value `release_vf_access`
# (:265) hands back so the PF recognises which window to close.
#
# amdev.py:254 -- "a VF may only touch the engines inside an access window, take
# one so the host does not have to FLR the VF later". THE ACCESS WINDOW IS A
# LEASE AND THE ALTERNATIVE IS A RESET. A Virtual Function may only touch the
# engines the PHYSICAL FUNCTION has handed it, and the PF hands out those
# engines as an ACCESS WINDOW -- a bounded set of engines the VF may drive.
# The alternative to taking a window is an FLR (Function Level Reset), which
# resets the WHOLE function and is the PF's way of taking the engines back
# when a VF misbehaves. So the window is taken UP FRONT: it is cheaper than
# resetting the VF later, and it is the reason `release_vf_access` exists to
# hand the lease back.
def mb.lease(req: U32) -> U32: U32.add(req, 1)

# `:347-354` `_read_vram`. The window protocol is a fixed 3-call sequence per
# four bytes -- `wreg(0x06, caddr >> 31)`, `wreg(0x00, (caddr & 0x7FFFFFFF) |
# 0x80000000)`, `rreg(0x01)` -- and the ASSERT is `addr % 4 == 0 and
# size % 4 == 0` (:348), which refuses BEFORE any word is read.

def rv.hi(caddr: U32) -> U32: U32.shrn(caddr, 31n)
def rv.lo(caddr: U32) -> U32: U32.or(U32.and(caddr, VRAM_WIN_MASK()), VRAM_WIN_FLAG())

# ONE WORD: the high half of the address, then the low half with the window bit
# set, then the data read. The ORDER of the first two is what selects the window,
# so swapping them silently reads the wrong half of VRAM.
def rv.word(+caddr: U32, t: Tr) -> Tr:
  Tr.rreg(RREG_DATA(), Tr.wreg(RREG_LO(), rv.lo(caddr), Tr.wreg(RREG_HI(), rv.hi(caddr), t)))

def rv.go(n: Nat, +caddr: U32, +t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m: rv.go(m, U32.add(caddr, VRAM_WIN_STEP()), rv.word(caddr, t))

# `for caddr in range(addr, addr + size, 4)`, and the refusal: `assert addr % 4 ==
# 0 and size % 4 == 0` truncates the trace, so a misaligned window reads NOTHING
# rather than reading a half word.
def rv.read(+addr: U32, +size: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, Bool.and(U32.is_eq(U32.and(addr, VRAM_WIN_STEP()), 0),
                         U32.is_eq(U32.and(size, VRAM_WIN_STEP()), 0)),
    rv.go(U32.to_nat(U32.div(size, VRAM_WIN_STEP())), addr, t),
    Tr.refuse(t))

# `:332-345` `indirect_rreg` / `indirect_wreg` / `indirect_wreg_pcie`. THE 64-BIT
# ONE. `indirect_wreg_pcie`'s index is
#
#   reg_addr = reg * 4 + ((((aid & 0b11) << 32) | (1 << 34)) if aid > 0 else 0)
#
# which for aid 2 is `0x4000_0006_48d0` -- above 2^32, so it is an `I64` and NOT a
# `U32`. `ops_amd`'s agent found exactly this class of bug in that file: the SQTT
# write pointer is `(raw & 0x1FFFFFFF) * 32`, up to 2^34, and the first version
# computed it in `U32` and WRAPPED. This one is the second instance of the same
# shape, and it is why the constant above is named.

def pc.has_aid(aid: U32) -> Bool: U32.is_gt(aid, 0)

# the INDEX the PCIe window computes, as its two words.
def pc.addr_hi(+reg: U32, +aid: U32) -> U32:
  # `1 << 34` IS NOT A `U32`: `U32.shln` saturates past 31 and answers 0, which is
  # how the first version of this row read 0 for every aid. The HIGH WORD carries
  # bit 34 as bit 2, so the shift is RELATIVE -- `PCIE_EXT_SHIFT() - PCIE_AID_SHIFT()`
  # -- and that difference is the whole of the 64-bit arithmetic here.
  Bool.pick(U32, pc.has_aid(aid),
    U32.or(U32.and(aid, PCIE_AID_MASK()),
      U32.shln(1, U32.to_nat(U32.sub(PCIE_EXT_SHIFT(), PCIE_AID_SHIFT())))), 0)

def pc.addr_lo(reg: U32, aid: U32) -> U32: U32.shln(reg, 2n)

def pc.has_hi(hi: U32) -> Bool: U32.is_gt(hi, 0)
def pc.mask_hi(hi: U32) -> U32: U32.and(hi, PCIE_HI_MASK())

# :342-345, IN ORDER. `INDEX2` low, `INDEX2_HI` (only when the high word is
# non-zero), `DATA2`, then `INDEX2_HI` back to ZERO. The last store is what makes
# the next access start clean, and dropping it is a silently wrong register write
# on the following call rather than a visible error here.
def pc.write(+reg: U32, +val: U32, +aid: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, pc.has_hi(pc.addr_hi(reg, aid)),
    Tr.reg_wr(REG_PCIE_INDEX2_HI(), 0,
      Tr.reg_wr(REG_PCIE_DATA2(), val,
        Tr.reg_wr(REG_PCIE_INDEX2_HI(), pc.mask_hi(pc.addr_hi(reg, aid)),
          Tr.reg_wr(REG_PCIE_INDEX2(), pc.addr_lo(reg, aid), t)))),
    Tr.reg_wr(REG_PCIE_DATA2(), val, Tr.reg_wr(REG_PCIE_INDEX2(), pc.addr_lo(reg, aid), t)))

# :333-338, the PF indirect window: `INDEX = reg * 4` then the DATA read/write.
def pc.index(reg: U32) -> U32: U32.shln(reg, 2n)

def pc.wreg(reg: U32, val: U32, t: Tr) -> Tr:
  Tr.reg_wr(REG_RSMU_DATA(), val, Tr.reg_wr(REG_RSMU_INDEX(), pc.index(reg), t))

# :333-334 `self.reg("regBIF_BX_PF0_RSMU_INDEX").write(reg * 4)` THEN
# `self.reg("regBIF_BX_PF0_RSMU_DATA").read()` -- the INDEX is written FIRST. The
# argument that reads LAST must therefore be the OUTER call, or the trace records
# the DATA read before the INDEX write.
def pc.rreg(reg: U32, t: Tr) -> Tr:
  Tr.reg_rd(REG_RSMU_DATA(), Tr.reg_wr(REG_RSMU_INDEX(), pc.index(reg), t))

def pc.rreg2(reg: U32, t: Tr) -> Tr:
  Tr.reg_rd(REG_RSMU_DATA(), Tr.reg_wr(REG_RSMU_INDEX(), pc.index(reg), t))

# `:314-326` `rlcg_rw` -- THE RLC GATEWAY. A register access on a VF goes
# through scratch registers instead of the MMIO window, and there are TWO paths:
#
#   if addr in {regGRBM_GFX_CNTL.addr[inst], regGRBM_GFX_INDEX.addr[inst]}:
#     reg(regSCRATCH_REG2 if CNTL else regSCRATCH_REG3).write(val, inst, direct=True)
#     return val
#   self.wreg_pair("regSCRATCH_REG", "0", "1",
#                  (addr | (0x1 << 28 if read else 0)) << 32 | val, inst, direct=True)
#   self.reg("regRLC_SPARE_INT").write(1, inst, direct=True)
#   wait_cond(regSCRATCH_REG1.read() & 0xFFFFF == 0, ...)
#   return regSCRATCH_REG0.read()
#
# The scratch word is 64 bits and `<< 32` is where a `U32` would wrap: for
# addr 0x1234 read, the high word is 0x10001234 -- bit 28 set -- which is the whole
# distinction between a read and a write.
# :316 `if addr in {self.reg("regGRBM_GFX_CNTL").addr[inst],
# self.reg("regGRBM_GFX_INDEX").addr[inst]}` -- the MEMBERSHIP is on the register's
# BASE address, and the two have DIFFERENT bases (CNTL at 0, INDEX one 64KB page
# up), so the enum ids cannot be the addresses. `rlcg.base_cntl`/`rlcg.base_index`
# are those bases and the rows below pin them against the oracle.
#
# amdev.py:316 -- "the rlc gateway takes the grbm selection through its own
# scratch registers". THE GRBM SELECTION IS A SEPARATE CONNECTION: the GRBM
# (Graphics Register Base Master) chooses WHICH graphics block a register
# access names, and on a VF that selection cannot go through the MMIO window --
# it goes through the RLC gateway's OWN scratch registers. So the two addresses
# in the membership test are the two GRBM CONTROL registers themselves
# (`regGRBM_GFX_CNTL` selects the block, `regGRBM_GFX_INDEX` selects the
# instance), and for those two the gateway writes the value STRAIGHT to
# `regSCRATCH_REG2`/`regSCRATCH_REG3` instead of going through the
# address/value pair.
def rlcg.base_cntl() -> U32: 0
def rlcg.base_index() -> U32: 65536

def rlcg.is_grbm(+addr: U32, +inst: U32) -> Bool:
  Bool.or(U32.is_eq(addr, U32.add(rlcg.base_cntl(), U32.shln(inst, 16n))),
          U32.is_eq(addr, U32.add(rlcg.base_index(), U32.shln(inst, 16n))))

def rlcg.scratch_of(+addr: U32, +inst: U32) -> U32:
  Bool.pick(U32, U32.is_eq(addr, U32.add(rlcg.base_cntl(), U32.shln(inst, 16n))),
    REG_SCRATCH_REG2(), REG_SCRATCH_REG3())

# the 64-bit scratch word: `(addr | (0x1 << 28 if read else 0)) << 32 | val`.
def rlcg.pair_hi(+addr: U32, read: Bool) -> U32:
  Bool.pick(U32, read, U32.or(addr, U32.shln(RLCG_READ_BIT(), U32.to_nat(RLCG_READ_SHIFT()))), addr)

# :320 `wreg_pair` writes the LOW word FIRST and then the HIGH word. The order is
# not visible in the result and is exactly the sort of thing a port gets wrong.
def rlcg.write(lo: U32, hi: U32, t: Tr) -> Tr: Tr.pair(1, hi, Tr.pair(0, lo, t))

# the whole gateway, in order. The `read` arm's high word carries bit 28 and the
# write arm's does not, and that single bit is the read/write distinction.
def rlcg.access(addr: U32, val: U32, read: Bool, t: Tr) -> Tr:
  rlcg.write(val, rlcg.pair_hi(addr, read), Tr.reg_rd(REG_SCRATCH_REG0(),
    Tr.wait(0, 0, Tr.reg_wr(REG_RLC_SPARE_INT(), 1, Tr.reg_rd(REG_RLC_SPARE_INT(), t)))))

# `:417-421` THE AID ALIVE-MASK. "Live AIDs like the kernel: 4 SDMAs per AID;
# the AID lives iff its group's alive-mask is 0xf/0x3/0xc. Dead AIDs must never
# be touched via the indirect window: writes poison the whole fabric" (:417-418).
#
#   live_sdma = {k for k in regs_offset[SDMA0_HWIP] if k not in harvested[SDMA0_HWIP]}
#   max_aid = max((k >> 2 for k in regs_offset[SDMA0_HWIP]), default=0)
#   self.aids = [0] + [aid for aid in range(1, max_aid+1)
#                     if sum(1 << (i & 3) for i in live_sdma if i >> 2 == aid) in {0xf,0x3,0xc}]
#
# The mask is a SUM of `1 << (i & 3)` over the LIVE instances in the group, so
# three numbers {0xf, 0x3, 0xc} decide liveness: all four, the low pair, or the
# outer pair. Everything else is harvested-and-still-present and must not be
# touched. `0` goes in unconditionally, and it is NOT a mask -- it is AID 0.
# `i & 3` is `i mod 4`, the instance's slot inside its AID's group of four.
def aid.slot(i: U32) -> U32: U32.and(i, 3)
def aid.of(i: U32) -> U32: U32.shrn(i, 2n)

# the four slots: `sum(1 << slot)` over which of them are live.
def AID_SLOT0() -> U32: 1
def AID_SLOT1() -> U32: 2
def AID_SLOT2() -> U32: 4
def AID_SLOT3() -> U32: 8

def aid.is_mask(m: U32, x: U32) -> Bool: U32.is_eq(m, x)

def aid.alive(+mask: U32) -> Bool:
  Bool.or(aid.is_mask(mask, AID_ALIVE_F()),
    Bool.or(aid.is_mask(mask, AID_ALIVE_3()), aid.is_mask(mask, AID_ALIVE_C())))

# ONE GROUP's mask: the sum over the four instances at `aid * 4 + slot`. The
# fixture supplies the four LIVE flags, so the row is about the mask arithmetic
# and the {0xf,0x3,0xc} test rather than about the walk.
def aid.mask(+live0: U32, +live1: U32, +live2: U32, +live3: U32) -> U32:
  U32.add(U32.add(Bool.pick(U32, U32.is_eq(live0, 1), AID_SLOT0(), 0),
    Bool.pick(U32, U32.is_eq(live1, 1), AID_SLOT1(), 0)),
    U32.add(Bool.pick(U32, U32.is_eq(live2, 1), AID_SLOT2(), 0),
      Bool.pick(U32, U32.is_eq(live3, 1), AID_SLOT3(), 0)))

# `max((k >> 2 for k in insts), default=0)`, and `default=0` is load-bearing: an
# SDMA block with NO instances yields 0, and then `range(1, 1)` is empty so the
# whole list is just `[0]`.
# the predicate is ITS OWN def, because `Bool.pick` needs the value on both
# sides and `U32.is_gt(acc, x)` would read `x` twice.
def aid.bigger(acc: U32, x: U32) -> Bool: U32.is_gt(acc, x)

def aid.max_better(+acc: U32, +x: U32) -> U32:
  Bool.pick(U32, aid.bigger(acc, x), acc, x)

def aid.max_aid.go(n: Nat, +insts: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match insts:
        case Nil{}: acc
        case i <> t: aid.max_aid.go(m, t, aid.max_better(acc, aid.of(i)))

def aid.max_aid(+insts: List<&2, U32>) -> U32:
  aid.max_aid.go(List.length(&2, U32, insts), insts, 0)

# THE LIST. `[0] + [aid for aid in range(1, max_aid+1) if alive(mask_of(aid))]`,
# and the leading `0` is unconditional -- AID 0 always exists, and the gate rows
# say so rather than leaving it implied.
# the four flags of group `aidn` are at `aidn * 4 + slot`, and `aidn * 4` is the
# BASE rather than the index -- which is why :419's `i & 3` and :421's `i >> 2`
# are inverses and not two independent things.
def aid.base(+aidn: U32) -> Nat: Nat.mul(U32.to_nat(aidn), 4n)
def aid.slot_at(aidn: U32, slot: U32) -> Nat: Nat.add(aid.base(aidn), U32.to_nat(slot))

def aid.of_group(+aidn: U32, +flags: List<&2, U32>) -> U32:
  aid.mask(aspm.at(flags, aid.slot_at(aidn, 0)), aspm.at(flags, aid.slot_at(aidn, 1)),
    aspm.at(flags, aid.slot_at(aidn, 2)), aspm.at(flags, aid.slot_at(aidn, 3)))

# THE KEEP TEST, as its own def: it reads `aidn` twice (the bound and the group),
# so `Bool.pick` cannot see it without a named predicate.
def aid.keep1(+aidn: U32, maxa: U32, +flags: List<&2, U32>) -> Bool:
  Bool.and(U32.is_le(aidn, maxa), aid.alive(aid.of_group(aidn, flags)))

def aid.keep(n: Nat, +aidn: U32, +maxa: U32, +flags: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: aid.keep(m, U32.add(aidn, 1), maxa, flags,
      Bool.pick(List<&2, U32>, aid.keep1(aidn, maxa, flags),
        List.append(&2, U32, acc, [aidn]), acc))

# `:405-407` the module ladder, and `:233` the palloc ladder.
# :406 `"nbio" if self.ip_ver[am.GC_HWIP] < (12,0,0) else "nbif"` -- ONE
# character decides which of the two register tables the device is built from.
def MOD_NBIO() -> String: "nbio"
def MOD_NBIF() -> String: "nbif"

def mods.nb(gcmaj: U32, gcmin: U32, gcrev: U32) -> String:
  Bool.pick(String, v.lt3(gcmaj, gcmin, gcrev, 12, 0, 0), MOD_NBIO(), MOD_NBIF())

# the six modules :405 names, in order, with the HWIP each one is keyed by.
def mods.names() -> List<&2, String>: ["mp", "hdp", "gc", "mmhub", "osssys"]
def mods.hwips() -> List<&2, U32>: [MP0_HWIP(), HDP_HWIP(), GC_HWIP(), MMHUB_HWIP(), OSSSYS_HWIP(), NBIO_HWIP()]
def mods.nbase() -> U32: 6
def MOD_SDMA() -> String: "sdma"

# :407 `if self.ip_ver[am.SDMA0_HWIP] in {(4,4,2), (4,4,4)}` -- TWO versions, and
# they are the only two that get an `sdma` register table.
def SDMA_V_A0() -> U32: 4
def SDMA_V_A1() -> U32: 4
def SDMA_V_B0() -> U32: 4
def SDMA_V_A2() -> U32: 2
def SDMA_V_B2() -> U32: 4

# each arm gets its own def, because `Bool.or` needs `sdrev` on both sides.
def mods.sdma_a(sdmaj: U32, sdmin: U32, sdrev: U32) -> Bool:
  v.eq3(sdmaj, sdmin, sdrev, SDMA_V_A0(), SDMA_V_A1(), SDMA_V_A2())

def mods.sdma_b(sdmaj: U32, sdmin: U32, sdrev: U32) -> Bool:
  v.eq3(sdmaj, sdmin, sdrev, SDMA_V_B0(), SDMA_V_A1(), SDMA_V_B2())

def mods.sdma(+sdmaj: U32, +sdmin: U32, +sdrev: U32) -> Bool:
  Bool.or(mods.sdma_a(sdmaj, sdmin, sdrev), mods.sdma_b(sdmaj, sdmin, sdrev))

# :233 `palloc_ranges=[(1 << (i + 12), (2 << 20) if i >= 9 else 0x1000) for i in
# range(9 * (3 - am.AMDGPU_VM_PDB2), -1, -1)]`. DESCENDING in `i`, so the SIZES
# DESCEND and the whole list is the allocator's free-list order.
# `1 << (i + 12)` is 64-BIT for i >= 20, and :233's list runs to i = 27 -- so
# `1 << 39`. `U32.shln` SATURATES past 31 and answers 0, which would make the
# whole top half of the allocator's free list a run of ZERO-SIZED entries: a
# `Nil` that means "everything" is a silent wrong answer, and this is the same
# shape as `ops_amd`'s 2^34 SQTT pointer. So the size is its TWO WORDS, and
# `palloc_size_is64` says which entries need the high one.
def palloc.align(+i: U32) -> U32: Bool.pick(U32, U32.is_ge(i, PALLOC_BIG_I()), PALLOC_BIG(), PALLOC_SMALL())

def palloc.shift(i: U32) -> U32: U32.add(i, 12)
def palloc.big(i: U32) -> Bool: U32.is_ge(palloc.shift(i), 32)
def palloc.size_hi(+i: U32) -> U32: Bool.pick(U32, palloc.big(i), U32.shln(1, U32.to_nat(U32.sub(palloc.shift(i), 32))), 0)
def palloc.size_lo(+i: U32) -> U32: Bool.pick(U32, palloc.big(i), 0, U32.shln(1, U32.to_nat(palloc.shift(i))))
# The index rides as its OWN decreasing argument, because the countdown binder
# `m` may be read only once per arm and `i` has to appear both in the recursion
# and in the `palloc.big` test.
def palloc.nbig.at(+i: U32, got: U32) -> U32: U32.add(got, Bool.to_u32(palloc.big(i)))

def palloc.nbig.go(n: Nat, +i: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: palloc.nbig.go(m, U32.sub(i, 1), palloc.nbig.at(i, got))

def palloc.nbig() -> U32: palloc.nbig.go(PALLOC_LEN(), PALLOC_NLV(), 0)

# :231 `va_shifts=[12, 21, 30, 39]` and :232 `va_bits=48`. Four page-table
# levels, and 21 is the 2MB shift while 30 and 39 are 1GB and 512GB -- so the LIST
# is the LEVEL ORDER, and reading it backwards would silently invert the page
# tables.
def va.shifts() -> List<&2, U32>: [VA_SHIFT0(), VA_SHIFT1(), VA_SHIFT2(), VA_SHIFT3()]

# THE SIX MODULE NAMES, with the one that is version-dependent last -- that is
# :405's list, and `nbio`/`nbif` is the only entry that changes.
def mods.names.at(+nb: String) -> List<&2, String>:
  List.append(&2, String, mods.names(), [nb])

def mods.names6(maj: U32, min: U32, rev: U32) -> List<&2, String>:
  mods.names.at(mods.nb(maj, min, rev))

def mods.names_sd.at(add: Bool, +six: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, add, List.append(&2, String, six, [MOD_SDMA()]), six)

# :407's `mods += [("sdma", am.SDMA0_HWIP)]`, so the seven-entry list exists for
# exactly two SDMA versions and the six-entry one for the other seven.
def mods.n_of(add: Bool) -> U32: Bool.pick(U32, add, 7, 6)

# :407's SEVEN-entry list, which is the six plus `sdma` -- and `sdma` is appended
# LAST, so a port that put it anywhere else would iterate the IP tables in a
# different order and build `AM_SDMA` against the wrong module.
def mods.names_sd(add: Bool, maj: U32, min: U32, +rev: U32) -> List<&2, String>:
  mods.names_sd.at(add, mods.names6(maj, min, rev))

def aid.keep4(n: Nat, +aidn: U32, +maxa: U32, +flags: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: aid.keep4(m, U32.add(aidn, 1), maxa, flags,
      Bool.pick(List<&2, U32>, aid.keep1(aidn, maxa, flags),
        List.append(&2, U32, acc, [aidn]), acc))

# THE LIST, `[0] + [aid for aid in range(1, max_aid+1) if alive]`, over a fixture
# of SIXTEEN live flags -- four per group, four groups. The leading `0` is
# unconditional (AID 0 always exists), and `range(1, max_aid+1)` is `aid <= maxa`
# so a fixture with nothing live past group 0 still yields `[0]`.
def aid.list4(+flags: List<&2, U32>) -> List<&2, U32>:
  aid.keep4(3n, 1, 3, flags, [0])

# THE FIXTURES. Each is a named shape, so a row says what it is about and a
# mutation's effect is legible. The ASPM chains are the seam's ANSWERS: `links`
# is `read_config(cap, 1)` and `nexts` is `read_config(cap + 1, 1)`, one entry per
# PROBE, and the last entry FAILS the condition -- which is what makes Python's
# `while` stop there rather than at the fuel.
# `first` is what `read_config(0x34, 1)` answers -- the FIRST CAP, and it is a
# DIFFERENT register from the chain: `links` is what `read_config(cap, 1)` says and
# `nexts` is what `read_config(cap + 1, 1)` says. The first version reused
# `links[0]` as the first cap, which made the walk start at 16 instead of 60 and
# put a read of `cap + 1` where Python reads `cap`.
def aspm_fx.link_first() -> U32: 60
def aspm_fx.link_links() -> List<&2, U32>: [16]
def aspm_fx.link_nexts() -> List<&2, U32>: [0]
def aspm_fx.chain_first() -> U32: 64
def aspm_fx.chain_links() -> List<&2, U32>: [17]
def aspm_fx.chain_nexts() -> List<&2, U32>: [1]
def aspm_fx.zero_first() -> U32: 0
def aspm_fx.zero_links() -> List<&2, U32>: [0]
def aspm_fx.zero_nexts() -> List<&2, U32>: [0]
def aspm_fx.loop_first() -> U32: 60
def aspm_fx.loop_links() -> List<&2, U32>: [17]
def aspm_fx.loop_nexts() -> List<&2, U32>: [60]

# `read_config(cap + 0x10, 2)` -- the LNKCTL LINK CONTROL register, read as two
# bytes and written back with `& ~3`. The value is a FIXTURE because the seam
# supplies it; what is NOT the seam's is the `& ~3`, which is :154.
def aspm_fx.lnkctl() -> U32: 65535

# THE FOUR `DEBUG >= 2` SITES -- amdev.py:185, :225, :251, :254.
#
#     :185  if DEBUG >= 2: print(f"am {self.devfmt}: Malformed state. Issuing a full reset.")
#     :225  if DEBUG >= 2: print(f"am {self.devfmt}: boot done")
#     :251  if DEBUG >= 2: print(f"am {self.devfmt}: {ip.__class__.__name__} initialized")
#     :254  if DEBUG >= 2: print(f"am {self.devfmt}: Finalizing")
#
# why these are ported and nothing ELSE is. All four are inside `AMDev`'s own methods
# -- `boot` (:168-225), `init_hw` (:248-251), `fini` (:253-254) -- and this file ports
# NONE of those bodies: the register writes are `Tr.emit` calls behind a `pci_dev`
# that only exists on real hardware, and `AMDev.boot` reaches `:185` only after
# `self.init_sw(...)`, `self.reg("regSCRATCH_REG7").read()` and a partial-boot
# decision. What these four lines SHARE, and what is genuinely portable, is the
# PREFIX: `am {devfmt}: `, where `devfmt` is `self.devfmt` and `AMDev.__init__` (:157)
# sets `self.devfmt = pci_dev.pcibus` -- a STRING ALREADY IN HAND, with no device
# call behind it. So one `am_dbg_text` and four gates is the whole of it, and it is
# honest about being the prefix rather than pretending to be `boot`.
#
# THE THREE STATES THE BOOT DECIDES BETWEEN, kept because the whole of `boot` is
# this decision and the port ports none of the body:
#   amdev.py:171 -- "The GPU being passed can be in one of several states:
#   1. Not initialized. 2. Initialized by amdgpu. 3. Initialized by AM." THE
#   THREE STATES HAVE THREE DIFFERENT COSTS. State 1 (nothing has touched it)
#   and state 2 (the amdgpu driver initialised it) both need a FULL setup
#   because their state is UNKNOWN -- and state 2 additionally needs a MODE1
#   RESET, because the amdgpu driver left the hardware in a configuration the
#   AM boot sequence does not know how to resume from.
#   amdev.py:175 -- "The 3rd state can be set up partially to optimize boot
#   time. In this case, only the GFX and SDMA IPs need to be initialized." THE
#   PARTIAL BOOT IS AN OPTIMISATION AND IT IS POSSIBLE ONLY BECAUSE OF A
#   RESERVED REGION: "AM uses a separate boot memory that is guaranteed not to
#   be overwritten", and that memory holds "all blocks that are initialized only
#   during the initial AM boot". So the third state skips re-initialising the
#   blocks whose initialisation state PERSISTED in a region nobody overwrote.
#   amdev.py:178 -- "To determine if the GPU is in the third state, AM uses
#   regSCRATCH_REG7 as a flag. To determine if the previous AM session
#   finalized correctly, AM uses regSCRATCH_REG6 as a flag." TWO SCRATCH
#   REGISTERS, TWO DIFFERENT QUESTIONS, and they are SCRATCH registers
#   precisely because they survive across sessions and across resets of the
#   things they describe. `regSCRATCH_REG7` holds the AM VERSION, so "it
#   equals AMDev.Version" is the third-state test, and `regSCRATCH_REG6` being
#   non-zero is the "the last session did not finish" test.
#   amdev.py:188 -- "aqua (gc 9.5.0): full boot over live state can kill the
#   fabric (power cycle recovers); partial boot+reset_mec is the deepest safe
#   reset". THE HARDWARE-SPECIFIC EXCEPTION, and it is a warning rather than a
#   rule: on that specific part, a FULL boot over LIVE state can kill the
#   fabric, and only a power cycle recovers it. So the deepest reset that is
#   still safe there is a partial boot plus a `reset_mec`.
#   amdev.py:198 -- "Quiesce first: mode1 reset over live engines can wedge the
#   GPU until power cycled." THE RESET NEEDS THE ENGINES STOPPED FIRST, for
#   the same reason: a mode1 reset issued while engines are live can WEDGE the
#   GPU. So `fini_hw` and `halt_engines` come BEFORE the reset, and a port
#   that reordered them would produce a wedged GPU rather than a wrong answer.
#
# the threshold is 2 for all four, measured rather than read off the pattern: the
# oracle's LANE B pulls the right-hand side out of each cited line with
# `re.search(r"DEBUG\s*>=\s*(\d+)", src)` and prints `thr_am185..thr_am254`, all `2`.
# `:185` is NOT a level-1 site -- `schedule/memory.py:59` is the only one of the seven
# that is, and mixing the two up in a single-level gate is invisible.
#
# :251 IS THE ONE WITH A SECOND INPUT, and `ip.__class__.__name__` is not derivable
# here: the ip classes are `AM_SOC`, `AM_GMC`, `AM_IH`, `AM_PSP`, `AM_SMU`, `AM_GFX`,
# `AM_SDMA` and they live in `ip.py`, which this repository does not port as records
# (ip.bend's header names them but has no `AM_GFX` def). So the class name is a
# PARAMETER and the gate supplies upstream's own spelling. `init_hw` is called as
# `init_hw(self, *blocks)` and the loop at :250 runs `for ip in blocks: ip.init_hw()`,
# so ONE CALL PRINTS ONE LINE, and the count is the number of blocks.

def am_dbg_prefix(devfmt: String) -> String:
  String.concat(["am ", devfmt, ": "])

def am_dbg_tail.of(v: String, tail: String) -> String:
  String.concat([am_dbg_prefix(v), tail])

# :251 is the only one whose tail is not a CONSTANT, so the text is one def with a
# parameter and the three constant tails are three defs that call it. Three constants
# as three defs rather than one with a `match` on a name: the names would then be
# arguments, and a call site that passed the wrong one would still compile.
def am_dbg_malformed(devfmt: String) -> String:
  am_dbg_tail.of(devfmt, "Malformed state. Issuing a full reset.")

def am_dbg_boot(devfmt: String) -> String:
  am_dbg_tail.of(devfmt, "boot done")

def am_dbg_ip(devfmt: String, ip: String) -> String:
  am_dbg_tail.of(devfmt, String.concat([ip, " initialized"]))

def am_dbg_final(devfmt: String) -> String:
  am_dbg_tail.of(devfmt, "Finalizing")

def am_dbg_text.gate(open: Bool, t: String) -> String:
  match open:
    case True{}: t
    case _: ""

# THE FOUR SITES. Two args for :251 (the IP class name) and one for the rest, and
# `dbg` is the THREADED level in every case -- see helpers.bend's `debug_print` for
# why the gate and the text are two defs rather than one `if`, and
# `schedule/allreduce.bend`'s header for why the level is a parameter at all.
def am_dbg_malformed_of(dbg: U32, devfmt: String) -> String:
  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_malformed(devfmt))

def am_dbg_boot_of(dbg: U32, devfmt: String) -> String:
  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_boot(devfmt))

def am_dbg_ip_of(dbg: U32, devfmt: String, ip: String) -> String:
  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_ip(devfmt, ip))

def am_dbg_final_of(dbg: U32, devfmt: String) -> String:
  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_final(devfmt))

# THE GATE PRINTERS. `IO.print` takes a `String`, so each printer CONCATENATES the
# name and the value -- and a row's name says which claim it is, so a mutation's
# effect is legible in the diff.
# THE GATE MOVED TO `gates/amdev-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Their 552 expectations are CPython's:
# `oracles/tinybendygrad_runtime_support_am_amdev.bend.rows` records upstream's
# own answers (564 lines -- 552 rows and 12 blank separators), and the
# driver's output is byte-identical to it.
