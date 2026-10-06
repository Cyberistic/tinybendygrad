# 02 — EVERY STALE CLAIM, WITH ITS DENOMINATOR AND WHAT CAME TO

Rule followed throughout: **a stale count without its denominator is not yet a correction**,
and **a number that could not be re-measured is marked STALE, not guessed.** Ground truth is
in `01-GROUND-TRUTH.md`; every "current" below came from a run, not from a note.

Denominator key: **/77** = of the 77 upstream `Ops` (measured `len(list(Ops))`) ·
**/24** = of the 24 corpus graphs · **/136→137** = of the `.bend` files.

## A. The corpus coverage number — the big one, and it is stale in 8 places

| # | file:line | claim as written | denominator | current | corrected |
|---|---|---|---|---|---|
| A1 | `REACH.md:11-18` | headline block: `graphs 22`, `reached 53/53/53`, `NEITHER 24` | /24 graphs, /77 ops | **24 graphs, 59/59/59, NEITHER 18** | **yes** — banner above the block, block kept as baseline |
| A2 | `REACH.md:26-29` | "The 24 not reached, named" + 24 names | /77 | **18 not reached** | **yes** — the 24-list is the 53-era complement; marked |
| A3 | `REACH.md:108` | "53 of 77 is coverage of the emitter" | /77 | **59 of 77** | **yes** |
| A4 | `REACH.md:41` | `UNION of the four: 0 new -> 53+0=53 of 77` | /77 | arithmetic of its own era | **left, marked era** — a record of that measurement, not a live claim |
| A5 | `graphcmp-LIMITS.md:26` | `ops 34 of 77` in the current-state block | /77 | **59 of 77** | **yes** — superseded banner + both values |
| A6 | `graphcmp-LIMITS.md:50-53` | "RESOLVED, at **34 of 77** ops" | /77 | **59 of 77** | **yes** — the resolution stands, the figure does not |
| A7 | `graphcmp-LIMITS.md:420-437` | §5 headline `34 of 77` + `REACHED (34)` table + `NOT REACHED (43 of 77)` | /77 | **59 reached, 18 not** | **yes** — banner; old table kept verbatim as the baseline §0/§3c were written against |
| A8 | `graphcmp-LIMITS.md:737` | "anything about the **43** unexercised ops" | /77 | **18** | **yes** |
| A9 | `TENSOR-SURFACE.md:206` | *"The '43 of 77 not reached' in `graphcmp-LIMITS.md:422`"* | /77 | **18 of 77**, and **`:422` is the wrong line** | **yes** — both the figure and the citation |
| A10 | `AUDIT-CAN-FAIL.md:15` | `02 \| 34 of 77 ops \| the 16-graph corpus` | /77 | 59 of 77 over 24 | **left — it is an audit TABLE with planted baselines**, and its BASELINE column is the measurement, not a live claim |
| A11 | `unfalsifiable/FIX-4:118`, `audit/02-*.md`, `graphcmp-report.md:5`, `COMMIT-MISATTRIBUTION.md:64`, `BW-GRAPH.md` | `34`/`35`/`43` of 77 | /77 | all pre-date the current corpus | **left** — every one is quoting a *historical baseline* of a named experiment. Rewriting them destroys the audit. |

**A12 — `AUDIT-CAN-FAIL.md`'s "16-graph corpus" is the one audit row that has aged into a
live claim.** Its own subject column says "which of tinygrad's 77 `Ops` the 16-graph corpus
reaches", which is a description of the *instrument's* scope, not of the corpus. Flagged,
not edited: the audit's plants are stated against that baseline.

## B. The `flip` verdict — `6/7` DISAGREE, superseded by `6/6` AGREE (5 sites)

| # | file:line | claim | denominator | current | corrected |
|---|---|---|---|---|---|
| B1 | `REACH.md:63` (table) | `flip \| DISAGREE \| **6/7**` | nodes | **AGREE 6/6** | **yes** |
| B2 | `REACH.md:96-97` | "7 nodes against 6 … sole cause of DISAGREE" | nodes | py side never had 7; the `GROUP` was a **fixture** bug | **yes** — both differences re-cast, each labelled CORRECTED |
| B3 | `REACH.md:255-256` (BEFORE/AFTER block) | the `6/7 → 6/6` record | nodes | ✅ **AFTER line still holds exactly** | **kept + re-measured confirmation** |
| B4 | `flip/FLIPR.md:180,182` | same BEFORE/AFTER | nodes | ✅ still correct | **kept — verified, not assumed** |
| B5 | `REACH.md:188-192` | "**`flip` … is stale.** reads AGREE 6/6 now" | — | ✅ **correct; the caution is right** | **kept**, re-labelled as history now that the table is fixed |

**The `7` came from a stale `GROUP=1` in a py-side census** (`ops.py:558-560` returns a lone
src unchanged), i.e. a stale *census*, not a stale tree. **All four "brief-said" `6/7` sites
were the same four and all four are now marked.**

## C. `graphs-agree` — the pin, in 5 places (brief said 5; **6 found**)

| # | site | claim | denominator | current | corrected |
|---|---|---|---|---|---|
| C1 | **`graphcmp-repro.sh:66`** | `grep -q '^graphs-agree=14$'` | /24 graphs | **22** | **NOT EDITED — gate script, out of scope.** Reported in `REACH.md`, `graphcmp-LIMITS.md` §3c, `NOTES-SWEEP.md` |
| C2 | `graphcmp-LIMITS.md:359` (§3c table) | `graphs-agree=13` → `14` | /24 | **22** | **yes** — the only live pin in that table, flagged |
| C3 | `REACH.md:123` | "`graphs-agree=14` should read **15**" | /24 | **22** | **yes** — and this is the "in the other direction" the addendum warned about |
| C4 | `REACH.md:192` | "the `…=14`-should-read-15 note is now out of date in the other direction" | /24 | still true, **and now understated** | **yes** — reconciled to 22 |
| C5 | `backward-graph/BW-GRAPH.md:278` | "reads `graphs-agree=14` and must become **15**" | /24 | **22** | **flagged, handover note** — its "must become" is now wrong twice over |
| C6 | `notes/bend2-constraints.md:21396`, `graphcmp-report.md:48`, `graphcmp-LIMITS.md:39` | `14` / `13` | /24 | historical | **left** — each is describing the pin's *own history*, which is the point |

**`graphcmp-repro.sh` also pins `graphs=16` and `byte-identical=14`, both wrong** (24 and 21).
So the gate refuses a correct run for **three** reasons at once.

## D. Graph/verdict counts and denominators that aged

| # | site | claim | denominator | current | corrected |
|---|---|---|---|---|---|
| D1 | `graphcmp-LIMITS.md:25` | `graphs 16  AGREE 14 … nodes 189 per side` | /24 | **24 graphs, 22 AGREE** | **yes** |
| D2 | `graphcmp-LIMITS.md:27` | `field-records 1134 per side`, `byte-identical 14 of 16` | /24, nodes | byte-identical **21 of 24**; field-records **STALE** | **yes / STALE** |
| D3 | `graphcmp-LIMITS.md:413` | "14 of 16 graphs' canonical files byte-identical" | /24 | **21 of 24**, and `flip` differs yet AGREEs | **yes** — plus the finding that these are two different events |
| D4 | `graphcmp-LIMITS.md:599` | gate wants "sixteen graphs, **thirteen AGREE**" | /24 | **24 / 22** | **yes** (marked STALE: the repro gate was not re-run) |
| D5 | `graphcmp-LIMITS.md:728-734` | "for these 16 graphs … 189 nodes … 1134 field-records … 14 of 16" | /24 | **24 / 21 of 24**; nodes+records **STALE** | **yes / STALE** |
| D6 | `REACH.md:261`, `flip/FLIPR.md:202` | `20 AGREE, 2 DISAGREE` | /22 then | **22 AGREE, 2 DISAGREE** /24 | **yes, both** |
| D7 | `graphcmp-LIMITS.md:207, 223, 412` | "0 of the **189** nodes", "0 of **16** graphs", "over 189 nodes" | nodes, /16 | **STALE** ×3 | **yes — marked STALE, not re-measured** |
| D8 | `AUDIT-CAN-FAIL.md:158`, `graphcmp-report.md:5`, `audit/02-*.md`, `BW-GRAPH.md:86` | "sixteen graphs", "189 nodes per side", "0 of the 189 nodes" | /16 | historical baselines | **left** — quoting a named past experiment |

## E. The commutative count — a claim that inverted (not in the brief)

`graphcmp-LIMITS.md:462-470` asserts **"SEVEN of the eight COMMUTATIVE ops"** and spends a
paragraph proving `CMPEQ` is unreachable (*"`CMPEQ` is still 0. Reaching it needs a
pattern-matched rewrite"*). **MEASURED: EIGHT of eight** — `CMPEQ` is reached by the `late`
graph, and `commutative-ops=8` is on every report's `DENOMINATOR` line.

**Every measurement the paragraph makes is still true and the conclusion it draws is false.**
No eager graph reaches `CMPEQ`; the corpus reaches it by a *rewrite* route. **"I could not
reach it" and "it cannot be reached" are different claims** — and this file spent a paragraph
promoting the first into the second. Corrected with the reasoning preserved. `REACH.md:236-238`
already had the right half of this ("true and incomplete").

## F. The `.bend` census in `agent-core.md` — numerator right, both denominators wrong

`agent-core.md:138`: "**14 of the 136** `.bend` files … 0 for the other **122**".
MEASURED over all files: **`total 137  rc=1: 14  rc=0: 123`**. **The 14 cold files are
exactly the 14 in that table, member for member**, so the `plain run` column and the 8/6 split
are untouched. Only the file count aged — a `.bend` was added.

## G. `SPELLING.md` — two counts moved, one citation is dead, eight are fine

| claim | denominator | current | corrected |
|---|---|---|---|
| **678** qualified `H.I64` uses | occurrences | ✅ **678 — held** | confirmed |
| **41** files | files | **39** | **yes** |
| **40** `i64_*` defs | defs | read **23**; 40 not reproduced | **yes — marked STALE** |
| `libclang.bend:95,98,101` nullary uses | lines | those lines are now a `Ty` record and a blank | **yes — STALE** |
| `i64_add :1720` … `i64_cmp :1688`, `data64 :2099` | lines | ✅ **all 9 still exact** | **confirmed** |
| S-6 (`dsl.bend:64` → `helpers.bend:1167`) | — | ✅ **still true, defect still live** | **confirmed, reported unfixed** |
| S-7 (`ffi-lane.bend:20` → `cl-port-gate.sh`) | — | ✅ **still true**; `cl-port-gate.py` exists, no `.sh` | **confirmed, reported unfixed** |
| `dtype.c:205` / `dtype.js:136` | lines | **STALE by construction** — `dtype.js` is owned by a live unit | **yes** |

## H. Wrong `file:line` citations — verified, not assumed

**H1 — `arith/REACH-ARITH.md` §5: FOUR of its six citations were wrong, all in the wall that
reported them.** (The brief found two.)

| wall | cited | actual | by name |
|---|---|---|---|
| 3 | `graphcmp.py:2769` = `os.environ["DEV"]` | **`:2769` is `continue` in `split_debug`** | `DEV` is at **`:2977`**, `load_tinygrad()` at `:2978` |
| 3 | `graphcmp.py:1712-1717` = `clean_env` | **that range is a plant comment** | `def clean_env` at **`:1820`** |
| 5 | `graphcmp.py:2869` = the well-posedness precondition | **that is a `CONFLATION 1` line in `cross`** | precondition at **`:3082-3083`**, prints `:3084` |
| 6 | `ops.py:842` = `unique_num` | **`:842` is `def getaddr`** | `unique_num` at **`:839`** |
| 1 | `graphcmp.py:1686` / `:1703-1705` = `emit_py` | **both prose/comments** | `def emit_py` at **`:1794`**, last two lines **`:1812-1813`** |
| 2 | `reach/census.py:24` | ✅ **exactly right** | confirmed |
| 4 | `ops.py:1619` / `:1888` | ✅ **both exactly right** | confirmed |

**Every wall's SUBSTANCE is still correct** — only line numbers were fiction. That is worth
separating: the notes' reasoning was sound and their pointers were not.

**H2 — `flip/FLIPR.md`: citations into the GENERATED `graphcmp.bend` moved.** `def g_flip` is
now **`:1289`** (cited `:1274`), the `ATuple{[1, 0]}` at **`:1295`** (cited `:1273`), the
repaired `O.UOp.group(...)` at **`:1296`**. `ops.py:558-560` ✅ and `ops.bend:1066` ✅ are
still exact. **`graphcmp.bend:1241-1242` now records the *corrected* census** — i.e. the
number FLIPR was citing has already been fixed underneath it. **A citation into a generated
file is a citation into a file that is rewritten by a header edit; cite by NAME.**

**H3 — `TENSOR-SURFACE.md:206`** cites `graphcmp-LIMITS.md:422`; the figure is not on `:422`.

## I. Numbers I found CORRECT that a note says are wrong — the other direction

1. **`REACH-ARITH.md`'s `cdiv` `7/7 of 77` and `late` `9/9 of 77`** — re-measured from the
   reports' own `DENOMINATOR` lines: **exactly 7/7 and 9/9.** ✅
2. **`loop`'s `?=0/2` and `lin`'s `q=0/1`+`E=1/0`** residuals (`graphcmp-LIMITS.md:255`,
   §2) — re-measured verbatim. ✅ **The residual ledger is the one part of this tree that
   has not drifted.**
3. **All five of `REACH.md`'s "five new graphs" non-`flip` rows** (`alu 14/14`, `bit 10/10`,
   `where 8/8`, `move 22/22`) — re-measured, all exact. ✅
4. **`SPELLING.md`'s eight `i64_*` line numbers and `678` uses.** ✅
5. **`REACH-ARITH.md` walls 2 and 4.** ✅
6. **`agent-core.md`'s `libclang.bend` cause** (11 foreign laws) — **already correct**, per
   the brief. Not redone.
7. **`FLIPR.md`'s AFTER line and its `ops.py:558-560` / `ops.bend:1066` / `ops.bend:2486`.** ✅

**The pattern worth keeping: every number with a MACHINE-PRINTED denominator is current, and
every number a human typed into prose has aged.** `nodes=`, `ops-reached=`, `?=`,
`commutative-ops=` are printed on every run and were all correct; the prose tables are the
ones that rotted. **That is an argument for printing the claim, not for writing it down.**