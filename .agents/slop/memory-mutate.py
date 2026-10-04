#!/usr/bin/env python3
"""memory-mutate.py -- mutation harness for tinybendygrad/runtime/support/memory.bend,
on a STAGED MIRROR.

    .agents/slop/memory-mutate.py [name ...]
    .agents/slop/memory-mutate.py --report FILE

ONE ENTRY PER PORTED RULE.  Each mutation is a whole-line `name=value` edit to a COPY
of the .bend file, and the report is WHICH ROWS MOVED BY NAME -- not whether the
harness saw anything, because a name-comparing harness has reported 0 for all 30
mutations in one unit of this project and all 68 in another.

CONVERTED 2026-10-04.  The old harness wrote `memory.bend.mut` BESIDE the live file
and deleted it afterwards, which is better than an in-place write and still wrong in
two measurable ways, both recorded here rather than argued:

  * a file BESIDE a live source is INSIDE ITS IMPORT CLOSURE and inside every
    `find tinybendygrad -name '*.bend*'` census.  `memory.bend.mut` does not end in
    `.bend`, so a `*.bend` glob misses it -- but it is a full copy of a source file
    sitting in `runtime/support/`, and any census or reader that globs `*.bend*` or
    iterates the directory finds a Bend file it cannot account for.  This harness's
    staged copy is named `memory.staged-mem-<pid>`: BESIDE the file, so
    `import ./../../helpers.bend` still resolves (a `$TMPDIR` copy cannot, and that
    produced 22 phantom blind spots in one unit), and with NO extension, so neither
    glob can see it.  That is the property `staged_mut` exists to hold, and holding
    it is the whole difference between this file and the one it replaces.

  * it had NO DIGEST GUARD AT ALL.  It mutated, wrote `.mut`, ran bend on `.mut`, and
    deleted `.mut` -- with no statement anywhere about whether the live `memory.bend`
    was the file it started from, and therefore no way to notice if a concurrent
    agent's edit arrived mid-run.  `staged_mut.Staged` asserts
    `sha256(jj @) == sha256(live)` at stage time and REPORTS a live digest that moves
    during the run instead of writing over it.

THE OTHER BUG THIS HARNESS HAD, kept because it was the more expensive one: it read
bend's `bend 2.0.35 is available: run bend update` notice on STDERR as a BASELINE
FAILURE and exited 2 before measuring anything, losing all 70 mutations -- and exit 2
is indistinguishable from "did not compile".  `staged_mut.run()` is STDOUT-ONLY by
contract, so that liveness test cannot be permanently true, and `try_rows()` re-runs
the machine-stack-overflow that bend hits about 1 run in 20 rather than reporting it
as a zero.

THE ANCHORS below are this harness's own declaration and are spliced in VERBATIM from
the pre-conversion file by a script rather than retyped.  What is re-derived is the
MEASUREMENT: the row set, the moved rows, the anchor occurrence count, and the
control.  An anchor that reads `0 occurrences` prints `PATCH-NOT-APPLY` and NO row
count at all, because a count there is a count of rows the edit never touched.

THE CONTROL IS THE SAME MIRROR WITH NO EDIT, RUN TWICE, compared on the ROW COUNT and
on a digest over the ROW SET.  A count is equal when one row is lost and another is
gained, and a baseline can BE the mutant -- frozen digests cover the file being
mutated, never the file `SAME` is measured against.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import staged_mut as S                                        # noqa: E402

LIVE = S.ROOT / "tinybendygrad" / "runtime" / "support" / "memory.bend"

# (id, description, the exact text to find, the replacement)
MUTS = [
 ("M01", "calcsizes: '?' given 4 instead of 1",
  'csz_of(1, "?")', 'csz_of(4, "?")'),
 ("M02", "calcsizes: 'I2B' given 8 instead of 6",
  'csz_of(6, "I2B")', 'csz_of(8, "I2B")'),
 ("M03", "calcsizes: 3I given 12 -> 16",
  'csz_of(12, "3I")', 'csz_of(16, "3I")'),
 ("M04", "calcsizes: 12I given 48 -> 32",
  'csz_of(48, "12I")', 'csz_of(32, "12I")'),
 ("M05", "calcsizes: the 2I entry removed from the middle (position swap)",
  'csz_of(8, "2I"), csz_of(4, "4B")', 'csz_of(4, "4B"), csz_of(8, "2I")'),

 ("M06", "AddrSpace: SYS index 1 -> 2",
  'def ASPACE_SYS_IX() -> U32: 1', 'def ASPACE_SYS_IX() -> U32: 2'),
 ("M07", "AddrSpace: PHYS value 1 -> 0",
  'def ASPACE_PHYS_VAL() -> U32: 1', 'def ASPACE_PHYS_VAL() -> U32: 0'),
 ("M08", "AddrSpace: the value column replaced by the index column",
  '[space_of(0, 1, "PHYS"), space_of(1, 2, "SYS"), space_of(2, 3, "PEER")]',
  '[space_of(0, 0, "PHYS"), space_of(1, 1, "SYS"), space_of(2, 2, "PEER")]'),

 ("M09", "MMIO: the field order mv,addr,nbytes,fmt -> addr,nbytes,mv,fmt",
  'type Mv is Data:\n  Mv{h: U32, addr: U32, nbytes: U32, fmt: U32}',
  'type Mv is Data:\n  Mv{addr: U32, nbytes: U32, h: U32, fmt: U32}'),
 ("M10", "Bump: the field order size,ptr,base,wrap -> size,base,ptr,wrap",
  'Bump{size, ptr, base, wrap}', 'Bump{size, base, ptr, wrap}'),
 ("M11", "TLSF blocks 4-tuple row: the comment names the fields, reordered",
  'srow("tlsf_blocks_comment", "size next prev is_free")', 'srow("tlsf_blocks_comment", "size prev next is_free")'),
 ("M12", "Pa pair order: paddr,psize -> psize,paddr",
  'type Pa is Data:\n  Pa{paddr: U32, psize: U32}',
  'type Pa is Data:\n  Pa{psize: U32, paddr: U32}'),
 ("M13", "Vmap field order: va_addr,size,paddrs,aspace,uncached,snooped -> size,va_addr,...",
  'type Vmap is Data:\n  Vmap{va_addr: U32, size: U32, paddrs: List<&2, Pa>, aspace: U32, uncached: Bool, snooped: Bool}',
  'type Vmap is Data:\n  Vmap{size: U32, va_addr: U32, paddrs: List<&2, Pa>, aspace: U32, uncached: Bool, snooped: Bool}'),

 ("M14", "bump_overflow: the ROUND is dropped from the overflow test",
  'U32.is_gt(U32.add(bump_round(Bump.ptr(b), align), size), Bump.size(b))',
  'U32.is_gt(U32.add(Bump.ptr(b), size), Bump.size(b))'),
 ("M15", "bump_round: round_up's -1 dropped",
  'U32.mul(U32.div(U32.add(a, U32.sub(q, 1)), q), q)',
  'U32.mul(U32.div(a, q), q)'),
 ("M16", "bump_take: ptr set to res instead of res+size",
  'BumpR{bump_at(b, bump_end(bump_res(b, align), size)), False{}, bump_res(b, align)}',
  'BumpR{bump_at(b, bump_res(b, align)), False{}, bump_res(b, align)}'),
 ("M17", "bump_addr_of: the address is ptr+base instead of res+base",
  'def bump_addr_of(+r: BumpR, b: Bump) -> U32: bump_addr(Bump.base(b), BumpR.res(r))',
  'def bump_addr_of(+r: BumpR, b: Bump) -> U32: bump_addr(Bump.base(b), Bump.ptr(BumpR.b(r)))'),
 ("M18", "bump_over: the wrap arm refuses unconditionally",
  'match wrap:\n    case True{}: bump_wrapped(b, size, align)\n    case False{}: BumpR{b, True{}, 0}',
  'match wrap:\n    case True{}: BumpR{b, True{}, 0}\n    case False{}: BumpR{b, True{}, 0}'),
 ("M19", "bump_wrap_ptr: reset to the ALIGNED value instead of 0",
  'def bump_wrap_ptr() -> U32: 0', 'def bump_wrap_ptr() -> U32: 16'),

 ("M20", "mmio_view: the `size is None` arm answers 0 instead of nbytes-off",
  'case None{}: U32.sub(Mv.nbytes(root), off)', 'case None{}: 0'),
 ("M21", "mmio_view: the address does not accumulate",
  'def mmio_view_off(root: Mv, off: U32) -> U32: U32.add(Mv.addr(root), off)',
  'def mmio_view_off(root: Mv, off: U32) -> U32: U32.add(off, off)'),
 ("M22", "mmio_view: `fmt or self.fmt` always takes the parent's fmt",
  'case Some{+f}: f', 'case Some{+f}: Mv.fmt(root)'),
 ("M23", "mmio_len: divide by 1 always (fmt ignored)",
  'def mmio_len(+m: Mv) -> U32: U32.div(Mv.nbytes(m), calcsize_i(Mv.fmt(m)))',
  'def mmio_len(+m: Mv) -> U32: U32.div(Mv.nbytes(m), 1)'),
 ("M24", "mmio_def_fmt: the default fmt is 'H' instead of 'B'",
  'def mmio_def_fmt() -> U32: fmt_ix_name("B")', 'def mmio_def_fmt() -> U32: fmt_ix_name("H")'),
 ("M25", "fmt_of_size: the reverse lookup answers the LAST match, not the first",
  'def cfmt_sz.go(+cs: List<&2, Csz>, +want: U32, +at: U32, acc: Nat) -> Nat:\n'
  '  match cs:\n    case Nil{}: acc\n    case c <> t: cfmt_sz.go(t, want, U32.add(at, 1), cfmt_sz.step(acc, at, want, c))',
  'def cfmt_sz.go(+cs: List<&2, Csz>, +want: U32, +at: U32, acc: Nat) -> Nat:\n'
  '  match cs:\n    case Nil{}: acc\n    case c <> t: cfmt_sz.go(t, want, U32.add(at, 1), Bool.pick(Nat, U32.is_eq(Csz.sz(c), want), Nat.add(1n, U32.to_nat(at)), acc))'),

 # RE-AIMED 2026-10-04.  `frag_lowbit` gained a `+` binder; same edit, same site.
 ("M26", "frag_lowbit: x - 2x instead of x & (~x + 1)",
  'def frag_lowbit(+x: U32) -> U32: U32.and(x, U32.add(U32.not(x), 1))',
  'def frag_lowbit(+x: U32) -> U32: U32.sub(x, U32.add(x, x))'),
 ("M27", "frag_va_div: no `va > 0` sentinel (raw lowbit for va == 0)",
  'def frag_va_div(+va: U32) -> U32: Bool.pick(U32, U32.is_gt(va, 0), frag_lowbit(va), LOWBIT_ZERO())',
  'def frag_va_div(+va: U32) -> U32: frag_lowbit(va)'),
 ("M28", "frag_sz_max: 1 << bl instead of 1 << (bl - 1)",
  'def frag_sz_max(sz: U32) -> U32: shl1(U32.sub(bitlen1(sz), 1))',
  'def frag_sz_max(sz: U32) -> U32: shl1(bitlen1(sz))'),
 ("M29", "frag_min: must_cover ignored (the other arm always)",
  'Bool.pick(U32, must_cover, u32_min(frag_va_div(va), frag_sz_div(sz)),\n            u32_min(frag_va_div(va), frag_sz_max(sz)))',
  'Bool.pick(U32, must_cover, u32_min(frag_va_div(va), frag_sz_max(sz)),\n            u32_min(frag_va_div(va), frag_sz_max(sz)))'),
 ("M30", "frag_of: the -1 -12 becomes -0 -12",
  'U32.sub(bitlen1(frag_min(va, sz, must_cover)), U32.add(1, FRAG_UNIT_SHIFT()))',
  'U32.sub(bitlen1(frag_min(va, sz, must_cover)), FRAG_UNIT_SHIFT())'),
 ("M31", "FRAG_UNIT_SHIFT 12 -> 13",
  'def FRAG_UNIT_SHIFT() -> U32: 12', 'def FRAG_UNIT_SHIFT() -> U32: 13'),
 ("M32", "LOWBIT_ZERO 2^31 -> 2^30 (still outside the lowbit range?)",
  'def LOWBIT_ZERO() -> U32: 2147483648', 'def LOWBIT_ZERO() -> U32: 1073741824'),

 ("M33", "pte_covers: the [::-1] is dropped (covers_of == covers_raw)",
  'def covers_of(shifts: List<&2, U32>) -> List<&2, U32>: rev.u32(covers_raw(shifts))',
  'def covers_of(shifts: List<&2, U32>) -> List<&2, U32>: covers_raw(shifts)'),
 ("M34", "pte_covers: the reversal is applied TWICE",
  'def covers_of(shifts: List<&2, U32>) -> List<&2, U32>: rev.u32(covers_raw(shifts))',
  'def covers_of(shifts: List<&2, U32>) -> List<&2, U32>: rev.u32(rev.u32(covers_raw(shifts)))'),
 ("M35", "pte_cnt: the [::-1] is dropped",
  '  rev.u32(cnts_raw(lvl_msb(shifts, va_bits)))', '  cnts_raw(lvl_msb(shifts, va_bits))'),
 ("M36", "lvl_msb: the extra is va_bits, not va_bits + 1",
  'def lvl_msb_last(shifts: List<&2, U32>, va_bits: U32) -> U32: U32.add(va_bits, 1)',
  'def lvl_msb_last(shifts: List<&2, U32>, va_bits: U32) -> U32: va_bits'),
 ("M37", "cnts_raw: the list is not shortened (the head's difference is included)",
  '    case x <> t: cnts_raw.go(t, Nil{}, x)',
  '    case x <> t: cnts_raw.go(t, Nil{}, 0)'),
 ("M38", "pte_ladder: the invariant is dropped (always true)",
  'Bool.pick(Bool, Bool.and(Bool.and(has_sz(c), has_sz(n)), has_sz(u)),\n    U32.is_eq(U32.mul(c, n), u), False{})',
  'Bool.pick(Bool, Bool.and(Bool.and(has_sz(c), has_sz(n)), has_sz(u)),\n    True{}, False{})'),
 ("M39", "shl1: 1 << x becomes x",
  'def shl1(x: U32) -> U32: U32.shln(1, U32.to_nat(x))', 'def shl1(x: U32) -> U32: x'),

 ("M40", "mm_ptable_sz: the `if reserve else 0` arm is dropped",
  'Bool.pick(U32, reserve, bump_round(U32.div(vram, 512), 1048576), 0)',
  'bump_round(U32.div(vram, 512), 1048576)'),
 ("M41", "mm_off_sz: the ptable window is not added",
  'U32.add(boot, mm_ptable_sz(vram, reserve))', 'boot'),
 ("M42", "mm_pa_sz: the size is the whole vram, not what is left",
  'U32.sub(vram, mm_off_sz(boot, vram, reserve))', 'vram'),
 ("M43", "mm_ptable_sz: the //512 divisor is 256",
  'U32.div(vram, 512)', 'U32.div(vram, 256)'),
 ("M44", "mm_ptable_sz: the round unit is 1<<19 not 1<<20",
  'bump_round(U32.div(vram, 512), 1048576)', 'bump_round(U32.div(vram, 512), 524288)'),

 ("M45", "alloc_vaddr: max() becomes min()",
  'def valloc_align(+sz: U32) -> U32: u32_max(PAGE_4K(), next_pow2(sz))',
  'def valloc_align(+sz: U32) -> U32: u32_min(PAGE_4K(), next_pow2(sz))'),
 ("M46", "VA_ALLOC_BASE hi 8192 -> 4096",
  'def VA_ALLOC_BASE() -> H.I64: H.i64_of_hi_lo(8192, 0)',
  'def VA_ALLOC_BASE() -> H.I64: H.i64_of_hi_lo(4096, 0)'),
 ("M47", "VA_ALLOC_SIZE hi 4096 -> 256",
  'def VA_ALLOC_SIZE() -> H.I64: H.i64_of_hi_lo(4096, 0)',
  'def VA_ALLOC_SIZE() -> H.I64: H.i64_of_hi_lo(256, 0)'),

 ("M48", "tlsf lv1: size.bit_length() -> size.bit_length()-1",
  'urow(String.concat(["tlsf_lv1_", U32.show(sz)]), bitlen1(sz))',
  'urow(String.concat(["tlsf_lv1_", U32.show(sz)]), U32.sub(bitlen1(sz), 1))'),
 ("M49", "tlsf lv2: the `max(0, ..)` clamp is dropped",
  'def lv2_shift(sz: U32) -> U32: u32_sub0(bitlen1(sz), bitlen1(TLSF_DEF_LV2_CNT()))',
  'def lv2_shift(sz: U32) -> U32: U32.sub(bitlen1(sz), bitlen1(TLSF_DEF_LV2_CNT()))'),
 ("M50", "tlsf alloc: step 2's align-1 is dropped",
  'u32_max(TLSF_DEF_BLOCK(), U32.add(req, U32.sub(al, 1)))', 'u32_max(TLSF_DEF_BLOCK(), req)'),
 ("M51", "tlsf alloc: the final bucket rounding is dropped",
  'def tlsf_round(+sz: U32) -> U32: bump_round(sz, shl1(u32_sub0(bitlen1(sz), bitlen1(TLSF_DEF_LV2_CNT()))))',
  'def tlsf_round(+sz: U32) -> U32: sz'),
 ("M52", "tlsf l2_cnt: 16.bit_length() -> 4",
  'bitlen1(TLSF_DEF_LV2_CNT())', '4'),
 ("M53", "tlsf storage len: +1 dropped",
  'urow("tlsf_storage_len_1048576", U32.add(bitlen1(1048576), 1))',
  'urow("tlsf_storage_len_1048576", bitlen1(1048576))'),

 ("M54", "valloc ladder: the skip-if-bigger comparison is >= instead of >",
  'Bool.pick(U32, U32.is_le(s, rem), s, ladder_pick.go(t, rem, dflt))',
  'Bool.pick(U32, U32.is_lt(s, rem), s, ladder_pick.go(t, rem, dflt))'),
 ("M55", "valloc ladder: LAST match instead of FIRST",
  'case s <> t: Bool.pick(U32, U32.is_le(s, rem), s, ladder_pick.go(t, rem, dflt))',
  'case s <> t: Bool.pick(U32, U32.is_le(s, rem), ladder_pick.go(t, rem, s), s)'),
 # RE-AIMED 2026-10-04.  The ladder call's second argument was renamed `t` -> `ss`.
 ("M56", "valloc ladder: the remainder is not decremented",
  'valloc_picks.fuel(p, U32.sub(rem, ladder_pick(rem, ss)), stop_sizes(rem, ss), append_sz(rem, ss, acc))',
  'valloc_picks.fuel(p, rem, stop_sizes(rem, ss), append_sz(rem, ss, acc))'),

 ("M57", "vm_psize_sum: reads p[0] instead of p[1] (the :211 vs :279 pair swap)",
  'case p <> t: psum.go(t, U32.add(acc, Pa.psize(p)))',
  'case p <> t: psum.go(t, U32.add(acc, Pa.paddr(p)))'),
 ("M58", "vm_free_paddrs: reads p[1] instead of p[0]",
  'case p <> t: pcol.go(t, List.append(&2, U32, acc, [Pa.paddr(p)]))',
  'case p <> t: pcol.go(t, List.append(&2, U32, acc, [Pa.psize(p)]))'),
 ("M59", "vmap_gmmu0: snooped supplied as uncached",
  'vmap_all(va, size, [Pa{paddr, size}], ASPACE_PHYS_IX(), uncached, False{})',
  'vmap_all(va, size, [Pa{paddr, size}], ASPACE_PHYS_IX(), uncached, uncached)'),
 ("M60", "vmap_gmmu0: aspace is SYS, not PHYS",
  'vmap_all(va, size, [Pa{paddr, size}], ASPACE_PHYS_IX(), uncached, False{})',
  'vmap_all(va, size, [Pa{paddr, size}], ASPACE_SYS_IX(), uncached, False{})'),

 ("M61", "first_of: the `seen` flag is dropped (the LAST element)",
  'case x <> t: first_of.take(t, True{}, first_of.keep(seen, acc, x))',
  'case x <> t: first_of.take(t, True{}, List.append(&2, U32, acc, [x]))'),
 ("M62", "pte_first_largest: `first == max` becomes `first >= min`",
  'def pte_first_largest_of(+xs: List<&2, U32>) -> Bool: U32.is_eq(first_of(xs), pte_max_all(xs, fmt_absent()))',
  'def pte_first_largest_of(+xs: List<&2, U32>) -> Bool: U32.is_le(first_of(xs), pte_max_all(xs, fmt_absent()))'),
 ("M63", "MMIO_INDEX tag 3 -> 2 (collides with TO_MV_CAST)",
  'def MMIO_INDEX() -> U32: 3', 'def MMIO_INDEX() -> U32: 2'),
 ("M64", "PT_SET_ENTRY tag 9 -> 8 (collides with PT_SUPPORTS_HUGE)",
  'def PT_SET_ENTRY() -> U32: 9', 'def PT_SET_ENTRY() -> U32: 8'),
 ("M65", "PAGE_4K 4096 -> 8192",
  'def PAGE_4K() -> U32: 4096', 'def PAGE_4K() -> U32: 8192'),
 ("M66", "TLSF_DEF_BLOCK 16 -> 32",
  'def TLSF_DEF_BLOCK() -> U32: 16', 'def TLSF_DEF_BLOCK() -> U32: 32'),
 ("M67", "lvl_msb_len: the +1 is dropped",
  'def lvl_msb_len(shifts: List<&2, U32>) -> U32: U32.add(level_cnt(shifts), 1)',
  'def lvl_msb_len(shifts: List<&2, U32>) -> U32: level_cnt(shifts)'),
 ("M68", "odd_not_mult: the modulo test becomes equality-to-1",
  'def odd_not_mult(nb: U32, isz: U32) -> Bool: Bool.not(U32.is_eq(U32.mod(nb, isz), 0))',
  'def odd_not_mult(nb: U32, isz: U32) -> Bool: U32.is_eq(U32.mod(nb, isz), 1)'),
 # M64 RETAGS `PT_SET_ENTRY` ONTO `PT_SUPPORTS_HUGE`, WHICH NOTHING EMITS, and a
 # tag collision with an UNUSED tag is invisible: both lanes count the same
 # number of calls under the shared value. This one retags onto `PT_VALID`, which
 # IS emitted, so it moves -- and the pair is what shows the difference between
 # "the tag space is wrong" and "the tag is wrong".
 ("M69", "PT_SET_ENTRY tag 9 -> 4 (collides with PT_VALID, WHICH IS EMITTED)",
  'def PT_SET_ENTRY() -> U32: 9', 'def PT_SET_ENTRY() -> U32: 4'),
 # THE `:260-262` LADDER WALK. A LAST-match walk keeps the SMALLEST segment at
 # or below the remainder instead of the largest, which is the same class of bug
 # as advancing the list past the pick -- the one this port HAD, and which the
 # CPython diff caught as eight 2 MiB picks for an 8 MiB request.
 ("M70", "ladder_pick: the FIRST match at or below the remainder becomes the LAST",
  'case s <> t: Bool.pick(U32, U32.is_le(s, rem), s, ladder_pick.go(t, rem, dflt))',
  'case s <> t: Bool.pick(U32, U32.is_le(s, rem), ladder_pick.go(t, rem, s), dflt)'),
]
# A ZERO MAY NOT BE CLOSED WITH A ROW THAT ENCODES THE BUG, and it may not be closed
# with an unexplained adjective either.  Every zero this table has, with the evidence
# for it, re-derived on 2026-10-04 rather than inherited from the table's own comments.
#
# `note` is printed with the zero either way.  `theorem` decides the CLASS and it is
# True only where a refutation of "unreachable" is IMPOSSIBLE rather than merely
# unobserved -- i.e. where two spellings of the port are the same function, or where
# the value the mutation collides with is one no def emits.  Everything else is
# PORT-DEFECT, which agent-core.md calls a REQUEST FOR A FIXTURE and NOT a theorem:
# inventing a theorem for an unexplained zero is the one move that turns this table
# into a liar.  Both PORT-DEFECT entries below carry the SEPARATING FIXTURE, measured.
ZERO_NOTES = {
    "M09": ("the LABELLED `type Mv is Data` field order is not observable: every read of "
            "Mv is an UNLABELLED positional pattern `case Mv{h, addr, nbytes, fmt}`, and a "
            "probe reading all four accessors off `Mv{7, 11, 13, 17}` returns 7 11 13 17 "
            "before AND after the mutation.  Two spellings of one type.", True),
    "M12": ("same measurement for `type Pa is Data`: `Pa.paddr`/`Pa.psize` return 7 and 11 "
            "off `Pa{7, 11}` both before and after.  Two spellings of one type.", True),
    "M13": ("same measurement for `type Vmap is Data`: the accessors return the values the "
            "positional pattern binds, before and after.  Two spellings of one type.", True),
    "M38": ("SEPARATING FIXTURE EXISTS, so this is a fixture gap and not a theorem: "
            "`ladder_hit.go(3, 3, 10)` has c*n = 9 != 10, and the measured row goes "
            "0 -> 1 under M38.  A `Lad` that `lad_of` builds from a real covers/cnts pair "
            "cannot be inconsistent, so only a DIRECT call separates it.", False),
    "M62": ("SEPARATING FIXTURE EXISTS, so this is a fixture gap and not a theorem: "
            "`pte_first_largest_of(covers_of([9, 7, 4]))` measured 0 and becomes 1 under "
            "M62, i.e. for that va_shifts the port's own `first_of(covers)` is NOT "
            "`max(covers)`.  A sweep of 14 va_shifts vectors gives 4 True and 10 False, so "
            "the existing `pte_first_largest_*` fixtures are all in the True minority.  "
            "THIS ALSO CONTRADICTS THE WALL AT memory.bend:1728, which asserts that "
            "`pte_first_largest` is a theorem for every va_shifts CPython accepts; it is "
            "not, and `pte_first_largest_of` is CALLED (memory.bend:1593 -> :1616) so it "
            "is reachable, not dead.  Reported, not fixed: the file is read-only here.",
            False),
    "M64": ("retagging `PT_SET_ENTRY` 9 -> 8 collides with `PT_SUPPORTS_HUGE`, and "
            "`PT_SUPPORTS_HUGE()` has ZERO call sites (measured: one mention, the def at "
            "memory.bend:197, no `PT_SUPPORTS_HUGE()` anywhere else), so no def emits the "
            "value 8 and every row that counts calls under a shared tag value counts the "
            "same.  The pair with M69, which retags onto `PT_VALID` and DOES move, is what "
            "separates 'the tag space is wrong' from 'the tag is wrong'.", True),
}

# An anchor that occurs MORE THAN ONCE is refused, and the old harness's behaviour on
# these two is the reason the refusal exists rather than a stylistic choice.  It did
# `src.replace(find, repl)` with NO count, so it rewrote every site and reported the
# result under a description naming ONE of them.
AMBIGUOUS = {
    "M10": "the anchor `Bump{size, ptr, base, wrap}` occurs 5x and NONE of the 5 is the "
           "`type Bump is Data` declaration, which is LABELLED "
           "(`Bump{size: U32, ptr: U32, base: U32, wrap: Bool}`).  The 5 sites are the "
           "four accessors' patterns (:488 size, :491 ptr, :494 base, :497 wrap) and "
           "`bump_at`'s constructor (:504).  Measured: rewriting all 5 swaps TWO POSITIONAL "
           "BINDERS -- `Bump.base` returns 11 where it returned 13 and `Bump.ptr` 13 where "
           "it returned 11 -- and moves 13 rows.  So the old number was a 13-row move for "
           "an edit that is NOT the field-order mutation its description names.  Re-aim at "
           "the labelled declaration, or at one accessor pattern.",
    "M52": "the anchor `bitlen1(TLSF_DEF_LV2_CNT())` occurs 5x (:2124 lv2_shift, :2131 "
           "t_tlsf1, :2135 tlsf_bucket, :2150 a def, :2225 tlsf_req), so replacing all of "
           "them is five edits and the description names one.  Re-aim.",
}

# The verdict vocabulary is SPELLED THROUGH the two modules that own it rather than
# invented here, and looked up BY NAME.  `zero-classify.py` prints
# `UNREACHABLE+proof` and `INVISIBLE-to-reader`, so the query returns five strings that
# are NOT the five names this table uses; slicing that list by position -- which is
# exactly what this footer did on its first attempt -- reads `PATCH-NOT-APPLY` when it
# asks for `INVISIBLE`.  `zero_verdict_map()` refuses a key that does not match exactly
# one queried verdict, so the vocabulary cannot drift silently underneath the table.
MOVED = "MOVED"
V = S.zero_verdict_map()
UNREACHABLE, PORT_DEFECT, INVISIBLE = V["UNREACHABLE"], V["PORT-DEFECT"], V["INVISIBLE"]
DID_NOT_COMPILE = __import__("patch_not_apply").NOT_A_PROGRAM
NO_MUTATION = V["NO-MUTATION-WRITTEN"]
PATCH_NOT_APPLY = __import__("patch_not_apply").MARKER


def classify(mid, moved, compiled):
    """One verdict, from the measurement only.

    `compiled` is what separates a zero from a non-program, and conflating the two is
    how three mutations that never compiled were published as "49 rows moved" each: a
    harness that counts lines counts bend's `1007>|` parse-error ROWS on stderr.  A
    `DID-NOT-COMPILE` NEVER contributes a row count, and `moved` is `[]` for it
    because `try_rows()` returns None rather than an empty dict.
    """
    if moved:
        return MOVED, ""
    if not compiled:
        return DID_NOT_COMPILE, "the mutant is not a program"
    note, theorem = ZERO_NOTES.get(mid, ("no entry in ZERO_NOTES: an unexplained zero "
                                         "is still a zero", False))
    return (UNREACHABLE if theorem else PORT_DEFECT), note


def cell(v, n=58):
    """A VALUE clipped for a human.  A 4,000-character `valloc_picks_*` row buries the
    five rows after it, and a table nobody can read past line three is a table whose
    later rows go unread -- which is how a DID-NOT-COMPILE at the bottom of a screen
    goes unnoticed.  The clip is applied to the PRINT only; `moved` and the report
    carry whole lines."""
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n] + " ...[%d]" % len(s)


def main():
    # `--report FILE` takes a VALUE, and a value does not start with `--`.  Collecting
    # selectors as "everything that is not a flag" therefore put the filename in the
    # set, every mutation id missed it, and the harness printed `0 mutations:` -- which
    # is the one output indistinguishable from "did not start".  It did exactly that on
    # its first run here.  An option's ARGUMENT is removed with the option, by index.
    argv = list(sys.argv[1:])
    report = None
    if "--report" in argv:
        i = argv.index("--report")
        report, argv = pathlib.Path(argv[i + 1]), argv[:i] + argv[i + 2:]
    only = set(argv)

    table, tally = [], {}
    with S.Staged(LIVE, "mem") as g:
        g.write(g.origin())
        c1 = g.rows()
        g.write(g.origin())
        c2 = g.rows()
        S.control(c1, c2, "memory.bend unedited staged mirror, two runs")
        base = c1
        print("CONTROL SAME: %d rows, row-set digest %s, both runs"
              % (len(base), S.row_digest(base)[:16]))

        for mid, desc, find, repl in MUTS:
            if only and mid not in only:
                continue
            occ = g.occurrences(find)
            if occ != 1:
                note = ("anchor occurs %dx in the asserted-equal substrate (need exactly 1)"
                        % occ) + (("  " + AMBIGUOUS[mid]) if mid in AMBIGUOUS else "")
                print("%s %s  %-56s %s" % (mid, PATCH_NOT_APPLY, desc, note))
                table.append((mid, desc, NO_MUTATION, [], note))
                tally[NO_MUTATION] = tally.get(NO_MUTATION, 0) + 1
                continue
            g.write(g.origin().replace(find, repl, 1))
            if g.text() == g.origin():
                note = "replacement is byte-identical to the anchor"
                print("%s %s  %s" % (mid, NO_MUTATION, desc))
                table.append((mid, desc, NO_MUTATION, [], note))
                tally[NO_MUTATION] = tally.get(NO_MUTATION, 0) + 1
                continue
            got = g.try_rows()
            g.write(g.origin())                   # restore from pristine, not from disk
            moved = [] if got is None else \
                sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
            verdict, why = classify(mid, moved, got is not None)
            tally[verdict] = tally.get(verdict, 0) + 1
            table.append((mid, desc, verdict, moved, why))
            print("%s %-18s rows_moved=%-4d %s" % (mid, verdict, len(moved), desc))
            for k in moved[:6]:
                print("      %-30s %s -> %s" % (k, cell(base.get(k)), cell(got.get(k))))
            if len(moved) > 6:
                print("      ... and %d more" % (len(moved) - 6))
            if why:
                print("      reason offered: %s" % why)
        print()
        print("SUBSTRATE  live=%s staged=%s  (%d rows)"
              % (g.live_sha[:16], g.mirror_sha[:16], len(base)))

    print()
    # `0` IS INDISTINGUISHABLE FROM "did not start", so it is refused rather than
    # printed.  A table with no rows means the selectors matched nothing, and a
    # harness that reports that as a result is reporting its own argument parsing.
    if not table:
        raise SystemExit("NO MUTATIONS RAN.  selectors=%r matched none of the %d ids in "
                         "MUTS.  No table is written -- a 0 here means the run never "
                         "began." % (sorted(only), len(MUTS)))
    print("%d mutations: %s" % (len(table), ", ".join("%s=%d" % kv for kv in sorted(tally.items()))))
    for v in (UNREACHABLE, PORT_DEFECT, INVISIBLE, DID_NOT_COMPILE, NO_MUTATION):
        for mid, desc, verdict, _, why in table:
            if verdict == v:
                print("  %-18s %s  %s%s" % (v, mid, desc, ("  -- " + why) if why else ""))
    if report:
        report.write_text("\n".join(
            ["memory-mutate -- STAGED, the live tree is never written",
             "substrate tinybendygrad/runtime/support/memory.bend",
             "sha256(mirror)==sha256(live) asserted with jj --ignore-working-copy",
             "reader rebase-gate.rows() over the WHOLE row set, keyed on NAME",
             "control SAME on %d rows, row-set digest %s" % (len(base), S.row_digest(base)[:16]),
             "MUT    VERDICT            ROWS_MOVED  DESCRIPTION"] +
            ["%-6s %-18s %-11d %s" % (m, v, len(mv), d) for m, d, v, mv, _ in table]) + "\n")
        print("wrote %s" % report)
    return 0


if __name__ == "__main__":
    sys.exit(main())