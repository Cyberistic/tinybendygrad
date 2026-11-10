# gates/ops_cpu-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_cpu.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_cpu.bend as P
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/runtime/support/compiler_cpu.bend as CC

# ops_cpu.py:40, `PROT_READ|PROT_WRITE|PROT_EXEC` == 1|2|4.
def cpu.prot_rwx() -> U32: 7

# ops_cpu.py:81, `wait_timeout_ms = 30000` -- the INT. `Compiled` has 30000.0
# and this line overwrites it with an int, which is why the row is named
# `cpu_wait_timeout_int`.
def cpu.wait_timeout_ms() -> U32: 30000

def cpu.link_libs_n(osx: Bool, win: Bool) -> U32:
  U32.from_nat(List.length(&2, String, P.cpu.link_libs(osx, win)))


# ops_cpu.py:21, `libc.ELFMAG.encode()` == b'\x7fELF'. WALL 2 says four bytes
# cannot be compared in Bend, so they are NAMED rather than spelled as a
# comparison: the port carries the ANSWER and this is the auditable statement of
# what the answer means.
def cpu.elfmag() -> String: "7f454c46"

def seq(+t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)
def ncalls(k: U32, +t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
# ops_cpu.py:21, `_load` -- `lib if lib[:4] != libc.ELFMAG.encode() else
# jit_loader(lib, base=base, link_libs=[self.libm, self.rt_lib])`. The DECISION
# is WALL 2's Bool and the two arms are two trace tags. `link_libs` is
# `[self.libm, self.rt_lib]` -- TWO libraries, and both come from the class
# attribute at :19, which is why `cpu_rt_lib_name` is ported even though the
# loader itself is not.
def cpu.uses_jit_loader(elf: Bool) -> Bool: elf

# :23-56 -- `__init__`. THREE arms, MUTUALLY EXCLUSIVE: the remote branch (:26),
# the win32 branch (:27-36) and the posix branch (:38-56), and `local` is "none
# of the first two". A `P.Prog` is `Data`, so each arm's growth is a copy and
# `Bool.pick` picks between finished values rather than between effects -- which
# is the one place this file's `Bool.pick` use is not reading like the others.
def prog.init(+nm: String, +sig: List<&2, U32>, +lvp: Bool, +elf: Bool, +osx: Bool,
              +rt: Bool, +remote: Bool, +win: Bool, liblen: U32) -> P.Prog:
  +p0: P.Prog = P.Prog.of(nm, sig, lvp, elf, osx, rt, liblen)
  +p1: P.Prog = Bool.pick(P.Prog, remote, P.prog.remote.at(lvp, p0), p0)
  +p2: P.Prog = Bool.pick(P.Prog, win, P.prog.win.at(lvp, p1), p1)
  P.prog.posix.at(Bool.not(Bool.or(remote, win)), p2, lvp, elf, osx, rt)

# helpers.py:81, `data64_le(data) = (data & 0xFFFFFFFF, data >> 32)`. The
# address is a 64-bit number (WALL 1), so the port carries the 32-bit LOW word
# it can compute and answers the high word as the carry out of `lo + 12`, which
# is the only part of the pair that is nonzero for an address near 4 GiB.
def lvp.d64(lo: U32) -> List<&2, U32>: [lo, 0]

# :69, `(len(bufs)+len(vals))*2` -- the third header word. THE `*2` is because
# the val slots are 8 bytes each while `iter_sig` is handed `len(bufs)*8`, so
# the header counts WORDS-PAIRs and the base counts BYTES. `lvp_third` and
# `lvp_slots` disagree by a factor of four and that disagreement is the row.
def lvp.third(nbufs: U32, nvals: U32) -> U32: U32.mul(P.prog.nargs(nbufs, nvals), 2)

# :69-70 -- the val slot offsets, `TinyELF.iter_sig(self.signature[-len(vals):],
# len(bufs)*8)`, as offsets into `lvp_args`. The `[-len(vals):]` slice and the
# `len(bufs)*8` base are both decisions and both are rows. `D.isig.go` is
# device.bend's offset-carrying walk of the itemsize list, so the tail slice is
# this file's and the base is the second argument -- see OWED BACK, item 1.
def lvp.slots(+sig: List<&2, U32>, +nvals: Nat, nbufs: U32) -> List<&2, U32>:
  P.cn_walk(Nat.sub(List.length(&2, U32, sig), nvals),
          List.drop(&2, U32, sig, Nat.sub(List.length(&2, U32, sig), nvals)),
          U32.mul(nbufs, 8), Nil{})

# :70, `12+off` -- where a val's BYTES go. Not the bytes (WALL 3), the offset.
def lvp.at(off: U32) -> U32: U32.add(12, off)

# :73, `return float(...) * 1e-6 if wait else None`. The ANSWER'S SHAPE is the
# decision: with `wait` there is a number and without it there is nothing. The
# number itself is two clock reads, so the VALUE is the seam's and only the
# shape is ported.
def prog.ret_is_none(wait: Bool) -> U32: Bool.pick(U32, wait, 0, 1)

def prog.call(+p: P.Prog, nbufs: U32, nvals: U32, wait: Bool, remote: Bool) -> P.Prog:
  P.prog.call.at(p, nbufs, nvals, wait, remote)

def prog.del(remote: Bool, win: Bool, +p: P.Prog) -> P.Prog: P.prog.del.at(remote, win, p)

# :86-92 -- `__init__` as the step list it is. The `if` comes FIRST, so the
# connect happens before `super().__init__` and therefore before the arch
# string exists. `osx`/`win` are NOT parameters here because Python does not use
# them in `__init__` either -- they are `getenv` reads that only feed
# `CPUProgram`'s class attribute at :19, and `cpu_rt_lib_name` is that
# derivation, gated on its own.
#
# `cpu.peer_of` is called ONCE and its answer is already the post-:92 value
# (`remote_peer` on the remote arm, the inherited `head(dev)` otherwise), so
# there is no separate overwrite step to write. A `.at` wrapper that returned the
# device unchanged on both arms was written and deleted: it read as a decision
# and was not one.
def cpu.init(+dev: String, +machine: String) -> P.Cpu:
  +rm: Bool = P.cpu.is_remote(dev)
  P.Cpu{dev, P.cpu.arch_of(machine), rm, P.cpu.peer_of(rm, dev), P.cpu.renderers(),
      D.dev_id(dev),
      Bool.pick(P.Tr, rm, P.Tr.emit(P.CALL_CONNECT(), P.cpu.nparts(dev), P.Tr.of()), P.Tr.of())}

def cpu.synchronize(remote: Bool, c: P.Cpu) -> P.Cpu: P.cpu.synchronize.at(remote, c)


# THE NAMES OF THE WHOLE TRACE, in order, comma-joined. `List.append` is
# `xs ++ ys` and `String.join` is HEAD-FIRST, so the walk APPENDS; consing here
# reverses every order row at once.
def tnames(+t: P.Tr) -> String:
  String.join(P.tnames.go(List.length(&2, P.Call, P.Tr.calls(t)), P.Tr.calls(t), Nil{}), ",")

# the names of ONE tag's args, for the rows where the arg is the claim.
def targ(k: U32, +t: P.Tr) -> List<&2, U32>: P.Tr.args(k, P.Tr.calls(t))

def call_at(+t: P.Tr, i: U32) -> String: P.call_name.go(P.tat(t, i))


# --- THE GATE ROWS ----------------------------------------------------
# ===========================================================================
# THE GATE. Every row is a claim about `ops_cpu.py` / `ops_null.py`'s TEXT, or
# about a constant read out of a live CPython object, or about a value the REAL
# CPython device computed -- and every row's expectation came out of the
# `.venv/bin/python` oracle that drives `CPUDevice`, `NullDevice`, the renderer
# tables, `NullAllocator` and the actual tensor ops with `DEV=NULL`. The
# acceptance test is a BYTE DIFF of the three lanes (interpreted, native,
# CPython), not a per-row comparison.
#
# FIXTURES. One CPU program per combination of the five init facts, one CPU
# device per device string, one NULL device per `EMULATE` value, and the
# MEASURED signature and command word stream for the emulated executor. The word
# stream is the twelve `cmd` calls I captured off the real device, flattened to
# 48 words -- twelve quads.
# ===========================================================================

# THE CPU PROGRAM SIGNATURE, itemsizes only, from the MEASURED seven-entry
# signature of a real submit/kernel program: [8,1,8,1,8,1,1].
def sig7() -> List<&2, U32>: [8, 1, 8, 1, 8, 1, 1]

# an EMPTY trace, so a gate row reads ONE program call and not the init in front
# of it. Resetting AFTER the call is the mistake that emptied `cpu_call_local_*`
# the first time -- the reset took the call's own entries with it.
def Prog.reset(p: P.Prog) -> P.Prog:
  match p:
    case P.Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}:
      P.Prog{name, sig, lvp, elf, osx, rt, addr, liblen, P.Tr.reset(t)}

def fx_init(osx: Bool, rt: Bool, elf: Bool, lvp: Bool, remote: Bool, win: Bool) -> P.Prog:
  Prog.reset(prog.init("k", sig7(), lvp, elf, osx, rt, remote, win, 64))

# the init rows count the UNRESET trace, because the whole of `__init__` is what
# they are about. The CALL rows use the reset fixture.
def fx_init_raw(osx: Bool, rt: Bool, elf: Bool, lvp: Bool) -> P.Prog:
  prog.init("k", sig7(), lvp, elf, osx, rt, False{}, False{}, 64)

# THE WIN32 FIXTURE IS ITS OWN DEF rather than a `prog.init` call with a bare
# `True{}` in the seventh argument slot: `prog.init` takes SEVEN Bools and a
# literal in that position is a parse error the checker reports at the ARGUMENT
# and not at the def, which is the most expensive kind of error to diagnose.
def fx_win() -> P.Prog:
  prog.init("k", sig7(), False{}, False{}, False{}, False{}, False{}, True{}, 64)

def fx_remote() -> P.Prog:
  prog.init("k", sig7(), False{}, False{}, False{}, False{}, True{}, False{}, 64)

def init_n(osx: Bool, rt: Bool, elf: Bool, lvp: Bool) -> U32:
  P.seen(P.Prog.t(fx_init_raw(osx, rt, elf, lvp)))


# `List<&2, U32>` has no `String.join`, so the itemsizes print through the same
# `ush` fold the numeric rows use.
def ilist(+xs: List<&2, U32>) -> String: String.join(P.ush(xs, Nil{}), ",")

# --- 1: the CPU constants, :16 :28 :31 :40 :54 :78 :81 :19 ----------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    P.urow("cpu_map_jit", P.cpu.map_jit())
    P.urow("cpu_map_anon", P.cpu.map_anon())
    P.urow("cpu_map_private", P.cpu.map_private())
    P.urow("cpu_prot_rwx", cpu.prot_rwx())
    P.urow("cpu_ms_flags", P.cpu.ms_flags())
    P.urow("cpu_mem_release", P.cpu.mem_release())
    P.urow("cpu_page_xrw", P.cpu.page_xrw())
    P.urow("cpu_wr_flags", P.cpu.wr_flags())
    P.urow("cpu_wait_timeout_int", cpu.wait_timeout_ms())
    P.srow("cpu_lib_m", P.cpu.lib_m())
    P.srow("cpu_lib_objc", P.cpu.lib_objc())
    # THE LINK SET, JOINED. One row per platform cell, and the join pins the ORDER
    # as well as the contents -- `link_sym` walks it left to right, so a set with
    # the right three names in the wrong order is a different set.
    P.rlist("cpu_link_libs_00", P.cpu.link_libs(False{}, False{}))
    P.rlist("cpu_link_libs_10", P.cpu.link_libs(True{}, False{}))
    P.rlist("cpu_link_libs_01", P.cpu.link_libs(False{}, True{}))
    P.rlist("cpu_link_libs_11", P.cpu.link_libs(True{}, True{}))
    P.urow("cpu_link_libs_n", cpu.link_libs_n(True{}, False{}))
    P.srow("cpu_rtlib_00", P.cpu.rt_lib_name(False{}, False{}))
    P.srow("cpu_rtlib_10", P.cpu.rt_lib_name(True{}, False{}))
    P.srow("cpu_rtlib_01", P.cpu.rt_lib_name(False{}, True{}))
    P.srow("cpu_rtlib_11", P.cpu.rt_lib_name(True{}, True{}))
    P.srow("cpu_elfmag_hex", cpu.elfmag())
    P.srow("cpu_arch_amd64", P.cpu.arch_of("amd64"))
    P.srow("cpu_arch_aarch64", P.cpu.arch_of("aarch64"))
    P.srow("cpu_arch_x86_64", P.cpu.arch_of("x86_64"))
    P.srow("cpu_arch_arm64", P.cpu.arch_of("arm64"))
    P.srow("cpu_arch_riscv64", P.cpu.arch_of("riscv64"))
    P.srow("cpu_arch_empty", P.cpu.arch_of(""))
    P.srow("cpu_arch_AMD", P.cpu.arch_of("AMD"))

# --- 2: the device-string decisions, :88 :89 ------------------------------
def t_devname() -> IO(Unit):
  do IO<Unit>:
    P.urow("cpu_nparts_empty", P.cpu.nparts(""))
    P.row("cpu_remote_empty", P.cpu.is_remote(""))
    P.urow("cpu_nparts_CPU", P.cpu.nparts("CPU"))
    P.row("cpu_remote_CPU", P.cpu.is_remote("CPU"))
    P.urow("cpu_nparts_CPU_0", P.cpu.nparts("CPU:0"))
    P.row("cpu_remote_CPU_0", P.cpu.is_remote("CPU:0"))
    P.urow("cpu_nparts_CPU_1", P.cpu.nparts("CPU:1"))
    P.row("cpu_remote_CPU_1", P.cpu.is_remote("CPU:1"))
    P.urow("cpu_nparts_remote_host_1234", P.cpu.nparts("remote:host:1234"))
    P.row("cpu_remote_remote_host_1234", P.cpu.is_remote("remote:host:1234"))
    P.urow("cpu_nparts_remote_h_1_2", P.cpu.nparts("remote:h:1:2"))
    P.row("cpu_remote_remote_h_1_2", P.cpu.is_remote("remote:h:1:2"))
    P.urow("cpu_nparts_a_b_c_d", P.cpu.nparts("a:b:c:d"))
    P.row("cpu_remote_a_b_c_d", P.cpu.is_remote("a:b:c:d"))
    P.srow("cpu_remote_peer_remote_host_1234", P.cpu.remote_peer("remote:host:1234"))
    P.srow("cpu_remote_peer_CPU_1", P.cpu.remote_peer("CPU:1"))

# --- 3: the CPU DEVICE, :80-92 -------------------------------------------
def t_device() -> IO(Unit):
  do IO<Unit>:
    +c0: P.Cpu <- IO.pure(P.Cpu, cpu.init("", "arm64"))
    +c1: P.Cpu <- IO.pure(P.Cpu, cpu.init("CPU:1", "arm64"))
    +c2: P.Cpu <- IO.pure(P.Cpu, cpu.init("remote:host:1234", "arm64"))
    P.srow("cpu_dev_empty", P.Cpu.dev(c0))
    P.srow("cpu_arch_fixture", P.Cpu.arch(c0))
    P.urow("cpu_has_copy_queue", P.cpu.has_copy_queue())
    P.srow("cpu_peer_local", P.Cpu.peer(c0))
    P.urow("cpu_dev_id_1", P.Cpu.dev_id(c1))
    P.srow("cpu_peer_cpu1", P.Cpu.peer(c1))
    # The remote arm of `cpu.peer_of` is `:89`, and `cpu_peer_remote` is its
    # only row: the two `peer` rows above are both non-remote, so without this
    # one the whole `remote_peer` derivation could be replaced by `head(dev)`
    # and every row would still hold.
    P.srow("cpu_peer_remote", P.Cpu.peer(c2))
    P.urow("cpu_renderers_n", U32.from_nat(List.length(&2, P.Cr, P.Cpu.renders(c0))))
    P.srow("cpu_renderers", P.rnames(P.Cpu.renders(c0)))
    P.urow("cpu_connect_local_n", P.seen(P.Cpu.t(c1)))
    P.urow("cpu_connect_remote_n", P.seen(P.Cpu.t(c2)))
    P.urow("cpu_sync_local_pings", ncalls(P.CALL_PING(), P.Cpu.t(cpu.synchronize(False{}, c1))))
    P.urow("cpu_sync_remote_pings", ncalls(P.CALL_PING(), P.Cpu.t(cpu.synchronize(True{}, c2))))

# --- 4: `__init__` -- the call sequence, :23-56 --------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    P.urow("cpu_init_0000_n", init_n(False{}, False{}, False{}, False{}))
    P.urow("cpu_init_0001_n", init_n(False{}, False{}, False{}, True{}))
    P.urow("cpu_init_0010_n", init_n(False{}, False{}, True{}, False{}))
    P.urow("cpu_init_0011_n", init_n(False{}, False{}, True{}, True{}))
    P.urow("cpu_init_0100_n", init_n(False{}, True{}, False{}, False{}))
    P.urow("cpu_init_0101_n", init_n(False{}, True{}, False{}, True{}))
    P.urow("cpu_init_0110_n", init_n(False{}, True{}, True{}, False{}))
    P.urow("cpu_init_0111_n", init_n(False{}, True{}, True{}, True{}))
    P.urow("cpu_init_1000_n", init_n(True{}, False{}, False{}, False{}))
    P.urow("cpu_init_1001_n", init_n(True{}, False{}, False{}, True{}))
    P.urow("cpu_init_1010_n", init_n(True{}, False{}, True{}, False{}))
    P.urow("cpu_init_1011_n", init_n(True{}, False{}, True{}, True{}))
    P.urow("cpu_init_1100_n", init_n(True{}, True{}, False{}, False{}))
    P.urow("cpu_init_1101_n", init_n(True{}, True{}, False{}, True{}))
    P.urow("cpu_init_1110_n", init_n(True{}, True{}, True{}, False{}))
    P.urow("cpu_init_1111_n", init_n(True{}, True{}, True{}, True{}))
    +p8: P.Prog <- IO.pure(P.Prog, fx_init_raw(True{}, True{}, True{}, True{}))
    +p6: P.Prog <- IO.pure(P.Prog, fx_init_raw(False{}, False{}, False{}, False{}))
    +pw: P.Prog <- IO.pure(P.Prog, fx_win())
    P.srow("cpu_init_order", tnames(P.Prog.t(p8)))
    P.srow("cpu_init_order_posix", tnames(P.Prog.t(p6)))
    P.srow("cpu_init_order_win", tnames(P.Prog.t(pw)))
    P.urow("cpu_init_win_n", P.seen(P.Prog.t(pw)))
    P.srow("cpu_init_posix_load", call_at(P.Prog.t(p6), 2))
    P.srow("cpu_init_posix_cache", call_at(P.Prog.t(p6), 4))
    P.srow("cpu_init_osx_load", call_at(P.Prog.t(p8), 3))
    P.srow("cpu_init_osx_cache", call_at(P.Prog.t(p8), 6))
    P.urow("cpu_init_posix_wp_n", (U32.add(ncalls(P.CALL_WRITE_PROTECT_OFF(), P.Prog.t(p6)),
                                    ncalls(P.CALL_WRITE_PROTECT_ON(), P.Prog.t(p6))) : U32))
    P.urow("cpu_init_osx_wp_n", (U32.add(ncalls(P.CALL_WRITE_PROTECT_OFF(), P.Prog.t(p8)),
                                    ncalls(P.CALL_WRITE_PROTECT_ON(), P.Prog.t(p8))) : U32))
    P.urow("cpu_init_posix_mmap_n", ncalls(P.CALL_MMAP(), P.Prog.t(p6)))
    P.urow("cpu_init_win_mmap_n", ncalls(P.CALL_MMAP(), P.Prog.t(pw)))
    # the REMOTE arm is one call long and skips everything else
    +pr: P.Prog <- IO.pure(P.Prog, fx_remote())
    P.urow("cpu_init_remote_n", P.seen(P.Prog.t(pr)))
    P.srow("cpu_init_remote_order", tnames(P.Prog.t(pr)))
    P.urow("cpu_init_remote_has_mmap", ncalls(P.CALL_MMAP(), P.Prog.t(pr)))
    # :21, the `_load` branch: an ELF blob goes through `jit_loader`, anything
    # else is used as it stands.
    P.row("cpu_load_raw_elf", Bool.not(cpu.uses_jit_loader(True{})))
    P.row("cpu_load_raw_short", Bool.not(cpu.uses_jit_loader(False{})))
    P.row("cpu_load_raw_other", Bool.not(cpu.uses_jit_loader(False{})))
    P.srow("cpu_load_tag_elf", P.call_name.go(P.cpu.load_raw(True{})))
    P.srow("cpu_load_tag_raw", P.call_name.go(P.cpu.load_raw(False{})))
    # :40, the mmap flags under each platform fact
    P.urow("cpu_map_flags_posix", P.cpu.map_flags(False{}))
    P.urow("cpu_map_flags_osx", P.cpu.map_flags(True{}))


# `struct.pack_into(f'<3I{len(bufs)}Q', lvp_args, 0, *data64_le(addr+12), ...)`
# -- the val slots AT their byte offsets, which is what `12 + off` answers.
def lvp.smap.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}: acc
        case x <> t: lvp.smap.go(p, t, List.append(&2, U32, acc, [lvp.at(x)]))

def lvp.slotmap(+nvals: Nat, +nbufs: U32) -> List<&2, U32>:
  lvp.smap.go(List.length(&2, U32, lvp.slots(sig7(), nvals, nbufs)), lvp.slots(sig7(), nvals, nbufs), Nil{})

# --- 5: `__call__` and `__del__`, :58-78 ---------------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    P.urow("cpu_nargs_00", P.prog.nargs(0, 0))
    P.urow("cpu_nargs_30", P.prog.nargs(3, 0))
    P.urow("cpu_nargs_31", P.prog.nargs(3, 1))
    P.urow("cpu_nargs_20", P.prog.nargs(2, 0))
    P.urow("cpu_nargs_14", P.prog.nargs(1, 4))
    P.urow("cpu_nargs_02", P.prog.nargs(0, 2))
    P.urow("cpu_lvp_size_00", P.lvp.size(0, 0))
    P.urow("cpu_lvp_size_31", P.lvp.size(3, 1))
    P.urow("cpu_lvp_size_14", P.lvp.size(1, 4))
    P.urow("cpu_lvp_third_31", lvp.third(3, 1))
    P.urow("cpu_lvp_third_00", lvp.third(0, 0))
    P.srow("cpu_sig_itemsizes", ilist(sig7()))
    P.lrow("cpu_lvp_slots_3_2", lvp.slotmap(2n, 3))
    P.lrow("cpu_lvp_slots_2_1", lvp.slotmap(1n, 2))
    P.lrow("cpu_lvp_slots_0_3", lvp.slotmap(3n, 0))
    P.urow("cpu_lvp_d64_lo", P.nth(lvp.d64(4108), 0n))
    P.urow("cpu_lvp_d64_hi", P.nth(lvp.d64(4108), 1n))
    P.srow("cpu_call_remote_wait", P.call_name.go(P.prog.remote_tag(True{})))
    P.srow("cpu_call_remote_nowait", P.call_name.go(P.prog.remote_tag(False{})))
    P.urow("cpu_call_ret_wait_none", prog.ret_is_none(True{}))
    P.urow("cpu_call_ret_nowait_none", prog.ret_is_none(False{}))
    +pl: P.Prog <- IO.pure(P.Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, False{}, False{}))
    +pv: P.Prog <- IO.pure(P.Prog, prog.call(fx_init(False{}, False{}, False{}, True{}, False{}, False{}), 3, 1, False{}, False{}))
    +pr: P.Prog <- IO.pure(P.Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, True{}, True{}))
    +pw: P.Prog <- IO.pure(P.Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, False{}, False{}))
    P.srow("cpu_call_local_plain", tnames(P.Prog.t(pw)))
    P.srow("cpu_call_local_lvp", tnames(P.Prog.t(pv)))
    P.srow("cpu_call_remote_order", tnames(P.Prog.t(pr)))
    P.urow("cpu_del_00", ncalls(P.CALL_VIRTUAL_FREE(), P.Prog.t(prog.del(False{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    P.urow("cpu_del_01", ncalls(P.CALL_VIRTUAL_FREE(), P.Prog.t(prog.del(False{}, True{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    P.urow("cpu_del_10", ncalls(P.CALL_VIRTUAL_FREE(), P.Prog.t(prog.del(True{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    P.urow("cpu_del_11", ncalls(P.CALL_VIRTUAL_FREE(), P.Prog.t(prog.del(True{}, True{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    P.urow("cpu_del_remote_posix", ncalls(P.CALL_VIRTUAL_FREE(), P.Prog.t(prog.del(True{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    P.lrow("cpu_call_lvp_arg_31", targ(P.CALL_FXN_LVP(), P.Prog.t(pv)))
    P.lrow("cpu_call_plain_arg_31", targ(P.CALL_FXN(), P.Prog.t(pl)))
    P.lrow("cpu_call_nargs_arg_31", targ(P.CALL_FXN(), P.Prog.t(pl)))
    P.urow("cpu_call_profile_n", ncalls(P.CALL_PROFILE(), P.Prog.t(pl)))
    P.urow("cpu_call_profile_none", ncalls(P.CALL_PROFILE(), P.Prog.t(pr)))
    # THE MATCHER PINS ITSELF, and it needs BOTH directions. `ops_webgpu.bend`
    # shipped with the pattern length as the fuel and M23 measured that no row
    # could fail; a matcher that is only ever asked to REJECT answers False for
    # every fuel, which is why the rejection rows alone did not catch it here
    # either (M56). A fuel of `len(pat)` reads the first `len(pat)` calls only,
    # so the row that kills it is a one-call pattern at index 1 of a two-call
    # trace: the real answer is True, the short fuel cannot reach it.
    P.urow("cpu_has_rejects_reverse", Bool.to_u32(Bool.not(seq(P.Prog.t(pw),
      [P.Call{P.CALL_FXN, 0}, P.Call{P.CALL_PROFILE, 0}]))))
    P.urow("cpu_has_rejects_absent", Bool.to_u32(Bool.not(seq(P.Prog.t(pw), [P.Call{P.CALL_PING, 0}]))))
    P.urow("cpu_has_accepts_plain", Bool.to_u32(seq(P.Prog.t(pl), [P.Call{P.CALL_FXN, 4}])))
    P.urow("cpu_has_accepts_lvp", Bool.to_u32(seq(P.Prog.t(pv), [P.Call{P.CALL_FXN_LVP, 44}])))
    P.urow("cpu_has_rejects_wrong_arg", Bool.to_u32(Bool.not(seq(P.Prog.t(pl), [P.Call{P.CALL_FXN, 5}]))))


def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_devname()
    c : Unit <- t_device()
    d : Unit <- t_init()
    t_call()

# ===========================================================================
# THE MUTATION TABLE, MEASURED.
#
# 109 edits, one at a time, each against a scratch copy of THIS file, each run
# through `./bin/bend` and diffed ROW BY ROW against the unmutated 308. The
# number is how many rows changed value, appeared or vanished -- NOT how many
# rules the edit might have broken. A zero is a fact about the GATE, so the
# three zeros are argued below rather than closed with a row that encodes the
# bug. Reproduce with cn-mutate.py, which lives OUTSIDE the tree because this
# file is the only thing this port adds to the repo.
#
# 225 of the 308 rows are named by at least one mutation. The 83 that are not
# are per-index twins -- a second `Zz` cell, a second `pk_*` layout, a second
# `cpu_nparts` spelling -- of a family that IS mutated, plus the two cells where
# a separator mutation is a sound no-op (`""` and `"CPU"` both have one part
# under either separator).
#
# THE THREE ZEROS.
#
#   M60  a comment-only edit. THE CONTROL, and it is SUPPOSED to be zero: if a
#        comment moved a row, this harness was measuring something other than
#        the code.
#
# what this gate still does not see. Stated here rather than left to be found:
#
#   * Anything the wall stops. A 64-bit `addr`, a `Native` function pointer, the
#     real `mv_address`, the real `jit_loader` link and the `mmap`ed bytes are
#     all seams. `P.Prog.addr` is a PORT MODEL -- the trace index -- and no row
#     claims it is a measurement.
#   * Every ordering the PORT does not walk. `Ev.put` keeps keys in insert
#     order in a LIST where Python has a dict, so the list can only stay a dict
#     because nothing but `Ev.put` inserts. That is a fact about the port's
#     discipline, not about its type.
#   * `String` bytes. WALL 2 means four bytes cannot be compared, so
#     `cpu.elfmag` is the ANSWER `7f454c46` and not a comparison against one.
#     A port that computed it wrongly and a port that hardcoded it correctly
#     look identical here.
#   * The compiler backend, the linker and `__clear_cache`. :51 picks between
#     `pthread` write-protect, `__clear_cache` and `msync` on `getenv` reads;
#     all three arms are traced and none of them is executed.
#
# ===========================================================================
#   M6      1  cpu.arch_of: the `amd64` row maps to itself
#   M7      8  cpu.arch_of: the `,native` suffix dropped
#   M8      2  cpu.is_remote: `== 3` -> `>= 3`
#   M9      3  cpu.remote_peer: the `remote:` prefix dropped
#   M10     1  cpu.peer_of: the remote arm returns the head, not the remote peer
#   M11     1  cpu.wait_timeout_ms: 30000 -> 30000*1000
#   M12     1  cpu.rt_lib_name: the WIN ternary answers `kernel` always
#   M13     1  cpu.map_flags: MAP_JIT on every platform
#   M14     1  prog.wp.on_at: the write-protect pair swapped
#   M15     4  prog.posix: the load and the write swapped (:44 walrus order)
#   M16     2  prog.cache.at: the msync arm emits CLEAR_CACHE (both arms same tag)
#   M17     2  prog.init: the win32 arm replaced by the posix arm
#   M18     3  prog.init: `local` ignores the remote test
#   M19     2  prog.call.local: PROFILE emitted only on the lvp arm
#   M20     3  prog.remote_tag: `_rpc if wait else _post` inverted
#   M21     1  prog.ret_is_none: always None
#   M22     1  prog.del.at: the remote conjunct dropped
#   M23     4  lvp.size: no 8-bytes-per-argument
#   M24     2  lvp.slots: the `len(bufs)*8` base dropped
#   M25     3  lvp.at: the 12-byte header dropped from the slot
#   M26     1  lvp.d64: the low word is the ADDRESS, not address+12
#   M27     2  prog.fxn.lvp: the trace arg is the arg COUNT, not the buffer size
#   M44     2  pk.size: the `max(len(args), 1)` guard dropped
#   M45     1  pk.nsrc: the interior pads not counted
#   M46     4  cn_slot: device.bend`s OFF-BY-ALIGNMENT semantics restored
#   M48    14  pk.pads.go: every offset counted as a pad
#   M54     2  Tr.assert_at: the failing assert does NOT record its refusal
#   M55     1  P.Tr.emit.go: drop the `refused` guard (the raise is gone)
#   M56     2  P.Tr.has.go: the fuel is the PATTERN length (ops_webgpu M23, reintroduced)
#   M57     5  tnames: the names fold CONSES (the whole order row reverses)
#   M60     0  a comment-only edit -- THE CONTROL   ZERO -- see below
#   M61     2  cpu.rt_lib_name: the OSX ternary answers `System` always
#   M62    14  cn_slot.of: the running offset is the head, not the aligned one
#   M63     1  cpu.prot_rwx: 0x7 -> 0x6 (the write bit dropped)
#   M64     1  cpu.mem_release: 0x8000 -> 0x4000
#   M65     2  cpu.page_xrw: 0x40 -> 0x20
#   M66     1  cpu.elfmag: ELFMAG.encode() -> "\x7fELG"
#   M67     1  has_copy_queue: the two overrides swapped
#   M73     1  cpu.lib_m: `DLL("m", "m")` -> `DLL("m", "c")`
#   M74    11  prog.nargs: `len(bufs) + len(vals)` -> `len(bufs)`
#   M75     1  lvp.third: two slots per argument -> one
#   M77     4  pk.tail: `size - end` -> `end`
#   M78     3  P.Tr.reset: the trace is NOT cleared
#   M79     2  cpu.uses_jit_loader: the ELF test ignored
#   M81     3  cpu.map_anon: 0x1000 -> 0x800
#   M82     2  cpu.map_jit: 0x0800 -> 0x0400
#   M83     3  cpu.map_private: 2 -> 1
#   M84     1  cpu.ms_flags: MS_SYNC|MS_INVALIDATE -> MS_SYNC
#   M85     1  cpu.renderers: the four names in the wrong order
#   M87    16  pk.size: eight bytes per argument, not four
#   M88     8  cpu.nparts: split on ";" instead of ":"
#   M89     2  prog.del.at: the WIN conjunct dropped (M22 drops the remote one)
#   M90     2  nva.base: 1<<40 -> 1<<41
#   M92     3  sig7: the last itemsize is 8, not 1
#   M98     6  cpu.load_raw: the jit_loader/raw tags swapped
#   M99    20  prog.posix: the CACHE step dropped (every posix count drops by one)
#   M100    2  prog.win: the GET_PROCESS step dropped
#   M103    3  cpu.peer.at: the local arm returns the REMOTE peer (the arms swapped)
#   M106    2  the op tags: EXEC is 5, not 0 (the whole range renumbered)
# ===========================================================================
