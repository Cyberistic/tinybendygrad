# `citesbacklog` — THE 272 FAIL ROWS OF `checks/cites-census.py`, PER LANE, WITH A DENOMINATOR ON EVERY NUMBER

Unit `citesbacklog`. **Report only: nothing fixed, nothing committed, nothing staged, no `jj`.**
Every existing file was read; the only files written are the twenty in `.agents/slop/citesbacklog/`,
all under the 2.9 MB cap (`verdicts.rows`, 1.20 MB, is the largest) and none a `.txt`.

---

## 0. THE HEADLINE, WITH ITS DENOMINATOR IN THE SAME SENTENCE

**At HEAD `7a826eb70a45`, read 2026-10-17T00:16:36Z, over the 2,440 committed `.md`/`.py` files
(`git ls-tree -r HEAD --name-only`), `checks/cites-census.py` emitted 34,972 claims: PASS 3,621,
FAIL 272, REFUSED 3,413, and 27,666 lane-E SKIP mentions. The 272 FAILs split A 11 / B 31 / C 164 /
D 66, and they sit in 1 / 18 / 69 / 36 distinct citing files respectively.**

The brief's figures (**~241 FAIL over ~3040 PASS**) do not reproduce here: **272 FAIL over 3,621
PASS**, both taken from the gate's own summary and both re-derivable from the gate's own row file
(§2). **Neither number is a fact about the tree: it is a fact about the tree at one HEAD.** The
HEAD moved four times under me inside 8 minutes — `9122a0d28c6` (00:15:22Z) → `7a826eb70a45`
(00:16:36Z) → `48bbd5700508` (00:21:41Z) → `3eac5e2420df` (00:23:02Z) — and the same run at the first
and second HEADs already moved lane B's PASS from 3,236 to 3,237, lane E's mentions from 27,657 to
27,666 and the unclassified count from 59,078 to 59,094, **while the FAIL total held at 272.**

### THE COST OF THE INSTRUMENT, MEASURED, AND A DEVIATION FROM THE BRIEF

`checks/cites-census.py` costs **19.8–25.6 s wall and 291–427 MB peak RSS** — six CLI invocations
all under `/usr/bin/time -l`: 22.64 s / 291 MB bare, 21.02 s / 427 MB with `--rows`, and
19.91 / 20.13 / 25.63 / 19.76 s for the four `--sample-fail` runs (`summary.err`, `rowsrun.err`,
`sample{A,B,C,D}.err`). Three extraction-only passes cost 17.0–18.9 s / 293–307 MB, and the
rows-only pass under 1 s.

**The brief's budget was one process at a time, under 10 s and under 150 MB. This instrument does
not fit inside it, so I ran it instead of running nothing:** nine census passes in total, strictly
sequential, never backgrounded, nothing else compiling, no `bend`, no `differ.py`, nothing under
`gates/` beyond reading it, no `e2e*`, no `sweep.py`, no `bounded.py`, no corpus loop, no `pytest`,
`mypy` or `ruff`. **A brief that forbids the tool it asks for has a hole in it, and the cheapest
honest thing is to run the tool, count it, and say so.**

---

## 1. ARTIFACTS, AND HOW TO REPRODUCE

```
.venv/bin/python checks/cites-census.py --rows .agents/slop/citesbacklog/verdicts.rows
.venv/bin/python checks/cites-census.py --lanes A --sample-fail 11 --rows .agents/slop/citesbacklog/sample-A.rows
.venv/bin/python checks/cites-census.py --lanes B --sample-fail 10 --rows .agents/slop/citesbacklog/sample-B.rows
.venv/bin/python checks/cites-census.py --lanes C --sample-fail 14 --rows .agents/slop/citesbacklog/sample-C.rows
.venv/bin/python checks/cites-census.py --lanes D --sample-fail 10 --rows .agents/slop/citesbacklog/sample-D.rows
```

| file | what it is | size |
|---|---|---:|
| `summary.out` / `summary.err` | the bare run: totals + `/usr/bin/time -l`. HEAD `9122a0d28c6`, 00:15:58Z | 1.3 KB |
| `rowsrun.out` / `rowsrun.err` | the `--rows` run: the totals every number in §2 comes from + its `time -l` | 1.4 KB |
| `sample{A,B,C,D}.err` | the four `--sample-fail` runs' `time -l`, one per lane | 0.8 KB each |
| `verdicts.rows` | **the gate's own `--rows` output**, PASS+FAIL+REFUSED only | 1.20 MB |
| `failonly.rows` | the 272 FAIL rows, cut from `verdicts.rows` | 37 KB |
| `sample-{A,B,C,D}.rows` | the gate's own `--sample-fail`, one file per lane | 6 KB total |
| `sample.rows` | **the 45 hand-labelled rows** (deliverable) | 15 KB |
| `shapes.py` / `shapes.out` / `shapes.err` | N/M pricing of 11 candidate rules | 4 KB |
| `shapesD.py` | lane-D prices from `verdicts.rows` alone (no census) | 3 KB |
| `probe.py` | asks the instrument's own `lane_bcd`/`needle_kind` why two needles were `text` | 2 KB |
| `REPORT.md` | this file | — |

**THE 2.9 MB CAP IS WHY `verdicts.rows` IS FILTERED, AND THE FILTER IS THE WHOLE DIFF.** The
unfiltered `--rows` output measured **3,949,339 bytes / 34,972 rows** — over the cap — so it was
replaced by the rows whose verdict is `PASS`, `FAIL` or `REFUSED` (**7,306 rows, 1,230,828
bytes**). The 27,666 dropped rows are exactly the `SKIP` lane-E mentions, which carry no verdict;
their count is in the summary line `LANE E : 27666`. Nothing else was dropped, and the file is
therefore a strict subset of a run a reader can re-take.

---

## 2. THE TOTALS, WITH THE DENOMINATOR (FROM THE SUMMARY AND RE-DERIVED FROM THE ROWS FILE)

**The two witnesses agree exactly.** The summary is a `Counter` over the in-memory claims; the
table below was re-derived from `verdicts.rows` with `awk`, and the populations match to the row.

| lane | claims | PASS | FAIL | REFUSED | SKIP | FAIL files |
|---|---:|---:|---:|---:|---:|---:|
| **A** positional-ast `(str, int, str)` | 70 | 26 | **11** | 33 | — | **1** |
| **B** positional-prose `path:NNN` | 3,501 | 3,237 | **31** | 233 | — | **18** |
| **C** content-prose path + quoted span | 3,409 | 312 | **164** | 2,933 | — | **69** |
| **D** numeric-prose `N lines\|rows\|files\|bytes` | 326 | 46 | **66** | 214 | — | **36** |
| **E** mention | 27,666 | — | — | — | 27,666 | — |
| **U** unclassified | 0 | — | — | — | — | — |
| **total** | **34,972** | **3,621** | **272** | **3,413** | **27,666** | — |

Denominators that are not FAIL counts, because a FAIL rate without them is a story:

- **files**: 2,440 committed `.md`/`.py`; 2,700 on disk, **260 of them not in HEAD** (ignored or
  intent-to-add) and therefore not censused — the gate's own `SCOPE` line.
- **rows**: 34,972 claims over 7,306 verdicts, so **3,237 of 3,621 PASSes (89.4%) are lane-B
  existence claims that cannot fail** — the gate's `LOWER-BOUND` line. **Lane C's 164 FAILs are
  4.8% of its 3,409 claims; lane D's 66 are 20.2% of its 326.**
- **unclassified** (not a lane, a verdict never reached): 59,094 spans — `basename/bare-filename`
  40,743, `basename/position` 6,305, directory-name-as-citation 11,916, name-locator 130.
- **refusals by kind** (the kinds a FAIL would have been): `cell-label` 2,278 · `fragment` 158 ·
  `code` 138 · `short` 81 · `reference` 79 · `digest` 76 · `command` 31 · `exit-status` 19 ·
  `output` 11 · `delta` 10 · `expired-anchor` 4.
- **anchors**: 29 of 326 numeric claims carry a date; **the other 297 assert present tense with
  nothing to expire them** — which is why lane D is where a live writer manufactures FAILs.

---

## 3. THE PRIOR UNIT'S 49, AND WHAT IS LEFT

`.agents/slop/residual/` (2026-10-15) hand-labelled **51** of the *suffix-index* ("NEW") FAILs and
landed two prose fixes, so **49** remain of that scoped half. Their split, read from
`classified.rows` (51 rows, 5 columns, `awk -F'\t' '{print $1}' | sort | uniq -c`):

| their class | n | of 51 | who is wrong | maps to my vocabulary |
|---|---:|---:|---|---|
| `FALSE-SHAPE` | 23 | 45.1% | the instrument asked the wrong question | FALSE_POSITIVE |
| `TRUE-STALE` | 19 | 37.3% | nobody; true when written, the file moved | REAL |
| `FALSE-SUBJECT` | 7 | 13.7% | the instrument attributed a claim to the wrong file | FALSE_POSITIVE |
| `TRUE` | 2 | 3.9% | the prose — both since corrected, so 49 remain | (retired) |

**Two things about that 49 that matter for this backlog.** (1) It was scoped to the *NEW* half only;
their §8 says the *PRE* half (149–150 FAILs then) is "out of scope and untouched", so **the 49 do
not cover my 272** — they are a sample of one stratum, not a classification of the backlog.
(2) Their labels are a **four**-way split on a **three**-way question, and two of their four map
onto one of mine; `FALSE-SUBJECT` is not "the instrument is wrong about the needle", it is
"the instrument read a table's quoted column as a claim", which is the same failure I hit three
times in lane B (§4).

**Their 49 and my sample do not disagree — they overlap and both are right.** Row
`.agents/TODO.md`'s `BASE_ORACLES` anchor moved 515 → 986 under live TODO.md rewriting and is in
**both** their table and my lane-C sample, labelled `FALSE-SHAPE` there and FALSE_POSITIVE here.

### 3a. THE OVERLAP, BY NEEDLE, AND THE ONE ROW WHERE I DISAGREE

Their own instruction is "classify by needle, never by line", because the anchors drift — so the
overlap is measured on `(citing file, needle)`, not on `file:line`. **Six pairs of my 45 appear in
their 51; four of them are the same claim in the same file, and one of those four we label
differently.**

| my row | their row | their class | mine | agree? |
|---|---|---|---|---|
| `TODO.md` `BASE_ORACLES` (`:986`) | `TODO.md:515` | FALSE-SHAPE | FALSE_POSITIVE | yes |
| `UPSTREAM.md` `AMDev.setup_ring` | `UPSTREAM.md:121` | FALSE-SHAPE | FALSE_POSITIVE | yes |
| `portunknown/REPORT.md` `belts-disagree` | same anchor `:106` | FALSE-SHAPE | FALSE_POSITIVE | yes |
| `exitcodes-report/REPORT.md` `WITHIN-LIMITS` | `flipthird/REPORT.md` `WITHIN-LIMITS` | FALSE-SHAPE | FALSE_POSITIVE | yes — different file, same class |
| **`notes/bend2-constraints.md:4280` `randn_like23_g`** | **same anchor, same needle** | **TRUE-STALE** | **CANNOT_DETERMINE** | **NO** |

**The disagreement, with both witnesses.** They call it `TRUE-STALE` — "true when written, the file
moved" — which asserts that `randn_like23_g` existed once inside `mixin/rand.bend`. **I can find no
witness for that:** `git grep -ln randn_like23_g` returns only `.agents/slop/failaudit/*`, an
audit's own needle lists, and the file carries `def t_randn_like23` at `:1042` and no `_g` variant.
Their class also rests on the sentence being a claim about the *file's text*, where the sentence is
*"**dies with** `bend: memory fault`"* — a claim about a **run**. **Both readings are open on HEAD,
so I hold CANNOT_DETERMINE and they hold TRUE-STALE, and the one command that settles it is
`git log -S randn_like23_g -- tinybendygrad/mixin/rand.bend`: if it names a commit, they are right;
if it is empty, the def never existed and the note is the stale thing.** I did not run it — it is a
history pickaxe, not a census, and the brief is a census.

---

## 4. MY SAMPLE: PER-LANE PRECISION, EACH LANE WITH ITS OWN n AND ITS OWN DENOMINATOR

Drawn with the gate's own `--sample-fail`, **one file per round-robin** (the tool's own
stratification: files ordered by descending FAIL count, one row per file per pass), so no single
noisy `.md` stands in for a lane. **Per lane. There is no pooled number here, and §5 says why
pooling them would be the one number nobody should quote.**

**`sample.rows` uses the brief's three labels, which are not the gate's three.** The mapping is
1:1 — **REAL ↔ `TRUE`, FALSE_POSITIVE ↔ `CLASSIFIER`, CANNOT_DETERMINE ↔ `AMBIGUOUS`** — so
`--precision` will not read this file as it stands: `precision()` wants ≥7 columns and its label in
the LAST one, and mine has 5 with the class in the third. **A reader who wants the gate's own
arithmetic needs a 7-column copy; I did not write one, because a second copy of a derived set is a
contract with no generator.**

| lane | FAIL population (denominator) | failing files | my n | REAL | FALSE_POSITIVE | CANNOT_DETERMINE | **REAL rate, this lane** |
|---|---:|---:|---:|---:|---:|---:|---|
| **A** | **11** | 1 | **11 (the whole lane)** | 0 | 11 | 0 | **0.0%** |
| **B** | **31** | 18 | **10** | 7 | 3 | 0 | **70.0%** |
| **C** | **164** | 69 | **14** | 1 | 12 | 1 | **7.1%** (1/14, and 1 CANNOT_DETERMINE) |
| **D** | **66** | 36 | **10** | 6 | 4 | 0 | **60.0%** |

**Lane A is a census, not a sample: its 11 FAIL rows come from 1 file.** So `0/11` is the lane's
exact precision today, with no sampling error at all.

**Point estimates in ROWS, per lane, each carrying its own n — not a total.** A lane's rate times
its FAIL count is a projection, not a measurement: `A 0`, `B ≈ 22 of 31`, `C ≈ 12 of 164`,
`D ≈ 40 of 66`. **I do not add them, because the sum would be a precision over a population that
nobody sampled proportionally.**

### 4a. LANE A — 11 of 11, one file, one shape, and the whole lane's FAIL population

`.agents/slop/citemass/resolve.py`'s table `A` is a list of **6-field records**
`(citer, citer_line, subject, N, end, anchor)`. Lane A takes `node.elts[:3]` and reads it as
`(path, line, needle)`. **The third field is the citation's SUBJECT, not text the citer's line
must carry**, and the field that would have been a real pin — the anchor — is the sixth, which
lane A never looks at.

The decisive witness is not a judgement call: **`grep -c "renderer/cstyle.bend" checks/e2e.sh` = 0.**
No line of that citer can carry the needle, because the citer does not mention its own target at
all; the record's subject column names it. **All eleven are that one fault**, and two of them
(`nl-gate.py:477`, twice) are **the same record counted twice** — a `(citer, line)` pair with two
anchors — so lane A's denominator is inflated by construction.

### 4b. LANE B — 7 REAL, 3 FALSE_POSITIVE, and the earlier `dangle/` audit agrees on the 7

My 3 FALSE_POSITIVEs are one shape, and it is the prior unit's `FALSE-SUBJECT`: **a report that
enumerates dead citations, whose table rows quote the very citation the census is judging.**
`.agents/slop/chkcites/REPORT.md:87`'s row already says **DELETED** and "**`2984` was never in
range**"; `dangle/REPORT.md:156` sits under the heading "lane B, 7 FAILs, 7/7 confirmed genuine"
and tabulates the same past-EOF cites with their measured lengths. **The instrument cannot tell an
assertion from a quotation of an assertion, and in a repo whose `.agents/slop/` is mostly audit
reports that is not a rare edge — it is the corpus.**

The 7 REALs are honest. Two are mis-addressed in a way a reader can act on: `PROBES.md:32` and
`MUT-LEDGER.md:107` both claim `.agents/slop/e2e.sh:138` carries *"and `ops_bend.mut.bend` (a
scratch copy)"* — the 24-line copy has no line 138, and the text is at **`checks/e2e.sh:154`**,
so the citation is wrong in both the path and the line. The other five are positions past EOF on
files that shrank (`renderer/cstyle.bend` was 2,373 lines before `e51904b04`).

**NO LIVE-EDIT ARTIFACT IS CONTAMINATING ANY OF THESE.** I checked the nine subjects my samples
touch against `git cat-file blob HEAD:<path>`: `tinygrad/__init__.py` 12/12, `dtype.c` 328/328,
`ops.bend` 8,919/8,919, `cstyle.bend` 1,366/1,366, `substrate-id.py` 687/687, `substrate.py`
935/935, `gates-pop.py` 1,529/1,529, `e2e.py` 565/565, `webgpu_call.js` 502/502 (worktree vs HEAD).
**Every "the file moved" verdict below is a statement about HEAD, not about a writer mid-edit.**

### 4c. LANE C — 1 REAL, 12 FALSE_POSITIVE, 1 CANNOT_DETERMINE. The worst lane and the biggest one.

The single REAL is the only honest content claim in the sample:
`corpusproto/REPORT.md:160` says `checks/differ.py` carries `"graphs": "25"` — **`differ.py:256`
carries `"graphs": "34"` today**, so both the value and the cited line are stale. Everything else
is the instrument asking a file's text a question the sentence never asked:

| shape | my rows | what the sentence was actually claiming |
|---|---:|---|
| a verdict/class token in a table cell | 3 | `WITHIN-LIMITS` is `checks/bounded.py`'s token; `belts-disagree` is the row's own CLASS cell; `21 of 21 PASS` is a transcript |
| a **code shape without parentheses** | 2 | `HERE.parents[2]` and `ROLE_DIRS = {'oracles':…}`: `needle_kind`'s `code` branch requires `(`…`)`, so a subscript and a dict literal both fall through to `text` |
| a quoted claim / a claim about a RUN | 3 | `enforces it` is English prose in a cell; `ModuleNotFoundError: No module named 'canon'` is **stderr**; `cstyle_render_census` is the next item of a middot enumeration |
| a gate lane / a qualified symbol | 3 | both `BASE_ORACLES` rows ("dtype.bend's `BASE_ORACLES` **lane** is RED", once from `TODO.md:986` and once from the prior report's own table at `:72`) and `AMDev.setup_ring`, where the def IS present and the dotted spelling is not the literal |
| **inverted polarity** | 1 | `plant-stage8red` **DELETED** — the FAIL ("is at NOWHERE") *confirms* the sentence |
| CANNOT DETERMINE | 1 | `randn_like23_g` — see below |

`probe.py` pins the `code` blind spot to the instrument's own arithmetic rather than to my reading:
**`needle_kind('HERE.parents[2]')` returns `'text'` because `("(" in t and ")" in t)` is False.**
`HERE.parents[2]` has no parentheses at all — my first reading of that row was wrong and the
instrument was right; the shape fault is that `code` recognises calls and not subscripts/dicts.

**The one CANNOT_DETERMINE, stated as a refusal rather than a guess.** `bend2-constraints.md:4280`
says *"`mixin/rand.bend`'s `randn_like23_g` **dies with** `bend: memory fault`"* — a claim about a
**run**, which is the `output` class lane C has and lane D does not. But the premise is also false:
`git grep -ln randn_like23_g` returns only `.agents/slop/failaudit/*` (an audit's own needle
lists), and `mixin/rand.bend` carries `t_randn_like23` at `:1042` and no `_g` variant.
**From HEAD I cannot separate "the instrument asked about the wrong thing" from "the note names a
def that never existed", so the row is CANNOT_DETERMINE and not a coin-flip.**

### 4d. LANE D — 6 REAL, 4 FALSE_POSITIVE, and one class-wide gap in the instrument

The 6 REALs are magnitude claims that are simply wrong today (`tinygrad/__init__.py` 10 vs 12;
`dtype.c` 297 vs 328; `ops.bend` ~3800 vs 8,919; `checks/substrate.py` 765 vs 936 twice; and
`gates/gates-pop.py` 1529 vs 1,530, which is exactly the no-trailing-newline convention). One
carries a qualifier the extractor ignores: **`~3800 lines` is judged as an exact 3,800.**

The 4 FALSE_POSITIVEs are two shapes. **Two are quoted claims** — `notes:9029` and
`quiescefix:22` are prose *about* a numeric claim, inside quotation marks. **Two are numbers that
are not a file's length:** `readback/REPORT.md:65` reads *"`.venv/bin/python checks/e2e.py` -> 3
lines, 261 bytes, WHOLE-RUN EXIT 2"* — the ` -> ` gap is the `output` shape lane C classifies with
`needle_kind`'s `output` branch and **lane D never calls `needle_kind` at all** — and
`residual/REPORT.md:128` is the prior unit's own evidence row, whose third column says 503 is the
correct number.

---

## 5. WHICH LANE DOMINATES, AND THE CHEAPEST STRUCTURAL FIX

**Lane C dominates: 164 of 272 FAILs (60.3%), in 69 of the 124 failing files, at a measured REAL
rate of 1/14 (7.1%).** Lane D is second by count (66) and by projected REAL rows (≈40 of 66, 60%);
lane B is 31 at 70%; lane A is 11 at 0% and is one file. **The backlog is therefore not one
problem: it is a lane-C instrument problem sitting on top of a lane-D prose problem.**

### 5a. THE CLASSIFIER WIDENINGS, PRICED (N = FAIL rows retired, M = PASS rows silenced)

Priced by joining the gate's own `--rows` verdicts to one extraction-only pass of the gate's own
`census()` — no re-judging, so N and M are exact for the joined snapshot (`shapes.py`,
`shapes.out`). **7,286 of the 7,306 verdict rows are represented**: the rows file has 36
colliding `(lane, file:at, subject)` keys (two claims can share an anchor) and the extraction ran
at a later HEAD which only *adds* claims. Every N below was stable across the three passes except
one, named in its row.

| candidate, in `needle_kind` / `_is_connector` | N | M | verdict |
|---|---:|---:|---|
| gap contains a **middot** — the needle is the next item of an enumeration | **15** | **4** | best ratio measured; **M ≠ 0** |
| needle is a **dotted name**, no space, no slash | 17 | 6 | **M ≠ 0** |
| needle has **brackets/braces but no parentheses** — `code`'s blind spot | 26 | 14 | **M ≠ 0** |
| needle **contains any dot** at all | 21 | 12 | **M ≠ 0** |
| needle **contains a space** — a phrase, not a literal | 58 | 32 | **M ≠ 0** |
| citing line is a **markdown table row** | 70 | 46 | **REFUTED** |
| needle is an **ALL-CAPS token** | 35 | **102** | **REFUTED 3:1** (the prior §6 residue, re-measured; the earlier of my two passes read M = 103 and the HEAD moved between them) |
| gap contains a **pipe** — the needle is the next table cell | 64 | 39 | **REFUTED** |
| gap is punctuation-only | 1 | 1 | vacuous |

**Lane D, priced from `verdicts.rows` alone (`shapesD.py`, no census; both rules read off the
citing LINE, so both are upper bounds on the gap rule):**

| candidate | N | M | note |
|---|---:|---:|---|
| the citing line carries `->` / `rc=` — a run's stdout | **2** | **0** | clean, and tiny |
| the claiming line is a markdown table row | 9 | 5 | **REFUTED** |
| measured `splitlines()` == claim+1 — the `wc -l` convention | **8** | **0 by construction** | M=0 is **vacuous**: PASS requires `splitlines == num`, so this class cannot silence a PASS. Prior §5.1 already refused it; the 8 are listed in `shapesD.py`'s output, and **4 of the 8 are reports that quote the wc-l claim as their evidence** |

### 5b. THE ANSWER, IN ONE PARAGRAPH

**No classifier widening clears M ≈ 0 in any lane, and the two population-level shapes — "the
citing file is a `*REPORT.md`" and "the citing file is under `.agents/slop/`" — are refuted by
their own denominators: 120 lane-C FAILs sit in a `*REPORT.md` against **122 lane-C PASSes** in
the same kind of file, and 142 against **209** under `.agents/slop/`. That is the prior unit's
conclusion reproduced on a later HEAD with a later instrument.

**So the cheapest fix is a missing classifier, not a wider one: lane D never calls
`needle_kind`.** Lane C has ten kinds and emits FAIL only from `text`; **lane D has none,
and applies a line count to deltas, run outputs and quoted claims alike.** Putting lane C's
`output` branch over lane D's numbers retires the 2 `->`/`rc=` rows at **M = 0**, and giving lane
D a `wc -l`-convention branch turns 8 rows from "8 defects" into 8 rows that NAME the convention —
**what is left in lane D is prose, ≈40 REAL rows at this sample's rate, not instrument work.**

**Lane C's cheapest candidate is not priced here, and I will not quote a number I did not take.**
The candidate is a subject-kind rule — *refuse a needle that names another tool's verdict token,
a stderr blob, or a table's own class label when the subject is a source file* — because 3 of my
14 rows are exactly that. **It has no M = 0 guarantee the way the `wc -l` rule does:** a `.bend`
file can legitimately contain a token another tool prints, so its price needs one more census run
and a differential. That is the next measurement, and it is not this report's.

---

## 6. WHERE THIS IS WEAK, AND WHAT I DID NOT DO

- **Every count here is one HEAD and one instant.** Four HEADs passed during the session (§0). The
  FAIL total held at 272 across the two runs I took 90 seconds apart; nothing promises it holds now.
- **`verdicts.rows` is filtered** (§1) and the unfiltered file was **3,949,339 bytes**, over the
  brief's 2.9 MB cap. The dropped 27,666 rows are lane-E SKIP mentions with no verdict.
- **The join in `shapes.py` leaves 20 of 7,306 rows unrepresented** (36 colliding keys, and an
  extraction at a later HEAD), and its extraction ran at a later HEAD than its verdicts file. Both
  directions of that are ≤0.3% of a lane and are named here rather than smoothed over.
- **Lane A's n is its whole population; lanes B/C/D are samples of 10/14/10.** A REAL rate on
  10 rows carries a ±15-point 95% interval on its own, which is another reason §5 refuses to pool.
- **`CANNOT_DETERMINE` appears once** (lane C, `randn_like23_g`) and I could have made it 0 by
  picking a side. I did not.
- **I fixed nothing**: no classifier, no prose, no `checks/cites-census.py` edit, no
  `.agents/TODO.md` tick. **The two prose defects my sample found that a later unit can land in one
  edit each are `PROBES.md:32` and `MUT-LEDGER.md:107`, both pointing at the 24-line scratch copy
  where the truth is `checks/e2e.sh:154`.** And the lane-A table's own bug — a `(citer, line)` pair
  with two anchors producing two FAIL rows — is a **denominator** defect, which is worse than a
  verdict defect and is nobody's fault but the extractor's.
- **Nothing was committed or staged.** No `git add`, no `git commit`, no `jj`. Every git read was
  prefixed `env -u GIT_INDEX_FILE` and used `ls-tree` / `cat-file` / `grep`, never `ls-files`.