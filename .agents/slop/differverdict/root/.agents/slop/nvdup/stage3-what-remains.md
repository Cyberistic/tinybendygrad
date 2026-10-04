# STAGE 3 — THE 21 THAT REMAIN, EVERY ONE WITH `file:line`

**NOTHING here was edited.**  Every producer below is either a do-not-touch `.bend` or an oracle
this unit does not own.  The census is re-run against the current lane texts, so these numbers
are post-fix and not inherited.

```
DENOMINATOR: 10 of 78 lane texts carry at least one duplicate name under the WRITER'S OWN boundary
rows the writer emitted: 22766   lines the shipped reader ACCEPTS: 22970
distinct names the producer printed: 22713   distinct keys rows() produces: 22867
DUPLICATE NAMES: 21 over 42 rows, costing 21 measurements
the reader's OWN loss: accepted 22970 - keys 22867 = 103
  attributed to: 82 continuation + 0 `=`-in-a-name + 21 duplicate = 103   RECONCILES
```

`48 -> 21`, and **all 27 of the reduction are on one lane's oracle side.**

## 1. THE TABLE

| lane text | rows | distinct | dup names | LOST | owner of the fix |
|---|---|---|---|---|---|
| `runtime/ops_nv.bend` PORT | 611 | 600 | **11** | 11 | `tinybendygrad/runtime/ops_nv.bend` — **DO NOT TOUCH** |
| `runtime/support/hcq2.bend` ORACLE | 165 | 163 | 2 | 2 | `.agents/slop/hcq2-oracle.py` — not this unit's |
| `renderer/llvmir.bend` PORT | 471 | 470 | 1 | 1 | producer is `llvmir-oracle.py:866` — not this unit's |
| `renderer/llvmir.bend` ORACLE | 471 | 470 | 1 | 1 | `.agents/slop/llvmir-oracle.py:866` — not this unit's |
| `renderer/tc_ptx.bend` PORT | 334 | 333 | 1 | 1 | producer is `tcptx-oracle.py:394` — not this unit's |
| `renderer/tc_ptx.bend` ORACLE | 334 | 333 | 1 | 1 | `.agents/slop/tcptx-oracle.py:394` — not this unit's |
| `uop/fold.bend` PORT | 241 | 240 | 1 | 1 | producer is `mm-lift-gate.py:31` — not this unit's |
| `uop/fold.bend` ORACLE | 131 | 130 | 1 | 1 | `.agents/slop/mm-lift-gate.py:31` — not this unit's |
| `viz/serve.bend` PORT | 175 | 174 | 1 | 1 | producer is `vz/viz_oracle.py:79-80` — not this unit's |
| `viz/serve.bend` ORACLE | 175 | 174 | 1 | 1 | `.agents/slop/vz/viz_oracle.py:79-80` — not this unit's |
| **10 texts** | | | **21** | **21** | |

## 2. THE BRIEF'S LEAD, ANSWERED BY MEASUREMENT

> "for `ops_nv` in particular, the 27/11 asymmetry is the lead: fix the oracle side and see
> whether the port side's 11 are the same rows seen from the other end."

**They are not. The two sets are DISJOINT.**

```
port dup names:    11      oracle dup names:    27
INTERSECTION port & oracle dup names: []
port-only: 11   oracle-only: 27      shared names overall: 543
```

And they are not even the same *families*:

| port's 11 | oracle's 27 |
|---|---|
| `nv_iface_count`, `nv_encode_names` — a re-print at the file's tail | `nv_errstr_*` ×5, `nv_iowr_*` ×9 — two fixture tuples with the same 9 names |
| `nv_slmtot_*` ×7 — two byte-identical blocks | `nv_paccess_*` ×3, `nv_reloc_*` ×6 |
| `nv_pc_id_after_hit` — **two different fixtures**, one name | `nv_launch_ok_*` ×2 — two different fixtures, one name |
| | `nv_bpt_1_48428`, `nv_copy_nsteps_4294967295` |

**So the asymmetry is not one defect seen from two ends; it is 38 disjoint names, and fixing
either side un-gates nothing on the other.**  The brief's "symmetric" label belongs to the OTHER
four families, and for two of those it has the direction backwards (§3).

## 3. THE PORT'S 11, WITH `file:line`

`sha256(tinybendygrad/runtime/ops_nv.bend) = 24497e96ddebc56c802bc8ed9fd36c998c794d066e5ce7b3575cb0f42272062c`,
measured and **reported before any edit, and none was made** — this file is DO NOT TOUCH.
`.agents/slop/nvdup/nvdev.bend` `sha256 = d00afaf6628bfa6dc0cd9178fe52cff99267689345310ecb2bb53866e712e4f7`
and **none of these eleven producers lives there**, so the one `.bend` this unit was cleared to
touch was not needed.

| name(s) | site A | site B | shape |
|---|---|---|---|
| `nv_iface_count`, `nv_encode_names` | `:1687`, `:1688` | `:3857`, `:3858` | identical calls, re-printed at the tail of `main` |
| `nv_slmtot_{0,32,1024,4096,1024}_*` (5) | `:3608-3612` | `:3648-3652` | **two byte-identical 5-row blocks** |
| `nv_slmtot_1_48428` | `:3613` | `:3642` | same call, twice |
| `nv_slmtot_1_48428_hi` | `:3625` via **`srow`** | `:3643` via **`i64row`** | **the only one emitted through two different row-builders** |
| `nv_slm_cmd` | `:3634` `lrow(... wstream(dev.slm_cmd(...)))` | `:3655` `lrow(... wstream(a2))` | same call, bound two ways |
| `nv_pc_id_after_hit` | `:3464` `pc.new_id(pc_one(a, K2()))` | `:3472` `pc.new_id(b2)` | **TWO FIXTURES, ONE NAME** — the `nv_launch_ok_*` shape |

## 4. THE OTHER FOUR FAMILIES ARE ALL **ONE LINE**, AND TWO OF THEM HAVE THE DIRECTION BACKWARDS

`DUP-1` classified these as "two emission sites for one row family".  **Every one is a single
line whose fixture list names the same key twice** — the same shape as the
`nv_copy_nsteps_4294967295` fix this unit did make:

| lane | the ONE line | the repeated key |
|---|---|---|
| `fold` | `.agents/slop/mm-lift-gate.py:31` | `("sub","SUB",[(3,4),(-3,4),(-3,-4),(3,-4),**(-3, 4)**,(0,0),(5,5),(4,5)])` |
| `tc_ptx` | `.agents/slop/tcptx-oracle.py:394` | `lines = [..., "ret;", ..., "ret;"]` |
| `llvmir` | `.agents/slop/llvmir-oracle.py:865-866` | `for cnt,d,ptr in ((1,f32,True),(4,f32,False),(4,f32,True),**(1,f32,True)**,(8,f64,False),(2,bf16,True))` |
| `viz` | `.agents/slop/vz/viz_oracle.py:79-80` | `[..., "GPU Memory", ..., **"GPU Memory "**]` — **TRAILING SPACE** |

**"Symmetric" has the direction backwards on `llvmir` and `tc_ptx`.**  The port lines are
**generated from** the oracle's fixture, so the oracle is upstream and the port inherits it:

```
tinybendygrad/renderer/llvmir.bend:981   r_ltn("lt 1 ptr f32", ...) x2 on ONE line
.agents/slop/llvmir-oracle.py:866        (1, dtypes.f32, True) is in the tuple TWICE

tinybendygrad/renderer/tc_ptx.bend:878   r_fmt1("ret;", ...) x2 on ONE line
.agents/slop/tcptx-oracle.py:394         "ret;" is in the list literal TWICE
```

`dup/stage2-classify.md:86-88` concluded "the duplication is in the PORT and the oracle inherits
it".  **The oracle's fixture list generates the port's line, so it is the other way round**, and
on these two the oracle alone is the whole fix.  `llvmir.bend:66` already says so in its own
comment: "`lt 1 ptr f32` IS PRINTED TWICE, ON BOTH SIDES, AND IS NOT FIXED HERE."

`fold` is the same relationship: `mm-lift-gate.py:207` builds the PORT's `lf_row("sub_int32_-3_4",
…)` source line out of the `:31` fixture, so `mm-lift-gate.py:31` is the whole fix there too.

## 5. `viz` IS NOT THIS SHAPE, AND IT IS THE ONE THAT NEEDS A DECISION

`vz/viz_oracle.py:79-80` holds **both** `"GPU Memory"` and `"GPU Memory "` — the second with a
trailing space, and that space is the **only** thing distinguishing two measurements that differ:

```
dev_sort.GPU Memory=true/100/GPU/GPU Memory        <- the same key before the sort toggle
dev_sort.GPU Memory =false/100/GPU/GPU Memory      <- and after, with a SPACE before the '='
```

Under `rebase-gate.py:row()`'s first-`=` cut the second name is `dev_sort.GPU Memory ` and the
first is `dev_sort.GPU Memory`, and **`row()` `.strip()`s the head**, so both land on one key and
the sort-toggle measurement is unreachable.  **A trailing space in a producer's fixture list is a
row name the reader cannot address.**  Whoever owns it decides which of two things is true —
either the space is a typo (delete the element) or it is load-bearing (then `.strip()` in
`row()` is the defect and the reader changes).  **This one is not a mechanical deletion**, and it
is the only one of the 21 that is not.

## 6. WHAT IS LEFT IS 21 MEASUREMENTS IN ONE-LINE EDITS, ALL IN FILES THIS UNIT DOES NOT OWN

| if the owners apply | lines deleted | measurements recovered |
|---|---|---|
| `llvmir-oracle.py:866` (1 element) → also un-gates `llvmir.bend:981` | 1 | 2 |
| `tcptx-oracle.py:394` (1 element) → also un-gates `tc_ptx.bend:878` | 1 | 2 |
| `mm-lift-gate.py:31` (1 element) → also un-gates `fold.bend` | 1 | 2 |
| `hcq2-oracle.py` (2 adjacent emissions, oracle-only, no shared name lost) | 2 | 2 |
| `vz/viz_oracle.py:79-80` (**a decision, not a deletion**) | 0–1 | 2 |
| `ops_nv.bend` (4 families, §3) | 9 | 11 |

**`21 = 2 + 2 + 2 + 2 + 2 + 11`**, and **17 of the 21 are one-element deletions in four lines of
`.agents/slop/`** that no `.bend` edit is needed for and that un-gate their symmetric port half
for free.

## 7. WALLS

* `tinybendygrad/runtime/ops_nv.bend` is DO NOT TOUCH (its closure also contains `uop/ops.bend`,
  under single ownership) — the 11 are reported with `sha256` and `file:line` and nothing more.
* `rebase-gate.py` reported `1 of 4 closure file(s) CHANGED WHILE THIS LANE RAN:
  tinybendygrad/helpers.bend` — six units are live, so any count on this lane is a lower bound.
  The dup unit's `tc_ptx` capture answered `RE-PORTED [STARVED]` on the same sweep; this unit's
  `ops_nv` capture needed **one** attempt and printed its closure size (4).
* `grep -c 'lf_sub_int32' tinybendygrad/uop/fold.bend` returns **0** — the name is BUILT
  (`mm-lift-gate.py:206`), so a name grep cannot find the producer of a `fold` row. Use
  `mm-lift-gate.py:206-207`, not the name.