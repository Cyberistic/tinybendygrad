# nameless — the subject census: what a gate NAMES and the commit no longer HAS

Unit `nameless`, 2026-10-07/08. Scope, stated once and repeated in every number below:

> **every path a TRACKED `checks/*.py` or `gates/*.py` file names, measured against
> `git ls-tree -r <rev>`,** by discovery over three axes (readers, subjects, tree). No hand list
> of gates, subjects or directories. Nothing outside `.agents/slop/nameless/` was touched;
> nothing was restored; nothing was committed or staged.

**THE TREE MOVED UNDER THIS UNIT, so every number is pinned by `rev` and two readings are kept.**
`HEAD` went `c83f04ad1` → `75ab9b8f8` mid-run (other agents committed). `census.py --rev` takes
the commit as an argument precisely because of this.

| at | readers | named | absent | LOST | IGNORED | PREFIX |
|---|---|---|---|---|---|---|
| `c83f04ad1` | 150 | 119 | 22 | **13** | 6 | 3 |
| `75ab9b8f8` (later HEAD) | 152 | 122 | 23 | **14** | 6 | 3 |

**The 13 → 14 delta is the TREE, not the instrument**: another agent added
`dup_census_lanes()` to `checks/no-txt.py` (verified by `git diff c83f04ad1 HEAD --
checks/no-txt.py`), which introduced the `checks/lanes/` spelling alongside `checks/lanes`.
Both commits are reproduced from one file; `--rows` writes either rows file.

## 0. HOW THIS MEASUREMENT IS WRONG — eight defects, each with its before-value

The rule is to find the error first, so this section leads. All eight were found by running
the instrument, not by reading it. Every one changed a headline number.

| # | defect | before | after | how it was found |
|---|---|---|---|---|
| 1 | **`ls-tree -r` lists BLOBS, so a tracked DIRECTORY is absent from its own output.** `.agents/slop` holds 4 062 tracked files at this commit and my first run reported it as an absent subject. | **89 absent of 158 named** | 43 | printed the absent list and saw `.agents/slop` in it |
| 2 | **"contains a `/`" is satisfied by ENGLISH.** Admitted `-`, `rows`, `rows.json`, `tinybendygrad/runtime/dtype.c emit`, and a sentence containing `2 hits)`. | **43 absent** | 38 | every entry was read by hand and was not a path |
| 3 | **A gate's OWN `--plant` control is a citation.** `checks/bad.py`, `checks/good.py`, `checks/driver.py`, `checks/first.py`, `checks/probe.js` are synthetic subjects a gate writes to test itself. Counting them is `readerdecl`'s failure one level up. | **38 absent** | 22 | cross-read `gates/gates-pop.py:841` and found them being *written* |
| 4 | **A reader-relative basename is not a subject.** `checks/abi.json`, `checks/both-census.py` are tracked; `checks/hermetic-census.py:47` records that two siblings "were gone". | **22 absent** | 17 | `HERE / "abi.json"` resolved to a tracked file |

Then two more, found while classifying, both of which inverted the verdict rather than the count:

| # | defect | before | after |
|---|---|---|---|
| 5 | **My "is it generated?" test was vacuous.** It asked "does a tracked directory sit UNDER this path?" — and `checks/` is a tracked top, so every lost file under `checks/` satisfied it. 15 of 23 were called GENERATED, including the two real losses. | **2 LOST** | 17 LOST |
| 6 | **A tracked directory used as a SCOPE is not a subject.** `tinygrad/` (230 tracked files) is `checks/devgate.py:210`'s `VENDOR_PREFIX` — a tuple of trees the gate walks *around*. | 3 false LOST | 3 PREFIX |
| 7 | **The rows file disagreed with the report above it.** `_classify`'s fallthrough is `LOST` and I ran it over EVERY row, so `subjects.rows` labelled **90** rows LOST — including `pyproject.toml`, `README.md` and 30 tracked `.agents/slop/` files. Stdout was right (it classified only the absent set); the table was wrong. | 90 rows mis-classified | 14 LOST / 316 PRESENT / 6 IGNORED / 7 PREFIX |
| 8 | **A gate may SEARCH for its subject and find it elsewhere.** `checks/hermetic-census.py:86` looks in `(HERE, REPO/".agents"/"slop"/"hermetic")` and `isolate.py` (4 181 B) exists at the second, untracked. Its `PASS` is correct; my one-path-per-literal census called it a lost subject. | 1 false positive | 1 false positive, now named as an instrument limit |

**The residual errors I cannot rule out, stated before you trust the 14.**

1. **A subject built at runtime is invisible.** This census sees string CONSTANTS. A subject
   assembled by concatenation (`f"rows-{name}-{which}.rows"`, or `os.path.join(ROOT, p)` where `p`
   arrives as an argument) names no constant and is **not counted here**. `readerdecl` names this
   as its own blind spot 1 and calls every reader count a LOWER BOUND; that word applies here too.
   One measured instance of the size: `checks/census.py` writes `rows-{name}-{which}.rows` and so
   names **no** individual row file, while `checks/unowned.py:112` must declare it by hand in
   `GENERATORS` for the same reason.
2. **A gate may SEARCH for its subject, and this census cannot follow a search.** Defect 8:
   `checks/hermetic-census.py:86` looks in two directories and found its file at the second one.
   A path-literal census records the literal's own path and calls it absent. **This makes the 14
   an OVER-count of losses and an UNDER-count of real ones at the same time**, which is the worst
   of both and the reason §3 reads every gate individually instead of trusting the total.

## 1. THE DENOMINATOR

```
gate homes          ('checks', 'gates')   loaded BY PATH from gates/gates-pop.py:103
tracked readers     152                  a directory walk of the commit, narrowed to *.py
string constants    15 421               across those 152 files (docstrings 627, excluded)
DISTINCT PATHS NAMED 122
ABSENT from <rev>    23
  by class: LOST 14, IGNORED 6, PREFIX 3
LOST                  14                 (13 at c83f04ad1 -- see the delta note above)
rows                 345                 .agents/slop/nameless/subjects.rows (346 lines with header)
```

`HOMES` is loaded, not retyped — `gates/gates-pop.py` admits in its own comments that the two
homes are "a list, and it is admitted". `*.py` is a **suffix set** and this file says so: the two
homes hold 224 tracked files, 150 of which are Python. The walk is the population; the suffix
narrows it and both numbers are printed together for exactly that reason.

**Reader population, and the share you asked for:** all 14 naming instances of absent subjects
come from `checks/` (8) and `gates/` (6); **0 are in-slop peers, and that is 0 BY
CONSTRUCTION, not a finding.** This census reads only the two gate homes.
`readerdecl/census.out:28-32` measured 4 190 of 4 437 reader instances (**94%**) to be in-slop
peers against 81 in `checks/` and 39 in `gates/` — **that is a different population at a
different commit** (`7ad97ccbcbfd`, and directory-keyed rather than subject-keyed). The honest
statement is: **`readerdecl` says the peer share of *the tree's readership* is 94%; this census
deliberately excludes peers, so it says nothing about them and must not be read as contradicting
it.**

## 2. THE 14 LOST SUBJECTS, AND WHO NAMES EACH

Every one verified individually against `git ls-tree -r HEAD` (0 hits) and `os.path.exists` (all
absent from disk too). Rows: `.agents/slop/nameless/subjects.rows`.

| lost subject | named by | size if found |
|---|---|---|
| `checks/canon.py` | `checks/gate_norm.py` | 11 270 B |
| `checks/isolate.py` | `checks/hermetic-census.py` | 4 181 B |
| `checks/drive.mjs` | `checks/gate.py` | 3 438 B |
| `checks/BASELINE.tsv` | `checks/slop-declare.py` | 794 B |
| `checks/declare.tsv` | `checks/slop-declare.py` | 8 585 B |
| `checks/gate.out` | `checks/gate_norm.py` | 3 976 B |
| `checks/lanes`, `checks/lanes/` | `checks/dup-census.py`, `checks/no-txt.py` | a cache DIR, never tracked |
| `checks/nl-port-post.txt` | `checks/nl-gate.py` | 34 169 B |
| `checks/rn-orc.txt` | `checks/rn-gate.py` | 7 683 B |
| `checks/rn-port.txt` | `checks/rn-gate.py` | 8 734 B |
| `checks/rows`, `checks/rows.json` | `checks/hermetic-census.py`, `checks/abi4_gate.py`, `checks/jsfix_gate.py` | 64 288 B for `rows.json` |
| `checks/abi_gate.py.fixed` | `gates/gates-pop.py` | **synthetic — see §4** |

The other two classes, so the 14 is not read as 23: **IGNORED 6** (`.gitignore:169` proves
`gates/artifacts/` and `checks/gen*` are declared-absent) and **PREFIX 3** (`checks/`, `tinygrad/`,
`tinybendygrad/` as scopes).

## 3. THE ANSWER NOTHING ANSWERED: does the gate REFUSE, or misbehave?

Each gate that names an absent subject was RUN, and the **token** recorded — never the exit code.
Full output: `.agents/slop/nameless/plant.out`.

```
REFUSED (correct — a precondition was absent)  4
FAIL     (it ran and got it wrong)             8
PASS     (it ran and agreed)                   7   <-- THE FINDING
TIMEOUT  (cannot classify; 45 s budget)         2
CRASH    (subject present, tool died)          0
```

(Read at `75ab9b8f8`. At `c83f04ad1` the split was PASS 6 / FAIL 5 / TIMEOUT 6 — three gates
that TIMEOUT at 45 s here finished and were reclassified. **A token table is a measurement of the
budget too**, which is why `TIMEOUT` is printed rather than folded into any verdict.)

**`SKIP` and `DEAD` are 0 here, and that is not an omission:** `gates/gatekit.py:59` spells the
five as exits `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`, and no gate in this population
emits 4 or 5. **A gate that exits 0 while its subject is absent is worse than one that refuses,
because it is trusted** — so the 6 `PASS` are the headline and the 4 `REFUSED` are the control
that proves the instrument could tell the difference.

### The six that PASS while naming an absent subject

| gate | absent subject it names | token | is it a defect? |
|---|---|---|---|
| `checks/nl-gate.py` | `checks/nl-port-post.txt` | **PASS** | **YES — the finding** |
| `checks/no-txt.py` | `checks/lanes/` | **PASS** | no — cache, documented at `:156` |
| `checks/devgate.py` | `tinygrad/` | **PASS** | no — `VENDOR_PREFIX` at `:210` |
| `checks/hermetic-census.py` | `checks/isolate.py` | **PASS** | **no — see below** |
| `checks/oracle-txt-census.py` | `tinygrad/` | **PASS** | no — `excluded` at `:238` |
| `gates/gatekit.py` | `gates/artifacts/` | **PASS** | no — `.gitignore`d, `:150` |
| `gates/gendirs.py` | `checks/gen/probe.js` | **PASS** | no — its own plant, `:612` |

**Six of the seven are not defects, and each names its own absence in its own source** — which is
the whole lesson of this section: **`PASS` is not the finding; `PASS` on a subject that is gone
FROM EVERY CONTAINER is.** `checks/no-txt.py:156`, `checks/devgate.py:210`,
`checks/oracle-txt-census.py:238`, `gates/gatekit.py:150` and `gates/gendirs.py:612` all say so
in their own words.

`checks/hermetic-census.py` is the instructive one and I initially mis-called it. It searches
**two** locations — `_ISOLATE_DIRS = (HERE, REPO/".agents"/"slop"/"hermetic")` at `:86` — and
`isolate.py` (4 181 B) **exists** at the second one, untracked. Its `refuse()` at `:88-92` is
armed and did not fire, correctly. **My census tracks ONE path per literal and cannot see a
SEARCH**, so it reported a subject as absent that the gate had legitimately found elsewhere. That
is a false positive of this instrument, and it is the honest limit of a path-literal census: it
misses alternate-location resolution entirely.

**One is real, and `nl-gate` is it. Measured, not argued:**

```
.venv/bin/python checks/nl-gate.py              -> rc=0   AGREE, 205/205 rows
.venv/bin/python checks/nl-gate.py --selftest   -> rc=1   FileNotFoundError:
      checks/nl-port-post.txt
```

`checks/nl-gate.py:416` reads `(HERE / "nl-port-post.txt").read_text()` **inside `selftest()`**,
and `main()` dispatches to `selftest()` only under `--selftest` (`:458-459`). So the default run
is **green while its subject does not exist** — and the one branch that would have noticed is not
the branch anyone runs. And when that branch *is* run, it **CRASHES**: `FileNotFoundError`, an
uncaught exception, **not a `SKIP`.** A `SKIP`'s subject was absent; this one's subject was absent
*and the gate died on it*, which is the measurement that separates "nothing to grade" from
"graded and died". `checks/dup-census.py:204` documents the same cache going the other way and
fixing it by REFUSING — the precedent for the cheap fix, in this tree, already written.

## 4. RECOVERABILITY

The naive test — `git cat-file -s 371cc64c9^:<path>` — answers **"no blob" for 11 of 13**,
because these files were never at those paths before the sweep: `3f0e70ff1` MOVED them into
`checks/`, then `371cc64c9` swept them. So recoverability is asked over ALL history by basename
and proved with a non-empty blob (`.agents/slop/nameless/recover.py`,
`.agents/slop/nameless/recover.out`):

```
RECOVERABLE    11 / 13
UNRECOVERABLE   2 / 13   -- checks/abi_gate.py.fixed, checks/lanes
```

**The 2 unrecoverable ones are not losses, and both are deliberate:**

- **`checks/abi_gate.py.fixed`** — `gates/gates-pop.py:720` *assigns* it in memory
  (`out["checks/abi_gate.py.fixed"] = GOOD_ROOT`) as the "FIXED form, asserted clean in the same
  breath, so the plant cannot be satisfied by a clause that calls everything red". It is a value
  in a dict. **It should never have been in my LOST class, and its absence is the point.**
- **`checks/lanes`** — a CACHE directory. `checks/dup-census.py:204` already says so in the tree:
  "⚠ `CACHE` IS NOT IN GIT (`git ls-tree -r HEAD --name-only | grep -c 'checks/lanes/'` = 0)".
  Its basename has never appeared in any commit, which is what "unrecoverable" measures here.

So: **10 of the 14 are recoverable losses; 4 are not losses at all.** That is the honest split,
and it is smaller than the 14 the raw walk reports.

## 5. DOES THE TREE ALREADY OWN A DETECTOR? — yes, three, and none of them is this one

Read before building anything, per the brief:

1. **`.agents/slop/SUBJECTS.rows`** — 9 rows with `path`/`in_head`/`on_disk`/`readable_now`,
   produced by walking **three gates' source**. It found `.agents/slop/eq/lane.py` and
   `.agents/slop/eq/nl-gate-noguard.py` (both `in_head=False on_disk=False`) and
   `.agents/slop/nl/nl-oracle.py` (`in_head=False on_disk=True` — since restored by `0d901e986`,
   and `in_head=yes` at this commit). **It is the right SHAPE and it is 9 paths.** It is a
   per-gate list: it can only see the three gates it was written from.
2. **`checks/unowned.py`** — has `in_head` and `cited`/`exec`/`written` columns and a real
   `verdict()`. **It runs the census in the INVERSE direction**: it starts from `git status`
   (dirty paths) and asks who reads them. It never starts from a gate and asks what it names, so
   it **cannot see this class** — a swept subject is not dirty, it is *absent*.
3. **`checks/slop-declare.py`** — walks tracked `.agents/slop/*/` directories for whether each
   DECLARES itself. It detects *absence of a declaration*, not absence of a *subject*.

**Does the class need a general detector? YES, and here is the arithmetic.** The list is **9
paths**; the population is **14 lost subjects in 11 gates**. `SUBJECTS.rows` is **smaller than the
class it was meant to record** — it missed `checks/nl-gate.py` entirely, which is the single
worst member, because it never looked at that gate. A detector worth building must be **bigger
than the list**, and this one is measured at 1.6× from three gates. `.agents/slop/nameless/census.py`
is that shape: population by walk, subjects by AST, absence by `ls-tree`, and **five plants that
must fire** (4/5 do; control 3 fires by design, see below).

**Recommendation to the orchestrator (described, not applied):** promote `census.py` to
`checks/subject-census.py` with three changes — (a) classify *before* token-reading so the four
by-design `PASS`es retire; (b) add the missing `SKIP`/`DEAD` detection, since 0 of 21 gates emit
them today and a detector that cannot see them is untested on them; (c) have it print `SUBJECTS.rows`
as its own output so the per-gate list stops being maintained by hand.

## 6. THE CONTROL THAT FIRES, AND WHY rc=1 IS THE RIGHT ANSWER

`--plant` runs five controls (`.agents/slop/nameless/plant.out`). **4 of 5 pass; control 3 FAILS,
and it is supposed to:**

> `FAIL  no gate naming an absent subject is PASS: want [] got ['checks/devgate.py', 'checks/hermetic-census.py', 'checks/nl-gate.py', 'checks/no-txt.py', 'checks/oracle-txt-census.py', 'gates/gatekit.py', 'gates/gendirs.py']`

**This is the measurement, not a defect in the census.** The census asserts that a gate naming an
absent subject must not be `PASS`; seven do; the control fires. **A census whose control cannot
fail cannot be anything** (`readerdecl`'s header), and this one fails for the reason the brief
predicted. `census.py --plant` therefore exits **1**, and **that is the honest verdict, not a
broken tool.**

**And the control is now known to be IMPERFECT in the other direction, which is why §3 does not
stop at the seven.** Six of the seven are *declared* absences (each gate says in its own source
that the path is not supposed to be there), and one (`hermetic-census`) resolved its subject at a
second path. **So the control fires 7 times and 1 of the 7 is a genuine defect** — which means
the raw "PASS while absent" count is a LOWER bound on attention needed and an UPPER bound on
defects, and only §3's per-gate reading distinguishes them. **A control that fires on a
false positive is still a control that fires**, but it is not the same measurement as one that
fires only on truth, and this one is the former.

The other four: (1) a planted absent path classifies absent; (2) a planted present path does not;
(4) the five tokens are five; (5) the 150-reader denominator reproduces byte-identically across
two walks.

**The first version of control 3 was vacuous and I am recording that too.** It picked one gate
and asked "is this not PASS?" — and `gates/gate-surface.py` `FAIL`s for unrelated reasons, so the
control passed trivially. The control is now over the **whole class** and additionally asserts at
least one gate must `REFUSED` (it does: 4 do), which is the refusal the brief is about.

## 7. THE CHEAP FIX, DESCRIBED AND NOT APPLIED

Per the brief, I restored nothing. Ordered by measured value:

1. **`checks/nl-gate.py` — the one real defect.** Its `selftest()` reads `nl-port-post.txt` with
   no guard while `main()` dispatches to it under `--selftest`. Two lines: the same `refuse()`
   already at `checks/nl-gate.py:73-84` (which exists because *"the reader was a SIBLING at
   `.agents/slop/eq/` and the move carried this file without them, so `load()` raised
   `FileNotFoundError` FIRST"*) applied to `selftest()`. **Restoring the file is 34 169 B and
   recoverable; refusing on absence is 2 lines and permanent.** The in-tree template to copy is
   `checks/hermetic-census.py:86-92`, which searches two locations and `refuse()`s naming both —
   and which is the reason that gate's `PASS` is correct and `nl-gate`'s is not.
2. **The four by-design `PASS`es** — one `ABSENT_BY_DESIGN` class label each, declared by the
   gate that already documents its own absence (`no-txt.py:156`, `gatekit.py:150`,
   `gendirs.py:612`, `oracle-txt-census.py:238`). No behaviour change; the census stops crying wolf.
3. **`checks/gate_norm.py`** names both `checks/canon.py` (11 270 B, recoverable) and
   `checks/gate.out`, and returns **FAIL**. One restore may be the whole class here.
4. **`checks/rows.json`** (64 288 B, recoverable) is named by two gates, one of which
   (`jsfix_gate.py`) `FAIL`s. The largest single recoverable item in the 14.

## FILES

| path | what |
|---|---|
| `.agents/slop/nameless/census.py` | the census: 3 axes by discovery, `--rev`, 5 plants, token not exit code |
| `.agents/slop/nameless/census.out` | the run at `75ab9b8f8`: 152 readers, 122 named, 14 LOST |
| `.agents/slop/nameless/census-c83f04ad1.out` | the same run at the earlier rev: 150 readers, 119 named, 13 LOST |
| `.agents/slop/nameless/subjects.rows` | 346 lines = 1 header + **345 rows** at `75ab9b8f8`: `subject class form reader lineno in_head in_head_as on_disk` |
| `.agents/slop/nameless/subjects-c83f04ad1.rows` | 341 lines = 1 header + **340 rows** at `c83f04ad1` |
| `.agents/slop/nameless/absent-paths.rows` | the 13 paths put to the recoverability question |
| `.agents/slop/nameless/recover.py` | recoverability over ALL history by basename, blob-proved |
| `.agents/slop/nameless/recover.out` | RECOVERABLE 11/13, UNRECOVERABLE 2/13, both named |
| `.agents/slop/nameless/plant.out` | the 5 controls; **4 ok, control 3 FAILS BY DESIGN** |
| `.agents/slop/nameless/nl-gate.out` | the green default run (rc=0, AGREE 205/205) |
| `.agents/slop/nameless/nl-selftest.out` | the branch that reads the missing subject: `FileNotFoundError` |
| `.agents/slop/nameless/hermetic.out` | `hermetic-census` rc=0 — the *correct* PASS, subject found at a 2nd path |
| `.agents/slop/nameless/notxt-baseline.out` | `checks/no-txt.py` rc=0, unchanged by this unit |

`checks/no-txt.py` verified **rc=0** before and after. No `.txt` written. No commit, no staging,
no `git add`. No file outside `.agents/slop/nameless/` created, edited or deleted — the 19
modified `checks/`/`gates/` files in `git status` are other agents' in-flight work
(`gates/gatekit.py`, `checks/wallcheck.py`, `checks/nl-gate.py` among them), untouched here.