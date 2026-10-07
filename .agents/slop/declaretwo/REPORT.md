# `declaretwo` — what counts as a DECLARATION, re-derived, and what the census cannot see

Measured **2026-10-07 18:45–19:40 +0300** against the immutable commit **`389aa61c5d50`**
(`git rev-parse HEAD` at 18:45; the tree moved twice while this unit ran — see §0).
Instruments, both beside this file: `census.py` (**334 lines**), `plant.py` (**251 lines**).
**No commit, no `git add`, no `git mv` executed, no `@`.**

```
.venv/bin/python .agents/slop/declaretwo/census.py            # -> census.out + census.rows
.venv/bin/python .agents/slop/declaretwo/census.py --rename-plan   # -> rename-plan.rows, printed not run
.venv/bin/python .agents/slop/declaretwo/plant.py              # -> 31/31, temp git repos only
```

---

## 0. WHAT I ANSWER, AND AT WHICH SCOPE — because `pairs` was right and three units paid for it

`pairs` recorded that **a number without its scope is meaningless**. That is precisely why
`orcdecide` published **256**, `declare` published **262**, and I measure **265**: **they are three
answers to three different questions, and none of the three is wrong.**

> **MY QUESTION, STATED BEFORE I ANSWER IT: *how many `.agents/slop` directories does this
> repository contain at commit `389aa61c5d50`, and does each one declare itself?***

Two axes carry the disagreement, and each has been measured, not inferred.

**Axis 1 — A COMMIT, OR THE INDEX.** `orcdecide` and `declare` both read `git ls-files`. This tree's
index **has been reset six times today**. Measured at `389aa61c5d50`:

| source | count |
|---|---:|
| `git ls-tree -r 389aa61c5d50` — **a commit** | **265** |
| `git ls-files` at 18:45 — **the index** | 282 |
| `git ls-files` at 19:31 — the index, again | **460** |

The index moved by **178 directories in 46 minutes** with no commit of mine. **21 of the index's
directories are not in the commit at all** (`citeresolve`, `coindependent`, `declare`, `midrun`,
`orcdecide`, `pairs`, `msgdiff`, …), and **at 19:31 it carried 59 committed paths it had lost**.
A population read from an index is a population read from something being rebuilt under you.
**So I read `git ls-tree -r <commit>`, and I print the commit on every run.** `checks/slop-declare.py`
has the same defect — it calls `git ls-files` at `:142` — and that is the single change that would
most improve it.

**Axis 2 — WHICH REVISION.** Re-measuring the *same* question at the *same* instrument over three
revisions of the *same* tree:

| revision | time | top-level dirs | no report and no manifest |
|---|---|---:|---:|
| `6dd6ba1c9` | 06:33 | 250 | 107 |
| `905c6174a` | 17:03 | 262 | 107 |
| `389aa61c5d50` | 18:45 | **265** | **109** |

**`orcdecide`'s 256 was not a miscount; it was a reading of a tree that has since grown by 15
directories in 12 hours.** Units are landing reports right now. `declare`'s 262 matches its own
commit exactly.

**AND THE `17` vs `48` GAP IS NOT A COUNT. IT IS A READER TEST — two different tests, and I
measured the difference rather than describing it.**

| reader test | undeclared **and** unread | who |
|---|---:|---|
| `big.count(token) <= own.count(token)`, corpus **includes `.md`** | **10** at `389aa61c5d50` | `orcdecide` (`sweep.py:60`) |
| **set**-membership, corpus **CODE only** (`.py/.sh/.bend/.mjs/.ts/.js/.rs`) | **48** | `declare` (`checks/slop-declare.py:96`) |
| set-membership, corpus **CODE + PROSE** | **0** | — never run |

Three things drive it, and **each is a defect, not a choice**:

1. **`.md` counted as a reader.** `orcdecide`'s `KEEP` includes `.md`, so a **prose file naming a
   directory silences the walk**. That is `checks/slop-declare.py`'s own stated rule ("a `.md` that
   merely NAMES the directory is not a reader, it is prose about one") applied in reverse. **37 of
   the 48** are opened by no code file but only by prose.
2. **COUNT, NOT SET.** `big.count(tok) > own.count(tok)` compares *occurrences*, so a directory
   whose own files cite its path more often than the rest of the tree does is **excused for the
   wrong reason**. PLANT 7 pins this: `selfcite` cites its own path twice, `quiet` never, and the
   count test reads `selfcite` as referenced while the set test reads both as unopened.
3. **THE SAME DIRECTORY CLASS, THREE READINGS.** `orcdecide`'s **17** is its own committed
   number at 06:33; **its own code reproduced at `389aa61c5d50` gives 10**, because three of its
   17 (`citeresolve`, `coindependent`, `jjreset`) acquired declarations in the intervening twelve
   hours. **`orcdecide` is not wrong and neither am I; the number is a reading with a timestamp,
   and `pairs` is right that an untimestamped count is nothing.**

---

## 1. WHAT THE PLANTS FOUND — the harness came first, and it failed four times

`AGENTS.md`: *"NEVER write unit tests after you write code."* The plants are written to fail.
**First run: 19/25. Second: 27/31. Now: 31/31**, and the four failures were **real defects in my
own census**, not bad assertions:

| plant | what failed | the defect it caught |
|---|---|---|
| 5 | nested directories were **absorbed into the parent** | the walk stopped at depth 1, so `parent/child/CLAIM.md` was filed under `parent`. **This is the `orcdecide` "108 `.md` DIRxFILE pairs" shape, reproduced in my own instrument.** Fixed: the walk descends. |
| 6 | `md_names` compared against the **file's** depth | `files[0].count("/")` is never the directory's depth, so **every row read `P=1`**. A column that is always one is a column that measured nothing. |
| 3, 4 | `opened_by` never found a reader | `hit = line.rsplit(":", 1)[-1]` on `HEAD:path` is right, but the **prefix was `SLOP/{name}` while `name` had become the full path** — `.agents/slop/.agents/slop/x/`, which matches nothing. |
| 4 | the reader fixture opened a **hard-coded** path | the plant chose the row; the fixture did not. A plant that names its own fixture is `checks/no-txt.py`'s second-copy defect one level down. |

And the freshness column was **dead until I looked**: after the full-path refactor `age_h` joined
onto `SLOP` **and** the full path, so every one of **109 rows read `0.0 h`** while printing four
digits. **A column that is always zero is indistinguishable from a column that measured nothing**
— `prune4`'s twelve-committed-files shape. `MIN_SPREAD_MIN` is now in the file to catch it: a
population whose mtimes span under an hour is a **checkout**, and the census says so rather than
reporting every row as IN PROGRESS.

---

## 2. WHAT COUNTS AS A DECLARATION — **THE THREE ANSWERS ARE COMPATIBLE, NOT RIVAL**

One population (`389aa61c5d50`, 265 top-level), three readings:

| shape | what it asks | count |
|---|---|---:|
| **R** | a file named `report.md`/`readme.md`/`findings.md` | **153** |
| **M** | a file named `manifest.tsv`/`manifest.md`/`manifest.rows` | **4** (1 also R) |
| **R \| M** | **the name set** — what `orcdecide` and `declare` both mean by "declared" | **156** |
| **P** | **any `.md` at depth 0** — a *shape*, not a name | **216** |
| R\|M ∧ P | | 154 |
| **R\|M ∧ ¬P** | **declared under a NAME, holding no `.md` at all** | **2** |
| ¬R ∧ ¬M ∧ ¬P | neither a name nor a `.md` | **47** |

**They are nested, and that is the whole answer.** P ⊇ R\|M except for **2** directories, which are
the sharp end of the question: **`.agents/slop/strays` and `.agents/slop/oracles259` declare
themselves with a `MANIFEST.tsv` and no prose whatsoever.** That is exactly the
`plancarve`/`prune3` precedent — *"`strays/` has no `REPORT.md`; `prune3` audited it anyway because
it holds a tracked `MANIFEST.tsv`"* — and it is why
**no shape can be a superset of the other**. They are not competing definitions; they are two
answers to two questions:

- **R\|M answers: *did a unit write something with the agreed filename?*** It is a **name set**, so
  it is doctrine 1's third forbidden shape and it is what `checks/slop-declare.py` ratchets on.
- **P answers: *is this a human's directory?*** It is a shape, so it is population-by-shape and it
  is the honest *census*.

**A WALK THAT REQUIRES A DECLARATION AND A WALK THAT ACCEPTS A MANIFEST GIVE DIFFERENT ANSWERS
FROM THE SAME TREE, AND NEITHER IS WRONG** — because they were asked different things. **Which
should `checks/slop-declare.py` use? R\|M, and it already does** (`DECLARATIONS` at `:96`), for
three measured reasons:

1. **R\|M is the one with a BASELINE.** A ratchet needs a starting point; P would have started at
   216-of-265 today and 265-of-265 after tomorrow, because every unit that writes a report under
   any name moves it. **A ratchet whose population moves by authorship is not a ratchet.**
2. **R\|M is CONSERVATIVE in the direction that matters.** It under-counts (109 rather than 47),
   so it **names more**, and naming is the cheap direction. P would silence 62 directories today
   with **no human decision at all**.
3. **R\|M is STABLE under the failure mode `AGENTS.md` names** — a unit that writes `NOTES.md`
   does not make its directory declared. P would.

**IS THE OTHER STILL NEEDED? YES, FOR A DIFFERENT QUESTION — and it is this report.** P is a
*census* instrument: it answers *"which directories hold prose under a name nobody agreed on?"*,
which is a **one-time reconciliation**, not a gate. **Running it as a gate would make the number
move every time a unit types a file, which is `checks/sweep.py`'s `LIVE_UNITS` in a different
hat.** And §4 is the place the other shape is load-bearing.

---

## 3. THE 24-UNDER-40-NAMES FINDING — **RE-DERIVED, AND THE TWO FIXES ARE NOT THE SAME ACT**

**The claim was "24 of the 48 already declare themselves under 40 other names." Re-derived over the
whole undeclared set at `389aa61c5d50`:**

| | count |
|---|---:|
| undeclared under R\|M | **109** |
| **of those, holding a `.md` at depth 0 under another name** | **62** |
| of those, **holding no `.md` at all** — no rename exists | **47** |
| distinct `.md` basenames among the 62 | **91** |

**62, not 24** — the claim was scoped to the 48 (undeclared **and** code-unread), and it survives
in that scope: at the narrower reading the figure is **25**. And **91 distinct names, not 40**,
because the broader set holds far more of them.

**NOW THE PART THAT MATTERS. THE TWO FIXES LOOK IDENTICAL AND ONE OF THEM IS THE FAULT.**

- **(A) `git mv` — A REAL DECISION BY A HUMAN.** A file that already exists, already says what it
  says, moves to the name the walk looks for. The content is not touched. **46 directories have
  exactly one candidate and the plan is mechanical. 25 have two or more and the choice is a
  judgement** — `audit/` has eight (`01-proofs-34of34.md` … `08-ledger-234counts.md`), and *which*
  one is the report is a question about intent that no walk can answer.
- **(B) ADDING 91 NAMES TO `DECLARATIONS` — A HAND LIST, WHICH IS **THE** FAULT.** It would turn
  **62 directories green with ZERO human decisions**. The census would be **green by being
  LYING**: it would report that 62 units declared themselves, when in fact a name set was widened
  until the number fell. That is `gendirs.py`/`coindep.py`/`pairs` built to remove, and it is
  `AGENTS.md` doctrine 1's third forbidden shape. **I did not do it and I recommend against it.**

**LANDED: THE `git mv` PATH ONLY.** `.venv/bin/python census.py --rename-plan` writes
`rename-plan.rows`:

```
git mv .agents/slop/adev/CLAIM.md .agents/slop/adev/REPORT.md      <- 46 of these
AMBIGUOUS .agents/slop/audit has 8: .../01-proofs-34of34.md ...  <- 25 of these
```

**46 unambiguous, 25 ambiguous, 71 directories total, 0 colliding targets.** Two properties make
this the right artifact: it is **discovered** (the walk finds the `.md` files; no directory is
named in the code), and it **cannot be run by me** — a `git mv` is a commit, and the tool prints it
so that *choosing* and *executing* stay a human's. **My first version emitted two `git mv` lines to
the same `REPORT.md` for the 25 ambiguous directories, which would have destroyed 25 files; the
`AMBIGUOUS` line exists because I wrote the check after the hazard, not before it.**

### The 7 `orcdecide` named — `bf16fix devgate fp8dec gatespop jsbf16 jslane readback`

**All 7 are STILL undeclared. And all 7 are in the rename-candidate class** — each holds exactly
one `.md` under another name, so **each has a one-line `git mv` and none requires a judgement**:

| dir | `REPORT.md`? | the `.md` it holds | a tracked file now opens it |
|---|---|---|---|
| `bf16fix` | no | `STUB.md` | yes |
| `devgate` | no | `CLAIM-devgate.md`, `DEV-GATE.md` | yes |
| `fp8dec` | no | `notes.md` | yes |
| `gatespop` | no | `ENUMERATION.md` | yes |
| `jsbf16` | no | `JSBF16.md` | yes |
| `jslane` | no | `00-seed.md` | yes |
| `readback` | no | `silent2.md` | yes |

**`STUB.md` deserves one word: it is not a declaration, it is a placeholder saying there is nothing
yet.** Renaming it to `REPORT.md` would satisfy the walk and misdescribe the directory. **It is the
one row of the 46 I would not land**, and the tool cannot tell it apart — a shape cannot distinguish
a stub from a report, only a reader can. `devgate` has **two** candidates and is in the ambiguous
class, so it is 6 of 7 mechanical, not 7.

---

## 4. FRESHNESS — **THE 13/35 SPLIT IS A MEASUREMENT, AND IT IS A MEASUREMENT OF WHEN**

Over the **109 undeclared** top-level directories at `389aa61c5d50`, mtime of the newest file:

| window | fresh | stale |
|---|---:|---:|
| < 6 h | 5 | 104 |
| < 12 h | 5 | 104 |
| **< 24 h** (`declare`'s line) | **9** | **100** |
| < 48 h | 71 | 38 |

Histogram by whole hour: `0h:5 12h:1 13h:3 26h:4 27h:5 28h:2 30h:2 31h:1 33h:1 36h:2 37h:8 42h:7
43h:10 46h:16 47h:4 48h:1 50h:15 51h:2 64h:1 65h:3 66h:2 67h:2 68h:3 70h:1 71h:2 72h:1 74h:1
75h:1 79h:1 121h:1 174h:1`. Span **0.0 h – 174.7 h**.

**IS THE FRESHNESS TEST A SHAPE OR A MEASUREMENT? A MEASUREMENT — and it is the instrument's
reading, not a property of the directories.** Three reasons, all measured:

1. **It MOVES.** The distribution is bimodal with a **gap between 13 h and 26 h** — no directory
   in that band. That gap is not a fact about the directories; it is **the two shifts of a working
   session**, and it slides right every hour. `declare`'s **13 fresh / 35 stale** was true of *its*
   48 at 17:03; **at 19:40 the same instrument on a slightly larger set reads 9 fresh / 100 stale.**
   **A number that moves 100 in three hours is a timestamp wearing a count's clothes.**
2. **THE COMMIT CLOCK IS DEGENERATE AND STAYS DEGENERATE.** `checks/slop-declare.py` measured it:
   one restore commit touched **every** `.agents/slop/*/` directory, so commit age has **ONE
   distinct value**. I did not re-derive that and I do not need to — the file that measured it is
   still true, and re-measuring a property of *history* with a *worktree* clock would be the wrong
   instrument. **`mtime` is the only clock that discriminates here, and mtime is the clock a
   `git checkout` resets.** `MIN_SPREAD_MIN` guards the reset; it cannot repair the weakness.
3. **`prune4`'s warning is the one I take most seriously: a regex census said 183 where the truth
   was 61.** This census has no regex and no hand list, so it cannot make *that* mistake. But
   `mtime` is a number in a column, and **a number in a column is a reading, not a proof.**

**AND THE DISTRIBUTION IS THE RIGHT ARTIFACT, NOT A THRESHOLD.** I bake in no window: a reader who
wants "finished" draws their own line on a published histogram. **That is the shape
`pairs`/`prune4`/`indextree` each asked for — the instrument does not decide what finished means,
it prints the axis.**

**THE 9 FRESH ONES ARE NOT STALE AND THE 100 ARE NOT FINISHED — AND HERE IS WHY THE DISTINCTION
IS NOT MINE TO DRAW.** `prune4` measured `midrun` at **11.4 MB → 60 KB *while being measured***:
sweeping a running unit's output is the one prune failure that **destroys work rather than
evidence**. The 5 at `0h` are directories a live unit is writing right now. **A census that could
delete them would be worse than a census that cannot**, and that asymmetry — not caution, but
*direction of harm* — is the whole reason freshness exists as a printed column rather than a
delete list.

---

## 5. **IS "DECLARED" THE RIGHT PROPERTY AT ALL? — I RAN THE TEST `prune4` DID NOT RUN**

`prune4`'s caveat, verbatim: *"I MEASURED THE CLASSES BUT NOT THE CLASSIFIER — IT'S AN INSTRUMENT's
READING, NOT A PROOF, AND `git grep -F` PER FILE WOULD BE THE EXACT TEST I DIDN'T RUN."*

I ran it: **`git grep -l -F -- <file> <commit>`, per file, outside the directory**, over the
**156 declared** directories at `389aa61c5d50`.

| | count |
|---|---:|
| declared AND some tracked file outside opens one of its files by exact path | **140** |
| **declared AND NOTHING opens one of its files** | **16** |

```
adevfix  agendop2  armfour  awmma  censusfix  citetruth  envguard  flipport
mselectarg  plancarve  plantthe46  refusalsweep  subtree  threegraphs  unshardtable  wmmafix
```

**THE SAME TEST OVER THE UNDECLARED SET IS THE LOUDER RESULT: of 109 undeclared directories, 107 are
opened by an exact-path reader. Only 2 are opened by nothing.**

**AND THAT IS THE ANSWER TO THE GOVERNING QUESTION. NO — THE CENSUS IS COUNTING AUTHORSHIP WHEN IT
THINKS IT IS COUNTING AUDITABILITY.** Put the two readings side by side and the property inverts:

| | declared (authorship) | opened by a tracked file (auditability) |
|---|---:|---:|
| **R\|M name set** | **156** | 140 of them → **16 declared, unopened** |
| **the rest of the tree** | 109 undeclared | **107 of 109 ARE opened** |

**The two questions select nearly DISJOINT sets.** Sixteen directories wrote a document that
**nothing on earth opens**, and 107 directories wrote no document that **something does open** —
the 107 are the units whose *output* is their declaration: a `rows` file a gate reads, a `.rows`
table a `.py` parses. **`orcdecide` reached this by accident** — it did not require a declaration at
all, only a full-path reference, and it found **10**; `declare` required a declaration and found
**48**; the truth is that **these are two nearly disjoint populations**, and any single number over
their union is a category error.

**SO WHAT SHOULD THE PROPERTY BE? BOTH, NAMED, AND NOT SUMMED.** Neither alone survives contact:

- **"Declared"** (authorship) is what a **reviewer** needs: *"does a human say what this is?"*
- **"Opened"** (auditability) is what a **prune** needs: *"does anything depend on it?"*

**`checks/slop-declare.py` should keep `declared` as its ratchet key** — it is a **baseline against
growth**, and the 16 unopened-but-declared rows are exactly the **human queue**: 16 directories
holding a document nobody reads is a real, small, actionable list, and it is the first time that
list has been computed. **But the header's sentence "A walk that REQUIRES a declaration is a gate
that is red from birth" is now measurably the wrong framing**, because **the gate it is actually
green on is the other half**: **107 of 109 undeclared directories ARE opened**, so a prune that
wanted *evidence of use* has **107 live directories and only 2 dead ones**, and **the reclaimable
class is not the undeclared one at all.** `prune4` measured 84.76% irreducible; this says **which
rows that percentage is made of**, and it is **not** the undeclared ones.

---

## 6. **WHAT IT CANNOT SEE — READ THIS BEFORE THE NUMBERS, BECAUSE THE NUMBERS ARE SMALLER THAN THEY LOOK**

**A WALK DETECTS ABSENCE. It cannot author a declaration and it cannot judge one.**

1. **IT CANNOT TELL A WRONG DECLARATION FROM A RIGHT ONE.** This is the ceiling the task names and
   it is absolute. **A `MANIFEST.tsv` with 260 rows and a `MANIFEST.tsv` with 54 rows are THE SAME
   FILE NAME**, and my shape M accepts both without opening either. So **the walk that accepted
   either is counting a shape, and I am reporting it as if it were a fact.** MEASURED in this
   population: `.agents/slop/strays/MANIFEST.tsv` is **54 rows** and `.agents/slop/oracles259/
   MANIFEST.tsv` is **260**, and **4 directories hold a manifest-shaped name at all — and the tool
   reads none of them.** A rename would fix the *name* and leave the *content* exactly as unchecked
   as it was.
2. **IT CANNOT TELL AN ABSENT DECLARATION FROM AN UNWRITTEN ONE.** **A `REPORT.md` IS A HUMAN
   ARTIFACT AND NO WALK CAN WRITE ONE.** Turning 47 rows into declarations is 47 decisions. **The
   tool names; a person decides.** That is the whole honest ceiling and no amount of cleverness
   raises it.
3. **IT CANNOT JUDGE WHETHER A DECLARATION IS TRUE — and this is not a caveat, it is a MEASURED
   LOSS.** `citeresolve` measured **2 448 committed prose `<path>:<N>` claims, 165 unresolved and
   1 777 never positively checked, including essentially every `REPORT.md` written that night.**
   **So a `REPORT.md` is an UNCHECKED CLAIM THAT HAS A FILENAME**, and every "declared" row in
   §2 and every "opened" row in §5 is a fact about a path, not about a truth.
4. **IT CANNOT DISTINGUISH A STUB FROM A REPORT.** `bf16fix/STUB.md` is a **placeholder saying
   there is nothing yet**, and the rename plan would call it a report. A shape cannot tell them
   apart.
5. **IT CANNOT SEE UNTRACKED WORK, AND THAT IS CORRECT — BUT IT HAS A COST.** It reads a commit,
   so a `REPORT.md` written and not committed leaves a directory declared in the worktree and
   undeclared in the census. **A walk that read the worktree would let an uncommitted `REPORT.md`
   silence it — the same shape as a plant that rewrites its own population.**
6. **IT CANNOT SEE A UNIT THAT IS STILL RUNNING**, only that its mtime is recent, and **§4 shows
   the mtime distribution moving by 100 rows in three hours.**
7. **`opened_by` IS THE FIRST OPENER IN SORTED ORDER, NOT ALL OF THEM.** A directory with five
   readers records one. **The census answers "is anything a reader?", not "how many?"** — and a
   reader that counts is the `ORACLE_WORD` failure at a different altitude.

**WHAT WOULD MAKE A DECLARATION *CHECKED* RATHER THAN PRESENT — NAMED, NOT BUILT.** A declaration
would become checkable if some **claim in it** were machine-verifiable and **the verifier ran**:

1. **EVERY `<path>:<N>` CITATION IN A `REPORT.md` RESOLVES AT THAT COMMIT.** `citeresolve`
   already does this for 2 448 claims and found 165 unresolved. **Running it as a gate over the
   156 declared directories turns 156 unchecked claims into 156 checked ones** — and it is
   `git cat-file`, not a new invention.
2. **A DECLARATION NAMES ITS OWN POPULATION AND THE WALK CHECKS THE NAMES RESOLVE.** A `REPORT.md`
   that says "these 12 files are the unit's output" becomes auditable the moment a walk confirms
   12 of 12 exist at the commit. **`MANIFEST.tsv` is already that shape** — `strays/`'s is
   `arm · role · path · verdict · why · restore` — **and nothing checks its paths.** That is the
   cheapest available win and it is a **generator's own declaration loaded by path**
   (`differ.declared()`), **not a hand list.**
3. **A DECLARATION NAMES ITS OWN SUCCESS CRITERION AND A NAMED GATE REPORTS IT.** "the tree
   imports" is checkable; "this unit investigated X" is not.

**AND THE ONLY INSTRUMENT FOR WHAT REMAINS IS A REVIEWER — `declareverdict` said this of its own
`RED_IS`, and it is the correct ceiling.** A declaration can be **present**, **opened**, and
**internally consistent**, and still be **wrong**, and no walk over paths detects that. **A reviewer
is not a missing feature of this census; it is the part of the answer that is not an instrument.**

---

## 7. THE VERDICTS, IN THE FIVE (`AGENTS.md`)

| | |
|---|---|
| **PASS** | 31/31 plants, and the census's own `--rename-plan` emits **0 colliding targets** |
| **FAIL** | nothing, by design — **this unit CHANGES NO GATE**, it publishes a census and a plan |
| **SKIP** | the **47** undeclared directories with no `.md`: no rename exists, and writing one is a human act I do not perform |
| **REFUSED** | `census.py` exits **3** on a tree with **0** `.agents/slop/*/` directories, and `MIN_SPREAD_MIN` refuses a **checkout**'s single mtime stamp. PLANT 8 pins the first. |
| **DEAD** | the freshness column **was** DEAD — 109 rows reading `0.0 h` — and is now guarded. **A column that prints four digits and measures nothing is DEAD, not PASS.** |

**AND THE ONE-LINE ANSWER TO EACH QUESTION ASKED:**

1. **265 directories at `389aa61c5d50`; 256 and 262 are readings of an index and of an earlier commit.**
2. **R, M and P are three shapes; they are nested except for 2 directories, and `checks/slop-declare.py` should keep R\|M because only R\|M has a stable baseline. P is needed for a one-time reconciliation, not as a gate.**
3. **62 directories hold a declaration under another name; the fix is 46 `git mv` plus 25 human choices, never 91 names in a set. All 7 of `orcdecide`'s are still undeclared and all 7 are in that class — 6 of 7 mechanically.**
4. **Freshness is a measurement and it moves: the 13/35 split was true at 17:03 and reads 9/100 at 19:40. The histogram is the artifact; no window is baked in.**
5. **No, the census was counting authorship. The exact test `prune4` did not run gives 140 of 156 declared directories opened and 107 of 109 undeclared ones opened — two near-disjoint populations.**
6. **Both directions planted, plus the false-able control (a declaration with no reader) and the nested-inheritance control (a child inside a declared parent is its own row), plus PLANT 7b for the direction the count test gets wrong.**
7. **It cannot see that a declaration is wrong; a 53-row manifest and a 3-row manifest are the same filename. A citation-resolving gate over the declared set is the cheapest thing that would make one CHECKED.**

**NOT DONE, AND NOT TO BE DONE BY ME:** no `git mv` executed, no commit, no `git add`, no `git
ls-files` in any gate, no edit to `AGENTS.md`, `tinybendygrad/`, or any gate body.