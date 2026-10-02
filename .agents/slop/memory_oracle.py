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

# the calcsize table, BOTH directions.
FMTS = ['B','b','H','h','I','i','Q','q','f','d','?','2I','4B','2H','8B','I2B','3I','16B','6I','32B','12I','2d','4f']

# which of those are REACHABLE as an `MMIOInterface` fmt, probed by CALLING it.
def multichar_refused(f):
  try:
    M.MMIOInterface(0x90000000, 0x1000, f); return 0
  except ValueError: return 1
for f in FMTS:
  row(f"mmio_multichar_refused_{f}", multichar_refused(f))

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
for nm, addr, nb, fmt in MMIO:
  m = M.MMIOInterface(addr, nb, fmt)
  row(f"mmio_len_{nm}", len(m))
  row(f"mmio_addr_{nm}", m.addr)
  row(f"mmio_nbytes_{nm}", m.nbytes)
  row(f"mmio_fmt_{nm}", m.fmt)
  row(f"mmio_isbyte_{nm}", m.fmt == 'B')

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
  outs = []
  for anm, asz, al in allocs:
    try:
      p = b.alloc(asz, al)
      outs.append((p, b.ptr))
    except RuntimeError:
      outs.append((-1, b.ptr))
      break
  return outs

for bn, size, base, wrap in BUMP:
  o = bump_seq(size, base, wrap, BUMP_ALLOCS)
  row(f"bump_ptr_init_{bn}", 0)
  for i, (p, ptr) in enumerate(o):
    row(f"bump_alloc_{bn}_{i}", p)
    row(f"bump_ptr_{bn}_{i}", ptr)
  row(f"bump_n_{bn}", len(o))

# THE WRAP/REFUSE PAIR AT THE SAME SIZE AND THE SAME ALLOCATION. `plain` and
# `wrap` differ in NOTHING but the `wrap` flag, and the refused and taken
# answers sit one row apart -- which is the negative-case requirement, and the
# refusal is the NEGATIVE side of the pair.
row("bump_pair_same_size", BUMP[0][1])
row("bump_pair_plain_refused", bump_seq(BUMP[0][1], BUMP[0][2], BUMP[0][3], BUMP_ALLOCS)[-1][0])
row("bump_pair_wrap_addr", bump_seq(BUMP[1][1], BUMP[1][2], BUMP[1][3], BUMP_ALLOCS)[-1][0])
# the pointer after the refusal: it must be UNCHANGED, which is the row that a
# refused allocation that still advanced the pointer fails.
bp = M.BumpAllocator(BUMP[0][1], BUMP[0][2], BUMP[0][3])
bp.alloc(16, 1)
ptr_before = bp.ptr
try: bp.alloc(4096, 4096)
except RuntimeError: pass
row("bump_refuse_ptr_before", ptr_before)
row("bump_refuse_ptr_after", bp.ptr)
# the wrap arm RESETS to 0, not to the aligned value: the next allocation's
# padding is measured from 0.
bw = M.BumpAllocator(BUMP[1][1], BUMP[1][2], BUMP[1][3])
bw.alloc(0x800, 0x100)
row("bump_wrap_ptr_pre", bw.ptr)
row("bump_wrap_next", bw.alloc(16, 0x100))
row("bump_wrap_ptr_post", bw.ptr)

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
for nm, shifts, vbits in PTE:
  lvl_msb = shifts + [vbits + 1]
  covers = [1 << x for x in shifts][::-1]
  cnts = [1 << (lvl_msb[i+1] - lvl_msb[i]) for i in range(len(lvl_msb)-1)][::-1]
  row(f"pte_shifts_{nm}", " ".join(map(str, shifts)))
  row(f"pte_vabits_{nm}", vbits)
  row(f"pte_msb_{nm}", " ".join(map(str, lvl_msb)))
  row(f"pte_covers_{nm}", " ".join(map(str, covers)))
  row(f"pte_covers_raw_{nm}", " ".join(str(1 << x) for x in shifts))
  row(f"pte_cnts_{nm}", " ".join(map(str, cnts)))
  row(f"pte_level_cnt_{nm}", len(shifts))
  row(f"pte_msb_len_{nm}", len(lvl_msb))
  row(f"pte_first_largest_{nm}", int(covers[0] == max(covers)))
  # the ladder invariant, for every lv >= 1.
  lad = []
  for lv in range(len(covers)):
    if lv == 0: lad.append(0); continue
    lad.append(int(cnts[lv] * covers[lv] == covers[lv-1]))
  row(f"pte_ladder_{nm}", " ".join(map(str, lad)))
  # the root-level entry count: pte_cnt[0] is the number of ROOT entries.
  row(f"pte_root_cnt_{nm}", cnts[0])
  row(f"pte_root_covers_{nm}", covers[0])

# --- _frag_size ---
for nm, va, sz, mc in FRAG:
  a = M.MemoryManager.__new__(M.MemoryManager)
  row(f"frag_{nm}", a._frag_size(va, sz, mc))
  va_p = (va & -va) if va > 0 else (1 << 63)
  row(f"frag_va_div_{nm}", va_p)
  row(f"frag_sz_div_{nm}", sz & -sz)
  row(f"frag_sz_max_{nm}", 1 << (sz.bit_length()-1))
  row(f"frag_min_{nm}", min(va_p, sz & -sz) if mc else min(va_p, 1 << (sz.bit_length()-1)))
  row(f"frag_min_bl_{nm}", (min(va_p, sz & -sz) if mc else min(va_p, 1 << (sz.bit_length()-1))).bit_length())

# the lowbit in isolation, which is what a port that forgot the sentinel gets.
LOWBITS = [0, 1, 2, 3, 4, 6, 8, 12, 14, 16, 0x1000, 0x1234, 0x80000000, 0xffffffff, 1, 0x2000]
for x in LOWBITS:
  row(f"lowbit_{x}", x & -x)
  row(f"lowbit_div_{x}", (x + x - x) - (x + x - x))  # placeholder replaced below
  rows.pop(); rows.pop()
  row(f"lowbit_x_{x}", x)
  row(f"lowbit_{x}", x & -x)
  row(f"lowbit_plus1_{x}", (x & -x) + 1)

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

# the va_allocator window and alloc_vaddr's alignment.
row("va_alloc_size", 1 << 44)
row("va_alloc_base", 0x200000000000)
row("va_alloc_size_hi", (1 << 44) >> 32)
row("va_alloc_size_lo", (1 << 44) & 0xffffffff)
row("va_alloc_base_hi", (0x200000000000) >> 32)
row("va_alloc_base_lo", (0x200000000000) & 0xffffffff)

# alloc_vaddr's align: `max((1 << (size.bit_length() - 1)), align)`.
# the PORT computes the max; the allocator's answer is 64-bit, so what is
# gated here is the ALIGNMENT the port builds, which is U32-shaped.
VALLOC_SZ = [0x1000, 0x1001, 0x2000, 0x4000, 0x100000, 0x100001]
for sz in VALLOC_SZ:
  row(f"valloc_align_{sz}", max((1 << (sz.bit_length()-1)), 0x1000))
  row(f"valloc_round_{sz}", round_up(sz, 0x1000))
  row(f"valloc_p2_{sz}", 1 << (sz.bit_length()-1))

# the va_allocator itself, small window so U32 arithmetic suffices.
va = M.TLSFAllocator(1 << 20, base=0)
for i, sz in enumerate([0x100, 0x100, 0x100, 0x200, 0x400]):
  p = va.alloc(sz, 1)
  row(f"va_alloc_{i}", p)
  row(f"va_alloc_aligned_{i}", p % 0x100)

# palloc's rounding: `allocator.alloc(round_up(size, 0x1000), align)`.
PSZ = [1, 0xfff, 0x1000, 0x1001, 0x2000, 0x100000]
for sz in PSZ:
  row(f"palloc_round_{sz}", round_up(sz, 0x1000))

# --- TLSF bucket arithmetic (the two-way table) ---
def lv1(sz): return sz.bit_length()
def lv2(sz, l2c=5): return (sz - (1 << (sz.bit_length()-1))) // (1 << max(0, sz.bit_length()-l2c))
row("tlsf_l2_cnt", 16 .bit_length())
row("tlsf_block_size", 16)
LV1_SZ = [1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 100, 128, 255, 256, 1000, 1024]
for sz in LV1_SZ:
  row(f"tlsf_lv1_{sz}", lv1(sz))
  row(f"tlsf_lv2_{sz}", lv2(sz))
  row(f"tlsf_bucket_{sz}", f"{lv1(sz)}:{lv2(sz)}")
  # the REVERSE direction: the smallest size in the same bucket.
  row(f"tlsf_lv2_shift_{sz}", 1 << max(0, sz.bit_length()-5))
# storage length: `size.bit_length() + 1`.
for sz in [0, 1, 2, 0x1000, 0x100000, 1 << 20]:
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
for i, req in enumerate(VREQ):
  nxt, rem, picks = 0, req, []
  guard = 0
  while rem > 0 and guard < 40:
    guard += 1
    while RANGES[nxt][0] > rem: nxt += 1
    picks.append(RANGES[nxt][0])
    rem -= RANGES[nxt][0]
  row(f"valloc_req_{i}", req)
  row(f"valloc_picks_{i}", " ".join(map(str, picks)))
  row(f"valloc_sum_{i}", sum(picks))
  row(f"valloc_rem_{i}", rem)

print("\n".join(rows))
