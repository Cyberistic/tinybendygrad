# LANE D'S MISSING CLASSIFIER — PRICED

**Report only. Nothing fixed, nothing committed, nothing staged.**
HEAD at first measurement `444890672d9baebb6309952495f480623f481fc5`, at write
`3173198bd80e2c1ba28d635d7c0f8121fac31a37` — **the tree moved twice while this report was
written**, which is §6's first warning and the reason every count here carries its HEAD.
`2026-10-17T00:42:36Z` → `2026-10-17T00:46:44Z`.

Instruments, all under `.agents/slop/citeslaneD/`:
`priceD.py` (prices the candidates; imports `checks/cites-census.py` for its regexes and calls
its `prose`/`lane_bcd` extractor — **it never re-judges a verdict**), `emit.py` (joins the hand
labels and writes `pricing.rows`), `detail.rows` (326 lane-D rows with a witness column each),
`priceD.out`/`.err`.
**`checks/cites-census.py` was NOT run.** Its rows were reused from
`.agents/slop/citesbacklog/verdicts.rows`, per the brief.

---

## 1. THE CLAIM, CONFIRMED — AND ONE THING THE PRIOR UNIT GOT WRONG

> *"the cheapest real fix is a MISSING CLASSIFIER … lane D never calls `needle_kind`; lane C
> has ten kinds, lane D none"*

**CONFIRMED as a fact about the code.** Lane C's judge branch opens with the call and refuses
everything that is not `text` (`checks/cites-census.py:478-483`):

```python
  if c["lane"] == "C":
    kind = needle_kind(c["needle"], c.get("gap", ""), c.get("line_text", ""))
    if kind != "text":
      return {**c, "verdict": REFUSED, "needle_kind": kind, ...}
```

Lane D's branch (`:493-514`) **never names `needle_kind` at all**. Its whole of the precision
work is a unit test, a delta test, an anchor test, and then a line count:

```python
  if c["lane"] == "D":
    if c["unit"] != "line":
      return {**c, "verdict": REFUSED, "evidence": f"unit {c['unit']!r} has no unambiguous meaning for a file"}
    if c.get("delta"):
      return {**c, "verdict": REFUSED, "needle_kind": "delta", ...}
    ...
    n = len(text.splitlines())
    ok = n == c["num"]
    return {**c, "verdict": PASS if ok else FAIL,
            "evidence": f"{c['subject']} has {n} lines, claim says {c['num']}"}
```

**What it does instead: it line-counts.** `len(text.splitlines()) == num`, applied to a claim
whose unit may be a run's stdout, a quoted quotation, a diff's endpoint, or a `wc -l` newline
count. `needle_kind`'s ten kinds are never consulted.

**One correction to the prior unit, and it is the row-file half of the claim.** Lane D emits
**two** values into the `needle_kind` column — `delta` (10 rows) and `expired-anchor` (4) —
and **neither is in `needle_kind`'s vocabulary**:

```
lane C needle_kind on REFUSED: cell-label=2278 fragment=158 code=138 short=81 reference=79
                               digest=76 command=31 exit-status=19 output=11   (10 kinds)
lane D needle_kind on REFUSED: delta=10 expired-anchor=4                          (2 kinds)
```

`summarise` pools both lanes into one `REFUSALS BY KIND` counter over one column
(`:567-571`). So "ten kinds and none" is right about the *call* and wrong about the *column*:
that column is already a **mixed vocabulary with no generator**, which is the same defect
`.agents/TOOLS.md` and `checks/no-txt.py` exist to prevent, one level down.

---

## 2. WHAT LANE D MIS-CLASSIFIES — THE KINDS, NAMED

Lane D's population at HEAD `7a826eb70a` (the rows file's HEAD): **326 rows =
FAIL 66 · PASS 46 · REFUSED 214.** The 214 are 184 `unit != line` (141 `row`, 35 `byte`,
8 `file`), 14 subject unreadable/absent, 10 `delta`, 4 `expired-anchor`, 2 ambiguous subject.

The FALSE_POSITIVEs are **four kinds of claim wearing a file's length**:

| kind of claim | what the prose actually asserts | a hand-labelled example |
|---|---|---|
| **a RUN's stdout** | the number is a row/exit count of a command, not the file's length | `.agents/slop/literal-oracle-report.md:390` — `` `python3 .agents/slop/nv-oracle.py` → 574 lines `` |
| **a DIFF's endpoint** | `2605 → 2712 lines` is one end of a change; the extractor took the first number | `.agents/slop/I64MUL.md:3`, `.agents/slop/closure/REPORT.md:263`, `.agents/slop/envprecond/REPORT.md:200` |
| **a QUOTATION about a number** | prose *about* a numeric claim, inside a quote or a backtick span | `.agents/slop/notes/bend2-constraints.md:9029`, `:11635`; `.agents/slop/quiescefix/REPORT.md:22`; `.agents/slop/claimaudit2/REPORT.md:271` (quotes a **commit message**) |
| **a `wc -l` newline count** | the number counts newlines, and `splitlines()` also counts a final unterminated line | `.agents/slop/guardfix/REPORT.md:18`, `:141`; `.agents/slop/residual/REPORT.md:128`, `:138` |

Plus one that is **not** a kind at all and is the largest class in the lane: **a unit this
census declines to define.** 176 of the 214 REFUSED rows are refused for `row` (141) or `byte`
(35), and **both are checkable by a census that already reads the file** — `splitlines()` and
`os.path.getsize`. Only `file` (8) is genuinely out of reach, being a directory listing.
**That is 176 rows, 2.7× the 66 FAIL rows the whole classifier question is about, and it needs
no kind test — only a unit meaning.**

---

## 3. THE MINIMAL CLASSIFIER, AND WHAT EACH KIND WOULD DISCHARGE

Denominators: **56 of 66 FAIL and 35 of 46 PASS reproduce** at this HEAD's extraction (§6).
N = FAIL rows retired. M = PASS rows silenced. **M_real** = labelled-REAL findings silenced.
`priceD.out`; every row has a witness line in `detail.rows` and a label in `pricing.rows`.

| candidate | kind borrowed from `needle_kind`? | N | M | M_real | verdict |
|---|---|---:|---:|---:|---|
| `output` (`->` / `rc=` / `exit=`, **verbatim**) | **YES** — `output`, unchanged | **1** | **0** | **0** | **PASSES** |
| `wc -l` **causal** (`splitlines()==claim+1` **AND** subject lacks trailing `\n`) | **NO — and it is not a kind** | **4** | **0** | **0** | **PASSES** |
| `command` — the number is a command's output | YES — `command`, widened | 0 | 0 | 0 | **DEAD**, drop it |
| `fragment(quoted)` — the number sits in a quote/backtick span | YES — `fragment`, widened | 5 | 0 | **1** | fails the ~zero bar |
| `cell-label` — the claiming line is a table row | YES — `cell-label` | 9 | **5** | **4** | **REFUTED** |
| `wc -l` **bare** (`==claim+1`, no newline test) | NO | 5 | 0 | **1** | fails the ~zero bar |
| `output` + unicode arrows (`→ ⇒ ↦ ⟶`) | YES — same kind, wider alphabet | 9 | 0 | **3** | fails the ~zero bar |
| **UNION of all seven** | — | **22** | **5** | **6** | **REFUTED** |

Four things this table says that the prior report did not:

1. **`cell-label` is the only branch that touches a PASS row at all** — all 5 PASS silences in
   the whole union are its. It is refuted on both denominators at once (M = 5 PASS, 4 REAL).
   And it is wrong for a reason visible in the data: `.agents/TOOLS.md:392` is a table row
   whose cell **carries a predicate** ("Reads the pieces in DEPENDENCY order and writes X,
   2596 lines"), which is exactly what `needle_kind`'s `cell-label` branch exists to exclude.
2. **The `wc -l` rule's "M = 0 by construction" is measured on the wrong denominator.** It is
   M = 0 over PASS rows — guaranteed, because PASS *requires* equality, so it is vacuous there.
   Over the FAIL rows the rule actually discharges, **1 of 5 is a REAL finding**:
   `.agents/slop/notes/bend2-constraints.md:11548` says `tinygrad/helpers.py` "is 646 lines";
   it has 647 and **ends with a newline**, so the convention does not account for it. Adding
   the causal newline test drops N 5→4 and M_real 1→0. That test is the whole difference, and
   it is one condition wide.
3. **Widening `output` to unicode arrows is a trap, not a fix.** It takes N from 1 to 9 and
   M_real from 0 to 3. Three of the four extra rows are `A → B lines` **deltas** the census's
   own `DELTA` verb test misses because it looks for verbs and signed numbers, not arrows
   (`I64MUL.md:3`, `closure/REPORT.md:263`, `envprecond/REPORT.md:200`) — and one
   (`bullets/REPLACEMENTS.md:73`) is a plain magnitude claim whose arrow is incidental
   (`46-line shim → .venv/bin/python checks/substrate.py, 765 lines`). So **the real win is to
   widen `DELTA` to see an arrow, not to widen `output`** — a different branch, and it is
   lane D's own vocabulary, not a new one.
4. **`output` at N = 1 is clean and nearly worthless.** Its one row is
   `.agents/slop/readback/REPORT.md:65`, the prior unit's own FALSE_POSITIVE. Correct, free,
   and worth 1 row of 66.

---

## 4. THE M/N VERDICT, WITH DENOMINATORS

**M = REAL findings silenced. N = PASS rows silenced. Bar ≈ 0; M > N refutes.**

> ### M = 0, N = 0. N_discharged = 5 of 66 FAIL rows (7.6% of lane D, 1.8% of the 272-row backlog).

- **The proposed pair** (`output` verbatim + `wc -l` causal) discharges **5** FAIL rows:
  `readback/REPORT.md:65`, `guardfix/REPORT.md:18`, `guardfix/REPORT.md:141`,
  `residual/REPORT.md:128`, `residual/REPORT.md:138`.
  **All 5 are hand-labelled FALSE_POSITIVE — 3 by the prior unit, 2 by me, agreeing with its
  prose.** So **M = 0** over 5 discharged rows, and **N = 0** over the 35 reproduced PASS rows
  (of 46).
- **It also touches 8 REFUSED rows** with the `output` test, and changes **0** of their
  verdicts: `judge` returns REFUSED on `unit` at `:494` before any kind is consulted. Evidence
  changes, verdicts do not. Named because "0 verdict changes" is a measurement, not a promise.
- **The full union is a net loss**: N = 22 FAIL discharged, **M = 6 REAL silenced**
  (`TOOLS.md:392`, `agend2/REPORT.md:102`, `agend2/REPORT.md:49`, `gatesweep/REPORT.md:12`,
  `bullets/REPLACEMENTS.md:73`, `notes/bend2-constraints.md:11548`) against N = 5 PASS silenced.
  **It silences more real defects than it rescues from PASS, and leaves 44 of 66 FAIL rows
  (66.7%) untouched.**

**Label denominators, which are weaker than the numbers above and are stated so they can be
discounted:** of the 66 FAIL rows, **26 are hand-labelled — 10 REAL, 13 FALSE_POSITIVE,
3 AMBIGUOUS — and 40 are UNLABELLED.** The prior unit sampled 10 (6 REAL / 4 FALSE_POSITIVE);
I added 16. So **M_real is measured on 4 priceable REAL rows of 6 labelled of 10 sampled of
66**, and the 40 unlabelled rows could hide more REALs that a candidate would silence. The
prior unit's sample is **not reproducible from its files** — its `sample.rows` has an empty
label column and the labels live only in `REPORT.md` §4d prose, which is the defect the census
docstring itself records at `:775-778`.

---

## 5. WHAT WOULD MAKE THIS UNSAFE, AND SHOULD IT LAND

**Land the `wc -l` causal branch. Do not land the rest. The finding is right and the
conclusion drawn from it is not.**

Land, because it is one extra condition, it names its own convention, and it is measured at
N = 4 / M = 0 on the only class in this lane where the number is *arithmetically* a different
number rather than a different claim. Suggested shape, in lane D's own existing idiom:

> if the subject's measured `splitlines()` is exactly one more than the claim **and** the
> subject does not end in a newline, REFUSE with a `needle_kind` that says **which convention
> was applied**, because `wc -l` counts newlines and this census counts lines.

Three conditions make it unsafe, and each is checkable:

1. **Without the newline condition it is a coincidence, and it demonstrably is one** — 1 of its
   5 bare-`claim+1` firings is a REAL defect. A rule that refuses on `|n − c| == 1` alone must
   never be landed.
2. **It must REFUSE with a reason, never PASS.** A PASS here would assert the file has 502
   lines when it has 503 — inventing a defect rather than declining one. This is the exact
   shape of the `artefacts_ok()` fault at `:206`.
3. **It is only correct while `splitlines()` is the census's counter.** If the comparison ever
   moves to `wc`-equivalent counting the branch becomes vacuous, and it must then be deleted
   rather than left to fire on nothing. A vacuous guard is worse than no guard.

**Unsafe for `cell-label`, `fragment(quoted)`, and the widened `output`**, at 4, 1 and 3 REAL
findings respectively — and each is unsafe for a legible reason: a table row can carry a
predicate; a backticked number is usually just a number in this tree; and an arrow is far more
often a delta than a run.

**The honest summary is that lane D's remaining 44 of 66 FAIL rows are prose to fix, not
instrument work** — and that the biggest hole in lane D is **not** the classifier at all: it is
**176 REFUSED rows refused for a unit that is checkable** (§2), which is 2.7× the entire FAIL
backlog and needs one `os.path.getsize` and one `splitlines()` rather than a kind test.

**And the measurement that governs all of it: 0 of 66 FAIL rows carry an ISO date.** Lane D
already has the refusal that says *STALE, not FALSE* (`expired-anchor`, 4 rows) and it fires on
**none** of lane D's failures. Per the census's own docstring — *"A CLAIM WITH A DATE GOES
STALE HONESTLY; ONE WITHOUT LIES INDEFINITELY"* — all 66 are asserting present tense with
nothing to expire them, on a tree that moved HEAD twice during this report. **Any classifier
that tries to separate stale from false here is guessing, and should be REFUSED rather than
landed.**

---

## 6. WHERE THIS IS WEAK — AND A BUG IN MY OWN INSTRUMENT

- **Two HEADs, and the numbers do not agree across them.** The rows file is HEAD
  `7a826eb70a`; extraction ran at `444890672d` (HEAD moved to `3173198b` by write time).
  **56 of 66 FAIL and 35 of 46 PASS reproduce.** The other 10 FAIL rows cannot be priced at
  all and are counted as UNPRICED, not as zero.
- **My first `detail.rows` was wrong and I caught it by disagreement, not by reading.** The
  writer consumed a generator that referenced `kinds` as a **free variable**, so every row
  inherited the *last* row's kinds and the file claimed `output` fired on 66/66 while the same
  script's own table said 1. An independent recount (`:6` of the transcript) said 1. **A
  generator that reads a loop variable it did not bind is a second copy of the answer with no
  generator** — the `differ.declared()` fault inside my own instrument. Fixed at
  `priceD.py:180` by unpacking `for f, kinds in out`. The *priced table* was correct
  throughout; the *row file* was not.
- **My subject line count disagrees with the census's own evidence on 4 of 91 comparable
  rows** (`priceD.out`, "validity of MY subject line count"). Three are the tree growing
  (`.agents/TODO.md` 18368→18506, `gates/gates-pop.py` 1530→1643). One is a real resolver
  difference: `runtime/sz.c` — census 119, mine 32, i.e. the **suffix index resolved the
  subject to a different file at this HEAD**. **None of the 5 rows the proposed pair discharges
  is among the 4**, so the proposal's price is unaffected — but the `wc -l` branch depends on
  `_n`, and that dependency is exactly where this shows up.
- **Only 26 of 66 FAIL rows are labelled** (§4). Every "REAL" count is bounded by that.
- **40 of the 66 rows are UNLABELLED and therefore UNPRICED.** A candidate could be wrong on
  any of them; the ~zero bar is met on 26 rows and unknown on 40.
- **I did not re-run the census**, so lane D's *current* FAIL total is unmeasured. Every count
  here is the rows file's, at `7a826eb70a`.
- **Nothing was committed or staged.** No `git add`, `git commit` or `jj`. The one git call was
  `git rev-parse HEAD`; it does not consult the index. Read-only everywhere else.