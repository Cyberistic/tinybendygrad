# tinybendygrad/runtime/ops_disk.bend -- port of tinygrad/runtime/ops_disk.py
#
# ===========================================================================
# WHY this file is not the small one it looks like.
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
# THE place a result can be checked rather than a trace, and it is
# `_copyout_sharded` -- GONE at this pin: upstream 4e4f6b9fb ("hcq2 fast disk") REPLACED
# it with the uring `disk_read`. The surviving construct is `DiskAllocator._copyout`
# (`tinygrad/runtime/ops_disk.py:69-77 symbol=_copyout` `_copyout`). Every segment the GONE
# was `(copy_batch, copied_in, minor_offset, real_copy_size)` and `copied_in` is where the
# segment LANDS in the destination. So the `real_copy_size`s must sum to exactly `size` AND
# consecutive `copied_in`s must be contiguous -- statements about the DATA, not about the spelling of a call. `dk_shard_cover_*` and `dk_shard_contig_*` assert them. Everything else in this file is a trace.
#
# And the sharper version of the same fact, which is a RESULT a trace cannot see:
# a wrong `minor_offset` leaves the total CORRECT. The skew is subtracted from
# exactly ONE segment (it is zeroed by the GONE upstream `_copyout_sharded`) and the LAST segment is truncated by
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
#   tinygrad/runtime/ops_disk.py:14  `synchronize`              PORTED  `dev_sync` -- it is `pass`
#   tinygrad/runtime/ops_disk.py:16-20 `__init__`                PORTED  `dev_init`
#   GONE  the io_uring guard         PORTED  `dev_ioring_setup`, `Dev.tried` -- upstream DELETED it
#   tinygrad/runtime/ops_disk.py:21-41 `_might_open`             PORTED  `dev_might_open` and its steps
#                                             `dev_warm`, `dev_shm.on`,
#                                             `dev_file.at`, `dev_finish.at`
#   :22  the assert                 PORTED  `dev_fits`, `dev_reopen_msg` -- upstream's `size`
#                                             IS the same refusal
#   :23  the fast path              PORTED  `dev_is_open`, `dev_warm` -- upstream's `size`
#                                             IS the already-open test
#   :26  `filename`                 PORTED  `dsk_filename`
#   :28  the shm predicate          PORTED  `dev_is_shm`, `dsk_shm_name` -- upstream's `filename`
#                                             IS the same predicate's subject
#   :29-31 the shm branch            PORTED  `dev_shm.on`
#   :33-34 the try/except open       PORTED  `dev_file.open.at` -- and :34's
#                                             branch is NOT a parameter; see
#                                             THE EXCEPT IS NOT A BRANCH
#   :35  the block-device guard     PORTED  `dev_file.trunc.at`, `dev_trunc`
#   :36  the mapping                PORTED  `dev_file.mmap.at`
#   tinygrad/runtime/ops_disk.py:37-41 the tail -- upstream's `refcount` IS the
#                                             tail's last word --   PORTED  `dev_sized`, `dev_bumped`,
#                                             `dev_finish.at`
#   tinygrad/runtime/ops_disk.py:39-40 `madvise`                 PORTED  `dev_finish.at` (the condition)
#   tinygrad/runtime/ops_disk.py:42-49 `_might_close`            PORTED  `dev_might_close`
#   tinygrad/runtime/ops_disk.py:160-164 `uring`                PARTIAL `dev_ioring.*` -- the call ORDER and
#                                             the four numbers Python spells
#                                             itself; the three mmap LENGTHS are
#                                             WALL 2
#   tinygrad/runtime/ops_disk.py:51-57 `DiskBuffer`             PORTED  `Db.of`, `db_repr`, `db_buf`
#   tinygrad/runtime/ops_disk.py:59  `MAP_LOCKED`/`MAP_POPULATE` PORTED  `map_locked`, `map_populate`
#   tinygrad/runtime/ops_disk.py:61  `lru` = False               PORTED  `ALLOC_LRU`
#   tinygrad/runtime/ops_disk.py:62-64 `_alloc`                  PORTED  `alloc_of` (`mv_address` is WALL 1)
#   tinygrad/runtime/ops_disk.py:66  `_free`                     PORTED  `alloc_free`
#   tinygrad/runtime/ops_disk.py:67  `_as_buffer`                PORTED  `alloc_as_buffer`
#   tinygrad/runtime/ops_disk.py:68  `_copyin`                   PORTED  `alloc_copyin`
#   tinygrad/runtime/ops_disk.py:69-77 `_copyout`                PORTED  `alloc_copyout`
#   GONE  the NON-uring shard    PORTED  `shard_at`, `shard.go`, `shard_read`,
#                                             `shard_real` -- upstream 4e4f6b9fb DELETED it
#   tinygrad/runtime/ops_disk.py:88-111 `disk_read`              PARTIAL `shard_ioring` -- the two submission
#                                             calls and the segment arithmetic
#   tinygrad/runtime/ops_disk.py:79 `_offset`                   PORTED  `alloc_offset`
#
# ===========================================================================
# THE FOUR WALLS.
#
# 1. ADDRESSES. `mv_address(mv) = ctypes.addressof(ctypes.c_char.from_buffer(mv))`
#    (:86) is a live mmap base address, and it is what every consumer of a Disk
#    buffer reaches a buffer through. The port carries a 0 and names it;
#    `Rc.addr` is the field and `dk_alloc_addr` is the row.
#    TODO(p3) helpers.py:576  symbol=mv_address  -- mv_address -> the mapping's base address.
#
# 2. THE io_uring mmaps (:57-61). Their LENGTHS are `p.sq_off.array +
#    p.sq_entries * 4`, `p.cq_off.cqes + p.cq_entries * sizeof(cqe)` and
#    p.sq_entries * sizeof(sqe)`, and `p` is a `struct_io_uring_params` the KERNEL
#    fills in from the 4096 entries requested at :54. None of it is computable
#    before the syscall, so the trace records the ORDER and the file OFFSET
#    (`IORING_OFF_CQ_RING` = 0x8000000, `IORING_OFF_SQES` = 0x10000000) and not
#    the length.
#    TODO(p3) ops_disk.py:164  symbol=uring  -- the three mmap lengths.
#    TODO(p3) ops_disk.py:164  symbol=uring  -- ditto.
#    TODO(p3) ops_disk.py:164  symbol=uring  -- ditto.
#
# 3. `is_block_device` (:35) is a `pathlib` stat of the PATH and `os.fstat(fd)
#    .st_size` (:35) is a stat of the DESCRIPTOR. Both are one Bool and one `U32`
#    the host supplies, and both ride on `Dev` as `blockdev`/`stsize` so a fixture
#    reaches each of the three cells of :35's conjunction.
#    TODO(p3) ops_disk.py:35  symbol=_might_open  -- is_block_device() and fstat().st_size.
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
# THE except is not a branch. :33-34 is `try: os.open(f, O_RDWR|O_CREAT|O_DIRECT)
# except OSError: os.open(f, O_RDWR|O_CREAT)` and the trace records the ATTEMPT as
# well as the RETRY, in that order -- so :34's two arms produce the SAME trace and
# `dev_file.open.at` takes NO branch parameter for them. The one thing that
# differs is which descriptor ends up in `self.fd`, and both are `os.open` answers
# on the same path, so it is not observable in this trace either. The flags DO
# differ and both are recorded, which is what `dk_open_file_args` pins.
#
# ===========================================================================
# FOUR facts that are easy to get wrong and that the gate pins by name.
#
# A. THE refcount is on the device, NOT on the BUFFER. `_alloc` calls
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
# C. `MAP_LOCKED`/`MAP_POPULATE` (tinygrad/runtime/ops_disk.py:59) ARE platform constants and the `getattr`
#    IS VACUOUS. `map_populate` therefore takes ONE Bool (`osx`), not two, and the
#    file says why rather than carrying a `hasattr` no fixture can falsify. The
#    SAME vacuity does NOT apply to `getattr(os,"O_DIRECT",0)` (:33): Linux has
#    the attribute and macOS does not, so `open_direct` keeps its parameter and
#    `dk_direct_yes`/`dk_direct_no` are a row per cell.
#
# D. THE open fallback changes the flags, NOT the path, AND both flags are
#    RECORDED. :33 asks for `O_RDWR|O_CREAT|O_DIRECT` and :34 retries with
#    `O_RDWR|O_CREAT`, so the two trace arguments differ and `dk_open_file_args` is
#    the row that pins both numbers.
#
# E. THERE is no dtype-TO-SUFFIX table in this file, and the gate should not look
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
# THE constants, AND every one of them is a *PLATFORM fact* WITH two cells.
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

# :103's `mmap.PAGESIZE`. THE one that changes results rather than trace arguments,
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

# :28 -- `sys.platform != "win32" and filename.startswith("shm:")`. TWO conjuncts
# and the first is the platform: on win32 a `shm:` name is opened as a FILE whose
# name is literally "shm:foo". `dk_is_shm_win` is the row that says so.
def dev_is_shm(name: String, win: Bool) -> Bool:
  Bool.and(Bool.not(win), String.starts_with(dsk_filename(name), SHM_PREFIX()))

# ===========================================================================
# THE CLASS LIFECYCLE, :12-20 and :50-71.
# ===========================================================================

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

# ===========================================================================
# `_might_open`, :21-40. Two branches and six steps, and each is one Python line.
# ===========================================================================

# :22 -- `assert self.size is None or size <= self.size`. The message is the
# f-string and `dev_reopen_msg` IS it, so the gate can diff the string.
def dev_fits(+size: U32, +d: Dev) -> Bool:
  Bool.or(Bool.not(Dev.has_size(d)), U32.is_le(size, Dev.size(d)))

# THE message interpolates `self.size`, WHICH is `None` ON a cold device -- so the
# string is `"opened with None"` and not `"opened with 0"`. The port carries size in
# a `U32` and presence in `has_size`, so `None` is the `has_size == False` arm.
# `dk_fresh_msg` is the row, and it is a row against a COLD fixture precisely
# because that is the only way to reach the `None`.

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
# is the row that says so. A short-circuiting `and` in Python is TWO defs in Bend
# whenever the right side has a side effect, and the gate row has to be the one that
# counts the CALL rather than the one that tests the predicate.
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

# :90 -- `_copyin(self, dest, src): dest._buf()[:] = src`. The window is the whole
# slice `[:]`, so the copy is `dest.size` bytes AT ZERO -- not at `dest.offset`.
# The offset is where the destination already sits in the mapping and the slice is
# relative to it. `dk_copyin_at_zero` is the row.
def alloc_copyin.put(x: DbB) -> Dev:
  match x:
    case DbB{w, +d}: dev_put(d, Tr.emit(K_COPYIN(), Win.size(w), Dev.tr(d)))

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

# TWO steps, NOT one: `Tr.emit(K_FILEIO(), fd, Tr.emit(K_SEEK(), off, t))` records
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

def Roff.offs(r: Roff) -> List<&2, U32>:
  match r:
    case Roff{offs, d}: offs

def Roff.dev(r: Roff) -> Dev:
  match r:
    case Roff{offs, d}: d

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
# ==== THE blind spots this port has, and none of them is a gap in the gate ====
#
# These are the places where the port is KNOWN to diverge from `ops_disk.py`. They
# are listed because a divergence that is not written down is indistinguishable
# from a port that is correct, and each one names the row that would catch it if it
# were implemented.
#
# 1. THE `io_uring` ARM'S segment arithmetic is not ported. :119-141 is a pair
#    of while-loops over `sq.ktail`/`cq.khead` and the port records the two
#    submission calls and then computes the segments with the NON-uring fold. This
#    is only correct because :132's `real_copy_size := min(sqe.len - minor_offset,
#    size - copied_in)` IS `shard_real` and :125's `sqe.len` is
#    `min(seg_len, total_copy_size - next_read_offset)` -- i.e. the third term of the
#    non-uring `read_size` is ABSENT. The two arms agree whenever the mapping is at
#    least as long as the shard, which is the invariant `ops_disk.py` relies on, and
#    DISAGREE on fixture D. `dk_shard_ioring_order` is what the port does; nothing
#    checks that it should do more.
# 2. THE SEAM IS NOT A SEAM. `os.open` answers a descriptor, `mmap.mmap` answers
#    a mapping, `os.fstat().st_size` answers a size and `_posixshmem.shm_open`
#    answers a descriptor: none of them exists here, so the port MINTS identifiers
#    from a counter and takes the size from a fixture field. Every row about "which
#    descriptor" or "how big is the file" is a row about the counter and the fixture.
#    `dk_open_file_fd` names one such row and says so.
# 3. `_posixshmem` MAY NOT BE IMPORTED. :6 wraps it in
#    `contextlib.suppress(ImportError)`, so on a host without it :29 raises
#    AttributeError. The port has no such branch: it always takes the shm path.
#    `dk_is_shm_win` is the adjacent row and it is about `sys.platform`, not about
#    the import.
# 4. `_copyout_sharded`'s `_get_free_buf` IS NOT PORTED. :109's
#    `while (copy_batch := _get_free_buf()) is None: pass` is a blocking wait on the
#    caller's allocator, and the port assumes it always succeeds. The segments it
#    yields are independent of WHICH buffer it got, so this is invisible in the
#    arithmetic -- and `dk_shard_cover_*` would be the row that noticed if it were
#    not.
# 5. THE `_might_open` ASSERT IS NOT AN EXCEPTION. :22 raises `AssertionError`
#    and the port LATCHES `refused` instead, which is the template's discipline: no
#    later emit records anything, so a refusal shows up as a TRUNCATION of the trace
#    rather than as an exception value. `dk_grow_trace_unchanged` and
#    `dk_grow_refused` are the two rows, and `dk_buf_refused_calls` is the third.
# TODO(p3) ops_disk.py:105  symbol=disk_read  -- the two while-loops of the io_uring arm.
# TODO(p3) ops_disk.py:125  symbol=disk_copy_rewriter  -- ktail/kring_mask and the sqe array.
# TODO(p3) ops_disk.py:105  symbol=disk_read  -- sq.array[sqe_index] = sqe_index; ktail[0] += 1.
# TODO(p3) ops_disk.py:140  symbol=disk_copy_rewriter  -- `assert cqe.res >= 0`, the third assert in the file.
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

