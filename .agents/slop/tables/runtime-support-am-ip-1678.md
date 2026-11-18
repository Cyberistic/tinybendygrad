<!-- FROM: tinybendygrad/runtime/support/am/ip.bend:1678 -->
# BLOCK:
# THE WALLS. Nothing below is in the port; each is a `raise`, an `ioctl`, a
# register ACCESS, or a Python reflection that Bend has no spelling for.
#
# 1. REGISTER ACCESS. Every `.write(...)` / `.update(...)` / `.read_bitfields()`
#    lands in the register file, and `AMDReg.encode`'s bit POSITIONS are in
#    `autogen/am/regs.py`, PER ARCH. `ops_amd.bend`'s WALL 2 says the same about
#    `regCOMPUTE_*` and `regSQ_THREAD_TRACE_*`, so this file and that one agree on
#    the split: the port carries WHICH register, WHICH field NAMES and in WHICH
#    order, and the offsets are the seam's. `amp_mqd_pqbits_*` is the row that
#    shows the split is real by printing the ENCODED word CPython produces.
# | WALL(p3) runtime/support/am/ip.py:411  AMDReg.encode -> regGRBM_GFX_CNTL. -- BLOCKED: needs `AMDReg.encode` and the `regGRBM_GFX_CNTL` register: `AMDReg`/`encode` are not defs under `am/`. The register WRITE itself is data the header says survives; the ENCODER is not written.
# | WALL(p3) runtime/support/am/ip.py:367  regCP_HQD_PQ_CONTROL bit positions. -- BLOCKED: needs `regCP_HQD_PQ_CONTROL`'s bitfield POSITIONS -- again data the header says survives, and not written.
#
# 2. `hasattr` / `getattr`. :17/:21/:22/:25/:56/:58/:103/:260/:359/:389/:477/:646
#    all probe the `adev` or the module for a NAME, and :506-507 does
#    `getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')`. A Python attribute table is a
#    `dict`; what survives is the ANSWER and not the lookup.
# | wall(p3) runtime/support/am/ip.py:260  hasattr(smu_mod, 'PPSMC_MSG_QueryValidMcaCount'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
# | wall(p3) runtime/support/am/ip.py:389  hasattr(adev, 'regMM_ATC_L2_MISC_CG'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
# | wall(p3) runtime/support/am/ip.py:646  hasattr(adev.fw, 'smu_psp_desc'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
#
# 3. `functools.cache`. `get_pte_flags` (:177) and `read_clocks` (:230) are
#    memoised on their argument tuples. Bend has no memo table and the VALUE is a
#    pure function of the arguments, so nothing is lost but the cache.
# | WALL(p3) runtime/support/am/ip.py:177  functools.cache on get_pte_flags. -- BLOCKED: needs an UNBOUNDED memoisation DECORATOR (`functools.cache`). The port has no decorator mechanism, and a cache with no bound is not the same object as a `Table`.
# | WALL(p3) runtime/support/am/ip.py:230  functools.cache on read_clocks. -- BLOCKED: needs an UNBOUNDED memoisation DECORATOR (`functools.cache`). The port has no decorator mechanism, and a cache with no bound is not the same object as a `Table`.
#
# 4. THE FIRMWARE BLOBS and the FLOAT ROUND. `self.adev.fw.sos_fw[fw]` is a
#    `memoryview` of a signed PSP image, `read_table` (:228) is
#    `table_t.from_buffer(bytearray(vram.view(...)))`, and :250's
#    `int(round(watts))` is a float round. The KEYS and the clamp are ported; the
#    bytes and the round are not.
# | wall(p3) runtime/support/am/ip.py:250  int(round(watts)). -- blocked: needs Python's `round`, which is round-half-to-even: measured, `round(3.5)` is 4 and `int(3.5)` is 3, and `round(0.6)` is 1 while `int(0.6)` is 0. So this is a semantic difference and not a missing float-to-int conversion.
# | WALL(p3) runtime/support/am/ip.py:228  table_t.from_buffer(...). -- BLOCKED: needs `table_t.from_buffer(...)` -- CTYPES buffer aliasing, a Python object whose memory IS the table.
#
# 5. `wait_cond` and `time.sleep`. Thirteen `wait_cond`s (:113, :117, :121, :222,
#    :271, :284, :393, :450, :640, :656, :695, :704, :717) and six `time.sleep`s
#    (:219, :346, :417, :584, :692, :702). Each wait is a POLL with a timeout and
#    a message; the port carries the POLLED VALUE and the EXPECTED VALUE and not
#    the spin.
# | wall(p3) runtime/support/am/ip.py:113  wait_cond on the kiq fence. -- blocked: needs `wait_cond` on the kiq fence: a polling wait whose predicate is a device read, which is an ffi seam -- device mmio / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is data: the register field lists).
# | WALL(p3) runtime/support/am/ip.py:219  time.sleep(0.5) after mode1 reset. -- BLOCKED: needs the mode1 RESET and the `read_config` poll that follows it -- and NOT the sleep: `IO.sleep` EXISTS (`bend guide:359`). The blocker is the device I/O on either side of it, so the marker's own annotation names the wrong half.
#
# 6. THE MPS AND PAGE TABLES. `mm.palloc`, `mm.map_range`, `mm.alloc_vaddr`,
#    `pci_dev.alloc_sysmem`, `paddrs` and `mm.root_page_table` are the memory
#    manager, which is `support/memory.py` and not this file. What survives is
#    the SIZE and the ALIGNMENT each asks for.
# | WALL(p3) runtime/support/am/ip.py:278  mm.palloc(0x1000 * xccs, 2 + is_vf). -- BLOCKED: needs `mm.palloc(0x1000 * xccs, 2 + is_vf)`: an FFI seam -- device MMIO / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is DATA: the register field lists).
# | wall(p3) runtime/support/am/ip.py:331  mm.map_range(..., AddrSpace.sys, snooped, uncached). -- blocked: needs `mm.map_range(..., AddrSpace.SYS, snooped, ...)`: an ffi seam -- device mmio / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is data: the register field lists).
#
# THE GATE. One row per claim; the ORACLE is `.agents/slop/ip_oracle.py` and
# every `py=` expectation in it was produced by CALLING CPython, never typed.
# END BLOCK

# THE WALLS. Nothing below is in the port; each is a `raise`, an `ioctl`, a
# register ACCESS, or a Python reflection that Bend has no spelling for.
#
# 1. REGISTER ACCESS. Every `.write(...)` / `.update(...)` / `.read_bitfields()`
#    lands in the register file, and `AMDReg.encode`'s bit POSITIONS are in
#    `autogen/am/regs.py`, PER ARCH. `ops_amd.bend`'s WALL 2 says the same about
#    `regCOMPUTE_*` and `regSQ_THREAD_TRACE_*`, so this file and that one agree on
#    the split: the port carries WHICH register, WHICH field NAMES and in WHICH
#    order, and the offsets are the seam's. `amp_mqd_pqbits_*` is the row that
#    shows the split is real by printing the ENCODED word CPython produces.
# | WALL(p3) runtime/support/am/ip.py:411  AMDReg.encode -> regGRBM_GFX_CNTL. -- BLOCKED: needs `AMDReg.encode` and the `regGRBM_GFX_CNTL` register: `AMDReg`/`encode` are not defs under `am/`. The register WRITE itself is data the header says survives; the ENCODER is not written.
# | WALL(p3) runtime/support/am/ip.py:367  regCP_HQD_PQ_CONTROL bit positions. -- BLOCKED: needs `regCP_HQD_PQ_CONTROL`'s bitfield POSITIONS -- again data the header says survives, and not written.
#
# 2. `hasattr` / `getattr`. :17/:21/:22/:25/:56/:58/:103/:260/:359/:389/:477/:646
#    all probe the `adev` or the module for a NAME, and :506-507 does
#    `getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')`. A Python attribute table is a
#    `dict`; what survives is the ANSWER and not the lookup.
# | wall(p3) runtime/support/am/ip.py:260  hasattr(smu_mod, 'PPSMC_MSG_QueryValidMcaCount'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
# | wall(p3) runtime/support/am/ip.py:389  hasattr(adev, 'regMM_ATC_L2_MISC_CG'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
# | wall(p3) runtime/support/am/ip.py:646  hasattr(adev.fw, 'smu_psp_desc'). -- blocked: needs a dynamic attribute probe: Python resolves a name against an object at runtime (`hasattr(x, 'regMM_ATC_L2_MISC_CG')`). a compiled language has no name-to-field table, and this is the same blocker as `bnxtdev`'s `getattr` on a constructed f-string.
#
# 3. `functools.cache`. `get_pte_flags` (:177) and `read_clocks` (:230) are
#    memoised on their argument tuples. Bend has no memo table and the VALUE is a
#    pure function of the arguments, so nothing is lost but the cache.
# | WALL(p3) runtime/support/am/ip.py:177  functools.cache on get_pte_flags. -- BLOCKED: needs an UNBOUNDED memoisation DECORATOR (`functools.cache`). The port has no decorator mechanism, and a cache with no bound is not the same object as a `Table`.
# | WALL(p3) runtime/support/am/ip.py:230  functools.cache on read_clocks. -- BLOCKED: needs an UNBOUNDED memoisation DECORATOR (`functools.cache`). The port has no decorator mechanism, and a cache with no bound is not the same object as a `Table`.
#
# 4. THE FIRMWARE BLOBS and the FLOAT ROUND. `self.adev.fw.sos_fw[fw]` is a
#    `memoryview` of a signed PSP image, `read_table` (:228) is
#    `table_t.from_buffer(bytearray(vram.view(...)))`, and :250's
#    `int(round(watts))` is a float round. The KEYS and the clamp are ported; the
#    bytes and the round are not.
# | wall(p3) runtime/support/am/ip.py:250  int(round(watts)). -- blocked: needs Python's `round`, which is round-half-to-even: measured, `round(3.5)` is 4 and `int(3.5)` is 3, and `round(0.6)` is 1 while `int(0.6)` is 0. So this is a semantic difference and not a missing float-to-int conversion.
# | WALL(p3) runtime/support/am/ip.py:228  table_t.from_buffer(...). -- BLOCKED: needs `table_t.from_buffer(...)` -- CTYPES buffer aliasing, a Python object whose memory IS the table.
#
# 5. `wait_cond` and `time.sleep`. Thirteen `wait_cond`s (:113, :117, :121, :222,
#    :271, :284, :393, :450, :640, :656, :695, :704, :717) and six `time.sleep`s
#    (:219, :346, :417, :584, :692, :702). Each wait is a POLL with a timeout and
#    a message; the port carries the POLLED VALUE and the EXPECTED VALUE and not
#    the spin.
# | wall(p3) runtime/support/am/ip.py:113  wait_cond on the kiq fence. -- blocked: needs `wait_cond` on the kiq fence: a polling wait whose predicate is a device read, which is an ffi seam -- device mmio / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is data: the register field lists).
# | WALL(p3) runtime/support/am/ip.py:219  time.sleep(0.5) after mode1 reset. -- BLOCKED: needs the mode1 RESET and the `read_config` poll that follows it -- and NOT the sleep: `IO.sleep` EXISTS (`bend guide:359`). The blocker is the device I/O on either side of it, so the marker's own annotation names the wrong half.
#
# 6. THE MPS AND PAGE TABLES. `mm.palloc`, `mm.map_range`, `mm.alloc_vaddr`,
#    `pci_dev.alloc_sysmem`, `paddrs` and `mm.root_page_table` are the memory
#    manager, which is `support/memory.py` and not this file. What survives is
#    the SIZE and the ALIGNMENT each asks for.
# | WALL(p3) runtime/support/am/ip.py:278  mm.palloc(0x1000 * xccs, 2 + is_vf). -- BLOCKED: needs `mm.palloc(0x1000 * xccs, 2 + is_vf)`: an FFI seam -- device MMIO / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is DATA: the register field lists).
# | wall(p3) runtime/support/am/ip.py:331  mm.map_range(..., AddrSpace.sys, snooped, uncached). -- blocked: needs `mm.map_range(..., AddrSpace.SYS, snooped, ...)`: an ffi seam -- device mmio / an `mmap` -- which cannot be anything in Bend but a foreign call (`ip.bend:3-8` says what survives the crossing is data: the register field lists).
#
# THE GATE. One row per claim; the ORACLE is `.agents/slop/ip_oracle.py` and
# every `py=` expectation in it was produced by CALLING CPython, never typed.
