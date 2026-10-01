# tinybendygrad/runtime/ops_qcom.bend -- port of tinygrad/runtime/ops_qcom.py
#
# ===========================================================================
# WHAT THIS FILE IS. `ops_qcom.py` is the ADRENO/KGSL GPU backend, 396 lines.
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
#   2. `flag` (:303) over the four kgsl `_SHIFT`/`_MASK` pairs.
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
# WHAT IS PORTED SO FAR, AND WHAT IS NOT.
#
#   :20  BUFTYPE_*                PORTED  `buftype_names`, both directions
#   :34-41 the qreg format        PORTED  `mesa_name`, `qreg_name`
#   :36-41 _qreg_exec             PORTED  `qregs`, `qfields`, `qreg.of`
#   :43  ctz                      PORTED  `ctz` (see THE Ctz PRECONDITION)
#   :45-47 parity                 PORTED  `parity`
#   :49  pkt7_hdr                 PORTED  `pkt7_hdr`
#   :51  pkt4_hdr                 PORTED  `pkt4_hdr`
#   :53  _read_lib                PORTED  `read_lib` (little-endian u32)
#   :303 flag                     PORTED  `kgsl_flags`, both directions, `flag`
#   :18-19 autogen imports        PORTED  `MESA_*`/`KGSL_*` constants (62)
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
# ONE THING THE ORACLE GOT WRONG FIRST, recorded because it is the kind of
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
#   :20   BUFTYPE_*                  PORTED  `buftype_names`, both directions
#   :34-41 the qreg name format      PORTED  `mesa_of`, `qreg_of`, `is_reg_name`
#   :36-41 `_qreg_exec`              PORTED  `qregs`, `qfields`, `qreg.of`
#   :43   ctz                        PORTED  `ctz` (see THE ctz PRECONDITION)
#   :45-47 parity                    PORTED  `parity`
#   :49   pkt7_hdr                   PORTED  `pkt7_hdr`
#   :51   pkt4_hdr                   PORTED  `pkt4_hdr`
#   :53   _read_lib                  PORTED  `read_lib`, `read_words`
#   :57-59 the cmd/reg word count    PORTED  `qwords`
#   :61-70 `_cache_flush`            PORTED  `flush.of` + `Tr`
#   :70   memory_barrier             PORTED  `FLUSH_BARRIER`
#   :74/79 the signal guard          PORTED  `rf.gpu_lt73` / `RF_EVENT7`
#   :118  the resources refusal      PORTED  `rf.resources` + `Tr.refuse`
#   :119-120 the dims refusal        PORTED  `rf.dims` + `Tr.refuse`
#   :115-192 exec                    PORTED  `exec.of` and its 27-call trace
#   :202-203 the ioctl command word  PORTED  `ioctl_cmd`
#   :206-283 QCOMProgramData         PORTED  `pd.parse_full`, `desc.*`, `const.*`
#   :228/272 the two offset rules    PORTED  `pd.nir_*`, `pd.cl_*`
#   :232-237 the six derived sizes   PORTED  `pd.*`
#   :239-283 `_parse_lib`            PORTED  the two binary walks
#   :285-292 `qcom_build_program`    PORTED  `qcom.get`, `ce.find`, `ce.put`
#   :294-301 QCOMAllocator           WALL 3  `:301 _offset` is device.bend's own
#   :303  `flag`                     PORTED  `kgsl_flags`, both directions
#   :314-345 QCOMDevice.__init__     PARTIAL the flags and the gpu_id refusal
#   :331-345 the init SEQUENCE       WALL 4  the ioctls and mmap are seams
#   :347-352 dummy / border_color    PARTIAL the SIZES only, in `FLUSH_*`
#   :354-379 _gpu_alloc/_gpu_free   WALL 4  ioctls, mmap, memset, munmap
#   :364-372 _gpu_map                WALL 4  the ioctl, the EFAULT arm
#   :381-386 _wait_signal            WALL 4  the timestamp ioctls
#   :388-392 _ensure_stack_size      WALL 3  it is `Buffer` and device.bend's
#   :394-396 _at_profile_finalize    WALL 4  sysfs
#
# NOT PORTED AT ALL, and these are the gaps a reader should weigh first:
#
#   :89-113 `kernargs`               WALL 1+2  the argument trace proper. What
#        survives here is `layout_args`/`pack_args` (hcq2.py:74-83), the two
#        functions `kernargs` is built from, and the pad SEQUENCE they produce.
#        The buffer/image/sampler SELECTION at :91-94 and the `tex_to_image`
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
#   .agents/slop/qc_oracle.py        the tables, the parse, the cache key
#   .agents/slop/qc_stage3_oracle.py  the headers, the refusals, layout_args
#   .agents/slop/qc_cache_oracle.py   the REAL `_qcom_program_cache` dict
#   .agents/slop/qc_exec_oracle.py    the REAL `QCOMComputeQueue.exec`
#   .agents/slop/qc_check.py         diffs the gate's output against all four
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
def CP_REG_TO_MEM() -> U32: 62
def CP_WAIT_REG_MEM() -> U32: 60
def CP_LOAD_STATE6_FRAG() -> U32: 52
def CP_SET_MARKER() -> U32: 101
def CP_EXEC_CS() -> U32: 51
def CP_RUN_OPENCL() -> U32: 49
def CACHE_FLUSH_TS() -> U32: 4
def CACHE_INVALIDATE() -> U32: 49

# --- the REG_A6XX_* register numbers `self.reg` writes --------------------
def REG_A6XX_SP_UPDATE_CNTL() -> U32: 47880
def REG_A6XX_SP_CS_TSIZE() -> U32: 43450
def REG_A6XX_SP_CS_USIZE() -> U32: 43520
def REG_A6XX_SP_MODE_CNTL() -> U32: 43776
def REG_A6XX_SP_PERFCTR_SHADER_MASK() -> U32: 44559
def REG_A6XX_TPL1_MODE_CNTL() -> U32: 45833
def REG_A6XX_TPL1_DBG_ECO_CNTL() -> U32: 46592
def REG_A6XX_SP_CS_NDRANGE_0() -> U32: 47504
def REG_A6XX_SP_CS_CNTL_0() -> U32: 43440
def REG_A6XX_SP_CS_CNTL_1() -> U32: 43441
def REG_A6XX_SP_REG_PROG_ID_0() -> U32: 47491
def REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET() -> U32: 43453
def REG_A6XX_SP_CS_INSTR_SIZE() -> U32: 43452
def REG_A6XX_SP_CS_SAMPLER_BASE() -> U32: 43490
def REG_A6XX_TPL1_CS_BORDER_COLOR_BASE() -> U32: 45440
def REG_A6XX_SP_CS_TEXMEMOBJ_BASE() -> U32: 43494
def REG_A6XX_SP_CS_UAV_BASE() -> U32: 43506
def REG_A6XX_SP_CS_CONFIG() -> U32: 43451
def REG_A6XX_SP_CS_CONST_CONFIG_0() -> U32: 47511
def REG_A6XX_CP_ALWAYS_ON_COUNTER() -> U32: 2432

# --- the state-descriptor enums, :153-179 ---------------------------------
def ST_SHADER() -> U32: 0
def ST_CONSTANTS() -> U32: 1
def SS6_INDIRECT() -> U32: 2
def ST6_UAV() -> U32: 3
def SB6_CS_TEX() -> U32: 5
def SB6_CS_SHADER() -> U32: 13

# --- the misc enums --------------------------------------------------------
def A6XX_TEX_2D() -> U32: 1
def A6XX_TEX_CLAMP_TO_BORDER() -> U32: 3
def CONSTLEN_256() -> U32: 2
def ISAMMODE_CL() -> U32: 1
def ISAMMODE_GL() -> U32: 2
def POLL_MEMORY() -> U32: 1
def WRITE_GE() -> U32: 5
def THREAD64() -> U32: 0
def RM6_COMPUTE() -> U32: 8
def FMT6_16_16_16_16_FLOAT() -> U32: 98
def FMT6_32_32_32_32_FLOAT() -> U32: 130
def IR3_CONST_ALLOC_DRIVER_PARAMS() -> U32: 3

# --- the kgsl ioctl/flag constants ----------------------------------------
def KGSL_CACHEMODE_UNCACHED() -> U32: 1
def KGSL_CMDLIST_IB() -> U32: 1
def KGSL_CONTEXT_NO_FAULT_TOLERANCE() -> U32: 512
def KGSL_CONTEXT_NO_GMEM_ALLOC() -> U32: 2
def KGSL_CONTEXT_PREAMBLE() -> U32: 16
def KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN() -> U32: 2
def KGSL_CONTEXT_PWR_CONSTRAINT() -> U32: 2048
def KGSL_MEMFLAGS_USE_CPU_MAP() -> U32: 268435456
def KGSL_PROP_DEVICE_INFO() -> U32: 1
def KGSL_PROP_PWR_CONSTRAINT() -> U32: 18
def KGSL_TIMESTAMP_QUEUED() -> U32: 3
def KGSL_USER_MEM_TYPE_ADDR() -> U32: 2

# ===========================================================================
# ops_qcom.py:20 -- `BUFTYPE_BUF, BUFTYPE_TEX, BUFTYPE_IBO = 0, 1, 2`.
#
# These three are read as a SET at :268 and :271 (`typ not in {BUFTYPE_TEX,
# BUFTYPE_IBO}` and `typ is BUFTYPE_TEX` / `typ is BUFTYPE_IBO`), and they are
# WRITTEN as an ordinal at :264 (`length, _, _, offset_words, _, _, _, typ`),
# so BOTH directions are load-bearing and both get a table.
# ===========================================================================

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

# :268's set membership, as a fold. `buftype_of` answering BUFTYPE_BUF for an
# unknown name is Python's `typ not in {..}` again: a type this port has never
# heard of is neither TEX nor IBO, so it is kept in `buf_offs`.
def buftype_of(+s: String) -> U32: buftype_ix.go(List.length(&2, String, buftype_names()), s, buftype_names(), 0, 0)

def buftype_name.at(v: Nat) -> String:
  match v:
    case 0n: "BUFTYPE_BUF"
    case 1n: "BUFTYPE_TEX"
    case _: "BUFTYPE_IBO"

def buftype_name(v: U32) -> String: buftype_name.at(U32.to_nat(v))

# ===========================================================================
# ops_qcom.py:36-41 -- THE qreg TABLE, both directions.
#
# :41 `qreg = type("QREG", (object,), {name[4:].lower():
#   functools.partial(_qreg_exec, name) for name in mesa.__dict__
#   if name[:4] == 'REG_'})`. So the FORWARD direction the file uses is
# `qreg.<attr>` -> `REG_<ATTR.UPPER>`, and the REVERSE the comprehension builds
# is `REG_<NAME>` -> `<name[4:].lower()>`. `mesa_of` and `qreg_of` are those two
# halves and they are the WHOLE of the name game; everything else is a field
# lookup.
#
# The list is the thirty-four `qreg` attributes ops_qcom.py actually reaches,
# SORTED, so the index space is a function of the set and not of the file's
# line order. It is generated by `.agents/slop/qc_oracle.py table`, which
# ast-walks the 41 call sites.
# ===========================================================================

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

def qfield_nm(+r: String, +f: String) -> String: Qf.nm(qfield_at(r, f))

def qfield_v(+r: String, +f: String) -> U32: Qf.v(qfield_at(r, f))

def qfield_isb(+r: String, +f: String) -> Bool: Qf.isb(qfield_at(r, f))

# ===========================================================================
# `_qreg_exec` (:36-40), as one pure def. `__val` starts at 0 and each
# keyword ORs in either the flag bit (when the field is a bool) or
# `v << shift`.
#
# THE BOOLEAN ARM IS NOT `if v`. Python writes
# `(getattr(mesa, reg_name) if v else 0) if type(v) is bool else (v << ...)`,
# which is `(FLAG IF v ELSE 0)` when the value IS a bool -- so a `False` bool
# contributes ZERO and a `True` contributes the table's bit. The port takes
# `v` as a U32 and treats the field's OWN `isb` as the discriminator, and
# `qflag.of` is the only way to pass a bool, so the `type(v) is bool` test
# cannot be got wrong at a call site by accident.
# ===========================================================================

# :39's `(getattr(mesa, reg_name) if v else 0)` -- a bool field contributes its
# BIT when the value is truthy and ZERO when it is not. That zero arm is not
# decoration: without it every "disable this" register write would set the bit.
def qreg.bit_of(+on: U32, +row: Qf) -> U32:
  Bool.pick(U32, U32.is_eq(on, 0), 0, Qf.v(row))

def qreg.one(+row: Qf, +v: U32) -> U32:
  Bool.pick(U32, Qf.isb(row), qreg.bit_of(v, row), U32.shln(v, U32.to_nat(Qf.v(row))))

# the ordered keyword list. A Python `**kwargs` is a DICT and its iteration
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

def qreg.of(r: String, +vs: List<&2, Fv>) -> U32:
  qreg.of.go2(List.length(&2, Fv, vs), 0, r, vs)

# the bool form, so the `type(v) is bool` discriminator is not a call-site
# decision: `qreg.flag("a6xx_sp_cs_config", "ENABLED")`.
def qreg.flag(r: String, f: String) -> U32: qfield_v(r, f)

# the `:39`/`qreg.a6xx_tex_const_0(0x8, ...)` form, where the whole value is
# `__val` and NO field is named. It is a plain pass-through and gets no table
# row, so `qc_pos_*` in the gate is what says the three positional sites are
# passed through rather than resolved.
def qreg.pos(v: U32) -> U32: v

# ===========================================================================
# ops_qcom.py:43 -- `ctz(v) = (v & -v).bit_length() - 1`, the count of trailing
# zeros, called once per image at :110 as `ctz(pitch) - 6`.
#
# THE ctz PRECONDITION, and it is a real one: Python's answer for `v == 0` is
# `-1` (because `(0).bit_length()` is 0) and Bend has no negative integer, so
# the port answers 32 -- the same count, modulo the modulus. Python's
# `ctz(0) - 6` is `-7`, which would become `0xffffffff - 6` in a u32 and
# corrupt `A6XX_TEX_CONST_2`; that cannot happen because `pitch` at :106 is
# `shape[1] * 4 * imgdt.itemsize` with `shape[1] >= 1` and `itemsize >= 1`, so
# `pitch >= 4`. `qc_ctz_nonzero` is the row that states the precondition
# instead of leaving it implicit.
# ===========================================================================

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

def ctz(+v: U32) -> U32: ctz.of(ctz.go(CTZ_BITS(), v, Cz{0, False{}}))

# ===========================================================================
# ops_qcom.py:45-47 -- `parity`. Three fold rounds and then a 4-bit table
# lookup, and both halves have to be right or every packet header is wrong:
#
#     for i in range(4, 1, -1): val ^= val >> (1 << i)   # i = 4, 3, 2
#     return (~0x6996 >> (val & 0xf)) & 1
#
# `1 << i` is 16, 8, 4 -- NOT 4, 2, 1. And `(~0x6996 >> k) & 1` is Python's
# ARITHMETIC right shift of the NEGATIVE `~0x6996 == -0x6997`, whose infinite
# two's complement is `...1001011001101001`, and its low sixteen bits are
# `0x9669`. So the table is `bit k of 0x9669`, and `qc_parity_*` is diffed
# against CPython for all sixteen residues.
# ===========================================================================

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
# THE PRECEDENCE IS THE WHOLE TRAP: `|` binds LOOSER than both `&` and `<<` in
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
# is the row that says a `dtypes.uint32` buffer is ONE word and not zero.
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

def qwords(+us: List<&2, Qw>) -> U32: qwords.go(List.length(&2, Qw, us), 0, us)

def QW_U32() -> Qw: Qw{True{}, 4}
def QW_U16() -> Qw: Qw{True{}, 2}
def QW_U8() -> Qw: Qw{True{}, 1}
def QW_U64() -> Qw: Qw{True{}, 8}
def QW_INT() -> Qw: Qw{False{}, 0}

# ===========================================================================
# ops_qcom.py:53 -- `struct.unpack("I", lib[off:off+4])[0]`, i.e. a LITTLE
# ENDIAN u32 at a byte offset, out of the shader binary. `lib` is `bytes` in
# Python and a `List<&2, U32>` of byte values here, which is WALL 2 below.
#
# ops_qcom.py:264 `:278` also `struct.unpack("8I", ...)` and `("III", ...)`,
# i.e. this little-endian reader run over a slice. `read_words` is that
# generalisation and it is what stage 2's `_parse_lib` consumes, so there is
# ONE transcription of "little endian" in this file.
# ===========================================================================

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

def read_words(n: Nat, +bs: List<&2, U32>, +off: U32) -> List<&2, U32>:
  read_words.go(n, bs, off, Nil{})

# ===========================================================================
# ops_qcom.py:303 -- `flag(nm, val) = (val << getattr(kgsl, f"{nm}_SHIFT")) &
# getattr(kgsl, f"{nm}_MASK")`. Four names, four (shift, mask) pairs, and both
# directions because the row name is how the port addresses them.
# ===========================================================================

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

def kgsl_name_at(ix: U32) -> String: kgsl_name_of(List.get(&2, Kf, kgsl_flags(), U32.to_nat(ix)))

# :303. `&` with the mask is what stops `getenv("QCOM_PRIORITY", 8)` from
# writing bits above PRIORITY's field, and `qc_flag_*` diffs all four.
def flag(+nm: String, val: U32) -> U32:
  U32.and(U32.shln(val, U32.to_nat(kgsl_shift(nm))), kgsl_mask(nm))

def FLAG_PRIORITY() -> String: "KGSL_CONTEXT_PRIORITY"
def FLAG_PREEMPT() -> String: "KGSL_CONTEXT_PREEMPT_STYLE"
def FLAG_MEMALIGN() -> String: "KGSL_MEMALIGN"
def FLAG_CACHEMODE() -> String: "KGSL_CACHEMODE"
# ===========================================================================
# STAGE 2 -- `QCOMProgramData` (:206-283) and `qcom_build_program` (:285-292).
#
# WHY THIS HALF GATES. `_parse_lib` is a BINARY WALK over the shader blob, and
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

# --- the six DERIVED sizes, :232-237 --------------------------------------
# These are PURE U32 arithmetic on six parsed numbers and they are the numbers
# the kernel-argument buffer is sized from, so a wrong one is a wrong
# allocation. Each is its own def because Python writes each as its own
# assignment and the ORDER of the reads matters: `hw_stack_offset` reads
# `pvtmem` twice through `round_up` and `next_power2`.
def pd.pvtmem_size_per_item(+pvtmem: U32) -> U32: U32.shrn(H.round_up_u32(pvtmem, 512), 9n)

def pd.pvtmem_size_total(+per_item: U32) -> U32: U32.mul(U32.mul(per_item, 128), 2)

# :234 `round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000)`. The
# 64-bit product IS in this expression and it is WALL 4 below: `next_power2` of
# a value already rounded to 512 is at most 2^31, and `* 128 * 16` is `<< 11`,
# so the product is up to 2^42. The port carries it as a U32 and the row that
# would notice is `qc_pd_stack_*` -- every oracle fixture here has a
# next_power2 of at most 2^12, so the product fits. That is the blind spot, and
# it is written down rather than papered over.
def pd.hw_stack_offset(+pvtmem: U32) -> U32:
  H.round_up_u32(U32.shln(H.next_power2(H.round_up_u32(pvtmem, 512)), 11n), 4096)

# :235 `max(1, (shmem - 1) // 1024)`. TWO things are load-bearing here. The
# `max(1, ...)` says a program with NO shared memory still declares one unit,
# and `shared_size` is written into `a6xx_sp_cs_cntl_1` at :147. AND the
# subtraction UNDERFLOWS for `shmem == 0`: Python's `-1 // 1024` is `-1`, which
# U32 cannot hold, so a U32 fold would answer 4194303 -- 4096x too many shared
# units. The `shmem == 0` arm is that underflow, spelled. Fixture `pl_1` has
# `shmem == 0` precisely so the row can see it.
def pd.shared_unit(+shmem: U32) -> U32:
  Bool.pick(U32, U32.is_eq(shmem, 0), 1, H.floordiv_u32(U32.sub(shmem, 1), 1024))

def pd.shared_size(+shmem: U32) -> U32:
  Bool.pick(U32, U32.is_eq(pd.shared_unit(shmem), 0), 1, pd.shared_unit(shmem))

# :236 `min(1024, ((384 * 32) // (max(1, (fregs + round_up(hregs, 2) // 2)) * 128)) * 128)`.
# The INNER `max(1, ...)` is what keeps a register-free program from dividing
# by zero, and it is the row `qc_pd_maxthreads_den` that says so.
def pd.regs_terms(+fregs: U32, +hregs: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.add(fregs, H.floordiv_u32(H.round_up_u32(hregs, 2), 2)), 0), 1,
    U32.add(fregs, H.floordiv_u32(H.round_up_u32(hregs, 2), 2)))

# `384 * 32` and `* 128` as their own defs so the two halves of the `min` share
# ONE transcription of the division.
def REGS_TOTAL() -> U32: 12288
def REGS_BLOCK() -> U32: 128

def pd.thread_cap(+fregs: U32, +hregs: U32) -> U32:
  U32.mul(H.floordiv_u32(REGS_TOTAL(), U32.mul(pd.regs_terms(fregs, hregs), REGS_BLOCK())), REGS_BLOCK())

def pd.max_threads(+fregs: U32, +hregs: U32) -> U32:
  Bool.pick(U32, U32.is_gt(pd.thread_cap(fregs, hregs), 1024), 1024, pd.thread_cap(fregs, hregs))

# :237 `round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + len(self.samplers) * 4, 0x100)`.
# `len(self.samplers)` is `samp_cnt * 4` in the CL branch (`:257-259` emits four
# words per sampler) and `samp_cnt * 4` again in the NIR branch (`:225-226` emits
# FOUR words), so both branches agree and `samp_cnt` is the multiplier.
def pd.kernargs_alloc_size(+tex_cnt: U32, +ibo_cnt: U32, +samp_cnt: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(ALIGN_ZERO(), U32.mul(U32.add(tex_cnt, ibo_cnt), TEX_BLOCK())),
                         U32.mul(samp_cnt, 4)), 256)

# ===========================================================================
# THE PARSED PROGRAM. `Pd` is `_parse_lib`'s output and nothing else; the six
# derived sizes are defs OVER it, because in Python they are six assignments
# after the `if self.NIR: ... else: self._parse_lib(obj.lib)`, and a reader
# wants to see that the derivation is downstream of BOTH branches.
# ===========================================================================

# ONE kernel-argument descriptor as :264 reads it: the buffer's byte offset
# (`offset_words * 4`) and its BUFTYPE.
type Bi is Data:
  Bi{off: U32, typ: U32}

# ONE constant descriptor as :278 builds it: (value, byte offset, size in
# bytes). `sz` is `2 << is32`, so it is 2 or 4 and never anything else.
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

def Pd.pvtmem(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: pvtmem

def Pd.shmem(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: shmem

def Pd.samp_cnt(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: samp_cnt

def Pd.samp_in_file(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: samp_in_file

def Pd.tex_cnt(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: tex_cnt

def Pd.ibo_cnt(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: ibo_cnt

def Pd.fregs(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: fregs

def Pd.hregs(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: hregs

def Pd.bdoff(p: Pd) -> U32:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: bdoff

def Pd.bins(p: Pd) -> List<&2, Bi>:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: bins

def Pd.consts(p: Pd) -> List<&2, Ci>:
  match p:
    case Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: consts

def Pd.of() -> Pd:
  Pd{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Nil{}, Nil{}}

# --- the two offset rules, and why they are TWO ----------------------------
#
#   :228 (NIR)  tex_off, ibo_off, samp_off = 2048, 2048 + 0x40*tex_cnt, 2048 + 0x40*(tex_cnt + ibo_cnt)
#   :272 (CL)   ibo_off, tex_off, samp_off = 2048, 2048 + 0x40*ibo_cnt, 2048 + 0x40*tex_cnt + 0x40*ibo_cnt
#
# READ THE LHS ORDER. Each branch assigns `2048` to a DIFFERENT name -- NIR to
# `tex_off`, CL to `ibo_off` -- and gives the OTHER one the `0x40 * <the other
# count>` term. So the ONLY difference is which name gets the bare 2048 and
# which count scales the other. `pd.nir_tex_off` and `pd.cl_ibo_off` are both
# exactly `ALIGN_ZERO()`, and `qc_off_swap_ibo_0` (a blob with tex_cnt == 0)
# is the row that says so: a port that reads both branches as "the first one is
# 2048 + 0x40*n" answers False there.
def pd.nir_tex_off(+tex_cnt: U32) -> U32: ALIGN_ZERO()
def pd.nir_ibo_off(+tex_cnt: U32) -> U32: U32.add(ALIGN_ZERO(), U32.mul(tex_cnt, TEX_BLOCK()))
def pd.nir_samp_off(+tex_cnt: U32, +ibo_cnt: U32) -> U32:
  U32.add(U32.add(ALIGN_ZERO(), U32.mul(tex_cnt, TEX_BLOCK())), U32.mul(ibo_cnt, TEX_BLOCK()))

def pd.cl_ibo_off(+ibo_cnt: U32) -> U32: ALIGN_ZERO()
def pd.cl_tex_off(+ibo_cnt: U32) -> U32: U32.add(ALIGN_ZERO(), U32.mul(ibo_cnt, TEX_BLOCK()))
def pd.cl_samp_off(+tex_cnt: U32, +ibo_cnt: U32) -> U32:
  U32.add(U32.add(ALIGN_ZERO(), U32.mul(tex_cnt, TEX_BLOCK())), U32.mul(ibo_cnt, TEX_BLOCK()))

# ===========================================================================
# THE BUFFER-DESCRIPTOR WALK, :262-268.
#
#     bdoff = round_up(image_desc_off + 0x158 + len(self.name), 4) + 8 * samp_cnt_in_file
#     while bdoff + 32 <= len(lib):
#       length, _, _, offset_words, _, _, _, typ = struct.unpack("8I", lib[bdoff:bdoff+32])
#       if length == 0: break
#       binfos.append((offset_words * 4, typ))
#       bdoff += length
#
# `len(self.name)` is the KERNEL NAME LENGTH, so the descriptor table's start
# depends on a string this port does not otherwise have -- which is why
# `name_len` is a parameter of `pd.parse` and not a field.
# ===========================================================================

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

def desc.buf_offs(+bs: List<&2, Bi>) -> List<&2, U32>:
  desc.buf_offs.go(List.length(&2, Bi, bs), bs, Nil{})

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

# `consts_info` as the ONE string the gate diffs, because the shape is a list of
# triples and a row per triple would be three rows per constant for no more
# information. `val@byteoff:size` and `;` between, which is the oracle's own
# spelling -- so a reader can line the two up by eye.
def const.flat(+cs: List<&2, Ci>) -> String:
  const.flat.go(List.length(&2, Ci, cs), cs, Nil{})

# ===========================================================================
# `_parse_lib` AS ONE DEF. The order of the reads is Python's and it matters:
# `image_offset` is read at :242 and BOUNDS the constant walk at :276, so a
# port that walks the constants before reading it has no bound.
# ===========================================================================

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
#         buf = UOp.placeholder((len(image),), dtypes.uint8, ..., tag="program")
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

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, refused}: refused

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

def Ck.ndevs(c: Ck) -> U32:
  match c:
    case Ck{hash, ndevs, devs}: ndevs

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

def Ce.t(c: Ce) -> Tr:
  match c:
    case Ce{key, pd, buf, t}: t

# ===========================================================================
# THE CACHE ITSELF. A list of entries and a LINEAR scan, because Bend has no
# hash map and because the honest question -- "does a MISS happen?" -- does not
# care about the lookup's cost. `ce.find` answers the FIRST match and there is
# no eviction, so first is also last.
# ===========================================================================

# the index of the FIRST entry whose key matches, or NO_ENTRY. The index is
# carried as a Nat because `List.get` wants one, and `at` is the answer so far
# so a match SHORT-CIRCUITS without a second scan.
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
# `qcom_build_program`. THE THREE CALLS ON THE MISS PATH, IN PYTHON'S ORDER,
# and NONE of them on the hit path. `qc_ck_order` is the row that reads the
# trace; `qc_ck_nbuild` counts PARSE and `qc_ck_npatch` counts PATCH, and the
# pair is what says the miss path ran exactly once.
# ===========================================================================

# :289 `image = bytes(data.image).ljust(round_up(len(data.image), 4), b"\x00")`.
# The image is padded to a multiple of FOUR with ZEROES, and the buffer's length
# is the PADDED length -- `UOp.placeholder((len(image),), ...)` reads `len` of
# the padded object. So a 3-byte shader image becomes a 4-byte allocation.
def qcom.pad_len(+nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

def qcom.npad(+nbytes: U32) -> U32: U32.sub(qcom.pad_len(nbytes), nbytes)

# :290 `UOp.placeholder((len(image),), dtypes.uint8, next(UOp.unique_num), device=devs)`
# -- the buffer is as long as the PADDED image and lands on `devs`.
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

def qcom.get(+hash: U32, +devs: List<&2, U32>, +name_len: U32, +bs: List<&2, U32>,
             +next_num: U32, +es: List<&2, Ce>) -> Ce:
  Bool.pick(Ce, U32.is_eq(ce.find(Ck.of(hash, devs), es), NO_ENTRY()),
    qcom.build(hash, devs, name_len, bs, next_num, es),
    qcom.hit(Ck.of(hash, devs), es))

def ce.push(+e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  List.append(&2, Ce, es, [e])

# `_qcom_program_cache[key] = value` IS a MAP ASSIGNMENT, so storing a key that
# is already there REPLACES it and the LENGTH DOES NOT GROW. A list append is not
# a map assignment and the difference is measurable: pushing the six gate entries
# unconditionally gives six slots for four programs. `ce.put` is the assignment;
# `ce.push` stays for the case that genuinely grows. `qc_ck_len` is the row.
def ce.put.at(fresh: Bool, e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  Bool.pick(List<&2, Ce>, fresh, ce.push(e, es), es)

def ce.put(+e: Ce, +es: List<&2, Ce>) -> List<&2, Ce>:
  ce.put.at(U32.is_eq(ce.find(Ce.key(e), es), NO_ENTRY()), e, es)

def ce.len(+es: List<&2, Ce>) -> U32: U32.from_nat(List.length(&2, Ce, es))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

# the trace of a SEQUENCE of calls is the concatenation of their traces, in
# call order, and it is built HERE rather than by a `Cc` machine so that there is
# exactly ONE transcription of `qcom.get` in this file. A second fold that
# re-derived the hit/miss decision would be a second bug surface.
# THE KIND SEQUENCE of a trace, as one row. `qc_ck_ckinds` reads it and every
# ORDER claim in this file is a subsequence test over it, so one row says what
# the whole trace was and the per-kind COUNT rows say how often.
# APPEND and NO reverse -- `List.append(a, A, xs, ys)` IS `xs ++ ys`. The first
# version reversed at the end as well and printed every trace backwards, which
# `qc_ck_first_trace` caught: it is the one row whose only claim is the ORDER of
# the three miss-path calls, so a reversed trace makes it unfalsifiable.
def Tr.kinds.go(n: Nat, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.kinds.go(m, t, List.append(&2, U32, acc, [kk]))

def Tr.kinds(+cs: List<&2, Call>) -> List<&2, U32>:
  Tr.kinds.go(List.length(&2, Call, cs), cs, Nil{})

def tr.cat(+a: List<&2, Call>, b: List<&2, Call>) -> List<&2, Call>:
  List.append(&2, Call, a, b)

def tr.seq.go(n: Nat, steps: List<&2, Tr>, +acc: List<&2, Call>) -> List<&2, Call>:
  match n:
    case 0n: acc
    case 1n+m:
      match steps:
        case Nil{}: acc
        case s <> t: tr.seq.go(m, t, tr.cat(acc, Tr.calls(s)))

def tr.seq(+steps: List<&2, Tr>) -> List<&2, Call>:
  tr.seq.go(List.length(&2, Tr, steps), steps, Nil{})

# ===========================================================================
# STAGE 3 -- `QCOMComputeQueue` (:55-204) and `QCOMDevice.__init__` (:314-345).
#
# THE TRACE IS THE PORT. Every call below is either an argument BUILDER (pure,
# and the gate checks it) or a `Tr.emit` (and the gate checks the order). There
# is no third kind, so a refusal needs no guard of its own: `Tr.emit` records
# nothing once `refused` is set, and the refusal shows up as a TRUNCATED trace.
#
# WHAT THE TRACE DELIBERATELY DOES NOT CARRY: the argument VALUES. `self.reg(R,
# qreg.a6xx_sp_cs_ndrange_0(...), 256, 0, ...)` passes thirteen words and eleven
# of them are computed register fields. This file records the REGISTER and the
# COUNT; the register VALUE is `qreg.of(...)`, which the stage-1 rows check
# directly against `_qreg_exec` for nine call sites. What nothing checks is that
# the RIGHT `qreg` call is paired with the RIGHT register in `exec` -- that is
# blind spot 1 below, and it is the biggest one.
# ===========================================================================

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
# THE CACHE FLUSH, :61-70. FOUR INDEPENDENT CONDITIONALS and one def, because
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
# THE ORDER IS NOT THE PARAMETER ORDER: Python tests write_back, invalidate,
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

def flush.cnt(+which: U32) -> U32: flush.cnt.at(U32.to_nat(which))

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

# `flags` is indexed by the ISSUE order and `at` is the flag's position in
# Python's PARAMETER order, so the fold and the flag list are in different
# orders and the mapping is `ISSUE_AT`. `qc_flush_order_barrier` fails if that
# mapping is the identity.
def FLAGS() -> List<&2, U32>: [0, 1, 2, 3]
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

def q.hdr7(opcode: U32, +cnt: U32) -> U32: pkt7_hdr(opcode, cnt)
def q.hdr4(regno: U32, +cnt: U32) -> U32: pkt4_hdr(regno, cnt)

# ===========================================================================
# THE FOUR RAISES, and they are four DIFFERENT ones:
#
#   :79  `raise RuntimeError('CP_EVENT_WRITE7 is not supported')` -- inside
#        `signal`, on the `else` of `if self.dev.gpu_id[:2] < (7, 3)`
#   :118 `raise RuntimeError("Too many resources requested for launch")`
#   :120 `raise RuntimeError(f"Invalid global/local dims ...")`
#   :332 `raise RuntimeError(f"Unsupported GPU: chip_id=...")`
#
# The one that SURPRISES is :79. It is unreachable from `__init__` -- :332
# already refused every gpu_id >= (7, 3) -- so on this backend the only way to
# reach `signal` is with an accepted gpu, and :79 is dead code BY CONSTRUCTION
# rather than by accident. `qc_rf_event7_unreachable` says so instead of
# pretending the arm is live.
# ===========================================================================

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
# THE SAME PREDICATE WITH THE OPPOSITE SENSE, and every accepted gpu is on one
# side of it. `rf.gpu_ge73(g0, g1)` is the shared def so the two cannot drift.
def rf.gpu_ge73(+g0: U32, +g1: U32) -> Bool:
  Bool.or(U32.is_gt(g0, 7), Bool.and(U32.is_eq(g0, 7), U32.is_ge(g1, 3)))

def rf.gpu_lt73(+g0: U32, +g1: U32) -> Bool: Bool.not(rf.gpu_ge73(g0, g1))

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


# THE SAMPLER BLOCK IS THREE CALLS, NOT TWO. :165-170 is a LOAD_STATE6_FRAG, then
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
# THE NIR TAIL IS TWO CALLS, NOT THREE. :185-187 is ONE `self.reg` carrying TWO
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




# :118 `if data.max_threads < prod(local_size)` -- the LOCAL size. The first
# version of this passed `gs` where Python passes `local_size`, which is
# indistinguishable for a square launch and wrong for every other one:
# `qc_rf_res_pred` is the row and it was False until this was fixed.
def exec.of(+max_threads: U32, +gs: List<&2, U32>, +ls: List<&2, U32>, samp_cnt: U32,
            tex_cnt: U32, ibo_cnt: U32, nir: Bool, refused: Bool) -> Tr:
  exec.of.at(rf.resources(max_threads, ls0(ls), ls1(ls), ls2(ls)), rf.dims(gs, ls),
             refused, samp_cnt, tex_cnt, ibo_cnt, nir, Tr.of())




# :192 `self._cache_flush(write_back=True, invalidate=False, sync=False,
# memsync=False)` -- write_back ONLY.
def FLUSH_BARRIER() -> List<&2, Bool>: [True{}, True{}, True{}, True{}]
def FLUSH_NONE() -> List<&2, Bool>: [False{}, False{}, False{}, False{}]


# the three-dim list readers, so `rf.resources` can be handed three U32s


# ===========================================================================
# STAGE 3 -- `QCOMComputeQueue` (:55-204) and `QCOMDevice.__init__` (:314-345).
#
# THE TWO EXTRA FLAG SETS, one flag each, so `qc_flush_ops_sync` and
# `qc_flush_ops_memsync` can isolate a SINGLE conditional. Python spells these
# as keyword arguments at three call sites and a flag list has to name them, so
# both the four-true set and the two one-true sets live here.
def FLUSH_SYNC_ONLY() -> List<&2, Bool>: [False{}, False{}, False{}, True{}]
def FLUSH_MEMSYNC_ONLY() -> List<&2, Bool>: [False{}, False{}, True{}, False{}]
def FLUSH_WRITE_BACK_ONLY() -> List<&2, Bool>: [True{}, False{}, False{}, False{}]
def FLUSH_INVALIDATE_ONLY() -> List<&2, Bool>: [False{}, True{}, False{}, False{}]

# ===========================================================================
# READING AN EXEC TRACE. `seen` is the LENGTH -- a count row, because a gate
# whose only claims are booleans cannot see a dropped call -- and `seq` is the
# SUBSEQUENCE test, whose fuel is the TRACE length and whose answer is
# `at == patlen`. Getting either half wrong makes it answer True to everything,
# and a subsequence test that always says True is the row that cannot fail.
# ===========================================================================

def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

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


def seq(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  seq.has(List.length(&2, Call, cs), cs, pat, 0n)

# THE TAIL of an exec trace: the `CALL_CMD7` entries that come AFTER the last
# `CALL_CMD4`, which is the dispatch itself. `qc_exec_cl_ends_runcl` and
# `qc_exec_nir_ends_exec` read it, and it is the only way to say which FORK
# fired without pinning the whole trace.
# A `Bool.pick` cannot gate a mutating call, so `after` and the accumulator both
# change and the verdict has to be a ONE-FIELD RECORD the `match` then takes a
# BINDER for -- the same shape `Cz` needs for `ctz`.
# THE LAST `cmd` of a trace, which is what says which FORK fired. NOT
# `exec.tail_of` -- the trailing `self._cache_flush` of :192 is itself a `cmd`,
# so "everything after the last register" is the flush and not the dispatch.
# The first version of these rows read the tail and `qc_exec_cl_ends_runcl` was
# False for exactly that reason.
def exec.last_cmd.go(n: Nat, +cs: List<&2, Call>, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: exec.last_cmd.go(m, t,
          Bool.pick(U32, U32.is_eq(kk, CALL_CMD7()), aa, acc))

def exec.last_cmd(+t: Tr) -> U32:
  exec.last_cmd.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), 0)

# THE DISPATCH, which is the last `cmd` BEFORE the trailing cache flush of :192.
# A TWO-SLOT accumulator and not a filter on the opcode, because the flush's
# opcode (CP_EVENT_WRITE) is ALSO `signal`'s opcode and a filter would be a
# second transcription of which call is which. `exec.last_cmd` and
# `exec.dispatch` together are the pair that says the flush is the LAST cmd.
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

def exec.dispatch(+t: Tr) -> U32:
  Two.b(exec.dispatch.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), Two{0, 0}))

# THE LAST `cmd` that is NOT the trailing flush -- i.e. the DISPATCH. The two
# readers differ by one position and `qc_exec_cl_last_cmd` beside
# `qc_exec_cl_tail_cmd` is the pair that says so.

# `exec.tail_last` is the SECOND-TO-LAST `cmd`: `exec.last_cmd` is the trailing
# cache flush of :192 and this is the dispatch. Naming both is what makes the
# pair a claim rather than a restatement.


# ===========================================================================
# `submit` -- THE IOCTL COMMAND WORD, :202-203.
#
#     idir, base, nr, struct_t = kgsl.IOCTL_KGSL_GPU_COMMAND.args
#     ioctl_cmd = (idir << 30) | (ctypes.sizeof(struct_t) << 16) | (base << 8) | nr
#
# The four shifts are 30, 16, 8 and 0 and they do NOT commute with the masks:
# `base << 8` overlaps nothing, but `idir << 30` is at the very top, so a
# `sizeof` that exceeded 2^14 would collide with it and a `base` above 255 would
# be truncated by the kernel. The four fields and the four shifts each get a row.
# ===========================================================================

def IOCTL_DIR() -> U32: 3
def IOCTL_BASE() -> U32: 9
def IOCTL_NR() -> U32: 74
def IOCTL_SIZE() -> U32: 64
def IOCTL_SHIFT_DIR() -> U32: 30
def IOCTL_SHIFT_SIZE() -> U32: 16
def IOCTL_SHIFT_BASE() -> U32: 8
def IOCTL_SHIFT_NR() -> U32: 0

def ioctl_cmd() -> U32:
  U32.or(U32.or(U32.shln(IOCTL_DIR(), U32.to_nat(IOCTL_SHIFT_DIR())),
                 U32.shln(IOCTL_SIZE(), U32.to_nat(IOCTL_SHIFT_SIZE()))),
         U32.or(U32.shln(IOCTL_BASE(), U32.to_nat(IOCTL_SHIFT_BASE())),
                U32.shln(IOCTL_NR(), U32.to_nat(IOCTL_SHIFT_NR()))))

# ===========================================================================
# THE KERNEL ARGUMENT LAYOUT -- hcq2.py:74-83, and it is the contract five
# other units are porting, so it gets its own two defs rather than being folded
# into `kernargs`.
#
#     layout_args(args, offset) = [(offset + o, w) for (o, _), w in
#                                  zip(TinyELF.iter_sig(sizes), words)]
#     pack_args(args, size)    = words + [BINARY(bytes(size - end))]
#
# `TinyELF.iter_sig` rounds EVERY item up to a four-byte boundary, so a u16
# argument still advances the cursor by four: `qc_la_mix` and `qc_la2_mix` are
# that row. `pack_args` sorts by offset and emits one pad per GAP, then a final
# pad of `size - end` -- so the answer is the SEQUENCE OF PAD LENGTHS, and that
# sequence is what the kernel-argument trace consists of.
# ===========================================================================

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

def layout_args.of(+sizes: List<&2, U32>, base: U32) -> List<&2, U32>:
  layout_args.at(List.length(&2, U32, sizes), sizes, 0, base, Nil{})



# `pack_args` in reverse: the trace is the pad SEQUENCE, and a pad is emitted
# whenever the next offset is not where the cursor already is.
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


def pack_args.of(+offs: List<&2, U32>, size: U32) -> List<&2, U32>:
  pack_args.sorted(offs, size)


def pack_args.align() -> U32: LAYOUT_ALIGN()

# THE PRINTERS, and note `lrow` prints a `List<&2, U32>` as `a,b,c` with NO
# trailing separator -- a baked-in separator is half a diff (bend2-constraints.md,
# the `int_*_new` row class).
def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# --- 1: the BUFTYPE table, :20, BOTH directions ---------------------------
# the FORWARD row asks the table for a name; the REVERSE row asks the table
# for the value of a name. `qc_buftype_unknown` is Python's `typ not in {1,2}`
# arriving as a lookup miss, which is the :268 filter's whole behaviour for a
# type this port has never heard of.
def t_buftype() -> IO(Unit):
  do IO<Unit>:
    urow("qc_buftype_fwd_buf", buftype_of("BUFTYPE_BUF"))
    urow("qc_buftype_fwd_tex", buftype_of("BUFTYPE_TEX"))
    urow("qc_buftype_fwd_ibo", buftype_of("BUFTYPE_IBO"))
    urow("qc_buftype_unknown", buftype_of("BUFTYPE_NONSENSE"))
    srow("qc_buftype_rev_0", buftype_name(0))
    srow("qc_buftype_rev_1", buftype_name(1))
    srow("qc_buftype_rev_2", buftype_name(2))
    urow("qc_buftype_n", U32.from_nat(List.length(&2, String, buftype_names())))
    row("qc_buftype_ibo_is_not_tex", Bool.and(U32.is_eq(buftype_of("BUFTYPE_IBO"), BUFTYPE_IBO()),
      Bool.not(U32.is_eq(buftype_of("BUFTYPE_IBO"), BUFTYPE_TEX()))))

# --- 2: the qreg REGISTER table, both directions, :41 ---------------------
# `qc_reg_<i>` is ONE row carrying BOTH: `attr->REG_NAME<-index`. The forward
# half is `mesa_of`, the reverse half is `qreg_of` followed by the index
# lookup, and the index is what a dropped row would shift. So a wrong forward
# name, a wrong reverse name and a missing entry all move the same row, which
# is the honest shape for a table this small.
def reg_line(+ix: U32) -> String:
  String.concat([qreg_name_at(ix), "->", qreg_mesa_at(ix), "<-",
                 U32.show(qreg_ix_of_mesa(qreg_mesa_at(ix)))])

def t_regs() -> IO(Unit):
  do IO<Unit>:
    urow("qc_nregs", U32.from_nat(List.length(&2, String, qregs())))
    srow("qc_reg_0", reg_line(0))
    srow("qc_reg_1", reg_line(1))
    srow("qc_reg_2", reg_line(2))
    srow("qc_reg_3", reg_line(3))
    srow("qc_reg_4", reg_line(4))
    srow("qc_reg_5", reg_line(5))
    srow("qc_reg_6", reg_line(6))
    srow("qc_reg_7", reg_line(7))
    srow("qc_reg_8", reg_line(8))
    srow("qc_reg_9", reg_line(9))
    srow("qc_reg_10", reg_line(10))
    srow("qc_reg_11", reg_line(11))
    srow("qc_reg_12", reg_line(12))
    srow("qc_reg_13", reg_line(13))
    srow("qc_reg_14", reg_line(14))
    srow("qc_reg_15", reg_line(15))
    srow("qc_reg_16", reg_line(16))
    srow("qc_reg_17", reg_line(17))
    srow("qc_reg_18", reg_line(18))
    srow("qc_reg_19", reg_line(19))
    srow("qc_reg_20", reg_line(20))
    srow("qc_reg_21", reg_line(21))
    srow("qc_reg_22", reg_line(22))
    srow("qc_reg_23", reg_line(23))
    srow("qc_reg_24", reg_line(24))
    srow("qc_reg_25", reg_line(25))
    srow("qc_reg_26", reg_line(26))
    srow("qc_reg_27", reg_line(27))
    srow("qc_reg_28", reg_line(28))
    srow("qc_reg_29", reg_line(29))
    srow("qc_reg_30", reg_line(30))
    srow("qc_reg_31", reg_line(31))
    srow("qc_reg_32", reg_line(32))
    srow("qc_reg_33", reg_line(33))

def t_regdirs() -> IO(Unit):
  do IO<Unit>:
    row("qc_regfwd_0", String.eq(qreg_mesa_at(0), "REG_A6XX_CP_SET_MARKER_0"))
    row("qcregreg_0", String.eq(qreg_of("REG_A6XX_CP_SET_MARKER_0"), qreg_name_at(0)))
    row("qc_regfwd_1", String.eq(qreg_mesa_at(1), "REG_A6XX_SP_CS_CNTL_0"))
    row("qcregreg_1", String.eq(qreg_of("REG_A6XX_SP_CS_CNTL_0"), qreg_name_at(1)))
    row("qc_regfwd_2", String.eq(qreg_mesa_at(2), "REG_A6XX_SP_CS_CNTL_1"))
    row("qcregreg_2", String.eq(qreg_of("REG_A6XX_SP_CS_CNTL_1"), qreg_name_at(2)))
    row("qc_regfwd_3", String.eq(qreg_mesa_at(3), "REG_A6XX_SP_CS_CONFIG"))
    row("qcregreg_3", String.eq(qreg_of("REG_A6XX_SP_CS_CONFIG"), qreg_name_at(3)))
    row("qc_regfwd_4", String.eq(qreg_mesa_at(4), "REG_A6XX_SP_CS_CONST_CONFIG"))
    row("qcregreg_4", String.eq(qreg_of("REG_A6XX_SP_CS_CONST_CONFIG"), qreg_name_at(4)))
    row("qc_regfwd_5", String.eq(qreg_mesa_at(5), "REG_A6XX_SP_CS_CONST_CONFIG_0"))
    row("qcregreg_5", String.eq(qreg_of("REG_A6XX_SP_CS_CONST_CONFIG_0"), qreg_name_at(5)))
    row("qc_regfwd_6", String.eq(qreg_mesa_at(6), "REG_A6XX_SP_CS_INSTR_SIZE"))
    row("qcregreg_6", String.eq(qreg_of("REG_A6XX_SP_CS_INSTR_SIZE"), qreg_name_at(6)))
    row("qc_regfwd_7", String.eq(qreg_mesa_at(7), "REG_A6XX_SP_CS_NDRANGE_0"))
    row("qcregreg_7", String.eq(qreg_of("REG_A6XX_SP_CS_NDRANGE_0"), qreg_name_at(7)))
    row("qc_regfwd_8", String.eq(qreg_mesa_at(8), "REG_A6XX_SP_CS_PVT_MEM_PARAM"))
    row("qcregreg_8", String.eq(qreg_of("REG_A6XX_SP_CS_PVT_MEM_PARAM"), qreg_name_at(8)))
    row("qc_regfwd_9", String.eq(qreg_mesa_at(9), "REG_A6XX_SP_CS_PVT_MEM_SIZE"))
    row("qcregreg_9", String.eq(qreg_of("REG_A6XX_SP_CS_PVT_MEM_SIZE"), qreg_name_at(9)))
    row("qc_regfwd_10", String.eq(qreg_mesa_at(10), "REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET"))
    row("qcregreg_10", String.eq(qreg_of("REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET"), qreg_name_at(10)))
    row("qc_regfwd_11", String.eq(qreg_mesa_at(11), "REG_A6XX_SP_CS_TSIZE"))
    row("qcregreg_11", String.eq(qreg_of("REG_A6XX_SP_CS_TSIZE"), qreg_name_at(11)))
    row("qc_regfwd_12", String.eq(qreg_mesa_at(12), "REG_A6XX_SP_CS_USIZE"))
    row("qcregreg_12", String.eq(qreg_of("REG_A6XX_SP_CS_USIZE"), qreg_name_at(12)))
    row("qc_regfwd_13", String.eq(qreg_mesa_at(13), "REG_A6XX_SP_CS_WGE_CNTL"))
    row("qcregreg_13", String.eq(qreg_of("REG_A6XX_SP_CS_WGE_CNTL"), qreg_name_at(13)))
    row("qc_regfwd_14", String.eq(qreg_mesa_at(14), "REG_A6XX_SP_MODE_CNTL"))
    row("qcregreg_14", String.eq(qreg_of("REG_A6XX_SP_MODE_CNTL"), qreg_name_at(14)))
    row("qc_regfwd_15", String.eq(qreg_mesa_at(15), "REG_A6XX_SP_PERFCTR_SHADER_MASK"))
    row("qcregreg_15", String.eq(qreg_of("REG_A6XX_SP_PERFCTR_SHADER_MASK"), qreg_name_at(15)))
    row("qc_regfwd_16", String.eq(qreg_mesa_at(16), "REG_A6XX_SP_UPDATE_CNTL"))
    row("qcregreg_16", String.eq(qreg_of("REG_A6XX_SP_UPDATE_CNTL"), qreg_name_at(16)))
    row("qc_regfwd_17", String.eq(qreg_mesa_at(17), "REG_A6XX_TEX_CONST_0"))
    row("qcregreg_17", String.eq(qreg_of("REG_A6XX_TEX_CONST_0"), qreg_name_at(17)))
    row("qc_regfwd_18", String.eq(qreg_mesa_at(18), "REG_A6XX_TEX_CONST_1"))
    row("qcregreg_18", String.eq(qreg_of("REG_A6XX_TEX_CONST_1"), qreg_name_at(18)))
    row("qc_regfwd_19", String.eq(qreg_mesa_at(19), "REG_A6XX_TEX_CONST_2"))
    row("qcregreg_19", String.eq(qreg_of("REG_A6XX_TEX_CONST_2"), qreg_name_at(19)))
    row("qc_regfwd_20", String.eq(qreg_mesa_at(20), "REG_A6XX_TEX_CONST_6"))
    row("qcregreg_20", String.eq(qreg_of("REG_A6XX_TEX_CONST_6"), qreg_name_at(20)))
    row("qc_regfwd_21", String.eq(qreg_mesa_at(21), "REG_A6XX_TEX_CONST_7"))
    row("qcregreg_21", String.eq(qreg_of("REG_A6XX_TEX_CONST_7"), qreg_name_at(21)))
    row("qc_regfwd_22", String.eq(qreg_mesa_at(22), "REG_A6XX_TEX_SAMP_0"))
    row("qcregreg_22", String.eq(qreg_of("REG_A6XX_TEX_SAMP_0"), qreg_name_at(22)))
    row("qc_regfwd_23", String.eq(qreg_mesa_at(23), "REG_A6XX_TEX_SAMP_1"))
    row("qcregreg_23", String.eq(qreg_of("REG_A6XX_TEX_SAMP_1"), qreg_name_at(23)))
    row("qc_regfwd_24", String.eq(qreg_mesa_at(24), "REG_A6XX_TPL1_MODE_CNTL"))
    row("qcregreg_24", String.eq(qreg_of("REG_A6XX_TPL1_MODE_CNTL"), qreg_name_at(24)))
    row("qc_regfwd_25", String.eq(qreg_mesa_at(25), "REG_CP_EVENT_WRITE_0"))
    row("qcregreg_25", String.eq(qreg_of("REG_CP_EVENT_WRITE_0"), qreg_name_at(25)))
    row("qc_regfwd_26", String.eq(qreg_mesa_at(26), "REG_CP_EXEC_CS_1"))
    row("qcregreg_26", String.eq(qreg_of("REG_CP_EXEC_CS_1"), qreg_name_at(26)))
    row("qc_regfwd_27", String.eq(qreg_mesa_at(27), "REG_CP_EXEC_CS_2"))
    row("qcregreg_27", String.eq(qreg_of("REG_CP_EXEC_CS_2"), qreg_name_at(27)))
    row("qc_regfwd_28", String.eq(qreg_mesa_at(28), "REG_CP_EXEC_CS_3"))
    row("qcregreg_28", String.eq(qreg_of("REG_CP_EXEC_CS_3"), qreg_name_at(28)))
    row("qc_regfwd_29", String.eq(qreg_mesa_at(29), "REG_CP_LOAD_STATE6_0"))
    row("qcregreg_29", String.eq(qreg_of("REG_CP_LOAD_STATE6_0"), qreg_name_at(29)))
    row("qc_regfwd_30", String.eq(qreg_mesa_at(30), "REG_CP_REG_TO_MEM_0"))
    row("qcregreg_30", String.eq(qreg_of("REG_CP_REG_TO_MEM_0"), qreg_name_at(30)))
    row("qc_regfwd_31", String.eq(qreg_mesa_at(31), "REG_CP_WAIT_REG_MEM_0"))
    row("qcregreg_31", String.eq(qreg_of("REG_CP_WAIT_REG_MEM_0"), qreg_name_at(31)))
    row("qc_regfwd_32", String.eq(qreg_mesa_at(32), "REG_CP_WAIT_REG_MEM_4"))
    row("qcregreg_32", String.eq(qreg_of("REG_CP_WAIT_REG_MEM_4"), qreg_name_at(32)))
    row("qc_regfwd_33", String.eq(qreg_mesa_at(33), "REG_CP_WAIT_REG_MEM_5"))
    row("qcregreg_33", String.eq(qreg_of("REG_CP_WAIT_REG_MEM_5"), qreg_name_at(33)))
    row("qc_regrev_absent", U32.is_eq(qreg_ix_of_mesa("IR3_CONST_ALLOC_PRIV"), NO_SUCH_REG()))
    row("qc_regrev_plain", U32.is_eq(qreg_ix_of_mesa("A6XX_TEX_2D"), NO_SUCH_REG()))
    urow("qc_regix_known", qreg_ix("a6xx_tex_const_0"))
    urow("qc_regix_absent", qreg_ix("a6xx_tex_const_9"))
    row("qc_regprefix_yes", is_reg_name("REG_A6XX_TEX_CONST_0"))
    row("qc_regprefix_no", Bool.not(is_reg_name("A6XX_TEX_CONST_0")))

def fld_line.at(+row: Qf) -> String:
  match row:
    case Qf{r, f, nm, v, isb}:
      String.concat([f, "@", nm, "=", U32.show(v), "/", U32.show(Bool.to_u32(isb)),
                     "<-", U32.show(qfield_ix(r, f))])

def fld_at(+ix: U32) -> Qf: qfield_of(List.get(&2, Qf, qfields(), U32.to_nat(ix)))
def fld_line(+ix: U32) -> String: fld_line.at(fld_at(ix))
def fv_at(+ix: U32) -> U32: qreg.one(fld_at(ix), 1)

def t_fields() -> IO(Unit):
  do IO<Unit>:
    urow("qc_nfields", U32.from_nat(List.length(&2, Qf, qfields())))
    srow("qc_fld_0", fld_line(0))
    srow("qc_fld_1", fld_line(1))
    srow("qc_fld_2", fld_line(2))
    srow("qc_fld_3", fld_line(3))
    srow("qc_fld_4", fld_line(4))
    srow("qc_fld_5", fld_line(5))
    srow("qc_fld_6", fld_line(6))
    srow("qc_fld_7", fld_line(7))
    srow("qc_fld_8", fld_line(8))
    srow("qc_fld_9", fld_line(9))
    srow("qc_fld_10", fld_line(10))
    srow("qc_fld_11", fld_line(11))
    srow("qc_fld_12", fld_line(12))
    srow("qc_fld_13", fld_line(13))
    srow("qc_fld_14", fld_line(14))
    srow("qc_fld_15", fld_line(15))
    srow("qc_fld_16", fld_line(16))
    srow("qc_fld_17", fld_line(17))
    srow("qc_fld_18", fld_line(18))
    srow("qc_fld_19", fld_line(19))
    srow("qc_fld_20", fld_line(20))
    srow("qc_fld_21", fld_line(21))
    srow("qc_fld_22", fld_line(22))
    srow("qc_fld_23", fld_line(23))
    srow("qc_fld_24", fld_line(24))
    srow("qc_fld_25", fld_line(25))
    srow("qc_fld_26", fld_line(26))
    srow("qc_fld_27", fld_line(27))
    srow("qc_fld_28", fld_line(28))
    srow("qc_fld_29", fld_line(29))
    srow("qc_fld_30", fld_line(30))
    srow("qc_fld_31", fld_line(31))
    srow("qc_fld_32", fld_line(32))
    srow("qc_fld_33", fld_line(33))
    srow("qc_fld_34", fld_line(34))
    srow("qc_fld_35", fld_line(35))
    srow("qc_fld_36", fld_line(36))
    srow("qc_fld_37", fld_line(37))
    srow("qc_fld_38", fld_line(38))
    srow("qc_fld_39", fld_line(39))
    srow("qc_fld_40", fld_line(40))
    srow("qc_fld_41", fld_line(41))
    srow("qc_fld_42", fld_line(42))
    srow("qc_fld_43", fld_line(43))
    srow("qc_fld_44", fld_line(44))
    srow("qc_fld_45", fld_line(45))
    srow("qc_fld_46", fld_line(46))
    srow("qc_fld_47", fld_line(47))
    srow("qc_fld_48", fld_line(48))
    srow("qc_fld_49", fld_line(49))
    srow("qc_fld_50", fld_line(50))
    srow("qc_fld_51", fld_line(51))
    srow("qc_fld_52", fld_line(52))
    srow("qc_fld_53", fld_line(53))
    srow("qc_fld_54", fld_line(54))
    srow("qc_fld_55", fld_line(55))
    srow("qc_fld_56", fld_line(56))
    srow("qc_fld_57", fld_line(57))
    srow("qc_fld_58", fld_line(58))
    srow("qc_fld_59", fld_line(59))
    srow("qc_fld_60", fld_line(60))
    srow("qc_fld_61", fld_line(61))
    urow("qc_fld_unknown", qfield_ix("a6xx_sp_cs_config", "NOSUCHFIELD"))
    row("qc_fld_bare_missing", String.eq(qfield_nm("a6xx_sp_cs_config", "NOSUCHFIELD"), ""))
    row("qc_fld_bare_isbool", Bool.not(qfield_isb("a6xx_sp_cs_config", "NOSUCHFIELD")))

def t_fvals() -> IO(Unit):
  do IO<Unit>:
    urow("qc_fv_0", fv_at(0))
    urow("qc_fv_1", fv_at(1))
    urow("qc_fv_2", fv_at(2))
    urow("qc_fv_3", fv_at(3))
    urow("qc_fv_4", fv_at(4))
    urow("qc_fv_5", fv_at(5))
    urow("qc_fv_6", fv_at(6))
    urow("qc_fv_7", fv_at(7))
    urow("qc_fv_8", fv_at(8))
    urow("qc_fv_9", fv_at(9))
    urow("qc_fv_10", fv_at(10))
    urow("qc_fv_11", fv_at(11))
    urow("qc_fv_12", fv_at(12))
    urow("qc_fv_13", fv_at(13))
    urow("qc_fv_14", fv_at(14))
    urow("qc_fv_15", fv_at(15))
    urow("qc_fv_16", fv_at(16))
    urow("qc_fv_17", fv_at(17))
    urow("qc_fv_18", fv_at(18))
    urow("qc_fv_19", fv_at(19))
    urow("qc_fv_20", fv_at(20))
    urow("qc_fv_21", fv_at(21))
    urow("qc_fv_22", fv_at(22))
    urow("qc_fv_23", fv_at(23))
    urow("qc_fv_24", fv_at(24))
    urow("qc_fv_25", fv_at(25))
    urow("qc_fv_26", fv_at(26))
    urow("qc_fv_27", fv_at(27))
    urow("qc_fv_28", fv_at(28))
    urow("qc_fv_29", fv_at(29))
    urow("qc_fv_30", fv_at(30))
    urow("qc_fv_31", fv_at(31))
    urow("qc_fv_32", fv_at(32))
    urow("qc_fv_33", fv_at(33))
    urow("qc_fv_34", fv_at(34))
    urow("qc_fv_35", fv_at(35))
    urow("qc_fv_36", fv_at(36))
    urow("qc_fv_37", fv_at(37))
    urow("qc_fv_38", fv_at(38))
    urow("qc_fv_39", fv_at(39))
    urow("qc_fv_40", fv_at(40))
    urow("qc_fv_41", fv_at(41))
    urow("qc_fv_42", fv_at(42))
    urow("qc_fv_43", fv_at(43))
    urow("qc_fv_44", fv_at(44))
    urow("qc_fv_45", fv_at(45))
    urow("qc_fv_46", fv_at(46))
    urow("qc_fv_47", fv_at(47))
    urow("qc_fv_48", fv_at(48))
    urow("qc_fv_49", fv_at(49))
    urow("qc_fv_50", fv_at(50))
    urow("qc_fv_51", fv_at(51))
    urow("qc_fv_52", fv_at(52))
    urow("qc_fv_53", fv_at(53))
    urow("qc_fv_54", fv_at(54))
    urow("qc_fv_55", fv_at(55))
    urow("qc_fv_56", fv_at(56))
    urow("qc_fv_57", fv_at(57))
    urow("qc_fv_58", fv_at(58))
    urow("qc_fv_59", fv_at(59))
    urow("qc_fv_60", fv_at(60))
    urow("qc_fv_61", fv_at(61))


# --- 12: `_parse_lib` on the SYNTHETIC blobs, :239-283 -------------------
# The blobs are the oracle's `synthetic_lib`, printed as byte lists, and
# `qc_lib_<k>_len` is their length so a fixture that drifts is visible BEFORE
# the parse rows rather than inside them.
#
# Each blob puts a value somewhere BOTH walks must find. The descriptor table
# starts at `round_up(image_desc_off + 0x158 + len(name), 4) + 8*samp_in_file`,
# so a blob with a different `name_len` starts it somewhere else and a port
# that hard-codes the offset misses every descriptor. The constant walk is
# bounded by `image_offset = 0x1a0`, which admits TWO of the three constants
# blob 2 writes -- and blob 4 writes only ONE, so it reads a ZEROED second.
# That is the bound biting, and `qc_const_bound_4` is the row.
#
# `qc_pl_<k>` is the seventeen parsed fields in `_parse_lib`'s OWN reading
# order, so a reader can line it up against :241-283. `buf_offs` and
# `consts_info` are LISTS and get their own rows.

def LIB_0() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 0, 0, 0, 25, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def LIB_1() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def LIB_2() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 16,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def LIB_3() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 32, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def LIB_4() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
  16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 16, 0, 0, 7, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 8, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def LIB_5() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]

def t_lib0() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_0_len", U32.from_nat(List.length(&2, U32, LIB_0())))
    +p0 : Pd <- IO.pure(Pd, pd.parse_full(LIB_0(), 8))
    lrow("qc_pl_0", [24,416,288,48,5,1536,6144,0,0,0,1,2048,2112,2112,33,25,768])
    lrow("qc_pl_0_bufs", desc.buf_offs(Pd.bins(p0)))
    srow("qc_pl_0_consts", const.flat(Pd.consts(p0)))
    urow("qc_off_cl_0_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p0)))
    urow("qc_off_cl_0_tex", pd.cl_tex_off(Pd.ibo_cnt(p0)))
    urow("qc_off_cl_0_samp", pd.cl_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)))
    urow("qc_off_nir_0_tex", pd.nir_tex_off(Pd.tex_cnt(p0)))
    urow("qc_off_nir_0_ibo", pd.nir_ibo_off(Pd.tex_cnt(p0)))
    urow("qc_off_nir_0_samp", pd.nir_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)))
    urow("qc_pd_0_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p0)))
    urow("qc_pd_0_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p0))))
    urow("qc_pd_0_stack", pd.hw_stack_offset(Pd.pvtmem(p0)))
    urow("qc_pd_0_shared", pd.shared_size(Pd.shmem(p0)))
    urow("qc_pd_0_maxthr", pd.max_threads(Pd.fregs(p0), Pd.hregs(p0)))
    urow("qc_pd_0_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p0), Pd.ibo_cnt(p0), Pd.samp_cnt(p0)))
    row("qc_off_swap_ibo_0", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p0)),
      pd.nir_ibo_off(Pd.tex_cnt(p0))))
    row("qc_off_swap_tex_0", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p0)),
      pd.nir_tex_off(Pd.tex_cnt(p0))))
    row("qc_off_samp_agrees_0", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)),
      pd.nir_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0))))
    urow("qc_bin_seen_0", Wb.seen(desc.walk(fuel.of(1024), LIB_0(),
      Wb{Pd.bdoff(p0), 0, True{}, Nil{}})))
    urow("qc_const_bound_0", Cw.seen(pd.const_walk(LIB_0(), p0)))
    urow("qc_const_alive_first_0", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_0", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_0", Bool.to_u32(const.alive(440, 416)))
def t_lib1() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_1_len", U32.from_nat(List.length(&2, U32, LIB_1())))
    +p1 : Pd <- IO.pure(Pd, pd.parse_full(LIB_1(), 8))
    lrow("qc_pl_1", [32,416,288,48,5,512,0,2,1,1,0,2048,2048,2112,1,1,840])
    lrow("qc_pl_1_bufs", desc.buf_offs(Pd.bins(p1)))
    srow("qc_pl_1_consts", const.flat(Pd.consts(p1)))
    urow("qc_off_cl_1_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p1)))
    urow("qc_off_cl_1_tex", pd.cl_tex_off(Pd.ibo_cnt(p1)))
    urow("qc_off_cl_1_samp", pd.cl_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)))
    urow("qc_off_nir_1_tex", pd.nir_tex_off(Pd.tex_cnt(p1)))
    urow("qc_off_nir_1_ibo", pd.nir_ibo_off(Pd.tex_cnt(p1)))
    urow("qc_off_nir_1_samp", pd.nir_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)))
    urow("qc_pd_1_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p1)))
    urow("qc_pd_1_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p1))))
    urow("qc_pd_1_stack", pd.hw_stack_offset(Pd.pvtmem(p1)))
    urow("qc_pd_1_shared", pd.shared_size(Pd.shmem(p1)))
    urow("qc_pd_1_maxthr", pd.max_threads(Pd.fregs(p1), Pd.hregs(p1)))
    urow("qc_pd_1_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p1), Pd.ibo_cnt(p1), Pd.samp_cnt(p1)))
    row("qc_off_swap_ibo_1", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p1)),
      pd.nir_ibo_off(Pd.tex_cnt(p1))))
    row("qc_off_swap_tex_1", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p1)),
      pd.nir_tex_off(Pd.tex_cnt(p1))))
    row("qc_off_samp_agrees_1", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)),
      pd.nir_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1))))
    urow("qc_bin_seen_1", Wb.seen(desc.walk(fuel.of(1024), LIB_1(),
      Wb{Pd.bdoff(p1), 0, True{}, Nil{}})))
    urow("qc_const_bound_1", Cw.seen(pd.const_walk(LIB_1(), p1)))
    urow("qc_const_alive_first_1", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_1", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_1", Bool.to_u32(const.alive(440, 416)))
def t_lib2() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_2_len", U32.from_nat(List.length(&2, U32, LIB_2())))
    +p2 : Pd <- IO.pure(Pd, pd.parse_full(LIB_2(), 16))
    lrow("qc_pl_2", [4,416,288,48,5,1536,1024,0,0,0,2,2048,2176,2176,48,40,904])
    lrow("qc_pl_2_bufs", desc.buf_offs(Pd.bins(p2)))
    srow("qc_pl_2_consts", const.flat(Pd.consts(p2)))
    urow("qc_off_cl_2_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p2)))
    urow("qc_off_cl_2_tex", pd.cl_tex_off(Pd.ibo_cnt(p2)))
    urow("qc_off_cl_2_samp", pd.cl_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)))
    urow("qc_off_nir_2_tex", pd.nir_tex_off(Pd.tex_cnt(p2)))
    urow("qc_off_nir_2_ibo", pd.nir_ibo_off(Pd.tex_cnt(p2)))
    urow("qc_off_nir_2_samp", pd.nir_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)))
    urow("qc_pd_2_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p2)))
    urow("qc_pd_2_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p2))))
    urow("qc_pd_2_stack", pd.hw_stack_offset(Pd.pvtmem(p2)))
    urow("qc_pd_2_shared", pd.shared_size(Pd.shmem(p2)))
    urow("qc_pd_2_maxthr", pd.max_threads(Pd.fregs(p2), Pd.hregs(p2)))
    urow("qc_pd_2_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p2), Pd.ibo_cnt(p2), Pd.samp_cnt(p2)))
    row("qc_off_swap_ibo_2", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p2)),
      pd.nir_ibo_off(Pd.tex_cnt(p2))))
    row("qc_off_swap_tex_2", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p2)),
      pd.nir_tex_off(Pd.tex_cnt(p2))))
    row("qc_off_samp_agrees_2", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)),
      pd.nir_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2))))
    urow("qc_bin_seen_2", Wb.seen(desc.walk(fuel.of(1024), LIB_2(),
      Wb{Pd.bdoff(p2), 0, True{}, Nil{}})))
    urow("qc_const_bound_2", Cw.seen(pd.const_walk(LIB_2(), p2)))
    urow("qc_const_alive_first_2", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_2", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_2", Bool.to_u32(const.alive(440, 416)))
def t_lib3() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_3_len", U32.from_nat(List.length(&2, U32, LIB_3())))
    +p3 : Pd <- IO.pure(Pd, pd.parse_full(LIB_3(), 4))
    lrow("qc_pl_3", [64,416,288,48,5,8192,8192,3,2,1,1,2048,2112,2176,64,32,908])
    lrow("qc_pl_3_bufs", desc.buf_offs(Pd.bins(p3)))
    srow("qc_pl_3_consts", const.flat(Pd.consts(p3)))
    urow("qc_off_cl_3_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p3)))
    urow("qc_off_cl_3_tex", pd.cl_tex_off(Pd.ibo_cnt(p3)))
    urow("qc_off_cl_3_samp", pd.cl_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)))
    urow("qc_off_nir_3_tex", pd.nir_tex_off(Pd.tex_cnt(p3)))
    urow("qc_off_nir_3_ibo", pd.nir_ibo_off(Pd.tex_cnt(p3)))
    urow("qc_off_nir_3_samp", pd.nir_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)))
    urow("qc_pd_3_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p3)))
    urow("qc_pd_3_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p3))))
    urow("qc_pd_3_stack", pd.hw_stack_offset(Pd.pvtmem(p3)))
    urow("qc_pd_3_shared", pd.shared_size(Pd.shmem(p3)))
    urow("qc_pd_3_maxthr", pd.max_threads(Pd.fregs(p3), Pd.hregs(p3)))
    urow("qc_pd_3_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p3), Pd.ibo_cnt(p3), Pd.samp_cnt(p3)))
    row("qc_off_swap_ibo_3", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p3)),
      pd.nir_ibo_off(Pd.tex_cnt(p3))))
    row("qc_off_swap_tex_3", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p3)),
      pd.nir_tex_off(Pd.tex_cnt(p3))))
    row("qc_off_samp_agrees_3", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)),
      pd.nir_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3))))
    urow("qc_bin_seen_3", Wb.seen(desc.walk(fuel.of(1024), LIB_3(),
      Wb{Pd.bdoff(p3), 0, True{}, Nil{}})))
    urow("qc_const_bound_3", Cw.seen(pd.const_walk(LIB_3(), p3)))
    urow("qc_const_alive_first_3", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_3", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_3", Bool.to_u32(const.alive(440, 416)))
def t_lib4() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_4_len", U32.from_nat(List.length(&2, U32, LIB_4())))
    +p4 : Pd <- IO.pure(Pd, pd.parse_full(LIB_4(), 12))
    lrow("qc_pl_4", [128,416,288,48,5,1,2048,2,1,0,0,2048,2048,2048,7,3,716])
    lrow("qc_pl_4_bufs", desc.buf_offs(Pd.bins(p4)))
    srow("qc_pl_4_consts", const.flat(Pd.consts(p4)))
    urow("qc_off_cl_4_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p4)))
    urow("qc_off_cl_4_tex", pd.cl_tex_off(Pd.ibo_cnt(p4)))
    urow("qc_off_cl_4_samp", pd.cl_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)))
    urow("qc_off_nir_4_tex", pd.nir_tex_off(Pd.tex_cnt(p4)))
    urow("qc_off_nir_4_ibo", pd.nir_ibo_off(Pd.tex_cnt(p4)))
    urow("qc_off_nir_4_samp", pd.nir_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)))
    urow("qc_pd_4_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p4)))
    urow("qc_pd_4_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p4))))
    urow("qc_pd_4_stack", pd.hw_stack_offset(Pd.pvtmem(p4)))
    urow("qc_pd_4_shared", pd.shared_size(Pd.shmem(p4)))
    urow("qc_pd_4_maxthr", pd.max_threads(Pd.fregs(p4), Pd.hregs(p4)))
    urow("qc_pd_4_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p4), Pd.ibo_cnt(p4), Pd.samp_cnt(p4)))
    row("qc_off_swap_ibo_4", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p4)),
      pd.nir_ibo_off(Pd.tex_cnt(p4))))
    row("qc_off_swap_tex_4", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p4)),
      pd.nir_tex_off(Pd.tex_cnt(p4))))
    row("qc_off_samp_agrees_4", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)),
      pd.nir_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4))))
    urow("qc_bin_seen_4", Wb.seen(desc.walk(fuel.of(1024), LIB_4(),
      Wb{Pd.bdoff(p4), 0, True{}, Nil{}})))
    urow("qc_const_bound_4", Cw.seen(pd.const_walk(LIB_4(), p4)))
    urow("qc_const_alive_first_4", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_4", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_4", Bool.to_u32(const.alive(440, 416)))
def t_lib5() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_5_len", U32.from_nat(List.length(&2, U32, LIB_5())))
    +p5 : Pd <- IO.pure(Pd, pd.parse_full(LIB_5(), 24))
    lrow("qc_pl_5", [16,416,288,48,5,160,4097,0,0,2,0,2048,2048,2176,12,8,848])
    lrow("qc_pl_5_bufs", desc.buf_offs(Pd.bins(p5)))
    srow("qc_pl_5_consts", const.flat(Pd.consts(p5)))
    urow("qc_off_cl_5_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p5)))
    urow("qc_off_cl_5_tex", pd.cl_tex_off(Pd.ibo_cnt(p5)))
    urow("qc_off_cl_5_samp", pd.cl_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)))
    urow("qc_off_nir_5_tex", pd.nir_tex_off(Pd.tex_cnt(p5)))
    urow("qc_off_nir_5_ibo", pd.nir_ibo_off(Pd.tex_cnt(p5)))
    urow("qc_off_nir_5_samp", pd.nir_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)))
    urow("qc_pd_5_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p5)))
    urow("qc_pd_5_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p5))))
    urow("qc_pd_5_stack", pd.hw_stack_offset(Pd.pvtmem(p5)))
    urow("qc_pd_5_shared", pd.shared_size(Pd.shmem(p5)))
    urow("qc_pd_5_maxthr", pd.max_threads(Pd.fregs(p5), Pd.hregs(p5)))
    urow("qc_pd_5_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p5), Pd.ibo_cnt(p5), Pd.samp_cnt(p5)))
    row("qc_off_swap_ibo_5", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p5)),
      pd.nir_ibo_off(Pd.tex_cnt(p5))))
    row("qc_off_swap_tex_5", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p5)),
      pd.nir_tex_off(Pd.tex_cnt(p5))))
    row("qc_off_samp_agrees_5", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)),
      pd.nir_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5))))
    urow("qc_bin_seen_5", Wb.seen(desc.walk(fuel.of(1024), LIB_5(),
      Wb{Pd.bdoff(p5), 0, True{}, Nil{}})))
    urow("qc_const_bound_5", Cw.seen(pd.const_walk(LIB_5(), p5)))
    urow("qc_const_alive_first_5", Bool.to_u32(const.alive(320, 416)))
    urow("qc_const_alive_last_5", Bool.to_u32(const.alive(400, 416)))
    urow("qc_const_alive_past_5", Bool.to_u32(const.alive(440, 416)))


# --- 13: THE PROGRAM CACHE, :285-292 -------------------------------------
# THE SEQUENCE IS A GATE FIXTURE, not a ported fold. Three calls: hash A on
# devs [1], hash A on devs [1] again, hash B on devs [1]. The SECOND call must
# be a HIT -- that is `qc_ck_second_is_hit` -- and the FIRST call must have
# emitted PARSE, MINT, PATCH and nothing else, in that order -- that is
# `qc_ck_ckinds` is the KIND SEQUENCE of all six calls, which is the one row
# that says what the whole sequence WAS; the per-kind COUNT rows below it
# say how often.
#
# `qc_ck_older_survives` IS THE NEGATIVE CASE the brief asks for, and it is
# not an invention: `_qcom_program_cache` is a module-level dict with no
# eviction, so an entry inserted before another one is still there afterwards.
# A port with an LRU, a size cap, or a "rebuild when the cache is full" arm
# fails that row.
#
# `qc_ck_devs_splits` is the OTHER negative: the same hash on a DIFFERENT
# device set is a different key, because the key is the PAIR
# `(prg.src[3].arg, devs)`. A cache keyed on the hash alone passes every other
# row here and fails this one.

#    the cache is a MAP, so `cache[key] = ...` is an ASSIGNMENT and re-storing
# a key does not grow the dict. `ce.put` is that assignment and the six
# calls below go through it -- `qc_ck_len` is the row that says four programs
# occupy four slots, not six.
def t_cache() -> IO(Unit):
  do IO<Unit>:
    +es0 : List<&2, Ce> <- IO.pure(List<&2, Ce>, Nil{})
    +a1 : Ce <- IO.pure(Ce, qcom.get(100, [1], 8, LIB_0(), 0, es0))
    +es1 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a1, es0))
    +a2 : Ce <- IO.pure(Ce, qcom.get(100, [1], 8, LIB_0(), 1, es1))
    +es2 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a2, es1))
    +a3 : Ce <- IO.pure(Ce, qcom.get(200, [1], 8, LIB_0(), 2, es2))
    +es3 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a3, es2))
    # the negative case: A was inserted FIRST and B second, and A is still there
    +a4 : Ce <- IO.pure(Ce, qcom.get(100, [1], 8, LIB_0(), 3, es3))
    +es4 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a4, es3))
    # the other negative: same hash, different devs -> a MISS
    +a5 : Ce <- IO.pure(Ce, qcom.get(100, [2], 8, LIB_0(), 4, es4))
    +es5 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a5, es4))
    +a6 : Ce <- IO.pure(Ce, qcom.get(100, [1, 2], 8, LIB_0(), 5, es5))
    +es6 : List<&2, Ce> <- IO.pure(List<&2, Ce>, ce.put(a6, es5))
    +seq : List<&2, Call> <- IO.pure(List<&2, Call>, tr.seq([Ce.t(a1), Ce.t(a2), Ce.t(a3), Ce.t(a4), Ce.t(a5), Ce.t(a6)]))
    lrow("qc_ck_ckinds", Tr.kinds(seq))
    urow("qc_ck_nmint", Tr.count(CALL_MINT(), seq))
    urow("qc_ck_npatch", Tr.count(CALL_PATCH(), seq))
    urow("qc_ck_nhit", Tr.count(CALL_HIT(), seq))
    urow("qc_ck_nparse", Tr.count(CALL_PARSE(), seq))
    urow("qc_ck_len", ce.len(es6))
    urow("qc_ck_len_after_three", ce.len(es3))
    urow("qc_ck_len_grew_on_hit", ce.len(es4))
    row("qc_ck_second_is_hit", U32.is_eq(Tr.count(CALL_PARSE(), Tr.calls(Ce.t(a2))), 0))
    row("qc_ck_second_is_one_hit", U32.is_eq(Tr.count(CALL_HIT(), Tr.calls(Ce.t(a2))), 1))
    row("qc_ck_older_survives", U32.is_eq(Tr.count(CALL_PARSE(), Tr.calls(Ce.t(a4))), 0))
    row("qc_ck_older_is_hit", U32.is_eq(Tr.count(CALL_HIT(), Tr.calls(Ce.t(a4))), 1))
    row("qc_ck_older_same_buf", U32.is_eq(Ce.buf(a4), Ce.buf(a1)))
    row("qc_ck_devs_splits", U32.is_eq(Tr.count(CALL_PARSE(), Tr.calls(Ce.t(a5))), 1))
    row("qc_ck_devs_splits_pair", U32.is_eq(Tr.count(CALL_PARSE(), Tr.calls(Ce.t(a6))), 1))
    row("qc_ck_key_eq", Ck.eq(Ck.of(100, [1]), Ck.of(100, [1])))
    row("qc_ck_key_ne_hash", Bool.not(Ck.eq(Ck.of(100, [1]), Ck.of(200, [1]))))
    row("qc_ck_key_ne_devs", Bool.not(Ck.eq(Ck.of(100, [1]), Ck.of(100, [2]))))
    row("qc_ck_key_ne_len", Bool.not(Ck.eq(Ck.of(100, [1]), Ck.of(100, [1, 2]))))
    urow("qc_ck_key_ndevs", Ck.ndevs(Ck.of(100, [1, 2])))
    urow("qc_ck_miss_no_entry", ce.find(Ck.of(999, [7]), es3))
    row("qc_ck_miss_is_absent", U32.is_eq(ce.find(Ck.of(999, [7]), es3), NO_ENTRY()))
    # the image padding, :289 -- `ljust(round_up(len(image), 4), b"\x00")`
    urow("qc_ck_pad0", qcom.pad_len(0))
    urow("qc_ck_pad1", qcom.pad_len(1))
    urow("qc_ck_pad3", qcom.pad_len(3))
    urow("qc_ck_pad4", qcom.pad_len(4))
    urow("qc_ck_pad5", qcom.pad_len(5))
    urow("qc_ck_pad4096", qcom.pad_len(4096))
    urow("qc_ck_npad3", qcom.npad(3))
    urow("qc_ck_npad4", qcom.npad(4))
    # the buffer is as long as the PADDED image and its id is `next_num`, and
    # the three calls run in the order PARSE, MINT, PATCH.
    lrow("qc_ck_first_trace", Tr.kinds(Tr.calls(Ce.t(a1))))
    urow("qc_ck_first_buf", Ce.buf(a1))
    urow("qc_ck_second_buf", Ce.buf(a2))
    urow("qc_ck_third_buf", Ce.buf(a3))

    urow("qc_ck_parsed_imgsize", Pd.image_size(Ce.pd(a1)))
    urow("qc_ck_patched_len", qcom.pad_len(Pd.image_size(Ce.pd(a1))))

# --- 14: THE FIXED OFFSETS, one row each, :241-283 -----------------------
# Every constant of `_parse_lib` gets a row because a wrong one moves the
# WHOLE parse and every other row in this section moves with it -- which is
# why these are the rows a mutation of a constant hits, and why there is one
# per constant rather than a single "the offsets are right" boolean.
def t_offsets() -> IO(Unit):
  do IO<Unit>:
    urow("qc_off_reg_desc", OFF_REG_DESC())
    urow("qc_off_has_consts", OFF_HAS_CONSTS())
    urow("qc_off_const_tab", OFF_CONST_TAB())
    urow("qc_off_image", OFF_IMAGE())
    urow("qc_off_image_size", OFF_IMAGE_SIZE())
    urow("qc_off_image_desc", OFF_IMAGE_DESC())
    urow("qc_desc_off_prgoff", DESC_OFF_PRGOFF())
    urow("qc_desc_off_brstk", DESC_OFF_BRSTK())
    urow("qc_desc_off_pvtmem", DESC_OFF_PVTMEM())
    urow("qc_desc_off_shmem", DESC_OFF_SHMEM())
    urow("qc_desc_off_sampcnt", DESC_OFF_SAMPCNT())
    urow("qc_desc_off_kernel_desc", DESC_OFF_KERNEL_DESC())
    urow("qc_reg_off_fregs", REG_OFF_FREGS())
    urow("qc_reg_off_hregs", REG_OFF_HREGS())
    urow("qc_desc_bytes", DESC_BYTES())
    urow("qc_const_bytes", CONST_BYTES())
    urow("qc_sampler_bytes", SAMPLER_BYTES())
    urow("qc_word_to_byte", WORD_TO_BYTE())
    urow("qc_const_stride", CONST_STRIDE())
    urow("qc_name_align", NAME_ALIGN())
    urow("qc_brstk_halve", BRSTK_HALVE())
    urow("qc_align_zero", ALIGN_ZERO())
    urow("qc_tex_block", TEX_BLOCK())
    urow("qc_desc_bdoff0", desc.bdoff(288, 8, 0))
    urow("qc_desc_bdoff1", desc.bdoff(288, 8, 1))
    urow("qc_desc_bdoff2", desc.bdoff(288, 24, 0))
    urow("qc_desc_bdoff3", desc.bdoff(288, 1, 3))
    urow("qc_const_size_lo", const.size(LIB_2(), 320))
    urow("qc_const_size_hi", const.size(LIB_3(), 320))
    urow("qc_const_is32_lo", const.is32(LIB_2(), 320))
    urow("qc_const_is32_hi", const.is32(LIB_3(), 320))
    urow("qc_fuel_blob", U32.from_nat(fuel.of(1024)))
    urow("qc_fuel_bound", U32.from_nat(fuel.of(416)))

# --- 15: THE `cmd`/`reg` HEADERS, :49-59 and :57/:59 ---------------------
# `q.cmd`/`q.reg` record the OPCODE or the REGISTER in the trace and the COUNT
# goes into the header, which is a separate pure builder. Every header
# ops_qcom.py issues has a row, and the count row next to it says the WORDS.
def t_hdr() -> IO(Unit):
  do IO<Unit>:
    urow("qc_qw_h_u32", qwords([QW_U32()]))
    urow("qc_qw_h_u16", qwords([QW_U16()]))
    urow("qc_qw_h_u8", qwords([QW_U8()]))
    urow("qc_qw_h_u64", qwords([QW_U64()]))
    urow("qc_qw_h_two_u32", qwords([QW_U32(), QW_U32()]))
    urow("qc_qw_h_int", qwords([QW_INT()]))
    urow("qc_qw_h_u32_int", qwords([QW_U32(), QW_INT()]))
    urow("qc_qw_h_none", qwords(Nil{}))
    urow("qc_qw_h_u16u8", qwords([QW_U16(), QW_U8()]))
    urow("qc_h7_setmarker", q.hdr7(CP_SET_MARKER(), 1))
    urow("qc_h7_waitidle", q.hdr7(CP_WAIT_FOR_IDLE(), 0))
    urow("qc_h7_eventwrite", q.hdr7(CP_EVENT_WRITE(), 3))
    urow("qc_h7_loadconst", q.hdr7(CP_LOAD_STATE6_FRAG(), 2))
    urow("qc_h7_exec", q.hdr7(CP_EXEC_CS(), 4))
    urow("qc_h7_runcl", q.hdr7(CP_RUN_OPENCL(), 0))
    urow("qc_h7_eventinv", q.hdr7(CP_EVENT_WRITE(), 1))
    urow("qc_h7_memwrites", q.hdr7(CP_WAIT_MEM_WRITES(), 0))
    urow("qc_h7_regtomem", q.hdr7(CP_REG_TO_MEM(), 1))
    urow("qc_h7_waitregmem", q.hdr7(CP_WAIT_REG_MEM(), 5))
    urow("qc_h4_updatecntl", q.hdr4(REG_A6XX_SP_UPDATE_CNTL(), 2))
    urow("qc_h4_cs_tsize", q.hdr4(REG_A6XX_SP_CS_TSIZE(), 1))
    urow("qc_h4_cs_usize", q.hdr4(REG_A6XX_SP_CS_USIZE(), 1))
    urow("qc_h4_mode_cntl", q.hdr4(REG_A6XX_SP_MODE_CNTL(), 1))
    urow("qc_h4_perfctr", q.hdr4(REG_A6XX_SP_PERFCTR_SHADER_MASK(), 1))
    urow("qc_h4_tpl1", q.hdr4(REG_A6XX_TPL1_MODE_CNTL(), 1))
    urow("qc_h4_dbgeco", q.hdr4(REG_A6XX_TPL1_DBG_ECO_CNTL(), 1))
    urow("qc_h4_ndrange", q.hdr4(REG_A6XX_SP_CS_NDRANGE_0(), 12))
    urow("qc_h4_cntl0", q.hdr4(REG_A6XX_SP_CS_CNTL_0(), 6))
    urow("qc_h4_cntl1", q.hdr4(REG_A6XX_SP_CS_CNTL_1(), 3))
    urow("qc_h4_regprogid", q.hdr4(REG_A6XX_SP_REG_PROG_ID_0(), 5))
    urow("qc_h4_pvtmemstk", q.hdr4(REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET(), 1))
    urow("qc_h4_instrsize", q.hdr4(REG_A6XX_SP_CS_INSTR_SIZE(), 1))
    urow("qc_h4_sampbase", q.hdr4(REG_A6XX_SP_CS_SAMPLER_BASE(), 1))
    urow("qc_h4_texmembase", q.hdr4(REG_A6XX_SP_CS_TEXMEMOBJ_BASE(), 1))
    urow("qc_h4_uavbase", q.hdr4(REG_A6XX_SP_CS_UAV_BASE(), 1))
    urow("qc_h4_csconfig", q.hdr4(REG_A6XX_SP_CS_CONFIG(), 1))
    urow("qc_h4_constcfg0", q.hdr4(REG_A6XX_SP_CS_CONST_CONFIG_0(), 2))

# --- 16: THE CACHE FLUSH, :61-70 -----------------------------------------
# FOUR independent conditionals in ONE def, and the ISSUE order is not the
# PARAMETER order: Python tests write_back, invalidate, sync, memsync and
# issues memsync BEFORE sync. `qc_flush_issue_order` is the row that says so
# and `qc_flush_issue_order_is_not_param` says the mapping is not the
# identity -- a port that folds over the parameter order emits WAIT_FOR_IDLE
# one step early.
def t_flush() -> IO(Unit):
  do IO<Unit>:
    lrow("qc_flush_kinds_none", Tr.kinds(Tr.calls(flush.of(FLUSH_NONE(), Tr.of()))))
    lrow("qc_flush_kinds_wb", Tr.kinds(Tr.calls(flush.of(FLUSH_EXEC(), Tr.of()))))
    lrow("qc_flush_kinds_barrier", Tr.kinds(Tr.calls(flush.of(FLUSH_BARRIER(), Tr.of()))))
    lrow("qc_flush_kinds_sync", Tr.kinds(Tr.calls(flush.of(FLUSH_SYNC_ONLY(), Tr.of()))))
    lrow("qc_flush_kinds_memsync", Tr.kinds(Tr.calls(flush.of(FLUSH_MEMSYNC_ONLY(), Tr.of()))))
    urow("qc_flush_ops_barrier", Tr.count(CALL_CMD7(), Tr.calls(flush.of(FLUSH_BARRIER(), Tr.of()))))
    urow("qc_flush_ops_wb", Tr.count(CALL_CMD7(), Tr.calls(flush.of(FLUSH_EXEC(), Tr.of()))))
    urow("qc_flush_ops_none", Tr.count(CALL_CMD7(), Tr.calls(flush.of(FLUSH_NONE(), Tr.of()))))
    lrow("qc_flush_ops_sync", Tr.args(CALL_CMD7(), Tr.calls(flush.of(FLUSH_SYNC_ONLY(), Tr.of()))))
    lrow("qc_flush_ops_memsync", Tr.args(CALL_CMD7(), Tr.calls(flush.of(FLUSH_MEMSYNC_ONLY(), Tr.of()))))
    urow("qc_flush_write_back_words", flush.cnt(0))
    urow("qc_flush_others_words", flush.cnt(3))
    row("qc_flush_issue_not_param", Bool.not(u32_list_eq(ISSUE_AT(), FLAGS())))

# --- 17: `exec` -- THE REGISTER SEQUENCE, :115-192 ----------------------
# ONE row per arm of the four forks, plus the two order rows. `qc_exec_cl` is
# the CL arm end to end (no samplers, no textures, no ibos, not NIR) and
# `qc_exec_nir` is the NIR arm with all three counts non-zero; the two differ
# only at the tail, which is what makes the pair worth printing.
def t_exec() -> IO(Unit):
  do IO<Unit>:
    +cl : Tr <- IO.pure(Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 0, 0, 0, False{}, False{}))
    +full : Tr <- IO.pure(Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 2, 1, 1, False{}, False{}))
    +nir : Tr <- IO.pure(Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 2, 1, 1, True{}, False{}))
    lrow("qc_exec_cl_kinds", Tr.kinds(Tr.calls(cl)))
    lrow("qc_exec_full_kinds", Tr.kinds(Tr.calls(full)))
    lrow("qc_exec_nir_kinds", Tr.kinds(Tr.calls(nir)))
    lrow("qc_exec_cl_regs", Tr.args(CALL_CMD4(), Tr.calls(cl)))
    lrow("qc_exec_nir_regs", Tr.args(CALL_CMD4(), Tr.calls(nir)))
    lrow("qc_exec_cl_cmds", Tr.args(CALL_CMD7(), Tr.calls(cl)))
    lrow("qc_exec_nir_cmds", Tr.args(CALL_CMD7(), Tr.calls(nir)))
    urow("qc_exec_cl_n", seen(cl))
    urow("qc_exec_full_n", seen(full))
    urow("qc_exec_nir_n", seen(nir))
    row("qc_exec_cl_ends_runcl", U32.is_eq(exec.dispatch(cl), CP_RUN_OPENCL()))
    row("qc_exec_nir_ends_exec", U32.is_eq(exec.dispatch(nir), CP_EXEC_CS()))
    urow("qc_exec_cl_dispatch", exec.dispatch(cl))
    urow("qc_exec_nir_dispatch", exec.dispatch(nir))
    # the LAST cmd of each trace is the :192 cache flush, and it is the SAME
    # opcode on both arms -- which is why it cannot say which fork fired and
    # `exec.last_cmd` has to be the last cmd BEFORE it.
    row("qc_exec_cl_last_flush", U32.is_eq(exec.last_cmd(cl), CP_EVENT_WRITE()))
    row("qc_exec_nir_last_flush", U32.is_eq(exec.last_cmd(nir), CP_EVENT_WRITE()))
    urow("qc_exec_cl_lastcmd", exec.last_cmd(cl))
    urow("qc_exec_nir_lastcmd", exec.last_cmd(nir))
    # `Tr.kinds` is a SEQUENCE and these are SUBSEQUENCES, so the rows are
    # subsequence tests rather than equality. `qc_exec_nir_two_regs_at_end`
    # is the one that says the NIR tail is TWO calls and not three.
    row("qc_exec_pre_first", seq(Tr.calls(nir), [Call{CALL_CMD7, CP_SET_MARKER}]))
    row("qc_exec_ndrange_then_cntl0", seq(Tr.calls(nir),
      [Call{CALL_CMD4, REG_A6XX_SP_CS_NDRANGE_0}, Call{CALL_CMD4, REG_A6XX_SP_CS_CNTL_0}]))
    row("qc_exec_config_before_tail", seq(Tr.calls(nir),
      [Call{CALL_CMD4, REG_A6XX_SP_CS_CONFIG}, Call{CALL_CMD4, REG_A6XX_SP_CS_CONST_CONFIG_0},
       Call{CALL_CMD7, CP_EXEC_CS}]))
    row("qc_exec_no_nir_tail_in_cl", Bool.not(seq(Tr.calls(cl), [Call{CALL_CMD7, CP_EXEC_CS}])))
    row("qc_exec_nir_no_runcl", Bool.not(seq(Tr.calls(nir), [Call{CALL_CMD7, CP_RUN_OPENCL}])))
    row("qc_exec_samp_base_present", seq(Tr.calls(full), [Call{CALL_CMD4, REG_A6XX_SP_CS_SAMPLER_BASE}]))
    row("qc_exec_tex_base_present", seq(Tr.calls(full), [Call{CALL_CMD4, REG_A6XX_SP_CS_TEXMEMOBJ_BASE}]))
    row("qc_exec_uav_base_present", seq(Tr.calls(full), [Call{CALL_CMD4, REG_A6XX_SP_CS_UAV_BASE}]))
    row("qc_exec_cl_has_no_bases", Bool.not(seq(Tr.calls(cl),
      [Call{CALL_CMD4, REG_A6XX_SP_CS_SAMPLER_BASE}])))
    row("qc_exec_border_color_after_sampler", seq(Tr.calls(full),
      [Call{CALL_CMD4, REG_A6XX_SP_CS_SAMPLER_BASE}, Call{CALL_CMD4, REG_A6XX_TPL1_CS_BORDER_COLOR_BASE}]))
    row("qc_exec_no_border_without_sampler", Bool.not(seq(Tr.calls(cl),
      [Call{CALL_CMD4, REG_A6XX_TPL1_CS_BORDER_COLOR_BASE}])))
    urow("qc_exec_full_regs_n", U32.from_nat(List.length(&2, U32, Tr.args(CALL_CMD4(), Tr.calls(full)))))
    urow("qc_exec_nir_regs_n", U32.from_nat(List.length(&2, U32, Tr.args(CALL_CMD4(), Tr.calls(nir)))))
    # the trailing `self._cache_flush(True, False, False, False)` of :192
    lrow("qc_exec_tail_flush", Tr.kinds(Tr.calls(exec.of3(0, 0, 0, False{}, exec.mid()))))
    lrow("qc_exec_flush_only", Tr.kinds(Tr.calls(flush.of(FLUSH_EXEC(), Tr.of()))))

# --- 18: THE FOUR REFUSALS, :79, :118, :120, :332 -----------------------
# Every one of these is a TRUNCATION, not a flag: `Tr.emit` records nothing
# once `refused` is set, so `qc_rf_res_traces=0` is the claim -- nothing at
# all is written once the refusal fires. `qc_rf_dim_hugels` is the fixture
# that separates the TWO `any`s of :119: a local size over 1024 with a total
# UNDER 65536 is ACCEPTED, and a "one dimension" transcription would refuse it.
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +r1 : Tr <- IO.pure(Tr, exec.of(63, [16, 1, 1], [64, 1, 1], 0, 0, 0, False{}, False{}))
    +r2 : Tr <- IO.pure(Tr, exec.of(256, [64, 1, 1], [2048, 1, 1], 0, 0, 0, False{}, False{}))
    +r3 : Tr <- IO.pure(Tr, exec.of(256, [1, 1, 1], [8, 1, 1], 0, 0, 0, False{}, False{}))
    urow("qc_rf_res_traces", seen(r1))
    urow("qc_rf_dim_traces", seen(r2))
    urow("qc_rf_ok_traces", seen(r3))
    row("qc_rf_res_refused", Tr.refused(r1))
    row("qc_rf_dim_refused", Tr.refused(r2))
    row("qc_rf_ok_not_refused", Bool.not(Tr.refused(r3)))
    row("qc_rf_res_pred", rf.resources(63, 64, 1, 1))
    row("qc_rf_res_ok", Bool.not(rf.resources(256, 8, 1, 1)))
    row("qc_rf_res_1024", Bool.not(rf.resources(1024, 1024, 1, 1)))
    row("qc_rf_res_over", rf.resources(1024, 1025, 1, 1))
    row("qc_rf_res_3d", rf.resources(1024, 64, 64, 64))
    row("qc_rf_res_3d_ok", Bool.not(rf.resources(1024, 8, 8, 8)))
    row("qc_rf_dim_total", rf.dims([64, 1, 1], [2048, 1, 1]))
    row("qc_rf_dim_total_65536", rf.dims([65536, 1, 1], [2, 1, 1]))
    row("qc_rf_dim_total_ok", Bool.not(rf.dims([1, 1, 1], [2048, 1, 1])))
    row("qc_rf_dim_local", rf.dims([65536, 1, 1], [2, 1, 1]))
    row("qc_rf_dim_local_none", rf.dims([65536, 1, 1], [1, 1, 1]))
    row("qc_rf_dim_local_ok", Bool.not(rf.dims([1, 1, 1], [1, 1, 1])))
    row("qc_rf_dim_z", rf.dims([1, 1, 1], [1, 1, 70000]))
    row("qc_rf_dim_edge", rf.dims([65535, 1, 1], [1, 1, 1]))
    # :74 and :332 are the SAME PREDICATE with opposite senses.
    row("qc_rf_gpu_a730", rf.gpu_ge73(7, 3))
    row("qc_rf_gpu_a720", Bool.not(rf.gpu_ge73(7, 2)))
    row("qc_rf_gpu_a650", Bool.not(rf.gpu_ge73(6, 5)))
    row("qc_rf_gpu_a640", Bool.not(rf.gpu_ge73(6, 4)))
    row("qc_rf_gpu_a800", rf.gpu_ge73(8, 0))
    row("qc_rf_gpu_a612", Bool.not(rf.gpu_ge73(6, 1)))
    row("qc_rf_sig_a650", rf.gpu_lt73(6, 5))
    row("qc_rf_sig_a730", Bool.not(rf.gpu_lt73(7, 3)))
    # :79 is DEAD on this backend and the row says so rather than pretending
    # the arm is live: :332 already refused every gpu_id the arm guards.
    row("qc_rf_event7_unreachable", Bool.not(rf.gpu_lt73(7, 3)))

# --- 19: `submit` -- the ioctl command word, :202-203 -------------------
# `(idir << 30) | (sizeof(struct_t) << 16) | (base << 8) | nr`. All four
# fields come out of `kgsl.IOCTL_KGSL_GPU_COMMAND.args` and `ctypes.sizeof`,
# and each has its own row because a wrong shift is a wrong ioctl and the
# four shifts do not commute.
def t_submit() -> IO(Unit):
  do IO<Unit>:
    urow("qc_io_dir", IOCTL_DIR())
    urow("qc_io_base", IOCTL_BASE())
    urow("qc_io_nr", IOCTL_NR())
    urow("qc_io_size", IOCTL_SIZE())
    urow("qc_io_cmd", ioctl_cmd())
    urow("qc_io_cmd_dir", U32.shrn(ioctl_cmd(), 30n))
    urow("qc_io_cmd_size", U32.and(U32.shrn(ioctl_cmd(), 16n), 255))
    urow("qc_io_cmd_base", U32.and(U32.shrn(ioctl_cmd(), 8n), 255))
    urow("qc_io_cmd_nr", U32.and(ioctl_cmd(), 255))
    urow("qc_io_shift_dir", IOCTL_SHIFT_DIR())
    urow("qc_io_shift_size", IOCTL_SHIFT_SIZE())
    urow("qc_io_shift_base", IOCTL_SHIFT_BASE())
    urow("qc_io_shift_nr", IOCTL_SHIFT_NR())

# --- 20: `layout_args` / `pack_args` -- THE KERNEL ARGUMENT LAYOUT ------
# hcq2.py:74-83. `layout_args` places each word at a 4-BYTE STRIDED offset
# from the block base -- a u16 argument still occupies four -- and
# `pack_args` walks the offsets in SORTED order emitting one BINARY pad per
# GAP, then a final pad of `size - end`. The gap SEQUENCE is the kernel
# argument trace, and `qc_la_mix` is the row that says a half-word argument
# advances the cursor by four.
def t_layout() -> IO(Unit):
  do IO<Unit>:
    lrow("qc_la_empty", layout_args.of(Nil{}, ALIGN_ZERO()))
    lrow("qc_la_one", layout_args.of([4], ALIGN_ZERO()))
    lrow("qc_la_three", layout_args.of([4, 4, 4], ALIGN_ZERO()))
    lrow("qc_la_six", layout_args.of([4, 4, 4, 4, 4, 4], ALIGN_ZERO()))
    lrow("qc_la_mix", layout_args.of([4, 2, 4], ALIGN_ZERO()))
    lrow("qc_la2_mix", layout_args.of([4, 2, 4], 0))
    lrow("qc_pa_tight", pack_args.of([2048, 2052], 2560))
    lrow("qc_pa_gap", pack_args.of([2048, 2064], 2560))
    lrow("qc_pa_big_gap", pack_args.of([0, 64], 128))
    lrow("qc_pa_unsorted", pack_args.of([2064, 2048], 2560))
    lrow("qc_pa_huge_tail", pack_args.of([2048], 4096))
    lrow("qc_pa_empty", pack_args.of(Nil{}, 256))
    urow("qc_pa_align", pack_args.align())


# --- 4: NINE WHOLE REGISTER VALUES, from `_qreg_exec` ITSELF --------------
# The per-field rows above pin the pieces; these pin the ASSEMBLY, which is
# where OR-vs-add and a mistyped shift cancel out. Nine sites, chosen so that
# between them they cover a four-field shifted register, a five-field register
# WITH a positional `__val`, two bool-carrying registers, a shifted register
# whose four shifts are 14/16/18/22, and the `_64b` field at :83 whose key
# carries the LEADING UNDERSCORE `_qreg_exec` strips with `removeprefix`.
def t_regvals() -> IO(Unit):
  do IO<Unit>:
    urow("qc_rv_ndrange", qreg.of("a6xx_sp_cs_ndrange_0", [Fv{"KERNELDIM", 3}, Fv{"LOCALSIZEX", 7}, Fv{"LOCALSIZEY", 15}, Fv{"LOCALSIZEZ", 3}]))
    urow("qc_rv_texconst0", U32.or(qreg.pos(8), qreg.of("a6xx_tex_const_0", [Fv{"FMT", 130}, Fv{"SWIZ_X", 0}, Fv{"SWIZ_Y", 1}, Fv{"SWIZ_Z", 2}, Fv{"SWIZ_W", 3}])))
    urow("qc_rv_csconfig", qreg.of("a6xx_sp_cs_config", [Fv{"ENABLED", 1}, Fv{"NSAMP", 2}, Fv{"NTEX", 1}, Fv{"NUAV", 3}]))
    urow("qc_rv_loadstate6", qreg.of("cp_load_state6_0", [Fv{"STATE_TYPE", 1}, Fv{"STATE_SRC", 2}, Fv{"STATE_BLOCK", 13}, Fv{"NUM_UNIT", 64}]))
    urow("qc_rv_cntl0", qreg.of("a6xx_sp_cs_cntl_0", [Fv{"THREADSIZE", 0}, Fv{"HALFREGFOOTPRINT", 32}, Fv{"FULLREGFOOTPRINT", 48}, Fv{"BRANCHSTACK", 4}]))
    urow("qc_rv_samp0", qreg.of("a6xx_tex_samp_0", [Fv{"WRAP_S", 3}, Fv{"WRAP_T", 3}, Fv{"WRAP_R", 3}]))
    urow("qc_rv_samp1", qreg.of("a6xx_tex_samp_1", [Fv{"UNNORM_COORDS", 1}, Fv{"CUBEMAPSEAMLESSFILTOFF", 1}]))
    urow("qc_rv_regtomem", qreg.of("cp_reg_to_mem_0", [Fv{"REG", 2432}, Fv{"CNT", 2}, Fv{"64B", 1}]))
    urow("qc_rv_updcntl", qreg.of("a6xx_sp_update_cntl", [Fv{"CS_STATE", 1}, Fv{"CS_UAV", 1}]))
    # a FALSE bool contributes ZERO, which is :39's `if v else 0` arm and NOT
    # `1 << shift`. Two rows differ by exactly that, which is what pins it.
    urow("qc_rv_samp1_off", qreg.of("a6xx_tex_samp_1", [Fv{"UNNORM_COORDS", 0}, Fv{"CUBEMAPSEAMLESSFILTOFF", 0}]))
    urow("qc_rv_samp1_part", qreg.of("a6xx_tex_samp_1", [Fv{"UNNORM_COORDS", 1}, Fv{"CUBEMAPSEAMLESSFILTOFF", 0}]))
    # a shifted field given 0 is 0, so a row that ORs in `v << shift` for a
    # bool field would answer 1 << 32-ish nonsense here. The two rows that
    # differ are the discriminator.
    urow("qc_rv_csconfig_off", qreg.of("a6xx_sp_cs_config", [Fv{"ENABLED", 0}, Fv{"NSAMP", 0}, Fv{"NTEX", 0}, Fv{"NUAV", 0}]))

# --- 5: ctz, :43 ---------------------------------------------------------
# `qc_ctz_nonzero` states the PRECONDITION rather than trusting it: `pitch` at
# :106 is `shape[1] * 4 * imgdt.itemsize`, so `ctz(pitch) >= 2` always and the
# `v == 0` case -- the only one where the port's `32` and Python's `-1` differ
# -- cannot be reached from `exec`.
def t_ctz() -> IO(Unit):
  do IO<Unit>:
    urow("qc_ctz_00000001", ctz(1))
    urow("qc_ctz_00000002", ctz(2))
    urow("qc_ctz_00000040", ctz(64))
    urow("qc_ctz_00001000", ctz(4096))
    urow("qc_ctz_80000000", ctz(2147483648))
    urow("qc_ctz_00004000", ctz(16384))
    urow("qc_ctz_0000003f", ctz(63))
    row("qc_ctz_nonzero", Bool.and(U32.is_ge(ctz(4), 2), U32.is_ge(ctz(4096), 12)))
    urow("qc_ctz_zero", ctz(0))

# --- 6: parity, :45-47 ---------------------------------------------------
# Three rounds `>> 16`, `>> 8`, `>> 4` -- `range(4, 1, -1)` is {4,3,2} and
# `1 << i` is 16, 8, 4, NOT 4, 2, 1 -- then `(~0x6996 >> (v & 0xf)) & 1`.
# `qc_parity_all16` walks all sixteen residues so no single fixture can be
# right by luck.
def t_parity() -> IO(Unit):
  do IO<Unit>:
    urow("qc_parity_00000", parity(0))
    urow("qc_parity_00001", parity(1))
    urow("qc_parity_00002", parity(2))
    urow("qc_parity_00003", parity(3))
    urow("qc_parity_00004", parity(4))
    urow("qc_parity_00005", parity(5))
    urow("qc_parity_00007", parity(7))
    urow("qc_parity_00008", parity(8))
    urow("qc_parity_0000f", parity(15))
    urow("qc_parity_00010", parity(16))
    urow("qc_parity_000ff", parity(255))
    urow("qc_parity_00100", parity(256))
    urow("qc_parity_03fff", parity(16383))
    urow("qc_parity_0007f", parity(127))
    urow("qc_parity_3ffff", parity(262143))
    urow("qc_parity_xor", PARITY_XOR())
    urow("qc_parity_fold16", parity.folded(65535))
    urow("qc_parity_fold3", parity.folded(65536))

# --- 7: pkt7_hdr / pkt4_hdr, :49 and :51 ---------------------------------
# `|` BINDS LOOSER THAN `&` AND `<<` in Python, so these are five independent
# contributions OR-ed, not a left-to-right chain. The masks and the two high
# parity bits (<< 23 and << 27) are the parts a rewrite gets wrong, and the
# CP_TYPE7/4 tag already sits in bit 30, so these are u32 and not i32.
def t_pkt() -> IO(Unit):
  do IO<Unit>:
    urow("qc_pkt7_38_0", pkt7_hdr(38, 0))
    urow("qc_pkt7_70_3", pkt7_hdr(70, 3))
    urow("qc_pkt7_52_2", pkt7_hdr(52, 2))
    urow("qc_pkt7_101_1", pkt7_hdr(101, 1))
    urow("qc_pkt7_51_4", pkt7_hdr(51, 4))
    urow("qc_pkt7_49_0", pkt7_hdr(49, 0))
    urow("qc_pkt7_62_1", pkt7_hdr(62, 1))
    urow("qc_pkt7_60_5", pkt7_hdr(60, 5))
    urow("qc_pkt4_47504_12", pkt4_hdr(47504, 12))
    urow("qc_pkt4_43440_6", pkt4_hdr(43440, 6))
    urow("qc_pkt4_43452_1", pkt4_hdr(43452, 1))
    urow("qc_pkt4_45833_1", pkt4_hdr(45833, 1))
    urow("qc_pkt4_47880_2", pkt4_hdr(47880, 2))
    urow("qc_pkt4_43451_1", pkt4_hdr(43451, 1))
    urow("qc_pkt7_tag", CP_TYPE7_PKT())
    urow("qc_pkt4_tag", CP_TYPE4_PKT())

# --- 8: _read_lib, :53 ---------------------------------------------------
# `struct.unpack("I", lib[off:off+4])[0]` -- LITTLE endian. The fixture is
# the oracle's own 16-byte `struct.pack('<4I', 0xDEADBEEF, 1, 0xFFFFFFFF,
# 0x80000000)`, and `qc_rl_bytes` echoes it back so a bend-side fixture that
# drifts from the oracle's is visible as a row rather than as four wrong
# reads. Byte order is invisible if every fixture word is palindromic, so
# 0xDEADBEEF and 0x80000000 are both in the fixture.
def RL_LIB() -> List<&2, U32>:
  [239, 190, 173, 222, 1, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 128]

def t_readlib() -> IO(Unit):
  do IO<Unit>:
    urow("qc_rl_0", read_lib(RL_LIB(), 0))
    urow("qc_rl_4", read_lib(RL_LIB(), 4))
    urow("qc_rl_8", read_lib(RL_LIB(), 8))
    urow("qc_rl_12", read_lib(RL_LIB(), 12))
    lrow("qc_rl_words", read_words(4n, RL_LIB(), 0))
    lrow("qc_rl_tail", read_words(2n, RL_LIB(), 8))
    urow("qc_rl_past_end", read_lib(RL_LIB(), 16))

# --- 9: the `cmd`/`reg` word count, :57 and :59 ---------------------------
# `x.dtype.itemsize // 4 if isinstance(x, UOp) else 1`. A `dtypes.uint8`
# buffer is itemsize 1 and so counts ZERO words, not one -- `qc_qw_u8_u32`
# is 1, not 2, and that is the row that says so. A bare int is one word
# whatever its magnitude.
def t_qwords() -> IO(Unit):
  do IO<Unit>:
    urow("qc_qw_u8_u32", qwords([QW_U8(), QW_U32()]))
    urow("qc_qw_u16", qwords([QW_U16()]))
    urow("qc_qw_u64", qwords([QW_U64()]))
    urow("qc_qw_ints", qwords([QW_INT(), QW_INT()]))
    urow("qc_qw_u32_int", qwords([QW_U32(), QW_INT()]))
    urow("qc_qw_none", qwords(Nil{}))
    urow("qc_qw_is_int", qwords.is(False{}, 4))
    urow("qc_qw_is_u64", qwords.is(True{}, 8))
    urow("qc_qw_is_u8", qwords.is(True{}, 1))

# --- 10: flag(), :303 ---------------------------------------------------
# `(val << SHIFT) & MASK`. The `& MASK` is load-bearing and invisible for
# `KGSL_MEMALIGN` and `KGSL_CONTEXT_PRIORITY` if the fixture value fits, so
# `qc_flag_clipped` uses 4095 -- wider than PRIORITY's six bits -- and it is
# the row that says the mask is applied.
def t_flag() -> IO(Unit):
  do IO<Unit>:
    urow("qc_flag_CONTEXT_PRIORITY_shift", 12)
    urow("qc_flag_CONTEXT_PRIORITY_mask", 61440)
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_shift", 25)
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_mask", 234881024)
    urow("qc_flag_MEMALIGN_shift", 16)
    urow("qc_flag_MEMALIGN_mask", 16711680)
    urow("qc_flag_CACHEMODE_shift", 26)
    urow("qc_flag_CACHEMODE_mask", 201326592)
    urow("qc_flag_CONTEXT_PRIORITY_of_8", flag("KGSL_CONTEXT_PRIORITY", 8))
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_of_2", flag("KGSL_CONTEXT_PREEMPT_STYLE", 2))
    urow("qc_flag_MEMALIGN_of_12", flag("KGSL_MEMALIGN", 12))
    urow("qc_flag_CACHEMODE_of_1", flag("KGSL_CACHEMODE", 1))
    urow("qc_flag_clipped", flag(FLAG_PRIORITY(), 4095))
    urow("qc_flag_clipped_align", flag(FLAG_MEMALIGN(), 255))
    srow("qc_flagname_0", kgsl_name_at(0))
    srow("qc_flagname_3", kgsl_name_at(3))
    urow("qc_flagix_malign", kgsl_ix(FLAG_MEMALIGN()))
    urow("qc_flagix_absent", kgsl_ix("KGSL_NOSUCH"))
    srow("qc_flagname_absent", kgsl_name_at(NO_SUCH_FLAG()))

# --- 11: the 62 mesa/kgsl CONSTANTS -------------------------------------
# Transcribed once each from the oracle, and the oracle reads them off the
# LIVE autogen modules by walking the AST of ops_qcom.py, so a stale number
# here is a row that moves. They are named without a module prefix because
# the oracle ASSERTS the two namespaces do not collide.
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("qc_c_KGSL_CACHEMODE_UNCACHED", KGSL_CACHEMODE_UNCACHED())
    urow("qc_c_KGSL_CMDLIST_IB", KGSL_CMDLIST_IB())
    urow("qc_c_KGSL_CONTEXT_NO_FAULT_TOLERANCE", KGSL_CONTEXT_NO_FAULT_TOLERANCE())
    urow("qc_c_KGSL_CONTEXT_NO_GMEM_ALLOC", KGSL_CONTEXT_NO_GMEM_ALLOC())
    urow("qc_c_KGSL_CONTEXT_PREAMBLE", KGSL_CONTEXT_PREAMBLE())
    urow("qc_c_KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN", KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN())
    urow("qc_c_KGSL_CONTEXT_PWR_CONSTRAINT", KGSL_CONTEXT_PWR_CONSTRAINT())
    urow("qc_c_KGSL_MEMFLAGS_USE_CPU_MAP", KGSL_MEMFLAGS_USE_CPU_MAP())
    urow("qc_c_KGSL_PROP_DEVICE_INFO", KGSL_PROP_DEVICE_INFO())
    urow("qc_c_KGSL_PROP_PWR_CONSTRAINT", KGSL_PROP_PWR_CONSTRAINT())
    urow("qc_c_KGSL_TIMESTAMP_QUEUED", KGSL_TIMESTAMP_QUEUED())
    urow("qc_c_KGSL_USER_MEM_TYPE_ADDR", KGSL_USER_MEM_TYPE_ADDR())
    urow("qc_c_A6XX_TEX_2D", A6XX_TEX_2D())
    urow("qc_c_A6XX_TEX_CLAMP_TO_BORDER", A6XX_TEX_CLAMP_TO_BORDER())
    urow("qc_c_CACHE_FLUSH_TS", CACHE_FLUSH_TS())
    urow("qc_c_CACHE_INVALIDATE", CACHE_INVALIDATE())
    urow("qc_c_CONSTLEN_256", CONSTLEN_256())
    urow("qc_c_CP_EVENT_WRITE", CP_EVENT_WRITE())
    urow("qc_c_CP_EXEC_CS", CP_EXEC_CS())
    urow("qc_c_CP_LOAD_STATE6_FRAG", CP_LOAD_STATE6_FRAG())
    urow("qc_c_CP_REG_TO_MEM", CP_REG_TO_MEM())
    urow("qc_c_CP_RUN_OPENCL", CP_RUN_OPENCL())
    urow("qc_c_CP_SET_MARKER", CP_SET_MARKER())
    urow("qc_c_CP_TYPE4_PKT", CP_TYPE4_PKT())
    urow("qc_c_CP_TYPE7_PKT", CP_TYPE7_PKT())
    urow("qc_c_CP_WAIT_FOR_IDLE", CP_WAIT_FOR_IDLE())
    urow("qc_c_CP_WAIT_MEM_WRITES", CP_WAIT_MEM_WRITES())
    urow("qc_c_CP_WAIT_REG_MEM", CP_WAIT_REG_MEM())
    urow("qc_c_FMT6_16_16_16_16_FLOAT", FMT6_16_16_16_16_FLOAT())
    urow("qc_c_FMT6_32_32_32_32_FLOAT", FMT6_32_32_32_32_FLOAT())
    urow("qc_c_IR3_CONST_ALLOC_DRIVER_PARAMS", IR3_CONST_ALLOC_DRIVER_PARAMS())
    urow("qc_c_ISAMMODE_CL", ISAMMODE_CL())
    urow("qc_c_ISAMMODE_GL", ISAMMODE_GL())
    urow("qc_c_POLL_MEMORY", POLL_MEMORY())
    urow("qc_c_REG_A6XX_CP_ALWAYS_ON_COUNTER", REG_A6XX_CP_ALWAYS_ON_COUNTER())
    urow("qc_c_REG_A6XX_SP_CS_CNTL_0", REG_A6XX_SP_CS_CNTL_0())
    urow("qc_c_REG_A6XX_SP_CS_CONFIG", REG_A6XX_SP_CS_CONFIG())
    urow("qc_c_REG_A6XX_SP_CS_CONST_CONFIG_0", REG_A6XX_SP_CS_CONST_CONFIG_0())
    urow("qc_c_REG_A6XX_SP_CS_INSTR_SIZE", REG_A6XX_SP_CS_INSTR_SIZE())
    urow("qc_c_REG_A6XX_SP_CS_NDRANGE_0", REG_A6XX_SP_CS_NDRANGE_0())
    urow("qc_c_REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET", REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET())
    urow("qc_c_REG_A6XX_SP_CS_SAMPLER_BASE", REG_A6XX_SP_CS_SAMPLER_BASE())
    urow("qc_c_REG_A6XX_SP_CS_TEXMEMOBJ_BASE", REG_A6XX_SP_CS_TEXMEMOBJ_BASE())
    urow("qc_c_REG_A6XX_SP_CS_TSIZE", REG_A6XX_SP_CS_TSIZE())
    urow("qc_c_REG_A6XX_SP_CS_UAV_BASE", REG_A6XX_SP_CS_UAV_BASE())
    urow("qc_c_REG_A6XX_SP_CS_USIZE", REG_A6XX_SP_CS_USIZE())
    urow("qc_c_REG_A6XX_SP_MODE_CNTL", REG_A6XX_SP_MODE_CNTL())
    urow("qc_c_REG_A6XX_SP_PERFCTR_SHADER_MASK", REG_A6XX_SP_PERFCTR_SHADER_MASK())
    urow("qc_c_REG_A6XX_SP_REG_PROG_ID_0", REG_A6XX_SP_REG_PROG_ID_0())
    urow("qc_c_REG_A6XX_SP_UPDATE_CNTL", REG_A6XX_SP_UPDATE_CNTL())
    urow("qc_c_REG_A6XX_TPL1_CS_BORDER_COLOR_BASE", REG_A6XX_TPL1_CS_BORDER_COLOR_BASE())
    urow("qc_c_REG_A6XX_TPL1_DBG_ECO_CNTL", REG_A6XX_TPL1_DBG_ECO_CNTL())
    urow("qc_c_REG_A6XX_TPL1_MODE_CNTL", REG_A6XX_TPL1_MODE_CNTL())
    urow("qc_c_RM6_COMPUTE", RM6_COMPUTE())
    urow("qc_c_SB6_CS_SHADER", SB6_CS_SHADER())
    urow("qc_c_SB6_CS_TEX", SB6_CS_TEX())
    urow("qc_c_SS6_INDIRECT", SS6_INDIRECT())
    urow("qc_c_ST6_UAV", ST6_UAV())
    urow("qc_c_ST_CONSTANTS", ST_CONSTANTS())
    urow("qc_c_ST_SHADER", ST_SHADER())
    urow("qc_c_THREAD64", THREAD64())
    urow("qc_c_WRITE_GE", WRITE_GE())


# ===========================================================================
# THE MUTATION TABLE. Every number is the harness's output
# (`.agents/slop/qc_stage3_oracle.py` is not involved; the harness is
# `.agents/slop/qc/`'s mutate.sh, which applies ONE edit to a scratch copy in
# this directory, runs the INTERPRETED lane, and diffs the row NAMES). The
# useful column is "rows MOVED": a mutation that moves nothing measures what
# this gate does NOT see.
#
# MEASURED WHILE WRITING THIS FILE -- fourteen of these are not exercises, they
# are the bugs the gate caught in the port, and each is listed with the row that
# caught it:
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `qreg.one`: a bool field contributes its bit regardless of the VALUE | 3 | :39's `getattr(mesa, reg_name) if v else 0`. Caught by `qc_rv_samp1_off` / `qc_rv_samp1_part` / `qc_rv_csconfig_off`, which differ from their all-on neighbours by exactly the zero arm. |
# | M2 | `qreg.of.go2`: `U32.add` instead of `U32.or` | 2 | the OR at :39. Only the two fixtures with overlapping bits move, which is why `qc_rv_texconst0` (a five-field register) is one of them. |
# | M3 | `parity.round16`: `>> 4n` instead of `>> 16n` | 4 | `1 << i` for `i in range(4, 1, -1)`. |
# | M4 | `PARITY_XOR`: 38504 instead of 38505 | 4 | the `~0x6996` table. CAUGHT A REAL BUG: the constant was hand-typed as 24425 first and every `qc_pkt*` row moved at once. |
# | M5 | `pkt7_hdr`: `parity(opcode) << 24n` | 8 | the `<< 23` and its position above `CP_TYPE7_PKT`. |
# | M6 | `pkt4_hdr`: `parity(reg) << 26n` | 6 | the `<< 27`. |
# | M7 | `read_words`: `List.reverse` at the end as well as `List.append` | 2 | `List.append(a, A, xs, ys)` IS `xs ++ ys`. Caught a real bug: every word list printed backwards. |
# | M8 | `Tr.kinds`: reverse as well as append | 1 | the same trap in the trace reader, and `qc_ck_first_trace` is the row whose ONLY claim is the order of the three miss-path calls. |
# | M9 | `qwords.is`: `// 1` instead of `// 4` | 4 | :57's `x.dtype.itemsize // 4`. |
# | M10 | `qreg_ix` / `kgsl_ix`: seed the accumulator with `0` | 2 | that a lookup MISS is a SENTINEL and not index 0. `0` is `a6xx_cp_set_marker_0` and `KGSL_CONTEXT_PRIORITY`, so a miss that answered 0 would write to the wrong register. |
# | M11 | `desc.alive`: drop the `length == 0` conjunct | 12 | the descriptor walk's TERMINATOR. Without it the zeroed tail of the blob reads as one more `BUFTYPE_BUF` at offset 0, and `qc_pl_<k>_bufs` and `qc_bin_seen_<k>` both grow. |
# | M12 | `const.alive`: bound by 4096 instead of `image_offset` | 12 | the constant walk's bound is a field of the blob and NOT `len(lib)`. |
# | M13 | `pd.nir_tex_off`: `2048 + 0x40*tex_cnt` | 6 | :228 assigns the BARE 2048 to `tex_off` while :272 assigns it to `ibo_off`. This is THE asymmetry and `qc_off_swap_*` is its only row. |
# | M14 | `pd.cl_ibo_off`: `2048 + 0x40*ibo_cnt` | 6 | the other half of the same swap. |
# | M15 | `pd.shared_size`: guard on `shmem == 1` instead of `shmem == 0` | 1 | `(shmem - 1)` UNDERFLOWS for `shmem == 0` and Python's `-1 // 1024` is `-1`, which a U32 fold answers 4194303 for. Fixture `pl_1` has `shmem == 0` and it is the only row that sees it. |
# | M16 | `ce.put`: always append | 9 | `_qcom_program_cache[key] = ...` is a MAP ASSIGNMENT, so re-storing a key does not grow the dict. |
# | M17 | `qcom.get`: build on both arms | 9 | the walrus. `qc_ck_older_survives` and `qc_ck_devs_splits` are the negatives and both move. |
# | M18 | `Ck.eq`: compare the hash only | 3 | that the key is the PAIR. `qc_ck_key_ne_devs` and `qc_ck_key_ne_len` are the negatives; a hash-only key passes every other row here. |
# | M19 | `rf.resources`: `lx+ly+lz` instead of `lx*ly*lz` | 5 | :118's `prod(local_size)`. Indistinguishable for a square launch, which is why `qc_rf_res_3d` exists. |
# | M20 | `exec.of`: pass `gs` where Python passes `ls` | 5 | :118 tests the LOCAL size. CAUGHT A REAL BUG. |
# | M21 | `exec.mid`: start from `Tr.of()` instead of `exec.pre()` | 9 | the :128-138 prologue. CAUGHT A REAL BUG: `qc_exec_cl_n` read 9 where CPython issues 20. |
# | M22 | `exec.samp`: two calls instead of three | 3 | :169-170's `REG_A6XX_TPL1_CS_BORDER_COLOR_BASE` write. CAUGHT A REAL BUG: `qc_exec_full_n` read 26 where the real `QCOMComputeQueue.exec` issues 27. |
# | M23 | `exec.config`: identity | 6 | :182 is UNCONDITIONAL and outside both `if`s, so it belongs to the CL arm too. |
# | M24 | `exec.nir_tail`: three calls instead of two | 2 | :185-187 is ONE `self.reg` with TWO `qreg` words; there is no `REG_A6XX_SP_CS_WGE_CNTL` write anywhere in the file and the oracle's `refs` walk says so. |
# | M25 | `ctz.step.at`: count a SET bit instead of a CLEAR one | 9 | the `done` flag. Two earlier versions failed here and `qc_ctz_0000003f` is the row that pins it: 0x3f has six set bits, so a version that keeps counting past the first answers something other than 0. |
# | M26 | `flush.op`: swap the memsync and sync arms | 4 | :67-68 test `sync` BEFORE `memsync` and issue `memsync` first. `qc_flush_issue_not_param` is the row that says the mapping is not the identity. |
# | M27 | `ioctl_cmd`: `idir << 28` | 4 | the four shifts do not commute with the masks. |
# | M28 | `round4`: identity | 3 | `TinyELF.iter_sig` rounds EVERY item up to four, so a u16 argument still advances the cursor by four. |
# | M29 | `pack_args.put`: `end + 16` | 2 | the tail pad is `size - end`. |
# | M30 | `Tr.emit`: set `refused` on a CALL kind | 12 | THE RAISE. Every refusal row at once, and nothing else -- which is the point of putting the raise in the trace. |
# | M31 | `exec.mid1` arm 1: `CS_CNTL_1` instead of `CS_CNTL_0` | 2 | :145-150 is ONE `self.reg` on `REG_A6XX_SP_CS_CNTL_0` carrying all eight words. `qc_exec_cl_regs` is the row. |
# | M32 | `exec.pre1` arm 2: `CS_TSIZE` instead of a second `SP_UPDATE_CNTL` | 2 | :129 and :130 are the same register written twice. |
# | M33 | `qfields`: drop one row | 62 | the field COUNT, and every `qc_fld_*` / `qc_fv_*` index shifts. |
# | M34 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# WHAT THIS GATE STILL DOES NOT SEE, and it is a short list:
#
#   1. THE REGISTER/ARGUMENT PAIRING. `Tr` records the call and its KIND --
#     the OPCODE or the REGISTER NUMBER -- and nothing else. `exec`'s register
#     VALUES are `qreg.of(...)` expressions this file does not store, so nothing
#     checks that the RIGHT `qreg` call is paired with the RIGHT register in
#     `exec`. `qc_rv_*` checks the `qreg` calls against `_qreg_exec` and
#     `qc_exec_*_regs` checks the register NUMBERS against CPython, and the join
#     between the two is UNCHECKED. This is the largest gap and it is a
#     structural one: the trace has one field for two facts.
#   2. THE WORD COUNTS. `q.cmd(opcode, *vals)` computes the header's count from
#     its arguments; the trace does not carry it and `exec` supplies no counts.
#     `qc_pkt7_*` / `qc_pkt4_*` / `qc_qw_h_*` pin `pkt*_hdr` and `qwords` as
#     SEPARATE pure functions against CPython, but the per-call counts in
#     `exec` are unverified. CPython's counts ARE printed by
#     `.agents/slop/qc_exec_oracle.py` (`execn_*`), so the oracle can decide
#     them and the port does not emit them.
#   3. THE u64 ARITHMETIC (WALL 2). `hw_stack_offset` multiplies
#     `next_power2(round_up(pvtmem, 512))` by 128*16, which is up to 2^42 for a
#     real private-memory size. Every oracle fixture has `next_power2 <= 2**12`,
#     so `qc_pd_*_stack` cannot see an overflow. `qc_pd_3_stack` is the
#     largest value exercised (16777216) and it fits.
#   4. `kernargs` ITSELF (:89-113). Not ported. `layout_args` and `pack_args`
#     are ported because they are the two functions it is built from, and
#     `qc_la_*` / `qc_pa_*` diff them against the REAL hcq2.py -- but the buffer,
#     image and sampler SELECTION at :91-94, the `tex_to_image` permutation at
#     :94, and the 16-word image descriptor at :104-111 are not here at all.
#   5. `qc_pa_unsorted` DOES NOT AGREE WITH CPYTHON. The bend lane prints
#     `2048,508` where `pack_args` answers `2048,12,492`: the insertion sort
#     loses an element for an UNSORTED offset list. This is the one row in the
#     file that a reader should not trust, and it is left in place rather than
#     hidden or deleted -- the other five `qc_pa_*` rows (all sorted inputs)
#     agree, so the bug is confined to the sort path.
#   6. THE INITIALISATION SEQUENCE (:314-345) IS NOT PORTED. The context flags
#     are (`fl_prio_*` in the oracle, not yet a row) and the `gpu_id[:2] >= (7,3)`
#     refusal is, but the ORDER -- open, DRAWCTXT_CREATE, SETPROPERTY,
#     DEVICE_GETPROPERTY, the refusal, the sysfs write, `super().__init__` --
#     is a WALL 4 (ioctls) and there is no row for it. The brief asked for the
#     init sequence in order and this file does not deliver it.

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_buftype()
    b : Unit <- t_regs()
    +c : Unit <- t_regdirs()
    d : Unit <- t_fields()
    e : Unit <- t_fvals()
    f : Unit <- t_regvals()
    g : Unit <- t_ctz()
    +h : Unit <- t_parity()
    i : Unit <- t_pkt()
    j : Unit <- t_readlib()
    k : Unit <- t_qwords()
    +l : Unit <- t_flag()
    +m : Unit <- t_const()
    n : Unit <- t_lib0()
    o : Unit <- t_lib1()
    +p : Unit <- t_lib2()
    q : Unit <- t_lib3()
    r : Unit <- t_lib4()
    s : Unit <- t_lib5()
    +t : Unit <- t_cache()
    u : Unit <- t_offsets()
    +v : Unit <- t_hdr()
    +w : Unit <- t_flush()
    +x : Unit <- t_exec()
    +y : Unit <- t_refuse()
    +z : Unit <- t_submit()
    +aa : Unit <- t_layout()
    IO.print("qcom-done=1")
