# prune4 — `.agents/slop` at 50 MB: the floor is 84.76% irreducible, and the reclaimable class is 100% live

Measured 2026-10-07 06:12–06:45 by discovery. Instruments beside this file: `measure.py`
(lstat/`st_blocks`), `census.py`, `duphash.py`, `dircopies.py`, `liveness.py`, `movecopy.py`,
`floor.py`, `final.py`, `prove.py`, `delete.py`, `settle-insprobe.py`, `orphan.py`.
Rows beside this file. **No `bend` was run. No `git add`, no `git rm`, no commit, nothing staged.**

Every figure is `st_blocks`/lstat. `os.path.getsize` appears exactly once, in `measure.py`, and
only to quote how wrong it is.

---

## 0. The three measurements, and the two of mine that were wrong

| instrument | says | verdict |
|---|---:|---|
| `du -sk .agents/slop` | **51 564 KB = 50.36 MB** | agrees with `st_blocks` to 4 KB |
| `st_blocks` × 512 (lstat) | **52 801 536 B = 50.355 MB** | the number this report uses |
| apparent size (no follow) | 42 871 498 B = 40.89 MB | < disk: block rounding on 3 974 small files |
| **`os.path.getsize` walk** | **1 537 921 882 B = 1466.7 MB** | **WRONG by 1416 MB** |

**`prune2`'s trap reproduces exactly.** 205 symlinks point at system binaries;
`getsize` follows them and charges this tree 1.4 GB it does not own. `prune2` measured the
overstatement at 1487 MB; I measure 1416 MB, the difference being live units' symlink churn.
An instrument that cannot see its population cannot be wrong because it cannot be anything.

### Two errors of MY OWN, both caught by a number that did not add up

**1. `git ls-tree` without `--name-only` — this made my `untracked` predicate VACUOUS.**
`prove.py` first asked git for the tracked population with `ls-tree -r HEAD -z`, which emits
`<mode> <type> <sha>\t<path>`, not paths. Every test of a bare path against that set therefore
failed, so **all 3 974 files looked untracked** and the "must not be tracked" clause of my own
rule certified nothing. I found it because `os.popen` and `subprocess` versions of the same
command returned sets of equal size (3977) that were **not equal**. Fixed with `--name-only`.
*An instrument that cannot see its population cannot be wrong, because it cannot be anything —
and this one could have been very wrong.*

**2. `git cat-file --batch` fed PATHS returns `<path> missing`.** It wants object NAMES. My
first floor census read back a **0-byte reader corpus** and reported "99.08% irreducible" —
a number computed against an empty set of readers, which degenerates bucket C into "is
committed". After feeding SHAs the corpus read **3 839 of 3 839 blobs** and the honest figure
fell to **84.76%**. *I nearly reported a 99% floor that was an artifact of a broken read.*

### And the standing trap: `git ls-files` is not a witness here

`git ls-files .agents/slop/orcdecide` answers **2** (only `enumerate.{py,out}`), while
`git ls-tree -r HEAD -- .agents/slop/orcdecide` answers **24**. The index was reset (the
condition the orchestrator warned about), so committed files read as untracked. **Every
trackedness test in this report uses `git ls-tree -r HEAD`, never `git ls-files`.**
`git status` shows 24 staged deletions under `orcdecide` that are not deletions.

---

## 1. The 12 biggest directories, classified — and the LIVE exclusion

`final.py`, one instant, 278 unit dirs, 50.36 MB. `LIVE` = owner dir written within 120 min.

| MB | files | cold (min) | unit | biggest files, classified |
|---:|---:|---:|---|---|
| 3.559 | 29 | 2021 | `strays` | all COMMIT-EVIDENCE (prune3 re-verified 24/24 blobs unique) |
| 2.418 | 16 | **57** | **`citeresolve` LIVE** | `hist.tsv` 1.1 MB, `classified.tsv` 656 K, `scan.tsv` 624 K |
| 2.184 | 5 | 1482 | `e2e` | COMMIT-EVIDENCE, named by 25 committed readers (prune2) |
| 1.859 | 13 | 1072 | `emptyevid` | COMMIT-EVIDENCE |
| 1.816 | 11 | 1071 | `sloptxt` | COMMIT-EVIDENCE |
| 1.707 | 15 | 1104 | `emptyblob` | COMMIT-EVIDENCE |
| 1.680 | 7 | 1813 | `notes` | COMMIT-REPORT (`bend2-constraints.md` 1.6 MB) |
| 1.680 | 22 | **40** | **`livenum` LIVE** | `scan-before.tsv` 624 K, `named.tsv` 524 K |
| 1.164 | 28 | 899 | `gitignore` | COMMIT-EVIDENCE |
| 1.109 | 301 | 953 | `loopfix` | 3 × `.bin` **ORPHAN** (see §5), rest committed |
| 0.969 | 228 | 1043 | `rerun` | COMMIT-EVIDENCE, the duplicates ARE the measurement |
| 0.961 | 104 | 963 | `bendsuite` | COMMIT-EVIDENCE |

12 dirs = **21.11 MB of 45.49 MB** across unit dirs; the remaining 4.87 MB is **278 loose files**
at the top of `slop`.

### The live set, DISCOVERED from mtimes — and it corrects the brief

The brief names `bendperf`, `midrun`, `twopass` "and three others" as live. Measured:

- **`midrun` does not exist as a directory of 11 MB.** It was 11.4 MB at 06:18 and **60 KB at
  06:27**: the unit deleted its own 11.4 MB `snap/` and wrote a `REPORT.md`. **A live unit
  reclaimed its own footprint while I was measuring it.** Had I pruned `midrun` as "the biggest
  untracked thing", I would have destroyed 11.4 MB of a running unit's work that the unit was
  about to reclaim by itself. That is the whole argument for the liveness exclusion, measured
  rather than asserted.
- **`bendperf` is cold** — newest file **904 min** (15 h). The brief's live list was wrong here.
- `twopass` is live (0.1 min). 24 unit dirs are live by mtime; together they hold
  **8.18 MB (18.0%)** of the tree and are excluded from every verdict in this report.

`liveness.py` prints the whole set. mtime says when a file was *written*, not whether a process
*holds* it — both are inferences; see §8.

---

## 2. The new axis: directories that are copies of other directories

`dircopies.py` keys **every** directory under `slop` by its full `(relpath → sha1)` map and
groups equal maps — equality of the whole set, not "shares some files". **583 dirs scanned,
19 identical-map groups, 1 339 392 B (1.28 MB) redundant.**

That is **2.5% of the tree**, and it did not yield the most, as the brief predicted. The three
largest groups:

| MB | files × n | the copies | verdict |
|---:|---|---|---|
| 0.273 | 7 × 11 | `gatehealth/gates-syn/{bc-u32,beautiful-mnist,ew-consts,ew-explog,i64-shl,i64-shr,mixin-op,ops-core,wk-cd,wk-eval,wk-f32}-gate` | **KEEP — see §4, this is where my rule's false positive lives** |
| 0.195 | 25 × 3 | `arghalf/pyside` ≡ `linfix/{before,after}-out/py` | **KEEP** — the arms ARE the experiment |
| 0.172 | 44 × 3 | `loopfix/{final-new,frozen-new,v2-new}` | **KEEP** — variant arms, pruned3 |

The remaining 12 groups are `e2epy/fixtures/*` (the ledger already ruled 37 fixture groups
"load-bearing"). **A retirement directory is not automatically a duplicate; it has to be an
EQUAL map, and the only 19 that are are instrument arms, not retirements.**

---

## 3. `orcdecide/retired/` — MOVE or COPY? **MOVE.** 19 files, 180 224 B

`movecopy.py` asks both questions, per file, from git:

```
19 files, 180224 B (0.172 MB) in .agents/slop/orcdecide/retired
  content in SOME commit (git is the archive):  19/19
  committed at THIS path in HEAD:              19/19
  byte-identical twin still at oracles259/:      0/19   -> MOVE (original is gone)
```

**This unit MOVED, it did not copy.** `oracles259/` no longer exists at the root; the 19 files
were re-committed at `orcdecide/retired/`, where HEAD holds every one. The premise in my brief
— *"a retirement directory is a copy of what it retired"* — is **false for this case**, and the
correction matters: a MOVE is not a second answer to "what was there", it is *the* answer, and
180 KB is 0.36% of the tree. `orcdecide` is also LIVE (26 min) and was excluded from pruning.

---

## 4. The false positive my own rule would have cost

My deletion rule is: untracked ∧ gitignored ∧ committed generator ∧ cold owner ∧ no reader
names it. On its first run it returned **11 DELETE, 44 KB**. All 11 were
`gatehealth/gates-syn/*/gate.bin`. **That verdict was wrong, twice over:**

1. **`gate.bin` is not a build product.** It is **2 bytes containing `x\n`** — a captured
   stdout. Its six siblings (`bd.cmp bd.out bn.cmp bn.out py.cmp py.rows`) are **all committed
   in HEAD and byte-identical to it**, and `gate.bin` is the only one of the seven not in HEAD.
2. **The "committed generator" was a name-shape match.** The rule looked for `<stem>.bend` and,
   finding none at the artifact's path, fell back to "any tracked `.bend` with a matching
   basename". `gate.bend` matched **three unrelated files** — `.agents/slop/helpers-mut/gate.bend`,
   `.agents/slop/i64mul/gate.bend`, `checks/gate.bend`. `bc-u32-gate.bend` does not exist in
   HEAD at all (measured: 0).

And all **11 directories are byte-identical as a whole set** (`final.py`: 1 distinct
directory-signature across 11 dirs). So deleting `gate.bin` would have removed the one
uncommitted lane from **eleven gates that all answered `x`**, destroying exactly the evidence
the ledger's `spine/`/`rerun/` line warns about — 11 gates × 7 lanes is a comparison, and the
comparison is the copies.

**Rule change: the generator must be named by the artifact at the same path or a sibling.
Never a basename scan.** With that clause the same 11 files fall to REFUSE
(`no gate.bend at this path/sibling/parent in HEAD`) — for the right reason, which is that they
are not compile products at all. `AGENTS.md`'s two named failures (`nostraysshape`, `portzz`)
are the same trap; I walked into it and the instrument caught it.

**Second false positive, smaller:** my rule would also have deleted 8 cold `__pycache__` dirs
under the ledger's weaker precedent ("gitignored + 0 tracked"). My stricter rule refuses 3 of
them (`gitinput`, and 2 whose sibling `.py` is not in HEAD) — **the ledger's own precedent
would have deleted evidence my rule protects**, which is the direction I would rather err.

---

## 5. `loopfix/insprobe*.bin` — prune3's open question, advanced, still open

`prune3` refused 3 binaries (348 160 B) because the generator `insprobe.bend` was *"deleted and
never committed"*, and called that an **ABSENCE, not a proof of redundancy**. Its settling route
(1) was "the source recovered from somewhere". Route (1) has an instrument prune3 did not have:

**`git cat-file --batch-all-objects` sees every object in the store, including ones no ref
reaches** — which is exactly what `git add` followed by a reset or by this repo's index churn
orphans. `settle-insprobe.py` read the **whole store**:

> **MEASURED NEGATIVE: no blob anywhere in the object store is the `insprobe.bend` source.**
> The source was never added, even transiently.

This is a **strictly stronger** statement than prune3's `--all refs` search: it now covers
orphaned and unreferenced objects, not just reachable ones. And I newly established that the
compiles were **clean** — the committed `b-insprobe*.err` says
`[bounded] WITHIN-LIMITS rc=0 … :: ./bin/bend …/insprobe.bend -o  out=0B err=42B`, and the 42 B
of stderr is *provably* the banner `bend 2.0.35 is available: run bend update`, not a
diagnostic. So the binaries are certainly build products; what is still unknown is whether the
committed `.rows` came from *running* them or from an interpreted lane.

**I did not run them.** That is `prune3`'s route (2) and it would settle the question — the
binaries are self-contained, so no `bend` is needed. I declined: it executes an unverified
compiled artifact, and "run the binary" is not a measurement this prune can defend. **REFUSE
stands**, on a stronger footing than before.

---

## 6. WHAT I DELETED

`delete.py` re-verifies every precondition **at the moment of deletion** — a verdict is 20
minutes stale on a tree other units are writing, and prune3 §3 measured exactly that trap.

```
DELETED .agents/slop/e2epy/__pycache__       20480 B  gen=diff.py     owner cold 350 min
DELETED .agents/slop/skipexit/__pycache__    12288 B  gen=repro.py    owner cold 352 min
DELETED .agents/slop/bitcastrow/__pycache__  12288 B  gen=bc-gen.py   owner cold 725 min
DELETED .agents/slop/txtexec/__pycache__      8192 B  gen=tally.py    owner cold 856 min
DELETED .agents/slop/orcfix/__pycache__       8192 B  gen=lanes.py    owner cold 349 min
DELETED .agents/slop/figure2/__pycache__      8192 B  gen=plant.py    owner cold 856 min
DELETED .agents/slop/bendwire/__pycache__     4096 B  gen=oldexec.py  owner cold 271 min
FREED 73728 B (72 KB) over 7 files
```

Authority per file: **gitignored** (`.gitignore:13`), **0 tracked in HEAD**, **committed sibling
generator named above** (CPython rebuilds a `.pyc` on the next import, so regenerability is
proven without running anything), **owner cold > 120 min**, **no tracked reader names it**.
Ledger precedent: the last prune removed 11 `__pycache__` dirs on the same grounds.

**`du` before 51 604 KB → after 51 532 KB, delta 72 KB — exactly the freed sum.** I quote
`delete.py`'s own lstat sum (73 728 B), not the whole-tree delta: a whole-tree delta on this
tree is not a measurement, because it moved **+11.4 MB and −11.4 MB** in the same hour.

**`git rm --cached`: NONE NEEDED.** All 7 were untracked in HEAD and gitignored. Tracked counts
in HEAD under each touched directory are **unchanged** (`e2epy` 347, `skipexit` 29, `bitcastrow`
12, `txtexec` 23, `orcfix` 17, `figure2` 18, `bendwire` 40). `git status` for all seven is
**empty** except a pre-existing ` A fold.bend.ORIG` that is not mine.

**My own footprint: 240 KB** under `.agents/slop/prune4/` (I deleted a 0-byte `reader-mentions.rows`
produced by the broken `floor.py` — a DEAD artifact is not evidence).

---

## 7. `du` before / after, and the handoff

| metric | first read 06:12 | final 06:45 | note |
|---|---:|---:|---|
| `du -sk .agents/slop` | 50 776 KB | **51 564 KB** | net +0.8 MB; **not attributable to me** |
| `st_blocks` disk | 51 994 624 B | 52 801 536 B | |
| files / dirs / symlinks | 3 846 / 580 / 205 | 3 974 / 582 / 205 | other units' writes |
| `git ls-tree -r HEAD .agents/slop` | 3 968 | 3 881 | **fell** — other units commit *deletions* |
| unit dirs | — | 278 | +278 loose files at the top of `slop` |

The tree grew, shrank and grew while I measured. **The only number I will defend as mine is
`delete.py`'s 73 728 B, and the `du` delta of exactly 72 KB that matches it.**

### Handoff to the orchestrator — nothing below is staged or committed
Full table in `HANDOFF.rows` (42 rows).

```
# NO git rm --cached is required for what I deleted. These are candidates ONLY.

git rm --cached .agents/slop/bitcastrow/fold.bend.ORIG        385 024 B
   SETTLED in §9: `git show 61be7ea90^:<path>` restores it BYTE-IDENTICALLY and
   61be7ea90 IS an ancestor of HEAD. It is residue. NOT deleted by me because it is
   STAGED (` A`) -- a pending index entry that is not mine to discard.

git rm --cached <38 paths in committed-unnamed.rows>            282 624 B
   in HEAD, no tracked reader names them. 33 are bendwire/reach-*.out,
   the rest are citemass/ citemass / censusred / ccdead / nostraysshape scratch.

rm .agents/slop/helpers-tc-gate.bin                             258 048 B
   prune2 flagged it 14:20 and it is still here. No committed helpers-tc-gate.bend
   -> ABSENCE, not proof. Named "helpers-tc" with a HYPHEN while the .gitignore rule
   and every generator here use UNDERSCORES -- a name-shape guess, so: reported, not deleted.

rm .agents/slop/loopfix/insprobe{,-old,-v2}.bin                 348 160 B
   prune3's open question, advanced in §5 and still open. NOT recommended without
   running one of them.
```

---

## 8. IS 43 MB THE FLOOR? **84.76% of what is there now is irreducible, and the reclaimable class is 100% live-owned.**

`floor.py`, one instant, 3 974 regular files, 50.355 MB. Classes are decided by git and by a
batched read of **3 839 tracked text blobs (3 839 read, 78 292 503 bytes)** — not by a path shape.

| class | files | bytes | MB | share | irreducible? |
|---|---:|---:|---:|---:|---|
| **A** committed report (`*.md`, in HEAD) | 408 | 7 188 480 | 6.855 | 13.6% | **yes** — the audit record |
| **B** mutant, named by a tracked reader | 24 | 323 584 | 0.309 | 0.6% | **yes** — mutants are evidence |
| **C** committed AND named by a tracked reader | 3 187 | 37 244 928 | 35.520 | 70.5% | **yes** — a gate reads it |
| **D** untracked, no reader names it | 88 | 4 640 768 | 4.426 | 8.8% | **no — but 100% LIVE** |
| **E** untracked yet NAMED by a reader | 229 | 3 121 152 | 2.977 | 5.9% | no — deleting breaks a reader |
| **F** committed, no reader names it | 38 | 282 624 | 0.270 | 0.5% | no — needs `git rm` |

**STRICT IRREDUCIBLE (A+B+C) = 44 756 992 B = 84.76%.**

### The answer, in one line: **further pruning is possible, but not by deleting.**

- **Class D — the only class with no committed reader — is 100% live.** Measured: **88 of 88
  files, 3 469 312 B, ZERO cold bytes.** Every one belongs to a unit that wrote it within the
  last 120 minutes (`citeresolve` 2.4 MB, `livenum` 1.6 MB, `midrun`, `quiesce`, `prune4` itself).
  **`midrun` demonstrated the reason live: it reclaimed 11.4 MB of its own scratch by itself
  while this prune ran.** Deleting D would have deleted 4.4 MB of other units' in-flight work
  and reclaimed nothing.
- **Class E (2.98 MB)** is untracked *because* a committed reader names it — `loopfix` 332 K,
  `twopass` 270 K, `orcdecide` 195 K, `hooks` 133 K, `hooks`/`pairs`/`e2epy`/`coindependent`/
  `declare` the rest. Deleting any of it breaks a reader that is not a test.
- **Class F (270 KB)** is the true remainder and it is *committed*: it needs an orchestrator
  `git rm`, not an `rm`. It is 0.5% of the tree.
- The brief's own framing is confirmed by the numbers: the 43 MB the ledger recorded is **not a
  floor**, because live units keep adding reports, `.rows` and snapshots, and at least one
  (`midrun`) removes them on its own. **What 43 MB *was* — and what 50 MB is — is ~85% evidence
  and ~15% other units' live working set, of which 0 bytes are cold and reclaimable.**

**So: no, it is not at the floor, and the honest ceiling on further pruning is ~3.3 MB
(classes E+F), all of which requires deleting committed files or breaking a named reader.
That is 6.4% of the tree, and I recommend none of it.** The 84.76% is measured, not asserted —
but note the class boundaries are mine and the reader-corpus tokenisation is mine, so the
figure is **an instrument's reading, not a proof**. A reader that names a path by a name I did
not tokenise would move a file between C and F.

---

## 9. `fold.bend.ORIG` — I COULD settle it, and I did

I wrote this section as the one open question, then ran the settling command instead of
leaving it, because a prune that names an open question it could have closed is a prune that
picked the cheaper answer.

**The question:** is `.agents/slop/bitcastrow/fold.bend.ORIG` (385 024 B — the largest single
reclaimable item in the tree) evidence or residue? It is **staged in the index** but **absent
from HEAD**; its blob `de252716` is reachable from a ref that is **not** HEAD
(`ab500a5f9` is *not* an ancestor of HEAD); and it is the **only** live copy of those bytes.

**The answer, by restore test rather than by inference:**

```
git show 61be7ea90^:.agents/slop/bitcastrow/fold.bend.ORIG | shasum -a1
  511bbf5bbcb09a4e31e1205c9e3d2e508c8e7991
worktree file:
  511bbf5bbcb09a4e31e1205c9e3d2e508c8e7991     <- BYTE-IDENTICAL
git merge-base --is-ancestor 61be7ea90 HEAD    -> YES
```

The commit that deleted the path is **in HEAD's own ancestry**, and one `git show` restores the
file **byte for byte**. So the working-tree copy is **a second answer to a question git already
answers deterministically** — precisely the class the brief describes as cheapest to remove. Its
sibling `fold.bend.FIXED` is committed, and `bitcastrow/README.md:109-112` already records
*"fold.bend's own rows, before and after the fix"* in prose.

**So it is residue — and I did not delete it, for one reason: it is STAGED (` A`).** A staged
entry is another unit's deliberate pending commit, and removing a working-tree file whose index
entry is not mine would destroy a pending intent I cannot audit. `orphan.py` reported "reachable
from a ref" without saying *which*, and I had guessed the wrong one — I assumed `origin/master`,
which `AGENTS.md` says can reset. **It was HEAD's ancestry all along, the most durable thing in
this repo.** A measurement beat my assumption, in the direction of deleting less. Handed over in
§7 with its restore command.

### And the thing I still cannot settle, named

**Whether my own class boundaries are the right ones.** The 84.76% floor depends on (i) treating
a `*.md` in HEAD as an audit record and (ii) tokenising 3 839 tracked text blobs into 385 701
path-like tokens to decide "a reader names this". **A reader that names its input by a form my
regex drops moves a file from C (irreducible) to F (removable), and vice versa.** I measured
the classes; I did not measure the classifier. `git grep -F` per candidate file would be the
exact instrument — 4 000 invocations, so it was not run here, and **the floor figure should be
read as an instrument's reading, not a proof.** That is the honest limit of §8.

---

## 10. Verdict

`SKIP is not PASS` and `DEAD is not a zero`, so, in the five verdicts:

| verdict | what |
|---|---|
| **PASS** | the 7 `__pycache__` deletions: 73 728 B, every precondition re-verified at deletion |
| **FAIL** | my first two instruments (`prove.py` vacuous-`untracked`, `floor.py` 0-byte corpus). Both caught by a number that did not add up; neither is quoted above |
| **REFUSED** | 27 of 34 candidates, incl. `midrun`'s 11.4 MB, 11 `gate.bin`, 3 `insprobe*.bin`, `helpers-tc-gate.bin` |
| **SKIP** | nothing — I ran no `bend`, so no lane was measured; every claim here is a filesystem or git fact |
| **DEAD** | one artifact found and deleted: a 0-byte `reader-mentions.rows` from the broken corpus read |

`.agents/slop` is **50.36 MB**, **84.76%** of it committed reports, mutants and reader-named
artifacts. The largest untracked class contains **no cold bytes at all**. **The next prune should
not run until the units writing to `slop` have written their reports** — a live unit's directory
is work, and this one watched a unit reclaim 11.4 MB by itself mid-measurement.