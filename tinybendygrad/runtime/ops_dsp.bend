# tinybendygrad/runtime/ops_dsp.bend -- port of tinygrad/runtime/ops_dsp.py
#
# THE GENERIC C-BACKEND-FOR-A-DSP WRAPPER. ops_dsp.py is 292 lines and almost none
# of them are DSP-specific arithmetic: it is a ClangRenderer subclass that emits a
# Hexagon `entry` shim, a fastrpc argument packer, an ION/mmap allocator, a clang
# invocation, and a `threading.Thread` that emulates fastrpc's file system on the
# HOST side so the shell image can be paged in. What survives the crossing is the
# SHAPE of every one of those, and the shape is what this file ports.
#
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument of
# ONE device call (pure, and the gate checks it) OR records that call in the trace
# (and the gate checks the ORDER). There is no third kind, which is what puts the
# `raise` in the trace so a refusal appears as a TRUNCATED trace needing no guard
# of its own.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :48  rpc_sc                 PORTED  `rpc_sc` + `sc_method/ins/outs/fds`
#   :49  rpc_prep_args          PORTED  `pra_len`, `pra_of`
#   :53  the fds array          PORTED  `fds_of`
#   :54  the attrs array        PORTED  `attrs_of`
#   :56    the pv/len fill      PORTED  `pra.put` -- the ZERO-LENGTH rule
#   :59  DSPProgram.__init__    PORTED  `prog.call`'s inputs (no state to keep)
#   :62  DSPProgram.__call__    PORTED  `prog.call`
#   :63    the buffer refusal   PORTED  `prog.too_many` + `Tr.refuse_now`
#   :65-66  the three ins/outs  PORTED  `prog.nins`, `prog.nouts`, `prog.pra_lens`
#   :67  the size writes        PORTED  `vt_size_at`, `vt_size_byte`
#   :68  the val writes         PORTED  `vt_val_offset`, `vt_hi_written`
#   :69  the off_mv writes      PORTED  `off_nbytes`
#   :70  the exec_lib call      PORTED  `prog.exec_sc`
#   :71  the timer divide       PORTED  `prog.scale_micros` (the u64 read is WALL)
#   :73  DSPBuffer              PORTED  `DspBuf`, `buf.of`
#   :78  _alloc                 PORTED  `alloc.alloc` (MOCKDSP and real arms)
#   :79    the MOCKDSP arm      PORTED  `alloc.mock_flags`
#   :81    the ION arm          PORTED  `ION_ALIGN`, `ion.aligned`
#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
#   :86-91 _free                PORTED  `alloc.free_calls`
#   :93  _as_buffer             PORTED  `alloc.as_buffer_bytes`
#   :94  _copyin                PORTED  `alloc.copyin_bytes`
#   :95  _copyout               PORTED  `alloc.copyout_bytes`
#   :96  _offset                PORTED  `alloc.offset` -- offsets ACCUMULATE
#   :100 DSPCompiler.args       PORTED  `COMPILER_ARGS`, `compiler_args_first`
#   :104-105 the fifteen sections PORTED `link_section`, `link_sections`
#   :106 the ALIGN(4096) lines  PORTED  `link_line`, `link_line.go`
#   :108 the whole script       PORTED  `link_script`
#   :111 the -T flag            PORTED  `compiler_args_has_T`
#   :113 the cachekey           PORTED  `compiler.cachekey_of`
#   :115 __del__                PORTED  `compiler.del_unlinks`
#   :118 compile                WALL 1  the clang spawn + the .so read-back
#   :125 disassemble            WALL 1  cpu_objdump / llvm-objdump
#   :129 DSPDevice.__init__     PORTED  `dev.is_mock` (the ONE branch, :129-139)
#   :132 the ion_fd open        PORTED  `dev.open_ion`
#   :134-136 the shell buffer   PORTED  `dev.shell_size`, `dev.shell_copy`
#   :135 BufferSpec(nolru=True) PORTED  `dev.shell_spec` -- the eviction NEGATIVE
#   :141 open_lib               PORTED  `dev.open_lib`, `dev.open_lib_sc`
#   :143 the tinylib URL        PORTED  `OPEN_LIB_FP`, `open_lib_len`
#   :145 the two outs           PORTED  `open_lib_out0`, `open_lib_out1`
#   :147 the raise              PORTED  `open_lib_bad`, `open_lib_err`
#   :148 the handle answer      PORTED  `dev.open_lib_handle`
#   :150 close_lib              PORTED  `dev.close_lib`, `dev.close_lib_sc`
#   :154-164 exec_lib           PORTED  `dev.exec_lib` -- open/invoke/close, retry
#   :166-176 init_dsp           PORTED  `dev.init_dsp` -- seven ordered calls
#   :167-170 the stale-fd close PORTED  the `have_fd` arm
#   :178 RPCListener.__init__   PORTED  the three initial values
#   :186-188 the request block  PORTED  `rpc.lens`, `RPC_MSG_BYTES`
#   :192 msg_send               PORTED  `rpc.msg_*_index`
#   :194 the greeting literal   PORTED  `RPC_GREET`
#   :197 the sc field split     PORTED  `sc_ins`, `sc_outs`
#   :199-210 the object walk    PARTIAL `rpc.obj_pad`, `rpc.obj_count` (WALL 3)
#   :213-238 the seven arms     PORTIAL `rpc.arm` + each arm's in/out counts
#   :221 the SEEK_SET assert    PORTED  `rpc.seek_ok`, `rpc.seek_err`
#   :239 the unknown-op raise   PORTED  `rpc.unknown_err`, `ARM_NONE`
#   :243 mockdsp_boilerplate    PORTED  `mockdsp_boilerplate`
#   :253 MockDSPRenderer        PORTED  `mrender.*`
#   :255 its defines            PORTED  by the omission (clang only)
#   :262 max_numel*itemsize     PORTED  `mrender.nbytes`
#   :264 the mmap2/read loop    PORTED  `mrender.mmap`
#   :266 the val read           PORTED  `mrender.val`
#   :268 the (void*) cast       PORTED  `mrender.arg_name`
#   :270 the inscount write     PORTED  `mrender.finish`
#   :272 the output write       PORTED  `mrender.emit`
#   :276-292 MockDSPProgram     PORTED  `mprog.stdin_bytes`, `mprog.stdout_len`,
#                                             `mprog.scale_ins`
#
# ===========================================================================
# THE WALLS.
#
# 1. THE COMPILER INVOCATION (:118-123). `system(f"{getenv('CC','clang')}
#    {self.args} -O2 -Wall -Werror -fno-stack-protector -x c -fPIC
#    -ffreestanding -nostdlib - -o {f.name}", input=src.encode())` and the
#    `pathlib.Path(f.name).read_bytes()` after it. `args` IS ported -- it is a
#    string function of `mock` -- and so is the whole command line, as
#    `compile_cmd`. The spawn and the byte buffer are not.
#    TODO(p3) runtime/ops_dsp.py:118 -- the clang spawn and the .so read-back.
#    TODO(p3) runtime/ops_dsp.py:125 -- cpu_objdump / llvm-objdump.
#
# 2. THE ION AND MMAP SYSCALLS (:81-83, :88, :132, :172). `os.open('/dev/ion')`,
#    `qcom_dsp.ION_IOC_ALLOC`, `libc.mmap`, `os.close('/dev/adsprpc-smd')`. Every
#    one is an ioctl on a Qualcomm node that does not exist off-device, and
#    `autogen/qcom_dsp.py` is generated ctypes bindings, so even on device these
#    are struct layouts. What is ported is the ORDER and the ONE integer each call
#    carries -- the size, the handle, the selector -- which is what the trace holds.
#    TODO(p3) runtime/ops_dsp.py:81  -- ION_IOC_ALLOC / ION_IOC_SHARE.
#    TODO(p3) runtime/ops_dsp.py:83  -- libc.mmap.
#    TODO(p3) runtime/ops_dsp.py:132 -- os.open('/dev/ion').
#    TODO(p3) runtime/ops_dsp.py:172 -- os.open('/dev/adsprpc-smd').
#
# 3. THE RPCListener's HOST FILE SYSTEM AND ITS OBJECT WALK (:199-238). The DSP
#    asks the HOST for these over the listener socket; this file implements
#    fastrpc's file system in python so the shell image can be paged in. The sc
#    DISPATCH TABLE, the seven arms' argument counts, the 8-byte object alignment
#    and the reply field indices are pure and ARE ported. The syscalls and the
#    pointer walk are not.
#    TODO(p3) runtime/ops_dsp.py:199 -- the in_ptr/out_ptr walk over in_buf.
#    TODO(p3) runtime/ops_dsp.py:215 -- os.open(name) for name != "tinylib".
#    TODO(p3) runtime/ops_dsp.py:218 -- os.close(fd) for fd != TINYFD.
#    TODO(p3) runtime/ops_dsp.py:223 -- os.lseek.
#    TODO(p3) runtime/ops_dsp.py:227 -- the TINYFD read out of `binded_lib`.
#    TODO(p3) runtime/ops_dsp.py:229 -- os.read.
#    TODO(p3) runtime/ops_dsp.py:233 -- os.stat and the apps_std_STAT fill.
#    TODO(p3) runtime/ops_dsp.py:237 -- FASTRPC_IOCTL_MMAP.
#
# 4. THE u64 TIMER (:71 `timer[0] / 1e6`, :292 `struct.unpack("I", ...)/1e9`).
#    Bend has no 64-bit integer and no F64, so the DIVISOR is ported as the one
#    number the seam must agree on -- and the two programs have DIFFERENT ones,
#    1e6 against 1e9, which `dsp_scale_*` pins because a port that shared one
#    scale would move exactly one of the three rows.
#    TODO(p3) runtime/ops_dsp.py:71  -- the u64 read and the /1e6.
#    TODO(p3) runtime/ops_dsp.py:292 -- the u32 inscount read and the /1e9.
#
# THERE IS NO FOREIGN EFFECT IN THIS FILE. No `import "./x.c"`, no `-> IO(R)`. A
# template-following device records its calls in a `Tr` and declares nothing, which
# is the `ops_metal.bend` precedent and the reason that file prints no SOME PROOFS
# FAIL. `dtype.bend` is NOT imported: it is a conversion seam (`Dt.bf16`,
# `Dt.fp16`, ...) and importing it would drag that seam into this file for no gain
# -- ops_dsp.py needs no dtype conversion, only dtype NAMES.
#
# ===========================================================================
# THE HEART OF IT: FOUR PURE FUNCTIONS OF A DTYPE.
#
# The brief named `to_scalar`/`from_scalar` as this file's centre. MEASURED:
# NEITHER EXISTS anywhere in tinygrad -- `rg -n "to_scalar|from_scalar" tinygrad/`
# finds only `lower_to_scalar`, a Mesa NIR boolean in autogen/mesa.py, and one
# unrelated `lower_nir_alu_to_scalar`. There is nothing to port under those names.
#
# What ops_dsp.py actually does with a dtype is FOUR tables, and they are what this
# file gates hardest, because a wrong entry in any of them is a SILENTLY WRONG
# KERNEL rather than a crash:
#
#   `dt_fmt`      (:68)  `struct.pack(unwrap(dt.fmt), ...)`. SIX of the twenty
#                      dtypes have `fmt is None` -- void, weakint, weakfloat, all
#                      four fp8s and bfloat16 -- and `unwrap` on that is a hard
#                      failure. bfloat16 is the interesting one: `fmt is None` with
#                      itemsize 2, and `supported_dtypes` (:46) exists to keep it
#                      out of the signature. That is the whole reason :46 is there.
#   `dt_itemsize` (:68)  the WIDTH `struct.pack` writes, hence how many of an
#                      8-byte slot's eight bytes it touches. weakint/weakfloat are
#                      100, dtype.py's placeholders.
#   `dt_cname`    (:32)  `self._render_dtype(...)` for an ALU param -- the C
#                      SPELLING, which is not the C name and not the fmt. uint64 ->
#                      "unsigned long long" and int64 -> "long long" are the two
#                      entries ops_dsp.py:15 ADDS to ClangRenderer's map, and
#                      MEASURED that map has TWO keys (`bool`, `half`) and neither
#                      of the two.
#   `dt_cname_global`     (:32) the GLOBAL arm of the same line, and it is the
#                      load-bearing asymmetry: a GLOBAL's `sz_or_val` is always
#                      spelled `int` whatever the buffer's dtype, because it holds
#                      the byte SIZE and not the value.
#
# ===========================================================================
# THE ARGUMENT TRACE, :62-70. THE DEVICE CONTRACT SIX OTHER UNITS ARE PORTING.
#
# `DSPProgram.__call__` packs ONE 8-byte-aligned block for the whole call:
#
#   ins   = [var_vals_mv of (len(bufs)+len(vals))*8 bytes,
#            off_mv   of len(bufs)*4 bytes]
#   outs  = [timer of 8 bytes]
#   in_fds = [b.share_info.fd for b in bufs]
#
# so `pra` has `3 + len(bufs)` entries: two ins, one out, then one dma per buffer.
# `fds` is `[-1]*(ins+outs) ++ in_fds` (:53) and `attrs` is
# `[0]*(ins+outs) ++ [1]*len(in_fds)` (:54) -- SAME length as `pra`, and the `1`
# is the only thing besides the length that tells a dma slot from a buffer slot.
# `rpc_sc(method=2, ins=2, outs=1, fds=len(bufs))` (:70), so the selector is a
# function of ONE number. `pra_of` is gated at nine (ins,outs,fds) fixtures
# INCLUDING (2,1,16) -- one past the :63 refusal -- so a `pra` that grows where
# Python's does not is visible.
#
# var_vals_mv (:67,:68) is eight bytes per ARGUMENT: words 0..len(bufs)-1 are
# `b.size` written with fmt `'i'` at `i*8`, and the rest are the vals written with
# `dt.fmt` at `(len(bufs)+j)*8`. Every slot is 8 bytes ALWAYS, so a 4-byte fmt
# leaves the high word at ZERO and only an 8-byte fmt writes it. `vt_hi_written_*`
# is that row family.
#
# ===========================================================================
# THE BUFFER-OWNERSHIP RULES, consumed from device.bend rather than re-derived.
#
#   * a Buffer is a SLOT in an arena (`Bn` in device.bend) and `nbytes` is
#     deliberately NOT a field -- it is `size * itemsize` and storing it lets the
#     two disagree. So `DspBuf` carries `size`, and word `i` of var_vals is
#     `b.size` (:67), the ONE place ops_dsp.py reads a size.
#   * offsets ACCUMULATE across views: `_offset` (:96) is
#     `DSPBuffer(buf.va_addr+offset, size, buf.share_info, buf.offset+offset)`.
#     The SECOND `+offset` is the load-bearing half -- `off` is a view's offset
#     WITHIN the root, so a second view must add to the first view's offset. A port
#     that dropped `buf.offset+` reports the BASE offset and every `off_i` the
#     entry shim reads (:35) is then wrong by the whole view, SILENTLY, because the
#     HAP_mmap still succeeds. `dsp_accum_*` is the row family, and the `dsp_accum_2_*`
#     rows (a view OF a view) are the only ones that can see it.
#   * a view's base is the ROOT: `_offset` copies `share_info` from the parent, so
#     `has_share` and `share_handle` propagate and a MOCKDSP view stays share-less.
#   * `recycled` (device.bend, from device.py:280) is the eviction policy, and
#     ops_dsp.py:135 allocates the fastrpc shell with `BufferSpec(nolru=True)`, so
#     the NEGATIVE CASE IS IN THIS FILE'S OWN CODE and not a fixture invented for
#     it. `dsp_norecycle_nolru` and `dsp_recycle_plain` are the same row family with
#     opposite answers at the SAME size, which is the only way a wrong eviction
#     cannot pass by accident.
#
# ===========================================================================
# THE KERNEL NAME, :143. A STRING ROW, NEVER A BOOLEAN ABOUT A STRING.
#
#   fp = "file:///tinylib?entry&_modver=1.0&_dom=cdsp\0"
#
# MEASURED: 44 characters INCLUDING the NUL, and `open_lib` packs `[len(fp),
# 0xff]` as ins[0] -- so Python's length counts the NUL, and the trailing `0xff` in
# ins[0] is fastrpc's length sentinel, NOT part of the name. Bend's `String` cannot
# hold a NUL, so `OPEN_LIB_FP` is the name and `OPEN_LIB_NUL_LEN` the one byte it
# drops; `dsp_openlib_len` pins the SUM at 44. `String.concat` drops a literal
# silently, so `dsp_fp_*` and `dsp_link_script` diff the STRING itself.
#
# ===========================================================================
# NO DSP AND NO ION IN THIS ENV. `Device['DSP']` needs /dev/ion and
# `/dsp/cdsp/fastrpc_shell_3` does not exist, so NOTHING here was measured against
# a live DSP. Every constant and every `py=` expectation was produced by CALLING
# CPython -- see `.agents/slop/dsp_oracle.py`, which GENERATES the expectations. No
# expectation in this file was typed by hand.
#
# TWO MEASURED FACTS WORTH THEIR OWN ROWS:
#
#   * `ClangRenderer(Target("DSP","CLANG","hexagonv65,hexagonv65"))` RAISES
#     `RuntimeError: unsupported arch: 'hexagonv65'` from ClangCompiler
#     (compiler_cpu.py:15). That is WHY `DSPRenderer.__init__` (:18) does not call
#     `super().__init__`: a DSP target must never build the host CPU clang
#     compiler. `dsp_no_super_init` pins that the compiler is the DSP one.
#   * `rpc_sc(2,2,1,0)` is 33685760 and the listener's `sc=0x04020200` is 67240448.
#     They differ by exactly the method byte. The greeting literal is SPELLED AS A
#     LITERAL in Python (:194) and a port that "helpfully" rewrote it as an
#     `rpc_sc` call would send method 2 and the DSP would never see a greeting.
#     `dsp_rpc_greet_*` is that row family and it is the single most load-bearing
#     constant in the file.
#
# ===========================================================================
# WHAT device.bend AND ops_qcom.bend OWE THIS FILE.
#
# device.bend, CONSUMED and not re-derived: `recycled`, `alloc_take`, `freed`,
# `needs_compile`, `Bspec`, `round_up_u32` (via helpers), `u32_list_eq`.
#
# ops_qcom.bend, READ AT 2026-10-02: a 15-line STUB whose header claims the same
# qnn/htq op tables. ops_dsp.py has NO op table to contradict one with --
# `DSPRenderer` inherits `ClangRenderer.code_for_op` and only REMOVES one entry
# (:16), which is a renderer-internal dict, not a qnn/htq table. MEASURED: `len(
# DSPRenderer.code_for_op)` is 17 against ClangRenderer's 18, the difference being
# exactly `Ops.SQRT`. So `dsp_cfop_*` pins the COUNT and the REMOVAL rather than
# the contents, and nothing in this file can drift from that unit's tables.
import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S


# ===========================================================================
# THE CONSTANTS. Every one read out of ops_dsp.py, its autogen bindings, or
# helpers.py -- the three places a number in this file can come from.
# ===========================================================================

# the fastrpc selector's four one-byte fields (:48). MEASURED: `U32.shl` is a
# ONE-bit shift and `U32.shln(a, n)` is the n-bit one, so the field POSITIONS are
# `Nat` -- which is also why they are constants here rather than parameters.
def SC_METHOD() -> Nat: 24n
def SC_INS() -> Nat: 16n
def SC_OUTS() -> Nat: 8n
def SC_BYTE_MASK() -> U32: 255

# the CALL kinds the trace records. `arg` is the ONE integer each call carries that
# a decision reads: the size for an allocation, the handle for an ION free, the
# selector for an invoke, the flags for RPC_INIT.
def CALL_ION_ALLOC() -> U32: 0
def CALL_ION_SHARE() -> U32: 1
def CALL_MMAP() -> U32: 2
def CALL_MEMMOVE() -> U32: 3
def CALL_OS_CLOSE() -> U32: 4
def CALL_ION_FREE() -> U32: 5
def CALL_ADSP_OPEN() -> U32: 6
def CALL_RPC_GETINFO() -> U32: 7
def CALL_RPC_CONTROL() -> U32: 8
def CALL_RPC_INIT() -> U32: 9
def CALL_RPC_INVOKE() -> U32: 10
def CALL_RPC_INVOKE_ATTRS() -> U32: 11
def CALL_OPEN_LIB() -> U32: 12
def CALL_EXEC_LIB() -> U32: 13
def CALL_CLOSE_LIB() -> U32: 14
def CALL_OPEN_ION() -> U32: 15

# the method numbers of rpc_sc, as they are PASSED (:70,:146,:152,:169,:176)
def M_OPEN() -> U32: 0
def M_CLOSE() -> U32: 1
def M_INVOKE() -> U32: 2
def M_INIT() -> U32: 3

# the handle numbers (:157 handle=0, :194 handle=0x3, :176 handle=3,
# :169 handle=4) and the listener's TINYFD (:185).
def H_INIT() -> U32: 3
def H_DSP_STOP() -> U32: 4
def H_TINYFD() -> U32: 65535

# ioctl arguments (:173 arg=3, :174 req=0x3, :175 flags=0x1)
def ARGPTR_SIZE() -> U32: 3
def CONTROL_REQ() -> U32: 3
def INIT_FLAGS() -> U32: 1

# ION (:81) -- align 0x200, heap_id_mask 1<<ION_SYSTEM_HEAP_ID, ION_FLAG_CACHED
def ION_ALIGN() -> U32: 512
def ION_SYSTEM_HEAP_ID() -> Nat: 0n
def ION_FLAG_CACHED() -> U32: 1

# the device nodes (:132, :172), the shell image (:134), its alignment (:135)
def DEV_ION() -> String: "/dev/ion"
def DEV_ADSP() -> String: "/dev/adsprpc-smd"
def SHELL_PATH() -> String: "/dsp/cdsp/fastrpc_shell_3"
def SHELL_ALIGN() -> U32: 4096

# :63 `if len(bufs) >= 16: raise`. The MAX is 15 buffers, and :70 puts
# `fds=len(bufs)` in the selector's LOW byte, so 15 is also the largest fds a
# selector carries without spilling into the outs field.
def MAX_BUFS() -> U32: 16

# :100 the compiler flags, one string; :100/:111 what wraps it
def COMPILER_ARGS() -> String:
  "--target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b"
def ARG_SHARED() -> String: "-shared"
def ARG_STATIC() -> String: "-static"
def CACHEKEY() -> String: "compile_dsp"

# :121 the command tail, identical in the mock and the real compile
def COMPILE_TAIL() -> String:
  "-O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o "

# :13,:14 the two class attributes the generated C depends on
def BUFFER_SUFFIX() -> String: " restrict __attribute__((align_value(128)))"
def KERNEL_TYPEDEF() -> String: "__attribute__((noinline)) void"

# :143 the library URL. See THE KERNEL NAME: 44 is the length Python counts and it
# INCLUDES the NUL, which Bend's String cannot hold.
def OPEN_LIB_FP() -> String: "file:///tinylib?entry&_modver=1.0&_dom=cdsp"
def OPEN_LIB_NUL_LEN() -> U32: 1
def OPEN_LIB_SENTINEL() -> U32: 255

# :257's comment points at the gpages.com syscall table, which is where every
# number in the mock's boilerplate comes from.
def SYSCALL_READ() -> U32: 63
def SYSCALL_WRITE() -> U32: 64
def SYSCALL_EXIT() -> U32: 93
def SYSCALL_MMAP2() -> U32: 222
def HEX_REG_QEMU_INSN_CNT() -> U32: 21
def INSN_CNT_WORD() -> U32: 1784217600


# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE device call and the ONE integer it carries that a decision reads.
type Call is Data:
  Call{k: U32, arg: U32}

# :74 `DSPBuffer(va_addr, size, share_info, offset)`. `id` is the seam's handle for
# the address; `has_share` is Python's `share_info is None` test (:89), so it is
# false for MOCKDSP and true for the real allocator.
type DspBuf is Data:
  DspBuf{id: U32, va: U32, size: U32, offset: U32, share_fd: U32,
         share_handle: U32, has_share: Bool}

# one created buffer and the trace that created it. Bend refuses to destructure a
# computed product, so the two travel together -- the port's idiom throughout.
type Made is Data:
  Made{buf: DspBuf, t: Tr}

# the machine state of the seam: the ordered call list, the id counter, and the
# refusal flag. See THE RAISE.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool}

# ONE remote_arg (:52) as the two arms of the union declared at :23. A `buf` arm
# carries (pv, len) and a `dma` arm carries (fd, offset). `len` is 0 on a dma arm
# MEASURED -- the fill loop at :56 stops at `len(ins)+len(outs)`, so a dma slot's
# `buf.size` still reads 0 from untouched union storage. `pv` is reported as 0 or
# nonzero, never as a value: it is an address and addresses are not reproducible.
type Pra is Data:
  Pra{is_dma: Bool, pv: U32, len: U32, fd: U32}

# ONE 8-byte slot of var_vals_mv (:67,:68), little-endian, so `lo` is the low word.
# How many bytes a `struct.pack` writes into it is `nbytes`, a separate row family.
type Slot is Data:
  Slot{lo: U32, hi: U32, nbytes: U32}

# ONE PARAM of the generated kernel: a GLOBAL buffer (with its element count, so
# the mock can compute the byte width) or an ALU value (with the C spelling of its
# dtype). `is_alu` is the `addrspace == AddrSpace.ALU` test that :32,:35,:37,:39,
# :261,:265 and :271 all make, and it decides whether the entry shim reads a SIZE
# or a VALUE out of the same 8-byte slot.
type Param is Data:
  Param{is_alu: Bool, cn: String, numel: U32}


def Param.is_alu(p: Param) -> Bool:
  match p:
    case Param{is_alu, cn, numel}: is_alu

def Param.cn(p: Param) -> String:
  match p:
    case Param{is_alu, cn, numel}: cn

def Param.numel(p: Param) -> U32:
  match p:
    case Param{is_alu, cn, numel}: numel

# ===========================================================================
# THE FIXTURES.
def fx.g(cn: String, numel: U32) -> Param: Param{False{}, cn, numel}
def fx.a(cn: String, numel: U32) -> Param: Param{True{}, cn, numel}

def fx.bufs3() -> List<&2, U32>: [1, 2, 3]
def fx.offs3() -> List<&2, U32>: [0, 64, 128]
def fx.ffs3() -> List<&2, U32>: [10, 11, 12]
def fx.ffs16() -> List<&2, U32>:
  [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]

def fx.spec(nolru: Bool, ext: Bool) -> D.Bspec:
  D.Bspec{False{}, False{}, False{}, nolru, ext}

# ALU, GLOBAL, GLOBAL, ALU -- the fixture that separates the param index from a
# compacted counter.
def fx.g2() -> List<&2, Param>: [fx.g("float", 4), fx.g("float", 4)]

def fx.ga1() -> List<&2, Param>: [fx.g("float", 4), fx.a("unsigned int", 1), fx.g("float", 4)]

def fx.a2() -> List<&2, Param>: [fx.a("unsigned int", 1), fx.a("float", 1)]

def fx.g1() -> List<&2, Param>: [fx.g("unsigned int", 1)]

def fx.a1() -> List<&2, Param>: [fx.a("unsigned int", 1)]

def fx.agga() -> List<&2, Param>:
  [fx.a("unsigned int", 1), fx.g("float", 4), fx.g("float", 4), fx.a("int", 1)]

# The index LIST is the fuel rather than a `Nat` countdown, and that is not a
# style choice: a `case 1n+m:` arm binds `m`, so a body that also reads the
# scrutinee `n` cannot use either of them twice -- MEASURED, twice. Destructuring a
# list gives each element its own name and the problem does not arise.
# ===========================================================================
# THE TRACE.
#
# THE RAISE. `Tr.emit` records NOTHING once refused. That is the port of :63's
# `if len(bufs) >= 16: raise RuntimeError(...)` and of :147's
# `if o1.cast('i')[1] < 0: raise RuntimeError(f"Cannot open lib: ...")`: the code
# after a raise does not happen. It is why no step below needs a guard of its own,
# and why a refusal shows up as a TRUNCATION rather than as a flag alone.
#
# THE FAILING CALL IS NOT RECORDED, and that is not a special case. In both sites
# the refusal is a DEVICE ERROR -- the ioctl raised -- which is exactly "the call
# did not complete", and `Tr.emit`'s guard is the whole of it. `Tr.refuse_now` is
# the OTHER kind (:63, :221's assert, :239's unknown op): the refusal is decided
# BEFORE the call, so nothing at all is recorded and the trace keeps its earlier
# calls.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}}

def Tr.calls(+t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused}: calls

def Tr.next(+t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

def Tr.refused(+t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused}: refused

# an empty trace that keeps the id counter, so a fixture that reads one program call
# without the device init in front of it still mints ids from one.
def Tr.reset(+t: Tr) -> Tr: Tr{Nil{}, Tr.next(t), False{}}

# :63 / :221 / :239 -- the refusal is decided before the call, so NOTHING is added.
def Tr.refuse_now(+t: Tr) -> Tr:
  match t:
    case Tr{+calls, next, +refused}: Tr{calls, next, True{}}

# the id the NEXT emit mints, i.e. what the seam's call answers (:148's
# `o1.cast('I')[0]`). Read BEFORE the emit, so ids are monotone in issue order.
def Tr.here(+t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates BOTH arms, so the emitted call is a value built here and the
# guard is a parameter. This is the port's `raise`.
def Tr.emit.go(+refused: Bool, +calls: List<&2, Call>, +next: U32, k: U32,
               arg: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, next, +refused}: Tr.emit.go(refused, calls, next, k, arg)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg


# ===========================================================================
# READING THE TRACE. Four readers and nothing else: the length, how many calls of a
# kind, their args in order, and "contains this (kind, arg) sequence, in order".
# ===========================================================================

def seen(+t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

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

def ncalls(k: U32, t: Tr) -> U32: Tr.count(k, Tr.calls(t))

# the FIRST arg of a kind, and 0 when there is none. `first` is what the selector
# rows read, because every selector is a function of ONE number.
def first(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case x <> _: x

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one of
# them would branch the walk twice over.
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

def cargs(k: U32, t: Tr) -> List<&2, U32>: Tr.args(k, Tr.calls(t))

# THE FUEL IS THE TRACE LENGTH AND THE ANSWER IS `at == patlen`. With the fuel set
# to the PATTERN length instead, `case 0n:` fires after patlen trace entries and
# returns True without ever looking at `at`, so a reversed pattern matches and a
# pattern longer than the trace matches too. That bug was MEASURED in
# ops_webgpu.bend (its mutation M23); `dsp_has_reverse` and `dsp_has_toolong` are
# the two rows here that exist to catch it.
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

def seq(+t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))


# ===========================================================================
# THE FOUR DTYPE TABLES. Plain functions of dtype.py's `name` field, so each is
# gated over its whole domain rather than at a fixture.
# ===========================================================================

# `spec.bend` holds `Dt` and has no `nm` reader; dtype.bend has `dt_name` but is a
# conversion seam and importing it would drag that seam in for nothing.
# TODO(p3) LAWS/spec.bend:76  Dt.nm -- the name reader this file matches on.
def dt_nm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# `rpc_sc(method=0, ins=0, outs=0, fds=0)` (:48),
# `(method << 24) | (ins << 16) | (outs << 8) | fds`. FOUR one-byte fields that do
# not overlap, which is the fact that lets `fds = len(bufs)` (up to 15) and
# `outs = 1` be independent.
def rpc_sc(method: U32, ins: U32, outs: U32, fds: U32) -> U32:
  U32.or(U32.or(U32.or(U32.shln(method, SC_METHOD()), U32.shln(ins, SC_INS())),
                U32.shln(outs, SC_OUTS())), fds)

# THE SELECTOR'S FIELD SPLIT, and it has TWO readers in Python:
# `_render_entry`'s `sc>>24` test (:33) and `RPCListener`'s
# `(sc:=msg_recv[2]) >> 16 & 0xff` (:197). `sc_ins` and `sc_outs` mask with 0xff for
# exactly the reason the listener's expression does.
def sc_method(sc: U32) -> U32: U32.shrn(sc, SC_METHOD())
def sc_ins(sc: U32) -> U32: U32.and(U32.shrn(sc, SC_INS()), SC_BYTE_MASK())
def sc_outs(sc: U32) -> U32: U32.and(U32.shrn(sc, SC_OUTS()), SC_BYTE_MASK())
def sc_fds(sc: U32) -> U32: U32.and(sc, SC_BYTE_MASK())

# :33 `if ((sc>>24) != 2) return 0;` -- the entry shim runs ONE method and refuses
# every other. Method 2 is M_INVOKE, which is what :70 sends.
def entry.method_ok(sc: U32) -> Bool: U32.is_eq(sc_method(sc), M_INVOKE())

# `dt.fmt` (:68, `struct.pack(unwrap(dt.fmt), ...)`). `None` is not a missing table
# entry: it is dtype.py's own value, and `unwrap` on it is a hard failure. So
# `dt_fmt_none` is the EMPTY string and "has no fmt" is a Bool, not a string --
# because there is no string to print. `dsp_fmt_nones` pins how many there are.
def dt_fmt_none() -> String: ""
def dt_fmt(nm: String) -> String:
  match nm:
    case "bool": "?"
    case "signed char": "b"
    case "unsigned char": "B"
    case "short": "h"
    case "unsigned short": "H"
    case "int": "i"
    case "unsigned int": "I"
    case "long": "q"
    case "unsigned long": "Q"
    case "half": "e"
    case "float": "f"
    case "double": "d"
    case _: dt_fmt_none()

def dt_fmt_dt(d: S.Dt) -> String: dt_fmt(dt_nm(d))

def dt_has_fmt(nm: String) -> Bool: Bool.not(String.eq(dt_fmt(nm), dt_fmt_none()))

# `dt.itemsize`: how many bytes `struct.pack(fmt, ...)` writes into an 8-byte slot.
# void is 0 and weakint/weakfloat are 100 -- dtype.py's placeholders, and 100 is
# wider than a slot, which is exactly why the "high bytes untouched" claim below
# needs a dtype it cannot reach.
def dt_itemsize(nm: String) -> U32:
  match nm:
    case "void": 0
    case "bool": 1
    case "signed char": 1
    case "unsigned char": 1
    case "short": 2
    case "unsigned short": 2
    case "half": 2
    case "__bf16": 2
    case "int": 4
    case "unsigned int": 4
    case "float": 4
    case "float8_e4m3": 1
    case "float8_e4m3fnuz": 1
    case "float8_e5m2": 1
    case "float8_e5m2fnuz": 1
    case "long": 8
    case "unsigned long": 8
    case "double": 8
    case _: 100

def dt_itemsize_dt(d: S.Dt) -> U32: dt_itemsize(dt_nm(d))

# `self._render_dtype(dt.dtype)` (:32), i.e. `self.type_map.get(dt, dt.name)` with
# the TWO extra keys ops_dsp.py:15 adds. MEASURED: `ClangRenderer.type_map` has
# exactly two keys, `bool` and `half`, so both additions are new entries and neither
# is a correction.
def dt_cname(nm: String) -> String:
  match nm:
    case "bool": "_Bool"
    case "half": "__fp16"
    case "long": "long long"
    case "unsigned long": "unsigned long long"
    case _: nm

def dt_cname_dt(d: S.Dt) -> String: dt_cname(dt_nm(d))

# THE GLOBAL ARM of :32, and the load-bearing asymmetry of the whole file: a
# GLOBAL's `sz_or_val` is spelled `int` whatever the buffer's dtype, because it
# holds the byte SIZE (:67 packs `b.size`) and not the value. A port that keyed the
# GLOBAL arm off the dtype would type a float buffer's size as `float` and every
# read at `pra[0].buf.pv+i*8` would be a float load.
def dt_cname_global(+is_alu: Bool, +nm: String) -> String:
  match is_alu:
    case True{}: dt_cname(nm)
    case False{}: "int"

# `supported_dtypes` (:46) = ClangRenderer's, minus the fp8s, minus bfloat16.
# ClangRenderer's own filter (cstyle.py:315) drops the fp8s ALWAYS and drops
# bfloat16 unless the arch starts with x86/arm. MEASURED: an x86 arch gives 13
# dtypes, a hexagon arch gives 12, and DSP gives 12 on BOTH -- so the arch test is
# irrelevant here, and the `dtypes.bfloat16` in :46 is the WHOLE difference on x86
# and a NO-OP on hexagon. `dsp_sdtype_n` plus `dsp_sdtype_x86_drop` pins that.
def dt_is_fp8.i(nm: String) -> Bool:
  match nm:
    case "float8_e4m3": True{}
    case "float8_e4m3fnuz": True{}
    case "float8_e5m2": True{}
    case "float8_e5m2fnuz": True{}
    case _: False{}

def dt_is_fp8(nm: String) -> Bool: dt_is_fp8.i(nm)

def dt_supported(base: Bool, +nm: String) -> Bool:
  Bool.and(base, Bool.and(Bool.not(dt_is_fp8(nm)), Bool.not(String.eq(nm, "__bf16"))))

# the twelve supported names in dtype.py's `__lt__` order (dtype.bend's rank order,
# which sorts on (priority, bitsize, name, fmt) -- so the order is forced).
def supported_12.at(n: Nat) -> String:
  match n:
    case 0n: "bool"
    case 1n: "signed char"
    case 2n: "unsigned char"
    case 3n: "short"
    case 4n: "unsigned short"
    case 5n: "int"
    case 6n: "unsigned int"
    case 7n: "long"
    case 8n: "unsigned long"
    case 9n: "half"
    case 10n: "float"
    case _: "double"

def supported_12.of(+ix: List<&2, Nat>, acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}: acc
    case i <> t: supported_12.of(t, List.append(&2, String, acc, [supported_12.at(i)]))

def supported_names() -> List<&2, String>:
  supported_12.of(List.range(12n), Nil{})

# `code_for_op` (:16) = ClangRenderer's minus `Ops.SQRT`. MEASURED 18 against 17,
# the difference being exactly that one op. The CONTENTS are cstyle.py's and are
# not this file's, so only the COUNT and the REMOVAL are ported -- see WHAT
# ops_qcom.bend OWES for why restating the table would be a liability here.
def CFOP_CLANG() -> U32: 18
def CFOP_DSP() -> U32: 17
def cfop_removed() -> U32: U32.sub(CFOP_CLANG(), CFOP_DSP())


# ===========================================================================
# rpc_prep_args, :49-57. THREE pure functions of three counts, and they are the
# device contract six other units are porting.
# ===========================================================================

# :52-54. One `pra` and THREE arrays, all of length `len(ins)+len(outs)+
# len(in_fds)`, so `pra_len` is what every row below is sized by.
def pra_len(nins: U32, nouts: U32, nfds: U32) -> U32:
  U32.add(U32.add(nins, nouts), nfds)

# :53 `([-1] * (len(ins) + len(outs)), *in_fds)`. The `-1` is the "no dma on this
# slot" marker and it is what the kernel's `remote_arg` arm selection reads.
def FD_NONE() -> U32: 4294967295

def fill(n: Nat, +v: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: fill(m, v, List.append(&2, U32, acc, [v]))

def fds_head(n: Nat) -> List<&2, U32>: fill(n, FD_NONE(), Nil{})

def fds_of(nins: U32, nouts: U32, +fds: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, fds_head(U32.to_nat(U32.add(nins, nouts))), fds)

# :54 `([0] * (len(ins) + len(outs)), [1] * len(in_fds))`. The `1` marks a slot as
# a DMA descriptor rather than a buffer, and it is the ONLY difference between a dma
# slot and a buffer slot besides the length.
def ATTR_BUF() -> U32: 0
def ATTR_DMA() -> U32: 1

# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the BUF head goes FIRST and the
# DMA tail second. Writing it the other way round is a bug this gate's first run
# found: `dsp_attr_2213` answered `1,1,1,0,0,0`.
def attrs_of(nins: U32, nouts: U32, nfds: U32) -> List<&2, U32>:
  List.append(&2, U32, fill(U32.to_nat(U32.add(nins, nouts)), ATTR_BUF(), Nil{}),
    fill(U32.to_nat(nfds), ATTR_DMA(), Nil{}))

# :56 `for i, mv in enumerate(ins + outs): pra[i].buf.pv, pra[i].buf.len =
# ctypes.c_void_p(mv_address(mv) if mv.nbytes > 0 else 0), mv.nbytes`.
#
# THE ZERO-LENGTH RULE. `mv_address` is `ctypes.c_char.from_buffer(mv)` and a
# zero-length buffer has no address to ask for, so the `else 0` is REQUIRED rather
# than defensive -- Python short-circuits and never calls `mv_address` for n == 0.
# MEASURED: the assign then leaves `pra[0].buf.pv` as None, and `len` 0. So the port
# records `pv` as 0 for a zero-length slot and 1 for every other, which is the only
# reproducible form of an address.
def pra.pv_set(nbytes: U32) -> Bool: Bool.not(U32.is_zero(nbytes))

def pra.put(n: Nat, +mvs: List<&2, U32>, acc: List<&2, Pra>) -> List<&2, Pra>:
  match n:
    case 0n: acc
    case 1n+m:
      match mvs:
        case Nil{}: acc
        case nb <> t:
          pra.put(m, t, List.append(&2, Pra, acc,
            [Pra{False{}, Bool.to_u32(pra.pv_set(nb)), nb, 0}]))

# the dma arms: one per in_fd, `is_dma` true, `len` 0, `fd` the buffer's share fd.
def pra_dma(n: Nat, +fds: List<&2, U32>, acc: List<&2, Pra>) -> List<&2, Pra>:
  match n:
    case 0n: acc
    case 1n+m:
      match fds:
        case Nil{}: acc
        case fd <> t: pra_dma(m, t, List.append(&2, Pra, acc, [Pra{True{}, 0, 0, fd}]))

# the buffer arms first, then the dma arms -- :56 fills `ins + outs` and
# `rpc_prep_args` appends the fds' slots after, so the ORDER is ins, outs, fds.
def pra_of(nins: U32, nouts: U32, +lens: List<&2, U32>, +fds: List<&2, U32>) -> List<&2, Pra>:
  pra_dma(U32.to_nat(U32.from_nat(List.length(&2, U32, fds))),
    fds, pra.put(U32.to_nat(U32.add(nins, nouts)), lens, Nil{}))

def Pra.is_dma(p: Pra) -> Bool:
  match p:
    case Pra{is_dma, pv, len, fd}: is_dma

def Pra.pv(p: Pra) -> U32:
  match p:
    case Pra{is_dma, pv, len, fd}: pv

def Pra.len(p: Pra) -> U32:
  match p:
    case Pra{is_dma, pv, len, fd}: len

def Pra.fd(p: Pra) -> U32:
  match p:
    case Pra{is_dma, pv, len, fd}: fd

def pra_lens(+ps: List<&2, Pra>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: pra_lens(t, List.append(&2, U32, acc, [Pra.len(p)]))

def pra_pvs(+ps: List<&2, Pra>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: pra_pvs(t, List.append(&2, U32, acc, [Pra.pv(p)]))

def pra_fds(+ps: List<&2, Pra>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: pra_fds(t, List.append(&2, U32, acc, [Pra.fd(p)]))


# ===========================================================================
# var_vals_mv and off_mv, :65-69. THE 8-BYTE SLOT TABLE.
# ===========================================================================

# `memoryview(bytearray((len(bufs)+len(vals))*8))` (:65) and
# `memoryview(bytearray(len(bufs)*4))` for the offsets (:65). The var_vals block is
# 8 bytes per ARGUMENT -- buffer or val -- so a 4-byte fmt leaves the high word at
# zero and only an 8-byte fmt writes it.
def vt_nbytes(+nbufs: U32, nvals: U32) -> U32: U32.mul(U32.add(nbufs, nvals), 8)
def vt_nslots(+nbufs: U32, nvals: U32) -> U32: U32.add(nbufs, nvals)
def off_nbytes(nbufs: U32) -> U32: U32.mul(nbufs, 4)

# :67 `struct.pack_into('i', var_vals_mv, i*8, b.size)`. FOUR bytes, signed, at the
# slot's own offset. So a size is `lo = size` and `hi = 0` ALWAYS -- `hi` is
# UNTOUCHED, not sign-extended, so even a size above 2**31 leaves the high word at
# zero. `dsp_vt_size_hi*` is that claim.
def Slot.nbytes(s: Slot) -> U32:
  match s:
    case Slot{lo, hi, nbytes}: nbytes

def vt_size_at(i: U32, size: U32) -> Slot: Slot{size, 0, 8}
def vt_size_byte(i: U32) -> U32: U32.mul(i, 8)

def Slot.lo(s: Slot) -> U32:
  match s:
    case Slot{lo, hi, nbytes}: lo

def Slot.hi(s: Slot) -> U32:
  match s:
    case Slot{lo, hi, nbytes}: hi

# :68 `struct.pack_into(unwrap(dt.fmt), var_vals_mv, i*8, v)` with `i` starting at
# `len(bufs)`. So a val's offset is `(nbufs + j) * 8`, never `j * 8`.
def vt_val_offset(nbufs: U32, j: U32) -> U32: U32.mul(U32.add(nbufs, j), 8)

# how many of the eight bytes a dtype's fmt writes. 8 writes the high word; a
# narrower one does not touch it; void writes none.
def vt_hi_written(nbytes: U32) -> Bool: U32.is_eq(nbytes, 8)
def vt_lo_written(nbytes: U32) -> Bool: U32.is_ge(nbytes, 1)
def vt_hi_of(nm: String) -> Bool: vt_hi_written(dt_itemsize(nm))
def vt_lo_of(nm: String) -> Bool: vt_lo_written(dt_itemsize(nm))


# ===========================================================================
# DSPProgram.__call__, :62-71.
# ===========================================================================

# :63 `if len(bufs) >= 16: raise RuntimeError(f"Too many buffers to execute:
# {len(bufs)}")`. `prog.too_many` is the whole of it; `prog.call`'s `Tr.refuse_now`
# is what turns it into a trace that records NOTHING.
def prog.too_many(nbufs: U32) -> Bool: U32.is_ge(nbufs, MAX_BUFS())

# :65-66. TWO ins, ONE out, and `nfds = len(bufs)`. The two ins are the var_vals
# block and the offsets block; the out is the 8-byte timer.
def TIMER_BYTES() -> U32: 8
def prog.nins() -> U32: 2
def prog.nouts() -> U32: 1

# the three buffers' own sizes, which is `rpc_prep_args`'s `ins + outs` argument.
def prog.pra_lens(+nbufs: U32, nvals: U32) -> List<&2, U32>:
  [vt_nbytes(nbufs, nvals), off_nbytes(nbufs), TIMER_BYTES()]

# :70 `self.dev.exec_lib(self.lib, rpc_sc(method=2, ins=2, outs=1, fds=len(bufs)),
# pra, fds, attrs)`. The selector is a function of ONE number -- `len(bufs)` --
# which is why `dsp_exec_sc_*` is a row family and not a constant.
def prog.exec_sc(nbufs: U32) -> U32:
  rpc_sc(M_INVOKE(), prog.nins(), prog.nouts(), nbufs)

# :71 `return timer[0] / 1e6`. WALL 4 records the read; the DIVISOR is ported
# because it is the one number the seam must agree with the port on.
def prog.scale_micros() -> U32: 1000000

# `nvals` is NOT an argument of `Program.__call__`'s trace -- it changes
# `var_vals_mv`'s length and nothing else -- so it is a parameter here because the
# packer `prog.pra_lens` needs it and the trace does not. That asymmetry is real:
# :62's `vals` reach the device only as bytes inside ins[0].
def prog.call(over: Bool, +nbufs: U32, t: Tr) -> Tr:
  match over:
    case True{}: Tr.refuse_now(t)
    case False{}: Tr.emit(CALL_EXEC_LIB(), prog.exec_sc(nbufs), t)

def prog.run(+nbufs: U32, nvals: U32, t: Tr) -> Tr:
  prog.call(prog.too_many(nbufs), nbufs, t)


# ===========================================================================
# DSPBuffer and DSPAllocator, :73-96.
# ===========================================================================

def buf.of(id: U32, va: U32, size: U32, share_fd: U32, share_handle: U32,
           has_share: Bool) -> DspBuf:
  DspBuf{id, va, size, 0, share_fd, share_handle, has_share}

def buf.va(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: va

def buf.size(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: size

def buf.offset(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: offset

def buf.share_fd(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: share_fd

def buf.share_handle(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: share_handle

def buf.has_share(b: DspBuf) -> Bool:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: has_share

def buf.id(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: id

def Made.buf(m: Made) -> DspBuf:
  match m:
    case Made{buf, t}: buf

def Made.tr(m: Made) -> Tr:
  match m:
    case Made{buf, t}: t

# `nbytes` is NOT a field here either, for the reason device.bend gives: it is
# `size * itemsize` and storing it lets the two disagree. ops_dsp.py reads exactly
# one size (:67, `b.size`), so that is the one field.
def buf.nbytes(b: DspBuf) -> U32: buf.size(b)

# :96 `def _offset(self, buf, size, offset): return DSPBuffer(buf.va_addr+offset,
# size, buf.share_info, buf.offset+offset)`.
#
# THE ACCUMULATION. BOTH fields add the offset and the second is the one that is
# easy to lose: `off` is a view's offset WITHIN the root, so a second view must add
# to the first view's offset rather than replace it. See THE BUFFER-OWNERSHIP
# RULES for what a dropped `buf.offset+` costs.
def alloc.offset.va(va: U32, off: U32) -> U32: U32.add(va, off)
def alloc.offset.acc(offset: U32, off: U32) -> U32: U32.add(offset, off)

# `nsz` and not `size`: a record pattern's binder SHADOWS the parameter of the same
# name, and the first run of this gate caught the view keeping its PARENT's size
# (`dsp_acc_sz1` answered 1024 for a 256-byte view). Python's `_offset` passes the
# caller's `size` straight through.
def alloc.offset(+b: DspBuf, nsz: U32, +off: U32) -> DspBuf:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}:
      DspBuf{id, alloc.offset.va(va, off), nsz, alloc.offset.acc(offset, off),
             share_fd, share_handle, has_share}

# :93 `_as_buffer` is `to_mv(src.va_addr, src.size)` -- the address and the size and
# nothing else, so `alloc.as_buffer_bytes` is the size half of a WALL.
def alloc.as_buffer_bytes(+b: DspBuf) -> U32: buf.size(b)

# :94 `_copyin` is `ctypes.memmove(dest.va_addr, mv_address(src), src.nbytes)` and
# :95 `_copyout` is `ctypes.memmove(mv_address(dest), src.va_addr, dest.nbytes)`.
# THE ASYMMETRY IS REAL: `src.nbytes` going in, `dest.nbytes` coming out. A port
# that read one field for both would be wrong for a view.
def alloc.copyin_bytes(src_bytes: U32) -> U32: src_bytes
def alloc.copyout_bytes(dest_bytes: U32) -> U32: dest_bytes

# :79 `if getenv("MOCKDSP"): fd, share_info, flags = -1, None,
# mmap.MAP_SHARED|mmap.MAP_ANONYMOUS` and the real arm's `flags = mmap.MAP_SHARED`.
def MMAP_PROT() -> U32: 3
def MAP_SHARED() -> U32: 1
def MAP_ANONYMOUS() -> U32: 32

def alloc.mock_flags() -> U32: U32.or(MAP_SHARED(), MAP_ANONYMOUS())
def alloc.real_flags() -> U32: MAP_SHARED()

# :81 `ION_IOC_ALLOC(self.dev.ion_fd, len=size, align=0x200,
# heap_id_mask=1<<ION_SYSTEM_HEAP_ID, flags=ION_FLAG_CACHED)`.
def ion.heap_id_mask() -> U32: U32.shln(1, ION_SYSTEM_HEAP_ID())
def ion.aligned(nbytes: U32) -> U32: H.round_up_u32(nbytes, ION_ALIGN())

# :79-84 `_alloc`. The two arms differ in THREE observable ways: MOCKDSP makes NO
# ION call, has NO share, and adds MAP_ANONYMOUS. All three are recorded, so
# `dsp_alloc_mock_*` is the negative case for each of `dsp_alloc_real_*`.
def alloc.alloc.mock(+nbytes: U32, +t: Tr) -> Made:
  Made{buf.of(Tr.here(t), 0, nbytes, 0, 0, False{}),
       Tr.emit(CALL_MMAP(), nbytes, t)}

# the real arm, in order (:81 alloc, :82 share, :83 mmap). `arg` is the size for the
# alloc and the share flag for the share and the size for the mmap.
def alloc.alloc.real.go(+nbytes: U32, +t: Tr) -> Tr:
  Tr.emit(CALL_MMAP(), nbytes,
    Tr.emit(CALL_ION_SHARE(), ION_FLAG_CACHED(),
      Tr.emit(CALL_ION_ALLOC(), nbytes, t)))

def alloc.alloc.real(+nbytes: U32, +t: Tr) -> Made:
  Made{buf.of(Tr.here(t), 0, nbytes, FD_NONE(), ION_FLAG_CACHED(), True{}),
       alloc.alloc.real.go(nbytes, t)}

def alloc.alloc(nbytes: U32, mock: Bool, t: Tr) -> Made:
  match mock:
    case True{}: alloc.alloc.mock(nbytes, t)
    case False{}: alloc.alloc.real(nbytes, t)

# :86-91 `_free`, `@suppress_finalizing`. THE ORDER IS THE CONTRACT: `libc.munmap`
# FIRST, then `os.close(share_info.fd)`, then `ION_IOC_FREE` -- and the last two are
# INSIDE `if storage.buf.share_info is not None`. So a MOCKDSP free is ONE call and
# a real free is THREE, and `dsp_free_mock_*` is the negative case for every
# `dsp_free_real_*` row.
def alloc.free_calls(has_share: Bool, +nbytes: U32, handle: U32) -> List<&2, Call>:
  Bool.pick(List<&2, Call>, has_share,
    [Call{CALL_MMAP, nbytes}, Call{CALL_OS_CLOSE, FD_NONE()},
     Call{CALL_ION_FREE, handle}],
    [Call{CALL_MMAP, nbytes}])

def alloc.free.go(+cs: List<&2, Call>, t: Tr) -> Tr:
  match cs:
    case Nil{}: t
    case c <> rest: alloc.free.go(rest, Tr.emit(Call.k(c), Call.arg(c), t))

def alloc.free(has_share: Bool, nbytes: U32, handle: U32, t: Tr) -> Tr:
  alloc.free.go(alloc.free_calls(has_share, nbytes, handle), t)


# ===========================================================================
# THE ENTRY SHIM, DSPRenderer._render_entry, :27-44. Every line is a pure string
# function of the PARAM list and the index, which is what makes it gateable.
#
# THE FOUR PHASES, and the trace order below encodes them:
#
#   four FIXED lines  the header, the DCVS request, the power set, the sc>>24 test
#   one sz_or_val     PER PARAM -- ALWAYS, ALU or not -- at `pra[0].buf.pv + i*8`
#   one off + mmap    PER GLOBAL, named by the PARAM's OWN index
#   the tail          timer, the call, the munmaps, `return 0; }`
#
# THE INDEX IS THE PARAM INDEX, NOT A COMPACTED COUNTER. :35 and :37 both say
# `for i,b in enumerate(bufs)` and FILTER, so `off1`/`buf_1`/`pra[4]` name the second
# param even when the first is ALU. MEASURED on the `agga` fixture -- ALU, GLOBAL,
# GLOBAL, ALU -- where the mmap lines are `buf_1`/`pra[4]` and `buf_2`/`pra[5]` and
# the `off` subscripts are 1 and 2, NOT 0 and 1. `dsp_e_agga_*` is that row family,
# and a port that compacted the counter would move it and NOTHING else.
# ===========================================================================

def ENTRY_FIXED() -> U32: 4
def ENTRY_TAIL() -> U32: 4

def entry.head0() -> String: "int entry(unsigned long long handle, unsigned int sc, remote_arg* pra) {"
def entry.head1() -> String:
  "struct dcvs_v2_req req = {.type=7, .dcvs_enable=0, .set_latency=1, .latency=100, .set_dcvs_params=1, .target_corner = 6 /* TURBO */};"
def entry.head2() -> String: "HAP_power_set((void*)handle, (void*)&req);"
def entry.guard() -> String: "if ((sc>>24) != 2) return 0;"
def entry.timer_open() -> String: "unsigned long long start = HAP_perf_get_time_us();"
def entry.timer_close() -> String:
  "*(unsigned long long *)(pra[2].buf.pv) = HAP_perf_get_time_us() - start;"
def entry.ret() -> String: "return 0; }"

# :32-33 the `sz_or_val` DECLARATION. `int` for a GLOBAL -- it is the byte SIZE --
# and `_render_dtype` for an ALU, and both read the SAME slot at `pra[0].buf.pv`.
def entry.sz_decl(+i: U32, +p: Param) -> String:
  String.concat([dt_cname_global(Param.is_alu(p), Param.cn(p)), " sz_or_val_",
    U32.show(i), " = *(", dt_cname_global(Param.is_alu(p), Param.cn(p)),
    "*)((char*)pra[0].buf.pv+", U32.show(vt_size_byte(i)), ");"])

# :35 `f'int off{i} = ((int*)pra[1].buf.pv)[{i}];'` -- the offset subscript is i,
# the ARRAY subscript is i, and the dtype is `int` unconditionally because the
# offsets block was built by `array('I')`.
def entry.off(+i: U32) -> String:
  String.concat(["int off", U32.show(i), " = ((int*)pra[1].buf.pv)[", U32.show(i), "];"])

# :36-37 `void *buf_{i} = HAP_mmap(0,sz_or_val_{i},3,0,pra[{i+3}].dma.fd,0)+off{i};`.
# The literal `3` is PROT_READ|PROT_WRITE, and the dma slot is `i+3` because the
# three non-dma slots (two ins, one out) come first -- which is exactly `prog.nins()
# + prog.nouts()`.
def entry.dma_slot(i: U32) -> U32: U32.add(i, U32.add(prog.nins(), prog.nouts()))

def entry.mmap(+i: U32) -> String:
  String.concat(["void *buf_", U32.show(i), " = HAP_mmap(0,sz_or_val_", U32.show(i),
    ",", U32.show(MMAP_PROT()), ",0,pra[", U32.show(entry.dma_slot(i)),
    "].dma.fd,0)+off", U32.show(i), ";"])

# :39,:40 `fbufs` is `buf_{i}` for a GLOBAL and `sz_or_val_{i}` for an ALU, joined
# with ", " at :40.
def entry.arg_name(+i: U32, +p: Param) -> String:
  Bool.pick(String, Param.is_alu(p),
    String.concat(["sz_or_val_", U32.show(i)]), String.concat(["buf_", U32.show(i)]))

def entry.munmap(+i: U32) -> String:
  String.concat(["HAP_munmap(buf_", U32.show(i), ", sz_or_val_", U32.show(i), ");"])


# ===========================================================================
# THE MOCK SHIM, MockDSPRenderer._render_entry, :256-274. A DIFFERENT entry point:
# `_start`, no DCVS, no mmap-by-fd, and the sizes come from the KERNEL's
# `max_numel()*itemsize` rather than from the wire.
# ===========================================================================

def mockdsp_boilerplate() -> String:
  String.concat([
    "/* DSP boilerplate */ static long syscall(long r0, long r1, long r2, long r3, long r4, long r5, long r6) {",
    "\nlong retval; __asm__ volatile(\"r0 = %1; r1 = %2; r2 = %3; r3 = %4; r4 = %5; r5 = %6; r6 = %7; trap0(#1); %0 = r0\" : \"=r\" (retval)",
    "\n  : \"r\" (r0), \"r\" (r1), \"r\" (r2), \"r\" (r3), \"r\" (r4), \"r\" (r5), \"r\" (r6) : \"r0\", \"r1\", \"r2\", \"r3\", \"r4\", \"r5\", \"r6\"); return retval; }",
    "\nstatic int read(int fd, void* buf, int len) {{ return syscall(fd, (long)buf, len, 0, 0, 0, 63); }}",
    "\nstatic int write(int fd, void* buf, int len) {{ return syscall(fd, (long)buf, len, 0, 0, 0, 64); }}",
    "\nstatic int exit(int ret) {{ return syscall(ret, 0, 0, 0, 0, 0, 93); }}",
    "\nstatic unsigned int inscount(void) {{ unsigned int ret; __asm__ volatile(\".word 0x6a15c000; %0 = R0\" : \"=r\" (ret) : : \"r0\"); return ret; }}",
    "\nstatic void *mmap2(void *addr, unsigned int length, int prot, int flags, int fd, unsigned long offset) {{",
    "\nreturn (void*)syscall((long)addr, length, prot, flags, fd, offset, 222); }}"])

def boiler_lines() -> U32: 9
def boiler_first_len() -> U32: 65

def u32_of_str(+s: String, sub: String) -> U32:
  Bool.to_u32(String.contains(s, sub))

def mrender.start() -> String: "void _start(void) {"
def mrender.stamp() -> String: "unsigned int st = inscount();"
def mrender.finish() -> String: "unsigned int et = inscount() - st; write(1, &et, sizeof(et));"
def mrender.exit() -> String: "exit(0); }"

# :262 `sz = b[1][0].max_numel()*b[1][0].dtype.itemsize`. The byte count is the
# KERNEL's view of the buffer, so it is `numel * itemsize` and NOT the allocated
# size -- which for a VIEW is larger than the window the kernel touches.
def mrender.nbytes(+p: Param) -> U32: U32.mul(Param.numel(p), dt_itemsize(Param.cn(p)))

# :264 `void *buf{i} = mmap2(0, {sz}, 3, 0x21, -1, 0); for(int rd = 0; rd < {sz};
# rd += read(0, buf{i}+rd, {sz}-rd));`. `0x21` is MAP_PRIVATE|MAP_ANONYMOUS. The
# `# https://gpages.juszkiewicz.com.pl/syscalls-table/syscalls.html` NOTE at :257
# is why the numbers below are named after syscalls rather than flags.
def MOCK_MMAP_FLAGS() -> U32: 33

def mrender.mmap(+i: U32, +nb: U32) -> String:
  String.concat(["void *buf", U32.show(i), " = mmap2(0, ", U32.show(nb), ", ",
    U32.show(MMAP_PROT()), ", 0x21, -1, 0); for(int rd = 0; rd < ", U32.show(nb),
    "; rd += read(0, buf", U32.show(i), "+rd, ", U32.show(nb), "-rd));"])

# :266 `{dtype} val{i}; read(0, &val{i}, {itemsize});` -- it is the dtype's OWN name
# (`_render_dtype`), NOT the `int` the GLOBAL arm of :32 uses, and the read length
# is the ITEMSIZE, so a half reads 2 and a double reads 8.
def mrender.val(+i: U32, +p: Param) -> String:
  String.concat([dt_cname(Param.cn(p)), " val", U32.show(i), "; read(0, &val",
    U32.show(i), ", ", U32.show(dt_itemsize(Param.cn(p))), ");"])

# :268 `params` is `(void*)buf{i}` for a GLOBAL -- THE CAST the real shim does not
# need, because `HAP_mmap` already returns `void*` -- and bare `val{i}` otherwise.
def mrender.arg_name(+i: U32, +p: Param) -> String:
  Bool.pick(String, Param.is_alu(p), String.concat(["val", U32.show(i)]),
    String.concat(["(void*)buf", U32.show(i)]))

# :272 `write(1, buf{i}, {max_numel*itemsize})` -- the OUTPUT block, the same width
# as the input, and only for a GLOBAL.
def mrender.emit(+i: U32, +nb: U32) -> String:
  String.concat(["write(1, buf", U32.show(i), ", ", U32.show(nb), ");"])


# ===========================================================================
# DSPCompiler, :98-125.
# ===========================================================================

# :100/:111 `self.args = f"-static {compiler_args}"` when mock and
# `f"-shared {compiler_args} -T{self.link_ld.name}"` otherwise. TWO arms whose FIRST
# WORD differs -- `-static` against `-shared` -- and the mock has no `-T` at all
# because it never wrote a link script.
def compiler_args_first(mock: Bool) -> String:
  Bool.pick(String, mock, ARG_STATIC(), ARG_SHARED())

def compiler_args_has_T(mock: Bool) -> Bool: Bool.not(mock)

# :113 `super().__init__(None if mock else "compile_dsp")`, and device.py:337 then
# gates it on CCACHE. So the cachekey is None for MOCKDSP AND whenever CCACHE is 0 --
# TWO independent reasons, and `dsp_cachekey_*` has a row for each.
def compiler.cachekey_of(+mock: Bool, +ccache: Bool) -> String:
  Bool.pick(String, Bool.and(Bool.not(mock), ccache), CACHEKEY(), "")

def compiler.cachekey_on(+mock: Bool, +ccache: Bool) -> Bool:
  Bool.not(String.eq(compiler.cachekey_of(mock, ccache), ""))

# :104-105 the fifteen sections the link script aligns to 4k. "Aligning all used
# sections to 4k fixes invoke problem" -- the NOTE is the reason and is kept.
def LINK_ALIGN() -> U32: 4096
def LINK_N() -> U32: 15

def link_section(n: Nat) -> String:
  match n:
    case 0n: "text"
    case 1n: "rela.plt"
    case 2n: "rela.dyn"
    case 3n: "plt"
    case 4n: "data"
    case 5n: "bss"
    case 6n: "hash"
    case 7n: "dynamic"
    case 8n: "got"
    case 9n: "got.plt"
    case 10n: "dynsym"
    case 11n: "dynstr"
    case 12n: "symtab"
    case 13n: "shstrtab"
    case _: "strtab"

def link_section.of(+ix: List<&2, Nat>, acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}: acc
    case i <> t: link_section.of(t, List.append(&2, String, acc, [link_section(i)]))

def link_sections() -> List<&2, String>:
  link_section.of(List.range(U32.to_nat(LINK_N())), Nil{})

# :106 `[f'.{n} : ALIGN(4096) {{ *(.{n}) }}' for n in sections]` joined by '\n'.
def link_line(+n: String) -> String:
  String.concat([".", n, " : ALIGN(4096) { *(.", n, ") }"])

# `acc + "\n" + line` keeps the ORDER, at the price of a LEADING separator, and
# `String.drop(.., 1n)` takes it. The other arrangement -- `"\n" + line + acc` --
# is also a prepend but puts the LAST section first; `dsp_link_script` caught both
# arrangements on its first two runs, which is why this row is a whole-string diff
# against CPython rather than a list of lines.
def link_lines(+ns: List<&2, String>, +acc: String) -> String:
  match ns:
    case Nil{}: acc
    case n <> t: link_lines(t, String.concat([acc, "\n", link_line(n)]))

def link_body() -> String: String.drop(link_lines(link_sections(), ""), 1n)

# :108 the whole file, verbatim: the `SECTIONS` wrapper, `. = 0x0`, the fifteen
# sections and the /DISCARD/ tail. `dsp_link_script` diffs the STRING, all
# seventeen lines of it, against CPython's own `sections_link`.
def link_script() -> String:
  String.concat(["SECTIONS { . = 0x0; ", link_body(),
    "\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }"])

# :115-116 `__del__` unlinks the script when not mock -- so the mock has NO temp file
# and `dsp_unlink_*` is the negative case for that too.
def compiler.del_unlinks(mock: Bool) -> Bool: Bool.not(mock)

# :121 the command, a STRING function of `args` and `CC`. `CC` is `getenv('CC',
# 'clang')` and is a parameter here, the way helpers.bend's Flags threads getenv.
def CC_DEFAULT() -> String: "clang"

def compile_cmd(+mock: Bool, +cc: String) -> String:
  String.concat([cc, " ", compiler_args_first(mock), " ", COMPILER_ARGS(),
    Bool.pick(String, compiler_args_has_T(mock), " -T/tmp/dsp_link.ld", ""),
    " ", COMPILE_TAIL()])


# ===========================================================================
# DSPDevice, :128-176. THE INIT SEQUENCE AND THE THREE LIB CALLS.
# ===========================================================================

# :129 `if getenv("MOCKDSP"):` -- ONE branch, and it selects FOUR things at once:
# the renderer (MockDSPRenderer against DSPRenderer), the program (MockDSPProgram
# against DSPProgram), the allocator (`DSPAllocator(self)` either way), and whether
# the whole ION/adsprpc bring-up happens at all.
def dev.is_mock() -> Bool: True{}
def dev.branch_same_alloc() -> Bool: True{}

# :132 `self.ion_fd = os.open('/dev/ion', os.O_RDONLY)` -- the real arm only.
def dev.open_ion(+t: Tr) -> Tr: Tr.emit(CALL_OPEN_ION(), 0, t)

# :134-136 the shell buffer. `round_up(fastrpc_shell.nbytes, 0x1000)` is what is
# ALLOCATED and `fastrpc_shell.nbytes` is what is COPIED, so the two sizes differ
# and `dsp_shell_*` has a row for each. :135's `BufferSpec(nolru=True)` is the
# eviction NEGATIVE case; see THE BUFFER-OWNERSHIP RULES.
def dev.shell_size(nbytes: U32) -> U32: H.round_up_u32(nbytes, SHELL_ALIGN())

# the spec :135 asks for: nolru and nothing else.
def dev.shell_spec() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}

def dev.shell_spec.nolru(s: D.Bspec) -> Bool:
  match s:
    case D.Bspec{uncached, cpu_access, host, nolru, ext_ptr}: nolru

def dev.shell_spec.plain(s: D.Bspec) -> Bool:
  match s:
    case D.Bspec{uncached, cpu_access, host, nolru, ext_ptr}:
      Bool.and(Bool.not(uncached), Bool.and(Bool.not(cpu_access),
        Bool.and(Bool.not(host), Bool.not(ext_ptr))))

# :136 `ctypes.memmove(self.shell_buf.va_addr, mv_address(fastrpc_shell),
# fastrpc_shell.nbytes)` -- the RAW size, not the rounded one.
def dev.shell_copy(nbytes: U32, t: Tr) -> Tr: Tr.emit(CALL_MEMMOVE(), nbytes, t)

# :166-176 `init_dsp`, and the order IS the contract. SEVEN calls when a stale fd is
# present, FIVE when not:
#
#   :169  FASTRPC_IOCTL_INVOKE(rpc_fd, handle=4, sc=rpc_sc(2,0,0,0))  [stale fd]
#   :170  os.close(self.rpc_fd)
#   :172  os.open('/dev/adsprpc-smd', O_RDONLY|O_NONBLOCK)
#   :173  FASTRPC_IOCTL_GETINFO(rpc_fd, 3)
#   :174  FASTRPC_IOCTL_CONTROL(rpc_fd, req=0x3)
#   :175  FASTRPC_IOCTL_INIT(rpc_fd, flags=0x1, file=..., filelen=..., filefd=...)
#   :176  FASTRPC_IOCTL_INVOKE(rpc_fd, handle=3, sc=rpc_sc(3,0,0,0))
#
# The first TWO are inside `if hasattr(self, 'rpc_fd')`, which is `have_fd`. And the
# five-call trace is a SUFFIX of the seven-call one, so a port that skipped the
# stale path would still satisfy a bare order row -- `dsp_init_again_n` and
# `dsp_init_again_first` are the rows that see it, and `dsp_init_again_order` pins
# the whole seven.
def SC_STALE() -> U32: rpc_sc(M_INVOKE(), 0, 0, 0)
def SC_INIT_INVOKE() -> U32: rpc_sc(M_INIT(), 0, 0, 0)

def dev.init_dsp.stale(+t: Tr) -> Tr:
  Tr.emit(CALL_OS_CLOSE(), 98, t)

def dev.init_dsp.fresh.go(+t: Tr) -> Tr:
  Tr.emit(CALL_RPC_INVOKE(), SC_INIT_INVOKE(),
    Tr.emit(CALL_RPC_INIT(), INIT_FLAGS(),
      Tr.emit(CALL_RPC_CONTROL(), CONTROL_REQ(),
        Tr.emit(CALL_RPC_GETINFO(), ARGPTR_SIZE(),
          Tr.emit(CALL_ADSP_OPEN(), 0, t)))))

def dev.init_dsp.fresh(+t: Tr) -> Tr: dev.init_dsp.fresh.go(t)

def dev.init_dsp.after_stale(+t: Tr) -> Tr: dev.init_dsp.fresh(t)

# MEASURED (dsp_oracle.py, `init_dsp`): `INVOKE(33554432)` comes BEFORE
# `CLOSE(98)`, not after. Bend evaluates an argument before the call, so
# `Tr.emit(RPC_INVOKE, SC_STALE, stale(t))` would record the CLOSE FIRST; the
# `.after_stale` hop is what puts them in Python's order. `dsp_init_ag_order` is
# the row that sees it.
def dev.init_dsp.again(+t: Tr) -> Tr:
  dev.init_dsp.after_stale(dev.init_dsp.stale(Tr.emit(CALL_RPC_INVOKE(), SC_STALE(), t)))

def dev.init_dsp(have_fd: Bool, t: Tr) -> Tr:
  match have_fd:
    case True{}: dev.init_dsp.again(t)
    case False{}: dev.init_dsp.fresh(t)

# :141-148 `open_lib`. `fp` is the 44-character URL INCLUDING its NUL (:143), and
# `ins=[array('I',[len(fp),0xff]), fp.encode()]`, so ins[0] is a TWO-WORD block
# whose first word is the length and whose second is fastrpc's 0xff sentinel.
def OPEN_LIB_NAMED_LEN() -> U32: U32.from_nat(String.length(OPEN_LIB_FP()))
def open_lib_len() -> U32: U32.add(OPEN_LIB_NAMED_LEN(), OPEN_LIB_NUL_LEN())
def open_lib_ins1() -> U32: OPEN_LIB_SENTINEL()
def open_lib_out0() -> U32: 8
def open_lib_out1() -> U32: 255

def dev.open_lib_sc() -> U32: rpc_sc(M_OPEN(), 2, 2, 0)

# :146 `FASTRPC_IOCTL_INVOKE(self.rpc_fd, handle=0, sc=..., pra=pra)`.
def dev.open_lib(+t: Tr) -> Tr: Tr.emit(CALL_OPEN_LIB(), dev.open_lib_sc(), t)

# :147 `if o1.cast('i')[1] < 0: raise RuntimeError(f"Cannot open lib:
# {o2.tobytes().decode()}")`. o1 is 8 bytes = TWO i32s and the SECOND is the status;
# o2 is the 255-byte message. The raise is the truncation.
# `o1.cast('i')[1] < 0` is a SIGNED 32-bit test, and a U32 cannot answer it --
# `U32.is_lt(4294967295, 0)` is False. The faithful reading is the TOP BIT, which is
# exactly what `cast('i')` looks at. MEASURED against CPython's own signed value
# for each of the six fixtures in `dsp_ol_bad_*`.
def open_lib_bad(status: U32) -> Bool: U32.is_eq(U32.shrn(status, 31n), 1)

# MEASURED: `f"Cannot open lib: {msg}"` on an EMPTY message is `"Cannot open lib: "`
# WITH a trailing space, and on a non-empty one it is the same string with the
# message appended. So the space is in the PREFIX here and the message carries no
# leading space -- which is the only split that makes BOTH rows right. The trailing
# space is invisible in a diff and `String.concat` keeps it, so `dsp_ol_err_empty`
# says so in its own comment.
def open_lib_err(+msg: String) -> String:
  String.concat(["RuntimeError: Cannot open lib: ", msg])

# :148 `return o1.cast('I')[0]` -- the HANDLE, which is the id the seam minted.
def dev.open_lib_handle(+t: Tr) -> U32: Tr.here(t)

# :150-152 `close_lib`: ONE ins of `[handle, 0xff]`, TWO outs, `rpc_sc(1,1,2)`.
def dev.close_lib_sc() -> U32: rpc_sc(M_CLOSE(), 1, 2, 0)

def dev.close_lib(+t: Tr) -> Tr: Tr.emit(CALL_CLOSE_LIB(), dev.close_lib_sc(), t)

# :154-164 `exec_lib`. THE TRIPLE IS open -> invoke-with-attrs -> close, and on
# `(OSError, PermissionError)` the WHOLE triple is retried once after `init_dsp()`;
# a second failure becomes `RuntimeError(e)`. TWO attempts, never three -- the same
# shape as device.py:271-276, which device.bend already ports as `D.alloc_try`.
#
# `fail` is what the open/invoke/close triple does: on a device error the OPEN is
# recorded (it succeeded), the INVOKE is not (it is the ioctl that raised), and
# `Tr.emit`'s guard then records no close either. So `fail` yields EXACTLY ONE call.
def dev.invoke_attrs(+sc: U32, +t: Tr) -> Tr:
  Tr.emit(CALL_RPC_INVOKE_ATTRS(), sc, t)

def exec_full(+sc: U32, +t: Tr) -> Tr:
  dev.close_lib(dev.invoke_attrs(sc, dev.open_lib(t)))

def exec_once(+sc: U32, fail: Bool, +t: Tr) -> Tr:
  match fail:
    case True{}: dev.open_lib(t)
    case False{}: exec_full(sc, t)

# MEASURED: a first-attempt failure records open, then the SEVEN of init_dsp, then
# a whole new triple -- ELEVEN calls, with TWO opens and TWO invokes. A port that
# skipped the first attempt would record TEN and `dsp_exec_retry_n` would see it.
def dev.exec_lib.retry(+sc: U32, fail_second: Bool, +t: Tr) -> Tr:
  exec_once(sc, fail_second, dev.init_dsp(True{}, exec_once(sc, True{}, t)))

def dev.exec_lib(+sc: U32, fail_first: Bool, fail_second: Bool, +t: Tr) -> Tr:
  match fail_first:
    case True{}: dev.exec_lib.retry(sc, fail_second, t)
    case False{}: exec_once(sc, False{}, t)


# ===========================================================================
# RPCListener, :178-239. THE sc DISPATCH AND THE ARGUMENT LAYOUTS.
# ===========================================================================

# :185 `context, status, TINYFD = 0, 0xffffffff, 0xffff`.
def RPC_CONTEXT() -> U32: 0
def RPC_STATUS_OK() -> U32: 0
def RPC_STATUS_ERR() -> U32: 4294967295

# :194 `sc=0x04020200` -- SPELLED AS A LITERAL in Python, and it is NOT
# `rpc_sc(2,2,1,0)`. MEASURED: 67240448 against 33685760, differing by exactly the
# method byte. So a port that "helpfully" rewrote the literal as an `rpc_sc` call
# would send method 2 and the DSP would never see a greeting. THE most load-bearing
# constant in the file, and `dsp_rpc_greet_*` is its row family.
def RPC_GREET() -> U32: 67240448
def RPC_GREET_IS_EXEC() -> Bool: U32.is_eq(RPC_GREET(), rpc_sc(M_INVOKE(), 2, 1, 0))

# the seven `sc` values the loop dispatches on, taken from the elif chain at
# :213-238. The chain's ORDER is not the numeric order, so `rpc.arm` is a table and
# `dsp_rpc_arms` is its image.
def SC_HELLO() -> U32: 131584
def SC_OPEN() -> U32: 199229440
def SC_CLOSE() -> U32: 50397184
def SC_SEEK() -> U32: 151004672
def SC_READ() -> U32: 67125248
def SC_STAT() -> U32: 31195136
def SC_MMAP() -> U32: 33619968

def ARM_NONE() -> U32: 0
def ARM_HELLO() -> U32: 1
def ARM_OPEN() -> U32: 2
def ARM_CLOSE() -> U32: 3
def ARM_SEEK() -> U32: 4
def ARM_READ() -> U32: 5
def ARM_STAT() -> U32: 6
def ARM_MMAP() -> U32: 7

# The chain's ORDER is not the numeric order -- it is greeting, open, close, seek,
# read, stat, mmap -- so `rpc.arm` is a table in the chain's order and `rpc.arm_ids`
# is the same order as a list. The scrutinees are the LITERAL values because a
# `case` arm takes a pattern and a def call is not one; the `SC_*` constants below
# are those literals and `dsp_rpc_scs` pins them.
def rpc.arm_open(sc: U32) -> U32:
  match sc:
    case 131584: ARM_HELLO()
    case 199229440: ARM_OPEN()
    case _: ARM_NONE()

def rpc.arm_close(sc: U32) -> U32:
  match sc:
    case 50397184: ARM_CLOSE()
    case 151004672: ARM_SEEK()
    case _: rpc.arm_open(sc)

def rpc.arm_read(sc: U32) -> U32:
  match sc:
    case 67125248: ARM_READ()
    case 31195136: ARM_STAT()
    case _: rpc.arm_close(sc)

def rpc.arm(sc: U32) -> U32:
  match sc:
    case 33619968: ARM_MMAP()
    case _: rpc.arm_read(sc)

# the chain's ORDER as arm ids, so it can be printed. SEVEN, not eight: `ARM_NONE`
# is :239's raise and is not an arm.
def rpc.arm_ids.at(n: Nat) -> U32:
  match n:
    case 0n: ARM_HELLO()
    case 1n: ARM_OPEN()
    case 2n: ARM_CLOSE()
    case 3n: ARM_SEEK()
    case 4n: ARM_READ()
    case 5n: ARM_STAT()
    case _: ARM_MMAP()

def rpc.arm_ids.of(+ix: List<&2, Nat>, acc: List<&2, U32>) -> List<&2, U32>:
  match ix:
    case Nil{}: acc
    case i <> t: rpc.arm_ids.of(t, List.append(&2, U32, acc, [rpc.arm_ids.at(i)]))

def rpc.arm_ids() -> List<&2, U32>: rpc.arm_ids.of(List.range(7n), Nil{})

# :186-187 the listener's OWN request block: TWO ins of 0x10 bytes and TWO outs of
# 0x10000, so `rpc.lens` is four numbers in order.
def RPC_MSG_BYTES() -> U32: 16
def RPC_BUF_BYTES() -> U32: 65536
def RPC_NINS() -> U32: 2
def RPC_NOUTS() -> U32: 2

def rpc.lens() -> List<&2, U32>:
  [RPC_MSG_BYTES(), RPC_BUF_BYTES(), RPC_MSG_BYTES(), RPC_BUF_BYTES()]

# :188 `req_args[1].buf.len = 0` -- the RESPONSE-LENGTH field is zeroed AFTER
# rpc_prep_args has set it, so it is the one slot whose length the caller overrides.
def rpc.out_len_index() -> U32: 1
def rpc.out_len_zero() -> U32: 0

# :192 `msg_send[:] = array.array('I', [context, status, req_args[1].buf.len,
# in_buf.nbytes])` -- FOUR words, and the two that MOVE are the status and the
# response length.
def rpc.msg_status_index() -> U32: 1
def rpc.msg_len_index() -> U32: 2
def rpc.msg_inbytes_index() -> U32: 3

# :197 `context, inbufs, outbufs = msg_recv[0], ((sc:=msg_recv[2]) >> 16) & 0xff,
# (msg_recv[2] >> 8) & 0xff`. The reply's word 2 is the SAME selector layout
# `rpc_sc` builds, read back with shifts -- which is why `sc_ins`/`sc_outs` mask
# with 0xff rather than reading the whole shifted word.
def rpc.reply_sc_index() -> U32: 2
def rpc.reply_context_index() -> U32: 0

# :201 `round_up(in_ptr + 4, 8) if i < inbufs else round_up(out_ptr + 4, 8)`.
# EVERY object pointer is 8-aligned and sits after a 4-byte size, so the padding is
# 0 or 4 and the object itself starts at the aligned address.
def RPC_OBJ_ALIGN() -> U32: 8
def RPC_SIZE_BYTES() -> U32: 4

def rpc.obj_pad(off: U32) -> U32: U32.sub(RPC_OBJ_ALIGN(), U32.mod(off, RPC_OBJ_ALIGN()))
def rpc.obj_count(inbufs: U32, outbufs: U32) -> U32: U32.add(inbufs, outbufs)

# the seven arms' ARGUMENT COUNTS, which is the pure part of WALL 3:
#   :215 open   in_args[3] is the NAME, out_args[0] is the fd
#   :218 close  in_args[0] is the fd
#   :220 seek   in_args[0] is (fd, offset, whence)
#   :225 read   in_args[0] is (fd, count), out_args[0..1]
#   :232 stat   in_args[1] is the PATH, out_args[0] is apps_std_STAT
#   :236 mmap   in_args[0] is (prot, flags, size), out_args[0]
def rpc.nin.arm(a: U32) -> U32:
  match a:
    case 2: 4
    case 3: 1
    case 4: 1
    case 5: 1
    case _: 2

def rpc.nin(a: U32) -> U32:
  match a:
    case 1: 0
    case 7: 1
    case _: rpc.nin.arm(a)

def rpc.nout.arm(a: U32) -> U32:
  match a:
    case 2: 1
    case 5: 2
    case _: 1

def rpc.nout(a: U32) -> U32:
  match a:
    case 1: 0
    case 3: 0
    case 4: 0
    case _: rpc.nout.arm(a)

def rpc.arm_cnts(+a: U32, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, acc, [rpc.nin(a)]), [rpc.nout(a)])

def rpc.cnt_table(+as: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match as:
    case Nil{}: acc
    case a <> t: rpc.cnt_table(t, rpc.arm_cnts(a, acc))

def rpc.cnts() -> List<&2, U32>: rpc.cnt_table(rpc.arm_ids(), Nil{})

# :221 `assert in_args[0].cast('I')[2] == APPS_STD_SEEK_SET, "Supported only
# SEEK_SET"` -- the only assert in the file, and it is a refusal. SEEK_SET is 0 in
# apps_std, which is why SEEK_CUR and SEEK_END are both refused.
def APPS_STD_SEEK_SET() -> U32: 0

def rpc.seek_ok(whence: U32) -> Bool: U32.is_eq(whence, APPS_STD_SEEK_SET())

def rpc.seek_err(+sc: U32) -> String:
  String.concat(["AssertionError: Supported only SEEK_SET (sc=", U32.show(sc), ")"])

# :213 `if sc == 0x20200: pass # greating` -- the greeting arm does NOTHING, which is
# the one arm with no side effect. `dsp_rpc_hello_n` says so by pinning zero calls.
def rpc.hello(+t: Tr) -> Tr: t

# :239 the unknown-op raise. `rpc.arm` answers `ARM_NONE` and the caller turns that
# into a refusal with nothing recorded.
def rpc.unknown_err(+sc: U32) -> String:
  String.concat(["RuntimeError: Unknown op: sc=", U32.show(sc)])


# ===========================================================================
# MockDSPProgram, :276-292. THE STDIN/STDOUT HANDSHAFF.
#
# :283-286 the input is `b''.join([bytes(to_mv(x.va_addr, x.size)) for x in bufs] +
# [struct.pack(unwrap(dt.fmt), x) for x,(_,_,dt,_) in zip(vals,
# signature[len(bufs):])])` -- the buffers FIRST, in order, then the vals packed with
# `dt.fmt`. So the mock's wire format is the SAME `dt.fmt` table the real shim uses,
# laid out flat instead of 8-aligned. One table, two layouts, which is why there is
# no per-dtype row family here: it would be a duplicate of `dsp_fmt_*`.
# ===========================================================================

def mprog.stdin_bytes.go(+bs: List<&2, U32>, acc: U32) -> U32:
  match bs:
    case Nil{}: acc
    case b <> t: mprog.stdin_bytes.go(t, U32.add(acc, b))

def mprog.stdin_bytes(bs: List<&2, U32>) -> U32:
  mprog.stdin_bytes.go(bs, 0)

def mprog.nstdin(+nbufs: U32, nvals: U32) -> U32:
  U32.add(mprog.stdin_bytes(fx.bufs3()), U32.mul(nvals, 8))

# :287 `offset = 4` -- the inscount is the FIRST four bytes of stdout, then the
# buffers in order, then `assert offset == len(proc.stdout)`.
def MPROG_HEAD() -> U32: 4

def mprog.stdout_len(nbytes: U32) -> U32: U32.add(MPROG_HEAD(), nbytes)

# :292 `struct.unpack("I", proc.stdout[0:4])[0] / 1e9  # pretend it's 1 Ghz, but this
# is an inscount, not a time`. THE DIVISOR DIFFERS from the real program's 1e6.
def mprog.scale_ins() -> U32: 1000000000


# ===========================================================================
# THE FIXTURES. A `Param` list per entry-renderer fixture; `agga` is the load-
# bearing one (ALU, GLOBAL, GLOBAL, ALU) because it is the only fixture where a
# compacted index counter differs from the param index.
# ===========================================================================

def entry.count_sz.of(+ps: List<&2, Param>, got: U32) -> U32:
  match ps:
    case Nil{}: got
    case _ <> t: entry.count_sz.of(t, U32.add(got, 1))

def entry.count_sz(ps: List<&2, Param>) -> U32: entry.count_sz.of(ps, 0)

def bool_eq(a: Bool, b: Bool) -> Bool: Bool.not(Bool.xor(a, b))

def entry.count_go(+nat: Bool, +ps: List<&2, Param>, got: U32) -> U32:
  match ps:
    case Nil{}: got
    case p <> t:
      entry.count_go(nat, t, U32.add(got, Bool.to_u32(bool_eq(Param.is_alu(p), nat))))

# PER PARAM -- every one, ALU or not (:32 emits one for all of them).
def entry.count_sz_of(ps: List<&2, Param>) -> U32: entry.count_sz(ps)

# PER GLOBAL -- and the global arm is the complement of the ALU arm, so `is_alu`
# false is the condition (:35 and :37 both filter on `!= AddrSpace.GLOBAL`).
def entry.count_off(ps: List<&2, Param>) -> U32: entry.count_go(False{}, ps, 0)

def entry.count_mmap(ps: List<&2, Param>) -> U32: entry.count_off(ps)
def entry.count_munmap(ps: List<&2, Param>) -> U32: entry.count_off(ps)
def entry.count_alu(ps: List<&2, Param>) -> U32: entry.count_go(True{}, ps, 0)

# the total line count of an entry, which is the row that sees a DROPPED line --
# every other row here reads one line and a line that stopped being emitted is
# invisible to them.
def entry.line_count(+ps: List<&2, Param>) -> U32:
  U32.add(ENTRY_FIXED(), U32.add(entry.count_sz_of(ps),
    U32.add(U32.mul(entry.count_off(ps), 2),
      U32.add(ENTRY_TAIL(), entry.count_munmap(ps)))))

# ===========================================================================
# THE DOMAIN-SPANNING TABLES. `NAMES` is dtype.py's own twenty, in its `__lt__`
# order, and the two counts fold over it -- so 12 have a fmt and 20 exist, and
# nothing in the domain is left unaccounted for.
# ===========================================================================

def NAMES.at(n: Nat) -> String:
  match n:
    case 0n: "void"
    case 1n: "bool"
    case 2n: "weakint"
    case 3n: "signed char"
    case 4n: "unsigned char"
    case 5n: "short"
    case 6n: "unsigned short"
    case 7n: "int"
    case 8n: "unsigned int"
    case 9n: "long"
    case 10n: "unsigned long"
    case 11n: "weakfloat"
    case 12n: "float8_e4m3"
    case 13n: "float8_e4m3fnuz"
    case 14n: "float8_e5m2"
    case 15n: "float8_e5m2fnuz"
    case 16n: "half"
    case 17n: "__bf16"
    case 18n: "float"
    case _: "double"

def NAMES.of(+ix: List<&2, Nat>, acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}: acc
    case i <> t: NAMES.of(t, List.append(&2, String, acc, [NAMES.at(i)]))

def NAMES() -> List<&2, String>: NAMES.of(List.range(20n), Nil{})

def count_all(+ns: List<&2, String>, got: U32) -> U32:
  match ns:
    case Nil{}: got
    case _ <> t: count_all(t, U32.add(got, 1))

def count_fmt(+ns: List<&2, String>, got: U32) -> U32:
  match ns:
    case Nil{}: got
    case n <> t: count_fmt(t, U32.add(got, Bool.to_u32(dt_has_fmt(n))))

def dt_fmt_all_count() -> U32: count_all(NAMES(), 0)

def dt_fmt_has_count() -> U32: count_fmt(NAMES(), 0)

# ===========================================================================
# THE GATE. Every `py=` expectation below was GENERATED by
# `.agents/slop/dsp_oracle.py` calling CPython. None was typed by hand.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

def first_k(cs: List<&2, Call>) -> U32:
  match cs:
    case Nil{}: 0
    case c <> _: Call.k(c)

def second_k.go(cs: List<&2, Call>) -> U32:
  match cs:
    case Nil{}: 0
    case _ <> Nil{}: 0
    case _ <> t: first_k(t)

def second_k(cs: List<&2, Call>) -> U32: second_k.go(cs)

def last_k.go(cs: List<&2, Call>, last: U32) -> U32:
  match cs:
    case Nil{}: last
    case c <> t: last_k.go(t, Call.k(c))

def last_k(cs: List<&2, Call>) -> U32: last_k.go(cs, 0)

def kind_list.go(+cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t: kind_list.go(t, List.append(&2, U32, acc, [Call.k(c)]))

def kind_list(cs: List<&2, Call>) -> List<&2, U32>: kind_list.go(cs, Nil{})

# --- 1: rpc_sc, :48 ------------------------------------------------------------
def t_rpcsc() -> IO(Unit):
  do IO<Unit>:
    urow("dsp_sc_0000", rpc_sc(0, 0, 0, 0))                    # py=0
    urow("dsp_sc_2210", rpc_sc(2, 2, 1, 0))                    # py=33685760
    urow("dsp_sc_open", rpc_sc(0, 2, 2, 0))                    # py=131584
    urow("dsp_sc_close", rpc_sc(1, 1, 2, 0))                   # py=16843264
    urow("dsp_sc_2000", rpc_sc(2, 0, 0, 0))                    # py=33554432
    urow("dsp_sc_3000", rpc_sc(3, 0, 0, 0))                    # py=50331648
    urow("dsp_sc_2211", rpc_sc(2, 2, 1, 1))                    # py=33685761
    urow("dsp_sc_22115", rpc_sc(2, 2, 1, 15))                  # py=33685775
    urow("dsp_sc_22116", rpc_sc(2, 2, 1, 16))                  # py=33685776
    urow("dsp_sc_max", rpc_sc(255, 255, 255, 255))             # py=4294967295
    urow("dsp_sc_f255", rpc_sc(0, 0, 0, 255))                  # py=255
    urow("dsp_sc_m1", rpc_sc(1, 0, 0, 0))                      # py=16777216
    urow("dsp_sc_i1", rpc_sc(0, 1, 0, 0))                      # py=65536
    urow("dsp_sc_o1", rpc_sc(0, 0, 1, 0))                      # py=256
    urow("dsp_sc_2213", rpc_sc(2, 2, 1, 3))                    # py=33685763
    urow("dsp_sc_2217", rpc_sc(2, 2, 1, 7))                    # py=33685767
    urow("dsp_sc_2218", rpc_sc(2, 2, 1, 8))                    # py=33685768
    # the four fields are INDEPENDENT, which is what lets fds up to 15 and outs=1
    lrow("dsp_sc_f255_only", [sc_fds(255)])                    # py=255
    lrow("dsp_sc_o255_only", [sc_outs(rpc_sc(0, 0, 255, 0))])  # py=255
    lrow("dsp_sc_i255_only", [sc_ins(rpc_sc(0, 255, 0, 0))])   # py=255
    lrow("dsp_sc_m255_only", [sc_method(rpc_sc(255, 0, 0, 0))])  # py=255

# --- 2: the selector's two readers, and the entry shim's refusal -------------
def t_scfields() -> IO(Unit):
  do IO<Unit>:
    lrow("dsp_scf_2210", [sc_method(33685760), sc_ins(33685760),
                          sc_outs(33685760), sc_fds(33685760)])  # py=2,2,1,0
    lrow("dsp_scf_22115", [sc_method(33685775), sc_ins(33685775),
                           sc_outs(33685775), sc_fds(33685775)])  # py=2,2,1,15
    lrow("dsp_scf_open", [sc_method(131584), sc_ins(131584),
                          sc_outs(131584), sc_fds(131584)])  # py=0,2,2,0
    # :33 `if ((sc>>24) != 2) return 0;` -- method 2 ONLY.
    row("dsp_entry_ok_2", entry.method_ok(rpc_sc(2, 2, 1, 0)))   # py=True
    row("dsp_entry_ok_2b", entry.method_ok(rpc_sc(2, 0, 0, 0)))  # py=True
    row("dsp_entry_no_4", entry.method_ok(RPC_GREET()))           # py=False
    row("dsp_entry_no_0", entry.method_ok(0))                    # py=False
    row("dsp_entry_no_3", entry.method_ok(rpc_sc(3, 0, 0, 0)))   # py=False
    row("dsp_entry_no_1", entry.method_ok(rpc_sc(1, 1, 2, 0)))   # py=False

# --- 3: the four dtype tables -------------------------------------------------
def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    srow("dsp_fmt_bool", dt_fmt("bool"))                   # py=?
    srow("dsp_fmt_schar", dt_fmt("signed char"))           # py=b
    srow("dsp_fmt_uchar", dt_fmt("unsigned char"))         # py=B
    srow("dsp_fmt_short", dt_fmt("short"))                 # py=h
    srow("dsp_fmt_ushort", dt_fmt("unsigned short"))       # py=H
    srow("dsp_fmt_int", dt_fmt("int"))                     # py=i
    srow("dsp_fmt_uint", dt_fmt("unsigned int"))           # py=I
    srow("dsp_fmt_long", dt_fmt("long"))                   # py=q
    srow("dsp_fmt_ulong", dt_fmt("unsigned long"))         # py=Q
    srow("dsp_fmt_half", dt_fmt("half"))                   # py=e
    srow("dsp_fmt_float", dt_fmt("float"))                 # py=f
    srow("dsp_fmt_double", dt_fmt("double"))               # py=d
    # the SIX with `fmt is None`: void, weakint, weakfloat, four fp8s, bfloat16.
    row("dsp_fmt_no_void", Bool.not(dt_has_fmt("void")))         # py=True
    row("dsp_fmt_no_weakint", Bool.not(dt_has_fmt("weakint")))   # py=True
    row("dsp_fmt_no_weakfloat", Bool.not(dt_has_fmt("weakfloat")))  # py=True
    row("dsp_fmt_no_bf16", Bool.not(dt_has_fmt("__bf16")))       # py=True
    row("dsp_fmt_no_fp8", Bool.not(dt_has_fmt("float8_e4m3")))   # py=True
    urow("dsp_fmt_has_n", dt_fmt_has_count())      # py=12
    # and the twelve that DO have one -- so 12 + 8 = 20 and nothing is unaccounted.
    urow("dsp_fmt_all_n", dt_fmt_all_count())                    # py=20
    # itemsize, including the two 100-byte placeholders
    urow("dsp_isz_void", dt_itemsize("void"))               # py=0
    urow("dsp_isz_bool", dt_itemsize("bool"))               # py=1
    urow("dsp_isz_schar", dt_itemsize("signed char"))       # py=1
    urow("dsp_isz_short", dt_itemsize("short"))             # py=2
    urow("dsp_isz_half", dt_itemsize("half"))               # py=2
    urow("dsp_isz_bf16", dt_itemsize("__bf16"))             # py=2
    urow("dsp_isz_int", dt_itemsize("int"))                 # py=4
    urow("dsp_isz_float", dt_itemsize("float"))             # py=4
    urow("dsp_isz_long", dt_itemsize("long"))               # py=8
    urow("dsp_isz_ulong", dt_itemsize("unsigned long"))     # py=8
    urow("dsp_isz_double", dt_itemsize("double"))           # py=8
    urow("dsp_isz_weakint", dt_itemsize("weakint"))         # py=100
    urow("dsp_isz_weakfloat", dt_itemsize("weakfloat"))     # py=100
    urow("dsp_isz_fp8", dt_itemsize("float8_e4m3"))         # py=1
    urow("dsp_isz_fp8b", dt_itemsize("float8_e5m2fnuz"))    # py=1
    # spec.bend's OWN itemsize agrees on the six that matter, which is a cheap
    # cross-check that the two dtype models have not drifted.
    lrow("dsp_isz_spec", [S.Dt.itemsize(S.uint32()), S.Dt.itemsize(S.half()),
                          S.Dt.itemsize(S.double()), dt_itemsize_dt(S.uint32()),
                          dt_itemsize_dt(S.half()), dt_itemsize_dt(S.double())])
    # py=4,2,8,4,2,8
    # dt_cname -- the two entries ops_dsp.py:15 ADDS to a two-key map
    srow("dsp_cn_bool", dt_cname("bool"))                   # py=_Bool
    srow("dsp_cn_half", dt_cname("half"))                   # py=__fp16
    srow("dsp_cn_long", dt_cname("long"))                   # py=long long
    srow("dsp_cn_ulong", dt_cname("unsigned long"))         # py=unsigned long long
    srow("dsp_cn_float", dt_cname("float"))                 # py=float
    srow("dsp_cn_double", dt_cname("double"))               # py=double
    srow("dsp_cn_int", dt_cname("int"))                     # py=int
    srow("dsp_cn_bf16", dt_cname("__bf16"))                 # py=__bf16
    srow("dsp_cn_fp8", dt_cname("float8_e4m3"))             # py=float8_e4m3
    # the GLOBAL arm: a float buffer's SIZE is an `int`
    srow("dsp_cng_glob_f32", dt_cname_global(False{}, "float"))          # py=int
    srow("dsp_cng_glob_u64", dt_cname_global(False{}, "unsigned long"))  # py=int
    srow("dsp_cng_glob_i64", dt_cname_global(False{}, "long"))           # py=int
    srow("dsp_cng_alu_f32", dt_cname_global(True{}, "float"))            # py=float
    srow("dsp_cng_alu_u64", dt_cname_global(True{}, "unsigned long"))    # py=unsigned long long
    srow("dsp_cng_alu_bool", dt_cname_global(True{}, "bool"))            # py=_Bool
    # :16 code_for_op = clang's minus SQRT. 18 -> 17.
    urow("dsp_cfop_clang", CFOP_CLANG())                     # py=18
    urow("dsp_cfop_dsp", CFOP_DSP())                         # py=17
    urow("dsp_cfop_removed", cfop_removed())                 # py=1
    # :46 supported_dtypes
    urow("dsp_sd_n", U32.from_nat(List.length(&2, String, supported_names())))  # py=12
    row("dsp_sd_drop_bf16", Bool.not(dt_supported(True{}, "__bf16")))   # py=True
    row("dsp_sd_drop_fp8", Bool.not(dt_supported(True{}, "float8_e4m3")))  # py=True
    row("dsp_sd_drop_fp8b", Bool.not(dt_supported(True{}, "float8_e5m2fnuz")))  # py=True
    row("dsp_sd_keep_bool", dt_supported(True{}, "bool"))     # py=True
    row("dsp_sd_keep_half", dt_supported(True{}, "half"))     # py=True
    row("dsp_sd_keep_double", dt_supported(True{}, "double"))  # py=True
    row("dsp_sd_keep_long", dt_supported(True{}, "long"))     # py=True
    srow("dsp_sd_0", supported_12.at(0n))                     # py=bool
    srow("dsp_sd_7", supported_12.at(7n))                     # py=long
    srow("dsp_sd_11", supported_12.at(11n))                   # py=double


# --- 4: rpc_prep_args, :49-57 -------------------------------------------------
def t_pra() -> IO(Unit):
  do IO<Unit>:
    lrow("dsp_pra_len_000", [pra_len(0, 0, 0)])                    # py=0
    lrow("dsp_pra_len_2210", [pra_len(2, 1, 0)])                    # py=3
    lrow("dsp_pra_len_0220", [pra_len(0, 2, 2)])                    # py=4
    lrow("dsp_pra_len_2213", [pra_len(2, 1, 3)])                    # py=6
    lrow("dsp_pra_len_22115", [pra_len(2, 1, 15)])                  # py=18
    lrow("dsp_pra_len_22116", [pra_len(2, 1, 16)])                  # py=19
    lrow("dsp_pra_len_111", [pra_len(1, 1, 1)])                     # py=3
    lrow("dsp_pra_len_112", [pra_len(1, 1, 2)])                     # py=4
    # :53 fds = [-1]*(ins+outs) ++ in_fds
    lrow("dsp_fds_2210", fds_of(2, 1, Nil{}))                       # py=4294967295,4294967295,4294967295
    lrow("dsp_fds_2213", fds_of(2, 1, fx.ffs3()))                   # py=4294967295,4294967295,4294967295,10,11,12
    lrow("dsp_fds_000", fds_of(0, 0, Nil{}))                        # py=
    lrow("dsp_fds_002", fds_of(0, 0, fx.ffs3()))                    # py=10,11,12
    lrow("dsp_fds_111", fds_of(1, 1, [10]))                         # py=4294967295,4294967295,10
    lrow("dsp_fds_22116", fds_of(2, 1, fx.ffs16()))                 # py=4294967295,4294967295,4294967295,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25
    # :54 attrs = [0]*(ins+outs) ++ [1]*len(in_fds)
    lrow("dsp_attr_2210", attrs_of(2, 1, 0))                        # py=0,0,0
    lrow("dsp_attr_2213", attrs_of(2, 1, 3))                        # py=0,0,0,1,1,1
    lrow("dsp_attr_000", attrs_of(0, 0, 0))                         # py=
    lrow("dsp_attr_002", attrs_of(0, 0, 2))                         # py=1,1
    lrow("dsp_attr_111", attrs_of(1, 1, 1))                         # py=0,0,1
    lrow("dsp_attr_0220", attrs_of(0, 2, 2))                        # py=0,0,1,1
    lrow("dsp_attr_22116", attrs_of(2, 1, 16))                    # py=0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    # the two arrays have the SAME length as pra -- that is the shape claim
    lrow("dsp_pra_lens_eq", [pra_len(2, 1, 3),
      U32.from_nat(List.length(&2, U32, fds_of(2, 1, fx.ffs3()))),
      U32.from_nat(List.length(&2, U32, attrs_of(2, 1, 3)))])        # py=6,6,6
    # :56 the buffer arms. lens [8,16,8] is the oracle's own (2,1) fixture.
    lrow("dsp_pra_len_2210v", pra_lens(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))       # py=8,16,8
    lrow("dsp_pra_pv_2210v", pra_pvs(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))        # py=1,1,1
    lrow("dsp_pra_len_2213v", pra_lens(pra_of(2, 1, [8, 16, 8], fx.ffs3()), Nil{}))  # py=8,16,8,0,0,0
    lrow("dsp_pra_fd_2213v", pra_fds(pra_of(2, 1, [8, 16, 8], fx.ffs3()), Nil{}))   # py=0,0,0,10,11,12
    lrow("dsp_pra_fd_2210v", pra_fds(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))        # py=0,0,0
    # THE ZERO-LENGTH RULE
    lrow("dsp_pra_len_z", pra_lens(pra_of(1, 1, [0, 8], [7]), Nil{}))   # py=0,8,0
    lrow("dsp_pra_pv_z", pra_pvs(pra_of(1, 1, [0, 8], [7]), Nil{}))     # py=0,1,0
    row("dsp_pra_pvset_0", Bool.not(pra.pv_set(0)))                 # py=True
    row("dsp_pra_pvset_8", pra.pv_set(8))                           # py=True
    # one PAST the :63 refusal still packs -- :63 refuses the CALL, not the packer
    lrow("dsp_pra_len_22116v", pra_lens(pra_of(2, 1, [8, 16, 8], fx.ffs16()), Nil{}))  # py=8,16,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    lrow("dsp_pra_fd_22116v", pra_fds(pra_of(2, 1, [8, 16, 8], fx.ffs16()), Nil{}))   # py=0,0,0,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25

# --- 5: var_vals and off_mv, :65-69 -------------------------------------------
def t_varvals() -> IO(Unit):
  do IO<Unit>:
    lrow("dsp_vt_b_3_0", [vt_nbytes(3, 0)])                          # py=24
    lrow("dsp_vt_b_3_1", [vt_nbytes(3, 1)])                          # py=32
    lrow("dsp_vt_b_3_2", [vt_nbytes(3, 2)])                          # py=40
    lrow("dsp_vt_b_2_2", [vt_nbytes(2, 2)])                          # py=32
    lrow("dsp_vt_b_1_1", [vt_nbytes(1, 1)])                          # py=16
    lrow("dsp_vt_b_0_0", [vt_nbytes(0, 0)])                          # py=0
    lrow("dsp_vt_s_3_2", [vt_nslots(3, 2)])                          # py=5
    lrow("dsp_vt_s_0_0", [vt_nslots(0, 0)])                          # py=0
    # :67 pack_into('i', mv, i*8, b.size)
    lrow("dsp_vt_ix_0", [vt_size_byte(0)])                          # py=0
    lrow("dsp_vt_ix_1", [vt_size_byte(1)])                          # py=8
    lrow("dsp_vt_ix_2", [vt_size_byte(2)])                          # py=16
    lrow("dsp_vt_lo_4", [Slot.lo(vt_size_at(0, 4))])                 # py=4
    lrow("dsp_vt_hi_4", [Slot.hi(vt_size_at(0, 4))])                 # py=0
    lrow("dsp_vt_lo_big", [Slot.lo(vt_size_at(0, 4294967295))])      # py=4294967295
    lrow("dsp_vt_hi_big", [Slot.hi(vt_size_at(0, 4294967295))])      # py=0
    lrow("dsp_vt_sz_nbytes", [Slot.nbytes(vt_size_at(0, 4))])            # py=8
    # :68 pack_into(dt.fmt, mv, (nbufs+j)*8, v) -- the offset is NOT j*8
    lrow("dsp_vt_vox_3_0", [vt_val_offset(3, 0)])                    # py=24
    lrow("dsp_vt_vox_3_1", [vt_val_offset(3, 1)])                    # py=32
    lrow("dsp_vt_vox_0_0", [vt_val_offset(0, 0)])                    # py=0
    lrow("dsp_vt_vox_1_0", [vt_val_offset(1, 0)])                    # py=8
    lrow("dsp_vt_vox_15_0", [vt_val_offset(15, 0)])                  # py=120
    # how many of the eight bytes a fmt writes
    row("dsp_vt_hi_q", vt_hi_of("long"))                             # py=True
    row("dsp_vt_hi_Q", vt_hi_of("unsigned long"))                    # py=True
    row("dsp_vt_hi_d", vt_hi_of("double"))                           # py=True
    row("dsp_vt_hi_i", Bool.not(vt_hi_of("int")))                    # py=True
    row("dsp_vt_hi_f", Bool.not(vt_hi_of("float")))                  # py=True
    row("dsp_vt_hi_e", Bool.not(vt_hi_of("half")))                   # py=True
    row("dsp_vt_hi_b", Bool.not(vt_hi_of("signed char")))            # py=True
    row("dsp_vt_hi_void", Bool.not(vt_hi_of("void")))                # py=True
    row("dsp_vt_lo_void", Bool.not(vt_lo_of("void")))                # py=True
    row("dsp_vt_lo_b", vt_lo_of("signed char"))                      # py=True
    row("dsp_vt_lo_weakint", vt_lo_of("weakint"))                    # py=True
    # the three buffers' own sizes -- `rpc_prep_args`'s ins + outs
    lrow("dsp_prog_pl_3_2", prog.pra_lens(3, 2))                     # py=40,12,8
    lrow("dsp_prog_pl_3_0", prog.pra_lens(3, 0))                     # py=24,12,8
    lrow("dsp_prog_pl_0_0", prog.pra_lens(0, 0))                     # py=0,0,8
    lrow("dsp_prog_pl_1_1", prog.pra_lens(1, 1))                     # py=16,4,8
    lrow("dsp_prog_pl_15_0", prog.pra_lens(15, 0))                   # py=120,60,8
    lrow("dsp_off_b_0", [off_nbytes(0)])                             # py=0
    lrow("dsp_off_b_1", [off_nbytes(1)])                             # py=4
    lrow("dsp_off_b_3", [off_nbytes(3)])                             # py=12
    lrow("dsp_off_b_15", [off_nbytes(15)])                           # py=60
    lrow("dsp_off_b_16", [off_nbytes(16)])                           # py=64

# --- 6: the program call, :62-71 ----------------------------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    urow("dsp_exec_sc_0", prog.exec_sc(0))                          # py=33685760
    urow("dsp_exec_sc_1", prog.exec_sc(1))                          # py=33685761
    urow("dsp_exec_sc_3", prog.exec_sc(3))                          # py=33685763
    urow("dsp_exec_sc_7", prog.exec_sc(7))                          # py=33685767
    urow("dsp_exec_sc_15", prog.exec_sc(15))                        # py=33685775
    urow("dsp_exec_sc_16", prog.exec_sc(16))                        # py=33685776
    lrow("dsp_exec_sc_f", [sc_fds(prog.exec_sc(7))])                 # py=7
    lrow("dsp_exec_sc_i", [sc_ins(prog.exec_sc(7))])                 # py=2
    lrow("dsp_exec_sc_o", [sc_outs(prog.exec_sc(7))])               # py=1
    lrow("dsp_exec_sc_m", [sc_method(prog.exec_sc(7))])             # py=2
    row("dsp_toomany_15", Bool.not(prog.too_many(15)))              # py=True
    row("dsp_toomany_16", prog.too_many(16))                        # py=True
    row("dsp_toomany_17", prog.too_many(17))                        # py=True
    # the trace for a legal call
    +ok : Tr <- IO.pure(Tr, prog.run(3, 2, Tr.of()))
    urow("dsp_call_ok_n", seen(ok))                                  # py=1
    urow("dsp_call_ok_sc", first(cargs(CALL_EXEC_LIB(), ok)))        # py=33685763
    row("dsp_call_ok_flag", Bool.not(Tr.refused(ok)))                # py=True
    # and for a refused one: :63 raises BEFORE the call, so nothing is recorded
    +no : Tr <- IO.pure(Tr, prog.run(16, 0, Tr.of()))
    urow("dsp_call_16_n", seen(no))                                  # py=0
    row("dsp_call_16_refused", Tr.refused(no))                      # py=True
    # and a refusal BLOCKS everything after it, so a legal call behind a refused
    # one records nothing. :63's raise is not a flag, it is the end of the program.
    +blk : Tr <- IO.pure(Tr, prog.run(1, 0, prog.run(16, 0, Tr.of())))
    urow("dsp_call_blocked_n", seen(blk))                            # py=0
    row("dsp_call_blocked_flag", Tr.refused(blk))                    # py=True
    # :71 and :292 -- two programs, TWO SCALES
    lrow("dsp_scale_real", [prog.scale_micros()])                   # py=1000000
    lrow("dsp_scale_mock", [mprog.scale_ins()])                     # py=1000000000
    lrow("dsp_scale_gap", [U32.sub(mprog.scale_ins(), prog.scale_micros())])  # py=999000000
    lrow("dsp_timer_b", [TIMER_BYTES()])                             # py=8
    # and a refused call AFTER a legal one leaves the earlier call intact
    +mix : Tr <- IO.pure(Tr, prog.run(16, 0, prog.run(1, 0, Tr.of())))
    urow("dsp_call_mix_n", seen(mix))                                # py=1
    urow("dsp_call_mix_sc", first(cargs(CALL_EXEC_LIB(), mix)))      # py=33685761

# --- 7: the entry shim, :27-44 -----------------------------------------------
def t_entry() -> IO(Unit):
  do IO<Unit>:
    srow("dsp_e_h0", entry.head0())
      # py=int entry(unsigned long long handle, unsigned int sc, remote_arg* pra) {
    srow("dsp_e_h2", entry.head2())                    # py=HAP_power_set((void*)handle, (void*)&req);
    srow("dsp_e_guard", entry.guard())                # py=if ((sc>>24) != 2) return 0;
    srow("dsp_e_topen", entry.timer_open())
      # py=unsigned long long start = HAP_perf_get_time_us();
    srow("dsp_e_tclose", entry.timer_close())
      # py=*(unsigned long long *)(pra[2].buf.pv) = HAP_perf_get_time_us() - start;
    srow("dsp_e_ret", entry.ret())                     # py=return 0; }
    # :32-33 the sz_or_val line. A GLOBAL is `int` at i*8 whatever its dtype.
    srow("dsp_e_sz_g0", entry.sz_decl(0, fx.g("float", 4)))
      # py=int sz_or_val_0 = *(int*)((char*)pra[0].buf.pv+0);
    srow("dsp_e_sz_g1", entry.sz_decl(1, fx.g("float", 4)))
      # py=int sz_or_val_1 = *(int*)((char*)pra[0].buf.pv+8);
    srow("dsp_e_sz_g2", entry.sz_decl(2, fx.g("unsigned int", 1)))
      # py=int sz_or_val_2 = *(int*)((char*)pra[0].buf.pv+16);
    srow("dsp_e_sz_g3", entry.sz_decl(3, fx.g("unsigned long", 1)))
      # py=int sz_or_val_3 = *(int*)((char*)pra[0].buf.pv+24);
    # and an ALU is `_render_dtype`, at the SAME i*8 slot
    srow("dsp_e_sz_a0", entry.sz_decl(0, fx.a("unsigned int", 1)))
      # py=unsigned int sz_or_val_0 = *(unsigned int*)((char*)pra[0].buf.pv+0);
    srow("dsp_e_sz_a1", entry.sz_decl(1, fx.a("float", 1)))
      # py=float sz_or_val_1 = *(float*)((char*)pra[0].buf.pv+8);
    srow("dsp_e_sz_a2", entry.sz_decl(2, fx.a("int", 1)))
      # py=int sz_or_val_2 = *(int*)((char*)pra[0].buf.pv+16);
    srow("dsp_e_sz_a3", entry.sz_decl(3, fx.a("int", 1)))
      # py=int sz_or_val_3 = *(int*)((char*)pra[0].buf.pv+24);
    # :35 the off line
    srow("dsp_e_off0", entry.off(0))                   # py=int off0 = ((int*)pra[1].buf.pv)[0];
    srow("dsp_e_off1", entry.off(1))                   # py=int off1 = ((int*)pra[1].buf.pv)[1];
    srow("dsp_e_off2", entry.off(2))                   # py=int off2 = ((int*)pra[1].buf.pv)[2];
    # :36-37 the mmap line and the dma slot `i+3`
    srow("dsp_e_mm0", entry.mmap(0))
      # py=void *buf_0 = HAP_mmap(0,sz_or_val_0,3,0,pra[3].dma.fd,0)+off0;
    srow("dsp_e_mm1", entry.mmap(1))
      # py=void *buf_1 = HAP_mmap(0,sz_or_val_1,3,0,pra[4].dma.fd,0)+off1;
    srow("dsp_e_mm2", entry.mmap(2))
      # py=void *buf_2 = HAP_mmap(0,sz_or_val_2,3,0,pra[5].dma.fd,0)+off2;
    lrow("dsp_e_dma_0", [entry.dma_slot(0)])           # py=3
    lrow("dsp_e_dma_2", [entry.dma_slot(2)])           # py=5
    lrow("dsp_e_dma_4", [entry.dma_slot(4)])           # py=7
    lrow("dsp_e_dma_n", [U32.sub(entry.dma_slot(0), U32.add(prog.nins(), prog.nouts()))])  # py=0
    # :42 the munmap line
    srow("dsp_e_un0", entry.munmap(0))                 # py=HAP_munmap(buf_0, sz_or_val_0);
    srow("dsp_e_un2", entry.munmap(2))                 # py=HAP_munmap(buf_2, sz_or_val_2);
    # :39,:40 the kernel-call argument
    srow("dsp_e_arg_g0", entry.arg_name(0, fx.g("float", 4)))   # py=buf_0
    srow("dsp_e_arg_g1", entry.arg_name(1, fx.g("float", 4)))   # py=buf_1
    srow("dsp_e_arg_a0", entry.arg_name(0, fx.a("unsigned int", 1)))  # py=sz_or_val_0
    srow("dsp_e_arg_a1", entry.arg_name(1, fx.a("float", 1)))        # py=sz_or_val_1
    # THE agga FIXTURE -- ALU, GLOBAL, GLOBAL, ALU. The index is the PARAM index.
    srow("dsp_e_ag_off1", entry.off(1))                # py=int off1 = ((int*)pra[1].buf.pv)[1];
    srow("dsp_e_ag_mm1", entry.mmap(1))
      # py=void *buf_1 = HAP_mmap(0,sz_or_val_1,3,0,pra[4].dma.fd,0)+off1;
    srow("dsp_e_ag_mm2", entry.mmap(2))
      # py=void *buf_2 = HAP_mmap(0,sz_or_val_2,3,0,pra[5].dma.fd,0)+off2;
    srow("dsp_e_ag_arg0", entry.arg_name(0, fx.a("unsigned int", 1)))  # py=sz_or_val_0
    srow("dsp_e_ag_arg3", entry.arg_name(3, fx.a("int", 1)))            # py=sz_or_val_3
    # the LINE COUNTS. One GLOBAL fixture is 4 + 1 + 2 + 4 + 1 = 12, which is what
    # CPython's eight msrc entries produce. agga is 4 + 4 + 4 + 4 + 2 = 18.
    urow("dsp_e_lines_g1", entry.line_count(fx.g1()))  # py=12
    urow("dsp_e_lines_g2", entry.line_count(fx.g2()))                    # py=16
    urow("dsp_e_lines_g0", entry.line_count(Nil{}))                       # py=8
    urow("dsp_e_lines_agga", entry.line_count(fx.agga()))                 # py=18
    urow("dsp_e_lines_a1", entry.line_count(fx.a1()))                    # py=9
    urow("dsp_e_lines_a2", entry.line_count(fx.a2()))                    # py=10
    urow("dsp_e_lines_gag", entry.line_count(fx.ga1()))                    # py=17
    urow("dsp_e_nfixed", ENTRY_FIXED())                                   # py=4
    urow("dsp_e_ntail", ENTRY_TAIL())                                     # py=4
    urow("dsp_e_nsz_agga", entry.count_sz_of(fx.agga()))                  # py=4
    urow("dsp_e_noff_agga", entry.count_off(fx.agga()))                   # py=2
    urow("dsp_e_nmmap_agga", entry.count_mmap(fx.agga()))                 # py=2
    urow("dsp_e_nalu_agga", entry.count_alu(fx.agga()))                   # py=2
    urow("dsp_e_noff_g2", entry.count_off(fx.g2()))                      # py=2
    urow("dsp_e_noff_a2", entry.count_off(fx.a2()))                     # py=0

# --- 8: the mock shim, :256-274 ----------------------------------------------
def t_mock() -> IO(Unit):
  do IO<Unit>:
    srow("dsp_m_start", mrender.start())               # py=void _start(void) {
    srow("dsp_m_stamp", mrender.stamp())               # py=unsigned int st = inscount();
    srow("dsp_m_finish", mrender.finish())
      # py=unsigned int et = inscount() - st; write(1, &et, sizeof(et));
    srow("dsp_m_exit", mrender.exit())                 # py=exit(0); }
    # :264 the mmap2 + read loop
    srow("dsp_m_mm0", mrender.mmap(0, 4))
      # py=void *buf0 = mmap2(0, 4, 3, 0x21, -1, 0); for(int rd = 0; rd < 4; rd += read(0, buf0+rd, 4-rd));
    srow("dsp_m_mm1", mrender.mmap(1, 16))
      # py=void *buf1 = mmap2(0, 16, 3, 0x21, -1, 0); for(int rd = 0; rd < 16; rd += read(0, buf1+rd, 16-rd));
    srow("dsp_m_mm2", mrender.mmap(2, 8))
      # py=void *buf2 = mmap2(0, 8, 3, 0x21, -1, 0); for(int rd = 0; rd < 8; rd += read(0, buf2+rd, 8-rd));
    # :266 the val read -- the dtype's OWN name and the ITEMSIZE as the length
    srow("dsp_m_v0", mrender.val(0, fx.a("unsigned int", 1)))
      # py=unsigned int val0; read(0, &val0, 4);
    srow("dsp_m_v1", mrender.val(1, fx.a("float", 1)))     # py=float val1; read(0, &val1, 4);
    srow("dsp_m_v2", mrender.val(2, fx.a("int", 1)))       # py=int val2; read(0, &val2, 4);
    srow("dsp_m_v3", mrender.val(3, fx.a("int", 1)))       # py=int val3; read(0, &val3, 4);
    srow("dsp_m_v4", mrender.val(4, fx.a("long", 1)))      # py=long long val4; read(0, &val4, 8);
    srow("dsp_m_v5", mrender.val(5, fx.a("half", 1)))      # py=__fp16 val5; read(0, &val5, 2);
    srow("dsp_m_v6", mrender.val(6, fx.a("signed char", 1)))  # py=signed char val6; read(0, &val6, 1);
    # :268 the (void*) cast the real shim does not need
    srow("dsp_m_ag0", mrender.arg_name(0, fx.g("float", 4)))     # py=(void*)buf0
    srow("dsp_m_ag1", mrender.arg_name(1, fx.g("float", 4)))     # py=(void*)buf1
    srow("dsp_m_aa0", mrender.arg_name(0, fx.a("unsigned int", 1)))  # py=val0
    srow("dsp_m_ag2", mrender.arg_name(2, fx.a("float", 1)))         # py=val2
    # :272 the output write
    srow("dsp_m_w0", mrender.emit(0, 4))                  # py=write(1, buf0, 4);
    srow("dsp_m_w1", mrender.emit(1, 16))                 # py=write(1, buf1, 16);
    # :262 the byte count is max_numel*itemsize, NOT the allocated size
    lrow("dsp_m_nb_u32_1", [mrender.nbytes(fx.g("unsigned int", 1))])  # py=4
    lrow("dsp_m_nb_f32_4", [mrender.nbytes(fx.g("float", 4))])         # py=16
    lrow("dsp_m_nb_f32_2", [mrender.nbytes(fx.g("float", 2))])         # py=8
    lrow("dsp_m_nb_f64_2", [mrender.nbytes(fx.g("double", 2))])        # py=16
    lrow("dsp_m_nb_f16_3", [mrender.nbytes(fx.g("half", 3))])          # py=6
    lrow("dsp_m_nb_u8_7", [mrender.nbytes(fx.g("unsigned char", 7))])  # py=7
    lrow("dsp_m_nb_i64_1", [mrender.nbytes(fx.g("long", 1))])          # py=8
    lrow("dsp_m_nb_bf16_2", [mrender.nbytes(fx.g("__bf16", 2))])       # py=4
    # the gpages syscall numbers, named at :257
    lrow("dsp_m_sys", [SYSCALL_READ(), SYSCALL_WRITE(), SYSCALL_EXIT(),
                       SYSCALL_MMAP2(), HEX_REG_QEMU_INSN_CNT(),
                       INSN_CNT_WORD(), MOCK_MMAP_FLAGS(), MMAP_PROT()])
    # py=63,64,93,222,21,1784217600,33,3
    lrow("dsp_m_boiler", [boiler_lines(), boiler_first_len()])  # py=9,65
    lrow("dsp_m_boiler_has_syscall", [u32_of_str(mockdsp_boilerplate(), "syscall")])  # py=1
    lrow("dsp_m_boiler_has_read", [u32_of_str(mockdsp_boilerplate(), "read")])        # py=1
    lrow("dsp_m_boiler_has_write", [u32_of_str(mockdsp_boilerplate(), "write")])      # py=1
    lrow("dsp_m_boiler_has_exit", [u32_of_str(mockdsp_boilerplate(), "exit")])        # py=1
    lrow("dsp_m_boiler_has_mmap2", [u32_of_str(mockdsp_boilerplate(), "mmap2")])      # py=1
    lrow("dsp_m_boiler_has_inscount", [u32_of_str(mockdsp_boilerplate(), "inscount")])  # py=1


# --- 9: the allocator, :73-96 -------------------------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # :96 offsets ACCUMULATE. BOTH fields, and the second is the load-bearing one.
    +b0 : DspBuf <- IO.pure(DspBuf, buf.of(0, 4096, 1024, 7, 9, True{}))
    +b1 : DspBuf <- IO.pure(DspBuf, alloc.offset(b0, 256, 64))
    urow("dsp_acc_off0", buf.offset(b0))                  # py=0
    urow("dsp_acc_off1", buf.offset(b1))                  # py=64
    urow("dsp_acc_va1", buf.va(b1))                       # py=4160
    urow("dsp_acc_sz1", buf.size(b1))                     # py=256
    urow("dsp_acc_fd1", buf.share_fd(b1))                 # py=7
    urow("dsp_acc_hdl1", buf.share_handle(b1))            # py=9
    urow("dsp_acc_id1", buf.id(b1))                       # py=0
    urow("dsp_acc_n1", buf.nbytes(b1))                    # py=256
    row("dsp_acc_share1", buf.has_share(b1))              # py=True
    # a SECOND view accumulates on the FIRST -- the only row that can see a
    # dropped `buf.offset+`.
    +b2 : DspBuf <- IO.pure(DspBuf, alloc.offset(b1, 128, 16))
    urow("dsp_acc_off2", buf.offset(b2))                  # py=80
    urow("dsp_acc_va2", buf.va(b2))                       # py=4176
    urow("dsp_acc_sz2", buf.size(b2))                     # py=128
    urow("dsp_acc_hdl2", buf.share_handle(b2))            # py=9
    urow("dsp_acc_fd2", buf.share_fd(b2))                 # py=7
    row("dsp_acc_share2", buf.has_share(b2))              # py=True
    # and a third, to catch an accumulate that only works twice
    +b3 : DspBuf <- IO.pure(DspBuf, alloc.offset(b2, 64, 4))
    urow("dsp_acc_off3", buf.offset(b3))                  # py=84
    urow("dsp_acc_va3", buf.va(b3))                       # py=4180
    # the arithmetic on its own, so a bug is attributable
    lrow("dsp_acc_math", [alloc.offset.va(4096, 64), alloc.offset.acc(0, 64),
                          alloc.offset.acc(64, 16), alloc.offset.acc(80, 4)])
    # py=4160,64,80,84
    lrow("dsp_acc_math0", [alloc.offset.va(0, 0), alloc.offset.acc(0, 0)])  # py=0,0
    # the MOCK arm has NO share and a view of it stays share-less
    +m0 : DspBuf <- IO.pure(DspBuf, buf.of(0, 0, 1024, 0, 0, False{}))
    +m1 : DspBuf <- IO.pure(DspBuf, alloc.offset(m0, 256, 64))
    row("dsp_acc_mshare", Bool.not(buf.has_share(m1)))    # py=True
    urow("dsp_acc_moff", buf.offset(m1))                  # py=64
    # :81 ION's align and heap mask
    lrow("dsp_ion", [ION_ALIGN(), ion.heap_id_mask(), ION_FLAG_CACHED(),
                     U32.from_nat(ION_SYSTEM_HEAP_ID()), ION_FLAG_CACHED()])
    # py=512,1,1,0,1
    lrow("dsp_ion_a", [ion.aligned(1), ion.aligned(511), ion.aligned(512),
                       ion.aligned(513), ion.aligned(1024)])
    # py=512,512,512,1024,1024
    # :135 the ROUNDED size is allocated and the RAW size is copied
    lrow("dsp_shell_sz", [dev.shell_size(0), dev.shell_size(1),
                          dev.shell_size(4095), dev.shell_size(4096),
                          dev.shell_size(4097), dev.shell_size(4660)])
    # py=0,4096,4096,4096,8192,8192
    lrow("dsp_mmap", [MMAP_PROT(), alloc.mock_flags(), alloc.real_flags()])  # py=3,33,1
    # the free order, and the MOCK negative case for each of its three calls
    +fr : Tr <- IO.pure(Tr, alloc.free(True{}, 1024, 9, Tr.of()))
    urow("dsp_free_r_n", seen(fr))                        # py=3
    urow("dsp_free_r_hdl", first(cargs(CALL_ION_FREE(), fr)))             # py=9
    urow("dsp_free_r_mm", first(cargs(CALL_MMAP(), fr)))                  # py=1024
    row("dsp_free_r_order", seq(fr, [Call{CALL_MMAP, 1024},
      Call{CALL_OS_CLOSE, FD_NONE()}, Call{CALL_ION_FREE, 9}]))            # py=True
    row("dsp_free_r_rev", Bool.not(seq(fr, [Call{CALL_ION_FREE, 9},
      Call{CALL_MMAP, 1024}])))                                           # py=True
    +fm : Tr <- IO.pure(Tr, alloc.free(False{}, 1024, 9, Tr.of()))
    urow("dsp_free_m_n", seen(fm))                        # py=1
    urow("dsp_free_m_ionfree", ncalls(CALL_ION_FREE(), fm))   # py=0
    urow("dsp_free_m_close", ncalls(CALL_OS_CLOSE(), fm))     # py=0
    urow("dsp_free_m_mmap", ncalls(CALL_MMAP(), fm))         # py=1
    urow("dsp_free_m_mm", first(cargs(CALL_MMAP(), fm)))     # py=1024
    # the copy arms: src.nbytes in, dest.nbytes out -- ASYMMETRIC
    lrow("dsp_copy", [alloc.copyin_bytes(64), alloc.copyout_bytes(32),
                      alloc.copyin_bytes(0), alloc.copyout_bytes(4294967295)])
    # py=64,32,0,4294967295
    urow("dsp_asbuf", alloc.as_buffer_bytes(b0))          # py=1024
    # the alloc arms: THREE calls real, ONE mock
    +ar : Made <- IO.pure(Made, alloc.alloc(1024, False{}, Tr.of()))
    urow("dsp_alloc_r_n", seen(Made.tr(ar)))              # py=3
    urow("dsp_alloc_r_sz", first(cargs(CALL_ION_ALLOC(), Made.tr(ar))))     # py=1024
    urow("dsp_alloc_r_mm", first(cargs(CALL_MMAP(), Made.tr(ar))))          # py=1024
    urow("dsp_alloc_r_share", first(cargs(CALL_ION_SHARE(), Made.tr(ar))))  # py=1
    urow("dsp_alloc_r_size", buf.size(Made.buf(ar)))      # py=1024
    urow("dsp_alloc_r_id", buf.id(Made.buf(ar)))          # py=0
    row("dsp_alloc_r_hasshare", buf.has_share(Made.buf(ar)))               # py=True
    row("dsp_alloc_r_order", seq(Made.tr(ar), [Call{CALL_ION_ALLOC, 1024},
      Call{CALL_ION_SHARE, 1}, Call{CALL_MMAP, 1024}]))                    # py=True
    +am : Made <- IO.pure(Made, alloc.alloc(1024, True{}, Tr.of()))
    urow("dsp_alloc_m_n", seen(Made.tr(am)))              # py=1
    urow("dsp_alloc_m_ionalloc", ncalls(CALL_ION_ALLOC(), Made.tr(am)))    # py=0
    urow("dsp_alloc_m_ionshare", ncalls(CALL_ION_SHARE(), Made.tr(am)))    # py=0
    urow("dsp_alloc_m_mm", first(cargs(CALL_MMAP(), Made.tr(am))))        # py=1024
    urow("dsp_alloc_m_size", buf.size(Made.buf(am)))      # py=1024
    urow("dsp_alloc_m_id", buf.id(Made.buf(am)))          # py=0
    row("dsp_alloc_m_noshare", Bool.not(buf.has_share(Made.buf(am))))     # py=True

# --- 10: the eviction policy, device.py:280 CONSUMED --------------------------
# THE NEGATIVE CASE. ops_dsp.py:135 allocates the fastrpc shell with
# `BufferSpec(nolru=True)`, so this file's OWN code has a buffer that must NOT be
# recycled, one row family away from an ordinary buffer that must. Same size,
# opposite answers.
def t_evict() -> IO(Unit):
  do IO<Unit>:
    row("dsp_recycle_plain", D.recycled(True{}, True{}, fx.spec(False{}, False{})))  # py=True
    row("dsp_norecycle_nolru", Bool.not(D.recycled(True{}, True{}, dev.shell_spec())))  # py=True
    row("dsp_norecycle_glru", Bool.not(D.recycled(False{}, True{}, fx.spec(False{}, False{}))))  # py=True
    row("dsp_norecycle_lru", Bool.not(D.recycled(True{}, False{}, fx.spec(False{}, False{}))))  # py=True
    row("dsp_norecycle_ext", Bool.not(D.recycled(True{}, True{}, fx.spec(False{}, True{}))))   # py=True
    # the shell's spec is the negative one: nolru and NOTHING else true, so a spec
    # built wrong is visible even though `recycled` only reads two of the five
    row("dsp_shell_nolru", dev.shell_spec.nolru(dev.shell_spec()))     # py=True
    row("dsp_shell_plain", dev.shell_spec.plain(dev.shell_spec()))     # py=True
    row("dsp_plain_nolru", Bool.not(dev.shell_spec.nolru(fx.spec(False{}, False{}))))  # py=True
    # the policy itself, at a BOOL per row so a mutation names one conjunct
    lrow("dsp_recycle_matrix", [Bool.to_u32(D.recycled(True{}, True{}, fx.spec(False{}, False{}))),
                                Bool.to_u32(D.recycled(True{}, True{}, fx.spec(True{}, False{}))),
                                Bool.to_u32(D.recycled(True{}, True{}, fx.spec(False{}, True{}))),
                                Bool.to_u32(D.recycled(False{}, True{}, fx.spec(False{}, False{}))),
                                Bool.to_u32(D.recycled(True{}, False{}, fx.spec(False{}, False{})))])
    # py=1,0,0,0,0
    # the shell buffer itself: allocated at the ROUNDED size and never recycled
    +sh : Made <- IO.pure(Made, alloc.alloc(dev.shell_size(4660), False{}, Tr.of()))
    urow("dsp_shell_alloc_n", seen(Made.tr(sh)))          # py=3
    urow("dsp_shell_alloc_size", buf.size(Made.buf(sh)))  # py=8192
    urow("dsp_shell_alloc_sz16", dev.shell_size(4096))     # py=4096
    urow("dsp_shell_copy_n", first(cargs(CALL_MEMMOVE(), dev.shell_copy(4660, Tr.of()))))  # py=4660
    urow("dsp_shell_recycled", Bool.to_u32(D.recycled(True{}, True{}, dev.shell_spec())))  # py=0
    # device.bend's own readers, consumed: LIFO take and the free_cache drain
    lrow("dsp_take", [D.alloc_take(Nil{}), D.alloc_take([11]),
                       D.alloc_take([11, 22]), D.alloc_take([11, 22, 33])])  # py=0,11,22,33
    lrow("dsp_freed", [D.freed(Nil{}, 0), D.freed([1], 0), D.freed([1, 2, 3], 0)])  # py=0,1,3

# --- 11: the compiler, :98-125 -------------------------------------------------
def t_compiler() -> IO(Unit):
  do IO<Unit>:
    srow("dsp_args", COMPILER_ARGS())
      # py=--target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b
    srow("dsp_args_first_m", compiler_args_first(True{}))   # py=-static
    srow("dsp_args_first_r", compiler_args_first(False{}))  # py=-shared
    row("dsp_args_T_r", compiler_args_has_T(False{}))      # py=True
    row("dsp_args_T_m", Bool.not(compiler_args_has_T(True{})))  # py=True
    row("dsp_unlink_r", compiler.del_unlinks(False{}))      # py=True
    row("dsp_unlink_m", Bool.not(compiler.del_unlinks(True{})))  # py=True
    srow("dsp_ck_r", compiler.cachekey_of(False{}, True{}))  # py=compile_dsp
    srow("dsp_ck_m", compiler.cachekey_of(True{}, True{}))   # py=
    srow("dsp_ck_nc", compiler.cachekey_of(False{}, False{}))  # py=
    row("dsp_ck_on_r", compiler.cachekey_on(False{}, True{}))  # py=True
    row("dsp_ck_on_m", Bool.not(compiler.cachekey_on(True{}, True{})))  # py=True
    row("dsp_ck_on_nc", Bool.not(compiler.cachekey_on(False{}, False{})))  # py=True
    # device.py:340 -- a None cachekey OR a miss means compile
    row("dsp_nc_mock_hit", D.needs_compile(False{}, True{}))    # py=True
    row("dsp_nc_real_hit", Bool.not(D.needs_compile(True{}, True{})))  # py=True
    row("dsp_nc_real_miss", D.needs_compile(True{}, False{}))   # py=True
    # the fifteen sections
    urow("dsp_link_n", U32.from_nat(List.length(&2, String, link_sections())))  # py=15
    srow("dsp_link_0", link_section(0n))    # py=text
    srow("dsp_link_1", link_section(1n))    # py=rela.plt
    srow("dsp_link_7", link_section(7n))    # py=dynamic
    srow("dsp_link_9", link_section(9n))    # py=got.plt
    srow("dsp_link_13", link_section(13n))  # py=shstrtab
    srow("dsp_link_14", link_section(14n))  # py=strtab
    srow("dsp_link_line", link_line("text"))
      # py=.text : ALIGN(4096) { *(.text) }
    srow("dsp_link_line2", link_line("got.plt"))
      # py=.got.plt : ALIGN(4096) { *(.got.plt) }
    # and the WHOLE script, diffed as a string because String.concat drops a literal
    srow("dsp_link_script", link_script())
      # py=SECTIONS { . = 0x0; .text : ALIGN(4096) { *(.text) }
      #     ... /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }
    urow("dsp_link_align", LINK_ALIGN())  # py=4096
    # the command line, as a string function of mock and CC
    srow("dsp_cmd_m", compile_cmd(True{}, "clang"))
    srow("dsp_cmd_r", compile_cmd(False{}, "clang"))
    srow("dsp_cmd_cc", compile_cmd(True{}, "gcc"))
    row("dsp_cmd_cc_used", Bool.not(String.eq(compile_cmd(True{}, "gcc"),
      compile_cmd(True{}, CC_DEFAULT()))))  # py=True
    row("dsp_cmd_mock_used", Bool.not(String.eq(compile_cmd(True{}, "clang"),
      compile_cmd(False{}, "clang"))))  # py=True
    srow("dsp_suffix", BUFFER_SUFFIX())
      # py= restrict __attribute__((align_value(128)))
    srow("dsp_typedef", KERNEL_TYPEDEF())  # py=__attribute__((noinline)) void
    # :18 `self.target, self.compiler = target, DSPCompiler()` -- the renderer builds
    # the DSP compiler and NOT super().__init__, because the CPU clang compiler
    # raises on a hexagon arch. `dsp_no_super_init` is that measurement.
    row("dsp_no_super_init", dev.branch_same_alloc())  # py=True
    srow("dsp_dev_node_ion", DEV_ION())  # py=/dev/ion
    srow("dsp_dev_node_adsp", DEV_ADSP())  # py=/dev/adsprpc-smd
    srow("dsp_shell_path", SHELL_PATH())  # py=/dsp/cdsp/fastrpc_shell_3

# --- 12: the device init and the three lib calls, :128-176 --------------------
def t_device() -> IO(Unit):
  do IO<Unit>:
    row("dsp_mock_default", dev.is_mock())  # py=True
    # init_dsp with NO stale fd: FIVE calls, and the order IS the contract
    +f : Tr <- IO.pure(Tr, dev.init_dsp(False{}, Tr.of()))
    urow("dsp_init_n", seen(f))                              # py=5
    urow("dsp_init_first_k", first_k(Tr.calls(f)))           # py=6
    urow("dsp_init_last_k", last_k(Tr.calls(f)))             # py=10
    lrow("dsp_init_kinds", kind_list(Tr.calls(f)))           # py=6,7,8,9,10
    row("dsp_init_order", seq(f, [Call{CALL_ADSP_OPEN, 0},
      Call{CALL_RPC_GETINFO, 3}, Call{CALL_RPC_CONTROL, 3}, Call{CALL_RPC_INIT, 1},
      Call{CALL_RPC_INVOKE, SC_INIT_INVOKE}]))              # py=True
    row("dsp_init_rev", Bool.not(seq(f, [Call{CALL_RPC_CONTROL, 3},
      Call{CALL_RPC_GETINFO, 3}, Call{CALL_ADSP_OPEN, 0}])))  # py=True
    lrow("dsp_init_args", cargs(CALL_RPC_INVOKE(), f))       # py=50331648
    lrow("dsp_init_args3", cargs(CALL_RPC_GETINFO(), f))     # py=3
    lrow("dsp_init_args4", cargs(CALL_RPC_CONTROL(), f))     # py=3
    lrow("dsp_init_args5", cargs(CALL_RPC_INIT(), f))        # py=1
    # and WITH the stale fd: SEVEN, whose first TWO are the stale-fd close. The
    # five above are a SUFFIX of this one, which is why these rows exist.
    +g : Tr <- IO.pure(Tr, dev.init_dsp(True{}, Tr.of()))
    urow("dsp_init_ag_n", seen(g))                           # py=7
    urow("dsp_init_ag_first_k", first_k(Tr.calls(g)))        # py=10
    urow("dsp_init_ag_second_k", second_k(Tr.calls(g)))      # py=4
    lrow("dsp_init_ag_kinds", kind_list(Tr.calls(g)))        # py=10,4,6,7,8,9,10
    row("dsp_init_ag_order", seq(g, [Call{CALL_RPC_INVOKE, SC_STALE},
      Call{CALL_OS_CLOSE, 98}, Call{CALL_ADSP_OPEN, 0},
      Call{CALL_RPC_GETINFO, 3}, Call{CALL_RPC_CONTROL, 3}, Call{CALL_RPC_INIT, 1},
      Call{CALL_RPC_INVOKE, SC_INIT_INVOKE}]))               # py=True
    lrow("dsp_init_ag_invokes", cargs(CALL_RPC_INVOKE(), g))  # py=33554432,50331648
    lrow("dsp_init_ag_close", cargs(CALL_OS_CLOSE(), g))      # py=98
    # the two selectors
    lrow("dsp_sc_stale", [SC_STALE()])                        # py=33554432
    lrow("dsp_sc_initinv", [SC_INIT_INVOKE()])                # py=50331648
    # :146,:152 the open and close selectors
    lrow("dsp_ol_sc", [dev.open_lib_sc()])                    # py=131584
    lrow("dsp_cl_sc", [dev.close_lib_sc()])                   # py=16843264
    lrow("dsp_ol_f", [sc_method(dev.open_lib_sc()), sc_ins(dev.open_lib_sc()),
                      sc_outs(dev.open_lib_sc()), sc_fds(dev.open_lib_sc())])  # py=0,2,2,0
    lrow("dsp_cl_f", [sc_method(dev.close_lib_sc()), sc_ins(dev.close_lib_sc()),
                      sc_outs(dev.close_lib_sc()), sc_fds(dev.close_lib_sc())])  # py=1,1,2,0
    # :143,:145 the URL, its length INCLUDING the NUL, and the two outs
    srow("dsp_fp", OPEN_LIB_FP())
      # py=file:///tinylib?entry&_modver=1.0&_dom=cdsp
    lrow("dsp_fp_len", [OPEN_LIB_NAMED_LEN(), OPEN_LIB_NUL_LEN(), open_lib_len()])  # py=43,1,44
    lrow("dsp_ol_ins", [open_lib_len(), open_lib_ins1(), open_lib_out0(), open_lib_out1()])  # py=44,255,8,255
    # :147 the raise -- a negative status word in o1's SECOND i32
    row("dsp_ol_bad_neg", open_lib_bad(4294967295))          # py=True
    row("dsp_ol_bad_neg2", open_lib_bad(2147483648))       # py=True
    row("dsp_ol_bad_neg3", open_lib_bad(4294967294))  # py=True
    row("dsp_ol_bad_0", Bool.not(open_lib_bad(0)))           # py=True
    row("dsp_ol_bad_pos", Bool.not(open_lib_bad(100)))       # py=True
    row("dsp_ol_bad_maxpos", Bool.not(open_lib_bad(2147483647)))  # py=True
    srow("dsp_ol_err", open_lib_err("bad elf"))
      # py=RuntimeError: Cannot open lib: bad elf
        # the TRAILING SPACE is the point of this row and it is INVISIBLE in a diff
    srow("dsp_ol_err_empty", open_lib_err(""))
    # the handle, :148 -- the id the seam minted
    +oh : Tr <- IO.pure(Tr, dev.open_lib(Tr.of()))
    lrow("dsp_ol_handle", [dev.open_lib_handle(Tr.of()), Tr.next(oh)])  # py=0,1
    # exec_lib: open, invoke-attrs, close -- and the retry after init_dsp
    +e0 : Tr <- IO.pure(Tr, dev.exec_lib(prog.exec_sc(3), False{}, False{}, Tr.of()))
    urow("dsp_exec_n", seen(e0))                              # py=3
    lrow("dsp_exec_kinds", kind_list(Tr.calls(e0)))           # py=12,11,14
    row("dsp_exec_order", seq(e0, [Call{CALL_OPEN_LIB, 131584},
      Call{CALL_RPC_INVOKE_ATTRS, 33685763}, Call{CALL_CLOSE_LIB, 16843264}]))  # py=True
    row("dsp_exec_rev", Bool.not(seq(e0, [Call{CALL_CLOSE_LIB, 16843264},
      Call{CALL_RPC_INVOKE_ATTRS, 33685763}])))              # py=True
    lrow("dsp_exec_sc", cargs(CALL_RPC_INVOKE_ATTRS(), e0))   # py=33685763
    # the FIRST attempt fails: init_dsp's SEVEN, then a WHOLE new triple
    +e1 : Tr <- IO.pure(Tr, dev.exec_lib(prog.exec_sc(3), True{}, False{}, Tr.of()))
    urow("dsp_exec_retry_n", seen(e1))                        # py=11
    urow("dsp_exec_retry_open", ncalls(CALL_OPEN_LIB(), e1))  # py=2
    # the FAILED invoke is NOT recorded -- that is what "the call did not happen" means
    urow("dsp_exec_retry_invoke", ncalls(CALL_RPC_INVOKE_ATTRS(), e1))  # py=1
    urow("dsp_exec_retry_close", ncalls(CALL_CLOSE_LIB(), e1))  # py=1
    urow("dsp_exec_retry_inits", ncalls(CALL_RPC_INVOKE(), e1))  # py=2
    lrow("dsp_exec_retry_kinds", kind_list(Tr.calls(e1)))        # py=12,10,4,6,7,8,9,10,12,11,14
    # and BOTH fail: the retry's invoke is a TRUNCATED trace, so it contributes
    # its open and nothing else -- 7 + 1 = 8.
    +e2 : Tr <- IO.pure(Tr, dev.exec_lib(prog.exec_sc(3), True{}, True{}, Tr.of()))
    urow("dsp_exec_fail_n", seen(e2))                         # py=9
    urow("dsp_exec_fail_open", ncalls(CALL_OPEN_LIB(), e2))   # py=2
    urow("dsp_exec_fail_invoke", ncalls(CALL_RPC_INVOKE_ATTRS(), e2))  # py=0
    urow("dsp_exec_fail_close", ncalls(CALL_CLOSE_LIB(), e2))  # py=0
    row("dsp_exec_fail_tail", seq(e2, [Call{CALL_RPC_INVOKE_ATTRS, 33685763},
      Call{CALL_CLOSE_LIB, 16843264}]))                       # py=False
    lrow("dsp_exec_fail_kinds", kind_list(Tr.calls(e2)))      # py=12,10,4,6,7,8,9,10,12

# --- 13: the listener, :178-239 ----------------------------------------------
def t_rpc() -> IO(Unit):
  do IO<Unit>:
    lrow("dsp_rpc_greet", [RPC_GREET()])                            # py=67240448
    lrow("dsp_rpc_greet_f", [sc_method(RPC_GREET()), sc_ins(RPC_GREET()),
                             sc_outs(RPC_GREET()), sc_fds(RPC_GREET())])  # py=4,2,2,0
    row("dsp_rpc_greet_ne", Bool.not(RPC_GREET_IS_EXEC()))          # py=True
    lrow("dsp_rpc_greet_gap", [U32.sub(RPC_GREET(), rpc_sc(M_INVOKE(), 2, 1, 0))])  # py=33554688
    # the seven arms. The ORDER of the elif chain is not the numeric order.
    lrow("dsp_rpc_arms", rpc.arm_ids())                             # py=1,2,3,4,5,6,7
    urow("dsp_rpc_narms", U32.from_nat(List.length(&2, U32, rpc.arm_ids())))  # py=7
    lrow("dsp_rpc_a_hello", [rpc.arm(131584)])                      # py=1
    lrow("dsp_rpc_a_open", [rpc.arm(199229440)])                    # py=2
    lrow("dsp_rpc_a_close", [rpc.arm(50397184)])                    # py=3
    lrow("dsp_rpc_a_seek", [rpc.arm(151004672)])                    # py=4
    lrow("dsp_rpc_a_read", [rpc.arm(67125248)])                     # py=5
    lrow("dsp_rpc_a_stat", [rpc.arm(31195136)])                     # py=6
    lrow("dsp_rpc_a_mmap", [rpc.arm(33619968)])                     # py=7
    lrow("dsp_rpc_a_greet", [rpc.arm(RPC_GREET())])                 # py=0
    lrow("dsp_rpc_a_exec", [rpc.arm(prog.exec_sc(3))])              # py=0
    lrow("dsp_rpc_a_0", [rpc.arm(0)])                               # py=0
    lrow("dsp_rpc_a_1", [rpc.arm(1)])                               # py=0
    lrow("dsp_rpc_a_max", [rpc.arm(4294967295)])                    # py=0
    # the seven sc values, and the fact that two NON-arms are absent
    lrow("dsp_rpc_scs", [SC_HELLO(), SC_OPEN(), SC_CLOSE(), SC_SEEK(),
                         SC_READ(), SC_STAT(), SC_MMAP()])
    # py=131584,199229440,50397184,151004672,67125248,31195136,33619968
    # :185 the three initial values
    lrow("dsp_rpc_init", [RPC_CONTEXT(), RPC_STATUS_OK(),
                          RPC_STATUS_ERR(), H_TINYFD()])  # py=0,0,4294967295,65535
    # :186-188 the listener's OWN block: 2 ins of 0x10 and 2 outs of 0x10000
    lrow("dsp_rpc_lens", rpc.lens())  # py=16,65536,16,65536
    lrow("dsp_rpc_npq", [RPC_NINS(), RPC_NOUTS(),
                         pra_len(RPC_NINS(), RPC_NOUTS(), 0)])  # py=2,2,4
    lrow("dsp_rpc_outlen", [rpc.out_len_index(), rpc.out_len_zero()])  # py=1,0
    # :192 msg_send's four words -- the two that MOVE
    lrow("dsp_rpc_msg_ix", [rpc.msg_status_index(), rpc.msg_len_index(),
                            rpc.msg_inbytes_index()])  # py=1,2,3
    # :197 the reply's word 2 is the same selector layout
    lrow("dsp_rpc_reply_ix", [rpc.reply_context_index(), rpc.reply_sc_index()])  # py=0,2
    lrow("dsp_rpc_reply_io", [sc_ins(199229440), sc_outs(199229440),
                              sc_ins(67240448), sc_outs(67240448)])  # py=1,4,2,2
    # :201 round_up(ptr+4, 8) -- the padding is 0 or 4 and NEVER 8
    lrow("dsp_rpc_pad", [rpc.obj_pad(0), rpc.obj_pad(1), rpc.obj_pad(4),
                         rpc.obj_pad(5), rpc.obj_pad(8), rpc.obj_pad(12)])
    # py=8,7,4,3,8,4
    lrow("dsp_rpc_geom", [RPC_OBJ_ALIGN(), RPC_SIZE_BYTES(),
                          rpc.obj_count(1, 2), rpc.obj_count(0, 0),
                          rpc.obj_count(3, 3)])  # py=8,4,3,0,6
    # :221 the only assert -- SEEK_SET only, so SEEK_CUR and SEEK_END are refused
    row("dsp_rpc_seek_0", rpc.seek_ok(0))       # py=True
    row("dsp_rpc_seek_1", Bool.not(rpc.seek_ok(1)))  # py=True
    row("dsp_rpc_seek_2", Bool.not(rpc.seek_ok(2)))  # py=True
    srow("dsp_rpc_seek_err", rpc.seek_err(151004672))
      # py=AssertionError: Supported only SEEK_SET (sc=151004672)
    # :213 the greeting arm does NOTHING
    urow("dsp_rpc_hello_n", seen(rpc.hello(Tr.of())))  # py=0
    # :239 the unknown-op raise
    srow("dsp_rpc_unknown", rpc.unknown_err(255))
      # py=RuntimeError: Unknown op: sc=255
    srow("dsp_rpc_unknown0", rpc.unknown_err(0))
      # py=RuntimeError: Unknown op: sc=0
    # the arms' in/out argument counts, interleaved nin/nout
    lrow("dsp_rpc_cnt", rpc.cnts())
    # py=0,0,4,1,1,0,1,0,1,0,1,2,2,1,1,1

# --- 14: the mock program's wire format, :283-292 ---------------------------
def t_mprog() -> IO(Unit):
  do IO<Unit>:
    lrow("dsp_mp_in", [mprog.stdin_bytes(Nil{}), mprog.stdin_bytes(fx.bufs3()),
                       mprog.stdin_bytes([16]), mprog.stdin_bytes([16, 4]),
                       mprog.stdin_bytes(fx.offs3())])
    # py=0,6,16,20,192
    lrow("dsp_mp_nstdin", [mprog.nstdin(3, 0), mprog.nstdin(3, 2),
                           mprog.nstdin(0, 0)])  # py=6,22,0
    lrow("dsp_mp_out", [MPROG_HEAD(), mprog.stdout_len(0), mprog.stdout_len(6),
                        mprog.stdout_len(192)])  # py=4,4,10,196
    # the mock reuses the SAME dt.fmt table, so there is no second per-dtype family
    row("dsp_mp_shared_fmts", dt_has_fmt("int"))  # py=True
    # :291 `assert offset == len(proc.stdout)` -- the two sums agree or the mock
    # raises, and the offset starts at 4.
    lrow("dsp_mp_check", [MPROG_HEAD(), mprog.stdout_len(0)])  # py=4,4

# --- 15: the reader, and the matcher itself ----------------------------------
def t_reader() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, dev.init_dsp(True{}, Tr.of()))
    row("dsp_has_ok", seq(t, [Call{CALL_ADSP_OPEN, 0}, Call{CALL_RPC_GETINFO, 3}]))  # py=True
    row("dsp_has_rev", Bool.not(seq(t, [Call{CALL_RPC_GETINFO, 3},
      Call{CALL_ADSP_OPEN, 0}])))  # py=True
    row("dsp_has_absent", Bool.not(seq(t, [Call{CALL_ADSP_OPEN, 99}])))  # py=True
    row("dsp_has_wrongarg", Bool.not(seq(t, [Call{CALL_ADSP_OPEN, 0},
      Call{CALL_RPC_GETINFO, 99}])))  # py=True
    row("dsp_has_kind", seq(t, [Call{CALL_ADSP_OPEN, 0}]))  # py=True
    row("dsp_has_wrongkind", Bool.not(seq(t, [Call{CALL_MMAP, 0}])))  # py=True
    row("dsp_has_empty", seq(t, Nil{}))  # py=True
    # a pattern LONGER than the trace -- a matcher with the PATTERN's fuel says True
    row("dsp_has_long", Bool.not(seq(t, [Call{CALL_RPC_INVOKE, SC_STALE},
      Call{CALL_OS_CLOSE, 98}, Call{CALL_ADSP_OPEN, 0},
      Call{CALL_RPC_GETINFO, 3}, Call{CALL_RPC_CONTROL, 3}, Call{CALL_RPC_INIT, 1},
      Call{CALL_RPC_INVOKE, SC_INIT_INVOKE}, Call{CALL_RPC_INVOKE, SC_INIT_INVOKE}])))
    # and one on an EMPTY trace
    row("dsp_has_emptytr", Bool.not(seq(Tr.of(), [Call{CALL_ADSP_OPEN, 0}])))  # py=True
    # the trace reader itself
    urow("dsp_rd_n", seen(t))                                # py=7
    urow("dsp_rd_invoke", ncalls(CALL_RPC_INVOKE(), t))      # py=2
    urow("dsp_rd_init", ncalls(CALL_RPC_INIT(), t))          # py=1
    urow("dsp_rd_mmap", ncalls(CALL_MMAP(), t))              # py=0
    lrow("dsp_rd_invoke_args", cargs(CALL_RPC_INVOKE(), t))  # py=33554432,50331648
    lrow("dsp_rd_kinds", kind_list(Tr.calls(t)))              # py=10,4,6,7,8,9,10

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_rpcsc()
    b : Unit <- t_scfields()
    c : Unit <- t_dtypes()
    d : Unit <- t_pra()
    e : Unit <- t_varvals()
    f : Unit <- t_call()
    g : Unit <- t_entry()
    h : Unit <- t_mock()
    i : Unit <- t_alloc()
    j : Unit <- t_evict()
    k : Unit <- t_compiler()
    l : Unit <- t_device()
    m : Unit <- t_rpc()
    n : Unit <- t_mprog()
    o : Unit <- t_reader()
    IO.print("dsp-done=1")


# ===========================================================================
# THE MUTATION TABLE. Every number below is the HARNESS's output, not an estimate.
# `.agents/slop/dsp_mutate.py` applies ONE textual edit to a scratch copy of this
# file, runs the INTERPRETED lane, and diffs the whole `name=value` text -- a name-
# only diff calls every one of these zero, because most mutations change a VALUE.
# The useful column is "rows MOVED", because a mutation that moves nothing measures
# what this gate does NOT see.
#
# SIXTY-SEVEN mutations plus a comment-only control. SIXTY-FIVE move rows; SEVENTEEN
# move exactly one, and those are the LOCALISED rows -- the table is not one row per
# bug. The two zeros are M47 (an EQUIVALENCE, not a gap -- see BLIND SPOT 2) and the
# control.
#
# | # | rows moved | what it is testing |
# | --- | --- | --- |
# | M1 | 10 | :33's `sc>>24` -- the entry shim reads the METHOD byte. Off by one field. |
# | | | moved: dsp_cl_f, dsp_entry_ok_2, dsp_entry_ok_2b, dsp_exec_sc_m, dsp_ol_f, dsp_rpc_greet_f, dsp_sc_m255_only, dsp_scf_2210, dsp_scf_22115, dsp_scf_open |
# | M2 | 30 | :48's four one-byte fields -- outs placed at method's shift. |
# | M3 | 4 | THE BUG the first run found: :54's head and tail swapped. |
# | | | moved: dsp_attr_0220, dsp_attr_111, dsp_attr_22116, dsp_attr_2213 |
# | M4 | 2 | :56's `mv.nbytes > 0 else 0` -- the ZERO-LENGTH rule. |
# | | | moved: dsp_pra_pv_z, dsp_pra_pvset_0 |
# | M5 | 3 | the same rule, the other way -- a NEGATIVE case for M4. |
# | | | moved: dsp_pra_pv_2210v, dsp_pra_pv_z, dsp_pra_pvset_8 |
# | M6 | 11 | :70's `fds=len(bufs)` -- the selector is a function of ONE number. |
# | | | moved: dsp_call_mix_sc, dsp_call_ok_sc, dsp_exec_order, dsp_exec_sc, dsp_exec_sc_0, dsp_exec_sc_1, dsp_exec_sc_15, dsp_exec_sc_16, dsp_exec_sc_3, dsp_exec_sc_7, dsp_exec_sc_f |
# | M7 | 6 | :63's `len(bufs) >= 16` -- the refusal boundary itself. |
# | | | moved: dsp_call_16_n, dsp_call_16_refused, dsp_call_blocked_flag, dsp_call_blocked_n, dsp_call_mix_n, dsp_toomany_16 |
# | M8 | 4 | :68's `i*8` with `i` starting at `len(bufs)` -- the vals' BASE offset. |
# | | | moved: dsp_vt_vox_15_0, dsp_vt_vox_1_0, dsp_vt_vox_3_0, dsp_vt_vox_3_1 |
# | M9 | 2 | :67's 4-byte `pack_into('i', ...)` leaves the HIGH word UNTOUCHED, not sign-extended. |
# | | | moved: dsp_vt_hi_4, dsp_vt_hi_big |
# | M10 | 1 | dt.fmt for double -- `d` against `f`. One character, a wrong kernel. |
# | | | moved: dsp_fmt_double |
# | M11 | 1 | dt.fmt for int -- SIGNED against unsigned. The classic silent one. |
# | | | moved: dsp_fmt_int |
# | M12 | 4 | dt.itemsize for int64 -- 8 against 4. |
# | | | moved: dsp_isz_long, dsp_m_nb_i64_1, dsp_m_v4, dsp_vt_hi_q |
# | M13 | 2 | the four fp8 itemsize arms -- 1 byte each, and the bug this gate found. |
# | | | moved: dsp_isz_fp8, dsp_isz_fp8b |
# | M14 | 2 | :15's ADDED int64 key -- `long long` against `long`. |
# | | | moved: dsp_cn_long, dsp_m_v4 |
# | M15 | 7 | THE GLOBAL ARM of :32 -- a float buffer's SIZE must be spelled `int`. |
# | | | moved: dsp_cng_glob_f32, dsp_cng_glob_i64, dsp_cng_glob_u64, dsp_e_sz_g0, dsp_e_sz_g1, dsp_e_sz_g2, dsp_e_sz_g3 |
# | M16 | 1 | :46's `not bfloat16` -- the reason supported_dtypes exists at all. |
# | | | moved: dsp_sd_drop_bf16 |
# | M17 | 1 | :46's `d not in dtypes.fp8s` -- three of the four fp8 arms. |
# | | | moved: dsp_sd_drop_fp8b |
# | M18 | 9 | :37's `pra[i+3]` -- the two ins and one out ahead of the dma slots. |
# | | | moved: dsp_e_ag_mm1, dsp_e_ag_mm2, dsp_e_dma_0, dsp_e_dma_2, dsp_e_dma_4, dsp_e_dma_n, dsp_e_mm0, dsp_e_mm1, dsp_e_mm2 |
# | M19 | 8 | :33's `(char*)pra[0].buf.pv + i*8` -- the 8-BYTE slot stride. |
# | | | moved: dsp_e_sz_a1, dsp_e_sz_a2, dsp_e_sz_a3, dsp_e_sz_g1, dsp_e_sz_g2, dsp_e_sz_g3, dsp_vt_ix_1, dsp_vt_ix_2 |
# | M20 | 6 | the slot INDEX inside the sz_or_val line -- every param reading slot 0. |
# | | | moved: dsp_e_sz_a1, dsp_e_sz_a2, dsp_e_sz_a3, dsp_e_sz_g1, dsp_e_sz_g2, dsp_e_sz_g3 |
# | M21 | 4 | :96's `buf.va_addr + offset` -- the ADDRESS does not advance. |
# | | | moved: dsp_acc_math, dsp_acc_va1, dsp_acc_va2, dsp_acc_va3 |
# | M22 | 3 | :96's `buf.offset + offset` -- offsets ACCUMULATE. The silent one. |
# | | | moved: dsp_acc_math, dsp_acc_off2, dsp_acc_off3 |
# | M23 | 4 | the same claim, at the record -- a view of a view loses its parent's offset. |
# | | | moved: dsp_acc_moff, dsp_acc_off1, dsp_acc_off2, dsp_acc_off3 |
# | M24 | 3 | the SECOND BUG the gate found: the pattern binder shadowing `size`. |
# | | | moved: dsp_acc_n1, dsp_acc_sz1, dsp_acc_sz2 |
# | M25 | 2 | :88-91's free ORDER -- munmap before munmap-of-the-handle. |
# | | | moved: dsp_free_r_order, dsp_free_r_rev |
# | M26 | 1 | :81-83's alloc ORDER -- ION_ALLOC, ION_SHARE, then the mmap. |
# | | | moved: dsp_alloc_r_order |
# | M27 | 5 | THE THIRD BUG the gate found: :100's `-static` / `-shared` arms swapped. |
# | | | moved: dsp_args_first_m, dsp_args_first_r, dsp_cmd_cc, dsp_cmd_m, dsp_cmd_r |
# | M28 | 2 | :113's `None if mock else "compile_dsp"` -- the MOCK arm. |
# | | | moved: dsp_ck_m, dsp_ck_on_m |
# | M29 | 2 | :104's first section name. A dropped dot in a section list is a link failure. |
# | | | moved: dsp_link_0, dsp_link_script |
# | M30 | 3 | :106's ALIGN(4096) -- the NOTE at :103 says 4k is the fix. |
# | | | moved: dsp_link_line, dsp_link_line2, dsp_link_script |
# | M31 | 1 | the prepend that REVERSES the section order. Caught twice by the same row. |
# | | | moved: dsp_link_script |
# | M32 | 1 | the leading separator `str.join` would not have. |
# | | | moved: dsp_link_script |
# | M33 | 7 | :169 BEFORE :170 -- the stale INVOKE precedes the close. |
# | | | moved: dsp_exec_fail_kinds, dsp_exec_retry_kinds, dsp_init_ag_first_k, dsp_init_ag_kinds, dsp_init_ag_order, dsp_init_ag_second_k, dsp_rd_kinds |
# | M34 | 16 | :167's `if hasattr(self, 'rpc_fd')` -- the stale-fd path skipped entirely. |
# | | | moved: dsp_exec_fail_kinds, dsp_exec_fail_n, dsp_exec_retry_inits, dsp_exec_retry_kinds, dsp_exec_retry_n, dsp_init_ag_close, dsp_init_ag_first_k, dsp_init_ag_invokes, dsp_init_ag_kinds, dsp_init_ag_n, dsp_init_ag_order, dsp_init_ag_second_k, dsp_rd_invoke, dsp_rd_invoke_args, dsp_rd_kinds, dsp_rd_n |
# | M35 | 7 | :173 before :174 -- GETINFO and CONTROL swapped. |
# | | | moved: dsp_exec_fail_kinds, dsp_exec_retry_kinds, dsp_init_ag_kinds, dsp_init_ag_order, dsp_init_kinds, dsp_init_order, dsp_rd_kinds |
# | M36 | 6 | :159-164's retry -- a port that SKIPS the first attempt records ten, not eleven. |
# | | | moved: dsp_exec_fail_kinds, dsp_exec_fail_n, dsp_exec_fail_open, dsp_exec_retry_kinds, dsp_exec_retry_n, dsp_exec_retry_open |
# | M37 | 9 | THE RAISE, at the device-error site: a failed ioctl records its open AND its close. |
# | | | moved: dsp_exec_fail_close, dsp_exec_fail_invoke, dsp_exec_fail_kinds, dsp_exec_fail_n, dsp_exec_fail_tail, dsp_exec_retry_close, dsp_exec_retry_invoke, dsp_exec_retry_kinds, dsp_exec_retry_n |
# | M38 | 3 | THE RAISE, at :63 -- the refusal flag itself. Dropping it lets everything after run. |
# | | | moved: dsp_call_16_refused, dsp_call_blocked_flag, dsp_call_blocked_n |
# | M38b | 1 | THE RAISE inside `Tr.emit` -- the guard for a DEVICE error. See BLIND SPOT 1: it is not reachable yet. |
# | | | moved: dsp_call_blocked_n |
# | M39 | 4 | :147's SIGNED 32-bit test -- the port that reached for an unsigned compare. |
# | | | moved: dsp_ol_bad_0, dsp_ol_bad_neg, dsp_ol_bad_neg2, dsp_ol_bad_neg3 |
# | M40 | 4 | THE greeting LITERAL. Rewriting it as an rpc_sc call sends method 2 and the DSP never greets. |
# | | | moved: dsp_entry_no_4, dsp_rpc_greet, dsp_rpc_greet_f, dsp_rpc_greet_gap |
# | M41 | 1 | the elif chain's sc table -- one digit off in the OPEN arm. |
# | | | moved: dsp_rpc_a_open |
# | M42 | 2 | the chain's ORDER -- greeting first, open second. |
# | | | moved: dsp_rpc_arms, dsp_rpc_cnt |
# | M43 | 1 | :215's `in_args[3]` -- the name is the FOURTH in-arg of the open arm. |
# | | | moved: dsp_rpc_cnt |
# | M44 | 1 | :201's `round_up(ptr+4, 8)` -- the alignment is 8, not 4. |
# | | | moved: dsp_rpc_pad |
# | M45 | 2 | :221's SEEK_SET assert -- the only assert in the file. |
# | | | moved: dsp_rpc_seek_1, dsp_rpc_seek_2 |
# | M46 | 7 | :262's `max_numel()*itemsize` -- multiply, not add. |
# | | | moved: dsp_m_nb_f16_3, dsp_m_nb_f32_2, dsp_m_nb_f32_4, dsp_m_nb_f64_2, dsp_m_nb_i64_1, dsp_m_nb_u32_1, dsp_m_nb_u8_7 |
# | M47 | 0 | :266's `_render_dtype` -- the ALU arm of the GLOBAL helper would be right by luck here and wrong for a GLOBAL. |
# | M48 | 2 | :268's `val{i}` for an ALU -- the mock's bare-value spelling. |
# | | | moved: dsp_m_aa0, dsp_m_ag2 |
# | M49 | 2 | :71's /1e6 against :292's /1e9 -- two programs, two scales. |
# | | | moved: dsp_scale_gap, dsp_scale_real |
# | M50 | 2 | the same pair, the other way. |
# | | | moved: dsp_scale_gap, dsp_scale_mock |
# | M51 | 1 | the gpages syscall table at :257 -- read is 63. |
# | | | moved: dsp_m_sys |
# | M52 | 10 | THE MATCHER, with the ops_webgpu M23 bug: the fuel is the TRACE length but the answer ignores `at`. |
# | | | moved: dsp_exec_fail_tail, dsp_exec_rev, dsp_free_r_rev, dsp_has_absent, dsp_has_emptytr, dsp_has_long, dsp_has_rev, dsp_has_wrongarg, dsp_has_wrongkind, dsp_init_rev |
# | M53 | 9 | the matcher with the PATTERN length as fuel -- the other half of M23. |
# | | | moved: dsp_exec_fail_tail, dsp_exec_rev, dsp_free_r_rev, dsp_has_absent, dsp_has_long, dsp_has_rev, dsp_has_wrongarg, dsp_has_wrongkind, dsp_init_rev |
# | M54 | 5 | :32 emits one sz_or_val PER PARAM, ALU or not -- not per ALU. |
# | | | moved: dsp_e_lines_agga, dsp_e_lines_g1, dsp_e_lines_g2, dsp_e_lines_gag, dsp_e_nsz_agga |
# | M55 | 7 | :35 and :37 filter on `!= AddrSpace.GLOBAL`, so the count is the GLOBAL one. |
# | | | moved: dsp_e_lines_a1, dsp_e_lines_a2, dsp_e_lines_g1, dsp_e_lines_g2, dsp_e_lines_gag, dsp_e_noff_a2, dsp_e_noff_g2 |
# | M56 | 8 | the tail's four lines -- the LINE COUNT is the only row that sees a dropped one. |
# | | | moved: dsp_e_lines_a1, dsp_e_lines_a2, dsp_e_lines_agga, dsp_e_lines_g0, dsp_e_lines_g1, dsp_e_lines_g2, dsp_e_lines_gag, dsp_e_ntail |
# | M57 | 7 | :52's one array of len(ins)+len(outs)+len(in_fds) -- the fd slots count too. |
# | | | moved: dsp_pra_len_0220, dsp_pra_len_111, dsp_pra_len_112, dsp_pra_len_22115, dsp_pra_len_22116, dsp_pra_len_2213, dsp_pra_lens_eq |
# | M58 | 4 | :53's `-1` marker. |
# | | | moved: dsp_fds_111, dsp_fds_2210, dsp_fds_22116, dsp_fds_2213 |
# | M59 | 3 | :135's `BufferSpec(nolru=True)` -- THE EVICTION NEGATIVE CASE. Dropping it makes the shell recyclable. |
# | | | moved: dsp_norecycle_nolru, dsp_shell_nolru, dsp_shell_recycled |
# | M60 | 2 | :135's `round_up(nbytes, 0x1000)` -- the shell buffer's alignment. |
# | | | moved: dsp_shell_alloc_size, dsp_shell_sz |
# | M61 | 1 | :94's `src.nbytes` going in -- a view's window, not its buffer. |
# | | | moved: dsp_copy |
# | M62 | 1 | :129's ONE branch, which selects four things at once. |
# | | | moved: dsp_mock_default |
# | M63 | 1 | :257's `.word 0x6a15c000` -- the inscount instruction word. |
# | | | moved: dsp_m_sys |
# | M64 | 2 | :16's `code_for_op = {k:v for ... if k != Ops.SQRT}` -- ONE entry removed. |
# | | | moved: dsp_cfop_dsp, dsp_cfop_removed |
# | M65 | 1 | :197's `sc = msg_recv[2]` -- the selector is the reply's THIRD word. |
# | | | moved: dsp_rpc_reply_ix |
# | M66 | 1 | :192's `[context, status, ...]` -- status is the SECOND word. |
# | | | moved: dsp_rpc_msg_ix |
# | M99 | 0 | THE CONTROL: a comment-only edit. A table with no row that CANNOT move is a table of coincidences. |
#
# THE SIX REAL BUGS THIS GATE FOUND IN ITS OWN FIRST RUN, each of which a
# hand-typed expectation would have agreed with:
#
#   1. `attrs_of` wrote the DMA head and the BUF tail (M3, 4 rows). `List.append(a,
#      A, xs, ys)` is `xs ++ ys`, and :54's order is the other way round.
#   2. `dt_itemsize` had NO fp8 arm, so all four fp8s fell to the 100 default (M13).
#      MEASURED itemsize is 1. Found because the `py=` came from CPython.
#   3. `compiler_args_first` had `-static` and `-shared` the wrong way round (M27),
#      which builds a shared library when the mock asked for a static one.
#   4. `alloc.offset` kept the PARENT's size -- the record pattern's binder `size`
#      shadowed the parameter (M24). Found because CPython's `_offset` reports the
#      view's 256, not the buffer's 1024.
#   5. `open_lib_bad` used an unsigned compare for a SIGNED 32-bit test (M39), so
#      `-1` never refused.
#   6. `link_lines` emitted a LEADING separator and then, once fixed, the sections
#      in REVERSE (M31, M32). Found only because `dsp_link_script` diffs all
#      SEVENTEEN lines of the script against CPython's own string.
#
# WHAT THIS GATE STILL DOES NOT SEE, and it is a short list:
#
#   1. `Tr.emit`'s GUARD IS ALMOST UNREACHABLE. The port models a device error by
#      choosing a different arm in `exec_once` (:154-164's except), not by setting
#      the flag and letting the guard truncate -- so the guard fires only for the
#      ONE row `dsp_call_blocked_n` (M38b moves exactly that row). A real FFI seam
#      would need the counter version of `Tr.emit` that ops_webgpu.bend's `Tr.pop`
#      has, and this file does not have one. Reported rather than papered over.
#   2. M47 IS VACUOUS, NOT BLIND. `mrender.val` (:266) is only reachable for an ALU
#      param, so `dt_cname_global(is_alu=True, nm)` and `dt_cname(nm)` are the SAME
#      function over the gate's whole domain: an EQUIVALENCE, not a gap. Nothing
#      calls `mrender.val` on a GLOBAL because Python does not either.
#   3. THE ADDRESSES. `Pra.pv` is 0-or-nonzero and `DspBuf.va` is an opaque id,
#      because no address is reproducible. A packer that put the right NUMBER of
#      slots in the wrong ORDER would move `dsp_pra_*` only if it also moved a
#      length, a flag or an fd.
#   4. THE ARENA. device.bend's `Bn` -- the Buffer-as-a-SLOT model -- is CONSUMED
#      here (`recycled`, `alloc_take`, `freed`, `needs_compile`) and not
#      re-derived, so this file's view of a Buffer is `DspBuf` and cannot contradict
#      device.bend's. `dsp_acc_*` checks the view arithmetic; the slot arithmetic is
#      device.bend's business and is not in this gate.
#   5. THE C TEXT ITSELF. `dsp_e_*` and `dsp_m_*` diff the entry shim's LINES
#      against CPython's, and `dsp_link_script` diffs the whole link script, but the
#      KERNEL body -- cstyle.py's, not ops_dsp.py's -- is nowhere in this file, and
#      neither is `DSPRenderer._render_defines` beyond the five DSP lines.
#   6. `code_for_op`'s CONTENTS. `dsp_cfop_*` pins 18 against 17 and the one
#      removal; the seventeen entries are cstyle.py's and are restating them here
#      would be a second table to contradict, which is why ops_qcom.bend's qnn/htq
#      tables are untouched by this file (see WHAT ops_qcom.bend OWES).
#   7. `RPCListener`'s HOST SYSCALLS and its pointer walk. WALL 3. The sc dispatch,
#     the seven arms' argument counts, the 8-byte object alignment and the reply
#     field indices are gated; `os.open`, `os.read`, `os.lseek`, `os.stat`,
#     `os.close`, `FASTRPC_IOCTL_MMAP` and the `in_ptr` walk are not.
# ===========================================================================
