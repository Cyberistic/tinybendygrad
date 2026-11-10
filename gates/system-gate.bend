# gates/system-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/support/system.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/runtime/support/system.bend as P
import ./../tinybendygrad/helpers.bend as H

def Meta.has_cpu_mapping(m: P.Meta) -> Bool:
  match m:
    case P.Meta{has_cpu_mapping, hMemory}: has_cpu_mapping

def pci.map_size(bar_size: U32, off: U32, size: U32) -> U32:
  P.pci.map_size.pick(U32.sub(bar_size, off), size)

# ===========================================================================
# :292-293 `PCIAllocationMeta` AND :295-355 `PCIIfaceBase`.
# ===========================================================================

# `@dataclasses.dataclass class PCIAllocationMeta: mapping:VirtMapping;
#  has_cpu_mapping:bool; hMemory:int=0`
#
# THE field order and the names, in this order, and the THIRD one defaulted. The
# oracle read the field list out of the live dataclass:
#   fields   = ['mapping', 'has_cpu_mapping', 'hMemory']
#   defaults = [MISSING, MISSING, 0]
# so only `hMemory` has a default and `PCIAllocationMeta('M', False)` gives
# `('M', False, 0)`.
#
# `mapping` is a `VirtMapping`, which is `support/memory.py`, so the port carries the
# two fields this file's own logic reads and says so. What survives is the thing
# worth checking: THE TWO SITES BUILD IT DIFFERENTLY, and
#   :321 `PCIAllocationMeta(mapping, has_cpu_mapping=True, hMemory=paddrs[0])`
#   :325 `PCIAllocationMeta(mapping, cpu_access, hMemory=mapping.paddrs[0][0])`
# :321's second field is the LITERAL True and :325's is the `cpu_access` ARGUMENT. A
# port that read `cpu_access` at both sites would make the sysmem path claim a CPU
# mapping it does not have, and `PCIIfaceBase.free`'s
# `if storage.meta.has_cpu_mapping and self.remote is None: FileIOInterface.munmap(...)`
# would then unmap a buffer that was never mapped. `Meta.of` takes the argument and
# `meta.sysmem` passes True, so the LITERAL is a def of the call site.
def rmm.int_en(k: U32, el: U32) -> U32: U32.mul(U32.add(k, 1), el)

# :372 the cmd choice, and the ADDRESS with it: sysmem uses `self.addr` and the node's
# memory space, everything else uses `self.off` and the BAR's. Getting these two the
# wrong way round reads the right bytes from the wrong place.
def TCP_NODELAY() -> U32: 1
# --- :84-87 `reserve_va`: the NEGATIVE CASE IS IN THE PYTHON SOURCE -----------
def VA_SZ() -> U32: 0                              # 68719476736 == 16 << 32: the low word is 0
# :75 `os.system("sudo modprobe vfio-pci disable_idle_d3=1")` -- WALL 2's plain string,
# and it is CONDITIONAL on `/sys/module/vfio` being absent.
def Tr.calls(t: P.Tr) -> List<&2, P.Call>:
  match t:
    case P.Tr{calls, next, reserved, have_atomic, have_sys, refused}: calls

def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def first_arg(k: U32, +cs: List<&2, P.Call>) -> U32: P.head_u32(List.get(&2, U32, P.Tr.args(k, cs), 0n))

# ===========================================================================
# A BOUNDED `%x`. WALL-FREE, and the bound is written down because it IS the
# claim: `hx.d4` is exactly four digits and `hx.q` DROPS the leading zeros with an
# ARITHMETIC digit count, because a per-character strip has no base case a `match`
# can name (bend2-constraints.md, position 6880). Everything here is under 65536,
# which is true of every vendor id and device id in this file (:117's `f"{v:x}:{d:x}"`).
# ===========================================================================

# :136 `cl(device[:2], pcibus)` -- the device CLASS is the first TWO characters of the
# device head, and it is two and not one and not three. `AM` for AMD, `CU` for CUDA,
# `NPU` would be three. So this is a genuine `take(2)` and a row.
def Tr.of() -> P.Tr: P.Tr{Nil{}, 0, Nil{}, False{}, False{}, False{}}

def VA_LO() -> U32: 0
# --- the wire formats, :363 ---------------------------------------------------
#
# `REMOTE_REQ, REMOTE_RESP = '<BIIQQQ', '<BQQ'` and the comment spells the fields:
# `# (cmd, dev, bar, arg0, arg1, arg2) and (status, resp0, resp1)`.
#
# THE COMMENT IS NOT EVIDENCE, so the oracle PROVED the field order by a sentinel
# round-trip -- six distinct sentinels packed and unpacked positionally, and the
# unpacked tuple came back in the order they were sent. That is a measurement of the
# LAYOUT and not a restatement of the comment, which is the distinction
# `agent-core.md` insists on. The offsets:
#   REMOTE_REQ  '<BIIQQQ'  size 33   cmd@0 dev@1 bar@5 arg0@9 arg1@17 arg2@25
#   REMOTE_RESP '<BQQ'     size 17   status@0 resp0@1 resp1@9
#
# A SWAPPED `dev` and `bar` is a silently wrong request, and the byte sizes are the only
# thing a count gate would catch -- so the port carries the six FIELD NAMES in order
# and the gate prints them.
def VA_LO2() -> U32: 4096

# 0x7f0000100000 is the alloc_sysmem `vaddr` fixture, and its LOW word is 1048576 --
# nonzero, which is the point. Using VA_LO() (whose low word is 0) for a `vaddr`
# argument made `alloc.fixed` answer 0 and every MAP_FIXED row read as "unset".
def Tr.count(k: U32, +cs: List<&2, P.Call>) -> U32:
  P.Tr.count.go(List.length(&2, P.Call, cs), k, cs, 0)

# does the trace CONTAIN this (kind, arg, string) sequence, in order? `at` is how
# much of the pattern is matched so far, read out of the pattern BY INDEX rather
# than carried as a second list: the head and the tail of ONE destructure share a
# binder, and a descent may not use that binder twice.
#
# THE fuel is the trace length and the answer is `at == patlen`. With the fuel set
# to the PATTERN length, `case 0n:` fires after patlen trace entries and returns
# `True{}` without ever reading `at`, so a reversed pattern matches and so does a
# pattern element that never occurs. MEASURED in `ops_webgpu.bend`, and the
# matcher is copied from the fixed one.
# `atomic_lib` is the `sys.platform == "linux"` gate, and it is a def OF the
# platform so the fixture can drive both arms: on macOS the answer is None and
# `cap.atomic_on` must be False.
def sys.reserve_va(+va_start: U32, va_size: U32, osx: U32, +t: P.Tr) -> P.Tr:
  P.sys.reserve_va.put(va_start, va_size, osx,
    List.contains(U32, U32.is_eq, P.Tr.reserved(t), va_start), t)

# :91-92 `lock_memory`: `if libc.mlock(c_void_p(addr), size): raise`. A NONZERO
# return is the refusal, so the port emits the call and then truncates on a
# nonzero result. The `addr` is a 64-bit pointer, so only its LOW word travels.
def t_05_va() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.reserve_va(VA_LO(), VA_SZ(), P.CAP_NO(), Tr.of()))
    urow("sy_va_first_nmmap", Tr.count(P.CALL_MMAP(), Tr.calls(a)))
    urow("sy_va_first_flags", first_arg(P.CALL_MMAP(), Tr.calls(a)))
    +b : P.Tr <- IO.pure(P.Tr, sys.reserve_va(VA_LO(), VA_SZ(), P.CAP_NO(), a))
    urow("sy_va_cached_nmmap", Tr.count(P.CALL_MMAP(), Tr.calls(b)))
    urow("sy_va_nreserved", U32.from_nat(List.length(&2, U32, P.Tr.reserved(b))))
    +c : P.Tr <- IO.pure(P.Tr, sys.reserve_va(VA_LO2(), VA_SZ(), P.CAP_NO(), b))
    urow("sy_va_other_nmmap", Tr.count(P.CALL_MMAP(), Tr.calls(c)))
    urow("sy_va_nreserved2", U32.from_nat(List.length(&2, U32, P.Tr.reserved(c))))

def gid.TAIL_LEN() -> U32: 4
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# a comma-joined U32 list, in list order. `List.append` is `xs ++ ys`, so this
# fold APPENDS and must not reverse at the end.
def REQ_OFF_ARG0() -> U32: 9
def bars.PADDR_BASE() -> U32: 2097152               # 0x200000

# ===========================================================================
# :207-268 -- `PCIDevice`, AND THE sysfs PATH TABLE.
#
# EVERY path is `f"/sys/bus/pci/devices/{self.pcibus}/<tail>"` and every one of them
# is opened with a DIFFERENT flag set, and a wrong flag is a silently wrong `open` --
# `O_WRONLY` where the code means `O_RDWR` fails on a device node, and `O_RDWR` where
# it means `O_WRONLY` succeeds and then truncates nothing. So the path and the flags
# are ONE claim.
#
# MEASURED, and the TAILS are a table because there are ten of them and a mis-spelled
# tail is a `FileNotFoundError` at device-open time:
#   enable          O_RDWR   :211 open, :240 write "1"
#   driver          EXISTS   :214
#   driver/unbind   O_WRONLY :215 write the pcibus
#   driver_override O_WRONLY :223 write "vfio-pci"
#   config          O_RDWR|O_SYNC|O_CLOEXEC  :242
#   iommu_group     READLINK :225
#   resource        O_RDONLY :259  (the multi-line one, `bar_info`)
#   resource        O_RDONLY :267 read, for `resize_bar`
#   resource        O_RDWR|O_SYNC|O_CLOEXEC  :256  (`bar_fd`, cached)
#   reset           SYSTEM   :247
#
# :211 and :216 BOTH look at `enable`/`driver`, and :216 re-checks `driver` AFTER the
# unbind -- that second check is the "Driver is bound" refusal and it is a
# TRUNCATION. The order is the claim: check, unbind, CHECK AGAIN.
# ===========================================================================

def cap.load_sys(t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_CDLL(), P.LIB_SYS(), "System", t)

# ===========================================================================
# :56-59 -- `write_sysfs`, AND THE `sudo` STRING OF WALL 2.
#
#   :57 `if FileIOInterface(path, os.O_RDONLY).read().splitlines()[0] != (expected or value):`
#   :58 `  os.system(cmd:=f"sudo sh -c 'echo {value} > {path}'")`
#   :59 `  if FileIOInterface(path, os.O_RDONLY).read().splitlines()[0] != (expected or value): raise RuntimeError(...)`
#
# THE STRING, verbatim: `sudo sh -c 'echo ` + value + ` > ` + path + `'`. There is
# NO trailing space and there are spaces on BOTH sides of the `>`. My first oracle
# cut added a trailing space to every one of these and the port would have
# inherited it, which is why the oracle now EVALUATES the f-string out of the
# source text instead of retyping it, and why the gate prints the string and not a
# boolean about it. `String.concat` will happily drop a literal and still leave two
# strings that agree on a length.
# ===========================================================================

def Tr.has(+cs: List<&2, P.Call>, +pat: List<&2, P.Call>) -> Bool:
  P.Tr.has.go(List.length(&2, P.Call, cs), List.length(&2, P.Call, pat), cs, pat, 0n)

# :62 and :65 as a trace: the LINUX platform loads 'atomic' and BOTH platforms load
# "System", and the two are separate `CDLL` calls. The order is fixed by the
# fixture, not claimed from Python -- the two are independent cached properties.
def cap.load(t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_CDLL(), 0, "atomic", t)

# WHICH arm answered :51's `getattr`. This is the part the two spellings share
# and the part a reader would get wrong: MAP_LOCKED is a plain ternary, and
# MAP_POPULATE asks `mmap` first. `cap.populate_from` is the answer the gate
# checks, and it is a TABLE ROW rather than an inference from the value, because
# on Linux the value is 0x8000 either way and only the table says why.
def cap.populate_from(osx: U32) -> U32:
  Bool.pick(U32, U32.is_eq(osx, P.CAP_YES()), P.CAP_GETATTR(), P.CAP_MMAP())

# `mmap.MAP_HUGETLB` is ABSENT on macOS, which is why :100 reaches for
# `libc.MAP_HUGETLB` instead. MEASURED: `mmap.MAP_HUGETLB` -> AttributeError here.
# :57 the comparison, `read().splitlines()[0] != (expected or value)`.
def sysfs.matches(current: String, expected: String, +value: String) -> Bool:
  String.eq(current, P.sysfs.want(expected, value))

def RESP_OFF_RESP0() -> U32: 1
def RESP_SIZE() -> U32: 17
def pci.map_flags(+addr: U32) -> U32: P.pci.map_flags.pick(addr)

# `size or (bar_info(bar)[1] - off)` -- the FALSY side is 0, not None.
# :69-70 the write is UNCONDITIONAL on the first access and never again.
def sys.pagemap(first: Bool, +t: P.Tr) -> P.Tr:
  Bool.pick(P.Tr, first,
    P.Tr.emit(P.CALL_OPEN(), P.O_RDONLY(), P.PAGEMAP_PATH(),
      P.sysfs.apply(P.PAGEMAP_SYSFS(), P.PAGEMAP_VALUE(), "", True{}, True{}, t)),
    t)

# :84-87 `reserve_va`. THE negative case lives in the python source, which is the
# best kind: the comment at :86 says "cached, runs only once per range", and the
# second call for the SAME `va_start` must emit NOTHING. A port that re-maps would
# hand the same virtual address to two mappings and the second `MAP_FIXED_NOREPLACE`
# would fail inside the kernel, silently.
#
# THE FLAGS, :87: `mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS | MAP_NORESERVE |
# MAP_FIXED_NOREPLACE`. `MAP_LOCKED` and `MAP_POPULATE` are NOT here, which is the
# one thing easy to get wrong, and MAP_ANONYMOUS is the platform-dependent one.
# MEASURED: the source's own Linux OR is 0x100422 == 2 | 0x20 | 0x400 | 0x100000.
def gid.of(+tail: U32) -> String: P.gid.of.p2(U32.shrn(tail, 16n), U32.and(tail, 65535))

# ===========================================================================
# :50-51 -- THE mmap CONSTANT TABLE, BOTH DIRECTIONS.
#
# The forward direction is the VALUE and the reverse is the NAME, and the reverse
# exists because the three platform-dependent entries are the ones a reader needs
# to check: MAP_LOCKED and MAP_POPULATE must both be 0 on OSX, and MAP_ANONYMOUS
# must be 0x20 on Linux and 0x1000 on macOS. A port that computed any of the three
# as a constant would get one platform right for the wrong reason and the other
# wrong outright.
#
# `mapflag_names` is INDEXED BY THE ANSWER, so the two directions read the SAME
# list and cannot disagree. The thirteen rows are the flags :87/:100/:101/:263
# actually OR together.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def mapflag_name(i: U32) -> String: P.mapflag_name.pick(i)

# ===========================================================================
# :11-16 -- `filter_visible_devices`, THE INDEX-STRING PARSER.
#
# `if '-' in (idstr:=DEV.target(device).indices)[1:]: ids = list(range(int(idstr.split('-')[0]),
#  int(idstr.split('-')[1])+1))` else `ids = [int(x) for x in idstr.split(',') if x.strip()]`
#
# THE `[1:]` IS the whole of the RANGE DETECTION and it is not decoration: a LEADING
# '-' is not a range separator, so `DEV=AMD:-1` is a LIST whose single element is
# the NEGATIVE number -1, not a range. MEASURED in CPython, and it is the one
# fixture a naive `'in idstr` port gets wrong.
#
# THE SECOND `-` IS IGNORED: `0-1-2` splits to `['0','1','2']` and
# `idstr.split('-')[1]` is `'1'`, so the range is 0..1 and the `2` is DISCARDED.
# `vis.range` takes the two halves as SEPARATE arguments for exactly that reason,
# and the caller supplies `split[0]` and `split[1]` -- never the whole string.
#
# `3-1` is an EMPTY range, not an error: `range(3, 2)` is empty in Python, and
# :16's `return [...] if ids else devs` turns an empty id list into "no filter at
# all". So an out-of-order range SILENTLY MEANS EVERY DEVICE, and that is the
# single most dangerous line in this file.
# ===========================================================================

# `'0-3' -> [0,1,2,3]`, `'0-0' -> [0]`, `'3-1' -> []`, `'10-12' -> [10,11,12]`.
# The count is `hi - lo + 1` CLAMPED AT ZERO, spelled as a clamp because `U32`
# cannot hold a negative count and `0 - 1 + 1` wraps to 4294967295.
def mapflag_of_linux(v: U32) -> U32: P.mapflag_of.go(v, P.mapflag_values_linux(), 0)

# THE absent answer is 0, AND that is safe because every legal SIZE IS >= 1 -- the
# format table has no zero row. The INDEX direction uses the 4294967295 sentinel
# instead, and `sy_el_absent` and `sy_eli_absent` are the two rows that say so.
def elemsize(c: String) -> U32: P.elemsize.maybe(List.get(&2, U32, P.FMT_SIZES(), U32.to_nat(P.elemsize.at(c))))

# `st` and `en` in BYTES. `st = (sl.start or 0) * el` and
# `en = (len(self) if sl.stop is None else sl.stop) * el`, so an absent stop is the WHOLE
# view in ELEMENTS and then scaled. `nbytes` is `len(self)`.
def Tr.refused(t: P.Tr) -> Bool:
  match t:
    case P.Tr{calls, next, reserved, have_atomic, have_sys, refused}: refused

def t_04_write_ok() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.sysfs.apply(P.PAGEMAP_SYSFS(), P.PAGEMAP_VALUE(), "", True{}, True{}, Tr.of()))
    urow("sy_write_ok_nsys", Tr.count(P.CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_ok_nread", Tr.count(P.CALL_READ(), Tr.calls(t)))
    row("sy_write_ok_read", Tr.has(Tr.calls(t), [P.Call{P.CALL_READ, 0, P.PAGEMAP_SYSFS()}]))
    row("sy_write_ok_refused", Tr.refused(t))

def rpc.port(has_colon: Bool, port: U32) -> U32: P.rpc.port.pick(has_colon, port)

# :406 `f"remote:{host}:{port}:{d}"` -- FOUR colon-separated fields, and `d` is the
# device the node reported, not the one that was asked for.
# --- :292-293 the Meta field order and the LITERAL True at :321 ---------------
def meta.bar(+hMemory: U32, +cpu_access: Bool) -> P.Meta: P.Meta.of(cpu_access, hMemory)

# :297 `@property def peer_group(self) -> str: return getattr(self.pci_dev,
# 'peer_group', type(self.pci_dev).__name__)`
#
# THE `getattr` DEFAULT is the class name, and only ONE of the three classes in this
# file actually sets `peer_group`. MEASURED, from the three `__init__`s:
#   PCIDevice       -- no assignment                    -> "PCIDevice"
#   USBPCIDevice    -- :272 `f"USBPCIDevice_{pcibus}"`  -> "USBPCIDevice_0000:03:00.0"
#   RemotePCIDevice -- :430 `"remote:%s:%d" % ...`       -> "remote:10.0.0.1:6667"
#
# SO the fallback fires for exactly one of the three, and for that one the value is
# the class name. `face.peer_group` is the three-way table and `face.has_explicit` is
# the second direction, so the gate can ask "which class sets it" and "what does the
# fallback give" as two separate claims -- a single-direction row could pass with the
# fallback always on.
#
# THE CROSS-FILE CITATION. `.agents/TODO.md:1374` and `ops_rdma.bend:826` both record
# that `peer_group` is "PCIDevice", not the device head, and both cite this line. THEY
# AGREE WITH THE TABLE ABOVE, and this file gates the value directly rather than
# taking the citation on trust. Reported, not reconciled.
# --- :208 the ORDER of `PCIDevice.__init__` -----------------------------------
def meta.sysmem(+hMemory: U32) -> P.Meta: P.Meta.of(True{}, hMemory)
def Meta.hMemory(m: P.Meta) -> U32:
  match m:
    case P.Meta{has_cpu_mapping, hMemory}: hMemory

def t_10_meta() -> IO(Unit):
  do IO<Unit>:
    +m : P.Meta <- IO.pure(P.Meta, meta.sysmem(512))
    row("sy_meta_sysmem_cpu", Meta.has_cpu_mapping(m))
    urow("sy_meta_sysmem_hmem", Meta.hMemory(m))
    +n : P.Meta <- IO.pure(P.Meta, meta.bar(1024, False{}))
    row("sy_meta_bar_cpu", Meta.has_cpu_mapping(n))
    urow("sy_meta_bar_hmem", Meta.hMemory(n))
    +o : P.Meta <- IO.pure(P.Meta, meta.bar(7, True{}))
    row("sy_meta_bar_cpu_true", Meta.has_cpu_mapping(o))
    urow("sy_meta_bar_hmem_true", Meta.hMemory(o))

# --- :392-393 the socket option SEQUENCE, as a trace --------------------------
# --- Tr.has's NEGATIVE cases. M48 hard-wires the matcher to True{} and this
# function moved NOTHING until these three rows existed: every order row in this file
# was `True` in the baseline, so the whole matcher was unfalsifiable. That is the
# `ops_webgpu` M23 lesson arriving again, and the harness is what found it.
def t_11_has() -> IO(Unit):
  do IO<Unit>:
    row("sy_has_present", Tr.has([P.Call{P.CALL_MMAP, 1, "a"}, P.Call{P.CALL_SYSTEM, 2, "b"}],
      [P.Call{P.CALL_SYSTEM, 2, "b"}]))
    row("sy_has_absent", Tr.has([P.Call{P.CALL_MMAP, 1, "a"}], [P.Call{P.CALL_SYSTEM, 2, "b"}]))
    # the REVERSED pattern: the same two calls, the other way round
    row("sy_has_reversed", Tr.has([P.Call{P.CALL_MMAP, 1, "a"}, P.Call{P.CALL_SYSTEM, 2, "b"}],
      [P.Call{P.CALL_SYSTEM, 2, "b"}, P.Call{P.CALL_MMAP, 1, "a"}]))
    # the right kinds in the right order, but the WRONG argument
    row("sy_has_wrong_arg", Tr.has([P.Call{P.CALL_MMAP, 1, "a"}], [P.Call{P.CALL_MMAP, 2, "a"}]))
    # the right argument, the wrong STRING -- the half a `U32` slot could not carry
    row("sy_has_wrong_str", Tr.has([P.Call{P.CALL_MMAP, 1, "a"}], [P.Call{P.CALL_MMAP, 1, "b"}]))

# :369-370 the INT arm: `sl = slice(k, k + 1)`, so `st = k * el` and `en = (k + 1) * el`.
# MEASURED: k=3 with el=1 gives st=3 en=4.
def rmm.int_st(k: U32, el: U32) -> U32: U32.mul(k, el)
def LOCK_MODE() -> U32: 438                        # 0o666 -- the umask(0) mode

# --- the PCI config register NUMBERS, :142-185 -----------------------------
# READ OUT OF `tinygrad/runtime/autogen/pci.py` by the oracle. These are OFFSETS
# in the 256-byte config space, and :165 adds `bar_off` to one of them.
# MEASURED: the Linux base is 0xa021 and a 2-page contiguous request adds
# MAP_HUGETLB and nothing else, so the mmap flags are 0x4a021 == 303137 at vaddr 0
# and 0x4a031 == 303153 with a vaddr, and a plain one-page request is 0xa031 == 41009.
def ALLOC_HUGE_VADDR0() -> U32: 303137
def Rcmd.hi2() -> U32: 16
def Rcmd.second() -> List<&2, String>: P.list.drop(P.Rcmd.base(), P.Rcmd.names())

# --- the wire formats, :363 ---------------------------------------------------
#
# `REMOTE_REQ, REMOTE_RESP = '<BIIQQQ', '<BQQ'` and the comment spells the fields:
# `# (cmd, dev, bar, arg0, arg1, arg2) and (status, resp0, resp1)`.
#
# THE COMMENT IS NOT EVIDENCE, so the oracle PROVED the field order by a sentinel
# round-trip -- six distinct sentinels packed and unpacked positionally, and the
# unpacked tuple came back in the order they were sent. That is a measurement of the
# LAYOUT and not a restatement of the comment, which is the distinction
# `agent-core.md` insists on. The offsets:
#   REMOTE_REQ  '<BIIQQQ'  size 33   cmd@0 dev@1 bar@5 arg0@9 arg1@17 arg2@25
#   REMOTE_RESP '<BQQ'     size 17   status@0 resp0@1 resp1@9
#
# A SWAPPED `dev` and `bar` is a silently wrong request, and the byte sizes are the only
# thing a count gate would catch -- so the port carries the six FIELD NAMES in order
# and the gate prints them.
# :339 `if b._buf % 0x1000: raise RuntimeError("Host mapping requires a page-aligned
# address")` -- a refusal, and the modulus is a power of two so it is an AND.
def Rcmd.of(s: String) -> U32: P.Rcmd.of.go(s, P.Rcmd.names(), 0)

# A `U32` countdown as the FIRST argument is refused, and a `Nat` countdown cannot be
# read after the arm spends it (bend2-constraints.md, positions 6847 and 1404), so the
# countdown is a `Nat`, the list is the second scrutinee, and the arms cover the CROSS
# PRODUCT -- two bounds instead of one, which is the price and is the honest shape:
# take n of a list shorter than n is a real case here, because `Rcmd.second()` takes
# three of a list that could be shorter.
def sxs(xs: List<&2, String>) -> String: String.join(xs, ",")

# `H.List.head` does not exist in this tree's helpers, so the first element of a
# trace argument list gets its own leaf. `sy_*_arg` rows read a single value and a
# leaf here is what keeps them from having to name the whole list.
def sys.lock_memory(addr_lo: U32, +size: U32, ret: U32, +t: P.Tr) -> P.Tr:
  Bool.pick(P.Tr, U32.is_zero(ret),
    P.Tr.emit(P.CALL_MLOCK_OK(), size, "", t), P.Tr.emit.stop(P.CALL_MLOCK(), size, "", t))

# ===========================================================================
# :98-102 -- `alloc_sysmem`, THE FLAG ARITHMETIC. Four inputs, two outputs, and
# one of the inputs is a WALRUS that only fires on one arm.
#
#   :99  `assert not contiguous or size <= (2 << 20)`
#   :100 `flags = (libc.MAP_HUGETLB if contiguous and (size:=round_up(size, mmap.PAGESIZE)) > mmap.PAGESIZE else 0) | (MAP_FIXED if vaddr else 0)`
#   :101 `FileIOInterface.anon_mmap(vaddr, size, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS|MAP_POPULATE|MAP_LOCKED|flags, 0)`
#
# THE walrus is the whole of it. `size := round_up(size, PAGESIZE)` sits INSIDE the
# `if contiguous and ...` expression, so a NON-contiguous request is NEVER rounded
# -- `size` stays exactly what the caller asked for. `alloc.size` is therefore a
# function of `contiguous` and not just a `round_up`, and a port that hoisted the
# rounding out of the `if` would hand `anon_mmap` a page-rounded size for every
# allocation and silently change every BAR-sized mapping.
#
# `MAP_HUGETLB` needs `size > PAGESIZE` AFTER the rounding, so a one-page contiguous
# request gets NO hugepage flag -- and `MAP_HUGETLB` is absent from `mmap` on macOS,
# which is why :100 says `libc.MAP_HUGETLB`.
#
# MEASURED on the LINUX page size (4096). The host's 16384 answers differently for
# every size below 16 KiB, and the first cut of this port used the host's.
#   size=0x1000 contig=True  vaddr=0      -> size'=0x1000  flags=0x0
#   size=0x2000 contig=True  vaddr=0      -> size'=0x2000  flags=0x40000
#   size=0x2000 contig=True  vaddr=0x7f.. -> size'=0x2000  flags=0x40010
#   size=0x1000 contig=False vaddr=0x7f.. -> size'=0x1000  flags=0x10
#   size=0x1001 contig=True  vaddr=0      -> size'=0x2000  flags=0x40000
# ===========================================================================

def t_05_lock_ok() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.lock_memory(0, 4096, 0, Tr.of()))
    row("sy_lock_ok", Bool.not(Tr.refused(a)))
    row("sy_lock_ok_kind", Tr.has(Tr.calls(a), [P.Call{P.CALL_MLOCK_OK, 4096, ""}]))

def t_05_va_osx() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.reserve_va(VA_LO(), VA_SZ(), P.CAP_YES(), Tr.of()))
    urow("sy_va_osx_first", Tr.count(P.CALL_MMAP(), Tr.calls(a)))
    urow("sy_va_osx_flags", first_arg(P.CALL_MMAP(), Tr.calls(a)))

# --- :67-70 `pagemap`, also a cached_property ---------------------------------
# --- :56-59, four FIXTURE DEFS rather than four binders in one block. --------
# A do-block binder of a `Data` record is AFFINE -- one read -- and a trace needs
# five. So each fixture is its own def, and the rows that read one trace live with
# it. That is the same shape `am/ip.bend` uses and it is the price of the linearity.
def t_05_pagemap() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.pagemap(True{}, Tr.of()))
    +b : P.Tr <- IO.pure(P.Tr, sys.pagemap(False{}, a))
    urow("sy_pagemap_first", Tr.count(P.CALL_OPEN(), Tr.calls(a)))
    urow("sy_pagemap_cached", Tr.count(P.CALL_OPEN(), Tr.calls(b)))
    urow("sy_pagemap_total_reads", Tr.count(P.CALL_READ(), Tr.calls(b)))
    # :69 writes the sysfs knob BEFORE :70 opens /proc/self/pagemap, so the READ
    # comes FIRST. The row had them the other way round and was satisfied by
    # `Tr.has` returning False for a reason that had nothing to do with the paths.
    row("sy_pagemap_order", Tr.has(Tr.calls(b), [P.Call{P.CALL_READ, 0, P.PAGEMAP_SYSFS()}, P.Call{P.CALL_OPEN, 0, P.PAGEMAP_PATH()}]))

# --- :91-92 `lock_memory`: a NONZERO return is the refusal --------------------
def t_05_lock_fail() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.lock_memory(0, 4096, 1, Tr.of()))
    row("sy_lock_fail", Tr.refused(a))
    urow("sy_lock_fail_n", Tr.count(P.CALL_MLOCK(), Tr.calls(a)))

def t_05_cache() -> IO(Unit):
  do IO<Unit>:
    t_05_va()
    t_05_va_osx()
    t_05_pagemap()
    t_05_lock_ok()
    t_05_lock_fail()

# --- :98-102 `alloc_sysmem` ---------------------------------------------------
# the USBPCIDevice constants, :277-282, and they are a fixed table rather than
# arguments because :277 SPELLS them at the call site.
def bars.SRAM_SIZE() -> U32: 524288                 # 0x80000
def VFIO_MODPROBE() -> String: "sudo modprobe vfio-pci disable_idle_d3=1"

# :225 `FileIOInterface.readlink(f".../iommu_group").split('/')[-1]` and :227
# `f"/dev/vfio/noiommu-{iommu_group}"`. MEASURED: the readlink target ends in
# '.../iommu_group', so `split('/')[-1]` is the WORD 'iommu_group' and NOT a number
# -- the number is the second-to-last component, and this file's expression is what
# it is. `pci.iommu_path` takes the group the SEAM resolved.
def SOCK_BUF() -> U32: 67108864                    # 64 << 20
def HEAD_NPU() -> String: "NPU"
def pci.flags_bar() -> U32: P.O_RDWR_SYNC_CLOEXEC()
def Rcmd.lo2() -> U32: 13
# --- :91-92 `lock_memory`: a NONZERO return is the refusal --------------------
def face.is_host_device(+head: String) -> Bool:
  List.contains(String, String.eq, P.HOST_HEADS(), head)

# :339 `if b._buf % 0x1000: raise RuntimeError("Host mapping requires a page-aligned
# address")` -- a refusal, and the modulus is a power of two so it is an AND.
def cfgs(xs: List<&2, P.Cfg>) -> String: P.cfgs.go(xs, Nil{})

def mapflag_of(v: U32) -> U32: P.mapflag_of.go(v, P.mapflag_values(), 0)

# :225 `FileIOInterface.readlink(f".../iommu_group").split('/')[-1]` and :227
# `f"/dev/vfio/noiommu-{iommu_group}"`. MEASURED: the readlink target ends in
# '.../iommu_group', so `split('/')[-1]` is the WORD 'iommu_group' and NOT a number
# -- the number is the second-to-last component, and this file's expression is what
# it is. `pci.iommu_path` takes the group the SEAM resolved.
def pci.iommu_path(+iommu_group: U32) -> String:
  String.concat([P.VFIO_NOIOMMU(), U32.show(iommu_group)])

# ===========================================================================
# :248-249, :258-260, :265-268 -- read_config / write_config / bar_info /
# resize_bar. Four small pure functions over hex text, and all four are pure
# string-or-arithmetic work with no FFI in the middle.
#
# :248 `int.from_bytes(self.cfg_fd.read(size, binary=True, offset=offset), 'little')`
# :249 `self.cfg_fd.write(value.to_bytes(size, byteorder='little'), binary=True, offset=offset)`
# :259 `s, e, _ = FileIOInterface(".../resource", O_RDONLY).read().splitlines()[bar_idx].split()`
# :260 `return (int(s, 16), int(e, 16) - int(s, 16) + 1)`
# :267 `str(int(FileIOInterface(rpath, O_RDONLY).read(), 16).bit_length() - 1)`
#
# THE `+ 1` at :260 IS THE WHOLE OF bar_info and it is inclusive-to-exclusive: a
# resource line '0x7c000000 0x7fffffff 0x00000000' is a bar from 0x7c000000
# INCLUSIVE to 0x7fffffff INCLUSIVE, so the size is 0x4000000 and not 0x3fffffff.
# MEASURED. A `bar_info` that is one byte short is a mapping that faults on its last
# page, which is the worst kind of off-by-one because everything works.
# ===========================================================================

def gid.len() -> U32: 16

# FOUR TAIL BYTES, so EIGHT hex digits, so two `hx.d4` and NOT two `hx.q`: `%x` is
# UNPADDED and a GID's tail is not. MEASURED: 127.0.0.1 gives
# '00000000000000000000ffff7f000001'.
def REQ_FIELDS() -> List<&2, String>: ["cmd", "dev", "bar", "arg0", "arg1", "arg2"]
def VA_ADDR_LO() -> U32: 1048576
def sys.alloc_sysmem(+size: U32, vaddr: U32, +contiguous: Bool, pagesize: U32, t: P.Tr) -> P.Tr:
  P.sys.alloc_sysmem.go(size, vaddr, contiguous, pagesize, P.alloc.ok(size, contiguous), t)

# ===========================================================================
# :126 -- `pci_scan_bus`'s FILTER, and the device table it filters with.
#
#   `return sorted([val for vndr, device, val in all_devs if vndr == vendor and any((device & mask) in devlist for mask, devlist in devices)])`
#
# THE MASK IS NOT DECORATION. AMD's table is `(0xffff, (...))`, so `device & mask`
# is the device ITSELF and the membership is exact. NVIDIA's is `(0xff00, (...))`,
# so `device & 0xff00` STRIPS THE LOW BYTE: MEASURED, `0x2f01 & 0xff00 == 0x2f00`
# and `0x2f00` IS in NVIDIA's list, so device `0x2f01` is ACCEPTED. A port that
# compared `device` instead of `device & mask` would refuse every NVIDIA card whose
# revision is not `0x00`, which is most of them.
#
# THE tables are read out of the callers by the oracle, not typed:
#   ops_amd.py:739  vendor=0x1002  mask=0xffff  11 ids 0x74a1 0x74b5 0x744c 0x7480
#                  0x7550 0x7551 0x7590 0x75a0 0x75a8 0x75b0 0x75b3
#   ops_nv.py:534   vendor=0x10de  mask=0xff00  10 ids 0x2200 0x2400 0x2500 0x2600
#                  0x2700 0x2800 0x2b00 0x2c00 0x2d00 0x2f00
#
# THE NEGATIVE CASES live in the numbers: `0x75b4` is ONE PAST AMD's largest id and
# `0x74a0` is ONE BELOW its smallest, and the same for NVIDIA at `0x3000` and
# `0x2100`. Both are refused. A row that only tested a known-good id could not tell
# a filter from a constant.
# ===========================================================================

# :400 `if r == "local"`. A bare `Bool` and not a `String` on the wire, so the gate can
# ask the question without building the string.
def t_06_alloc_plain() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.alloc_sysmem(4096, VA_ADDR_LO(), False{}, 4096, Tr.of()))
    urow("sy_alloc_mmap_plain", first_arg(P.CALL_MMAP(), Tr.calls(a)))

# the REFUSAL TRUNCATES BEFORE the mmap, so the trace shows no MAP at all.
def t_06_alloc_fixed() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.alloc_sysmem(8192, VA_ADDR_LO(), True{}, 4096, Tr.of()))
    urow("sy_alloc_mmap_huge_fixed", first_arg(P.CALL_MMAP(), Tr.calls(a)))

# 0x7f0000000000 is 139637976727552 and does not fit a U32, so `reserve_va`'s
# `va_start` is a 64-bit ADDRESS. Its LOW word is 0, which is the whole of what the
# cache key needs -- and it is exactly why a `U32` port of the cache would answer
# "already reserved" for EVERY 4 GiB-aligned address, since they all have low word
# 0. The row `sy_va_cached_nmmap` is the one that would catch it.
def t_06_alloc_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.alloc_sysmem(1073741824, 0, True{}, 4096, Tr.of()))
    row("sy_alloc_refused", Tr.refused(a))
    urow("sy_alloc_refused_nmmap", Tr.count(P.CALL_MMAP(), Tr.calls(a)))

def t_06_alloc_huge() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, sys.alloc_sysmem(8192, 0, True{}, 4096, Tr.of()))
    row("sy_alloc_mmap_2p", Tr.has(Tr.calls(a), [P.Call{P.CALL_MMAP, ALLOC_HUGE_VADDR0(), ""}]))
    urow("sy_alloc_mmap_n", Tr.count(P.CALL_MMAP(), Tr.calls(a)))

def t_06_alloc() -> IO(Unit):
  do IO<Unit>:
    # --- :99 the assert
    row("sy_alloc_ok_2m", P.alloc.ok(2097152, True{}))
    row("sy_alloc_ok_2m1", P.alloc.ok(2097153, True{}))
    row("sy_alloc_ok_1g_not_contig", P.alloc.ok(1073741824, False{}))
    # --- :100 the WALRUS: rounded ONLY when contiguous
    urow("sy_alloc_size_1000_contig", P.alloc.size(4096, True{}, 4096))
    urow("sy_alloc_size_1000_plain", P.alloc.size(4096, False{}, 4096))
    urow("sy_alloc_size_1001_contig", P.alloc.size(4097, True{}, 4096))
    urow("sy_alloc_size_1001_plain", P.alloc.size(4097, False{}, 4096))
    urow("sy_alloc_size_2000_contig", P.alloc.size(8192, True{}, 4096))
    urow("sy_alloc_size_1000000_contig", P.alloc.size(16777216, True{}, 4096))
    # --- the flags, term by term
    urow("sy_alloc_huge_1page", P.alloc.huge(4096, True{}, 4096))
    urow("sy_alloc_huge_2page", P.alloc.huge(8192, True{}, 4096))
    urow("sy_alloc_huge_not_contig", P.alloc.huge(8192, False{}, 4096))
    urow("sy_alloc_fixed_0", P.alloc.fixed(0))
    urow("sy_alloc_fixed_nz", P.alloc.fixed(VA_ADDR_LO()))
    urow("sy_alloc_flags_2000_0", P.alloc.flags(8192, True{}, 0, 4096))
    urow("sy_alloc_flags_2000_nz", P.alloc.flags(8192, True{}, VA_ADDR_LO(), 4096))
    urow("sy_alloc_flags_1000_nz", P.alloc.flags(4096, False{}, VA_ADDR_LO(), 4096))
    urow("sy_mmap_base", P.MMAP_BASE_LINUX())
    t_06_alloc_huge()
    t_06_alloc_fixed()
    t_06_alloc_plain()
    t_06_alloc_refuse()

def rpc.options(t: P.Tr) -> P.Tr: P.rpc.opts(P.rpc.buf_opts(),
  P.Tr.emit(P.CALL_SETSOCKOPT(), P.IPPROTO_TCP(), "TCP_NODELAY", t))

# ===========================================================================
# :454 -- `if DEV.interface.startswith("MOCK"): from test.mockgpu.mockgpu import
# MockFileIOInterface as FileIOInterface`. A MODULE REBIND keyed on the interface name,
# and the only reader of `DEV.interface` in this file. It replaces the WHOLE class, so
# every `FileIOInterface(...)` above it becomes a mock and every path in this file stops
# being read. The port keeps the PREDICATE and names the rebind as a wall, because a
# gate cannot check "which class object is bound to a name".
# TODO(p3) runtime/support/system.py:17  symbol=FileIOInterface -- the MockFileIOInterface rebind -- upstream's LAST line rebinds this name to the mock.
# ===========================================================================

# the REFUSAL TRUNCATES BEFORE the mmap, so the trace shows no MAP at all.
def t_11_sock_arg() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, rpc.options(Tr.of()))
    urow("sy_sock_nodelay_arg", first_arg(P.CALL_SETSOCKOPT(), Tr.calls(a)))

def RESP_OFF_STATUS() -> U32: 0
def pci.probe(+pcibus: String, +bound: Bool, use_vfio: Bool, t: P.Tr) -> P.Tr:
  P.pci.probe.unbound(pcibus, use_vfio, bound,
    P.pci.probe.sibs(pcibus, P.pci.probe.drv2(pcibus, bound,
      P.pci.probe.drv1(pcibus, P.pci.probe.enable(pcibus, t)))))

# :75 `os.system("sudo modprobe vfio-pci disable_idle_d3=1")` -- WALL 2's plain string,
# and it is CONDITIONAL on `/sys/module/vfio` being absent.
def Tr.strs(k: U32, +cs: List<&2, P.Call>) -> List<&2, String>:
  P.Tr.strs.go(List.length(&2, P.Call, cs), k, cs, Nil{})

def BUS() -> String: "0000:03:00.0"
# --- :98-102 `alloc_sysmem` ---------------------------------------------------
def t_09_probe() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, pci.probe(BUS(), False{}, False{}, Tr.of()))
    srow("sy_pci_opens", sxs(Tr.strs(P.CALL_OPEN(), Tr.calls(a))))
    urow("sy_pci_nopen", Tr.count(P.CALL_OPEN(), Tr.calls(a)))
    urow("sy_pci_nwrite", Tr.count(P.CALL_WRITE(), Tr.calls(a)))
    urow("sy_pci_nexists", Tr.count(P.CALL_EXISTS(), Tr.calls(a)))
    row("sy_pci_order_ok", Tr.has(Tr.calls(a), [P.Call{P.CALL_EXISTS, 0, P.pci.path(BUS(), P.pci.tail(1))},
      P.Call{P.CALL_WRITE, 1, P.pci.path(BUS(), P.pci.tail(2))},
      P.Call{P.CALL_WRITE, 1, P.pci.sib_path(BUS(), 1)}]))
    srow("sy_pci_sibs", sxs(P.sib.paths(BUS())))

def t_11_libs_trace() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, cap.load_sys(cap.load(Tr.of())))
    srow("sy_lib_trace", sxs(Tr.strs(P.CALL_CDLL(), Tr.calls(a))))
    urow("sy_lib_ncdll", Tr.count(P.CALL_CDLL(), Tr.calls(a)))

# --- :50-51 the two PLATFORM flag tables side by side ------------------------
def cap.atomic_on(osx: U32) -> Bool: U32.is_eq(osx, P.CAP_NO())

def cap.barrier_lib(osx: U32, have_atomic: Bool, have_sys: Bool) -> U32:
  P.cap.barrier_lib.p2(osx, have_atomic, have_sys)

# the SECOND question: does a fence get emitted at all? A None library is a SILENT
# no-op, not an error.
# THE 32-BIT SIZE, which is exact in U32: `0 - (lo & 0xfffffff0)`.
def cap.fences(lib: U32) -> Bool: U32.is_ne(lib, P.LIB_NONE())

# :62 and :65 as a trace: the LINUX platform loads 'atomic' and BOTH platforms load
# "System", and the two are separate `CDLL` calls. The order is fixed by the
# fixture, not claimed from Python -- the two are independent cached properties.
def t_03_libs() -> IO(Unit):
  do IO<Unit>:
    urow("sy_lib_linux_atomic", cap.barrier_lib(P.CAP_NO(), True{}, False{}))
    urow("sy_lib_linux_noatomic", cap.barrier_lib(P.CAP_NO(), False{}, False{}))
    urow("sy_lib_osx_sys", cap.barrier_lib(P.CAP_YES(), False{}, True{}))
    urow("sy_lib_osx_nosys", cap.barrier_lib(P.CAP_YES(), False{}, False{}))
    # THE NEGATIVE CASE: OSX with an atomic library present must NOT consult it.
    urow("sy_lib_osx_atomic_ignored", cap.barrier_lib(P.CAP_YES(), True{}, False{}))
    row("sy_fence_linux", cap.fences(cap.barrier_lib(P.CAP_NO(), True{}, False{})))
    row("sy_fence_osx", cap.fences(cap.barrier_lib(P.CAP_YES(), False{}, True{})))
    row("sy_nofence_linux", cap.fences(cap.barrier_lib(P.CAP_NO(), False{}, False{})))
    row("sy_nofence_osx", cap.fences(cap.barrier_lib(P.CAP_YES(), False{}, False{})))
    row("sy_atomic_on_linux", cap.atomic_on(P.CAP_NO()))
    row("sy_atomic_on_osx", cap.atomic_on(P.CAP_YES()))
    t_11_libs_trace()

# `mem_space_addr[bar_mem] += round_up(bar_size, 2 << 20)` -- :181, and the alignment
# is 2 MiB REGARDLESS of the BAR's real size, so two adjacent BARs cannot overlap.
# MEASURED: round_up(0x10000000, 2<<20) == 0x10000000 and round_up(0xf0000000, 2<<20)
# == 0xf0000000 -- both already aligned, which is the NEGATIVE case: a fixture that
# only used aligned sizes could not see a wrong alignment. 0x1000 rounds to 0x200000.
def bars.next_addr(+base: U32, size: U32) -> U32: U32.add(base, H.round_up_u32(size, P.TWO_MB()))

# the USBPCIDevice constants, :277-282, and they are a fixed table rather than
# arguments because :277 SPELLS them at the call site.
def post.n2(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(2, a0, a1, a2)
def post.n4(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(4, a0, a1, a2)
def pci.class_prefix(device: String) -> String: String.take(device, 2n)

# :240 the non-VFIO arm, `FileIOInterface(..."/enable", O_RDWR).write("1")`, and it is
# the ELSE of :222 so it happens exactly when VFIO is not used.
def scan.is_rebar(hdr: U32) -> Bool: U32.is_eq(P.scan.cap_id(hdr), P.PCI_EXT_CAP_ID_REBAR())

# :117 the 8-byte little-endian property read, `int.from_bytes(bytes(buf), "little")`.
# Only the LOW FOUR bytes are used, because the property read writes into a
# `(c_uint8*8)()` and every property in :116-117 is a 16-bit id.
def t_04_write_fail() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.sysfs.apply("/x", "1", "", False{}, False{}, Tr.of()))
    row("sy_write_fail_refused", Tr.refused(t))
    urow("sy_write_fail_nsys", Tr.count(P.CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_fail_nread", Tr.count(P.CALL_READ(), Tr.calls(t)))

def t_04_write_retry() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.sysfs.apply("/x", "1", "", False{}, True{}, Tr.of()))
    urow("sy_write_retry_nsys", Tr.count(P.CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_retry_nread", Tr.count(P.CALL_READ(), Tr.calls(t)))
    urow("sy_write_retry_nopen", Tr.count(P.CALL_OPEN(), Tr.calls(t)))
    row("sy_write_retry_cmd", Tr.has(Tr.calls(t), [P.Call{P.CALL_SYSTEM, 0, "sudo sh -c 'echo 1 > /x'"}]))
    row("sy_write_retry_refused", Bool.not(Tr.refused(t)))

def t_04_sysfs() -> IO(Unit):
  do IO<Unit>:
    # --- WALL 2: THE STRING, diffed BESIDE CPython's and never as a boolean
    srow("sy_echo_pagemap", P.sysfs.echo(P.PAGEMAP_VALUE(), P.PAGEMAP_SYSFS()))
    srow("sy_echo_enable", P.sysfs.echo("1", P.pci.path(BUS(), P.pci.tail(0))))
    srow("sy_echo_reset", P.sysfs.echo("1", P.pci.path(BUS(), P.pci.tail(9))))
    urow("sy_echo_len_pagemap", U32.from_nat(List.length(&2, Char, String.to_list(P.sysfs.echo(P.PAGEMAP_VALUE(), P.PAGEMAP_SYSFS())))))
    urow("sy_echo_len_enable", U32.from_nat(List.length(&2, Char, String.to_list(P.sysfs.echo("1", P.pci.path(BUS(), P.pci.tail(0)))))))
    srow("sy_modprobe", VFIO_MODPROBE())
    # --- :57 `(expected or value)`, a TRUTHINESS rule
    srow("sy_want_none", P.sysfs.want("", "0"))
    srow("sy_want_empty_is_falsy", P.sysfs.want("", "1"))
    srow("sy_want_set", P.sysfs.want("y", "0"))
    row("sy_match_same", sysfs.matches("0", "", "0"))
    row("sy_match_diff", sysfs.matches("1", "", "0"))
    t_04_write_ok()
    t_04_write_retry()
    t_04_write_fail()

# --- :84-87 `reserve_va`: the NEGATIVE CASE IS IN THE PYTHON SOURCE -----------
def AMD_VA_BITS() -> U32: 48
# TWO PREFIXES FOR TWO SITES. `pci.lock_name` (:208) gets the devpref already
# lowercased, because the two `lower()` calls are the seam's; `pci.class_prefix`
# (:136) gets the DEVICE HEAD, which is uppercase, and takes its first two
# characters. MEASURED: 'am' and 'AMD' both lock to 'am_0000:03:00.0.lock' but only
# 'AMD' has the class prefix 'AM'.
def face.has_explicit(kind: U32) -> Bool: U32.is_ne(kind, P.KIND_PCI())

# the fallback, and it is the CLASS NAME.
# --- :36/:42 the mmap / munmap seam -------------------------------------------
def face.aligned(addr: U32) -> Bool: U32.is_zero(U32.and(addr, 4095))

# :341 `if not self.dev_impl.mm.va_base <= lo < lo + size <= self.dev_impl.mm.va_base
# + (1 << self.dev_impl.mm.va_bits)`. THREE comparisons in a chain and the middle one
# is STRICT, so `lo == va_base` passes and `lo + size == span` passes. The span is
# `(1 << 48)` for AMD, which is 281474976710656 and does not fit a U32 -- so the port
# takes both words and checks the chain in two halves, with the CARRY out of
# `lo + size` making the middle comparison correct across the word boundary.
#
# 0x10000000000 is 2**40, so `>> 32` is 2**8 == 256 and NOT 0x1000 == 4096. I wrote
# 4096 and the CPython differ caught it -- the port's own `sy_va_base_hi` said 4096
# next to an oracle that said 256. (1 << 48) >> 32 == 65536. Both LOW words are ZERO,
# which is the whole difficulty: a 32-bit port that compared only the low words would
# find `0 <= lo` and `lo + size <= 0` and so would refuse EVERY address, or with the
# bounds dropped would accept every one.
def face.align_size(+size: U32, sysmem: Bool, pagesize: U32) -> U32:
  H.round_up_u32(size, P.face.align(size, sysmem, pagesize))

# :337 `if b.device.split(":")[0] in {"CPU", "PYTHON", "NPY"}` -- a SET of three HEADS,
# and it is the HEAD and not the whole device string. MEASURED: 'CPU:0' and
# 'PYTHON:1' and 'NPY:2' are host buffers and 'NPU:0' and 'AMD:1' are not. A port that
# compared the whole string would refuse every host buffer, because a Buffer always
# carries its index.
def HOST() -> String: "10.0.0.1"
def face.in_va(+lo_hi: U32, +lo: U32, +size: U32) -> Bool:
  P.face.in_va.p2(lo_hi, lo, P.u64.end_hi(lo_hi, lo, size), U32.add(lo, size))

# ===========================================================================
# :359-363 -- `RemoteCmd`, `REMOTE_REQ`, `REMOTE_RESP`. THE TABLE, BOTH
# DIRECTIONS, AND THE SPLIT.
#
#   class RemoteCmd(enum.IntEnum):
#     PROBE,MAP_BAR,MAP_SYSMEM_FD,CFG_READ,CFG_WRITE,RESET,MMIO_READ,MMIO_WRITE,
#     MAP_SYSMEM,SYSMEM_READ,SYSMEM_WRITE,RESIZE_BAR,PING = range(13)
#     LOAD_PROG,EXEC_PROG,UNMAP_SYSMEM = range(13, 16)
#
# SIXTEEN members in TWO `range()` calls, and the second STARTS WHERE THE first stops.
# A port that read one `range(16)` would get the same sixteen values and the same
# order, and would be right -- so the split is a TABLE CLAIM, not a value claim, and
# `Rcmd.base` / `Rcmd.lo2` / `Rcmd.hi2` are the numbers `range()` was handed. The
# oracle confirmed both halves against the LIVE enum:
#   [m.value for m in RemoteCmd][:13] == list(range(13))      -> True
#   [m.value for m in RemoteCmd][13:]  == list(range(13, 16)) -> True
#
# `RemoteCmd.name` is READ at :425 -- `f"remote {cmd.name} failed: ..."` -- so the
# reverse direction (value -> name) has a real reader and not just a reader in the
# gate. `RemoteCmd(0).name` is 'PROBE' and `RemoteCmd(15).name` is 'UNMAP_SYSMEM'.
# ===========================================================================

def face.peer_group(kind: U32, pcibus: String, host: String, port: U32) -> String:
  P.face.peer_group.p2(kind, pcibus, host, port)

# :312 `should_use_sysmem = host or (cpu_access and self.is_bar_small() and not
# force_devmem)` -- THREE conjuncts and an `or`, and `Bool.pick` is the `or` (a
# `Bool.or` would evaluate both arms, which is harmless here but is the wrong
# spelling for `x or y`). MEASURED over the six interesting fixtures:
#   host=1 -> True whatever else says
#   cpu_access=1, small, !force_devmem -> True
#   cpu_access=1, NOT small -> False   <- the conjunct that decides small-bar
#   cpu_access=1, small, force_devmem -> False
#   cpu_access=0 -> False
def face.is_bar_small(bar_size: U32) -> Bool: U32.is_eq(bar_size, P.SMALL_BAR_SIZE())

# :267 `int(x, 16).bit_length() - 1`, the log2 of the resizable-BAR size. The `- 1` is
# a subtraction that goes NEGATIVE for x < 2, and `resize_bar` writes that straight
# into sysfs -- MEASURED, x=0x1 -> "0" and x=0x0 -> "-1". A U32 port wraps it, and the
# row for the boundary says so rather than pretending.
def face.use_sysmem(host: Bool, cpu_access: Bool, force_devmem: Bool, small: Bool) -> Bool:
  P.face.use_sysmem.pick(host, P.face.use_sysmem.p2(cpu_access, small, force_devmem))

# :315 `size = round_up(size, mmap.PAGESIZE if should_use_sysmem else ((2 << 20) if
# size >= (8 << 20) else (4 << 10)))` -- A THREE-BRANCH LADDER and the comment above it
# says why: "Align size to huge pages for large allocations, otherwise the unaligned
# tail falls back to 4KB pages, increasing TLB pressure."
#
# THE LADDER IS NOT MONOTONE IN SIZE, and that is the trap. MEASURED:
#   size=0x800000 (8 MiB exactly) -> align 2 MiB, and round_up is 0x800000
#   size=0x800001 (8 MiB + 1)    -> align 2 MiB, and round_up is 0xA00000
#   size=0x7fffff (8 MiB - 1)    -> align 4 KiB, and round_up is 0x800000
#   size=0x1001                 -> align 4 KiB, and round_up is 0x2000
# So ONE BYTE below the threshold is aligned to 8 MiB and one byte above it costs 2 MiB
# of slack. The `>=` is load-bearing and `>` would move the 8 MiB fixture.
def t_10_face() -> IO(Unit):
  do IO<Unit>:
    # --- :297 the `getattr` fallback, BOTH directions
    row("sy_pg_explicit_pci", Bool.not(face.has_explicit(P.KIND_PCI())))
    row("sy_pg_explicit_usb", face.has_explicit(P.KIND_USB()))
    row("sy_pg_explicit_remote", face.has_explicit(P.KIND_REMOTE()))
    srow("sy_pg_pci", face.peer_group(P.KIND_PCI(), BUS(), HOST(), 6667))
    srow("sy_pg_usb", face.peer_group(P.KIND_USB(), BUS(), HOST(), 6667))
    srow("sy_pg_remote", face.peer_group(P.KIND_REMOTE(), BUS(), HOST(), 6667))
    srow("sy_pg_fallback_pci", P.face.peer_group_fallback(P.KIND_PCI()))
    srow("sy_pg_fallback_usb", P.face.peer_group_fallback(P.KIND_USB()))
    srow("sy_pg_usb_direct", P.face.peer_group_usb(BUS()))
    srow("sy_pg_remote_direct", P.face.peer_group_remote(HOST(), 1))
    # --- :300 the EQUALITY
    row("sy_issmall_yes", face.is_bar_small(268435456))
    row("sy_issmall_no", face.is_bar_small(268435457))
    # --- :312 the three-conjunct `or`
    row("sy_sysmem_host", face.use_sysmem(True{}, False{}, False{}, False{}))
    row("sy_sysmem_cpu_small", face.use_sysmem(False{}, True{}, False{}, True{}))
    row("sy_sysmem_cpu_big", face.use_sysmem(False{}, True{}, False{}, False{}))
    row("sy_sysmem_forced", face.use_sysmem(False{}, True{}, True{}, True{}))
    row("sy_sysmem_nocpu", face.use_sysmem(False{}, False{}, False{}, True{}))
    row("sy_sysmem_host_forced", face.use_sysmem(True{}, True{}, True{}, False{}))
    # --- :315 the ladder, and the `>=` at the threshold
    urow("sy_align_big", P.face.devmem_align(8388608))
    urow("sy_align_big1", P.face.devmem_align(8388609))
    urow("sy_align_just_under", P.face.devmem_align(8388607))
    urow("sy_align_small", P.face.devmem_align(4097))
    urow("sy_align_tiny", P.face.devmem_align(1))
    urow("sy_ladder_800000", face.align_size(8388608, False{}, 4096))
    urow("sy_ladder_800001", face.align_size(8388609, False{}, 4096))
    urow("sy_ladder_7fffff", face.align_size(8388607, False{}, 4096))
    urow("sy_ladder_1001", face.align_size(4097, False{}, 4096))
    urow("sy_ladder_1001_sys", face.align_size(4097, True{}, 4096))
    urow("sy_ladder_1234567", face.align_size(19088743, False{}, 4096))
    # --- :337 the HOST set, and :339 the alignment
    row("sy_host_CPU", face.is_host_device("CPU"))
    row("sy_host_PYTHON", face.is_host_device("PYTHON"))
    row("sy_host_NPY", face.is_host_device("NPY"))
    row("sy_host_NPU", face.is_host_device("NPU"))
    row("sy_host_AMD", face.is_host_device("AMD"))
    row("sy_align_ok_0", face.aligned(0))
    row("sy_align_bad_800", face.aligned(2048))
    row("sy_align_ok_1000", face.aligned(4096))
    # --- :341 the three-comparison chain, IN TWO WORDS
    row("sy_inva_lo", face.in_va(P.AMD_VA_BASE_HI(), 4096, 8192))
    row("sy_inva_base", face.in_va(P.AMD_VA_BASE_HI(), 0, 8192))
    row("sy_inva_below", face.in_va(U32.sub(P.AMD_VA_BASE_HI(), 1), 4294967295, 8192))
    row("sy_inva_tiny", face.in_va(0, 80, 8192))
    row("sy_inva_carry", face.in_va(P.AMD_VA_BASE_HI(), 4294967292, 8192))
    row("sy_carry_detect", P.u64.carried(4294967292, 8192))
    urow("sy_va_bits", AMD_VA_BITS())
    urow("sy_va_base_hi", P.AMD_VA_BASE_HI())
    urow("sy_va_span_hi", P.AMD_VA_SPAN_HI())
    t_10_meta()

def PAGEFRAME_MASK_LO() -> U32: 4294967295         # 0xffffffff -- (1<<55)-1, low word
def PAGEFRAME_MASK_HI() -> U32: 8388607            # 0x7fffff  -- (1<<55)-1, high word
# :117's `f"{v:x}:{d:x}"`, the OSX id, beside :124's Linux `pcibus` string. Two
# different strings for the same device, and which one you get is the platform.
def t_11_pagemask() -> IO(Unit):
  do IO<Unit>:
    # WALL 1's two words, read so the constants are not dead (rule 8: an unread
    # constant is not a port). M4 perturbed the HIGH word and moved NOTHING until
    # these two rows existed.
    urow("sy_pageframe_hi", PAGEFRAME_MASK_HI())
    urow("sy_pageframe_lo", PAGEFRAME_MASK_LO())
    row("sy_pageframe_differs", Bool.not(U32.is_eq(PAGEFRAME_MASK_HI(), PAGEFRAME_MASK_LO())))

# `(en - st) // el` -- the ITEM COUNT, and it is only total for `st <= en`. A reversed
# slice gives a negative count in Python and `struct.unpack` then raises; in U32 the
# subtraction WRAPS to a huge positive and the port would ask for a four-gigabyte
# unpack. `rmm.count` is gated on the ordered fixtures and the reversal is named as a
# WALL rather than approximated.
def rmm.count(st: U32, +en: U32, +el: U32) -> U32: U32.div(U32.sub(en, st), el)

# :369-370 the INT arm: `sl = slice(k, k + 1)`, so `st = k * el` and `en = (k + 1) * el`.
# MEASURED: k=3 with el=1 gives st=3 en=4.
def bars.more(bar_off: U32) -> Bool: U32.is_lt(bar_off, P.BAR_LOOP_BOUND())

# `mem_space_addr[bar_mem] += round_up(bar_size, 2 << 20)` -- :181, and the alignment
# is 2 MiB REGARDLESS of the BAR's real size, so two adjacent BARs cannot overlap.
# MEASURED: round_up(0x10000000, 2<<20) == 0x10000000 and round_up(0xf0000000, 2<<20)
# == 0xf0000000 -- both already aligned, which is the NEGATIVE case: a fixture that
# only used aligned sizes could not see a wrong alignment. 0x1000 rounds to 0x200000.
def REQ_OFF_ARG2() -> U32: 25
# the SIX arities and their padded triples, as rows. The last two are the negative
# cases and they are the reason this rule is gated at all.
def post.n0(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(0, a0, a1, a2)
# :341 `if not self.dev_impl.mm.va_base <= lo < lo + size <= self.dev_impl.mm.va_base
# + (1 << self.dev_impl.mm.va_bits)`. THREE comparisons in a chain and the middle one
# is STRICT, so `lo == va_base` passes and `lo + size == span` passes. The span is
# `(1 << 48)` for AMD, which is 281474976710656 and does not fit a U32 -- so the port
# takes both words and checks the chain in two halves, with the CARRY out of
# `lo + size` making the middle comparison correct across the word boundary.
#
# 0x10000000000 is 2**40, so `>> 32` is 2**8 == 256 and NOT 0x1000 == 4096. I wrote
# 4096 and the CPython differ caught it -- the port's own `sy_va_base_hi` said 4096
# next to an oracle that said 256. (1 << 48) >> 32 == 65536. Both LOW words are ZERO,
# which is the whole difficulty: a 32-bit port that compared only the low words would
# find `0 <= lo` and `lo + size <= 0` and so would refuse EVERY address, or with the
# bounds dropped would accept every one.
def HEAD_AMD() -> String: "AMD"
# :208 the lock name, `f"{devpref.lower()}_{pcibus.lower()}.lock"`. MEASURED:
# 'am_0000:03:00.0.lock'. BOTH halves are lowercased, and a device prefix that is
# already lower does not change -- so the row pair is the same file for 'AMD' and
# 'am', which is the point of the lower(). The lower() itself is a WALL (no
# per-character fold) and the seam hands the lowercased halves over.
# THE `lower()` IS THE SEAM'S. A per-character fold has no base case a `match` can
# name (bend2-constraints.md, position 6880), so `pci.lock_name` takes the two halves
# ALREADY lowercased -- which is why `sy_lock_AMD` and `sy_lock_AM` both pass a
# lowercased prefix and both answer the SAME file. MEASURED against CPython:
# 'AMD' and 'am' both give 'am_0000:03:00.0.lock', and that is the point of the
# `lower()`. TODO(p3) runtime/support/system.py:205  symbol=__init__ -- the two `lower()` calls.
def pci.lock_name(devpref: String, +pcibus: String) -> String:
  String.concat([devpref, "_", pcibus, ".lock"])

# :136 `cl(device[:2], pcibus)` -- the device CLASS is the first TWO characters of the
# device head, and it is two and not one and not three. `AM` for AMD, `CU` for CUDA,
# `NPU` would be three. So this is a genuine `take(2)` and a row.
def O_RDWR_CREAT_CLOEXEC() -> U32: 16777730        # 0x40006  -- os.O_RDWR|O_CREAT|O_CLOEXEC

# --- the fcntl lock flags, :197 ---------------------------------------------
# 0x7f0000100000 is the alloc_sysmem `vaddr` fixture, and its LOW word is 1048576 --
# nonzero, which is the point. Using VA_LO() (whose low word is 0) for a `vaddr`
# argument made `alloc.fixed` answer 0 and every MAP_FIXED row read as "unset".
def REQ_SIZE() -> U32: 33
def bars.step(+bar_off: U32, +bar_64: U32) -> U32:
  P.bars.step.pick(bar_off, Bool.pick(U32, U32.is_zero(bar_64), P.BAR_OFF_STEP32(), P.BAR_OFF_STEP64()))

def rmm.en(stop: U32, nbytes: U32, el: U32) -> U32: P.rmm.en.pick(stop, nbytes, el)

# `(en - st) // el` -- the ITEM COUNT, and it is only total for `st <= en`. A reversed
# slice gives a negative count in Python and `struct.unpack` then raises; in U32 the
# subtraction WRAPS to a huge positive and the port would ask for a four-gigabyte
# unpack. `rmm.count` is gated on the ordered fixtures and the reversal is named as a
# WALL rather than approximated.
def rmm.read_addr(sysmem: Bool, +addr: U32, +off: U32) -> U32: Bool.pick(U32, sysmem, addr, off)

# ===========================================================================
# :386-406 -- `RemotePCIDevice.connect` / `scan`, and the REMOTE parser.
#
#   :391 `sock = socket.create_connection((host, port), timeout=getenv("REMOTE_TIMEOUT", 60))`
#   :392 `sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)`
#   :393 `for opt in (socket.SO_SNDBUF, socket.SO_RCVBUF): sock.setsockopt(socket.SOL_SOCKET, opt, 64 << 20)`
#   :399 `for r in [r.strip() for r in getenv("REMOTE", "").split(",") if r.strip()]:`
#   :400 `if r == "local": ret += [(PCIDevice, d) for d in System.pci_scan_bus(...)]`
#   :402 `host, port = r.split(":")[0], int(r.split(":")[1]) if ":" in r else 6667`
#   :406 `ret += [(..., f"remote:{host}:{port}:{d}") for d in data.decode().split()]`
#
# THE socket options are a three-CALL sequence with a LOOP over two options that share
# ONE value, and the order is the claim: TCP_NODELAY first, then SNDBUF, then RCVBUF.
# MEASURED: IPPROTO_TCP=6 TCP_NODELAY=1 SOL_SOCKET=65535 SO_SNDBUF=4097
# SO_RCVBUF=4098, and 64<<20 = 67108864 for both buffers. The two buffer options DIFFER
# BY ONE and a transposed pair is invisible to any check that only counts the calls.
#
# THE DEFAULT PORT IS 6667 and it applies when there is no `:` at all -- not when the
# port is empty. MEASURED over the parser:
#   ''                     -> no parts
#   ' '                    -> no parts          (strip drops it, then `if r.strip()`)
#   'local'                -> LOCAL
#   '10.0.0.1'             -> remote:10.0.0.1:6667
#   '10.0.0.1:6666'        -> remote:10.0.0.1:6666
#   ' local , 10.0.0.2:1 ' -> [LOCAL, remote:10.0.0.2:1]
# So the SPLIT and the STRIP are a WALL (no `String.split`, no `String.strip`) and the
# two RULES that drive them are not: the `local` test, the `:` test, the default port,
# and the result string.
# ===========================================================================

def rmm.st(start: U32, el: U32) -> U32: P.rmm.st.pick(start, el)

def t_11_sock_n() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, rpc.options(Tr.of()))
    urow("sy_sock_nopts", Tr.count(P.CALL_SETSOCKOPT(), Tr.calls(a)))

def sys.is_mock(head: String) -> Bool: List.contains(String, String.eq, P.MOCK_HEADS(), head)


# ===========================================================================
# THE FIXTURES. Real bus ids and real sizes, so a row is a real answer and not a
# shape check. Every one of these strings and numbers is MEASURED; the oracle is
# `.agents/slop/oracle-system.py` and its captured output is
# `.agents/slop/oracle-system.txt`.
# ===========================================================================

# 0x7f0000000000 is 139637976727552 and does not fit a U32, so `reserve_va`'s
# `va_start` is a 64-bit ADDRESS. Its LOW word is 0, which is the whole of what the
# cache key needs -- and it is exactly why a `U32` port of the cache would answer
# "already reserved" for EVERY 4 GiB-aligned address, since they all have low word
# 0. The row `sy_va_cached_nmmap` is the one that would catch it.
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(P.ush(xs), ",")]))

# the two `range()` calls, as the two halves of the table, TAKEN FROM THE SAME LIST
# rather than written out again -- a second literal of sixteen names would be a second
# table and the two could disagree.
def Rcmd.first() -> List<&2, String>: P.list.take(P.Rcmd.base(), P.Rcmd.names())

# `LOAD_PROG, EXEC_PROG, UNMAP_SYSMEM` are the last three and `range(13, 16)` produced
# them, so their INDICES are 13, 14, 15 and the lower bound is 13 again.
def pci.resize_log2(size: U32) -> U32: U32.sub(P.hx.bitlen(size), P.BAR_INFO_DELTA())

# :263 `map_bar`: `fd.mmap(addr, sz, PROT_READ|PROT_WRITE, MAP_SHARED | (MAP_FIXED if
# addr else 0), off)` and `sz = size or (self.bar_info(bar)[1] - off)`. MEASURED:
# addr=0 -> 0x1, addr!=0 -> 0x11. And the `or` means size=0 is FALSY and falls back
# to the BAR size, which is a Python truthiness rule and not a `None` check.
def pci.bar_path(+pcibus: String, bar_idx: U32) -> String:
  String.concat([P.PCI_ROOT(), pcibus, "/resource", U32.show(bar_idx)])

def LOCK_EX_NB() -> U32: 6                         # LOCK_EX | LOCK_NB
def DEV_AM() -> String: "am"
def DEV_AMD() -> String: "amd"
def t_09_probe_vfio() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, pci.probe(BUS(), False{}, True{}, Tr.of()))
    row("sy_pci_vfio", Tr.has(Tr.calls(a), [P.Call{P.CALL_WRITE, 1, P.pci.path(BUS(), P.pci.tail(3))}]))

def BUS2() -> String: "c1:00.0"
def bar.size(lo: U32, +hi: U32) -> U32: U32.add(U32.sub(hi, lo), P.BAR_INFO_DELTA())

# MEASURED pairs (start, end, size):
#   0x7c000000 0x7fffffff -> 0x4000000
#   0x10000000 0x1fffffff -> 0x10000000   (the 256 MiB "small bar" AMD reports)
#   0x7d000000 0x7d1fffff -> 0x200000
#   0x7d000000 0x7d3fffff -> 0x400000
#   0x0        0xfff      -> 0x1000
# `cfg & PCI_BASE_ADDRESS_SPACE == PCI_BASE_ADDRESS_SPACE` -- bit 0 set means a
# memory BAR and clear means an I/O BAR, and an I/O BAR is SKIPPED entirely.
def pci.flags_resource() -> U32: P.O_RDONLY()
def pci.flags_resize() -> U32: P.O_RDWR()

# :219-220 `for fn in range(1, 8)`, and each `remove` is O_WRONLY. SEVEN writes.
#
# A `U32` self-call is refused without a `Nat` fuel and a `Nat` self-call cannot read
# the counter it just spent, so the loop is THREE folds: one that builds the seven
# function numbers, one that builds the seven paths, one that emits. Each is a
# single self-call and none of them is mutually recursive.
def face.bar_small(size: U32) -> Bool: U32.is_eq(size, P.SMALL_BAR_SIZE())

def t_09_probe_bound() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, pci.probe(BUS(), True{}, False{}, Tr.of()))
    row("sy_pci_bound_refused", Tr.refused(a))
    urow("sy_pci_bound_nopen", Tr.count(P.CALL_OPEN(), Tr.calls(a)))

def DEV_CPU() -> String: "cpu"
# TWO PREFIXES FOR TWO SITES. `pci.lock_name` (:208) gets the devpref already
# lowercased, because the two `lower()` calls are the seam's; `pci.class_prefix`
# (:136) gets the DEVICE HEAD, which is uppercase, and takes its first two
# characters. MEASURED: 'am' and 'AMD' both lock to 'am_0000:03:00.0.lock' but only
# 'AMD' has the class prefix 'AM'.
def pci.resize_path(+pcibus: String, bar_idx: U32) -> String:
  String.concat([P.PCI_ROOT(), pcibus, "/resource", U32.show(bar_idx), "_resize"])

# :220 `f"/sys/bus/pci/devices/{self.pcibus[:-1]}{fn}/remove"` for fn in range(1,8).
# `pcibus[:-1]` drops the LAST character -- the function number -- and `fn` replaces
# it. `String.take` keeps the FIRST n and `String.drop` removes the FIRST n, so the
# tail is `String.take(pcibus, len - 1)`. MEASURED: '0000:03:00.0'[:-1] ==
# '0000:03:00.' and fn=1 gives '/sys/bus/pci/devices/0000:03:00.1/remove'.
def t_09_pci() -> IO(Unit):
  do IO<Unit>:
    # --- the sysfs PATH TABLE, and every tail diffed as a string
    srow("sy_path_enable", P.pci.path(BUS(), P.pci.tail(0)))
    srow("sy_path_driver", P.pci.path(BUS(), P.pci.tail(1)))
    srow("sy_path_unbind", P.pci.path(BUS(), P.pci.tail(2)))
    srow("sy_path_override", P.pci.path(BUS(), P.pci.tail(3)))
    srow("sy_path_config", P.pci.path(BUS(), P.pci.tail(4)))
    srow("sy_path_iommu", P.pci.path(BUS(), P.pci.tail(5)))
    srow("sy_path_reset", P.pci.path(BUS(), P.pci.tail(9)))
    srow("sy_path_bus2", P.pci.path(BUS2(), P.pci.tail(0)))
    srow("sy_bar0", pci.bar_path(BUS(), 0))
    srow("sy_bar2", pci.bar_path(BUS(), 2))
    srow("sy_bar2_resize", pci.resize_path(BUS(), 2))
    srow("sy_bus_trim", P.pci.bus_trim(BUS()))
    urow("sy_bus_len", P.pci.bus_len(BUS()))
    srow("sy_sib1", P.pci.sib_path(BUS(), 1))
    srow("sy_sib7", P.pci.sib_path(BUS(), 7))
    urow("sy_sib_n", P.sib.n())
    srow("sy_iommu_path", pci.iommu_path(18))
    # --- the OPEN FLAGS, and a wrong flag is a silently wrong open
    urow("sy_flag_enable", P.pci.flags_enable())
    urow("sy_flag_unbind", P.pci.flags_unbind())
    urow("sy_flag_config", P.pci.flags_config())
    urow("sy_flag_bar", pci.flags_bar())
    urow("sy_flag_resource", pci.flags_resource())
    urow("sy_flag_resize", pci.flags_resize())
    urow("sy_o_rdwr_sync_cloexec", P.O_RDWR_SYNC_CLOEXEC())
    urow("sy_o_rdwr_creat_cloexec", O_RDWR_CREAT_CLOEXEC())
    urow("sy_lock_ex_nb", LOCK_EX_NB())
    urow("sy_lock_mode", LOCK_MODE())
    # --- the lock name and the class prefix
    # both rows take a LOWERCASED prefix, and they differ in length only
    srow("sy_lock_AMD", pci.lock_name(DEV_AMD(), BUS()))
    srow("sy_lock_AM", pci.lock_name(DEV_AM(), BUS()))
    srow("sy_lock_cpu", pci.lock_name(DEV_CPU(), BUS()))
    srow("sy_class_AMD", pci.class_prefix(HEAD_AMD()))
    srow("sy_class_NPU", pci.class_prefix(HEAD_NPU()))
    # --- :259/:260 the `+ 1`, and :263 the falsy `or`, and :267 the log2
    urow("sy_barinfo_7c", bar.size(2080374784, 2147483647))
    urow("sy_barinfo_1000", bar.size(268435456, 536870911))
    urow("sy_barinfo_7d0", bar.size(2097152000, 2099249151))
    urow("sy_barinfo_0", bar.size(0, 4095))
    row("sy_smallbar_exact", face.bar_small(268435456))
    row("sy_smallbar_minus1", face.bar_small(268435455))
    row("sy_smallbar_plus1", face.bar_small(268435457))
    urow("sy_mapflags_0", pci.map_flags(0))
    urow("sy_mapflags_nz", pci.map_flags(1048576))
    urow("sy_mapsize_or", pci.map_size(268435456, 0, 0))
    urow("sy_mapsize_off", pci.map_size(268435456, 4096, 0))
    urow("sy_mapsize_given", pci.map_size(268435456, 4096, 8192))
    urow("sy_resize_100000", pci.resize_log2(1048576))
    urow("sy_resize_40000000", pci.resize_log2(1073741824))
    urow("sy_resize_1", pci.resize_log2(1))
    urow("sy_resize_0", pci.resize_log2(0))
    t_09_probe()
    t_09_probe_bound()
    t_09_probe_vfio()

# --- :292-293 the Meta field order and the LITERAL True at :321 ---------------
def bars.bar_mem(cfg: U32) -> U32:
  P.bars.bar_mem.pick(U32.is_ne(U32.and(cfg, P.PCI_BASE_ADDRESS_MEM_PREFETCH()), 0))

# :406 `f"remote:{host}:{port}:{d}"` -- FOUR colon-separated fields, and `d` is the
# device the node reported, not the one that was asked for.
def rpc.device_name(+host: String, port: U32, +d: String) -> String:
  String.concat(["remote:", host, ":", U32.show(port), ":", d])

# :393 the two buffer options, in order, with their ONE shared value.
# `LOAD_PROG, EXEC_PROG, UNMAP_SYSMEM` are the last three and `range(13, 16)` produced
# them, so their INDICES are 13, 14, 15 and the lower bound is 13 again.
def post.n5(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(5, a0, a1, a2)

# ===========================================================================
# :369-378 -- `RemoteMMIOInterface.__getitem__` / `__setitem__`, and the two rules of
# theirs that are this file's arithmetic rather than `struct`'s.
#
#   :370 `el = struct.calcsize(self.fmt)`
#   :371 `st, en = (sl.start or 0) * el, (len(self) if sl.stop is None else sl.stop) * el`
#   :372 `cmd, addr = (SYSMEM_READ, self.addr) if self.sysmem else (MMIO_READ, self.off)`
#   :374 `res = data if self.fmt == 'B' else list(struct.unpack(f'<{(en - st) // el}{self.fmt}', data))`
#
# `struct.calcsize` for the format codes the class can carry, MEASURED:
#   B=1 H=2 I=4 L=8 Q=8   b=1 h=2 i=4 q=8   f=4 d=8
# `L` and `Q` are BOTH 8 -- a native-size-dependent coincidence and a 32-bit-port trap,
# because a `L` in a struct format is the platform's C `long` and the port cannot know
# it. `elemsize` answers 8 for both and says why.
#
# THE `or 0` AT :371 IS A TRUTHINESS RULE AGAIN, not a `None` check: `slice(0, n)` has
# `start == 0` and `0 or 0` is 0, so a slice from zero works -- but it means a slice
# whose start is zero goes through the FALLBACK, not through the value.
# ===========================================================================

def rmm.write_cmd(+sysmem: Bool) -> U32: Bool.pick(U32, sysmem, P.CMD_SYSMEM_WRITE(), P.CMD_MMIO_WRITE())
def gid.PREFIX_LEN() -> U32: 12
def t_02_gid() -> IO(Unit):
  do IO<Unit>:
    urow("sy_gid_len", gid.len())
    urow("sy_gid_prefix_len", gid.PREFIX_LEN())
    urow("sy_gid_tail_len", gid.TAIL_LEN())
    srow("sy_gid_prefix", P.gid.PREFIX_HEX())
    # the four tail bytes are the seam's, so the two rows below are the PREFIX
    # with a tail bolted on -- and they pin the ORDER, which a length cannot.
    srow("sy_gid_7f000001", gid.of(2130706433))
    srow("sy_gid_0a000001", gid.of(167772161))
    srow("sy_gid_ffffffff", gid.of(4294967295))
    srow("sy_gid_00000000", gid.of(0))
    srow("sy_gid_c0a801ff", gid.of(3232236031))
    # the %x formatter, which the GID and the OSX id both use
    srow("sy_hx_1002", P.hx.q(4098))
    srow("sy_hx_744c", P.hx.q(29772))
    srow("sy_hx_0", P.hx.q(0))
    srow("sy_hx_f", P.hx.q(15))
    srow("sy_hx_10", P.hx.q(16))
    srow("sy_hx_ff", P.hx.q(255))
    srow("sy_hx_100", P.hx.q(256))
    srow("sy_hx_1000", P.hx.q(4096))
    srow("sy_hx_ffff", P.hx.q(65535))
    urow("sy_hx_width_0", P.hx.width(0))
    urow("sy_hx_width_15", P.hx.width(15))
    urow("sy_hx_width_16", P.hx.width(16))
    urow("sy_hx_width_255", P.hx.width(255))
    urow("sy_hx_width_256", P.hx.width(256))
    urow("sy_hx_width_4095", P.hx.width(4095))
    urow("sy_hx_width_4096", P.hx.width(4096))
    srow("sy_hx_d4_1002", P.hx.d4(4098))

# --- :392-393 the socket option SEQUENCE, as a trace --------------------------
# --- Tr.has's NEGATIVE cases. M48 hard-wires the matcher to True{} and this
# function moved NOTHING until these three rows existed: every order row in this file
# was `True` in the baseline, so the whole matcher was unfalsifiable. That is the
# `ops_webgpu` M23 lesson arriving again, and the harness is what found it.
def bars.rebar(cur: U32, cap: U32) -> U32:
  P.bars.rebar.pick(U32.and(cur, P.REBAR_CTRL_MASK()), P.bars.rebar_size(cap))

# --- (c) the BAR probe loop --------------------------------------------------
#
# `bar_mem, bar_64 = bool(cfg & PCI_BASE_ADDRESS_MEM_PREFETCH),
#  cfg & PCI_BASE_ADDRESS_MEM_TYPE_64` -- `bar_mem` is a BOOL, so it indexes
# `mem_space_addr` as 0 or 1, and `bar_64` is the MASKED value (4), not a bool.
# :267 `int(x, 16).bit_length() - 1`, the log2 of the resizable-BAR size. The `- 1` is
# a subtraction that goes NEGATIVE for x < 2, and `resize_bar` writes that straight
# into sysfs -- MEASURED, x=0x1 -> "0" and x=0x0 -> "-1". A U32 port wraps it, and the
# row for the boundary says so rather than pretending.
def rpc.is_local(r: String) -> Bool: String.eq(r, "local")

# :402 `int(r.split(":")[1]) if ":" in r else 6667`. The colon test is the WHOLE of the
# default and it is on the ENTRY, not on the field.
def Rcmd.name(i: U32) -> String: P.Rcmd.name.of(i)

# name -> value, and it is the REVERSE of the same list so the two cannot disagree.
# `Rcmd.of("PROBE")` is 0 and `Rcmd.of("UNMAP_SYSMEM")` is 15, and a name that
# is not in the table
# is `mapflag_missing()` rather than 0 -- which matters, because 0 IS a legal value
# (PROBE) and a "not found" of 0 would be indistinguishable from it.
def REQ_OFF_DEV() -> U32: 1
def REQ_OFF_CMD() -> U32: 0
def post.n3(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(3, a0, a1, a2)
def sys.call_name(k: U32) -> String:
  P.sys.call_name.at(P.sys.call_names(), P.sys.call_name.go(
    List.length(&2, String, P.sys.call_names()), k, P.sys.call_names(), 0, 0))

# ===========================================================================
# READING THE TRACE.
# ===========================================================================

# :300 `is_bar_small` is `bar_info(vram_bar)[1] == (256 << 20)` -- an EQUALITY on the
# size, not a comparison, so 256 MiB - 1 is NOT a small bar. Both sides are rows.
def REMOTE_TIMEOUT() -> U32: 60
def REQ_OFF_BAR() -> U32: 5
def RESP_FIELDS() -> List<&2, String>: ["status", "resp0", "resp1"]
def RESP_OFF_RESP1() -> U32: 9

# ===========================================================================
# :418 -- THE PAD-TO-3 RULE, which is the quietest rule in the file.
#
#   `sock.sendall(struct.pack(REMOTE_REQ, cmd, dev, bar, *(*args, 0, 0, 0)[:3]))`
#
# `(*args, 0, 0, 0)[:3]` PADS to three and then SLICES to three, so a call with FOUR
# arguments silently loses the fourth and a call with TWO gets a zero. There is no
# arity check anywhere and `struct.pack` cannot fail, because the tuple is always
# exactly three long. MEASURED, the padded triples:
#   args=()             -> (0, 0, 0)
#   args=(5,)           -> (5, 0, 0)
#   args=(5, 6)         -> (5, 6, 0)
#   args=(5, 6, 7)      -> (5, 6, 7)
#   args=(5, 6, 7, 8)   -> (5, 6, 7)   <- THE FOURTH IS DROPPED
#   args=(5, 6, 7, 8, 9)-> (5, 6, 7)   <- AND THE FIFTH
# So `rpc` has a THREE-argument wire and every call site is responsible for not passing
# a fourth, and the port's `post.slots` is the rule.
# ===========================================================================

def REQ_OFF_ARG1() -> U32: 17
def rmm.read_cmd(+sysmem: Bool) -> U32: Bool.pick(U32, sysmem, P.CMD_SYSMEM_READ(), P.CMD_MMIO_READ())
# forward: the index, so a def that picks a `k` cannot pick one that is not a call
def sys.call_of(s: String) -> U32:
  match s:
    case "open": P.CALL_OPEN()
    case "close": P.CALL_CLOSE()
    case "mmap": P.CALL_MMAP()
    case "munmap": P.CALL_MUNMAP()
    case "system": P.CALL_SYSTEM()
    case "mlock": P.CALL_MLOCK()
    case "flock": P.CALL_FLOCK()
    case "umask": P.CALL_UMASK()
    case "readlink": P.CALL_READLINK()
    case "exists": P.CALL_EXISTS()
    case "listdir": P.CALL_LISTDIR()
    case "seek": P.CALL_SEEK()
    case "read": P.CALL_READ()
    case "write": P.CALL_WRITE()
    case "eventfd": P.CALL_EVENTFD()
    case "select.register": P.CALL_SELECT_REGISTER()
    case "mlock.ok": P.CALL_MLOCK_OK()
    case "madvise": P.CALL_MADVISE()
    case "cdll": P.CALL_CDLL()
    case "fence": P.CALL_FENCE()
    case "poll": P.CALL_POLL()
    case "ioctl": P.CALL_IOCTL()
    case "vfio.check_extension": P.CALL_VFIO_CHECK_EXT()
    case "vfio.set_container": P.CALL_VFIO_SET_CONTAINER()
    case "vfio.set_iommu": P.CALL_VFIO_SET_IOMMU()
    case "vfio.get_device_fd": P.CALL_VFIO_GET_DEVICE_FD()
    case "vfio.set_irqs": P.CALL_VFIO_SET_IRQS()
    case "connect": P.CALL_CONNECT()
    case "setsockopt": P.CALL_SETSOCKOPT()
    case "send": P.CALL_SEND()
    case "recv": P.CALL_RECV()
    case "poller": P.CALL_POLLER()
    case "resolve": P.CALL_RESOLVE()
    case _: P.CALL_NCALLS()

# reverse: a `got` accumulator and not a two-list walk, because the names are
# unique, so "the last hit" is "the only hit". The key is the INDEX, and the
# index is a `U32` turned into a `String` for the comparison -- a `U32`-to-
# `String` conversion that does not exist, so the walk compares the INDEXES and
# `sys.call_name` indexes the list with the index it found. The value
# direction and the name direction therefore cannot disagree: both read
# `sys.call_names()`.
def post.n1(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: P.post.slots(1, a0, a1, a2)
# --- :50-51 the two PLATFORM flag tables side by side ------------------------
def t_11_remote() -> IO(Unit):
  do IO<Unit>:
    # --- :359-361 the SIXTEEN names, both directions
    urow("sy_rcmd_n", P.Rcmd.count())
    srow("sy_rcmd_0", Rcmd.name(0))
    srow("sy_rcmd_3", Rcmd.name(3))
    srow("sy_rcmd_8", Rcmd.name(8))
    srow("sy_rcmd_12", Rcmd.name(12))
    srow("sy_rcmd_13", Rcmd.name(13))
    srow("sy_rcmd_15", Rcmd.name(15))
    srow("sy_rcmd_oob", Rcmd.name(16))
    urow("sy_rcmd_PROBE", Rcmd.of("PROBE"))
    urow("sy_rcmd_MAP_BAR", Rcmd.of("MAP_BAR"))
    urow("sy_rcmd_UNMAP", Rcmd.of("UNMAP_SYSMEM"))
    urow("sy_rcmd_absent", Rcmd.of("NOPE"))
    # the SPLIT: 13 and then 3, from the SAME list
    srow("sy_rcmd_first", sxs(Rcmd.first()))
    srow("sy_rcmd_second", sxs(Rcmd.second()))
    urow("sy_rcmd_nfirst", U32.from_nat(List.length(&2, String, Rcmd.first())))
    urow("sy_rcmd_nsecond", U32.from_nat(List.length(&2, String, Rcmd.second())))
    urow("sy_rcmd_base", P.Rcmd.base())
    urow("sy_rcmd_lo2", Rcmd.lo2())
    urow("sy_rcmd_hi2", Rcmd.hi2())
    urow("sy_rcmd_last", Rcmd.of(Rcmd.name(15)))
    # --- :363 the wire formats: field NAMES in order, and the offsets
    srow("sy_req_fields", sxs(REQ_FIELDS()))
    srow("sy_resp_fields", sxs(RESP_FIELDS()))
    urow("sy_req_size", REQ_SIZE())
    urow("sy_resp_size", RESP_SIZE())
    urow("sy_req_off_cmd", REQ_OFF_CMD())
    urow("sy_req_off_dev", REQ_OFF_DEV())
    urow("sy_req_off_bar", REQ_OFF_BAR())
    urow("sy_req_off_arg0", REQ_OFF_ARG0())
    urow("sy_req_off_arg1", REQ_OFF_ARG1())
    urow("sy_req_off_arg2", REQ_OFF_ARG2())
    urow("sy_resp_off_status", RESP_OFF_STATUS())
    urow("sy_resp_off_resp0", RESP_OFF_RESP0())
    urow("sy_resp_off_resp1", RESP_OFF_RESP1())
    # --- :418 the pad-to-3 rule, and the LAST TWO are the negative cases
    lrow("sy_post_0", post.n0(5, 6, 7))
    lrow("sy_post_1", post.n1(5, 6, 7))
    lrow("sy_post_2", post.n2(5, 6, 7))
    lrow("sy_post_3", post.n3(5, 6, 7))
    lrow("sy_post_4", post.n4(5, 6, 7))
    lrow("sy_post_5", post.n5(5, 6, 7))
    # --- :370 the calcsize table, both directions
    urow("sy_el_B", elemsize("B"))
    urow("sy_el_H", elemsize("H"))
    urow("sy_el_I", elemsize("I"))
    urow("sy_el_L", elemsize("L"))
    urow("sy_el_Q", elemsize("Q"))
    urow("sy_el_f", elemsize("f"))
    urow("sy_el_d", elemsize("d"))
    urow("sy_el_absent", elemsize("Z"))
    urow("sy_eli_B", P.elemsize.at("B"))
    urow("sy_eli_Q", P.elemsize.at("Q"))
    urow("sy_eli_absent", P.elemsize.at("Z"))
    urow("sy_fmt_n", U32.from_nat(List.length(&2, String, P.FMT_CHARS())))
    urow("sy_fmt_nsize", U32.from_nat(List.length(&2, U32, P.FMT_SIZES())))
    # L and Q are BOTH 8 -- a native-size coincidence a 32-bit port must be told about
    row("sy_el_L_eq_Q", U32.is_eq(elemsize("L"), elemsize("Q")))
    # --- :371-372 the slice arithmetic and the cmd/address choice
    urow("sy_rmm_st_2", rmm.st(2, 1))
    urow("sy_rmm_en_6", rmm.en(6, 8, 1))
    urow("sy_rmm_en_absent", rmm.en(0, 8, 1))
    urow("sy_rmm_st_I0", rmm.st(0, 4))
    urow("sy_rmm_en_I8", rmm.en(8, 8, 4))
    urow("sy_rmm_cnt_B", rmm.count(2, 6, 1))
    urow("sy_rmm_cnt_I", rmm.count(0, 32, 4))
    urow("sy_rmm_ist3", rmm.int_st(3, 1))
    urow("sy_rmm_ien3", rmm.int_en(3, 1))
    urow("sy_rmm_cmd_rd_mmio", rmm.read_cmd(False{}))
    urow("sy_rmm_cmd_rd_sys", rmm.read_cmd(True{}))
    urow("sy_rmm_cmd_wr_mmio", rmm.write_cmd(False{}))
    urow("sy_rmm_cmd_wr_sys", rmm.write_cmd(True{}))
    urow("sy_rmm_addr_mmio", rmm.read_addr(False{}, 4096, 8192))
    urow("sy_rmm_addr_sys", rmm.read_addr(True{}, 4096, 8192))
    # --- :386-406 the REMOTE parser and the socket options
    row("sy_local_yes", rpc.is_local("local"))
    row("sy_local_no", rpc.is_local("10.0.0.1"))
    urow("sy_port_colon", rpc.port(True{}, 6666))
    urow("sy_port_default", rpc.port(False{}, 6666))
    urow("sy_port_default0", rpc.port(False{}, 0))
    srow("sy_rpc_name", rpc.device_name(HOST(), 6667, "0000:03:00.0"))
    srow("sy_rpc_name_p", rpc.device_name(HOST(), 1, "0000:03:00.0"))
    lrow("sy_sock_opts", P.rpc.buf_opts())
    urow("sy_sock_buf", SOCK_BUF())
    urow("sy_sock_sndbuf", P.SO_SNDBUF())
    urow("sy_sock_rcvbuf", P.SO_RCVBUF())
    urow("sy_sock_sol", P.SOL_SOCKET())
    urow("sy_sock_ipproto", P.IPPROTO_TCP())
    urow("sy_sock_nodelay", TCP_NODELAY())
    urow("sy_remote_timeout", REMOTE_TIMEOUT())
    urow("sy_remote_port", P.REMOTE_DEFAULT_PORT())
    # --- the call table, both directions
    urow("sy_ncalls", U32.from_nat(List.length(&2, String, P.sys.call_names())))
    srow("sy_call_0", sys.call_name(0))
    srow("sy_call_18", sys.call_name(18))
    srow("sy_call_32", sys.call_name(32))
    srow("sy_call_33", sys.call_name(33))
    srow("sy_call_oob", sys.call_name(34))
    urow("sy_call_of_system", sys.call_of("system"))
    urow("sy_call_of_mmap", sys.call_of("mmap"))
    urow("sy_call_of_bogus", sys.call_of("bogus"))
    row("sy_is_mock", sys.is_mock("MOCK"))
    row("sy_is_mock_no", sys.is_mock("AMD"))

# ===========================================================================
# THE MUTATION TABLE. Every number is the harness's output and not an estimate.
# The harness is `.agents/slop/system_mutate.py`: it applies one edit to a scratch
# copy INSIDE THE TREE (a $TMPDIR copy cannot resolve `import ../../helpers.bend`),
# runs the interpreted lane, and diffs WHOLE `name=value` LINES -- never row names,
# because a name-diff harness reports 0 for every mutation whose effect is a changed
# value and EVERY mutation in this file changes a value. It refuses to report a
# mutation whose anchor is not in the file: that is a broken instrument and not a
# finding, and it prints `HARNESS-FAIL` for it. The baseline is 440 rows.
#
# | # | rows moved | what it is testing |
# | --- | --- | --- |
# | # | rows moved | what it is testing |
# | --- | --- | --- |
# | M1 | 4 <br>`sy_flagL_locked`, `sy_flag_locked_linux`, `sy_map_locked_linux`, `sy_map_locked_osx` | :51's `0 if OSX else 0x2000`, with the ternary reversed |
# | M2 | 4 <br>`sy_flagL_populate`, `sy_flag_populate_linux`, `sy_map_populate_linux`, `sy_map_populate_osx` | :51's `getattr(mmap, 'MAP_POPULATE', 0 if OSX else 0x008000)`, reversed |
# | M3 | 2 <br>`sy_flag_anon_osx`, `sy_map_anon_osx` | MAP_ANONYMOUS's platform split -- a host value where a platform one belongs |
# | M4 | 1 <br>`sy_pageframe_hi` | (1<<55)-1's HIGH word. 0x7fffff vs 0x7ffffff: one hex digit, and the bug I made |
# | M5 | 6 <br>`sy_echo_enable`, `sy_echo_len_enable`, `sy_echo_len_pagemap`, `sy_echo_pagemap`, `sy_echo_reset`, `sy_write_retry_cmd` | WALL 2's SPACES around the `>`. A dropped space is a `sudo` that writes a file named `echo1` |
# | M6 | COMPILE-FAIL (- expected : a defined name) | the def is GONE (a rename is the one edit that proves the rows read the def) |
# | M7 | 4 <br>`sy_va_cached_nmmap`, `sy_va_nreserved`, `sy_va_nreserved2`, `sy_va_other_nmmap` | THE CACHE. :86's `functools.cache` -- the negative case is IN THE PYTHON SOURCE |
# | M8 | 2 <br>`sy_write_fail_refused`, `sy_write_retry_refused` | :59's RAISE. Everything after the second read truncates |
# | M9 | 6 <br>`sy_pagemap_order`, `sy_pagemap_total_reads`, `sy_write_fail_nread`, `sy_write_ok_nread`, `sy_write_ok_read`, `sy_write_retry_nread` | :57's FIRST READ. It happens on both arms, before the comparison |
# | M10 | 1 <br>`sy_alloc_size_1001_plain` | THE WALRUS. `size := round_up(...)` is inside the `if contiguous`, so a plain request is never rounded |
# | M11 | 3 <br>`sy_alloc_fixed_0`, `sy_alloc_flags_2000_0`, `sy_alloc_mmap_2p` | :100's `(MAP_FIXED if vaddr else 0)` -- a FALSY test, not a None test |
# | M12 | 4 <br>`sy_buses_0`, `sy_buses_1`, `sy_buses_2`, `sy_writes_bus0` | :141's `(bus+1) << 8 | (gpu_bus) << 16` -- the two shifts TRANSPOSED. A silently wrong bus number |
# | M13 | 3 <br>`sy_membase16`, `sy_writes_bus0`, `sy_writes_bus3` | :144's `(mem_base>>16) & 0xffff` -- the shift dropped |
# | M14 | 3 <br>`sy_prefbase16`, `sy_writes_bus0`, `sy_writes_bus3` | the HIGH word substituted for the low one. The bug I made: 8 instead of 0 |
# | M15 | 5 <br>`sy_rebar_1001_201`, `sy_rebar_1_201`, `sy_rebar_2100_201`, `sy_rebar_size_1001`, `sy_rebar_size_2100` | :158's `<< 8` -- the shift amount, which resizes a BAR to the wrong power of two |
# | M16 | 3 <br>`sy_rebar_1001_201`, `sy_rebar_2100_201`, `sy_rebar_mask` | `~0x1F00` -- the bits it CLEARS |
# | M17 | 4 <br>`sy_barsize_10000000`, `sy_barsize_f0000000`, `sy_barsize_fff00000`, `sy_barsize_fffff000` | :175's `& ~0xf`. A BAR size four orders of magnitude wrong |
# | M18 | 1 <br>`sy_step32` | :183's `bar_off += 8 if bar_64 else 4` -- the two arms SWAPPED |
# | M19 | 1 <br>`sy_more_24` | `while bar_off < 24` -- `<` against `<=`, so the loop runs one BAR too many |
# | M20 | 1 <br>`sy_inva_base` | the two-word lexicographic `>=`. `va_base <= lo` with `==` refused |
# | M21 | 4 <br>`sy_barinfo_0`, `sy_barinfo_1000`, `sy_barinfo_7c`, `sy_barinfo_7d0` | :260's `int(e,16) - int(s,16) + 1`. The `+ 1` IS the whole of bar_info |
# | M22 | 1 <br>`sy_issmall_no` | :300's `== (256 << 20)` turned into a comparison -- a 1 GiB bar is suddenly 'small' |
# | M23 | 8 <br>`sy_align_big`, `sy_align_big1`, `sy_align_just_under`, `sy_align_small`, `sy_align_tiny`, `sy_ladder_1001`, `sy_ladder_1234567`, `sy_ladder_800001` | :315's `(2 << 20) if size >= (8 << 20) else (4 << 10)` -- the two arms SWAPPED |
# | M24 | 2 <br>`sy_ladder_1234567`, `sy_ladder_800001` | :315's `PAGESIZE if should_use_sysmem else <ladder>` -- the two arms SWAPPED |
# | M25 | 3 <br>`sy_hx_100`, `sy_hx_width_256`, `sy_hx_width_4095` | the THIRD threshold of the `%x` ladder. The bug I made: one predicate for two rungs |
# | M26 | 10 <br>`sy_gid_0a000001`, `sy_gid_7f000001`, `sy_gid_c0a801ff`, `sy_gid_ffffffff`, `sy_hx_744c`, `sy_hx_f`, `sy_hx_ff`, `sy_hx_ffff`, `sy_id_osx_1002_744c`, `sy_id_osx_10de_144c` | the `a`-..`f` base of `%x`. Off by one in one letter, and only the letters see it |
# | M27 | 0 | :418's `[:3]` TRUNCATION -- a fourth argument would be sent |
# | M28 | 3 <br>`sy_port_colon`, `sy_port_default`, `sy_port_default0` | :402's `int(...) if ":" in r else 6667` -- the default on the wrong side |
# | M29 | 4 <br>`sy_rcmd_0`, `sy_rcmd_MAP_BAR`, `sy_rcmd_PROBE`, `sy_rcmd_first` | :360's enum ORDER -- two members NEIGHBOUR-SWAPPED, which is a silently wrong remote command |
# | M31 | 3 <br>`sy_nv_2f01_masked`, `sy_nv_2fff_masked`, `sy_term_nv_2f01` | :126's `(device & mask)` -- the AND dropped, which refuses every NVIDIA card with a nonzero revision |
# | M32 | 2 <br>`sy_base_030000`, `sy_base_030200` | :116/:122's `>> 16` |
# | M33 | 9 <br>`sy_capid_1001`, `sy_capid_15`, `sy_capid_1500`, `sy_capid_2100`, `sy_capid_ff15`, `sy_is_rebar_15`, `sy_is_rebar_1500`, `sy_is_rebar_1501`, `sy_is_rebar_ff15` | :156's `PCI_EXT_CAP_ID` -- the low BYTE, not bits 15:8 |
# | M34 | 4 <br>`sy_bus_trim`, `sy_pci_sibs`, `sy_sib1`, `sy_sib7` | :220's `pcibus[:-1]` -- `take` against `drop`. `drop` removes from the FRONT |
# | M35 | 2 <br>`sy_class_AMD`, `sy_class_NPU` | :136's `device[:2]` -- the class is TWO characters, not one |
# | M36 | 2 <br>`sy_mapflags_0`, `sy_mapflags_nz` | :263's `MAP_SHARED | (MAP_FIXED if addr else 0)` |
# | M37 | 4 <br>`sy_resize_0`, `sy_resize_1`, `sy_resize_100000`, `sy_resize_40000000` | :267's `bit_length() - 1` -- the wrong constant |
# | M38 | 1 <br>`sy_meta_sysmem_cpu` | :321's LITERAL `has_cpu_mapping=True` read as the `cpu_access` argument |
# | M39 | 1 <br>`sy_pg_explicit_pci` | :297's getattr fallback -- which of the three classes SETS peer_group |
# | M40 | 2 <br>`sy_path_override`, `sy_path_unbind` | the sysfs TAIL table -- two neighbours swapped, a silently wrong unbind path |
# | M41 | 2 <br>`sy_sock_opts`, `sy_sock_opts_str` | :393's `(SO_SNDBUF, SO_RCVBUF)` -- the two options TRANSPOSED |
# | M42 | 0 | THE RAISE. Every refusal row at once, and nothing else |
# | M43 | 6 <br>`sy_el_H`, `sy_el_I`, `sy_el_L`, `sy_el_Q`, `sy_el_d`, `sy_el_f` | the struct calcsize table's WALK -- a stub that always misses, so only the negative row moves |
# | M44 | 19 <br>`sy_flagL_anon`, `sy_flagL_locked`, `sy_flagL_missing`, `sy_flagL_populate`, `sy_flagL_private`, `sy_flagL_shared`, `sy_flag_anon_linux`, `sy_flag_anon_osx`, `sy_flag_dontfork`, `sy_flag_fixed`, `sy_flag_hugetlb`, `sy_flag_locked_linux`, `sy_flag_missing`, `sy_flag_missing_linux` ... | the mmap table's WALK, reduced to its length. Only the name rows and the missing row can move |
# | M45 | 3 <br>`sy_nwrites`, `sy_writes_bus0`, `sy_writes_bus3` | the EIGHTH write -- :151's PCI_COMMAND duplicated. The bug I made: nine writes for eight |
# | M46 | 1 <br>`sy_writes_bus3` | :141's `bus` threaded into the first write -- pinned at zero, which is the bus-0 fixture |
# | M48 | 4 <br>`sy_has_absent`, `sy_has_reversed`, `sy_has_wrong_arg`, `sy_has_wrong_str` | Tr.has with the answer hard-wired -- the order rows and the matcher, all of them |
# | M47 | 0 | CONTROL -- a comment-only edit. A table with no row that CANNOT move is a table of coincidences |
# | M49 | 3 <br>`sy_pci_bound_nopen`, `sy_pci_nopen`, `sy_pci_opens` | :211's `enable` open -- the DEAD-CODE probe. A def nothing calls is invisible to every other check |
# | M50 | 3 <br>`sy_gid_0a000001`, `sy_gid_7f000001`, `sy_gid_c0a801ff` | :53's tail ORDER -- four bytes the wrong way round, and every length and total still correct |#
# M6 is a compile-FAIL and that is the point: renaming `sysfs.echo` breaks the
# build, which is the one edit that proves the rows
# really read the def instead of restating a literal somewhere else.
#
# THE ZEROS, and none of them is a coverage claim dressed up.
#
#   M27 -- A THEOREM, and it is about the def it perturbs. :418's
#     `(*args, 0, 0, 0)[:3]` pads AND truncates to three, and `post.nclamp` is the
#     clamp. Returning `n` unchanged moves nothing because the only slot indices that
#     exist are 0, 1 and 2, and on those `i < min(n, 3)` and `i < n` are the SAME
#     predicate. `post.slot` already enforces the truncation by its own test, so
#     `post.nclamp` is redundant with it -- rule 8's leaf sweep would delete it, and
#     the theorem is why deleting it is behaviour-preserving. Reported, not closed.
#
#   M42 -- A STRUCTURAL BLIND SPOT with a reason, and the reason is in the source.
#     `Tr.emit.go`'s `refused` guard drops nothing when removed, because NO def in
#     this file emits after a refusal: every truncation is produced by the CALLER's
#     `Bool.pick` -- `sysfs.raise` fails on a trace whose last call it just emitted,
#     and `Tr.emit.stop` fails on the call it emits. So the guard is defence-in-depth
#     that Python's control flow never reaches. M8, which removes the RAISE ITSELF,
#     moves 2 rows, so the refusals ARE checked; what is not checked is a hypothetical
#     emit-after-refusal that the Python cannot perform.
#
#   M47 -- THE CONTROL, and it is the row that makes the other forty-eight mean
#     something. A comment-only edit. If this ever moves, the harness is diffing
#     something other than the rows.
#
# TWO zeros that were real gaps and are now fixed, and both are the reason the table
# has to be MEASURED rather than reasoned about:
#
#   M4 moved 0 on its first run. `PAGEFRAME_MASK_HI` is WALL 1's `(1<<55)-1` high
#     word and NO row read it, so perturbing it by a whole hex digit moved nothing --
#     and the wrong value (0x7ffffff for 0x7fffff) was a bug I had already made while
#     writing the constant. Fixed by `sy_pageframe_hi`, `sy_pageframe_lo` and
#     `sy_pageframe_differs`; it moves 1 now. Rule 8 -- "an unread constant is not a
#     port" -- arriving as a zero.
#   M48 moved 0 on its first run. `Tr.has` hard-wired to `True{}` changed nothing,
#     because every order row in this file was `True` in the baseline. Asking for the
#     matcher's NEGATIVE rows (`sy_has_absent`, `sy_has_reversed`, `sy_has_wrong_arg`,
#     `sy_has_wrong_str`) exposed a REAL BUG: `Tr.step.at` matched on `at` and
#     returned `at + 1` for the `0n` arm WITHOUT COMPARING, so the matcher said True
#     for a pattern element that never occurred. M48 now moves 4 and `Tr.has` can
#     fail. This is `ops_webgpu`'s M23 lesson arriving a third time.
#
# WHAT this gate still does not see, and the list is short enough to be honest about:
#
#   1. EVERY FFI CALL. `os.open`, `libc.mmap`, `fcntl.flock`, `ctypes.CDLL`,
#     `socket.*`, the `vfio.*` ctypes structs, the iokit/CoreFoundation chain and
#     every `struct.pack`/`unpack` byte. The trace records the call, its one `U32`
#     argument and its STRING; nothing checks that the argument is the RIGHT one for
#     that call. `sy_flag_enable` reads the CONSTANT `pci.flags_enable()` and not the
#     `CALL_OPEN` that carries it, so mutating `pci.probe.enable` to use
#     `pci.flags_unbind()` moves NOTHING -- the same class as `ops_webgpu`'s "the
#     right descriptor on the right call", and the honest way to close it would be a
#     `Tr.args(CALL_OPEN)` row, which would need the enable and config opens to
#     differ in `arg` in a fixture where they do not.
#   2. THE TRACE'S `arg` FOR MOST CALLS. `Tr.args` is read by ten rows; the other
#     twenty-eight calls carry an `arg` no row inspects. A wrong `bar` in a
#     `setsockopt` is invisible.
#   3. THE u64 ARITHMETIC. Wall 1: the pagemap multiply, the 64-bit BAR size and
#     `struct.unpack('<Q', data)`. The 32-bit BAR size IS computed (`bars.size32`) and
#     gated at five fixtures; the 64-bit arm is not computed at all.
#   4. `BumpAllocator`, `MMIOInterface`, `VirtMapping` and `AddrSpace` are
#     `support/memory.py`; `USB3` and `CustomASM24Controller` are `support/usb.py`.
#     This file NAMES them and ports none of them.
#   5. THE `REMOTE` ENV parser'S split and strip (:399). Wall: no `String.split`, no
#     `String.strip`. The two RULES the split feeds -- `r == "local"`, `":" in r`, the
#     6667 default and the result string -- are gated; the tokenisation is not.
#   6. `inet_aton` (:53) and the ORDER of the device tables. The twelve-byte GID
#     prefix, the length and the tail's ORDER are gated; the dotted quad to four bytes
#     is the seam's.
#   7. `filter_visible_devices` is ported as `vis.*` and the PARSER is gated, but
#     nothing in this file CALLS `vis.range` -- the DEV target string is
#     `helpers.py`'s. The rows drive `vis.range` directly, so the parser is checked
#     and the WIRING is not.
#
def scan.amd(vndr: U32, device: U32) -> Bool:
  P.scan.keeps(vndr, P.AMD_VENDOR(), device, [P.AMD_MASK()], [P.amd_ids()])

# --- :67-70 `pagemap`, also a cached_property ---------------------------------
def bars.size32(lo: U32) -> U32: U32.sub(0, U32.and(lo, P.LO_MASK()))

# `bar_off += 8 if bar_64 else 4`, and the loop is `while bar_off < 24`.
# `resource{bar_idx}` and `resource{bar_idx}_resize`, :256/:266.
def bars.DMA_BASE() -> U32: 61440                   # 0xf000
def t_11_sock_str() -> IO(Unit):
  do IO<Unit>:
    +a : P.Tr <- IO.pure(P.Tr, rpc.options(Tr.of()))
    srow("sy_sock_opts_str", sxs(Tr.strs(P.CALL_SETSOCKOPT(), Tr.calls(a))))
    lrow("sy_sock_args", P.Tr.args(P.CALL_SETSOCKOPT(), Tr.calls(a)))

# --- :36/:42 the mmap / munmap seam -------------------------------------------
def bars.is_mem(cfg: U32) -> Bool:
  U32.is_eq(U32.and(cfg, P.PCI_BASE_ADDRESS_SPACE()), P.PCI_BASE_ADDRESS_SPACE())

# THE 32-BIT SIZE, which is exact in U32: `0 - (lo & 0xfffffff0)`.
# :122-123 the base-class filter, `int(read(..., "class"), 16) >> 16 != base_class`.
# The shift is 16 and the comparison is against the WHOLE shifted value, so
# `0x30000 >> 16 == 0x03` accepts and `0x020000 >> 16 == 0x02` does not.
def scan.base_ok(class_code: U32, base_class: U32) -> Bool:
  U32.is_eq(U32.shrn(class_code, 16n), base_class)

# :156 `pci.PCI_EXT_CAP_ID(x)` and :161 `pci.PCI_EXT_CAP_NEXT(x)`. Both are the low
# byte of the dword, and the gate asks both directions because the REBAR test is the
# only reader of the first and the walk is the only reader of the second.
# (1<<55)-1 == 0x7FFFFFFFFFFFFF, so the HIGH word is 0x7FFFFF == 8388607 and not
# 0x7FFFFFF. I wrote 134217727 (0x7FFFFFF) -- one hex digit too many -- and the
# oracle caught it before a row existed to agree with it. A mask with one wrong
# half selects the wrong physical pages and nothing else in the file notices.
def scan.id_osx(vendor: U32, device: U32) -> String:
  String.concat([P.hx.q(vendor), ":", P.hx.q(device)])

# :122-123 the base-class filter, `int(read(..., "class"), 16) >> 16 != base_class`.
# The shift is 16 and the comparison is against the WHOLE shifted value, so
# `0x30000 >> 16 == 0x03` accepts and `0x020000 >> 16 == 0x02` does not.
def bars.writes(bus: U32) -> List<&2, P.Cfg>: P.bars.writes.of(bus, P.GPU_BUS(), Nil{})

# --- (b) the REBAR rewrite ---------------------------------------------------
#
# `int(cap >> 4).bit_length() - 1` is log2 of the BAR size in the capability's own
# field, and it is a `Nat` in Python and a bounded `U32` here. `hx.bitlen` is bounded
# to 32 bits by a `Nat` countdown, and the bound is the claim.
def t_01_caps() -> IO(Unit):
  do IO<Unit>:
    # --- :50-51 the two platform-dependent constants, BOTH arms
    urow("sy_map_locked_linux", P.cap.locked_of(P.CAP_NO()))
    urow("sy_map_locked_osx", P.cap.locked_of(P.CAP_YES()))
    urow("sy_map_populate_linux", P.cap.populate_of(P.CAP_NO()))
    urow("sy_map_populate_osx", P.cap.populate_of(P.CAP_YES()))
    urow("sy_map_populate_from_linux", cap.populate_from(P.CAP_NO()))
    urow("sy_map_populate_from_osx", cap.populate_from(P.CAP_YES()))
    urow("sy_map_anon_linux", P.MAP_ANONYMOUS_LINUX())
    urow("sy_map_anon_osx", P.MAP_ANONYMOUS_OSX())
    urow("sy_va_flags_linux", P.VA_FLAGS_LINUX())
    urow("sy_va_flags_osx", P.VA_FLAGS_OSX())
    # --- the table, BOTH directions, and the two PLATFORMS
    urow("sy_flag_anon_linux", mapflag_of_linux(32))
    urow("sy_flag_anon_osx", mapflag_of(4096))
    urow("sy_flag_fixed", mapflag_of(16))
    urow("sy_flag_noreplace", mapflag_of(1048576))
    urow("sy_flag_populate_linux", mapflag_of_linux(32768))
    urow("sy_flag_locked_linux", mapflag_of_linux(8192))
    urow("sy_flag_noreserve", mapflag_of(1024))
    urow("sy_flag_hugetlb", mapflag_of(262144))
    urow("sy_flag_dontfork", mapflag_of(10))
    urow("sy_flag_shared", mapflag_of(1))
    urow("sy_flag_private", mapflag_of(2))
    srow("sy_flag_name_0", mapflag_name(0))
    srow("sy_flag_name_4", mapflag_name(4))
    srow("sy_flag_name_6", mapflag_name(6))
    srow("sy_flag_name_8", mapflag_name(8))
    srow("sy_flag_name_11", mapflag_name(11))
    # the NEGATIVE direction, in both tables
    urow("sy_flag_missing", mapflag_of(3))
    srow("sy_flag_name_oob", mapflag_name(13))
    urow("sy_flag_missing_linux", mapflag_of_linux(3))

# :91-92 `lock_memory`: `if libc.mlock(c_void_p(addr), size): raise`. A NONZERO
# return is the refusal, so the port emits the call and then truncates on a
# nonzero result. The `addr` is a 64-bit pointer, so only its LOW word travels.
def t_08_bars() -> IO(Unit):
  do IO<Unit>:
    # --- (a) the EIGHT writes, in order, whole argument tuples
    srow("sy_buses_0", U32.show(P.bars.buses(0, 4)))
    srow("sy_buses_1", U32.show(P.bars.buses(1, 4)))
    srow("sy_buses_2", U32.show(P.bars.buses(2, 4)))
    srow("sy_buses_3", U32.show(P.bars.buses(3, 4)))
    srow("sy_writes_bus0", cfgs(bars.writes(0)))
    srow("sy_writes_bus3", cfgs(bars.writes(3)))
    urow("sy_nwrites", U32.from_nat(List.length(&2, P.Cfg, bars.writes(0))))
    urow("sy_membase16", P.bars.mem_base16(P.MEM_BASE_USB()))
    urow("sy_prefbase16", P.bars.pref_base16(P.PREF_BASE_HI(), P.PREF_BASE_LO()))
    urow("sy_prefbasehi", P.bars.pref_base_hi(P.PREF_BASE_HI(), P.PREF_BASE_LO()))
    # --- (b) the REBAR rewrite
    urow("sy_rebar_1001_201", bars.rebar(513, 4097))
    urow("sy_rebar_2100_201", bars.rebar(513, 8448))
    urow("sy_rebar_1_201", bars.rebar(513, 1))
    urow("sy_rebar_size_1001", P.bars.rebar_size(4097))
    urow("sy_rebar_size_2100", P.bars.rebar_size(8448))
    urow("sy_rebar_mask", P.REBAR_CTRL_MASK())
    urow("sy_bitlen_0", P.hx.bitlen(0))
    urow("sy_bitlen_1", P.hx.bitlen(1))
    urow("sy_bitlen_10", P.hx.bitlen(16))
    urow("sy_bitlen_ff", P.hx.bitlen(255))
    urow("sy_bitlen_100", P.hx.bitlen(256))
    urow("sy_bitlen_10000", P.hx.bitlen(65536))
    # --- (c) the BAR probe
    urow("sy_barsize_10000000", bars.size32(268435456))
    urow("sy_barsize_f0000000", bars.size32(4026531840))
    urow("sy_barsize_0", bars.size32(0))
    urow("sy_barsize_fff00000", bars.size32(4293918720))
    urow("sy_barsize_fffff000", bars.size32(4294963200))
    urow("sy_step32", bars.step(0, 0))
    urow("sy_step64", bars.step(0, 4))
    row("sy_more_0", bars.more(0))
    row("sy_more_20", bars.more(20))
    row("sy_more_24", bars.more(24))
    row("sy_more_28", bars.more(28))
    row("sy_ismem_0", bars.is_mem(0))
    row("sy_ismem_1", bars.is_mem(1))
    row("sy_ismem_2", bars.is_mem(2))
    urow("sy_barmem_0", bars.bar_mem(0))
    urow("sy_barmem_8", bars.bar_mem(8))
    urow("sy_barmem_9", bars.bar_mem(9))
    urow("sy_nextaddr_10000000", bars.next_addr(268435456, 268435456))
    urow("sy_nextaddr_1000", bars.next_addr(0, 4096))
    urow("sy_nextaddr_1000_2m", bars.next_addr(0, 268435456))
    # --- the USBPCIDevice constants
    urow("sy_usb_sram", bars.SRAM_SIZE())
    urow("sy_usb_dma", bars.DMA_BASE())
    urow("sy_usb_paddr", bars.PADDR_BASE())

# --- :208 the ORDER of `PCIDevice.__init__` -----------------------------------
def t_01_flags_linux() -> IO(Unit):
  do IO<Unit>:
    urow("sy_flagL_anon", mapflag_of_linux(32))
    urow("sy_flagL_populate", mapflag_of_linux(32768))
    urow("sy_flagL_locked", mapflag_of_linux(8192))
    urow("sy_flagL_missing", mapflag_of_linux(3))
    urow("sy_flagL_shared", mapflag_of_linux(1))
    urow("sy_flagL_private", mapflag_of_linux(2))
    srow("sy_flagL_name5", mapflag_name(5))
    srow("sy_flagL_name6", mapflag_name(6))

# --- :56-59, four FIXTURE DEFS rather than four binders in one block. --------
# A do-block binder of a `Data` record is AFFINE -- one read -- and a trace needs
# five. So each fixture is its own def, and the rows that read one trace live with
# it. That is the same shape `am/ip.bend` uses and it is the price of the linearity.
# the SECOND question: does a fence get emitted at all? A None library is a SILENT
# no-op, not an error.
def scan.nv(vndr: U32, device: U32) -> Bool:
  P.scan.keeps(vndr, P.NV_VENDOR(), device, [P.NV_MASK()], [P.nv_ids()])

# :117's `f"{v:x}:{d:x}"`, the OSX id, beside :124's Linux `pcibus` string. Two
# different strings for the same device, and which one you get is the platform.
def t_07_scan() -> IO(Unit):
  do IO<Unit>:
    # --- :126 the filter, AMD's exact mask
    row("sy_amd_744c", scan.amd(4098, 29772))
    row("sy_amd_74a1", scan.amd(4098, 29857))
    row("sy_amd_75b3", scan.amd(4098, 30131))
    # THE NEGATIVE CASES, one past the top and one below the bottom
    row("sy_amd_75b4", scan.amd(4098, 30132))
    row("sy_amd_74a0", scan.amd(4098, 29856))
    row("sy_amd_744d", scan.amd(4098, 29773))
    row("sy_amd_1635", scan.amd(4098, 5685))
    row("sy_amd_wrong_vendor", scan.amd(4318, 29772))
    # --- NVIDIA's mask, and the `device & mask` IS NOT `device`
    row("sy_nv_2200", scan.nv(4318, 8704))
    row("sy_nv_2f00", scan.nv(4318, 12032))
    row("sy_nv_2f01_masked", scan.nv(4318, 12033))
    row("sy_nv_2fff_masked", scan.nv(4318, 12287))
    row("sy_nv_3000", scan.nv(4318, 12288))
    row("sy_nv_2100", scan.nv(4318, 8448))
    row("sy_nv_amd_id", scan.nv(4318, 29772))
    # the term alone, so a row can say WHICH conjunct refused
    row("sy_term_amd_744c", P.scan.term(29772, P.AMD_MASK(), P.amd_ids()))
    row("sy_term_amd_75b4", P.scan.term(30132, P.AMD_MASK(), P.amd_ids()))
    row("sy_term_nv_2f01", P.scan.term(12033, P.NV_MASK(), P.nv_ids()))
    urow("sy_namd", U32.from_nat(List.length(&2, U32, P.amd_ids())))
    urow("sy_nnv", U32.from_nat(List.length(&2, U32, P.nv_ids())))
    # --- :122 the base-class shift
    row("sy_base_030000", scan.base_ok(196608, 3))
    row("sy_base_030200", scan.base_ok(197632, 3))
    row("sy_base_020000", scan.base_ok(131072, 3))
    row("sy_base_0c0330", scan.base_ok(787504, 3))
    # --- :117 the OSX id format
    srow("sy_id_osx_1002_744c", scan.id_osx(4098, 29772))
    srow("sy_id_osx_10de_144c", scan.id_osx(4318, 5196))
    srow("sy_id_osx_8086_0", scan.id_osx(32902, 0))
    # --- :156/:161 the extended-capability byte
    # A REBAR header's id 0x15 is in the LOW byte; 0x1001 has id 1 and is NOT one.
    urow("sy_capid_15", P.scan.cap_id(21))
    urow("sy_capid_ff15", P.scan.cap_id(65301))
    urow("sy_capid_1001", P.scan.cap_id(4097))
    urow("sy_capid_2100", P.scan.cap_id(8448))
    urow("sy_capid_1500", P.scan.cap_id(5376))
    row("sy_is_rebar_15", scan.is_rebar(21))
    row("sy_is_rebar_ff15", scan.is_rebar(65301))
    row("sy_is_rebar_1001", scan.is_rebar(4097))
    row("sy_is_rebar_2100", scan.is_rebar(8448))
    row("sy_is_rebar_1500", scan.is_rebar(5376))
    row("sy_is_rebar_1501", scan.is_rebar(5377))
    urow("sy_rebar_capid", P.PCI_EXT_CAP_ID_REBAR())

def main() -> IO(Unit):
  do IO<Unit>:
    t_01_caps()
    t_01_flags_linux()
    t_02_gid()
    t_03_libs()
    t_04_sysfs()
    t_05_cache()
    t_06_alloc()
    t_07_scan()
    t_08_bars()
    t_09_pci()
    t_10_face()
    t_11_remote()
    t_11_has()
    t_11_pagemask()
    t_11_sock_n()
    t_11_sock_arg()
    t_11_sock_str()
