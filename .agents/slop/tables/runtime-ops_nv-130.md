<!-- FROM: tinybendygrad/runtime/ops_nv.bend:130 -->
# BLOCK:
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
# END BLOCK
