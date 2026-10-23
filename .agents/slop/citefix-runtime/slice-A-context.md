## tinybendygrad/runtime/ops_amd.bend  (13 rows)
- :12 [only_older_revision] tinygrad/runtime/ops_amd.py:361-364 rev=225f6d0ec3 toks=kernargs,layout_args
    10	# survive, which is why this file is worth the gate:
    11	#
   >12	#   * the KERNEL ARGUMENT TRACE -- `kernargs` (:361-364) is `layout_args` then
    13	#     `pack_args` over a list whose widths are `8` per global and
    14	#     `v.dtype.itemsize` per var. That is `hcq2.py:74-80` and it is the SAME
- :68 [only_older_revision] ops_amd.py:551 rev=956e956e2b toks=lds,ceildiv
    66	#
    67	#   * `args.ks` used `LANES_PER_WAVE` (64) for a `getaddr`, which is EIGHT bytes.
   >68	#   * `pd.lds` used `ceildiv` where `ops_amd.py:551` uses `//`, i.e. FLOOR, so
    69	#     512 granules read back as 2 instead of 1 and the `rsrc2` bit was wrong.
    70	#   * `dev_max_copy` compared a three-part version COMPONENTWISE where
- :184 [only_older_revision] tinygrad/runtime/ops_amd.py:810-833 rev=c52b227c7b toks=USB3,list_devices,dma_view
    182	# | WALL(p3) runtime/ops_amd.py:731-733  struct_drm_amdgpu_info_device.cu_bitmap. -- BLOCKED: needs `struct_drm_amdgpu_info_device.cu_bitmap`, a ctypes STRUCT FIELD: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    183	#
   >184	# 3. USB3 (USBIface, :810-833). `USB3.list_devices`, `dma_view`, the
    185	#    `0/4096/20480` controller window and its `AddrSpace.SYS` mapping.
    186	# | WALL(p3) runtime/ops_amd.py:812  USB3.list_devices. -- BLOCKED: needs `USB3.list_devices`, which ENUMERATES devices through libusb: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
- :190 [only_older_revision] tinygrad/runtime/ops_amd.py:841-844 rev=70fe874269 toks=pm_encode
    188	# | WALL(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768). -- BLOCKED: needs `pci_dev.dma_view(40960, 544768)`, a DMA mapping: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    189	#
   >190	# 4. THE UOp MATCHER (:841-844, :888-892, :895-896, :905-906). `pm_encode`
    191	#    matches `CUSTOM_FUNCTION` nodes and `pm_bufferize` PREPENDS three rules to
    192	#    `Compiled`'s. The port carries the three rules' PATTERNS and their
- :190 [at_no_revision] tinygrad/runtime/ops_amd.py:888-892 rev= toks=pm_encode
    188	# | WALL(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768). -- BLOCKED: needs `pci_dev.dma_view(40960, 544768)`, a DMA mapping: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    189	#
   >190	# 4. THE UOp MATCHER (:841-844, :888-892, :895-896, :905-906). `pm_encode`
    191	#    matches `CUSTOM_FUNCTION` nodes and `pm_bufferize` PREPENDS three rules to
    192	#    `Compiled`'s. The port carries the three rules' PATTERNS and their
- :190 [only_older_revision] tinygrad/runtime/ops_amd.py:895-896 rev=4d185f6b5e toks=pm_encode
    188	# | WALL(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768). -- BLOCKED: needs `pci_dev.dma_view(40960, 544768)`, a DMA mapping: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    189	#
   >190	# 4. THE UOp MATCHER (:841-844, :888-892, :895-896, :905-906). `pm_encode`
    191	#    matches `CUSTOM_FUNCTION` nodes and `pm_bufferize` PREPENDS three rules to
    192	#    `Compiled`'s. The port carries the three rules' PATTERNS and their
- :190 [at_no_revision] tinygrad/runtime/ops_amd.py:905-906 rev= toks=pm_encode
    188	# | WALL(p3) runtime/ops_amd.py:824  pci_dev.dma_view(40960, 544768). -- BLOCKED: needs `pci_dev.dma_view(40960, 544768)`, a DMA mapping: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    189	#
   >190	# 4. THE UOp MATCHER (:841-844, :888-892, :895-896, :905-906). `pm_encode`
    191	#    matches `CUSTOM_FUNCTION` nodes and `pm_bufferize` PREPENDS three rules to
    192	#    `Compiled`'s. The port carries the three rules' PATTERNS and their
- :203 [only_older_revision] tinygrad/runtime/ops_amd.py:705-717 rev=975127a100 toks=on_device_hang
    201	# | WALL(p3) runtime/ops_amd.py:891  ctx.queue_buffer(b.tag). -- BLOCKED: needs `ctx.queue_buffer(b.tag)`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    202	#
   >203	# 5. THE HANG PATH (:705-717, :800-802, :798). `on_device_hang` builds its
    204	#    report out of `queue_event_arr[i].memory_exception_data.failure`, whose
    205	#    `_real_fields_` it walks by name. A field NAME is a Python string table and
- :203 [only_older_revision] tinygrad/runtime/ops_amd.py:800-802 rev=1f521c4301 toks=on_device_hang
    201	# | WALL(p3) runtime/ops_amd.py:891  ctx.queue_buffer(b.tag). -- BLOCKED: needs `ctx.queue_buffer(b.tag)`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    202	#
   >203	# 5. THE HANG PATH (:705-717, :800-802, :798). `on_device_hang` builds its
    204	#    report out of `queue_event_arr[i].memory_exception_data.failure`, whose
    205	#    `_real_fields_` it walks by name. A field NAME is a Python string table and
- :203 [only_older_revision] tinygrad/runtime/ops_amd.py:798 rev=d50e16d79d toks=on_device_hang
    201	# | WALL(p3) runtime/ops_amd.py:891  ctx.queue_buffer(b.tag). -- BLOCKED: needs `ctx.queue_buffer(b.tag)`: an FFI SEAM -- an `ioctl`/`mmap`/ctypes register write, and NONE of those can be anything in Bend but a foreign call (`ops_amd.bend:1-8`). The port declares no foreign seam here because `ops.bend:87` records that foreign code makes the checker exit 1 for any importer.
    202	#
   >203	# 5. THE HANG PATH (:705-717, :800-802, :798). `on_device_hang` builds its
    204	#    report out of `queue_event_arr[i].memory_exception_data.failure`, whose
    205	#    `_real_fields_` it walks by name. A field NAME is a Python string table and
- :208 [only_older_revision] runtime/ops_amd.py:706 rev=956e956e2b toks=_str,_real_fields_
    206	#    a walk over it is a `dict`, so the port keeps the two refusal MESSAGES and
    207	#    the trace truncation and nothing of the report's body.
   >208	# | WALL(p3) runtime/ops_amd.py:706  `_str(st)` over `st._real_fields_`. -- BLOCKED: needs `_str(st)` over `st._real_fields_` -- PYTHON REFLECTION over a ctypes struct's field list, which a compiled language does not expose.
    209	# | WALL(p3) runtime/ops_amd.py:714  the MMU-fault f-string. -- BLOCKED: an MMU-FAULT f-string inside a signal-handler path the port does not have; the FORMAT is not the blocker.
    210	#    TODO(p3) runtime/ops_amd.py:685  symbol=on_device_hang  the HW-fault f-string.
- :215 [only_older_revision] tinygrad/runtime/ops_amd.py:544-548 rev=c52b227c7b toks=_amd_program_image,elf_loader,lib
    213	# TWO THINGS THAT ARE NOT IN THE PORT AT ALL, and why.
    214	#
   >215	#  * `_amd_program_image`'s ELF WALK (:544-548). `elf_loader(lib)` returns the
    216	#    image, the section headers and the relocation list, and the loop
    217	#    `image[off:off+8] = struct.pack('<q', sym - off + addent)` rewrites eight
- :248 [at_no_revision] helpers.py:69 rev= toks=round_up,round_up_u32,ceildiv_u32
    246	#     rather than a stale comment. `sig.slot` below is the CPython form and
    247	#     `amd_arg_at_*` is generated from the CPython call.
   >248	#  2. `D.round_up` is `helpers.py:69`, and `H.round_up_u32` / `H.ceildiv_u32` /
    249	#     `H.floordiv_u32` are the same three functions under the names
    250	#     `tmpring_size` and `wg_data_size` use. Nothing re-derives a rounding.

## tinybendygrad/runtime/ops_bend.bend  (13 rows)
- :53 [at_no_revision] tinygrad/runtime/ops_bend.py:90 rev= toks=lanes,lanes_sorted
    51	# WHAT IS PORTED, DEF BY DEF.
    52	#
   >53	#   :90  LANES                    PORTED  `lanes`, `lanes_sorted`
    54	#   :92  wire_dtype               PORTED  `wire_dtype` -- the NAME and the
    55	#                                           refusal, message included
- :54 [at_no_revision] tinygrad/runtime/ops_bend.py:92 rev= toks=wire_dtype
    52	#
    53	#   :90  LANES                    PORTED  `lanes`, `lanes_sorted`
   >54	#   :92  wire_dtype               PORTED  `wire_dtype` -- the NAME and the
    55	#                                           refusal, message included
    56	#   :103 wire_width               PORTED  `wire_width` (node.numel)
- :57 [at_no_revision] tinygrad/runtime/ops_bend.py:110 rev= toks=wire_arg
    55	#                                           refusal, message included
    56	#   :103 wire_width               PORTED  `wire_width` (node.numel)
   >57	#   :110 wire_arg                 PORTED  `wire_arg` -- every arm but the float
    58	#                                           CONST's `struct.pack` (WALL 2)
    59	#   :133 encode                   PORTED  `encode`
- :59 [at_no_revision] tinygrad/runtime/ops_bend.py:133 rev= toks=encode
    57	#   :110 wire_arg                 PORTED  `wire_arg` -- every arm but the float
    58	#                                           CONST's `struct.pack` (WALL 2)
   >59	#   :133 encode                   PORTED  `encode`
    60	#   :149 executor                 SEAM   the build/cache of the executor
    61	#   :169 UOpLine                  PORTED  `Line`
- :61 [at_no_revision] tinygrad/runtime/ops_bend.py:169 rev= toks=Line
    59	#   :133 encode                   PORTED  `encode`
    60	#   :149 executor                 SEAM   the build/cache of the executor
   >61	#   :169 UOpLine                  PORTED  `Line`
    62	#   :175 is_buf                   PORTED  `is_buf`
    63	#   :178 buf_extent               PORTED  `buf_extent`
- :62 [at_no_revision] tinygrad/runtime/ops_bend.py:175 rev= toks=is_buf
    60	#   :149 executor                 SEAM   the build/cache of the executor
    61	#   :169 UOpLine                  PORTED  `Line`
   >62	#   :175 is_buf                   PORTED  `is_buf`
    63	#   :178 buf_extent               PORTED  `buf_extent`
    64	#   :180 parse                    PORTED  `parse`
- :63 [at_no_revision] tinygrad/runtime/ops_bend.py:178 rev= toks=buf_extent
    61	#   :169 UOpLine                  PORTED  `Line`
    62	#   :175 is_buf                   PORTED  `is_buf`
   >63	#   :178 buf_extent               PORTED  `buf_extent`
    64	#   :180 parse                    PORTED  `parse`
    65	#   :195 BendProgram.__init__     PORTED  `prog.of` -- in_bufs AND out_bufs
- :64 [at_no_revision] tinygrad/runtime/ops_bend.py:180 rev= toks=parse
    62	#   :175 is_buf                   PORTED  `is_buf`
    63	#   :178 buf_extent               PORTED  `buf_extent`
   >64	#   :180 parse                    PORTED  `parse`
    65	#   :195 BendProgram.__init__     PORTED  `prog.of` -- in_bufs AND out_bufs
    66	#   :211 BendProgram.__call__     PORTED  `prog.call` as a TRUNCATED TRACE
- :68 [at_no_revision] tinygrad/runtime/ops_bend.py:234 rev= toks=render,has_local
    66	#   :211 BendProgram.__call__     PORTED  `prog.call` as a TRUNCATED TRACE
    67	#   :231 BendCompiler.compile     PORTED  `compiler.of` -- pass-through
   >68	#   :234 BendRenderer             PORTED  `render`, `has_local`
    69	#   :243 BendDevice.__init__      SEAM   HostAllocator + Compiled wiring
    70	#
- :111 [at_no_revision] tinygrad/runtime/ops_bend.py:214 rev= toks=to_mv
    109	#      :150-164  `executor()`  -- exists(), stat(), hashlib, subprocess.run
    110	#               over ./bin/bend, os.replace. The build and the cache.
   >111	#      :214      `to_mv(b, nb)` -- a ctypes memoryview over a device pointer.
    112	#      :217      `pkt.write_text(...)` -- the PACKET.in on disk.
    113	#      :222      `subprocess.run([exe, pkt, gx, gy, gz, vals...])` -- the launch.
- :117 [at_no_revision] tinygrad/runtime/ops_bend.py:219 rev= toks=time,perf_counter
    115	#      :228      `views[i][:] = bytes.fromhex(...)` -- the copy-back.
    116	#      :232      `src.encode()` -- BendCompiler, which is a pass-through.
   >117	#      :219      `time.perf_counter()` -- the returned duration. Not modelled:
    118	#               the only thing this port does with a time is hand it back, and
    119	#               no caller of `Program.__call__` reads it (engine/realize.py:168
- :119 [dangling] engine/realize.py:168 rev= toks=Program,__call__
    117	#      :219      `time.perf_counter()` -- the returned duration. Not modelled:
    118	#               the only thing this port does with a time is hand it back, and
   >119	#               no caller of `Program.__call__` reads it (engine/realize.py:168
    120	#               discards it).
    121	#
- :127 [at_no_revision] tinygrad/runtime/ops_bend.py:238 rev= toks=has_local,False
    125	#
    126	# ===========================================================================
   >127	# `has_local = False` (:238) is a CONSTANT the scheduler consults
    128	# (opt/heuristic.py:163), so it is a `def` and not a field: a def nothing calls
    129	# is invisible to every other check, and `bend_has_local` is its only reader.

## tinybendygrad/runtime/ops_cl.bend  (6 rows)
- :165 [only_older_revision] tinygrad/runtime/ops_cl.py:100 rev=9dc524536f toks=device_name
    163	#    `(ptr, len)` pair the seam frees as soon as the call returns. The port keeps
    164	#    the decoded String, because the decoded String IS what :106 stores in
   >165	#    `self.device_name` and what :100 prints.
    166	#    TODO(p3) runtime/ops_cl.py:31  symbol=compile  -- the build-log string buffer.
    167	#    TODO(p3) runtime/ops_cl.py:108  symbol=__init__ -- the device-info string buffer.
- :169 [only_older_revision] tinygrad/runtime/ops_cl.py:10-11 rev=a6addc2d43 toks=CC_CB,BP_CB,CFUNCTYPE
    167	#    TODO(p3) runtime/ops_cl.py:108  symbol=__init__ -- the device-info string buffer.
    168	#
   >169	# 4. `CC_CB` / `BP_CB` (:10-11) are `CFUNCTYPE` signatures handed as the
    170	#    `pfn_notify` argument of `clCreateContext` and `clBuildProgram`. cl:110
    171	#    passes a fresh `CC_CB()` and cl:27,46 pass `BP_CB()`, and a callback that
- :216 [only_older_revision] tinygrad/runtime/ops_cl.py:16 rev=35c2870b1f toks=check
    214	#
    215	# ===========================================================================
   >216	# THE ERROR TABLES, :16 and cu:18 and hp:10, which are the three `check`s.
    217	#
    218	# `cl_errors = {attr: k for k in dir(cl) if k.startswith("CL_") and isinstance(
- :259 [only_older_revision] device.py:365 rev=c52b227c7b toks=TinyELF,iter_sig,round_up,offset,itemsize
    257	#      `copy.copyin` / `copy.copyout` and it is two rows in the gate.
    258	#   3. `TinyELF.signature` is `tuple[(name, slot, DType, shape)]` and
   >259	#      `TinyELF.iter_sig` (device.py:365) is the `round_up(offset, dt.itemsize)`
    260	#      walk. hp:41 calls it, and so does `hcq2.layout_args` for CUDA -- the SAME
    261	#      walk in two of the three vendors. `iter_sig` is not in any of the three
- :272 [at_no_revision] cstyle.py:348 rev= toks=OpenCLRenderer
    270	#
    271	# cstyle.bend owes, and this is the interesting half:
   >272	#   1. `OpenCLRenderer` (cstyle.py:348) is the renderer cl:124 registers. Its
    273	#      kernel text names the arguments `data0_4, data1_4` in BUFFER ORDER, and
    274	#      cl:57's `for i, (_, slot, dt, shape) in enumerate(self.signature)` walks
- :282 [at_no_revision] helpers.py:37 rev= toks=is_image_shape,shape
    280	#      bytes is FLOAT regardless of signedness. `img.fmt_of` is that table and it
    281	#      is a two-entry table, which is what makes it gateable at all.
   >282	#   3. `is_image_shape(shape)` (helpers.py:37) is `shape is not None and
    283	#      len(shape) == 3 and shape[-1] == 4` -- the LAST dim is 4, not the first.
    284	#      `img.is_image` is that and the gate has a fixture whose image is 4 in the

## tinybendygrad/runtime/ops_cpu.bend  (8 rows)
- :22 [only_older_revision] ops_cpu.py:70 rev=bdddaad219 toks=cn_slot,cn_walk,struct,pack_into
    20	#
    21	# THIS FILE ALSO CARRIES WHAT BOTH HALVES NEED, and `ops_null.bend` imports it as `C`:
   >22	#   * `Cn`/`cn_slot`/`cn_walk` -- ops_cpu.py:70's `struct.pack_into` slot walk, with
    23	#     the CORRECT `iter_sig` semantics; see the `device.bend` DEFECT report below,
    24	#     which is why they are declared here and not read from `device.bend`.
- :61 [only_older_revision] device.py:365 rev=bec565d157 toks=isig,TinyELF,iter_sig
    59	#
    60	# WHAT device.bend AND helpers.bend LEND, AND WHAT IS OWED BACK.
   >61	# LENT: `D.isig.go` (the offset-carrying body of `TinyELF.iter_sig`, device.py:365 --
    62	# device.bend's `iter_sig` entry point hard-codes 0, so BOTH uses here need `go`;
    63	# REPORTED, not fixed, device.bend is read-only to this unit); `D.dev_id` (device.py:397,
- :64 [only_older_revision] ops_null.py:58 rev=c509335eaa toks=timeline_bytes,timeline
    62	# device.bend's `iter_sig` entry point hard-codes 0, so BOTH uses here need `go`;
    63	# REPORTED, not fixed, device.bend is read-only to this unit); `D.dev_id` (device.py:397,
   >64	# inherited by both); `D.timeline_bytes` (`ops_null.py:58`'s `timeline` IS that call);
    65	# `H.round_up_u32`, `H.u32_list_eq`, `H.dedup_str`.
    66	# OWED: the renderer ORDER is the policy -- `Compiled._select_renderer` (device.py:489)
- :66 [at_no_revision] device.py:489 rev= toks=Compiled,_select_renderer
    64	# inherited by both); `D.timeline_bytes` (`ops_null.py:58`'s `timeline` IS that call);
    65	# `H.round_up_u32`, `H.u32_list_eq`, `H.dedup_str`.
   >66	# OWED: the renderer ORDER is the policy -- `Compiled._select_renderer` (device.py:489)
    67	# walks it and the FIRST INITIALISED renderer wins, and `cpu.renderers`/`ndev.renderers`
    68	# are those two orders transcribed and both are rows. `Compiled.has_copy_queue` is True
- :72 [only_older_revision] device.py:398 rev=9c1da89b5b toks=Compiled,peer_group
    70	# `cpu_has_copy_queue` and `nr_has_copy_queue_inherited` are two rows with DIFFERENT
    71	# answers -- either constant could be wrong without the other noticing.
   >72	# `Compiled.peer_group` (device.py:398) means a CPU device with no remote and no iface
    73	# answers its own device-class prefix -- `Device['CPU:1'].peer_group == 'CPU'`, MEASURED
    74	# -- and ops_cpu.py:92 overwrites it with the REMOTE's when there is one;
- :77 [only_older_revision] device.py:450 rev=ad189c0305 toks=Compiled,synchronize
    75	# `cpu.peer_of` is that two-arm choice and both arms are rows. `Compiled.wait_timeout_ms`
    76	# is `30000.0` (a float) and ops_cpu.py:81 writes the INT `30000`, so the row name says
   >77	# so. `Compiled.synchronize` (device.py:450) is what ops_cpu.py:96 adds a remote PING to.
    78	#
    79	# THE TWO GATES. For ops_cpu: the ORDER AND IDENTITY of the init call sequence --
- :77 [only_older_revision] ops_cpu.py:96 rev=bdddaad219 toks=Compiled,synchronize
    75	# `cpu.peer_of` is that two-arm choice and both arms are rows. `Compiled.wait_timeout_ms`
    76	# is `30000.0` (a float) and ops_cpu.py:81 writes the INT `30000`, so the row name says
   >77	# so. `Compiled.synchronize` (device.py:450) is what ops_cpu.py:96 adds a remote PING to.
    78	#
    79	# THE TWO GATES. For ops_cpu: the ORDER AND IDENTITY of the init call sequence --
- :114 [only_older_revision] tinygrad/runtime/ops_cpu.py:89 rev=bdddaad219 toks=int,parts,String,to_u32
    112	#    about the tree's shape. The four defs are generic in `List<&2, Call>` and lift
    113	#    unchanged if the coordinator wants them hoisted.
   >114	# 2. `int(parts[2])` (:89) is a DECIMAL PARSE and is a WALL: `String.to_u32` does not
    115	#    exist in 2.0.34, so a parse is a fold over `String.to_list(s)` feeding
    116	#    `U32.add(U32.mul(acc,10), Char.to_u32(c)-48)` and it raises on a non-numeric port --

## tinybendygrad/runtime/ops_cuda.bend  (2 rows)
- :20 [only_older_revision] ops_cuda.py:125 rev=741ec28536 toks=ops_cuda,count,_wait_signal
    18	# PART 2 -- CUDA. `ops_cuda.py`. STALE-LINE NOTE: the pre-split header said
    19	# "all 136 lines" and cited `cu:132` and `cu:134-136`; MEASURED against this
   >20	# tree `ops_cuda.py` is 129 lines, `count` is at :125 and `_wait_signal` at
    21	# :126. The citations are NOT renumbered here: `tinygrad/` is mid-rebase.
    22	#
- :21 [at_no_revision] tinygrad/runtime/ops_cuda.py:126 rev= toks=tinygrad
    19	# "all 136 lines" and cited `cu:132` and `cu:134-136`; MEASURED against this
    20	# tree `ops_cuda.py` is 129 lines, `count` is at :125 and `_wait_signal` at
   >21	# :126. The citations are NOT renumbered here: `tinygrad/` is mid-rebase.
    22	#
    23	# THE ONLY ONE OF THE THREE THAT IS NOT A SEQUENCE OF DRIVER CALLS. `CUDAQueue`

## tinybendygrad/runtime/ops_disk.bend  (3 rows)
- :22 [only_older_revision] tinygrad/runtime/ops_disk.py:101-116 rev=4c5ec46025 toks=_copyout_sharded
    20	#
    21	# THE PLACE A RESULT CAN BE CHECKED RATHER THAN A TRACE, and it is
   >22	# `_copyout_sharded` (:101-116). Every segment it yields is
    23	# `(copy_batch, copied_in, minor_offset, real_copy_size)` and `copied_in` is where
    24	# the segment LANDS in the destination. So the `real_copy_size`s must sum to
- :94 [only_older_revision] tinygrad/runtime/ops_disk.py:84-86 rev=4c5ec46025 toks=alloc_of,mv_address
    92	#   :81  MAP_LOCKED/MAP_POPULATE    PORTED  `map_locked`, `map_populate`
    93	#   :83  lru = False                PORTED  `ALLOC_LRU`
   >94	#   :84-86 _alloc                   PORTED  `alloc_of` (`mv_address` is WALL 1)
    95	#   :88  _free                      PORTED  `alloc_free`
    96	#   :89  _as_buffer                 PORTED  `alloc_as_buffer`
- :176 [only_older_revision] tinygrad/runtime/ops_disk.py:81 rev=4c5ec46025 toks=MAP_LOCKED,MAP_POPULATE,getattr
    174	#    rows.
    175	#
   >176	# C. `MAP_LOCKED`/`MAP_POPULATE` (:81) ARE PLATFORM CONSTANTS AND THE `getattr`
    177	#    IS VACUOUS. `map_populate` therefore takes ONE Bool (`osx`), not two, and the
    178	#    file says why rather than carrying a `hasattr` no fixture can falsify. The

## tinybendygrad/runtime/ops_dsp.bend  (16 rows)
- :35 [only_older_revision] tinygrad/runtime/ops_dsp.py:79 rev=81a4a9623c toks=alloc,mock_flags
    33	#   :73  DSPBuffer              PORTED  `DspBuf`, `buf.of`
    34	#   :78  _alloc                 PORTED  `alloc.alloc` (MOCKDSP and real arms)
   >35	#   :79    the MOCKDSP arm      PORTED  `alloc.mock_flags`
    36	#   :81    the ION arm          PORTED  `ION_ALIGN`, `ion.aligned`
    37	#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
- :38 [at_no_revision] tinygrad/runtime/ops_dsp.py:86-91 rev= toks=alloc,free_calls
    36	#   :81    the ION arm          PORTED  `ION_ALIGN`, `ion.aligned`
    37	#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
   >38	#   :86-91 _free                PORTED  `alloc.free_calls`
    39	#   :93  _as_buffer             PORTED  `alloc.as_buffer_bytes`
    40	#   :94  _copyin                PORTED  `alloc.copyin_bytes`
- :39 [at_no_revision] tinygrad/runtime/ops_dsp.py:93 rev= toks=alloc,as_buffer_bytes
    37	#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
    38	#   :86-91 _free                PORTED  `alloc.free_calls`
   >39	#   :93  _as_buffer             PORTED  `alloc.as_buffer_bytes`
    40	#   :94  _copyin                PORTED  `alloc.copyin_bytes`
    41	#   :95  _copyout               PORTED  `alloc.copyout_bytes`
- :40 [at_no_revision] tinygrad/runtime/ops_dsp.py:94 rev= toks=alloc,copyin_bytes
    38	#   :86-91 _free                PORTED  `alloc.free_calls`
    39	#   :93  _as_buffer             PORTED  `alloc.as_buffer_bytes`
   >40	#   :94  _copyin                PORTED  `alloc.copyin_bytes`
    41	#   :95  _copyout               PORTED  `alloc.copyout_bytes`
    42	#   :96  _offset                PORTED  `alloc.offset` -- offsets ACCUMULATE
- :41 [at_no_revision] tinygrad/runtime/ops_dsp.py:95 rev= toks=alloc,copyout_bytes
    39	#   :93  _as_buffer             PORTED  `alloc.as_buffer_bytes`
    40	#   :94  _copyin                PORTED  `alloc.copyin_bytes`
   >41	#   :95  _copyout               PORTED  `alloc.copyout_bytes`
    42	#   :96  _offset                PORTED  `alloc.offset` -- offsets ACCUMULATE
    43	#   :100 DSPCompiler.args       PORTED  `COMPILER_ARGS`, `compiler_args_first`
- :48 [at_no_revision] tinygrad/runtime/ops_dsp.py:113 rev= toks=compiler,cachekey_of
    46	#   :108 the whole script       PORTED  `link_script`
    47	#   :111 the -T flag            PORTED  `compiler_args_has_T`
   >48	#   :113 the cachekey           PORTED  `compiler.cachekey_of`
    49	#   :115 __del__                PORTED  `compiler.del_unlinks`
    50	#   :118 compile                WALL 1  the clang spawn + the .so read-back
- :49 [at_no_revision] tinygrad/runtime/ops_dsp.py:115 rev= toks=compiler,del_unlinks
    47	#   :111 the -T flag            PORTED  `compiler_args_has_T`
    48	#   :113 the cachekey           PORTED  `compiler.cachekey_of`
   >49	#   :115 __del__                PORTED  `compiler.del_unlinks`
    50	#   :118 compile                WALL 1  the clang spawn + the .so read-back
    51	#   :125 disassemble            WALL 1  cpu_objdump / llvm-objdump
- :52 [only_older_revision] tinygrad/runtime/ops_dsp.py:129 rev=161fee9a48 toks=dev,is_mock
    50	#   :118 compile                WALL 1  the clang spawn + the .so read-back
    51	#   :125 disassemble            WALL 1  cpu_objdump / llvm-objdump
   >52	#   :129 DSPDevice.__init__     PORTED  `dev.is_mock` (the ONE branch, :129-139)
    53	#   :132 the ion_fd open        PORTED  `dev.open_ion`
    54	#   :134-136 the shell buffer   PORTED  `dev.shell_size`, `dev.shell_copy`
- :54 [only_older_revision] tinygrad/runtime/ops_dsp.py:134-136 rev=0cdddf3495 toks=dev,shell_size,shell_copy
    52	#   :129 DSPDevice.__init__     PORTED  `dev.is_mock` (the ONE branch, :129-139)
    53	#   :132 the ion_fd open        PORTED  `dev.open_ion`
   >54	#   :134-136 the shell buffer   PORTED  `dev.shell_size`, `dev.shell_copy`
    55	#   :135 BufferSpec(nolru=True) PORTED  `dev.shell_spec` -- the eviction NEGATIVE
    56	#   :141 open_lib               PORTED  `dev.open_lib`, `dev.open_lib_sc`
- :55 [only_older_revision] tinygrad/runtime/ops_dsp.py:135 rev=0cdddf3495 toks=dev,shell_spec
    53	#   :132 the ion_fd open        PORTED  `dev.open_ion`
    54	#   :134-136 the shell buffer   PORTED  `dev.shell_size`, `dev.shell_copy`
   >55	#   :135 BufferSpec(nolru=True) PORTED  `dev.shell_spec` -- the eviction NEGATIVE
    56	#   :141 open_lib               PORTED  `dev.open_lib`, `dev.open_lib_sc`
    57	#   :143 the tinylib URL        PORTED  `OPEN_LIB_FP`, `open_lib_len`
- :60 [only_older_revision] tinygrad/runtime/ops_dsp.py:148 rev=ab8fb191b2 toks=dev,open_lib_handle
    58	#   :145 the two outs           PORTED  `open_lib_out0`, `open_lib_out1`
    59	#   :147 the raise              PORTED  `open_lib_bad`, `open_lib_err`
   >60	#   :148 the handle answer      PORTED  `dev.open_lib_handle`
    61	#   :150 close_lib              PORTED  `dev.close_lib`, `dev.close_lib_sc`
    62	#   :154-164 exec_lib           PORTED  `dev.exec_lib` -- open/invoke/close, retry
- :155 [only_older_revision] tinygrad/runtime/ops_dsp.py:46 rev=a6addc2d43 toks=supported_dtypes
    153	#                      four fp8s and bfloat16 -- and `unwrap` on that is a hard
    154	#                      failure. bfloat16 is the interesting one: `fmt is None` with
   >155	#                      itemsize 2, and `supported_dtypes` (:46) exists to keep it
    156	#                      out of the signature. That is the whole reason :46 is there.
    157	#   `dt_itemsize` (:68)  the WIDTH `struct.pack` writes, hence how many of an
- :183 [only_older_revision] tinygrad/runtime/ops_dsp.py:54 rev=a6addc2d43 toks=ins,outs,len,in_fds,pra
    181	# so `pra` has `3 + len(bufs)` entries: two ins, one out, then one dma per buffer.
    182	# `fds` is `[-1]*(ins+outs) ++ in_fds` (:53) and `attrs` is
   >183	# `[0]*(ins+outs) ++ [1]*len(in_fds)` (:54) -- SAME length as `pra`, and the `1`
    184	# is the only thing besides the length that tells a dma slot from a buffer slot.
    185	# `rpc_sc(method=2, ins=2, outs=1, fds=len(bufs))` (:70), so the selector is a
- :187 [only_older_revision] tinygrad/runtime/ops_dsp.py:63 rev=0cdddf3495 toks=pra
    185	# `rpc_sc(method=2, ins=2, outs=1, fds=len(bufs))` (:70), so the selector is a
    186	# function of ONE number. `pra_of` is gated at nine (ins,outs,fds) fixtures
   >187	# INCLUDING (2,1,16) -- one past the :63 refusal -- so a `pra` that grows where
    188	# Python's does not is visible.
    189	#
- :243 [at_no_revision] compiler_cpu.py:15 rev= toks=DSPRenderer,__init__
    241	#   * `ClangRenderer(Target("DSP","CLANG","hexagonv65,hexagonv65"))` RAISES
    242	#     `RuntimeError: unsupported arch: 'hexagonv65'` from ClangCompiler
   >243	#     (compiler_cpu.py:15). That is WHY `DSPRenderer.__init__` (:18) does not call
    244	#     `super().__init__`: a DSP target must never build the host CPU clang
    245	#     compiler. `dsp_no_super_init` pins that the compiler is the DSP one.
- :243 [only_older_revision] tinygrad/runtime/ops_dsp.py:18 rev=a6addc2d43 toks=DSPRenderer,__init__
    241	#   * `ClangRenderer(Target("DSP","CLANG","hexagonv65,hexagonv65"))` RAISES
    242	#     `RuntimeError: unsupported arch: 'hexagonv65'` from ClangCompiler
   >243	#     (compiler_cpu.py:15). That is WHY `DSPRenderer.__init__` (:18) does not call
    244	#     `super().__init__`: a DSP target must never build the host CPU clang
    245	#     compiler. `dsp_no_super_init` pins that the compiler is the DSP one.

## tinybendygrad/runtime/ops_hip.bend  (1 rows)
- :23 [only_older_revision] device.py:365 rev=bec565d157 toks=ret,value,iter_sig
    21	# WHAT IS HERE: `HP_*`, the HIP column of the vendor table `vend.hp`,
    22	# `hp_unchecked` (hp:16), `hp_err_of` (hp:10), `timing.scale_hp` (hp:57's
   >23	# `ret.value * 1e-3`), `iter_sig` (TinyELF.iter_sig, device.py:365), `hp.*` and
    24	# `HpDev`.
    25	#

## tinybendygrad/runtime/ops_metal.bend  (16 rows)
- :18 [only_older_revision] tinygrad/runtime/ops_metal.py:264 rev=ad189c0305 toks=off
    16	# ALU scalar packed into that struct. And `ops_metal.py:263` binds it with
    17	# `cmd.setKernelBuffer_offset_atIndex(buf.get_storage().meta, off, 0)`:
   >18	# buffer index 0, the ICB header Buffer, byte offset `off`. `:264` then sets the
    19	# geometry with `concurrentDispatchThreadgroups_threadsPerThreadgroup(MTLSize
    20	# (*dims[:3]), MTLSize(*dims[3:]))`, and `dims` is
- :93 [at_no_revision] tinygrad/runtime/ops_metal.py:55 rev= toks=std
    91	#   :41   __reduce__                WALL 3  PICKLE (a multiprocessing detail)
    92	#   :42   compile                   PARTIAL  the layout and the refusals
   >93	#   :55   macos_major/metal_version PORTED  the four-way `-std=` ladder
    94	#   :60   params                    PORTED  the f-string
    95	#   :62   src_padded/params_padded  PORTED  the 4-byte pad and the NUL
- :109 [only_older_revision] tinygrad/runtime/ops_metal.py:111 rev=c509335eaa toks=getaddr
    107	#   :105 MetalQueue.__init__        PORTED  the five accumulators
    108	#   :109 exec                       PORTED  the whole argument layout
   >109	#   :111 args                       PORTED  `getaddr` is 8 bytes, a var is its own
    110	#   :112 rows / :113 nbytes         PORTED  `layout_args` and the `max`
    111	#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
- :110 [only_older_revision] tinygrad/runtime/ops_metal.py:112 rev=c509335eaa toks=layout_args
    108	#   :109 exec                       PORTED  the whole argument layout
    109	#   :111 args                       PORTED  `getaddr` is 8 bytes, a var is its own
   >110	#   :112 rows / :113 nbytes         PORTED  `layout_args` and the `max`
    111	#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
    112	#   :123 wait                       PORTED  a no-op, ON PURPOSE
- :110 [at_no_revision] tinygrad/runtime/ops_metal.py:113 rev= toks=layout_args
    108	#   :109 exec                       PORTED  the whole argument layout
    109	#   :111 args                       PORTED  `getaddr` is 8 bytes, a var is its own
   >110	#   :112 rows / :113 nbytes         PORTED  `layout_args` and the `max`
    111	#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
    112	#   :123 wait                       PORTED  a no-op, ON PURPOSE
- :116 [only_older_revision] tinygrad/runtime/ops_metal.py:131 rev=c509335eaa toks=zero
    114	#   :127 submit                     PORTED  the ICB size and the header
    115	#   :129 the placeholder size       PORTED  and it EQUALS :253's buffer size
   >116	#   :131 patch                      PORTED  three zero rows at `zero`
    117	#   :135 the sizes loop             PORTED  one msgSend per symbolic command
    118	#   :138 run                        PORTED  thirteen calls, four arms
- :133 [at_no_revision] tinygrad/runtime/ops_metal.py:239 rev= toks=link_buffer
    131	#   :222 sels                       PORTED  18 u64 = 144 bytes, and the [3:5]
    132	#   :228 mark_resident              PORTED  both paths, and they are exclusive
   >133	#   :239 new_slots                  GONE    upstream deleted it; `link_buffer` replaced it
    134	#   :243 pipeline                   PORTED  four calls and `checked` twice
    135	#   :251 new_icb                    PORTED  the size and the eleven steps
- :134 [only_older_revision] tinygrad/runtime/ops_metal.py:243 rev=c3ee61fa7e toks=checked
    132	#   :228 mark_resident              PORTED  both paths, and they are exclusive
    133	#   :239 new_slots                  GONE    upstream deleted it; `link_buffer` replaced it
   >134	#   :243 pipeline                   PORTED  four calls and `checked` twice
    135	#   :251 new_icb                    PORTED  the size and the eleven steps
    136	#   :258 the ICB refusal           PORTED  refusal 5
- :142 [at_no_revision] tinygrad/runtime/ops_metal.py:276-281 rev= toks=dev,sync_scan
    140	#   :284-285 the autorelease pool   PORTED  pop-then-push, in that order
    141	#   :267 the ICB weak-dict         PORTED  `icb_keep`, and it WAS NOT CALLED
   >142	#   :276-281 the profile scan      PORTED  `dev.sync_scan`, and it WAS NOT CALLED
    143	#   :23   to_ns_str                PORTED  `cns_string`, and it WAS NOT WIRED
    144	#   :42-71 compile                 CLOSED  all of it but the block pointer
- :149 [at_no_revision] tinygrad/runtime/ops_metal.py:267 rev= toks=icb_keep,dev,sync_scan,sync_starts
    147	# ---------------------------------------------------------------------------
    148	# THREE DEFS WERE WRITTEN AND NOTHING REACHED THEM, and that is the finding this
   >149	# session started from. `icb_keep` (:267), `dev.sync_scan`'s list (`sync_starts`,
    150	# :276-281) and `cns_string` (:23) each carried a comment saying a row checked it,
    151	# and each was DEAD: correct, unread, and unreachable from `main`. A file whose
- :200 [at_no_revision] tinygrad/runtime/ops_metal.py:186 rev= toks=pm_lower
    198	#    `pm_bufferize` WAS a third one and it is GONE from upstream at the pin, so
    199	#    the port carries it no longer -- see the section that used to hold it.
   >200	#    The `pm_encode` rule is at :186 and the `pm_lower` rule at :190.
    201	#    TODO(p3) runtime/ops_metal.py:186  symbol=MetalQueue  -- `MetalQueue(s).encode()`.
    202	#    TODO(p3) runtime/ops_metal.py:192  symbol=mtl_msg  -- the `pm_lower` fence poll.
- :200 [only_older_revision] tinygrad/runtime/ops_metal.py:190 rev=a6addc2d43 toks=pm_encode,pm_lower
    198	#    `pm_bufferize` WAS a third one and it is GONE from upstream at the pin, so
    199	#    the port carries it no longer -- see the section that used to hold it.
   >200	#    The `pm_encode` rule is at :186 and the `pm_lower` rule at :190.
    201	#    TODO(p3) runtime/ops_metal.py:186  symbol=MetalQueue  -- `MetalQueue(s).encode()`.
    202	#    TODO(p3) runtime/ops_metal.py:192  symbol=mtl_msg  -- the `pm_lower` fence poll.
- :231 [only_older_revision] hcq2.py:74-76 rev=8ea900d1ba toks=iter_sig,layout_args
    229	#     `Made`, by the same rule `D.bnew` follows. `nbytes` is `size * itemsize`
    230	#     and a view's offset ACCUMULATES, so neither is a field here.
   >231	#  2. `D.iter_sig` IS `layout_args`' engine. `hcq2.py:74-76` is
    232	#     `[(offset + o, w) for (o,_),w in zip(TinyELF.iter_sig(item sizes), words)]`
    233	#     and `device.py:364-368` is what `D.iter_sig` ports. `q.layout` is the one
- :233 [only_older_revision] device.py:364-368 rev=bec565d157 toks=iter_sig,layout
    231	#  2. `D.iter_sig` IS `layout_args`' engine. `hcq2.py:74-76` is
    232	#     `[(offset + o, w) for (o,_),w in zip(TinyELF.iter_sig(item sizes), words)]`
   >233	#     and `device.py:364-368` is what `D.iter_sig` ports. `q.layout` is the one
    234	#     `zip` and nothing else -- re-deriving the rounding would be a SECOND
    235	#     transcription of device.py:364 and the two could disagree silently.
- :236 [at_no_revision] helpers.py:69 rev= toks=round_up,off,nbytes
    234	#     `zip` and nothing else -- re-deriving the rounding would be a SECOND
    235	#     transcription of device.py:364 and the two could disagree silently.
   >236	#  3. `D.round_up` is `helpers.py:69`, and `off = round_up(self.nbytes, 256)`
    237	#     (:112) and `at = round_up(self.nbytes, 8)` (:118) are both it.
    238	#  4. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and `new_icb`'s
- :239 [only_older_revision] tinygrad/runtime/ops_metal.py:253 rev=c509335eaa toks=BufferSpec,nolru,True
    237	#     (:112) and `at = round_up(self.nbytes, 8)` (:118) are both it.
    238	#  4. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and `new_icb`'s
   >239	#     `BufferSpec(nolru=True)` (:253) is one of them: a Metal ICB is NEVER
    240	#     recycled, which is a decision this file does not have to make and gets
    241	#     from `D.Bspec` by naming it. `mt_nolru` is the row.

## tinybendygrad/runtime/ops_npy.bend  (12 rows)
- :18 [only_older_revision] device.py:396 rev=9ff6db7b0e toks=renderers,Renderer
    16	#     None     -> self.runtime_t                               device.py:396
    17	#
   >18	# THE ARGUMENT NOBODY EXPECTS. `renderers or [Renderer]` at device.py:396 is an
    19	# `or`, and `[]` is FALSY, so `NpyDevice` is NOT the renderer-less device its
    20	# source line suggests -- it is handed `[Renderer]`, the same default every
- :28 [only_older_revision] device.py:398 rev=9c1da89b5b toks=iface,peer_group
    26	# `RDMADevice.__init__` (ops_rdma.py:70) calls `self._select_iface(device)`.
    27	# `NpyDevice.__init__` does not. So:
   >28	#   * `self.iface` is never set, and `peer_group` (device.py:398) falls all the
    29	#     way through `getattr(getattr(self,'iface',None),'peer_group', …)` to
    30	#     `device.split(":")[0]` -- the head, "NPY".
- :31 [only_older_revision] device.py:397 rev=8b5a02db7f toks=device_id,Compiled,__init__
    29	#     way through `getattr(getattr(self,'iface',None),'peer_group', …)` to
    30	#     `device.split(":")[0]` -- the head, "NPY".
   >31	#   * `device_id` comes from `Compiled.__init__` (device.py:397) and NOT from
    32	#     `_select_iface` (device.py:494), which sets it FIRST and then asserts on
    33	#     the deprecated `NPY_IFACE` env var. Two lines of Python set the same
- :32 [at_no_revision] device.py:494 rev= toks=_select_iface
    30	#     `device.split(":")[0]` -- the head, "NPY".
    31	#   * `device_id` comes from `Compiled.__init__` (device.py:397) and NOT from
   >32	#     `_select_iface` (device.py:494), which sets it FIRST and then asserts on
    33	#     the deprecated `NPY_IFACE` env var. Two lines of Python set the same
    34	#     field and only one of them can run here.
- :37 [only_older_revision] device.py:488 rev=9c1da89b5b toks=arch,_select_renderer
    35	#   * `self.host` is device.py:418, `host_name(peer_group, HCQ_RUNTIME_DEV)`,
    36	#     which for a local peer group is the string "CPU".
   >37	#   * `arch` is None, so `_select_renderer` (device.py:488) passes NO `arch`
    38	#     kwarg at all: `**({"arch": self.arch} if self.arch else {})`.
    39	#   * `NpyDevice.ifaces` is `[]`, inherited from `Compiled` (device.py:377).
- :39 [only_older_revision] device.py:377 rev=33cd373ad3 toks=NpyDevice,ifaces,Compiled
    37	#   * `arch` is None, so `_select_renderer` (device.py:488) passes NO `arch`
    38	#     kwarg at all: `**({"arch": self.arch} if self.arch else {})`.
   >39	#   * `NpyDevice.ifaces` is `[]`, inherited from `Compiled` (device.py:377).
    40	#
    41	# ===========================================================================
- :59 [only_older_revision] device.py:304-330 rev=c52b227c7b toks=HostAllocator
    57	# ===========================================================================
    58	# WHAT IS PORTED, DEF BY DEF. The first block is `ops_npy.py` and the second is
   >59	# `HostAllocator` (device.py:304-330), which is the surface those four lines
    60	# expose and which nothing else in `runtime/` re-implements.
    61	#
- :83 [only_older_revision] device.py:307 rev=c52b227c7b toks=mmap,size,access,ACCESS_WRITE
    81	# THE THREE WALLS.
    82	#
   >83	# 1. MMAP (device.py:307). `mmap.mmap(-1, size, access=ACCESS_WRITE)` is a
    84	#    syscall and this file reaches host memory the way `device.bend` reaches
    85	#    it -- by NAMING the call in a trace. `mmap`/`munmap`/`memcpy` and
- :86 [at_no_revision] helpers.py:573 rev= toks=to_mv,ctypes,from_address
    84	#    syscall and this file reaches host memory the way `device.bend` reaches
    85	#    it -- by NAMING the call in a trace. `mmap`/`munmap`/`memcpy` and
   >86	#    `to_mv` (helpers.py:573, `ctypes.from_address`) are FFI seams.
    87	#    TODO(p3) device.py:297  symbol=_alloc  mmap.mmap -- the mapping syscall.
    88	#    TODO(p3) helpers.py:575  symbol=to_mv  to_mv -- `memoryview((ctypes.c_uint8*sz).from_address(ptr))`.
- :93 [only_older_revision] device.py:328 rev=8b5a02db7f toks=Device,buf,device
    91	#    it, and the three calls inside it are what the gate pins.
    92	#    TODO(p3) device.py:310  symbol=_copyin  cpu_profile -- the `with` and its profile event.
   >93	# 3. `Device[buf.device]` (device.py:328). Opening a device by string is a
    94	#    registry lookup and a hardware open. `device.bend` OWES this file the
    95	#    already-opened set, so the port compares host NAMES rather than
- :110 [only_older_revision] device.py:270 rev=8b5a02db7f toks=Allocator,alloc,size
    108	#
    109	# THE RAISES ARE IN THE TRACE, both of them, and they are the device's two
   >110	# refusals: `Allocator.alloc`'s `assert size > 0` (device.py:270) and
    111	# `HostAllocator._map`'s host guard (device.py:328). A refusal records itself
    112	# and truncates: `Tr.emit` records NOTHING once `refused` is set, so
- :111 [at_no_revision] device.py:328 rev= toks=HostAllocator,_map
    109	# THE RAISES ARE IN THE TRACE, both of them, and they are the device's two
    110	# refusals: `Allocator.alloc`'s `assert size > 0` (device.py:270) and
   >111	# `HostAllocator._map`'s host guard (device.py:328). A refusal records itself
    112	# and truncates: `Tr.emit` records NOTHING once `refused` is set, so
    113	# `alloc(0)` shows as `[REFUSE]` and never reaches `mmap`, which is what

## tinybendygrad/runtime/ops_null.bend  (2 rows)
- :34 [only_older_revision] ops_cpu.py:84 rev=bdddaad219 toks=False,cpu,has_copy_queue
    32	# `nr.has_copy_queue` is a NULL fact -- `ops_null.py` does not override
    33	# `@property def has_copy_queue` at all, so NULL inherits `Compiled`'s `True` while
   >34	# `ops_cpu.py:84` returns `False`. `C.cpu.has_copy_queue` is the other half of that
    35	# pair and it lives in `ops_cpu.bend` beside the comment explaining why two rows exist.
    36	#
- :38 [only_older_revision] runtime/support/hcq2.py:78-83 rev=a6addc2d43 toks=pack_args
    36	#
    37	# ONE FILE IN HERE IS NOT MINE TO MOVE. `pk`/`Pk`/`fx_pk`/`pkend` and the `pk_*` rows
   >38	# port `pack_args`, which is `runtime/support/hcq2.py:78-83` -- a file with its own
    39	# `.bend` and another unit's. They stay here because `ops_null.py:29-30` builds the
    40	# kernargs through them. THE FIX IS TO MOVE THEM to `runtime/support/hcq2.bend`;

## tinybendygrad/runtime/ops_nv.bend  (7 rows)
- :13 [only_older_revision] tinygrad/runtime/ops_nv.py:47-48 rev=e8308c08f7 toks=nvm,hilo,nv_flags
    11	#            (_ensure_has_local_memory), :449-451 (alloc's page size).
    12	#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
   >13	#            `nvm` word encoding (:47-48), `hilo` (:33), `nv_flags` (:40-41), the
    14	#            `layout_args` kernel-argument trace (hcq2.py:74-76), and the four
    15	#            queues' command vocabularies (:99-225).
- :13 [only_older_revision] tinygrad/runtime/ops_nv.py:33 rev=c509335eaa toks=nvm,hilo,nv_flags
    11	#            (_ensure_has_local_memory), :449-451 (alloc's page size).
    12	#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
   >13	#            `nvm` word encoding (:47-48), `hilo` (:33), `nv_flags` (:40-41), the
    14	#            `layout_args` kernel-argument trace (hcq2.py:74-76), and the four
    15	#            queues' command vocabularies (:99-225).
- :13 [only_older_revision] tinygrad/runtime/ops_nv.py:40-41 rev=e8308c08f7 toks=nvm,hilo,nv_flags
    11	#            (_ensure_has_local_memory), :449-451 (alloc's page size).
    12	#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
   >13	#            `nvm` word encoding (:47-48), `hilo` (:33), `nv_flags` (:40-41), the
    14	#            `layout_args` kernel-argument trace (hcq2.py:74-76), and the four
    15	#            queues' command vocabularies (:99-225).
- :14 [only_older_revision] hcq2.py:74-76 rev=8ea900d1ba toks=layout_args
    12	#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
    13	#            `nvm` word encoding (:47-48), `hilo` (:33), `nv_flags` (:40-41), the
   >14	#            `layout_args` kernel-argument trace (hcq2.py:74-76), and the four
    15	#            queues' command vocabularies (:99-225).
    16	#   STAGE 3  LANDED AND CHECKED. the program cache (:313-320 -- the lookup is
- :23 [only_older_revision] hcq2.py:63 rev=dc9af790e2 toks=to_name,reg_ops
    21	#   STAGE 4  LANDED AND CHECKED. the QMD version/slot/grid layer (:50-94), the
    22	#            ioctl command encoding (:43-45), the video-HW sizing (:699-715),
   >23	#            `to_name` (hcq2.py:63), `reg_ops`'s chunking (:818-824), the
    24	#            profiler register addresses (:793-816), the error-string tables
    25	#            (:35, :37-38) and the GPA-info index fallback (:664-665).
- :23 [only_older_revision] tinygrad/runtime/ops_nv.py:818-824 rev=06e57e3298 toks=to_name,reg_ops
    21	#   STAGE 4  LANDED AND CHECKED. the QMD version/slot/grid layer (:50-94), the
    22	#            ioctl command encoding (:43-45), the video-HW sizing (:699-715),
   >23	#            `to_name` (hcq2.py:63), `reg_ops`'s chunking (:818-824), the
    24	#            profiler register addresses (:793-816), the error-string tables
    25	#            (:35, :37-38) and the GPA-info index fallback (:664-665).
- :66 [only_older_revision] tinygrad/runtime/ops_nv.py:43-45 rev=e8308c08f7 toks=nv_iowr
    64	#   TODO(p3) ops_nv.py:349-380  NVKIface.__init__      WALL: /dev/nvidiactl,
    65	#     /dev/nvidia-uvm opens and the three rm_controls that pick the driver
   >66	#     version table. `nv_iowr` (:43-45) is PORTED as an ENCODER and the actual
    67	#     `fd.ioctl(...)` is the seam.
    68	#   TODO(p3) ops_nv.py:385-401  rm_alloc/rm_control/uvm -- NVOS21/NVOS54/

## tinybendygrad/runtime/ops_python.bend  (9 rows)
- :24 [only_older_revision] ops_python.py:70 rev=5f93061f67 toks=loop_ends
    22	#     right and the remaining 120 are untouched, so the inner loop is right and
    23	#     the OUTER one's back edge is not: `Prog.loop`/`Prog.rng` walk
   >24	#     `loop_ends` and the nested END at ops_python.py:70 jumps to the inner head.
    25	#   * pad -- refused. The refusal is `Prog.bad`, so it is an oob load or store.
    26	#
- :49 [at_no_revision] tinygrad/runtime/ops_python.py:94 rev= toks=vals
    47	#   :85  STORE          PORTED  gated, vector, stepped
    48	#   :93  AFTER, BITCAST@GLOBAL/LOCAL    PORTED (pass-through)
   >49	#   :94  PARAM@ALU      PORTED  reads a `vals` entry
    50	#   :95  PARAM, BUFFER  PORTED  binds a buffer, or allocates zeros
    51	#   :106 BINARY         WALL  ops_python.py:106 -- `memoryview(u.arg)` is raw
- :81 [at_no_revision] ops.py:1417-1424 rev= toks=KeyError
    79	#    arm at all.
    80	# 2. `Ops.FDIV` AND `Ops.THREEFRY` ARE IN `GroupOp.ALU` BUT NOT IN `python_alu`
   >81	#    (ops.py:1417-1424), so ops_python.py:154 raises `KeyError` on them. They are
    82	#    WALL 3 below for the same reason rather than given an invented meaning.
    83	# 3. THERE ARE NO `DEFINE_*` OPS in this tinygrad. `Ops` has PARAM and BUFFER and
- :98 [at_no_revision] dtype.py:296-297 rev= toks=truncate
    96	#    lanes are i32, u32, f32 and bool, where `w == dtype.itemsize` always, so
    97	#    that arm is DEAD here and the four lanes take the first branch verbatim.
   >98	#    `truncate` has the same shape: dtype.py:296-297 answers float16, bfloat16,
    99	#    the four fp8s, float64, six narrow ints and int64/uint64 through ctypes and
    100	#    struct, and only bool/int32/uint32/float32 are pure in Bend. So CAST is
- :108 [only_older_revision] ops_python.py:33 rev=0a5776355e toks=wmma,tcore,frag_coords
    106	#    TODO(p3) tinygrad/dtype.py:289  symbol=truncate -- `truncate` for the ten C widths.
    107	#
   >108	# 2. TENSOR CORES. `wmma` (ops_python.py:33) needs `tcore.frag_coords()` and a
    109	#    three-way fragment layout, and its `arg` is a `(dims, dtype_in, threads)`
    110	#    tuple. There is no v1 spelling and no scalar lane for a fragment.
- :115 [only_older_revision] ops.py:1429 rev=a26c50b019 toks=exec_alu
    113	# 3. `Ops.FDIV` AND `Ops.THREEFRY` -- see MEASURED FACT 2.
    114	#
   >115	# 4. THE TUPLE OPERAND BRANCH. `exec_alu`'s first line (ops.py:1429) is
    116	#    `if any(isinstance(x, tuple) for x in operands)` and it recurses per lane.
    117	#    symbolic.bend ports only the scalar spine, so `alu1/2/3` below call the same
- :124 [only_older_revision] ops.py:1412 rev=ad189c0305 toks=inf
    122	#    packet is `CONST(Invalid)`.
    123	#    ONE DIVERGENCE IS INHERITED, and it is named where it bites: `safe_pow`
   >124	#    (ops.py:1412) answers `inf if x > 0 else -inf` for a negative base with a
    125	#    fractional exponent, where IEEE -- and therefore `exec_alu_f32` -- answers
    126	#    nan. Taking IEEE over a Python-shaped branch nobody can compute is
- :144 [only_older_revision] ops_python.py:99 rev=4e0192eaf4 toks=BUFFER
    142	#
    143	# A1. There are no `DEFINE_*` ops (MEASURED FACT 3); the arms are `PARAM` and
   >144	#     `BUFFER` plus an AddrSpace (ops_python.py:99,105). So the brief's
    145	#     DEFINE_GLOBAL/LOCAL/REG/VAR/BUF are spelled `PARAM`/`BUFFER` and the
    146	#     addrspace rides in `<arg>`:
- :156 [only_older_revision] ops_python.py:104 rev=0a5776355e toks=pbufs
    154	#     encoder never has to repeat it.
    155	#     PACKET BUFFER ORDER: packet buffer i is the i-th `PARAM` of addrspace g or l
   >156	#     in uop order, because ops_python.py:104 pops `pbufs` in exactly that order.
    157	#     A PARAM inside a RANGE loop would pop a second time in Python too, so
    158	#     resolving the index once at parse time is the same answer.

## tinybendygrad/runtime/ops_qcom.bend  (15 rows)
- :22 [only_older_revision] tinygrad/runtime/ops_qcom.py:303 rev=225f6d0ec3 toks=flag,_SHIFT,_MASK
    20	#      table this project gates best, because a wrong entry is a silent
    21	#      wrong kernel and a table gates in both directions.
   >22	#   2. `flag` (:303) over the four kgsl `_SHIFT`/`_MASK` pairs.
    23	#   3. The six DERIVED program sizes (:232-237), pure U32 arithmetic over
    24	#      `pvtmem`, `shmem`, `fregs`, `hregs`, `tex_cnt`, `ibo_cnt`, `samp_cnt`.
- :44 [only_older_revision] tinygrad/runtime/ops_qcom.py:43 rev=4f781611a8 toks=ctz
    42	#   :34-41 the qreg format        PORTED  `mesa_name`, `qreg_name`
    43	#   :36-41 _qreg_exec             PORTED  `qregs`, `qfields`, `qreg.of`
   >44	#   :43  ctz                      PORTED  `ctz` (see THE Ctz PRECONDITION)
    45	#   :45-47 parity                 PORTED  `parity`
    46	#   :49  pkt7_hdr                 PORTED  `pkt7_hdr`
- :46 [only_older_revision] tinygrad/runtime/ops_qcom.py:49 rev=4f781611a8 toks=pkt7_hdr
    44	#   :43  ctz                      PORTED  `ctz` (see THE Ctz PRECONDITION)
    45	#   :45-47 parity                 PORTED  `parity`
   >46	#   :49  pkt7_hdr                 PORTED  `pkt7_hdr`
    47	#   :51  pkt4_hdr                 PORTED  `pkt4_hdr`
    48	#   :53  _read_lib                PORTED  `read_lib` (little-endian u32)
- :47 [only_older_revision] tinygrad/runtime/ops_qcom.py:51 rev=4f781611a8 toks=pkt4_hdr
    45	#   :45-47 parity                 PORTED  `parity`
    46	#   :49  pkt7_hdr                 PORTED  `pkt7_hdr`
   >47	#   :51  pkt4_hdr                 PORTED  `pkt4_hdr`
    48	#   :53  _read_lib                PORTED  `read_lib` (little-endian u32)
    49	#   :303 flag                     PORTED  `kgsl_flags`, both directions, `flag`
- :49 [only_older_revision] tinygrad/runtime/ops_qcom.py:303 rev=225f6d0ec3 toks=kgsl_flags,flag
    47	#   :51  pkt4_hdr                 PORTED  `pkt4_hdr`
    48	#   :53  _read_lib                PORTED  `read_lib` (little-endian u32)
   >49	#   :303 flag                     PORTED  `kgsl_flags`, both directions, `flag`
    50	#   :18-19 autogen imports        PORTED  `MESA_*`/`KGSL_*` constants (62)
    51	#
- :90 [only_older_revision] tinygrad/runtime/ops_qcom.py:43 rev=4f781611a8 toks=ctz
    88	#   :34-41 the qreg name format      PORTED  `mesa_of`, `qreg_of`, `is_reg_name`
    89	#   :36-41 `_qreg_exec`              PORTED  `qregs`, `qfields`, `qreg.of`
   >90	#   :43   ctz                        PORTED  `ctz` (see THE ctz PRECONDITION)
    91	#   :45-47 parity                    PORTED  `parity`
    92	#   :49   pkt7_hdr                   PORTED  `pkt7_hdr`
- :92 [only_older_revision] tinygrad/runtime/ops_qcom.py:49 rev=4f781611a8 toks=pkt7_hdr
    90	#   :43   ctz                        PORTED  `ctz` (see THE ctz PRECONDITION)
    91	#   :45-47 parity                    PORTED  `parity`
   >92	#   :49   pkt7_hdr                   PORTED  `pkt7_hdr`
    93	#   :51   pkt4_hdr                   PORTED  `pkt4_hdr`
    94	#   :53   _read_lib                  PORTED  `read_lib`, `read_words`
- :93 [only_older_revision] tinygrad/runtime/ops_qcom.py:51 rev=4f781611a8 toks=pkt4_hdr
    91	#   :45-47 parity                    PORTED  `parity`
    92	#   :49   pkt7_hdr                   PORTED  `pkt7_hdr`
   >93	#   :51   pkt4_hdr                   PORTED  `pkt4_hdr`
    94	#   :53   _read_lib                  PORTED  `read_lib`, `read_words`
    95	#   :57-59 the cmd/reg word count    PORTED  `qwords`
- :102 [only_older_revision] tinygrad/runtime/ops_qcom.py:202-203 rev=225f6d0ec3 toks=ioctl_cmd
    100	#   :119-120 the dims refusal        PORTED  `rf.dims` + `Tr.refuse`
    101	#   :115-192 exec                    PORTED  `exec.of` and its 27-call trace
   >102	#   :202-203 the ioctl command word  PORTED  `ioctl_cmd`
    103	#   :206-283 QCOMProgramData         PORTED  `pd.parse_full`, `desc.*`, `const.*`
    104	#   :228/272 the two offset rules    PORTED  `pd.nir_*`, `pd.cl_*`
- :103 [only_older_revision] tinygrad/runtime/ops_qcom.py:206-283 rev=eeaadb99a2 toks=parse_full,desc,const
    101	#   :115-192 exec                    PORTED  `exec.of` and its 27-call trace
    102	#   :202-203 the ioctl command word  PORTED  `ioctl_cmd`
   >103	#   :206-283 QCOMProgramData         PORTED  `pd.parse_full`, `desc.*`, `const.*`
    104	#   :228/272 the two offset rules    PORTED  `pd.nir_*`, `pd.cl_*`
    105	#   :232-237 the six derived sizes   PORTED  `pd.*`
- :109 [only_older_revision] tinygrad/runtime/ops_qcom.py:303 rev=225f6d0ec3 toks=flag,kgsl_flags
    107	#   :285-292 `qcom_build_program`    PORTED  `qcom.get`, `ce.find`, `ce.put`
    108	#   :294-301 QCOMAllocator           WALL 3  `:301 _offset` is device.bend's own
   >109	#   :303  `flag`                     PORTED  `kgsl_flags`, both directions
    110	#   :314-345 QCOMDevice.__init__     PARTIAL the flags and the gpu_id refusal
    111	#   :331-345 the init SEQUENCE       WALL 4  the ioctls and mmap are seams
- :116 [only_older_revision] tinygrad/runtime/ops_qcom.py:388-392 rev=06e57e3298 toks=Buffer
    114	#   :364-372 _gpu_map                WALL 4  the ioctl, the EFAULT arm
    115	#   :381-386 _wait_signal            WALL 4  the timestamp ioctls
   >116	#   :388-392 _ensure_stack_size      WALL 3  it is `Buffer` and device.bend's
    117	#   :394-396 _at_profile_finalize    WALL 4  sysfs
    118	#
- :122 [only_older_revision] hcq2.py:69-83 rev=a6addc2d43 toks=layout_args,pack_args
    120	#
    121	#   :89-113 `kernargs`               WALL 1+2  the argument trace proper. What
   >122	#        survives here is `layout_args`/`pack_args` (hcq2.py:69-83), the two
    123	#        functions `kernargs` is built from, and the pad SEQUENCE they produce.
    124	#        The buffer/image/sampler SELECTION at :91-94 and the `tex_to_image`
- :124 [only_older_revision] tinygrad/runtime/ops_qcom.py:91-94 rev=225f6d0ec3 toks=tex_to_image
    122	#        survives here is `layout_args`/`pack_args` (hcq2.py:69-83), the two
    123	#        functions `kernargs` is built from, and the pad SEQUENCE they produce.
   >124	#        The buffer/image/sampler SELECTION at :91-94 and the `tex_to_image`
    125	#        permutation at :94 are not ported.
    126	#   :104-112 `_tex`                   WALL 1  the 16-word image descriptor
- :163 [only_older_revision] ops_qcom.py:132 rev=741ec28536 toks=dev,tag,stack
    161	#   .agents/slop/qc_exec_oracle.py    the REAL `QCOMComputeQueue.exec` -- **NOT RESTORED, IT IS
    162	#                                     RED**: its own stub device `D` has no `tag`, and the live
   >163	#                                     `ops_qcom.py:132` calls `self.dev.tag("stack")`, so it dies
    164	#                                     `AttributeError: 'D' object has no attribute 'tag'`. It
    165	#                                     measured a thing that still exists; the FIXTURE is one

## tinybendygrad/runtime/ops_rdma.bend  (16 rows)
- :10 [at_no_revision] tinygrad/runtime/ops_rdma.py:140 rev= toks=rdma_copies
    8	#      virtual address, and the NIC answers a KEY. From that moment the GPU
    9	#      address is not usable by the NIC and the key is not usable by the GPU, and
   >10	#      `rdma_copies` (:140) puts BOTH in every work queue element. So there is a
    11	#      TRANSLATION TABLE and a wrong entry in it is a silently wrong transfer --
    12	#      which is why `Pdt` carries it in BOTH directions and why `ops.wqe`
- :44 [at_no_revision] tinygrad/runtime/ops_rdma.py:18 rev= toks=vram_bar
    42	#
    43	#   :16  RDMA_CHUNK                  PORTED  `RDMA_CHUNK()`
   >44	#   :18  BNXT_IDS                     PORTED  the four constants and `vram_bar`
    45	#   :22  `BNXTIface.__init__`         PORTED  `Iface.of`  -- vram_bar=2,
    46	#                                               base_class, dev_impl_t, the PCs
- :75 [at_no_revision] ops_rdma.py:57-58 rev= toks=min
    73	#   :64  the closest NIC              NOT PORTED -- inside `rdma_nic_for`, a `min(...)`
    74	#   THE FOUR ABOVE SAID "PORTED" AND WERE NOT. `node`/`bus` are nested defs INSIDE `rdma_nic_for`
   >75	#   (ops_rdma.py:57-58) and the closest nic is a `min(...)` at :64; MEASURED, there is no `def
    76	#   nic.node` (or `.bus`/`.list`/`.closest`) anywhere in the port, and no `rdma_nic_for` either. The
    77	#   error's shape: a NAME was read in the CPython and a SAME-NAMED def assumed in the port.
- :87 [only_older_revision] tinygrad/runtime/ops_rdma.py:85 rev=e15997f1ba toks=PatternMatcher,rules,pm_bufferize,qp_len
    85	#                                               rq_seq psn, db
    86	#   :84  the UPat rules               PORTED  `qp.rules_len` -- 8 tags, FIRST-WINS
   >87	#   :85  `PatternMatcher(rules) + pm_bufferize` PORTED `qp_len`
    88	#   :86  `connect` both ways          PORTED  `qp.connect` -- nics THEN reversed
    89	#   :89  `rdma_mem`                   PORTED  `mem.of` -- volatile, dtype, tag
- :96 [only_older_revision] tinygrad/runtime/ops_rdma.py:101 rev=e15997f1ba toks=is_rdma,wire
    94	#   :96  `rdma_db`                    PORTED  `mem.db`   -- one whole page
    95	#   :99-100 `rdma_wire`               PORTED  `wire.of`  -- CALL/STORE, then RDMA
   >96	#   :101 `is_rdma`                    PORTED  `wire.is_rdma`
    97	#   :104-106 `queue_of`               PORTED  `queue.hi`/`queue.lo` -- the SORTED
    98	#                                               pair and
- :100 [only_older_revision] tinygrad/runtime/ops_rdma.py:109 rev=a1798d4db5 toks=ins,queue,is_recv
    98	#                                               pair and
    99	#                                               `wire is src`
   >100	#   :109 `ins`                        PORTED  `queue.is_recv` -- every int is a uint32
    101	#   :112 `queue_of(calls[0])`         PORTED  `copies.cap_ok` + `Tr.count`
    102	#   :113 `rdma_qp(pair)[nic.device]`  PORTED  `qp.new`
- :105 [only_older_revision] tinygrad/runtime/ops_rdma.py:118 rev=e15997f1ba toks=len,chunks,sum,nchunks,ops,n_writes
    103	#   :116 `bufs = [args[c][0 if recv else 1]]` PORTED `ops.wqe`
    104	#   :117 the chunks comprehension     PORTED  `chunks_of` / `nchunks` / `psns_len`
   >105	#   :118 `len(chunks), sum(chunks)`   PORTED  `nchunks`, `ops.n_writes`
    106	#   :120 the ring-cap ASSERT          PORTED  `copies.guard`  (the REFUSAL)
    107	#   :123 the bumps                    PORTED  `bump.seq` / `bump.psn`
- :108 [only_older_revision] tinygrad/runtime/ops_rdma.py:125 rev=e15997f1ba toks=accumulate,chunks,psns_of
    106	#   :120 the ring-cap ASSERT          PORTED  `copies.guard`  (the REFUSAL)
    107	#   :123 the bumps                    PORTED  `bump.seq` / `bump.psn`
   >108	#   :125 `accumulate(chunks, 0)`      PORTED  `psns_of`
    109	#   :126 `n`, `p`                     PORTED  `ops.n_of` / `ops.p_of`
    110	#   :128 `ring.getaddr`, `cq.getaddr` PORTED  `ins.write` / `ins.cq_db`
- :109 [only_older_revision] tinygrad/runtime/ops_rdma.py:126 rev=1a58c3ae9d toks=ops,n_of,p_of
    107	#   :123 the bumps                    PORTED  `bump.seq` / `bump.psn`
    108	#   :125 `accumulate(chunks, 0)`      PORTED  `psns_of`
   >109	#   :126 `n`, `p`                     PORTED  `ops.n_of` / `ops.p_of`
    110	#   :128 `ring.getaddr`, `cq.getaddr` PORTED  `ins.write` / `ins.cq_db`
    111	#   :129 the `db` address             PORTED  `ins.ring_db` -- low 12 bits only
- :111 [only_older_revision] tinygrad/runtime/ops_rdma.py:129 rev=18345d059b toks=ins,ring_db
    109	#   :126 `n`, `p`                     PORTED  `ops.n_of` / `ops.p_of`
    110	#   :128 `ring.getaddr`, `cq.getaddr` PORTED  `ins.write` / `ins.cq_db`
   >111	#   :129 the `db` address             PORTED  `ins.ring_db` -- low 12 bits only
    112	#   :130-131 `db_value`               PORTED  `db_value.hi` / `db_value.lo`
    113	#   :136-137 the chunk loop           PORTED  `ops.chunk_size` / `ops.wqe`
- :119 [only_older_revision] tinygrad/runtime/ops_rdma.py:152 rev=e15997f1ba toks=ins,cq_db
    117	#   :148 the ring doorbell            PORTED  `ins.ring_db`
    118	#   :151 `wait_eq`                    PORTED  `ins.wait` -- the inverted epoch
   >119	#   :152 the cq doorbell              PORTED  `ins.cq_db`
    120	#   :155 the recv barrier             PORTED  `ins.barrier`
    121	#   :162 the `{i: queue_of(u)}` dict  PORTED  `submit.fires`
- :125 [only_older_revision] tinygrad/runtime/ops_rdma.py:166 rev=a08c6742c6 toks=positions,submit,pos_at
    123	#                                               keeps ITSELF
    124	#   :165 `dict.fromkeys(queues.values())` PORTED `submit.srcs_kept`
   >125	#   :166 `positions`                  PORTED  `submit.pos_at`
    126	#   :167 the zip                      PORTED  `psns_at` + `ops.n_of`
    127	#   :169 `pm_rdma_encode`             PORTED  `encode_len`
- :126 [only_older_revision] tinygrad/runtime/ops_rdma.py:167 rev=18345d059b toks=psns_at,ops,n_of
    124	#   :165 `dict.fromkeys(queues.values())` PORTED `submit.srcs_kept`
    125	#   :166 `positions`                  PORTED  `submit.pos_at`
   >126	#   :167 the zip                      PORTED  `psns_at` + `ops.n_of`
    127	#   :169 `pm_rdma_encode`             PORTED  `encode_len`
    128	#
- :127 [only_older_revision] tinygrad/runtime/ops_rdma.py:169 rev=18345d059b toks=pm_rdma_encode,encode_len
    125	#   :166 `positions`                  PORTED  `submit.pos_at`
    126	#   :167 the zip                      PORTED  `psns_at` + `ops.n_of`
   >127	#   :169 `pm_rdma_encode`             PORTED  `encode_len`
    128	#
    129	# ===========================================================================
- :150 [only_older_revision] tinygrad/runtime/ops_rdma.py:140 rev=e15997f1ba toks=unwrap_view
    148	#    whether the registration is right.
    149	#    TODO(p3) ops_rdma.py:46  symbol=_map  PCIIfaceBase.p2p_paddrs.
   >150	# 4. `unwrap_view` (:140). Collapsing a view chain to (base, offset) and then
    151	#    `getaddr(nic.device)` on it. The NIC-side address IS the key the
    152	#    registration handed back, so the port reads it out of `Pdt` -- which is the
- :165 [at_no_revision] tinygrad/runtime/ops_rdma.py:145 rev= toks=slot,next,psn
    163	#        only the slot and the epoch. MEASURED, and it is the sharpest thing in
    164	#        this file: `rdma_db_hi_dropped`. REPORTED, not fixed.
   >165	#      the msn entry (:145) is `slot << 48 | next << 24 | psn`, all three fields
    166	#        24 bits wide and `slot` in the TOP 16. So `msn.hi(slot, next)` and
    167	#        `msn.lo(next, psn)` are exact halves and no shift is missing.

## tinybendygrad/runtime/ops_webgpu.bend  (19 rows)
- :19 [at_no_revision] tinygrad/runtime/ops_webgpu.py:11 rev= toks=dev,create_instance
    17	#
    18	#   :10  backend_types               PORTED  `backend_names`, `backend_of`
   >19	#   :11  the module-level instance    PORTED  `dev.create_instance`
    20	#   :13  from_wgpu_str               WALL 1  STRING VIEWS
    21	#   :14  to_wgpu_str                 WALL 1  STRING VIEWS
- :29 [only_older_revision] tinygrad/runtime/ops_webgpu.py:48 rev=77a76d1b13 toks=dev,request_adapter
    27	#   :46  DevicePopErrorScope         PORTED  a WAIT, in `Tr.pop`
    28	#   :47  DeviceCreateComputePipeline PORTED  a WAIT, in `pass.pipeline`
   >29	#   :48  InstanceRequestAdapter      PORTED  a WAIT, in `dev.request_adapter`
    30	#   :49  AdapterRequestDevice        PORTED  a WAIT, in `dev.request_device`
    31	#   :50  QueueOnSubmittedWorkDone    DEAD   the only caller was `dev.synchronize`,
- :30 [only_older_revision] tinygrad/runtime/ops_webgpu.py:49 rev=bacabf0866 toks=dev,request_device
    28	#   :47  DeviceCreateComputePipeline PORTED  a WAIT, in `pass.pipeline`
    29	#   :48  InstanceRequestAdapter      PORTED  a WAIT, in `dev.request_adapter`
   >30	#   :49  AdapterRequestDevice        PORTED  a WAIT, in `dev.request_device`
    31	#   :50  QueueOnSubmittedWorkDone    DEAD   the only caller was `dev.synchronize`,
    32	#                                             which nothing called. The status
- :84 [only_older_revision] tinygrad/runtime/ops_webgpu.py:141 rev=4c5ec46025 toks=timestamps
    82	# 2. THE 64-BIT WALL, and it is two lines of Python.
    83	#      :37  `wgpuInstanceWaitAny(instance, 1, WGPUFutureWaitInfo(future), 2**64-1)`
   >84	#      :141 `((timestamps:=…)[1] - timestamps[0]) / 1e9`
    85	#    The query set answers two TIMESTAMPS in NANOSECONDS as u64 and
    86	#    `buf_to_mv(...).cast("Q")` reads them as such. Bend has no 64-bit integer
- :94 [only_older_revision] tinygrad/runtime/ops_webgpu.py:204 rev=4c5ec46025 toks=val,to_bytes,little,signed
    92	#    TODO(p3) runtime/ops_webgpu.py:142  symbol=__call__ -- the u64 timestamp delta and its /1e9.
    93	#
   >94	# 3. FLOAT UNIFORMS (:204). `val.to_bytes(4,'little',signed=val<0)` for an int,
    95	#    `struct.pack('<f', val)` for a float, and :97 passes `float('inf')`.
    96	#    `base.bend`'s F32 has no infinity literal, no bitcast and no to_bits, so the
- :103 [at_no_revision] tinygrad/runtime/ops_webgpu.py:87 rev= toks=WGPUBindGroupLayoutEntry
    101	#
    102	# CTYPES SHAPING is not a wall and is named once: the
   >103	# `(WGPUBindGroupLayoutEntry * n)(...)` array constructions at :77, :87, :97, :99,
    104	# :129 and :215 are how Python spells "an array of n descriptors", and
    105	# `ctypes.pointer`/`cast` at :59 and :116 spell the chained struct. The port has
- :103 [at_no_revision] tinygrad/runtime/ops_webgpu.py:97 rev= toks=WGPUBindGroupLayoutEntry
    101	#
    102	# CTYPES SHAPING is not a wall and is named once: the
   >103	# `(WGPUBindGroupLayoutEntry * n)(...)` array constructions at :77, :87, :97, :99,
    104	# :129 and :215 are how Python spells "an array of n descriptors", and
    105	# `ctypes.pointer`/`cast` at :59 and :116 spell the chained struct. The port has
- :103 [at_no_revision] tinygrad/runtime/ops_webgpu.py:99 rev= toks=WGPUBindGroupLayoutEntry
    101	#
    102	# CTYPES SHAPING is not a wall and is named once: the
   >103	# `(WGPUBindGroupLayoutEntry * n)(...)` array constructions at :77, :87, :97, :99,
    104	# :129 and :215 are how Python spells "an array of n descriptors", and
    105	# `ctypes.pointer`/`cast` at :59 and :116 spell the chained struct. The port has
- :125 [only_older_revision] tinygrad/runtime/ops_webgpu.py:41 rev=e039d38f7a toks=None
    123	#     wrapped calls pass has_emsg=True (:45,47,48,49) and two pass False (:46,50)
    124	#     -- `sync_has_emsg` is that table and `sync_payload` is the arithmetic.
   >125	#   - The :41 collapse therefore NEVER takes its `None` branch for these six
    126	#     calls, because their payload is never empty. `sync_ret` ports the collapse
    127	#     anyway, because the branch structure is the thing.
- :140 [only_older_revision] device.py:391 rev=bdddaad219 toks=Compiled,__init__
    138	#
    139	# device.bend owes:
   >140	#   1. `Compiled.__init__` (device.py:391) is handed
    141	#      `arch="shader-f16" * (… in features)` at :190. `dev.init` produces that
    142	#      arch string and the feature list; whoever wires the device records it.
- :143 [only_older_revision] device.py:372 rev=bec565d157 toks=Program,__call__
    141	#      `arch="shader-f16" * (… in features)` at :190. `dev.init` produces that
    142	#      arch string and the feature list; whoever wires the device records it.
   >143	#   2. `Program.__call__` (device.py:372) is called from engine/realize.py:168
    144	#      with `bufs` = `ast.arg.globals` resolved and `vals` = `ProgramInfo.vals`.
    145	#      THIS FILE NEEDS THE BUFFER LIST AND THE VAL COUNT AND NOTHING ELSE --
- :143 [dangling] engine/realize.py:168 rev= toks=Program,__call__
    141	#      `arch="shader-f16" * (… in features)` at :190. `dev.init` produces that
    142	#      arch string and the feature list; whoever wires the device records it.
   >143	#   2. `Program.__call__` (device.py:372) is called from engine/realize.py:168
    144	#      with `bufs` = `ast.arg.globals` resolved and `vals` = `ProgramInfo.vals`.
    145	#      THIS FILE NEEDS THE BUFFER LIST AND THE VAL COUNT AND NOTHING ELSE --
- :147 [only_older_revision] device.py:110 rev=bec565d157 toks=BufferStorage,_alloc,buf
    145	#      THIS FILE NEEDS THE BUFFER LIST AND THE VAL COUNT AND NOTHING ELSE --
    146	#      they are what `bgl.of` turns into entries. See THE LAYOUT DERIVATION.
   >147	#   3. `BufferStorage` (device.py:110) is `_alloc`'s return (:152) and its `.buf`
    148	#      is what `_free` (:163) and `_copyout` (:160) hand back. `Buf` is that
    149	#      pair, and `alloc.of` is the `BufferStorage`.
- :147 [only_older_revision] tinygrad/runtime/ops_webgpu.py:152 rev=4c5ec46025 toks=BufferStorage,_alloc,buf
    145	#      THIS FILE NEEDS THE BUFFER LIST AND THE VAL COUNT AND NOTHING ELSE --
    146	#      they are what `bgl.of` turns into entries. See THE LAYOUT DERIVATION.
   >147	#   3. `BufferStorage` (device.py:110) is `_alloc`'s return (:152) and its `.buf`
    148	#      is what `_free` (:163) and `_copyout` (:160) hand back. `Buf` is that
    149	#      pair, and `alloc.of` is the `BufferStorage`.
- :148 [only_older_revision] tinygrad/runtime/ops_webgpu.py:163 rev=4c5ec46025 toks=_free,_copyout,Buf
    146	#      they are what `bgl.of` turns into entries. See THE LAYOUT DERIVATION.
    147	#   3. `BufferStorage` (device.py:110) is `_alloc`'s return (:152) and its `.buf`
   >148	#      is what `_free` (:163) and `_copyout` (:160) hand back. `Buf` is that
    149	#      pair, and `alloc.of` is the `BufferStorage`.
    150	#   4. `TinyELF` (device.py:355) carries `name`, which is the entry point (:54)
- :150 [only_older_revision] device.py:355 rev=c52b227c7b toks=name
    148	#      is what `_free` (:163) and `_copyout` (:160) hand back. `Buf` is that
    149	#      pair, and `alloc.of` is the `BufferStorage`.
   >150	#   4. `TinyELF` (device.py:355) carries `name`, which is the entry point (:54)
    151	#      and the pipeline's `entryPoint` (:106). `prog.init` takes it as a String.
    152	#
- :159 [at_no_revision] tinygrad/runtime/ops_webgpu.py:78 rev= toks=WGPUBufferBindingType_Storage
    157	#      must agree or every kernel faults at bind time. MEASURED by calling
    158	#      `WGSLRenderer.render_kernel` in CPython -- see THE LAYOUT DERIVATION.
   >159	#   2. `WGPUBufferBindingType_Storage` for a GLOBAL buffer, because :78 keys the
    160	#      type off the POSITION (`i < len(bufs)`) while wgsl.py:116 keys it off the
    161	#      ADDRSPACE. They agree only because every `ProgramInfo.globals` entry is
- :160 [at_no_revision] wgsl.py:116 rev= toks=len,bufs
    158	#      `WGSLRenderer.render_kernel` in CPython -- see THE LAYOUT DERIVATION.
    159	#   2. `WGPUBufferBindingType_Storage` for a GLOBAL buffer, because :78 keys the
   >160	#      type off the POSITION (`i < len(bufs)`) while wgsl.py:116 keys it off the
    161	#      ADDRSPACE. They agree only because every `ProgramInfo.globals` entry is
    162	#      GLOBAL (ops.py:1378). If wgsl.bend ever emits a non-GLOBAL global, the two
- :197 [at_no_revision] ops.py:1378 rev= toks=ProgramInfo,globals
    195	# so the shader declares 1+len(bufs) bindings, in the order `bufs` was handed to
    196	# it (cstyle.py:264 "this relies on bufs dict preserving order"), and
   >197	# `ProgramInfo.globals` (ops.py:1378, sorted+deduped by slot) is that same order.
    198	# `pass.uniforms` binds layout entry k+1 to bufs[k]. THAT IS THE WHOLE INTERFACE
    199	# between this file and wgsl.bend, and a divergence there is silent in both.

## tinybendygrad/runtime/support/am/amdev.bend  (6 rows)
- :25 [only_older_revision] tinygrad/runtime/support/am/amdev.py:400 rev=471a3aeb69 toks=hwid_names,hw_id_map
    23	#   * the DISCOVERY WALK (:356-397) -- the die/IP nesting, the `ip_offset` stride
    24	#     (8 + 8-or-4 per base address), the `hw_id_map` gate, and the HARVEST table parse.
   >25	#   * `hwid_names` (:400) and `hw_id_map` (:380) -- TWO-WAY TABLES, both directions.
    26	#   * the REGISTER ARITHMETIC that is 64-BIT and therefore where a `U32` would be a
    27	#     silently wrong register write: `indirect_wreg_pcie`'s `1 << 34` (:341) and
- :25 [only_older_revision] tinygrad/runtime/support/am/amdev.py:380 rev=471a3aeb69 toks=hwid_names,hw_id_map
    23	#   * the DISCOVERY WALK (:356-397) -- the die/IP nesting, the `ip_offset` stride
    24	#     (8 + 8-or-4 per base address), the `hw_id_map` gate, and the HARVEST table parse.
   >25	#   * `hwid_names` (:400) and `hw_id_map` (:380) -- TWO-WAY TABLES, both directions.
    26	#   * the REGISTER ARITHMETIC that is 64-BIT and therefore where a `U32` would be a
    27	#     silently wrong register write: `indirect_wreg_pcie`'s `1 << 34` (:341) and
- :27 [at_no_revision] tinygrad/runtime/support/am/amdev.py:341 rev= toks=indirect_wreg_pcie
    25	#   * `hwid_names` (:400) and `hw_id_map` (:380) -- TWO-WAY TABLES, both directions.
    26	#   * the REGISTER ARITHMETIC that is 64-BIT and therefore where a `U32` would be a
   >27	#     silently wrong register write: `indirect_wreg_pcie`'s `1 << 34` (:341) and
    28	#     `rlcg_rw`'s `(addr | 1<<28) << 32 | val` (:320), plus `ucode_start`'s `<< 32` (:82).
    29	#   * the REQUEST TRACES -- the VF mailbox protocol (:268-281), `_read_vram` (:347-354),
- :29 [only_older_revision] tinygrad/runtime/support/am/amdev.py:268-281 rev=c117da9850 toks=_read_vram
    27	#     silently wrong register write: `indirect_wreg_pcie`'s `1 << 34` (:341) and
    28	#     `rlcg_rw`'s `(addr | 1<<28) << 32 | val` (:320), plus `ucode_start`'s `<< 32` (:82).
   >29	#   * the REQUEST TRACES -- the VF mailbox protocol (:268-281), `_read_vram` (:347-354),
    30	#     the ASPM capability walk (:147-154), `indirect_wreg`/`_pcie`, and the boot order.
    31	#   * the AID ALIVE-MASK (:417-421), the palloc ladder (:233), the reserved-vram ladder
- :30 [at_no_revision] tinygrad/runtime/support/am/amdev.py:147-154 rev= toks=indirect_wreg,_pcie
    28	#     `rlcg_rw`'s `(addr | 1<<28) << 32 | val` (:320), plus `ucode_start`'s `<< 32` (:82).
    29	#   * the REQUEST TRACES -- the VF mailbox protocol (:268-281), `_read_vram` (:347-354),
   >30	#     the ASPM capability walk (:147-154), `indirect_wreg`/`_pcie`, and the boot order.
    31	#   * the AID ALIVE-MASK (:417-421), the palloc ladder (:233), the reserved-vram ladder
    32	#     (:397) and the module ladder (:405-407).
- :72 [only_older_revision] tinygrad/runtime/support/am/amdev.py:364 rev=4340197132 toks=table_list,offset
    70	#     common header's -- a fixture that set only the common one yields a
    71	#     ZERO-LENGTH descriptor, silently.
   >72	#   * :364's window is `(10 << 10)` bytes, so a `table_list[].offset` past it
    73	#     reads back as version 0_0 rather than as an error.
    74	import ../../../helpers.bend as H

## tinybendygrad/runtime/support/am/ip.bend  (1 rows)
- :19 [only_older_revision] tinygrad/runtime/support/am/ip.py:354 rev=bbf7b35db4 toks=KIQ,xcc,x20
    17	#   * the PTE FLAG TABLES (:178-195), four generations, `|` of five constants
    18	#     and a version-selected MTYPE field.
   >19	#   * the DOORBELL ARITHMETIC: `KIQ + xcc*0x20` (:354), `sDMA_ENGINE0 +
    20	#     (pipe+queue*4)*0xA` (:592), `(ring_size//4).bit_length()-2` (:367), the
    21	#     `(regf pair)-1) * 0xA) * 2` s2a entry ladder (:570-571).

## tinybendygrad/runtime/support/autogen.bend  (2 rows)
- :121 [at_no_revision] tinygrad/runtime/support/autogen.py:107 rev= toks=types,tnm,defd
    119	#                                           emit_macro/_fn, emit_cfunctype,
    120	#                                           emit_pointer, emit_array
   >121	#   :107  the `types` dict      PORTED   `Gt{nm, tnm, defd, ln}` and its readers
    122	#   :273  the main prologue     PORTED   prolog_head, prolog_objc, emit_dll_line
    123	#   :112  tname, its DISPATCH   WALL 4   the ten-arm `match t.kind` and its
- :126 [only_older_revision] tinygrad/runtime/support/autogen.py:30 rev=950d8de00e toks=fields
    124	#                                           record arm -- see WALL 4 above
    125	#   :5-80 the libclang FFI      WALL 1   46 functions MEASURED, 0 bound
   >126	#   :30   all_fields            WALL 4   it is a loop over `fields(t)` calling
    127	#                                           into tname, so it inherits WALL 4
    128	#   :73   readext               WALL 1   file IO at a source offset

## tinybendygrad/runtime/support/compiler_cpu.bend  (5 rows)
- :58 [at_no_revision] tinygrad/runtime/support/compiler_cpu.py:8 rev= toks=ClangCompiler,arch_of,cpu_of
    56	#
    57	#   :7   the assert                PORTED `ClangCompiler.ge2` `ClangCompiler.msg`
   >58	#   :8   the unpack                PORTED `ClangCompiler.arch_of` `.cpu_of`
    59	#                                          `.feats`
    60	#   :10  the x86_64 arm            PORTED `ClangCompiler.x86_feat` `ClangCompiler.args`
- :62 [at_no_revision] tinygrad/runtime/support/compiler_cpu.py:14 rev= toks=ClangCompiler,riscv64_cpu
    60	#   :10  the x86_64 arm            PORTED `ClangCompiler.x86_feat` `ClangCompiler.args`
    61	#   :13  the arm64 arm             PORTED `ClangCompiler.arm64_feat` `ClangCompiler.args`
   >62	#   :14  the riscv64 arm           PORTED `ClangCompiler.riscv64_cpu`
    63	#                                          `ClangCompiler.args`
    64	#   :15  the refusal               PORTED `ClangCompiler.supported` `ClangCompiler.unsupported`
- :67 [at_no_revision] tinygrad/runtime/support/compiler_cpu.py:24 rev= toks=ClangCompiler,dis_row
    65	#   :16  the cache key             PORTED `ClangCompiler.key`
    66	#   :21-22 the spawn               PORTED `ClangCompiler.compile_argv` `.argv_n`
   >67	#   :24  disassemble               PORTED `ClangCompiler.dis_row`
    68	#   :28  X86Compiler.__init__      PORTED `X86Compiler.key`
    69	#   :29  X86Compiler.compile       PORTED `X86Compiler.nibble` `X86Compiler.hex_ok`
- :91 [at_no_revision] helpers.py:161 rev= toks=getenv,clang
    89	#   TODO(p3) compiler_cpu.py:30 -- `capstone_flatdump(lib, "x86_64")`.
    90	#
   >91	# WALL 3 -- `getenv("CC", 'clang')` is a PROCESS-BOOT CONSTANT: helpers.py:161
    92	#   carries `@functools.cache`, so `CC` is read ONCE per interpreter and
    93	#   setting it later is invisible. `ClangCompiler.prog` therefore takes the
- :103 [only_older_revision] device.py:337 rev=c52b227c7b toks=cachekey,CCACHE,None
    101	#
    102	# WALL 4 -- `CCACHE`. `Compiler.__init__` is
   >103	#   `self.cachekey = cachekey if CCACHE else None` (device.py:337), so the key
    104	#   the port builds is the one that EXISTS only when CCACHE is on -- and CCACHE
    105	#   is a `ContextVar`, which is the same cached `getenv`. So `cpu.x86key` is

## tinybendygrad/runtime/support/compiler_cuda.bend  (2 rows)
- :68 [at_no_revision] helpers.py:161 rev= toks=functools,cache
    66	# ===========================================================================
    67	# `CUDA_PATH = getenv("CUDA_PATH", "")` IS A PROCESS-BOOT CONSTANT, and it is
   >68	# read at IMPORT: `helpers.py:161` carries `@functools.cache`, so the module
    69	# constant is fixed before any caller can change the environment. Measured, in
    70	# one process: `os.environ["CUDA_PATH"] = "/mutated"` AFTER the import leaves
- :93 [at_no_revision] tinygrad/runtime/support/compiler_cuda.py:63 rev= toks=NVRTCCompiler,dis_row
    91	#   :55-62 NVRTCCompiler.compile PORTED `NVRTCCompiler.calls` `.calls_n` `.first`
    92	#                                        `.last` `NVRTCCompiler.getter`
   >93	#   :63    disassemble          PORTED `NVRTCCompiler.dis_row`
    94	#   :65-76 NVCCCompiler         PORTED `NVCCCompiler.mode` `.suffix` `.cmd`
    95	#                                       `.join` `.keystr` `.key`

## tinybendygrad/runtime/support/compiler_llvm.bend  (3 rows)
- :26 [at_no_revision] helpers.py:161 rev= toks=functools,cache,LLVMOPT
    24	# ===========================================================================
    25	# THE SECOND HEADLINE: `getenv("LLVMOPT", 1)` IS A PROCESS-BOOT CONSTANT.
   >26	# helpers.py:161 carries `@functools.cache`, so `LLVMOPT` is read ONCE per
    27	# interpreter. `LLVMCompiler.__init__` therefore answers `default<O2>` and sets
    28	# FOUR PassBuilderOptions, or `default<O0>` and sets NONE, and there is no way to
- :56 [at_no_revision] tinygrad/runtime/support/compiler_llvm.py:18 rev= toks=LLVMCompiler,triple_ok
    54	#   :14-15 the five inits      PORTED `LLVMCompiler.prefix` `.components`
    55	#   :17  the triple map        PORTED `LLVMCompiler.triple` `.triple_ok`
   >56	#   :18  expect(#1)            PORTED `LLVMCompiler.triple_ok`
    57	#   :20-21 the target machine  PORTED `LLVMCompiler.tm_processor` `.tm_feats`
    58	#   :23-31 the pass options    PORTED `LLVMCompiler.passes` `.pbosets`
- :70 [at_no_revision] tinygrad/runtime/support/compiler_llvm.py:76 rev= toks=CPULLVMCompiler,dis_row
    68	#   :83-87 the RuntimeError    PORTED `AMDLLVMCompiler.remap` `.remap_msg`
    69	#                                       `.remap_kind`
   >70	#   :76,88 disassemble         PORTED `CPULLVMCompiler.dis_row`
    71	#                                       `AMDLLVMCompiler.dis_row`
    72	#

## tinybendygrad/runtime/support/compiler_mesa.bend  (5 rows)
- :49 [at_no_revision] tinygrad/runtime/support/compiler_mesa.py:98 rev= toks=ir3,arch_ok
    47	#                                         %08x] ` line format, the decode-option
    48	#                                         field ORDER and its four values
   >49	#   :98    the a630 assert         PORTED  `ir3.arch_ok`
    50	#   :99    the dev id              PORTED  `ir3.gpu_id` `ir3.chip_id`
    51	#   :101   disable_cache=True      PORTED  `ir3.disable_cache`
- :50 [only_older_revision] tinygrad/runtime/support/compiler_mesa.py:99 rev=fc4faed0b2 toks=ir3,gpu_id,chip_id
    48	#                                         field ORDER and its four values
    49	#   :98    the a630 assert         PORTED  `ir3.arch_ok`
   >50	#   :99    the dev id              PORTED  `ir3.gpu_id` `ir3.chip_id`
    51	#   :101   disable_cache=True      PORTED  `ir3.disable_cache`
    52	#   :104   the IR3 cache key       PORTED  `ir3.key`
- :54 [at_no_revision] tinygrad/runtime/support/compiler_mesa.py:118 rev= toks=ir3,variant_fields
    52	#   :104   the IR3 cache key       PORTED  `ir3.key`
    53	#   :119   the uav count           PORTED  `ir3.num_uavs` -- `num_ssbos + num_images`
   >54	#   :118   the three-field store   PORTED  `ir3.variant_fields`
    55	#   :123   the four-way concat     PORTED  `ir3.ret_parts` -- four LENGTHS, and
    56	#                                         the fourth is `info.size`
- :55 [at_no_revision] tinygrad/runtime/support/compiler_mesa.py:123 rev= toks=ir3,ret_parts
    53	#   :119   the uav count           PORTED  `ir3.num_uavs` -- `num_ssbos + num_images`
    54	#   :118   the three-field store   PORTED  `ir3.variant_fields`
   >55	#   :123   the four-way concat     PORTED  `ir3.ret_parts` -- four LENGTHS, and
    56	#                                         the fourth is `info.size`
    57	#   :127-131 unpack_lib            PORTED  `ul.*` -- THE HEADLINE. Two successive
- :60 [at_no_revision] tinygrad/runtime/support/compiler_mesa.py:133 rev= toks=ir3,dis_row
    58	#                                         `sizeof` offsets and then a split at
    59	#                                         `count * 4`
   >60	#   :133   the disassemble call    PORTED  `ir3.dis_row`
    61	#
    62	# ===========================================================================

## tinybendygrad/runtime/support/compiler_qcom.bend  (1 rows)
- :65 [at_no_revision] device.py:352 rev= toks=compile_server
    63	# WALL 2 -- the two persistent-pipe paths. `self.server(...)` is
    64	#   `subprocess.Popen(argv.split() + [...], stdout=PIPE, stdin=PIPE, bufsize=0)`
   >65	#   (device.py:352) and `compile_server` writes a length-prefixed frame and
    66	#   reads one back on the SAME long-lived pipe. `Process.run` spawns and
    67	#   collects; it cannot hold a duplex pipe open. **This is the one seam in the

## tinybendygrad/runtime/support/compileserver.bend  (1 rows)
- :35 [at_no_revision] device.py:355 rev= toks=CompileError
    33	#      stderr. So the reader cannot distinguish "the compiler failed" from "the
    34	#      compiler returned an empty library" by the protocol -- which is exactly
   >35	#      what `device.py:355` relies on when it raises `CompileError` on an empty
    36	#      read. MEASURED end to end: a frame set of four requests where two fail
    37	#      still answers four frames, and the server's exit code is 0.

## tinybendygrad/runtime/support/elf.bend  (1 rows)
- :137 [at_no_revision] tinygrad/runtime/support/elf.py:50 rev= toks=type,ElfImage
    135	#   :42-48 the reloc loop          PORTED  `type Rctx`, `Rc.walk`, `Rc.mk`,
    136	#                                         `Trg.off`, `Rc.defined`, `Rc.undefined`
   >137	#   :50  the return                PORTED  `type ElfImage` + its four readers
    138	#   :52  jit_loader                PORTED  `jit_loader`, `Jit.go`, `Jit.step`
    139	#   :56  relocate                  PORTED  `Jit.relocate`..`Jit.relocate8`, the ten

## tinybendygrad/runtime/support/hcq2.bend  (2 rows)
- :51 [only_older_revision] tinygrad/runtime/support/hcq2.py:130 rev=b5be082207 toks=cfield,d2420e64,cstruct
    49	#   GONE upstream at this pin, each named with the construct that SURVIVED it:
    50	#   `select_lane` (folded into `unwrap_lane`, :45), `CDTYPE` (`dtypes.uints` at
   >51	#   :130), `cfield` (`7d2420e64`; `cstruct` at :129 reads the fields),
    52	#   `STAGING_SIZE`/`STAGING_SLOTS` (`6816873ad`), `epilogue_queue` (`dc9af790e`,
    53	#   the queues are built by `_build_queues` at :244), and `sched_tl`/`staging_chunk`,
- :108 [only_older_revision] tinygrad/runtime/support/hcq2.py:458 rev=48ed17396a toks=HCQInfo,CallInfo,aux
    106	
    107	#    WALL(p3) tinygrad/runtime/support/hcq2.py:452   `pm_lift` symbol=pm_lift -- BLOCKED: needs the shaped `UOp.param` and `UOp.substitute` (`uop/ops.bend:514` open TODO).
   >108	#    WALL(p3) tinygrad/runtime/support/hcq2.py:458   `pm_encode` -- BLOCKED: needs `HCQInfo`; `CallInfo` has no `aux` (`uop/ops.bend:1116`).
    109	#    TODO(p3) runtime/support/hcq2.py:552  symbol=hcq_link -- `Compiled.pm_link` -- the link matcher upstream declares at module level (upstream line 478) and rewrites with in `hcq_link`.
    110	#

## tinybendygrad/runtime/support/memory.bend  (3 rows)
- :8 [at_no_revision] tinygrad/runtime/support/memory.py:12 rev= toks=BumpAllocator
    6	#   * the OFFSET AND LAYOUT ARITHMETIC -- `round_up(size, 0x1000)` in `palloc`
    7	#     and `valloc` (:284, :249, :253), the `MMIOInterface.view` window
   >8	#     arithmetic (:12), the `BumpAllocator` bump-and-align sequence (:16-21),
    9	#     and the TLSF bucket arithmetic (:43, :46, :91). A wrong offset is a
    10	#     silently wrong memory access and no row about counts can see it.
- :15 [only_older_revision] tinygrad/runtime/support/memory.py:127 rev=4fd4eafb23 toks=pte_idx,pte_size,next
    13	#     arguments, so a field swap is a silent remapping. `blocks`' 4-tuple is
    14	#     `(size, next, prev, is_free)` (:39) and `pt_stack`'s is
   >15	#     `(pt, pte_idx, pte_size)` (:127) while `next()` YIELDS the five-tuple
    16	#     `(off, pt, pte_idx, entries, pte_covers)` (:175) -- three different
    17	#     orders in 136 lines.
- :18 [at_no_revision] tinygrad/runtime/support/memory.py:187 rev= toks=MemoryManager,__init__
    16	#     `(off, pt, pte_idx, entries, pte_covers)` (:175) -- three different
    17	#     orders in 136 lines.
   >18	#   * the TWO REVERSALS in `MemoryManager.__init__` (:187):
    19	#     `pte_covers = [1 << x for x in va_shifts][::-1]` and
    20	#     `pte_cnt = [1 << (lvl_msb[i+1] - lvl_msb[i]) for ...][::-1]`. Both are

## tinybendygrad/runtime/support/nv/ip.bend  (3 rows)
- :70 [at_no_revision] tinygrad/runtime/support/nv/ip.py:48 rev= toks=entryOff
    68	#   2. The ring's usable length is `msgSize*msgCount`, and the wrap threshold is
    69	#      `wp*msgSize + msgSize*msgCount` -- i.e. `ring_len`, NOT `size`. :30 slices
   >70	#      the ring at `entryOff` but :48 measures the wrap against
    71	#      `len(self.queue_mv)`, which is `msgSize*msgCount`. `Q.ring_len` is the
    72	#      second number and `Q.rx_hdr_off` is the first; a port that confuses them
- :153 [at_no_revision] tinygrad/runtime/support/nv/ip.py:123 rev= toks=desc_v3
    151	#     WALKS are over bytes this file does not have. The one thing ported is the
    152	#     arithmetic that survives without the bytes -- `frts_offset` (:145),
   >153	#     `desc_v3` size arithmetic (:141-143) -- and the refusal at :123.
    154	#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  the PCI expansion ROM walk
    155	#       # TODO(p3) support/nv/ip.py:123  assert bit_header.Signature == 0x00544942
- :217 [at_no_revision] tinygrad/runtime/support/nv/ip.py:419 rev= toks=List,memoryview,cast
    215	# * hdr.entryCount)(...)` at :156 spells "an array of n descriptors", so the
    216	# layout of `FALCON_APPLICATION_INTERFACE_ENTRY_V1` is one row of the table and
   >217	# the array is a `List`. `memoryview(...).cast('I'/'Q')` (:111,:419,:306) is the
    218	# same statement about width.
    219	#

## tinybendygrad/runtime/support/nv/nvdev.bend  (5 rows)
- :25 [only_older_revision] tinygrad/runtime/support/nv/nvdev.py:12-31 rev=041dc0cf85 toks=NVPageTableEntry
    23	# nv_regs`, `tinygrad.helpers`, `tinygrad.runtime.autogen.pci` and the support
    24	# modules. It has NO ctypes and NO ioctl. What it is: the MMIO REGISTER file
   >25	# (`NVReg`, :12-31), the PAGE TABLE entry codec (`NVPageTableEntry`, :33-67), the
    26	# device's early MMIO/MMU bring-up (`NVDev._early_ip_init` :97-121 and
    27	# `_early_mmu_init` :123-147), a boot-memory allocator (`_alloc_boot_mem`
- :28 [only_older_revision] tinygrad/runtime/support/nv/nvdev.py:161-163 rev=98807603d1 toks=include
    26	# device's early MMIO/MMU bring-up (`NVDev._early_ip_init` :97-121 and
    27	# `_early_mmu_init` :123-147), a boot-memory allocator (`_alloc_boot_mem`
   >28	# :149-159) and the generated-register loader (`include`, :161-163).
    29	#
    30	# The ioctl layer is `ops_nv.py`'s `NVKIface` (:337-399), a different `.py` in a
- :70 [at_no_revision] tinygrad/runtime/support/nv/nvdev.py:489 rev= toks=sys,call_names
    68	#      an `open`, or an `ioctl`.
    69	#   2. `system.bend` HAS an `ioctl`: `system.bend:471 def CALL_IOCTL() -> U32: 21`,
   >70	#      `:489` lists "ioctl" among `sys.call_names()`, `:517` dispatches it. But
    71	#      `rg 'def sys.ioctl' tinybendygrad/runtime/support/system.bend` returns ZERO
    72	#      hits and there is no `system.c` under `tinybendygrad/`. It is a NAME IN A
- :70 [at_no_revision] tinygrad/runtime/support/nv/nvdev.py:517 rev= toks=sys,call_names
    68	#      an `open`, or an `ioctl`.
    69	#   2. `system.bend` HAS an `ioctl`: `system.bend:471 def CALL_IOCTL() -> U32: 21`,
   >70	#      `:489` lists "ioctl" among `sys.call_names()`, `:517` dispatches it. But
    71	#      `rg 'def sys.ioctl' tinybendygrad/runtime/support/system.bend` returns ZERO
    72	#      hits and there is no `system.c` under `tinybendygrad/`. It is a NAME IN A
- :157 [only_older_revision] tinygrad/runtime/support/nv/nvdev.py:52 rev=b6981404ed toks=entry
    155	#
    156	# W2. THE 128-BIT PAGE-TABLE ENTRY. `NV_MMU_VER2_DUAL_PDE.address_small_sys` is
   >157	#     bits (72,117) -- 46 bits, at offset 72 -- and `entry()` (:52) recombines two
    158	#     64-bit halves as `(entries[2e+1] << 64) | entries[2e]`. Bend has no 64-bit
    159	#     integer, so `nv.pte_idx` ports the INDEX (`2e+1` for a dual level, `e`

## tinybendygrad/runtime/support/objc.bend  (4 rows)
- :50 [at_no_revision] cstyle.py:268 rev= toks=emits
    48	# The failure is NOT a failed dlsym. `hcq2.py:84` names a DEVICE symbol after
    49	# `fn.__name__`, so `ccall(SELNAME, sel)` becomes `custom_function
   >50	# ("sel_registerName")`, `cstyle.py:268` emits `extern void sel_registerName();`
    51	# into the generated host kernel, and `elf.py:13` then fails to link it
    52	# against `[libm, libSystem]` -- neither of which exports it either. Measured
- :55 [only_older_revision] ops_cpu.py:19 rev=fec703cbec toks=CPUProgram,link_libs
    53	# end to end: `(a@a.T).realize()` raises `RuntimeError: Attempting to relocate
    54	# against an undefined symbol sel_registerName`. The fix belongs in
   >55	# `ops_cpu.py:19/21` (libobjc is missing from `CPUProgram.link_libs`), NOT in
    56	# `objc.py` and NOT in `ops_metal.py:86`. Reported, not fixed.
    57	#
- :56 [at_no_revision] ops_metal.py:86 rev= toks=objc
    54	# against an undefined symbol sel_registerName`. The fix belongs in
    55	# `ops_cpu.py:19/21` (libobjc is missing from `CPUProgram.link_libs`), NOT in
   >56	# `objc.py` and NOT in `ops_metal.py:86`. Reported, not fixed.
    57	#
    58	# ===========================================================================
- :100 [at_no_revision] tinygrad/runtime/support/objc.py:37 rev= toks=msg
    98	#     `returns_retained_name=f` is the sharp version of that: the wrapped
    99	#     function is named `f`, NOT the selector, because `returns_retained(f)`
   >100	#     wraps the INNER `f` from :37 and not `msg`'s return.
    101	#
    102	# ===========================================================================

## tinybendygrad/runtime/support/rdma/bnxtdev.bend  (11 rows)
- :12 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:42-45 rev= toks=db_value
    10	# silently wrong DMA:
    11	#
   >12	#   1. THE DOORBELL AND THE RING (:13-15, :42-45, :162-164). `db_value` is a
    13	#      64-bit word whose HIGH half says WHICH QUEUE and whose LOW half says
    14	#      WHERE in it. There is no U64 in Bend 2.0.34, so the word is two U32
- :59 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:33 rev= toks=pbl,level_of
    57	#   :27  `build_pbl`               PORTED  `pbl.level_of` / `pbl.entry` /
    58	#                                              `pbl.decode`, encode AND decode
   >59	#   :33  the one-paddr shortcut    PORTED  `pbl.level_of(1) == 0`
    60	#   :34  `assert len <= 512`       PORTED  the REFUSAL, a truncated trace
    61	#   :42  `BNXTQueue.read`          PORTED  `q.read_off`, `q.read_len`
- :88 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:83 rev= toks=hwrm,bar0_at
    86	#   :79  `cmpl_ring`/`target_id`   PORTED  `hwrm.header`
    87	#   :81  the 0x1000-byte clear     PORTED  a WRITE, in the trace
   >88	#   :83  the word loop into bar0  PORTED  `hwrm.bar0_at`
    89	#   :84  the trigger dword         PORTED  `hwrm.trig_at`
    90	#   :86  `resp_len` / `seq_id`     PORTED  `hwrm.gate_ok`
- :89 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:84 rev= toks=hwrm,trig_at
    87	#   :81  the 0x1000-byte clear     PORTED  a WRITE, in the trace
    88	#   :83  the word loop into bar0  PORTED  `hwrm.bar0_at`
   >89	#   :84  the trigger dword         PORTED  `hwrm.trig_at`
    90	#   :86  `resp_len` / `seq_id`     PORTED  `hwrm.gate_ok`
    91	#   :88  `assert error_code == 0`  PORTED  the REFUSAL
- :101 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:138 rev= toks=rcfw,first_flag
    99	#   :133 `ceildiv(sizeof(req_t),16)` PORTED `rcfw.slots_of`
    100	#   :136-137 the producer index    PORTED  `rcfw.write_idx` / `rcfw.prod`
   >101	#   :138 the FIRMWARE_FIRST flag   PORTED  `rcfw.first_flag`
    102	#   :142-143 the prod/trig dwords  PORTED  `rcfw.prod_at` / `rcfw.trig_at`
    103	#   :146 the CREQ valid test       PORTED  `creq.ready`
- :104 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:153 rev= toks=rcfw,nq_arm
    102	#   :142-143 the prod/trig dwords  PORTED  `rcfw.prod_at` / `rcfw.trig_at`
    103	#   :146 the CREQ valid test       PORTED  `creq.ready`
   >104	#   :153 the NQ_ARM consumer db    PORTED  `rcfw.nq_arm`
    105	#   :154 the QP_EVENT filter       PORTED  `rcfw.is_final`, and its threshold
    106	#   :155 `assert ret.status == 0`  PORTED  the REFUSAL
- :105 [only_older_revision] tinygrad/runtime/support/rdma/bnxtdev.py:154 rev=cd36643576 toks=rcfw,is_final
    103	#   :146 the CREQ valid test       PORTED  `creq.ready`
    104	#   :153 the NQ_ARM consumer db    PORTED  `rcfw.nq_arm`
   >105	#   :154 the QP_EVENT filter       PORTED  `rcfw.is_final`, and its threshold
    106	#   :155 `assert ret.status == 0`  PORTED  the REFUSAL
    107	#   :160 `fini`                    PORTED  `dev.fini`
- :151 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:54 rev= toks=getattr,bnxt
    149	#   :160 `func_drv_unrgtr`                    CALL_FINI
    150	#   :164 `self.db[...] = db_value(...)`       CALL_DB
   >151	#   :54/72 the `getattr(bnxt, ...)` struct
    152	#         construction and `from_buffer_copy` WALL 1 -- see below
    153	#
- :180 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:42-45 rev= toks=MMIOInterface
    178	# | WALL(p3) bnxtdev.py:32  struct.pack(f"<{len(values)}Q", *values). -- BLOCKED. #   A FORMAT STRING BUILT FROM THE ARGUMENT COUNT -- `struct.pack(f"<{len(values)}Q", *values)` --
    179	#   and `*values` splats a variable-length tuple.
   >180	#   3. `MMIOInterface` (:42-45). A byte-addressed slice of host memory over a
    181	#      BAR. `read` and `write` COMPUTE the offsets, and that arithmetic is
    182	#      ported and gated; the slice itself is the seam.
- :188 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:157 rev= toks=getenv
    186	#      U32 words, but nothing constructs a ctypes object.
    187	#   5. `self.pci_dev.pcibus` (:54), `DEBUG`/`BNXT_DEBUG` and `print` (:61,:74,
   >188	#      :157,:217). The verbosity levels are WALLS (`getenv` is IO); the device
    189	#      node string is `nic.node` in `ops_rdma.bend`, which already ports it.
    190	# | WALL(p3) bnxtdev.py:54  self.devfmt = pci_dev.pcibus. -- BLOCKED. #   `self.devfmt = pci_dev.pcibus` READS A FIELD OFF A LIVE PCI DEVICE OBJECT. There is no live
- :188 [at_no_revision] tinygrad/runtime/support/rdma/bnxtdev.py:217 rev= toks=getenv
    186	#      U32 words, but nothing constructs a ctypes object.
    187	#   5. `self.pci_dev.pcibus` (:54), `DEBUG`/`BNXT_DEBUG` and `print` (:61,:74,
   >188	#      :157,:217). The verbosity levels are WALLS (`getenv` is IO); the device
    189	#      node string is `nic.node` in `ops_rdma.bend`, which already ports it.
    190	# | WALL(p3) bnxtdev.py:54  self.devfmt = pci_dev.pcibus. -- BLOCKED. #   `self.devfmt = pci_dev.pcibus` READS A FIELD OFF A LIVE PCI DEVICE OBJECT. There is no live

## tinybendygrad/runtime/support/system.bend  (8 rows)
- :29 [at_no_revision] tinygrad/runtime/support/system.py:61-65 rev= toks=cap
    27	#   :56-59 write_sysfs            PORTED  `sysfs.*` + `sysfs.wrote` -- the `sudo`
    28	#                                               STRING
   >29	#   :61-65 atomic_lib / libsys    PORTED  `cap.*` -- the PLATFORM gate, which is
    30	#                                               `cap.barrier_lib`'s `osx`
    31	#   :67-70 pagemap                PORTED  `sys.pagemap`
- :35 [at_no_revision] tinygrad/runtime/support/system.py:89 rev= toks=cap,barrier_lib
    33	#                                               None`
    34	#   :84-87 reserve_va             PORTED  `sys.reserve_va` -- the CACHE negative case
   >35	#   :89    memory_barrier         PORTED  `cap.barrier_lib` -- which library is
    36	#                                               consulted
    37	#   :91-92 lock_memory            PORTED  `sys.lock_memory` -- the refusal
- :38 [at_no_revision] tinygrad/runtime/support/system.py:94-96 rev= toks=paddr
    36	#                                               consulted
    37	#   :91-92 lock_memory            PORTED  `sys.lock_memory` -- the refusal
   >38	#   :94-96 system_paddrs          PARTIAL `paddr.*` -- the mask; the u64 read is FFI
    39	#   :98-102 alloc_sysmem          PORTED  `sys.alloc_sysmem` -- the flag arithmetic
    40	#   :104-126 pci_scan_bus         PORTED  `scan.*` -- the mask filter + both id formats
- :40 [at_no_revision] tinygrad/runtime/support/system.py:104-126 rev= toks=scan
    38	#   :94-96 system_paddrs          PARTIAL `paddr.*` -- the mask; the u64 read is FFI
    39	#   :98-102 alloc_sysmem          PORTED  `sys.alloc_sysmem` -- the flag arithmetic
   >40	#   :104-126 pci_scan_bus         PORTED  `scan.*` -- the mask filter + both id formats
    41	#   :128-136 list_devices/probe   PORTED  `pci.probe.*`
    42	#   :138-186 pci_setup_usb_bars   PORTED  `bars.*` -- THE HEADLINE. 7 ordered writes,
- :66 [only_older_revision] tinygrad/runtime/support/system.py:175 rev=129a3a3aa3 toks=xffff,bar_64
    64	# 1. THE u64 WALL, and it is three Python lines and one struct format.
    65	#      :96   `[(x & ((1<<55)-1)) * mmap.PAGESIZE for x in array.array('Q', ...)]`
   >66	#      :175  `((~(((hi << 32) | lo) & ~0xf)) + 1) & (0xffff... if bar_64 else ...)`
    67	#      :448  `struct.unpack('<Q', data)[0]`
    68	#    The PAGEFRAME entry, the 64-bit BAR size and the remote bar's host address
- :94 [only_older_revision] tinygrad/runtime/support/system.py:89 rev=129a3a3aa3 toks=atomic_lib
    92	#    TODO(p3) runtime/support/system.py:244  symbol=reset -- `os.system(...)`, in `PCIDevice.reset`.
    93	#
   >94	# 3. THE CTYPES LIBRARY GATE, :61-65 and :89. `atomic_lib` is
    95	#    `ctypes.CDLL(ctypes.util.find_library('atomic')) if sys.platform == "linux"
    96	#    else None` and `libsys` has NO such gate. So the two libraries are NOT
- :100 [at_no_revision] tinygrad/runtime/support/system.py:89 rev= toks=cap,barrier_lib
    98	#    is a SECOND, different predicate over the same two facts -- one per
    99	#    platform, and the two do not agree. That is the whole branching story at
   >100	#    :89 and it is pure, so it is ported as `cap.barrier_lib`, and the gate asks
    101	#    the question twice: which library, and whether it is a real fence at all.
    102	#    `ctypes.CDLL` and `find_library` are the FFI and are the trace.
- :127 [only_older_revision] tinygrad/runtime/support/system.py:391-393 rev=129a3a3aa3 toks=setsockopt,_recvall
    125	# ctypes structs (:79/:228/:230/:231/:237-239) are a ctypes packing of
    126	# `struct_vfio_irq_set` and belong to `autogen.py`; `socket.create_connection`
   >127	# and the five `setsockopt` calls (:391-393) are a socket; `_recvall`'s
    128	# `sock.recv` loop (:410-415) is a socket; `struct.pack`/`struct.unpack` (:239,
    129	# :374, :378, :418, :424, :426, :437, :448) are byte layout and are FFI, EXCEPT

## tinybendygrad/runtime/support/usb.bend  (3 rows)
- :34 [only_older_revision] tinygrad/runtime/support/usb.py:350-351 rev=06e57e3298 toks=usb_chunk
    32	# printing 590 green rows, and `ops_rdma` shipped `BNXT_VENDOR` as 5356 where the
    33	# header says 5348. `struct_libusb_transfer`'s thirteen field names, in order, are
   >34	# what `usb_chunk` (:350-351) addresses three times by name, so a transposed pair
    35	# is a silently wrong transfer.
    36	#
- :57 [only_older_revision] tinygrad/runtime/support/usb.py:42 rev=06e57e3298 toks=USB3,alloc_cbuffer,x1000
    55	#   * AND A CORRECTION TO CARRY BACK. ops_amd's 4096 is `0x1000`, which is NOT
    56	#     `usb_cq`'s offset: `usb_cq` is `usb_asm24[0x100c:0x1010]` = 4108..4112, and
   >57	#     0x1000 is `USB3`'s own CONTROL buffer size (:42, `alloc_cbuffer(0x1000)`). Both
    58	#     are real, they are different numbers, and this file rows both -- so a port
    59	#     that conflated them shows up as a disagreement rather than as a plausible
- :65 [only_older_revision] ops_amd.py:824 rev=1f521c4301 toks=dma_view,PCIDevice
    63	#     walk of state that ends in a CLAIM) and `usb_open` is its trace.
    64	#
   >65	# NOT CLOSED, DELIBERATELY. `dma_view` (ops_amd.py:824) is a `PCIDevice` method
    66	# that lives in ops_amd.bend's own wall 2 and is not usb.py's to answer.
    67	#

## tinybendygrad/runtime/webgpu_call.bend  (1 rows)
- :65 [at_no_revision] ops_webgpu.py:202-205 rev= toks=Uniform
    63	# `pass.uniforms.put` emits only the create. So the write has no trace entry of
    64	# its own and this file cannot match the trace by emitting one. `Op` therefore has
   >65	# `Uniform` -- :202-205 AS ONE UNIT, create-and-initialise -- and
    66	# `wgc_uniform_one_step` is the row that pins the collapse. THE TRACE IS NOT
    67	# CHANGED: those 147 rows are not mine to move.

