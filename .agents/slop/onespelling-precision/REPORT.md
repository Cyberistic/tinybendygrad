# THE PRECISION OF `.agents/slop/onespelling/census.py`, MEASURED BY HAND

**MEASURED 2026-10-16T14:35:45Z–14:38:55Z at HEAD `03500a26202aa8560adbab980f705ad9c0a7cbfb`**, with
`.venv/bin/python` (3.12) and nothing else running. The tree is a moving target; another session
commits continuously. Rows: `census-run.rows` (311 lines, the census's own output at that HEAD, byte
for byte), labels: `sample.rows` (46 rows, TAB-separated
`kind / site / TRUE|FALSE / reason / evidence`), sampler: `pick.py`, intervals: `intervals.py` →
`intervals.out`.

**PROOF THAT I MODIFIED NOTHING OUTSIDE THIS DIRECTORY**, because the tree's own doctrine says a
claim without a named instrument is not a claim. `env -u GIT_INDEX_FILE git status --porcelain --
.agents/slop/onespelling/` prints **`D` (staged deletion) for all three of the census's files while
all three are present on disk** — that is `AGENTS.md`'s documented armed-index artifact, not a
deletion by me. What is COMMITTED: `git cat-file -e HEAD:.agents/slop/onespelling/{census.py,
findings.rows, REPORT.md}` answers present for all three. What is ON DISK: 30 236 / 61 779 / 11 335
bytes at mtime 16:20/16:22 local, **before this session's first command at 16:35 local (14:35Z)**.
The census was re-run with its own `--rows` flag pointed HERE, precisely so that re-running it could
not overwrite the author's `findings.rows`.

No `.txt` was created. No `bend`, no corpus, no `gates/*.py` execution, no `pytest`/`mypy`/`ruff`.

---

## 0. THE HEADLINE, STATED BEFORE ANYTHING ELSE

**257 POSITIVE findings, of which I could not confirm 41 of the 46 I sampled.** Per kind:

| kind | POSITIVE n | sampled | TRUE | **precision** | Wilson 95 % |
|---|---|---|---|---|---|
| `prose-basename-citation` | **251** | 40 | 11 | **0.275** | [0.161, 0.428] |
| `regex-anchor-set` | 3 | **3 (the whole population)** | 1 | **0.333** | [0.061, 0.792] |
| `single-base-resolver` | 3 | **3 (the whole population)** | 2 | **0.667** | [0.208, 0.939] |
| `extension-set` | **0** | — | — | **no denominator** | — |
| `module-attr-table` | **0** | — | — | **no denominator** | — |

**There is no pooled number, and one is not available.** 251 of the 257 positives (97.7 %) are ONE
kind, and two kinds produced **zero** positives out of 51 candidate sites. A pooled figure would be
`0.28` wearing the costume of a measurement about 257 things.

**AND THE MOST IMPORTANT LINE IN THIS REPORT IS STRUCTURAL, NOT NUMERIC:**

> **`prose-basename-citation` HAS NO PROBE.** `census.py:451-454` appends its rows with
> `verdict="POSITIVE"` **written into the literal**. There is no `probe_prose()`, no `NEGATIVE`
> branch, no threshold to be wrong about, and no self-check that can fail for this kind. Its precision
> is therefore **definitionally 1.0 and unmeasurable from its own output** — which is precisely how a
> kind comes to supply 97.7 % of a census's findings while being incapable of being false.

The other two kinds DO have probes and DO have `NEGATIVE`/`UNKNOWN` branches. They also have real
error rates. The kind that can be wrong, errs. The kind that cannot, contributes the volume.

---

## 1. THE CENSUS'S NUMBERS AT THE HEAD I MEASURED

I ran the census twice (`:14:35:34Z` selfcheck-only, `:14:35:45Z` full write). Identical both times.

```
HEAD 03500a26202aa8560adbab980f705ad9c0a7cbfb
population : 1845 committed .py, 554 committed .md, 7326 committed paths -- every one from `git ls-tree -r HEAD`
module-level literals examined : 101062  (from 1379 .py parsed; 466 dropped by the column-0 grammar gate)
CANDIDATE SITES : 311   extension-set=48  module-attr-table=3  prose-basename-citation=251  regex-anchor-set=3  single-base-resolver=6
bare basenames cited : 4255, ambiguous 251
VERDICTS : NEGATIVE=28  POSITIVE=257  UNKNOWN=26
selfcheck : OK -- 6 controls, the FS_DELETES trap, and every literal spelling read:
           Tuple=6084, Dict=2155, List=598, re.compile=352, Set=128, frozenset(Set)=30, sorted(List)=2, sorted(Set)=1
```

**THE NUMBERS HAVE MOVED, and the census's own REPORT is stale by exactly the tree's growth.**

| | census's REPORT.md (`037d5d536e`, 2026-10-16T13:21:36Z) | my run (`03500a2620`, 14:35:45Z) | Δ |
|---|---|---|---|
| committed `.py` | 1 835 | 1 845 | +10 |
| committed `.md` | 551 | 554 | +3 |
| committed paths | 7 308 | 7 326 | +18 |
| literals examined | 100 951 | 101 062 | +111 |
| CANDIDATE SITES | 307 | **311** | +4 |
| POSITIVE | 254 | **257** | +3 |
| NEGATIVE | 27 | 28 | +1 |
| UNKNOWN | 26 | 26 | 0 |

**I did not edit the census to make it agree.** `findings.rows` in
`.agents/slop/onespelling/` is untouched; I wrote the census's output to `census-run.rows` here via
its own `--rows` flag, precisely so that re-running it could not overwrite the author's artifact.

### The kind × verdict cross-tab, which the census does not print

```
kind                        n   POSITIVE  NEGATIVE  UNKNOWN
extension-set              48      0         25        23
module-attr-table           3      0          3         0
prose-basename-citation   251    251          0         0     <-- POSITIVE is a LITERAL, not a probe result
regex-anchor-set            3      3          0         0
single-base-resolver        6      3          0         3
```

**Two of the five kinds have produced exactly ZERO positives across 51 candidate sites.** The census's
header calls five candidate kinds and its REPORT devotes sections to three. `extension-set` is the
kind its own docstring warns about at length (`rx_extensions`, :210-213) and the kind that found the
class's second instance; it returned nothing. A kind that has never returned a positive has not been
shown to work, and a census that prints it as `extension-set=48` alongside the others is reporting a
population it does not interrogate.

---

## 2. THE SAMPLING RULE AND n

Followed `checks/cites-census.py:753-774` for the SPIRIT, not the code — that file's own comment
records the failure mode I was avoiding:

> ***A STRIDE OVER SORTED ROWS IS NOT A SAMPLE.*** … `fails[::step]` … got 40 rows of which 31 were
> one file … The effective population was two files. **STRATIFY BY CLAIMING FILE.**

**Two problems had to be solved before that rule applied at all.**

1. **A `prose-basename-citation` row is `.md:<basename>`. It carries NO claiming file.** The
   stratum must be derived — I recomputed each basename's citing `file:line` set from the census's OWN
   regex (`` `([^`\n]+)` `` filtered by `` [\w.+-]*\.[A-Za-z0-9]+ ``) over the committed `.md`. That
   derivation is `pick.py`, and it reports its own denominator: **1 423 citation lines across 354
   distinct claiming `.md` files** for the 251 POSITIVE rows. A stride over the sorted rows would
   therefore have been a stride over *basenames*, alphabetised.
2. **A ROW IS A BASENAME, NOT A (basename, file) PAIR.** My first draft was cites-census's algorithm
   verbatim — round-robin over files, one pick per file — and it returned `.agents` three times under
   three different strata and `.out` twice. **40 picks, ~8 distinct rows: a fake n.** `pick.py` now
   carries a global `chosen` set, so it samples **without replacement over rows** and uses the
   round-robin only to choose WHICH citing file the stratum is drawn from. Verified:
   `picked rows: 40, distinct basenames: 40`, and `sample.rows`' prose sites are exactly the picked
   set (no unlabelled, no extras).

**The rule, stated once:**

> Take every POSITIVE row of the kind. Order the claiming `.md` files by (−distinct basenames cited,
> name). Walk that order round-robin; on each visit take the alphabetically-first basename that file
> cites which has not already been taken. Stop at 40. **n = 40 distinct rows over 40 distinct
> claiming files**, drawn from a population of 251 rows / 354 files.

For the two small kinds **n = 3 is the whole POSITIVE population**, so those are censuses, not
samples, and their intervals are near-vacuous — said so rather than dressed up.

---

## 3. PER-KIND PRECISION, WITH THE DENOMINATORS

### 3.1 `prose-basename-citation` — 11 / 40 = **0.275**

**The labelling standard, applied uniformly (and it is a standard, not a preference):**

- **TRUE** — the token is used **referentially** (it points at one specific file to be opened, run or
  read) in at least one citing line, that line carries **no disambiguator** (no directory, no row
  count, no owning unit, no full path), and the collision set holds ≥ 2 tracked files that are not
  merely shadow copies of one live file.
- **FALSE** — one of: **(a)** the token is not a filename at all (`.out` is an extension, `.agents` is
  a directory, `.gitignore` is a convention name); **(b)** the token is **de-referential** — it names a
  CLASS (`REPORT.md`, `__init__.py`, the per-gate `bd.out` family) and the sentence is counting or
  listing, so "which one" is not the question being asked; **(c)** the citing line is its own unit's
  artifact and names the unit; **(d)** every referring citation carries a disambiguator.

**TRUE, 11 of 40.** These are not marginal. `MANIFEST.tsv` has **two different row counts (106 424
and 259) cited by the same bare token in the same report**
(`.agents/slop/orcdecide/REPORT.md:25` and `:62`), over 4 tracked files. `dtype.bend` has **3 real
port files** and one citation carries a **line number** — `dtype.bend:838-443` — which disambiguates
nothing; there are 277 such citation lines. `BEFORE-rows.rows` is ambiguous even when *qualified*,
because both tracked files live under `oracles/`. `census.py` has a literal decoy at
`.agents/slop/census7/decoy/` and a documented near-miss import shadow. `cdp.mjs`, `diff.py`,
`cli.py`, `coverage.py`, `cost.out`, `derive.py`, `PLAN.tsv` are two-or-more real unrelated files
cited bare from a third.

**FALSE, 29 of 40.** The dominant shapes: the token is a **de-referential class** (`REPORT.md` 211
tracked files, `README.md` 56, `__init__.py` 65 — the sentence is "see REPORT.md" meaning *this* unit's
report, or "35 `__init__.py` across `test/`" counting them); the citation is **its own unit's
artifact** stated as such in that unit's inventory; or the collisions are **shadow copies**
(`.agents/slop/figure2/plant/{broken,real}/`, `.agents/slop/corpuswire/tree/`,
`.agents/slop/strays/working/`, `.agents/slop/differverdict/pristine/`) of one live file.

**THE FINDING THAT MATTERS MOST IS ABOUT A CONTROL, NOT A COUNT:**

> **`md:differ.py` is one of the census's own six `CONTROLS` (`census.py:468`) and I read it FALSE.**
> 3 of its 4 tracked collisions are copies of `checks/differ.py` planted under `corpuswire/tree/` and
> `figure2/plant/{broken,real}/` — the tree maintains `.agents/slop/shadowcopies/REPORT.md` to
> catalogue exactly these. A bare `differ.py` in prose names the live `checks/` instrument
> unambiguously, and `AGENTS.md` itself always writes `checks/differ.py` when it wants a path. **A
> control the auditor cannot confirm is a control that cannot falsify.** Two of the six CONTROLS are
> `prose-basename-citation` POSITIVEs — a kind whose verdict is a literal — so **one third of the
> census's falsification surface is unfalsifiable by construction.**

### 3.2 `regex-anchor-set` — 1 / 3 = **0.333** (census of the population)

- **TRUE** — `checks/repro-paths.py:64:REF`. Real, and it is the class's first instance. `re.search`
  needs `^` or whitespace immediately before the path; the measured preceding-delimiter histogram over
  554 committed `.md` is `` ` ``×9078, ` `×3152, `'`×719, `/`×668, `\n`×205 — i.e. the spelling markdown
  actually uses is the one the anchor cannot see. This is the census at its best.
- **FALSE** — `.agents/slop/reprorefs/probe.py:27:PERMISSIVE`. **Byte-identical to the shipped fix at
  `checks/repro-paths.py:64`.** It *is* the permissive replacement, spelled locally so the probe cannot
  compare the change to itself (its own comment, `:23-25`). The census charges the proposed FIX for
  the defect it fixes. Its own REPORT notices — "that file reproduces the shipped pattern" — and
  reports it as a positive anyway, unweighted.
- **FALSE** — `.agents/slop/reprorefs/probe.py:26:OLD`. A **deliberately retained supersession
  fixture**, kept for the reason stated in the same file at `:23-25`. Its census numbers (576→1361)
  differ from the shipped pattern's (734→3534) precisely because `OLD` still carries the five-item
  suffix alternation and so matches fewer tokens at all.

**So 2 of this kind's 3 positives are measurement fixtures of a fix that has already landed.**

### 3.3 `single-base-resolver` — 2 / 3 = **0.667** (census of the population)

- **TRUE** — `.agents/slop/toolsledger/extract.py:15`. `present()` is
  `t in tracked or os.path.exists(t)` after `chdir(ROOT)`, with no tail index: `uop/ops.bend` is
  reported ABSENT although `tinybendygrad/uop/ops.bend` is tracked.
- **TRUE** — `.agents/slop/shapecensus/toolsmd.py:20`. A verbatim re-implementation of the same
  `present()` (its own header says so), so it mis-resolves independently and **keeps doing so after
  `extract.py` is fixed**. A duplicate RULE at a second site is a second site, and this one is true.
- **FALSE** — `.agents/slop/ledgerdrift/drift.py:38`. **`drift.py` HAS the second spelling.** `:51-54`
  builds `tails` from every `/`-separated tail of every indexed path; `resolve()` (`:70-77`) has a
  dedicated `suffix` lane; `:125` calls it. `uop/ops.bend` resolves to `tinybendygrad/uop/ops.bend`.
  `probe_base` charges any `single-base-resolver` without ever asking whether the site has a fallback
  — **while `probe_table`, in the same file, has exactly that discharge** (a same-file companion that
  shares a name ⇒ NEGATIVE, `:196-200`). The test exists; it was not applied to this probe.

**AND ALL THREE ROWS CARRY BYTE-IDENTICAL EVIDENCE** (`lost` is computed from the CORPUS, not from
the SITE). A count of 3 whose evidence is one string is a count of sites whose individual behaviour
was never exercised. That is how `drift.py` got charged: nobody ran the site's resolver.

### 3.4 The two kinds with no denominator

`extension-set`: 48 candidates, **0 POSITIVE**, 25 NEGATIVE, 23 UNKNOWN.
`module-attr-table`: 3 candidates, **0 POSITIVE**, 3 NEGATIVE.
There is no precision to report, and reporting `0/0` as a precision would be exactly the confident
wrong answer this census exists to catch.

---

## 4. HONEST EXTRAPOLATION

**Method.** Wilson score interval at 95 % (`z` = 1.959964), because two kinds have n = 3 and the
normal approximation is exactly what misbehaves there. `intervals.py` computes them from the labels;
`intervals.out` is the transcript.

**What I assumed, stated:**

1. **Simple random sampling within the kind.** My round-robin is *not* SRS — it deliberately
   over-samples rare claiming files and under-samples `.agents/TODO.md` (85 basenames). I am treating
   it as SRS for the interval, so the interval is **optimistic for the rare-file end and the point
   estimate is unbiased only if precision does not correlate with citation count per file**. I
   checked one such correlation (§4.1) and it did not separate.
2. **Labels are independent given the row.** They are not: `README.md`-class tokens recur across the
   sample and share a failure mode. If failures cluster by *shape*, the effective n is below 40 and
   these intervals are too narrow. I flag this rather than correct for it.
3. **The tree does not move.** It does. The population was 311 at 14:35:45Z and the tree gained 10
   `.py` between the census's own report and my run. **Every count here is a reading with a
   timestamp, not a property of the tree.**

| kind | k / n | p̂ | Wilson 95 % | Laplace `(t+1)/(k+2)` | **implied TRUE findings in the kind's n** |
|---|---|---|---|---|---|
| `prose-basename-citation` | 11/40 | 0.275 | **[0.161, 0.428]** | 0.286 | **40 – 107 of 251** (point 69) |
| `regex-anchor-set` | 1/3 | 0.333 | [0.061, 0.792] | 0.400 | 0 – 2 of 3 (point 1) |
| `single-base-resolver` | 2/3 | 0.667 | [0.208, 0.939] | 0.600 | 1 – 3 of 3 (point 2) |

**The two n = 3 intervals span almost the whole unit interval and should not be quoted as bounds.**
With 3 draws and 1 success, the data are consistent with a true precision anywhere from near 0 to
near 1. The point estimates are reported because they are what the hand reading found, and the
interval is reported because it is what the hand reading cannot support. **For `regex-anchor-set` the
honest summary is not a precision — it is "2 of the 3 findings are fixtures of an already-landed
fix", which is a fact about the RULE, not an estimate about a rate.**

**Over all 257 positives, if — and only if — the three kinds are assumed exchangeable (they are not):
69 + 1 + 2 = 72, 95 % CI roughly [43, 112].** Given that 97.7 % of the mass is one kind, that pooled
figure carries essentially no information beyond the first row and I record it only so that nobody has
to construct it by hand later.

### 4.1 A post-hoc stratification, and why it does NOT explain the labels

I tested the mechanical hypothesis that shadow copies explain the FALSE verdicts: define a collision
as **shadow** if any path segment matches `(plant|plants|broken|real|tree|strays|working|pristine|
shell-…|decoy|probe|fixture|fixures|gates-syn)`. Over the whole population of 251:

- every collision shadow: **7** rows
- ≥ 2 collisions: 251 (by construction — the census's threshold)
- ≥ 2 **non-shadow** collisions: **212**
- exactly 1 non-shadow collision: 32

And on the sample: sampled TRUE rows with ≥ 2 non-shadow collisions **10/11**; sampled FALSE rows with
≥ 2 non-shadow collisions **18/29**. **The test does not discriminate.**

So the shadow-copy discharge is worth only ~39 of 251 rows (15.5 %) and **is not the lever.** The
lever is prose semantics — de-referential use, disambiguation in context, own-unit artifacts — and
**I could not reduce my hand labels to a mechanical rule. A hand-labelled precision of 0.275 has no
generator.** That is the honest limit of this report, and it is the same limit `checks/cites-census.py`
lives with.

---

## 5. WHAT WOULD MAKE THE CENSUS BETTER — RULE CHANGES, NOT FINDING EDITS

Ordered by how many rows each one moves.

**R1 — GIVE `prose-basename-citation` A PROBE, OR STOP CALLING IT A VERDICT.** *(unblocks 251 rows,
97.7 % of the census.)* Today `census.py:451-454` writes `verdict="POSITIVE"` into the literal. At
minimum the row must carry the **citing site** (`file:line`), because the token is not the site — this
audit had to re-derive the whole stratum. Then three discharges, in the order they fire:

1. **De-referential test.** Is the token the OBJECT of a count/list/class statement (`REPORT.md`
   211 files, `__init__.py` 65, `bd.out` per-gate family)? → not a finding. This is the biggest
   single class in my sample.
2. **In-context disambiguation.** Does the citing line carry a directory, a row count, an owning
   unit, or a full path? (`checkshells/REPORT.md:39` inside the `checks/*.sh` inventory;
   `indextree/REPORT.md:4` naming its own producer) → not a finding.
3. **Own-unit test.** Is the citing document the artifact's own directory? (`extract.py` citing its own
   `census.rows`) → not a finding.

If those cannot be written as code, then the honest move is to **re-label the kind**: it is a
*census of ambiguity*, and it should print `AMBIGUOUS n=251` with no verdict, the way
`prose-basename-citation` already prints nothing about severity. **An instrument that cannot decide
should say so rather than emit a verdict it did not compute.**

**R2 — A CONTROL MUST BE ABLE TO FAIL.** *(3 of 6 controls.)* Two of the six CONTROLS are
`prose-basename-citation` POSITIVEs from a kind that emits POSITIVE unconditionally: they cannot
fail, so they are not controls. `md:differ.py`, a third control, does not survive reading. Require:
every control asserts a verdict the instrument could in principle have computed the other way, and
**at least one NEGATIVE control per kind**.

**R3 — REUSE THE COMPANION TEST `probe_table` ALREADY HAS.** *(releases 1 row today, prevents the
class.)* `probe_table:196-200` discharges a table when a same-file companion shares a name.
`probe_base` never asks whether a resolver has a `tails`/suffix/second-root fallback, which is why
`ledgerdrift/drift.py` — a site with a dedicated `suffix` lane — is charged. Move that test into
`probe_base`.

**R4 — A FIXTURE IS NOT AN INSTRUMENT.** *(releases 2 rows today, 2 of this kind's 3.)* Two of three
`regex-anchor-set` positives live in `.agents/slop/reprorefs/probe.py`, one of them byte-identical to
the shipped fix. Require: a `re.compile` that is **byte-identical to another site in the tree**, or
that a same-file comment names as the pattern this file REPLACED, emits `DUPLICATE-OF <site>` rather
than POSITIVE. `probe_regex` should also report whether the site is under `.agents/slop/` at all —
`checks/` is where shipped gates live and `.agents/slop/` is where probes live, and that difference is
mechanical.

**R5 — EVIDENCE MUST BE SITE-SPECIFIC.** *(3 rows.)* All three `single-base-resolver` rows carry
byte-identical evidence because `probe_base` reports the corpus result, not the site's behaviour. A
row's evidence must contain a measurement of **that site** (what this module's resolver does with a
named token) or the row must be collapsed to one.

**R6 — REJECT NON-FILENAME TOKENS.** *(3 rows, cheap, and it closes a class.)* The token test
`[\w.+-]*\.[A-Za-z0-9]+` accepts a token that **is** an extension or a directory, then matches it
against `os.path.basename` of tracked paths — so prose writing `` `.out` `` (the house rule for
captured streams) is charged because `checks/.out` and `.agents/slop/strays-root/.out` exist. That is
`rx_extensions`' own docstring warning ("charges a directory for being one") reproduced one level up.
Requiring a **non-dot stem** (`^\w[\w.+-]*\.[A-Za-z0-9]+$`) removes 3 rows here. It is small — the
point is that it is a **rule**, applied before the verdict, and today it is not applied at all.

**R7 — A KIND THAT HAS NEVER FIRED SHOULD SAY SO.** *(51 candidates, 0 findings.)* `extension-set=48`
and `module-attr-table=3` print as peer populations of the other three. Neither has produced a POSITIVE
in this run. Print the kind's **yield**, not only its size, so a reader can see which kinds are
interrogating and which are merely enumerated.

---

## 6. WHAT I COULD NOT DETERMINE

- **WHETHER 0.275 IS THE RIGHT NUMBER FOR `prose-basename-citation`.** The labelling standard is
  mine, stated in §3.1, and a different (defensible) standard would move the count. I did not run a
  second rater, so there is **no inter-rater agreement figure**, and without one the precision has one
  opinion in it. This is the largest single caveat in the report.
- **THE 26 UNKNOWNS WERE NOT SAMPLED.** They are excluded by construction, not by choice, and
  `extension-set`'s 23 UNKNOWNs are all `probe_ext` declining to decide. **The census's precision on
  its UNKNOWNs is unmeasured, and a census that is 26/311 undecided has an unmeasured surface that is
  larger than its confirmed error rate suggests.**
- **2 of the 5 kinds have no precision at all**, for want of a single positive. Not estimated,
  reported as absent.
- **The `regex-anchor-set` and `single-base-resolver` intervals are not bounds.** n = 3.
- **Whether the shadow-copy set is the right SHADOW set.** It is a stated regex, chosen by me, and
  §4.1 shows it barely moves anything either way — so the conclusion is robust to my getting it wrong,
  which is the only reason to trust it at all.
- **Whether the tree's numbers are stable.** They are not. The census's own REPORT was 4 sites and 3
  positives out of date at the moment I measured it, and it will be out of date again.
- **I did not run the census against a mutated tree**, so I have no measurement of its sensitivity —
  only its validity on this tree.

## 7. COST AND COMPLIANCE

`census.py` ×2 (8.4 s each, 92 % of one core), `pick.py` ×2, `intervals.py` ×2, the label cross-check
— all single-process, all well under 200 MB, no `bend`, no corpus, no `gates/*.py` execution, no
`pytest`/`mypy`/`ruff`, no network, no installs. `.venv/bin/python` only; `git` asked only of
`GIT_INDEX_FILE`-scrubbed `ls-tree`/`cat-file`. Files written: **9, all under
`.agents/slop/onespelling-precision/`** — `REPORT.md`, `sample.rows`, `census-run.rows`,
`intervals.out`, `intervals.py`, `pick.py`, `picked.tsv`, `contexts.rows`, `run-stamp.rows`. **Zero
`.txt`.** `sample.rows` shape verified: 46 data rows, every one exactly 5 columns, and the 40 prose
sites exactly equal the 40 distinct basenames `pick.py` drew. Nothing outside this directory was
modified — proof at the top of this report.