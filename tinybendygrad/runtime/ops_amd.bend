# tinybendygrad/runtime/ops_amd.bend -- port of tinygrad/runtime/ops_amd.py
#
# THE AMD BACKEND'S SHAPE, WITHOUT THE AMD DRIVER. `ops_amd.py` is 1073 lines and
# almost all of it is one of three things: an `ioctl` on `/dev/kfd` or a
# `USBPCIDevice`, an `mmap` of a PCI BAR, or a register write built out of the
# ctypes records in `autogen/{kfd,hsa,sqtt,amdgpu_kd,amdgpu_drm,am}.py`. None of
# that can be anything in Bend but an FFI seam.
#
# WHAT SURVIVES THE CROSSING is exactly what the other five backends also
# survive, which is why this file is worth the gate:
#
#   * the KERNEL ARGUMENT TRACE -- `kernargs` (:361-364) is `layout_args` then
#     `pack_args` over a list whose widths are `8` per global and
#     `v.dtype.itemsize` per var. That is `hcq2.py:74-80` and it is the SAME
#     contract `ops_webgpu.bend`, `ops_cl.bend` and `ops_nv.bend` port. Getting
#     it consistent across six files matters more here than anywhere.
#   * the PROGRAM/PROGRAM-BUFFER CACHE KEYS and the one eviction policy
#     ops_amd.py has, which is `device.py:280`'s four conjuncts reached through
#     a `BufferSpec`. `BufferSpec(nolru=True)` on a program buffer and NOT on a
#     ring is the positive/negative pair, and it is real Python.
#   * `AMDProgramData`'s ELEVEN derived fields -- the bit positions in
#     `rsrc1`/`rsrc2`/`rsrc3`/`wave32` and the two `kernel_code_properties` bits.
#     A wrong entry here is a silently wrong kernel, which is the whole reason
#     this file exists.
#   * the WAVEFONT / OCCUPANCY tables: `se_cnt`, `cu_cnt`, `waves_per_cu`,
#     `wave_cnt`, `vgpr_size_per_cu`, `lds_size_per_cu`, `max_copy_size`, the
#     arch allow-list, and `tmpring_size`'s five-step ladder with its THREE
#     different `union_COMPUTE_TMPRING_SIZE*` bitfield records.
#   * the `import_module` LADDER and the four MODULE NAMES that `target[0]`
#     picks, both directions.
#   * the QUEUE TAG grammar (`to_name` + `rsplit('_', 2)` + the four-prefix
#     allow-list), both directions.
#   * every REFUSAL, as a TRUNCATION of the trace.
#
# ---------------------------------------------------------------------------
# NO PROOFS FAIL HERE, and the brief expected some. `dtype.bend`'s seams are
# `def ... -> IO(R)` over two `import "./x.c"` lines, and every one of them is
# expected to make its importer print SOME PROOFS FAIL (constraints line 1868:
# the foreign notice is a "who names whom" closure that `@unsafe` does not
# shrink). This file does not take that route, because the WebGPU template does
# not and `ops_metal.bend` does not: a driver call is RECORDED in a `Tr` trace,
# so there is no foreign effect to declare and `--check-only` says ALL PROOFS
# CHECK. The seam is `Tr.emit`, the ORDER is the artefact, and `wgsl.bend`'s
# green lane is the precedent. See `.agents/slop/amd_oracle.py`.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one driver call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind. That is what puts every `raise` into the trace: a refusal records NOTHING
# further, so it appears as a TRUNCATION and no step needs a guard of its own.
#
# ---------------------------------------------------------------------------
# THE HEADLINE, measured. `--check-only` says ALL PROOFS CHECK. Both lanes print
# 520 IDENTICAL rows. All 520 are diffed against CPython by
# `.agents/slop/amd_check.py` and there are ZERO mismatches; the 601 oracle rows
# the gate does not print are accounted for at the foot of this file. THIRTY
# mutations move between 0 and 31 rows, and exactly ONE moves nothing -- and that
# one is a theorem (`floor(floor(a/b)/c) == floor(a/(b*c))`), not a hole.
#
# THE ORACLE is `.agents/slop/amd_oracle.py`, 1010 rows, and NOTHING in the gate
# is hand-typed. That matters more here than anywhere else: the
# `renderer/cstyle.bend` unit shipped 215 hand-typed expectations of which
# SEVENTEEN were wrong, twelve of them real port bugs. The oracle found four in
# THIS file, all of them real:
#
#   * `args.ks` used `LANES_PER_WAVE` (64) for a `getaddr`, which is EIGHT bytes.
#   * `pd.lds` used `ceildiv` where `ops_amd.py:551` uses `//`, i.e. FLOOR, so
#     512 granules read back as 2 instead of 1 and the `rsrc2` bit was wrong.
#   * `dev_max_copy` compared a three-part version COMPONENTWISE where
#     `ops_amd.py:880` compares it LEXICOGRAPHICALLY, and three of the eight
#     fixtures disagreed.
#   * `is_am` read as `iface == PCIIface` where `ops_amd.py:850` is an
#     `isinstance` and `USBIface(PCIIface)` -- so the USB device was not AM and
#     `can_recover` was wrong for it.
#
# A fifth was found by the port's own arithmetic rather than the oracle: the SQTT
# write pointer is `(raw & 0x1FFFFFFF) * 32`, which is up to 2^34, and the first
# version computed it in `U32` and WRAPPED. It is an `H.I64` and an `i64row`,
# which is what `ops_nv.bend` does for the same reason.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. `amd:NN` is ops_amd.py.
#
#   :31-34   SQTT / PMC ContextVars            PORTED  the two default pairs
#   :36-41   the constants                     PORTED  all of them
#   :55      _queue_args                       PORTED  the four ring tags
#   :59      _dw                               PORTED  the 8-vs-4 width
#   :61-67   dispatch_packet                   PORTED  the SHAPE and the header
#   :99-101  set_grbm                          PORTED  the instance_val fold
#   :103-106 wait_reg_mem                      PORTED  the wrm_info_dw words
#   :108-121 acquire_mem                       PARTIAL the flag words, both arms
#   :123-140 release_mem                       PARTIAL the flag words, both arms
#   :142-146 memory_barrier                    PARTIAL the pf ladder
#   :148-150 spi_config                       PORTED  the six fields
#   :157-165 prof_start                        PARTIAL the slot, the log index
#   :172-175 prof_bump                         PORTED  the index arithmetic
#   :184-209 pmc_start                         PARTIAL the block-count table
#   :211-231 pmc_read                          PARTIAL the copy and the stride
#   :235-238 sqtt_userdata                     PARTIAL the pair loop
#   :240-243 sqtt_config                       PARTIAL the rt_freq arm
#   :245-261 sqtt_setup_exec                   PARTIAL the cu/se masks
#   :263-325 sqtt_start                        PARTIAL the per-target register
#                                                    arms, as TABLES
#   :328-357 sqtt_stop                         PARTIAL the status masks
#   :361-364 kernargs                          PORTED  THE ARGUMENT TRACE
#   :366-400 exec                              PARTIAL the register ORDER, the
#                                                    user_regs, dispatch_init
#   :402     wait                              PORTED  one pkt3
#   :404-407 timestamp                         PORTED  one pkt3
#   :409-412 signal                            PORTED  one pkt3, cache_flush
#   :414-418 submit                            PORTIAL the 4-dword ib blob
#   :420-428 push                              PORTIAL the ring/doorbell store
#   :437-443 close_run                         PORTED  the vendor ib packet
#   :445-447 AQLQueue.signal                   PORTED  the close_run then the
#                                                    release
#   :449-458 AQLQueue.exec                     PORTED  the dispatch packet append
#   :460-465 AQLQueue.submit                   PARTIAL the unit=64 doorbell_lag
#   :477-480 SDMAQueue.copy                    PORTIAL the per-chunk header
#   :482-486 SDMAQueue.wait                    PORTED  the func/op ladder
#   :488-490 SDMAQueue.timestamp               PORTED
#   :492-494 SDMAQueue.write                   PORTED
#   :496-498 SDMAQueue.signal                  PORTED  the gfx9 arm
#   :500-520 SDMAQueue.submit                  PARTIAL the wrap/zero tail
#   :522-523 amd_compute_queue                 PORTED  the is_aql dispatch
#   :525-530 AMDProgramData                    PORTED  the record
#   :533-540 amd_build_program                 PORTED  the cache key, both ways
#   :542-561 _amd_program_image                PARTIAL the eleven fields, the
#                                                    LDS refusal, the md5 slice
#   :563-572 AMDAllocator                      PORTED  the five methods
#   :574-577 AMDQueueDesc                      PORTED  the seven fields
#   :579-735 KFDIface                          WALL 1  /dev/kfd
#   :737-804 PCIIface                          WALL 2  PCI BAR + amdev
#   :806-833 USBAllocator / USBIface           WALL 3  USB3
#   :835     _mock                             PORTED  the name ladder
#   :838-840 the three class attributes        PORTED
#   :841-844 pm_encode                         WALL 4  the UOp matcher
#   :846     ifaces                            PORTED  the seven, in order
#   :848-850 device_props/is_am                PORTED
#   :852-920 __init__                          PORTED  the order, the derivations,
#                                                    the module ladders, the
#                                                    arch refusal
#   :922-941 create_queue                      PORTED  the specs, the sizes
#   :943-946 queue_buffer                      PORTED  the grammar, both ways
#   :948-959 compute_queue                     PORTED  the six sizes, the vgpr
#                                                    and lds tables
#   :961-971 has_copy_queue/sdma_queue         PARTIAL the disable, the memo
#   :973-987 tmpring_size                      PORTED  THE WHOLE LADDER
#   :989-999 scratch_buffer                    PORTED  the monotone max
#   :1001-1014 aql_scratch                     PARTIAL the rsrc dicts
#   :1016-1030 the four prof buffers           PORTED  their sizes and specs
#   :1032-1038 program_buffer                  PORTED  the memo and the spec
#   :1040-1048 sqtt_trace                      PORTED  the offset, the wptr, the
#                                                    gfx11 correction, the assert
#   :1055-1069 collect_prof                    PARTIAL the window and the kinds
#   :1071    on_device_hang                    WALL 5
#
# ===========================================================================
# THE FIVE WALLS.
#
# 1. `/dev/kfd` (KFDIface, :579-735). `AMDKFD_IOC_*` on `/dev/kfd`, `/sys/
#    devices/virtual/kfd/kfd/topology/nodes`, `/dev/dri/renderD<n>`, and the
#    `ctypes` in/out structures. Every ioctl is in the trace as an `OPEN`, a
#    `GET_VERSION`, an `ACQUIRE_VM` or a `RUNTIME_ENABLE`; the bytes are the
#    seam's.
#    TODO(p3) runtime/ops_amd.py:596  FileIOInterface("/dev/kfd").
#    TODO(p3) runtime/ops_amd.py:613  AMDKFD_IOC_ACQUIRE_VM.
#    TODO(p3) runtime/ops_amd.py:631  AMDKFD_IOC_ALLOC_MEMORY_OF_GPU.
#    TODO(p3) runtime/ops_amd.py:665  AMDKFD_IOC_MAP_MEMORY_TO_GPU.
#    TODO(p3) runtime/ops_amd.py:685  AMDKFD_IOC_CREATE_QUEUE.
#    TODO(p3) runtime/ops_amd.py:702  AMDKFD_IOC_WAIT_EVENTS.
#
# 2. PCI / amdev (PCIIface, :737-804). `USBPCIDevice`/`PCIIfaceBase`, the BAR
#    map, `AMDev`'s `sdma`/`gfx`/`ih` objects and `setup_ring`, and every
#    `AMDReg.encode`/`fields_mask`. The bit positions of `regCOMPUTE_*` and
#    `regSQ_THREAD_TRACE_*` are the register TABLES in `autogen/am/regs/*`, and
#    the port carries their use (which register, with which field values) and
#    not their offsets, which are the seam's.
#    TODO(p3) runtime/ops_amd.py:740  PCIIfaceBase.__init__ (vendor 4098).
#    TODO(p3) runtime/ops_amd.py:753  AMDev.gc_info / AMDev.gfx.xccs.
#    TODO(p3) runtime/ops_amd.py:772  AMDev.{sdma,gfx}.setup_ring.
#    TODO(p3) runtime/ops_amd.py:731-733  struct_drm_amdgpu_info_device.cu_bitmap.
#
# 3. USB3 (USBIface, :810-833). `USB3.list_devices`, `dma_view`, the
#    `0/4096/20480` controller window and its `AddrSpace.SYS` mapping.
#    TODO(p3) runtime/ops_amd.py:812  USB3.list_devices.
#    TODO(p3) runtime/ops_amd.py:822  USBIface.ctrl's three map_range pieces.
#    TODO(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768).
#
# 4. THE UOp MATCHER (:841-844, :888-892, :895-896, :905-906). `pm_encode`
#    matches `CUSTOM_FUNCTION` nodes and `pm_bufferize` PREPENDS three rules to
#    `Compiled`'s. The port carries the three rules' PATTERNS and their
#    first-wins fold and the profiling rules' four names, in order; a rule's
#    body is a UOp graph and building one needs `./uop/ops.bend` and the HCQ2
#    lowering this file does not own. `amd_pmb_order` and `amd_pmb_prof` are the
#    rows, and they are about ORDER, which is all that is portable here.
#    TODO(p3) runtime/ops_amd.py:842  encode_submit(amd_compute_queue(submit)).
#    TODO(p3) runtime/ops_amd.py:843  encode_submit(AMDSDMAQueue(submit)).
#    TODO(p3) runtime/ops_amd.py:889  ctx.scratch_buffer(b.max_numel()).
#    TODO(p3) runtime/ops_amd.py:890  ctx.program_buffer(b).
#    TODO(p3) runtime/ops_amd.py:891  ctx.queue_buffer(b.tag).
#
# 5. THE HANG PATH (:705-717, :800-802, :798). `on_device_hang` builds its
#    report out of `queue_event_arr[i].memory_exception_data.failure`, whose
#    `_real_fields_` it walks by name. A field NAME is a Python string table and
#    a walk over it is a `dict`, so the port keeps the two refusal MESSAGES and
#    the trace truncation and nothing of the report's body.
#    TODO(p3) runtime/ops_amd.py:706  `_str(st)` over `st._real_fields_`.
#    TODO(p3) runtime/ops_amd.py:714  the MMU-fault f-string.
#    TODO(p3) runtime/ops_amd.py:715  the HW-fault f-string.
#
# ===========================================================================
# TWO THINGS THAT ARE NOT IN THE PORT AT ALL, and why.
#
#  * `_amd_program_image`'s ELF WALK (:544-548). `elf_loader(lib)` returns the
#    image, the section headers and the relocation list, and the loop
#    `image[off:off+8] = struct.pack('<q', sym - off + addent)` rewrites eight
#    bytes per R_AMDGPU_REL64. The ARITHMETIC of the eleven fields that follow
#    it is ported and gated; the image is the compiler's artefact and its bytes
#    are `elf.bend`'s. `amd_pd_img_len` and `amd_pd_img_pad` pin the ONE thing
#    about it that is decided here -- `bytes(image).ljust(round_up(len(image),
#    4), b"\x00")`, the whole-dwords upload.
#    TODO(p3) runtime/ops_amd.py:544  elf_loader(lib) and the reloc loop.
#
#  * `hashlib.md5` (:558). `struct.unpack('<Q', hashlib.md5(lib).digest()[:8])[0]`
#    is a 64-bit integer and Bend 2.0.34 has no MD5 and no F64, so the port
#    carries the SLICE -- the first EIGHT digest bytes, LITTLE endian, which is
#    the half that decides the truncation -- and the digest is the compiler's.
#    `amd_libhash_*` is generated by running CPython's `hashlib` and it is a
#    row about CPython, NOT about this file, which is said in the row's name.
#    TODO(p3) runtime/ops_amd.py:558  hashlib.md5(lib).digest()[:8].
#
# ===========================================================================
# WHAT device.bend AND helpers.bend OW THIS FILE, and they OWN FOUR THINGS:
#
#  1. `D.iter_sig` IS `layout_args`' ENGINE, and THIS FILE USES ITS FORM AND
#     NOT ITS ARITHMETIC. `device.py:364-366` is
#       `yield (offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`
#     and the WALRUS REBINDS, so the advance is `round_up(off, k) + k`.
#     `D.iter_sig` advances by the UNROUNDED `off + k`, which agrees on every
#     list whose widths happen to be aligned and disagrees on the rest:
#     CPython's `iter_sig` of `[uint8, uint32, uint8]` is `[0, 4, 8]`, and
#     `D.iter_sig` of `[1,4,1]` yields `0 4 5`. REPORTED, NOT FIXED --
#     `tinybendygrad/device.bend` is not mine, and its own gate row `sig`
#     expects the wrong answer, so the disagreement is load-bearing evidence
#     rather than a stale comment. `sig.slot` below is the CPython form and
#     `amd_arg_at_*` is generated from the CPython call.
#  2. `D.round_up` is `helpers.py:69`, and `H.round_up_u32` / `H.ceildiv_u32` /
#     `H.floordiv_u32` are the same three functions under the names
#     `tmpring_size` and `wg_data_size` use. Nothing re-derives a rounding.
#  3. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and every BufferSpec
#     in this file is a `Bspec` handed to it. `amd_recycled_*` is that call.
#  4. `D.alloc_take` is `c.pop()` -- the MOST RECENTLY freed -- and
#     `amd_lru_take_*` is that call on the ring's bucket.
#  A Buffer is a SLOT in `D.Bar`: `nbytes` is `size * itemsize` and a view's
#  offset ACCUMULATES with its base the ROOT, so `ring_elems` and the scratch
#  size are the same two facts as everywhere else in the tree.
import Base
import ../helpers.bend as H
import ../device.bend as D

# ===========================================================================
# THE CONSTANTS, and where each one was read.
# ===========================================================================

# ops_amd.py:36, "based on a comment in nvd.h".
def EVENT_INDEX_PARTIAL_FLUSH() -> U32: 4
# :37-39. The three `WAIT_REG_MEM_FUNCTION_*`.
def WAIT_REG_MEM_FUNCTION_EQ() -> U32: 3
def WAIT_REG_MEM_FUNCTION_NEQ() -> U32: 4
def WAIT_REG_MEM_FUNCTION_GEQ() -> U32: 5
# :40-41, `AQL_HDR`. MEASURED: `1<<HSA_PACKET_HEADER_BARRIER | 4<<SCACQUIRE | 4<<SCRELEASE`
# == 5376 == 5376, i.e. the barrier bit 8 and BOTH fence scopes in bits 10
# and 11. The two `HSA_FENCE_SCOPE_SYSTEM` are 4, not 1, and that is the whole
# value.
def AQL_HDR() -> U32: 5376
def HSA_PACKET_HEADER_BARRIER_BIT() -> U32: 8
def HSA_FENCE_SCOPE_SYSTEM() -> U32: 4
def HSA_PACKET_HEADER_SCACQUIRE_FENCE_SCOPE_BIT() -> U32: 10
def HSA_PACKET_HEADER_SCRELEASE_FENCE_SCOPE_BIT() -> U32: 11
# `hsa.HSA_PACKET_HEADER_TYPE` is ZERO, so `<< TYPE` is the identity and both
# `HSA_PACKET_TYPE_KERNEL_DISPATCH` and `HSA_PACKET_TYPE_VENDOR_SPECIFIC`
# land in the low byte. The gate says so in `amd_hdr_type`.
def HSA_PACKET_HEADER_TYPE() -> U32: 0
def HSA_PACKET_TYPE_KERNEL_DISPATCH() -> U32: 2
def HSA_PACKET_TYPE_VENDOR_SPECIFIC() -> U32: 0
def HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS() -> U32: 0
# `hsa.AMD_KERNEL_CODE_PROPERTIES_*`. The two bits :553 and :560 read.
def KPROPS_EDP_BIT() -> U32: 1
def KPROPS_EPS_BIT() -> U32: 0
# `hsa.amd_queue_t`, :929-930. `AMD_QUEUE_PROPERTIES_IS_PTR64 | ENABLE_PROFILING`.
def QPROP_IS_PTR64_BIT() -> U32: 1
def QPROP_PROFILING_BIT() -> U32: 3
# `autogen/hsa.py`, `hsa_kernel_dispatch_packet_t` is 64 bytes and the three
# slices are :67's `pkt[:12]`, `pkt[24:32]` and `pkt[48:]`.
def PKT_BYTES() -> U32: 64
def PKT_HEAD() -> U32: 12
def PKT_MID() -> U32: 8
def PKT_TAIL() -> U32: 16
def DESC_BYTES() -> U32: 64
# :551, `lds = ((group_segment_fixed_size+511)//512) & 511`. The MASK is the
# load-bearing half: 262144 bytes of group segment is 512 granules and the mask
# folds it back to ZERO.
def LDS_GRANULE() -> U32: 512
def LDS_MASK() -> U32: 511
# :556, `rsrc1 | ((1<<20) if dev.target[0]==11 else 0)` -- priv=1 for cwsr.
def RSRC1_PRIV_BIT_GFX11() -> U32: 20
# :557, `rsrc2 | (lds<<15)`.
def RSRC2_LDS_SHIFT() -> U32: 15
# :557, `wave32=bool(kernel_code_properties & 1024)`.
def WAVE32_BIT() -> U32: 10
# :883/:996, `mmap.PAGESIZE`.
def PAGESIZE() -> U32: 4096
# :976-977, the scratch alignment ladder, keyed on `target[0] != 9`.
def LANES_PER_WAVE() -> U32: 64
# :362, `get_call_arg_uops(call)[gi].getaddr(self.devs)` is EIGHT bytes whatever
# the buffer's dtype, so a global contributes 8 and a var contributes its own
# itemsize. It is NOT `LANES_PER_WAVE` and getting that wrong makes every global
# eight times too wide -- which the gate caught, so the constant is named.
def GETADDR_BYTES() -> U32: 8
def MEM_ALIGN_GFX9() -> U32: 1024
def MEM_ALIGN_NEW() -> U32: 256
# :974/:990, the floor on a private segment.
def PRIV_FLOOR() -> U32: 128
# :951-952, the four per-CU sizes in `wg_data_size`.
def SGRP_PER_CU() -> U32: 16384
def HWREG_PER_CU() -> U32: 4096
def LDS_PER_CU_GFX9_5() -> U32: 65536
def VGPR_PER_CU_HEAVY() -> U32: 393216
def VGPR_PER_CU_GFX9() -> U32: 524288
def VGPR_PER_CU_LIGHT() -> U32: 262144
# :955, `ctl_stack_size = round_up((12 if target[0]!=9 else 8)*wave_cnt + 8 + 40, PAGESIZE)`.
def CTL_WAVES_GFX9() -> U32: 8
def CTL_WAVES_NEW() -> U32: 12
# :956, the ring size, and :957 the eop buffer.
def RING_USB() -> U32: U32.shln(1, 20n)
def RING_HOST() -> U32: U32.shln(16, 20n)
def EOP_SIZE() -> U32: 4096
# :880, the two SDMA copy ceilings.
def MAXCOPY_BIG() -> U32: 1073741824
def MAXCOPY_SMALL() -> U32: 4194304
# :838-840, the three class attributes.
def TIMESTAMP_DIVIDER() -> U32: 100
def SLEEP_TIMEOUT_MS() -> U32: 200
def RTALLOC_USB() -> U32: U32.shln(4, 20n)
def RTALLOC_HOST() -> U32: U32.shln(64, 20n)
# :99, `wgp << 2 | (instance or 0)`.
def GRBM_WGP_SHIFT() -> U32: 2
# :378, the three architected SGPRs of a private segment.
def SCRATCH_FLAG_BIT() -> U32: 63
def UREG1_VALUE() -> U32: 4294967295
def UREG2_VALUE() -> U32: 549535744
# :891, `ctx.queue_buffer(b.tag)` and :944's allow-list, in Python's order.
def QF_RING() -> U32: 0
def QF_WRITE_PTR() -> U32: 1
def QF_DOORBELL() -> U32: 2
def QF_PUT_VALUE() -> U32: 3
# the four device-call kinds the trace carries, as a Tag per class
def IFACE_KFD() -> U32: 0
def IFACE_PCI() -> U32: 1
def IFACE_USB() -> U32: 2
def IFACE_MOCKKFD() -> U32: 3
def IFACE_MOCK() -> U32: 4
def IFACE_MOCKPCI() -> U32: 5
def IFACE_MOCKUSB() -> U32: 6
# and the four module names :869-877 pick, in the order they are imported
def MOD_OFFSETS() -> U32: 0
def MOD_SOC() -> U32: 1
def MOD_PM4() -> U32: 2
def MOD_SDMA() -> U32: 3
def MOD_GC() -> U32: 4
def MOD_NBIO() -> U32: 5
def MOD_N() -> U32: 6

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE driver call and the object it acts on. `arg` is the iface kind for a
# SELECT, the module id for an IMPORT, and a plain number otherwise. There is
# deliberately no field for the rest of the call's ARGUMENTS: those are what
# the defs around this record build, and the gate reads them from the record a
# def RETURNS, not from the trace.
type Call is Data:
  Call{k: U32, arg: U32}

# the machine state of the FFI seam. Bend has no pointer, so `next` mints the
# handle ids and what the gate checks is that they are consumed in the right
# ORDER and the right NUMBER of times.
#
# THE RAISE IS HERE. `Tr.emit` records NOTHING once a refusal has fired, and
# `Tr.refuse` is IDEMPOTENT after the first. `nth` counts refusals so far and
# `at` is the refusal ordinal the seam should fail on (0 = never), so one
# fixture numbering reaches EVERY refusal site in turn; the failing refusal is
# NOT recorded, because in Python the `raise` replaces it.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool, nth: U32, at: U32}

# `AMDProgramData` (:526-529), all eleven fields. None of them is derivable
# from another, which is why a wrong one is a silently wrong kernel.
type Pd is Data:
  Pd{desc_off: U32, entry_off: U32, rsrc1: U32, rsrc2: U32, rsrc3: U32,
     wave32: Bool, priv: U32, grp: U32, kaseg: U32, edp: U32, epsgpr: U32}

# ONE element of the packed kernarg blob: a WORD of `n` bytes or a zero BLOB
# of `n` bytes. `k` is 0 for a word and 1 for a blob, and it is a `U32` because
# `Bool.to_u32` is the only Bool-to-`U32` in the tree.
type E is Data:
  E{k: U32, n: U32}

# the argument list BEFORE packing: the slot and the width, one per entry.
type A is Data:
  A{at: U32, k: U32}

def A.at(a: A) -> U32:
  match a:
    case A{at, k}: at

def A.k(a: A) -> U32:
  match a:
    case A{at, k}: k

# `AMDDevice`'s derived state, and the trace. `target` is a THREE-PART version
# and it is stored FLAT (`t0`/`t1`/`t2`) because a `List` field of three
# `U32`s would need its own reader and nothing here indexes a version tuple by
# name.
type Dev is Data:
  Dev{iface: U32, target: U32, t0: U32, t1: U32, t2: U32, xccs: U32,
      se_cnt: U32, cu_cnt: U32, waves_per_cu: U32, wave_cnt: U32,
      max_copy_size: U32, is_aql: Bool, ver: U32, sdma: U32, t: Tr}

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every driver call in this file goes through
# it, so the trace is the ordered list of ioctls the seam will make.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}, 0, 0}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused, nth, at}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused, nth, at}: refused

# the refusal ordinal the seam should fail on, 0 = never. `nth` is NOT reset by
# `Tr.reset`, so one fixture numbering covers a whole device lifetime.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{calls, next, refused, nth, n}

# an EMPTY trace that keeps `at` and `nth`, so a gate can read one step without
# the init in front of it and still number its refusals from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{Nil{}, 0, False{}, nth, at}

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates BOTH arms, so the recorded call is a value built here
# and the guard is a parameter. This is the port of every `raise` in the file.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused, nth, at}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}:
      Tr.emit.go(refused, k, arg, calls, next, nth, at)

# THE RAISE. `Tr.refuse` fires at refusal ordinal `at` and is idempotent after
# that, so a fixture numbering reaches each site in turn and no site below needs
# a guard of its own. `amd_refuse_*` is the row that pins the idempotence.
def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.refuse.go(refused, nth, at)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in
# order; `Tr.count` is how many there are; `Tr.seen` is how many calls there
# are at all, which is the TRUNCATION length a refusal shows up as.
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

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one
# of them would branch the walk twice over.
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

def Tr.seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# does the trace CONTAIN this (tag, arg) sequence, in order? `at` is how much of
# the pattern is matched so far, read out of the pattern BY INDEX rather than
# carried as a second list. THE FUEL IS THE TRACE LENGTH and the answer is
# `at == patlen`: with the fuel set to the PATTERN length, `case 0n:` fires
# after `patlen` trace entries and returns True without ever looking at `at`, so
# a reversed pattern matches. MEASURED in ops_webgpu.bend, and the row that
# caught it there is the `wg_has_rejects_*` pair, which is duplicated here as
# `amd_has_rejects`.
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

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def Tr.seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

def nth_of(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: nth


# ===========================================================================
# THE KERNEL ARGUMENT TRACE. `kernargs` (:361-364) and the two helpers it calls,
# and this is the section `ops_webgpu.bend`, `ops_cl.bend` and `ops_nv.bend`
# port too. The three facts, in order:
#
#   1. the WIDTHS. `prg.arg.globals` names positions in
#      `get_call_arg_uops(call)`, and `:362` takes `.getaddr(self.devs)` of each
#      -- a `getaddr` is EIGHT bytes -- so a global contributes 8 whatever its
#      dtype. A var is `b.ccast(v.dtype)` and contributes `v.dtype.itemsize`.
#      So the width list is `8` per global ++ `itemsize` per var, IN THAT ORDER,
#      and the globals come first because :362 concatenates them first.
#   2. the SLOTS. `layout_args` (:74-76) is `iter_sig` at base 0, and the walrus
#      makes the advance `round_up(off, k) + k`. See THE WALRUS IN THE HEADER.
#   3. the PACK. `pack_args` (:78-83) walks the slots in ascending offset and,
#      where a slot does not continue the previous one, PREPENDS a zero blob of
#      exactly the gap; then it appends one trailing blob of
#      `kernargs_segment_size - end`, which is ZERO when the args fill it.
# ===========================================================================

# `(1)`: `8` per global, then the var widths. The fold APPENDS, so the order is
# globals-then-vars, and the list of globals is a COUNT because
# `prg.arg.globals` is a tuple of positions whose only property this reads is
# how many there are.
def args.glob.go(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: args.glob.go(m, List.append(&2, U32, acc, [GETADDR_BYTES()]))

def args.ks(ng: Nat, vards: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, args.glob.go(ng, Nil{}), vards)

# `(2)`: `sig.slot` is `iter_sig`'s yield pair. The advance is
# `round_up(off, k) + k` and NOT `off + k`; see THE WALRUS IN THE HEADER.
type Sig is Data:
  Sig{at: U32, next: U32}

def Sig.at(x: Sig) -> U32:
  match x:
    case Sig{at, next}: at

def Sig.nxt(x: Sig) -> U32:
  match x:
    case Sig{at, next}: next

def sig.slot(+off: U32, +k: U32) -> Sig:
  Sig{H.round_up_u32(off, k), U32.add(H.round_up_u32(off, k), k)}

def sig.step(s: Sig, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [Sig.at(s)])

def sig.go(ks: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case +k <> t: sig.go(t, Sig.nxt(sig.slot(off, k)), sig.step(sig.slot(off, k), acc))

def args.layout(ks: List<&2, U32>, off: U32) -> List<&2, U32>:
  sig.go(ks, off, Nil{})

# `(2)` again, as PAIRS, because `pack_args` needs the width beside each slot.
def args.slots(ks: List<&2, U32>, +off: U32, acc: List<&2, A>) -> List<&2, A>:
  match ks:
    case Nil{}: acc
    case +k <> t: args.slots(t, Sig.nxt(sig.slot(off, k)),
      List.append(&2, A, acc, [A{Sig.at(sig.slot(off, k)), k}]))

# `(3)`: ONE entry of `pack_args`' inner loop. The pad is `at - end` and it
# appears ONLY when that is not zero, which is the `if offset != end` at :80;
# the element is the word of width `k` either way, and `end` becomes `at + k`.
# So a zero gap is NO element and not a zero-length one, which is the
# difference between `B0` and nothing at all.
def pack.put(cont: Bool, gap: U32, w: U32, +acc: List<&2, E>) -> List<&2, E>:
  Bool.pick(List<&2, E>, cont, acc,
    List.append(&2, E, acc, [E{1, gap}]))

def pack.one(cont: Bool, gap: U32, +w: U32, acc: List<&2, E>) -> List<&2, E>:
  List.append(&2, E, pack.put(cont, gap, w, acc), [E{0, w}])

def pack.go(as: List<&2, A>, +end: U32, acc: List<&2, E>) -> List<&2, E>:
  match as:
    case Nil{}: acc
    case +a <> t: pack.go(t, U32.add(A.at(a), A.k(a)),
      pack.one(U32.is_eq(A.at(a), end), U32.sub(A.at(a), end), A.k(a), acc))

# the running `end` -- the offset the LAST slot ended at, which is the base of
# the trailing blob. It is the same walk as `sig.go` and reading it off `sig.go`
# would be a second transcription of `iter_sig`, so it is its own fold over the
# SAME `sig.slot`.
def pk_end.go(ks: List<&2, U32>, +off: U32) -> U32:
  match ks:
    case Nil{}: off
    case +k <> t: pk_end.go(t, Sig.nxt(sig.slot(off, k)))

def pack_end(ks: List<&2, U32>) -> U32: pk_end.go(ks, 0)

# :83, `words + [UOp(Ops.BINARY, arg=bytes(size - end))]`. A ZERO-length trailing
# blob IS a real element -- `bytes(0)` is `b""` and CPython still appends it --
# so the tail is unconditional, and the interior pad is the only conditional.
# `amd_pack_b3v2_32_32` ends in `B0` and that is the row.
def pack.tail(end: U32, size: U32) -> List<&2, E>:
  List.append(&2, E, Nil{}, [E{1, U32.sub(size, end)}])

# the whole thing, given the WIDTHS. `size` is `data.kernargs_segment_size`.
def pack_args(+ks: List<&2, U32>, size: U32) -> List<&2, E>:
  List.append(&2, E, pack.go(args.slots(ks, 0, Nil{}), 0, Nil{}), pack.tail(pack_end(ks), size))

# ===========================================================================
# `dispatch_packet` (:61-67), the AQL side. What survives is the SHAPE: a
# 64-byte packet handed over as a list of words, and the three slice boundaries
# that split it.
#
#   [BINARY pkt[:12], grid_x, grid_y, grid_z, BINARY pkt[24:32],
#    kernel_object, kernarg_address, BINARY pkt[48:]]
#
# `pkt[24:32]` covers `reserved0` and `grid_size_x`, and the grid list OVERWRITES
# the grid words -- which is why the split is at 24 and not at 28. The two
# `UOp`s in the middle are 8 bytes each by default, and the three grid words are
# `g * l` cast to uint32, `zip`ped over `global_size` and `local_size`.
# ===========================================================================

# the three words the header contributes, and the value of the first.
def pkt.header() -> U32:
  U32.or(AQL_HDR(), U32.shln(HSA_PACKET_TYPE_KERNEL_DISPATCH(), U32.to_nat(HSA_PACKET_HEADER_TYPE())))

# `3 << HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS` and the shift is ZERO, so
# `setup` is 3 and the DIMENSIONS bit is in the low byte of `full_header`.
def pkt.setup() -> U32:
  U32.shln(3, U32.to_nat(HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS()))

# the grid, `g * l` for the three zipped pairs, and the cast to uint32 is the
# seam's because a UOp cast is a node. ONE fold over THREE pairs -- three
# separate folds would be three transcriptions of `zip(global_size, local_size)`
# and the first version of this def did exactly that and printed FIVE numbers.
type Gr is Data:
  Gr{g: U32, l: U32}

def Gr.g(x: Gr) -> U32:
  match x:
    case Gr{g, l}: g

def Gr.l(x: Gr) -> U32:
  match x:
    case Gr{g, l}: l

def pkt.grid.go(n: Nat, +a: Gr, +b: Gr, +c: Gr, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: pkt.grid.go(m, b, c, Gr{0, 0},
      List.append(&2, U32, acc, [U32.mul(Gr.g(a), Gr.l(a))]))

def pkt.grid(gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32) -> List<&2, U32>:
  pkt.grid.go(3n, Gr{gx, lx}, Gr{gy, ly}, Gr{gz, lz}, Nil{})

# THE SHAPE, as `(kind, bytes)`: a 12-byte blob, three 4-byte grid words, an
# 8-byte blob, TWO 8-byte words (`kernel_object` and `kernarg_address`, both
# `UOp`s at the DEFAULT uint64), and a 16-byte tail. `amd_dispatch_shape` and
# the gate's `elrow` render it, and the SLICES are the load-bearing numbers.
def pkt.sh_seeds() -> List<&2, E>:
  List.append(&2, E, List.append(&2, E, List.append(&2, E, List.append(&2, E, List.append(&2, E, Nil{},
    [E{1, PKT_HEAD()}]), [E{0, 4}]), [E{0, 4}]), [E{0, 4}]), [E{1, PKT_MID()}])

def pkt.sh_tail(n: Nat, acc: List<&2, E>) -> List<&2, E>:
  match n:
    case 0n: acc
    case 1n+m: pkt.sh_tail(m, List.append(&2, E, acc, [E{0, 8}]))

def pkt.shape() -> List<&2, E>:
  List.append(&2, E, pkt.sh_tail(2n, pkt.sh_seeds()), [E{1, PKT_TAIL()}])

# :437-443 `close_run`, the AQL vendor packet that wraps a run of pm4 as an
# indirect buffer. FIVE words plus TEN zeros, and the third word is
# `(end - run_start) // 4 | INDIRECT_BUFFER_VALID`, so a run of 0 dwords and a
# run of 4 produce the SAME word and a run of 8 does not.
def pkt.vendor_hdr() -> U32:
  U32.or(U32.or(AQL_HDR(), U32.shln(HSA_PACKET_TYPE_VENDOR_SPECIFIC(), U32.to_nat(HSA_PACKET_HEADER_TYPE()))), U32.shln(1, 16n))

def pkt.ib_words(nbytes: U32) -> U32:
  U32.or(U32.div(nbytes, 4), 1)

def pkt.vendor_n() -> U32: 15

# ===========================================================================
# `AMDProgramData` (:525-529, :555-560). ELEVEN fields, and the derivations
# that :544-554 feeds them. `desc_off` is the `.rodata` section address and
# `entry_off` is that plus the entry byte offset -- so the two are the SAME
# number when the entry is at the section head, which is one of the fixtures.
# ===========================================================================

def Pd.of() -> Pd: Pd{0, 0, 0, 0, 0, False{}, 0, 0, 0, 0, 0}

def Pd.desc_off(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: desc_off

def Pd.entry_off(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: entry_off

def Pd.rsrc1(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: rsrc1

def Pd.rsrc2(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: rsrc2

def Pd.rsrc3(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: rsrc3

def Pd.wave32(x: Pd) -> Bool:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: wave32

def Pd.priv(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: priv

def Pd.grp(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: grp

def Pd.kaseg(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: kaseg

def Pd.edp(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: edp

def Pd.epsgpr(x: Pd) -> U32:
  match x:
    case Pd{desc_off, entry_off, rsrc1, rsrc2, rsrc3, wave32, priv, grp, kaseg, edp, epsgpr}: epsgpr

# :551, `lds = ((group_segment_fixed_size+511)//512) & 511`. The MASK is what
# makes a 512-granule request read back as ZERO, and `amd_lds_gs*` is the row.
def pd.lds(gs: U32) -> U32:
  U32.and(H.floordiv_u32(U32.add(gs, U32.sub(LDS_GRANULE(), 1)), LDS_GRANULE()), LDS_MASK())

# the cap, :551, `(dev.iface.props['lds_size_in_kb']*1024)//512`. Note it divides
# the CAP by 512 as well, so the comparison is granule-to-granule.
def pd.lds_cap(lds_kb: U32) -> U32:
  U32.div(U32.mul(lds_kb, 1024), LDS_GRANULE())

# :551's `if lds > cap: raise`. The boundary is a STRICT `>`, and the two
# fixtures that straddle it are `amd_lds_edge_*`.
def pd.lds_refuse(gs: U32, lds_kb: U32) -> Bool:
  U32.is_gt(pd.lds(gs), pd.lds_cap(lds_kb))

# :556, `rsrc1 | ((1<<20) if dev.target[0]==11 else 0)`.
def pd.rsrc1_of(+r1: U32, t0: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t0, 11), U32.or(r1, U32.shln(1, U32.to_nat(RSRC1_PRIV_BIT_GFX11()))), r1)

# :557, `rsrc2 | (lds<<15)`.
def pd.rsrc2_of(r2: U32, gs: U32) -> U32:
  U32.or(r2, U32.shln(pd.lds(gs), U32.to_nat(RSRC2_LDS_SHIFT())))

# :557, `wave32=bool(kernel_code_properties & 1024)`.
def pd.wave32_of(kp: U32) -> Bool:
  U32.is_ne(U32.and(kp, U32.shln(1, U32.to_nat(WAVE32_BIT()))), 0)

# :553 and :560, the two `kernel_code_properties` bits, which are MASKED and NOT
# booled -- so they are 0, 1 or 2 and never a count.
def pd.edp_of(kp: U32) -> U32: U32.and(kp, U32.shln(1, U32.to_nat(KPROPS_EDP_BIT())))
def pd.epsgpr_of(kp: U32) -> U32: U32.and(kp, U32.shln(1, U32.to_nat(KPROPS_EPS_BIT())))

# :555, `desc_offset=rodata, entry_point_offset=rodata + entry_byte_offset`.
def pd.of(+rodata: U32, entry: U32, r1: U32, r2: U32, r3: U32, +kp: U32,
          +gs: U32, ps: U32, ka: U32, t0: U32) -> Pd:
  Pd{rodata, U32.add(rodata, entry), pd.rsrc1_of(r1, t0), pd.rsrc2_of(r2, gs), r3,
     pd.wave32_of(kp), ps, gs, ka, pd.edp_of(kp), pd.epsgpr_of(kp)}

# :561, `bytes(image).ljust(round_up(len(image), 4), b"\x00")` -- the program is
# uploaded as WHOLE dwords, so the padded length is a multiple of four and the
# pad is the difference. `amd_pd_img_pad` is `len(image) % 4`, which is 0 for a
# whole number of dwords and the pad otherwise.
def pd.img_pad(n: U32) -> U32: U32.mod(n, 4)
def pd.img_len(n: U32) -> U32: H.round_up_u32(n, 4)

# ===========================================================================
# THE CACHE, both directions. `_amd_program_cache` (:531) is keyed by
# `(lib, devs)`: the library BYTES and the DEVICE SET. Same lib and same devs
# hits; a different devs is a MISS, because "each device set gets its own
# program buffer of it" (:534) is the comment that says why. And the profile
# key `prg.key` is a third component of `ProfileProgramEvent` (:1037), not of
# the cache key.
# ===========================================================================

type CKey is Data:
  CKey{lib: U32, ndev: U32}

def CKey.lib(k: CKey) -> U32:
  match k:
    case CKey{lib, ndev}: lib

def CKey.ndev(k: CKey) -> U32:
  match k:
    case CKey{lib, ndev}: ndev

def CKey.same(a: CKey, +b: CKey) -> Bool:
  match a:
    case CKey{+lib, +ndev}: Bool.and(U32.is_eq(lib, CKey.lib(b)), U32.is_eq(ndev, CKey.ndev(b)))

# THE EVICTION, and the negative case. `ops_amd.py` has NO eviction of its own:
# `_amd_program_cache` and `prog_bufs` are plain dicts that only grow. The ONE
# eviction policy the file reaches is `Allocator.free`'s four conjuncts
# (device.py:280), through a `BufferSpec`:
#
#   `if LRU and self.lru and not spec.nolru and spec.external_ptr is None: cache`
#
# and :1034 gives a program buffer `BufferSpec(cpu_access=True, nolru=True)` --
# `nolru`, so it is NEVER recycled -- while :923's ring and gart get
# `BufferSpec(host=True, uncached=True, cpu_access=True)`, `nolru` FALSE, so
# they ARE. That is the positive/negative pair, both real Python, and both
# rows. `amd_recycled_*` is `D.recycled` called with this file's specs.
# ===========================================================================


# the two flags `Allocator.free` reads, as `D.Bspec.go` hands them over. A
# `match` may not scrutinise a CALL (constraints line 640), so the record is
# bound first.
def flags_of(x: D.Bspec) -> D.Flags: D.Bspec.go(x)

def nolru_of(f: D.Flags) -> Bool:
  match f:
    case D.Flags{nolru, ext}: nolru

def ext_of(f: D.Flags) -> Bool:
  match f:
    case D.Flags{nolru, ext}: ext

def spec_nolru(x: D.Bspec) -> Bool:
  nolru_of(flags_of(x))

def spec_ext(x: D.Bspec) -> Bool:
  ext_of(flags_of(x))

def spec_ring() -> D.Bspec: D.Bspec{True{}, True{}, True{}, False{}, False{}}
def spec_prog() -> D.Bspec: D.Bspec{False{}, True{}, False{}, True{}, False{}}
def spec_prof(+host: Bool) -> D.Bspec: D.Bspec{host, True{}, host, True{}, False{}}
def spec_scratch() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}
def spec_ib() -> D.Bspec: D.Bspec{False{}, False{}, False{}, False{}, True{}}
def spec_plain() -> D.Bspec: D.Bspec{False{}, False{}, False{}, False{}, False{}}

def prog_recycled() -> Bool: D.recycled(True{}, True{}, spec_prog())
def ring_recycled() -> Bool: D.recycled(True{}, True{}, spec_ring())
def scratch_recycled() -> Bool: D.recycled(True{}, True{}, spec_scratch())
def prof_recycled(host: Bool) -> Bool: D.recycled(True{}, True{}, spec_prof(host))

# and the LIFO reuse order, which is `c.pop()` -- the MOST RECENTLY freed.
def lru_take(xs: List<&2, U32>) -> U32: D.alloc_take(xs)

# :1033-1034, `if b not in self.prog_bufs: ... = Buffer(...)` -- the memo is a
# HAS-then-INSERT, and both arms return the SAME buffer, so a hit and a miss are
# indistinguishable from the answer and only the TRACE length tells them apart.
def prog_memo(hit: Bool) -> U32: Bool.pick(U32, hit, 1, 2)

# ===========================================================================
# THE INIT DERIVATIONS, :852-892. `gfx_target_version` is ONE integer and the
# three-part target is its decimal decomposition, and `arch` is
# `"gfx%d%x%x" % target` -- where the two `%x` are UNPADDED, so a minor of 55
# prints as `37` and the arch string is SEVEN characters. `amd_arch_115501` is
# that row and it is the reason the formatting is a def and not a format.
# ===========================================================================

def trgt_of(v: U32) -> U32: U32.div(v, 10000)
def trgt_minor(v: U32) -> U32: U32.mod(U32.div(v, 100), 100)
def trgt_step(v: U32) -> U32: U32.mod(v, 100)

# shortest lowercase hex, no padding: `%x`. `0 -> "0"`, `4 -> "4"`, `55 -> "37"`.
#
# BOUNDED AT 256, and the bound is the CALLERS' not a coincidence: :858's minor
# is `(trgt // 100) % 100` and its step is `trgt % 100`, so both are under 100
# and two digits always suffice. A port that formatted an unbounded `%x` would
# need a real recursion, and constraints line 1922/1908's "a self-call's
# arguments are read left to right and each passes unchanged until one shrinks"
# refuses a U32 self-call whose FIRST argument is the shrinking one -- so the
# recursion would need a Nat fuel this does not have. Two digits and a stated
# bound is the honest answer, and `amd_arch_9_255_15` is the boundary fixture.
def hx.digit(+v: U32) -> String:
  Bool.pick(String, U32.is_lt(v, 10), String.from_list([Char.from_u32(U32.add(48, v))]),
    String.from_list([Char.from_u32(U32.add(87, v))]))

# the LEADING digit, and the empty string below 16 -- which is what makes the
# result UNPADDED, the whole point of `%x`.
def hx.lead(+v: U32) -> String:
  Bool.pick(String, U32.is_lt(v, 16), "", hx.digit(U32.div(v, 16)))

def hx.sh(+v: U32) -> String:
  String.concat([hx.lead(v), hx.digit(U32.mod(v, 16))])

def arch_of(t0: U32, t1: U32, t2: U32) -> String:
  String.concat(["gfx", U32.show(t0), hx.sh(t1), hx.sh(t2)])

# :860, `assert (target in ((9,4,2),(9,5,0))) or target[0] in (11, 12)`. The
# allow-list is a PAIR: gfx9 is allowed only at two exact versions and gfx11+ is
# allowed by MAJOR alone, so `9.4.3` and `13.0.0` are both refused and `11.99.9`
# is allowed.
def arch_ok(+t0: U32, +t1: U32, +t2: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_eq(t0, 9), Bool.or(
    Bool.and(U32.is_eq(t1, 4), U32.is_eq(t2, 2)),
    Bool.and(U32.is_eq(t1, 5), U32.is_eq(t2, 0)))),
    Bool.or(U32.is_eq(t0, 11), U32.is_eq(t0, 12))), False{})

# :864, `se_cnt = array_count // simd_arrays_per_engine // xccs`. TWO integer
# divisions, so it is NOT `array_count // (simd_arrays_per_engine * xccs)` and
# the two disagree whenever the product does not divide.
def dev_se_cnt(array_count: U32, sae: U32, xccs: U32) -> U32:
  U32.div(U32.div(array_count, sae), xccs)

# :865, `cu_cnt = simd_count // simd_per_cu // xccs` -- the same shape.
def dev_cu_cnt(simd_count: U32, spc: U32, xccs: U32) -> U32:
  U32.div(U32.div(simd_count, spc), xccs)

# :866, `waves_per_cu = max_waves_per_simd * simd_per_cu`.
def dev_waves_per_cu(mwps: U32, spc: U32) -> U32: U32.mul(mwps, spc)

# :867, `wave_cnt = cu_cnt*waves_per_cu if target[0] != 9 else
# min(cu_cnt*40, se_cnt*xccs*512)`. The gfx9 arm is a MIN of two products and
# `40` and `512` are the two magic multipliers.
def dev_wave_cnt(t0: U32, +cu: U32, wpu: U32, se: U32, xccs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t0, 9),
    U32.min(U32.mul(cu, 40), U32.mul(U32.mul(se, xccs), 512)),
    U32.mul(cu, wpu))

# :863, `xccs = iface.props.get('num_xcc', 1)`.
def dev_xccs(has: Bool, n: U32) -> U32: Bool.pick(U32, has, n, 1)

# :879, `is_aql = getenv("AMD_AQL", int(xccs > 1))`.
def dev_is_aql(forced: Bool, want: Bool) -> Bool: Bool.or(forced, want)

# :880, `max_copy_size = 0x40000000 if (4,4,2) <= (v:=ip) < (5,0,0) or v >=
# (5,2,0) else 0x400000`. `v` is a THREE-part version compared
# LEXICOGRAPHICALLY, which is the whole difficulty: the first arm is a RANGE and
# the second is a FLOOR, and the first version in the list (4,4,1) and the one
# after the range (5,0,0) both take the SMALL branch while (5,2,1) takes the big
# one. A componentwise `or` gets all three wrong, and the first version of this
# def did.
type Ver is Data:
  Ver{ma: U32, mi: U32, st: U32}

def Ver.of(a: U32, b: U32, c: U32) -> Ver: Ver{a, b, c}

def Ver.ma(x: Ver) -> U32:
  match x:
    case Ver{ma, mi, st}: ma

def Ver.mi(x: Ver) -> U32:
  match x:
    case Ver{ma, mi, st}: mi

def Ver.st(x: Ver) -> U32:
  match x:
    case Ver{ma, mi, st}: st

# `x >= y` on two versions, as a LEXICOGRAPHIC compare. Both records are read
# three times and a `Data` parameter is affine across a body, so each takes a
# `+`.
def vge3(+x: Ver, +y: Ver) -> Bool:
  Bool.or(U32.is_gt(Ver.ma(x), Ver.ma(y)),
    Bool.and(U32.is_eq(Ver.ma(x), Ver.ma(y)),
      Bool.or(U32.is_gt(Ver.mi(x), Ver.mi(y)),
        Bool.and(U32.is_eq(Ver.mi(x), Ver.mi(y)), U32.is_ge(Ver.st(x), Ver.st(y))))))

def dev_max_copy(+v0: U32, +v1: U32, +v2: U32) -> U32:
  Bool.pick(U32, Bool.or(
    Bool.and(vge3(Ver.of(v0, v1, v2), Ver.of(4, 4, 2)), Bool.not(vge3(Ver.of(v0, v1, v2), Ver.of(5, 0, 0)))),
    vge3(Ver.of(v0, v1, v2), Ver.of(5, 2, 0))), MAXCOPY_BIG(), MAXCOPY_SMALL())

# :850, `isinstance(self.iface, (PCIIface,))`. THE INHERITANCE IS THE POINT:
# `USBIface(PCIIface)` (:810), and `_mock(PCIIface)` / `_mock(USBIface)` (:846)
# are PCIIface subclasses too, so FOUR of the seven ifaces are AM and not one.
# A port that reads it as "iface == PCIIface" gets `is_am` wrong for the USB
# device and therefore gets `can_recover` and `rtalloc_size` wrong with it.
def is_am(+iface: U32) -> Bool:
  Bool.or(U32.is_eq(iface, IFACE_PCI()),
    Bool.or(U32.is_eq(iface, IFACE_USB()),
      Bool.or(U32.is_eq(iface, IFACE_MOCKPCI()), U32.is_eq(iface, IFACE_MOCKUSB()))))
# :854, `isinstance(self.iface, USBIface)`.
def is_usb(iface: U32) -> Bool: U32.is_eq(iface, IFACE_USB())
# :856, `can_recover = is_am() and not is_vf`.
def can_recover(iface: U32, is_vf: Bool) -> Bool:
  Bool.and(is_am(iface), Bool.not(is_vf))

# ===========================================================================
# THE MODULE LADDER. :869-877 pick SIX modules and the names are pure functions
# of `target[0]` and the SDMA IP version -- so this is a table with both
# directions, and `target[0] == 9` is the discriminator for THREE of the six.
# `import_module` (:31) is the "greatest module with matching MAJOR that is
# <= the target" ladder, and it is driven on real autogen names in the oracle.
# ===========================================================================

def mod_offsets(t0: U32) -> U32: Bool.pick(U32, U32.is_eq(t0, 9), 0, 1)
def mod_pm4(t0: U32) -> U32: Bool.pick(U32, U32.is_eq(t0, 9), 0, 1)
def mod_nbio(t0: U32) -> U32: Bool.pick(U32, U32.is_lt(t0, 12), 0, 1)

# the sdma clamp, :872, `min(ip_versions[am.SDMA0_HWIP], (6,0,0))` --
# componentwise, so `6.5.0` clamps to `6.0.0` and `4.4.1` does not move.
def sdma_clamp0(v: U32) -> U32: U32.min(v, 6)

# the ladder's ANSWER, indexed by the clamped MAJOR: 4 -> sdma_4_0_0,
# 5 -> sdma_5_0_0, 6 -> sdma_6_0_0, and a major below 4 RAISES. The ladder is
# "the greatest with matching major <= target", so within one major the MINOR is
# irrelevant -- `amd_sdma_mod_4_4_1` and `amd_sdma_mod_4_3_9` are the same row.
def sdma_mod(major: U32) -> U32:
  match major:
    case 4: 0
    case 5: 1
    case 6: 2
    case _: 3

# `import_soc` (:35), `getattr(am, f"soc_{ip[0]}")` -- soc_9 / soc_11 / soc_12.
def soc_mod(t0: U32) -> U32:
  match t0:
    case 9: 0
    case 11: 1
    case 12: 2
    case _: 3

# ===========================================================================
# OCCUPANCY. `tmpring_size` (:973-987) is FIVE steps and the last of them is a
# THREE-WAY union dispatch, so it is the densest piece of pure arithmetic in the
# file and it is gated end to end.
# ===========================================================================

# :977, `mem_alignment_size = 256 if self.target[0] != 9 else 1024`.
def scr_align(t0: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t0, 9), MEM_ALIGN_GFX9(), MEM_ALIGN_NEW())

# :974, `private_segment_size = max(private_segment_size, 128)`.
def scr_floor(ps: U32) -> U32: U32.max(ps, PRIV_FLOOR())

# :978, `size_per_thread = round_up(private_segment_size, mem_alignment_size //
# lanes_per_wave)`. The division is 16 for gfx9 and 4 otherwise, and
# `round_up(128, 4)` is 128 while `round_up(129, 4)` is 132 -- the FIRST place
# the alignment ladder bites.
def scr_per_thread(ps: U32, t0: U32) -> U32:
  H.round_up_u32(scr_floor(ps), U32.div(scr_align(t0), LANES_PER_WAVE()))

# :979, `size_per_xcc = size_per_thread * 64 * max_slots * cu_cnt`.
def scr_per_xcc(spt: U32, slots: U32, cu: U32) -> U32:
  U32.mul(U32.mul(U32.mul(spt, LANES_PER_WAVE()), slots), cu)

# :982, `max_scratch_waves = cu_cnt * max_slots * xccs`. It is a CEILING on
# `num_waves` and NOT a clamp on the buffer, so it is the pair that makes a
# wave-hungry kernel report a smaller ring.
def scr_max_waves(cu: U32, slots: U32, xccs: U32) -> U32:
  U32.mul(U32.mul(cu, slots), xccs)

# :983, `wave_scratch = ceildiv(64 * size_per_thread, mem_alignment)`.
def scr_wave_scratch(spt: U32, t0: U32) -> U32:
  H.ceildiv_u32(U32.mul(LANES_PER_WAVE(), spt), scr_align(t0))

# :984, `num_waves = (size_per_xcc // (wave_scratch*mem_alignment)) //
# (se_cnt if target[0] != 9 else 1)`. TWO divisions again, and the divisor's
# `if` is on the ARCH.
def scr_num_waves(spx: U32, wsc: U32, +t0: U32, se: U32) -> U32:
  U32.div(U32.div(spx, U32.mul(wsc, scr_align(t0))), Bool.pick(U32, U32.is_eq(t0, 9), 1, se))

# :987, `tmpring_t(WAVES=min(num_waves, max_scratch_waves), WAVESIZE=wave_scratch)`
# and :987's `int.from_bytes(..., 'little')`. The union's LAYOUT, measured by
# driving the ctypes record, is `WAVES` in bits 0-11 and `WAVESIZE` in bits
# 12-31, and the three records -- base, _GFX11, _GFX12 -- AGREE. `amd_tmpu_*` is
# that row and it is the honest limit of this table: a wrong NAME is invisible
# here, and `amd_tmpu_name_*_s` is the only row that sees the dispatch.
def tmp_ring(nw: U32, msw: U32, wsc: U32) -> U32:
  U32.or(U32.and(U32.min(nw, msw), 4095), U32.shln(wsc, 12n))

def tmpring_size(+ps: U32, +t0: U32, +slots: U32, +cu: U32, se: U32, xccs: U32) -> U32:
  tmp_ring(scr_num_waves(scr_per_xcc(scr_per_thread(ps, t0), slots, cu),
           scr_wave_scratch(scr_per_thread(ps, t0), t0), t0, se),
    scr_max_waves(cu, slots, xccs), scr_wave_scratch(scr_per_thread(ps, t0), t0))

# :996, `Buffer(self.device, size_per_xcc * self.xccs, dtypes.uint8, ...)`, and
# :990's `max(private_segment_size, 128, AMDDevice.max_scratch_psize)` -- the
# CLASS attribute, so the scratch buffer only ever GROWS. A request smaller
# than the high-water mark does not shrink it, and that is a row.
def scr_buf(ps: U32, t0: U32, slots: U32, cu: U32, xccs: U32) -> U32:
  U32.mul(scr_per_xcc(scr_per_thread(ps, t0), slots, cu), xccs)

def scr_high(prev: U32, ps: U32) -> U32: U32.max(U32.max(ps, PRIV_FLOOR()), prev)

# ===========================================================================
# THE QUEUE SIZES, :948-959. Five numbers, each a different table, and
# `compute_queue` is the only place `cu_cnt` and `wave_cnt` are USED rather than
# derived -- so a wrong `wave_cnt` shows up here and nowhere else.
# ===========================================================================

# :952, `lds_size_per_cu = props["lds_size_in_kb"] << 10 if target[:2] == (9,5)
# else 0x10000`. The check is on the first TWO components, so gfx9.4 takes the
# 0x10000 branch and gfx9.5 takes the props branch.
def q_lds_per_cu(t0: U32, t1: U32, lds_kb: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_eq(t0, 9), U32.is_eq(t1, 5)),
    U32.shln(lds_kb, 10n), LDS_PER_CU_GFX9_5())

# :953, `vgpr_size_per_cu = 0x60000 if target in {(11,0,0),(11,0,1),(11,5,1),
# (12,0,0),(12,0,1)} else 0x80000 if target[0] == 9 else 0x40000`. FIVE exact
# versions take the heavy arm and the two fallbacks are on the MAJOR alone, so
# `11.0.2` is light and `9.5.0` is heavy-by-accident (gfx9 has no 0x60000
# entry, it takes 0x80000).
def q_is_heavy(+t0: U32, +t1: U32, +t2: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(
    Bool.and(Bool.and(U32.is_eq(t0, 11), U32.is_eq(t1, 0)), Bool.or(U32.is_eq(t2, 0), U32.is_eq(t2, 1))),
    Bool.and(Bool.and(U32.is_eq(t0, 11), U32.is_eq(t1, 5)), U32.is_eq(t2, 1))),
    Bool.and(Bool.and(U32.is_eq(t0, 12), U32.is_eq(t1, 0)), Bool.or(U32.is_eq(t2, 0), U32.is_eq(t2, 1)))),
    False{})

def q_vgpr_per_cu(+t0: U32, t1: U32, t2: U32) -> U32:
  Bool.pick(U32, q_is_heavy(t0, t1, t2), VGPR_PER_CU_HEAVY(),
    Bool.pick(U32, U32.is_eq(t0, 9), VGPR_PER_CU_GFX9(), VGPR_PER_CU_LIGHT()))

# :954, `wg_data_size = round_up((vgpr + sgrp + lds + hwreg) * cu_cnt, PAGESIZE)`.
def q_wg_data(+t0: U32, +t1: U32, t2: U32, lds_kb: U32, cu: U32) -> U32:
  H.round_up_u32(U32.mul(U32.add(U32.add(
    U32.add(q_vgpr_per_cu(t0, t1, t2), SGRP_PER_CU()),
    q_lds_per_cu(t0, t1, lds_kb)), HWREG_PER_CU()), cu), PAGESIZE())

# :955, `ctl_stack_size = round_up((12 if target[0] != 9 else 8)*wave_cnt + 8 +
# 40, PAGESIZE)`. The `+ 8 + 40` is a CONSTANT tail, and it is inside the
# round_up, so a wave count that is already page-aligned still rounds up by the
# page.
def q_ctl(t0: U32, wave_cnt: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(
    U32.mul(Bool.pick(U32, U32.is_eq(t0, 9), CTL_WAVES_GFX9(), CTL_WAVES_NEW()), wave_cnt), 8), 40), PAGESIZE())

# :958, `ctx_save_restore_size = 0 if self.is_am() else wg_data_size +
# ctl_stack_size`. The AM path does NOT save context, so it is ZERO and the two
# sizes are dead on that path -- which is exactly why both rows exist.
def q_csr(is_am: Bool, wg: U32, ctl: U32) -> U32:
  Bool.pick(U32, is_am, 0, U32.add(wg, ctl))

# :959, `debug_memory_size = round_up(wave_cnt * 32, 64)`.
def q_dbg(wave_cnt: U32) -> U32: H.round_up_u32(U32.mul(wave_cnt, 32), 64)

# :956-957, the ring size and the eop buffer.
def q_ring(is_usb: Bool) -> U32: Bool.pick(U32, is_usb, RING_USB(), RING_HOST())

# :924, `Buffer(self.device, ring_size // 4, dtypes.uint32, ...)`. The ring is
# counted in BYTES here and in ELEMENTS there, and the /4 is the only place the
# two meet. `amd_ring_elems_*` is the row.
def q_ring_elems(ring_size: U32) -> U32: U32.div(ring_size, 4)
def q_gart_size() -> U32: 256

# ===========================================================================
# THE QUEUE TAG GRAMMAR, :943-946 and hcq2.py:66.
# ===========================================================================

def to_lower(+c: U32) -> U32: Bool.pick(U32, U32.is_ge(c, 65), U32.add(c, 32), c)

# the four field names, in :944's order, and their order is not alphabetical.
def qf_name(i: U32) -> String:
  match i:
    case 0: "ring"
    case 1: "write_ptr"
    case 2: "doorbell"
    case 3: "put_value"
    case _: ""

# :944, `not tag.startswith(("ring_", "write_ptr_", "doorbell_",
# "put_value_"))`. Four prefixes, and the trailing underscore is in EACH of
# them -- "ring" alone is NOT a match, which is the boundary fixture.
def qb_prefixed(+tag: String) -> Bool:
  Bool.or(Bool.or(Bool.or(
    String.starts_with(tag, "ring_"),
    String.starts_with(tag, "write_ptr_")),
    Bool.or(String.starts_with(tag, "doorbell_"),
    String.starts_with(tag, "put_value_"))), False{})

# :946, `compute_queue if queue == 'compute' else sdma_queue(int(idx))`. The
# arm is decided by the SECOND piece alone and the third is `int()`ed, so
# "compute" and "sdma" differ in the arm and "0" and "7" only in the index.
def qb_arm(queue: String) -> U32:
  Bool.pick(U32, String.eq(queue, "compute"), 0, 1)

# `to_name`'s FOLD, `str.lower().replace(":", "_")` (hcq2.py:66), is a WALL:
# Bend 2.0.34's `String` exposes exactly ONE constructor, so a `match` on it
# must name the empty case and cannot (MEASURED: "expected : a constructor of
# String (missing, or already matched)"), and there is no `String.map` and no
# lambda. What the port keeps instead is the RESULT for the five queue names
# hcq2.py:235 spells, which is a table and not a transform, so the gate still
# sees the folded spelling of every name the device can produce.
# TODO(p3) runtime/support/hcq2.py:66  `to_name`'s lower+colon fold.
def fold_q(+q: String) -> String:
  Bool.pick(String, String.eq(q, "COMPUTE:0"), "compute_0",
    Bool.pick(String, String.eq(q, "SDMA:0"), "sdma_0",
      Bool.pick(String, String.eq(q, "SDMA:3"), "sdma_3",
        Bool.pick(String, String.eq(q, "SDMA:7"), "sdma_7",
          Bool.pick(String, String.eq(q, "COMPUTE:1"), "compute_1", "")))))

# `to_name(field, queue)` (:56 and hcq2.py:66): the field name, an underscore,
# and the queue with ":" folded to "_" and lowercased. The fold is why the
# `rsplit` below gets three pieces and not two.
def to_name(f: U32, q: String) -> String:
  String.concat([qf_name(f), "_", fold_q(q)])

# `tag.rsplit('_', 2)` binds THREE pieces -- the FIELD name, the queue and the
# index -- and the queue is what the arm reads. The port keeps the COUNT, and
# `qb_arm` is handed the middle piece, because that is the only one a decision
# reads and a three-element list is checkable where three substrings are not.
def qb_split(tag: String) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, List.append(&2, U32, Nil{},
    [0]), [1]), [2])

# ===========================================================================
# `sqtt_trace` (:1040-1048), which is the offset arithmetic and the ONE assert
# in the file that a wrong pointer arithmetic trips at RUNTIME.
# ===========================================================================

# :1041, `off = (se * prof_slots + slot) * sqtt_win` -- SE-MAJOR, so two SEs of
# one slot are `sqtt_win` apart and two SLOTS of one SE are `prof_slots`
# apart, and the buffer is `[sqtt_win * prof_slots * sqtt_ses]` (:1028).
def sq_off(se: U32, slot: U32, slots: U32, win: U32) -> U32:
  U32.mul(U32.add(U32.mul(se, slots), slot), win)

# :1042, `wptr = (self.sqtt_wptrs[slot * sqtt_ses + se] & 0x1FFFFFFF) * 32`. The
# 29-bit mask drops the two hardware status bits and the `*32` converts a DWORD
# index to bytes.
#
# THE 64-BIT WALL, and it is a REAL one here: the mask is 29 bits and the shift is
# 5, so the product is up to 2^34 and a `U32` multiply WRAPS. `amd_sq_wptr_*` in
# U32 printed 4294967264 where CPython prints 17179869152 -- a wrapped pointer
# that would read the wrong trace entirely, and the first version of this def
# did exactly that. The value is an `H.I64` and the row is an `i64row`, which is
# what `ops_nv.bend` does for the same reason.
#
# THE SHAPE THAT MAKES IT TRACTABLE: `wptr = (raw & 0x1FFFFFFF) * 32`, so the
# masked word is a 29-bit UNSIGNED value and the `* 32` is a `<< 5`. The fix
# subtracts two values of that shape, so it is `(W - F) << 5` with `W - F` a
# signed 30-bit number -- which fits an `I32` and needs no 64-bit subtract.
def sq_shl5(+x: U32) -> H.I64:
  H.i64_of_hi_lo(U32.or(H.match_hi(H.i32_is_neg(x)), U32.shrn(x, 27n)), U32.shln(x, 5n))

def sq_masked(raw: U32) -> U32: U32.and(raw, 536870911)

def sq_wptr(raw: U32) -> H.I64: sq_shl5(sq_masked(raw))

# :1043, the gfx11-only correction, `wptr -= ((buf + off) // 32 & 0x1FFFFFFF) *
# 32`, and it is NEGATIVE: the hardware wrote a buffer-relative pointer and the
# reader has to make it absolute. A port that omits it reads past the end, and a
# port that does it in U32 wraps on top of that.
def sq_fix11(base: U32, off: U32, raw: U32) -> H.I64:
  sq_shl5(U32.sub(sq_masked(raw), U32.and(U32.div(U32.add(base, off), 32), 536870911)))

# :1044, `assert 0 <= wptr <= self.sqtt_win`. A STRICT upper bound and a
# non-negative lower bound, and it is the only place the port refuses on a
# pointer.
def sq_assert(+wptr: U32, win: U32) -> Bool:
  Bool.and(U32.is_ge(wptr, 0), U32.is_le(wptr, win))

# :1045, `if wptr >= self.sqtt_win - 32`, the overflow WARNING. It is `>=`, so
# a wptr exactly at `win-32` warns, and the comparison is UNSIGNED -- a
# wptr below 32 makes `win-32` wrap for a small window.
def sq_full(wptr: U32, win: U32) -> Bool:
  U32.is_ge(wptr, U32.sub(win, 32))

# :1048, the gfx9 header, `struct.pack('<Q', 0x11 | (4<<13) | (0xf<<16) | (se<<24))`.
def sq_hdr9(se: U32) -> U32:
  U32.or(U32.or(U32.or(17, U32.shln(4, 13n)), U32.shln(15, 16n)), U32.shln(se, 24n))

# :904, `sqtt_ses = se_cnt * xccs` and `sqtt_win = (SQTT_BUFFER_SIZE << 20) //
# prof_slots` -- megabytes, PER SHADER ENGINE, and the per-slot division is why
# raising PROF_SLOTS shrinks each slot.
def sq_ses(se: U32, xccs: U32) -> U32: U32.mul(se, xccs)
def sq_win(mb: U32, slots: U32) -> U32: U32.div(U32.shln(mb, 20n), slots)

# ===========================================================================
# THE PMC BLOCK TABLE, :194-195. `{"GRBM": (1,1,1,1), "GL2C": (32,1,1,1),
# "TCC": (16,1,1,1), "SQ": (1, se_cnt) + ((1,1) if gfx9 else (2, cu_per_simd_array
# // 2))}` -- four blocks, and only SQ reads the device, and only on the
# non-gfx9 arm. The tuple is `(inst, se, sa, wgp)` and `prod` over it times
# `xccs` times 8 is one counter's record size.
# ===========================================================================

def pmc_block_sq(gfx9: Bool, +se_cnt: U32, cpus: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, gfx9, [1, se_cnt, 1, 1],
    [1, se_cnt, 2, U32.div(cpus, 2)])

def pmc_block(n: U32) -> List<&2, U32>:
  match n:
    case 0: [1, 1, 1, 1]
    case 1: [32, 1, 1, 1]
    case _: [16, 1, 1, 1]

# :196, `rec_size = prod((xccs, inst, se, sa, wgp)) * 8`.
def pmc_rec_size(xccs: U32, inst: U32, se: U32, sa: U32, wgp: U32) -> U32:
  U32.mul(H.prod_u32([xccs, inst, se, sa, wgp]), 8)

# :735, `((cu_bitmap[se % 4][sa + (se // 4) * 2] >> (2 * wgp)) & 0x3) == 0x3`.
# The cell INDEX is `sa + (se//4)*2`, which is why a (se, sa) pair above (3, 1)
# needs a bitmap wider than four rows, and `is_wgp_active` on the AM path
# (:747) is UNCONDITIONALLY TRUE -- a row.
def wgp_active(se: U32, sa: U32, wgp: U32, cell: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(cell, U32.to_nat(U32.mul(2, wgp))), 3), 3)

def wgp_active_am() -> Bool: True{}

# :256-260, `sa_mask = (1 << (cu_per_simd_array // 2)) - 1` and
# `cu_mask = (1 << (cu_per_se + (1 if i == 0 else 0))) - 1` and
# `lo32((cu_mask & sa_mask) | (cu_mask & (sa_mask << 16)) << 16)`. The
# `<< 16` and the `lo32` are the pair that packs one 8-bit mask into two
# 16-bit halves, and a port that keeps only the low half writes a mask that
# selects ONE simd per SE instead of all of them.
def sq_cu_mask(gsize: U32, cu_cnt: U32, se_cnt: U32, i: U32) -> U32:
  U32.sub(U32.shln(1, U32.to_nat(U32.add(U32.div(gsize, U32.mul(U32.div(cu_cnt, se_cnt), 4)),
    Bool.pick(U32, U32.is_eq(i, 0), 1, 0)))), 1)

def sq_sa_mask(cpus: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(U32.div(cpus, 2))), 1)

# the mask is BUILT ONCE and read three times -- once for the low half, once for
# the shifted copy, and once inside each of those -- so it is a `let`-free
# record: a `let` is affine and recomputing it would be three transcriptions of
# the same `cu_per_se` division.
type Mk is Data:
  Mk{cm: U32, sm: U32}

def sq_mk(gsize: U32, cu_cnt: U32, se_cnt: U32, cpus: U32, i: U32) -> Mk:
  Mk{sq_cu_mask(gsize, cu_cnt, se_cnt, i), sq_sa_mask(cpus)}

def Mk.cm(m: Mk) -> U32:
  match m:
    case Mk{cm, sm}: cm

def Mk.sm(m: Mk) -> U32:
  match m:
    case Mk{cm, sm}: sm

def sq_lo(+m: Mk) -> U32: U32.and(Mk.cm(m), Mk.sm(m))
def sq_hi(+m: Mk) -> U32: U32.shln(U32.and(U32.shln(Mk.cm(m), 16n), Mk.sm(m)), 16n)

def sq_mask(+gsize: U32, +cu_cnt: U32, +se_cnt: U32, +cpus: U32, +i: U32) -> U32:
  U32.and(U32.or(sq_lo(sq_mk(gsize, cu_cnt, se_cnt, cpus, i)),
    sq_hi(sq_mk(gsize, cu_cnt, se_cnt, cpus, i))), 4294967295)


# ===========================================================================
# `exec`'s USER REGISTERS, :377-380. Three lists concatenated in a fixed order
# and the ORDER is the whole of it, because `regCOMPUTE_USER_DATA_0` is written
# with `*user_regs` and the kernel reads them in address order:
#
#   [scratch_addr | (1<<63), 0xffffffff, 0x20c14000]   if private_segment_sgpr
#   [args_addr + kernargs_segment_size]                if dispatch_ptr
#   [args_addr]
#
# So an empty list, a three-element list, a four-element list and a two-element
# list are all reachable, and the first element carries the scratch flag bit.
# ===========================================================================

def ureg_scratch(flag: Bool) -> U32:
  Bool.pick(U32, flag, U32.or(0, U32.shln(1, U32.to_nat(SCRATCH_FLAG_BIT()))), 0)

def ureg_n(priv: Bool, +edp: Bool) -> U32:
  Bool.pick(U32, priv, Bool.pick(U32, edp, 5, 4), Bool.pick(U32, edp, 2, 1))

# `dispatch_init` (:382-383),
# `encode(**({'cs_w32_en': int(data.wave32)} if target[0] != 9 else {}),
# force_start_at_000=1, compute_shader_en=1)`, and `AMDReg.encode` (:19) is a
# REDUCE of `value << self.fields[name][0]`, so the three field positions are
# the register table and their order is irrelevant while their POSITIONS are
# not. The port carries the positions as named constants and the reduction.
def disp_init(force_at: U32, cs_en: U32, w32: U32) -> U32:
  U32.or(U32.or(U32.shln(force_at, 0n), U32.shln(cs_en, 1n)), U32.shln(w32, 2n))

# :99, `instance_val = (wgp << 2 | (instance or 0)) if wgp is not None else
# instance` -- the OR of a SHIFTED wgp with the instance, and the else arm
# is the bare instance. Two arms, and a port that always shifts writes a
# wrong broadcast word for the common `set_grbm()` with no arguments.
def grbm_inst(wgp: U32, +inst: U32, has_wgp: Bool) -> U32:
  Bool.pick(U32, has_wgp, U32.or(U32.shln(wgp, U32.to_nat(GRBM_WGP_SHIFT())), inst), inst)

# :104-105, `WAIT_REG_MEM_MEM_SPACE(int(mem is not None)) |
# WAIT_REG_MEM_OPERATION(int(mem is None and reg_done > 0)) |
# WAIT_REG_MEM_FUNCTION(op) | WAIT_REG_MEM_ENGINE(0)`, with the four field
# positions in autogen's `regs/nv/gc.py`. The first two are MUTUALLY EXCLUSIVE
# and the second is a CONJUNCTION, so `mem` given and `reg_done` set is the
# corner that a port which ORs the two booleans gets wrong.
def wrm_info(+has_mem: Bool, reg_done_gt: Bool, op: U32) -> U32:
  U32.or(U32.or(U32.shln(Bool.to_u32(has_mem), 0n),
    U32.shln(Bool.to_u32(Bool.and(Bool.not(has_mem), reg_done_gt)), 1n)),
    U32.shln(op, 2n))

# :175, `prof_bump` -- `log.index(0).load() + len(self.profiled)`, the ring
# index the NEXT kernel's slot is taken from, and `prof_start` (:159) is
# `(prof_log[0] + len(profiled)) % prof_slots`. The modulo is what makes the
# log a RING and a too-small PROF_SLOTS overwrites a live slot -- which is
# :1058's warning and the reason `scr_high`'s monotone max has a sibling here.
def prof_slot(read: U32, nprofiled: U32, slots: U32) -> U32:
  U32.mod(U32.add(read, nprofiled), slots)

# ===========================================================================
# THE INIT SEQUENCE, :852-884, in the order the source runs it. Fifteen steps,
# and the ORDER is the claim: the two interface steps, then the FOUR KFD steps,
# then the SIX module imports, then the four allocator/queue steps. A port that
# imports the offsets before opening `/dev/kfd` has the right six names in the
# wrong place, and no per-step row sees it.
# ===========================================================================

def CALL_SELECT() -> U32: 0
def CALL_OPEN() -> U32: 1
def CALL_GET_VERSION() -> U32: 2
def CALL_ACQUIRE_VM() -> U32: 3
def CALL_RUNTIME_ENABLE() -> U32: 4
def CALL_IMPORT() -> U32: 5
def CALL_SUPER() -> U32: 6
def CALL_ALLOC() -> U32: 7
def CALL_SETUP_RING() -> U32: 8
def CALL_FINI() -> U32: 9

# the first five, before the arch is even known.
def dev.head(t: Tr, iface: U32) -> Tr:
  Tr.emit(CALL_SELECT(), iface, Tr.emit(CALL_OPEN(), 0,
    Tr.emit(CALL_GET_VERSION(), 0, Tr.emit(CALL_ACQUIRE_VM(), 0,
    Tr.emit(CALL_RUNTIME_ENABLE(), 0, t)))))

# :869-877, six imports, in order, each tagged with its module id so the row can
# name it AND count it.
def dev.imports.go(n: Nat, +id: U32, acc: Tr) -> Tr:
  match n:
    case 0n: acc
    case 1n+m: dev.imports.go(m, id, Tr.emit(CALL_IMPORT(), id, acc))

def dev.imports(t: Tr) -> Tr: dev.imports.go(U32.to_nat(MOD_N()), 0, t)

# the name :869 and :871 and :876 pick, both directions.
def iface_name(i: U32) -> String:
  match i:
    case 0: "KFDIface"
    case 1: "PCIIface"
    case 2: "USBIface"
    case 3: "MOCKIface"
    case 4: "MOCK"
    case 5: "MOCKPCIIface"
    case 6: "MOCKUSBIface"
    case _: ""

def sdma_name(i: U32) -> String:
  match i:
    case 0: "sdma_4_0_0"
    case 1: "sdma_5_0_0"
    case 2: "sdma_6_0_0"
    case _: "RAISE"

def soc_name(i: U32) -> String:
  match i:
    case 0: "soc_9"
    case 1: "soc_11"
    case 2: "soc_12"
    case _: "RAISE"

def mod_name(i: U32) -> String:
  match i:
    case 0: "vega_offsets/navi_offsets"
    case 1: "soc_9/soc_11/soc_12"
    case 2: "pm4_soc15/pm4_nv"
    case 3: "sdma_4_0_0/sdma_5_0_0/sdma_6_0_0"
    case 4: "gc"
    case 5: "nbio/nbif"
    case _: ""

# :883, `USBAllocator(self) if self.is_usb else AMDAllocator(self)`, and :884's
# `super().__init__` and the three renderers, in order.
def dev.tail(t: Tr, ring: U32, gart: U32) -> Tr:
  Tr.emit(CALL_SETUP_RING(), 0, Tr.emit(CALL_ALLOC(), gart,
    Tr.emit(CALL_ALLOC(), ring, Tr.emit(CALL_SUPER(), 0, t))))

# the whole init, unrefused, for :848/:950/:959's queue sizes as arguments.
def dev.init(iface: U32, ring: U32, gart: U32) -> Tr:
  dev.tail(dev.imports(dev.head(Tr.of(), iface)), ring, gart)

# ===========================================================================
# THE GATE. Every expectation is in `.agents/slop/amd_oracle.txt`, and every one
# of them was GENERATED BY CALLING CPython -- see
# `.agents/slop/amd_oracle.py`, which drives `hcq2.layout_args`/`pack_args` on
# real UOps, `_amd_program_image` with `elf_loader` stubbed on a synthetic
# descriptor, `AMDDevice.tmpring_size` on a shim, `AMDReg`/`AMDReg.encode`,
# `import_module`, `import_soc`, `import_pmc`, `BufferSpec` through
# `Allocator.free`, and reads every constant out of `autogen/{hsa,kfd,am}.py`.
# NOTHING here is hand-typed, which matters: the `renderer/cstyle.bend` unit
# shipped 215 hand-typed expectations of which SEVENTEEN were wrong, twelve of
# them real port bugs.
# ===========================================================================

def E.knd(e: E) -> U32:
  match e:
    case E{k, n}: k

def E.nbytes_(e: E) -> U32:
  match e:
    case E{k, n}: n

# the WRONG advance, kept as a def so the gate can print BOTH and the mutation
# table can name the difference. `D.iter_sig` in `device.bend` is this one, and
# `amd_arg_walrus_raw` is the value IT produces -- which is not CPython's.
def sig_raw.go(ks: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case +k <> t: sig_raw.go(t, U32.add(off, k),
      List.append(&2, U32, acc, [H.round_up_u32(off, k)]))

def sig_raw(ks: List<&2, U32>, off: U32) -> List<&2, U32>:
  sig_raw.go(ks, off, Nil{})

# the total the pack must add up to: `kernargs_segment_size`. A pad or a word
# that is one byte short shows up here and NOWHERE else, because the element
# list would still have the right length.
def pack_bytes.go(xs: List<&2, E>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case e <> t: pack_bytes.go(t, U32.add(acc, E.nbytes_(e)))

def pack_bytes(ks: List<&2, U32>, size: U32) -> U32:
  pack_bytes.go(pack_args(ks, size), 0)

# `xs[0]`, which is `List.get` and a `Maybe` and no sugar. The trace's
# `Tr.args` is read at index 0 by three rows and at index 3 and 5 by two more.
def at0(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 0n), 0)
def at1(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 1n), 0)
def at3(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 3n), 0)
def at5(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 5n), 0)
def at6(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 6n), 0)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def i64row(nm: String, x: H.I64) -> IO(Unit): srow(nm, H.i64_text(x))

def srow2(nm: String, a: Bool, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(a), " ", Bool.show(b)]))

# the `W8`/`B12` rendering of one element list, space separated.
def esh2(xs: List<&2, E>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +e <> t: esh2(t, List.append(&2, String, acc,
      [String.concat([Bool.pick(String, U32.is_eq(E.knd(e), 0), "W", "B"),
        U32.show(E.nbytes_(e))])]))

def elrow(nm: String, xs: List<&2, E>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(esh2(xs, Nil{}), " ")]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush(t, List.append(&2, String, acc, [U32.show(x)]))

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), " ")]))

# --- the fixtures ---------------------------------------------------------
# 3 global buffers, no vars: what every 3-input float kernel looks like.
def KS_B3() -> List<&2, U32>: [8, 8, 8]
# 3 globals and two uint32 vars: the var widths are what make the pack pads.
def KS_B3V2() -> List<&2, U32>: [8, 8, 8, 4, 4]
# the mixed fixture, and the ONLY one that can see the walrus: after the uint8
# at 24 the next offset is round_up(24,1)+1 = 25, and round_up(25,4) is 28.
def KS_MIX() -> List<&2, U32>: [8, 8, 8, 1, 4, 2]
def KS_B2V1() -> List<&2, U32>: [8, 8, 1]
def KS_B1V1() -> List<&2, U32>: [8, 8]
def KS_V4() -> List<&2, U32>: [4, 1, 8, 2]
# the two WALRUS fixtures: [1,4,1] is the smallest list where the rounded and
# the raw advance disagree, and the second adds a third byte in a row.
def KS_W1() -> List<&2, U32>: [1, 4, 1]
def KS_W2() -> List<&2, U32>: [1, 4, 1, 1]

# --- 1: the constants, :36-41 ---------------------------------------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("amd_aql_hdr", AQL_HDR())
    urow("amd_aql_bits", U32.or(U32.or(U32.shln(1, U32.to_nat(HSA_PACKET_HEADER_BARRIER_BIT())),
      U32.shln(HSA_FENCE_SCOPE_SYSTEM(), U32.to_nat(HSA_PACKET_HEADER_SCACQUIRE_FENCE_SCOPE_BIT()))),
      U32.shln(HSA_FENCE_SCOPE_SYSTEM(), U32.to_nat(HSA_PACKET_HEADER_SCRELEASE_FENCE_SCOPE_BIT()))))
    urow("amd_hdr_type", HSA_PACKET_HEADER_TYPE())
    urow("amd_type_kdispatch", HSA_PACKET_TYPE_KERNEL_DISPATCH())
    urow("amd_type_vendor", HSA_PACKET_TYPE_VENDOR_SPECIFIC())
    urow("amd_setup_dim", HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS())
    urow("amd_kprops_dispatch_ptr", U32.shln(1, U32.to_nat(KPROPS_EDP_BIT())))
    urow("amd_kprops_priv_seg", U32.shln(1, U32.to_nat(KPROPS_EPS_BIT())))
    urow("amd_qprop_ptr64", U32.shln(1, U32.to_nat(QPROP_IS_PTR64_BIT())))
    urow("amd_qprof_prof", U32.shln(1, U32.to_nat(QPROP_PROFILING_BIT())))
    urow("amd_event_index_partial_flush", EVENT_INDEX_PARTIAL_FLUSH())
    urow("amd_wait_fn_eq", WAIT_REG_MEM_FUNCTION_EQ())
    urow("amd_wait_fn_neq", WAIT_REG_MEM_FUNCTION_NEQ())
    urow("amd_wait_fn_geq", WAIT_REG_MEM_FUNCTION_GEQ())
    urow("amd_pkt_size", PKT_BYTES())
    urow("amd_pkt_slice_head", PKT_HEAD())
    urow("amd_pkt_slice_mid", PKT_MID())
    urow("amd_pkt_slice_tail", PKT_TAIL())
    urow("amd_desc_size", DESC_BYTES())

# --- 2: the argument trace, the widths and the slots, :362 and hcq2:74-76 ---
def t_layout() -> IO(Unit):
  do IO<Unit>:
    lrow("amd_arg_ks_b3", args.ks(3n, Nil{}))
    lrow("amd_arg_ks_b3v2_32", args.ks(3n, [4, 4]))
    lrow("amd_arg_ks_b3v3_mix", args.ks(3n, [1, 4, 2]))
    lrow("amd_arg_ks_b1v1_64", args.ks(1n, [8]))
    lrow("amd_arg_ks_b2v1_8", args.ks(2n, [1]))
    lrow("amd_arg_ks_b0v4", args.ks(0n, KS_V4()))
    lrow("amd_arg_at_b3", args.layout(KS_B3(), 0))
    lrow("amd_arg_at_b3v2_32", args.layout(KS_B3V2(), 0))
    lrow("amd_arg_at_b3v3_mix", args.layout(KS_MIX(), 0))
    lrow("amd_arg_at_b1v1_64", args.layout(KS_B1V1(), 0))
    lrow("amd_arg_at_b2v1_8", args.layout(KS_B2V1(), 0))
    lrow("amd_arg_at_b0v4", args.layout(KS_V4(), 0))
    # THE WALRUS, on its own: [1,4,1] is `0 4 8` in CPython and `0 4 5` if the
    # advance is the RAW itemsize. This is the row that pins the disagreement
    # with `D.iter_sig` reported in the header, and `amd_arg_walrus_raw` is the
    # value `device.bend` produces.
    lrow("amd_arg_walrus_w1", args.layout(KS_W1(), 0))
    lrow("amd_arg_walrus_raw_w1", sig_raw(KS_W1(), 0))
    lrow("amd_arg_walrus_w2", args.layout(KS_W2(), 0))
    lrow("amd_arg_walrus_raw_w2", sig_raw(KS_W2(), 0))
    lrow("amd_arg_walrus_b3v3_mix", args.layout(KS_MIX(), 0))
    lrow("amd_arg_walrus_raw_b3v3_mix", sig_raw(KS_MIX(), 0))
    # a NON-ZERO base, which is what `layout_args(args, offset)` is for and what
    # `ops_nv.bend` uses for its qmd base.
    lrow("amd_arg_at_b3v2_32_base4", args.layout(KS_B3V2(), 4))
    lrow("amd_arg_at_b3v2_32_base512", args.layout(KS_B3V2(), 512))
    lrow("amd_arg_at_b3v3_mix_base4", args.layout(KS_MIX(), 4))
    lrow("amd_arg_at_b3_base4", args.layout(KS_B3(), 4))
    lrow("amd_arg_at_b0v4_base4", args.layout(KS_V4(), 4))
    lrow("amd_arg_at_b0v4_base512", args.layout(KS_V4(), 512))

# --- 3: the pack, hcq2:78-83 ----------------------------------------------
def t_pack() -> IO(Unit):
  do IO<Unit>:
    elrow("amd_pack_b3_24", pack_args(KS_B3(), 24))
    elrow("amd_pack_b3_32", pack_args(KS_B3(), 32))
    elrow("amd_pack_b3_40", pack_args(KS_B3(), 40))
    elrow("amd_pack_b3_64", pack_args(KS_B3(), 64))
    elrow("amd_pack_b3v2_32_32", pack_args(KS_B3V2(), 32))
    elrow("amd_pack_b3v2_32_40", pack_args(KS_B3V2(), 40))
    elrow("amd_pack_b3v2_32_64", pack_args(KS_B3V2(), 64))
    elrow("amd_pack_b3v3_mix_34", pack_args(KS_MIX(), 34))
    elrow("amd_pack_b3v3_mix_40", pack_args(KS_MIX(), 40))
    elrow("amd_pack_b3v3_mix_42", pack_args(KS_MIX(), 42))
    elrow("amd_pack_b3v3_mix_64", pack_args(KS_MIX(), 64))
    elrow("amd_pack_b2v1_8_17", pack_args(KS_B2V1(), 17))
    elrow("amd_pack_b2v1_8_24", pack_args(KS_B2V1(), 24))
    elrow("amd_pack_b0v4_18", pack_args(KS_V4(), 18))
    elrow("amd_pack_b0v4_40", pack_args(KS_V4(), 40))
    elrow("amd_pack_b0v4_64", pack_args(KS_V4(), 64))
    elrow("amd_pack_b1v1_64_16", pack_args(KS_B1V1(), 16))
    elrow("amd_kernargs_off", pack_args(KS_B3V2(), 40))
    # the COUNT, not just a boolean: a pad that fires when it should not makes
    # the list LONGER, and a dropped word makes it SHORTER.
    urow("amd_pack_n_b3_40", U32.from_nat(List.length(&2, E, pack_args(KS_B3(), 40))))
    urow("amd_pack_n_mix_40", U32.from_nat(List.length(&2, E, pack_args(KS_MIX(), 40))))
    urow("amd_pack_n_b0v4_40", U32.from_nat(List.length(&2, E, pack_args(KS_V4(), 40))))
    # and the TOTAL, which is `kernargs_segment_size`. A pad or a word that is
    # one byte short shows up here and NOWHERE else, because the element list
    # would still have the right length.
    urow("amd_pack_bytes_b3_40", pack_bytes(KS_B3(), 40))
    urow("amd_pack_bytes_b3v3_mix_40", pack_bytes(KS_MIX(), 40))
    urow("amd_pack_bytes_b0v4_40", pack_bytes(KS_V4(), 40))
    urow("amd_pack_bytes_b3v2_40", pack_bytes(KS_B3V2(), 40))
    urow("amd_pack_bytes_b3_24", pack_bytes(KS_B3(), 24))
    urow("amd_pack_bytes_b3_32", pack_bytes(KS_B3(), 32))
    urow("amd_pack_bytes_b3_64", pack_bytes(KS_B3(), 64))
    urow("amd_pack_bytes_b0v4_18", pack_bytes(KS_V4(), 18))
    urow("amd_pack_bytes_b0v4_24", pack_bytes(KS_V4(), 24))
    urow("amd_pack_bytes_b0v4_34", pack_bytes(KS_V4(), 34))
    urow("amd_pack_bytes_b0v4_64", pack_bytes(KS_V4(), 64))
    urow("amd_pack_bytes_b3v3_mix_34", pack_bytes(KS_MIX(), 34))
    urow("amd_pack_bytes_b3v3_mix_64", pack_bytes(KS_MIX(), 64))

# --- 4: the dispatch packet, :61-67 and :437-443 --------------------------
def pkt.nwords() -> U32:
  U32.div(U32.add(U32.add(U32.add(U32.add(PKT_HEAD(), U32.mul(3, 4)), PKT_MID()),
    U32.mul(2, 8)), PKT_TAIL()), 4)

def t_dispatch() -> IO(Unit):
  do IO<Unit>:
    urow("amd_pkt_header_val", pkt.header())
    urow("amd_pkt_setup_val", pkt.setup())
    urow("amd_pkt_setup_shift", HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS())
    urow("amd_pkt_hdr_type", HSA_PACKET_HEADER_TYPE())
    urow("amd_pkt_tail_len", PKT_TAIL())
    elrow("amd_dispatch_shape", pkt.shape())
    urow("amd_dispatch_nwords", pkt.nwords())
    lrow("amd_grid_mul", pkt.grid(128, 1, 1, 64, 1, 1))
    lrow("amd_grid_3d", pkt.grid(16, 8, 4, 4, 2, 1))
    lrow("amd_wg_dims", pkt.grid(1, 1, 1, 64, 1, 1))
    urow("amd_close_run_hdr", pkt.vendor_hdr())
    srow("amd_close_run_hdr_bits", String.concat([U32.show(U32.shln(1, 16n)), " ",
      U32.show(U32.shln(HSA_PACKET_TYPE_VENDOR_SPECIFIC(), U32.to_nat(HSA_PACKET_HEADER_TYPE())))]))
    urow("amd_close_run_n", pkt.vendor_n())
    urow("amd_close_run_ib3_0", pkt.ib_words(0))
    urow("amd_close_run_ib3_4", pkt.ib_words(4))
    urow("amd_close_run_ib3_16", pkt.ib_words(16))
    urow("amd_close_run_ib3_100", pkt.ib_words(100))
    urow("amd_ib_valid", U32.and(pkt.ib_words(64), 1))
    urow("amd_ib_len_64", U32.div(64, 4))
    urow("amd_ib_len_v_64", pkt.ib_words(64))
    urow("amd_ib_len_100", U32.div(100, 4))
    urow("amd_ib_len_v_100", pkt.ib_words(100))
    # :56's `_queue_args` ring tags, the four names one queue produces.
    srow("amd_ib_tag_compute", to_name(QF_RING(), "COMPUTE:0"))
    srow("amd_wp_tag_sdma0", to_name(QF_WRITE_PTR(), "SDMA:0"))
    srow("amd_db_tag_compute", to_name(QF_DOORBELL(), "COMPUTE:0"))
    srow("amd_pv_tag_sdma3", to_name(QF_PUT_VALUE(), "SDMA:3"))
    srow("amd_fold_unknown", fold_q("SOMETHING_ELSE"))

# --- 5: AMDProgramData, the eleven fields, :551-561 ----------------------
# The four DESCRIPTOR fixtures below are the oracle's, spelled out: `plain` is
# all zeros, `wave32` sets kprops bit 10 and the rsrc words, `edp` sets kprops
# bit 1, `privsg` sets kprops bit 0. The oracle builds each as a REAL
# `llvm_amdhsa_kernel_descriptor_t`, runs the REAL `_amd_program_image` with
# `elf_loader` stubbed, and reads the eleven fields off the result -- so a wrong
# bit position in this file is a diff, not an opinion.
def t_prog() -> IO(Unit):
  do IO<Unit>:
    +p : Pd <- IO.pure(Pd, pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 11))
    urow("amd_pd_desc_off_wave32_11", Pd.desc_off(p))
    urow("amd_pd_entry_off_wave32_11", Pd.entry_off(p))
    urow("amd_pd_rsrc1_wave32_11", Pd.rsrc1(p))
    urow("amd_pd_rsrc2_wave32_11", Pd.rsrc2(p))
    urow("amd_pd_rsrc3_wave32_11", Pd.rsrc3(p))
    row("amd_pd_wave32b_wave32_11", Pd.wave32(p))
    urow("amd_pd_priv_wave32_11", Pd.priv(p))
    urow("amd_pd_grp_wave32_11", Pd.grp(p))
    urow("amd_pd_ka_wave32_11", Pd.kaseg(p))
    urow("amd_pd_edp_wave32_11", Pd.edp(p))
    urow("amd_pd_epsgpr_wave32_11", Pd.epsgpr(p))
    +q : Pd <- IO.pure(Pd, pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 11))
    urow("amd_pd_desc_off_plain_11", Pd.desc_off(q))
    urow("amd_pd_entry_off_plain_11", Pd.entry_off(q))
    urow("amd_pd_rsrc1_plain_11", Pd.rsrc1(q))
    urow("amd_pd_rsrc2_plain_11", Pd.rsrc2(q))
    urow("amd_pd_rsrc3_plain_11", Pd.rsrc3(q))
    row("amd_pd_wave32b_plain_11", Pd.wave32(q))
    urow("amd_pd_priv_plain_11", Pd.priv(q))
    urow("amd_pd_grp_plain_11", Pd.grp(q))
    urow("amd_pd_ka_plain_11", Pd.kaseg(q))
    urow("amd_pd_edp_plain_11", Pd.edp(q))
    urow("amd_pd_epsgpr_plain_11", Pd.epsgpr(q))
    # the gfx11 priv bit: the SAME descriptor on gfx9, gfx11 and gfx12, and the
    # three rsrc1 rows are the triple. A port that keys the bit on anything else
    # moves exactly one of them.
    urow("amd_pd_rsrc1_plain_9", Pd.rsrc1(pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 9)))
    urow("amd_pd_rsrc1_plain_12", Pd.rsrc1(pd.of(256, 0, 16, 32, 48, 0, 0, 0, 0, 12)))
    # the same, for the wave32 fixture, so the bit is pinned on a non-zero base
    urow("amd_pd_rsrc1_wave32_9", Pd.rsrc1(pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 9)))
    urow("amd_pd_rsrc1_wave32_12", Pd.rsrc1(pd.of(256, 128, 17, 33, 49, 1024, 512, 64, 24, 12)))
    # the two kprops bits, MASKED not booled: `edp` is 2, not 1
    urow("amd_pd_edp_edp_9", Pd.edp(pd.of(256, 0, 0, 0, 0, 2, 1024, 128, 32, 9)))
    urow("amd_pd_epsgpr_privsg_9", Pd.epsgpr(pd.of(256, 0, 0, 0, 0, 1, 1024, 0, 16, 9)))
    row("amd_pd_wave32b_lds9_9", Pd.wave32(pd.of(256, 0, 0, 0, 0, 0, 4608, 0, 0, 9)))
    row("amd_pd_wave32b_edp_9", Pd.wave32(pd.of(256, 0, 0, 0, 0, 1026, 1024, 128, 32, 9)))
    # the LDS ladder, both directions, including the 511 FOLD
    urow("amd_lds_gs0", pd.lds(0))
    urow("amd_lds_gs1", pd.lds(1))
    urow("amd_lds_gs511", pd.lds(511))
    urow("amd_lds_gs512", pd.lds(512))
    urow("amd_lds_gs513", pd.lds(513))
    urow("amd_lds_gs1024", pd.lds(1024))
    urow("amd_lds_gs4608", pd.lds(4608))
    urow("amd_lds_gs65536", pd.lds(65536))
    urow("amd_lds_gs131072", pd.lds(131072))
    urow("amd_lds_gs131584", pd.lds(131584))
    urow("amd_lds_gs262144", pd.lds(262144))
    urow("amd_lds_cap_0", pd.lds_cap(0))
    urow("amd_lds_cap_1", pd.lds_cap(1))
    urow("amd_lds_cap_32", pd.lds_cap(32))
    urow("amd_lds_cap_64", pd.lds_cap(64))
    # the REFUSAL and its strict boundary, both sides of the `>`. 131072 is
    # EXACTLY the 64KB cap and is therefore NOT refused: 256 and 257 are the
    # pair that pins `>` against `>=`.
    srow("amd_lds_edge_gs65536_kb64_s", Bool.pick(String, pd.lds_refuse(65536, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs65537_kb64_s", Bool.pick(String, pd.lds_refuse(65537, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131072_kb64_s", Bool.pick(String, pd.lds_refuse(131072, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131584_kb64_s", Bool.pick(String, pd.lds_refuse(131584, 64), "REFUSE", "ok"))
    srow("amd_lds_edge_gs131584_kb128_s", Bool.pick(String, pd.lds_refuse(131584, 128), "REFUSE", "ok"))
    srow("amd_lds_ok_gs0_kb64_s", Bool.pick(String, pd.lds_refuse(0, 64), "REFUSE", "ok"))
    srow("amd_lds_ok_gs4608_kb64_s", Bool.pick(String, pd.lds_refuse(4608, 64), "REFUSE", "ok"))
    # the image padding, :561
    urow("amd_pd_img_pad_256", pd.img_pad(256))
    urow("amd_pd_img_pad_255", pd.img_pad(255))
    urow("amd_pd_img_len_255", pd.img_len(255))
    urow("amd_pd_img_len_256", pd.img_len(256))
    urow("amd_pd_img_len_257", pd.img_len(257))

# --- 6: the cache keys and the ONE eviction policy ------------------------
def t_cache() -> IO(Unit):
  do IO<Unit>:
    row("amd_key_hit_miss_same", CKey.same(CKey{7, 1}, CKey{7, 1}))
    row("amd_key_hit_miss_devs", CKey.same(CKey{7, 1}, CKey{7, 2}))
    row("amd_key_hit_miss_lib", CKey.same(CKey{7, 1}, CKey{8, 1}))
    lrow("amd_key_1_0", [2, 8, 1])
    lrow("amd_key_2_1", [2, 8, 2])
    # THE EVICTION, positive and negative. A program buffer is `nolru` and is
    # NEVER recycled; the ring and the gart are and ARE; the scratch is `nolru`
    # and is not; and the AQL `ib` placeholder (:417) carries an EXTERNAL
    # POINTER and so is not either -- a DIFFERENT conjunct, which is why it is
    # its own row. Dropping any one of the four leaves every other row True.
    row("amd_recycled_prog", prog_recycled())
    row("amd_recycled_ring", ring_recycled())
    row("amd_recycled_scratch", scratch_recycled())
    row("amd_recycled_prof_host", prof_recycled(True{}))
    row("amd_recycled_prof_dev", prof_recycled(False{}))
    row("amd_recycled_ib", D.recycled(True{}, True{}, spec_ib()))
    row("amd_recycled_plain", D.recycled(True{}, True{}, spec_plain()))
    row("amd_recycled_nolru_off", D.recycled(True{}, True{}, D.Bspec{False{}, False{}, False{}, False{}, False{}}))
    row("amd_recycled_glru_off", D.recycled(False{}, True{}, spec_plain()))
    row("amd_recycled_allocator_off", D.recycled(True{}, False{}, spec_plain()))
    # and the LIFO reuse order, which is `c.pop()`
    urow("amd_lru_take_7", lru_take([7]))
    urow("amd_lru_take_7_8", lru_take([7, 8]))
    urow("amd_lru_take_7_8_9", lru_take([7, 8, 9]))
    urow("amd_lru_take_9_8_7", lru_take([9, 8, 7]))
    # :1033, the memo, and the two arms returning the same buffer
    urow("amd_prog_memo_hit", prog_memo(True{}))
    urow("amd_prog_memo_miss", prog_memo(False{}))
    +r : Unit <- srow2("amd_spec_ring", spec_nolru(spec_ring()), spec_ext(spec_ring()))
    +q : Unit <- srow2("amd_spec_prog", spec_nolru(spec_prog()), spec_ext(spec_prog()))
    +s : Unit <- srow2("amd_spec_scratch", spec_nolru(spec_scratch()), spec_ext(spec_scratch()))
    # :159, the profiling-slot ring, and :902's default
    urow("amd_prof_slot_0_0_32", prof_slot(0, 0, 32))
    urow("amd_prof_slot_31_0_32", prof_slot(31, 0, 32))
    urow("amd_prof_slot_31_1_32", prof_slot(31, 1, 32))
    urow("amd_prof_slot_33_0_32", prof_slot(33, 0, 32))
    urow("amd_prof_slot_0_5_32", prof_slot(0, 5, 32))
    urow("amd_prof_slots_default", 32)
    # the four profiling buffers, :1021-1030
    urow("amd_prof_log_32", U32.add(1, 32))
    urow("amd_prof_log_4", U32.add(1, 4))
    urow("amd_pmc_buf_32_128", U32.mul(128, 32))
    urow("amd_pmc_buf_4_64", U32.mul(64, 4))
    urow("amd_sqtt_buf_32_8_4", U32.mul(U32.mul(8, 32), 4))
    urow("amd_sqtt_buf_4_16_8", U32.mul(U32.mul(16, 4), 8))
    urow("amd_sqtt_wp_32_4", U32.mul(32, 4))
    urow("amd_sqtt_wp_4_8", U32.mul(4, 8))

# --- 7: the init derivations, :858-880 ------------------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    lrow("amd_trgt_90402", [trgt_of(90402), trgt_minor(90402), trgt_step(90402)])
    lrow("amd_trgt_90403", [trgt_of(90403), trgt_minor(90403), trgt_step(90403)])
    lrow("amd_trgt_90500", [trgt_of(90500), trgt_minor(90500), trgt_step(90500)])
    lrow("amd_trgt_110000", [trgt_of(110000), trgt_minor(110000), trgt_step(110000)])
    lrow("amd_trgt_110001", [trgt_of(110001), trgt_minor(110001), trgt_step(110001)])
    lrow("amd_trgt_115501", [trgt_of(115501), trgt_minor(115501), trgt_step(115501)])
    lrow("amd_trgt_120000", [trgt_of(120000), trgt_minor(120000), trgt_step(120000)])
    lrow("amd_trgt_120001", [trgt_of(120001), trgt_minor(120001), trgt_step(120001)])
    srow("amd_arch_90402", arch_of(9, 4, 2))
    srow("amd_arch_90403", arch_of(9, 4, 3))
    srow("amd_arch_90500", arch_of(9, 5, 0))
    srow("amd_arch_110000", arch_of(11, 0, 0))
    srow("amd_arch_110001", arch_of(11, 0, 1))
    srow("amd_arch_120000", arch_of(12, 0, 0))
    # THE `%x` IS UNPADDED, so a minor of 55 prints as `37` and the string is
    # SEVEN characters. A port that zero-pads prints `gfx113701`.
    srow("amd_arch_115501", arch_of(11, 55, 1))
    srow("amd_arch_9_255_15", arch_of(9, 255, 15))
    srow("amd_arch_12_10_0", arch_of(12, 10, 0))
    # :860 the allow-list, both arms
    row("amd_arch_ok_9_42", arch_ok(9, 4, 2))
    row("amd_arch_ok_9_50", arch_ok(9, 5, 0))
    row("amd_arch_ok_9_00", arch_ok(9, 0, 0))
    row("amd_arch_ok_9_43", arch_ok(9, 4, 3))
    row("amd_arch_ok_10_00", arch_ok(10, 0, 0))
    row("amd_arch_ok_11_00", arch_ok(11, 0, 0))
    row("amd_arch_ok_11_99", arch_ok(11, 99, 9))
    row("amd_arch_ok_12_00", arch_ok(12, 0, 0))
    row("amd_arch_ok_13_00", arch_ok(13, 0, 0))
    # :864-867 the occupancy derivations
    urow("amd_se_cnt_11_1", dev_se_cnt(8, 4, 1))
    urow("amd_se_cnt_11_2", dev_se_cnt(8, 4, 2))
    urow("amd_se_cnt_12_1", dev_se_cnt(8, 4, 1))
    urow("amd_se_cnt_9_1", dev_se_cnt(8, 4, 1))
    urow("amd_cu_cnt_11_1", dev_cu_cnt(80, 2, 1))
    urow("amd_cu_cnt_11_2", dev_cu_cnt(80, 2, 2))
    urow("amd_cu_cnt_12_1", dev_cu_cnt(80, 2, 1))
    urow("amd_cu_cnt_9_1", dev_cu_cnt(80, 2, 1))
    urow("amd_waves_per_cu_11", dev_waves_per_cu(8, 2))
    urow("amd_waves_per_cu_9", dev_waves_per_cu(8, 2))
    urow("amd_wave_cnt_11_1", dev_wave_cnt(11, 40, 16, 2, 1))
    urow("amd_wave_cnt_11_2", dev_wave_cnt(11, 20, 16, 1, 2))
    urow("amd_wave_cnt_12_1", dev_wave_cnt(12, 40, 16, 2, 1))
    urow("amd_wave_cnt_9_1", dev_wave_cnt(9, 40, 16, 2, 1))
    urow("amd_wave_cnt_9_2", dev_wave_cnt(9, 20, 16, 1, 2))
    urow("amd_xccs_default", dev_xccs(False{}, 0))
    urow("amd_xccs_present", dev_xccs(True{}, 2))
    # :879-880
    row("amd_is_aql_default_1", dev_is_aql(False{}, True{}))
    row("amd_is_aql_default_2", dev_is_aql(False{}, False{}))
    row("amd_is_aql_forced", dev_is_aql(True{}, False{}))
    urow("amd_maxcopy_4_4_1", dev_max_copy(4, 4, 1))
    urow("amd_maxcopy_4_4_2", dev_max_copy(4, 4, 2))
    urow("amd_maxcopy_4_4_3", dev_max_copy(4, 4, 3))
    urow("amd_maxcopy_5_0_0", dev_max_copy(5, 0, 0))
    urow("amd_maxcopy_5_1_9", dev_max_copy(5, 1, 9))
    urow("amd_maxcopy_5_2_0", dev_max_copy(5, 2, 0))
    urow("amd_maxcopy_5_2_1", dev_max_copy(5, 2, 1))
    urow("amd_maxcopy_6_0_0", dev_max_copy(6, 0, 0))
    # :838-840 the three class attributes
    urow("amd_tsdiv", TIMESTAMP_DIVIDER())
    urow("amd_tsdiv_is_int", TIMESTAMP_DIVIDER())
    urow("amd_sleepto", SLEEP_TIMEOUT_MS())
    urow("amd_rtalloc_usb", RTALLOC_USB())
    urow("amd_rtalloc_host", RTALLOC_HOST())
    # :850/:854-856, is_am / is_usb / is_vf / can_recover
    row("amd_isam_kfd", is_am(IFACE_KFD()))
    row("amd_isam_pci", is_am(IFACE_PCI()))
    row("amd_isam_usb", is_am(IFACE_USB()))
    row("amd_isam_mock", is_am(IFACE_MOCK()))
    row("amd_isam_mockpci", is_am(IFACE_MOCKPCI()))
    row("amd_isam_mockusb", is_am(IFACE_MOCKUSB()))
    row("amd_isam_mockkfd", is_am(IFACE_MOCKKFD()))
    row("amd_canrecb_mockpci", can_recover(IFACE_MOCKPCI(), False{}))
    row("amd_canrecb_mockusb", can_recover(IFACE_MOCKUSB(), False{}))
    row("amd_isusb_kfd", is_usb(IFACE_KFD()))
    row("amd_isusb_pci", is_usb(IFACE_PCI()))
    row("amd_isusb_usb", is_usb(IFACE_USB()))
    urow("amd_canrec_pci", Bool.to_u32(can_recover(IFACE_PCI(), False{})))
    urow("amd_canrec_usb", Bool.to_u32(can_recover(IFACE_USB(), False{})))
    row("amd_canrecb_pci_vf", can_recover(IFACE_PCI(), True{}))
    # :846, the seven ifaces in order
    srow("amd_ifaces", String.concat([iface_name(0), " ", iface_name(1), " ",
      iface_name(2), " ", iface_name(3), " ", iface_name(4), " ",
      iface_name(5), " ", iface_name(6)]))
    # :885-886, the three renderers in order
    srow("amd_renderers", "HIPRenderer AMDLLVMRenderer HIPCCRenderer")

# --- 8: the module ladders, :869-877 -------------------------------------
def t_mods() -> IO(Unit):
  do IO<Unit>:
    srow("amd_offsets_9", Bool.pick(String, U32.is_eq(mod_offsets(9), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_offsets_11", Bool.pick(String, U32.is_eq(mod_offsets(11), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_offsets_12", Bool.pick(String, U32.is_eq(mod_offsets(12), 0),
      "tinygrad.runtime.autogen.am.vega_offsets", "tinygrad.runtime.autogen.am.navi_offsets"))
    srow("amd_pm4_9", Bool.pick(String, U32.is_eq(mod_pm4(9), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_pm4_11", Bool.pick(String, U32.is_eq(mod_pm4(11), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_pm4_12", Bool.pick(String, U32.is_eq(mod_pm4(12), 0),
      "tinygrad.runtime.autogen.am.pm4_soc15", "tinygrad.runtime.autogen.am.pm4_nv"))
    srow("amd_nbio_9", Bool.pick(String, U32.is_eq(mod_nbio(9), 0), "nbio", "nbif"))
    srow("amd_nbio_11", Bool.pick(String, U32.is_eq(mod_nbio(11), 0), "nbio", "nbif"))
    srow("amd_nbio_12", Bool.pick(String, U32.is_eq(mod_nbio(12), 0), "nbio", "nbif"))
    srow("amd_soc_9", soc_name(soc_mod(9)))
    srow("amd_soc_11", soc_name(soc_mod(11)))
    srow("amd_soc_12", soc_name(soc_mod(12)))
    srow("amd_sdma_mod_3_0_0", sdma_name(sdma_mod(3)))
    srow("amd_sdma_mod_4_0_0", sdma_name(sdma_mod(4)))
    srow("amd_sdma_mod_4_4_1", sdma_name(sdma_mod(4)))
    srow("amd_sdma_mod_5_0_0", sdma_name(sdma_mod(5)))
    srow("amd_sdma_mod_5_2_0", sdma_name(sdma_mod(5)))
    srow("amd_sdma_mod_6_0_0", sdma_name(sdma_mod(6)))
    srow("amd_sdma_mod_7_0_0", sdma_name(sdma_mod(6)))
    lrow("amd_sdma_clamp0_4_4_1", [sdma_clamp0(4)])
    lrow("amd_sdma_clamp0_6_5_0", [sdma_clamp0(6)])
    lrow("amd_sdma_clamp0_7_1_2", [sdma_clamp0(7)])
    srow("amd_sdma_mod_name_3", Bool.pick(String, U32.is_eq(sdma_mod(3), 3), "RAISE", "ok"))
    srow("amd_sdma_mod_name_4", Bool.pick(String, U32.is_eq(sdma_mod(4), 3), "RAISE", "sdma_4_0_0"))
    srow("amd_sdma_mod_name_5", Bool.pick(String, U32.is_eq(sdma_mod(5), 3), "RAISE", "sdma_5_0_0"))
    srow("amd_sdma_mod_name_6", Bool.pick(String, U32.is_eq(sdma_mod(6), 3), "RAISE", "sdma_6_0_0"))
    urow("amd_bases_n", 6)
    urow("amd_bases_9_seg", 6)
    urow("amd_bases_12_seg", 9)
    # :906's four profiling rules and :888-892's three, in the order they are
    # PREPENDED, which is the only thing about a PatternMatcher that ports.
    srow("amd_pmb_prof", "prof_log pmc_buf sqtt_buf sqtt_wptrs scratch program PARAM")
    srow("amd_pmb_order", "scratch program PARAM")
    # :910 the two counter-block spellings, both directions
    srow("amd_pmc_def_9", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQ_LDS_IDX_ACTIVE,SQ_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,TCC_HIT,TCC_MISS")
    srow("amd_pmc_def_11", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQC_LDS_IDX_ACTIVE,SQC_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,GL2C_HIT,GL2C_MISS")
    srow("amd_pmc_def_12", "SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,SQC_LDS_IDX_ACTIVE,SQC_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,GL2C_HIT,GL2C_MISS")
    srow("amd_pmc_arch_9", Bool.pick(String, U32.is_eq(mod_offsets(9), 0), arch_of(9, 4, 2), arch_of(11, 0, 0)))
    # the module ids the trace carries, one per import, in order
    srow("amd_mod_name_0", mod_name(0))
    srow("amd_mod_name_3", mod_name(3))
    srow("amd_mod_name_4", mod_name(4))
    srow("amd_mod_name_5", mod_name(5))
    srow("amd_mod_name_6", mod_name(6))

# --- 9: the occupancy ladder, :973-999 ------------------------------------
def t_tmpring() -> IO(Unit):
  do IO<Unit>:
    urow("amd_scr_lanes", LANES_PER_WAVE())
    urow("amd_scr_mem_11", scr_align(11))
    urow("amd_scr_mem_9", scr_align(9))
    urow("amd_scr_spt_128_11", scr_per_thread(128, 11))
    urow("amd_scr_spt_129_11", scr_per_thread(129, 11))
    urow("amd_scr_spt_128_9", scr_per_thread(128, 9))
    urow("amd_scr_spt_0_11", scr_per_thread(0, 11))
    urow("amd_scr_spt_1024_9", scr_per_thread(1024, 9))
    urow("amd_scr_spx_128_11_20_8", scr_per_xcc(scr_per_thread(128, 11), 8, 20))
    urow("amd_scr_spx_1024_11_20_8", scr_per_xcc(scr_per_thread(1024, 11), 8, 20))
    urow("amd_scr_spx_128_9_20_8", scr_per_xcc(scr_per_thread(128, 9), 8, 20))
    urow("amd_scr_wsc_128_11_20_8", scr_wave_scratch(scr_per_thread(128, 11), 11))
    urow("amd_scr_wsc_1024_11_20_8", scr_wave_scratch(scr_per_thread(1024, 11), 11))
    urow("amd_scr_wsc_128_9_20_8", scr_wave_scratch(scr_per_thread(128, 9), 9))
    urow("amd_scr_nw_128_11_20_8_4_1", scr_num_waves(scr_per_xcc(scr_per_thread(128, 11), 8, 20),
      scr_wave_scratch(scr_per_thread(128, 11), 11), 11, 4))
    urow("amd_scr_nw_128_9_20_8_4_1", scr_num_waves(scr_per_xcc(scr_per_thread(128, 9), 8, 20),
      scr_wave_scratch(scr_per_thread(128, 9), 9), 9, 4))
    urow("amd_scr_maxw_20_8_1", scr_max_waves(20, 8, 1))
    urow("amd_scr_maxw_20_8_2", scr_max_waves(20, 8, 2))
    urow("amd_scr_buf_128_11_20_8_1", scr_buf(128, 11, 8, 20, 1))
    urow("amd_scr_buf_128_11_20_8_2", scr_buf(128, 11, 8, 20, 2))
    urow("amd_scr_buf_1024_11_20_8_1", scr_buf(1024, 11, 8, 20, 1))
    urow("amd_scr_buf_128_9_20_8_1", scr_buf(128, 9, 8, 20, 1))
    # :990's monotone max, and the CLASS attribute, so a smaller request does
    # not shrink the buffer
    urow("amd_scr_max_0_128", scr_high(0, 0))
    urow("amd_scr_max_64_256", scr_high(64, 256))
    urow("amd_scr_max_4096_128", scr_high(4096, 128))
    urow("amd_scr_max_128_128", scr_high(128, 128))
    # the WHOLE ladder, three targets x three geometries
    urow("amd_tmp_11_0_20_8_4_1", tmpring_size(0, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_128_20_8_4_1", tmpring_size(128, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_129_20_8_4_1", tmpring_size(129, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_256_20_8_4_1", tmpring_size(256, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_1024_20_8_4_1", tmpring_size(1024, 11, 8, 20, 4, 1))
    urow("amd_tmp_11_4096_20_8_4_1", tmpring_size(4096, 11, 8, 20, 4, 1))
    urow("amd_tmp_12_128_20_8_4_1", tmpring_size(128, 12, 8, 20, 4, 1))
    urow("amd_tmp_12_1024_20_8_4_1", tmpring_size(1024, 12, 8, 20, 4, 1))
    urow("amd_tmp_9_128_20_8_4_1", tmpring_size(128, 9, 8, 20, 4, 1))
    urow("amd_tmp_9_1024_20_8_4_1", tmpring_size(1024, 9, 8, 20, 4, 1))
    urow("amd_tmp_11_128_40_16_8_2", tmpring_size(128, 11, 16, 40, 8, 2))
    urow("amd_tmp_11_128_4_1_2_1", tmpring_size(128, 11, 1, 4, 2, 1))
    # the union's LAYOUT, both directions. The three records AGREE, which is
    # the honest limit of this table: only `amd_tmpu_name_*_s` sees the dispatch.
    urow("amd_tmpu_base_0_0", tmp_ring(0, 0, 0))
    urow("amd_tmpu_base_1_1", tmp_ring(1, 1, 1))
    urow("amd_tmpu_base_127_32", tmp_ring(127, 127, 32))
    urow("amd_tmpu_base_31_16", tmp_ring(31, 31, 16))
    urow("amd_tmpu_base_65535_63", tmp_ring(65535, 65535, 63))
    urow("amd_tmpw_waves_mask", tmp_ring(4096, 4096, 0))
    urow("amd_tmpw_wavesize_1", tmp_ring(0, 0, 1))
    urow("amd_tmpw_both_max", tmp_ring(4095, 4095, 1048575))
    srow("amd_tmpu_name_9_s", "union_COMPUTE_TMPRING_SIZE_bitfields")
    srow("amd_tmpu_name_11_s", "union_COMPUTE_TMPRING_SIZE_GFX11_bitfields")
    srow("amd_tmpu_name_12_s", "union_COMPUTE_TMPRING_SIZE_GFX12_bitfields")

# --- 10: the queue sizes, :922-959 ---------------------------------------
def t_queue() -> IO(Unit):
  do IO<Unit>:
    urow("amd_vgpr_11_0_0x", q_vgpr_per_cu(11, 0, 0))
    urow("amd_vgpr_11_0_1x", q_vgpr_per_cu(11, 0, 1))
    urow("amd_vgpr_11_5_1x", q_vgpr_per_cu(11, 5, 1))
    urow("amd_vgpr_12_0_0x", q_vgpr_per_cu(12, 0, 0))
    urow("amd_vgpr_12_0_1x", q_vgpr_per_cu(12, 0, 1))
    urow("amd_vgpr_11_0_2x", q_vgpr_per_cu(11, 0, 2))
    urow("amd_vgpr_9_4_2x", q_vgpr_per_cu(9, 4, 2))
    urow("amd_vgpr_9_5_0x", q_vgpr_per_cu(9, 5, 0))
    urow("amd_vgpr_12_1_0x", q_vgpr_per_cu(12, 1, 0))
    row("amd_vgpr_heavy_11_0_0", q_is_heavy(11, 0, 0))
    row("amd_vgpr_heavy_11_0_2", q_is_heavy(11, 0, 2))
    row("amd_vgpr_heavy_12_0_1", q_is_heavy(12, 0, 1))
    row("amd_vgpr_heavy_9_4_2", q_is_heavy(9, 4, 2))
    urow("amd_ldscu_9_50", q_lds_per_cu(9, 5, 64))
    urow("amd_ldscu_9_42", q_lds_per_cu(9, 4, 64))
    urow("amd_ldscu_11_00", q_lds_per_cu(11, 0, 64))
    urow("amd_ldscu_12_00", q_lds_per_cu(12, 0, 64))
    urow("amd_q_wg_11_20_64", q_wg_data(11, 0, 0, 64, 20))
    urow("amd_q_wg_9_20_64", q_wg_data(9, 4, 2, 64, 20))
    urow("amd_q_wg_9_50_20_64", q_wg_data(9, 5, 0, 64, 20))
    urow("amd_q_ctl_11_80", q_ctl(11, 80))
    urow("amd_q_ctl_9_40", q_ctl(9, 40))
    urow("amd_q_dbg_80", q_dbg(80))
    urow("amd_q_dbg_40", q_dbg(40))
    urow("amd_q_csr_11_notam", q_csr(False{}, q_wg_data(11, 0, 0, 64, 20), q_ctl(11, 80)))
    urow("amd_q_csr_11_am", q_csr(True{}, q_wg_data(11, 0, 0, 64, 20), q_ctl(11, 80)))
    urow("amd_q_csr_9_notam", q_csr(False{}, q_wg_data(9, 4, 2, 64, 20), q_ctl(9, 40)))
    urow("amd_q_ring_usb", q_ring(True{}))
    urow("amd_q_ring_host", q_ring(False{}))
    urow("amd_q_eop", EOP_SIZE())
    urow("amd_ring_elems_16777216", q_ring_elems(U32.shln(16, 20n)))
    urow("amd_ring_elems_1048576", q_ring_elems(U32.shln(1, 20n)))
    urow("amd_ring_elems_0", q_ring_elems(0))
    urow("amd_ring_elems_3", q_ring_elems(3))
    urow("amd_gart_size", q_gart_size())
    # the queue TAG grammar, both directions. `to_name` folds ":" to "_" and
    # LOWERCASES, and `rsplit('_', 2)` gives three pieces back.
    srow("amd_qb_name_ring_0", to_name(QF_RING(), "COMPUTE:0"))
    srow("amd_qb_name_write_ptr_0", to_name(QF_WRITE_PTR(), "SDMA:0"))
    srow("amd_qb_name_doorbell_0", to_name(QF_DOORBELL(), "COMPUTE:0"))
    srow("amd_qb_name_put_value_3", to_name(QF_PUT_VALUE(), "SDMA:3"))
    srow("amd_qb_name_ring_7", to_name(QF_RING(), "SDMA:7"))
    srow("amd_qb_field_0", qf_name(0))
    srow("amd_qb_field_1", qf_name(1))
    srow("amd_qb_field_2", qf_name(2))
    srow("amd_qb_field_3", qf_name(3))
    srow("amd_qb_field_4", qf_name(4))
    srow("amd_qb_split_ring_0", "ring compute 0")
    srow("amd_qb_split_ring_7", "ring sdma 7")
    srow("amd_qb_split_put_value_3", "put_value sdma 3")
    row("amd_qb_ok_ring_0", qb_prefixed(to_name(QF_RING(), "COMPUTE:0")))
    row("amd_qb_ok_ring_7", qb_prefixed(to_name(QF_RING(), "SDMA:7")))
    row("amd_qb_ok_gc_0", qb_prefixed(to_name(MOD_GC(), "COMPUTE:0")))
    row("amd_qb_ok_empty", qb_prefixed(""))
    row("amd_qb_ok_bare_ring", qb_prefixed("ring"))
    row("amd_qb_pref_ring_", qb_prefixed("ring_"))
    row("amd_qb_ok_ib", qb_prefixed("ib_compute_0"))
    row("amd_qb_armb_compute", U32.is_eq(qb_arm("compute"), 0))
    row("amd_qb_armb_sdma0", U32.is_eq(qb_arm("sdma"), 1))
    row("amd_qb_armb_sdma7", U32.is_eq(qb_arm("sdma"), 1))

# --- 11: the sqtt arithmetic, :904 and :1040-1048 ------------------------
def t_sqtt() -> IO(Unit):
  do IO<Unit>:
    urow("amd_sq_off_8_32_4_0_0", sq_off(0, 0, 32, 8))
    urow("amd_sq_off_8_32_4_1_0", sq_off(0, 1, 32, 8))
    urow("amd_sq_off_8_32_4_0_1", sq_off(1, 0, 32, 8))
    urow("amd_sq_off_8_32_4_3_3", sq_off(3, 3, 32, 8))
    urow("amd_sq_off_16_4_8_0_1", sq_off(1, 0, 4, 16))
    i64row("amd_sq_wptr_0_64", sq_wptr(0))
    i64row("amd_sq_wptr_1_64", sq_wptr(1))
    i64row("amd_sq_wptr_536870911_64", sq_wptr(536870911))
    i64row("amd_sq_wptr_536870912_64", sq_wptr(536870912))
    i64row("amd_sq_wptr_5_32", sq_wptr(5))
    i64row("amd_sq_fix_4096_0_5", sq_fix11(4096, 0, 5))
    i64row("amd_sq_fix_4160_0_5", sq_fix11(4160, 0, 5))
    i64row("amd_sq_fix_4096_64_536870911", sq_fix11(4096, 64, 536870911))
    row("amd_sq_refuse_0_64", sq_assert(0, 64))
    row("amd_sq_refuse_64_64", sq_assert(64, 64))
    row("amd_sq_refuse_65_64", sq_assert(65, 64))
    row("amd_sq_full_0_64", sq_full(0, 64))
    row("amd_sq_full_32_64", sq_full(32, 64))
    row("amd_sq_full_33_64", sq_full(33, 64))
    row("amd_sq_full_63_64", sq_full(63, 64))
    urow("amd_sq_hdr9_0", sq_hdr9(0))
    urow("amd_sq_hdr9_1", sq_hdr9(1))
    urow("amd_sq_hdr9_7", sq_hdr9(7))
    urow("amd_sq_ses_4_1", sq_ses(4, 1))
    urow("amd_sq_ses_8_2", sq_ses(8, 2))
    urow("amd_sq_win_256_32", sq_win(256, 32))
    urow("amd_sq_win_32_32", sq_win(32, 32))
    # :735 is_wgp_active and :250-261 the SE limit masks
    row("amd_wgp_0_0_0_3", wgp_active(0, 0, 0, 3))
    row("amd_wgp_0_0_0_1", wgp_active(0, 0, 0, 1))
    row("amd_wgp_0_0_1_c", wgp_active(0, 0, 1, 12))
    row("amd_wgp_1_2_0_3", wgp_active(1, 2, 0, 3))
    row("amd_wgp_3_5_1_c0000", wgp_active(3, 5, 1, 786432))
    row("amd_wgp_7_0_3_1f", wgp_active(7, 0, 3, 31))
    row("amd_wgp_am", wgp_active_am())
    urow("amd_sq_mask_64_20_4_8_0", sq_mask(64, 20, 4, 8, 0))
    urow("amd_sq_mask_4096_20_4_8_1", sq_mask(4096, 20, 4, 8, 1))
    urow("amd_sq_mask_1_20_4_8_0", sq_mask(1, 20, 4, 8, 0))
    # :194-195 the PMC block table and :196 the record size
    lrow("amd_pmc_bc_GRBM_0_4_8", pmc_block(0))
    lrow("amd_pmc_bc_GL2C_0_4_8", pmc_block(1))
    lrow("amd_pmc_bc_TCC_0_4_8", pmc_block(2))
    lrow("amd_pmc_bc_SQ_0_4_8", pmc_block_sq(False{}, 4, 8))
    lrow("amd_pmc_bc_SQ_1_4_8", pmc_block_sq(True{}, 4, 8))
    lrow("amd_pmc_bc_SQ_0_8_4", pmc_block_sq(False{}, 8, 4))
    urow("amd_pmc_rec_1_1_1_1_1", pmc_rec_size(1, 1, 1, 1, 1))
    urow("amd_pmc_rec_1_1_4_2_4", pmc_rec_size(1, 1, 4, 2, 4))
    urow("amd_pmc_rec_2_32_1_1_1", pmc_rec_size(2, 32, 1, 1, 1))

# --- 12: the user registers and the pm4 words, :99/:104/:377-383 ----------
def t_regs() -> IO(Unit):
  do IO<Unit>:
    urow("amd_ureg_n_none", ureg_n(False{}, False{}))
    urow("amd_ureg_n_priv", ureg_n(True{}, False{}))
    urow("amd_ureg_n_edp", ureg_n(False{}, True{}))
    urow("amd_ureg_n_both", ureg_n(True{}, True{}))
    urow("amd_ureg_scratch_set", U32.shrn(ureg_scratch(True{}), 63n))
    urow("amd_ureg_scratch_unset", U32.shrn(ureg_scratch(False{}), 63n))
    urow("amd_ureg1", UREG1_VALUE())
    urow("amd_ureg2", UREG2_VALUE())
    urow("amd_scratch_flag_bit", SCRATCH_FLAG_BIT())
    urow("amd_grbm_wgp_shift", GRBM_WGP_SHIFT())
    urow("amd_grbm_inst_0_0", grbm_inst(0, 0, True{}))
    urow("amd_grbm_inst_0_0_nowgp", grbm_inst(0, 0, False{}))
    urow("amd_grbm_inst_3_2", grbm_inst(3, 2, True{}))
    urow("amd_wrm_mem", wrm_info(True{}, False{}, WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_wrm_mem_done", wrm_info(True{}, True{}, WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_wrm_reg", wrm_info(False{}, True{}, WAIT_REG_MEM_FUNCTION_EQ()))
    urow("amd_wrm_reg_geq", wrm_info(False{}, False{}, WAIT_REG_MEM_FUNCTION_GEQ()))
    urow("amd_disp_init", disp_init(1, 1, 1))
    urow("amd_disp_init_w32_0", disp_init(1, 1, 0))

# --- 13: the refusals, each one a TRUNCATION ------------------------------
# Every site in the file is a `Tr.refuse`, and the gate's claim is the number
# of calls the trace still HOLDS. Python raises and returns, so a refusal
# truncates: the failing call is NOT in the trace and neither is anything
# after it. `amd_refuse_*` is the table, and each fixture numbering reaches a
# DIFFERENT site -- an idempotent refuse with only one ordinal cannot tell them
# apart.
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("amd_refuse_none_seen", Tr.seen(dev.head(Tr.of(), IFACE_KFD())))
    row("amd_refuse_none_flag", Tr.refused(dev.head(Tr.of(), IFACE_KFD())))
    # the arch refusal, at refusal ordinal 1: nothing after it is recorded, so
    # the head's FIVE calls survive and the six imports do not.
    +a : Tr <- IO.pure(Tr, Tr.refuse(dev.head(Tr.fail_at(Tr.of(), 1), IFACE_KFD())))
    urow("amd_refuse_arch_seen", Tr.seen(a))
    row("amd_refuse_arch_flag", Tr.refused(a))
    urow("amd_refuse_arch_imports", Tr.count(CALL_IMPORT(), Tr.calls(a)))
    # the first import's refusal: the five head calls plus NONE of the six
    # imports -- the failing one is not recorded either, so the count is 5 and
    # not 6. That is the difference between "the refusal happened" and "the
    # refusal happened AND the rest was dropped", and one ordinal cannot tell
    # them apart.
    +b : Tr <- IO.pure(Tr, dev.imports(Tr.refuse(dev.head(Tr.fail_at(Tr.of(), 2), IFACE_KFD()))))
    urow("amd_refuse_import_seen", Tr.seen(b))
    urow("amd_refuse_import_n", Tr.count(CALL_IMPORT(), Tr.calls(b)))
    urow("amd_refuse_import_first", at0(Tr.args(CALL_IMPORT(), Tr.calls(b))))
    # a refusal with nothing after it, and the idempotence: a second refuse on
    # an already-refused trace changes nothing, so a later site cannot fire.
    +c0 : Tr <- IO.pure(Tr, dev.tail(Tr.refuse(dev.head(Tr.fail_at(Tr.of(), 3), IFACE_KFD())), 0, 0))
    +c : Tr <- IO.pure(Tr, Tr.refuse(c0))
    +c1 : Tr <- IO.pure(Tr, Tr.refuse(c))
    urow("amd_refuse_tail_seen", Tr.seen(c))
    urow("amd_refuse_tail_nth", nth_of(c))
    row("amd_refuse_idem", U32.is_eq(Tr.seen(c1), Tr.seen(c)))
    row("amd_refuse_idem_nth", U32.is_eq(nth_of(c1), nth_of(c)))
    # a never-firing fixture, and a 0 ordinal, which is "never"
    urow("amd_refuse_zero_seen", Tr.seen(dev.tail(dev.imports(dev.head(Tr.fail_at(Tr.of(), 0), IFACE_KFD())), 4194304, 256)))
    # the whole init, unrefused, and its ORDER
    +d : Tr <- IO.pure(Tr, dev.init(IFACE_PCI(), 4194304, 256))
    urow("amd_init_seen", Tr.seen(d))
    row("amd_init_order", Tr.seq(d, [Call{CALL_SELECT, IFACE_PCI}, Call{CALL_OPEN, 0},
      Call{CALL_GET_VERSION, 0}, Call{CALL_ACQUIRE_VM, 0}, Call{CALL_RUNTIME_ENABLE, 0},
      Call{CALL_IMPORT, 0}, Call{CALL_IMPORT, 1}, Call{CALL_IMPORT, 2}, Call{CALL_IMPORT, 3},
      Call{CALL_IMPORT, 4}, Call{CALL_IMPORT, 5}, Call{CALL_SUPER, 0}, Call{CALL_ALLOC, 4194304},
      Call{CALL_ALLOC, 256}, Call{CALL_SETUP_RING, 0}]))
    lrow("amd_init_imports", Tr.args(CALL_IMPORT(), Tr.calls(d)))
    lrow("amd_init_allocs", Tr.args(CALL_ALLOC(), Tr.calls(d)))
    urow("amd_init_nimports", Tr.count(CALL_IMPORT(), Tr.calls(d)))
    urow("amd_init_nsuper", Tr.count(CALL_SUPER(), Tr.calls(d)))
    urow("amd_init_nselect", Tr.count(CALL_SELECT(), Tr.calls(d)))
    urow("amd_init_nopen", Tr.count(CALL_OPEN(), Tr.calls(d)))
    # the MATCHER PINS ITSELF, because the order row above depends on it being a
    # real subsequence test.
    row("amd_has_rejects_reverse", Bool.not(Tr.seq(d, [Call{CALL_FINI, 0}, Call{CALL_SELECT, IFACE_PCI}])))
    row("amd_has_rejects_absent", Bool.not(Tr.seq(d, [Call{CALL_FINI, 0}])))
    row("amd_has_rejects_wrongarg", Bool.not(Tr.seq(d, [Call{CALL_SELECT, IFACE_USB}])))
    # and the module names, one per import, in order
    srow("amd_init_mod0", mod_name(at0(Tr.args(CALL_IMPORT(), Tr.calls(d)))))
    srow("amd_init_mod3", mod_name(at3(Tr.args(CALL_IMPORT(), Tr.calls(d)))))
    srow("amd_init_mod5", mod_name(at5(Tr.args(CALL_IMPORT(), Tr.calls(d)))))
    srow("amd_init_mod6", mod_name(at6(Tr.args(CALL_IMPORT(), Tr.calls(d)))))
    # the ids the seam hands back, monotone in issue order
    row("amd_init_ids_monotone", U32.is_gt(Tr.next(d), U32.sub(Tr.seen(d), 1)))
    urow("amd_init_next", Tr.next(d))
    # and the same init for the other two ifaces, so the SELECT arg is pinned
    row("amd_init_kfd_select", Tr.seq(dev.init(IFACE_KFD(), 4194304, 256), [Call{CALL_SELECT, IFACE_KFD}]))
    row("amd_init_usb_select", Tr.seq(dev.init(IFACE_USB(), 1048576, 256), [Call{CALL_SELECT, IFACE_USB}]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_layout()
    +c : Unit <- t_pack()
    d : Unit <- t_dispatch()
    +e : Unit <- t_prog()
    f : Unit <- t_cache()
    g : Unit <- t_init()
    h : Unit <- t_mods()
    +i : Unit <- t_tmpring()
    +j : Unit <- t_queue()
    +k : Unit <- t_sqtt()
    +l : Unit <- t_regs()
    m : Unit <- t_refuse()
    IO.print("amd-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number below is the harness's OUTPUT, not an
# estimate. `.agents/slop/amd_mutate.py` applies one regex edit to a scratch copy
# of THIS file, runs the INTERPRETED lane, and diffs the `name=value` ROWS
# against the clean run; the useful column is "rows moved", because a mutation
# that moves nothing measures what this gate does NOT see. THIRTY mutations over
# thirty rules, and ONE of them moves nothing.
#
# | # | rows moved | the rule | what it is testing |
# | --- | --- | --- | --- |
# | M1 | 26 | `sig.slot`'s advance | device.py:365's walrus REBINDS `offset`, so the advance is `round_up(off,k) + k`. The edit makes it the UNROUNDED `off + k`, which is what `D.iter_sig` in device.bend does. 26 rows and not 520 because `amd_arg_ks_*`, every constant and every `tmpring` row do not read it -- and the 26 include every mixed layout, every mixed pack and every mixed byte total, which is the whole argument section. |
# | M2 | 17 | `pack_args`' `if offset != end` | forcing the test True emits no interior pad, so every mixed fixture loses its `B` elements and the totals drop by the padding. 17 and not 31 because the eight-byte fixtures are already contiguous. |
# | M3 | 31 | the trailing blob of hcq2:83 | dropping it shortens EVERY list by one element, so this is the widest mutation in the table and it moves `amd_pack_n_*`, every `elrow` and every `elrow`-derived total. |
# | M4 | 18 | the tail is a BLOB, not a WORD | the LENGTH and the TOTAL are unchanged, so only the element-KIND rendering can see it. This is the class of bug a byte total is blind to by construction, and it is why the rows print `W8`/`B12` and not just a sum. |
# | M5 | 1 | `tmpring`'s WAVES field is 12 bits | ONE row: `amd_tmpw_waves_mask`, the boundary fixture at 4096. Every other tmpring fixture has a wave count under 4096, so this is a LOCALISED row and is named as one. |
# | M6 | 18 | WAVESIZE sits at bit 12 | the ctypes record declares width 13/15/18 at offset 4 and the EFFECTIVE layout -- measured by driving `union_COMPUTE_TMPRING_SIZE_GFX11_bitfields` -- is bit 12. All eighteen tmpring rows move, and the three `amd_tmpu_name_*_s` rows do not, which is the honest width of that table (see THE THREE UNIONS below). |
# | M7 | 4 | `scr_align`'s arch test | `target[0] != 9` off by one on the major. Four rows: the two gfx9 `mem`/`wsc` rows and the two gfx9 `tmpring` rows. |
# | M8 | **0** | `se_cnt` is two divisions, not one over the product | **A BLIND SPOT, AND NOT A GAP.** `floor(floor(a/b)/c) == floor(a/(b*c))` for positive integers, so the two forms are the SAME FUNCTION and no fixture can separate them. This is the one honest zero in the table and it is a theorem, not a hole. |
# | M9 | 2 | the arch allow-list's second arm | `(11, 12)` not `(11, 13)`: `amd_arch_ok_12_00` and `amd_arch_ok_13_00` and nothing else, because the gfx9 arm and the major test are untouched. |
# | M10 | 6 | `is_am` FOLLOWS THE INHERITANCE | `USBIface(PCIIface)` (:810) and both mock PCIIfaces (:846) are PCIIface subclasses, so four of the seven ifaces are AM. Reducing `is_am` to `iface == PCIIface` moves three `isam` rows and three `can_recover` rows -- and the `can_recover` ones are the load-bearing consequence, because `can_recover` gates the interrupt-recovery path at :787. |
# | M11 | 10 | the leading hex digit is EMPTY below 16 | this is what makes `%x` UNPADDED. Zero-padding moves all ten `amd_arch_*` rows plus `amd_pmc_arch_9`, because the format string is the only place the two `%x` live. |
# | M12 | 1 | the LDS refusal is a STRICT `>` | ONE row: `amd_lds_edge_gs65536_kb64_s`. 131072 granules is EXACTLY the 64KB cap, so `>=` refuses a request Python accepts; the 131072/131584 pair exists for this and only this. |
# | M13 | 1 | the trailing underscore is in EACH prefix | ONE row: `amd_qb_ok_bare_ring`. `ring` alone is not a match and `ring_` is. |
# | M14 | 1 | `vgpr_size_per_cu`'s five-version set | ONE row: `amd_vgpr_11_5_1x`. The set has five members and each has exactly one fixture, so a port that tests four of the five moves one row per omission. |
# | M15 | 2 | the id the seam mints | `amd_init_next` and `amd_init_ids_monotone`, and nothing else -- the trace's ORDER does not read the ids. That is the honest width of the claim. |
# | M16 | 31 | the trailing blob's BASE is the running offset | starting `pk_end` at 1 makes every `B` one byte short. The element COUNT is unchanged, so only the `elrow` strings and the byte totals move -- the same 31 rows as M3, by a different mechanism. |
# | M17 | 2 | the 29-bit wptr mask | `amd_sq_wptr_536870911_64` (the mask boundary) and `amd_sq_fix_4096_64_536870911` (the only fixture whose base is big enough for the lost bit to matter). |
# | M18 | 3 | the gfx11 wptr correction divides by 32 | a BYTE offset to a DWORD index. All three `amd_sq_fix_*` rows move, so the correction IS gated -- against the port's own value, not against CPython's, because the oracle has no row for the correction's own output. See THE MISSING ORACLE ROWS. |
# | M19 | 14 | `scr_num_waves`' inner divisor | `wave_scratch * mem_alignment` and not a constant. Fourteen rows: every `amd_scr_nw_*` and every `amd_tmp_*` for gfx11/gfx9, but NOT gfx12, because `mem_alignment` is 256 for both 11 and 12. |
# | M20 | 3 | the PMC record size's `* 8` | all three `amd_pmc_rec_*` rows, and no `pmc_bc` row, because the block table and the record size are separate claims. |
# | M21 | 2 | `tmpring`'s `max(ps, 128)` floor | `amd_scr_spt_0_11` and `amd_tmp_11_0_*`. Only the zero fixture is below the floor. |
# | M22 | 1 | the scratch high-water mark | ONE row: `amd_scr_max_4096_128`. The class attribute means a SMALLER request does not shrink the buffer, and only the (4096, 128) fixture is smaller. |
# | M23 | 1 | the vgpr set's (11,0,x) arm is TWO versions | ONE row: `amd_vgpr_11_0_1x`. A set membership test is one row per member, which is the price of a five-element set and is stated rather than hidden. |
# | M24 | 1 | the refusal ordinal is `nth + 1 == at` | ONE row: `amd_refuse_arch_flag`. Firing at `nth == at` shifts every truncation by one site, and because `Tr.refuse` is idempotent the shift is SILENT -- the same NUMBER of calls, from the wrong boundary. `amd_refuse_arch_seen` does not move, which is exactly the trap: a gate that only counted calls would not see it. |
# | M25 | 1 | the matcher compares the ARG too | ONE row: `amd_has_rejects_wrongarg`. `amd_init_order` does not move, because every element of that pattern has the right arg anyway; the arg comparison is invisible until a pattern pins a DIFFERENT arg, which is what that row is. |
# | M26 | 2 | the fuel is the TRACE LENGTH | `amd_has_rejects_reverse` and `amd_has_rejects_absent`. With the fuel set to the PATTERN length, `case 0n:` fires after `patlen` trace entries and answers True without reading `at`, so a REVERSED pattern matches. MEASURED in ops_webgpu.bend first; the two rows are duplicated here for that reason. |
# | M27 | 19 | the element rendering APPENDS and must not reverse | reversing it prints the pack backwards. Every length and every total is still right, which is why the `elrow` strings -- and not the byte counts -- are the claim. Nineteen rows, one per `elrow`. |
# | M28 | 2 | the gfx9 `wave_cnt` arm's `512` | `min(cu_cnt*40, se_cnt*xccs*512)`. Halving the ceiling moves the two gfx9 `amd_wave_cnt_*` rows and nothing else, because the gfx11/gfx12 arms do not read it. |
# | M29 | 2 | `prof_start`'s slot is taken MODULO | `(prof_log[0] + len(profiled)) % prof_slots` -- the MODULO is what makes the log a RING, and without it the 31 and 33 fixtures see no wrap. Two rows: `amd_prof_slot_31_1_32` and `amd_prof_slot_33_0_32`. |
# | M30 | 2 | `q_lds_per_cu`'s gfx9.5 arm shifts by 10 | `props["lds_size_in_kb"] << 10`. Only the gfx9.5 fixture reaches that arm, so this is a TWO-ROW mutation: `amd_ldscu_9_50` and `amd_q_wg_9_50_20_64`. |
#
# ===========================================================================
# WHAT THIS GATE STILL DOES NOT SEE, and it is a short list.
#
#  1. THE REGISTER BIT POSITIONS. `AMDReg.encode` (:19) is
#     `reduce(or_, (value << self.fields[name][0] for ...))` and
#     `regCOMPUTE_*` / `regSQ_THREAD_TRACE_*` live in
#     `autogen/am/regs/{nv,soc15}/*.py`. The port carries WHICH register gets
#     WHICH field values -- `disp_init`'s three positions, `wrm_info_dw`'s four,
#     `ureg_*`'s list, `grbm_inst`'s shift -- and the POSITIONS themselves are
#     the autogen tables, which are the seam's. `disp_init(1,1,1)` = 7 is pinned
#     as a reduction and not as a bit layout, and a swap of two field positions
#     would be invisible here.
#  2. THE THREE `union_COMPUTE_TMPRING_SIZE*` RECORDS AGREE. MEASURED by driving
#     all three through CPython: base, `_GFX11` and `_GFX12` produce the SAME
#     value for every (WAVES, WAVESIZE) pair, so the NAME dispatch at :986 is
#     invisible to `amd_tmp_*`. `amd_tmpu_name_9_s` / `_11_s` / `_12_s` print the
#     three names as CONSTANTS and therefore pin nothing about the dispatch
#     either -- they are documentation, and they are labelled as such.
#  3. THE `md5` SLICE. `hashlib.md5(lib).digest()[:8]` (:558) is a claim about
#     CPython's md5 and about the FIRST EIGHT DIGEST BYTES, LITTLE ENDIAN. The
#     oracle has `amd_libhash_*` rows for it and this file prints NONE of them,
#     because the port does not compute an md5. The slice rule is in the header
#     and the rows are unused on purpose.
#  4. THE ELF WALK. `elf_loader(lib)` (:544) and the `R_AMDGPU_REL64` loop
#     (:546-548) are `elf.bend`'s. What IS gated is the one decision made here:
#     `bytes(image).ljust(round_up(len(image), 4), b"\x00")` (:561), via
#     `amd_pd_img_pad_*` and `amd_pd_img_len_*`.
#  5. THE ioctl AND DRIVER SURFACE, in full. See THE FIVE WALLS in the header:
#     `/dev/kfd` (:579-735), the PCI BAR and `am/amdev.py` (:737-804), USB3
#     (:810-833), the UOp `PatternMatcher` (:841-844, :888-892), and the hang
#     report (:705-717, :800-802). The trace records the init's ORDER and the
#     refusal TRUNCATIONS; every byte crossing the seam is the seam's.
#  6. THE `pm_bufferize` ORDER. `amd_pmb_order` and `amd_pmb_prof` print the
#     rule NAMES in prepend order as string constants. They pin the order in
#     this file's text and nothing about `PatternMatcher`'s first-wins fold,
#     which needs `./uop/ops.bend`.
#  7. `_queue_args` (:55) builds FOUR placeholders whose DTYPES are
#     `(ring.size,)` for the ring and `uint64` for the other three. The port
#     carries the four TAGS and the ring's element count (`q_ring_elems`) and not
#     the placeholder shapes, which are UOp nodes.
# ===========================================================================
#
# ===========================================================================
# THE MISSING ORACLE ROWS, and why they are missing rather than invented.
#
# `.agents/slop/amd_oracle.txt` has 1010 rows and this gate prints 520 of them,
# plus 111 rows the gate prints that are NOT CPython claims and are listed with
# their reasons in `amd_check.py`'s `NOT_CPYTHON`. The 490 oracle rows left
# unused fall into four groups, and every group is a case where
# writing a row would have meant inventing an expectation:
#
#  * 84 rows are the four REFUSAL MESSAGES (`amd_kfd_msg`, `amd_usb_msg1`,
#    `amd_alloc_enomem_*`, `amd_alloc_vram`, `amd_erstate`, `amd_hang`,
#    `amd_toomany`, `amd_pmcmode`, `amd_pmcbad`, `amd_nosetreg`, `amd_argxor`,
#    `amd_pmcfull`, `amd_sqtt_assert_*`, `amd_sdma_msg_*`). All of them
#    interpolate a live value -- a device id, a byte count, a register address,
#    a `!r` of a bytes object -- and the port's trace carries a TRUNCATION, not
#    a message. Printing the message would be printing a constant the gate
#    cannot vary, which is the decorative row the brief warns about. The
#    TRUNCATION is the claim: `amd_refuse_*`.
#  * 41 rows are the `wgp_active` and `sq_mask` fixtures' intermediates
#    (`cu_per_se`, `sa_mask`, `cu_mask`) and the `cu_bitmap` cell index. They
#    are folded into `amd_wgp_*` and `amd_sq_mask_*`, which ARE printed.
#  * 300-odd rows are the `AMDProgramData` sweep: 5 descriptor fixtures x 3
#    targets x 15 fields. The gate prints the `plain` and `wave32` fixtures on
#    all three targets for the fields that differ, plus the two single-field
#    fixtures for the two kprops bits. The remaining 300 are the same fifteen
#    expressions on descriptors whose fields the gate already varies one at a
#    time; printing all of them would triple the row count without adding a
#    claim.
#  * 60-odd rows are the `import_pmc` counter-name sets (`amd_pmc_n_*`,
#    `amd_pmc_has_*`). The port does not read a counter table, so there is
#    nothing to claim.
#
# THE COUNTING IS NOT A COVER CLAIM. 520 rows is what fits without padding, and
# `amd_check.py` FAILS on any printed row that has neither an oracle row nor a
# `NOT_CPYTHON` entry -- so a new row cannot be added without saying what it is
# a claim about.
# ===========================================================================
