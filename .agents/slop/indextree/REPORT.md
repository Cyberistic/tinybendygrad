# indextree — `git ls-files` is being read as if it were the tree

**Landed:** `gates/indexread-gate.py` + `gates/indexread-baseline.rows` (in git, beside the gate).
**Census:** `.agents/slop/indextree/census.py` → `census.rows`.
Every number below was measured by running the thing named. Nothing here is quoted from memory.

---

## 0. The live finding, first: the index is lying RIGHT NOW

Not at the scale of the night (2 files). At **88**.

```
INDEXREAD TREE-COMMITTED 6296  INDEX 6208  DIVERGENCE 88
```

`git ls-tree -r HEAD --name-only` → **6296**. `git ls-files` → **6208**. **`comm` both ways: 102
committed files are invisible to `git ls-files`**, and `gates/git-massdelete-gate.py` — *the
catastrophe guard itself* — is one of them. 14 further paths are in the index but not the tree.

So the brief's claim is not a warning about a past state. The index is **already** a partial lie,
and the guard named in the brief is **one of the files it hides**. `prune4`'s number (2 of 24) is
the fully-reset end of the same curve; 88 of 6296 is where it is sitting at 06:58 tonight.

---

## 1. The census — by DISCOVERY, and the walk's own scope

**Walk:** `os.walk` over **three roots** — `checks`, `gates`, `.agents/slop` — pruned of
`.git .jj __pycache__ .venv node_modules references`. **782 `.py` discovered**, **724 committed**
(the committed filter is `git ls-tree -r --name-only HEAD`, not the index).

**61 committed files read the index.** The risk split:

| | count | meaning |
|---|---|---|
| population (committed `.py` under the three roots) | **724** | the walk's output |
| **offenders** | **61** | read an index shape |
| **at risk** (no tree primitive anywhere in the file) | **36** | the index is their ONLY authority |
| **partial** (also read `ls-tree`/`diff-tree`/`cat-file`/`rev-parse`) | **25** | index is not their only authority |
| safe | **663** | no index shape at all |

Forms: `ls-files` 25 · `--cached,add` 5 · `add` 2 · one each of
`--cached,--porcelain,add,ls-files`, `--cached,add,read-tree`, `--cached,add,ls-files`,
`--porcelain,ls-files`.

**The `checks/` + `gates/` instruments, and what each would have WRITTEN under a reset index:**

| file | forms | what it would write at 0 instead of 724 |
|---|---|---|
| `checks/substrate.py:555` | `ls-files --error-unmatch` | port/non-port provenance + the PORT ALARM derived from it — an empty port |
| `checks/sweep.py:338,381,542` | `ls-files -z`, `--porcelain` | **the `LIVE_UNITS` census**: the very instrument that held 2 353 files and reported a floor computed over nothing |
| `checks/txt-owners.py:140` | `ls-files` | the `.txt` **owner** census — 550 hard / 139 excused becomes 0/0 |
| `checks/repro-paths.py:70` | `ls-files --` | `e2e.py` stage input census → "0 inputs named" |
| `checks/residue.py:164,429` | `ls-files -z`, `--cached`, `add` | residue/duplicate classes — **but** its `git add -A` at :429 is inside a `tempfile.TemporaryDirectory()` fixture on its own throwaway repo, so its *staging* is contained; its *census* at :164 is not |
| `checks/oracle-txt-census.py:236` | `ls-files` | the row-dump classification under `oracles/` |
| `gates/retention-check.py:304,322` | `ls-files -z --` | what the index holds per artifact dir |
| `gates/git-massdelete-gate.py:94,96` | `diff --cached`, `read-tree` | **the catastrophe guard's own deletion count** |
| `checks/git-index-guard.py:60` | `--cached` | the staged-set half of its own fingerprint |
| `checks/wallcheck.py` | `--porcelain` | *(partial — also uses `cat-file`/`rev-parse`)* |

**The ZERO-risk half, which is the point:** `gates/gendirs.py:469-481` already carries the lesson
written down — *"**`git ls-tree -r HEAD`, NOT `git ls-files -s`, AND THAT IS THE WHOLE POINT**"*,
with its own measurement (1006 intent-to-add entries staged, `ls-files -s` answering 1252). It is
an **exemplar already in the tree**, and the gate counts it as an offender only for the
`ls-files` string still present in its history comment — which is the classifier being honest
about a comment it does not read. It is the file to point new work at.

---

## 2. Gate or lint? — **GATE**, and here is the defence

A lint **prints**. Three consequences, in increasing order of how much they cost:

1. It cannot `exit 3`, so it cannot say **"I could not measure"** — and this gate has a real
   REFUSED state (baseline absent, `HEAD` unreadable, not a repository). A gate that cannot refuse
   must answer anyway, and a wrong answer from a broken instrument is the exact failure this
   project keeps re-learning.
2. It has no exit code, so **nothing can call it.** `hooks` measured 13 of 14 gates in 4.1 s
   combined — a caller with a list needs a number to branch on. A finding with no exit is a note,
   and notes do not get run.
3. It would **invent a sixth verdict.** `gates/gatekit.py:60` spells the five as
   `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. The gate imports `PASS, FAIL, REFUSED, DEAD,
   VERDICT` **from gatekit** — one definition, not a second copy. **`SKIP` is deliberately not
   imported**: this gate has no "could not run" state distinct from REFUSED, and importing a
   constant it can never produce would be a pin in a comment, which `gatekit`'s own `oracle_drift`
   docstring calls "a pin that cannot fail".

**The subject is the STATE, not a diff** — which is why this is a *different* gate from
`git-massdelete-gate.py` rather than a mode of it: that one asks *did this commit delete too much*;
this one asks *does any file this repo ships enumerate its population through a deletable index*.

**It is green at rest, on purpose.** The 61 predate this file. A gate that cannot pass teaches
nothing and gets skipped — the `PROOF.bend` 18-TODO lesson. So the default claim is **GROWTH**
(offender set ⊆ pinned baseline, `gates/indexread-baseline.rows`, in git beside the gate — the
`gates/cstyle-live.rows` precedent), and `--strict` states the strong claim and is **red today
(exit 1)**. Red-at-rest is a *measurement* here, not a defect, and it is opt-in.

---

## 3. Falsifiability — both directions, planted and named

**PLANT TARGET (named, as asked): `.agents/slop/abi4check/plant-measure.py`** — a committed
`.agents/slop` scratch instrument, chosen because it is **currently clean**, so the plant tests
*detection* and not *already-known-ness*. `sha256` before `765e125c01b76f59ac451da7217f44977871ffebc093a17ebdbf4c619a8f3e17`,
restored to the identical digest, `git diff` empty afterwards.

| plant | expected | measured |
|---|---|---|
| `subprocess.run(["git", "ls-files"], ...)` | FAIL | `NEW  .agents/slop/abi4check/plant-measure.py: ls-files` → **exit 1** |
| `subprocess.run(["git", "diff", "--cached"], ...)` | FAIL | **exit 1** |
| `subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"], ...)` | PASS | **exit 0** |
| *(no plant — restored)* | PASS | **exit 0**, sha256 identical |

The `ls-tree` row is the half that matters: the gate is not a keyword blacklist, and the correct
form of the same call passes it. Re-proven **after** the §7 pre-filter optimisation, because an
optimisation is exactly where a detector silently stops detecting.

The other three verdicts, each reachable and measured:

| state | how | exit |
|---|---|---|
| `REFUSED` | baseline moved aside | **3** |
| `DEAD` | walk monkeypatched to return 0 files → *"walked 0 files — the walk is broken, not clean"* | **5** |
| `PASS` | at rest | **0** |

`DEAD` is the answer to `zerogate`'s two GREEN-ONLY plants: **a walk that finds nothing is not a
clean census.** There is no path by which this gate prints `PASS` with an empty population.

---

## 4. How the gate establishes the tree's truth **without** the index — and does not agree with the lie

**It runs no `git ls-files` and no `git diff --cached`, not even to check itself.**
Population comes from `git ls-tree -r --name-only HEAD`, which reads the **commit tree object** in
`.git/objects` — content-addressed, immutable, and out of reach of any index operation.

The proof, run under a **throwaway** `GIT_INDEX_FILE` so `.git/index` was never written:

```
$ GIT_INDEX_FILE=$T/empty-index git ls-files | wc -l
0                                    # a naive instrument believes this
$ GIT_INDEX_FILE=$T/empty-index .venv/bin/python gates/indexread-gate.py
INDEXREAD TREE-COMMITTED 6296  INDEX 0  DIVERGENCE 6296
INDEXREAD POPULATION 724  OFFENDERS 61  BASELINE 61  NEW 0
exit=0                               # verdict UNCHANGED
```

**A self-checking instrument that shares the index with its subject cannot detect the index.** That
is not a caveat here, it is the design: the index is read **once, as a diagnostic, and never as
the population** — so the gate does not merely survive the reset, it *reports* it (`DIVERGENCE
6296`). `.git/index` mtime verified untouched after every run.

**Which trap each primitive avoids:**

| primitive | trap 1 `ls-tree` no `--name-only` | trap 2 `cat-file` fed paths | trap 3 index reset |
|---|---|---|---|
| `git ls-files` | avoids | avoids | **falls in** — returns 0 |
| `git ls-tree -r --name-only HEAD` | **avoids** (flag passed at every site) | **avoids** (never calls cat-file) | **avoids** |
| `git cat-file --batch` fed **paths** | avoids | **falls in** | avoids |
| `git cat-file --batch-check` fed **OIDs** | avoids | **avoids** | avoids |

The fourth row is the useful asymmetry: **`cat-file` fed OIDs is also index-free, but it cannot
enumerate** — it answers about objects you already have OIDs for. So `ls-tree` is the
**enumeration** primitive and `cat-file`-on-OIDs is the **resolution** primitive; they are not
alternatives, and this gate needs only the first.

---

## 5. The three traps, as named entries — what to LOOK FOR, not a test

These are not tests. `prune4` discovered two of the three **by being wrong and noticing a number
that did not add up**, and that is the only way either was found. So, what to look for:

**TRAP 1 — `ls-tree` without `--name-only`.** The line is `100644 blob 293ea9c…\t.agents/AFFINITY.tsv`.
**LOOK FOR:** a `.split()` or `field[0]` that yields `100644`. A census that reports the same
count either way but whose names are all modes. *Silent* — no error, 6296 rows that look like paths.

**TRAP 2 — `cat-file` fed paths.** MEASURED: `printf 'AGENTS.md\n' | git cat-file --batch` →
**`AGENTS.md missing`** — for a file that exists in `HEAD`. `--batch-check` says the same.
**LOOK FOR:** a byte count of 0 that produced a **clean, plausible, confident number**. A 99%
coverage floor computed over a corpus that was never read is the dangerous shape, not the safe one.
Feed OIDs and the identical path resolves to `blob 38408`. **A measurement that reads nothing
produces the most trustworthy-looking output in the system.**

**TRAP 3 — `ls-files` after a reset.** Returns **2** (per `prune4`) or **0** (an emptied index),
where the tree has 6296. **LOOK FOR:** two numbers that should agree and don't — *the trigger
`prune4` actually used*. Or a census that drops to zero and still exits 0. Run the same gate under
`GIT_INDEX_FILE` at a throwaway path: if its verdict moves, it was reading the index.

---

## 6. What this gate CANNOT see — said first

1. **Destruction 4: staging that is CORRECT-BUT-UNDER-ANOTHER-UNIT's-ENTRY.** `twopass`'s
   `fold.bend` sat in the index under another unit's entry and a commit landed without it. **This
   gate cannot see that.** The staging was *well-formed*; the index was not corrupt; `ls-files`
   reported it faithfully. Nothing about "is this file reading the index" bears on "whose entry is
   this". **That needs PATH OWNERSHIP** — who staged what, compared against who wrote it. Not
   implemented here, and named as a gap rather than papered over.
2. **A commit message that lies.** `gates/msgdiff-gate.py` is that gate. Out of scope.
3. **Its own blindness, self-referential:** it excludes **only itself** from the walk. That is a
   deliberate, bounded self-exemption (its source necessarily contains every form string) and it is
   the single largest thing it is not checking. It is stated in the code, not hidden.
4. **Uncommitted files are invisible** — the population is committed-by-construction. A new
   index-reading file is caught on the commit *after* it lands, not before. That is the cost of a
   tree-authoritative population, and it is the correct trade.
5. **It reads SOURCE, not behaviour.** A file can call `ls-files` in a branch that never executes,
   or build a path by concatenation (`"ls" + "-files"`), which neither the AST classifier nor the
   pre-filter sees. Both are recorded as known limits; neither is defended as impossible.
6. **It says nothing about whether an offender's index read is WRONG.** 61 offenders are not 61
   bugs. `retention-check.py:142` *documents* that its `ls-files` reads the index and defends it.
   The gate reports the shape; judgement stays with the caller.

### ONE instrument or TWO — and why `msgdiff` argued for two

**TWO. And `msgdiff` is right, for a reason that generalises.**

Their subjects are different *kinds* of thing: this gate's subject is **the state of a repository**,
`msgdiff`'s is **a commit's own message about its own diff**. One commit can carry both subjects,
so one exit cannot say which failed — a caller branching on `$?` gets an answer to a question it
did not ask.

The deeper reason is **verdict stability**. A state-gate's verdict changes when the working copy
changes; a message-gate's verdict is frozen against an immutable revision. Merging them forces one
of two compromises: the state part becomes un-runnable in a message check (you cannot ask "is the
index sane" about a commit that is 40 revisions old), or the message part becomes un-runnable in a
state check. Either way the instrument can be neither.

**And they are not even neighbours:** `msgdiff` catches a message that claims a deletion its diff
does not witness — a *false claim*. This gate catches a reader pointed at a deletable index — a
*wrong measurement*. One is a lie, the other is an error. `AGENTS.md`'s own precedent for keeping
them apart is that the mass-delete guard's subject is the DIFF and `msgdiff`'s is the MESSAGE, and
the two "3"s in this file — `checks/sb-gate.sh` and `gatekit` — share **zero lines**, so they are
already two instruments wearing one number.

---

## 7. Cost

| | measured |
|---|---|
| **runtime** | **0.41 s/run** — 5 runs in **2.05 s** total |
| `hooks`' 13 gates | 4.1 s combined (~0.32 s each) — this gate is **~1.3× one of those** |
| network | **none.** 0 references to `urllib`/`requests`/`socket`/`http`. All git reads are local objects. |
| writes | **none.** The only writer is `--write-baseline`, called deliberately. |
| dependencies | `git` + stdlib (`ast`, `subprocess`, `warnings`) + `gatekit` for the verdict constants |

Profiled, not guessed: `import 0.011s · ls-tree 0.084s · walk 0.088s · scan 1.879s` — **the scan was
the entire cost.** A substring pre-filter (skip-if-absent: a file whose bytes lack `ls-files`
cannot hold the literal) cut 724 walked → **68 parsed**, 1.88 s → 0.13 s. **The offender set was
61 before and after every version of it**, and falsifiability was re-proven after the change. The
`add` form needed a narrower filter than the other four — it is only an offender when a git word is
a sibling, and it is **always quoted** where git is concerned (`git("add", "-A")`) and never in
`seen.add(`.

**Why the optimisation matters beyond time:** the first census was a **regex** and reported **183**
offenders where the truth is **61**, because `\.add\(` matched `seen.add(` on Python sets —
**106 false positives, a classifier error of exactly the kind doctrine 1 exists to catch.** The
detection is AST over string constants, because AST gives two things a regex cannot: comments are
not in the tree at all, and a docstring is a `Constant` that is the whole of an `Expr` statement,
which `bare_strings` excludes. **That single substitution is the difference between a census you
can act on and a number you have to re-derive by hand — which is what "LOCs is quality" costs
when a classifier is wrong.**

---

## 8. Reconciliation: 61 vs 80, and which is authoritative

`.agents/slop/indextree/census.py` says **80**; the gate says **61**. Both are correct and the gate
wins, for two stated reasons: the census is **regex** (so it counts `.add(`) and it includes
**uncommitted** files (16) **and the gate's own source**. The gate is **AST**, **committed-only**,
**self-excluded**. **One number governs; the other is its build step.**

---

## What I did not do

Did not touch any gate body, `AGENTS.md`, or `tinybendygrad/`. Did not commit, did not `git add`,
did not stage, did not `@` anyone. **`.git/index` was never written** — every demonstration used a
throwaway `GIT_INDEX_FILE`, verified by mtime. The plant file was restored to a byte-identical
`sha256`. `ruff check` clean on both files. No `.txt` was created (0).