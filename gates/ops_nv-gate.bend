# gates/ops_nv-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_nv.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/runtime/ops_nv.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/device.bend as D

def LAUNCH_SHIFT() -> U32: 8
def VAL32() -> U32: 5
# --- 1: arch and sass, :601-602 --------------------------------------------
def rl_shift(r: P.Rf, n: Nat) -> U32: P.Rl.shift(P.rl_at(P.Rf.rs(r), n))
def fifo_gpput_off(v: D.BFound) -> U32: D.Bn.off(D.bar_at(D.BFound.ar(v), 2))
# :111 `NVQueue.signal` -> `release(signal, value)`, timestamp False.
def q.signal(addr: U32, value: U32, t: P.Tr) -> P.Tr: P.q.release(addr, value, False{}, t)
# :112 `NVQueue.timestamp` -> `release(signal, UOp.const(0, uint64),
# timestamp=True)`.
def SM_120() -> U32: 288
def fifo_gpput_base(v: D.BFound) -> U32: D.Bn.base(D.bar_at(D.BFound.ar(v), 2))
def brow(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def pd.relocs(ts: List<&2, P.Rb>) -> P.Rf: P.Rf.go(ts, P.Rf{Nil{}, False{}})
# ===========================================================================
# :135-137 -- NVComputeQueue.__init__. TWO NUMBERS AND A BUFFER, and both
# numbers are the stride the launch path indexes by.
#
#   `self.qmd_sz = round_up(QMD(self.dev).sz * 4, 256)`
#   `self.stride = self.qmd_sz + max([p.kernargs_size for p in progs], default=0)`
#
# `sz * 4` is the QMD in BYTES (256 for ver 3, 384 for ver 5) rounded up to 256,
# so `qmd_sz` is 256 or 512 -- and it is ALSO the size of constant buffer 0's
# driver params, which is why the launch's argument base is `qmd_sz`.
# the ordinal of the refusal that should fire, as a PAIR with the trace, so a
# def can both read its own id and advance the trace in one step.
def Tr.minted(k: U32, arg: U32, t: P.Tr) -> P.Tr:
  match t:
    case P.Tr{calls, next, bad_at, seen, refused}:
      P.Tr{List.append(&2, P.Call, calls, [P.Call{k, arg}]), U32.add(next, 1),
         bad_at, U32.add(seen, 1), refused}
# ONE emit, and `refuse` is the port's `raise`: when it is set the failing call
# IS recorded and every LATER emit records nothing, so a refusal shows up as a
# TRUNCATED trace and needs no guard of its own. `Bool.pick` evaluates BOTH
# arms, so the emitted call is a value built here and the guard is a parameter.
def qmd.cbuf_sfx(v: U32, +i: String) -> String:
  Bool.pick(String, U32.is_ge(v, 4),
            String.concat(["_shifted6_", i]), String.concat(["_", i]))
# :85-91 `set_release`, and it is the only method that can REFUSE: it finds the
# first `release{i}_enable` that is clear, and returns False when BOTH are set.
# `NVComputeQueue.release` (:145-148) then falls back to the channel method --
# so a QMD whose two release slots are full silently gets no release, which is
# the whole reason this is a function and not an assignment.
# `layout_args(args, offset)`: the offsets are `iter_sig`'s plus the base, and
# the base is `self.qmd_sz` -- the size of constant buffer 0's driver params --
# which is why `nv_args_at_qmdsz` is a row and not a constant.
def args.layout(ks: List<&2, U32>, off: U32) -> List<&2, U32>: P.sig.slots(ks, off)
# the widths the three fixtures use, and the lengths.
def VAL64() -> U32: 5
# :206 `filter_sz = round_up(round_up(intra_top_off, 0x10000) + (64<<10) +
# intra_unk_size, 2<<20)`. The unk size is INSIDE the round_up, so an OLD card's
# filter buffer is SMALLER by 2 MiB than a NEW card's for the same resolution.
def dev.vid_filter(+top: U32, unk: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(H.round_up_u32(top, P.VID_TOP_ROUND()), P.VID_PAD()), unk),
                 P.VID_ROUND())
# :219 `buf + (round_up(w, 64) * round_up(h, 64) >> 8)` -- the chroma offset, and
# the `>> 8` is the 256-byte unit of :206.
def slrow(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(P.ssh(xs, Nil{}), ",")]))
# the trace readers every section below uses.
# ===========================================================================
# :135-137 -- NVComputeQueue.__init__. TWO NUMBERS AND A BUFFER, and both
# numbers are the stride the launch path indexes by.
#
#   `self.qmd_sz = round_up(QMD(self.dev).sz * 4, 256)`
#   `self.stride = self.qmd_sz + max([p.kernargs_size for p in progs], default=0)`
#
# `sz * 4` is the QMD in BYTES (256 for ver 3, 384 for ver 5) rounded up to 256,
# so `qmd_sz` is 256 or 512 -- and it is ALSO the size of constant buffer 0's
# driver params, which is why the launch's argument base is `qmd_sz`.
def cq.qmd_sz(ver: U32) -> U32: H.round_up_u32(P.qmd.words(ver), 256)
# `max([...], default=0)`: no programs means stride `qmd_sz`, NOT zero, and a
# port that wrote `max` without the default would answer 0.
# `Buffer(self.device, round_up(bytes_per_tpc * num_tpc_per_gpc * num_gpcs,
# 0x20000), ...)`. THE LAST ROUNDING IS 128 KiB, and it is the ONLY place in the
# file where a buffer's size is rounded to a 128 KiB multiple.
def dev.slm_bytes(bpt: U32, ntpg: U32, ngpc: U32) -> U32:
  H.round_up_u32(U32.mul(U32.mul(bpt, ntpg), ngpc), P.TOT_ROUND())
# :696-697 the two commands the raise submits, and they carry DIFFERENT numbers:
# `data64(shader_local_mem._buf)` is the buffer's ADDRESS and
# `data64(bytes_per_tpc)` is the PER-TPC byte count, then 0xff.
def fifo_gpput_root(v: D.BFound) -> U32: D.Bn.self_ix(D.bar_at(D.BFound.ar(v), 2))
# THE MOCK'S CLASS LIST. `nvdriver.py:160-162` ANSWERS
# `NV0080_CTRL_CMD_GPU_GET_CLASSLIST` WITH A LITERAL LIST OF CLASS IDS "from
# ada102". THE port does not carry the list -- IT is a list of numbers and the
# PORT'S class ladder is a different thing (`:403-415`'s PAIRS). WHAT the port
# CARRIES is the count, WHICH is what `setup_usermode`'s CLASSLIST rm_control
# RETURNS and what the class ladder walks.
#
# THE count is fifty-TWO, AND it was fifty-FIVE in the first draft of this
# COMMENT. MEASURED, BY reading the list out of the driver'S own source
# (NOT BY COUNTING A TRANSCRIPTION OF IT):
#
#     src = open('test/mockgpu/nv/nvdriver.py').read()
#     i = src.index('classes = [');  j = src.index(']', i)
#     len(ast.literal_eval(src[i+9:j+1]))   ->  52
#
# AND the port'S row answered 55, WHICH was a hand-TYPED count of a hand-TYPED
# LIST. THIS is the class the tree already names: the `renderer/cstyle.bend`
# unit shipped 215 hand-typed expectations of which SEVENTEEN were wrong. A
# COUNT typed by a human is a count of a transcription, NOT of the thing.
def MOCK_CLASSLIST_N() -> U32: 52
# THE mock'S init sequence, AS a trace. THE mock is a driver
# SUBSTITUTION: `test/mockgpu/mockgpu.py` INTERCEPTS `open()` AND `ioctl()`
# AT the python level, SO `NVKIface.__init__` RUNS unchanged against the
# SOFTWARE driver. THE ioctl sequence is therefore the same one, AND that is
# THE claim: THE mock is not a different code path.
#
# SO `dev.mock_init` IS `dev.init` WITH the mock'S answers, AND the rows
# BELOW compare the two traces. IF THEY differ, THE port believes the mock is
# A DIFFERENT PATH, AND IT IS NOT.
#
# `dev.mock_init` IS DEFINED AFTER `dev.init`, BECAUSE BEND REQUIRES
# DEFINITION-BEFORE-USE and `dev.init` IS below. MEASURED: the first attempt
# put it here and the compiler said "expected : dev.init, observed : dev.init
# (consumed more than once)" -- which is BEND'S WAY OF SAYING THE NAME IS NOT
# IN SCOPE YET.
def fifo_gpput_bytes(v: D.BFound) -> U32: D.nbytes(D.BFound.ar(v), 2)
# ===========================================================================
# :613-626 `fifos`, THE CHANNEL SETUP WORDS. These are the commands
# `_submit_cmds` uploads for the two rings, and they are the words `hw.ops[0]`
# packs into the channel's first push buffer, so the ORDER is the interface:
# SET_OBJECT first, then the LOCAL memory window, then the SHARED one.
# ===========================================================================
def SM_90() -> U32: 144
# `round_up(intra_top_off, 0x10000) + (64<<10)` IF unk_size > 0 ELSE None, and
# `None` here is 0 with `dev.vid_unk_none` beside it -- the decoder's `if
# self.dev.intra_unk_off is not None` at :224 reads the difference.
def dev.vid_unk_off(+top: U32, unk: U32) -> U32:
  Bool.pick(U32, U32.is_zero(unk), 0, U32.add(H.round_up_u32(top, P.VID_TOP_ROUND()), P.VID_PAD()))
def PD_BW() -> P.PData: P.pd.of(P.CLASS_BLACKWELL_COMPUTE_A(), 64, 1024, 352, 5, 3, 2, 8192, False{})
def cq.setobj(t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_OBJECT(), P.nvm.words_of(P.NVALS_ONE()), P.NVM_TYP2(), [P.CLASS_AMPERE_COMPUTE_B()], t)
# `release_structure_size_{i}` is 0 for a TIMESTAMP and 2 otherwise -- the
# reverse of what the name suggests, and it is the only difference between
# `signal` and `timestamp` inside the QMD.
def qmd.rel_size(tstamp: Bool) -> U32:
  Bool.pick(U32, tstamp, 0, 2)
# `{} if self.ver >= 4 else {f"release{i}_payload64b": 1}` -- ver 3 needs the
# explicit 64-bit payload flag and ver 5 does not have the field.
def exec.msg.too_many(+pr: U32, +max_threads: U32) -> String:
  Bool.pick(String, P.exec.ok.prod(pr, max_threads), "",
    String.concat(["Too many resources requested for launch, prod(local_size)=",
                   U32.show(pr), ", data.max_threads=", U32.show(max_threads)]))
# the second refusal, per axis. THREE INDEPENDENT COMPARISONS and no product.
# :170 `qmd_addr = self.qmd_buf.getaddr(self.devs) + UOp.const(len(self.qmds) *
# self.stride, dtypes.u64)` -- the n-th launch's QMD is at `n * stride` and
# NOTHING else. `cq.qmd_off` is that and it is a row per launch index.
def cq.qmd_off(n: U32, stride: U32) -> U32: U32.mul(n, stride)
# :177 `qmd.mv[self.qmd_sz:(at := self.qmd_sz + len(data.cbuf_0) * 4)] =
# array.array('I', data.cbuf_0).tobytes()` -- "constant buffer 0: the driver
# params". `at` is where the ARGS start, and it is `qmd_sz` PLUS the driver
# params, so the two bases are different numbers and the gate reads both.
def dev.slm_early(required: U32, have: U32) -> Bool: U32.is_ge(have, required)
# `bytes_per_tpc = round_up(round_up(slm * 32, 0x200) * max_warps_per_sm *
# num_sm_per_tpc, 0x8000)`. FOUR FACTORS and two roundings, and the inner one is
# to 512 while the outer is to 32768.
def pd.smem_cfg.msg(+shmem: U32) -> String:
  Bool.pick(String, P.smemcfg.ok(shmem), "",
            "min() iterable argument is empty")
# :277 `self.image = image.ljust(round_up(len(image), 0x1000) + 0x1000, 0)` --
# "NOTE: Ensure at least 4KB of space after the program to mitigate prefetch
# memory faults". The +0x1000 is the NOTE and it is 4096 bytes of slack.
# THE same four terms in a different order. `functools.reduce(int.__or__, ...)`
# does not care, and this def exists so the gate can ASK it: a port that appended
# the terms in the order the kwargs happen to appear would answer the same value
# here and there is no other place that could tell the difference.
def flags.release.reordered(tstamp: U32) -> U32:
  P.flags.go([P.flags.term(tstamp, P.FLD_SEM_RELEASE_TIMESTAMP()),
            P.flags.term(P.V_SEM_RELEASE_WFI_EN(), P.FLD_SEM_RELEASE_WFI()),
            P.flags.term(P.V_SEM_OPERATION_RELEASE(), P.FLD_SEM_OPERATION()),
            P.flags.term(P.V_SEM_PAYLOAD_SIZE_64BIT(), P.FLD_SEM_PAYLOAD_SIZE())], 0)
# :159 `memory_barrier`.
def Dev.sass(d: P.Dev) -> U32:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: P.sass_of(sm)
def dev.iface_count() -> U32: 3
def drv_table_name(t: U32) -> String:
  match t:
    case 615: "nv_615"
    case 610: "nv_610"
    case 580: "nv_580"
    case 570: "nv_570"
    case _: ""
# THE MOCK'S GPU COUNT. `NVKIface.count` IS `len(NVKIface.gpus_info)`, AND
# `gpus_info` COMES from `NV_ESC_CARD_INFO` FILTERED by `valid`. THE mock
# DRIVER answers `NV_ESC_CARD_INFO` FOR every gpu it knows -- IT creates
# SIX IN `NVDriver.__init__` (`NVDriver(gpus=6)`, `nvdriver.py:49`) AND SETS
# `st.valid = True` AND `st.pci_info.device_id = 0x2684` FOR EACH
# (`nvdriver.py:238-242`). SO THE MOCK REPORTS SIX GPUS.
#
# AND `MOCKIface.count = 1` OVERRIDES it. THAT is the one-LINE difference
# BETWEEN the two classes, AND it is the whole of what `MOCKIface` IS.
# :805 `SM_REG(...) = GPC_BASE + gpc * 0x4000 +
# (num_tpc_per_gpc - tpc_cnt[gpc] + tpc) * 0x200 + [0x400, 0x1000][sm] + reg` --
# pre-Blackwell. THE tpc INDEX IS counted from the end, so sharing one def with
# the Blackwell arm would be wrong in three places at once.
# THE sm base is an addend and not a factor. The first version had
# `U32.mul(<tpc term>, prof.sm_base(sm))`, which is 4 * 512 * 1024 where Python
# has 4 * 512 + 1024 -- MEASURED, and it is the difference between 1576232 and
# 2101544 for the same (gpc 0, tpc 0, sm 0, reg 0x128).
def prof.sm_reg.pre(gpc: U32, tpc: U32, sm: U32, reg: U32, ntpg: U32, tpc_cnt: U32) -> U32:
  U32.add(U32.add(P.PROF_PRE_GPC_BASE(), U32.mul(gpc, P.PROF_GPC_STRIDE())),
          U32.add(U32.mul(U32.add(U32.sub(ntpg, tpc_cnt), tpc), P.PROF_TPC_STRIDE_PRE()),
                  U32.add(P.prof.sm_base(sm), reg)))
# :781 `tpc_cnt = [bin(mask).count('1') for mask in tpc_masks]` and :798
# `tpc in range(tpc_cnt[gpc])` -- the per-GPC TPC count is a POPCOUNT and the
# Blackwell arm iterates exactly that many. `nv_prof_tpc_cnt_65535` is the row,
# and a port that used the raw mask would iterate 65535 times per GPC.
def notifier_bufferized() -> Bool: False{}
# :660 `to_name(n, name)` where `name` is "COMPUTE:0" or "COPY:0", and the fifo
# names come from :618-619 -- so the tag set is a FUNCTION of the two queue names
# and the `nv_toname_*` rows below pin it, ONE ROW PER (tag, queue) PAIR and under
# the same name CPython's own loop uses (`nv_toname_<parts joined by _>`). THE
# FIRST version named them after the queue first (`nv_toname_compute_ring`) and so
# five rows compared against nothing: the oracle names them the other way round and
# the differ called them unmatched, which is how a row can be WRONG AND UNCHECKED
# at the same time. Two of the five were also pure duplicates of the loop rows and
# `nv_toname_notifier` was emitted TWICE, where the differ's dict keeps the LAST
# one and the first is dead.
# ===========================================================================
# :818-824 `reg_ops`'s CHUNKING, and it is a policy number.
#
#   `for i in range(0, len(ops), 124): params = ... (regOpCount=len(ops[i:i+124]))`
#
# 124, and the LAST chunk is short -- so a 125-op write is TWO ioctls of 124 and
# 1. `nv_regops_chunks_125` and `nv_regops_last_125` are the rows, and a port
# that chunked at 128 would answer 1 for 125.
# ===========================================================================
# THE MOCK'S GPU COUNT. `NVKIface.count` IS `len(NVKIface.gpus_info)`, AND
# `gpus_info` COMES from `NV_ESC_CARD_INFO` FILTERED by `valid`. THE mock
# DRIVER answers `NV_ESC_CARD_INFO` FOR every gpu it knows -- IT creates
# SIX IN `NVDriver.__init__` (`NVDriver(gpus=6)`, `nvdriver.py:49`) AND SETS
# `st.valid = True` AND `st.pci_info.device_id = 0x2684` FOR EACH
# (`nvdriver.py:238-242`). SO THE MOCK REPORTS SIX GPUS.
#
# AND `MOCKIface.count = 1` OVERRIDES it. THAT is the one-LINE difference
# BETWEEN the two classes, AND it is the whole of what `MOCKIface` IS.
def MOCK_GPUS() -> U32: 6
# `self.prev_qmd.write(dependent_qmd0_pointer=qmd_addr >> 8,
# dependent_qmd0_action=1, dependent_qmd0_prefetch=1, dependent_qmd0_enable=1)`.
# FOUR fields, all immediates, all into the PREVIOUS QMD, and `>> 8` is the same
# shift `SEND_PCAS_A`'s argument carries. The trace entry's `arg` is the pointer,
# so the COUNT is what pins "four writes" and `nv_launch_chain_n` is the row.
def cq.exec.chain(qmd_addr_hi: U32, t: P.Tr) -> P.Tr:
  P.Tr.emit(P.CALL_ALLOC, P.DEPENDENT_ENABLE(),
    P.Tr.emit(P.CALL_ALLOC, P.DEPENDENT_PREFETCH(),
      P.Tr.emit(P.CALL_ALLOC, P.DEPENDENT_ACTION(),
        P.Tr.emit(P.CALL_ALLOC, qmd_addr_hi, t))))
# ===========================================================================
# :313-320 -- THE program cache. ITS key, BOTH directions, AND its absent
# EVICTION POLICY.
#
#   `_nv_program_cache: dict[tuple[bytes, tuple[str, ...]], ...]`
#   `if (cached := _nv_program_cache.get(key := (prg.src[3].arg, devs))) is None:`
#
# THE KEY IS A PAIR and both halves are load-bearing: `prg.src[3].arg` is the
# program's own ELF bytes and `devs` is the device tuple, so the same bytes on two
# devices are TWO entries and byte-identical programs on one device are ONE. A
# key that dropped `devs` would hand a program the address of a buffer allocated
# on a DIFFERENT device.
# ===========================================================================
def fifo_ring_off(v: D.BFound) -> U32: D.Bn.off(D.bar_at(D.BFound.ar(v), 1))
# :177 `qmd.mv[self.qmd_sz:(at := self.qmd_sz + len(data.cbuf_0) * 4)] =
# array.array('I', data.cbuf_0).tobytes()` -- "constant buffer 0: the driver
# params". `at` is where the ARGS start, and it is `qmd_sz` PLUS the driver
# params, so the two bases are different numbers and the gate reads both.
def cq.arg_base(qmd_sz: U32, cbuf0_len: U32) -> U32:
  U32.add(qmd_sz, U32.mul(cbuf0_len, 4))
# ===========================================================================
# :161-168 -- `NVComputeQueue.exec`'s TWO REFUSALS, and they are checked BEFORE
# anything is written, which is why both are refusals of the SAME shape and both
# truncate the launch trace.
#
#   `if prod(local_size) > 1024 or data.max_threads < prod(local_size): raise`
#   `if any(g > mx for g,mx in zip(global_size, [2147483647, 65535, 65535])) or
#       any(l > mx for l,mx in zip(local_size, [1024, 1024, 64])): raise`
#
# THE FIRST IS A DISJUNCTION and the second is a DISJUNCTION OF DISJUNCTIONS, so
# a port that collapsed either to a conjunction would accept a launch the driver
# refuses. The three maxima are PER AXIS and NOT a single bound: 1024 x 1024 x 64
# is legal and 65 in z is not, which is a row.
# ===========================================================================
# THE two traces compared. `Tr.has` IS a subsequence match, so this asks "IS
# THE mock'S trace the real one'S trace" and not "DO they have the same
# LENGTH" -- and a SUBSQUENCE is the right relation here, because THE mock'S
# TRACE is the real one'S with the mock'S answers in place of the card'S.
def dev.mock_same_shape() -> Bool:
  P.Tr.has(P.Tr.calls(P.Dev.tr(P.dev.mock_init(0))), P.Tr.calls(P.Dev.tr(P.dev.init(0, P.IFACE_NVK(), False{}, False{}))))
# THE mock'S trace'S three call counts. `NVKIface.__init__`'s SEQUENCE is
# `rm_alloc(ROOT)` THEN the version rm_control THEN `uvm(UVM_INITIALIZE)` THEN
# `uvm(UVM_MM_INITIALIZE)`, SO the counts are the shape of the init and not
# OF THE MOCK.
# --- 17: the buffer pool and the gpfifo views, :613-662 and :688-697 ------
def dev.bpt(slm: U32, mws: U32, nsm: U32) -> U32:
  H.round_up_u32(U32.mul(U32.mul(H.round_up_u32(U32.mul(slm, P.WARP_THREADS()), P.BPT_GRAN()), mws), nsm),
                 P.BPT_ROUND())
# `Buffer(self.device, round_up(bytes_per_tpc * num_tpc_per_gpc * num_gpcs,
# 0x20000), ...)`. THE LAST ROUNDING IS 128 KiB, and it is the ONLY place in the
# file where a buffer's size is rounded to a 128 KiB multiple.
# :214-215 `NVC9B0_SET_CONTROL_PARAMS`.
def cq.slmb(t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_SHADER_LOCAL_MEMORY_NON_THROTTLED_A(), P.nvm.words_of(P.NVALS_THREE_INT()),
           P.NVM_TYP2(), [0, 196608, 255], t)
# :337 `GPFifo`, and Python's field order IS the constructor order -- seven
# fields, and `notifier` is the FIFTH.
def fifo_ring_bytes(v: D.BFound) -> U32: D.nbytes(D.BFound.ar(v), 1)
def cq.lmemwin(t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_SHADER_LOCAL_MEMORY_WINDOW_A(), P.nvm.words_of(P.NVALS_TWO_INT()),
           P.NVM_TYP2(), P.hilo.pair(P.win_local()), t)
# :219 `buf + (round_up(w, 64) * round_up(h, 64) >> 8)` -- the chroma offset, and
# the `>> 8` is the 256-byte unit of :206.
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
# `max([...], default=0)`: no programs means stride `qmd_sz`, NOT zero, and a
# port that wrote `max` without the default would answer 0.
def i64row(nm: String, x: H.I64) -> IO(Unit): srow(nm, H.i64_text(x))
def cq.setobj4(t: P.Tr) -> P.Tr:
  P.nvm.emit(4, P.M_SET_OBJECT(), P.nvm.words_of(P.NVALS_ONE()), P.NVM_TYP2(), [P.CLASS_AMPERE_DMA_COPY_B()], t)
# :696-697 the two commands `_ensure_has_local_memory` uploads. `hilo.pair` is
# `data64` -- HIGH FIRST -- and the two commands are SEPARATE nvm calls, so the
# per-TPC byte count and the 0xff are in the second one only.
def NOTIFIER_BYTES() -> U32: 50331648
# ===========================================================================
# THE TYPES.
# ===========================================================================
# ONE recorded call, and it is ONE WORD in the two cases that matter:
#   - a queue word stream: `k` is the command header and `arg` is its payload
#     word, so the trace IS `array.array('I', cmds).tobytes()` read back;
#   - a driver call: `k` is the `CALL_*` tag and `arg` is the handle or the
#     object's kind.
#
# There is deliberately no field for the rest of a call's arguments: those are
# what the defs around this record build, and the gate reads them from the
# record a def RETURNS, not from the trace.
# The machine state of the FFI seam. `bad_at` is the ORDINAL of the refusal that
# should fire (0 = never), so one fixture reaches each raise site in turn and a
# refusal shows up as a TRUNCATED trace, which is what `raise` does.
#
# `next` mints the handle ids, so what the gate checks is that handles are
# consumed in the right ORDER and the right NUMBER of times.
# :559-567 `NVDevice`: `ifaces`, `sleep_timeout_ms` and `pm_encode`'s four
# rules. `sm_version` is the ONE query result every derived property reads, and
# `compute_class` is the ONE number that selects the QMD generation, so both
# are fields and everything else is a def.
# ONE ring's fixed geometry. :337 `GPFifo` is a frozen dataclass and Python's
# field order IS the constructor order, so this is its order:
#   ring, gpput, doorbell, put_value, notifier, entries, token
# `off` is `_new_gpu_fifo`'s `offset` and `ctxshare` is 0 for the video ring.
# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every driver call in this file goes through
# it, so the trace is the ordered list of ioctls and words the GPU will see.
#
# THE RAISE IS IN THE TRACE, and it is `Tr.emit`'s `refused`: once a
# refusal has fired no later step records anything, so a raise shows up as a
# TRUNCATION and needs no guard of its own. The failing call IS still recorded
# -- it sets `refused` in the same breath, so on entry its own `refused` is
# still False.
# ===========================================================================
# --- 7: `nv_flags` and the two tables under it, :40-41 ---------------------
def fifo_ring_base(v: D.BFound) -> U32: D.Bn.base(D.bar_at(D.BFound.ar(v), 1))
# :779-780 `tpc_masks = [m for i in range(self.num_gpcs) if (m := rm_control(...
# GR_GET_TPC_MASK, ...(gpcId=i)).tpcMask) > 0]` -- only NONZERO masks are kept, so
# the count is the number of GPCs that HAVE TPCs and not `num_gpcs`.
def wstream(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_WORD(), P.Tr.calls(t))
# `xs[i]`, which is `List.get` and a `Maybe` and no sugar. `Wv` is the record
# version of `Maybe<&2, U32>`. THE reason given was half FALSE: a `Data` record CAN hold a
# `Maybe` field -- MEASURED, 20 in-tree `Data` records carry 38 of them -- while the OTHER half
# is the real constraint and stands: a `Maybe` is affine, read once, no `+`. So `Wv` may be
# the right encoding; what was wrong is the reason offered for it.
# --- 19: the error strings and the two fault tables, :35 and :37-38 --------
def dev.slm_cmd(bpt: U32, +addr_hi: U32, addr_lo: U32, t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_SHADER_LOCAL_MEMORY_NON_THROTTLED_A(), P.nvm.words_of(P.NVALS_THREE_INT()),
           P.NVM_TYP2(), [addr_hi, bpt, 255],
    P.nvm.emit(1, P.M_SET_SHADER_LOCAL_MEMORY_A(), P.nvm.words_of(P.NVALS_TWO_INT()),
             P.NVM_TYP2(), [addr_hi, addr_lo], t))
# ===========================================================================
# :449-450 `alloc`'s PAGE SIZE, AND THE SIZE IT ROUNDS TO.
#
#   `page_size = mmap.PAGESIZE if uncached or host else
#                ((2 << 20) if size >= (8 << 20) else (mmap.PAGESIZE if MOCK else 4 << 10))`
#
# `mmap.PAGESIZE` is a HOST constant -- 16384 on this machine and 4096 on a
# typical x86-64 Linux -- so it is a parameter of `alloc.page_size` and not a
# constant, and `nv_ps_*` is measured against `mmap.PAGESIZE` as CPython sees it.
# The `2 << 20` for a size >= 8 MiB is "use huge pages only for gpu memory".
# ===========================================================================
# `round_up(h,64)2 + round_up(w,64)*round_up(h,64)//16`, then rounded to 2 MiB.
def fifo_ring_n(v: D.BFound) -> U32: D.Bn.size(D.bar_at(D.BFound.ar(v), 1))
# --- 3b: the MOCK PATH, `MOCKIface` and the selection that reaches it -------
# THE interface tags, so a row can name WHICH interface it is about. THE order
# IS the ladder'S order and the order is the policy (`_select_iface` walks it
# FIRST-WINS), so THE INDEX IS THE TAG.
def hilo.str32(+x: U32) -> String:
  String.concat([U32.show(U32.shrn(x, 32n)), ":", U32.show(x)])
# `sum(v.dtype.itemsize // 4 if isinstance(v, UOp) else 1 for v in vals)`, and
# this is NOT decoration: `NVQueue.sem` passes a uint64 address, a uint64
# payload and an int flag word, so its header counts 2 + 2 + 1 = FIVE words and
# not the THREE a reader counting the arguments would guess. MEASURED: CPython
# answers `0x20050017` for `wait`, and `0x20030017` for the same command with
# three INT arguments. `nv_nvals_sem` pins the five and `nv_sem_is_three_words`
# pins that the wrong answer is the plausible one.
# :541-542 PCIIface reads all three off the GSP, so it takes them verbatim
# rather than walking the ladder.
def cq.smemwin(t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_SHADER_SHARED_MEMORY_WINDOW_A(), P.nvm.words_of(P.NVALS_TWO_INT()),
           P.NVM_TYP2(), P.hilo.pair(P.win_shared()), t)
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(P.ush(xs, Nil{}), ",")]))
def alloc.alloc_size(+size: U32, uncached: Bool, host: Bool, mock: Bool) -> U32:
  H.round_up_u32(size, P.alloc.page_size(size, uncached, host, mock))
# ===========================================================================
# :699-715 `_ensure_has_vid_hw`. THE five numbers a decoder needs, ONE refusal,
# AND THE ORDER.
#
#   `if self.iface.viddec_class is None: raise RuntimeError(...)`
#   `coloc_sz      = round_up(round_up(h,64)2 + round_up(w,64)*round_up(h,64)//16, 2<<20)`
#   `intra_top_off = round_up(h, 64) * (608 + 4864 + 152 + 2000)`
#   `intra_unk_size = 2<<20 if viddec_class >= NVCFB0_VIDEO_DECODER else 0`
#   `intra_unk_off  = round_up(intra_top_off, 0x10000) + (64<<10)` if unk_size else None
#   `filter_sz     = round_up(round_up(intra_top_off, 0x10000) + (64<<10) + unk_size, 2<<20)`
#
# THE COMMENT says "decoder offsets are in 256-byte units" and the code shifts by
# 8 for exactly that reason -- so `intra_top_off` is in those units too and the
# 608+4864+152+2000 is a per-row byte count.
# ===========================================================================
def dev.slm(+required: U32, +have: U32) -> U32:
  Bool.pick(U32, U32.is_ge(have, required), have, H.round_up_u32(required, P.SLM_GRAN()))
def dev.fifos_of(+entries: U32, +off: U32) -> D.BFound:
  P.dev.fifos_pair(P.dev.fifos_root(entries, off), entries, off)
# THE two views share one arena, so they are SLOTS: slot 0 is the 3 MiB
# `gpfifo_buf` root, slot 1 is the ring view and slot 2 is the gpput view. MEASURED:
# reading slot 0 answers the ROOT's 4 bytes and `nv_ring_nbytes` printed 4 instead
# of 524288 -- so the readers below name the INDEX, and a reader that hardcoded
# 0 reads the root and passes every root-shaped row.
def fifo_ring_root(v: D.BFound) -> U32: D.Bn.self_ix(D.bar_at(D.BFound.ar(v), 1))
# the number of steps: `len(range(0, sz, step))`, which for sz 0 is ZERO -- the
# empty copy emits nothing at all. THE FUEL IS A `Nat` AND IT IS FIRST, because
# `off` GROWS and a self-call has to be decreasing (bend2-constraints.md rule 5).
# Three steps is the ceiling for any U32 `sz` -- 2^32-1 over 2^31 is 2 -- so
# COPY_NFUEL is generous rather than tight, and `nv_copy_nsteps_max` is the row
# that says the ceiling is not the bound.
def cq.slma(t: P.Tr) -> P.Tr:
  P.nvm.emit(1, P.M_SET_SHADER_LOCAL_MEMORY_A(), P.nvm.words_of(P.NVALS_TWO_INT()),
           P.NVM_TYP2(), [0, 187], t)
def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def t_pool() -> IO(Unit):
  do IO<Unit>:
    # :655 the GP-PUT slot, one row per fifo.
    row("nv_fifo_gpput_off_0", P.dev.gpput_off(0, 65536))
    row("nv_fifo_gpput_off_1", P.dev.gpput_off(1048576, 65536))
    row("nv_fifo_gpput_off_vid", P.dev.gpput_off(2097152, 2048))
    row("nv_fifo_gpput_off_def", P.dev.gpput_off(0, 1024))
    row("nv_fifo_entries_c", 65536)
    lrow("nv_fifo_setobj", wstream(cq.setobj(P.Tr.of())))
    lrow("nv_fifo_setobj_copy", wstream(cq.setobj4(P.Tr.of())))
    lrow("nv_fifo_lmemwin", wstream(cq.lmemwin(P.Tr.of())))
    lrow("nv_fifo_smemwin", wstream(cq.smemwin(P.Tr.of())))
    row("nv_fifo_entries_cp", 65536)
    row("nv_fifo_entries_vid", 2048)
    row("nv_fifo_alloc", P.GPFIFO_ALLOC())
    row("nv_notifier_bytes", NOTIFIER_BYTES())
    # THE two views of one root, read off device.bend's own `bview`. THE OFFSET
    # ACCUMULATES: the ring is at `off` and the gpput view is at
    # `gpput_off(off, entries)`, and both report the ROOT as their base.
    +a : D.BFound <- IO.pure(D.BFound, dev.fifos_of(65536, 1048576))
    row("nv_ring_n", fifo_ring_n(a))
    row("nv_ring_bytes", fifo_ring_bytes(a))
    row("nv_ring_off", fifo_ring_off(a))
    row("nv_ring_base", fifo_ring_base(a))
    row("nv_ring_root", fifo_ring_root(a))
    row("nv_gpput_off", fifo_gpput_off(a))
    row("nv_gpput_bytes", fifo_gpput_bytes(a))
    row("nv_gpput_base", fifo_gpput_base(a))
    row("nv_gpput_root", fifo_gpput_root(a))
    row("nv_ring_nbytes", fifo_ring_bytes(a))
    row("nv_gpput_nbytes", fifo_gpput_bytes(a))
    row("nv_ring_itemsize", S.Dt.itemsize(S.uint64()))
    row("nv_gpput_itemsize", S.Dt.itemsize(S.uint32()))
    # :688-697 `_ensure_has_local_memory`. THE NEGATIVE CASE: `if slm >=
    # required: return` reallocates nothing. `nv_slmp_*` IS `slm_per_thread`, the
    # PER-THREAD number; `nv_slmtot_*` below is the BUFFER it sizes. THE TWO WERE
    # BOTH NAMED `nv_slm_*` in the first version, and the oracle's `nv_slmtot_*`
    # rows went unmatched against the gate's `nv_slm_*` while every value agreed
    # -- the right number for the wrong function, which is what a name collision
    # between two claims looks like from the outside.
    row("nv_slmp_0_0", dev.slm(0, 0))
    row("nv_slmp_1_0", dev.slm(1, 0))
    row("nv_slmp_32_0", dev.slm(32, 0))
    row("nv_slmp_1_have32", dev.slm(1, 32))
    row("nv_slmp_32_have32", dev.slm(32, 32))
    row("nv_slmp_33_have32", dev.slm(33, 32))
    # THE one fixture WHERE THE early return and the rounding differ:
    # `have` 48 is not `round_up(33, 32)`, so the correct answer keeps 48 and
    # a port that dropped the guard answers 64. MEASURED: with only the
    # round_up-multiple `have` values this mutation moved NOTHING.
    row("nv_slmp_33_have48", dev.slm(33, 48))
    row("nv_slmp_64_have48", dev.slm(64, 48))
    row("nv_slmp_1024_have0", dev.slm(1024, 0))
    brow("nv_slm_early_0", dev.slm_early(0, 0))
    brow("nv_slm_early_1_have32", dev.slm_early(1, 32))
    brow("nv_slm_early_33_have32", dev.slm_early(33, 32))
    row("nv_bpt_0_48428", dev.bpt(0, 48, 4))
    row("nv_bpt_1_48428", dev.bpt(32, 48, 4))
    # :693 `round_up(bytes_per_tpc * num_tpc_per_gpc * num_gpcs, 0x20000)` -- THE
    # ONLY 128 KiB ROUNDING IN THE FILE. Both halves of every fixture are rows, the
    # value and the `hi:lo` pair, because the claim is that a 64-bit total fits the
    # word model and only the pair shows it.
    row("nv_slmtot_0_48428", dev.slm_bytes(0, 2, 8))
    row("nv_slmtot_32_48428", dev.slm_bytes(196608, 2, 8))
    row("nv_slmtot_1024_48428", dev.slm_bytes(6291456, 2, 8))
    row("nv_slmtot_4096_64828", dev.slm_bytes(67108864, 2, 8))
    row("nv_slmtot_1024_644214", dev.slm_bytes(8388608, 2, 14))
    row("nv_slmtot_1_48428", dev.slm_bytes(196608, 2, 8))
    # AND one that is not already a 128 KiB MULTIPLE. Every other fixture is --
    # 196608 x 16, 6291456 x 16, 67108864 x 16 and 8388608 x 28 are all exact
    # multiples of 131072 -- so a port that DROPPED the rounding answered the same
    # six numbers and mutation M30 moved NOTHING. The `1,1,1` fixture is the one
    # that makes the rounding visible: 1 against 131072.
    row("nv_slmtot_1_1_1", dev.slm_bytes(1, 1, 1))
    srow("nv_slmtot_0_48428_hi", hilo.str32(dev.slm_bytes(0, 2, 8)))
    srow("nv_slmtot_32_48428_hi", hilo.str32(dev.slm_bytes(196608, 2, 8)))
    srow("nv_slmtot_1024_48428_hi", hilo.str32(dev.slm_bytes(6291456, 2, 8)))
    srow("nv_slmtot_4096_64828_hi", hilo.str32(dev.slm_bytes(67108864, 2, 8)))
    srow("nv_slmtot_1024_644214_hi", hilo.str32(dev.slm_bytes(8388608, 2, 14)))
    srow("nv_slmtot_1_48428_hi", hilo.str32(dev.slm_bytes(196608, 2, 8)))
    # :696-697 the two uploads, as WORD LISTS. `nvm`'s header carries the WORD
    # COUNT, so the first is 2 and the second is 3 -- and that is why CPython
    # answers 537010660 and not the 536945124 the arithmetic gives.
    lrow("nv_slm_lmem_cmd", wstream(cq.slma(P.Tr.of())))
    lrow("nv_slm_nthr_cmd", wstream(cq.slmb(P.Tr.of())))
    # :696-697 `self._submit_cmds("COMPUTE:0", *nvm(...), *nvm(...))` -- SEVEN WORDS
    # IN ONE SUBMIT, the local-memory-window pair FIRST, and
    # `dev.slm_cmd(bpt, addr_hi, addr_lo, t)` is the call with the address and the
    # per-TPC count filled in: SLMA carries the ADDRESS and NTHR carries the COUNT.
    lrow("nv_slm_cmd", wstream(dev.slm_cmd(196608, 0, 187, P.Tr.of())))
    brow("nv_slm_early_0_48428", dev.slm_early(0, 0))
    brow("nv_slm_early_1_48428", dev.slm_early(1, 0))
    brow("nv_slm_early_32_48428", dev.slm_early(32, 0))
    brow("nv_slm_early_1024_48428", dev.slm_early(1024, 0))
    brow("nv_slm_early_4096_64828", dev.slm_early(4096, 0))
    brow("nv_slm_early_1024_644214", dev.slm_early(1024, 0))
    # THE same total, PRINTED through the other printer. `hilo.str32` splits a
    # `U32` with a saturating shift and `H.i64_of_i32` builds an `I64` and then
    # splits THAT, so the two paths are independent and a defect in either shows
    # up as ONE of the two rows moving while the other holds. THIS SITE USED TO
    # PRINT `nv_slmtot_1_48428` AND `nv_slmtot_1_48428_hi` -- the names the
    # `srow` SITE ABOVE already owns -- and the two are now distinguished by the
    # PATH THAT PRODUCED THEM, which is the thing that actually differs.
    row("nv_slmtot_1_48428_i64", dev.slm_bytes(196608, 2, 8))
    i64row("nv_slmtot_1_48428_hi_i64", H.i64_of_i32(dev.slm_bytes(196608, 2, 8)))
    row("nv_bpt_32_48428", dev.bpt(32, 48, 4))
    row("nv_bpt_1024_48428", dev.bpt(1024, 48, 4))
    row("nv_bpt_4096_64828", dev.bpt(4096, 64, 8))
    row("nv_bpt_1024_644214", dev.bpt(1024, 64, 4))
    # THE two commands the raise submits, AS one trace. THE row above
    # (`nv_slm_cmd`) IS the same two commands built by the same call with the
    # SAME arguments, so THIS site used to print the same name a second time --
    # and a NAME printed twice is a row that cannot be addressed. THE claim here
    # IS the one the first site cannot make: that the trace is BUILT and held in
    # A variable and the variable'S contents are the trace, not a fresh
    # construction that happens to agree. THAT IS A DIFFERENT QUESTION, so it
    # gets a different name.
    +a2 : P.Tr <- IO.pure(P.Tr, dev.slm_cmd(196608, 0, 187, P.Tr.of()))
    lrow("nv_slm_cmd_held", wstream(a2))
    # :449-451 `alloc`'s page size and the size it rounds to. `mmap.PAGESIZE` is
    # a HOST constant, so it is a parameter here and 16384 on this machine.
    row("nv_pagesize", P.HOST_PAGESIZE())
    row("nv_ps_4096_000", P.alloc.page_size(4096, False{}, False{}, False{}))
    row("nv_ps_8388608_000", P.alloc.page_size(8388608, False{}, False{}, False{}))
    row("nv_ps_8388607_000", P.alloc.page_size(8388607, False{}, False{}, False{}))
    row("nv_ps_1_001", P.alloc.page_size(1, False{}, False{}, True{}))
    row("nv_ps_1_100", P.alloc.page_size(1, True{}, False{}, False{}))
    row("nv_ps_1_010", P.alloc.page_size(1, False{}, True{}, False{}))
    row("nv_ps_1_111", P.alloc.page_size(1, True{}, True{}, True{}))
    row("nv_allocsz_4096_000", alloc.alloc_size(4096, False{}, False{}, False{}))
    row("nv_allocsz_8388608_000", alloc.alloc_size(8388608, False{}, False{}, False{}))
    row("nv_allocsz_8388607_000", alloc.alloc_size(8388607, False{}, False{}, False{}))
    row("nv_allocsz_1_001", alloc.alloc_size(1, False{}, False{}, True{}))
    row("nv_allocsz_1_100", alloc.alloc_size(1, True{}, False{}, False{}))
    row("nv_allocsz_1_010", alloc.alloc_size(1, False{}, True{}, False{}))
    row("nv_allocsz_1_111", alloc.alloc_size(1, True{}, True{}, True{}))
# --- 18: the video decoder sizing, :699-715 ------------------------------
def iface_name(i: U32) -> String:
  match i:
    case 1: "NVKIface"
    case 2: "PCIIface"
    case 3: "MOCKIface"
    case _: ""
# `MOCKIface.count = 1` (`tinygrad/runtime/ops_nv.py:552`) IS THE WHOLE
# DIFFERENCE from `NVKIface`, AND `NVKIface.count` IS the number of GPUs THE
# CARD reports. SO the count is a function of the interface and not a constant
# OF the device, AND a port that hard-CODES "3" -- WHICH is what
# `dev.iface_count` IS -- HAS ported the ladder'S length and not its count.
#
# MEASURED: `dev.iface_count` ANSWERS 3, and that is the LENGTH of
# `ifaces = [NVKIface, PCIIface, MOCKIface]`, and `nv_iface_count` IS A ROW
# THAT CPython ANSWERS with 3 TOO -- so THE row is right and the name is
# WRONG. THE count of interfaces and the count of devices are two different
# QUESTIONS and the row was answering the first one under the second one'S
# NAME.
def M_OLD() -> U32: 1346
# `next((c for c in [...] if c in ...), None)` -- the access table's NONE arm is
# the same `None` `dev.vid_ok` reads.
# THE table has nine entries and they are not contiguous: 4 is WEAK and 8, 9, 10
# are READ, WRITE, ATOMIC. A catch-all answered WEAK for all three and
# `nv_paccess_8/9/10` said so.
def paccess.of(x: U32) -> String:
  match x:
    case 0: P.ACCESS_READ()
    case 1: "WRITE"
    case 2: P.ACCESS_STRONG()
    case 3: "PREFETCH"
    case 8: P.ACCESS_READ()
    case 9: "WRITE"
    case 10: "ATOMIC"
    case _: P.ACCESS_WEAK()
# ===========================================================================
# hcq2.py:63 `to_name(*parts) = "_".join(parts).replace(":", "_").lower()`.
# THE `pm_bufferize` TAG, and it is a NAME both ways: :660-661 builds
# `UPat(Ops.PARAM, tag=to_name(n, name))` for n in ("ring", "gpput", "doorbell",
# "put_value") and `to_name` is how a PARAM is matched to a fifo field. A tag
# that disagrees in either direction matches NOTHING and the buffer silently
# falls through to a fresh allocation.
# ===========================================================================
# `.replace(":", "_").lower()`, and the ORDER matters: the replace is on the
# ORIGINAL case and the lower is last, so `to_name("COMPUTE", "0")` is
# `compute_0` and NOT `compute:0`.
# `String.split` THROWS THE SEPARATORS AWAY, so `concat(split("COMPUTE:0", ':'))`
# is `"COMPUTE0"` and not `"COMPUTE_0"` -- MEASURED: `to_name(["ring",
# "COMPUTE:0"])` printed `ring_compute0` where CPython prints `ring_compute_0`.
# The separator has to be put BACK between the parts, and `device.bend`'s
# `rest_of` is the same fix with `:` where this needs `_`.
# The accumulator is already in FORWARD order (`List.append` is `xs ++ ys`), so
# reversing it at the end gave "0COMPUTE_" -- MEASURED, and it is why the first
# two attempts printed `ring_compute0` and then `doorbell_0compute_`.
# `prod(local_size)`, and it is a U32 because every local dimension is <= 1024
# for a launch Python accepts -- but the PRODUCT is computed BEFORE the check, so
# a (64, 64, 64) local size is 262144 and answers U32 fine.
def prod3(a: U32, b: U32, c: U32) -> U32: U32.mul(U32.mul(a, b), c)
# the first refusal: `prod > 1024 or max_threads < prod`.
# --- 16: the launch refusals and the launch word trace, :161-186 -----------
def ncalls(k: U32, t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
# --- 8: the queues' command sequences -------------------------------------
def cq.qmd_buf_len(nprogs: U32, stride: U32) -> U32: U32.mul(nprogs, stride)
# :170 `qmd_addr = self.qmd_buf.getaddr(self.devs) + UOp.const(len(self.qmds) *
# self.stride, dtypes.u64)` -- the n-th launch's QMD is at `n * stride` and
# NOTHING else. `cq.qmd_off` is that and it is a row per launch index.
def exec.msg.dims(+d: P.Dim) -> String:
  Bool.pick(String, P.exec.ok.dims(d), "",
    String.concat(["Invalid global/local dims global_size=(", U32.show(P.Dim.gx(d)),
                   ", ", U32.show(P.Dim.gy(d)), ", ", U32.show(P.Dim.gz(d)),
                   "), local_size=(", U32.show(P.Dim.lx(d)), ", ", U32.show(P.Dim.ly(d)),
                   ", ", U32.show(P.Dim.lz(d)), ")"]))
# ===========================================================================
# :180-186 -- THE LAUNCH, AS A WORD TRACE. Two shapes and the difference is
# `self.prev_qmd is None`:
#
#   None:  (PMA) NVC6C0_PM_TRIGGER, then NVC6C0_SEND_PCAS_A(qmd_addr>>8),
#          then NVC6C0_SEND_SIGNALING_PCAS2_B(PREFETCH_SCHEDULE)
#   else:  FOUR writes into the PREVIOUS QMD -- dependent_qmd0_pointer,
#          _action, _prefetch and _enable -- and NO words at all.
#
# The chained arm emits no words, so the ring's word count is the only thing that
# distinguishes the two, and a port that always opened a PCAS pair would drop the
# launch ordering that `NVComputeQueue.release` (:145-148) depends on.
# ===========================================================================
def exec.dims(gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32) -> P.Dim:
  P.Dim{gx, gy, gz, lx, ly, lz}
# `qmd.slot.ok` is "AT LEAST ONE SLOT IS FREE", not "not both are busy" -- the
# two differ the moment exactly one is busy, and Python answers 1 there. The
# first version used `not (busy0 or busy1)` and `nv_qmd_release_ok_one` printed
# False where CPython's scan answers slot 1.
def cq.stride(qmd_sz: U32, max_kernargs: U32) -> U32: U32.add(qmd_sz, max_kernargs)
def t_launch() -> IO(Unit):
  do IO<Unit>:
    # THE FIRST REFUSAL, and it is a DISJUNCTION: `prod > 1024 OR max_threads <
    # prod`. A tiny max_threads with a small product refuses, and so does a big
    # product with a big one -- `nv_launch_small_refuses` and
    # `nv_launch_big_refuses` are two different conjuncts.
    brow("nv_launch_ok_1024_1024", P.exec.ok.prod(prod3(32, 32, 1), 1024))
    brow("nv_launch_small_refuses", Bool.not(P.exec.ok.prod(prod3(32, 32, 1), 512)))
    brow("nv_launch_big_refuses", Bool.not(P.exec.ok.prod(prod3(64, 32, 1), 8192)))
    brow("nv_launch_ok_1024_8192", P.exec.ok.prod(prod3(32, 32, 1), 8192))
    # THE other two arms of the same disjunction, one per conjunct: a SMALL
    # max_threads under a legal product, and a product over 1024 with a
    # max_threads large enough to cover it. Either alone refuses.
    brow("nv_launch_ok_1024_512", P.exec.ok.prod(prod3(32, 32, 1), 512))
    brow("nv_launch_ok_2048_8192", P.exec.ok.prod(prod3(64, 32, 1), 8192))
    srow("nv_launch_msg_small", exec.msg.too_many(1024, 512))
    srow("nv_launch_msg_big", exec.msg.too_many(2048, 8192))
    srow("nv_launch_msg_ok", exec.msg.too_many(1024, 8192))
    # THE SECOND REFUSAL, and the maxima are PER AXIS: 1024 x 1024 x 64 is legal
    # and 65 in z is not, which no single bound could express.
    row("nv_gmax_x", P.exec.gmax(0))
    row("nv_gmax_y", P.exec.gmax(1))
    row("nv_gmax_z", P.exec.gmax(2))
    row("nv_lmax_x", P.exec.lmax(0))
    row("nv_lmax_y", P.exec.lmax(1))
    row("nv_lmax_z", P.exec.lmax(2))
    brow("nv_dims_ok_default", P.exec.ok.dims(exec.dims(1, 1, 1, 1, 1, 1)))
    brow("nv_dims_ok_max", P.exec.ok.dims(exec.dims(2147483647, 65535, 65535, 1024, 1024, 64)))
    brow("nv_dims_gx_over", Bool.not(P.exec.ok.dims(exec.dims(2147483648, 1, 1, 1, 1, 1))))
    brow("nv_dims_gy_over", Bool.not(P.exec.ok.dims(exec.dims(1, 65536, 1, 1, 1, 1))))
    brow("nv_dims_gz_over", Bool.not(P.exec.ok.dims(exec.dims(1, 1, 65536, 1, 1, 1))))
    brow("nv_dims_lz_over", Bool.not(P.exec.ok.dims(exec.dims(1, 1, 1, 1, 1, 65))))
    brow("nv_dims_lx_over", Bool.not(P.exec.ok.dims(exec.dims(1, 1, 1, 1025, 1, 1))))
    srow("nv_dims_msg_lz", exec.msg.dims(exec.dims(1, 1, 1, 1, 1, 65)))
    srow("nv_dims_msg_ok", exec.msg.dims(exec.dims(1, 1, 1, 1, 1, 64)))
    # THE TWO LAUNCH SHAPES. `prev_qmd is None` opens a PCAS pair and emits
    # WORDS; otherwise four fields go into the previous QMD and NO words are
    # emitted. `nv_launch_chain_words` is 0 and that is the whole difference.
    +a : P.Tr <- IO.pure(P.Tr, P.cq.exec(False{}, False{}, 4660, 9, P.Tr.of()))
    lrow("nv_launch_open", wstream(a))
    +b : P.Tr <- IO.pure(P.Tr, P.cq.exec(True{}, False{}, 4660, 9, P.Tr.of()))
    row("nv_launch_chain_words", P.seen(b))
    +h : P.Tr <- IO.pure(P.Tr, cq.exec.chain(4660, P.Tr.of()))
    row("nv_launch_chain_n", ncalls(P.CALL_ALLOC(), h))
    lrow("nv_launch_chain_args", P.Tr.args(P.CALL_ALLOC(), P.Tr.calls(h)))
    +c : P.Tr <- IO.pure(P.Tr, P.cq.exec(False{}, True{}, 4660, 9, P.Tr.of()))
    row("nv_launch_pma_words", P.seen(c))
    row("nv_launch_open_words", P.seen(a))
    # THE TWO BASES: `qmd_sz` is the driver params and `at` is where the ARGS
    # start, so they are DIFFERENT numbers and both are rows.
    row("nv_launch_qmd_sz3", cq.qmd_sz(P.QMD_VER3()))
    row("nv_launch_qmd_sz5", cq.qmd_sz(P.QMD_VER5()))
    row("nv_launch_at", cq.arg_base(512, 12))
    row("nv_launch_at_mixed", cq.arg_base(512, 224))
    brow("nv_launch_at_equals", U32.is_eq(cq.arg_base(512, 0), 512))
    row("nv_launch_shift", LAUNCH_SHIFT())
    row("nv_launch_dep_action", P.DEPENDENT_ACTION())
    # THE STRIDE and the QMD addresses: `n * stride` and nothing else.
    row("nv_launch_stride0", cq.stride(512, 512))
    # A NON-ZERO `kernargs`, which is the only way to tell `qmd_sz + max` from
    # `qmd_sz + kernargs`: at 0 kernargs the two agree.
    row("nv_launch_stride256", cq.stride(256, 256))
    row("nv_launch_qmd_off0", cq.qmd_off(0, 1024))
    row("nv_launch_qmd_off1", cq.qmd_off(1, 1024))
    row("nv_launch_qmd_off3", cq.qmd_off(3, 1024))
    row("nv_launch_buflen_3", cq.qmd_buf_len(3, 1024))
    row("nv_launch_buflen_0", cq.qmd_buf_len(0, 1024))
# --- 17: the buffer pool and the gpfifo views, :613-662 and :688-697 ------
# THE two generated tables' SIZES, MEASURED, because the word model is only exact
# BECAUSE of what they do not contain.
def iface.err_msg(+status: U32) -> String:
  Bool.pick(String, U32.is_zero(status), "", P.iface.err_str_of(status, P.iface.unknown()))
# `NV_PFAULT_ACCESS_TYPE` is `{dt: name.split("_")[-1] ...}`, so a value maps to a
# BARE word -- "READ", "WRITE" -- while `NV_PFAULT_FAULT_TYPE` maps to the FULL C
# name. Both directions differ and both are rows.
# --- 6: `nvm`, :47-48 ------------------------------------------------------
def qmd.fields_v3() -> U32: 181
# THE `status == 0` ARM IS NOT PYTHON-OBSERVABLE and it deliberately has no row:
# all four `get_error_str` raises (:388, :396, :401, :444) are guarded by
# `if status != 0`, so CPython never builds a message for a zero status. The first
# version had `nv_errstr_0_err = iface.err_msg(0)` on the gate AND
# `row("nv_err_0_err", "")` hardcoded in the oracle -- a tautology on BOTH sides
# that the differ happily reported as agreeing. A row nobody can compute is a row
# that cannot fail.
def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  H.u32_list_eq(a, b)
# ===========================================================================
# :557-567 -- THE three ifaces and the four encode rules.
#
# `ifaces = [NVKIface, PCIIface, MOCKIface]` is a FIRST-WINS ladder
# (`Compiled._select_iface` walks it), so the ORDER is the policy and
# `dev.iface_count` returns the count while `dev.encode_rules` returns the four
# custom-function names. A misspelled `pm_encode` entry silently matches
# NOTHING, so both directions are rows.
# ===========================================================================
# `NV_PFAULT_ACCESS_TYPE` is `{dt: name.split("_")[-1] ...}`, so a value maps to a
# BARE word -- "READ", "WRITE" -- while `NV_PFAULT_FAULT_TYPE` maps to the FULL C
# name. Both directions differ and both are rows.
def ADDR_LO() -> U32: 2147418112
def t_nvm() -> IO(Unit):
  do IO<Unit>:
    # THE FIVE. A uint64 address counts two words and a uint64 payload counts
    # two and an int flag word counts one, so the header's argument field is 5
    # and NOT 3. `nv_nvm_sem` and `nv_nvm_sem_int3` are the same command built
    # the two ways, and they differ -- which is the whole measurement.
    +a : P.Tr <- IO.pure(P.Tr, P.nvm.emit(0, P.M_SEM_ADDR_LO(), P.nvm.words_of(P.NVALS_SEM()),
                                    P.NVM_TYP2(), [ADDR_LO(), VAL64(), 0], P.Tr.of()))
    lrow("nv_nvm_sem", wstream(a))
    +b : P.Tr <- IO.pure(P.Tr, P.nvm.emit(0, P.M_SEM_ADDR_LO(), 3, P.NVM_TYP2(),
                                    [1, 2, 3], P.Tr.of()))
    lrow("nv_nvm_sem_int3", wstream(b))
    brow("nv_sem_is_three_words", Bool.not(u32_list_eq(wstream(a), wstream(b))))
    row("nv_nvals_sem", P.nvm.words_of(P.NVALS_SEM()))
    row("nv_nvals_hilo3", P.nvm.words_of(P.NVALS_HILO3()))
    row("nv_nvals_hilo4", P.nvm.words_of(P.NVALS_HILO4()))
    row("nv_nvals_two", P.nvm.words_of(P.NVALS_TWO_INT()))
    +c : P.Tr <- IO.pure(P.Tr, P.nvm.emit(1, P.M_SEND_PCAS_A(), 1, 1, [4660], P.Tr.of()))
    lrow("nv_nvm_typ1", wstream(c))
    +d : P.Tr <- IO.pure(P.Tr, P.nvm.emit(4, P.M_OFFSET_IN_UPPER(), P.nvm.words_of(P.NVALS_HILO4()),
                                    P.NVM_TYP2(), [0, ADDR_LO(), 0, ADDR_LO()], P.Tr.of()))
    lrow("nv_nvm_hilo4", wstream(d))
    +e : P.Tr <- IO.pure(P.Tr, P.nvm.emit(0, P.M_NON_STALL_INTERRUPT(), 1, P.NVM_TYP2(), [0], P.Tr.of()))
    lrow("nv_nvm_nsi", wstream(e))
    # THE four fields, ONE row each, because they do not overlap and a port that
    # ORed them in the wrong place would still answer True for small values.
    row("nv_hdr_typ2", P.nvm.word(0, 0, 0, 2))
    row("nv_hdr_subc4", P.nvm.word(4, 0, 0, 0))
    row("nv_hdr_mthd", P.nvm.word(0, P.M_OFFSET_IN_UPPER(), 0, 0))
    row("nv_hdr_nvals5", P.nvm.word(0, 0, 5, 0))
    row("nv_hdr_all", P.nvm.word(4, P.M_OFFSET_IN_UPPER(), 4, 2))
# --- 7: `nv_flags` and the two tables under it, :40-41 ---------------------
# :45 `if ret != 0: raise RuntimeError(f"ioctl returned {ret}")`. THE REFUSAL, and
# `ret` is the ioctl's return value, which the seam supplies.
def iowr.msg(+ret: U32) -> String:
  Bool.pick(String, U32.is_zero(ret), "", String.concat(["ioctl returned ", U32.show(ret)]))
# ===========================================================================
# :50-94 -- QMD. THE field table, AND why a `List<&2, U32>` OF words is exact.
#
# `self.mv = bytearray(self.sz * 4)` -- 256 bytes for ver 3 and 384 for ver 5.
# `QMD.fields[pref][k]` is a `(hi, lo)` BIT RANGE and `read`/`write` do
#
#   (int.from_bytes(mv[lo//8:hi//8+1], "little") >> (lo % 8)) & ((1 << (hi-lo+1)) - 1)
#   mv[lo//8:hi//8+1] = ((num & ~mask) | (v << (lo % 8))).to_bytes(...)
#
# MEASURED over BOTH generated tables: 181 fields for NVC6C0_QMDV03_00 and 296
# for NVCEC0_QMDV05_00, and NOT ONE of the 477 is wider than 32 bits and NOT ONE
# straddles a 32-bit boundary. So a field lives in exactly one U32 word, `lo//32`
# is its word and `lo % 32` is its shift, and the byte-array model is EXACT
# rather than approximate. `nv_qmd_fields_v3` and `nv_qmd_fields_v5` are the
# rows that pin the counts, and the WIDE/STRADDLE counts are measured on the
# GENERATED tables by the ORACLE (`nv_qmd_wide_v3`, `nv_qmd_wide_v5`,
# `nv_qmd_straddle_v3`, `nv_qmd_straddle_v5`, all 0) and are deliberately NOT rows
# here: this port does not carry the 407 unreferenced fields, so a Bend row for
# their width would be a constant printing itself.
# ===========================================================================
def relocs_bad() -> List<&2, P.Rb>: [P.Rb{16, 8, P.RELOC_64()}, P.Rb{48, 8, 3}, P.Rb{64, 8, P.RELOC_32()}]
def paccess.n() -> U32: 9
def reg_fields_n() -> U32: 5
# ===========================================================================
# :793-816 `_prof_setup_pc_sampling`'s REGISTER ADDRESSES. NOT A WALL: they are
# integer arithmetic on four base addresses and the gpc/tpc/sm indices, and the
# Blackwell and pre-Blackwell arms differ in the SPACING (0x4000 per gpc against
# 0x200 per tpc) and in the SM base.
#
# :777 `PMASYS_BASE, PMAGPC_BASE, GR_GPC_BASE, GPC_BASE = (0x2b1000, 0x2b0000,
# 0x424000, 0x200000) if is_bw else (0x24a000, 0x244000, 0x419800, 0x180000)`
# ===========================================================================
def pd.reloc_arms() -> List<&2, U32>: [P.RELOC_64(), P.RELOC_32(), P.RELOC_32_HI()]
# THE FORWARD DIRECTION. The offsets differ by FOUR for BOTH 32-bit arms, which
# is what makes them the two halves of one 64-bit address.
def Dev.arch(d: P.Dev) -> String:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}:
      P.arch_of(sm)
# `bytes_per_tpc = round_up(round_up(slm * 32, 0x200) * max_warps_per_sm *
# num_sm_per_tpc, 0x8000)`. FOUR FACTORS and two roundings, and the inner one is
# to 512 while the outer is to 32768.
def flags.ctrl() -> U32:
  P.flags.go([P.flags.term(P.V_CTRL_HEVC(), P.FLD_CTRL_CODEC_TYPE()),
            P.flags.term(P.V_CTRL_PROD_RUN(), P.FLD_CTRL_TESTRUN_ENV()),
            P.flags.term(P.V_TRUE(), P.FLD_CTRL_GPTIMER_ON()),
            P.flags.term(P.V_TRUE(), P.FLD_CTRL_ERR_CONCEAL_ON()),
            P.flags.term(P.V_TRUE(), P.FLD_CTRL_MBTIMER_ON()),
            P.flags.term(P.V_TRUE(), P.FLD_CTRL_EVENT_TRACE_LOGGING_ON())], 0)
# ===========================================================================
# :33 `hilo`, the ONLY thing `NVCopyQueue` does with a 64-bit address.
#   `(addr >> 32).cast(dtypes.u32), addr.cast(dtypes.u32)`
# Two words, HIGH FIRST, and the COPY commands emit them in that order -- so the
# order is the contract and `nv_copy_order` pins it.
# ===========================================================================
def qmd.cbuf_shift(+v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 6, 0)
def wnth(xs: List<&2, U32>, n: Nat, d: U32) -> U32:
  P.Wv.at(List.get(&2, U32, xs, n), d)
def CLASS_USERMODE() -> U32: 1
def Rf.refused(+r: P.Rf) -> Bool:
  match r:
    case P.Rf{rs, refused}: refused
# A REFUSAL EMPTIES THE LIST, because Python raises INSIDE
# `NVProgramData.__init__` and `self.relocs` never comes into existence -- it is
# not "everything up to the bad one". MEASURED: keeping the prefix made
# `nv_reloc_bad_n` answer 2 where CPython's constructor answers nothing at all.
def Dev.nqmd(d: P.Dev) -> U32:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: next_qmd
# :572 `self.iface = self._select_iface(device)`. The selection itself is a
# WALL (it opens hardware); the RESULT is a tag and the ladder order above is
# the policy, so `dev.init` takes the winner as a parameter and records it.
def Dev.pma(d: P.Dev) -> Bool:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: pma
# --- 2: the VA bump allocators, :347-351 ------------------------------------
def HOST_OBJ_BASE() -> U32: 4096
# --- 3: the ifaces and the four encode rules, :559-567 ----------------------
def va.uvm_top_osx() -> H.I64: H.i64_add(P.va.uvm_base_osx(), P.va.uvm_size())
# --- 5: the init order, :571-611 -------------------------------------------
# The fixture is a Hopper-shaped GPU: sm_version 2192 and the FULL class set,
# so every ladder picks a non-trivial winner. `peer=True` gives one other NV
# device, which is the one-uva-per-peer shape.
def t_va() -> IO(Unit):
  do IO<Unit>:
    i64row("nv_va_low_sz", P.va.low_size())
    i64row("nv_va_low_base", P.va.low_base_osx())
    i64row("nv_va_uvm_sz", P.va.uvm_size())
    i64row("nv_va_uvm_base", P.va.uvm_base_osx())
    i64row("nv_va_uvm_top", va.uvm_top_osx())
    i64row("nv_va_hostobj", H.i64_of_hi_lo(0, HOST_OBJ_BASE()))
    # THE COMMENT'S CLAIM. `uvm_vaddr_allocator.size == (1<<48)-1`, so
    # base+size is 2^49-1 on OSX and NOT 2^48-1: the "VA space is 48bits" note
    # counts the ALLOCATOR's size, not the top address, and the two differ by
    # the base. `nv_va_top_is_48` says so rather than letting a reader assume.
    brow("nv_va_size_is_48", Bool.not(String.eq(U32.show(H.hi32(P.va.uvm_size())), "0")))
    row("nv_va_uvm_base_hi", H.hi32(P.va.uvm_base_osx()))
    row("nv_va_uvm_base_lo", H.lo32(P.va.uvm_base_osx()))
# --- 3: the ifaces and the four encode rules, :559-567 ----------------------
def SM_130() -> U32: 304
# :277 `self.image = image.ljust(round_up(len(image), 0x1000) + 0x1000, 0)` --
# "NOTE: Ensure at least 4KB of space after the program to mitigate prefetch
# memory faults". The +0x1000 is the NOTE and it is 4096 bytes of slack.
def pd.image_len(img: U32) -> U32: U32.add(H.round_up_u32(img, 4096), 4096)
# :273 `self.vars = [dtypes.u64 if mock else dt for _,_,dt,_ in
# signature[nbufs:]]` and :272 `nbufs = sum(name is None for name, *_ in
# signature)`. A MOCKGPU program wants EVERY var 64 bit and counts the buffers
# and the vars out of cbuf_0 at :274, which is why `nvars` is a field.
def SM_A04_HI() -> U32: 2564
def pc_three() -> P.PC: P.pc_one(P.pc_two(), P.K1_OTHER_DEV())
# --- 20: `to_name`, the tags and the profiler, hcq2.py:63 and :793-824 ----
def K1_TWO_DEVS() -> P.PKey: P.PKey{100, 0, 1}
def t_cache() -> IO(Unit):
  do IO<Unit>:
    # THE KEY IS A PAIR and both halves are load-bearing. The `devs` half is the
    # one a reader forgets: `nv_find_dev_matters` says the same ELF on a second
    # device is a DIFFERENT key.
    row("nv_find_k1_0", P.pc.find(P.K1(), Nil{}))
    row("nv_find_k1_at0", P.pc.find(P.K1(), [P.K1(), P.K2()]))
    row("nv_find_k2_at1", P.pc.find(P.K2(), [P.K1(), P.K2()]))
    row("nv_find_missing", P.pc.find(P.K2(), [P.K1()]))
    row("nv_find_dev_matters", P.pc.find(P.K1_OTHER_DEV(), [P.K1()]))
    row("nv_find_devs2_matters", P.pc.find(K1_TWO_DEVS(), [P.K1()]))
    row("nv_find_dup_first", P.pc.find(P.K1(), [P.K1(), P.K1_OTHER_DEV()]))
    # FIRST-WINS on the reverse direction: `nv_find_dup_first` answers 0 and a
    # last-wins scan answers 1. That is the row, and it is the only thing that
    # tells the two apart.
    brow("nv_find_dup_is_first", U32.is_eq(P.pc.find(P.K1(), [P.K1(), P.K1_OTHER_DEV()]), 0))
    # THE EVICTION POLICY, WHICH IS ABSENT. Three distinct keys and the count is
    # three; a fourth put of an EXISTING key does not grow it. Both rows, and the
    # second is the NEGATIVE case the brief asks for: an entry that must NOT be
    # added again, so a port that appended on every lookup or invented an LRU
    # fails one of the two.
    +a : P.PC <- IO.pure(P.PC, pc_three())
    row("nv_pc_grow_0", P.PC.n(P.PC.of()))
    row("nv_pc_grow_1", P.PC.n(P.pc_one(P.PC.of(), P.K1())))
    row("nv_pc_grow_3", P.PC.n(a))
    row("nv_pc_grow_repeat", P.PC.n(P.pc_one(a, P.K2())))
    row("nv_pc_grow_repeat_k1", P.PC.n(P.pc_one(a, P.K1())))
    row("nv_pc_miss_3", P.PC.miss(a))
    row("nv_pc_hit_1", P.PC.hit(P.pc_one(a, P.K2())))
    # THE BUFFER IDS come from `next(UOp.unique_num)` AND not from the count, so
    # a hit does not advance them and a miss does.
    row("nv_pc_id_0", P.pc.new_id(P.PC.of()))
    row("nv_pc_id_after_3", P.pc.new_id(a))
    # THE first site is a hit on a cache that does not yet hold the key, AND the
    # SECOND (BELOW) IS a hit on one that does. THEY are two fixtures and they
    # USED to share one name, WHICH is how a value can be right at one site and
    # WRONG at the other with nothing saying which is which.
    row("nv_pc_id_after_miss_hit", P.pc.new_id(P.pc_one(a, P.K2())))
    # A HIT ADVANCES NOTHING. `UOp.unique_num` is a monotone counter over every
    # unique num the process mints, so its ABSOLUTE value is not the cache size
    # and this port numbers from 0 because nothing else here consumes it. The
    # claim with teeth is the NEXT TWO ROWS: a lookup of a key already present
    # must not append an id and must not advance the counter, and a port that
    # appended on every lookup prints `0,1,2,2` and `4` here.
    +b2 : P.PC <- IO.pure(P.PC, P.pc_one(a, P.K2()))
    row("nv_pc_id_after_hit", P.pc.new_id(b2))
    lrow("nv_pc_ords_after_hit", P.PC.ord(b2))
    lrow("nv_pc_ords", P.PC.ord(a))
# --- 16: the launch refusals and the launch word trace, :161-186 -----------
# three uint64 buffers and no vars: what every 3-input float kernel looks like.
def args.buf3() -> List<&2, U32>: [P.W64(), P.W64(), P.W64()]
def dev.vid_msg(viddec: U32, +name: String) -> String:
  Bool.pick(String, P.dev.vid_ok(viddec), "",
    String.concat([name, " ", P.DEV_ERR_VID()]))
# `round_up(h, 64)`, twice in every one of these, so it is its own def.
def relocs0() -> List<&2, P.Rb>: [P.Rb{16, 8, P.RELOC_64()}, P.Rb{32, 8, P.RELOC_32()}]
def cq.ts(h: U32, l: U32, t: P.Tr) -> P.Tr: P.cq.semaphore(h, l, 0, P.DMA_SEM_FOUR(), t)
# :110 `NVQueue.wait` -- `sem(signal.getaddr(self.devs), value,
# operation="acq_circ_geq")`. Four words and no trailing interrupt.
def q.wait(addr: U32, value: U32, t: P.Tr) -> P.Tr: P.q.sem(addr, value, P.flags.wait(), t)
# :115 `NVQueue.release` -- `if not timestamp: self.nvm(0,
# NVC56F_NON_STALL_INTERRUPT, 0x0)`. THE NEGATIVE GUARD, and it is the whole of
# the difference between `signal` and `timestamp`: a signal is six words and a
# timestamp is four.
# `"en" if timestamp else "dis"` reduced to a U32, so the two arms are the two
# table rows `V_SEM_RELEASE_TIMESTAMP_EN`/`_DIS` and not a Python ternary.
def q.timestamp(addr: U32, t: P.Tr) -> P.Tr: P.q.release(addr, 0, True{}, t)
# :156-159 `NVComputeQueue.memory_barrier` -- `self.prev_qmd = None` FIRST, then
# the invalidate. The None matters: it forces the NEXT launch to open its own
# PCAS pair instead of chaining onto the previous QMD, which is the whole point
# of a barrier and the reason `cq.exec` reads `Dev.nqmd`.
# --- 11: `nv_iowr`, :43-45 ---------------------------------------------------
def Dev.of() -> P.Dev: P.Dev{0, 0, 0, 0, 0, 0, 1, 0, False{}, 0, P.Tr.of()}
# --- 4: the class ladders, :404-412 ----------------------------------------
# THE THREE FIXTURE MASKS, generated by the oracle's `mask()` over the class
# sets below and not transcribed. `AMP` is a Blackwell-GPU-that-is-not-quite: it
# has ADA but not BLACKWELL, which is the only fixture that can tell a
# three-entry ladder from a two-entry one.
#   AMP = {TURING, AMPERE_GPFIFO, AMPERE_COMPUTE_B, ADA_COMPUTE_A,
#          AMPERE_DMA_COPY_B, NVC9B0}
#   OLD = {TURING, AMPERE_COMPUTE_B, AMPERE_DMA_COPY_B, NVC9B0}
#   NEW = AMP + {HOPPER, BLACKWELL_GPFIFO, BLACKWELL_COMPUTE_B, NVCFB0}
def cq.sig(h: U32, l: U32, v: U32, t: P.Tr) -> P.Tr: P.cq.semaphore(h, l, v, P.DMA_SEM_ONE(), t)
# ===========================================================================
# THE KERNEL ARGUMENT TRACE. `layout_args` (hcq2.py:74-76), and it is the
# contract `ops_webgpu.bend` and `ops_cl.bend` port: given the buffer list and
# the var list, WHERE does each one land in constant buffer 0.
#
# `iter_sig` (device.py:364-368) is
#   `yield (offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`
# and the `:=` REBINDS `offset`, so the advance is `round_up(off, k) + k`. See
# THE WALRUS IS LOAD-BEARING in the header: `device.bend:871` advances off the
# UNROUNDED offset and disagrees on any list whose widths are not all 8.
# ===========================================================================
# `ifaces = [NVKIface, PCIIface, MOCKIface]` spelled out, because
# `Compiled._select_iface` walks it FIRST-WINS and the order is the policy.
def cq.memory_barrier(fl: U32, d: P.Dev) -> P.Dev:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, +t}:
      P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, 0,
          P.nvm.emit(1, P.M_INVALIDATE_SHADER_CACHES_NO_WFI(), P.nvm.words_of(P.NVALS_ONE()),
                   P.NVM_TYP2(), [fl], t)}
# :189-195 `NVCopyQueue.copy`. THE STEP LOOP, and it is the one place a loop
# bound is a policy: `step := 1 << 31` and `for off in range(0, sz, step)`. A
# 2 GiB copy is therefore TWO or THREE commands per queue word, and the
# per-step length is `min(sz - off, step)` -- so the LAST step is short and every
# other is exactly 2^31. `nv_copy_step_*` pins both.
def COPY_NFUEL() -> Nat: 8n
# NOT A LOOP. `off += 1 << 31` OVERFLOWS a U32 once it passes 2^31 -- measured:
# for sz 2^31+1 the offset went 0, 2^31, 0, 2^31 and the loop only stopped when
# the fuel ran out, answering 8. `ceildiv(sz, step)` is the same number with no
# overflow, and the zero-size answer is the same 0. `nv_copy_nsteps_*` and
# `nv_copy_nsteps_zero` are the rows that would have caught it.
def flags.invalidate() -> U32:
  P.flags.go([P.flags.term(P.V_TRUE(), P.FLD_INV_INSTRUCTION()),
            P.flags.term(P.V_TRUE(), P.FLD_INV_GLOBAL_DATA()),
            P.flags.term(P.V_TRUE(), P.FLD_INV_CONSTANT())], 0)
# :195 `NVCopyQueue.copy`'s LAUNCH_DMA.
def t_queue() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, q.wait(ADDR_LO(), VAL64(), P.Tr.of()))
    lrow("nv_sem_wait", wstream(a))
    +b : P.Tr <- IO.pure(P.Tr, q.signal(ADDR_LO(), VAL64(), P.Tr.of()))
    lrow("nv_sem_signal", wstream(b))
    +c : P.Tr <- IO.pure(P.Tr, q.timestamp(ADDR_LO(), P.Tr.of()))
    lrow("nv_sem_timestamp", wstream(c))
    # THE NEGATIVE GUARD, and it is the WHOLE of the difference: a signal is six
    # words and a timestamp is four, because `if not timestamp` suppresses the
    # NON_STALL_INTERRUPT.
    row("nv_sig_n", U32.from_nat(List.length(&2, U32, wstream(b))))
    row("nv_ts_n", U32.from_nat(List.length(&2, U32, wstream(c))))
    row("nv_nsi_n", ncalls(P.CALL_WORD(), Tr.minted(P.M_NON_STALL_INTERRUPT(), 0, P.Tr.of())))
    row("nv_sig_value_kept", wnth(wstream(b), 0n, 0))
    +d : P.Dev <- IO.pure(P.Dev, cq.memory_barrier(flags.invalidate(), Dev.of()))
    +dt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(d))
    lrow("nv_membar", wstream(dt))
    # `memory_barrier` sets `prev_qmd = None`, which forces the next launch to
    # open its own PCAS pair. THAT IS THE POINT of the barrier and the row is
    # the nqmd slot, not the words.
    row("nv_membar_nqmd", Dev.nqmd(d))
    +e : P.Tr <- IO.pure(P.Tr, P.cq.copy(768, 0, ADDR_LO(), 0, ADDR_LO(), P.Tr.of()))
    lrow("nv_copy_cmd", wstream(e))
    +f : P.Tr <- IO.pure(P.Tr, cq.sig(0, ADDR_LO(), VAL32(), P.Tr.of()))
    lrow("nv_csema_one", wstream(f))
    +g : P.Tr <- IO.pure(P.Tr, cq.ts(0, ADDR_LO(), P.Tr.of()))
    lrow("nv_csema_four", wstream(g))
    # `hilo` is HIGH FIRST and the semaphore payload is LAST, so the pair reads
    # hi, lo, value and NOT lo, hi, value.
    row("nv_csema_head_hi", wnth(wstream(f), 0n, 0))
    row("nv_csema_3rd_is_value", wnth(wstream(f), 2n, 0))
    # THE COPY STEP LOOP. :191 `for off in range(0, sz, step:=1<<31)` and
    # :193 `min(sz - off, step)`. A 0-byte copy emits NOTHING, which is the
    # negative case a fixture that only used big sizes would miss.
    row("nv_copy_nsteps_0", P.copy.nsteps(0))
    row("nv_copy_nsteps_1", P.copy.nsteps(1))
    row("nv_copy_nsteps_half", P.copy.nsteps(4294967294))
    row("nv_copy_nsteps_768", P.copy.nsteps(768))
    row("nv_copy_nsteps_2147483648", P.copy.nsteps(2147483648))
    row("nv_copy_nsteps_2147483649", P.copy.nsteps(2147483649))
    row("nv_copy_nsteps_4294967295", P.copy.nsteps(4294967295))
    row("nv_copy_nsteps_4294967294", P.copy.nsteps(4294967294))
    row("nv_copy_step_half", P.copy.step.of(4294967294, 2147483648))
    row("nv_copy_step_last", P.copy.step.of(4294967295, 2147483648))
    row("nv_copy_step_0", P.copy.step.of(0, 0))
    row("nv_copy_step_1", P.copy.step.of(1, 0))
    row("nv_copy_step_300", P.copy.step.of(768, 0))
    row("nv_copy_step_full", P.copy.step.of(2147483648, 0))
    row("nv_copy_step_over", P.copy.step.of(2147483649, 0))
    # A U32 `sz` REACHES TWO STEPS AND NO MORE: the third needs sz > 2^32, which
    # is the 64-BIT WALL and is why `COPY_NFUEL` is 8 and not 2.
    row("nv_copy_step2", P.copy.nsteps(4294967295))
    row("nv_copy_nfuel", U32.from_nat(COPY_NFUEL()))
    # THE ZERO-SIZE NEGATIVE CASE, as a TRACE: no words at all.
    +z : P.Tr <- IO.pure(P.Tr, P.cq.copy(0, 0, ADDR_LO(), 0, ADDR_LO(), P.Tr.of()))
    row("nv_copy_zero_words", P.seen(z))
# --- 9: the kernel argument trace, hcq2.py:74-76 --------------------------
# --- 18: the video decoder sizing, :699-715 ------------------------------
def dev.vid_h(+pic_h: U32) -> U32: U32.div(U32.mul(2, pic_h), 3)
# ===========================================================================
# :35, :37-38 -- THE ERROR STRINGS and the two fault tables.
#
# `get_error_str(status) = f"{status}: {nv_gpu.nv_status_codes.get(status,
# 'Unknown error')}"` -- the `get` has a DEFAULT, so an unknown status is
# "Unknown error" and not a KeyError, and that is a row. The two fault tables at
# :37-38 are the OPPOSITE: they have NO default, so `NV_PFAULT_FAULT_TYPE[dt]`
# on an unknown type raises KeyError, and that asymmetry is the port's reason for
# two different shapes.
# ===========================================================================
def dev.vid_unk_size(viddec: U32) -> U32:
  Bool.pick(U32, U32.is_ge(viddec, P.CLASS_NVCFB0_VIDEO_DECODER()), P.VID_UNK_SIZE(), 0)
# `round_up(intra_top_off, 0x10000) + (64<<10)` IF unk_size > 0 ELSE None, and
# `None` here is 0 with `dev.vid_unk_none` beside it -- the decoder's `if
# self.dev.intra_unk_off is not None` at :224 reads the difference.
# `{} if self.ver >= 4 else {f"release{i}_payload64b": 1}` -- ver 3 needs the
# explicit 64-bit payload flag and ver 5 does not have the field.
def dev.vid_chroma(+w: U32, +h: U32) -> U32: U32.shrn(U32.mul(P.vid64(w), P.vid64(h)), 8n)
# :208 `h, w, frame_pos = 2 * ast.src[1].val // 3, ast.src[2].val, ...` -- the
# DECODER'S height is two thirds of the picture height, and it is an INTEGER
# floor, so 1080 gives 720 and 5 gives 3.
def dev.vid_top(+h: U32) -> U32:
  U32.mul(P.vid64(h), U32.add(U32.add(P.VID_ROW_BYTES(), 4864), U32.add(152, 2000)))
# `2<<20 if viddec_class >= NVCFB0_VIDEO_DECODER else 0` -- the NEW decoder class
# gets the unknown-region buffer and the OLD one does not, so a port that made
# this unconditional would reserve 2 MiB on every card.
def dev.vid_coloc(+w: U32, +h: U32) -> U32:
  H.round_up_u32(U32.add(U32.mul(P.vid64(h), P.vid64(h)),
    U32.div(U32.mul(P.vid64(w), P.vid64(h)), 16)), P.VID_ROUND())
# `round_up(h, 64) * (608 + 4864 + 152 + 2000)` -- the four numbers are the
# decoder's per-row buffers and their SUM is one constant here because they are
# adjacent in the source with no arithmetic between them.
def dev.vid_unk_none(unk: U32) -> Bool: U32.is_zero(unk)
# :206 `filter_sz = round_up(round_up(intra_top_off, 0x10000) + (64<<10) +
# intra_unk_size, 2<<20)`. The unk size is INSIDE the round_up, so an OLD card's
# filter buffer is SMALLER by 2 MiB than a NEW card's for the same resolution.
def t_vid() -> IO(Unit):
  do IO<Unit>:
    # THE REFUSAL, and `None` is 0 here while `dev.vid_ok` is what reads it.
    brow("nv_vid_ok_new", P.dev.vid_ok(P.CLASS_NVCFB0_VIDEO_DECODER()))
    brow("nv_vid_ok_old", P.dev.vid_ok(P.CLASS_NVC9B0_VIDEO_DECODER()))
    brow("nv_vid_ok_none", P.dev.vid_ok(0))
    brow("nv_vid_none_refuses", Bool.not(P.dev.vid_ok(0)))
    srow("nv_vid_msg_none", dev.vid_msg(0, "NV:0"))
    srow("nv_vid_msg_ok", dev.vid_msg(P.CLASS_NVCFB0_VIDEO_DECODER(), "NV:0"))
    # THE DECODER'S OWN WIDTHS, and :208 derives the decoder height from the
    # picture height as `2 * ast.src[1].val // 3` -- an INTEGER floor.
    row("nv_vid_h_1080", dev.vid_h(1080))
    row("nv_vid_h_720", dev.vid_h(720))
    row("nv_vid_h_5", dev.vid_h(5))
    row("nv_vid_h_3", dev.vid_h(3))
    row("nv_vid_h_1", dev.vid_h(1))
    row("nv_vid_coloc_64_64", dev.vid_coloc(64, 64))
    row("nv_vid_coloc_1280_720", dev.vid_coloc(1280, 720))
    row("nv_vid_coloc_1920_1080", dev.vid_coloc(1920, 1080))
    row("nv_vid_coloc_3840_2160", dev.vid_coloc(3840, 2160))
    row("nv_vid_coloc_0_0", dev.vid_coloc(0, 0))
    row("nv_vid_top_64", dev.vid_top(64))
    row("nv_vid_top_720", dev.vid_top(720))
    row("nv_vid_top_1080", dev.vid_top(1080))
    row("nv_vid_top_2160", dev.vid_top(2160))
    row("nv_vid_top_0", dev.vid_top(0))
    # THE new decoder gets the unknown-REGION BUFFER AND the old one does not,
    # so an unconditional 2 MiB would reserve it on every card.
    row("nv_vid_unk_new", dev.vid_unk_size(P.CLASS_NVCFB0_VIDEO_DECODER()))
    row("nv_vid_unk_old", dev.vid_unk_size(P.CLASS_NVC9B0_VIDEO_DECODER()))
    row("nv_vid_unk_none", dev.vid_unk_size(0))
    row("nv_vid_unkoff_new", dev.vid_unk_off(5855232, 2097152))
    row("nv_vid_unkoff_old", dev.vid_unk_off(5855232, 0))
    brow("nv_vid_unk_is_none_old", dev.vid_unk_none(0))
    # THE new row was wrong side up. It read
    # `Bool.not(dev.vid_unk_none(2097152))` under the name `..._is_none_new`, so it
    # printed True where the claim is False -- and no oracle row existed to say so.
    # `intra_unk_off is None` is EXACTLY `intra_unk_size == 0` (:705), so a new
    # card is the NOT-None arm and this row now says False, which is the truth.
    brow("nv_vid_unk_is_none_new", dev.vid_unk_none(2097152))
    row("nv_vid_filter_new", dev.vid_filter(5855232, 2097152))
    row("nv_vid_filter_old", dev.vid_filter(5855232, 0))
    # THE 256-BYTE UNIT of :206 -- `round_up(w,64)*round_up(h,64) >> 8` -- and it
    # is the same shift the offsets use, which `nv_vid_chroma_*` shows.
    row("nv_vid_chroma_64_64", dev.vid_chroma(64, 64))
    row("nv_vid_chroma_1280_720", dev.vid_chroma(1280, 720))
    row("nv_vid_chroma_1920_1080", dev.vid_chroma(1920, 1080))
    row("nv_vid_chroma_3840_2160", dev.vid_chroma(3840, 2160))
# --- 19: the error strings and the two fault tables, :35 and :37-38 --------
# :208 `h, w, frame_pos = 2 * ast.src[1].val // 3, ast.src[2].val, ...` -- the
# DECODER'S height is two thirds of the picture height, and it is an INTEGER
# floor, so 1080 gives 720 and 5 gives 3.
def FAULT_PDE() -> String: "NV_PFAULT_FAULT_TYPE_PDE"
# `2<<20 if viddec_class >= NVCFB0_VIDEO_DECODER else 0` -- the NEW decoder class
# gets the unknown-region buffer and the OLD one does not, so a port that made
# this unconditional would reserve 2 MiB on every card.
def qmd.payload64b(v: U32) -> Bool: Bool.not(U32.is_ge(v, 4))
# ===========================================================================
# :230-305 -- NVProgramData. THE DERIVATIONS, and every one of them is a pure
# function of five numbers: `regs`, `shmem`, `cbuf0_size`, the signature length
# and the image length.
#
# `nbytes` IS NOT A FIELD ANYWHERE IN HERE, the same rule `device.bend` states
# for a Buffer: it is a derivation from its inputs, so storing it would let two
# copies disagree. `image_len` and `kernargs` are DERIVED and the gate reads the
# derivations.
# ===========================================================================
# :54 `self.ver, self.sz = (5, 0x60) if dev.iface.compute_class >=
# nv_gpu.BLACKWELL_COMPUTE_A else (3, 0x40)` -- ONE comparison decides the whole
# QMD layout and it is `>=`.
# the ordinal of the refusal that should fire, so a fixture can reach each
# raise site. 0 = never, which is every successful fixture.
def Tr.fail_at(t: P.Tr, n: U32) -> P.Tr:
  match t:
    case P.Tr{calls, next, bad_at, seen, refused}:
      P.Tr{calls, next, n, seen, refused}
# an EMPTY trace that keeps `bad_at` and `seen`, so a gate can read one queue
# without the device init in front of it and still number its refusals from one.
# `else: raise RuntimeError(f"unknown NV reloc {typ}")`. THE MESSAGE, and the
# number in it is the reloc TYPE and not the arm index.
def pd.reloc_msg(+typ: U32) -> String:
  Bool.pick(String, U32.is_zero(P.pd.reloc_kind(typ)),
            String.concat(["unknown NV reloc ", U32.show(typ)]), "")
# THE FOLD, and it is where the refusal LIVES: an unknown type contributes
# NOTHING to the list, so a later-known reloc is not appended either. That is the
# port's "the raise happens HERE and not later", and `nv_reloc_bad_n` is the row.
def SM_110() -> U32: 272
def SM_121() -> U32: 289
def PD_MOCK() -> P.PData: P.pd.of(P.CLASS_AMPERE_COMPUTE_B(), 0, 1024, 0, 5, 3, 2, 8192, True{})
# the mixed fixture, which is the only one that can see the walrus.
def PD_AMPERE() -> P.PData: P.pd.of(P.CLASS_AMPERE_COMPUTE_B(), 64, 1024, 352, 5, 3, 2, 8192, False{})
# :696-697 the two commands the raise submits, and they carry DIFFERENT numbers:
# `data64(shader_local_mem._buf)` is the buffer's ADDRESS and
# `data64(bytes_per_tpc)` is the PER-TPC byte count, then 0xff.
def pd.var_isize(p: P.PData, k: U32) -> U32:
  Bool.pick(U32, P.PData.mock(p), P.W64(), k)
# ===========================================================================
# :261-265 -- THE RELOC TABLE, BOTH DIRECTIONS. A reloc either lands in the
# image at its own offset as a 64-bit pointer, four bytes later as a 32-bit
# pointer, or four bytes later as a 32-bit POINTER SHIFTED BY 32 -- which is the
# high half of one 64-bit address, so `relocs` and `set_addr` are the same fact
# written twice -- or it is a type this backend does not know, and Python raises
# `RuntimeError(f"unknown NV reloc {typ}")`.
# ===========================================================================
# :279 `self.kernargs_size = round_up(max(self.constbufs[0][1],
# len(self.cbuf_0) * 4 + len(signature) * 8), 256)`. THREE TERMS and a max:
# the constant buffer's own declared size, the driver params, and EIGHT BYTES A
# SIGNATURE ENTRY -- the 8 is a conservative bound and NOT a sum of the entry's
# own itemsize, so a program with five uint32 vars is budgeted as 40 bytes of
# args while `layout_args` only spends 12. That gap IS the padding, and a port
# that budgeted the signature's real size would under-allocate cbuf_0. Both
# numbers are `U32` and both are read twice, so the max is a def.
def pd.kernargs(+p: P.PData) -> U32:
  H.round_up_u32(P.pd.max2(P.PData.cbuf0(p),
    U32.add(U32.mul(P.pd.cbuf0_len(p), 4), U32.mul(P.PData.nsig(p), 8))), 256)
# :305 `self.max_threads = ((65536 // round_up(max(1, regs) * 32, 256)) // 4) * 4
# * 32` -- "Registers allocation granularity per warp is 256, warp allocation
# granularity is 4. Register file size is 65536". THREE divisions and a max(1,
# regs): a MOCK program has regs 0 and must still divide by 256.
def pd.max_threads(regs: U32) -> U32:
  U32.mul(U32.mul(U32.div(U32.div(65536, H.round_up_u32(U32.mul(P.pd.r1(regs), 32), 256)), 4), 4), 32)
# :293 `smem_cfg = min(shmem_conf * 1024 for shmem_conf in [32, 64, 100] if
# shmem_conf * 1024 >= shmem) // 4096 + 1`. THREE CANDIDATES and a MIN, and the
# MIN IS OVER AN EMPTY SEQUENCE for shmem > 102400 -- which Python reports as
# `ValueError("min() iterable argument is empty")`. That refusal is the row
# `nv_smemcfg_too_big` and it is the only one in this section.
def t_pdata() -> IO(Unit):
  do IO<Unit>:
    row("nv_pd_ver_ampere", P.PData.ver(PD_AMPERE()))
    row("nv_pd_ver_mock", P.PData.ver(PD_MOCK()))
    row("nv_pd_ver_bw", P.PData.ver(PD_BW()))
    # :268 min_cbuf0_entries, and it is the SAME predicate as the QMD version.
    row("nv_pd_min_cbuf0_ampere", P.pd.min_cbuf0(P.PData.ver(PD_AMPERE())))
    row("nv_pd_min_cbuf0_bw", P.pd.min_cbuf0(P.PData.ver(PD_BW())))
    brow("nv_cbuf0_by_ver", Bool.and(Bool.not(U32.is_eq(P.pd.min_cbuf0(3), P.pd.min_cbuf0(5))),
      Bool.or(U32.is_eq(P.pd.min_cbuf0(3), 12), U32.is_eq(P.pd.min_cbuf0(5), 224))))
    row("nv_pd_cbuf0_len_ampere", P.pd.cbuf0_len(PD_AMPERE()))
    row("nv_pd_cbuf0_len_bw", P.pd.cbuf0_len(PD_BW()))
    row("nv_pd_cbuf0_len_mock", P.pd.cbuf0_len(PD_MOCK()))
    # :279 kernargs_size, and the EIGHT-BYTES-A-ENTRY bound is the row: the
    # signature is five entries and two uint32 vars, so the budget is 40 bytes
    # where `layout_args` spends 12.
    row("nv_pd_kernargs_ampere", pd.kernargs(PD_AMPERE()))
    row("nv_pd_kernargs_bw", pd.kernargs(PD_BW()))
    row("nv_pd_kernargs_mock", pd.kernargs(PD_MOCK()))
    row("nv_pd_kernargs_0sig", pd.kernargs(P.pd.of(P.CLASS_AMPERE_COMPUTE_B(), 64, 1024, 352, 0, 0, 0, 8192, False{})))
    # :305 max_threads, and regs 0 is the MOCK case.
    row("nv_pd_maxthreads_0", pd.max_threads(0))
    row("nv_pd_maxthreads_1", pd.max_threads(1))
    row("nv_pd_maxthreads_16", pd.max_threads(16))
    row("nv_pd_maxthreads_32", pd.max_threads(32))
    row("nv_pd_maxthreads_40", pd.max_threads(40))
    row("nv_pd_maxthreads_64", pd.max_threads(64))
    row("nv_pd_maxthreads_256", pd.max_threads(256))
    row("nv_pd_maxthreads_1024", pd.max_threads(1024))
    row("nv_pd_maxthreads_2048", pd.max_threads(2048))
    # :293 smem_cfg and its REFUSAL -- `min()` over an empty sequence.
    row("nv_smemcfg_0", P.pd.smem_cfg(0))
    row("nv_smemcfg_1024", P.pd.smem_cfg(1024))
    row("nv_smemcfg_32768", P.pd.smem_cfg(32768))
    row("nv_smemcfg_65536", P.pd.smem_cfg(65536))
    row("nv_smemcfg_102400", P.pd.smem_cfg(102400))
    brow("nv_smemcfg_too_big", Bool.not(P.smemcfg.ok(131071)))
    brow("nv_smemcfg_ok_max", P.smemcfg.ok(102400))
    # THE refusal'S own two rows, because `nv_smemcfg_too_big` only says THAT it
    # refuses and CPython's answer is a STRING: `min() iterable argument is empty`
    # is what Python 3's `min()` says, and a port that wrote "smem too large"
    # would satisfy the boolean and fail the diff.
    srow("nv_smemcfg_msg_131071", pd.smem_cfg.msg(131071))
    srow("nv_smemcfg_msg_102400", pd.smem_cfg.msg(102400))
    srow("nv_smemcfg_msg_0", pd.smem_cfg.msg(0))
    srow("nv_smemcfg_msg_big", pd.smem_cfg.msg(131072))
    # :277 the image padding, and the +4KB is the NOTE.
    row("nv_pd_image_0", pd.image_len(0))
    row("nv_pd_image_1", pd.image_len(1))
    row("nv_pd_image_4095", pd.image_len(4095))
    row("nv_pd_image_4096", pd.image_len(4096))
    row("nv_pd_image_4097", pd.image_len(4097))
    row("nv_pd_image_8192", pd.image_len(8192))
    # :273 mockgpu wants every var 64 bit.
    row("nv_pd_var_isize_mock4", pd.var_isize(PD_MOCK(), 4))
    row("nv_pd_var_isize_mock8", pd.var_isize(PD_MOCK(), 8))
    row("nv_pd_var_isize_amp4", pd.var_isize(PD_AMPERE(), 4))
# --- 14: the reloc table, :261-265, BOTH DIRECTIONS ------------------------
# :821-822 the row builder, and the FIELDS are `regOp`, `regType`, `regOffset`,
# `regValueLo`, `regAndNMaskLo` -- five, in that order, and `regOp` is
# `NV2080_CTRL_GPU_REG_OP_WRITE_32` at the default and `regType` is 0.
def REG_OP_WRITE_32() -> U32: 1
def pfault.status_n() -> U32: 142
# `next((c for c in [...] if c in ...), None)` -- the access table's NONE arm is
# the same `None` `dev.vid_ok` reads.
# THE table has nine entries and they are not contiguous: 4 is WEAK and 8, 9, 10
# are READ, WRITE, ATOMIC. A catch-all answered WEAK for all three and
# `nv_paccess_8/9/10` said so.
# :200-201 `timestamp` and `signal` -- one word semaphore vs four, and the only
# difference is the second command's flag word.
def t_flags() -> IO(Unit):
  do IO<Unit>:
    row("nv_flags_wait", P.flags.wait())
    row("nv_flags_signal", P.flags.release(0))
    row("nv_flags_timestamp", P.flags.release(1))
    row("nv_flags_invalidate", flags.invalidate())
    row("nv_flags_copy", P.flags.copy_dma())
    row("nv_flags_dma1", P.flags.dma_sem(P.DMA_SEM_ONE()))
    row("nv_flags_dma4", P.flags.dma_sem(P.DMA_SEM_FOUR()))
    row("nv_flags_ctrl", flags.ctrl())
    # THE SHIFTS, one row each. Every one of these eleven was read out of
    # `nv_570` and a wrong one is a silently wrong command word.
    row("nv_fld_sem_payload", P.FLD_SEM_PAYLOAD_SIZE())
    row("nv_fld_sem_operation", P.FLD_SEM_OPERATION())
    row("nv_fld_sem_wfi", P.FLD_SEM_RELEASE_WFI())
    row("nv_fld_sem_ts", P.FLD_SEM_RELEASE_TIMESTAMP())
    row("nv_fld_dma_semtype", P.FLD_DMA_SEMAPHORE_TYPE())
    row("nv_fld_inv_const", P.FLD_INV_CONSTANT())
    row("nv_fld_ctrl_testrun", P.FLD_CTRL_TESTRUN_ENV())
    # THE REDUCE IS AN OR, so the kwarg order does not matter. The reordered
    # release is a separate def for exactly that reason: a port that appended
    # the terms in a fixed order would pass `nv_flags_signal` and this is the
    # row that says the order is not load-bearing either.
    row("nv_flags_signal_reordered", flags.release.reordered(0))
    brow("nv_flags_signal_reorder_same", U32.is_eq(flags.release.reordered(0), P.flags.release(0)))
    # THE 31-BIT CEILING. `U32.shln` saturates past 31 and no flag here sits
    # above bit 25, so `nv_shift_25` is not saturated and `nv_shift_32` IS --
    # which is the boundary, stated rather than assumed.
    row("nv_shift_25", P.flags.term(1, 25))
    row("nv_shift_26", P.flags.term(1, 26))
    row("nv_shift_32", P.flags.term(1, 32))
    row("nv_shift_31", P.flags.term(1, 31))
    row("nv_term_2_at_24", P.flags.term(2, 24))
# --- 8: the queues' command sequences -------------------------------------
def CLASS_DMA() -> U32: 4
def dev.sleep_timeout_ms() -> U32: 200
# `ifaces = [NVKIface, PCIIface, MOCKIface]` spelled out, because
# `Compiled._select_iface` walks it FIRST-WINS and the order is the policy.
def SM_101() -> U32: 257
# --- 1: arch and sass, :601-602 --------------------------------------------
def SM_86() -> U32: 134
def SM_89() -> U32: 137
# :451 `size = round_up(size, page_size)`. The ROUNDING IS NOT OPTIONAL: a 4097
# byte buffer becomes 8192 and the extra page is real device memory, so
# `nv_allocsz_*` is a row per fixture and not one row for the function.
def dev.renderers() -> U32: 4
def dev.runtime_is_null() -> Bool: True{}
# The STARTING TRACE is a parameter so a gate can ARM a refusal before the init
# runs: `Tr.fail_at(Tr.of(), 6)` makes the sixth emit the one that raises, and
# `dev.init` threads it through every step. Arming it afterwards would be a
# no-op, which is the bug this shape exists to prevent.
# `cmd or (...)` -- the explicit-command arm, which is EVERY `uvm()` call (:400
# passes `cmd=cmd`). 0 is not a legal encoded word, because the read bit is
# always set, so 0 is a safe sentinel for "no explicit command".
def SM_100() -> U32: 256
def t_arch() -> IO(Unit):
  do IO<Unit>:
    srow("nv_arch_86", P.arch_of(SM_86()))
    srow("nv_arch_89", P.arch_of(SM_89()))
    srow("nv_arch_90", P.arch_of(SM_90()))
    srow("nv_arch_a04", P.arch_of(SM_A04_HI()))
    srow("nv_arch_100", P.arch_of(SM_100()))
    srow("nv_arch_110", P.arch_of(SM_110()))
    srow("nv_arch_120", P.arch_of(SM_120()))
    srow("nv_arch_121", P.arch_of(SM_121()))
    srow("nv_arch_130", P.arch_of(SM_130()))
    srow("nv_arch_101", P.arch_of(SM_101()))
    row("nv_sass_86", P.sass_of(SM_86()))
    row("nv_sass_89", P.sass_of(SM_89()))
    row("nv_sass_90", P.sass_of(SM_90()))
    row("nv_sass_a04", P.sass_of(SM_A04_HI()))
    row("nv_sass_100", P.sass_of(SM_100()))
    row("nv_sass_110", P.sass_of(SM_110()))
    row("nv_sass_120", P.sass_of(SM_120()))
    row("nv_sass_121", P.sass_of(SM_121()))
    row("nv_sass_130", P.sass_of(SM_130()))
    row("nv_sass_101", P.sass_of(SM_101()))
    i64row("nv_win_shared", P.win_shared())
    i64row("nv_win_local", P.win_local())
    # THE blackwell special case is its own row, because `"sm_120" if
    # sm_version==2564` is not what the f-string would say and 2564's high
    # digit is 10 -- so a port that deleted the special case prints "sm_1010".
    brow("nv_arch_a04_is_special", String.eq(P.arch_of(SM_A04_HI()), "sm_120"))
    brow("nv_arch_a04_not_fstring", Bool.not(String.eq(P.arch_of(SM_A04_HI()), "sm_1010")))
    # :609 the four renderers and the NULL runtime, and both are properties of
    # the backend: it has no Program, it goes through the hcq2 queues.
    row("nv_renderers", dev.renderers())
    brow("nv_runtime_null", dev.runtime_is_null())
    row("nv_sleep_ms", dev.sleep_timeout_ms())
# --- 2: the VA bump allocators, :347-351 ------------------------------------
def M_NEW() -> U32: 1919
# `ops_nv.py:357-359` -- the version table picker. THE THRESHOLDS ARE 615, 610
# AND 580 AND THEY ARE DESCENDING, so the first one that holds wins. A
# port that writes them ascending picks the wrong table for a driver between
# 610 and 615, and `nv_mock_drv_*` is the row that sees it.
def drv_table_of(+major: U32) -> U32:
  Bool.pick(U32, U32.is_ge(major, 615), 615,
    Bool.pick(U32, U32.is_ge(major, 610), 610,
      Bool.pick(U32, U32.is_ge(major, 580), 580, 570)))
# :79 `self.set_addr("program_address", addr >> (4 if self.ver >= 4 else 0),
# "_shifted4" if self.ver >= 4 else "")` -- the ADDRESS is shifted for ver 5 and
# the FIELD NAME says so, and the same shape holds for the constant buffer's
# `_shifted6_`. Both are rows because both are silent-wrong-kernel shapes, and
# `qmd.cbuf_sfx`'s index is a String because Python builds it with an f-string
# and `U32.show` is the only way to get one.
def qmd.prog_shift(v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 4, 0)
def uvms(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_UVM(), P.Tr.calls(t))
def pd.reloc_kind_n() -> U32: 3
# :112 `NVQueue.timestamp` -> `release(signal, UOp.const(0, uint64),
# timestamp=True)`.
def iowr.cmd.at(+explicit: U32, nbytes: U32, nr: U32) -> U32:
  Bool.pick(U32, U32.is_zero(explicit), P.iowr.cmd(nbytes, nr), explicit)
# :45 `if ret != 0: raise RuntimeError(f"ioctl returned {ret}")`. THE REFUSAL, and
# `ret` is the ioctl's return value, which the seam supplies.
def t_iowr() -> IO(Unit):
  do IO<Unit>:
    row("nv_iowr_0_0", P.iowr.cmd(0, 0))
    row("nv_iowr_4_1", P.iowr.cmd(4, 1))
    row("nv_iowr_64_44", P.iowr.cmd(64, 44))
    row("nv_iowr_40_43", P.iowr.cmd(40, 43))
    row("nv_iowr_96_65", P.iowr.cmd(96, 65))
    row("nv_iowr_1280_2", P.iowr.cmd(1280, 2))
    row("nv_iowr_8191_136", P.iowr.cmd(8191, 136))
    # THE MASK ROW. 8192 & 0x1FFF is 0, so the size field VANISHES and the word
    # reads as if the struct were empty. `nv_iowr_8192_1` and `nv_iowr_4_1`
    # differ only in the size, so a port that dropped the mask answers
    # `nv_iowr_8192_1 = nv_iowr_0_0`.
    row("nv_iowr_8192_1", P.iowr.cmd(8192, 1))
    row("nv_iowr_8192_255", P.iowr.cmd(8192, 255))
    # THE MASK MAKES THEM EQUAL, which is the bug it prevents: an 8 KiB struct
    # encodes as if it were empty.
    brow("nv_iowr_size_is_same", u32_list_eq([P.iowr.cmd(8192, 1)], [P.iowr.cmd(0, 1)]))
    # `cmd or (...)` -- the explicit arm every uvm() call takes, and 0 is a safe
    # sentinel because the read bit makes a real word non-zero.
    row("nv_iowr_explicit_kept", iowr.cmd.at(201, 40, 43))
    row("nv_iowr_explicit_0", iowr.cmd.at(0, 40, 43))
    # `0 or X` IS X, so a zero explicit word falls through to the DERIVED one --
    # and `cmd or (...)` is the only reason uvm() can pass `cmd=0`. The oracle's
    # `nv_iowr_0_0` is that derived word, so the two rows above already pin it;
    # this row says the same thing in the port's own terms and moves if the
    # sentinel arm is dropped.
    brow("nv_iowr_explicit_0_derived", U32.is_eq(iowr.cmd.at(0, 40, 43), P.iowr.cmd(40, 43)))
    # THE REFUSAL, and the message carries the ioctl's RETURN value.
    srow("nv_iowr_msg_0", iowr.msg(0))
    srow("nv_iowr_msg_5", iowr.msg(5))
    srow("nv_iowr_msg_4096", iowr.msg(4096))
# --- 12: the QMD field layer, :50-94 ---------------------------------------
def query_litter_n() -> U32: 3
# THE device count per interface. `MOCKIface` IS one by declaration; the other
# two ARE the card'S own count, WHICH is what `NVKIface.count` HOLDS after
# `NV_ESC_CARD_INFO`.
def fifo_field_names() -> List<&2, String>:
  ["ring", "gpput", "doorbell", "put_value"]
def prof.gpcs_with_tpc(n: U32) -> U32: U32.div(n, 2)
# ===========================================================================
# :664-665 `_query_gpu_info`'s INDEX FALLBACK, and it is the OTHER direction of
# a marshalling table:
#
#   `getattr(nv_gpu, 'NV2080_CTRL_GR_INFO_INDEX_' + r.upper(),
#            getattr(nv_gpu, 'NV2080_CTRL_GR_INFO_INDEX_LITTER_' + r.upper(), None))`
#
# The inner `getattr` has a DEFAULT OF ITS OWN, so a request with neither name
# answers None -- and `x.dataList[nvr]` would then raise. The outer default is
# LITTER, i.e. per-warp, so `max_warps_per_sm` and `num_sm_per_tpc` may come from
# a different table than `num_gpcs`. `nv_query_litter_n` is the COUNT row,
# because a table that transcribed the fallback for all five would pass every one
# of the five names.
# ===========================================================================
# :800 `SM_REG(gpc, tpc, sm, reg) = GPC_BASE + gpc * 0x4000 + 0x800 +
# (tpc * num_sm_per_tpc + sm) * 0x200 + reg` -- Blackwell. The SM index is
# `tpc * num_sm_per_tpc + sm`, so the SMs of one TPC are CONTIGUOUS.
def prof.sm_reg.bw(gpc: U32, tpc: U32, sm: U32, reg: U32, nsm: U32) -> U32:
  U32.add(U32.add(U32.add(P.PROF_BW_GPC_BASE(), U32.mul(gpc, P.PROF_GPC_STRIDE())),
                  P.PROF_SM_BASE_BW()),
          U32.add(U32.mul(U32.add(U32.mul(tpc, nsm), sm), P.PROF_SM_STRIDE()), reg))
# :805 `[0x400, 0x1000][sm]` -- the two SM bases are a LOOKUP.
# the trace readers every section below uses.
def dev.is_nvd(iface: U32) -> Bool: U32.is_eq(iface, 2)
# ===========================================================================
# :571-611 -- NVDevice.__init__, AS THE STEP LIST IT IS. Each step is one line
# range of the Python and takes the `Dev` it is handed, so the order IS the
# whole of the init and nothing else. `dev.init` is the trace the gate pins.
# ===========================================================================
# --- 10: the matcher pins itself ------------------------------------------
def dev.encode_count() -> U32: 4
# ===========================================================================
# :601-602 -- `arch` and `sass_version`, both pure functions of `sm_version`.
#
#   :601 `self.arch = "sm_120" if self.sm_version==0xa04 else
#          f"sm_{(self.sm_version>>8)&0xff}{(val>>4) if (val:=self.sm_version&0xff) > 0xf else val}"`
#   :602 `self.sass_version = ((self.sm_version & 0xf00) >> 4) | (self.sm_version & 0xf)`
#
# The `> 0xf` is the load-bearing half and it is a HEX-digit rule: sm_89 is
# `sm_08` and `9` because 0x89 & 0xff is 0x89, `>> 8 & 0xff` is 8 and
# `0x89 & 0xff` is 0x89 > 0xf, so the LOW digit is `0x89 >> 4`... no: `val` is
# `sm_version & 0xff` = 0x89 and 0x89 > 0xf, so the low digit is `0x89 >> 4` =
# 8. The FIXME above :600 ("no idea how to convert this for blackwells") is
# about that: sm_89 and sm_8a BOTH print `sm_08`.
# ===========================================================================
# --- 13: `NVProgramData`, :230-305 ------------------------------------------
# The fixture is a 3-buffer / 2-var program with 64 registers, 0x400 shared
# memory and the 0x160 cbuf0 size a real cuda program reports.
def dev.encode_rules() -> List<&2, String>:
  [P.ENC_COMPUTE(), P.ENC_COPY(), P.ENC_ENCDEC(), P.ENC_RAW()]
# ===========================================================================
# THE mock path. `MOCKIface`, AND the selection that reaches it.
#
# WHY this section exists at all, GIVEN that the mock is "JUST a driver".
#
# UPSTREAM'S NV MOCK IS A DRIVER SUBSTITUTION: `test/mockgpu/nv/nvdriver.py`
# INTERCEPTS `open()` AND `ioctl()` AT the python level, so `NVKIface` RUNS
# UNCHANGED against a software driver. THAT is why the mock needs no nvidia
# CARD.
#
# AND `MOCKIface` ITSELF IS NOT THE DRIVER. `class MOCKIface(NVKIface):
# count = 1` (`tinygrad/runtime/ops_nv.py:552`) INHERITS `NVKIface` WHOLE AND
# DIFFERS from it in exactly one way: `count = 1`. IT is a fallback
# INTERFACE, NOT a reimplementation. SO the port of it is tiny, AND what it
# MAKES TRUE IS:
#
#   1. THE count. `NVKIface.count` IS the number of GPUs THE card reports
#      (`len(NVKIface.gpus_info)`), and `MOCKIface`'s IS ONE. THE PORT MUST BE
#      ABLE to answer "HOW many devices does this interface claim" FOR both.
#   2. THE PAGE SIZE. `alloc`'s `page_size` is
#      `mmap.PAGESIZE if uncached or host else ((2 << 20) if size >= (8 << 20)
#       else (mmap.PAGESIZE if isinstance(self, MOCKIface) else 4 << 10))`
#      (`tinygrad/runtime/ops_nv.py:444-445`). THE mock branch is the host page
#      SIZE AND NOT 4 KiB, and `alloc.page_size`'s `mock` PARAMETER IS ALREADY
#      THAT BRANCH.
#   3. THE SELECTION. `device.py:473`, `filtered = [i for i in filtered if
#      t.interface.startswith("MOCK") or not i.__name__[:-5].startswith("MOCK")]`
#      -- "never fallback to mock ifaces". A MOCK INTERFACE SURVIVES A
#      SELECTION only when the target itself is a mock. `device.bend`'s
#      `iface_ok(is_mock, want_mock)` IS THAT RULE AND `device.bend`'s
#      `ifaces()` IS the placeholder list -- FOUR names that name no real
#      INTERFACE. `dev.iface_names` IS THE REAL LIST.
#
# THE THREE IFACE TAGS. `dev.is_nvd` ANSWERS `isinstance(self.iface, PCIIface)`
# (`tinygrad/runtime/ops_nv.py:568`), so THE tags must be the ladder'S order:
# 1 IS `NVKIface`, 2 IS `PCIIface`, 3 IS `MOCKIface`.
# ===========================================================================
def PCI_ROOT() -> U32: 3231741952
# THE mock'S trace'S three call counts. `NVKIface.__init__`'s SEQUENCE is
# `rm_alloc(ROOT)` THEN the version rm_control THEN `uvm(UVM_INITIALIZE)` THEN
# `uvm(UVM_MM_INITIALIZE)`, SO the counts are the shape of the init and not
# OF THE MOCK.
def t_iface() -> IO(Unit):
  do IO<Unit>:
    row("nv_iface_count", dev.iface_count())
    slrow("nv_encode_names", dev.encode_rules())
    row("nv_encode_count", dev.encode_count())
    # the encode names are matched with `arg="submit_nv_compute"`, so a
    # misspelling matches NOTHING and silently drops a queue's submit. The
    # reverse direction is the one that matters: a name that is not in the
    # table is not a queue.
    brow("nv_encode_exact", String.eq(P.ENC_COMPUTE(), "submit_nv_compute"))
    brow("nv_encode_raw_exact", String.eq(P.ENC_RAW(), "submit_nv_raw"))
    brow("nv_encode_bad", Bool.not(String.eq(P.ENC_COPY(), "submit_nv_cl")))
    brow("nv_is_nvd_2", dev.is_nvd(2))
    brow("nv_is_nvd_1", dev.is_nvd(1))
    brow("nv_pc_root_hi", U32.is_eq(PCI_ROOT(), 3231741952))
# --- 3b: the MOCK PATH, `MOCKIface` and the selection that reaches it -------
# THE interface tags, so a row can name WHICH interface it is about. THE order
# IS the ladder'S order and the order is the policy (`_select_iface` walks it
# FIRST-WINS), so THE INDEX IS THE TAG.
# :273 `self.vars = [dtypes.u64 if mock else dt for _,_,dt,_ in
# signature[nbufs:]]` and :272 `nbufs = sum(name is None for name, *_ in
# signature)`. A MOCKGPU program wants EVERY var 64 bit and counts the buffers
# and the vars out of cbuf_0 at :274, which is why `nvars` is a field.
def fifo_field_n() -> U32: 4
def QUERY_REQS_N() -> U32: 5
# `ix` is read by BOTH comparisons and `U32` is affine, so the `+` goes on the
# parameter -- the same shape `exec.ok.dims` uses and the reason the OR is one
# line and not two defs.
#
# MEASURED against nv_570, and this table has now been WRONG TWICE, both times
# caught only because the oracle ASKS `nv_570.__dict__` instead of writing the
# answer down. The first version claimed queries 1 and 3 fall back to LITTER and
# the second claimed 1, 2 and 3. Asking the dict: num_gpcs, num_tpc_per_gpc AND
# num_sm_per_tpc have NO `NV2080_CTRL_GR_INFO_INDEX_<R>` at all, so all three
# fall back and the positions are 0, 1 and 2 -- while max_warps_per_sm (13) and
# sm_version (12) have a plain INDEX. So the count is 3 and the set is the FIRST
# THREE, which no "interior requests" reading of the source would produce.
# A wrong answer here means `x.dataList[nvr]` reads the wrong attribute off
# `engineInfo[0].infoList` -- a per-warp count where a per-GPC one belonged.
# `nv_query_ix_*` prints each request's resolved index value, because a `False`
# row is worth printing only when the VALUE it is a function of is printed too.
# :823 `regAndNMaskLo=rest[0] if rest else 0xffffffff` -- the ONLY place a third
# operand changes a register write, and the default is all ones so a write with
# no mask writes the whole register.
def reg_mask(+rest: U32) -> U32:
  Bool.pick(U32, U32.is_zero(rest), P.REG_MASK_LO(), rest)
# :821-822 the row builder, and the FIELDS are `regOp`, `regType`, `regOffset`,
# `regValueLo`, `regAndNMaskLo` -- five, in that order, and `regOp` is
# `NV2080_CTRL_GPU_REG_OP_WRITE_32` at the default and `regType` is 0.
def prof.is_bw(compute: U32) -> Bool: U32.is_ge(compute, P.CLASS_BLACKWELL_COMPUTE_A())
# :800 `SM_REG(gpc, tpc, sm, reg) = GPC_BASE + gpc * 0x4000 + 0x800 +
# (tpc * num_sm_per_tpc + sm) * 0x200 + reg` -- Blackwell. The SM index is
# `tpc * num_sm_per_tpc + sm`, so the SMs of one TPC are CONTIGUOUS.
# :696-697 the two commands `_ensure_has_local_memory` uploads. `hilo.pair` is
# `data64` -- HIGH FIRST -- and the two commands are SEPARATE nvm calls, so the
# per-TPC byte count and the 0xff are in the second one only.
def t_tags() -> IO(Unit):
  do IO<Unit>:
    srow("nv_toname_program", P.to_name(["program"]))
    srow("nv_toname_ring_compute_0", P.to_name(["ring", "COMPUTE:0"]))
    srow("nv_toname_qmd_compute_0", P.to_name(["qmd", "COMPUTE:0"]))
    srow("nv_toname_gpput_copy_0", P.to_name(["gpput", "COPY:0"]))
    srow("nv_toname_doorbell_compute_0", P.to_name(["doorbell", "COMPUTE:0"]))
    srow("nv_toname_doorbell_copy_0", P.to_name(["doorbell", "COPY:0"]))
    srow("nv_toname_put_value_copy_0", P.to_name(["put_value", "COPY:0"]))
    srow("nv_toname_notifier_compute_0", P.to_name(["notifier", "COMPUTE:0"]))
    srow("nv_toname_two_parts", P.to_name(["COMPUTE", "0"]))
    srow("nv_toname_empty", P.to_name(Nil{}))
    # THE ORDER MATTERS and both halves are rows: the replace is on the ORIGINAL
    # case and the lower is last, so `to_name("COMPUTE", "0")` is `compute_0`.
    brow("nv_toname_colon_replaced", String.eq(P.to_name(["ring", "COMPUTE:0"]), "ring_compute_0"))
    brow("nv_toname_lower", String.eq(P.to_name(["QMD", "COPY:0"]), "qmd_copy_0"))
    slrow("nv_fifo_fields", fifo_field_names())
    row("nv_fifo_fields_n", fifo_field_n())
    # THE fifth GPFifo FIELD is not in the table, and that is the negative case:
    # :660 bufferizes ("ring", "gpput", "doorbell", "put_value") and NOT
    # "notifier". The row is NAMED FOR WHAT IT ANSWERS, so it prints False, and
    # False is the claim -- a port that wrongly added `notifier` to the table
    # flips it to True. (It was named `nv_notifier_not_bufferized` and printed
    # False, which made the name contradict its own value.)
    brow("nv_notifier_bufferized", notifier_bufferized())
    brow("nv_notifier_absent_from_table", Bool.not(List.contains(~String, ~String.eq, fifo_field_names(), "notifier")))
    brow("nv_ring_in_table", List.contains(~String, ~String.eq, fifo_field_names(), "ring"))
    # :819 `range(0, len(ops), 124)` and the last chunk is short.
    row("nv_regops_chunks_0", P.dev.reg_nchunks(0))
    row("nv_regops_chunks_1", P.dev.reg_nchunks(1))
    row("nv_regops_chunks_124", P.dev.reg_nchunks(124))
    row("nv_regops_chunks_125", P.dev.reg_nchunks(125))
    row("nv_regops_chunks_248", P.dev.reg_nchunks(248))
    row("nv_regops_chunks_1000", P.dev.reg_nchunks(1000))
    row("nv_regops_last_0", P.dev.reg_clen(0))
    row("nv_regops_last_1", P.dev.reg_clen(1))
    row("nv_regops_last_124", P.dev.reg_clen(124))
    row("nv_regops_last_125", P.dev.reg_clen(125))
    row("nv_regops_last_248", P.dev.reg_clen(248))
    row("nv_regops_last_1000", P.dev.reg_clen(1000))
    row("nv_reg_mask_default", reg_mask(0))
    row("nv_reg_mask_explicit", reg_mask(255))
    row("nv_reg_fields_n", reg_fields_n())
    row("nv_reg_op_write32", REG_OP_WRITE_32())
    # :777 ONE PREDICATE, three uses -- the QMD version, the min cbuf0 entries and
    # the profiler's register bases.
    brow("nv_prof_is_bw_ampere", prof.is_bw(P.CLASS_AMPERE_COMPUTE_B()))
    brow("nv_prof_is_bw_ada", prof.is_bw(P.CLASS_ADA_COMPUTE_A()))
    brow("nv_prof_is_bw_bwa", prof.is_bw(52672))
    brow("nv_prof_is_bw_bwb", prof.is_bw(P.CLASS_BLACKWELL_COMPUTE_B()))
    brow("nv_prof_shares_predicate", Bool.and(Bool.and(U32.is_eq(P.qmd.ver.of(52672), 5),
      U32.is_eq(P.pd.min_cbuf0(5), 224)), U32.is_eq(P.qmd.ver.of(P.CLASS_ADA_COMPUTE_A()), 3)))
    # :781 the TPC count is a POPCOUNT, not the mask.
    row("nv_prof_tpc_cnt_0", P.prof.tpc_cnt(0))
    row("nv_prof_tpc_cnt_1", P.prof.tpc_cnt(1))
    row("nv_prof_tpc_cnt_2", P.prof.tpc_cnt(2))
    row("nv_prof_tpc_cnt_3", P.prof.tpc_cnt(3))
    row("nv_prof_tpc_cnt_255", P.prof.tpc_cnt(255))
    row("nv_prof_tpc_cnt_65535", P.prof.tpc_cnt(65535))
    row("nv_prof_tpc_cnt_2147483648", P.prof.tpc_cnt(2147483648))
    row("nv_prof_gpcs", prof.gpcs_with_tpc(16))
    # :800 / :805 the two SM_REG arms. THE pre-BLACKWELL one counts the tpc INDEX
    # FROM THE END and its two SM bases are a LOOKUP, so sharing one def with the
    # Blackwell arm would be wrong in three places at once.
    row("nv_prof_smreg_bw_0_0_0", prof.sm_reg.bw(0, 0, 0, 296, 4))
    row("nv_prof_smreg_bw_1_2_3", prof.sm_reg.bw(1, 2, 3, 296, 4))
    row("nv_prof_smreg_bw_7_3_3", prof.sm_reg.bw(7, 3, 3, 296, 4))
    row("nv_prof_smreg_pre_0_0_0", prof.sm_reg.pre(0, 0, 0, 296, 8, 4))
    row("nv_prof_smreg_pre_1_2_1", prof.sm_reg.pre(1, 2, 1, 296, 8, 4))
    row("nv_prof_smreg_pre_0_0_1", prof.sm_reg.pre(0, 0, 1, 296, 8, 4))
    row("nv_prof_sm_base_0", P.prof.sm_base(0))
    row("nv_prof_sm_base_1", P.prof.sm_base(1))
    # :665 the LITTER fallback and WHICH of the five requests takes it.
    row("nv_query_reqs_n", QUERY_REQS_N())
    row("nv_query_litter_n", query_litter_n())
    brow("nv_query_litter_0", P.query_litter(0))
    brow("nv_query_litter_1", P.query_litter(1))
    brow("nv_query_litter_2", P.query_litter(2))
    brow("nv_query_litter_3", P.query_litter(3))
    brow("nv_query_litter_4", P.query_litter(4))
    srow("nv_query_name_0", P.query_name(0))
    srow("nv_query_name_1", P.query_name(1))
    srow("nv_query_name_2", P.query_name(2))
    srow("nv_query_name_3", P.query_name(3))
    srow("nv_query_name_4", P.query_name(4))
    # THE RESOLVED INDEX VALUES: 20, 23, 32 are LITTER and 13, 12 are plain, and
    # the ORDER is the order of the five requests at :597-598.
    row("nv_query_ix_0", P.query_ix(0))
    row("nv_query_ix_1", P.query_ix(1))
    row("nv_query_ix_2", P.query_ix(2))
    row("nv_query_ix_3", P.query_ix(3))
    row("nv_query_ix_4", P.query_ix(4))
# --- 21: the two NAME tables, :337 and :560 ------------------------------
# `GPFifo`'s field order IS its constructor order and `ifaces` is a FIRST-WINS
# ladder, so both are name lists rather than counts -- a count of seven and a
# count of three would pass with every name wrong.
#
# `nv_iface_count` AND `nv_encode_names` ARE NOT PRINTED HERE. `t_iface()`
# ALREADY prints both, AND this function used to print them a second time
# UNDER the same names. MEASURED: 11 row names in this file were emitted TWICE,
# and a NAME emitted twice is a row that cannot be addressed -- the reader
# sees two values under one name and cannot tell which site produced which, so
# a wrong one is not a wrong value but an unnameable one. The names are
# different questions: `t_iface` asks WHICH interfaces and WHICH encode rules
# exist, and it answers with the COUNT and the LIST; this function asks about
# the OTHER two name tables, `GPFifo`'s field order and the interface ladder's
# names, which are questions `t_iface` does not ask.
def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)
# a 64-bit ADDRESS FIXTURE, and it is the same one the oracle uses, because
# `nvm`'s word count depends on the arg DTYPE and not on the value -- so the
# VALUE only has to be one the gate and the oracle agree on.
# --- 9: the kernel argument trace, hcq2.py:74-76 --------------------------
def args.buf3_var2() -> List<&2, U32>: [P.W64(), P.W64(), P.W64(), P.W32(), P.W32()]
# the mixed fixture, which is the only one that can see the walrus.
# :337 `GPFifo`, and Python's field order IS the constructor order -- seven
# fields, and `notifier` is the FIFTH.
def args.mixed() -> List<&2, U32>: [P.W8(), P.W32(), P.W16(), P.W64(), P.W32(), P.W8()]
# ===========================================================================
# THE GATE, STAGES 1 AND 2. Every row is a claim about `ops_nv.py`'s TEXT, and
# every expectation was GENERATED BY CALLING CPython -- see
# `.agents/slop/nv-oracle.py`, which imports `ops_nv.py` with no GPU and no
# /dev/nvidiactl because none of these defs touches a live device.
#
# Numeric rows print the value so a wrong one is diagnosable from the output
# alone; string rows print the string so a wrong one is too. Nothing here is a
# boolean ABOUT a boolean.
# ===========================================================================
def t_args() -> IO(Unit):
  do IO<Unit>:
    lrow("nv_args_buf3", args.layout(args.buf3(), 0))
    lrow("nv_args_buf0", args.layout(Nil{}, 0))
    lrow("nv_args_buf1", args.layout([P.W64()], 0))
    lrow("nv_args_five_u32", args.layout([P.W32(), P.W32(), P.W32(), P.W32(), P.W32()], 0))
    # THE MIXED FIXTURE, and it is the ONLY one that can see the walrus: the
    # uint16 at slot 8 ends at 10 and the ulong after it is padded to 16.
    lrow("nv_args_mixed", args.layout(args.mixed(), 0))
    # THE BASE OFFSET, and it is `self.qmd_sz` -- the driver params' size --
    # so `nv_args_at512` is a launch row and not an arbitrary shift.
    lrow("nv_args_at512", args.layout(args.buf3_var2(), 512))
    lrow("nv_args_at256", args.layout(args.buf3_var2(), 256))
    lrow("nv_args_at512_mixed", args.layout(args.mixed(), 512))
    row("nv_args_buf3_n", U32.from_nat(List.length(&2, U32, args.layout(args.buf3(), 0))))
    row("nv_args_buf0_n", U32.from_nat(List.length(&2, U32, args.layout(Nil{}, 0))))
    row("nv_args_mixed_n", U32.from_nat(List.length(&2, U32, args.layout(args.mixed(), 0))))
    # device.bend:871's `iter_sig` USED TO advance off the UNROUNDED offset and to
    # disagree with `hcq2.layout_args` on the mixed list; `7f170f644` fixed it to
    # `U32.add(round_up(off, k), k)` and the two implementations now AGREE. THE ROWS
    # ARE kept because the pair is the claim -- `nv_device_args_*` is
    # `device.bend`'s answer and `nv_cpython_args_device_*` is this file's own
    # `sig.slot`, and two independent implementations of the same walrus are worth
    # one row each. They were named `nv_REPORTED_*` while the bug was live and a
    # `nv_REPORTED_args_device_differs_on_mixed` row asserted the DIVERGENCE; that
    # row is now `nv_device_args_agree_on_mixed`, because the name has to survive
    # reading the value.
    lrow("nv_device_args_mixed", D.iter_sig(args.mixed()))
    lrow("nv_device_args_buf3", D.iter_sig(args.buf3()))
    lrow("nv_device_args_five", D.iter_sig([P.W32(), P.W32(), P.W32(), P.W32(), P.W32()]))
    lrow("nv_cpython_args_device_mixed", args.layout(args.mixed(), 0))
    lrow("nv_cpython_args_device_buf3", args.layout(args.buf3(), 0))
    lrow("nv_cpython_args_device_five", args.layout([P.W32(), P.W32(), P.W32(), P.W32(), P.W32()], 0))
    brow("nv_device_args_same_on_bufs",
      u32_list_eq(args.layout(args.buf3(), 0), D.iter_sig(args.buf3())))
    brow("nv_device_args_agree_on_mixed",
      u32_list_eq(args.layout(args.mixed(), 0), D.iter_sig(args.mixed())))
    # THE ALIGNMENT IS THE CLAIM. `round_up(off, k)` at every step, so the
    # offset of the ulong in the mixed list is 16 and not 10.
    row("nv_args_mixed_ulong_slot", wnth(args.layout(args.mixed(), 0), 3n, 0))
    row("nv_args_mixed_uint16_slot", wnth(args.layout(args.mixed(), 0), 2n, 0))
# --- 10: the matcher pins itself ------------------------------------------
def dev.count(iface: U32, gpus: U32) -> U32:
  Bool.pick(U32, U32.is_eq(iface, P.IFACE_MOCK()), 1, gpus)
# `device.py:473` -- "never fallback to mock ifaces". A MOCK INTERFACE
# SURVIVES only when the target is a mock, AND `device.bend`'s `iface_ok` IS
# THE same rule. THE port spells it here as a function of the interface tag
# SO that the gate can ask it directly, AND the rows below are that function'S
# FOUR CELLS.
# THE FOUR NAMES `_new_gpu_fifo`'s pm_bufferize table uses, in the source's order,
# and the FIFTH is `notifier`, which is NOT in the table -- so a buffer named
# `notifier` is NOT bufferized and is allocated from `self.iface.alloc` instead.
def t_matcher() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.nvm.emit(0, P.M_SEM_ADDR_LO(), 3, P.NVM_TYP2(), [1, 2, 3], P.Tr.of()))
    brow("nv_has_forward", seq(t, [P.Call{P.CALL_WORD, 537067543},
      P.Call{P.CALL_WORD, 1}, P.Call{P.CALL_WORD, 2}, P.Call{P.CALL_WORD, 3}]))
    brow("nv_has_rejects_reverse", Bool.not(seq(t, [P.Call{P.CALL_WORD, 3},
      P.Call{P.CALL_WORD, 2}, P.Call{P.CALL_WORD, 1}])))
    brow("nv_has_rejects_absent", Bool.not(seq(t, [P.Call{P.CALL_WORD, 99}])))
    brow("nv_has_subsequence", seq(t, [P.Call{P.CALL_WORD, 1}, P.Call{P.CALL_WORD, 3}]))
    row("nv_trace_n", P.seen(t))
    row("nv_trace_words", U32.from_nat(List.length(&2, U32, wstream(t))))
# ===========================================================================
# STAGE 3 -- THE program cache, THE image, AND the launch path.
#
# ===========================================================================
# :43-45 `nv_iowr`, THE COMMAND ENCODER.
#
#   `cmd or ((3 << 30) | (ctypes.sizeof(args) & 0x1FFF) << 16 |
#            (ord('F') & 0xFF) << 8 | (nr & 0xFF))`
#
# FOUR FIELDS, and the two masks are load-bearing: `sizeof(args) & 0x1FFF`
# TRUNCATES an 8 KiB struct to 0, and `nv_iowr(fd, nr, args, cmd=...)` passes an
# explicit `cmd` for the UVM calls so the encoding does not happen at all. Both
# are rows, and `nv_iowr_8192_1` is the truncation.
# ===========================================================================
def M_AMP() -> U32: 1386
def dev.gpfifo_fields() -> List<&2, String>:
  ["ring", "gpput", "doorbell", "put_value", "notifier", "entries", "token"]
def dev.iface_names() -> List<&2, String>: ["NVKIface", "PCIIface", "MOCKIface"]
# :562-567, the four `Ops.CUSTOM_FUNCTION` argument strings, in order. These
# are matched with `arg="submit_nv_compute"` etc., so they are exact.
# `round_up(h, 64) * (608 + 4864 + 152 + 2000)` -- the four numbers are the
# decoder's per-row buffers and their SUM is one constant here because they are
# adjacent in the source with no arithmetic between them.
def pfault.n() -> U32: 16
def FAULT_PRIV() -> String: "NV_PFAULT_FAULT_TYPE_PRIV_VIOLATION"
# :156-159 `NVComputeQueue.memory_barrier` -- `self.prev_qmd = None` FIRST, then
# the invalidate. The None matters: it forces the NEXT launch to open its own
# PCAS pair instead of chaining onto the previous QMD, which is the whole point
# of a barrier and the reason `cq.exec` reads `Dev.nqmd`.
def t_err() -> IO(Unit):
  do IO<Unit>:
    srow("nv_errstr_0", P.iface.err_str_of(0, "NV_OK"))
    srow("nv_errstr_2", P.iface.err_str_of(2, "NV_ERR_BUFFER_TOO_SMALL"))
    srow("nv_errstr_8", P.iface.err_str_of(8, "NV_ERR_DMA_MEM_NOT_LOCKED"))
    # THE `get` DEFAULT: an unknown status is "Unknown error" and NOT a KeyError,
    # and the number is printed too.
    srow("nv_errstr_999", iface.err_msg(999))
    srow("nv_errstr_4096", iface.err_msg(4096))
    srow("nv_err_unknown", P.iface.unknown())
    row("nv_pfault_n", pfault.n())
    row("nv_paccess_n", paccess.n())
    row("nv_status_n", pfault.status_n())
    # THE two tables differ in shape: the fault table maps to the FULL c name and
    # the access table to a BARE word, because :38 splits on "_" and :37 does not.
    srow("nv_pfault_0", FAULT_PDE())
    srow("nv_pfault_5", FAULT_PRIV())
    srow("nv_paccess_0", paccess.of(0))
    srow("nv_paccess_1", paccess.of(1))
    srow("nv_paccess_2", paccess.of(2))
    srow("nv_paccess_3", paccess.of(3))
    srow("nv_paccess_4", paccess.of(4))
    srow("nv_paccess_8", paccess.of(8))
    srow("nv_paccess_9", paccess.of(9))
    srow("nv_paccess_10", paccess.of(10))
    # :35's `get_error_str` prefixes the STATUS NUMBER, so the two halves are
    # joined and the row is the whole string.
    srow("nv_err_full_8", P.iface.err_str_of(8, "NV_ERR_DMA_MEM_NOT_LOCKED"))
# --- 20: `to_name`, the tags and the profiler, hcq2.py:63 and :793-824 ----
def CLASS_VIDDEC() -> U32: 5
# :541-542 PCIIface reads all three off the GSP, so it takes them verbatim
# rather than walking the ladder.
# --- 21: the two NAME tables, :337 and :560 ------------------------------
# `GPFifo`'s field order IS its constructor order and `ifaces` is a FIRST-WINS
# ladder, so both are name lists rather than counts -- a count of seven and a
# count of three would pass with every name wrong.
#
# `nv_iface_count` AND `nv_encode_names` ARE NOT PRINTED HERE. `t_iface()`
# ALREADY prints both, AND this function used to print them a second time
# UNDER the same names. MEASURED: 11 row names in this file were emitted TWICE,
# and a NAME emitted twice is a row that cannot be addressed -- the reader
# sees two values under one name and cannot tell which site produced which, so
# a wrong one is not a wrong value but an unnameable one. The names are
# different questions: `t_iface` asks WHICH interfaces and WHICH encode rules
# exist, and it answers with the COUNT and the LIST; this function asks about
# the OTHER two name tables, `GPFifo`'s field order and the interface ladder's
# names, which are questions `t_iface` does not ask.
def dev.gpfifo_n() -> U32: 7
# ===========================================================================
# :688-694 `_ensure_has_local_memory`, AND its early return is the negative case
# FOR THE WHOLE POOL. `if self.slm_per_thread >= required: return` reallocates
# NOTHING, submits NOTHING and leaves `slm_per_thread` alone -- so a program
# asking for LESS local memory than the device already has must not move the
# window, and `nv_slm_early_1_have32` is the row that says so. It is the same
# shape as the program cache's "an entry that must NOT be evicted": a pool that
# reallocated on every ask would re-map the local memory window under a running
# kernel.
# ===========================================================================
def t_names() -> IO(Unit):
  do IO<Unit>:
    slrow("nv_iface_names", dev.iface_names())
    slrow("nv_gpfifo_fields", dev.gpfifo_fields())
    row("nv_gpfifo_n", dev.gpfifo_n())
def rl_isize(r: P.Rf, n: Nat) -> U32: P.Rl.isize(P.rl_at(P.Rf.rs(r), n))
# the top is base + size and the comment says 48 bits, so this row is the check
# that base+size == 2^48-1 on Linux and 2^49-1 on OSX.
def rl_off(r: P.Rf, n: Nat) -> U32: P.Rl.off(P.rl_at(P.Rf.rs(r), n))
def t_reloc() -> IO(Unit):
  do IO<Unit>:
    # THE REVERSE DIRECTION FIRST: which arm claims a type, and the COUNT of
    # claims so a table that dropped an arm is caught by a number and not only
    # by the forward rows.
    row("nv_reloc_kind_2", P.pd.reloc_kind(2))
    row("nv_reloc_kind_56", P.pd.reloc_kind(56))
    row("nv_reloc_kind_57", P.pd.reloc_kind(57))
    row("nv_reloc_kind_0", P.pd.reloc_kind(0))
    row("nv_reloc_kind_1", P.pd.reloc_kind(1))
    row("nv_reloc_kind_3", P.pd.reloc_kind(3))
    row("nv_reloc_kind_58", P.pd.reloc_kind(58))
    row("nv_reloc_kind_100", P.pd.reloc_kind(100))
    row("nv_reloc_kind_255", P.pd.reloc_kind(255))
    row("nv_reloc_kind_65535", P.pd.reloc_kind(65535))
    row("nv_reloc_kind_n", pd.reloc_kind_n())
    lrow("nv_reloc_arms", pd.reloc_arms())
    # THE FORWARD DIRECTION: the offsets differ by FOUR for both 32-bit arms.
    row("nv_reloc_off_2", P.pd.reloc.off(100, P.RELOC_64()))
    row("nv_reloc_off_56", P.pd.reloc.off(100, P.RELOC_32()))
    row("nv_reloc_off_57", P.pd.reloc.off(100, P.RELOC_32_HI()))
    row("nv_reloc_isize_2", P.pd.reloc.isize(P.RELOC_64()))
    row("nv_reloc_isize_56", P.pd.reloc.isize(P.RELOC_32()))
    row("nv_reloc_shift_2", P.pd.reloc.shift(P.RELOC_64()))
    row("nv_reloc_shift_56", P.pd.reloc.shift(P.RELOC_32()))
    row("nv_reloc_shift_57", P.pd.reloc.shift(P.RELOC_32_HI()))
    row("nv_reloc_isize_57", P.pd.reloc.isize(P.RELOC_32_HI()))
    # THE MESSAGE, and the number in it is the TYPE.
    srow("nv_reloc_msg_2", pd.reloc_msg(2))
    srow("nv_reloc_msg_0", pd.reloc_msg(0))
    srow("nv_reloc_msg_3", pd.reloc_msg(3))
    srow("nv_reloc_msg_100", pd.reloc_msg(100))
    # THE FOLD, and the refusal LIVES IN IT: an unknown type contributes nothing
    # and neither does anything AFTER it, which is the port's "the raise happens
    # HERE and not later".
    +a : P.Rf <- IO.pure(P.Rf, pd.relocs(relocs0()))
    row("nv_reloc_ok_n", U32.from_nat(List.length(&2, P.Rl, P.Rf.rs(a))))
    brow("nv_reloc_ok_refused", Rf.refused(a))
    row("nv_reloc_ok_off0", rl_off(a, 0n))
    row("nv_reloc_ok_off1", rl_off(a, 1n))
    row("nv_reloc_ok_isize1", rl_isize(a, 1n))
    row("nv_reloc_ok_shift1", rl_shift(a, 1n))
    +b : P.Rf <- IO.pure(P.Rf, pd.relocs(relocs_bad()))
    row("nv_reloc_bad_n", U32.from_nat(List.length(&2, P.Rl, P.Rf.rs(b))))
    brow("nv_reloc_bad_refused", Rf.refused(b))
    +c : P.Rf <- IO.pure(P.Rf, pd.relocs(Nil{}))
    row("nv_reloc_empty_n", U32.from_nat(List.length(&2, P.Rl, P.Rf.rs(c))))
    brow("nv_reloc_empty_refused", Rf.refused(c))
# --- 15: the program cache, :313-320. THE key and the absent eviction -------
def MOCK_DRV_MAJOR() -> U32: 570
# THE two views share one arena, so they are SLOTS: slot 0 is the 3 MiB
# `gpfifo_buf` root, slot 1 is the ring view and slot 2 is the gpput view. MEASURED:
# reading slot 0 answers the ROOT's 4 bytes and `nv_ring_nbytes` printed 4 instead
# of 524288 -- so the readers below name the INDEX, and a reader that hardcoded
# 0 reads the root and passes every root-shaped row.
def MOCK_PCI_DEVICE_ID() -> U32: 9860
# THE MOCK'S CLASS LIST. `nvdriver.py:160-162` ANSWERS
# `NV0080_CTRL_CMD_GPU_GET_CLASSLIST` WITH A LITERAL LIST OF CLASS IDS "from
# ada102". THE port does not carry the list -- IT is a list of numbers and the
# PORT'S class ladder is a different thing (`:403-415`'s PAIRS). WHAT the port
# CARRIES is the count, WHICH is what `setup_usermode`'s CLASSLIST rm_control
# RETURNS and what the class ladder walks.
#
# THE count is fifty-TWO, AND it was fifty-FIVE in the first draft of this
# COMMENT. MEASURED, BY reading the list out of the driver'S own source
# (NOT BY COUNTING A TRANSCRIPTION OF IT):
#
#     src = open('test/mockgpu/nv/nvdriver.py').read()
#     i = src.index('classes = [');  j = src.index(']', i)
#     len(ast.literal_eval(src[i+9:j+1]))   ->  52
#
# AND the port'S row answered 55, WHICH was a hand-TYPED count of a hand-TYPED
# LIST. THIS is the class the tree already names: the `renderer/cstyle.bend`
# unit shipped 215 hand-typed expectations of which SEVENTEEN were wrong. A
# COUNT typed by a human is a count of a transcription, NOT of the thing.
def dev.mock_init_call_count() -> U32:
  U32.add(U32.add(P.Tr.count(P.CALL_ALLOC(), P.Tr.calls(P.Dev.tr(P.dev.mock_init(0)))),
                  P.Tr.count(P.CALL_CONTROL(), P.Tr.calls(P.Dev.tr(P.dev.mock_init(0))))),
          P.Tr.count(P.CALL_UVM(), P.Tr.calls(P.Dev.tr(P.dev.mock_init(0)))))
# ===========================================================================
# STAGE 2 -- THE queue and command-SUBMISSION structure.
#
# Everything in this section is a PURE function of small integers, and it is
# the portable heart of the file: `nvm` builds a push-buffer command header,
# `nv_flags` builds a flag word, and the queues are the fixed sequences of
# commands they emit. `NVQueue.q` (`hcq2.py:366`) then concatenates the ints
# and `array.array('I', cmds).tobytes()` uploads them -- and the concatenation
# is the trace.
#
# ===========================================================================
# :47-48 `nvm`,
#   `[(typ << 28) | (nvals << 16) | (subc << 13) | (mthd >> 2), *vals]`
#
# FOUR FIELDS IN ONE WORD, and they do not overlap: bits 28-29 are `typ`, 16-19
# the argument count, 13-15 the subcommand and 0-11 the method shifted right by
# two. The `>> 2` is because the method is stored with its low two bits clear.
#
# `nvals` is `sum(v.dtype.itemsize // 4 if isinstance(v, UOp) else 1 for v in
# vals)`, so a uint64 argument COUNTS TWO and a uint32 ONE. That is the whole
# of `vals`' contribution and it is why `nvm.nvals64` exists below: a kernel
# argument trace and a command header agree on the word count.
# ===========================================================================
def IFACE_PCI() -> U32: 2
def t_mock() -> IO(Unit):
  do IO<Unit>:
    # THE three interface names, ONE row each, BOTH directions. A name that is
    # NOT in the list is not a queue, AND a name in the list that is not
    # SPELLED the way upstream spells it selects nothing.
    srow("nv_mock_iface_nvk", iface_name(P.IFACE_NVK()))
    srow("nv_mock_iface_pci", iface_name(IFACE_PCI()))
    srow("nv_mock_iface_mock", iface_name(P.IFACE_MOCK()))
    srow("nv_mock_iface_none", iface_name(0))
    srow("nv_mock_iface_four", iface_name(4))
    # THE count. `MOCKIface.count = 1` IS the whole difference from
    # `NVKIface`, AND `NVKIface.count` IS the card'S own gpu count. SO the
    # COUNT is a function of the interface and the mock'S answer is one while
    # THE REAL ONE'S IS THE CARD'S.
    row("nv_mock_count_mock", dev.count(P.IFACE_MOCK(), MOCK_GPUS()))
    row("nv_mock_count_nvk", dev.count(P.IFACE_NVK(), MOCK_GPUS()))
    row("nv_mock_count_pci", dev.count(IFACE_PCI(), MOCK_GPUS()))
    # THE SELECTION. `device.py:473` -- "never fallback to mock ifaces". A MOCK
    # INTERFACE survives only when the target is a mock. THE two cells are the
    # CLAIM and its negative, AND they are separate rows because a reader
    # THAT always kept or always dropped would satisfy one of them.
    row("nv_mock_filtered_real", P.dev.iface_filtered_n(False{}))
    row("nv_mock_filtered_mock", P.dev.iface_filtered_n(True{}))
    # THE per-INTERFACE cells of the rule.
    brow("nv_mock_ok_mock_real", P.dev.iface_ok(P.IFACE_MOCK(), False{}))
    brow("nv_mock_ok_nvk_real", P.dev.iface_ok(P.IFACE_NVK(), False{}))
    brow("nv_mock_ok_mock_mock", P.dev.iface_ok(P.IFACE_MOCK(), True{}))
    brow("nv_mock_ok_nvk_mock", P.dev.iface_ok(P.IFACE_NVK(), True{}))
    # THE driver version. THE mock answers `b"570.00.00\0"`
    # (`test/mockgpu/nv/nvdriver.py:208`) AND `NVKIface.__init__` PICKS THE
    # CONSTANT table from the major version, SO 570 SELECTS `nv_570` -- WHICH
    # IS the table the port'S constants are read from. THE LOOP IS closed.
    row("nv_mock_drv_major", MOCK_DRV_MAJOR())
    row("nv_mock_drv_table", drv_table_of(MOCK_DRV_MAJOR()))
    srow("nv_mock_drv_table_name", drv_table_name(drv_table_of(MOCK_DRV_MAJOR())))
    # THE thresholds, IN both directions, BECAUSE a table that picks the wrong
    # ONE for a driver between 610 AND 615 IS a wrong constant set and no
    # OTHER ROW SEES IT.
    row("nv_mock_drv_615", drv_table_of(615))
    row("nv_mock_drv_614", drv_table_of(614))
    row("nv_mock_drv_610", drv_table_of(610))
    row("nv_mock_drv_609", drv_table_of(609))
    row("nv_mock_drv_580", drv_table_of(580))
    row("nv_mock_drv_579", drv_table_of(579))
    row("nv_mock_drv_570", drv_table_of(570))
    row("nv_mock_drv_569", drv_table_of(569))
    # THE mock'S gpu count and its pci device ID. THE mock driver creates six
    # GPUS (`NVDriver(gpus=6)`) AND ANSWERS `NV_ESC_CARD_INFO` WITH
    # `st.pci_info.device_id = 0x2684` FOR EACH.
    row("nv_mock_gpus", MOCK_GPUS())
    row("nv_mock_pci_device_id", MOCK_PCI_DEVICE_ID())
    # THE mock'S class list length. `nvdriver.py:160-162` ANSWERS the
    # CLASSLIST rm_control WITH FIFTY-FIVE IDS "from ada102".
    row("nv_mock_classlist_n", MOCK_CLASSLIST_N())
    # THE mock is a driver substitution and not a different code path: ITS
    # TRACE is the real one'S trace. `Tr.has` IS a subsequence match, SO this
    # ROW is TRUE WHENEVER the mock'S calls appear in the real one'S order.
    brow("nv_mock_same_shape", dev.mock_same_shape())
    # AND the mock'S trace is not empty, WHICH is the other half of the claim:
    # A subsequence match against an empty trace is TRUE AND proves nothing.
    row("nv_mock_init_calls", dev.mock_init_call_count())
# --- 4: the class ladders, :404-412 ----------------------------------------
# THE THREE FIXTURE MASKS, generated by the oracle's `mask()` over the class
# sets below and not transcribed. `AMP` is a Blackwell-GPU-that-is-not-quite: it
# has ADA but not BLACKWELL, which is the only fixture that can tell a
# three-entry ladder from a two-entry one.
#   AMP = {TURING, AMPERE_GPFIFO, AMPERE_COMPUTE_B, ADA_COMPUTE_A,
#          AMPERE_DMA_COPY_B, NVC9B0}
#   OLD = {TURING, AMPERE_COMPUTE_B, AMPERE_DMA_COPY_B, NVC9B0}
#   NEW = AMP + {HOPPER, BLACKWELL_GPFIFO, BLACKWELL_COMPUTE_B, NVCFB0}
# THE same two words as one printable `hi:lo` STRING, because `dev.slm` answers a
# `U32` and the claim that a 64-bit total needs no third word is only visible if
# the pair is printed. `U32.shrn(x, 32)` SATURATES at 0 (bend2-constraints.md:
# a shift past the width is 0, not a mod-2^32 rotation), so every real local
# memory total answers `0:<total>` -- which is the claim these six rows make.
def iface.pc_ok(+m: U32) -> Bool:
  Bool.and(P.iface.has(P.Hav{m}, P.CLASS_AMPERE_COMPUTE_B()),
    P.iface.has(P.Hav{m}, P.CLASS_AMPERE_DMA_COPY_B()))
# --- 12: the QMD field layer, :50-94 ---------------------------------------
def qmd.fields_v5() -> U32: 296
# :94 `return ("grid_width", "grid_height", "grid_depth") if self.ver >= 4 else
# ("cta_raster_width", "cta_raster_height", "cta_raster_depth")`. The NAMES, and
# a port that kept the ver-3 names would write three fields that do not exist in
# a ver-5 QMD.
# THE arms were backwards in the first version. Python :94 is
# `("grid_width", "grid_height", "grid_depth") if self.ver >= 4 else
#  ("cta_raster_width", "cta_raster_height", "cta_raster_depth")`, so ver 5 is
# the grid_* arm and ver 3 the cta_raster_* one -- MEASURED: `nv_qmd_grid3` printed
# grid_width where CPython prints cta_raster_width, and the two rows SWAPPED.
def qmd.prog_sfx(v: U32) -> String:
  Bool.pick(String, U32.is_ge(v, 4), "_shifted4", "")
# :537 PCIIface's two FIXED handles. Not rm_alloc'd at all, which is why they
# are constants and why `rm_alloc` there is a GSP RPC and not an ioctl.
def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.and(busy0, busy1))
# `release_structure_size_{i}` is 0 for a TIMESTAMP and 2 otherwise -- the
# reverse of what the name suggests, and it is the only difference between
# `signal` and `timestamp` inside the QMD.
def t_qmd() -> IO(Unit):
  do IO<Unit>:
    row("nv_qmd_ver_ampere", P.qmd.ver.of(P.CLASS_AMPERE_COMPUTE_B()))
    row("nv_qmd_ver_ada", P.qmd.ver.of(P.CLASS_ADA_COMPUTE_A()))
    # 52672 is WRITTEN OUT, not `CLASS_BLACKWELL_COMPUTE_A()`. The constant is
    # the ver-5 THRESHOLD and this row is its INPUT, so feeding the constant in
    # makes the row tautological: both sides move together and it answers 5 for
    # every value the constant can hold. MEASURED -- with the constant fed in,
    # mutating it moved ZERO rows. The literal is what makes it a test.
    row("nv_qmd_ver_bwa", P.qmd.ver.of(52672))
    row("nv_qmd_ver_bwb", P.qmd.ver.of(P.CLASS_BLACKWELL_COMPUTE_B()))
    row("nv_qmd_sz3", P.qmd.sz.of(P.QMD_VER3()))
    row("nv_qmd_sz5", P.qmd.sz.of(P.QMD_VER5()))
    row("nv_qmd_words3", P.qmd.words(P.QMD_VER3()))
    row("nv_qmd_words5", P.qmd.words(P.QMD_VER5()))
    # THE TABLE SIZES, which are what makes `qmd.words` exact rather than
    # approximate. The first version wrote this claim in a COMMENT and defined the
    # two functions, but printed no row -- so `nv_qmd_fields_v3` was a row the
    # file talked about and did not have, and CPython's answer for it went
    # unmatched in the differ.
    row("nv_qmd_fields_v3", qmd.fields_v3())
    row("nv_qmd_fields_v5", qmd.fields_v5())
    # THE GRID NAMES, and a port that kept the ver-3 names would write three
    # fields that do not exist in a ver-5 QMD. Both lists, both directions.
    slrow("nv_qmd_grid3", P.qmd.grid(P.QMD_VER3()))
    slrow("nv_qmd_grid5", P.qmd.grid(P.QMD_VER5()))
    # THE ADDRESS SHIFTS, which the FIELD NAME also encodes.
    row("nv_qmd_prog_shift3", qmd.prog_shift(P.QMD_VER3()))
    row("nv_qmd_prog_shift5", qmd.prog_shift(P.QMD_VER5()))
    row("nv_qmd_cbuf_shift3", qmd.cbuf_shift(P.QMD_VER3()))
    row("nv_qmd_cbuf_shift5", qmd.cbuf_shift(P.QMD_VER5()))
    srow("nv_qmd_prog_sfx3", qmd.prog_sfx(P.QMD_VER3()))
    srow("nv_qmd_prog_sfx5", qmd.prog_sfx(P.QMD_VER5()))
    srow("nv_qmd_cbuf_sfx3_0", qmd.cbuf_sfx(P.QMD_VER3(), "0"))
    srow("nv_qmd_cbuf_sfx3_3", qmd.cbuf_sfx(P.QMD_VER3(), "3"))
    srow("nv_qmd_cbuf_sfx5_0", qmd.cbuf_sfx(P.QMD_VER5(), "0"))
    srow("nv_qmd_cbuf_sfx5_7", qmd.cbuf_sfx(P.QMD_VER5(), "7"))
    # `set_release`'s SLOT, and the refusal: both slots busy answers 3.
    row("nv_qmd_slot_free", P.qmd.slot(False{}, False{}))
    row("nv_qmd_slot_0", P.qmd.slot(True{}, False{}))
    row("nv_qmd_slot_1", P.qmd.slot(False{}, True{}))
    row("nv_qmd_slot_both", P.qmd.slot(True{}, True{}))
    brow("nv_qmd_release_ok_free", qmd.slot.ok(False{}, False{}))
    brow("nv_qmd_release_ok_one", qmd.slot.ok(True{}, False{}))
    brow("nv_qmd_release_refuses", Bool.not(qmd.slot.ok(True{}, True{})))
    # `release_structure_size_{i}` is 0 for a TIMESTAMP and 2 otherwise -- the
    # reverse of what the name suggests.
    row("nv_qmd_rel_size_signal", qmd.rel_size(False{}))
    row("nv_qmd_rel_size_timestamp", qmd.rel_size(True{}))
    brow("nv_qmd_payload64b_3", qmd.payload64b(P.QMD_VER3()))
    brow("nv_qmd_payload64b_5", qmd.payload64b(P.QMD_VER5()))
# --- 13: `NVProgramData`, :230-305 ------------------------------------------
# The fixture is a 3-buffer / 2-var program with 64 registers, 0x400 shared
# memory and the 0x160 cbuf0 size a real cuda program reports.
def Dev.slm(d: P.Dev) -> U32:
  match d:
    case P.Dev{sm, compute, gpfifo, dma, viddec, usermode, iface, slm, pma, next_qmd, t}: slm
# :609 `super().__init__(device, NVAllocator(self), [CUDARenderer, PTXRenderer,
# NVCCRenderer, NAKRenderer], None, arch=self.arch)` -- FOUR renderers and a
# NULL runtime, because the NV path goes through the hcq2 queues and not through
# a `Program.__call__`. That is the single most important fact about this
# backend and it is two constants.
def CLASS_COMPUTE() -> U32: 3
def CLASS_GPFIFO() -> U32: 2
# `is_bw = self.iface.compute_class >= nv_gpu.BLACKWELL_COMPUTE_A` -- THE SAME
# PREDICATE as the QMD version and the min cbuf_0 entries, so
# `nv_prof_shares_predicate` pins that they are one predicate and not three copies
# of it.
def t_class() -> IO(Unit):
  do IO<Unit>:
    lrow("nv_ladder_user", P.iface.ladder(CLASS_USERMODE()))
    lrow("nv_ladder_gpfifo", P.iface.ladder(CLASS_GPFIFO()))
    lrow("nv_ladder_comp", P.iface.ladder(CLASS_COMPUTE()))
    lrow("nv_ladder_dma", P.iface.ladder(CLASS_DMA()))
    lrow("nv_ladder_vid", P.iface.ladder(CLASS_VIDDEC()))
    row("nv_mask_amp", M_AMP())
    row("nv_mask_old", M_OLD())
    row("nv_mask_new", M_NEW())
    # THE ELEVEN CLASS-ID -> BIT ASSIGNMENTS, one row each. `iface.has` reads a
    # mask through this table, so a wrong assignment makes a whole ladder answer
    # 0 and every `nv_pick_*` row with it -- and a table row that only printed
    # "the mask is well-formed" would have shown nothing.
    row("nv_bit_turing", P.iface.bit(P.CLASS_TURING_USERMODE()))
    row("nv_bit_hopper", P.iface.bit(P.CLASS_HOPPER_USERMODE()))
    row("nv_bit_ampgpfifo", P.iface.bit(P.CLASS_AMPERE_GPFIFO()))
    row("nv_bit_bwgpfifo", P.iface.bit(P.CLASS_BLACKWELL_GPFIFO()))
    row("nv_bit_ampcomp", P.iface.bit(P.CLASS_AMPERE_COMPUTE_B()))
    row("nv_bit_ada", P.iface.bit(P.CLASS_ADA_COMPUTE_A()))
    row("nv_bit_bwcomp", P.iface.bit(P.CLASS_BLACKWELL_COMPUTE_B()))
    row("nv_bit_ampdma", P.iface.bit(P.CLASS_AMPERE_DMA_COPY_B()))
    row("nv_bit_bwdma", P.iface.bit(P.CLASS_BLACKWELL_DMA_COPY_B()))
    row("nv_bit_nvc9b0", P.iface.bit(P.CLASS_NVC9B0_VIDEO_DECODER()))
    row("nv_bit_nvcfb0", P.iface.bit(P.CLASS_NVCFB0_VIDEO_DECODER()))
    brow("nv_has_ada", P.iface.has(P.Hav{M_AMP()}, P.CLASS_ADA_COMPUTE_A()))
    brow("nv_has_bwcomp", P.iface.has(P.Hav{M_AMP()}, P.CLASS_BLACKWELL_COMPUTE_B()))
    brow("nv_has_turing_new", P.iface.has(P.Hav{M_NEW()}, P.CLASS_TURING_USERMODE()))
    brow("nv_has_bwgpfifo_old", P.iface.has(P.Hav{M_OLD()}, P.CLASS_BLACKWELL_GPFIFO()))
    row("nv_pick_amp_user", P.iface.pick(CLASS_USERMODE(), M_AMP()))
    row("nv_pick_amp_gpfifo", P.iface.pick(CLASS_GPFIFO(), M_AMP()))
    row("nv_pick_amp_comp", P.iface.pick(CLASS_COMPUTE(), M_AMP()))
    row("nv_pick_amp_dma", P.iface.pick(CLASS_DMA(), M_AMP()))
    row("nv_pick_amp_vid", P.iface.pick(CLASS_VIDDEC(), M_AMP()))
    row("nv_pick_old_user", P.iface.pick(CLASS_USERMODE(), M_OLD()))
    row("nv_pick_old_gpfifo", P.iface.pick(CLASS_GPFIFO(), M_OLD()))
    row("nv_pick_old_comp", P.iface.pick(CLASS_COMPUTE(), M_OLD()))
    row("nv_pick_old_dma", P.iface.pick(CLASS_DMA(), M_OLD()))
    row("nv_pick_old_vid", P.iface.pick(CLASS_VIDDEC(), M_OLD()))
    row("nv_pick_new_user", P.iface.pick(CLASS_USERMODE(), M_NEW()))
    row("nv_pick_new_gpfifo", P.iface.pick(CLASS_GPFIFO(), M_NEW()))
    row("nv_pick_new_comp", P.iface.pick(CLASS_COMPUTE(), M_NEW()))
    row("nv_pick_new_dma", P.iface.pick(CLASS_DMA(), M_NEW()))
    row("nv_pick_new_vid", P.iface.pick(CLASS_VIDDEC(), M_NEW()))
    # THE negative case for the viddec ladder: no decoder means the answer is
    # `None`, which is 0 here, and 0 is NOT an error. Every other ladder's
    # empty answer is a `StopIteration` and is therefore never reached, which is
    # why only this one has a row for it.
    row("nv_pick_none_vid", P.iface.pick(CLASS_VIDDEC(), 0))
    # THE order of the pair is the policy, and these two rows are the ones a
    # last-wins port fails: the OLD fixture has AMPERE but not BLACKWELL, so
    # walking backwards finds nothing, and the NEW fixture has both.
    # THE order of the pair is the policy, and THESE two rows are why. `OLD`
    # holds AMPERE but not BLACKWELL, so walking either ladder BACKWARDS finds
    # nothing; `NEW` holds both, so a backwards walk answers the OLD class where
    # CPython answers the new one. `nv_pick_amp_*` alone could not see it.
    row("nv_pick_old_gpfifo_zero", P.iface.pick(CLASS_GPFIFO(), M_OLD()))
    brow("nv_pc_ok_amp", iface.pc_ok(M_AMP()))
    brow("nv_pc_ok_old", iface.pc_ok(M_OLD()))
# --- 5: the init order, :571-611 -------------------------------------------
# The fixture is a Hopper-shaped GPU: sm_version 2192 and the FULL class set,
# so every ladder picks a non-trivial winner. `peer=True` gives one other NV
# device, which is the one-uva-per-peer shape.
def Tr.refused(t: P.Tr) -> Bool:
  match t:
    case P.Tr{calls, next, bad_at, seen, refused}: refused
# the ordinal of the refusal that should fire, so a fixture can reach each
# raise site. 0 = never, which is every successful fixture.
# :159 `memory_barrier`.
def t_init() -> IO(Unit):
  do IO<Unit>:
    +d : P.Dev <- IO.pure(P.Dev, P.dev.init(SM_89(), 1, True{}, True{}))
    +t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(d))
    srow("nv_init_arch", Dev.arch(d))
    row("nv_init_sass", Dev.sass(d))
    # :574-578 the three device objects, in order, parent first. The handles are
    # minted by the trace so they are CONSECUTIVE and the row pins all three.
    lrow("nv_init_alloc_head", P.Tr.args(P.CALL_ALLOC(), P.Tr.calls(t)))
    row("nv_init_nalloc", ncalls(P.CALL_ALLOC(), t))
    row("nv_init_ncontrol", ncalls(P.CALL_CONTROL(), t))
    row("nv_init_nuvm", ncalls(P.CALL_UVM(), t))
    row("nv_init_nmmap", ncalls(P.CALL_MMAP(), t))
    row("nv_init_seen", P.seen(t))
    # :589 setup_vm's two registers THEN the peer access, and the peer access is
    # per peer, so it is LAST.
    lrow("nv_init_uvm", uvms(t))
    # :597-598 five queries and the count is load-bearing.
    row("nv_init_query_n", U32.sub(ncalls(P.CALL_CONTROL(), t), 1))
    brow("nv_init_refused", Tr.refused(t))
    row("nv_init_slm0", Dev.slm(d))
    brow("nv_init_pma", Dev.pma(d))
    # A REFUSAL MUST TRUNCATE. `bad_at` 6 is the fourth rm_alloc, so the vaspace
    # (:587) and everything after it records nothing.
    +r : P.Dev <- IO.pure(P.Dev, P.dev.init.at(SM_89(), 1, True{}, True{}, Tr.fail_at(P.Tr.of(), 6)))
    +rt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(r))
    row("nv_init_fail_nalloc", ncalls(P.CALL_ALLOC(), rt))
    row("nv_init_fail_seen", P.seen(rt))
    brow("nv_init_fail_flag", Tr.refused(rt))
    row("nv_init_ok_nalloc", ncalls(P.CALL_ALLOC(), t))
# --- 6: `nvm`, :47-48 ------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_arch()
    b : Unit <- t_va()
    c : Unit <- t_iface()
    c2 : Unit <- t_mock()
    d : Unit <- t_class()
    e : Unit <- t_init()
    f : Unit <- t_nvm()
    g : Unit <- t_flags()
    h : Unit <- t_queue()
    i : Unit <- t_args()
    j : Unit <- t_matcher()
    k : Unit <- t_iowr()
    l : Unit <- t_qmd()
    m : Unit <- t_pdata()
    n : Unit <- t_reloc()
    o : Unit <- t_cache()
    p : Unit <- t_launch()
    q : Unit <- t_pool()
    r : Unit <- t_vid()
    u : Unit <- t_err()
    v : Unit <- t_tags()
    w : Unit <- t_names()
    IO.print("nv-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every "rows moved" below is the HARNESS'S OUTPUT, not an
# estimate: `.agents/slop/nv-mutate.py` applies one edit to a scratch copy, runs
# the INTERPRETED lane, and diffs the row NAMES and VALUES against the clean run.
# The useful column is "rows moved", because a mutation that moves nothing
# measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `qmd.ver.of`: `>=` becomes `>` | 6 | :54 the ONE comparison that picks the QMD generation, and it reaches `nv_qmd_ver_bwa`, `nv_pd_ver_bw`, `nv_pd_min_cbuf0_bw`, `nv_pd_kernargs_bw`, `nv_pd_cbuf0_len_bw` and `nv_prof_shares_predicate` -- which is the ROW COUNT of "three places spell the same predicate". |
# | M2 | `pd.reloc.off`: drop the `+ 4` | 3 | :263 the two 32-bit arms land four bytes later. `nv_reloc_ok_off1` is the only forward row; the two per-arm rows make the shape readable. |
# | M3 | `nvm.word`: `typ << 28` becomes `<< 29` | 25 | :48 the command header's four fields. Almost every queue row moves, which is the point: the header is in EVERY word stream. |
# | M4 | `nvm.emit`: one word more for `NVQueue.sem` | 4 | :48 the UOp WEIGHTING -- a uint64 argument counts two words, so the header says 5. It moves `nv_sem_wait`, `nv_sem_signal`, `nv_sem_timestamp` and `nv_sig_value_kept`. |
# | M5 | `qmd.slot.ok`: `not (a and b)` becomes `not (a or b)` | 1 | :86 `set_release` refuses only when BOTH release slots are busy. One row, and it is the case that differs. |
# | M6 | `smemcfg.cand`: the candidates are walked largest-first | 2 | :293 the `min()` over {32768, 65536, 102400}. `nv_smemcfg_0` and `nv_smemcfg_1024` do NOT move, which is the trap: a `min` and a `max` agree on a zero shmem. |
# | M7 | `to_name.join.parts`: the separator is appended to the head too | 11 | hcq2.py:63 `String.split` DROPS the separator, so it has to be put back. This is a `device.bend` `rest_of` shape. |
# | M8 | `flags.term`: the shift is `lo - 1` | 21 | :40 `getattr(nv_gpu, f"{reg}_{k}")[1]` is the bitfield tuple's SECOND element, which is the SHIFT and not the low bit. |
# | M9 | `Tr.emit`: the append is built OUTSIDE the `Bool.pick` | 12 | the emit REPLACES the head instead of appending -- the `Bool.pick` selector trap. It reaches the semaphores, the copy command and the launch. |
# | M10 | `copy.nsteps`: `ceildiv` becomes "1 unless zero" | 5 | :191 `len(range(0, sz, 1 << 31))` is 0 for an empty copy and 2 at the top of the `U32` range; `nv_copy_nsteps_half` and the two top-of-range rows are what move. |
# | M11 | `cq.exec.at`: the chained arm drops the `Bool.pick` | 1 | :180 a CHAINED launch emits no words at all -- `nv_launch_chain_words` is 0 and every other launch row is untouched. |
# | M12 | `exec.ok.prod`: the disjunction loses one conjunct | 6 | :164 `prod > 1024 OR max_threads < prod`. The two conjuncts are separate rows (`nv_launch_ok_1024_512` and `nv_launch_ok_2048_8192`) BECAUSE a mutation that keeps one conjunct still moves the other's row. |
# | M13 | `pc.find`: the miss sentinel becomes `!=` instead of `<` | 0 | :315 A real blind spot. It moves nothing because `pc.find` answers `len` on a miss and an index below it on a hit, which makes `found < len` and `found != len` THE same predicate over every possible answer. A test that cannot fail is not a test. |
# | M14 | `arch_of`: `>> 4` becomes `>> 1` | 8 | :601 `val >> 4` where the test is `val > 0xf`. |
# | M15 | `sass_of`: `(sm & 0xf00) >> 4` becomes `(sm & 0xf)` | 7 | :602, and it is the only place in the file where the two masks are confused with each other. |
# | M16 | `iowr.cmd`: the size mask is dropped | 3 | :44 `ctypes.sizeof(args) & 0x1FFF` -- an 8 KiB struct encodes as if it were empty. |
# | M17 | `pd.min_cbuf0`: a `max` becomes a `min` | 7 | `device.bend:584`'s own rule, one layer down: `max(cbuf0 // 4, min_cbuf0)`. |
# | M18 | `reg_ops`: the chunk is 128 instead of 124 | 10 | :819 `range(0, len(ops), 124)` and the last chunk is short, so 125 ops are TWO ioctls. |
# | M19 | `dev.slm`: the early-return guard is dropped | 1 | :689 the NEGATIVE CASE for the whole pool. It moved NOTHING until `nv_slmp_33_have48` was added, because every other fixture had `have` already equal to `round_up(required, 32)`. |
# | M20 | `NV_PICK`: the ladders are walked oldest-first | 7 | :408-412 the ladders are NEWEST GENERATION FIRST, and `nv_ladder_*` print the whole chosen row. |
# | M21 | `sm_reg.pre`: `* 0x200` becomes `+ 0x200` | 3 | :805 `(ntpg - cnt + tpc) * 0x200` MULTIPLIES. |
# | M22 | THE CONTROL: a comment-only edit | 0 | a table with no row that CANNOT move is a table of coincidences. This is the row that says the other zeroes mean something. |
# | M23 | `to_name.join.go`: cons instead of append | REFUSED | not a number: the cons puts the shrinking list SECOND in the self-call and the decrease check fails. The ORDER claim is covered by M7 and by the nine `nv_toname_*` value rows. |
# | M24 | `pd.max_threads`: the register granularity is 128 | 2 | :305 `round_up(regs * 32, 256)`, and it only shows at `regs` 0 and 1 where the two roundings part company. |
# | M25 | `nvm.words`: the payload drops its tag | REFUSED | a TYPE change -- a bare `U32` where a `Call` belongs -- so it is refused rather than measured. |
# | M26 | `Tr.has.go`: the fuel is set to nothing | 2 | THE MATCHER WITH NO FUEL: it moves the two NEGATIVE rows and no positive one, which is `ops_webgpu.bend`'s real blind spot. |
# | M27 | `cq.stride`: the `qmd_sz` is dropped | 2 | :137 stride is `qmd_sz` PLUS the largest kernargs. `nv_launch_stride256` is the row that can tell the two apart; at 0 kernargs they agree. |
# | M28 | `pd.image_len`: the trailing 4 KiB is dropped | 6 | :277 the NOTE is 4 KiB of slack AFTER the page-aligned image. |
# | M29 | `query_litter.at`: the set becomes {1,2,3} | 4 | :665 THE LITTER SET IS {0,1,2}. This mutation is the SECOND wrong reading of that set -- the first said {1,3} -- and it is kept in the table so both readings stay on the record. Only `nv_570.__dict__` settles it. |
# | M30 | `dev.slm_bytes`: the 128 KiB rounding is dropped | 1 | :693 the ONLY 128 KiB rounding in the file. It moved NOTHING until `nv_slmtot_1_1_1` was added, because all six real fixtures are already exact multiples of 131072. |
# | M31 | `qmd.fields_v3`: 181 becomes 180 | 1 | :58-59 the count IS the reason a word list is exact. The count had a COMMENT naming a row the file did not have. |
# | M32 | `iowr.cmd.at`: the sentinel arm is swapped | 3 | :44 `cmd or (...)` -- a zero explicit word falls THROUGH to the derived one, and `cmd=0` is what every `uvm()` call passes. |
#
# THE BLIND SPOT (M13), because it is the honest half of the table.
# `pc.find`'s CONTRACT is "the index of the match, or the list length if there is
# none", and under that contract `found < len(keys)` and `found != len(keys)` are
# the same predicate. The mutation is therefore an EQUIVALENCE on this port and
# no arrangement of rows over `pc.put` can see it. What CAN be seen is the
# contract itself, so `nv_pc_grow_3` (three distinct keys grow the cache by
# three) and `nv_pc_grow_repeat` (a known key does not) are the rows that carry
# it, and M13's zero is the measurement that those two are the load-bearing pair
# and the comparison inside `pc.put.at` is not.
#
# WHAT this gate still does not see, and it is a short list:
#
#   1. THE C-DRIVER SURFACE. Every `fd.ioctl`, `mmap` and `NVOS*_PARAMETERS` is
#      a seam (the header's TODO list), so nothing checks that a handle is passed
#      to the right call -- `Tr.args(CALL_ALLOC(), t)` answers the handle SEQUENCE
#      and not the handle-to-call binding.
#   2. THE qmd bit field layout. The word model is EXACT (see the header's
#      measurement: no field in either generated table is wider than 32 bits or
#      straddles a word) but the 477 `(hi, lo)` pairs are NOT transcribed -- only
#      the 70 the gate names. A wrong bit position in an unnamed field is
#      invisible here, and `nv_qmd_fields_v3`/`_v5` pin only the counts.
#   3. THE ELF AND PTX TEXT. `elf_loader` (support/elf.py) parses the sections that
#      `shmem`, `prog_off`, `constbufs` and `regs` come from; those five NUMBERS
#      are ported as inputs and the parse is not.
#   4. THE PM TRACE. `reg_ops` is ported to its CHUNK COUNT and its mask default;
#      the register VALUES and the `struct_NVB0CC_CTRL_EXEC_REG_OPS_PARAMS` are
#      the seam, so a wrong value in a profiler write is invisible.
#   5. `_submit_cmds` ITSELF. It builds, LOWERS, COMPILES and RUNS a linear
#      through realize.py's scheduler. This file records that channel setup
#      happens by the words `_submit_cmds` would upload and by the fact that it
#      uses the same submit as a kernel; the lowering is not here.
#   6. `MOCKIface`. It inherits `NVKIface` whole and differs in `count = 1` and
#      two `page_size` branches; only the page-size branch is ported, and
#      `nv_ps_1_001` is the row.
#      AND now the `count = 1` HALF is ported too -- STAGE 5 -- along with
#      the selection rule and the mock driver's answers. WHAT REMAINS IS THE
#      INHERITED part, WHICH is `NVKIface`'S own ioctl surface and therefore
#      THE same seam as item 1: THE mock is a driver substitution, NOT a
#      DIFFERENT code path, SO porting the mock'S class does not port the
#      DRIVER UNDER IT.
