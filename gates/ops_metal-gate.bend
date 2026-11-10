# gates/ops_metal-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_metal.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_metal.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S

# ops_metal.py:85, `HANDLES`. The five, as their own def because `sels` (:224)
# writes them in this order and `mark_resident` (:237) rewrites slots 3 and 4.
def handles() -> List<&2, String>:
  ["queue", "event", "fence", "resources", "count"]

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

def str_list_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, String, a)),
                     U32.from_nat(List.length(&2, String, b))), P.str_eq.go(a, b, False{}))

# :262, `raise RuntimeError(f"local size {dims[3:]} bigger than {mx}")`. A
# Python tuple repr: `(4, 1, 1) bigger than 1024`. The tuple's spelling is the
# port's, and `mt_local_4` says so.
def msg_local(lx: U32, ly: U32, lz: U32, mx: U32) -> String:
  String.concat(["local size (", U32.show(lx), ", ", U32.show(ly), ", ",
                 U32.show(lz), ") bigger than ", U32.show(mx)])

# :273, `raise RuntimeError(f"{self.device} signal wait timed out")`. The
# device name is the argument, so on `Device["METAL"]` with no index the PREFIX
# is EMPTY and the message is exactly the tail -- which is the case the gate
# diffs, because `d.device == ''` is MEASURED on this host.
def msg_timeout() -> String: " signal wait timed out"

# :70, `assert ret[:4] == b"MTLB" and ret[-4:] == b"ENDT", f"Invalid Metal
# library. {ret!r}"`. The `repr` is a `bytes` and has no spelling here, so the
# port builds the PREFIX and the seam appends the repr.
def msg_badlib() -> String: "Invalid Metal library. "

def metal_version(+major: U32) -> String:
  P.metal_version.at(U32.is_ge(major, 26), U32.is_ge(major, 14), U32.is_ge(major, 13))

# :60 `params = f'-fno-fast-math -std={metal_version} --driver-mode=metal -x
# metal -fmodules-cache-path="{cache_dir}" -fno-caret-diagnostics'`. The whole
# string, because the gate diffs it against CPython's own f-string and a
# dropped literal inside `String.concat` is SILENT.
#
# `cache_dir` is `helpers.py`'s, which is a `Path` under the tinygrad cache
# directory and is therefore the seam's value -- but it is a PARAMETER and not a
# constant, so `mt_params_cache` can diff two different cache dirs and prove
# the interpolation site is where the source puts it.
def mtl_params(cache: String, mv: String) -> String:
  String.concat(["-fno-fast-math -std=", mv,
                 " --driver-mode=metal -x metal -fmodules-cache-path=\"", cache,
                 "\" -fno-caret-diagnostics"])

def creq_len(nsrc: U32, nparams: U32) -> U32:
  U32.add(P.cstruct_qq(), U32.add(P.csrc_padded(nsrc), P.cparams_padded(nparams)))

# :50, `ret = reply[sum(struct.unpack('<LL', reply[8:16])):]` -- the data starts
# at header size + warning size, both u32s read out of bytes 8..16. The SLICE
# is the seam's; the SUM is the port's, and `mt_liboff` is its row. A reply
# with a zero header and a zero warning puts the data at byte 0.
def mtl_lib.off(hdr: U32, warn: U32) -> U32: U32.add(hdr, warn)

def ccompile.of(err: U32, head: U32, tail: U32, ibytes: U32, t: P.Tr) -> P.Tr:
  P.ccompile.slice.at(P.cc_error_ok(err), head, tail, P.cgs_build(ibytes, P.cgs_create(t)))

def ccompile(cerr: Bool, head: U32, tail: U32, ibytes: U32, t: P.Tr) -> P.Tr:
  P.ccompile.ok(head, tail, P.cgs_build(ibytes, P.cgs_create(t)))

# :123 `wait(self, dst, val, eq=False): pass` -- "the fence orders the queue",
# so the NO-OP is the port: `q.wait` returns its trace untouched and
# `mt_wait_noop` is the row that says a trace with a wait in it is the same
# trace as one without.
def q.wait(t: P.Tr) -> P.Tr: t

# :124 `timestamp(self, dst): self.stamps.append(dst)` and :125
# `signal(self, dst, val): self.value = val`. The first is a count and the
# second is a value, and they are the two things `run` and `submit` branch on.
def q.timestamp(q: P.Q) -> P.Q:
  match q:
    case P.Q{rows, cmds, sizes, stamps, nbytes, npipes, t}:
      P.Q{rows, cmds, sizes, U32.add(stamps, 1), nbytes, npipes, t}

# ops_metal.py:109-121 -- `exec`, in the order the source does it. THREE steps
# and the order is the claim: the offset, the layout and the symbolic arm, then
# the command.
def q.exec(+q: P.Q, nbufs: Nat, vars: List<&2, U32>, lib: U32, nm: String,
           ds: List<&2, U32>, +mask: U32) -> P.Q:
  a1 = P.q.exec.off(P.Q.nbytes(q))
  P.q.exec.cmd(P.q.exec.pre(q, nbufs, vars, mask), lib, nm, P.q.dims(mask, ds), a1, mask)

def dev.table_len(+nres: U32) -> U32:
  Bool.pick(U32, U32.is_lt(nres, P.TABLE_MIN()), P.TABLE_MIN(), nres)

# ops_metal.py:196-220 -- `__init__`, in the order the twelve statements are
# written. The ORDER is the claim and `mt_init_order` is the row: the system
# device, then the queue (and the ONE refusal), then the residency set (and
# `addResidencySet` only if it exists), then the event and the fence, then the
# family probe, then the arch. `q_ok` drives the refusal and `has_res` is the
# residency set's EXISTENCE, which is not a refusal.
def dev.init(+apple: U32, +mac: U32, q_ok: Bool, +has_res: Bool) -> P.Dev:
  +a1 = P.Dev.at(P.Dev.of(), P.dev.sysdevice(P.Tr.of()))
  a2 = P.Dev.at(a1, P.dev.queue(P.Dev.tr(a1)))
  +a3 = P.dev.queue_ok(q_ok, a2)
  +a4 = P.dev.add_residency.at(has_res, P.dev.residency(has_res, a3))
  a5 = P.dev.handles(a4)
  a6 = P.dev.arch(apple, mac, P.dev.family(P.dev.arch.apple(mac, apple), a5))
  a6


def sels_bytes() -> U32: U32.mul(P.sels_len(), S.Dt.itemsize(S.uint64()))

# :226, `Buffer(self.host, len(vals), dtypes.uint64, initial_value=...)` and
# then the `cached_property`'s memo.
def dev.sels(ar: D.Bar, dev: U32) -> P.Made:
  P.made.at(P.made.of(ar, dev, P.sels_len(), S.uint64(), 0, D.spec(), P.Tr.of()),
          P.selreg(P.Tr.of()))

def dev.sels_made.at(d: P.Dev) -> P.Dev:
  match d:
    case P.Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, _, t}:
      P.Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, True{}, t}

def new_slots_bytes(n: U32) -> U32: U32.mul(n, P.SLOTS_STRIDE())

def dev.wants_slots(n: U32) -> Bool: U32.is_gt(n, P.SLOTS_MIN())

def mtl_size.g(+ds: List<&2, U32>) -> P.MtlSize: P.mtl_size.at(0, ds)
def mtl_size.l(+ds: List<&2, U32>) -> P.MtlSize: P.mtl_size.at(3, ds)

# :262, `prod(dims[3:])` -- the local size's product, and the right-hand side of
# the ONLY per-command refusal in this file.
def q.prod_l(+ds: List<&2, U32>) -> U32: H.prod_u32(List.drop(&2, U32, ds, 3n))

# :130's third tag element and :132's `args.bitcast(dtypes.uint64)[zero // 8 + 3:]`
# -- the SAME number reached from two directions: a byte offset on one side and a
# word index on the other. `zero // 8 + 3` words past `zero // 8` IS
# `zero + 24` bytes, and `mt_hdr_word` is the row that says the two agree.
def icb_header(zero: U32) -> U32: U32.add(zero, P.ICB_HEADER_PAD())

def hdr_word(zero: U32) -> U32: U32.add(U32.div(zero, P.ADDR_SIZE()), P.HDR_SKIP())

# :266, `buf.host.view(fmt='P.Q')[header // 8:] = array.array('P.Q', [icb.value,
# *[c.value for c in commands], *[self.pipeline(*p).value for p in pipes]])`. The
# layout is ICB, then the COMMANDS, then the PIPELINES, and every index
# `run` uses is relative to the header: word 0 is the ICB (:151), word
# `1 + ci` is command ci (:136) and word `1 + n + i` is pipeline i (:148).
# `mt_hdr_layout` is the row.
def hdr_icb() -> U32: P.HDR_ICB()
def hdr_cmd(ci: U32) -> U32: U32.add(P.HDR_CMD(), ci)
def hdr_pipe(n: U32, i: U32) -> U32: U32.add(U32.add(n, P.HDR_PIPE()), i)

# :131, `patch(buf, self.rows + [(zero + 8 * i, UOp.const(0, dtypes.uint64)) for
# i in range(3)])` -- THREE zero rows, at `zero`, `zero + 8` and `zero + 16`,
# and three is the `+ 24` in both buffer sizes. `mt_zero_rows` is the row.
def zero_row(i: U32, zero: U32) -> U32: U32.add(zero, U32.mul(P.ADDR_SIZE(), i))

# :127-168, the whole of `submit`. FOUR steps in source order: the sizes loop,
# the three locals, the three-way tail.
def q.submit(+d: P.Dev, +q: P.Q) -> P.Tr:
  +n = P.Q.ncmds(q)
  a1 = P.q.submit.sizes.go(List.length(&2, P.Sz, P.Q.sizes(q)), 0, P.Q.sizes(q), P.Q.t(q))
  P.q.submit.at(Bool.not(P.q.syms(q)), P.q.many(q, n), d, n, P.Q.npipes(q),
              P.q.submit.zero(P.Q.nbytes(q)), 0, Bool.not(P.Dev.resid_ok(d)),
              P.dev.apple9(P.Dev.arch(d)), a1)

# :262, `if prod(dims[3:]) > (mx := state.maxTotalThreadsPerThreadgroup()): raise`.
# The local size's product against the pipeline's limit, and it is the ONLY
# per-command refusal in the file. The comparison is a STRICT `>` -- an exactly
# fitting local size is legal and `>=` would refuse it, which is why
# `mt_local_eq` (equal) and `mt_local_over` (one over) are the pair.
def local_ok(prod: U32, mx: U32) -> Bool: Bool.not(U32.is_gt(prod, mx))

# :267, `self.icbs[buf] = (icb, commands)` -- a `WeakKeyDictionary[Buffer,
# tuple]`, so an ICB Buffer that dies takes its entry with it. The port carries
# the COUNT and `mt_nics` is the row.
def icb_keep(d: P.Dev) -> P.Dev:
  match d:
    case P.Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}:
      P.Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam,
           U32.add(nics, 1), nslot, sels_made, t}

def dev.icb(ar: D.Bar, dev: U32, +q: P.Q, +header: U32, ok: Bool) -> P.Made:
  +b = P.dev.new_icb(ar, dev, q, header)
  a1 = P.icb_desc(P.Made.t(b))
  a2 = P.icb_binds1(P.icb_cmdtype(a1))
  a3 = P.icb_new(P.Q.ncmds(q), a2)
  a4 = P.icb_ok(ok, a3)
  a5 = P.icb_cmds(P.Q.ncmds(q), a4)
  P.made.at(b, P.icb_store(header, P.Q.ncmds(q), P.Q.npipes(q), P.icb_setup(q, True{}, True{}, True{}, a5)))

# THE SAME, with the two `checked` refusals and the :262 local-size refusal
# driven. `mt_icb_refuse_n` is the row that sees the TRUNCATION at command 1 of
# two, and it is the only fixture in the file that can.
def dev.icb.rf(ar: D.Bar, dev: U32, +q: P.Q, +header: U32, ok: Bool, +lib_ok: Bool,
               +pipe_ok: Bool, +lo: Bool) -> P.Made:
  +b = P.dev.new_icb(ar, dev, q, header)
  a1 = P.icb_desc(P.Made.t(b))
  a2 = P.icb_binds1(P.icb_cmdtype(a1))
  a3 = P.icb_new(P.Q.ncmds(q), a2)
  a4 = P.icb_ok(ok, a3)
  a5 = P.icb_cmds(P.Q.ncmds(q), a4)
  P.made.at(b, P.icb_store(header, P.Q.ncmds(q), P.Q.npipes(q), P.icb_setup(q, lib_ok, pipe_ok, lo, a5)))


# :174-179, `_alloc`, in source order: the buffer, the refusal, `mark_resident`,
# then the two handle reads of the BufferStorage.
# `mark_resident(mtl, True)` is handed the HANDLE the buffer call returned, which
# is `P.Tr.here` read BEFORE the refusal -- `P.Tr.refuse` does not advance the counter
# because a refused call mints nothing.
def alloc.of(ar: D.Bar, dev: U32, +size: U32, ext: Bool, ok: Bool, +d: P.Dev) -> P.Made:
  match d:
    case P.Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, +t}:
      +a1 = Bool.pick(P.Tr, ext, P.alloc_ext(t), P.alloc_size(size, t))
      +a2 = P.alloc_ok(ok, a1)
      a3 = P.Dev.tr(P.dev.mark_resident(P.Tr.here(a1), True{}, P.Dev.at(d, a2)))
      +b = P.made.of(ar, dev, size, S.uint8(), 0, D.spec(), a3)
      P.made.at(b, P.alloc_contents(P.alloc_addr(P.Made.t(b))))

# :185, `def _offset(self, buf, size, offset): return buf + offset`. THE SAME
# LINE as `device.py:330`'s `HostAllocator._offset`, and `D.host_offset` is that
# line ported -- so this is a one-line def that CONSUMES device.bend rather than
# re-deriving it, and `mt_offset` is the row that says the two agree.
def alloc_offset(buf: U32, off: U32) -> U32: D.host_offset(buf, off)

# :272-273,
#   `wait = objc.msg("waitUntilSignaledValue:timeoutMS:", ctypes.c_bool, [c_uint64, c_uint64])`
#   `if not wait(self.event, value, int(self.wait_timeout_ms)): raise RuntimeError(f"{self.device} signal wait timed out")`
# The TIMEOUT is the argument, and `int(self.wait_timeout_ms)` is a property of
# the base class and not of this file. `mt_waitsig` is the row and it is the
# SEVENTH refusal's own argument.
def dev.waitsig(tms: U32, +t: P.Tr) -> P.Tr:
  P.Tr.emit(P.CALL_WAITSIG, P.sel_ix("waitUntilSignaledValue:timeoutMS:"), tms, t)

# :273's refusal, and the message's device name is the PARAMETER.
def wait_ok(ok: Bool, +t: P.Tr) -> P.Tr: P.Tr.refuse(t, ok)

# :276-281 over a slots buffer of `size` u64 words. The guard is PER ENTRY in Python
# (`slots[start] and not slots[start + 2]`) and the port carries ONE Bool, because a
# `Bool` LIST is not a usable type here -- device.bend's measured constraint, and the
# same reason `exec`'s symbolic test is a six-bit MASK.
def dev.sync_scan(+size: U32, filled: Bool, t: P.Tr) -> P.Tr:
  P.dev.sync.go(U32.to_nat(P.sync_count(size)), P.sync_starts(size), filled, t)

def dev.pools.at(has: Bool, +t: P.Tr) -> P.Tr:
  match has:
    case True{}: P.pool_push(P.pool_pop(t))
    case False{}: P.pool_push(t)


# --- THE GATE ROWS ------------------------------------------------------
# ===========================================================================
# THE GATE. Every row is a claim about `ops_metal.py`'s TEXT, about a constant
# in `autogen/metal.py`, or about a LIVE `MetalDevice` on this host -- and every
# expectation is generated by `.agents/slop/mt_oracle.py`, which `ast`-walks this
# same Python file for the selector order and OPENS A REAL DEVICE for the arch,
# the family and the residency set. Nothing here is transcribed by hand.
#
# THE FIXTURES, and there are four of them:
#
#   fx_dev   METAL on THIS host: Apple8, a residency set, and the seven init
#            calls. MEASURED, not assumed.
#   fx_dev0  the same device with NO residency set, which is the configuration
#            that makes :143's `useResources:count:usage:` run -- and so the
#            only fixture in which all THIRTEEN of `run`'s calls appear.
#   fx_q     two commands sharing ONE pipeline, 2 global buffers and 1 var each,
#            the second with SYMBOLIC sizes. The shape of a 2-input 1-output
#            float kernel with a symbolic grid.
#   fx_run   fx_q submitted on fx_dev0 with no stamps: ONE `run` over (0, 2).
# ===========================================================================

def METAL_APPLE() -> U32: 1008
def METAL_MAC() -> U32: 2002

def fx_dev() -> P.Dev: dev.init(METAL_APPLE(), METAL_MAC(), True{}, True{})
def fx_dev0() -> P.Dev: dev.init(METAL_APPLE(), METAL_MAC(), True{}, False{})

# 2 global buffers, 1 var of 4 bytes, one MTLB (lib 1) named "kern", and the six
# numbers `(*global_size, *local_size)`.
def DIMS() -> List<&2, U32>: [8, 1, 1, 4, 1, 1]
def VARS() -> List<&2, U32>: [4]
def ALL_SYMS() -> U32: 63

# two `exec`s: the first constant, the second with all six dims symbolic. Both
# use the same (lib, name) so `pipes` is ONE.
def fx_q(mask: U32) -> P.Q:
  b1 = q.exec(P.Q.of(), 2n, VARS(), 1, "kern", DIMS(), 0)
  q.exec(b1, 2n, VARS(), 1, "kern", DIMS(), mask)

def fx_run(dev: P.Dev, mask: U32) -> P.Tr: q.submit(dev, fx_q(mask))

# the fixture's `zero`, :128's `round_up(self.nbytes, 8)` over BOTH commands.
# It is a def and not a literal because FIVE rows read it and they must all be
# the same number -- the first version of them hardcoded 256, which is the
# FIRST command's `off` rather than `zero`, and CPython answered 280. One `fx_zero`
# is what makes the family agree by construction.
def fx_zero() -> U32: P.q.submit.zero(P.Q.nbytes(fx_q(0)))

# :118's `at` for the fixture, read off the queue's OWN `sizes` list. The
# second command is the symbolic one, and `P.Sz.at` is the reader.
# the SIZE of `self.sizes` for the symbolic fixture -- one entry, because only
# the second command is symbolic. `mt_run_sym_n` and `mt_run_nosym_n` are the pair.



# ONE command, for :168's `run(h, n - 1, 1, True)` with n == 1
def one_cmd() -> P.Q: q.exec(P.Q.of(), 2n, VARS(), 1, "kern", DIMS(), 0)

# two commands with the given (lib, name) pairs -- the `pipes` dedup's fixture
def q2_pipe(l1: U32, l2: U32, n2: String) -> P.Q:
  q.exec(q.exec(P.Q.of(), 1n, [], l1, "kern", DIMS(), 0), 1n, [], l2, n2, DIMS(), 0)
def fx_t(dev: P.Dev) -> P.Tr: P.Tr.of()

def kinds(k: U32, t: P.Tr) -> List<&2, U32>: P.Tr.args(k, P.Tr.calls(t))
def sels_of(t: P.Tr) -> List<&2, U32>: P.Tr.sels(P.CALL_MSGSEND(), P.Tr.calls(t))
def store_slots(t: P.Tr) -> List<&2, U32>: P.Tr.sels(P.CALL_STORE(), P.Tr.calls(t))
def stores(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_STORE(), P.Tr.calls(t))
def ncalls(k: U32, t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
def seen(t: P.Tr) -> U32: U32.from_nat(List.length(&2, P.Call, P.Tr.calls(t)))
def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

# --- 1: the selector table, :85-91 -------------------------------------------
# `mt_sel_ix_*` is `(HANDLES + SELECTORS).index(name)` called in CPython, so
# every one of the EIGHTEEN is diffed against Python's own `.index` and the rest
# against the table's position. `mt_sel_n` is the COUNT, which is the row that
# sees a dropped selector -- and a dropped selector makes no `mt_sel_ix_*` row
# move, because `.index` of a name that is not there is 0 and 0 is `queue`'s.
def sel_n() -> U32: U32.from_nat(List.length(&2, D.AEnt, P.sel_table()))
def sel_h() -> U32: U32.from_nat(List.length(&2, String, handles()))
def sel_s() -> U32: U32.from_nat(List.length(&2, String, P.selectors()))

def t_sel() -> IO(Unit):
  do IO<Unit>:
    urow("mt_sel_n", sel_n())
    urow("mt_sel_handles", sel_h())
    urow("mt_sel_selectors", sel_s())
    urow("mt_sel_queue", P.sel_ix("queue"))
    urow("mt_sel_event", P.sel_ix("event"))
    urow("mt_sel_fence", P.sel_ix("fence"))
    urow("mt_sel_resources", P.sel_ix("resources"))
    urow("mt_sel_count", P.sel_ix("count"))
    urow("mt_sel_cmdbuf", P.sel_ix("commandBuffer"))
    urow("mt_sel_encoder", P.sel_ix("computeCommandEncoder"))
    urow("mt_sel_waitfence", P.sel_ix("waitForFence:"))
    urow("mt_sel_updatefence", P.sel_ix("updateFence:"))
    urow("mt_sel_signalev", P.sel_ix("encodeSignalEvent:value:"))
    urow("mt_sel_endenc", P.sel_ix("endEncoding"))
    urow("mt_sel_commit", P.sel_ix("commit"))
    urow("mt_sel_useres", P.sel_ix("useResources:count:usage:"))
    urow("mt_sel_exec", P.sel_ix("executeCommandsInBuffer:withRange:"))
    urow("mt_sel_conc", P.sel_ix("concurrentDispatchThreadgroups:threadsPerThreadgroup:"))
    urow("mt_sel_setpipe", P.sel_ix("setComputePipelineState:"))
    urow("mt_sel_dispatch", P.sel_ix("dispatchThreadgroups:threadsPerThreadgroup:"))
    urow("mt_sel_sigval", P.sel_ix("signaledValue"))
    # the first DIRECT selector, and the two that are the SAME SPELLING as a
    # SELECTORS entry with a colon -- the collision the `k` field exists for.
    urow("mt_sel_newqueue", P.sel_ix("newCommandQueueWithMaxCommandBufferCount"))
    urow("mt_sel_seticb", P.sel_ix("setSupportIndirectCommandBuffers"))
    urow("mt_sel_icbpipe", P.sel_ix("setComputePipelineState"))
    urow("mt_sel_setkbuf", P.sel_ix("setKernelBuffer_offset_atIndex"))
    urow("mt_sel_concd", P.sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"))
    urow("mt_sel_new", P.sel_ix("new"))
    urow("mt_sel_nsstring", P.sel_ix("stringWithUTF8String:"))
    urow("mt_sel_localdesc", P.sel_ix("localizedDescription"))
    # a name that is not in the table at all
    urow("mt_sel_missing", P.sel_ix("noSuchSelector"))
    urow("mt_sels_len", P.sels_len())
    urow("mt_sels_bytes", sels_bytes())
    urow("mt_msgsend_n", P.MSGSEND_N())
    urow("mt_req_compile", P.REQUEST_TYPE_COMPILE())
    urow("mt_queue_max", P.QUEUE_MAX_CMDS())
    urow("mt_usage_rw", P.USAGE_READ_WRITE())
    urow("mt_storagemode", P.STORAGE_MODE_SHARED())
    urow("mt_cmdtype", P.CMDTYPE_CONCURRENT())
    urow("mt_ph_ix", P.PLACEHOLDER_IX())

# --- 2: the compiler, :40, :56, :60, :62-63, :70 -----------------------------
# The `metal_version` ladder is FOUR arms and the boundary between arm 2 and arm
# 3 is macOS 13, so `mt_ver12` and `mt_ver13` are the pair that sees `>= 13`
# read as `>= 14`.
def t_compiler() -> IO(Unit):
  do IO<Unit>:
    srow("mt_cgs_k", P.CACHEKEY())
    srow("mt_ver26", metal_version(26))
    srow("mt_ver25", metal_version(25))
    srow("mt_ver14", metal_version(14))
    srow("mt_ver13", metal_version(13))
    srow("mt_ver12", metal_version(12))
    srow("mt_params", mtl_params("CACHE", metal_version(26)))
    srow("mt_params2", mtl_params("/tinygrad/cache", metal_version(12)))
    # :62's `round_up(len(src) + 1, 4) - len(src)`. `mt_pad4` is THE row: a
    # `round_up(len, 4) - len` transcription answers 0 where the source says 1,
    # and 0 is what the other seven rows also say, so only the `len == 4` one
    # can see it.
    urow("mt_pad0", P.csrc_pad(0))
    urow("mt_pad1", P.csrc_pad(1))
    urow("mt_pad2", P.csrc_pad(2))
    urow("mt_pad3", P.csrc_pad(3))
    urow("mt_pad4", P.csrc_pad(4))
    urow("mt_pad5", P.csrc_pad(5))
    urow("mt_pad7", P.csrc_pad(7))
    urow("mt_psrc7", P.csrc_padded(7))
    urow("mt_psrc4", P.csrc_padded(4))
    urow("mt_ppar109", P.cparams_padded(109))
    urow("mt_req7", creq_len(7, 109))
    urow("mt_req1", creq_len(1, 109))
    urow("mt_qq", P.cstruct_qq())
    urow("mt_mtlb", P.MTLB_MAGIC())
    urow("mt_endt", P.ENDT_MAGIC())
    urow("mt_liboff42", mtl_lib.off(4, 2))
    urow("mt_liboff00", mtl_lib.off(0, 0))
    +a : P.Tr <- IO.pure(P.Tr, ccompile(True{}, P.MTLB_MAGIC(), P.ENDT_MAGIC(), 134, P.Tr.of()))
    urow("mt_compile_ok_calls", seen(a))
    row("mt_compile_ok", Bool.not(P.Tr.refused(a)))
    +b : P.Tr <- IO.pure(P.Tr, ccompile(False{}, P.MTLB_MAGIC(), P.ENDT_MAGIC(), 134, P.Tr.of()))
    row("mt_compile_err", P.Tr.refused(b))
    urow("mt_compile_err_calls", seen(b))
    +c : P.Tr <- IO.pure(P.Tr, ccompile(True{}, 0, P.ENDT_MAGIC(), 134, P.Tr.of()))
    row("mt_compile_bad", P.Tr.refused(c))
    urow("mt_compile_bad_calls", seen(c))
    row("mt_nsstring_sel", U32.is_eq(P.sel_ix("stringWithUTF8String:"), 50))

# --- 2b: THE SEAM, :42-71, MEASURED ------------------------------------------
# Every number below came out of running the REAL `MTLCodeGenServiceBuildRequest`
# on this host with an INSTRUMENTED callback (`.agents/slop/mt_compile_probe.py`),
# not out of reading `compile`. That is the difference between this section and a
# transcription: `reply[8:16] == (104, 0)` and `error == 2` are answers, and the
# two blobs' different first words are the reason `P.REPLY_LEAD` exists.
#
# WHAT is still the seam, and it is ONE call. `compile` is FFI at exactly two
# points: `MTLCodeGenServiceCreate` (:39) and `MTLCodeGenServiceBuildRequest` (:68).
# The SECOND of those takes `ctypes.byref(callback, -0x10)` -- a pointer to the
# `invoke` slot of an Apple BLOCK, and Bend cannot allocate a block descriptor, let
# alone name its 16th byte. Everything else in :42-71 is now ported and gated:
# the four-way `-std=` ladder, the f-string, the 4-byte source pad, the NUL, the
# 16-byte `<QQ` header, the two request lengths, the callback's `error == 0` arm
# and its other arm, the header sum, the slice, and both refusals.
def t_seam() -> IO(Unit):
  do IO<Unit>:
    # :55-56 -- the version THIS host compiles with, diffed against `platform.mac_ver()`.
    urow("mt_macos_major", P.MACOS_MAJOR())
    srow("mt_ver_host", metal_version(P.MACOS_MAJOR()))
    # :62-63 -- a REAL kernel's two blob lengths and the request they make.
    urow("mt_psrc238", P.csrc_padded(238))
    urow("mt_ppar145", P.cparams_padded(145))
    urow("mt_req238", creq_len(238, 145))
    # :50 -- the header the REAL reply carried, and the MTLB it therefore starts at.
    urow("mt_liboff_host", mtl_lib.off(P.REPLY_HDR(), P.REPLY_WARN()))
    urow("mt_reply_hdr", P.REPLY_HDR())
    urow("mt_reply_warn", P.REPLY_WARN())
    # THE TWO BLOBS. `mt_reply_lead` is the UNSLICED reply's first word and
    # `mt_mtlb` is the SLICED one's; `mt_lead_is_mtlb` says they are NOT the same,
    # which is the only reason the distinction can survive an edit.
    urow("mt_reply_lead", P.REPLY_LEAD())
    row("mt_reply_is_mtlb", U32.is_eq(P.REPLY_LEAD(), P.MTLB_MAGIC()))
    # :47 -- the callback's own test, against the codes this host really returned.
    urow("mt_err_ok", P.CB_ERR_OK())
    urow("mt_err_compile", P.CB_ERR_COMPILE())
    row("mt_cb_ok0", P.cc_error_ok(P.CB_ERR_OK()))
    row("mt_cb_bad2", P.cc_error_ok(P.CB_ERR_COMPILE()))
    # THE TWO ARMS AS TRACES. One compiles and keeps both calls; the other calls and
    # then refuses, and the call COUNT is the row that says the refusal is a
    # TRUNCATION and not a skip -- which is the whole template of this file.
    +g : P.Tr <- IO.pure(P.Tr, ccompile.of(P.CB_ERR_OK(), P.MTLB_MAGIC(), P.ENDT_MAGIC(), 402, P.Tr.of()))
    urow("mt_cb_ok_calls", seen(g))
    row("mt_cb_ok_live", Bool.not(P.Tr.refused(g)))
    +h : P.Tr <- IO.pure(P.Tr, ccompile.of(P.CB_ERR_COMPILE(), P.MTLB_MAGIC(), P.ENDT_MAGIC(), 402, P.Tr.of()))
    urow("mt_cb_bad_calls", seen(h))
    row("mt_cb_bad_refused", P.Tr.refused(h))
    # M49's FIXTURE. Dropping the ENDT conjunct of :70 moved NOTHING, because every
    # other fixture feeds `ok` a good pair -- and `P.MTLB_MAGIC` and `P.ENDT_MAGIC` are
    # constants, so the check was only ever asked a question it had already been
    # told the answer to. `mt_cb_badtail` is the negative half and without it the
    # check is untested. (A `0` is a request for a fixture, not a coverage claim.)
    +i : P.Tr <- IO.pure(P.Tr, ccompile.of(P.CB_ERR_OK(), P.MTLB_MAGIC(), 0, 402, P.Tr.of()))
    row("mt_cb_badtail", P.Tr.refused(i))
    +j : P.Tr <- IO.pure(P.Tr, ccompile.of(P.CB_ERR_OK(), 0, P.ENDT_MAGIC(), 402, P.Tr.of()))
    row("mt_cb_badhead", P.Tr.refused(j))

# --- 2c: THE three defs that were written and never called --------------------
# `str_list_eq`, `icb_keep` and `sync_starts` were all live in the file's own words
# -- one of them carries a comment saying a row checks it -- and NOTHING reached
# them, which is what `.agents/slop/dead-defs.py` found. Wiring them costs three
# rows and buys three things no other row has: the WHOLE selector table in one
# comparison, `:267`'s weak-dict count, and the profile SCAN rather than a single
# scan step.
def t_wired() -> IO(Unit):
  do IO<Unit>:
    # :85-86, both tables, element for element -- the rows `.index` cannot see,
    # because a reordered pair of selectors with the same COUNT keeps every index.
    row("mt_tbl_handles", str_list_eq(handles(), ["queue", "event", "fence", "resources", "count"]))
    row("mt_tbl_sels", str_list_eq(P.selectors(), ["commandBuffer", "computeCommandEncoder", "waitForFence:",
                                                 "updateFence:", "encodeSignalEvent:value:", "endEncoding",
                                                 "commit", "useResources:count:usage:",
                                                 "executeCommandsInBuffer:withRange:",
                                                 "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
                                                 "setComputePipelineState:",
                                                 "dispatchThreadgroups:threadsPerThreadgroup:",
                                                 "signaledValue"]))
    # M54's FIXTURE, and it is the one that matters: the two rows above compare the
    # table against a COPY OF THE TABLE INSIDE THIS FILE, so their lengths always
    # agree and the ELEMENT comparison was never exercised -- deleting `str_eq.go`
    # from `str_list_eq` moved nothing. `mt_tbl_reorder` and `mt_tbl_wrong` are the
    # two negative halves: one swaps two names and one changes one, and a length
    # check alone sees NEITHER.
    row("mt_tbl_reorder", Bool.not(str_list_eq(P.selectors(), ["computeCommandEncoder", "commandBuffer", "waitForFence:",
                                                            "updateFence:", "encodeSignalEvent:value:", "endEncoding",
                                                            "commit", "useResources:count:usage:",
                                                            "executeCommandsInBuffer:withRange:",
                                                            "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
                                                            "setComputePipelineState:",
                                                            "dispatchThreadgroups:threadsPerThreadgroup:",
                                                            "signaledValue"])))
    row("mt_tbl_wrong", Bool.not(str_list_eq(handles(), ["queue", "event", "fence", "count", "resources"])))
    # :267, `self.icbs[buf] = (icb, commands)` -- a WeakKeyDictionary, so its only
    # observable is how many entries are alive. Zero, then one.
    urow("mt_nics0", P.Dev.nics(fx_dev()))
    urow("mt_nics1", P.Dev.nics(icb_keep(fx_dev())))
    # :276-281, THE SCAN. `filled` is the END SLOT, so `True` means "already
    # collected" and does NOTHING, and `False` is the arm that waits and reads the
    # two timestamps. Three calls per entry, so 13 words = two entries of
    # `range(5, 13, 4)` = six calls. The polarity is worth a comment because the
    # obvious reading of "filled" is the opposite one and it silently halves the
    # count from 6 to 0.
    lrow("mt_sync_scan_idx", P.sync_starts(13))
    # M51's FIXTURE. `mt_sync_scan_idx` reads `sync_starts` DIRECTLY, so a scan that
    # walked one entry too few moved nothing -- the row never went through the def
    # under repair, and `sync_starts` is unchanged by such a bug.
    # The scan's COUNT through `dev.sync_scan` itself, at two sizes, because
    # `sync_starts` returns the same list for 13 and for 17 -- `sync_count` decides
    # the length and `sync_starts` only walks it -- so a scan that lost its last
    # entry is a COUNT bug and needs two sizes to be visible at all.
    urow("mt_sync_scan_calls21", seen(dev.sync_scan(21, False{}, P.Tr.of())))
    lrow("mt_sync_scan_idx21", P.sync_starts(21))
    +u : P.Tr <- IO.pure(P.Tr, dev.sync_scan(13, False{}, P.Tr.of()))
    urow("mt_sync_scan_calls", seen(u))
    row("mt_sync_scan_refused", P.Tr.refused(u))
    +w : P.Tr <- IO.pure(P.Tr, dev.sync_scan(13, True{}, P.Tr.of()))
    urow("mt_sync_noscan_calls", seen(w))
    # `size` below P.SYNC_START is an EMPTY range in Python, not a negative count.
    lrow("mt_sync_scan_small", P.sync_starts(4))
    urow("mt_sync_scan_small_calls", seen(dev.sync_scan(4, False{}, P.Tr.of())))

    # :247, the NSString, wired in -- `mt_pipe_order` and `mt_pipe_sels` are the
    # rows that see it and they are in `t_icb`; nothing is repeated here.


# --- 3: the init ORDER and the family table, :196-215 ------------------------
# `mt_init_order` pins the ORDER AND THE IDENTITY of all eight calls, and the
# oracle's `init_*` rows are the same statements read out of the AST.
def init_pat() -> List<&2, P.Call>:
  [P.Call{P.CALL_SYSDEVICE, P.PLACEHOLDER_IX(), 0},
   P.Call{P.CALL_NEWQUEUE, P.sel_ix("newCommandQueueWithMaxCommandBufferCount"), P.QUEUE_MAX_CMDS()},
   P.Call{P.CALL_MSGSEND, P.sel_ix("new"), 0},
   P.Call{P.CALL_NEWRESID, P.sel_ix("newResidencySetWithDescriptor_error"), 0},
   P.Call{P.CALL_ADDRESID, P.sel_ix("addResidencySet"), 0},
   P.Call{P.CALL_NEWEVENT, P.sel_ix("newSharedEvent"), 0},
   P.Call{P.CALL_NEWFENCE, P.sel_ix("newFence"), 0},
   P.Call{P.CALL_FAMILY, P.sel_ix("supportsFamily"), METAL_APPLE()}]

def t_init() -> IO(Unit):
  do IO<Unit>:
    +d : P.Dev <- IO.pure(P.Dev, fx_dev())
    +t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(d))
    row("mt_init_order", seq(t, init_pat()))
    urow("mt_init_calls", seen(t))
    lrow("mt_init_sels", kinds(P.CALL_MSGSEND(), t))
    urow("mt_init_new_n", ncalls(P.CALL_MSGSEND(), t))
    lrow("mt_init_sels_only", sels_of(t))
    srow("mt_init_arch", P.Dev.arch(d))
    urow("mt_init_fam", P.Dev.fam(d))
    row("mt_init_resid", P.Dev.resid_ok(d))
    lrow("mt_init_queueargs", kinds(P.CALL_NEWQUEUE(), t))
    +d0 : P.Dev <- IO.pure(P.Dev, fx_dev0())
    row("mt_init_noresid", Bool.not(P.Dev.resid_ok(d0)))
    urow("mt_init_noresid_calls", seen(P.Dev.tr(d0)))
    lrow("mt_init_noresid_sels", kinds(P.CALL_MSGSEND(), P.Dev.tr(d0)))
    # the ONE refusal in __init__
    +dq : P.Dev <- IO.pure(P.Dev, dev.init(METAL_APPLE(), METAL_MAC(), False{}, False{}))
    row("mt_init_refused", P.Tr.refused(P.Dev.tr(dq)))
    urow("mt_init_refused_calls", seen(P.Dev.tr(dq)))
    srow("mt_msg_noqueue", P.msg_noqueue())
    # the family table, BOTH DIRECTIONS
    urow("mt_fam_n", U32.from_nat(List.length(&2, D.AEnt, P.families())))
    urow("mt_fam_apple8", P.check_family([1008], "Apple"))
    urow("mt_fam_apple8_9", P.check_family([1008, 1009], "Apple"))
    urow("mt_fam_apple9", P.check_family([1008, 1009], "Apple"))
    urow("mt_fam_apple_first", P.check_family([1001, 1002, 1003], "Apple"))
    urow("mt_fam_mac", P.check_family([2001, 2002], "Mac"))
    urow("mt_fam_mac_catalyst", P.check_family([2001, 2002, 4001, 4002], "Mac"))
    urow("mt_fam_none", P.check_family([2001, 2002], "Apple"))
    urow("mt_fam_apple9_family", P.check_family([1009], "Apple"))
    srow("mt_fam_nm", P.fam_nm(1008))
    srow("mt_fam_nm_metal", P.fam_nm(5002))
    srow("mt_fam_nm_missing", P.fam_nm(4242))
    srow("mt_arch_slice", P.arch_of(1008))
    srow("mt_arch_slice_mac", P.arch_of(2002))
    srow("mt_arch_slice_none", P.arch_of(0))
    urow("mt_arch_or_apple", P.dev.arch.apple(METAL_MAC(), METAL_APPLE()))
    urow("mt_arch_or_fallback", P.dev.arch.apple(METAL_MAC(), 0))
    urow("mt_arch_or_none", P.dev.arch.apple(0, 0))
    # the apple9 DISJUNCTION, and only the last two rows of the family can see
    # an `or` read as an `and`.
    row("mt_apple9_apple8", P.dev.apple9("Apple8"))
    row("mt_apple9_apple9", P.dev.apple9("Apple9"))
    row("mt_apple9_apple10", P.dev.apple9("Apple10"))
    row("mt_apple9_mac2", P.dev.apple9("Mac2"))
    row("mt_apple9_metal4", P.dev.apple9("Metal4"))
    urow("mt_apple_num_apple8", P.dev.apple_num("Apple8"))
    urow("mt_apple_num_apple9", P.dev.apple_num("Apple9"))
    urow("mt_apple_num_common", P.dev.apple_num("Common1"))
    urow("mt_apple_num_mac", P.dev.apple_num("Mac2"))

# --- 4: THE per-CALL trace for a fixed pipeline, :127-168 --------------------
# THIS IS THE PORT. The `run` sequence below is `mt_oracle.py`'s `run_order` row,
# which is an `ast` walk of ops_metal.py:138-163 -- so the expectation is the
# source's own statement order and a dropped or moved line moves a row.
#
# The fixture is fx_dev0 (NO residency set, so :143 runs) on Apple8 (so
# :146-149 run), with no stamps (so :157 does not) and `last` (so :162 does), and
# TWO commands sharing ONE pipeline. So the trace is the thirteen statements of
# `run` -- TWELVE msgSends and two UOp stores -- plus the ONE
# `setComputePipelineState:` that :148 emits per pipe.
# THE ELEVEN msgSENDS, with EVERY argument spelled, and the four that are not
# zero are the four the source computes: the FENCE handle (:141 and :152),
# `1 + n + i` (:148), `zero` (:149) and `count` (:151). Spelling them is what
# makes the row an IDENTITY check and not an order check -- the first version of
# this pattern had zeros in all four and printed False, which is a row that says
# nothing about the order and a bad way to learn that.
#
# THE FENCE HANDLE IS NOT ZERO and that is not an accident of the fixture: it is
# minted by the DEVICE's trace during `__init__` and the QUEUE's trace is a
# different one, which is faithful -- `MetalQueue.h` starts empty in Python too.
# So the handle is a number from another arena and the row spells it rather than
# pretending the two traces share a counter.
def run_pat(+d: P.Dev, +n: U32) -> List<&2, P.Call>:
  [P.Call{P.CALL_MSGSEND, P.SEL_COMMANDBUFFER(), 0},
   P.Call{P.CALL_MSGSEND, P.SEL_COMPUTEENCODER(), 0},
   P.Call{P.CALL_MSGSEND, P.SEL_WAITFENCE(), P.Dev.fence(d)},
   P.Call{P.CALL_MSGSEND, P.SEL_USERESOURCES(), P.Dev.nres(d)},
   P.Call{P.CALL_MSGSEND, P.SEL_SETPIPESTATE(), hdr_pipe(n, 0)},
   P.Call{P.CALL_MSGSEND, P.SEL_DISPATCH(), fx_zero()},
   P.Call{P.CALL_MSGSEND, P.SEL_EXECUTECMDS(), n},
   P.Call{P.CALL_MSGSEND, P.SEL_UPDATEFENCE(), P.Dev.fence(d)},
   P.Call{P.CALL_MSGSEND, P.SEL_ENDENCODING(), 0},
   P.Call{P.CALL_MSGSEND, P.SEL_SIGNALEVENT(), 0},
   P.Call{P.CALL_MSGSEND, P.SEL_COMMIT(), 0}]

def t_run() -> IO(Unit):
  do IO<Unit>:
    +d : P.Dev <- IO.pure(P.Dev, fx_dev0())
    +t : P.Tr <- IO.pure(P.Tr, q.submit(d, fx_q(0)))
    # THE MATCHER PINS ITSELF FIRST, because every order row below depends on it
    # being a real SUBSEQUENCE test. `P.Tr.has`'s fuel is the TRACE length and the
    # answer is `at == patlen`; get either half wrong and it answers True to
    # everything, which is the bug the WebGPU template's M23 documents.
    row("mt_has_reverse", Bool.not(seq(t, [P.Call{P.CALL_MSGSEND, P.SEL_COMMIT(), 0},
      P.Call{P.CALL_MSGSEND, P.SEL_COMMANDBUFFER(), 0}])))
    row("mt_has_absent", Bool.not(seq(t, [P.Call{P.CALL_MSGSEND, 99, 0}])))
    row("mt_has_absent3", Bool.not(seq(t, [P.Call{P.CALL_MSGSEND, P.SEL_DISPATCH(), 999}])))
    # A pattern that occurs ONLY LATE in the trace. The good matcher scans the
    # WHOLE trace; mutation M16 sets the fuel to the PATTERN length, so a
    # ONE-entry pattern would only ever look at entry 0. These three rows are
    # what makes M16 move more than one row, and they are the fixture the
    # WebGPU template's M23 says a subsequence matcher needs.
    +tl : P.Tr <- IO.pure(P.Tr, q.submit(fx_dev(), q.timestamp(fx_q(0))))
    row("mt_has_late", seq(tl, [P.Call{P.CALL_MSGSEND, P.SEL_COMMIT(), 0}]))
    row("mt_has_late2", seq(tl, [P.Call{P.CALL_STORE, P.slot_at(P.SLOT_PENDING(), 1), 0}]))
    row("mt_has_late_absent", Bool.not(seq(tl, [P.Call{P.CALL_MSGSEND, P.SEL_ENDENCODING(), 1}])))
    row("mt_run_order", seq(t, run_pat(d, 2)))
    urow("mt_run_calls", seen(t))
    lrow("mt_run_sels", sels_of(t))
    urow("mt_run_msgsend_n", ncalls(P.CALL_MSGSEND(), t))
    urow("mt_run_setpipe_n", P.Tr.count_s(P.SEL_SETPIPESTATE(), P.Tr.calls(t)))
    lrow("mt_run_exec_args", kinds(P.CALL_MSGSEND(), t))
    lrow("mt_run_disp_args", kinds(P.CALL_MSGSEND(), t))
    lrow("mt_run_setpipe_args", kinds(P.CALL_MSGSEND(), t))
    lrow("mt_run_useres_args", kinds(P.CALL_MSGSEND(), t))
    # WITH a residency set :143 is skipped -- THE MUTUAL EXCLUSION, and the
    # `nores` guard is :142's `self.dev.residency.value is None`.
    +tr : P.Tr <- IO.pure(P.Tr, q.submit(fx_dev(), fx_q(0)))
    urow("mt_run_res_calls", seen(tr))
    row("mt_run_res_nouseres", Bool.not(seq(tr, [P.Call{P.CALL_MSGSEND, P.SEL_USERESOURCES(), 0}])))
    # arch "Apple10": startswith("Apple") is true and 10 < 9 is false, so the
    # `or` is FALSE and BOTH :148 and :149 vanish. THE DISJUNCTION'S FIXTURE.
    +ta : P.Tr <- IO.pure(P.Tr, q.submit(dev.init(METAL_APPLE(), METAL_MAC(), True{}, False{}), fx_q(0)))
    urow("mt_run_a10_calls", seen(ta))
    row("mt_run_a10_nopipe", Bool.not(seq(ta, [P.Call{P.CALL_MSGSEND, P.SEL_SETPIPESTATE(), 0}])))
    row("mt_run_a10_nodisp", Bool.not(seq(ta, [P.Call{P.CALL_MSGSEND, P.SEL_DISPATCH(), 0}])))
    # SYMBOLIC sizes: :135-136 emits one
    # concurrentDispatchThreadgroups:threadsPerThreadgroup: PER entry of
    # `self.sizes`, BEFORE the `run`, and `exec` put ONE entry there.
    +ts : P.Tr <- IO.pure(P.Tr, q.submit(d, fx_q(ALL_SYMS())))
    # THE `at` IS 280 AND not any of the three numbers a reader guesses. It is
    # :118's `round_up(self.nbytes, 8)` taken AFTER the SECOND command's argument
    # block, which is at 256 and twenty bytes long, so it is `round_up(276, 8)`.
    # The first two versions of this row wrote 0 and 24 and both printed False,
    # and both were the ROW being wrong about the arithmetic and not about the
    # order -- which is why `mt_run_sym_args` below prints the WHOLE argument
    # list and this row says only that the msgSend comes first.
    row("mt_run_sym_first", seq(ts, [P.Call{P.CALL_MSGSEND, P.SEL_CONCDISPATCH(), 280},
      P.Call{P.CALL_MSGSEND, P.SEL_COMMANDBUFFER(), 0}]))
    urow("mt_run_sym_conc", ncalls(P.CALL_MSGSEND(), ts))
    lrow("mt_run_sym_args", kinds(P.CALL_MSGSEND(), ts))
    urow("mt_run_sym_n", U32.from_nat(List.length(&2, P.Sz, P.Q.sizes(fx_q(ALL_SYMS())))))
    urow("mt_run_nosym_n", U32.from_nat(List.length(&2, P.Sz, P.Q.sizes(fx_q(0)))))
    # TWO `run`s when there are stamps and n > 1: :167 then :168, and the first
    # is NOT `last`, so `encodeSignalEvent:value:` appears ONCE and `commit`
    # twice.
    +t2 : P.Tr <- IO.pure(P.Tr, q.submit(d, q.timestamp(fx_q(0))))
    urow("mt_run_two_calls", seen(t2))
    urow("mt_run_two_signal", P.Tr.count_s(P.SEL_SIGNALEVENT(), P.Tr.calls(t2)))
    urow("mt_run_two_commit", P.Tr.count_s(P.SEL_COMMIT(), P.Tr.calls(t2)))
    urow("mt_run_two_stores", ncalls(P.CALL_STORE(), t2))
    lrow("mt_run_two_storevals", stores(t2))
    lrow("mt_run_two_storeslots", store_slots(t2))
    # ONE `run` when there are stamps and n == 1: :168 alone, with first = 0.
    +t3 : P.Tr <- IO.pure(P.Tr, q.submit(d, q.timestamp(one_cmd())))
    urow("mt_run_one_commit", P.Tr.count_s(P.SEL_COMMIT(), P.Tr.calls(t3)))
    urow("mt_run_one_signal", P.Tr.count_s(P.SEL_SIGNALEVENT(), P.Tr.calls(t3)))
    lrow("mt_run_one_storevals", stores(t3))
    lrow("mt_run_one_storeslots", store_slots(t3))
    lrow("mt_run_one_exec", kinds(P.CALL_MSGSEND(), t3))
    # :123 `wait` IS A NO-OP -- the comment says "the fence orders the queue".
    row("mt_wait_noop", U32.is_eq(seen(q.wait(fx_t(d))), 0))

# --- 5: the ICB geometry, :112-121, :128-132, :266 ---------------------------
def t_geometry() -> IO(Unit):
  do IO<Unit>:
    # :111 -- every global is a `getaddr` and so is EIGHT bytes, and every var is
    # its own width. `mt_items_*` is the claim that the two halves DIFFER.
    lrow("mt_items_2_1", P.q.items(2n, [4]))
    lrow("mt_items_0_0", P.q.items(0n, []))
    lrow("mt_items_3_2", P.q.items(3n, [4, 2]))
    # `layout_args`, MEASURED through tinygrad's own `layout_args`:
    #   [u64, i32] at 0 -> [0:8, 8:4];  [u64, f16, f16] at 256 -> 256, 264, 266
    lrow("mt_layout_2buf1var", P.q.flat(P.q.layout(0, P.q.items(2n, [4])), Nil{}))
    lrow("mt_layout_3buf", P.q.flat(P.q.layout(0, P.q.items(3n, [])), Nil{}))
    lrow("mt_layout_at256", P.q.flat(P.q.layout(256, P.q.items(1n, [2, 2])), Nil{}))
    lrow("mt_layout_1buf", P.q.flat(P.q.layout(0, P.q.items(1n, [])), Nil{}))
    # :113's `max(..., default=off + 8)` -- the `default` is the whole point and
    # `mt_end_empty` is the only row that reaches it.
    urow("mt_end_2buf1var", P.q.end(0, P.q.layout(0, P.q.items(2n, [4]))))
    urow("mt_end_3buf", P.q.end(0, P.q.layout(0, P.q.items(3n, []))))
    urow("mt_end_1buf", P.q.end(0, P.q.layout(0, P.q.items(1n, []))))
    urow("mt_end_empty", P.q.end(256, Nil{}))
    urow("mt_end_empty0", P.q.end(0, Nil{}))
    # the two alignments, 256 and 8, and they are NOT the same number
    urow("mt_off256_1", P.q.exec.off(1))
    urow("mt_off256_256", P.q.exec.off(256))
    urow("mt_off256_257", P.q.exec.off(257))
    urow("mt_at8_1", P.q.exec.at(1))
    urow("mt_at8_9", P.q.exec.at(9))
    urow("mt_zero", P.q.submit.zero(1))
    urow("mt_zero9", P.q.submit.zero(9))
    # :128-132 -- the ICB sizes, and they must AGREE. `FX_ZERO` is the fixture's
    # OWN `zero`, not a literal: the first version of these five rows hardcoded
    # 256, which is the FIRST command's `off`, and CPython's `zero` is 280 -- so
    # five rows were wrong by 24 and the oracle caught all five at once. ONE
    # `fx_zero` def is what makes the family agree by construction.
    urow("mt_hdr_word", hdr_word(fx_zero()))
    urow("mt_header", icb_header(fx_zero()))
    urow("mt_header_agree", U32.mul(hdr_word(fx_zero()), P.ADDR_SIZE()))
    urow("mt_icb_size", P.icb_size(icb_header(fx_zero()), 2, 1))
    urow("mt_icb_size0", P.icb_size(0, 0, 0))
    urow("mt_icb_sizes_agree", P.icb_size(icb_header(fx_zero()), 2, 1))
    lrow("mt_zero_rows", [zero_row(0, fx_zero()), zero_row(1, fx_zero()),
                          zero_row(2, fx_zero())])
    # :266's header layout: the ICB at word 0, the commands at 1.., the pipes at
    # 1+n..  -- the three indices :151, :136 and :148 all read.
    urow("mt_hdr_icb", hdr_icb())
    urow("mt_hdr_cmd0", hdr_cmd(0))
    urow("mt_hdr_cmd1", hdr_cmd(1))
    urow("mt_hdr_pipe0", hdr_pipe(2, 0))
    urow("mt_hdr_pipe1", hdr_pipe(2, 1))
    # :121's tuple, and :117's mask
    lrow("mt_dims_const", P.q.dims(0, DIMS()))
    lrow("mt_dims_all", P.q.dims(ALL_SYMS(), DIMS()))
    lrow("mt_dims_mixed", P.q.dims(8, DIMS()))
    lrow("mt_dims_one", P.q.dims(1, DIMS()))
    row("mt_sym_no", Bool.not(P.q.any_sym(0)))
    row("mt_sym_yes", P.q.any_sym(ALL_SYMS()))
    row("mt_sym_bit", P.q.sym_at(8, 3))
    row("mt_sym_nobit", P.q.sym_at(8, 4))
    # :264's two MTLSizes, and :262's product
    urow("mt_size_g0", P.MtlSize.w(mtl_size.g(DIMS())))
    urow("mt_size_g2", P.MtlSize.d(mtl_size.g(DIMS())))
    urow("mt_size_l0", P.MtlSize.w(mtl_size.l(DIMS())))
    urow("mt_size_l1", P.MtlSize.h(mtl_size.l(DIMS())))
    urow("mt_size_l2", P.MtlSize.d(mtl_size.l(DIMS())))
    urow("mt_prod_l", q.prod_l(DIMS()))
    urow("mt_prod_l_1", q.prod_l([8, 1, 1, 1, 1, 1]))
    row("mt_local_eq", local_ok(1024, 1024))
    row("mt_local_over", local_ok(1025, 1024))
    row("mt_local_under", local_ok(1023, 1024))
    # `exec`, end to end, for the fixture: nbytes after both commands
    urow("mt_exec_nbytes", P.Q.nbytes(fx_q(ALL_SYMS())))
    urow("mt_exec_nbytes_c", P.Q.nbytes(fx_q(0)))
    urow("mt_exec_ncmds", P.Q.ncmds(fx_q(0)))
    urow("mt_exec_nrows", U32.from_nat(List.length(&2, P.Row, P.Q.rows(fx_q(0)))))
    urow("mt_exec_nrows_s", U32.from_nat(List.length(&2, P.Row, P.Q.rows(fx_q(ALL_SYMS())))))
    # the (lib, name) dedup: SAME name + DIFFERENT lib is TWO pipelines. The
    # JOINT condition is the claim, and these three rows are the only fixtures
    # that can see a dedup on either half alone.
    urow("mt_pipe_same", P.Q.npipes(fx_q(0)))
    urow("mt_pipe_difflib", P.Q.npipes(q2_pipe(1, 2, "kern")))
    urow("mt_pipe_diffname", P.Q.npipes(q2_pipe(1, 1, "other")))
    urow("mt_pipe_of_0", P.Seen.got(P.q.pipe_of(1, "kern", P.Q.cmds(fx_q(0)))))
    urow("mt_pipe_of_new", P.Seen.got(P.q.pipe_of(9, "nope", P.Q.cmds(fx_q(0)))))
    row("mt_pipe_of_new_hit", P.Seen.hit(P.q.pipe_of(9, "nope", P.Q.cmds(fx_q(0)))))

# --- 6: the allocator, the residency table and `mark_resident`, :174-237 -----
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # :175-179, the ORDER of the three calls: the buffer, then the ADDRESS, then
    # the CONTENTS -- because Python evaluates the BufferStorage's three
    # arguments left to right and `gpuAddress()` is the first of them.
    +a : P.Made <- IO.pure(P.Made, alloc.of(D.bar_empty(), P.MTL_DEV(), 64, False{}, True{}, fx_dev0()))
    # the binder is `t1` and not `at`, because `x.at` is Bend's namespace
    # selector and a `do`-block binder named `at` reads as one.
    +t1 : P.Tr <- IO.pure(P.Tr, P.Made.t(a))
    row("mt_alloc_order", seq(t1, [P.Call{P.CALL_NEWBUFFER, P.sel_ix("newBufferWithLength_options"), 64},
      P.Call{P.CALL_GPUADDR, P.sel_ix("gpuAddress"), 0},
      P.Call{P.CALL_CONTENTS, P.sel_ix("contents"), 0}]))
    urow("mt_alloc_nbytes", P.Made.nbytes(a))
    lrow("mt_alloc_size_arg", kinds(P.CALL_NEWBUFFER(), t1))
    # the EXTERNAL arm, :175's `MTLBuffer(options.external_ptr)`
    +e : P.Made <- IO.pure(P.Made, alloc.of(D.bar_empty(), P.MTL_DEV(), 64, True{}, True{}, fx_dev0()))
    lrow("mt_alloc_ext_kinds", kinds(P.CALL_NEWBUFFER(), P.Made.t(e)))
    # the OOM refusal and its MESSAGE
    srow("mt_oom_64", P.msg_oom(64))
    srow("mt_oom_0", P.msg_oom(0))
    +o : P.Made <- IO.pure(P.Made, alloc.of(D.bar_empty(), P.MTL_DEV(), 64, False{}, False{}, fx_dev0()))
    row("mt_alloc_refused", P.Tr.refused(P.Made.t(o)))
    urow("mt_alloc_refused_calls", seen(P.Made.t(o)))
    # :185 `_offset` IS `device.py:330`'s, consumed rather than re-derived
    urow("mt_offset", alloc_offset(4096, 16))
    urow("mt_offset0", alloc_offset(4096, 0))
    # `D.Bar` really is the Buffer: the ICB's `nolru` says it is never recycled
    row("mt_nolru", Bool.not(D.recycled(True{}, True{}, P.icb_spec())))
    row("mt_lru_alloc", D.recycled(True{}, True{}, D.spec()))
    urow("mt_icb_binds", P.icb_binds())
    urow("mt_icb_ix", P.KERNEL_BUF_IX())
    urow("mt_icb_max0", P.icb_max(0))
    urow("mt_icb_max2", P.icb_max(2))
    # `mark_resident`, the TWO PATHS. With a residency set: TWO calls and
    # `resources` UNCHANGED. Without: NO residency call and TWO stores.
    +mr : P.Dev <- IO.pure(P.Dev, P.dev.mark_resident(7, True{}, fx_dev()))
    row("mt_resid_excl", u32_list_eq(kinds(P.CALL_RS_ADD(), P.Dev.tr(mr)), [7]))
    urow("mt_resid_excl_commits", ncalls(P.CALL_RS_COMMIT(), P.Dev.tr(mr)))
    urow("mt_resid_excl_stores", ncalls(P.CALL_STORE(), P.Dev.tr(mr)))
    urow("mt_resid_excl_nres", P.Dev.nres(mr))
    urow("mt_resid_excl_len", U32.from_nat(List.length(&2, U32, P.Dev.res(mr))))
    lrow("mt_resid_add_sels", sels_of(P.Dev.tr(mr)))
    +md : P.Dev <- IO.pure(P.Dev, P.dev.mark_resident(7, False{}, fx_dev()))
    lrow("mt_resid_del_sels", sels_of(P.Dev.tr(md)))
    # without a residency set, and with the sels table already made
    +m0 : P.Dev <- IO.pure(P.Dev, P.dev.mark_resident(7, True{}, dev.sels_made.at(fx_dev0())))
    lrow("mt_resid_stores", kinds(P.CALL_STORE(), P.Dev.tr(m0)))
    lrow("mt_resid_store_slots", store_slots(P.Dev.tr(m0)))
    urow("mt_resid_made", U32.from_nat(List.length(&2, U32, P.Dev.res(m0))))
    urow("mt_resid_nres0", P.Dev.nres(m0))
    # and WITHOUT the sels table, which is the `cached_property` guard
    +m1 : P.Dev <- IO.pure(P.Dev, P.dev.mark_resident(7, True{}, fx_dev0()))
    urow("mt_resid_nomade", ncalls(P.CALL_STORE(), P.Dev.tr(m1)))
    urow("mt_resid_nomade_nres", P.Dev.nres(m1))
    # :224's THIRTEEN `sel_registerName` calls, in the SELECTORS order
    +sm : P.Made <- IO.pure(P.Made, dev.sels(D.bar_empty(), P.MTL_DEV()))
    urow("mt_sels_sels", ncalls(P.CALL_SELREG(), P.Made.t(sm)))
    lrow("mt_sels_sel_args", kinds(P.CALL_SELREG(), P.Made.t(sm)))
    urow("mt_sels_n", P.Made.nbytes(sm))
    row("mt_sels_made", P.Dev.sels_made(fx_dev0()))
    row("mt_sels_unmade", Bool.not(P.Dev.sels_made(fx_dev0())))
    # the `cached_property`'s MEMO, set by `dev.sels_made.at` -- the positive half,
    # and without it the flag has a `False` row and no `True` one, which is a
    # conjunct with a fixture on one side only.
    row("mt_sels_made_set", P.Dev.sels_made(dev.sels_made.at(fx_dev0())))
    urow("mt_table_one0", dev.table_len(0))
    urow("mt_table_one1", dev.table_len(1))
    urow("mt_table_five", dev.table_len(5))
    # :239's slots, and :218's `max_numel() > 4`
    urow("mt_slots_bytes", new_slots_bytes(8))
    urow("mt_slots_bytes0", new_slots_bytes(0))
    row("mt_slots_thresh4", dev.wants_slots(4))
    row("mt_slots_thresh5", dev.wants_slots(5))
    urow("mt_slots_str", P.SLOTS_STRIDE())
    # :101 `mtl_poll` and :273 `_wait_signal`
    +p : P.Tr <- IO.pure(P.Tr, P.mtl_poll(fx_dev0()))
    lrow("mt_poll_sels", sels_of(p))
    urow("mt_poll_calls", seen(p))
    lrow("mt_waitsig_t", kinds(P.CALL_WAITSIG(), dev.waitsig(5000, P.Tr.of())))
    srow("mt_msg_timeout", msg_timeout())
    row("mt_wait_ok", Bool.not(P.Tr.refused(wait_ok(True{}, P.Tr.of()))))
    row("mt_wait_bad", P.Tr.refused(wait_ok(False{}, P.Tr.of())))
    srow("mt_msg_badlib", msg_badlib())
    srow("mt_msg_noicb", P.msg_noicb())
    srow("mt_msg_local", msg_local(4, 1, 1, 1024))
    srow("mt_msg_local_1", msg_local(1, 1, 1, 256))

# --- 7: the pipeline and the ICB, :243-268 -----------------------------------
# :247 is the ORDER row: Python evaluates `setComputeFunction`'s ARGUMENT, so
# `to_ns_str` happens FIRST of all, then `newFunctionWithName`, and only then
# `setComputeFunction`. The NSString is the THIRD call and it was missing from this
# pattern until `cns_string` was wired -- which is why `mt_pipe_order` is the row
# that would have caught it: `seq` compares the WHOLE list, so a missing call in
# the middle is a length mismatch and not a mismatch somebody has to notice.
def pipe_pat() -> List<&2, P.Call>:
  [P.Call{P.CALL_NEWLIB, P.sel_ix("newLibraryWithData_error"), 0},
   P.Call{P.CALL_MSGSEND, P.sel_ix("new"), 0},
   P.Call{P.CALL_MSGSEND, P.sel_ix("stringWithUTF8String:"), 0},
   P.Call{P.CALL_NEWFUNC, P.sel_ix("newFunctionWithName"), 0},
   P.Call{P.CALL_SETCOMPFUNC, P.sel_ix("setComputeFunction"), 0},
   P.Call{P.CALL_SETICB, P.sel_ix("setSupportIndirectCommandBuffers"), 0},
   P.Call{P.CALL_NEWPIPE, P.sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0}]

def t_icb() -> IO(Unit):
  do IO<Unit>:
    +p : P.Tr <- IO.pure(P.Tr, P.dev.pipeline(True{}, True{}, P.Tr.of()))
    row("mt_pipe_order", seq(p, pipe_pat()))
    urow("mt_pipe_calls", seen(p))
    lrow("mt_pipe_sels", sels_of(p))
    row("mt_pipe_ok", Bool.not(P.Tr.refused(p)))
    +p1 : P.Tr <- IO.pure(P.Tr, P.dev.pipeline(False{}, True{}, P.Tr.of()))
    row("mt_pipe_librefuse", P.Tr.refused(p1))
    urow("mt_pipe_librefuse_calls", seen(p1))
    +p2 : P.Tr <- IO.pure(P.Tr, P.dev.pipeline(True{}, False{}, P.Tr.of()))
    row("mt_pipe_typerefuse", P.Tr.refused(p2))
    # :259's TWO calls per command, and :261-265's five per command
    +b : P.Made <- IO.pure(P.Made, dev.icb(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(fx_zero()), True{}))
    +bt : P.Tr <- IO.pure(P.Tr, P.Made.t(b))
    urow("mt_icb_calls", seen(bt))
    urow("mt_icb_nbytes", P.Made.nbytes(b))
    urow("mt_icb_cmds", ncalls(P.CALL_ICBCMD(), bt))
    urow("mt_icb_retain", ncalls(P.CALL_RETAIN(), bt))
    urow("mt_icb_bind", ncalls(P.CALL_SETKBUF(), bt))
    urow("mt_icb_bar", ncalls(P.CALL_SETBAR(), bt))
    urow("mt_icb_conc", ncalls(P.CALL_CONCDISP(), bt))
    lrow("mt_icb_kbuf_args", kinds(P.CALL_SETKBUF(), bt))
    lrow("mt_icb_cmd_args", kinds(P.CALL_ICBCMD(), bt))
    lrow("mt_icb_store", kinds(P.CALL_STORE(), bt))
    lrow("mt_icb_storeslots", store_slots(bt))
    # the per-command ORDER, :259 then :261-265. THE COUNTS (`mt_icb_cmds`,
    # `mt_icb_retain`) CANNOT see a swap of the two, which is what mutation M38
    # measured: 0 rows, and this row is the answer to that.
    # :259's list comprehension and :260's `zip` are TWO SEPARATE LOOPS: every
    # command handle is taken FIRST and only then is each one set up. The first
    # version of this pattern interleaved them and printed False, which is a row
    # that was wrong about the source and right about nothing.
    row("mt_icb_cmd_order", seq(bt, [P.Call{P.CALL_ICBCMD, P.sel_ix("indirectComputeCommandAtIndex"), 0},
      P.Call{P.CALL_RETAIN, P.sel_ix("retain"), 0},
      P.Call{P.CALL_ICBCMD, P.sel_ix("indirectComputeCommandAtIndex"), 1},
      P.Call{P.CALL_RETAIN, P.sel_ix("retain"), 1},
      P.Call{P.CALL_NEWPIPE, P.sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      P.Call{P.CALL_SETKBUF, P.sel_ix("setKernelBuffer_offset_atIndex"), 0},
      P.Call{P.CALL_CONCDISP, P.sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      P.Call{P.CALL_SETBAR, P.sel_ix("setBarrier"), 0},
      P.Call{P.CALL_NEWPIPE, P.sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      P.Call{P.CALL_SETKBUF, P.sel_ix("setKernelBuffer_offset_atIndex"), 256}]))
    row("mt_icb_ok", Bool.not(P.Tr.refused(bt)))
    row("mt_icb_order", seq(bt, [P.Call{P.CALL_MSGSEND, P.sel_ix("new"), 0},
      P.Call{P.CALL_SETCMDTYPE, P.sel_ix("setCommandTypes"), P.CMDTYPE_CONCURRENT()},
      P.Call{P.CALL_SETBINDS, P.sel_ix("setMaxKernelBufferBindCount"), 1},
      P.Call{P.CALL_NEWICB, P.sel_ix("newIndirectCommandBufferWithDescriptor_maxCommandCount_options"), 2},
      P.Call{P.CALL_ICBCMD, P.sel_ix("indirectComputeCommandAtIndex"), 0},
      P.Call{P.CALL_RETAIN, P.sel_ix("retain"), 0},
      P.Call{P.CALL_SETKBUF, P.sel_ix("setKernelBuffer_offset_atIndex"), 0},
      P.Call{P.CALL_CONCDISP, P.sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      P.Call{P.CALL_SETBAR, P.sel_ix("setBarrier"), 0},
      P.Call{P.CALL_STORE, U32.div(icb_header(fx_zero()), P.ADDR_SIZE()), 4}]))
    # the ICB refusal, :258
    +bn : P.Made <- IO.pure(P.Made, dev.icb(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(fx_zero()), False{}))
    row("mt_icb_refuse", P.Tr.refused(P.Made.t(bn)))
    urow("mt_icb_refuse_calls", seen(P.Made.t(bn)))
    # THE PER-COMMAND REFUSAL, :262, and it needs TWO commands to be visible:
    # with one command the truncation is the same length as with none, so the
    # COUNT row and the ORDER row are both blind to it on a one-command fixture.
    +c0 : P.Tr <- IO.pure(P.Tr, P.Made.t(dev.icb.rf(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(256), True{}, True{}, True{}, True{})))
    +c1 : P.Tr <- IO.pure(P.Tr, P.Made.t(dev.icb.rf(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(256), True{}, True{}, True{}, False{})))
    row("mt_icb_local_ok", Bool.not(P.Tr.refused(c0)))
    urow("mt_icb_local_ok_calls", seen(c0))
    row("mt_icb_local_refuse", P.Tr.refused(c1))
    urow("mt_icb_local_bad_calls", seen(c1))
    # :262 sits BETWEEN the pipeline and the bind, so a command whose local size
    # is too big is left with a pipeline and NO BUFFER. `mt_icb_local_bound` is
    # the negative row and it is the one that says the refusal is in the right
    # PLACE; the positive half only says the pipeline was built.
    row("mt_icb_local_pipeline", seq(c1, [P.Call{P.CALL_SETCOMPFUNC, P.sel_ix("setComputeFunction"), 0},
      P.Call{P.CALL_NEWPIPE, P.sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0}]))
    row("mt_icb_local_bound", Bool.not(seq(c1, [P.Call{P.CALL_SETKBUF, P.sel_ix("setKernelBuffer_offset_atIndex"), 0}])))
    # the per-command `checked` refusals reach the same place
    +c2 : P.Tr <- IO.pure(P.Tr, P.Made.t(dev.icb.rf(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(256), True{}, False{}, True{}, True{})))
    row("mt_icb_librefuse", P.Tr.refused(c2))
    urow("mt_icb_librefuse_calls", seen(c2))
    # the OTHER `checked`, :249's, on the same fixture: the pipeline TYPE refusal
    # and the library refusal are the two sites `checked` wraps, and the second
    # is only reachable if the first passes.
    +c3 : P.Tr <- IO.pure(P.Tr, P.Made.t(dev.icb.rf(D.bar_empty(), P.MTL_DEV(), fx_q(0), icb_header(fx_zero()), True{}, True{}, False{}, True{})))
    row("mt_icb_typerefuse", P.Tr.refused(c3))
    urow("mt_icb_typerefuse_calls", seen(c3))

# --- 8: `synchronize`, :270-285 ------------------------------------------------
def t_sync() -> IO(Unit):
  do IO<Unit>:
    urow("mt_sync_start", P.SYNC_START())
    urow("mt_sync_step", P.SYNC_STEP())
    urow("mt_sync_end_off", P.SYNC_END_OFFSET())
    # `range(5, size, 4)` -- the count AND the list, because a wrong step gives
    # the right count for some sizes and the wrong list for all of them.
    urow("mt_sync_n0", P.sync_count(0))
    urow("mt_sync_n4", P.sync_count(4))
    urow("mt_sync_n5", P.sync_count(5))
    urow("mt_sync_n9", P.sync_count(9))
    urow("mt_sync_n13", P.sync_count(13))
    urow("mt_sync_n17", P.sync_count(17))
    urow("mt_sync_n21", P.sync_count(21))
    lrow("mt_sync_idx17", P.sync_range.go(3n, P.SYNC_START(), Nil{}))
    lrow("mt_sync_idx21", P.sync_range.go(4n, P.SYNC_START(), Nil{}))
    lrow("mt_sync_idx5", P.sync_range.go(1n, P.SYNC_START(), Nil{}))
    urow("mt_sync_end_slot5", P.sync_end_slot(5))
    urow("mt_sync_end_slot9", P.sync_end_slot(9))
    # :279-281 -- the guard, and the three calls it makes
    # :279's guard is `slots[start] and not slots[start + 2]` -- the body runs
    # when the command buffer is THERE and the END time is NOT, so `collected`
    # False is the fixture that does the work and `mt_sync_guard_*` is the PAIR
    # that says so.
    +g0 : P.Tr <- IO.pure(P.Tr, P.sync.one(5, False{}, P.Tr.of()))
    urow("mt_sync_guard_hits", seen(g0))
    lrow("mt_sync_guard_sels", sels_of(g0))
    lrow("mt_sync_guard_args", kinds(P.CALL_MSGSEND(), g0))
    +g1 : P.Tr <- IO.pure(P.Tr, P.sync.one(9, True{}, P.Tr.of()))
    urow("mt_sync_guard_miss", seen(g1))
    # :284-285 -- POP THEN PUSH
    +p : P.Tr <- IO.pure(P.Tr, dev.pools.at(True{}, P.Tr.of()))
    row("mt_pool_order", seq(p, [P.Call{P.CALL_AUTORELPOP, P.PLACEHOLDER_IX(), 0},
      P.Call{P.CALL_AUTORELPUSH, P.PLACEHOLDER_IX(), 0}]))
    +p0 : P.Tr <- IO.pure(P.Tr, dev.pools.at(False{}, P.Tr.of()))
    urow("mt_pool_nopop", ncalls(P.CALL_AUTORELPOP(), p0))
    urow("mt_pool_push", ncalls(P.CALL_AUTORELPUSH(), p0))

# ===========================================================================
# --- 9: THE CONSTANTS THEMSELVES -------------------------------------------
# WHY THIS SECTION EXISTS, and it is the answer to ops_nv.bend, which shipped 606
# green rows with 33 of 219 constants WRONG. Every other section in this file tests
# a GRAPH. A wrong constant in a graph is visible; a wrong constant in a dead
# corner is not, and no amount of rows finds it -- the numbers answer to
# `autogen/metal.py` and to `ops_metal.py`'s literals, and neither was being read.
#
# So every numeric constant def that has a numeric authority gets a row HERE, and
# `.agents/slop/mt_constmap.py --rows` emits the same row names from CPython: the
# authority for `P.MTLB_MAGIC` is `int.from_bytes(b"MTLB", "little")`, for
# `P.CMDTYPE_CONCURRENT` it is `getattr(autogen.metal, ...)` , for `P.HDR_CMD` it is the
# int CPython's `ast` pulls out of `ops_metal.py:136`, and for `P.DIM_WORDS` it is
# `len(dims)` recorded off a REAL kernel launch through the REAL `MetalQueue.exec`.
# `mt_diff.py` then compares the two. A hand map is the map; CPython is the answer.
#
# ELEVEN of these were DEAD before this section -- declared, correct as far as I can
# tell, and read by NOTHING, so mutating any of them moved zero rows and no
# mutation in the table below could have found them. `mt_c_*` is what makes a
# constant with no reader into a constant that is checked.
# ===========================================================================
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("mt_c_request_type", P.REQUEST_TYPE_COMPILE())
    urow("mt_c_queue_max", P.QUEUE_MAX_CMDS())
    urow("mt_c_usage_rw", P.USAGE_READ_WRITE())
    urow("mt_c_storagemode", P.STORAGE_MODE_SHARED())
    urow("mt_c_cmdtype", P.CMDTYPE_CONCURRENT())
    urow("mt_c_binds", P.KERNEL_BUF_BINDS())
    urow("mt_c_icbopt", P.ICB_OPTIONS())
    urow("mt_c_pipeopt", P.MTL_PIPELINE_OPTION_NONE())
    urow("mt_c_run_count_all", P.RUN_COUNT_ALL())
    urow("mt_c_sync_start", P.SYNC_START())
    urow("mt_c_sync_step", P.SYNC_STEP())
    urow("mt_c_sync_end", P.SYNC_END_OFFSET())
    urow("mt_c_zero_align", P.ZERO_ALIGN())
    urow("mt_c_zero_rows", P.ZERO_ROWS())
    urow("mt_c_icb_pad", P.ICB_HEADER_PAD())
    urow("mt_c_arg_align", P.ARG_ALIGN())
    urow("mt_c_sym_bytes", P.SYM_BYTES())
    urow("mt_c_dim_words", P.DIM_WORDS())
    urow("mt_c_hdr_skip", P.HDR_SKIP())
    urow("mt_c_hdr_icb", P.HDR_ICB())
    urow("mt_c_hdr_cmd", P.HDR_CMD())
    urow("mt_c_hdr_pipe", P.HDR_PIPE())
    urow("mt_c_addr_size", P.ADDR_SIZE())
    urow("mt_c_sel_queue", P.SEL_QUEUE())
    urow("mt_c_sel_event", P.SEL_EVENT())
    urow("mt_c_sel_fence", P.SEL_FENCE())
    urow("mt_c_sel_resources", P.SEL_RESOURCES())
    urow("mt_c_sel_count", P.SEL_COUNT())
    urow("mt_c_sel_cmdbuf", P.SEL_COMMANDBUFFER())
    urow("mt_c_sel_encoder", P.SEL_COMPUTEENCODER())
    urow("mt_c_sel_waitfence", P.SEL_WAITFENCE())
    urow("mt_c_sel_updatefence", P.SEL_UPDATEFENCE())
    urow("mt_c_sel_signalev", P.SEL_SIGNALEVENT())
    urow("mt_c_sel_endenc", P.SEL_ENDENCODING())
    urow("mt_c_sel_commit", P.SEL_COMMIT())
    urow("mt_c_sel_useres", P.SEL_USERESOURCES())
    urow("mt_c_sel_exec", P.SEL_EXECUTECMDS())
    urow("mt_c_sel_conc", P.SEL_CONCDISPATCH())
    urow("mt_c_sel_setpipe", P.SEL_SETPIPESTATE())
    urow("mt_c_sel_dispatch", P.SEL_DISPATCH())
    urow("mt_c_sel_sigval", P.SEL_SIGNALEDVALUE())
    urow("mt_c_msgsend_n", P.MSGSEND_N())
    urow("mt_c_ret_none", P.RET_NONE())
    urow("mt_c_ret_voidp", P.RET_VOIDP())
    urow("mt_c_placeholder", P.PLACEHOLDER_IX())
    urow("mt_c_cstruct_qq", P.cstruct_qq())
    urow("mt_c_mtlb", P.MTLB_MAGIC())
    urow("mt_c_endt", P.ENDT_MAGIC())
    urow("mt_c_table_min", P.TABLE_MIN())
    urow("mt_c_sels_len", P.sels_len())
    urow("mt_c_sels_res", P.SELS_RES())
    urow("mt_c_sels_cnt", P.SELS_CNT())
    urow("mt_c_slots_stride", P.SLOTS_STRIDE())
    urow("mt_c_slots_min", P.SLOTS_MIN())
    urow("mt_c_apple9", P.APPLE9())
    urow("mt_c_slot_pending", P.SLOT_PENDING())
    urow("mt_c_slot_cbuf", P.SLOT_CBUF())
    urow("mt_c_slot_stride4", P.SLOT_STRIDE4())
    urow("mt_c_kbuf_ix", P.KERNEL_BUF_IX())
    urow("mt_c_metal_apple", METAL_APPLE())
    urow("mt_c_metal_mac", METAL_MAC())
    urow("mt_c_all_syms", ALL_SYMS())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_sel()
    b : Unit <- t_compiler()
    c : Unit <- t_init()
    d : Unit <- t_run()
    e : Unit <- t_geometry()
    f : Unit <- t_alloc()
    g : Unit <- t_icb()
    h : Unit <- t_sync()
    i : Unit <- t_const()
    j : Unit <- t_seam()
    k : Unit <- t_wired()
    IO.print("mt-done=1")

# ===========================================================================
# THE MUTATION TABLE. Seventy-two entries over a 432-row gate, and every number
# below is the HARNESS'S OUTPUT, not an estimate:
# `.venv/bin/python .agents/slop/mt_mutate.py <this file>` applies one edit to a
# scratch copy BESIDE THIS FILE, runs the INTERPRETED lane, and diffs the row
# NAMES. It REFUSES a mutation whose `old` text does not match exactly once and
# prints `PATTERN MATCHES Nx -- NOT RUN`, because a table entry whose target line
# was hand-edited would otherwise read as "0 rows moved" and that is exactly the
# reading a blind spot must not be confused with. `.agents/slop/mt-table.py`
# rewrites the table below from the harness's output and REFUSES an id with no
# prose, so a row with an empty last column cannot happen.
#
# The useful column is "rows MOVED", because a mutation that moves nothing
# measures what this gate does NOT see.
#
# ---------------------------------------------------------------------------
# THREE MOVE NOTHING, and only ONE of them is a control.
#
#  * M14 and M14c add a `+` to a parameter and nothing else. They cannot change
#    behaviour and are run BECAUSE "the edit that adds only a `+`" is the one an
#    LLM would most plausibly make by accident. M14b and M14e are the same two
#    edits made real, and they move 9 and 11 rows.
#  * M41 is the comment-only CONTROL. A table with no row that CANNOT move is a
#    table of coincidences.
#
# ---------------------------------------------------------------------------
# THREE moved nothing on the first run and were fixed with a fixture, which is
# the whole point of running the harness rather than reading the code:
#
#  * M49 dropped :70's ENDT conjunct and nothing moved, because every fixture fed
#    `ccompile.ok` a good pair and both magics are CONSTANTS -- the check was
#    asked a question it had been told the answer to. `mt_cb_badtail` and
#    `mt_cb_badhead` are the negative halves it needed.
#  * M51 dropped the scan's last entry and nothing moved, because `mt_sync_scan_idx`
#    read `sync_starts` DIRECTLY and `sync_starts` is unchanged by a wrong count.
#    The row has to go through `dev.sync_scan`, at two sizes.
#  * M54 deleted `str_list_eq`'s ELEMENT walk and nothing moved, because the two
#    table rows compare `handles()`/`P.selectors()` against a COPY OF THE SAME TABLE
#    INSIDE THIS FILE -- the lengths always agree. `mt_tbl_reorder` (two names
#    swapped) and `mt_tbl_wrong` (one name changed) are the negatives a length
#    check cannot see, and they are also the rows that make the positive pair worth
#    anything.
#
# ---------------------------------------------------------------------------
# AND THE CONSTANT SWEEP, which is the table's most important row and is not a
# single edit: `mt_mutate.py` adds 1 to EVERY numeric constant def, one at a time.
# 111 defs, 30 whose +1 moves nothing -- and all 30 are the `CALL_*` tag
# space (29) plus `P.MTL_DEV` (a fixture device index). Every other constant in the
# file is now seen by at least one row, which was NOT true of eleven of them
# before this session because they had no reader at all.
#
# THE thirty are a genuine blind spot and must not be closed with rows that encode
# the bug. The `CALL_*` NUMBERS are a port-internal tag space: Python has no
# counterpart for "this call kind is 12", so a row printing the tag would only ever
# restate the assignment. What protects them runs the OTHER way -- `mt_constmap.py`
# checks each tag NAME against the `ops_metal.py` line that carries the selector
# the port claims (the `CLASS_BLACKWELL_COMPUTE_A`-holding-`_B` failure mode) and
# checks the tag set for density (`0..37 n=38 DENSE=True`). `P.MTL_DEV` is a fixture:
# it must be the device index `device.bend`'s `Bn.dev` compares against, and the
# right test is a row about `mem_used`, which is `device.bend`'s to write.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | csrc_pad drops the `- n` | 12  mt_pad1,mt_pad2,mt_pad3,mt_pad4,mt_pad5,mt_pad7 |  mt_pad1,mt_pad2,mt_pad3,mt_pad4,mt_pad5,mt_pad7 | | :62's `round_up(len+1,4) - len`. A real port bug this gate found: the first version printed 4 where CPython says 3, and `mt_psrc7`/`mt_req7` moved with it. |
# | M2 | metal_version's `>= 13` becomes `>= 14` | 3  mt_params2,mt_ver12,mt_ver13 |  mt_params2,mt_ver12,mt_ver13 | | :56's four-arm ladder, and the 13/14 boundary. |
# | M3 | sel_ix cannot say `no name matched` | 34  mt_init_sels_only,mt_nsstring_sel,mt_pipe_sels,mt_poll_sels,mt_resid_add_sels,mt_resid_del_sels |  mt_init_sels_only,mt_nsstring_sel,mt_pipe_sels,mt_poll_sels,mt_resid_add_sels,mt_resid_del_sels | | the reverse lookup at all. Thirty-four rows, because every selector is looked up by name. |
# | M4 | q.items appends the vars BEFORE the globals | 6  mt_end_2buf1var,mt_exec_nbytes_c,mt_items_2_1,mt_items_3_2,mt_layout_2buf1var,mt_layout_at256 |  mt_end_2buf1var,mt_exec_nbytes_c,mt_items_2_1,mt_items_3_2,mt_layout_2buf1var,mt_layout_at256 | | :111's `[globals] + [vals]`. A REAL PORT BUG: `List.append` is `xs ++ ys`, so the first version built `[4,8,8]`. |
# | M5 | q.end's `default` is `at`, not `at + 8` | 2  mt_end_empty,mt_end_empty0 |  mt_end_empty,mt_end_empty0 | | :113's `default=off + 8`, and ONLY the two empty-rows fixtures reach it. |
# | M5b | q.end's `default` is `at + 16` | 2  mt_end_empty,mt_end_empty0 |  mt_end_empty,mt_end_empty0 | | the same two rows, so M5 is not a one-value accident. |
# | M6 | q.exec.off aligns to 64, not 256 | 20  mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree,mt_icb_cmd_order |  mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree,mt_icb_cmd_order | | :112's 256-byte argument alignment. |
# | M7 | run.encoder before run.cmdbuf | 4  mt_run_one_storevals,mt_run_order,mt_run_sels,mt_run_two_storevals |  mt_run_one_storevals,mt_run_order,mt_run_sels,mt_run_two_storevals | | :139 before :140 -- the FIRST TWO calls of every `run`. |
# | M8 | run.pipeline.at is inverted | 16  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n,mt_run_one_exec |  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n,mt_run_one_exec | | :146's arm, and the call count behind it. |
# | M9 | run.execute dispatches `first`, not `count` | 7  mt_run_disp_args,mt_run_exec_args,mt_run_one_exec,mt_run_order,mt_run_setpipe_args,mt_run_sym_args |  mt_run_disp_args,mt_run_exec_args,mt_run_one_exec,mt_run_order,mt_run_setpipe_args,mt_run_sym_args | | :151's `withRange:` length. Seven rows, and `mt_run_order` is one of them -- the pattern spells the argument. |
# | M10 | run.slot0 and run.slot1 swapped | 4  mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_storeslots,mt_run_two_storevals |  mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_storeslots,mt_run_two_storevals | | :159 before :160. Four rows and not one, because the two stores differ in BOTH their slot and their value. |
# | M11 | dev.apple9's `or` becomes an `and` | 17  mt_apple9_apple8,mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n |  mt_apple9_apple8,mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n | | :146's DISJUNCTION. Only `mt_apple9_apple8` of the seventeen is ABOUT the disjunction; the other sixteen are the trace, because the arm gates two of `run`'s thirteen calls. |
# | M12 | runs2's FIRST run is `last` | 3  mt_run_two_calls,mt_run_two_signal,mt_run_two_storevals |  mt_run_two_calls,mt_run_two_signal,mt_run_two_storevals | | :167's `last=False`, and the fact that `encodeSignalEvent:value:` then appears once. |
# | M13 | runs2 does NOT thread the trace | 5  mt_run_two_calls,mt_run_two_commit,mt_run_two_stores,mt_run_two_storeslots,mt_run_two_storevals |  mt_run_two_calls,mt_run_two_commit,mt_run_two_stores,mt_run_two_storeslots,mt_run_two_storevals | | `h` is the ACCUMULATOR through both `run` calls. A port that gave each `run` a fresh trace loses the first run's thirteen calls, and five rows say so. |
# | M14 | q.submit.at's no-stamps arm builds the STAMPS path | 0 | a mutation that cannot change behaviour, run because "the edit that adds only a `+`" is the one an LLM would most plausibly make by accident. It moves nothing, and the table is honest about that. |
# | M14b | q.submit.at's no-stamps arm builds the STAMPS path (real) | 9  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_order,mt_run_res_calls |  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_order,mt_run_res_calls | | :166's `if not self.stamps`. |
# | M14c | q.submit.at's many arm is selected when NOT many | 0 | see M14. |
# | M14e | q.submit.at's many arm is selected when NOT many (real) | 11  mt_has_late2,mt_run_one_commit,mt_run_one_exec,mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_calls |  mt_has_late2,mt_run_one_commit,mt_run_one_exec,mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_calls | | the three-way tail, and `mt_run_one_*` is in the eleven because the one-run fixture takes the `else` arm. |
# | M14d | q.submit.runs2 drops its SECOND run | 7  mt_has_late2,mt_run_two_calls,mt_run_two_commit,mt_run_two_signal,mt_run_two_stores,mt_run_two_storeslots |  mt_has_late2,mt_run_two_calls,mt_run_two_commit,mt_run_two_signal,mt_run_two_stores,mt_run_two_storeslots | | :168. Seven rows, and `mt_has_late2` is one of them -- a pattern that only occurs in the SECOND run. |
# | M15 | P.Tr.emit.go drops the `raise` guard | 6  mt_alloc_refused_calls,mt_icb_local_bad_calls,mt_icb_local_bound,mt_icb_refuse_calls,mt_init_refused_calls,mt_pipe_librefuse_calls |  mt_alloc_refused_calls,mt_icb_local_bad_calls,mt_icb_local_bound,mt_icb_refuse_calls,mt_init_refused_calls,mt_pipe_librefuse_calls | | THE RAISE. Every refusal TRUNCATION row, and only those. |
# | M16 | P.Tr.has.go's fuel is the PATTERN length | 6  mt_alloc_order,mt_has_late,mt_has_late2,mt_icb_cmd_order,mt_icb_local_pipeline,mt_icb_order |  mt_alloc_order,mt_has_late,mt_has_late2,mt_icb_cmd_order,mt_icb_local_pipeline,mt_icb_order | | THE MATCHER. `mt_has_late`/`mt_has_late2` exist for this and are the two rows the WebGPU template's M23 had to add. |
# | M17 | pipeline emits setComputeFunction BEFORE newFunctionWithName | 1  mt_pipe_order |  mt_pipe_order | | :247's argument-before-callee order. One row, and it is LOCALISED. |
# | M17b | pipeline drops the NSString as well | 8  mt_icb_calls,mt_icb_librefuse_calls,mt_icb_local_bad_calls,mt_icb_local_ok_calls,mt_icb_typerefuse_calls,mt_pipe_calls |  mt_icb_calls,mt_icb_librefuse_calls,mt_icb_local_bad_calls,mt_icb_local_ok_calls,mt_icb_typerefuse_calls,mt_pipe_calls | | :247's NSString. `pipe_pat` compares the WHOLE list, so a missing call in the MIDDLE is a length mismatch, and eight rows move because every ICB builds a pipeline per command. |
# | M18 | mark_resident runs BOTH paths | 1  mt_resid_excl_commits |  mt_resid_excl_commits | | :229-237's mutual exclusion. One row, and it is the commit COUNT. |
# | M19 | setMaxKernelBufferBindCount is 2 | 2  mt_icb_binds,mt_icb_order |  mt_icb_binds,mt_icb_order | | :256's ONE bind, which is the number cstyle's `[[buffer(0)]]` and this file have to agree on. |
# | M20 | icb_max drops the `max(..., 1)` | 1  mt_icb_max0 |  mt_icb_max0 | | :257's `max(len(cmds), 1)`. |
# | M21 | local_ok's `>` becomes `>=` | 1  mt_local_eq |  mt_local_eq | | :262's STRICT comparison; `mt_local_eq` is the only fixture at the boundary. |
# | M22 | sync_count uses round_up, not ceildiv | 8  mt_sync_n13,mt_sync_n17,mt_sync_n21,mt_sync_n9,mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_n13,mt_sync_n17,mt_sync_n21,mt_sync_n9,mt_sync_scan_calls,mt_sync_scan_calls21 | | `range(5, size, 4)`. A REAL PORT BUG: `round_up(4, 4)` is 4 and `range(5,9,4)` has one element. |
# | M23 | sync_range CONSES and reverses | 4  mt_sync_idx17,mt_sync_idx21,mt_sync_scan_idx,mt_sync_scan_idx21 |  mt_sync_idx17,mt_sync_idx21,mt_sync_scan_idx,mt_sync_scan_idx21 | | the append-vs-cons order. `mt_sync_idx5` is the one-element fixture that is BLIND to it, which is why `mt_sync_idx17` exists. |
# | M24 | sync.one's guard is inverted | 7  mt_sync_guard_args,mt_sync_guard_hits,mt_sync_guard_miss,mt_sync_guard_sels,mt_sync_noscan_calls,mt_sync_scan_calls |  mt_sync_guard_args,mt_sync_guard_hits,mt_sync_guard_miss,mt_sync_guard_sels,mt_sync_noscan_calls,mt_sync_scan_calls | | :279's `slots[start] and not slots[start + 2]`. |
# | M25 | the autorelease pool PUSHES before it POPS | 1  mt_pool_order |  mt_pool_order | | :284-285's pop-then-push. |
# | M26c | dev.pipeline.f keeps the COMPILER's magic check | 17  mt_icb_bar,mt_icb_bind,mt_icb_calls,mt_icb_cmd_order,mt_icb_conc,mt_icb_kbuf_args |  mt_icb_bar,mt_icb_bind,mt_icb_calls,mt_icb_cmd_order,mt_icb_conc,mt_icb_kbuf_args | | A real port bug: `P.ccompile.ok(0, 0, ...)` compares a library's head against MTLB/ENDT and so EVERY pipeline refused. |
# | M26e | icb: every command is set up BEFORE the next handle is taken | 2  mt_icb_cmd_order,mt_icb_order |  mt_icb_cmd_order,mt_icb_order | | :259 and :260 are TWO SEPARATE LOOPS. |
# | M28 | icb_hdr_word divides by 4, not 8 | 2  mt_icb_order,mt_icb_storeslots |  mt_icb_order,mt_icb_storeslots | | :266's `view(fmt='P.Q')[header // 8]`. Found as a blind spot -- the row was missing and `mt_icb_storeslots` is the fix. |
# | M29 | icb_size drops the `+ 24` header | 3  mt_icb_nbytes,mt_icb_size,mt_icb_sizes_agree |  mt_icb_nbytes,mt_icb_size,mt_icb_sizes_agree | | :129 and :253 must spell the SAME number. |
# | M30 | fam_scan is FIRST-wins, not LAST-wins | 8  mt_fam_apple8,mt_fam_apple8_9,mt_fam_apple9,mt_fam_apple9_family,mt_fam_apple_first,mt_fam_mac |  mt_fam_apple8,mt_fam_apple8_9,mt_fam_apple9,mt_fam_apple9_family,mt_fam_apple_first,mt_fam_mac | | :213's `next(filter(..., reversed(...)))` is a LAST-wins over the dict. |
# | M31 | arch_of drops 5 characters, not 12 | 3  mt_arch_slice,mt_arch_slice_mac,mt_init_arch |  mt_arch_slice,mt_arch_slice_mac,mt_init_arch | | :215's `[12:]`. |
# | M32 | dev.arch.apple's `or` becomes an `and` | 5  mt_arch_or_apple,mt_arch_or_fallback,mt_init_arch,mt_init_fam,mt_init_order |  mt_arch_or_apple,mt_arch_or_fallback,mt_init_arch,mt_init_fam,mt_init_order | | :215's `or` is a FALLBACK, not a union. |
# | M33 | csrc_padded is off by one | 6  mt_psrc238,mt_psrc4,mt_psrc7,mt_req1,mt_req238,mt_req7 |  mt_psrc238,mt_psrc4,mt_psrc7,mt_req1,mt_req238,mt_req7 | | `len(src_padded)`. |
# | M34 | hdr_pipe is `n + 2`, not `n + 1` | 3  mt_hdr_pipe0,mt_hdr_pipe1,mt_run_order |  mt_hdr_pipe0,mt_hdr_pipe1,mt_run_order | | :148's `header.index(1 + n + r)`. |
# | M35 | selreg starts at word 0, not word 5 | 1  mt_sels_sel_args |  mt_sels_sel_args | | :224's five handles before the thirteen selectors. |
# | M36 | q.dims reads bit i+1, not bit i | 2  mt_dims_mixed,mt_dims_one |  mt_dims_mixed,mt_dims_one | | :121's `tuple(1 if isinstance(d, UOp) else int(d) for d in dims)` and the mask's bit order. |
# | M37 | alloc.of asks for contents BEFORE gpuAddress | 1  mt_alloc_order |  mt_alloc_order | | :179's three arguments, evaluated left to right. |
# | M38 | icb_cmds retains BEFORE it indexes | 2  mt_icb_cmd_order,mt_icb_order |  mt_icb_cmd_order,mt_icb_order | | :259's `indirectComputeCommandAtIndex(i).own()`. Found as a blind spot -- the two COUNT rows cannot see a swap and `mt_icb_cmd_order` is the fix. |
# | M39 | q.exec.sizes.at is unconditional | 28  mt_exec_nbytes_c,mt_exec_nrows,mt_exec_nrows_s,mt_hdr_word,mt_header,mt_header_agree |  mt_exec_nbytes_c,mt_exec_nrows,mt_exec_nrows_s,mt_hdr_word,mt_header,mt_header_agree | | :117's `if any(isinstance(d, UOp) for d in dims)`. |
# | M40 | dev.queue_max is 512 | 3  mt_c_queue_max,mt_init_queueargs,mt_queue_max |  mt_c_queue_max,mt_init_queueargs,mt_queue_max | | :200's 1024. |
# | M41 | a comment-only edit -- THE CONTROL | 0 | a table with no row that CANNOT move is a table of coincidences. |
# | M42 | the seam: `cc_error_ok` tests `err == 2` instead of `err == 0` | 4  mt_cb_bad2,mt_cb_bad_refused,mt_cb_ok0,mt_cb_ok_live |  mt_cb_bad2,mt_cb_bad_refused,mt_cb_ok0,mt_cb_ok_live | | :47's `if error == 0`. Four rows and not one, because inverting it also inverts `mt_cb_ok_live` -- which is what makes this a test of the arm rather than of the constant. |
# | M43 | the seam: the error arm does NOT refuse | 1  mt_cb_bad_refused |  mt_cb_bad_refused | | the error arm's RAISE. One row, and one is right: a refusal that still made both calls is exactly what `mt_cb_bad_calls` exists to distinguish from skipping them. |
# | M44 | the seam: the error arm refuses WITHOUT calling | 2  mt_cb_bad_calls,mt_cb_ok_calls |  mt_cb_bad_calls,mt_cb_ok_calls | | the error arm's ORDER -- refuse before the call rather than after. Two rows, and they are the two COUNT rows, so the table records that the port calls first and refuses second. |
# | M45 | the seam: `P.REPLY_HDR` is 100, the header the SYNTHETIC fixtures guessed | 2  mt_liboff_host,mt_reply_hdr |  mt_liboff_host,mt_reply_hdr | | :50's header sum, on the value a REAL reply carried. This is the row that did not exist before this session: `mt_liboff42` and `mt_liboff00` were synthetic and 104 was unreachable. |
# | M46 | the seam: `P.REPLY_LEAD` is MTLB -- the two blobs confused | 2  mt_reply_is_mtlb,mt_reply_lead |  mt_reply_is_mtlb,mt_reply_lead | | THE two blobs. Printing MTLB as the reply's leading word moves `mt_reply_is_mtlb` to True and the row then says the un-sliced reply carries the magic, which it does not. `nv_query_litter` in two rows. |
# | M47 | the seam: `P.CB_ERR_COMPILE` is 1 | 1  mt_err_compile |  mt_err_compile | | the compiler's error code. One row, because `P.CB_ERR_COMPILE` is also `cc_error_ok`'s input and M42 covers the consumer. |
# | M48 | the seam: `P.MACOS_MAJOR` is 15, so the host compiles with metal3.1 | 2  mt_macos_major,mt_ver_host |  mt_macos_major,mt_ver_host | | :55-56's ladder at the HOST's version, so the four-way ladder is checked at the value it will actually be asked about. |
# | M49 | the seam: the magic check drops the ENDT half | 1  mt_cb_badtail |  mt_cb_badtail | | :70's ENDT conjunct. THIS moved 0 ROWS before the fixture. Every fixture fed `ccompile.ok` a good pair, and both magics are CONSTANTS, so the check was only ever asked a question it had been told the answer to. `mt_cb_badtail` and `mt_cb_badhead` are the negative halves. |
# | M50 | the wiring: `dev.sync.go` drops the call and keeps walking | 2  mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_scan_calls,mt_sync_scan_calls21 | | :276-281's walk: drop the per-entry work and keep walking. Two rows and both are COUNT rows at two sizes, which is the fixture M51 needed. |
# | M51 | the wiring: `dev.sync_scan` misses the LAST entry | 2  mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_scan_calls,mt_sync_scan_calls21 | | the scan losing its LAST entry. ALSO 0 BEFORE the fixture: `mt_sync_scan_idx` read `sync_starts` DIRECTLY, so the row never went through the def under repair, and `sync_starts` is unchanged by such a bug. `mt_sync_scan_calls21` is the second size. |
# | M52 | the wiring: `dev.sync_scan` ignores the guard | 1  mt_sync_noscan_calls |  mt_sync_noscan_calls | | the guard, through the scan rather than through `sync.one`. One row, the guarded arm's count. |
# | M53 | the wiring: `icb_keep` adds ZERO -- :267 is entered and not counted | 1  mt_nics1 |  mt_nics1 | | :267's weak-dictionary count. One row, and adding ZERO is the mutation that matters: the entry is created and the count does not move, which is a bug an `nics`-reading gate would miss. |
# | M54 | the wiring: `str_list_eq` compares lengths only | 2  mt_tbl_reorder,mt_tbl_wrong |  mt_tbl_reorder,mt_tbl_wrong | | `str_list_eq`'s ELEMENT comparison. ALSO 0 BEFORE the fixture, and for a worse reason than M49: `mt_tbl_handles` and `mt_tbl_sels` compare the table against a copy of the table INSIDE this file, so the lengths always agree and deleting the element walk changed nothing. `mt_tbl_reorder` (same length, two names swapped) and `mt_tbl_wrong` (same length, one name changed) are the two negatives a length check cannot see. |
# | M54b | the wiring: `str_list_eq` returns True unconditionally | 2  mt_tbl_reorder,mt_tbl_wrong |  mt_tbl_reorder,mt_tbl_wrong | | the same walk made unconditional. Two rows and not four, because the two POSITIVE rows cannot tell. |
# | M55 | the constants: `P.ARG_ALIGN` is 128 | 21  mt_c_arg_align,mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree |  mt_c_arg_align,mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree | | :112's 256. Twenty-one rows and one of them is `mt_c_arg_align`; the other twenty are the layout, the header word and the ICB's byte offset, which is the composability claim. |
# | M56 | the constants: `P.SYNC_START` is 4 | 14  mt_c_sync_start,mt_sync_idx17,mt_sync_idx21,mt_sync_idx5,mt_sync_n13,mt_sync_n17 |  mt_c_sync_start,mt_sync_idx17,mt_sync_idx21,mt_sync_idx5,mt_sync_n13,mt_sync_n17 | | :278's scan start. Fourteen rows: the profile scan's count, its index list at three lengths, AND the new `mt_sync_scan_*` pair. |
# | M57 | the constants: `P.MTLB_MAGIC` is byte-swapped | 2  mt_c_mtlb,mt_mtlb |  mt_c_mtlb,mt_mtlb | | the magic's ENDIANNESS. Two rows and both would read as plausible -- this is the failure mode the seam's two-blob rows exist to make visible. |
# | M58 | the constants: `P.DIM_WORDS` is 3 | 1  mt_c_dim_words |  mt_c_dim_words | | `:116`'s `len(dims)`. One row, and one is a FINDING: `P.DIM_WORDS` feeds nothing but the fixture's symbolic mask, so before `mt_c_dim_words` existed it was invisible. `mt_c_all_syms` catches the mask. |
# | M59 | the constants: `ALL_SYMS` is 32, a NON-ALL symbolic mask | 2  mt_c_all_syms,mt_dims_all |  mt_c_all_syms,mt_dims_all | | (1 << len(dims)) - 1, on a NON-ALL mask. Two rows, and `mt_dims_all` is the one that would have caught a fixture that stopped being all-symbolic. |
# | M60 | the constants: `P.SEL_SIGNALEDVALUE` is 16 | 2  mt_c_sel_sigval,mt_poll_sels |  mt_c_sel_sigval,mt_poll_sels | | one of the eighteen selector indices. Two rows, and it is the LAST one, so a table that dropped its tail would still agree on the other seventeen -- which is why `mt_sel_n` counts. |
# | M61 | the constants: `P.HDR_ICB` is 1 -- the ICB word is 0 | 2  mt_c_hdr_icb,mt_hdr_icb |  mt_c_hdr_icb,mt_hdr_icb | | the ICB's word index. Two rows, and the `mt_hdr_icb` half is the one that is about the header layout rather than the trace. |
#
# SEVEN of these mutations found a real bug in this port, and every one of them
# was a DIFFERENT KIND of mistake --
#
#   M1/M33   an arithmetic omission (a missing subtraction)
#   M4       a reversed concatenation (`List.append` is `xs ++ ys`)
#   M22      the wrong helper (`round_up` is not `ceildiv`)
#   M23      a reverse applied to a fold that appends
#   M26      a predicate chained off the wrong rule
#   M26c     the wrong function called (the compiler's check on the pipeline)
#   M26d     an accumulator that did not advance on a miss
#
# and NOT ONE of them was a type error or a proof failure. `--check-only` said
# ALL PROOFS CHECK through all seven, which is the argument for the gate and the
# argument for generating its expectations from CPython rather than by hand.
#
# M3 (thirty-four rows) and M39 (twenty-eight) are the two widest, and neither is
# a shared bug: M3 moves every row that LOOKS A SELECTOR UP BY NAME, because
# `sel_ix` is called on both sides of the trace, and M39 moves every row that
# depends on `nbytes`, which is what :117's `if` decides. M6 (twenty) and M26c
# (seventeen) are the next two and each is one constant or one call under a
# whole subtree.
#
# M26b WAS a blind spot and it was about the source, NOT the gate. M1's pattern
# was `UPat(Ops.PARAM, tag="slots", name="b")` and its body was
# `ctx.new_slots(b.max_numel()) if b.max_numel() > 4 else None`; `device.py:404`'s
# second rule was `UPat(Ops.PARAM, name="b")` -> a program Buffer, and it fired
# on EVERY node M1 fired on. So whenever M1 fired, `device.bend`'s rule 1 gave
# the same ANSWER (2) and the same ARENA GROWTH (one Buffer). Adding
# `tag="mtl_sel"` to M1's predicate changed nothing observable, for any input.
# The only difference M1 could make was to fire LESS -- which is what the `> 4`
# guard and M26 showed. Metal's first `pm_bufferize` rule was REDUNDANT with
# `Compiled`'s second one, on every input.
#
# AND THEN UPSTREAM DELETED BOTH. At the pin `ops_metal.py` has NO
# `pm_bufferize` at all, `new_slots` is GONE, and their replacements are the
# LINK mechanism -- `Compiled.link_bufs |= {to_name(self.device, "handles"):
# lambda b: self.handles}` and `MetalDevice.link_buffer` -- neither of which
# this file ports. So the whole `pm_bufferize` port is GONE from here too, and
# with it the seventeen rows that measured it.
#
# WHAT this gate still does not see, and it is a short list:
#
#  1. THE ObjC ARGUMENTS THEMSELVES. `P.Tr` records the call, the selector and ONE
#     number. `useResources:count:usage:` has three arguments and the port can
#     only read the count; `setKernelBuffer_offset_atIndex` has a buffer, an
#     offset and an index and the port can only read the offset; the dispatch's
#     MTLSizes are built by `mtl_size` and read by `mt_size_*`, and NOTHING checks
#     that the MTLSize `icb_disp` emits is the one `mtl_size.l` built -- the two
#     are one line apart and a swap moves nothing.
#  2. THE `getaddr` UOps THEMSELVES. `q.items` knows a global is EIGHT bytes
#     because `getaddr` is uint64 (MEASURED), and the ADDRESS each buffer
#     contributes is a graph write -- WALL 5. `mt_items_2_1` pins the WIDTHS and
#     nothing pins the VALUES.
#  3. THE COMPILER'S REQUEST BYTES. :62-63 are gated as LENGTHS
#     (`mt_psrc7`, `mt_ppar109`, `mt_req7`, `mt_qq`) and the sixteen bytes of
#     `struct.pack('<QQ', ...)` are the seam's. The MTLB/ENDT magics are gated
#     as NUMBERS (`mt_mtlb`, `mt_endt`) and the reply's bytes are not.
#  4. `checked`'s MESSAGE (:26). The port keeps the CALL and drops the text,
#     because the text is `localizedDescription` and there is nothing to decide
#     about it.
#  5. `int(cb.GPUStartTime() * 1e9)` (:281) -- no F64, so `dev.sync` records the
#     THREE calls and the two slot indices and not the nanoseconds.
#  6. `pm_encode` and `pm_lower` (:189, :192). Both are `UOp` MATCHERS whose
#     bodies build graphs, and the port carries neither. `pm_bufferize` WAS
#     gated because its answers were Buffers and Buffers are the port's
#     subject; upstream DELETED it, so it is not gated at all any more.
# ===========================================================================


# ===========================================================================
# THE LANES. `mt_diff.py` runs FIVE and compares them, and the number that
# matters is not "green" -- it is how many rows each oracle ANSWERS.
#
#   interpreted  the file, `bin/bend <file>`
#   native       `bin/bend <file> -o x && x`, and it must be BYTE IDENTICAL
#   graph        `.agents/slop/mt_rows.py`, the original 169-row graph oracle
#   const        `.agents/slop/mt_constmap.py --rows`, 72 rows, ONE PER CONSTANT
#                with a numeric authority -- `autogen/metal.py` by getattr,
#                `ops_metal.py` by CPython's `ast`, a real `MetalDevice` for the
#                family and the `sels` Buffer, and a REAL KERNEL LAUNCH for
#                `P.DIM_WORDS` and `ALL_SYMS`
#   seam         `.agents/slop/mt_seam_rows.py`, the REAL
#                `MTLCodeGenServiceBuildRequest` fired through Apple's block ABI
#                with an instrumented callback, for `:42-71`
#
# 432 rows, `ALL PROOFS CHECK`, interpreted == native, 253 oracle rows answered,
# 0 disagreements, 6 oracle-only and 173 Bend-only. The oracle-only six are
# facts about a real MTLB that the port has no way to HOLD because it never sees
# the bytes (`mt_mtlb_ret`, `mt_endt_ret`, `mt_ret_bytes`, `mt_ret_is_mtlb`) and two
# pre-existing `*_and` fixtures.
#
# The `const` lane is the answer to `ops_nv.bend`'s 33 of 219. That file's gate
# tested graphs and its constants answered to a C header nobody read, so no number
# of rows could have found them; here the constants are ROWS, diffed against
# authorities produced by a different program from a different source. A wrong
# constant is now a `DIFFER`, not a coincidence.
