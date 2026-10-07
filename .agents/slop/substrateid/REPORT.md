# `substrateid` — `D0-run-summary.txt` RECORDS THE ENVIRONMENT AND NOT ONE BYTE OF THE PORT

Unit: `substrateid`. All numbers below were measured in this session; none are inherited.
Instruments, all under `.agents/slop/substrateid/`:

| file | what it measures | rc |
|---|---|---|
| `measure.py` → `measure.out` | how the 148 are derived; anchors; the two absent inputs; the three blockers | 0 |
| `cost.py` → `cost.out` | warm and cold cost, and read-vs-hash split | 0 |
| `plant.py` → `plant.out` | **20/20**, incl. the mid-run case | 0 |
| `impact.py` → `impact.out` | set-drift against `snapshot.py`; the four parsers | 0 |

A predecessor incarnation of this unit left `blockers.{py,out}`, `plant.out`, `cost.out`,
`inputs.out`, `measure-inputs.py`, `population-drift.out` here at 06:56–07:09, with **no
`REPORT.md`** — it died before reporting. Its `cost.out` claims 35 ms; I measure a **floor of
252 ms**. Its numbers are **not** reused. Its `blockers.py` loads `checks/substrate-id.py`,
which exists (533 lines, 07:05) and is **wired into nothing** — see §4.

---

## 0. WHAT IT DOES NOT FIX — FIRST, BECAUSE IT IS THE PART THAT GETS REPORTED LAST AND READ FIRST

1. **It does not make the 17 pins independent.** They still all read `D0-run-summary.txt`.
   `pinindep` is right: `17/17 green` is one run's 17 rows, denominator 1. Two more rows in
   that same file change nothing about that. Measured here too: all 17 pin keys are absent from
   `PINS`' substrate names, because **neither row is pinned** — see §2.
2. **It does not stop a mid-run break on the HOT path.** `pinindep` measured **12 of 17 pins
   go red** when a finished artifact set is edited. Nothing here changes that number.
3. **A hash proves WHICH substrate ran, not that the substrate was CORRECT.** An artifact set
   that faithfully records a broken substrate is still a broken measurement. Recording it
   better is not the same as fixing it, and these rows make no claim about the port being right.
4. **It is not executed end-to-end.** `bend` is off-limits in this session, so `differ.py run`
   (294 s, ~56 `bend` launches) was never run. Every landed function is exercised directly and
   the *ordering* is verified by `ast` (§5, C), but **no fresh `D0-run-summary.txt` exists on
   disk carrying the rows.** That is stated as a limit, not as a pass.
5. **The landing makes every pre-existing summary unhealthy** until one fresh run rewrites it.
   Measured: `unhealthy()` against the live summary goes from 0 substrate complaints to **2**.
   See §4 — that is blocker 3 biting, and it bites toward REFUSAL, not toward a silent green.

---

## 1. HOW THE 148 ARE DERIVED — DISCOVERY OR LIST

`quiesce/snapshot.py:74-86`, `inputs()`:

| source | shape | count |
|---|---|---|
| `snapshot.py:78-79` `tinybendygrad/**` `rglob`, minus `__pycache__` | **DISCOVERY** (directory walk) | **140** |
| `snapshot.py:80-85` `COPIES` (`snapshot.py:63-67`) | **LIST** (hand) | **8** files over 10 entries |
| | | **148** |

`140 + 8 = 148` is asserted by `measure.py`, so `inputs()` is *exactly* walk + list and nothing
else. The list is **5.4 %** of the population.

### Is a hand list of 8, anchored, the same fault as `coindependent`'s 42?

**No, and the distinction is measured rather than argued.** `zerogate` named the 42 because it
was a bare list. `COPIES` is a list, but it is not *bare*:

| COPIES entry | on disk | row in `FILES` anchor table (`:50-59`) | named in a consumer |
|---|---|---|---|
| `bin` | yes | **0** | `differ.py:43` |
| `checks/differ.py` | yes | 6 | — |
| `checks/devpin.py` | yes | 1 | `differ.py:763` |
| `.agents/slop/graphcmp.py` | yes | 2 | — |
| `.agents/slop/graphcmp.bend` | yes | **0** | `differ.py:132,168` (comment) |
| `.agents/slop/graphcmp-dbg.bend` | **ABSENT** | **0** | `differ.py:579`, `graphcmp.py:274` |
| `.agents/slop/graphcmp-empty.bend` | **ABSENT** | **0** | `differ.py:576,588` |
| `.agents/slop/graphcmp-oracle.py` | yes | 1 | — |
| `.agents/slop/graphcmp-dbg-oracle.py` | yes | 1 | — |
| `.agents/slop/graphcmp-p13-ops.py` | yes | 1 | — |

- **4 of 10** entries have **no row in the `FILES` anchor table** — and `--declare` asserts
  *only* that table, so it structurally cannot see those four. Its own header claims the
  anchors; the gap between the header and the table is the fault.
- **0 of 10** are named **nowhere**: every entry appears in `differ.py` or `graphcmp.py`. So
  the list is *traceable*, which the 42 was not.

**Verdict:** an anchored list of 8 is admissible under AGENTS.md's third form (rule (c): a list
with its anchors admitted and checkable). It is **not** the same fault as 42. The residual is
that **4 of the 10 anchors are absent from the one table whose job is to hold them**, and the
two `.bend` fixtures are anchored only in a **comment** (`:576`, `:579`) — a comment is not a
write site, so removing the run's use of them would leave the anchor intact.

### The two absent inputs, and the silent drop

`graphcmp-dbg.bend` and `graphcmp-empty.bend` are named at `snapshot.py:65-66` and **absent on
disk** (deleted in `371cc64c9`). Measured:

- `--declare` **exits 1** and prints `ABSENT ON DISK` for both.
- `inputs()` returns **148**; both paths are **not in it** — `snapshot.py:85` is
  `elif p.is_file():` with **no `else`**, so a declared-but-absent path is dropped silently.
- `build()` therefore prints **`froze 148`** and **exits 0** on the same tree where
  `--declare` exits 1.

**This is the same shape as `indextree`'s finding that `git ls-files` cannot see a file
`git ls-tree` sees: a declaration that is right and a walk that drops what it names.** The
docstring at `snapshot.py:76-77` claims "A named path that is ABSENT is returned as well (by
`--declare`), never silently dropped" — and the code does drop it in the only path that
freezes anything. **The comment is right and the branch is not.**

**And the walk half is worse**: measured on a temp tree, `b.bend` deleted → the walk emits
`['a.bend']` and the deleted name appears **nowhere**. A walk cannot see its own deletion.
That is precisely why the landed digest (§4) hashes the token `ABSENT` for a declared path
that is not there.

---

## 2. THE TWO ROWS, AND EXACTLY WHAT THEY COMPARE

### The aggregation

**One sha256 over a sorted stream of `(relpath, sha256(bytes))` pairs** — a git-style tree
hash, folded to a single 64-hex token.

- **Keyed on:** the file's path **relative to `ROOT`**, and its **content**. Never `st_mtime`,
  never the absolute path, never directory iteration order (`sorted()`).
- **Absent declared paths contribute the literal token `ABSENT`**, so the population cannot
  silently shrink and a deletion moves the digest.
- Measured: **148** inputs, **11.35 MB**.

**Rejected, and why:**

- **One hash over 148 inputs detects a change and says nothing about *which*.** That is why the
  answer is two rows and not one: with one hash you learn *that*, with a per-file manifest you
  learn *which* at the cost of 148 rows in a file four `key=value` parsers read. The two rows
  get the *comparison*; the diagnosis of *which file* stays a one-liner:
  `diff <(snapshot.py --build a) <(snapshot.py --build b)`.
- **A per-file SHA column** would be 148 rows in a summary whose consumers split on `=`, and
  `env-precond.py`/`corpus-figure.py` iterate its keys. Proportionally absurd.
- **A git tree hash** (`git write-tree`) needs `git`, which `differ.py:58-60` refuses on
  purpose. A content hash of the same shape needs nothing. **The refusal is about the
  dependency, not about the shape.**

### What the two rows compare — and why **two**, not one

| row | taken | meaning |
|---|---|---|
| `substrate-start=<h>` | **before the first `emit`** (AST-verified, §5 C) | H0: the bytes the run began with |
| `substrate-end=<h>` | **after the last `emit`**, as an argument to the `write` that makes the summary | H1: the bytes the run ended with |

- **One row would be a LABEL.** `substrate=<h>` says what the substrate *was*; nothing compares
  it, so it cannot go red. That is the `?`-assertion with no fixture, and it is the same defect
  `preconditions_bad()` exists to prevent for `dev` and the three ENV rows.
- **Two rows are a COMPARISON**: `start ≠ end` means **this run is a MIXTURE of two
  substrates**, so no artifact set in `D/` describes one thing. Both halves are recorded, so
  the diagnosis is checkable rather than asserted.

### WHERE H0 COMES FROM — the hard part, and it is cheaper than it looks

H0 **lives in row 1 of the same file**, written by the same run. It is **not pinned and must
not be**:

> A pin on a substrate digest would have to be re-pinned **every time the port moves** — i.e.
> red by construction after any real edit. That is `pinindep`'s finding (17 pins on one file is
> one measurement wearing 17 hats) made strictly worse. Measured: neither `substrate-start` nor
> `substrate-end` is in the `PINS` table, so `unhealthy()`'s `k in PINS` arm ignores them and
> only `substrate_bad()` can judge them.

So the comparison needs **no second witness, no external ledger, and no new parser**. This is
the smallest answer to "where does H0 come from": H0 is not a historical fact needing a store,
it is the first half of a pair the run measured about itself.

**Why not compare against a *recomputed live* digest** (the shape `checks/substrate-id.py`
uses)? Because it makes a good run unhealthy the moment any unrelated unit touches the port —
and units are touching this tree continuously (measured: the port went **280 → 140 files**
during this session). Start-vs-end has a **false-positive rate of zero by construction**: it
fires only when the tree moved *during* the run, which is the defect.

---

## 3. THE BLOCKER, ANSWERED DIRECTLY

**NONE OF THE THREE BLOCKS A CONTENT SHA.** Each re-tested, not inherited:

| blocker | verdict | measurement |
|---|---|---|
| (1) `differ.py:58-60` refuses a `git` dependency **on purpose** | **NOT HIT** | the digest path imports `hashlib`, `pathlib`, `os`. No subprocess, no ref read. `git` is on `PATH` here and is never invoked. |
| (2) `runs/` is gitignored, so an **mtime** is a fact about this tree; two clones disagree | **NOT HIT** | clone A `72f4b3f9eac6b905` == clone B `72f4b3f9eac6b905`. Then **every mtime in B rewritten across a 4 000 000 000 000 ns spread** → digest **unchanged**. A content sha never reads one; an mtime rule would have had to compare all three. |
| (3) writing two rows **moves consumers it does not own** | **BIT — ONCE, MEASURED** | see §4. It is the only one a sha can hit, and it bites in the safe direction. |

**So the answer is "none of them", which means the residual IS solvable and the mtime rule was
the wrong instrument for a different reason:** blockers (1) and (2) are about *where the
number comes from*, and a content hash sidesteps both by not consulting an external store and
not reading a timestamp. Blocker (3) is about *where the number is written*, and no
aggregation dodges it — it is a cost of the instrument, not a property of the key.

**Blocker 3, measured, in full** (`impact.out`):

- `checks/disagree-gate.py` reads `graphs-disagree=` **by name** → an extra row is invisible.
- `checks/env-precond.py` `declared_values()` reads its own key list → invisible.
- `checks/corpus-figure.py` splits on `=` → invisible.
- `checks/differ.py` `unhealthy()` → **MOVES**: 0 → **2** complaints on every pre-existing
  summary. This is `gates/retention-check.py`'s CLAUSE IV and `clean_run()`, which call it by
  reference.

**The bite and why it is the right one:** the summary on disk was written before these rows
existed, so its other 22 rows are claims about bytes nobody recorded. `ABSENT` here is
**REFUSAL, not FAIL and not a silent green** — and `clean_run()` re-runs `run` before judging,
so it clears itself in one pass. **A row that could not redden a stale summary would be a
label**, which is the entire justification for paying this cost.

---

## 4. WHAT LANDED, AND WHERE H0 LIVES

**LANDED. Two rows in `D0-run-summary.txt`. No new file. No new parser. No new pin.**

`checks/differ.py`, **+105 lines** (a 104-line block at `:786-889`, **61 of them non-blank
non-comment**; the file is 1133 → 1238). `ruff check checks/differ.py` → **1 error, and it is
pre-existing at HEAD** (verified by running `ruff` on `git show HEAD:checks/differ.py`: same
`line-too-long`, at line 600 there / 603 now). **Zero new lint.**

Four pieces:

| site | what |
|---|---|
| `SUBSTRATE_INPUTS` / `SUBSTRATE_ROWS` | the population and the row names, with anchors in the comment |
| `substrate_digest()` / `substrate_entries()` | the tree hash; `ABSENT` for declared paths not on disk |
| `substrate_rows(start, end)` | the two lines |
| `substrate_bad(got)` | **the comparison** — a function beside `unhealthy()`, never inside `PINS` |
| `cmd_run` | `substrate_start = substrate_digest()` before the first `run(...)`; the second digest inside the summary `write` |
| `unhealthy()` | `+ substrate_bad(got)` |

**H0 lives in `substrate-start=`, row 1 of the run's own `D0-run-summary.txt` — the file four
parsers already read.** There is no ledger, no pin and no second file.

**Population, as landed:** 140 (directory walk over `tinybendygrad/**`) + 8 named files =
**148**. Measured against `snapshot.py`'s: **the two sets are IDENTICAL, 0 of 148 paths
disagree.**

**The residual that measurement did NOT kill:** they agree *today* because `bin/` happens to
hold exactly one file. `snapshot.py` walks `bin/` **recursively**; `differ.py` names
`bin/bend`. Add a second file under `bin/` and the freeze gains an input the digest does not
have, with nothing saying so. That is **two declarations of one population** — doctrine 1's
shape. They are separate instruments and cannot import each other, so the guard is the set
diff in `impact.py`, not a comment.

**`checks/substrate-id.py` (533 lines, 07:05) is NOT wired into any gate, is now redundant
with this landing, and I did not delete it** — this unit does not own it, and deleting is how
inputs vanish. Flagged, not touched.

---

## 5. THE PLANT — AND IT COVERS THE **MID-RUN** CASE

`plant.out`, **20/20, rc=0**. No `bend`, no `differ.py run`, no real artifact written or
deleted.

**Answer to the direct question: it covers the MID-RUN case, and it covers the between-runs
case separately and labels it as the easy one. They are not the same test and the output says
which is which.**

| section | case | result |
|---|---|---|
| **A** | **BETWEEN RUNS** (easy, explicitly *not* the claim): same tree → byte-identical; one edit → moves; restore → **byte-identical** | 3/3 OK |
| **B** | **MID RUN** (the question): `start` taken → **`PROOF.bend` edited inside the bracket** → `end` taken. Rows **DIFFER**; **exactly one** complaint, naming both rows. Control: a run that did not move raises **nothing**. | 4/4 OK |
| **C** | **THE ORDERING** — without this, B tests a function `cmd_run` might not call. `ast` reads `cmd_run`: `substrate_start` at **stmt 2**, first `emit` at **stmt 3**; the second digest is an argument to the `write` that makes the summary; **exactly 2 digest call sites**, lines 462 and 679. | 3/3 OK |
| **D** | **the what-it-does-not-do control**: a port edit is invisible to every pre-existing row; absent rows give 2 complaints that matching rows remove, **with no other delta**; the pre-existing `dev` complaint is **unchanged**. | 6/6 OK |
| **E** | the other shapes: moved → 1, half-present → 1 naming the **missing** row, none → 2 | 4/4 OK |

Verbatim from `plant.out` §B:

```
substrate-start=dbbeafb137c2 but substrate-end=642b768ff199 -- THE SUBSTRATE MOVED
WHILE THE RUN WAS IN FLIGHT, so D/ holds a MIXTURE of two substrate...
```

**Two assertions in my first plant run FAILED and both were the plant's fault, not the code's**
— recorded because that is the only evidence the plant can fail: a substring count reported
**3 digest calls for 2** (it was matching `def substrate_digest() -> str`), and an
absolute-zero claim on `unhealthy()` failed because the **rig's** temp `D` holds no artifacts,
so the **pre-existing** `dev` cross-check fires on its own. Both assertions were wrong; the
code was right. Fixed to a set-delta and an AST call-site count.

**What the mid-run plant does NOT cover:** it drives the landed functions and the landed
ordering, but **no real `bend` ran**, so it does not prove a real 294 s run emits the pair. It
also edits only **one cold input** (`.bend`). It does not cover a mid-run edit to a **hot**
input (e.g. `graphcmp.py` re-read by every `gc()`), which would produce a *different*
mixture — some artifacts from H0, some from H1 — and the rows would report it as the same
one-line verdict. **The plant covers the mid-run case. It does not cover the hot/cold
distinction, and no instrument here does.**

---

## 6. COST, IN THE UNIT ALREADY USED

`cost.out`, 15-sweep tight loop, **contended** — other units are writing this tree.

```
population : 148 inputs, 11.35 MB
one digest, WARM (tight loop)   min  252.3 ms   median  583.8 ms   max 1270.6 ms
one digest, COLD (after purge)  min  365.1 ms   median  506.5 ms   max  660.9 ms
read 148 files                  min  106.9 ms   median  198.9 ms
sha256 148 buffers              min   18.0 ms   median   54.9 ms
```

| basis | two digests (start + end) | of a **warm** 294 s run | of **one cold bend launch** (~2.8 s, `bendperf`) |
|---|---|---|---|
| warm **median** (contended) | **1167.5 ms** | **0.397 %** | 41.7 % |
| warm **floor** (best of 15) | **504.5 ms** | **0.172 %** | 18.0 % |
| **COLD** page cache, median | **1012.9 ms** | 0.344 % | **36.2 %** |

**A percentage of a warm run is not a percentage of a cold one, and this is the number that
matters:** on a cold page cache the two digests cost **36 % of a single `bend` launch**. Taken
**once per run** — not per `emit` — that is ~1.0 s out of 294 s. Taken per emit it would be
~56 launches × 0.5 s = 28 s, ~10 % of the run, which is why the landing brackets the run
rather than sampling it.

**Three honest caveats:**

1. **The measurement is contention-dominated and I say so rather than quoting the median.**
   min/median/max spread is **5.0×** in one run, and the **COLD median (506 ms) came in
   BELOW the warm median (584 ms)** — a colder cache cannot be faster, so the two columns are
   measuring noise, not cache state. **Read + hash of already-read buffers is 162 ms at the
   floor; everything above that is other units writing the tree.**
2. **`midrun`'s 56 ms and the predecessor's 35 ms are ~5× below my measured floor of 252 ms.**
   They are not reproducible on this host tonight. The defensible claim is the **ratio**,
   not the milliseconds.
3. **Rows: 2 of 24 (8.3 %). Parsers: 0. Files: 0. Pins: 0.**

---

## 7. RESIDUALS, NAMED

1. **The 17 pins are still one measurement.** These rows do not touch that.
2. **Two declarations of one population** — `differ.py`'s `SUBSTRATE_INPUTS` and
   `snapshot.py`'s `COPIES`. Identical today (0/148); they drift if `bin/` gains a file. Guard
   is `impact.py`, not a comment.
3. **4 of 10 `COPIES` anchors are absent from the `FILES` table** that `--declare` asserts,
   and two `.bend` fixtures are anchored only in a comment. Reported, not edited — that file
   is not mine.
4. **`inputs()` silently drops 2 declared-and-absent inputs** while `--declare` exits 1 and its
   own docstring claims they are "never silently dropped". Reported, not edited.
5. **The hot/cold mid-run distinction is unplanted** (§5).
6. **No end-to-end run.** `bend` was off-limits; the rows are not on disk yet.
7. **A hash proves which substrate ran, not that it was correct.** See §0.3.
8. `checks/substrate-id.py` — 533 lines, unwired, now redundant. Flagged, not deleted.

**NOT DONE, DELIBERATELY:** `.agents/TOOLS.md` and `.agents/TODO.md` were not edited. This
unit owns `.agents/slop/substrateid/` and `checks/differ.py`; `TOOLS.md` is the 333-path ledger
`AGENTS.md` itself records as having **180 dead entries, 14 of them instruments**, and adding to
it by hand is the shape that produced that number. Reporting here instead.