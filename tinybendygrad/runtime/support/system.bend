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
#   tinygrad/runtime/support/system.py:10-15 `filter_visible_devices` PORTED  `vis.*` -- the index-string parser
#   :17-47 FileIOInterface        FFI     open/close/ioctl/mmap/read/write.
#                                              :36's `-1` mmap sentinel and :42-47's
#                                              three statics are the trace
#   tinygrad/runtime/support/system.py:49-50 `MAP_FIXED` `MAP_LOCKED` PORTED  `MAP_*` -- both directions, per PLATFORM
#   tinygrad/runtime/support/system.py:52 `ipv4_to_gid` PORTED  `gid.*` -- 16 bytes of multicast group
#   :56-59 write_sysfs            PORTED  `sysfs.*` + `sysfs.wrote` -- the `sudo`
#                                               STRING
#   tinygrad/runtime/support/system.py:61-65 `atomic_lib` / libsys PORTED  `cap.*` -- the PLATFORM gate, which is
#                                               `cap.barrier_lib`'s `osx`
#   :67-70 pagemap                PORTED  `sys.pagemap`
#   :72-82 vfio                   PORTED  `pci.probe.vfio` -- its `except OSError:
#                                               None`
#   :84-87 reserve_va             PORTED  `sys.reserve_va` -- the CACHE negative case
#   tinygrad/runtime/support/system.py:88 `memory_barrier`  PORTED  `cap.barrier_lib` -- which library is
#                                               consulted
#   :91-92 lock_memory            PORTED  `sys.lock_memory` -- the refusal
#   tinygrad/runtime/support/system.py:93 `system_paddrs`   PARTIAL `paddr.*` -- the mask; the u64 read is FFI
#   :98-102 alloc_sysmem          PORTED  `sys.alloc_sysmem` -- the flag arithmetic
#   tinygrad/runtime/support/system.py:103 `pci_scan_bus`  PORTED  `scan.*` -- the mask filter + both id formats
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
#   tinygrad/runtime/support/system.py:290 `PCIAllocationMeta` PORTED  `Meta.*` -- field order and names
#   tinygrad/runtime/support/system.py:292-352 `PCIIfaceBase` PORTED  `face.*` -- peer_group, is_bar_small, the
#                                               alloc size ladder, map()'s refusals
#   tinygrad/runtime/support/system.py:356-360 `RemoteCmd` PORTED  `Rcmd.*` -- 16 names, both directions,
#                                               REMOTE_REQ/REMOTE_RESP field order
#   tinygrad/runtime/support/system.py:362-380 `RemoteMMIOInterface` PORTED  `rmm.*` -- the element-size table
#   :385-452 RemotePCIDevice      PORTED  `rpc.*` -- the pad-to-3 rule, the REMOTE
#                                               parser, the socket-option table
#   :454   the MOCK swap          FFI     DEV.interface, a module rebind
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# 1. THE u64 WALL, and it is three Python lines and one struct format.
#      :96   `[(x & ((1<<55)-1)) * mmap.PAGESIZE for x in array.array('Q', ...)]`
#      :174  the BAR size -- `bar_64` -- `((~(((hi << 32) | lo) & ~0xf)) + 1) & (0xffff... if bar_64 else ...)`
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
#    TODO(p3) runtime/support/system.py:95  symbol=system_paddrs  -- the u64 pagemap read.
#    TODO(p3) runtime/support/system.py:174  symbol=pci_setup_usb_bars -- the u64 BAR size.
#    TODO(p3) runtime/support/system.py:445 -- `struct.unpack('<Q', data)[0]`.
#
# 2. THE SYSCALL STRINGS, :58/:75/:198/:247. `os.system` takes ONE string and
#    hands it to `/bin/sh`, so these four are the whole of what a shell sees. A
#    dropped quote or a dropped path is a `sudo` that writes the wrong file, and
#    it is silent. `sysfs.echo` and `pci.resize_path` build them, and the gate
#    DIFFS
#    THE STRING BESIDE CPYTHON'S -- a boolean about a string proves nothing,
#    because `String.concat` will happily drop a literal and still make two
#    strings that differ agree on a length.
#    TODO(p3) runtime/support/system.py:58  symbol=write_sysfs  -- `os.system(cmd)`.
#    TODO(p3) runtime/support/system.py:74  symbol=vfio  -- `os.system("sudo modprobe ...")`.
#    TODO(p3) runtime/support/system.py:195  symbol=flock_acquire -- `os.system("sudo lsof ...")`, in a message.
#    TODO(p3) runtime/support/system.py:244  symbol=reset -- `os.system(...)`, in `PCIDevice.reset`.
#
# 3. THE CTYPES LIBRARY GATE, tinygrad/runtime/support/system.py:61-65 and tinygrad/runtime/support/system.py:88. `atomic_lib` is
#    `ctypes.CDLL(ctypes.util.find_library('atomic')) if sys.platform == "linux"
#    else None` and `libsys` has NO such gate. So the two libraries are NOT
#    symmetric, and `memory_barrier`'s `self.libsys if OSX else self.atomic_lib`
#    is a SECOND, different predicate over the same two facts -- one per
#    platform, and the two do not agree. That is the whole branching story at
#    tinygrad/runtime/support/system.py:88 and it is pure, so it is ported as `cap.barrier_lib` -- upstream's `memory_barrier` -- and the gate asks
#    the question twice: which library, and whether it is a real fence at all.
#    `ctypes.CDLL` and `find_library` are the FFI and are the trace.
#    TODO(p3) runtime/support/system.py:61  symbol=atomic_lib -- `ctypes.CDLL(find_library('atomic'))`.
#    TODO(p3) runtime/support/system.py:64  symbol=libsys -- `ctypes.CDLL(find_library("System"))`.
#    TODO(p3) runtime/support/system.py:88  symbol=memory_barrier -- `lib.atomic_thread_fence(5)`.
#
# 4. THE OSX PROPERTY READ, :108-112. `read_prop` is CoreFoundation: a CFString
#    key, a `CFDataRef`, an 8-byte `c_uint8` buffer and `int.from_bytes(...,
#    "little")`. It is four ctypes calls and a cast chain, and the ONLY part of it
#    that is this file's own logic is the 8-byte little-endian read, which
#    `pci.read_prop` ports. Everything above it is CoreFoundation, so the whole
#    `OSX` half of `pci_scan_bus` is FFI and only the LINUX half is a trace.
#    TODO(p3) runtime/support/system.py:109  symbol=read_prop -- the ctypes cast chain.
#    TODO(p3) runtime/support/system.py:109  symbol=read_prop -- `IORegistryEntryCreateCFProperty`.
#    TODO(p3) runtime/support/system.py:110  symbol=read_prop -- `CFDataGetBytes` into `(c_uint8*8)()`.
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
# and the five `setsockopt` calls (tinygrad/runtime/support/system.py:389-390) are a socket; `_recvall`'s
# `sock.recv` loop (:410-415) is a socket; `struct.pack`/`struct.unpack` (:239,
# :374, :378, :418, :424, :426, :437, :448) are byte layout and are FFI, EXCEPT
# the two rules they are driven by -- `elemsize` (this file's own name for
# upstream's `struct.calcsize(self.fmt)`, tinygrad/runtime/support/system.py:367
# symbol=RemoteMMIOInterface) and `post_args` (this file's own name for
# upstream's `struct.pack(REMOTE_REQ, ...)`,
# tinygrad/runtime/support/system.py:415 symbol=_post) --
# which are this file's own arithmetic and are ported and gated; and
# `BumpAllocator`, `MMIOInterface`, `VirtMapping` and `AddrSpace` are
# `support/memory.py`, `CustomASM24Controller` and `USB3` are `support/usb.py`,
# `PCIDevice`/`RemotePCIDevice` are consumed by `ops_amd.py` and the other
# devices. None of those is invented here.
import Base
import ../../helpers.bend as H

# ===========================================================================
# THE constants. EVERY one of these was READ out of a live CPYTHON by
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
# TWO platform-DEPENDENT constants in one line, and they are the `has_`/`is_`
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

def MAP_HUGETLB() -> U32: 262144                    # 0x40000
def MADV_DONTFORK() -> U32: 10                     # 0xa -- libc.MADV_DONTFORK

# --- the os open flags, :19/:211/:242/:256 ----------------------------------
def O_RDONLY() -> U32: 0
def O_WRONLY() -> U32: 1
def O_RDWR() -> U32: 2
def O_SYNC() -> U32: 128                           # 0x80
def O_CLOEXEC() -> U32: 16777216                   # 0x40000
def O_RDWR_SYNC_CLOEXEC() -> U32: 16777346         # 0x40002  -- os.O_RDWR|O_SYNC|O_CLOEXEC
def LOCK_EX() -> U32: 2
def LOCK_NB() -> U32: 4
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
# THE order of `k` IS the order of the table, and `sys.call_names` is that table
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
# THE three fields in this order, and the third one DEFAULTED. The port carries
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

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case c <> t: Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(Call.k(c), k))))

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

def ush.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush.go(t, List.append(&2, String, acc, [U32.show(x)]))

def ush(xs: List<&2, U32>) -> List<&2, String>: ush.go(xs, Nil{})

def head_u32(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

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
# THREE distinct predicates and three distinct arms. My first version passed the
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
# TODO(p3) runtime/support/system.py:52 -- `socket.inet_aton(ip)`.
# ===========================================================================

def gid.PREFIX_HEX() -> String: "00000000000000000000ffff"
def gid.of.p2(+hi: U32, +lo: U32) -> String:
  String.concat([gid.PREFIX_HEX(), hx.d4(hi), hx.d4(lo)])

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

# FIRST-HIT wins, AND that is not what python does. `Bool.pick` was MEASURED to
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

def mapflag_name.maybe(m: Maybe<&2, String>) -> String:
  match m:
    case Some{g}: g
    case None{}: "?"

def mapflag_name.at(ns: List<&2, String>, i: U32) -> String:
  mapflag_name.maybe(List.get(&2, String, ns, U32.to_nat(i)))

def mapflag_name.pick(+i: U32) -> String:
  Bool.pick(String, U32.is_ge(i, U32.from_nat(List.length(&2, String, mapflag_names()))),
    "?", mapflag_name.at(mapflag_names(), i))

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
# THE two libraries are not symmetric. `atomic_lib` is LINUX-ONLY and so is None on
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

def cap.barrier_lib.p2(+osx: U32, have_atomic: Bool, +have_sys: Bool) -> U32:
  Bool.pick(U32, U32.is_eq(osx, CAP_YES()),
    Bool.pick(U32, have_sys, LIB_SYS(), LIB_NONE()),
    Bool.pick(U32, have_atomic, LIB_ATOMIC(), LIB_NONE()))

def sysfs.echo(+value: String, +path: String) -> String:
  String.concat(["sudo sh -c 'echo ", value, " > ", path, "'"])

# :57's `(expected or value)`: the COMPARISON target. `expected` is `str | None` and
# :57 passes `expected or value`, so an `expected` of "" is ALSO falsy and the
# fallback is the VALUE. Python's `or` on a string is emptiness, so this is a
# two-way gate and not a `Maybe`.
def sysfs.want(+expected: String, +value: String) -> String:
  Bool.pick(String, String.is_empty(expected), value, expected)

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

# THE first read is part of the claim. :57 is `if FileIOInterface(path,
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

def MMAP_BASE_LINUX() -> U32: 40993                 # 0xa021 = SHARED|ANON|POPULATE|LOCKED

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

def scan.cap_id(hdr: U32) -> U32: U32.and(hdr, 255)
def scan.cap_next(hdr: U32) -> U32: U32.and(hdr, 255)

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

def bars.bar_mem.pick(+hit: Bool) -> U32: Bool.pick(U32, hit, 1, 0)

def bars.bar_64(cfg: U32) -> U32: U32.and(cfg, PCI_BASE_ADDRESS_MEM_TYPE_64())

def bars.step.pick(+bar_off: U32, step: U32) -> U32: U32.add(bar_off, step)

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
# raises -- so an UNBIND that did not take is a refusal, and it is a TRUNCATION
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

def BAR_INFO_DELTA() -> U32: 1

def SMALL_BAR_SIZE() -> U32: 268435456

def MAP_BAR_FLAGS_OSX() -> U32: 1
def MAP_BAR_FLAGS_FIXED() -> U32: 17

def pci.map_flags.pick(+addr: U32) -> U32: Bool.pick(U32, U32.is_zero(addr), MAP_BAR_FLAGS_OSX(), MAP_BAR_FLAGS_FIXED())

def pci.map_size.pick(+want: U32, +size: U32) -> U32: Bool.pick(U32, U32.is_zero(size), want, size)

def Meta.of(+has_cpu_mapping: Bool, +hMemory: U32) -> Meta: Meta{has_cpu_mapping, hMemory}

def KIND_PCI() -> U32: 0
def KIND_USB() -> U32: 1
def KIND_REMOTE() -> U32: 2

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

def face.use_sysmem.pick(+host: Bool, +rest: Bool) -> Bool: Bool.or(host, rest)

def face.use_sysmem.p2(+cpu_access: Bool, +small: Bool, +force: Bool) -> Bool:
  Bool.and(cpu_access, Bool.and(small, Bool.not(force)))

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

def HOST_HEADS() -> List<&2, String>: ["CPU", "PYTHON", "NPY"]

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

def Rcmd.base() -> U32: 13
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

def Rcmd.of.go(+s: String, ns: List<&2, String>, +at: U32) -> U32:
  match ns:
    case Nil{}: mapflag_missing()
    case h <> t:
      +nxt = U32.add(at, 1)
      Bool.pick(U32, String.eq(h, s), at, Rcmd.of.go(s, t, nxt))

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

def rmm.st.pick(+start: U32, +el: U32) -> U32: Bool.pick(U32, U32.is_zero(start), 0, U32.mul(start, el))

def rmm.en.pick(+stop: U32, +nbytes: U32, +el: U32) -> U32:
  Bool.pick(U32, U32.is_zero(stop), U32.mul(nbytes, el), U32.mul(stop, el))

def CMD_MMIO_READ() -> U32: 6
def CMD_SYSMEM_READ() -> U32: 9
def CMD_MMIO_WRITE() -> U32: 7
def CMD_SYSMEM_WRITE() -> U32: 10

def REMOTE_DEFAULT_PORT() -> U32: 6667
def SOL_SOCKET() -> U32: 65535
def SO_SNDBUF() -> U32: 4097
def SO_RCVBUF() -> U32: 4098
def IPPROTO_TCP() -> U32: 6
def NODELAY_ON() -> U32: 1

def rpc.port.pick(+has_colon: Bool, +port: U32) -> U32:
  Bool.pick(U32, has_colon, port, REMOTE_DEFAULT_PORT())

def rpc.buf_opts() -> List<&2, U32>: [SO_SNDBUF(), SO_RCVBUF()]

# :392-393 the whole option sequence, as a trace. THREE setsockopt calls: the NODELAY
# one and the two buffer ones, IN THAT ORDER.
def rpc.opts(os: List<&2, U32>, +t: Tr) -> Tr:
  match os:
    case Nil{}: t
    case o <> u: rpc.opts(u, Tr.emit(CALL_SETSOCKOPT(), SOL_SOCKET(), U32.show(o), t))

def MOCK_HEADS() -> List<&2, String>: ["MOCK"]

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

