# READER vs DECLARATION — the census was counting authorship and calling it auditability

Measured 2026-10-07 at commit **`7ad97ccbcbfd`**, by `.venv/bin/python .agents/slop/readerdecl/census.py`.
Population is a walk of that commit via `git ls-tree -r` — **never `git ls-files`**. Every number
below carries its scope in its own sentence. The commit is printed on every run.

Artifacts: `census.py`, `census.out`, `census.rows` (269 top-level + 232 nested rows),
`manifests.rows`.

---

## 0. WHAT IT CANNOT SEE — FIRST, IN FULL, BEFORE ANY NUMBER

1. **A reader that BUILDS ITS PATH AT RUNTIME is invisible.** `slop / name / "x.rows"` names
   nothing a literal grep can see. Every such reader counts as absent, so **every readership count
   in this report is a LOWER BOUND.** The bound is not symmetric between the two axes: a
   declaration *cannot* be built at runtime, so axis (a) has no such blind spot and axis (b) does.
   That asymmetry alone is a reason to distrust a cross-tab built this way, and it is stated here
   rather than discovered later by a reader.
2. **"Carries no bound" is STATIC.** `slowgate`: a static property is not a hang. `UNVERIFIABLE`
   means *no bound is proven present*, never that a reader was observed hanging. Only
   `checks/residue.py` was actually observed (120 s → 0 bytes out; 524 s uncapped).
3. **Prose that names a path is a CITATION, not an opening.** PROSE and DATA are reported so the
   citation count stays visible, and they open nothing — `orcdecide` measured 3 citations, 0
   opens. **If a citation IS the intended use of a report, then PROSE should count and this file
   is wrong about a large part of the tree.** That is a decision about intent, not a fact about the
   tree, and it is named rather than silently assumed.
4. **The worktree is never read** except through `git cat-file` at `rev`, so an *untracked* file
   that opens a directory is invisible. That is the point of pinning a commit.
5. **An in-slop peer is not a witness** (see §4). This file separates them in the *cells*, not
   only in the prose — the first version counted them in both and the prose then denied it.

---

## 1. THE QUESTION, STATED BEFORE ITS ANSWER

> **Which directories under `.agents/slop/` does something OPEN, and which are OPENED BY NOTHING?**

Over **269 top-level tracked directories at `7ad97ccbcbfd`** (plus **232 nested** directories, each
its own row — never inherited), the cross-tab of the two properties is:

| | a **CODE** reader outside the subtree opens it | nothing that RUNS opens it |
|---|---|---|
| **declared** (a declaring name sits in it) | **12** | **130** — ORPHAN 102, UNVERIFIABLE 28 |
| **undeclared** | **6** | **92** — CITED 35, INERT 57 |

**The off-diagonals are 130 and 6 rows out of 269.**

**Cross-check, and it is exact:** under `declaretwo`'s own definition (any reader at all, including
peers and prose) this file measures **107 of 107 undeclared directories opened**, against
`declaretwo`'s **107 of 109**. Same instrument, same answer — which is what makes the split below a
finding rather than a disagreement.

---

## 2. WHAT EACH QUESTION ALONE MISSES

**(a) "Is a declaration PRESENT?"** passes 162 top-level directories and misses **130** of them —
they carry a declaration that no code outside the directory opens. It cannot see a declaration
that nobody reads, because a declaration is a *thing*, and a census of things finds things.

**(b) "Is there a READER?"** passes 18 and misses **6** — a directory a gate genuinely opens,
holding no declaration at all. It cannot see a directory whose reader arrived before its author
learned what a declaration was.

**They are not alternatives.** They are two independent questions with near-disjoint answers:
130 rows answer (a) and not (b); 6 answer (b) and not (a). **A census that asks either alone
half-sees the tree, and the half it misses is not a small half — under (a) it is 80% of the
declared population.**

---

## 3. THE THIRD POSSIBILITY, WHICH IS THE ANSWER

The prompt offers a third answer: **neither is the question. Say what is.**

**Here it is. The property is not "declared" and it is not "opened". It is:

> **Is there a witness OUTSIDE this tree that would FAIL if the directory's contents changed?**

That has four conjuncts, and the two questions each satisfy a *different pair*:

| conjunct | (a) declaration | (b) reader |
|---|---|---|
| 1. something is named | ✅ a `.md` sits there | ✅ a path appears |
| 2. the naming is *outside* the directory | ❌ by construction | ✅ |
| 3. the namer **runs** | ❌ a file does not run | ⚠️ only if it is an entry point |
| 4. the namer **completes** | ❌ | ❌ unless bounded |

**Only (b) reaches conjunct 2, and only the full property reaches 3 and 4.** So the answer is *both
questions plus two more conjuncts* — which is why asking both is necessary and not sufficient.

---

## 4. IS A READER THE RIGHT WITNESS, OR A SYMPTOM? — **and where it LIVES**

**A reader is a symptom.** Measured over **4437 reader instances** in this same population, by where
the *reader* lives:

| reader instances | home | what it is |
|---|---|---|
| **4190 (94%)** | **inside `.agents/slop/`** | a **PEER** — another agent's scratch script, same tree, same clock |
| 127 (2%) | elsewhere | unrelated file |
| 81 (1%) | `checks/` | a gate |
| 39 (0.8%) | `gates/` | a gate |

**94% of all readership in this tree is agents citing each other.** A census that reports "140
directories are opened" as **auditability** is reporting that agents mentioned each other. This is
the sharpest form of the third sense and it is not about hanging — it is about **who is allowed to
be a witness.**

**139 of 269 top-level directories are cited ONLY by in-slop peers and by nothing outside the
tree.** They are the most-cited rows in the tree and they have no reader at all in any sense that
could fail.

> **THE LINE THAT IS WORTH MORE THAN THE FIX: a reader is a witness only if it is a stranger.**
> A peer is not a witness; a peer is a *symptom* of two agents having run in the same session.

### 4b. THE THIRD SENSE, NAMED: A READER THAT CANNOT COMPLETE

`slowgate` measured **105 of 129** gate entry points carry no time bound and **1 hangs forever**.
**28 top-level directories** here have *only* code readers that are entry points carrying no
bound. They are counted in their own cell, `UNVERIFIABLE`, and **are not counted as opened** in
either column of the 2×2.

**Does my measurement call a directory read only by a hanging gate OPENED or UNOPENED? — It calls
it NEITHER, and that is the whole answer.** `checks/residue.py`, the one gate `slowgate` *observed*
hanging (120 s → 0 bytes out), opens exactly two directories:

- `.agents/slop/deadclause/REPORT.md`
- `.agents/slop/slopcopies/MANIFEST.tsv`

**MEASURED, and it is a trap worth naming:** `residue.py` **does carry a bound** today (`bounded.py`,
`--seconds`), so a pure "carries a bound?" test scores it `bounded` — while `slowgate` measured it
**needing 524 s**. *Carrying a bound and carrying a sufficient bound are different properties*, and
only the second one is the property. `deadclause` and `slopcopies` therefore read `WITNESSED` here
and **that verdict is optimistic**, for a reason no static test can see.

> **A "reader" that cannot finish is not a witness — it is a second `residue.py`.**
> **THE THIRD SENSE: even a *bounded* reader may be bounded below its own runtime. "There is a
> reader" and "a reader ran to completion here" are different claims, and only the first is cheap.**

---

## 5. THE NESTING ROW — a declaration is about a DIRECTORY, not a subtree

Over **232 nested directories at `7ad97ccbcbfd`**:

- nested directories holding a declaration of their **own**: **0 of 232**
- nested directories undeclared while their **parent** is declared: **56**

**A walk that INHERITED would green those 56 by inheriting a fact about a different directory.**
This file does not inherit: depth compared against is the directory's own (`name.count('/') + 1`),
so a nested `.md` cannot declare its parent, and every nested directory is a row of its own.

---

## 6. THE TWO THAT NO SHAPE CONTAINS — `strays` and `oracles259`

**`prune3`'s premise was false, exactly as recorded.** `prune2` searched for
`REPORT.md`/`FINDINGS.md` only, concluded "no report", and paused deletion. `prune3` found
`.agents/slop/strays/MANIFEST.tsv` — **a 53-row restore record with `arm / role / path / verdict /
why /` columns.** `prune3` used it as its evidence: **24/24 KEEP blobs verified unique**, and it
concluded **SPARE — do not delete.**

**So: is a `MANIFEST.tsv` a declaration, or a file with a familiar name?**

**It is a declaration, and the row count is why.** `checks/slop-declare.py` already says so in its
header, and the measurement agrees: a manifest with a **verdict column** carries a per-file
judgement and a justification — that is a report in tabular form. **But the test cannot be
`basename == "MANIFEST.tsv"`, because the same filename spans a 4.8× range of meaning.**

### The manifest shapes across the tree, discovered by basename shape, with row counts

| rows | basename | path |
|---:|---|---|
| 260 | `MANIFEST.tsv` | `.agents/slop/oracles259/MANIFEST.tsv` |
| 142 | `manifest.py` | `.agents/slop/oracles259/manifest.py` |
| 130 | `MANIFEST.md` | `.agents/slop/slopcopies/MANIFEST.md` |
| 111 | `MANIFEST.tsv` | `.agents/slop/slopcopies/MANIFEST.tsv` |
| **54** | `MANIFEST.tsv` | `.agents/slop/strays/MANIFEST.tsv` |
| 20 | `MANIFEST.tsv` | `.agents/slop/land71/MANIFEST.tsv` |
| 19 | `manifest-fix.out` | `.agents/slop/txtexec/manifest-fix.out` |
| 6 | `manifest-write.out` | `.agents/slop/oracles259/manifest-write.out` |
| 2 | `manifest-prove.out` | `.agents/slop/oracles259/manifest-prove.out` |

**Four *declaration-bearing* manifests exist: 260, 130, 111, 54 rows.** Note
`.agents/slop/slopcopies/` carries **two** manifests under **the same directory** — `MANIFEST.md`
(130) and `MANIFEST.tsv` (111) — so "does this directory have a manifest" is not even a function
of the directory.

**`strays/MANIFEST.tsv` reads 54 rows here and `prune3` wrote 53** — one header line. Quoted with
both numbers rather than reconciled, because the difference is a convention, not a fact about the
tree.

---

## 7. THE INSTRUMENT: `census.py` asks BOTH, and its plants test the PROPERTY

`classify_one` is the single copy of the rule. **The census classifies with it and the plants drive
it** — not two implementations that happen to agree. Branch order is the answer to §4: an unbounded
reader is placed in its own cell *before* it may make anything opened.

**Six false-able controls, each a case one question alone PASSES** (`.venv/bin/python .agents/slop/readerdecl/census.py --plant`, exit 0, **6 of 6 fire**):

| control | wants | question it defeats |
|---|---|---|
| declared + no reader | `ORPHAN` | (a) alone passes it |
| reader + no declaration | `UNDECLARED-OPEN` | (b) alone passes it |
| nested under a declared parent, holding neither | `INERT` | an **inheriting** walk passes it |
| only-unbounded reader | `UNVERIFIABLE`, **never `WITNESSED`** | (b) alone calls it opened |
| the same row with a bounded reader | `WITNESSED` | — (proves the cell is load-bearing) |
| an unbounded reader must never land in `ORPHAN` | ≠ `ORPHAN` | a reader-exists census's default |

**The first version of the plant FAILED control 4 and the failure was real:** the census inlined the
rule and the plant called a *second* copy. Two implementations of one rule is a control that tests
nothing — the `zerogate`/`plantthe46` vacuous-plant class arriving by a third door.

**Three further defects this file found in ITSELF, each kept with its before-value:**

1. `git cat-file --batch` headers are `<oid> <type> <size>`, and reading `header[1]` returned the
   string `blob` as every key — so **every citation missed and the entire reader axis read 0**,
   printing five digits. A DEAD instrument, and the first run's output looked plausible.
2. In-slop peers were recorded as `reader` *and* `peer`, so the `WITNESSED` cell counted the very
   thing §4 says is not a witness — **4190 of 4437 instances.** The prose and the cells were
   making opposite claims; the cells won until they were changed.
3. `(a) 'is a declaration present?' alone passes N` printed the `(a)AND(b)` cell — **12 where the
   answer is 162.** A passing-row count was presented as a question-alone count.

---

## 8. WHAT IT CANNOT SEE ABOUT ITSELF

- The runtime-path blind spot (§0.1) is **one-sided**, and a cross-tab whose two axes have
  different blind spots is weaker than it looks. It makes axis (b) a floor and axis (a) a floor,
  but not by the same margin, so the **off-diagonal sizes are not comparable to each other** in
  the strict sense. They are comparable as *counts of what a literal-path census sees*.
- `UNVERIFIABLE` is a **static** verdict. §4b shows a bounded reader can still be bounded below
  its own runtime, so **28 is a floor and the true count is higher.**
- PROSE-as-reader is a **decision** (§0.3), and it moves 35 CITED rows and re-scores the whole
  2×2 if reversed.

---

## 9. SETTLED — NOT RE-ARGUED

`declareverdict` on `RED_IS`, `plantthe46` on a zero-declaration report, and `declaretwo` itself all
concluded: **a reviewer is not a missing feature — it is the part of the answer that isn't an
instrument.** This report does not propose a reviewer.

**One thing this answer needs that is not an instrument, named — one per line, and stopping there:**

```
.agents/slop/deadclause        only ENTRY-POINT reader is checks/residue.py, measured needing 524 s
.agents/slop/slopcopies       only ENTRY-POINT reader is checks/residue.py, measured needing 524 s
```

**Both read `WITNESSED` in `census.rows` and both verdicts are OPTIMISTIC** — §4b: `residue.py`
carries a bound today and `slowgate` measured it exceeding it. That is what needs a human, and it
is not an instrument's to decide.