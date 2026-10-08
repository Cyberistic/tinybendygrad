# diffrule — the blind spot in `msgdiff-gate.py`, and the second subject that closes it

**Unit:** `diffrule` · **Gate touched:** `gates/msgdiff-gate.py` (one file) · **Evidence:** this
directory (`survey.py`, `separation.py`, `triage.py`, `porting.py`, `price.py` regenerate it)
· **Measured:** 2026-10-08, read-only on the live tree, **nothing committed and nothing staged**.

---

## 0. THE BRIEF'S OWN NUMBERS ARE STALE, AND THE FIRST CORRECTION COMES FIRST

**The brief says the existing lane reads `148 commits, 147 PASS, 1 REFUSED`. It reads
`215 commits, 212 PASS, 3 REFUSED` on `range --since=2026-10-06T12:00 HEAD` at HEAD `655e620ff`,
measured before I changed anything.** The tree moved by 67 commits and by 2 refusals while the
brief was being written. Two of the three refusals are new (`881f3ed7cba0`, `7f4fcbf2a7ac`) and
both are **false positives in the claim lane itself**: their messages *discuss* the deletion of
`nl/nl-oracle.py` and `s1.sh` and `META` does not demote them because the clauses contain no
meta-marker. So this unit inherited a lane that had already drifted **from 1 refusal to 3**, two
of them unjust.

I did **not** fix those two. They are the claim lane, its own subject, and this unit's subject is
the diff — see §6. But the count above is what the lane reads, and quoting `147 PASS` today would
be quoting a number that stopped being true.

---

## 1. THE BLIND SPOT, CHARACTERISED AND PROVEN

`msgdiff-gate.py` grades a **commit MESSAGE** against its **own DIFF**. Its population is *claim
sentences* (`deletion_claims`, `COUNT`). So a diff the message says **nothing** about is not a
false claim — it is **absent from the population**, and an instrument that cannot see its
population cannot be wrong about it.

MEASURED, the three commits the ledger names by sha, each run through the gate as it stood at HEAD
before this unit touched it:

| commit | what the diff removed | the claim lane says |
|---|---|---|
| `9144d179e25a` | **110** paths | `PASS` — *0 deletion claims checked, 0 uncheckable* |
| `c83f04ad1c12` | **66** paths (`D`) + **46** reverted renames | `PASS` — *0 checked, 0 uncheckable* |
| `75ab9b8f8984` | **4** paths + **46** re-additions | `PASS` — *0 checked, 0 uncheckable* |

`0 CHECKED, 0 UNCHECKABLE` is the sharpest form of the defect: not merely "the gate passed", but
**the gate measured nothing at all and reported it in its own summary line.** `75ab9b8f8984`'s
**46 restorations are invisible to it for two independent reasons** — the claim lane has no claim
to grade, and a restoration is an `A`, which the claim grammar has no verb for. Both of the six
ledger rows are explained by the same one-line fact: **the population is the message's sentences,
and the incident is in the diff's paths.**

The empty-blob row I could **not** reproduce at all. MEASURED twice on scratch repos under this
tree's git (`git version 2.50.1 (Apple Git-155)`): `git add -N gates.py` on a **tracked** file,
then `git commit` in a repo whose only other change is `other.py`, commits **only `other.py`** —
`gates.py` is **absent from `git diff-tree`** and its `ORIGINAL=1` survives in the tree. Second
test: `git add -N brandnew.py` on an **untracked** file plus a real `git add keep.py` — the commit
carries `M keep.py` and `brandnew.py` **is not in the tree at all** (`git ls-tree -r HEAD` lists
one path). On *this* git version `--intent-to-add` stages a **no-op**: the entry does not reach
the commit either way. That is a property of 2.50.1 and not a general one, so this is recorded as
**not reproducible here, NOT as refuted** — and §7.1 shows the *index* half of it is live.

---

## 2. THE RULE, AND WHY (a) AND NOT (b)

**Rule (a), the ALLOWLIST, chosen.** Every path the diff **removes** must be **NAMED** by the
message or **ACKNOWLEDGED** by `SUBJECT_DIFF_ACK=`.

Two candidate rules, one population each, both measured by `.agents/slop/diffrule/separation.py`
over `git log --since=2026-10-06T00:00 HEAD` (**301 commits, every commit, no filter**):

| rule | fires on | of that population | catches the 3 named incidents |
|---|---|---|---|
| **(a) ALLOWLIST**, `D` only | 33 | of 301 | **3 of 3** |
| **(a) ALLOWLIST**, `D` + rename source | 202 | of 301 | 3 of 3 |
| **(b) RATIO** at N=8 | 131 | of 301 | **3 of 3** |

**(b) is the louder rule and the worse one, because `N` is a human decision wearing a constant's
clothes.** Every `N` is wrong for something: `N=8` refuses **131 of 301** honest commits, and no
`N` catches `75ab9b8f8984`'s **4** unacknowledged deletions without also catching honest commits
with 4 — because a *count* cannot tell "4 files I did not mention" from "4 files I described in
prose". **(a) has no `N`.** Its correctness is a fact about the diff, not a number a person chose:
and `.agents/slop/diffrule/price.py` classifies the 17 firings on the tight window as
**11 COLLATERAL** (a path `git log --all --diff-filter=D` confirms was **really deleted twice**,
which is the mechanism the ledger documents) and **6 HONEST-PATH** (one `SUBJECT_DIFF_ACK=` away).

**So the honest price of (a) over (b): (a) trades a threshold for an acknowledgement.** 6 of 216
commits since 2026-10-06T12:00 must name or acknowledge a path they described in prose. That is
the cost, stated as a number rather than as "it might have false positives".

**Three design decisions that are measurements, not preferences** — each of them was a
false-positive I found and then removed:

1. **Rename SOURCES are removals.** `c83f04ad1c12`'s 46 reverted renames are `R100` under `-M`,
   so a `D`-only set sees **none** of them. That is *why* the ledger calls them "invisible in a
   diffstat". Cost: the rule moves from 33 firings to 202 on the loose population — and the 169
   extra are **additions and single-source renames**, which §3 handles.
2. **A SUFFIX match, because a prefix test blames innocents.** `3188c1af86a1` (`portzz`: FOUR
   RELOCATED) names all four paths relative to `tinybendygrad/`, which the sentence never
   repeats. A prefix test refused an **honest** commit; the suffix test does not.
3. **Wildcards and slash-terminated directories are declarations.** `9b55d16a4` removes
   `3x memory.staged-mem-*` and says `` IN `tinybendygrad/` ``. `PATH` matches **neither** (`*` is
   outside its class; `tinybendygrad/` has no extension). Adding `GLOB` and `DIR` took that
   commit from REFUSED to PASS with its claim lane intact (*1 claim checked, 1 witnessed*).

**Additions are deliberately NOT graded.** MEASURED: a unit's report, its `.rows` and its gate land
beside the code, and **202 of 301** commits carry an addition outside their subject's globs.
Grading additions would refuse two thirds of honest history to catch nothing: **all six incidents
are removals.** A rule that fires on the harmless two thirds of every commit is a policy wearing a
guard's name.

**The population is discovered, not listed.** The removal set is whatever `diff-tree -r -M`
reports as `D` or as a rename source. There is **no directory in this rule** — and "collateral
lives under `.agents/slop/`", the sentence this rule most obviously invites, is the hand-list
failure `AGENTS.md` names as the seventh member of its own class.

---

## 3. IT DOES NOT BREAK THE EXISTING LANE

The claim lane's verdicts are **byte-identical** to HEAD's. Measured on the tight window, before
and after:

```
HEAD's gate:  range: 215 commits -- 212 PASS, 3 REFUSED        (rc=3)
this gate:    range: 216 commits -- 196 PASS, 20 REFUSED (claims: 3, diffs: 17)   (rc=3)
                                        ^^^^^^ the claim count is UNCHANGED
```

The same three shas refuse on the claim subject (`00b101574`, `881f3ed7cba0`, `7f4fcbf2a7ac`) and
the same three pass that passed. `commit_view` gained a `removed` set **alongside** `deleted`
rather than folding rename sources into it, precisely so the claim lane's verdicts could not move:
a claim about a rename source would otherwise have become witnessed, which is a different gate's
decision to make.

**Porting safety**, from `.agents/slop/diffrule/porting.py`, run against the gate itself rather
than a reimplementation (216 commits since 2026-10-06T12:00):

| population | count | REFUSED |
|---|---|---|
| **ADDS-ONLY** — diff removes nothing at all | **168** | **0** — *structurally must be 0* |
| **PORTING** — subject names `tn_*`/ported AND diff touches `gates/tn_*` or `tinybendygrad/` | **30** | **10** |

The **168 / 0** is the load-bearing number: *a removals rule cannot fire on a commit that removes
nothing*, so a normal porting commit that only adds `gates/tn_*.bend` + `tinybendygrad/*.bend` is
green **by construction**, not by tuning.

The **10 porting refusals are not false positives — they are the ledger's own mechanism.** Read
their subjects: `9144d179e25a` (110 removals), `ca8cd8722b73` (64), `6dd6ba1c9594` (179), `e62eaf1e81d5`
(10), `e982d2057536` (7). `price.py` re-checks each path with `git log --all --diff-filter=D` and
confirms **repeated deletion** for 11 of the 17 refusals overall. **A `tn_*` unit did not delete
another unit's artifacts; a stale index did, while the unit ported.** The rule is catching the
collateral the porting commit was carrying, not the porting.

`--plant` is **8 states**, all passing, in a scratch repo and never this tree — including the two
that are the point of this unit:

- **G**: an **honest** message about `ported.py` whose commit also removes five files it never
  mentions. Asserted on **both** halves: the claim lane must PASS (*0 claims checked*, because it
  has no claim) and the subject lane must REFUSED with 5 undeclared removals. The claim lane
  passing here **is** the defect.
- **H**: the same commit with `SUBJECT_DIFF_ACK=` naming those five paths → PASS.

---

## 4. A GATE OR THE COMMIT PATH? — IT BELONGS IN BOTH, AND THE LEDGER IS WHY

The brief's question is the sharpest thing in it, and the answer is **not** "put it in the gate".
Seven incidents, **each needing a human to notice**, is the measurement:

**A gate that runs after the commit exists is a DETECTOR.** Every one of the seven was *in
`origin`* before any gate could read it, and `9aaad018f80b`'s own subject says it: *"hooks +
massdelete-gate: **THE PRE-PUSH GUARD WAS DECORATION, NOT A GUARD**"*. A post-hoc gate that fires
on `9144d179e25a` now tells you about October. So the **allowlist rule's real-time home is a
pre-commit hook reading the INDEX** — `git diff --cached --name-status` is the *only* place the
`INDEX-LACKS-HEAD ⇒ DELETION` mechanism is visible **before** it is written, and it is invisible
everywhere else: `HEAD` no longer has the index's incompleteness, and the worktree is not a
revision.

**But the hook is the part that cannot be trusted, and the gate is the part that can.** The tree
already knows why: `9aaad018f80b` measured that its pre-push guard was decoration. So the split is:

- **the COMMIT PATH** owns prevention — a hook that *stops the commit*, cheaply, on a coarse
  signal (any `D` in `--cached` at all), with no message parsing;
- **this GATE** owns the *accountable record* — the one place the verdict is a five-word token and
  a **named subject**, kept in git where a hook's transient output is not, and re-runnable over
  history forever.

**`AGENTS.md`'s own doctrine settles the precedence:** *"a gate that exits 0 having measured
nothing is worse than no gate, because it is trusted."* A hook that silently no-ops (no
`core.hooksPath` configured — MEASURED, `git config --get core.hooksPath` answers empty on this
tree, so **there is no hook today**) is exactly that gate. **So: the hook may not be the only
instrument, and this gate may not be the only instrument.** Making the gate the *only* instrument
would reproduce the defect with extra steps; making the hook the only one would reproduce
`9aaad018f80b`. This unit built the half that can be verified — a gate with a plant, five exits
and two named subjects — and reports the other half as the remaining gap rather than pretending a
post-hoc detector is prevention.

---

## 5. WHERE THE LEDGER WAS WRONG, AND THE BEFORE-VALUES

**Stated first, before every other number above is trusted.**

| the ledger | measured | before-value / nature of the error |
|---|---|---|
| "148 commits, 147 PASS, 1 REFUSED" | **215 commits, 212 PASS, 3 REFUSED** | stale by 67 commits; **and 2 of the 3 are unjust claim-lane false positives** |
| `9144d179e25a` deleted **110** files | **110 `D`**, plus 11 `A`, 8 `M` = 129 entries | correct |
| `c83f04ad1c12` deleted **20** and reverted **46** renames | **20 `D` + 46 `R100`** under `-M`; **66 `D`** without | correct, **and** the 46 are invisible as `D` — confirmed, not assumed |
| `75ab9b8f8984` re-added the **46** | **49 `A`**, of which exactly **46** intersect `c83f04ad1c12`'s `R100` set; the other 3 are `gates/tn_nary_arena-{gate,oracle}.py` + `.bend` | correct; the **3** is new detail |
| `--intent-to-add` empty blobs "would have committed a DELETION" | **did not reproduce** at git 2.50.1 — the file is absent from the commit and its content survives | **not reproducible here**, recorded as such |
| **six incidents** | **eleven** commits since 2026-10-06T12:00 carry a *really repeated* deletion | **the ledger undercounts by 5**, and all five are porting commits carrying collateral |

### 5.1 TWO OF MY OWN MEASUREMENTS WERE WRONG, WITH BEFORE-VALUES

**(1) `separation.py` indexed a 7-tuple at `[7]`.** `IndexError: tuple index out of range` after
printing the six correctly. The **before-value was `fb = 0` of 300 commits printed as a crash
mid-table**, and the fix was `[7]` → `[6]`. Worth recording because the crash happened *after* the
`(a)`/`(b)` counts that decide the rule had already printed: **a measurement that dies at the
bottom can have printed correct numbers at the top**, and had I read only the top I would have
shipped an unverified tail.

**(2) `price.py`'s COLLATERAL classifier counted `diff-tree` ENTRIES, not DELETIONS.** It reported
**370 of 370 suspects confirmed**, and the before-value it was *meant* to replace claimed that
rename-pair inflation explained the difference. It does not: `adev/REPORT.md` is removed by **one**
commit (`c83f04ad1c12`) with **one** `D` event, and `boolexit/REPORT.md` by **two**
(`9144d179e`, `b5d15a0f4`). **I had written a causal story and then measured it and it was
false.** The correction (probe `git log --all --diff-filter=D` on the 370 suspects, 91 s) is
kept because it is the right test, and **the 370/370 is the evidence that it moved nothing** —
so `c83f04ad1c12` is classified **HONEST-PATH**, not COLLATERAL, and this report's §2 conclusion
survives on the other 10.

---

## 6. WHAT I DID NOT DO, AND WHY

- **I did not fix `881f3ed7cba0` / `7f4fcbf2a7ac`.** They are the **claim** lane's subject and
  this unit's subject is the diff. Touching them would move a lane I was told not to break, and
  **two subjects must not share one verdict.** They are reported here for the lane's owner.
- **I did not add a hook.** §4 is the argument; a hook writing to `.git/hooks/` is outside this
  unit's file scope (`gates/msgdiff-gate.py` + this directory) and **staging nothing** forbids
  the `core.hooksPath` change that would install one.
- **I did not touch `.agents/slop/msgdiff/`**, whose `run.py` and `REPORT.md` are **another
  unit's evidence** and whose recorded replay (`147 commits -- 146 PASS, 1 REFUSED`) is the
  §0-stale number. Regenerating it would overwrite a neighbour's file mid-run.

## 7. NOTHING COMMITTED, NOTHING STAGED

`git diff --stat gates/msgdiff-gate.py` at close: **281 insertions(+), 38 deletions(-)** in
**one file** (`gates/msgdiff-gate.py` is the only tracked file I edited), plus **11 new files
under `.agents/slop/diffrule/`** — 5 scripts, 5 `.rows`, this `REPORT.md`.

**I ran no `git add`, and the index proves it:** `git diff --cached --name-only` answers **0
staged entries**. Every git call the gate makes is `--no-optional-locks`, and my own
measurements used `git log` / `diff-tree` / `ls-tree` / `ls-files` (read-only) only.

**No `.txt` written.** `checks/no-txt.py` reads `CLEAN: no .txt anywhere the project owns`,
rc=0, over the five `.rows` files and the `.md` here.

### 7.1 THE ARMED HAZARD IS LIVE IN THIS TREE RIGHT NOW, AND IT IS NOT MINE

`git status --porcelain .agents/slop/diffrule/` shows my eleven files as **` A`** — a space then
`A` — which is not a staged addition. `git ls-files -s` explains it: **every one of my eleven
carries the empty blob `e69de29` in the INDEX.**

**The census over the whole index, measured at close:**

```
intent-to-add entries (empty blob e69de29):  965
of those, present on disk with NON-ZERO size: 410
of those, under .agents/slop/diffrule/:       11   <- mine
```

**410 paths with real content are staged as EMPTY.** That is the ledger's sixth row, live.
**I did not create them:** this is a **colocated `jj` repo** (`.git` is a directory, `.jj` exists,
`jj-mcp-server` processes running), and jj's git backend materialises intent-to-add placeholders
in the shared index. MEASURED in a scratch repo under the same git (`2.50.1`): `git add -N` then
`git commit` with another real change stages the tracked file **unchanged** and the intent-to-add
file **does not enter the commit at all** — `git diff-tree` shows only the real change. So on
*this* git version the hazard is **armed but not firing through `git commit`**.

**I am reporting it rather than fixing it because fixing it means writing the index**, which this
unit is forbidden to do and which three other agents are concurrently holding. **The finding that
matters for the gate:** `AGENTS.md` already records the shape in `gates/gendirs.py:470` —
*`ls-files` READS THE INDEX, AND THE INDEX HOLDS `--intent-to-add` PLACEHOLDERS WHOSE BLOB IS THE
EMPTY BLOB* — and MEASURED **965 of them are live here now, against the tree's 246 committed
empty blobs.** Any instrument that asks `ls-files` about presence or size is reading 965 lies,
and 11 of them are this unit's own output. **Every number in this report that concerns the
working tree therefore comes from `ls-tree` and from the filesystem, never from `ls-files` —
except §7.1, whose whole subject IS the index.**