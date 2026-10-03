# tinybendygrad/runtime/ops_disk.bend -- port of tinygrad/runtime/ops_disk.py
#
# ===========================================================================
# WHY THIS FILE IS NOT THE SMALL ONE IT LOOKS LIKE.
#
# Every other backend in `tinygrad/runtime/` is a wrapper around a driver, and a
# wrapper around a driver has nothing to port: the calls are calls. `DISK` is the
# one backend whose storage is FILES, which makes it the cheapest end-to-end
# device a test can actually run against -- and it exercises the parts of the
# device contract the GPU backends hide:
#
#   - a Buffer is a WINDOW onto a mapping, not a name, so `size`/`offset` are
#     arithmetic a gate can check;
#   - the open is a PATH CONSTRUCTION with two spellings (`disk:` and `shm:`)
#     and three normalisations, which is a naming table in both directions;
#   - the writes are PARTIAL -- page-aligned reads, sub-page copies -- and the
#     segment arithmetic is the whole content of `_copyout_sharded`;
#   - and a `DiskDevice` buffer is a REAL FILE, so `_buf`'s window is a range of
#     bytes that exists on the host and could be read back.
#
# THE PLACE A RESULT CAN BE CHECKED RATHER THAN A TRACE, and it is
# `_copyout_sharded` (:101-116). Every segment it yields is
# `(copy_batch, copied_in, minor_offset, real_copy_size)` and `copied_in` is where
# the segment LANDS in the destination. So the `real_copy_size`s must sum to
# exactly `size` AND consecutive `copied_in`s must be contiguous -- statements
# about the DATA, not about the spelling of a call. `dk_shard_cover_*` and
# `dk_shard_contig_*` assert them. Everything else in this file is a trace.
#
# And the sharper version of the same fact, which is a RESULT a trace cannot see:
# **a wrong `minor_offset` leaves the total CORRECT.** The skew is subtracted from
# exactly ONE segment (it is zeroed at :115) and the LAST segment is truncated by
# `size - copied_in` anyway, so dropping it moves the destination of every byte
# without changing the sum. The `cin` column is the only thing that sees it, and
# `dk_shard_b` is the row that carries it. See the gate's section 7.
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed, and it is `ops_webgpu.bend`'s.
#
# STATUS, and it is what a reader should check first. This file COMPILES, runs on
# both lanes, and its gate rows are BYTE-IDENTICAL to a CPython oracle that
# re-derives every one of them from `ops_disk.py`:
#
#     ./bin/bend tinybendygrad/runtime/ops_disk.bend --check-only         # ALL CHECK
#     ./bin/bend tinybendygrad/runtime/ops_disk.bend                      # interpreted
#     ./bin/bend tinybendygrad/runtime/ops_disk.bend -o /tmp/d && /tmp/d  # native
#     python3 -c "import sys; sys.path.insert(0,'.'); \
#                exec(open('.agents/slop/dk-oracle.py').read())"           # CPython
#
# All four agree byte for byte, and the mutation table at the foot is MEASURED: 43
# mutations here plus 13 in `datasets.bend`, one comment-only control that moves
# nothing, and 55 that each change at least one row. The oracle ASSERTS that this
# host's `mmap.PAGESIZE`, `os.O_CREAT`, `getattr(os,"O_DIRECT",0)` and
# `getattr(mmap,"MADV_HUGEPAGE",None)` agree with the port's macOS cell, so the
# two-platform claim is measured rather than asserted.
#
# A def here EITHER builds the argument of ONE host call (pure, and the gate
# checks it) OR records that call in the trace (and the gate checks the ORDER).
# There is no third kind. NO `@extern` seam and no `import "./x.c"` anywhere in
# this file, and that is a DIFFERENCE from `dtype.bend` rather than an omission:
# the syscall trace IS the record of the call, so a foreign effect would be a
# second way of saying the same thing. `--check-only` is GREEN here, so the
# import-closure redness the brief predicted does not arise.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :12  synchronize               PORTED  `dev_sync` -- it is `pass`
#   :14-20 __init__                 PORTED  `dev_init`
#   :15  the io_uring guard         PORTED  `dev_ioring_setup`, `Dev.tried`
#   :21-40 _might_open              PORTED  `dev_might_open` and its steps
#                                             `dev_warm`, `dev_shm.on`,
#                                             `dev_file.at`, `dev_finish.at`
#   :22  the assert                 PORTED  `dev_fits`, `dev_reopen_msg`
#   :23  the fast path              PORTED  `dev_is_open`, `dev_warm`
#   :26  filename                   PORTED  `dsk_filename`
#   :28  the shm predicate          PORTED  `dev_is_shm`, `dsk_shm_name`
#   :29-31 the shm branch            PORTED  `dev_shm.on`
#   :33-34 the try/except open       PORTED  `dev_file.open.at` -- and :34's
#                                             branch is NOT a parameter; see
#                                             THE EXCEPT IS NOT A BRANCH
#   :35  the block-device guard     PORTED  `dev_file.trunc.at`, `dev_trunc`
#   :36  the mapping                PORTED  `dev_file.mmap.at`
#   :37-40 the tail                  PORTED  `dev_sized`, `dev_bumped`,
#                                             `dev_finish.at`
#   :38-39 madvise                  PORTED  `dev_finish.at` (the condition)
#   :41-49 _might_close             PORTED  `dev_might_close`
#   :50-71 _iouring_setup           PARTIAL `dev_ioring.*` -- the call ORDER and
#                                             the four numbers Python spells
#                                             itself; the three mmap LENGTHS are
#                                             WALL 2
#   :73-79 DiskBuffer               PORTED  `Db.of`, `db_repr`, `db_buf`
#   :81  MAP_LOCKED/MAP_POPULATE    PORTED  `map_locked`, `map_populate`
#   :83  lru = False                PORTED  `ALLOC_LRU`
#   :84-86 _alloc                   PORTED  `alloc_of` (`mv_address` is WALL 1)
#   :88  _free                      PORTED  `alloc_free`
#   :89  _as_buffer                 PORTED  `alloc_as_buffer`
#   :90  _copyin                    PORTED  `alloc_copyin`
#   :91-99 _copyout                 PORTED  `alloc_copyout`
#   :101-116 the NON-uring shard    PORTED  `shard_at`, `shard.go`, `shard_read`,
#                                             `shard_real`
#   :118-142 the io_uring shard     PARTIAL `shard_ioring` -- the two submission
#                                             calls and the segment arithmetic
#   :144 _offset                    PORTED  `alloc_offset`
#
# ===========================================================================
# THE FOUR WALLS.
#
# 1. ADDRESSES. `mv_address(mv) = ctypes.addressof(ctypes.c_char.from_buffer(mv))`
#    (:86) is a live mmap base address, and it is what every consumer of a Disk
#    buffer reaches a buffer through. The port carries a 0 and names it;
#    `Rc.addr` is the field and `dk_alloc_addr` is the row.
#    TODO(p3) ops_disk.py:86  -- mv_address -> the mapping's base address.
#
# 2. THE io_uring mmaps (:57-61). Their LENGTHS are `p.sq_off.array +
#    p.sq_entries * 4`, `p.cq_off.cqes + p.cq_entries * sizeof(cqe)` and
#    p.sq_entries * sizeof(sqe)`, and `p` is a `struct_io_uring_params` the KERNEL
#    fills in from the 4096 entries requested at :54. None of it is computable
#    before the syscall, so the trace records the ORDER and the file OFFSET
#    (`IORING_OFF_CQ_RING` = 0x8000000, `IORING_OFF_SQES` = 0x10000000) and not
#    the length.
#    TODO(p3) ops_disk.py:57  -- the three mmap lengths.
#    TODO(p3) ops_disk.py:58  -- ditto.
#    TODO(p3) ops_disk.py:60  -- ditto.
#
# 3. `is_block_device` (:35) is a `pathlib` stat of the PATH and `os.fstat(fd)
#    .st_size` (:35) is a stat of the DESCRIPTOR. Both are one Bool and one `U32`
#    the host supplies, and both ride on `Dev` as `blockdev`/`stsize` so a fixture
#    reaches each of the three cells of :35's conjunction.
#    TODO(p3) ops_disk.py:35  -- is_block_device() and fstat().st_size.
#
# 4. `readinto`'s byte count (:97) and `mem.close()`'s BufferError (:48) are the
#    FILE's answers. `dsk_reads.go` takes the reads that HAPPENED as its chunk
#    list; `dev_close_mems.at` records the unmap whether or not it succeeded,
#    because :48 swallows the error.
#
# ===========================================================================
# THE ASSERT/EXCEPT DISTINCTION, and it is the one structural thing this file has
# that `ops_webgpu.bend` does not.
#
# `ops_webgpu` has ONE raise and it TRUNCATES the trace: nothing after a refusal
# is recorded, so no step needs a guard of its own. `ops_disk.py` has THREE raises
# and THREE swallowed failures, and they behave differently:
#
#   the ASSERTS (:22, :78, :139) raise, and they TRUNCATE -- `Tr.refuse` latches
#     `refused` and `Tr.emit` consults it, exactly as in `ops_webgpu.bend`;
#
#   the swallowed failures (:34 `except OSError`, :39 `contextlib.suppress(OSError)`
#     :48 `except BufferError`) do NOT truncate: execution continues.
#
# THE EXCEPT IS NOT A BRANCH. :33-34 is `try: os.open(f, O_RDWR|O_CREAT|O_DIRECT)
# except OSError: os.open(f, O_RDWR|O_CREAT)` and the trace records the ATTEMPT as
# well as the RETRY, in that order -- so :34's two arms produce the SAME trace and
# `dev_file.open.at` takes NO branch parameter for them. The one thing that
# differs is which descriptor ends up in `self.fd`, and both are `os.open` answers
# on the same path, so it is not observable in this trace either. The flags DO
# differ and both are recorded, which is what `dk_open_file_args` pins.
#
# ===========================================================================
# FOUR FACTS THAT ARE EASY TO GET WRONG AND THAT THE GATE PINS BY NAME.
#
# A. THE REFCOUNT IS ON THE DEVICE, NOT ON THE BUFFER. `_alloc` calls
#    `self.dev._might_open(size)` and `_free` calls `self.dev._might_close()`
#    (:88) with NO argument at all. Two buffers of DIFFERENT sizes therefore share
#    one mapping and one refcount, the second `_free` releases whichever was
#    allocated first, and the unmap covers the whole mapping rather than either
#    buffer. `alloc_free` takes a `Dev` and nothing else -- there is no storage to
#    read a size out of -- and `dk_two_alloc_*` is the row set: ONE free after TWO
#    allocs does NOTHING, and the SECOND free unmaps the FIRST buffer's size.
#
# B. `self.size = None` AT :49 DOES NOT CLEAR `self.mem` OR `self.fd`. So after a
#    close the device has `size is None` and still `hasattr(self,"mem")`, which is
#    exactly why :23's fast path needs BOTH conjuncts and not just the first.
#    `dk_close_keeps_mem`, `dk_close_keeps_fd` and `dk_warm_needs_both` are the
#    rows.
#
# C. `MAP_LOCKED`/`MAP_POPULATE` (:81) ARE PLATFORM CONSTANTS AND THE `getattr`
#    IS VACUOUS. `map_populate` therefore takes ONE Bool (`osx`), not two, and the
#    file says why rather than carrying a `hasattr` no fixture can falsify. The
#    SAME vacuity does NOT apply to `getattr(os,"O_DIRECT",0)` (:33): Linux has
#    the attribute and macOS does not, so `open_direct` keeps its parameter and
#    `dk_direct_yes`/`dk_direct_no` are a row per cell.
#
# D. THE OPEN FALLBACK CHANGES THE FLAGS, NOT THE PATH, AND BOTH FLAGS ARE
#    RECORDED. :33 asks for `O_RDWR|O_CREAT|O_DIRECT` and :34 retries with
#    `O_RDWR|O_CREAT`, so the two trace arguments differ and `dk_open_file_args` is
#    the row that pins both numbers.
#
# E. THERE IS NO DTYPE-TO-SUFFIX TABLE IN THIS FILE, and the gate should not look
#    for one. `DiskBuffer` is a raw `mmap` window: a `disk:/tmp/x` file holds the
#    buffer's bytes and nothing else, so a dtype changes how many BYTES the window
#    covers and never how the file is named. `nbytes` is `size * itemsize`
#    (`device.bend`) and that product is the whole of a dtype's reach into this
#    file. The naming table that IS here is the two PREFIXES, and it is gated in
#    both directions: device string -> path (`dk_file_*`) and path -> scheme
#    (`dk_is_shm_*`).
# ===========================================================================
import Base
import ./../helpers.bend as H
import ./../device.bend as DV

# ===========================================================================
# THE CONSTANTS, AND EVERY ONE OF THEM IS A *PLATFORM FACT* WITH TWO CELLS.
#
# `ops_disk.py` reads these from `os`, from `mmap` and from `helpers.OSX`, so on a
# host that is not Linux they are DIFFERENT NUMBERS. Writing the Linux value as a
# bare constant is how a port claims to be portable while being Linux-only, and it
# is not detectable from inside the file: `mmap.PAGESIZE` is 16384 on macOS/arm64
# and 4096 on Linux, so a hardcoded 4096 changes every shard row and nothing says so.
#
# SO: every host constant below is a function of the SAME `osx` Bool the fixtures
# already carry -- `Dev.osx` is `helpers.OSX` -- and the gate prints BOTH cells.
# The CPython oracle asserts that this host's `mmap.PAGESIZE`, `os.O_CREAT`,
# `getattr(os,"O_DIRECT",0)` and `getattr(mmap,"MADV_HUGEPAGE",None)` agree with the
# macOS cell, so the second cell is measured against the machine rather than trusted.
#
# THE macOS COLUMN, and where each number comes from on THIS host:
#   O_CREAT   512   -- `os.O_CREAT`
#   O_DIRECT  0     -- `getattr(os,"O_DIRECT",0)`: macOS has no such attribute
#   PAGESIZE  16384 -- `mmap.PAGESIZE` on arm64 macOS
#   MADV_HUGEPAGE 0 -- `getattr(mmap,"MADV_HUGEPAGE",None)` is None, so :39 IS NOT
#                      REACHED there. `madv_hp` answers 0 and `Dev.madv` is the
#                      PRESENCE flag, which is what :38's `getattr(...) is not None`
#                      actually tests.
#   MAP_LOCKED / MAP_POPULATE 0 -- `OSX` is True, so :81's first cell is 0 and
#                      `getattr(mmap,"MAP_POPULATE", 0)` finds nothing either.
# ===========================================================================
def O_RDWR() -> U32: 2
def O_CREAT_LINUX() -> U32: 64
def O_CREAT_MACOS() -> U32: 512
def O_DIRECT_LINUX() -> U32: 16384
def O_DIRECT_MACOS() -> U32: 0

def o_creat(osx: Bool) -> U32: Bool.pick(U32, osx, O_CREAT_MACOS(), O_CREAT_LINUX())
def o_direct(osx: Bool) -> U32: Bool.pick(U32, osx, O_DIRECT_MACOS(), O_DIRECT_LINUX())

# :33's `getattr(os, "O_DIRECT", 0)` -- TWO variables, not one: whether the
# attribute exists at all AND whether the call site ORs it in.
def open_direct(osx: Bool, has: Bool) -> U32: Bool.pick(U32, has, o_direct(osx), 0)

def open_flags(osx: Bool, direct: U32) -> U32:
  U32.or(O_RDWR(), U32.or(o_creat(osx), direct))

# :81 -- `MAP_LOCKED, MAP_POPULATE = 0 if OSX else 0x2000, getattr(mmap,
# "MAP_POPULATE", 0 if OSX else 0x008000)`.
def MAP_SHARED() -> U32: 1
def MAP_LOCKED_LINUX() -> U32: 8192
def MAP_POPULATE_LINUX() -> U32: 32768

def map_locked(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MAP_LOCKED_LINUX())
def map_populate(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MAP_POPULATE_LINUX())

# The three flags OR'd at :30, spelled as the source spells them. `osx` is
# linear, so the branch is the WHOLE expression rather than two picks over one
# Bool: both of the conditional flags are 0 on OSX, so the arm is exactly
# Python's `0 if OSX else 0x2000` applied twice. 1 | 32768 | 8192 = 40961.
def mem_flags(osx: Bool) -> U32:
  Bool.pick(U32, osx, MAP_SHARED(),
            U32.or(MAP_SHARED(), U32.or(MAP_POPULATE_LINUX(), MAP_LOCKED_LINUX())))

# :29's `0o600` -- 0o600 is 384 and is NOT a POSIX page-size question, so it has
# one cell. `shm_open`'s mode is a literal in the source.
def SHM_MODE() -> U32: 384

# :39's `getattr(mmap, "MADV_HUGEPAGE", None)` -- the VALUE, with `Dev.madv` as the
# PRESENCE. macOS has no such attribute, hence 0 and hence never emitted there.
def MADV_HUGEPAGE_LINUX() -> U32: 14
def madv_hp(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MADV_HUGEPAGE_LINUX())

# :103's `mmap.PAGESIZE`. THE ONE THAT CHANGES RESULTS rather than trace arguments,
# and the reason the whole section above is parameterised.
def PAGESIZE_LINUX() -> U32: 4096
def PAGESIZE_MACOS() -> U32: 16384
def pagesize(osx: Bool) -> U32:
  Bool.pick(U32, osx, PAGESIZE_MACOS(), PAGESIZE_LINUX())

# io_uring, read out of `tinygrad/runtime/autogen/io_uring.py`: the
# `enum_io_uring_op` dict at :155 for the opcode, the module constants at :530-540
# for the two offsets and the enter flag, and :447-449 for the syscall numbers.
def IORING_ENTRIES() -> U32: 4096
def IORING_OFF_CQ_RING() -> U32: 134217728
def IORING_OFF_SQES() -> U32: 268435456
def IORING_OP_READ() -> U32: 22
def IORING_ENTER_GETEVENTS() -> U32: 1
def NR_IO_URING_SETUP() -> U32: 425
def NR_IO_URING_ENTER() -> U32: 426

# `ctypes.sizeof(struct_io_uring_cqe)` is 16 and of `struct_io_uring_sqe` is 64,
# read off the `register_fields` lists at autogen/io_uring.py:101 and :76 (the
# sqe's last named field sits at offset 56 and is 8 wide).
def SIZEOF_CQE() -> U32: 16
def SIZEOF_SQE() -> U32: 64

# ===========================================================================
# THE CALL TAGS. One per HOST CALL, in Python line order, so a tag names the line
# it belongs to. `arg` is ONE numeric argument of that call and nothing else --
# `ops_webgpu.bend`'s `Call` discipline, and the reason the path and the mode are
# gate ROWS rather than trace entries.
# ===========================================================================
def K_IOURING_SETUP() -> U32: 0     # :54
def K_MMAP() -> U32: 1              # :36, :57, :58, :60
def K_SHM_OPEN() -> U32: 2          # :29
def K_MMAP_SHM() -> U32: 3          # :30
def K_CLOSE() -> U32: 4             # :31, :45
def K_OPEN_DIRECT() -> U32: 5       # :33
def K_OPEN() -> U32: 6              # :34
def K_FSTAT() -> U32: 7             # :35
def K_FTRUNCATE() -> U32: 8         # :35
def K_MADVISE() -> U32: 9           # :39
def K_MUNMAP() -> U32: 10           # :47
def K_COPYIN() -> U32: 11           # :90
def K_COPYOUT() -> U32: 12          # :99, :111
def K_FILEIO() -> U32: 13           # :94
def K_SEEK() -> U32: 14             # :95
def K_READINTO() -> U32: 15         # :97
def K_FILEIO_CLOSE() -> U32: 16     # the `with` exit at :94
def K_SQE_STORE() -> U32: 17        # :128
def K_IORING_ENTER() -> U32: 18     # :130

# ===========================================================================
# THE TYPES.
# ===========================================================================

type Call is Data:
  Call{k: U32, arg: U32}

# the machine state of the trace. `next` mints the descriptor ids the seam would
# hand back, so the gate can say that the shm `close` closes the descriptor the
# shm `open` minted and NOT `self.fd`.
#
# `refused` is the port of the asserts and it LATCHES: once set no later emit
# records anything, so a refusal appears in the trace as a TRUNCATION.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool}

# ops_disk.py:9 DiskDevice, only the fields ops_disk.py reads or writes.
#
# `has_size`/`size` is Python's `self.size: int|None`, `has_fd`/`fd` is
# `self.fd: int|None` and `has_mem` is `hasattr(self,"mem")`. A `Data` record may
# not hold a `Maybe` field, so each absence is a `Bool` BESIDE its value --
# `device.bend`'s `external_ptr` escaping.
#
# The next six are facts the HOST supplies and the code branches on, so they ride
# here rather than being threaded through every arm:
#   osx      `helpers.OSX`                                    -- :81, :92
#   win      `sys.platform == "win32"`                        -- :28
#   direct   `getattr(os,"O_DIRECT",0)`                       -- :33
#   blockdev `pathlib.Path(f).is_block_device()`              -- :35   (WALL 3)
#   madv     `hasattr(mem,'madvise') and MADV_HUGEPAGE is not None` -- :38
#   stsize   `os.fstat(fd).st_size`                           -- :35   (WALL 3)
type Dev is Data:
  Dev{name: String, size: U32, has_size: Bool, fd: U32, has_fd: Bool,
      refcount: U32, has_mem: Bool, tried: Bool, ioring: Bool,
      osx: Bool, win: Bool, direct: U32, blockdev: Bool, madv: Bool,
      stsize: U32, t: Tr}

# ops_disk.py:73 DiskBuffer. `d` is Python's `self.device` -- the OBJECT -- so
# `_buf`'s `assert hasattr(self.device,"mem")` at :78 reaches it through here.
# Embedding the `Dev` rather than its name is what makes :78 a STATE predicate
# instead of a parameter, and it costs nothing: no def that RECORDS a call ever
# reads a `Db` (the recording defs take the `Dev` as their own parameter), so the
# copy of `t` a `Db` carries is never stale where it is read.
type Db is Data:
  Db{d: Dev, size: U32, offset: U32}

# `memoryview(mem)[offset : offset+size]` -- :79. `hi` is the SUM and it is a
# READER rather than a field, so the two cannot disagree.
type Win is Data:
  Win{lo: U32, size: U32}

# `_buf`'s answer: the window plus the device, so the caller that goes on to record
# a call gets the GROWN trace and not the pre-call copy.
type DbB is Data:
  DbB{w: Win, d: Dev}

# :86 `BufferStorage(opaque, None, MMIOInterface(mv_address(...), size))`. `addr`
# is WALL 1 and is a 0; `b` is the `DiskBuffer` (and :144's `_offset` builds a new
# one of exactly this shape); `d` is the grown device.
type Rc is Data:
  Rc{b: Db, addr: U32, d: Dev}

# `_copyout`'s OSX arm's per-read destination offsets, and the grown device.
type Roff is Data:
  Roff{offs: List<&2, U32>, d: Dev}

# ONE yielded segment of :114 -- `(copy_batch, copied_in, minor_offset,
# real_copy_size)` with `copy_batch` dropped (the host's buffer, WALL). `off` is
# the loop variable and `rd` is `read_size`; all five are what `dk_shard_a` and
# `dk_shard_b` print in one string.
type Seg is Data:
  Seg{off: U32, rd: U32, cin: U32, moff: U32, real: U32}

# the shard's answer: the segments, and the device the segment `_copyout`s left.
type ShOut is Data:
  ShOut{segs: List<&2, Seg>, d: Dev}

# :101-104 -- everything that does not change between segments.
type Sh is Data:
  Sh{sz: U32, seg: U32, total: U32, fd_off: U32, devsize: U32}

def Sh.sz(s: Sh) -> U32:
  match s:
    case Sh{sz, seg, total, fd_off, devsize}: sz

def Sh.seg(s: Sh) -> U32:
  match s:
    case Sh{sz, seg, total, fd_off, devsize}: seg

def Sh.total(s: Sh) -> U32:
  match s:
    case Sh{sz, seg, total, fd_off, devsize}: total

def Sh.fd_off(s: Sh) -> U32:
  match s:
    case Sh{sz, seg, total, fd_off, devsize}: fd_off

def Sh.devsize(s: Sh) -> U32:
  match s:
    case Sh{sz, seg, total, fd_off, devsize}: devsize

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every host call in this file goes through it,
# so the trace is the ordered list of syscalls a port of this file will make.
# ===========================================================================
def Tr.of() -> Tr: Tr{Nil{}, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused}: refused

# the id the NEXT emit mints, i.e. what `os.open`/`shm_open` would answer. Read
# BEFORE the emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# the port of `raise AssertionError`. The latch, and `Tr.emit` is the one place
# that consults it, so nothing below needs a guard of its own.
def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused}: Tr{calls, next, True{}}

# `Bool.pick` evaluates BOTH arms, so the emitted call is a value built here and
# the guard is a parameter. `ops_webgpu.bend`'s `Tr.emit.go`, unchanged in shape.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)),
     refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, next, +refused}: Tr.emit.go(refused, k, arg, calls, next)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in order;
# `Tr.count` is how many; `Tr.pairs` is the whole trace flattened to k,arg,k,arg;
# `Tr.has` is "contains this (tag, arg) sequence, in order".
#
# `Tr.has` is `ops_webgpu.bend`'s matcher verbatim INCLUDING the fuel being the
# TRACE length rather than the pattern length -- the defect that made eight of that
# file's order rows unable to fail. `dk_has_rejects_reverse` and
# `dk_has_rejects_absent` pin the matcher here rather than trusting it.
# ===========================================================================
def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one
# of them would walk the trace twice over.
def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

# the WHOLE trace as a flat `k,arg,k,arg` list, which is what makes `seq_eq` a
# total-sequence comparison rather than a subsequence one. The recorded "put all
# the facts in one string" rule, for a trace.
def Tr.pairs.go(n: Nat, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t:
          Tr.pairs.go(m, t,
            List.append(&2, U32, List.append(&2, U32, acc, [kk]), [aa]))

def Tr.pairs(+cs: List<&2, Call>) -> List<&2, U32>:
  Tr.pairs.go(List.length(&2, Call, cs), cs, Nil{})

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

# is the WHOLE trace this exact sequence? Stronger than `seq` and it is what the
# `dk_close_*` and `dk_two_*` rows want: "the free did exactly these two calls".
def seq_eq(t: Tr, pat: List<&2, Call>) -> Bool:
  u32_list_eq(Tr.pairs(Tr.calls(t)), Tr.pairs(pat))

def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, +at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, +at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

# Python's `min` is `U32.min` -- `min(min(a, b), c)` for the three-term form.
# `U32.min` destructures its arguments rather than reading them, so each one is
# consumed ONCE; the `U32.is_le` spelling at the two sites below was a first
# draft and read each term twice, which `U32` cannot express.

# ===========================================================================
# THE DEVICE. Sixteen fields and sixteen readers, and the readers are the floor
# this port pays for a `Data` record with no field projections (rule 27).
# ===========================================================================
def Dev.of(name: String) -> Dev:
  Dev{name, 0, False{}, 0, False{}, 0, False{}, False{}, False{},
      False{}, False{}, 0, False{}, True{}, 0, Tr.of()}

def Dev.name(d: Dev) -> String:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: name

def Dev.size(d: Dev) -> U32:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: size

def Dev.has_size(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: hs

def Dev.fd(d: Dev) -> U32:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: fd

def Dev.has_fd(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: hf

def Dev.refcount(d: Dev) -> U32:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: rc

def Dev.has_mem(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: hm

def Dev.tried(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: tr

def Dev.ioring(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: io

def Dev.osx(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: osx

def Dev.win(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: win

def Dev.direct(d: Dev) -> U32:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: dr

def Dev.blockdev(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: bd

def Dev.madv(d: Dev) -> Bool:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: mv

def Dev.stsize(d: Dev) -> U32:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: ss

def Dev.tr(d: Dev) -> Tr:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}: t

# THE ARENA RULE, the same one `ops_webgpu.bend` states: `Dev` carries a growing
# `Tr`, so a def that records a call must hand back the `Dev` and not just its
# trace. Every step below returns a `Dev`.
def dev_put(d: Dev, t: Tr) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, _}:
      Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}

# AN EMPTY TRACE THAT KEEPS THE DEVICE STATE, so a gate can read ONE step in
# isolation and use a WHOLE-trace comparison. This is `ops_webgpu.bend`'s
# `Tr.reset` and it is the ONLY way a `seq_eq` row can be written at all: every
# fixture in this file carries the four io_uring calls from `dev_init` in front of
# the step under test, so `seq_eq(Dev.tr(x), [...])` would be False for every
# correct step. `dk_close_exactly_two` and `dk_copyin_at_zero` are the rows that
# need it and they say so where they are used.
def dev_reset(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, Tr.of()}

# the six HOST facts as one setter, so a fixture reaches each cell of a
# conjunction with one call instead of six.
def dev_cfg(osx: Bool, win: Bool, direct: U32, blockdev: Bool, madv: Bool,
            stsize: U32, d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, _, _, _, _, _, _, t}:
      Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, direct, blockdev,
          madv, stsize, t}

# ===========================================================================
# THE PATH, and it is the naming table this file owns.
#
# :26  `filename = self.device[len("disk:"):]`
#
# `Compiled.__init__` (device.py:376) stores the device string VERBATIM, so the
# prefix is still there and the slice strips five characters. `disk:` with nothing
# after it names the empty path, which is a real (if useless) answer and not an
# error -- `dk_file_bare` is that row.
# ===========================================================================
def DISK_PREFIX() -> String: "disk:"
def SHM_PREFIX() -> String: "shm:"
def SLASH() -> Char: Char.from_u32(47)

def dsk_filename(name: String) -> String:
  String.drop(name, String.length(DISK_PREFIX()))

# `filename[4:].lstrip("/")` -- :29. `String.trim_start` is WHITESPACE-only in
# 2.0.34 and takes no `Char`, and `String.split` pushes the separator back onto
# every piece (`nn/state.bend:195` measured both), so a char-list walk is the
# honest spelling. This is `state.bend`'s `sd_lstrip` with `/` instead of `.`, and
# it is not a shared helper because `state.bend` is read-only here.
type Lst is Data:
  Lst{seen: Bool, acc: List<&2, Char>}

def Lst.acc(s: Lst) -> List<&2, Char>:
  match s:
    case Lst{seen, acc}: acc

# `seen` IS THE CONDITION, not a status: a slash is dropped only while nothing has
# been kept yet. Dropping on `cut` alone is a `replace("/","")` and eats the
# interior slash, which is what this did first -- `dk_shm_trailing_kept` is the row,
# and it is the only row in the file that can tell `lstrip("/")` from a global
# replace.
def Lst.step(+cut: Bool, c: Char, s: Lst) -> Lst:
  match s:
    case Lst{seen, +acc}:
      +keep: Bool = Bool.or(seen, Bool.not(cut))
      Lst{keep, Bool.pick(List<&2, Char>, keep,
                          List.append(&2, Char, acc, [c]), acc)}

def Lst.drop(cs: List<&2, Char>, +s: Lst) -> List<&2, Char>:
  match cs:
    case Nil{}: Lst.acc(s)
    case +c <> t: Lst.drop(t, Lst.step(Char.is_eq(c, SLASH()), c, s))

def dsk_lstrip(s: String) -> String:
  String.from_list(Lst.drop(String.to_list(s), Lst{False{}, Nil{}}))

# :29 -- `"/"+filename[4:].lstrip("/")`. The leading slash is UNCONDITIONAL, so
# "shm:" with nothing after it names "/" and not "". That is shm_open's convention
# (a POSIX name must start with a slash) and it is why `dk_shm_empty` is "/".
def dsk_shm_name(fn: String) -> String:
  String.concat(["/", dsk_lstrip(String.drop(fn, String.length(SHM_PREFIX())))])

# :28 -- `sys.platform != "win32" and filename.startswith("shm:")`. TWO conjuncts
# and the first is the platform: on win32 a `shm:` name is opened as a FILE whose
# name is literally "shm:foo". `dk_is_shm_win` is the row that says so.
def dev_is_shm(name: String, win: Bool) -> Bool:
  Bool.and(Bool.not(win), String.starts_with(dsk_filename(name), SHM_PREFIX()))

# `Compiled.__init__` (device.py:397) reads the SECOND colon field, so a
# `disk:2:/tmp/x` names device 2. Nothing in `ops_disk.py` reads it and neither
# does this port; `dk_device_id` is the row that says so rather than leaving the
# field unconsidered.
def dsk_device_id(name: String) -> U32: DV.dev_id(name)

# ===========================================================================
# THE CLASS LIFECYCLE, :12-20 and :50-71.
# ===========================================================================

# :12 -- `def synchronize(self, timeout=None): pass`. It is the ONLY
# synchronisation a DiskDevice does and it does nothing, so it records nothing.
# `dk_sync_noop` is a LIST comparison rather than a count, so it is the claim
# "adding it changed nothing" and not the claim "there are four calls".
def dev_sync(d: Dev) -> Dev: d

# :51 -- `DiskDevice._tried_io_uring_init = True`, set FIRST and before the
# platform test, so a device on a non-linux host has still TRIED -- which is the
# whole of :15's guard. The flag is a CLASS attribute, so it is on the `Dev`.
def dev_tried(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, rc, hm, True{}, io, osx, win, dr, bd, mv, ss, t}

# :71 -- `DiskDevice.io_uring = struct_io_uring(...)`. Also a class attribute, so
# :106's `hasattr(DiskDevice,'io_uring')` reads it.
def dev_ioring.store(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, rc, hm, tr, True{}, osx, win, dr, bd, mv, ss, t}

# :57-61 -- three `libc.mmap` calls whose file OFFSETS are named in Python and
# whose lengths are not (:57 offset 0, :58 `IORING_OFF_CQ_RING`, :60
# `IORING_OFF_SQES`). The offsets are what the trace carries. THREE STEPS AND NOT
# ONE: `Tr.emit(k, a, Tr.emit(k2, b, t))` appends the INNER call first, so nesting
# the three reverses Python's order -- which is what this did first, and what
# `dk_ioring_order` is for.
def dev_ioring.mmaps(+d: Dev) -> Dev:
  +a: Dev = dev_put(d, Tr.emit(K_MMAP(), 0, Dev.tr(d)))
  +b: Dev = dev_put(a, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(a)))
  dev_put(b, Tr.emit(K_MMAP(), IORING_OFF_SQES(), Dev.tr(b)))

# :54 -- `libc.syscall(NR_io_uring_setup, 4096, byref(p))`. `p` is the WALL; the two
# numbers Python spells itself are the syscall number and the entry count.
def dev_ioring.setup(+d: Dev) -> Dev:
  dev_put(d, Tr.emit(K_IOURING_SETUP(), IORING_ENTRIES(), Dev.tr(d)))

# :55 -- `if fd < 0: return`. The syscall's answer is the seam's, so the guard is
# a parameter.
def dev_ioring.enter(ok: Bool, +d: Dev) -> Dev:
  match ok:
    case True{}:  dev_ioring.store(dev_ioring.mmaps(dev_ioring.setup(d)))
    case False{}: dev_ioring.setup(d)

# :53 -- `if sys.platform == 'linux' and not hasattr(sys, "getandroidapilevel")`.
# The android half is `sys.platform == 'linux'` being False on android, so one Bool
# is the whole predicate; the parameter is named `linux` for that reason.
def dev_ioring_setup(linux: Bool, ok: Bool, +d: Dev) -> Dev:
  dev_tried(Bool.pick(Dev, linux, dev_ioring.enter(ok, d), d))

# :14-20 -- `__init__`. The class flag is set by `dev_ioring_setup` BEFORE the
# device is handed back, so a second `Device['disk']` never re-enters the setup, and
# the three `None`s at :17-19 are the `has_size`/`has_fd`/`refcount` zeros.
def dev_init.at(linux: Bool, ok: Bool, name: String) -> Dev:
  dev_cfg(False{}, False{}, open_direct(False{}, True{}), False{}, True{}, 0,
          dev_ioring_setup(linux, ok, Dev.of(name)))

def dev_init(name: String) -> Dev: dev_init.at(True{}, True{}, name)

# ===========================================================================
# `_might_open`, :21-40. Two branches and six steps, and each is one Python line.
# ===========================================================================

# :22 -- `assert self.size is None or size <= self.size`. The message is the
# f-string and `dev_reopen_msg` IS it, so the gate can diff the string.
def dev_fits(+size: U32, +d: Dev) -> Bool:
  Bool.or(Bool.not(Dev.has_size(d)), U32.is_le(size, Dev.size(d)))

# THE MESSAGE INTERPOLATES `self.size`, WHICH IS `None` ON A COLD DEVICE -- so the
# string is `"opened with None"` and not `"opened with 0"`. The port carries size in
# a `U32` and presence in `has_size`, so `None` is the `has_size == False` arm.
# `dk_fresh_msg` is the row, and it is a row against a COLD fixture precisely
# because that is the only way to reach the `None`.

def dev_reopen_msg(+size: U32, +d: Dev) -> String:
  String.concat(["can't reopen Disk tensor with larger size, opened with ",
                 Bool.pick(String, Dev.has_size(d), U32.show(Dev.size(d)), "None"),
                 ", tried to open with ", U32.show(size)])

# :23 -- `self.size is not None and hasattr(self,"mem")`. TWO conjuncts and they are
# not the same test: `size` is set at :37 and `mem` at :30/:36, and :49 clears ONLY
# `size`. So a device just closed has `size is None` and still `hasattr(self,
# "mem")`, and `has_mem` alone is not "open".
def dev_is_open(+d: Dev) -> Bool: Bool.and(Dev.has_size(d), Dev.has_mem(d))

# :23-25 -- the fast path: `self.refcount += 1; return`. NO call is recorded,
# because no syscall happens, and `dk_warm_calls` is the row that says so.
def dev_warm(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, U32.add(rc, 1), hm, tr, io, osx, win, dr, bd,
          mv, ss, t}

# `self.mem` is assigned in BOTH branches (:30, :36), so this is what :79's
# `memoryview(self.device.mem)` needs and it is the field `has_mem` tracks.
def dev_have_mem(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, rc, True{}, tr, io, osx, win, dr, bd, mv, ss, t}

# :29-31 -- the shm branch. `shm_open(name, O_RDWR, 0o600)`, then the mapping, then
# `os.close(fd)` -- THREE calls, and the close is of the SHM descriptor, which is
# NOT `self.fd`: :17 left `self.fd` None and nothing in this branch sets it.
# `dk_shm_fd_none` is the row.
def dev_shm.on(+size: U32, +d: Dev) -> Dev:
  +fd: U32 = Tr.here(Dev.tr(d))
  dev_have_mem(dev_put(d, Tr.emit(K_CLOSE(), fd,
    Tr.emit(K_MMAP_SHM(), mem_flags(Dev.osx(d)),
      Tr.emit(K_SHM_OPEN(), SHM_MODE(), Dev.tr(d))))))

# :33-34 -- the try/except, with NO branch parameter (see THE EXCEPT IS NOT A BRANCH
# in the header): both opens are recorded, in this order, each with its own flags.
# `dk_open_file_trace` is the row that pins the two numbers.
def dev_fd(f: U32, d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, f, True{}, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}

# :33-34 -- the try/except, with NO branch parameter (see THE EXCEPT IS NOT A
# BRANCH in the header): both opens are recorded, in this order, each with its own
# flags. `dk_open_file_trace` is what pins the two numbers, and THEY DIFFER:
# `open_flags(0)` is :34's `O_RDWR|O_CREAT`. Passing `dr` to both -- which is what
# this did first -- makes the fallback trace 16450, a trace no read of Python
# supports.
def dev_file.open.at(+dr: U32, +osx: Bool, +d: Dev) -> Dev:
  +f: U32 = Tr.here(Dev.tr(d))
  +e: Dev = dev_put(d, Tr.emit(K_OPEN_DIRECT(), open_flags(osx, dr), Dev.tr(d)))
  dev_fd(f, dev_put(e, Tr.emit(K_OPEN(), open_flags(osx, 0), Dev.tr(e))))

# :35 -- `if not pathlib.Path(filename).is_block_device() and os.fstat(fd).st_size
# < size: os.ftruncate(fd, size)`.
#
# THE `and` SHORT-CIRCUITS, and that is a CALL SEQUENCE question and not a predicate
# question: `os.fstat` is an ARGUMENT of the second conjunct, so a block device never
# stats the file at all and the trace has NO `fstat` in it. That is why this is TWO
# `.at`s and not one -- my first version folded the conjunction into one parameter and
# emitted `fstat` for the block-device fixture, which is wrong, and `dk_blockdev_fstat`
# is the row that says so. **A short-circuiting `and` in Python is TWO defs in Bend
# whenever the right side has a side effect, and the gate row has to be the one that
# counts the CALL rather than the one that tests the predicate.**
def dev_file.trunc.go(trunc: Bool, +size: U32, +d: Dev) -> Dev:
  match trunc:
    case True{}:
      dev_put(d, Tr.emit(K_FTRUNCATE(), size,
        Tr.emit(K_FSTAT(), Dev.stsize(d), Dev.tr(d))))
    case False{}:
      dev_put(d, Tr.emit(K_FSTAT(), Dev.stsize(d), Dev.tr(d)))

def dev_file.trunc.at(block: Bool, trunc: Bool, +size: U32, +d: Dev) -> Dev:
  match block:
    case True{}:  d
    case False{}: dev_file.trunc.go(trunc, size, d)

# :35's SECOND conjunct on its own: `os.fstat(fd).st_size < size`. A `match` may not
# scrutinise a call, and the FIRST conjunct is a separate `.at` above because the `and`
# short-circuits a CALL. See `dev_file.trunc.at`.
def dev_trunc(+size: U32, +d: Dev) -> Bool: U32.is_lt(Dev.stsize(d), size)

# :36 -- `self.mem = mmap.mmap(self.fd, size)`, with NO flags: a plain mapping,
# unlike the shm branch's :30. `dk_open_file_mmap_plain` is the row, and the tag is
# SHARED with :30 and :57-:60 on purpose -- :36 and :30 are different mappings and
# the gate says which by its ARGS, since :36's arg is the size and :30's is the
# flags.
# THE TRACE IS A PARAMETER HERE rather than read off `d`, and `d` is passed
# SEPARATELY, because :36 runs after :35 has already advanced the trace: `d`'s own
# `Tr` is the one :35 left behind. Reading `Dev.tr(d)` at this point and passing it
# alongside `d` would be a second read of the same field with no way to say which
# copy is meant, and `dev_file.at` is the caller that shows which is which.
def dev_file.mmap.at(+size: U32, +t: Tr, d: Dev) -> Dev:
  dev_put(d, Tr.emit(K_MMAP(), size, t))

# :32-36 -- the whole file branch as Python writes it: open, take the
# fstat/truncate decision, then map.
# the two flags, in the order `dev_file.trunc.at` wants them: the block device first
# (because it gates whether `fstat` happens at all) and the size comparison second.
def dev_file.at(block: Bool, +size: U32, +d: Dev) -> Dev:
  +osx: Bool = Dev.osx(d)
  +e: Dev = dev_file.trunc.at(block, dev_trunc(size, d), size,
                             dev_file.open.at(Dev.direct(d), osx, d))
  dev_have_mem(dev_file.mmap.at(size, Dev.tr(e), e))

# :37 -- `self.size = size`. One field and one flag, and no call. THE FIELD IS
# `_` IN THE PATTERN, because naming it would shadow the `size` PARAMETER and the
# assignment would become a no-op: Bend lets a binder shadow an in-scope name, so
# `case Dev{name, size, ...}: Dev{name, size, ...}` typechecks, keeps the OLD size
# and still sets the flag. `dk_open_size` is the row that saw 0 for an open of
# 10000 before the binder was made `_`.
def dev_sized(+size: U32, d: Dev) -> Dev:
  match d:
    case Dev{name, _, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, True{}, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}

# :40 -- `self.refcount += 1`. And no call.
def dev_bumped(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, U32.add(rc, 1), hm, tr, io, osx, win, dr, bd,
          mv, ss, t}

# :38-39 -- `if hasattr(self.mem,'madvise') and (hp := getattr(mmap,
# "MADV_HUGEPAGE", None)) is not None: with contextlib.suppress(OSError):
# self.mem.madvise(hp)`. The guard is the seam's and rides on `Dev.madv`; the
# `suppress` means a FAILING madvise is recorded and execution continues, so this
# is not a truncation -- it is the second swallowed failure in the file.
def dev_finish.on(+size: U32, d: Dev) -> Dev:
  +e: Dev = dev_sized(size, d)
  dev_bumped(dev_put(e, Tr.emit(K_MADVISE(), madv_hp(Dev.osx(e)), Dev.tr(e))))

def dev_finish.off(+size: U32, d: Dev) -> Dev: dev_bumped(dev_sized(size, d))

def dev_finish.at(madv: Bool, +size: U32, +d: Dev) -> Dev:
  Bool.pick(Dev, madv, dev_finish.on(size, d), dev_finish.off(size, d))

def dev_might_open.cold.at(shm: Bool, +size: U32, +d: Dev) -> Dev:
  match shm:
    case True{}:
      dev_finish.at(Dev.madv(d), size, dev_shm.on(size, d))
    case False{}:
      dev_finish.at(Dev.madv(d), size,
                    dev_file.at(Dev.blockdev(d), size, d))

def dev_might_open.body.at(open: Bool, shm: Bool, +size: U32, +d: Dev) -> Dev:
  match open:
    case True{}:  dev_warm(d)
    case False{}: dev_might_open.cold.at(shm, size, d)

# the ONE entry point, :21. A `match` may not scrutinise a call, so the two
# predicates (:22's assert and :28's shm test) arrive as parameters of `.at` and
# are computed here, in Python's own order.
def dev_might_open.at(shm: Bool, fits: Bool, +size: U32, +d: Dev) -> Dev:
  match fits:
    case True{}:  dev_might_open.body.at(dev_is_open(d), shm, size, d)
    case False{}: dev_put(d, Tr.refuse(Dev.tr(d)))

def dev_might_open(+size: U32, +d: Dev) -> Dev:
  dev_might_open.at(dev_is_shm(Dev.name(d), Dev.win(d)), dev_fits(size, d), size, d)

# ===========================================================================
# `_might_close`, :41-49. The refcount goes DOWN first and unconditionally, and
# the close is keyed on the result being ZERO -- so a free with no matching
# `_might_open` walks the count away from zero and closes ONCE at the crossing.
#
# `U32` WRAPS and that is invisible HERE on purpose: 0 - 1 is 4294967295 and
# `is_zero` says False, and Python's -1 `!= 0` says False too. The wrap is VISIBLE
# in the count itself, so `dk_free_underflow_4294967294` puts the bit pattern in the
# row NAME rather than in a comment and no one has to do the mental arithmetic.
# ===========================================================================
def dev_dropped(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, size, hs, fd, hf, U32.sub(rc, 1), hm, tr, io, osx, win, dr, bd,
          mv, ss, t}

# :44 -- `if self.fd is not None: os.close(self.fd)`. On the shm branch `self.fd`
# is None, so a shm-backed device closes by MUNMAP alone. `dk_close_shm_n` is the
# row.
def dev_close_fds.at(has_fd: Bool, +d: Dev) -> Dev:
  Bool.pick(Dev, has_fd, dev_put(d, Tr.emit(K_CLOSE(), Dev.fd(d), Dev.tr(d))), d)

# :46-48 -- `if hasattr(self,"mem"): try: self.mem.close() except BufferError:
# pass`. The `pass` means a BufferError is SWALLOWED, so the unmap is recorded
# whether or not it worked. That is the third swallowed failure in the file.
def dev_close_mems.at(has_mem: Bool, +d: Dev) -> Dev:
  Bool.pick(Dev, has_mem, dev_put(d, Tr.emit(K_MUNMAP(), Dev.size(d), Dev.tr(d))), d)

# :49 -- `self.size = None`. It clears ONLY `size`: `self.mem` and `self.fd` are
# still set, so the device is "closed" and still looks mapped.
def dev_closed(d: Dev) -> Dev:
  match d:
    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      Dev{name, 0, False{}, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}

def dev_close_all(+d: Dev) -> Dev:
  dev_closed(dev_close_mems.at(Dev.has_mem(d),
                              dev_close_fds.at(Dev.has_fd(d), d)))

def dev_might_close.at(zero: Bool, +d: Dev) -> Dev:
  match zero:
    case True{}:  dev_close_all(d)
    case False{}: d

# :42-43 -- `self.refcount -= 1` and THEN `if self.refcount == 0`. THE ORDER IS THE
# WHOLE FUNCTION, so the count is walked down first and the test reads the WALKED
# value. Testing before the decrement closes a device whose refcount was 1 (the
# every-day case) and never closes one whose refcount was 0, which is what my first
# version did; `dk_close_exactly_two` is the row that caught it.
def dev_might_close(+d: Dev) -> Dev:
  +e: Dev = dev_dropped(d)
  dev_might_close.at(U32.is_zero(Dev.refcount(e)), e)

# ===========================================================================
# `DiskBuffer`, :73-79. The default `offset=0` at :74 is why `_alloc`'s buffer
# starts at 0 and `_offset`'s does not.
# ===========================================================================
def Db.of(d: Dev, size: U32, off: U32) -> Db: Db{d, size, off}

def Db.size(b: Db) -> U32:
  match b:
    case Db{d, size, offset}: size

def Db.offset(b: Db) -> U32:
  match b:
    case Db{d, size, offset}: offset

def Db.d(b: Db) -> Dev:
  match b:
    case Db{d, size, offset}: d

def Db.has_mem(b: Db) -> Bool: Dev.has_mem(Db.d(b))

def Db.name(b: Db) -> String: Dev.name(Db.d(b))

# :76 -- `def __repr__(self): return f"<DiskBuffer size={self.size}
# offset={self.offset}>"`. USER-VISIBLE, and the one string in this file a caller
# sees, so the gate diffs it against CPython's f-string rather than against itself.
def db_repr(+b: Db) -> String:
  String.concat(["<DiskBuffer size=", U32.show(Db.size(b)),
                 " offset=", U32.show(Db.offset(b)), ">"])

# :78 -- `f"DiskBuffer wasn't opened: {self.device.device}"`. The device's OWN
# string, not the buffer's, which is the one place `_buf`'s message is not about
# the buffer.
def db_not_open_msg(b: Db) -> String:
  String.concat(["DiskBuffer wasn't opened: ", Db.name(b)])

def Win.lo(w: Win) -> U32:
  match w:
    case Win{lo, size}: lo

def Win.size(w: Win) -> U32:
  match w:
    case Win{lo, size}: size

# the sum is a READER and not a field, so the two cannot disagree -- and the gate
# has a row for the window's high end precisely because `hi` is where an
# off-by-one in `offset` would show.
def Win.hi(+w: Win) -> U32: U32.add(Win.lo(w), Win.size(w))

def db_window(+b: Db) -> Win: Win{Db.offset(b), Db.size(b)}

def DbB.win(x: DbB) -> Win:
  match x:
    case DbB{w, d}: w

def DbB.dev(x: DbB) -> Dev:
  match x:
    case DbB{w, d}: d

# :77-79 -- `_buf`. The assert latches `refused` and the slice is answered either
# way: a refused `_buf` has NO answer in Python and the window is unobservable,
# because nothing after a refusal is recorded.
def db_buf.at(open: Bool, +w: Win, +d: Dev) -> DbB:
  match open:
    case True{}:  DbB{w, d}
    case False{}: DbB{w, dev_put(d, Tr.refuse(Dev.tr(d)))}

def db_buf(+b: Db, d: Dev) -> DbB: db_buf.at(Db.has_mem(b), db_window(b), d)

# ===========================================================================
# THE ALLOCATOR, :82-99. `lru = False` (:83) is a CLASS attribute no allocator
# overwrites, so it is a constant here and the row says it is False rather than
# restating the code.
# ===========================================================================
def ALLOC_LRU() -> Bool: False{}

# :84-86 -- `_alloc`: `self.dev._might_open(size)` and then the `BufferStorage`.
# `mv_address(opaque._buf())` is WALL 1, so `Rc.addr` is a 0, and `_buf()`'s assert
# fires here for the first time in a device's life.
def alloc_of(+size: U32, d: Dev) -> Rc:
  +e: Dev = dev_might_open(size, d)
  +b: Db = Db.of(e, size, 0)
  Rc{b, 0, DbB.dev(db_buf(b, e))}

# :88 -- `_free(self, storage, options): self.dev._might_close()`. The STORAGE is
# not read, which is fact A in the header and the reason this def takes a `Dev`
# and nothing else.
def alloc_free(d: Dev) -> Dev: dev_might_close(d)

# :89 -- `_as_buffer(self, src): return src._buf()`. The bare `_buf`, so it is the
# SAME assert and the SAME refusal as `_copyin`'s.
def alloc_as_buffer(b: Db, d: Dev) -> DbB: db_buf(b, d)

# :90 -- `_copyin(self, dest, src): dest._buf()[:] = src`. The window is the whole
# slice `[:]`, so the copy is `dest.size` bytes AT ZERO -- not at `dest.offset`.
# The offset is where the destination already sits in the mapping and the slice is
# relative to it. `dk_copyin_at_zero` is the row.
def alloc_copyin.put(x: DbB) -> Dev:
  match x:
    case DbB{w, +d}: dev_put(d, Tr.emit(K_COPYIN(), Win.size(w), Dev.tr(d)))

def alloc_copyin(b: Db, d: Dev) -> Dev: alloc_copyin.put(db_buf(b, d))

# :99 -- `dest[:] = src._buf()`. The window is `src`'s and the write starts at ZERO
# of that window, so the trace argument is `src.size`.
def alloc_copyout.put(x: DbB) -> Roff:
  match x:
    case DbB{w, +d}: Roff{Nil{}, dev_put(d, Tr.emit(K_COPYOUT(), Win.size(w), Dev.tr(d)))}

def alloc_copyout.posix(b: Db, d: Dev) -> Roff: alloc_copyout.put(db_buf(b, d))

# :94-97 -- the OSX arm. `io.FileIO(self.dev.fd, "a+b", closefd=False)` then
# `fo.seek(src.offset)` then the readinto loop. The mode is `"a+b"` at every call
# site and `closefd=False` means the `with` exit does NOT close the descriptor --
# which is why `K_FILEIO_CLOSE` records the `with` and not a close.
# `while (n := fo.readinto(dest[bytes_read:])) is not None and n > 0`. The byte
# count is the FILE's answer, so the chunk list is the reads that HAPPENED and the
# port's own content is the running sum `bytes_read` -- which is each read's
# DESTINATION OFFSET, and so the row that says the reads TILE the destination.
# There is no spelling of "a readinto that returned 0": the loop does not perform
# it, so the list terminates instead. `Roff.offs` is therefore the RUNNING SUMS
# themselves, accumulated as they go -- carrying a constant `Nil{}` here is what
# printed an empty `dk_copyout_osx_offs`.
def dsk_reads.done(offs: List<&2, U32>, +d: Dev) -> Roff:
  Roff{offs, dev_put(d, Tr.emit(K_FILEIO_CLOSE(), 0, Dev.tr(d)))}

def dsk_reads.go(+chunks: List<&2, U32>, offs: List<&2, U32>, +got: U32,
                 +d: Dev) -> Roff:
  match chunks:
    case Nil{}: dsk_reads.done(offs, d)
    case c <> t:
      dsk_reads.go(t, List.append(&2, U32, offs, [got]), U32.add(got, c),
                   dev_put(d, Tr.emit(K_READINTO(), got, Dev.tr(d))))

# TWO STEPS, NOT ONE: `Tr.emit(K_FILEIO(), fd, Tr.emit(K_SEEK(), off, t))` records
# the SEEK first, because the inner emit is the one that appends. Python opens the
# file and then seeks. `dk_copyout_osx_order` is the row.
def alloc_copyout.osx(+chunks: List<&2, U32>, off: U32, fd: U32, +d: Dev) -> Roff:
  +e: Dev = dev_put(d, Tr.emit(K_FILEIO(), fd, Dev.tr(d)))
  dsk_reads.go(chunks, Nil{}, 0, dev_put(e, Tr.emit(K_SEEK(), off, Dev.tr(e))))

# :92 -- `if OSX and self.dev.fd is not None`. TWO conjuncts, and the second is the
# one the shm branch loses: `self.fd` is None there, so a `disk:shm:` device takes
# the `dest[:] = src._buf()` arm even on OSX. `dk_copyout_shm_posix` is the row, and
# it is the only thing in the file that sees it.
def alloc_copyout.at(arm: Bool, +chunks: List<&2, U32>, +b: Db, +d: Dev) -> Roff:
  match arm:
    case True{}:  alloc_copyout.osx(chunks, Db.offset(b), Dev.fd(d), d)
    case False{}: alloc_copyout.posix(b, d)

def alloc_copyout(chunks: List<&2, U32>, b: Db, +d: Dev) -> Roff:
  alloc_copyout.at(Bool.and(Dev.osx(d), Dev.has_fd(d)), chunks, b, d)

def Roff.offs(r: Roff) -> List<&2, U32>:
  match r:
    case Roff{offs, d}: offs

def Roff.dev(r: Roff) -> Dev:
  match r:
    case Roff{offs, d}: d

# :144 -- `_offset(self, buf, size, offset): return DiskBuffer(buf.device, size,
# offset)`. A NEW buffer on the SAME device: `size` and `offset` are the caller's,
# `offset` does NOT ACCUMULATE (that is `Buffer.view`, device.py:252, which this is
# not) and the device's refcount does not move. `dk_offset_off` is the row that pins
# the non-accumulation, against a buffer that already has offset 4.
def alloc_offset(size: U32, off: U32, b: Db) -> Db: Db.of(Db.d(b), size, off)

def Rc.b(r: Rc) -> Db:
  match r:
    case Rc{b, addr, d}: b

def Rc.addr(r: Rc) -> U32:
  match r:
    case Rc{b, addr, d}: addr

def Rc.d(r: Rc) -> Dev:
  match r:
    case Rc{b, addr, d}: d

# ===========================================================================
# `_copyout_sharded`, :101-116. THE RESULT-CAN-BE-CHECKED PART, and the header
# says why. Read the gate's section 7 before changing anything here.
# ===========================================================================

# :103 -- `minor_offset := src.offset % mmap.PAGESIZE`, the page skew of the source.
# `U32.mod` and Python's `%` agree for a positive dividend, which an offset is.
def shard_minor(off: U32, osx: Bool) -> U32: U32.mod(off, pagesize(osx))

# :103 -- `fd_offset = src.offset - minor_offset`. The PAGE-ALIGNED file offset, and
# it is where the first read starts; every segment's file offset is
# `fd_offset + off`. `+off` because `minor_offset` is computed from the same value.
def shard_fd_off(+off: U32, osx: Bool) -> U32: U32.sub(off, shard_minor(off, osx))

# :104 -- `total_copy_size = round_up(size + minor_offset, mmap.PAGESIZE)`. The
# skew is ADDED, so the total covers the skew AND the request.
def shard_total(size: U32, +off: U32, +osx: Bool) -> U32:
  H.round_up_u32(U32.add(size, shard_minor(off, osx)), pagesize(osx))

# `range(0, total_copy_size, seg_len)` -- the segment COUNT, which is
# `ceil(total/seg)`. `seg == 0` is an empty range in Python and 0 here, because
# `U32.div(x, 0) = 0`; that is one of the two places this file leans on the
# documented div, and `dk_shard_seg0_n` is the row. `+seg` because the ceil reads it
# twice.
def shard_n(total: U32, +seg: U32) -> U32:
  Bool.pick(U32, U32.is_zero(seg), 0,
            U32.div(U32.add(total, U32.sub(seg, 1)), seg))

# :110's THIRD TERM ON ITS OWN -- `src.device.size - fd_offset - off` -- with no
# `min` around it, so a gate can print the value that is about to wrap. `dk_shard_
# raw_third_d` is the row and it is 4294965248 on the short-mapping fixture: the bit
# pattern of -2048. This def exists ONLY for that row; the fold reads `shard_read`.
def shard_raw_third(off: U32, +sh: Sh) -> U32:
  U32.sub(U32.sub(Sh.devsize(sh), Sh.fd_off(sh)), off)

# :110 -- `read_size = min(seg_len, total_copy_size - off, src.device.size -
# fd_offset - off)`. THREE terms, and the third goes NEGATIVE if the mapping is
# shorter than the shard asks for; `U32` then WRAPS and the `min` picks `seg_len`,
# which is a plausible wrong answer rather than a crash. That is why
# `dk_shard_third_*` is a gate row and not a comment: it is the invariant that keeps
# the third term from wrapping, and only an invariant can be checked without the
# file.
def shard_read(+off: U32, +sh: Sh) -> U32:
  U32.min(U32.min(Sh.seg(sh), U32.sub(Sh.total(sh), off)), shard_raw_third(off, sh))

# :113 -- `real_copy_size = min(read_size - minor_offset, size - copied_in)`. The
# skew is subtracted from the FIRST segment only (it is zeroed at :115) and the
# second term truncates the LAST. This is the line the whole function exists for.
def shard_real(+rd: U32, +moff: U32, +sh: Sh, +cin: U32) -> U32:
  U32.min(U32.sub(rd, moff), U32.sub(Sh.sz(sh), cin))

def Seg.off(s: Seg) -> U32:
  match s:
    case Seg{off, rd, cin, moff, real}: off

def Seg.rd(s: Seg) -> U32:
  match s:
    case Seg{off, rd, cin, moff, real}: rd

def Seg.cin(s: Seg) -> U32:
  match s:
    case Seg{off, rd, cin, moff, real}: cin

def Seg.moff(s: Seg) -> U32:
  match s:
    case Seg{off, rd, cin, moff, real}: moff

def Seg.real(s: Seg) -> U32:
  match s:
    case Seg{off, rd, cin, moff, real}: real

def ShOut.segs(s: ShOut) -> List<&2, Seg>:
  match s:
    case ShOut{segs, d}: segs

def ShOut.d(s: ShOut) -> Dev:
  match s:
    case ShOut{segs, d}: d

# :107-115 -- the whole non-uring loop as one fold. `rem` is the FIRST parameter
# because it is the fuel and what shrinks; `off`, `cin` and `moff` GROW or stay and
# are `+` so one arm can read each of them more than once. The `K_COPYOUT` per
# segment is :111's `self._copyout(local_buf[:read_size], DiskBuffer(src.device,
# read_size, fd_offset + off))` -- and it is the POSIX arm unconditionally, because
# `dest` there is a host `bytearray` slice rather than a Disk buffer. That is blind
# spot 1 at the foot of this file, restated where the fold is.
def shard.go(rem: Nat, +off: U32, +cin: U32, +moff: U32, +sh: Sh, +d: Dev,
             acc: List<&2, Seg>) -> ShOut:
  match rem:
    case 0n: ShOut{acc, d}
    case 1n+m:
      +rd: U32 = shard_read(off, sh)
      +rl: U32 = shard_real(rd, moff, sh, cin)
      sg: Seg = Seg{off, rd, cin, moff, rl}
      shard.go(m, U32.add(off, Sh.seg(sh)), U32.add(cin, rl), 0, sh,
               dev_put(d, Tr.emit(K_COPYOUT(), rd, Dev.tr(d))),
               List.append(&2, Seg, acc, [sg]))

# :104-116 -- the entry point to the non-uring arm. `shard_n` counts SEGMENTS in
# `U32` because it is the same division `range` does, and the fold's fuel is the
# segment count as a `Nat` because `Nat` is what says the fold terminates.
def shard_at(+seg_len: U32, +size: U32, +off: U32, devsize: U32, +osx: Bool,
             d: Dev) -> ShOut:
  +tot: U32 = shard_total(size, off, osx)
  shard.go(U32.to_nat(shard_n(tot, seg_len)), 0, 0, shard_minor(off, osx),
           Sh{size, seg_len, tot, shard_fd_off(off, osx), devsize}, d, Nil{})

# :118-142 -- the io_uring arm. ONE line of it is portable arithmetic and it is
# :132, `real_copy_size := min(sqe.len - minor_offset, size - copied_in)`, which is
# `shard_real` with `sqe.len` where the non-uring arm has `read_size` -- and
# `sqe.len` is `min(seg_len, total_copy_size - next_read_offset)` (:125), so the
# THIRD term of the non-uring `read_size` is simply ABSENT. That is a real
# divergence between the two arms whenever the mapping is shorter than the shard,
# and this port records the two submission calls and then delegates the segment
# arithmetic. That is a LISTED BLIND SPOT, not a claim, and `dk_shard_ioring_order`
# is the row for what this port does do.
#
# ==== THE BLIND SPOTS THIS PORT HAS, and none of them is a gap in the gate ====
#
# These are the places where the port is KNOWN to diverge from `ops_disk.py`. They
# are listed because a divergence that is not written down is indistinguishable
# from a port that is correct, and each one names the row that would catch it if it
# were implemented.
#
# 1. **THE `io_uring` ARM'S SEGMENT ARITHMETIC IS NOT PORTED.** :119-141 is a pair
#    of while-loops over `sq.ktail`/`cq.khead` and the port records the two
#    submission calls and then computes the segments with the NON-uring fold. This
#    is only correct because :132's `real_copy_size := min(sqe.len - minor_offset,
#    size - copied_in)` IS `shard_real` and :125's `sqe.len` is
#    `min(seg_len, total_copy_size - next_read_offset)` -- i.e. the third term of the
#    non-uring `read_size` is ABSENT. The two arms agree whenever the mapping is at
#    least as long as the shard, which is the invariant `ops_disk.py` relies on, and
#    DISAGREE on fixture D. `dk_shard_ioring_order` is what the port does; nothing
#    checks that it should do more.
# 2. **THE SEAM IS NOT A SEAM.** `os.open` answers a descriptor, `mmap.mmap` answers
#    a mapping, `os.fstat().st_size` answers a size and `_posixshmem.shm_open`
#    answers a descriptor: none of them exists here, so the port MINTS identifiers
#    from a counter and takes the size from a fixture field. Every row about "which
#    descriptor" or "how big is the file" is a row about the counter and the fixture.
#    `dk_open_file_fd` names one such row and says so.
# 3. **`_posixshmem` MAY NOT BE IMPORTED.** :6 wraps it in
#    `contextlib.suppress(ImportError)`, so on a host without it :29 raises
#    AttributeError. The port has no such branch: it always takes the shm path.
#    `dk_is_shm_win` is the adjacent row and it is about `sys.platform`, not about
#    the import.
# 4. **`_copyout_sharded`'s `_get_free_buf` IS NOT PORTED.** :109's
#    `while (copy_batch := _get_free_buf()) is None: pass` is a blocking wait on the
#    caller's allocator, and the port assumes it always succeeds. The segments it
#    yields are independent of WHICH buffer it got, so this is invisible in the
#    arithmetic -- and `dk_shard_cover_*` would be the row that noticed if it were
#    not.
# 5. **THE `_might_open` ASSERT IS NOT AN EXCEPTION.** :22 raises `AssertionError`
#    and the port LATCHES `refused` instead, which is the template's discipline: no
#    later emit records anything, so a refusal shows up as a TRUNCATION of the trace
#    rather than as an exception value. `dk_grow_trace_unchanged` and
#    `dk_grow_refused` are the two rows, and `dk_buf_refused_calls` is the third.
# TODO(p3) ops_disk.py:119  -- the two while-loops of the io_uring arm.
# TODO(p3) ops_disk.py:122  -- ktail/kring_mask and the sqe array.
# TODO(p3) ops_disk.py:128  -- sq.array[sqe_index] = sqe_index; ktail[0] += 1.
# TODO(p3) ops_disk.py:139  -- `assert cqe.res >= 0`, the third assert in the file.
def shard_ioring(seg_len: U32, size: U32, off: U32, devsize: U32, +osx: Bool,
                 +d: Dev) -> ShOut:
  shard_at(seg_len, size, off, devsize, osx,
           dev_put(d, Tr.emit(K_IORING_ENTER(), IORING_ENTER_GETEVENTS(),
             Tr.emit(K_SQE_STORE(), 0, Dev.tr(d)))))

# :106 -- `if not hasattr(DiskDevice,'io_uring') or not use_ioring`. The `not` on
# both makes it a DISJUNCTION OF TWO NEGATIONS, so the non-uring arm is taken when
# EITHER is true, and `dk_shard_ioring_absent` / `dk_shard_no_use_ioring` are the
# two rows, one per way of reaching it.
def shard.at(go: Bool, +seg_len: U32, +size: U32, +off: U32, +devsize: U32,
             +osx: Bool, +d: Dev) -> ShOut:
  match go:
    case True{}:  shard_ioring(seg_len, size, off, devsize, osx, d)
    case False{}: shard_at(seg_len, size, off, devsize, osx, d)

# the predicate :106 computes, in one place, because `a match may not scrutinise a
# call` -- so `shard.at` above takes the conjunction as a parameter and this is the
# only place the two flags are ANDed.
def shard.pick(ioring: Bool, use_ioring: Bool, seg_len: U32, size: U32, off: U32,
               devsize: U32, +osx: Bool, +d: Dev) -> ShOut:
  shard.at(Bool.and(ioring, use_ioring), seg_len, size, off, devsize, osx, d)

# ===========================================================================
# THE PRINTING and the FIXTURES.
# ===========================================================================
def ush(xs: List<&2, U32>, +acc: List<&2, String>) ->
List<&2,
String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush(t, List.append(&2, String, acc, [U32.show(x)]))

def ujoin(xs: List<&2, U32>) -> String: String.join(ush(xs, Nil{}), ",")

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def ncalls(k: U32, t: Tr) -> U32: Tr.count(k, Tr.calls(t))
def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

def u32_is_zero(v: U32) -> Bool: U32.is_zero(v)
def u32_add(a: U32, b: U32) -> U32: U32.add(a, b)

# the WHOLE trace as ONE string, `k,arg,k,arg,...`. This is the recorded "put all
# the facts in one string" rule applied to a trace, and `dk_open_file_trace` is the
# row: every tag AND every argument of every call in one diffable value.
def trace_str(t: Tr) -> String: ujoin(Tr.pairs(Tr.calls(t)))

# the FIRST arg of the calls with tag `k`, as a `U32`, for a row that wants the
# value rather than the count. `dk_two_free_unmap_size` is the row: it is the
# evidence that `_free` reads nothing from its storage.
def first_u32(xs: List<&2, U32>, d: U32) -> U32:
  match xs:
    case Nil{}: d
    case x <> t: first_u32(t, x)

def arg_of(k: U32, t: Tr) -> U32: first_u32(Tr.args(k, Tr.calls(t)), 0)

# one segment as `off/read/cin/moff/real` -- ALL FIVE in one string, because four
# separate rows let a fixture drop one, and the recorded "put all four facts in one
# string" rule is the fix.
def seg_str(+s: Seg) -> String:
  ujoin([Seg.off(s), Seg.rd(s), Seg.cin(s), Seg.moff(s), Seg.real(s)])

def shard_str.go(xs: List<&2, Seg>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +s <> t: shard_str.go(t, List.append(&2, String, acc, [seg_str(s)]))

def shard_str(xs: List<&2, Seg>) -> String:
  String.join(shard_str.go(xs, Nil{}), " ")

# THE RESULT ROW, part one: the `real_copy_size`s must sum to exactly `size`.
def shard_cover.go(xs: List<&2, Seg>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case s <> t: shard_cover.go(t, U32.add(acc, Seg.real(s)))

def shard_cover(xs: List<&2, Seg>) -> U32: shard_cover.go(xs, 0)

# THE RESULT ROW, part two: every `copied_in` must be the running sum of the
# PREVIOUS `real_copy_size`s, so the segments TILE the destination.
def shard_contig.go(xs: List<&2, Seg>, +run: U32) -> Bool:
  match xs:
    case Nil{}: True{}
    case +s <> t:
      Bool.and(U32.is_eq(Seg.cin(s), run),
               shard_contig.go(t, U32.add(run, Seg.real(s))))

def shard_contig(xs: List<&2, Seg>) -> Bool: shard_contig.go(xs, 0)

# FIXTURES. One device per host fact, and each `fx_*` reads its input once.
def DISK() -> String: "disk:/tmp/dk.bin"
def DISK_SHM() -> String: "disk:shm:dk"
def DISK_DEV() -> String: "disk:/dev/sda"

def fx_plain() -> Dev: dev_init(DISK())
def fx_shm() -> Dev: dev_init(DISK_SHM())
def fx_osx() -> Dev:
  dev_cfg(True{}, False{}, open_direct(True{}, False{}), False{}, False{}, 0,
          fx_plain())
def fx_nomadv() -> Dev:
  dev_cfg(False{}, False{}, open_direct(False{}, True{}), False{}, False{}, 0,
          fx_plain())
def fx_blockdev() -> Dev:
  dev_cfg(False{}, False{}, open_direct(False{}, True{}), True{}, True{}, 0,
          dev_init(DISK_DEV()))
def fx_longfile() -> Dev:
  dev_cfg(False{}, False{}, open_direct(False{}, True{}), False{}, True{}, 65536,
          fx_plain())
def fx_noioring() -> Dev: dev_ioring_setup(False{}, True{}, Dev.of(DISK()))
def fx_ioring_fail() -> Dev: dev_ioring_setup(True{}, False{}, Dev.of(DISK()))

# the opened file device at `size`, the opened shm device at `size`.
def fx_open(size: U32) -> Dev: dev_might_open(size, fx_plain())
def fx_shm_open(size: U32) -> Dev: dev_might_open(size, fx_shm())

# THE shm device ON macOS. **THE SECOND FIXTURE :92 NEEDS AND DID NOT HAVE.** :92 is
# `if OSX and self.dev.fd is not None`, and the drop-the-`has_fd` conjunct mutation
# moved NOTHING while `fx_shm_open` was the only shm fixture -- because that fixture
# is a LINUX device, so `Dev.osx` is False and the first conjunct already decides the
# arm. The mutation was invisible because the fixture could not reach the conjunct,
# not because the conjunct is redundant. THIS FIXTURE REACHES IT, and
# `dk_copyout_shm_osx_*` below is the pair that kills the mutation.
def fx_shm_osx() -> Dev: dev_cfg(True{}, False{}, 0, False{}, False{}, 0, fx_shm())
def fx_shm_osx_open(size: U32) -> Dev: dev_might_open(size, fx_shm_osx())

# THE FIVE SHARD FIXTURES, and every expected value below is derived from these
# numbers rather than written down:
#   A: offset 0 (ALIGNED),   size 10000, seg 4096, mapping 40960  -> 3 segments
#   B: offset 100 (SKEWED),  size 5000,  seg 2048, mapping 65536  -> 4 segments
#   C: offset 5000 (PAST A PAGE BOUNDARY), size 5000, seg 2048, mapping 65536.
#      `fd_offset` is 4096 here and NOT 0, which is the whole point: A and B both
#      give `fd_offset == 0` and would leave that column constant.
#   D: mapping SHORTER than the shard, so `shard_read`'s third term goes NEGATIVE.
#      That is the only fixture that exercises the `U32` wrap the header warns
#      about, and without it the warning is untested prose.
#   E: THE SKEW CROSSES A PAGE BOUNDARY. `size = 3000` and `minor = 1500`, so
#      `round_up(3000 + 1500, 4096)` is 8192 and `round_up(3000, 4096)` is 4096.
#      B and C do NOT separate the two: 5000 + 100 and 5000 + 904 both round up to
#      the same 8192 that 5000 alone gives, so for three of the four fixtures :104's
#      `size + minor_offset` is indistinguishable from `size`. M34 -- drop the skew --
#      moved nothing until this fixture existed, which is the measurement that
#      produced it.
#
#      THE TWO NUMBERS ARE CHOSEN, NOT FOUND. `minor` must be BELOW `seg_len` or the
#      first segment's `real = min(seg_len - minor, size)` goes negative -- which is
#      the `U32` divergence `dk_shard_raw_third_d` records, and an E that tripped it
#      would make E a second copy of D instead of a clean reading of :104. And `size`
#      must be big enough that `size + minor` crosses 4096. `1500 < 2048` and
#      `3000 + 1500 > 4096` are exactly those two constraints, and E is the only
#      fixture satisfying both.
def shard_sh(+size: U32, +off: U32, seg: U32, devsize: U32, +osx: Bool) -> Sh:
  Sh{size, seg, shard_total(size, off, osx), shard_fd_off(off, osx), devsize}

def SH_A(osx: Bool) -> Sh: shard_sh(10000, 0, 4096, 40960, osx)
def SH_B(osx: Bool) -> Sh: shard_sh(5000, 100, 2048, 65536, osx)
def SH_C(osx: Bool) -> Sh: shard_sh(5000, 5000, 2048, 65536, osx)
def SH_D(osx: Bool) -> Sh: shard_sh(5000, 100, 2048, 4096, osx)
def SH_E(osx: Bool) -> Sh: shard_sh(3000, 1500, 2048, 65536, osx)

def dk_run_a(d: Dev, osx: Bool) -> ShOut: shard_at(4096, 10000, 0, 40960, osx, d)
def dk_run_b(d: Dev, osx: Bool) -> ShOut: shard_at(2048, 5000, 100, 65536, osx, d)
def dk_run_c(d: Dev, osx: Bool) -> ShOut: shard_at(2048, 5000, 5000, 65536, osx, d)
def dk_run_d(d: Dev, osx: Bool) -> ShOut: shard_at(2048, 5000, 100, 4096, osx, d)
def dk_run_e(d: Dev, osx: Bool) -> ShOut: shard_at(2048, 3000, 1500, 65536, osx, d)

# ===========================================================================
# THE GATE. Every expectation comes from `ops_disk.py`'s own text, from a module it
# imports, or from arithmetic over the two fixture lines above. The numeric rows
# PRINT their value, so a wrong one is diagnosable from the output alone.
# ===========================================================================

# --- 1: the naming table, :26 and :28, both directions ----------------------
def t_path() -> IO(Unit):
  do IO<Unit>:
    srow("dk_file_plain", dsk_filename(DISK()))
    srow("dk_file_bare", dsk_filename(DISK_PREFIX()))
    srow("dk_file_rel", dsk_filename("disk:relative.bin"))
    srow("dk_file_dev", dsk_filename(DISK_DEV()))
    srow("dk_file_shm", dsk_filename(DISK_SHM()))
    srow("dk_shm_plain", dsk_shm_name(dsk_filename(DISK_SHM())))
    srow("dk_shm_empty", dsk_shm_name(dsk_filename("disk:shm:")))
    # THE FINDING, AND WHY THESE ARE BOOLEAN ROWS AND NOT FIVE STRINGS.
    # `filename[4:].lstrip("/")` makes the NUMBER OF LEADING SLASHES IRRELEVANT, so
    # `disk:shm:dk`, `disk:shm:/dk` and `disk:shm://dk` all name "/dk", and
    # `disk:shm:` and `disk:shm://///` both name "/". Five string rows would be two
    # CONSTANT COLUMNS and no mutation could move either; five BOOLEAN rows are five
    # independent claims about `lstrip` and `String.drop`, and a strip that stopped
    # at the first slash dies here.
    row("dk_shm_slashes_eq_plain", String.eq(dsk_shm_name(dsk_filename("disk:shm://dk")),
                                             "/dk"))
    row("dk_shm_abs_eq_plain", String.eq(dsk_shm_name(dsk_filename("disk:shm:/dk")),
                                         "/dk"))
    row("dk_shm_allslash_eq_empty", String.eq(dsk_shm_name(dsk_filename("disk:shm://///")),
                                              "/"))
    row("dk_shm_trailing_kept", String.eq(dsk_shm_name(dsk_filename("disk:shm:a/b")),
                                          "/a/b"))
    # the REVERSE direction: which of these paths is a shm path at all.
    row("dk_is_shm_plain", dev_is_shm(DISK(), False{}))
    row("dk_is_shm_shm", dev_is_shm(DISK_SHM(), False{}))
    row("dk_is_shm_win", dev_is_shm(DISK_SHM(), True{}))
    row("dk_is_shm_prefix_only", dev_is_shm(DISK_PREFIX(), False{}))
    urow("dk_device_id", dsk_device_id("disk:2:/tmp/x"))

# --- 2: the flags, :33, :34, :39, :81 and :103, and the io_uring constants ---
# EVERY HOST FACT IS PRINTED IN BOTH CELLS, and the `_linux` rows are the ones the
# rest of the gate uses. Two cells for a two-cell fact is the whole defence against
# a port that is quietly Linux-only: `mmap.PAGESIZE` alone changes every shard row,
# and `O_CREAT` alone changes every trace argument in the open.
def t_flags() -> IO(Unit):
  do IO<Unit>:
    urow("dk_locked_linux", map_locked(False{}))
    urow("dk_locked_osx", map_locked(True{}))
    urow("dk_populate_linux", map_populate(False{}))
    urow("dk_populate_osx", map_populate(True{}))
    urow("dk_mem_flags_linux", mem_flags(False{}))
    urow("dk_mem_flags_osx", mem_flags(True{}))
    urow("dk_direct_yes", open_direct(False{}, True{}))
    urow("dk_direct_no", open_direct(False{}, False{}))
    urow("dk_direct_yes_mac", open_direct(True{}, True{}))
    urow("dk_direct_no_mac", open_direct(True{}, False{}))
    urow("dk_open_plain", open_flags(False{}, 0))
    urow("dk_open_odirect", open_flags(False{}, open_direct(False{}, True{})))
    urow("dk_open_plain_mac", open_flags(True{}, 0))
    urow("dk_open_odirect_mac", open_flags(True{}, open_direct(True{}, True{})))
    row("dk_open_has_rdwr", U32.is_eq(U32.and(open_flags(False{}, 0), O_RDWR()),
                                      O_RDWR()))
    row("dk_open_has_creat", U32.is_eq(U32.and(open_flags(False{}, 0), O_CREAT_LINUX()),
                                       O_CREAT_LINUX()))
    row("dk_open_has_creat_mac", U32.is_eq(U32.and(open_flags(True{}, 0), O_CREAT_MACOS()),
                                           O_CREAT_MACOS()))
    row("dk_open_odirect_extra",
        U32.is_gt(open_flags(False{}, open_direct(False{}, True{})),
                  open_flags(False{}, 0)))
    row("dk_open_odirect_mac_same",
        U32.is_eq(open_flags(True{}, open_direct(True{}, True{})), open_flags(True{}, 0)))
    urow("dk_pagesize", pagesize(False{}))
    urow("dk_pagesize_mac", pagesize(True{}))
    urow("dk_shm_mode", SHM_MODE())
    urow("dk_madv_hugepage", madv_hp(False{}))
    urow("dk_madv_hugepage_mac", madv_hp(True{}))
    urow("dk_ioring_nr_setup", NR_IO_URING_SETUP())
    urow("dk_ioring_nr_enter", NR_IO_URING_ENTER())
    urow("dk_ioring_entries", IORING_ENTRIES())
    urow("dk_ioring_off_cq", IORING_OFF_CQ_RING())
    urow("dk_ioring_off_sqes", IORING_OFF_SQES())
    urow("dk_ioring_op_read", IORING_OP_READ())
    urow("dk_ioring_getevents", IORING_ENTER_GETEVENTS())
    urow("dk_ioring_cqe", SIZEOF_CQE())
    urow("dk_ioring_sqe", SIZEOF_SQE())
    urow("dk_alloc_lru", Bool.to_u32(ALLOC_LRU()))

# --- 3: the open, :29-40, in order -------------------------------------------
# THE TWO ORDER ROWS RESET BEFORE THE OPEN AND COMPARE THE WHOLE TRACE. A reset
# device has `next == 0`, so the descriptor both branches mint is 0 -- which is
# why `Call{K_CLOSE(), 0}` below is the seam's ANSWER and not a magic number, and
# why `dk_open_file_fd` (4, on the unreset fixture) is a separate row with a
# separate referent.
def t_open() -> IO(Unit):
  do IO<Unit>:
    +p : Dev <- IO.pure(Dev, fx_open(10000))
    +pt : Tr <- IO.pure(Tr, Dev.tr(p))
    +s : Dev <- IO.pure(Dev, fx_shm_open(10000))
    +st : Tr <- IO.pure(Tr, Dev.tr(s))
    +p0 : Dev <- IO.pure(Dev, dev_might_open(10000, dev_reset(fx_plain())))
    +p0t : Tr <- IO.pure(Tr, Dev.tr(p0))
    +s0 : Dev <- IO.pure(Dev, dev_might_open(10000, dev_reset(fx_shm())))
    +s0t : Tr <- IO.pure(Tr, Dev.tr(s0))
    # THE MATCHER PINS ITSELF FIRST. Seven rows below are order claims and none of
    # them means anything if `Tr.has` answers True to everything.
    row("dk_has_rejects_reverse", Bool.not(seq(pt, [Call{K_MMAP(), 10000},
      Call{K_FTRUNCATE(), 10000}])))
    row("dk_has_rejects_absent", Bool.not(seq(pt, [Call{K_COPYOUT(), 999}])))
    row("dk_open_file_order", seq_eq(p0t,
      [Call{K_OPEN_DIRECT(), 16450}, Call{K_OPEN(), 66}, Call{K_FSTAT(), 0},
       Call{K_FTRUNCATE(), 10000}, Call{K_MMAP(), 10000}, Call{K_MADVISE(), 14}]))
    # :38-39 RUNS ON BOTH BRANCHES -- `self.mem` is set at :30 as well as :36 --
    # so the shm branch is FOUR calls and not three.
    row("dk_open_shm_order", seq_eq(s0t, [Call{K_SHM_OPEN(), 384},
      Call{K_MMAP_SHM(), 40961}, Call{K_CLOSE(), 0}, Call{K_MADVISE(), 14}]))
    # THE WHOLE TRACE IN ONE STRING, tag and argument for every call: the four
    # io_uring calls `dev_init` made, then the five of the file branch, then the
    # madvise. This is the row that says :33 asked for O_DIRECT, :34 retried
    # without it, :35 fstat'd before it truncated, and :39 ran last.
    srow("dk_open_file_trace", trace_str(pt))
    urow("dk_open_file_fstat", ncalls(K_FSTAT(), pt))
    urow("dk_open_file_ftrunc", ncalls(K_FTRUNCATE(), pt))
    # BOTH attempts, and :34's flags: the fallback drops O_DIRECT and the trace keeps
    # the ask. This is the row that says the try/except is not a branch.
    urow("dk_open_direct_attempts", ncalls(K_OPEN_DIRECT(), pt))
    urow("dk_open_fallback_attempts", ncalls(K_OPEN(), pt))
    urow("dk_open_total_attempts", U32.add(ncalls(K_OPEN_DIRECT(), pt),
                                           ncalls(K_OPEN(), pt)))
    row("dk_shm_no_open_attempt", u32_is_zero(ncalls(K_OPEN_DIRECT(), st)))
    srow("dk_open_shm_trace", trace_str(st))
    urow("dk_open_shm_n", seen(st))
    row("dk_shm_fd_none", Bool.not(Dev.has_fd(s)))
    urow("dk_shm_size", Dev.size(s))
    row("dk_shm_has_mem", Dev.has_mem(s))
    row("dk_open_file_has_fd", Dev.has_fd(p))
    # the descriptor the seam would hand back: `Tr.here` is read BEFORE the open's
    # emit, and the four io_uring calls minted none, so it is 0 on both branches.
    # A row so that `dk_open_shm_order`'s `CLOSE, 0` has a referent.
    urow("dk_open_file_fd", Dev.fd(p))
    urow("dk_shm_fd_is_none", Bool.to_u32(Dev.has_fd(s)))
    # the madvise, and the device with no madvise.
    row("dk_madvise_order", seq(pt, [Call{K_MMAP(), 10000},
      Call{K_MADVISE(), 14}]))
    urow("dk_madvise_n", ncalls(K_MADVISE(), pt))
    +n : Dev <- IO.pure(Dev, dev_might_open(10000, fx_nomadv()))
    urow("dk_nomadv_n", ncalls(K_MADVISE(), Dev.tr(n)))
    # a block device and a file already long enough: :35's two other cells.
    +b : Dev <- IO.pure(Dev, dev_might_open(10000, fx_blockdev()))
    +bt : Tr <- IO.pure(Tr, Dev.tr(b))
    +g : Dev <- IO.pure(Dev, dev_might_open(10000, fx_longfile()))
    +gt : Tr <- IO.pure(Tr, Dev.tr(g))
    urow("dk_blockdev_fstat", ncalls(K_FSTAT(), bt))
    urow("dk_blockdev_ftrunc", ncalls(K_FTRUNCATE(), bt))
    urow("dk_longfile_fstat", ncalls(K_FSTAT(), gt))
    urow("dk_longfile_ftrunc", ncalls(K_FTRUNCATE(), gt))
    # the device state after a successful open, and :12's no-op.
    urow("dk_open_refcount", Dev.refcount(p))
    urow("dk_open_size", Dev.size(p))
    row("dk_open_has_size", Dev.has_size(p))
    row("dk_open_has_mem", Dev.has_mem(p))
    row("dk_sync_noop", u32_list_eq(Tr.pairs(Tr.calls(Dev.tr(dev_sync(fx_plain())))),
                                    Tr.pairs(Tr.calls(Dev.tr(fx_plain())))))

# --- 4: the fast path, the assert and the truncation, :22-25 ----------------
# THE CLAIM IN THIS SECTION IS THE TRUNCATION, so the rows are TRACE EQUALITIES and
# not counts: a refusal shows up as the trace being IDENTICAL before and after the
# offending call. A count row would read the same number either way and prove
# nothing -- which is the recorded "an `eq_u(n, 0)` row is satisfied by any
# wrong-but-present answer" trap.
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +w : Dev <- IO.pure(Dev, dev_might_open(10000, fx_open(10000)))
    +wt : Tr <- IO.pure(Tr, Dev.tr(w))
    srow("dk_warm_trace", trace_str(wt))
    urow("dk_warm_refcount", Dev.refcount(w))
    urow("dk_warm_size", Dev.size(w))
    # the assert REFUSES: `refused` latches and NO LATER EMIT RECORDS ANYTHING.
    +g : Dev <- IO.pure(Dev, dev_might_open(20000, w))
    +gt : Tr <- IO.pure(Tr, Dev.tr(g))
    row("dk_grow_refused", Tr.refused(gt))
    row("dk_grow_trace_unchanged", u32_list_eq(Tr.pairs(Tr.calls(gt)), Tr.pairs(Tr.calls(wt))))
    # and the assert is BEFORE the refcount bump, so the count does not move either.
    urow("dk_grow_refcount", Dev.refcount(g))
    urow("dk_grow_size", Dev.size(g))
    row("dk_grow_has_mem_unchanged", Dev.has_mem(g))
    srow("dk_grow_msg", dev_reopen_msg(20000, w))
    srow("dk_fresh_msg", dev_reopen_msg(10000, fx_plain()))
    # SHRINK is legal and is the SAME fast path: same trace, refcount 2, and the
    # recorded `size` STAYS at the first one rather than dropping to 4000.
    +k : Dev <- IO.pure(Dev, dev_might_open(4000, w))
    +kt : Tr <- IO.pure(Tr, Dev.tr(k))
    row("dk_shrink_not_refused", Bool.not(Tr.refused(kt)))
    row("dk_shrink_trace_unchanged", u32_list_eq(Tr.pairs(Tr.calls(kt)), Tr.pairs(Tr.calls(wt))))
    urow("dk_shrink_refcount", Dev.refcount(k))
    urow("dk_shrink_size", Dev.size(k))
    # the predicate itself, on both sides: a fresh device is not open, an opened one
    # is, and a CLOSED one is not even though it still `hasattr(self,"mem")`.
    row("dk_is_open_fresh", dev_is_open(fx_plain()))
    row("dk_is_open_after", dev_is_open(w))

# --- 5: the close, :41-49, and fact A (the refcount is the DEVICE's) --------
# EVERY `seq_eq` HERE RESETS *BEFORE* THE STEP AND READS *AFTER*. The fixture
# carries `dev_init`'s four io_uring calls and `dev_might_open`'s six in front of
# the close, so a whole-trace comparison needs the trace emptied -- and it needs
# emptying WITHOUT the step under test, which is the whole discipline. My first
# version called `dev_reset` on the RESULT, which deletes exactly the calls the
# row is about: `dk_close_exactly_two` was False against an empty trace, and
# `dk_close_shm_only_unmap` was False for the same reason. `dev_reset` is a gate
# mechanism and not a port of anything; `dk_two_free_exactly_two` is the row that
# pins it, because two resets in one row is one too many.
def t_close() -> IO(Unit):
  do IO<Unit>:
    +o : Dev <- IO.pure(Dev, dev_reset(fx_open(10000)))
    +c : Dev <- IO.pure(Dev, alloc_free(o))
    +ct : Tr <- IO.pure(Tr, Dev.tr(c))
    row("dk_close_exactly_two", seq_eq(ct,
      [Call{K_CLOSE(), Dev.fd(c)}, Call{K_MUNMAP(), 10000}]))
    urow("dk_close_n", u32_add(ncalls(K_CLOSE(), ct), ncalls(K_MUNMAP(), ct)))
    urow("dk_close_refcount", Dev.refcount(c))
    row("dk_close_size_none", Bool.not(Dev.has_size(c)))
    # :49 clears ONLY `size`, so `mem` and `fd` SURVIVE the close. This is why :23
    # needs two conjuncts and it is fact B in the header.
    row("dk_close_keeps_mem", Dev.has_mem(c))
    row("dk_close_keeps_fd", Dev.has_fd(c))
    row("dk_warm_needs_both", Bool.not(dev_is_open(c)))
    # the shm device closes by MUNMAP alone, and `Dev.fd(c)` is 0 there because
    # :17 never set it -- so the row is also the evidence that the shm branch's
    # :31 close is a DIFFERENT call from :44's.
    +so : Dev <- IO.pure(Dev, dev_reset(fx_shm_open(10000)))
    +sc : Dev <- IO.pure(Dev, alloc_free(so))
    +sct : Tr <- IO.pure(Tr, Dev.tr(sc))
    urow("dk_close_shm_closes", ncalls(K_CLOSE(), sct))
    urow("dk_close_shm_unmaps", ncalls(K_MUNMAP(), sct))
    row("dk_close_shm_only_unmap", seq_eq(sct, [Call{K_MUNMAP(), 10000}]))
    # FACT A. Two allocs of DIFFERENT sizes on ONE device: the second is legal (it
    # is smaller), the refcount is 2, ONE free does NOTHING, and the SECOND free
    # unmaps the FIRST buffer's size rather than the second's. The unmap argument is
    # the sharpest evidence that `_free` reads nothing from its storage -- 40960 when
    # the buffer freed last was 4096.
    +a1 : Rc <- IO.pure(Rc, alloc_of(40960, fx_plain()))
    +a2 : Rc <- IO.pure(Rc, alloc_of(4096, Rc.d(a1)))
    urow("dk_two_alloc_refcount", Dev.refcount(Rc.d(a2)))
    +f1 : Dev <- IO.pure(Dev, alloc_free(Rc.d(a2)))
    +f1t : Tr <- IO.pure(Tr, Dev.tr(f1))
    row("dk_one_free_trace_unchanged",
        u32_list_eq(Tr.pairs(Tr.calls(f1t)), Tr.pairs(Tr.calls(Dev.tr(Rc.d(a2))))))
    urow("dk_one_free_refcount", Dev.refcount(f1))
    # THE RESET IS HERE AND NOT EARLIER: the first free must be free to record
    # NOTHING, so the trace it leaves has to be the one the second free adds to.
    +f1r : Dev <- IO.pure(Dev, dev_reset(f1))
    +f2 : Dev <- IO.pure(Dev, alloc_free(f1r))
    +f2t : Tr <- IO.pure(Tr, Dev.tr(f2))
    row("dk_two_free_exactly_two", seq_eq(f2t,
      [Call{K_CLOSE(), Dev.fd(f2)}, Call{K_MUNMAP(), 40960}]))
    urow("dk_two_free_unmap_size", arg_of(K_MUNMAP(), f2t))
    urow("dk_last_alloc_size", Db.size(Rc.b(a2)))
    # THE UNDERFLOW. Two frees past the count walk it away from zero and the wrap is
    # a bit pattern, so it is in the ROW NAME. The call count does NOT move for the
    # second and third free: the crossing happens once.
    +u1 : Dev <- IO.pure(Dev, alloc_free(c))
    +u2 : Dev <- IO.pure(Dev, alloc_free(u1))
    +u2t : Tr <- IO.pure(Tr, Dev.tr(u2))
    urow("dk_free_underflow_4294967294", Dev.refcount(u2))
    urow("dk_free_underflow_calls", u32_add(ncalls(K_CLOSE(), u2t),
                                           ncalls(K_MUNMAP(), u2t)))
    row("dk_free_underflow_refused", Tr.refused(u2t))

# --- 6: the buffer, the window and the transfers, :73-99 and :144 -----------
# THE ALLOC FIXTURE IS A COLD DEVICE (`fx_plain()`, not an opened one), so
# `_alloc`'s `_might_open` takes the COLD path and the refcount really is 1. An
# already-open fixture would take the WARM path, add no call, and leave the refcount
# at 2 -- which is why `fx_plain()` and not `fx_open(...)` is the argument here.
def t_buf() -> IO(Unit):
  do IO<Unit>:
    +r : Rc <- IO.pure(Rc, alloc_of(10, fx_plain()))
    +rd : Dev <- IO.pure(Dev, Rc.d(r))
    srow("dk_repr", db_repr(Rc.b(r)))
    srow("dk_repr_zero", db_repr(alloc_offset(10, 0, Rc.b(r))))
    urow("dk_alloc_addr", Rc.addr(r))
    urow("dk_alloc_size", Db.size(Rc.b(r)))
    urow("dk_alloc_offset", Db.offset(Rc.b(r)))
    urow("dk_win_lo", Win.lo(db_window(Rc.b(r))))
    urow("dk_win_hi", Win.hi(db_window(Rc.b(r))))
    urow("dk_alloc_refcount", Dev.refcount(rd))
    # `_copyin`'s slice is `[:]`, so the bytes land at ZERO of the window, not at
    # `offset`. `dk_copyin_at_zero` is the row and it is the only thing that says so,
    # and it is a WHOLE-trace comparison -- so the device is reset BEFORE the copyin
    # and the copyin's own call is the entire trace.
    +v : Db <- IO.pure(Db, alloc_offset(10, 4, Rc.b(r)))
    +cir : Dev <- IO.pure(Dev, dev_reset(rd))
    +ci : Dev <- IO.pure(Dev, alloc_copyin(v, cir))
    +cit : Tr <- IO.pure(Tr, Dev.tr(ci))
    row("dk_copyin_at_zero", seq_eq(cit, [Call{K_COPYIN(), 10}]))
    # `_copyout`'s non-OSX arm, on the same offset-4 buffer: the WINDOW's size, again
    # not the offset. A different tag from COPYIN on the same fixture, which is what
    # separates the two rows.
    +cor : Roff <- IO.pure(Roff, alloc_copyout(Nil{}, v, dev_reset(ci)))
    +cot : Tr <- IO.pure(Tr, Dev.tr(Roff.dev(cor)))
    row("dk_copyout_at_zero", seq_eq(cot, [Call{K_COPYOUT(), 10}]))
    # its OSX arm: open, seek to the buffer's offset, one readinto per chunk, and a
    # `with` exit that does NOT close. The whole trace, so the fd and the exit are in
    # the same string as the seeks.
    +oo : Dev <- IO.pure(Dev, dev_reset(dev_might_open(10000, fx_osx())))
    +ro : Roff <- IO.pure(Roff, alloc_copyout([10, 12, 5], v, oo))
    +rot : Tr <- IO.pure(Tr, Dev.tr(Roff.dev(ro)))
    # `shm` AND `OSX`, which `fx_osx` above is not and `fx_shm_open` below is not.
    # THE RESET IS BEFORE THE COPYOUT, so the whole-trace comparison sees the
    # copyout's own call and nothing else -- `dev_reset` applied to the RESULT would
    # delete the call under test, which is the mistake `dk_close_exactly_two` records.
    +sdo : Dev <- IO.pure(Dev, dev_reset(fx_shm_osx_open(10000)))
    +sro : Roff <- IO.pure(Roff, alloc_copyout([10], Db.of(sdo, 10, 0), sdo))
    +sdot : Tr <- IO.pure(Tr, Dev.tr(Roff.dev(sro)))
    row("dk_copyout_osx_order", seq_eq(rot, [Call{K_FILEIO(), Dev.fd(Roff.dev(ro))},
      Call{K_SEEK(), 4}, Call{K_READINTO(), 0}, Call{K_READINTO(), 10},
      Call{K_READINTO(), 22}, Call{K_FILEIO_CLOSE(), 0}]))
    srow("dk_copyout_osx_trace", trace_str(rot))
    # `bytes_read` is each read's DESTINATION, and these are the running sums.
    srow("dk_copyout_osx_offs", ujoin(Roff.offs(ro)))
    urow("dk_copyout_osx_reads", ncalls(K_READINTO(), rot))
    # :89 -- `_as_buffer(self, src): return src._buf()`. It records NOTHING, because
    # `_buf` takes a slice and not a syscall, and it answers the SAME window. Two rows:
    # the window, and the absence of a call. Without the second, a port that routed
    # `_as_buffer` through `_copyin` would print the right window and nothing else
    # would say so.
    +ab : DbB <- IO.pure(DbB, alloc_as_buffer(v, ci))
    urow("dk_as_buffer_lo", Win.lo(DbB.win(ab)))
    urow("dk_as_buffer_size", Win.size(DbB.win(ab)))
    row("dk_as_buffer_no_call",
        u32_list_eq(Tr.pairs(Tr.calls(Dev.tr(DbB.dev(ab)))),
                    Tr.pairs(Tr.calls(cit))))
    # THE shm arm of :92, and it is the only row in the file that sees it: a
    # `disk:shm:` device has `self.fd` None, so OSX does NOT move it to FileIO.
    #
    # TWO FIXTURES, NOT ONE, and the second is the one with teeth. On a LINUX shm
    # device `Dev.osx` is False, so :92's FIRST conjunct already picks the posix arm
    # and the SECOND conjunct is never read -- the row pair below cannot see a port
    # that drops it. `fx_shm_osx_open` is `shm` AND `OSX`, which is the only
    # combination where `self.dev.fd is not None` is the deciding question, and
    # `dk_copyout_shm_osx_fileio` is the row that dies when the conjunct goes.
    +sd : Dev <- IO.pure(Dev, fx_shm_open(10000))
    +sr : Roff <- IO.pure(Roff, alloc_copyout([10], Db.of(sd, 10, 0), sd))
    +srt : Tr <- IO.pure(Tr, Dev.tr(Roff.dev(sr)))
    urow("dk_copyout_shm_fileio", ncalls(K_FILEIO(), srt))
    urow("dk_copyout_shm_copyout", ncalls(K_COPYOUT(), srt))
    row("dk_copyout_shm_osx_has_no_fd", Bool.not(Dev.has_fd(sdo)))
    row("dk_copyout_shm_osx_is_osx", Dev.osx(sdo))
    row("dk_copyout_shm_osx_posix", seq_eq(sdot, [Call{K_COPYOUT(), 10}]))
    urow("dk_copyout_shm_osx_fileio", ncalls(K_FILEIO(), sdot))
    # and the mirror: a macOS FILE device has an fd, so the FileIO arm IS taken.
    row("dk_copyout_osx_file_has_fd", Dev.has_fd(oo))
    # `_offset` does NOT accumulate: a buffer already at 4 moves to 8, and the row
    # beside it names the number an accumulating `view` WOULD have given. The third
    # row says the device is the SAME one, which is the other half of :144.
    +w : Db <- IO.pure(Db, alloc_offset(20, 8, Rc.b(r)))
    urow("dk_offset_size", Db.size(w))
    urow("dk_offset_off", Db.offset(w))
    urow("dk_offset_accumulated_would_be", U32.add(Db.offset(Rc.b(r)), 8))
    row("dk_offset_same_device", String.eq(Dev.name(Db.d(w)), Dev.name(rd)))
    srow("dk_not_open_msg", db_not_open_msg(Db.of(fx_plain(), 10, 0)))
    # a buffer over a device with no mapping REFUSES, and that is the second assert
    # in the file. :78's message is gated above and the REFUSAL here.
    +u : Db <- IO.pure(Db, Db.of(fx_plain(), 10, 0))
    +ud : Dev <- IO.pure(Dev, DbB.dev(db_buf(u, fx_plain())))
    row("dk_buf_refused", Tr.refused(Dev.tr(ud)))
    urow("dk_buf_refused_calls", seen(Dev.tr(ud)))

# --- 7: the shard, :101-116. THE RESULT ROWS. -------------------------------
# THE EXPECTED VALUES, derived by hand from :103-115 so the gate can be read
# without running it. The CPython oracle re-derives every one of them.
#
#   A: offset 0, size 10000, seg 4096, mapping 40960
#      minor 0, fd_offset 0, total = round_up(10000, 4096) = 12288, n = 3
#      off 0    read min(4096, 12288, 40960)  = 4096  real min(4096, 10000) = 4096  cin 0
#      off 4096 read min(4096, 8192, 36864)   = 4096  real min(4096, 5904)  = 4096  cin 4096
#      off 8192 read min(4096, 4096, 32768)   = 4096  real min(4096, 1808)  = 1808  cin 8192
#
#   B: offset 100, size 5000, seg 2048, mapping 65536
#      minor 100, fd_offset 0, total = round_up(5100, 4096) = 8192, n = 4
#      off 0    read 2048  real min(2048-100, 5000) = 1948  cin 0     moff 100
#      off 2048 read 2048  real min(2048, 3052)      = 2048  cin 1948  moff 0
#      off 4096 read 2048  real min(2048, 1004)      = 1004  cin 3996  moff 0
#      off 6144 read 2048  real min(2048, 0)         = 0     cin 5000  moff 0
#
#   C: offset 5000, size 5000, seg 2048, mapping 65536 -- the offset is PAST A PAGE
#      BOUNDARY, so `fd_offset` is 4096 and not 0.
#      minor 904, fd_offset 4096, total = round_up(5904, 4096) = 8192, n = 4
#      off 0    read min(2048, 8192, 61440) = 2048  real min(2048-904, 5000) = 1144  cin 0
#      off 2048 read min(2048, 6144, 59392) = 2048  real min(2048, 3856)      = 2048  cin 1144
#      off 4096 read min(2048, 4096, 57344) = 2048  real min(2048, 1808)      = 1808  cin 3192
#      off 6144 read min(2048, 2048, 55296) = 2048  real min(2048, 0)         = 0     cin 5000
#
#   D: offset 100, size 5000, seg 2048, mapping 4096 -- THE MAPPING IS SHORTER THAN
#      THE SHARD, so at `off = 6144` the third term of `read_size` is
#      `4096 - 4096 - 6144 = -2048`, which is `4294965248` in a `U32`. The `min3`
#      then picks `seg_len` and the port answers 2048 -- a PLAUSIBLE WRONG ANSWER
#      rather than a crash, which is exactly what `shard_read`'s header says.
#      off 0    read 2048  real 1948  cin 0     moff 100   (third term 4096)
#      off 2048 read 2048  real 2048  cin 1948  moff 0     (third term 2048)
#      off 4096 read 0     real 0     cin 3996  moff 0     (third term 0)
#      off 6144 read 2048  real 1004  cin 3996  moff 0     (third term 4294965248)
#      and the cover is STILL 5000: the wrap moves one segment's destination and the
#      sum survives, so `dk_shard_cover_d` is `True` for a wrong answer. `dk_shard_d`
#      is the row that sees it.
#
# NOTE THE FOURTH SEGMENT OF B AND C: `read` is 2048 and `real` is 0. The
# page-aligned READ is full and the COPY is empty, and that is the whole reason the
# two columns exist. A port that DROPPED the zero segment still covers `size` and
# still satisfies contiguity, so neither `dk_shard_cover_b` nor `dk_shard_contig_b`
# would notice -- only `dk_shard_b` would, and that is what it is for.
def t_shard() -> IO(Unit):
  do IO<Unit>:
    urow("dk_shard_total_a", Sh.total(SH_A(False{})))
    urow("dk_shard_fd_a", Sh.fd_off(SH_A(False{})))
    urow("dk_shard_minor_a", shard_minor(0, False{}))
    urow("dk_shard_n_formula_a", shard_n(Sh.total(SH_A(False{})), Sh.seg(SH_A(False{}))))
    +a : ShOut <- IO.pure(ShOut, dk_run_a(fx_plain(), False{}))
    srow("dk_shard_a", shard_str(ShOut.segs(a)))
    urow("dk_shard_cover_a", shard_cover(ShOut.segs(a)))
    row("dk_shard_contig_a", shard_contig(ShOut.segs(a)))
    urow("dk_shard_copyouts_a", ncalls(K_COPYOUT(), Dev.tr(ShOut.d(a))))
    # the FORMULA's count and the FOLD's length are two independent transcriptions
    # and a mutation to either one moves exactly one of them.
    urow("dk_shard_seg_len_a", U32.from_nat(List.length(&2, Seg, ShOut.segs(a))))
    # THE PAGE SIZE IS NOT CONSTANT. `dk_shard_total_a` is `round_up(10000, 4096)`
    # on the linux cell and `round_up(10000, 16384)` on the macOS one, so a port that
    # hardcoded `PAGESIZE` would print 12288 here and 16384 there and agree with
    # itself. These three rows are the pair that makes `pagesize` falsifiable: the
    # TOTAL differs, the SEGMENT COUNT differs, and the LAST segment's `cin` is
    # 8192 on one cell and 12288 on the other.
    urow("dk_shard_total_a_mac", Sh.total(SH_A(True{})))
    urow("dk_shard_n_formula_a_mac", shard_n(Sh.total(SH_A(True{})), Sh.seg(SH_A(True{}))))
    +am : ShOut <- IO.pure(ShOut, dk_run_a(fx_plain(), True{}))
    srow("dk_shard_a_mac", shard_str(ShOut.segs(am)))
    row("dk_shard_a_differs_by_platform", Bool.not(String.eq(shard_str(ShOut.segs(a)),
                                                           shard_str(ShOut.segs(am)))))
    # B, the SKEWED fixture, and the one the whole function is for.
    urow("dk_shard_total_b", Sh.total(SH_B(False{})))
    urow("dk_shard_fd_b", Sh.fd_off(SH_B(False{})))
    urow("dk_shard_minor_b", shard_minor(100, False{}))
    urow("dk_shard_n_formula_b", shard_n(Sh.total(SH_B(False{})), Sh.seg(SH_B(False{}))))
    +b : ShOut <- IO.pure(ShOut, dk_run_b(fx_plain(), False{}))
    srow("dk_shard_b", shard_str(ShOut.segs(b)))
    urow("dk_shard_cover_b", shard_cover(ShOut.segs(b)))
    row("dk_shard_contig_b", shard_contig(ShOut.segs(b)))
    urow("dk_shard_copyouts_b", ncalls(K_COPYOUT(), Dev.tr(ShOut.d(b))))
    urow("dk_shard_seg_len_b", U32.from_nat(List.length(&2, Seg, ShOut.segs(b))))
    # C, PAST A PAGE BOUNDARY, so `fd_offset` is NOT 0 and the `fd_offset` column
    # stops being constant over the suite.
    urow("dk_shard_fd_c", Sh.fd_off(SH_C(False{})))
    urow("dk_shard_minor_c", shard_minor(5000, False{}))
    +c : ShOut <- IO.pure(ShOut, dk_run_c(fx_plain(), False{}))
    srow("dk_shard_c", shard_str(ShOut.segs(c)))
    urow("dk_shard_cover_c", shard_cover(ShOut.segs(c)))
    row("dk_shard_contig_c", shard_contig(ShOut.segs(c)))
    # D, THE SHORT MAPPING, and the only fixture that exercises the `U32` wrap. The
    # two rows below it are the pair that makes the hazard a measurement: the RAW
    # third term is the bit pattern, and `shard_read` answers `seg_len` anyway.
    urow("dk_shard_raw_third_d", shard_raw_third(6144, SH_D(False{})))
    # THE ONE PLACE THE `U32` AND CPython DISAGREE, and THE GATE CANNOT PRINT
    # CPython's SIDE: `U32` has no signed type, which IS the divergence. What it can
    # print is the wrapped term (4294965248, i.e. -2048 as a bit pattern), the `min`
    # that term defeats (2048, where Python says -2048) and the cover that follows
    # (10000, where Python says 1948). `ops_disk.py` cannot reach the state -- it
    # relies on `fd_offset + total_copy_size <= src.device.size`, which fixture D
    # violates on purpose -- and a saturating subtraction would invent a rule Python
    # does not have. The oracle carries the pair as THREE ASSERTIONS, so if `U32`
    # ever stops wrapping the oracle FAILS instead of quietly agreeing with the port.
    urow("dk_shard_read4_d", shard_read(6144, SH_D(False{})))
    urow("dk_shard_read3_d", shard_read(4096, SH_D(False{})))
    +d : ShOut <- IO.pure(ShOut, dk_run_d(fx_plain(), False{}))
    srow("dk_shard_d", shard_str(ShOut.segs(d)))
    urow("dk_shard_cover_d", shard_cover(ShOut.segs(d)))
    row("dk_shard_contig_d", shard_contig(ShOut.segs(d)))
    # E, THE SKEW CROSSING A PAGE BOUNDARY -- the fixture that makes :104's
    # `size + minor_offset` separable from `size`. `minor` is 1500 and `size` is
    # 3000, so the sum is 4500 and rounds up to 8192 while `size` alone rounds up
    # to 4096, and the segment count is 4 rather than 1. `dk_shard_seg_len_e` is the
    # row a dropped-skew port gets wrong, and `dk_shard_total_e` is the row it gets
    # wrong FIRST.
    urow("dk_shard_total_e", Sh.total(SH_E(False{})))
    urow("dk_shard_minor_e", shard_minor(1500, False{}))
    urow("dk_shard_fd_e", Sh.fd_off(SH_E(False{})))
    +e : ShOut <- IO.pure(ShOut, dk_run_e(fx_plain(), False{}))
    srow("dk_shard_e", shard_str(ShOut.segs(e)))
    urow("dk_shard_cover_e", shard_cover(ShOut.segs(e)))
    row("dk_shard_contig_e", shard_contig(ShOut.segs(e)))
    urow("dk_shard_seg_len_e", U32.from_nat(List.length(&2, Seg, ShOut.segs(e))))
    # a segment LONGER than the whole shard: one segment, and `real` is the request.
    +big : ShOut <- IO.pure(ShOut, shard_at(20000, 10000, 0, 40960, False{}, fx_plain()))
    srow("dk_shard_big", shard_str(ShOut.segs(big)))
    urow("dk_shard_big_cover", shard_cover(ShOut.segs(big)))
    row("dk_shard_big_contig", shard_contig(ShOut.segs(big)))
    # `seg_len == 0` is an empty `range` in Python and 0 here, because `U32.div(x,0)
    # = 0`. That is the second place this file leans on the documented div.
    urow("dk_shard_seg0_n", shard_n(Sh.total(SH_A(False{})), 0))
    +zero : ShOut <- IO.pure(ShOut, shard_at(0, 10000, 0, 40960, False{}, fx_plain()))
    urow("dk_shard_seg0_segs", U32.from_nat(List.length(&2, Seg, ShOut.segs(zero))))
    # :106 -- `not hasattr(DiskDevice,'io_uring') or not use_ioring`. Either way the
    # non-uring arm is taken, and both give the SAME segments.
    +i0 : ShOut <- IO.pure(ShOut, shard.pick(False{}, True{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_ioring_absent", String.eq(shard_str(ShOut.segs(i0)),
                                            shard_str(ShOut.segs(a))))
    +i1 : ShOut <- IO.pure(ShOut, shard.pick(True{}, False{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_no_use_ioring", String.eq(shard_str(ShOut.segs(i1)),
                                            shard_str(ShOut.segs(a))))
    # and the io_uring arm's two submission calls, which are all it adds here.
    +i2 : ShOut <- IO.pure(ShOut, shard.pick(True{}, True{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_ioring_order", seq(Dev.tr(ShOut.d(i2)),
      [Call{K_SQE_STORE(), 0}, Call{K_IORING_ENTER(), 1}]))
    urow("dk_shard_ioring_sqes", ncalls(K_SQE_STORE(), Dev.tr(ShOut.d(i2))))
    urow("dk_shard_ioring_enters", ncalls(K_IORING_ENTER(), Dev.tr(ShOut.d(i2))))
    urow("dk_shard_ioring_copyouts", ncalls(K_COPYOUT(), Dev.tr(ShOut.d(i2))))

# --- 8: io_uring setup, :50-71 ----------------------------------------------
def t_ioring() -> IO(Unit):
  do IO<Unit>:
    +p : Dev <- IO.pure(Dev, fx_plain())
    +pt : Tr <- IO.pure(Tr, Dev.tr(p))
    row("dk_ioring_tried", Dev.tried(p))
    row("dk_ioring_stored", Dev.ioring(p))
    row("dk_ioring_order", seq(pt, [Call{K_IOURING_SETUP(), 4096},
      Call{K_MMAP(), 0}, Call{K_MMAP(), 134217728}, Call{K_MMAP(), 268435456}]))
    urow("dk_ioring_n", seen(pt))
    urow("dk_ioring_mmaps", ncalls(K_MMAP(), pt))
    urow("dk_ioring_setup_n", ncalls(K_IOURING_SETUP(), pt))
    # a non-linux host: :15's guard is satisfied and NOTHING is set up, but
    # `_tried_io_uring_init` is STILL True because :51 runs before the test.
    +n : Dev <- IO.pure(Dev, fx_noioring())
    urow("dk_ioring_skipped_calls", seen(Dev.tr(n)))
    row("dk_ioring_skipped_tried", Dev.tried(n))
    row("dk_ioring_skipped_stored", Bool.not(Dev.ioring(n)))
    # the `if fd < 0: return` at :55 -- one call, no mmaps, no store.
    +f : Dev <- IO.pure(Dev, fx_ioring_fail())
    +ft : Tr <- IO.pure(Tr, Dev.tr(f))
    urow("dk_ioring_failed_n", seen(ft))
    urow("dk_ioring_failed_mmaps", ncalls(K_MMAP(), ft))
    row("dk_ioring_failed_stored", Bool.not(Dev.ioring(f)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_path()
    b : Unit <- t_flags()
    c : Unit <- t_open()
    d : Unit <- t_refuse()
    e : Unit <- t_close()
    f : Unit <- t_buf()
    g : Unit <- t_shard()
    h : Unit <- t_ioring()
    IO.print("dk-done=1")

# ===========================================================================
# THE MUTATION TABLE. **MEASURED, NOT PREDICTED** -- every number below is
# `python3 .agents/slop/dk-mutate.py` output, and re-running it reproduces this file.
#
#     python3 .agents/slop/dk-mutate.py          # run all 56, print the measured table
#     python3 .agents/slop/dk-mutate.py --list   # the table, unrun
#     python3 .agents/slop/dk-mutate.py M7 M31   # a subset
#
# The harness applies each edit IN PLACE, runs the interpreted lane, and diffs the
# baseline. `CHANGED` is the number of rows whose NAME is present in both runs and
# whose VALUE differs; the last column lists them. **`MOVED` -- a row name appearing
# or disappearing -- is 0 for all 56**, which is itself the claim worth making: no
# mutation changed the SHAPE of the suite, only its answers, so no row can be
# quietly deleted by any of them. A row that is deleted is not a row that failed.
#
# **THE TWO CONTROLS MOVE NOTHING AND NOTHING ELSE DOES.** M0 and D0 are
# comment-only edits; both are `0/0`. Every other one of the 54 is `>= 1`. That is
# the property the recorded lesson asks for -- a table with no row that CANNOT move
# is a table of coincidences -- and the harness ENFORCES it: it reports any mutation
# with `0/0` as a BLIND SPOT rather than as a pass.
#
# TWO MUTATIONS WERE BLIND SPOTS ON FIRST MEASUREMENT, and both were fixed with a
# FIXTURE rather than explained away. They are the two most informative results here,
# because both were "the gate does not see this" and neither was "this rule does not
# matter":
#
#   - **M31, `:92`'s second conjunct, moved nothing (0/0).** The gate had ONE shm
#     fixture and it was a LINUX device, so `Dev.osx` was False and :92's FIRST
#     conjunct already picked the arm. The mutation was invisible because the
#     fixture could not REACH the conjunct -- not because the conjunct is
#     redundant. `fx_shm_osx` is the `shm` AND `OSX` combination, which is the only
#     one where `self.dev.fd is not None` is the deciding question, and
#     `dk_copyout_shm_osx_posix` / `dk_copyout_shm_osx_fileio` are the rows it took
#     to kill the mutation. It now moves 2.
#   - **M34, `:104`'s `+ minor_offset`, moved nothing (0/0).** For three of the four
#     shard fixtures `size + minor` rounds up to the same page count `size` alone
#     does: 5000+100 and 5000+904 both give 8192, and so does 5000 alone. The skew
#     was invisible. Fixture E exists for exactly this, and its TWO numbers are
#     constrained rather than found: `minor = 1500 < seg_len = 2048`, so E is not a
#     second copy of D (whose third term goes negative), and
#     `size + minor = 4500 > PAGESIZE`, so the two roundings differ. It now moves 4.
#
# THE FOUR MUTATIONS THAT PRODUCE A RESULT ROW FAILING, which is the whole reason
# this file has result rows and not only trace rows: M37 and M38 break the shard
# `cin` columns, M39 breaks contiguity, and M16 breaks `dk_shard_a_differs_by_platform`
# and the macOS total. Every one of those is a statement about the DATA rather than
# about the spelling of a call.
#
# | # | what it is testing | CHANGED | rows |
# | --- | --- | --- | --- |
# | D0 | CONTROL: a comment-only edit, which must move nothing | 0/0 |  |
# | D1 | :5's base_url, the `fashion=False` cell -- HTTPS | 0/5 | `dst_url_mnist`, `dst_url_t10k_images`, `dst_url_t10k_labels`, `dst_url_train_images`, `dst_url_train_labels` |
# | D2 | :5's base_url, the `fashion=True` cell -- HTTP | 0/2 | `dst_url_fashion`, `dst_url_fashion_t10k_labels` |
# | D3 | :7's `[0x10:]` -- the IDX3 header is 16 bytes | 0/5 | `dst_skip_idx3`, `dst_t10k_images_divides`, `dst_t10k_images_payload`, `dst_train_images_divides`, `dst_train_images_payload` |
# | D4 | :7's `[8:]` -- the IDX1 header is 8 bytes | 0/5 | `dst_images_skip8_divides`, `dst_images_skip8_payload`, `dst_mnist`, `dst_skip_idx1`, `dst_train_labels_rows` |
# | D5 | :7's `reshape(-1,1,28,28)` -- the channel dimension is EXPLICIT | 0/1 | `dst_img_shape` |
# | D6 | :14's `reshape(-1,3,32,32)` | 0/5 | `dst_cifar_image_bytes`, `dst_cifar_image_named`, `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_cifar_split` |
# | D7 | :12's `reshape(-1, 3073)` -- ONE LABEL BYTE plus 3072 image bytes | 0/4 | `dst_cifar_row`, `dst_cifar_split`, `dst_cifar_split_off0`, `dst_cifar_train_bytes` |
# | D8 | :14's `train[:, 0]` -- the LABEL is the FIRST column | 0/2 | `dst_cifar_label_off`, `dst_cifar_split` |
# | D9 | :12's f-string suffix | 0/2 | `dst_cifar_batch1`, `dst_cifar_batch5` |
# | D10 | each CIFAR-10 batch is 10000 rows -- the published size, not in datasets.py | 0/2 | `dst_cifar_train_bytes`, `dst_cifar_train_rows` |
# | D11 | train-images is the 60000-row file, t10k-images is the 10000-row one | 0/3 | `dst_mnist`, `dst_train_images_payload`, `dst_train_images_rows` |
# | D12 | the shape prints as PYTHON would: `-1,1,28,28`, comma inside the `-1` arm | 0/3 | `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_img_shape` |
# | M0 | CONTROL: a comment-only edit, which must move nothing | 0/0 |  |
# | M1 | :26 strips len("disk:") | 0/22 | `dk_close_shm_closes`, `dk_close_shm_only_unmap`, `dk_copyout_shm_osx_fileio`, `dk_copyout_shm_osx_has_no_fd`, `dk_copyout_shm_osx_posix`, `dk_file_dev`, ... (+16) |
# | M2 | :26's slice -- the prefix is stripped, not the string dropped | 0/23 | `dk_close_shm_closes`, `dk_close_shm_only_unmap`, `dk_copyout_shm_osx_fileio`, `dk_copyout_shm_osx_has_no_fd`, `dk_copyout_shm_osx_posix`, `dk_file_bare`, ... (+17) |
# | M3 | :29 strips len("shm:") | 0/6 | `dk_shm_abs_eq_plain`, `dk_shm_allslash_eq_empty`, `dk_shm_empty`, `dk_shm_plain`, `dk_shm_slashes_eq_plain`, `dk_shm_trailing_kept` |
# | M4 | :29's leading slash is UNCONDITIONAL | 0/6 | `dk_shm_abs_eq_plain`, `dk_shm_allslash_eq_empty`, `dk_shm_empty`, `dk_shm_plain`, `dk_shm_slashes_eq_plain`, `dk_shm_trailing_kept` |
# | M5 | `:29`'s `lstrip("/")` -- a slash is dropped only BEFORE anything is kept | 0/1 | `dk_shm_trailing_kept` |
# | M6 | :28's `sys.platform != "win32"` conjunct | 0/1 | `dk_is_shm_win` |
# | M7 | :28 tests the SLICED filename, not the device string | 0/12 | `dk_close_shm_closes`, `dk_close_shm_only_unmap`, `dk_copyout_shm_osx_fileio`, `dk_copyout_shm_osx_has_no_fd`, `dk_copyout_shm_osx_posix`, `dk_is_shm_shm`, ... (+6) |
# | M8 | O_CREAT's TWO CELLS | 0/6 | `dk_open_file_order`, `dk_open_file_trace`, `dk_open_has_creat`, `dk_open_odirect`, `dk_open_plain`, `dk_warm_trace` |
# | M9 | `getattr(os,"O_DIRECT",0)` -- macOS has NO such attribute | 0/3 | `dk_direct_yes_mac`, `dk_open_odirect_mac`, `dk_open_odirect_mac_same` |
# | M10 | :33 asks for O_DIRECT -- the `getattr` presence is a SECOND variable | 0/1 | `dk_direct_no` |
# | M11 | :34's RETRY drops O_DIRECT and :33's ASK does not -- and BOTH are recorded | 0/5 | `dk_open_file_order`, `dk_open_file_trace`, `dk_open_odirect`, `dk_open_odirect_extra`, `dk_warm_trace` |
# | M12 | :81's `0x2000` cell | 0/2 | `dk_locked_linux`, `dk_locked_osx` |
# | M13 | :81's `getattr(mmap,"MAP_POPULATE", 0x008000)` cell | 0/2 | `dk_populate_linux`, `dk_populate_osx` |
# | M14 | :30 ORs THREE flags | 0/3 | `dk_mem_flags_linux`, `dk_open_shm_order`, `dk_open_shm_trace` |
# | M15 | :39's `getattr` -- macOS has NO MADV_HUGEPAGE, so the value there is 0 | 0/1 | `dk_madv_hugepage_mac` |
# | M16 | :103's `mmap.PAGESIZE` -- 4096 on linux, 16384 on macOS/arm64 | 0/5 | `dk_pagesize_mac`, `dk_shard_a_differs_by_platform`, `dk_shard_a_mac`, `dk_shard_n_formula_a_mac`, `dk_shard_total_a_mac` |
# | M17 | :33 and :34 RECORD BOTH ATTEMPTS -- the try/except is not a branch | 0/3 | `dk_open_file_order`, `dk_open_file_trace`, `dk_warm_trace` |
# | M18 | :33's answer is `self.fd`, and it is 4 on the unreset fixture | 0/12 | `dk_close_exactly_two`, `dk_close_keeps_fd`, `dk_close_n`, `dk_copyout_osx_file_has_fd`, `dk_copyout_osx_offs`, `dk_copyout_osx_order`, ... (+6) |
# | M19 | :35's `fstat` runs BEFORE the `ftruncate` it decides | 0/3 | `dk_open_file_order`, `dk_open_file_trace`, `dk_warm_trace` |
# | M20 | :35's `and` SHORT-CIRCUITS -- a block device never stats the file | 0/2 | `dk_blockdev_fstat`, `dk_blockdev_ftrunc` |
# | M21 | :35's `st_size < size` -- the direction | 0/5 | `dk_longfile_ftrunc`, `dk_open_file_ftrunc`, `dk_open_file_order`, `dk_open_file_trace`, `dk_warm_trace` |
# | M22 | :36 maps with NO flags -- the trace argument is the SIZE, and 0 is the answer a port that recorded flags would give | 0/4 | `dk_madvise_order`, `dk_open_file_order`, `dk_open_file_trace`, `dk_warm_trace` |
# | M23 | :37's ASSIGNMENT -- the binder shadowing the parameter makes it a no-op | 0/16 | `dk_close_exactly_two`, `dk_close_shm_only_unmap`, `dk_grow_msg`, `dk_grow_refcount`, `dk_grow_size`, `dk_one_free_refcount`, ... (+10) |
# | M24 | :38's `hasattr(self.mem,'madvise') and ... is not None` | 0/9 | `dk_madvise_n`, `dk_madvise_order`, `dk_nomadv_n`, `dk_open_file_order`, `dk_open_file_trace`, `dk_open_shm_n`, ... (+3) |
# | M25 | :42 decrements BEFORE :43 tests -- THE ORDER IS THE FUNCTION | 0/12 | `dk_close_exactly_two`, `dk_close_n`, `dk_close_refcount`, `dk_close_shm_only_unmap`, `dk_close_shm_unmaps`, `dk_close_size_none`, ... (+6) |
# | M26 | :44's `if self.fd is not None` -- the shm branch has no fd | 0/6 | `dk_close_exactly_two`, `dk_close_n`, `dk_close_shm_closes`, `dk_close_shm_only_unmap`, `dk_free_underflow_calls`, `dk_two_free_exactly_two` |
# | M27 | :47's `self.mem.close()` and the SIZE it unmaps is `self.size` | 0/4 | `dk_close_exactly_two`, `dk_close_shm_only_unmap`, `dk_two_free_exactly_two`, `dk_two_free_unmap_size` |
# | M28 | :49 clears ONLY `size` -- `mem` and `fd` SURVIVE the close | 0/3 | `dk_close_exactly_two`, `dk_close_keeps_fd`, `dk_two_free_exactly_two` |
# | M29 | :79's `memoryview(mem)[offset:offset+size]` -- the WINDOW carries the offset | 0/1 | `dk_as_buffer_lo` |
# | M30 | :95's `fo.seek(src.offset)` -- the SEEK lands at the buffer's offset | 0/2 | `dk_copyout_osx_order`, `dk_copyout_osx_trace` |
# | M31 | :92's SECOND conjunct -- a `disk:shm:` device has `fd is None` | 0/2 | `dk_copyout_shm_osx_fileio`, `dk_copyout_shm_osx_posix` |
# | M32 | :97's `bytes_read` is each read's DESTINATION -- the running sum, not the chunk | 0/1 | `dk_copyout_osx_offs` |
# | M33 | :103's `fd_offset = src.offset - minor_offset` -- THE PAGE ALIGNMENT | 0/6 | `dk_shard_d`, `dk_shard_fd_b`, `dk_shard_fd_c`, `dk_shard_fd_e`, `dk_shard_raw_third_d`, `dk_shard_read3_d` |
# | M34 | :104 ADDS the skew to the size before rounding up | 0/4 | `dk_shard_cover_e`, `dk_shard_e`, `dk_shard_seg_len_e`, `dk_shard_total_e` |
# | M35 | :108's `range(0, total, seg)` is a CEIL, not a floor | 0/2 | `dk_shard_big`, `dk_shard_big_cover` |
# | M36 | :110's SECOND term -- `total_copy_size - off` | 0/1 | `dk_shard_big` |
# | M37 | :113 subtracts the SKEW -- and only the FIRST segment carries one | 0/4 | `dk_shard_b`, `dk_shard_c`, `dk_shard_d`, `dk_shard_e` |
# | M38 | :115's `copied_in += real_copy_size` -- NOT the bytes read | 0/13 | `dk_shard_a_mac`, `dk_shard_b`, `dk_shard_c`, `dk_shard_contig_b`, `dk_shard_contig_c`, `dk_shard_contig_d`, ... (+7) |
# | M39 | CONTIGUITY is a RESULT about the data: consecutive `cin`s tile the request | 0/5 | `dk_shard_contig_a`, `dk_shard_contig_b`, `dk_shard_contig_c`, `dk_shard_contig_d`, `dk_shard_contig_e` |
# | M40 | :57-:60's ORDER -- a nested `emit` appends the INNER call first | 0/4 | `dk_ioring_order`, `dk_open_file_trace`, `dk_open_shm_trace`, `dk_warm_trace` |
# | M41 | :57 offset 0 comes BEFORE :58 `IORING_OFF_CQ_RING` | 0/4 | `dk_ioring_order`, `dk_open_file_trace`, `dk_open_shm_trace`, `dk_warm_trace` |
# | M42 | :128 stores the sqe and :130 enters -- the nesting must put the STORE first | 0/1 | `dk_shard_ioring_order` |
