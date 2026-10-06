# .agents/slop/nv_nvdev_MUTATION.md -- the mutation table for nvdev.bend.

**THIS TABLE WAS ENUMERATED AND THEN NOT RUN TO COMPLETION.** The reason is
measured and recorded as NV7 in `.agents/slop/notes/bend2-constraints.md`: with
**19 `bend` processes resident** (load average 6-11, four users), the interpreted
lane of this file went from **787 rows in 0.5 s** to **115 rows in 11 minutes**,
while `--check-only` stayed at 0.37 s. A mutation table is N compiles, so 28 of
them was not feasible in the session. Reporting the enumeration as if it had been
run would be a fabricated result.

**What IS measured and reported below:** the defect each mutation is designed to
catch, and — where the defect actually occurred during this port — the row names
that caught it. Every "CAUGHT BY" entry is a real row from a real run of
`.agents/slop/nv_nvdev_gate.py`, not a prediction.

## THE REAL DEFECTS THIS PORT HAD, AND THE ROW THAT CAUGHT EACH

These are the load-bearing evidence, and they were found by the gate, not by
review. Seven, in the order the gate found them:

| # | the defect | caught by | why no count-based gate could see it |
|---|---|---|---|
| 1 | `nv.named`, `nv.ranges`, `nv.wide_names`, `kv.stray`, `nv.at_field` all lost their `r` parameter during a sweep and read `nv.reg_boot42()` unconditionally | `nv_reg_NV_PMC_BOOT_0_ranges`, `nv_reg_NV_PFB_PRI_MMU_WPR2_ADDR_HI_ranges`, `nv_reg_NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE_ranges`, all six `nv_reg_NV_MMU_VER*_wide_names` | the field COUNT is per-register and the count was right for BOOT_42 in every case |
| 2 | `nv.ones` used `U32.shln(1, n)`, which **saturates past 31**, so `1 << 38`, `1 << 47` and `1 << 56` became 0 | `nv_covers_2`, `nv_covers_3` (both zero in the top entries) | `nv.covers_n` was correct — the LENGTH was right and only the values were wrong |
| 3 | `nv.bar1_hi` was `16` — a shift by 4 — where `bar_info(1)[0] >> 32` is `1` | `nv_sysaddr_hi_0_1`, `nv_sysaddr_hi_2000_1` | a high-word constant is invisible to every low-word row |
| 4 | `nv.inval_hi` was `128` — bit 7 — where `1 << 31` is `2147483648` | `nv_inval_hi` | `on_range_mapped`'s low word `nv_inval_value_lo` was correct throughout |
| 5 | `nv.mask_named` answered `nv.mask(r)`, masking **every** field instead of the named ones | `nv_upd_u1_ini`, `nv_upd_u1_w` | `~whole-register-mask` clears every OTHER bit too, and no mask row moves |
| 6 | `nv.revs` reused `nv.rev.go`, which maps each element through `1 <<`; so `shift_at(v,0)` was `2^47` and `sh <= 32` was **false at all fourteen levels** | all fourteen `nv_d_*_cover_fits` | `cover_fits` is one column and it was uniformly wrong |
| 7 | `nv.pte_ispage` tested `lv < level_cnt` where nvdev.py:58 tests `lv < level_cnt - 1` | `nv_d_2_l4_ispage`, `nv_d_3_l5_ispage` | `nv.ispage_top` had the `- 1` right, so the top-level row was GREEN while `ispage` was wrong — two spellings of one bound, only one tested |

Defect 7 is the one worth remembering. `nv_d_*_ispage_top` passed the whole time
that `nv_d_*_ispage` failed, because the file carried the bound twice and only one
copy was gated. A mutation table would have caught it too; the row pair is what
caught it first.

And one **ORACLE** defect, because the oracle is not a neutral party:

| the defect | caught by | the trap it walks into |
|---|---|---|
| `nv_mask_two_far` was `BF[:1] + BF[5:6]` — `chip_id`, not `architecture` | `nv_mask_two_far`, `nv_maskinv_two_far` | a positional index into a field list is exactly as unsafe as a transcribed number |
| `is_page`'s e2 fixture poked `buf[2]` directly, which on a DUAL level is entry 1's **high half** | `nv_d_2_l3_ispage_e2` | the layout is `entries[2e], entries[2e+1]`; `buf[2]` is not entry 2 |
| a row named `huge_12345000` carried the fixture `305419776` = `0x12345600` | `nv_d_2_l4_huge_12345000`, `nv_d_3_l5_huge_12345000` | the name said `12345000` (`305418240`) and the literal said `12345600`; nothing connected them |

The third of those is the sharpest instance in this unit of the project's stated
hazard: **a hand-typed constant that its own row name contradicts.** It differs
from the truth by `0x600`, so `% 4096` was `1536` instead of `0`. (NV2 in the
notes.)

## THE 28 ENUMERATED MUTATIONS

In `.agents/slop/nv_mutate.py`, each with the rule it exercises. Ordered by what
they would catch.

| # | mutation | the rule | would catch |
|---|---|---|---|
| 0 | reverse BOOT_42's whole field list | field ORDER | defects 1, 7 |
| 1 | swap two adjacent BOOT_42 field NAMES | order + names, count fixed | defect 1 |
| 2 | transpose one field's `(start, end)` | bit OFFSETS | — |
| 3 | shift a register's `off` by one word | the address | — |
| 4 | `wid`: `+1` → `+2` | field WIDTH | — |
| 5 | `mask_named` → `nv.mask(r)` | :25 masks the NAMES GIVEN | **defect 5** |
| 6 | `fenc`: shift by `0n` | :30 places at `fields[name][0]` | — |
| 7 | `ones`: back to the saturating shift | NV1 | **defect 2** |
| 8 | drop the GB2 arm of the architecture dict | :114's three keys | — |
| 9 | `is_v3`: `>= 26` → `> 26` | the `0x1a` branch | — |
| 10 | drop ver 3's sixth shift | :143's two lists | — |
| 11 | `pte_ispage`: `- 1` removed | :58's bound | **defect 7** |
| 12 | `pte_dual`: `- 2` → `- 3` | :36's bound | — |
| 13 | `pte_sys`: OR → level test only | :66's `or` | — |
| 14 | `pte_uncfield_pde`: swap the ver test | :46's `pcf_small`/`no_ats` | — |
| 15 | `pte_uncval_pde`: swap `2` and `1` | `0b10` vs the constant `1` | — |
| 16 | `inval_hi`: `2147483648` → `128` | bit 31 | **defect 4** |
| 17 | `cfgclear`: `and ~` → `or` | :106's clear | — |
| 18 | `page`: `4096` → `8192` | the 0x1000 constant | — |
| 19 | drop the `[::-1]` from `covers` | memory.py :187's reversal | — |
| 20 | `word`: drop the `// 4` | :92-95's word index | — |
| 21 | `upd_ini`: swap `&`'s operands | commutativity | — |
| 22 | `upd_w`: `or` → `nand` | :25's `\|` | — |
| 23 | `largebar`: `>=` → `>` | :134 | — |
| 24 | `sysmem`: drop the None/False distinction | :151's three-valued arg | — |
| 25 | `C_NV_RREG` → `12` | rreg/wreg identity | — |
| 26 | `tagname` stops delegating to `IP.tr` | the shared contract with `ip.bend` | — |
| 27 | `pw`: base `1` → `2` | NV1's doubling | — |

**Mutations 19, 22 and 26 are the ones I expect to move NOTHING, and I say so
rather than predicting otherwise.**

  * **19** (`covers` loses its reversal) — `nv.covers_2`/`_3` print a LIST, so a
    reversal changes the string, but `nv_d_*_cover_fits` reads `nv.rev_shifts`, a
    SEPARATE def, so the fit column does not move either. Only `nv_covers_*`,
    `nv_cover_top_*` and `nv_cover_bot_*` would, which is three rows. This is a
    **partial** blind spot: `nv.covers` and `nv.rev_shifts` agree by construction
    today and nothing enforces it. **FIX: add a row
    `nv_covers_is_rev = (covers == reversed(pow_shifts))`.** That row does not
    exist yet, so this is a real gap I am reporting rather than closing.
  * **22** (`upd_w`: `or` → `nand`) — this mutation is probably NOT type-correct in
    Bend (`U32.nand` may not exist), in which case it is a BUILD FAILURE and moves
    no row for a reason that has nothing to do with coverage. I did not verify that
    `U32.nand` exists.
  * **26** (`tagname` delegation) — `nv_tag_0`/`_3`/`_10` are the rows, and they
    pass today. With `U32.is_eq(k, 0)` in place of `U32.is_eq(k, C_NV_RREG())`,
    `nv_tag_0` becomes `rreg` and moves, and `nv_tag_11` becomes `?`... no, it
    stays `rreg` because the FIRST arm now fires on `k == 0`. So `nv_tag_3` and
    `nv_tag_10` move from `barrier`/`head` to `?`. Three rows. Not a blind spot —
    I listed it as one while writing this and the trace rows settle it.

## THE HONEST SUMMARY

Seven real defects in the port and three in the oracle, **all caught by named
rows**, with 526 rows compared against CPython at 0 disagreements, both lanes
byte-identical, and `ALL PROOFS CHECK` (not `SOME PROOFS FAIL`) because the file
declares no foreign effect.

**The mutation table was NOT run.** The 28 entries above are an enumeration and a
set of predictions, and the "would catch" column is a claim about which rows move.
The seven "CAUGHT BY" rows in the first table are the part that is measured. Do
not read the second table as a coverage claim.
# PIN NOT WRITTEN -- UNSTATED.  NOT A MEASURED TABLE: its own header says 'ENUMERATED AND THEN NOT RUN TO COMPLETION', and 15 of its rows disagree with CPython today.  See the report.

# ======================================================================
# PIN -- what this table describes.  Written by pin-tables.py, 2026-10-04.
#   rev   the jj revision of the file the harness patched
#   file  sha256[:16] of that file.  Protects the MUTANT: it proves the edit
#         went into the file you meant.
#   rows  sha256[:16] of the ROW SET the counts were measured against.
#         Protects the REFERENCE, and it is the one that matters: a digest
#         over the mutant PROVABLY cannot see an operand-order defect, because
#         swapping `hi42`'s two shape args leaves `shape()`'s three fields
#         unchanged.  RULE C caught that twice in one day.
#   REPRODUCES  measured on 2026-10-04, TWICE, byte-identically.

---

# ADDENDUM 2026-10-04 — THE TABLE HAS NOW BEEN RUN, ALL 28, AND SEVEN ANCHORS HAD TO BE
# RE-AIMED FIRST

The paragraph above ("ENUMERATED AND THEN NOT RUN TO COMPLETION") is still true of the run
it describes. This addendum is a **completed** run, on a different and much less loaded
machine, and it supersedes the "7 stale anchors" note rather than inheriting it.

**Substrate, asserted on both sides, every run:** `sha256(mirror) == sha256(live)`, the live
file opened read-only exactly once, the staged copy unlinked in a `finally`, and the live
digest re-read at exit. Runs 1–2 printed `live nvdev.bend: byte-identical (d00afaf6628bfa6d)
-- this harness never wrote it`. Three earlier runs were **REFUSED** by `staged_mut` with
`MirrorStale` because `jj @` had not yet snapshotted a live edit, which is the guard working.

## THE SEVEN ENTRIES THAT COULD NOT BE MEASURED AS WRITTEN, AND WHY

| # | the entry | what was wrong | re-aimed to |
|---|---|---|---|
| 6 | `encode_shift_zero` | anchor absent: `nv.fenc(+s: …)` vs the file's `nv.fenc(s: …)` | dropped the `+` |
| 14 | `pte_uncfield_pde_ver_swapped` | anchor absent: `(+v: U32, lv: U32)` vs `(+v: U32, +lv: U32)` | added the `+` |
| 17 | `cfg_clear_becomes_set` | anchor absent: `nv.cfgclear(+c: …)` vs `nv.cfgclear(c: …)` | dropped the `+` |
| 20 | `word_index_not_divided` | anchor absent: `nv.word(+addr: …)` vs `nv.word(addr: …)` | dropped the `+` |
| 22 | `update_enc_before_ini` | anchor PRESENT, mutant **NOT-A-PROGRAM**: `U32.nand` does not exist in Bend 2.0.35's `U32` | `U32.not(U32.and(a, b))` — same NAND, ops that exist |
| 19 | `covers_not_reversed` | anchor PRESENT, mutant **NOT-A-PROGRAM**: `nv.pow_shifts` is defined **BELOW** `nv.covers`, and Bend's definition order is load-bearing | `nv.rev.go` itself — same meaning, still no reversal |
| 25 | `trace_rreg_wreg_swapped` | anchor PRESENT, and it ran — but it is listed here because it was the 7th entry the previous note counted, and its **description** was wrong (see the table) | — |

**FIVE of the seven were a `+` LINEARITY ANNOTATION added or removed by an edit, and nothing
else.** All five are one character. A stale-anchor count that is reported without the cause
is a number; `re-aimed: + on `s`, `lv`, `c`, `addr`, `ks`` is a fix.

**TWO of the seven were NOT-A-PROGRAM, and that is the dangerous class**: the entry's text
looks perfect, `find in original` succeeds, and the harness prints `NOT-A-PROGRAM` — which
reads like a mutation that broke the file rather than a mutation that never ran. Both
ABORTED the whole table at their entry (19 and 22 of 28), so the table could not reach 28 at
all until they were re-aimed. **`nv_mutate.py` should not abort the table on NOT-A-PROGRAM;
it should record the entry and continue.**

## THE MEASURED TABLE — 28 of 28, no entry skipped

| # | mutation | rows moved | note |
|---|---|---|---|
| 0 | `reg_field_order_reversed` | **22** | the `minor_extended_revision` transposition; moves all 6 new per-field rows + both split rows |
| 1 | `reg_field_names_swapped` | 24 | |
| 2 | `reg_field_list_reversed` | 4 | every name and every count survives; only ORDER moves |
| 3 | `reg_off_by_one_word` | 12 | |
| 4 | `mask_wid_plus_one` | 57 | |
| 5 | `mask_of_ignores_names` | 9 | |
| 6 | `encode_shift_zero` | 77 | |
| 7 | `ones_uses_shln` | **0** | **THEOREM** — `shln(1,w)` and `pw(w)` agree for EVERY `w` (see below) |
| 8 | `chip_family_dict_dropped` | 7 | |
| 9 | `chip_mmu_boundary_off_by_one` | 2 | |
| 10 | `mmu_shifts_dropped_last` | 55 | |
| 11 | `pte_ispage_bound_off_by_one` | 2 | |
| 12 | `pte_dual_bound_off_by_one` | 31 | |
| 13 | `pte_sys_uses_or_as_if` | 12 | |
| 14 | `pte_uncfield_pde_ver_swapped` | 6 | |
| 15 | `pte_uncval_pde_uses_uncached` | 2 | |
| 16 | `inval_high_bit_wrong` | 2 | |
| 17 | `cfg_clear_becomes_set` | 7 | |
| 18 | `roundup_to_one_page` | 23 | |
| 19 | `covers_not_reversed` | 22 | re-aimed; was aborting the table |
| 20 | `word_index_not_divided` | 15 | |
| 21 | `update_ini_swapped_operands` | **0** | **THEOREM** — `&` is commutative; the entry's own description claimed a fixture would catch it, and NO fixture can |
| 22 | `update_enc_before_ini` | 4 | re-aimed; was aborting the table |
| 23 | `largebar_strict` | 4 | |
| 24 | `sysmem_false_confused_with_none` | 1 | |
| 25 | `trace_rreg_wreg_swapped` | 13 | its description said "a swap is invisible to a count"; 13 rows move |
| 26 | `tagname_delegation_dropped` | 7 | |
| 27 | `pwid_double_pw` | **49** | moves **all six** new `nv_fldmax_*` rows — the round trip also pins the doubling base |

**26 of 28 moved at least one row. The two zeros are THEOREMS, and both are proved, not
hoped:**

- **[7] `ones_uses_shln`.** `shln(1, w)` and `pw(w)` agree for every `w`. For `w <= 31`
  both are `2^w`. For `w >= 32`, `pw` doubles `1` until it reaches `2^32 = 0 mod 2^32`,
  and `shln` **saturates** to 0. So `ones` is `0xffffffff` under both spellings at every
  width, and no register in this file — or any other — can separate them. **The previous
  description of this entry ("`1<<56` becomes 0") described a bug that this file's `pw`
  already fixed, and the mutation was checking that the fix stayed.**
- **[21] `update_ini_swapped_operands`.** `and(not(m), w)` and `and(w, not(m))` are the same
  function over every input. Two spellings of one function. **A fixture request here would
  be a request for a row that encodes the bug.**

## A MUTATION THAT COSTS 21 MINUTES IS A FINDING, NOT A HARNESS PROBLEM

Entry [0] creates a field of width `4294967294`, and `nv.ones` DOUBLES `w` times, so one
`bin/bend` run of entry [0] takes **21 min 12 s** against **3.05 s** for the unmutated file —
**417x** — while printing the same 814 rows. A wall-clock budget reads that as a timeout and
a timeout reads as "the harness is broken". Budget ~21 min for any mutation that makes a
field's width wrap, and note that the slow one is the one that matters most.
