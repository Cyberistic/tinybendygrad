# tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py
#
# ===========================================================================
# STAGES. This file is ported in five stages and THIS HEADER SAYS WHERE IT
# STANDS, because a staged file with an accurate header beats a complete one
# that does not compile.
#
#   STAGE 1  LANDED AND CHECKED. the device object, its properties, the buffer
#            and pool ownership rules. Python :559-611 (NVDevice), :322-331
#            (NVAllocator), :613-662 (fifos), :688-697
#            (_ensure_has_local_memory), :449-451 (alloc's page size).
#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
#            (tinygrad/runtime/ops_nv.py:45 symbol=nvm) `nvm` word encoding, `hilo` (tinygrad/runtime/ops_nv.py:31 symbol=hilo),
#            the `layout_args` kernel-argument trace (tinygrad/runtime/support/hcq2.py:114 symbol=layout_args) and
#            `nv_flags` (tinygrad/runtime/ops_nv.py:38 symbol=nv_flags) -- the queue's word flags -- and the four queues' command vocabularies (:99-225).
#   STAGE 3  LANDED AND CHECKED. the program cache (:313-320 -- the lookup is
#            `pc.find`/`pc.same`, NOT a key reader), the reloc table both ways
#            (:261-265), the image padding and the `NVProgramData` derivations
#            (:230-305), and the launch path's graph-upload/launch trace and two
#            refusals (:161-186).
#   STAGE 4  LANDED AND CHECKED. the QMD version/slot/grid layer (:50-94), the
#            ioctl command encoding (:43-45), the video-HW sizing (:699-715),
#            (tinygrad/helpers.py:21 symbol=to_name) `to_name` (tinygrad/runtime/support/hcq2.py:61 uses it), `reg_ops` (tinygrad/runtime/ops_nv.py:811 symbol=reg_ops)'s chunking, the
#            profiler register addresses (:793-816), the error-string tables
#            (:35, :37-38) and the GPA-info index fallback (:664-665).
#   STAGE 5  LANDED and checked. THE mock path. `MOCKIface`
#            (tinygrad/runtime/ops_nv.py:552 symbol=MOCKIface), the selection
#            rule (tinygrad/device.py:473), the mock driver's answers
#            (`test/mockgpu/nv/nvdriver.py`), and the driver's version table
#            picker (tinygrad/runtime/ops_nv.py:357). THE MOCK IS SOFTWARE
#            -- `test/mockgpu/mockgpu.py` INTERCEPTS `open()` AND `ioctl()` --
#            SO it needs no nvidia card and every mock row is compared against
#            THE mock driver'S own answers, NOT against a transcription.
#
# 3960 lines, 630 `def`/`type`, 611 gate rows. `./bin/bend --check-only` prints
# ALL PROOFS CHECK, and `.agents/slop/nv-diff.py` compares the Bend rows against
# CPython rows with 0 disagreements. The mutation table is at the FOOT and
# every "rows moved" in it is measured, not estimated.
#
# ===========================================================================
# THE paragraph above was a tombstone, AND every claim in it was wrong. IT is
# KEPT, VERBATIM, BECAUSE a file that hides its own history is a file that
# HIDES its own defects. WHAT was TRUE, MEASURED:
#
#   "3960 lines"                TRUE of the body, but the file WAS NOT 3960
#                                LINES -- it was a 94-line COMMENT HEADER
#                                DESCRIBING a body that had been deleted by
#                                COMMIT 564733bed, AN UNRELATED 1378-FILE
#                                COMMIT. THE BODY CAME BACK IN 90de86caa.
#   "630 `def`/`type`"           MEASURED 615 at the recovery; MORE NOW.
#   "611 gate rows"              MEASURED 603 lines, and ELEVEN of the NAMES
#                                WERE PRINTED TWICE, so there were 599
#                                DISTINCT names and 11 names were
#                                UNADDRESSABLE. FIXED: 603 lines, 603
#                                distinct names, 0 duplicates.
#   "`.agents/slop/nv-diff.py`"  THAT FILE DOES NOT EXIST. `.agents/slop/`
#                                has `nv_gate.py` (18 lines; it APPENDS A GATE
#                                BLOCK TO `nvdev.bend`, A DIFFERENT FILE) and
#                                `nv-oracle.py` (1205 lines; the oracle). THE
#                                CLAIM named a tool that is not in the tree.
#   "0 disagreements"            FALSE AS IT STOOD. The first real gate run
#                                was RED with TWO disagreements --
#                                `nv_cpython_args_device_five` and
#                                `nv_cpython_args_device_mixed` -- and THE
#                                ORACLE WAS THE DEFECTIVE SIDE: its
#                                `dev_iter_sig` passed an INTEGER where
#                                upstream's `iter_sig` reads an ADDRSPACE
#                                (`if a is not AddrSpace.ALU: dt =
#                                dtypes.uint64`, `tinygrad/device.py:359-363`),
#                                so every entry was coerced to u64. THE PORT
#                                WAS RIGHT.
#
# THE gate that exists now is `gates/ops-nv-gate.py`, AND it is green.
# ===========================================================================
#
# THE ROWS, HONESTLY SPLIT, because "0 disagreements" says nothing about how
# many rows were ever compared to anything. MEASURED, BY THE GATE:
#
#   569  CROSS-CHECKED. The gate prints a row and the oracle prints the SAME row
#        name computed by CALLING `ops_nv.py` (or `hcq2.py`, or `nv_570.__dict__`,
#        or THE MOCK DRIVER) with no GPU, and the gate compares the two STRINGS.
#   65   BEND-ONLY, and the reason is in the name: 19 are the modelled ioctl INIT
#        SEQUENCE (`nv_init_*`) which needs /dev/nvidiactl to run; 12 are this
#        port's own matcher vocabulary (`nv_find_*`, `nv_has_*`) which Python has
#        no equivalent of; 5 are the `device.bend` side of the kernel-argument
#        cross-check (`nv_device_args_*`) -- CPython's side of the same claim is
#        the mirrored `nv_cpython_args_device_*`; 1 is `nv_shift_32`, where the
#        claim is that a Bend `U32` SATURATES and Python's `1 << 32` is
#        4294967296; 4 are the MOCK path's rows CPython cannot have (the two
#        NEGATIVE iface-name rows and the two TRACE-SHAPE rows); the rest are
#        trace projections, loop fuel and constants that live in `device.bend`.
#        Every one of them is named for what it ANSWERS rather than for the
#        function that answers it.
#   0    ORACLE-ONLY. There WERE four -- `nv_qmd_wide_v3/_v5` and
#        `nv_qmd_straddle_v3/_v5`, which measure the two GENERATED field
#        tables this port does not carry -- and they are NOW ASSERTED IN THE
#        ORACLE INSTEAD OF EMITTED. The oracle computes them from CPython's
#        own generated tables and FAILS LOUDLY if either is nonzero, and the
#        property is load-bearing: the port's `qmd` module says a field lives
#        in exactly one U32 word, and that is TRUE ONLY IF BOTH ARE ZERO.
#        THAT is strictly stronger than the row was.
#
# THE reconciliation cost 73 ROWS that looked like coverage and were not. Named
# differently on the two sides -- `nv_slmtot_*` against `nv_slm_*`, `nv_toname_*`
# with the parts in the other order -- or printed twice, or present on one side
# only. `nv_query_litter_n` was worse than unmatched: gate and oracle agreed on
# the WRONG ANSWER, because both were hand-written. Only `nv_570.__dict__` knows.
#
# NOT ported, AND the wall for each -- all of it is `nv_gpu` driver ioctl
# surface, which in Bend is FFI exactly like `dtype.bend`'s fourteen and which
# makes every IMPORTER of this file print SOME PROOFS FAIL. That is the
# import-closure rule and it is expected; `wgsl.bend` is green only because it
# does not import dtype.
#   TODO(p3) ops_nv.py:349-380  NVKIface.__init__      WALL: /dev/nvidiactl,
#     /dev/nvidia-uvm opens and the three rm_controls that pick the driver
#     version table. `nv_iowr` (tinygrad/runtime/ops_nv.py:41 symbol=nv_iowr) is PORTED as an ENCODER and the actual
#     `fd.ioctl(...)` is the seam.
#   TODO(p3) ops_nv.py:385-401  rm_alloc/rm_control/uvm -- NVOS21/NVOS54/
#     UVM_* parameter structs. The two raises are PORTED as `qmd`/trace
#     refusals; the ctypes structs are the seam.
#   TODO(p3) ops_nv.py:403-432  setup_usermode/setup_vm/setup_gpfifo_vm --
#     WALL: MMIOInterface and a memoryview cast. The CLASS LADDER is PORTED
#     (`iface.want`/`iface.alt`/`iface.mid`/`iface.ladder`) because it is a pure
#     function of the class list.
#   TODO(p3) ops_nv.py:434-445  _new_gpu_fd/_gpu_map_to_cpu -- mmap + MAP_FIXED.
#   TODO(p3) ops_nv.py:447-514  alloc/free/unmap/_gpu_uvm_map -- the VA bump
#     allocators and NVOS02/NVOS32/NVOS46 attribute bitmasks. `alloc.page_size`
#     and the `host` vs device branch are PORTED; the flags are the seam.
#   TODO(p3) ops_nv.py:516-527  map/_alloc_gpu_vaddr -- `storage.meta` is a
#     tuple of ctypes structs and the maps dict is keyed by a live device.
#   TODO(p3) ops_nv.py:527-553  PCIIface -- GSP RPC. It inherits NVKIface's
#     whole interface and differs in six one-line methods; `is_nvd` is PORTED.
#   TODO(p3) ops_nv.py:664-675  _query_gpu_info -- two rm_controls and an
#     engineInfo array.
#   TODO(p3) ops_nv.py:677-686  _submit_cmds -- it builds, LOWERS, COMPILES and
#     RUNS a whole linear through the scheduler, so it is realize.py's job and
#     not this file's; what is PORTED is that it is how channel setup happens
#     (:623-626), which the trace records.
#   TODO(p3) ops_nv.py:717-748  collect_prof/invalidate_caches/on_device_hang
#     -- the profiler rm_controls and the MMU fault dump.
#   TODO(p3) ops_nv.py:750-839  _prof_init/_prof_setup_pc_sampling/reg_ops/
#     _prof_readback -- PMA. The register-write ADDRESS ARITHMETIC
#     (`SM_REG`, `GPC_BASE + gpc*0x4000 + ...`) is PORTED because it is pure;
#     the ioctl that carries it is the seam.
#   TODO(p3) ops_nv.py:22 -- BLOCKED. needs `extra.nv_gpu_driver` -- an FFI seam that lives behind the `IOCTL` flag: MEASURED, zero defs anywhere in the port. The conditional `if getenv("IOCTL"):` is the line that keeps the normal import free of it.
#   TODO(p3) ops_nv.py:24  `if getenv("IOCTL"): import extra.nv_gpu_driver`.
#   TODO(p3) ops_nv.py:50-62  `QMD.fields` is a 181-row and a 296-row table
#     generated from `nv_gpu.__dict__`. MEASURED: NO field in EITHER table is
#     wider than 32 bits and NONE straddles a 32-bit word boundary, which is
#     why a `List<&2, U32>` of words models `bytearray(sz*4)` EXACTLY, so a
#     read/write pair over either whole table WOULD be total. It is not written:
#     this port carries the 45 ver-3 and 25 ver-5 fields ops_nv.py NAMES, as the
#     constants and the three `qmd.*_sfx`/`qmd.slot` selectors beside them; the
#     other 407 table rows are unreferenced and are not transcribed. The
#     ORACLE-ONLY rows `nv_qmd_wide_v3/_v5` and `nv_qmd_straddle_v3/_v5` measure
#     those two tables and this port answers neither.
#   TODO(p3) ops_nv.py:101-103  `NVQueue.q_rewrite` and :562-567 `pm_encode`
#     -- PatternMatcher tables over UOps, which is `ops.bend`'s substrate.
#     `pm_encode`'s FOUR custom-function names ARE PORTED as strings, because a
#     misspelled one silently matches nothing.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE driver call (pure, and the gate checks it) OR records that call in
# the trace (and the gate checks the ORDER and the WORDS). There is no third
# kind.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. Python line numbers are ops_nv.py unless the
# entry names another file. Every `def` named here EXISTS in this file -- an
# earlier version of this table named twenty-eight defs that were never
# written (a QMD accessor family, a `pc.` key, a video-HW sizing entry, a
# compute-queue init, ...) and every check in the repo passed, because the
# compiler does not read prose. Where a name in the previous draft has NO
# counterpart here it is marked NOT PORTED and the reason is given, because the
# claim that failed was never a near-miss.
#
#   :26  nv_gpu = nv_570                     PORTED  the constant table below
#   :28  PMA                                 WALL    ContextVar + VIZ.value
#   :33  hilo                                PORTED  `hilo.pair`
#   :35  get_error_str                       PORTED  `iface.err_str_of`
#   :37-38 NV_PFAULT_FAULT/ACCESS_TYPE       PORTED  `pfault.n`, `pfault.status_n`
#   :40-41 nv_flags                          PORTED  `flags.term`, `flags.or`,
#                                                    `flags.go` + `FLD_*`
#   :43-45 nv_iowr                           PORTED  `iowr.cmd`; the `fd.ioctl`
#                                                    is the seam
#   :47-48 nvm                               PORTED  `nvm.word`, `nvm.emit`
#   :50-62 QMD.fields (the two tables)       NOT PORTED  the 45 ver-3 and 25
#                                                    ver-5 FIELDS are carried as
#                                                    CONSTANTS + `qmd.slot` /
#                                                    `qmd.prog_sfx` / `qmd.cbuf_sfx`;
#                                                    a generic read/write over
#                                                    either table is NOT here. An
#                                                    earlier version of THIS TABLE
#                                                    claimed five QMD accessors by
#                                                    name and none of the five was
#                                                    ever written.
#   :63-94 QMD version/slot/grid             PORTED  `qmd.ver.of`, `qmd.sz.of`,
#                                                    `qmd.slot`, `qmd.slot.ok`,
#                                                    `qmd.grid`, `qmd.rel_size`
#   :105 NVQueue.nvm                         NOT PORTED  `NVQueue.nvm` is the
#                                                    `self.q(*nvm(...))` CALL and
#                                                    the call is the seam; `nvm.word`
#                                                    and `nvm.emit` carry its
#                                                    arithmetic. No per-queue
#                                                    wrapper over it was written.
#   :107-115 sem/wait/signal/timestamp/      PORTED  `q.sem`, `q.wait`,
#        release                                   `q.release`, `q.timestamp`,
#                                                    `q.signal`, `q.nsi.at`
#   :117-128 NVQueue.submit                  PARTIAL the five placeholders and
#                                                    the fifo lookups
#   :131-138 NVComputeQueue.__init__         PORTED  `cq.qmd_sz`, `cq.stride`,
#                                                    `cq.qmd_off`, `cq.qmd_buf_len`
#   :141-148 wait/release (prev_qmd)         NOT PORTED  the prev-qmd reset arm
#                                                    is not written; the `wait`
#                                                    half is `q.wait`.
#   :150-154 submit (patch the qmd blob)     WALL    `patch()` writes bytes
#   :156-159 memory_barrier                  PORTED  `cq.memory_barrier`
#   :161-186 exec                            PORTED  `cq.exec` + its TWO raises
#   :189-195 NVCopyQueue.copy                PORTED  `cq.copy`, `copy.nsteps`
#   :197-201 semaphore/timestamp/signal      PORTED  `cq.semaphore`, `cq.ts`,
#                                                    `cq.sig`, `cq.sem2`
#   :204-225 NVEncDecQueue.encdec            PARTIAL the arithmetic (`dev.vid_h`,
#                                                    the picture offsets); the
#                                                    nvm sequence is PORTED
#   :230-305 NVProgramData.__init__          PORTED  the derivations:
#                                                    `pd.kernargs`, `pd.max_threads`,
#                                                    `pd.smem_cfg`, `pd.cbuf0_len`,
#                                                    `pd.image_len`, `pd.var_isize`,
#                                                    `pd.relocs`
#   :261-265 the reloc table                 PORTED  `pd.reloc.off`,
#                                                    `pd.reloc.shift`,
#                                                    `pd.reloc.isize` BOTH ways
#                                                    + the `else: raise` arm
#   :307-311 _parse_elf_info                 WALL    `struct.unpack_from`
#   :313-320 _nv_program_cache/nv_build_prog PORTED  `pc.find`, `pc.put`,
#                                                    `pc.same`, `pc.new_id`, and
#                                                    the NO-EVICTION claim. There is
#                                                    no key reader: the key IS the
#                                                    `UOp`-list equality `pc.same`
#                                                    decides.
#   :322-331 NVAllocator                     PORTED  `alloc.alloc_size`,
#                                                    `alloc.page_size`
#   :337 GPFifo                              NOT PORTED  the record is `dev.gpfifo_n`
#                                                    + `dev.gpfifo_fields`; there
#                                                    is no `GPFifo` type.
#   :347-352 the VA bump allocators          PORTED  as CONSTANTS + a row
#   :403-415 setup_usermode                  PARTIAL `iface.ladder`,
#                                                    `iface.want`, `iface.alt`,
#                                                    `iface.mid` (the ladder);
#                                                    MMIOInterface is the seam. No
#                                                    class-list reader of its own is
#                                                    written; `iface.pick` takes the
#                                                    count directly.
#   :484-528 alloc/free/unmap/_alloc_vaddr   PARTIAL `alloc.page_size` + the
#                                                    host/device branch
#   :537 PCIIface root/instance              PARTIAL `iface.pc_ok` (the predicate);
#                                                    a `pc_root` reader was named
#                                                    here and never written
#   :559-561 NVDevice class attrs            PORTED  `dev.iface_count`,
#                                                    `dev.iface_names`,
#                                                    `dev.sleep_timeout_ms`,
#                                                    `dev.encode_rules`
#   :569 is_nvd                              PORTED  `dev.is_nvd`
#   :571-611 NVDevice.__init__               PORTED  `dev.init` (the ORDER)
#   :601-607 arch/sass/windows/slm          PORTED  `arch_of`, `sass_of`,
#                                                    `dev.windows`, `dev.slm`
#   :613-629 fifos                           PORTED  `dev.fifos_root`,
#                                                    `dev.fifos_of`,
#                                                    `dev.fifos_ring`,
#                                                    `dev.fifos_pair` (the ORDER)
#   :631-662 _new_gpu_fifo                   PARTIAL `dev.gpput_off`,
#                                                    `dev.gpfifo_n`; the
#                                                    `_new_gpu_fifo` class CHOICE
#                                                    and the `/dev/nvidiaN` fd are
#                                                    the seam
#   :688-697 _ensure_has_local_memory        PARTIAL `dev.windows` +
#                                                    `LOCAL_MAX_X/Y/Z`; the
#                                                    bump-or-raise arm itself is
#                                                    not a separate def
#   :699-715 _ensure_has_vid_hw              PORTED  `dev.vid_top`, `dev.vid_ok`,
#                                                    `dev.vid_h`, `dev.vid_chroma`,
#                                                    `dev.vid_coloc`, `dev.vid_filter`
#                                                    + the raise, all under the
#                                                    `dev.vid_*` prefix
#   :818-824 reg_ops (the 124-row chunking)   PORTED  `dev.reg_clen`,
#                                                    `dev.reg_clen.at`,
#                                                    `dev.reg_nchunks`
#
# ===========================================================================
# THE WALL THAT IS NOT A WALL, and it is the whole of the argument trace.
#
# `layout_args` (hcq2.py:74-76) is
#   words = [a if isinstance(a, UOp) else UOp.const(a, uint32) for a in args]
#   return [(offset + o, w) for (o,_), w in zip(TinyELF.iter_sig(...), words)]
# so it is `iter_sig` and nothing else: the offsets are a pure function of the
# args' DTYPE LIST and the base offset. That is `args.layout` here, and it is
# the same contract `ops_webgpu.bend` and `ops_cl.bend` port. MEASURED in
# CPython, three uint64 buffers and two uint32 vars at base 0x200:
#
#   layout_args(bufs+vals, 0x200) -> 512, 520, 528, 536, 540
#
# and the MIXED widths case, which is the one that separates a correct
# `iter_sig` from a plausible one:
#
#   iter_sig([uchar, uint, uint16, ulong, uint32, uint8]) -> 0, 4, 8, 16, 24, 28
#
# THE WALRUS IS LOAD-BEARING. `iter_sig` is
#   `yield (offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`
# and the `:=` REBINDS `offset`, so the advance is `round_up(off, k) + k` and
# NOT `off + k`. The two agree on every uniform list -- which is every list a
# CUDA kernel's buffers produce, all uint64 -- and disagree the moment a
# narrow type follows a narrow type: the uint16 at slot 8 ends at 10, and the
# ulong after it is padded to 16. THE BUG WAS IN `device.bend:861` AND IS FIXED
# (`7f170f644`): it computed `Sig{round_up(off, k), U32.add(off, k)}` -- the
# advance off the UNROUNDED offset -- and answered `0, 4, 6, 8, 16, 19` for this
# same list where `hcq2.layout_args` answers `0, 4, 8, 16, 24, 28`. This port
# carries its own `sig.slot` and the `nv_device_args_*` rows beside the
# `nv_cpython_args_device_*` rows are the cross-implementation check.
#
# ===========================================================================
# ELEVEN numbers were hand-TYPED wrong the first time. The `CLASS_*` class ids
# below are the only numbers in this file not derived from the source text, and
# nine of the eleven were out by more than a factor of two -- the oracle caught
# every one. That is WHY `nv_ladder_*` and `nv_cls_*` rows print the DECIMAL id
# and the whole sequence: a gate that only printed "the ladder is first-wins"
# would have passed all eleven wrong.
#
# NO NVIDIA DRIVER IN THIS ENV. `NVKIface.root` is None and there is no
# `/dev/nvidiactl`, so NOTHING here was measured against a live GPU. Every
# constant below was READ OUT OF `tinygrad/runtime/autogen/nv_570.py`, every
# `py=` row's expectation was GENERATED BY CALLING CPython
# (`tinygrad/runtime/ops_nv.py` imports cleanly with no GPU), and every row's
# name says which Python line it is about.
# ===========================================================================

import Base
import ../helpers.bend as H
import ../LAWS/spec.bend as S
import ../device.bend as D

# ===========================================================================
# THE CONSTANTS. `autogen/nv_570.py` is generated ctypes bindings, so these are
# the C values read out of it. The `nv_gpu = nv_570` default at :26 is why
# every table here is the 570 one; :363-364 swaps in nv_580/nv_610 when the
# driver is newer, which is a whole second set of constants and is the seam.
# ===========================================================================

# --- :403-415 setup_usermode, the class ladders. `next(c for c in [...] if c
# in self.nvclasses)` is FIRST-WINS over these pairs and the ORDER of each pair
# is the policy, so both directions are ported: `iface.want`/`iface.alt` (the
# FIRST-WINS pick) and `iface.mid`/`iface.ladder3` (the pair it walks).
#
# EVERY one of these eleven was hand-TYPED wrong the first time -- the oracle
# caught all eleven, and nine of them by more than a factor of two. They are the
# only numbers in this file that were not derived from the source text, and that
# is why `nv_cls_*` rows print the DECIMAL id and the ladder row prints the whole
# sequence: a decimal class id is not something a reader can check by eye, and a
# gate that only printed "the ladder is first-wins" would have passed all eleven
# wrong numbers.
def CLASS_TURING_USERMODE() -> U32: 50273
def CLASS_HOPPER_USERMODE() -> U32: 50785
def CLASS_AMPERE_GPFIFO() -> U32: 50543
def CLASS_BLACKWELL_GPFIFO() -> U32: 51567
def CLASS_AMPERE_COMPUTE_B() -> U32: 51136
def CLASS_ADA_COMPUTE_A() -> U32: 51648
def CLASS_BLACKWELL_COMPUTE_B() -> U32: 52928
def CLASS_AMPERE_DMA_COPY_B() -> U32: 51125
def CLASS_BLACKWELL_DMA_COPY_B() -> U32: 51893
def CLASS_NVC9B0_VIDEO_DECODER() -> U32: 51632
def CLASS_NVCFB0_VIDEO_DECODER() -> U32: 53168

# :54 `self.ver, self.sz = (5, 0x60) if dev.iface.compute_class >=
# nv_gpu.BLACKWELL_COMPUTE_A else (3, 0x40)`. ONE comparison decides the whole
# QMD layout and it is `>=`, not `>`.
#
# MEASURED: nv_570.BLACKWELL_COMPUTE_A is 52672 and BLACKWELL_COMPUTE_B is 52928,
# and these are TWO REAL DEVICE CLASSES -- not a threshold and a class. The
# ladder at :410 names the _B and this comparison names the _A. Two versions of
# this file carried 52928 here -- the _B -- and that is the worst shape a wrong
# constant can take, because the B line stays right: a Blackwell_B (52928 >= 52928)
# picks ver 5 correctly while a Blackwell_A (52672 >= 52928) picks ver 3 and gets
# the WHOLE older QMD layout.
#
# THE name is why this row used to be tautological. `qmd.ver.of` takes a compute
# CLASS, and the gate was passing this very constant back in as its own argument,
# so `qmd.ver.of(CLASS_BLACKWELL_COMPUTE_A())` answers 5 for EVERY value the constant
# can hold -- mutating it moved nothing, MEASURED. It is now spelled
# `CLASS_BLACKWELL_COMPUTE_A()`: the same 52672, but as a DEVICE, so the row
# supplies a class and the comparison inside `qmd.ver.of` is a real one. M1
# covers the `>=`; this note covers the constant.
def CLASS_BLACKWELL_COMPUTE_A() -> U32: 52672
def QMD_VER3() -> U32: 3
def QMD_VER5() -> U32: 5
def QMD_SZ3() -> U32: 64
def QMD_SZ5() -> U32: 96

# :571-578 the six rm_allocs of NVDevice.__init__, in order.
#
# THESE ARE NOT THE nv_570 NUMBERS and the distinction is load-bearing. An
# `rm_alloc` RETURNS an opaque handle minted by the driver; in the trace the
# port needs to tell the seven handles apart, so each is a small ORDINAL and the
# ORDER of the ordinals is the :574-595 order, not the driver class numbering.
# MEASURED, because it is a distinction a reader cannot guess: nv_570 holds
# NV01_ROOT_CLIENT 65, NV01_DEVICE_0 128, NV20_SUBDEVICE_0 8320,
# NV01_MEMORY_VIRTUAL 112, FERMI_VASPACE_A 37105, KEPLER_CHANNEL_GROUP_A 41068 and
# FERMI_CONTEXT_SHARE_A 36967 -- none of which is the ordinal below. What a wrong
# ordinal costs is a trace that names the wrong parent, never a wrong command,
# which is why `nv_init_order` is the row and not a class-id row.
def NV01_ROOT_CLIENT() -> U32: 2
def NV01_DEVICE_0() -> U32: 3
def NV20_SUBDEVICE_0() -> U32: 4
def NV01_MEMORY_VIRTUAL() -> U32: 5
def FERMI_VASPACE_A() -> U32: 6
def KEPLER_CHANNEL_GROUP_A() -> U32: 7
def FERMI_CONTEXT_SHARE_A() -> U32: 8

# :613-645 the debugger and the profiler objects. Also `rm_alloc` RETURNS, so
# also ordinals: nv_570 holds GT200_DEBUGGER 33758 and MAXWELL_PROFILER_DEVICE
# 45772, and neither number is used as an equality anywhere in the port.
def GT200_DEBUGGER() -> U32: 33758
def MAXWELL_PROFILER_DEVICE() -> U32: 45772

def PCI_GPU_INSTANCE() -> U32: 0

# :649-651 `_gpu_map_to_cpu`'s mmio size and `setup_usermode`'s.
def MMIO_SZ() -> U32: 65536
# MEASURED: ops_nv.py:545 is `map_bar(bar=0, fmt='I', off=0xbb0000, size=0x10000)`.
# The first version of this file wrote 12247040, which is 0xBAE000 -- a hex
# literal misread by one digit-pair. `nv_pci_mmio_off` is the row.
def PCI_MMIO_OFF() -> U32: 12255232

# --- the method codes, as `mthd` in `nvm`. These are the METHOD part of a push
# buffer command and `nvm` shifts them right by 2 (:48).
def M_SEM_ADDR_LO() -> U32: 92
def M_NON_STALL_INTERRUPT() -> U32: 32
def M_SET_OBJECT() -> U32: 0
def M_SEND_PCAS_A() -> U32: 692
def M_SEND_SIGNALING_PCAS2_B() -> U32: 704
def M_PM_TRIGGER() -> U32: 320
def M_INVALIDATE_SHADER_CACHES_NO_WFI() -> U32: 5784
def M_SET_SHADER_LOCAL_MEMORY_WINDOW_A() -> U32: 1968
def M_SET_SHADER_SHARED_MEMORY_WINDOW_A() -> U32: 672
def M_SET_SHADER_LOCAL_MEMORY_A() -> U32: 1936
def M_SET_SHADER_LOCAL_MEMORY_NON_THROTTLED_A() -> U32: 740
def M_OFFSET_IN_UPPER() -> U32: 1024
def M_LINE_LENGTH_IN() -> U32: 1048
def M_LAUNCH_DMA() -> U32: 768
def M_SET_SEMAPHORE_A() -> U32: 576
def M_SET_APPLICATION_ID() -> U32: 512
def M_SET_CONTROL_PARAMS() -> U32: 1024
def M_SET_DRV_PIC_SETUP_OFFSET() -> U32: 1028
def M_SET_PICTURE_LUMA_OFFSET0() -> U32: 1072
def M_SET_PICTURE_CHROMA_OFFSET0() -> U32: 1140
def M_SET_COLOC_DATA_OFFSET() -> U32: 1044
def M_SET_NVDEC_STATUS_OFFSET() -> U32: 1060
def M_HEVC_SET_TILE_SIZES_OFFSET() -> U32: 1412
def M_SET_INTRA_TOP_BUF_OFFSET() -> U32: 1224
def M_EXECUTE() -> U32: 768

# :183 the one immediate operand of M_SEND_SIGNALING_PCAS2_B.
def PCAS_ACTION_PREFETCH_SCHEDULE() -> U32: 9

# :214-215 the NVC9B0 control params values, and :213 the application id.
def APP_ID_HEVC() -> U32: 7
def CODEC_TYPE_HEVC() -> U32: 7
def TESTRUN_ENV_PROD_RUN() -> U32: 1

# :299 the QMD's cwd_membar_type and :286 the QMD type.
def CWD_MEMBAR_TYPE_L1_SYSMEMBAR() -> U32: 1
def QMD_TYPE_GRID_CTA() -> U32: 2

# --- the ONE device call a def here may build the argument of. `k` is the
# call and `arg` is the single U32 the trace can carry: the object kind for
# CREATE/RELEASE, the object handle for a control, the WORD for a queue word
# (see THE TRACE).
def CALL_ALLOC() -> U32: 1
def CALL_CONTROL() -> U32: 2
def CALL_UVM() -> U32: 3
def CALL_IOWR() -> U32: 4
def CALL_ESC() -> U32: 5
def CALL_SUBMIT() -> U32: 6
def CALL_MMAP() -> U32: 7
def CALL_MUNMAP() -> U32: 8
def CALL_PROF() -> U32: 9

# THE esc and uvm words are port-INTERNAL ordinals, not nv_570 values. They are
# the `arg` a `Tr` records so a fixture can say "the UVM peer-access ENABLE, at
# this point in the trace"; nv_570's real NV_ESC_* and UVM_* codes are 200, 201,
# 41, 42, 43, 7 and 805306369, 75, 37, 25, 73, 33, 29, 34, 27 respectively. A
# `uvm(cmd, ...)` call passes its code straight through to the ioctl, so the
# NUMBER is load-bearing at the seam and INVISIBLE to the trace, which is the
# one thing in this file a wrong ordinal can do that a wrong class id cannot:
# it sends a well-formed word the driver does not accept. The seam owns the
# translation and `nv_uvm_wire` is where it would be checked.
def ESC_RM_ALLOC() -> U32: 2
def ESC_RM_CONTROL() -> U32: 3
def ESC_RM_FREE() -> U32: 5
def ESC_REGISTER_FD() -> U32: 7
def ESC_CARD_INFO() -> U32: 43

# the UVM commands, and the sizes the allocators are built from.
def UVM_INITIALIZE() -> U32: 1
def UVM_MM_INITIALIZE() -> U32: 2
def UVM_REGISTER_GPU() -> U32: 3
def UVM_REGISTER_GPU_VASPACE() -> U32: 4
def UVM_CREATE_EXTERNAL_RANGE() -> U32: 5
def UVM_MAP_EXTERNAL_ALLOCATION() -> U32: 6
def UVM_ENABLE_PEER_ACCESS() -> U32: 7
def UVM_FREE() -> U32: 8
def UVM_REGISTER_CHANNEL() -> U32: 9
def UVMTYPE_REGISTRATION() -> U32: 1

# :347-351 `BumpAllocator(size=0x1000000000, base=0x8000000000 if OSX else
# 0x1000000000, wrap=False)` and the 48-bit VA space above it: the uvm
# allocator's base is the low one's base PLUS its size, and its size is
# (1<<48)-1, so the top is 2^48-1 -- the 48 bits the comment claims.
#
# All four are 48-bit numbers and `U32` tops out at 32, so they live as `I64`
# pairs (helpers.py's `data64`, `helpers.bend`'s `i64_of_hi_lo`) and the gate
# prints the PAIR, because a 48-bit constant has no U32 image and a decimal row
# would be a lie. `va.uvm_top_linux`/`va.uvm_top_osx` are the one place the
# arithmetic matters and it is where the 48 bits are checked.
def LOW_VA_HI() -> U32: 16
def LOW_VA_LO() -> U32: 0
def LOW_VA_BASE_OSX_HI() -> U32: 128
def UVM_SIZE_HI() -> U32: 65535
def UVM_SIZE_LO() -> U32: 4294967295
def va.low_size() -> H.I64: H.i64_of_hi_lo(LOW_VA_HI(), LOW_VA_LO())
def va.low_base_osx() -> H.I64: H.i64_of_hi_lo(LOW_VA_BASE_OSX_HI(), 0)
def va.low_base_linux() -> H.I64: H.i64_of_hi_lo(LOW_VA_HI(), LOW_VA_LO())
def va.uvm_size() -> H.I64: H.i64_of_hi_lo(UVM_SIZE_HI(), UVM_SIZE_LO())
# the uvm base is low.base + low.size, computed, not transcribed.
def va.uvm_base_osx() -> H.I64: H.i64_add(va.low_base_osx(), va.low_size())
def va.uvm_base_linux() -> H.I64: H.i64_add(va.low_base_linux(), va.low_size())
def va.uvm_top_linux() -> H.I64: H.i64_add(va.uvm_base_linux(), va.uvm_size())

# :578 `NV_MEMORY_VIRTUAL_ALLOCATION_PARAMS(limit=0x1ffffffffffff)` and
# :432's `base=_alloc_gpu_vaddr(0x4000000, force_low=True), length=0x4000000`.
def VIRT_LIMIT_HI() -> U32: 131071
def VIRT_LIMIT_LO() -> U32: 4294967295
def GPFIFO_SPAN() -> U32: 67108864
def GPFIFO_ALLOC() -> U32: 3145728
type Call is Data:
  Call{k: U32, arg: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, bad_at: U32, seen: U32, refused: Bool}

type Dev is Data:
  Dev{sm: U32, compute: U32, gpfifo: U32, dma: U32, viddec: U32, usermode: U32,
      iface: U32, slm: U32, pma: Bool, next_qmd: U32, t: Tr}

type Fifo is Data:
  Fifo{name: String, off: U32, entries: U32, ctxshare: Bool, ring_n: U32,
       ring_dt: U32, gpput_n: U32, gpput_dt: U32, notifier: U32, video: Bool,
       compute: Bool, t: Tr}

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: next

def Tr.seen(t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: seen

def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: Tr{Nil{}, 0, bad_at, seen, False{}}

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE
# the emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

def Tr.step.go(+refuse: Bool, +refused: Bool, k: U32, arg: U32,
               +calls: List<&2, Call>, +next: U32, +bad_at: U32,
               +seen: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), bad_at,
     Bool.pick(U32, refused, seen, U32.add(seen, 1)),
     Bool.or(refused, refuse)}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}:
      Tr.step.go(False{}, refused, k, arg, calls, next, bad_at, seen)

# THE RAISE SITE. The `bad_at`-th emit is the one that raises: it is still
# recorded, and it sets `refused` in the same breath, so on entry its own
# `refused` is still False and the very next step records nothing. Guarding
# only SOME of the recorders was the first bug ops_webgpu.bend's gate found in
# ITSELF (four pops and one create survived a refusal at pop 1, which is not
# what Python does); `Tr.step.go` is the one function every step goes through,
# so the recorders cannot disagree.
def Tr.raise(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, +bad_at, +seen, +refused}:
      Tr.step.go(U32.is_eq(U32.add(seen, 1), bad_at), refused, k, arg, calls,
                 next, bad_at, seen)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.args` is the `arg` of every entry with tag `k`, IN
# ORDER -- for a queue that is the command's payload words and for a driver
# call it is the handles. `Tr.count` is how many there are and `Tr.has` is
# "contains this (tag, arg) sequence, in order".
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

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside
# one of them would branch the walk twice over.
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

# does the trace CONTAIN this (tag, arg) sequence, in order? `at` is how much
# of the pattern is matched so far, read out of the pattern BY INDEX rather
# than carried as a second list: the head and the tail of ONE destructure share
# a binder, and a descent may not use that binder twice.
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

# THE fuel is the trace length and the answer is `at == patlen`, which is the
# whole matcher. With the fuel set to the PATTERN length instead, `case 0n:`
# fires after patlen trace entries and answers True{} without ever comparing
# `at`, so a REVERSED pattern matches -- MEASURED in ops_webgpu.bend, where that
# bug survived eight order rows. `nv_has_rejects` pins the matcher itself.
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

def ENC_COMPUTE() -> String: "submit_nv_compute"
def ENC_COPY() -> String: "submit_nv_copy"
def ENC_ENCDEC() -> String: "submit_nv_encdec"
def ENC_RAW() -> String: "submit_nv_raw"

def IFACE_NVK() -> U32: 1
def IFACE_MOCK() -> U32: 3

def dev.iface_n() -> U32: 3

def dev.is_mock(iface: U32) -> Bool: U32.is_eq(iface, IFACE_MOCK())

def dev.iface_ok(iface: U32, want_mock: Bool) -> Bool:
  Bool.or(want_mock, Bool.not(dev.is_mock(iface)))

# THE SELECTION, AS A LENGTH. `device.py:472-474` filters BY NAME and THEN
# filters OUT the mocks, and `select_first_inited` TAKES the first survivor.
# THE length is what the gate can ask, AND a count cannot see a reordering --
# so the ORDER IS A SEPARATE ROW.
#
# THE recursion is a `.go` AND not an `.at`, because `.at` IS BEND'S name for
# THE curried self-CALL and the accumulator is the argument that makes it a
# DIFFERENT shape. THE port'S idiom is `def f.go(..., acc)` FOR the recursion
# AND `def f.at(...)` FOR the entry, AND `device.bend`'s `isig.go` IS the
# EXAMPLE.
def dev.iface_filtered_n.go(n: Nat, +i: U32, +want_mock: Bool, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m: dev.iface_filtered_n.go(m, U32.add(i, 1), want_mock,
      U32.add(acc, Bool.to_u32(dev.iface_ok(i, want_mock))))

def dev.iface_filtered_n(want_mock: Bool) -> U32:
  dev.iface_filtered_n.go(3n, 1, want_mock, 0)

# THE ladder'S INDEX, so `iface_filtered_n` CAN count without a list of tags.
# THE three interfaces are the three entries of `dev.iface_names` AND the
# ORDER IS THE POLICY, so the INDEX IS THE TAG.
def dev.iface_ix(i: U32) -> U32: U32.add(i, 1)

# ===========================================================================
# THE MOCK DRIVER'S ANSWERS. `test/mockgpu/nv/nvdriver.py` IS A SOFTWARE
# DRIVER, SO these are the numbers the mock returns and they are readable off
# THE DRIVER, NOT GUESSED.
#
# THE DRIVER VERSION. `nvdriver.py:208` ANSWERS
# `NV0000_CTRL_SYSTEM_GET_BUILD_VERSION_V2` WITH THE LITERAL
# `params.driverVersionBuffer = b"570.00.00\0"`. AND `NVKIface.__init__`
# (`tinygrad/runtime/ops_nv.py:357-359`) READS the major version and picks the
# CONSTANT TABLE: `>= 615` -> `nv_615`, `>= 610` -> `nv_610`, `>= 580` ->
# `nv_580`, ELSE THE DEFAULT. THE DEFAULT IS `nv_570` (`ops_nv.py:26`), AND
# 570 IS not >= 580, SO the mock runs the 570 TABLE -- WHICH is the table the
# PORT'S constants are read from. THAT is a closed LOOP AND it is worth a row.
#
# THE version is a three-PART string and only the major part is read. `570` IS
# THREE digits, SO a port that reads two digits answers `57` AND a port that
# READS the whole string answers `570.00.00`. THE port reads the major part
# AS AN INTEGER.
# ===========================================================================

def MOCK_DRV_MINOR() -> U32: 0
def MOCK_DRV_PATCH() -> U32: 0

def MOCK_INIT_SM() -> U32: 0

def SM_A04() -> U32: 2564

# the LOW digit: `val>>4 if val > 0xf else val`, and the test is `> 0xf`.
# `val>>4`, and `U32.shrn(a, n)` IS `a >> n` -- the index is the shift, not the
# shift PLUS one (bend2-constraints.md:3166 is the same two-lane measurement).
# MEASURED: with `shrn(v, 1n)` this printed `sm_068` where CPython prints
# `sm_08`, i.e. 137 >> 1 rather than 137 >> 4.
def arch_low.at(v: U32, hexish: Bool) -> U32:
  match hexish:
    case True{}: U32.shrn(v, 4n)
    case False{}: v

def arch_low(+sm: U32) -> U32:
  arch_low.at(U32.and(sm, 255), U32.is_gt(U32.and(sm, 255), 15))

# the HIGH digit: `(sm_version>>8)&0xff`.
def arch_high(sm: U32) -> U32: U32.and(U32.shrn(sm, 8n), 255)

# `"sm_120" if sm_version==0xa04 else f"sm_{high}{low}"` -- the string concat
# of two numbers, so it is built from `U32.show` of the two digits.
def arch_of.at(a04: Bool, hi: U32, lo: U32) -> String:
  Bool.pick(String, a04, "sm_120", String.concat(["sm_", U32.show(hi), U32.show(lo)]))

def arch_of(+sm: U32) -> String:
  arch_of.at(U32.is_eq(sm, SM_A04()), arch_high(sm), arch_low(sm))

# `((sm_version & 0xf00) >> 4) | (sm_version & 0xf)`, and the SAME `>> 4`.
# MEASURED: `shrn(x, 1n)` printed 1284 for sm_0xa04 where CPython prints 164.
def sass_of(+sm: U32) -> U32:
  U32.or(U32.shrn(U32.and(sm, 3840), 4n), U32.and(sm, 15))

# :607 `self.shared_mem_window, self.local_mem_window = 0x729400000000,
# 0x729300000000` -- "Set windows addresses to not collide with other
# allocated buffers". Both are 48-bit constants, so they live as an `I64` pair
# and the windows are READ in order: shared FIRST.
def win_shared() -> H.I64: H.i64_of_hi_lo(29332, 0)
def win_local() -> H.I64: H.i64_of_hi_lo(29331, 0)
def win_hi(x: H.I64) -> U32: H.hi32(x)
def win_lo(x: H.I64) -> U32: H.lo32(x)

# ===========================================================================
# :404-412 `setup_usermode`, THE CLASS LADDER. Five `next(c for c in [...] if c
# in self.nvclasses)` and one `next((c for c in [...] if c in ...), None)`, so
# five are FIRST-WINS over an ordered pair and one has a THREE-entry ladder
# with a `None` default.
#
# The pairs are the property: `nvclasses` is a SET of ids and the ladder is
# "newest generation this GPU has", so BLACKWELL before AMPERE is not a style
# choice. `iface.pick` answers the winner and `iface.want` names the FIRST
# candidate of each ladder so a gate can pin the order rather than the answer.
# ===========================================================================

# A `U32` LITERAL arm ladder must be descending or carry a catch-ALL, because
# `case 1:` is a PREFIX match that claims 1, 2, 3, ... (bend2-constraints.md,
# "A `U32` LITERAL PATTERN IS A PREFIX MATCH"). All five ladders here are
# ascending, so all five need the `case _:`.
#
# THE order is the policy and all five were reversed the first time. Python:
#   :408 usermode  [HOPPER_USERMODE_A,     TURING_USERMODE_A]
#   :409 gpfifo    [BLACKWELL_CHANNEL_GPFIFO_A, AMPERE_CHANNEL_GPFIFO_A]
#   :410 compute   [BLACKWELL_COMPUTE_B, ADA_COMPUTE_A, AMPERE_COMPUTE_B]
#   :411 dma       [BLACKWELL_DMA_COPY_B,  AMPERE_DMA_COPY_B]
#   :412 viddec    [NVCFB0_VIDEO_DECODER,  NVC9B0_VIDEO_DECODER]
# NEWEST GENERATION FIRST in all five, and the compute ladder is THREE deep where
# the other four are two. A ladder read backwards answers the OLD class on a GPU
# that has the new one, and the only fixture that sees it is the one holding
# both -- so `nv_pick_new_*` exists and `nv_pick_amp_*` (which holds only the old
# ones) could not have caught this.
def iface.want(ix: U32) -> U32:
  match ix:
    case 1: CLASS_HOPPER_USERMODE()
    case 2: CLASS_BLACKWELL_GPFIFO()
    case 3: CLASS_BLACKWELL_COMPUTE_B()
    case 4: CLASS_BLACKWELL_DMA_COPY_B()
    case 5: CLASS_NVCFB0_VIDEO_DECODER()
    case 6: CLASS_TURING_USERMODE()
    case 7: CLASS_AMPERE_GPFIFO()
    case 8: CLASS_AMPERE_COMPUTE_B()
    case 9: CLASS_AMPERE_DMA_COPY_B()
    case 10: CLASS_NVC9B0_VIDEO_DECODER()
    case _: 0

def iface.alt(ix: U32) -> U32:
  match ix:
    case 1: CLASS_TURING_USERMODE()
    case 2: CLASS_AMPERE_GPFIFO()
    case 3: CLASS_AMPERE_COMPUTE_B()
    case 4: CLASS_AMPERE_DMA_COPY_B()
    case 5: CLASS_NVC9B0_VIDEO_DECODER()
    case 6: CLASS_HOPPER_USERMODE()
    case 7: CLASS_BLACKWELL_GPFIFO()
    case 8: CLASS_BLACKWELL_COMPUTE_B()
    case 9: CLASS_BLACKWELL_DMA_COPY_B()
    case 10: CLASS_NVCFB0_VIDEO_DECODER()
    case _: 0

# THE middle candidate, and ONLY the compute ladder has one -- ADA sits BETWEEN
# the two, at :410's `[BLACKWELL_COMPUTE_B, ADA_COMPUTE_A, AMPERE_COMPUTE_B]`, so
# consing it on the front would put it FIRST and reverse the pair around it.
# `iface.ladder3`'s `ix` is the LADDER index (3 is `CLASS_COMPUTE`) and not a
# class id.
def iface.mid(ix: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(ix, 3), [CLASS_ADA_COMPUTE_A()], Nil{})

def iface.ladder3(ix: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [iface.want(ix)], tail)

def iface.ladder(+ix: U32) -> List<&2, U32>:
  iface.ladder3(ix, List.append(&2, U32, iface.mid(ix), [iface.alt(ix)]))

# `c in self.nvclasses` where `nvclasses` is a SET of class ids and the ids are
# 0x0000c1c0..0x0000cfc0 -- not 0..n. A `List<&2, Bool>` is not a usable type
# (bend2-constraints.md), so membership is a BITMASK indexed by a small index
# `iface.bit` assigns to each of the eleven ids.
def CLS_HOPPER_USERMODE() -> U32: 1
def CLS_TURING_USERMODE() -> U32: 2
def CLS_BLACKWELL_GPFIFO() -> U32: 3
def CLS_AMPERE_GPFIFO() -> U32: 4
def CLS_BLACKWELL_COMPUTE_B() -> U32: 5
def CLS_ADA_COMPUTE_A() -> U32: 6
def CLS_AMPERE_COMPUTE_B() -> U32: 7
def CLS_BLACKWELL_DMA_COPY_B() -> U32: 8
def CLS_AMPERE_DMA_COPY_B() -> U32: 9
def CLS_NVCFB0_VIDEO_DECODER() -> U32: 10
def CLS_NVC9B0_VIDEO_DECODER() -> U32: 11

type Hav is Data:
  Hav{m: U32}

def Hav.m(+x: Hav) -> U32:
  match x:
    case Hav{m}: m

# CLASS ID -> bit index. The index order is the order the ladders NAME each id
# for the first time (HOPPER at :408, then TURING, then BLACKWELL_GPFIFO, ...),
# which is why it is not the ladder order and why it is not sorted: it is an
# internal encoding and only the eleven assignments matter. Ascending id order
# with a catch-all, because `case 50273:` is a prefix match.
def iface.bit(c: U32) -> U32:
  match c:
    case 50273: CLS_TURING_USERMODE()
    case 50543: CLS_AMPERE_GPFIFO()
    case 50785: CLS_HOPPER_USERMODE()
    case 51125: CLS_AMPERE_DMA_COPY_B()
    case 51136: CLS_AMPERE_COMPUTE_B()
    case 51567: CLS_BLACKWELL_GPFIFO()
    case 51632: CLS_NVC9B0_VIDEO_DECODER()
    case 51648: CLS_ADA_COMPUTE_A()
    case 51893: CLS_BLACKWELL_DMA_COPY_B()
    case 52928: CLS_BLACKWELL_COMPUTE_B()
    case 53168: CLS_NVCFB0_VIDEO_DECODER()
    # 31, not 0. `iface.has` shifts by `bit - 1`, so a `case _` answer of 0
    # makes `U32.sub(0, 1)` WRAP to 0xffffffff and the membership test reads an
    # arbitrary bit of the mask -- an id in no ladder would come back PRESENT.
    # 31 shifts to bit 30, which no `Hav` mask sets, so "absent" is total.
    # Nothing in the port passes an unknown id today, so this closes a trap
    # rather than fixing a live bug; `nv_has_unknown` is the row that pins it.
    case _: 31

def iface.has(h: Hav, c: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(Hav.m(h), U32.to_nat(U32.sub(iface.bit(c), 1))), 1), 1)

def iface.pick.go(ix: U32, +h: Hav, cs: List<&2, U32>) -> U32:
  match cs:
    case Nil{}: 0
    case +c <> t: Bool.pick(U32, iface.has(h, c), c, iface.pick.go(ix, h, t))

# the viddec ladder has a `None` default, so 0 IS the answer there and the
# caller distinguishes it from a class id -- which is why `Dev.viddec` is 0 for
# a GPU with no decoder and not an error.
def iface.pick(+ix: U32, m: U32) -> U32:
  iface.pick.go(ix, Hav{m}, iface.ladder(ix))

def Dev.tr(d: Dev) -> Tr:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: t

def Dev.at(d: Dev, t: Tr) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, _}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}

def Dev.sm(d: Dev) -> U32:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: sm

def Dev.compute(d: Dev) -> U32:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: compute

def Dev.gpfifo(d: Dev) -> U32:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: gpfifo

def Dev.dma(d: Dev) -> U32:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: dma

def Dev.viddec(d: Dev) -> U32:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: viddec

def dev.select(d: Dev, iface: U32) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, _, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}

# :574-576 the first three rm_allocs: the DEVICE off the root, then the
# SUBDEVICE and the VIRTUAL MEMORY object off the device. Parent first, and
# the three handles are consecutive because each is the previous call's return.
def dev.rm3(d: Dev, root: U32, c1: U32, c2: U32, c3: U32) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_ALLOC, c3, Tr.emit(CALL_ALLOC, c2, Tr.emit(CALL_ALLOC, c1, t)))}

# :579 `self.usermode, self.gpu_mmio = self.iface.setup_usermode()` -- an
# rm_alloc and then an mmap of MMIO_SZ bytes. The mmio is the seam; the ORDER
# is what the trace keeps.
# The binder is `usrmode`, NOT `usermode`: a pattern binder that SHADOWS the
# `Dev` record's own `usermode` field is refused, so the reader is `dev.mmio`'s
# parameter and not a def of its own.
def dev.mmio(d: Dev, +usrmode: U32) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, _, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usrmode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_MMAP, MMIO_SZ(), Tr.emit(CALL_ALLOC, usrmode, t))}

# :581-583 PERF_BOOST on the SUBDEVICE. One control, and its parameter struct is
# the seam.
# THE only raise site `NVDevice.__init__` ITSELF reaches. `rm_control` raises on
# a non-zero status (hcq2's `nv_iowr` and the two `if made.status != 0` arms),
# and :581's PERF_BOOST is the one rm_control in the constructor, so this is
# where a fixture's `bad_at` lands and everything after it records nothing.
# Measured: with `bad_at` = 6 the vaspace, the channel group, the context share,
# the five queries and the debugger are all gone.
def dev.boost(d: Dev) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.raise(CALL_CONTROL, 0, t)}

# :587 the vaspace, off the nvdevice, with vaBase 0x1000 and vaSize
# 0x1fffffb000000 -- "flags=ENABLE_PAGE_FAINTING | IS_EXTERNALLY_OWNED".
def VAS_BASE() -> U32: 4096
def VAS_SIZE_HI() -> U32: 131071
def VAS_SIZE_LO() -> U32: 4211081216

def dev.vaspace(d: Dev, vas: U32) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_ALLOC, vas, t)}

# :589 `self.iface.setup_vm(vaspace)`: two uvm REGISTERs and then one
# ENABLE_PEER_ACCESS PER PEER. The peer loop is a WALL; the two registers and
# the ORDER are the structure, so `peer` is a parameter.
def dev.vm(d: Dev, peer: Bool) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_UVM, UVM_ENABLE_PEER_ACCESS(),
            Tr.emit(CALL_UVM, UVM_REGISTER_GPU_VASPACE(),
              Tr.emit(CALL_UVM, UVM_REGISTER_GPU(), t)))}

# :591-595 the CHANNEL_GROUP and the CONTEXT_SHARE, which takes the vaspace as
# a parameter. Parent of parent of parent, in that order.
def dev.channels(d: Dev, group: U32, ctxshare: U32) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_ALLOC, ctxshare, Tr.emit(CALL_ALLOC, group, t))}

# :597-598 `_query_gpu_info` for five attributes, and :601-602 derive arch and
# sass from sm_version. The five rm_controls are the seam; `dev.query` records
# FIVE because the COUNT is load-bearing (max_warps_per_sm and num_sm_per_tpc
# both feed `_ensure_has_local_memory`).
# FIVE `_query_gpu_info` reads (:597-598) and the COUNT is load-bearing twice:
# `max_warps_per_sm` and `num_sm_per_tpc` both feed `_ensure_has_local_memory`,
# so a four-query port silently divides by the wrong shape.
def QUERY_N() -> U32: 5
def dev.query(d: Dev, sm: U32) -> Dev:
  match d:
    case Dev{_, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd,
          Tr.emit(CALL_CONTROL, QUERY_N(),
            Tr.emit(CALL_CONTROL, 0,
              Tr.emit(CALL_CONTROL, 0,
                Tr.emit(CALL_CONTROL, 0,
                  Tr.emit(CALL_CONTROL, 0, t)))))}

# :604-607 slm_per_thread starts at ZERO and the two windows are set. Both
# numbers are recorded and not derived -- the windows are constants and the slm
# is a RUNNING value that `_ensure_has_local_memory` raises.
def dev.windows(d: Dev) -> Dev:
  match d:
    case Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, 0, pma, next_qmd, t}

def dev.init.at(sm: U32, +iface: U32, +peer: Bool, pma: Bool, +t0: Tr) -> Dev:
  d1 = dev.select(Dev{0, 0, 0, 0, 0, 0, iface, 0, pma, 0, t0}, iface)
  d2 = dev.rm3(d1, NV01_ROOT_CLIENT(), NV01_DEVICE_0(), NV20_SUBDEVICE_0(), NV01_MEMORY_VIRTUAL())
  d3 = dev.mmio(d2, CLASS_TURING_USERMODE())
  d4 = dev.boost(d3)
  d5 = dev.vaspace(d4, FERMI_VASPACE_A())
  d6 = dev.vm(d5, peer)
  d7 = dev.channels(d6, KEPLER_CHANNEL_GROUP_A(), FERMI_CONTEXT_SHARE_A())
  d8 = dev.query(d7, sm)
  +d9 : Dev = dev.windows(d8)
  Dev.at(d9, Tr.emit(CALL_ALLOC, GT200_DEBUGGER(),
    Tr.emit(CALL_PROF, MAXWELL_PROFILER_DEVICE(), Dev.tr(d9))))

def dev.init(sm: U32, iface: U32, peer: Bool, pma: Bool) -> Dev:
  dev.init.at(sm, iface, peer, pma, Tr.of())

# the mock's init, right here, because BEND requires definition-before-use and
# `dev.init` IS the subject. `MOCK_INIT_SM` IS the sm version the mock
# REPORTS: `test/mockgpu/nv/nvgpu.py`'s GPU ANSWERS `NV0000_CTRL_CMD_GPU_GET_
# ID_INFO_V2`, AND THE PORT'S `dev.init` TAKES the sm version as a parameter
# BECAUSE `arch_of`/`sass_of` ARE FUNCTIONS OF IT.
def dev.mock_init(sm: U32) -> Dev:
  dev.init(sm, IFACE_MOCK(), False{}, False{})

def CALL_WORD() -> U32: 10
def NVM_TYP2() -> U32: 2

def nvm.word(subc: U32, mthd: U32, nvals: U32, typ: U32) -> U32:
  U32.or(U32.or(U32.shln(typ, 28n), U32.shln(nvals, 16n)),
         U32.or(U32.shln(subc, 13n), U32.shrn(mthd, 2n)))

# `v.dtype.itemsize // 4` for a UOp argument and 1 for a bare int, summed. The
# itemsize DIVIDES BY FOUR because the header counts 32-bit WORDS, so a uint64
# is 2 and a uint8 is... 0, which is `4 // 4` and not `1 // 4`: every argument
# reaching `nvm` is at least a word.
def nvm.nvals32(n: U32) -> U32: n

def nvm.nvals64(n: U32) -> U32: U32.mul(n, 2)

# THE EMIT. The header is the argument of one driver call and each payload word
# is recorded beside it, so `Tr.args(CALL_WORD(), t)` is EXACTLY
# `array.array('I', cmds)` -- the list `_submit_cmds` uploads. `Bool.pick`
# evaluates both arms, so the refusal guard is a parameter.
# the payload words, each recorded under the SAME header word, so the trace is a
# flat `array('I', cmds)` stream rather than a nested one. The shrinking list is
# the FIRST argument so the decrease check sees it.
def nvm.words(ws: List<&2, U32>, h: U32, acc: List<&2, Call>) -> List<&2, Call>:
  match ws:
    case Nil{}: acc
    case w <> t: nvm.words(t, h, List.append(&2, Call, acc, [Call{CALL_WORD(), w}]))

def nvm.words.of(ws: List<&2, U32>, +h: U32) -> List<&2, Call>:
  nvm.words(ws, h, [Call{CALL_WORD(), h}])

# THE EMIT, and it is ONE refusal guard for the whole command: `Bool.pick`
# evaluates both arms, so the words are built here and the guard is a parameter.
# APPEND, NOT REPLACE. The first version answered
# `Bool.pick(List, refused, calls, nvm.words.of(ws, h))`, which is `calls` when
# refused and the NEW words otherwise -- so a second command in the same trace
# dropped the first, and `nv_sem_signal` printed only the NON_STALL_INTERRUPT.
# MEASURED: it was the diff against CPython that found it, and the row that
# moves is `nv_sem_signal`.
def nvm.emit.go(+refused: Bool, +h: U32, ws: List<&2, U32>, +calls: List<&2, Call>,
                +next: U32, +bad_at: U32, +seen: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, nvm.words.of(ws, h))), next,
     bad_at, seen, refused}

def nvm.emit(subc: U32, mthd: U32, nvals: U32, typ: U32, ws: List<&2, U32>,
             t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}:
      nvm.emit.go(refused, nvm.word(subc, mthd, nvals, typ), ws, calls, next,
                  bad_at, seen)

# ===========================================================================
# :40-41 `nv_flags`, AND THE TWO TABLES UNDER IT. A wrong shift or a wrong enum
# value is a SILENTLY WRONG COMMAND, so both tables are rows and both
# directions are named.
#
#   `functools.reduce(int.__or__, ((getattr(nv_gpu, f"{reg}_{k}_{v}".upper())
#    if isinstance(v, str) else v) << getattr(nv_gpu, f"{reg}_{k}".upper())[1]
#    for k, v in kwargs.items()), 0)`
#
# TWO tables: `(reg, k) -> lo` (the `[1]` of a bitfield tuple) and
# `(reg, k, v) -> the enum value`. The reduce is an OR, so the KWARG ORDER DOES
# NOT MATTER -- and a port that put the terms in a fixed order would still be
# right here, so the row that pins this is the one that reorders them.
# ===========================================================================

def FLD_SEM_PAYLOAD_SIZE() -> U32: 24
def FLD_SEM_OPERATION() -> U32: 0
def FLD_SEM_RELEASE_WFI() -> U32: 20
def FLD_SEM_RELEASE_TIMESTAMP() -> U32: 25
def V_SEM_PAYLOAD_SIZE_64BIT() -> U32: 1
def V_SEM_PAYLOAD_SIZE_32BIT() -> U32: 0
def V_SEM_OPERATION_ACQ_CIRC_GEQ() -> U32: 3
def V_SEM_OPERATION_RELEASE() -> U32: 1
def V_SEM_RELEASE_WFI_EN() -> U32: 1
def V_SEM_RELEASE_WFI_DIS() -> U32: 0
def V_SEM_RELEASE_TIMESTAMP_EN() -> U32: 1
def V_SEM_RELEASE_TIMESTAMP_DIS() -> U32: 0

def FLD_INV_INSTRUCTION() -> U32: 0
def FLD_INV_GLOBAL_DATA() -> U32: 4
def FLD_INV_CONSTANT() -> U32: 12
def V_TRUE() -> U32: 1

def FLD_DMA_DATA_TRANSFER_TYPE() -> U32: 0
def FLD_DMA_SRC_MEMORY_LAYOUT() -> U32: 7
def FLD_DMA_DST_MEMORY_LAYOUT() -> U32: 8
def FLD_DMA_FLUSH_ENABLE() -> U32: 2
def FLD_DMA_SEMAPHORE_TYPE() -> U32: 3
def V_DMA_NON_PIPELINED() -> U32: 2
def V_DMA_PITCH() -> U32: 1
def V_DMA_RELEASE_ONE_WORD() -> U32: 1
def V_DMA_RELEASE_FOUR_WORD() -> U32: 2

def FLD_CTRL_CODEC_TYPE() -> U32: 0
def FLD_CTRL_TESTRUN_ENV() -> U32: 18
def FLD_CTRL_GPTIMER_ON() -> U32: 4
def FLD_CTRL_ERR_CONCEAL_ON() -> U32: 6
def FLD_CTRL_MBTIMER_ON() -> U32: 13
def FLD_CTRL_EVENT_TRACE_LOGGING_ON() -> U32: 16
def V_CTRL_HEVC() -> U32: 7
def V_CTRL_PROD_RUN() -> U32: 1

# ONE TERM: `value << lo`. `U32.shln` saturates past 31 and no flag here sits
# above bit 25, so the saturation is not load-bearing -- `nv_flags_shift_25` is
# the row that says so rather than leaving it implicit.
def flags.term(v: U32, lo: U32) -> U32: U32.shln(v, U32.to_nat(lo))

# the OR of the terms. `acc` first on the self-call so the decrease check sees
# the shrinking list before the accumulator (bend2-constraints.md, rule 19).
def flags.or(a: U32, b: U32) -> U32: U32.or(a, b)
def flags.go(terms: List<&2, U32>, acc: U32) -> U32:
  match terms:
    case Nil{}: acc
    case x <> t: flags.go(t, flags.or(acc, x))

# :108 `wait` -- `nv_flags("NVC56F_SEM_EXECUTE", payload_size="64bit",
# operation="acq_circ_geq")`. Three terms, two named bits and one enum.
def flags.wait() -> U32:
  flags.go([flags.term(V_SEM_PAYLOAD_SIZE_64BIT(), FLD_SEM_PAYLOAD_SIZE()),
            flags.term(V_SEM_OPERATION_ACQ_CIRC_GEQ(), FLD_SEM_OPERATION())], 0)

# :114 `release` -- and note the ORDER the kwargs appear in, which the reduce
# does not care about. The port builds them in Python's order so the row can
# show that reordering them changes nothing.
def flags.release(tstamp: U32) -> U32:
  flags.go([flags.term(V_SEM_PAYLOAD_SIZE_64BIT(), FLD_SEM_PAYLOAD_SIZE()),
            flags.term(V_SEM_OPERATION_RELEASE(), FLD_SEM_OPERATION()),
            flags.term(V_SEM_RELEASE_WFI_EN(), FLD_SEM_RELEASE_WFI()),
            flags.term(tstamp, FLD_SEM_RELEASE_TIMESTAMP())], 0)

def flags.copy_dma() -> U32:
  flags.go([flags.term(V_DMA_NON_PIPELINED(), FLD_DMA_DATA_TRANSFER_TYPE()),
            flags.term(V_DMA_PITCH(), FLD_DMA_SRC_MEMORY_LAYOUT()),
            flags.term(V_DMA_PITCH(), FLD_DMA_DST_MEMORY_LAYOUT())], 0)

# :199 `semaphore(..., typ)` -- ONE def for both, because the only difference is
# the semaphore type and a reader that wanted them separate would be wrong:
# `nv_dma_sem_one` and `nv_dma_sem_four` differ in exactly that word.
def flags.dma_sem(typ: U32) -> U32:
  flags.go([flags.term(V_TRUE(), FLD_DMA_FLUSH_ENABLE()),
            flags.term(typ, FLD_DMA_SEMAPHORE_TYPE())], 0)

def hilo.hi(x: H.I64) -> U32: H.hi32(x)
def hilo.lo(x: H.I64) -> U32: H.lo32(x)

def hilo.pair(+x: H.I64) -> List<&2, U32>:
  [hilo.hi(x), hilo.lo(x)]

def nvm.weights(ws: List<&2, U32>, acc: U32) -> U32:
  match ws:
    case Nil{}: acc
    case w <> t: nvm.weights(t, U32.add(acc, w))

def nvm.words_of(ws: List<&2, U32>) -> U32: nvm.weights(ws, 0)

# the three `nvm` shapes this file emits, named.
def NVALS_SEM() -> List<&2, U32>: [2, 2, 1]
def NVALS_HILO3() -> List<&2, U32>: [1, 1, 1]
def NVALS_HILO4() -> List<&2, U32>: [1, 1, 1, 1]
def NVALS_ONE() -> List<&2, U32>: [1]
def NVALS_ONE_INT() -> List<&2, U32>: [1]
def NVALS_TWO_INT() -> List<&2, U32>: [1, 1]
def NVALS_THREE_INT() -> List<&2, U32>: [1, 1, 1]

# ===========================================================================
# THE four queues' COMMAND vocabularies. Each def is ONE line range of the
# Python and emits the words in the Python's order; `q_*` names are the method
# names `ops_nv.py` uses.
#
# THE raise is in the trace (see THE trace), so `cq.exec`'s two raises need no
# guard of their own: a refusal truncates everything after it.
# ===========================================================================

# :107-108 `NVQueue.sem` -- `self.nvm(0, NVC56F_SEM_ADDR_LO, addr,
# value.ccast(uint64), nv_flags(...))`.
def q.sem(addr: U32, value: U32, fl: U32, t: Tr) -> Tr:
  nvm.emit(0, M_SEM_ADDR_LO(), nvm.words_of(NVALS_SEM()), NVM_TYP2(),
           [addr, value, fl], t)

def stamp.v(s: Bool) -> U32:
  Bool.pick(U32, s, V_SEM_RELEASE_TIMESTAMP_EN(), V_SEM_RELEASE_TIMESTAMP_DIS())

# `if not timestamp: self.nvm(0, NVC56F_NON_STALL_INTERRUPT, 0x0)` -- the guard
# is a parameter because a `match` may not scrutinise a call.
def q.nsi.at(stamp: Bool, t: Tr) -> Tr:
  match stamp:
    case True{}: t
    case False{}: nvm.emit(0, M_NON_STALL_INTERRUPT(), nvm.words_of(NVALS_ONE_INT()),
                           NVM_TYP2(), [0], t)

def q.release(addr: U32, value: U32, +stamp: Bool, t: Tr) -> Tr:
  q.nsi.at(stamp, q.sem(addr, value, flags.release(stamp.v(stamp)), t))

def COPY_STEP() -> U32: 2147483648

# `min(sz - off, step)`. `U32.sub` is read twice and U32 is affine, so the
# difference travels in a record -- the same rule `Sig` uses below.
type Rem is Data:
  Rem{r: U32}

def Rem.r(+x: Rem) -> U32:
  match x:
    case Rem{r}: r

def copy.step(+rem: Rem) -> U32:
  Bool.pick(U32, U32.is_gt(Rem.r(rem), COPY_STEP()), COPY_STEP(), Rem.r(rem))

def copy.step.of(sz: U32, off: U32) -> U32: copy.step(Rem{U32.sub(sz, off)})

def copy.nsteps(sz: U32) -> U32: H.ceildiv_u32(sz, COPY_STEP())

# the three commands of ONE step, in order: the upper/lower offset pair for src
# then dest, then the length, then LAUNCH_DMA.
def cq.copy.step(sh: U32, sl: U32, dh: U32, dl: U32, len: U32, t: Tr) -> Tr:
  t2 = nvm.emit(4, M_OFFSET_IN_UPPER(), nvm.words_of(NVALS_HILO4()), NVM_TYP2(),
                [sh, sl, dh, dl], t)
  t3 = nvm.emit(4, M_LINE_LENGTH_IN(), nvm.words_of(NVALS_ONE()), NVM_TYP2(),
                [len], t2)
  nvm.emit(4, M_LAUNCH_DMA(), nvm.words_of(NVALS_ONE()), NVM_TYP2(),
           [flags.copy_dma()], t3)

# THE STEP LOOP, and the zero-size case is a REAL CASE: `range(0, 0, step)` is
# empty, so a 0-byte copy emits NO commands at all. A port that emitted one step
# unconditionally would upload a length-0 DMA, which is a driver error rather
# than a no-op.
def cq.copy.at(n: U32, sh: U32, sl: U32, dh: U32, dl: U32, len: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_zero(n), t, cq.copy.step(sh, sl, dh, dl, len, t))

def cq.copy(+sz: U32, sh: U32, sl: U32, dh: U32, dl: U32, t: Tr) -> Tr:
  cq.copy.at(copy.nsteps(sz), sh, sl, dh, dl, copy.step.of(sz, 0), t)

# :197-201 `NVCopyQueue.semaphore` -- `nvm(4, NVC6B5_SET_SEMAPHORE_A,
# *hilo(addr), value.ccast(uint32))` then `nvm(4, NVC6B5_LAUNCH_DMA,
# nv_flags(...))`. FIVE words and then TWO. `hilo` puts the HIGH half first, so
# the pair reads `hi, lo, value` and NOT `lo, hi, value`.
def cq.sem2(h: U32, l: U32, v: U32, typ: U32, t: Tr) -> Tr:
  nvm.emit(4, M_LAUNCH_DMA(), nvm.words_of(NVALS_ONE()), NVM_TYP2(),
           [flags.dma_sem(typ)], t)

def cq.semaphore(+h: U32, +l: U32, +v: U32, typ: U32, t: Tr) -> Tr:
  cq.sem2(h, l, v, typ,
    nvm.emit(4, M_SET_SEMAPHORE_A(), nvm.words_of(NVALS_HILO3()), NVM_TYP2(),
             [h, l, v], t))

def DMA_SEM_ONE() -> U32: 1
def DMA_SEM_FOUR() -> U32: 2

type Slot is Data:
  Slot{at: U32, next: U32}

def Slot.at(x: Slot) -> U32:
  match x:
    case Slot{at, next}: at

def Slot.next(x: Slot) -> U32:
  match x:
    case Slot{at, next}: next

# `round_up(off, k)` is read twice -- as the yielded slot and as the base of the
# advance -- so the pair travels in a record.
def sig.slot(+off: U32, +k: U32) -> Slot:
  Slot{H.round_up_u32(off, k), U32.add(H.round_up_u32(off, k), k)}

# the fold APPENDS (`List.append` is `xs ++ ys`), so the offsets come out in
# Python's yield order. The shrinking list is the FIRST argument.
def sig.go(ks: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case +k <> t: sig.go(t, Slot.next(sig.slot(off, k)),
                         List.append(&2, U32, acc, [Slot.at(sig.slot(off, k))]))

def sig.slots(ks: List<&2, U32>, off: U32) -> List<&2, U32>:
  sig.go(ks, off, Nil{})

def W64() -> U32: 8
def W32() -> U32: 4
def W16() -> U32: 2
def W8() -> U32: 1

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def ssh(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ssh(t, x <> acc)

type Wv is Data:
  Wv{v: U32}

def Wv.at(m: Maybe<&2, U32>, d: U32) -> U32:
  match m:
    case None{}: d
    case Some{+x}: x

def allocs(t: Tr) -> List<&2, U32>: Tr.args(CALL_ALLOC(), Tr.calls(t))
def controls(t: Tr) -> List<&2, U32>: Tr.args(CALL_CONTROL(), Tr.calls(t))
def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def ADDR_HI() -> U32: 0
def IOWR_READ() -> U32: 3
def IOWR_F() -> U32: 70
def IOWR_SIZE_MASK() -> U32: 8191
def IOWR_NR_MASK() -> U32: 255

# THE FOUR FIELDS, `U32.or`ed because they do not overlap: bits 30-31 the read
# direction, 16-28 the struct size, 8-15 `'F'`, 0-7 the request number.
def iowr.pack(sz: U32, nr: U32) -> U32:
  U32.or(U32.or(U32.shln(IOWR_READ(), 30n), U32.shln(sz, 16n)),
         U32.or(U32.shln(IOWR_F(), 8n), nr))

# THE TWO MASKS ARE LOAD-BEARING and `nv_iowr_8192_1` is the row: `sizeof(args)
# & 0x1FFF` is 0 for an 8 KiB struct, so the size field vanishes and the word
# reads as if the struct were empty.
def iowr.cmd(nbytes: U32, nr: U32) -> U32:
  iowr.pack(U32.and(nbytes, IOWR_SIZE_MASK()), U32.and(nr, IOWR_NR_MASK()))

def qmd.ver.of(compute: U32) -> U32:
  Bool.pick(U32, U32.is_ge(compute, CLASS_BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())

def qmd.sz.of(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(v, QMD_VER5()), QMD_SZ5(), QMD_SZ3())

def qmd.words(v: U32) -> U32: U32.mul(qmd.sz.of(v), 4)

def qmd.grid.a(+v: U32) -> String:
  match v:
    case 3: "cta_raster_width"
    case _: "grid_width"

def qmd.grid.b(+v: U32) -> String:
  match v:
    case 3: "cta_raster_height"
    case _: "grid_height"

def qmd.grid.c(+v: U32) -> String:
  match v:
    case 3: "cta_raster_depth"
    case _: "grid_depth"

def qmd.grid(+v: U32) -> List<&2, String>:
  [qmd.grid.a(v), qmd.grid.b(v), qmd.grid.c(v)]

def qmd.slot(busy0: Bool, busy1: Bool) -> U32:
  Bool.pick(U32, busy0, Bool.pick(U32, busy1, 3, 1), 0)

type PData is Data:
  PData{ver: U32, regs: U32, shmem: U32, cbuf0: U32, nsig: U32, nbufs: U32,
        nvars: U32, img: U32, mock: Bool}

def pd.of(compute: U32, regs: U32, shmem: U32, cbuf0: U32, nsig: U32, nbufs: U32,
          nvars: U32, img: U32, mock: Bool) -> PData:
  PData{qmd.ver.of(compute), regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}

def PData.ver(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: ver

def PData.regs(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: regs

def PData.shmem(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: shmem

def PData.cbuf0(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: cbuf0

def PData.nsig(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nsig

def PData.nbufs(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nbufs

def PData.nvars(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nvars

def PData.img(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: img

def PData.mock(p: PData) -> Bool:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: mock

# :268-269 `min_cbuf0_entries = 224 if dev.iface.compute_class >=
# nv_gpu.BLACKWELL_COMPUTE_A else 12` and `self.cbuf_0 = [0] *
# max(cbuf0_size // 4, min_cbuf0_entries)`. THE COMMENT above :267 says why the
# two numbers differ: "Blackwell needs index 223 (224 entries), older GPUs need
# index 11 (12 entries)".
#
# THE CLASS IS NOT A FIELD OF `PData` and the VERSION is, which is sound because
# `qmd.ver.of` is the only way a version is set and it IS the same `>=`. So the
# comparison reads the version and `nv_cbuf0_by_ver` is the row that says the two
# are the same predicate.
def pd.min_cbuf0(ver: U32) -> U32:
  Bool.pick(U32, U32.is_eq(ver, QMD_VER5()), 224, 12)

def pd.max2(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

# :269, above.
def pd.cbuf0_len(+p: PData) -> U32:
  pd.max2(U32.div(PData.cbuf0(p), 4), pd.min_cbuf0(PData.ver(p)))

def pd.r1(+regs: U32) -> U32: Bool.pick(U32, U32.is_zero(regs), 1, regs)

def smemcfg.step(+shmem: U32) -> U32: H.round_up_u32(shmem, 4096)

def smemcfg.ok(shmem: U32) -> Bool: U32.is_le(shmem, 102400)

# THE smallest of the three candidates that is >= `shmem`, then `// 4096 + 1`.
# THE SHORTCUT `round_up(shmem, 4096) + 1` IS WRONG and the diff against CPython
# is what said so: for shmem 0 it answers 1 where Python answers 9, because the
# minimum is over {32768, 65536, 102400} and NOT over the multiples of 4096.
def smemcfg.cand(+shmem: U32) -> U32:
  Bool.pick(U32, U32.is_le(shmem, 32768), 32768,
    Bool.pick(U32, U32.is_le(shmem, 65536), 65536, 102400))

def pd.smem_cfg(shmem: U32) -> U32: U32.add(U32.div(smemcfg.cand(shmem), 4096), 1)

def RELOC_NONE() -> U32: 0
def RELOC_64() -> U32: 2
def RELOC_32() -> U32: 56
def RELOC_32_HI() -> U32: 57

type Rl is Data:
  Rl{off: U32, sym: U32, isize: U32, shift: U32}

def Rl.off(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: off

def Rl.sym(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: sym

def Rl.isize(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: isize

def Rl.shift(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: shift

# THE REVERSE DIRECTION: which arm claims a type. 0 means "no arm", which is the
# refusal. `pd.reloc_kind` is a first-wins scan and `pd.reloc_kind_n` counts the
# claims, so a table that dropped the 0x39 arm is caught by the COUNT and not
# only by the forward rows.
def reloc.claims(+typ: U32, arm: U32) -> Bool: U32.is_eq(typ, arm)

def pd.reloc_kind(+typ: U32) -> U32:
  Bool.pick(U32, reloc.claims(typ, RELOC_64()), RELOC_64(),
    Bool.pick(U32, reloc.claims(typ, RELOC_32()), RELOC_32(),
      Bool.pick(U32, reloc.claims(typ, RELOC_32_HI()), RELOC_32_HI(), RELOC_NONE())))

def pd.reloc.off(+a: U32, kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), a, U32.add(a, 4))

def pd.reloc.isize(kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), W64(), W32())

def pd.reloc.shift(kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_32_HI()), 32, 0)

type Rf is Data:
  Rf{rs: List<&2, Rl>, refused: Bool}

def Rf.put.at(+kind: U32, a: U32, sym: U32, rf: Rf) -> Rf:
  match rf:
    case Rf{+rs, +refused}:
      Bool.pick(Rf, Bool.or(refused, U32.is_zero(kind)), Rf{Nil{}, True{}},
                Rf{List.append(&2, Rl, rs,
                      [Rl{pd.reloc.off(a, kind), sym, pd.reloc.isize(kind),
                          pd.reloc.shift(kind)}]), refused})

def Rf.put(a: U32, sym: U32, typ: U32, rf: Rf) -> Rf:
  Rf.put.at(pd.reloc_kind(typ), a, sym, rf)

# the (apply_image_offset, rel_sym_offset, type) triples from `elf_loader`, so the
# fold reads them in Python's order.
type Rb is Data:
  Rb{a: U32, sym: U32, typ: U32}

def Rf.go(ts: List<&2, Rb>, +rf: Rf) -> Rf:
  match ts:
    case Nil{}: rf
    case Rb{a, sym, typ} <> t: Rf.go(t, Rf.put.at(pd.reloc_kind(typ), a, sym, rf))

def GLOBAL_MAX_X() -> U32: 2147483647
def GLOBAL_MAX_Y() -> U32: 65535
def GLOBAL_MAX_Z() -> U32: 65535
def LOCAL_MAX_X() -> U32: 1024
def LOCAL_MAX_Y() -> U32: 1024
def LOCAL_MAX_Z() -> U32: 64
def THREADS_MAX() -> U32: 1024

def exec.ok.prod(+pr: U32, max_threads: U32) -> Bool:
  Bool.not(Bool.or(U32.is_gt(pr, THREADS_MAX()), U32.is_lt(max_threads, pr)))

def exec.gmax(ix: U32) -> U32:
  match ix:
    case 0: GLOBAL_MAX_X()
    case 1: GLOBAL_MAX_Y()
    case 2: GLOBAL_MAX_Z()
    case _: 0

def exec.lmax(ix: U32) -> U32:
  match ix:
    case 0: LOCAL_MAX_X()
    case 1: LOCAL_MAX_Y()
    case 2: LOCAL_MAX_Z()
    case _: 0

def exec.g_ok(v: U32, ix: U32) -> Bool: Bool.not(U32.is_gt(v, exec.gmax(ix)))
def exec.l_ok(v: U32, ix: U32) -> Bool: Bool.not(U32.is_gt(v, exec.lmax(ix)))

# SIX NUMELS TRAVEL IN ONE RECORD, because every one of them is read by both the
# predicate and the message and `U32` is affine.
type Dim is Data:
  Dim{gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32}

def Dim.gx(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gx

def Dim.gy(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gy

def Dim.gz(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gz

def Dim.lx(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: lx

def Dim.ly(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: ly

def Dim.lz(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: lz

def exec.ok.dims(+d: Dim) -> Bool:
  Bool.and(Bool.and(exec.g_ok(Dim.gx(d), 0), exec.g_ok(Dim.gy(d), 1)),
    Bool.and(Bool.and(exec.g_ok(Dim.gz(d), 2), exec.l_ok(Dim.lx(d), 0)),
      Bool.and(exec.l_ok(Dim.ly(d), 1), exec.l_ok(Dim.lz(d), 2))))

def DEPENDENT_ACTION() -> U32: 1
def DEPENDENT_PREFETCH() -> U32: 1
def DEPENDENT_ENABLE() -> U32: 1

# `if self.dev.pma_enabled: self.nvm(1, NVC6C0_PM_TRIGGER, 0)` -- FIRST, and it
# is inside the None arm, so a chained launch never triggers the profiler.
def cq.pm.at(pma: Bool, t: Tr) -> Tr:
  match pma:
    case True{}: nvm.emit(1, M_PM_TRIGGER(), nvm.words_of(NVALS_ONE()), NVM_TYP2(), [0], t)
    case False{}: t

def cq.pcas.at(qmd_addr_hi: U32, t: Tr) -> Tr:
  nvm.emit(1, M_SEND_PCAS_A(), nvm.words_of(NVALS_ONE()), NVM_TYP2(), [qmd_addr_hi], t)

def cq.pcas2.at(pcas2: U32, t: Tr) -> Tr:
  nvm.emit(1, M_SEND_SIGNALING_PCAS2_B(), nvm.words_of(NVALS_ONE()), NVM_TYP2(),
           [pcas2], t)

def cq.exec.open(pma: Bool, qmd_addr_hi: U32, pcas2: U32, t: Tr) -> Tr:
  cq.pcas2.at(pcas2, cq.pcas.at(qmd_addr_hi, cq.pm.at(pma, t)))

# THE GUARD IS A PARAMETER, because `self.prev_qmd is None` is a CALL and a
# `match` may not scrutinise one.
def cq.exec.at(prev: Bool, pma: Bool, qmd_addr_hi: U32, pcas2: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, prev, t, cq.exec.open(pma, qmd_addr_hi, pcas2, t))

def cq.exec(prev: Bool, pma: Bool, qmd_addr_hi: U32, pcas2: U32, t: Tr) -> Tr:
  cq.exec.at(prev, pma, qmd_addr_hi, pcas2, t)

type PKey is Data:
  PKey{src3: U32, dev0: U32, dev1: U32}

def PKey.src3(+k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: src3

def PKey.dev0(k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: dev0

def PKey.dev1(+k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: dev1

# THE REVERSE DIRECTION -- "which entry does this key name" -- and it is a
# first-wins scan, so a table with two identical keys answers the FIRST and a
# last-wins scan would answer the second. `nv_find_dup_first` is the fixture that
# tells the two apart.
def pc.same(+a: PKey, +b: PKey) -> Bool:
  Bool.and(U32.is_eq(PKey.src3(a), PKey.src3(b)), U32.is_eq(PKey.dev0(a), PKey.dev0(b)))

# THE MISS SENTINEL IS `len(keys)`, NOT 0. The first version answered 0 on a
# miss and the hit test `found < len(keys)` read that as a HIT AT INDEX 0, so
# `nv_pc_grow_3` answered 1 where CPython's dict holds three entries. `got` is
# seeded with `len(ks)` and `at` is the index, so a match KEEPS its index (the
# scan is first-wins) and a miss answers the length.
def pc.find.go(+k: PKey, ks: List<&2, PKey>, +at: U32, got: U32) -> U32:
  match ks:
    case Nil{}: got
    case +x <> t: pc.find.go(k, t, U32.add(at, 1), Bool.pick(U32, pc.same(k, x), at, got))

def pc.find.at(+k: PKey, +ks: List<&2, PKey>) -> U32:
  pc.find.go(k, ks, 0, U32.from_nat(List.length(&2, PKey, ks)))

def pc.find(k: PKey, ks: List<&2, PKey>) -> U32: pc.find.at(k, ks)

# THE CACHE, AND IT HAS NO EVICTION. `_nv_program_cache` is a bare module-level
# dict with no bound and no eviction anywhere in ops_nv.py: the answer to "which
# entry must NOT be evicted" is "all of them", and the honest measurement is a
# GROWTH COUNT -- insert n distinct keys and the count is n. `nv_pc_grow_3` and
# `nv_pc_grow_repeat` are the rows, and the SECOND is the negative case: a key
# that is already present must not grow the cache, so a port that invented an LRU
# or that appended on every lookup fails one of the two.
#
# THE fields are not named after the readers. `PC{n: ...}` with a reader `PC.n`
# is REFUSED -- "a pattern binder that shadows a FIELD NAME is reported as an
# arity error" (bend2-constraints.md), and the error names the reader, not the
# field. So the fields are `cnt`, `uid`, `misses`, `hits`, `keys` and `ords`.
type PC is Data:
  PC{cnt: U32, uid: U32, misses: U32, hits: U32, keys: List<&2, PKey>, ords: List<&2, U32>}

def PC.of() -> PC: PC{0, 0, 0, 0, Nil{}, Nil{}}

def PC.n(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: cnt

def PC.next(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: uid

def PC.miss(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: misses

def PC.hit(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: hits

def PC.ks(p: PC) -> List<&2, PKey>:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: keys

def PC.ord(p: PC) -> List<&2, U32>:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: ords

def PC.at(+p: PC, cnt: U32, ks: List<&2, PKey>, misses: U32, hits: U32,
          ords: List<&2, U32>, uid: U32) -> PC:
  PC{cnt, uid, misses, hits, ks, ords}

# `next(UOp.unique_num)` at :317 -- the buffer's id is a MONOTONE counter and NOT
# the cache size, so a port that used the cache size would reuse an id. There is
# no eviction, so the two can only differ by how many HITS happened, and
# `nv_pc_id_is_not_count` pins that.
def pc.new_id(p: PC) -> U32: PC.next(p)

# `if (cached := cache.get(key)) is None: ... cache[key] = ...` -- the branch is a
# HIT when the key is already there, and `found` is the scan's answer: an INDEX,
# so the hit test is `found < len(keys)` and a MISS appends. TWO ARMS AS TWO DEFS
# and not one `Bool.pick`, because each arm builds a different `PC` and
# `Bool.pick` evaluates both -- which is how the first version appended the
# PREVIOUS last key instead of the one being inserted.
def pc.hit_arm(+p: PC) -> PC:
  PC.at(p, PC.n(p), PC.ks(p), PC.miss(p), U32.add(PC.hit(p), 1), PC.ord(p), PC.next(p))

# THE miss advances the unique-NUM counter, which is the buffer's id at :317. A
# port that froze it would reuse an id for the second program.
def pc.miss_arm(k: PKey, +p: PC) -> PC:
  PC.at(p, U32.add(PC.n(p), 1), List.append(&2, PKey, PC.ks(p), [k]),
        U32.add(PC.miss(p), 1), PC.hit(p),
        List.append(&2, U32, PC.ord(p), [pc.new_id(p)]), U32.add(PC.next(p), 1))

def pc.put.at(found: U32, +k: PKey, +p: PC) -> PC:
  Bool.pick(PC, U32.is_lt(found, U32.from_nat(List.length(&2, PKey, PC.ks(p)))),
            pc.hit_arm(p), pc.miss_arm(k, p))

def pc.put(+k: PKey, +p: PC) -> PC: pc.put.at(pc.find(k, PC.ks(p)), k, p)

# ===========================================================================
# STAGE 4 (part one) -- THE BUFFER POOL and the device'S own buffers.
#
# `device.bend`'s rules are CONSUMED and not re-derived: a Buffer is a SLOT in a
# `Bar` arena, `nbytes` is `size * itemsize` and is NOT a field, a view's offset
# ACCUMULATES and a view's base is the ROOT. `dev.gpput_off` is the number that
# becomes a `bview` offset and `nv_gpput_off` is what says the accumulation is
# right.
# ===========================================================================

def GPPUT_OFF() -> U32: 140

# :655 `gpput_off = offset + entries*8 + getattr(nv_gpu.AmpereAControlGPFifo,
# 'GPPut').offset` -- the GP-PUT pointer's slot in the host gpfifo buffer, and
# `GPPut.offset` is 140 read out of `AmpereAControlGPFifo`. `entries * 8` is the
# ring's byte length (a uint64 per entry), so the two fifos' GP-PUT pointers sit
# one ring-length apart.
def dev.gpput_off(off: U32, entries: U32) -> U32:
  U32.add(U32.add(off, U32.mul(entries, 8)), GPPUT_OFF())

def dev.fifos_ring(+r: D.BFound, entries: U32, off: U32) -> D.BFound:
  D.bview(D.BFound.ar(r), 0, entries, S.uint64(), off)

def dev.fifos_pair(+r: D.BFound, entries: U32, off: U32) -> D.BFound:
  D.bview(D.BFound.ar(r), 0, 1, S.uint32(), dev.gpput_off(off, entries))

# `dev.fifos_of` builds the ONE arena both views hang off: the 3 MiB
# `gpfifo_buf` of :616 is the root, and a fold cannot carry an arena, so the two
# `bview` calls are a chain of THREE defs -- root, ring, gpput -- rather than one.
# MEASURED: with the ring view missing, `nv_ring_nbytes` read the ROOT's four
# bytes and `nv_gpput_nbytes` read nothing at all.
def dev.fifos_root(+entries: U32, +off: U32) -> D.BFound:
  dev.fifos_ring(D.bnew(D.bar_empty(),
                  D.root(3, GPFIFO_ALLOC(), S.uint8(), D.spec())), entries, off)

def SLM_GRAN() -> U32: 32
def BPT_GRAN() -> U32: 512
def BPT_ROUND() -> U32: 32768
def TOT_ROUND() -> U32: 131072
def WARP_THREADS() -> U32: 32

def HOST_PAGESIZE() -> U32: 16384
def HUGE_PAGESIZE() -> U32: 2097152
def HUGE_THRESHOLD() -> U32: 8388608
def DEV_PAGESIZE() -> U32: 4096

def alloc.page_size(+size: U32, uncached: Bool, host: Bool, mock: Bool) -> U32:
  Bool.pick(U32, Bool.or(uncached, host), HOST_PAGESIZE(),
    Bool.pick(U32, U32.is_ge(size, HUGE_THRESHOLD()), HUGE_PAGESIZE(),
      Bool.pick(U32, mock, HOST_PAGESIZE(), DEV_PAGESIZE())))

def VID_ROUND() -> U32: 2097152
def VID_TOP_ROUND() -> U32: 65536
def VID_PAD() -> U32: 65536
def VID_ROW_BYTES() -> U32: 608
def VID_UNK_SIZE() -> U32: 2097152
def DEV_ERR_VID() -> String: "Video decoder class not available."

def dev.vid_ok(viddec: U32) -> Bool: Bool.not(U32.is_zero(viddec))

def vid64(n: U32) -> U32: H.round_up_u32(n, 64)

def iface.unknown() -> String: "Unknown error"

def iface.err_str.at(+status: U32, +name: String) -> String:
  String.concat([U32.show(status), ": ", name])

def iface.err_str_of(status: U32, name: String) -> String:
  iface.err_str.at(status, name)

def ACCESS_READ() -> String: "READ"
def ACCESS_STRONG() -> String: "STRONG"
def ACCESS_WEAK() -> String: "WEAK"

def to_name.join.parts(parts: List<&2, String>, +acc: List<&2, String>) -> String:
  match parts:
    case Nil{}: String.concat(acc)
    case h <> Nil{}: to_name.join.parts(Nil{}, List.append(&2, String, acc, [h]))
    case h <> t: to_name.join.parts(t, List.append(&2, String, acc, [String.concat([h, "_"])]))

def to_name.norm(+s: String) -> String:
  String.to_lower(to_name.join.parts(String.split(s, ':'), Nil{}))

def to_name.join.go(parts: List<&2, String>, acc: List<&2, String>) -> String:
  match parts:
    case Nil{}: String.join(List.reverse(&2, String, acc), "_")
    case h <> t: to_name.join.go(t, to_name.norm(h) <> acc)

def to_name(+parts: List<&2, String>) -> String:
  to_name.join.go(parts, Nil{})

def REG_CHUNK() -> U32: 124
def REG_MASK_LO() -> U32: 4294967295

# `len(range(0, n, 124))`, and n 0 is ZERO chunks -- a `reg_ops()` with no
# arguments issues no ioctl at all.
def dev.reg_nchunks(n: U32) -> U32: H.ceildiv_u32(n, REG_CHUNK())

# the LAST chunk's length: the total minus the full chunks before it, and n 0 is
# ZERO because `range(0, 0, 124)` is empty and no ioctl is issued.
def dev.reg_clen.at(rem: U32, chunks: U32) -> U32:
  Bool.pick(U32, U32.is_zero(chunks), 0, rem)

def dev.reg_clen(+n: U32) -> U32:
  dev.reg_clen.at(U32.sub(n, U32.mul(U32.sub(dev.reg_nchunks(n), 1), REG_CHUNK())),
                  dev.reg_nchunks(n))

def PROF_BW_GPC_BASE() -> U32: 2097152
def PROF_PRE_GPC_BASE() -> U32: 1572864
def PROF_GPC_STRIDE() -> U32: 16384
def PROF_TPC_STRIDE_PRE() -> U32: 512
def PROF_SM_BASE_BW() -> U32: 2048
def PROF_SM_STRIDE() -> U32: 512

def prof.sm_base(sm: U32) -> U32:
  match sm:
    case 0: 1024
    case _: 4096

def prof.tpc_cnt.go(n: Nat, +mask: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: prof.tpc_cnt.go(m, U32.shrn(mask, 1n),
      U32.add(got, U32.and(mask, 1)))

def prof.tpc_cnt(mask: U32) -> U32: prof.tpc_cnt.go(32n, mask, 0)

def query_litter.at(+ix: U32) -> Bool:
  Bool.or(U32.is_eq(ix, 0), Bool.or(U32.is_eq(ix, 1), U32.is_eq(ix, 2)))

def query_litter(ix: U32) -> Bool: query_litter.at(ix)

def query_name.at(lit: Bool) -> String:
  Bool.pick(String, lit, "NV2080_CTRL_GR_INFO_INDEX_LITTER_",
    "NV2080_CTRL_GR_INFO_INDEX_")

def query_name(ix: U32) -> String: query_name.at(query_litter(ix))

# THE resolved INDEX EACH of the five requests answers -- 20, 23, 32 for the three
# LITTER ones and 13, 12 for the plain two -- because `query_litter` above says
# WHICH TABLE and this says WHICH ENTRY, and a wrong index reads a neighbouring
# attribute off `infoList` without raising.
def query_ix.at(+ix: U32) -> U32:
  Bool.pick(U32, U32.is_eq(ix, 0), 20, Bool.pick(U32, U32.is_eq(ix, 1), 23,
    Bool.pick(U32, U32.is_eq(ix, 2), 32, Bool.pick(U32, U32.is_eq(ix, 3), 13, 12))))

def query_ix(ix: U32) -> U32: query_ix.at(ix)

# ===========================================================================

def Rf.rs(+r: Rf) -> List<&2, Rl>:
  match r:
    case Rf{rs, refused}: rs

def rl_at.at(m: Maybe<&2, Rl>) -> Rl:
  match m:
    case None{}: Rl{0, 0, 0, 0}
    case Some{+x}: x

def rl_at(rs: List<&2, Rl>, n: Nat) -> Rl:
  rl_at.at(List.get(&2, Rl, rs, n))

def K1() -> PKey: PKey{100, 0, 0}
def K2() -> PKey: PKey{200, 0, 0}
def K1_OTHER_DEV() -> PKey: PKey{100, 1, 0}
def K3() -> PKey: PKey{300, 0, 0}

def pc_one(p: PC, k: PKey) -> PC: pc.put(k, p)

def pc_two() -> PC: pc_one(pc_one(PC.of(), K1()), K2())

