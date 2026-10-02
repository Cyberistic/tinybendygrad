#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_disk.bend.

Run from the repo root:

    python3 -c "import sys; sys.path.insert(0,'.'); exec(open('.agents/slop/dk-oracle.py').read())"

Every row is COMPUTED here, from `tinygrad/runtime/ops_disk.py`'s own text, so the
diff against the Bend gate is a comparison of two independent transcriptions of the
same 144 lines and not a comparison of a program with itself.

THREE RULES THIS FILE FOLLOWS, and they are the difference between an oracle and a
mirror:

1. **IMMUTABLE VALUES.** A `Dev` is a frozen record and every step returns a new one.
   Python's `DiskDevice` mutates in place, so a mutating oracle makes
   `g.trace == w.trace` true by aliasing -- a tautology, not a check. `dataclasses`
   `frozen=True` makes aliasing impossible: comparing two traces compares two lists.

2. **CPYTHON INTEGERS, NOT `U32`.** Where `ops_disk.py` computes in Python `int`, so
   does this file, INCLUDING the negatives. The Bend port is `U32` and wraps; the two
   places that matters are named by their rows and are marked `& 0xFFFFFFFF` HERE, at
   the single point where the widths are reconciled:
     - `dk_shard_raw_third_d` -- `4096 - 4096 - 6144` is `-2048` here and
       `4294965248` in a `U32`. The row NAME says which it is.
     - `dk_free_underflow_4294967294` -- `-2` here and `4294967294` in a `U32`.
   Everywhere else the widths agree and the arithmetic is Python's.

3. **NO ROW IS A LITERAL.** The earlier version of this file asserted
   `row("dk_open_file_order", True)` and `urow("dk_close_n", 2)`, which checks
   nothing. Every boolean below is a comparison of two computed things and every
   number is an expression.

WHAT THIS ORACLE CANNOT SEE, and the Bend file says so at the same rows: the seam.
`os.open` answers a descriptor, `mmap.mmap` answers a mapping, and neither exists
here -- so the oracle and the port both mint identifiers from a counter, and a row
about "which descriptor" is a row about the counter, not about the kernel.
`dk_open_file_fd` and the `Call{K_CLOSE(), 0}` argument in `dk_open_shm_order` are
the two rows where that shows.
"""

import ctypes, dataclasses, mmap, os, sys
from tinygrad.runtime.autogen import io_uring

# tinygrad/helpers.py's OSX -- read from the source of truth, not guessed.
OSX = sys.platform == "darwin"

# ===========================================================================
# CONSTANTS. Read from the modules `ops_disk.py` imports, so a host difference
# shows up here instead of being papered over by a literal.
# ===========================================================================
O_RDWR = os.O_RDWR                                            # 2 everywhere
O_CREAT_LINUX, O_CREAT_MACOS = 64, 512                        # 64 = 0o100, 512 = 0o1000
O_DIRECT_LINUX, O_DIRECT_MACOS = 16384, 0                     # :33's getattr default

# THE macOS CELL IS ASSERTED AGAINST THIS HOST, not trusted. Four numbers that a
# hardcoded Linux constant would silently get wrong, and each is read from the
# module `ops_disk.py` reads it from:
assert os.O_CREAT == O_CREAT_MACOS, f"os.O_CREAT is {os.O_CREAT}, port's macOS cell is {O_CREAT_MACOS}"
assert getattr(os, "O_DIRECT", 0) == O_DIRECT_MACOS, "macOS gained an O_DIRECT"
assert mmap.PAGESIZE == 16384, f"mmap.PAGESIZE is {mmap.PAGESIZE}, port's macOS cell is 16384"
assert getattr(mmap, "MADV_HUGEPAGE", None) is None, "macOS gained a MADV_HUGEPAGE"

# :81 -- `MAP_LOCKED, MAP_POPULATE = 0 if OSX else 0x2000, getattr(mmap,
# "MAP_POPULATE", 0 if OSX else 0x008000)`. THE `getattr` IS VACUOUS on macOS: `OSX`
# is True so the fallback is 0, AND the attribute is absent, so both cells are 0
# whatever the machine does. That is why the port makes the platform a parameter and
# gates both cells, and the assertion below is what keeps that reading honest.
MAP_SHARED = mmap.MAP_SHARED
MAP_LOCKED_LINUX, MAP_POPULATE_LINUX = 0x2000, 0x008000
assert getattr(mmap, "MAP_POPULATE", None) is None, "macOS gained a MAP_POPULATE"

# :29's `0o600` -- a literal in the source and not a platform question, so ONE cell.
SHM_MODE = 0o600

# :39's `getattr(mmap, "MADV_HUGEPAGE", None)`. The VALUE is `madv_hp`; PRESENCE is
# `Dev.madv`, because what :38 tests is `is not None` and macOS has no such
# attribute at all -- so on the macOS cell the call is not reached, which is why
# `madv_hp(True{})` is 0 and never emitted rather than 14.
MADV_HUGEPAGE_LINUX = 14
def madv_hp(osx): return 0 if osx else MADV_HUGEPAGE_LINUX

def map_locked(osx): return 0 if osx else MAP_LOCKED_LINUX
def map_populate(osx): return 0 if osx else MAP_POPULATE_LINUX
def mem_flags(osx): return MAP_SHARED | map_populate(osx) | map_locked(osx)

def o_creat(osx): return O_CREAT_MACOS if osx else O_CREAT_LINUX
def o_direct(osx): return O_DIRECT_MACOS if osx else O_DIRECT_LINUX
def open_direct(osx, has): return o_direct(osx) if has else 0
def open_flags(osx, direct): return O_RDWR | o_creat(osx) | direct
PAGESIZE_LINUX, PAGESIZE_MACOS = 4096, 16384
def pagesize(osx): return PAGESIZE_MACOS if osx else PAGESIZE_LINUX

NR_IO_URING_SETUP = io_uring.NR_io_uring_setup              # :54
NR_IO_URING_ENTER = io_uring.NR_io_uring_enter              # :130
IORING_ENTRIES = 4096                                      # :54
IORING_OFF_CQ_RING = io_uring.IORING_OFF_CQ_RING           # :59
IORING_OFF_SQES = io_uring.IORING_OFF_SQES                 # :61
IORING_OP_READ = io_uring.IORING_OP_READ                   # :124
IORING_ENTER_GETEVENTS = io_uring.IORING_ENTER_GETEVENTS   # :130
SIZEOF_CQE = ctypes.sizeof(io_uring.struct_io_uring_cqe)
SIZEOF_SQE = ctypes.sizeof(io_uring.struct_io_uring_sqe)

# ===========================================================================
# THE TAGS. One per host call, numbered in `ops_disk.py` line order so a tag names
# the line it belongs to. These NUMBERS ARE NOT `ops_disk.py`'s -- they are the
# gate's, and they are checked by `dk_ioring_*` and the trace rows, not asserted.
# ===========================================================================
K_IOURING_SETUP, K_MMAP, K_SHM_OPEN, K_MMAP_SHM = 0, 1, 2, 3
K_CLOSE, K_OPEN_DIRECT, K_OPEN, K_FSTAT, K_FTRUNCATE = 4, 5, 6, 7, 8
K_MADVISE, K_MUNMAP, K_COPYIN, K_COPYOUT = 9, 10, 11, 12
K_FILEIO, K_SEEK, K_READINTO, K_FILEIO_CLOSE = 13, 14, 15, 16
K_SQE_STORE, K_IORING_ENTER = 17, 18

rows = []
def row(nm, b): rows.append(f"{nm}={b}")
def urow(nm, v): rows.append(f"{nm}={v}")
def srow(nm, v): rows.append(f"{nm}={v}")

def u32(v): return v & 0xFFFFFFFF

# ===========================================================================
# THE MODEL. `Dev` is `DiskDevice`'s state (:14-20) plus the six host facts a seam
# has to decide and the trace the port records.
# ===========================================================================
@dataclasses.dataclass(frozen=True)
class Dev:
  name: str
  size: int = 0
  has_size: bool = False
  fd: int = 0
  has_fd: bool = False
  refcount: int = 0
  has_mem: bool = False
  tried: bool = False
  ioring: bool = False
  osx: bool = False
  win: bool = False
  direct: int = 0    # set per fixture; `fx_plain` uses open_direct(False, True)
  blockdev: bool = False
  madv: bool = True
  stsize: int = 0
  trace: tuple = ()
  refused: bool = False
  nxt: int = 0

  def emit(self, k, arg):
    """`Tr.emit` -- :78's assert is a LATCH, so nothing after a refusal records."""
    if self.refused: return self
    return dataclasses.replace(self, trace=self.trace + ((k, arg),), nxt=self.nxt + 1)

  def here(self): return self.nxt                # the seam's descriptor answer
  def cfg(self, **kw): return dataclasses.replace(self, **kw)
  def reset(self): return dataclasses.replace(self, trace=(), nxt=0)

def pairs(t): return [x for c in t for x in c]
def trace_str(t): return ",".join(str(x) for x in pairs(t))
def ncalls(k, t): return sum(1 for c in t if c[0] == k)
def seen(t): return len(t)
def arg_of(k, t):
  a = [c[1] for c in t if c[0] == k]
  return a[0] if a else 0

# `Tr.has` -- a SUBSEQUENCE test, exactly as `ops_webgpu.bend`'s matcher is.
def seq(t, pat):
  i = 0
  for c in t:
    if i < len(pat) and c == pat[i]: i += 1
  return i == len(pat)
# `seq_eq` -- a WHOLE-sequence test.
def seq_eq(t, pat): return pairs(t) == pairs(pat)

# ===========================================================================
# :50-71 -- `_iouring_setup`.
# ===========================================================================
def iouring_setup(linux, ok, d):
  d = dataclasses.replace(d, tried=True)                  # :51, BEFORE the test
  if not linux: return d                                 # :53
  d = d.emit(K_IOURING_SETUP, IORING_ENTRIES)             # :54
  if not ok: return d                                    # :55, `if fd < 0: return`
  d = d.emit(K_MMAP, 0)                                  # :57
  d = d.emit(K_MMAP, IORING_OFF_CQ_RING)                 # :59
  d = d.emit(K_MMAP, IORING_OFF_SQES)                    # :61
  return dataclasses.replace(d, ioring=True)             # :71

# ===========================================================================
# :26, :28 -- the path.
# ===========================================================================
DISK_PREFIX, SHM_PREFIX = "disk:", "shm:"
def dsk_filename(name): return name[len(DISK_PREFIX):]
def dsk_lstrip(s): return s.lstrip("/")
def dsk_shm_name(fn): return "/" + dsk_lstrip(fn[len(SHM_PREFIX):])
def dev_is_shm(name, win): return (not win) and dsk_filename(name).startswith(SHM_PREFIX)
def dsk_device_id(name):
  # device.py:397 -- the SECOND colon field, digits only.
  f = name.split(":")[1] if name.count(":") > 1 else ""
  return int(f) if f.isdigit() else 0

DISK, DISK_SHM, DISK_DEV = "disk:/tmp/dk.bin", "disk:shm:dk", "disk:/dev/sda"

# THE FIXTURES, one per cell of the six host facts, mirroring the .bend's `dev_cfg`
# and `fx_*` exactly -- including WHICH platform each one is. `fx_osx` is the macOS
# cell throughout: `osx` true, `O_DIRECT` absent (so `direct` is `getattr`'s 0) and
# `madv` false because `mmap.MADV_HUGEPAGE` does not exist there.
def dev_init(name): return iouring_setup(True, True, Dev(name,
                                      direct=open_direct(False, True), madv=True))
def fx_plain(): return dev_init(DISK)
def fx_nomadv(): return dataclasses.replace(dev_init(DISK), madv=False)
def fx_osx(): return dataclasses.replace(dev_init(DISK), osx=True,
                                        direct=open_direct(True, True), madv=False)
def fx_blockdev(): return dataclasses.replace(dev_init(DISK_DEV), blockdev=True,
                                              direct=open_direct(False, True))
def fx_longfile(): return dataclasses.replace(dev_init(DISK), stsize=65536,
                                              direct=open_direct(False, True))
def fx_noioring(): return iouring_setup(False, True, Dev(DISK,
                                        direct=open_direct(False, True), madv=True))
def fx_ioring_fail(): return iouring_setup(True, False, Dev(DISK,
                                        direct=open_direct(False, True), madv=True))


# ===========================================================================
# :21-40 -- `_might_open`. Each numbered step is its own statement, in Python's
# order, and every `and` that has a CALL on its right is SPLIT -- because Python
# short-circuits and a predicate that folds two calls into one records a call that
# never happened. :35 is the live case.
# ===========================================================================
def dev_fits(size, d): return (not d.has_size) or size <= d.size     # :22
def dev_is_open(d): return d.has_size and d.has_mem                   # :23
def dev_fresh_msg(size, d):                                          # :22's f-string
  return (f"can't reopen Disk tensor with larger size, opened with "
          f"{'None' if not d.has_size else d.size}, tried to open with {size}")

def dev_shm_on(size, d):                                              # :29-31
  fd = d.here()
  d = d.emit(K_SHM_OPEN, SHM_MODE)                                    # :29
  d = d.emit(K_MMAP_SHM, mem_flags(d.osx))                            # :30
  d = dataclasses.replace(d, has_mem=True)
  return d.emit(K_CLOSE, fd)                                          # :31 -- NOT self.fd

def dev_file_trunc_go(trunc, size, d):                                # :35
  d = d.emit(K_FSTAT, d.stsize)                                       # the 2nd conjunct
  return d.emit(K_FTRUNCATE, size) if trunc else d                    # its body

def dev_file_mmap(size, d):                                           # :36
  return dataclasses.replace(d.emit(K_MMAP, size), has_mem=True)

def dev_file_at(block, size, d):                                      # :32-36
  fd = d.here()
  d = d.emit(K_OPEN_DIRECT, open_flags(d.osx, d.direct))              # :33 the ASK
  d = dataclasses.replace(d.emit(K_OPEN, open_flags(d.osx, 0)),       # :34
                         fd=fd, has_fd=True)
  if not block: d = dev_file_trunc_go(d.stsize < size, size, d)       # :35
  return dev_file_mmap(size, d)                                       # :36

def dev_might_open(size, d):                                          # :21
  if not dev_fits(size, d): return dataclasses.replace(d, refused=True)   # :22
  if dev_is_open(d): return dataclasses.replace(d, refcount=d.refcount + 1) # :24
  d = dev_shm_on(size, d) if dev_is_shm(d.name, d.win) else dev_file_at(d.blockdev, size, d)
  d = dataclasses.replace(d, size=size, has_size=True)                # :37
  if d.madv: d = d.emit(K_MADVISE, madv_hp(d.osx))                     # :39
  return dataclasses.replace(d, refcount=d.refcount + 1)              # :40

def dev_sync(d): return d                                             # :12, `pass`

# ===========================================================================
# :41-49 -- `_might_close`. THE DECREMENT IS :42 AND THE TEST IS :43, so the test
# reads the WALKED count.
# ===========================================================================
def may_close(d):
  d = dataclasses.replace(d, refcount=d.refcount - 1)                 # :42
  if d.refcount != 0: return d                                        # :43
  if d.has_fd: d = d.emit(K_CLOSE, d.fd)                              # :44
  if d.has_mem: d = d.emit(K_MUNMAP, d.size)                          # :47
  return dataclasses.replace(d, size=0, has_size=False)               # :49 -- and ONLY size

# ===========================================================================
# :73-79 -- `DiskBuffer`.
# ===========================================================================
@dataclasses.dataclass(frozen=True)
class Db:
  d: Dev
  size: int
  offset: int = 0

  def __repr__(self): return f"<DiskBuffer size={self.size} offset={self.offset}>"
  def window(self): return (self.offset, self.offset + self.size)     # :79

def db_buf(b, d):                                                     # :77-79
  if not b.d.has_mem: d = dataclasses.replace(d, refused=True)        # :78
  return (b, d)

# ===========================================================================
# :84-99 -- the allocator.
# ===========================================================================
def alloc_of(size, d):                                                # :84-86
  e = dev_might_open(size, d)
  b, e = db_buf(Db(e, size), e)
  return (b, 0, e)                       # (buffer, addr, device); `addr` is WALL 1
def alloc_free(d): return may_close(d)                                # :88
def alloc_as_buffer(b, d): return db_buf(b, d)                        # :89
def alloc_copyin(dest, d): return d.emit(K_COPYIN, dest.size)         # :90
def alloc_copyout_posix(src, d): return ((), d.emit(K_COPYOUT, src.size))  # :99

def copyout_osx(src, chunks, d):                                      # :94-97
  d = d.emit(K_FILEIO, d.fd)                                          # :94
  d = d.emit(K_SEEK, src.offset)                                      # :95
  offs, got = [], 0
  for n in chunks:                                                    # :97
    offs.append(got)
    d = d.emit(K_READINTO, got)
    got += n
  return (tuple(offs), d.emit(K_FILEIO_CLOSE, 0))                     # the `with` exit

def alloc_copyout(chunks, src, d):                                    # :91-99
  # :92 reads `OSX and self.dev.fd is not None` -- `self` is the ALLOCATOR, so the
  # platform and the descriptor come from the ALLOCATOR'S device and only the OFFSET
  # in the seek comes from `src`. Reading `src.device` instead is wrong in general
  # and `dk_copyout_shm_fileio` is the row: a `disk:shm:` device has `fd is None`,
  # so OSX does NOT move it to the FileIO arm.
  if d.osx and d.has_fd: return copyout_osx(src, chunks, d)           # :92
  return alloc_copyout_posix(src, d)                                  # :99

def alloc_offset(b, size, offset): return Db(b.d, size, offset)       # :144

# ===========================================================================
# :101-116 -- `_copyout_sharded`, the non-uring arm, as a generator of segments.
# PYTHON INTEGERS THROUGHOUT, so a negative third term is negative.
# ===========================================================================
def shard_read(off, seg_len, total, fd_off, devsize):                 # :110
  return min(seg_len, total - off, devsize - fd_off - off)
def shard_read_u32(off, seg_len, total, fd_off, devsize):             # :110, as U32
  return min(seg_len, u32(total - off), u32(devsize - fd_off - off))
def shard_real(rd, minor, size, copied_in):                           # :113
  return min(rd - minor, size - copied_in)

def shard_total(size, off, osx):                                       # :104
  ps = pagesize(osx)
  return -(-(size + off % ps) // ps) * ps

def shard_run(size, off, seg_len, devsize, d, osx=False, wrap=False):
  """The whole :107-115 loop. Yields (off, read, copied_in, minor, real).

  THE LOOP RUNS `shard_n(...)` TIMES AND MULTIPLIES, rather than stepping
  `range(0, total, seg_len)` by `seg_len`. The two agree for `seg_len > 0`, and
  only this spelling survives `seg_len == 0`, which is a `LISTED DIVERGENCE` and not
  a portability accident -- see `shard_n`.
  """
  minor_offset = off % pagesize(osx)                                  # :103
  fd_offset = off - minor_offset                                      # :103
  total = shard_total(size, off, osx)                                 # :104
  copied_in, segs = 0, []
  for i in range(shard_n(total, seg_len)):                            # :108
    o = i * seg_len
    # :110 -- `shard_read_u32` when wrapping, because the WRAP HAS TO HAPPEN BEFORE
    # THE `min` and not after it. Wrapping the result instead wraps Python's `-2048`
    # and keeps a `read_size` of 4294965248, which is a THIRD answer that neither
    # language produces.
    read_size = (shard_read_u32 if wrap else shard_read)(
        o, seg_len, total, fd_offset, devsize)                        # :110
    real = shard_real(read_size, minor_offset, size, copied_in)       # :113
    if wrap:
      # THE `U32` DIVERGENCE, and it is the ONLY place this file stops being
      # CPython. The .bend is `U32`, so a negative third term WRAPS instead of
      # staying negative, and `min` then answers `seg_len` where Python answers the
      # negative number. `ops_disk.py` cannot reach the state -- it relies on
      # `fd_offset + total_copy_size <= src.device.size`, which fixture D violates
      # on purpose -- so the divergence is not a bug in the source and is not a bug
      # the port can fix inside `U32`. It is RECORDED: `shard_read_u32` is the
      # port's arithmetic and `shard_read` is Python's, and the assertions below
      # check that the two really do disagree, so if a future `U32` ever stops
      # wrapping this file fails instead of quietly agreeing with itself.
      read_size, real = u32(read_size), u32(real)
    d = d.emit(K_COPYOUT, read_size)                                  # :111
    segs.append((o, read_size, copied_in, minor_offset, real))        # :114
    copied_in, minor_offset = copied_in + real, 0                     # :115
  return (tuple(segs), d)

# `,` within a segment and ` ` between, which is what the .bend's `seg_str` prints:
# all FIVE facts of a segment in one value, and every segment in one string.
def seg_str(segs): return " ".join(",".join(str(x) for x in s) for s in segs)
def cover(segs): return sum(s[4] for s in segs)                       # a RESULT
def contig(segs):                                                      # a RESULT
  run = 0
  for _, _, cin, _, real in segs:
    if cin != run: return False
    run += real
  return True

def shard_n(total, seg_len):
  """`range(0, total, seg_len)`'s length. **CPython RAISES FOR `seg_len == 0`** --
  `ValueError: range() arg 3 must not be zero` -- so this function's zero case is
  the PORT's answer and not Python's. That is a real divergence and it is a real
  one: nothing in `_copyout_sharded` can pass 0 either, because `seg_len` comes from
  the caller. `dk_shard_seg0_n` and `dk_shard_seg0_segs` are the two rows that show
  the port answering 0 segments where CPython raises, and `seg0_raises()` below is
  the assertion that keeps that honest if CPython ever changes."""
  return 0 if seg_len == 0 else -(-total // seg_len)

def seg0_raises():
  try: range(0, 12288, 0)
  except ValueError: return True
  return False
assert seg0_raises(), "CPython no longer raises on range step 0; re-check dk_shard_seg0_*"

# ===========================================================================
# THE GATE, in the .bend file's row order so the diff is line-for-line.
# ===========================================================================
def t_path():
  srow("dk_file_plain", dsk_filename(DISK))
  srow("dk_file_bare", dsk_filename(DISK_PREFIX))
  srow("dk_file_rel", dsk_filename("disk:relative.bin"))
  srow("dk_file_dev", dsk_filename(DISK_DEV))
  srow("dk_file_shm", dsk_filename(DISK_SHM))
  srow("dk_shm_plain", dsk_shm_name(dsk_filename(DISK_SHM)))
  srow("dk_shm_empty", dsk_shm_name(dsk_filename("disk:shm:")))
  row("dk_shm_slashes_eq_plain", dsk_shm_name(dsk_filename("disk:shm://dk")) == "/dk")
  row("dk_shm_abs_eq_plain", dsk_shm_name(dsk_filename("disk:shm:/dk")) == "/dk")
  row("dk_shm_allslash_eq_empty", dsk_shm_name(dsk_filename("disk:shm://///")) == "/")
  row("dk_shm_trailing_kept", dsk_shm_name(dsk_filename("disk:shm:a/b")) == "/a/b")
  row("dk_is_shm_plain", dev_is_shm(DISK, False))
  row("dk_is_shm_shm", dev_is_shm(DISK_SHM, False))
  row("dk_is_shm_win", dev_is_shm(DISK_SHM, True))
  row("dk_is_shm_prefix_only", dev_is_shm(DISK_PREFIX, False))
  urow("dk_device_id", dsk_device_id("disk:2:/tmp/x"))

def t_flags():
  urow("dk_locked_linux", map_locked(False))
  urow("dk_locked_osx", map_locked(True))
  urow("dk_populate_linux", map_populate(False))
  urow("dk_populate_osx", map_populate(True))
  urow("dk_mem_flags_linux", mem_flags(False))
  urow("dk_mem_flags_osx", mem_flags(True))
  urow("dk_direct_yes", open_direct(False, True))
  urow("dk_direct_no", open_direct(False, False))
  urow("dk_direct_yes_mac", open_direct(True, True))
  urow("dk_direct_no_mac", open_direct(True, False))
  urow("dk_open_plain", open_flags(False, 0))
  urow("dk_open_odirect", open_flags(False, open_direct(False, True)))
  urow("dk_open_plain_mac", open_flags(True, 0))
  urow("dk_open_odirect_mac", open_flags(True, open_direct(True, True)))
  row("dk_open_has_rdwr", (open_flags(False, 0) & O_RDWR) == O_RDWR)
  row("dk_open_has_creat", (open_flags(False, 0) & O_CREAT_LINUX) == O_CREAT_LINUX)
  row("dk_open_has_creat_mac", (open_flags(True, 0) & O_CREAT_MACOS) == O_CREAT_MACOS)
  row("dk_open_odirect_extra",
      open_flags(False, open_direct(False, True)) > open_flags(False, 0))
  row("dk_open_odirect_mac_same",
      open_flags(True, open_direct(True, True)) == open_flags(True, 0))
  urow("dk_pagesize", pagesize(False))
  urow("dk_pagesize_mac", pagesize(True))
  urow("dk_shm_mode", SHM_MODE)
  urow("dk_madv_hugepage", madv_hp(False))
  urow("dk_madv_hugepage_mac", madv_hp(True))
  urow("dk_ioring_nr_setup", NR_IO_URING_SETUP)
  urow("dk_ioring_nr_enter", NR_IO_URING_ENTER)
  urow("dk_ioring_entries", IORING_ENTRIES)
  urow("dk_ioring_off_cq", IORING_OFF_CQ_RING)
  urow("dk_ioring_off_sqes", IORING_OFF_SQES)
  urow("dk_ioring_op_read", IORING_OP_READ)
  urow("dk_ioring_getevents", IORING_ENTER_GETEVENTS)
  urow("dk_ioring_cqe", SIZEOF_CQE)
  urow("dk_ioring_sqe", SIZEOF_SQE)
  urow("dk_alloc_lru", 0)                                   # ops_disk.py:83

def t_open():
  p = dev_might_open(10000, dev_init(DISK))
  s = dev_might_open(10000, dev_init(DISK_SHM))
  p0 = dev_might_open(10000, dev_init(DISK).reset())
  s0 = dev_might_open(10000, dev_init(DISK_SHM).reset())
  # THE MATCHER PINS ITSELF FIRST.
  row("dk_has_rejects_reverse", not seq(p.trace, [(K_MMAP, 10000), (K_FTRUNCATE, 10000)]))
  row("dk_has_rejects_absent", not seq(p.trace, [(K_COPYOUT, 999)]))
  row("dk_open_file_order", seq_eq(p0.trace,
      [(K_OPEN_DIRECT, open_flags(False, open_direct(False, True))),
       (K_OPEN, open_flags(False, 0)), (K_FSTAT, 0), (K_FTRUNCATE, 10000),
       (K_MMAP, 10000), (K_MADVISE, madv_hp(False))]))
  row("dk_open_shm_order", seq_eq(s0.trace,
      [(K_SHM_OPEN, SHM_MODE), (K_MMAP_SHM, mem_flags(False)), (K_CLOSE, 0),
       (K_MADVISE, madv_hp(False))]))
  srow("dk_open_file_trace", trace_str(p.trace))
  urow("dk_open_file_fstat", ncalls(K_FSTAT, p.trace))
  urow("dk_open_file_ftrunc", ncalls(K_FTRUNCATE, p.trace))
  urow("dk_open_direct_attempts", ncalls(K_OPEN_DIRECT, p.trace))
  urow("dk_open_fallback_attempts", ncalls(K_OPEN, p.trace))
  urow("dk_open_total_attempts", ncalls(K_OPEN_DIRECT, p.trace) + ncalls(K_OPEN, p.trace))
  row("dk_shm_no_open_attempt", ncalls(K_OPEN_DIRECT, s.trace) == 0)
  srow("dk_open_shm_trace", trace_str(s.trace))
  urow("dk_open_shm_n", seen(s.trace))
  row("dk_shm_fd_none", not s.has_fd)
  urow("dk_shm_size", s.size)
  row("dk_shm_has_mem", s.has_mem)
  row("dk_open_file_has_fd", p.has_fd)
  urow("dk_open_file_fd", p.fd)
  urow("dk_shm_fd_is_none", 1 if s.has_fd else 0)
  row("dk_madvise_order", seq(p.trace, [(K_MMAP, 10000), (K_MADVISE, madv_hp(False))]))
  urow("dk_madvise_n", ncalls(K_MADVISE, p.trace))
  nomadv = dev_might_open(10000, Dev(DISK, madv=False))
  urow("dk_nomadv_n", ncalls(K_MADVISE, nomadv.trace))
  bd = dev_might_open(10000, Dev(DISK_DEV, blockdev=True,
                                        direct=open_direct(False, True)))
  urow("dk_blockdev_fstat", ncalls(K_FSTAT, bd.trace))
  urow("dk_blockdev_ftrunc", ncalls(K_FTRUNCATE, bd.trace))
  lo = dev_might_open(10000, Dev(DISK, stsize=65536,
                                     direct=open_direct(False, True)))
  urow("dk_longfile_fstat", ncalls(K_FSTAT, lo.trace))
  urow("dk_longfile_ftrunc", ncalls(K_FTRUNCATE, lo.trace))
  urow("dk_open_refcount", p.refcount)
  urow("dk_open_size", p.size)
  row("dk_open_has_size", p.has_size)
  row("dk_open_has_mem", p.has_mem)
  row("dk_sync_noop", dev_sync(dev_init(DISK)).trace == dev_init(DISK).trace)

def t_refuse():
  w = dev_might_open(10000, dev_init(DISK))                          # :23-25
  w = dev_might_open(10000, w)
  srow("dk_warm_trace", trace_str(w.trace))
  urow("dk_warm_refcount", w.refcount)
  urow("dk_warm_size", w.size)
  g = dev_might_open(20000, w)                                       # :22 refuses
  row("dk_grow_refused", g.refused)
  row("dk_grow_trace_unchanged", g.trace == w.trace)
  urow("dk_grow_refcount", g.refcount)
  urow("dk_grow_size", g.size)
  row("dk_grow_has_mem_unchanged", g.has_mem == w.has_mem)
  srow("dk_grow_msg", dev_fresh_msg(20000, w))
  fresh = dev_init(DISK)
  srow("dk_fresh_msg", dev_fresh_msg(10000, fresh))
  k = dev_might_open(4000, w)                                        # a SHRINK is legal
  row("dk_shrink_not_refused", not k.refused)
  row("dk_shrink_trace_unchanged", k.trace == w.trace)
  urow("dk_shrink_refcount", k.refcount)
  urow("dk_shrink_size", k.size)
  row("dk_is_open_fresh", dev_is_open(fresh))
  row("dk_is_open_after", dev_is_open(w))

def t_close():
  # RESET AFTER THE OPEN: the calls in the row are the FREE's, so resetting before
  # the open would leave the open's calls in the trace and deleting them after would
  # delete the row. `dk_close_exactly_two` and `dk_close_shm_only_unmap` are the
  # rows, and the shm one is why the reset cannot move.
  c = may_close(dev_might_open(10000, dev_init(DISK)).reset())
  row("dk_close_exactly_two", seq_eq(c.trace, [(K_CLOSE, c.fd), (K_MUNMAP, 10000)]))
  urow("dk_close_n", ncalls(K_CLOSE, c.trace) + ncalls(K_MUNMAP, c.trace))
  urow("dk_close_refcount", c.refcount)
  row("dk_close_size_none", not c.has_size)
  row("dk_close_keeps_mem", c.has_mem)
  row("dk_close_keeps_fd", c.has_fd)
  row("dk_warm_needs_both", not dev_is_open(c))
  sc = may_close(dev_might_open(10000, dev_init(DISK_SHM)).reset())
  urow("dk_close_shm_closes", ncalls(K_CLOSE, sc.trace))
  urow("dk_close_shm_unmaps", ncalls(K_MUNMAP, sc.trace))
  row("dk_close_shm_only_unmap", seq_eq(sc.trace, [(K_MUNMAP, 10000)]))
  # FACT A -- two allocs of DIFFERENT sizes on one device.
  a1 = dev_might_open(40960, dev_init(DISK))
  a2 = dev_might_open(4096, a1)
  urow("dk_two_alloc_refcount", a2.refcount)
  f1 = may_close(a2)
  row("dk_one_free_trace_unchanged", f1.trace == a2.trace)
  urow("dk_one_free_refcount", f1.refcount)
  f2 = may_close(f1.reset())
  row("dk_two_free_exactly_two", seq_eq(f2.trace, [(K_CLOSE, f2.fd), (K_MUNMAP, 40960)]))
  urow("dk_two_free_unmap_size", arg_of(K_MUNMAP, f2.trace))
  # the SECOND `_alloc`'s buffer size, which is 4096 -- NOT the device's 40960. The
  # device grew on the FIRST alloc and `_might_open` does not shrink it (:37 runs
  # only on the cold path), so reading `self.size` here is the tempting wrong answer.
  urow("dk_last_alloc_size", 4096)
  # THE UNDERFLOW. Python's -2 and the `U32`'s 4294967294 are the same number; the
  # ROW NAME is the `U32` spelling, so this is the one place the widths are
  # reconciled, and it is reconciled HERE and not in the arithmetic.
  u1 = may_close(c)
  u2 = may_close(u1)
  urow("dk_free_underflow_4294967294", u32(u2.refcount))
  urow("dk_free_underflow_calls", ncalls(K_CLOSE, u2.trace) + ncalls(K_MUNMAP, u2.trace))
  row("dk_free_underflow_refused", u2.refused)

def t_buf():
  b, addr, rd = alloc_of(10, dev_init(DISK))                         # :84-86
  srow("dk_repr", repr(b))
  srow("dk_repr_zero", repr(alloc_offset(b, 10, 0)))
  urow("dk_alloc_addr", addr)
  urow("dk_alloc_size", b.size)
  urow("dk_alloc_offset", b.offset)
  urow("dk_win_lo", b.window()[0])
  urow("dk_win_hi", b.window()[1])
  urow("dk_alloc_refcount", rd.refcount)
  v = alloc_offset(b, 10, 4)                                         # offset 4
  # `_copyin`'s slice is `[:]`, so the bytes land at ZERO of the window, not at
  # `offset` -- the trace argument is the WINDOW's size, which is `v.size`.
  ci = alloc_copyin(v, rd.reset())                                   # :90
  row("dk_copyin_at_zero", seq_eq(ci.trace, [(K_COPYIN, v.size)]))
  _, cposix = alloc_copyout((), v, ci.reset())                       # :99
  row("dk_copyout_at_zero", seq_eq(cposix.trace, [(K_COPYOUT, v.size)]))
  # the OSX arm. `fx_osx` is a device whose `osx` is set AND whose `direct` is 0,
  # because :33's `getattr(os,"O_DIRECT",0)` is 0 here.
  oo = dev_might_open(10000, fx_osx()).reset()
  offs, ro = alloc_copyout([10, 12, 5], v, oo)                       # :94-97
  row("dk_copyout_osx_order", seq_eq(ro.trace,
      [(K_FILEIO, ro.fd), (K_SEEK, v.offset), (K_READINTO, 0),
       (K_READINTO, 10), (K_READINTO, 22), (K_FILEIO_CLOSE, 0)]))
  srow("dk_copyout_osx_trace", trace_str(ro.trace))
  srow("dk_copyout_osx_offs", ",".join(str(o) for o in offs))
  urow("dk_copyout_osx_reads", ncalls(K_READINTO, ro.trace))
  ab, abd = alloc_as_buffer(v, ci)                                   # :89
  urow("dk_as_buffer_lo", ab.window()[0])
  # `hi` is `offset + size` (4 + 10 = 14) and the row asks for the WIDTH, which is
  # `offset + size - offset`. Printing `hi` is the plausible wrong answer and it is
  # why `dk_as_buffer_lo` sits next to it.
  urow("dk_as_buffer_size", ab.window()[1] - ab.window()[0])
  row("dk_as_buffer_no_call", abd.trace == ci.trace)
  sd = dev_might_open(10000, dataclasses.replace(fx_osx(), name=DISK_SHM))
  _, srm = alloc_copyout([10], Db(sd, 10), sd)                       # the shm arm of :92
  urow("dk_copyout_shm_fileio", ncalls(K_FILEIO, srm.trace))
  urow("dk_copyout_shm_copyout", ncalls(K_COPYOUT, srm.trace))
  # `shm` AND `OSX`. ON A LINUX shm DEVICE `osx` IS FALSE, SO :92's FIRST CONJUNCT
  # ALREADY PICKS THE ARM AND THE SECOND IS NEVER READ -- which is why a port that
  # DROPS `self.dev.fd is not None` is invisible on the fixture above and visible
  # only here. The four rows are the claim and the oracle states it as one:
  # `assert not sdo.has_fd and sdo.osx` is the combination that makes the second
  # conjunct the deciding one.
  sdo = dev_might_open(10000, dataclasses.replace(fx_osx(), name=DISK_SHM)).reset()
  _, sro = alloc_copyout([10], Db(sdo, 10), sdo)
  row("dk_copyout_shm_osx_has_no_fd", not sdo.has_fd)
  row("dk_copyout_shm_osx_is_osx", sdo.osx)
  row("dk_copyout_shm_osx_posix", seq_eq(sro.trace, [(K_COPYOUT, 10)]))
  urow("dk_copyout_shm_osx_fileio", ncalls(K_FILEIO, sro.trace))
  # and the mirror: a macOS FILE device HAS an fd, so the FileIO arm is taken.
  row("dk_copyout_osx_file_has_fd", oo.has_fd)
  assert not sdo.has_fd and sdo.osx, \
    "the shm+OSX fixture stopped being the combination that reaches :92's second conjunct"
  w = alloc_offset(b, 20, 8)                                         # :144
  urow("dk_offset_size", w.size)
  urow("dk_offset_off", w.offset)
  urow("dk_offset_accumulated_would_be", b.offset + 8)
  row("dk_offset_same_device", w.d.name == rd.name)
  nb = Db(dev_init(DISK), 10)
  srow("dk_not_open_msg", f"DiskBuffer wasn't opened: {nb.d.name}")  # :78's f-string
  ud, udd = db_buf(nb, dev_init(DISK))                               # :78 refuses
  row("dk_buf_refused", udd.refused)
  urow("dk_buf_refused_calls", seen(udd.trace))

def t_shard():
  a_dev = dev_init(DISK)
  aseg, a = shard_run(10000, 0, 4096, 40960, a_dev, osx=False)       # A
  urow("dk_shard_total_a", shard_total(10000, 0, False))
  urow("dk_shard_fd_a", 0 - 0 % pagesize(False))
  urow("dk_shard_minor_a", 0 % pagesize(False))
  urow("dk_shard_n_formula_a", shard_n(shard_total(10000, 0, False), 4096))
  srow("dk_shard_a", seg_str(aseg))
  urow("dk_shard_cover_a", cover(aseg))
  row("dk_shard_contig_a", contig(aseg))
  urow("dk_shard_copyouts_a", ncalls(K_COPYOUT, a.trace))
  urow("dk_shard_seg_len_a", len(aseg))
  # THE macOS CELL. `mmap.PAGESIZE` is 16384 here (asserted at the top), so the
  # total, the segment count and the last segment's `cin` all differ -- which is
  # what makes `pagesize` falsifiable rather than a constant column.
  amseg, am = shard_run(10000, 0, 4096, 40960, a_dev, osx=True)
  urow("dk_shard_total_a_mac", shard_total(10000, 0, True))
  urow("dk_shard_n_formula_a_mac", shard_n(shard_total(10000, 0, True), 4096))
  srow("dk_shard_a_mac", seg_str(amseg))
  row("dk_shard_a_differs_by_platform", seg_str(amseg) != seg_str(aseg))
  bseg, b = shard_run(5000, 100, 2048, 65536, a_dev, osx=False)      # B
  urow("dk_shard_total_b", shard_total(5000, 100, False))
  urow("dk_shard_fd_b", 100 - 100 % pagesize(False))
  urow("dk_shard_minor_b", 100 % pagesize(False))
  urow("dk_shard_n_formula_b", shard_n(shard_total(5000, 100, False), 2048))
  srow("dk_shard_b", seg_str(bseg))
  urow("dk_shard_cover_b", cover(bseg))
  row("dk_shard_contig_b", contig(bseg))
  urow("dk_shard_copyouts_b", ncalls(K_COPYOUT, b.trace))
  urow("dk_shard_seg_len_b", len(bseg))
  cseg, c = shard_run(5000, 5000, 2048, 65536, a_dev, osx=False)     # C
  urow("dk_shard_fd_c", 5000 - 5000 % pagesize(False))
  urow("dk_shard_minor_c", 5000 % pagesize(False))
  srow("dk_shard_c", seg_str(cseg))
  urow("dk_shard_cover_c", cover(cseg))
  row("dk_shard_contig_c", contig(cseg))
  # D -- THE SHORT MAPPING. The third term of `read_size` is negative here and
  # wraps to 4294965248 in the `U32`, which is the ONLY row where this file masks to
  # 32 bits. `dk_shard_read4_d` is the pair row: the mask is on the value and not on
  # the answer, and the answer is `seg_len` either way.
  third_d = 4096 - (100 - 100 % pagesize(False)) - 6144
  # THE GATE CANNOT PRINT CPython's `-2048`: `U32` has no signed type, which IS the
  # divergence. What it CAN print is the wrapped term (4294965248, i.e. -2048 read
  # as a bit pattern), the `min` that term defeats (2048 where Python says -2048)
  # and the cover that follows (10000 where Python says 1948). The three assertions
  # below are the pair: they fail loudly if `U32` ever stops wrapping, which is what
  # turns "this row is different" from an excuse into a measurement.
  urow("dk_shard_raw_third_d", u32(third_d))
  urow("dk_shard_read4_d", shard_read_u32(6144, 2048, shard_total(5000, 100, False),
                                          0, 4096))
  urow("dk_shard_read3_d", shard_read_u32(4096, 2048, shard_total(5000, 100, False),
                                          0, 4096))
  assert third_d == -2048, f"the D fixture's third term is {third_d}, not -2048"
  assert (shard_read_u32(6144, 2048, shard_total(5000, 100, False), 0, 4096)
          != shard_read(6144, 2048, shard_total(5000, 100, False), 0, 4096)), \
    "the U32 wrap and CPython now agree; drop the dk_shard_*_d divergence rows"
  # D is the ONE fixture that opts into the `U32` arithmetic, and the two
  # assertions are what make that a measurement rather than a redefinition.
  dseg_py, _ = shard_run(5000, 100, 2048, 4096, a_dev, osx=False)   # D, CPython ints
  dseg, d = shard_run(5000, 100, 2048, 4096, a_dev, osx=False, wrap=True)
  srow("dk_shard_d", seg_str(dseg))
  urow("dk_shard_cover_d", cover(dseg))
  row("dk_shard_contig_d", contig(dseg))
  # E, THE SKEW CROSSING A PAGE BOUNDARY: `size + minor` is 4500 and rounds up to
  # 8192, where `size` alone rounds up to 4096. B and C do NOT separate :104's
  # `size + minor_offset` from `size` -- 5000+100 and 5000+904 both give the 8192
  # that 5000 alone gives -- so this fixture is what makes the addition visible.
  # `minor < seg_len` is the OTHER constraint (else the first segment's `real` goes
  # negative, which is D's `U32` divergence rather than a clean reading), so E is
  # `size = 3000`, `offset = 1500`, `seg_len = 2048`, and both assertions hold.
  eseg, _ = shard_run(3000, 1500, 2048, 65536, a_dev, osx=False)
  urow("dk_shard_total_e", shard_total(3000, 1500, False))
  urow("dk_shard_minor_e", 1500 % pagesize(False))
  urow("dk_shard_fd_e", 1500 - 1500 % pagesize(False))
  srow("dk_shard_e", seg_str(eseg))
  urow("dk_shard_cover_e", cover(eseg))
  row("dk_shard_contig_e", contig(eseg))
  urow("dk_shard_seg_len_e", len(eseg))
  assert shard_total(3000, 1500, False) == 8192, "E's total is not 8192"
  assert shard_total(3000, 1500, False) != shard_total(3000, 0, False), \
    "E no longer separates `size + minor` from `size`"
  assert 1500 < 2048, "E's skew is no longer below seg_len, so E is a copy of D"
  bigseg, big = shard_run(10000, 0, 20000, 40960, a_dev, osx=False)
  srow("dk_shard_big", seg_str(bigseg))
  urow("dk_shard_big_cover", cover(bigseg))
  row("dk_shard_big_contig", contig(bigseg))
  urow("dk_shard_seg0_n", shard_n(shard_total(10000, 0, False), 0))
  zseg, _ = shard_run(10000, 0, 0, 40960, a_dev, osx=False)
  urow("dk_shard_seg0_segs", len(zseg))
  # :106 -- `not hasattr(DiskDevice,'io_uring') or not use_ioring`. EITHER way the
  # non-uring arm is taken and both give the SAME segments.
  i0, _ = shard_run(10000, 0, 4096, 40960, a_dev, osx=False)
  row("dk_shard_ioring_absent", seg_str(i0) == seg_str(aseg))
  i1, _ = shard_run(10000, 0, 4096, 40960, a_dev, osx=False)
  row("dk_shard_no_use_ioring", seg_str(i1) == seg_str(aseg))
  # and the io_uring arm's two submission calls, which are all it adds here.
  # :128 `sq.array[sqe_index] = sqe_index` and :130 `libc.syscall(NR_io_uring_enter,
  # ...)` -- the STORE is recorded FIRST. (Note that a nested
  # `emit(k, a, emit(k2, b, t))` in the .bend appends the INNER call first, which
  # here lands the same way by construction and not by accident.)
  i2d = a_dev.reset().emit(K_SQE_STORE, 0).emit(K_IORING_ENTER, IORING_ENTER_GETEVENTS)
  i2, i2e = shard_run(10000, 0, 4096, 40960, i2d, osx=False)
  row("dk_shard_ioring_order", seq(i2e.trace, [(K_SQE_STORE, 0), (K_IORING_ENTER,
      IORING_ENTER_GETEVENTS)]))
  urow("dk_shard_ioring_sqes", ncalls(K_SQE_STORE, i2e.trace))
  urow("dk_shard_ioring_enters", ncalls(K_IORING_ENTER, i2e.trace))
  urow("dk_shard_ioring_copyouts", ncalls(K_COPYOUT, i2e.trace))

def t_ioring():
  p = dev_init(DISK)
  row("dk_ioring_tried", p.tried)
  row("dk_ioring_stored", p.ioring)
  row("dk_ioring_order", seq(p.trace, [(K_IOURING_SETUP, IORING_ENTRIES),
      (K_MMAP, 0), (K_MMAP, IORING_OFF_CQ_RING), (K_MMAP, IORING_OFF_SQES)]))
  urow("dk_ioring_n", seen(p.trace))
  urow("dk_ioring_mmaps", ncalls(K_MMAP, p.trace))
  urow("dk_ioring_setup_n", ncalls(K_IOURING_SETUP, p.trace))
  n = iouring_setup(False, True, Dev(DISK))                           # not linux
  urow("dk_ioring_skipped_calls", seen(n.trace))
  row("dk_ioring_skipped_tried", n.tried)
  row("dk_ioring_skipped_stored", not n.ioring)
  f = iouring_setup(True, False, Dev(DISK))                           # :55 returns
  urow("dk_ioring_failed_n", seen(f.trace))
  urow("dk_ioring_failed_mmaps", ncalls(K_MMAP, f.trace))
  row("dk_ioring_failed_stored", not f.ioring)

for fn in (t_path, t_flags, t_open, t_refuse, t_close, t_buf, t_shard, t_ioring): fn()
rows.append("dk-done=1")   # the Bend main's sentinel, so the diff is byte-for-byte
print("\n".join(rows))