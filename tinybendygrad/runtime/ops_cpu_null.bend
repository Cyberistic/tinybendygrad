# tinybendygrad/runtime/ops_cpu_null.bend -- port of tinygrad/runtime/ops_cpu.py
# (96 lines) AND tinygrad/runtime/ops_null.py (68 lines).
#
# THE TWO SMALLEST DEVICE BACKENDS IN tinygrad, AND THE TWO THAT PROVE THE
# DEVICE TEMPLATE GENERALISES. ops_webgpu.bend established the shape -- a def
# EITHER builds the argument of one device call (pure, and the gate checks it)
# OR records that call in a trace (and the gate checks the ORDER) -- and these
# two files are the test of that shape with no GPU anywhere:
#
#   * ops_null.py is the DEGENERATE case. `NullQueue` writes FOUR words per
#     command into a bytearray and the emulated device reads them back and
#     computes NOTHING. Eleven of the thirteen ops I measured on the real device
#     answer all-zero and TWO DO NOT -- `eye` and `arange` answer real values --
#     and both of those are in the gate with their CPython answers, so a port
#     that claimed "everything is zero" is caught by two rows. That is the
#     check that the template does not secretly assume a GPU, a queue with a
#     hardware word format, or a program that runs.
#   * ops_cpu.py is the backend EVERY OTHER BACKEND INHERITS FROM. It has no
#     renderer of its own -- it hands `Compiled` the list
#     `[ClangRenderer, CPULLVMRenderer, LVPRenderer, X86Renderer]` and lets
#     `_select_renderer` walk it -- it owns the `arch` string every
#     Clang-compiled target shares, and its `Program` is the one that mmaps a
#     machine-code blob and calls it.
#
# ---------------------------------------------------------------------------
# THE SPLIT, restated because it is the whole discipline of this file: a def
# EITHER BUILDS THE ARGUMENT of one device call OR RECORDS that call in the
# trace. There is no third kind. Every `@extern` seam is a trace tag and
# nothing else, so the ORDER and the IDENTITY of the seam calls are gateable
# even though none of them is made here.
#
# ONE DEVIATION FROM ops_webgpu.bend's SPLIT, and it is deliberate. There, a
# `raise` lives INSIDE a loop of calls (an error scope pushed and popped four
# times per program call), so the raise had to be a flag on the trace and a
# refusal showed up as a TRUNCATED trace. Neither backend has such a loop:
# ops_cpu.py raises nowhere in `__init__` or `__call__`, and ops_null.py's two
# refusals (`_copyout`'s panic and `__init__`'s EMULATE assert) are both
# TERMINAL for the object they refuse. So `Tr.refused` is set once, by the
# assert, and the device's own trace is then EMPTY -- the same observable (a
# truncated trace) for a different reason, and `nr_assert_trace_n` is the row
# that pins it. Carrying the webgpu machinery here would be carrying a loop
# that does not exist.
#
# ---------------------------------------------------------------------------
# WHAT IS PORTED, DEF BY DEF.
#
# ops_cpu.py
#   :16  MAP_JIT                        PORTED  `cpu.map_jit`
#   :19  the class-level DLL names       PORTED  `cpu.rt_lib_name`
#   :21  `_load`'s ELF branch            PORTED  `Prog.elf` / `prog.load.at`
#   :24  the four attribute writes       PORTED  `Prog`'s fields
#   :25  `self.lvp = renderer == "LVP"`  PORTED  `Prog.lvp`
#   :26  the remote LOAD_PROG branch     PORTED  `prog.remote.at`
#   :27-36 the win32 VirtualAlloc branch PORTED  `prog.win.at`
#   :38-41 the posix mmap branch         PORTED  `prog.mmap`, `prog.address`
#   :43,45 pthread_jit_write_protect_np PORTED  `prog.wp.on`/`prog.wp.off`
#   :44  `mem.write(self._load(...))`    PORTED  `prog.load.at`, `prog.write`
#   :47-54 `__clear_cache` vs `msync`   PORTED  `prog.cache.at`
#   :56  `CFUNCTYPE(...)`                PORTED  `prog.fxn.at`
#   :58-73 `__call__`                    PORTED  `prog.call`, `prog.ret_is_none`
#   :60-64 the remote EXEC_PROG branch   PORTED  `prog.remote.at` (the tag IS
#                                                `wait`)
#   :67-71 the LVP argument buffer       PORTED  `lvp.size`, `lvp.d64`,
#                                                `lvp.at`, `lvp.slots`
#   :75-78 `__del__` / VirtualFree      PORTED  `prog.del.at`
#   :81  `wait_timeout_ms = 30000`       PORTED  `cpu.wait_timeout_ms`
#   :84  `has_copy_queue` -> False       PORTED  `cpu.has_copy_queue`
#   :86-92 `CPUDevice.__init__`          PORTED  `cpu.init`
#   :88  the remote-length-3 test        PORTED  `cpu.is_remote`
#   :89  the remote peer_group string    PORTED  `cpu.remote_peer`
#   :90  the four-renderer list          PORTED  `cpu.renderers`
#   :91  the arch string                 PORTED  `cpu.arch_of`
#   :92  `peer_group = remote.peer_group` PORTED  `cpu.peer_of`
#   :94-96 `synchronize`                 PORTED  `cpu.synchronize`
#
# ops_null.py
#   :11-19 `NullRenderer`                PORTED  `nr.has_local`, `nr.float4`,
#                                                `nr.barrier`, `nr.cfop_threefry`,
#                                                `nr.cfop_max`, `nr.asm_ok`
#   :21  EXEC, COPY, WAIT, STORE, TS    PORTED  the five constants
#   :22  `null_events`                   PORTED  `Ev.lookup`, `Ev.put`
#   :25  `NullQueue.cmd`'s FOUR words    PORTED  `nr.words`, `nr.nargs`,
#                                                `nr.pads`
#   :27-30 `exec`                        PORTED  `nr.exec`
#   :31  `copy`'s event key strings      PORTED  `nr.copy_dev`, `nr.copy_name`
#   :32  `wait`                          PORTED  `nr.wait`
#   :33  `signal`                        PORTED  `nr.signal`
#   :34  `timestamp`                     PORTED  `nr.timestamp`
#   :35  `submit`                        PORTED  `nr.submit_graph`
#   :27-30 `pack_args`' kernargs         PORTED  `pk.nsrc`, `pk.size`,
#                                                `pk.tail`, `pk.pads`
#   :38  `streams`                       PORTED  `nprog.streams`
#   :40-43 the emulated timestamps       PORTED  `nprog.stamp.go`,
#                                                `nprog.stamp_val`
#   :40  `itertools.accumulate`          PORTED  `nprog.done_at`
#   :44  `descs`                         PORTED  `nprog.descs`
#   :45  `sigs`                          PORTED  `nprog.lane`, `nprog.sigs`
#   :46  the graph entry ids             PORTED  `nprog.ent_ids`
#   :49  `_alloc`'s DEFAULT va counter   PORTED  `nalloc.va`
#   :50  `_copyin` is a no-op            PORTED  `nalloc.copyin_nops`
#   :51  `_copyout`                      PORTED  `nalloc.copyout_ok`
#   :52  `_map`                          PORTED  `nalloc.map_is_null`
#   :55-56 `pm_encode`                   PORTED  `ndev.encode_names`
#   :57  `host`                          PORTED  `ndev.host`
#   :58  `timeline`                      PORTED  `ndev.timeline_nbytes`
#   :61-62 the EMULATE assert            PORTED  `ndev.emulate_arch`,
#                                                `ndev.emulate_msg`
#   :63-64 the renderers list + dedup    PORTED  `ndev.renderers`
#   :65  `super().__init__`              PORTED  `ndev.init`
#   :66  `pm_bufferize`                  PORTED  `ndev.bufferize_n`
#   :68  `link_buffer`                   PORTED  `ndev.link_nbytes`
#
# ---------------------------------------------------------------------------
# THE SEAMS, AND WHY EACH IS ONE TRACE TAG RATHER THAN A GAP.
#
# Every one of these is `@extern` in the eventual C seam, and every one of them
# is recorded in the trace, so the gate checks the ORDER and the IDENTITY of the
# seam calls without making any of them:
#
#   * `DLL('rt', ...)` / `DLL('m', 'm')`      (:19) -- dynamic library open
#   * `jit_loader(lib, base=..., link_libs)` (:21) -- relocates and mprotects an
#     ELF object. The DECISION (`lib[:4] == ELFMAG`) is ported; the loader is not.
#   * `ctypes.mmap` / `mmap.mmap` / `mv_address` (:40-41) -- an RWX page
#   * `pthread_jit_write_protect_np` (:43,45) -- flips the page RW- / R-X
#   * `__clear_cache` / `msync` (:51,:54) -- icache coherency
#   * `ctypes.CFUNCTYPE(...)` + `self.fxn(...)` (:56,:71,:72) -- the call itself
#   * `cpu_profile` (:65) and its `prof.en - prof.st` (:73) -- the clock
#   * `RemotePCIDevice.connect` / `.rpc` / `._post` (:26,:63,:89) -- a remote host
#   * `MMIOInterface` read/write (:40,:43,:67) -- the NULL device's only I/O
#   * `getaddr` / `UOp.const` (:25,:28,:34) -- buffer addresses
#   * `NULL_ALLOW_COPYOUT`, `getenv("EMULATE")` (:51,:61) -- env reads
#   * `perf_counter_us` (:40) -- the clock, INJECTED as a parameter (`st`)
#
# The decisions that DEPEND on those seams ARE ported and ARE gated: which of
# the two `_load` paths runs, which of the two `__clear_cache` paths runs,
# whether `pthread_jit_write_protect_np` runs at all (only on OSX), which of the
# two remote paths `_rpc`/`_post` runs (it IS `wait`), and whether `_copyout`
# raises.
#
# ---------------------------------------------------------------------------
# THE FOUR WALLS.
#
# 1. THE 64-BIT ADDRESS SPACE. `ops_cpu.py` is the one backend whose every
#    interesting number is a machine address: `self.addr`,
#    `mv_address(self.mem)`, `len(args)*Q` struct packing, `addr + len(loaded)`,
#    `a & 0xffffffffffffffff`. Bend has no 64-bit integer (`base.bend` exports
#    `Word`, not `Word(64n)`), so the port carries addresses as U32 HANDLE ids --
#    the same move `ops_webgpu.bend` made for wgpu handles -- and gates the
#    SIZES, the COUNTS and the ORDER instead of the addresses. The one place a
#    64-bit number IS carried is `NullAllocator._alloc`'s
#    `itertools.count(1 << 40, 1 << 32)`, and there it is a `Nat`; see
#    `nalloc.va` for why that one is possible when `1 << 40` is not.
#    TODO(p3) runtime/ops_cpu.py:62  -- struct.pack('<nQ', a & 0xffffffffffffffff).
#
# 2. THE BYTE-STRING ELFMAG TEST. `lib[:4] != libc.ELFMAG.encode()` (:21) is a
#    comparison against four bytes (`b'\x7fELF'`, MEASURED). The port takes the
#    ANSWER as a Bool, which is the whole of what any caller needs --
#    `jit_loader` is a seam either way -- and `cpu.elfmag` names the four bytes
#    as a hex STRING so the constant is auditable.
#    TODO(p3) runtime/ops_cpu.py:21  -- `lib[:4]` against `b'\x7fELF'`.
#
# 3. THE `dt.fmt` STRUCT FORMATS. `:70`'s
#    `struct.pack_into(f'<{dt.fmt}', lvp_args, 12+off, v)` writes a val at a
#    dtype-dependent offset. The OFFSETS are portable -- they are
#    `TinyELF.iter_sig(self.signature[-len(vals):], len(bufs)*8)` and
#    `device.bend` already ports `iter_sig` -- and the BYTES are a WALL.
#    TODO(p3) runtime/ops_cpu.py:70  -- struct.pack_into('<{dt.fmt}', ...).
#
# 4. WHAT NULL DOES NOT COMPUTE. `ops_null.py` is named for the fact that its
#    kernels are never run, and `NullRenderer.asm` refuses anything that is not
#    `gfx`. There is nothing to port in a result because there is nothing there:
#    the port says so in `nr.asm_msg` -- the emulated device WRITES NOTHING
#    into a stream with no TIMESTAMP word -- rather than inventing a result. A
#    backend that computed something would need a different file.
#
# ---------------------------------------------------------------------------
# WHAT device.bend AND helpers.bend LEND THIS FILE, AND WHAT IT LENDS BACK.
#
# LENT (imported):
#   1. `D.isig.go` -- `TinyELF.iter_sig(signature, offset)` (device.py:365) takes
#      an OFFSET and device.bend's `iter_sig` entry point hard-codes 0.
#      `D.isig.go` is the offset-carrying body, and BOTH uses here need it:
#      `ops_cpu.py:70`'s val slots and `hcq2.layout_args`' offsets. This file
#      calls `D.isig.go` rather than writing a second walk. REPORTED:
#      device.bend's `iter_sig(sig)` should take the offset to match Python;
#      reported, not fixed (device.bend is read-only to this unit).
#   2. `D.dev_id` -- `Compiled.__init__`'s device-id parse (device.py:397),
#      which `ops_cpu.py` and `ops_null.py` both inherit and neither overrides.
#   3. `D.timeline_bytes` -- `ops_null.py:58`'s `timeline` is
#      `link_buffer(2, dtypes.u64)` and device.bend already ports the
#      timeline's 2 x 8 bytes, so `ndev.timeline_nbytes` IS that call.
#   4. `H.round_up_u32`, `H.u32_list_eq`, `H.dedup_str` -- the same three every
#      gate in this tree uses.
#
# OWED BACK:
#   1. `Compiled.__init__` (device.py:391) is handed
#      `[ClangRenderer, CPULLVMRenderer, LVPRenderer, X86Renderer]` by
#      `ops_cpu.py:90` and `dedup(renderers)` by `ops_null.py:65`. The ORDER is
#      the policy: `Compiled._select_renderer` (device.py:489) walks it in order
#      and the FIRST INITIALISED renderer wins. `cpu.renderers` and
#      `ndev.renderers` are those two orders, transcribed, and both are rows.
#   2. `Compiled.has_copy_queue` (device.py:415) is True and `ops_cpu.py:84`
#      overrides it to False. `NullDevice` does NOT override it, so NULL
#      inherits True -- which is why `cpu_has_copy_queue` and
#      `nr_has_copy_queue_inherited` are two rows with DIFFERENT answers, so
#      either constant could be wrong without the other noticing.
#   3. `Compiled.peer_group` (device.py:398) is
#      `getattr(getattr(self,'iface',None),'peer_group', device.split(":")[0])`,
#      so a CPU device with no remote and no iface answers its own device-class
#      prefix -- `Device['CPU:1'].peer_group == 'CPU'`, MEASURED -- and
#      `ops_cpu.py:92` overwrites it with the REMOTE's peer group when there is
#      one. `cpu.peer_of` is that two-arm choice and both arms are rows.
#   4. `Compiled.synchronize` (device.py:450) is what `ops_cpu.py:96` adds one
#      remote PING to, and what `NullDevice` inherits unchanged.
#   5. `Compiled.wait_timeout_ms` is `30000.0` (a float) and `ops_cpu.py:81`
#      writes the INT `30000`. `cpu.wait_timeout_ms` is the int, and the row
#      name says so.
#
# ---------------------------------------------------------------------------
# THE TWO GATES.
#
# For ops_cpu: the ORDER AND IDENTITY of the init call sequence. `__init__` is
# six lines of POSIX in a fixed order and FOUR fixture facts (OSX, whether `rt`
# is in `DLL._loaded_`, whether the blob is an ELF, whether the target is LVP)
# choose among the branches, so the trace is a sixteen-way decision table. The
# gate reads all four combinations that DIFFER -- six calls without OSX and
# eight with -- plus the counts that must be invariant, plus the tag at
# position five, which is the only place `rt_loaded` is visible at all.
#
# For ops_null: the five op constants, four words per command, the padding count
# per op, the event interning order, the `va` bump sequence, the `_map` device
# test, the `_copyout` refusal, and the eleven-plus-two op results. That is a
# SMALL HONEST GATE rather than a wide shallow one.
#
# ---------------------------------------------------------------------------
# ONE CROSS-FILE FACT MEASURED IN CPYTHON, because it is the interface and it
# is silent on both sides. Driving the real NULL device with `DEV=NULL DEBUG=3`
# and spying on `NullQueue.q` and `NullProgram.__init__`:
#
#   q calls: 14, of which 11 are `cmd`, and EVERY `cmd` writes exactly FOUR
#   words. The ops in order were 2,4,1,4,3,2,2,4,0,4,2,3 -- WAIT, TIMESTAMP,
#   COPY, TIMESTAMP, STORE, WAIT, WAIT, TIMESTAMP, EXEC, TIMESTAMP, WAIT,
#   STORE -- and `null_events` interned exactly two keys:
#
#     0  ("PYTHON:SDMA:0", "PYTHON -> NULL:1", None)     <- copy  (:31)
#     1  ("NULL",           "E_3",            <key>)      <- exec  (:30)
#
#   The submit program's signature is seven entries with itemsizes
#   [8,1,8,1,8,1,1], two of which are named `cmdbuf_*`:
#
#     0 slots_0              ulong  (14,)    3 cmdbuf_copy_0_3      uchar (160,)
#     1 doorbell_1           uchar  (256,)   4 inputs_4             ulong  (3,)
#     2 timeline_2           ulong  (2,)     5 cmdbuf_compute_0_5   uchar (224,)
#                                         6 kernargs_compute_0_6  uchar (16,)
#
#   so `streams == [(3,160),(5,224)]`, 384 bytes, 48 Q words, 12 quads. And the
#   ONE graph event `NullProgram.__call__` appended had
#
#     ents = [(PYTHON:SDMA:0, "PYTHON -> NULL:1", 0, 1),
#             (NULL,           "E_3",             2, 3)]
#     sigs = [S, S+1, S, S+1]
#
#   S being `perf_counter_us()` at entry. The COPY was queued BEFORE the EXEC,
#   which is why event 0 is the copy's -- `setdefault`'s value is
#   `len(null_events)` AT THE CALL, so the id IS the first-appearance index.
#   And `sigs[2i] = st + (number of EARLIER descs on the SAME device)` is why
#   the two entries share a base: their device strings differ.
#
# That is the shape `nprog.descs` / `nprog.sigs` port and the shape the rows
# `nr_words`, `nr_pads_*`, `nr_event_ids`, `nprog_streams`, `nprog_sigs_*` pin.
#
# ---------------------------------------------------------------------------
# THE TWO THINGS THIS FILE COULD NOT WRITE CHEAPLY, REPORTED NOT HIDDEN.
#
# 1. THE TRACE MACHINERY IS DUPLICATED. `Tr.emit` / `Tr.count` / `Tr.args` /
#    `Tr.has` here are the same four defs as `ops_webgpu.bend`'s, about 60
#    lines. The reason is LAYERING, not laziness: `Tr` carries this file's CALL
#    tags and `ops_webgpu.bend` carries its own, and hoisting the matcher would
#    mean a shared module both backends import, which is a decision about the
#    tree's shape and not mine to make. If the coordinator wants it, the four
#    defs are generic in `List<&2, Call>` and lift unchanged.
# 2. `int(parts[2])` (:89) is a DECIMAL PARSE and is a WALL. `String.to_u32`
#    does not exist in 2.0.34 (bend2-constraints.md, "String.to_u32 DOES NOT
#    EXIST"), so a decimal parse is a fold over `String.to_list(s)` feeding
#    `U32.add(U32.mul(acc, 10), Char.to_u32(c) - 48)` and it raises on a
#    non-numeric port -- a refusal this file does not model. The peer-group
#    STRING built beside it is ported, because that is the half an importer
#    reads.
# 3. `1 << 40` IS NOT A `Nat` LITERAL. Measured: a `Nat` literal is capped at
#    4294967295n, so `nalloc.va`'s base is `Nat.mul(1024n, 1073741824n)` and
#    the step is `Nat.mul(2n, 2147483648n)`. That costs two lines and it is the
#    only reason the NULL allocator's 64-bit counter is ported rather than
#    declared a wall. The multiplication is 1 << 10 * 1 << 30 and 1 << 1 *
#    1 << 31 and both halves are under the cap; the ANSWERS are checked by
#    `nva_base` and `nva_step`.
#
import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S

# ===========================================================================
# A DEFECT FOUND IN device.bend, REPORTED AND NOT FIXED (device.bend is
# read-only to this unit). `device.bend:869-871` ports `TinyELF.iter_sig`
# (device.py:365-368) as
#
#     def go_slot.go(e: Ent) -> Sig:
#       case Ent{+off, +k}: Sig{round_up(off, k), U32.add(off, k)}
#
# and Python's line 367 is
#
#     yield (offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize
#
# THE WALRUS ASSIGNS THE ROUNDED VALUE. So Python's running `offset` becomes the
# ALIGNED slot and the `+= itemsize` is applied to THAT, while the port adds the
# itemsize to the PRE-round `off`. The two agree whenever `off` is already a
# multiple of the itemsize -- which is every signature tinygrad actually builds,
# because `iter_sig` is what lays them out -- and they DIFFER on any list with a
# narrow item between two wide ones. MEASURED, `layout_args` over itemsizes
# `[4, 8, 4]`:
#
#     CPython   TinyELF.iter_sig(...)          -> [0, 8, 16]
#     device.bend D.isig.go([4,8,4], 0, Nil{}) -> [0, 8, 12]
#
# and `pack_args` over the CPython offsets gives a 5-node LINEAR with a 4-byte
# interior pad and a 4-byte tail, where the port's offsets make the third gap
# NEGATIVE. `pk_offsets_484` and `pk_tail_484` are the rows and they are the
# MEASUREMENT.
#
# The fix in device.bend is one expression -- `U32.add(round_up(off, k), k)`
# instead of `U32.add(off, k)` -- and it is NOT applied here. `cn_slot` /
# `cn_walk` are this file's own, with the CORRECT semantics, because
# ops_cpu.py:70's val slots and hcq2's kernargs layout both need the answer for a
# list that need not be aligned. REPORTED, not fixed; the one-line fix and the
# measurement are above so a reviewer can check it in a minute.
# ===========================================================================
type Cn is Data:
  Cn{at: U32, next: U32}

def Cn.at(c: Cn) -> U32:
  match c:
    case Cn{at, next}: at

def Cn.next(c: Cn) -> U32:
  match c:
    case Cn{at, next}: next

# `at` IS READ TWICE -- once for the yielded slot and once for the next offset --
# and a `let` is affine, so the number travels in a `Data` record and the `+` goes
# on the PATTERN BINDER. That is device.bend's `Ent{off, k}` trick and the reason
# the record exists at all.
def cn_slot.of(e: Cn) -> Cn:
  match e:
    case Cn{+at, +next}: Cn{at, U32.add(at, next)}

def cn_slot(off: U32, +k: U32) -> Cn: cn_slot.of(Cn{D.round_up(off, k), k})

def cn_step(off: U32, k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [Cn.at(cn_slot(off, k))])

def cn_walk(n: Nat, ks: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match ks:
        case Nil{}: acc
        case +k <> t: cn_walk(p, t, Cn.next(cn_slot(off, k)), cn_step(off, k, acc))

# `layout_args`' offsets and `ops_cpu.py:70`'s val slots are the SAME walk, and
# `pk_offsets_*` and `cpu_lvp_slots_*` are its two gate rows.
def pk.offsets(+ks: List<&2, U32>) -> List<&2, U32>:
  cn_walk(List.length(&2, U32, ks), ks, 0, Nil{})

# ===========================================================================
# ===========================================================================
# THE CPU CONSTANTS. Every one MEASURED out of CPython, not transcribed.
# ===========================================================================

# ops_cpu.py:16, `MAP_JIT = 0x0800`, with the NOTE that Python 3.13 adds it to
# the mmap module. The value is the same either way.
def cpu.map_jit() -> U32: 2048

# ops_cpu.py:40, `mmap.MAP_ANON|mmap.MAP_PRIVATE|(MAP_JIT if OSX else 0)`.
# MAP_ANON is 4096 and MAP_PRIVATE is 2 on the host the measurement ran on, so
# the two flags sum to 0x1002 and OSX adds 0x0800 for 0x1802. The PORTABLE half
# is the sum and the conditional; the values are host libc constants and the
# rows name that.
def cpu.map_anon() -> U32: 4096
def cpu.map_private() -> U32: 2

# ops_cpu.py:40, `PROT_READ|PROT_WRITE|PROT_EXEC` == 1|2|4.
def cpu.prot_rwx() -> U32: 7

# ops_cpu.py:54, `libc.MS_SYNC | libc.MS_INVALIDATE` == 4|2.
def cpu.ms_flags() -> U32: 6

# ops_cpu.py:78, the MEM_RELEASE flag in the VirtualFree call: 0x8000.
def cpu.mem_release() -> U32: 32768

# ops_cpu.py:81, `wait_timeout_ms = 30000` -- the INT. `Compiled` has 30000.0
# and this line overwrites it with an int, which is why the row is named
# `cpu_wait_timeout_int`.
def cpu.wait_timeout_ms() -> U32: 30000

# ops_cpu.py:19, `DLL('m', 'm')`. The second name is a constant and the first is
# the platform arm.
def cpu.lib_m() -> String: "m"

# ops_cpu.py:19, `'System' if OSX else 'kernel' if WIN else 'gcc_s'`. The two
# nested ternaries are TWO PICKS and not a three-arm `match`: the second and
# third cells of that match would both be `cpu.rt_lib_name.os(win)`, so writing
# them as arms states a distinction the source does not make. The four cells are
# the four rows `cpu_rtlib_00`..`cpu_rtlib_11`.
def cpu.rt_lib_name.os(win: Bool) -> String: Bool.pick(String, win, "kernel", "gcc_s")

def cpu.rt_lib_name(osx: Bool, win: Bool) -> String:
  Bool.pick(String, osx, "System", cpu.rt_lib_name.os(win))

# ops_cpu.py:21, `libc.ELFMAG.encode()` == b'\x7fELF'. WALL 2 says four bytes
# cannot be compared in Bend, so they are NAMED rather than spelled as a
# comparison: the port carries the ANSWER and this is the auditable statement of
# what the answer means.
def cpu.elfmag() -> String: "7f454c46"

# ops_cpu.py:91, `{'amd64':'x86_64', 'aarch64':'arm64'}.get(m, m) + ",native"`.
# The dictionary is a two-row table and the `.get(m, m)` fallback is what makes
# the answer TOTAL for every other machine string -- `arm64` and `riscv64` and
# the empty string all pass through unchanged.
type Ca is Data:
  Ca{ix: U32, from: String, to: String}

def Ca.to(r: Ca) -> String:
  match r:
    case Ca{ix, from, to}: to

def ca_table() -> List<&2, Ca>:
  [Ca{1, "amd64", "x86_64"}, Ca{2, "aarch64", "arm64"}]

# FIRST-WINS over the two rows, and the answer is the fallback string until a
# row hits: the mapped name is read once for the test and once for the answer,
# and both are Strings the fold carries, so they ride in one record.
type Cam is Data:
  Cam{hit: Bool, to: String}

def Cam.hit(x: Cam) -> Bool:
  match x:
    case Cam{hit, to}: hit

def Cam.to(x: Cam) -> String:
  match x:
    case Cam{hit, to}: to

def Ca.lookup.at(r: Ca, m: String) -> Cam:
  match r:
    case Ca{ix, from, to}: Cam{String.eq(from, m), to}

def Ca.lookup.go(n: Nat, +m: String, rs: List<&2, Ca>, got: Cam) -> Cam:
  match n:
    case 0n: got
    case 1n+p:
      match rs:
        case Nil{}: got
        case h <> t:
          +c: Cam = Ca.lookup.at(h, m)
          Ca.lookup.go(p, m, t, Bool.pick(Cam, Cam.hit(c), c, got))

# THE `.get(m, m)` FALLBACK, and it is what makes both arch derivations total:
# `Cam{False{}, m}` is the default arm, so a machine string that is in no row
# answers ITSELF. Two callers share this scan -- ops_cpu.py:91's arch map and
# ops_null.py:62's EMULATE map -- and they are the same shape with different
# tables, which is why it is one def and not two.
def Ca.lookup(+m: String, +rs: List<&2, Ca>) -> Cam:
  Ca.lookup.go(List.length(&2, Ca, rs), m, rs, Cam{False{}, m})

def cpu.arch_of(+m: String) -> String:
  String.concat([Cam.to(Ca.lookup(m, ca_table())), ",native"])

# ops_cpu.py:88, `len(parts:=device.split(':')) == 3`. `String.split` always
# answers at least one piece, so "" is one part and "a:b" is two. The row
# `cpu_remote_*` walks all six spellings.
def cpu.nparts(dev: String) -> U32: U32.from_nat(List.length(&2, String, String.split(dev, ':')))

def cpu.is_remote(dev: String) -> Bool: U32.is_eq(cpu.nparts(dev), 3)

# ops_cpu.py:89, `f"remote:{device[4:]}:0"` -- the peer group handed to
# `RemotePCIDevice`. `device[4:]` drops the literal `remot` prefix, so for
# `remote:host:1234` the rest is `e:host:1234` and the answer is
# `remote:e:host:1234:0`. That leading `e` is a real oddity of the source and
# the row pins it.
def cpu.remote_peer(dev: String) -> String:
  String.concat(["remote:", String.drop(dev, 4n), ":0"])

# ops_cpu.py:90, the four renderers, IN ORDER. `Compiled._select_renderer`
# walks this list and takes the first initialised one, so the order is the
# policy. Indices are 1..4 in the Python list order.
type Cr is Data:
  Cr{ix: U32, nm: String}

def Cr.nm(r: Cr) -> String:
  match r:
    case Cr{ix, nm}: nm

def cpu.renderers() -> List<&2, Cr>:
  [Cr{1, "ClangRenderer"}, Cr{2, "CPULLVMRenderer"}, Cr{3, "LVPRenderer"}, Cr{4, "X86Renderer"}]

# ops_cpu.py:84, `@property def has_copy_queue(self) -> bool: return False`.
# NULL does NOT override it, so the two rows differ and both are gateable.
def cpu.has_copy_queue() -> U32: 0

def nr.has_copy_queue() -> U32: 1

# ===========================================================================
# THE CPU CALL TAGS. One per seam call in ops_cpu.py, in the order the source
# first mentions them. `arg` is the ONE argument the port can carry for that
# call (a size, a flag, an address mask); everything else about the call is the
# seam's, and the header says so rather than inventing fields for it.
# ===========================================================================

# :21 the two `_load` arms, :26 LOAD_PROG, :30-36 the win32 chain.
def CALL_LOAD_RAW() -> U32: 1
def CALL_LOAD_JIT() -> U32: 2
def CALL_LOAD_PROG() -> U32: 3
def CALL_VIRTUAL_ALLOC() -> U32: 4
def CALL_MEMMOVE() -> U32: 5
def CALL_GET_PROCESS() -> U32: 6
def CALL_FLUSH_ICACHE() -> U32: 7
# :40 mmap, :41 mv_address, :44 the write, :56 CFUNCTYPE.
def CALL_MMAP() -> U32: 13
def CALL_MV_ADDRESS() -> U32: 14
def CALL_MEM_WRITE() -> U32: 15
def CALL_CFUNCTYPE() -> U32: 16
# :63 the remote RPC/POST pair, :65 the cpu_profile enter, :72 the call itself.
def CALL_RPC() -> U32: 17
def CALL_POST() -> U32: 18
def CALL_PROFILE() -> U32: 19
def CALL_FXN_LVP() -> U32: 20
def CALL_FXN() -> U32: 21
# :78 VirtualFree, :95 the remote PING.
def CALL_VIRTUAL_FREE() -> U32: 22
def CALL_PING() -> U32: 23
# ops_null.py:61 the EMULATE assert. It is the only call in either file whose
# FAILURE is a port decision rather than a hardware fact, so it gets a tag of
# its own and it is the one entry a gate can make vanish.
def CALL_ASSERT_EMULATE() -> U32: 24

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every device call in this file goes
# through it, so the trace is the ordered list of C calls the eventual seam
# makes. THE RAISE: once `refused` is set nothing else is recorded, which is
# `ops_null.py:61`'s `assert emu == ""` refusing to build a device -- and the
# failing assert IS still recorded, because it sets `refused` in the same breath
# and so on entry its own `refused` is still False. That is why a refusal shows
# up as a truncated trace needing no guard of its own.
# ===========================================================================

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

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE
# the emit, so ids are monotone in issue order. It is the LENGTH, not a field
# of its own: a second counter would need its own reset rule and nothing could
# observe that rule.
def Tr.here(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# `Bool.pick` evaluates BOTH arms, so the emitted call is a value built here and
# the guard is a parameter. This is the port's `raise`.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls, List.append(&2, Call, calls, [Call{k, arg}])),
     refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, refused}: Tr.emit.go(refused, k, arg, calls)

# an EMPTY trace, so a gate can read one program call without the init in front
# of it.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, refused}: Tr{Nil{}, refused}

# ===========================================================================
# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in
# order; `Tr.count` is how many there are; `Tr.has` is "contains this
# (tag, arg) sequence, in order".
# ===========================================================================

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside
# one of them would branch the walk twice over.
def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k), List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

# does the trace CONTAIN this (tag, arg) sequence, in order? `at` is how much of
# the pattern is matched so far, read out of the pattern BY INDEX rather than
# carried as a second list: the head and the tail of ONE destructure share a
# binder, and a descent may not use that binder twice.
#
# BOTH fields are compared, so a pattern pins the IDENTITY of each call and not
# only its kind.
#
# THE FUEL IS THE TRACE LENGTH AND THE ANSWER IS `at == patlen`. That is the
# whole matcher, and getting either half wrong makes it answer True to
# everything: with the fuel set to the PATTERN length, `case 0n:` fired after
# patlen trace entries and returned True{} without ever looking at `at`, so a
# reversed pattern matched. This is `ops_webgpu.bend`'s M23, its one documented
# BLIND SPOT, and it is fixed HERE from the start. MEASURED, though: the two
# REJECTION rows alone did NOT pin it (M56), because a matcher that is only
# asked to reject answers False for every fuel. `cpu_has_accepts_plain` and
# `cpu_has_accepts_lvp` are the rows that do -- a one-call pattern at index 1 of
# a two-call trace, which `len(pat)` fuel cannot reach.
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

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
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
def ncalls(k: U32, +t: Tr) -> U32: Tr.count(k, Tr.calls(t))
def seen(+t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def key(+t: Tr, k: U32) -> List<&2, U32>: Tr.args(k, Tr.calls(t))
# ===========================================================================
# THE CPU PROGRAM STATE. `ops_cpu.py:24` writes four attributes in one
# statement -- `self.dev, self.name, self.signature, self.profile_key` -- and
# `:25-26` add `lvp` and `fxn`. `signature` is a tuple of
# `(name, slot, dtype, shape)`; only the DTYPE itemsizes are read by anything
# (`TinyELF.iter_sig`), so `Prog.sig` is that list alone, exactly as
# `device.bend`'s `iter_sig` wants it. `osx` and `rt` are `OSX` and
# `'rt' in DLL._loaded_` -- two `getenv`/state reads, so two fixture fields,
# and they are the ONLY two facts that choose between the init branches.
# `elf` is the WALL 2 answer (`lib[:4] == ELFMAG`) and `liblen` is
# `len(obj.lib)`.
# ===========================================================================

type Prog is Data:
  Prog{name: String, sig: List<&2, U32>, lvp: Bool, elf: Bool, osx: Bool,
       rt: Bool, addr: U32, liblen: U32, t: Tr}

def Prog.of(name: String, sig: List<&2, U32>, lvp: Bool, elf: Bool, osx: Bool,
            rt: Bool, liblen: U32) -> Prog:
  Prog{name, sig, lvp, elf, osx, rt, 0, liblen, Tr.of()}

def Prog.t(p: Prog) -> Tr:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: t

def Prog.name(p: Prog) -> String:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: name

def Prog.sig(p: Prog) -> List<&2, U32>:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: sig

def Prog.lvp(p: Prog) -> Bool:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: lvp

def Prog.elf(p: Prog) -> Bool:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: elf

def Prog.osx(p: Prog) -> Bool:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: osx

def Prog.rt(p: Prog) -> Bool:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: rt

def Prog.addr(p: Prog) -> U32:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: addr

def Prog.liblen(p: Prog) -> U32:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}: liblen

# `Tr.here` read BEFORE the emit, so ids are monotone in issue order. Every
# step below mints exactly one handle, which is what makes `prog_init_ids`
# (a strictly increasing sequence) a real row and not a restatement.
def prog.at(p: Prog, addr: U32, k: U32, arg: U32) -> Prog:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, ad, liblen, t}:
      Prog{name, sig, lvp, elf, osx, rt, addr, liblen, Tr.emit(k, arg, t)}

# ops_cpu.py:26 -- the remote branch, `dev.remote.rpc(RemoteCmd.LOAD_PROG,
# len(obj.lib), payload=obj.lib)[0]`. It is FIRST in the source and it RETURNS,
# so on a remote host NOTHING ELSE in `__init__` happens: no mmap, no
# write-protect, no fxn. The three arms are mutually exclusive and the gate
# reads the trace LENGTH for each, which is the only way to see the
# exclusivity.
def prog.remote.at(lvp: Bool, p: Prog) -> Prog:
  match p:
    case Prog{name, sig, lv, elf, osx, rt, addr, +liblen, +t}:
      Prog{name, sig, lvp, elf, osx, rt, Tr.here(t), liblen,
           Tr.emit(CALL_LOAD_PROG(), liblen, t)}

# ops_cpu.py:28, `PAGE_EXECUTE_READWRITE, MEM_COMMIT, MEM_RESERVE = 0x40,
# 0x1000, 0x2000` and :31 the two are OR-ed, so the VirtualAlloc flags are
# 0x3040. The memmove's length is `len(loaded)`.
def cpu.page_xrw() -> U32: 64
def cpu.mem_commit() -> U32: 4096
def cpu.mem_reserve() -> U32: 8192
def cpu.wr_flags() -> U32: U32.or(U32.or(cpu.page_xrw(), cpu.mem_commit()), cpu.mem_reserve())

# ops_cpu.py:40 -- `mmap.mmap(-1, len(obj.lib), MAP_ANON|MAP_PRIVATE|(MAP_JIT
# if OSX else 0), PROT_READ|PROT_WRITE|PROT_EXEC)`. THE MAP SIZE IS `len(lib)`,
# not a page multiple: an mmap of a machine-code blob is exactly the blob's
# length. MAP_JIT is added only on OSX, so the flags differ by 0x800 there and
# the two flags are separate constants rather than one baked number.
def cpu.map_flags(osx: Bool) -> U32:
  Bool.pick(U32, osx,
    U32.or(U32.or(cpu.map_anon(), cpu.map_jit()), cpu.map_private()),
    U32.or(cpu.map_anon(), cpu.map_private()))

# ops_cpu.py:41 -- `self.addr = mv_address(self.mem)`. `mv_address` is
# `ctypes.addressof(ctypes.c_char.from_buffer(mv))`, a seam; what the port
# carries is the mint of the second handle, so `prog_init_ids` sees two
# increasing ids before the first conditional.
def prog.mmap(p: Prog) -> Prog:
  match p:
    case Prog{name, sig, lvp, elf, +osx, rt, addr, liblen, +t}:
      Prog{name, sig, lvp, elf, osx, rt, Tr.here(t), liblen,
           Tr.emit(CALL_MMAP(), cpu.map_flags(osx), t)}

def prog.address(+p: Prog) -> Prog:
  prog.at(p, Tr.here(Prog.t(p)), CALL_MV_ADDRESS(), Prog.liblen(p))

# ops_cpu.py:43 `pthread_jit_write_protect_np(False)` and :45 the same with
# `True`. TWO calls around the load+write and both only on OSX, so the trace
# grows by exactly two on OSX. The Bool argument is the seam's.
def CALL_WRITE_PROTECT_OFF() -> U32: 11
def CALL_WRITE_PROTECT_ON() -> U32: 12
def CALL_CLEAR_CACHE() -> U32: 9
def CALL_MSYNC() -> U32: 10

def prog.wp.off(+p: Prog) -> Prog: prog.at(p, Prog.addr(p), CALL_WRITE_PROTECT_OFF(), 0)
def prog.wp.on(+p: Prog) -> Prog: prog.at(p, Prog.addr(p), CALL_WRITE_PROTECT_ON(), 1)

# a `match` scrutinee must be a PARAMETER, so `if OSX:` is a `.at` whose Bool
# is handed in. TWO `.at`s and not one that does both, because Python writes
# `False` at :43 and `True` at :45 and they are TWO calls around ONE load+write
# -- an earlier version of this file paired them and every OSX trace came out
# four entries long instead of two. `cpu_init_osx_wp_n` is the row that saw it.
def prog.wp.off_at(osx: Bool, +p: Prog) -> Prog:
  match osx:
    case True{}: prog.wp.off(p)
    case False{}: p

def prog.wp.on_at(osx: Bool, +p: Prog) -> Prog:
  match osx:
    case True{}: prog.wp.on(p)
    case False{}: p

# ops_cpu.py:21, `_load` -- `lib if lib[:4] != libc.ELFMAG.encode() else
# jit_loader(lib, base=base, link_libs=[self.libm, self.rt_lib])`. The DECISION
# is WALL 2's Bool and the two arms are two trace tags. `link_libs` is
# `[self.libm, self.rt_lib]` -- TWO libraries, and both come from the class
# attribute at :19, which is why `cpu_rt_lib_name` is ported even though the
# loader itself is not.
def cpu.uses_jit_loader(elf: Bool) -> Bool: elf

def cpu.load_raw(elf: Bool) -> U32:
  Bool.pick(U32, elf, CALL_LOAD_JIT(), CALL_LOAD_RAW())

def prog.load.at(elf: Bool, +p: Prog) -> Prog:
  prog.at(p, Prog.addr(p), cpu.load_raw(elf), Prog.liblen(p))

# ops_cpu.py:44, `self.mem.write(loaded:=self._load(obj.lib, mv_address(self.mem)))`.
# The walrus means the LOAD happens INSIDE the write's argument, so the load's
# trace entry comes first. That ordering is not cosmetic: `_load` is what
# relocates, and the memory must not be written before it is relocated.
def prog.write(+p: Prog) -> Prog: prog.at(p, Prog.addr(p), CALL_MEM_WRITE(), Prog.liblen(p))

# ops_cpu.py:51-54 -- `if 'rt' in DLL._loaded_: rt_lib["__clear_cache"](addr,
# addr+len(loaded)) else: libc.msync(addr, len(loaded), MS_SYNC|MS_INVALIDATE)`.
# ONE call either way, with different tags and different second arguments: the
# clear_cache's RANGE END is `addr + len(loaded)` and msync's FLAGS are
# `MS_SYNC|MS_INVALIDATE`. Both ride on the trace entry as one U32, and the two
# differ in KIND -- an address against a flag mask -- which is the whole of what
# is portable here.
def prog.cache.at(rt: Bool, +addr: U32, +p: Prog) -> Prog:
  match rt:
    case True{}: prog.at(p, addr, CALL_CLEAR_CACHE(), addr)
    case False{}: prog.at(p, addr, CALL_MSYNC(), cpu.ms_flags())

# ops_cpu.py:56 -- `ctypes.CFUNCTYPE(None, ctypes.c_void_p)(self.addr) if self.lvp
# else ctypes.CFUNCTYPE(None)(self.addr)`. The LVP build takes an EXTRA
# `c_void_p` argument, so the arity is 2 on the LVP path and 1 otherwise. That
# is the only difference between the two branches and it is the arg on the
# entry.
def prog.fxn.at(lvp: Bool, +p: Prog) -> Prog:
  prog.at(p, Prog.addr(p), CALL_CFUNCTYPE(), Bool.to_u32(lvp))

# ops_cpu.py:27-36, `elif sys.platform == "win32":`. Its five seam calls are
# VirtualAlloc, memmove, GetCurrentProcess, FlushInstructionCache and then
# CFUNCTYPE, and it is a branch of `__init__` MUTUALLY EXCLUSIVE with the posix
# one, so the trace for a win32 program is five entries long and contains NO
# mmap at all. `PAGE_EXECUTE_READWRITE, MEM_COMMIT, MEM_RESERVE = 0x40, 0x1000,
# 0x2000` and the two flags are OR-ed on the VirtualAlloc.
def prog.win.at(lvp: Bool, +p: Prog) -> Prog:
  +p1: Prog = prog.at(p, Tr.here(Prog.t(p)), CALL_VIRTUAL_ALLOC(), cpu.wr_flags())
  +p2: Prog = prog.at(p1, Prog.addr(p1), CALL_MEMMOVE(), Prog.liblen(p1))
  +p3: Prog = prog.at(p2, Prog.addr(p2), CALL_GET_PROCESS(), 0)
  +p4: Prog = prog.at(p3, Prog.addr(p3), CALL_FLUSH_ICACHE(), Prog.liblen(p3))
  prog.fxn.at(lvp, p4)

# ===========================================================================
# ops_cpu.py:23-56 -- `__init__` as the step list it is. The order IS the
# source, and the two conditionals are the only branching.
# ===========================================================================

# THE POSIX HALF, as its own def, because `__init__` is an if/elif/else and
# only ONE of the three arms runs. Writing the chain here and letting
# `prog.posix.at` pick it is what makes that true in Bend: the chain GROWS the
# trace inside its OWN copy of `p`, so on the win32 arm the growth is discarded
# with the arm and `cpu_init_win_order` (five names, no MMAP) is the row that
# proves it.
def prog.posix(+p: Prog, +lvp: Bool, +elf: Bool, +osx: Bool, +rt: Bool) -> Prog:
  +p1: Prog = prog.mmap(p)
  +p2: Prog = prog.address(p1)
  +p3: Prog = prog.wp.off_at(osx, p2)
  +p4: Prog = prog.write(prog.load.at(elf, p3))
  +p5: Prog = prog.wp.on_at(osx, p4)
  +p6: Prog = prog.cache.at(rt, Prog.addr(p5), p5)
  prog.fxn.at(lvp, p6)

def prog.posix.at(local: Bool, +p: Prog, +lvp: Bool, +elf: Bool, +osx: Bool, +rt: Bool) -> Prog:
  Bool.pick(Prog, local, prog.posix(p, lvp, elf, osx, rt), p)

# :23-56 -- `__init__`. THREE arms, MUTUALLY EXCLUSIVE: the remote branch (:26),
# the win32 branch (:27-36) and the posix branch (:38-56), and `local` is "none
# of the first two". A `Prog` is `Data`, so each arm's growth is a copy and
# `Bool.pick` picks between finished values rather than between effects -- which
# is the one place this file's `Bool.pick` use is not reading like the others.
def prog.init(+nm: String, +sig: List<&2, U32>, +lvp: Bool, +elf: Bool, +osx: Bool,
              +rt: Bool, +remote: Bool, +win: Bool, liblen: U32) -> Prog:
  +p0: Prog = Prog.of(nm, sig, lvp, elf, osx, rt, liblen)
  +p1: Prog = Bool.pick(Prog, remote, prog.remote.at(lvp, p0), p0)
  +p2: Prog = Bool.pick(Prog, win, prog.win.at(lvp, p1), p1)
  prog.posix.at(Bool.not(Bool.or(remote, win)), p2, lvp, elf, osx, rt)

# ===========================================================================
# ===========================================================================
# ops_cpu.py:67-71 -- the LVP argument buffer, which is the one piece of
# `__call__` that is PURE INTEGER ARITHMETIC and therefore the one piece worth
# porting exactly.
#
#   lvp_args = bytearray(12 + (len(bufs) + len(vals)) * 8)
#   struct.pack_into(f'<3I{len(bufs)}Q', lvp_args, 0,
#                    *data64_le(addr+12), (len(bufs)+len(vals))*2, *bufs)
#   for v,(off,dt) in zip(vals, TinyELF.iter_sig(self.signature[-len(vals):],
#                                               len(bufs)*8)):
#     struct.pack_into(f'<{dt.fmt}', lvp_args, 12+off, v)
#   self.fxn(addr)
#
# So the header is THREE u32s -- the address+12 as a (lo, hi) pair from
# `data64_le` (helpers.py:81), then `(nbufs+nvals)*2` -- and the vals land at
# 12 + the offset `iter_sig` computes from `len(bufs)*8`. Four facts and each is
# its own row.
# ===========================================================================

# `args = [*bufs, *cast(tuple[int, ...], vals)]` is ONE list (:60), so every
# count in `__call__` is `nbufs + nvals` and the two branches cannot disagree
# about it. EVERY count below is this one def.
def prog.nargs(nbufs: U32, nvals: U32) -> U32: U32.add(nbufs, nvals)

# helpers.py:81, `data64_le(data) = (data & 0xFFFFFFFF, data >> 32)`. The
# address is a 64-bit number (WALL 1), so the port carries the 32-bit LOW word
# it can compute and answers the high word as the carry out of `lo + 12`, which
# is the only part of the pair that is nonzero for an address near 4 GiB.
def lvp.d64(lo: U32) -> List<&2, U32>: [lo, 0]

# :67, the bytearray length. 12 bytes of header plus 8 bytes per argument.
def lvp.size(nbufs: U32, nvals: U32) -> U32: U32.add(12, U32.mul(prog.nargs(nbufs, nvals), 8))

# :69, `(len(bufs)+len(vals))*2` -- the third header word. THE `*2` is because
# the val slots are 8 bytes each while `iter_sig` is handed `len(bufs)*8`, so
# the header counts WORDS-PAIRs and the base counts BYTES. `lvp_third` and
# `lvp_slots` disagree by a factor of four and that disagreement is the row.
def lvp.third(nbufs: U32, nvals: U32) -> U32: U32.mul(prog.nargs(nbufs, nvals), 2)

# :69-70 -- the val slot offsets, `TinyELF.iter_sig(self.signature[-len(vals):],
# len(bufs)*8)`, as offsets into `lvp_args`. The `[-len(vals):]` slice and the
# `len(bufs)*8` base are both decisions and both are rows. `D.isig.go` is
# device.bend's offset-carrying walk of the itemsize list, so the tail slice is
# this file's and the base is the second argument -- see OWED BACK, item 1.
def lvp.slots(+sig: List<&2, U32>, +nvals: Nat, nbufs: U32) -> List<&2, U32>:
  cn_walk(Nat.sub(List.length(&2, U32, sig), nvals),
          List.drop(&2, U32, sig, Nat.sub(List.length(&2, U32, sig), nvals)),
          U32.mul(nbufs, 8), Nil{})

# :70, `12+off` -- where a val's BYTES go. Not the bytes (WALL 3), the offset.
def lvp.at(off: U32) -> U32: U32.add(12, off)

# ===========================================================================
# ops_cpu.py:58-73 -- `__call__` as the step list it is.
#
# `args = [*bufs, *cast(tuple[int, ...], vals)]` is ONE list, so the two
# branches cannot disagree about the count: `len(args) == nbufs + nvals`
# everywhere. `remote._rpc if wait else remote._post` is the ONLY thing `wait`
# changes on the remote path and it changes the TAG, so `cpu_call_remote_tag` is
# the row that says wait decides synchrony. `float(unwrap(prof.en) - prof.st) *
# 1e-6 if wait else None` is the other: without `wait` the answer is None, and
# that is a decision with no arithmetic in it.
# ===========================================================================


# :63, `(remote._rpc if wait else remote._post)(...)`.
def prog.remote_tag(wait: Bool) -> U32:
  Bool.pick(U32, wait, CALL_RPC(), CALL_POST())

# :73, `return float(...) * 1e-6 if wait else None`. The ANSWER'S SHAPE is the
# decision: with `wait` there is a number and without it there is nothing. The
# number itself is two clock reads, so the VALUE is the seam's and only the
# shape is ported.
def prog.ret_is_none(wait: Bool) -> U32: Bool.pick(U32, wait, 0, 1)

# :63, the remote EXEC_PROG packet: `len(args)` and `int(wait)` are both on the
# wire, so the entry's arg is the count and the tag carries the wait.
def prog.call.remote(+p: Prog, nbufs: U32, nvals: U32, wait: Bool) -> Prog:
  prog.at(p, Prog.addr(p), prog.remote_tag(wait), prog.nargs(nbufs, nvals))

# :65, `with cpu_profile(self.name, self.dev.device, profile_key=...) as prof:`
# -- the context manager's ENTER. There is no EXIT entry: Python's `with` runs
# the body and `prof.en` is read at :73, and both halves of that are the clock
# seam. One entry for the enter is the whole of what the trace can see, and the
# NAME is `cpu_profile`'s first argument and it rides on `Prog.name`, not on the
# trace entry: the entry's `arg` is a U32 and a program name is a String, and
# the trace already pins which program a call belongs to by being inside one
# `Prog`.
def prog.profile(+p: Prog) -> Prog: prog.at(p, Prog.addr(p), CALL_PROFILE(), 0)

# :71, `self.fxn(addr)` -- the LVP call takes ONE pointer, the address of the
# argument bytearray. The entry's arg is the buffer LENGTH, which is
# `lvp.size` and not `nbufs + nvals`: the two differ by the 12-byte header and
# by the factor 8, and `cpu_call_lvp_arg` is the row that tells them apart.
# NOTE THE ARGUMENT POSITION. `prog.at(p, addr, k, arg)` puts `arg` FOURTH, and
# three of these builders had the size in the `addr` slot -- so every trace row
# that reads the entry's ARG read 0 while the ORDER rows stayed green. `addr` is
# the HANDLE and `arg` is the claim; the LVP size is the claim.
def prog.fxn.lvp(+p: Prog, nbufs: U32, nvals: U32) -> Prog:
  prog.at(p, Prog.addr(p), CALL_FXN_LVP(), lvp.size(nbufs, nvals))

# :72, `self.fxn(*[ctypes.c_uint64(x) for x in args])` -- the plain call. Each
# argument is widened to `c_uint64`, so the seam receives `nargs` 64-bit values
# and the count is the only portable fact. The entry's arg is that count.
def prog.fxn.plain(+p: Prog, nbufs: U32, nvals: U32) -> Prog:
  prog.at(p, Prog.addr(p), CALL_FXN(), prog.nargs(nbufs, nvals))

# the `with` BODY, one def because the two `if self.lvp` arms both live inside
# it and Python runs the PROFILE first on either.
def prog.call.local(+p: Prog, +nbufs: U32, +nvals: U32) -> Prog:
  +p1: Prog = prog.profile(p)
  Bool.pick(Prog, Prog.lvp(p1), prog.fxn.lvp(p1, nbufs, nvals), prog.fxn.plain(p1, nbufs, nvals))

# a `match` scrutinee must be a PARAMETER, so `if (remote:=...) is not None:` is
# a `.at` whose Bool is handed in.
def prog.call.at(+p: Prog, nbufs: U32, nvals: U32, wait: Bool, remote: Bool) -> Prog:
  match remote:
    case True{}: prog.call.remote(p, nbufs, nvals, wait)
    case False{}: prog.call.local(p, nbufs, nvals)

def prog.call(+p: Prog, nbufs: U32, nvals: U32, wait: Bool, remote: Bool) -> Prog:
  prog.call.at(p, nbufs, nvals, wait, remote)

# ===========================================================================
# ops_cpu.py:75-78 -- `__del__`, the ONLY teardown either backend has, and it
# is a CONJUNCTION: `if self.dev.remote is None and sys.platform == 'win32'`.
# A remote device's pages belong to the remote and a posix device's belong to
# its mmap, so VirtualFree fires on exactly one platform and only when there is
# no remote -- `prog_del_win_free` is the two-cell matrix and all four cells
# are rows.
# ===========================================================================

def prog.del.at(remote: Bool, win: Bool, +p: Prog) -> Prog:
  match remote win:
    case False{} True{} : prog.at(p, 0, CALL_VIRTUAL_FREE(), cpu.mem_release())
    case _ _            : p

def prog.del(remote: Bool, win: Bool, +p: Prog) -> Prog: prog.del.at(remote, win, p)

# ===========================================================================
# ops_cpu.py:80-96 -- `CPUDevice`, and it is the SMALLEST device in tinygrad:
# eight attributes, one `if`, one `super().__init__` and one `if` again.
#
# Everything it does NOT do is inherited and owned by device.bend: the
# allocator (`HostAllocator`), the device-id parse, the timeline, the three
# `pm_bufferize` rules and `synchronize`. What is here is what ops_cpu.py
# itself writes, and that is one arch string, one renderer list, one bool, one
# int and the peer-group choice.
# ===========================================================================

type Cpu is Data:
  Cpu{dev: String, arch: String, remote: Bool, peer: String,
      renders: List<&2, Cr>, dev_id: U32, t: Tr}

def Cpu.dev(c: Cpu) -> String:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: dev

def Cpu.arch(c: Cpu) -> String:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: arch

def Cpu.remote(c: Cpu) -> Bool:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: remote

def Cpu.peer(c: Cpu) -> String:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: peer

def Cpu.renders(c: Cpu) -> List<&2, Cr>:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: renders

def Cpu.dev_id(c: Cpu) -> U32:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: dev_id

def Cpu.t(c: Cpu) -> Tr:
  match c:
    case Cpu{dev, arch, remote, peer, renders, dev_id, t}: t

# :89, `RemotePCIDevice("CPU", f"remote:{device[4:]}:0", connect(parts[1],
# int(parts[2])))`. The CONNECT is a socket seam and the port is WALL 3's
# decimal parse; what is here is the CONNECT itself as a trace entry and the
# peer-group string, which is the half a caller reads.
def CALL_CONNECT() -> U32: 25

# :92, `if self.remote is not None: self.peer_group = self.remote.peer_group`.
# THE OTHER ARM IS INHERITED: `Compiled.__init__` (device.py:398) sets
# `peer_group = getattr(getattr(self,'iface',None),'peer_group',
# device.split(":")[0])`, and a CPU device with no remote and no iface answers its
# own device-class prefix -- MEASURED, `Device['CPU:1'].peer_group == 'CPU'`. So
# the two arms are `remote:...` and `head(dev)`, and `cpu_peer_*` covers both.
def cpu.peer.at(remote: Bool, dev: String, got: String) -> String:
  match remote:
    case True{}: cpu.remote_peer(dev)
    case False{}: got

def cpu.peer_of(remote: Bool, +dev: String) -> String:
  cpu.peer.at(remote, dev, D.head(dev))

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
def cpu.init(+dev: String, +machine: String) -> Cpu:
  +rm: Bool = cpu.is_remote(dev)
  Cpu{dev, cpu.arch_of(machine), rm, cpu.peer_of(rm, dev), cpu.renderers(),
      D.dev_id(dev),
      Bool.pick(Tr, rm, Tr.emit(CALL_CONNECT(), cpu.nparts(dev), Tr.of()), Tr.of())}

# :95, `if self.remote is not None: self.remote.rpc(RemoteCmd.PING)` and then
# `super().synchronize(timeout)`. The PING is a trace entry; the super is
# device.bend's timeline wait and is a seam. `cpu_sync_ping` and
# `cpu_sync_noping` are the two cells and both are rows, because a port that
# always pinged would still satisfy every non-remote fixture.
def cpu.synchronize.at(remote: Bool, +c: Cpu) -> Cpu:
  match remote:
    case True{}:
      Cpu{Cpu.dev(c), Cpu.arch(c), Cpu.remote(c), Cpu.peer(c), Cpu.renders(c),
          Cpu.dev_id(c), Tr.emit(CALL_PING(), 0, Cpu.t(c))}
    case False{}: c

def cpu.synchronize(remote: Bool, c: Cpu) -> Cpu: cpu.synchronize.at(remote, c)

# ===========================================================================
# ops_null.py -- THE DEGENERATE BACKEND.
#
# Everything below is either an INTEGER the queue lays down or a DECISION about
# whether to lay it down. There is no arithmetic on results, no shader, no
# compiler and no synchronisation, and the header's WALL 4 says so rather than
# inventing one.
#
# `NullQueue.q` (hcq2.py:366) writes each word LITTLE-ENDIAN and pads a UOp with
# its own bytes, and `HWQueue.blob` accumulates them -- that is the one place
# the words become bytes and it is a seam. What survives the crossing is the
# SHAPE: how many words per command, what each position means, and which of the
# five ops pads.
# ===========================================================================

# ops_null.py:21, `EXEC, COPY, WAIT, STORE, TIMESTAMP = range(5)`. Five tags,
# zero-based, and the tag is word 0 of every command.
def NEXEC() -> U32: 0
def NCOPY() -> U32: 1
def NWAIT() -> U32: 2
def NSTORE() -> U32: 3
def NTIMESTAMP() -> U32: 4

# ===========================================================================
# ops_null.py:25, `def cmd(self, op, *args): self.q(*[... for a in (op, *args,
# 0, 0, 0)][:4])`. THREE FACTS AND ALL THREE ARE THE FILE:
#
#   1. the tuple is (op, *args, 0, 0, 0) -- THREE trailing zeros, so a command
#      with one argument is padded by two and one with two is padded by one;
#   2. the slice is [:4], so the length is ALWAYS FOUR and an over-long argument
#      list is TRUNCATED, not extended;
#   3. word 0 is the op and the args follow in order, so a two-argument command
#      has its second argument in word 2 and its PAD in word 3.
#
# (1) is `nr.pads` and (2) is `nr.words`, and they are separate because they are
# separate facts: a port that padded correctly and emitted five words would pass
# `nr_pads_*` and fail `nr_words`.
# ===========================================================================

# THE ARITY OF EACH `cmd` CALL SITE, as a `U32` literal ladder in DESCENDING
# order (bend2-constraints.md, tc_ptx rule 4: an ascending ladder makes every
# arm after `case 0:` dead code that still typechecks).
def nr.nargs(op: U32) -> U32:
  match op:
    case 4: 1
    case 3: 2
    case 2: 3
    case 1: 3
    case _: 3

# (1) -- the pads are `3 - arity`, because the tuple has three zeros and the
# slice keeps the first four.
def nr.pads(op: U32) -> U32: U32.sub(3, nr.nargs(op))

# (2) and (3) -- the argument of one `cmd` call, as the four words `q` receives.
# The three arg SLOTS are parameters rather than a list because the call sites
# have different arities and a list would have to be sliced at every one of them.
def nr.words(op: U32, a0: U32, a1: U32, a2: U32) -> List<&2, U32>: [op, a0, a1, a2]

# ops_null.py:30, `self.cmd(EXEC, kernargs, len(args), self.event(...))`.
def nr.exec(kernargs: U32, nargs: U32, ev: U32) -> List<&2, U32>:
  nr.words(NEXEC(), kernargs, nargs, ev)

# ops_null.py:31, `self.cmd(COPY, dst, src, self.event(...))`.
def nr.copy(dst: U32, src: U32, ev: U32) -> List<&2, U32>: nr.words(NCOPY(), dst, src, ev)

# ops_null.py:32, `self.cmd(WAIT, signal, value, int(eq))` -- `int(eq)` is a
# Bool widened, and it is the LAST word, so `eq` never collides with a pad.
def nr.wait(sig: U32, val: U32, eq: Bool) -> List<&2, U32>:
  nr.words(NWAIT(), sig, val, Bool.to_u32(eq))

# ops_null.py:33, `self.cmd(STORE, signal, value)` -- TWO args, so ONE pad, and
# the pad is word 3. That the pad is a CONSTANT ZERO and `value` may also be zero
# is why the gate reads the arity rather than counting zero words.
def nr.signal(sig: U32, val: U32) -> List<&2, U32>: nr.words(NSTORE(), sig, val, 0)

# ops_null.py:34, `self.cmd(TIMESTAMP, signal.getaddr(self.devs) +
# UOp.const(8, dtypes.u64))` -- ONE arg, so TWO pads. The `+ 8` is the
# timeline's VALUE slot (`timeline` is `Buffer(dev, 2, uint64)`) and it is the
# only arithmetic in the file.
def nr.timestamp(addr: U32) -> List<&2, U32>: nr.words(NTIMESTAMP(), U32.add(addr, 8), 0, 0)

# ops_null.py:31, the two event-key strings. They are USER-VISIBLE -- they are
# the device and name a profile graph entry carries -- and they are the only two
# strings in the file.
def nr.copy_dev(src_dev: String) -> String: String.concat([src_dev, ":SDMA:0"])
def nr.copy_name(+src_dev: String, +dst_dev: String) -> String:
  String.concat([src_dev, " -> ", dst_dev])

# ops_null.py:35, `submit` returns
#   `UOp.placeholder((1,), uint8, device=devs, tag="doorbell").index(0).store(
#      cmdbuf.index(0).load())`.
# SEVEN nodes, MEASURED by running that expression in CPython, and the op
# sequence in toposort order is the shape: PARAM (the doorbell placeholder,
# which `UOp.placeholder` IS), CONST 0, INDEX, PARAM (the cmdbuf), INDEX, LOAD,
# STORE. The root is a void STORE. Seven nodes and one op sequence is what a
# reader of a NULL trace needs and nothing here is a wall.
type Sub is Data:
  Sub{ix: U32, nm: String}

def Sub.nm(r: Sub) -> String:
  match r:
    case Sub{ix, nm}: nm

def nr.submit_graph() -> List<&2, Sub>:
  [Sub{1, "PARAM"}, Sub{2, "CONST"}, Sub{3, "INDEX"}, Sub{4, "PARAM"},
   Sub{5, "INDEX"}, Sub{6, "LOAD"}, Sub{7, "STORE"}]

# ===========================================================================
# ops_null.py:22 and :26 -- `null_events` and `event`. A process-global dict
# keyed by `(device, name, key)` and `setdefault`'d with `len(null_events)`, so
# AN EVENT'S ID IS ITS FIRST-APPEARANCE INDEX and two events with the same key
# share one id. `key` is `bytes | None` and only identity matters, so the port
# carries it as a U32 with 0 meaning None.
#
# First-wins over the table, and the ANSWER and the LIST both come back, so the
# accumulator is a record: `Ev.lookup` needs the id and `Ev.put` needs the
# grown list, and both read the same walk.
# ===========================================================================

type Nk is Data:
  Nk{dev: String, nm: String, key: U32}

def Nk.dev(x: Nk) -> String:
  match x:
    case Nk{dev, nm, key}: dev

def Nk.nm(x: Nk) -> String:
  match x:
    case Nk{dev, nm, key}: nm

def Nk.key(x: Nk) -> U32:
  match x:
    case Nk{dev, nm, key}: key

# `(device, name, key)` equality -- all THREE, and the third is the one a
# two-field comparison drops. A profile KEY distinguishes two executions of the
# SAME kernel, so a port that compared only (device, name) would merge them.
def Nk.same(+a: Nk, +b: Nk) -> Bool:
  Bool.and(Bool.and(String.eq(Nk.dev(a), Nk.dev(b)), String.eq(Nk.nm(a), Nk.nm(b))),
           U32.is_eq(Nk.key(a), Nk.key(b)))

type EvA is Data:
  EvA{hit: Bool, id: U32, evs: List<&2, Nk>}

def EvA.hit(a: EvA) -> Bool:
  match a:
    case EvA{hit, id, evs}: hit

def EvA.id(a: EvA) -> U32:
  match a:
    case EvA{hit, id, evs}: id

def EvA.evs(a: EvA) -> List<&2, Nk>:
  match a:
    case EvA{hit, id, evs}: evs

# ONCE a key is found the walk must NOT record a later equal one, or the id
# would be the LAST hit rather than the first. `hit` rides on the accumulator
# for exactly that. MEASURED (M28): flipping it to last-wins moves NO row, and
# it cannot: `Nk.same` IS Python's tuple equality on `(device, name, key)`,
# `null_events` is a dict so it never holds two equal keys, and `Ev.put` -- the
# only inserter, and pinned by M29's five rows -- appends on a miss only. So
# "no equal pair in the table" is an invariant, and the fold is a redundancy
# the dict makes unreachable, not a behaviour the gate is missing. The key being
# examined is `k` (a walk binder) and the key being SOUGHT is `want`, so
# `Nk.same` never has to read the list back by index.
def EvA.step(want: Nk, k: Nk, at: U32, acc: EvA) -> EvA:
  match acc:
    case EvA{+hit, +id, +evs}:
      Bool.pick(EvA, hit, acc, Bool.pick(EvA, Nk.same(k, want), EvA{True{}, at, evs}, acc))

def EvA.go(n: Nat, ks: List<&2, Nk>, +want: Nk, +at: U32, acc: EvA) -> EvA:
  match n:
    case 0n: acc
    case 1n+p:
      match ks:
        case Nil{}: acc
        case h <> t: EvA.go(p, t, want, U32.add(at, 1), EvA.step(want, h, at, acc))

def Ev.walk(want: Nk, +evs: List<&2, Nk>) -> EvA:
  EvA.go(List.length(&2, Nk, evs), evs, want, 0, EvA{False{}, U32.from_nat(List.length(&2, Nk, evs)), evs})

# `null_events.setdefault(key, len(null_events))` -- the id a MISS returns, which
# is also the slot the key would take.
def Ev.lookup(+k: Nk, evs: List<&2, Nk>) -> U32: EvA.id(Ev.walk(k, evs))

# `setdefault` on a MISS INSERTS, so the list grows by one. A hit does not.
def Ev.put(+k: Nk, +evs: List<&2, Nk>) -> List<&2, Nk>:
  Bool.pick(List<&2, Nk>, EvA.hit(Ev.walk(k, evs)), evs,
    List.append(&2, Nk, evs, [k]))

# ===========================================================================
# hcq2.py:78-83, `pack_args`, which is what ops_null.py:29 builds the kernargs
# LINEAR from. It is the only REAL ARITHMETIC in the NULL backend and the only
# place its queue has a layout:
#
#   for offset, arg in sorted(args, key=lambda x: x[0]):
#     words += [UOp(Ops.BINARY, arg=bytes(offset - end)), arg] if offset != end
#              else [arg]
#     end = offset + arg.dtype.itemsize
#   return words + [UOp(Ops.BINARY, arg=bytes(size - end))]
#
# and the SIZE is ops_null.py:29's `8 * max(len(args), 1)`. MEASURED over five
# arg lists:
#
#   itemsizes  size  offsets   nsrc  tail bytes
#   [4]          8      [0]        2         4
#   [4,4]       16     [0,4]       3         8
#   [4,4,4]     24     [0,4,8]     4        12
#   [8,4]       16     [0,8]       3         4
#   [8,8]       16     [0,8]       3         0
#
# TWO facts fall out and they are independent: the LINEAR has `nargs + 1` srcs
# one TAIL BINARY always, PLUS one per interior gap, and the tail's byte count
# is `size - end`. The interior count is zero for five of the seven MEASURED
# layouts and ONE for `[4,8,4]`, because a 1-byte argument between two 4-byte
# ones makes `layout_args` place the third at slot 8 rather than slot 5.
# ===========================================================================

# :29, `8 * max(len(args), 1)`. The `max` matters for the EMPTY call and only
# for it -- a zero-argument kernel is the one case where `size` is not 0.
def pk.size(+nargs: U32) -> U32: U32.mul(Bool.pick(U32, U32.is_zero(nargs), 1, nargs), 8)

# one TAIL BINARY, one entry per argument, and one BINARY per INTERIOR GAP.
# `nargs + 1` is right for every CONTIGUOUS layout and wrong by the pad count
# otherwise -- and `[4,8,4]` is the one MEASURED layout that is not contiguous,
# at `pk_pads_484` / `pk_nsrc_484`.
def pk.nsrc(nargs: U32, pads: U32) -> U32: U32.add(U32.add(nargs, 1), pads)

# the tail's byte count, `bytes(size - end)` with `end` the running sum of
# itemsizes. A NEGATIVE tail is impossible for a signature whose itemsizes sum
# to at most `8*nargs`, and the `[8,8]` row is the one where the tail is zero --
# `bytes(0)` is a real BINARY node with an empty arg, which is why
# `pk_tail_88` is 0 and not "absent".
def pk.tail(nargs: U32, end: U32) -> U32: U32.sub(pk.size(nargs), end)

# the interior-pad count, which is the port of hcq2.py:81's `if offset != end`:
# it counts the offsets that are NOT contiguous with the running end. FIVE of the
# SEVEN measured layouts give 0 and `[4,8,4]` gives 1, because a 1-byte argument
# between two 4-byte ones makes `layout_args` place the third at slot 8 rather
# than slot 5. A pad count that was CONSTANT zero would pass six rows and fail
# the seventh, so `pk_pads_484` is the row that makes the count vary.
def pk.pads.go(n: Nat, ks: List<&2, U32>, +off: U32, end: U32, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ks:
        case Nil{}: acc
        case s <> t:
          +r: Cn = cn_slot(off, s)
          pk.pads.go(p, t, Cn.next(r), Cn.next(r),
            U32.add(acc, Bool.to_u32(Bool.not(U32.is_eq(Cn.at(r), end)))))

def pk.pads(+ks: List<&2, U32>) -> U32: pk.pads.go(List.length(&2, U32, ks), ks, 0, 0, 0)

# ===========================================================================
# ops_null.py:38-46 -- `NullProgram`, the emulated executor. It is FORTY-EIGHT
# lines of Python and every one of them is a fold over the command words:
#
#   :38  streams = [(i, prod(s)) for i,(n,_,_,s) in enumerate(obj.signature)
#                  if (n or "").startswith("cmdbuf")]
#   :40  st, words = perf_counter_us(), [w for i,n in self.streams
#                                       for w in MMIOInterface(bufs[i], n, fmt='Q')[:]]
#   :42  for op, addr, done in zip(words[0::4], words[1::4],
#                                 itertools.accumulate(op in (EXEC, COPY)
#                                                     for op in words[0::4])):
#          if op == TIMESTAMP: MMIOInterface(addr,8,fmt='Q')[0] = int((st+done)*1000)
#   :44  descs = [list(null_events)[event] for op, event in zip(words[0::4],
#                  words[3::4]) if op in (EXEC, COPY)] if PROFILE else []
#   :45  sigs = [st + sum(x[0]==d[0] for x in descs[:i]) + k
#                for i,d in enumerate(descs) for k in (0,1)]
#   :46  if descs: cpu_events.append(ProfileGraphEvent(...))
#
# So the four words of a quad are (op, addr, value, event), the emulated clock
# is `st + done` where `done` is the running count of EXEC-or-COPY commands, and
# the profile lane of an entry is its device's OWN ordinal. `st` is INJECTED --
# `perf_counter_us` is a seam and a gate may not read a clock.
# ===========================================================================

# :38 -- one SIGNATURE ENTRY, and only the three fields the comprehension reads:
# the index `i`, the name `n` and the shape product `prod(s)`. `prod(())` is 1,
# so `nbytes` is never 0 for a real entry and 0 is free to mean "no stream".
type Sg is Data:
  Sg{ix: U32, nm: String, sz: U32}

# the two answers `streams` gives: the byte total (which is what the Q-word
# count is derived from) and the `(index, bytes)` pairs IN ORDER. `List.append`
# is `xs ++ ys`, so the walk APPENDS and the pairs come out in signature order --
# the opposite choice reverses them and `nprog_streams` is the row that dies.
type St is Data:
  St{nbytes: U32, pairs: List<&2, U32>}

def St.nbytes(s: St) -> U32:
  match s:
    case St{nbytes, pairs}: nbytes

def St.pairs(s: St) -> List<&2, U32>:
  match s:
    case St{nbytes, pairs}: pairs

# `(n or "")` -- a signature name is `str | None` and `None` reads as the empty
# string, which is the one thing that makes `.startswith` total.
def Sg.is_stream(nm: String) -> Bool: String.starts_with(nm, "cmdbuf")

def nprog.streams.go(n: Nat, xs: List<&2, Sg>, +nb: U32, +ps: List<&2, U32>) -> St:
  match n:
    case 0n: St{nb, ps}
    case 1n+p:
      match xs:
        case Nil{}: St{nb, ps}
        case Sg{ix, +nm, +sz} <> t:
          nprog.streams.go(p, t,
            Bool.pick(U32, Sg.is_stream(nm), U32.add(nb, sz), nb),
            Bool.pick(List<&2, U32>, Sg.is_stream(nm),
              List.append(&2, U32, ps, [ix, sz]), ps))

def nprog.streams(+xs: List<&2, Sg>) -> St:
  nprog.streams.go(List.length(&2, Sg, xs), xs, 0, Nil{})

# :40 -- `MMIOInterface(bufs[i], n, fmt='Q')` reads `n` BYTES as Q words, so the
# word count is `n / 8`. It is `/` and not `n`: `n` is `prod(shape)` and the
# shape is in BYTES, which is the one place the two units meet.
def nprog.qwords(nbytes: U32) -> U32: U32.div(nbytes, 8)

# the quad count is the number of FOUR-word groups, which is the stream's Q
# words over four -- and it is `U32.div`, not the byte count, because a word list
# IS already in words.
def nprog.quads(+ws: List<&2, U32>) -> U32: U32.div(U32.from_nat(List.length(&2, U32, ws)), 4)

# :42 -- the accumulate. `itertools.accumulate(op in (EXEC, COPY) for op in
# words[0::4])` is a PREFIX COUNT of the EXEC-or-COPY commands, inclusive of the
# current one, so the first quad's `done` is 1 when the quad is an EXEC. This is
# the fold that has to be a fold and not a `List.get`: the value at quad `i`
# depends on all `i` of them.
def nprog.is_work(+op: U32) -> Bool:
  Bool.or(U32.is_eq(op, NEXEC()), U32.is_eq(op, NCOPY()))

def nprog.done.go(n: Nat, ws: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t:
          nprog.done.go(p, List.drop(&2, U32, t, 3n),
            U32.add(acc, Bool.to_u32(nprog.is_work(h))))

# THE FUEL IS `quads + 1`, because `itertools.accumulate` answers element `i` with
# the sum of elements `0..i` INCLUSIVE and this fold returns the accumulator after
# `n` steps. `nprog_done_at_2` came out 0 where CPython says 1, and the COPY that
# makes it 1 is quad 2 -- the row that found the off-by-one. `nprog_done_sum` is
# the same fold over every quad, so it asks for `quads + 1` there too.
def nprog.done_at(+ws: List<&2, U32>, quads: Nat) -> U32:
  nprog.done.go(Nat.add(quads, 1n), ws, 0)

# :42-43 -- `if op == TIMESTAMP: MMIOInterface(addr,8,fmt='Q')[0] =
# int((st+done)*1000)`. The WRITE COUNT is the number of TIMESTAMP commands and
# that is the whole of WALL 4's claim: on a stream with none, the emulated device
# writes NOTHING and every kernel result is whatever the buffer already held.
def nprog.stamp.go(n: Nat, ws: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t: nprog.stamp.go(p, List.drop(&2, U32, t, 3n),
          U32.add(acc, Bool.to_u32(U32.is_eq(h, NTIMESTAMP()))))

# THE WRITE COUNT over a whole stream: the number of TIMESTAMP commands among
# the quads the stream actually has. `nprog.quads` is the number of FOUR-word
# groups, which is the stream's Q words over four -- and it is `U32.div`, not
# the byte count, because a word list IS already in words.
def nprog.writes(+ws: List<&2, U32>) -> U32: nprog.stamp.go(U32.to_nat(nprog.quads(ws)), ws, 0)

# `int((st+done)*1000)` -- microseconds to nanoseconds. `st` is injected.
def nprog.stamp_val(st: U32, done: U32) -> U32: U32.mul(U32.add(st, done), 1000)

# :44 -- `descs = [list(null_events)[event] for op, event in zip(words[0::4],
# words[3::4]) if op in (EXEC, COPY)]`. TWO folds: one over the quads keeping the
# event IDs, one over those IDs projecting each to its KEY'S DEVICE. The device
# is the only part the NEXT line reads (`x[0]`), so projecting here rather than
# carrying `Nk` saves a fold and loses nothing.
# word 3 of the quad `ws` starts at.
def nprog.word_at(+ws: List<&2, U32>, k: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, List.drop(&2, U32, ws, U32.to_nat(k)), 0n), 0)

# the projection `list(null_events)[event]`, i.e. the KEY at that slot.
def nprog.dev_at.of(m: Maybe<&2, Nk>) -> String:
  match m:
    case Some{+k}: Nk.dev(k)
    case None{}: ""

# `list(null_events)[event]` -- the KEY at that slot. An id past the end is the
# empty device, which is Python's `IndexError` reduced to the one thing a fold
# can carry; no real stream reaches it because every event word is an id the
# queue interned on the way in.
def nprog.dev_at(+evs: List<&2, Nk>, i: U32) -> String:
  nprog.dev_at.of(List.get(&2, Nk, evs, U32.to_nat(i)))

def nprog.devs.go(n: Nat, +ws: List<&2, U32>, +evs: List<&2, Nk>,
                   +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t:
          nprog.devs.go(p, List.drop(&2, U32, t, 3n), evs,
            Bool.pick(List<&2, String>, nprog.is_work(h),
              List.append(&2, String, acc, [nprog.dev_at(evs, nprog.word_at(ws, 3))]), acc))

def nprog.descs(+ws: List<&2, U32>, +evs: List<&2, Nk>) -> List<&2, String>:
  nprog.devs.go(U32.to_nat(nprog.quads(ws)), ws, evs, Nil{})

# :45 -- `sum(x[0]==d[0] for x in descs[:i])`, the number of EARLIER profile
# entries on the SAME DEVICE. This is the per-device lane: two entries on
# different devices share a base and two on the same device do not. The
# `[i]` is the CURRENT entry, never the whole list -- an accumulator that read
# the whole list would answer `len(descs)` for every entry and every sig would
# be `st + len(descs) + k`, which is a plausible string and a wrong graph.
def nprog.lane.go(n: Nat, +d: String, ds: List<&2, String>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ds:
        case Nil{}: acc
        case x <> t: nprog.lane.go(p, d, t, U32.add(acc, Bool.to_u32(String.eq(x, d))))

def nprog.dev_at_list.of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{+d}: d
    case None{}: ""

def nprog.dev_at_list(ds: List<&2, String>, i: Nat) -> String:
  nprog.dev_at_list.of(List.get(&2, String, ds, i))

def nprog.lane(+ds: List<&2, String>, +i: Nat) -> U32:
  nprog.lane.go(i, nprog.dev_at_list(ds, i), ds, 0)

# :45 -- the sigs, two per entry: `st + lane(i) + k for k in (0,1)`. They are
# PAIRED, so the gate reads a flat list of 2*len(descs) numbers and the pair
# structure is the row that checks it.
def nprog.sig_one(st: U32, lane: U32, k: U32) -> U32: U32.add(U32.add(st, lane), k)

# THE INDEX IS A PARAMETER AND THE LIST IS NEVER MATCHED. The first version read
# `i` out of `len(acc)/2` and matched on `ds` in the same arm -- and
# `case h <> t:` SPENDS its scrutinee, so `nprog.lane(ds, i)` was handed a spent
# list, `nprog.dev_at_list` answered "" for every entry and every lane was 0.
# `nprog_sigs_same` came out 1000,1001,1001,1002,1000,1001: the first two entries
# right and every later one wrong. The fuel IS the length, so there is nothing to
# walk and nothing to spend.
def nprog.sigs.go(n: Nat, +ds: List<&2, String>, +st: U32, +acc: List<&2, U32>,
                  +i: U32) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      +ln: U32 = nprog.lane(ds, U32.to_nat(i))
      nprog.sigs.go(p, ds, st,
        List.append(&2, U32, List.append(&2, U32, acc, [nprog.sig_one(st, ln, 0)]),
          [nprog.sig_one(st, ln, 1)]), U32.add(i, 1))

def nprog.sigs(+st: U32, +ds: List<&2, String>) -> List<&2, U32>:
  nprog.sigs.go(List.length(&2, String, ds), ds, st, Nil{}, 0)

# :46 -- `[ProfileGraphEntry(d, n, 2*i, 2*i+1, k) for i,(d,n,k) in
# enumerate(descs)]`, so the entry ids are 2i and 2i+1 and they are the same
# numbers `sigs` is indexed by.
def nprog.ent_ids(+i: U32) -> List<&2, U32>: [U32.mul(i, 2), U32.add(U32.mul(i, 2), 1)]

# THE SIGNATURE MEASURED ON THE REAL NULL DEVICE (DEV=NULL, DEBUG=3): seven
# entries, itemsizes [8,1,8,1,8,1,1], two of them named `cmdbuf_*` at indices 3
# and 5 with 160 and 224 bytes. The fixture is this list and nothing else.
def nprog.sig7() -> List<&2, Sg>:
  [Sg{0, "slots_0", 14}, Sg{1, "doorbell_1", 256}, Sg{2, "timeline_2", 2},
   Sg{3, "cmdbuf_copy_0_3", 160}, Sg{4, "inputs_4", 3},
   Sg{5, "cmdbuf_compute_0_5", 224}, Sg{6, "kernargs_compute_0_6", 16}]

# ===========================================================================
# ops_null.py:48-52 -- `NullAllocator`. FOUR lines of source and the only 64-BIT
# arithmetic in either file.
#
#   def _alloc(self, size, options, va=itertools.count(1 << 40, 1 << 32)):
#     return BufferStorage(next(va))
#   def _copyin(self, dest, src): pass
#   def _copyout(self, dest, src): NULL_ALLOW_COPYOUT or panic(RuntimeError, "no copyout on NULL")
#   def _map(self, buf): return BufferStorage(buf._buf if buf.device.startswith("NULL") else buf.host.addr)
#
# `va` is a DEFAULT ARGUMENT, so the counter is created ONCE per `NullAllocator`
# class and every `_alloc` in the process draws from the SAME sequence. That is
# why the addresses are monotone and not per-call, and MEASURED over three real
# allocations: 1099511627776, 1103806595072, 1108101562368.
# ===========================================================================

# `1 << 40` AND `1 << 32` ARE NOT `Nat` LITERALS -- a `Nat` literal is capped at
# 4294967295n (MEASURED) -- so each is a product of two halves that are under
# the cap. 1024 * (1 << 30) and 2 * (1 << 31). The ANSWERS are the rows
# `nva_base` and `nva_step`.
def nva.base() -> Nat: Nat.mul(1024n, 1073741824n)
def nva.step() -> Nat: Nat.mul(2n, 2147483648n)

# `next(va)` k times. `k` is the ALLOCATION ORDINAL, and the port carries it as
# a `Nat` because the answer does not fit in a `U32` -- which is the one place
# WALL 1 does not bite, and it is worth a row (`nva_step_1`) to say so.
def nalloc.va(k: Nat) -> Nat: Nat.add(nva.base(), Nat.mul(k, nva.step()))

# :51, `NULL_ALLOW_COPYOUT or panic(RuntimeError, "no copyout on NULL")`. THE
# PANIC IS THE ANSWER: with the flag unset `_copyout` raises, and the message is
# user-visible, so it is a constant here and a row. `nalloc.copyout_ok` answers
# whether the write is allowed at all.
def nalloc.copyout_msg() -> String: "no copyout on NULL"

def nalloc.copyout_ok(allow: U32) -> U32: Bool.to_u32(Bool.not(U32.is_zero(allow)))

# :50, `def _copyin(self, dest, src): pass`. The function is a no-op, so the
# number of bytes it moves is the whole of it -- and it is ZERO, which is how a
# NULL upload leaves the destination untouched and every kernel result is
# whatever the buffer already held (WALL 4).
def nalloc.copyin_nops() -> U32: 0

# :52, `buf._buf if buf.device.startswith("NULL") else buf.host.addr`. A NULL
# buffer's OWN storage address is the mapping; anything else has to come from
# the host allocator, and on a remote node that is a different address. The test
# is `startswith("NULL")` and not equality, so `NULL:1` and `NULL` both map
# themselves -- `nr_map_*` walks four spellings.
def nalloc.map_is_null(dev: String) -> Bool: String.starts_with(dev, "NULL")

# ===========================================================================
# ops_null.py:11-19 -- `NullRenderer`. Four attributes and TWO code_for_op
# overrides, and the overrides are the file's only STRING-BUILDING code.
#
#   has_local = False; float4 = "float4"; barrier = "// BARRIER"
#   code_for_op = {**CStyleLanguage.code_for_op,
#                  Ops.THREEFRY: lambda a,b,dtype: f"threefry({a},{b})",
#                  Ops.MAX:      lambda a,b,dtype: f"max({a},{b})"}
#
# MEASURED: `{**CStyleLanguage.code_for_op}` has 21 entries, NullRenderer's has
# 23, and the two it adds are EXACTLY MAX and THREEFRY -- every shared entry is
# the SAME lambda object (`cfop_changed == 0`). So the merge is ADDITIVE, and
# `nr_cfop_overrides` being 2 rather than 23 is the row that says so.
# ===========================================================================

def nr.has_local() -> U32: 0
def nr.float4() -> String: "float4"
def nr.barrier() -> String: "// BARRIER"
def nr.cstyle_n() -> U32: 21
def nr.cfop_overrides() -> U32: 2
def nr.cfop_total() -> U32: 23

# The lambdas take the RENDERED OPERAND STRINGS -- cstyle.py:66-67 passes
# `ctx[v]`, a string -- so the format is `threefry(<a>,<b>)` with NO SPACE.
# MEASURED with operands "A" and "B".
def nr.cfop_threefry(+a: String, +b: String) -> String:
  String.concat(["threefry(", a, ",", b, ")"])

def nr.cfop_max(+a: String, +b: String) -> String: String.concat(["max(", a, ",", b, ")"])

# :17, `assert self.target.arch.startswith("gfx"), "only amd supports assembly"`.
# The assert REFUSES a non-AMD arch, and both arch spellings the assert message
# and the three in the EMULATE map are the same vocabulary -- `gfx` is not a
# coincidence of naming, it is the one family this backend can hand to an AMD
# assembler.
def nr.asm_ok(arch: String) -> Bool: String.starts_with(arch, "gfx")
def nr.asm_msg() -> String: "only amd supports assembly"

# ===========================================================================
# ops_null.py:55-68 -- `NullDevice`, and the device-side buffer identity rules
# the brief names.
#
#   :55-56 pm_encode -- two rules, `submit_null_{compute,copy}`, and the arg is
#           the FUNCTION NAME, so the two rows differ only in the suffix.
#   :57    host = property(lambda self: self.device) -- the IDENTITY, and the
#           opposite of `Compiled.host` (device.py:418) which answers
#           `HCQ_RUNTIME_DEV`. So NULL's host IS its own name and CPU's is not.
#   :58    timeline = link_buffer(2, dtypes.u64)
#   :61-62 the EMULATE assert and its message
#   :63-64 the renderers list, deduped
#   :66    pm_bufferize -- ONE rule, `ctx.link_buffer(b.max_numel(), b.dtype)`
#   :68    link_buffer(n, dt)
#
# `Compiled`'s `pm_bufferize` has THREE rules (device.py:403-408) and NULL
# REPLACES the table with one, so `ndev_bufferize_n` is 1 where
# `device.bend`'s `pmb_len` is 3 -- and the two rows together are the
# cross-file fact.
# ===========================================================================

# :55-56 -- the two `to_name("submit", devs[0], queue)` results. MEASURED:
# `to_name('submit','NULL','compute')` == 'submit_null_compute'.
def ndev.encode_names() -> List<&2, String>: ["submit_null_compute", "submit_null_copy"]

# :66 -- ONE rule, against `Compiled`'s THREE.
def ndev.bufferize_n() -> U32: 1
def ndev.compiled_bufferize_n() -> U32: 3

# :57 -- `host` IS the device string, so `nr_host_*` on "NULL:1" answers
# "NULL:1" and `cpu_host_*` on "CPU:1" answers "CPU" (device.py:418's
# `HCQ_RUNTIME_DEV.value`). Two rows with different sources and different
# answers, and the difference is the row.
def ndev.host(dev: String) -> String: dev

# :58 -- `link_buffer(2, dtypes.u64)`, and `device.bend` already ports the
# timeline's two uint64 slots, so this IS that call.
def ndev.timeline_n() -> U32: 2
def ndev.timeline_nbytes() -> U32: D.timeline_bytes()

# :68, `Buffer(self.device, n, dt, opaque=memoryview(bytearray(n * dt.itemsize)),
# options=BufferSpec(external_ptr=1))`. The byte size is `n * itemsize` and the
# `external_ptr=1` is what makes `_map` answer the buffer's OWN storage -- the
# two facts together ARE the NULL buffer identity rule.
def ndev.link_nbytes(n: U32, dt: S.Dt) -> U32: U32.mul(n, S.Dt.itemsize(dt))
def ndev.link_ext_ptr() -> U32: 1

# :62, `{"AMD":"gfx1100", "AMD_RDNA4":"gfx1201", "AMD_CDNA4":"gfx950"}.get(emu,
# "<arch>")`. The SAME `Ca` table shape as the CPU arch map and the SAME
# `Ca.lookup` scan, with a different table -- which is why that scan is one def.
def ndev.emulate_table() -> List<&2, Ca>:
  [Ca{1, "AMD", "gfx1100"}, Ca{2, "AMD_RDNA4", "gfx1201"}, Ca{3, "AMD_CDNA4", "gfx950"}]

def ndev.emulate_fallback() -> String: "<arch>"

# THE FALLBACK IS NOT THE KEY HERE. `Ca.lookup`'s default arm is the key itself,
# which is right for the CPU arch map (an unknown machine IS its own arch) and
# wrong here (an unknown emu is literally the five-character string "<arch>").
# So the substitution is this def's, and it is why `nr_emulate_arch_empty` and
# `nr_emulate_arch_raw` are rows: both answer the PLACEHOLDER and neither answers
# the key.
def ndev.emulate_arch(+emu: String) -> String:
  Bool.pick(String, Cam.hit(Ca.lookup(emu, ndev.emulate_table())),
            Cam.to(Ca.lookup(emu, ndev.emulate_table())), ndev.emulate_fallback())

# :61-62, the assert MESSAGE. It is USER-VISIBLE -- it is what a user sees when
# they set a deprecated env var -- and it is built from the arch map, so the
# message and the map cannot disagree.
def ndev.emulate_prefix() -> String: "EMULATE is deprecated, use DEV=NULL:HIP:"
def ndev.emulate_msg(+emu: String) -> String:
  String.concat([ndev.emulate_prefix(), ndev.emulate_arch(emu)])

# :63-64, `renderers = [NullRenderer] + [r for m in [cstyle, nir, ptx, llvmir,
# wgsl] for r in m.__dict__.values() if inspect.isclass(r) and issubclass(r,
# Renderer)]` then `dedup(renderers)`. MEASURED: the raw list is 27 long and
# `dedup` -- `list(dict.fromkeys(x))`, which RETAINS LIST ORDER (helpers.py:23) --
# makes it 20, and the twenty are the raw list with the repeats removed in
# order. `Renderer` itself appears four times in the raw list (once per module's
# `__dict__`) and once in the answer, which is the single most dedup-dependent
# row here: a port that deduped by sorting would move `nr_renderers`.
def ndev.renderers_pre() -> U32: 27

def ndev.renderers() -> List<&2, Cr>:
  [Cr{1, "NullRenderer"}, Cr{2, "Renderer"}, Cr{3, "CStyleLanguage"},
   Cr{4, "ClangRenderer"}, Cr{5, "OpenCLRenderer"}, Cr{6, "MetalRenderer"},
   Cr{7, "CUDARenderer"}, Cr{8, "NVCCRenderer"}, Cr{9, "HIPRenderer"},
   Cr{10, "HIPCCRenderer"}, Cr{11, "QCOMCLRenderer"}, Cr{12, "NIRRenderer"},
   Cr{13, "NAKRenderer"}, Cr{14, "LVPRenderer"}, Cr{15, "IR3Renderer"},
   Cr{16, "PTXRenderer"}, Cr{17, "LLVMRenderer"}, Cr{18, "CPULLVMRenderer"},
   Cr{19, "AMDLLVMRenderer"}, Cr{20, "WGSLRenderer"}]

# ===========================================================================
# THE ZERO TABLE, which is WALL 4's content and the reason this backend exists.
#
# A NULL kernel is NEVER RUN, so every value a kernel would have produced is
# whatever the buffer already held -- and `link_buffer` hands over
# `bytearray(n * itemsize)`, which is ZEROS. So eleven of the thirteen ops I
# measured on the real device answer all-zero, and TWO DO NOT:
#
#     rand  randn  full  add  sum  l2norm  ones  dot  neg  max  softmax -> ZERO
#     eye   [1,0,0,0]     arange [0,1,2,3]                                -> NOT
#
# MEASURED with `DEV=NULL` on the real device, one row per op. `eye` and
# `arange` answer real values because tinygrad builds them out of CONSTs on a
# host-visible buffer rather than out of a kernel, and that is a fact about the
# SCHEDULER, not about this backend -- which is exactly why it belongs in the
# gate: a port that asserted "NULL answers zero" for everything would be wrong
# on two rows and right on eleven, and eleven is enough to hide it.
#
# ONE TABLE, THIRTEEN ROWS, and the table is the content. A count row over it
# would be a second transcription of the same thirteen facts and would prove
# nothing, so there is no count row; `nr_zero_*` reads the table BY NAME.
# ===========================================================================

type Zz is Data:
  Zz{ix: U32, nm: String, z: U32}

def Zz.nm(r: Zz) -> String:
  match r:
    case Zz{ix, nm, z}: nm

def Zz.z(r: Zz) -> U32:
  match r:
    case Zz{ix, nm, z}: z

def nr.zero_table() -> List<&2, Zz>:
  [Zz{1, "rand", 1}, Zz{2, "randn", 1}, Zz{3, "full", 1}, Zz{4, "add", 1},
   Zz{5, "sum", 1}, Zz{6, "l2norm", 1}, Zz{7, "ones", 1}, Zz{8, "dot", 1},
   Zz{9, "neg", 1}, Zz{10, "max", 1}, Zz{11, "softmax", 1},
   Zz{12, "eye", 0}, Zz{13, "arange", 0}]

# FIRST-WINS over the table, and 2 is the answer for a name that is not in it --
# not 0, because 0 means "measured: not all zero" and a missing row must not be
# able to masquerade as one. `nr_zero_missing` is the row that says so.
# THE ACCUMULATOR IS "not found YET" (0) and a hit STORES `Zz.z + 2`, so the three
# answers -- found-and-zero, found-and-not, not-found -- are 3, 2 and 0 and cannot
# be confused with one another. The `+ 2` is load-bearing in a way that is easy to
# get wrong: storing `Zz.z + 1` puts "found and zero" at 2, the outer pick's own
# "not found" test is `is_zero`, and every row after a hit resets the accumulator
# -- so the fold answered 2 for every name and thirteen rows moved at once. THE
# OUTER PICK'S FALSE ARM IS `got` AND NOT `0`: `Bool.pick(T, c, a, b)` answers
# `a` when `c`, so "not yet found" means `is_zero(got)` is TRUE and the answer is
# the inner test, and "already found" means it is FALSE and the answer is `got`
# KEPT. Writing `0` there -- which reads as "reset to not-found" -- makes the fold
# forget every hit on the very next row, and all thirteen rows answer 2 at once.
# MEASURED (M53): flipping this to LAST-wins moves no row, and it cannot. The
# thirteen names are distinct -- they are thirteen separately MEASURED ops, not a
# generated set -- so at most one row ever matches and first-wins and last-wins
# are the same function on every input this def can receive. There is no
# duplicate to plant and planting one would assert a state the table cannot be
# in. See also `EvA.step`: the same argument, for the same reason.
def nr.zero_of.done(+got: U32) -> U32:
  Bool.pick(U32, U32.is_zero(got), 2, U32.sub(got, 2))

def nr.zero_of.go(n: Nat, +nm: String, rs: List<&2, Zz>, +got: U32) -> U32:
  match n:
    case 0n: nr.zero_of.done(got)
    case 1n+p:
      match rs:
        case Nil{}: nr.zero_of.done(got)
        case +h <> t:
          nr.zero_of.go(p, nm, t, Bool.pick(U32, U32.is_zero(got),
            Bool.pick(U32, String.eq(Zz.nm(h), nm), U32.add(Zz.z(h), 2), 0), got))

def nr.zero_of(+nm: String) -> U32:
  nr.zero_of.go(List.length(&2, Zz, nr.zero_table()), nm, nr.zero_table(), 0)

# ===========================================================================
# ops_null.py:60-66 -- `NullDevice.__init__` and the assert.
#
#   assert (emu:=getenv("EMULATE", "")) == "", \
#     "EMULATE is deprecated, use DEV=NULL:HIP:" + {...}.get(emu, "<arch>")
#   super().__init__(device, NullAllocator(self), dedup(renderers), NullProgram)
#   self.pm_bufferize = PatternMatcher([...])
#
# THE ASSERT IS FIRST, so a failing one means `super().__init__` NEVER RUNS and
# there is no device at all -- not a half-built one. That is what the truncation
# in the trace is for: `ndev.init` records the assert, sets `refused`, and then
# records NOTHING else, because `Tr.emit` is a no-op once refused. The failing
# assert IS still recorded, which is not a special case: it sets `refused` in the
# same breath and so on entry its own `refused` is still False.
# ===========================================================================

type Nul is Data:
  Nul{dev: String, renders: List<&2, Cr>, enc: List<&2, String>, bufz: U32,
      host: String, tl: U32, t: Tr}

def Nul.t(n: Nul) -> Tr:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: t

def Nul.dev(n: Nul) -> String:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: dev

def Nul.renders(n: Nul) -> List<&2, Cr>:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: renders

def Nul.tl(n: Nul) -> U32:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: tl

# the assert as a trace event: the call IS recorded and `refused` is set when it
# fails. `Bool.or` rather than a pick, so a SECOND failing assert cannot clear
# an earlier one.
def Tr.assert_at(+bad: Bool, t: Tr) -> Tr:
  match t:
    case Tr{calls, refused}:
      Tr{List.append(&2, Call, calls, [Call{CALL_ASSERT_EMULATE(), Bool.to_u32(bad)}]),
         Bool.or(refused, bad)}

def ndev.init(+dev: String, +emu: String) -> Nul:
  Nul{dev, ndev.renderers(), ndev.encode_names(), ndev.bufferize_n(), ndev.host(dev),
      ndev.timeline_nbytes(),
      Tr.assert_at(Bool.not(String.eq(emu, "")), Tr.of())}

# ===========================================================================
# THE TRACE VOCABULARY. A tag's NUMBER is this file's; its NAME is Python's,
# and the gate prints NAMES so the CPython oracle -- which knows Python and not
# this file -- can be compared byte for byte. `call_name` is one descending
# ladder over the whole vocabulary, so a tag this file invented with no Python
# counterpart answers `"?"` and the diff says so instead of agreeing silently.
# ===========================================================================
def CALL_NAME_UNKNOWN() -> String: "?"

def call_name.go(k: U32) -> String:
  match k:
    case 25: "CONNECT"
    case 24: "ASSERT_EMULATE"
    case 23: "PING"
    case 22: "VIRTUAL_FREE"
    case 21: "FXN"
    case 20: "FXN_LVP"
    case 19: "PROFILE"
    case 18: "POST"
    case 17: "RPC"
    case 16: "CFUNCTYPE"
    case 15: "MEM_WRITE"
    case 14: "MV_ADDRESS"
    case 13: "MMAP"
    case 12: "WP_ON"
    case 11: "WP_OFF"
    case 10: "MSYNC"
    case 9 : "CLEAR_CACHE"
    case 8 : "WRITE_PROTECT"
    case 7 : "FLUSH_ICACHE"
    case 6 : "GET_PROCESS"
    case 5 : "MEMMOVE"
    case 4 : "VIRTUAL_ALLOC"
    case 3 : "LOAD_PROG"
    case 2 : "LOAD_JIT"
    case 1 : "LOAD_RAW"
    case _: CALL_NAME_UNKNOWN()

def tnames.go(n: Nat, cs: List<&2, Call>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match cs:
        case Nil{}: acc
        case h <> t: tnames.go(p, t, List.append(&2, String, acc, [call_name.go(Call.k(h))]))

# THE NAMES OF THE WHOLE TRACE, in order, comma-joined. `List.append` is
# `xs ++ ys` and `String.join` is HEAD-FIRST, so the walk APPENDS; consing here
# reverses every order row at once.
def tnames(+t: Tr) -> String:
  String.join(tnames.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), Nil{}), ",")

# the names of ONE tag's args, for the rows where the arg is the claim.
def targ(k: U32, +t: Tr) -> List<&2, U32>: Tr.args(k, Tr.calls(t))

# the tag at POSITION `i`, which is a different question from "the args of tag
# k" and the one the four conditional positions in `__init__` need.
def tat.go(n: Nat, cs: List<&2, Call>, +i: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+p:
      match cs:
        case Nil{}: 0
        case h <> t: Bool.pick(U32, U32.is_zero(i), Call.k(h), tat.go(p, t, U32.sub(i, 1)))

def tat(+t: Tr, i: U32) -> U32: tat.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), i)

def call_at(+t: Tr, i: U32) -> String: call_name.go(tat(t, i))

# `Renderer` appears four times in the raw 27-long NULL list and ONCE in the
# deduped twenty, so this join is the row that dies if a port deduped by
# sorting or kept the repeats. A `List<Cr>` has no `String.join`, so the names
# are folded into a `List<&2, String>` first -- and the fold APPENDS, because
# `String.join` is head-first and a cons would reverse the whole answer.
def rnames.go(n: Nat, cs: List<&2, Cr>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match cs:
        case Nil{}: acc
        case h <> t: rnames.go(p, t, List.append(&2, String, acc, [Cr.nm(h)]))

def rnames(+cs: List<&2, Cr>) -> String:
  String.join(rnames.go(List.length(&2, Cr, cs), cs, Nil{}), ",")

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

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def nrow(nm: String, v: Nat) -> IO(Unit): IO.print(String.concat([nm, "=", Nat.show(v)]))

def ush(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

def rlist(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(xs, ",")]))

# THE CPU PROGRAM SIGNATURE, itemsizes only, from the MEASURED seven-entry
# signature of a real submit/kernel program: [8,1,8,1,8,1,1].
def sig7() -> List<&2, U32>: [8, 1, 8, 1, 8, 1, 1]

# an EMPTY trace, so a gate row reads ONE program call and not the init in front
# of it. Resetting AFTER the call is the mistake that emptied `cpu_call_local_*`
# the first time -- the reset took the call's own entries with it.
def Prog.reset(p: Prog) -> Prog:
  match p:
    case Prog{name, sig, lvp, elf, osx, rt, addr, liblen, t}:
      Prog{name, sig, lvp, elf, osx, rt, addr, liblen, Tr.reset(t)}

def fx_init(osx: Bool, rt: Bool, elf: Bool, lvp: Bool, remote: Bool, win: Bool) -> Prog:
  Prog.reset(prog.init("k", sig7(), lvp, elf, osx, rt, remote, win, 64))

# the init rows count the UNRESET trace, because the whole of `__init__` is what
# they are about. The CALL rows use the reset fixture.
def fx_init_raw(osx: Bool, rt: Bool, elf: Bool, lvp: Bool) -> Prog:
  prog.init("k", sig7(), lvp, elf, osx, rt, False{}, False{}, 64)

# THE WIN32 FIXTURE IS ITS OWN DEF rather than a `prog.init` call with a bare
# `True{}` in the seventh argument slot: `prog.init` takes SEVEN Bools and a
# literal in that position is a parse error the checker reports at the ARGUMENT
# and not at the def, which is the most expensive kind of error to diagnose.
def fx_win() -> Prog:
  prog.init("k", sig7(), False{}, False{}, False{}, False{}, False{}, True{}, 64)

def fx_remote() -> Prog:
  prog.init("k", sig7(), False{}, False{}, False{}, False{}, True{}, False{}, 64)

def init_n(osx: Bool, rt: Bool, elf: Bool, lvp: Bool) -> U32:
  seen(Prog.t(fx_init_raw(osx, rt, elf, lvp)))

# --- 1: the CPU constants, :16 :28 :31 :40 :54 :78 :81 :19 ----------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("cpu_map_jit", cpu.map_jit())
    urow("cpu_map_anon", cpu.map_anon())
    urow("cpu_map_private", cpu.map_private())
    urow("cpu_prot_rwx", cpu.prot_rwx())
    urow("cpu_ms_flags", cpu.ms_flags())
    urow("cpu_mem_release", cpu.mem_release())
    urow("cpu_page_xrw", cpu.page_xrw())
    urow("cpu_wr_flags", cpu.wr_flags())
    urow("cpu_wait_timeout_int", cpu.wait_timeout_ms())
    srow("cpu_lib_m", cpu.lib_m())
    srow("cpu_rtlib_00", cpu.rt_lib_name(False{}, False{}))
    srow("cpu_rtlib_10", cpu.rt_lib_name(True{}, False{}))
    srow("cpu_rtlib_01", cpu.rt_lib_name(False{}, True{}))
    srow("cpu_rtlib_11", cpu.rt_lib_name(True{}, True{}))
    srow("cpu_elfmag_hex", cpu.elfmag())
    srow("cpu_arch_amd64", cpu.arch_of("amd64"))
    srow("cpu_arch_aarch64", cpu.arch_of("aarch64"))
    srow("cpu_arch_x86_64", cpu.arch_of("x86_64"))
    srow("cpu_arch_arm64", cpu.arch_of("arm64"))
    srow("cpu_arch_riscv64", cpu.arch_of("riscv64"))
    srow("cpu_arch_empty", cpu.arch_of(""))
    srow("cpu_arch_AMD", cpu.arch_of("AMD"))

# --- 2: the device-string decisions, :88 :89 ------------------------------
def t_devname() -> IO(Unit):
  do IO<Unit>:
    urow("cpu_nparts_empty", cpu.nparts(""))
    row("cpu_remote_empty", cpu.is_remote(""))
    urow("cpu_nparts_CPU", cpu.nparts("CPU"))
    row("cpu_remote_CPU", cpu.is_remote("CPU"))
    urow("cpu_nparts_CPU_0", cpu.nparts("CPU:0"))
    row("cpu_remote_CPU_0", cpu.is_remote("CPU:0"))
    urow("cpu_nparts_CPU_1", cpu.nparts("CPU:1"))
    row("cpu_remote_CPU_1", cpu.is_remote("CPU:1"))
    urow("cpu_nparts_remote_host_1234", cpu.nparts("remote:host:1234"))
    row("cpu_remote_remote_host_1234", cpu.is_remote("remote:host:1234"))
    urow("cpu_nparts_remote_h_1_2", cpu.nparts("remote:h:1:2"))
    row("cpu_remote_remote_h_1_2", cpu.is_remote("remote:h:1:2"))
    urow("cpu_nparts_a_b_c_d", cpu.nparts("a:b:c:d"))
    row("cpu_remote_a_b_c_d", cpu.is_remote("a:b:c:d"))
    srow("cpu_remote_peer_remote_host_1234", cpu.remote_peer("remote:host:1234"))
    srow("cpu_remote_peer_CPU_1", cpu.remote_peer("CPU:1"))

# --- 3: the CPU DEVICE, :80-92 -------------------------------------------
def t_device() -> IO(Unit):
  do IO<Unit>:
    +c0: Cpu <- IO.pure(Cpu, cpu.init("", "arm64"))
    +c1: Cpu <- IO.pure(Cpu, cpu.init("CPU:1", "arm64"))
    +c2: Cpu <- IO.pure(Cpu, cpu.init("remote:host:1234", "arm64"))
    srow("cpu_dev_empty", Cpu.dev(c0))
    srow("cpu_arch_fixture", Cpu.arch(c0))
    urow("cpu_has_copy_queue", cpu.has_copy_queue())
    srow("cpu_peer_local", Cpu.peer(c0))
    urow("cpu_dev_id_1", Cpu.dev_id(c1))
    srow("cpu_peer_cpu1", Cpu.peer(c1))
    # The remote arm of `cpu.peer_of` is `:89`, and `cpu_peer_remote` is its
    # only row: the two `peer` rows above are both non-remote, so without this
    # one the whole `remote_peer` derivation could be replaced by `head(dev)`
    # and every row would still hold.
    srow("cpu_peer_remote", Cpu.peer(c2))
    urow("cpu_renderers_n", U32.from_nat(List.length(&2, Cr, Cpu.renders(c0))))
    srow("cpu_renderers", rnames(Cpu.renders(c0)))
    urow("cpu_connect_local_n", seen(Cpu.t(c1)))
    urow("cpu_connect_remote_n", seen(Cpu.t(c2)))
    urow("cpu_sync_local_pings", ncalls(CALL_PING(), Cpu.t(cpu.synchronize(False{}, c1))))
    urow("cpu_sync_remote_pings", ncalls(CALL_PING(), Cpu.t(cpu.synchronize(True{}, c2))))

# --- 4: `__init__` -- the call sequence, :23-56 --------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    urow("cpu_init_0000_n", init_n(False{}, False{}, False{}, False{}))
    urow("cpu_init_0001_n", init_n(False{}, False{}, False{}, True{}))
    urow("cpu_init_0010_n", init_n(False{}, False{}, True{}, False{}))
    urow("cpu_init_0011_n", init_n(False{}, False{}, True{}, True{}))
    urow("cpu_init_0100_n", init_n(False{}, True{}, False{}, False{}))
    urow("cpu_init_0101_n", init_n(False{}, True{}, False{}, True{}))
    urow("cpu_init_0110_n", init_n(False{}, True{}, True{}, False{}))
    urow("cpu_init_0111_n", init_n(False{}, True{}, True{}, True{}))
    urow("cpu_init_1000_n", init_n(True{}, False{}, False{}, False{}))
    urow("cpu_init_1001_n", init_n(True{}, False{}, False{}, True{}))
    urow("cpu_init_1010_n", init_n(True{}, False{}, True{}, False{}))
    urow("cpu_init_1011_n", init_n(True{}, False{}, True{}, True{}))
    urow("cpu_init_1100_n", init_n(True{}, True{}, False{}, False{}))
    urow("cpu_init_1101_n", init_n(True{}, True{}, False{}, True{}))
    urow("cpu_init_1110_n", init_n(True{}, True{}, True{}, False{}))
    urow("cpu_init_1111_n", init_n(True{}, True{}, True{}, True{}))
    +p8: Prog <- IO.pure(Prog, fx_init_raw(True{}, True{}, True{}, True{}))
    +p6: Prog <- IO.pure(Prog, fx_init_raw(False{}, False{}, False{}, False{}))
    +pw: Prog <- IO.pure(Prog, fx_win())
    srow("cpu_init_order", tnames(Prog.t(p8)))
    srow("cpu_init_order_posix", tnames(Prog.t(p6)))
    srow("cpu_init_order_win", tnames(Prog.t(pw)))
    urow("cpu_init_win_n", seen(Prog.t(pw)))
    srow("cpu_init_posix_load", call_at(Prog.t(p6), 2))
    srow("cpu_init_posix_cache", call_at(Prog.t(p6), 4))
    srow("cpu_init_osx_load", call_at(Prog.t(p8), 3))
    srow("cpu_init_osx_cache", call_at(Prog.t(p8), 6))
    urow("cpu_init_posix_wp_n", (U32.add(ncalls(CALL_WRITE_PROTECT_OFF(), Prog.t(p6)),
                                    ncalls(CALL_WRITE_PROTECT_ON(), Prog.t(p6))) : U32))
    urow("cpu_init_osx_wp_n", (U32.add(ncalls(CALL_WRITE_PROTECT_OFF(), Prog.t(p8)),
                                    ncalls(CALL_WRITE_PROTECT_ON(), Prog.t(p8))) : U32))
    urow("cpu_init_posix_mmap_n", ncalls(CALL_MMAP(), Prog.t(p6)))
    urow("cpu_init_win_mmap_n", ncalls(CALL_MMAP(), Prog.t(pw)))
    # the REMOTE arm is one call long and skips everything else
    +pr: Prog <- IO.pure(Prog, fx_remote())
    urow("cpu_init_remote_n", seen(Prog.t(pr)))
    srow("cpu_init_remote_order", tnames(Prog.t(pr)))
    urow("cpu_init_remote_has_mmap", ncalls(CALL_MMAP(), Prog.t(pr)))
    # :21, the `_load` branch: an ELF blob goes through `jit_loader`, anything
    # else is used as it stands.
    row("cpu_load_raw_elf", Bool.not(cpu.uses_jit_loader(True{})))
    row("cpu_load_raw_short", Bool.not(cpu.uses_jit_loader(False{})))
    row("cpu_load_raw_other", Bool.not(cpu.uses_jit_loader(False{})))
    srow("cpu_load_tag_elf", call_name.go(cpu.load_raw(True{})))
    srow("cpu_load_tag_raw", call_name.go(cpu.load_raw(False{})))
    # :40, the mmap flags under each platform fact
    urow("cpu_map_flags_posix", cpu.map_flags(False{}))
    urow("cpu_map_flags_osx", cpu.map_flags(True{}))

# `List.get` answers a `Maybe` and a gate row may not, so these are the two
# TOTAL readers the positional rows need -- the same `drv.one` / `drv.nth` pair
# `upat.bend` grew for the same reason.
def nth(xs: List<&2, U32>, k: Nat) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, k), 0)

def subnames.go(n: Nat, cs: List<&2, Sub>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match cs:
        case Nil{}: acc
        case h <> t: subnames.go(p, t, List.append(&2, String, acc, [Sub.nm(h)]))

def subnames(+xs: List<&2, Sub>) -> List<&2, String>:
  subnames.go(List.length(&2, Sub, xs), xs, Nil{})

# `List<&2, U32>` has no `String.join`, so the itemsizes print through the same
# `ush` fold the numeric rows use.
def ilist(+xs: List<&2, U32>) -> String: String.join(ush(xs, Nil{}), ",")

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
    urow("cpu_nargs_00", prog.nargs(0, 0))
    urow("cpu_nargs_30", prog.nargs(3, 0))
    urow("cpu_nargs_31", prog.nargs(3, 1))
    urow("cpu_nargs_20", prog.nargs(2, 0))
    urow("cpu_nargs_14", prog.nargs(1, 4))
    urow("cpu_nargs_02", prog.nargs(0, 2))
    urow("cpu_lvp_size_00", lvp.size(0, 0))
    urow("cpu_lvp_size_31", lvp.size(3, 1))
    urow("cpu_lvp_size_14", lvp.size(1, 4))
    urow("cpu_lvp_third_31", lvp.third(3, 1))
    urow("cpu_lvp_third_00", lvp.third(0, 0))
    srow("cpu_sig_itemsizes", ilist(sig7()))
    lrow("cpu_lvp_slots_3_2", lvp.slotmap(2n, 3))
    lrow("cpu_lvp_slots_2_1", lvp.slotmap(1n, 2))
    lrow("cpu_lvp_slots_0_3", lvp.slotmap(3n, 0))
    urow("cpu_lvp_d64_lo", nth(lvp.d64(4108), 0n))
    urow("cpu_lvp_d64_hi", nth(lvp.d64(4108), 1n))
    srow("cpu_call_remote_wait", call_name.go(prog.remote_tag(True{})))
    srow("cpu_call_remote_nowait", call_name.go(prog.remote_tag(False{})))
    urow("cpu_call_ret_wait_none", prog.ret_is_none(True{}))
    urow("cpu_call_ret_nowait_none", prog.ret_is_none(False{}))
    +pl: Prog <- IO.pure(Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, False{}, False{}))
    +pv: Prog <- IO.pure(Prog, prog.call(fx_init(False{}, False{}, False{}, True{}, False{}, False{}), 3, 1, False{}, False{}))
    +pr: Prog <- IO.pure(Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, True{}, True{}))
    +pw: Prog <- IO.pure(Prog, prog.call(fx_init(False{}, False{}, False{}, False{}, False{}, False{}), 3, 1, False{}, False{}))
    srow("cpu_call_local_plain", tnames(Prog.t(pw)))
    srow("cpu_call_local_lvp", tnames(Prog.t(pv)))
    srow("cpu_call_remote_order", tnames(Prog.t(pr)))
    urow("cpu_del_00", ncalls(CALL_VIRTUAL_FREE(), Prog.t(prog.del(False{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    urow("cpu_del_01", ncalls(CALL_VIRTUAL_FREE(), Prog.t(prog.del(False{}, True{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    urow("cpu_del_10", ncalls(CALL_VIRTUAL_FREE(), Prog.t(prog.del(True{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    urow("cpu_del_11", ncalls(CALL_VIRTUAL_FREE(), Prog.t(prog.del(True{}, True{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    urow("cpu_del_remote_posix", ncalls(CALL_VIRTUAL_FREE(), Prog.t(prog.del(True{}, False{}, fx_init(False{}, False{}, False{}, False{}, False{}, False{})))))
    lrow("cpu_call_lvp_arg_31", targ(CALL_FXN_LVP(), Prog.t(pv)))
    lrow("cpu_call_plain_arg_31", targ(CALL_FXN(), Prog.t(pl)))
    lrow("cpu_call_nargs_arg_31", targ(CALL_FXN(), Prog.t(pl)))
    urow("cpu_call_profile_n", ncalls(CALL_PROFILE(), Prog.t(pl)))
    urow("cpu_call_profile_none", ncalls(CALL_PROFILE(), Prog.t(pr)))
    # THE MATCHER PINS ITSELF, and it needs BOTH directions. `ops_webgpu.bend`
    # shipped with the pattern length as the fuel and M23 measured that no row
    # could fail; a matcher that is only ever asked to REJECT answers False for
    # every fuel, which is why the rejection rows alone did not catch it here
    # either (M56). A fuel of `len(pat)` reads the first `len(pat)` calls only,
    # so the row that kills it is a one-call pattern at index 1 of a two-call
    # trace: the real answer is True, the short fuel cannot reach it.
    urow("cpu_has_rejects_reverse", Bool.to_u32(Bool.not(seq(Prog.t(pw),
      [Call{CALL_FXN, 0}, Call{CALL_PROFILE, 0}]))))
    urow("cpu_has_rejects_absent", Bool.to_u32(Bool.not(seq(Prog.t(pw), [Call{CALL_PING, 0}]))))
    urow("cpu_has_accepts_plain", Bool.to_u32(seq(Prog.t(pl), [Call{CALL_FXN, 4}])))
    urow("cpu_has_accepts_lvp", Bool.to_u32(seq(Prog.t(pv), [Call{CALL_FXN_LVP, 44}])))
    urow("cpu_has_rejects_wrong_arg", Bool.to_u32(Bool.not(seq(Prog.t(pl), [Call{CALL_FXN, 5}]))))

# --- 6: the NULL queue -- the five ops and the four words ----------------
def subat.of(m: Maybe<&2, Sub>) -> String:
  match m:
    case Some{+x}: Sub.nm(x)
    case None{}: "?"

def subat(xs: List<&2, Sub>, k: Nat) -> String:
  subat.of(List.get(&2, Sub, xs, k))

def t_queue() -> IO(Unit):
  do IO<Unit>:
    urow("nr_exec", NEXEC())
    urow("nr_copy", NCOPY())
    urow("nr_wait", NWAIT())
    urow("nr_store", NSTORE())
    urow("nr_timestamp", NTIMESTAMP())
    urow("nr_nargs_exec", nr.nargs(NEXEC()))
    urow("nr_pads_exec", nr.pads(NEXEC()))
    urow("nr_words_exec", U32.from_nat(List.length(&2, U32, nr.exec(60, 2, 1))))
    urow("nr_nargs_copy", nr.nargs(NCOPY()))
    urow("nr_pads_copy", nr.pads(NCOPY()))
    urow("nr_words_copy", U32.from_nat(List.length(&2, U32, nr.copy(21, 22, 0))))
    urow("nr_nargs_wait", nr.nargs(NWAIT()))
    urow("nr_pads_wait", nr.pads(NWAIT()))
    urow("nr_words_wait", U32.from_nat(List.length(&2, U32, nr.wait(11, 12, False{}))))
    urow("nr_nargs_store", nr.nargs(NSTORE()))
    urow("nr_pads_store", nr.pads(NSTORE()))
    urow("nr_words_store", U32.from_nat(List.length(&2, U32, nr.signal(31, 32))))
    urow("nr_nargs_ts", nr.nargs(NTIMESTAMP()))
    urow("nr_pads_ts", nr.pads(NTIMESTAMP()))
    urow("nr_words_ts", U32.from_nat(List.length(&2, U32, nr.timestamp(20))))
    srow("nr_copy_dev", nr.copy_dev("PYTHON"))
    srow("nr_copy_name", nr.copy_name("PYTHON", "NULL:1"))
    # the WORDS of the measured stream, one row per position, so a port that
    # padded correctly and filled the pad with something else is caught
    lrow("nr_words_exec_all", nr.exec(60, 2, 1))
    lrow("nr_words_copy_all", nr.copy(21, 22, 0))
    lrow("nr_words_wait_all", nr.wait(11, 12, False{}))
    lrow("nr_words_wait_eq", nr.wait(11, 12, True{}))
    lrow("nr_words_store_all", nr.signal(31, 32))
    lrow("nr_words_ts_all", nr.timestamp(20))
    urow("nr_ts_offset", U32.sub(nth(nr.timestamp(20), 1n), 20))
    urow("nr_submit_n", U32.from_nat(List.length(&2, Sub, nr.submit_graph())))
    rlist("nr_submit_graph", subnames(nr.submit_graph()))
    srow("nr_submit_root", subat(nr.submit_graph(), 6n))
    urow("nr_has_local", nr.has_local())
    srow("nr_float4", nr.float4())
    srow("nr_barrier", nr.barrier())
    urow("nr_cstyle_n", nr.cstyle_n())
    urow("nr_cfop_overrides", nr.cfop_overrides())
    urow("nr_cfop_total", nr.cfop_total())
    srow("nr_cfop_threefry", nr.cfop_threefry("A", "B"))
    srow("nr_cfop_max", nr.cfop_max("A", "B"))
    urow("nr_asm_ok_gfx1100", Bool.to_u32(nr.asm_ok("gfx1100")))
    # gfx950 is the CDNA4 answer `nr_emulate_arch_cdna4` hands out, and it is the
    # fixture that separates `startswith("gfx")` from every longer prefix.
    urow("nr_asm_ok_gfx950", Bool.to_u32(nr.asm_ok("gfx950")))
    urow("nr_asm_ok_arm64", Bool.to_u32(nr.asm_ok("arm64")))
    srow("nr_asm_msg", nr.asm_msg())

# --- 7: the NULL DEVICE and the allocator, :48-68 ------------------------
def t_ndev() -> IO(Unit):
  do IO<Unit>:
    +n: Nul <- IO.pure(Nul, ndev.init("NULL:1", ""))
    srow("nr_dev", Nul.dev(n))
    urow("nr_dev_id", D.dev_id(Nul.dev(n)))
    srow("nr_host", ndev.host(Nul.dev(n)))
    urow("nr_has_copy_queue_inherited", nr.has_copy_queue())
    urow("nr_encode_n", U32.from_nat(List.length(&2, String, ndev.encode_names())))
    rlist("nr_encode_names", ndev.encode_names())
    urow("nr_bufferize_n", ndev.bufferize_n())
    urow("nr_compiled_bufferize_n", ndev.compiled_bufferize_n())
    urow("nr_renderers_pre", ndev.renderers_pre())
    urow("nr_renderers_n", U32.from_nat(List.length(&2, Cr, Nul.renders(n))))
    srow("nr_renderers", rnames(Nul.renders(n)))
    urow("nr_timeline_n", ndev.timeline_n())
    urow("nr_timeline_bytes", Nul.tl(n))
    urow("nr_link_ext_ptr", ndev.link_ext_ptr())
    urow("nr_link_2_f32", ndev.link_nbytes(2, S.single()))
    urow("nr_link_3_u64", ndev.link_nbytes(3, S.uint64()))
    nrow("nva_first", nalloc.va(0n))
    nrow("nva_base", nva.base())
    nrow("nva_step1", Nat.sub(nalloc.va(1n), nalloc.va(0n)))
    nrow("nva_step2", Nat.sub(nalloc.va(2n), nalloc.va(1n)))
    urow("nva_count3", Bool.to_u32(Bool.and(Nat.is_ne(nalloc.va(1n), nalloc.va(0n)),
         Bool.and(Nat.is_ne(nalloc.va(2n), nalloc.va(1n)), Nat.is_ne(nalloc.va(2n), nalloc.va(0n))))))
    urow("nalloc_copyin_nops", nalloc.copyin_nops())
    urow("nr_copyout_ok_0", nalloc.copyout_ok(0))
    srow("nr_copyout_msg", nalloc.copyout_msg())
    urow("nr_copyout_ok_1", nalloc.copyout_ok(1))
    row("nr_map_null_NULL", nalloc.map_is_null("NULL"))
    row("nr_map_null_NULL_1", nalloc.map_is_null("NULL:1"))
    row("nr_map_null_NULL_0", nalloc.map_is_null("NULL:0"))
    row("nr_map_null_CPU", nalloc.map_is_null("CPU"))
    row("nr_map_null_null", nalloc.map_is_null("null"))

# A `pack_args` FIXTURE: the itemsize list and the sum of them, which is `end`.
# `end` is a second field rather than a fold because the SAME list feeds the
# size, the offsets and the tail, and a `U32` cannot be read twice in one
# expression -- the `Amt` trick from device.bend, for a different reason.
type Pk is Data:
  Pk{ks: List<&2, U32>, e: U32}

def Pk.itemsizes(p: Pk) -> List<&2, U32>:
  match p:
    case Pk{ks, e}: ks

def Pk.nargs(p: Pk) -> U32: U32.from_nat(List.length(&2, U32, Pk.itemsizes(p)))

def Pk.end(p: Pk) -> U32:
  match p:
    case Pk{ks, e}: e

# `end` IS THE RUNNING `Cn.next`, not the sum of the itemsizes: hcq2.py:82 writes
# `end = offset + arg.dtype.itemsize` where `offset` is the ALIGNED slot, so for
# `[4, 8, 4]` the sum is 16 and the real end is 20. A tail computed from the sum
# gives 8 where CPython gives 4. `pk_tail_484` is the row.
def pkend.go(n: Nat, ks: List<&2, U32>, +off: U32, end: U32) -> U32:
  match n:
    case 0n: end
    case 1n+p:
      match ks:
        case Nil{}: end
        case +k <> t: pkend.go(p, t, Cn.next(cn_slot(off, k)), Cn.next(cn_slot(off, k)))

def pkend(+ks: List<&2, U32>) -> U32: pkend.go(List.length(&2, U32, ks), ks, 0, 0)

def fx_pk(+ks: List<&2, U32>) -> Pk: Pk{ks, pkend(ks)}

# --- 8: pack_args, hcq2.py:78-83 ----------------------------------------
def t_pack() -> IO(Unit):
  do IO<Unit>:
    +k0: Pk <- IO.pure(Pk, fx_pk(Nil{}))
    +k1: Pk <- IO.pure(Pk, fx_pk([4]))
    +k2: Pk <- IO.pure(Pk, fx_pk([4,4]))
    +k3: Pk <- IO.pure(Pk, fx_pk([4,4,4]))
    +k4: Pk <- IO.pure(Pk, fx_pk([8,4]))
    +k5: Pk <- IO.pure(Pk, fx_pk([8,8]))
    +k6: Pk <- IO.pure(Pk, fx_pk([4,4,4,4]))
    +k7: Pk <- IO.pure(Pk, fx_pk([4,8,4]))
    urow("pk_size_4", pk.size(Pk.nargs(k1)))
    urow("pk_nsrc_4", pk.nsrc(Pk.nargs(k1), pk.pads(Pk.itemsizes(k1))))
    urow("pk_tail_4", pk.tail(Pk.nargs(k1), Pk.end(k1)))
    urow("pk_pads_4", pk.pads(Pk.itemsizes(k1)))
    lrow("pk_offsets_4", pk.offsets(Pk.itemsizes(k1)))
    urow("pk_size_44", pk.size(Pk.nargs(k2)))
    urow("pk_nsrc_44", pk.nsrc(Pk.nargs(k2), pk.pads(Pk.itemsizes(k2))))
    urow("pk_tail_44", pk.tail(Pk.nargs(k2), Pk.end(k2)))
    urow("pk_pads_44", pk.pads(Pk.itemsizes(k2)))
    lrow("pk_offsets_44", pk.offsets(Pk.itemsizes(k2)))
    urow("pk_size_444", pk.size(Pk.nargs(k3)))
    urow("pk_nsrc_444", pk.nsrc(Pk.nargs(k3), pk.pads(Pk.itemsizes(k3))))
    urow("pk_tail_444", pk.tail(Pk.nargs(k3), Pk.end(k3)))
    urow("pk_pads_444", pk.pads(Pk.itemsizes(k3)))
    lrow("pk_offsets_444", pk.offsets(Pk.itemsizes(k3)))
    urow("pk_size_84", pk.size(Pk.nargs(k4)))
    urow("pk_nsrc_84", pk.nsrc(Pk.nargs(k4), pk.pads(Pk.itemsizes(k4))))
    urow("pk_tail_84", pk.tail(Pk.nargs(k4), Pk.end(k4)))
    urow("pk_pads_84", pk.pads(Pk.itemsizes(k4)))
    lrow("pk_offsets_84", pk.offsets(Pk.itemsizes(k4)))
    urow("pk_size_88", pk.size(Pk.nargs(k5)))
    urow("pk_nsrc_88", pk.nsrc(Pk.nargs(k5), pk.pads(Pk.itemsizes(k5))))
    urow("pk_tail_88", pk.tail(Pk.nargs(k5), Pk.end(k5)))
    urow("pk_pads_88", pk.pads(Pk.itemsizes(k5)))
    lrow("pk_offsets_88", pk.offsets(Pk.itemsizes(k5)))
    urow("pk_size_4444", pk.size(Pk.nargs(k6)))
    urow("pk_nsrc_4444", pk.nsrc(Pk.nargs(k6), pk.pads(Pk.itemsizes(k6))))
    urow("pk_tail_4444", pk.tail(Pk.nargs(k6), Pk.end(k6)))
    urow("pk_pads_4444", pk.pads(Pk.itemsizes(k6)))
    lrow("pk_offsets_4444", pk.offsets(Pk.itemsizes(k6)))
    urow("pk_size_484", pk.size(Pk.nargs(k7)))
    urow("pk_nsrc_484", pk.nsrc(Pk.nargs(k7), pk.pads(Pk.itemsizes(k7))))
    urow("pk_tail_484", pk.tail(Pk.nargs(k7), Pk.end(k7)))
    urow("pk_pads_484", pk.pads(Pk.itemsizes(k7)))
    lrow("pk_offsets_484", pk.offsets(Pk.itemsizes(k7)))
    # THE EMPTY CALL. MEASURED: `layout_args([])` is `[]`, `8 * max(0, 1)` is 8,
    # and `pack_args([], 8)` still emits the one 8-byte zero tail. Without these
    # five rows `pk.size` could lose its `max` and stay correct on all seven
    # non-empty layouts.
    urow("pk_size_0", pk.size(Pk.nargs(k0)))
    urow("pk_nsrc_0", pk.nsrc(Pk.nargs(k0), pk.pads(Pk.itemsizes(k0))))
    urow("pk_tail_0", pk.tail(Pk.nargs(k0), Pk.end(k0)))
    urow("pk_pads_0", pk.pads(Pk.itemsizes(k0)))
    lrow("pk_offsets_0", pk.offsets(Pk.itemsizes(k0)))

# THE MEASURED COMMAND WORD STREAM: the twelve `cmd` calls I captured off the
# real NULL device, as four-word tuples with the pads explicit. 48 words, twelve
# quads. EXEC's third argument is word 2 and its event id is word 3; TIMESTAMP's
# only argument is word 1 and its two pads are words 2 and 3.
#
# THE STREAM IS BUILT BY APPENDING, and `List.append(a, A, xs, ys)` is `xs ++ ys`,
# so the nested appends below read left to right as the command order: the
# INNERMOST is the LAST command. Consing here would put EXEC first and
# `nprog_descs` -- which is the copy-then-exec order, and the thing setdefault's
# ids depend on -- would come out reversed.
def cmds() -> List<&2, U32>:
  List.append(&2, U32, nr.wait(11, 12, False{}),
    List.append(&2, U32, nr.timestamp(20),
      List.append(&2, U32, nr.copy(21, 22, 0),
        List.append(&2, U32, nr.timestamp(30),
          List.append(&2, U32, nr.signal(31, 32),
            List.append(&2, U32, nr.wait(41, 42, False{}),
              List.append(&2, U32, nr.wait(43, 44, False{}),
                List.append(&2, U32, nr.timestamp(50),
                  List.append(&2, U32, nr.exec(60, 2, 1),
                    List.append(&2, U32, nr.timestamp(70),
                      List.append(&2, U32, nr.wait(81, 82, False{}),
                        nr.signal(83, 84))))))))))))

def zeroed(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: zeroed(p, List.append(&2, U32, acc, [0]))

# `evids` -- the id of every key in a table, IN ORDER, which is the same list
# `setdefault`'s values are. `List.append` is in order and this walk does not
# reverse, so the ids come out ascending and the row is the whole table.
def evids.go(n: Nat, es: List<&2, Nk>, +at: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match es:
        case Nil{}: acc
        case h <> t: evids.go(p, t, U32.add(at, 1), List.append(&2, U32, acc, [at]))

def evids(+es: List<&2, Nk>) -> List<&2, U32>:
  evids.go(List.length(&2, Nk, es), es, 0, Nil{})

# the FIVE lookups the oracle runs, `k0, k1, k0, k1, k2`, with the TABLE growing
# underneath them. Two accumulators in one `Data` record because both the id and
# the grown table have to come back out, and `Ev.put` and `Ev.lookup` must both
# see the table as it was BEFORE this key -- which is the whole of `setdefault`.
type EvQ is Data:
  EvQ{tbl: List<&2, Nk>, acc: List<&2, U32>}

def EvQ.tbl(q: EvQ) -> List<&2, Nk>:
  match q:
    case EvQ{tbl, acc}: tbl

def EvQ.acc(q: EvQ) -> List<&2, U32>:
  match q:
    case EvQ{tbl, acc}: acc

def evq.go(n: Nat, ks: List<&2, Nk>, +q: EvQ) -> EvQ:
  match n:
    case 0n: q
    case 1n+p:
      match ks:
        case Nil{}: q
        case +k <> t:
          +g: EvQ = EvQ{Ev.put(k, EvQ.tbl(q)),
                        List.append(&2, U32, EvQ.acc(q), [Ev.lookup(k, EvQ.tbl(q))])}
          evq.go(p, t, g)

def evlookup(+want: List<&2, Nk>) -> List<&2, U32>:
  EvQ.acc(evq.go(List.length(&2, Nk, want), want, EvQ{Nil{}, Nil{}}))

# the table the five lookups leave behind -- `setdefault` applied to the SAME
# five keys in the SAME order, which is how `nr_event_count_after` is measured
# without a second hand-written fold. A `+` on both because `Ev.put` reads the
# table through each `Nk.same`.
def evtab5(+k0: Nk, +k1: Nk, +k2: Nk) -> List<&2, Nk>:
  Ev.put(k2, Ev.put(k1, Ev.put(k0, Ev.put(k1, Ev.put(k0, Nil{})))))

def t_prog() -> IO(Unit):
  do IO<Unit>:
    +st: St <- IO.pure(St, nprog.streams(nprog.sig7()))
    urow("nprog_sig_n", U32.from_nat(List.length(&2, Sg, nprog.sig7())))
    urow("nprog_streams_n", U32.div(U32.from_nat(List.length(&2, U32, St.pairs(st))), 2))
    lrow("nprog_streams", St.pairs(st))
    urow("nprog_stream_bytes", St.nbytes(st))
    urow("nprog_qwords", nprog.qwords(St.nbytes(st)))
    urow("nprog_quads", U32.div(nprog.qwords(St.nbytes(st)), 4))
    +ws: List<&2, U32> <- IO.pure(List<&2, U32>, cmds())
    urow("nprog_words_n", U32.from_nat(List.length(&2, U32, ws)))
    urow("nprog_quads_real", nprog.quads(ws))
    urow("nprog_writes_ts", nprog.writes(ws))
    +wz: List<&2, U32> <- IO.pure(List<&2, U32>, zeroed(48n, Nil{}))
    urow("nprog_writes_zeroed", nprog.writes(wz))
    urow("nprog_done_at_0", nprog.done_at(ws, 0n))
    urow("nprog_done_at_1", nprog.done_at(ws, 1n))
    urow("nprog_done_at_2", nprog.done_at(ws, 2n))
    urow("nprog_done_at_8", nprog.done_at(ws, 8n))
    urow("nprog_done_at_11", nprog.done_at(ws, 11n))
    urow("nprog_done_sum", nprog.done_at(ws, 12n))
    urow("nprog_stamp_val_1000_0", nprog.stamp_val(1000, 0))
    urow("nprog_stamp_val_1000_1", nprog.stamp_val(1000, 1))
    urow("nprog_stamp_val_7_3", nprog.stamp_val(7, 3))
    lrow("nprog_ent_ids_0", nprog.ent_ids(0))
    lrow("nprog_ent_ids_1", nprog.ent_ids(1))
    +ev0: Nk <- IO.pure(Nk, Nk{"PYTHON:SDMA:0", "PYTHON -> NULL:1", 0})
    +ev1: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 7})
    +e1: List<&2, Nk> <- IO.pure(List<&2, Nk>, List.append(&2, Nk, Ev.put(ev0, Nil{}), [ev1]))
    urow("nr_events_n", U32.from_nat(List.length(&2, Nk, e1)))
    lrow("nr_event_ids", evids(e1))
    +k5: Nk <- IO.pure(Nk, Nk{"PYTHON:SDMA:0", "E_4", 0})
    lrow("nr_event_lookup", evlookup([ev0, ev1, ev0, ev1, k5]))
    urow("nr_event_count_after", U32.from_nat(List.length(&2, Nk, evtab5(ev0, ev1, k5))))
    +ka: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 1})
    +kb: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 2})
    urow("nr_event_key_matters", Bool.to_u32(Bool.not(Nk.same(ka, kb))))
    +dd: List<&2, String> <- IO.pure(List<&2, String>, nprog.descs(ws, e1))
    urow("nprog_descs_n", U32.from_nat(List.length(&2, String, dd)))
    rlist("nprog_descs", dd)
    lrow("nprog_sigs", nprog.sigs(1000, dd))
    lrow("nprog_sigs_same", nprog.sigs(1000, ["A", "A", "A"]))
    lrow("nprog_sigs_mixed", nprog.sigs(1000, ["A", "B", "A"]))

# --- 10: the ops NULL does and does not zero, and the assert --------------
def t_zero() -> IO(Unit):
  do IO<Unit>:
    urow("nr_zero_rand", nr.zero_of("rand"))
    urow("nr_zero_randn", nr.zero_of("randn"))
    urow("nr_zero_full", nr.zero_of("full"))
    urow("nr_zero_eye", nr.zero_of("eye"))
    urow("nr_zero_arange", nr.zero_of("arange"))
    urow("nr_zero_add", nr.zero_of("add"))
    urow("nr_zero_sum", nr.zero_of("sum"))
    urow("nr_zero_l2norm", nr.zero_of("l2norm"))
    urow("nr_zero_ones", nr.zero_of("ones"))
    urow("nr_zero_dot", nr.zero_of("dot"))
    urow("nr_zero_neg", nr.zero_of("neg"))
    urow("nr_zero_max", nr.zero_of("max"))
    urow("nr_zero_softmax", nr.zero_of("softmax"))
    urow("nr_zero_missing", nr.zero_of("relu"))
    urow("ndev_zero_table_n", U32.from_nat(List.length(&2, Zz, nr.zero_table())))
    srow("nr_emulate_arch_empty", ndev.emulate_arch(""))
    srow("nr_emulate_msg_empty", ndev.emulate_msg(""))
    srow("nr_emulate_arch_amd", ndev.emulate_arch("AMD"))
    srow("nr_emulate_msg_amd", ndev.emulate_msg("AMD"))
    srow("nr_emulate_arch_rdna4", ndev.emulate_arch("AMD_RDNA4"))
    srow("nr_emulate_msg_rdna4", ndev.emulate_msg("AMD_RDNA4"))
    srow("nr_emulate_arch_cdna4", ndev.emulate_arch("AMD_CDNA4"))
    srow("nr_emulate_msg_cdna4", ndev.emulate_msg("AMD_CDNA4"))
    srow("nr_emulate_arch_raw", ndev.emulate_arch("gfx1100"))
    srow("nr_emulate_msg_raw", ndev.emulate_msg("gfx1100"))
    srow("nr_emulate_arch_junk", ndev.emulate_arch("nonsense"))
    srow("nr_emulate_msg_junk", ndev.emulate_msg("nonsense"))
    srow("nr_emulate_prefix", ndev.emulate_prefix())
    # THE REFUSAL. `assert emu == ""` is the FIRST statement, so a failing one
    # means `super().__init__` never runs and there is no device. The trace is
    # the observable: it holds the assert and NOTHING after it, and
    # `nr_assert_blocks_*` is that -- one further seam call, still unrecorded.
    +ok: Nul <- IO.pure(Nul, ndev.init("NULL:1", ""))
    +bad: Nul <- IO.pure(Nul, ndev.init("NULL:1", "AMD"))
    urow("nr_assert_trace_ok_n", seen(Nul.t(ok)))
    urow("nr_assert_trace_bad_n", seen(Nul.t(bad)))
    urow("nr_assert_refused_ok", Bool.to_u32(Tr.refused(Nul.t(ok))))
    urow("nr_assert_refused_bad", Bool.to_u32(Tr.refused(Nul.t(bad))))
    urow("nr_assert_post_ok", seen(Tr.emit(CALL_PING(), 0, Nul.t(ok))))
    urow("nr_assert_post_bad", seen(Tr.emit(CALL_PING(), 0, Nul.t(bad))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_devname()
    c : Unit <- t_device()
    d : Unit <- t_init()
    e : Unit <- t_call()
    f : Unit <- t_queue()
    g : Unit <- t_ndev()
    h : Unit <- t_pack()
    i : Unit <- t_prog()
    j : Unit <- t_zero()
    IO.print("cn-done=1")

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
#   M28  `EvA.step` last-wins. A SOUND EQUIVALENCE, with a proof rather than a
#        shrug: `Nk.same` IS Python's tuple equality on `(device, name, key)`,
#        `null_events` is a DICT so it never holds two equal keys, and `Ev.put`
#        -- the only inserter, and pinned by M29's five rows -- appends on a
#        miss only. Given "no equal pair in the table", first-wins and
#        last-wins are the same function. The invariant that makes M28 sound is
#        itself the thing M29 pins.
#
#   M53  `nr.zero_of.go` last-wins. THE SAME ARGUMENT: the thirteen names are
#        thirteen separately MEASURED ops, so at most one row ever matches.
#        There is no duplicate to plant, and planting one would assert a state
#        the table cannot be in.
#
#   M60  a comment-only edit. THE CONTROL, and it is SUPPOSED to be zero: if a
#        comment moved a row, this harness was measuring something other than
#        the code.
#
# WHAT THIS GATE STILL DOES NOT SEE. Stated here rather than left to be found:
#
#   * Anything the wall stops. A 64-bit `addr`, a `Native` function pointer, the
#     real `mv_address`, the real `jit_loader` link and the `mmap`ed bytes are
#     all seams. `Prog.addr` is a PORT MODEL -- the trace index -- and no row
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

#   M1      5  nr.pads: `3 - arity` -> `4 - arity`
#   M2     22  nr.words: emit FIVE words (the `[:4]` slice dropped)
#   M3      4  nr.nargs: swap the TIMESTAMP and STORE arities
#   M4      2  nr.timestamp: drop the `+ 8` (the timeline value slot)
#   M5      1  nr.copy_dev: drop the `:SDMA:0` suffix
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
#   M28     0  Ev.lookup: last-wins instead of first-wins   ZERO -- see below
#   M29     5  Ev.put: the miss does NOT insert (setdefault -> get)
#   M30     1  Nk.same: the `key` field ignored (device+name only)
#   M31     1  nr.copy_name: the arrow becomes a comma
#   M32     1  nr.cfop_threefry: a space after the comma
#   M33     1  nr.renderers: the deduped list sorted (order no longer the policy)
#   M34     2  nalloc.va: the 1<<32 step becomes 1<<31
#   M35     2  nalloc.map_is_null: `startswith` -> equality
#   M36     1  nalloc.copyout_ok: the flag IGNORED (always refuse)
#   M37     5  nprog.sig7: the cmdbuf name at index 5 does not start with `cmdbuf`
#   M38     2  nprog.qwords: bytes divided by 4 instead of 8
#   M39     7  nprog.is_work: EXEC or COPY -> EXEC only
#   M40     3  nprog.stamp_val: microseconds, not nanoseconds
#   M41     2  nprog.done_at: the inclusive accumulate becomes exclusive
#   M42     2  nprog.lane.go: `or` becomes `and` (the count stops growing)
#   M43     3  nprog.sigs: the lane term dropped from the odd entries
#   M44     2  pk.size: the `max(len(args), 1)` guard dropped
#   M45     1  pk.nsrc: the interior pads not counted
#   M46     4  cn_slot: device.bend`s OFF-BY-ALIGNMENT semantics restored
#   M47     1  pkend: the sum of the itemsizes instead of the running `next`
#   M48    14  pk.pads.go: every offset counted as a pad
#   M49     6  ndev.emulate_arch: the `<arch>` fallback replaced by the key
#   M50     2  ndev.emulate_table: AMD_CDNA4 maps to gfx1201 not gfx950
#   M51     1  nr.zero_table: `eye` marked as all-zero (the scheduler fact, faked)
#   M52     1  nr.zero_table: `arange` marked as all-zero
#   M53     0  nr.zero_of.go: last-wins (the hit overwrites)   ZERO -- see below
#   M54     2  Tr.assert_at: the failing assert does NOT record its refusal
#   M55     1  Tr.emit.go: drop the `refused` guard (the raise is gone)
#   M56     2  Tr.has.go: the fuel is the PATTERN length (ops_webgpu M23, reintroduced)
#   M57     5  tnames: the names fold CONSES (the whole order row reverses)
#   M58     1  nprog.streams.go: the pairs CONS (the stream order reverses)
#   M59     3  cmds(): the whole 12-command stream emitted in REVERSE
#   M60     0  a comment-only edit -- THE CONTROL   ZERO -- see below
#   M61     2  cpu.rt_lib_name: the OSX ternary answers `System` always
#   M62    14  cn_slot.of: the running offset is the head, not the aligned one
#   M63     1  cpu.prot_rwx: 0x7 -> 0x6 (the write bit dropped)
#   M64     1  cpu.mem_release: 0x8000 -> 0x4000
#   M65     2  cpu.page_xrw: 0x40 -> 0x20
#   M66     1  cpu.elfmag: ELFMAG.encode() -> "\x7fELG"
#   M67     1  has_copy_queue: the two overrides swapped
#   M68     1  nr.asm_ok: `startswith("gfx")` -> `startswith("gfx1")`
#   M69     7  ndev.emulate_prefix: DEV=NULL:HIP -> DEV=NULL:HIP2
#   M70     1  nr.cfop_max: `max(` -> `Max(`
#   M71     1  ndev.timeline_n: `link_buffer(2, uint64)` -> 3 slots
#   M72     1  ndev.link_ext_ptr: external_ptr=1 -> 0
#   M73     1  cpu.lib_m: `DLL("m", "m")` -> `DLL("m", "c")`
#   M74    11  prog.nargs: `len(bufs) + len(vals)` -> `len(bufs)`
#   M75     1  lvp.third: two slots per argument -> one
#   M76     2  nprog.ent_ids: `2i, 2i+1` -> `2i, 2i+2`
#   M77     4  pk.tail: `size - end` -> `end`
#   M78     3  Tr.reset: the trace is NOT cleared
#   M79     2  cpu.uses_jit_loader: the ELF test ignored
#   M80     1  ndev.bufferize_n: the ONE NULL rule becomes Compiled`s THREE
#   M81     3  cpu.map_anon: 0x1000 -> 0x800
#   M82     2  cpu.map_jit: 0x0800 -> 0x0400
#   M83     3  cpu.map_private: 2 -> 1
#   M84     1  cpu.ms_flags: MS_SYNC|MS_INVALIDATE -> MS_SYNC
#   M85     1  cpu.renderers: the four names in the wrong order
#   M86     1  nr.zero_table: `rand` marked as NOT all-zero
#   M87    16  pk.size: eight bytes per argument, not four
#   M88     8  cpu.nparts: split on ";" instead of ":"
#   M89     2  prog.del.at: the WIN conjunct dropped (M22 drops the remote one)
#   M90     2  nva.base: 1<<40 -> 1<<41
#   M91     2  nr.submit_graph: the STORE root becomes a LOAD
#   M92     3  sig7: the last itemsize is 8, not 1
#   M93     1  nr.float4: `float4` -> `float2`
#   M94     1  nr.barrier: `// BARRIER` -> `//barrier`
#   M95     1  nr.has_local: False -> True
#   M96     1  ndev.renderers_pre: the raw list is 27 long
#   M97     2  ndev.link_nbytes: `n * itemsize` -> `n`
#   M98     6  cpu.load_raw: the jit_loader/raw tags swapped
#   M99    20  prog.posix: the CACHE step dropped (every posix count drops by one)
#   M100    2  prog.win: the GET_PROCESS step dropped
#   M101   15  nr.words: the op tag is the SECOND slot, not the first
#   M102    6  nprog.done_at: EVERY work command counts, not just EXEC
#   M103    3  cpu.peer.at: the local arm returns the REMOTE peer (the arms swapped)
#   M104    4  ndev.init: the assert is INVERTED (a non-empty EMULATE passes)
#   M105    1  nr.zero_of: a name that is NOT in the table answers 0, not 2
#   M106    2  the op tags: EXEC is 5, not 0 (the whole range renumbered)
#   M107    1  nr.zero_table: `randn` marked as NOT all-zero (M86 does `rand`)
#   M108    1  nprog.writes: nothing is stamped
#   M109    3  nprog.stamp_val: nanoseconds, not microseconds -- and the other way
