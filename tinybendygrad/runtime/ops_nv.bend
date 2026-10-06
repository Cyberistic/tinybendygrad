# tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py
#
# ===========================================================================
# STAGES. This file is ported in four stages and THIS HEADER SAYS WHERE IT
# STANDS, because a staged file with an accurate header beats a complete one
# that does not compile.
#
#   STAGE 1  LANDED AND CHECKED. the device object, its properties, the buffer
#            and pool ownership rules. Python :559-611 (NVDevice), :322-331
#            (NVAllocator), :613-662 (fifos), :688-697
#            (_ensure_has_local_memory), :449-451 (alloc's page size).
#   STAGE 2  LANDED AND CHECKED. the queue and command-submission structure: the
#            `nvm` word encoding (:47-48), `hilo` (:33), `nv_flags` (:40-41), the
#            `layout_args` kernel-argument trace (hcq2.py:74-76), and the four
#            queues' command vocabularies (:99-225).
#   STAGE 3  LANDED AND CHECKED. the program cache (:313-320 -- the lookup is
#            `pc.find`/`pc.same`, NOT a key reader), the reloc table both ways
#            (:261-265), the image padding and the `NVProgramData` derivations
#            (:230-305), and the launch path's graph-upload/launch trace and two
#            refusals (:161-186).
#   STAGE 4  LANDED AND CHECKED. the QMD version/slot/grid layer (:50-94), the
#            ioctl command encoding (:43-45), the video-HW sizing (:699-715),
#            `to_name` (hcq2.py:63), `reg_ops`'s chunking (:818-824), the
#            profiler register addresses (:793-816), the error-string tables
#            (:35, :37-38) and the GPA-info index fallback (:664-665).
#
# 3960 lines, 630 `def`/`type`, 611 gate rows. `./bin/bend --check-only` prints
# ALL PROOFS CHECK, and `.agents/slop/nv-diff.py` compares the Bend rows against
# CPython rows with **0 disagreements**. The mutation table is at the FOOT and
# every "rows moved" in it is measured, not estimated.
#
# THE 611 ROWS, HONESTLY SPLIT, because "0 disagreements" says nothing about how
# many rows were ever compared to anything:
#
#   543  CROSS-CHECKED. The gate prints a row and the oracle prints the SAME row
#        name computed by CALLING `ops_nv.py` (or `hcq2.py`, or `nv_570.__dict__`)
#        with no GPU, and the differ compares the two STRINGS.
#   56   BEND-ONLY, and the reason is in the name: 19 are the modelled ioctl INIT
#        SEQUENCE (`nv_init_*`) which needs /dev/nvidiactl to run; 12 are this
#        port's own matcher vocabulary (`nv_find_*`, `nv_has_*`) which Python has
#        no equivalent of; 5 are the `device.bend` side of the kernel-argument
#        cross-check (`nv_device_args_*`) -- CPython's side of the same claim is
#        the mirrored `nv_cpython_args_device_*`; 1 is `nv_shift_32`, where the
#        claim is that a Bend `U32` SATURATES and Python's `1 << 32` is
#        4294967296; the rest are trace projections, loop fuel and constants that
#        live in `device.bend`. Every one of them is named for what it ANSWERS
#        rather than for the function that answers it.
#   4    ORACLE-ONLY AND DELIBERATE: `nv_qmd_wide_v3/_v5` and
#        `nv_qmd_straddle_v3/_v5` measure the two GENERATED field tables, which
#        this port does not carry. A Bend row for them would be a constant
#        printing itself.
#
# THE RECONCILIATION COST 73 ROWS THAT LOOKED LIKE COVERAGE AND WERE NOT. Named
# differently on the two sides -- `nv_slmtot_*` against `nv_slm_*`, `nv_toname_*`
# with the parts in the other order -- or printed twice, or present on one side
# only. `nv_query_litter_n` was worse than unmatched: gate and oracle agreed on
# the WRONG ANSWER, because both were hand-written. Only `nv_570.__dict__` knows.
#
# NOT PORTED, AND THE WALL FOR EACH -- all of it is `nv_gpu` driver ioctl
# surface, which in Bend is FFI exactly like `dtype.bend`'s fourteen and which
# makes every IMPORTER of this file print SOME PROOFS FAIL. That is the
# import-closure rule and it is expected; `wgsl.bend` is green only because it
# does not import dtype.
#   TODO(p3) ops_nv.py:353-384  NVKIface.__init__      WALL: /dev/nvidiactl,
#     /dev/nvidia-uvm opens and the three rm_controls that pick the driver
#     version table. `nv_iowr` (:43-45) is PORTED as an ENCODER and the actual
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
#   TODO(p3) ops_nv.py:530-556  PCIIface -- GSP RPC. It inherits NVKIface's
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
#   TODO(p3) ops_nv.py:24 -- BLOCKED. needs `extra.nv_gpu_driver` -- an FFI seam that lives behind the `IOCTL` flag: MEASURED, zero defs anywhere in the port. The conditional `if getenv("IOCTL"):` is the line that keeps the normal import free of it.