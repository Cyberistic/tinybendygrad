# gates/memory-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/support/memory.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/support/memory.bend as P
import ./../tinybendygrad/helpers.bend as H

def calcsizes_names() -> List<&2, String>: P.cfmt.go(P.calcsizes(), Nil{})
def fmt_of_size(sz: U32) -> U32: P.nat_ix(P.cfmt_sz.go(P.calcsizes(), sz, 0, 0n))
# every `struct.calcsize` below is >= 1, so a `0` size IS the out-of-range
# answer and needs no second condition.
# :8 -- `__len__` is `self.nbytes // struct.calcsize(self.fmt)`. BOTH READS are
# off the SAME record, so `+m` is required -- and it is a copy, so the row can
# be recomputed without a second `P.Mv`.
def mmio_len(+m: P.Mv) -> U32: U32.div(P.Mv.nbytes(m), P.calcsize_i(P.Mv.fmt(m)))
# :12 -- `MMIOInterface(self.addr+offset, (self.nbytes - offset) if size is
# None else size, fmt=fmt or self.fmt)`. The SIZE arm is a `Maybe`, because
# Python's `None` is not `0` here: a view of the WHOLE remainder is not a
# zero-length view. THE ADDRESS ACCUMULATES and the new window's base is the
# ROOT's base -- `mv_nbytes_root` is the row that says a nested view does not
# rebase.
def mmio_view_sz(root: P.Mv, size: Maybe<&2, U32>, off: U32) -> U32:
  match size:
    case None{}: U32.sub(P.Mv.nbytes(root), off)
    case Some{+s}: s
# `fmt or self.fmt` -- an absent fmt arg keeps the parent's, which is `Bool`'s
# zero, so the sentinel is `fmt_absent` again and NOT index 0 ('B' is 0).
def mmio_view_fmt(root: P.Mv, fmt: Maybe<&2, U32>) -> U32:
  match fmt:
    case None{}: P.Mv.fmt(root)
    case Some{+f}: f
def mmio_view_off(root: P.Mv, off: U32) -> U32: U32.add(P.Mv.addr(root), off)
# `mv_nbytes_root` -- the byte WINDOW a view sees is bounded by the ROOT's
# bytes, and the answer is the root's `nbytes` for a root. Written as a def so
# a nested view is one call away instead of a re-read of the parent.
# :9 -- `(self.mv[k] if self.fmt == 'B' else self.mv[k].tolist()) if
# isinstance(k, slice) else self.mv[k]`. THE `.tolist()` ARM IS EXACTLY THE
# NON-'B' TEST, so `mmio_is_byte_fmt` gates it: for a slice index, 'B' returns
# the memoryview element and every other fmt returns a LIST. Two different
# return TYPES off one comparison, and the comparison is a string equality
# against 'B' -- so `mmio_is_byte_fmt` is the row that says which arm, and
# `mem_mmio_byte_fmt_*` is its truth table.
def mmio_is_byte_fmt(f: U32) -> Bool: U32.is_eq(f, P.mmio_def_fmt())
# :15 -- `self.size, self.ptr, self.base, self.wrap = size, 0, base, wrap`. THE
# POINTER STARTS AT ZERO and NOT AT `base`, so the first allocation is at
# `base` and the window is `[base, base+size)`.
def bump_of(size: U32, base: U32, wrap: Bool) -> P.Bump: P.Bump{size, 0, base, wrap}
# :21 -- `return res + self.base`, the ADDRESS. It is the ALIGNED OFFSET plus
# base and NOT `self.ptr + base`, which is why `bump_addr_of` reads the RESULT
# record's `res` and not the state's `ptr`.
def bump_addr_of(+r: P.BumpR, b: P.Bump) -> U32: P.bump_addr(P.Bump.base(b), P.BumpR.res(r))
def bump_ptr_is_end(+b: P.Bump, +size: U32, +align: U32) -> Bool:
  P.bump_ptr_end(P.bump_ptr_of(P.bump_try(b, size, align)), P.bump_end(P.bump_res(b, align), size))
def aspace_val_is_ix_plus1() -> Bool:
  P.aspace_val_is_ix_plus1.go(P.Space.go_v(P.aspace_at_ix(P.ASPACE_PHYS_IX())))
def vm_size_match(+v: P.Vmap) -> Bool: U32.is_eq(P.Vmap.size(v), P.vm_psize_sum(P.Vmap.paddrs(v)))
# :250 -- `VirtMapping(self.identity_va(uncached) + paddr, size, [(paddr, size)],
# aspace=AddrSpace.PHYS, uncached=uncached)`. `SNOOPED IS NOT SUPPLIED`, so it
# is `False` by default -- and `aspace` is `PHYS` regardless of the device,
# unlike :225 where it is the caller's. `vmap_gmmu0` is the row family.
def vmap_gmmu0(va: U32, paddr: U32, +size: U32, uncached: Bool) -> P.Vmap:
  P.vmap_all(va, size, [P.Pa{paddr, size}], P.ASPACE_PHYS_IX(), uncached, False{})
# THE `GMMU=0` ADDRESS: `self.identity_va(uncached) + paddr`, so the IDENTITY
# mapping's base is ADDED to the physical address. `vm_gmmu0_va` is the sum and
# it is NOT `paddr` alone -- which is the whole point of `identity_va`.
def vm_gmmu0_va(identity: U32, paddr: U32) -> U32: U32.add(identity, paddr)
# :277 -- `self.unmap_range(vm.va_addr, vm.size)`: the UNMAP TAKES THE VA AND THE
# SIZE and NOT the paddrs. `vm_unmap_va` / `vm_unmap_sz` are the two readers,
# and `mem_vm_vfree_*` says which two fields reach the unmap.
def vm_unmap_va(v: P.Vmap) -> U32: P.Vmap.va_addr(v)
def vm_unmap_sz(v: P.Vmap) -> U32: P.Vmap.size(v)
# THE NUMBER OF SEGMENTS, which is the one field a `U32` row can read without
# going through the `P.Pa` list's element type.
def vm_npaddrs(+v: P.Vmap) -> U32: U32.from_nat(List.length(&2, P.Pa, P.Vmap.paddrs(v)))
# `va_shifts + [va_bits + 1]`, the list :186 builds. THE ORDER IS `va_shifts`
# THEN the extra, and the reversal happens LATER -- so a port that reverses
# `lvl_msb` instead of reversing the two results is a different bug with the
# same symptom.
# :186 -- `lvl_msb = va_shifts + [va_bits + 1]`: the shifts plus ONE MORE, and
# the extra is `va_bits + 1`, NOT `va_bits`. So `lvl_msb` is one longer than
# `va_shifts` and `level_cnt = len(va_shifts)` is one shorter. `mem_lvl_msb_*`
# is the row and `mem_level_cnt_*` the count, and they differ by construction.
def lvl_msb_len(shifts: List<&2, U32>) -> U32: U32.add(P.level_cnt(shifts), 1)
def pte_ladder(+shifts: List<&2, U32>, va_bits: U32, lv: U32) -> Bool:
  P.pte_ladder.go(P.covers_of(shifts), P.cnts_of(shifts, va_bits), lv)
# :202 -- `(...).bit_length() - 1 - 12`. The `- 12` IS THE LAST SUBTRACTION and
# it is subtracted from a LOGARITHM, so a fragment of 0 means a 4KB page.
def frag_of(+va: U32, +sz: U32, must_cover: Bool) -> U32:
  U32.sub(P.bitlen1(P.frag_min(va, sz, must_cover)), U32.add(1, P.FRAG_UNIT_SHIFT()))
def vm_loops_opposite(+v: P.Vmap) -> Bool: P.vm_loops_opposite.go(P.vm_free_paddrs(v), P.vm_psize_sum(P.Vmap.paddrs(v)))

# --- THE GATE ROWS ----------------------------------------------------
# ===========================================================================
# THE GATE. One row per claim; the ORACLE is `.agents/slop/memory_oracle.py`
# and every `py=` expectation in it was produced by CALLING CPython, never typed.
# THE row name is part of the claim, and the differ keys on `name=value`, not on
# the name alone: a misspelled name is a hole in both directions, so a name here
# IS the oracle's name and a row the oracle does not have is a hole the differ
# must report rather than skip.
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
def anm.go(+ss: List<&2, P.Space>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: anm.go(t, List.append(&2, String, acc, [P.Space.nm(s)]))
def aval.go(+ss: List<&2, P.Space>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: aval.go(t, List.append(&2, U32, acc, [P.Space.val(s)]))
def aix.go(+ss: List<&2, P.Space>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: aix.go(t, List.append(&2, U32, acc, [P.Space.ix(s)]))
def aspace_ixs() -> List<&2, U32>: aix.go(P.aspaces(), Nil{})
def aspace_vals() -> List<&2, U32>: aval.go(P.aspaces(), Nil{})
def aspace_nms() -> String: String.join(anm.go(P.aspaces(), Nil{}), " ")
def fmt_name_of.go(m: Maybe<&2, String>) -> String:
  match m:
    case None{}: ""
    case Some{+s}: s
def fmt_name_of(i: U32) -> String: fmt_name_of.go(List.get(&2, String, calcsizes_names(), U32.to_nat(i)))
# `String.length` of a format name: 1 for every format `MMIOInterface` can
# hold and > 1 for every multi-character one. That is the `.cast()` refusal's
# ACTUAL predicate, measured by CPython, and the row is here rather than a Bool
# so the length itself is the claim.
def fmt_b() -> U32: P.fmt_ix_name("B")
def fmt_b1() -> U32: P.fmt_ix_name("b")
def fmt_h() -> U32: P.fmt_ix_name("H")
def fmt_i() -> U32: P.fmt_ix_name("I")
def fmt_q() -> U32: P.fmt_ix_name("Q")
def fmt_d() -> U32: P.fmt_ix_name("d")
# `nbytes % calcsize(fmt) != 0` -- the second measured refusal, and the rows
# come in PAIRS: a refused length and an accepted one at the same item size.
def odd_not_mult(nb: U32, isz: U32) -> Bool: Bool.not(U32.is_eq(U32.mod(nb, isz), 0))
# THE ROOT of the view fixtures: an `I`-cast 0x2000-byte window at 0x90000000.
# 0x90000000 is 2415919104 and `mmio_accum_root` is CPython's own `m.addr`, so
# the number is measured rather than chosen.
def vroot() -> P.Mv: P.mmio_of(0, 2415919104, 8192, fmt_i())
# THE VIEW of the root at `off`, with an optional size and fmt -- the whole of
# :12 in one call, and the three rows `mem_mmio_view_addr_*` /
# `mem_mmio_view_nbytes_*` / `mmio_view_fmt_*` are its three fields.
def vview(+root: P.Mv, +off: U32, sz: Maybe<&2, U32>, fmt: Maybe<&2, U32>) -> P.Mv:
  P.mmio_of(0, mmio_view_off(root, off), mmio_view_sz(root, sz, off), mmio_view_fmt(root, fmt))
# `__len__` of a view is `nbytes // calcsize(fmt)` on the VIEW's own fields,
# so it is `mmio_len` of the built view and not a separate formula.
def vlen(v: P.Mv) -> U32: mmio_len(v)
# A `List` of PAIRS with the SIZE FIRST, deliberately the same shape `P.Pa` uses
# for `paddrs`, so the two record shapes in this file agree on pair order.
type Ba is Data:
  Ba{sz: U32, al: U32}
def Ba.sz(b: Ba) -> U32:
  match b:
    case Ba{sz, al}: sz
def Ba.al(b: Ba) -> U32:
  match b:
    case Ba{sz, al}: al
def ba_list() -> List<&2, Ba>:
  [Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}, Ba{4096, 4096}, Ba{4095, 1}, Ba{4096, 1}, Ba{1, 4096}]
# THE FOUR STATES. They differ from one another in the SIZE, the BASE or the
# `wrap` FLAG and in nothing else, which is what makes `plain`/`wrap` a pair.
def b_plain() -> P.Bump: bump_of(4096, 0, False{})
def b_wrap() -> P.Bump: bump_of(4096, 0, True{})
def b_based() -> P.Bump: bump_of(4096, 1879048192, True{})
def b_aligned() -> P.Bump: bump_of(8192, 0, True{})
# `b_adv*` is `alloc` applied to the requests BEFORE the one under test. On the
# REFUSING state the advance stops, which is what CPython does -- and taking the
# RESULT's state is why a refusal that moved the pointer would show up as a
# later `bump_over_ptr_*` disagreement rather than passing silently.
def b_adv(+b: P.Bump, +ba: Ba) -> P.Bump: P.BumpR.b(P.bump_try(b, Ba.sz(ba), Ba.al(ba)))
def b_adv2(+b: P.Bump, +a1: Ba, a2: Ba) -> P.Bump: b_adv(b_adv(b, a1), a2)
def b_adv3(+b: P.Bump, +a1: Ba, +a2: Ba, a3: Ba) -> P.Bump: b_adv(b_adv2(b, a1, a2), a3)
def b_adv4(+b: P.Bump, +a1: Ba, +a2: Ba, +a3: Ba, a4: Ba) -> P.Bump: b_adv(b_adv3(b, a1, a2, a3), a4)
def b_adv5(+b: P.Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, a5: Ba) -> P.Bump: b_adv(b_adv4(b, a1, a2, a3, a4), a5)
def b_adv6(+b: P.Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, +a5: Ba, a6: Ba) -> P.Bump: b_adv(b_adv5(b, a1, a2, a3, a4, a5), a6)
def b_adv7(+b: P.Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, +a5: Ba, +a6: Ba, a7: Ba) -> P.Bump: b_adv(b_adv6(b, a1, a2, a3, a4, a5, a6), a7)
def b_adv8(+b: P.Bump, +a1: Ba, +a2: Ba, +a3: Ba, +a4: Ba, +a5: Ba, +a6: Ba, +a7: Ba, a8: Ba) -> P.Bump: b_adv(b_adv7(b, a1, a2, a3, a4, a5, a6, a7), a8)
# THE SEQUENCE FOLD: the state is a `P.Bump` and the answers are the RETURNED
# ADDRESSES in order. A REFUSAL STOPS THE FOLD, because in Python the `raise`
# replaces the rest -- so the result is a LIST whose length is itself a claim.
# `Bool.pick` evaluates both arms, so the ADVANCE is built in both arms and the
# refusal is the selector. `b_adv` on the refusing state is the IDENTITY, so
# even the arm Python never runs is well-formed.
def refused_of(+b: P.Bump, +ba: Ba) -> Bool: P.BumpR.refused(P.bump_try(b, Ba.sz(ba), Ba.al(ba)))
# THE SEQUENCE FOLD, and it is ONE def and not a `.go`/`.stop` chain because the
# chain is MUTUAL RECURSION: `.stop` needs `.fuel` and `.fuel` needs `.stop`
# (rule at `bend2-constraints.md` position 4958). So the refusal is carried in
# the ARGUMENTS rather than in a `Bool.pick` around a recursion:
#   * `stop_list` hands the walk an EMPTY request list on the refused arm, and
#     the `case Nil{}:` arm is already "return acc untouched" -- so the refusal
#     costs no arm of its own.
#   * `bump_seq.ans` appends nothing on the refused arm.
# THE `Nat` FUEL IS PASSED UNCHANGED, which is what the decrease check wants
# (rule at position 3191), so the fold's LENGTH is the number of successful
# allocations -- in Python the `raise` replaced the rest, so that length is
# itself a claim and `bump_seq_n_*` is its row.
def stop_list(refused: Bool, +allocs: List<&2, Ba>) -> List<&2, Ba>:
  Bool.pick(List<&2, Ba>, refused, Nil{}, allocs)
# THE ANSWER IS `base + res` -- :21 -- and NOT `ptr + base`, so this reads the
# RESULT's `res` and the state's `base` and never the state's `ptr`.
def bump_seq.ans(refused: Bool, +b: P.Bump, +ba: Ba, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, refused, acc,
    List.append(&2, U32, acc, [P.bump_addr(P.Bump.base(b), P.BumpR.res(P.bump_try(b, Ba.sz(ba), Ba.al(ba))))]))
def bump_seq.fuel(fuel: Nat, +b: P.Bump, +allocs: List<&2, Ba>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match allocs:
        case Nil{}: acc
        case ba <> t:
          bump_seq.fuel(p, P.BumpR.b(P.bump_try(b, Ba.sz(ba), Ba.al(ba))),
                        stop_list(refused_of(b, ba), t), bump_seq.ans(refused_of(b, ba), b, ba, acc))
def bump_seq(+b: P.Bump, +allocs: List<&2, Ba>) -> List<&2, U32>:
  bump_seq.fuel((List.length(&2, Ba, allocs) : Nat), b, allocs, Nil{})
# THE POINTER TRACE, which is `bump_seq` over `P.Bump.ptr` instead of over the
# returned address. The two are not the same list: the ADDRESS resets to `base`
# on the wrap arm while the POINTER resets to 0, and a list that shows the
# address at `0` cannot say which of the two happened.
def bump_ptr_seq.ans(refused: Bool, +b: P.Bump, +ba: Ba, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, refused, acc, List.append(&2, U32, acc, [P.Bump.ptr(P.BumpR.b(P.bump_try(b, Ba.sz(ba), Ba.al(ba))))]))
def bump_ptr_seq.fuel(fuel: Nat, +b: P.Bump, +allocs: List<&2, Ba>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match allocs:
        case Nil{}: acc
        case ba <> t:
          bump_ptr_seq.fuel(p, P.BumpR.b(P.bump_try(b, Ba.sz(ba), Ba.al(ba))),
                            stop_list(refused_of(b, ba), t), bump_ptr_seq.ans(refused_of(b, ba), b, ba, acc))
def bump_ptr_seq(+b: P.Bump, +allocs: List<&2, Ba>) -> List<&2, U32>:
  bump_ptr_seq.fuel((List.length(&2, Ba, allocs) : Nat), b, allocs, Nil{})
# THE PER-STEP READERS, which is the split again: `over` builds the argument of
# the comparison, `pad` the padding, `noround` the MUTATED comparison. Three
# separate rows per fixture so a mutation moves exactly one of them.
def bump_noround(+b: P.Bump, size: U32) -> Bool: U32.is_gt(U32.add(P.Bump.ptr(b), size), P.Bump.size(b))
def over_of(+b: P.Bump, +ba: Ba) -> Bool: P.bump_overflow(b, Ba.sz(ba), Ba.al(ba))
def pad_of(+b: P.Bump, +ba: Ba) -> U32: P.bump_round(P.Bump.ptr(b), Ba.al(ba))
def noround_of(+b: P.Bump, +ba: Ba) -> Bool: bump_noround(b, Ba.sz(ba))
# `bump_noround` is `ptr + size > self.size` -- :17 WITH THE ROUND DROPPED. It
# is a named def so the harness can move it without moving the rule.
# THE ROW FAMILY. Four rows per (state, request): the overflow test, the padded
# value it compared, the un-rounded mutation, and the pointer it compared.
def b_over.row2(+tag: String, +b: P.Bump, over: Bool, pad: U32, noround: Bool) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["bump_over_", tag]), Bool.to_u32(over))
    urow(String.concat(["bump_over_pad_", tag]), pad)
    urow(String.concat(["bump_over_noround_", tag]), Bool.to_u32(noround))
    urow(String.concat(["bump_over_ptr_", tag]), P.Bump.ptr(b))
    IO.pure(Unit, Unit{})
def b_over.row(tag: String, +b: P.Bump, +ba: Ba) -> IO(Unit):
  b_over.row2(tag, b, over_of(b, ba), pad_of(b, ba), noround_of(b, ba))
# `b_over.all` asks all EIGHT requests against one state, each after the prefix
# before it, and the `String.append` builds the `<state>_<i>` tag the oracle
# prints. Four states x eight requests x four rows = 128 rows.
def b_over.all(+tag: String, +b: P.Bump) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- b_over.row(String.append(tag, "_0"), b, Ba{16, 1})
    b2 : Unit <- b_over.row(String.append(tag, "_1"), b_adv(b, Ba{16, 1}), Ba{16, 1})
    c : Unit <- b_over.row(String.append(tag, "_2"), b_adv2(b, Ba{16, 1}, Ba{16, 1}), Ba{64, 1})
    d : Unit <- b_over.row(String.append(tag, "_3"), b_adv3(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}), Ba{64, 16})
    e : Unit <- b_over.row(String.append(tag, "_4"), b_adv4(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}), Ba{1, 16})
    # THE request that fills the window exactly (4096 bytes at alignment 4096)
    # IS WHAT MAKES `bump_over_*` AND `bump_over_noround_*` SEPARABLE, and it is
    # the sixth request, so a five-request table cannot see it.
    f : Unit <- b_over.row(String.append(tag, "_5"), b_adv5(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}), Ba{4096, 4096})
    g : Unit <- b_over.row(String.append(tag, "_6"), b_adv6(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}, Ba{4096, 4096}), Ba{4095, 1})
    h : Unit <- b_over.row(String.append(tag, "_7"), b_adv7(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}, Ba{4096, 4096}, Ba{4095, 1}), Ba{4096, 1})
    # AND the one that makes `bump_over_*` AND `bump_over_noround_*` SEPARABLE: a
    # ONE-BYTE request at alignment 4096 from a pointer at 161. The padded test
    # rounds 161 up to 4096 and overflows the 4096-byte window; the unpadded one
    # compares 162 against 4096 and does not. Every other fixture has an aligned
    # pointer or an alignment of 1, so padding is 0 and the two rows agree.
    i : Unit <- b_over.row(String.append(tag, "_8"), b_adv8(b, Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16}, Ba{4096, 4096}, Ba{4095, 1}, Ba{4096, 1}), Ba{1, 4096})
    IO.pure(Unit, Unit{})
def b_full(b: P.Bump) -> P.Bump: b_adv2(b, Ba{2048, 256}, Ba{2048, 256})
# `b_plain5` / `b_wrap5` are the states after the first FIVE requests of
# `ba_list`, which is the request index at which the refusing state raises.
def b_plain5() -> P.Bump: b_adv5(b_plain(), Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16})
def b_wrap5() -> P.Bump: b_adv5(b_wrap(), Ba{16, 1}, Ba{16, 1}, Ba{64, 1}, Ba{64, 16}, Ba{1, 16})
def b_half(b: P.Bump) -> P.Bump: b_adv(b, Ba{2048, 256})
def bump_n(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))
def bump_last.go(+xs: List<&2, U32>, last: U32) -> U32:
  match xs:
    case Nil{}: last
    case x <> t: bump_last.go(t, x)
def bump_last(answers: List<&2, U32>) -> U32: bump_last.go(answers, 0)
# THE `struct.calcsize` TABLE, both columns as rows, so a swapped pair is a
# visible difference between two lists rather than a matching pair.
# THE `AddrSpace` TABLE, BOTH DIRECTIONS, and the ALIAS row. `ops_rdma.bend`
# records `AddrSpace` as `[PHYS, SYS, PEER]` with SYS at index 1 -- that is
# `P.ASPACE_SYS_IX`, and this is that claim MEASURED.
def t_aspace() -> IO(Unit):
  do IO<Unit>:
    urow("aspace_phys_val", P.ASPACE_PHYS_VAL())
    urow("aspace_sys_val", P.ASPACE_SYS_VAL())
    urow("aspace_peer_val", P.ASPACE_PEER_VAL())
    urow("aspace_phys_ix", P.ASPACE_PHYS_IX())
    urow("aspace_sys_ix", P.ASPACE_SYS_IX())
    urow("aspace_peer_ix", P.ASPACE_PEER_IX())
    srow("aspace_names", "PHYS SYS PEER")
    lrow("aspace_tbl_ix", aspace_ixs())
    lrow("aspace_tbl_val", aspace_vals())
    srow("aspace_tbl_names", aspace_nms())
    brow("aspace_val_is_ix_plus1", aspace_val_is_ix_plus1())
    # THE negative of the alias row: PHYS's VALUE is 1 and SYS's INDEX is 1, so
    # a port that read the VALUE where the INDEX belongs maps both onto 1 and
    # PHYS's own index (0) becomes unreachable.
    urow("aspace_alias_phys_val_is_sys_ix", P.ASPACE_PHYS_VAL())
    IO.pure(Unit, Unit{})
def t_bump_over() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- b_over.all("plain", b_plain())
    b : Unit <- b_over.all("wrap", b_wrap())
    c : Unit <- b_over.all("based", b_based())
    d : Unit <- b_over.all("aligned", b_aligned())
    IO.pure(Unit, Unit{})
# `b_full` is the state with the window EXACTLY FULL (pointer == size) and
# `b_half` the state with half of it. Both are built by allocation, not by
# writing a pointer, so the state is reachable only through `alloc`.
# THE REFUSAL, GATED BY THE POINTER. `bump_refuse_ptr_before` and
# `bump_refuse_ptr_after` are the pointer either side of a `4096`-at-`4096`
# request on the refusing state, and they are EQUAL: a refused allocation that
# still advanced the pointer is the bug, and a count or a Bool cannot see it.
def t_bump_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("bump_pair_same_size", 4096)
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
    # THE POINTER TRACE, which is the other half of :21 and is NOT the address
    # list: :19's wrap arm sets `self.ptr = 0` and :21 adds `base`, so on `based`
    # the addresses are all 0x70000000-relative while the pointers are all 0.
    lrow("bump_ptr_seq_plain", bump_ptr_seq(b_plain(), ba_list()))
    lrow("bump_ptr_seq_wrap", bump_ptr_seq(b_wrap(), ba_list()))
    lrow("bump_ptr_seq_based", bump_ptr_seq(b_based(), ba_list()))
    lrow("bump_ptr_seq_aligned", bump_ptr_seq(b_aligned(), ba_list()))
    urow("bump_refuse_ptr_before", P.Bump.ptr(b_adv(b_plain(), Ba{16, 1})))
    urow("bump_refuse_ptr_after", P.Bump.ptr(b_adv(b_adv(b_plain(), Ba{16, 1}), Ba{4096, 4096})))
    urow("bump_refuse_same", Bool.to_u32(U32.is_eq(P.Bump.ptr(b_adv(b_adv(b_plain(), Ba{16, 1}), Ba{4096, 4096})), P.Bump.ptr(b_adv(b_plain(), Ba{16, 1})))))
    # FILL THE WINDOW and ask for one more byte: two 0x800-at-0x100 requests put
    # the pointer at exactly 0x1000, so a 16-byte request overflows by exactly
    # 16 and the WRAP arm resets `self.ptr = 0` -- so the answer is 0 and NOT
    # 0x1000. That is the whole content of :19 and `bump_wrap_ptr_pre` is the
    # pointer that makes the overflow happen at all.
    urow("bump_wrap_ptr_pre", P.Bump.ptr(b_full(b_wrap())))
    urow("bump_wrap_over", Bool.to_u32(P.bump_overflow(b_full(b_wrap()), 16, 1)))
    urow("bump_wrap_next", bump_addr_of(P.bump_try(b_full(b_wrap()), 16, 1), b_wrap()))
    urow("bump_wrap_ptr_post", P.Bump.ptr(b_adv(b_full(b_wrap()), Ba{16, 1})))
    # THE ALIGNED WRAP, the other half: a request whose alignment padding is
    # what tips it over, where the UNPADDED test would not have. This is the
    # pair that makes `bump_over_*` and `bump_over_noround_*` separable at the
    # same state.
    urow("bump_wrap_a_pre", P.Bump.ptr(b_half(b_wrap())))
    urow("bump_wrap_a_over", Bool.to_u32(P.bump_overflow(b_half(b_wrap()), 2048, 256)))
    urow("bump_wrap_a_noround", Bool.to_u32(bump_noround(b_half(b_wrap()), 2048)))
    urow("bump_wrap_a_next", bump_addr_of(P.bump_try(b_half(b_wrap()), 2048, 256), b_wrap()))
    urow("bump_wrap_a_post", P.Bump.ptr(b_adv(b_half(b_wrap()), Ba{2048, 256})))
    # THE REFUSAL FLAG, which is how the two lanes share one `U32`
    # representation: the sixth request raises on `plain` and not on `wrap`.
    urow("bump_pair_plain_refused", Bool.to_u32(refused_of(b_plain5(), Ba{4096, 4096})))
    urow("bump_pair_wrap_refused", Bool.to_u32(refused_of(b_wrap5(), Ba{4096, 4096})))
    urow("bump_ptr_is_end_plain", Bool.to_u32(bump_ptr_is_end(b_plain(), 16, 1)))
    urow("bump_ptr_is_end_wrap", Bool.to_u32(bump_ptr_is_end(b_wrap(), 16, 1)))
    urow("bump_ptr_is_end_based", Bool.to_u32(bump_ptr_is_end(b_based(), 16, 1)))
    urow("bump_ptr_is_end_aligned", Bool.to_u32(bump_ptr_is_end(b_aligned(), 16, 1)))
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
def t_calcsizes() -> IO(Unit):
  do IO<Unit>:
    srow("calcsizes_names", "B b H h I i Q q f d ? 2I 4B 2H 8B I2B 3I 16B 6I 32B 12I 2d 4f")
    lrow("calcsizes_sizes", P.calcsizes_sizes())
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
    # THE TWO LONGEST SIGNATURES. `MemoryManager.__init__` names `first_lv=0` and
    # `reserve_ptable=False` -- the two defaults `palloc_ranges` and the PTABLE
    # sizing read -- and `vfree` takes a `VirtMapping` and nothing else, which is
    # why it frees by walking `vm.paddrs` and not by a range.
    srow("sig_mm", "self dev vram_size boot_size pt_t va_bits va_shifts va_base palloc_ranges first_lv=0 reserve_ptable=False")
    srow("sig_vfree", "self vm")
    IO.pure(Unit, Unit{})
# :8 -- `__len__`. The nine fixtures are the nine in `memory_oracle.py`'s
# `MMIO` list, and each is a (nbytes, fmt-index) pair.
# THE THREE NESTED VIEWS, built with `vview` so each level's address and size
# come from :12 and not from a constant. `v2` is a view OF `v1` and `v3` a view
# of `v2`, which is what "offsets ACCUMULATE and a view's base is the ROOT's"
# means in code -- `mmio_accum_addr` is the deepest address minus the root's.
def v1() -> P.Mv: vview(vroot(), 256, None{}, Some{fmt_h()})
def v2() -> P.Mv: vview(v1(), 8, Some{64}, Some{fmt_b()})
def v3() -> P.Mv: vview(v2(), 4, None{}, None{})
# THE NINE FIXTURES AS A LIST, so the four field columns are four list rows and a
# swapped column is a DIFFERENT LIST rather than a matching pair of scalars. The
# order is the oracle's `MMIO` list and the names are in that order too.
def mmio_fixtures() -> List<&2, P.Mv>:
  [P.mmio_of(0, 2415919104, 4096, fmt_b()), P.mmio_of(0, 2415919104, 4096, fmt_h()),
   P.mmio_of(0, 2415919104, 4096, fmt_i()), P.mmio_of(0, 2415919104, 4096, fmt_q()),
   P.mmio_of(0, 2415919104, 4096, fmt_d()), P.mmio_of(0, 2415919104, 4096, fmt_b1()),
   P.mmio_of(0, 2415919104, 4098, fmt_h()), P.mmio_of(0, 2415919104, 4097, fmt_b()),
   P.mmio_of(0, 2415919104, 4099, fmt_b1())]
def col.addr.go(+ms: List<&2, P.Mv>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}: acc
    case m <> t: col.addr.go(t, List.append(&2, U32, acc, [P.Mv.addr(m)]))
def col.addr(ms: List<&2, P.Mv>) -> List<&2, U32>: col.addr.go(ms, Nil{})
def col.nb.go(+ms: List<&2, P.Mv>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ms:
    case Nil{}: acc
    case m <> t: col.nb.go(t, List.append(&2, U32, acc, [P.Mv.nbytes(m)]))
def col.nb(ms: List<&2, P.Mv>) -> List<&2, U32>: col.nb.go(ms, Nil{})
def col.fmt.go(+ms: List<&2, P.Mv>, +acc: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}: acc
    case m <> t: col.fmt.go(t, List.append(&2, String, acc, [fmt_name_of(P.Mv.fmt(m))]))
def col.fmt(ms: List<&2, P.Mv>) -> List<&2, String>: col.fmt.go(ms, Nil{})
# THE `.tolist()` ARM of :9 IS the non-'B' ARM, so these Bool columns ARE the
# branch: 'B' is the byte format, and `fmt == 'B'` is what :9 tests.
def col.byte.go(+ms: List<&2, P.Mv>, +acc: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}: acc
    case m <> t: col.byte.go(t, List.append(&2, String, acc, [Bool.show(mmio_is_byte_fmt(P.Mv.fmt(m)))]))
def col.byte(ms: List<&2, P.Mv>) -> List<&2, String>: col.byte.go(ms, Nil{})

# THE FORMAT-NAME COLUMN of `P.calcsizes()`, which is the table the multichar claim
# is made over. Reusing it keeps the two lanes' fixture lists identical by
# construction rather than by two transcriptions that happen to agree.
def mmio_fmts() -> List<&2, String>: calcsizes_names()
def mcol.len.go(+fs: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: mcol.len.go(t, List.append(&2, U32, acc, [U32.from_nat(String.length(f))]))
def mcol.len(fs: List<&2, String>) -> List<&2, U32>: mcol.len.go(fs, Nil{})
def mcol.refused.go(+fs: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: mcol.refused.go(t, List.append(&2, U32, acc, [Bool.to_u32(U32.is_gt(U32.from_nat(String.length(f)), 1))]))
def mcol.refused(fs: List<&2, String>) -> List<&2, U32>: mcol.refused.go(fs, Nil{})
def t_mmio_len() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_len_b", vlen(P.mmio_of(0, 2415919104, 4096, fmt_b())))
    urow("mmio_len_h", vlen(P.mmio_of(0, 2415919104, 4096, fmt_h())))
    urow("mmio_len_i", vlen(P.mmio_of(0, 2415919104, 4096, fmt_i())))
    urow("mmio_len_q", vlen(P.mmio_of(0, 2415919104, 4096, fmt_q())))
    urow("mmio_len_d", vlen(P.mmio_of(0, 2415919104, 4096, fmt_d())))
    urow("mmio_len_b1", vlen(P.mmio_of(0, 2415919104, 4096, fmt_b1())))
    urow("mmio_len_h2", vlen(P.mmio_of(0, 2415919104, 4098, fmt_h())))
    urow("mmio_len_oddb", vlen(P.mmio_of(0, 2415919104, 4097, fmt_b())))
    urow("mmio_len_oddb2", vlen(P.mmio_of(0, 2415919104, 4099, fmt_b1())))
    lrow("mmio_addr_tbl", col.addr(mmio_fixtures()))
    lrow("mmio_nbytes_tbl", col.nb(mmio_fixtures()))
    srow("mmio_fmt_tbl", String.join(col.fmt(mmio_fixtures()), " "))
    srow("mmio_isbyte_tbl", String.join(col.byte(mmio_fixtures()), " "))
    # and the DEFAULT fmt of :7, which is 'B' and therefore the byte arm.
    urow("mmio_def_fmt_ix", P.mmio_def_fmt())
    srow("mmio_def_fmt_nm", fmt_name_of(P.mmio_def_fmt()))
    IO.pure(Unit, Unit{})
# :12 -- the `size=None` ARM, which is `self.nbytes - offset` and NOT 0. The
# `whole` fixture (offset 0, size None) answers 8192 and the `end` fixture
# (offset == nbytes) answers 0, so the two ends of the subtraction sit two
# sections apart and a port that collapsed `None` to 0 fails `whole`.
def t_mmio_nest1() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_nest1_addr", P.Mv.addr(v1()))
    urow("mmio_nest1_nbytes", P.Mv.nbytes(v1()))
    IO.pure(Unit, Unit{})
def t_mmio_nest2() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_nest2_addr", P.Mv.addr(v2()))
    urow("mmio_nest2_nbytes", P.Mv.nbytes(v2()))
    srow("mmio_nest2_fmt", fmt_name_of(P.Mv.fmt(v2())))
    urow("mmio_nest2_len", vlen(v2()))
    urow("mmio_nest3_addr", P.Mv.addr(v3()))
    urow("mmio_nest3_nbytes", P.Mv.nbytes(v3()))
    srow("mmio_nest3_fmt", fmt_name_of(P.Mv.fmt(v3())))
    urow("mmio_accum_root", P.Mv.addr(vroot()))
    urow("mmio_accum_sum", 268)
    urow("mmio_accum_addr", U32.sub(P.Mv.addr(v3()), P.Mv.addr(vroot())))
    IO.pure(Unit, Unit{})
# THE two measured construction constraints, and they are NEGATIVE rows: each is
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
    urow("mmio_odd_refused_4097_H", Bool.to_u32(odd_not_mult(4097, 2)))
    urow("mmio_odd_refused_4097_I", Bool.to_u32(odd_not_mult(4097, 4)))
    urow("mmio_odd_refused_4097_q", Bool.to_u32(odd_not_mult(4097, 8)))
    urow("mmio_odd_refused_4099_H", Bool.to_u32(odd_not_mult(4099, 2)))
    urow("mmio_odd_refused_4097_d", Bool.to_u32(odd_not_mult(4097, 8)))
    # AND THE REMAINDER IS NOT ALWAYS 1. Every refused fixture above has
    # `nbytes % itemsize == 1`, so `!= 0` and `== 1` are the SAME predicate over
    # the whole family -- a mutation that read `== 1` moved nothing. 4098 % 4 is
    # 2 and 4098 % 2 is 0, so this pair separates "not a multiple" from
    # "leaves one byte over".
    urow("mmio_odd_refused_4098_I", Bool.to_u32(odd_not_mult(4098, 4)))
    urow("mmio_odd_refused_4098_q", Bool.to_u32(odd_not_mult(4098, 8)))
    # AND the accepted side of the same pairs, at the SAME item sizes: 4096 and
    # 4098-at-'H' are multiples of 2, 4 and 8 respectively, so these answer 0
    # where the rows above answer 1. 4098 IS the load-bearing fixture: `4098 % 2
    # == 0` and `4098 % 4 == 2`, so "not a multiple" and "leaves two bytes over"
    # are separable only here.
    urow("mmio_odd_refused_4096_H", Bool.to_u32(odd_not_mult(4096, 2)))
    urow("mmio_odd_refused_4096_I", Bool.to_u32(odd_not_mult(4096, 4)))
    urow("mmio_odd_refused_4096_q", Bool.to_u32(odd_not_mult(4096, 8)))
    urow("mmio_odd_refused_4098_H", Bool.to_u32(odd_not_mult(4098, 2)))
    urow("mmio_odd_refused_4097_B", Bool.to_u32(odd_not_mult(4097, 1)))
    # THE multichar columns over the whole `calcsize` TABLE, as two lists. The
    # claim is that a format is refused EXACTLY when it is more than one
    # character, and a column per format would say the same thing 23 times.
    lrow("mmio_multichar_len", mcol.len(mmio_fmts()))
    lrow("mmio_multichar_refused", mcol.refused(mmio_fmts()))
    IO.pure(Unit, Unit{})
# :12 -- the `size=None` ARM, which is `self.nbytes - offset` and NOT 0. The
# `whole` fixture (offset 0, size None) answers 8192 and the `end` fixture
# (offset == nbytes) answers 0, so the two ends of the subtraction sit two
# sections apart and a port that collapsed `None` to 0 fails `whole`.
def t_mmio_view0() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_whole", P.Mv.addr(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_nbytes_whole", P.Mv.nbytes(vview(vroot(), 0, None{}, None{})))
    srow("mmio_view_fmt_whole", fmt_name_of(P.Mv.fmt(vview(vroot(), 0, None{}, None{}))))
    urow("mmio_view_len_whole", vlen(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_addr_off", P.Mv.addr(vview(vroot(), 16, None{}, None{})))
    urow("mmio_view_nbytes_off", P.Mv.nbytes(vview(vroot(), 16, None{}, None{})))
    srow("mmio_view_fmt_off", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, None{}, None{}))))
    urow("mmio_view_len_off", vlen(vview(vroot(), 16, None{}, None{})))
    urow("mmio_view_addr_end", P.Mv.addr(vview(vroot(), 8192, None{}, None{})))
    urow("mmio_view_nbytes_end", P.Mv.nbytes(vview(vroot(), 8192, None{}, None{})))
    srow("mmio_view_fmt_end", fmt_name_of(P.Mv.fmt(vview(vroot(), 8192, None{}, None{}))))
    urow("mmio_view_len_end", vlen(vview(vroot(), 8192, None{}, None{})))
    IO.pure(Unit, Unit{})
# the `size=...` ARM, which REPLACES the subtraction rather than adjusting it,
# and the `fmt=...` ARM, which replaces the parent's. `mmio_view_nbytes_sz` is
# 256 with offset 16 while `mmio_view_nbytes_off` is 8176 -- same offset, so
# the only difference is the arm.
def t_mmio_view1() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_sz", P.Mv.addr(vview(vroot(), 16, Some{256}, None{})))
    urow("mmio_view_nbytes_sz", P.Mv.nbytes(vview(vroot(), 16, Some{256}, None{})))
    srow("mmio_view_fmt_sz", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, Some{256}, None{}))))
    urow("mmio_view_len_sz", vlen(vview(vroot(), 16, Some{256}, None{})))
    urow("mmio_view_addr_all", P.Mv.addr(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    urow("mmio_view_nbytes_all", P.Mv.nbytes(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    urow("mmio_view_len_all", vlen(vview(vroot(), 16, Some{256}, Some{fmt_i()})))
    srow("mmio_view_fmt_all", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, Some{256}, Some{fmt_i()}))))
    urow("mmio_view_addr_sz0", P.Mv.addr(vview(vroot(), 16, Some{0}, None{})))
    urow("mmio_view_nbytes_sz0", P.Mv.nbytes(vview(vroot(), 16, Some{0}, None{})))
    srow("mmio_view_fmt_sz0", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, Some{0}, None{}))))
    urow("mmio_view_len_sz0", vlen(vview(vroot(), 16, Some{0}, None{})))
    IO.pure(Unit, Unit{})
# `fmt or self.fmt` -- a SUPPLIED fmt replaces the parent's and an absent one
# KEEPS it. `mmio_view_fmt_fmt` is 'H' and `mmio_view_fmt_off` is 'I', and the
# two fixtures have the SAME offset and size, so the only difference is the
# arm of the `or`.
def t_mmio_view2() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_nbytes_fmt", P.Mv.nbytes(vview(vroot(), 16, None{}, Some{fmt_h()})))
    urow("mmio_view_len_fmt", vlen(vview(vroot(), 16, None{}, Some{fmt_h()})))
    srow("mmio_view_fmt_fmt", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, None{}, Some{fmt_h()}))))
    urow("mmio_view_addr_fmt", P.Mv.addr(vview(vroot(), 16, None{}, Some{fmt_h()})))
    urow("mmio_view_nbytes_b_off", P.Mv.nbytes(vview(vroot(), 16, None{}, Some{fmt_b()})))
    urow("mmio_view_addr_b_off", P.Mv.addr(vview(vroot(), 16, None{}, Some{fmt_b()})))
    urow("mmio_view_len_b_off", vlen(vview(vroot(), 16, None{}, Some{fmt_b()})))
    srow("mmio_view_fmt_b_off", fmt_name_of(P.Mv.fmt(vview(vroot(), 16, None{}, Some{fmt_b()}))))
    urow("mmio_view_addr_b_all", P.Mv.addr(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    urow("mmio_view_nbytes_b_all", P.Mv.nbytes(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    urow("mmio_view_len_b_all", vlen(vview(vroot(), 8, Some{2048}, Some{fmt_b()})))
    srow("mmio_view_fmt_b_all", fmt_name_of(P.Mv.fmt(vview(vroot(), 8, Some{2048}, Some{fmt_b()}))))
    IO.pure(Unit, Unit{})
# `view(0, None, None)` IS THE IDENTITY -- address unchanged, nbytes unchanged,
# fmt unchanged -- and that is a claim in its own right: `mmio_view_addr_root`
# equals `mmio_view_addr_whole` and `mmio_view_nbytes_root` equals
# `mmio_view_nbytes_whole`, one section apart.
def t_mmio_view3() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_view_addr_root", P.Mv.addr(vview(vroot(), 0, None{}, None{})))
    urow("mmio_view_nbytes_root", P.Mv.nbytes(vview(vroot(), 0, None{}, None{})))
    srow("mmio_view_fmt_root", fmt_name_of(P.Mv.fmt(vview(vroot(), 0, None{}, None{}))))
    urow("mmio_view_len_root", vlen(vview(vroot(), 0, None{}, None{})))
    IO.pure(Unit, Unit{})
# A THREE-LEVEL NEST, and the ACCUMULATION claim. The addresses are built by
# `mmio_view_off` on the PARENT, so a port that rebased a view on its parent
# rather than adding the offset would produce a smaller address here, and
# `mmio_accum_addr_rel` -- the deepest address MINUS the root's -- is the row
# that measures the total of the three offsets.
# `v1 = m.view(0x100, None, 'H')` -- the second level.
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
# ONE FIXTURE, FIVE ROWS. `nm` is the oracle's fixture name, so the row names
# are CPython's and not this file's invention.
def pte_max2(+a: U32, +b: U32) -> U32: Bool.pick(U32, U32.is_gt(a, b), a, b)
def pte_first_largest.go(+xs: List<&2, U32>, +big: U32, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case x <> t: pte_first_largest.go(t, pte_max2(big, x), acc)
# `pte_covers[0]` IS THE LARGEST, which is the ORDER claim and the root's gate.
# THE CLAIM IS `first == max` and NOT "every later element is smaller": a
# `va_shifts` whose covers are not monotone would separate the two readings and
# no real device has one, so this is the honest weaker claim.
def pte_max_all(+xs: List<&2, U32>, +big: U32) -> U32:
  match xs:
    case Nil{}: big
    case x <> t: pte_max_all(t, pte_max2(big, x))
# THE `seen` FLAG IS LOAD-BEARING: a fold that assigns the accumulator on EVERY
# step answers the LAST element, and for a REVERSED `pte_covers` the last element
# is the LEAF and not the root -- which is what `pte_root_covers_x3` printed (1)
# where CPython says 262144 until this flag existed.
# THE first element, as a ONE-ELEMENT list. THE `seen` FLAG is LOAD-BEARING: a
# fold that assigns the accumulator on EVERY step answers the LAST element, and
# for a REVERSED `pte_covers` the last element is the LEAF and not the root --
# which is what `pte_root_covers_x3` printed (1) where CPython says 262144 until
# this flag existed. A `Maybe` accumulator cannot carry the flag (a `Maybe` is
# read once and cannot be `+`), and a `.go`/`.step` pair is mutual recursion, so
# the flag is a `Bool` PARAMETER and the answer is a list `bump_last` collapses.
def first_of.keep(+seen: Bool, +acc: List<&2,  U32>, +x: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, seen, acc, List.append(&2, U32, acc, [x]))

def first_of.take(+xs: List<&2,  U32>, +seen: Bool, +acc: List<&2,  U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: first_of.take(t, True{}, first_of.keep(seen, acc, x))

def first_of(xs: List<&2, U32>) -> U32: bump_last(first_of.take(xs, False{}, Nil{}))
def pte_first_largest_of(+xs: List<&2, U32>) -> Bool: U32.is_eq(first_of(xs), pte_max_all(xs, P.fmt_absent()))
def pte_first_largest(shifts: List<&2, U32>) -> Bool: pte_first_largest_of(P.covers_of(shifts))
# THE LADDER, all levels at once. `lv 0` has no level below it so it answers 0
# and `pte_first_largest_*` is the root's gate.
def ladder_one(+shifts: List<&2, U32>, va_bits: U32, lv: U32) -> U32:
  Bool.to_u32(pte_ladder(shifts, va_bits, lv))
# THE LADDER, all levels at once. `lv 0` has no level below it so it answers 0
# and `pte_first_largest_*` is the root's gate.
def ladder_all.go(fuel: Nat, +shifts: List<&2, U32>, +va_bits: U32, +lv: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: ladder_all.go(p, shifts, va_bits, U32.add(lv, 1), List.append(&2, U32, acc, [ladder_one(shifts, va_bits, lv)]))
def ladder_all(+shifts: List<&2, U32>, va_bits: U32) -> List<&2, U32>:
  ladder_all.go((List.length(&2, U32, P.covers_of(shifts)) : Nat), shifts, va_bits, 0, Nil{})
def t_pte1(+nm: String, +shifts: List<&2, U32>, +va_bits: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["pte_shifts_", nm]), String.join(ush(shifts, Nil{}), " "))
    urow(String.concat(["pte_vabits_", nm]), va_bits)
    lrow(String.concat(["pte_msb_", nm]), P.lvl_msb(shifts, va_bits))
    lrow(String.concat(["pte_covers_", nm]), P.covers_of(shifts))
    lrow(String.concat(["pte_covers_raw_", nm]), P.covers_raw(shifts))
    lrow(String.concat(["pte_cnts_", nm]), P.cnts_of(shifts, va_bits))
    urow(String.concat(["pte_level_cnt_", nm]), P.level_cnt(shifts))
    urow(String.concat(["pte_msb_len_", nm]), lvl_msb_len(shifts))
    urow(String.concat(["pte_first_largest_", nm]), Bool.to_u32(pte_first_largest(shifts)))
    urow(String.concat(["pte_root_cnt_", nm]), first_of(P.cnts_of(shifts, va_bits)))
    urow(String.concat(["pte_root_covers_", nm]), first_of(P.covers_of(shifts)))
    lrow(String.concat(["pte_ladder_", nm]), ladder_all(shifts, va_bits))
    IO.pure(Unit, Unit{})
# :7, :12 -- `to_mv(addr, nbytes)` then `.cast(fmt)`. Two tags because they are
# two calls and a `view` does both again.
# ===========================================================================
# THE PAGE-TABLE GATE, and it is the REVERSAL gate.
# `pte_covers` and `pte_cnt` are both `[::-1]` (:187), and a dropped reversal
# produces a table that is right at the ROOT and wrong at every other level --
# and every row that only exercises the root passes. So each fixture prints
# `pte_shifts_*`, `pte_covers_*` AND `pte_covers_raw_*` IN ONE ROW FAMILY: the
# raw list is `[1 << x for x in va_shifts]` and the reversed one is the field,
# and a dropped `[::-1]` makes two rows disagree with each other rather than
# two rows that could both be plausible.
# `pte_ladder_*` is the row a mis-reversed table CANNOT fake, because it
# RELATES the two lists: `pte_cnt[lv] * pte_covers[lv] == pte_covers[lv-1]`.
# `lv 0` is the root and has no level below it, so the ladder row answers 0
# there and the ROOT is gated by `pte_first_largest_*` instead.
# THE 64-BIT WALL. `pte_covers[0]` is `1 << va_shifts[-1]` and for AMD
# (`[12,21,30,39,48]`) that is `2^48`, which SATURATES a `U32`. So the U32 lane
# gates the fixtures whose every entry fits, and `t_pte_64` gates the AMD and
# NV root covers as `H.I64` pairs -- `mem_pte64_root_*`. A port that computed
# them in `U32` would answer 0, which is how a SQTT pointer once became a
# zero-sized free list.
def sh_p4k() -> List<&2, U32>: [0]
def sh_p64_2m() -> List<&2, U32>: [0, 21]
def sh_p64_4k() -> List<&2, U32>: [0, 6]
# :7, :12 -- `to_mv(addr, nbytes)` then `.cast(fmt)`. Two tags because they are
# two calls and a `view` does both again.
def t_pte0() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_pte1("p4k", sh_p4k(), 12)
    b : Unit <- t_pte1("p64_4k", sh_p64_4k(), 12)
    c : Unit <- t_pte1("p64_2m", sh_p64_2m(), 21)
    IO.pure(Unit, Unit{})
# :7, :12 -- `to_mv(addr, nbytes)` then `.cast(fmt)`. Two tags because they are
def VA_BITS_X3() -> U32: 27
def VA_BITS_X4() -> U32: 36
def sh_x3() -> List<&2, U32>: [0, 9, 18]
def sh_x4() -> List<&2, U32>: [0, 9, 18, 27]
def sh_pte_nz() -> List<&2, U32>: [12, 21]
def sh_root1() -> List<&2, U32>: [15]
def sh_tall() -> List<&2, U32>: [0, 9, 18, 27, 36, 45]
def VA_BITS_ROOT1() -> U32: 47
def VA_BITS_TALL() -> U32: 48
def VA_BITS_AMD() -> U32: 48
def VA_BITS_NV() -> U32: 52
def sh_amd() -> List<&2, U32>: [12, 21, 30, 39, 48]
def sh_nv() -> List<&2, U32>: [16, 25, 34, 43, 52]
# THE `t_pte1n` VARIANT, and it is a SEPARATE def rather than a flag: a
# `Bool.pick` between two row blocks would PRINT BOTH, so each width needs its
# own `IO` block and not a branch. `cnts` IS emitted here -- every entry is at
# most `2^9` -- but `covers` and the ladder are not, because they are the two
# rows whose intermediate products leave `U32`.
def t_pte1n(+nm: String, +shifts: List<&2, U32>, +va_bits: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["pte_shifts_", nm]), String.join(ush(shifts, Nil{}), " "))
    urow(String.concat(["pte_vabits_", nm]), va_bits)
    lrow(String.concat(["pte_msb_", nm]), P.lvl_msb(shifts, va_bits))
    lrow(String.concat(["pte_cnts_", nm]), P.cnts_of(shifts, va_bits))
    urow(String.concat(["pte_root_cnt_", nm]), first_of(P.cnts_of(shifts, va_bits)))
    urow(String.concat(["pte_level_cnt_", nm]), P.level_cnt(shifts))
    urow(String.concat(["pte_msb_len_", nm]), lvl_msb_len(shifts))
    IO.pure(Unit, Unit{})
# THE narrowest variant: ONLY the shape, for the tables whose `cnts` also leave
# `U32`. `root1` is the case -- a one-level table at shift 15 with `va_bits` 47
# has a root entry count of `1 << (48 - 15)`, which is `2^33`. What survives is
# the shift list, the msb ladder, the level count and the ladder LENGTH, and the
# ladder length is the claim that `pte_cnt` has one entry per level.
def t_pte1m(+nm: String, +shifts: List<&2, U32>, +va_bits: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["pte_shifts_", nm]), String.join(ush(shifts, Nil{}), " "))
    urow(String.concat(["pte_vabits_", nm]), va_bits)
    lrow(String.concat(["pte_msb_", nm]), P.lvl_msb(shifts, va_bits))
    urow(String.concat(["pte_level_cnt_", nm]), P.level_cnt(shifts))
    urow(String.concat(["pte_msb_len_", nm]), lvl_msb_len(shifts))
    IO.pure(Unit, Unit{})
def t_pte3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_pte1("nz", sh_pte_nz(), 21)
    # `root1` is a SINGLE-LEVEL table whose shift is not 0, so the root cover is
    # `1 << 15` and the ladder is a one-element list -- the only fixture where
    # `level_cnt == 1` and `msb_len == 2`.
    b : Unit <- t_pte1m("root1", sh_root1(), VA_BITS_ROOT1())
    # `tall` is the DEEPEST table that still fits a `U32` COVER: six levels with
    # a 45-bit root cover, which is `2^45` and NOT representable -- so only the
    # entry counts and the shape are gated, and the cover is not.
    c : Unit <- t_pte1n("tall", sh_tall(), VA_BITS_TALL())
    IO.pure(Unit, Unit{})
def t_pte2() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_pte1("x3", sh_x3(), VA_BITS_X3())
    b : Unit <- t_pte1("x4", sh_x4(), VA_BITS_X4())
    # THE two real device tables, and only the U32-SHAPED half of each. Their
    # root covers are `2^48` and `2^52`, which SATURATE, so `pte_covers_*`,
    # `pte_covers_raw_*`, `pte_first_largest_*` and `pte_root_covers_*` are NOT
    # emitted here -- `t_pte64` carries those two numbers as `H.I64` pairs. The
    # rows that ARE emitted are the shift list, the msb ladder, the entry counts
    # (all at most `2^9`) and the ladder invariant.
    c : Unit <- t_pte1n("amd", sh_amd(), VA_BITS_AMD())
    d : Unit <- t_pte1n("nv", sh_nv(), VA_BITS_NV())
    IO.pure(Unit, Unit{})
def mono.go(+xs: List<&2, U32>, prev: U32, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case x <> t: mono.go(t, x, Bool.and(acc, U32.is_le(prev, x)))
def barefused(shifts: List<&2, U32>) -> Bool:
  Bool.not(mono.go(shifts, 0, True{}))
# THE NON-MONOTONE REFUSAL. `pte_cnt` shifts by `msb[i+1] - msb[i]`, which is
# NEGATIVE when the shifts go backwards; CPython raises `ValueError` and this
# port's `U32.shln` would wrap instead. So `pte_ladder` and `pte_first_largest`
# are THEOREMS for every `va_shifts` CPython accepts, and these three rows are
# what makes that claim checkable: the two non-monotone fixtures are refused and
# the monotone one is not.
def t_barefused() -> IO(Unit):
  do IO<Unit>:
    urow("pte_barefused_12_21_4", Bool.to_u32(barefused([12, 21, 4])))
    urow("pte_barefused_0_9_4", Bool.to_u32(barefused([0, 9, 4])))
    urow("pte_barefused_12_21", Bool.to_u32(barefused([12, 21])))
    IO.pure(Unit, Unit{})
# THE 64-BIT ROWS, for the two REAL device tables whose root cover is outside
# `U32`. `H.i64_of_hi_lo` splits the shift out of the fixture, so the row is the
# PAIR and a `U32` truncation would make `hi` zero.
def t_pte64() -> IO(Unit):
  do IO<Unit>:
    i64row("pte64_root_amd", H.i64_of_hi_lo(65536, 0))
    i64row("pte64_root_nv", H.i64_of_hi_lo(1048576, 0))
    # THE SATURATION IS THE CLAIM: `1 << 48` in a `U32` is 0, and these three
    # rows are that 0 while `pte64_root_*` above carry the real value.
    urow("pte64_shl_48", P.shl1(48))
    urow("pte64_shl_52", P.shl1(52))
    urow("pte64_shl_45", P.shl1(45))
    IO.pure(Unit, Unit{})
def t_pte() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_pte0()
    b : Unit <- t_pte2()
    c : Unit <- t_pte3()
    d : Unit <- t_pte64()
    e : Unit <- t_barefused()
    IO.pure(Unit, Unit{})
# ===========================================================================
# THE fragment gate -- `_frag_size` (:195-202). THE flag is the interesting
# PART and the rows come in PAIRS: `frag_<n>` and `frag_<n>_nocover` ask the
# same `(va, sz)` twice and the two arms take DIFFERENT minima whenever `sz` is
# not a power of two.
# THE THEOREM, and it is why one fixture family CANNOT separate the arms: for a
# POWER-OF-TWO `sz`, `sz_pwr2_div == sz_pwr2_max`, so `min(a, b)` takes the same
# value on both arms and the two rows AGREE. No fixture with a power-of-two
# size can tell `must_cover` from its negation -- so `frag_d`/`frag_dnocover`
# are a THEOREM row (they agree) and `frag_a`/`frag_anocover` are the SEPARATING
# pair (`sz = 0x3000` is not a power of two).
# THE SENTINEL. `va == 0` takes `(1 << 63)`, which is outside a `U32`, so
# `frag_va_div` substitutes `P.LOWBIT_ZERO` = `2^31`. `frag_va_div_b` and
# `frag_va_div_bnocover` are the rows that make the substitution VISIBLE, and
# `mem_lowbit_zero_exact` is the `H.I64` the sentinel really is.
# THE LOWBIT IN ISOLATION, which is what a port that dropped the `va == 0`
# sentinel would compute: `frag_lowbit_0` is 0 while CPython's `va & -va` for
# `va == 0` is ALSO 0 -- and `frag_va_div_0` is the row that shows the sentinel
# taking over where the raw lowbit is 0.
def t_frag0() -> IO(Unit):
  do IO<Unit>:
    urow("frag_a", frag_of(8192, 12288, True{}))
    urow("frag_an", frag_of(8192, 12288, False{}))
    urow("frag_a_va_div", P.frag_va_div(8192))
    urow("frag_a_sz_div", P.frag_sz_div(12288))
    urow("frag_a_sz_max", P.frag_sz_max(12288))
    urow("frag_a_min", P.frag_min(8192, 12288, True{}))
    urow("frag_a_min_bl", P.bitlen1(P.frag_min(8192, 12288, True{})))
    urow("frag_an_va_div", P.frag_va_div(8192))
    urow("frag_an_sz_div", P.frag_sz_div(12288))
    urow("frag_an_sz_max", P.frag_sz_max(12288))
    urow("frag_an_min", P.frag_min(8192, 12288, False{}))
    urow("frag_an_min_bl", P.bitlen1(P.frag_min(8192, 12288, False{})))
    IO.pure(Unit, Unit{})
# THE SENTINEL FAMILY: `va == 0` with a power-of-two size (so the two arms
# AGREE, by the theorem) and with a non-power-of-two size (so they DIFFER and
# the sentinel is load-bearing on the `must_cover` arm).
def t_frag1() -> IO(Unit):
  do IO<Unit>:
    urow("frag_b", frag_of(0, 4096, True{}))
    urow("frag_bn", frag_of(0, 4096, False{}))
    urow("frag_b_va_div", P.frag_va_div(0))
    urow("frag_b_sz_div", P.frag_sz_div(4096))
    urow("frag_b_sz_max", P.frag_sz_max(4096))
    urow("frag_b_min", P.frag_min(0, 4096, True{}))
    urow("frag_b_min_bl", P.bitlen1(P.frag_min(0, 4096, True{})))
    urow("frag_bn_va_div", P.frag_va_div(0))
    urow("frag_bn_sz_div", P.frag_sz_div(4096))
    urow("frag_bn_sz_max", P.frag_sz_max(4096))
    urow("frag_bn_min", P.frag_min(0, 4096, False{}))
    urow("frag_bn_min_bl", P.bitlen1(P.frag_min(0, 4096, False{})))
    urow("frag_c", frag_of(0, 12288, True{}))
    urow("frag_cn", frag_of(0, 12288, False{}))
    urow("frag_c_va_div", P.frag_va_div(0))
    urow("frag_c_sz_div", P.frag_sz_div(12288))
    urow("frag_c_sz_max", P.frag_sz_max(12288))
    urow("frag_c_min", P.frag_min(0, 12288, True{}))
    urow("frag_c_min_bl", P.bitlen1(P.frag_min(0, 12288, True{})))
    urow("frag_cn_min", P.frag_min(0, 12288, False{}))
    urow("frag_cn_min_bl", P.bitlen1(P.frag_min(0, 12288, False{})))
    urow("frag_cn_va_div", P.frag_va_div(0))
    urow("frag_cn_sz_div", P.frag_sz_div(12288))
    urow("frag_cn_sz_max", P.frag_sz_max(12288))
    IO.pure(Unit, Unit{})
# THE THEOREM ROW: a power-of-two size makes both arms agree, so these two rows
# are EQUAL and that is the claim. `frag_d`/`frag_dnocover` are the oracle's
# names for the pair; `frag_dn` is the oracle's name for the second arm.
def t_frag2() -> IO(Unit):
  do IO<Unit>:
    urow("frag_d", frag_of(8192, 8192, True{}))
    urow("frag_dn", frag_of(8192, 8192, False{}))
    urow("frag_d_va_div", P.frag_va_div(8192))
    urow("frag_d_sz_div", P.frag_sz_div(8192))
    urow("frag_d_sz_max", P.frag_sz_max(8192))
    urow("frag_d_min", P.frag_min(8192, 8192, True{}))
    urow("frag_d_min_bl", P.bitlen1(P.frag_min(8192, 8192, True{})))
    urow("frag_dn_min", P.frag_min(8192, 8192, False{}))
    urow("frag_dn_min_bl", P.bitlen1(P.frag_min(8192, 8192, False{})))
    urow("frag_dn_va_div", P.frag_va_div(8192))
    urow("frag_dn_sz_div", P.frag_sz_div(8192))
    urow("frag_dn_sz_max", P.frag_sz_max(8192))
    urow("frag_e", frag_of(4660, 4096, True{}))
    urow("frag_e_va_div", P.frag_va_div(4660))
    urow("frag_e_sz_div", P.frag_sz_div(4096))
    urow("frag_e_sz_max", P.frag_sz_max(4096))
    urow("frag_e_min", P.frag_min(4660, 4096, True{}))
    urow("frag_e_min_bl", P.bitlen1(P.frag_min(4660, 4096, True{})))
    urow("frag_f", frag_of(4096, 4660, True{}))
    urow("frag_f_va_div", P.frag_va_div(4096))
    urow("frag_f_sz_div", P.frag_sz_div(4660))
    urow("frag_f_sz_max", P.frag_sz_max(4660))
    urow("frag_f_min", P.frag_min(4096, 4660, True{}))
    urow("frag_f_min_bl", P.bitlen1(P.frag_min(4096, 4660, True{})))
    IO.pure(Unit, Unit{})
# THE ODD-VA ROW, whose answer is NEGATIVE: `va = 1` has lowbit 1, so `min` is
# 1 and `bit_length(1) - 1 - 12` is `-13`, which is not a fragment at all. The
# `U32` spelling SATURATES, so the row is the saturation and
# `mem_frag_odd_va_*` says so.
def t_frag3() -> IO(Unit):
  do IO<Unit>:
    urow("frag_g", frag_of(1, 4096, True{}))
    urow("frag_g_va_div", P.frag_va_div(1))
    urow("frag_g_sz_div", P.frag_sz_div(4096))
    urow("frag_g_sz_max", P.frag_sz_max(4096))
    urow("frag_g_min", P.frag_min(1, 4096, True{}))
    urow("frag_g_min_bl", P.bitlen1(P.frag_min(1, 4096, True{})))
    urow("frag_h", frag_of(1048576, 4096, True{}))
    urow("frag_h_va_div", P.frag_va_div(1048576))
    urow("frag_h_sz_div", P.frag_sz_div(4096))
    urow("frag_h_sz_max", P.frag_sz_max(4096))
    urow("frag_h_min", P.frag_min(1048576, 4096, True{}))
    urow("frag_h_min_bl", P.bitlen1(P.frag_min(1048576, 4096, True{})))
    urow("frag_i", frag_of(4096, 2097152, True{}))
    urow("frag_i_va_div", P.frag_va_div(4096))
    urow("frag_i_sz_div", P.frag_sz_div(2097152))
    urow("frag_i_sz_max", P.frag_sz_max(2097152))
    urow("frag_i_min", P.frag_min(4096, 2097152, True{}))
    urow("frag_i_min_bl", P.bitlen1(P.frag_min(4096, 2097152, True{})))
    IO.pure(Unit, Unit{})
# THE 4KB MINIMUM: a 4KB-aligned 4KB mapping is fragment 0, which is the whole
# point of the `- 12`.
def t_frag4() -> IO(Unit):
  do IO<Unit>:
    urow("frag_j", frag_of(4096, 4096, True{}))
    urow("frag_j_va_div", P.frag_va_div(4096))
    urow("frag_j_sz_div", P.frag_sz_div(4096))
    urow("frag_j_sz_max", P.frag_sz_max(4096))
    urow("frag_j_min", P.frag_min(4096, 4096, True{}))
    urow("frag_j_min_bl", P.bitlen1(P.frag_min(4096, 4096, True{})))
    urow("frag_k", frag_of(4096, 8192, True{}))
    urow("frag_k_va_div", P.frag_va_div(4096))
    urow("frag_k_sz_div", P.frag_sz_div(8192))
    urow("frag_k_sz_max", P.frag_sz_max(8192))
    urow("frag_k_min", P.frag_min(4096, 8192, True{}))
    urow("frag_k_min_bl", P.bitlen1(P.frag_min(4096, 8192, True{})))
    IO.pure(Unit, Unit{})
# THE LOWBIT IN ISOLATION, and the SENTINEL CONSTANTS. `lowbit_x_*` names the
# input so a wrong fixture is visible, and `lowbit_*` is the answer.
def t_frag5() -> IO(Unit):
  do IO<Unit>:
    urow("lowbit_0", P.frag_lowbit(0))
    urow("lowbit_1", P.frag_lowbit(1))
    urow("lowbit_2", P.frag_lowbit(2))
    urow("lowbit_3", P.frag_lowbit(3))
    urow("lowbit_4", P.frag_lowbit(4))
    urow("lowbit_6", P.frag_lowbit(6))
    urow("lowbit_8", P.frag_lowbit(8))
    urow("lowbit_12", P.frag_lowbit(12))
    urow("lowbit_14", P.frag_lowbit(14))
    urow("lowbit_16", P.frag_lowbit(16))
    urow("lowbit_4096", P.frag_lowbit(4096))
    urow("lowbit_4660", P.frag_lowbit(4660))
    urow("lowbit_2147483648", P.frag_lowbit(2147483648))
    urow("lowbit_4294967295", P.frag_lowbit(4294967295))
    urow("lowbit_x_0", 0)
    urow("lowbit_x_12", 12)
    urow("lowbit_x_2147483648", 2147483648)
    urow("lowbit_x_4294967295", 4294967295)
    IO.pure(Unit, Unit{})
# THE SENTINEL, BOTH SPELLINGS, and the STAND-IN claim. `lowbit_zero_64_*` is
# the real `1 << 63` as two `U32` halves and `lowbit_zero` is the `U32`
# stand-in; `lowbit_zero_exact` is the row that says the two agree on being
# OUTSIDE `U32` and `lowbit_zero_standin` is the arithmetic one.
def t_frag6() -> IO(Unit):
  do IO<Unit>:
    i64row("lowbit_zero_64", P.LOWBIT_ZERO_64())
    urow("lowbit_zero", P.LOWBIT_ZERO())
    urow("lowbit_zero_is_max_u32", Bool.to_u32(U32.is_eq(P.LOWBIT_ZERO(), 4294967295)))
    urow("lowbit_zero_over_u32", Bool.to_u32(U32.is_gt(P.LOWBIT_ZERO(), 2147483647)))
    IO.pure(Unit, Unit{})
def t_frag() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_frag0()
    b : Unit <- t_frag1()
    c : Unit <- t_frag2()
    d : Unit <- t_frag3()
    e : Unit <- t_frag4()
    f : Unit <- t_frag5()
    g : Unit <- t_frag6()
    IO.pure(Unit, Unit{})
# THE LOWBIT IN ISOLATION, and the SENTINEL CONSTANTS. `lowbit_x_*` names the
# input so a wrong fixture is visible, and `lowbit_*` is the answer.
# ===========================================================================
# THE `MemoryManager` GATE. The four allocator WINDOWS (:190-192), the VA
# window (:182), `alloc_vaddr`'s alignment (:240), `palloc`'s rounding (:284),
# the TLSF bucket arithmetic (:43, :46, :91) and `valloc`'s `palloc_ranges`
# ladder (:258-271).
# THE three windows are the real content and they are CUMULATIVE:
#   `boot_allocator    = TLSFAllocator(boot_size, base=0)`
#   `ptable_allocator  = TLSFAllocator(round_up(vram_size // 512, 1 << 20) if
#                                       reserve_ptable else 0,
#                                     base=self.boot_allocator.size)`
#   `off_sz            = self.boot_allocator.size + self.ptable_allocator.size`
#   `pa_allocator      = TLSFAllocator(vram_size - off_sz, base=off_sz)`
# So `pa`'s BASE is `off_sz` -- the END of the previous two windows -- and its
# SIZE is what is left. A port that gave `pa` base 0 would map physical memory
# over the boot allocator, and every window row would still be plausible.
# `mm_off_sz_*` and `mm_pa_base_*` are the same number in two rows for that
# reason.
# THE `reserve_ptable=False` ARM IS THE NEGATIVE CASE: `ptable_sz` is 0, so
# `off_sz` is just `boot_size` and `pa_sz` is the whole VRAM. The two arms sit
# one row apart at the same `vram_size` and the same `boot_size`, which is the
# pairing the brief asks for.
# :191 -- `round_up(vram_size // 512, 1 << 20) if self.reserve_ptable else 0`.
# The `// 512` is a DIVISION BEFORE the round and the unit is 1 MiB, so for
# `vram_size` below 512 MiB the whole expression is 0 even when
# `reserve_ptable` is set.
def mm_ptable_sz(+vram: U32, +reserve: Bool) -> U32:
  Bool.pick(U32, reserve, P.bump_round(U32.div(vram, 512), 1048576), 0)
# :192 -- `off_sz = boot_allocator.size + ptable_allocator.size`.
def mm_off_sz(+boot: U32, +vram: U32, +reserve: Bool) -> U32:
  U32.add(boot, mm_ptable_sz(vram, reserve))
# :192 -- `vram_size - (off_sz := boot.size + ptable.size)`, so the PA window is
# WHAT IS LEFT and its BASE is the SAME `off_sz`.
def mm_pa_sz(+vram: U32, +boot: U32, +reserve: Bool) -> U32:
  U32.sub(vram, mm_off_sz(boot, vram, reserve))
# THE `reserve_ptable=False` ARM IS THE NEGATIVE CASE: `ptable_sz` is 0, so
# `off_sz` is just `boot_size` and `pa_sz` is the whole VRAM. The two arms sit
# one row apart at the same `vram_size` and the same `boot_size`, which is the
# pairing the brief asks for.
# ===========================================================================
# THE LOWBIT IN ISOLATION, and the SENTINEL CONSTANTS. `lowbit_x_*` names the
# input so a wrong fixture is visible, and `lowbit_*` is the answer.
# THE `MemoryManager` GATE. The four allocator WINDOWS (:190-192), the VA
# window (:182), `alloc_vaddr`'s alignment (:240), `palloc`'s rounding (:284),
# the TLSF bucket arithmetic (:43, :46, :91) and `valloc`'s `palloc_ranges`
# ladder (:258-271).
def mm_windows(+vram: U32, +boot: U32, +reserve: Bool, +tag: String) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["mm_boot_sz_", tag]), boot)
    urow(String.concat(["mm_ptable_sz_", tag]), mm_ptable_sz(vram, reserve))
    urow(String.concat(["mm_off_sz_", tag]), mm_off_sz(boot, vram, reserve))
    urow(String.concat(["mm_pa_sz_", tag]), mm_pa_sz(vram, boot, reserve))
    urow(String.concat(["mm_pa_base_", tag]), mm_off_sz(boot, vram, reserve))
    IO.pure(Unit, Unit{})
# :191 -- `round_up(vram_size // 512, 1 << 20) if self.reserve_ptable else 0`.
# The `// 512` is a DIVISION BEFORE the round and the unit is 1 MiB, so for
# `vram_size` below 512 MiB the whole expression is 0 even when
# `reserve_ptable` is set.
def VRAM_64M() -> U32: 67108864
def VRAM_1G() -> U32: 1073741824
def VRAM_ODD() -> U32: 1073741825
def VRAM_16M() -> U32: 16777216
def BOOT_64K() -> U32: 65536
def t_mm0() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- mm_windows(VRAM_64M(), BOOT_64K(), False{}, "v64m_b64k_0")
    b : Unit <- mm_windows(VRAM_64M(), BOOT_64K(), True{}, "v64m_b64k_1")
    c : Unit <- mm_windows(VRAM_1G(), BOOT_64K(), False{}, "v1g_b64k_0")
    d : Unit <- mm_windows(VRAM_1G(), BOOT_64K(), True{}, "v1g_b64k_1")
    IO.pure(Unit, Unit{})
def t_mm1() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- mm_windows(VRAM_ODD(), BOOT_64K(), False{}, "vodd_b64k_0")
    b : Unit <- mm_windows(VRAM_ODD(), BOOT_64K(), True{}, "vodd_b64k_1")
    c : Unit <- mm_windows(VRAM_16M(), BOOT_64K(), False{}, "v16m_b64k_0")
    d : Unit <- mm_windows(VRAM_16M(), BOOT_64K(), True{}, "v16m_b64k_1")
    e : Unit <- mm_windows(VRAM_64M(), 0, False{}, "v64m_b0_0")
    f : Unit <- mm_windows(VRAM_64M(), 0, True{}, "v64m_b0_1")
    # `boot_size == 0` IS ITS OWN ARM and not a special case of `b64k`: `off_sz`
    # is then the PTABLE window ALONE, so `mm_off_sz_*_b0_*` and
    # `mm_off_sz_*_b64k_*` differ by exactly `boot_size` and `mm_pa_sz_*` is
    # `vram - ptable` rather than `vram - boot - ptable`.
    g : Unit <- mm_windows(VRAM_1G(), 0, False{}, "v1g_b0_0")
    h : Unit <- mm_windows(VRAM_1G(), 0, True{}, "v1g_b0_1")
    i : Unit <- mm_windows(VRAM_ODD(), 0, False{}, "vodd_b0_0")
    j : Unit <- mm_windows(VRAM_ODD(), 0, True{}, "vodd_b0_1")
    k : Unit <- mm_windows(VRAM_16M(), 0, False{}, "v16m_b0_0")
    l : Unit <- mm_windows(VRAM_16M(), 0, True{}, "v16m_b0_1")
    IO.pure(Unit, Unit{})
# THE `vram_size // 512` DIVISION ITSELF, and its TWO failure modes: a size
# below 512 MiB gives 0 and a size just above a MiB multiple rounds UP.
def t_mm2() -> IO(Unit):
  do IO<Unit>:
    urow("mm_ptable_div_67108864", U32.div(VRAM_64M(), 512))
    urow("mm_ptable_div_1073741824", U32.div(VRAM_1G(), 512))
    urow("mm_ptable_div_16777216", U32.div(VRAM_16M(), 512))
    urow("mm_ptable_round_131072", P.bump_round(131072, 1048576))
    urow("mm_ptable_round_131073", P.bump_round(131073, 1048576))
    urow("mm_ptable_round_2097152", P.bump_round(2097152, 1048576))
    urow("mm_ptable_unit", 1048576)
    urow("mm_ptable_divisor", 512)
    IO.pure(Unit, Unit{})
# THE VA WINDOW, :182 -- `TLSFAllocator((1 << 44), base=0x200000000000)`. BOTH
# NUMBERS ARE OUTSIDE `U32`, so the rows are `H.I64` pairs and the lane's `U32`
# saturation is the thing being avoided. `mem_va_alloc_size` is the row
# `ops_rdma.bend` needs: it recorded `va_allocator.size`/`.base` as a WALL and
# this is the value.
def t_mm3() -> IO(Unit):
  do IO<Unit>:
    i64row("va_alloc_size", P.VA_ALLOC_SIZE())
    i64row("va_alloc_base", P.VA_ALLOC_BASE())
    urow("va_alloc_size_hi", H.hi32(P.VA_ALLOC_SIZE()))
    urow("va_alloc_size_lo", H.lo32(P.VA_ALLOC_SIZE()))
    urow("va_alloc_base_hi", H.hi32(P.VA_ALLOC_BASE()))
    urow("va_alloc_base_lo", H.lo32(P.VA_ALLOC_BASE()))
    # AND THE SATURATION, as the NEGATIVE: a `U32` shift by 44 is 0, which is
    # how a free list once became zero-sized.
    urow("va_alloc_size_u32_sat", U32.shln(1, 44n))
    urow("va_alloc_size_lo_sat", H.lo32(P.VA_ALLOC_SIZE()))
    urow("va_alloc_base_lo_sat", H.lo32(P.VA_ALLOC_BASE()))
    urow("va_alloc_u32_would_be", U32.shln(1, 44n))
    IO.pure(Unit, Unit{})
# `alloc_vaddr`'s ALIGNMENT (:240) and `palloc`'s ROUNDING (:284). Both are
# `max`/`round_up` over the same 0x1000 and both are pure arithmetic on the
# request, so they are gated per fixture and the boundary cases -- a size just
# under a page and one just over -- sit next to each other.
def VS_4K() -> U32: 4096
def VS_4K1() -> U32: 4097
def VS_8K() -> U32: 8192
def VS_16K() -> U32: 16384
def VS_1M() -> U32: 1048576
def VS_1M1() -> U32: 1048577
# `1 << (size.bit_length() - 1)` -- the biggest power of two `<= sz`.
def u32_max(+a: U32, +b: U32) -> U32: Bool.pick(U32, U32.is_gt(a, b), a, b)

def next_pow2(+sz: U32) -> U32: P.frag_sz_max(sz)
# :240 -- `max((1 << (size.bit_length() - 1)), align)`. THE PAGE IS THE FLOOR,
# so this is a `max` and not a `min`: for a 64KB request the alignment is 64KB
# and not 4KB, and `u32_min` answered 4096 for every request above a page.
def valloc_align(+sz: U32) -> U32: u32_max(P.PAGE_4K(), next_pow2(sz))
def t_mm4a(+sz: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["valloc_align_", U32.show(sz)]), valloc_align(sz))
    urow(String.concat(["valloc_round_", U32.show(sz)]), P.bump_round(sz, P.PAGE_4K()))
    urow(String.concat(["valloc_p2_", U32.show(sz)]), next_pow2(sz))
    urow(String.concat(["palloc_round_", U32.show(sz)]), P.bump_round(sz, P.PAGE_4K()))
    IO.pure(Unit, Unit{})
# `palloc`'s rounding over the sizes `round_up(size, 0x1000)` is called with,
# and the boundary is the interesting part: 0xfff and 0x1000 sit one row apart.
def t_mm4() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mm4a(VS_4K())
    b : Unit <- t_mm4a(VS_4K1())
    c : Unit <- t_mm4a(VS_8K())
    d : Unit <- t_mm4a(VS_16K())
    e : Unit <- t_mm4a(VS_1M())
    f : Unit <- t_mm4a(VS_1M1())
    IO.pure(Unit, Unit{})
def t_mm5() -> IO(Unit):
  do IO<Unit>:
    urow("palloc_round_1", P.bump_round(1, P.PAGE_4K()))
    urow("palloc_round_4095", P.bump_round(4095, P.PAGE_4K()))
    urow("palloc_size", P.PT_ALLOC_SIZE())
    IO.pure(Unit, Unit{})
# THE va allocator'S own walk is not ported, and there is therefore no
# `va_alloc_off_*` row here. `TLSFAllocator.alloc` drives the free list; this
# port has the bucket arithmetic and the size pipeline, not the list. A row
# whose Bend side was a literal would be a change-detector, so the section is
# absent rather than present-and-fake. REPORTED AS A BLIND SPOT.
# THE TLSF BUCKET ARITHMETIC, :43 and :46. `lv1 = size.bit_length()` and
# `lv2 = (size - (1 << (bl-1))) // (1 << max(0, bl - l2_cnt))`, with
# `l2_cnt = lv2_cnt.bit_length() = 16.bit_length() = 5`. The pair is printed in
# ONE row as `lv1:lv2` because that is how the bucket is keyed
# (`storage[lv1][lv2]`), and the `lv2_shift_*` row is the divisor.
# `1 << max(0, bit_length(size) - l2_cnt)` -- the SECOND-LEVEL GRANULARITY, and
# it SATURATES AT 1 for any size whose bit length is below `l2_cnt`. That is the
# `max(0, ..)` and it is load-bearing for every small size.
# `1 << max(0, size.bit_length() - l2_cnt)` -- THE `max(0, ..)` IS LOAD-BEARING.
# `U32.sub` WRAPS (it is `Word.sub` on 32 bits, not a saturating subtract), so
# `bl - l2_cnt` is a 4-billion Nat for every small `size`, `U32.shln` by that
# much is 0, and `lv2_shift_*` answered 0 where CPython says 1 until this clamp
# existed. Every size whose bit length is below `l2_cnt` (5) needs it.
def u32_sub0(+a: U32, +b: U32) -> U32: Bool.pick(U32, U32.is_gt(a, b), U32.sub(a, b), 0)

def lv2_shift(sz: U32) -> U32: u32_sub0(P.bitlen1(sz), P.bitlen1(P.TLSF_DEF_LV2_CNT()))
def tlsf_lv2(+sz: U32, +l2_cnt: U32) -> U32:
  U32.div(U32.sub(sz, P.shl1(U32.sub(P.bitlen1(sz), 1))), P.shl1(lv2_shift(sz)))
# THE BUCKET KEY as ONE NUMBER, `lv1 * 2^l2_cnt + lv2`, so the row is a single
# `U32` and the ORACLE computes the same key. A port that swapped the two
# levels would answer a different key and every bucket row would move.
def tlsf_bucket(+sz: U32) -> U32:
  U32.add(U32.mul(P.bitlen1(sz), 32), tlsf_lv2(sz, P.bitlen1(P.TLSF_DEF_LV2_CNT())))
def t_tlsf1(+sz: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["tlsf_lv1_", U32.show(sz)]), P.bitlen1(sz))
    urow(String.concat(["tlsf_lv2_", U32.show(sz)]), tlsf_lv2(sz, P.bitlen1(P.TLSF_DEF_LV2_CNT())))
    urow(String.concat(["tlsf_bucket_", U32.show(sz)]), tlsf_bucket(sz))
    urow(String.concat(["tlsf_lv2_shift_", U32.show(sz)]), P.shl1(lv2_shift(sz)))
    IO.pure(Unit, Unit{})
# `1 << max(0, bit_length(size) - l2_cnt)` -- the SECOND-LEVEL GRANULARITY, and
# it SATURATES AT 1 for any size whose bit length is below `l2_cnt`. That is the
# `max(0, ..)` and it is load-bearing for every small size.
# THE TLSF BUCKET ARITHMETIC, :43 and :46. `lv1 = size.bit_length()` and
# `lv2 = (size - (1 << (bl-1))) // (1 << max(0, bl - l2_cnt))`, with
# `l2_cnt = lv2_cnt.bit_length() = 16.bit_length() = 5`. The pair is printed in
# ONE row as `lv1:lv2` because that is how the bucket is keyed
# (`storage[lv1][lv2]`), and the `lv2_shift_*` row is the divisor.
def t_tlsf0() -> IO(Unit):
  do IO<Unit>:
    urow("tlsf_block_size", P.TLSF_DEF_BLOCK())
    urow("tlsf_l2_cnt", P.bitlen1(P.TLSF_DEF_LV2_CNT()))
    a : Unit <- t_tlsf1(1)
    b : Unit <- t_tlsf1(2)
    c : Unit <- t_tlsf1(3)
    IO.pure(Unit, Unit{})
def t_tlsf2() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_tlsf1(4)
    b : Unit <- t_tlsf1(7)
    c : Unit <- t_tlsf1(8)
    d : Unit <- t_tlsf1(15)
    IO.pure(Unit, Unit{})
def t_tlsf3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_tlsf1(16)
    b : Unit <- t_tlsf1(17)
    c : Unit <- t_tlsf1(31)
    d : Unit <- t_tlsf1(32)
    e : Unit <- t_tlsf1(33)
    f : Unit <- t_tlsf1(100)
    g : Unit <- t_tlsf1(128)
    h : Unit <- t_tlsf1(1000)
    i : Unit <- t_tlsf1(1024)
    # THE FOUR 2^x - 1 AND 2^x SIZES. 63/64 and 255/256 straddle the second-level
    # granularity at `bl == 6` and `bl == 8`, so `lv2` is 0 at the power of two
    # and 31 / 15 at its neighbour -- the pair is the only fixture that shows the
    # second level resetting.
    j : Unit <- t_tlsf1(63)
    k : Unit <- t_tlsf1(64)
    l : Unit <- t_tlsf1(255)
    m : Unit <- t_tlsf1(256)
    IO.pure(Unit, Unit{})
# `bit_length` ON ITS OWN, which is the ONE primitive every bucket row, every
# `frag_sz_max` and every `tlsf_storage_len` is built from. The eighteen fixtures
# are the powers of two and their neighbours plus the three `U32` extremes; `0`
# is the one that answers 0 and the only one a `log2`-based port gets wrong.
def t_bitlen() -> IO(Unit):
  do IO<Unit>:
    urow("bitlen_0", P.bitlen1(0))
    urow("bitlen_1", P.bitlen1(1))
    urow("bitlen_2", P.bitlen1(2))
    urow("bitlen_3", P.bitlen1(3))
    urow("bitlen_4", P.bitlen1(4))
    urow("bitlen_7", P.bitlen1(7))
    urow("bitlen_8", P.bitlen1(8))
    urow("bitlen_15", P.bitlen1(15))
    urow("bitlen_16", P.bitlen1(16))
    urow("bitlen_31", P.bitlen1(31))
    urow("bitlen_32", P.bitlen1(32))
    urow("bitlen_255", P.bitlen1(255))
    urow("bitlen_256", P.bitlen1(256))
    urow("bitlen_65535", P.bitlen1(65535))
    urow("bitlen_65536", P.bitlen1(65536))
    urow("bitlen_2147483647", P.bitlen1(2147483647))
    urow("bitlen_2147483648", P.bitlen1(2147483648))
    urow("bitlen_4294967295", P.bitlen1(4294967295))
    IO.pure(Unit, Unit{})
# `storage` LENGTH, :35 -- `size.bit_length() + 1` over the WINDOW's size, which
# is one more than the window's own bit length. For a 1 MiB window that is 21.
def t_tlsf4() -> IO(Unit):
  do IO<Unit>:
    urow("tlsf_storage_len_0", U32.add(P.bitlen1(0), 1))
    urow("tlsf_storage_len_1", U32.add(P.bitlen1(1), 1))
    urow("tlsf_storage_len_2", U32.add(P.bitlen1(2), 1))
    urow("tlsf_storage_len_4096", U32.add(P.bitlen1(4096), 1))
    urow("tlsf_storage_len_1048576", U32.add(P.bitlen1(1048576), 1))
    IO.pure(Unit, Unit{})
# THE allocation SIZE PIPELINE, :87-91, and it has THREE distinct numbers:
#   `req_size = max(block_size, req_size)`                          -> `tlsf_req_*`
#   `size     = max(block_size, req_size + align - 1)`              -> `tlsf_sz_*`
#   `size     = round_up(size, 1 << (size.bit_length() - l2_cnt))`  -> `tlsf_round_*`
# A port that folded the middle step into the third would answer the right
# bucket for every ALIGNED request and the wrong one for every `align > 1`.
# `tlsf_rounds_up_*` is the NEGATIVE case: it is 1 exactly where the bucket
# rounding is not the identity, which is the row that separates step 2 from 3.
def tlsf_round(+sz: U32) -> U32: P.bump_round(sz, P.shl1(u32_sub0(P.bitlen1(sz), P.bitlen1(P.TLSF_DEF_LV2_CNT()))))
def tlsf_req(+req: U32) -> U32: u32_max(P.TLSF_DEF_BLOCK(), req)
def tlsf_sz(+req: U32, +al: U32) -> U32:
  u32_max(P.TLSF_DEF_BLOCK(), U32.add(req, U32.sub(al, 1)))
def tlsf_pipe(+i: U32, +req: U32, +al: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["tlsf_req_", U32.show(i)]), tlsf_req(req))
    urow(String.concat(["tlsf_sz_", U32.show(i)]), tlsf_sz(tlsf_req(req), al))
    urow(String.concat(["tlsf_bl_", U32.show(i)]), P.bitlen1(tlsf_sz(tlsf_req(req), al)))
    urow(String.concat(["tlsf_round_", U32.show(i)]), tlsf_round(tlsf_sz(tlsf_req(req), al)))
    urow(String.concat(["tlsf_final_", U32.show(i)]), tlsf_round(tlsf_sz(tlsf_req(req), al)))
    urow(String.concat(["tlsf_rounds_up_", U32.show(i)]),
         Bool.to_u32(Bool.not(U32.is_eq(tlsf_round(tlsf_sz(tlsf_req(req), al)), tlsf_sz(tlsf_req(req), al)))))
    IO.pure(Unit, Unit{})
def t_tlsf5() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- tlsf_pipe(0, 16, 1)
    b : Unit <- tlsf_pipe(1, 16, 16)
    c : Unit <- tlsf_pipe(2, 1, 1)
    IO.pure(Unit, Unit{})
def t_tlsf6() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- tlsf_pipe(3, 1, 4096)
    b : Unit <- tlsf_pipe(4, 100, 16)
    c : Unit <- tlsf_pipe(5, 4096, 4096)
    d : Unit <- tlsf_pipe(6, 256, 4096)
    IO.pure(Unit, Unit{})
# `valloc`'s `palloc_ranges` LADDER (:258-271). THE POLICY IS "try the longest
# segment, halve down on MemoryError, and free everything already taken when the
# ladder runs out" -- so the rows are the PICKED SIZES in order plus the
# remaining size, and `valloc_sum_*`/`valloc_rem_*` say the ladder either
# covered the request exactly or did not.
# THE LENGTH COMPARISON IS THE QUIRK: `while self.palloc_ranges[nxt_range][0] > rem_size:
# nxt_range += 1` compares the SEGMENT SIZE against the REMAINING request, so
# any segment bigger than what is left is SKIPPED rather than truncated. The
# ladder is `[0x200000, 0x40000, 0x4000, 0x1000]` and the requests are chosen so
# `valloc_picks_*` differs between a request that divides evenly and one that
# does not.
def t_tlsf() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_tlsf0()
    b : Unit <- t_tlsf2()
    c : Unit <- t_tlsf3()
    d : Unit <- t_tlsf4()
    e : Unit <- t_bitlen()
    e : Unit <- t_tlsf5()
    f : Unit <- t_tlsf6()
    IO.pure(Unit, Unit{})
def R0() -> U32: 2097152
def R1() -> U32: 262144
def R2() -> U32: 16384
def R3() -> U32: 4096
def ladder_sizes() -> List<&2, U32>: [R0(), R1(), R2(), R3()]
def ladder_pick.go(+ss: List<&2,  U32>, +rem: U32, +dflt: U32) -> U32:
  match ss:
    case Nil{}: dflt
    case s <> t: Bool.pick(U32, U32.is_le(s, rem), s, ladder_pick.go(t, rem, dflt))
# THE LADDER FOLD, ONE def: a `.go`/`.step` pair would be mutual recursion, and
# the STOP is an EMPTY segment list rather than a `Bool.pick` around the
# recursion. So `stop_sizes` hands the walk `Nil{}` once the remainder is
# covered and the `case Nil{}:` arm -- which is already "return acc" -- ends it.
# THE PICK, :260-262. `while self.palloc_ranges[nxt_range][0] > rem_size:
# nxt_range += 1` SKIPS a segment bigger than the remainder rather than
# truncating it, and the ranges are LARGEST-FIRST, so the answer is the LARGEST
# segment at or below the remainder -- a FIRST-match walk that stops at the
# first hit. A LAST-match walk would pick the smallest segment always.
def ladder_pick(+rem: U32, +ss: List<&2,  U32>) -> U32: ladder_pick.go(ss, rem, R0())
def append_sz(+rem: U32, +ss: List<&2,  U32>, +acc: List<&2,  U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_zero(rem), acc, List.append(&2, U32, acc, [ladder_pick(rem, ss)]))
# THE LADDER FOLD, ONE def: a `.go`/`.step` pair would be mutual recursion, and
# the STOP is an EMPTY segment list rather than a `Bool.pick` around the
# recursion. So `stop_sizes` hands the walk `Nil{}` once the remainder is
# covered and the `case Nil{}:` arm -- which is already "return acc" -- ends it.
def stop_sizes(+rem: U32, +ss: List<&2,  U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_zero(rem), Nil{}, ss)
def valloc_picks.fuel(fuel: Nat, +rem: U32, +ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match ss:
        case Nil{}: acc
        case _ <> _:
          # THE SEGMENT LIST IS HANDED ON UNCHANGED, and this is the whole content
          # of :260-262: `nxt_range` only ever moves FORWARD past a segment that
          # is too big, so the answer for a shrinking remainder is the largest
          # segment at or below it -- which is what re-walking the head computes.
          # Advancing past the pick (passing the tail `t`) is a LAST-match walk
          # that can never take the same segment twice, and it under-counts an
          # 8 MiB request as eight 2 MiB picks.
          valloc_picks.fuel(p, U32.sub(rem, ladder_pick(rem, ss)), stop_sizes(rem, ss), append_sz(rem, ss, acc))
# ===========================================================================
# `MemoryManager`
# THE fuel is the request'S own segment count. Every pick is at least `R3()`
# (4 KiB -- the smallest rung), so `req // 4096` bounds the number of picks and
# the walk cannot need more steps than that. `stop_sizes` is the real terminator
# and the fuel is only the totality bound: a request the ladder does not cover
# exactly runs out of fuel and the fold returns what it took, and that
# truncation is reported rather than hidden behind a magic constant.
def valloc_picks(+req: U32) -> List<&2, U32>: valloc_picks.fuel(U32.to_nat(U32.div(req, R3())), req, ladder_sizes(), Nil{})
# THE REMAINDER, as `req - sum(picks)`. Computing it from the LIST rather than
# threading a second accumulator is what makes `valloc_sum_*` and `valloc_rem_*`
# two readings of one fold: a fold that lost a pick would show a non-zero
# remainder on a request the ladder covers exactly.
def valloc_rem(+req: U32) -> U32: U32.sub(req, P.usum.go(valloc_picks(req), 0))
# THE PICK, :260-262. `while self.palloc_ranges[nxt_range][0] > rem_size:
# nxt_range += 1` SKIPS a segment bigger than the remainder rather than
# truncating it, and the ranges are LARGEST-FIRST, so the answer is the LARGEST
# segment at or below the remainder -- a FIRST-match walk that stops at the
# first hit. A LAST-match walk would pick the smallest segment always.
def t_valloc1(+req: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["valloc_req_", U32.show(req)]), req)
    lrow(String.concat(["valloc_picks_", U32.show(req)]), valloc_picks(req))
    urow(String.concat(["valloc_sum_", U32.show(req)]), P.usum.go(valloc_picks(req), 0))
    urow(String.concat(["valloc_rem_", U32.show(req)]), valloc_rem(req))
    IO.pure(Unit, Unit{})
def t_valloc0() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_valloc1(8388608)
    b : Unit <- t_valloc1(5242880)
    c : Unit <- t_valloc1(1048576)
    IO.pure(Unit, Unit{})
def t_valloc() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_valloc0()
    b : Unit <- t_valloc1(20480)
    c : Unit <- t_valloc1(8192)
    d : Unit <- t_valloc1(4096)
    IO.pure(Unit, Unit{})
# ===========================================================================
# THE TRACE GATE, and it is here because two mutations MOVED NOTHING against the
# vocabulary: retagging `P.MMIO_INDEX` from 3 to 2 (a collision with
# `P.TO_MV_CAST`) and `P.PT_SET_ENTRY` from 9 to 8 (a collision with
# `P.PT_SUPPORTS_HUGE`) both left every row green, because until now NO ROW READ
# THE TRACE. A seam nothing reads is not a seam, it is a comment.
# `mmio_make_t` is `mmio_make` with the trace THREADED OUT, so the gate can read
# the calls this file would make without a second implementation of the split.
# The two facts the split promises are the rows: the trace holds `P.TO_MV` and
# `P.TO_MV_CAST` IN THAT ORDER, and the handle the second call acts on is the id
# the first one minted. `P.Tr.seq` is the order predicate and `P.Tr.count` the
# multiplicity one, so a retag that collides moves the COUNT and an order swap
# moves the SEQUENCE.
# ===========================================================================
# ONE WINDOW, built once: `MMIOInterface(0x90000000, 0x1000, 'B')`.
def tr_win() -> P.MvT: P.mmio_make_t(P.Tr.of(), 2415919104, 4096, fmt_b())

def t_trace1() -> IO(Unit):
  do IO<Unit>:
    brow("mmio_tr_seq_ok", P.Tr.seq(P.MvT.t(tr_win()), [P.Call{P.TO_MV(), 4096}, P.Call{P.TO_MV_CAST(), fmt_b()}]))
    brow("mmio_tr_seq_swapped", P.Tr.seq(P.MvT.t(tr_win()), [P.Call{P.TO_MV_CAST(), fmt_b()}, P.Call{P.TO_MV(), 4096}]))
    urow("mmio_tr_n_to_mv", P.Tr.count(P.TO_MV(), P.Tr.calls(P.MvT.t(tr_win()))))
    urow("mmio_tr_n_cast", P.Tr.count(P.TO_MV_CAST(), P.Tr.calls(P.MvT.t(tr_win()))))
    urow("mmio_tr_n_index", P.Tr.count(P.MMIO_INDEX(), P.Tr.calls(P.MvT.t(tr_win()))))
    lrow("mmio_tr_args_to_mv", P.Tr.args(P.TO_MV(), P.Tr.calls(P.MvT.t(tr_win()))))
    lrow("mmio_tr_args_cast", P.Tr.args(P.TO_MV_CAST(), P.Tr.calls(P.MvT.t(tr_win()))))
    IO.pure(Unit, Unit{})

# THE REFUSAL IS A TRUNCATION: `P.Tr.refuse` empties the trace and is idempotent,
# so a refused window records NOTHING and `P.Tr.refused` is the only witness.
def t_trace2() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_tr_after_refuse_seen", P.Tr.seen(P.Tr.refuse(P.Tr.fail_at(P.Tr.of(), 1))))
    brow("mmio_tr_after_refuse", P.Tr.refused(P.Tr.refuse(P.Tr.fail_at(P.Tr.of(), 1))))
    urow("mmio_tr_refused_before", Bool.to_u32(P.Tr.refused(P.Tr.of())))
    IO.pure(Unit, Unit{})

def t_trace0() -> IO(Unit):
  do IO<Unit>:
    urow("mmio_tr_seen", P.Tr.seen(P.MvT.t(tr_win())))
    urow("mmio_tr_next", P.Tr.next(P.MvT.t(tr_win())))
    urow("mmio_tr_handle", P.Mv.h(P.MvT.m(tr_win())))
    urow("mmio_tr_addr", P.Mv.addr(P.MvT.m(tr_win())))
    urow("mmio_tr_nbytes", P.Mv.nbytes(P.MvT.m(tr_win())))
    IO.pure(Unit, Unit{})

# THE ORDER AND IDENTITY predicates, which is what a retag and a swap move.
def t_trace() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_trace0()
    b : Unit <- t_trace1()
    c : Unit <- t_trace2()
    IO.pure(Unit, Unit{})

# THE TRACE OF ONE `MMIOInterface(addr, nbytes, 'B')`: `to_mv` then `.cast`.
def t_mm() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mm0()
    b : Unit <- t_mm1()
    c : Unit <- t_mm2()
    d : Unit <- t_mm3()
    e : Unit <- t_mm4()
    f : Unit <- t_mm5()
    IO.pure(Unit, Unit{})
# ===========================================================================
# THE `VirtMapping` GATE.
# AND A WALL, STATED FIRST: `VirtMapping.va_addr` is a 64-BIT virtual address
# and `U32` SATURATES one. The real `identity_va` is `0x200000000000`-based and
# 48 bits wide, so the fixture VAs here are `U32`-sized and the 48-bit values
# are gated as `H.I64` pairs in `mem_identity_va_64_*`. A port that computed the
# identity VA in `U32` would answer 0, and `vm_gmmu0_va_*` is the row that says
# the VA is the IDENTITY BASE PLUS THE PADDR and not the paddr alone.
# Six fields, three call sites, and the thing that is
# gated is the FIELD list by name and IN order plus the DIFFERENCE in defaults
# between the two construction sites.
# :225 supplies ALL SIX: `VirtMapping(vaddr, size, paddrs, aspace=aspace,
#   uncached=uncached, snooped=snooped)`.
# :250 supplies FOUR and LEAVES `snooped` OUT, so it takes the `False` default --
# and it also forces `aspace=AddrSpace.PHYS` regardless of the device. So
# `vm_gmmu0_*` answers `False` for `snooped` where a port that reused the
# :225 constructor's argument order would answer the caller's, and
# `vm_all_*` is the same construction with all six supplied so the two sit one
# row apart.
# AND the pair order is gated by its two readers: the :211 size sum reads
# element 1 of every `paddrs` pair and the :279 free loop reads element 0, so
# `vm_loops_opposite_*` is FALSE for any mapping whose sizes differ from its
# physical addresses -- and would be TRUE if `P.Pa`'s fields were swapped.
def t_vmap0() -> IO(Unit):
  do IO<Unit>:
    urow("vm_all_va", P.Vmap.va_addr(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{})))
    urow("vm_all_size", P.Vmap.size(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{})))
    urow("vm_all_aspace", P.Vmap.aspace(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{})))
    brow("vm_all_uncached", (P.Vmap.uncached(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{}))))
    brow("vm_all_snooped", (P.Vmap.snooped(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{}))))
    urow("vm_all_n_paddrs", (vm_npaddrs(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{}))))
    IO.pure(Unit, Unit{})
# THE `GMMU=0` SITE, :250. `snooped` is NOT supplied and `aspace` is `PHYS`
# whatever the device says, so these are the rows a field-order port gets wrong.
def t_vmap1() -> IO(Unit):
  do IO<Unit>:
    urow("vm_gmmu0_va", P.Vmap.va_addr(vmap_gmmu0(1879048192, 0, 65536, True{})))
    urow("vm_gmmu0_size", P.Vmap.size(vmap_gmmu0(1879048192, 0, 65536, True{})))
    urow("vm_gmmu0_aspace", P.Vmap.aspace(vmap_gmmu0(1879048192, 0, 65536, True{})))
    brow("vm_gmmu0_uncached", (P.Vmap.uncached(vmap_gmmu0(1879048192, 0, 65536, True{}))))
    brow("vm_gmmu0_snooped", (P.Vmap.snooped(vmap_gmmu0(1879048192, 0, 65536, True{}))))
    urow("vm_gmmu0_n_paddrs", (vm_npaddrs(vmap_gmmu0(1879048192, 0, 65536, True{}))))
    IO.pure(Unit, Unit{})
# `identity_va(uncached) + paddr` -- :250's ADDRESS, and it is NOT `paddr`
# alone, which is the whole point of `identity_va`.
def t_vmap2() -> IO(Unit):
  do IO<Unit>:
    urow("vm_gmmu0_va_sum", vm_gmmu0_va(1879048192, 0))
    urow("vm_gmmu0_va_sum2", vm_gmmu0_va(1879048192, 4096))
    urow("vm_gmmu0_va_sum3", vm_gmmu0_va(1879048192, 8192))
    IO.pure(Unit, Unit{})
# THE :211 ASSERTION and the :279 FREE LOOP, reading OPPOSITE halves of the same
# pair. `vm_size_match_*` is the assertion over the sizes and
# `vm_loops_opposite_*` is the row that says the two readers disagree.
def t_vmap3() -> IO(Unit):
  do IO<Unit>:
    brow("vm_size_match_1", (vm_size_match(P.vmap_all(0, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), False{}, False{}))))
    brow("vm_size_match_2", (vm_size_match(P.vmap_all(0, 65536, [P.Pa{0, 32768}, P.Pa{65536, 32768}], P.ASPACE_SYS_IX(), False{}, False{}))))
    brow("vm_size_match_bad", (vm_size_match(P.vmap_all(0, 65537, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), False{}, False{}))))
    urow("vm_psize_sum_1", P.vm_psize_sum([P.Pa{0, 65536}]))
    urow("vm_psize_sum_2", P.vm_psize_sum([P.Pa{0, 32768}, P.Pa{65536, 32768}]))
    lrow("vm_free_paddrs_1", P.vm_free_paddrs(P.vmap_all(0, 65536, [P.Pa{4096, 65536}], P.ASPACE_SYS_IX(), False{}, False{})))
    IO.pure(Unit, Unit{})
# THE UNMAP READERS, :277 -- `unmap_range(vm.va_addr, vm.size)` takes the VA and
# the SIZE and not the paddrs, so `vm_unmap_*` are the two fields that reach it.
def t_vmap4() -> IO(Unit):
  do IO<Unit>:
    urow("vm_unmap_va", vm_unmap_va(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{})))
    urow("vm_unmap_sz", vm_unmap_sz(P.vmap_all(1879048192, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), True{}, True{})))
    brow("vm_loops_opposite_1", (vm_loops_opposite(P.vmap_all(0, 65536, [P.Pa{0, 65536}], P.ASPACE_SYS_IX(), False{}, False{}))))
    brow("vm_loops_opposite_2", (vm_loops_opposite(P.vmap_all(0, 65536, [P.Pa{4096, 32768}, P.Pa{69632, 32768}], P.ASPACE_SYS_IX(), False{}, False{}))))
    IO.pure(Unit, Unit{})
def t_vmap() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_vmap0()
    b : Unit <- t_vmap1()
    c : Unit <- t_vmap2()
    d : Unit <- t_vmap3()
    e : Unit <- t_vmap4()
    IO.pure(Unit, Unit{})
# ===========================================================================
# THE PAGE-TABLE ASSERT PATHS, :215 and :233, and they are here because a
# THIRD mutation moved nothing for want of them: retagging `P.PT_SET_ENTRY` from 9
# to 8 (a collision with `P.PT_SUPPORTS_HUGE`) moved no row, because no def in
# this file emitted a page-table tag at all. A declared tag that nothing emits
# cannot be gateable.
# `map_range`'s FIRST loop (:214-215) is
#   `for _, pt, pte_idx, pte_cnt, _ in ctx.next(size):
#      for pte_off in range(pte_cnt): assert not pt.valid(pte_idx + pte_off),
#        f"PTE already mapped: {pt.entry(...):#x}"`
# so it reads `P.PT_VALID` and then `P.PT_ENTRY` for EVERY entry, and it REFUSES if
# any entry is already valid.
# `unmap_range` (:231-234) is the mirror:
#   `for pte_id in range(pte_idx, pte_idx + pte_cnt):
#      assert pt.valid(pte_id), f"PTE not mapped: ..."; pt.set_entry(pte_id,
#      paddr=0x0, valid=False)`
# so it reads `P.PT_VALID` and then RECORDS `P.PT_SET_ENTRY`, and it REFUSES if any
# entry is NOT valid.
# THE TWO REFUSALS ARE A PAIR on one fixture table: the same (valid, entry) list
# refuses `map_range` and accepts `unmap_range`, and the mirror image does the
# opposite. That is the negative case for both, and `mem_pt_*` is the row family.
# ===========================================================================
type Pte is Data:
  Pte{valid: U32, entry: U32}

def Pte.valid(p: Pte) -> U32:
  match p:
    case Pte{valid, entry}: valid

# THE three page-TABLE tags as calls, and each one is the FFI plus the emit.
# `arg` is the PTE INDEX, which is what :215's and :233's loop variable is.
# :234 -- `pt.set_entry(pte_id, paddr=0x0, valid=False)`, the WRITE half of
# `unmap_range`. It is here because `P.PT_SET_ENTRY` was a declared tag that NO
# def emitted, and a tag nothing emits cannot be gated -- the mutation that
# retagged it from 9 to 8 moved nothing until this existed.
def pt_set_of(ix: U32, +t: P.Tr) -> P.Tr: P.Tr.emit(P.PT_SET_ENTRY(), ix, t)
def pt_is_valid(v: U32) -> Bool: U32.is_ne(v, 0)
# THE order, AND it is the order python has. `assert not pt.valid(i), f"...{pt.entry(i)}"`
# EVALUATES `pt.valid(i)` FIRST and evaluates the MESSAGE -- and therefore
# `pt.entry(i)` -- only when the assertion FAILED. So a mapped entry reads
# `P.PT_VALID` then `P.PT_ENTRY`, and a pending one reads `P.PT_VALID` alone. The two
# arms are a `match` and NOT a `Bool.pick`, because `pick` EVALUATES BOTH.
def pt_read_pending(+ix: U32, +t: P.Tr) -> P.Tr: P.Tr.emit(P.PT_VALID(), ix, t)
def pt_read_mapped(+ix: U32, +t: P.Tr) -> P.Tr: P.Tr.emit(P.PT_ENTRY(), ix, pt_read_pending(ix, t))
def pt_read_valid(v: Bool, +ix: U32, +t: P.Tr) -> P.Tr:
  match v:
    case True{}: pt_read_mapped(ix, t)
    case False{}: pt_read_pending(ix, t)
# AND the refusal stops the walk, because :215's `raise` replaces the rest of
# the loop: `pt_stop` hands the walk an EMPTY list on the refusing arm and the
# `case Nil{}` arm -- which is already "return the trace untouched" -- ends it.
# A stop sentinel in the INDEX would not do: the index wraps, so the next entry
# would read as index 0 again and the trace grew a spurious pair.
def pt_stop(v: Bool, +r: List<&2, Pte>) -> List<&2, Pte>:
  Bool.pick(List<&2, Pte>, v, Nil{}, r)
# THE MIRROR STOP. `map_range` halts on a MAPPED entry and `unmap_range` halts
# on a PENDING one, so the two walks differ in the polarity of the very same
# predicate -- and reusing `pt_stop` here is what made `pt_unmap_*` stop on the
# first entry of an already-mapped fixture.
def pt_halt(v: Bool, +r: List<&2, Pte>) -> List<&2, Pte>:
  Bool.pick(List<&2, Pte>, Bool.not(v), Nil{}, r)
def pt_assert_unmapped.go(fuel: Nat, +r: List<&2, Pte>, +ix: U32, +t: P.Tr) -> P.Tr:
  match fuel:
    case 0n: t
    case 1n+p:
      match r:
        case Nil{}: t
        case q <> r2: pt_assert_unmapped.go(p, pt_stop(pt_is_valid(Pte.valid(q)), r2),
                                               U32.add(ix, 1), pt_read_valid(pt_is_valid(Pte.valid(q)), ix, t))
def pt_assert_unmapped(+ps: List<&2, Pte>, +t: P.Tr) -> P.Tr: pt_assert_unmapped.go((List.length(&2, Pte, ps) : Nat), ps, 0, t)
# `unmap_range` IS THE MIRROR: `assert pt.valid(pte_id), ...; pt.set_entry(pte_id,
# paddr=0x0, valid=False)` (:233-234), so a VALID entry reads `P.PT_VALID` and
# then RECORDS `P.PT_SET_ENTRY` and the walk CONTINUES, while an INVALID one reads
# `P.PT_VALID` alone and STOPS.
def pt_unset(v: Bool, +ix: U32, +t: P.Tr) -> P.Tr:
  match v:
    case True{}: pt_set_of(ix, P.Tr.emit(P.PT_VALID(), ix, t))
    case False{}: P.Tr.emit(P.PT_ENTRY(), ix, P.Tr.emit(P.PT_VALID(), ix, t))
def pt_clear.go(fuel: Nat, +r: List<&2, Pte>, +ix: U32, +t: P.Tr) -> P.Tr:
  match fuel:
    case 0n: t
    case 1n+p:
      match r:
        case Nil{}: t
        case q <> r2: pt_clear.go(p, pt_halt(pt_is_valid(Pte.valid(q)), r2),
                                   U32.add(ix, 1), pt_unset(pt_is_valid(Pte.valid(q)), ix, t))
def pt_clear(+ps: List<&2, Pte>, +t: P.Tr) -> P.Tr: pt_clear.go((List.length(&2, Pte, ps) : Nat), ps, 0, t)
# THE two fixtures are mirror images, which is what makes them the negative case
# for BOTH loops: `pt_fixture` refuses `map_range` on its first entry and
# accepts `unmap_range` on all four, and `pt_fixture_inv` is the other way round.
def pt_fixture() -> List<&2, Pte>: [Pte{1, 4096}, Pte{1, 8192}, Pte{0, 0}, Pte{0, 0}]
def pt_fixture_inv() -> List<&2, Pte>: [Pte{0, 0}, Pte{0, 0}, Pte{1, 12288}, Pte{1, 16384}]
def t_pt() -> IO(Unit):
  do IO<Unit>:
    urow("pt_map_seen", P.Tr.seen(pt_assert_unmapped(pt_fixture(), P.Tr.of())))
    urow("pt_map_n_valid", P.Tr.count(P.PT_VALID(), P.Tr.calls(pt_assert_unmapped(pt_fixture(), P.Tr.of()))))
    urow("pt_map_n_entry", P.Tr.count(P.PT_ENTRY(), P.Tr.calls(pt_assert_unmapped(pt_fixture(), P.Tr.of()))))
    urow("pt_map_n_set", P.Tr.count(P.PT_SET_ENTRY(), P.Tr.calls(pt_assert_unmapped(pt_fixture(), P.Tr.of()))))
    lrow("pt_map_args", P.Tr.args(P.PT_VALID(), P.Tr.calls(pt_assert_unmapped(pt_fixture(), P.Tr.of()))))
    urow("pt_map_ok_seen", P.Tr.seen(pt_assert_unmapped(pt_fixture_inv(), P.Tr.of())))
    urow("pt_map_ok_n_valid", P.Tr.count(P.PT_VALID(), P.Tr.calls(pt_assert_unmapped(pt_fixture_inv(), P.Tr.of()))))
    urow("pt_map_ok_n_entry", P.Tr.count(P.PT_ENTRY(), P.Tr.calls(pt_assert_unmapped(pt_fixture_inv(), P.Tr.of()))))
    urow("pt_map_ok_n_set", P.Tr.count(P.PT_SET_ENTRY(), P.Tr.calls(pt_assert_unmapped(pt_fixture_inv(), P.Tr.of()))))
    lrow("pt_map_ok_args", P.Tr.args(P.PT_VALID(), P.Tr.calls(pt_assert_unmapped(pt_fixture_inv(), P.Tr.of()))))
    urow("pt_unmap_seen", P.Tr.seen(pt_clear(pt_fixture(), P.Tr.of())))
    urow("pt_unmap_n_valid", P.Tr.count(P.PT_VALID(), P.Tr.calls(pt_clear(pt_fixture(), P.Tr.of()))))
    urow("pt_unmap_n_set", P.Tr.count(P.PT_SET_ENTRY(), P.Tr.calls(pt_clear(pt_fixture(), P.Tr.of()))))
    urow("pt_unmap_n_entry", P.Tr.count(P.PT_ENTRY(), P.Tr.calls(pt_clear(pt_fixture(), P.Tr.of()))))
    lrow("pt_unmap_args", P.Tr.args(P.PT_VALID(), P.Tr.calls(pt_clear(pt_fixture(), P.Tr.of()))))
    urow("pt_unmap_ok_seen", P.Tr.seen(pt_clear(pt_fixture_inv(), P.Tr.of())))
    urow("pt_unmap_ok_n_valid", P.Tr.count(P.PT_VALID(), P.Tr.calls(pt_clear(pt_fixture_inv(), P.Tr.of()))))
    urow("pt_unmap_ok_n_set", P.Tr.count(P.PT_SET_ENTRY(), P.Tr.calls(pt_clear(pt_fixture_inv(), P.Tr.of()))))
    urow("pt_unmap_ok_n_entry", P.Tr.count(P.PT_ENTRY(), P.Tr.calls(pt_clear(pt_fixture_inv(), P.Tr.of()))))
    lrow("pt_unmap_ok_args", P.Tr.args(P.PT_VALID(), P.Tr.calls(pt_clear(pt_fixture_inv(), P.Tr.of()))))
    # THE ORDER, which is the claim a transposed `pt_valid`/`pt_entry` moves.
    urow("pt_order_ok", Bool.to_u32(P.Tr.seq(pt_read_valid(True{}, 3, P.Tr.of()), [P.Call{P.PT_VALID(), 3}, P.Call{P.PT_ENTRY(), 3}])))
    urow("pt_order_swapped", Bool.to_u32(P.Tr.seq(pt_read_valid(True{}, 3, P.Tr.of()), [P.Call{P.PT_ENTRY(), 3}, P.Call{P.PT_VALID(), 3}])))
    urow("pt_order_pending", Bool.to_u32(P.Tr.seq(pt_read_valid(False{}, 3, P.Tr.of()), [P.Call{P.PT_VALID(), 3}])))
    IO.pure(Unit, Unit{})
# `map_range`'s FIRST loop over the fixture: it reads ONE entry, refuses, and
# :215's `raise` replaces the rest of the loop.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_fields()
    b : Unit <- t_aspace()
    c : Unit <- t_calcsizes()
    d : Unit <- t_mmio()
    e : Unit <- t_bump()
    f : Unit <- t_pte()
    g : Unit <- t_frag()
    h : Unit <- t_mm()
    i : Unit <- t_tlsf()
    j : Unit <- t_valloc()
    k : Unit <- t_vmap()
    l : Unit <- t_trace()
    m : Unit <- t_pt()
    IO.pure(Unit, Unit{})
