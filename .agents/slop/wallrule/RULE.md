# WALL RULE

Adopted 2026-10-05. Prefix `WALL/`. The prior draft lived at `.agents/slop/WALLRULE.md`;
this file supersedes it and the differences are the instrument's, listed at the foot.

## WALL/1 — A WALL NAMES ITS PREREQUISITE, AND A WALL WHOSE PREREQUISITE LANDED IS *STALE*, NOT *RETIRED*

> **A WALL SAYS "THIS CANNOT BE DONE." A STALE WALL SAYS "NOBODY HAS CHECKED SINCE." THEY LOOK
> IDENTICAL IN A NOTE, AND THE SECOND ONE IS WHAT GETS FORWARDED AS FACT — WHICH IS WHAT
> HAPPENED HERE NINE TIMES IN ONE DAY, INCLUDING TWICE BY THE COORDINATOR INTO THE NEXT BRIEF.**

Three fields, and the wall is checked or it is not:

| field | meaning | absent ⇒ |
|---|---|---|
| **(a) anchor** | the symbol a grep can settle it — `file` + pattern, or the command that re-runs it | the wall is a **story** |
| **(b) reopen** | the exact check whose result would clear the wall | the wall is a **permanent veto** nobody can retire |
| **(c) date** | `YYYY-MM-DD` of the measurement that PRODUCED it, not of the read | the wall ages silently |

**Anchor + reopen + date is a claim. Anchor alone is an anecdote with a coordinate.**

### The two retirement acts, never conflated

- **RETIRED — the capability ARRIVED.** Delete the wall. Say *what arrived and where it landed.*
  A deleted wall is a wall somebody will re-derive, so say it in the commit message.
- **STALE — the prerequisite landed, the original question was never re-asked.** Annotate in
  place with the new measurement and its date. **Do not delete a wall because it is stale.**

### Two refinements this sweep forced, both measured

**A WALL IS A CLAIM ABOUT A TREE, SO THE ANCHOR NAMES A FILE, NOT A FINDING.**
W3's anchor was `runtime/dtype.c emit` — not a path. A grep of a nonexistent file answers
nothing, and under `DEFECT` polarity "nothing" reads as "the defect is GONE," so a wall with
no file behind it was reported as a measurement. **A scope that is readable in neither the
working copy nor HEAD is a REFUSAL, never a verdict.**

**THE ANCHOR'S POLARITY IS PART OF THE CLAIM, AND AN INVERTED ONE INVERTS THE VERDICT.**
`MISSING` (a capability is absent) and `DEFECT` (a defect is present) are opposite readings of
the same grep. **Three of the first nine rows were inverted** and all three read "ABSENT, the
wall stands" for capabilities that had landed.

### And the corollary that is the sharp one

**A WORKING COPY AND `HEAD` ARE TWO TREES AND THEY DISAGREE WHILE A REWRITE IS IN FLIGHT.**
Four of nineteen rows are `SPLIT` right now: `uop/ops.bend` is 6,306 working lines against
HEAD's 8,334. **`SPLIT` is not `LANDED` and not `STANDS`. It means WAIT**, and it is the
answer for `noneshape/ns-oparg.bend`, which compiles or not depending on which tree you ask.
This is the instrument's most load-bearing verdict and it is why the sweep read two trees.

## WALL/2 — A COMPRESSED OBSERVATION IS A NEW CLAIM AND IT OWES THE SAME EVIDENCE

> **"THE PIPE IS THE TRAP" COMPRESSED TO "`md5` TAKES ONE FILE" DROPPED THE MECHANISM AND KEPT
> THE AUTHORITY.** `md5 -q a b` works; `find … | md5 -q` is a no-op because `md5` reads stdin.

Compression is where truth loses its falsifier. Dropping the mechanism leaves a rule **wider
than its evidence**, and therefore wrong exactly where it will be used. So every rule recorded
from an observation carries:

- **(a) mechanism** — why the observation implies the rule, in one clause that could be tested;
- **(b) counterexample test** — a case where the rule must *not* apply. No out-of-scope case
  is an overfit, and this is what `md5 -q a b` is;
- **(c) the command** — re-runnable verbatim.

A rule whose mechanism cannot be stated in one testable clause is a slogan, **and a slogan must
not be cited as the grounds for a decision.**

## WALL/3 — A CITATION SUPPORTING A *DECISION* IS A DIFFERENT KIND OF CLAIM FROM ONE SUPPORTING A NOTE

> **A `file:line` IS A COORDINATE IN A SYSTEM WITH AN OFFSET.** A +32-line header moved every
> body citation in a generated file by exactly +21. **CITE GENERATED FILES BY NAME.**

- **NOTE citation** — supports a note. WALL/1's three fields.
- **DECISION citation** — the cited text is the *warrant* for a choice. Obligation is stronger:
  **quote it, do not point at it**, because the pointed-at line moves and the decision silently
  inherits every future edit of it.

**A FALSE PREMISE INSIDE A DECISION LOOKS DERIVED, SO NOBODY RE-DERIVES IT.** This sweep found
two live instances of exactly that shape, both still in the tree:

- `uop/fold.bend:513` justifies "a dim is not a value this port needs 64-bit arithmetic for"
  by stating *"`helpers.bend` has `i64_add` and `i64_sub` but no `i64_mul` or `i64_div`"*.
  `helpers.bend:2206` and `:1969` declare both. **The warrant is false; the decision may still
  be right — and nobody can tell from the file, which is the point.**
- `uop/weak.bend:15` names `i64_mul`, `i64_div`, `i64_mod` as the missing pieces of a wall. All
  three are declared. Its *other* claim ("there is no F32 min/max") was NOT checked and is
  therefore not counted here.

## WALL/4 — COUNT NO NUMBER YOU DID NOT MEASURE YOURSELF

A count in a note is a measurement **of the file it was taken in, at the time it was taken**.
Re-measure before citing. Nine counts in these notes were stale, each individually true once.

**Corollary for instruments: AN INSTRUMENT THAT CANNOT FAIL IS NOT AN INSTRUMENT, IT IS A
COMMENT THAT ADDS UP.** Report its **hit rate and its error rate against a stated denominator.**

## THE INSTRUMENT

`wallcheck.py` · one grep per wall against its anchor, in the working copy **and** at HEAD.
(It replaces `wallcheck.sh`, which this unit found already in the tree and deleted: two
instruments over one ledger is a second dialect, which is WALL/1's own disease. Its `hit
rate`-style self-report is reproduced here and its `landed` computation was dead code —
assigned on two consecutive lines and read by neither.)
Run: `.venv/bin/python .agents/slop/wallrule/wallcheck.py [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.] [ID ...]`

Verdicts: `STANDS` · `LANDED` (MISSING wall's capability arrived) · `GONE` (DEFECT wall's defect
is fixed) · `SPLIT` (trees disagree — **wait**) · `NO-SCOPE` · `STORY` · `OUT-OF-SCOPE`.

Polarity per row: `MISSING` · `DEFECT` · `RUN` (prerequisite is a re-run, never guessed at with
a pattern) · `PROSE` (the defect is a **sentence**, so the anchor reads comments too — without
it, five rows are unfalsifiable in the safe direction).

Exit 0 all stands · **1** something moved (the number the rule exists to produce) · 2 ledger
unreadable · 3 a row is a STORY · 4 **selection matched nothing — a guard over an empty
population is refused, never `CLEAN`** · 5 nothing was graded.

### MEASURED, 2026-10-05

19 rows · **15 graded** against `walls.truth.tsv` (hand-measured, independently) · 4 refused
(3 `RUN`, 0 wrong to grade) · **agreement 15/15, error rate 0/15** · outcomes **4 LANDED,
3 GONE, 3 SPLIT, 5 STANDS, 4 OUT-OF-SCOPE**.

**Four plants, all fired, all files restored byte-identical (`cmp`):**

| plant | expected | got |
|---|---|---|
| rename `def i64_mul(` | W1a flips | `LANDED` → `SPLIT (pin only, work=0 pin=1@2206)` |
| re-add `import "./runtime/dtype.c"` to `dtype.bend` | W11 flips | `GONE` → `SPLIT (work only) — LIVE in the shipping copy` |
| rename `def mm.u64.of(` | U2 flips | `STANDS` → `SPLIT (pin only, work=0 pin=1@2681)` |
| rename `def mm.u64.of(` **before the split verdict existed** | must fail | **still `STANDS`** — this is how the verdict was found |

**HIT RATE IS 100% AND THAT IS NOT THE NUMBER THAT MATTERS.** Every anchor matches, so the
instrument reports a verdict for all of them; the informative number is the **0/15 error rate
against an independent truth file**, plus the 4 refusals, which are reported as refusals rather
than folded into agreement. **An instrument that graded the rows it declined to judge would
report agreement it did not measure.**

### The five ways this instrument was wrong, each found by a plant or a disagreement

1. **v1** whole-tree patterns: `PRESENT` for 11 of 11 — several matched the wall's own prose.
   Hit rate 100% = no information.
2. **v2** working copy only: called W4/W8 `STANDS` for capabilities at HEAD.
3. **v3** `runtime/dtype.c emit` is not a path; `[[ -r scope ]]` failing silently made it `GONE`.
   → `NO-SCOPE`.
4. **POSIX `[[:space:]]` is a nested set to Python's `re`** — one anchor of eighteen could not
   compile and would have graded forever. Anchors are now translated, not the ledger rewritten.
5. **A coarse anchor cannot fail.** `^def (i64_mul|i64_div|i64_mod|i64_shl)\(` read `work=4`;
   a plant removing one of the four moved it to 3 and the verdict did not change. **Split into
   W1a/W1b, and W1a's plant now fires.** *This is the "instrument that cannot fail" defect in
   its purest form, and it is why an error rate needs a denominator.*

**KNOWN LIMIT, STATED NOT HIDDEN: ONE LABELLER.** Every row of `walls.truth.tsv` was measured by
the agent that wrote the anchors, so 0/15 is a **self-consistency** rate. It cannot detect an
anchor and its truth wrong in the *same* way — which is this project's dominant failure mode.
**And on its first pass 3 of 18 hand-labels were wrong, with the instrument right on all three**
(W4/W8 read off the working copy alone; U7 called a def RETIRED because the working copy had
half-deleted it). The column earned its place in its first run.

## WALL/5 — A WALL NOBODY WROTE DOWN IS INVISIBLE TO EVERY SWEEP

A grep can only re-measure walls that are in the ledger, so **the ledger's own completeness is
a wall on the instrument.** Four found by reading, none recorded anywhere: `#ifdef CID(...)`
(the `CID` macro a `cc` run rejects, `runtime/sz.c:126`), the `NV` dead arms (`NV-1`'s
`def t_const`), the `sz.c` stat/lstat shim (`sz.bend:51`), the `Args` spelling
(`ops_python.bend:1469` — a gather row named `Args` beside the domain type imported as `O.Arg`).
Three of the four are in this ledger as U-rows. **A sweep reports its own denominator, and a
sweep that finds nothing new has not looked hard enough to be believed.**

## WALL/6 — THE CHAIN REMEMBERS MORE THAN THE PATHSPEC DOES

`jj bookmark set master -r @-` moves master along the **whole ancestry**, so any leftover
uncommitted commit in the chain is published with it — two leftovers from before a server
restart were dragged onto `master`, **both invisible to `jj split <paths>`**. This is `jj split`
being a ledger of the paths you remembered, one level up. **Before moving a bookmark, read the
chain, not the pathspec.**

## WALL/7 — WHAT I WOULD HAVE ADDED TO `agent-core.md` AND DID NOT

That file is owned by the unit reconciling the three coldness numbers, so this is reported
rather than edited. One block, under the existing `--check-only` wall:

> - **A WALL IN A FILE HEADER IS A CLAIM AGAINST A FILE NOBODY RE-READS.** `mixin/dtype.bend:52`
>   says `i64_mul` is "NOWHERE. Not helpers.bend, not dtype.bend, not any tinygrad .py" — over
>   `helpers.bend:2206`, which declares it. The wall's own next paragraph conceded div/mod
>   exist. **A header is the part of a file least likely to be re-read and most likely to be
>   believed**, so it is where a wall rots fastest. Any wall in a header carries its anchor,
>   and `agents/` re-measures anchors on load. Precedent: `WALL/1`, and the nine rows in
>   `.agents/slop/wallrule/walls.tsv`.