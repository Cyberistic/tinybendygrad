# msgdiff2 — a commit MESSAGE against its own DIFF, over the unpushed range

**REPORT ONLY. Nothing in the repo was changed, nothing was pushed, and no git command that
writes was run. One file-family was created, all under `.agents/slop/msgdiff2/`.**

## 0. THE RANGE, CAPTURED ONCE

The tree is a moving target, so the range is named exactly rather than described.

| | |
|---|---|
| base | `473d7ce988d0f0741e26bccf5e8c1495d864be4c` (`origin/master`, "Update README.md") |
| head | `2473958642727eeb0e5ed0b86dbe8eadb0a823d5` |
| range | `473d7ce988d0f0741e26bccf5e8c1495d864be4c..2473958642727eeb0e5ed0b86dbe8eadb0a823d5` |
| **denominator** | **55 commits** |
| captured | `2026-10-17T05:25:50Z` (UTC) |
| rev list | `.agents/slop/msgdiff2/.range-snapshot.rows` (read once; every row below comes from that file, never from a re-resolved `origin/master`) |

`HEAD` is **detached**, so `@{u}` fails and "unpushed" had to be resolved by hand. `master..HEAD`
is 668 commits; `origin/master..HEAD` is **55**, inside the ~49–55 band given in the brief, so
that is the range used. The 49 in the earlier reading is the same range six commits shorter, not
a different one.

## 1. WHAT WAS NOT DONE, AND WHY — READ THIS BEFORE THE NUMBERS

**`gates/msgdiff-gate.py` WAS NOT EXECUTED.** The brief's machine contract forbids running
anything under `gates/`, and that outranks the brief's "run it if it does not write".

Two facts so the constraint is not mistaken for a blocker:

- **The gate does not write.** Its `_git` (`gates/msgdiff-gate.py:269`) passes
  `--no-optional-locks`, so it never writes the index it reads; `check` and `range` print to
  stdout/stderr and touch no file. Only `--plant` (`:412`) writes, and only into a
  `tempfile.TemporaryDirectory` outside the repo. So the brief's condition is **satisfied**.
- Therefore **the verdicts below are NOT the gate's verdicts.** They come from a
  **re-implementation** whose fidelity is measured in §4, not asserted.

The re-implementation loads the gate's **grammar from the gate itself**: `classify.load_grammar`
`ast.parse`s `gates/msgdiff-gate.py`, reads each `re.compile(...)` binding's pattern *and flags*
out of the source, and compiles it locally (`classify.py:81`). The module is never imported and
never executed. So there is exactly **one copy of the grammar in this repo and it is the gate's**
— not a second copy that can rot.

> **A fidelity bug this design caught in itself, worth recording.** The first loader read only
> `args[0]` (the pattern) and dropped `args[1:]` (the flags). `VERB` is
> `re.compile(r"...", re.I)` (`msgdiff-gate.py:106`), so the loader silently produced a
> **case-sensitive** delete grammar, under which an honest capitalised "Deleted X" matches
> nothing. The instrument would have reported *zero* false claims while being broken in exactly
> the direction this unit exists to detect. Second bug: `re.I` is an `ast.Attribute`, not an
> `ast.Constant`, so a flags resolver that only looked for integer literals also read zero. Both
> are fixed (`classify._flags`, `classify.py:67`) and both were found by asserting on the gate's
> own vectors rather than by inspecting the code.

## 2. `gates/msgdiff-gate.py` — COVERAGE, ANSWERED DIRECTLY

### 2a. Does it check a message that claims a deletion its diff does not contain? **YES.**

Two independent subjects, and they are kept apart on purpose (`:70-84`, `:151-158`):

- **CLAIM subject** (`:363-373`, docstring `:42`): a **delete verb** + the **path it governs**,
  graded against the diff's `D` entries and the commit's tree. Fires when the path is present in
  the tree and not deleted here. The canonical case is `00b101574`, which claims it deleted
  `oracles259/plants.py` while the file sits in that tree at blob `e6e31707` (`:20-29`).
- **DIFF subject** (`:240-266`): **every path the diff removes** (D entries plus rename sources)
  must be named by the message or acknowledged by `SUBJECT_DIFF_ACK=`. This is what catches a
  message that says nothing at all about its removals.
- **COUNT subject** (`:375-380`, docstring `:48`): `N files changed|deleted|added|removed|touched`.

Its own docstring states the limit precisely and correctly: REFUSED is **not** FAIL — "the gate
does not know the message is WRONG, it knows only that THIS DIFF does not witness it" (`:66-68`).

### 2b. Does it handle INVERTED polarity (says "restored"/"added"/"fixed", diff DELETES)? **NO — measured, not assumed.**

- `VERB` (`:106-107`) is **ten delete forms and nothing else**:
  `deleted|delete|deletes|deleting|removed|removes|removing|git\s+rm|dropped|drops|dropping`.
  **`restored`, `reintroduced`, `reinstated`, `resurrected`, `reverted`, `undeleted`,
  `repaired`, `added` are not in it.** A message asserting any of them yields **zero claims**, the
  claim lane prints `0 deletion claims checked`, and it PASSes.
- The **DIFF subject cannot cover it either**, and this is the sharper half: a message that says
  "restored `foo.py`" over a diff whose removal set is exactly `foo.py` **names** the path, so
  `unacknowledged_removals` is empty and the lane PASSes too. **Both lanes pass on a message and
  diff pointing in opposite directions.**
- Additions are excluded from the diff subject **by decision**, not oversight: "ADDITIONS ARE
  DELIBERATELY NOT IN THE RULE" (`:188-192`), because grading them refuses 202 of 300 honest
  commits to catch nothing.
- **Whole-file count of the gap:** across all 593 lines, the only restore-family words are in
  **comments** — `:183` ("deleted twice ... and restored in between") and `:286` ("`c83f04ad1c12`
  reverted 46 renames"). `grep -icE 'restor|re-add|readd|reinstat|resurrect|reintroduc|revert|
  undelet|repair' gates/msgdiff-gate.py` → **2, both comments.** There is no restore grammar in
  the gate to find.

**And the checkable gap is not the one its docstring advertises.** The docstring (`:4-18`) lists
what the gate cannot see: a bare percentage, a dead pid, an invented config key — and every one
of those **names nothing checkable**. §5 finds a gap of the opposite kind: a claim that is
perfectly checkable, about the **wrong commit**, which the gate grades and gets wrong.

## 3. THE INVERSION LANE I ADDED — AND WHY IT IS REPORTED AS UNPROVEN

I wrote a third lane mirroring `deletion_claims` with a restore/add/repair vocabulary
(`classify.INVERSE`, `classify.py:121`): a message asserting a restoration/addition of a path it
**names**, where the diff **removes** that same path. It requires a named-path witness, so prose
about restoration in general cannot trigger it.

**It fired 0 times in the 55-commit range.** Rather than report that as "0 false claims, lane
works", I tried to prove it could fire at all, and it could not:

| probe | window | result |
|---|---|---|
| C3-strict (verb governs a removed path) | 600 commits | **1 hit** — and it is a **false positive** |
| C3-weak (verb anywhere + names a removed path) | 600 commits | 2 more — **both false positives** |

All three, read by hand:

- `9b55d16a4fa1` — "THE LAST FOUR TRACKED STRAY FILES ... **ARE REMOVED**", followed by a
  recovery recipe line `RESTORE: \`git show <blob> > <path>\` — \`elf.bend.mut\` ...`. The word
  RESTORE is an **instruction for recovering** the files the commit correctly removes. The lane
  fires on the recipe.
- `b70551451278` — an essay *about* restore semantics ("`git checkout` ADDS AND OVERWRITES BUT
  **NEVER DELETES**"). It removes 46 `REPORT.md` files, correctly and by a discovered delete set.
- `3fb8dde1af26` — honest stray-blob removal ("TWO OF THEM ARE **KILLED MUTANTS**").

**So the inversion lane has a ~100% false-positive rate on the only real material available, and
no positive instance anywhere in 600 commits.** Conclusion, stated as a refusal rather than a
number: **inverted polarity is not measurable with a word-matching instrument over this corpus,
because in this corpus the vocabulary of restoration is mostly *meta-commentary about* restoration.**
A lane that cannot separate "I restored X" from "here is how you would restore X" is the same
failure as the gate's, in the opposite polarity.

## 4. FIDELITY — THE RE-IMPLEMENTATION IS MEASURED AGAINST 6 REAL COMMITS

The gate's docstring and comments publish exact verdicts for six real commits. Those are the
denominator this re-implementation is judged against, and **§4 gates every verdict in §5**: a
mismatch refuses the run (exit 5).

`.agents/slop/msgdiff2/vectors.rows` — **11/11 reproduced**:

| sha | lane | expected | measured |
|---|---|---|---|
| `00b101574` | CLAIM | REFUSED | REFUSED (names `oracles259/plants.py`, present in tree) |
| `9144d179e25a` | CLAIM | PASS, 0 checked | PASS, 0 checked / 0 uncheckable |
| `c83f04ad1c12` | CLAIM | PASS, 0 checked | PASS, 0 checked / 0 uncheckable |
| `75ab9b8f8984` | CLAIM | PASS, 0 checked | PASS, 0 checked / 0 uncheckable |
| `9144d179e25a` | DIFF | REFUSED, 110 removals | REFUSED (110 removals, unnamed) |
| `c83f04ad1c12` | DIFF | REFUSED, 66 removals | REFUSED (66 removals as `R100`) |
| `75ab9b8f8984` | DIFF | REFUSED, 4 removals | REFUSED (4 removals) |
| `9b55d16a4fa1` | DIFF | PASS (GLOB/DIR declare the strays) | PASS |
| `169ee6ac8` | CLAIM | PASS (meta-report) | PASS |
| `3c4ceeea3` | CLAIM | PASS (negated) | PASS |
| `3188c1af86a1` | DIFF | PASS (suffix match) | PASS |

## 5. THE PER-COMMIT SPLIT — DENOMINATOR 55

`.agents/slop/msgdiff2/classify.rows`, TAB-separated, one row per commit:

```
sha <TAB> verdict <TAB> message_polarity <TAB> diff_polarity <TAB> reason
```

| verdict | n | of |
|---|---|---|
| CONFIRMED | **3** | 55 |
| FALSE-CLAIM-ARTIFACT (gate fired, refuted on reading) | **4** | 55 |
| UNCLEAR (no checkable assertion) | **48** | 55 |
| **FALSE-CLAIM (upheld on reading)** | **0** | 55 |
| **FALSE-CLAIM-INVERSE** | **0 observed — lane UNPROVEN, §3** | 55 |

`message_polarity` ∈ {NEUTRAL 28, UNSPECIFIED 20, DELETE 3, RESTORE 3, MIXED 1};
`diff_polarity` ∈ {ADDS 43, MIXED 7, DELETES 4, NO-CHANGE 1}.

**UNCLEAR IS NOT CONFIRMED.** It is the bucket for a commit the instrument **cannot see**:
zero claims survive the grammar, so nothing was graded. Per this project's own doctrine, a
verdict over zero comparisons is not agreement — it is the state nobody writes down.

**The DIFF subject found nothing at all: 0 commits, 0 paths.** Across all 55 commits, **every**
path the diff removed was named by its own message. On that subject the history in this range is
clean, and that is a real measurement rather than an absence of looking.

### The 4 gate firings, every one named — and all 4 refuted on reading

**0 of the 4 is a wrong message.** All four are the same underlying gap in different clothes: the
grammar attributes a verb to a path when the sentence is not asserting that verb about that path.
Each firing **must** have an entry in `classify.ADJUDICATION` or the run raises
(`classify.py:369`) — so a new false claim cannot reach this report unadjudicated, which is the
only thing that lets "0 FALSE-CLAIM" mean something other than "nobody looked".

| sha | shape | why it is not a false claim |
|---|---|---|
| `f19347f66e20` | **HYPOTHETICAL-MOOD** | "a bare `git commit` in this tree **would try to** DELETE `checks/substrate-manifest.py`" — a prediction about a future command over a phantom index. The same message says "NOTHING IS WRONG WITH THE COMMIT". Its diff deletes nothing (0 D). |
| `57b8f71c9466` | **FILE-LINE-REF** | "pr_0 dropped BOTH halves of `spec.py:204`" — two conjuncts removed from a *line*. `PATH` has no `:`, so it captures the half-path `spec.py` and reports a file deletion. 0 D. |
| `02329daf0847` | **OTHER-COMMIT-REF + QUOTED-GIT-OUTPUT** | The deletion and the "435 files changed" are both about **`591f6b499`, its parent**, which the sentence names. `delete mode 100644 gates/README.md` is a line of `git commit` **stdout**, quoted as evidence. Graded against its own diff: 0 of those paths deleted. |
| `1655307d1f37` | **OTHER-COMMIT-REF** | "deleted `gates/README.md`; a 178-path `--only` carried 430" is the INDEXRACE record describing **earlier** commits. This commit deletes nothing (0 D). |

**`OTHER-COMMIT-REF` is the finding.** The gate grades every message against its own diff and has
no notion of *which commit a claim is about*. A truthful sentence about the parent reads as a
false claim about the child. Its docstring does not list this: the three gaps it names
(`:4-18`) all **name nothing checkable**, and this one is the opposite failure — a perfectly
checkable claim, aimed at the wrong target. **A cross-reference guard (does the clause name a sha
other than this commit's?) is the one change that would remove both of the 02329daf0847 and
1655307d1f37 firings**, and it is the change I would propose first.

## 6. THE INVERSION CASE THE BRIEF NAMED — `02329daf0847`, ADJUDICATED HONEST

The brief's premise is **factually right about the numbers and wrong about the verdict**.

`02329daf0847` — *"REPAIR: 178 phantom deletions from an armed-index race, restored verbatim from
HEAD~1"* — is indeed a commit whose message says "restored" and whose diff **deletes 252 paths**.
So the inverted polarity is real as a *polarity observation*.

It is **not a false claim**, because the message describes **both halves and the diff does both**:

| measured | value |
|---|---|
| `git diff-tree -r -M --root --name-status` | **178 A**, **252 D** lines |
| distinct removed paths | **126** |
| distinct added paths | 178 |
| message's own account | "178 ARE BYTE-IDENTICAL TO `HEAD~1` AND ARE RESTORED HERE VERBATIM"; "**182 LOST**, **252 ADDED**" — all about the parent |
| the one path the message names as deleted-by-the-parent, `gates/README.md` | **`A` in this diff** — restored, exactly as claimed |

The message's "restored" claims the 178 additions; the 252 deletions are the phantom additions
inherited from `591f6b499` and are described in the following paragraph. Polarity inverts only
if you read the subject line and stop. **Verdict: CONFIRMED-BY-READING, not FALSE-CLAIM-INVERSE.**

## 7. AN INSTRUMENT DEFECT FOUND WHILE MEASURING: `435` IS A LINE COUNT

While checking §6 I found that `git diff-tree -r -M --root --no-commit-id --name-status` emits
**duplicated lines** for two commits:

| sha | name-status lines | distinct lines |
|---|---|---|
| `591f6b499` (the outage commit) | **435** | **309** |
| `02329daf0847` (its repair) | **430** | **304** |

The `D` block of `02329daf0847` is **the same 126 paths emitted twice, in identical order**
(verified by splitting the block in half and diffing). Every other commit in the range is clean:
**2 of 55 affected**, and they are exactly the phantom pair.

**Why this matters beyond curiosity:** `commit_view` in the gate (`:296-309`) increments `changed`
**once per name-status line**, so it reads **430** where 304 distinct paths changed. And **435** —
the figure quoted as the outage's size in `AGENTS.md` and in two commit messages — is precisely
`591f6b499`'s **line** count; the distinct-path count is **309**. So the headline number of the
best-documented incident in this tree is inflated by ~40% by git's own duplication, and any
COUNT-lane check against those two commits is graded against an inflated denominator.
**I did not establish the cause** and am not guessing at one.

## 8. THE FUNNEL — AND THE CORRECTION TO THE EARLIER COARSE COUNT

`classify.deletion_claims` is a funnel, and each stage is a strict subset of the one above.
`.agents/slop/msgdiff2/funnel.rows`:

| stage | n | of |
|---|---|---|
| 1 — message contains a delete verb at all | 25 | 55 |
| 2 — not negated, not a meta-report | 20 | 55 |
| 3 — the verb **governs a path** (forward, ≤40 chars, gap-filtered) | **4** | 55 |
| 4 — the path resolves in this commit's diff or tree | 4 | 55 |
| 5 — the claim was actually graded | **4** | 55 |

This reframes the earlier unit's "28/49 messages contain a deletion word; only 2 have
actually-deleted paths; 26 deleted NOTHING". Stage 1 (25 of 55) is that same population — the 49
vs 55 difference is the moving range, not a disagreement. The conclusion "the other 26 are false
positives" is **not** the right reading of the 26: they are not false positives, they are
**outside the population of a message-vs-diff gate**, because the word they match is about
in-file code, a recovery recipe, or another commit. And the claim lane's own hit rate over this
range is **0 of 4 witnessed** — every graded deletion claim was refuted on reading.

**The instrument's real denominator is 4 of 55 commits (7%).** The 3 CONFIRMED rows are not
deletion claims at all; they are **COUNT** claims ("N files changed" == the diff's path count),
which is the gate's second, narrower claim kind (`:48`, `:375-380`) and which its own docstring
records as dormant.

## 9. CONTROLS

`controls.rows`. **C1 is the control the brief required. C2 and C3 are stricter additions.**

| # | shape | commit | result |
|---|---|---|---|
| **C1** | message asserts an **addition**, diff **ADDS** it → must NOT fire | `3173198bd80e` | **PASS** — `UNCLEAR`, mp=RESTORE, dp=ADDS |
| C2 | a claim the diff witnesses → must NOT fire | `4f747540b372` | **PASS** — `CONFIRMED` |
| C3 | a **real** commit whose restore/add verb governs a path its diff removes → MUST fire | none found in 600 | **FAIL** |

**C1 PASSES, so the brief's control condition is met and the results in §5 stand.** C3 fails, and
that failure is reported as a refusal, not smoothed over: **the inversion lane is UNPROVEN.** No
`FALSE-CLAIM-INVERSE` count in this report is backed by a demonstrated firing; the count is 0
observed and 0 provable with this instrument. C2 is weaker than intended — no CONFIRMED commit in
the range has `dp=DELETES`, so C2 fell back to a count-claim commit rather than a deletion one.

## 10. DELIVERABLES AND REPRODUCTION

| file | what it is |
|---|---|
| `classify.rows` | **the per-commit classification**, TAB-separated, 55 rows + header |
| `REPORT.md` | this file |
| `classify.py` | the classifier; loads the gate's grammar by `ast`, never imports or runs it |
| `vectors.rows` | 11/11 fidelity vectors against the gate's own published verdicts |
| `controls.rows`, `controls.py` | the three controls and their results |
| `c3.rows`, `c3.py` | the 600-commit inversion probe and its three refuted hits |
| `funnel.rows`, `funnel.py` | the 25→20→4→4→4 funnel |
| `.range-snapshot.rows` | the 55 revs, read once |

```sh
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/msgdiff2/classify.py vectors   # must be 11/11
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/msgdiff2/classify.py rows
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/msgdiff2/controls.py
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/msgdiff2/funnel.py
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/msgdiff2/c3.py 600
```

`vectors` is run **first, always**: it is what licenses the rest. Every git read is
`--no-optional-locks` with `GIT_INDEX_FILE` unset, so a colocated `jj` snapshot's armed index
cannot answer a question about the tree — the `index-arm-gate` false-`PASS` hazard.

## 11. WHAT I WOULD PROPOSE NEXT, IN ORDER

1. **A cross-reference guard.** Detect a clause that names a sha other than the graded commit and
   demote it to uncheckable, the way `META` demotes a reported claim. Removes 2 of the 4 firings
   and is the only one of these three that closes a *documented* gate gap.
2. **Grade the count lane against DISTINCT paths, not lines** (§7). Two commits, one inflated
   headline number, one wrong denominator.
3. **Do not ship an inversion lane.** Two attempts, three of three hits refuted on reading, zero
   positive instances in 600 commits. Closing this needs the message and the diff judged
   *together* (does the restored path appear as an `A`?), not a wider verb list — and the honest
   intermediate is to **count the class and refuse to judge it**, which is the same state
   `rebase-gate-selftest.py:1168-1180` declares for its six DEAD lanes.