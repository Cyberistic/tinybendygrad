# `dangle` — references into a tree under it

**Unit:** `dangle` · **date:** 2026-10-14, 15:31–16:03 local · **committed: NOTHING, staged: NOTHING**
**Instrument:** `checks/cites-census.py` (new, 524 lines, `--selftest` 6 plants green) ·
**rows:** `.agents/slop/dangle/cites.rows` (30,751)
**Verdict of the instrument: `FAIL` (exit 1)** — and §0 explains why that token is about *half* wrong.

Every count below carries its timestamp and its denominator. The tree moved under me twice during
this session (`runs/graphcmp/D` held at 242 files throughout; `AGENTS.md` is 496 lines by `wc -l`).

---

## 0. FINDINGS FIRST — four ways MY OWN measurement was wrong, with the before-values

The brief asked me to find a way my measurement was wrong and say so first. It was wrong **four
times**, each time in the exact shape this unit exists to catch: *an instrument that cannot see
its population, reporting a clean number anyway.*

### 0.1 A classifier bug reported `0` over a population of thousands

**Before:** `LANE B: 0`, `LANE C: 0`, `LANE D: 0`, `UNCLASSIFIED: 0`, on a tree whose own prose
cites `checks/differ.py:670` and `ops.py:1398` on nearly every page.

**Cause:** `token_kind()` tested the *whole* token against a FILENAME shape **before** peeling the
locator. `differ.py:670` has a colon in it, so it failed the test, returned `None`, and was
silently discarded. An instrument that classifies a citation out of existence is DEAD wearing a
PASS. **This is the `head -1` trap applied to a census.**

### 0.2 Over-correction: 1,604,391 "unclassified"

**Before:** `UNCLASSIFIED: 1,604,391` — four orders of magnitude above the file count.

**Cause:** I classified *every* SPAN, and a SPAN is any word. `the`, `and`, `or` all became
"unclassified". A matcher that counts ordinary English is measuring itself. Now: a token with no
`/`, no `.` and no locator returns `None` and is **not counted at all**.

### 0.3 Lane C failed 68% of the time — all three error sources were mine

**Before:** `VERDICT C: PASS=1 FAIL=26` (of 27 judged), then `PASS=599 FAIL=2266` (of 3239).

**Cause, in order of discovery:**
1. **Unanchored predicate.** I took the next quoted span *anywhere on the line*, so
   `` `checks/differ.py` is parsed by `gates/...` `` asked whether `differ.py` contains
   "is parsed by". Fixed with a connector rule: the gap must be ≤24 chars and contain no word of
   three letters or more (`checks/cites-census.py:_is_connector`).
2. **Backticks are a toggle, not a bracket.** The regex `` `([^`]{4,})` `` pairs backtick #1 with
   #2, so in `` `a.md`, BEHIND TWO `b` `` it returned the span `", BEHIND TWO "` — a *prose
   fragment*. Fixed by `quoted_spans()`, which pairs delimiters **positionally**.
3. **Not every needle is content.** A sha256, a git rev, an exit status and a shell command are
   four different kinds of claim. Asking whether a file "contains" `rc=0` is not a question about
   content, and answering it `FAIL` is a lie about what was asked. Now `REFUSED`, with the unit
   named in the evidence.

### 0.4 My own SAMPLE was a cluster, not a sample — and this one I would have shipped

**Before:** `--sample-fail 40` returned 40 rows of which **31 were one file** (`.agents/slop/residue/
000-the-residue.md`) and one heading word (`DELETE`).

**Cause:** `fails[::step]` over rows sorted by file does not sample the FAIL population; it samples
whichever files **dominate** the FAIL count. The effective population was two files out of 163.

**Fix:** stratify by *claiming file*, one row per file, round-robin, largest-file-first
(`checks/cites-census.py`, `--sample-fail`). **Without this my reported precision would have been
measured on a population of 2.**

**And the measurement that followed:** a 36-row stratified sample, hand-labelled one row at a time,
found **13 of 36 FAILs were my matcher's fault** — a **36.1% precision**. That is the number I would
have reported if I had tuned the classifier until the failure rate *looked* plausible instead of
measuring it. After the three principled fixes in §0.3, a second 30-row stratified sample gives
**15/30 = 50.0%**.

> **THE HEADLINE OF THIS UNIT: AT 50% PRECISION, A `FAIL` FROM THIS CENSUS IS A COIN FLIP. IT IS
> NOT A FINDING. EVERY FAIL COUNT BELOW IS REPORTED TWICE — RAW, AND PRECISION-WEIGHTED.**

---

## 1. THE CENSUS — population, method, denominators

**Population, by discovery.** `git ls-tree -r HEAD` filtered to `.md`/`.py` → **2,294 files**
(529 `.md`, 1,758 `.py`, of which 448+711 are under `.agents/slop/`).

*Why `git ls-tree` and not `git ls-files`:* `ls-files` reads the **INDEX**, which this repo arms
with intent-to-add placeholders by design. The index answered **14 staged paths** and 0 about my own
files at the end of my run. A census that read the index would have censused a tree that does not
exist.

**Scope, stated:** a directory walk finds **2,509** `.md`/`.py` on disk; **215 are not in `HEAD`**
(ignored, or intent-to-add) and are **not** censused. 205 symlinks live under `.agents/slop/`,
`checks/`, `gates/` — the census follows them, and I flag this as an unmeasured exposure.

**Prose sources.** A `.md` is prose whole. A `.py` contributes its **comments** (`tokenize`) and its
**docstrings** (`ast`) — *not* its string literals, which are code and belong to lane A. This is why
`.py` prose is counted and not grepped: a comment that says `(path, 1, x)` is not an assertion, and
a tuple built by a comprehension is not a hand-written pin.

| lane | shape | count | method |
|---|---|---|---|
| **A** | `(str, int, str)` tuple literal | **62** | AST: `ast.walk` for `Tuple`/`List` with 3+ `ast.Constant` elements typed `(str, int, str)` |
| **B** | `path:NNN` in prose | **2,764** | anchored matcher |
| **C** | path + adjacent quoted span | **3,239** | anchored matcher |
| **D** | path + adjacent `N lines\|rows\|files\|bytes` | **291** | anchored matcher |
| **E** | mention (no predicate) | **24,395** | **counted, never a verdict** |
| **U** | unclassified | **53,495** | see below |

**Unclassified, broken out (this is the answer to "how many could not classify"):**

| class | count | what it is |
|---|---|---|
| `basename/bare-filename` | 37,041 | `ops.py`, `differ.py` — **a basename is not a path** |
| `directory name used as a citation` | **10,733** | the exact shape the orchestrator's first check counted |
| `basename/position` | 5,631 | `ops.py:1398` — a **name** and a position, no path |
| `name-locator` | 90 | `DEF:…:name` — parser-resolvable, not by this census |

3,962 directory-shaped references resolve to **778 distinct directories**; the top five are
`.agents/slop/` (316), `tinybendygrad/` (304), `checks/` (236), `tinygrad/` (218), `runs/` (174).
**A trailing slash is a suffix.** All 778 are lane E and none is a verdict.

**The matcher, stated so it can be argued with:** a token is a path iff it carries a `/`; a locator
(`:N`, `:N-M`, `:name`) is peeled **first** and the bare subject judged second; a subject must end
in a real filename extension or a `/`; a predicate must be **adjacent** (connector gap ≤24 chars, no
word ≥3 letters); digests, revs, exit statuses and commands are `REFUSED` as a different kind of claim.

### An off-by-one worth naming

`wc -l` and `len(text.splitlines())` **disagree by 1** on files without a trailing newline —
`checks/substrate.py`: `wc -l` = **935**, `splitlines` = **936**. My census uses `splitlines`.
**Every `N lines` claim near a boundary moves by one depending on which tool the author ran**, and
three of my seven lane-B FAILs cite a file that shrank by an order of magnitude, so it did not change
those verdicts — but it is a live ambiguity in a lane whose entire content is a number.

---

## 2. THE DECISIVE QUESTION — which claims are still true?

**Raw, timestamped 2026-10-14 ~16:00, over 2,294 committed `.md`/`.py`:**

| lane | PASS | FAIL | REFUSED |
|---|---|---|---|
| A positional-ast | 29 | **8** | 25 |
| B positional-prose | 1,746 | **7** | 1,011 |
| C content-prose | 576 | 2,153 | 510 |
| D numeric-prose | 33 | 61 | 197 |
| **TOTAL** | **2,384** | **2,229** | **1,743** |

**Precision-weighted** at the measured 50.0% precision of §0.4: of 2,229 FAIL rows, **≈1,100 are the
tree lying and ≈1,100 are this instrument lying.** I decline to narrow that further; the sample is
30 rows and the interval is wide. **Raw numbers are in the `.rows`; the weighted ones are a guess
with a stated denominator, and they are marked as such.**

### 2.1 The one lane I will stand behind: **B, 7 FAILs, 7/7 confirmed genuine**

Every lane-B FAIL was verified against the filesystem, not inferred:

| citation | cited | measured |
|---|---|---|
| `.agents/slop/e2e.sh:122`, `:138` (×3) | 122–161 | **23 lines** |
| `tinybendygrad/runtime/ops_nv.bend:2344`, `:2348` (×2) | 2344 | **94 lines** |
| `tinybendygrad/engine/jit.bend:1091` | 1091 | **434 lines** |

These files **shrank by an order of magnitude** and the prose still cites positions inside the old
versions. `checks/e2e.sh` is 340 lines — the `.agents/slop/e2e.sh` citation is not a typo for it,
because the citing line names the `.agents/slop/` path explicitly.

**And the orchestrator's own example is confirmed by the census, independently:**
`checks/disagree-gate.py` **no longer contains the string `CITES = (path, line, must_contain, why)`.**
It was rewritten to `DEF:<path>:<name>` / `AT:<path>`. The claim that it still had the positional
shape is false, and `disagree-gate.py --lane citations` is **rc=0** while carrying that stale shape
in *other* units' prose.

### 2.2 Lane A: the positional shape is **already dead in live code** — 0 of 4

58 of 62 positional AST pin tuples live under `.agents/slop/` (finished scratch), and all 8 FAILs are
there. The 4 in live files are **false positives of my own AST lane** — `(x, y, "32B")` test tuples
in `examples/qwq.py:104` and `test/null/test_disk_cache.py:18`. **`REFUSED`, not `FAIL`:
`unreadable or absent: 32B`.**

> **The true count of `(path, line, must_contain)` tuples in live instruments is ZERO.**
> `disagree-gate.py` did the job. **The shape has no live instances left to convert.**

`58 of 62` are in `.agents/slop/citemass/resolve.py` — **a prior unit's own
`(check_relpath, cite_line, ref, N, end, anchor)` pin table for this exact subject**, built with
6-tuples. Its rows (`("checks/differ.py", 149, "ops.bend", 1066, None, "ATuple{ys: List<&2, U32>}")`)
independently agree with my lane-A FAIL on `checks/differ.py:149`, and it exposes the second failure
mode: its needle `ops.bend` occurs at **4 lines**, which is `disagree-gate.py`'s own documented
"an anchor that matches many lines is a claim that cannot fail."

### 2.3 The strongest single false claim in the set

`.agents/TOOLS.md:71` cites `tools/get-bend.sh` for `0187512` — a **revision**, asked to be file
content. It is `REFUSED` now, correctly, and it is the shape that turns a git log into a lie.

---

## 3. THE SHAPE, NOT THE LIST

### 3.1 For code — the fix already exists and the population is already empty

`disagree-gate.py`'s `DEF:<path>:<name>` (resolved by parser, body-scoped) and `AT:<path>` (unique
substring, **REFUSED if it matches 0 or >1 lines**) are the right shape. **9 of 14 are AST-derivable;
the 5 that are not are all `.bend`, which has no AST to ask.** With **0 live instances of the old
shape**, this is a *prohibition* task, not a conversion task:

> **A POSITIONAL ASSERTION IN A NEW OR EDITED INSTRUMENT IS `REFUSED`, NOT REVIEWED.**

That is a `rg`-able rule with no hand list: `checks/cites-census.py --rows` lane A is 0 in live code,
and it stays 0 only if something checks it.

### 3.2 For prose — **a path + a predicate is not a claim, and prose cannot be anchored**

Lane C is the proof. 3,239 claims, and the needle is a *quoted span adjacent to a path*. The
adjacency rule I could write — gap ≤24 chars, no word ≥3 letters — still cannot separate
`\u0027UNCHANGED\u0027` (a status word) from `dtype: S.Dt` (a field name), or `rc=0` from a row count,
or `Path(__file__).resolve().parents[3]` from the same expression written without its `pathlib.`
prefix. **That last pair is the argument in miniature: a prose claim is checkable only if the author
wrote the needle byte-for-byte as the file has it, and prose does not preserve bytes.**

**So: prose carries a TIMESTAMP, and the timestamp is the claim.**

The rule I propose, and it is one line:

> **A PROSE CLAIM ABOUT A FILE IS `path` + `must contain` + `MEASURED <date>`. It is TRUE as of that
> date and is NOT A VERDICT about the file.** A citation with a date goes stale *honestly* — the
> reader can see it is a reading. A citation without one lies indefinitely, because nothing in the
> document ever says it was true once.

The evidence for "indefinitely" is in this tree: `.agents/slop/guardfix/REPORT.md` says `dtype.c` is
297 lines (it is 328); `.agents/slop/quiescefix/REPORT.md` says `substrate-id.py` is 532 (it is 681);
`.agents/slop/brief-port.md` says `ops.bend` is 3800 (it is 8912). **AGENTS.md itself concedes the
same disease** — it records `checks/substrate.py` as "766 lines at 13:00, 841 at 13:03", and it is
**936** now.

**The one prose shape worth machine-checking, and it is not a path:** a **count** whose unit is
declared (`34 of 34 byte-identical`, `242 files`, `205/205 AGREE`) is checkable *without a path*, and
`checks/nl-gate.py`, `checks/runs-artifacts.py` and `gates/gate-surface.py` already print it. That is
the shape prose should adopt: **print the number, and let the instrument that prints it be the claim.**

### 3.3 What is deliberately NOT proposed

- **Not** a global `CITES` table for prose. A table of prose claims is a hand list; the day it is
  edited apart from the prose it describes, it is a second source with no generator.
- **Not** a superset suffix scheme (`*.md`) or a basename index. 37,041 bare-filename mentions and
  10,733 directory-names-used-as-citations are precisely the populations that scheme cannot resolve.

---

## 4. WHAT HAPPENS WHEN AN ANCHOR IS ABSENT — `REFUSED` (exit 3)

**`REFUSED`, never a silent pass and never a `FAIL`.** A `FAIL` asserts the tree is wrong; a missing
anchor cannot distinguish *"the code moved"* from *"the citation never described the code"*, and
guessing between them is the fault the whole removal exists for. `disagree-gate.py:locate()` already
implements exactly this and I adopt it unchanged:

| condition | verdict | exit |
|---|---|---|
| subject present, anchor resolves, content matches | `PASS` | 0 |
| subject present, anchor resolves, content differs | `FAIL` | 1 |
| **subject absent** | **`REFUSED`** | **3** |
| **anchor matches 0 lines, or >1 line** | **`REFUSED`** | **3** |
| locator names a digest / rev / exit status / command | `REFUSED` (wrong kind of claim) | 3 |
| lane found no population to judge | `DEAD` | 5 |

**`REFUSED` must be non-zero and must never be summarised as a pass.** A census that reports
`REFUSED` as green is worse than no census, because it is trusted. `checks/cites-census.py` exits with
the worst verdict present and prints the token; its **`1,743 REFUSED` is the honest size of the hole
this unit cannot measure**, not a rounding error.

---

## 5. VERIFICATION SWEEP — every rc, token, timestamp

Run 2026-10-14 16:01–16:03, this unit, nothing else claimed:

| gate | rc | token / reading |
|---|---|---|
| `checks/no-txt.py` | **0** | `CLEAN: no .txt anywhere the project owns, outside those named exceptions` |
| `checks/nl-gate.py` | **0** | **`AGREE 205/205`** |
| `gates/gate-surface.py --report` | **0** | **`II SHELL HALF: 18`** |
| `checks/disagree-gate.py --lane citations` | **0** | `ok CITATIONS` |
| `checks/census.py` | **0** | `NEITHER : 7` |
| `checks/runs-artifacts.py` | **0** | **`ARTIFACTS-FRESH`** · `runs/graphcmp/D: 242 files, newest 4.8 h old` |
| `checks/index-arm-gate.py` | **3** | **`REFUSED, NOT A VERDICT`** — 373 intent-to-add, 4 stale |
| `checks/bounded.py --selftest` | **see below** | |
| `runs/graphcmp/D` | — | **242 files**, unchanged for the whole session |

### 5.1 `checks/bounded.py --selftest` is **FLAKY** — the brief's `rc=0` is not a fact

Measured **5 runs**: run 1 **`rc=1`**, run 2 `rc=0`, runs 3–5 `rc=0`. The failure is named:

```
[   FAIL] ORPHAN: a grandchild is still watched after its parent exits
          exit 0, token WITHIN-LIMITS
=== selftest FAIL: 13 case(s) run, 1 failed ===
```

The guard reported `WITHIN-LIMITS` where the case expects a kill. **A one-in-five flake in the guard
that wraps every `bend` process in this tree**, and the brief states its expectation as a plain
`rc=0`. I did not diagnose it further and I did not touch the file. **It is `FAIL` sometimes, so it
cannot be cited as `rc=0` without the timestamp and the run count.**

### 5.2 `.git/index` **CHANGED THREE TIMES** during my run — `REFUSED`, not PASS

The brief asks me to verify "`.git/index`'s sha256 unchanged by your run". It changed **three
times**, and the third time **it armed my own 17 files**:

```
15:31  e4acb6f4b74bf16ec4aca737146d382ac6f03b743c2022e5e3ef645ff08b882a   (my "before")
16:01  8672e4991473a3db28fd2ab938893e74e6719d23bc8a623ef86688e7c0f94234
16:04  b1ec60045302b0c92ef28118188de30bf2d5a098b9cbc90d00e40fc4cfb44b70
```

**And it happened to me, live.** At 16:01, `git ls-files -- checks/cites-census.py .agents/slop/dangle/`
answered **0**. At 16:04 it answers **17** — all 17 of my files, armed with git's **EMPTY blob**:

```
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391  .agents/slop/dangle/census.out
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391  checks/cites-census.py
$ git status --porcelain=v2 -- checks/cites-census.py
  1 .A N... 000000 000000 100644 0000…  checks/cites-census.py
$ git diff --cached --name-only | grep -c 'cites-census|dangle'
  0
```

**A snapshot by another unit armed 17 files I never staged, over the EMPTY blob, and `git diff
--cached` still names 0.** I issued **no** `git add`, no `git commit`, no `jj` command, and
`GIT_INDEX_FILE` was never set — the entire hazard arrived from outside my unit.

**The check is `REFUSED`, not satisfied.** "The index did not move during my run" is **not a
property of any unit** in a tree with this many concurrent writers; it is a race that cannot be won
by being careful. `checks/index-arm-gate.py` (**rc=3**) is the right instrument, and its own verdict
text says it: *`REFUSED, NOT A VERDICT … The tree is fine; the TOOL is pointed wrong.`* **My brief's
requirement is unsatisfiable as written, and the unsatisfiability is the finding.**

> **A bare `git commit` right now would act on these 17 paths.** For a path that does not exist in
> `HEAD` that is harmless; for a path that *does* exist it commits the **PREVIOUS** content, silently.
> The hazard is silent reversion, not an empty blob.

---

## 6. WHAT I DID NOT DO, AND WHAT I AM NOT REPORTING

- **Committed nothing. Staged nothing.** `GIT_INDEX_FILE` was never used because no `git` write ran.
- Did not edit `AGENTS.md`, `checks/differ.py`, `checks/disagree-gate.py`, `checks/sweep.py`,
  `checks/census.py`, `checks/runs-artifacts.py`, `.gitignore`, or `checks/bounded.py`.
- Did not tick `.agents/TODO.md` — the brief scoped me to `checks/` and `.agents/slop/dangle/`, and
  that file is being written live by other units.
- **Did not re-derive the prune's forward direction.** The orchestrator measured
  `0 named VERBATIM, 0 opened at runtime by AST` across the 46 deleted `.md`; I take those as given
  and did not spend the budget re-measuring them. **My unit is the reverse direction and is
  independent of them.**
- **`differ.declared()` I did not re-count.** `checks/no-txt.py` is rc=0 and its EXCUSED lines name
  the carve-outs; the brief's `176` is not restated here because I did not measure it.

## 7. THE ONE-LINE ANSWER

> **The positional shape is already dead in live code (0 instances), so the remaining problem is not
> the shape — it is that 2,764 prose citations and 53,495 unresolvable names survive in a tree where
> files have shrunk by 10× and the prose has not moved. Prose cannot be anchored; it should carry a
> date and print its counts instead of citing its sources.**