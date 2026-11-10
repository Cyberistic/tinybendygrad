# tinybendygrad/runtime/ops_qcom.bend -- port of tinygrad/runtime/ops_qcom.py
#
# ===========================================================================
# WHAT this file is. `ops_qcom.py` is the ADRENO/KGSL gpu backend, 396 lines.
# (The unit brief called it a Hexagon/QNN DSP backend with `qnn`/`htp` tables.
# It is not. `qnn`, `htp` and `cdsp` appear nowhere in this repo; the DSP
# backend is `ops_dsp.py`. What is here is what the named 396-line file
# actually contains, and it turns out to be the same SHAPE the brief asked
# for -- pure name tables and pure string emission over kernel uops -- so the
# plan is unchanged.)
#
# The three pure tables, and they are the whole of the portable half:
#
#   1. `qreg` (:36-41). `_qreg_exec` turns `qreg.a6xx_sp_cs_ndrange_0(
#      kerneldim=3, localsizex=7)` into a u32 by string surgery on the mesa
#      register namespace: `reg_name = __reg[4:] + "_" + k.removeprefix("_")
#      .upper()`, then `getattr(mesa, reg_name)` if the value is a bool and
#      `v << getattr(mesa, reg_name + "__SHIFT")` otherwise. NO ARITHMETIC
#      HAPPENS HERE, ONLY NAME RESOLUTION -- which is exactly the kind of
#      table this project gates best, because a wrong entry is a silent
#      wrong kernel and a table gates in both directions.
#   2. `flag` (tinygrad/runtime/ops_qcom.py:298 symbol=flag) over the four kgsl `_SHIFT`/`_MASK` pairs.
#   3. The six DERIVED program sizes (:232-237), pure U32 arithmetic over
#      `pvtmem`, `shmem`, `fregs`, `hregs`, `tex_cnt`, `ibo_cnt`, `samp_cnt`.
#
# And the two packet headers (:49, :51), which are pure bit arithmetic with
# a NON-TRIVIAL precedence (`|` binds looser than `&` and `<<`) and a
# non-trivial `parity` (:45-47).
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure, and the gate checks it) OR records that call in
# the trace -- and stage 1 records nothing, so every def here is a builder and
# the whole table set is pure. There is no third kind, which is what puts the
# `raise` in the trace once stage 3 adds it, so a refusal appears as a
# TRUNCATED trace needing no guard of its own.
#
# ===========================================================================
# WHAT is ported so far, AND what is not.
#
#   :19  `BUFTYPE_BUF`             PORTED  the port's own buftype_names, both directions
#   :35-40 `_qreg_exec`/`qreg`     PORTED  the port's own mesa_name/qreg_name
#   :35-40 `_qreg_exec`            PORTED  the port's own qregs/qfields/qreg.of
#   tinygrad/runtime/ops_qcom.py:42  ctz               PORTED  `ctz` (see THE Ctz PRECONDITION) symbol=ctz
#   :44-46 parity                 PORTED  `parity`
#   tinygrad/runtime/ops_qcom.py:48  pkt7_hdr          PORTED  `pkt7_hdr` symbol=pkt7_hdr
#   tinygrad/runtime/ops_qcom.py:50  pkt4_hdr          PORTED  `pkt4_hdr` symbol=pkt4_hdr
#   :52  `_read_lib`              PORTED  the port's own read_lib (little-endian u32)
#   tinygrad/runtime/ops_qcom.py:298 flag              PORTED  `kgsl_flags`, both directions, `flag` symbol=flag
#   :8   the `kgsl`/`mesa`/`libc` import  PORTED  the MESA_*/KGSL_* constants (62)
#
# NOT YET PORTED, and every one of these is a SEAM or a later stage:
#
#   :22-32 dcache_flush           WALL 1  the CPU-side kernel, a seam
#   :55-204 QCOMComputeQueue      STAGE 3 the trace (kernargs, exec, submit)
#   :206-283 QCOMProgramData      STAGE 2 the lib parser and the cache
#   :285-292 qcom_build_program   STAGE 2 the program cache
#   :294-301 QCOMAllocator        STAGE 3 consumes device.bend's Bn/Bspec
#   :305-396 QCOMDevice           STAGE 3 the init order and the ioctls
#
# THE SEAMS, named once: the CDSP/kgsl DRIVER (`FileIOInterface`,
# `IOCTL_KGSL_*`, `mmap`), the compiler invocation
# (`Device["CPU"].renderer`, `prg.to_elf()`, `IR3Compiler.unpack_lib`),
# and Hexagon-RPC (which this file does not use -- see the note above).
#
# ===========================================================================
# NO qgpu IN THIS ENV. There is no Adreno here, so NOTHING below was measured
# against a live device. Every constant and every table entry was read out of
# `tinygrad/runtime/autogen/mesa.py` and `.../kgsl.py` BY CALLING THEM, and
# every expectation in the gate is printed by `.agents/slop/qc_oracle.py`.
# Nothing in this file is a number somebody typed.
#
# ===========================================================================
# ONE thing the oracle got wrong first, recorded because it is the kind of
# thing that ships: the first version keyed the qreg call sites by LINE
# NUMBER, and lines :111, :189, :225, :257 and :258 each carry TWO or THREE
# `qreg.` calls. Keying by line silently dropped `a6xx_tex_const_7`,
# `cp_exec_cs_2`, `cp_exec_cs_3` and every second sampler field -- NREGS=30
# and NFIELDS=55 where the AST walk says 34 and 62. The tables below are the
# SECOND run's, and `qc_nregs`/`qc_nfields` are the rows that would have
# caught it.
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. The PORTED lines are what this file decides; the
# SEAM lines are what it names and does not do; the WALL lines are what Bend
# cannot express at all.
#
#   :19   `BUFTYPE_BUF`                  PORTED  the port's own buftype_names, both directions
#   :35-40 `_qreg_exec`/`qreg`           PORTED  the port's own mesa_of/qreg_of/is_reg_name
#   :35-40 `_qreg_exec`                  PORTED  the port's own qregs/qfields/qreg.of
#   tinygrad/runtime/ops_qcom.py:42   ctz                PORTED  `ctz` (see THE ctz PRECONDITION) symbol=ctz
#   :44-46 parity                        PORTED  `parity`
#   tinygrad/runtime/ops_qcom.py:48   pkt7_hdr          PORTED  `pkt7_hdr` symbol=pkt7_hdr
#   tinygrad/runtime/ops_qcom.py:50   pkt4_hdr          PORTED  `pkt4_hdr` symbol=pkt4_hdr
#   :52   `_read_lib`                    PORTED  the port's own read_lib/read_words
#   :62/:64 `cmd`/`reg` the word count   PORTED  the port's own qwords
#   :66-73 `_cache_flush`                PORTED  the port's own flush.of + `Tr`
#   :75   `memory_barrier`               PORTED  the port's own FLUSH_BARRIER
#   :79   the `gpu_id` signal guard      PORTED  the port's own rf.gpu_lt73 / RF_EVENT7
#   :122  the resources refusal          PORTED  the port's own rf.resources + `Tr.refuse`
#   :123  the dims refusal                PORTED  the port's own rf.dims + `Tr.refuse`
#   :119-196 exec                         PORTED  the port's own exec.of and its 27-call trace
#   tinygrad/runtime/ops_qcom.py:57 the ioctl command word  PORTED  `ioctl_cmd` symbol=qcom_submit
#   tinygrad/runtime/ops_qcom.py:206 `QCOMProgramData`    PORTED  `pd.parse_full`, `desc.*`, `const.*` symbol=QCOMProgramData
#   :225/:272 the two offset rules       PORTED  the port's own pd.nir_*/pd.cl_*
#   :232-237 the six derived sizes        PORTED  the port's own pd.*
#   :239-283 `_parse_lib`                 PORTED  the two binary walks
#   :285-288 `qcom_build_program`         PORTED  the port's own qcom.get/ce.find/ce.put
#   :289-297 `QCOMAllocator`              WALL 3  `:296 _offset` is device.bend's own
#   tinygrad/runtime/ops_qcom.py:298 `flag`              PORTED  `kgsl_flags`, both directions symbol=flag
#   :310-345 `QCOMDevice.__init__`        PARTIAL the flags and the gpu_id refusal
#   :310-345 the init SEQUENCE            WALL 4  the ioctls and mmap are seams
#   :339-342 `dummy`/`border_color`       PARTIAL the SIZES only, in the port's own FLUSH_*
#   :344-370 _gpu_alloc/_gpu_free        WALL 4  ioctls, mmap, memset, munmap
#   :354-362 `_gpu_map`                   WALL 4  the ioctl, the EFAULT arm
#   :371-376 `_wait_signal`               WALL 4  the timestamp ioctls
#   tinygrad/runtime/ops_qcom.py:378 _ensure_stack_size  WALL 3  it is `Buffer` and device.bend's
#   :384-386 `_at_profile_finalize`       WALL 4  sysfs
#
# NOT PORTED AT ALL, and these are the gaps a reader should weigh first:
#
#   :89-113 `kernargs`               WALL 1+2  the argument trace proper. What
#        survives here is `layout_args`/`pack_args` (tinygrad/runtime/support/hcq2.py:114-124 symbol=layout_args), the two
#        functions `kernargs` is built from, and the pad SEQUENCE they produce.
#        The buffer/image/sampler SELECTION at tinygrad/runtime/ops_qcom.py:98 symbol=kernargs and the `tex_to_image`
#        permutation at :94 are not ported.
#   :104-112 `_tex`                   WALL 1  the 16-word image descriptor
#   :194-204 `submit`                PARTIAL the ioctl word only; the
#        `cstruct(kgsl...)` layout and the `ret.index(0).store(...)` are walls
#   :18    the IOCTL import          PORTED  the 62 mesa/kgsl constants
#   :19-20 the two renderers         WALL 4  a seam
#   :22-32 `dcache_flush`            WALL 1  a CPU-device kernel and a seam
#
# THE FOUR WALLS.
#
#  1. UOPS. `bufs[slot].getaddr(self.devs)`, `data.prg_offset`, `stack_addr`
#     and every `UOp` in `kernargs` are arena indices, and there is no arena
#     here. What is portable is the COUNT and the ORDER, which is what `exec`'s
#     trace carries -- one entry per CALL -- and the argument builders, which
#     are separate pure defs.
#  2. u64. `info.chip_id >> 24`, `mv_address(...)`, `UOp.placeholder((n,), ...)`
#     with n from a 64-bit product, `2**31 - 1` in `submit`. The `hw_stack_offset`
#     derivation multiplies by 128*16 and is a 42-bit product in general; every
#     oracle fixture here has `next_power2(...) <= 2**12` so it fits, and that is
#     blind spot 2.
#  3. Buffer. `_gpu_alloc` returns a `BufferStorage`, `_offset` returns an
#     arena index, and `_ensure_stack_size` allocates a `Buffer`. `device.bend`
#     OWES all three (`D.Bn`, `D.Bspec`, `D.root`) and this file CONSUMES none
#     of them yet -- see WALL 3 above.
#  4. SYSCALLS AND THE DRIVER. `FileIOInterface`, `IOCTL_KGSL_*`, `mmap`,
#     `munmap`, `ctypes.memset`, `System.write_sysfs`. Named once, here.
#
# ===========================================================================
# NO qgpu IN THIS ENV. There is no Adreno here, so NOTHING below was measured
# against a live device. Every constant was read out of
# `tinygrad/runtime/autogen/mesa.py` and `.../kgsl.py` BY CALLING THEM, and
# every expectation in the gate is printed by CPython:
#
#   gates/qcom-oracle.py         the tables, the parse, the cache key
#   gates/qcom_stage3-oracle.py  the headers, the refusals, layout_args
#   gates/qcom_cache-oracle.py   the REAL `_qcom_program_cache` dict
#   .agents/slop/qc_exec_oracle.py    the REAL `QCOMComputeQueue.exec` -- NOT RESTORED, IT IS
#                                     RED: its own stub device `D` has no `tag`, and the live
#                                     `tinygrad/runtime/ops_qcom.py:130` allocates the stack with `name="stack"`; upstream's `self.dev.tag` is GONE
#                                     at this pin (9ff6db7b0), so the stub's own `AttributeError: 'D' object has no
#                                     attribute 'tag'` is about the PORT's stub, not about upstream. It measured a
#                                     thing upstream no longer has; the FIXTURE is one method behind it. Reported, not fabricated.
#   .agents/slop/qc_check.py         diffs the gate's output against all four
#
# THE FIRST THREE WERE RESTORED 2026-10-16 from `.agents/slop/{qc,qc_stage3,qc_cache}_oracle.py`
# (blobs e853efc4b, 17567/8870/2449 B, byte for byte) and now live in `gates/`, because
# `gates/README.md` says a gate's oracle lives beside its gate and the sweep of 2026-10-05
# proved the other directory cannot be depended on. MEASURED from `gates/`: rc=0 and 588 / 108 /
# 6 rows respectively, and `qcom_cache-oracle.py` drives the REAL `_qcom_program_cache` dict,
# so it is a call and not a transcription.
#
# Nothing in this file is a number somebody typed.

import Base
import ../helpers.bend as H

# ===========================================================================
# THE CONSTANTS. Every one is `getattr(mesa|kgsl, NAME)` MEASURED by the
# oracle's `refs`, which walks the AST of ops_qcom.py and reports the value of
# every `mesa.X` / `kgsl.X` attribute the file actually reads. Sixty-two of
# them, and they are named WITHOUT a module prefix because the two C
# namespaces do not collide -- the oracle asserts that, so a future collision
# is an oracle failure rather than a silent shadow.
# ===========================================================================

# --- the packet-type tags, :49 and :51 -------------------------------------
def CP_TYPE7_PKT() -> U32: 1879048192
def CP_TYPE4_PKT() -> U32: 1073741824

# --- the CP_* opcodes ops_qcom.py passes to `self.cmd` --------------------
def CP_WAIT_FOR_IDLE() -> U32: 38
def CP_EVENT_WRITE() -> U32: 70
def CP_WAIT_MEM_WRITES() -> U32: 18
def CP_LOAD_STATE6_FRAG() -> U32: 52
def CP_SET_MARKER() -> U32: 101
def CP_EXEC_CS() -> U32: 51
def CP_RUN_OPENCL() -> U32: 49
def REG_A6XX_SP_UPDATE_CNTL() -> U32: 47880
def REG_A6XX_SP_CS_TSIZE() -> U32: 43450
def REG_A6XX_SP_CS_USIZE() -> U32: 43520
def REG_A6XX_SP_MODE_CNTL() -> U32: 43776
def REG_A6XX_SP_PERFCTR_SHADER_MASK() -> U32: 44559
def REG_A6XX_TPL1_MODE_CNTL() -> U32: 45833
def REG_A6XX_TPL1_DBG_ECO_CNTL() -> U32: 46592
def REG_A6XX_SP_CS_NDRANGE_0() -> U32: 47504
def REG_A6XX_SP_CS_CNTL_0() -> U32: 43440
def REG_A6XX_SP_REG_PROG_ID_0() -> U32: 47491
def REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET() -> U32: 43453
def REG_A6XX_SP_CS_INSTR_SIZE() -> U32: 43452
def REG_A6XX_SP_CS_SAMPLER_BASE() -> U32: 43490
def REG_A6XX_TPL1_CS_BORDER_COLOR_BASE() -> U32: 45440
def REG_A6XX_SP_CS_TEXMEMOBJ_BASE() -> U32: 43494
def REG_A6XX_SP_CS_UAV_BASE() -> U32: 43506
def REG_A6XX_SP_CS_CONFIG() -> U32: 43451
def REG_A6XX_SP_CS_CONST_CONFIG_0() -> U32: 47511
def BUFTYPE_BUF() -> U32: 0
def BUFTYPE_TEX() -> U32: 1
def BUFTYPE_IBO() -> U32: 2

def buftype_names() -> List<&2, String>: ["BUFTYPE_BUF", "BUFTYPE_TEX", "BUFTYPE_IBO"]

def buftype_ix.put(hit: Bool, at: U32, got: U32) -> U32:
  Bool.pick(U32, hit, at, got)

def buftype_ix.go(n: Nat, +s: String, ns: List<&2, String>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ns:
        case Nil{}: got
        case h <> t: buftype_ix.go(m, s, t, U32.add(at, 1), buftype_ix.put(String.eq(h, s), at, got))

def buftype_name.at(v: Nat) -> String:
  match v:
    case 0n: "BUFTYPE_BUF"
    case 1n: "BUFTYPE_TEX"
    case _: "BUFTYPE_IBO"

def qregs() -> List<&2, String>:
  ["a6xx_cp_set_marker_0", "a6xx_sp_cs_cntl_0", "a6xx_sp_cs_cntl_1", "a6xx_sp_cs_config",
   "a6xx_sp_cs_const_config", "a6xx_sp_cs_const_config_0", "a6xx_sp_cs_instr_size",
   "a6xx_sp_cs_ndrange_0", "a6xx_sp_cs_pvt_mem_param", "a6xx_sp_cs_pvt_mem_size",
   "a6xx_sp_cs_pvt_mem_stack_offset", "a6xx_sp_cs_tsize", "a6xx_sp_cs_usize",
   "a6xx_sp_cs_wge_cntl", "a6xx_sp_mode_cntl", "a6xx_sp_perfctr_shader_mask",
   "a6xx_sp_update_cntl", "a6xx_tex_const_0", "a6xx_tex_const_1", "a6xx_tex_const_2",
   "a6xx_tex_const_6", "a6xx_tex_const_7", "a6xx_tex_samp_0", "a6xx_tex_samp_1",
   "a6xx_tpl1_mode_cntl", "cp_event_write_0", "cp_exec_cs_1", "cp_exec_cs_2",
   "cp_exec_cs_3", "cp_load_state6_0", "cp_reg_to_mem_0", "cp_wait_reg_mem_0",
   "cp_wait_reg_mem_4", "cp_wait_reg_mem_5"]

# :41 `name[4:]` strips the `REG_` and the `f"{__reg[4:]}_{...}"` at :38 uses
# what is left. `REG_` itself is a constant of the FORMAT, not of the table, so
# it gets a def and the two name functions use it.
def REG_PREFIX() -> String: "REG_"
def REG_PREFIX_LEN() -> Nat: 4n

# FORWARD. `qreg.a6xx_tex_const_0` -> `REG_A6XX_TEX_CONST_0`.
def mesa_of(+nm: String) -> String: String.concat([REG_PREFIX(), String.to_upper(nm)])

# REVERSE. `REG_A6XX_TEX_CONST_0` -> `a6xx_tex_const_0`. This is the `:41`
# comprehension's OWN key function, and `qc_rev_*` is the row that says the
# round trip is the identity -- a table that is only right one way is a table
# with a transcription error waiting to happen.
def qreg_of(+nm: String) -> String: String.to_lower(String.drop(nm, REG_PREFIX_LEN()))

# is this mesa name one the :41 comprehension kept? `name[:4] == 'REG_'`.
def is_reg_name(+nm: String) -> Bool: String.eq(String.take(nm, REG_PREFIX_LEN()), REG_PREFIX())

# `AttributeError`, as a U32. A mesa name outside the table has no `qreg`
# attribute and cannot be written, so the port says so instead of answering 0,
# which is `a6xx_cp_set_marker_0`.
def NO_SUCH_REG() -> U32: 4294967295
def NO_SUCH_FIELD() -> U32: 4294967295

def qreg_ix.put(hit: Bool, at: U32, got: U32) -> U32:
  Bool.pick(U32, hit, at, got)

def qreg_ix.go(n: Nat, +nm: String, vs: List<&2, String>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match vs:
        case Nil{}: got
        case h <> t: qreg_ix.go(m, nm, t, U32.add(at, 1), qreg_ix.put(String.eq(h, nm), at, got))

# seeded with NO_SUCH_REG, NOT 0: 0 is `a6xx_cp_set_marker_0`, so a lookup miss
# that answered 0 would silently write to the wrong register. `qc_regix_absent`
# is the row that says the table can refuse.
def qreg_ix(+nm: String) -> U32: qreg_ix.go(List.length(&2, String, qregs()), nm, qregs(), 0, NO_SUCH_REG())

# the REVERSE lookup, by index: which `qreg` attribute is mesa name `nm`?
def qreg_ix_of_mesa(+nm: String) -> U32:
  Bool.pick(U32, is_reg_name(nm), qreg_ix(qreg_of(nm)), NO_SUCH_REG())

def qreg_name_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "?"

def qreg_name_at(ix: U32) -> String: qreg_name_of(List.get(&2, String, qregs(), U32.to_nat(ix)))

def qreg_mesa_at(ix: U32) -> String: mesa_of(qreg_name_at(ix))

# ===========================================================================
# THE FIELD TABLE. `_qreg_exec`'s second half, and this is where the whole
# subtlety lives:
#
#     __val |= (getattr(mesa, reg_name) if v else 0) if type(v) is bool \
#             else (v << getattr(mesa, f'{reg_name}__SHIFT'))
#
# `type(v) is bool` -- NOT `isinstance`, and NOT "the value is 0 or 1". A field
# whose mesa attribute exists WITHOUT the `__SHIFT` suffix is a bit flag whose
# Python value is always the literal `True`; a field whose attribute exists
# only WITH the suffix takes an arbitrary integer and is shifted into place.
# The oracle ASSERTS that for all sixty-two fields exactly one of the two names
# exists (`assert isb != ish`), so `isb` below is not a guess about the call
# site: it is READ OUT OF THE NAMESPACE, and the namespace is the authority.
#
# `nm` is the full mesa attribute the port would `getattr`. It is a field of
# the row so the gate can diff it against CPython, because a wrong `nm` with a
# right `v` still produces a right-looking u32 in the port and a wrong one on
# the device.
# ===========================================================================

type Qf is Data:
  Qf{r: String, f: String, nm: String, v: U32, isb: Bool}

def qfields() -> List<&2, Qf>:
  [Qf{"a6xx_cp_set_marker_0", "MODE", "A6XX_CP_SET_MARKER_0_MODE__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_cntl_0", "THREADSIZE", "A6XX_SP_CS_CNTL_0_THREADSIZE__SHIFT", 20, False{}},
   Qf{"a6xx_sp_cs_cntl_0", "HALFREGFOOTPRINT", "A6XX_SP_CS_CNTL_0_HALFREGFOOTPRINT__SHIFT", 1, False{}},
   Qf{"a6xx_sp_cs_cntl_0", "FULLREGFOOTPRINT", "A6XX_SP_CS_CNTL_0_FULLREGFOOTPRINT__SHIFT", 7, False{}},
   Qf{"a6xx_sp_cs_cntl_0", "BRANCHSTACK", "A6XX_SP_CS_CNTL_0_BRANCHSTACK__SHIFT", 14, False{}},
   Qf{"a6xx_sp_cs_cntl_1", "CONSTANTRAMMODE", "A6XX_SP_CS_CNTL_1_CONSTANTRAMMODE__SHIFT", 5, False{}},
   Qf{"a6xx_sp_cs_cntl_1", "SHARED_SIZE", "A6XX_SP_CS_CNTL_1_SHARED_SIZE__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_config", "ENABLED", "A6XX_SP_CS_CONFIG_ENABLED", 256, True{}},
   Qf{"a6xx_sp_cs_config", "NSAMP", "A6XX_SP_CS_CONFIG_NSAMP__SHIFT", 17, False{}},
   Qf{"a6xx_sp_cs_config", "NTEX", "A6XX_SP_CS_CONFIG_NTEX__SHIFT", 9, False{}},
   Qf{"a6xx_sp_cs_config", "NUAV", "A6XX_SP_CS_CONFIG_NUAV__SHIFT", 22, False{}},
   Qf{"a6xx_sp_cs_const_config", "CONSTLEN", "A6XX_SP_CS_CONST_CONFIG_CONSTLEN__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_const_config", "ENABLED", "A6XX_SP_CS_CONST_CONFIG_ENABLED", 256, True{}},
   Qf{"a6xx_sp_cs_const_config_0", "WGIDCONSTID", "A6XX_SP_CS_CONST_CONFIG_0_WGIDCONSTID__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_const_config_0", "WGSIZECONSTID", "A6XX_SP_CS_CONST_CONFIG_0_WGSIZECONSTID__SHIFT", 8, False{}},
   Qf{"a6xx_sp_cs_const_config_0", "WGOFFSETCONSTID", "A6XX_SP_CS_CONST_CONFIG_0_WGOFFSETCONSTID__SHIFT", 16, False{}},
   Qf{"a6xx_sp_cs_const_config_0", "LOCALIDREGID", "A6XX_SP_CS_CONST_CONFIG_0_LOCALIDREGID__SHIFT", 24, False{}},
   Qf{"a6xx_sp_cs_ndrange_0", "KERNELDIM", "A6XX_SP_CS_NDRANGE_0_KERNELDIM__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_ndrange_0", "LOCALSIZEX", "A6XX_SP_CS_NDRANGE_0_LOCALSIZEX__SHIFT", 2, False{}},
   Qf{"a6xx_sp_cs_ndrange_0", "LOCALSIZEY", "A6XX_SP_CS_NDRANGE_0_LOCALSIZEY__SHIFT", 12, False{}},
   Qf{"a6xx_sp_cs_ndrange_0", "LOCALSIZEZ", "A6XX_SP_CS_NDRANGE_0_LOCALSIZEZ__SHIFT", 22, False{}},
   Qf{"a6xx_sp_cs_pvt_mem_param", "MEMSIZEPERITEM", "A6XX_SP_CS_PVT_MEM_PARAM_MEMSIZEPERITEM__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_pvt_mem_size", "TOTALPVTMEMSIZE", "A6XX_SP_CS_PVT_MEM_SIZE_TOTALPVTMEMSIZE__SHIFT", 0, False{}},
   Qf{"a6xx_sp_cs_wge_cntl", "THREADSIZE", "A6XX_SP_CS_WGE_CNTL_THREADSIZE__SHIFT", 9, False{}},
   Qf{"a6xx_sp_cs_wge_cntl", "LINEARLOCALIDREGID", "A6XX_SP_CS_WGE_CNTL_LINEARLOCALIDREGID__SHIFT", 0, False{}},
   Qf{"a6xx_sp_mode_cntl", "ISAMMODE", "A6XX_SP_MODE_CNTL_ISAMMODE__SHIFT", 1, False{}},
   Qf{"a6xx_sp_mode_cntl", "CONSTANT_DEMOTION_ENABLE", "A6XX_SP_MODE_CNTL_CONSTANT_DEMOTION_ENABLE", 1, True{}},
   Qf{"a6xx_sp_perfctr_shader_mask", "CS", "A6XX_SP_PERFCTR_SHADER_MASK_CS", 32, True{}},
   Qf{"a6xx_sp_update_cntl", "CS_STATE", "A6XX_SP_UPDATE_CNTL_CS_STATE", 32, True{}},
   Qf{"a6xx_sp_update_cntl", "CS_UAV", "A6XX_SP_UPDATE_CNTL_CS_UAV", 64, True{}},
   Qf{"a6xx_tex_const_0", "FMT", "A6XX_TEX_CONST_0_FMT__SHIFT", 22, False{}},
   Qf{"a6xx_tex_const_0", "SWIZ_X", "A6XX_TEX_CONST_0_SWIZ_X__SHIFT", 4, False{}},
   Qf{"a6xx_tex_const_0", "SWIZ_Y", "A6XX_TEX_CONST_0_SWIZ_Y__SHIFT", 7, False{}},
   Qf{"a6xx_tex_const_0", "SWIZ_Z", "A6XX_TEX_CONST_0_SWIZ_Z__SHIFT", 10, False{}},
   Qf{"a6xx_tex_const_0", "SWIZ_W", "A6XX_TEX_CONST_0_SWIZ_W__SHIFT", 13, False{}},
   Qf{"a6xx_tex_const_1", "WIDTH", "A6XX_TEX_CONST_1_WIDTH__SHIFT", 0, False{}},
   Qf{"a6xx_tex_const_1", "HEIGHT", "A6XX_TEX_CONST_1_HEIGHT__SHIFT", 15, False{}},
   Qf{"a6xx_tex_const_2", "TYPE", "A6XX_TEX_CONST_2_TYPE__SHIFT", 29, False{}},
   Qf{"a6xx_tex_const_2", "PITCH", "A6XX_TEX_CONST_2_PITCH__SHIFT", 7, False{}},
   Qf{"a6xx_tex_const_2", "PITCHALIGN", "A6XX_TEX_CONST_2_PITCHALIGN__SHIFT", 0, False{}},
   Qf{"a6xx_tex_const_6", "PLANE_PITCH", "A6XX_TEX_CONST_6_PLANE_PITCH__SHIFT", 8, False{}},
   Qf{"a6xx_tex_samp_0", "WRAP_S", "A6XX_TEX_SAMP_0_WRAP_S__SHIFT", 5, False{}},
   Qf{"a6xx_tex_samp_0", "WRAP_T", "A6XX_TEX_SAMP_0_WRAP_T__SHIFT", 8, False{}},
   Qf{"a6xx_tex_samp_0", "WRAP_R", "A6XX_TEX_SAMP_0_WRAP_R__SHIFT", 11, False{}},
   Qf{"a6xx_tex_samp_1", "UNNORM_COORDS", "A6XX_TEX_SAMP_1_UNNORM_COORDS", 32, True{}},
   Qf{"a6xx_tex_samp_1", "CUBEMAPSEAMLESSFILTOFF", "A6XX_TEX_SAMP_1_CUBEMAPSEAMLESSFILTOFF", 16, True{}},
   Qf{"a6xx_tpl1_mode_cntl", "ISAMMODE", "A6XX_TPL1_MODE_CNTL_ISAMMODE__SHIFT", 0, False{}},
   Qf{"cp_event_write_0", "EVENT", "CP_EVENT_WRITE_0_EVENT__SHIFT", 0, False{}},
   Qf{"cp_exec_cs_1", "NGROUPS_X", "CP_EXEC_CS_1_NGROUPS_X__SHIFT", 0, False{}},
   Qf{"cp_exec_cs_2", "NGROUPS_Y", "CP_EXEC_CS_2_NGROUPS_Y__SHIFT", 0, False{}},
   Qf{"cp_exec_cs_3", "NGROUPS_Z", "CP_EXEC_CS_3_NGROUPS_Z__SHIFT", 0, False{}},
   Qf{"cp_load_state6_0", "STATE_TYPE", "CP_LOAD_STATE6_0_STATE_TYPE__SHIFT", 14, False{}},
   Qf{"cp_load_state6_0", "STATE_SRC", "CP_LOAD_STATE6_0_STATE_SRC__SHIFT", 16, False{}},
   Qf{"cp_load_state6_0", "STATE_BLOCK", "CP_LOAD_STATE6_0_STATE_BLOCK__SHIFT", 18, False{}},
   Qf{"cp_load_state6_0", "NUM_UNIT", "CP_LOAD_STATE6_0_NUM_UNIT__SHIFT", 22, False{}},
   Qf{"cp_reg_to_mem_0", "REG", "CP_REG_TO_MEM_0_REG__SHIFT", 0, False{}},
   Qf{"cp_reg_to_mem_0", "CNT", "CP_REG_TO_MEM_0_CNT__SHIFT", 18, False{}},
   Qf{"cp_reg_to_mem_0", "64B", "CP_REG_TO_MEM_0_64B", 1073741824, True{}},
   Qf{"cp_wait_reg_mem_0", "FUNCTION", "CP_WAIT_REG_MEM_0_FUNCTION__SHIFT", 0, False{}},
   Qf{"cp_wait_reg_mem_0", "POLL", "CP_WAIT_REG_MEM_0_POLL__SHIFT", 4, False{}},
   Qf{"cp_wait_reg_mem_4", "MASK", "CP_WAIT_REG_MEM_4_MASK__SHIFT", 0, False{}},
   Qf{"cp_wait_reg_mem_5", "DELAY_LOOP_CYCLES", "CP_WAIT_REG_MEM_5_DELAY_LOOP_CYCLES__SHIFT", 0, False{}}]

def Qf.r(x: Qf) -> String:
  match x:
    case Qf{r, f, nm, v, isb}: r

def Qf.f(x: Qf) -> String:
  match x:
    case Qf{r, f, nm, v, isb}: f

def Qf.nm(x: Qf) -> String:
  match x:
    case Qf{r, f, nm, v, isb}: nm

def Qf.v(x: Qf) -> U32:
  match x:
    case Qf{r, f, nm, v, isb}: v

def Qf.isb(x: Qf) -> Bool:
  match x:
    case Qf{r, f, nm, v, isb}: isb

# the two-key match. `(r, f)` is unique in the table and the oracle asserts
# that too, so "the last hit" is "the only hit" and the accumulator is sound.
def qfield_ix.put(hit: Bool, at: U32, got: U32) -> U32:
  Bool.pick(U32, hit, at, got)

def qfield_ix.go(n: Nat, +r: String, +f: String, vs: List<&2, Qf>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match vs:
        case Nil{}: got
        case Qf{rr, ff, nm, v, isb} <> t:
          qfield_ix.go(m, r, f, t, U32.add(at, 1),
            qfield_ix.put(Bool.and(String.eq(rr, r), String.eq(ff, f)), at, got))

def qfield_ix(+r: String, +f: String) -> U32:
  qfield_ix.go(List.length(&2, Qf, qfields()), r, f, qfields(), 0, NO_SUCH_FIELD())

def qfield_of(m: Maybe<&2, Qf>) -> Qf:
  match m:
    case Some{s}: s
    case None{}: Qf{"", "", "", 0, False{}}

def qfield_at(r: String, f: String) -> Qf:
  qfield_of(List.get(&2, Qf, qfields(), U32.to_nat(qfield_ix(r, f))))

def qfield_v(+r: String, +f: String) -> U32: Qf.v(qfield_at(r, f))

def qreg.bit_of(+on: U32, +row: Qf) -> U32:
  Bool.pick(U32, U32.is_eq(on, 0), 0, Qf.v(row))

def qreg.one(+row: Qf, +v: U32) -> U32:
  Bool.pick(U32, Qf.isb(row), qreg.bit_of(v, row), U32.shln(v, U32.to_nat(Qf.v(row))))

# the ordered keyword list. A Python `kwargs` is a DICT and its iteration
# order is insertion order, and `_qreg_exec` ORs in that order; OR is
# commutative so the order does not change the ANSWER, but it does change the
# SEQUENCE the trace would show, and the trace shows one def per field, so the
# order is kept and `qc_reg_order` pins it.
type Fv is Data:
  Fv{f: String, v: U32}

def qreg.of.go2(n: Nat, +val: U32, +r: String, vs: List<&2, Fv>) -> U32:
  match n:
    case 0n: val
    case 1n+m:
      match vs:
        case Nil{}: val
        case Fv{f, v} <> t: qreg.of.go2(m, U32.or(val, qreg.one(qfield_at(r, f), v)), r, t)

def qreg.flag(r: String, f: String) -> U32: qfield_v(r, f)

def CTZ_BITS() -> Nat: 32n

# `(v & -v).bit_length() - 1` is the INDEX of the lowest set bit, so the walk has
# to STOP at the first one and not merely stop counting -- and those are two
# different bugs. Two versions of this failed here, both caught by the gate:
# the arms the other way round (which counts trailing ONES) and then an arm that
# merely declines to increment (which answers 31 for `ctz(1)`, because the bits
# ABOVE the lowest set bit go on incrementing). So `done` is a FIELD, not an
# early exit: Bend has no `break` and a `Bool.pick` cannot gate a self-call.
type Cz is Data:
  Cz{got: U32, done: Bool}

# A SET bit STOPS the walk without counting -- the bit itself is not a zero --
# and a CLEAR bit counts one and moves on. Three versions of this got it wrong
# (see the note above); this is the one the gate accepts, and `qc_ctz_0000003f`
# is the row that pins it: 0x3f has SIX set bits, so a version that keeps
# counting past the first answers something other than 0.
def ctz.step.at(bit: Bool, +got: U32, done: Bool) -> Cz:
  Bool.pick(Cz, done, Cz{got, True{}},
    Bool.pick(Cz, bit, Cz{got, True{}}, Cz{U32.add(got, 1), False{}}))

def ctz.step(v: U32, +st: Cz) -> Cz:
  match st:
    case Cz{+got, done}: ctz.step.at(U32.is_eq(U32.and(v, 1), 1), got, done)

def ctz.go(n: Nat, +v: U32, +st: Cz) -> Cz:
  match n:
    case 0n: st
    case 1n+m: ctz.go(m, U32.shrn(v, 1n), ctz.step(v, st))

def ctz.of(st: Cz) -> U32:
  match st:
    case Cz{got, done}: got

def PARITY_XOR() -> U32: 38505

# the three rounds are `>> 16`, `>> 8`, `>> 4` and NOTHING ELSE, because
# `range(4, 1, -1)` is {4, 3, 2} and `1 << 4, 1 << 3, 1 << 2` are 16, 8, 4.
def parity.round16(+v: U32) -> U32: U32.xor(v, U32.shrn(v, 16n))
def parity.round8(+v: U32) -> U32: U32.xor(v, U32.shrn(v, 8n))
def parity.round4(+v: U32) -> U32: U32.xor(v, U32.shrn(v, 4n))
def parity.folded(+v: U32) -> U32: parity.round4(parity.round8(parity.round16(v)))

def parity.bit(+v: U32) -> U32: U32.and(U32.shrn(PARITY_XOR(), U32.to_nat(U32.and(v, 15))), 1)

def parity(+v: U32) -> U32: parity.bit(parity.folded(v))

# ===========================================================================
# ops_qcom.py:49 and :51 -- THE PACKET HEADERS.
#
#     pkt7_hdr(opcode, cnt) = CP_TYPE7_PKT | cnt & 0x3FFF | parity(cnt) << 15
#                            | (opcode & 0x7F) << 16 | parity(opcode) << 23
#     pkt4_hdr(reg, cnt)    = CP_TYPE4_PKT | cnt & 0x7F | parity(cnt) << 7
#                            | (reg & 0x3FFFF) << 8 | parity(reg) << 27
#
# THE precedence is the whole trap: `|` binds LOOSER than both `&` and `<<` in
# Python, so this is five independent contributions OR-ed together and NOT a
# left-to-right chain in which `cnt & 0x3FFF | parity(cnt)` is parenthesised
# wrongly. It also means `CP_TYPE7_PKT` (0x70000000) and `CP_TYPE4_PKT`
# (0x40000000) are already in the HIGH bit, and `parity << 23` / `<< 27` sit
# above them -- so these are genuinely u32 and not i32, which is why the port
# can hold them at all. `qc_pkt7_*` and `qc_pkt4_*` are diffed against CPython.
# ===========================================================================

def PKT7_CNT_MASK() -> U32: 16383
def PKT7_OP_MASK() -> U32: 127
def PKT4_CNT_MASK() -> U32: 127
def PKT4_REG_MASK() -> U32: 262143

def pkt7_hdr(+opcode: U32, +cnt: U32) -> U32:
  U32.or(U32.or(U32.or(U32.or(CP_TYPE7_PKT(), U32.and(cnt, PKT7_CNT_MASK())),
                   U32.shln(parity(cnt), 15n)),
         U32.shln(U32.and(opcode, PKT7_OP_MASK()), 16n)),
         U32.shln(parity(opcode), 23n))

def pkt4_hdr(+reg: U32, +cnt: U32) -> U32:
  U32.or(U32.or(U32.or(U32.or(CP_TYPE4_PKT(), U32.and(cnt, PKT4_CNT_MASK())),
                   U32.shln(parity(cnt), 7n)),
         U32.shln(U32.and(reg, PKT4_REG_MASK()), 8n)),
         U32.shln(parity(reg), 27n))

# ===========================================================================
# ops_qcom.py:57 and :59 -- THE COUNT OF A `cmd`/`reg`.
#
#     self.q(pkt7_hdr(opcode, sum(x.dtype.itemsize // 4 if isinstance(x, UOp)
#                                 else 1 for x in vals)), *vals)
#
# So a UOp argument counts `itemsize // 4` WORDS and a bare int counts ONE,
# and the header's count is the sum. `qwords` is that sum over the two kinds,
# and it is the second half of what makes a cmd header correct -- `qc_qwords_*`
# is the row that says a `dtypes.u32` buffer is ONE word and not zero.
# ===========================================================================

def ITEMSIZE_TO_WORDS() -> U32: 4

type Qw is Data:
  Qw{u: Bool, sz: U32}

def qwords.is(uop: Bool, itemsize: U32) -> U32:
  Bool.pick(U32, uop, U32.div(itemsize, ITEMSIZE_TO_WORDS()), 1)

def qwords.go(n: Nat, +acc: U32, us: List<&2, Qw>) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match us:
        case Nil{}: acc
        case Qw{u, sz} <> t: qwords.go(m, U32.add(acc, qwords.is(u, sz)), t)

def byte_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{b}: b
    case None{}: 0

def read_byte(bs: List<&2, U32>, off: U32) -> U32:
  byte_of(List.get(&2, U32, bs, U32.to_nat(off)))

def read_lib(+bs: List<&2, U32>, +off: U32) -> U32:
  U32.or(U32.or(read_byte(bs, off),
                U32.shln(read_byte(bs, U32.add(off, 1)), 8n)),
         U32.or(U32.shln(read_byte(bs, U32.add(off, 2)), 16n),
                U32.shln(read_byte(bs, U32.add(off, 3)), 24n)))

# APPEND and no reverse: `List.append(a, A, xs, ys)` IS `xs ++ ys`, so
# `List.append(acc, [x])` already puts x at the END. The first version reversed
# at the end as well and printed every word list backwards.
def read_words.go(n: Nat, +bs: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: read_words.go(m, bs, U32.add(off, 4),
      List.append(&2, U32, acc, [read_lib(bs, off)]))

type Kf is Data:
  Kf{nm: String, sh: U32, mk: U32}

def kgsl_flags() -> List<&2, Kf>:
  [Kf{"KGSL_CONTEXT_PRIORITY", 12, 61440},
   Kf{"KGSL_CONTEXT_PREEMPT_STYLE", 25, 234881024},
   Kf{"KGSL_MEMALIGN", 16, 16711680},
   Kf{"KGSL_CACHEMODE", 26, 201326592}]

def Kf.nm(x: Kf) -> String:
  match x:
    case Kf{nm, sh, mk}: nm

def Kf.sh(x: Kf) -> U32:
  match x:
    case Kf{nm, sh, mk}: sh

def Kf.mk(x: Kf) -> U32:
  match x:
    case Kf{nm, sh, mk}: mk

def kgsl_ix.put(hit: Bool, at: U32, got: U32) -> U32:
  Bool.pick(U32, hit, at, got)

def kgsl_ix.go(n: Nat, +nm: String, vs: List<&2, Kf>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match vs:
        case Nil{}: got
        case Kf{nn, sh, mk} <> t: kgsl_ix.go(m, nm, t, U32.add(at, 1),
          kgsl_ix.put(String.eq(nn, nm), at, got))

def NO_SUCH_FLAG() -> U32: 4294967295

def kgsl_ix(+nm: String) -> U32: kgsl_ix.go(List.length(&2, Kf, kgsl_flags()), nm, kgsl_flags(), 0, NO_SUCH_FLAG())

def kgsl_of(m: Maybe<&2, Kf>) -> Kf:
  match m:
    case Some{s}: s
    case None{}: Kf{"", 0, 0}

def kgsl_at(nm: String) -> Kf: kgsl_of(List.get(&2, Kf, kgsl_flags(), U32.to_nat(kgsl_ix(nm))))

def kgsl_shift(+nm: String) -> U32: Kf.sh(kgsl_at(nm))
def kgsl_mask(+nm: String) -> U32: Kf.mk(kgsl_at(nm))

def kgsl_name_of(m: Maybe<&2, Kf>) -> String:
  match m:
    case Some{s}: Kf.nm(s)
    case None{}: "?"

def FLAG_PREEMPT() -> String: "KGSL_CONTEXT_PREEMPT_STYLE"
def FLAG_CACHEMODE() -> String: "KGSL_CACHEMODE"
# ===========================================================================
# STAGE 2 -- `QCOMProgramData` (:206-283) and `qcom_build_program` (:285-292).
#
# WHY this half gates. `_parse_lib` is a BINARY walk over the shader blob, and
# the walks have THREE exits each: a length bound, a zero-length terminator, and
# -- for the constants -- a different bound (`image_offset`, not `len(lib)`). A
# port that honours only the first invents buffer descriptors and mis-sizes the
# constant upload. All three are in `walk.alive` and `cwalk.alive` and all three
# have a row.
#
# The second thing worth saying out loud: THE TWO BRANCHES DISAGREE.
#
#   :228 (NIR)   tex_off, ibo_off, samp_off = 2048, 2048 + 0x40*tex_cnt, 2048 + 0x40*(tex_cnt + ibo_cnt)
#   :272 (CL)    ibo_off, tex_off, samp_off = 2048, 2048 + 0x40*ibo_cnt, 2048 + 0x40*tex_cnt + 0x40*ibo_cnt
#
# `tex_off` and `ibo_off` are SWAPPED between them, and the CL branch's middle
# term counts `ibo_cnt` while the NIR branch's counts `tex_cnt`. The
# `samp_off` agrees by reordering. `qc_off_swapped` is the row that says so: it
# is the only way to notice a port that reads the two branches as one rule.
# ===========================================================================

# --- the fixed offsets ops_qcom.py reads out of the blob, with Python lines ---
def OFF_REG_DESC() -> U32: 52       # 0x34, :282
def OFF_HAS_CONSTS() -> U32: 176    # 0xb0, :274
def OFF_CONST_TAB() -> U32: 172     # 0xac, :275
def OFF_IMAGE() -> U32: 192         # 0xc0, :242
def OFF_IMAGE_SIZE() -> U32: 256    # 0x100, :241
def OFF_IMAGE_DESC() -> U32: 272    # 0x110, :245
def DESC_OFF_PRGOFF() -> U32: 196   # image_desc_off + 0xc4, :246
def DESC_OFF_BRSTK() -> U32: 264    # image_desc_off + 0x108, :246
def DESC_OFF_PVTMEM() -> U32: 200   # image_desc_off + 0xc8, :247
def DESC_OFF_SHMEM() -> U32: 216    # image_desc_off + 0xd8, :247
def DESC_OFF_SAMPCNT() -> U32: 220  # image_desc_off + 0xdc, :253
def DESC_OFF_KERNEL_DESC() -> U32: 344   # image_desc_off + 0x158, :262
def REG_OFF_FREGS() -> U32: 20      # reg_desc_off + 0x14, :283
def REG_OFF_HREGS() -> U32: 24      # reg_desc_off + 0x18, :283
def DESC_BYTES() -> U32: 32         # struct.unpack("8I"), :264
def CONST_BYTES() -> U32: 40        # the constant descriptor stride, :279
def SAMPLER_BYTES() -> U32: 8       # `8 * samp_cnt_in_file`, :262
def WORD_TO_BYTE() -> U32: 4        # `offset_words * 4`, :266
def CONST_STRIDE() -> U32: 40       # the constant walk's stride, :279
def NAME_ALIGN() -> U32: 4          # round_up(..., 4), :262
def BRSTK_HALVE() -> U32: 2         # `// 2`, :246
def ALIGN_ZERO() -> U32: 2048       # the shared `2048` in both offset rules
def TEX_BLOCK() -> U32: 64          # `0x40`, :228 and :272

def pd.shared_unit(+shmem: U32) -> U32:
  Bool.pick(U32, U32.is_eq(shmem, 0), 1, H.floordiv_u32(U32.sub(shmem, 1), 1024))

def pd.regs_terms(+fregs: U32, +hregs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.add(fregs, H.floordiv_u32(H.round_up_u32(hregs, 2), 2)), 0), 1,
    U32.add(fregs, H.floordiv_u32(H.round_up_u32(hregs, 2), 2)))

# `384 * 32` and `* 128` as their own defs so the two halves of the `min` share
# ONE transcription of the division.
def REGS_TOTAL() -> U32: 12288
def REGS_BLOCK() -> U32: 128

def pd.thread_cap(+fregs: U32, +hregs: U32) -> U32:
  U32.mul(H.floordiv_u32(REGS_TOTAL(), U32.mul(pd.regs_terms(fregs, hregs), REGS_BLOCK())), REGS_BLOCK())

type Bi is Data:
  Bi{off: U32, typ: U32}

type Ci is Data:
  Ci{val: U32, off: U32, sz: U32}

type Pd is Data:
  Pd{image_size: U32, image_offset: U32, image_desc_off: U32, prg_offset: U32,
     brnchstck: U32, pvtmem: U32, shmem: U32, samp_cnt: U32, samp_in_file: U32,
     tex_cnt: U32, ibo_cnt: U32, fregs: U32, hregs: U32, bdoff: U32,
     bins: List<&2, Bi>, consts: List<&2, Ci>}

def Pd.image_size(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: image_size

def Pd.image_offset(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: image_offset

def Pd.image_desc_off(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: image_desc_off

def Pd.prg_offset(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: prg_offset

def Pd.brnchstck(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: brnchstck

def Pd.samp_in_file(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: samp_in_file

def Pd.of() -> Pd:
  Pd{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Nil{}, Nil{}}

type Wb is Data:
  Wb{off: U32, seen: U32, alive: Bool, bins: List<&2, Bi>}

def Wb.off(w: Wb) -> U32:
  match w:
    case Wb{off, seen, alive, bins}: off

def Wb.seen(w: Wb) -> U32:
  match w:
    case Wb{off, seen, alive, bins}: seen

def Wb.alive(w: Wb) -> Bool:
  match w:
    case Wb{off, seen, alive, bins}: alive

def Wb.bins(w: Wb) -> List<&2, Bi>:
  match w:
    case Wb{off, seen, alive, bins}: bins

def Wb.of() -> Wb: Wb{0, 0, True{}, Nil{}}

# THE THREE EXITS, and `desc.alive` is where two of them live. `length == 0` is
# the TERMINATOR and `off + 32 > len(lib)` is the BOUND; a walk that honours
# only the bound reads the zeroed tail of the blob as a descriptor with
# `length == 0`, `offset_words == 0`, `typ == 0` -- i.e. a `BUFTYPE_BUF` at
# offset 0 -- and inflates `buf_offs` by one. `qc_bin_terminator` is the row.
def desc.alive(+off: U32, +bs: List<&2, U32>, +st: Wb) -> Bool:
  Bool.and(U32.is_le(U32.add(off, DESC_BYTES()), U32.from_nat(List.length(&2, U32, bs))),
           Bool.not(U32.is_eq(read_lib(bs, off), 0)))

def desc.next.at(alive: Bool, +st: Wb, +bs: List<&2, U32>) -> Wb:
  Bool.pick(Wb, alive,
    Wb{U32.add(Wb.off(st), read_lib(bs, Wb.off(st))), U32.add(Wb.seen(st), 1), True{},
       List.append(&2, Bi, Wb.bins(st),
                   [Bi{U32.mul(read_lib(bs, U32.add(Wb.off(st), 12)), WORD_TO_BYTE()),
                       read_lib(bs, U32.add(Wb.off(st), 28))}])},
    Wb{Wb.off(st), Wb.seen(st), False{}, Wb.bins(st)})

def desc.walk(n: Nat, +bs: List<&2, U32>, +st: Wb) -> Wb:
  match n:
    case 0n: st
    case 1n+m: desc.walk(m, bs, desc.next.at(desc.alive(Wb.off(st), bs, st), st, bs))

def desc.bdoff(+image_desc_off: U32, +name_len: U32, +samp_in_file: U32) -> U32:
  U32.add(H.round_up_u32(U32.add(U32.add(image_desc_off, DESC_OFF_KERNEL_DESC()), name_len), NAME_ALIGN()),
          U32.mul(samp_in_file, SAMPLER_BYTES()))

def Bi.off(b: Bi) -> U32:
  match b:
    case Bi{off, typ}: off

def Bi.typ(b: Bi) -> U32:
  match b:
    case Bi{off, typ}: typ

# :268 `self.buf_offs = [off for off, typ in binfos if typ not in {TEX, IBO}]`.
# An UNKNOWN type is kept, which is the whole behaviour of `typ not in {...}`
# and the reason `buftype_of`'s miss answers BUFTYPE_BUF.
def desc.is_keep(+typ: U32) -> Bool:
  Bool.not(Bool.or(U32.is_eq(typ, BUFTYPE_TEX()), U32.is_eq(typ, BUFTYPE_IBO())))

def desc.keep.put(+b: Bi, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, desc.is_keep(Bi.typ(b)), List.append(&2, U32, acc, [Bi.off(b)]), acc)

def desc.buf_offs.go(n: Nat, bs: List<&2, Bi>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case b <> t: desc.buf_offs.go(m, t, desc.keep.put(b, acc))

def desc.count.put(+want: U32, +b: Bi, +n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(Bi.typ(b), want), U32.add(n, 1), n)

def desc.count(n: Nat, +want: U32, bs: List<&2, Bi>, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case b <> t: desc.count(m, want, t, desc.count.put(want, b, acc))

def desc.count.of(want: U32, +bs: List<&2, Bi>) -> U32:
  desc.count(List.length(&2, Bi, bs), want, bs, 0)

# ===========================================================================
# THE CONSTANT WALK, :274-279. A DIFFERENT bound: `cdoff + 40 <= image_offset`,
# where `image_offset` is a field of the blob and NOT `len(lib)`. A port that
# reaches for the list length here walks off the end, and one that uses the
# right bound with the wrong stride walks the wrong descriptors.
#
#     cnst, offset_words, _, is32 = unpack('I', lib[cdoff:cdoff+4])[0], *unpack('III', lib[cdoff+16:cdoff+28])
#     self.consts_info.append((cnst, offset_words * (sz_bytes := 2 << is32), sz_bytes))
#     cdoff += 40
#
# `is32` is a FLAG and `sz_bytes := 2 << is32` is 2 or 4 -- so a constant is
# either a u16 pair or a u32, and the offset is in BYTES. `qc_const_stride` and
# `qc_const_sz` are the two rows.
# ===========================================================================

# `bound` is the U32 the constant walk is bounded BY -- `image_offset`, not
# `len(lib)`. It is a FIELD because :276 reads it out of the blob and the walk
# starts at :275's `cdoff`, and getting the two the wrong way round is exactly
# the bug the walk is here to prevent.
type Cw is Data:
  Cw{off: U32, seen: U32, on: Bool, bound: U32, cs: List<&2, Ci>}

def Cw.off(w: Cw) -> U32:
  match w:
    case Cw{off, seen, on, bound, cs}: off

def Cw.seen(w: Cw) -> U32:
  match w:
    case Cw{off, seen, on, bound, cs}: seen

def Cw.on(w: Cw) -> Bool:
  match w:
    case Cw{off, seen, on, bound, cs}: on

def Cw.bound(w: Cw) -> U32:
  match w:
    case Cw{off, seen, on, bound, cs}: bound

def Cw.cs(w: Cw) -> List<&2, Ci>:
  match w:
    case Cw{off, seen, on, bound, cs}: cs

def Cw.of() -> Cw: Cw{0, 0, True{}, 0, Nil{}}

def const.is32(+bs: List<&2, U32>, +off: U32) -> U32: read_lib(bs, U32.add(off, 24))

def const.size(+bs: List<&2, U32>, +off: U32) -> U32: U32.shln(2, U32.to_nat(const.is32(bs, off)))

def const.alive(+off: U32, +bound: U32) -> Bool: U32.is_le(U32.add(off, CONST_BYTES()), bound)

def const.next.at(on: Bool, +st: Cw, +bs: List<&2, U32>) -> Cw:
  Bool.pick(Cw, on,
    Cw{U32.add(Cw.off(st), CONST_STRIDE()), U32.add(Cw.seen(st), 1), True{}, Cw.bound(st),
       List.append(&2, Ci, Cw.cs(st),
                   [Ci{read_lib(bs, Cw.off(st)),
                       U32.mul(read_lib(bs, U32.add(Cw.off(st), 16)), const.size(bs, Cw.off(st))),
                       const.size(bs, Cw.off(st))}])},
    Cw{Cw.off(st), Cw.seen(st), False{}, Cw.bound(st), Cw.cs(st)})

def const.walk(n: Nat, +bs: List<&2, U32>, +st: Cw) -> Cw:
  match n:
    case 0n: st
    case 1n+m: const.walk(m, bs, const.next.at(const.alive(Cw.off(st), Cw.bound(st)), st, bs))

def Ci.val(c: Ci) -> U32:
  match c:
    case Ci{val, off, sz}: val

def Ci.off(c: Ci) -> U32:
  match c:
    case Ci{val, off, sz}: off

def Ci.sz(c: Ci) -> U32:
  match c:
    case Ci{val, off, sz}: sz

def const.flat.at(+c: Ci, +acc: List<&2, String>) -> List<&2, String>:
  String.concat([U32.show(Ci.val(c)), "@", U32.show(Ci.off(c)), ":", U32.show(Ci.sz(c))]) <> acc

def const.flat.done(+acc: List<&2, String>) -> String:
  String.join(List.reverse(&2, String, acc), ";")

def const.flat.go(n: Nat, cs: List<&2, Ci>, +acc: List<&2, String>) -> String:
  match n:
    case 0n: const.flat.done(acc)
    case 1n+m:
      match cs:
        case Nil{}: const.flat.done(acc)
        case c <> t: const.flat.go(m, t, const.flat.at(c, acc))

def pd.parse.at(+bs: List<&2, U32>, +name_len: U32, image_offset: U32, image_size: U32,
                +ido: U32) -> Pd:
  Pd{image_size, image_offset, ido,
     read_lib(bs, U32.add(ido, DESC_OFF_PRGOFF())),
     H.floordiv_u32(read_lib(bs, U32.add(ido, DESC_OFF_BRSTK())), BRSTK_HALVE()),
     read_lib(bs, U32.add(ido, DESC_OFF_PVTMEM())),
     read_lib(bs, U32.add(ido, DESC_OFF_SHMEM())),
     Bool.pick(U32, U32.is_eq(read_lib(bs, U32.add(ido, DESC_OFF_SAMPCNT())), 0), 0,
               U32.add(read_lib(bs, U32.add(ido, DESC_OFF_SAMPCNT())), 1)),
     read_lib(bs, U32.add(ido, DESC_OFF_SAMPCNT())),
     0, 0,
     read_lib(bs, U32.add(read_lib(bs, OFF_REG_DESC()), REG_OFF_FREGS())),
     read_lib(bs, U32.add(read_lib(bs, OFF_REG_DESC()), REG_OFF_HREGS())),
     desc.bdoff(ido, name_len, read_lib(bs, U32.add(ido, DESC_OFF_SAMPCNT()))),
     Nil{}, Nil{}}

# the two walks, applied to the record the fixed offsets produced. Split out
# because `pd.parse.at` would need the same `bs` four times over and the
# record is already sixteen fields.
# the fourteen fixed-offset reads, in Python's order. `samp_cnt` is
# `samp_in_file + 1` when there is one (`:255-256`) and ZERO otherwise, which is
# not the same as `samp_in_file` -- fixture `pl_0` has one in the file and none
# counted, and `qc_pl_samp` is the row that tells them apart.
def pd.parse(+bs: List<&2, U32>, +name_len: U32) -> Pd:
  pd.parse.at(bs, name_len, read_lib(bs, OFF_IMAGE()), read_lib(bs, OFF_IMAGE_SIZE()),
              read_lib(bs, OFF_IMAGE_DESC()))

def pd.with_bins(p: Pd, +w: Wb) -> Pd:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}:
      Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
         samp_in_file, desc.count.of(BUFTYPE_TEX(), Wb.bins(w)), desc.count.of(BUFTYPE_IBO(), Wb.bins(w)),
         fregs, hregs, bdoff, Wb.bins(w), consts}

def pd.with_consts(p: Pd, +w: Cw) -> Pd:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}:
      Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
         samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, Cw.cs(w)}

def pd.has_consts(+bs: List<&2, U32>) -> Bool: Bool.not(U32.is_eq(read_lib(bs, OFF_HAS_CONSTS()), 0))

# the fuel for both walks. It is a BOUND, not a guess: the walks' own `alive`
# predicates stop them, and this only stops a malformed blob that claims
# `length < 32` forever. `ceildiv(len, 32) + 1` is enough for the descriptor
# walk and `len / 40 + 1` for the constant walk, because both strides are >= 32.
def fuel.of(+len: U32) -> Nat: U32.to_nat(U32.add(H.ceildiv_u32(len, DESC_BYTES()), 1))

def pd.const_walk(+bs: List<&2, U32>, +p: Pd) -> Cw:
  Bool.pick(Cw, pd.has_consts(bs),
    const.walk(fuel.of(Pd.image_offset(p)), bs,
      Cw{read_lib(bs, OFF_CONST_TAB()), 0, True{}, Pd.image_offset(p), Nil{}}),
    Cw{0, 0, False{}, Pd.image_offset(p), Nil{}})

# `pd.parse_full` IS `_parse_lib`: the fixed offsets, then the descriptor walk,
# then the constant walk. Its own def so the order of the three is one claim
# rather than three.
def pd.parse_full(+bs: List<&2, U32>, +name_len: U32) -> Pd:
  pd.with_consts(pd.with_bins(pd.parse(bs, name_len),
    desc.walk(fuel.of(U32.from_nat(List.length(&2, U32, bs))), bs,
              Wb{desc.bdoff(read_lib(bs, OFF_IMAGE_DESC()), name_len,
                            read_lib(bs, U32.add(read_lib(bs, OFF_IMAGE_DESC()), DESC_OFF_SAMPCNT()))),
                 0, True{}, Nil{}})), pd.const_walk(bs, pd.parse(bs, name_len)))
# ===========================================================================
# STAGE 2b -- `qcom_build_program` (:285-292) AND THE PROGRAM CACHE.
#
#     _qcom_program_cache: dict[tuple[bytes, tuple[str, ...]], tuple[QCOMProgramData, UOp]] = {}
#     def qcom_build_program(dev, prg, devs):
#       if (cached := _qcom_program_cache.get(key := (prg.src[3].arg, devs))) is None:
#         data = QCOMProgramData(dev, prg.to_elf())
#         image = bytes(data.image).ljust(round_up(len(data.image), 4), b"\x00")
#         buf = UOp.placeholder((len(image),), dtypes.u8, ..., tag="program")
#         cached = _qcom_program_cache[key] = (data, patch(buf, [], image))
#       return cached
#
# THE KEY IS A PAIR: `prg.src[3].arg` -- the COMPILER'S HASH of the shader --
# and `devs`, the tuple of device indices the image must live on. Two programs
# with the same source but different `devs` are DIFFERENT ENTRIES, because the
# second element is the device the buffer was allocated on. `qc_ck_devs_splits`
# is the row for that, and it is the reason the cache is not a string set.
#
# THERE IS NO EVICTION. Python's `_qcom_program_cache` is a module-level dict
# that grows for the life of the process and is never pruned. So the "entry that
# must NOT be evicted" the brief asks for is not a special case I invented: it
# is what the code does. `qc_ck_older_survives` builds A, then B, then asks for
# A AGAIN and requires that it is a HIT -- an implementation with an LRU, a
# size cap, or a "rebuild if the cache is full" arm fails that row, and one that
# simply never checks the cache before building fails `qc_ck_second_is_hit`.
#
# THE OTHER NEGATIVE: a cache that reports a hit without a build is only honest
# if the build is RECORDED. `Tr` exists so that "did this parse the blob again"
# is a question with an answer, and `qc_ck_nobuild_after_hit` reads the trace
# rather than the cache's own flag.
# ===========================================================================

def CALL_PARSE() -> U32: 0     # QCOMProgramData(dev, prg.to_elf())   :288
def CALL_PATCH() -> U32: 1      # patch(buf, [], image)                :291
def CALL_HIT() -> U32: 2        # the walrus found the key              :287
def CALL_MINT() -> U32: 3       # UOp.placeholder(... tag="program")    :290

type Call is Data:
  Call{k: U32, arg: U32}

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

type Tr is Data:
  Tr{calls: List<&2, Call>, refused: Bool}

def Tr.of() -> Tr: Tr{Nil{}, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, refused}: calls

def Tr.emit(+k: U32, +arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +refused}: Tr{List.append(&2, Call, calls, [Call{k, arg}]), refused}

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

# ===========================================================================
# THE CACHE KEY. `Ck` is the tuple `(prg.src[3].arg, devs)` and the equality is
# PAIRWISE, because that is what a tuple's `==` is and because `devs` is a LIST
# -- so two keys with the same hash element and a different device set are
# different keys, and a string-joined key would quietly merge them.
# ===========================================================================

type Ck is Data:
  Ck{hash: U32, ndevs: U32, devs: List<&2, U32>}

def Ck.hash(c: Ck) -> U32:
  match c:
    case Ck{hash, ndevs, devs}: hash

def Ck.devs(c: Ck) -> List<&2, U32>:
  match c:
    case Ck{hash, ndevs, devs}: devs

def Ck.of(hash: U32, +devs: List<&2, U32>) -> Ck:
  Ck{hash, U32.from_nat(List.length(&2, U32, devs)), devs}

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

def Ck.same_devs(+a: Ck, +b: Ck) -> Bool: u32_list_eq(Ck.devs(a), Ck.devs(b))

def Ck.eq(+a: Ck, +b: Ck) -> Bool:
  Bool.and(U32.is_eq(Ck.hash(a), Ck.hash(b)), Ck.same_devs(a, b))

# the ONE cache entry: the key, the DATA and the BUFFER, which is exactly the
# `(QCOMProgramData, UOp)` value the dict holds.
type Ce is Data:
  Ce{key: Ck, pd: Pd, buf: U32, t: Tr}

def Ce.key(c: Ce) -> Ck:
  match c:
    case Ce{key, pd, buf, t}: key

def Ce.pd(c: Ce) -> Pd:
  match c:
    case Ce{key, pd, buf, t}: pd

def Ce.buf(c: Ce) -> U32:
  match c:
    case Ce{key, pd, buf, t}: buf

def NO_ENTRY() -> U32: 4294967295

def ce.find.put(at: Nat, +want: Ck, e: Ce, +acc: U32) -> U32:
  Bool.pick(U32, Ck.eq(Ce.key(e), want), U32.from_nat(at), acc)

def ce.find.go(n: Nat, +at: Nat, +want: Ck, es: List<&2, Ce>, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match es:
        case Nil{}: acc
        case e <> t: ce.find.go(m, 1n+at, want, t,
          ce.find.put(at, want, e, acc))

def ce.find(want: Ck, +es: List<&2, Ce>) -> U32:
  ce.find.go(List.length(&2, Ce, es), 0n, want, es, NO_ENTRY())

# ===========================================================================
# `qcom_build_program`. THE three calls on the miss path, IN python'S order,
# and NONE of them on the hit path. `qc_ck_order` is the row that reads the
# trace; `qc_ck_nbuild` counts PARSE and `qc_ck_npatch` counts PATCH, and the
# pair is what says the miss path ran exactly once.
# ===========================================================================

# :289 `image = bytes(data.image).ljust(round_up(len(data.image), 4), b"\x00")`.
# The image is padded to a multiple of FOUR with ZEROES, and the buffer's length
# is the PADDED length -- `UOp.placeholder((len(image),), ...)` reads `len` of
# the padded object. So a 3-byte shader image becomes a 4-byte allocation.
def qcom.pad_len(+nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

def qcom.mint(+nbytes: U32, ndevs: U32) -> Call: Call{CALL_MINT(), nbytes}

# the miss path. `next_num` is `UOp.unique_num`, the global allocation counter,
# and it is the buffer's id.
def qcom.build.go(+hash: U32, +devs: List<&2, U32>, +name_len: U32, +bs: List<&2, U32>,
                  +next_num: U32, +es: List<&2, Ce>, +p: Pd) -> Ce:
  Ce{Ck.of(hash, devs), p, next_num,
     Tr.emit(CALL_PATCH(), qcom.pad_len(Pd.image_size(p)),
       Tr.emit(CALL_MINT(), next_num,
         Tr.emit(CALL_PARSE(), Pd.image_size(p), Tr.of())))}

def qcom.push(e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  List.append(&2, Ce, es, [e])

# the entry point. `Bool.pick` cannot gate a self-call and cannot gate the
# BUILD -- the build is an expression in one arm and the cache read is in the
# other -- so the hit and the miss are two `Bool.pick`s over the same lookup,
# and `qc_ck_hit_emits_nothing` is what says the hit arm records only HIT.
def ce.get(m: Maybe<&2, Ce>) -> Ce:
  match m:
    case Some{+s}: Ce{Ce.key(s), Ce.pd(s), Ce.buf(s), Tr.emit(CALL_HIT(), Ce.buf(s), Tr.of())}
    case None{}: Ce{Ck{0, 0, Nil{}}, Pd.of(), 0, Tr.of()}

def qcom.hit.at(ix: Nat, +es: List<&2, Ce>) -> Ce: ce.get(List.get(&2, Ce, es, ix))

def qcom.build(+hash: U32, +devs: List<&2, U32>, +name_len: U32, +bs: List<&2, U32>,
               +next_num: U32, +es: List<&2, Ce>) -> Ce:
  qcom.build.go(hash, devs, name_len, bs, next_num, es, pd.parse_full(bs, name_len))

# `bs` is `prg.to_elf()`, the shader binary this parse walks. It is a PARAMETER
# and not a fixture baked into the port, so the same `qcom.build` serves every
# gate blob.
def ce.find.nat(want: Ck, +es: List<&2, Ce>) -> Nat: U32.to_nat(ce.find(want, es))

def qcom.hit(want: Ck, +es: List<&2, Ce>) -> Ce:
  qcom.hit.at(ce.find.nat(want, es), es)

def ce.push(+e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  List.append(&2, Ce, es, [e])

# `_qcom_program_cache[key] = value` IS a MAP ASSIGNMENT, so storing a key that
# is already there REPLACES it and the LENGTH DOES NOT GROW. A list append is not
# a map assignment and the difference is measurable: pushing the six gate entries
# unconditionally gives six slots for four programs. `ce.put` is the assignment;
# `ce.push` stays for the case that genuinely grows. `qc_ck_len` is the row.
def ce.put.at(fresh: Bool, e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  Bool.pick(List<&2, Ce>, fresh, ce.push(e, es), es)

def Tr.kinds.go(n: Nat, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.kinds.go(m, t, List.append(&2, U32, acc, [kk]))

def tr.cat(+a: List<&2, Call>, b: List<&2, Call>) -> List<&2, Call>:
  List.append(&2, Call, a, b)

def tr.seq.go(n: Nat, steps: List<&2, Tr>, +acc: List<&2, Call>) -> List<&2, Call>:
  match n:
    case 0n: acc
    case 1n+m:
      match steps:
        case Nil{}: acc
        case s <> t: tr.seq.go(m, t, tr.cat(acc, Tr.calls(s)))

def CALL_CMD7() -> U32: 4        # self.cmd(opcode, *vals)          :57
def CALL_CMD4() -> U32: 5        # self.reg(reg, *vals)             :59
def CALL_IOCTL() -> U32: 6       # an IOCTL_KGSL_* or an mmap        :319-368
def CALL_SYSCALL() -> U32: 7     # System.write_sysfs               :335

def CALL_OPEN() -> U32: 0        # FileIOInterface('/dev/kgsl-3d0')  :315
def CALL_DRAWCTXT() -> U32: 1    # IOCTL_KGSL_DRAWCTXT_CREATE        :319
def CALL_SETPOWER() -> U32: 2    # IOCTL_KGSL_SETPROPERTY           :324
def CALL_DEVINFO() -> U32: 3     # IOCTL_KGSL_DEVICE_GETPROPERTY     :328
def CALL_GPUOBJ() -> U32: 4      # IOCTL_KGSL_GPUOBJ_ALLOC           :358
def CALL_MMAP() -> U32: 5        # self.fd.mmap(...)                 :359
def CALL_MEMSET() -> U32: 6      # ctypes.memset                     :361
def CALL_MAPUSER() -> U32: 7     # IOCTL_KGSL_MAP_USER_MEM           :368
def CALL_SHAREDFREE() -> U32: 8  # IOCTL_KGSL_SHAREDMEM_FREE         :376
def CALL_GPUOBJFREE() -> U32: 9  # IOCTL_KGSL_GPUOBJ_FREE            :378
def CALL_MUNMAP() -> U32: 10     # FileIOInterface.munmap            :379
def CALL_CDSPF() -> U32: 11      # dcache_flush().fxn(...)           :366
def CALL_DCFLUSH() -> U32: 12    # dcache_flush() itself            :23
def CALL_READTS() -> U32: 13     # IOCTL_..._READTIMESTAMP_CTXTID    :383
def CALL_WAITTS() -> U32: 14     # IOCTL_..._WAITTIMESTAMP_CTXTID    :385
def CALL_SYSFS() -> U32: 15      # System.write_sysfs                :335

# ===========================================================================
# THE cache flush, :61-70. FOUR independent conditionals and one def, because
# `memory_barrier` (:70) is `self._cache_flush(True, True, True, True)` and
# `exec` (:192) is `self._cache_flush(True, False, False, False)`. So the two
# callers differ in three of the four flags and `qc_flush_barrier_vs_exec` is the
# row that says the difference is three and not four.
#
#     if write_back: self.cmd(CP_EVENT_WRITE, CACHE_FLUSH_TS, dummy, 0)
#     if invalidate: self.cmd(CP_EVENT_WRITE, CACHE_INVALIDATE)
#     if memsync:    self.cmd(CP_WAIT_MEM_WRITES)
#     if sync:       self.cmd(CP_WAIT_FOR_IDLE)
#
# THE order is not the parameter order: Python tests write_back, invalidate,
# sync, memsync and issues memsync BEFORE sync. `flush.go` is a fold over the
# four flags in ISSUE order and `qc_flush_order_*` reads the result.
# ===========================================================================

def FLUSH_WRITE_BACK() -> U32: 0
def FLUSH_INVALIDATE() -> U32: 1
def FLUSH_MEMSYNC() -> U32: 2
def FLUSH_SYNC() -> U32: 3

# the OPERATION each conditional issues, and its word count. write_back is a
# FOUR-word `cmd` (opcode, event, address, 0) and the other three are ONE.
def flush.op.at(which: Nat) -> U32:
  match which:
    case 0n: CP_EVENT_WRITE()
    case 1n: CP_EVENT_WRITE()
    case 2n: CP_WAIT_MEM_WRITES()
    case _: CP_WAIT_FOR_IDLE()

def flush.op(+which: U32) -> U32: flush.op.at(U32.to_nat(which))

def flush.cnt.at(which: Nat) -> U32:
  match which:
    case 0n: 4
    case _: 1

def at_of.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{s}: s
    case None{}: 0

def at_of(at: List<&2, U32>, n: Nat) -> U32: at_of.at(List.get(&2, U32, at, n))

# `which` is RESOLVED by the caller and passed in, because a `match` may not
# scrutinise a call and `at_of` is one.
def flush.step(which: U32, on: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, on, Tr.emit(CALL_CMD7(), flush.op(which), t), t)

# THE INDEX LIST IS WALKED IN PARALLEL with the flag list, and that is the only
# way this goes in Bend: a countdown arm may not read its own fuel twice (see
# bend2-constraints.md, the "+U32 that grows" rule), and `at_of(at, m)` is
# exactly such a second read. `ISSUE_AT()` is in ISSUE order, so the head of the
# parallel list IS the resolved `which`.
def flush.go(n: Nat, flags: List<&2, Bool>, +at: List<&2, U32>, +t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m:
      match flags:
        case Nil{}: t
        case f <> r:
          match at:
            case Nil{}: t
            case a <> rest: flush.go(m, r, rest, flush.step(a, f, t))

def ISSUE_AT() -> List<&2, U32>: [0, 1, 2, 3]

def flush.of(+flags: List<&2, Bool>, +t: Tr) -> Tr:
  flush.go(List.length(&2, Bool, flags), flags, ISSUE_AT(), t)

# ===========================================================================
# `cmd` AND `reg`. ONE def each, because they differ in the HEADER and nothing
# else: `cmd` builds `pkt7_hdr(opcode, cnt)` and `reg` builds
# `pkt4_hdr(reg, cnt)`, and both append the header to the same `q`.
# ===========================================================================

# The COUNT is not in the trace -- it is in the HEADER, and `q.hdr7` builds it.
# Keeping it out of the record is deliberate: one trace entry per CALL, and the
# header is a separate pure builder with its own rows (`qc_pkt7_*`).
def q.cmd(opcode: U32, t: Tr) -> Tr: Tr.emit(CALL_CMD7(), opcode, t)
def q.reg(regno: U32, t: Tr) -> Tr: Tr.emit(CALL_CMD4(), regno, t)

def RF_RESOURCES() -> U32: 0
def RF_DIMS() -> U32: 1
def RF_GPU() -> U32: 2
def RF_EVENT7() -> U32: 3

# :118 `if data.max_threads < prod(local_size): raise`. `prod(local_size)` is
# ls[0]*ls[1]*ls[2], so a 64-wide local size already needs 64 threads.
def rf.resources(+max_threads: U32, +lx: U32, +ly: U32, +lz: U32) -> Bool:
  U32.is_lt(max_threads, U32.mul(U32.mul(lx, ly), lz))

# :119 `any(g*l>mx for g,l,mx in zip(global_size, local_size, [65536]*3)) and
# any(l>mx for l,mx in zip(local_size, [1024]*3))`. TWO `any`s AND-ed, so a
# launch with a huge local size but a small total is ACCEPTED -- that is the
# fixture `qc_rf_dim_bigl` and it is the row a "one dimension" transcription
# would fail.
def DIM_TOTAL() -> U32: 65536
def DIM_LOCAL() -> U32: 1024

# TWO LISTS WALKED IN LOCKSTEP, because `zip` is a fold over both and Bend has no
# `zip`. `m` is read once -- the fuel -- and `mx` is `+` because the `any` has to
# hand it to the self-call on every step.
def rf.any_over.go(n: Nat, +gs: List<&2, U32>, +ls: List<&2, U32>, +mx: U32, +hit: Bool) -> Bool:
  match n:
    case 0n: hit
    case 1n+m:
      match gs:
        case Nil{}: hit
        case g <> tg:
          match ls:
            case Nil{}: hit
            case l <> tl: rf.any_over.go(m, tg, tl, mx,
              Bool.or(hit, Bool.not(U32.is_le(U32.mul(g, l), mx))))

def rf.any_over(+gs: List<&2, U32>, +ls: List<&2, U32>, +mx: U32) -> Bool:
  rf.any_over.go(List.length(&2, U32, gs), gs, ls, mx, False{})

def rf.dims(+gs: List<&2, U32>, +ls: List<&2, U32>) -> Bool:
  Bool.and(rf.any_over(gs, ls, DIM_TOTAL()), rf.any_over(ls, ls, DIM_LOCAL()))

# :74 `if self.dev.gpu_id[:2] < (7, 3)` and :332 `if self.gpu_id[:2] >= (7, 3)`.
# THE same predicate with the opposite sense, and every accepted gpu is on one
# side of it. `rf.gpu_ge73(g0, g1)` is the shared def so the two cannot drift.
def rf.gpu_ge73(+g0: U32, +g1: U32) -> Bool:
  Bool.or(U32.is_gt(g0, 7), Bool.and(U32.is_eq(g0, 7), U32.is_ge(g1, 3)))

def Tr.refuse(kind: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +refused}: Tr{calls, Bool.or(refused, True{})}

# ===========================================================================
# `exec` (:115-192). THE REGISTER SEQUENCE, in Python's order, and the two
# FORKS: the three `if data.samp_cnt / tex_cnt / ibo_cnt > 0` blocks and the
# `if data.NIR:` at :184. `qc_exec_order_*` is the subsequence test over the
# trace; `qc_exec_forks_*` says which of the four arms fired.
# ===========================================================================
def exec.pre1.at(which: Nat, t: Tr) -> Tr:
  match which:
    case 0n: q.cmd(CP_SET_MARKER(), t)
    case 1n: q.reg(REG_A6XX_SP_UPDATE_CNTL(), t)
    case 2n: q.reg(REG_A6XX_SP_UPDATE_CNTL(), t)
    case 3n: q.reg(REG_A6XX_SP_CS_TSIZE(), t)
    case 4n: q.reg(REG_A6XX_SP_CS_USIZE(), t)
    case 5n: q.reg(REG_A6XX_SP_MODE_CNTL(), t)
    case 6n: q.reg(REG_A6XX_SP_PERFCTR_SHADER_MASK(), t)
    case 7n: q.reg(REG_A6XX_TPL1_MODE_CNTL(), t)
    case _: q.reg(REG_A6XX_TPL1_DBG_ECO_CNTL(), t)

def exec.pre1(which: U32, t: Tr) -> Tr: exec.pre1.at(U32.to_nat(which), t)


def exec.pre2(n: Nat, +at: List<&2, U32>, +t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m:
      match at:
        case Nil{}: t
        case a <> rest: exec.pre2(m, rest, exec.pre1(a, t))


def PRE_AT() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 7, 8]


def exec.pre() -> Tr:
  # :128-138 -- marker, SP_UPDATE_CNTL twice, TSIZE, USIZE, MODE_CNTL,
  # PERFCTR_SHADER_MASK, TPL1_MODE_CNTL, TPL1_DBG_ECO_CNTL, WAIT_FOR_IDLE
  Tr.emit(CALL_CMD7(), CP_WAIT_FOR_IDLE(), exec.pre2(9n, PRE_AT(), Tr.of()))

# :140-143 NDRANGE_0, :145-150 CS_CNTL_0, :153-156 the two CP_LOAD_STATE6_FRAG,
# :158 SP_REG_PROG_ID_0, :160 PVT_MEM_STACK_OFFSET, :163 CS_INSTR_SIZE.
def exec.mid1.at(which: Nat, +t: Tr) -> Tr:
  match which:
    case 0n: q.reg(REG_A6XX_SP_CS_NDRANGE_0(), t)
    case 1n: q.reg(REG_A6XX_SP_CS_CNTL_0(), t)
    case 2n: q.cmd(CP_LOAD_STATE6_FRAG(), t)
    case 3n: q.cmd(CP_LOAD_STATE6_FRAG(), t)
    case 4n: q.reg(REG_A6XX_SP_REG_PROG_ID_0(), t)
    case 5n: q.reg(REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET(), t)
    case _: q.reg(REG_A6XX_SP_CS_INSTR_SIZE(), t)

def exec.mid1(which: U32, +t: Tr) -> Tr: exec.mid1.at(U32.to_nat(which), t)

def exec.mid.go(n: Nat, +at: List<&2, U32>, +t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m:
      match at:
        case Nil{}: t
        case a <> rest: exec.mid.go(m, rest, exec.mid1(a, t))
def MID_AT() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6]


def exec.mid() -> Tr: exec.mid.go(7n, MID_AT(), exec.pre())





# THE THREE CONDITIONAL BLOCKS. Each is a LOAD_STATE6_FRAG followed by a BASE
# register, in that order, and the counts are 2 and 1. `qc_exec_ibo_is_two`
# is the row that says the IBO block loads TWO words (the header plus the
# address) where the sampler block also loads two -- and that the block is
# emitted only when its count is non-zero.
def exec.base.at(which: Nat) -> U32:
  match which:
    case 0n: REG_A6XX_SP_CS_SAMPLER_BASE()
    case 1n: REG_A6XX_SP_CS_TEXMEMOBJ_BASE()
    case _: REG_A6XX_SP_CS_UAV_BASE()

def exec.base(+which: U32) -> U32: exec.base.at(U32.to_nat(which))

def exec.block(which: U32, +t: Tr) -> Tr:
  q.reg(exec.base(which), q.cmd(CP_LOAD_STATE6_FRAG(), t))
def BLOCK_SAMPLER() -> U32: 0


# THE sampler block is three calls, NOT two. :165-170 is a LOAD_STATE6_FRAG, then
# SP_CS_SAMPLER_BASE, then `self.reg(REG_A6XX_TPL1_CS_BORDER_COLOR_BASE,
# <the 0x1000 border_color placeholder>)`. The port had two and
# `qc_exec_full_n` is the row that said so: it read 26 where CPython's own
# `QCOMComputeQueue.exec` issues 27. The tex and ibo blocks really are two, which
# is why a single `exec.block` could not serve all three.
def exec.samp(+samp_cnt: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_gt(samp_cnt, 0),
    q.reg(REG_A6XX_TPL1_CS_BORDER_COLOR_BASE(),
      exec.block(BLOCK_SAMPLER(), t)), t)
def BLOCK_TEX() -> U32: 1


def exec.tex(+tex_cnt: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_gt(tex_cnt, 0), exec.block(BLOCK_TEX(), t), t)
def BLOCK_UAV() -> U32: 2


def exec.ibo(+ibo_cnt: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_gt(ibo_cnt, 0), exec.block(BLOCK_UAV(), t), t)





# :182 `self.reg(REG_A6XX_SP_CS_CONFIG, ...)` then the `if data.NIR:` fork at
# :184: TWO more registers plus a CP_EXEC_CS, OR a single CP_RUN_OPENCL.
# THE nir tail is two calls, NOT three. :185-187 is ONE `self.reg` carrying TWO
# `qreg` words -- `a6xx_sp_cs_const_config_0(...)` AND `a6xx_sp_cs_wge_cntl(...)`
# -- and there is no `REG_A6XX_SP_CS_WGE_CNTL` write anywhere in the file (the
# oracle's `refs` walk says so: it is not one of the 62 mesa constants).
# `qc_exec_nir_kinds` is the row, and it was written after getting this wrong.
def exec.nir_tail(+t: Tr) -> Tr:
  q.cmd(CP_EXEC_CS(), q.reg(REG_A6XX_SP_CS_CONST_CONFIG_0(), t))

def exec.tail(nir: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, nir, exec.nir_tail(t), q.cmd(CP_RUN_OPENCL(), t))


# `exec` whole, with the two REFUSALS in front of it exactly as Python has them
# (:118 and :120, before any register is written) and the trailing cache flush
# (:192) after it.
def FLUSH_EXEC() -> List<&2, Bool>: [True{}, False{}, False{}, False{}]

# :182 `self.reg(REG_A6XX_SP_CS_CONFIG, ...)` is UNCONDITIONAL -- it is written
# for both the NIR and the CL arm and it is INSIDE neither `if`. It gets its own
# def so a port that folds it into `exec.nir_tail` -- which is what the first
# version did -- loses it from the CL trace, and `qc_exec_cl_regs` is the row.
def exec.config(t: Tr) -> Tr: q.reg(REG_A6XX_SP_CS_CONFIG(), t)

# THE WHOLE SEQUENCE, in Python's order: pre (:128-138), mid (:140-163), the
# three conditional blocks (:165-180), CS_CONFIG (:182), the fork (:184-190) and
# the trailing cache flush (:192). The first version of this skipped `pre`
# ENTIRELY and `qc_exec_cl_n` is the row that said so.
def exec.of3(+samp_cnt: U32, +tex_cnt: U32, +ibo_cnt: U32, nir: Bool, t: Tr) -> Tr:
  flush.of(FLUSH_EXEC(), exec.tail(nir, exec.config(exec.ibo(ibo_cnt,
    exec.tex(tex_cnt, exec.samp(samp_cnt, exec.mid()))))))

def exec.of2(dim: Bool, refused: Bool, samp_cnt: U32, tex_cnt: U32, ibo_cnt: U32,
             nir: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, dim, Tr.refuse(RF_DIMS(), t), exec.of3(samp_cnt, tex_cnt, ibo_cnt, nir, t))

def exec.of.at(res: Bool, dim: Bool, refused: Bool, samp_cnt: U32, tex_cnt: U32,
               ibo_cnt: U32, nir: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, res, Tr.refuse(RF_RESOURCES(), t),
    exec.of2(dim, refused, samp_cnt, tex_cnt, ibo_cnt, nir, t))
def at3.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{s}: s
    case None{}: 1

def at3(+xs: List<&2, U32>, n: Nat) -> U32: at3.at(List.get(&2, U32, xs, n))

def ls0(+xs: List<&2, U32>) -> U32: at3(xs, 0n)
def ls1(+xs: List<&2, U32>) -> U32: at3(xs, 1n)
def ls2(+xs: List<&2, U32>) -> U32: at3(xs, 2n)




def FLUSH_WRITE_BACK_ONLY() -> List<&2, Bool>: [True{}, False{}, False{}, False{}]
def FLUSH_INVALIDATE_ONLY() -> List<&2, Bool>: [False{}, True{}, False{}, False{}]

# ===========================================================================
# READING AN EXEC TRACE. `seen` is the LENGTH -- a count row, because a gate
# whose only claims are booleans cannot see a dropped call -- and `seq` is the
# SUBSEQUENCE test, whose fuel is the TRACE length and whose answer is
# `at == patlen`. Getting either half wrong makes it answer True to everything,
# and a subsequence test that always says True is the row that cannot fail.
# ===========================================================================

def seq.has.put(+c: Call, +want: Call, +at: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(U32.is_eq(Call.k(c), Call.k(want)),
                          U32.is_eq(Call.arg(c), Call.arg(want))), 1n+at, at)
def seq.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+w}: seq.has.put(c, w, at)


def seq.has(n: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, List.length(&2, Call, pat))
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, List.length(&2, Call, pat))
        case Call{kk, aa} <> t:
          seq.has(m, t, pat, seq.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))


def exec.last_cmd.go(n: Nat, +cs: List<&2, Call>, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: exec.last_cmd.go(m, t,
          Bool.pick(U32, U32.is_eq(kk, CALL_CMD7()), aa, acc))

type Two is Data:
  Two{a: U32, b: U32}

def Two.a(t: Two) -> U32:
  match t:
    case Two{a, b}: a

def Two.b(t: Two) -> U32:
  match t:
    case Two{a, b}: b

def exec.dispatch.go(n: Nat, +cs: List<&2, Call>, +st: Two) -> Two:
  match n:
    case 0n: st
    case 1n+m:
      match cs:
        case Nil{}: st
        case Call{kk, aa} <> t: exec.dispatch.go(m, t,
          Bool.pick(Two, U32.is_eq(kk, CALL_CMD7()), Two{aa, Two.a(st)}, st))

def IOCTL_DIR() -> U32: 3
def IOCTL_BASE() -> U32: 9
def IOCTL_NR() -> U32: 74
def IOCTL_SIZE() -> U32: 64
def IOCTL_SHIFT_DIR() -> U32: 30
def IOCTL_SHIFT_SIZE() -> U32: 16
def IOCTL_SHIFT_BASE() -> U32: 8
def IOCTL_SHIFT_NR() -> U32: 0

def LAYOUT_ALIGN() -> U32: 4
def acc_of(n: Nat, at: U32, acc: List<&2, U32>) -> List<&2, U32>:
  acc
def round4(+n: U32) -> U32: H.round_up_u32(n, LAYOUT_ALIGN())



def layout_args.at(n: Nat, +sizes: List<&2, U32>, +at: U32, +base: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match sizes:
        case Nil{}: acc
        case s <> t: layout_args.at(m, t, U32.add(at, round4(s)), base,
          List.append(&2, U32, acc, [U32.add(base, at)]))

def pack_end(+o: U32, +end: U32) -> U32: Bool.pick(U32, U32.is_lt(end, o), o, end)
def pack_pad(+o: U32, +end: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(o, end), acc, List.append(&2, U32, acc, [U32.sub(o, end)]))


def pack_args.at(n: Nat, +offs: List<&2, U32>, +size: U32, +end: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.append(&2, U32, acc, [U32.sub(size, end)])
    case 1n+m:
      match offs:
        case Nil{}: List.append(&2, U32, acc, [U32.sub(size, end)])
        case o <> t: pack_args.at(m, t, size, pack_end(U32.add(o, LAYOUT_ALIGN()), end),
          pack_pad(o, end, acc))
def pack_args.put(n: Nat, size: U32, end: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  pack_args.at(List.length(&2, U32, acc), acc, size, end, Nil{})




# THE SORT, and it is the reason `qc_pa_unsorted` exists: `pack_args` does
# `sorted(args, key=lambda x: x[0])`, so [2064, 2048] is walked as [2048, 2064]
# and the FIRST pad is 2048 rather than 2064. An insertion sort on the offsets
# is the whole of it, and a port that walks the list as given gets every pad
# length wrong for an unsorted kernel-argument block -- which is a thing that
# happens, because `kernargs` builds the block by APPENDING.
# THE INSERTION CARRIES THE PREFIX. `Bool.pick` is strict and an insertion has
# to rebuild `prefix ++ [o] ++ suffix`, which one `List.append` cannot do -- the
# first version appended at the tail in BOTH arms and answered
# `2052,4294967288,4294967288,504` for a tight block where CPython answers
# `2048,504`. `carried` is the prefix and `qc_pa_tight` is the row.
def pack_args.cat(+a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

def pack_args.ins(n: Nat, +o: U32, +acc: List<&2, U32>, +carried: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.append(&2, U32, carried, [o])
    case 1n+m:
      match acc:
        case Nil{}: List.append(&2, U32, carried, [o])
        case h <> t: Bool.pick(List<&2, U32>, U32.is_le(o, h),
          List.append(&2, U32, carried, [o]),
          pack_args.ins(m, o, t, List.append(&2, U32, carried, [h])))

# `carried ++ [o] ++ t`, which is `carried ++ [o]` and then the TAIL -- dropping
# the tail is what made the sort swallow an element and answer `2048,508`.

def pack_args.sort.put(+o: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  pack_args.ins(List.length(&2, U32, acc), o, acc, Nil{})

def pack_args.sort(n: Nat, +offs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match offs:
        case Nil{}: acc
        case o <> t: pack_args.sort(m, t, pack_args.sort.put(o, acc))
def pack_args.sorted.at(+sorted: List<&2, U32>, size: U32) -> List<&2, U32>:
  pack_args.at(List.length(&2, U32, sorted), sorted, size, 0, Nil{})

# THE SEED IS `Nil{}`, NOT `offs`. Seeding the accumulator with the list being
# walked makes `List.append` grow the walk's own input, and the sort then
# swallows an element: `qc_pa_unsorted` answered `2048,508` where CPython answers
# `2048,12,492`, which is a one-element block.
def pack_args.sorted(+offs: List<&2, U32>, size: U32) -> List<&2, U32>:
  pack_args.sorted.at(pack_args.sort(List.length(&2, U32, offs), offs, Nil{}), size)


def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def fld_line.at(+row: Qf) -> String:
  match row:
    case Qf{r, f, nm, v, isb}:
      String.concat([f, "@", nm, "=", U32.show(v), "/", U32.show(Bool.to_u32(isb)),
                     "<-", U32.show(qfield_ix(r, f))])

def fld_at(+ix: U32) -> Qf: qfield_of(List.get(&2, Qf, qfields(), U32.to_nat(ix)))
