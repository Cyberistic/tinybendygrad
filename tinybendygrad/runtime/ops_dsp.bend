# tinybendygrad/runtime/ops_dsp.bend -- port of tinygrad/runtime/ops_dsp.py
#
# THE generic c-BACKEND-FOR-A-DSP wrapper. ops_dsp.py is 292 lines and almost none
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

# WHAT IS PORTED, DEF BY DEF.
#
#   :48  rpc_sc                 PORTED  `rpc_sc` + `sc_method/ins/outs/fds`
#   :49  rpc_prep_args          PORTED  `pra_len`, `pra_of` -- upstream builds the packed array in `rpc_prep_args`
#   :52  the fds array          PORTED  `fds_of` -- upstream builds the fd vector in `fds`
#   :53  the attrs array        PORTED  `attrs_of` -- upstream builds the attribute vector in `attrs`
#   :56    the pv/len fill      PORTED  `pra.put` -- the ZERO-LENGTH rule
#   :59  DSPProgram.__init__    PORTED  `prog.call`'s inputs (no state to keep)
#   :62  DSPProgram.__call__    PORTED  `prog.call`
#   :63    the buffer refusal   PORTED  `prog.too_many` + `Tr.refuse_now` -- upstream raises RuntimeError in `__call__`
#   :65-66  the three ins/outs  PORTED  `prog.nins`, `prog.nouts`, `prog.pra_lens`
#   :68  the size writes        PORTED  `vt_size_at`, `vt_size_byte` -- upstream packs each scalar with `struct.pack_into`
#   :68  the val writes         PORTED  `vt_val_offset`, `vt_hi_written` -- upstream packs each scalar with `struct.pack_into`
#   :69  the off_mv writes      PORTED  `off_nbytes` -- upstream fills the offset vector with `off_mv.cast`
#   :70  the exec_lib call      PORTED  `prog.exec_sc` -- upstream invokes the fastrpc ioctl in `__call__`
#   :71  the timer divide       PORTED  `prog.scale_micros` (the u64 read is WALL) -- upstream scales the timer in `__call__`
#   :73  DSPBuffer              PORTED  `DspBuf`, `buf.of`
#   :78  _alloc                 PORTED  `alloc.alloc` (MOCKDSP and real arms)
#   tinygrad/runtime/ops_dsp.py:79 the MOCKDSP arm    PORTED  `alloc.mock_flags` -- upstream's `MOCKDSP` arm symbol=_alloc
#   :81    the ION arm          PORTED  `ION_ALIGN`, `ion.aligned`
#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
#   tinygrad/runtime/ops_dsp.py:87-91 `_free`       PORTED  `alloc.free_calls` symbol=_free
#   tinygrad/runtime/ops_dsp.py:93 `_as_buffer`     PORTED  `alloc.as_buffer_bytes` symbol=_as_buffer
#   tinygrad/runtime/ops_dsp.py:94 `_copyin`        PORTED  `alloc.copyin_bytes` symbol=_copyin
#   tinygrad/runtime/ops_dsp.py:95 `_copyout`       PORTED  `alloc.copyout_bytes` symbol=_copyout
#   :96  _offset                PORTED  `alloc.offset` -- offsets ACCUMULATE
#   :100 DSPCompiler.args       PORTED  `COMPILER_ARGS`, `compiler_args_first`
#   :104-105 the fifteen sections PORTED `link_section`, `link_sections` -- upstream lists the sections in `__init__`
#   :106 the ALIGN(4096) lines  PORTED  `link_line`, `link_line.go`
#   :108 the whole script       PORTED  `link_script` -- upstream writes the SECTIONS script in `__init__`
#   :111 the -T flag            PORTED  `compiler_args_has_T` -- upstream adds the link script flag in `self.args`
#   tinygrad/runtime/ops_dsp.py:113 the cachekey    PORTED  `compiler.cachekey_of` -- upstream's `compile_dsp` key symbol=__init__
#   tinygrad/runtime/ops_dsp.py:115 `__del__`        PORTED  `compiler.del_unlinks` symbol=__del__
#   :118 compile                WALL 1  the clang spawn + the .so read-back
#   :125 disassemble            WALL 1  cpu_objdump / llvm-objdump
#   tinygrad/runtime/ops_dsp.py:129 `DSPDevice.__init__` PORTED  `dev.is_mock` (the ONE branch, tinygrad/runtime/ops_dsp.py:129-139) symbol=__init__
#   :132 the ion_fd open        PORTED  `dev.open_ion`
#   tinygrad/runtime/ops_dsp.py:134-136 the shell buffer PORTED  `dev.shell_size`, `dev.shell_copy` -- upstream's `shell_buf` symbol=__init__
#   tinygrad/runtime/ops_dsp.py:135 `BufferSpec(nolru=True)` PORTED  `dev.shell_spec` -- the eviction NEGATIVE symbol=__init__
#   :141 open_lib               PORTED  `dev.open_lib`, `dev.open_lib_sc`
#   :143 the tinylib URL        PORTED  `OPEN_LIB_FP`, `open_lib_len` -- upstream builds the `tinylib` URL there
#   :145 the two outs           PORTED  `open_lib_out0`, `open_lib_out1` -- upstream allocates the two out views in `open_lib`
#   :147 the raise              PORTED  `open_lib_bad`, `open_lib_err` -- upstream raises RuntimeError in `open_lib`
#   tinygrad/runtime/ops_dsp.py:141-148 `open_lib`   PORTED  `dev.open_lib_handle` -- the handle answer symbol=open_lib
#   :150 close_lib              PORTED  `dev.close_lib`, `dev.close_lib_sc`
#   :154-164 exec_lib           PORTED  `dev.exec_lib` -- open/invoke/close, retry
#   :166-176 init_dsp           PORTED  `dev.init_dsp` -- seven ordered calls
#   :167-170 the stale-fd close PORTED  the `have_fd` arm -- upstream closes a stale fastrpc fd in `init_dsp`
#   :178 RPCListener.__init__   PORTED  the three initial values
#   :186-188 the request block  PORTED  `rpc.lens`, `RPC_MSG_BYTES`
#   :192 msg_send               PORTED  `rpc.msg_*_index` -- upstream writes the request header in `run`
#   :194 the greeting literal   PORTED  `RPC_GREET` -- upstream invokes `FASTRPC_IOCTL_INVOKE` with the greeting `sc` in `run` -- the literal is 0x04020200
#   :197 the sc field split     PORTED  `sc_ins`, `sc_outs` -- upstream splits the sc word in `run`
#   :199-210 the object walk    PARTIAL `rpc.obj_pad`, `rpc.obj_count` (WALL 3) -- upstream walks the object list in `run`
#   :213-238 the seven arms     PORTIAL `rpc.arm` + each arm's in/out counts
#   :221 the SEEK_SET assert    PORTED  `rpc.seek_ok`, `rpc.seek_err` -- upstream asserts `APPS_STD_SEEK_SET` in `run`
#   :239 the unknown-op raise   PORTED  `rpc.unknown_err`, `ARM_NONE` -- upstream raises `RuntimeError` on an unknown op in `run`
#   :243 mockdsp_boilerplate    PORTED  `mockdsp_boilerplate`
#   :253 MockDSPRenderer        PORTED  `mrender.*` -- upstream defines the mock renderer class `MockDSPRenderer`
#   :255 its defines            PORTED  by the omission (clang only)
#   :262 max_numel*itemsize     PORTED  `mrender.nbytes`
#   :264 the mmap2/read loop    PORTED  `mrender.mmap`
#   :266 the val read           PORTED  `mrender.val`
#   :268 the (void*) cast       PORTED  `mrender.arg_name` -- upstream casts the buffer argument in `_render_entry`
#   :270 the inscount write     PORTED  `mrender.finish`
#   :272 the output write       PORTED  `mrender.emit`
#   :276-292 MockDSPProgram     PORTED  `mprog.stdin_bytes`, `mprog.stdout_len`, -- upstream runs the mock program `MockDSPProgram`
#                                             `mprog.scale_ins`
#

# THE WALLS.
#
# 1. THE COMPILER INVOCATION (:118-123). `system(f"{getenv('CC','clang')}
#    {self.args} -O2 -Wall -Werror -fno-stack-protector -x c -fPIC
#    -ffreestanding -nostdlib - -o {f.name}", input=src.encode())` and the
#    `pathlib.Path(f.name).read_bytes()` after it. `args` IS ported -- it is a
#    string function of `mock` -- and so is the whole command line, as
#    `compile_cmd`. The spawn and the byte buffer are not.
#    TODO(p3) runtime/ops_dsp.py:118  symbol=compile -- the clang spawn and the .so read-back.
#    TODO(p3) runtime/ops_dsp.py:125  symbol=disassemble -- cpu_objdump / llvm-objdump.
#
# 2. THE ION AND MMAP SYSCALLS (:81-83, :88, :132, :172). `os.open('/dev/ion')`,
#    `qcom_dsp.ION_IOC_ALLOC`, `libc.mmap`, `os.close('/dev/adsprpc-smd')`. Every
#    one is an ioctl on a Qualcomm node that does not exist off-device, and
#    `autogen/qcom_dsp.py` is generated ctypes bindings, so even on device these
#    are struct layouts. What is ported is the ORDER and the ONE integer each call
#    carries -- the size, the handle, the selector -- which is what the trace holds.
#    TODO(p3) runtime/ops_dsp.py:81  symbol=_alloc  -- ION_IOC_ALLOC / ION_IOC_SHARE.
#    TODO(p3) runtime/ops_dsp.py:83  symbol=_alloc  -- libc.mmap.
#    TODO(p3) runtime/ops_dsp.py:132  symbol=__init__ -- os.open('/dev/ion').
#    TODO(p3) runtime/ops_dsp.py:172  symbol=init_dsp -- os.open('/dev/adsprpc-smd').
#
# 3. THE RPCListener's HOST file system and its object walk (:199-238). The DSP
#    asks the HOST for these over the listener socket; this file implements
#    fastrpc's file system in python so the shell image can be paged in. The sc
#    DISPATCH TABLE, the seven arms' argument counts, the 8-byte object alignment
#    and the reply field indices are pure and ARE ported. The syscalls and the
#    pointer walk are not.
#    TODO(p3) runtime/ops_dsp.py:199  symbol=run -- the in_ptr/out_ptr walk over in_buf.
#    TODO(p3) runtime/ops_dsp.py:215  symbol=run -- os.open(name) for name != "tinylib".
#    TODO(p3) runtime/ops_dsp.py:218  symbol=run -- os.close(fd) for fd != TINYFD.
#    TODO(p3) runtime/ops_dsp.py:223  symbol=run -- os.lseek.
#    TODO(p3) runtime/ops_dsp.py:227 -- the TINYFD read out of `binded_lib`.
#    TODO(p3) runtime/ops_dsp.py:229  symbol=run -- os.read.
#    TODO(p3) runtime/ops_dsp.py:233  symbol=run -- os.stat and the apps_std_STAT fill.
#    TODO(p3) runtime/ops_dsp.py:237  symbol=run -- FASTRPC_IOCTL_MMAP.
#
# 4. THE u64 TIMER (:71 `timer[0] / 1e6`, :292 `struct.unpack("I", ...)/1e9`).
#    Bend has no 64-bit integer and no F64, so the DIVISOR is ported as the one
#    number the seam must agree on -- and the two programs have DIFFERENT ones,
#    1e6 against 1e9, which `dsp_scale_*` pins because a port that shared one
#    scale would move exactly one of the three rows.
#    TODO(p3) runtime/ops_dsp.py:71  symbol=__call__  -- the u64 read and the /1e6.
#    TODO(p3) runtime/ops_dsp.py:292  symbol=__call__ -- the u32 inscount read and the /1e9.
#
# THERE IS NO FOREIGN EFFECT IN THIS FILE. No `import "./x.c"`, no `-> IO(R)`. A
# template-following device records its calls in a `Tr` and declares nothing, which
# is the `ops_metal.bend` precedent and the reason that file prints no SOME PROOFS
# FAIL. `dtype.bend` is NOT imported: it is a conversion seam (`Dt.bf16`,
# `Dt.fp16`, ...) and importing it would drag that seam into this file for no gain
# -- ops_dsp.py needs no dtype conversion, only dtype NAMES.
#

# THE heart of it: FOUR pure functions of a dtype.
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
#                      itemsize 2, and `supported_dtypes` (tinygrad/runtime/ops_dsp.py:45 symbol=supported_dtypes) exists to keep it
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
#   `dt_cname_global`     (:32) the GLOBAL arm of the same line, and it is the -- upstream's `int` spelling for a GLOBAL size lives in `_render_entry`
#                      load-bearing asymmetry: a GLOBAL's `sz_or_val` is always
#                      spelled `int` whatever the buffer's dtype, because it holds
#                      the byte SIZE and not the value.
#

# THE argument trace, :62-70. THE device contract six other units are porting.
#
# `DSPProgram.__call__` packs ONE 8-byte-aligned block for the whole call:
#
#   ins   = [var_vals_mv of (len(bufs)+len(vals))*8 bytes,
#            off_mv   of len(bufs)*4 bytes]
#   outs  = [timer of 8 bytes]
#   in_fds = [b.share_info.fd for b in bufs]
#
# so `pra` has `3 + len(bufs)` entries: two ins, one out, then one dma per buffer.
# `fds` is `[-1]*(ins+outs) ++ in_fds` (tinygrad/runtime/ops_dsp.py:52 symbol=rpc_prep_args) and `attrs` is
# `[0]*(ins+outs) ++ [1]*len(in_fds)` (tinygrad/runtime/ops_dsp.py:53 symbol=rpc_prep_args) -- SAME length as `pra`, and the `1`
# is the only thing besides the length that tells a dma slot from a buffer slot.
# `rpc_sc(method=2, ins=2, outs=1, fds=len(bufs))` (:70), so the selector is a
# function of ONE number. `pra_of` is gated at nine (ins,outs,fds) fixtures
# INCLUDING (2,1,16) -- one past upstream's `bufs` refusal (tinygrad/runtime/ops_dsp.py:63 symbol=__call__) -- so a `pra` that grows where
# Python's does not is visible.
#
# var_vals_mv (:67,:68) is eight bytes per ARGUMENT: words 0..len(bufs)-1 are
# `b.size` written with fmt `'i'` at `i*8`, and the rest are the vals written with
# `dt.fmt` at `(len(bufs)+j)*8`. Every slot is 8 bytes ALWAYS, so a 4-byte fmt
# leaves the high word at ZERO and only an 8-byte fmt writes it. `vt_hi_written_*`
# is that row family.
#

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
#   * `recycled` (device.bend, from tinygrad/device.py:280) is the eviction policy, and -- upstream's `BufferSpec(nolru=True)` is in `__init__`
#     ops_dsp.py:135 allocates the fastrpc shell with `BufferSpec(nolru=True)`, so
#     the NEGATIVE case is in this file'S own code and not a fixture invented for
#     it. `dsp_norecycle_nolru` and `dsp_recycle_plain` are the same row family with
#     opposite answers at the SAME size, which is the only way a wrong eviction
#     cannot pass by accident.
#

# THE kernel name, :143. A string row, NEVER a boolean about a string.
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

# NO dsp and no ion in this env. `Device['DSP']` needs /dev/ion and
# `/dsp/cdsp/fastrpc_shell_3` does not exist, so NOTHING here was measured against
# a live DSP. Every constant and every `py=` expectation was produced by CALLING
# CPython -- see `.agents/slop/dsp_oracle.py`, which GENERATES the expectations. No
# expectation in this file was typed by hand.
#
# TWO measured facts worth their own rows:
#
#   * `ClangRenderer(Target("DSP","CLANG","hexagonv65,hexagonv65"))` RAISES
#     `RuntimeError: unsupported arch: 'hexagonv65'` from ClangCompiler (tinygrad/runtime/support/compiler_cpu.py:15).
#     That is WHY `DSPRenderer.__init__` (tinygrad/runtime/ops_dsp.py:17 symbol=__init__) does not call
#     `super().__init__`: a DSP target must never build the host CPU clang
#     compiler. `dsp_no_super_init` pins that the compiler is the DSP one.
#   * `rpc_sc(2,2,1,0)` is 33685760 and the listener's `sc=0x04020200` is 67240448.
#     They differ by exactly the method byte. The greeting literal is SPELLED AS A
#     LITERAL in Python (:194) and a port that "helpfully" rewrote it as an
#     `rpc_sc` call would send method 2 and the DSP would never see a greeting.
#     `dsp_rpc_greet_*` is that row family and it is the single most load-bearing
#     constant in the file.
#

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

# THE CONSTANTS. Every one read out of ops_dsp.py, its autogen bindings, or
# helpers.py -- the three places a number in this file can come from.

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
def ARGPTR_SIZE() -> U32: 3
def CONTROL_REQ() -> U32: 3
def INIT_FLAGS() -> U32: 1

# ION (:81) -- align 0x200, heap_id_mask 1<<ION_SYSTEM_HEAP_ID, ION_FLAG_CACHED
# `ION_SYSTEM_HEAP_ID` is 25, out of `tinygrad/runtime/autogen/qcom_dsp.py`'s
# `enum_ion_heap_ids` -- `(ION_SYSTEM_HEAP_ID:=25)`.  It was 0 HERE, and 0 is
# `INVALID_HEAP_ID`, so the port asked ION for the INVALID heap and its
# `heap_id_mask` was 1<<0 = 1 instead of 1<<25 = 33554432.  `dsp_ion` is the
# row that pins all five numbers and it says so.
def ION_ALIGN() -> U32: 512
def ION_SYSTEM_HEAP_ID() -> Nat: 25n
def ION_FLAG_CACHED() -> U32: 1

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

# :121 the command tail, identical in the mock and the real compile.  The `-o` slot
# is where upstream writes `{f.name}` -- a TEMPFILE name, and a name no fixed
# string can be -- so the slot is `<TMP>` here, and the port never spawns this
# command anyway (the spawn is not ported).  `<TMP>` is the SAME token the
# oracle's `dsp_cmd_*` rows carry, and it is a SLOT, not a path: upstream's
# `f.name` and `self.link_ld.name` are both random.
def COMPILE_TAIL() -> String:
  "-O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o <TMP>"

def OPEN_LIB_FP() -> String: "file:///tinylib?entry&_modver=1.0&_dom=cdsp"
def OPEN_LIB_NUL_LEN() -> U32: 1
def OPEN_LIB_SENTINEL() -> U32: 255

type Call is Data:
  Call{k: U32, arg: U32}

type DspBuf is Data:
  DspBuf{id: U32, va: U32, size: U32, offset: U32, share_fd: U32,
         share_handle: U32, has_share: Bool}

type Made is Data:
  Made{buf: DspBuf, t: Tr}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool}

type Pra is Data:
  Pra{is_dma: Bool, pv: U32, len: U32, fd: U32}

type Slot is Data:
  Slot{lo: U32, hi: U32, nbytes: U32}

def dt_cname.si(bits: U32) -> String:
  match bits:
    case 8: "signed char"
    case 16: "short"
    case 32: "int"
    case 64: "long long"
    case _: "KeyError"

def dt_cname.su(bits: U32) -> String:
  match bits:
    case 8: "unsigned char"
    case 16: "unsigned short"
    case 32: "unsigned int"
    case 64: "unsigned long long"
    case _: "KeyError"

def dt_cname.sf(bits: U32, pri: U32) -> String:
  match bits:
    case 16: Bool.pick(String, U32.is_eq(pri, 12), "__fp16", "__bf16")
    case 32: "float"
    case 64: "double"
    case _: "KeyError"

def dt_cname_dt(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CVoid{}  : "void"
        case S.CBool{}  : "_Bool"
        case S.CSint{}  : dt_cname.si(bits)
        case S.CUint{}  : dt_cname.su(bits)
        case S.CFloat{} : dt_cname.sf(bits, pri)
        case _: "KeyError"

# ONE PARAM of the generated kernel: a GLOBAL buffer (with its element count, so
# the mock can compute the byte width) or an ALU value (with its C spelling).
# `is_alu` is the `addrspace == AddrSpace.ALU` test that :32,:35,:37,:39,
# :261,:265 and :271 all make, and it decides whether the entry shim reads a SIZE
# or a VALUE out of the same 8-byte slot.
#
# IT carries the dtype, NOT its name. It carried `cn: String` -- a dtype NAME -- and
# every consumer fed it straight to `dt_cname` / `dt_itemsize`, both of which were
# ladders keyed on that name. So a dtype rename made eleven `dt_fmt` rows print the
# EMPTY STRING where CPython prints `b`/`e`/`f`/`d`, and it was invisible: the gate
# carried the expectation in a `# py=` COMMENT, so nothing compared. A `S.Dt` cannot
# be misspelled, and a ladder keyed on it cannot be renamed out from under itself.
type Param is Data:
  Param{is_alu: Bool, dt: S.Dt, numel: U32}

def Param.is_alu(p: Param) -> Bool:
  match p:
    case Param{is_alu, dt, numel}: is_alu

# The C SPELLING, `self.type_map.get(dt, dt.name)` (:15,:32). Read off the DTYPE.
def Param.cn(p: Param) -> String:
  match p:
    case Param{is_alu, dt, numel}: dt_cname_dt(dt)

def Param.dt(p: Param) -> S.Dt:
  match p:
    case Param{is_alu, dt, numel}: dt

def Param.numel(p: Param) -> U32:
  match p:
    case Param{is_alu, dt, numel}: numel

# THE fixtures. THE dtype is an `S.Dt`, BUILT by `LAWS/spec.bend`'s OWN constructor,
# so a fixture cannot name a dtype that does not exist.
def fx.g(dt: S.Dt, numel: U32) -> Param: Param{False{}, dt, numel}
def fx.a(dt: S.Dt, numel: U32) -> Param: Param{True{}, dt, numel}

def fx.bufs3() -> List<&2, U32>: [1, 2, 3]
def Tr.calls(+t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused}: calls

def Tr.next(+t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

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

# READING THE TRACE. Four readers and nothing else: the length, how many calls of a
# kind, their args in order, and "contains this (kind, arg) sequence, in order".

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

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

# THE FOUR DTYPE TABLES. Plain functions of dtype.py's `name` field, so each is
# gated over its whole domain rather than at a fixture.

# `spec.bend` holds `Dt` and has no `nm` reader; dtype.bend has `dt_name` but is a
# conversion seam and importing it would drag that seam in for nothing.
# TODO(p3) LAWS/spec.bend:76 symbol=Dt  Dt.nm -- the name reader this file matches on.
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
def dt_fmt_none() -> String: ""

# KEYED on `cls` AND `bits` -- A `Data` TAG and a number -- NEVER on a name. This ladder
# WAS keyed on names, and 793abbb renamed them: eleven `dt_fmt` rows printed the EMPTY
# STRING where CPython prints `b`/`e`/`f`/`d`, and nothing noticed, because the gate
# carried the expectation in a COMMENT. A name-keyed arm is a silent fall-through
# (`agent-core.md`, dtype-rename section), and this file is the worked example.
#
# `pri` is load-bearing for the ONE pair `bits` cannot separate: `f16` is `bits 16` and
# `fmt` `e`, `bf16` is `bits 16` and `fmt` None. Same split as
# `renderer/llvmir.bend`'s `lt.fp` and `renderer/isa/x86.bend`'s `Op.to_int.fp`.
def dt_fmt.si(bits: U32) -> String:
  match bits:
    case 8: "b"
    case 16: "h"
    case 32: "i"
    case 64: "q"
    case _: dt_fmt_none()

def dt_fmt.su(bits: U32) -> String:
  match bits:
    case 8: "B"
    case 16: "H"
    case 32: "I"
    case 64: "Q"
    case _: dt_fmt_none()

def dt_fmt.sf(bits: U32, pri: U32) -> String:
  match bits:
    case 16: Bool.pick(String, U32.is_eq(pri, 12), "e", dt_fmt_none())
    case 32: Bool.pick(String, U32.is_eq(pri, 14), "f", dt_fmt_none())
    case 64: Bool.pick(String, U32.is_eq(pri, 15), "d", dt_fmt_none())
    case _: dt_fmt_none()

def dt_fmt_dt(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CBool{}  : "?"
        case S.CSint{}  : dt_fmt.si(bits)
        case S.CUint{}  : dt_fmt.su(bits)
        case S.CFloat{} : dt_fmt.sf(bits, pri)
        case _: dt_fmt_none()

def dt_has_fmt_dt(d: S.Dt) -> Bool: Bool.not(String.eq(dt_fmt_dt(d), dt_fmt_none()))

# `dt.itemsize`: how many bytes `struct.pack(fmt, ...)` writes into an 8-byte slot.
# void is 0 and weakint/weakfloat are 100 -- dtype.py's placeholders, and 100 is
# wider than a slot, which is exactly why the "high bytes untouched" claim below
# needs a dtype it cannot reach.
#
# A nineteen-ARM name table was here. It is `(bitsize + 7) // 8`, which is dtype.py's
# own `DType.itemsize` PROPERTY -- measured on all twenty: void 0, bool 1, the four
# 8-bits 1, the four 16-bits 2, the four 32-bits 4, the four 64-bits 8, weak 100. So
# this is arithmetic on `bits` and a table was twenty opportunities to be wrong.
def dt_itemsize_dt(d: S.Dt) -> U32:
  match d:
    case S.Dt{pri, bits, cls, nm}: U32.div(U32.add(bits, 7), 8)

# `self._render_dtype(dt.dtype)` (:32), i.e. `self.type_map.get(dt, dt.name)` with
# the TWO extra keys ops_dsp.py:15 adds. MEASURED: `ClangRenderer.type_map` has
# exactly two keys, `bool` and `half`, so both additions are new entries and neither
# is a correction.
# KEYED on `cls`/`bits`/`pri`, and it is a TOTAL fourteen-ENTRY table with NO fallback.
# It HAD a `case _: nm`, and that is wrong twice over: `cstyle.py:30` is
# `self.type_map[dtype]` -- a KEY LOOKUP that RAISES, not `.get(dt, dt.name)` -- and the
# `nm` it fell back to was a dtype NAME, which since 793abbb is `i8` and not the C
# THE GLOBAL ARM of :32, and the load-bearing asymmetry of the whole file: a
# GLOBAL's `sz_or_val` is spelled `int` whatever the buffer's dtype, because it
# holds the byte SIZE (:67 packs `b.size`) and not the value. A port that keyed the
# GLOBAL arm off the dtype would type a float buffer's size as `float` and every
# read at `pra[0].buf.pv+i*8` would be a float load.
def dt_cname_global(+is_alu: Bool, +d: S.Dt) -> String:
  match is_alu:
    case True{}: dt_cname_dt(d)
    case False{}: "int"

# `supported_dtypes` (:46) = ClangRenderer's, minus the fp8s, minus bfloat16.
# ClangRenderer's own filter (cstyle.py:315) drops the fp8s ALWAYS and drops
# bfloat16 unless the arch starts with x86/arm. MEASURED: an x86 arch gives 13
# dtypes, a hexagon arch gives 12, and DSP gives 12 on BOTH -- so the arch test is
# irrelevant here, and the `dtypes.bf16` in :46 is the WHOLE difference on x86
# and a NO-OP on hexagon. `dsp_sdtype_n` plus `dsp_sdtype_x86_drop` pins that.
# BOTH drops are structural, `(cls, bits, pri)` AND nothing ELSE. They were
# `dt_is_fp8("fp8e4m3")` and `String.eq(nm, "__bf16")` -- NAME TESTS on strings that
# `LAWS/spec.bend` had already renamed, so BOTH ANSWERED FALSE for a real dtype and
# `dsp_sd_drop_fp8` printed False where CPython drops. Measured: `dtypes.bf16 in
# DSPRenderer(Target("DSP","CLANG","x86_64,znver3")).supported_dtypes()` is False.
def dt_is_fp8_dt(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CFloat{}: U32.is_eq(bits, 8)
        case _: False{}

def dt_is_bf16_dt(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CFloat{}: Bool.and(U32.is_eq(bits, 16), U32.is_eq(pri, 13))
        case _: False{}

def supported_12.at(n: Nat) -> S.Dt:
  match n:
    case 0n: S.boolean()
    case 1n: S.int8()
    case 2n: S.uint8()
    case 3n: S.int16()
    case 4n: S.uint16()
    case 5n: S.int32()
    case 6n: S.uint32()
    case 7n: S.int64()
    case 8n: S.uint64()
    case 9n: S.half()
    case 10n: S.single()
    case _: S.double()

def supported_12.of(+ix: List<&2, Nat>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ix:
    case Nil{}: acc
    case i <> t: supported_12.of(t, List.append(&2, S.Dt, acc, [supported_12.at(i)]))

def supported_dtypes() -> List<&2, S.Dt>:
  supported_12.of(List.range(12n), Nil{})

def supported_names.of(+ix: List<&2, Nat>, acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}: acc
    case i <> t: supported_names.of(t, List.append(&2, String, acc, [dt_nm(supported_12.at(i))]))

def supported_names() -> List<&2, String>:
  supported_names.of(List.range(12n), Nil{})

# `code_for_op` (:16) = ClangRenderer's minus `Ops.SQRT`. MEASURED 18 against 17,
# the difference being exactly that one op. The CONTENTS are cstyle.py's and are
# not this file's, so only the COUNT and the REMOVAL are ported -- see WHAT
# ops_qcom.bend OWES for why restating the table would be a liability here.
def CFOP_CLANG() -> U32: 18
def CFOP_DSP() -> U32: 17
def FD_NONE() -> U32: 4294967295

def fill(n: Nat, +v: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: fill(m, v, List.append(&2, U32, acc, [v]))

def fds_head(n: Nat) -> List<&2, U32>: fill(n, FD_NONE(), Nil{})

def ATTR_BUF() -> U32: 0
def ATTR_DMA() -> U32: 1

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

# var_vals_mv and off_mv, :65-69. THE 8-BYTE SLOT TABLE.

# `memoryview(bytearray((len(bufs)+len(vals))*8))` (:65) and
# `memoryview(bytearray(len(bufs)*4))` for the offsets (:65). The var_vals block is
# 8 bytes per ARGUMENT -- buffer or val -- so a 4-byte fmt leaves the high word at
# zero and only an 8-byte fmt writes it.
def vt_nbytes(+nbufs: U32, nvals: U32) -> U32: U32.mul(U32.add(nbufs, nvals), 8)
def off_nbytes(nbufs: U32) -> U32: U32.mul(nbufs, 4)

def vt_size_byte(i: U32) -> U32: U32.mul(i, 8)

def vt_hi_written(nbytes: U32) -> Bool: U32.is_eq(nbytes, 8)
def vt_lo_written(nbytes: U32) -> Bool: U32.is_ge(nbytes, 1)
def prog.too_many(nbufs: U32) -> Bool: U32.is_ge(nbufs, MAX_BUFS())

# :65-66. TWO ins, ONE out, and `nfds = len(bufs)`. The two ins are the var_vals
# block and the offsets block; the out is the 8-byte timer.
def TIMER_BYTES() -> U32: 8
def prog.nins() -> U32: 2
def prog.nouts() -> U32: 1

def prog.exec_sc(nbufs: U32) -> U32:
  rpc_sc(M_INVOKE(), prog.nins(), prog.nouts(), nbufs)

def prog.call(over: Bool, +nbufs: U32, t: Tr) -> Tr:
  match over:
    case True{}: Tr.refuse_now(t)
    case False{}: Tr.emit(CALL_EXEC_LIB(), prog.exec_sc(nbufs), t)

def buf.of(id: U32, va: U32, size: U32, share_fd: U32, share_handle: U32,
           has_share: Bool) -> DspBuf:
  DspBuf{id, va, size, 0, share_fd, share_handle, has_share}

def buf.size(b: DspBuf) -> U32:
  match b:
    case DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: size

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

def MMAP_PROT() -> U32: 3
def MAP_SHARED() -> U32: 1
def MAP_ANONYMOUS() -> U32: 32

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

def ENTRY_FIXED() -> U32: 4
def ENTRY_TAIL() -> U32: 4

def entry.head1() -> String:
  "struct dcvs_v2_req req = {.type=7, .dcvs_enable=0, .set_latency=1, .latency=100, .set_dcvs_params=1, .target_corner = 6 /* TURBO */};"
def entry.dma_slot(i: U32) -> U32: U32.add(i, U32.add(prog.nins(), prog.nouts()))

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

def boiler_first_len.go(m: Maybe<&2, String>) -> U32:
  match m:
    case None{}: 0
    case Some{+l}: U32.from_nat(String.length(l))

def boiler_first_len() -> U32:
  boiler_first_len.go(List.get(&2, String, String.lines(mockdsp_boilerplate()), 0n))

def compiler_args_first(mock: Bool) -> String:
  Bool.pick(String, mock, ARG_STATIC(), ARG_SHARED())

def compiler_args_has_T(mock: Bool) -> Bool: Bool.not(mock)

# :113 `super().__init__(None if mock else "compile_dsp")`, and tinygrad/runtime/ops_dsp.py:113 then
# gates it on CCACHE. So the cachekey is None for MOCKDSP AND whenever CCACHE is 0 --
# TWO independent reasons, and `dsp_cachekey_*` has a row for each.
def compiler.cachekey_of(+mock: Bool, +ccache: Bool) -> String:
  Bool.pick(String, Bool.and(Bool.not(mock), ccache), CACHEKEY(), "")

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

def LINK_SCRIPT_ARG() -> String: " -T<TMP>"

def dev.open_ion(+t: Tr) -> Tr: Tr.emit(CALL_OPEN_ION(), 0, t)

def dev.shell_spec() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}

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
def dev.open_lib_sc() -> U32: rpc_sc(M_OPEN(), 2, 2, 0)

# :146 `FASTRPC_IOCTL_INVOKE(self.rpc_fd, handle=0, sc=..., pra=pra)`.
def dev.open_lib(+t: Tr) -> Tr: Tr.emit(CALL_OPEN_LIB(), dev.open_lib_sc(), t)

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

# RPCListener, :178-239. THE sc DISPATCH and the argument layouts.

def RPC_GREET() -> U32: 67240448
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
    case 319095040: ARM_OPEN()
    case _: ARM_NONE()

def rpc.arm_close(sc: U32) -> U32:
  match sc:
    case 50397184: ARM_CLOSE()
    case 151060480: ARM_SEEK()
    case _: rpc.arm_open(sc)

def rpc.arm_read(sc: U32) -> U32:
  match sc:
    case 67174912: ARM_READ()
    case 520225024: ARM_STAT()
    case _: rpc.arm_close(sc)

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
def RPC_OBJ_ALIGN() -> U32: 8
def RPC_SIZE_BYTES() -> U32: 4

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

def APPS_STD_SEEK_SET() -> U32: 0

def HEX_DIGITS() -> String: "0123456789ABCDEF"

def u32_hex_digit(n: U32) -> String:
  String.from_list([Maybe.default(&2, Char, String.get(HEX_DIGITS(), U32.to_nat(n)),
    Char.from_u32(63))])

# The FUEL is the digit count and it SHRINKS, so the self-call is a decreasing
# one: a U32 is at most eight hex digits, and the walk stops at the first zero.
def u32_hex.go(n: Nat, +v: U32, +acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m:
      match v:
        case 0: acc
        case _: u32_hex.go(m, U32.div(v, 16),
          String.append(acc, u32_hex_digit(U32.mod(v, 16))))

def u32_hex(+n: U32) -> String:
  match n:
    case 0: "0"
    case _: String.reverse(u32_hex.go(8n, n, ""))

def mprog.stdin_bytes.go(+bs: List<&2, U32>, acc: U32) -> U32:
  match bs:
    case Nil{}: acc
    case b <> t: mprog.stdin_bytes.go(t, U32.add(acc, b))

def mprog.stdin_bytes(bs: List<&2, U32>) -> U32:
  mprog.stdin_bytes.go(bs, 0)

# :283-286 the input is the bufs' bytes and THEN the vals packed with `dt.fmt`,
# so the count is the bufs' bytes plus EIGHT per val.  `nbufs` was IGNORED here
# -- `mprog.nstdin(0, 0)` answered the three-buffer fixture's 6 -- so the row
# `dsp_mp_nstdin` said 6 where upstream's own arithmetic says 0.
def mprog.bufs_prefix.go(n: Nat, +bs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case b <> t: mprog.bufs_prefix.go(m, t, List.append(&2, U32, acc, [b]))

def mprog.bufs_prefix(nbufs: U32) -> List<&2, U32>:
  mprog.bufs_prefix.go(U32.to_nat(nbufs), fx.bufs3(), Nil{})

def MPROG_HEAD() -> U32: 4

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

def entry.count_munmap(ps: List<&2, Param>) -> U32: entry.count_off(ps)
def NAMES.at(n: Nat) -> S.Dt:
  match n:
    case 0n: S.void()
    case 1n: S.boolean()
    case 2n: S.weakint()
    case 3n: S.int8()
    case 4n: S.uint8()
    case 5n: S.int16()
    case 6n: S.uint16()
    case 7n: S.int32()
    case 8n: S.uint32()
    case 9n: S.int64()
    case 10n: S.uint64()
    case 11n: S.weakfloat()
    case 12n: S.fp8e4m3()
    case 13n: S.fp8e4m3fnuz()
    case 14n: S.fp8e5m2()
    case 15n: S.fp8e5m2fnuz()
    case 16n: S.half()
    case 17n: S.bfloat16()
    case 18n: S.single()
    case _: S.double()

def NAMES.of(+ix: List<&2, Nat>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ix:
    case Nil{}: acc
    case i <> t: NAMES.of(t, List.append(&2, S.Dt, acc, [NAMES.at(i)]))

def NAMES() -> List<&2, S.Dt>: NAMES.of(List.range(20n), Nil{})

def count_all(+ns: List<&2, S.Dt>, got: U32) -> U32:
  match ns:
    case Nil{}: got
    case _ <> t: count_all(t, U32.add(got, 1))

def count_fmt(+ns: List<&2, S.Dt>, got: U32) -> U32:
  match ns:
    case Nil{}: got
    case n <> t: count_fmt(t, U32.add(got, Bool.to_u32(dt_has_fmt_dt(n))))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

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
