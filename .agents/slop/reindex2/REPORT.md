# REINDEX3 -- THE MEASUREMENT, AND WHY THE LAND IS STILL REFUSED

**STATUS: NOT LANDED. `tinybendygrad/` is byte-identical to `HEAD`; the only edits in
this working copy are the prior unit's `.agents/slop/reindex/` and this unit's
`.agents/slop/reindex2/`.** Every number below was measured on a COPY outside the
repo; the copy's three closure files were verified to `git show HEAD:` blob-for-blob.

Two findings, one of which changes the land's plan.

---

## 1. THE FOUR ORACLES: NOT GREEN. TWO ARE HARD DEAD, ONE IS rc=0 AND DEAD.

**MY FIRST `rc` READING WAS WRONG AND I AM RECORDING WHY.** At ~14:05 I measured all
five files and got `rc=1` on four of them, all with
`TypeError: ParamArg.__init__() got an unexpected keyword argument 'size'`. Re-measured
at ~14:35 against content `git diff` confirms is `HEAD`, two of them are `rc=0`.

The reason is **not** that I misread an exit code -- `rc=$?` was captured with no
pipeline in between in both readings. The reason is that **another unit had the files
in a transiently-broken state and then restored them.** `mtime` proves it:

```
14:13:34  oracles/fold-probe1.py
14:15:36  oracles/mm-survey.py
14:29:05  oracles/fold-mvt-oracle.py
14:29:05  oracles/fold-mvt-rows.py
14:14:53  gates/ptx_render_census-oracle.py
```

**A `rc` CITED WITHOUT ITS TIMESTAMP IS A `rc` THAT CAN CHANGE UNDER YOU.** The prior
unit's four-orphans finding was probably measured the same way and is probably about
the same window.

### THE STATE AT HEAD, RE-MEASURED AT 14:40 (a later unit landed `ORACLES4`/`ORACLEREVIVE`)

| oracle | rc | what it says |
|---|---|---|
| `gates/ptx_render_census-oracle.py` | **0** | **GREEN.** `f14_skips` emits a full 11-row walk |
| `oracles/fold-probe1.py` | **0** | prints `Ops.FLIP present: False` and degrades |
| `oracles/mm-survey.py` | **0** | green |
| `oracles/fold-mvt-oracle.py` | **1** | `TypeError: ParamArg.__init__() got an unexpected keyword argument 'size'` |
| `oracles/fold-mvt-rows.py` | **1** | same |

**CORRECTION TO MY OWN FIRST REPORT.** At 14:20 I recorded
`ptx_render_census-oracle.py` as `rc=0` **but with `f14_skips` DEAD** —
`f14_skips.mod=REFUSE:build:AttributeError`. **THAT WAS TRUE AT 14:20 AND IS FALSE
NOW.** `ORACLES4` (`6304f5b53`) rewrote `F14_skips` to stop minting `UOp(Ops.GROUP, ...)`;
`grep -c 'Ops\.GROUP\|Ops\.FLIP'` on that file is now **1**, and it is a **comment** at
`:199` ("Ops.GROUP WAS the third skip here and UPSTREAM DELETED IT"), verified by an
`ast` walk, not by eye. The fixture now answers:

```
f14_skips.r0=NONE  ...  f14_skips.r10   (11 walk rows)
f14_skips.mod=.version VERSION\n.target TARGET\n... mov.b32 ...\n\tret;\n}
```

**SO THAT ORACLE IS GREEN AND MY EARLIER `DEAD` VERDICT ON IT WAS WRONG.** It is worth
recording HOW it was wrong: I found the `REFUSE:` row, believed the `DEAD` reading, and
wrote it down -- while another unit was mid-fix. **The `REFUSE:` prefix IS the file's own
marker for "this did not measure the thing", and I treated a marker I had not finished
reading as a verdict.** The three checks that would have caught it, and that I did not
run, are: `git log -1 -- <file>` for a newer commit, the `ast` check for comment-vs-code,
and re-running the fixture to see whether its row COUNT matches its neighbours'.

**THE NET IS UNCHANGED IN THE ONE PLACE THAT DECIDES THE LAND:** the two `fold-mvt`
oracles are still `rc=1` at the current HEAD, and they still die on `ParamArg.size`.

### THE TWO THAT ARE STILL DEAD, AND WHY IT IS NOT `Ops.FLIP`

### **THE IMPORTANT PART: TWO ORACLES DIE FOR A REASON THAT IS NOT `Ops.FLIP`**

The prior unit recorded that these construct an op that no longer exists. That is
true and it is **masked by an earlier, independent defect**:

```
tinygrad/uop/ops.py:25  class ParamArg:
  slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile,
  image, buffer          <- NO `size`
oracles/fold-mvt-oracle.py:31  return UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32, size=size))
oracles/fold-mvt-rows.py:27    return UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32, size=size))
```

`fold-mvt-rows.py:13` says the `size=k` was **deliberate**: *"`ParamArg(slot=0, int32,
size=k)`, so `buf(4)` is `g_mv_exp1`'s source"*. So upstream dropped a `ParamArg` field
the fixture was built on, and the two `fold-mvt` oracles have been dead on **that**
since before anyone touched `ops.bend`.

> **SO THE VERIFICATION SET CANNOT BE MADE GREEN BY THE RE-INDEX AT ALL.** Re-indexing
> `tinybendygrad/` cannot make a CPython-side `ParamArg(size=...)` call legal, and
> `tinygrad/` is read-only and byte-identical to upstream. **THE DEAD SET IS DEAD FOR A
> REASON OUTSIDE THE GRANT.** That is a stronger statement than "still dead", and it is
> the reason this unit did not fix them under the grant rather than stopping: dropping a
> deliberate `size=k` from a fixture is a DIFFERENT defect with a DIFFERENT owner, and
> doing it inside the re-index commit is exactly the "one edit, not two" failure.
>
> **AND NOTE `ORACLEREVIVE`'s OWN COMMIT MESSAGE AGREES ABOUT THE SHAPE OF THIS TRAP**
> (`80471aa4c275`, quoted): *"run_fixture SWALLOWED THE AttributeError AS
> `REFUSE:build:AttributeError` -- alongside `REFUSE:KeyError` at :530 -- THE SAME
> SPELLING FAMILY AS THE CENSUS's FOUR DELIBERATE REFUSALS. SO A DELETED SYMBOL MASKED
> ITSELF AS [a refusal]"*. **A `REFUSE:` row is a spelling family, not a verdict, and
> I read one as a verdict -- see the correction above.**

### AND THE BRIEF'S OWN FILE LIST IS PARTLY WRONG

`oracles/fold-probe1.bend` and `oracles/mm-survey*.bend` **DO NOT EXIST.** The only
`.bend` there is `oracles/fold-mvt-e2e.bend`, and it carries **0** references to FLIP
or GROUP (`grep -c 'FLIP\|GROUP' oracles/fold-mvt-e2e.bend` = 0). So of the four groups
the brief names, two were never dead and one was dead for an unrelated reason.

**VERDICT: NOT GREEN -> STOP. NO LAND.**

---

## 2. `multi.bend`'s `t_rej_n` / `t_ops_n`: MEASURED, AND **THERE IS A SIXTH SITE**

The prior unit could not measure these because they need a `bend` run. Taken here, on
a copy, `SPEC=1 DEV=CPU`, under `checks/bounded.py --mb 2048`, reading the verdict
token, never two `bend` concurrent (probed for a clear window before every run).

`multi.bend`'s import closure is exactly four files -- `multi.bend`, `helpers.bend`,
`LAWS/spec.bend`, `uop/ops.bend`, `uop/fold.bend` -- and **`LAWS/spec.bend` carries
ZERO `GROUP`/`FLIP` references**, so `shift_sh.py` (which edits `uop/spec.bend`, a
different file that `multi.bend` does not import) is **NOT in this closure**. The
prior report's "2 + cascade" for `multi.bend` was scoped against the wrong `spec.bend`.

### THE MEASURED TABLE (25 probe rows, instrumented IDENTICALLY on both sides)

```
ROW              BEFORE      AFTER  DELTA        ROW              BEFORE      AFTER  DELTA
r_own_n              19         18      -1        r_te19              19         19      +0
r_ra_n                6          6      +0        r_tl24              --         24      --
r_pm_n               25         24      -1        r_tl25              25        999    +974
r_late_n             26         25      -1        r_full_su            2          2      +0
r_rej_n              21    ->    20      -1        r_full_st            1          1      +0
r_rej_late           21    ->    20      -1        r_first_st          17         16      -1
r_ops_n              57    ->    56      -1        r_first_su          17         16      -1
r_mov_n               6    ->     5      -1        r_first_ad           0          0      +0
r_e19                65         64      -1        r_first_m0  4294967295 4294967295     +0
r_e20                65         65      +0        r_claim_su           2          2      +0
r_l19                76         64     -12        r_claim_st           2          2      +0
r_l20                65         64      -1
r_l23                18         65     +47
r_l24                66         65      -1
r_l25                66 4294967295     (sentinel)
```

**THE THREE NUMBERS THE BRIEF REFUSED TO GUESS, MEASURED: `t_rej_n` 21 -> 20,
`t_rej_late` 21 -> 20, `t_ops_n` 57 -> 56, `t_mov_n` 6 -> 5.**

### **THE FINDING THAT MATTERS MOST: `mu_src_src.of` IS A PER-TAG `case` LADDER**

The prior unit listed `multi.bend` as **2 sites + cascade**. It is **3 sites + cascade**,
and the third is the same trap `spec.bend` records in its own header -- *"renaming the
right-hand sides of a `match` does not renumber its left-hand arms"* -- one file over.

`multi.bend:2102` is a `match tag:` over **tag numbers**, with 20 arms
(`case 1: ex2` ... `case 24: alu0`, plus `case _: True{}`). `mu_claim_full.go` (`:2161`)
feeds it `O.PMEntry.tag(e)`. **Delete `mu_own`'s tag 7 and every arm at or above it is
now one rule's number answering for another rule's src test.**

I DID NOT BELIEVE IT, I MEASURED IT. With the ladder left alone, `r_full_su`
(`mu_claim_full` on STORE-of-`M0`) went **2 -> 1**. **A COUNT MOVING IS NOT A
RENUMBERING** -- it is precisely the signal the brief says to stop on:

> *"IF A PIN WOULD HAVE TO BE REWRITTEN, **THAT IS THE SIGNAL YOU RENUMBERED SOMETHING
> YOU SHOULD NOT HAVE.**"*

Renumbering the ladder the same way (`case 7` deleted, every arm `t > 7` moved to
`t-1` -- uniform, because the own half's tags drop one AND `mu_ra_cfg`'s base drops
one) **restored `r_full_su` to 2** and `t_full_su` is no longer red. Decisive.

The ladder after: `case 1 2 3 4 5 6 7 8 10 11 13 14 15 16 17 20 21 22 23` + `case _`
-- 20 arms to 19, `case 7` gone, no collision.

### THE ELEVEN ROWS THAT GO RED, AND WHAT EACH NEEDS

`diff` of the `t_*` rows, BEFORE vs AFTER-with-the-ladder-fixed. **Every one is an
expectation that the re-index makes stale, and NONE is a divergence and NONE is a pin
that should move:**

| row | now | measured replacement |
|---|---|---|
| `t_rej_n` | 0 | `21 -> 20` |
| `t_rej_late` | 0 | `21 -> 20` |
| `t_ops_n` | 0 | `57 -> 56` |
| `t_mov_n` | 0 | `6 -> 5` |
| `t_first_st` | 0 | `17 -> 16` |
| `t_first_su` | 0 | `17 -> 16` |
| `t_t20_on` | 0 | `mt_op(early,20)` is `COPY`->`MSELECT`; expect **`MSELECT()`** |
| `t_t19_off` | 0 | `mt_op(late,19)` is `ALLREDUCE`->`COPY`; expect **`COPY()`** |
| `t_t23_off` | 0 | `mt_op(late,23)` is `SHRINK`->`MSELECT`; expect **`MSELECT()`** |
| `t_t25_off` | 0 | **NOT A NUMBER FIX -- INDEX 25 IS PAST THE END** of a 25-entry table |
| `t_tag25` | 0 | **NOT A NUMBER FIX -- SAME** |

**THE LAST TWO ARE NOT TRANSCRIPTIONS AND THAT IS THE POINT.** `mu_c_late`'s table
shrank 26 -> 25 entries, so index 25 no longer exists: `mt_entry` (`:2376`) returns the
sentinel `PMEntry{999, Nil, Nil}` and `mt_op` on its empty op list returns
`4294967295`. **MEASURED, index 24 is the last real one: `mt_op(late,24)` = `MSELECT`
and `mt_tag(late,24)` = 24.** So both rows repoint `25n -> 24n` and their existing
expectations (`MSELECT`, and `24`) are already correct. **`t_t25_off` and `t_tag25`
must NOT be deleted** -- deleting a row to make a gate pass is the one thing forbidden,
and here deletion would also be unnecessary.

### THE OP VALUES, so nothing is transcribed

```
          before -> after            before -> after
COPY        65 -> 64  (-1)          SHRINK      18 -> 17  (-1)
MSELECT     66 -> 65  (-1)          STORE       20 -> 19  (-1)
ALLREDUCE   76 -> 74  (-2)          STACK       15 -> 14  (-1)
UNSHARD     74 -> 72  (-2)
```

---

## 3. THE RE-INDEX ITSELF, RE-VERIFIED ON MY COPY

```
declared 75   upstream 75   value arms 75   all_ops 75
NEW Ops.value == upstream, all 75: True
mismatches: 0
declared order == value-arm order == all_ops order: True
numbers are 1..75 with no gap: True
removed by upstream now (name-matched): []
added upstream: []
GROUP/FLIP references left in ops.bend: 0
```

**THE PRIOR UNIT'S CENTRAL PROOF REPRODUCES EXACTLY.** Arm counts as it recorded:
13 unchanged, 58 shift -1, 4 shift -2, 2 deleted.

---

## 4. NOT DONE, AND WHY

| item | why |
|---|---|
| **THE LAND** | two `fold-mvt` oracles are hard-dead at `HEAD` on `ParamArg.size`, a CPython-side defect outside the grant; see section 1 |
| `REMOVE_FROM_SINK_LIKE` BOTH HALVES | in `uop/symbolic.bend`, not in `multi.bend`'s closure; not measured, so not done |
| `sym_table` loses only 11 | same file; the prior unit's reading of `symbolic.py:440/:444/:445` stands unverified by me |
| the other 8 re-index files | outside what a stopped unit should touch |
| `fold-mvt` `ParamArg(size=)` repair | a different defect with a different owner; see section 1 |

**ITEMS 2 AND 3 ARE RECORDED HERE AS THE PRIOR UNIT RECORDED THEM, NOT AS MY OWN
FINDINGS. I DID NOT MEASURE EITHER AND I AM NOT RESTATING THE BRIEF'S NUMBERS AS IF I
HAD.**

---

## 5. INSTRUMENTS

`multi_reindex.py` (`mu_own` tag deletion + one simultaneous renumber + `mu_move_ops`
+ the `mu_src_src.of` ladder + the `mu_ra_cfg` rebase) and `probe.py` (the 25 RAW rows)
are here, alongside `multi-BEFORE.rows` / `multi-AFTER.rows`.

**`multi_reindex.py`'s OWN CHECKS CAUGHT THREE OF MY OWN BUGS BEFORE THEY REACHED THE
TREE, WHICH IS THE ARGUMENT FOR WRITING THE CHECKS FIRST:**

1. `TAG` did not allow for `mu_own`'s opening `[`, so tag **0 fell out of the map's
   domain** -- the same blindness as reading a population off a suffix, one level down.
2. `drop[0]` is a **line index**, and I first used it as the **tag number**.
3. `own_n` counted **lines**, and the block carries comments, so 18 entries read as 24
   and the `mu_ra_shift` rebase refused.

Each exited `sys.exit(...)` with the tree untouched. **A SCRIPT THAT REWRITES A TABLE
AND CHECKS ITSELF IS WORTH MORE THAN A SCRIPT THAT DOES NOT.**

## 6. RUNS

| run | verdict token | peak RSS | wall |
|---|---|---|---|
| `multi.bend` BEFORE (`OPS.bend` at HEAD) | `WITHIN-LIMITS` | 567 MB | 1s |
| `multi.bend` AFTER (3 files re-indexed) | `WITHIN-LIMITS` | 600 MB | 1s |
| `multi.bend` AFTER + ladder fix | `WITHIN-LIMITS` | 456 MB | 1s |
| `gates/tn_minimum-gate.py` | FAIL, `rc=1` | -- | <1s |

`bounded.py` printed `MACHINE: **VIOLATED**` on every run (loadavg 14.0 on 12 cores,
swap free 1.08 of 22.00 GiB) and records itself that *"a time bound here is not
attributable to the child"*. **I AM READING THE PEAK AND THE TOKEN ONLY.**