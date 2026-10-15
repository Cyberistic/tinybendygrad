# `residual` — WHAT IS LEFT OF THE FALSE FAILs IN `checks/cites-census.py`, AND THE ONE GUARD THAT TAKES 16 OF THEM

Unit `residual`. 2026-10-15. **Committed nothing, staged nothing, ran no `jj`.** Every run below is
one process at a time on this machine, with nothing else compiling. **No `bend`, no
`differ.py run/repro`, no graphcorpus loop, no RSS sampling.**

**A note on the clock.** Python only via `.venv/bin/python`; no `.txt` anywhere — the artifacts are
`.rows`, `.out`, `.py` and this `.md`. **The tree was being written by other units the whole time**
(`c51c5ffd2 → b23f4a885 → 265d31b7d → 8cd284f8d → c1e2b9fb2 → 00e0b4f784e0 → 94da1a0914c0` during the
session, and `.agents/TODO.md` alone grew 12 lines in 3 minutes at one point). **Every count below
carries its UTC instant and the HEAD it was read at, because the next read will not reproduce it.**
The one number that is immune to that is §4's, because it is a differential on a frozen snapshot.

---

## 0. THE HEADLINE, WITH ITS DENOMINATOR IN THE SAME SENTENCE

**At HEAD `00e0b4f784e0`, 2026-10-15T09:29:59Z, over the 2,329 committed `.md`/`.py` files (31,674
rows), `checks/cites-census.py` emitted `FAIL = 201`, and `51` of those are the NEW half** (the
subject resolves only through the suffix index `adfee1a5028e` added). Of the 51, hand-labelled one at
a time against a witness:

| class | n | of 51 | who is wrong |
|---|---:|---:|---|
| **FALSE-SHAPE** | **23** | 45.1% | the instrument asked the wrong question |
| **TRUE-STALE** | **19** | 37.3% | nobody; the claim was true when it was written |
| **FALSE-SUBJECT** | **7** | 13.7% | the instrument attributed a claim to the wrong file |
| **TRUE** | **2** | 3.9% | the prose — and both are now corrected |

**So 30 of 51 (58.8%) are FALSE FAILs, 19 (37.3%) are stale-but-once-true, and 2 (3.9%) are a
genuinely false sentence.** That is the whole residual: **there is no fourth category hiding in
here, and no residual NEW FAIL that I could not name.** The two TRUE rows were corrected in
`.agents/TODO.md` (§3) and the NEW half fell to **49** (2026-10-15T09:37:39Z, HEAD `94da1a0914c0`).

---

## 1. HOW TO REPRODUCE, WITH THE COMMAND AND THE INSTANT

```
.venv/bin/python .agents/slop/residual/censusnow.py .agents/slop/residual/fails-now.rows
```

`censusnow.py` runs ONE census through the instrument's own `committed()`, `census()`, `judge()` —
no reimplementation — prints the totals, splits the FAILs by whether the subject is a file at
`ROOT/<subject>` (PRE) or only a suffix-index hit (NEW), and writes the FAIL rows with the needle
untruncated. Two readings, both on this machine, back to back:

| instant (UTC) | HEAD | files | rows | PASS | FAIL | REFUSED | SKIP | DEAD | FAIL NEW | FAIL PRE |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026-10-15T09:29:59Z | `00e0b4f784e0` | 2,329 | 31,674 | 2,949 | **201** | 3,326 | 25,198 | 0 | **51** | 150 |
| 2026-10-15T09:37:39Z | `94da1a0914c0` | 2,329 | 31,680 | 2,952 | **198** | 3,326 | 25,204 | 0 | **49** | 149 |

**The denominator is the 2,329 committed `.md`/`.py` files at that HEAD** — `git ls-tree -r HEAD`,
not `.venv`, not the on-disk walk. The 6-row SKIP swing between the two readings is other units'
writes, not mine; §3's two edits are the NEW 51 → 49.

---

## 2. THE 51 NEW FAILs, EVERY ONE, WITH ITS ANCHOR

Anchor is `claiming-file:line`. `classified.rows` is the machine-readable table; the classes are
the four in §0. **A `TRUE` or `TRUE-STALE` row is an honest FAIL** (the claim is wrong, or was true
once); a `FALSE-*` row is the instrument's fault.

### 2a. `FALSE-SHAPE` — 23 rows. **The needle is not a literal of the subject, so the question was wrong.**

Every one of these is a needle that names a *thing* — a gate lane, a run mode, a table column, a
command, a delta verb — and the census then asks the subject file whether it *contains* that word.

| anchor | subject | needle | why the question is wrong |
|---|---|---|---|
| `.agents/TODO.md:515` | `codegen/decomp/dtype.bend` | `BASE_ORACLES` | a dict in `.agents/slop/rebase-gate.py`, keyed BY the port path; the sentence is "dtype.bend's BASE_ORACLES **lane** is RED", a claim about the gate |
| `.agents/TODO.md:3022` | `uop/ops.bend` | `cfunc_buf` | a token in the *next* clause of a list, not a predicate on `ops.bend` |
| `.agents/TODO.md:3803` | `engine/realize.bend` | `array` | the sentence says "`array` **removed**" — a claim about a DIFF |
| `.agents/TODO.md:5635` | `codegen/decomp/dtype.bend` | `native` | a bend RUN MODE (`native` rc=1 vs `interpreted`), not text in the file |
| `.agents/TODO.md:5691` | `uop/render.bend` | `LANE-DEATH` | a table CELL LABEL |
| `.agents/TODO.md:5692` | `viz/serve.bend` | `LANE-DEATH` | same |
| `.agents/UPSTREAM.md:121` | `runtime/support/am/amdev.bend` | `AMDev.setup_ring` | a dotted-qualified name that never appears literally (`setup_ring` is PRESENT) |
| `.agents/UPSTREAM.md:134` | `runtime/support/hcq2.py` | `encode_submit` | the sentence is about upstream's RENAME; `encode_submit` is PRESENT in the port twin |
| `.agents/slop/CSTYLE2.md:61` | `renderer/cstyle.bend` | `main` | a def name the prose is *describing*, not quoting |
| `.agents/slop/DEADARM.md:186` | `renderer/cstyle.bend` | `sha256` | a command, and the sentence says a digest is "recorded below" |
| `.agents/slop/F64-KERNEL.md:155` | `renderer/cstyle.bend` | `sha256 07ae2766…` | a digest with an ellipsis |
| `.agents/slop/deadreg/REPORT.md:190` | `runtime/dtype.c` | `file:line` | the words "file:line", a SHAPE |
| `.agents/slop/declared472/census.py:2` | `capstream/refsplit.py` | `a basename match is not a reference` | prose inside a docstring ABOUT capstream's rule |
| `.agents/slop/emptyevid/REPORT.md:88` | `gatesrun/CLASSES.tsv` | `path · class · rc · token · cause · answer` | a column list, and middots |
| `.agents/slop/flipthird/REPORT.md:26` | `uop/render.bend` | `WITHIN-LIMITS` | a gate VERDICT TOKEN (see §6) |
| `.agents/slop/flipthird/REPORT.md:27` | `uop/upat.bend` | `WITHIN-LIMITS` | same |
| `.agents/slop/lanedeath-census.md:198` | `uop/ops.bend` | `ABlob{n}` | a SHAPE with a metavariable; the file has `ABlob{bs}` |
| `.agents/slop/notes/bend2-constraints.md:10608` | `codegen/opt/postrange.py` | `Scheduler.reduce_axes` | a dotted name for a def the sentence says was DELETED |
| `.agents/slop/notes/bend2-constraints.md:20651` | `codegen/decomp/dtype.bend` | `md5 -q` | a COMMAND |
| `.agents/slop/notes/bend2-constraints.md:23901` | `renderer/cstyle.bend` | `kern2 CLANG` | two tokens: a row NAME plus a qualifier |
| `.agents/slop/portunknown/REPORT.md:106` | `mixin/dtype.bend` | `belts-disagree` | a class name the row says is a *tokenizer artifact* |
| `.agents/slop/rebase/REPORT.md:82` | `runtime/support/c.py` | `DLL._loaded_` | the prose is about the PORT's `.bend`; it is PRESENT there |
| `.agents/slop/unobservable-report.md:218` | `uop/ops.bend` | `pm_dispatch_m case 0` | a case label with an argument; `pm_dispatch_m` is PRESENT |

**THE 23 ARE ONE FAULT WITH 23 FACES: `needle_kind()`'s `text` branch is the only one that emits a
FAIL, and a needle can be unmistakably about the file and still be none of `text`'s business.** §5
prices the branch-wide fixes, and every one of them is refused.

### 2b. `FALSE-SUBJECT` — 7 rows. **The instrument attributed a sentence's claim to the wrong file.**

All seven are the SAME deleted range, `renderer/cstyle.bend:2984-3015`: the prose is a TABLE whose
subject is the *citer* (`e2e.py:55`, `e2e.sh:228`), and the census read the citer's quoted path as
its own subject.

| anchor | subject | evidence |
|---|---|---|
| `.agents/slop/chkcites/REPORT.md:87` | `renderer/cstyle.bend` | "has 1367 lines, cited at :2984" |
| `.agents/slop/chkcites/REPORT.md:88` | `renderer/cstyle.bend` | same |
| `.agents/slop/cites2/REPORT.md:44` | `renderer/cstyle.bend` | same |
| `.agents/slop/cites2/REPORT.md:79` | `renderer/cstyle.bend` | same |
| `.agents/slop/notes/bend2-constraints.md:9029` | `renderer/cstyle.bend` | "has 1367 lines, claim says 287" |
| `.agents/slop/skipexit/prefix/checks/e2e.py:2` | `renderer/cstyle.bend` | the docstring of a *copy* of `e2e.py` |
| `.agents/slop/notes/bend2-constraints.md:16308` | `uop/spec.bend` | `#rebase_inner` is quoted as belonging to a NEIGHBOURING file in the same sentence |

### 2c. `TRUE-STALE` — 19 rows. **True when written; the file moved.**

10 are POSITIONS, 5 are COUNTS, 4 are names that moved file. The exact figures are in
`classified.rows`; the pattern is that `renderer/cstyle.bend` was cut from 2373 to **1367** lines by
`e51904b04`, so four of its own citations now point past EOF, and `runtime/sz.c`, `runtime/ops_nv.bend`
and `mixin/gradient.bend` all changed length under claims that did not. **A `TRUE-STALE` row is not a
false FAIL** — the prose does lie today — but it is not a defect the *instrument* can be blamed for.

### 2d. `TRUE` — 2 rows, the whole actionable finding. **Both corrected in §3.**

| anchor | subject | claim | measured |
|---|---|---|---|
| `.agents/TODO.md:2023` | `runtime/webgpu_call.js` | 502 lines | **503** (`splitlines()`); 502 is the newline count |
| `.agents/TODO.md:9779` | `viz/serve.bend` | its `pad_name` | `pad_name` is defined in `viz/cli.bend`, and nowhere else tracked |

---

## 3. THE TWO CORRECTIONS LANDED IN `.agents/TODO.md`

Both are one-token edits, both are unambiguous, and both are verified to have removed exactly the
NEW FAIL they name (51 → 49, §1):

1. **`` `runtime/webgpu_call.js` (502 lines) `` → `(503 lines)`.** The file has **503** lines and no
   trailing newline, so `splitlines()` = 503 and `wc -l` = 502. **`AGENTS.md` already adjudicates
   this**: "`splitlines() == awk NR` on all four probed… **`wc -l` undercounts exactly the one file
   the parent was already burned by. The parent's `wc -l` reply was the bad measurement and the gate
   was right.**" So the gate is right and the prose carried the `wc -l` number. §5 prices and refuses
   the tempting alternative — teaching the gate to accept `wc -l`.
2. **`` `viz/serve.bend`'s `pad_name` `` → `` `viz/cli.bend`'s `pad_name` ``.** `git grep -ln '\bpad_name\b'`
   finds `tinybendygrad/viz/cli.bend` and no other source file; the presence table in §7 says the same
   ("ABSENT in `viz/serve.bend`, PRESENT in `viz/cli.bend`"). The symbol moved; the sentence did not.

**Not landed, and why.** The third candidate — `.agents/TODO.md:515`'s `BASE_ORACLES` lane — is
§2a's first row: the census's question is wrong, so there is no prose defect to fix, and the sentence
should stand.

---

## 4. THE PRICE OF THE `quoted_spans()` GUARD: **16 FAILs RETIRED, 0 PASSes SILENCED**

**THE CHANGE.** In `checks/cites-census.py`, `quoted_spans()`'s double-quote alternative grew a
lookbehind:

```python
for m in re.finditer(r"\"([^\"]{4,})\"|(?<![\w`])'([^']{4,})'", s):
```

An apostrophe now opens a span only when no word character and no backtick precedes it. In
`` `x.bend`'s `y` `` the span used to start on the `'` — one position BEFORE the code span the
sentence names — so the needle was English prose (`` s `y`, which is `z` ``) and the verdict was
about a sentence. **A load-bearing selftest plant drives the EXTRACTOR, not `judge`**, because
`judge` never sees the span list:

```
revert `(?<![\w`])`  ->  === selftest FAIL: 23 case(s) run, 1 failed ===
landed               ->  === selftest PASS: 23 case(s) run, 0 failed ===
```

**THE PRICE, AS A DIFFERENTIAL ON ONE FROZEN SNAPSHOT** (`freeze.py`; 2,329 files, 31,675 rows, both
passes over ONE in-memory text and ONE memoized `read()`, so no live writer can move a verdict
between the two passes; 2026-10-15T09:32:52Z, HEAD `94da1a0914c0`):

```
BEFORE  PASS=2940 FAIL=215 REFUSED=3366 SKIP=25154
AFTER   PASS=2950 FAIL=200 REFUSED=3326 SKIP=25199
RETIRED-FAIL    16 rows (8 NEW/suffix-index)
SILENCED-PASS    0 rows (0 NEW/suffix-index)
```

- **N = 16 FAIL keys retired. M = 0 PASS keys silenced.** The guard bar is `M ≈ 0` against `N`, and
  this is the only candidate measured this session that clears it with M exactly 0.
- **15, not 16, is the net FAIL drop (215 → 200)**: `spec/render.md:36` keeps its FAIL but the needle
  improves from `` s "parse, don` `` to `parse, don't validate` — a better witness for a verdict that
  did not change. **An instrument that cannot improve its own evidence without looking like it lost a
  row is an instrument that will be reverted by accident.**
- **12 anchors recovered a PASS** (36 rows that were `REFUSED` moved out of lane C's hole into plain
  mentions — the shape of the hole changed, no verdict was lost). `frozen.rows` carries all of them.
- Run against the two rejected alternatives on the same baseline (`resid.py`, artifacts
  `price-A.rows` / `price-D.rows` / `price-E.rows`): **A** (drop `'…'` entirely) lost **19 FAIL /
  2 PASS**; **D** (apostrophe after whitespace) lost **18 FAIL / 1 PASS**; **E** lost **16 FAIL /
  0 PASS**. E is the only one that silences nothing.

---

## 5. GUARDS PRICED AND REFUSED, EACH WITH THE MEASUREMENT THAT REFUTED IT

The bar: **`N` = FAIL rows retired, `M` = PASS rows silenced; `M > N` means REFUTED.** These are from
`kinds.out` (one census, `rows=31,456 PASS=2,932 FAIL=212 REFUSED=3,364 SKIP=24,948`, read
2026-10-15 ~09:11Z), except the last two, which have their own instants.

| candidate | N | M | new FAILs | verdict |
|---|---:|---:|---:|---|
| `cell-label` accepts hyphen (`ARTIFACTS-FRESH` is one) | 8 | **4** | 0 | **REFUSED** |
| `OUTPUT` (`->`/`rc=`) reads the LINE, not the gap | 12 | **22** | 0 | REFUTED |
| `DELTA` verb anywhere on the line | 32 | **271** | +25 | REFUTED |
| dotted-qualified name (`Scheduler.reduce_axes`) | 30 | **247** | +26 | REFUTED |
| shape `…` / `{n}` / `file:line` | 29 | **247** | +29 | REFUTED |
| lane-D accepts the `wc -l` convention | 5 | 0 | 0 | **REFUSED** (§5.1) |

### 5.1 The lane-D convention guard, and why M = 0 does not save it

`convd.py` widens lane D so a number equal to the file's NEWLINE count (a file with no trailing
newline) is `REFUSED` rather than `FAIL`. Measured 2026-10-15T09:34Z, one process, whole census:
**BASELINE `FAIL=200` → VARIANT `FAIL=195`, N = 5, M = 0.** The five rows are
`.agents/TODO.md:2023` (`runtime/webgpu_call.js`, 502), `checks/sweep.py:85` (`checks/residue.py`,
750), `.agents/slop/gatesweep/REPORT.md:12` (`gates/gatesppop.py`, 1529) and two in
`.agents/slop/guardfix/REPORT.md` — and all five files verify as `newlines == claim` and
`splitlines == claim + 1` with no trailing newline.

**Refused anyway, for a reason M=0 cannot answer: a lane-D widening cannot silence a PASS by
construction, so the bar is vacuous for this class, and the five are not false FAILs.** §3 already
quotes `AGENTS.md` adjudicating this exact case — `splitlines() == awk NR` is this tree's count and
`wc -l` is "the bad measurement". **Teaching the census to refuse would hide five honest FAILs to
flatter a count, and there is a one-token prose fix for each.** The instrument is right; the prose is
one number off.

**AND THE GUARD THAT WAS LANDED IS §4's, WHICH IS THE ONE THAT SILENCES NOTHING.**

---

## 6. THE IMMOVABLE RESIDUE — WHY THE `cell-label` GUARD CANNOT BE LANDED

The single most attractive remaining guard is §2a's `LANE-DEATH` / `WITHIN-LIMITS` class: a bare
ALL-CAPS word in a table cell is a label, and `needle_kind()`'s `cell-label` branch already exists —
it just demands `WORD3.fullmatch`, which a HYPHEN (`LANE-DEATH`) and a compound (`WITHIN-LIMITS`)
fail. **Widening `cell-label` to accept hyphens retires 8 FAILs (N=8) and silences 4 PASSes (M=4).**

**Those 4 silenced PASSes are exactly the mirror of the false FAIL, and they are inseparable from it.**
MEASURED 2026-10-15 (whole tree, `grep -c`):

| file | `WITHIN-LIMITS` | `ARTIFACTS-FRESH` |
|---|---:|---:|
| `tinybendygrad/uop/render.bend` | **0** | — |
| `tinybendygrad/uop/upat.bend` | **0** | — |
| `tinybendygrad/tensor.bend` | **0** | — |
| `checks/runs-artifacts.py` | — | **3** |

`WITHIN-LIMITS` is a verdict token of `checks/bounded.py`; it is **absent** from every `.bend` file
that prose claims carries it — a FALSE FAIL, §2a. `ARTIFACTS-FRESH` **is** a literal in
`checks/runs-artifacts.py` — a TRUE PASS, and the four PASSes the guard silences are the
`ARTIFACTS-FRESH`/`ARTIFACTS-STALE` rows at `.agents/slop/{clonesafe,constfix,dangle,wireit}/…`.
**A rule that catches the label cannot tell what the label names, so it converts a false FAIL and a
true PASS on the same shape at the same time.** There is no narrower rule: the two differ only in
whether the named file happens to contain the token, which is the very question the census answers.
**This is the brief's "immovable residue", and it is immovable by measurement, not by opinion.**

---

## 7. THE WITNESS SET — WHERE EACH NEEDLE ACTUALLY LIVES

`presence.py`, 2026-10-15T09:45:47Z, HEAD `94da1a0914c0`: resolve the census's own subject
(ROOT-exact, then the unique suffix), then ask `git grep` where else the needle is tracked.

**ABSENT from the file the census read (the FAIL is at least about the right file):**
`BASE_ORACLES` in `tinybendygrad/codegen/decomp/dtype.bend` · `cfunc_buf` in `tinybendygrad/uop/ops.bend` ·
`pad_name` in `tinybendygrad/viz/serve.bend` · `main` in `tinybendygrad/renderer/cstyle.bend` ·
`randn_like23_g` in `tinybendygrad/mixin/rand.bend` · `nv_errstr_N` and `WHAT IS PORTED, DEF BY DEF`
in `tinybendygrad/runtime/ops_nv.bend` · `md5 -q` in `tinybendygrad/codegen/decomp/dtype.bend` ·
`file:line` in `tinybendygrad/runtime/dtype.c` · `DLL._loaded_` in `tinygrad/runtime/support/c.py` ·
`Scheduler.reduce_axes` in `tinygrad/codegen/opt/postrange.py` · `encode_submit` in
`tinygrad/runtime/support/hcq2.py` · `pm_dispatch_m case 0` in `tinybendygrad/uop/ops.bend` ·
`WITHIN-LIMITS` in `tinybendygrad/uop/render.bend` and `tinybendygrad/uop/upat.bend` ·
`parse, don't validate` in `spec/ops.md` · `a basename match is not a reference` in
`.agents/slop/capstream/refsplit.py` · `ABlob{n}` in `tinybendygrad/uop/ops.bend` · `#rebase_inner` in
`tinybendygrad/uop/spec.bend` · `sha256` in `tinybendygrad/renderer/cstyle.bend` · `belts-disagree` in
`tinybendygrad/mixin/dtype.bend` · `array` in `tinybendygrad/engine/realize.bend`.

**PRESENT — the symbol moved file, which is what makes the row `FALSE-SHAPE` or `FALSE-SUBJECT`:**
`pad_name` in `tinybendygrad/viz/cli.bend` · `DLL._loaded_` in `tinybendygrad/runtime/support/c.bend` ·
`setup_ring` in `tinybendygrad/runtime/support/am/amdev.bend` · `encode_submit` in
`tinybendygrad/runtime/support/hcq2.bend` · `ABlob{bs}` in `tinybendygrad/uop/ops.bend` ·
`ARTIFACTS-FRESH` in `checks/runs-artifacts.py`.

**AND NOTHING IN THIS LIST IS DISCOVERED BY A HAND LIST.** `presence.py`'s pairs are the FAIL rows'
own `(needle, subject)`, `censusnow.py`'s population is the instrument's own `committed()`, and
`label.py`'s 39 reused labels are `failaudit`'s `handlabels.rows` matched BY ANCHOR. **A population
named by a reader is a list; one named by the instrument is a census.**

---

## 8. WHERE THIS MEASUREMENT IS WEAK, AND WHAT I DID NOT DO

- **The anchors move.** `.agents/TODO.md` is under a live rewrite by another unit — `BASE_ORACLES`
  moved `508 → 515 → 531` inside this session, and the 12 TODO rows in §2 were re-labelled from the
  ROWS' own evidence because `failaudit`'s line anchors no longer resolve. **Two of the 51 are
  corrected (§3) and the rest will re-anchor again. Classify by needle, never by line.**
- **I disagree with `failaudit` on ONE row, with the witness.** `failaudit` labelled
  `.agents/TODO.md`'s `BASE_ORACLES` row **TRUE** ("NOWHERE in `codegen/decomp/dtype.bend`"). The
  sentence is "dtype.bend's `BASE_ORACLES` **lane** is RED", and `git grep -l BASE_ORACLES` finds it
  in **30 tracked files**, the table itself in `.agents/slop/rebase-gate.py`, and **zero `.bend`**.
  A claim about a gate lane is not a claim about the file's text, so it is **FALSE-SHAPE**, not TRUE.
  **That is 23 FALSE-SHAPE / 2 TRUE, not 22 / 3.** `failaudit`'s other two TRUE rows (`webgpu_call.js`
  and `pad_name`) I adopt.
- **The PRE half (149–150 FAILs) is out of scope and untouched.** The brief scoped the residual to
  the NEW population; the PRE rows have ROOT-exact subjects and their own audit.
- **Nothing was committed and nothing staged.** `checks/cites-census.py`'s guard (§4) and
  `.agents/TODO.md`'s two corrections (§3) sit UNCOMMITTED in the working tree, alongside another
  unit's `UNIT`/`needle_kind` edits to the same file, which this report neither claims nor reverts.
- **One row I should have caught earlier and did not**: the 4 rows
  `.agents/slop/{chkcites,cites2,skipexit,notes}/…` in §2b are the *same* deleted range counted four
  times, because the census reads the CITERS' prose as claims. **A population that counts a table's
  rows as independent claims is inflating its own denominator**, and the fix (a citer-aware subject
  rule) is a shape change, not a guard — priced nowhere here.
