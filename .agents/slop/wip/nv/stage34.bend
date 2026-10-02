# ===========================================================================
# STAGE 3 -- THE PROGRAM CACHE, THE IMAGE, AND THE LAUNCH PATH.
#
# ===========================================================================
# :43-45 `nv_iowr`, THE COMMAND ENCODER.
#
#   `cmd or ((3 << 30) | (ctypes.sizeof(args) & 0x1FFF) << 16 |
#            (ord('F') & 0xFF) << 8 | (nr & 0xFF))`
#
# FOUR FIELDS, and the two masks are load-bearing: `sizeof(args) & 0x1FFF`
# TRUNCATES an 8 KiB struct to 0, and `nv_iowr(fd, nr, args, cmd=...)` passes an
# explicit `cmd` for the UVM calls so the encoding does not happen at all. Both
# are rows, and `nv_iowr_8192_1` is the truncation.
# ===========================================================================

def IOWR_READ() -> U32: 3
def IOWR_F() -> U32: 70
def IOWR_SIZE_MASK() -> U32: 8191
def IOWR_NR_MASK() -> U32: 255

# THE FOUR FIELDS, `U32.or`ed because they do not overlap: bits 30-31 the read
# direction, 16-28 the struct size, 8-15 `'F'`, 0-7 the request number.
def iowr.pack(sz: U32, nr: U32) -> U32:
  U32.or(U32.or(U32.shln(IOWR_READ(), 30n), U32.shln(sz, 16n)),
         U32.or(U32.shln(IOWR_F(), 8n), nr))

# THE TWO MASKS ARE LOAD-BEARING and `nv_iowr_8192_1` is the row: `sizeof(args)
# & 0x1FFF` is 0 for an 8 KiB struct, so the size field vanishes and the word
# reads as if the struct were empty.
def iowr.cmd(nbytes: U32, nr: U32) -> U32:
  iowr.pack(U32.and(nbytes, IOWR_SIZE_MASK()), U32.and(nr, IOWR_NR_MASK()))

# `cmd or (...)` -- the explicit-command arm, which is EVERY `uvm()` call (:400
# passes `cmd=cmd`). 0 is not a legal encoded word, because the read bit is
# always set, so 0 is a safe sentinel for "no explicit command".
def iowr.cmd.at(+explicit: U32, nbytes: U32, nr: U32) -> U32:
  Bool.pick(U32, U32.is_zero(explicit), iowr.cmd(nbytes, nr), explicit)

# :45 `if ret != 0: raise RuntimeError(f"ioctl returned {ret}")`. THE REFUSAL, and
# `ret` is the ioctl's return value, which the seam supplies.
def iowr.msg(+ret: U32) -> String:
  Bool.pick(String, U32.is_zero(ret), "", String.concat(["ioctl returned ", U32.show(ret)]))

# ===========================================================================
# :50-94 -- QMD. THE FIELD TABLE, AND WHY A `List<&2, U32>` OF WORDS IS EXACT.
#
# `self.mv = bytearray(self.sz * 4)` -- 256 bytes for ver 3 and 384 for ver 5.
# `QMD.fields[pref][k]` is a `(hi, lo)` BIT RANGE and `read`/`write` do
#
#   (int.from_bytes(mv[lo//8:hi//8+1], "little") >> (lo % 8)) & ((1 << (hi-lo+1)) - 1)
#   mv[lo//8:hi//8+1] = ((num & ~mask) | (v << (lo % 8))).to_bytes(...)
#
# MEASURED over BOTH generated tables: 181 fields for NVC6C0_QMDV03_00 and 296
# for NVCEC0_QMDV05_00, and NOT ONE of the 477 is wider than 32 bits and NOT ONE
# straddles a 32-bit boundary. So a field lives in exactly one U32 word, `lo//32`
# is its word and `lo % 32` is its shift, and the byte-array model is EXACT
# rather than approximate. `nv_qmd_fields_v3` and `nv_qmd_fields_v5` are the
# rows that pin the counts the property is measured over, and the WALL for the
# 407 fields ops_nv.py does not name is in the header.
# ===========================================================================

def qmd.ver.of(compute: U32) -> U32:
  Bool.pick(U32, U32.is_ge(compute, BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())

def qmd.sz.of(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(v, QMD_VER5()), QMD_SZ5(), QMD_SZ3())

def qmd.words(v: U32) -> U32: U32.mul(qmd.sz.of(v), 4)

# THE TWO GENERATED TABLES' SIZES, MEASURED, because the word model is only exact
# BECAUSE of what they do not contain.
def qmd.fields_v3() -> U32: 181
def qmd.fields_v5() -> U32: 296

# :94 `return ("grid_width", "grid_height", "grid_depth") if self.ver >= 4 else
# ("cta_raster_width", "cta_raster_height", "cta_raster_depth")`. The NAMES, and
# a port that kept the ver-3 names would write three fields that do not exist in
# a ver-5 QMD.
def qmd.grid.a(+v: U32) -> String:
  match v:
    case 3: "grid_width"
    case _: "cta_raster_width"

def qmd.grid.b(+v: U32) -> String:
  match v:
    case 3: "grid_height"
    case _: "cta_raster_height"

def qmd.grid.c(+v: U32) -> String:
  match v:
    case 3: "grid_depth"
    case _: "cta_raster_depth"

def qmd.grid(+v: U32) -> List<&2, String>:
  [qmd.grid.a(v), qmd.grid.b(v), qmd.grid.c(v)]

# :79 `self.set_addr("program_address", addr >> (4 if self.ver >= 4 else 0),
# "_shifted4" if self.ver >= 4 else "")` -- the ADDRESS is shifted for ver 5 and
# the FIELD NAME says so, and the same shape holds for the constant buffer's
# `_shifted6_`. Both are rows because both are silent-wrong-kernel shapes, and
# `qmd.cbuf_sfx`'s index is a String because Python builds it with an f-string
# and `U32.show` is the only way to get one.
def qmd.prog_shift(v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 4, 0)
def qmd.cbuf_shift(+v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 6, 0)

def qmd.prog_sfx(v: U32) -> String:
  Bool.pick(String, U32.is_ge(v, 4), "_shifted4", "")

def qmd.cbuf_sfx(v: U32, +i: String) -> String:
  Bool.pick(String, U32.is_ge(v, 4),
            String.concat(["_shifted6_", i]), String.concat(["_", i]))

# :85-91 `set_release`, and it is the only method that can REFUSE: it finds the
# first `release{i}_enable` that is clear, and returns False when BOTH are set.
# `NVComputeQueue.release` (:145-148) then falls back to the channel method --
# so a QMD whose two release slots are full silently gets no release, which is
# the whole reason this is a function and not an assignment.
def qmd.slot(busy0: Bool, busy1: Bool) -> U32:
  Bool.pick(U32, busy0, Bool.pick(U32, busy1, 3, 1), 0)

def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.or(busy0, busy1))

# `release_structure_size_{i}` is 0 for a TIMESTAMP and 2 otherwise -- the
# reverse of what the name suggests, and it is the only difference between
# `signal` and `timestamp` inside the QMD.
def qmd.rel_size(tstamp: Bool) -> U32:
  Bool.pick(U32, tstamp, 0, 2)

# `{} if self.ver >= 4 else {f"release{i}_payload64b": 1}` -- ver 3 needs the
# explicit 64-bit payload flag and ver 5 does not have the field.
def qmd.payload64b(v: U32) -> Bool: Bool.not(U32.is_ge(v, 4))

# ===========================================================================
# :230-305 -- NVProgramData. THE DERIVATIONS, and every one of them is a pure
# function of five numbers: `regs`, `shmem`, `cbuf0_size`, the signature length
# and the image length.
#
# `nbytes` IS NOT A FIELD ANYWHERE IN HERE, the same rule `device.bend` states
# for a Buffer: it is a derivation from its inputs, so storing it would let two
# copies disagree. `image_len` and `kernargs` are DERIVED and the gate reads the
# derivations.
# ===========================================================================

type PData is Data:
  PData{ver: U32, regs: U32, shmem: U32, cbuf0: U32, nsig: U32, nbufs: U32,
        nvars: U32, img: U32, mock: Bool}

# :54 `self.ver, self.sz = (5, 0x60) if dev.iface.compute_class >=
# nv_gpu.BLACKWELL_COMPUTE_A else (3, 0x40)` -- ONE comparison decides the whole
# QMD layout and it is `>=`.
def pd.of(compute: U32, regs: U32, shmem: U32, cbuf0: U32, nsig: U32, nbufs: U32,
          nvars: U32, img: U32, mock: Bool) -> PData:
  PData{qmd.ver.of(compute), regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}

def PData.ver(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: ver

def PData.regs(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: regs

def PData.shmem(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: shmem

def PData.cbuf0(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: cbuf0

def PData.nsig(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nsig

def PData.nbufs(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nbufs

def PData.nvars(p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: nvars

def PData.img(+p: PData) -> U32:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: img

def PData.mock(p: PData) -> Bool:
  match p:
    case PData{ver, regs, shmem, cbuf0, nsig, nbufs, nvars, img, mock}: mock

# :268-269 `min_cbuf0_entries = 224 if dev.iface.compute_class >=
# nv_gpu.BLACKWELL_COMPUTE_A else 12` and `self.cbuf_0 = [0] *
# max(cbuf0_size // 4, min_cbuf0_entries)`. THE COMMENT above :267 says why the
# two numbers differ: "Blackwell needs index 223 (224 entries), older GPUs need
# index 11 (12 entries)".
#
# THE CLASS IS NOT A FIELD OF `PData` and the VERSION is, which is sound because
# `qmd.ver.of` is the only way a version is set and it IS the same `>=`. So the
# comparison reads the version and `nv_cbuf0_by_ver` is the row that says the two
# are the same predicate.
def pd.min_cbuf0(ver: U32) -> U32:
  Bool.pick(U32, U32.is_eq(ver, QMD_VER5()), 224, 12)

def pd.max2(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

# :269, above.
def pd.cbuf0_len(+p: PData) -> U32:
  pd.max2(U32.div(PData.cbuf0(p), 4), pd.min_cbuf0(PData.ver(p)))

# :279 `self.kernargs_size = round_up(max(self.constbufs[0][1],
# len(self.cbuf_0) * 4 + len(signature) * 8), 256)`. THREE TERMS and a max:
# the constant buffer's own declared size, the driver params, and EIGHT BYTES A
# SIGNATURE ENTRY -- the 8 is a conservative bound and NOT a sum of the entry's
# own itemsize, so a program with five uint32 vars is budgeted as 40 bytes of
# args while `layout_args` only spends 12. That gap IS the padding, and a port
# that budgeted the signature's real size would under-allocate cbuf_0. Both
# numbers are `U32` and both are read twice, so the max is a def.
def pd.kernargs(+p: PData) -> U32:
  H.round_up_u32(pd.max2(PData.cbuf0(p),
    U32.add(U32.mul(pd.cbuf0_len(p), 4), U32.mul(PData.nsig(p), 8))), 256)

# :305 `self.max_threads = ((65536 // round_up(max(1, regs) * 32, 256)) // 4) * 4
# * 32` -- "Registers allocation granularity per warp is 256, warp allocation
# granularity is 4. Register file size is 65536". THREE divisions and a max(1,
# regs): a MOCK program has regs 0 and must still divide by 256.
def pd.r1(+regs: U32) -> U32: Bool.pick(U32, U32.is_zero(regs), 1, regs)

def pd.max_threads(regs: U32) -> U32:
  U32.mul(U32.mul(U32.div(U32.div(65536, H.round_up_u32(U32.mul(pd.r1(regs), 32), 256)), 4), 4), 32)

# :293 `smem_cfg = min(shmem_conf * 1024 for shmem_conf in [32, 64, 100] if
# shmem_conf * 1024 >= shmem) // 4096 + 1`. THREE CANDIDATES and a MIN, and the
# MIN IS OVER AN EMPTY SEQUENCE for shmem > 102400 -- which Python reports as
# `ValueError("min() iterable argument is empty")`. That refusal is the row
# `nv_smemcfg_too_big` and it is the only one in this section.
def smemcfg.step(+shmem: U32) -> U32: H.round_up_u32(shmem, 4096)

def smemcfg.ok(shmem: U32) -> Bool: U32.is_le(shmem, 102400)

# the smallest candidate >= shmem, then `// 4096 + 1`. `H.round_up_u32` is
# overflow-free and `102400` is the largest candidate, so the whole thing is
# `round_up(shmem, 4096) + 1` on the domain where it is defined.
def pd.smem_cfg(shmem: U32) -> U32: U32.add(smemcfg.step(shmem), 1)

def pd.smem_cfg.msg(+shmem: U32) -> String:
  Bool.pick(String, smemcfg.ok(shmem), "",
            "min() iterable argument is empty")

# :277 `self.image = image.ljust(round_up(len(image), 0x1000) + 0x1000, 0)` --
# "NOTE: Ensure at least 4KB of space after the program to mitigate prefetch
# memory faults". The +0x1000 is the NOTE and it is 4096 bytes of slack.
def pd.image_len(img: U32) -> U32: U32.add(H.round_up_u32(img, 4096), 4096)

# :273 `self.vars = [dtypes.uint64 if mock else dt for _,_,dt,_ in
# signature[nbufs:]]` and :272 `nbufs = sum(name is None for name, *_ in
# signature)`. A MOCKGPU program wants EVERY var 64 bit and counts the buffers
# and the vars out of cbuf_0 at :274, which is why `nvars` is a field.
def pd.var_isize(p: PData, k: U32) -> U32:
  Bool.pick(U32, PData.mock(p), W64(), k)

# ===========================================================================
# :261-265 -- THE RELOC TABLE, BOTH DIRECTIONS. A reloc either lands in the
# image at its own offset as a 64-bit pointer, four bytes later as a 32-bit
# pointer, or four bytes later as a 32-bit POINTER SHIFTED BY 32 -- which is the
# high half of one 64-bit address, so `relocs` and `set_addr` are the same fact
# written twice -- or it is a type this backend does not know, and Python raises
# `RuntimeError(f"unknown NV reloc {typ}")`.
# ===========================================================================

def RELOC_NONE() -> U32: 0
def RELOC_64() -> U32: 2
def RELOC_32() -> U32: 56
def RELOC_32_HI() -> U32: 57

type Rl is Data:
  Rl{off: U32, sym: U32, isize: U32, shift: U32}

def Rl.off(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: off

def Rl.sym(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: sym

def Rl.isize(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: isize

def Rl.shift(r: Rl) -> U32:
  match r:
    case Rl{off, sym, isize, shift}: shift

# THE REVERSE DIRECTION: which arm claims a type. 0 means "no arm", which is the
# refusal. `pd.reloc_kind` is a first-wins scan and `pd.reloc_kind_n` counts the
# claims, so a table that dropped the 0x39 arm is caught by the COUNT and not
# only by the forward rows.
def reloc.claims(+typ: U32, arm: U32) -> Bool: U32.is_eq(typ, arm)

def pd.reloc_kind(+typ: U32) -> U32:
  Bool.pick(U32, reloc.claims(typ, RELOC_64()), RELOC_64(),
    Bool.pick(U32, reloc.claims(typ, RELOC_32()), RELOC_32(),
      Bool.pick(U32, reloc.claims(typ, RELOC_32_HI()), RELOC_32_HI(), RELOC_NONE())))

def pd.reloc_kind_n() -> U32: 3

def pd.reloc_arms() -> List<&2, U32>: [RELOC_64(), RELOC_32(), RELOC_32_HI()]

# THE FORWARD DIRECTION. The offsets differ by FOUR for BOTH 32-bit arms, which
# is what makes them the two halves of one 64-bit address.
def pd.reloc.off(+a: U32, kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), a, U32.add(a, 4))

def pd.reloc.isize(kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), W64(), W32())

def pd.reloc.shift(kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, RELOC_32_HI()), 32, 0)

# `else: raise RuntimeError(f"unknown NV reloc {typ}")`. THE MESSAGE, and the
# number in it is the reloc TYPE and not the arm index.
def pd.reloc_msg(+typ: U32) -> String:
  Bool.pick(String, U32.is_zero(pd.reloc_kind(typ)), "",
            String.concat(["unknown NV reloc ", U32.show(typ)]))

# THE FOLD, and it is where the refusal LIVES: an unknown type contributes
# NOTHING to the list, so a later-known reloc is not appended either. That is the
# port's "the raise happens HERE and not later", and `nv_reloc_bad_n` is the row.
type Rf is Data:
  Rf{rs: List<&2, Rl>, refused: Bool}

def Rf.refused(+r: Rf) -> Bool:
  match r:
    case Rf{rs, refused}: refused

def Rf.put.at(+kind: U32, a: U32, sym: U32, rf: Rf) -> Rf:
  match rf:
    case Rf{+rs, +refused}:
      Bool.pick(Rf, U32.is_zero(kind), rf,
                Rf{List.append(&2, Rl, rs,
                      [Rl{pd.reloc.off(a, kind), sym, pd.reloc.isize(kind),
                          pd.reloc.shift(kind)}]), refused})

def Rf.put(a: U32, sym: U32, typ: U32, rf: Rf) -> Rf:
  Rf.put.at(pd.reloc_kind(typ), a, sym, rf)

# the (apply_image_offset, rel_sym_offset, type) triples from `elf_loader`, so the
# fold reads them in Python's order.
type Rb is Data:
  Rb{a: U32, sym: U32, typ: U32}

def Rf.go(ts: List<&2, Rb>, +rf: Rf) -> Rf:
  match ts:
    case Nil{}: rf
    case Rb{a, sym, typ} <> t: Rf.go(t, Rf.put.at(pd.reloc_kind(typ), a, sym, rf))

def relocs0() -> List<&2, Rb>: [Rb{16, 8, RELOC_64()}, Rb{32, 8, RELOC_32()}]

def relocs_bad() -> List<&2, Rb>: [Rb{16, 8, RELOC_64()}, Rb{48, 8, 3}, Rb{64, 8, RELOC_32()}]

def pd.relocs(ts: List<&2, Rb>) -> Rf: Rf.go(ts, Rf{Nil{}, False{}})

# ===========================================================================
# :135-137 -- NVComputeQueue.__init__. TWO NUMBERS AND A BUFFER, and both
# numbers are the stride the launch path indexes by.
#
#   `self.qmd_sz = round_up(QMD(self.dev).sz * 4, 256)`
#   `self.stride = self.qmd_sz + max([p.kernargs_size for p in progs], default=0)`
#
# `sz * 4` is the QMD in BYTES (256 for ver 3, 384 for ver 5) rounded up to 256,
# so `qmd_sz` is 256 or 512 -- and it is ALSO the size of constant buffer 0's
# driver params, which is why the launch's argument base is `qmd_sz`.
def cq.qmd_sz(ver: U32) -> U32: H.round_up_u32(qmd.words(ver), 256)

# `max([...], default=0)`: no programs means stride `qmd_sz`, NOT zero, and a
# port that wrote `max` without the default would answer 0.
def cq.stride(qmd_sz: U32, max_kernargs: U32) -> U32: U32.add(qmd_sz, max_kernargs)

def cq.qmd_buf_len(nprogs: U32, stride: U32) -> U32: U32.mul(nprogs, stride)

# :170 `qmd_addr = self.qmd_buf.getaddr(self.devs) + UOp.const(len(self.qmds) *
# self.stride, dtypes.uint64)` -- the n-th launch's QMD is at `n * stride` and
# NOTHING else. `cq.qmd_off` is that and it is a row per launch index.
def cq.qmd_off(n: U32, stride: U32) -> U32: U32.mul(n, stride)

# :177 `qmd.mv[self.qmd_sz:(at := self.qmd_sz + len(data.cbuf_0) * 4)] =
# array.array('I', data.cbuf_0).tobytes()` -- "constant buffer 0: the driver
# params". `at` is where the ARGS start, and it is `qmd_sz` PLUS the driver
# params, so the two bases are different numbers and the gate reads both.
def cq.arg_base(qmd_sz: U32, cbuf0_len: U32) -> U32:
  U32.add(qmd_sz, U32.mul(cbuf0_len, 4))

# ===========================================================================
# :161-168 -- `NVComputeQueue.exec`'s TWO REFUSALS, and they are checked BEFORE
# anything is written, which is why both are refusals of the SAME shape and both
# truncate the launch trace.
#
#   `if prod(local_size) > 1024 or data.max_threads < prod(local_size): raise`
#   `if any(g > mx for g,mx in zip(global_size, [2147483647, 65535, 65535])) or
#       any(l > mx for l,mx in zip(local_size, [1024, 1024, 64])): raise`
#
# THE FIRST IS A DISJUNCTION and the second is a DISJUNCTION OF DISJUNCTIONS, so
# a port that collapsed either to a conjunction would accept a launch the driver
# refuses. The three maxima are PER AXIS and NOT a single bound: 1024 x 1024 x 64
# is legal and 65 in z is not, which is a row.
# ===========================================================================

def GLOBAL_MAX_X() -> U32: 2147483647
def GLOBAL_MAX_Y() -> U32: 65535
def GLOBAL_MAX_Z() -> U32: 65535
def LOCAL_MAX_X() -> U32: 1024
def LOCAL_MAX_Y() -> U32: 1024
def LOCAL_MAX_Z() -> U32: 64
def THREADS_MAX() -> U32: 1024

# `prod(local_size)`, and it is a U32 because every local dimension is <= 1024
# for a launch Python accepts -- but the PRODUCT is computed BEFORE the check, so
# a (64, 64, 64) local size is 262144 and answers U32 fine.
def prod3(a: U32, b: U32, c: U32) -> U32: U32.mul(U32.mul(a, b), c)

# the first refusal: `prod > 1024 or max_threads < prod`.
def exec.ok.prod(+pr: U32, max_threads: U32) -> Bool:
  Bool.not(Bool.or(U32.is_gt(pr, THREADS_MAX()), U32.is_lt(max_threads, pr)))

def exec.msg.too_many(+pr: U32, +max_threads: U32) -> String:
  Bool.pick(String, exec.ok.prod(pr, max_threads), "",
    String.concat(["Too many resources requested for launch, prod(local_size)=",
                   U32.show(pr), ", data.max_threads=", U32.show(max_threads)]))

# the second refusal, per axis. THREE INDEPENDENT COMPARISONS and no product.
def exec.gmax(ix: U32) -> U32:
  match ix:
    case 0: GLOBAL_MAX_X()
    case 1: GLOBAL_MAX_Y()
    case 2: GLOBAL_MAX_Z()
    case _: 0

def exec.lmax(ix: U32) -> U32:
  match ix:
    case 0: LOCAL_MAX_X()
    case 1: LOCAL_MAX_Y()
    case 2: LOCAL_MAX_Z()
    case _: 0

def exec.g_ok(v: U32, ix: U32) -> Bool: Bool.not(U32.is_gt(v, exec.gmax(ix)))
def exec.l_ok(v: U32, ix: U32) -> Bool: Bool.not(U32.is_gt(v, exec.lmax(ix)))

# SIX NUMELS TRAVEL IN ONE RECORD, because every one of them is read by both the
# predicate and the message and `U32` is affine.
type Dim is Data:
  Dim{gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32}

def exec.dims(gx: U32, gy: U32, gz: U32, lx: U32, ly: U32, lz: U32) -> Dim:
  Dim{gx, gy, gz, lx, ly, lz}

def Dim.gx(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gx

def Dim.gy(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gy

def Dim.gz(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: gz

def Dim.lx(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: lx

def Dim.ly(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: ly

def Dim.lz(+d: Dim) -> U32:
  match d:
    case Dim{gx, gy, gz, lx, ly, lz}: lz

def exec.ok.dims(+d: Dim) -> Bool:
  Bool.and(Bool.and(exec.g_ok(Dim.gx(d), 0), exec.g_ok(Dim.gy(d), 1)),
    Bool.and(Bool.and(exec.g_ok(Dim.gz(d), 2), exec.l_ok(Dim.lx(d), 0)),
      Bool.and(exec.l_ok(Dim.ly(d), 1), exec.l_ok(Dim.lz(d), 2))))

def exec.msg.dims(+d: Dim) -> String:
  Bool.pick(String, exec.ok.dims(d), "",
    String.concat(["Invalid global/local dims global_size=(", U32.show(Dim.gx(d)),
                   ", ", U32.show(Dim.gy(d)), ", ", U32.show(Dim.gz(d)),
                   "), local_size=(", U32.show(Dim.lx(d)), ", ", U32.show(Dim.ly(d)),
                   ", ", U32.show(Dim.lz(d)), ")"]))

# ===========================================================================
# :180-186 -- THE LAUNCH, AS A WORD TRACE. Two shapes and the difference is
# `self.prev_qmd is None`:
#
#   None:  (PMA) NVC6C0_PM_TRIGGER, then NVC6C0_SEND_PCAS_A(qmd_addr>>8),
#          then NVC6C0_SEND_SIGNALING_PCAS2_B(PREFETCH_SCHEDULE)
#   else:  FOUR writes into the PREVIOUS QMD -- dependent_qmd0_pointer,
#          _action, _prefetch and _enable -- and NO words at all.
#
# The chained arm emits no words, so the ring's word count is the only thing that
# distinguishes the two, and a port that always opened a PCAS pair would drop the
# launch ordering that `NVComputeQueue.release` (:145-148) depends on.
# ===========================================================================

def LAUNCH_SHIFT() -> U32: 8
def DEPENDENT_ACTION() -> U32: 1
def DEPENDENT_PREFETCH() -> U32: 1
def DEPENDENT_ENABLE() -> U32: 1

# `if self.dev.pma_enabled: self.nvm(1, NVC6C0_PM_TRIGGER, 0)` -- FIRST, and it
# is inside the None arm, so a chained launch never triggers the profiler.
def cq.pm.at(pma: Bool, t: Tr) -> Tr:
  match pma:
    case True{}: nvm.emit(1, M_PM_TRIGGER(), nvm.words_of(NVALS_ONE()), NVM_TYP2(), [0], t)
    case False{}: t

def cq.pcas.at(qmd_addr_hi: U32, t: Tr) -> Tr:
  nvm.emit(1, M_SEND_PCAS_A(), nvm.words_of(NVALS_ONE()), NVM_TYP2(), [qmd_addr_hi], t)

def cq.pcas2.at(pcas2: U32, t: Tr) -> Tr:
  nvm.emit(1, M_SEND_SIGNALING_PCAS2_B(), nvm.words_of(NVALS_ONE()), NVM_TYP2(),
           [pcas2], t)

def cq.exec.open(pma: Bool, qmd_addr_hi: U32, pcas2: U32, t: Tr) -> Tr:
  cq.pcas2.at(pcas2, cq.pcas.at(qmd_addr_hi, cq.pm.at(pma, t)))

# THE GUARD IS A PARAMETER, because `self.prev_qmd is None` is a CALL and a
# `match` may not scrutinise one.
def cq.exec.at(prev: Bool, pma: Bool, qmd_addr_hi: U32, pcas2: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, prev, t, cq.exec.open(pma, qmd_addr_hi, pcas2, t))

def cq.exec(prev: Bool, pma: Bool, qmd_addr_hi: U32, pcas2: U32, t: Tr) -> Tr:
  cq.exec.at(prev, pma, qmd_addr_hi, pcas2, t)

# `self.prev_qmd.write(dependent_qmd0_pointer=qmd_addr >> 8,
# dependent_qmd0_action=1, dependent_qmd0_prefetch=1, dependent_qmd0_enable=1)`.
# FOUR fields, all immediates, all into the PREVIOUS QMD, and `>> 8` is the same
# shift `SEND_PCAS_A`'s argument carries. The trace entry's `arg` is the pointer,
# so the COUNT is what pins "four writes" and `nv_launch_chain_n` is the row.
def cq.exec.chain(qmd_addr_hi: U32, t: Tr) -> Tr:
  Tr.emit(CALL_ALLOC, qmd_addr_hi,
    Tr.emit(CALL_ALLOC, DEPENDENT_PREFETCH(),
      Tr.emit(CALL_ALLOC, DEPENDENT_ACTION(),
        Tr.emit(CALL_ALLOC, DEPENDENT_ENABLE(), t))))

# ===========================================================================
# :313-320 -- THE PROGRAM CACHE. ITS KEY, BOTH DIRECTIONS, AND ITS ABSENT
# EVICTION POLICY.
#
#   `_nv_program_cache: dict[tuple[bytes, tuple[str, ...]], ...]`
#   `if (cached := _nv_program_cache.get(key := (prg.src[3].arg, devs))) is None:`
#
# THE KEY IS A PAIR and both halves are load-bearing: `prg.src[3].arg` is the
# program's own ELF bytes and `devs` is the device tuple, so the same bytes on two
# devices are TWO entries and byte-identical programs on one device are ONE. A
# key that dropped `devs` would hand a program the address of a buffer allocated
# on a DIFFERENT device.
# ===========================================================================

type PKey is Data:
  PKey{src3: U32, dev0: U32, dev1: U32}

def PKey.src3(+k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: src3

def PKey.dev0(k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: dev0

def PKey.dev1(+k: PKey) -> U32:
  match k:
    case PKey{src3, dev0, dev1}: dev1

# THE REVERSE DIRECTION -- "which entry does this key name" -- and it is a
# first-wins scan, so a table with two identical keys answers the FIRST and a
# last-wins scan would answer the second. `nv_find_dup_first` is the fixture that
# tells the two apart.
def pc.same(+a: PKey, +b: PKey) -> Bool:
  Bool.and(U32.is_eq(PKey.src3(a), PKey.src3(b)), U32.is_eq(PKey.dev0(a), PKey.dev0(b)))

def pc.find.go(+k: PKey, ks: List<&2, PKey>, +at: U32, got: U32) -> U32:
  match ks:
    case Nil{}: got
    case +x <> t: pc.find.go(k, t, U32.add(at, 1), Bool.pick(U32, pc.same(k, x), at, got))

def pc.find(+k: PKey, ks: List<&2, PKey>) -> U32: pc.find.go(k, ks, 0, 0)

# THE CACHE, AND IT HAS NO EVICTION. `_nv_program_cache` is a bare module-level
# dict with no bound and no eviction anywhere in ops_nv.py: the answer to "which
# entry must NOT be evicted" is "all of them", and the honest measurement is a
# GROWTH COUNT -- insert n distinct keys and the count is n. `nv_pc_grow_3` and
# `nv_pc_grow_repeat` are the rows, and the SECOND is the negative case: a key
# that is already present must not grow the cache, so a port that invented an LRU
# or that appended on every lookup fails one of the two.
#
# THE FIELDS ARE NOT NAMED AFTER THE READERS. `PC{n: ...}` with a reader `PC.n`
# is REFUSED -- "a pattern binder that shadows a FIELD NAME is reported as an
# arity error" (bend2-constraints.md), and the error names the reader, not the
# field. So the fields are `cnt`, `uid`, `misses`, `hits`, `keys` and `ords`.
type PC is Data:
  PC{cnt: U32, uid: U32, misses: U32, hits: U32, keys: List<&2, PKey>, ords: List<&2, U32>}

def PC.of() -> PC: PC{0, 0, 0, 0, Nil{}, Nil{}}

def PC.n(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: cnt

def PC.next(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: uid

def PC.miss(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: misses

def PC.hit(p: PC) -> U32:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: hits

def PC.ks(p: PC) -> List<&2, PKey>:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: keys

def PC.ord(p: PC) -> List<&2, U32>:
  match p:
    case PC{cnt, uid, misses, hits, keys, ords}: ords

def PC.at(+p: PC, cnt: U32, ks: List<&2, PKey>, misses: U32, hits: U32,
          ords: List<&2, U32>) -> PC:
  PC{cnt, PC.next(p), misses, hits, ks, ords}

# `next(UOp.unique_num)` at :317 -- the buffer's id is a MONOTONE counter and NOT
# the cache size, so a port that used the cache size would reuse an id. There is
# no eviction, so the two can only differ by how many HITS happened, and
# `nv_pc_id_is_not_count` pins that.
def pc.new_id(p: PC) -> U32: PC.next(p)

# `if (cached := cache.get(key)) is None: ... cache[key] = ...` -- the branch is a
# HIT when the key is already there, and `found` is the scan's answer: an INDEX,
# so the hit test is `found < len(keys)` and a MISS appends. TWO ARMS AS TWO DEFS
# and not one `Bool.pick`, because each arm builds a different `PC` and
# `Bool.pick` evaluates both -- which is how the first version appended the
# PREVIOUS last key instead of the one being inserted.
def pc.hit_arm(+p: PC) -> PC:
  PC.at(p, PC.n(p), PC.ks(p), PC.miss(p), U32.add(PC.hit(p), 1), PC.ord(p))

def pc.miss_arm(k: PKey, +p: PC) -> PC:
  PC.at(p, U32.add(PC.n(p), 1), List.append(&2, PKey, PC.ks(p), [k]),
        U32.add(PC.miss(p), 1), PC.hit(p),
        List.append(&2, U32, PC.ord(p), [pc.new_id(p)]))

def pc.put.at(found: U32, +k: PKey, +p: PC) -> PC:
  Bool.pick(PC, U32.is_lt(found, U32.from_nat(List.length(&2, PKey, PC.ks(p)))),
            pc.hit_arm(p), pc.miss_arm(k, p))

def pc.put(+k: PKey, +p: PC) -> PC: pc.put.at(pc.find(k, PC.ks(p)), k, p)

# ===========================================================================
# STAGE 4 (part one) -- THE BUFFER POOL AND THE DEVICE'S OWN BUFFERS.
#
# `device.bend`'s rules are CONSUMED and not re-derived: a Buffer is a SLOT in a
# `Bar` arena, `nbytes` is `size * itemsize` and is NOT a field, a view's offset
# ACCUMULATES and a view's base is the ROOT. `dev.gpput_off` is the number that
# becomes a `bview` offset and `nv_gpput_off` is what says the accumulation is
# right.
# ===========================================================================

def GPPUT_OFF() -> U32: 140

# :655 `gpput_off = offset + entries*8 + getattr(nv_gpu.AmpereAControlGPFifo,
# 'GPPut').offset` -- the GP-PUT pointer's slot in the host gpfifo buffer, and
# `GPPut.offset` is 140 read out of `AmpereAControlGPFifo`. `entries * 8` is the
# ring's byte length (a uint64 per entry), so the two fifos' GP-PUT pointers sit
# one ring-length apart.
def dev.gpput_off(off: U32, entries: U32) -> U32:
  U32.add(U32.add(off, U32.mul(entries, 8)), GPPUT_OFF())

def dev.fifos_ring(+r: D.BFound, entries: U32, off: U32) -> D.BFound:
  D.bview(D.BFound.ar(r), 0, entries, S.uint64(), off)

def dev.fifos_pair(+r: D.BFound, entries: U32, off: U32) -> D.BFound:
  D.bview(D.BFound.ar(r), 0, 1, S.uint32(), dev.gpput_off(off, entries))

# the two views' answers, which is what the gate reads: the ring's element count,
# the gpput view's byte offset, and the ROOT both of them report.
def fifo_ring_n(v: D.BFound) -> U32: D.Bn.size(D.bar_at(D.BFound.ar(v), 0))
def fifo_ring_off(v: D.BFound) -> U32: D.Bn.off(D.bar_at(D.BFound.ar(v), 0))
def fifo_ring_base(v: D.BFound) -> U32: D.Bn.base(D.bar_at(D.BFound.ar(v), 0))
def fifo_ring_root(v: D.BFound) -> U32: D.Bn.self_ix(D.bar_at(D.BFound.ar(v), 0))
def fifo_ring_bytes(+v: D.BFound) -> U32: D.nbytes(D.BFound.ar(v), D.BFound.i(v))
def fifo_gpput_off(v: D.BFound) -> U32: D.Bn.off(D.bar_at(D.BFound.ar(v), 0))
def fifo_gpput_base(v: D.BFound) -> U32: D.Bn.base(D.bar_at(D.BFound.ar(v), 0))
def fifo_gpput_root(v: D.BFound) -> U32: D.Bn.self_ix(D.bar_at(D.BFound.ar(v), 0))
def fifo_gpput_bytes(+v: D.BFound) -> U32: D.nbytes(D.BFound.ar(v), D.BFound.i(v))

# ===========================================================================
# :688-694 `_ensure_has_local_memory`, AND ITS EARLY RETURN IS THE NEGATIVE CASE
# FOR THE WHOLE POOL. `if self.slm_per_thread >= required: return` reallocates
# NOTHING, submits NOTHING and leaves `slm_per_thread` alone -- so a program
# asking for LESS local memory than the device already has must not move the
# window, and `nv_slm_early_1_have32` is the row that says so. It is the same
# shape as the program cache's "an entry that must NOT be evicted": a pool that
# reallocated on every ask would re-map the local memory window under a running
# kernel.
# ===========================================================================

def SLM_GRAN() -> U32: 32
def BPT_GRAN() -> U32: 512
def BPT_ROUND() -> U32: 32768
def TOT_ROUND() -> U32: 131072
def WARP_THREADS() -> U32: 32

def dev.slm(+required: U32, +have: U32) -> U32:
  Bool.pick(U32, U32.is_ge(have, required), have, H.round_up_u32(required, SLM_GRAN()))

def dev.slm_early(required: U32, have: U32) -> Bool: U32.is_ge(have, required)

# `bytes_per_tpc = round_up(round_up(slm * 32, 0x200) * max_warps_per_sm *
# num_sm_per_tpc, 0x8000)`. FOUR FACTORS and two roundings, and the inner one is
# to 512 while the outer is to 32768.
def dev.bpt(slm: U32, mws: U32, nsm: U32) -> U32:
  H.round_up_u32(U32.mul(U32.mul(H.round_up_u32(U32.mul(slm, WARP_THREADS()), BPT_GRAN()), mws), nsm),
                 BPT_ROUND())

# `Buffer(self.device, round_up(bytes_per_tpc * num_tpc_per_gpc * num_gpcs,
# 0x20000), ...)`. THE LAST ROUNDING IS 128 KiB, and it is the ONLY place in the
# file where a buffer's size is rounded to a 128 KiB multiple.
def dev.slm_bytes(bpt: U32, ntpg: U32, ngpc: U32) -> U32:
  H.round_up_u32(U32.mul(U32.mul(bpt, ntpg), ngpc), TOT_ROUND())

# :696-697 the two commands the raise submits, and they carry DIFFERENT numbers:
# `data64(shader_local_mem._buf)` is the buffer's ADDRESS and
# `data64(bytes_per_tpc)` is the PER-TPC byte count, then 0xff.
def dev.slm_cmd(bpt: U32, +addr_hi: U32, addr_lo: U32, t: Tr) -> Tr:
  nvm.emit(1, M_SET_SHADER_LOCAL_MEMORY_NON_THROTTLED_A(), nvm.words_of(NVALS_THREE_INT()),
           NVM_TYP2(), [addr_hi, bpt, 255],
    nvm.emit(1, M_SET_SHADER_LOCAL_MEMORY_A(), nvm.words_of(NVALS_TWO_INT()),
             NVM_TYP2(), [addr_hi, addr_lo], t))

# ===========================================================================
# :449-450 `alloc`'s PAGE SIZE, AND THE SIZE IT ROUNDS TO.
#
#   `page_size = mmap.PAGESIZE if uncached or host else
#                ((2 << 20) if size >= (8 << 20) else (mmap.PAGESIZE if MOCK else 4 << 10))`
#
# `mmap.PAGESIZE` is a HOST constant -- 16384 on this machine and 4096 on a
# typical x86-64 Linux -- so it is a parameter of `alloc.page_size` and not a
# constant, and `nv_ps_*` is measured against `mmap.PAGESIZE` as CPython sees it.
# The `2 << 20` for a size >= 8 MiB is "use huge pages only for gpu memory".
# ===========================================================================

def HOST_PAGESIZE() -> U32: 16384
def HUGE_PAGESIZE() -> U32: 2097152
def HUGE_THRESHOLD() -> U32: 8388608
def DEV_PAGESIZE() -> U32: 4096

def alloc.page_size(+size: U32, uncached: Bool, host: Bool, mock: Bool) -> U32:
  Bool.pick(U32, Bool.or(uncached, host), HOST_PAGESIZE(),
    Bool.pick(U32, U32.is_ge(size, HUGE_THRESHOLD()), HUGE_PAGESIZE(),
      Bool.pick(U32, mock, HOST_PAGESIZE(), DEV_PAGESIZE())))

# :451 `size = round_up(size, page_size)`. The ROUNDING IS NOT OPTIONAL: a 4097
# byte buffer becomes 8192 and the extra page is real device memory, so
# `nv_allocsz_*` is a row per fixture and not one row for the function.
def alloc.alloc_size(+size: U32, uncached: Bool, host: Bool, mock: Bool) -> U32:
  H.round_up_u32(size, alloc.page_size(size, uncached, host, mock))

# ===========================================================================
# :699-715 `_ensure_has_vid_hw`. THE FIVE NUMBERS A DECODER NEEDS, ONE REFUSAL,
# AND THE ORDER.
#
#   `if self.iface.viddec_class is None: raise RuntimeError(...)`
#   `coloc_sz      = round_up(round_up(h,64)**2 + round_up(w,64)*round_up(h,64)//16, 2<<20)`
#   `intra_top_off = round_up(h, 64) * (608 + 4864 + 152 + 2000)`
#   `intra_unk_size = 2<<20 if viddec_class >= NVCFB0_VIDEO_DECODER else 0`
#   `intra_unk_off  = round_up(intra_top_off, 0x10000) + (64<<10)` if unk_size else None
#   `filter_sz     = round_up(round_up(intra_top_off, 0x10000) + (64<<10) + unk_size, 2<<20)`
#
# THE COMMENT says "decoder offsets are in 256-byte units" and the code shifts by
# 8 for exactly that reason -- so `intra_top_off` is in those units too and the
# 608+4864+152+2000 is a per-row byte count.
# ===========================================================================

def VID_ROUND() -> U32: 2097152
def VID_TOP_ROUND() -> U32: 65536
def VID_PAD() -> U32: 65536
def VID_ROW_BYTES() -> U32: 608
def VID_UNK_SIZE() -> U32: 2097152
def DEV_ERR_VID() -> String: "Video decoder class not available."

def dev.vid_ok(viddec: U32) -> Bool: Bool.not(U32.is_zero(viddec))

def dev.vid_msg(viddec: U32, +name: String) -> String:
  Bool.pick(String, dev.vid_ok(viddec), "",
    String.concat([name, " ", DEV_ERR_VID()]))

# `round_up(h, 64)`, twice in every one of these, so it is its own def.
def vid64(n: U32) -> U32: H.round_up_u32(n, 64)

# `round_up(h,64)**2 + round_up(w,64)*round_up(h,64)//16`, then rounded to 2 MiB.
def dev.vid_coloc(+w: U32, +h: U32) -> U32:
  H.round_up_u32(U32.add(U32.mul(vid64(h), vid64(h)),
    U32.div(U32.mul(vid64(w), vid64(h)), 16)), VID_ROUND())

# `round_up(h, 64) * (608 + 4864 + 152 + 2000)` -- the four numbers are the
# decoder's per-row buffers and their SUM is one constant here because they are
# adjacent in the source with no arithmetic between them.
def dev.vid_top(+h: U32) -> U32:
  U32.mul(vid64(h), U32.add(U32.add(VID_ROW_BYTES(), 4864), U32.add(152, 2000)))

# `2<<20 if viddec_class >= NVCFB0_VIDEO_DECODER else 0` -- the NEW decoder class
# gets the unknown-region buffer and the OLD one does not, so a port that made
# this unconditional would reserve 2 MiB on every card.
def dev.vid_unk_size(viddec: U32) -> U32:
  Bool.pick(U32, U32.is_ge(viddec, CLASS_NVCFB0_VIDEO_DECODER()), VID_UNK_SIZE(), 0)

# `round_up(intra_top_off, 0x10000) + (64<<10)` IF unk_size > 0 ELSE None, and
# `None` here is 0 with `dev.vid_unk_none` beside it -- the decoder's `if
# self.dev.intra_unk_off is not None` at :224 reads the difference.
def dev.vid_unk_off(+top: U32, unk: U32) -> U32:
  Bool.pick(U32, U32.is_zero(unk), 0, U32.add(H.round_up_u32(top, VID_TOP_ROUND()), VID_PAD()))

def dev.vid_unk_none(unk: U32) -> Bool: U32.is_zero(unk)

# :206 `filter_sz = round_up(round_up(intra_top_off, 0x10000) + (64<<10) +
# intra_unk_size, 2<<20)`. The unk size is INSIDE the round_up, so an OLD card's
# filter buffer is SMALLER by 2 MiB than a NEW card's for the same resolution.
def dev.vid_filter(+top: U32, unk: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(H.round_up_u32(top, VID_TOP_ROUND()), VID_PAD()), unk),
                 VID_ROUND())

# :219 `buf + (round_up(w, 64) * round_up(h, 64) >> 8)` -- the chroma offset, and
# the `>> 8` is the 256-byte unit of :206.
def dev.vid_chroma(+w: U32, +h: U32) -> U32: U32.shrn(U32.mul(vid64(w), vid64(h)), 8n)

# :208 `h, w, frame_pos = 2 * ast.src[1].val // 3, ast.src[2].val, ...` -- the
# DECODER'S height is two thirds of the picture height, and it is an INTEGER
# floor, so 1080 gives 720 and 5 gives 3.
def dev.vid_h(+pic_h: U32) -> U32: U32.div(U32.mul(2, pic_h), 3)

# ===========================================================================
# :35, :37-38 -- THE ERROR STRINGS AND THE TWO FAULT TABLES.
#
# `get_error_str(status) = f"{status}: {nv_gpu.nv_status_codes.get(status,
# 'Unknown error')}"` -- the `get` has a DEFAULT, so an unknown status is
# "Unknown error" and not a KeyError, and that is a row. The two fault tables at
# :37-38 are the OPPOSITE: they have NO default, so `NV_PFAULT_FAULT_TYPE[dt]`
# on an unknown type raises KeyError, and that asymmetry is the port's reason for
# two different shapes.
# ===========================================================================

def iface.unknown() -> String: "Unknown error"

def iface.err_str.at(+status: U32, +name: String) -> String:
  String.concat([U32.show(status), ": ", name])

def iface.err_str_of(status: U32, name: String) -> String:
  iface.err_str.at(status, name)

def iface.err_msg(+status: U32) -> String:
  Bool.pick(String, U32.is_zero(status), "", iface.err_str_of(status, iface.unknown()))

# `NV_PFAULT_ACCESS_TYPE` is `{dt: name.split("_")[-1] ...}`, so a value maps to a
# BARE word -- "READ", "WRITE" -- while `NV_PFAULT_FAULT_TYPE` maps to the FULL C
# name. Both directions differ and both are rows.
def FAULT_PDE() -> String: "NV_PFAULT_FAULT_TYPE_PDE"
def FAULT_PRIV() -> String: "NV_PFAULT_FAULT_TYPE_PRIV_VIOLATION"
def ACCESS_READ() -> String: "READ"
def ACCESS_STRONG() -> String: "STRONG"
def ACCESS_WEAK() -> String: "WEAK"

def pfault.n() -> U32: 16
def paccess.n() -> U32: 9
def pfault.status_n() -> U32: 142

# `next((c for c in [...] if c in ...), None)` -- the access table's NONE arm is
# the same `None` `dev.vid_ok` reads.
def paccess.of(x: U32) -> String:
  match x:
    case 0: ACCESS_READ()
    case 1: "WRITE"
    case 2: ACCESS_STRONG()
    case 3: "PREFETCH"
    case _: ACCESS_WEAK()

# ===========================================================================
# hcq2.py:63 `to_name(*parts) = "_".join(parts).replace(":", "_").lower()`.
# THE `pm_bufferize` TAG, and it is a NAME both ways: :660-661 builds
# `UPat(Ops.PARAM, tag=to_name(n, name))` for n in ("ring", "gpput", "doorbell",
# "put_value") and `to_name` is how a PARAM is matched to a fifo field. A tag
# that disagrees in either direction matches NOTHING and the buffer silently
# falls through to a fresh allocation.
# ===========================================================================

# `.replace(":", "_").lower()`, and the ORDER matters: the replace is on the
# ORIGINAL case and the lower is last, so `to_name("COMPUTE", "0")` is
# `compute_0` and NOT `compute:0`.
def to_name.norm(+s: String) -> String:
  String.to_lower(String.concat(String.split(s, ':')))

def to_name.join.go(parts: List<&2, String>, acc: List<&2, String>) -> String:
  match parts:
    case Nil{}: String.join(List.reverse(&2, String, acc), "_")
    case h <> t: to_name.join.go(t, to_name.norm(h) <> acc)

def to_name(+parts: List<&2, String>) -> String:
  to_name.join.go(parts, Nil{})

# THE FOUR NAMES `_new_gpu_fifo`'s pm_bufferize table uses, in the source's order,
# and the FIFTH is `notifier`, which is NOT in the table -- so a buffer named
# `notifier` is NOT bufferized and is allocated from `self.iface.alloc` instead.
def fifo_field_names() -> List<&2, String>:
  ["ring", "gpput", "doorbell", "put_value"]

def fifo_field_n() -> U32: 4

def notifier_bufferized() -> Bool: False{}

# :660 `to_name(n, name)` where `name` is "COMPUTE:0" or "COPY:0", and the fifo
# names come from :618-619 -- so the tag set is a FUNCTION of the two queue names
# and `nv_toname_*` pins it.
def to_name_compute_ring() -> String: to_name(["ring", "COMPUTE:0"])
def to_name_copy_gpput() -> String: to_name(["gpput", "COPY:0"])
def to_name_copy_doorbell() -> String: to_name(["doorbell", "COPY:0"])
def to_name_compute_qmd() -> String: to_name(["qmd", "COMPUTE:0"])

# ===========================================================================
# :818-824 `reg_ops`'s CHUNKING, and it is a policy number.
#
#   `for i in range(0, len(ops), 124): params = ... (regOpCount=len(ops[i:i+124]))`
#
# 124, and the LAST chunk is short -- so a 125-op write is TWO ioctls of 124 and
# 1. `nv_regops_chunks_125` and `nv_regops_last_125` are the rows, and a port
# that chunked at 128 would answer 1 for 125.
# ===========================================================================

def REG_CHUNK() -> U32: 124
def REG_MASK_LO() -> U32: 4294967295

# `len(range(0, n, 124))`, and n 0 is ZERO chunks -- a `reg_ops()` with no
# arguments issues no ioctl at all.
def dev.reg_nchunks(n: U32) -> U32: H.ceildiv_u32(n, REG_CHUNK())

# the LAST chunk's length: the total minus the full chunks before it, and n 0 is
# ZERO because `range(0, 0, 124)` is empty and no ioctl is issued.
def dev.reg_clen.at(rem: U32, chunks: U32) -> U32:
  Bool.pick(U32, U32.is_zero(chunks), 0, rem)

def dev.reg_clen(+n: U32) -> U32:
  dev.reg_clen.at(U32.sub(n, U32.mul(U32.sub(dev.reg_nchunks(n), 1), REG_CHUNK())),
                  dev.reg_nchunks(n))

# :823 `regAndNMaskLo=rest[0] if rest else 0xffffffff` -- the ONLY place a third
# operand changes a register write, and the default is all ones so a write with
# no mask writes the whole register.
def reg_mask(+rest: U32) -> U32:
  Bool.pick(U32, U32.is_zero(rest), REG_MASK_LO(), rest)

# :821-822 the row builder, and the FIELDS are `regOp`, `regType`, `regOffset`,
# `regValueLo`, `regAndNMaskLo` -- five, in that order, and `regOp` is
# `NV2080_CTRL_GPU_REG_OP_WRITE_32` at the default and `regType` is 0.
def REG_OP_WRITE_32() -> U32: 1
def reg_fields_n() -> U32: 5

# ===========================================================================
# :793-816 `_prof_setup_pc_sampling`'s REGISTER ADDRESSES. NOT A WALL: they are
# integer arithmetic on four base addresses and the gpc/tpc/sm indices, and the
# Blackwell and pre-Blackwell arms differ in the SPACING (0x4000 per gpc against
# 0x200 per tpc) and in the SM base.
#
# :777 `PMASYS_BASE, PMAGPC_BASE, GR_GPC_BASE, GPC_BASE = (0x2b1000, 0x2b0000,
# 0x424000, 0x200000) if is_bw else (0x24a000, 0x244000, 0x419800, 0x180000)`
# ===========================================================================

def PROF_BW_GPC_BASE() -> U32: 2097152
def PROF_PRE_GPC_BASE() -> U32: 1572864
def PROF_GPC_STRIDE() -> U32: 16384
def PROF_TPC_STRIDE_PRE() -> U32: 512
def PROF_SM_BASE_BW() -> U32: 2048
def PROF_SM_STRIDE() -> U32: 512

# `is_bw = self.iface.compute_class >= nv_gpu.BLACKWELL_COMPUTE_A` -- THE SAME
# PREDICATE as the QMD version and the min cbuf_0 entries, so
# `nv_prof_shares_predicate` pins that they are one predicate and not three copies
# of it.
def prof.is_bw(compute: U32) -> Bool: U32.is_ge(compute, BLACKWELL_COMPUTE_A())

# :800 `SM_REG(gpc, tpc, sm, reg) = GPC_BASE + gpc * 0x4000 + 0x800 +
# (tpc * num_sm_per_tpc + sm) * 0x200 + reg` -- Blackwell. The SM index is
# `tpc * num_sm_per_tpc + sm`, so the SMs of one TPC are CONTIGUOUS.
def prof.sm_reg.bw(gpc: U32, tpc: U32, sm: U32, reg: U32, nsm: U32) -> U32:
  U32.add(U32.add(U32.add(PROF_BW_GPC_BASE(), U32.mul(gpc, PROF_GPC_STRIDE())),
                  PROF_SM_BASE_BW()),
          U32.add(U32.mul(U32.add(U32.mul(tpc, nsm), sm), PROF_SM_STRIDE()), reg))

# :805 `[0x400, 0x1000][sm]` -- the two SM bases are a LOOKUP.
def prof.sm_base(sm: U32) -> U32:
  match sm:
    case 0: 1024
    case _: 4096

# :805 `SM_REG(...) = GPC_BASE + gpc * 0x4000 +
# (num_tpc_per_gpc - tpc_cnt[gpc] + tpc) * 0x200 + [0x400, 0x1000][sm] + reg` --
# pre-Blackwell. THE TPC INDEX IS COUNTED FROM THE END, so sharing one def with
# the Blackwell arm would be wrong in three places at once.
def prof.sm_reg.pre(gpc: U32, tpc: U32, sm: U32, reg: U32, ntpg: U32, tpc_cnt: U32) -> U32:
  U32.add(U32.add(PROF_PRE_GPC_BASE(), U32.mul(gpc, PROF_GPC_STRIDE())),
          U32.add(U32.mul(U32.add(U32.add(U32.sub(ntpg, tpc_cnt), tpc), PROF_TPC_STRIDE_PRE()),
                  prof.sm_base(sm)), reg))

# :781 `tpc_cnt = [bin(mask).count('1') for mask in tpc_masks]` and :798
# `tpc in range(tpc_cnt[gpc])` -- the per-GPC TPC count is a POPCOUNT and the
# Blackwell arm iterates exactly that many. `nv_prof_tpc_cnt_65535` is the row,
# and a port that used the raw mask would iterate 65535 times per GPC.
def prof.tpc_cnt.go(n: Nat, +mask: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: prof.tpc_cnt.go(m, U32.shrn(mask, 1n),
      U32.add(got, U32.and(mask, 1)))

def prof.tpc_cnt(mask: U32) -> U32: prof.tpc_cnt.go(32n, mask, 0)

# ===========================================================================
# :664-665 `_query_gpu_info`'s INDEX FALLBACK, and it is the OTHER direction of
# a marshalling table:
#
#   `getattr(nv_gpu, 'NV2080_CTRL_GR_INFO_INDEX_' + r.upper(),
#            getattr(nv_gpu, 'NV2080_CTRL_GR_INFO_INDEX_LITTER_' + r.upper(), None))`
#
# The inner `getattr` has a DEFAULT OF ITS OWN, so a request with neither name
# answers None -- and `x.dataList[nvr]` would then raise. The outer default is
# LITTER, i.e. per-warp, so `max_warps_per_sm` and `num_sm_per_tpc` may come from
# a different table than `num_gpcs`. `nv_query_litter_n` is the COUNT row,
# because a table that transcribed the fallback for all five would pass every one
# of the five names.
# ===========================================================================

def QUERY_REQS_N() -> U32: 5

# `ix` is read by BOTH comparisons and `U32` is affine, so the `+` goes on the
# parameter -- the same shape `exec.ok.dims` uses and the reason the OR is one
# line and not two defs.
def query_litter.at(+ix: U32) -> Bool:
  Bool.or(U32.is_eq(ix, 1), U32.is_eq(ix, 3))

def query_litter(ix: U32) -> Bool: query_litter.at(ix)

def query_litter_n() -> U32: 2

def query_name.at(lit: Bool) -> String:
  Bool.pick(String, lit, "NV2080_CTRL_GR_INFO_INDEX_LITTER_",
    "NV2080_CTRL_GR_INFO_INDEX_")

def query_name(ix: U32) -> String: query_name.at(query_litter(ix))