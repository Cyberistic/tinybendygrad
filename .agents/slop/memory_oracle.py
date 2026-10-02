#!/usr/bin/env python
"""Oracle for tinybendygrad/runtime/support/memory.bend.

EVERY `py=` expectation is produced by CALLING CPython here. Nothing is typed.
Each row is printed as `name=value` with NO trailing space, so a byte-diff of
this file's output against the Bend lane's output is the gate.

Run from the repo root:
    .venv/bin/python .agents/slop/memory_oracle.py > .agents/slop/memory_oracle.txt
"""
import sys, os, dataclasses, struct, collections
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from tinygrad.runtime.support import memory as M
from tinygrad.helpers import round_up

rows = []
def row(nm, v): rows.append(f"{nm}={v}")

# ===========================================================================
# THE FIXTURES. Every number here is chosen to make a claim SEPARABLE, and the
# choices are recorded next to the rows they serve.
# ===========================================================================

# MMIO: (name, addr, nbytes, fmt).
#
# MEASURED CONSTRAINT: `to_mv(addr, nbytes).cast(fmt)` REFUSES a multi-character
# format -- `memoryview: destination format must be a native single character
# format`. So `MMIOInterface` only ever holds a SINGLE-CHARACTER fmt, and the
# multi-char entries in the `calcsize` table below are reachable only through
# `struct.calcsize` itself, never through `MMIOInterface`. That is why `fmt` is a
# `U32` INDEX in this port and why the table is wider than the fixtures: the
# table is `struct`'s, the fixtures are `MMIOInterface`'s, and
# `mem_mmio_multichar_refused_*` is the row that keeps the two apart.
# AND a second measured constraint: `nbytes` must be a multiple of the item
# size, or `.cast(fmt)` raises `TypeError: length is not a multiple of
# itemsize`. So `__len__` is not merely `nbytes // calcsize(fmt)` -- the FLOOR
# never happens, because construction refuses first. `mem_mmio_odd_refused_*`
# is that row and `mmio_oddi_*` below is the ONE odd fixture, on 'B' only.
MMIO = [
  ("b",      0x90000000, 0x1000, "B"),
  ("h",      0x90000000, 0x1000, "H"),
  ("i",      0x90000000, 0x1000, "I"),
  ("q",      0x90000000, 0x1000, "Q"),
  ("d",      0x90000000, 0x1000, "d"),
  ("b1",     0x90000000, 0x1000, "b"),
  ("h2",     0x90000000, 0x1002, "H"),
  ("oddb",   0x90000000, 0x1001, "B"),
  ("oddb2",  0x90000000, 0x1003, "b"),
]
# the refused constructions, probed by CALLING.
def odd_refused(nb, fmt):
  try:
    M.MMIOInterface(0x90000000, nb, fmt); return 0
  except TypeError: return 1
for nb, fmt in [(0x1001, "H"), (0x1001, "I"), (0x1001, "q"), (0x1003, "H"), (0x1001, "d")]:
  row(f"mmio_odd_refused_{nb}_{fmt}", odd_refused(nb, fmt))
# THE REMAINDER IS NOT ALWAYS 1. Every refused fixture above leaves one byte
# over, so `!= 0` and `== 1` are the SAME predicate over the whole family and a
# mutation reading `== 1` moved nothing. 4098 % 4 is 2 and 4098 % 2 is 0.
for nb, fmt in [(0x1002, "I"), (0x1002, "q"), (0x1002, "H"), (0x1000, "H"),
                (0x1000, "I"), (0x1000, "q"), (0x1001, "B")]:
  row(f"mmio_odd_refused_{nb}_{fmt}", odd_refused(nb, fmt))

# the calcsize table, BOTH directions.
FMTS = ['B','b','H','h','I','i','Q','q','f','d','?','2I','4B','2H','8B','I2B','3I','16B','6I','32B','12I','2d','4f']

# which of those are REACHABLE as an `MMIOInterface` fmt, probed by CALLING it.
def multichar_refused(f):
  try:
    M.MMIOInterface(0x90000000, 0x1000, f); return 0
  except ValueError: return 1
# THE REFUSAL OVER THE WHOLE `calcsize` TABLE, AS ONE ROW PER COLUMN. A format is
# refused EXACTLY when it is more than one character, so twenty-three per-format
# rows would be twenty-three copies of one claim.
row("mmio_multichar_len", " ".join(str(len(f)) for f in FMTS))
row("mmio_multichar_refused", " ".join(str(multichar_refused(f)) for f in FMTS))

# BumpAllocator: (size, base, wrap) and a sequence of (alloc_size, align).
BUMP = [
  ("plain",   0x1000, 0, False),
  ("wrap",    0x1000, 0, True),
  ("based",   0x1000, 0x70000000, True),
  ("aligned", 0x2000, 0, True),
]
BUMP_ALLOCS = [
  ("a16", 16, 1), ("a16b", 16, 1), ("a64", 64, 1),
  ("a64a16", 64, 16), ("a1a16", 1, 16), ("a4096", 4096, 4096),
  ("a4095", 4095, 1), ("a4096b", 4096, 1),
]

# A NON-MONOTONE `va_shifts` IS REFUSED BY CPYTHON, and that is a finding rather
# than a fixture: `1 << (lvl_msb[i+1] - lvl_msb[i])` is a NEGATIVE shift count
# when the shifts go backwards, and CPython raises `ValueError` where Bend's
# `U32.shln` wraps. So `pte_cnt` is only defined for a SORTED `va_shifts`, which
# makes the ladder invariant and the `first == max` order claim THEOREMS for
# every legal fixture -- see `mem_pte_barefused_*`.
def barefused(shifts, va_bits):
  try:
    lvl = shifts + [va_bits + 1]
    [1 << (lvl[i+1] - lvl[i]) for i in range(len(lvl)-1)]
    return 0
  except ValueError:
    return 1
for _sh in ([12, 21, 4], [0, 9, 4], [12, 21]):
  row(f"pte_barefused_{'_'.join(map(str, _sh))}", barefused(_sh, 21))

# pte layout: (name, va_shifts, va_bits)
PTE = [
  ("p4k",   [0], 12),
  ("p64_4k",[0, 6], 12),
  ("p64_2m",[0, 21], 21),
  ("x3",    [0, 9, 18], 27),
  ("x4",    [0, 9, 18, 27], 36),
  ("amd",   [12, 21, 30, 39, 48], 48),
  ("nv",    [16, 25, 34, 43, 52], 52),
  ("root1", [15], 47),
  ("tall",  [0, 9, 18, 27, 36, 45], 48),
  # THE TWO FIXTURES THAT MAKE THREE ROWS FALSIFIABLE. `nz` starts at a
  # non-zero shift so `cnts_raw`'s head predecessor is load-bearing; `bad` is
  # NOT monotone so the ladder product and `first == max` can both fail.
  ("nz",    [12, 21], 21),
]

# _frag_size: (name, va, sz, must_cover)
FRAG = [
  # the must_cover=False NEGATIVE CASE: a NON-power-of-two size, where the two
  # arms take DIFFERENT minima.
  ("a",   0x2000, 0x3000, True),
  ("an",  0x2000, 0x3000, False),
  # the sentinel case: va == 0 takes (1 << 63).
  ("b",   0,      0x1000, True),
  ("bn",  0,      0x1000, False),
  ("c",   0,      0x3000, True),
  ("cn",  0,      0x3000, False),
  # THEOREM family: a power-of-two sz makes both arms agree.
  ("d",   0x2000, 0x2000, True),
  ("dn",  0x2000, 0x2000, False),
  # unaligned va and sz.
  ("e",   0x1234, 0x1000, True),
  ("f",   0x1000, 0x1234, True),
  # odd va: lowbit 1, so the min is 1 and the answer is -13 (below the table).
  ("g",   1,      0x1000, True),
  # huge va, small sz.
  ("h",   0x100000, 0x1000, True),
  ("i",   0x1000, 0x200000, True),
  # the exact 4KB minimum: fragment 0.
  ("j",   0x1000, 0x1000, True),
  ("k",   0x1000, 0x2000, True),
]

# bit_length probes: powers of two and neighbours.
BITLEN = [0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 255, 256, 65535, 65536,
          0x7fffffff, 0x80000000, 0xffffffff]

# AllocSpace and VirtMapping
row("aspace_phys_val", M.AddrSpace.PHYS.value)
row("aspace_sys_val", M.AddrSpace.SYS.value)
row("aspace_peer_val", M.AddrSpace.PEER.value)
row("aspace_phys_ix", list(M.AddrSpace).index(M.AddrSpace.PHYS))
row("aspace_sys_ix", list(M.AddrSpace).index(M.AddrSpace.SYS))
row("aspace_peer_ix", list(M.AddrSpace).index(M.AddrSpace.PEER))
row("aspace_names", " ".join(e.name for e in M.AddrSpace))
# THE TABLE, BOTH DIRECTIONS, AS LISTS -- so a swap in either column shows as a
# DIFFERENT LIST rather than as a matching pair of scalars.
row("aspace_tbl_ix", " ".join(str(list(M.AddrSpace).index(e)) for e in M.AddrSpace))
row("aspace_tbl_val", " ".join(str(e.value) for e in M.AddrSpace))
row("aspace_tbl_names", " ".join(e.name for e in M.AddrSpace))
# `enum.auto()` starts at 1, so `value == index + 1` for every member.
row("aspace_val_is_ix_plus1", all(e.value == list(M.AddrSpace).index(e) + 1 for e in M.AddrSpace))
# THE ALIAS: PHYS's VALUE is 1 and SYS's INDEX is 1, so a port that read the
# value where the index belongs maps both onto one address space.
row("aspace_alias_phys_val_is_sys_ix", M.AddrSpace.PHYS.value)

vm_fields = [f.name for f in dataclasses.fields(M.VirtMapping)]
row("vm_fields", " ".join(vm_fields))
row("vm_defaults", " ".join(
  ("false" if f.default is False else "missing") for f in dataclasses.fields(M.VirtMapping)))

# the paddr pair order, read off the annotation and not typed.
row("vm_pa_ann", M.VirtMapping.__annotations__["paddrs"])

# the MMIOInterface field order, out of the four-tuple assignment. The
# four-tuple is on the LAST source line of the def, and the field names are the
# dotted targets -- so the parse takes the part after the last `=`, splits on
# `,`, and keeps the dotted entries.
import inspect
def assign_fields(fn):
  """The dotted TARGETS of the first `self.a, self.b = ...` line in the body.

  `rsplit('=', 1)` and not `split`, because a signature can carry its own `=`
  (`fmt='B'`) before the assignment -- which is exactly how the first version
  of this parse lost `mv` and `size`.
  """
  body = inspect.getsource(fn).strip().split('\n')
  for l in body:
    # a one-line `def f(...): self.a, self.b = ...` puts the body AFTER the
    # signature's `):`, and a naive `split(':')` splits inside the ANNOTATIONS
    # (`addr:int`) instead -- which is what silently emptied the first two rows.
    s = l.strip()
    if s.startswith('def '): s = s.split('):', 1)[1].strip() if '):' in s else ''
    if s.startswith('self.') and '=' in s:
      lhs = s.rsplit('=', 1)[0]
      return [t.strip().split('.', 1)[1].split(':')[0] for t in lhs.split(',') if t.strip().startswith('self.')]
  return []

row("mmio_init_fields", " ".join(assign_fields(M.MMIOInterface.__init__)))
row("bump_init_fields", " ".join(assign_fields(M.BumpAllocator.__init__)))
row("tlsf_init_fields", " ".join(assign_fields(M.TLSFAllocator.__init__)))
# and the SIGNATURES, which give the DEFAULT VALUES -- read off `inspect`, so
# `fmt='B'`, `base=0`, `wrap=True`, `block_size=16`, `lv2_cnt=16`, `align=1`.
for fn, nm in [(M.MMIOInterface.__init__, "mmio"), (M.BumpAllocator.__init__, "bump"),
               (M.MMIOInterface.view, "mmio_view"), (M.BumpAllocator.alloc, "bump_alloc"),
               (M.MemoryManager.__init__, "mm"), (M.MemoryManager.palloc, "palloc"),
               (M.MemoryManager.valloc, "valloc"), (M.MemoryManager.alloc_vaddr, "alloc_vaddr"),
               (M.MemoryManager._frag_size, "frag_size"),
               (M.MemoryManager.map_range, "map_range"),
               (M.MemoryManager.unmap_range, "unmap_range"),
               (M.PageTableTraverseContext.__init__, "ptctx"),
               (M.MemoryManager.vfree, "vfree")]:
  sig = inspect.signature(fn)
  ps = []
  for p in sig.parameters.values():
    if p.default is inspect.Parameter.empty: ps.append(p.name)
    else: ps.append(f"{p.name}={p.default!r}")
  row(f"sig_{nm}", " ".join(ps))

# the blocks 4-tuple, read out of the dict literal at :39.
blocks_line = [l for l in inspect.getsource(M.TLSFAllocator.__init__).split('\n') if 'self.blocks:' in l][0]
# the tuple is `{0: (a, b, c, d)}` -- the annotation's `tuple[...]` comes
# first, so the dict literal's tuple is the LAST parenthesised group.
row("tlsf_blocks_tuple", " ".join(
  p.strip() for p in blocks_line.rsplit('(', 1)[1].split(')')[0].split(',')))
# and the trailing comment on that line NAMES the four fields in order, which
# is the independent reading of the same order.
row("tlsf_blocks_comment", " ".join(
  p.strip() for p in blocks_line.split('#', 1)[1].split(',')))

# ===========================================================================
# THE ROWS.
# ===========================================================================

# --- MMIO: __len__ and view ---
# THE FOUR FIELD COLUMNS ARE LIST ROWS, not one row per fixture per field: the
# fixtures differ only in `addr`/`nbytes`/`fmt` and a per-fixture field row says
# nothing a single list does not, while a list makes a swapped column a
# DIFFERENT LIST instead of a matching pair of scalars.
_mmio = [M.MMIOInterface(a, nb, f) for _nm, a, nb, f in MMIO]
row("mmio_addr_tbl", " ".join(str(m.addr) for m in _mmio))
row("mmio_nbytes_tbl", " ".join(str(m.nbytes) for m in _mmio))
row("mmio_fmt_tbl", " ".join(m.fmt for m in _mmio))
row("mmio_isbyte_tbl", " ".join(str(m.fmt == 'B') for m in _mmio))
for nm, addr, nb, fmt in MMIO:
  row(f"mmio_len_{nm}", len(M.MMIOInterface(addr, nb, fmt)))

# view(): (name, off, size or None, fmt or None)
VIEWS = [
  ("whole",  0,    None,  None),
  ("off",    0x10, None,  None),
  ("sz",     0x10, 0x100, None),
  ("fmt",    0x10, None,  "H"),
  ("all",    0x10, 0x100, "I"),
  ("root",   0,    None,  None),
  ("end",    0x2000, None, None),
  ("b_off",  0x10, None,  "B"),
  ("b_all",  0x8,  0x800, "B"),
  ("sz0",    0x10, 0,    None),
]
for nm, off, sz, fmt in VIEWS:
  # a fresh 'I' window whose 0x2000 bytes is a multiple of 4.
  m = M.MMIOInterface(0x90000000, 0x2000, "I")
  v = m.view(off, sz, fmt)
  row(f"mmio_view_addr_{nm}", v.addr)
  row(f"mmio_view_nbytes_{nm}", v.nbytes)
  row(f"mmio_view_fmt_{nm}", v.fmt)
  row(f"mmio_view_len_{nm}", len(v))

# a NESTED view: offsets ACCUMULATE and the base is the ROOT's.
m = M.MMIOInterface(0x90000000, 0x2000, "I")
v1 = m.view(0x100, None, "H")
v2 = v1.view(0x8, 0x40, "B")
v3 = v2.view(0x4, None, None)
row("mmio_nest1_addr", v1.addr)
row("mmio_nest1_nbytes", v1.nbytes)
row("mmio_nest2_addr", v2.addr)
row("mmio_nest2_nbytes", v2.nbytes)
row("mmio_nest2_fmt", v2.fmt)
row("mmio_nest2_len", len(v2))
# the THIRD level, to say the accumulation is not a two-level coincidence.
row("mmio_nest3_addr", v3.addr)
row("mmio_nest3_nbytes", v3.nbytes)
row("mmio_nest3_fmt", v3.fmt)
# and the invariant: every level's address is the ROOT's plus the sum of the
# offsets, which is what "offsets ACCUMULATE" means.
row("mmio_accum_root", m.addr)
row("mmio_accum_sum", 0x100 + 0x8 + 0x4)
row("mmio_accum_addr", v3.addr - m.addr)

# --- calcsize, BOTH directions ---
row("calcsizes_names", " ".join(FMTS))
row("calcsizes_sizes", " ".join(str(struct.calcsize(f)) for f in FMTS))
# reverse: for each DISTINCT size, the FIRST fmt with that size
seen = []
for f in FMTS:
  s = struct.calcsize(f)
  if s not in [x[0] for x in seen]: seen.append((s, f))
for s, f in seen: row(f"calcsize_rev_{s}", f)
# and the NEGATIVE: a size calcsize never returns.
for s in [0, 3, 5, 7, 9, 10, 11, 64]:
  row(f"calcsize_absent_{s}", int(any(struct.calcsize(f) == s for f in FMTS)))

# --- BumpAllocator ---
def bump_seq(size, base, wrap, allocs):
  b = M.BumpAllocator(size, base, wrap)
  addrs, ptrs = [], []
  for anm, asz, al in allocs:
    try:
      p = b.alloc(asz, al)
    except RuntimeError:
      break
    addrs.append(p); ptrs.append(b.ptr)
  return addrs, ptrs

for bn, size, base, wrap in BUMP:
  addrs, ptrs = bump_seq(size, base, wrap, BUMP_ALLOCS)
  # `bump_seq_<bn>` is the ADDRESSES :21 returns and `bump_ptr_seq_<bn>` is the
  # POINTER :20 leaves behind. They are different lists -- the wrap arm resets
  # `ptr` to 0 and `base` is added on top -- so both are rows.
  row(f"bump_seq_{bn}", " ".join(map(str, addrs)))
  row(f"bump_ptr_seq_{bn}", " ".join(map(str, ptrs)))
  row(f"bump_seq_n_{bn}", len(addrs))

# THE WRAP/REFUSE PAIR AT THE SAME SIZE AND THE SAME ALLOCATION. `plain` and
# `wrap` differ in NOTHING but the `wrap` flag, and the refused and taken
# answers sit one row apart -- which is the negative-case requirement, and the
# refusal is the NEGATIVE side of the pair.
row("bump_pair_same_size", BUMP[0][1])
# the REFUSAL FLAG, not a sentinel address: the two lanes share one `U32`
# representation, so "did the nth request raise" is the portable claim.
def refused_nth(size, base, wrap, n):
  b = M.BumpAllocator(size, base, wrap)
  for i, (anm, asz, al) in enumerate(BUMP_ALLOCS[:n+1]):
    try: b.alloc(asz, al)
    except RuntimeError: return int(i == n)
  return 0
row("bump_pair_plain_refused", refused_nth(BUMP[0][1], BUMP[0][2], BUMP[0][3], 5))
row("bump_pair_wrap_refused", refused_nth(BUMP[1][1], BUMP[1][2], BUMP[1][3], 5))
row("bump_pair_wrap_addr", bump_seq(BUMP[1][1], BUMP[1][2], BUMP[1][3], BUMP_ALLOCS)[0][-1])
row("bump_pair_based_addr", bump_seq(BUMP[2][1], BUMP[2][2], BUMP[2][3], BUMP_ALLOCS)[0][-1])
row("bump_pair_aligned_addr", bump_seq(BUMP[3][1], BUMP[3][2], BUMP[3][3], BUMP_ALLOCS)[0][-1])
# THE POINTER, WHICH IS NOT THE END OF THE ADDRESS: `ptr` is `res + size` and the
# RETURNED address is `base + res`, so one 16-byte allocation at alignment 1 from
# a fresh allocator says `ptr == 16` while the address is 0.
def ptr_is_end(size, base, wrap, asz, al):
  b = M.BumpAllocator(size, base, wrap)
  res = round_up(b.ptr, al)
  b.alloc(asz, al)
  return int(b.ptr == res + asz)
for bn, size, base, wrap in BUMP: row(f"bump_ptr_is_end_{bn}", int(ptr_is_end(size, base, wrap, 16, 1)))
# the pointer after the refusal: it must be UNCHANGED, which the row that a
# refused allocation that still advanced the pointer fails.
bp = M.BumpAllocator(BUMP[0][1], BUMP[0][2], BUMP[0][3])
bp.alloc(16, 1)
ptr_before = bp.ptr
try: bp.alloc(4096, 4096)
except RuntimeError: pass
row("bump_refuse_ptr_before", ptr_before)
row("bump_refuse_ptr_after", bp.ptr)
row("bump_refuse_same", int(bp.ptr == ptr_before))
# the wrap arm RESETS to 0, not to the aligned value: the next allocation's
# padding is measured from 0.
bw = M.BumpAllocator(BUMP[1][1], BUMP[1][2], BUMP[1][3])
# FILL THE WINDOW and then ask for one more byte. Two 0x800-at-0x100 requests
# put the pointer at exactly 0x1000, so the third (16 bytes at alignment 1)
# overflows by exactly 16 -- and the wrap arm resets `self.ptr = 0`, so the
# answer is 0 and NOT 0x1000. That is the whole content of :19.
bw.alloc(0x800, 0x100)
bw.alloc(0x800, 0x100)
row("bump_wrap_ptr_pre", bw.ptr)
row("bump_wrap_over", int(round_up(bw.ptr, 1) + 16 > bw.size))
row("bump_wrap_next", bw.alloc(16, 1))
row("bump_wrap_ptr_post", bw.ptr)
# the ALIGNED wrap, which is the other half: a request whose alignment padding
# is what tips it over, where the UNPADDED test would not have.
bwa = M.BumpAllocator(BUMP[1][1], BUMP[1][2], BUMP[1][3])
bwa.alloc(0x800, 0x100)
row("bump_wrap_a_pre", bwa.ptr)
row("bump_wrap_a_over", int(round_up(bwa.ptr, 0x100) + 0x800 > bwa.size))
row("bump_wrap_a_noround", int(bwa.ptr + 0x800 > bwa.size))
row("bump_wrap_a_next", bwa.alloc(0x800, 0x100))
row("bump_wrap_a_post", bwa.ptr)

# the overflow test itself: `round_up(ptr, align) + size > self.size`
for bn, size, base, wrap in BUMP:
  for i, (anm, asz, al) in enumerate(BUMP_ALLOCS):
    b = M.BumpAllocator(size, base, wrap)
    for anm2, asz2, al2 in BUMP_ALLOCS[:i]:
      try: b.alloc(asz2, al2)
      except RuntimeError: pass
    over = (round_up(b.ptr, al) + asz > size)
    row(f"bump_over_{bn}_{i}", int(over))
    row(f"bump_over_pad_{bn}_{i}", round_up(b.ptr, al))
    row(f"bump_over_ptr_{bn}_{i}", b.ptr)
    # the UNPADDED comparison, which is the mutation that drops the round: it
    # differs from `over` wherever the padding mattered, and the row pair
    # `bump_over_*` / `bump_over_noround_*` is what catches it.
    row(f"bump_over_noround_{bn}_{i}", int(b.ptr + asz > size))

# --- pte layout ---
U32MAX = 0xffffffff
for nm, shifts, vbits in PTE:
  lvl_msb = shifts + [vbits + 1]
  covers = [1 << x for x in shifts][::-1]
  cnts = [1 << (lvl_msb[i+1] - lvl_msb[i]) for i in range(len(lvl_msb)-1)][::-1]
  row(f"pte_shifts_{nm}", " ".join(map(str, shifts)))
  row(f"pte_vabits_{nm}", vbits)
  row(f"pte_msb_{nm}", " ".join(map(str, lvl_msb)))
  row(f"pte_msb_len_{nm}", len(lvl_msb))
  row(f"pte_level_cnt_{nm}", len(shifts))
  # `pte_covers` AND `pte_cnt` BOTH LEAVE `U32` FOR SOME OF THE REAL TABLES --
  # `1 << 48` for AMD's root cover and `1 << 33` for `root1`'s root entry count
  # -- and a `U32` port SATURATES them to 0. Emitting the covered rows anyway
  # would fail them for the wrong reason (the port did not mis-order anything,
  # it ran out of bits), so each row is emitted only while its own table still
  # fits, and the two real device root covers are gated as `H.I64` pairs by
  # `pte64_root_*` instead.
  if all(c <= U32MAX for c in cnts):
    row(f"pte_cnts_{nm}", " ".join(map(str, cnts)))
    row(f"pte_root_cnt_{nm}", cnts[0])
  if all(c <= U32MAX for c in covers) and all(c <= U32MAX for c in cnts):
    # the ladder invariant, for every lv >= 1. It MULTIPLIES the two tables, so
    # it needs BOTH of them to fit even where each separately would.
    lad = []
    for lv in range(len(covers)):
      if lv == 0: lad.append(0); continue
      lad.append(int(cnts[lv] * covers[lv] == covers[lv-1]))
    row(f"pte_ladder_{nm}", " ".join(map(str, lad)))
    row(f"pte_covers_{nm}", " ".join(map(str, covers)))
    row(f"pte_covers_raw_{nm}", " ".join(str(1 << x) for x in shifts))
    row(f"pte_first_largest_{nm}", int(covers[0] == max(covers)))
    row(f"pte_root_covers_{nm}", covers[0])

# --- _frag_size ---
# `_frag_size` ANSWERS CAN BE NEGATIVE (`bit_length(1) - 1 - 12 == -13`), and the
# Bend lane is a `U32` lane, so every answer is printed MODULO 2**32 -- which is
# the same number in two's complement, so `frag_e=4294967286` IS CPython's
# `-10` and one row carries both readings. (A second `frag_*_signed` row would
# be the same number twice, and a gate that diffs whole lines would then have a
# row no mutation can move.)
# THE ROW NAMES ARE `<value>_<sub>_<fixture>` -- `frag_e_min`, not `frag_min_e`
# -- so the fixture is the LAST token and one mutation moves a whole fixture.
U32 = 1 << 32
for nm, va, sz, mc in FRAG:
  a = M.MemoryManager.__new__(M.MemoryManager)
  row(f"frag_{nm}", a._frag_size(va, sz, mc) % U32)
  va_p = (va & -va) if va > 0 else (1 << 63)
  # THE `U32` STAND-IN. CPython's `1 << 63` is outside a U32, so the Bend lane
  # substitutes `2**31`; `lowbit_zero_64` and `lowbit_zero` carry the real
  # sentinel and the stand-in, so the substitution is gated there instead of
  # being restated thirteen times.
  row(f"frag_{nm}_va_div", (va_p if va > 0 else (1 << 31)) % U32)
  row(f"frag_{nm}_sz_div", sz & -sz)
  row(f"frag_{nm}_sz_max", 1 << (sz.bit_length()-1))
  row(f"frag_{nm}_min", min(va_p, sz & -sz) if mc else min(va_p, 1 << (sz.bit_length()-1)))
  row(f"frag_{nm}_min_bl", (min(va_p, sz & -sz) if mc else min(va_p, 1 << (sz.bit_length()-1))).bit_length())

# the lowbit in isolation, which is what a port that forgot the sentinel gets.
LOWBITS = [0, 1, 2, 3, 4, 6, 8, 12, 14, 16, 0x1000, 0x1234, 0x80000000, 0xffffffff]
for x in LOWBITS:
  row(f"lowbit_{x}", x & -x)
# and the fixture named, so a wrong fixture is visible rather than a wrong answer.
for x in [0, 12, 0x80000000, 0xffffffff]:
  row(f"lowbit_x_{x}", x)

# THE SENTINEL, both spellings. `1 << 63` is outside a U32, so the honest
# constant is an I64 pair and the U32 stand-in is `2**31` -- which is never
# smaller than any lowbit a U32 `sz` can have.
# `H.i64_text` is `hi:lo` in DECIMAL (helpers.bend:1229-1233), so the oracle
# prints the same shape rather than inventing a hex rendering.
row("lowbit_zero_64", f"{(1 << 63) >> 32}:{1 << 63 & 0xffffffff}")
row("lowbit_zero", 1 << 31)
row("lowbit_zero_is_max_u32", int((1 << 31) == 0xffffffff))
row("lowbit_zero_over_u32", int((1 << 31) > 0x7fffffff))

# bit_length probes
for x in BITLEN:
  row(f"bitlen_{x}", x.bit_length())

# --- MemoryManager allocator windows ---
# :190-192. boot/ptable/pa windows, and the off_sz that separates them.
VRAM = [("v64m", 0x4000000), ("v1g", 0x40000000), ("vodd", 0x40000001), ("v16m", 0x1000000)]
BOOT = [("b64k", 0x10000), ("b0", 0)]
for vn, vram in VRAM:
  for bn, boot in BOOT:
    for reserve in [False, True]:
      pa_sz = round_up(vram // 512, 1 << 20) if reserve else 0
      off_sz = boot + pa_sz
      pa = vram - off_sz
      tag = f"{vn}_{bn}_{int(reserve)}"
      row(f"mm_boot_sz_{tag}", boot)
      row(f"mm_ptable_sz_{tag}", pa_sz)
      row(f"mm_off_sz_{tag}", off_sz)
      row(f"mm_pa_sz_{tag}", pa)
      row(f"mm_pa_base_{tag}", off_sz)

# the va_allocator window and alloc_vaddr's alignment. THE `hi:lo` SPELLING is
# `H.i64_text`'s (helpers.bend:1229) and it is the row -- the two halves are the
# same number, so printing `hi` and `lo` as their own rows would be three rows
# where one is the claim.
row("va_alloc_size", f"{(1<<44)>>32}:{(1<<44)&0xffffffff}")
row("va_alloc_base", f"{0x200000000000>>32}:{0x200000000000&0xffffffff}")
row("va_alloc_size_hi", (1 << 44) >> 32)
row("va_alloc_size_lo", (1 << 44) & 0xffffffff)
row("va_alloc_base_hi", (0x200000000000) >> 32)
row("va_alloc_base_lo", (0x200000000000) & 0xffffffff)
# the SATURATION, which is the negative: a U32 shift by 44 is 0 and a 64-bit
# literal above U32 cannot be written at all.
row("va_alloc_size_u32_sat", (1 << 44) % (1 << 32))
row("va_alloc_size_lo_sat", (1 << 44) & 0xffffffff)
row("va_alloc_base_lo_sat", 0x200000000000 & 0xffffffff)
row("va_alloc_u32_would_be", (1 << 44) % (1 << 32))

# THE `vram_size // 512` DIVISION AND ITS TWO FAILURE MODES, split out because
# `mm_ptable_sz_*` folds the division into a zero for every `vram_size` under
# 512 MiB, so the division itself is only visible on its own rows.
for _v in [0x4000000, 0x40000000, 0x1000000]:
  row(f"mm_ptable_div_{_v}", _v // 512)
for _q in [131072, 131073, 2097152]:
  row(f"mm_ptable_round_{_q}", round_up(_q, 1 << 20))
row("mm_ptable_unit", 1 << 20)
row("mm_ptable_divisor", 512)

# alloc_vaddr's align: `max((1 << (size.bit_length() - 1)), align)`.
# the PORT computes the max; the allocator's answer is 64-bit, so what is
# gated here is the ALIGNMENT the port builds, which is U32-shaped.
VALLOC_SZ = [0x1000, 0x1001, 0x2000, 0x4000, 0x100000, 0x100001]
for sz in VALLOC_SZ:
  row(f"valloc_align_{sz}", max((1 << (sz.bit_length()-1)), 0x1000))
  row(f"valloc_round_{sz}", round_up(sz, 0x1000))
  row(f"valloc_p2_{sz}", 1 << (sz.bit_length()-1))

# THE 64-BIT WALL: pte_covers[0] is 1 << va_shifts[-1], and for the two REAL
# device tables that is outside a U32. 1 << 48 == 0x1000000000000000 and
# 1 << 52 == 0x10000000000000, so the hi/lo pairs are the rows.
# a U32 SHIFT SATURATES, so these are the zeros a U32 port would print and the
# `pte64_root_*` rows above are the values it should have had.
# `U32.shln` is `Word.shln` on 32 bits, so a shift by 48 is 0 -- the arithmetic
# wraps, it does not saturate, and these three rows are that 0.
row("pte64_shl_48", (1 << 48) % (1 << 32))
row("pte64_shl_52", (1 << 52) % (1 << 32))
row("pte64_shl_45", (1 << 45) % (1 << 32))
# `hi:lo` IN DECIMAL, which is `H.i64_text`'s spelling (helpers.bend:1229), so
# the two lanes print the same shape and the U32 lane's two halves are gated.
row("pte64_root_amd", f"{(1 << 48) >> 32}:{(1 << 48) & 0xffffffff}")
row("pte64_root_nv", f"{(1 << 52) >> 32}:{(1 << 52) & 0xffffffff}")

# THE VA ALLOCATOR'S OWN WALK IS NOT PORTED. `TLSFAllocator.alloc` drives the
# free list, and this port implements the bucket arithmetic (:43, :46, :91) and
# the size pipeline, not the list. So there is deliberately no `va_alloc_off_*`
# row: the Bend side would have been a literal, and a literal on one side of a
# diff is a change-detector rather than a gate. REPORTED AS A BLIND SPOT.

# palloc's rounding: `allocator.alloc(round_up(size, 0x1000), align)`.
PSZ = [1, 0xfff, 0x1000, 0x1001, 0x2000, 0x100000, 0x100001, 0x4000]
for sz in PSZ:
  row(f"palloc_round_{sz}", round_up(sz, 0x1000))
# THE PAGE SIZE, read off `palloc`'s own `align` default rather than typed.
row("palloc_size", inspect.signature(M.MemoryManager.palloc).parameters['align'].default)
# `MMIOInterface.__init__`'s `fmt` default, both the INDEX the port uses and the
# NAME, so a port that resolved the default to the wrong row moves.
row("mmio_def_fmt_nm", inspect.signature(M.MMIOInterface.__init__).parameters['fmt'].default)
row("mmio_def_fmt_ix", FMTS.index(inspect.signature(M.MMIOInterface.__init__).parameters['fmt'].default))

# --- TLSF bucket arithmetic (the two-way table) ---
def lv1(sz): return sz.bit_length()
def lv2(sz, l2c=5): return (sz - (1 << (sz.bit_length()-1))) // (1 << max(0, sz.bit_length()-l2c))
row("tlsf_l2_cnt", 16 .bit_length())
row("tlsf_block_size", 16)
LV1_SZ = [1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 100, 128, 255, 256, 1000, 1024]
for sz in LV1_SZ:
  row(f"tlsf_lv1_{sz}", lv1(sz))
  row(f"tlsf_lv2_{sz}", lv2(sz))
  # THE BUCKET KEY AS ONE NUMBER, `lv1 * 2^l2_cnt + lv2` -- the same key the
  # Bend lane prints, so the two lanes compare numbers and not strings.
  row(f"tlsf_bucket_{sz}", lv1(sz) * 32 + lv2(sz))
  # the REVERSE direction: the smallest size in the same bucket.
  row(f"tlsf_lv2_shift_{sz}", 1 << max(0, sz.bit_length()-5))
# storage length: `size.bit_length() + 1`.
for sz in [0, 1, 2, 0x1000, 0x100000]:
  row(f"tlsf_storage_len_{sz}", sz.bit_length() + 1)

# the alloc size pipeline, which has THREE distinct numbers:
#   req_size = max(block_size, req_size)
#   size = max(block_size, req_size + align - 1)
#   size = round_up(size, 1 << (size.bit_length() - l2_cnt))
ALLOC = [(16,1), (16,16), (1,1), (1,4096), (100,16), (0x1000,4096), (0x100,0x1000)]
for i, (rs, al) in enumerate(ALLOC):
  bs = 16
  a_req = max(bs, rs)
  a_sz = max(bs, a_req + al - 1)
  a_bl = a_sz.bit_length()
  a_round = round_up(a_sz, 1 << (a_bl - 5))
  row(f"tlsf_req_{i}", a_req)
  row(f"tlsf_sz_{i}", a_sz)
  row(f"tlsf_bl_{i}", a_bl)
  row(f"tlsf_round_{i}", a_round)
  row(f"tlsf_final_{i}", a_round)
  # the NEGATIVE case: does the bucket rounding actually round UP sometimes?
  row(f"tlsf_rounds_up_{i}", int(a_round != a_sz))

# --- valloc's palloc_ranges ladder ---
RANGES = [(0x200000, 0x1000), (0x40000, 0x1000), (0x4000, 0x1000), (0x1000, 0x1000)]
VREQ = [0x800000, 0x500000, 0x100000, 0x5000, 0x2000, 0x1000]
for req in VREQ:
  nxt, rem, picks = 0, req, []
  guard = 0
  while rem > 0 and guard < 40:
    guard += 1
    while RANGES[nxt][0] > rem: nxt += 1
    picks.append(RANGES[nxt][0])
    rem -= RANGES[nxt][0]
  # THE ROW NAME CARRIES THE REQUEST, so a mis-keyed fixture is visible instead
  # of being a row index that matches on both sides for the wrong reason.
  row(f"valloc_req_{req}", req)
  row(f"valloc_picks_{req}", " ".join(map(str, picks)))
  row(f"valloc_sum_{req}", sum(picks))
  row(f"valloc_rem_{req}", rem)

# ===========================================================================
# VirtMapping. THE TWO CONSTRUCTION SITES AND THEIR DIFFERENCE IN DEFAULTS.
# :225 supplies all six; :250 supplies four and LEAVES `snooped` out, and forces
# `aspace=AddrSpace.PHYS`. The identity VA is 48-bit so the fixtures use
# U32-sized VAs for the field rows and the 48-bit values are gated separately.
# ===========================================================================
VA = 0x70000000
def vm_all(vaddr, size, paddrs, aspace, uncached, snooped):
  return M.VirtMapping(vaddr, size, paddrs, aspace=aspace, uncached=uncached, snooped=snooped)
allv = vm_all(VA, 0x10000, [(0, 0x10000)], M.AddrSpace.SYS, True, True)
row("vm_all_va", allv.va_addr)
row("vm_all_size", allv.size)
row("vm_all_aspace", list(M.AddrSpace).index(allv.aspace))
row("vm_all_uncached", bool(allv.uncached))
row("vm_all_snooped", bool(allv.snooped))
row("vm_all_n_paddrs", len(allv.paddrs))

g = M.VirtMapping(VA, 0x10000, [(0, 0x10000)], aspace=M.AddrSpace.PHYS, uncached=True)
row("vm_gmmu0_va", g.va_addr)
row("vm_gmmu0_size", g.size)
row("vm_gmmu0_aspace", list(M.AddrSpace).index(g.aspace))
row("vm_gmmu0_uncached", bool(g.uncached))
row("vm_gmmu0_snooped", bool(g.snooped))
row("vm_gmmu0_n_paddrs", len(g.paddrs))

# identity_va + paddr -- :250's ADDRESS, and NOT paddr alone.
IDENT = 0x70000000
row("vm_gmmu0_va_sum", IDENT + 0)
row("vm_gmmu0_va_sum2", IDENT + 0x1000)
row("vm_gmmu0_va_sum3", IDENT + 0x2000)

# :211's assertion and :279's free loop read OPPOSITE halves of each pair.
def psize_sum(v): return sum(p[1] for p in v.paddrs)
def paddr_sum(v): return sum(p[0] for p in v.paddrs)
one = vm_all(0, 0x10000, [(0, 0x10000)], M.AddrSpace.SYS, False, False)
two = vm_all(0, 0x10000, [(0, 0x8000), (0x10000, 0x8000)], M.AddrSpace.SYS, False, False)
bad = vm_all(0, 0x10001, [(0, 0x10000)], M.AddrSpace.SYS, False, False)
row("vm_size_match_1", bool(one.size == psize_sum(one)))
row("vm_size_match_2", bool(two.size == psize_sum(two)))
row("vm_size_match_bad", bool(bad.size == psize_sum(bad)))
row("vm_psize_sum_1", psize_sum(one))
row("vm_psize_sum_2", psize_sum(two))
row("vm_free_paddrs_1", " ".join(str(p[0]) for p in vm_all(0, 0x10000, [(0x1000, 0x10000)], M.AddrSpace.SYS, False, False).paddrs))
# :277's unmap readers.
row("vm_unmap_va", allv.va_addr)
row("vm_unmap_sz", allv.size)
# THE PAIR ORDER IS GATED BY ITS TWO READERS: a mapping whose sizes DIFFER from
# its physical addresses is the one where a swapped `Pa` is visible.
off = vm_all(0, 0x10000, [(0x1000, 0x8000), (0x11000, 0x8000)], M.AddrSpace.SYS, False, False)
row("vm_loops_opposite_1", bool(paddr_sum(one) != psize_sum(one)))
row("vm_loops_opposite_2", bool(paddr_sum(off) != psize_sum(off)))

# ===========================================================================
# THE TRACE. A memoryview is FFI, so `to_mv(addr, nbytes).cast(fmt)` is two
# CALLS in that order and the trace is the only place they exist. These rows are
# what a retag of the vocabulary must move -- two mutations over the tags moved
# nothing until they existed.
# ===========================================================================
row("mmio_tr_seen", 2)                    # two calls: TO_MV then TO_MV_CAST
row("mmio_tr_next", 2)                     # two ids minted
row("mmio_tr_handle", 0)                   # the first id is 0
row("mmio_tr_addr", 0x90000000)
row("mmio_tr_nbytes", 0x1000)
row("mmio_tr_n_to_mv", 1)
row("mmio_tr_n_cast", 1)
row("mmio_tr_n_index", 0)                  # MMIO_INDEX is not emitted by a ctor
row("mmio_tr_args_to_mv", "4096")          # `to_mv`'s `arg` is the LENGTH
row("mmio_tr_args_cast", "0")              # `.cast`'s `arg` is the fmt INDEX
row("mmio_tr_refused_before", 0)           # `Tr.of()` has NOT refused yet
row("mmio_tr_after_refuse_seen", 0)        # `Tr.refuse` EMPTIES the trace
# the ORDER predicates: the true sequence and the reversed one.
row("mmio_tr_seq_ok", True)
row("mmio_tr_seq_swapped", False)
row("mmio_tr_after_refuse", True)

# ===========================================================================
# THE PAGE-TABLE ASSERT LOOPS, :215 and :233-234, and they are run AS PYTHON so
# the order and the stopping point come from the interpreter rather than from a
# transcription. A recorder stands in for the device page table:
#   * `assert not pt.valid(i), f"PTE already mapped: {pt.entry(i):#x}"` reads
#     `valid` FIRST and evaluates the message -- and so `entry` -- only on
#     failure, then raises and the rest of the loop is replaced.
#   * `assert pt.valid(pte_id), ...; pt.set_entry(pte_id, paddr=0x0,
#     valid=False)` reads `valid`, records a WRITE, and halts on a PENDING entry.
# ===========================================================================
PT = [(1, 4096), (1, 8192), (0, 0), (0, 0)]
PT_INV = [(0, 0), (0, 0), (1, 12288), (1, 16384)]
class Rec:
  def __init__(self, tab): self.tab, self.calls = tab, []
  def valid(self, i): self.calls.append(("V", i)); return bool(self.tab[i][0])
  def entry(self, i): self.calls.append(("E", i)); return self.tab[i][1]
  def set_entry(self, i, paddr, valid): self.calls.append(("S", i))
def pt_map(tab):
  r = Rec(tab)
  try:
    for pte_off in range(len(tab)):
      assert not r.valid(pte_off), f"PTE already mapped: {r.entry(pte_off):#x}"
  except AssertionError: pass
  return r.calls
def pt_unmap(tab):
  r = Rec(tab)
  try:
    for pte_id in range(len(tab)):
      assert r.valid(pte_id), f"PTE not mapped: {r.entry(pte_id):#x}"
      r.set_entry(pte_id, paddr=0x0, valid=False)
  except AssertionError: pass
  return r.calls
def trace_rows(tag, calls):
  row(f"pt_{tag}_seen", len(calls))
  row(f"pt_{tag}_n_valid", sum(1 for k, _ in calls if k == "V"))
  row(f"pt_{tag}_n_entry", sum(1 for k, _ in calls if k == "E"))
  row(f"pt_{tag}_n_set", sum(1 for k, _ in calls if k == "S"))
  row(f"pt_{tag}_args", " ".join(str(i) for k, i in calls if k == "V"))
trace_rows("map", pt_map(PT))
trace_rows("map_ok", pt_map(PT_INV))
trace_rows("unmap", pt_unmap(PT))
trace_rows("unmap_ok", pt_unmap(PT_INV))
# THE ORDER, which is the claim a transposed `pt_valid`/`pt_entry` moves. One
# mapped entry at index 3 is all it takes: `valid` is read first and `entry`
# only on failure.
_m = Rec([(0, 0), (0, 0), (0, 0), (1, 0)])
try: assert not _m.valid(3), f"PTE already mapped: {_m.entry(3):#x}"
except AssertionError: pass
row("pt_order_ok", int([c[0] for c in _m.calls] == ["V", "E"]))
row("pt_order_swapped", int([c[0] for c in _m.calls] == ["E", "V"]))
_p = Rec([(0, 0), (0, 0), (0, 0), (0, 0)])
assert not _p.valid(3), f"PTE already mapped: {_p.entry(3):#x}"
row("pt_order_pending", int([c[0] for c in _p.calls] == ["V"]))

print("\n".join(rows))
