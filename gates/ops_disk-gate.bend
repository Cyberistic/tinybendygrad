# gates/ops_disk-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_disk.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_disk.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as DV

def map_locked(osx: Bool) -> U32: Bool.pick(U32, osx, 0, P.MAP_LOCKED_LINUX())
def map_populate(osx: Bool) -> U32: Bool.pick(U32, osx, 0, P.MAP_POPULATE_LINUX())

# AN empty trace that keeps the device state, so a gate can read ONE step in
# isolation and use a WHOLE-trace comparison. This is `ops_webgpu.bend`'s
# `P.Tr.reset` and it is the ONLY way a `seq_eq` row can be written at all: every
# fixture in this file carries the four io_uring calls from `dev_init` in front of
# the step under test, so `P.seq_eq(P.Dev.tr(x), [...])` would be False for every
# correct step. `dk_close_exactly_two` and `dk_copyin_at_zero` are the rows that
# need it and they say so where they are used.
def dev_reset(d: P.Dev) -> P.Dev:
  match d:
    case P.Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:
      P.Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, P.Tr.of()}

# :29 -- `"/"+filename[4:].lstrip("/")`. The leading slash is UNCONDITIONAL, so
# "shm:" with nothing after it names "/" and not "". That is shm_open's convention
# (a POSIX name must start with a slash) and it is why `dk_shm_empty` is "/".
def dsk_shm_name(fn: String) -> String:
  String.concat(["/", P.dsk_lstrip(String.drop(fn, String.length(P.SHM_PREFIX())))])

# `Compiled.__init__` (device.py:397) reads the SECOND colon field, so a
# `disk:2:/tmp/x` names device 2. Nothing in `ops_disk.py` reads it and neither
# does this port; `dk_device_id` is the row that says so rather than leaving the
# field unconsidered.
def dsk_device_id(name: String) -> U32: DV.dev_id(name)

# :12 -- `def synchronize(self, timeout=None): pass`. It is the ONLY
# synchronisation a DiskDevice does and it does nothing, so it records nothing.
# `dk_sync_noop` is a LIST comparison rather than a count, so it is the claim
# "adding it changed nothing" and not the claim "there are four calls".
def dev_sync(d: P.Dev) -> P.Dev: d

def dev_init(name: String) -> P.Dev: P.dev_init.at(True{}, True{}, name)

def dev_reopen_msg(+size: U32, +d: P.Dev) -> String:
  String.concat(["can't reopen Disk tensor with larger size, opened with ",
                 Bool.pick(String, P.Dev.has_size(d), U32.show(P.Dev.size(d)), "None"),
                 ", tried to open with ", U32.show(size)])

# :76 -- `def __repr__(self): return f"<DiskBuffer size={self.size}
# offset={self.offset}>"`. USER-VISIBLE, and the one string in this file a caller
# sees, so the gate diffs it against CPython's f-string rather than against itself.
def db_repr(+b: P.Db) -> String:
  String.concat(["<DiskBuffer size=", U32.show(P.Db.size(b)),
                 " offset=", U32.show(P.Db.offset(b)), ">"])

# :78 -- `f"DiskBuffer wasn't opened: {self.device.device}"`. The device's OWN
# string, not the buffer's, which is the one place `_buf`'s message is not about
# the buffer.
def db_not_open_msg(b: P.Db) -> String:
  String.concat(["DiskBuffer wasn't opened: ", P.Db.name(b)])

# :84-86 -- `_alloc`: `self.dev._might_open(size)` and then the `BufferStorage`.
# `mv_address(opaque._buf())` is WALL 1, so `P.Rc.addr` is a 0, and `_buf()`'s assert
# fires here for the first time in a device's life.
def alloc_of(+size: U32, d: P.Dev) -> P.Rc:
  +e: P.Dev = P.dev_might_open(size, d)
  +b: P.Db = P.Db.of(e, size, 0)
  P.Rc{b, 0, P.DbB.dev(P.db_buf(b, e))}

# :88 -- `_free(self, storage, options): self.dev._might_close()`. The STORAGE is
# not read, which is fact A in the header and the reason this def takes a `P.Dev`
# and nothing else.
def alloc_free(d: P.Dev) -> P.Dev: P.dev_might_close(d)

# :89 -- `_as_buffer(self, src): return src._buf()`. The bare `_buf`, so it is the
# SAME assert and the SAME refusal as `_copyin`'s.
def alloc_as_buffer(b: P.Db, d: P.Dev) -> P.DbB: P.db_buf(b, d)

def alloc_copyin(b: P.Db, d: P.Dev) -> P.Dev: P.alloc_copyin.put(P.db_buf(b, d))

def alloc_copyout(chunks: List<&2, U32>, b: P.Db, +d: P.Dev) -> P.Roff:
  P.alloc_copyout.at(Bool.and(P.Dev.osx(d), P.Dev.has_fd(d)), chunks, b, d)

# :144 -- `_offset(self, buf, size, offset): return DiskBuffer(buf.device, size,
# offset)`. A NEW buffer on the SAME device: `size` and `offset` are the caller's,
# `offset` does NOT ACCUMULATE (that is `Buffer.view`, device.py:252, which this is
# not) and the device's refcount does not move. `dk_offset_off` is the row that pins
# the non-accumulation, against a buffer that already has offset 4.
def alloc_offset(size: U32, off: U32, b: P.Db) -> P.Db: P.Db.of(P.Db.d(b), size, off)

# the predicate :106 computes, in one place, because `a match may not scrutinise a
# call` -- so `shard.at` above takes the conjunction as a parameter and this is the
# only place the two flags are ANDed.
def shard.pick(ioring: Bool, use_ioring: Bool, seg_len: U32, size: U32, off: U32,
               devsize: U32, +osx: Bool, +d: P.Dev) -> P.ShOut:
  P.shard.at(Bool.and(ioring, use_ioring), seg_len, size, off, devsize, osx, d)


# --- THE GATE ROWS ------------------------------------------------------
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

def ncalls(k: U32, t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
def seen(t: P.Tr) -> U32: U32.from_nat(List.length(&2, P.Call, P.Tr.calls(t)))
def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)

def u32_is_zero(v: U32) -> Bool: U32.is_zero(v)
def u32_add(a: U32, b: U32) -> U32: U32.add(a, b)

# the WHOLE trace as ONE string, `k,arg,k,arg,...`. This is the recorded "put all
# the facts in one string" rule applied to a trace, and `dk_open_file_trace` is the
# row: every tag AND every argument of every call in one diffable value.
def trace_str(t: P.Tr) -> String: ujoin(P.Tr.pairs(P.Tr.calls(t)))

# the FIRST arg of the calls with tag `k`, as a `U32`, for a row that wants the
# value rather than the count. `dk_two_free_unmap_size` is the row: it is the
# evidence that `_free` reads nothing from its storage.
def first_u32(xs: List<&2, U32>, d: U32) -> U32:
  match xs:
    case Nil{}: d
    case x <> t: first_u32(t, x)

def arg_of(k: U32, t: P.Tr) -> U32: first_u32(P.Tr.args(k, P.Tr.calls(t)), 0)

# one segment as `off/read/cin/moff/real` -- ALL FIVE in one string, because four
# separate rows let a fixture drop one, and the recorded "put all four facts in one
# string" rule is the fix.
def seg_str(+s: P.Seg) -> String:
  ujoin([P.Seg.off(s), P.Seg.rd(s), P.Seg.cin(s), P.Seg.moff(s), P.Seg.real(s)])

def shard_str.go(xs: List<&2, P.Seg>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +s <> t: shard_str.go(t, List.append(&2, String, acc, [seg_str(s)]))

def shard_str(xs: List<&2, P.Seg>) -> String:
  String.join(shard_str.go(xs, Nil{}), " ")

# THE RESULT ROW, part one: the `real_copy_size`s must sum to exactly `size`.
def shard_cover.go(xs: List<&2, P.Seg>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case s <> t: shard_cover.go(t, U32.add(acc, P.Seg.real(s)))

def shard_cover(xs: List<&2, P.Seg>) -> U32: shard_cover.go(xs, 0)

# THE RESULT ROW, part two: every `copied_in` must be the running sum of the
# PREVIOUS `real_copy_size`s, so the segments TILE the destination.
def shard_contig.go(xs: List<&2, P.Seg>, +run: U32) -> Bool:
  match xs:
    case Nil{}: True{}
    case +s <> t:
      Bool.and(U32.is_eq(P.Seg.cin(s), run),
               shard_contig.go(t, U32.add(run, P.Seg.real(s))))

def shard_contig(xs: List<&2, P.Seg>) -> Bool: shard_contig.go(xs, 0)

# FIXTURES. One device per host fact, and each `fx_*` reads its input once.
def DISK() -> String: "disk:/tmp/dk.bin"
def DISK_SHM() -> String: "disk:shm:dk"
def DISK_DEV() -> String: "disk:/dev/sda"

def fx_plain() -> P.Dev: dev_init(DISK())
def fx_shm() -> P.Dev: dev_init(DISK_SHM())
def fx_osx() -> P.Dev:
  P.dev_cfg(True{}, False{}, P.open_direct(True{}, False{}), False{}, False{}, 0,
          fx_plain())
def fx_nomadv() -> P.Dev:
  P.dev_cfg(False{}, False{}, P.open_direct(False{}, True{}), False{}, False{}, 0,
          fx_plain())
def fx_blockdev() -> P.Dev:
  P.dev_cfg(False{}, False{}, P.open_direct(False{}, True{}), True{}, True{}, 0,
          dev_init(DISK_DEV()))
def fx_longfile() -> P.Dev:
  P.dev_cfg(False{}, False{}, P.open_direct(False{}, True{}), False{}, True{}, 65536,
          fx_plain())
def fx_noioring() -> P.Dev: P.dev_ioring_setup(False{}, True{}, P.Dev.of(DISK()))
def fx_ioring_fail() -> P.Dev: P.dev_ioring_setup(True{}, False{}, P.Dev.of(DISK()))

# the opened file device at `size`, the opened shm device at `size`.
def fx_open(size: U32) -> P.Dev: P.dev_might_open(size, fx_plain())
def fx_shm_open(size: U32) -> P.Dev: P.dev_might_open(size, fx_shm())

# THE shm device ON macOS. THE second fixture :92 NEEDS and did not have. :92 is
# `if OSX and self.dev.fd is not None`, and the drop-the-`has_fd` conjunct mutation
# moved NOTHING while `fx_shm_open` was the only shm fixture -- because that fixture
# is a LINUX device, so `P.Dev.osx` is False and the first conjunct already decides the
# arm. The mutation was invisible because the fixture could not reach the conjunct,
# not because the conjunct is redundant. THIS FIXTURE REACHES IT, and
# `dk_copyout_shm_osx_*` below is the pair that kills the mutation.
def fx_shm_osx() -> P.Dev: P.dev_cfg(True{}, False{}, 0, False{}, False{}, 0, fx_shm())
def fx_shm_osx_open(size: U32) -> P.Dev: P.dev_might_open(size, fx_shm_osx())

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
#      THE two numbers are chosen, NOT found. `minor` must be BELOW `seg_len` or the
#      first segment's `real = min(seg_len - minor, size)` goes negative -- which is
#      the `U32` divergence `dk_shard_raw_third_d` records, and an E that tripped it
#      would make E a second copy of D instead of a clean reading of :104. And `size`
#      must be big enough that `size + minor` crosses 4096. `1500 < 2048` and
#      `3000 + 1500 > 4096` are exactly those two constraints, and E is the only
#      fixture satisfying both.
def shard_sh(+size: U32, +off: U32, seg: U32, devsize: U32, +osx: Bool) -> P.Sh:
  P.Sh{size, seg, P.shard_total(size, off, osx), P.shard_fd_off(off, osx), devsize}

def SH_A(osx: Bool) -> P.Sh: shard_sh(10000, 0, 4096, 40960, osx)
def SH_B(osx: Bool) -> P.Sh: shard_sh(5000, 100, 2048, 65536, osx)
def SH_C(osx: Bool) -> P.Sh: shard_sh(5000, 5000, 2048, 65536, osx)
def SH_D(osx: Bool) -> P.Sh: shard_sh(5000, 100, 2048, 4096, osx)
def SH_E(osx: Bool) -> P.Sh: shard_sh(3000, 1500, 2048, 65536, osx)

def dk_run_a(d: P.Dev, osx: Bool) -> P.ShOut: P.shard_at(4096, 10000, 0, 40960, osx, d)
def dk_run_b(d: P.Dev, osx: Bool) -> P.ShOut: P.shard_at(2048, 5000, 100, 65536, osx, d)
def dk_run_c(d: P.Dev, osx: Bool) -> P.ShOut: P.shard_at(2048, 5000, 5000, 65536, osx, d)
def dk_run_d(d: P.Dev, osx: Bool) -> P.ShOut: P.shard_at(2048, 5000, 100, 4096, osx, d)
def dk_run_e(d: P.Dev, osx: Bool) -> P.ShOut: P.shard_at(2048, 3000, 1500, 65536, osx, d)

# ===========================================================================
# THE GATE. Every expectation comes from `ops_disk.py`'s own text, from a module it
# imports, or from arithmetic over the two fixture lines above. The numeric rows
# PRINT their value, so a wrong one is diagnosable from the output alone.
# ===========================================================================

# --- 1: the naming table, :26 and :28, both directions ----------------------
def t_path() -> IO(Unit):
  do IO<Unit>:
    srow("dk_file_plain", P.dsk_filename(DISK()))
    srow("dk_file_bare", P.dsk_filename(P.DISK_PREFIX()))
    srow("dk_file_rel", P.dsk_filename("disk:relative.bin"))
    srow("dk_file_dev", P.dsk_filename(DISK_DEV()))
    srow("dk_file_shm", P.dsk_filename(DISK_SHM()))
    srow("dk_shm_plain", dsk_shm_name(P.dsk_filename(DISK_SHM())))
    srow("dk_shm_empty", dsk_shm_name(P.dsk_filename("disk:shm:")))
    # THE finding, AND why these are boolean rows and not five strings.
    # `filename[4:].lstrip("/")` makes the NUMBER OF LEADING SLASHES IRRELEVANT, so
    # `disk:shm:dk`, `disk:shm:/dk` and `disk:shm://dk` all name "/dk", and
    # `disk:shm:` and `disk:shm://///` both name "/". Five string rows would be two
    # CONSTANT COLUMNS and no mutation could move either; five BOOLEAN rows are five
    # independent claims about `lstrip` and `String.drop`, and a strip that stopped
    # at the first slash dies here.
    row("dk_shm_slashes_eq_plain", String.eq(dsk_shm_name(P.dsk_filename("disk:shm://dk")),
                                             "/dk"))
    row("dk_shm_abs_eq_plain", String.eq(dsk_shm_name(P.dsk_filename("disk:shm:/dk")),
                                         "/dk"))
    row("dk_shm_allslash_eq_empty", String.eq(dsk_shm_name(P.dsk_filename("disk:shm://///")),
                                              "/"))
    row("dk_shm_trailing_kept", String.eq(dsk_shm_name(P.dsk_filename("disk:shm:a/b")),
                                          "/a/b"))
    # the REVERSE direction: which of these paths is a shm path at all.
    row("dk_is_shm_plain", P.dev_is_shm(DISK(), False{}))
    row("dk_is_shm_shm", P.dev_is_shm(DISK_SHM(), False{}))
    row("dk_is_shm_win", P.dev_is_shm(DISK_SHM(), True{}))
    row("dk_is_shm_prefix_only", P.dev_is_shm(P.DISK_PREFIX(), False{}))
    urow("dk_device_id", dsk_device_id("disk:2:/tmp/x"))

# --- 2: the flags, :33, :34, :39, :81 and :103, and the io_uring constants ---
# EVERY host fact is printed in both cells, and the `_linux` rows are the ones the
# rest of the gate uses. Two cells for a two-cell fact is the whole defence against
# a port that is quietly Linux-only: `mmap.PAGESIZE` alone changes every shard row,
# and `O_CREAT` alone changes every trace argument in the open.
def t_flags() -> IO(Unit):
  do IO<Unit>:
    urow("dk_locked_linux", map_locked(False{}))
    urow("dk_locked_osx", map_locked(True{}))
    urow("dk_populate_linux", map_populate(False{}))
    urow("dk_populate_osx", map_populate(True{}))
    urow("dk_mem_flags_linux", P.mem_flags(False{}))
    urow("dk_mem_flags_osx", P.mem_flags(True{}))
    urow("dk_direct_yes", P.open_direct(False{}, True{}))
    urow("dk_direct_no", P.open_direct(False{}, False{}))
    urow("dk_direct_yes_mac", P.open_direct(True{}, True{}))
    urow("dk_direct_no_mac", P.open_direct(True{}, False{}))
    urow("dk_open_plain", P.open_flags(False{}, 0))
    urow("dk_open_odirect", P.open_flags(False{}, P.open_direct(False{}, True{})))
    urow("dk_open_plain_mac", P.open_flags(True{}, 0))
    urow("dk_open_odirect_mac", P.open_flags(True{}, P.open_direct(True{}, True{})))
    row("dk_open_has_rdwr", U32.is_eq(U32.and(P.open_flags(False{}, 0), P.O_RDWR()),
                                      P.O_RDWR()))
    row("dk_open_has_creat", U32.is_eq(U32.and(P.open_flags(False{}, 0), P.O_CREAT_LINUX()),
                                       P.O_CREAT_LINUX()))
    row("dk_open_has_creat_mac", U32.is_eq(U32.and(P.open_flags(True{}, 0), P.O_CREAT_MACOS()),
                                           P.O_CREAT_MACOS()))
    row("dk_open_odirect_extra",
        U32.is_gt(P.open_flags(False{}, P.open_direct(False{}, True{})),
                  P.open_flags(False{}, 0)))
    row("dk_open_odirect_mac_same",
        U32.is_eq(P.open_flags(True{}, P.open_direct(True{}, True{})), P.open_flags(True{}, 0)))
    urow("dk_pagesize", P.pagesize(False{}))
    urow("dk_pagesize_mac", P.pagesize(True{}))
    urow("dk_shm_mode", P.SHM_MODE())
    urow("dk_madv_hugepage", P.madv_hp(False{}))
    urow("dk_madv_hugepage_mac", P.madv_hp(True{}))
    urow("dk_ioring_nr_setup", P.NR_IO_URING_SETUP())
    urow("dk_ioring_nr_enter", P.NR_IO_URING_ENTER())
    urow("dk_ioring_entries", P.IORING_ENTRIES())
    urow("dk_ioring_off_cq", P.IORING_OFF_CQ_RING())
    urow("dk_ioring_off_sqes", P.IORING_OFF_SQES())
    urow("dk_ioring_op_read", P.IORING_OP_READ())
    urow("dk_ioring_getevents", P.IORING_ENTER_GETEVENTS())
    urow("dk_ioring_cqe", P.SIZEOF_CQE())
    urow("dk_ioring_sqe", P.SIZEOF_SQE())
    urow("dk_alloc_lru", Bool.to_u32(P.ALLOC_LRU()))

# --- 3: the open, :29-40, in order -------------------------------------------
# THE two order rows reset before the open and compare the whole trace. A reset
# device has `next == 0`, so the descriptor both branches mint is 0 -- which is
# why `P.Call{P.K_CLOSE(), 0}` below is the seam's ANSWER and not a magic number, and
# why `dk_open_file_fd` (4, on the unreset fixture) is a separate row with a
# separate referent.
def t_open() -> IO(Unit):
  do IO<Unit>:
    +p : P.Dev <- IO.pure(P.Dev, fx_open(10000))
    +pt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(p))
    +s : P.Dev <- IO.pure(P.Dev, fx_shm_open(10000))
    +st : P.Tr <- IO.pure(P.Tr, P.Dev.tr(s))
    +p0 : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, dev_reset(fx_plain())))
    +p0t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(p0))
    +s0 : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, dev_reset(fx_shm())))
    +s0t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(s0))
    # THE MATCHER PINS ITSELF FIRST. Seven rows below are order claims and none of
    # them means anything if `P.Tr.has` answers True to everything.
    row("dk_has_rejects_reverse", Bool.not(seq(pt, [P.Call{P.K_MMAP(), 10000},
      P.Call{P.K_FTRUNCATE(), 10000}])))
    row("dk_has_rejects_absent", Bool.not(seq(pt, [P.Call{P.K_COPYOUT(), 999}])))
    row("dk_open_file_order", P.seq_eq(p0t,
      [P.Call{P.K_OPEN_DIRECT(), 16450}, P.Call{P.K_OPEN(), 66}, P.Call{P.K_FSTAT(), 0},
       P.Call{P.K_FTRUNCATE(), 10000}, P.Call{P.K_MMAP(), 10000}, P.Call{P.K_MADVISE(), 14}]))
    # :38-39 RUNS ON BOTH BRANCHES -- `self.mem` is set at :30 as well as :36 --
    # so the shm branch is FOUR calls and not three.
    row("dk_open_shm_order", P.seq_eq(s0t, [P.Call{P.K_SHM_OPEN(), 384},
      P.Call{P.K_MMAP_SHM(), 40961}, P.Call{P.K_CLOSE(), 0}, P.Call{P.K_MADVISE(), 14}]))
    # THE WHOLE TRACE IN ONE STRING, tag and argument for every call: the four
    # io_uring calls `dev_init` made, then the five of the file branch, then the
    # madvise. This is the row that says :33 asked for O_DIRECT, :34 retried
    # without it, :35 fstat'd before it truncated, and :39 ran last.
    srow("dk_open_file_trace", trace_str(pt))
    urow("dk_open_file_fstat", ncalls(P.K_FSTAT(), pt))
    urow("dk_open_file_ftrunc", ncalls(P.K_FTRUNCATE(), pt))
    # BOTH attempts, and :34's flags: the fallback drops O_DIRECT and the trace keeps
    # the ask. This is the row that says the try/except is not a branch.
    urow("dk_open_direct_attempts", ncalls(P.K_OPEN_DIRECT(), pt))
    urow("dk_open_fallback_attempts", ncalls(P.K_OPEN(), pt))
    urow("dk_open_total_attempts", U32.add(ncalls(P.K_OPEN_DIRECT(), pt),
                                           ncalls(P.K_OPEN(), pt)))
    row("dk_shm_no_open_attempt", u32_is_zero(ncalls(P.K_OPEN_DIRECT(), st)))
    srow("dk_open_shm_trace", trace_str(st))
    urow("dk_open_shm_n", seen(st))
    row("dk_shm_fd_none", Bool.not(P.Dev.has_fd(s)))
    urow("dk_shm_size", P.Dev.size(s))
    row("dk_shm_has_mem", P.Dev.has_mem(s))
    row("dk_open_file_has_fd", P.Dev.has_fd(p))
    # the descriptor the seam would hand back: `P.Tr.here` is read BEFORE the open's
    # emit, and the four io_uring calls minted none, so it is 0 on both branches.
    # A row so that `dk_open_shm_order`'s `CLOSE, 0` has a referent.
    urow("dk_open_file_fd", P.Dev.fd(p))
    urow("dk_shm_fd_is_none", Bool.to_u32(P.Dev.has_fd(s)))
    # the madvise, and the device with no madvise.
    row("dk_madvise_order", seq(pt, [P.Call{P.K_MMAP(), 10000},
      P.Call{P.K_MADVISE(), 14}]))
    urow("dk_madvise_n", ncalls(P.K_MADVISE(), pt))
    +n : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, fx_nomadv()))
    urow("dk_nomadv_n", ncalls(P.K_MADVISE(), P.Dev.tr(n)))
    # a block device and a file already long enough: :35's two other cells.
    +b : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, fx_blockdev()))
    +bt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(b))
    +g : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, fx_longfile()))
    +gt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(g))
    urow("dk_blockdev_fstat", ncalls(P.K_FSTAT(), bt))
    urow("dk_blockdev_ftrunc", ncalls(P.K_FTRUNCATE(), bt))
    urow("dk_longfile_fstat", ncalls(P.K_FSTAT(), gt))
    urow("dk_longfile_ftrunc", ncalls(P.K_FTRUNCATE(), gt))
    # the device state after a successful open, and :12's no-op.
    urow("dk_open_refcount", P.Dev.refcount(p))
    urow("dk_open_size", P.Dev.size(p))
    row("dk_open_has_size", P.Dev.has_size(p))
    row("dk_open_has_mem", P.Dev.has_mem(p))
    row("dk_sync_noop", P.u32_list_eq(P.Tr.pairs(P.Tr.calls(P.Dev.tr(dev_sync(fx_plain())))),
                                    P.Tr.pairs(P.Tr.calls(P.Dev.tr(fx_plain())))))

# --- 4: the fast path, the assert and the truncation, :22-25 ----------------
# THE claim in this section is the truncation, so the rows are TRACE equalities and
# not counts: a refusal shows up as the trace being IDENTICAL before and after the
# offending call. A count row would read the same number either way and prove
# nothing -- which is the recorded "an `eq_u(n, 0)` row is satisfied by any
# wrong-but-present answer" trap.
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +w : P.Dev <- IO.pure(P.Dev, P.dev_might_open(10000, fx_open(10000)))
    +wt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(w))
    srow("dk_warm_trace", trace_str(wt))
    urow("dk_warm_refcount", P.Dev.refcount(w))
    urow("dk_warm_size", P.Dev.size(w))
    # the assert REFUSES: `refused` latches and NO LATER EMIT RECORDS ANYTHING.
    +g : P.Dev <- IO.pure(P.Dev, P.dev_might_open(20000, w))
    +gt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(g))
    row("dk_grow_refused", P.Tr.refused(gt))
    row("dk_grow_trace_unchanged", P.u32_list_eq(P.Tr.pairs(P.Tr.calls(gt)), P.Tr.pairs(P.Tr.calls(wt))))
    # and the assert is BEFORE the refcount bump, so the count does not move either.
    urow("dk_grow_refcount", P.Dev.refcount(g))
    urow("dk_grow_size", P.Dev.size(g))
    row("dk_grow_has_mem_unchanged", P.Dev.has_mem(g))
    srow("dk_grow_msg", dev_reopen_msg(20000, w))
    srow("dk_fresh_msg", dev_reopen_msg(10000, fx_plain()))
    # SHRINK is legal and is the SAME fast path: same trace, refcount 2, and the
    # recorded `size` STAYS at the first one rather than dropping to 4000.
    +k : P.Dev <- IO.pure(P.Dev, P.dev_might_open(4000, w))
    +kt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(k))
    row("dk_shrink_not_refused", Bool.not(P.Tr.refused(kt)))
    row("dk_shrink_trace_unchanged", P.u32_list_eq(P.Tr.pairs(P.Tr.calls(kt)), P.Tr.pairs(P.Tr.calls(wt))))
    urow("dk_shrink_refcount", P.Dev.refcount(k))
    urow("dk_shrink_size", P.Dev.size(k))
    # the predicate itself, on both sides: a fresh device is not open, an opened one
    # is, and a CLOSED one is not even though it still `hasattr(self,"mem")`.
    row("dk_is_open_fresh", P.dev_is_open(fx_plain()))
    row("dk_is_open_after", P.dev_is_open(w))

# --- 5: the close, :41-49, and fact A (the refcount is the DEVICE's) --------
# EVERY `seq_eq` HERE resets *BEFORE* THE step and reads *AFTER*. The fixture
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
    +o : P.Dev <- IO.pure(P.Dev, dev_reset(fx_open(10000)))
    +c : P.Dev <- IO.pure(P.Dev, alloc_free(o))
    +ct : P.Tr <- IO.pure(P.Tr, P.Dev.tr(c))
    row("dk_close_exactly_two", P.seq_eq(ct,
      [P.Call{P.K_CLOSE(), P.Dev.fd(c)}, P.Call{P.K_MUNMAP(), 10000}]))
    urow("dk_close_n", u32_add(ncalls(P.K_CLOSE(), ct), ncalls(P.K_MUNMAP(), ct)))
    urow("dk_close_refcount", P.Dev.refcount(c))
    row("dk_close_size_none", Bool.not(P.Dev.has_size(c)))
    # :49 clears ONLY `size`, so `mem` and `fd` SURVIVE the close. This is why :23
    # needs two conjuncts and it is fact B in the header.
    row("dk_close_keeps_mem", P.Dev.has_mem(c))
    row("dk_close_keeps_fd", P.Dev.has_fd(c))
    row("dk_warm_needs_both", Bool.not(P.dev_is_open(c)))
    # the shm device closes by MUNMAP alone, and `P.Dev.fd(c)` is 0 there because
    # :17 never set it -- so the row is also the evidence that the shm branch's
    # :31 close is a DIFFERENT call from :44's.
    +so : P.Dev <- IO.pure(P.Dev, dev_reset(fx_shm_open(10000)))
    +sc : P.Dev <- IO.pure(P.Dev, alloc_free(so))
    +sct : P.Tr <- IO.pure(P.Tr, P.Dev.tr(sc))
    urow("dk_close_shm_closes", ncalls(P.K_CLOSE(), sct))
    urow("dk_close_shm_unmaps", ncalls(P.K_MUNMAP(), sct))
    row("dk_close_shm_only_unmap", P.seq_eq(sct, [P.Call{P.K_MUNMAP(), 10000}]))
    # FACT A. Two allocs of DIFFERENT sizes on ONE device: the second is legal (it
    # is smaller), the refcount is 2, ONE free does NOTHING, and the SECOND free
    # unmaps the FIRST buffer's size rather than the second's. The unmap argument is
    # the sharpest evidence that `_free` reads nothing from its storage -- 40960 when
    # the buffer freed last was 4096.
    +a1 : P.Rc <- IO.pure(P.Rc, alloc_of(40960, fx_plain()))
    +a2 : P.Rc <- IO.pure(P.Rc, alloc_of(4096, P.Rc.d(a1)))
    urow("dk_two_alloc_refcount", P.Dev.refcount(P.Rc.d(a2)))
    +f1 : P.Dev <- IO.pure(P.Dev, alloc_free(P.Rc.d(a2)))
    +f1t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(f1))
    row("dk_one_free_trace_unchanged",
        P.u32_list_eq(P.Tr.pairs(P.Tr.calls(f1t)), P.Tr.pairs(P.Tr.calls(P.Dev.tr(P.Rc.d(a2))))))
    urow("dk_one_free_refcount", P.Dev.refcount(f1))
    # THE reset is here and not earlier: the first free must be free to record
    # NOTHING, so the trace it leaves has to be the one the second free adds to.
    +f1r : P.Dev <- IO.pure(P.Dev, dev_reset(f1))
    +f2 : P.Dev <- IO.pure(P.Dev, alloc_free(f1r))
    +f2t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(f2))
    row("dk_two_free_exactly_two", P.seq_eq(f2t,
      [P.Call{P.K_CLOSE(), P.Dev.fd(f2)}, P.Call{P.K_MUNMAP(), 40960}]))
    urow("dk_two_free_unmap_size", arg_of(P.K_MUNMAP(), f2t))
    urow("dk_last_alloc_size", P.Db.size(P.Rc.b(a2)))
    # THE UNDERFLOW. Two frees past the count walk it away from zero and the wrap is
    # a bit pattern, so it is in the ROW NAME. The call count does NOT move for the
    # second and third free: the crossing happens once.
    +u1 : P.Dev <- IO.pure(P.Dev, alloc_free(c))
    +u2 : P.Dev <- IO.pure(P.Dev, alloc_free(u1))
    +u2t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(u2))
    urow("dk_free_underflow_4294967294", P.Dev.refcount(u2))
    urow("dk_free_underflow_calls", u32_add(ncalls(P.K_CLOSE(), u2t),
                                           ncalls(P.K_MUNMAP(), u2t)))
    row("dk_free_underflow_refused", P.Tr.refused(u2t))

# --- 6: the buffer, the window and the transfers, :73-99 and :144 -----------
# THE ALLOC FIXTURE IS A COLD DEVICE (`fx_plain()`, not an opened one), so
# `_alloc`'s `_might_open` takes the COLD path and the refcount really is 1. An
# already-open fixture would take the WARM path, add no call, and leave the refcount
# at 2 -- which is why `fx_plain()` and not `fx_open(...)` is the argument here.
def t_buf() -> IO(Unit):
  do IO<Unit>:
    +r : P.Rc <- IO.pure(P.Rc, alloc_of(10, fx_plain()))
    +rd : P.Dev <- IO.pure(P.Dev, P.Rc.d(r))
    srow("dk_repr", db_repr(P.Rc.b(r)))
    srow("dk_repr_zero", db_repr(alloc_offset(10, 0, P.Rc.b(r))))
    urow("dk_alloc_addr", P.Rc.addr(r))
    urow("dk_alloc_size", P.Db.size(P.Rc.b(r)))
    urow("dk_alloc_offset", P.Db.offset(P.Rc.b(r)))
    urow("dk_win_lo", P.Win.lo(P.db_window(P.Rc.b(r))))
    urow("dk_win_hi", P.Win.hi(P.db_window(P.Rc.b(r))))
    urow("dk_alloc_refcount", P.Dev.refcount(rd))
    # `_copyin`'s slice is `[:]`, so the bytes land at ZERO of the window, not at
    # `offset`. `dk_copyin_at_zero` is the row and it is the only thing that says so,
    # and it is a WHOLE-trace comparison -- so the device is reset BEFORE the copyin
    # and the copyin's own call is the entire trace.
    +v : P.Db <- IO.pure(P.Db, alloc_offset(10, 4, P.Rc.b(r)))
    +cir : P.Dev <- IO.pure(P.Dev, dev_reset(rd))
    +ci : P.Dev <- IO.pure(P.Dev, alloc_copyin(v, cir))
    +cit : P.Tr <- IO.pure(P.Tr, P.Dev.tr(ci))
    row("dk_copyin_at_zero", P.seq_eq(cit, [P.Call{P.K_COPYIN(), 10}]))
    # `_copyout`'s non-OSX arm, on the same offset-4 buffer: the WINDOW's size, again
    # not the offset. A different tag from COPYIN on the same fixture, which is what
    # separates the two rows.
    +cor : P.Roff <- IO.pure(P.Roff, alloc_copyout(Nil{}, v, dev_reset(ci)))
    +cot : P.Tr <- IO.pure(P.Tr, P.Dev.tr(P.Roff.dev(cor)))
    row("dk_copyout_at_zero", P.seq_eq(cot, [P.Call{P.K_COPYOUT(), 10}]))
    # its OSX arm: open, seek to the buffer's offset, one readinto per chunk, and a
    # `with` exit that does NOT close. The whole trace, so the fd and the exit are in
    # the same string as the seeks.
    +oo : P.Dev <- IO.pure(P.Dev, dev_reset(P.dev_might_open(10000, fx_osx())))
    +ro : P.Roff <- IO.pure(P.Roff, alloc_copyout([10, 12, 5], v, oo))
    +rot : P.Tr <- IO.pure(P.Tr, P.Dev.tr(P.Roff.dev(ro)))
    # `shm` AND `OSX`, which `fx_osx` above is not and `fx_shm_open` below is not.
    # THE RESET IS BEFORE THE COPYOUT, so the whole-trace comparison sees the
    # copyout's own call and nothing else -- `dev_reset` applied to the RESULT would
    # delete the call under test, which is the mistake `dk_close_exactly_two` records.
    +sdo : P.Dev <- IO.pure(P.Dev, dev_reset(fx_shm_osx_open(10000)))
    +sro : P.Roff <- IO.pure(P.Roff, alloc_copyout([10], P.Db.of(sdo, 10, 0), sdo))
    +sdot : P.Tr <- IO.pure(P.Tr, P.Dev.tr(P.Roff.dev(sro)))
    row("dk_copyout_osx_order", P.seq_eq(rot, [P.Call{P.K_FILEIO(), P.Dev.fd(P.Roff.dev(ro))},
      P.Call{P.K_SEEK(), 4}, P.Call{P.K_READINTO(), 0}, P.Call{P.K_READINTO(), 10},
      P.Call{P.K_READINTO(), 22}, P.Call{P.K_FILEIO_CLOSE(), 0}]))
    srow("dk_copyout_osx_trace", trace_str(rot))
    # `bytes_read` is each read's DESTINATION, and these are the running sums.
    srow("dk_copyout_osx_offs", ujoin(P.Roff.offs(ro)))
    urow("dk_copyout_osx_reads", ncalls(P.K_READINTO(), rot))
    # :89 -- `_as_buffer(self, src): return src._buf()`. It records NOTHING, because
    # `_buf` takes a slice and not a syscall, and it answers the SAME window. Two rows:
    # the window, and the absence of a call. Without the second, a port that routed
    # `_as_buffer` through `_copyin` would print the right window and nothing else
    # would say so.
    +ab : P.DbB <- IO.pure(P.DbB, alloc_as_buffer(v, ci))
    urow("dk_as_buffer_lo", P.Win.lo(P.DbB.win(ab)))
    urow("dk_as_buffer_size", P.Win.size(P.DbB.win(ab)))
    row("dk_as_buffer_no_call",
        P.u32_list_eq(P.Tr.pairs(P.Tr.calls(P.Dev.tr(P.DbB.dev(ab)))),
                    P.Tr.pairs(P.Tr.calls(cit))))
    # THE shm arm of :92, and it is the only row in the file that sees it: a
    # `disk:shm:` device has `self.fd` None, so OSX does NOT move it to FileIO.
    #
    # TWO FIXTURES, NOT ONE, and the second is the one with teeth. On a LINUX shm
    # device `P.Dev.osx` is False, so :92's FIRST conjunct already picks the posix arm
    # and the SECOND conjunct is never read -- the row pair below cannot see a port
    # that drops it. `fx_shm_osx_open` is `shm` AND `OSX`, which is the only
    # combination where `self.dev.fd is not None` is the deciding question, and
    # `dk_copyout_shm_osx_fileio` is the row that dies when the conjunct goes.
    +sd : P.Dev <- IO.pure(P.Dev, fx_shm_open(10000))
    +sr : P.Roff <- IO.pure(P.Roff, alloc_copyout([10], P.Db.of(sd, 10, 0), sd))
    +srt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(P.Roff.dev(sr)))
    urow("dk_copyout_shm_fileio", ncalls(P.K_FILEIO(), srt))
    urow("dk_copyout_shm_copyout", ncalls(P.K_COPYOUT(), srt))
    row("dk_copyout_shm_osx_has_no_fd", Bool.not(P.Dev.has_fd(sdo)))
    row("dk_copyout_shm_osx_is_osx", P.Dev.osx(sdo))
    row("dk_copyout_shm_osx_posix", P.seq_eq(sdot, [P.Call{P.K_COPYOUT(), 10}]))
    urow("dk_copyout_shm_osx_fileio", ncalls(P.K_FILEIO(), sdot))
    # and the mirror: a macOS FILE device has an fd, so the FileIO arm IS taken.
    row("dk_copyout_osx_file_has_fd", P.Dev.has_fd(oo))
    # `_offset` does NOT accumulate: a buffer already at 4 moves to 8, and the row
    # beside it names the number an accumulating `view` WOULD have given. The third
    # row says the device is the SAME one, which is the other half of :144.
    +w : P.Db <- IO.pure(P.Db, alloc_offset(20, 8, P.Rc.b(r)))
    urow("dk_offset_size", P.Db.size(w))
    urow("dk_offset_off", P.Db.offset(w))
    urow("dk_offset_accumulated_would_be", U32.add(P.Db.offset(P.Rc.b(r)), 8))
    row("dk_offset_same_device", String.eq(P.Dev.name(P.Db.d(w)), P.Dev.name(rd)))
    srow("dk_not_open_msg", db_not_open_msg(P.Db.of(fx_plain(), 10, 0)))
    # a buffer over a device with no mapping REFUSES, and that is the second assert
    # in the file. :78's message is gated above and the REFUSAL here.
    +u : P.Db <- IO.pure(P.Db, P.Db.of(fx_plain(), 10, 0))
    +ud : P.Dev <- IO.pure(P.Dev, P.DbB.dev(P.db_buf(u, fx_plain())))
    row("dk_buf_refused", P.Tr.refused(P.Dev.tr(ud)))
    urow("dk_buf_refused_calls", seen(P.Dev.tr(ud)))

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
    urow("dk_shard_total_a", P.Sh.total(SH_A(False{})))
    urow("dk_shard_fd_a", P.Sh.fd_off(SH_A(False{})))
    urow("dk_shard_minor_a", P.shard_minor(0, False{}))
    urow("dk_shard_n_formula_a", P.shard_n(P.Sh.total(SH_A(False{})), P.Sh.seg(SH_A(False{}))))
    +a : P.ShOut <- IO.pure(P.ShOut, dk_run_a(fx_plain(), False{}))
    srow("dk_shard_a", shard_str(P.ShOut.segs(a)))
    urow("dk_shard_cover_a", shard_cover(P.ShOut.segs(a)))
    row("dk_shard_contig_a", shard_contig(P.ShOut.segs(a)))
    urow("dk_shard_copyouts_a", ncalls(P.K_COPYOUT(), P.Dev.tr(P.ShOut.d(a))))
    # the FORMULA's count and the FOLD's length are two independent transcriptions
    # and a mutation to either one moves exactly one of them.
    urow("dk_shard_seg_len_a", U32.from_nat(List.length(&2, P.Seg, P.ShOut.segs(a))))
    # THE PAGE SIZE IS NOT CONSTANT. `dk_shard_total_a` is `round_up(10000, 4096)`
    # on the linux cell and `round_up(10000, 16384)` on the macOS one, so a port that
    # hardcoded `PAGESIZE` would print 12288 here and 16384 there and agree with
    # itself. These three rows are the pair that makes `pagesize` falsifiable: the
    # TOTAL differs, the SEGMENT COUNT differs, and the LAST segment's `cin` is
    # 8192 on one cell and 12288 on the other.
    urow("dk_shard_total_a_mac", P.Sh.total(SH_A(True{})))
    urow("dk_shard_n_formula_a_mac", P.shard_n(P.Sh.total(SH_A(True{})), P.Sh.seg(SH_A(True{}))))
    +am : P.ShOut <- IO.pure(P.ShOut, dk_run_a(fx_plain(), True{}))
    srow("dk_shard_a_mac", shard_str(P.ShOut.segs(am)))
    row("dk_shard_a_differs_by_platform", Bool.not(String.eq(shard_str(P.ShOut.segs(a)),
                                                           shard_str(P.ShOut.segs(am)))))
    # B, the SKEWED fixture, and the one the whole function is for.
    urow("dk_shard_total_b", P.Sh.total(SH_B(False{})))
    urow("dk_shard_fd_b", P.Sh.fd_off(SH_B(False{})))
    urow("dk_shard_minor_b", P.shard_minor(100, False{}))
    urow("dk_shard_n_formula_b", P.shard_n(P.Sh.total(SH_B(False{})), P.Sh.seg(SH_B(False{}))))
    +b : P.ShOut <- IO.pure(P.ShOut, dk_run_b(fx_plain(), False{}))
    srow("dk_shard_b", shard_str(P.ShOut.segs(b)))
    urow("dk_shard_cover_b", shard_cover(P.ShOut.segs(b)))
    row("dk_shard_contig_b", shard_contig(P.ShOut.segs(b)))
    urow("dk_shard_copyouts_b", ncalls(P.K_COPYOUT(), P.Dev.tr(P.ShOut.d(b))))
    urow("dk_shard_seg_len_b", U32.from_nat(List.length(&2, P.Seg, P.ShOut.segs(b))))
    # C, PAST A PAGE BOUNDARY, so `fd_offset` is NOT 0 and the `fd_offset` column
    # stops being constant over the suite.
    urow("dk_shard_fd_c", P.Sh.fd_off(SH_C(False{})))
    urow("dk_shard_minor_c", P.shard_minor(5000, False{}))
    +c : P.ShOut <- IO.pure(P.ShOut, dk_run_c(fx_plain(), False{}))
    srow("dk_shard_c", shard_str(P.ShOut.segs(c)))
    urow("dk_shard_cover_c", shard_cover(P.ShOut.segs(c)))
    row("dk_shard_contig_c", shard_contig(P.ShOut.segs(c)))
    # D, THE SHORT MAPPING, and the only fixture that exercises the `U32` wrap. The
    # two rows below it are the pair that makes the hazard a measurement: the RAW
    # third term is the bit pattern, and `shard_read` answers `seg_len` anyway.
    urow("dk_shard_raw_third_d", P.shard_raw_third(6144, SH_D(False{})))
    # THE one place the `U32` AND CPython DISAGREE, and THE gate cannot print
    # CPython's SIDE: `U32` has no signed type, which IS the divergence. What it can
    # print is the wrapped term (4294965248, i.e. -2048 as a bit pattern), the `min`
    # that term defeats (2048, where Python says -2048) and the cover that follows
    # (10000, where Python says 1948). `ops_disk.py` cannot reach the state -- it
    # relies on `fd_offset + total_copy_size <= src.device.size`, which fixture D
    # violates on purpose -- and a saturating subtraction would invent a rule Python
    # does not have. The oracle carries the pair as THREE ASSERTIONS, so if `U32`
    # ever stops wrapping the oracle FAILS instead of quietly agreeing with the port.
    urow("dk_shard_read4_d", P.shard_read(6144, SH_D(False{})))
    urow("dk_shard_read3_d", P.shard_read(4096, SH_D(False{})))
    +d : P.ShOut <- IO.pure(P.ShOut, dk_run_d(fx_plain(), False{}))
    srow("dk_shard_d", shard_str(P.ShOut.segs(d)))
    urow("dk_shard_cover_d", shard_cover(P.ShOut.segs(d)))
    row("dk_shard_contig_d", shard_contig(P.ShOut.segs(d)))
    # E, THE SKEW CROSSING A PAGE BOUNDARY -- the fixture that makes :104's
    # `size + minor_offset` separable from `size`. `minor` is 1500 and `size` is
    # 3000, so the sum is 4500 and rounds up to 8192 while `size` alone rounds up
    # to 4096, and the segment count is 4 rather than 1. `dk_shard_seg_len_e` is the
    # row a dropped-skew port gets wrong, and `dk_shard_total_e` is the row it gets
    # wrong FIRST.
    urow("dk_shard_total_e", P.Sh.total(SH_E(False{})))
    urow("dk_shard_minor_e", P.shard_minor(1500, False{}))
    urow("dk_shard_fd_e", P.Sh.fd_off(SH_E(False{})))
    +e : P.ShOut <- IO.pure(P.ShOut, dk_run_e(fx_plain(), False{}))
    srow("dk_shard_e", shard_str(P.ShOut.segs(e)))
    urow("dk_shard_cover_e", shard_cover(P.ShOut.segs(e)))
    row("dk_shard_contig_e", shard_contig(P.ShOut.segs(e)))
    urow("dk_shard_seg_len_e", U32.from_nat(List.length(&2, P.Seg, P.ShOut.segs(e))))
    # a segment LONGER than the whole shard: one segment, and `real` is the request.
    +big : P.ShOut <- IO.pure(P.ShOut, P.shard_at(20000, 10000, 0, 40960, False{}, fx_plain()))
    srow("dk_shard_big", shard_str(P.ShOut.segs(big)))
    urow("dk_shard_big_cover", shard_cover(P.ShOut.segs(big)))
    row("dk_shard_big_contig", shard_contig(P.ShOut.segs(big)))
    # `seg_len == 0` is an empty `range` in Python and 0 here, because `U32.div(x,0)
    # = 0`. That is the second place this file leans on the documented div.
    urow("dk_shard_seg0_n", P.shard_n(P.Sh.total(SH_A(False{})), 0))
    +zero : P.ShOut <- IO.pure(P.ShOut, P.shard_at(0, 10000, 0, 40960, False{}, fx_plain()))
    urow("dk_shard_seg0_segs", U32.from_nat(List.length(&2, P.Seg, P.ShOut.segs(zero))))
    # :106 -- `not hasattr(DiskDevice,'io_uring') or not use_ioring`. Either way the
    # non-uring arm is taken, and both give the SAME segments.
    +i0 : P.ShOut <- IO.pure(P.ShOut, shard.pick(False{}, True{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_ioring_absent", String.eq(shard_str(P.ShOut.segs(i0)),
                                            shard_str(P.ShOut.segs(a))))
    +i1 : P.ShOut <- IO.pure(P.ShOut, shard.pick(True{}, False{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_no_use_ioring", String.eq(shard_str(P.ShOut.segs(i1)),
                                            shard_str(P.ShOut.segs(a))))
    # and the io_uring arm's two submission calls, which are all it adds here.
    +i2 : P.ShOut <- IO.pure(P.ShOut, shard.pick(True{}, True{}, 4096, 10000, 0, 40960,
                                              False{}, fx_plain()))
    row("dk_shard_ioring_order", seq(P.Dev.tr(P.ShOut.d(i2)),
      [P.Call{P.K_SQE_STORE(), 0}, P.Call{P.K_IORING_ENTER(), 1}]))
    urow("dk_shard_ioring_sqes", ncalls(P.K_SQE_STORE(), P.Dev.tr(P.ShOut.d(i2))))
    urow("dk_shard_ioring_enters", ncalls(P.K_IORING_ENTER(), P.Dev.tr(P.ShOut.d(i2))))
    urow("dk_shard_ioring_copyouts", ncalls(P.K_COPYOUT(), P.Dev.tr(P.ShOut.d(i2))))

# --- 8: io_uring setup, :50-71 ----------------------------------------------
def t_ioring() -> IO(Unit):
  do IO<Unit>:
    +p : P.Dev <- IO.pure(P.Dev, fx_plain())
    +pt : P.Tr <- IO.pure(P.Tr, P.Dev.tr(p))
    row("dk_ioring_tried", P.Dev.tried(p))
    row("dk_ioring_stored", P.Dev.ioring(p))
    row("dk_ioring_order", seq(pt, [P.Call{P.K_IOURING_SETUP(), 4096},
      P.Call{P.K_MMAP(), 0}, P.Call{P.K_MMAP(), 134217728}, P.Call{P.K_MMAP(), 268435456}]))
    urow("dk_ioring_n", seen(pt))
    urow("dk_ioring_mmaps", ncalls(P.K_MMAP(), pt))
    urow("dk_ioring_setup_n", ncalls(P.K_IOURING_SETUP(), pt))
    # a non-linux host: :15's guard is satisfied and NOTHING is set up, but
    # `_tried_io_uring_init` is STILL True because :51 runs before the test.
    +n : P.Dev <- IO.pure(P.Dev, fx_noioring())
    urow("dk_ioring_skipped_calls", seen(P.Dev.tr(n)))
    row("dk_ioring_skipped_tried", P.Dev.tried(n))
    row("dk_ioring_skipped_stored", Bool.not(P.Dev.ioring(n)))
    # the `if fd < 0: return` at :55 -- one call, no mmaps, no store.
    +f : P.Dev <- IO.pure(P.Dev, fx_ioring_fail())
    +ft : P.Tr <- IO.pure(P.Tr, P.Dev.tr(f))
    urow("dk_ioring_failed_n", seen(ft))
    urow("dk_ioring_failed_mmaps", ncalls(P.K_MMAP(), ft))
    row("dk_ioring_failed_stored", Bool.not(P.Dev.ioring(f)))

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
# THE mutation table. MEASURED, NOT predicted -- every number below is
# `.venv/bin/python gates/datasets-mutate.py` output, and re-running it reproduces this file.
# (RESTORED 2026-10-16 from `.agents/slop/dk-mutate.py`, blob e853efc4b, 20941 B, byte for byte;
# the same instrument serves `nn/datasets.bend`'s table, so it is named for what it measures
# rather than for the file it was swept out of.)
#
#     .venv/bin/python gates/datasets-mutate.py          # run all 56, print the measured table
#     .venv/bin/python gates/datasets-mutate.py --list   # the table, unrun
#     .venv/bin/python gates/datasets-mutate.py M7 M31   # a subset
#
# The harness applies each edit IN PLACE, runs the interpreted lane, and diffs the
# baseline. `CHANGED` is the number of rows whose NAME is present in both runs and
# whose VALUE differs; the last column lists them. `MOVED` -- a row name appearing
# or disappearing -- is 0 for all 56, which is itself the claim worth making: no
# mutation changed the SHAPE of the suite, only its answers, so no row can be
# quietly deleted by any of them. A row that is deleted is not a row that failed.
#
# THE two controls MOVE NOTHING and nothing ELSE DOES. M0 and D0 are
# comment-only edits; both are `0/0`. Every other one of the 54 is `>= 1`. That is
# the property the recorded lesson asks for -- a table with no row that CANNOT move
# is a table of coincidences -- and the harness ENFORCES it: it reports any mutation
# with `0/0` as a BLIND SPOT rather than as a pass.
#
# TWO mutations were blind spots on first measurement, and both were fixed with a
# FIXTURE rather than explained away. They are the two most informative results here,
# because both were "the gate does not see this" and neither was "this rule does not
# matter":
#
#   - M31, `:92`'s second conjunct, moved nothing (0/0). The gate had ONE shm
#     fixture and it was a LINUX device, so `P.Dev.osx` was False and :92's FIRST
#     conjunct already picked the arm. The mutation was invisible because the
#     fixture could not REACH the conjunct -- not because the conjunct is
#     redundant. `fx_shm_osx` is the `shm` AND `OSX` combination, which is the only
#     one where `self.dev.fd is not None` is the deciding question, and
#     `dk_copyout_shm_osx_posix` / `dk_copyout_shm_osx_fileio` are the rows it took
#     to kill the mutation. It now moves 2.
#   - M34, `:104`'s `+ minor_offset`, moved nothing (0/0). For three of the four
#     shard fixtures `size + minor` rounds up to the same page count `size` alone
#     does: 5000+100 and 5000+904 both give 8192, and so does 5000 alone. The skew
#     was invisible. Fixture E exists for exactly this, and its TWO numbers are
#     constrained rather than found: `minor = 1500 < seg_len = 2048`, so E is not a
#     second copy of D (whose third term goes negative), and
#     `size + minor = 4500 > PAGESIZE`, so the two roundings differ. It now moves 4.
#
# THE four mutations that produce a result row failing, which is the whole reason
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
# | M41 | :57 offset 0 comes BEFORE :58 `P.IORING_OFF_CQ_RING` | 0/4 | `dk_ioring_order`, `dk_open_file_trace`, `dk_open_shm_trace`, `dk_warm_trace` |
# | M42 | :128 stores the sqe and :130 enters -- the nesting must put the STORE first | 0/1 | `dk_shard_ioring_order` |
