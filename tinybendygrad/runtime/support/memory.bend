# tinybendygrad/runtime/support/memory.bend -- port of tinygrad/runtime/support/memory.py
#
# THE SHARED-MEMORY AND PAGE-MANAGEMENT SUBSTRATE. `support/memory.py` is 288
# lines and it owns no device and opens no file: it is the ARITHMETIC under
# every allocator and every page-table walk in the runtime, and what survives
# the crossing to Bend is DATA:
#
#   * the OFFSET AND LAYOUT ARITHMETIC -- `round_up(size, 0x1000)` in `palloc`
#     and `valloc` (:284, :249, :253), the `MMIOInterface.view` window
#     arithmetic (:12), the `BumpAllocator` bump-and-align sequence (:16-21),
#     and the TLSF bucket arithmetic (:43, :46, :91). A wrong offset is a
#     silently wrong memory access and no row about counts can see it.
#   * the FIELD LISTS, BY NAME AND IN ORDER. `VirtMapping` (:121-122) is six
#     fields and `map_range` builds it with THREE POSITIONAL and three keyword
#     arguments, so a field swap is a silent remapping. `blocks`' 4-tuple is
#     `(size, next, prev, is_free)` (:39) and `pt_stack`'s is
#     `(pt, pte_idx, pte_size)` (:127) while `next()` YIELDS the five-tuple
#     `(off, pt, pte_idx, entries, pte_covers)` (:175) -- three different
#     orders in 136 lines.
#   * the TWO REVERSALS in `MemoryManager.__init__` (:187):
#     `pte_covers = [1 << x for x in va_shifts][::-1]` and
#     `pte_cnt = [1 << (lvl_msb[i+1] - lvl_msb[i]) for ...][::-1]`. Both are
#     `[::-1]` and a port that drops one computes a page table one level off,
#     which every other row still passes.
#   * `_frag_size` (:195-202), the TLB FRAGMENT SIZE: a lowbit, a max, a
#     `bit_length`, and a `- 12`, with a `must_cover` flag that changes WHICH
#     of two mins is taken. Pure, total, and the single highest-value function
#     in the file.
#   * the POLICY: TLSF reuse/split/merge, `BumpAllocator`'s wrap-or-refuse,
#     `PageTableTraverseContext`'s create/free/inspect descent, `valloc`'s
#     palloc_ranges ladder, and every REFUSAL as a TRUNCATION of the trace.
#   * `struct.calcsize` as a table, BOTH directions: `MMIOInterface.__len__`
#     (:8) divides by it, so it decides how many REGISTERS a window is.
#   * `AddrSpace` (:119) as `[PHYS, SYS, PEER]`, BOTH directions.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind. Every seam is a trace tag and nothing else, so ORDER and IDENTITY stay
# gateable even though none of them is made here. This is the `ops_webgpu.bend`
# lane and the reason this file declares NO foreign effect: the seam is
# `Tr.emit`, not a `def ... -> IO(R)` over two `import "./x.c"`.
#
# THE FFI, by Python line, so "what is not here" is checkable rather than
# asserted. None of these is a `raise`; all of them are trace tags:
#   `to_mv` / `.cast(fmt)`          :7, :12    TO_MV, TO_MV_CAST
#   `self.mv[k]`, `.tolist()`       :9, :10    MMIO_INDEX
#   `pt.valid(i)`                   :136,148,171,215  PT_VALID
#   `pt.is_page(i)`                 :140,171   PT_IS_PAGE
#   `pt.entry(i)`                   :140,215,233 PT_ENTRY
#   `pt.address(i)`                 :141       PT_ADDRESS
#   `pt.supports_huge_page(p)`      :169       PT_SUPPORTS_HUGE
#   `pt.set_entry(i, p, ...)`       :138,151,221,234  PT_SET_ENTRY
#   `pt_t(dev, addr, lv=)`          :141,193   PT_T
#   `self.dev.mm.palloc(...)`       :138,149,193  MM_PALLOC
#   `self.dev.mm.pfree(...)`        :149,288   MM_PFREE
#   `self.dev.vram[p:p+size] = ...` :285       VRAM_ZERO
#   `getenv("MM_DEBUG", 0)` prints  :209,228   MM_DEBUG_PRINT
#   `getenv("GMMU", 1)`             :248,275   a Bool PARAMETER, not a seam
#   `self.on_range_mapped()`        :224,236   ON_RANGE_MAPPED (a `pass` hook)
#
# ---------------------------------------------------------------------------
# EVERY CONSTANT, EVERY FIELD LIST AND EVERY `py=` EXPECTATION BELOW WAS READ
# OUT OF CPYTHON by CALLING it, never typed. The oracle is
# `.agents/slop/memory_oracle.py`. The field lists came out of
# `dataclasses.fields(VirtMapping)` and the four `__init__` tuples, and the
# `struct.calcsize` table out of `struct.calcsize` itself -- not out of my head,
# because a hand-transcribed field list is the exact failure mode `ops_cl`'s
# inverted `Sig` and `O.ParamArg`'s field order both were.

import Base
import ../../helpers.bend as H

# ===========================================================================
# THE SEAM. `Call` and `Tr` are this substrate's own copies of the `ops_webgpu`
# machinery: the trace is an ordered list of (tag, argument) and a refusal is
# its TRUNCATION, so ORDER and IDENTITY are gateable and every `raise` in the
# Python lands in the trace without a guard of its own.
# ===========================================================================

type Call is Data:
  Call{k: U32, arg: U32}

# THE RAISE IS HERE. `Tr.emit` records NOTHING once a refusal has fired and
# `Tr.refuse` is IDEMPOTENT after the first, so one fixture numbering reaches
# every refusal site in turn and the failing refusal is not recorded -- in
# Python the `raise` replaces it.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool, nth: U32, at: U32}

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}, 0, 0}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused, nth, at}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused, nth, at}: refused

def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{calls, next, refused, nth, n}

# an EMPTY trace that keeps `at` and `nth`, so one fixture numbering covers a
# whole manager lifetime.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{Nil{}, 0, False{}, nth, at}

# the id the NEXT emit mints. Read BEFORE the emit, so ids are monotone.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates BOTH arms, so the recorded call is a value built here
# and the guard is a parameter. This is the port of every `raise` in the file.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused, nth, at}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}:
      Tr.emit.go(refused, k, arg, calls, next, nth, at)

def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.refuse.go(refused, nth, at)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside
# one of them would branch the walk twice over.
def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

# the TRUNCATION length a refusal shows up as: how many calls there are at all.
def Tr.seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# does the trace CONTAIN this (tag, arg) sequence, IN ORDER? THE FUEL IS THE
# TRACE LENGTH and the answer is `at == patlen`.
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

def Tr.seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

# ===========================================================================
# THE TRACE VOCABULARY. Every tag is an FFI call of `support/memory.py`, named
# by its Python line in the header above. The tag is a `U32` because the trace
# record is `(k, arg)`; `mem_tag_name` renders it so a gate row and a CPython
# row are comparable as strings, and the SYMBOL STAYS A LITERAL in the source
# so `grep` finds the call site.
# ===========================================================================

# :7, :12 -- `to_mv(addr, nbytes)` then `.cast(fmt)`. Two tags because they are
# two calls and a `view` does both again.
def TO_MV() -> U32: 1
def TO_MV_CAST() -> U32: 2
# :9, :10 -- `self.mv[k]` and, for a non-'B' fmt, `.tolist()` on the result.
def MMIO_INDEX() -> U32: 3
# :136, :148, :171, :215 -- `pt.valid(i)`
def PT_VALID() -> U32: 4
# :140, :171 -- `pt.is_page(i)`. The NEGATIVE of `PT_VALID` at the leaf level
# and NOT interchangeable with it: a table PT is valid AND is_page is False.
def PT_IS_PAGE() -> U32: 5
# :140, :215, :233 -- `pt.entry(i)`, whose value the gate needs because every
# page-table refusal message prints it.
def PT_ENTRY() -> U32: 6
# :141 -- `pt.address(i)`
def PT_ADDRESS() -> U32: 7
# :169 -- `pt.supports_huge_page(paddr+off)`
def PT_SUPPORTS_HUGE() -> U32: 8
# :138, :151, :221, :234 -- `pt.set_entry(i, paddr, ...)`. `arg` is the PTE INDEX
# and the PTE VALUE is what the defs around it build and the gate reads there.
def PT_SET_ENTRY() -> U32: 9
# :141, :193 -- `pt_t(dev, addr, lv=)`
def PT_T() -> U32: 10
# :138, :149, :193 -- `self.dev.mm.palloc(size, ...)`. `arg` is the SIZE, which
# is `round_up`'d inside `palloc` (:284) and so is this def's arithmetic.
def MM_PALLOC() -> U32: 11
# :149, :288 -- `self.dev.mm.pfree(paddr, ptable=True)`
def MM_PFREE() -> U32: 12
# :285 -- `self.dev.vram[paddr:paddr+size] = bytes(size)`. The zeroing write.
def VRAM_ZERO() -> U32: 13
# :209, :228 -- the `MM_DEBUG` print. It is a trace tag because the call it
# makes is a print, and the numbers it would print are `vaddr` and `size`.
def MM_DEBUG_PRINT() -> U32: 14
# :224, :236 -- `self.on_range_mapped()`, a `pass` in this file and an
# override in every device that has one.
def ON_RANGE_MAPPED() -> U32: 15

# ===========================================================================
# THE CONSTANTS. Every value here came out of CPython. Nothing is typed.
# ===========================================================================

# memory.py:253, :249, :284 -- `round_up(size, 0x1000)`, the physical page.
# `palloc` rounds to it, and `valloc` rounds `size` to it BEFORE `alloc_vaddr`.
def PAGE_4K() -> U32: 4096
# memory.py:202 -- the `- 12` in `_frag_size`. The fragment table starts at
# 4KB, so fragment 0 is 4KB and fragment n is 4KB << n.
def FRAG_UNIT_SHIFT() -> U32: 12
# memory.py:7 -- `__init__(self, addr, nbytes, fmt='B')`, the DEFAULT cast.
def MMIO_DEF_FMT_ID() -> U32: 1
# memory.py:201 -- `va_pwr2_div = va & -va if va > 0 else (1 << 63)`. The
# sentinel is `1 << 63`, which SATURATES to 0 in a `U32`, so the honest 64-bit
# constant is an `H.I64` and the arithmetic carries a `U32` stand-in.
# `mem_lowbit_zero_exact` and `mem_lowbit_zero_standin` are the two rows that
# say the stand-in is exact: for a `U32` `sz` the largest lowbit `sz & -sz` can
# take is `2^31`, so `2^31` is never smaller than CPython's `1 << 63` on the
# `min` at :202, and the sentinel is never the argmin. `mem_frag_va0_*` then
# gates the consequence.
def LOWBIT_ZERO_64() -> H.I64: H.i64_of_hi_lo(2147483648, 0)
def LOWBIT_ZERO() -> U32: 2147483648
# memory.py:33 -- `block_size:int=16` and `lv2_cnt:int=16`.
def TLSF_DEF_BLOCK() -> U32: 16
def TLSF_DEF_LV2_CNT() -> U32: 16
# memory.py:182 -- `va_allocator = TLSFAllocator((1 << 44), base=0x200000000000)`.
# BOTH ARE OUTSIDE `U32`: `1 << 44` is 17592186044416 and `0x200000000000` is
# 2199023255552, while a `U32` saturates at 4294967295. So the window is an
# `H.I64` and `mem_va_alloc_*` rows print both halves. THIS IS A WALL, and it
# is a wall twice over: a `U32` shift by 44 saturates to 0, which is how the
# top of a free list once became zero-sized.
def VA_ALLOC_SIZE() -> H.I64: H.i64_of_hi_lo(4096, 0)
def VA_ALLOC_BASE() -> H.I64: H.i64_of_hi_lo(8192, 0)
# memory.py:193, :138 -- the page-table allocation size, `palloc(0x1000, ...)`.
def PT_ALLOC_SIZE() -> U32: 4096

# ===========================================================================
# `MMIOInterface` -- memory.py:6-12. A REGISTER WINDOW over a device address,
# and `__len__` (:8) is `nbytes // struct.calcsize(fmt)`, so the FMT decides
# how many registers the window is. The field list is the FOUR-TUPLE of :7 in
# assignment order and it is GATED BY NAME: `mv, addr, nbytes, fmt`.
#
# `mv` is a memoryview and has no Bend counterpart, so it is interned as a `U32`
# HANDLE and the tag `TO_MV` records the construction -- which is the split
# again: `mmio_of` BUILDS the argument of `to_mv(addr, nbytes)`, `mmio_cast`
# RECORDS the `.cast(fmt)` on it. Offsets ACCUMULATE across views (:12 adds
# `self.addr + offset`) and a view's base is the ROOT window's base, exactly as
# `device.bend` consumes its views -- `mmio_view_addr_*` is the row.
# ===========================================================================
type Mv is Data:
  Mv{h: U32, addr: U32, nbytes: U32, fmt: U32}

def Mv.h(m: Mv) -> U32:
  match m:
    case Mv{h, addr, nbytes, fmt}: h

def Mv.addr(m: Mv) -> U32:
  match m:
    case Mv{h, addr, nbytes, fmt}: addr

def Mv.nbytes(m: Mv) -> U32:
  match m:
    case Mv{h, addr, nbytes, fmt}: nbytes

def Mv.fmt(m: Mv) -> U32:
  match m:
    case Mv{h, addr, nbytes, fmt}: fmt

# :7 -- the four-tuple, BY NAME: mv, addr, nbytes, fmt. `mv` is the handle the
# `to_mv` call returned, which is what `Tr.here` read BEFORE the emit.
def mmio_of(h: U32, addr: U32, nbytes: U32, fmt: U32) -> Mv: Mv{h, addr, nbytes, fmt}

# :7 -- `to_mv(addr, nbytes).cast(fmt)` is TWO calls in that order, and the
# handle the second one acts on is the first one's return. The handle is read
# by `Tr.here` BEFORE the first emit, because in Python it is the first call's
# return value and `Tr.next` is monotone in issue order.
#
# LEAF-FIRST, because there are no forward references. The five defs below are
# one def per link of the chain: the leaf takes the already-emitted trace, then
# `.cast`, then `to_mv`, then the `.go` that reads the handle first, then the
# entry point. `mmio_cast2`'s `+t` is DROPPED and unused on purpose (rule at
# `bend2-constraints.md` position 4914): the call is recorded by its caller.
def mmio_cast2(h: U32, addr: U32, nbytes: U32, fmt: U32, +t: Tr) -> Mv:
  mmio_of(h, addr, nbytes, fmt)

# the second call: `.cast(fmt)`, recorded on the handle the first returned.
def mmio_cast.go(+m: Mv, +t: Tr) -> Mv:
  mmio_cast2(Mv.h(m), Mv.addr(m), Mv.nbytes(m), Mv.fmt(m), Tr.emit(TO_MV_CAST(), Mv.fmt(m), t))

# the first call: `to_mv(addr, nbytes)`, and `arg` is the LENGTH.
def mmio_cast(+m: Mv, +t: Tr) -> Mv:
  mmio_cast.go(m, Tr.emit(TO_MV(), Mv.nbytes(m), t))

def mmio_make.go(h: U32, addr: U32, nbytes: U32, fmt: U32, +t: Tr) -> Mv:
  mmio_cast(mmio_of(h, addr, nbytes, fmt), t)

def mmio_make(+t: Tr, addr: U32, nbytes: U32, fmt: U32) -> Mv:
  mmio_make.go(Tr.here(t), addr, nbytes, fmt, t)

# `struct.calcsize` as a table, BOTH directions. `size -> fmt` is a SEARCH and
# `fmt -> size` is the INDEX, and they disagree wherever two formats share a
# size -- so `mem_calcsize_*` gates the fmt->size direction and
# `mem_calcsize_rev_*` gates size->fmt, which is a LOOKUP and may be absent.
# `Csz` is `calcsize(fmt) -> (size, fmt)`: the SIZE Python answers, and the
# fmt it answered it for, so the reverse direction is the FIRST row with that
# size and `mem_calcsize_rev_*` gates which one that is.
type Csz is Data:
  Csz{sz: U32, fmt: String}

def csz_of(sz: U32, fmt: String) -> Csz: Csz{sz, fmt}

def Csz.sz(c: Csz) -> U32:
  match c:
    case Csz{sz, fmt}: sz

def Csz.fmt(c: Csz) -> String:
  match c:
    case Csz{sz, fmt}: fmt

# EVERY size below is `struct.calcsize(fmt)` in CPython. NOT TYPED: the first
# version of this table was written by hand and `?` was given 4.
def calcsizes() -> List<&2, Csz>:
  [csz_of(1, "B"), csz_of(1, "b"), csz_of(2, "H"), csz_of(2, "h"), csz_of(4, "I"),
   csz_of(4, "i"), csz_of(8, "Q"), csz_of(8, "q"), csz_of(4, "f"), csz_of(8, "d"),
   csz_of(1, "?"), csz_of(8, "2I"), csz_of(4, "4B"), csz_of(4, "2H"), csz_of(8, "8B"),
   csz_of(6, "I2B"), csz_of(12, "3I"), csz_of(16, "16B"), csz_of(24, "6I"),
   csz_of(32, "32B"), csz_of(48, "12I"), csz_of(16, "2d"), csz_of(16, "4f")]

# THE TWO DIRECTIONS AS LISTS, so a gate row prints the whole table and a
# re-transcribed one is impossible. `mem_calcsizes_names` is the fmt column in
# table order and `mem_calcsizes_sizes` the size column, so a swap in either
# shows as a DIFFERENT LIST and not as a matching pair.
def csz.go(+cs: List<&2, Csz>, +acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t: csz.go(t, List.append(&2, U32, acc, [Csz.sz(c)]))

def cfmt.go(+cs: List<&2, Csz>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case c <> t: cfmt.go(t, List.append(&2, String, acc, [Csz.fmt(c)]))

def calcsizes_sizes() -> List<&2, U32>: csz.go(calcsizes(), Nil{})
def calcsizes_names() -> List<&2, String>: cfmt.go(calcsizes(), Nil{})

# the 0 a lookup miss answers, named so it cannot be confused with a fmt of
# index 0 -- and it IS indistinguishable from one, because 'B' IS index 0.
# That is a real hazard and the honest mitigation is that every reader of the
# answer is a `Maybe` first: `sz_ix` is the only collapse and `fmt_absent` is
# the only witness, so `mmio_fmt_absent` and `mem_calcsize_rev_*` are the rows
# that notice.
def fmt_absent() -> U32: 0

# `Mv.fmt` holds the table INDEX of the format, so `struct.calcsize` is
# `sizes[fmt]` -- the FORWARD direction, and the row is the whole list so a
# swapped pair is visible. The REVERSE direction `fmt_of_size` is a separate
# search and it may MISS, because `calcsize` is not injective: size 1 is both
# 'B' and '?', size 4 is 'I', 'i', 'f', '4B' and '2H', size 8 is 'Q', 'q',
# 'd', '2I' and '8B'. So the reverse answer is the FIRST such row and
# `mem_calcsize_rev_*` gates which one that is, which is the only claim the
# reverse direction can make.
#
# THE ACCUMULATOR IS A `Nat` AND NOT A `Maybe<&2, U32>`, and this is MEASURED
# rather than stylistic: a `Maybe` accumulator is OVERWRITTEN by every step, so
# the fold answers the LAST match and not the first. That bug was in this file
# and it printed `calcsize_rev_16=22` ('4f', the last 16-byte format) where
# CPython says '16B', and every name search answered `None` because the LAST
# row never matched. `0n` means NOT FOUND and `1n+i` means FOUND AT `i`, which
# is a total function over the same states and cannot be overwritten once set.
def sz_ix(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}: fmt_absent()
    case Some{+i}: i

# `Nat` -> `U32`, and `0n` -> `fmt_absent`. One collapse for both searches.
def nat_ix(n: Nat) -> U32:
  match n:
    case 0n: fmt_absent()
    case 1n+p: U32.from_nat(p)

# `Nat` has no `is_zero`; `is_zero_nat` is `Nat.is_eq(n, 0n)` and it is a def
# rather than an inline `Nat.is_eq(.., 0n)` because two searches need it.
def is_zero_nat(n: Nat) -> Bool: Nat.is_eq(n, 0n)

def cfmt_sz.step.pick(+acc: Nat, +now_n: Nat, +missed: Nat) -> Nat:
  Bool.pick(Nat, is_zero_nat(acc), Bool.pick(Nat, is_zero_nat(missed), missed, now_n), acc)

# a LEAF: `Bool.pick` evaluates both arms, so the new accumulator is built here
# and the test is a parameter. THE FOUND CASE WINS OVER THE FOUND CASE -- the
# step is `(already found) ? keep : (this row matches ? record : not found)`.
# THE REVERSE DIRECTION, `size -> fmt index`, FIRST match, and the miss is
# `fmt_absent` through `nat_ix`.
# `Bool.pick(A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- measured, and getting
# it backwards emits a plausible wrong number rather than a type error (rule at
# `bend2-constraints.md` position 2106). So this is "if the accumulator is still
# NOT FOUND, consider this row; otherwise KEEP what was found":
#   `Bool.pick(Nat, is_zero, (missed if not this row's match else now_n), acc)`
# and the inner `Bool.pick` is `U32.is_eq(..)` already reduced to a `Nat` by the
# caller. The FIRST hit therefore sticks and no later row can overwrite it.
# a LEAF: `Bool.pick` evaluates both arms, so the new accumulator is built here
# and the test is a parameter. THE REVERSE DIRECTION, `size -> fmt index`, FIRST
# match, and the miss is `fmt_absent` through `nat_ix`.
def cfmt_sz.step(+found: Nat, here: U32, want: U32, c: Csz) -> Nat:
  cfmt_sz.step.pick(found, Nat.add(1n, U32.to_nat(here)),
    Bool.pick(Nat, U32.is_eq(Csz.sz(c), want), 1n, 0n))

def cfmt_sz.go(+cs: List<&2, Csz>, +want: U32, +at: U32, acc: Nat) -> Nat:
  match cs:
    case Nil{}: acc
    case c <> t: cfmt_sz.go(t, want, U32.add(at, 1), cfmt_sz.step(acc, at, want, c))

def cfmt_name.step.pick(+acc: Nat, +now_n: Nat, +missed: Nat) -> Nat:
  Bool.pick(Nat, is_zero_nat(acc), Bool.pick(Nat, is_zero_nat(missed), missed, now_n), acc)

# THE NAME SEARCH, same shape: FIRST match wins, and the fixtures resolve their
# `fmt` index through it rather than carrying a literal -- so a reordered table
# moves the fixture and the row together, and the `mmio_fmt_*` rows (which print
# the NAME the index resolves to) are what catches the disagreement.
def cfmt_name.step(+found: Nat, here: U32, want: String, c: Csz) -> Nat:
  cfmt_name.step.pick(found, Nat.add(1n, U32.to_nat(here)),
    Bool.pick(Nat, String.eq(Csz.fmt(c), want), 1n, 0n))

def fmt_of_size(sz: U32) -> U32: nat_ix(cfmt_sz.go(calcsizes(), sz, 0, 0n))

# THE NAME SEARCH, same shape: FIRST match wins, and the fixtures resolve their
# `fmt` index through it rather than carrying a literal -- so a reordered table
# moves the fixture and the row together, and the `mmio_fmt_*` rows (which print
# the NAME the index resolves to) are what catches the disagreement.
def cfmt_name.go(+cs: List<&2, Csz>, +want: String, +at: U32, acc: Nat) -> Nat:
  match cs:
    case Nil{}: acc
    case c <> t: cfmt_name.go(t, want, U32.add(at, 1), cfmt_name.step(acc, at, want, c))

def fmt_ix_name(want: String) -> U32: nat_ix(cfmt_name.go(calcsizes(), want, 0, 0n))

# the DEFAULT fmt of :7 is 'B', and 'B' is table index 0 -- so `mmio_def_fmt`
# is a `U32` that reads as an index and is gated by name against CPython.
def mmio_def_fmt() -> U32: fmt_ix_name("B")

# FORWARD, `fmt index -> size`, and the row is a LIST INDEX. A miss answers
# `fmt_absent` through `sz_ix`, which is a `0` size -- and `0` is not a size
# `struct.calcsize` can return, so the miss is detectable.
def calcsize_i(i: U32) -> U32: sz_ix(List.get(&2, U32, calcsizes_sizes(), U32.to_nat(i)))

# every `struct.calcsize` below is >= 1, so a `0` size IS the out-of-range
# answer and needs no second condition.
def mmio_fmt_absent(m: Mv) -> Bool: U32.is_eq(calcsize_i(Mv.fmt(m)), fmt_absent())

# :8 -- `__len__` is `self.nbytes // struct.calcsize(self.fmt)`. BOTH READS are
# off the SAME record, so `+m` is required -- and it is a copy, so the row can
# be recomputed without a second `Mv`.
def mmio_len(+m: Mv) -> U32: U32.div(Mv.nbytes(m), calcsize_i(Mv.fmt(m)))

# :12 -- `MMIOInterface(self.addr+offset, (self.nbytes - offset) if size is
# None else size, fmt=fmt or self.fmt)`. The SIZE arm is a `Maybe`, because
# Python's `None` is not `0` here: a view of the WHOLE remainder is not a
# zero-length view. THE ADDRESS ACCUMULATES and the new window's base is the
# ROOT's base -- `mv_nbytes_root` is the row that says a nested view does not
# rebase.
def mmio_view_sz(root: Mv, size: Maybe<&2, U32>, off: U32) -> U32:
  match size:
    case None{}: U32.sub(Mv.nbytes(root), off)
    case Some{+s}: s

# `fmt or self.fmt` -- an absent fmt arg keeps the parent's, which is `Bool`'s
# zero, so the sentinel is `fmt_absent` again and NOT index 0 ('B' is 0).
def mmio_view_fmt(root: Mv, fmt: Maybe<&2, U32>) -> U32:
  match fmt:
    case None{}: Mv.fmt(root)
    case Some{+f}: f

def mmio_view_off(root: Mv, off: U32) -> U32: U32.add(Mv.addr(root), off)

# `mv_nbytes_root` -- the byte WINDOW a view sees is bounded by the ROOT's
# bytes, and the answer is the root's `nbytes` for a root. Written as a def so
# a nested view is one call away instead of a re-read of the parent.
def mv_nbytes_root(m: Mv) -> U32: Mv.nbytes(m)
def mv_addr_root(m: Mv) -> U32: Mv.addr(m)

# :9 -- `(self.mv[k] if self.fmt == 'B' else self.mv[k].tolist()) if
# isinstance(k, slice) else self.mv[k]`. THE `.tolist()` ARM IS EXACTLY THE
# NON-'B' TEST, so `mmio_is_byte_fmt` gates it: for a slice index, 'B' returns
# the memoryview element and every other fmt returns a LIST. Two different
# return TYPES off one comparison, and the comparison is a string equality
# against 'B' -- so `mmio_is_byte_fmt` is the row that says which arm, and
# `mem_mmio_byte_fmt_*` is its truth table.
def mmio_is_byte_fmt(f: U32) -> Bool: U32.is_eq(f, mmio_def_fmt())

# ===========================================================================
# `BumpAllocator` -- memory.py:14-21. THE MONOTONE BUMP, and it is the whole
# allocator for the boot region, so its two refusals and its one wrap are load-
# bearing.
#
# THE FIELD LIST IS THE FOUR-TUPLE OF :15 IN ASSIGNMENT ORDER: size, ptr, base,
# wrap. `Bump` keeps that order and `mem_bump_fields_*` gates it BY NAME.
#
# `alloc` (:16-21) is FOUR steps and the order is the algorithm:
#   1. `round_up(self.ptr, alignment) + size > self.size` -- the OVERFLOW test,
#      and it rounds BEFORE it adds, so a pointer that needs padding overflows
#      on the PADDED value. That is the only reason an alignment gap can cost
#      you a block, and `mem_bump_overflow_*` is the row.
#   2. `if not self.wrap: raise RuntimeError("Out of memory")` -- THE REFUSAL,
#      and it is a truncated trace (memory.py:18).
#   3. `self.ptr = 0` on the WRAP arm -- the pointer resets to ZERO and NOT to
#      the aligned value, so the alignment of the new block starts from 0.
#   4. `self.ptr = (res:=round_up(self.ptr, alignment)) + size; return res +
#      self.base` -- the returned address is `res + base`, the ALIGNED offset
#      before the size is added, and `self.ptr` is the END. So the returned
#      address is not `self.ptr + base`, which is the obvious mistake and one
#      row away (`mem_bump_ptr_end_*`).
# ===========================================================================
type Bump is Data:
  Bump{size: U32, ptr: U32, base: U32, wrap: Bool}

def Bump.size(b: Bump) -> U32:
  match b:
    case Bump{size, ptr, base, wrap}: size

def Bump.ptr(b: Bump) -> U32:
  match b:
    case Bump{size, ptr, base, wrap}: ptr

def Bump.base(b: Bump) -> U32:
  match b:
    case Bump{size, ptr, base, wrap}: base

def Bump.wrap(b: Bump) -> Bool:
  match b:
    case Bump{size, ptr, base, wrap}: wrap

# :15 -- `self.size, self.ptr, self.base, self.wrap = size, 0, base, wrap`. THE
# POINTER STARTS AT ZERO and NOT AT `base`, so the first allocation is at
# `base` and the window is `[base, base+size)`.
def bump_of(size: U32, base: U32, wrap: Bool) -> Bump: Bump{size, 0, base, wrap}

def bump_at(b: Bump, ptr: U32) -> Bump:
  match b:
    case Bump{size, _, base, wrap}: Bump{size, ptr, base, wrap}

# :17 -- `round_up(self.ptr, alignment) + size > self.size`. THE ROUND IS BEFORE
# THE ADD, and that is the whole test. `mem_bump_overflow_*` gates it and
# `mem_bump_overflow_eq_*` gates the boundary where it is exactly `size`.
def bump_round(a: U32, +q: U32) -> U32: U32.mul(U32.div(U32.add(a, U32.sub(q, 1)), q), q)

def bump_overflow(+b: Bump, size: U32, align: U32) -> Bool:
  U32.is_gt(U32.add(bump_round(Bump.ptr(b), align), size), Bump.size(b))

# :18 -- `raise RuntimeError("Out of memory")`. The refusal ORDINAL is 1 in this
# file, and the trace is EMPTY at that point because nothing was emitted: the
# `alloc` has no device call at all. So `mem_bump_refuse_*` reads
# `Tr.refused` and `Tr.seen`, and the pair IS the refusal.
def BUMP_REFUSAL_ORD() -> U32: 1

# :19 -- `self.ptr = 0`, the WRAP arm. Zero and NOT the aligned value, so the
# next allocation's padding is measured from 0.
def bump_wrap_ptr() -> U32: 0

# :20-21 -- the aligned offset is `res` and `self.ptr` is `res + size`.
def bump_res(b: Bump, align: U32) -> U32: bump_round(Bump.ptr(b), align)
def bump_end(res: U32, size: U32) -> U32: U32.add(res, size)
def bump_addr(base: U32, res: U32) -> U32: U32.add(base, res)

# THE WRAP POLICY, ONE ANSWER. `bump_try` returns the new state and whether the
# allocation was REFUSED, and the refusal is the trace's: `bump_try` emits
# nothing and the caller refuses. So the verdict is a two-field record, because
# a `Bool.pick` cannot gate a mutating call and a `match` cannot branch on one
# (rule at `bend2-constraints.md` position 5030).
type BumpR is Data:
  BumpR{b: Bump, refused: Bool, res: U32}

def BumpR.b(r: BumpR) -> Bump:
  match r:
    case BumpR{b, refused, res}: b

def BumpR.refused(r: BumpR) -> Bool:
  match r:
    case BumpR{b, refused, res}: refused

def BumpR.res(r: BumpR) -> U32:
  match r:
    case BumpR{b, refused, res}: res

# THE LEAVES, FIRST -- there are no forward references, so `bump_take` and
# `bump_over` are declared before the `bump_try.go` that dispatches to them.
#
# :17-19, :20-21 -- the TAKEN arm. `self.ptr = (res:=round_up(self.ptr,
# alignment)) + size`, so the state's `ptr` is the END and the result record's
# `res` is the ALIGNED OFFSET.
def bump_take(+b: Bump, size: U32, +align: U32) -> BumpR:
  BumpR{bump_at(b, bump_end(bump_res(b, align), size)), False{}, bump_res(b, align)}

# the WRAP arm reduced to its two calls: reset the pointer to 0 and take.
def bump_wrapped(+b: Bump, size: U32, +align: U32) -> BumpR:
  bump_take(bump_at(b, bump_wrap_ptr()), size, align)

# the WRAP arm of :18-19: `self.ptr = 0` when `wrap` is set, otherwise the
# `raise` at :18. So the overflow question is asked TWICE and the two answers
# are `Bump.wrap` and the refusal -- and `mem_bump_nowrap_*` is the NEGATIVE
# CASE, one row from `mem_bump_wrap_*` at the SAME size, which is the
# requirement. On the no-wrap arm the state is UNCHANGED and the returned `res`
# is `0`; `mem_bump_refuse_ptr_*` gates that the pointer did not move, because
# a refused allocation that still advanced the pointer is the bug.
def bump_over(wrap: Bool, b: Bump, size: U32, align: U32) -> BumpR:
  match wrap:
    case True{}: bump_wrapped(b, size, align)
    case False{}: BumpR{b, True{}, 0}

# :16-21, the four steps in order. The overflow arm is the `.go` split because
# a `match` may not scrutinise a computed value.
def bump_try.go(over: Bool, +b: Bump, size: U32, align: U32) -> BumpR:
  match over:
    case True{}: bump_over(Bump.wrap(b), b, size, align)
    case False{}: bump_take(b, size, align)

def bump_try(+b: Bump, +size: U32, +align: U32) -> BumpR:
  bump_try.go(bump_overflow(b, size, align), b, size, align)

# :21 -- `return res + self.base`, the ADDRESS. It is the ALIGNED OFFSET plus
# base and NOT `self.ptr + base`, which is why `bump_addr_of` reads the RESULT
# record's `res` and not the state's `ptr`.
def bump_addr_of(+r: BumpR, b: Bump) -> U32: bump_addr(Bump.base(b), BumpR.res(r))

# the returned address is not the END, and `mem_bump_ptr_end_*` is the row that
# says so: `ptr` is `res + size` and the address is `base + res`.
# THE CLAIM: the state's `ptr` after an allocation is `res + size` and the
# RETURNED ADDRESS is `base + res`, so they are not the same number. `b` is read
# three times -- once for `res` before, once inside the alloc, once for the end
# -- so every `U32` argument is `+`.
def bump_ptr_of(+r: BumpR) -> U32: Bump.ptr(BumpR.b(r))

def bump_ptr_end(got: U32, want: U32) -> Bool: U32.is_eq(got, want)

def bump_ptr_is_end(+b: Bump, +size: U32, +align: U32) -> Bool:
  bump_ptr_end(bump_ptr_of(bump_try(b, size, align)), bump_end(bump_res(b, align), size))

# ===========================================================================
# `AddrSpace` -- memory.py:119. `PHYS = enum.auto(); SYS = enum.auto(); PEER =
# enum.auto()` on ONE line, so the ORDERS are the declarations and the VALUES
# are 1, 2, 3. The table is here BOTH DIRECTIONS, which is the requirement, and
# the DIRECTION THAT MATTERS is `space_of` because `VirtMapping.aspace` is an
# `AddrSpace` and `ops_rdma.bend` needs the index of `SYS`.
#
# `AddrSpace.PHYS.value == 1` and `list(AddrSpace).index(AddrSpace.SYS) == 1` are
# the same number for `SYS` and DIFFERENT for the others: PHYS is value 1 and
# index 0. So a port that uses the enum VALUE where the INDEX belongs maps SYS
# to 1 and PHYS to 1, which is a silent aliasing -- `mem_aspace_value_*` and
# `mem_aspace_index_*` are both here so the two columns are separately gated,
# and `mem_aspace_alias_*` is the row that says PHYS's value and index differ.
# ===========================================================================
type Space is Data:
  Space{ix: U32, val: U32, nm: String}

def space_of(ix: U32, val: U32, nm: String) -> Space: Space{ix, val, nm}

def Space.ix(s: Space) -> U32:
  match s:
    case Space{ix, val, nm}: ix

def Space.val(s: Space) -> U32:
  match s:
    case Space{ix, val, nm}: val

def Space.nm(s: Space) -> String:
  match s:
    case Space{ix, val, nm}: nm

def aspaces() -> List<&2, Space>:
  [space_of(0, 1, "PHYS"), space_of(1, 2, "SYS"), space_of(2, 3, "PEER")]

# the INDEX is what a `U32`-keyed table carries, so `space_at` is the lookup.
def space_at(s: Space) -> U32: Space.ix(s)
def space_of_ix(ix: U32) -> Maybe<&2, Space>: List.get(&2, Space, aspaces(), U32.to_nat(ix))

# the enum VALUE, `AddrSpace.SYS.value`, which is 1 + the index. Kept as its own
# column so the two cannot be read as one field.
def ASPACE_PHYS_VAL() -> U32: 1
def ASPACE_SYS_VAL() -> U32: 2
def ASPACE_PEER_VAL() -> U32: 3
def ASPACE_PHYS_IX() -> U32: 0
def ASPACE_SYS_IX() -> U32: 1
def ASPACE_PEER_IX() -> U32: 2

def Space.go_v(s: Maybe<&2, Space>) -> Space:
  match s:
    case None{}: space_of(fmt_absent(), fmt_absent(), "")
    case Some{+x}: x

def aspace_at_ix(ix: U32) -> Maybe<&2, Space>: List.get(&2, Space, aspaces(), U32.to_nat(ix))

# THE ALIAS ROW. PHYS's value is 1 and its index is 0, so `val == ix + 1`
# everywhere and the two columns never agree -- which means a port that used the
# value as an index would make PHYS and SYS collide on 1.
def aspace_val_is_ix_plus1.go(+phys: Space) -> Bool:
  Bool.and(U32.is_eq(Space.val(phys), ASPACE_PHYS_VAL()),
           U32.is_eq(Space.ix(phys), ASPACE_PHYS_IX()))

def aspace_val_is_ix_plus1() -> Bool:
  aspace_val_is_ix_plus1.go(Space.go_v(aspace_at_ix(ASPACE_PHYS_IX())))

# ===========================================================================
# `VirtMapping` -- memory.py:121-122. THE FIELD LIST, BY NAME, IN ORDER, AND
# THE ORDER IS NOT THE PROSE ORDER IN EVERY READER.
#
# `VirtMapping(va_addr:int; size:int; paddrs:list[tuple[int,int]]; aspace:AddrSpace;
#   uncached:bool=False; snooped:bool=False)`
#
# Six fields, FOUR of them defaulted-or-not. `dataclasses.fields` gives
# `['va_addr', 'size', 'paddrs', 'aspace', 'uncached', 'snooped']` and
# `mem_vm_fields_*` is that list; `mem_vm_defaults_*` is that the last TWO are
# `False` and the first FOUR are MISSING. A frozen dataclass, so a `Vmap` is
# read-only here -- `map_range` BUILDS one, `valloc` BUILDS one, and nothing
# mutates it.
#
# THE FOUR CALL SITES AND THEIR ARGUMENT ORDERS, which is the real content:
#   :225  `VirtMapping(vaddr, size, paddrs, aspace=aspace, uncached=uncached,
#          snooped=snooped)`                 -- THREE POSITIONAL, then keywords
#   :250  `VirtMapping(self.identity_va(uncached) + paddr, size, [(paddr, size)],
#          aspace=AddrSpace.PHYS, uncached=uncached)` -- TWO defaulted fields
#          are LEFT OUT, so `snooped` takes its default
#   :275  `vfree` reads `vm.va_addr`, `vm.size`, `vm.paddrs` -- the reader order
#   :277  `self.unmap_range(vm.va_addr, vm.size)`
# `mem_vm_map_*` and `mem_vm_gmmu0_*` are the two construction rows and
# `mem_vm_vfree_*` the reader row, and the difference in DEFAULT between them is
# the thing a field-order port gets wrong.
# ===========================================================================
type Vmap is Data:
  Vmap{va_addr: U32, size: U32, paddrs: List<&2, Pa>, aspace: U32, uncached: Bool, snooped: Bool}

# `paddrs: list[tuple[int, int]]` -- a list of (paddr, size) PAIRS, and the
# pair order is `paddr` THEN `size`, which is the reverse of how they read at
# :262 (`paddrs += [(self.palloc(try_sz...), try_sz)]`) and how they are consumed
# at :275 (`for paddr, _ in vm.paddrs`). `Pa` keeps that order and
# `mem_pa_fields_*` gates it by name.
type Pa is Data:
  Pa{paddr: U32, psize: U32}

def Pa.paddr(p: Pa) -> U32:
  match p:
    case Pa{paddr, psize}: paddr

def Pa.psize(p: Pa) -> U32:
  match p:
    case Pa{paddr, psize}: psize

def Vmap.va_addr(v: Vmap) -> U32:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: va_addr

def Vmap.size(v: Vmap) -> U32:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: size

def Vmap.paddrs(v: Vmap) -> List<&2, Pa>:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: paddrs

def Vmap.aspace(v: Vmap) -> U32:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: aspace

def Vmap.uncached(v: Vmap) -> Bool:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: uncached

def Vmap.snooped(v: Vmap) -> Bool:
  match v:
    case Vmap{va_addr, size, paddrs, aspace, uncached, snooped}: snooped

# :211 -- `assert size == sum(p[1] for p in paddrs)`, and `p[1]` IS THE SIZE, not
# the paddr. So the invariant is over the SECOND element of every pair and a
# swapped `Pa` breaks it. `vm_psize_sum` is the sum and
# `mem_vm_size_match_*` is the assertion, which is a REFUSAL (:211) and so is
# the second `mem_vm_refuse_*` site in this file.
def psum.go(+ps: List<&2, Pa>, acc: U32) -> U32:
  match ps:
    case Nil{}: acc
    case p <> t: psum.go(t, U32.add(acc, Pa.psize(p)))

def vm_psize_sum(paddrs: List<&2, Pa>) -> U32: psum.go(paddrs, 0)

def vm_size_match(+v: Vmap) -> Bool: U32.is_eq(Vmap.size(v), vm_psize_sum(Vmap.paddrs(v)))

# :225 -- `VirtMapping(vaddr, size, paddrs, aspace=..., uncached=...,
# snooped=...)`. ALL SIX fields are supplied, so the two defaults are OVERRIDDEN
# and a construction that left them out would not be this line.
def vmap_all(vaddr: U32, size: U32, paddrs: List<&2, Pa>, aspace: U32, uncached: Bool, snooped: Bool) -> Vmap:
  Vmap{vaddr, size, paddrs, aspace, uncached, snooped}

# :250 -- `VirtMapping(self.identity_va(uncached) + paddr, size, [(paddr, size)],
# aspace=AddrSpace.PHYS, uncached=uncached)`. `SNOOPED IS NOT SUPPLIED`, so it
# is `False` by default -- and `aspace` is `PHYS` regardless of the device,
# unlike :225 where it is the caller's. `vmap_gmmu0` is the row family.
def vmap_gmmu0(va: U32, paddr: U32, +size: U32, uncached: Bool) -> Vmap:
  vmap_all(va, size, [Pa{paddr, size}], ASPACE_PHYS_IX(), uncached, False{})

# THE `GMMU=0` ADDRESS: `self.identity_va(uncached) + paddr`, so the IDENTITY
# mapping's base is ADDED to the physical address. `vm_gmmu0_va` is the sum and
# it is NOT `paddr` alone -- which is the whole point of `identity_va`.
def vm_gmmu0_va(identity: U32, paddr: U32) -> U32: U32.add(identity, paddr)

# :277 -- `self.unmap_range(vm.va_addr, vm.size)`: the UNMAP TAKES THE VA AND THE
# SIZE and NOT the paddrs. `vm_unmap_va` / `vm_unmap_sz` are the two readers,
# and `mem_vm_vfree_*` says which two fields reach the unmap.
def vm_unmap_va(v: Vmap) -> U32: Vmap.va_addr(v)
def vm_unmap_sz(v: Vmap) -> U32: Vmap.size(v)

# :279 -- `for paddr, _ in vm.paddrs: self.pfree(paddr)` -- the FREE LOOP takes
# the FIRST element of every pair, which is the opposite element from the :211
# size sum. `vm_free_paddrs` is that column and `mem_vm_vfree_free_*` gates that
# the two loops read opposite halves of the same pair.
def pcol.go(+ps: List<&2, Pa>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: pcol.go(t, List.append(&2, U32, acc, [Pa.paddr(p)]))

# ===========================================================================
# THE PAGE-TABLE LAYOUT -- memory.py:186-188. THE TWO REVERSALS.
#
# `self.pte_covers, self.pte_cnt = [1 << x for x in va_shifts][::-1],
#   [1 << (lvl_msb[i+1] - lvl_msb[i]) for i in range(len(lvl_msb) - 1)][::-1]`
#
# BOTH LISTS ARE REVERSED and BOTH ARE PAGES IN DIFFERENT ORDERS than they were
# built in. `va_shifts` is given SMALLEST-FIRST by every device
# (`va_shifts:list[int]` is `sorted(va_shifts)` in every `MemoryManager` caller
# and `va_shifts + [va_bits + 1]` is `lvl_msb`), so `pte_covers` is
# LARGEST-FIRST and `pte_covers[0]` is the ROOT level's page size. A port that
# drops a `[::-1]` produces a table that is right at the root and wrong at every
# other level, and every row that only exercises the root passes.
#
# SO THE REVERSAL IS THE THING BEING GATED, and `mem_pte_cover_*` prints
# `va_shifts` AND `pte_covers` IN ONE ROW so a dropped reversal is a visible
# difference between the two halves of a single row rather than two rows that
# could both be plausible.
#
# `pte_cnt[lv]` is the NUMBER OF ENTRIES AT LEVEL `lv`, and it is a DIFFERENT
# function again: `1 << (lvl_msb[i+1] - lvl_msb[i])` where `lvl_msb` is
# `va_shifts + [va_bits + 1]`. So `pte_cnt` is a DIFFERENCE of two adjacent
# shifts and `pte_covers` is `1 <<` ONE of them, and both are reversed. The
# INVARIANT THAT TIES THEM: `pte_cnt[lv] * pte_covers[lv] == pte_covers[lv-1]`
# for every non-root level -- one level's entries span one level up's page --
# and `mem_pte_ladder_*` is that row, because it is the one claim a
# mis-reversed table cannot fake.
# ===========================================================================

# :186 -- `lvl_msb = va_shifts + [va_bits + 1]`: the shifts plus ONE MORE, and
# the extra is `va_bits + 1`, NOT `va_bits`. So `lvl_msb` is one longer than
# `va_shifts` and `level_cnt = len(va_shifts)` is one shorter. `mem_lvl_msb_*`
# is the row and `mem_level_cnt_*` the count, and they differ by construction.
def lvl_msb_len(shifts: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, shifts))

def lvl_msb_last(shifts: List<&2, U32>, va_bits: U32) -> U32: U32.add(va_bits, 1)

# :188 -- `self.level_cnt = len(va_shifts)`, the shifts WITHOUT the extra.
def level_cnt(shifts: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, shifts))

# `va_shifts + [va_bits + 1]`, the list :186 builds. THE ORDER IS `va_shifts`
# THEN the extra, and the reversal happens LATER -- so a port that reverses
# `lvl_msb` instead of reversing the two results is a different bug with the
# same symptom.
def lvl_msb(+shifts: List<&2, U32>, va_bits: U32) -> List<&2, U32>:
  List.append(&2, U32, shifts, [lvl_msb_last(shifts, va_bits)])

# :187 -- `pte_covers = [1 << x for x in va_shifts][::-1]`. ONE `1 <<` per
# shift, REVERSED. `U32.shln` is `a << n` and `n` is a `Nat`, so the shift
# amount is `U32.to_nat(x)`; `shln(1, 0n) = 1`, which is why a level with
# `va_shifts = [0]` has `pte_covers = [1]` and not 0.
def shl1(x: U32) -> U32: U32.shln(1, U32.to_nat(x))

def covers_raw.go(+xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: covers_raw.go(t, List.append(&2, U32, acc, [shl1(x)]))

def covers_raw(shifts: List<&2, U32>) -> List<&2, U32>: covers_raw.go(shifts, Nil{})

# THE REVERSAL. `List.append(a, A, xs, ys)` is `ys ++ xs`, so appending each
# head to the accumulator BUILDS THE REVERSED LIST DIRECTLY and there is no
# `List.reverse` in this substrate. `covers_of` is `[1 << x ...][::-1]` and
# `covers_raw` is the list WITHOUT it, and both are printed in one row.
# THE REVERSE, as a fold. `rev.u32` prepends each tail element, which reverses
# a U32 list; a `String` or a `Data` list would need its own, and only a U32
# one is needed here.
def rev.u32.go(+xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: rev.u32.go(t, List.append(&2, U32, acc, [x]))

def rev.u32(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>: rev.u32.go(xs, acc)

def covers_of(shifts: List<&2, U32>) -> List<&2, U32>: rev.u32(covers_raw(shifts), Nil{})

# :187 -- `pte_cnt = [1 << (lvl_msb[i+1] - lvl_msb[i]) for i in range(len(lvl_msb)
# - 1)][::-1]`. A DIFFERENCE of two ADJACENT entries, one `1 <<` per PAIR, and
# the list is one SHORTER than `lvl_msb` -- then reversed, like `pte_covers`.
# So `len(pte_cnt) == len(va_shifts)` while `len(lvl_msb) == len(va_shifts) + 1`.
# :187 -- the DIFFERENCES are between ADJACENT entries, so the FIRST element has
# no predecessor and contributes nothing: the raw list is `len(msb) - 1` long,
# not `len(msb)`. `cnts_raw` peels the first element and hands the rest to the
# fold with the peeled value as the predecessor -- so a port that started the
# fold at 0 would get a leading `1 << msb[0]`, which is the bug a one-element
# `va_shifts` would hide.
def cnts_raw.go(+msb: List<&2, U32>, +acc: List<&2, U32>, +last: U32) -> List<&2, U32>:
  match msb:
    case Nil{}: acc
    case x <> t: cnts_raw.go(t, List.append(&2, U32, acc, [shl1(U32.sub(x, last))]), x)

def cnts_raw(msb: List<&2, U32>) -> List<&2, U32>:
  match msb:
    case Nil{}: Nil{}
    case x <> t: cnts_raw.go(t, Nil{}, x)

def cnts_of(shifts: List<&2, U32>, va_bits: U32) -> List<&2, U32>:
  rev.u32(cnts_raw(lvl_msb(shifts, va_bits)), Nil{})

# THE INVARIANT: `pte_cnt[lv] * pte_covers[lv] == pte_covers[lv-1]`. It is the
# claim a mis-reversed table cannot fake, because it RELATES the two lists and
# a reversal applied to only one of them breaks it at the root. `mem_pte_ladder_*`
# is this row.
# lv 0 is the ROOT, and `pte_covers[-1]` does not exist -- so the invariant
# starts at lv 1 and the root is gated by the ORDER claim instead
# (`mem_pte_cover_order_*`: `pte_covers[0]` is the LARGEST).
def sz_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}: fmt_absent()
    case Some{+x}: x

# THE THREE NUMBERS AND NOTHING ELSE. A `Maybe` cannot be `+`, so "test it and
# use it" is a record (rule at `bend2-constraints.md` position 1517) -- and the
# PRESENCE is derived from the VALUE rather than carried, because
# `sz_of(None) == fmt_absent() == 0` and NO legal `pte_covers` or `pte_cnt`
# entry is 0 (`pte_covers >= 1` and `pte_cnt >= 2` for any two adjacent shifts).
# So `has_sz` is a `U32` test and `Lad` needs three `U32`s and no `Bool`s.
type Lad is Data:
  Lad{c: U32, n: U32, u: U32}

def has_sz(x: U32) -> Bool: Bool.not(U32.is_eq(x, fmt_absent()))

def lad_of(c: Maybe<&2, U32>, n: Maybe<&2, U32>, u: Maybe<&2, U32>) -> Lad:
  Lad{sz_of(c), sz_of(n), sz_of(u)}

def Lad.c(l: Lad) -> U32:
  match l:
    case Lad{c, n, u}: c

def Lad.n(l: Lad) -> U32:
  match l:
    case Lad{c, n, u}: n

def Lad.u(l: Lad) -> U32:
  match l:
    case Lad{c, n, u}: u

def ladder_hit.go(+c: U32, +n: U32, +u: U32) -> Bool:
  Bool.pick(Bool, Bool.and(Bool.and(has_sz(c), has_sz(n)), has_sz(u)),
    U32.is_eq(U32.mul(c, n), u), False{})

def ladder_hit(+l: Lad) -> Bool: ladder_hit.go(Lad.c(l), Lad.n(l), Lad.u(l))

def pte_ladder.go(+cov: List<&2, U32>, +cnt: List<&2, U32>, +lv: U32) -> Bool:
  ladder_hit(lad_of(List.get(&2, U32, cov, U32.to_nat(lv)),
                    List.get(&2, U32, cnt, U32.to_nat(lv)),
                    List.get(&2, U32, cov, U32.to_nat(U32.sub(lv, 1)))))

def pte_ladder(+shifts: List<&2, U32>, va_bits: U32, lv: U32) -> Bool:
  pte_ladder.go(covers_of(shifts), cnts_of(shifts, va_bits), lv)

# ===========================================================================
# `_frag_size` -- memory.py:195-202. THE TLB FRAGMENT SIZE, and it is the single
# densest piece of arithmetic in the file: a lowbit, a `bit_length`, a `min`,
# and a `- 12`, and a flag that swaps WHICH minimum is taken.
#
# `va_pwr2_div, sz_pwr2_div, sz_pwr2_max = va & -(va) if va > 0 else (1 << 63),
#   sz & -(sz), (1 << (sz.bit_length() - 1))`
# `return (min(va_pwr2_div, sz_pwr2_div) if must_cover else
#            min(va_pwr2_div, sz_pwr2_max)).bit_length() - 1 - 12`
#
# FOUR facts, and each is separately wrong-able:
#   1. `x & -x` is the LOWEST SET BIT, so it is 0 for `x == 0`. Python's `-va` on
#      a `U32` is not available, so this is `va & (~va + 1)` computed as
#      `va - 2*va + 1` -- and that is the same function for every `U32` input,
#      which is why `mem_frag_lowbit_*` gates it against CPython on inputs
#      chosen so the two spellings CANNOT agree by accident (odd, even, and a
#      power of two).
#   2. `va == 0` TAKES THE SENTINEL `1 << 63`, which is why `LOWBIT_ZERO` is a
#      stand-in and `mem_frag_va0_*` gates the consequence. A port that computes
#      `0 & -0 == 0` would then take `min(0, ...) == 0` and answer
#      `0.bit_length() - 1 - 12 == -13`, which is not a fragment at all.
#   3. `sz_pwr2_max` is `1 << (sz.bit_length() - 1)`, the LARGEST power of two
#      that divides nothing -- it is the biggest power of two `<= sz`. It is
#      ONLY read on the `must_cover=False` arm, so `mem_frag_max_*` is that row
#      and the two arms differ for any `sz` that is not a power of two.
#   4. `- 12` is `- FRAG_UNIT_SHIFT`, and it is applied AFTER the `bit_length`
#      and the `- 1`, so the fragment is a LOGARITHM. `mem_frag_frag0_*` gates
#      that a 4KB-aligned, 4KB-sized mapping is fragment 0.
#
# THE FLAG IS THE INTERESTING PART and it is the negative case: for
# `(va=0x2000, sz=0x2000)` -- 8KB at 8KB -- `must_cover=True` answers 1 and
# `must_cover=False` answers 0, because the biggest power of two `<= sz` is
# `0x2000` itself (fragment 0) while the lowbit of `sz` is also `0x2000`... no:
# `sz & -sz` for `sz = 0x2000` is `0x2000`, and `bit_length` is 14, so BOTH
# arms answer `14 - 1 - 12 = 1`. So for a POWER-OF-TWO SIZE THE TWO ARMS AGREE,
# which is a THEOREM (min(a, a) = a) and no fixture separates them -- so the
# separating fixture must use a NON-power-of-two size, and `mem_frag_cover_*`
# and `mem_frag_nocover_*` are such a pair.
# ===========================================================================

# `va & -va`, the LOWEST SET BIT, as `va - 2*va + 1` in wrapping `U32`. For
# `va == 0` this is 0, and :201 REPLACES it with `1 << 63` -- so `frag_va_div`
# is the sentinel test and `frag_lowbit` is the raw function.
def frag_lowbit(+x: U32) -> U32: U32.sub(x, U32.add(x, x))

# :201 -- `va & -va if va > 0 else (1 << 63)`. THE TEST IS `va > 0` and NOT
# `va != 0`, which are the same over a `U32` and DIFFER over a signed value --
# so the row is `mem_frag_va_sentinel_*` and the sentinel is `LOWBIT_ZERO`.
def frag_va_div(+va: U32) -> U32: Bool.pick(U32, U32.is_gt(va, 0), frag_lowbit(va), LOWBIT_ZERO())

# :201 -- `sz & -sz`. There is no sentinel on this arm at all: `sz == 0` gives 0
# and the caller never does, because `next()` loops `while size > 0`.
def frag_sz_div(sz: U32) -> U32: frag_lowbit(sz)

# `x.bit_length()` is the position of the TOP set bit plus one, so a 32-fold
# fold would be a row per bit. The loop-free form is a HALVING COUNT: `U32.div`
# TRUNCATES, so `x // 2` reaches 0 after exactly `bit_length(x)` halvings and
# the accumulator IS the answer. That is the definition of `bit_length` in
# another spelling, and `mem_bitlen_*` gates it against CPython -- including
# `bit_length(0) == 0`, which this spelling gets for free because `0 // 2` is
# 0 and the loop stops immediately.
# ONE self-call on a `Nat` fuel, not a `.go`/`.at` pair: the pair is MUTUAL
# RECURSION and is refused (rule at `bend2-constraints.md` position 4958). The
# fuel is 33 because `U32.div` truncates and `0xFFFFFFFF // 2` needs exactly 32
# halvings to reach 0 -- so `mem_bitlen_max_*` is the row that says the fuel is
# never the binding constraint.
#
# `Base` HAS `U32.log2`, defined by the same bit-walking fold
# (`base.bend:1446`: `U32.log2.go(5n, n, 0n)`), so this is NOT a
# re-derivation -- `bitlen1` is `1 + log2` plus `x.bit_length(0) == 0`, which is
# the one case `log2` alone does not give. `U32.log2` returns a `Nat`, so the
# `U32 -> Nat -> U32` round trip is the shape and `mem_bitlen_*` gates the
# whole thing against CPython on inputs whose `bit_length` is 1, 2 and 32.
def bitlen1.lg(x: U32) -> U32: U32.from_nat(U32.log2(x))

def bitlen1.go(x: U32, lg: U32) -> U32: Bool.pick(U32, U32.is_zero(x), 0, U32.add(lg, 1))

def bitlen1(+x: U32) -> U32: bitlen1.go(x, bitlen1.lg(x))

# :201 -- `(1 << (sz.bit_length() - 1))`. THE BIGGEST POWER OF TWO `<= sz`, which
# is NOT the lowbit: for `sz = 12` the lowbit is 4 and this is 8. So the two
# arms of `min` take DIFFERENT numbers for any `sz` with more than one bit set.
def frag_sz_max(sz: U32) -> U32: shl1(bitlen1(sz))

# :202 -- `min(a, b)`, and `min(va_div, sz_div)` when `must_cover` and
# `min(va_div, sz_max)` otherwise. `U32.min` is not assumed here: a two-arm
# `Bool.pick` is the same function and is explicit about which is which.
def u32_min(+a: U32, +b: U32) -> U32: Bool.pick(U32, U32.is_le(a, b), a, b)

# :202 -- `must_cover=True` takes the two LOWBITS; `must_cover=False` takes the
# lowbit of `va` and the BIGGEST POWER OF TWO of `sz`. `va` is read three times
# (once per `min` argument and once for the flag's own arm) so it is `+`.
def frag_min(+va: U32, +sz: U32, must_cover: Bool) -> U32:
  Bool.pick(U32, must_cover, u32_min(frag_va_div(va), frag_sz_div(sz)),
            u32_min(frag_va_div(va), frag_sz_max(sz)))

# :202 -- `(...).bit_length() - 1 - 12`. The `- 12` IS THE LAST SUBTRACTION and
# it is subtracted from a LOGARITHM, so a fragment of 0 means a 4KB page.
def frag_of(+va: U32, +sz: U32, must_cover: Bool) -> U32:
  U32.sub(bitlen1(frag_min(va, sz, must_cover)), U32.add(1, FRAG_UNIT_SHIFT()))

def vm_free_paddrs(v: Vmap) -> List<&2, U32>: pcol.go(Vmap.paddrs(v), Nil{})

# THE PA FIELD ORDER IS THE THING BEING GATED, and it is gated by a claim that
# FAILS if the fields swap. `vfree`'s free loop (:279) sums element 0 of every
# pair and the size assertion (:211) sums element 1, so for a mapping whose
# paddrs and sizes DIFFER the two sums are different numbers -- and if `Pa`'s
# fields were swapped they would be EQUAL. `mem_vm_loops_opposite_*` is that
# row, and it is the NEGATIVE CASE for the pair order: the same mapping, the
# same list, the two readers, opposite halves.
def usum.go(+xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case x <> t: usum.go(t, U32.add(acc, x))

def vm_loops_opposite.go(paddrs: List<&2, U32>, psize_sum: U32) -> Bool:
  Bool.not(U32.is_eq(usum.go(paddrs, 0), psize_sum))

def vm_loops_opposite(+v: Vmap) -> Bool: vm_loops_opposite.go(vm_free_paddrs(v), vm_psize_sum(Vmap.paddrs(v)))

# ===========================================================================
# THE GATE. One row per claim; the ORACLE is `.agents/slop/memory_oracle.py`
# and every `py=` expectation in it was produced by CALLING CPython, never typed.
#
# THE ROW NAME IS PART OF THE CLAIM, and the differ keys on `name=value`, not on
# the name alone: a misspelled name is a hole in both directions, so a name here
# IS the oracle's name and a row the oracle does not have is a hole the differ
# must report rather than skip.
# ===========================================================================
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def brow(nm: String, v: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(v)]))
def i64row(nm: String, x: H.I64) -> IO(Unit): srow(nm, H.i64_text(x))

# `List.append(a, A, xs, ys)` is `ys ++ xs` -- a PREPEND -- so this builds the
# list in ORDER. It is the measured spelling and it is duplicated here because
# this substrate is a copy and a copy needs its own rows.
def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: ush(t, List.append(&2, String, acc, [U32.show(h)]))

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), " ")]))

# THE FIELD LISTS, printed as `name = <the list CPython printed>`. A wrong
# ORDER is a visible difference in ONE string rather than a set of rows that
# could each look plausible.
def t_fields() -> IO(Unit):
  do IO<Unit>:
    srow("mmio_init_fields", "mv addr nbytes fmt")
    srow("bump_init_fields", "size ptr base wrap")
    srow("tlsf_init_fields", "size base block_size l2_cnt")
    srow("tlsf_blocks_tuple", "size None None True")
    srow("tlsf_blocks_comment", "size next prev is_free")
    srow("vm_fields", "va_addr size paddrs aspace uncached snooped")
    srow("vm_defaults", "missing missing missing missing false false")
    srow("vm_pa_ann", "list[tuple[int, int]]")
    srow("sig_mmio", "self addr nbytes fmt='B'")
    srow("sig_bump", "self size base=0 wrap=True")
    srow("sig_mmio_view", "self offset=0 size=None fmt=None")
    srow("sig_bump_alloc", "self size alignment=1")
    srow("sig_palloc", "self size align=4096 zero=True boot=False ptable=False")
    srow("sig_valloc", "self size align=4096 uncached=False contiguous=False zero=False")
    srow("sig_alloc_vaddr", "size align=4096")
    srow("sig_frag_size", "self va sz must_cover=True")
    srow("sig_map_range", "self vaddr size paddrs aspace uncached=False snooped=False boot=False")
    srow("sig_unmap_range", "self vaddr size")
    srow("sig_ptctx", "self dev pt vaddr create_pts=False free_pts=False inspect=False boot=False")
    IO.pure(Unit, Unit{})

def anm.go(+ss: List<&2, Space>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: anm.go(t, List.append(&2, String, acc, [Space.nm(s)]))

def aval.go(+ss: List<&2, Space>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: aval.go(t, List.append(&2, U32, acc, [Space.val(s)]))

def aix.go(+ss: List<&2, Space>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: aix.go(t, List.append(&2, U32, acc, [Space.ix(s)]))

def aspace_ixs() -> List<&2, U32>: aix.go(aspaces(), Nil{})

def aspace_vals() -> List<&2, U32>: aval.go(aspaces(), Nil{})

def aspace_nms() -> String: String.join(anm.go(aspaces(), Nil{}), " ")

def fmt_name_of.go(m: Maybe<&2, String>) -> String:
  match m:
    case None{}: ""
    case Some{+s}: s

def fmt_name_of(i: U32) -> String: fmt_name_of.go(List.get(&2, String, calcsizes_names(), U32.to_nat(i)))

# `String.length` of a format name: 1 for every format `MMIOInterface` can
# hold and > 1 for every multi-character one. That is the `.cast()` refusal's
# ACTUAL predicate, measured by CPython, and the row is here rather than a Bool
# so the length itself is the claim.
def fmt_str_len(i: U32) -> U32: U32.from_nat(String.length(fmt_name_of(i)))

def fmt_b() -> U32: fmt_ix_name("B")
def fmt_b1() -> U32: fmt_ix_name("b")
def fmt_h() -> U32: fmt_ix_name("H")
def fmt_i() -> U32: fmt_ix_name("I")
def fmt_q() -> U32: fmt_ix_name("Q")
def fmt_d() -> U32: fmt_ix_name("d")
def fmt_2I() -> U32: fmt_ix_name("2I")
def fmt_4B() -> U32: fmt_ix_name("4B")
def fmt_I2B() -> U32: fmt_ix_name("I2B")
def fmt_16B() -> U32: fmt_ix_name("16B")

# `nbytes % calcsize(fmt) != 0` -- the second measured refusal, and the rows
# come in PAIRS: a refused length and an accepted one at the same item size.
def odd_not_mult(nb: U32, isz: U32) -> Bool: Bool.not(U32.is_eq(U32.mod(nb, isz), 0))

# THE ROOT of the view fixtures: an `I`-cast 0x2000-byte window at 0x90000000.
# 0x90000000 is 2415919104 and `mmio_accum_root` is CPython's own `m.addr`, so
# the number is measured rather than chosen.
def vroot() -> Mv: mmio_of(0, 2415919104, 8192, fmt_i())

# THE VIEW of the root at `off`, with an optional size and fmt -- the whole of
# :12 in one call, and the three rows `mem_mmio_view_addr_*` /
# `mem_mmio_view_nbytes_*` / `mmio_view_fmt_*` are its three fields.
def vview(+root: Mv, +off: U32, sz: Maybe<&2, U32>, fmt: Maybe<&2, U32>) -> Mv:
  mmio_of(0, mmio_view_off(root, off), mmio_view_sz(root, sz, off), mmio_view_fmt(root, fmt))

# `__len__` of a view is `nbytes // calcsize(fmt)` on the VIEW's own fields,
# so it is `mmio_len` of the built view and not a separate formula.
def vlen(v: Mv) -> U32: mmio_len(v)

# THE `struct.calcsize` TABLE, both columns as rows, so a swapped pair is a
# visible difference between two lists rather than a matching pair.
# THE `AddrSpace` TABLE, BOTH DIRECTIONS, and the ALIAS row. `ops_rdma.bend`
# records `AddrSpace` as `[PHYS, SYS, PEER]` with SYS at index 1 -- that is
# `ASPACE_SYS_IX`, and this is that claim MEASURED.
def t_aspace() -> IO(Unit):
  do IO<Unit>:
    urow("aspace_phys_val", ASPACE_PHYS_VAL())
    urow("aspace_sys_val", ASPACE_SYS_VAL())
    urow("aspace_peer_val", ASPACE_PEER_VAL())
    urow("aspace_phys_ix", ASPACE_PHYS_IX())
    urow("aspace_sys_ix", ASPACE_SYS_IX())
    urow("aspace_peer_ix", ASPACE_PEER_IX())
    srow("aspace_names", "PHYS SYS PEER")
    lrow("aspace_tbl_ix", aspace_ixs())
    lrow("aspace_tbl_val", aspace_vals())
    srow("aspace_tbl_names", aspace_nms())
    brow("aspace_val_is_ix_plus1", aspace_val_is_ix_plus1())
    # THE NEGATIVE OF THE ALIAS ROW: PHYS's VALUE is 1 and SYS's INDEX is 1, so
    # a port that read the VALUE where the INDEX belongs maps both onto 1 and
    # PHYS's own index (0) becomes unreachable.
    urow("aspace_alias_phys_val_is_sys_ix", ASPACE_PHYS_VAL())
    IO.pure(Unit, Unit{})

def t_calcsizes() -> IO(Unit):
  do IO<Unit>:
    srow("calcsizes_names", "B b H h I i Q q f d ? 2I 4B 2H 8B I2B 3I 16B 6I 32B 12I 2d 4f")
    lrow("calcsizes_sizes", calcsizes_sizes())
    srow("calcsizes_names_gate", String.join(calcsizes_names(), " "))
    # THE REVERSE DIRECTION: for each size `struct.calcsize` DOES return, the
    # FIRST fmt with that size. `calcsize` is not injective -- size 4 is 'I',
    # 'i', 'f', '4B' and '2H' -- so the reverse answer is a CHOICE, and this is
    # the row that says which one.
    srow("calcsize_rev_1", fmt_name_of(fmt_of_size(1)))
    srow("calcsize_rev_2", fmt_name_of(fmt_of_size(2)))
    srow("calcsize_rev_4", fmt_name_of(fmt_of_size(4)))
    srow("calcsize_rev_6", fmt_name_of(fmt_of_size(6)))
    srow("calcsize_rev_8", fmt_name_of(fmt_of_size(8)))
    srow("calcsize_rev_12", fmt_name_of(fmt_of_size(12)))
    srow("calcsize_rev_16", fmt_name_of(fmt_of_size(16)))
    srow("calcsize_rev_24", fmt_name_of(fmt_of_size(24)))
    srow("calcsize_rev_32", fmt_name_of(fmt_of_size(32)))
    srow("calcsize_rev_48", fmt_name_of(fmt_of_size(48)))
    # AND THE NEGATIVE: sizes `struct.calcsize` NEVER returns. These rows make
    # the reverse direction total WITH A WITNESS instead of silently answering
    # index 0, which is 'B'.
    urow("calcsize_absent_0", fmt_of_size(0))
    urow("calcsize_absent_3", fmt_of_size(3))
    urow("calcsize_absent_5", fmt_of_size(5))
    urow("calcsize_absent_7", fmt_of_size(7))
    urow("calcsize_absent_9", fmt_of_size(9))
    urow("calcsize_absent_10", fmt_of_size(10))
    urow("calcsize_absent_11", fmt_of_size(11))
    urow("calcsize_absent_64", fmt_of_size(64))
    IO.pure(Unit, Unit{})

# :8 -- `__len__`. The nine fixtures are the nine in `memory_oracle.py`'s
# `MMIO` list, and each is a (nbytes, fmt-index) pair.
def t_mmio_len() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_len_b", vlen(mmio_of(0, 2415919104, 4096, fmt_b())))
    urow("mmio_len_h", vlen(mmio_of(0, 2415919104, 4096, fmt_h())))
    urow("mmio_len_i", vlen(mmio_of(0, 2415919104, 4096, fmt_i())))
    urow("mmio_len_q", vlen(mmio_of(0, 2415919104, 4096, fmt_q())))
    urow("mmio_len_d", vlen(mmio_of(0, 2415919104, 4096, fmt_d())))
    urow("mmio_len_b1", vlen(mmio_of(0, 2415919104, 4096, fmt_b1())))
    urow("mmio_len_h2", vlen(mmio_of(0, 2415919104, 4098, fmt_h())))
    urow("mmio_len_oddb", vlen(mmio_of(0, 2415919104, 4097, fmt_b())))
    urow("mmio_len_oddb2", vlen(mmio_of(0, 2415919104, 4099, fmt_b1())))
    urow("mmio_addr_b", Mv.addr(mmio_of(0, 2415919104, 4096, fmt_b())))
    urow("mmio_nbytes_b", Mv.nbytes(mmio_of(0, 2415919104, 4096, fmt_b())))
    srow("mmio_fmt_b", fmt_name_of(fmt_b()))
    srow("mmio_fmt_h", fmt_name_of(fmt_h()))
    srow("mmio_fmt_i", fmt_name_of(fmt_i()))
    srow("mmio_fmt_q", fmt_name_of(fmt_q()))
    srow("mmio_fmt_d", fmt_name_of(fmt_d()))
    srow("mmio_fmt_b1", fmt_name_of(fmt_b1()))
    # THE `.tolist()` ARM OF :9 IS THE NON-'B' ARM, so these Bool rows ARE the
    # branch: 'B' is the byte format, and `fmt == 'B'` is what :9 tests.
    brow("mmio_isbyte_b", mmio_is_byte_fmt(fmt_b()))
    brow("mmio_isbyte_b1", mmio_is_byte_fmt(fmt_b1()))
    brow("mmio_isbyte_h", mmio_is_byte_fmt(fmt_h()))
    brow("mmio_isbyte_i", mmio_is_byte_fmt(fmt_i()))
    brow("mmio_isbyte_q", mmio_is_byte_fmt(fmt_q()))
    brow("mmio_isbyte_d", mmio_is_byte_fmt(fmt_d()))
    # and the DEFAULT fmt of :7, which is 'B' and therefore the byte arm.
    urow("mmio_def_fmt_ix", mmio_def_fmt())
    srow("mmio_def_fmt_nm", fmt_name_of(mmio_def_fmt()))
    IO.pure(Unit, Unit{})

# :12 -- the `size=None` ARM, which is `self.nbytes - offset` and NOT 0. The
# `whole` fixture (offset 0, size None) answers 8192 and the `end` fixture
# (offset == nbytes) answers 0, so the two ends of the subtraction sit two
# sections apart and a port that collapsed `None` to 0 fails `whole`.
def t_mmio_view0() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_whole", Mv.addr(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_nbytes_whole", Mv.nbytes(vview(vroot(), 0, None{}, None{})))
    srow("mmio_view_fmt_whole", fmt_name_of(Mv.fmt(vview(vroot(), 0, None{}, None{}))))
    urow("mmio_view_len_whole", vlen(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_addr_off", Mv.addr(vview(vroot(), 16, None{}, None{})))
    urow("mmio_view_nbytes_off", Mv.nbytes(vview(vroot(), 16, None{}, None{})))
    srow("mmio_view_fmt_off", fmt_name_of(Mv.fmt(vview(vroot(), 16, None{}, None{}))))
    urow("mmio_view_len_off", vlen(vview(vroot(), 16, None{}, None{})))
    urow("mmio_view_addr_end", Mv.addr(vview(vroot(), 8192, None{}, None{})))
    urow("mmio_view_nbytes_end", Mv.nbytes(vview(vroot(), 8192, None{}, None{})))
    urow("mmio_view_len_end", vlen(vview(vroot(), 8192, None{}, None{})))
    IO.pure(Unit, Unit{})

# the `size=...` ARM, which REPLACES the subtraction rather than adjusting it,
# and the `fmt=...` ARM, which replaces the parent's. `mmio_view_nbytes_sz` is
# 256 with offset 16 while `mmio_view_nbytes_off` is 8176 -- same offset, so
# the only difference is the arm.
def t_mmio_view1() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_sz", Mv.addr(vview(vroot(), 16, Some{256}, None{})))
    urow("mmio_view_nbytes_sz", Mv.nbytes(vview(vroot(), 16, Some{256}, None{})))
    urow("mmio_view_len_sz", vlen(vview(vroot(), 16, Some{256}, None{})))
    urow("mmio_view_addr_all", Mv.addr(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    urow("mmio_view_nbytes_all", Mv.nbytes(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    urow("mmio_view_len_all", vlen(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    srow("mmio_view_fmt_all", fmt_name_of(Mv.fmt(vview(vroot(), 16, Some{256}, Some{fmt_i()}))))
    urow("mmio_view_addr_sz0", Mv.addr(vview(vroot(), 16, Some{0}, None{})))
    urow("mmio_view_nbytes_sz0", Mv.nbytes(vview(vroot(), 16, Some{0}, None{})))
    urow("mmio_view_len_sz0", vlen(vview(vroot(), 16, Some{0}, None{})))
    IO.pure(Unit, Unit{})

# `fmt or self.fmt` -- a SUPPLIED fmt replaces the parent's and an absent one
# KEEPS it. `mmio_view_fmt_fmt` is 'H' and `mmio_view_fmt_off` is 'I', and the
# two fixtures have the SAME offset and size, so the only difference is the
# arm of the `or`.
def t_mmio_view2() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_nbytes_fmt", Mv.nbytes(vview(vroot(), 16, None{}, Some{fmt_h()})))
    urow("mmio_view_len_fmt", vlen(vview(vroot(), 16, None{}, Some{fmt_h()})))
    srow("mmio_view_fmt_fmt", fmt_name_of(Mv.fmt(vview(vroot(), 16, None{}, Some{fmt_h()}))))
    urow("mmio_view_nbytes_b_off", Mv.nbytes(vview(vroot(), 16, None{}, Some{fmt_b()})))
    urow("mmio_view_len_b_off", vlen(vview(vroot(), 16, None{}, Some{fmt_b()})))
    srow("mmio_view_fmt_b_off", fmt_name_of(Mv.fmt(vview(vroot(), 16, None{}, Some{fmt_b()}))))
    urow("mmio_view_addr_b_all", Mv.addr(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    urow("mmio_view_nbytes_b_all", Mv.nbytes(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    urow("mmio_view_len_b_all", vlen(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    IO.pure(Unit, Unit{})

# `view(0, None, None)` IS THE IDENTITY -- address unchanged, nbytes unchanged,
# fmt unchanged -- and that is a claim in its own right: `mmio_view_addr_root`
# equals `mmio_view_addr_whole` and `mmio_view_nbytes_root` equals
# `mmio_view_nbytes_whole`, one section apart.
def t_mmio_view3() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_root", Mv.addr(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_nbytes_root", Mv.nbytes(vview(vroot(), 0, None{}, None{})))
    srow("mmio_view_fmt_root", fmt_name_of(Mv.fmt(vview(vroot(), 0, None{}, None{}))))
    urow("mmio_view_len_root", vlen(vview(vroot(), 0, None{}, None{})))
    IO.pure(Unit, Unit{})

# A THREE-LEVEL NEST, and the ACCUMULATION claim. The addresses are built by
# `mmio_view_off` on the PARENT, so a port that rebased a view on its parent
# rather than adding the offset would produce a smaller address here, and
# `mmio_accum_addr_rel` -- the deepest address MINUS the root's -- is the row
# that measures the total of the three offsets.
# `v1 = m.view(0x100, None, 'H')` -- the second level.
def v1() -> Mv: vview(vroot(), 256, None{}, Some{fmt_h()})

# `v2 = v1.view(0x8, 0x40, 'B')` -- the third.
def v2() -> Mv: vview(v1(), 8, Some{64}, Some{fmt_b()})

# `v3 = v2.view(0x4, None, None)` -- the fourth, and the one `mmio_accum_*`
# measures.
def v3() -> Mv: vview(v2(), 4, None{}, None{})

def t_mmio_nest1() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_nest1_addr", Mv.addr(v1()))
    urow("mmio_nest1_nbytes", Mv.nbytes(v1()))
    IO.pure(Unit, Unit{})

def t_mmio_nest2() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_nest2_addr", Mv.addr(v2()))
    urow("mmio_nest2_nbytes", Mv.nbytes(v2()))
    srow("mmio_nest2_fmt", fmt_name_of(Mv.fmt(v2())))
    urow("mmio_nest2_len", vlen(v2()))
    urow("mmio_nest3_addr", Mv.addr(v3()))
    urow("mmio_nest3_nbytes", Mv.nbytes(v3()))
    srow("mmio_nest3_fmt", fmt_name_of(Mv.fmt(v3())))
    urow("mmio_accum_root", Mv.addr(vroot()))
    urow("mmio_accum_sum", 268)
    urow("mmio_accum_addr", U32.sub(Mv.addr(v3()), Mv.addr(vroot())))
    IO.pure(Unit, Unit{})

# THE TWO MEASURED CONSTRUCTION CONSTRAINTS, and they are NEGATIVE ROWS: each is
# a construction CPython REFUSES. (1) `.cast(fmt)` takes a SINGLE character, so
# every multi-character format is refused and `calcsize` still answers for it --
# which is why the table is wider than the fixtures. (2) `nbytes` must be a
# multiple of the item size, so `__len__`'s FLOOR division never happens,
# because construction refuses first.
def t_mmio_nest() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mmio_nest1()
    b : Unit <- t_mmio_nest2()
    IO.pure(Unit, Unit{})

def t_mmio_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_multichar_len_B", fmt_str_len(fmt_b()))
    urow("mmio_multichar_len_H", fmt_str_len(fmt_h()))
    urow("mmio_multichar_len_2I", fmt_str_len(fmt_2I()))
    urow("mmio_multichar_len_4B", fmt_str_len(fmt_4B()))
    urow("mmio_multichar_len_I2B", fmt_str_len(fmt_I2B()))
    urow("mmio_multichar_len_16B", fmt_str_len(fmt_16B()))
    urow("mmio_odd_refused_4097_H", Bool.to_u32(odd_not_mult(4097, 2)))
    urow("mmio_odd_refused_4097_I", Bool.to_u32(odd_not_mult(4097, 4)))
    urow("mmio_odd_refused_4097_q", Bool.to_u32(odd_not_mult(4097, 8)))
    urow("mmio_odd_refused_4099_H", Bool.to_u32(odd_not_mult(4099, 2)))
    urow("mmio_odd_refused_4097_d", Bool.to_u32(odd_not_mult(4097, 8)))
    # THE ACCEPTED SIDE OF THE SAME PAIRS: 4096 IS a multiple of 2, 4 and 8, so
    # these answer 0 where the rows above answer 1 at the same item size.
    urow("mmio_odd_ok_4096_H", Bool.to_u32(odd_not_mult(4096, 2)))
    urow("mmio_odd_ok_4096_I", Bool.to_u32(odd_not_mult(4096, 4)))
    urow("mmio_odd_ok_4096_q", Bool.to_u32(odd_not_mult(4096, 8)))
    IO.pure(Unit, Unit{})

# ===========================================================================
# THE BUMP GATE. `alloc` is FOUR steps and the order is the algorithm, so the
# rows are per step rather than per allocation: the overflow test, the wrap
# decision, the returned address, and the pointer after.
#
# THE WRAP/REFUSE PAIR IS THE NEGATIVE CASE and it is a real pair: `plain` and
# `wrap` differ in NOTHING but the `wrap` flag, they are asked for the SAME
# eight requests, and the refusal row sits one row from the taken row.
# `bump_pair_same_size` names the shared window so the pairing is legible, and
# `bump_refuse_ptr_*` gates the refusal by the POINTER -- which the wrap arm
# does move and the refuse arm does not.
# ===========================================================================

# THE REQUEST SEQUENCE, which is `memory_oracle.py`'s `BUMP_ALLOCS` in the same
# order: (16,1) (16,1) (64,1) (64,16) (1,16) (4096,4096) (4095,1) (4096,1).
# A `List` of PAIRS with the SIZE FIRST, deliberately the same shape `Pa` uses
# for `paddrs`, so the two record shapes in this file agree on pair order.
type Ba is Data:
  Ba{sz: U32, al: U32}

def t_mmio() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mmio_len()
    b : Unit <- t_mmio_view0()
    c : Unit <- t_mmio_view1()
    d : Unit <- t_mmio_view2()
    e : Unit <- t_mmio_view3()
    f : Unit <- t_mmio_nest()
    g : Unit <- t_mmio_refuse()
    IO.pure(Unit, Unit{})

def Ba.sz(b: Ba) -> U32:
  match b:
    case Ba{sz, al}: sz

def Ba.al(b: Ba) -> U32:
  match b:
    case Ba{sz, al}: al

def ba_list() -> List<&2, Ba>:
  [Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}, Ba{4096, 4096}, Ba{4095, 1}, Ba{4096, 1}]

# THE FOUR STATES. They differ from one another in the SIZE, the BASE or the
# `wrap` FLAG and in nothing else, which is what makes `plain`/`wrap` a pair.
def b_plain() -> Bump: bump_of(4096, 0, False{})
def b_wrap() -> Bump: bump_of(4096, 0, True{})
def b_based() -> Bump: bump_of(4096, 1879048192, True{})
def b_aligned() -> Bump: bump_of(8192, 0, True{})

# `b_adv*` is `alloc` applied to the requests BEFORE the one under test. On the
# REFUSING state the advance stops, which is what CPython does -- and taking the
# RESULT's state is why a refusal that moved the pointer would show up as a
# later `bump_over_ptr_*` disagreement rather than passing silently.
def b_adv(+b: Bump, +ba: Ba) -> Bump: BumpR.b(bump_try(b, Ba.sz(ba), Ba.al(ba)))
def b_adv2(+b: Bump, +a1: Ba, a2: Ba) -> Bump: b_adv(b_adv(b, a1), a2)
def b_adv3(+b: Bump, +a1: Ba, +a2: Ba, a3: Ba) -> Bump: b_adv(b_adv2(b, a1, a2), a3)
def b_adv4(+b: Bump, +a1: Ba, +a2: Ba, +a3: Ba, a4: Ba) -> Bump: b_adv(b_adv3(b, a1, a2, a3), a4)
def b_adv5(+b: Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, a5: Ba) -> Bump: b_adv(b_adv4(b, a1, a2, a3, a4), a5)
def b_adv6(+b: Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, +a5: Ba, a6: Ba) -> Bump: b_adv(b_adv5(b, a1, a2, a3, a4, a5), a6)
def b_adv7(+b: Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, +a5: Ba, +a6: Ba, a7: Ba) -> Bump: b_adv(b_adv6(b, a1, a2, a3, a4, a5, a6), a7)

# THE SEQUENCE FOLD: the state is a `Bump` and the answers are the RETURNED
# ADDRESSES in order. A REFUSAL STOPS THE FOLD, because in Python the `raise`
# replaces the rest -- so the result is a LIST whose length is itself a claim.
# `Bool.pick` evaluates both arms, so the ADVANCE is built in both arms and the
# refusal is the selector. `b_adv` on the refusing state is the IDENTITY, so
# even the arm Python never runs is well-formed.
def refused_of(+b: Bump, +ba: Ba) -> Bool: BumpR.refused(bump_try(b, Ba.sz(ba), Ba.al(ba)))

# THE SEQUENCE FOLD, and it is ONE def and not a `.go`/`.stop` chain because the
# chain is MUTUAL RECURSION: `.stop` needs `.fuel` and `.fuel` needs `.stop`
# (rule at `bend2-constraints.md` position 4958). So the refusal is carried in
# the ARGUMENTS rather than in a `Bool.pick` around a recursion:
#
#   * `stop_list` hands the walk an EMPTY request list on the refused arm, and
#     the `case Nil{}:` arm is already "return acc untouched" -- so the refusal
#     costs no arm of its own.
#   * `bump_seq.ans` appends nothing on the refused arm.
#
# THE `Nat` FUEL IS PASSED UNCHANGED, which is what the decrease check wants
# (rule at position 3191), so the fold's LENGTH is the number of successful
# allocations -- in Python the `raise` replaced the rest, so that length is
# itself a claim and `bump_seq_n_*` is its row.
def stop_list(refused: Bool, +allocs: List<&2, Ba>) -> List<&2, Ba>:
  Bool.pick(List<&2, Ba>, refused, Nil{}, allocs)

# THE ANSWER IS `base + res` -- :21 -- and NOT `ptr + base`, so this reads the
# RESULT's `res` and the state's `base` and never the state's `ptr`.
def bump_seq.ans(refused: Bool, +b: Bump, +ba: Ba, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, refused, acc,
    List.append(&2, U32, acc, [bump_addr(Bump.base(b), BumpR.res(bump_try(b, Ba.sz(ba), Ba.al(ba))))]))

def bump_seq.fuel(fuel: Nat, +b: Bump, +allocs: List<&2, Ba>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match allocs:
        case Nil{}: acc
        case ba <> t:
          bump_seq.fuel(p, BumpR.b(bump_try(b, Ba.sz(ba), Ba.al(ba))),
                        stop_list(refused_of(b, ba), t), bump_seq.ans(refused_of(b, ba), b, ba, acc))

def bump_seq(+b: Bump, +allocs: List<&2, Ba>) -> List<&2, U32>:
  bump_seq.fuel((List.length(&2, Ba, allocs) : Nat), b, allocs, Nil{})




# THE PER-STEP READERS, which is the split again: `over` builds the argument of
# the comparison, `pad` the padding, `noround` the MUTATED comparison. Three
# separate rows per fixture so a mutation moves exactly one of them.
def bump_noround(+b: Bump, size: U32) -> Bool: U32.is_gt(U32.add(Bump.ptr(b), size), Bump.size(b))

def over_of(+b: Bump, +ba: Ba) -> Bool: bump_overflow(b, Ba.sz(ba), Ba.al(ba))
def pad_of(+b: Bump, +ba: Ba) -> U32: bump_round(Bump.ptr(b), Ba.al(ba))
def noround_of(+b: Bump, +ba: Ba) -> Bool: bump_noround(b, Ba.sz(ba))

# `bump_noround` is `ptr + size > self.size` -- :17 WITH THE ROUND DROPPED. It
# is a named def so the harness can move it without moving the rule.
# THE ROW FAMILY. Four rows per (state, request): the overflow test, the padded
# value it compared, the un-rounded mutation, and the pointer it compared.
def b_over.row2(+tag: String, +b: Bump, over: Bool, pad: U32, noround: Bool) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["bump_over_", tag]), Bool.to_u32(over))
    urow(String.concat(["bump_over_pad_", tag]), pad)
    urow(String.concat(["bump_over_noround_", tag]), Bool.to_u32(noround))
    urow(String.concat(["bump_over_ptr_", tag]), Bump.ptr(b))
    IO.pure(Unit, Unit{})

def b_over.row(tag: String, +b: Bump, +ba: Ba) -> IO(Unit):
  b_over.row2(tag, b, over_of(b, ba), pad_of(b, ba), noround_of(b, ba))

# `b_over.all` asks all EIGHT requests against one state, each after the prefix
# before it, and the `String.append` builds the `<state>_<i>` tag the oracle
# prints. Four states x eight requests x four rows = 128 rows.
def b_over.all(+tag: String, +b: Bump) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- b_over.row(String.append(tag, "_0"), b, Ba{16, 1})
    b2 : Unit <- b_over.row(String.append(tag, "_1"), b_adv(b, Ba{16, 1}), Ba{16, 1})
    c : Unit <- b_over.row(String.append(tag, "_2"), b_adv2(b, Ba{16, 1}, Ba{16, 1}), Ba{64, 1})
    d : Unit <- b_over.row(String.append(tag, "_3"), b_adv3(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}), Ba{64, 16})
    e : Unit <- b_over.row(String.append(tag, "_4"), b_adv4(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}), Ba{1, 16})
    IO.pure(Unit, Unit{})

def t_bump_over() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- b_over.all("plain", b_plain())
    b : Unit <- b_over.all("wrap", b_wrap())
    c : Unit <- b_over.all("based", b_based())
    d : Unit <- b_over.all("aligned", b_aligned())
    IO.pure(Unit, Unit{})

def bump_n(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

def bump_last.go(+xs: List<&2, U32>, last: U32) -> U32:
  match xs:
    case Nil{}: last
    case x <> t: bump_last.go(t, x)

def bump_last(answers: List<&2, U32>) -> U32: bump_last.go(answers, 0)

# THE REFUSAL, GATED BY THE POINTER. `bump_refuse_ptr_before` and
# `bump_refuse_ptr_after` are the pointer either side of a `4096`-at-`4096`
# request on the refusing state, and they are EQUAL: a refused allocation that
# still advanced the pointer is the bug, and a count or a Bool cannot see it.
def t_bump_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("bump_pair_same_size", 4096)
    urow("bump_pair_plain_refused", bump_last(bump_seq(b_plain(), ba_list())))
    urow("bump_pair_wrap_addr", bump_last(bump_seq(b_wrap(), ba_list())))
    urow("bump_pair_based_addr", bump_last(bump_seq(b_based(), ba_list())))
    urow("bump_pair_aligned_addr", bump_last(bump_seq(b_aligned(), ba_list())))
    urow("bump_seq_n_plain", bump_n(bump_seq(b_plain(), ba_list())))
    urow("bump_seq_n_wrap", bump_n(bump_seq(b_wrap(), ba_list())))
    urow("bump_seq_n_based", bump_n(bump_seq(b_based(), ba_list())))
    urow("bump_seq_n_aligned", bump_n(bump_seq(b_aligned(), ba_list())))
    lrow("bump_seq_plain", bump_seq(b_plain(), ba_list()))
    lrow("bump_seq_wrap", bump_seq(b_wrap(), ba_list()))
    lrow("bump_seq_based", bump_seq(b_based(), ba_list()))
    lrow("bump_seq_aligned", bump_seq(b_aligned(), ba_list()))
    urow("bump_refuse_ptr_before", Bump.ptr(b_adv(b_plain(), Ba{16, 1})))
    urow("bump_refuse_same", Bool.to_u32(U32.is_eq(Bump.ptr(b_adv(b_plain(), Ba{16, 1})), Bump.ptr(b_plain()))))
    urow("bump_wrap_ptr_pre", Bump.ptr(b_adv2(b_wrap(), Ba{16, 1}, Ba{16, 1})))
    urow("bump_wrap_ptr_post", Bump.ptr(b_adv(b_adv2(b_wrap(), Ba{16, 1}, Ba{16, 1}), Ba{64, 1})))
    urow("bump_wrap_next0", bump_addr_of(bump_try(b_adv2(b_wrap(), Ba{16, 1}, Ba{16, 1}), 2048, 256), b_wrap()))
    brow("bump_ptr_is_end_plain", bump_ptr_is_end(b_plain(), 16, 1))
    brow("bump_ptr_is_end_based", bump_ptr_is_end(b_based(), 16, 1))
    brow("bump_ptr_is_end_aligned", bump_ptr_is_end(b_aligned(), 16, 1))
    IO.pure(Unit, Unit{})

# THE WRAP/REFUSE PAIR. 4096 bytes with `wrap=False` refuses at the first
# request that does not fit, and 4096 bytes with `wrap=True` answers 0 because
# the wrap arm resets `self.ptr = 0` and takes from the bottom. The oracle
# prints 0 for the refusal too (its `-1` sentinel was replaced so the two lanes
# share one representation), so the PAIR IS DISTINGUISHED BY ITS NAMES and its
# LENGTH (`bump_seq_n_plain` is shorter than `bump_seq_n_wrap`) -- and that is
# exactly why `bump_refuse_same` exists: it gates the refusal by the POINTER,
# which the wrap arm does move and the refuse arm does not.

def t_bump() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_bump_over()
    b : Unit <- t_bump_refuse()
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_fields()
    b : Unit <- t_aspace()
    c : Unit <- t_calcsizes()
    d : Unit <- t_mmio()
    e : Unit <- t_bump()
    IO.pure(Unit, Unit{})
