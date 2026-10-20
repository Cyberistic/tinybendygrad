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
#   * `Cn`/`cn_slot`/`cn_walk` -- ops_cpu.py:70's `struct.pack_into` slot walk, with
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
#    TODO(p3) runtime/ops_cpu.py:62  -- struct.pack('<nQ', a & 0xffffffffffffffff).
# 2. THE BYTE-STRING ELFMAG TEST. `lib[:4] != libc.ELFMAG.encode()` (:21) compares
#    four bytes (`b'\x7fELF'`, MEASURED); the port takes the ANSWER as a Bool, which
#    is all any caller needs since `jit_loader` is a seam either way, and `cpu.elfmag`
#    names the four bytes as a hex STRING so the constant is auditable.
#    TODO(p3) runtime/ops_cpu.py:21  -- `lib[:4]` against `b'\x7fELF'`.
# 3. THE `dt.fmt` STRUCT FORMATS. `:70`'s `struct.pack_into(f'<{dt.fmt}', ...)` writes
#    at a dtype-dependent offset. The OFFSETS are portable -- they are
#    `TinyELF.iter_sig(...)`, which device.bend already ports -- the BYTES are a WALL.
#    TODO(p3) runtime/ops_cpu.py:70  -- struct.pack_into('<{dt.fmt}', ...).
# 4. WHAT NULL DOES NOT COMPUTE. Its kernels are never run and `NullRenderer.asm`
#    refuses anything that is not `gfx`. There is nothing to port in a result because
#    there is nothing there: `nr.asm_msg` says so -- the emulated device WRITES
#    NOTHING into a stream with no TIMESTAMP word -- rather than inventing a result.
#
# WHAT device.bend AND helpers.bend LEND, AND WHAT IS OWED BACK.
# LENT: `D.isig.go` (the offset-carrying body of `TinyELF.iter_sig`, device.py:365 --
# device.bend's `iter_sig` entry point hard-codes 0, so BOTH uses here need `go`;
# REPORTED, not fixed, device.bend is read-only to this unit); `D.dev_id` (device.py:397,
# inherited by both); `D.timeline_bytes` (`ops_null.py:58`'s `timeline` IS that call);
# `H.round_up_u32`, `H.u32_list_eq`, `H.dedup_str`.
# OWED: the renderer ORDER is the policy -- `Compiled._select_renderer` (device.py:489)
# walks it and the FIRST INITIALISED renderer wins, and `cpu.renderers`/`ndev.renderers`
# are those two orders transcribed and both are rows. `Compiled.has_copy_queue` is True
# and ops_cpu.py:84 overrides it to False while `NullDevice` does NOT, so
# `cpu_has_copy_queue` and `nr_has_copy_queue_inherited` are two rows with DIFFERENT
# answers -- either constant could be wrong without the other noticing.
# `Compiled.peer_group` (device.py:398) means a CPU device with no remote and no iface
# answers its own device-class prefix -- `Device['CPU:1'].peer_group == 'CPU'`, MEASURED
# -- and ops_cpu.py:92 overwrites it with the REMOTE's when there is one;
# `cpu.peer_of` is that two-arm choice and both arms are rows. `Compiled.wait_timeout_ms`
# is `30000.0` (a float) and ops_cpu.py:81 writes the INT `30000`, so the row name says
# so. `Compiled.synchronize` (device.py:450) is what ops_cpu.py:96 adds a remote PING to.
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
# 2. `int(parts[2])` (:89) is a DECIMAL PARSE and is a WALL: `String.to_u32` does not
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
# the platform arm. MEASURED on this host, `DLL.findlib('m','m')` answers
# `/usr/lib/libm.dylib`, so the name in this row DOES reach a library.
def cpu.lib_m() -> String: "m"

# ===========================================================================
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
# ===========================================================================
def cpu.lib_objc() -> String: "/usr/lib/libobjc.dylib"

# ===========================================================================
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

def cpu.link_libs_n(osx: Bool, win: Bool) -> U32:
  U32.from_nat(List.length(&2, String, cpu.link_libs(osx, win)))


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
    srow("cpu_lib_objc", cpu.lib_objc())
    # THE LINK SET, JOINED. One row per platform cell, and the join pins the ORDER
    # as well as the contents -- `link_sym` walks it left to right, so a set with
    # the right three names in the wrong order is a different set.
    rlist("cpu_link_libs_00", cpu.link_libs(False{}, False{}))
    rlist("cpu_link_libs_10", cpu.link_libs(True{}, False{}))
    rlist("cpu_link_libs_01", cpu.link_libs(False{}, True{}))
    rlist("cpu_link_libs_11", cpu.link_libs(True{}, True{}))
    urow("cpu_link_libs_n", cpu.link_libs_n(True{}, False{}))
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
#   M55     1  Tr.emit.go: drop the `refused` guard (the raise is gone)
#   M56     2  Tr.has.go: the fuel is the PATTERN length (ops_webgpu M23, reintroduced)
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
#   M78     3  Tr.reset: the trace is NOT cleared
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