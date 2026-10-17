# DECISION: should `prose-basename-citation` be a POSITIVE finding?

**MEASURED 2026-10-17T00:15:22Z–00:18:40Z. Tree HEAD `7a826eb70a4599392e229b750782a5e9d76a2f24`**
(session start HEAD was `9122a0d28c60055d45c07566715823af2f208680`; the tree moved 53 s into the
session and had not moved again by the end — `git log 9122a0d2..7a826eb70a` is one commit,
`.agents/TODO.md`, +58 lines).

**VERDICT: RELABEL** — `verdict="POSITIVE"` → a non-verdict class (`AMBIGUOUS`), with the audit's
R6 non-dot-stem rule folded in. **SPLIT is measured and rejected below** (§5.4): its POSITIVE
branch scores **0.250** against the audit's own hand labels where the branch it *excludes* scores
**0.281**. KEEP is rejected because the verdict is a literal in the source.

Read this file's §2 first: **`census.py` REFUSED at this HEAD and wrote nothing.** Every number
below that I attribute to a run is attributed to a run that declared itself un-reportable, and I
say so each time.

---

## 1. THE TOTALS AT MY HEAD, AND THE MOVEMENT

### 1.1 The census REFUSED. This is the headline fact.

I ran `census.py` **once**, with `--rows` pointed at this directory so the author's
`findings.rows` could not be overwritten:

```
HEAD 7a826eb70a4599392e229b750782a5e9d76a2f24
population : 1878 committed .py, 562 committed .md, 7386 committed paths -- every one from `git ls-tree -r HEAD`
module-level literals examined : 101323  (from 1410 .py parsed; 468 dropped by the column-0 grammar gate)
CANDIDATE SITES : 314   extension-set=50  module-attr-table=3  prose-basename-citation=253  regex-anchor-set=2  single-base-resolver=6
bare basenames cited : 4341, ambiguous 253
VERDICTS : NEGATIVE=30  POSITIVE=258  UNKNOWN=26
SELFCHECK REFUSED -- nothing written:
  pos1 anchored path regex: no POSITIVE regex-anchor-set site matching checks/repro-paths.py
rc=3
```

Transcript: `census-run.out`, `census-run.time`. **Real 8.97 s, user 7.39 s.** `census-run.rows`
**does not exist** — `census.py:525-529` returns 3 before opening the file.

**Why, and it is not my doing.** `checks/repro-paths.py:64` at HEAD is

```python
REF = re.compile(r"(?<![\w/.])((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
```

A negative lookbehind, not the `(?:^|…)` delimiter class `widened()` (`census.py:174-179`) needs.
So `regex-anchor-set` is now **2** sites, the class's known positive #1 is no longer an instance of
the class, and control `pos1` is **unsatisfiable**. **The instrument's first real falsification
happened and it was correct**: a gate was fixed, the census noticed. A control asserting a defect
that has been repaired is a control that must fail forever.

**So at this HEAD `census.py` cannot produce a rows file at all.** There is no
"current findings" to relabel in the running sense; the newest rows artifact that exists anywhere
is the author's `.agents/slop/onespelling/findings.rows`, **307 rows** (POSITIVE 254 / NEGATIVE 27 /
UNKNOWN 26), written at HEAD `037d5d536e` 2026-10-16T13:21:36Z. Untouched by me: sha256
`3718313d…`, mtime Oct 16 16:22, unchanged across the whole session.

### 1.2 Movement. Three readings, and the instrument is not stable.

| | author REPORT `037d5d536e` 13:21:36Z (307 rows) | precision audit `03500a2620` 14:35:45Z (311) | **mine `7a826eb70a` 00:15:40Z (314)** | Δ vs author |
|---|---|---|---|---|
| committed `.py` | 1 835 | 1 845 | **1 878** | **+43** |
| committed `.md` | 551 | 554 | **562** | **+11** |
| committed paths | 7 308 | 7 326 | **7 386** | **+78** |
| literals examined | 100 951 | 101 062 | **101 323** | **+372** |
| `.py` parsed | 1 369 | 1 379 | **1 410** | **+41** |
| dropped by grammar gate | 466 | 466 | **468** | +2 |
| CANDIDATE SITES | 307 | 311 | **314** | **+7** |
| `prose-basename-citation` | 248 | 251 | **253** | **+5** |
| `extension-set` | 47 | 48 | **50** | +3 |
| `regex-anchor-set` | 3 | 3 | **2** | **−1 (fixed)** |
| `module-attr-table` | 3 | 3 | 3 | 0 |
| `single-base-resolver` | 6 | 6 | 6 | 0 |
| POSITIVE | 254 | 257 | **258** | **+4** |
| NEGATIVE | 27 | 28 | **30** | +3 |
| UNKNOWN | 26 | 26 | **26** | 0 |

**`prose-basename-citation` grew 5 rows in 11 hours while the tree grew 78 paths** — it is
roughly proportional to tree growth, which is what a census of prose should do, and it means **the
count is a property of the tree's size, not of its defects.**

### 1.3 The kind × verdict cross-tab, which the census does not print

```
kind                        n   POSITIVE  NEGATIVE  UNKNOWN
extension-set              50      0         27        23
module-attr-table           3      0          3         0
prose-basename-citation   253    253          0         0     <-- verdict is a LITERAL (census.py:451)
regex-anchor-set            2      2          0         0
single-base-resolver        6      3          0         3
TOTAL                     314    258         30        26      (cross-check: 253+2+3 = 258 POSITIVE)
```

`prose-basename-citation` is **253 of 314 candidate sites (80.6 %) and 253 of 258 positives
(98.1 %)**, and it is the only kind with no `NEGATIVE` and no `UNKNOWN` branch.

### 1.4 A defect I hit while measuring, and it is in the instrument's own labelling

My independent recomputation of the census's cited denominator gives **4 342** where the census
printed **4 341** on the same nominal HEAD. Cause, measured not guessed:

- `census.py:430` `build()` reads the tree with `git ls-tree -r HEAD`; **`census.py:513` prints
  `HEAD` *after* `build()` returns.** The commit `7a826eb70a` landed between those two reads.
- That commit changed `.agents/TODO.md` (+58 lines). The added lines cite one new token matching
  `[\w.+-]*\.[A-Za-z0-9]+`: **`.py`**.
- `.py` is **0 tracked files**' basename, so it raises `cited` 4 341 → 4 342 while `ambiguous`
  stays **253**. Exactly the 1-token gap.

**`census.py`'s printed HEAD does not name the tree its numbers came from.** Both revisions have
identical path/md/py counts (7 386 / 562 / 1 878), which is why the drift is invisible to every
count the census prints. Evidence: `denom-diff.out` (whole-text and per-line `BACKTICK` sets are
identical at 4 342, so the sets agree and the census's label is the wrong one).

---

## 2. WHAT RELABELLING DOES — THE MEASURED EFFECT

**RELABEL = the 253 rows stop being verdicts and become a census count.** At my HEAD the headline
becomes:

| | today | after RELABEL | after RELABEL + R6 | after SPLIT (rejected) |
|---|---|---|---|---|
| **POSITIVE (findings)** | **258** | **5** | **5** | **27** |
| **AMBIGUOUS (not findings)** | 0 | **253** | **250** | **231** |
| NEGATIVE | 30 | 30 | 30 | 30 |
| UNKNOWN | 26 | 26 | 26 | 26 |
| CANDIDATE SITES | 314 | 314 | 311 | 314 |

The surviving **5** are `regex-anchor-set=2` and `single-base-resolver=3` — exactly the kinds that
have a probe, a `NEGATIVE` branch and a failure mode. At the author's HEAD the same change gives
**6 findings + 248 suggestions** (POSITIVE 254 → 6).

### What a reader can no longer conclude from the number

1. **They can no longer conclude there are 258 things to fix.** They can conclude there are **5**,
   and that 253 more bare basenames are ambiguous.
2. **They can no longer treat the headline as a to-do list of size 258.** This is the concrete
   harm: the census's own REPORT frames its POSITIVE section as the defect list, and 98.1 % of it
   was one shape whose verdict could not have been otherwise.
3. **They can no longer infer that ambiguity is a defect rate.** Nothing measures whether a given
   reader was misled — the census says so itself (author REPORT, "WHAT I COULD NOT DETERMINE":
   *"Severity of the 248 basename citations"*). A count labelled POSITIVE reads as a rate;
   labelled AMBIGUOUS it reads as what it is, a count of collisions that exist.
4. **They lose cross-run comparability of the headline** — and that is the correct loss, because
   253 of 258 was tracking tree size (§1.2).
5. **They can no longer be misled by the audit's own pooled figure.** `.agents/slop/onespelling-precision/REPORT.md:36-38`
   records that *"There is no pooled number, and one is not available"* and that a pool would be
   *"`0.28` wearing the costume of a measurement about 257 things."* After the relabel the pool is
   5 rows and no costume is needed.

### What the reader GAINS

The **SUGGESTED/AMBIGUOUS count is well-founded and carries its denominator**, which is more than
the POSITIVE count ever did: **253 ambiguous of 4 342 distinct bare basenames cited, over 14 303
citing lines, in 562 committed `.md`** (all measured at `7a826eb70a`, `split.out`). That is a real
census result. "258 defects" was not.

---

## 3. BOTH CASES, AT EQUAL SERIOUSNESS

### 3.1 THE CASE FOR KEEPING POSITIVE

**It is true, and the tree says so itself.** A bare `` `differ.py` `` in prose is answered to by
**4 tracked files**; `gatekit.py` by 3; `extract.py` by 2; `census.py` by **27**; `REPORT.md` by
**219**; `dtype.bend` by 3. The collision is a fact about the tree, computed from
`git ls-tree -r HEAD`, not a guess. Collision histogram over the 253:

```
2:144   3:41   4:17   5:9   6:12   7:2   8:2   9:3   10:4   11:6   13:4   14:2   15:1
22:1    27:1   31:1   56:1  65:1   219:1
```

**The harm is real and concrete.** A reader who greps `REPORT.md`, opens the wrong one of 219, and
writes confidently wrong conclusions about this project has been harmed, and the census is the
only instrument that counts that situation.

**A reader may not know.** The audit's strongest counter to "experts are never misled" is that
this tree is written *for agents*, and `AGENTS.md` is explicit that a path named without a
directory is unresolvable. If the audience includes a reader who has not memorised 219 report
files, the bare basename is a genuine defect at the point of reading.

**The kind is an instance of the CLASS, and the class is the deliverable.** `census.py:6` states
the shape — *"a BARE BASENAME in prose / `differ.py` is four tracked files"* — and that statement is
**still true** after any relabelling. Relabelling the verdict does not make the shape go away, and
an instrument that silently stopped counting a real instance of its own class would be lying by
omission.

**The verdict column is not the only output.** Each row carries
`evidence = "<n> tracked files share this basename: <first 4 paths>"`. A reader who reads the
evidence gets the truth. So the defect is narrow — **the HEADLINE counts the row as a finding** —
and the fix should be narrow too. That is exactly why the answer is RELABEL and not DELETE.

### 3.2 THE CASE AGAINST

**A count that cannot be false is not a measurement.** `census.py:451-454` writes the verdict into
the literal:

```python
451    rows += [dict(site=f"{PROSE_EXT}:{b}", kind="prose-basename-citation", verdict="POSITIVE",
452                  second_spelling_found="yes", spelling="backtick token",
```

There is no `probe_prose()`, no `NEGATIVE` branch, no threshold, no `--selfcheck` that can fail for
this kind. **It supplies 98.1 % of a census's findings while being incapable of being false.**
`AGENTS.md`'s doctrine 2 has a name for this: *"`DEAD` is not a zero and not a pass … it ran and
emitted nothing"*. A verdict that is a constant is not a verdict; and per the same doctrine,
*"`SKIP IS NOT PASS`"* cuts both ways — **an instrument that emits a verdict it did not compute is
worse than one that emits nothing.**

**It suppresses attention from the kinds that can err.** Of the 5 surviving findings, 3 are
`single-base-resolver` — and the audit measured **byte-identical evidence** on all three, because
`probe_base` computes `lost` from the CORPUS, not from the SITE. That is a defect *inside* a
probed kind, sitting behind 253 rows of unprobeable volume. A headline of 258 tells a reader to
start at the biggest bucket. A headline of 5 tells them to start at the only five things that can
be wrong. **The relabelling does not fix `probe_base`'s evidence; it moves it into view.**

**The volume is not measuring severity, it is measuring tree size** (§1.2: +5 rows, +78 paths).

**One third of the census's falsification surface is unfalsifiable by construction.** `CONTROLS`
(`census.py:466-473`) has **six** entries and **three** are `prose-basename-citation` POSITIVE
(`differ.py`, `gatekit.py`, `extract.py`). A control asserting a constant cannot fail. At my HEAD
the tally is starker:

| control | verdict asserted | can it fail? |
|---|---|---|
| `pos1 anchored path regex` | POSITIVE | **it DID fail — REFUSED** |
| `pos2 differ.py` | POSITIVE | **no** (verdict is a literal) |
| `pos2 gatekit.py` | POSITIVE | **no** |
| `pos2 extract.py` | POSITIVE | **no** |
| `pos3 single base` | POSITIVE | yes |
| `neg live table has companion` | NEGATIVE | yes |

**Two of six controls can fail; three cannot; one does and takes the instrument down.** The audit
is right that *"`md:differ.py` is one of the census's own six CONTROLS and I read it FALSE"* — 3 of
its 4 tracked collisions are shadow copies under `corpuswire/tree/` and `figure2/plant/{broken,real}/`.

**And the class's own doctrine says what to do.** `AGENTS.md` doctrine 1: *"A population is (a) a
generator's own declaration … or (b) a directory walk … **A BASENAME SHAPE, A SUFFIX SET, AND A
HAND LIST ARE NOT POPULATIONS. An instrument that cannot see its population cannot be wrong,
because it cannot be anything.**"* Applied one level down: **a verdict that cannot be computed
cannot be a finding.** The audit's R1 states the remedy — *"it should print `AMBIGUOUS n=251` with
no verdict … An instrument that cannot decide should say so rather than emit a verdict it did not
compute."*

### 3.3 Where they actually conflict

The two cases conflict on exactly one question: **does the row belong in the census at all?** The
evidence says yes — the collision is real, computed, and carries its denominator. The label
`POSITIVE` says the row is a defect, and the evidence says nothing supports that. So **keep the
row, change the label.** That is RELABEL, and it is the only option in the brief that keeps both
of the cases' legitimate content.

---

## 4. THE CONCRETE MINIMAL CHANGE, AND WHAT BREAKS

### 4.1 Exact lines

**(a) The verdict — `census.py:451`, one token.**

```python
-    rows += [dict(site=f"{PROSE_EXT}:{b}", kind="prose-basename-citation", verdict="POSITIVE",
+    rows += [dict(site=f"{PROSE_EXT}:{b}", kind="prose-basename-citation", verdict="AMBIGUOUS",
```

Nothing else reads `verdict` for this kind. `census.py:522` counts verdicts with a `Counter`, so
`AMBIGUOUS=253` appears in the `VERDICTS` line with no edit. `census.py:520-521`'s
`ambiguous {sum(1 for r in rows if r['kind'] == 'prose-basename-citation')}` is **kind**-based,
so it is unaffected and stays truthful. `census.py:536-538` writes the verdict verbatim; the rows
file has no schema constraint on the column.

**(b) The three prose controls — `census.py:468-470`,** or the census refuses four times instead of
once:

```python
468    ("pos2 bare basename differ.py",  "prose-basename-citation", "AMBIGUOUS", "differ.py"),
469    ("pos2 bare basename gatekit.py", "prose-basename-citation", "AMBIGUOUS", "gatekit.py"),
470    ("pos2 bare basename extract.py", "prose-basename-citation", "AMBIGUOUS", "extract.py"),
```

**This is the honest cost and it should not be hidden: these three controls become assertions that
the census *emitted a class it did not decide* — which is a real, falsifiable control, and is
strictly better than asserting a constant.** They should be *relabelled*, not deleted. But note they
still cannot detect a *wrong* ambiguity count, only a missing one.

**(c) R6, the one mechanical discharge that survives scrutiny — `census.py:423-424`.** Require a
non-dot stem, so a token that **is** an extension or a directory cannot be matched against
`os.path.basename`:

```python
-             if "/" not in t and re.fullmatch(r"[\w.+-]*\.[A-Za-z0-9]+", t)}
+             if "/" not in t and re.fullmatch(r"\w[\w.+-]*\.[A-Za-z0-9]+", t)}
```

**Measured effect: exactly 3 rows, 178 citing lines removed** (`split.rows`):

| token | tracked collisions | citing lines | what it is |
|---|---|---|---|
| `.agents` | 2 | 13 | **a directory** |
| `.out` | 2 | 74 | **an extension** |
| `.gitignore` | 13 | 91 | **a convention name** |

None of the three is a filename, so none is an instance of *"a bare basename that several tracked
**files** answer to"*. This is `rx_extensions`' own docstring warning (`census.py:212-213`:
*"charging a directory for being one"*) reproduced one level up, and it is the same 3 rows the
audit's FALSE-category (a) found by hand. 253 → **250**. It touches none of the three controls.
**It is also the only proposed rule in this report that is a plain rule, applied before the
verdict, and cheap.**

**(d) The docstring, or the instrument contradicts itself — `census.py:6`.** *"a BARE BASENAME in
prose / `differ.py` is four tracked files"* is still true as prose and is no longer a reported
instance. Either amend it to say the kind yields a census count rather than a verdict, or the
header and the `VERDICTS` line disagree.

**(e) Prerequisite, and it is not part of this change: `pos1`.** `checks/repro-paths.py:64` was
repaired. `CONTROLS[0]` must be replaced with a live instance of `regex-anchor-set` or dropped with
its reason recorded, or `census.py` stays REFUSED regardless of (a)–(d).

### 4.2 What BREAKS — named, not implied

1. **`census.py` REFUSES harder, not less.** Today 1 failure (`pos1`). With (a)+(b): **4**. With
   (a)+(b)+(e): **1**, the `pos1` one. **The relabelling alone does not restore the instrument**,
   and anyone expecting `census.py` to run afterwards will be disappointed.
2. **`.agents/slop/onespelling/REPORT.md` (author, at `037d5d536e`) — three places go stale:**
   the header block `VERDICTS : NEGATIVE=27 POSITIVE=254 UNKNOWN=26` → `AMBIGUOUS=248 NEGATIVE=27
   POSITIVE=6 UNKNOWN=26`; the heading **`### POSITIVE — 254`** → `### POSITIVE — 6`; and the
   subsection *"**`prose-basename-citation`, 248 of 4228 cited bare basenames, and this is known
   positive #2**"* must **move out of** the POSITIVE section into a new AMBIGUOUS section. The
   class table at the top drops from 4 named instances to 3. The line *"the severity is not uniform
   and the collision count is in the evidence"* stays true and becomes *more* apt.
3. **The precision audit's denominators — this is the largest break.**
   - Its headline *"257 POSITIVE findings, of which I could not confirm 41 of the 46 I sampled"*
     → **5** POSITIVE. Every downstream pooled figure changes: its §4 *"69 + 1 + 2 = 72, CI
     [43,112]"* becomes the 3 true of 6 in the two probed kinds.
   - Its table row *"`prose-basename-citation` | 251 | sampled 40 | TRUE 11 | precision 0.275"*:
     the **251 becomes 0 POSITIVE**, and the 0.275 becomes a statement about the audit's
     labelling standard rather than about the census's verdict. That is a *gain* — §6 of that
     report says its standard has one opinion in it and no inter-rater figure, which is only a
     tolerable position for a class carrying **no** verdict.
   - **Its §2 sampling rule becomes unrunnable as written.** It takes *"every POSITIVE row of the
     kind"* and stratifies by claiming file; after the relabel that set is **empty**. The audit
     must re-target its sampler at `AMBIGUOUS` rows, re-derive the stratum, and re-report
     `0.275` — so **its 40 hand labels remain valid but its 251/257 denominators do not**, and any
     re-run is a new measurement, not a citation of the old one.
   - Its §3.4 *"two kinds with no denominator"* table gains a third peer:
     `prose-basename-citation` has no denominator *and* no verdict.
   - Its §0 line *"251 of the 257 positives (97.7 %) are ONE kind"* becomes false; *"0 of 5"* is
     the true replacement.
4. **Nothing else.** `git grep 'findings\.rows\|onespelling' HEAD` over `*.py *.sh *.md` returns 9
   hits; `gates/citations-census-gate.py:130,139` refers to **its own**
   `gates/citations-census-findings.rows` and `.agents/slop/shapecensus/` has **its own**
   `findings.rows`. **No gate, check or instrument consumes
   `.agents/slop/onespelling/findings.rows`.** Blast radius is `census.py`, its own REPORT.md, the
   precision audit, and prose in `.agents/TODO.md` / `claimaudit2` / `shapecensus`.

---

## 5. THE SPLIT, MEASURED (and rejected)

### 5.1 The exact test

A citing line is **OPERATIONAL** when it is inside a fenced code block or an indented code block:

- **FENCED** — between an opening fence (` ``` ` or `~~~`, ≤ 3 leading spaces, optional info
  string) and the next line that is only that fence character, ≥ as long, no info string.
- **INDENTED** — begins with a tab or 4+ spaces, is not inside a fence, and the **previous line is
  blank** (markdown requires it; without it this is list continuation).

**Branch A (POSITIVE)** = the basename has ≥ 1 OPERATIONAL citing line. **Branch B (SUGGESTED)** =
every citing line is ordinary prose. The census's own population rule is reused verbatim, not
re-invented, so this is the census's population. Instrument: `split.py` → `split.rows` (253 rows,
10 TAB columns), `split.out`.

### 5.2 The row counts

```
SPLIT branch A  POSITIVE  (>=1 fenced or indented citing line) : 22
SPLIT branch B  SUGGESTED (every citing line is ordinary prose) : 231
cross-tab (branch, any citing line carries a "/") : POSITIVE/slash=0: 3  POSITIVE/slash=1: 19
                                                  SUGGESTED/slash=0: 81  SUGGESTED/slash=1: 150
citing lines inside the ambiguous set : 3303  (fenced 37  indented 8  prose 3258)
```

Denominator: **4 342 distinct bare basenames cited, 14 303 bare-basename citing lines, 562
committed `.md`** at `7a826eb70a`. Headline after SPLIT: **27 findings + 231 suggestions**
(5 probed + 22 operational).

### 5.3 The margin, which is where SPLT dies

```
branch A : 1653 citing lines, 37 fenced + 8 indented = 45 operational lines = 2.7% of the branch
branch B : 1650 citing lines, 0 operational
```

The two branches carry **almost identical citation mass (1 653 vs 1 650)** — so "is this basename
ever cited operationally" is nearly independent of how much prose cites it. It is splitting a
population roughly in half on a coin-flip-like property, not on severity.

**11 of the 22 branch-A rows rest on exactly ONE operational line**, half of them out of hundreds:

| row | collisions | citing lines | operational margin |
|---|---|---|---|
| `fold.bend` | 3 | 240 | **1** |
| `device.bend` | 2 | 80 | **1** |
| `D0-run-summary.txt` | 2 | 85 | **1** |
| `census.py` | 27 | 63 | **1** |
| `spec.bend` | 3 | 33 | **0 fenced**, 1 indented |
| `helpers.bend` | 2 | 211 | **0 fenced**, 4 indented |
| `gatekit.py` | 3 | 24 | **1** |
| `differ.py` | 4 | 119 | 3 fenced + 1 indented |

Two rows are POSITIVE with **zero** fenced lines. And `.gitignore` — a *convention name*, not a
file — is in branch A. **SPLIT's operational test does not even check that the token is a filename.**

Branch A does not correlate with ambiguity magnitude either: 2-collision rows are 54.5 % of branch A
(12/22) and 57.1 % of branch B (132/231).

### 5.4 The decisive measurement: SPLIT scored against the audit's own hand labels

The audit already decided TRUE/FALSE for **40** `prose-basename-citation` rows. A branch rule is
worth what it agrees with. Joining `sample.rows` (labels at `03500a2620`) to `split.rows` (branches
at `7a826eb70a`) — **all 40 joined, none unjoined** (`score-split.out`):

| branch | TRUE | FALSE | n | precision | Wilson 95 % |
|---|---|---|---|---|---|
| **POSITIVE (operational)** | **2** | **6** | 8 | **0.250** | [0.071, 0.591] |
| **SUGGESTED (all prose)** | **9** | **23** | 32 | **0.281** | [0.156, 0.454] |
| undivided (today) | 11 | 29 | 40 | 0.275 | [0.161, 0.428] |

> **The SPLIT's POSITIVE branch is no more precise than the branch it excludes — 0.250 against
> 0.281 — and its interval spans almost the whole unit interval at n = 8.**

**SPLIT is rejected on its own numbers.** It buys a falsifiable verdict for 22 rows at the cost of
an 11-row single-line margin, and those 22 rows are not the defect rows: 6 of the 8 labelled
branch-A rows are the audit's FALSE, which is **worse than the 9/32 base rate of the rows it
throws away**. The honest reading is that *prose semantics* — de-referential use, in-context
disambiguation, own-unit artifacts — are what separate TRUE from FALSE here, and the audit already
recorded (§4.1) that it **could not reduce its hand labels to a mechanical rule**: the
shadow-copy discharge moved 39 of 251 rows and **did not discriminate** (sampled TRUE ≥ 2
non-shadow collisions 10/11; sampled FALSE 18/29).

**This is the finding that decides the brief.** The SPLIT was the attractive answer because it
*converts a literal into a computed verdict*. It does that and the verdict is still wrong as often
as not, because the thing it computes is code-block membership, not referential intent. **A probe
that measures the wrong question is not a probe.** SPLIT is rejected; RELABEL is not merely
survivable by comparison, it is the only option left that does not assert something unmeasured.

---

## 6. VERDICT

**RELABEL.** `verdict="POSITIVE"` → `verdict="AMBIGUOUS"` at `census.py:451`; the three prose
controls at `:468-470` reassert `AMBIGUOUS`; R6's non-dot stem at `:423-424` removes 3 rows; the
docstring at `:6` is amended. Headline: **5 findings + 253 suggestions** at `7a826eb70a`
(**6 + 248** at the author's `037d5d536e`).

**Why, in one line each:**

1. **253 of 258 positives carry a verdict written into a string literal** (`census.py:451`) — 98.1 %
   of the headline cannot be false, so it is not a measurement.
2. **The SPLIT that would make it measurable was built and scored** (§5.4): its POSITIVE branch is
   0.250 against the audit's labels where the excluded branch is 0.281. **Measured, rejected.**
3. **The 5 surviving findings are the only rows with a probe**, a `NEGATIVE` branch and a failure
   mode — and one of them (`probe_base`'s byte-identical evidence on all 3 rows) is a real defect
   that 253 rows of volume was burying.
4. **The ambiguity itself is real and stays.** 253 of 4 342 cited basenames over 14 303 citing
   lines is a census result with a denominator. Relabelling moves it out of the findings count and
   leaves it as the count it always was.

**Ordering, and the thing not to skip:** this is a **labelling** change, not a repair. The repair
is the audit's R1 — a `probe_prose()` with three discharges — and it is **not yet writable**,
because the lever is prose semantics and the audit showed no mechanical rule discriminates. Until
then `AMBIGUOUS` is the honest label and SPLIT is a measured dead end.

**And regardless of (1)–(4): `census.py` REFUSES at this HEAD because `pos1` names a defect that
has been fixed.** That refusal is the census's first correct falsification and it must be
resolved before any of this is observable. A relabelling that lands while the instrument is dead
changes no number anyone reads.

---

## 7. WHAT I COULD NOT DETERMINE

- **Whether 0.275 is the right precision for this kind.** It is the audit's standard, not mine,
  with no second rater. Everything in §5.4 inherits one opinion. **This is the largest caveat in
  this report.**
- **Any post-change census number.** I did not edit `census.py` and I could not have measured one:
  the instrument REFUSES at this HEAD, and the tree moves. §2's `5` and §4's control-failure counts
  are *derived from the code and the printed cross-tab*, and the cross-tab is fully determined
  (253 + 2 + 3 = 258 POSITIVE; 27 + 3 = 30 NEGATIVE; 23 + 3 = 26 UNKNOWN; 314 sites). They are
  **not** a run.
- **Whether SPLIT would score differently on a rater who disagrees with the audit.** §5.4's 0.250
  vs 0.281 gap is smaller than the n = 8 Wilson interval. I report the point estimates and the
  interval together for that reason and claim only that **SPLIT shows no discrimination**, not that
  it is worse.
- **Whether the SPLIT's `INDENTED` rule is right.** It is my rule; 8 lines turn on it and 2 rows
  are POSITIVE on indented lines alone. A different reading of markdown changes those 2 rows and
  nothing else in §5.4.
- **Whether the ambiguity should be reported at all.** §3.1 argues it must; nobody has shown a
  reader was actually misled by a bare basename. I have 253 collisions and **zero** documented
  harms, and a count of collisions is not a count of harms.
- **Whether `AMBIGUOUS` is the right word.** It is the audit's. `UNVERIFIED-AMBIGUOUS` or
  `COLLIDES` would also be honest. I did not test alternatives and the choice is a naming
  preference, not a result.

## 8. COST AND COMPLIANCE

`census.py` **once** (real 8.97 s, user 7.39 s, 92 % of one core, `nice -n 15`) — the mandated
single run, `--rows` redirected here so the author's artifact could not be overwritten.
`split.py` twice (a corrected denominator between them), `denom-diff.py` once, `score-split.py`
once, three inline Wilson computations. **Every process single, never background, nothing
concurrent with anything of mine.** No `bend`, no `checks/differ.py`, no `checks/e2e*`, no
`checks/sweep.py`, no `checks/bounded.py`, no corpus loop, no `pytest`/`mypy`/`ruff`, no
`gates/*.py` executed (`gates/` read only, via `git show` / `git grep`). `.venv/bin/python` only.
`git` asked only of `GIT_INDEX_FILE`-scrubbed `ls-tree` / `cat-file` / `rev-parse` / `log` /
`diff` / `grep` / `show` — **no `git add`, no `git commit`, no `jj` mutation, no `git ls-files`.**

**Files written: 10, all under `.agents/slop/onespelling-decision/`** — `decision.md`, `split.py`,
`split.rows`, `split.out`, `denom-diff.py`, `denom-diff.out`, `score-split.py`, `score-split.out`,
`census-run.out`, `census-run.time`. **`census-run.rows` does not exist** — the run refused
(§1.1). **Zero `.txt`; zero `.md` outside this directory.**

**Proof that the two instruments I was told not to modify are unmodified**, because an
un-instrumented claim is not a claim:

```
$ shasum -a 256 .agents/slop/onespelling/census.py .agents/slop/onespelling/findings.rows
1b4701ed0fc92256ac06966069f960c394f1b2db0306bb449f8649adabf23d07  census.py       (== pre-session)
3718313d944b57640f2822b345c48aaf32527cba87332af79874d1c0c8bd0991  findings.rows   (== pre-session)
$ ls -la .agents/slop/onespelling/
30236  Oct 16 16:20  census.py       61779  Oct 16 16:22  findings.rows   11335  Oct 16 16:22  REPORT.md
```

Both sha256 values and all three mtimes are identical to the readings taken **before** this
session's first command at 00:15:22Z.