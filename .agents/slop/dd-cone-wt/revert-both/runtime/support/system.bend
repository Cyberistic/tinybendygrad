# tinybendygrad/runtime/support/system.bend -- port of tinygrad/runtime/support/system.py
#
# THE OS BOUNDARY. `support/system.py` is where tinygrad stops being arithmetic
# and starts being a PROCESS: `os.open`, `mmap.mmap`, `libc.mlock`, `os.system`,
# `fcntl.flock`, `socket.create_connection`, `ctypes.CDLL`, and the sysfs reads
# that answer "is this GPU here". None of that is an arithmetic kernel, and none
# of it is a Bend type. What survives the crossing is the part that DECIDES:
# which constant goes in which register, which string gets passed to `sudo`,
# which path gets opened with which flags, and in what ORDER.
#
# So this file is a trace. `Tr` records every OS call the Python makes, and every
# def either BUILDS THE ARGUMENT of one call (pure, and the gate diffs it) or
# RECORDS that call (and the gate checks ORDER and IDENTITY). There is no third
# kind, and the file declares NO foreign effect: the trace IS the seam, exactly
# as in `ops_webgpu.bend`, `am/ip.bend` and `nv/ip.bend`.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. "FFI" means there is nothing to check: the call
# itself is the port's job and the Python line is the whole of it.
#
#   :11-16 filter_visible_devices PORTED  `vis.*` -- the index-string parser
#   :18-48 FileIOInterface        FFI     open/close/ioctl/mmap/read/write.
#                                              :37's `-1` mmap sentinel and :43-48's
#                                              three statics are the trace
#   :50-51 the mmap constants     PORTED  `MAP_*` -- both directions, per PLATFORM
#   :53    ipv4_to_gid            PORTED  `gid.*` -- 16 bytes of multicast group
#   :56-59 write_sysfs            PORTED  `sysfs.*` + `sysfs.wrote` -- the `sudo`
#                                               STRING
#   :61-65 atomic_lib / libsys    PORTED  `cap.*` -- the PLATFORM gate, which is
#                                               `cap.barrier_lib`'s `osx`
#   :67-70 pagemap                PORTED  `sys.pagemap`
#   :72-82 vfio                   PORTED  `pci.probe.vfio` -- its `except OSError:
#                                               None`
#   :84-87 reserve_va             PORTED  `sys.reserve_va` -- the CACHE negative case
#   :89    memory_barrier         PORTED  `cap.barrier_lib` -- which library is
#                                               consulted
#   :91-92 lock_memory            PORTED  `sys.lock_memory` -- the refusal
#   :94-96 system_paddrs          PARTIAL `paddr.*` -- the mask; the u64 read is FFI
#   :98-102 alloc_sysmem          PORTED  `sys.alloc_sysmem` -- the flag arithmetic
#   :104-126 pci_scan_bus         PORTED  `scan.*` -- the mask filter + both id formats
#   :128-136 list_devices/probe   PORTED  `pci.probe.*`
#   :138-186 pci_setup_usb_bars   PORTED  `bars.*` -- THE HEADLINE. 7 ordered writes,
#                                               the REBAR control, the BAR sizing
#   :188-200 flock_acquire        WALL   the `fcntl.flock` call itself is the
#                                               seam; the two open-flag sets are
#                                               constants
#   :206-268 PCIDevice            PORTED  `pci.*` -- the sysfs path table, the open
#                                               flags, bar_info, read/write_config,
#                                               resize_bar, map_bar
#   :270-290 USBPCIDevice         PORTED  `usb.*` -- the constants and the DMA window
#   :292-293 PCIAllocationMeta    PORTED  `Meta.*` -- field order and names
#   :295-355 PCIIfaceBase         PORTED  `face.*` -- peer_group, is_bar_small, the
#                                               alloc size ladder, map()'s refusals
#   :359-363 RemoteCmd            PORTED  `Rcmd.*` -- 16 names, both directions,
#                                               REMOTE_REQ/REMOTE_RESP field order
#   :365-383 RemoteMMIOInterface  PORTED  `rmm.*` -- the element-size table
#   :385-452 RemotePCIDevice      PORTED  `rpc.*` -- the pad-to-3 rule, the REMOTE
#                                               parser, the socket-option table
#   :454   the MOCK swap          FFI     DEV.interface, a module rebind
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# 1. THE u64 WALL, and it is three Python lines and one struct format.
#      :96   `[(x & ((1<<55)-1)) * mmap.PAGESIZE for x in array.array('Q', ...)]`
#      :175  `((~(((hi << 32) | lo) & ~0xf)) + 1) & (0xffff... if bar_64 else ...)`
#      :448  `struct.unpack('<Q', data)[0]`
#    The PAGEFRAME entry, the 64-bit BAR size and the remote bar's host address
#    are all 64-bit. `base.bend` exports `Word`, not `Word(64n)`, so the port
#    computes the 32-bit half and carries the high word in an `H.I64` where a
#    value is only ever PRINTED. `paddr.mask` is the one piece that fits in 32
#    bits, and it is the one the whole expression hangs on: `(1<<55)-1` is
#    36028797018963967, which has no `U32` image at all. The port splits it
#    (`paddr.mask_hi = 0x7ffffff`, `paddr.mask_lo = 0xffffffff`) and gates BOTH
#    halves against CPython, because a mask with one wrong half selects the wrong
#    physical pages and nothing else notices.
#    TODO(p3) runtime/support/system.py:96  -- the u64 pagemap read.
#    TODO(p3) runtime/support/system.py:175 -- the u64 BAR size.
#    TODO(p3) runtime/support/system.py:448 -- `struct.unpack('<Q', data)[0]`.
#
# 2. THE SYSCALL STRINGS, :58/:75/:198/:247. `os.system` takes ONE string and
#    hands it to `/bin/sh`, so these four are the whole of what a shell sees. A
#    dropped quote or a dropped path is a `sudo` that writes the wrong file, and
#    it is silent. `sysfs.echo` and `pci.resize_path` build them, and the gate
#    DIFFS
#    THE STRING BESIDE CPYTHON'S -- a boolean about a string proves nothing,
#    because `String.concat` will happily drop a literal and still make two
#    strings that differ agree on a length.
#    TODO(p3) runtime/support/system.py:58  -- `os.system(cmd)`.
#    TODO(p3) runtime/support/system.py:75  -- `os.system("sudo modprobe ...")`.
#    TODO(p3) runtime/support/system.py:198 -- `os.system("sudo lsof ...")`, in a message.
#    TODO(p3) runtime/support/system.py:247 -- `os.system(...)`, in `PCIDevice.reset`.
#
# 3. THE CTYPES LIBRARY GATE, :61-65 and :89. `atomic_lib` is
#    `ctypes.CDLL(ctypes.util.find_library('atomic')) if sys.platform == "linux"
#    else None` and `libsys` has NO such gate. So the two libraries are NOT
#    symmetric, and `memory_barrier`'s `self.libsys if OSX else self.atomic_lib`
#    is a SECOND, different predicate over the same two facts -- one per
#    platform, and the two do not agree. That is the whole branching story at
#    :89 and it is pure, so it is ported as `cap.barrier_lib`, and the gate asks
#    the question twice: which library, and whether it is a real fence at all.
#    `ctypes.CDLL` and `find_library` are the FFI and are the trace.
#    TODO(p3) runtime/support/system.py:62 -- `ctypes.CDLL(find_library('atomic'))`.
#    TODO(p3) runtime/support/system.py:65 -- `ctypes.CDLL(find_library("System"))`.
#    TODO(p3) runtime/support/system.py:89 -- `lib.atomic_thread_fence(5)`.
#
# 4. THE OSX PROPERTY READ, :108-112. `read_prop` is CoreFoundation: a CFString
#    key, a `CFDataRef`, an 8-byte `c_uint8` buffer and `int.from_bytes(...,
#    "little")`. It is four ctypes calls and a cast chain, and the ONLY part of it
#    that is this file's own logic is the 8-byte little-endian read, which
#    `pci.read_prop` ports. Everything above it is CoreFoundation, so the whole
#    `OSX` half of `pci_scan_bus` is FFI and only the LINUX half is a trace.
#    TODO(p3) runtime/support/system.py:108 -- the ctypes cast chain.
#    TODO(p3) runtime/support/system.py:110 -- `IORegistryEntryCreateCFProperty`.
#    TODO(p3) runtime/support/system.py:111 -- `CFDataGetBytes` into `(c_uint8*8)()`.
#
# WHAT IS FFI, WHOLE. Stated once so the short file is not read as a short port:
# `FileIOInterface` (:18-48) is a file descriptor and nothing else; `libc.mmap`
# and `libc.munmap` (:36/:42) are two symbols; `libc.mlock` (:92) is one; the
# `ctypes` library loads (:62/:65) are two; `os.umask` (:191), `fcntl.flock`
# (:197), `os.open` (:194/:195), `os.close` (:23), `os.lseek` (:33),
# `os.listdir` (:32), `os.readlink` (:46), `os.path.exists` (:44),
# `os.eventfd` (:48) and `fcntl.ioctl` (:24) are one call each;
# `mmap.madvise` (:263) is one; `select.poll` (:234-235) is two; the `vfio.*`
# ctypes structs (:79/:228/:230/:231/:237-239) are a ctypes packing of
# `struct_vfio_irq_set` and belong to `autogen.py`; `socket.create_connection`
# and the five `setsockopt` calls (:391-393) are a socket; `_recvall`'s
# `sock.recv` loop (:410-415) is a socket; `struct.pack`/`struct.unpack` (:239,
# :374, :378, :418, :424, :426, :437, :448) are byte layout and are FFI, EXCEPT
# the two rules they are driven by -- `elemsize` (:370) and `post_args` (:418) --
# which are this file's own arithmetic and are ported and gated; and
# `BumpAllocator`, `MMIOInterface`, `VirtMapping` and `AddrSpace` are
# `support/memory.py`, `CustomASM24Controller` and `USB3` are `support/usb.py`,
# `PCIDevice`/`RemotePCIDevice` are consumed by `ops_amd.py` and the other
# devices. None of those is invented here.
import Base
import ../../helpers.bend as H

# ===========================================================================
# THE CONSTANTS. EVERY one of these was READ OUT OF A LIVE CPYTHON by
# `.agents/slop/oracle-system.py`; none is transcribed. Where a value is
# PLATFORM-DEPENDENT it is a def OF the platform flag, not a constant, and
# `cap.barrier_lib` takes the platform as an argument and the fixture drives
# both arms.
#
# BEND HAS NO HEX LITERALS (bend2-constraints.md, position 6835), so every
# constant below is decimal. The comment gives the hex so a reader can check it
# against the source without a converter.
# ===========================================================================

# --- the mmap family, :50-51 -------------------------------------------------
# `MAP_FIXED, MAP_FIXED_NOREPLACE = 0x10, 0x100000` -- spelled as LITERALS in
# Python, not read from `mmap`, because `mmap.MAP_FIXED` is ABSENT on macOS.
# MEASURED: `mmap.MAP_FIXED` -> AttributeError on this host.
def MAP_FIXED() -> U32: 16                        # 0x10
def MAP_FIXED_NOREPLACE() -> U32: 1048576          # 0x100000
def MAP_NORESERVE() -> U32: 1024                   # 0x400  -- a LITERAL in Python too

# `MAP_LOCKED, MAP_POPULATE, MAP_NORESERVE = 0 if OSX else 0x2000,
#  getattr(mmap, "MAP_POPULATE", 0 if OSX else 0x008000), 0x400`
#
# TWO PLATFORM-DEPENDENT CONSTANTS IN ONE LINE, and they are the `has_`/`is_`
# kind of test the brief asks for: MAP_LOCKED is 0 on OSX and 0x2000 elsewhere;
# MAP_POPULATE is 0 on OSX and 0x008000 elsewhere -- but by a DIFFERENT route, the
# `getattr` default rather than the ternary. `mmap.MAP_POPULATE` exists on Linux
# and is 0x8000 there, so the two spellings agree on Linux and only the mechanism
# differs. The port keeps the mechanism as `cap.populate_from` so the gate can
# ask WHICH arm answered.
# `mmap.MAP_ANONYMOUS` IS A THIRD PLATFORM-DEPENDENT CONSTANT, and this is the one
# that bit hardest: it is 0x20 (32) on Linux and 0x1000 (4096) on macOS. My first
# cut took the HOST's value, which put 0x1000 into `VA_FLAGS` and made
# `sy_va_flags` off by 3968 on every platform the port actually targets.
# MEASURED: `mmap.MAP_ANONYMOUS` -> 4096 here, and the source's own Linux OR is
# 0x100422, which is 2 | 0x20 | 0x400 | 0x100000 and NOT 2 | 0x1000 | ...
def MAP_ANONYMOUS_OSX() -> U32: 4096                # 0x1000
def MAP_ANONYMOUS_LINUX() -> U32: 32               # 0x20
def MAP_SHARED() -> U32: 1                         # 0x1  -- the same on both
def MAP_PRIVATE() -> U32: 2                        # 0x2  -- the same on both
def PROT_READ() -> U32: 1                          # 0x1
def PROT_WRITE() -> U32: 2                         # 0x2
def PROT_RW() -> U32: 3                            # 0x3  -- PROT_READ|PROT_WRITE, :101/:263

# the two platform answers, in BOTH directions: `osx` is the flag, and
# `cap.locked_of` / `cap.populate_of` are the ternary and the getattr.
def CAP_YES() -> U32: 1
def CAP_NO() -> U32: 0
def CAP_MMAP() -> U32: 1                           # `mmap.MAP_POPULATE` EXISTS
def CAP_GETATTR() -> U32: 2                        # the `getattr` default answered

def CAP_LOCKED_OSX() -> U32: 0
def CAP_LOCKED_LINUX() -> U32: 8192               # 0x2000
def CAP_POPULATE_OSX() -> U32: 0
def CAP_POPULATE_LINUX() -> U32: 32768             # 0x8000

def cap.locked_of(osx: U32) -> U32:
  Bool.pick(U32, U32.is_eq(osx, CAP_YES()), CAP_LOCKED_OSX(), CAP_LOCKED_LINUX())

def cap.populate_of(osx: U32) -> U32:
  Bool.pick(U32, U32.is_eq(osx, CAP_YES()), CAP_POPULATE_OSX(), CAP_POPULATE_LINUX())

# WHICH arm answered :51's `getattr`. This is the part the two spellings share
# and the part a reader would get wrong: MAP_LOCKED is a plain ternary, and
# MAP_POPULATE asks `mmap` first. `cap.populate_from` is the answer the gate
# checks, and it is a TABLE ROW rather than an inference from the value, because
# on Linux the value is 0x8000 either way and only the table says why.
def cap.populate_from(osx: U32) -> U32:
  Bool.pick(U32, U32.is_eq(osx, CAP_YES()), CAP_GETATTR(), CAP_MMAP())

# `mmap.MAP_HUGETLB` is ABSENT on macOS, which is why :100 reaches for
# `libc.MAP_HUGETLB` instead. MEASURED: `mmap.MAP_HUGETLB` -> AttributeError here.
def MAP_HUGETLB() -> U32: 262144                    # 0x40000
def MADV_DONTFORK() -> U32: 10                     # 0xa -- libc.MADV_DONTFORK

# --- the os open flags, :19/:211/:242/:256 ----------------------------------
def O_RDONLY() -> U32: 0
def O_WRONLY() -> U32: 1
def O_RDWR() -> U32: 2
def O_SYNC() -> U32: 128                           # 0x80
def O_CLOEXEC() -> U32: 16777216                   # 0x40000
def O_RDWR_SYNC_CLOEXEC() -> U32: 16777346         # 0x40002  -- os.O_RDWR|O_SYNC|O_CLOEXEC
def O_RDWR_CREAT_CLOEXEC() -> U32: 16777730        # 0x40006  -- os.O_RDWR|O_CREAT|O_CLOEXEC

# --- the fcntl lock flags, :197 ---------------------------------------------
def LOCK_EX() -> U32: 2
def LOCK_NB() -> U32: 4
def LOCK_EX_NB() -> U32: 6                         # LOCK_EX | LOCK_NB
def LOCK_MODE() -> U32: 438                        # 0o666 -- the umask(0) mode

# --- the PCI config register NUMBERS, :142-185 -----------------------------
# READ OUT OF `tinygrad/runtime/autogen/pci.py` by the oracle. These are OFFSETS
# in the 256-byte config space, and :165 adds `bar_off` to one of them.
def PCI_COMMAND() -> U32: 4
def PCI_STATUS() -> U32: 6
def PCI_BASE_ADDRESS_0() -> U32: 16                # 0x10
def PCI_PRIMARY_BUS() -> U32: 24                   # 0x18
def PCI_MEMORY_BASE() -> U32: 32                   # 0x20
def PCI_MEMORY_LIMIT() -> U32: 34                  # 0x22
def PCI_PREF_MEMORY_BASE() -> U32: 36              # 0x24
def PCI_PREF_MEMORY_LIMIT() -> U32: 38             # 0x26
def PCI_PREF_BASE_UPPER32() -> U32: 40             # 0x28
def PCI_PREF_LIMIT_UPPER32() -> U32: 44            # 0x2c
def PCI_COMMAND_IO() -> U32: 1
def PCI_COMMAND_MEMORY() -> U32: 2
def PCI_COMMAND_MASTER() -> U32: 4
def PCI_COMMAND_ALL() -> U32: 7                    # IO | MEMORY | MASTER, :151/:185
def PCI_EXT_CAP_ID_REBAR() -> U32: 21              # 0x15
def PCI_BASE_ADDRESS_SPACE() -> U32: 1
def PCI_BASE_ADDRESS_MEM_TYPE_64() -> U32: 4
def PCI_BASE_ADDRESS_MEM_PREFETCH() -> U32: 8

# --- the two iokit/vfio/atomic constants that are just numbers --------------
def VFIO_NOIOMMU_IOMMU() -> U32: 8
def VFIO_PCI_MSI_IRQ_INDEX() -> U32: 1
def ATOMIC_SEQ_CST() -> U32: 5                     # `__ATOMIC_SEQ_CST:=5`, :89
def PCI_CLASS_SHIFT() -> U32: 16                   # `>> 16`, :116/:122
# (1<<55)-1 == 0x7FFFFFFFFFFFFF, so the HIGH word is 0x7FFFFF == 8388607 and not
# 0x7FFFFFF. I wrote 134217727 (0x7FFFFFF) -- one hex digit too many -- and the
# oracle caught it before a row existed to agree with it. A mask with one wrong
# half selects the wrong physical pages and nothing else in the file notices.
def PAGEFRAME_MASK_HI() -> U32: 8388607            # 0x7fffff  -- (1<<55)-1, high word
def PAGEFRAME_MASK_LO() -> U32: 4294967295         # 0xffffffff -- (1<<55)-1, low word
def SMALL_BAR() -> U32: 268435456                  # (256 << 20), :300
def HUGE_LO() -> U32: 2097152                      # (2 << 20) -- the contiguous cap :99
def PAGESIZE_LINUX() -> U32: 4096                  # 0x1000 -- Linux mmap.PAGESIZE
def TWO_MB() -> U32: 2097152                       # 2 << 20  -- the 2MB align, :181/:315
def EIGHT_MB() -> U32: 8388608                     # 8 << 20  -- the ladder's threshold :315
def FOUR_KB() -> U32: 4096                         # 4 << 10  -- the ladder's floor :315
def PAGE_4K() -> U32: 4096                         # 0x1000 -- the page-align refusals :339
def IOMEM_SLOT() -> U32: 4096                      # 0x1000 -- the `(paddr, 0x1000)` pair

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE OS call. `k` is the syscall, `arg` is the ONE argument this file's gate
# reads for it, and `s` is the STRING the call was handed -- a path, a `sudo`
# line, or "" for a call with no string. `s` exists because the strings in this
# file are the load-bearing part and a `U32` slot cannot carry them: WALL 2 says a
# boolean about a string proves nothing, and the same is true of an integer about
# a string.
#
# THE ORDER OF `k` IS THE ORDER OF THE TABLE, and `sys.call_names` is that table
# so a reader can read a trace without the source.
type Call is Data:
  Call{k: U32, arg: U32, s: String}

# The OS state. Bend has no pointer and no module-level state, so the singleton
# `System = _System()` at :202 becomes a threaded `Tr`; there is exactly one per
# process either way. `reserved` is the `functools.cache` at :85 -- the set of
# (va_start) values already mapped, which is what makes the NEGATIVE case at
# :87 observable, and `have_lib` is the `functools.cached_property` at :61/:64.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, reserved: List<&2, U32>,
     have_atomic: Bool, have_sys: Bool, refused: Bool}

# :13 the ids `filter_visible_devices` produced. A `List` rather than a range,
# because `3-1` produces an EMPTY list and not an error (:16's `if ids else devs`
# is what turns that into "no filter"), and an empty range and a failed parse are
# the same thing here.
type Ids is Data:
  Ids{n: U32, ids: List<&2, U32>}

# ONE `usb.pcie_cfg_req` call, :142-185. THE FIELD ORDER IS `USB3`/`CustomASM24Controller`'s
# SIGNATURE, read out of `usb.py:137` by the oracle:
#
#   (self, byte_addr: int, bus: int = 1, dev: int = 0, fn: int = 0,
#        value: int | None = None, size: int = 4)
#
# `byte_addr` is the only POSITIONAL argument and every call in this file passes
# it positionally; `bus`, `dev`, `fn`, `value` and `size` are KEYWORDS. So the
# order above is not a guess at a struct layout, it is the callee's own parameter
# order, and a swap of two of these fields is a silently wrong register write.
# `is_write` is `value is not None` -- the flag that separates the four READS from
# the eleven WRITES, and it is what :169/:170/:173 need to know.
type Cfg is Data:
  Cfg{byte_addr: U32, bus: U32, dev: U32, fn: U32, value: U32, size: U32,
      is_write: Bool}

# `PCIAllocationMeta`, :292-293. `@dataclasses.dataclass class PCIAllocationMeta:
# mapping:VirtMapping; has_cpu_mapping:bool; hMemory:int=0`.
# THE THREE FIELDS IN THIS ORDER, and the third one DEFAULTED. The port carries
# no `VirtMapping` -- that is `support/memory.py` -- so `hMemory` and a Bool are
# all that survive, and `Meta.of` is the two sites that build one: :321
# `PCIAllocationMeta(mapping, has_cpu_mapping=True, hMemory=paddrs[0])` and :325
# `PCIAllocationMeta(mapping, cpu_access, hMemory=mapping.paddrs[0][0])`.
# The two differ in a way that is easy to get wrong: :321's second field is the
# LITERAL True and :325's is the `cpu_access` ARGUMENT. `Meta.of` takes the
# argument and `Meta.has_cpu_mapping` passes True, so the port is a def of the
# call site, not a def of the dataclass.
type Meta is Data:
  Meta{has_cpu_mapping: Bool, hMemory: U32}

# `PCIIfaceBase`, :295-355, only the four fields this file's own logic reads.
type Face is Data:
  Face{peer_group: String, vram_bar: U32, bar_size: U32, remote: Bool}

# The read-only part of a PCI config space, handed in as a fixture: the 256-byte
# image the port reads registers out of, one `U32` per dword. The seam fills it;
# `pci.read_prop` and the BAR loop are pure over it.
type CfgSp is Data:
  CfgSp{words: List<&2, U32>}

# `a match` cannot scrutinise a COMPUTED value, so the `List.get` gets its own
# LEAF and the `match` reads the `Maybe` it returns. A dword past the end is 0,
# which is what a zeroed 256-byte config space spells.
def CfgSp.maybe(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

def CfgSp.at(ws: List<&2, U32>, dword: U32) -> U32:
  CfgSp.maybe(List.get(&2, U32, ws, U32.to_nat(dword)))

def CfgSp.at32(s: CfgSp, dword: U32) -> U32:
  match s:
    case CfgSp{+words}: CfgSp.at(words, dword)

def CfgSp.of(ws: List<&2, U32>) -> CfgSp: CfgSp{ws}

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every OS call goes through it, so the trace is
# the ordered list of syscalls the C runtime will make.
#
# THE RAISE. `Tr.emit` and `Tr.emit.stop` record NOTHING once `refused` is set.
#
# MEASURED BLIND SPOT. Dropping the `refused` guard from `Tr.emit.go` (M42) moves NO
# ROW, and the reason is structural rather than a coverage gap: no def in this file
# emits after a refusal, because every truncation is produced by the CALLER's
# `Bool.pick` -- `sysfs.raise` calls `Tr.fail` on a trace whose last call it just
# emitted, and `Tr.emit.stop` fails on the call it emits. So the guard is
# defence-in-depth that Python's control flow never reaches. It is kept because a
# future def that emits after a refusal needs it, and it is REPORTED rather than
# closed with a row that asserts the guard's own behaviour.
# That is the port of every `raise` and every `assert` in the file -- :15's
# visibility assert, :37's mmap failure, :59's re-read failure, :92's mlock, :99's
# contiguous cap, :120's "no pcie", :135's IndexError, :198's flock, :212's
# PermissionError, :216's bound driver, :268's resize -- and it is why no step
# below needs a guard of its own. A refusal shows up as a TRUNCATION.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, Nil{}, False{}, False{}, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}: calls

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}: refused

def Tr.have_atomic(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}: have_atomic

def Tr.have_sys(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}: have_sys

def Tr.reserved(t: Tr) -> List<&2, U32>:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}: reserved

def Tr.fail(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}:
      Tr{calls, next, reserved, have_atomic, have_sys, True{}}

def Tr.set_atomic(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}:
      Tr{calls, next, reserved, True{}, have_sys, refused}

def Tr.set_sys(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}:
      Tr{calls, next, reserved, have_atomic, True{}, refused}

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: match t: case Tr{_, next, _, _, _, _}: next

# `Bool.pick` evaluates BOTH arms, so the appended call is a value built here and
# the guard is a parameter. This is the port's `raise`.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, s: String,
               +calls: List<&2, Call>, +next: U32, reserved: List<&2, U32>,
               have_atomic: Bool, have_sys: Bool) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg, s}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)),
     reserved, have_atomic, have_sys, refused}

def Tr.emit(k: U32, arg: U32, s: String, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}:
      Tr.emit.go(refused, k, arg, s, calls, next, reserved, have_atomic, have_sys)

# emit AND THEN REFUSE -- the shape of every `assert` and every `raise` that
# follows a call: the call happened (:15 checks `ids` AFTER parsing, :216 checks
# the driver AFTER unbinding, :268 writes THEN discovers the size is wrong).
def Tr.emit.stop(k: U32, arg: U32, s: String, t: Tr) -> Tr:
  Tr.fail(Tr.emit(k, arg, s, t))

# ===========================================================================
# THE CALL TABLE. One row per kind of OS call this file makes, and the names are
# the ones a reader of the trace needs. `sys.call_name` is the REVERSE direction
# and `sys.call_of` the forward one, so a wrong `k` in a def is visible as a
# name that is not in the table.
# ===========================================================================

def CALL_OPEN() -> U32: 0
def CALL_CLOSE() -> U32: 1
def CALL_MMAP() -> U32: 2
def CALL_MUNMAP() -> U32: 3
def CALL_SYSTEM() -> U32: 4
def CALL_MLOCK() -> U32: 5
def CALL_FLOCK() -> U32: 6
def CALL_UMASK() -> U32: 7
def CALL_READLINK() -> U32: 8
def CALL_EXISTS() -> U32: 9
def CALL_LISTDIR() -> U32: 10
def CALL_SEEK() -> U32: 11
def CALL_READ() -> U32: 12
def CALL_WRITE() -> U32: 13
def CALL_EVENTFD() -> U32: 14
def CALL_SELECT_REGISTER() -> U32: 15
def CALL_MLOCK_OK() -> U32: 16
def CALL_MADVISE() -> U32: 17
def CALL_CDLL() -> U32: 18
def CALL_FENCE() -> U32: 19
def CALL_POLL() -> U32: 20
def CALL_IOCTL() -> U32: 21
def CALL_VFIO_CHECK_EXT() -> U32: 22
def CALL_VFIO_SET_CONTAINER() -> U32: 23
def CALL_VFIO_SET_IOMMU() -> U32: 24
def CALL_VFIO_GET_DEVICE_FD() -> U32: 25
def CALL_VFIO_SET_IRQS() -> U32: 26
def CALL_CONNECT() -> U32: 27
def CALL_SETSOCKOPT() -> U32: 28
def CALL_SEND() -> U32: 29
def CALL_RECV() -> U32: 30
def CALL_POLLER() -> U32: 31
def CALL_RESOLVE() -> U32: 32
def CALL_NCALLS() -> U32: 33

def sys.call_names() -> List<&2, String>:
  ["open", "close", "mmap", "munmap", "system", "mlock", "flock", "umask",
   "readlink", "exists", "listdir", "seek", "read", "write", "eventfd",
   "select.register", "mlock.ok", "madvise", "cdll", "fence", "poll",
   "ioctl", "vfio.check_extension", "vfio.set_container", "vfio.set_iommu",
   "vfio.get_device_fd", "vfio.set_irqs", "connect", "setsockopt", "send",
   "recv", "poller", "resolve", "ncalls"]

# forward: the index, so a def that picks a `k` cannot pick one that is not a call
def sys.call_of(s: String) -> U32:
  match s:
    case "open": CALL_OPEN()
    case "close": CALL_CLOSE()
    case "mmap": CALL_MMAP()
    case "munmap": CALL_MUNMAP()
    case "system": CALL_SYSTEM()
    case "mlock": CALL_MLOCK()
    case "flock": CALL_FLOCK()
    case "umask": CALL_UMASK()
    case "readlink": CALL_READLINK()
    case "exists": CALL_EXISTS()
    case "listdir": CALL_LISTDIR()
    case "seek": CALL_SEEK()
    case "read": CALL_READ()
    case "write": CALL_WRITE()
    case "eventfd": CALL_EVENTFD()
    case "select.register": CALL_SELECT_REGISTER()
    case "mlock.ok": CALL_MLOCK_OK()
    case "madvise": CALL_MADVISE()
    case "cdll": CALL_CDLL()
    case "fence": CALL_FENCE()
    case "poll": CALL_POLL()
    case "ioctl": CALL_IOCTL()
    case "vfio.check_extension": CALL_VFIO_CHECK_EXT()
    case "vfio.set_container": CALL_VFIO_SET_CONTAINER()
    case "vfio.set_iommu": CALL_VFIO_SET_IOMMU()
    case "vfio.get_device_fd": CALL_VFIO_GET_DEVICE_FD()
    case "vfio.set_irqs": CALL_VFIO_SET_IRQS()
    case "connect": CALL_CONNECT()
    case "setsockopt": CALL_SETSOCKOPT()
    case "send": CALL_SEND()
    case "recv": CALL_RECV()
    case "poller": CALL_POLLER()
    case "resolve": CALL_RESOLVE()
    case _: CALL_NCALLS()

# reverse: a `got` accumulator and not a two-list walk, because the names are
# unique, so "the last hit" is "the only hit". The key is the INDEX, and the
# index is a `U32` turned into a `String` for the comparison -- a `U32`-to-
# `String` conversion that does not exist, so the walk compares the INDEXES and
# `sys.call_name` indexes the list with the index it found. The value
# direction and the name direction therefore cannot disagree: both read
# `sys.call_names()`.
def sys.call_name.put(k: U32, +at: U32, got: U32) -> U32:
  Bool.pick(U32, U32.is_eq(at, k), at, got)

def sys.call_name.go(n: Nat, +k: U32, ns: List<&2, String>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ns:
        case Nil{}: got
        case _h <> t:
          +nxt = U32.add(at, 1)
          sys.call_name.go(m, k, t, nxt, sys.call_name.put(k, nxt, got))

def sys.call_name.maybe(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "?"

def sys.call_name.at(ns: List<&2, String>, i: U32) -> String:
  sys.call_name.maybe(List.get(&2, String, ns, U32.to_nat(i)))

def sys.call_name(k: U32) -> String:
  sys.call_name.at(sys.call_names(), sys.call_name.go(
    List.length(&2, String, sys.call_names()), k, sys.call_names(), 0, 0))

# ===========================================================================
# READING THE TRACE.
# ===========================================================================

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg, s}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg, s}: arg

def Call.s(c: Call) -> String:
  match c:
    case Call{k, arg, s}: s

# the `Tr.args` family, LEAF-ONLY, because `Bool.pick` evaluates both arms and a
# recursive call inside one of them would branch the walk twice over.
def Tr.put(+c: Call, k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case c <> t: Tr.args.go(m, k, t, Tr.put(c, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

# and the same for the STRINGS, which is the half that WALL 2 needs: a call's
# `sudo` line, read back as text and diffed against CPython's.
def Tr.puts(+c: Call, k: U32, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(Call.k(c), k),
    List.append(&2, String, acc, [Call.s(c)]), acc)

def Tr.strs.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case c <> t: Tr.strs.go(m, k, t, Tr.puts(c, k, acc))

def Tr.strs(k: U32, +cs: List<&2, Call>) -> List<&2, String>:
  Tr.strs.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case c <> t: Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(Call.k(c), k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# does the trace CONTAIN this (kind, arg, string) sequence, in order? `at` is how
# much of the pattern is matched so far, read out of the pattern BY INDEX rather
# than carried as a second list: the head and the tail of ONE destructure share a
# binder, and a descent may not use that binder twice.
#
# THE FUEL IS THE TRACE LENGTH AND THE ANSWER IS `at == patlen`. With the fuel set
# to the PATTERN length, `case 0n:` fires after patlen trace entries and returns
# `True{}` without ever reading `at`, so a reversed pattern matches and so does a
# pattern element that never occurs. MEASURED in `ops_webgpu.bend`, and the
# matcher is copied from the fixed one.
def Tr.same(k1: U32, k2: U32, a1: U32, a2: U32, s1: String, s2: String) -> Bool:
  Bool.and(Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2)), String.eq(s1, s2))

# `at` is read by the guard and by both `pick` arms, so the arms share ONE `+nxt`
# binding instead of each computing the add -- a `Bool.pick` evaluates both.
def Tr.step.pick(+at: Nat, same: Bool) -> Nat:
  Bool.pick(Nat, same, Nat.add(at, 1n), at)

# `at` is a COUNT of matched elements and NOT a fuel to split on. My first version
# matched on it and returned `at + 1` for the `0n` arm WITHOUT COMPARING, so
# `Tr.has` said True for a pattern element that never occurred -- `sy_has_absent`,
# `sy_has_wrong_arg` and `sy_has_wrong_str` were all True and the whole matcher was
# unfalsifiable. Found by asking for the negative rows, not by the mutation table.
def Tr.step.at(+c: Call, +want: Call, +at: Nat) -> Nat:
  Tr.step.pick(at, Tr.same(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want),
                           Call.s(c), Call.s(want)))

def Tr.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}: Tr.step.at(c, want, at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case c <> t: Tr.has.go(m, patlen, t, pat, Tr.step(List.get(&2, Call, pat, at), c, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)

def str_eq.go(a: List<&2, String>, b: List<&2, String>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case x <> t:
      match b:
        case Nil{}: False{}
        case y <> u: str_eq.go(t, u, Bool.or(bad, Bool.not(String.eq(x, y))))

def str_list_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, String, a)),
                     U32.from_nat(List.length(&2, String, b))), str_eq.go(a, b, False{}))

# ===========================================================================
# THE ROW PRIMITIVES. `row` prints `name=value` and the mutation harness diffs
# WHOLE LINES, never row names -- a name-diff harness measures only additions and
# removals, and every mutation in this file changes a VALUE.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# a comma-joined U32 list, in list order. `List.append` is `xs ++ ys`, so this
# fold APPENDS and must not reverse at the end.
def ush.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush.go(t, List.append(&2, String, acc, [U32.show(x)]))

def ush(xs: List<&2, U32>) -> List<&2, String>: ush.go(xs, Nil{})

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs), ",")]))

def sxs(xs: List<&2, String>) -> String: String.join(xs, ",")

# `H.List.head` does not exist in this tree's helpers, so the first element of a
# trace argument list gets its own leaf. `sy_*_arg` rows read a single value and a
# leaf here is what keeps them from having to name the whole list.
def head_u32(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

def first_arg(k: U32, +cs: List<&2, Call>) -> U32: head_u32(List.get(&2, U32, Tr.args(k, cs), 0n))

# ===========================================================================
# A BOUNDED `%x`. WALL-FREE, and the bound is written down because it IS the
# claim: `hx.d4` is exactly four digits and `hx.q` DROPS the leading zeros with an
# ARITHMETIC digit count, because a per-character strip has no base case a `match`
# can name (bend2-constraints.md, position 6880). Everything here is under 65536,
# which is true of every vendor id and device id in this file (:117's `f"{v:x}:{d:x}"`).
# ===========================================================================

def hx.digit.pick(+v: U32, dec: Bool) -> String:
  Bool.pick(String, dec, String.from_list([Char.from_u32(U32.add(48, v))]),
    String.from_list([Char.from_u32(U32.add(87, v))]))

def hx.digit(+v: U32) -> String: hx.digit.pick(v, U32.is_lt(v, 10))

def hx.d2.pick(+hi: U32, +lo: U32) -> String:
  String.concat([hx.digit(hi), hx.digit(lo)])

def hx.d2(+v: U32) -> String: hx.d2.pick(U32.shrn(v, 4n), U32.and(v, 15))

def hx.d4.pick(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  String.concat([hx.digit(a), hx.digit(b), hx.digit(c), hx.digit(d)])

def hx.d4(+v: U32) -> String:
  hx.d4.pick(U32.shrn(v, 12n), U32.and(U32.shrn(v, 8n), 15),
             U32.and(U32.shrn(v, 4n), 15), U32.and(v, 15))

# the digit count, arithmetically: 1 below 16, 2 below 256, 3 below 4096, 4 below.
#
# THREE DISTINCT PREDICATES AND THREE DISTINCT ARMS. My first version passed the
# `v < 16` test to BOTH inner picks, so anything from 256 up answered 4 and
# `hx.q(0x7f00)` printed "f00" instead of "7f00" -- and the `sy_gid_*` rows, which
# are the twelve-byte prefix plus two `%x` tails, were wrong in the tail. A ladder
# is not a two-way pick.
def hx.width.p1(+a: Bool, +b: Bool, +c: Bool) -> U32:
  Bool.pick(U32, a, 1, Bool.pick(U32, b, 2, Bool.pick(U32, c, 3, 4)))

def hx.width(+v: U32) -> U32: hx.width.p1(U32.is_lt(v, 16), U32.is_lt(v, 256), U32.is_lt(v, 4096))

# `%x`: the four-digit form minus its leading zeros. `String.drop` removes the
# FIRST n, which is the direction this needs.
def hx.q.pick(+s: String, n: U32) -> String: String.drop(s, U32.to_nat(n))

def hx.q(+v: U32) -> String: hx.q.pick(hx.d4(v), U32.sub(4, hx.width(v)))

# ===========================================================================
# :53 -- `ipv4_to_gid`, `bytes(10) + b'\xff\xff' + socket.inet_aton(ip)`.
#
# SIXTEEN BYTES, and the first twelve are the file's own and the last four are
# `inet_aton`'s. The first cut of this port's header said THIRTEEN, from reading
# the expression as 10 + 2 + 1; MEASURED, it is 16, and the twelve-byte PREFIX is
# `00 00 00 00 00 00 00 00 00 00 ff ff`.
#
# WALL: `inet_aton` itself. A dotted-quad to four bytes needs a `String.split` and
# a `String.strip`, and neither exists. So the port builds the PREFIX and takes the
# four tail bytes as the seam's, and `gid.of` takes them as TWO arguments and does
# not concat a tail it built itself -- a port that appended them in the wrong order
# would still print 24 hex characters.
# TODO(p3) runtime/support/system.py:53 -- `socket.inet_aton(ip)`.
# ===========================================================================

def gid.PREFIX_HEX() -> String: "00000000000000000000ffff"
def gid.PREFIX_LEN() -> U32: 12
def gid.TAIL_LEN() -> U32: 4
def gid.len() -> U32: 16

# FOUR TAIL BYTES, so EIGHT hex digits, so two `hx.d4` and NOT two `hx.q`: `%x` is
# UNPADDED and a GID's tail is not. MEASURED: 127.0.0.1 gives
# '00000000000000000000ffff7f000001'.
def gid.of.p2(+hi: U32, +lo: U32) -> String:
  String.concat([gid.PREFIX_HEX(), hx.d4(hi), hx.d4(lo)])

def gid.of(+tail: U32) -> String: gid.of.p2(U32.shrn(tail, 16n), U32.and(tail, 65535))

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

def mapflag_names() -> List<&2, String>:
  ["MAP_ANONYMOUS", "MAP_SHARED", "MAP_PRIVATE", "MAP_FIXED",
   "MAP_FIXED_NOREPLACE", "MAP_LOCKED", "MAP_POPULATE", "MAP_NORESERVE",
   "PROT_READ", "PROT_WRITE", "PROT_RW", "MAP_HUGETLB", "MADV_DONTFORK"]

def mapflag_values() -> List<&2, U32>:
  [MAP_ANONYMOUS_OSX(), 1, 2, 16, 1048576,
   cap.locked_of(CAP_YES()), cap.populate_of(CAP_YES()), 1024,
   1, 2, 3, 262144, 10]

def mapflag_values_linux() -> List<&2, U32>:
  [MAP_ANONYMOUS_LINUX(), 1, 2, 16, 1048576,
   cap.locked_of(CAP_NO()), cap.populate_of(CAP_NO()), 1024,
   1, 2, 3, 262144, 10]

# the negative direction, which is the one that catches a wrong constant: a value
# that is NOT in the table answers 4294967295 -- the walk's initial value -- rather
# than a plausible neighbour. Without it a table whose comparison always matched
# would pass every name row.
def mapflag_missing() -> U32: 4294967295

# FIRST-HIT WINS, AND THAT IS **NOT** WHAT PYTHON DOES. `Bool.pick` was MEASURED to
# short-circuit on a term (a one-line fixture printing 1 for `f(1, [9,1,1,7], 0)`),
# so the walk stops at the first match. A Python dict comprehension,
# `{v: k for k, v in table}`, keeps the LAST. The mmap table is NOT injective --
# MAP_SHARED and PROT_READ are both 1, MAP_PRIVATE and PROT_WRITE are both 2, and on
# OSX MAP_LOCKED and MAP_POPULATE are both 0 -- so the two directions genuinely
# disagree on three pairs and `mapflag_of(1)` answers 1 (MAP_SHARED) where
# `flags_by_value()[1]` would answer 9 (PROT_READ).
#
# This file does not HAVE a Python dict comprehension to be faithful to -- :50-51
# spell the values as a tuple assignment and nothing in this file ever looks one up
# by value -- so the divergence costs nothing here. It is recorded because the next
# agent to reuse `mapflag_of` will assume the dict semantics, and because
# `Rcmd.of` and `elemsize` ARE injective and so are unaffected: for those two,
# first-hit and last-hit are THEOREMS and not measurements. `sy_flag_shared` is the
# row that pins the answer this port actually gives.
def mapflag_of.go(+v: U32, vs: List<&2, U32>, +at: U32) -> U32:
  match vs:
    case Nil{}: mapflag_missing()
    case x <> t:
      +nxt = U32.add(at, 1)
      Bool.pick(U32, U32.is_eq(v, x), at, mapflag_of.go(v, t, nxt))

def mapflag_of(v: U32) -> U32: mapflag_of.go(v, mapflag_values(), 0)

def mapflag_of_linux(v: U32) -> U32: mapflag_of.go(v, mapflag_values_linux(), 0)

def mapflag_name.maybe(m: Maybe<&2, String>) -> String:
  match m:
    case Some{g}: g
    case None{}: "?"

def mapflag_name.at(ns: List<&2, String>, i: U32) -> String:
  mapflag_name.maybe(List.get(&2, String, ns, U32.to_nat(i)))

def mapflag_name.pick(+i: U32) -> String:
  Bool.pick(String, U32.is_ge(i, U32.from_nat(List.length(&2, String, mapflag_names()))),
    "?", mapflag_name.at(mapflag_names(), i))

def mapflag_name(i: U32) -> String: mapflag_name.pick(i)

# ===========================================================================
# :11-16 -- `filter_visible_devices`, THE INDEX-STRING PARSER.
#
# `if '-' in (idstr:=DEV.target(device).indices)[1:]: ids = list(range(int(idstr.split('-')[0]),
#  int(idstr.split('-')[1])+1))` else `ids = [int(x) for x in idstr.split(',') if x.strip()]`
#
# THE `[1:]` IS THE WHOLE OF THE RANGE DETECTION and it is not decoration: a LEADING
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
def vis.count.pick(lo: U32, +hi: U32, empty: Bool) -> U32:
  Bool.pick(U32, empty, 0, U32.add(U32.sub(hi, lo), 1))

def vis.count(+lo: U32, +hi: U32) -> U32: vis.count.pick(lo, hi, U32.is_le(hi, lo))

# `lo, lo+1, ..., hi`. The `Nat` COUNTDOWN is the first argument and the value
# rides a second `+` that grows: `U32.from_nat(n)` inside the arm would read the
# countdown the arm already spent, and a `U32` self-call is refused outright
# without a `Nat` fuel (bend2-constraints.md, position 6847).
def vis.count_at(n: Nat, +v: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: vis.count_at(m, U32.add(v, 1), List.append(&2, U32, acc, [v]))

def vis.range.go(n: Nat, +lo: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  vis.count_at(n, lo, acc)

def vis.range(+lo: U32, hi: U32) -> List<&2, U32>:
  vis.range.go(U32.to_nat(vis.count(lo, hi)), lo, Nil{})

# the id list, and the two answers :16 can give. `Ids2.n` is the length and
# `Ids2.ids` the list; the SELECTION is a separate def so the gate can ask both.
type Ids2 is Data:
  Ids2{n: U32, ids: List<&2, U32>}

def Ids2.counted(+xs: List<&2, U32>, n: U32) -> Ids2: Ids2{n, xs}

def Ids2.of(+xs: List<&2, U32>) -> Ids2:
  Ids2.counted(xs, U32.from_nat(List.length(&2, U32, xs)))

def Ids2.ids(i: Ids2) -> List<&2, U32>:
  match i:
    case Ids2{n, ids}: ids

def Ids2.n(i: Ids2) -> U32:
  match i:
    case Ids2{n, ids}: n

# :16 `return [devs[x] for x in ids] if ids else devs`. The `if ids` is the EMPTY
# case, and it is the one that turns a bad range into "every device".
def face.select(n: U32, +i: Ids2) -> U32:
  Bool.pick(U32, U32.is_eq(Ids2.n(i), 0), n, Ids2.n(i))

# :15 `assert all(x < len(devs) for x in ids)` -- every id must be IN RANGE, and
# `x == len(devs)` is already a refusal and not a wrap.
def face.one_in(x: U32, ndev: U32) -> Bool: U32.is_lt(x, ndev)

def face.all_in.go(+xs: List<&2, U32>, +ndev: U32, +bad: Bool) -> Bool:
  match xs:
    case Nil{}: Bool.not(bad)
    case x <> t: face.all_in.go(t, ndev, Bool.or(bad, Bool.not(face.one_in(x, ndev))))

def face.all_in(xs: List<&2, U32>, ndev: U32) -> Bool: face.all_in.go(xs, ndev, False{})

# which of the two `if` arms :13 took. The range arm is the one that CONSUMES THE
# `[1:]`, and a parser that answered `list` for a string with a '-' at index 1 or
# later would pick this wrong for EVERY ranged device.
def vis.is_range(dash_at: U32) -> Bool: U32.is_ne(dash_at, 0)

# ===========================================================================
# :61-65 and :89 -- THE CTYPES LIBRARY GATE, which is WALL 3 and the whole
# branching story in this file.
#
#   :62 `return ctypes.CDLL(ctypes.util.find_library('atomic')) if sys.platform == "linux" else None`
#   :65 `return ctypes.CDLL(ctypes.util.find_library("System"))`      <- NO GATE
#   :89 `lib.atomic_thread_fence(__ATOMIC_SEQ_CST:=5) if (lib:=self.libsys if OSX else self.atomic_lib) is not None else None`
#
# THE TWO LIBRARIES ARE NOT SYMMETRIC. `atomic_lib` is LINUX-ONLY and so is None on
# macOS; `libsys` is loaded unconditionally. :89 then asks a SECOND and DIFFERENT
# question -- `self.libsys if OSX else self.atomic_lib` -- and the two predicates
# happen to agree on every real platform, which is exactly why a port that read
# `have_atomic` on both arms would typecheck and be right by accident. On OSX it
# would call a fence through a library that is None.
#
# SO `cap.barrier_lib` reads `have_atomic` on the NON-OSX ARM ONLY, and
# `cap.fences` asks the SECOND question (:89's `is not None`) separately. One of
# the four fixtures is the negative case -- a None library emits NO FENCE AT ALL,
# which is the `else None` at the end of :89 and the reason a fence is not a
# guaranteed syscall.
# ===========================================================================

def LIB_NONE() -> U32: 0
def LIB_ATOMIC() -> U32: 1
def LIB_SYS() -> U32: 2

# `atomic_lib` is the `sys.platform == "linux"` gate, and it is a def OF the
# platform so the fixture can drive both arms: on macOS the answer is None and
# `cap.atomic_on` must be False.
def cap.atomic_on(osx: U32) -> Bool: U32.is_eq(osx, CAP_NO())

def cap.barrier_lib.p2(+osx: U32, have_atomic: Bool, +have_sys: Bool) -> U32:
  Bool.pick(U32, U32.is_eq(osx, CAP_YES()),
    Bool.pick(U32, have_sys, LIB_SYS(), LIB_NONE()),
    Bool.pick(U32, have_atomic, LIB_ATOMIC(), LIB_NONE()))

def cap.barrier_lib(osx: U32, have_atomic: Bool, have_sys: Bool) -> U32:
  cap.barrier_lib.p2(osx, have_atomic, have_sys)

# the SECOND question: does a fence get emitted at all? A None library is a SILENT
# no-op, not an error.
def cap.fences(lib: U32) -> Bool: U32.is_ne(lib, LIB_NONE())

# :62 and :65 as a trace: the LINUX platform loads 'atomic' and BOTH platforms load
# "System", and the two are separate `CDLL` calls. The order is fixed by the
# fixture, not claimed from Python -- the two are independent cached properties.
def cap.load(t: Tr) -> Tr: Tr.emit(CALL_CDLL(), 0, "atomic", t)

def cap.load_sys(t: Tr) -> Tr: Tr.emit(CALL_CDLL(), LIB_SYS(), "System", t)

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

def sysfs.echo(+value: String, +path: String) -> String:
  String.concat(["sudo sh -c 'echo ", value, " > ", path, "'"])

# :57's `(expected or value)`: the COMPARISON target. `expected` is `str | None` and
# :57 passes `expected or value`, so an `expected` of "" is ALSO falsy and the
# fallback is the VALUE. Python's `or` on a string is emptiness, so this is a
# two-way gate and not a `Maybe`.
def sysfs.want(+expected: String, +value: String) -> String:
  Bool.pick(String, String.is_empty(expected), value, expected)

# :57 the comparison, `read().splitlines()[0] != (expected or value)`.
def sysfs.matches(current: String, expected: String, +value: String) -> Bool:
  String.eq(current, sysfs.want(expected, value))

def sysfs.read(+path: String, t: Tr) -> Tr: Tr.emit(CALL_READ(), O_RDONLY(), path, t)

# the whole of :57-59 as a trace over a fixture that supplies the two reads. `ok1`
# is what the FIRST read returned and `ok2` what the second did, which is the only
# state this file's own logic owns -- the read itself is the seam.
def sysfs.raise(needed: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, needed, Tr.fail(t), t)

def sysfs.wrote(+path: String, +value: String, expected: String, +needed: Bool, +t: Tr) -> Tr:
  sysfs.raise(needed, Bool.pick(Tr, needed, sysfs.read(path, t), t))

# the `if` at :57: a MATCHING first read means the whole `if` body -- the `sudo`
# line AND the second read AND the raise -- does not happen. That is the negative
# case, and it is the row that says the write is CONDITIONAL.
def sysfs.again(+path: String, +value: String, expected: String, +needed: Bool, +t: Tr) -> Tr:
  sysfs.wrote(path, value, expected, needed,
    Bool.pick(Tr, needed, Tr.emit(CALL_SYSTEM(), 0, sysfs.echo(value, path), t), t))

# THE FIRST READ IS PART OF THE CLAIM. :57 is `if FileIOInterface(path,
# os.O_RDONLY).read().splitlines()[0] != ...` -- the read happens BEFORE the
# comparison, on BOTH arms, so `ok1 == True` is one CALL_READ and no `sudo` line
# and not "nothing happened". My first version called `sysfs.again` straight from
# here and emitted no read at all, which made `sy_write_ok_nread` and
# `sy_pagemap_total_reads` read 0 and made the whole of :67-70 look like a no-op.
def sysfs.apply(+path: String, +value: String, expected: String, ok1: Bool, ok2: Bool,
                t: Tr) -> Tr:
  sysfs.again(path, value, expected, Bool.not(ok1), sysfs.read(path, t))

# ===========================================================================
# :67-70 `pagemap`, :84-87 `reserve_va`, :91-92 `lock_memory`. Three
# `functools.cached_property` / `functools.cache` rules and one refusal, and the
# ONE thing worth porting in all of them is the CACHING, because each of them runs
# exactly once and a port that ran it twice would write to a device twice.
# ===========================================================================

def PAGEMAP_SYSFS() -> String: "/proc/sys/vm/compact_unevictable_allowed"
def PAGEMAP_VALUE() -> String: "0"
def PAGEMAP_PATH() -> String: "/proc/self/pagemap"

# :69-70 the write is UNCONDITIONAL on the first access and never again.
def sys.pagemap(first: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, first,
    Tr.emit(CALL_OPEN(), O_RDONLY(), PAGEMAP_PATH(),
      sysfs.apply(PAGEMAP_SYSFS(), PAGEMAP_VALUE(), "", True{}, True{}, t)),
    t)

# :84-87 `reserve_va`. THE NEGATIVE CASE LIVES IN THE PYTHON SOURCE, which is the
# best kind: the comment at :86 says "cached, runs only once per range", and the
# second call for the SAME `va_start` must emit NOTHING. A port that re-maps would
# hand the same virtual address to two mappings and the second `MAP_FIXED_NOREPLACE`
# would fail inside the kernel, silently.
#
# THE FLAGS, :87: `mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS | MAP_NORESERVE |
# MAP_FIXED_NOREPLACE`. `MAP_LOCKED` and `MAP_POPULATE` are NOT here, which is the
# one thing easy to get wrong, and MAP_ANONYMOUS is the platform-dependent one.
# MEASURED: the source's own Linux OR is 0x100422 == 2 | 0x20 | 0x400 | 0x100000.
def VA_FLAGS_OSX() -> U32: 1053698
def VA_FLAGS_LINUX() -> U32: 1049634

def VA_FLAGS(osx: U32) -> U32: Bool.pick(U32, U32.is_eq(osx, CAP_YES()), VA_FLAGS_OSX(), VA_FLAGS_LINUX())

def sys.reserve_va.add(va_start: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, reserved, have_atomic, have_sys, refused}:
      Tr{calls, next, List.append(&2, U32, reserved, [va_start]), have_atomic, have_sys, refused}

def sys.reserve_va.take(va_start: U32, va_size: U32, osx: U32, t: Tr) -> Tr:
  sys.reserve_va.add(va_start, Tr.emit(CALL_MMAP(), VA_FLAGS(osx), "", t))

def sys.reserve_va.put(va_start: U32, va_size: U32, osx: U32, seen: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, seen, t, sys.reserve_va.take(va_start, va_size, osx, t))

def sys.reserve_va(+va_start: U32, va_size: U32, osx: U32, +t: Tr) -> Tr:
  sys.reserve_va.put(va_start, va_size, osx,
    List.contains(U32, U32.is_eq, Tr.reserved(t), va_start), t)

# :91-92 `lock_memory`: `if libc.mlock(c_void_p(addr), size): raise`. A NONZERO
# return is the refusal, so the port emits the call and then truncates on a
# nonzero result. The `addr` is a 64-bit pointer, so only its LOW word travels.
def sys.lock_memory(addr_lo: U32, +size: U32, ret: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_zero(ret),
    Tr.emit(CALL_MLOCK_OK(), size, "", t), Tr.emit.stop(CALL_MLOCK(), size, "", t))

# ===========================================================================
# :98-102 -- `alloc_sysmem`, THE FLAG ARITHMETIC. Four inputs, two outputs, and
# one of the inputs is a WALRUS that only fires on one arm.
#
#   :99  `assert not contiguous or size <= (2 << 20)`
#   :100 `flags = (libc.MAP_HUGETLB if contiguous and (size:=round_up(size, mmap.PAGESIZE)) > mmap.PAGESIZE else 0) | (MAP_FIXED if vaddr else 0)`
#   :101 `FileIOInterface.anon_mmap(vaddr, size, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS|MAP_POPULATE|MAP_LOCKED|flags, 0)`
#
# THE WALRUS IS THE WHOLE OF IT. `size := round_up(size, PAGESIZE)` sits INSIDE the
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

def MMAP_BASE_LINUX() -> U32: 40993                 # 0xa021 = SHARED|ANON|POPULATE|LOCKED

# MEASURED: the Linux base is 0xa021 and a 2-page contiguous request adds
# MAP_HUGETLB and nothing else, so the mmap flags are 0x4a021 == 303137 at vaddr 0
# and 0x4a031 == 303153 with a vaddr, and a plain one-page request is 0xa031 == 41009.
def ALLOC_HUGE_VADDR0() -> U32: 303137
def ALLOC_HUGE_VADDRNZ() -> U32: 303153
def ALLOC_PLAIN_VADDRNZ() -> U32: 41009

# `flags`, split so the gate can ask each term.
def alloc.huge(size: U32, +contiguous: Bool, pagesize: U32) -> U32:
  Bool.pick(U32, Bool.and(contiguous, U32.is_gt(size, pagesize)), MAP_HUGETLB(), 0)

def alloc.fixed(+vaddr: U32) -> U32: Bool.pick(U32, U32.is_zero(vaddr), 0, MAP_FIXED())

def alloc.flags(size: U32, contiguous: Bool, vaddr: U32, pagesize: U32) -> U32:
  U32.or(alloc.huge(size, contiguous, pagesize), alloc.fixed(vaddr))

# `size'` -- the walrus. It rounds ONLY when `contiguous`.
def alloc.size.pick(+rounded: U32, +contiguous: Bool, +size: U32) -> U32:
  Bool.pick(U32, contiguous, rounded, size)

def alloc.size(+size: U32, contiguous: Bool, pagesize: U32) -> U32:
  alloc.size.pick(H.round_up_u32(size, pagesize), contiguous, size)

# :99 the assert, which is a REFUSAL and so a truncation.
def alloc.ok(size: U32, contiguous: Bool) -> Bool:
  Bool.or(Bool.not(contiguous), U32.is_le(size, HUGE_LO()))

def sys.alloc_sysmem.put(+ok: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, ok, t, Tr.fail(t))

def sys.alloc_sysmem.go(size: U32, vaddr: U32, +contiguous: Bool, +pagesize: U32,
                        +ok: Bool, +t: Tr) -> Tr:
  sys.alloc_sysmem.put(ok, Bool.pick(Tr, ok, Tr.emit(CALL_MMAP(),
    U32.or(MMAP_BASE_LINUX(),
           alloc.flags(alloc.size(size, contiguous, pagesize), contiguous, vaddr, pagesize)),
    "", t), t))

def sys.alloc_sysmem(+size: U32, vaddr: U32, +contiguous: Bool, pagesize: U32, t: Tr) -> Tr:
  sys.alloc_sysmem.go(size, vaddr, contiguous, pagesize, alloc.ok(size, contiguous), t)

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
# THE TABLES ARE READ OUT OF THE CALLERS by the oracle, not typed:
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

def AMD_VENDOR() -> U32: 4098                       # 0x1002
def NV_VENDOR() -> U32: 4318                        # 0x10de
def AMD_MASK() -> U32: 65535                        # 0xffff
def NV_MASK() -> U32: 65280                         # 0xff00

def amd_ids() -> List<&2, U32>:
  [29857, 29877, 29772, 29824, 30032, 30033, 30096, 30112, 30120, 30128, 30131]

def nv_ids() -> List<&2, U32>:
  [8704, 9216, 9472, 9728, 9984, 10240, 11008, 11264, 11520, 12032]

# the ONE term, and it is `device & mask` and not `device`.
def scan.term(device: U32, mask: U32, devlist: List<&2, U32>) -> Bool:
  List.contains(U32, U32.is_eq, devlist, U32.and(device, mask))

# `any(...)` over the groups, and a SINGLE group in each real table -- so the fold
# is written anyway, because the argument is a TUPLE OF PAIRS and a table with one
# entry is still a table that could have two.
def scan.any.go(ms: List<&2, U32>, ls: List<&2, List<&2, U32>>, +device: U32, +hit: Bool) -> Bool:
  match ms:
    case Nil{}: hit
    case m <> t:
      match ls:
        case Nil{}: hit
        case l <> u: scan.any.go(t, u, device, Bool.or(hit, scan.term(device, m, l)))

def scan.any(device: U32, masks: List<&2, U32>, lists: List<&2, List<&2, U32>>) -> Bool:
  scan.any.go(masks, lists, device, False{})

# the `and`, and the TWO conjuncts are checked apart: a row that only asked the
# conjunction could not say which half refused.
def scan.keeps(vndr: U32, vendor: U32, device: U32, masks: List<&2, U32>,
               lists: List<&2, List<&2, U32>>) -> Bool:
  Bool.and(U32.is_eq(vndr, vendor), scan.any(device, masks, lists))

def scan.amd(vndr: U32, device: U32) -> Bool:
  scan.keeps(vndr, AMD_VENDOR(), device, [AMD_MASK()], [amd_ids()])

def scan.nv(vndr: U32, device: U32) -> Bool:
  scan.keeps(vndr, NV_VENDOR(), device, [NV_MASK()], [nv_ids()])

# :117's `f"{v:x}:{d:x}"`, the OSX id, beside :124's Linux `pcibus` string. Two
# different strings for the same device, and which one you get is the platform.
def scan.id_osx(vendor: U32, device: U32) -> String:
  String.concat([hx.q(vendor), ":", hx.q(device)])

# :122-123 the base-class filter, `int(read(..., "class"), 16) >> 16 != base_class`.
# The shift is 16 and the comparison is against the WHOLE shifted value, so
# `0x30000 >> 16 == 0x03` accepts and `0x020000 >> 16 == 0x02` does not.
def scan.base_ok(class_code: U32, base_class: U32) -> Bool:
  U32.is_eq(U32.shrn(class_code, 16n), base_class)

# :156 `pci.PCI_EXT_CAP_ID(x)` and :161 `pci.PCI_EXT_CAP_NEXT(x)`. Both are the low
# byte of the dword, and the gate asks both directions because the REBAR test is the
# only reader of the first and the walk is the only reader of the second.
def scan.cap_id(hdr: U32) -> U32: U32.and(hdr, 255)
def scan.cap_next(hdr: U32) -> U32: U32.and(hdr, 255)

def scan.is_rebar(hdr: U32) -> Bool: U32.is_eq(scan.cap_id(hdr), PCI_EXT_CAP_ID_REBAR())

# :117 the 8-byte little-endian property read, `int.from_bytes(bytes(buf), "little")`.
# Only the LOW FOUR bytes are used, because the property read writes into a
# `(c_uint8*8)()` and every property in :116-117 is a 16-bit id.
def pci.read_prop(lo: U32, hi: U32) -> U32: lo

# ===========================================================================
# :138-186 -- `pci_setup_usb_bars`. THE HEADLINE, and the one place in this file
# where a wrong answer is a SILENTLY WRONG REGISTER WRITE with no other symptom.
#
# THREE SEPARATE CLAIMS, and the gate keeps them apart:
#
#   (a) THE WRITE ORDER. :142-151 is EIGHT `pcie_cfg_req` calls per bus, in this
#       order, and the order is the claim:
#         PCI_PRIMARY_BUS(0x18,s4)  PCI_MEMORY_BASE(0x20,s2)  PCI_MEMORY_LIMIT(0x22,s2)
#         PCI_PREF_MEMORY_BASE(0x24,s2)  PCI_PREF_MEMORY_LIMIT(0x26,s2)
#         PCI_PREF_BASE_UPPER32(0x28,s4)  PCI_PREF_LIMIT_UPPER32(0x2c,s4)
#         PCI_COMMAND(0x04,s1)
#       :140 says why the first five must be simultaneous ("All 3 values must be
#       written at the same time"), which is a hardware fact and not a Python one --
#       so the port records the order and does not reorder it.
#       MEASURED, bus=0, gpu_bus=4, mem_base=0x10000000, pref_mem_base=32<<30:
#         0x18 -> 0x40100 s4   0x20 -> 0x1000 s2   0x22 -> 0xffff  s2
#         0x24 -> 0x0    s2   0x26 -> 0xffff  s2   0x28 -> 0x8     s4
#         0x2c -> 0xffffffff s4   0x04 -> 0x7     s1
#       and bus=3 differs from bus=0 in ONE value: 0x18 is 0x40400 not 0x40100.
#       That single differing row is the negative case for the whole loop.
#
#   (b) THE REBAR CONTROL REWRITE, :158.
#       `new_ctrl = (cfg & ~0x1F00) | ((int(cap >> 4).bit_length() - 1) << 8)`
#       `~0x1F00` is 0xFFFFE0FF as a u32 -- the `0x1F00` is bits 8..12 and the mask
#       CLEARS them. MEASURED: cap=0x1001 cur=0x201 -> 0x1801; cap=0x2100 cur=0x201
#       -> 0x1901. `int(cap>>4).bit_length()` is the log2 of the BAR size, so this
#       is the RESIZE, and getting it wrong resizes a BAR to the wrong power of two.
#
#   (c) THE BAR PROBE LOOP, :163-183. `bar_off` starts at 0 and the loop is
#       `while bar_off < 24`, advancing `8 if bar_64 else 4`, so there are AT MOST
#       SIX iterations and the bound is not a coincidence: PCI config space has six
#       BARs. The 32-bit SIZE is `0 - (lo & 0xfffffff0)` in U32 wrap arithmetic --
#       MEASURED equal to CPython's
#       `((~(((hi << 32) | lo) & ~0xf)) + 1) & 0xffffffff` at lo = 0x10000000,
#       0xf0000000, 0x0, 0xfff00000 and 0xfffff000. The 64-bit arm is WALL 1.
#
# The `Cfg` record's field order is `CustomASM24Controller.pcie_cfg_req`'s own
# signature, MEASURED out of `usb.py:137`:
#   (self, byte_addr, bus=1, dev=0, fn=0, value=None, size=4)
# ===========================================================================

def BAR_LOOP_BOUND() -> U32: 24
def BAR_OFF_STEP32() -> U32: 4
def BAR_OFF_STEP64() -> U32: 8
def CAP_PTR_START() -> U32: 256                   # 0x100
def REBAR_CTRL_OFF() -> U32: 4                    # cap_ptr + 0x04
def REBAR_CTRL_MASK() -> U32: 4294959359          # ~0x1F00 as a u32 == 0xffffe0ff
def REBAR_SHIFT() -> U32: 8
def LO_MASK() -> U32: 4294967280                  # 0xfffffff0
def NOT_F() -> U32: 4294967295                     # ~0xf, the 32-bit form
def MEM_BASE_USB() -> U32: 268435456              # 0x10000000
def PREF_BASE_HI() -> U32: 8                      # (32 << 30) >> 32
def PREF_BASE_LO() -> U32: 0                      # (32 << 30) & 0xffffffff
def GPU_BUS() -> U32: 4
def U32MAX() -> U32: 4294967295
def U16MAX() -> U32: 65535

# the Cfg readers, BY NAME. The order of these six is the order of the callee's
# parameters and the gate reads them by name so a swap of two FIELDS shows up as a
# changed VALUE in a row that names the field.
def Cfg.of(byte_addr: U32, bus: U32, dev: U32, fn: U32, value: U32, size: U32) -> Cfg:
  Cfg{byte_addr, bus, dev, fn, value, size, True{}}

def Cfg.rd(byte_addr: U32, bus: U32, dev: U32, fn: U32, size: U32) -> Cfg:
  Cfg{byte_addr, bus, dev, fn, 0, size, False{}}

def Cfg.byte_addr(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: byte_addr

def Cfg.bus(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: bus

def Cfg.dev(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: dev

def Cfg.fn(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: fn

def Cfg.value(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: value

def Cfg.size(c: Cfg) -> U32:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: size

def Cfg.is_write(c: Cfg) -> Bool:
  match c:
    case Cfg{byte_addr, bus, dev, fn, value, size, is_write}: is_write

# --- (a) the eight bus-enable writes ---------------------------------------
#
# `buses = (0 << 0) | ((bus+1) << 8) | (gpu_bus << 16)` -- three terms and the first
# is the CONSTANT ZERO, which is there to say the secondary and subordinate bus
# fields are written as zero. MEASURED: bus=0 -> 0x40100, bus=1 -> 0x40200,
# bus=2 -> 0x40300, bus=3 -> 0x40400. So the bus number lands in bits 8..15 and
# `gpu_bus` in bits 16..23.
def bars.buses.pick(+bus1: U32, +gpu: U32) -> U32: U32.or(U32.shln(bus1, 8n), U32.shln(gpu, 16n))

def bars.buses(bus: U32, gpu_bus: U32) -> U32: bars.buses.pick(U32.add(bus, 1), gpu_bus)

# `(mem_base >> 16) & 0xffff` -- the 32-bit BAR window's low half, in 64 KiB units.
def bars.mem_base16(mem_base: U32) -> U32: U32.and(U32.shrn(mem_base, 16n), U16MAX())

# `(pref_mem_base >> 16) & 0xffff` where pref_mem_base is 64-BIT. The mask keeps
# bits 16..31 of the 64-bit value, and those live ENTIRELY IN THE LOW WORD, so the
# high word does not participate and (32<<30) answers 0. My first version invented a
# borrow from the high word and answered 8, which is `(pref_mem_base >> 32)`.
# `bars.pref_base16` takes both halves and IGNORES the high one, which is the claim.
def bars.pref_base16(+hi: U32, +lo: U32) -> U32: U32.and(U32.shrn(lo, 16n), U16MAX())

# `pref_mem_base >> 32` -- the HIGH half, and it is 8 for 32 GiB.
def bars.pref_base_hi(+hi: U32, +lo: U32) -> U32: hi

def bars.put8(xs: List<&2, Cfg>, c: Cfg) -> List<&2, Cfg>:
  List.append(&2, Cfg, xs, [c])

# `PCI_COMMAND` gets `IO | MEMORY | MASTER` at BOTH :151 and :185, and the second
# one is AFTER the BAR loop -- the port of "enable the BARs, then turn the bus on".
# The first SEVEN writes are the ones :140 says must be simultaneous, and they are
# built by `bars.writes.of` in source order. `bars.writes.cmd` is the eighth and is
# a separate def so the gate can name "the first seven" and "all eight" as two
# different claims.
def bars.writes.cmd(+bus: U32, +xs: List<&2, Cfg>) -> List<&2, Cfg>:
  bars.put8(xs, Cfg.of(PCI_COMMAND(), bus, 0, 0, PCI_COMMAND_ALL(), 1))

def bars.writes.of(+bus: U32, +gpu_bus: U32, +acc: List<&2, Cfg>) -> List<&2, Cfg>:
  bars.writes.cmd(bus,
    bars.put8(bars.put8(bars.put8(bars.put8(bars.put8(bars.put8(
      bars.put8(acc,
        Cfg.of(PCI_PRIMARY_BUS(), bus, 0, 0, bars.buses(bus, gpu_bus), 4)),
        Cfg.of(PCI_MEMORY_BASE(), bus, 0, 0, bars.mem_base16(MEM_BASE_USB()), 2)),
        Cfg.of(PCI_MEMORY_LIMIT(), bus, 0, 0, U16MAX(), 2)),
        Cfg.of(PCI_PREF_MEMORY_BASE(), bus, 0, 0,
               bars.pref_base16(PREF_BASE_HI(), PREF_BASE_LO()), 2)),
        Cfg.of(PCI_PREF_MEMORY_LIMIT(), bus, 0, 0, U16MAX(), 2)),
        Cfg.of(PCI_PREF_BASE_UPPER32(), bus, 0, 0,
               bars.pref_base_hi(PREF_BASE_HI(), PREF_BASE_LO()), 4)),
        Cfg.of(PCI_PREF_LIMIT_UPPER32(), bus, 0, 0, U32MAX(), 4)))

def bars.writes(bus: U32) -> List<&2, Cfg>: bars.writes.of(bus, GPU_BUS(), Nil{})

# --- (b) the REBAR rewrite ---------------------------------------------------
#
# `int(cap >> 4).bit_length() - 1` is log2 of the BAR size in the capability's own
# field, and it is a `Nat` in Python and a bounded `U32` here. `hx.bitlen` is bounded
# to 32 bits by a `Nat` countdown, and the bound is the claim.
def hx.bitlen.go(n: Nat, +v: U32, +w: U32) -> U32:
  match n:
    case 0n: w
    case 1n+m: hx.bitlen.go(m, U32.shrn(v, 1n),
      Bool.pick(U32, U32.is_zero(v), w, U32.add(w, 1)))

def hx.bitlen(v: U32) -> U32: hx.bitlen.go(32n, v, 0)

# THE `1n` IS A REAL EDGE, NOT A THEOREM. For `cap < 0x10`, `(cap>>4).bit_length()`
# is 0 and Python's `- 1` is NEGATIVE, so the shift is a negative int and `|` sets
# the HIGH bits: MEASURED, `cap=0x1, cur=0x201 -> 0xFFFFFF01`. The port computes the
# same thing in U32 wrap arithmetic, and the row for it is a boundary row, not a
# claim that the value is small.
def bars.rebar.pick(+cleared: U32, +sized: U32) -> U32: U32.or(cleared, sized)

def bars.rebar_size(cap: U32) -> U32:
  U32.shln(U32.sub(hx.bitlen(U32.shrn(cap, 4n)), 1), 8n)

def bars.rebar(cur: U32, cap: U32) -> U32:
  bars.rebar.pick(U32.and(cur, REBAR_CTRL_MASK()), bars.rebar_size(cap))

# --- (c) the BAR probe loop --------------------------------------------------
#
# `bar_mem, bar_64 = bool(cfg & PCI_BASE_ADDRESS_MEM_PREFETCH),
#  cfg & PCI_BASE_ADDRESS_MEM_TYPE_64` -- `bar_mem` is a BOOL, so it indexes
# `mem_space_addr` as 0 or 1, and `bar_64` is the MASKED value (4), not a bool.
def bars.bar_mem.pick(+hit: Bool) -> U32: Bool.pick(U32, hit, 1, 0)

def bars.bar_mem(cfg: U32) -> U32:
  bars.bar_mem.pick(U32.is_ne(U32.and(cfg, PCI_BASE_ADDRESS_MEM_PREFETCH()), 0))

def bars.bar_64(cfg: U32) -> U32: U32.and(cfg, PCI_BASE_ADDRESS_MEM_TYPE_64())

# `cfg & PCI_BASE_ADDRESS_SPACE == PCI_BASE_ADDRESS_SPACE` -- bit 0 set means a
# memory BAR and clear means an I/O BAR, and an I/O BAR is SKIPPED entirely.
def bars.is_mem(cfg: U32) -> Bool:
  U32.is_eq(U32.and(cfg, PCI_BASE_ADDRESS_SPACE()), PCI_BASE_ADDRESS_SPACE())

# THE 32-BIT SIZE, which is exact in U32: `0 - (lo & 0xfffffff0)`.
def bars.size32(lo: U32) -> U32: U32.sub(0, U32.and(lo, LO_MASK()))

# `bar_off += 8 if bar_64 else 4`, and the loop is `while bar_off < 24`.
def bars.step.pick(+bar_off: U32, step: U32) -> U32: U32.add(bar_off, step)

def bars.step(+bar_off: U32, +bar_64: U32) -> U32:
  bars.step.pick(bar_off, Bool.pick(U32, U32.is_zero(bar_64), BAR_OFF_STEP32(), BAR_OFF_STEP64()))

def bars.more(bar_off: U32) -> Bool: U32.is_lt(bar_off, BAR_LOOP_BOUND())

# `mem_space_addr[bar_mem] += round_up(bar_size, 2 << 20)` -- :181, and the alignment
# is 2 MiB REGARDLESS of the BAR's real size, so two adjacent BARs cannot overlap.
# MEASURED: round_up(0x10000000, 2<<20) == 0x10000000 and round_up(0xf0000000, 2<<20)
# == 0xf0000000 -- both already aligned, which is the NEGATIVE case: a fixture that
# only used aligned sizes could not see a wrong alignment. 0x1000 rounds to 0x200000.
def bars.next_addr(+base: U32, size: U32) -> U32: U32.add(base, H.round_up_u32(size, TWO_MB()))

# the USBPCIDevice constants, :277-282, and they are a fixed table rather than
# arguments because :277 SPELLS them at the call site.
def bars.SRAM_SIZE() -> U32: 524288                 # 0x80000
def bars.DMA_BASE() -> U32: 61440                   # 0xf000
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

def PCI_ROOT() -> String: "/sys/bus/pci/devices/"
def VFIO_MODULE() -> String: "/sys/module/vfio"
def VFIO_NOIOMMU_PARAM() -> String: "/sys/module/vfio/parameters/enable_unsafe_noiommu_mode"
def VFIO_DEV() -> String: "/dev/vfio/vfio"
def VFIO_NOIOMMU() -> String: "/dev/vfio/noiommu-"
def DRIVERS_PROBE() -> String: "/sys/bus/pci/drivers_probe"

def pci.path(+pcibus: String, +tail: String) -> String:
  String.concat([PCI_ROOT(), pcibus, "/", tail])

def pci.tails() -> List<&2, String>:
  ["enable", "driver", "driver/unbind", "driver_override", "config", "iommu_group",
   "resource", "resource", "resource", "reset"]

def pci.tail.at(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "?"

def pci.tail(i: U32) -> String: pci.tail.at(List.get(&2, String, pci.tails(), U32.to_nat(i)))

# `resource{bar_idx}` and `resource{bar_idx}_resize`, :256/:266.
def pci.bar_path(+pcibus: String, bar_idx: U32) -> String:
  String.concat([PCI_ROOT(), pcibus, "/resource", U32.show(bar_idx)])

def pci.resize_path(+pcibus: String, bar_idx: U32) -> String:
  String.concat([PCI_ROOT(), pcibus, "/resource", U32.show(bar_idx), "_resize"])

# :220 `f"/sys/bus/pci/devices/{self.pcibus[:-1]}{fn}/remove"` for fn in range(1,8).
# `pcibus[:-1]` drops the LAST character -- the function number -- and `fn` replaces
# it. `String.take` keeps the FIRST n and `String.drop` removes the FIRST n, so the
# tail is `String.take(pcibus, len - 1)`. MEASURED: '0000:03:00.0'[:-1] ==
# '0000:03:00.' and fn=1 gives '/sys/bus/pci/devices/0000:03:00.1/remove'.
def pci.bus_len(+pcibus: String) -> U32:
  U32.from_nat(List.length(&2, Char, String.to_list(pcibus)))

def pci.bus_trim.pick(+pcibus: String, n: U32) -> String: String.take(pcibus, U32.to_nat(n))

def pci.bus_trim(+pcibus: String) -> String: pci.bus_trim.pick(pcibus, U32.sub(pci.bus_len(pcibus), 1))

def pci.sib_path(+pcibus: String, fn: U32) -> String:
  String.concat([PCI_ROOT(), pci.bus_trim(pcibus), U32.show(fn), "/remove"])

def SIB_LO() -> U32: 1
def SIB_HI() -> U32: 8
def sib.n() -> U32: U32.sub(SIB_HI(), SIB_LO())

# the OPEN FLAG per site, and the sites are named because the same tail is opened
# with two different flag sets.
def pci.flags_enable() -> U32: O_RDWR()
def pci.flags_unbind() -> U32: O_WRONLY()
def pci.flags_override() -> U32: O_WRONLY()
def pci.flags_probe() -> U32: O_WRONLY()
def pci.flags_config() -> U32: O_RDWR_SYNC_CLOEXEC()
def pci.flags_bar() -> U32: O_RDWR_SYNC_CLOEXEC()
def pci.flags_resource() -> U32: O_RDONLY()
def pci.flags_resize() -> U32: O_RDWR()

# :219-220 `for fn in range(1, 8)`, and each `remove` is O_WRONLY. SEVEN writes.
#
# A `U32` self-call is refused without a `Nat` fuel and a `Nat` self-call cannot read
# the counter it just spent, so the loop is THREE folds: one that builds the seven
# function numbers, one that builds the seven paths, one that emits. Each is a
# single self-call and none of them is mutually recursive.
def sib.walk(n: Nat, +fn: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: sib.walk(m, U32.add(fn, 1), List.append(&2, U32, acc, [fn]))

def sib.build_paths(fs: List<&2, U32>, +pcibus: String, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> t:
      sib.build_paths(t, pcibus, List.append(&2, String, acc, [pci.sib_path(pcibus, f)]))

def sib.paths(+pcibus: String) -> List<&2, String>:
  sib.build_paths(sib.walk(U32.to_nat(sib.n()), SIB_LO(), Nil{}), pcibus, Nil{})

def pci.probe.sibs.go(ps: List<&2, String>, +t: Tr) -> Tr:
  match ps:
    case Nil{}: t
    case p <> u: pci.probe.sibs.go(u, Tr.emit(CALL_WRITE(), pci.flags_unbind(), p, t))

def pci.probe.sibs(+pcibus: String, +t: Tr) -> Tr: pci.probe.sibs.go(sib.paths(pcibus), t)

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
# `lower()`. TODO(p3) runtime/support/system.py:208 -- the two `lower()` calls.
def pci.lock_name(devpref: String, +pcibus: String) -> String:
  String.concat([devpref, "_", pcibus, ".lock"])

# :136 `cl(device[:2], pcibus)` -- the device CLASS is the first TWO characters of the
# device head, and it is two and not one and not three. `AM` for AMD, `CU` for CUDA,
# `NPU` would be three. So this is a genuine `take(2)` and a row.
def pci.class_prefix(device: String) -> String: String.take(device, 2n)

# :240 the non-VFIO arm, `FileIOInterface(..."/enable", O_RDWR).write("1")`, and it is
# the ELSE of :222 so it happens exactly when VFIO is not used.
def pci.probe.enable_write(+pcibus: String, +t: Tr) -> Tr:
  Tr.emit(CALL_WRITE(), pci.flags_enable(), pci.path(pcibus, pci.tail(0)), t)

def pci.probe.vfio(+pcibus: String, +t: Tr) -> Tr:
  Tr.emit(CALL_WRITE(), pci.flags_override(), pci.path(pcibus, pci.tail(3)), t)

# :208 the full `PCIDevice.__init__` as a trace, in ORDER. The five things it does,
# in order: open `enable`, ask whether `driver` exists, unbind it, ask AGAIN whether
# `driver` exists (and REFUSE if it does), remove the seven sibling functions, then
# either the VFIO sequence or the plain `enable` write, then open `config`.
#
# THE SECOND `driver` CHECK IS THE CLAIM. :214 asks, :215 unbinds, :216 asks again and
# raises -- so an UNBIND THAT DID NOT TAKE is a refusal, and it is a TRUNCATION
# rather than a flag. `pci.probe` threads `bound` into BOTH the unbind and the second
# check, which is the only way the second check can disagree with the first, and
# `sy_pci_bound_refused` is the row.
def pci.probe.config(+pcibus: String, +t: Tr) -> Tr:
  Tr.emit(CALL_OPEN(), pci.flags_config(), pci.path(pcibus, pci.tail(4)), t)

# :222 `if getenv("VFIO", 0) and (vfio_fd := System.vfio) is not None:` -- the VFIO arm,
# and it is an AND of TWO facts: the env var and the probe succeeding. A VFIO probe
# that returned None falls through to the plain `enable` write, and that fall-through
# is the row.
def pci.probe.arm(use_vfio: Bool, +plain: Tr, +vfi: Tr) -> Tr:
  Bool.pick(Tr, use_vfio, vfi, plain)

def pci.probe.unbound(+pcibus: String, use_vfio: Bool, +bound: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, bound, Tr.fail(t),
    pci.probe.config(pcibus, pci.probe.arm(use_vfio,
      pci.probe.enable_write(pcibus, t), pci.probe.vfio(pcibus, t))))

def pci.probe.drv2(+pcibus: String, +bound: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, bound, t,
    Tr.emit(CALL_WRITE(), pci.flags_unbind(), pci.path(pcibus, pci.tail(2)), t))

def pci.probe.drv1(+pcibus: String, +t: Tr) -> Tr:
  Tr.emit(CALL_EXISTS(), 0, pci.path(pcibus, pci.tail(1)), t)

def pci.probe.enable(+pcibus: String, +t: Tr) -> Tr:
  Tr.emit(CALL_OPEN(), pci.flags_enable(), pci.path(pcibus, pci.tail(0)), t)

def pci.probe(+pcibus: String, +bound: Bool, use_vfio: Bool, t: Tr) -> Tr:
  pci.probe.unbound(pcibus, use_vfio, bound,
    pci.probe.sibs(pcibus, pci.probe.drv2(pcibus, bound,
      pci.probe.drv1(pcibus, pci.probe.enable(pcibus, t)))))

# :75 `os.system("sudo modprobe vfio-pci disable_idle_d3=1")` -- WALL 2's plain string,
# and it is CONDITIONAL on `/sys/module/vfio` being absent.
def VFIO_MODPROBE() -> String: "sudo modprobe vfio-pci disable_idle_d3=1"

# :225 `FileIOInterface.readlink(f".../iommu_group").split('/')[-1]` and :227
# `f"/dev/vfio/noiommu-{iommu_group}"`. MEASURED: the readlink target ends in
# '.../iommu_group', so `split('/')[-1]` is the WORD 'iommu_group' and NOT a number
# -- the number is the second-to-last component, and this file's expression is what
# it is. `pci.iommu_path` takes the group the SEAM resolved.
def pci.iommu_path(+iommu_group: U32) -> String:
  String.concat([VFIO_NOIOMMU(), U32.show(iommu_group)])

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

def BAR_INFO_DELTA() -> U32: 1

def bar.size(lo: U32, +hi: U32) -> U32: U32.add(U32.sub(hi, lo), BAR_INFO_DELTA())

# MEASURED pairs (start, end, size):
#   0x7c000000 0x7fffffff -> 0x4000000
#   0x10000000 0x1fffffff -> 0x10000000   (the 256 MiB "small bar" AMD reports)
#   0x7d000000 0x7d1fffff -> 0x200000
#   0x7d000000 0x7d3fffff -> 0x400000
#   0x0        0xfff      -> 0x1000
def SMALL_BAR_SIZE() -> U32: 268435456

# :300 `is_bar_small` is `bar_info(vram_bar)[1] == (256 << 20)` -- an EQUALITY on the
# size, not a comparison, so 256 MiB - 1 is NOT a small bar. Both sides are rows.
def face.bar_small(size: U32) -> Bool: U32.is_eq(size, SMALL_BAR_SIZE())

def face.is_bar_small(bar_size: U32) -> Bool: U32.is_eq(bar_size, SMALL_BAR_SIZE())

# :267 `int(x, 16).bit_length() - 1`, the log2 of the resizable-BAR size. The `- 1` is
# a subtraction that goes NEGATIVE for x < 2, and `resize_bar` writes that straight
# into sysfs -- MEASURED, x=0x1 -> "0" and x=0x0 -> "-1". A U32 port wraps it, and the
# row for the boundary says so rather than pretending.
def pci.resize_log2(size: U32) -> U32: U32.sub(hx.bitlen(size), BAR_INFO_DELTA())

# :263 `map_bar`: `fd.mmap(addr, sz, PROT_READ|PROT_WRITE, MAP_SHARED | (MAP_FIXED if
# addr else 0), off)` and `sz = size or (self.bar_info(bar)[1] - off)`. MEASURED:
# addr=0 -> 0x1, addr!=0 -> 0x11. And the `or` means size=0 is FALSY and falls back
# to the BAR size, which is a Python truthiness rule and not a `None` check.
def MAP_BAR_FLAGS_OSX() -> U32: 1
def MAP_BAR_FLAGS_FIXED() -> U32: 17

def pci.map_flags.pick(+addr: U32) -> U32: Bool.pick(U32, U32.is_zero(addr), MAP_BAR_FLAGS_OSX(), MAP_BAR_FLAGS_FIXED())

def pci.map_flags(+addr: U32) -> U32: pci.map_flags.pick(addr)

# `size or (bar_info(bar)[1] - off)` -- the FALSY side is 0, not None.
def pci.map_size.pick(+want: U32, +size: U32) -> U32: Bool.pick(U32, U32.is_zero(size), want, size)

def pci.map_size(bar_size: U32, off: U32, size: U32) -> U32:
  pci.map_size.pick(U32.sub(bar_size, off), size)

# ===========================================================================
# :292-293 `PCIAllocationMeta` AND :295-355 `PCIIfaceBase`.
# ===========================================================================

# `@dataclasses.dataclass class PCIAllocationMeta: mapping:VirtMapping;
#  has_cpu_mapping:bool; hMemory:int=0`
#
# THE FIELD ORDER AND THE NAMES, in this order, and the THIRD ONE DEFAULTED. The
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
def Meta.of(+has_cpu_mapping: Bool, +hMemory: U32) -> Meta: Meta{has_cpu_mapping, hMemory}

def Meta.has_cpu_mapping(m: Meta) -> Bool:
  match m:
    case Meta{has_cpu_mapping, hMemory}: has_cpu_mapping

def Meta.hMemory(m: Meta) -> U32:
  match m:
    case Meta{has_cpu_mapping, hMemory}: hMemory

def meta.sysmem(+hMemory: U32) -> Meta: Meta.of(True{}, hMemory)
def meta.bar(+hMemory: U32, +cpu_access: Bool) -> Meta: Meta.of(cpu_access, hMemory)

# :297 `@property def peer_group(self) -> str: return getattr(self.pci_dev,
# 'peer_group', type(self.pci_dev).__name__)`
#
# THE `getattr` DEFAULT IS THE CLASS NAME, and only ONE of the three classes in this
# file actually sets `peer_group`. MEASURED, from the three `__init__`s:
#   PCIDevice       -- no assignment                    -> "PCIDevice"
#   USBPCIDevice    -- :272 `f"USBPCIDevice_{pcibus}"`  -> "USBPCIDevice_0000:03:00.0"
#   RemotePCIDevice -- :430 `"remote:%s:%d" % ...`       -> "remote:10.0.0.1:6667"
#
# SO THE FALLBACK FIRES FOR EXACTLY ONE OF THE THREE, and for that one the value is
# the class name. `face.peer_group` is the three-way table and `face.has_explicit` is
# the second direction, so the gate can ask "which class sets it" and "what does the
# fallback give" as two separate claims -- a single-direction row could pass with the
# fallback always on.
#
# THE CROSS-FILE CITATION. `.agents/TODO.md:1374` and `ops_rdma.bend:826` both record
# that `peer_group` is "PCIDevice", not the device head, and both cite this line. THEY
# AGREE WITH THE TABLE ABOVE, and this file gates the value directly rather than
# taking the citation on trust. Reported, not reconciled.
def KIND_PCI() -> U32: 0
def KIND_USB() -> U32: 1
def KIND_REMOTE() -> U32: 2

def face.has_explicit(kind: U32) -> Bool: U32.is_ne(kind, KIND_PCI())

# the fallback, and it is the CLASS NAME.
def face.peer_group_fallback.p2(+kind: U32) -> String:
  Bool.pick(String, U32.is_eq(kind, KIND_USB()), "USBPCIDevice",
    Bool.pick(String, U32.is_eq(kind, KIND_REMOTE()), "RemotePCIDevice", "PCIDevice"))

def face.peer_group_fallback(kind: U32) -> String: face.peer_group_fallback.p2(kind)

# :272 `f"USBPCIDevice_{pcibus}"` -- the class name is a PREFIX of the value and not
# the whole of it, which is the row that separates this from the fallback.
def face.peer_group_usb(+pcibus: String) -> String:
  String.concat(["USBPCIDevice_", pcibus])

# :430 `"remote:%s:%d" % sock.getpeername()[:2]` -- a `%`-format and not an f-string,
# and the two fields are the peer's ADDRESS and PORT in that order.
def face.peer_group_remote(+host: String, port: U32) -> String:
  String.concat(["remote:", host, ":", U32.show(port)])

# the whole of :297 over the three kinds.
def face.peer_group.p2(+kind: U32, +pcibus: String, +host: String, port: U32) -> String:
  Bool.pick(String, U32.is_eq(kind, KIND_USB()), face.peer_group_usb(pcibus),
    Bool.pick(String, U32.is_eq(kind, KIND_REMOTE()), face.peer_group_remote(host, port),
      face.peer_group_fallback(kind)))

def face.peer_group(kind: U32, pcibus: String, host: String, port: U32) -> String:
  face.peer_group.p2(kind, pcibus, host, port)

# :312 `should_use_sysmem = host or (cpu_access and self.is_bar_small() and not
# force_devmem)` -- THREE conjuncts and an `or`, and `Bool.pick` is the `or` (a
# `Bool.or` would evaluate both arms, which is harmless here but is the wrong
# spelling for `x or y`). MEASURED over the six interesting fixtures:
#   host=1 -> True whatever else says
#   cpu_access=1, small, !force_devmem -> True
#   cpu_access=1, NOT small -> False   <- the conjunct that decides small-bar
#   cpu_access=1, small, force_devmem -> False
#   cpu_access=0 -> False
def face.use_sysmem.pick(+host: Bool, +rest: Bool) -> Bool: Bool.or(host, rest)

def face.use_sysmem.p2(+cpu_access: Bool, +small: Bool, +force: Bool) -> Bool:
  Bool.and(cpu_access, Bool.and(small, Bool.not(force)))

def face.use_sysmem(host: Bool, cpu_access: Bool, force_devmem: Bool, small: Bool) -> Bool:
  face.use_sysmem.pick(host, face.use_sysmem.p2(cpu_access, small, force_devmem))

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
def face.devmem_align.pick(+big: Bool, +amt: U32) -> U32: Bool.pick(U32, big, TWO_MB(), amt)

def face.devmem_align(+size: U32) -> U32:
  face.devmem_align.pick(U32.is_ge(size, EIGHT_MB()), FOUR_KB())

# `mmap.PAGESIZE if should_use_sysmem else <the ladder>`, as ONE function, because
# the sysmem arm is a different ALIGNMENT and not a different branch of the same one.
# MEASURED on the Linux page size (4096).
def face.align.pick(+sysmem_align: U32, +dev_align: U32, +sysmem: Bool) -> U32:
  Bool.pick(U32, sysmem, sysmem_align, dev_align)

def face.align(size: U32, sysmem: Bool, pagesize: U32) -> U32:
  face.align.pick(pagesize, face.devmem_align(size), sysmem)

def face.align_size(+size: U32, sysmem: Bool, pagesize: U32) -> U32:
  H.round_up_u32(size, face.align(size, sysmem, pagesize))

# :337 `if b.device.split(":")[0] in {"CPU", "PYTHON", "NPY"}` -- a SET of three HEADS,
# and it is the HEAD and not the whole device string. MEASURED: 'CPU:0' and
# 'PYTHON:1' and 'NPY:2' are host buffers and 'NPU:0' and 'AMD:1' are not. A port that
# compared the whole string would refuse every host buffer, because a Buffer always
# carries its index.
def HOST_HEADS() -> List<&2, String>: ["CPU", "PYTHON", "NPY"]

def face.is_host_device(+head: String) -> Bool:
  List.contains(String, String.eq, HOST_HEADS(), head)

# :339 `if b._buf % 0x1000: raise RuntimeError("Host mapping requires a page-aligned
# address")` -- a refusal, and the modulus is a power of two so it is an AND.
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
def AMD_VA_BITS() -> U32: 48
def AMD_VA_BASE_HI() -> U32: 256
def AMD_VA_BASE_LO() -> U32: 0
def AMD_VA_SPAN_HI() -> U32: 65536
def AMD_VA_SPAN_LO() -> U32: 0

def u64.carried.pick(+sum: U32, +lo: U32) -> Bool: U32.is_lt(sum, lo)

def u64.carried(+lo: U32, size: U32) -> Bool: u64.carried.pick(U32.add(lo, size), lo)

def u64.end_hi(lo_hi: U32, lo: U32, size: U32) -> U32:
  U32.add(lo_hi, Bool.to_u32(u64.carried(lo, size)))

# lexicographic (hi, lo) comparisons, and EACH of the four words is read by at most
# one comparison so no word needs a `+` -- which is the reason these are written as
# `U32.is_gt(ah, bh)` rather than through a `Bool.pick` with a shared accumulator.
def u64.ge(+ah: U32, al: U32, +bh: U32, bl: U32) -> Bool:
  Bool.or(U32.is_gt(ah, bh), Bool.and(U32.is_eq(ah, bh), U32.is_ge(al, bl)))

def u64.lt(+ah: U32, al: U32, +bh: U32, bl: U32) -> Bool:
  Bool.or(U32.is_lt(ah, bh), Bool.and(U32.is_eq(ah, bh), U32.is_lt(al, bl)))

def u64.le.p2(ah: U32, al: U32, bh: U32, bl: U32) -> Bool:
  Bool.not(u64.lt(bh, bl, ah, al))

def u64.le(ah: U32, al: U32, bh: U32, bl: U32) -> Bool: u64.le.p2(ah, al, bh, bl)

# the THREE-comparison chain, in two words.
def face.in_va.p2(+lo_hi: U32, +lo: U32, +end_hi: U32, +end: U32) -> Bool:
  Bool.and(Bool.and(u64.ge(lo_hi, lo, AMD_VA_BASE_HI(), AMD_VA_BASE_LO()),
                    u64.lt(lo_hi, lo, end_hi, end)),
           u64.le(end_hi, end, AMD_VA_SPAN_HI(), AMD_VA_SPAN_LO()))

def face.in_va(+lo_hi: U32, +lo: U32, +size: U32) -> Bool:
  face.in_va.p2(lo_hi, lo, u64.end_hi(lo_hi, lo, size), U32.add(lo, size))

# ===========================================================================
# :359-363 -- `RemoteCmd`, `REMOTE_REQ`, `REMOTE_RESP`. THE TABLE, BOTH
# DIRECTIONS, AND THE SPLIT.
#
#   class RemoteCmd(enum.IntEnum):
#     PROBE,MAP_BAR,MAP_SYSMEM_FD,CFG_READ,CFG_WRITE,RESET,MMIO_READ,MMIO_WRITE,
#     MAP_SYSMEM,SYSMEM_READ,SYSMEM_WRITE,RESIZE_BAR,PING = range(13)
#     LOAD_PROG,EXEC_PROG,UNMAP_SYSMEM = range(13, 16)
#
# SIXTEEN members in TWO `range()` calls, and the second STARTS WHERE THE FIRST STOPS.
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

def Rcmd.base() -> U32: 13
def Rcmd.lo2() -> U32: 13
def Rcmd.hi2() -> U32: 16
def Rcmd.count() -> U32: 16

def Rcmd.names() -> List<&2, String>:
  ["PROBE", "MAP_BAR", "MAP_SYSMEM_FD", "CFG_READ", "CFG_WRITE", "RESET",
   "MMIO_READ", "MMIO_WRITE", "MAP_SYSMEM", "SYSMEM_READ", "SYSMEM_WRITE",
   "RESIZE_BAR", "PING", "LOAD_PROG", "EXEC_PROG", "UNMAP_SYSMEM"]

def Rcmd.maybe(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "?"

def Rcmd.name.at(ns: List<&2, String>, i: U32) -> String:
  Rcmd.maybe(List.get(&2, String, ns, U32.to_nat(i)))

# value -> name, with the SAME out-of-range answer as the mmap table so the two
# negative rows agree.
def Rcmd.name.of(+i: U32) -> String:
  Bool.pick(String, U32.is_ge(i, Rcmd.count()), "?", Rcmd.name.at(Rcmd.names(), i))

def Rcmd.name(i: U32) -> String: Rcmd.name.of(i)

# name -> value, and it is the REVERSE of the same list so the two cannot disagree.
# `Rcmd.of("PROBE")` is 0 and `Rcmd.of("UNMAP_SYSMEM")` is 15, and a name that
# is not in the table
# is `mapflag_missing()` rather than 0 -- which matters, because 0 IS a legal value
# (PROBE) and a "not found" of 0 would be indistinguishable from it.
def Rcmd.of.go(+s: String, ns: List<&2, String>, +at: U32) -> U32:
  match ns:
    case Nil{}: mapflag_missing()
    case h <> t:
      +nxt = U32.add(at, 1)
      Bool.pick(U32, String.eq(h, s), at, Rcmd.of.go(s, t, nxt))

def Rcmd.of(s: String) -> U32: Rcmd.of.go(s, Rcmd.names(), 0)

# A `U32` countdown as the FIRST argument is refused, and a `Nat` countdown cannot be
# read after the arm spends it (bend2-constraints.md, positions 6847 and 1404), so the
# countdown is a `Nat`, the list is the second scrutinee, and the arms cover the CROSS
# PRODUCT -- two bounds instead of one, which is the price and is the honest shape:
# take n of a list shorter than n is a real case here, because `Rcmd.second()` takes
# three of a list that could be shorter.
def list.take.go(n: Nat, xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match n xs:
    case 0n _a: acc
    case 1n+m Nil{}: acc
    case 1n+m h <> t: list.take.go(m, t, List.append(&2, String, acc, [h]))

def list.take(n: U32, xs: List<&2, String>) -> List<&2, String>:
  list.take.go(U32.to_nat(n), xs, Nil{})

def list.drop.go(n: Nat, xs: List<&2, String>) -> List<&2, String>:
  match n xs:
    case 0n _a: xs
    case 1n+m Nil{}: Nil{}
    case 1n+m _h <> t: list.drop.go(m, t)

def list.drop(n: U32, xs: List<&2, String>) -> List<&2, String>:
  list.drop.go(U32.to_nat(n), xs)

# the two `range()` calls, as the two halves of the table, TAKEN FROM THE SAME LIST
# rather than written out again -- a second literal of sixteen names would be a second
# table and the two could disagree.
def Rcmd.first() -> List<&2, String>: list.take(Rcmd.base(), Rcmd.names())

# `LOAD_PROG, EXEC_PROG, UNMAP_SYSMEM` are the last three and `range(13, 16)` produced
# them, so their INDICES are 13, 14, 15 and the lower bound is 13 again.
def Rcmd.second() -> List<&2, String>: list.drop(Rcmd.base(), Rcmd.names())

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
def REQ_SIZE() -> U32: 33
def RESP_SIZE() -> U32: 17
def REQ_FIELDS() -> List<&2, String>: ["cmd", "dev", "bar", "arg0", "arg1", "arg2"]
def RESP_FIELDS() -> List<&2, String>: ["status", "resp0", "resp1"]
def REQ_OFF_CMD() -> U32: 0
def REQ_OFF_DEV() -> U32: 1
def REQ_OFF_BAR() -> U32: 5
def REQ_OFF_ARG0() -> U32: 9
def REQ_OFF_ARG1() -> U32: 17
def REQ_OFF_ARG2() -> U32: 25
def RESP_OFF_STATUS() -> U32: 0
def RESP_OFF_RESP0() -> U32: 1
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

def POST_NSLOTS() -> U32: 3

# slot `i` of the padded triple.
def post.slot.pick(+i: U32, +n: U32, +a: U32) -> U32: Bool.pick(U32, U32.is_lt(i, n), a, 0)

def post.slot(i: U32, n: U32, a: U32) -> U32: post.slot.pick(i, n, a)

def post.slots.pick(+n: U32, +a0: U32, +a1: U32, +a2: U32) -> List<&2, U32>:
  [post.slot(0, n, a0), post.slot(1, n, a1), post.slot(2, n, a2)]

# THE CLAMP IS A THEOREM, and M27 measured it: returning `n` unchanged moves no row,
# because the only indices that exist are 0, 1 and 2 and `i < min(n, 3)` and `i < n`
# agree on all three. `post.slot` already enforces `[:3]` by its own test, so this
# def is redundant and is kept only because the `[:3]` is visible in the source it
# ports. Rule 8's leaf sweep would delete it; the theorem is why deleting it is safe.
def post.nclamp(+n: U32) -> U32: Bool.pick(U32, U32.is_ge(n, POST_NSLOTS()), POST_NSLOTS(), n)

def post.slots(n: U32, a0: U32, a1: U32, a2: U32) -> List<&2, U32>:
  post.slots.pick(post.nclamp(n), a0, a1, a2)

# the SIX arities and their padded triples, as rows. The last two are the negative
# cases and they are the reason this rule is gated at all.
def post.n0(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(0, a0, a1, a2)
def post.n1(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(1, a0, a1, a2)
def post.n2(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(2, a0, a1, a2)
def post.n3(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(3, a0, a1, a2)
def post.n4(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(4, a0, a1, a2)
def post.n5(a0: U32, a1: U32, a2: U32) -> List<&2, U32>: post.slots(5, a0, a1, a2)

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

def FMT_CHARS() -> List<&2, String>: ["B", "H", "I", "L", "Q", "b", "h", "i", "q", "f", "d"]
def FMT_SIZES() -> List<&2, U32>: [1, 2, 4, 8, 8, 1, 2, 4, 8, 4, 8]

def elemsize.go(fmts: List<&2, String>, sizes: List<&2, U32>, +c: String, +at: U32) -> U32:
  match fmts:
    case Nil{}: mapflag_missing()
    case h <> t:
      match sizes:
        case Nil{}: mapflag_missing()
        case z <> u:
          +nxt = U32.add(at, 1)
          Bool.pick(U32, String.eq(h, c), at, elemsize.go(t, u, c, nxt))

# THE SIZE, because `struct.calcsize` is a SIZE. The first version answered the INDEX
# and every row name promised a size, so `sy_el_B` printed 0 next to a row called
# `sy_el_B` -- a gate that reads as "the element size of B is 0". `elemsize` is the
# value and `elemsize.at` is the index, and the gate asks both.
def elemsize.at(c: String) -> U32: elemsize.go(FMT_CHARS(), FMT_SIZES(), c, 0)

def elemsize.maybe(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

# THE ABSENT ANSWER IS 0, AND THAT IS SAFE BECAUSE EVERY LEGAL SIZE IS >= 1 -- the
# format table has no zero row. The INDEX direction uses the 4294967295 sentinel
# instead, and `sy_el_absent` and `sy_eli_absent` are the two rows that say so.
def elemsize(c: String) -> U32: elemsize.maybe(List.get(&2, U32, FMT_SIZES(), U32.to_nat(elemsize.at(c))))

# `st` and `en` in BYTES. `st = (sl.start or 0) * el` and
# `en = (len(self) if sl.stop is None else sl.stop) * el`, so an absent stop is the WHOLE
# view in ELEMENTS and then scaled. `nbytes` is `len(self)`.
def rmm.st.pick(+start: U32, +el: U32) -> U32: Bool.pick(U32, U32.is_zero(start), 0, U32.mul(start, el))

def rmm.st(start: U32, el: U32) -> U32: rmm.st.pick(start, el)

def rmm.en.pick(+stop: U32, +nbytes: U32, +el: U32) -> U32:
  Bool.pick(U32, U32.is_zero(stop), U32.mul(nbytes, el), U32.mul(stop, el))

def rmm.en(stop: U32, nbytes: U32, el: U32) -> U32: rmm.en.pick(stop, nbytes, el)

# `(en - st) // el` -- the ITEM COUNT, and it is only total for `st <= en`. A reversed
# slice gives a negative count in Python and `struct.unpack` then raises; in U32 the
# subtraction WRAPS to a huge positive and the port would ask for a four-gigabyte
# unpack. `rmm.count` is gated on the ordered fixtures and the reversal is named as a
# WALL rather than approximated.
def rmm.count(st: U32, +en: U32, +el: U32) -> U32: U32.div(U32.sub(en, st), el)

# :369-370 the INT arm: `sl = slice(k, k + 1)`, so `st = k * el` and `en = (k + 1) * el`.
# MEASURED: k=3 with el=1 gives st=3 en=4.
def rmm.int_st(k: U32, el: U32) -> U32: U32.mul(k, el)
def rmm.int_en(k: U32, el: U32) -> U32: U32.mul(U32.add(k, 1), el)

# :372 the cmd choice, and the ADDRESS with it: sysmem uses `self.addr` and the node's
# memory space, everything else uses `self.off` and the BAR's. Getting these two the
# wrong way round reads the right bytes from the wrong place.
def CMD_MMIO_READ() -> U32: 6
def CMD_SYSMEM_READ() -> U32: 9
def CMD_MMIO_WRITE() -> U32: 7
def CMD_SYSMEM_WRITE() -> U32: 10

def rmm.read_cmd(+sysmem: Bool) -> U32: Bool.pick(U32, sysmem, CMD_SYSMEM_READ(), CMD_MMIO_READ())
def rmm.write_cmd(+sysmem: Bool) -> U32: Bool.pick(U32, sysmem, CMD_SYSMEM_WRITE(), CMD_MMIO_WRITE())
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
# THE SOCKET OPTIONS ARE A THREE-CALL SEQUENCE with a LOOP over two options that share
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

def REMOTE_DEFAULT_PORT() -> U32: 6667
def REMOTE_TIMEOUT() -> U32: 60
def SOCK_BUF() -> U32: 67108864                    # 64 << 20
def SOL_SOCKET() -> U32: 65535
def SO_SNDBUF() -> U32: 4097
def SO_RCVBUF() -> U32: 4098
def IPPROTO_TCP() -> U32: 6
def TCP_NODELAY() -> U32: 1
def NODELAY_ON() -> U32: 1

# :400 `if r == "local"`. A bare `Bool` and not a `String` on the wire, so the gate can
# ask the question without building the string.
def rpc.is_local(r: String) -> Bool: String.eq(r, "local")

# :402 `int(r.split(":")[1]) if ":" in r else 6667`. The colon test is the WHOLE of the
# default and it is on the ENTRY, not on the field.
def rpc.port.pick(+has_colon: Bool, +port: U32) -> U32:
  Bool.pick(U32, has_colon, port, REMOTE_DEFAULT_PORT())

def rpc.port(has_colon: Bool, port: U32) -> U32: rpc.port.pick(has_colon, port)

# :406 `f"remote:{host}:{port}:{d}"` -- FOUR colon-separated fields, and `d` is the
# device the node reported, not the one that was asked for.
def rpc.device_name(+host: String, port: U32, +d: String) -> String:
  String.concat(["remote:", host, ":", U32.show(port), ":", d])

# :393 the two buffer options, in order, with their ONE shared value.
def rpc.buf_opts() -> List<&2, U32>: [SO_SNDBUF(), SO_RCVBUF()]

# :392-393 the whole option sequence, as a trace. THREE setsockopt calls: the NODELAY
# one and the two buffer ones, IN THAT ORDER.
def rpc.opts(os: List<&2, U32>, +t: Tr) -> Tr:
  match os:
    case Nil{}: t
    case o <> u: rpc.opts(u, Tr.emit(CALL_SETSOCKOPT(), SOL_SOCKET(), U32.show(o), t))

def rpc.options(t: Tr) -> Tr: rpc.opts(rpc.buf_opts(),
  Tr.emit(CALL_SETSOCKOPT(), IPPROTO_TCP(), "TCP_NODELAY", t))

# ===========================================================================
# :454 -- `if DEV.interface.startswith("MOCK"): from test.mockgpu.mockgpu import
# MockFileIOInterface as FileIOInterface`. A MODULE REBIND keyed on the interface name,
# and the only reader of `DEV.interface` in this file. It replaces the WHOLE class, so
# every `FileIOInterface(...)` above it becomes a mock and every path in this file stops
# being read. The port keeps the PREDICATE and names the rebind as a wall, because a
# gate cannot check "which class object is bound to a name".
# TODO(p3) runtime/support/system.py:454 -- the MockFileIOInterface rebind.
# ===========================================================================

def MOCK_HEADS() -> List<&2, String>: ["MOCK"]

def sys.is_mock(head: String) -> Bool: List.contains(String, String.eq, MOCK_HEADS(), head)


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
def VA_LO() -> U32: 0
def VA_LO2() -> U32: 4096

# 0x7f0000100000 is the alloc_sysmem `vaddr` fixture, and its LOW word is 1048576 --
# nonzero, which is the point. Using VA_LO() (whose low word is 0) for a `vaddr`
# argument made `alloc.fixed` answer 0 and every MAP_FIXED row read as "unset".
def VA_ADDR_LO() -> U32: 1048576
def VA_SZ() -> U32: 0                              # 68719476736 == 16 << 32: the low word is 0
def BUS() -> String: "0000:03:00.0"
def BUS2() -> String: "c1:00.0"
def DEV_AMD() -> String: "amd"
def DEV_AM() -> String: "am"
def DEV_CPU() -> String: "cpu"
# TWO PREFIXES FOR TWO SITES. `pci.lock_name` (:208) gets the devpref already
# lowercased, because the two `lower()` calls are the seam's; `pci.class_prefix`
# (:136) gets the DEVICE HEAD, which is uppercase, and takes its first two
# characters. MEASURED: 'am' and 'AMD' both lock to 'am_0000:03:00.0.lock' but only
# 'AMD' has the class prefix 'AM'.
def HEAD_AMD() -> String: "AMD"
def HEAD_NPU() -> String: "NPU"
def HOST() -> String: "10.0.0.1"
def LOCKPATH() -> String: "/tmp/unique/am_0000:03:00.0.lock"

# the twelve `Cfg` field/offset values, printed as ONE string per write so the
# whole argument tuple is in the diff and not just one field of it.
def cfgs.pick(+c: Cfg, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, [String.concat([U32.show(Cfg.byte_addr(c)), "/",
    U32.show(Cfg.bus(c)), "/", U32.show(Cfg.dev(c)), "/", U32.show(Cfg.fn(c)), "/",
    U32.show(Cfg.value(c)), "/", U32.show(Cfg.size(c)), "/", Bool.show(Cfg.is_write(c))])])

def cfgs.go(xs: List<&2, Cfg>, +acc: List<&2, String>) -> String:
  match xs:
    case Nil{}: String.join(acc, " ")
    case c <> t: cfgs.go(t, cfgs.pick(c, acc))

def cfgs(xs: List<&2, Cfg>) -> String: cfgs.go(xs, Nil{})

def t_01_caps() -> IO(Unit):
  do IO<Unit>:
    # --- :50-51 the two platform-dependent constants, BOTH arms
    urow("sy_map_locked_linux", cap.locked_of(CAP_NO()))
    urow("sy_map_locked_osx", cap.locked_of(CAP_YES()))
    urow("sy_map_populate_linux", cap.populate_of(CAP_NO()))
    urow("sy_map_populate_osx", cap.populate_of(CAP_YES()))
    urow("sy_map_populate_from_linux", cap.populate_from(CAP_NO()))
    urow("sy_map_populate_from_osx", cap.populate_from(CAP_YES()))
    urow("sy_map_anon_linux", MAP_ANONYMOUS_LINUX())
    urow("sy_map_anon_osx", MAP_ANONYMOUS_OSX())
    urow("sy_va_flags_linux", VA_FLAGS_LINUX())
    urow("sy_va_flags_osx", VA_FLAGS_OSX())
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

def t_02_gid() -> IO(Unit):
  do IO<Unit>:
    urow("sy_gid_len", gid.len())
    urow("sy_gid_prefix_len", gid.PREFIX_LEN())
    urow("sy_gid_tail_len", gid.TAIL_LEN())
    srow("sy_gid_prefix", gid.PREFIX_HEX())
    # the four tail bytes are the seam's, so the two rows below are the PREFIX
    # with a tail bolted on -- and they pin the ORDER, which a length cannot.
    srow("sy_gid_7f000001", gid.of(2130706433))
    srow("sy_gid_0a000001", gid.of(167772161))
    srow("sy_gid_ffffffff", gid.of(4294967295))
    srow("sy_gid_00000000", gid.of(0))
    srow("sy_gid_c0a801ff", gid.of(3232236031))
    # the %x formatter, which the GID and the OSX id both use
    srow("sy_hx_1002", hx.q(4098))
    srow("sy_hx_744c", hx.q(29772))
    srow("sy_hx_0", hx.q(0))
    srow("sy_hx_f", hx.q(15))
    srow("sy_hx_10", hx.q(16))
    srow("sy_hx_ff", hx.q(255))
    srow("sy_hx_100", hx.q(256))
    srow("sy_hx_1000", hx.q(4096))
    srow("sy_hx_ffff", hx.q(65535))
    urow("sy_hx_width_0", hx.width(0))
    urow("sy_hx_width_15", hx.width(15))
    urow("sy_hx_width_16", hx.width(16))
    urow("sy_hx_width_255", hx.width(255))
    urow("sy_hx_width_256", hx.width(256))
    urow("sy_hx_width_4095", hx.width(4095))
    urow("sy_hx_width_4096", hx.width(4096))
    srow("sy_hx_d4_1002", hx.d4(4098))

# --- :392-393 the socket option SEQUENCE, as a trace --------------------------
# --- Tr.has's NEGATIVE cases. M48 hard-wires the matcher to True{} and this
# function moved NOTHING until these three rows existed: every order row in this file
# was `True` in the baseline, so the whole matcher was unfalsifiable. That is the
# `ops_webgpu` M23 lesson arriving again, and the harness is what found it.
def t_11_has() -> IO(Unit):
  do IO<Unit>:
    row("sy_has_present", Tr.has([Call{CALL_MMAP, 1, "a"}, Call{CALL_SYSTEM, 2, "b"}],
      [Call{CALL_SYSTEM, 2, "b"}]))
    row("sy_has_absent", Tr.has([Call{CALL_MMAP, 1, "a"}], [Call{CALL_SYSTEM, 2, "b"}]))
    # the REVERSED pattern: the same two calls, the other way round
    row("sy_has_reversed", Tr.has([Call{CALL_MMAP, 1, "a"}, Call{CALL_SYSTEM, 2, "b"}],
      [Call{CALL_SYSTEM, 2, "b"}, Call{CALL_MMAP, 1, "a"}]))
    # the right kinds in the right order, but the WRONG argument
    row("sy_has_wrong_arg", Tr.has([Call{CALL_MMAP, 1, "a"}], [Call{CALL_MMAP, 2, "a"}]))
    # the right argument, the wrong STRING -- the half a `U32` slot could not carry
    row("sy_has_wrong_str", Tr.has([Call{CALL_MMAP, 1, "a"}], [Call{CALL_MMAP, 1, "b"}]))

def t_11_pagemask() -> IO(Unit):
  do IO<Unit>:
    # WALL 1's two words, read so the constants are not dead (rule 8: an unread
    # constant is not a port). M4 perturbed the HIGH word and moved NOTHING until
    # these two rows existed.
    urow("sy_pageframe_hi", PAGEFRAME_MASK_HI())
    urow("sy_pageframe_lo", PAGEFRAME_MASK_LO())
    row("sy_pageframe_differs", Bool.not(U32.is_eq(PAGEFRAME_MASK_HI(), PAGEFRAME_MASK_LO())))

def t_11_sock_n() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, rpc.options(Tr.of()))
    urow("sy_sock_nopts", Tr.count(CALL_SETSOCKOPT(), Tr.calls(a)))

def t_11_sock_arg() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, rpc.options(Tr.of()))
    urow("sy_sock_nodelay_arg", first_arg(CALL_SETSOCKOPT(), Tr.calls(a)))

def t_11_sock_str() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, rpc.options(Tr.of()))
    srow("sy_sock_opts_str", sxs(Tr.strs(CALL_SETSOCKOPT(), Tr.calls(a))))
    lrow("sy_sock_args", Tr.args(CALL_SETSOCKOPT(), Tr.calls(a)))

# --- :36/:42 the mmap / munmap seam -------------------------------------------
def t_11_libs_trace() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, cap.load_sys(cap.load(Tr.of())))
    srow("sy_lib_trace", sxs(Tr.strs(CALL_CDLL(), Tr.calls(a))))
    urow("sy_lib_ncdll", Tr.count(CALL_CDLL(), Tr.calls(a)))

# --- :50-51 the two PLATFORM flag tables side by side ------------------------
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
def t_03_libs() -> IO(Unit):
  do IO<Unit>:
    urow("sy_lib_linux_atomic", cap.barrier_lib(CAP_NO(), True{}, False{}))
    urow("sy_lib_linux_noatomic", cap.barrier_lib(CAP_NO(), False{}, False{}))
    urow("sy_lib_osx_sys", cap.barrier_lib(CAP_YES(), False{}, True{}))
    urow("sy_lib_osx_nosys", cap.barrier_lib(CAP_YES(), False{}, False{}))
    # THE NEGATIVE CASE: OSX with an atomic library present must NOT consult it.
    urow("sy_lib_osx_atomic_ignored", cap.barrier_lib(CAP_YES(), True{}, False{}))
    row("sy_fence_linux", cap.fences(cap.barrier_lib(CAP_NO(), True{}, False{})))
    row("sy_fence_osx", cap.fences(cap.barrier_lib(CAP_YES(), False{}, True{})))
    row("sy_nofence_linux", cap.fences(cap.barrier_lib(CAP_NO(), False{}, False{})))
    row("sy_nofence_osx", cap.fences(cap.barrier_lib(CAP_YES(), False{}, False{})))
    row("sy_atomic_on_linux", cap.atomic_on(CAP_NO()))
    row("sy_atomic_on_osx", cap.atomic_on(CAP_YES()))
    t_11_libs_trace()

def t_04_write_ok() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, sysfs.apply(PAGEMAP_SYSFS(), PAGEMAP_VALUE(), "", True{}, True{}, Tr.of()))
    urow("sy_write_ok_nsys", Tr.count(CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_ok_nread", Tr.count(CALL_READ(), Tr.calls(t)))
    row("sy_write_ok_read", Tr.has(Tr.calls(t), [Call{CALL_READ, 0, PAGEMAP_SYSFS()}]))
    row("sy_write_ok_refused", Tr.refused(t))

def t_04_write_retry() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, sysfs.apply("/x", "1", "", False{}, True{}, Tr.of()))
    urow("sy_write_retry_nsys", Tr.count(CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_retry_nread", Tr.count(CALL_READ(), Tr.calls(t)))
    urow("sy_write_retry_nopen", Tr.count(CALL_OPEN(), Tr.calls(t)))
    row("sy_write_retry_cmd", Tr.has(Tr.calls(t), [Call{CALL_SYSTEM, 0, "sudo sh -c 'echo 1 > /x'"}]))
    row("sy_write_retry_refused", Bool.not(Tr.refused(t)))

def t_04_write_fail() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, sysfs.apply("/x", "1", "", False{}, False{}, Tr.of()))
    row("sy_write_fail_refused", Tr.refused(t))
    urow("sy_write_fail_nsys", Tr.count(CALL_SYSTEM(), Tr.calls(t)))
    urow("sy_write_fail_nread", Tr.count(CALL_READ(), Tr.calls(t)))

def t_04_sysfs() -> IO(Unit):
  do IO<Unit>:
    # --- WALL 2: THE STRING, diffed BESIDE CPython's and never as a boolean
    srow("sy_echo_pagemap", sysfs.echo(PAGEMAP_VALUE(), PAGEMAP_SYSFS()))
    srow("sy_echo_enable", sysfs.echo("1", pci.path(BUS(), pci.tail(0))))
    srow("sy_echo_reset", sysfs.echo("1", pci.path(BUS(), pci.tail(9))))
    urow("sy_echo_len_pagemap", U32.from_nat(List.length(&2, Char, String.to_list(sysfs.echo(PAGEMAP_VALUE(), PAGEMAP_SYSFS())))))
    urow("sy_echo_len_enable", U32.from_nat(List.length(&2, Char, String.to_list(sysfs.echo("1", pci.path(BUS(), pci.tail(0)))))))
    srow("sy_modprobe", VFIO_MODPROBE())
    # --- :57 `(expected or value)`, a TRUTHINESS rule
    srow("sy_want_none", sysfs.want("", "0"))
    srow("sy_want_empty_is_falsy", sysfs.want("", "1"))
    srow("sy_want_set", sysfs.want("y", "0"))
    row("sy_match_same", sysfs.matches("0", "", "0"))
    row("sy_match_diff", sysfs.matches("1", "", "0"))
    t_04_write_ok()
    t_04_write_retry()
    t_04_write_fail()

# --- :84-87 `reserve_va`: the NEGATIVE CASE IS IN THE PYTHON SOURCE -----------
def t_05_va() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.reserve_va(VA_LO(), VA_SZ(), CAP_NO(), Tr.of()))
    urow("sy_va_first_nmmap", Tr.count(CALL_MMAP(), Tr.calls(a)))
    urow("sy_va_first_flags", first_arg(CALL_MMAP(), Tr.calls(a)))
    +b : Tr <- IO.pure(Tr, sys.reserve_va(VA_LO(), VA_SZ(), CAP_NO(), a))
    urow("sy_va_cached_nmmap", Tr.count(CALL_MMAP(), Tr.calls(b)))
    urow("sy_va_nreserved", U32.from_nat(List.length(&2, U32, Tr.reserved(b))))
    +c : Tr <- IO.pure(Tr, sys.reserve_va(VA_LO2(), VA_SZ(), CAP_NO(), b))
    urow("sy_va_other_nmmap", Tr.count(CALL_MMAP(), Tr.calls(c)))
    urow("sy_va_nreserved2", U32.from_nat(List.length(&2, U32, Tr.reserved(c))))

def t_05_va_osx() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.reserve_va(VA_LO(), VA_SZ(), CAP_YES(), Tr.of()))
    urow("sy_va_osx_first", Tr.count(CALL_MMAP(), Tr.calls(a)))
    urow("sy_va_osx_flags", first_arg(CALL_MMAP(), Tr.calls(a)))

# --- :67-70 `pagemap`, also a cached_property ---------------------------------
def t_05_pagemap() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.pagemap(True{}, Tr.of()))
    +b : Tr <- IO.pure(Tr, sys.pagemap(False{}, a))
    urow("sy_pagemap_first", Tr.count(CALL_OPEN(), Tr.calls(a)))
    urow("sy_pagemap_cached", Tr.count(CALL_OPEN(), Tr.calls(b)))
    urow("sy_pagemap_total_reads", Tr.count(CALL_READ(), Tr.calls(b)))
    # :69 writes the sysfs knob BEFORE :70 opens /proc/self/pagemap, so the READ
    # comes FIRST. The row had them the other way round and was satisfied by
    # `Tr.has` returning False for a reason that had nothing to do with the paths.
    row("sy_pagemap_order", Tr.has(Tr.calls(b), [Call{CALL_READ, 0, PAGEMAP_SYSFS()}, Call{CALL_OPEN, 0, PAGEMAP_PATH()}]))

# --- :91-92 `lock_memory`: a NONZERO return is the refusal --------------------
def t_05_lock_ok() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.lock_memory(0, 4096, 0, Tr.of()))
    row("sy_lock_ok", Bool.not(Tr.refused(a)))
    row("sy_lock_ok_kind", Tr.has(Tr.calls(a), [Call{CALL_MLOCK_OK, 4096, ""}]))

def t_05_lock_fail() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.lock_memory(0, 4096, 1, Tr.of()))
    row("sy_lock_fail", Tr.refused(a))
    urow("sy_lock_fail_n", Tr.count(CALL_MLOCK(), Tr.calls(a)))

def t_05_cache() -> IO(Unit):
  do IO<Unit>:
    t_05_va()
    t_05_va_osx()
    t_05_pagemap()
    t_05_lock_ok()
    t_05_lock_fail()

# --- :98-102 `alloc_sysmem` ---------------------------------------------------
def t_06_alloc_huge() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.alloc_sysmem(8192, 0, True{}, 4096, Tr.of()))
    row("sy_alloc_mmap_2p", Tr.has(Tr.calls(a), [Call{CALL_MMAP, ALLOC_HUGE_VADDR0(), ""}]))
    urow("sy_alloc_mmap_n", Tr.count(CALL_MMAP(), Tr.calls(a)))

def t_06_alloc_fixed() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.alloc_sysmem(8192, VA_ADDR_LO(), True{}, 4096, Tr.of()))
    urow("sy_alloc_mmap_huge_fixed", first_arg(CALL_MMAP(), Tr.calls(a)))

def t_06_alloc_plain() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.alloc_sysmem(4096, VA_ADDR_LO(), False{}, 4096, Tr.of()))
    urow("sy_alloc_mmap_plain", first_arg(CALL_MMAP(), Tr.calls(a)))

# the REFUSAL TRUNCATES BEFORE the mmap, so the trace shows no MAP at all.
def t_06_alloc_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, sys.alloc_sysmem(1073741824, 0, True{}, 4096, Tr.of()))
    row("sy_alloc_refused", Tr.refused(a))
    urow("sy_alloc_refused_nmmap", Tr.count(CALL_MMAP(), Tr.calls(a)))

def t_06_alloc() -> IO(Unit):
  do IO<Unit>:
    # --- :99 the assert
    row("sy_alloc_ok_2m", alloc.ok(2097152, True{}))
    row("sy_alloc_ok_2m1", alloc.ok(2097153, True{}))
    row("sy_alloc_ok_1g_not_contig", alloc.ok(1073741824, False{}))
    # --- :100 the WALRUS: rounded ONLY when contiguous
    urow("sy_alloc_size_1000_contig", alloc.size(4096, True{}, 4096))
    urow("sy_alloc_size_1000_plain", alloc.size(4096, False{}, 4096))
    urow("sy_alloc_size_1001_contig", alloc.size(4097, True{}, 4096))
    urow("sy_alloc_size_1001_plain", alloc.size(4097, False{}, 4096))
    urow("sy_alloc_size_2000_contig", alloc.size(8192, True{}, 4096))
    urow("sy_alloc_size_1000000_contig", alloc.size(16777216, True{}, 4096))
    # --- the flags, term by term
    urow("sy_alloc_huge_1page", alloc.huge(4096, True{}, 4096))
    urow("sy_alloc_huge_2page", alloc.huge(8192, True{}, 4096))
    urow("sy_alloc_huge_not_contig", alloc.huge(8192, False{}, 4096))
    urow("sy_alloc_fixed_0", alloc.fixed(0))
    urow("sy_alloc_fixed_nz", alloc.fixed(VA_ADDR_LO()))
    urow("sy_alloc_flags_2000_0", alloc.flags(8192, True{}, 0, 4096))
    urow("sy_alloc_flags_2000_nz", alloc.flags(8192, True{}, VA_ADDR_LO(), 4096))
    urow("sy_alloc_flags_1000_nz", alloc.flags(4096, False{}, VA_ADDR_LO(), 4096))
    urow("sy_mmap_base", MMAP_BASE_LINUX())
    t_06_alloc_huge()
    t_06_alloc_fixed()
    t_06_alloc_plain()
    t_06_alloc_refuse()

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
    row("sy_term_amd_744c", scan.term(29772, AMD_MASK(), amd_ids()))
    row("sy_term_amd_75b4", scan.term(30132, AMD_MASK(), amd_ids()))
    row("sy_term_nv_2f01", scan.term(12033, NV_MASK(), nv_ids()))
    urow("sy_namd", U32.from_nat(List.length(&2, U32, amd_ids())))
    urow("sy_nnv", U32.from_nat(List.length(&2, U32, nv_ids())))
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
    urow("sy_capid_15", scan.cap_id(21))
    urow("sy_capid_ff15", scan.cap_id(65301))
    urow("sy_capid_1001", scan.cap_id(4097))
    urow("sy_capid_2100", scan.cap_id(8448))
    urow("sy_capid_1500", scan.cap_id(5376))
    row("sy_is_rebar_15", scan.is_rebar(21))
    row("sy_is_rebar_ff15", scan.is_rebar(65301))
    row("sy_is_rebar_1001", scan.is_rebar(4097))
    row("sy_is_rebar_2100", scan.is_rebar(8448))
    row("sy_is_rebar_1500", scan.is_rebar(5376))
    row("sy_is_rebar_1501", scan.is_rebar(5377))
    urow("sy_rebar_capid", PCI_EXT_CAP_ID_REBAR())

def t_08_bars() -> IO(Unit):
  do IO<Unit>:
    # --- (a) the EIGHT writes, in order, whole argument tuples
    srow("sy_buses_0", U32.show(bars.buses(0, 4)))
    srow("sy_buses_1", U32.show(bars.buses(1, 4)))
    srow("sy_buses_2", U32.show(bars.buses(2, 4)))
    srow("sy_buses_3", U32.show(bars.buses(3, 4)))
    srow("sy_writes_bus0", cfgs(bars.writes(0)))
    srow("sy_writes_bus3", cfgs(bars.writes(3)))
    urow("sy_nwrites", U32.from_nat(List.length(&2, Cfg, bars.writes(0))))
    urow("sy_membase16", bars.mem_base16(MEM_BASE_USB()))
    urow("sy_prefbase16", bars.pref_base16(PREF_BASE_HI(), PREF_BASE_LO()))
    urow("sy_prefbasehi", bars.pref_base_hi(PREF_BASE_HI(), PREF_BASE_LO()))
    # --- (b) the REBAR rewrite
    urow("sy_rebar_1001_201", bars.rebar(513, 4097))
    urow("sy_rebar_2100_201", bars.rebar(513, 8448))
    urow("sy_rebar_1_201", bars.rebar(513, 1))
    urow("sy_rebar_size_1001", bars.rebar_size(4097))
    urow("sy_rebar_size_2100", bars.rebar_size(8448))
    urow("sy_rebar_mask", REBAR_CTRL_MASK())
    urow("sy_bitlen_0", hx.bitlen(0))
    urow("sy_bitlen_1", hx.bitlen(1))
    urow("sy_bitlen_10", hx.bitlen(16))
    urow("sy_bitlen_ff", hx.bitlen(255))
    urow("sy_bitlen_100", hx.bitlen(256))
    urow("sy_bitlen_10000", hx.bitlen(65536))
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
def t_09_probe() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, pci.probe(BUS(), False{}, False{}, Tr.of()))
    srow("sy_pci_opens", sxs(Tr.strs(CALL_OPEN(), Tr.calls(a))))
    urow("sy_pci_nopen", Tr.count(CALL_OPEN(), Tr.calls(a)))
    urow("sy_pci_nwrite", Tr.count(CALL_WRITE(), Tr.calls(a)))
    urow("sy_pci_nexists", Tr.count(CALL_EXISTS(), Tr.calls(a)))
    row("sy_pci_order_ok", Tr.has(Tr.calls(a), [Call{CALL_EXISTS, 0, pci.path(BUS(), pci.tail(1))},
      Call{CALL_WRITE, 1, pci.path(BUS(), pci.tail(2))},
      Call{CALL_WRITE, 1, pci.sib_path(BUS(), 1)}]))
    srow("sy_pci_sibs", sxs(sib.paths(BUS())))

def t_09_probe_bound() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, pci.probe(BUS(), True{}, False{}, Tr.of()))
    row("sy_pci_bound_refused", Tr.refused(a))
    urow("sy_pci_bound_nopen", Tr.count(CALL_OPEN(), Tr.calls(a)))

def t_09_probe_vfio() -> IO(Unit):
  do IO<Unit>:
    +a : Tr <- IO.pure(Tr, pci.probe(BUS(), False{}, True{}, Tr.of()))
    row("sy_pci_vfio", Tr.has(Tr.calls(a), [Call{CALL_WRITE, 1, pci.path(BUS(), pci.tail(3))}]))

def t_09_pci() -> IO(Unit):
  do IO<Unit>:
    # --- the sysfs PATH TABLE, and every tail diffed as a string
    srow("sy_path_enable", pci.path(BUS(), pci.tail(0)))
    srow("sy_path_driver", pci.path(BUS(), pci.tail(1)))
    srow("sy_path_unbind", pci.path(BUS(), pci.tail(2)))
    srow("sy_path_override", pci.path(BUS(), pci.tail(3)))
    srow("sy_path_config", pci.path(BUS(), pci.tail(4)))
    srow("sy_path_iommu", pci.path(BUS(), pci.tail(5)))
    srow("sy_path_reset", pci.path(BUS(), pci.tail(9)))
    srow("sy_path_bus2", pci.path(BUS2(), pci.tail(0)))
    srow("sy_bar0", pci.bar_path(BUS(), 0))
    srow("sy_bar2", pci.bar_path(BUS(), 2))
    srow("sy_bar2_resize", pci.resize_path(BUS(), 2))
    srow("sy_bus_trim", pci.bus_trim(BUS()))
    urow("sy_bus_len", pci.bus_len(BUS()))
    srow("sy_sib1", pci.sib_path(BUS(), 1))
    srow("sy_sib7", pci.sib_path(BUS(), 7))
    urow("sy_sib_n", sib.n())
    srow("sy_iommu_path", pci.iommu_path(18))
    # --- the OPEN FLAGS, and a wrong flag is a silently wrong open
    urow("sy_flag_enable", pci.flags_enable())
    urow("sy_flag_unbind", pci.flags_unbind())
    urow("sy_flag_config", pci.flags_config())
    urow("sy_flag_bar", pci.flags_bar())
    urow("sy_flag_resource", pci.flags_resource())
    urow("sy_flag_resize", pci.flags_resize())
    urow("sy_o_rdwr_sync_cloexec", O_RDWR_SYNC_CLOEXEC())
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
def t_10_meta() -> IO(Unit):
  do IO<Unit>:
    +m : Meta <- IO.pure(Meta, meta.sysmem(512))
    row("sy_meta_sysmem_cpu", Meta.has_cpu_mapping(m))
    urow("sy_meta_sysmem_hmem", Meta.hMemory(m))
    +n : Meta <- IO.pure(Meta, meta.bar(1024, False{}))
    row("sy_meta_bar_cpu", Meta.has_cpu_mapping(n))
    urow("sy_meta_bar_hmem", Meta.hMemory(n))
    +o : Meta <- IO.pure(Meta, meta.bar(7, True{}))
    row("sy_meta_bar_cpu_true", Meta.has_cpu_mapping(o))
    urow("sy_meta_bar_hmem_true", Meta.hMemory(o))

def t_10_face() -> IO(Unit):
  do IO<Unit>:
    # --- :297 the `getattr` fallback, BOTH directions
    row("sy_pg_explicit_pci", Bool.not(face.has_explicit(KIND_PCI())))
    row("sy_pg_explicit_usb", face.has_explicit(KIND_USB()))
    row("sy_pg_explicit_remote", face.has_explicit(KIND_REMOTE()))
    srow("sy_pg_pci", face.peer_group(KIND_PCI(), BUS(), HOST(), 6667))
    srow("sy_pg_usb", face.peer_group(KIND_USB(), BUS(), HOST(), 6667))
    srow("sy_pg_remote", face.peer_group(KIND_REMOTE(), BUS(), HOST(), 6667))
    srow("sy_pg_fallback_pci", face.peer_group_fallback(KIND_PCI()))
    srow("sy_pg_fallback_usb", face.peer_group_fallback(KIND_USB()))
    srow("sy_pg_usb_direct", face.peer_group_usb(BUS()))
    srow("sy_pg_remote_direct", face.peer_group_remote(HOST(), 1))
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
    urow("sy_align_big", face.devmem_align(8388608))
    urow("sy_align_big1", face.devmem_align(8388609))
    urow("sy_align_just_under", face.devmem_align(8388607))
    urow("sy_align_small", face.devmem_align(4097))
    urow("sy_align_tiny", face.devmem_align(1))
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
    row("sy_inva_lo", face.in_va(AMD_VA_BASE_HI(), 4096, 8192))
    row("sy_inva_base", face.in_va(AMD_VA_BASE_HI(), 0, 8192))
    row("sy_inva_below", face.in_va(U32.sub(AMD_VA_BASE_HI(), 1), 4294967295, 8192))
    row("sy_inva_tiny", face.in_va(0, 80, 8192))
    row("sy_inva_carry", face.in_va(AMD_VA_BASE_HI(), 4294967292, 8192))
    row("sy_carry_detect", u64.carried(4294967292, 8192))
    urow("sy_va_bits", AMD_VA_BITS())
    urow("sy_va_base_hi", AMD_VA_BASE_HI())
    urow("sy_va_span_hi", AMD_VA_SPAN_HI())
    t_10_meta()

def t_11_remote() -> IO(Unit):
  do IO<Unit>:
    # --- :359-361 the SIXTEEN names, both directions
    urow("sy_rcmd_n", Rcmd.count())
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
    urow("sy_rcmd_base", Rcmd.base())
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
    urow("sy_eli_B", elemsize.at("B"))
    urow("sy_eli_Q", elemsize.at("Q"))
    urow("sy_eli_absent", elemsize.at("Z"))
    urow("sy_fmt_n", U32.from_nat(List.length(&2, String, FMT_CHARS())))
    urow("sy_fmt_nsize", U32.from_nat(List.length(&2, U32, FMT_SIZES())))
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
    lrow("sy_sock_opts", rpc.buf_opts())
    urow("sy_sock_buf", SOCK_BUF())
    urow("sy_sock_sndbuf", SO_SNDBUF())
    urow("sy_sock_rcvbuf", SO_RCVBUF())
    urow("sy_sock_sol", SOL_SOCKET())
    urow("sy_sock_ipproto", IPPROTO_TCP())
    urow("sy_sock_nodelay", TCP_NODELAY())
    urow("sy_remote_timeout", REMOTE_TIMEOUT())
    urow("sy_remote_port", REMOTE_DEFAULT_PORT())
    # --- the call table, both directions
    urow("sy_ncalls", U32.from_nat(List.length(&2, String, sys.call_names())))
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
# | M1 | **4** <br>`sy_flagL_locked`, `sy_flag_locked_linux`, `sy_map_locked_linux`, `sy_map_locked_osx` | :51's `0 if OSX else 0x2000`, with the ternary reversed |
# | M2 | **4** <br>`sy_flagL_populate`, `sy_flag_populate_linux`, `sy_map_populate_linux`, `sy_map_populate_osx` | :51's `getattr(mmap, 'MAP_POPULATE', 0 if OSX else 0x008000)`, reversed |
# | M3 | **2** <br>`sy_flag_anon_osx`, `sy_map_anon_osx` | MAP_ANONYMOUS's platform split -- a host value where a platform one belongs |
# | M4 | **1** <br>`sy_pageframe_hi` | (1<<55)-1's HIGH word. 0x7fffff vs 0x7ffffff: one hex digit, and the bug I made |
# | M5 | **6** <br>`sy_echo_enable`, `sy_echo_len_enable`, `sy_echo_len_pagemap`, `sy_echo_pagemap`, `sy_echo_reset`, `sy_write_retry_cmd` | WALL 2's SPACES around the `>`. A dropped space is a `sudo` that writes a file named `echo1` |
# | M6 | COMPILE-FAIL (- expected : a defined name) | the def is GONE (a rename is the one edit that proves the rows read the def) |
# | M7 | **4** <br>`sy_va_cached_nmmap`, `sy_va_nreserved`, `sy_va_nreserved2`, `sy_va_other_nmmap` | THE CACHE. :86's `functools.cache` -- the negative case is IN THE PYTHON SOURCE |
# | M8 | **2** <br>`sy_write_fail_refused`, `sy_write_retry_refused` | :59's RAISE. Everything after the second read truncates |
# | M9 | **6** <br>`sy_pagemap_order`, `sy_pagemap_total_reads`, `sy_write_fail_nread`, `sy_write_ok_nread`, `sy_write_ok_read`, `sy_write_retry_nread` | :57's FIRST READ. It happens on both arms, before the comparison |
# | M10 | **1** <br>`sy_alloc_size_1001_plain` | THE WALRUS. `size := round_up(...)` is inside the `if contiguous`, so a plain request is never rounded |
# | M11 | **3** <br>`sy_alloc_fixed_0`, `sy_alloc_flags_2000_0`, `sy_alloc_mmap_2p` | :100's `(MAP_FIXED if vaddr else 0)` -- a FALSY test, not a None test |
# | M12 | **4** <br>`sy_buses_0`, `sy_buses_1`, `sy_buses_2`, `sy_writes_bus0` | :141's `(bus+1) << 8 | (gpu_bus) << 16` -- the two shifts TRANSPOSED. A silently wrong bus number |
# | M13 | **3** <br>`sy_membase16`, `sy_writes_bus0`, `sy_writes_bus3` | :144's `(mem_base>>16) & 0xffff` -- the shift dropped |
# | M14 | **3** <br>`sy_prefbase16`, `sy_writes_bus0`, `sy_writes_bus3` | the HIGH word substituted for the low one. The bug I made: 8 instead of 0 |
# | M15 | **5** <br>`sy_rebar_1001_201`, `sy_rebar_1_201`, `sy_rebar_2100_201`, `sy_rebar_size_1001`, `sy_rebar_size_2100` | :158's `<< 8` -- the shift amount, which resizes a BAR to the wrong power of two |
# | M16 | **3** <br>`sy_rebar_1001_201`, `sy_rebar_2100_201`, `sy_rebar_mask` | `~0x1F00` -- the bits it CLEARS |
# | M17 | **4** <br>`sy_barsize_10000000`, `sy_barsize_f0000000`, `sy_barsize_fff00000`, `sy_barsize_fffff000` | :175's `& ~0xf`. A BAR size four orders of magnitude wrong |
# | M18 | **1** <br>`sy_step32` | :183's `bar_off += 8 if bar_64 else 4` -- the two arms SWAPPED |
# | M19 | **1** <br>`sy_more_24` | `while bar_off < 24` -- `<` against `<=`, so the loop runs one BAR too many |
# | M20 | **1** <br>`sy_inva_base` | the two-word lexicographic `>=`. `va_base <= lo` with `==` refused |
# | M21 | **4** <br>`sy_barinfo_0`, `sy_barinfo_1000`, `sy_barinfo_7c`, `sy_barinfo_7d0` | :260's `int(e,16) - int(s,16) + 1`. The `+ 1` IS the whole of bar_info |
# | M22 | **1** <br>`sy_issmall_no` | :300's `== (256 << 20)` turned into a comparison -- a 1 GiB bar is suddenly 'small' |
# | M23 | **8** <br>`sy_align_big`, `sy_align_big1`, `sy_align_just_under`, `sy_align_small`, `sy_align_tiny`, `sy_ladder_1001`, `sy_ladder_1234567`, `sy_ladder_800001` | :315's `(2 << 20) if size >= (8 << 20) else (4 << 10)` -- the two arms SWAPPED |
# | M24 | **2** <br>`sy_ladder_1234567`, `sy_ladder_800001` | :315's `PAGESIZE if should_use_sysmem else <ladder>` -- the two arms SWAPPED |
# | M25 | **3** <br>`sy_hx_100`, `sy_hx_width_256`, `sy_hx_width_4095` | the THIRD threshold of the `%x` ladder. The bug I made: one predicate for two rungs |
# | M26 | **10** <br>`sy_gid_0a000001`, `sy_gid_7f000001`, `sy_gid_c0a801ff`, `sy_gid_ffffffff`, `sy_hx_744c`, `sy_hx_f`, `sy_hx_ff`, `sy_hx_ffff`, `sy_id_osx_1002_744c`, `sy_id_osx_10de_144c` | the `a`-..`f` base of `%x`. Off by one in one letter, and only the letters see it |
# | M27 | **0** | :418's `[:3]` TRUNCATION -- a fourth argument would be sent |
# | M28 | **3** <br>`sy_port_colon`, `sy_port_default`, `sy_port_default0` | :402's `int(...) if ":" in r else 6667` -- the default on the wrong side |
# | M29 | **4** <br>`sy_rcmd_0`, `sy_rcmd_MAP_BAR`, `sy_rcmd_PROBE`, `sy_rcmd_first` | :360's enum ORDER -- two members NEIGHBOUR-SWAPPED, which is a silently wrong remote command |
# | M31 | **3** <br>`sy_nv_2f01_masked`, `sy_nv_2fff_masked`, `sy_term_nv_2f01` | :126's `(device & mask)` -- the AND dropped, which refuses every NVIDIA card with a nonzero revision |
# | M32 | **2** <br>`sy_base_030000`, `sy_base_030200` | :116/:122's `>> 16` |
# | M33 | **9** <br>`sy_capid_1001`, `sy_capid_15`, `sy_capid_1500`, `sy_capid_2100`, `sy_capid_ff15`, `sy_is_rebar_15`, `sy_is_rebar_1500`, `sy_is_rebar_1501`, `sy_is_rebar_ff15` | :156's `PCI_EXT_CAP_ID` -- the low BYTE, not bits 15:8 |
# | M34 | **4** <br>`sy_bus_trim`, `sy_pci_sibs`, `sy_sib1`, `sy_sib7` | :220's `pcibus[:-1]` -- `take` against `drop`. `drop` removes from the FRONT |
# | M35 | **2** <br>`sy_class_AMD`, `sy_class_NPU` | :136's `device[:2]` -- the class is TWO characters, not one |
# | M36 | **2** <br>`sy_mapflags_0`, `sy_mapflags_nz` | :263's `MAP_SHARED | (MAP_FIXED if addr else 0)` |
# | M37 | **4** <br>`sy_resize_0`, `sy_resize_1`, `sy_resize_100000`, `sy_resize_40000000` | :267's `bit_length() - 1` -- the wrong constant |
# | M38 | **1** <br>`sy_meta_sysmem_cpu` | :321's LITERAL `has_cpu_mapping=True` read as the `cpu_access` argument |
# | M39 | **1** <br>`sy_pg_explicit_pci` | :297's getattr fallback -- which of the three classes SETS peer_group |
# | M40 | **2** <br>`sy_path_override`, `sy_path_unbind` | the sysfs TAIL table -- two neighbours swapped, a silently wrong unbind path |
# | M41 | **2** <br>`sy_sock_opts`, `sy_sock_opts_str` | :393's `(SO_SNDBUF, SO_RCVBUF)` -- the two options TRANSPOSED |
# | M42 | **0** | THE RAISE. Every refusal row at once, and nothing else |
# | M43 | **6** <br>`sy_el_H`, `sy_el_I`, `sy_el_L`, `sy_el_Q`, `sy_el_d`, `sy_el_f` | the struct calcsize table's WALK -- a stub that always misses, so only the negative row moves |
# | M44 | **19** <br>`sy_flagL_anon`, `sy_flagL_locked`, `sy_flagL_missing`, `sy_flagL_populate`, `sy_flagL_private`, `sy_flagL_shared`, `sy_flag_anon_linux`, `sy_flag_anon_osx`, `sy_flag_dontfork`, `sy_flag_fixed`, `sy_flag_hugetlb`, `sy_flag_locked_linux`, `sy_flag_missing`, `sy_flag_missing_linux` ... | the mmap table's WALK, reduced to its length. Only the name rows and the missing row can move |
# | M45 | **3** <br>`sy_nwrites`, `sy_writes_bus0`, `sy_writes_bus3` | the EIGHTH write -- :151's PCI_COMMAND duplicated. The bug I made: nine writes for eight |
# | M46 | **1** <br>`sy_writes_bus3` | :141's `bus` threaded into the first write -- pinned at zero, which is the bus-0 fixture |
# | M48 | **4** <br>`sy_has_absent`, `sy_has_reversed`, `sy_has_wrong_arg`, `sy_has_wrong_str` | Tr.has with the answer hard-wired -- the order rows and the matcher, all of them |
# | M47 | **0** | CONTROL -- a comment-only edit. A table with no row that CANNOT move is a table of coincidences |
# | M49 | **3** <br>`sy_pci_bound_nopen`, `sy_pci_nopen`, `sy_pci_opens` | :211's `enable` open -- the DEAD-CODE probe. A def nothing calls is invisible to every other check |
# | M50 | **3** <br>`sy_gid_0a000001`, `sy_gid_7f000001`, `sy_gid_c0a801ff` | :53's tail ORDER -- four bytes the wrong way round, and every length and total still correct |#
# M6 IS A COMPILE-FAIL AND THAT IS THE POINT: renaming `sysfs.echo` breaks the
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
# TWO ZEROS THAT WERE REAL GAPS AND ARE NOW FIXED, and both are the reason the table
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
# WHAT THIS GATE STILL DOES NOT SEE, and the list is short enough to be honest about:
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
#   5. THE `REMOTE` ENV PARSER'S SPLIT AND STRIP (:399). Wall: no `String.split`, no
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
    IO.print("sy-done=1")
