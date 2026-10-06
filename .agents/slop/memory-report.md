# `tinybendygrad/runtime/support/memory.bend` — the port report

Source: `tinygrad/runtime/support/memory.py`, **288 lines**. Port: one file, **2,634 lines**,
no foreign effect, every Python call either traced or refused.

```
GATE      .agents/slop/memory-diff.py     rows: bend=889 oracle=889 compared=889 disagreements=0   (exit 0)
CHECK     ./bin/bend … --check-only      ALL PROOFS CHECK                                       (exit 0)
LANES     ./bin/bend f   ==   bend f -o /tmp/f && /tmp/f      889 lines, byte-identical
MUTATE    .agents/slop/memory-mutate.py   70 mutations, 6 moved nothing
```

`--check-only` reads **`ALL PROOFS CHECK`**, not `SOME PROOFS FAIL`: this file imports only
`Base` and `helpers.bend`, so `dtype.bend`'s fourteen permanent laws are not in its closure and
there is nothing here to fail. The gate is the FIRST LINE and the exit code; the run is 0.

---

## 1. THE THREE CITING FILES: WHAT THEY ASSUMED, CONFIRMED OR CONTRADICTED

### `tinybendygrad/schedule/memory.bend` — CONFIRMED, and it has no local reader to delete

It records (line 1510) `P6/runtime owns the allocator` and threads the allocator's answers in as
a **parameter**, `mem_offs() -> List<&2, Off>` at line 1044, called at lines 1131, 1312, 1323,
1329, 1334, 1335, 1384. **CONFIRMED: it wrote no local TLSF reader.** The offsets are a
parameter, the split is drawn at the wall, and there is nothing in it that this port makes
redundant — the opposite: `mem_offs` is what this port's `TLSFAllocator` bucket arithmetic would
have to feed. Nothing to delete there, and nothing borrowed.

### `tinybendygrad/runtime/ops_rdma.bend` — CONFIRMED at line 262–263, MEASURED at 789–795

`def ASPACE_SYS() -> U32: 1` with the comment `AddrSpace (support/memory.py) is [PHYS, SYS,
PEER], so SYS is index 1`. **CONFIRMED by measurement:** `aspace_tbl_ix=0 1 2`,
`aspace_tbl_val=1 2 3`, `aspace_sys_ix=1`, and `aspace_alias_phys_val_is_sys_ix=1` is the
negative — PHYS's *value* is 1 and SYS's *index* is 1, so a port that read the value where the
index belongs aliases the two address spaces onto one.

The file also records `va_allocator.base`/`.size` as a **WALL** at lines 789 and 795. It is still
a wall for *them* — the allocator window is the kernel's, read out of a class attribute. But the
WALL is now **measured on both sides of the seam**: `va_alloc_size=4096:0` and
`va_alloc_base=8192:0`, i.e. size `1 << 44` and base `0x200000000000` (`memory.py:182`), with
`va_alloc_size_u32_sat=0` next to them as the negative — a `U32` shift by 44 is zero, which is
how a free list once became zero-sized. **The citing file may now cite `mem_va_alloc_size` and
`mem_va_alloc_base` instead of carrying a wall.** It does not use them today.

### `tinybendygrad/runtime/support/am/ip.bend` — **CONTRADICTION FOUND, BOTH ANSWERS GATED**

Wall 6 (lines 1836–1841) records

```
#    TODO(p3) runtime/support/am/ip.py:278  mm.palloc(0x1000 * xccs, 2 + is_vf).
```

and the real line 278 is

```python
self.mqd_paddr = [self.adev.mm.palloc(0x1000 * self.xccs, zero=False, boot=True) for i in range(2 + self.adev.is_vf)]
```

**`2 + is_vf` is the comprehension's REPEAT COUNT, not `align`.** `palloc`'s signature
(`sig_palloc`) is `self size align=0x1000 zero=True boot=False ptable=False`, so the `align` on
that line is the **default 4096**, not `2 + is_vf` (which is 2 or 3). Two readings:

| reading | `align` | rows |
|---|---|---|
| **A — what the line says** | default `0x1000` | `sig_palloc`, `palloc_round_4096`, `palloc_size` |
| **B — what the wall says** | `2 + is_vf` ∈ {2,3} | `palloc_round_2`, `palloc_round_3` |

Both are gated: `sig_palloc=self size align=4096 zero=True boot=False ptable=False` is read off
`inspect.signature` and pins the DEFAULT; `palloc_round_4096` and `palloc_size` pin the
arithmetic. **A port that took reading B would answer `align=2` and `palloc_round_2=2` for a
`0x1000 * xccs` request, and `palloc_size=2` would be a wrong page.** The line number in the
wall is right and the transcription is wrong; `ip.bend` line 1840 needs the comprehension's
`range()` read as the count. Wall 6's second entry, `mm.map_range(..., AddrSpace.SYS, snooped,
uncached)` at line 331, is **CONFIRMED** verbatim (`aspace=AddrSpace.SYS, snooped=True,
uncached=True`) and the port's `pt_*` trace rows are the gated version of that call's page-table
loop.

---

## 2. STAGE TABLE

| stage | what it is | gate |
|---|---|---|
| 1 | **Fields and signatures, by name and in order** — `MV`, `Pa`, `Vmap`, `Bump`, `Csz`, `Pte`, `Space`; the three `__init__` tuples; twelve `inspect.signature` rows; `dataclasses.fields(VirtMapping)` | `mmio_init_fields`, `bump_init_fields`, `tlsf_init_fields`, `tlsf_blocks_tuple`, `tlsf_blocks_comment`, `vm_fields`, `vm_defaults`, `vm_pa_ann`, `sig_*` (13) |
| 2 | **Two-way tables** — `struct.calcsize` both directions (23 fmts, first-match reverse, absent sizes), `AddrSpace` both directions, TLSF `lv1`/`lv2`/bucket/`lv2_shift` over 20 sizes | `calcsizes_*`, `calcsize_rev_*`, `calcsize_absent_*`, `aspace_*`, `tlsf_lv*_*, `tlsf_bucket_*` |
| 3 | **Constants** — page, block sizes, `va_allocator` window as `H.I64` pairs, `1 << 63` sentinel, `512`/1 MiB PTABLE unit | `PAGE_4K`, `TLSF_DEF_*`, `va_alloc_*`, `lowbit_zero*`, `mm_ptable_div*`, `mm_ptable_round_*` |
| 4 | **Offset / layout arithmetic** — `pte_covers` and `pte_cnt` with both `[::-1]`, `lvl_msb`, the ladder identity, `bump` rounding, `valloc`'s range ladder, `valloc_align`, `palloc` rounding, `_frag_size` | `pte_*` (9 fixtures × 3 widths), `bump_over_*`, `valloc_*`, `palloc_round_*`, `frag_*` (13 × 6) |
| 5 | **Policy as ordered traces** — `to_mv`→`.cast`, the two page-table assert loops, and their refusals | `mmio_tr_*`, `pt_map_*`, `pt_unmap_*`, `pt_order_*` |
| 6 | **Field readers** — `VirtMapping`'s six fields at its two construction sites and their differing defaults, `paddrs` pair halves read by `:211` and `:279` | `vm_all_*`, `vm_gmmu0_*`, `vm_size_match_*`, `vm_loops_opposite_*` |
| 7 | **Mutation sweep** — 70 mutations, per-`name=value`-line diff | `.agents/slop/memory-mutate.py` |

---

## 3. THE GATE TABLE — every row traced to a CPython run

The oracle is `.agents/slop/memory_oracle.py`. **Every `py=` row is produced by CALLING
CPython**: `M.MMIOInterface(...)`, `M.BumpAllocator(...).alloc(...)`, `M.TLSFAllocator(...).lv1/lv2`,
`struct.calcsize`, `dataclasses.fields`, `inspect.signature`, `inspect.getsource`,
`MemoryManager.__new__(...)._frag_size(...)`, and the two page-table loops run as Python against a
recorder. Nothing is typed. `AddrSpace` comes off the enum object; the `va_allocator` window is
`1 << 44` / `0x200000000000` printed as the `hi:lo` pair `H.i64_text` produces.

| row family | n | CPython call behind it | what breaks it |
|---|---|---|---|
| `*_init_fields`, `tlsf_blocks_*`, `vm_fields`, `vm_pa_ann` | 9 | `inspect.getsource` parse of the four-tuple; `dataclasses.fields` | a swapped field |
| `sig_*` | 13 | `inspect.signature` | a mis-read default (`fmt='B'`, `wrap=True`, `lv2_cnt=16`) |
| `calcsizes_names/sizes`, `calcsize_rev_*`, `calcsize_absent_*` | 37 | `struct.calcsize(f)` for each of 23 fmts | a wrong size; the reverse's *choice* (size 4 is `I`, not `4B`) |
| `mmio_addr_tbl/nbytes_tbl/fmt_tbl/isbyte_tbl`, `mmio_len_*` | 13 | `M.MMIOInterface(a, n, f)` then `len`, `.addr`, `.nbytes`, `.fmt` | a field mix-up; `__len__` floored where the constructor refuses first |
| `mmio_view_*` | 34 | `m.view(off, size, fmt)` over 10 fixtures | a `None` collapsed to 0; offsets not accumulated |
| `mmio_multichar_len/refused`, `mmio_odd_refused_*` | 16 | `M.MMIOInterface(...)` in `try/except ValueError/TypeError` | a format accepted that CPython refuses, and the reverse |
| `aspace_*` | 12 | `list(AddrSpace).index(e)`, `e.value` | PHYS's value vs index alias |
| `bump_seq_*`, `bump_ptr_seq_*`, `bump_seq_n_*` | 12 | eight `BumpAllocator.alloc` calls per state | a wrap that did not reset `ptr`; a refusal that advanced it |
| `bump_over_{,pad_,noround_,ptr_}*` | 144 | `round_up(b.ptr, al) + asz > size` over nine requests × four states | the dropped round (M14, now closed) |
| `bump_pair_*`, `bump_refuse_*`, `bump_wrap*`, `bump_ptr_is_end_*` | 22 | `alloc` / `RuntimeError` | the refusal-vs-wrap pair, gated by the POINTER |
| `pte_*` | 145 | `memory.py:186-187`'s expressions evaluated, narrowed per fixture width | a dropped `[::-1]`; a swapped level |
| `pte64_root_amd/nv`, `pte64_shl_*` | 5 | `(1 << 48)`, `(1 << 52)` | a `U32` truncation of a real device table |
| `pte_barefused_*` | 3 | the `1 << (msb[i+1]-msb[i])` list, `ValueError` caught | the non-monotone refusal |
| `frag_*`, `frag_*_signed`-free | 78 | `_frag_size(va, sz, mc)` plus its four operands | `must_cover`'s polarity; the `va == 0` sentinel |
| `lowbit_*`, `bitlen_*` | 32 | `x & -x`, `x.bit_length()` | `x-2x` instead of `x & ~x+1`; `log2` at 0 |
| `mm_*_{boot_sz,ptable_sz,off_sz,pa_sz,pa_base}_*` | 80 | `memory.py:191-192` evaluated | `reserve_ptable`'s polarity; `//512` before the round |
| `mm_ptable_div*`, `mm_ptable_round_*` | 8 | the same division and `round_up` | the division hidden inside `mm_ptable_sz` |
| `va_alloc_*` | 8 | `1 << 44`, `0x200000000000` as `hi:lo` | the wall a citing file was carrying |
| `valloc_align/round/p2_*`, `valloc_{req,picks,sum,rem}_*` | 54 | `max`, `round_up`, the `:260-270` ladder | `max` vs `min`; the advanced-list walk (M70) |
| `tlsf_{req,sz,bl,round,final,rounds_up}_*` | 42 | the three-step size pipeline | each step's order |
| `mmio_tr_*` | 13 | `to_mv`→`.cast` recorder | a transposed pair; a tag retag (M63, M69) |
| `pt_map_*`, `pt_unmap_*`, `pt_order_*` | 24 | the two `raise`-terminated loops run as Python | a wrong stop polarity; a wrong read order |

**889 rows, 889 compared, 0 disagreements, and no row on either side alone.**

---

## 4. MUTATION TABLE — 70 mutations, 6 blind spots

The harness rewrites a `.mut` copy and diffs **whole `name=value` lines**, not row names.

### Closed by this unit's fixtures (5 of the 7 that were blind when the file was stubbed)

| id | mutation | rows moved |
|---|---|---|
| **M14** | `bump_overflow`: the ROUND is dropped from the overflow test | **5** — closed by adding the ninth request `(1 byte, align 4096)`: from a pointer at 161 the padded test rounds to 4096 and overflows the 4096-byte window, the unpadded one compares 162 and does not. Every earlier fixture had an aligned pointer or an alignment of 1, so padding was 0 and the two rows agreed. It moves `bump_over_plain_8` and `bump_over_aligned_8` plus three `aligned` sequence rows, because on `aligned` (an 8192-byte window) the ninth request also fits where the eighth does not. |
| **M63** | `MMIO_INDEX` tag 3 → 2 (collides with `TO_MV_CAST`) | 1 — closed by the trace gate |
| **M64** | `PT_SET_ENTRY` tag 9 → 8 (collides with `PT_SUPPORTS_HUGE`) | **still 0** — see blind spots |
| **M69** | `PT_SET_ENTRY` tag 9 → **4** (collides with `PT_VALID`, which IS emitted) | 6 — *added by this unit* to show the difference |
| **M70** | `ladder_pick`: FIRST match at or below the remainder becomes LAST | 18 — *added by this unit*; it is the mutation of the bug the diff found |

### Blind spots, with the reason each one is a blind spot

| id | mutation | rows | why it moves nothing | could it be closed? |
|---|---|---|---|---|
| **M09** | `MMIO` field order `mv,addr,nbytes,fmt` → `addr,nbytes,mv,fmt` | 0 | **Structural.** Every reader is a positional `case Mv{...}` destructure, so swapping the type declaration *and* all readers is one consistent relabelling. | Only by making the reader order observable from outside — which would mean a row whose value encodes the field order. `mmio_init_fields=mv addr nbytes fmt` **is** that row, and it is diffed against `inspect.getsource`, so the *declaration* is gated; the *readers* are not independently gated. |
| **M12** | `Pa` pair order `paddr,psize` → `psize,paddr` | 0 | Same, and weaker: M57/M58 (`vm_psize_sum` reading `p[0]`, `vm_free_paddrs` reading `p[1]`) already pin which half each of the two readers uses — 4 and 3 rows respectively. The *declaration* order is unpinned. | A `pa_fields` row like `mmio_init_fields`, read off the annotation. |
| **M13** | `Vmap` field order `va_addr,size,…` → `size,va_addr,…` | 0 | Same as M09. `vm_fields=va_addr size paddrs aspace uncached snooped` is gated by `dataclasses.fields`; the readers are not. | Same as M09. |
| **M38** | `pte_ladder`: the invariant is dropped (always true) | 0 | **A THEOREM.** For every `va_shifts` CPython accepts the ladder identity `cnt[lv]*cover[lv] == cover[lv-1]` holds by construction, so "check it" and "always true" are the same function on the whole fixture set. | Only by a `va_shifts` CPython REFUSES — and it does: a non-monotone list makes the shift count negative and `1 << negative` raises `ValueError`. **`pte_barefused_12_21_4=1`, `pte_barefused_0_9_4=1`, `pte_barefused_12_21=0` are the rows that make the theorem's boundary checkable**, and they are gated. The theorem is reported, not closed. |
| **M62** | `pte_first_largest`: `first == max` becomes `first >= min` | 0 | **A THEOREM**, same boundary: `covers` is `[1 << x for x in va_shifts][::-1]`, sorted exactly when `va_shifts` is monotone, and non-monotone is refused. 1 row, `pte_first_largest_nz`, and `nz` exists only to make `cnts_raw`'s head predecessor load-bearing (every other fixture has `va_shifts[0] == 0`). | Same as M38. |
| **M64** | `PT_SET_ENTRY` tag 9 → 8 (collides with `PT_SUPPORTS_HUGE`) | 0 | **The trace counts calls BY TAG VALUE, and nothing emits 8.** Both lanes count the same two calls under the shared value, so the collision is unobservable. M69 (retag onto `PT_VALID`, which IS emitted) moves 6 rows. | Only by emitting every tag, which needs a device page table. **Reported.** |

**68 → 70 mutations, 7 → 6 blind spots. No blind spot was closed by adding a row that encodes
the bug.**

---

## 5. THE FFI SEAM SPLIT

**Lane: the trace is the seam.** `Call{k, arg}` / `Tr{calls, next, refused, nth, at}` are
copied from `runtime/support/am/ip.bend` lines 91–275. **No foreign effect is declared**: the seam
is `Tr.emit`, not a `def … -> IO(R)` over two `import "./x.c"`. Every tag is a **literal
`def NAME() -> U32: n`** so it is greppable and retaggable by the mutation harness.

### Emitted here — seven tags, eight seams

| tag | Python line | the call | emitted by |
|---|---|---|---|
| `TO_MV` | `:7` | `to_mv(addr, nbytes)` | `mmio_make` |
| `TO_MV_CAST` | `:7`, `:12` | `.cast(fmt)` | `mmio_make` |
| `MMIO_INDEX` | `:9`, `:10` | `self.mv[k]` / `.tolist()` | declared; counted, not emitted by a ctor |
| `PT_VALID` | `:136,:148,:171,:215,:233` | `pt.valid(i)` | `pt_read_pending`, `pt_unset` |
| `PT_ENTRY` | `:140,:215,:233` | `pt.entry(i)` | `pt_read_mapped`, `pt_unset` |
| `PT_SET_ENTRY` | `:138,:151,:221,:234` | `pt.set_entry(i, p, …)` | `pt_set_of` |

### Declared, NOT emitted — eight tags, and this is the list of what this port does not gate

`PT_IS_PAGE` (`:140,:171`), `PT_ADDRESS` (`:141`), `PT_SUPPORTS_HUGE` (`:169`), `PT_T`
(`:141,:193`), `MM_PALLOC` (`:138,:149,:193`), `MM_PFREE` (`:149,:267,:288`), `VRAM_ZERO`
(`:285`), `MM_DEBUG_PRINT` (`:209,:228`). They are real methods on `PageTable`/`MemoryManager`
and on the device, so they belong to the vocabulary — and M64 is the fact that a declared tag
nothing emits cannot be gated.

### Not a seam

`getenv("GMMU", 1)` (`:248,:275`) is a **Bool parameter** on `valloc`/`vfree`, and
`on_range_mapped()` (`:224,:236`) is a `pass` hook — both are in the vocabulary as
`ON_RANGE_MAPPED` but neither is a call this port makes.

### The page-table loops are the one place the ORDER is the claim

`map_range:214-215` reads `valid` FIRST and `entry` only on failure (Python evaluates an `assert`
message lazily), so a mapped entry is `[PT_VALID, PT_ENTRY]` and a pending one `[PT_VALID]`.
`unmap_range:232-234` is the mirror with the **opposite stop polarity**: a valid entry reads
`PT_VALID` and *records* `PT_SET_ENTRY` and continues; a pending one reads `PT_VALID` and halts.
The oracle runs both loops **as Python against a recorder**, so the order and the stopping point
come from the interpreter and not from a transcription.

---

## 6. WHAT THE PORT GOT WRONG, AND WHAT CAUGHT IT

Eleven real defects, every one of them found by the CPython diff and none of them by reading:

| defect | caught by |
|---|---|
| `va_allocator` size/base hi words: 256/8192 instead of **4096/8192** | `va_alloc_size_hi/lo`, `va_alloc_base_hi/lo` |
| `U32.shln` / `add` / `sub` **WRAP**; the port treated them as saturating | `lv2_shift` needed an explicit `max(0, …)`; `valloc_rem` |
| `frag_lowbit` was `x - 2x`; it is **`x & (~x + 1)`** | all 78 `frag_*` rows |
| `frag_sz_max` is `1 << (bl - 1)`, not `1 << bl - 1` | `frag_*_sz_max` |
| `lvl_msb_len` is `len + 1` | `pte_msb_len_*` (M67) |
| `VRAM_ODD` is `0x40000001`, not `0x4000001` | `mm_pa_sz_vodd_*` |
| `valloc_align` is **`max`** of the page and `next_pow2`, not `min` | `valloc_align_64k` |
| `lv2_shift` needs a `max(0, …)` clamp (`U32.sub` wraps) | `tlsf_lv2_shift_*` |
| `List.append(a,A,xs,ys)` is `xs ++ ys`, so a "reverse" built on it is the **identity** | `pte_covers_*` vs `pte_covers_raw_*` disagreeing with each other |
| `first_of` needed a `seen` flag; search folds must keep the **FIRST** match | `pte_root_cnt_*` (M61, 18 rows) |
| **`valloc`'s range walk advanced the segment list past the pick**, making it a last-match walk that can never take the same segment twice: 8 MiB came out as `2 MiB × 8`, sum `16777216`, remainder `-8388608 mod 2^32` where CPython says `2 MiB × 4`, sum `8388608`, remainder 0 | `valloc_picks_8388608`, `valloc_sum_*`, `valloc_rem_*` |

The last one is the reason the whole exercise exists: **nothing in `memory.py` hints at it.**
`while self.palloc_ranges[nxt_range][0] > rem_size: nxt_range += 1` looks like a cursor into a
shrinking list, and the re-walking-the-head form — which is what it is — reads as a quadratic
loop nobody would write.

---

## 7. THE `U32` WALL, AND HOW THE THREE-WIDTH SPLIT PAYS FOR ITSELF

`pte_covers[0]` is `1 << va_shifts[-1]`: `2^48` for AMD, `2^52` for NV, `2^45` for `tall`,
`2^33` for `root1`'s root *entry count*. A `U32` shift wraps to 0. So:

* the six U32-safe fixtures print the full row family (`t_pte1`);
* `tall` and `amd`/`nv` print the entry counts but no covers and no ladder (`t_pte1n`) — the
  ladder **multiplies** the two tables, so it needs both to fit even where each separately
  would;
* `root1` prints the shape only (`t_pte1m`);
* the two real device root covers are `H.I64` pairs: `pte64_root_amd=65536:0` sitting next to
  `pte64_shl_48=0`.

**Three widths, three `IO` defs, because `Bool.pick` over two row blocks prints both.** The
count of narrow variants is the measure of how far the Python's integers are from the port's.

## 8. ROW SHAPE RULES THIS UNIT SETTLED

* **A per-fixture row per field is a list row waiting to happen.** 23
  `mmio_multichar_refused_<FMT>` rows said one thing; two list rows say it once, force both lanes
  onto the same fixture ORDER, and make a mis-typed fixture a different list. Same for the four
  `mmio_*_tbl` field columns, which replace 36 per-field rows.
* **A row name carries its own input.** `valloc_req_8388608`, not `valloc_req_0` — a loop index
  makes a mis-keyed fixture invisible, because both lanes index the same way.
* **Two rows that are the same number twice are not a gate.** `frag_*_signed` and
  `frag_va_div_*_exact` were deleted: `-10 % 2**32 == 4294967286`, so the `U32` row already
  carries both readings, and a differ that matches whole lines would then have a row no mutation
  can move.
* **A row that cannot be computed in the lane is ABSENT, not fake.** `va_alloc_off_*` (the
  `va_allocator`'s own allocation offsets) were literals on the Bend side because
  `TLSFAllocator.alloc` drives the free list and this port has the bucket arithmetic, not the
  walk. Deleted from both sides. **The TLSF free-list walk is NOT ported** — `lv1`, `lv2`, the
  bucket key, `lv2_shift`, the size pipeline and the storage length are; `alloc`/`free` are not.
  That is the one place this port stops short of `memory.py`, and it is the one thing a reader
  of this file should know.