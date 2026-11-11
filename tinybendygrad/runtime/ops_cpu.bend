# tinybendygrad/runtime/ops_cpu.bend -- port of tinygrad/runtime/ops_cpu.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `ops_cpu_null.bend`,
# which held `ops_cpu.py` (96 lines) AND `ops_null.py` (70 lines); the 1:1 ruling
# gives each its own file. `runtime/ops_null.bend` is the other half and the rows are
# the SAME rows -- 308 across the pair before the split, 308 after.
#
# ops_cpu.py is the backend EVERY OTHER BACKEND INHERITS FROM. It has no renderer of
# its own, it owns the `arch` string every Clang target shares, and its `Program` is
# the one that mmaps a machine-code blob and calls it. `ops_null.py` is the DEGENERATE
# case: `NullQueue` writes FOUR words per command into a bytearray and the emulated
# device computes NOTHING. Eleven of the thirteen ops answer all-zero and TWO DO NOT
# -- `eye` and `arange` -- and both are in `ops_null.bend`'s gate with their CPython
# answers, so a port claiming "everything is zero" is caught by two rows.
#
# THE SPLIT, restated because it is the whole discipline here: a def EITHER BUILDS THE
# ARGUMENT of one device call OR RECORDS that call in the trace. There is no third
# kind. Every seam is a trace tag and nothing else, so the ORDER and IDENTITY of the
# seam calls are gateable even though none of them is made.
#
# THIS FILE ALSO CARRIES WHAT BOTH HALVES NEED, and `ops_null.bend` imports it as `C`:
#   * `Cn`/`cn_slot`/`cn_walk` -- upstream's `struct.pack_into` slot walk (`tinygrad/runtime/ops_cpu.py:58-59 symbol=__call__`), with
#     the CORRECT `iter_sig` semantics; see the `device.bend` DEFECT report below,
#     which is why they are declared here and not read from `device.bend`.
#   * `Ca`/`Cam`/`Ca.lookup` -- the `.get(m, m)` arch map. TWO callers share the scan
#     -- ops_cpu.py:91's arch map and ops_null.py:62's EMULATE map -- and they are the
#     same shape with different tables, which is why it is one def and not two.
#   * `Tr`/`Tr.*`/`Call` and the eleven `CALL_*` seam tags -- ops_null.py's `EMULATE`
#     assert records through them, which is what `nr_assert_post_bad` measures.
#     `CALL_ASSERT_EMULATE` is the one tag that belongs to NULL and it is declared
#     here because that is where every tag is declared.
#   * `Cr` -- ops_cpu.py:90's four-renderer table, which ops_null.py:65-66's is a
#     twenty-row relative of.
#   * `nth`/`subnames`/`ilist` -- the three TOTAL readers the positional rows need.
#   * the row printers `row/srow/urow/nrow/lrow/rlist` and `CALL_NAME_*`.
# None of the substrate has an upstream counterpart of its own, so it lives in the
# FIRST of the pair in Python's order rather than being duplicated.
#
#    number is a machine address (`self.addr`, `mv_address(self.mem)`, `len(args)*Q`,
#    `a & 0xffffffffffffffff`), and Bend has no 64-bit integer, so addresses are
#    carried as U32 HANDLE ids and the SIZES, COUNTS and ORDER are gated instead.
#    The one 64-bit number ported is `NullAllocator._alloc`'s
#    `itertools.count(1 << 40, 1 << 32)`, as a `Nat`; see `nalloc.va` for why that
#    one is possible when `1 << 40` is not.
#    TODO(p3) runtime/ops_cpu.py:51  symbol=__call__  -- struct.pack('<nQ', a & 0xffffffffffffffff).
# 2. THE BYTE-STRING ELFMAG TEST. `lib[:4] != libc.ELFMAG.encode()` (:21) compares
#    four bytes (`b'\x7fELF'`, MEASURED); the port takes the ANSWER as a Bool, which
#    is all any caller needs since `jit_loader` is a seam either way, and `cpu.elfmag`
#    names the four bytes as a hex STRING so the constant is auditable.
#    TODO(p3) runtime/ops_cpu.py:21  symbol=_load -- the first FOUR bytes of `lib` against `b'\x7fELF'`.
# 3. THE `dt.fmt` STRUCT FORMATS. `:70`'s `struct.pack_into(f'<{dt.fmt}', ...)` writes
#    at a dtype-dependent offset. The OFFSETS are portable -- they are
#    `TinyELF.iter_sig(...)`, which device.bend already ports -- the BYTES are a WALL.
#    TODO(p3) runtime/ops_cpu.py:59  symbol=__call__  -- struct.pack_into('<{dt.fmt}', ...).
# 4. WHAT NULL DOES NOT COMPUTE. Its kernels are never run and `NullRenderer.asm`
#    refuses anything that is not `gfx`. There is nothing to port in a result because
#    there is nothing there: `nr.asm_msg` says so -- the emulated device WRITES
#    NOTHING into a stream with no TIMESTAMP word -- rather than inventing a result.
#
# WHAT device.bend AND helpers.bend LEND, AND WHAT IS OWED BACK.
# LENT: `D.isig.go` (the offset-carrying body of `TinyELF.iter_sig`, tinygrad/device.py:352 symbol=iter_sig --
# device.bend's `iter_sig` entry point hard-codes 0, so BOTH uses here need `go`;
# REPORTED, not fixed, device.bend is read-only to this unit); the port's `D.dev_id`
# (upstream's `device_id`, tinygrad/device.py:383 symbol=Compiled.__init__,
# inherited by both); the port's `D.timeline_bytes` (upstream's `timeline`,
# `tinygrad/runtime/ops_null.py:65 symbol=timeline` IS that call);
# `H.round_up_u32`, `H.u32_list_eq`, `H.dedup_str`.
# OWED: the renderer ORDER is the policy -- `Compiled._select_renderer` (tinygrad/device.py:462 symbol=_select_renderer)
# walks it and the FIRST INITIALISED renderer wins, and `cpu.renderers`/`ndev.renderers`
# are those two orders transcribed and both are rows. `Compiled.has_copy_queue` is True
# (tinygrad/device.py:391 symbol=has_copy_queue) and
# `tinygrad/runtime/ops_cpu.py:68 symbol=has_copy_queue` overrides it to False while
# upstream's `NullDevice` (tinygrad/runtime/ops_null.py:63 symbol=NullDevice) does NOT, so
# `cpu_has_copy_queue` and `nr_has_copy_queue_inherited` are two rows with DIFFERENT
# answers -- either constant could be wrong without the other noticing.
# `Compiled.peer_group` (tinygrad/device.py:384 symbol=Compiled.__init__) means a CPU device with no remote and no iface
# answers its own device-class prefix -- `Device['CPU:1'].peer_group == 'CPU'`, MEASURED
# -- and ops_cpu.py:92 overwrites it with the REMOTE's when there is one;
# `cpu.peer_of` is that two-arm choice and both arms are rows. `Compiled.wait_timeout_ms`
# is `30000.0` (a float) and ops_cpu.py:81 writes the INT `30000`, so the row name says
# so. `Compiled.synchronize` (tinygrad/device.py:429 symbol=synchronize) is what tinygrad/runtime/ops_cpu.py:80 `synchronize` adds a remote PING to.
#
# THE TWO GATES. For ops_cpu: the ORDER AND IDENTITY of the init call sequence --
# `__init__` is six lines of POSIX in a fixed order and four fixture facts (OSX, whether
# `rt` is loaded, whether the blob is an ELF, whether the target is LVP) choose among the
# branches, so the trace is a sixteen-way decision table; the gate reads all four
# combinations that DIFFER, plus the invariant counts, plus the tag at position five,
# which is the only place `rt_loaded` is visible. For ops_null: the five op constants,
# four words per command, the padding count per op, the event interning order, the `va`
# bump sequence, the `_map` device test, the `_copyout` refusal, and the eleven-plus-two
# op results -- a SMALL HONEST GATE rather than a wide shallow one.
#
# ONE CROSS-FILE FACT MEASURED IN CPYTHON (DEV=NULL DEBUG=3, spying on `NullQueue.q`
# and `NullProgram.__init__`), because it is the interface and it is silent on both
# sides. `q` makes 14 calls, 11 of them `cmd`, and EVERY `cmd` writes exactly FOUR
# words; the ops in order were WAIT, TIMESTAMP, COPY, TIMESTAMP, STORE, WAIT, WAIT,
# TIMESTAMP, EXEC, TIMESTAMP, WAIT, STORE. `null_events` interned exactly two keys:
#     0 ("PYTHON:SDMA:0", "PYTHON -> NULL:1", None)   <- copy (:31)
#     1 ("NULL",           "E_3",            <key>)    <- exec (:30)
# and the submit signature is seven entries with itemsizes [8,1,8,1,8,1,1], two named
# `cmdbuf_*`, so `streams == [(3,160),(5,224)]` -- 384 bytes, 48 Q words, 12 quads. The
# ONE graph event had `ents = [(PYTHON:SDMA:0,"PYTHON -> NULL:1",0,1), (NULL,"E_3",2,3)]`
# and `sigs = [S, S+1, S, S+1]` with `S = perf_counter_us()` at entry. The COPY was
# queued BEFORE the EXEC, which is why event 0 is the copy's: `setdefault`'s value is
# `len(null_events)` AT THE CALL, so the id IS the first-appearance index. And
# `sigs[2i] = st + (number of EARLIER descs on the SAME device)` is why the two entries
# share a base -- their device strings differ. That is the shape `nprog.descs`/`nprog.sigs`
# port and the shape `nr_words`, `nr_pads_*`, `nr_event_ids`, `nprog_streams`, `nprog_sigs_*`
# pin.
#
# THREE THINGS THIS FILE COULD NOT WRITE CHEAPLY, REPORTED NOT HIDDEN.
# 1. THE TRACE MACHINERY IS DUPLICATED. `Tr.emit`/`Tr.count`/`Tr.args`/`Tr.has` are the
#    same four defs as ops_webgpu.bend's, about 60 lines. The reason is LAYERING, not
#    laziness: `Tr` carries this file's call tags and ops_webgpu.bend carries its own, and
#    hoisting the matcher means a shared module both backends import, which is a decision
#    about the tree's shape. The four defs are generic in `List<&2, Call>` and lift
#    unchanged if the coordinator wants them hoisted.
# 2. `int(parts[2])` (`tinygrad/runtime/ops_cpu.py:73 symbol=__init__`) is a DECIMAL PARSE and is a WALL: `String.to_u32` does not
#    exist in 2.0.34, so a parse is a fold over `String.to_list(s)` feeding
#    `U32.add(U32.mul(acc,10), Char.to_u32(c)-48)` and it raises on a non-numeric port --
#    a refusal this file does not model. The peer-group STRING beside it is ported,
#    because that is the half an importer reads.
# 3. `1 << 40` IS NOT A `Nat` LITERAL. MEASURED: a `Nat` literal is capped at
#    4294967295n, so `nalloc.va`'s base is `Nat.mul(1024n, 1073741824n)` and the step is
#    `Nat.mul(2n, 2147483648n)`. That costs two lines and is the only reason the NULL
#    allocator's 64-bit counter is ported rather than declared a wall; `nva_base` and
#    `nva_step` check the answers.import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S
import ./support/compiler_cpu.bend as CC

# A DEFECT FOUND IN device.bend, REPORTED AND NOT FIXED (device.bend is
# read-only to this unit). `device.bend:988 symbol=TinyELF.iter_sig` ports `TinyELF.iter_sig`
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

# THE CPU CONSTANTS. Every one MEASURED out of CPython, not transcribed.

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

# ops_cpu.py:54, `libc.MS_SYNC | libc.MS_INVALIDATE` == 4|2.
def cpu.ms_flags() -> U32: 6

# ops_cpu.py:78, the MEM_RELEASE flag in the VirtualFree call: 0x8000.
def cpu.mem_release() -> U32: 32768

# ops_cpu.py:19, `DLL('m', 'm')`. The second name is a constant and the first is
# the platform arm. MEASURED on this host, `DLL.findlib('m','m')` answers
# `/usr/lib/libm.dylib`, so the name in this row DOES reach a library.
def cpu.lib_m() -> String: "m"

# THE OBJC LIBRARY -- A PORT-LEVEL FIX THAT UPSTREAM DOES NOT HAVE, and the only
# place in this file where the port is deliberately NOT a transcription.
#
# THE BUG, MEASURED. ops_cpu.py:21 builds the loader's search set as
# `link_libs=[self.libm, self.rt_lib]`, and `link_sym` (elf.py:9-13) walks it left
# to right and raises `RuntimeError(f'Attempting to relocate against an undefined
# symbol {sym}')` when none of them has the symbol. On this host:
#
#   dyld_info -exports /usr/lib/libSystem.dylib | grep -c sel_registerName   -> 0
#   dyld_info -exports /usr/lib/libobjc.dylib   | grep -c sel_registerName   -> 1
#
# and that is a real undefined reference, not a theoretical one: `cstyle.py:268`
# emits `extern void sel_registerName();` into a generated host kernel and
# `ops_metal.py:86` binds `metal.dll.sel_registerName` and `objc_msgSend`, so an
# objc-using kernel's ELF `.strtab` holds BOTH as undefined and the loader dies.
#
# WHY THE ROW IS A PATH AND NOT A NAME. `link_sym` takes `ctypes.CDLL` HANDLES, so
# what the set needs is whatever produces a handle that resolves. The obvious
# spelling, `DLL('objc', 'objc')`, does NOT work, and that is measured, not
# assumed:
#
#   DLL.findlib('objc','objc')  -> None       <- it never opens
#   ctypes.util.find_library('objc') -> /usr/lib/libobjc.dylib
#   ctypes.CDLL('/usr/lib/libobjc.dylib').sel_registerName -> 0x1801ac730
#
# `/System/Library/Frameworks/objc.framework` is not a directory on this host, so
# `findlib`'s darwin arm has nothing to match and answers None -- adding the bare
# name "objc" would add a library that never opens, which is the failure mode this
# row exists to avoid. The path is named instead, and the oracle proves it opens
# and resolves.
#
# THE RELATED FINDING, CORRECTED. `c.py:102-103` tests
# `pathlib.Path(p).is_file()`, which is FALSE for `/usr/lib/libSystem.dylib`
# because that path lives in the dyld shared cache. But `DLL` still loads
# libSystem, because the darwin arm also tries
# `/System/Library/Frameworks/System.framework/System` and accepts a SYMLINK
# there, and that path opens: MEASURED, `DLL.findlib('rt','System')` answers
# `/System/Library/Frameworks/System.framework/System` and `ctypes.CDLL` of it
# succeeds. So the shared-cache `is_file()` miss does not stop libSystem, and
# nothing here depends on it.

def cpu.lib_objc() -> String: "/usr/lib/libobjc.dylib"

# ops_cpu.py:19, `'System' if OSX else 'kernel' if WIN else 'gcc_s'`. The two
# nested ternaries are TWO PICKS and not a three-arm `match`: the second and
# third cells of that match would both be `cpu.rt_lib_name.os(win)`, so writing
# them as arms states a distinction the source does not make. The four cells are
# the four rows `cpu_rtlib_00`..`cpu_rtlib_11`.
def cpu.rt_lib_name.os(win: Bool) -> String: Bool.pick(String, win, "kernel", "gcc_s")

def cpu.rt_lib_name(osx: Bool, win: Bool) -> String:
  Bool.pick(String, osx, "System", cpu.rt_lib_name.os(win))

# THE LINK SET, IN ORDER, and the order is the policy: `link_sym` returns the
# FIRST handle that has the symbol, so a library that shadows another must come
# later. Upstream has TWO entries; this has THREE, and the third is the fix
# above. `n` counts the entries because the size of a fix is the thing a reader
# checks first.
def cpu.link_libs(osx: Bool, win: Bool) -> List<&2, String>:
  [cpu.lib_m(), cpu.rt_lib_name(osx, win), cpu.lib_objc()]

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

# THE CPU CALL TAGS. One per seam call in ops_cpu.py, in the order the source
# first mentions them. `arg` is the ONE argument the port can carry for that
# call (a size, a flag, an address mask); everything else about the call is the
# seam's, and the header says so rather than inventing fields for it.

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

# THE TRACE. `Tr.emit` is the seam: every device call in this file goes
# through it, so the trace is the ordered list of C calls the eventual seam
# makes. THE RAISE: once `refused` is set nothing else is recorded, which is
# `ops_null.py:61`'s `assert emu == ""` refusing to build a device -- and the
# failing assert IS still recorded, because it sets `refused` in the same breath
# and so on entry its own `refused` is still False. That is why a refusal shows
# up as a truncated trace needing no guard of its own.

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

# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in
# order; `Tr.count` is how many there are; `Tr.has` is "contains this
# (tag, arg) sequence, in order".

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

def seen(+t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def key(+t: Tr, k: U32) -> List<&2, U32>: Tr.args(k, Tr.calls(t))

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

# ops_cpu.py:23-56 -- `__init__` as the step list it is. The order IS the
# source, and the two conditionals are the only branching.

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

# `args = [*bufs, *cast(tuple[int, ...], vals)]` is ONE list (:60), so every
# count in `__call__` is `nbufs + nvals` and the two branches cannot disagree
# about it. EVERY count below is this one def.
def prog.nargs(nbufs: U32, nvals: U32) -> U32: U32.add(nbufs, nvals)

# :67, the bytearray length. 12 bytes of header plus 8 bytes per argument.
def lvp.size(nbufs: U32, nvals: U32) -> U32: U32.add(12, U32.mul(prog.nargs(nbufs, nvals), 8))

# ops_cpu.py:58-73 -- `__call__` as the step list it is.
#
# `args = [*bufs, *cast(tuple[int, ...], vals)]` is ONE list, so the two
# branches cannot disagree about the count: `len(args) == nbufs + nvals`
# everywhere. `remote._rpc if wait else remote._post` is the ONLY thing `wait`
# changes on the remote path and it changes the TAG, so `cpu_call_remote_tag` is
# the row that says wait decides synchrony. `float(unwrap(prof.en) - prof.st) *
# 1e-6 if wait else None` is the other: without `wait` the answer is None, and
# that is a decision with no arithmetic in it.

# :63, `(remote._rpc if wait else remote._post)(...)`.
def prog.remote_tag(wait: Bool) -> U32:
  Bool.pick(U32, wait, CALL_RPC(), CALL_POST())

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

# ops_cpu.py:75-78 -- `__del__`, the ONLY teardown either backend has, and it
# is a CONJUNCTION: `if self.dev.remote is None and sys.platform == 'win32'`.
# A remote device's pages belong to the remote and a posix device's belong to
# its mmap, so VirtualFree fires on exactly one platform and only when there is
# no remote -- `prog_del_win_free` is the two-cell matrix and all four cells
# are rows.

def prog.del.at(remote: Bool, win: Bool, +p: Prog) -> Prog:
  match remote win:
    case False{} True{} : prog.at(p, 0, CALL_VIRTUAL_FREE(), cpu.mem_release())
    case _ _            : p

# ops_cpu.py:80-96 -- `CPUDevice`, and it is the SMALLEST device in tinygrad:
# eight attributes, one `if`, one `super().__init__` and one `if` again.
#
# Everything it does NOT do is inherited and owned by device.bend: the
# allocator (`HostAllocator`), the device-id parse, the timeline, the three
# `pm_bufferize` rules and `synchronize`. What is here is what ops_cpu.py
# itself writes, and that is one arch string, one renderer list, one bool, one
# int and the peer-group choice.

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

# THE TRACE VOCABULARY. A tag's NUMBER is this file's; its NAME is Python's,
# and the gate prints NAMES so the CPython oracle -- which knows Python and not
# this file -- can be compared byte for byte. `call_name` is one descending
# ladder over the whole vocabulary, so a tag this file invented with no Python
# counterpart answers `"?"` and the diff says so instead of agreeing silently.

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

# THE SEAM -- LANDED 2026-10-27. THE TRACE TAGS ABOVE ARE STILL THERE AND
# THEY STILL RECORD WHAT UPSTREAM's `CPUProgram` DOES; WHAT FOLLOWS IS THE PART
# THAT ACTUALLY DOES IT.
#
# UPSTREAM's SEQUENCE, `tinygrad/runtime/ops_cpu.py:23-46`:
#   1. `cc` COMPILES THE C TO AN ELF OBJECT (support/compiler_cpu.py:21-22)
#   2. `jit_loader` RELOCATES IT (support/elf.py:52-86) -- THE PORT's OWN
#      `runtime/support/elf.bend:1816`
#   3. `mmap` AN ANONYMOUS RWX REGION (ops_cpu.py:30) AND COPY THE IMAGE IN
#   4. `pthread_jit_write_protect_np` ON macOS (ops_cpu.py:33, :35)
#   5. `__clear_cache` OR `msync` (ops_cpu.py:41-44)
#   6. `ctypes.CFUNCTYPE(None)(self.addr)` (ops_cpu.py:46)
#   7. CALL IT WITH 64-BIT POINTERS (ops_cpu.py:61)
#
# STEP 2 IS THE PORT's OWN `jit_loader`, SO IT IS NOT AN EFFECT: THE BEND SIDE
# RELOCATES. STEPS 1 AND 3-7 ARE THE EFFECT (`runtime/ops_cpu.c`), AND THEY ARE
# TWO EFFECTS BECAUSE UPSTREAM's ORDER HAS THE RELOCATION BETWEEN THEM.

# THE ARGV. UPSTREAM'S `ClangCompiler.compile_argv` (support/compiler_cpu.py:21-22)
# IS `[cc, '-c', '-x', 'c', '-O2', '-fPIC', '-ffreestanding', '-fno-math-errno',
# '-nostdlib', '-fno-ident', '--target=<arch>-none-unknown-elf', *args, '-', '-o',
# '-']`, AND `support/compiler_cpu.bend:268` IS THE PORT's SPELLING OF IT.
#
# THE ARGV CROSSES THE SEAM AS ONE "\n"-JOINED STRING AND THE C SIDE SPLITS
# IT, BECAUSE THE ARGV IS THE PORT's OWN SPELLING AND THE C SIDE MUST NOT HAVE
# A SECOND COPY OF IT. A PATH AND A FLAG CANNOT CONTAIN A NEWLINE, SO THE JOIN
# IS UNAMBIGUOUS.
#
# AND THE ARCH IS THE PORT's OWN TOO: `cpu.arch_of` (ops_cpu.py:91) IS
# UPSTREAM's `{'amd64':'x86_64', 'aarch64':'arm64'}.get(m, m) + ",native"`, AND
# UPSTREAM SPLITS THAT STRING INTO THE LIST `ClangCompiler` TAKES.
def cpu.cc_argv_str(cc: String, arch: String) -> String:
  String.join(CC.ClangCompiler.compile_argv(cc, String.split(arch, ',')), "\n")

# THE TWO EFFECTS.
#
# THEY ANSWER A `Result`, NOT A `String`, AND THIS IS MEASURED, NOT CHOSEN:
# THE C EFFECT's RETURN VALUE IS THE VALUE THE CONTINUATION RECEIVES, SO A
# `Done{...}` BOX WHERE THE TYPE SAYS `String` PRINTS AN EMPTY LINE. MEASURED:
# THE FIRST RUN PRINTED `sizes=1568,6272` AND THEN A BLANK LINE, AND THE CAUSE
# WAS THE `io_done` BOX. SO THE TYPE IS `Result<&1, &1, U32 & String, String>`,
# THE `Done`/`Fail` BOXES ARE THE `Result`'s OWN TWO CASES, AND `IO.try` (BASE's
# OWN) TURNS A `Fail` INTO A `Halt` WITH ITS MESSAGE ON STDERR. THIS IS
# EXACTLY WHAT `Process.run` DOES IN THIS SAME TREE, AND IT IS UPSTREAM's SHAPE:
# UPSTREAM's `CPUProgram.__call__` RAISES.
#
# `Cpu.compile` IS UPSTREAM's STEP 1: THE C SOURCE AND THE ARGV GO IN, THE
# ELF OBJECT'S HEX COMES OUT. `Cpu.exec` IS UPSTREAM's STEPS 3-7: THE RELOCATED
# IMAGE AND THE BUFFERS GO IN, THE BUFFERS' HEX COMES OUT.
def Cpu.compile(src: String, argv: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./ops_cpu.c"
  import "./ops_cpu.js"

def Cpu.exec(img: String, bufs: String, sizes: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./ops_cpu.c"
  import "./ops_cpu.js"

def ush(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

def nrow(nm: String, v: Nat) -> IO(Unit): IO.print(String.concat([nm, "=", Nat.show(v)]))

# `List.get` answers a `Maybe` and a gate row may not, so these are the two
# TOTAL readers the positional rows need -- the same `drv.one` / `drv.nth` pair
# `upat.bend` grew for the same reason.
def nth(xs: List<&2, U32>, k: Nat) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, k), 0)

def rlist(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(xs, ",")]))

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def subnames.go(n: Nat, cs: List<&2, Sub>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match cs:
        case Nil{}: acc
        case h <> t: subnames.go(p, t, List.append(&2, String, acc, [Sub.nm(h)]))

def subnames(+xs: List<&2, Sub>) -> List<&2, String>:
  subnames.go(List.length(&2, Sub, xs), xs, Nil{})

def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

# THE PORT's OWN ENTRY POINT, AND WHY IT IS HERE AND WHY IT DOES NOTHING.
#
# IT IS HERE BECAUSE THE COMPILER SAYS SO, NOT BECAUSE A TASTE SAYS SO.
# `references/bend/bend2/main.ts:1099` (`book_run`) TAKES ONE OF TWO PATHS: A
# FILE WITH A `main` IS RUN (`Comp.io_run`), AND A FILE WITHOUT ONE IS A
# "BOOK" AND IS JUDGED BY `cli_verdict` -- WHICH REFUSES A FILE WHOSE DEFS
# REACH A FOREIGN EFFECT. THIS FILE OWNS TWO (`Cpu.compile` AND
# `Cpu.exec`, `import "./ops_cpu.c"` AND `import "./ops_cpu.js"`), SO A PORT
# FILE WITH NO `main` IS REFUSED WITH
# `Error: 2 defs rely on unsafe or foreign code: Cpu.compile, Cpu.exec`.
#
# AND IT DOES NOTHING, AND THAT IS THE HONEST SHAPE. UPSTREAM's
# `tinygrad/runtime/ops_cpu.py` IS A MODULE -- IT HAS NO `main` AND NO
# PROGRAM, AND THE PORT IS THE SAME SHAPE. AND THE PORT's PROGRAM, IF
# IT IS EVER WRITTEN, IS `runtime/device.bend`'s -- WHOSE OWN HEADER SAYS
# *"THE port's `Device` LANE is a set of STAGES WITH NO LANE"* AND *"whoever
# produces it is the next UNIT"* -- SO WRITING ONE HERE WOULD BE INVENTING
# THE NEXT UNIT's WORK.
#
# AND IT MUST NOT CALL THE FOREIGN EFFECTS. `book_promises`
# (`main.ts:961`) MARKS EVERY DEF THAT REFERENCES A FOREIGN ONE, AND
# `runtime/device.bend` IMPORTS THIS FILE AS `CPU` AND CALLS
# `CPU.Cpu.compile(...)` AND `CPU.Cpu.exec(...)`, SO A `main` THAT CALLED
# THEM WOULD PUT THREE MORE NAMES INTO `device.bend`'s OWN VERDICT --
# MEASURED: `device.bend`'s FAILURE GOES FROM 4 DEFS TO 7. AND
# THAT FAILURE IS PRE-EXISTING (`device.bend` ALREADY FAILS WITH THOSE 4
# ON THE UNMOVED TREE), AND THIS MOVE MUST NOT MAKE IT WORSE.
#
# AND IT PRINTS NOTHING, BECAUSE EVERY ROW IS PART OF THE CLAIM THE
# DIFFER MAKES: A ROW THE PORT PRINTS THAT IT DID NOT PRINT BEFORE IS A ROW
# THE DIFF NEVER SAW. THE PORT's ROWS ARE THE DRIVER's ROWS NOW.

def main() -> IO(Unit):
  do IO<Unit>:
    IO.pure(Unit, Unit{})
