#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/runtime/support/memory.bend.

ONE ENTRY PER PORTED RULE. Each mutation is a whole-line `name=value` edit to a
COPY of the .bend file, and the report is WHICH ROWS MOVED BY NAME -- not
whether the harness saw anything, because a name-comparing harness has reported
0 for all 30 mutations in one unit of this project and all 68 in another.

The comparison is `difflib` over the FULL `name=value` lines. A mutation that
moves nothing is reported as a BLIND SPOT with a reason, never closed with a row
that encodes the bug.

    .agents/slop/memory-mutate.py [name ...]
"""
import subprocess, sys, os, re, shutil, difflib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BEND = os.path.join(ROOT, 'tinybendygrad/runtime/support/memory.bend')
WORK = os.path.join(ROOT, '.agents/slop/.mutwork')
NATIVE = os.path.join(WORK, 'mem')

# (id, description, the exact text to find, the replacement, expected-nonempty)
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

 ("M26", "frag_lowbit: x - 2x instead of x & (~x + 1)",
  'def frag_lowbit(x: U32) -> U32: U32.and(x, U32.add(U32.not(x), 1))',
  'def frag_lowbit(x: U32) -> U32: U32.sub(x, U32.add(x, x))'),
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
 ("M56", "valloc ladder: the remainder is not decremented",
  'valloc_picks.fuel(p, U32.sub(rem, ladder_pick(rem, t)), stop_sizes(rem, ss), append_sz(rem, ss, acc))',
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

def run(path):
    p = subprocess.run(['./bin/bend', path], cwd=ROOT, capture_output=True, text=True)
    return p.stdout, p.returncode, p.stderr

def rows_of(txt):
    out = []
    for l in txt.split('\n'):
        l = l.rstrip()
        if l and '=' in l: out.append(l)
    return out

def main():
    only = set(sys.argv[1:])
    os.makedirs(WORK, exist_ok=True)
    base_txt, _, base_err = run(BEND)
    if base_err.strip():
        print("BASELINE FAILED:\n" + base_err, file=sys.stderr); sys.exit(2)
    base = rows_of(base_txt)
    print(f'baseline rows: {len(base)}')

    results = []
    for mid, desc, find, repl in MUTS:
        if only and mid not in only: continue
        src = open(BEND).read()
        n = src.count(find)
        if find == 'KEEP' or n == 0:
            results.append((mid, desc, 'SKIP', [], f'pattern not found ({n})')); continue
        shutil.copy(BEND, BEND + '.mut')
        open(BEND + '.mut', 'w').write(src.replace(find, repl))
        txt, rc, err = run(BEND + '.mut')
        moved = []
        if rc == 0 and not err.strip():
            new = rows_of(txt)
            bm = {l.split('=', 1)[0]: l for l in base}
            nm = {l.split('=', 1)[0]: l for l in new}
            moved = sorted(k for k in set(bm) | set(nm)
                           if bm.get(k) != nm.get(k))
        os.remove(BEND + '.mut')
        results.append((mid, desc, 'OK' if (moved or rc != 0) else 'ZERO', moved, ''))

    print()
    zeros = []
    for mid, desc, st, moved, why in results:
        if st == 'ZERO': zeros.append((mid, desc))
        nmv = len(moved)
        sample = ', '.join(moved[:6]) + (' ...' if nmv > 6 else '')
        print(f'{mid} {st:5} rows_moved={nmv:4}  {desc}')
        if nmv: print(f'      {sample}')
        if why: print(f'      {why}')
    print(f'\n{len(results)} mutations, {len(zeros)} moved nothing')
    for mid, desc in zeros: print(f'  BLIND SPOT {mid}: {desc}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
