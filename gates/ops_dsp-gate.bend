# gates/ops_dsp-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_dsp.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/runtime/ops_dsp.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S

def INSN_CNT_WORD() -> U32: 1779810304
# ===========================================================================
# THE TYPES.
# ===========================================================================
# ONE device call and the ONE integer it carries that a decision reads.
# :74 `DSPBuffer(va_addr, size, share_info, offset)`. `id` is the seam's handle for
# the address; `has_share` is Python's `share_info is None` test (:89), so it is
# false for MOCKDSP and true for the real allocator.
# one created buffer and the trace that created it. Bend refuses to destructure a
# computed product, so the two travel together -- the port's idiom throughout.
# the machine state of the seam: the ordered call list, the id counter, and the
# refusal flag. See THE RAISE.
# ONE remote_arg (:52) as the two arms of the union declared at :23. A `buf` arm
# carries (pv, len) and a `dma` arm carries (fd, offset). `len` is 0 on a dma arm
# MEASURED -- the fill loop at :56 stops at `len(ins)+len(outs)`, so a dma slot's
# `buf.size` still reads 0 from untouched union storage. `pv` is reported as 0 or
# nonzero, never as a value: it is an address and addresses are not reproducible.
# ONE 8-byte slot of var_vals_mv (:67,:68), little-endian, so `lo` is the low word.
# How many bytes a `struct.pack` writes into it is `nbytes`, a separate row family.
# :257's comment points at the gpages.com syscall table, which is where every
# number in the mock's boilerplate comes from.
def SYSCALL_READ() -> U32: 63
# The boilerplate is NINE lines and its FIRST is 106 characters long --
# `/* DSP boilerplate */ static long syscall(long r0, long r1, long r2, long r3,
# long r4, long r5, long r6) {`.  The first-line length was 65 HERE, a number
# that is in no upstream revision at all, and it is MEASURED from the port's OWN
# boilerplate now, so a boilerplate that grows cannot leave the row behind.
def boiler_lines() -> U32:
  U32.from_nat(List.length(&2, String, String.lines(P.mockdsp_boilerplate())))
def RPC_NOUTS() -> U32: 2
def dt_fmt_all_count() -> U32: P.count_all(P.NAMES(), 0)
def open_lib_ins1() -> U32: P.OPEN_LIB_SENTINEL()
def entry.guard() -> String: "if ((sc>>24) != 2) return 0;"
def u32_of_str(+s: String, sub: String) -> U32:
  Bool.to_u32(String.contains(s, sub))
# --- 7: the entry shim, :27-44 -----------------------------------------------
def fx.g2() -> List<&2, P.Param>: [P.fx.g(S.single(), 4), P.fx.g(S.single(), 4)]
def entry.head2() -> String: "HAP_power_set((void*)handle, (void*)&req);"
# --- 10: the eviction policy, device.py:280 CONSUMED --------------------------
# THE NEGATIVE CASE. ops_dsp.py:135 allocates the fastrpc shell with
# `BufferSpec(nolru=True)`, so this file's OWN code has a buffer that must NOT be
# recycled, one row family away from an ordinary buffer that must. Same size,
# opposite answers.
def entry.sz_decl(+i: U32, +p: P.Param) -> String:
  String.concat([P.dt_cname_global(P.Param.is_alu(p), P.Param.dt(p)), " sz_or_val_",
    U32.show(i), " = *(", P.dt_cname_global(P.Param.is_alu(p), P.Param.dt(p)),
    "*)((char*)pra[0].buf.pv+", U32.show(P.vt_size_byte(i)), ");"])
# :35 `f'int off{i} = ((int*)pra[1].buf.pv)[{i}];'` -- the offset subscript is i,
# the ARRAY subscript is i, and the dtype is `int` unconditionally because the
# offsets block was built by `array('I')`.
# :268 `params` is `(void*)buf{i}` for a GLOBAL -- THE CAST the real shim does not
# need, because `HAP_mmap` already returns `void*` -- and bare `val{i}` otherwise.
def srow(nm: String, +v: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", v, "]   py=[", v, "]"]))
def urow(nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", U32.show(v), "]   py=[", U32.show(v), "]"]))
# :39,:40 `fbufs` is `buf_{i}` for a GLOBAL and `sz_or_val_{i}` for an ALU, joined
# with ", " at :40.
def entry.arg_name(+i: U32, +p: P.Param) -> String:
  Bool.pick(String, P.Param.is_alu(p),
    String.concat(["sz_or_val_", U32.show(i)]), String.concat(["buf_", U32.show(i)]))
def entry.count_mmap(ps: List<&2, P.Param>) -> U32: P.entry.count_off(ps)
def fx.agga() -> List<&2, P.Param>:
  [P.fx.a(S.uint32(), 1), P.fx.g(S.single(), 4), P.fx.g(S.single(), 4), P.fx.a(S.int32(), 1)]
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
def fx.ga1() -> List<&2, P.Param>: [P.fx.g(S.single(), 4), P.fx.a(S.uint32(), 1), P.fx.g(S.single(), 4)]
def fx.a2() -> List<&2, P.Param>: [P.fx.a(S.uint32(), 1), P.fx.a(S.single(), 1)]
# --- 2: the selector's two readers, and the entry shim's refusal -------------
def entry.off(+i: U32) -> String:
  String.concat(["int off", U32.show(i), " = ((int*)pra[1].buf.pv)[", U32.show(i), "];"])
# :36-37 `void *buf_{i} = HAP_mmap(0,sz_or_val_{i},3,0,pra[{i+3}].dma.fd,0)+off{i};`.
# The literal `3` is PROT_READ|PROT_WRITE, and the dma slot is `i+3` because the
# three non-dma slots (two ins, one out) come first -- which is exactly `prog.nins()
# + prog.nouts()`.
# :134-136 the shell buffer. `round_up(fastrpc_shell.nbytes, 0x1000)` is what is
# ALLOCATED and `fastrpc_shell.nbytes` is what is COPIED, so the two sizes differ
# and `dsp_shell_*` has a row for each. :135's `BufferSpec(nolru=True)` is the
# eviction NEGATIVE case; see THE BUFFER-OWNERSHIP RULES.
def entry.timer_close() -> String:
  "*(unsigned long long *)(pra[2].buf.pv) = HAP_perf_get_time_us() - start;"
def entry.munmap(+i: U32) -> String:
  String.concat(["HAP_munmap(buf_", U32.show(i), ", sz_or_val_", U32.show(i), ");"])
# ===========================================================================
# THE MOCK SHIM, MockDSPRenderer._render_entry, :256-274. A DIFFERENT entry point:
# `_start`, no DCVS, no mmap-by-fd, and the sizes come from the KERNEL's
# `max_numel()*itemsize` rather than from the wire.
# ===========================================================================
def entry.head0() -> String: "int entry(unsigned long long handle, unsigned int sc, remote_arg* pra) {"
# :266 `{dtype} val{i}; read(0, &val{i}, {itemsize});` -- it is the dtype's OWN name
# (`_render_dtype`), NOT the `int` the GLOBAL arm of :32 uses, and the read length
# is the ITEMSIZE, so a half reads 2 and a double reads 8.
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  +s = String.join(P.ush(xs, ",", Nil{}), ",")
  IO.print(String.concat([nm, " = [", s, "]   py=[", s, "]"]))
def entry.line_count(+ps: List<&2, P.Param>) -> U32:
  U32.add(P.ENTRY_FIXED(), U32.add(P.entry.count_sz_of(ps),
    U32.add(U32.mul(P.entry.count_off(ps), 2),
      U32.add(P.ENTRY_TAIL(), P.entry.count_munmap(ps)))))
# ===========================================================================
# THE DOMAIN-SPANNING TABLES. `NAMES` is dtype.py's own twenty, in its `__lt__`
# order, and the two counts fold over it -- so 12 have a fmt and 20 exist, and
# nothing in the domain is left unaccounted for.
# ===========================================================================
# THE TWENTY DTYPES, AS DTYPES. It was a table of NAMES -- the pre-793abbb spellings --
# which is how `count_fmt` came to ask `dt_has_fmt` about a dtype nobody has.
def entry.timer_open() -> String: "unsigned long long start = HAP_perf_get_time_us();"
# :104-105 the fifteen sections the link script aligns to 4k. "Aligning all used
# sections to 4k fixes invoke problem" -- the NOTE is the reason and is kept.
def fx.g1() -> List<&2, P.Param>: [P.fx.g(S.uint32(), 1)]
# :115-116 `__del__` unlinks the script when not mock -- so the mock has NO temp file
# and `dsp_unlink_*` is the negative case for that too.
def entry.count_alu(ps: List<&2, P.Param>) -> U32: P.entry.count_go(True{}, ps, 0)
# the total line count of an entry, which is the row that sees a DROPPED line --
# every other row here reads one line and a line that stopped being emitted is
# invisible to them.
# --- 11: the compiler, :98-125 -------------------------------------------------
def fx.a1() -> List<&2, P.Param>: [P.fx.a(S.uint32(), 1)]
def entry.ret() -> String: "return 0; }"
# :32-33 the `sz_or_val` DECLARATION. `int` for a GLOBAL -- it is the byte SIZE --
# and `_render_dtype` for an ALU, and both read the SAME slot at `pra[0].buf.pv`.
# :264 `void *buf{i} = mmap2(0, {sz}, 3, 0x21, -1, 0); for(int rd = 0; rd < {sz};
# rd += read(0, buf{i}+rd, {sz}-rd));`. `0x21` is MAP_PRIVATE|MAP_ANONYMOUS. The
# `# https://gpages.juszkiewicz.com.pl/syscalls-table/syscalls.html` NOTE at :257
# is why the numbers below are named after syscalls rather than flags.
def entry.mmap(+i: U32) -> String:
  String.concat(["void *buf_", U32.show(i), " = HAP_mmap(0,sz_or_val_", U32.show(i),
    ",", U32.show(P.MMAP_PROT()), ",0,pra[", U32.show(P.entry.dma_slot(i)),
    "].dma.fd,0)+off", U32.show(i), ";"])
# :39,:40 `fbufs` is `buf_{i}` for a GLOBAL and `sz_or_val_{i}` for an ALU, joined
# with ", " at :40.
# --- 1: rpc_sc, :48 ------------------------------------------------------------
def t_entry() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    srow("dsp_e_h0",     entry.head0())
    
    
    
    
    srow("dsp_e_h2",     entry.head2())
    
    
    
    
    srow("dsp_e_guard",     entry.guard())
    
    
    
    
    srow("dsp_e_topen",     entry.timer_open())
    
    
    
    
    srow("dsp_e_tclose",     entry.timer_close())
    
    
    
    
    srow("dsp_e_ret",     entry.ret())
    # :32-33 the sz_or_val line. A GLOBAL is `int` at i*8 whatever its dtype.
    
    
    
    
    srow("dsp_e_sz_g0",     entry.sz_decl(0, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_e_sz_g1",     entry.sz_decl(1, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_e_sz_g2",     entry.sz_decl(2, P.fx.g(S.uint32(), 1)))
    
    
    
    
    srow("dsp_e_sz_g3",     entry.sz_decl(3, P.fx.g(S.uint64(), 1)))
    # and an ALU is `_render_dtype`, at the SAME i*8 slot
    
    
    
    
    srow("dsp_e_sz_a0",     entry.sz_decl(0, P.fx.a(S.uint32(), 1)))
    
    
    
    
    srow("dsp_e_sz_a1",     entry.sz_decl(1, P.fx.a(S.single(), 1)))
    
    
    
    
    srow("dsp_e_sz_a2",     entry.sz_decl(2, P.fx.a(S.int32(), 1)))
    
    
    
    
    srow("dsp_e_sz_a3",     entry.sz_decl(3, P.fx.a(S.int32(), 1)))
    # :35 the off line
    
    
    
    
    srow("dsp_e_off0",     entry.off(0))
    
    
    
    
    srow("dsp_e_off1",     entry.off(1))
    
    
    
    
    srow("dsp_e_off2",     entry.off(2))
    # :36-37 the mmap line and the dma slot `i+3`
    
    
    
    
    srow("dsp_e_mm0",     entry.mmap(0))
    
    
    
    
    srow("dsp_e_mm1",     entry.mmap(1))
    
    
    
    
    srow("dsp_e_mm2",     entry.mmap(2))
    
    
    
    
    lrow("dsp_e_dma_0",     [P.entry.dma_slot(0)])
    
    
    
    
    lrow("dsp_e_dma_2",     [P.entry.dma_slot(2)])
    
    
    
    
    lrow("dsp_e_dma_4",     [P.entry.dma_slot(4)])
    
    
    
    
    lrow("dsp_e_dma_n",     [U32.sub(P.entry.dma_slot(0), U32.add(P.prog.nins(), P.prog.nouts()))])
    # :42 the munmap line
    
    
    
    
    srow("dsp_e_un0",     entry.munmap(0))
    
    
    
    
    srow("dsp_e_un2",     entry.munmap(2))
    # :39,:40 the kernel-call argument
    
    
    
    
    srow("dsp_e_arg_g0",     entry.arg_name(0, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_e_arg_g1",     entry.arg_name(1, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_e_arg_a0",     entry.arg_name(0, P.fx.a(S.uint32(), 1)))
    
    
    
    
    srow("dsp_e_arg_a1",     entry.arg_name(1, P.fx.a(S.single(), 1)))
    # THE agga FIXTURE -- ALU, GLOBAL, GLOBAL, ALU. The index is the PARAM index.
    
    
    
    
    srow("dsp_e_ag_off1",     entry.off(1))
    
    
    
    
    srow("dsp_e_ag_mm1",     entry.mmap(1))
    
    
    
    
    srow("dsp_e_ag_mm2",     entry.mmap(2))
    
    
    
    
    srow("dsp_e_ag_arg0",     entry.arg_name(0, P.fx.a(S.uint32(), 1)))
    
    
    
    
    srow("dsp_e_ag_arg3",     entry.arg_name(3, P.fx.a(S.int32(), 1)))
    # the LINE COUNTS. One GLOBAL fixture is 4 + 1 + 2 + 4 + 1 = 12, which is what
    # CPython's eight msrc entries produce. agga is 4 + 4 + 4 + 4 + 2 = 18.
    
    
    
    
    urow("dsp_e_lines_g1",     entry.line_count(fx.g1()))
    
    
    
    
    urow("dsp_e_lines_g2",     entry.line_count(fx.g2()))
    
    
    
    
    urow("dsp_e_lines_g0",     entry.line_count(Nil{}))
    
    
    
    
    urow("dsp_e_lines_agga",     entry.line_count(fx.agga()))
    
    
    
    
    urow("dsp_e_lines_a1",     entry.line_count(fx.a1()))
    
    
    
    
    urow("dsp_e_lines_a2",     entry.line_count(fx.a2()))
    
    
    
    
    urow("dsp_e_lines_gag",     entry.line_count(fx.ga1()))
    
    
    
    
    urow("dsp_e_nfixed",     P.ENTRY_FIXED())
    
    
    
    
    urow("dsp_e_ntail",     P.ENTRY_TAIL())
    
    
    
    
    urow("dsp_e_nsz_agga",     P.entry.count_sz_of(fx.agga()))
    
    
    
    
    urow("dsp_e_noff_agga",     P.entry.count_off(fx.agga()))
    
    
    
    
    urow("dsp_e_nmmap_agga",     entry.count_mmap(fx.agga()))
    
    
    
    
    urow("dsp_e_nalu_agga",     entry.count_alu(fx.agga()))
    
    
    
    
    urow("dsp_e_noff_g2",     P.entry.count_off(fx.g2()))
    
    
    
    
    urow("dsp_e_noff_a2",     P.entry.count_off(fx.a2()))
# --- 8: the mock shim, :256-274 ----------------------------------------------
# :68 `struct.pack_into(unwrap(dt.fmt), var_vals_mv, i*8, v)` with `i` starting at
# `len(bufs)`. So a val's offset is `(nbufs + j) * 8`, never `j * 8`.
def vt_val_offset(nbufs: U32, j: U32) -> U32: U32.mul(U32.add(nbufs, j), 8)
# how many of the eight bytes a dtype's fmt writes. 8 writes the high word; a
# narrower one does not touch it; void writes none.
def SYSCALL_MMAP2() -> U32: 222
# :108 the whole file, verbatim: the `SECTIONS` wrapper, `. = 0x0`, the fifteen
# sections and the /DISCARD/ tail. `dsp_link_script` diffs the STRING, all
# seventeen lines of it, against CPython's own `sections_link`.
def link_script() -> String:
  String.concat(["SECTIONS { . = 0x0; ", P.link_body(),
    "\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }"])
# :115-116 `__del__` unlinks the script when not mock -- so the mock has NO temp file
# and `dsp_unlink_*` is the negative case for that too.
def alloc.copyout_bytes(dest_bytes: U32) -> U32: dest_bytes
# :79 `if getenv("MOCKDSP"): fd, share_info, flags = -1, None,
# mmap.MAP_SHARED|mmap.MAP_ANONYMOUS` and the real arm's `flags = mmap.MAP_SHARED`.
def mrender.finish() -> String: "unsigned int et = inscount() - st; write(1, &et, sizeof(et));"
def seen(+t: P.Tr) -> U32: U32.from_nat(List.length(&2, P.Call, P.Tr.calls(t)))
def Tr.refused(+t: P.Tr) -> Bool:
  match t:
    case P.Tr{calls, next, refused}: refused
# an empty trace that keeps the id counter, so a fixture that reads one program call
# without the device init in front of it still mints ids from one.
def Made.buf(m: P.Made) -> P.DspBuf:
  match m:
    case P.Made{buf, t}: buf
def KERNEL_TYPEDEF() -> String: "__attribute__((noinline)) void"
# :143 the library URL. See THE KERNEL NAME: 44 is the length Python counts and it
# INCLUDES the NUL, which Bend's String cannot hold.
def SYSCALL_EXIT() -> U32: 93
def alloc.real_flags() -> U32: P.MAP_SHARED()
# :81 `ION_IOC_ALLOC(self.dev.ion_fd, len=size, align=0x200,
# heap_id_mask=1<<ION_SYSTEM_HEAP_ID, flags=ION_FLAG_CACHED)`.
def ion.aligned(nbytes: U32) -> U32: H.round_up_u32(nbytes, P.ION_ALIGN())
# :79-84 `_alloc`. The two arms differ in THREE observable ways: MOCKDSP makes NO
# ION call, has NO share, and adds MAP_ANONYMOUS. All three are recorded, so
# `dsp_alloc_mock_*` is the negative case for each of `dsp_alloc_real_*`.
# :136 `ctypes.memmove(self.shell_buf.va_addr, mv_address(fastrpc_shell),
# fastrpc_shell.nbytes)` -- the RAW size, not the rounded one.
def dev.shell_copy(nbytes: U32, t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_MEMMOVE(), nbytes, t)
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
# the seven `sc` values the loop dispatches on, taken from the elif chain at
# :213-238. The chain's ORDER is not the numeric order, so `rpc.arm` is a table and
# `dsp_rpc_arms` is its image.
#
# THE seven literals, READ out of upstream'S own source at
#   :213 `if sc == 0x20200: pass`          :213  0x0020200
#   :214 `elif sc == 0x13050100: # open`   :214  0x13050100
#   :217 `elif sc == 0x3010000:`           :217  0x03010000
#   :219 `elif sc == 0x9010000: # seek`    :219  0x09010000
#   :225 `elif sc == 0x4010200: # read`    :225  0x04010200
#   :232 `elif sc == 0x1f020100: # stat`   :232  0x1f020100
#   :236 `elif sc == 0x2010100: # mmap`    :236  0x02010100
# FIVE of the seven HERE were WRONG: 0x0BE00000, 0x09002600, 0x04004000,
# 0x01DC0000 and 0x02010000 are in NO upstream revision -- `git log --all -S` finds
# no such constant in `tinygrad/runtime/ops_dsp.py` at all -- and a port that
# dispatches on them NEVER reaches upstream's arms.  `dsp_rpc_scs` is the row
# that pins all seven, and `dsp_rpc_reply_io` and `dsp_rpc_seek_err` are the two
# that read a wrong selector out of it.
def SC_HELLO() -> U32: 131584
# ALU, GLOBAL, GLOBAL, ALU -- the fixture that separates the param index from a
# compacted counter.
def fx.offs3() -> List<&2, U32>: [0, 64, 128]
def row(nm: String, +b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, " = [", Bool.show(b), "]   py=[", Bool.show(b), "]"]))
def Made.tr(m: P.Made) -> P.Tr:
  match m:
    case P.Made{buf, t}: t
# `nbytes` is NOT a field here either, for the reason device.bend gives: it is
# `size * itemsize` and storing it lets the two disagree. ops_dsp.py reads exactly
# one size (:67, `b.size`), so that is the one field.
# --- 4: rpc_prep_args, :49-57 -------------------------------------------------
def first(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case x <> _: x
# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one of
# them would branch the walk twice over.
# --- 9: the allocator, :73-96 -------------------------------------------------
def dev.shell_size(nbytes: U32) -> U32: H.round_up_u32(nbytes, P.SHELL_ALIGN())
# the spec :135 asks for: nolru and nothing else.
def fx.spec(nolru: Bool, ext: Bool) -> D.Bspec:
  D.Bspec{False{}, False{}, False{}, nolru, ext}
# ALU, GLOBAL, GLOBAL, ALU -- the fixture that separates the param index from a
# compacted counter.
def Tr.of() -> P.Tr: P.Tr{Nil{}, 0, False{}}
def dev.shell_spec.plain(s: D.Bspec) -> Bool:
  match s:
    case D.Bspec{uncached, cpu_access, host, nolru, ext_ptr}:
      Bool.and(Bool.not(uncached), Bool.and(Bool.not(cpu_access),
        Bool.and(Bool.not(host), Bool.not(ext_ptr))))
# :136 `ctypes.memmove(self.shell_buf.va_addr, mv_address(fastrpc_shell),
# fastrpc_shell.nbytes)` -- the RAW size, not the rounded one.
def cargs(k: U32, t: P.Tr) -> List<&2, U32>: P.Tr.args(k, P.Tr.calls(t))
# THE fuel is the trace length and the answer is `at == patlen`. With the fuel set
# to the PATTERN length instead, `case 0n:` fires after patlen trace entries and
# returns True without ever looking at `at`, so a reversed pattern matches and a
# pattern longer than the trace matches too. That bug was MEASURED in
# ops_webgpu.bend (its mutation M23); `dsp_has_reverse` and `dsp_has_toolong` are
# the two rows here that exist to catch it.
def dev.shell_spec.nolru(s: D.Bspec) -> Bool:
  match s:
    case D.Bspec{uncached, cpu_access, host, nolru, ext_ptr}: nolru
# --- 15: the reader, and the matcher itself ----------------------------------
def t_evict() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    row("dsp_recycle_plain",     D.recycled(True{}, True{}, fx.spec(False{}, False{})))
    
    
    
    
    row("dsp_norecycle_nolru",     Bool.not(D.recycled(True{}, True{}, P.dev.shell_spec())))
    
    
    
    
    row("dsp_norecycle_glru",     Bool.not(D.recycled(False{}, True{}, fx.spec(False{}, False{}))))
    
    
    
    
    row("dsp_norecycle_lru",     Bool.not(D.recycled(True{}, False{}, fx.spec(False{}, False{}))))
    
    
    
    
    row("dsp_norecycle_ext",     Bool.not(D.recycled(True{}, True{}, fx.spec(False{}, True{}))))
    # the shell's spec is the negative one: nolru and NOTHING else true, so a spec
    # built wrong is visible even though `recycled` only reads two of the five
    
    
    
    
    row("dsp_shell_nolru",     dev.shell_spec.nolru(P.dev.shell_spec()))
    
    
    
    
    row("dsp_shell_plain",     dev.shell_spec.plain(P.dev.shell_spec()))
    
    
    
    
    row("dsp_plain_nolru",     Bool.not(dev.shell_spec.nolru(fx.spec(False{}, False{}))))
    # the policy itself, at a BOOL per row so a mutation names one conjunct
    
    
    
    
    lrow("dsp_recycle_matrix",     [Bool.to_u32(D.recycled(True{}, True{}, fx.spec(False{}, False{}))),
                                    Bool.to_u32(D.recycled(True{}, True{}, fx.spec(True{}, False{}))),
                                    Bool.to_u32(D.recycled(True{}, True{}, fx.spec(False{}, True{}))),
                                    Bool.to_u32(D.recycled(False{}, True{}, fx.spec(False{}, False{}))),
                                    Bool.to_u32(D.recycled(True{}, False{}, fx.spec(False{}, False{})))])
    # the shell buffer itself: allocated at the ROUNDED size and never recycled
    +sh : P.Made <- IO.pure(P.Made, P.alloc.alloc(dev.shell_size(4660), False{}, Tr.of()))
    
    
    
    
    urow("dsp_shell_alloc_n",     seen(Made.tr(sh)))
    
    
    
    
    urow("dsp_shell_alloc_size",     P.buf.size(Made.buf(sh)))
    
    
    
    
    urow("dsp_shell_alloc_sz16",     dev.shell_size(4096))
    
    
    
    
    urow("dsp_shell_copy_n",     first(cargs(P.CALL_MEMMOVE(), dev.shell_copy(4660, Tr.of()))))
    
    
    
    
    urow("dsp_shell_recycled",     Bool.to_u32(D.recycled(True{}, True{}, P.dev.shell_spec())))
    # device.bend's own readers, consumed: LIFO take and the free_cache drain
    
    
    
    
    lrow("dsp_take",     [D.alloc_take(Nil{}), D.alloc_take([11]),
                           D.alloc_take([11, 22]), D.alloc_take([11, 22, 33])])
    
    
    
    
    lrow("dsp_freed",     [D.freed(Nil{}, 0), D.freed([1], 0), D.freed([1, 2, 3], 0)])
# --- 11: the compiler, :98-125 -------------------------------------------------
def vt_lo_of(+d: S.Dt) -> Bool: P.vt_lo_written(P.dt_itemsize_dt(d))
# ===========================================================================
# DSPProgram.__call__, :62-71.
# ===========================================================================
# :63 `if len(bufs) >= 16: raise RuntimeError(f"Too many buffers to execute:
# {len(bufs)}")`. `prog.too_many` is the whole of it; `prog.call`'s `Tr.refuse_now`
# is what turns it into a trace that records NOTHING.
def SC_SEEK() -> U32: 151060480
# :32-33 the `sz_or_val` DECLARATION. `int` for a GLOBAL -- it is the byte SIZE --
# and `_render_dtype` for an ALU, and both read the SAME slot at `pra[0].buf.pv`.
def mrender.arg_name(+i: U32, +p: P.Param) -> String:
  Bool.pick(String, P.Param.is_alu(p), String.concat(["val", U32.show(i)]),
    String.concat(["(void*)buf", U32.show(i)]))
# :272 `write(1, buf{i}, {max_numel*itemsize})` -- the OUTPUT block, the same width
# as the input, and only for a GLOBAL.
# A ROW IS A COMPARISON. All four print the port's OWN value twice -- once as the
# answer and once as the `py=` half -- so the lane is a `diff` against
# `gates/ops_dsp_render-oracle.py` rather than 512 lines nobody compared. They used to
# print `nm=value` and carry the expectation in a `# py=` COMMENT, which is the same
# file on both sides of the comparison -- `dsp_gate_check.py` says so on every run and
# calls itself "AUTHORITY: NONE". The row count did not change and neither did the
# file's green; only this did. They then took CPython's answer as a THIRD argument,
# which was a TRANSCRIPTION of what CPython said once, and a transcription has no
# generator: it cannot see CPython move, and it cannot see the PORT move either --
# MEASURED 2026-10-22, thirty of these rows' `py=` halves were RIGHT while the
# `got=` half beside them was WRONG, so the file agreed with itself and was wrong on
# thirty rows. The `py=` half is now DERIVED -- the port's own value, re-read -- and
# the comparison is against CPython's lane, byte for byte.
def rpc.lens() -> List<&2, U32>:
  [P.RPC_MSG_BYTES(), P.RPC_BUF_BYTES(), P.RPC_MSG_BYTES(), P.RPC_BUF_BYTES()]
# :188 `req_args[1].buf.len = 0` -- the RESPONSE-LENGTH field is zeroed AFTER
# rpc_prep_args has set it, so it is the one slot whose length the caller overrides.
def fx.ffs16() -> List<&2, U32>:
  [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
# :188 `req_args[1].buf.len = 0` -- the RESPONSE-LENGTH field is zeroed AFTER
# rpc_prep_args has set it, so it is the one slot whose length the caller overrides.
def rpc.out_len_index() -> U32: 1
def seq(+t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)
def buf.offset(b: P.DspBuf) -> U32:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: offset
def mrender.stamp() -> String: "unsigned int st = inscount();"
def HEX_REG_QEMU_INSN_CNT() -> U32: 21
def rpc.seek_err(+sc: U32) -> String:
  String.concat(["AssertionError: Supported only SEEK_SET (sc=", U32.show(sc), ")"])
# :213 `if sc == 0x20200: pass # greating` -- the greeting arm does NOTHING, which is
# the one arm with no side effect. `dsp_rpc_hello_n` says so by pinning zero calls.
def SC_READ() -> U32: 67174912
def rpc.msg_inbytes_index() -> U32: 3
# :197 `context, inbufs, outbufs = msg_recv[0], ((sc:=msg_recv[2]) >> 16) & 0xff,
# (msg_recv[2] >> 8) & 0xff`. The reply's word 2 is the SAME selector layout
# `rpc_sc` builds, read back with shifts -- which is why `sc_ins`/`sc_outs` mask
# with 0xff rather than reading the whole shifted word.
def sc_fds(sc: U32) -> U32: U32.and(sc, P.SC_BYTE_MASK())
# :33 `if ((sc>>24) != 2) return 0;` -- the entry shim runs ONE method and refuses
# every other. Method 2 is M_INVOKE, which is what :70 sends.
def fds_of(nins: U32, nouts: U32, +fds: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, P.fds_head(U32.to_nat(U32.add(nins, nouts))), fds)
# :54 `([0] * (len(ins) + len(outs)), [1] * len(in_fds))`. The `1` marks a slot as
# a DMA descriptor rather than a buffer, and it is the ONLY difference between a dma
# slot and a buffer slot besides the length.
def pra_len(nins: U32, nouts: U32, nfds: U32) -> U32:
  U32.add(U32.add(nins, nouts), nfds)
# :53 `([-1] * (len(ins) + len(outs)), *in_fds)`. The `-1` is the "no dma on this
# slot" marker and it is what the kernel's `remote_arg` arm selection reads.
def pra_of(nins: U32, nouts: U32, +lens: List<&2, U32>, +fds: List<&2, U32>) -> List<&2, P.Pra>:
  P.pra_dma(U32.to_nat(U32.from_nat(List.length(&2, U32, fds))),
    fds, P.pra.put(U32.to_nat(U32.add(nins, nouts)), lens, Nil{}))
def fx.ffs3() -> List<&2, U32>: [10, 11, 12]
# MEASURED: `f"Cannot open lib: {msg}"` on an EMPTY message is `"Cannot open lib: "`
# WITH a trailing space, and on a non-empty one it is the same string with the
# message appended. So the space is in the PREFIX here and the message carries no
# leading space -- which is the only split that makes BOTH rows right. The trailing
# space is invisible in a diff and `String.concat` keeps it, so `dsp_ol_err_empty`
# says so in its own comment.
def attrs_of(nins: U32, nouts: U32, nfds: U32) -> List<&2, U32>:
  List.append(&2, U32, P.fill(U32.to_nat(U32.add(nins, nouts)), P.ATTR_BUF(), Nil{}),
    P.fill(U32.to_nat(nfds), P.ATTR_DMA(), Nil{}))
# :56 `for i, mv in enumerate(ins + outs): pra[i].buf.pv, pra[i].buf.len =
# ctypes.c_void_p(mv_address(mv) if mv.nbytes > 0 else 0), mv.nbytes`.
#
# THE ZERO-LENGTH RULE. `mv_address` is `ctypes.c_char.from_buffer(mv)` and a
# zero-length buffer has no address to ask for, so the `else 0` is REQUIRED rather
# than defensive -- Python short-circuits and never calls `mv_address` for n == 0.
# MEASURED: the assign then leaves `pra[0].buf.pv` as None, and `len` 0. So the port
# records `pv` as 0 for a zero-length slot and 1 for every other, which is the only
# reproducible form of an address.
# --- 3: the four dtype tables -------------------------------------------------
def t_pra() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    lrow("dsp_pra_len_000",     [pra_len(0, 0, 0)])
    
    
    
    
    lrow("dsp_pra_len_2210",     [pra_len(2, 1, 0)])
    
    
    
    
    lrow("dsp_pra_len_0220",     [pra_len(0, 2, 2)])
    
    
    
    
    lrow("dsp_pra_len_2213",     [pra_len(2, 1, 3)])
    
    
    
    
    lrow("dsp_pra_len_22115",     [pra_len(2, 1, 15)])
    
    
    
    
    lrow("dsp_pra_len_22116",     [pra_len(2, 1, 16)])
    
    
    
    
    lrow("dsp_pra_len_111",     [pra_len(1, 1, 1)])
    
    
    
    
    lrow("dsp_pra_len_112",     [pra_len(1, 1, 2)])
    # :53 fds = [-1]*(ins+outs) ++ in_fds
    
    
    
    
    lrow("dsp_fds_2210",     fds_of(2, 1, Nil{}))
    
    
    
    
    lrow("dsp_fds_2213",     fds_of(2, 1, fx.ffs3()))
    
    
    
    
    lrow("dsp_fds_000",     fds_of(0, 0, Nil{}))
    
    
    
    
    lrow("dsp_fds_002",     fds_of(0, 0, fx.ffs3()))
    
    
    
    
    lrow("dsp_fds_111",     fds_of(1, 1, [10]))
    
    
    
    
    lrow("dsp_fds_22116",     fds_of(2, 1, fx.ffs16()))
    # :54 attrs = [0]*(ins+outs) ++ [1]*len(in_fds)
    
    
    
    
    lrow("dsp_attr_2210",     attrs_of(2, 1, 0))
    
    
    
    
    lrow("dsp_attr_2213",     attrs_of(2, 1, 3))
    
    
    
    
    lrow("dsp_attr_000",     attrs_of(0, 0, 0))
    
    
    
    
    lrow("dsp_attr_002",     attrs_of(0, 0, 2))
    
    
    
    
    lrow("dsp_attr_111",     attrs_of(1, 1, 1))
    
    
    
    
    lrow("dsp_attr_0220",     attrs_of(0, 2, 2))
    
    
    
    
    lrow("dsp_attr_22116",     attrs_of(2, 1, 16))
    # the two arrays have the SAME length as pra -- that is the shape claim
    
    
    
    
    lrow("dsp_pra_lens_eq",     [pra_len(2, 1, 3),
          U32.from_nat(List.length(&2, U32, fds_of(2, 1, fx.ffs3()))),
          U32.from_nat(List.length(&2, U32, attrs_of(2, 1, 3)))])
    # :56 the buffer arms. lens [8,16,8] is the oracle's own (2,1) fixture.
    
    
    
    
    lrow("dsp_pra_len_2210v",     P.pra_lens(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))
    
    
    
    
    lrow("dsp_pra_pv_2210v",     P.pra_pvs(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))
    
    
    
    
    lrow("dsp_pra_len_2213v",     P.pra_lens(pra_of(2, 1, [8, 16, 8], fx.ffs3()), Nil{}))
    
    
    
    
    lrow("dsp_pra_fd_2213v",     P.pra_fds(pra_of(2, 1, [8, 16, 8], fx.ffs3()), Nil{}))
    
    
    
    
    lrow("dsp_pra_fd_2210v",     P.pra_fds(pra_of(2, 1, [8, 16, 8], Nil{}), Nil{}))
    # THE ZERO-LENGTH RULE
    
    
    
    
    lrow("dsp_pra_len_z",     P.pra_lens(pra_of(1, 1, [0, 8], [7]), Nil{}))
    
    
    
    
    lrow("dsp_pra_pv_z",     P.pra_pvs(pra_of(1, 1, [0, 8], [7]), Nil{}))
    
    
    
    
    row("dsp_pra_pvset_0",     Bool.not(P.pra.pv_set(0)))
    
    
    
    
    row("dsp_pra_pvset_8",     P.pra.pv_set(8))
    # one PAST the :63 refusal still packs -- :63 refuses the CALL, not the packer
    
    
    
    
    lrow("dsp_pra_len_22116v",     P.pra_lens(pra_of(2, 1, [8, 16, 8], fx.ffs16()), Nil{}))
    
    
    
    
    lrow("dsp_pra_fd_22116v",     P.pra_fds(pra_of(2, 1, [8, 16, 8], fx.ffs16()), Nil{}))
# --- 5: var_vals and off_mv, :65-69 -------------------------------------------
# the FIRST arg of a kind, and 0 when there is none. `first` is what the selector
# rows read, because every selector is a function of ONE number.
def buf.nbytes(b: P.DspBuf) -> U32: P.buf.size(b)
# :96 `def _offset(self, buf, size, offset): return DSPBuffer(buf.va_addr+offset,
# size, buf.share_info, buf.offset+offset)`.
#
# THE ACCUMULATION. BOTH fields add the offset and the second is the one that is
# easy to lose: `off` is a view's offset WITHIN the root, so a second view must add
# to the first view's offset rather than replace it. See THE BUFFER-OWNERSHIP
# RULES for what a dropped `buf.offset+` costs.
# --- 5: var_vals and off_mv, :65-69 -------------------------------------------
def buf.has_share(b: P.DspBuf) -> Bool:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: has_share
def alloc.mock_flags() -> U32: U32.or(P.MAP_SHARED(), P.MAP_ANONYMOUS())
# :292 `struct.unpack("I", proc.stdout[0:4])[0] / 1e9  # pretend it's 1 Ghz, but this
# is an inscount, not a time`. THE DIVISOR DIFFERS from the real program's 1e6.
def ncalls(k: U32, t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
# the FIRST arg of a kind, and 0 when there is none. `first` is what the selector
# rows read, because every selector is a function of ONE number.
# :192 `msg_send[:] = array.array('I', [context, status, req_args[1].buf.len,
# in_buf.nbytes])` -- FOUR words, and the two that MOVE are the status and the
# response length.
def alloc.as_buffer_bytes(+b: P.DspBuf) -> U32: P.buf.size(b)
# :94 `_copyin` is `ctypes.memmove(dest.va_addr, mv_address(src), src.nbytes)` and
# :95 `_copyout` is `ctypes.memmove(mv_address(dest), src.va_addr, dest.nbytes)`.
# THE ASYMMETRY IS REAL: `src.nbytes` going in, `dest.nbytes` coming out. A port
# that read one field for both would be wrong for a view.
def buf.share_handle(b: P.DspBuf) -> U32:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: share_handle
def buf.va(b: P.DspBuf) -> U32:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: va
# the total line count of an entry, which is the row that sees a DROPPED line --
# every other row here reads one line and a line that stopped being emitted is
# invisible to them.
def alloc.copyin_bytes(src_bytes: U32) -> U32: src_bytes
def ion.heap_id_mask() -> U32: U32.shln(1, P.ION_SYSTEM_HEAP_ID())
def buf.share_fd(b: P.DspBuf) -> U32:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: share_fd
def buf.id(b: P.DspBuf) -> U32:
  match b:
    case P.DspBuf{id, va, size, offset, share_fd, share_handle, has_share}: id
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # :96 offsets ACCUMULATE. BOTH fields, and the second is the load-bearing one.
    +b0 : P.DspBuf <- IO.pure(P.DspBuf, P.buf.of(0, 4096, 1024, 7, 9, True{}))
    +b1 : P.DspBuf <- IO.pure(P.DspBuf, P.alloc.offset(b0, 256, 64))
    
    
    
    
    urow("dsp_acc_off0",     buf.offset(b0))
    
    
    
    
    urow("dsp_acc_off1",     buf.offset(b1))
    
    
    
    
    urow("dsp_acc_va1",     buf.va(b1))
    
    
    
    
    urow("dsp_acc_sz1",     P.buf.size(b1))
    
    
    
    
    urow("dsp_acc_fd1",     buf.share_fd(b1))
    
    
    
    
    urow("dsp_acc_hdl1",     buf.share_handle(b1))
    
    
    
    
    urow("dsp_acc_id1",     buf.id(b1))
    
    
    
    
    urow("dsp_acc_n1",     buf.nbytes(b1))
    
    
    
    
    row("dsp_acc_share1",     buf.has_share(b1))
    # a SECOND view accumulates on the FIRST -- the only row that can see a
    # dropped `buf.offset+`.
    +b2 : P.DspBuf <- IO.pure(P.DspBuf, P.alloc.offset(b1, 128, 16))
    
    
    
    
    urow("dsp_acc_off2",     buf.offset(b2))
    
    
    
    
    urow("dsp_acc_va2",     buf.va(b2))
    
    
    
    
    urow("dsp_acc_sz2",     P.buf.size(b2))
    
    
    
    
    urow("dsp_acc_hdl2",     buf.share_handle(b2))
    
    
    
    
    urow("dsp_acc_fd2",     buf.share_fd(b2))
    
    
    
    
    row("dsp_acc_share2",     buf.has_share(b2))
    # and a third, to catch an accumulate that only works twice
    +b3 : P.DspBuf <- IO.pure(P.DspBuf, P.alloc.offset(b2, 64, 4))
    
    
    
    
    urow("dsp_acc_off3",     buf.offset(b3))
    
    
    
    
    urow("dsp_acc_va3",     buf.va(b3))
    # the arithmetic on its own, so a bug is attributable
    
    
    
    
    lrow("dsp_acc_math",     [P.alloc.offset.va(4096, 64), P.alloc.offset.acc(0, 64),
                              P.alloc.offset.acc(64, 16), P.alloc.offset.acc(80, 4)])
    
    
    
    
    lrow("dsp_acc_math0",     [P.alloc.offset.va(0, 0), P.alloc.offset.acc(0, 0)])
    # the MOCK arm has NO share and a view of it stays share-less
    +m0 : P.DspBuf <- IO.pure(P.DspBuf, P.buf.of(0, 0, 1024, 0, 0, False{}))
    +m1 : P.DspBuf <- IO.pure(P.DspBuf, P.alloc.offset(m0, 256, 64))
    
    
    
    
    row("dsp_acc_mshare",     Bool.not(buf.has_share(m1)))
    
    
    
    
    urow("dsp_acc_moff",     buf.offset(m1))
    # :81 ION's align and heap mask
    
    
    
    
    lrow("dsp_ion",     [P.ION_ALIGN(), ion.heap_id_mask(), P.ION_FLAG_CACHED(),
                         U32.from_nat(P.ION_SYSTEM_HEAP_ID()), P.ION_FLAG_CACHED()])
    
    
    
    
    lrow("dsp_ion_a",     [ion.aligned(1), ion.aligned(511), ion.aligned(512),
                           ion.aligned(513), ion.aligned(1024)])
    # :135 the ROUNDED size is allocated and the RAW size is copied
    
    
    
    
    lrow("dsp_shell_sz",     [dev.shell_size(0), dev.shell_size(1),
                              dev.shell_size(4095), dev.shell_size(4096),
                              dev.shell_size(4097), dev.shell_size(4660)])
    
    
    
    
    lrow("dsp_mmap",     [P.MMAP_PROT(), alloc.mock_flags(), alloc.real_flags()])
    # the free order, and the MOCK negative case for each of its three calls
    +fr : P.Tr <- IO.pure(P.Tr, P.alloc.free(True{}, 1024, 9, Tr.of()))
    
    
    
    
    urow("dsp_free_r_n",     seen(fr))
    
    
    
    
    urow("dsp_free_r_hdl",     first(cargs(P.CALL_ION_FREE(), fr)))
    
    
    
    
    urow("dsp_free_r_mm",     first(cargs(P.CALL_MMAP(), fr)))
    
    
    
    
    row("dsp_free_r_order",     seq(fr, [P.Call{P.CALL_MMAP, 1024},
          P.Call{P.CALL_OS_CLOSE, P.FD_NONE()}, P.Call{P.CALL_ION_FREE, 9}]))
    
    
    
    
    row("dsp_free_r_rev",     Bool.not(seq(fr, [P.Call{P.CALL_ION_FREE, 9},
          P.Call{P.CALL_MMAP, 1024}])))
    +fm : P.Tr <- IO.pure(P.Tr, P.alloc.free(False{}, 1024, 9, Tr.of()))
    
    
    
    
    urow("dsp_free_m_n",     seen(fm))
    
    
    
    
    urow("dsp_free_m_ionfree",     ncalls(P.CALL_ION_FREE(), fm))
    
    
    
    
    urow("dsp_free_m_close",     ncalls(P.CALL_OS_CLOSE(), fm))
    
    
    
    
    urow("dsp_free_m_mmap",     ncalls(P.CALL_MMAP(), fm))
    
    
    
    
    urow("dsp_free_m_mm",     first(cargs(P.CALL_MMAP(), fm)))
    # the copy arms: src.nbytes in, dest.nbytes out -- ASYMMETRIC
    
    
    
    
    lrow("dsp_copy",     [alloc.copyin_bytes(64), alloc.copyout_bytes(32),
                          alloc.copyin_bytes(0), alloc.copyout_bytes(4294967295)])
    
    
    
    
    urow("dsp_asbuf",     alloc.as_buffer_bytes(b0))
    # the alloc arms: THREE calls real, ONE mock
    +ar : P.Made <- IO.pure(P.Made, P.alloc.alloc(1024, False{}, Tr.of()))
    
    
    
    
    urow("dsp_alloc_r_n",     seen(Made.tr(ar)))
    
    
    
    
    urow("dsp_alloc_r_sz",     first(cargs(P.CALL_ION_ALLOC(), Made.tr(ar))))
    
    
    
    
    urow("dsp_alloc_r_mm",     first(cargs(P.CALL_MMAP(), Made.tr(ar))))
    
    
    
    
    urow("dsp_alloc_r_share",     first(cargs(P.CALL_ION_SHARE(), Made.tr(ar))))
    
    
    
    
    urow("dsp_alloc_r_size",     P.buf.size(Made.buf(ar)))
    
    
    
    
    urow("dsp_alloc_r_id",     buf.id(Made.buf(ar)))
    
    
    
    
    row("dsp_alloc_r_hasshare",     buf.has_share(Made.buf(ar)))
    
    
    
    
    row("dsp_alloc_r_order",     seq(Made.tr(ar), [P.Call{P.CALL_ION_ALLOC, 1024},
          P.Call{P.CALL_ION_SHARE, 1}, P.Call{P.CALL_MMAP, 1024}]))
    +am : P.Made <- IO.pure(P.Made, P.alloc.alloc(1024, True{}, Tr.of()))
    
    
    
    
    urow("dsp_alloc_m_n",     seen(Made.tr(am)))
    
    
    
    
    urow("dsp_alloc_m_ionalloc",     ncalls(P.CALL_ION_ALLOC(), Made.tr(am)))
    
    
    
    
    urow("dsp_alloc_m_ionshare",     ncalls(P.CALL_ION_SHARE(), Made.tr(am)))
    
    
    
    
    urow("dsp_alloc_m_mm",     first(cargs(P.CALL_MMAP(), Made.tr(am))))
    
    
    
    
    urow("dsp_alloc_m_size",     P.buf.size(Made.buf(am)))
    
    
    
    
    urow("dsp_alloc_m_id",     buf.id(Made.buf(am)))
    
    
    
    
    row("dsp_alloc_m_noshare",     Bool.not(buf.has_share(Made.buf(am))))
# --- 10: the eviction policy, device.py:280 CONSUMED --------------------------
# THE NEGATIVE CASE. ops_dsp.py:135 allocates the fastrpc shell with
# `BufferSpec(nolru=True)`, so this file's OWN code has a buffer that must NOT be
# recycled, one row family away from an ordinary buffer that must. Same size,
# opposite answers.
def H_TINYFD() -> U32: 65535
# ioctl arguments (:173 arg=3, :174 req=0x3, :175 flags=0x1)
# :129 `if getenv("MOCKDSP"):` -- ONE branch, and it selects FOUR things at once:
# the renderer (MockDSPRenderer against DSPRenderer), the program (MockDSPProgram
# against DSPProgram), the allocator (`DSPAllocator(self)` either way), and whether
# the whole ION/adsprpc bring-up happens at all.
def dev.is_mock() -> Bool: True{}
def dev.branch_same_alloc() -> Bool: True{}
# :132 `self.ion_fd = os.open('/dev/ion', os.O_RDONLY)` -- the real arm only.
# `nbytes` is NOT a field here either, for the reason device.bend gives: it is
# `size * itemsize` and storing it lets the two disagree. ops_dsp.py reads exactly
# one size (:67, `b.size`), so that is the one field.
def vt_hi_of(+d: S.Dt) -> Bool: P.vt_hi_written(P.dt_itemsize_dt(d))
def prog.pra_lens(+nbufs: U32, nvals: U32) -> List<&2, U32>:
  [P.vt_nbytes(nbufs, nvals), P.off_nbytes(nbufs), P.TIMER_BYTES()]
# :70 `self.dev.exec_lib(self.lib, rpc_sc(method=2, ins=2, outs=1, fds=len(bufs)),
# pra, fds, attrs)`. The selector is a function of ONE number -- `len(bufs)` --
# which is why `dsp_exec_sc_*` is a row family and not a constant.
def vt_nslots(+nbufs: U32, nvals: U32) -> U32: U32.add(nbufs, nvals)
def Slot.lo(s: P.Slot) -> U32:
  match s:
    case P.Slot{lo, hi, nbytes}: lo
def Slot.hi(s: P.Slot) -> U32:
  match s:
    case P.Slot{lo, hi, nbytes}: hi
# :68 `struct.pack_into(unwrap(dt.fmt), var_vals_mv, i*8, v)` with `i` starting at
# `len(bufs)`. So a val's offset is `(nbufs + j) * 8`, never `j * 8`.
def vt_size_at(i: U32, size: U32) -> P.Slot: P.Slot{size, 0, 8}
def Slot.nbytes(s: P.Slot) -> U32:
  match s:
    case P.Slot{lo, hi, nbytes}: nbytes
def t_varvals() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    lrow("dsp_vt_b_3_0",     [P.vt_nbytes(3, 0)])
    
    
    
    
    lrow("dsp_vt_b_3_1",     [P.vt_nbytes(3, 1)])
    
    
    
    
    lrow("dsp_vt_b_3_2",     [P.vt_nbytes(3, 2)])
    
    
    
    
    lrow("dsp_vt_b_2_2",     [P.vt_nbytes(2, 2)])
    
    
    
    
    lrow("dsp_vt_b_1_1",     [P.vt_nbytes(1, 1)])
    
    
    
    
    lrow("dsp_vt_b_0_0",     [P.vt_nbytes(0, 0)])
    
    
    
    
    lrow("dsp_vt_s_3_2",     [vt_nslots(3, 2)])
    
    
    
    
    lrow("dsp_vt_s_0_0",     [vt_nslots(0, 0)])
    # :67 pack_into('i', mv, i*8, b.size)
    
    
    
    
    lrow("dsp_vt_ix_0",     [P.vt_size_byte(0)])
    
    
    
    
    lrow("dsp_vt_ix_1",     [P.vt_size_byte(1)])
    
    
    
    
    lrow("dsp_vt_ix_2",     [P.vt_size_byte(2)])
    
    
    
    
    lrow("dsp_vt_lo_4",     [Slot.lo(vt_size_at(0, 4))])
    
    
    
    
    lrow("dsp_vt_hi_4",     [Slot.hi(vt_size_at(0, 4))])
    
    
    
    
    lrow("dsp_vt_lo_big",     [Slot.lo(vt_size_at(0, 4294967295))])
    
    
    
    
    lrow("dsp_vt_hi_big",     [Slot.hi(vt_size_at(0, 4294967295))])
    
    
    
    
    lrow("dsp_vt_sz_nbytes",     [Slot.nbytes(vt_size_at(0, 4))])
    # :68 pack_into(dt.fmt, mv, (nbufs+j)*8, v) -- the offset is NOT j*8
    
    
    
    
    lrow("dsp_vt_vox_3_0",     [vt_val_offset(3, 0)])
    
    
    
    
    lrow("dsp_vt_vox_3_1",     [vt_val_offset(3, 1)])
    
    
    
    
    lrow("dsp_vt_vox_0_0",     [vt_val_offset(0, 0)])
    
    
    
    
    lrow("dsp_vt_vox_1_0",     [vt_val_offset(1, 0)])
    
    
    
    
    lrow("dsp_vt_vox_15_0",     [vt_val_offset(15, 0)])
    # how many of the eight bytes a fmt writes
    
    
    
    
    row("dsp_vt_hi_q",     vt_hi_of(S.int64()))
    
    
    
    
    row("dsp_vt_hi_Q",     vt_hi_of(S.uint64()))
    
    
    
    
    row("dsp_vt_hi_d",     vt_hi_of(S.double()))
    
    
    
    
    row("dsp_vt_hi_i",     Bool.not(vt_hi_of(S.int32())))
    
    
    
    
    row("dsp_vt_hi_f",     Bool.not(vt_hi_of(S.single())))
    
    
    
    
    row("dsp_vt_hi_e",     Bool.not(vt_hi_of(S.half())))
    
    
    
    
    row("dsp_vt_hi_b",     Bool.not(vt_hi_of(S.int8())))
    
    
    
    
    row("dsp_vt_hi_void",     Bool.not(vt_hi_of(S.void())))
    
    
    
    
    row("dsp_vt_lo_void",     Bool.not(vt_lo_of(S.void())))
    
    
    
    
    row("dsp_vt_lo_b",     vt_lo_of(S.int8()))
    
    
    
    
    row("dsp_vt_lo_weakint",     vt_lo_of(S.weakint()))
    # the three buffers' own sizes -- `rpc_prep_args`'s ins + outs
    
    
    
    
    lrow("dsp_prog_pl_3_2",     prog.pra_lens(3, 2))
    
    
    
    
    lrow("dsp_prog_pl_3_0",     prog.pra_lens(3, 0))
    
    
    
    
    lrow("dsp_prog_pl_0_0",     prog.pra_lens(0, 0))
    
    
    
    
    lrow("dsp_prog_pl_1_1",     prog.pra_lens(1, 1))
    
    
    
    
    lrow("dsp_prog_pl_15_0",     prog.pra_lens(15, 0))
    
    
    
    
    lrow("dsp_off_b_0",     [P.off_nbytes(0)])
    
    
    
    
    lrow("dsp_off_b_1",     [P.off_nbytes(1)])
    
    
    
    
    lrow("dsp_off_b_3",     [P.off_nbytes(3)])
    
    
    
    
    lrow("dsp_off_b_15",     [P.off_nbytes(15)])
    
    
    
    
    lrow("dsp_off_b_16",     [P.off_nbytes(16)])
# --- 6: the program call, :62-71 ----------------------------------------------
def mrender.start() -> String: "void _start(void) {"
def open_lib_len() -> U32: U32.add(P.OPEN_LIB_NAMED_LEN(), P.OPEN_LIB_NUL_LEN())
# :185 `context, status, TINYFD = 0, 0xffffffff, 0xffff`.
def RPC_CONTEXT() -> U32: 0
def DEV_ADSP() -> String: "/dev/adsprpc-smd"
# --- 14: the mock program's wire format, :283-292 ---------------------------
def mprog.nstdin(+nbufs: U32, nvals: U32) -> U32:
  U32.add(P.mprog.stdin_bytes(P.mprog.bufs_prefix(nbufs)), U32.mul(nvals, 8))
# :287 `offset = 4` -- the inscount is the FIRST four bytes of stdout, then the
# buffers in order, then `assert offset == len(proc.stdout)`.
# :33 `if ((sc>>24) != 2) return 0;` -- the entry shim runs ONE method and refuses
# every other. Method 2 is M_INVOKE, which is what :70 sends.
def mprog.stdout_len(nbytes: U32) -> U32: U32.add(P.MPROG_HEAD(), nbytes)
# :292 `struct.unpack("I", proc.stdout[0:4])[0] / 1e9  # pretend it's 1 Ghz, but this
# is an inscount, not a time`. THE DIVISOR DIFFERS from the real program's 1e6.
def t_mprog() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    lrow("dsp_mp_in",     [P.mprog.stdin_bytes(Nil{}), P.mprog.stdin_bytes(P.fx.bufs3()),
                           P.mprog.stdin_bytes([16]), P.mprog.stdin_bytes([16, 4]),
                           P.mprog.stdin_bytes(fx.offs3())])
    
    
    
    
    lrow("dsp_mp_nstdin",     [mprog.nstdin(3, 0), mprog.nstdin(3, 2),
                               mprog.nstdin(0, 0)])
    
    
    
    
    lrow("dsp_mp_out",     [P.MPROG_HEAD(), mprog.stdout_len(0), mprog.stdout_len(6),
                            mprog.stdout_len(192)])
    # the mock reuses the SAME dt.fmt table, so there is no second per-dtype family
    
    
    
    
    row("dsp_mp_shared_fmts",     P.dt_has_fmt_dt(S.int32()))
    # :291 `assert offset == len(proc.stdout)` -- the two sums agree or the mock
    # raises, and the offset starts at 4.
    
    
    
    
    lrow("dsp_mp_check",     [P.MPROG_HEAD(), mprog.stdout_len(0)])
# --- 15: the reader, and the matcher itself ----------------------------------
def SHELL_PATH() -> String: "/dsp/cdsp/fastrpc_shell_3"
def SC_MMAP() -> U32: 33620224
def open_lib_out1() -> U32: 255
# :52-54. One `pra` and THREE arrays, all of length `len(ins)+len(outs)+
# len(in_fds)`, so `pra_len` is what every row below is sized by.
def entry.method_ok(sc: U32) -> Bool: U32.is_eq(P.sc_method(sc), P.M_INVOKE())
# `dt.fmt` (:68, `struct.pack(unwrap(dt.fmt), ...)`). `None` is not a missing table
# entry: it is dtype.py's own value, and `unwrap` on it is a hard failure. So
# `dt_fmt_none` is the EMPTY string and "has no fmt" is a Bool, not a string --
# because there is no string to print. `dsp_fmt_nones` pins how many there are.
def sc_ins(sc: U32) -> U32: U32.and(U32.shrn(sc, P.SC_INS()), P.SC_BYTE_MASK())
# --- 12: the device init and the three lib calls, :128-176 --------------------
def sc_outs(sc: U32) -> U32: U32.and(U32.shrn(sc, P.SC_OUTS()), P.SC_BYTE_MASK())
def t_scfields() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    lrow("dsp_scf_2210",     [P.sc_method(33685760), sc_ins(33685760),
                              sc_outs(33685760), sc_fds(33685760)])
    
    
    
    
    lrow("dsp_scf_22115",     [P.sc_method(33685775), sc_ins(33685775),
                               sc_outs(33685775), sc_fds(33685775)])
    
    
    
    
    lrow("dsp_scf_open",     [P.sc_method(131584), sc_ins(131584),
                              sc_outs(131584), sc_fds(131584)])
    # :33 `if ((sc>>24) != 2) return 0;` -- method 2 ONLY.
    
    
    
    
    row("dsp_entry_ok_2",     entry.method_ok(P.rpc_sc(2, 2, 1, 0)))
    
    
    
    
    row("dsp_entry_ok_2b",     entry.method_ok(P.rpc_sc(2, 0, 0, 0)))
    
    
    
    
    row("dsp_entry_no_4",     entry.method_ok(P.RPC_GREET()))
    
    
    
    
    row("dsp_entry_no_0",     entry.method_ok(0))
    
    
    
    
    row("dsp_entry_no_3",     entry.method_ok(P.rpc_sc(3, 0, 0, 0)))
    
    
    
    
    row("dsp_entry_no_1",     entry.method_ok(P.rpc_sc(1, 1, 2, 0)))
# --- 3: the four dtype tables -------------------------------------------------
def RPC_NINS() -> U32: 2
# :35 `f'int off{i} = ((int*)pra[1].buf.pv)[{i}];'` -- the offset subscript is i,
# the ARRAY subscript is i, and the dtype is `int` unconditionally because the
# offsets block was built by `array('I')`.
def mprog.scale_ins() -> U32: 1000000000
# ===========================================================================
# THE FIXTURES. A `Param` list per entry-renderer fixture; `agga` is the load-
# bearing one (ALU, GLOBAL, GLOBAL, ALU) because it is the only fixture where a
# compacted index counter differs from the param index.
# ===========================================================================
# the three buffers' own sizes, which is `rpc_prep_args`'s `ins + outs` argument.
def rpc.arm(sc: U32) -> U32:
  match sc:
    case 33620224: P.ARM_MMAP()
    case _: P.rpc.arm_read(sc)
# the chain's ORDER as arm ids, so it can be printed. SEVEN, not eight: `ARM_NONE`
# is :239's raise and is not an arm.
def dt_supported(base: Bool, +d: S.Dt) -> Bool:
  Bool.and(base, Bool.and(Bool.not(P.dt_is_fp8_dt(d)), Bool.not(P.dt_is_bf16_dt(d))))
# the twelve supported DTYPES in dtype.py's `__lt__` order (dtype.bend's rank order,
# which sorts on (priority, bitsize, name, fmt) -- so the order is forced). These were
# the pre-793abbb NAMES -- "signed char", "long", "half", "double" -- so `dsp_sd_0`,
# `dsp_sd_7` and `dsp_sd_11` answered `bool`/`long`/`double` where CPython answers
# `bool`/`i64`/`f64`.
def mrender.mmap(+i: U32, +nb: U32) -> String:
  String.concat(["void *buf", U32.show(i), " = mmap2(0, ", U32.show(nb), ", ",
    U32.show(P.MMAP_PROT()), ", 0x21, -1, 0); for(int rd = 0; rd < ", U32.show(nb),
    "; rd += read(0, buf", U32.show(i), "+rd, ", U32.show(nb), "-rd));"])
# :266 `{dtype} val{i}; read(0, &val{i}, {itemsize});` -- it is the dtype's OWN name
# (`_render_dtype`), NOT the `int` the GLOBAL arm of :32 uses, and the read length
# is the ITEMSIZE, so a half reads 2 and a double reads 8.
# :213 `if sc == 0x20200: pass # greating` -- the greeting arm does NOTHING, which is
# the one arm with no side effect. `dsp_rpc_hello_n` says so by pinning zero calls.
def rpc.hello(+t: P.Tr) -> P.Tr: t
# :239 the unknown-op raise. `rpc.arm` answers `ARM_NONE` and the caller turns that
# into a refusal with nothing recorded.
#
# :239 `raise RuntimeError(f"Unknown op: {sc=:X}")` -- the `:X` is UPPERCASE hex
# with NO padding, so 255 is `FF` and 0 is `0`.  The port printed the DECIMAL
# (`sc=255`), which is not what upstream's f-string says.
#
# THE HEX, and it is here because `helpers.bend` has no hex and the one in
# `renderer/tc_ptx.bend` is FIXED WIDTH (`hex4`, `hex8`), which is a different
# function: upstream's `:X` prints as many digits as the number has.
def RPC_STATUS_ERR() -> U32: 4294967295
# :194 `sc=0x04020200` -- SPELLED AS A LITERAL in Python, and it is NOT
# `rpc_sc(2,2,1,0)`. MEASURED: 67240448 against 33685760, differing by exactly the
# method byte. So a port that "helpfully" rewrote the literal as an `rpc_sc` call
# would send method 2 and the DSP would never see a greeting. THE most load-bearing
# constant in the file, and `dsp_rpc_greet_*` is its row family.
# :262 `sz = b[1][0].max_numel()*b[1][0].dtype.itemsize`. The byte count is the
# KERNEL's view of the buffer, so it is `numel * itemsize` and NOT the allocated
# size -- which for a VIEW is larger than the window the kernel touches.
def mrender.nbytes(+p: P.Param) -> U32: U32.mul(P.Param.numel(p), P.dt_itemsize_dt(P.Param.dt(p)))
# :264 `void *buf{i} = mmap2(0, {sz}, 3, 0x21, -1, 0); for(int rd = 0; rd < {sz};
# rd += read(0, buf{i}+rd, {sz}-rd));`. `0x21` is MAP_PRIVATE|MAP_ANONYMOUS. The
# `# https://gpages.juszkiewicz.com.pl/syscalls-table/syscalls.html` NOTE at :257
# is why the numbers below are named after syscalls rather than flags.
def rpc.obj_ptr(off: U32) -> U32:
  H.round_up_u32(U32.add(off, P.RPC_SIZE_BYTES()), P.RPC_OBJ_ALIGN())
def rpc.seek_ok(whence: U32) -> Bool: U32.is_eq(whence, P.APPS_STD_SEEK_SET())
def rpc.msg_status_index() -> U32: 1
# :93 `_as_buffer` is `to_mv(src.va_addr, src.size)` -- the address and the size and
# nothing else, so `alloc.as_buffer_bytes` is the size half of a WALL.
def dev.open_lib_handle(+t: P.Tr) -> U32: P.Tr.here(t)
# :150-152 `close_lib`: ONE ins of `[handle, 0xff]`, TWO outs, `rpc_sc(1,1,2)`.
def open_lib_bad(status: U32) -> Bool: U32.is_eq(U32.shrn(status, 31n), 1)
# MEASURED: `f"Cannot open lib: {msg}"` on an EMPTY message is `"Cannot open lib: "`
# WITH a trailing space, and on a non-empty one it is the same string with the
# message appended. So the space is in the PREFIX here and the message carries no
# leading space -- which is the only split that makes BOTH rows right. The trailing
# space is invisible in a diff and `String.concat` keeps it, so `dsp_ol_err_empty`
# says so in its own comment.
# --- 6: the program call, :62-71 ----------------------------------------------
def open_lib_out0() -> U32: 8
# :197 `context, inbufs, outbufs = msg_recv[0], ((sc:=msg_recv[2]) >> 16) & 0xff,
# (msg_recv[2] >> 8) & 0xff`. The reply's word 2 is the SAME selector layout
# `rpc_sc` builds, read back with shifts -- which is why `sc_ins`/`sc_outs` mask
# with 0xff rather than reading the whole shifted word.
def open_lib_err(+msg: String) -> String:
  String.concat(["RuntimeError: Cannot open lib: ", msg])
# :148 `return o1.cast('I')[0]` -- the HANDLE, which is the id the seam minted.
def t_device() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    row("dsp_mock_default",     dev.is_mock())
    # init_dsp with NO stale fd: FIVE calls, and the order IS the contract
    +f : P.Tr <- IO.pure(P.Tr, P.dev.init_dsp(False{}, Tr.of()))
    
    
    
    
    urow("dsp_init_n",     seen(f))
    
    
    
    
    urow("dsp_init_first_k",     P.first_k(P.Tr.calls(f)))
    
    
    
    
    urow("dsp_init_last_k",     P.last_k(P.Tr.calls(f)))
    
    
    
    
    lrow("dsp_init_kinds",     P.kind_list(P.Tr.calls(f)))
    
    
    
    
    row("dsp_init_order",     seq(f, [P.Call{P.CALL_ADSP_OPEN, 0},
          P.Call{P.CALL_RPC_GETINFO, 3}, P.Call{P.CALL_RPC_CONTROL, 3}, P.Call{P.CALL_RPC_INIT, 1},
          P.Call{P.CALL_RPC_INVOKE, P.SC_INIT_INVOKE}]))
    
    
    
    
    row("dsp_init_rev",     Bool.not(seq(f, [P.Call{P.CALL_RPC_CONTROL, 3},
          P.Call{P.CALL_RPC_GETINFO, 3}, P.Call{P.CALL_ADSP_OPEN, 0}])))
    
    
    
    
    lrow("dsp_init_args",     cargs(P.CALL_RPC_INVOKE(), f))
    
    
    
    
    lrow("dsp_init_args3",     cargs(P.CALL_RPC_GETINFO(), f))
    
    
    
    
    lrow("dsp_init_args4",     cargs(P.CALL_RPC_CONTROL(), f))
    
    
    
    
    lrow("dsp_init_args5",     cargs(P.CALL_RPC_INIT(), f))
    # and WITH the stale fd: SEVEN, whose first TWO are the stale-fd close. The
    # five above are a SUFFIX of this one, which is why these rows exist.
    +g : P.Tr <- IO.pure(P.Tr, P.dev.init_dsp(True{}, Tr.of()))
    
    
    
    
    urow("dsp_init_ag_n",     seen(g))
    
    
    
    
    urow("dsp_init_ag_first_k",     P.first_k(P.Tr.calls(g)))
    
    
    
    
    urow("dsp_init_ag_second_k",     P.second_k(P.Tr.calls(g)))
    
    
    
    
    lrow("dsp_init_ag_kinds",     P.kind_list(P.Tr.calls(g)))
    
    
    
    
    row("dsp_init_ag_order",     seq(g, [P.Call{P.CALL_RPC_INVOKE, P.SC_STALE},
          P.Call{P.CALL_OS_CLOSE, 98}, P.Call{P.CALL_ADSP_OPEN, 0},
          P.Call{P.CALL_RPC_GETINFO, 3}, P.Call{P.CALL_RPC_CONTROL, 3}, P.Call{P.CALL_RPC_INIT, 1},
          P.Call{P.CALL_RPC_INVOKE, P.SC_INIT_INVOKE}]))
    
    
    
    
    lrow("dsp_init_ag_invokes",     cargs(P.CALL_RPC_INVOKE(), g))
    
    
    
    
    lrow("dsp_init_ag_close",     cargs(P.CALL_OS_CLOSE(), g))
    # the two selectors
    
    
    
    
    lrow("dsp_sc_stale",     [P.SC_STALE()])
    
    
    
    
    lrow("dsp_sc_initinv",     [P.SC_INIT_INVOKE()])
    # :146,:152 the open and close selectors
    
    
    
    
    lrow("dsp_ol_sc",     [P.dev.open_lib_sc()])
    
    
    
    
    lrow("dsp_cl_sc",     [P.dev.close_lib_sc()])
    
    
    
    
    lrow("dsp_ol_f",     [P.sc_method(P.dev.open_lib_sc()), sc_ins(P.dev.open_lib_sc()),
                          sc_outs(P.dev.open_lib_sc()), sc_fds(P.dev.open_lib_sc())])
    
    
    
    
    lrow("dsp_cl_f",     [P.sc_method(P.dev.close_lib_sc()), sc_ins(P.dev.close_lib_sc()),
                          sc_outs(P.dev.close_lib_sc()), sc_fds(P.dev.close_lib_sc())])
    # :143,:145 the URL, its length INCLUDING the NUL, and the two outs
    
    
    
    
    srow("dsp_fp",     P.OPEN_LIB_FP())
    
    
    
    
    lrow("dsp_fp_len",     [P.OPEN_LIB_NAMED_LEN(), P.OPEN_LIB_NUL_LEN(), open_lib_len()])
    
    
    
    
    lrow("dsp_ol_ins",     [open_lib_len(), open_lib_ins1(), open_lib_out0(), open_lib_out1()])
    # :147 the raise -- a negative status word in o1's SECOND i32
    
    
    
    
    row("dsp_ol_bad_neg",     open_lib_bad(4294967295))
    
    
    
    
    row("dsp_ol_bad_neg2",     open_lib_bad(2147483648))
    
    
    
    
    row("dsp_ol_bad_neg3",     open_lib_bad(4294967294))
    
    
    
    
    row("dsp_ol_bad_0",     Bool.not(open_lib_bad(0)))
    
    
    
    
    row("dsp_ol_bad_pos",     Bool.not(open_lib_bad(100)))
    
    
    
    
    row("dsp_ol_bad_maxpos",     Bool.not(open_lib_bad(2147483647)))
    
    
    
    
    srow("dsp_ol_err",     open_lib_err("bad elf"))
        # the TRAILING SPACE is the point of this row and it is INVISIBLE in a diff
    
    
    
    
    srow("dsp_ol_err_empty",     open_lib_err(""))
    # the handle, :148 -- the id the seam minted
    +oh : P.Tr <- IO.pure(P.Tr, P.dev.open_lib(Tr.of()))
    
    
    
    
    lrow("dsp_ol_handle",     [dev.open_lib_handle(Tr.of()), P.Tr.next(oh)])
    # exec_lib: open, invoke-attrs, close -- and the retry after init_dsp
    +e0 : P.Tr <- IO.pure(P.Tr, P.dev.exec_lib(P.prog.exec_sc(3), False{}, False{}, Tr.of()))
    
    
    
    
    urow("dsp_exec_n",     seen(e0))
    
    
    
    
    lrow("dsp_exec_kinds",     P.kind_list(P.Tr.calls(e0)))
    
    
    
    
    row("dsp_exec_order",     seq(e0, [P.Call{P.CALL_OPEN_LIB, 131584},
          P.Call{P.CALL_RPC_INVOKE_ATTRS, 33685763}, P.Call{P.CALL_CLOSE_LIB, 16843264}]))
    
    
    
    
    row("dsp_exec_rev",     Bool.not(seq(e0, [P.Call{P.CALL_CLOSE_LIB, 16843264},
          P.Call{P.CALL_RPC_INVOKE_ATTRS, 33685763}])))
    
    
    
    
    lrow("dsp_exec_sc",     cargs(P.CALL_RPC_INVOKE_ATTRS(), e0))
    # the FIRST attempt fails: init_dsp's SEVEN, then a WHOLE new triple
    +e1 : P.Tr <- IO.pure(P.Tr, P.dev.exec_lib(P.prog.exec_sc(3), True{}, False{}, Tr.of()))
    
    
    
    
    urow("dsp_exec_retry_n",     seen(e1))
    
    
    
    
    urow("dsp_exec_retry_open",     ncalls(P.CALL_OPEN_LIB(), e1))
    # the FAILED invoke is NOT recorded -- that is what "the call did not happen" means
    
    
    
    
    urow("dsp_exec_retry_invoke",     ncalls(P.CALL_RPC_INVOKE_ATTRS(), e1))
    
    
    
    
    urow("dsp_exec_retry_close",     ncalls(P.CALL_CLOSE_LIB(), e1))
    
    
    
    
    urow("dsp_exec_retry_inits",     ncalls(P.CALL_RPC_INVOKE(), e1))
    
    
    
    
    lrow("dsp_exec_retry_kinds",     P.kind_list(P.Tr.calls(e1)))
    # and BOTH fail: the retry's invoke is a TRUNCATED trace, so it contributes
    # its open and nothing else -- 7 + 1 = 8.
    +e2 : P.Tr <- IO.pure(P.Tr, P.dev.exec_lib(P.prog.exec_sc(3), True{}, True{}, Tr.of()))
    
    
    
    
    urow("dsp_exec_fail_n",     seen(e2))
    
    
    
    
    urow("dsp_exec_fail_open",     ncalls(P.CALL_OPEN_LIB(), e2))
    
    
    
    
    urow("dsp_exec_fail_invoke",     ncalls(P.CALL_RPC_INVOKE_ATTRS(), e2))
    
    
    
    
    urow("dsp_exec_fail_close",     ncalls(P.CALL_CLOSE_LIB(), e2))
    
    
    
    
    row("dsp_exec_fail_tail",     seq(e2, [P.Call{P.CALL_RPC_INVOKE_ATTRS, 33685763},
          P.Call{P.CALL_CLOSE_LIB, 16843264}]))
    
    
    
    
    lrow("dsp_exec_fail_kinds",     P.kind_list(P.Tr.calls(e2)))
# --- 13: the listener, :178-239 ----------------------------------------------
def compile_cmd(+mock: Bool, +cc: String) -> String:
  String.concat([cc, " ", P.compiler_args_first(mock), " ", P.COMPILER_ARGS(),
    Bool.pick(String, P.compiler_args_has_T(mock), P.LINK_SCRIPT_ARG(), ""),
    " ", P.COMPILE_TAIL()])
# ===========================================================================
# DSPDevice, :128-176. THE init sequence and the three lib calls.
# ===========================================================================
# :129 `if getenv("MOCKDSP"):` -- ONE branch, and it selects FOUR things at once:
# the renderer (MockDSPRenderer against DSPRenderer), the program (MockDSPProgram
# against DSPProgram), the allocator (`DSPAllocator(self)` either way), and whether
# the whole ION/adsprpc bring-up happens at all.
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
def rpc.obj_count(inbufs: U32, outbufs: U32) -> U32: U32.add(inbufs, outbufs)
# the seven arms' ARGUMENT COUNTS, which is the pure part of WALL 3:
#   :215 open   in_args[3] is the NAME, out_args[0] is the fd
#   :218 close  in_args[0] is the fd
#   :220 seek   in_args[0] is (fd, offset, whence)
#   :225 read   in_args[0] is (fd, count), out_args[0..1]
#   :232 stat   in_args[1] is the PATH, out_args[0] is apps_std_STAT
#   :236 mmap   in_args[0] is (prot, flags, size), out_args[0]
# :148 `return o1.cast('I')[0]` -- the HANDLE, which is the id the seam minted.
def mrender.val(+i: U32, +p: P.Param) -> String:
  String.concat([P.Param.cn(p), " val", U32.show(i), "; read(0, &val",
    U32.show(i), ", ", U32.show(P.dt_itemsize_dt(P.Param.dt(p))), ");"])
# :268 `params` is `(void*)buf{i}` for a GLOBAL -- THE CAST the real shim does not
# need, because `HAP_mmap` already returns `void*` -- and bare `val{i}` otherwise.
# :121 the command, a STRING function of `args` and `CC`. `CC` is `getenv('CC',
# 'clang')` and is a parameter here, the way helpers.bend's Flags threads getenv.
def CC_DEFAULT() -> String: "clang"
# :111 `self.args = f"-shared {compiler_args} -T{self.link_ld.name}"` -- the `-T`
# slot is the LINK SCRIPT's tempfile name, so it is `<TMP>` for the same reason
# the `-o` slot is.  It was `/tmp/dsp_link.ld`, a path the port never creates.
# :13,:14 the two class attributes the generated C depends on
def BUFFER_SUFFIX() -> String: " restrict __attribute__((align_value(128)))"
def rpc.out_len_zero() -> U32: 0
# :192 `msg_send[:] = array.array('I', [context, status, req_args[1].buf.len,
# in_buf.nbytes])` -- FOUR words, and the two that MOVE are the status and the
# response length.
# :71 `return timer[0] / 1e6`. WALL 4 records the read; the DIVISOR is ported
# because it is the one number the seam must agree with the port on.
def prog.scale_micros() -> U32: 1000000
# `nvals` is NOT an argument of `Program.__call__`'s trace -- it changes
# `var_vals_mv`'s length and nothing else -- so it is a parameter here because the
# packer `prog.pra_lens` needs it and the trace does not. That asymmetry is real:
# :62's `vals` reach the device only as bytes inside ins[0].
def SC_OPEN() -> U32: 319095040
def RPC_STATUS_OK() -> U32: 0
# :147 `if o1.cast('i')[1] < 0: raise RuntimeError(f"Cannot open lib:
# {o2.tobytes().decode()}")`. o1 is 8 bytes = TWO i32s and the SECOND is the status;
# o2 is the 255-byte message. The raise is the truncation.
# `o1.cast('i')[1] < 0` is a SIGNED 32-bit test, and a U32 cannot answer it --
# `U32.is_lt(4294967295, 0)` is False. The faithful reading is the TOP BIT, which is
# exactly what `cast('i')` looks at. MEASURED against CPython's own signed value
# for each of the six fixtures in `dsp_ol_bad_*`.
def prog.run(+nbufs: U32, nvals: U32, t: P.Tr) -> P.Tr:
  P.prog.call(P.prog.too_many(nbufs), nbufs, t)
# ===========================================================================
# DSPBuffer and DSPAllocator, :73-96.
# ===========================================================================
# the buffer arms first, then the dma arms -- :56 fills `ins + outs` and
# `rpc_prep_args` appends the fds' slots after, so the ORDER is ins, outs, fds.
def t_call() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    urow("dsp_exec_sc_0",     P.prog.exec_sc(0))
    
    
    
    
    urow("dsp_exec_sc_1",     P.prog.exec_sc(1))
    
    
    
    
    urow("dsp_exec_sc_3",     P.prog.exec_sc(3))
    
    
    
    
    urow("dsp_exec_sc_7",     P.prog.exec_sc(7))
    
    
    
    
    urow("dsp_exec_sc_15",     P.prog.exec_sc(15))
    
    
    
    
    urow("dsp_exec_sc_16",     P.prog.exec_sc(16))
    
    
    
    
    lrow("dsp_exec_sc_f",     [sc_fds(P.prog.exec_sc(7))])
    
    
    
    
    lrow("dsp_exec_sc_i",     [sc_ins(P.prog.exec_sc(7))])
    
    
    
    
    lrow("dsp_exec_sc_o",     [sc_outs(P.prog.exec_sc(7))])
    
    
    
    
    lrow("dsp_exec_sc_m",     [P.sc_method(P.prog.exec_sc(7))])
    
    
    
    
    row("dsp_toomany_15",     Bool.not(P.prog.too_many(15)))
    
    
    
    
    row("dsp_toomany_16",     P.prog.too_many(16))
    
    
    
    
    row("dsp_toomany_17",     P.prog.too_many(17))
    # the trace for a legal call
    +ok : P.Tr <- IO.pure(P.Tr, prog.run(3, 2, Tr.of()))
    
    
    
    
    urow("dsp_call_ok_n",     seen(ok))
    
    
    
    
    urow("dsp_call_ok_sc",     first(cargs(P.CALL_EXEC_LIB(), ok)))
    
    
    
    
    row("dsp_call_ok_flag",     Bool.not(Tr.refused(ok)))
    # and for a refused one: :63 raises BEFORE the call, so nothing is recorded
    +no : P.Tr <- IO.pure(P.Tr, prog.run(16, 0, Tr.of()))
    
    
    
    
    urow("dsp_call_16_n",     seen(no))
    
    
    
    
    row("dsp_call_16_refused",     Tr.refused(no))
    # and a refusal BLOCKS everything after it, so a legal call behind a refused
    # one records nothing. :63's raise is not a flag, it is the end of the program.
    +blk : P.Tr <- IO.pure(P.Tr, prog.run(1, 0, prog.run(16, 0, Tr.of())))
    
    
    
    
    urow("dsp_call_blocked_n",     seen(blk))
    
    
    
    
    row("dsp_call_blocked_flag",     Tr.refused(blk))
    # :71 and :292 -- two programs, TWO SCALES
    
    
    
    
    lrow("dsp_scale_real",     [prog.scale_micros()])
    
    
    
    
    lrow("dsp_scale_mock",     [mprog.scale_ins()])
    
    
    
    
    lrow("dsp_scale_gap",     [U32.sub(mprog.scale_ins(), prog.scale_micros())])
    
    
    
    
    lrow("dsp_timer_b",     [P.TIMER_BYTES()])
    # and a refused call AFTER a legal one leaves the earlier call intact
    +mix : P.Tr <- IO.pure(P.Tr, prog.run(16, 0, prog.run(1, 0, Tr.of())))
    
    
    
    
    urow("dsp_call_mix_n",     seen(mix))
    
    
    
    
    urow("dsp_call_mix_sc",     first(cargs(P.CALL_EXEC_LIB(), mix)))
# --- 7: the entry shim, :27-44 -----------------------------------------------
def RPC_GREET_IS_EXEC() -> Bool: U32.is_eq(P.RPC_GREET(), P.rpc_sc(P.M_INVOKE(), 2, 1, 0))
# the seven `sc` values the loop dispatches on, taken from the elif chain at
# :213-238. The chain's ORDER is not the numeric order, so `rpc.arm` is a table and
# `dsp_rpc_arms` is its image.
#
# THE seven literals, READ out of upstream'S own source at
#   :213 `if sc == 0x20200: pass`          :213  0x0020200
#   :214 `elif sc == 0x13050100: # open`   :214  0x13050100
#   :217 `elif sc == 0x3010000:`           :217  0x03010000
#   :219 `elif sc == 0x9010000: # seek`    :219  0x09010000
#   :225 `elif sc == 0x4010200: # read`    :225  0x04010200
#   :232 `elif sc == 0x1f020100: # stat`   :232  0x1f020100
#   :236 `elif sc == 0x2010100: # mmap`    :236  0x02010100
# FIVE of the seven HERE were WRONG: 0x0BE00000, 0x09002600, 0x04004000,
# 0x01DC0000 and 0x02010000 are in NO upstream revision -- `git log --all -S` finds
# no such constant in `tinygrad/runtime/ops_dsp.py` at all -- and a port that
# dispatches on them NEVER reaches upstream's arms.  `dsp_rpc_scs` is the row
# that pins all seven, and `dsp_rpc_reply_io` and `dsp_rpc_seek_err` are the two
# that read a wrong selector out of it.
def rpc.reply_sc_index() -> U32: 2
# --- 13: the listener, :178-239 ----------------------------------------------
def rpc.reply_context_index() -> U32: 0
# :201 `round_up(in_ptr + 4, 8) if i < inbufs else round_up(out_ptr + 4, 8)`.
# THE OBJECT POINTER, and it is upstream's OWN expression: the size field is four
# bytes and the object that follows it is 8-ALIGNED, so the object starts at
# `round_up(off + 4, 8)`.  The formula here used to be `8 - (off mod 8)`, which
# is the distance to the NEXT 8-boundary and is NOT upstream's expression: it
# answers 8 for an already-aligned offset, and the comment beside it said "the
# padding is 0 or 4 and NEVER 8" -- so the row contradicted its own comment.
# The PADDING is the difference between the aligned pointer and the unaligned
# one, and it is 0..7 and not 0 or 4, because upstream's `in_ptr` advances by
# `obj_ptr + obj_size` and `obj_size` is arbitrary.
def rpc.msg_len_index() -> U32: 2
def rpc.cnts() -> List<&2, U32>: P.rpc.cnt_table(P.rpc.arm_ids(), Nil{})
# :221 `assert in_args[0].cast('I')[2] == APPS_STD_SEEK_SET, "Supported only
# SEEK_SET"` -- the only assert in the file, and it is a refusal. SEEK_SET is 0 in
# apps_std, which is why SEEK_CUR and SEEK_END are both refused.
def SC_CLOSE() -> U32: 50397184
def SC_STAT() -> U32: 520225024
def rpc.unknown_err(+sc: U32) -> String:
  String.concat(["RuntimeError: Unknown op: sc=", P.u32_hex(sc)])
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
# --- 8: the mock shim, :256-274 ----------------------------------------------
def t_rpc() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    lrow("dsp_rpc_greet",     [P.RPC_GREET()])
    
    
    
    
    lrow("dsp_rpc_greet_f",     [P.sc_method(P.RPC_GREET()), sc_ins(P.RPC_GREET()),
                                 sc_outs(P.RPC_GREET()), sc_fds(P.RPC_GREET())])
    
    
    
    
    row("dsp_rpc_greet_ne",     Bool.not(RPC_GREET_IS_EXEC()))
    
    
    
    
    lrow("dsp_rpc_greet_gap",     [U32.sub(P.RPC_GREET(), P.rpc_sc(P.M_INVOKE(), 2, 1, 0))])
    # the seven arms. The ORDER of the elif chain is not the numeric order.
    
    
    
    
    lrow("dsp_rpc_arms",     P.rpc.arm_ids())
    
    
    
    
    urow("dsp_rpc_narms",     U32.from_nat(List.length(&2, U32, P.rpc.arm_ids())))
    
    
    
    
    lrow("dsp_rpc_a_hello",     [rpc.arm(131584)])
    
    
    
    
    lrow("dsp_rpc_a_open",     [rpc.arm(SC_OPEN())])
    
    
    
    
    lrow("dsp_rpc_a_close",     [rpc.arm(50397184)])
    
    
    
    
    lrow("dsp_rpc_a_seek",     [rpc.arm(SC_SEEK())])
    
    
    
    
    lrow("dsp_rpc_a_read",     [rpc.arm(SC_READ())])
    
    
    
    
    lrow("dsp_rpc_a_stat",     [rpc.arm(SC_STAT())])
    
    
    
    
    lrow("dsp_rpc_a_mmap",     [rpc.arm(SC_MMAP())])
    
    
    
    
    lrow("dsp_rpc_a_greet",     [rpc.arm(P.RPC_GREET())])
    
    
    
    
    lrow("dsp_rpc_a_exec",     [rpc.arm(P.prog.exec_sc(3))])
    
    
    
    
    lrow("dsp_rpc_a_0",     [rpc.arm(0)])
    
    
    
    
    lrow("dsp_rpc_a_1",     [rpc.arm(1)])
    
    
    
    
    lrow("dsp_rpc_a_max",     [rpc.arm(4294967295)])
    # the seven sc values, and the fact that two NON-arms are absent
    
    
    
    
    lrow("dsp_rpc_scs",     [SC_HELLO(), SC_OPEN(), SC_CLOSE(), SC_SEEK(),
                             SC_READ(), SC_STAT(), SC_MMAP()])
    # :185 the three initial values
    
    
    
    
    lrow("dsp_rpc_init",     [RPC_CONTEXT(), RPC_STATUS_OK(),
                              RPC_STATUS_ERR(), H_TINYFD()])
    # :186-188 the listener's OWN block: 2 ins of 0x10 and 2 outs of 0x10000
    
    
    
    
    lrow("dsp_rpc_lens",     rpc.lens())
    
    
    
    
    lrow("dsp_rpc_npq",     [RPC_NINS(), RPC_NOUTS(),
                             pra_len(RPC_NINS(), RPC_NOUTS(), 0)])
    
    
    
    
    lrow("dsp_rpc_outlen",     [rpc.out_len_index(), rpc.out_len_zero()])
    # :192 msg_send's four words -- the two that MOVE
    
    
    
    
    lrow("dsp_rpc_msg_ix",     [rpc.msg_status_index(), rpc.msg_len_index(),
                                rpc.msg_inbytes_index()])
    # :197 the reply's word 2 is the same selector layout
    
    
    
    
    lrow("dsp_rpc_reply_ix",     [rpc.reply_context_index(), rpc.reply_sc_index()])
    
    
    
    
    lrow("dsp_rpc_reply_io",     [sc_ins(SC_OPEN()), sc_outs(SC_OPEN()),
                                  sc_ins(67240448), sc_outs(67240448)])
    # :201 round_up(ptr+4, 8) -- the padding is 0 or 4 and NEVER 8
    
    
    
    
    lrow("dsp_rpc_objptr",     [rpc.obj_ptr(0), rpc.obj_ptr(1), rpc.obj_ptr(4),
                                rpc.obj_ptr(5), rpc.obj_ptr(8), rpc.obj_ptr(12)])
    
    
    
    
    lrow("dsp_rpc_geom",     [P.RPC_OBJ_ALIGN(), P.RPC_SIZE_BYTES(),
                              rpc.obj_count(1, 2), rpc.obj_count(0, 0),
                              rpc.obj_count(3, 3)])
    # :221 the only assert -- SEEK_SET only, so SEEK_CUR and SEEK_END are refused
    
    
    
    
    row("dsp_rpc_seek_0",     rpc.seek_ok(0))
    
    
    
    
    row("dsp_rpc_seek_1",     Bool.not(rpc.seek_ok(1)))
    
    
    
    
    row("dsp_rpc_seek_2",     Bool.not(rpc.seek_ok(2)))
    
    
    
    
    srow("dsp_rpc_seek_err",     rpc.seek_err(SC_SEEK()))
    # :213 the greeting arm does NOTHING
    
    
    
    
    urow("dsp_rpc_hello_n",     seen(rpc.hello(Tr.of())))
    # :239 the unknown-op raise
    
    
    
    
    srow("dsp_rpc_unknown",     rpc.unknown_err(255))
    
    
    
    
    srow("dsp_rpc_unknown0",     rpc.unknown_err(0))
    # the arms' in/out argument counts, interleaved nin/nout
    
    
    
    
    lrow("dsp_rpc_cnt",     rpc.cnts())
# --- 14: the mock program's wire format, :283-292 ---------------------------
def cfop_removed() -> U32: U32.sub(P.CFOP_CLANG(), P.CFOP_DSP())
# ===========================================================================
# rpc_prep_args, :49-57. THREE pure functions of three counts, and they are the
# device contract six other units are porting.
# ===========================================================================
# :52-54. One `pra` and THREE arrays, all of length `len(ins)+len(outs)+
# len(in_fds)`, so `pra_len` is what every row below is sized by.
# the device nodes (:132, :172), the shell image (:134), its alignment (:135)
def DEV_ION() -> String: "/dev/ion"
def LINK_ALIGN() -> U32: 4096
def compiler.del_unlinks(mock: Bool) -> Bool: Bool.not(mock)
# :121 the command, a STRING function of `args` and `CC`. `CC` is `getenv('CC',
# 'clang')` and is a parameter here, the way helpers.bend's Flags threads getenv.
# :94 `_copyin` is `ctypes.memmove(dest.va_addr, mv_address(src), src.nbytes)` and
# :95 `_copyout` is `ctypes.memmove(mv_address(dest), src.va_addr, dest.nbytes)`.
# THE ASYMMETRY IS REAL: `src.nbytes` going in, `dest.nbytes` coming out. A port
# that read one field for both would be wrong for a view.
def compiler.cachekey_on(+mock: Bool, +ccache: Bool) -> Bool:
  Bool.not(String.eq(P.compiler.cachekey_of(mock, ccache), ""))
# :104-105 the fifteen sections the link script aligns to 4k. "Aligning all used
# sections to 4k fixes invoke problem" -- the NOTE is the reason and is kept.
def t_compiler() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    srow("dsp_args",     P.COMPILER_ARGS())
    
    
    
    
    srow("dsp_args_first_m",     P.compiler_args_first(True{}))
    
    
    
    
    srow("dsp_args_first_r",     P.compiler_args_first(False{}))
    
    
    
    
    row("dsp_args_T_r",     P.compiler_args_has_T(False{}))
    
    
    
    
    row("dsp_args_T_m",     Bool.not(P.compiler_args_has_T(True{})))
    
    
    
    
    row("dsp_unlink_r",     compiler.del_unlinks(False{}))
    
    
    
    
    row("dsp_unlink_m",     Bool.not(compiler.del_unlinks(True{})))
    
    
    
    
    srow("dsp_ck_r",     P.compiler.cachekey_of(False{}, True{}))
    
    
    
    
    srow("dsp_ck_m",     P.compiler.cachekey_of(True{}, True{}))
    
    
    
    
    srow("dsp_ck_nc",     P.compiler.cachekey_of(False{}, False{}))
    
    
    
    
    row("dsp_ck_on_r",     compiler.cachekey_on(False{}, True{}))
    
    
    
    
    row("dsp_ck_on_m",     Bool.not(compiler.cachekey_on(True{}, True{})))
    
    
    
    
    row("dsp_ck_on_nc",     Bool.not(compiler.cachekey_on(False{}, False{})))
    # device.py:340 -- a None cachekey OR a miss means compile
    
    
    
    
    row("dsp_nc_mock_hit",     D.needs_compile(False{}, True{}))
    
    
    
    
    row("dsp_nc_real_hit",     Bool.not(D.needs_compile(True{}, True{})))
    
    
    
    
    row("dsp_nc_real_miss",     D.needs_compile(True{}, False{}))
    # the fifteen sections
    
    
    
    
    urow("dsp_link_n",     U32.from_nat(List.length(&2, String, P.link_sections())))
    
    
    
    
    srow("dsp_link_0",     P.link_section(0n))
    
    
    
    
    srow("dsp_link_1",     P.link_section(1n))
    
    
    
    
    srow("dsp_link_7",     P.link_section(7n))
    
    
    
    
    srow("dsp_link_9",     P.link_section(9n))
    
    
    
    
    srow("dsp_link_13",     P.link_section(13n))
    
    
    
    
    srow("dsp_link_14",     P.link_section(14n))
    
    
    
    
    srow("dsp_link_line",     P.link_line("text"))
    
    
    
    
    srow("dsp_link_line2",     P.link_line("got.plt"))
    # and the WHOLE script, diffed as a string because String.concat drops a literal
    
    
    
    
    srow("dsp_link_script",     link_script())
      #     ... /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }
    
    
    
    
    urow("dsp_link_align",     LINK_ALIGN())
    # the command line, as a string function of mock and CC
    
    
    
    
    srow("dsp_cmd_m",     compile_cmd(True{}, "clang"))
    
    
    
    
    srow("dsp_cmd_r",     compile_cmd(False{}, "clang"))
    
    
    
    
    srow("dsp_cmd_cc",     compile_cmd(True{}, "gcc"))
    
    
    
    
    row("dsp_cmd_cc_used",     Bool.not(String.eq(compile_cmd(True{}, "gcc"),
          compile_cmd(True{}, CC_DEFAULT()))))
    
    
    
    
    row("dsp_cmd_mock_used",     Bool.not(String.eq(compile_cmd(True{}, "clang"),
          compile_cmd(False{}, "clang"))))
    
    
    
    
    srow("dsp_suffix",     BUFFER_SUFFIX())
    
    
    
    
    srow("dsp_typedef",     KERNEL_TYPEDEF())
    # :18 `self.target, self.compiler = target, DSPCompiler()` -- the renderer builds
    # the DSP compiler and NOT super().__init__, because the CPU clang compiler
    # raises on a hexagon arch. `dsp_no_super_init` is that measurement.
    
    
    
    
    row("dsp_no_super_init",     dev.branch_same_alloc())
    
    
    
    
    srow("dsp_dev_node_ion",     DEV_ION())
    
    
    
    
    srow("dsp_dev_node_adsp",     DEV_ADSP())
    
    
    
    
    srow("dsp_shell_path",     SHELL_PATH())
# --- 12: the device init and the three lib calls, :128-176 --------------------
# :81 `ION_IOC_ALLOC(self.dev.ion_fd, len=size, align=0x200,
# heap_id_mask=1<<ION_SYSTEM_HEAP_ID, flags=ION_FLAG_CACHED)`.
def dt_fmt_has_count() -> U32: P.count_fmt(P.NAMES(), 0)
# ===========================================================================
# THE GATE. Every `py=` half below is DERIVED -- the port's OWN value, re-read
# through the same code the port prints -- so a row cannot disagree with itself
# and there is no transcription left to rot.  The ASSERTION is the byte diff
# against CPython's lane, and CPython's lane is
# `gates/ops_dsp_render-oracle.py`, RECOVERED from git history (blob
# `291bbc8821dafb2ae0b8c464488d4b02300ced6b`, commit `192142295` -- the commit
# that made this file's rows compared in the first place).  Before the recovery
# the oracle lived in `.agents/slop/`, which was pruned: a gate with no oracle is
# a gate that CANNOT FAIL, and this one could not.
# ===========================================================================
# A ROW IS A COMPARISON. All four print the port's OWN value twice -- once as the
# answer and once as the `py=` half -- so the lane is a `diff` against
# `gates/ops_dsp_render-oracle.py` rather than 512 lines nobody compared. They used to
# print `nm=value` and carry the expectation in a `# py=` COMMENT, which is the same
# file on both sides of the comparison -- `dsp_gate_check.py` says so on every run and
# calls itself "AUTHORITY: NONE". The row count did not change and neither did the
# file's green; only this did. They then took CPython's answer as a THIRD argument,
# which was a TRANSCRIPTION of what CPython said once, and a transcription has no
# generator: it cannot see CPython move, and it cannot see the PORT move either --
# MEASURED 2026-10-22, thirty of these rows' `py=` halves were RIGHT while the
# `got=` half beside them was WRONG, so the file agreed with itself and was wrong on
# thirty rows. The `py=` half is now DERIVED -- the port's own value, re-read -- and
# the comparison is against CPython's lane, byte for byte.
def SYSCALL_WRITE() -> U32: 64
def mrender.exit() -> String: "exit(0); }"
# :262 `sz = b[1][0].max_numel()*b[1][0].dtype.itemsize`. The byte count is the
# KERNEL's view of the buffer, so it is `numel * itemsize` and NOT the allocated
# size -- which for a VIEW is larger than the window the kernel touches.
def MOCK_MMAP_FLAGS() -> U32: 33
def t_rpcsc() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    urow("dsp_sc_0000",     P.rpc_sc(0, 0, 0, 0))
    
    
    
    
    urow("dsp_sc_2210",     P.rpc_sc(2, 2, 1, 0))
    
    
    
    
    urow("dsp_sc_open",     P.rpc_sc(0, 2, 2, 0))
    
    
    
    
    urow("dsp_sc_close",     P.rpc_sc(1, 1, 2, 0))
    
    
    
    
    urow("dsp_sc_2000",     P.rpc_sc(2, 0, 0, 0))
    
    
    
    
    urow("dsp_sc_3000",     P.rpc_sc(3, 0, 0, 0))
    
    
    
    
    urow("dsp_sc_2211",     P.rpc_sc(2, 2, 1, 1))
    
    
    
    
    urow("dsp_sc_22115",     P.rpc_sc(2, 2, 1, 15))
    
    
    
    
    urow("dsp_sc_22116",     P.rpc_sc(2, 2, 1, 16))
    
    
    
    
    urow("dsp_sc_max",     P.rpc_sc(255, 255, 255, 255))
    
    
    
    
    urow("dsp_sc_f255",     P.rpc_sc(0, 0, 0, 255))
    
    
    
    
    urow("dsp_sc_m1",     P.rpc_sc(1, 0, 0, 0))
    
    
    
    
    urow("dsp_sc_i1",     P.rpc_sc(0, 1, 0, 0))
    
    
    
    
    urow("dsp_sc_o1",     P.rpc_sc(0, 0, 1, 0))
    
    
    
    
    urow("dsp_sc_2213",     P.rpc_sc(2, 2, 1, 3))
    
    
    
    
    urow("dsp_sc_2217",     P.rpc_sc(2, 2, 1, 7))
    
    
    
    
    urow("dsp_sc_2218",     P.rpc_sc(2, 2, 1, 8))
    # the four fields are INDEPENDENT, which is what lets fds up to 15 and outs=1
    
    
    
    
    lrow("dsp_sc_f255_only",     [sc_fds(255)])
    
    
    
    
    lrow("dsp_sc_o255_only",     [sc_outs(P.rpc_sc(0, 0, 255, 0))])
    
    
    
    
    lrow("dsp_sc_i255_only",     [sc_ins(P.rpc_sc(0, 255, 0, 0))])
    
    
    
    
    lrow("dsp_sc_m255_only",     [P.sc_method(P.rpc_sc(255, 0, 0, 0))])
# --- 2: the selector's two readers, and the entry shim's refusal -------------
def t_mock() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    srow("dsp_m_start",     mrender.start())
    
    
    srow("dsp_m_stamp",     mrender.stamp())
    
    
    srow("dsp_m_finish",    mrender.finish())
    
    
    srow("dsp_m_exit",      mrender.exit())
    
    
    
    
    srow("dsp_m_mm0",     mrender.mmap(0, 4))
    
    
    srow("dsp_m_mm1",     mrender.mmap(1, 16))
    
    
    
    
    srow("dsp_m_mm2",     mrender.mmap(2, 8))
    # :266 the val read -- the dtype's OWN name and the ITEMSIZE as the length
    
    
    
    
    srow("dsp_m_v0",     mrender.val(0, P.fx.a(S.uint32(), 1)))
    
    
    
    
    srow("dsp_m_v1",     mrender.val(1, P.fx.a(S.single(), 1)))
    
    
    
    
    srow("dsp_m_v2",     mrender.val(2, P.fx.a(S.int32(), 1)))
    
    
    
    
    srow("dsp_m_v3",     mrender.val(3, P.fx.a(S.int32(), 1)))
    
    
    
    
    srow("dsp_m_v4",     mrender.val(4, P.fx.a(S.int64(), 1)))
    
    
    
    
    srow("dsp_m_v5",     mrender.val(5, P.fx.a(S.half(), 1)))
    
    
    
    
    srow("dsp_m_v6",     mrender.val(6, P.fx.a(S.int8(), 1)))
    # :268 the (void*) cast the real shim does not need
    
    
    
    
    srow("dsp_m_ag0",     mrender.arg_name(0, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_m_ag1",     mrender.arg_name(1, P.fx.g(S.single(), 4)))
    
    
    
    
    srow("dsp_m_aa0",     mrender.arg_name(0, P.fx.a(S.uint32(), 1)))
    
    
    
    
    srow("dsp_m_ag2",     mrender.arg_name(2, P.fx.a(S.single(), 1)))
    # :272 the output write
    
    
    
    
    srow("dsp_m_w0",     mrender.emit(0, 4))
    
    
    
    
    srow("dsp_m_w1",     mrender.emit(1, 16))
    # :262 the byte count is max_numel*itemsize, NOT the allocated size
    
    
    
    
    lrow("dsp_m_nb_u32_1",     [mrender.nbytes(P.fx.g(S.uint32(), 1))])
    
    
    
    
    lrow("dsp_m_nb_f32_4",     [mrender.nbytes(P.fx.g(S.single(), 4))])
    
    
    
    
    lrow("dsp_m_nb_f32_2",     [mrender.nbytes(P.fx.g(S.single(), 2))])
    
    
    
    
    lrow("dsp_m_nb_f64_2",     [mrender.nbytes(P.fx.g(S.double(), 2))])
    
    
    
    
    lrow("dsp_m_nb_f16_3",     [mrender.nbytes(P.fx.g(S.half(), 3))])
    
    
    
    
    lrow("dsp_m_nb_u8_7",     [mrender.nbytes(P.fx.g(S.uint8(), 7))])
    
    
    
    
    lrow("dsp_m_nb_i64_1",     [mrender.nbytes(P.fx.g(S.int64(), 1))])
    
    
    
    
    lrow("dsp_m_nb_bf16_2",     [mrender.nbytes(P.fx.g(S.bfloat16(), 2))])
    # the gpages syscall numbers, named at :257
    
    
    
    
    lrow("dsp_m_sys",     [SYSCALL_READ(), SYSCALL_WRITE(), SYSCALL_EXIT(),
                           SYSCALL_MMAP2(), HEX_REG_QEMU_INSN_CNT(),
                           INSN_CNT_WORD(), MOCK_MMAP_FLAGS(), P.MMAP_PROT()])
    
    
    
    
    lrow("dsp_m_boiler",     [boiler_lines(), P.boiler_first_len()])
    
    
    
    
    lrow("dsp_m_boiler_has_syscall",     [u32_of_str(P.mockdsp_boilerplate(), "syscall")])
    
    
    
    
    lrow("dsp_m_boiler_has_read",     [u32_of_str(P.mockdsp_boilerplate(), "read")])
    
    
    
    
    lrow("dsp_m_boiler_has_write",     [u32_of_str(P.mockdsp_boilerplate(), "write")])
    
    
    
    
    lrow("dsp_m_boiler_has_exit",     [u32_of_str(P.mockdsp_boilerplate(), "exit")])
    
    
    
    
    lrow("dsp_m_boiler_has_mmap2",     [u32_of_str(P.mockdsp_boilerplate(), "mmap2")])
    
    
    
    
    lrow("dsp_m_boiler_has_inscount",     [u32_of_str(P.mockdsp_boilerplate(), "inscount")])
# --- 9: the allocator, :73-96 -------------------------------------------------
def t_reader() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.dev.init_dsp(True{}, Tr.of()))
    
    
    
    
    row("dsp_has_ok",     seq(t, [P.Call{P.CALL_ADSP_OPEN, 0}, P.Call{P.CALL_RPC_GETINFO, 3}]))
    
    
    
    
    row("dsp_has_rev",     Bool.not(seq(t, [P.Call{P.CALL_RPC_GETINFO, 3},
          P.Call{P.CALL_ADSP_OPEN, 0}])))
    
    
    
    
    row("dsp_has_absent",     Bool.not(seq(t, [P.Call{P.CALL_ADSP_OPEN, 99}])))
    
    
    
    
    row("dsp_has_wrongarg",     Bool.not(seq(t, [P.Call{P.CALL_ADSP_OPEN, 0},
          P.Call{P.CALL_RPC_GETINFO, 99}])))
    
    
    
    
    row("dsp_has_kind",     seq(t, [P.Call{P.CALL_ADSP_OPEN, 0}]))
    
    
    
    
    row("dsp_has_wrongkind",     Bool.not(seq(t, [P.Call{P.CALL_MMAP, 0}])))
    
    
    
    
    row("dsp_has_empty",     seq(t, Nil{}))
    # a pattern LONGER than the trace -- a matcher with the PATTERN's fuel says True
    
    
    
    
    row("dsp_has_long",     Bool.not(seq(t, [P.Call{P.CALL_RPC_INVOKE, P.SC_STALE},
          P.Call{P.CALL_OS_CLOSE, 98}, P.Call{P.CALL_ADSP_OPEN, 0},
          P.Call{P.CALL_RPC_GETINFO, 3}, P.Call{P.CALL_RPC_CONTROL, 3}, P.Call{P.CALL_RPC_INIT, 1},
          P.Call{P.CALL_RPC_INVOKE, P.SC_INIT_INVOKE}, P.Call{P.CALL_RPC_INVOKE, P.SC_INIT_INVOKE}])))
    # and one on an EMPTY trace
    
    
    
    
    row("dsp_has_emptytr",     Bool.not(seq(Tr.of(), [P.Call{P.CALL_ADSP_OPEN, 0}])))
    # the trace reader itself
    
    
    
    
    urow("dsp_rd_n",     seen(t))
    
    
    
    
    urow("dsp_rd_invoke",     ncalls(P.CALL_RPC_INVOKE(), t))
    
    
    
    
    urow("dsp_rd_init",     ncalls(P.CALL_RPC_INIT(), t))
    
    
    
    
    urow("dsp_rd_mmap",     ncalls(P.CALL_MMAP(), t))
    
    
    
    
    lrow("dsp_rd_invoke_args",     cargs(P.CALL_RPC_INVOKE(), t))
    
    
    
    
    lrow("dsp_rd_kinds",     P.kind_list(P.Tr.calls(t)))
# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the BUF head goes FIRST and the
# DMA tail second. Writing it the other way round is a bug this gate's first run
# found: `dsp_attr_2213` answered `1,1,1,0,0,0`.
def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    
    
    
    
    srow("dsp_fmt_bool",     P.dt_fmt_dt(S.boolean()))
    
    
    
    
    srow("dsp_fmt_schar",     P.dt_fmt_dt(S.int8()))
    
    
    
    
    srow("dsp_fmt_uchar",     P.dt_fmt_dt(S.uint8()))
    
    
    
    
    srow("dsp_fmt_short",     P.dt_fmt_dt(S.int16()))
    
    
    
    
    srow("dsp_fmt_ushort",     P.dt_fmt_dt(S.uint16()))
    
    
    
    
    srow("dsp_fmt_int",     P.dt_fmt_dt(S.int32()))
    
    
    
    
    srow("dsp_fmt_uint",     P.dt_fmt_dt(S.uint32()))
    
    
    
    
    srow("dsp_fmt_long",     P.dt_fmt_dt(S.int64()))
    
    
    
    
    srow("dsp_fmt_ulong",     P.dt_fmt_dt(S.uint64()))
    
    
    
    
    srow("dsp_fmt_half",     P.dt_fmt_dt(S.half()))
    
    
    
    
    srow("dsp_fmt_float",     P.dt_fmt_dt(S.single()))
    
    
    
    
    srow("dsp_fmt_double",     P.dt_fmt_dt(S.double()))
    # the SIX with `fmt is None`: void, weakint, weakfloat, four fp8s, bfloat16.
    
    
    
    
    row("dsp_fmt_no_void",     Bool.not(P.dt_has_fmt_dt(S.void())))
    
    
    
    
    row("dsp_fmt_no_weakint",     Bool.not(P.dt_has_fmt_dt(S.weakint())))
    
    
    
    
    row("dsp_fmt_no_weakfloat",     Bool.not(P.dt_has_fmt_dt(S.weakfloat())))
    
    
    
    
    row("dsp_fmt_no_bf16",     Bool.not(P.dt_has_fmt_dt(S.bfloat16())))
    
    
    
    
    row("dsp_fmt_no_fp8",     Bool.not(P.dt_has_fmt_dt(S.fp8e4m3())))
    
    
    
    
    urow("dsp_fmt_has_n",     dt_fmt_has_count())
    # and the twelve that DO have one -- so 12 + 8 = 20 and nothing is unaccounted.
    
    
    
    
    urow("dsp_fmt_all_n",     dt_fmt_all_count())
    # itemsize, including the two 100-byte placeholders
    
    
    
    
    urow("dsp_isz_void",     P.dt_itemsize_dt(S.void()))
    
    
    
    
    urow("dsp_isz_bool",     P.dt_itemsize_dt(S.boolean()))
    
    
    
    
    urow("dsp_isz_schar",     P.dt_itemsize_dt(S.int8()))
    
    
    
    
    urow("dsp_isz_short",     P.dt_itemsize_dt(S.int16()))
    
    
    
    
    urow("dsp_isz_half",     P.dt_itemsize_dt(S.half()))
    
    
    
    
    urow("dsp_isz_bf16",     P.dt_itemsize_dt(S.bfloat16()))
    
    
    
    
    urow("dsp_isz_int",     P.dt_itemsize_dt(S.int32()))
    
    
    
    
    urow("dsp_isz_float",     P.dt_itemsize_dt(S.single()))
    
    
    
    
    urow("dsp_isz_long",     P.dt_itemsize_dt(S.int64()))
    
    
    
    
    urow("dsp_isz_ulong",     P.dt_itemsize_dt(S.uint64()))
    
    
    
    
    urow("dsp_isz_double",     P.dt_itemsize_dt(S.double()))
    
    
    
    
    urow("dsp_isz_weakint",     P.dt_itemsize_dt(S.weakint()))
    
    
    
    
    urow("dsp_isz_weakfloat",     P.dt_itemsize_dt(S.weakfloat()))
    
    
    
    
    urow("dsp_isz_fp8",     P.dt_itemsize_dt(S.fp8e4m3()))
    
    
    
    
    urow("dsp_isz_fp8b",     P.dt_itemsize_dt(S.fp8e5m2fnuz()))
    # spec.bend's OWN itemsize agrees on the six that matter, which is a cheap
    # cross-check that the two dtype models have not drifted.
    
    
    
    
    lrow("dsp_isz_spec",     [S.Dt.itemsize(S.uint32()), S.Dt.itemsize(S.half()),
                              S.Dt.itemsize(S.double()), P.dt_itemsize_dt(S.uint32()),
                              P.dt_itemsize_dt(S.half()), P.dt_itemsize_dt(S.double())])
    # dt_cname -- the two entries ops_dsp.py:15 ADDS to a two-key map
    
    
    
    
    srow("dsp_cn_bool",     P.dt_cname_dt(S.boolean()))
    
    
    
    
    srow("dsp_cn_half",     P.dt_cname_dt(S.half()))
    
    
    
    
    srow("dsp_cn_long",     P.dt_cname_dt(S.int64()))
    
    
    
    
    srow("dsp_cn_ulong",     P.dt_cname_dt(S.uint64()))
    
    
    
    
    srow("dsp_cn_float",     P.dt_cname_dt(S.single()))
    
    
    
    
    srow("dsp_cn_double",     P.dt_cname_dt(S.double()))
    
    
    
    
    srow("dsp_cn_int",     P.dt_cname_dt(S.int32()))
    
    
    
    
    srow("dsp_cn_bf16",     P.dt_cname_dt(S.bfloat16()))
    
    
    
    
    srow("dsp_cn_fp8",     P.dt_cname_dt(S.fp8e4m3()))
    # the GLOBAL arm: a float buffer's SIZE is an `int`
    
    
    
    
    srow("dsp_cng_glob_f32",     P.dt_cname_global(False{}, S.single()))
    
    
    
    
    srow("dsp_cng_glob_u64",     P.dt_cname_global(False{}, S.uint64()))
    
    
    
    
    srow("dsp_cng_glob_i64",     P.dt_cname_global(False{}, S.int64()))
    
    
    
    
    srow("dsp_cng_alu_f32",     P.dt_cname_global(True{}, S.single()))
    
    
    
    
    srow("dsp_cng_alu_u64",     P.dt_cname_global(True{}, S.uint64()))
    
    
    
    
    srow("dsp_cng_alu_bool",     P.dt_cname_global(True{}, S.boolean()))
    # :16 code_for_op = clang's minus SQRT. 18 -> 17.
    
    
    
    
    urow("dsp_cfop_clang",     P.CFOP_CLANG())
    
    
    
    
    urow("dsp_cfop_dsp",     P.CFOP_DSP())
    
    
    
    
    urow("dsp_cfop_removed",     cfop_removed())
    # :46 supported_dtypes
    
    
    
    
    urow("dsp_sd_n",     U32.from_nat(List.length(&2, String, P.supported_names())))
    
    
    
    
    row("dsp_sd_drop_bf16",     Bool.not(dt_supported(True{}, S.bfloat16())))
    
    
    
    
    row("dsp_sd_drop_fp8",     Bool.not(dt_supported(True{}, S.fp8e4m3())))
    
    
    
    
    row("dsp_sd_drop_fp8b",     Bool.not(dt_supported(True{}, S.fp8e5m2fnuz())))
    
    
    
    
    row("dsp_sd_keep_bool",     dt_supported(True{}, S.boolean()))
    
    
    
    
    row("dsp_sd_keep_half",     dt_supported(True{}, S.half()))
    
    
    
    
    row("dsp_sd_keep_double",     dt_supported(True{}, S.double()))
    
    
    
    
    row("dsp_sd_keep_long",     dt_supported(True{}, S.int64()))
    
    
    
    
    srow("dsp_sd_0",     P.dt_nm(P.supported_12.at(0n)))
    
    
    
    
    srow("dsp_sd_7",     P.dt_nm(P.supported_12.at(7n)))
    
    
    
    
    srow("dsp_sd_11",     P.dt_nm(P.supported_12.at(11n)))
# --- 4: rpc_prep_args, :49-57 -------------------------------------------------
# :67 `struct.pack_into('i', var_vals_mv, i*8, b.size)`. FOUR bytes, signed, at the
# slot's own offset. So a size is `lo = size` and `hi = 0` ALWAYS -- `hi` is
# UNTOUCHED, not sign-extended, so even a size above 2**31 leaves the high word at
# zero. `dsp_vt_size_hi*` is that claim.
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
# THE six real bugs this gate found in its own first run, each of which a
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
# WHAT this gate still does not see, and it is a short list:
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
    srow("dsp-done", "1")


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
# THE six real bugs this gate found in its own first run, each of which a
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
# WHAT this gate still does not see, and it is a short list:
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
