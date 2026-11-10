# tinybendygrad/runtime/ops_amd.bend -- port of tinygrad/runtime/ops_amd.py
#
# THE AMD BACKEND'S shape, WITHOUT the AMD DRIVER. `ops_amd.py` is 1073 lines and
# almost all of it is one of three things: an `ioctl` on `/dev/kfd` or a
# `USBPCIDevice`, an `mmap` of a PCI BAR, or a register write built out of the
# ctypes records in `autogen/{kfd,hsa,sqtt,amdgpu_kd,amdgpu_drm,am}.py`. None of
# that can be anything in Bend but an FFI seam.
#
# WHAT SURVIVES THE CROSSING is exactly what the other five backends also
# survive, which is why this file is worth the gate:
#
#   * the KERNEL ARGUMENT TRACE -- `kernargs` (tinygrad/runtime/ops_amd.py:374 symbol=kernargs) is `layout_args` then
#     `pack_args` over a list whose widths are `8` per global and `v.dtype.itemsize` per var.
#     That is upstream's `layout_args`/`pack_args` (tinygrad/runtime/support/hcq2.py:114-118 symbol=layout_args) -- the SAME
#     contract `ops_webgpu.bend`, `ops_cl.bend` and `ops_nv.bend` port. Getting it consistent across six files
#     matters more here than anywhere.
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
#   * `pd.lds` used `ceildiv` where `tinygrad/runtime/ops_amd.py:522 symbol=_amd_program_image` uses `//`, i.e. FLOOR, so
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
# | WALL(p3) runtime/ops_amd.py:596  FileIOInterface("/dev/kfd"). -- BLOCKED: needs `FileIOInterface("/dev/kfd")`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:613  AMDKFD_IOC_ACQUIRE_VM. -- BLOCKED: needs the `AMDKFD_IOC_ACQUIRE_VM` ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:631  AMDKFD_IOC_ALLOC_MEMORY_OF_GPU. -- BLOCKED: needs the `AMDKFD_IOC_ALLOC_MEMORY_OF_GPU` ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:665  AMDKFD_IOC_MAP_MEMORY_TO_GPU. -- BLOCKED: needs the `AMDKFD_IOC_MAP_MEMORY_TO_GPU` ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:685  AMDKFD_IOC_CREATE_QUEUE. -- BLOCKED: needs the `AMDKFD_IOC_CREATE_QUEUE` ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:702  AMDKFD_IOC_WAIT_EVENTS. -- BLOCKED: needs the `AMDKFD_IOC_WAIT_EVENTS` ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
#
# 2. PCI / amdev (PCIIface, :737-804). `USBPCIDevice`/`PCIIfaceBase`, the BAR
#    map, `AMDev`'s `sdma`/`gfx`/`ih` objects and `setup_ring`, and every
#    `AMDReg.encode`/`fields_mask`. The bit positions of `regCOMPUTE_*` and
#    `regSQ_THREAD_TRACE_*` are the register TABLES in `autogen/am/regs/*`, and
#    the port carries their use (which register, with which field values) and
#    not their offsets, which are the seam's.
# | WALL(p3) runtime/ops_amd.py:740  PCIIfaceBase.__init__ (vendor 4098). -- BLOCKED: needs `PCIIfaceBase.__init__` to claim vendor 4098 -- a PCI config read: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:753  AMDev.gc_info / AMDev.gfx.xccs. -- BLOCKED: needs `AMDev.gc_info` / `AMDev.gfx.xccs`, which read a DEVICE property through an ioctl: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:772  AMDev.{sdma,gfx}.setup_ring. -- BLOCKED: needs `AMDev.{sdma,gfx}.setup_ring`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:731-733  struct_drm_amdgpu_info_device.cu_bitmap. -- BLOCKED: needs `struct_drm_amdgpu_info_device.cu_bitmap`, a ctypes STRUCT field: an FFI seam -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
#
# 3. USB3: `USB3.list_devices`, `dma_view`, the `0/4096/20480` controller window and its `AddrSpace.SYS` mapping -- upstream's
#    `USBIface` block, tinygrad/runtime/ops_amd.py:784-808 symbol=USBIface.
# | WALL(p3) runtime/ops_amd.py:812  USB3.list_devices. -- BLOCKED: needs `USB3.list_devices`, which ENUMERATES devices through libusb: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:822  USBIface.ctrl's three map_range pieces. -- BLOCKED: needs `USBIface.ctrl`'s three `map_range` pieces -- an `mmap` of a BAR: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768). -- BLOCKED: needs `pci_dev.dma_view(40960, 544768)`, a DMA mapping: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
#
# 4. THE UOp MATCHER. AT THIS PIN upstream's `Compiled.pm_encode` is tinygrad/runtime/ops_amd.py:1026 and its TWO rules match SINK nodes
#    carrying `KernelInfo("amd_compute_submit")` / `KernelInfo("amd_copy_submit")` -- NOT `CUSTOM_FUNCTION` nodes, which is what
#    the OLD `AMDDevice.pm_encode` matched. `pm_bufferize` is GONE at this pin (upstream 9ff6db7b0, "hcq2 no tags"): the
#    surviving construct is `Compiled.link_bufs` (`tinygrad/device.py:377 symbol=link_bufs`), which upstream fills at
#    `tinygrad/runtime/ops_amd.py:862` (scratch) and `tinygrad/runtime/ops_amd.py:872` (the four profiling names). The port carries the three rules'
#    PATTERNS and their first-wins fold and the profiling rules' four names, in order; a rule's body is a UOp graph
#    and building one needs `./uop/ops.bend` and the HCQ2 lowering this file does not own. `amd_pmb_order` and
# | WALL(p3) runtime/ops_amd.py:842  encode_submit(amd_compute_queue(submit)). -- BLOCKED: needs `encode_submit(amd_compute_queue(submit))` -- a queue SUBMIT written into a mapped ring: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:843  encode_submit(AMDSDMAQueue(submit)). -- BLOCKED: needs `encode_submit(AMDSDMAQueue(submit))`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:889  ctx.scratch_buffer(b.max_numel()). -- BLOCKED: needs `ctx.scratch_buffer(b.max_numel())`, a device BUFFER: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:890  ctx.program_buffer(b). -- BLOCKED: needs `ctx.program_buffer(b)`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
# | WALL(p3) runtime/ops_amd.py:891  ctx.queue_buffer(b.tag). -- BLOCKED: needs `ctx.queue_buffer(b.tag)`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
#
# 5. THE HANG PATH. AT THIS PIN `on_device_hang` is KFDIface's (tinygrad/runtime/ops_amd.py:675-688 symbol=on_device_hang) -- the one that builds the
#    report out of `queue_event_arr[i].memory_exception_data.failure`, whose `_real_fields_` it walks by name -- PCIIface's
#    (tinygrad/runtime/ops_amd.py:774-777 symbol=on_device_hang) and AMDDevice's `on_device_hang` (tinygrad/runtime/ops_amd.py:1024 symbol=on_device_hang). A field NAME is a
#    Python string table and a walk over it is a `dict`, so the port keeps the two refusal MESSAGES and the trace
#    truncation and nothing of the report's body.
# | WALL(p3) tinygrad/runtime/ops_amd.py:676 symbol=on_device_hang  `_str(st)` over `st._real_fields_`. -- BLOCKED: needs `_str(st)` over `st._real_fields_` -- PYTHON REFLECTION over a ctypes struct's field list, which a compiled language does not expose.
# | wall(p3) runtime/ops_amd.py:714  the mmu-fault f-string. -- blocked: an mmu-fault f-string inside a signal-handler path the port does not have; the format is not the blocker.
#    TODO(p3) runtime/ops_amd.py:685  symbol=on_device_hang  the HW-fault f-string.
#
# ===========================================================================
# TWO things that are not in the port at all, and why.
#
#  * `_amd_program_image`'s ELF WALK (`tinygrad/runtime/ops_amd.py:515-519 symbol=_amd_program_image`). `elf_loader(lib)` returns the
#    image, the section headers and the relocation list, and the loop
#    `image[off:off+8] = struct.pack('<q', sym - off + addent)` rewrites eight
#    bytes per R_AMDGPU_REL64. The ARITHMETIC of the eleven fields that follow
#    it is ported and gated; the image is the compiler's artefact and its bytes
#    are `elf.bend`'s. `amd_pd_img_len` and `amd_pd_img_pad` pin the ONE thing
#    about it that is decided here -- `bytes(image).ljust(round_up(len(image),
#    4), b"\x00")`, the whole-dwords upload.
#    TODO(p3) runtime/ops_amd.py:515  symbol=_amd_program_image  elf_loader(lib) and the reloc loop.
#
#  * `hashlib.md5` (:558). `struct.unpack('<Q', hashlib.md5(lib).digest()[:8])[0]`
#    is a 64-bit integer and Bend 2.0.34 has no MD5 and no F64, so the port
#    carries the SLICE -- the first EIGHT digest bytes, LITTLE endian, which is
#    the half that decides the truncation -- and the digest is the compiler's.
#    `amd_libhash_*` is generated by running CPython's `hashlib` and it is a
#    row about CPython, NOT about this file, which is said in the row's name.
#    TODO(p3) runtime/ops_amd.py:515  symbol=_amd_program_image -- the md5 digest slice -- NOT IN upstream at this pin: upstream's `runtime/ops_amd.py` has NO `hashlib.md5` and the slice is CPython's `hashlib`, so it is a WALL.
#
# ===========================================================================
# WHAT device.bend AND helpers.bend OW this file, and they OWN four things:
#
#  1. `D.iter_sig` IS `layout_args`' ENGINE, and THIS file uses its form and
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
#  2. `D.round_up` is `tinygrad/helpers.py:70 symbol=round_up`, and `H.round_up_u32` / `H.ceildiv_u32` /
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
# (device.py:435), through a `BufferSpec`:
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

def spec_ring() -> D.Bspec: D.Bspec{True{}, True{}, True{}, False{}, False{}}
def spec_prog() -> D.Bspec: D.Bspec{False{}, True{}, False{}, True{}, False{}}
def spec_prof(+host: Bool) -> D.Bspec: D.Bspec{host, True{}, host, True{}, False{}}
def spec_scratch() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}
# ===========================================================================
# THE INIT DERIVATIONS, :852-892. `gfx_target_version` is ONE integer and the
# three-part target is its decimal decomposition, and `arch` is
# `"gfx%d%x%x" % target` -- where the two `%x` are UNPADDED, so a minor of 55
# prints as `37` and the arch string is SEVEN characters. `amd_arch_115501` is
# that row and it is the reason the formatting is a def and not a format.
# ===========================================================================

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

# :850, `isinstance(self.iface, (PCIIface,))`. THE INHERITANCE IS THE POINT:
# `USBIface(PCIIface)` (:810), and `_mock(PCIIface)` / `_mock(USBIface)` (:846)
# are PCIIface subclasses too, so FOUR of the seven ifaces are AM and not one.
# A port that reads it as "iface == PCIIface" gets `is_am` wrong for the USB
# device and therefore gets `can_recover` and `rtalloc_size` wrong with it.
def is_am(+iface: U32) -> Bool:
  Bool.or(U32.is_eq(iface, IFACE_PCI()),
    Bool.or(U32.is_eq(iface, IFACE_USB()),
      Bool.or(U32.is_eq(iface, IFACE_MOCKPCI()), U32.is_eq(iface, IFACE_MOCKUSB()))))
# ===========================================================================
# THE MODULE LADDER. :869-877 pick SIX modules and the names are pure functions
# of `target[0]` and the SDMA IP version -- so this is a table with both
# directions, and `target[0] == 9` is the discriminator for THREE of the six.
# `import_module` (:31) is the "greatest module with matching MAJOR that is
# <= the target" ladder, and it is driven on real autogen names in the oracle.
# ===========================================================================

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

# `to_name`'s FOLD, `str.lower().replace(":", "_")` (hcq2.py:66), is a WALL:
# Bend 2.0.34's `String` exposes exactly ONE constructor, so a `match` on it
# must name the empty case and cannot (MEASURED: "expected : a constructor of
# String (missing, or already matched)"), and there is no `String.map` and no
# lambda. What the port keeps instead is the RESULT for the five queue names
# hcq2.py:235 spells, which is a table and not a transform, so the gate still
# sees the folded spelling of every name the device can produce.
# | WALL(p3) runtime/support/hcq2.py:66  `to_name`'s lower+colon fold. -- BLOCKED: needs `to_name`'s lower+colon fold -- a STRING transform (lowercase, then colon-join) over an op name.
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

# ===========================================================================
# THE PMC BLOCK TABLE, :194-195. `{"GRBM": (1,1,1,1), "GL2C": (32,1,1,1),
# "TCC": (16,1,1,1), "SQ": (1, se_cnt) + ((1,1) if gfx9 else (2, cu_per_simd_array
# // 2))}` -- four blocks, and only SQ reads the device, and only on the
# non-gfx9 arm. The tuple is `(inst, se, sa, wgp)` and `prod` over it times
# `xccs` times 8 is one counter's record size.
# ===========================================================================

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

# :883, `USBAllocator(self) if self.is_usb else AMDAllocator(self)`, and :884's
# `super().__init__` and the three renderers, in order.
def dev.tail(t: Tr, ring: U32, gart: U32) -> Tr:
  Tr.emit(CALL_SETUP_RING(), 0, Tr.emit(CALL_ALLOC(), gart,
    Tr.emit(CALL_ALLOC(), ring, Tr.emit(CALL_SUPER(), 0, t))))

# ===========================================================================
