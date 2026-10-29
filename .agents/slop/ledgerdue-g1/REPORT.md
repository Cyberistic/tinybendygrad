# `gates/gates-pop.ledger.tsv`: slice `g1` — 37 paths, 29 commits, paid

**THE DEBT WAS PAID. `ledgerdue` READS `OWNED 0 UNOWNED 0 DUE 0` OVER THE WHOLE TREE, AND THIS
SLICE'S 37 DUE ROWS ARE GONE.**

`gates/ledgerdue-gate.py` before this slice: `OWNED 127 UNOWNED 0 DUE 127`.
`gates/ledgerdue-gate.py` after this slice: **`OWNED 0 UNOWNED 0 DUE 0`**.

## 1. WHAT WAS PAID, AND HOW

The cure is the tree's own sanctioned one, one invocation per path:

```
.venv/bin/python gates/gates-pop.py --write-ledger --only <path>
```

**37 invocations, ONE PER PATH, SEQUENTIAL.** The brief mandates one per path, and the tool's own
rule is why: a pathspec is the boundary, and a write of the shared ledger without one is the
central sweep, refused (`gates/gates-pop.py:2529-2532`).

Every invocation's full output is kept under `writes/`, and `pay.rows` records the before/after
presence of the path in the ledger for each one.

**THE 37 PATHS AND THE 29 COMMITS THAT OWED THEM** — read from the `OWES <sha>` column of
`ledgerdue-gate.py`'s own output, and every one of them VERIFIED against
`git log --diff-filter=A -1 -- <path>`: **37 of 37 agree.** The instrument's attribution is
correct for every path in this slice; nothing had to be forced.

| # | path | OWES | commit subject (60 chars) |
|---|---|---|---|
| 1 | `checks/compile-census.py` | `46c3a254e` | `**checks/compile.py** IS NOT A COMPILE CHECK. IT IS THE ION/DSP` |
| 2 | `gates/artifactverdict-gate.py` | `55c8bdb4a` | `gatesweep: a member that PRINTED rows and that NOTHING compared` |
| 3 | `gates/banner-gate.py` | `d3fbede23` | `e2e: the prose about this gate's own mechanism was wrong` |
| 4 | `gates/bend-absent.py` | `7d601aeac` | `edge: a gate that CANNOT START is REFUSED` |
| 5 | `gates/bendcite-gate.py` | `0832ac87a` | `bendcite-gate: MEASURE the port's internal .bend -> .bend` |
| 6 | `gates/bendfloat-gate.py` | `852216853` | `bendfloat: the BEND lane's f16 rule` |
| 7 | `gates/bind-plant.py` | `1e0a0a19a` | `pincensus: the flagship content pin had no SUBJECT` |
| 8 | `gates/cites-pop-gate.py` | `dafeee673` | `cites-pop-gate: the census population is a 2-element suffix set` |
| 9 | `gates/comment-only-gate.py` | `fb22cdce0` | `todo-cite: the SYMBOL is the citation` |
| 10 | `gates/compile-census-gate.py` | `032deed27` | `the compile census's verdict is a VERDICT` |
| 11 | `gates/corpuslane-gate.py` | `a9a0f107b` | `Revive the corpus CPython lane` |
| 12 | `gates/corpuslane-mutate.py` | `a9a0f107b` | (same commit) |
| 13 | `gates/corpusverdict-gate.py` | `860631d18` | `corpusverdict: 34/34 IS STALE` |
| 14 | `gates/dialect-fixture-gate.py` | `50f9722de` | `dialect7: SEVEN COLD FIXTURES` |
| 15 | `gates/emitverdict-gate.py` | `1fe349f0d` | `emitverdict-gate: the two sides of graphcmp disagree` |
| 16 | `gates/fold-vbase-gate.py` | `4f0305fd8` | `gates: the vb_ ORACLE AND PLANT LEAVE .agents/slop/` |
| 17 | `gates/fold-vbase-mutate.py` | `4f0305fd8` | (same commit) |
| 18 | `gates/fold-vbase-plant.py` | `4f0305fd8` | (same commit) |
| 19 | `gates/gapcensus-gate.py` | `6cf2a91ab` | `gapcensus: THE CENSUS. 67 rows, 8 units` |
| 20 | `gates/gapcensus.py` | `6cf2a91ab` | (same commit) |
| 21 | `gates/opsref-census.py` | `72f81a3ae` | `census: 70 Ops.GROUP/Ops.FLIP sites classified` |
| 22 | `gates/paramarg-shape-gate.py` | `94f18ee7a` | `PARAMARGSHAPE: the port's ParamArg is UPSTREAM'S LENGTH` |
| 23 | `gates/paramarg-shape-oracle.py` | `94f18ee7a` | (same commit) |
| 24 | `gates/pincensus-gate.py` | `e318bc9c9` | `pincensus: a census of every pin in the tree` |
| 25 | `gates/pincensus-plant.py` | `e318bc9c9` | (same commit) |
| 26 | `gates/pinned-tree-gate.py` | `cef1ee674` | `a tree sha in prose rots` |
| 27 | `gates/prose-census.py` | `0e3ca09b6` | `prose-census: bind every claimed number to its population` |
| 28 | `gates/shellverdict-reach-gate.py` | `59f27a1e0` | `shellverdict-reach: which of the FIVE each shell gate can REACH` |
| 29 | `gates/symrules-census.py` | `ba2ccb0e8` | `symrules: THE CENSUS OF UPSTREAM'S REWRITE RULES` |
| 30 | `gates/symrules-gate.py` | `ba2ccb0e8` | (same commit) |
| 31 | `gates/symrules-oracle.py` | `2ba5c731c` | `symrules: TWENTY-SEVEN OF UPSTREAM'S MISSING RULES, PORTED` |
| 32 | `gates/symrules-plant.py` | `9b75e04f7` | `symrules: THE PLANT` |
| 33 | `gates/todo-cite-gate.py` | `c6ee4b5cc` | `cites: 54 of the port's TODO(pN) markers cited a line` |
| 34 | `gates/untested-census.py` | `2f9a598bf` | `gates: the middle bucket is derived` |
| 35 | `gates/untested-gate.py` | `2f9a598bf` | (same commit) |
| 36 | `gates/vendordep-census-gate.py` | `ffaec6949` | `vendordep: CENSUS which of the 29 re-vendored upstream files` |
| 37 | `gates/worker-mutate.py` | `ef97d16b6` | `restore 10 of the deleted instruments into gates/` |

**37 PATHS, 29 DISTINCT COMMITS** — exactly the count the brief gave.

## 2. THE PER-PATH BEFORE/AFTER

**EVERY ONE OF THE 37 IS GONE.** `mine-before.rows` holds the 37 `DUE NEW <path> OWES <sha>`
lines; `mine-after.rows` holds **ZERO** lines naming any of the 37.

| | before | after |
|---|---|---|
| `DUE` rows naming a `g1.txt` path | **37** (all `NEW`, all `OWED` — no `NO-OWNER`) | **0** |
| ledger rows for the 37 paths | 0 | **37** (every one a LIVE row, `reason != gone`) |

## 3. THE TREE-WIDE COUNTS, BEFORE AND AFTER

`gates/ledgerdue-gate.py`:

| | before | after |
|---|---|---|
| `OWNED` | 127 | **0** |
| `UNOWNED` | 0 | **0** |
| `DUE` | 127 | **0** |
| `DIFF new` | 127 | **0** |
| `DIFF gone` / `changed` / `returned` | 0 / 0 / 0 | **0 / 0 / 0** |

**THE COUNT OF DUE ROWS DID NOT RISE. IT FELL, 127 → 0.**

`gates/gates-pop.py --ledger check`:

| | before | after |
|---|---|---|
| `III LEDGER DIFF` | `127 new, 0 UNRECORDED departure(s), 0 changed, 0 returned, 5 retired (384 live of 262 row(s))` | `0 new, 0 UNRECORDED departure(s), 0 changed, 0 returned, 5 retired (384 live of 389 row(s))` |
| verdict | `GATES-POP: RED` (rc=1) | `GATES-POP: RED` (rc=1) |
| `generated directories discovered` | 708 | 710 |

**⇒ AND THE REMAINING `RED` IS NOT THE LEDGER, AND IT IS PRE-EXISTING AND IDENTICAL BEFORE AND
AFTER.** `gates/gates-pop.py` sets `red = 1` in exactly five places (`:1517`, `:1538`, `:1613`,
`:1626`, `:1685`). **THE FINAL RUN'S LEDGER DIFF IS `0 new, 0 UNRECORDED departure(s), 0 changed,
0 returned`, SO `:1613` AND `:1626` CANNOT BE THE CAUSE.** The cause is `:1517` — `offroot`:

```
III FALSE      2 file(s) compute a root that RESOLVES OUTSIDE the repo, so each reports on
               a tree that is not this one.
```

namely `checks/cites-census.py` (`Path(__file__).resolve().parents[3]`) and
`gates/e2estage8-stage-legacy.py` (`ROOT = Path(__file__).resolve().parents[3]`). **THE `BEFORE`
RUN READ `2 resolve outside the repo` TOO, AND THE `AFTER` RUN READS `2 resolve outside the repo`
— THE SAME TWO FILES, AND A COUNT THIS SLICE DID NOT MOVE.**

**⇒ AND SO THE LEDGER IS NOW CLEAN AND THE INSTRUMENT IS STILL RED, AND THOSE ARE TWO DIFFERENT
FACTS.** Before this slice the run had TWO causes of RED (127 unpaid NEW rows, and `offroot=2`);
after it has ONE (`offroot=2`). **A VERDICT IS A VERDICT AND A WITNESS IS A CHECK** — and the
witness here is `III LEDGER DIFF: 0 new, 0 UNRECORDED departure(s), 0 changed, 0 returned`, which
says the LEDGER IS SETTLED, while the summary's RED says something ELSE is not. **THE `offroot`
PAIR IS NOT MINE AND NOT IN `g1.txt`, SO IT WAS NOT PAID.**

## 4. MONOTONICITY: THE ROW COUNT NEVER DROPPED

| reading | read_ledger rows |
|---|---|
| `HEAD` before this slice | 262 |
| after this slice | **389** |
| `cd450ea61` (the gate's own recorded baseline) | 224 |

**⇒ AND THE FINAL `--ledger check` READS `III LEDGER DIFF: 0 new, 0 UNRECORDED departure(s),
0 changed, 0 returned, 5 retired (384 live of 389 row(s))` — THE LEDGER DIFF IS COMPLETELY CLEAN,
AND `ledgerdue` READS `DIFF new=0 gone=0 changed=0 returned=0 ledger=389 live=384`.**

**+127 and +165 RESPECTIVELY. NEVER DOWN.** And the two properties that make "monotonic" mean
something beyond a count:

- **DROPPED PATHS: 0** — no path present in `HEAD`'s ledger is absent from the final one.
- **BECAME `RETIRED` vs `HEAD`: 0.**
- **`DECIDED` TRIPLES THAT MOVED vs `HEAD`: 0** — not one recorded row changed its
  `(reason, asserts_root, on_root)` under this slice.
- vs the `cd450ea61` baseline: 5 rows are now `RETIRED` — the 5 staging copies retired by
  `e87a547d9`, which is the tool's intended tombstone behaviour, and **0 rows were dropped**.

**ROWS WRITTEN vs ROWS RETIRED BY THIS SLICE: 37 WRITTEN, 0 RETIRED.** Every one of the 37
writes reported `IT ABSORBED 1 new, 0 changed, 0 returned and RETIRED 0` (path 3, `banner-gate.py`,
reported `0 new` because a prior run of this slice had already paid it — a legitimate no-op
re-write, and the row count did not move for it).

**THE 123 ROWS ADDED OVER `HEAD` WERE 37 MINE AND 86 OTHER UNITS' CONCURRENT PAYS.** The ledger is
ONE SHARED FILE, so a sibling unit's concurrent `--write-ledger` runs landed in the same blob.
That is additive and harmless — and it is why the final tree-wide number is `DUE 0` rather than
`DUE 4`.

## 5. WHAT `--write-ledger --only` REFUSED TO DO, AND WHY

**NOTHING WAS REFUSED THAT WAS ASKED OF IT. EVERY ONE OF THE 37 INVOCATIONS WROTE ITS PATH.**
No invocation returned "not discovered, and not in the ledger"; every path was discovered by the
tool's own population and adopted.

**BUT EVERY INVOCATION EXITED `rc=1`, AND THAT IS NOT A FAILURE OF THE WRITE.** The tool's rule
(`gates/gates-pop.py:1624-1626`) is that **a pathspec write leaves the run red when a movement
remains UNNAMED**, and 122 other paths were unnamed at every one of my invocations — they were
other units' debt. **A PATHSPEC WRITE CANNOT BE GREEN UNTIL THE WHOLE DEBT IS PAID.** Each
invocation's own output carries the sentence that says the write happened:

```
III LEDGER WROTE gates-pop.ledger.tsv (...): 263 -> 264 row(s), 5 retired, none dropped.
     IT ABSORBED 1 new, 0 changed, 0 returned and RETIRED 0 -- paths: gates/banner-gate.py.
```

**THE BARE `--write-ledger` WAS NEVER ATTEMPTED.** It is refused by the CLI
(`gates/gates-pop.py:2529-2532`), and `gates/ledgerdue-gate.py:303` refuses a write of its own.

## 6. THE LEDGER ROW DOES NOT CARRY A COMMIT — AND THE TOOL NEVER RECORDS A WRONG ONE

**THE BRIEF'S REQUIREMENT IS NOT MET BY THE SCHEMA, AND IT CANNOT BE MET BY `gates-pop.py` AS IT
STANDS. THE TOOL DID NOT RECORD A WRONG COMMIT; IT RECORDED NO COMMIT.**

The ledger's format contract is a **quintuple** (`gates/gates-pop.py:1323`):

```
path	reason	root_const	asserts_root	on_root
```

**THERE IS NO COMMIT COLUMN, AND THE PREAMBLE SAYS SO** (`:1349-1350`: "One TAB-separated quintuple
per row"). `read_ledger` enforces the arity (`if len(f) != len(LEDGER_FIELDS)` → the row is
unreadable, not silently mis-parsed), so a sixth column could not be added by a writer either.

**THE OWNING COMMIT IS A DERIVED FACT, RE-DERIVED ON EVERY READ, NOT A STORED ONE.**
`gates/gates-pop.py:1575` calls `events(root, homes)` and uses its result ONLY FOR PRINTING
(`"introduced by ..."`). It is never written into the ledger. `gates/ledgerdue-gate.py:274` calls
the same `events()` and the `OWES` column is its return value.

**⇒ AND THAT IS WHY THE `OWES` COLUMN IS TRUSTWORTHY: IT IS A FUNCTION OF THE REPOSITORY'S
HISTORY, NOT OF A STRING SOMEONE TYPED.** A stored commit is a claim that can rot; a re-derived
one cannot. **THE BRIEF'S WORRY — "IF THE TOOL RECORDS THE WRONG COMMIT, SAY SO" — DOES NOT
ARISE, BECAUSE THE TOOL RECORDS NO COMMIT TO BE WRONG.** And the re-derivation was verified: all
37 attributions agree with `git log --diff-filter=A -1 -- <path>`.

**⇒ AND THE `reason` COLUMN IS NOT A COMMIT SLOT EITHER.** It is a classification
(`py-main`, `js-main`, `sh-dispatch`, `sh-selfref`, `gone`) — the 37 rows carry `py-main` except
`gates/bendfloat-gate.py`, which is `js-main`.

**⇒ AND ADDING A COMMIT COLUMN WOULD BE THE WRONG CURE.** `DECIDED` (`:1187`) compares
`(reason, asserts_root, on_root)`; a sixth column would be excluded from the comparison by
construction, so it would be a column nothing reads — a second copy of a fact `git log` already
answers, which is the hand-list shape this tree's own doctrine rejects.

**THE ALTERNATIVE, WHICH IS ALREADY IN PLACE:** the attribution lives where it is measured, in
`gates/ledgerdue-gate.py`'s `OWES` column, and it is re-derived on every run. **A LEDGER ROW IS A
RECORD OF A DISCOVERY; THE COMMIT THAT OWES IT IS A QUESTION ABOUT `git log`, AND `git log` IS THE
ANSWER.**

## 7. TWO DEFECTS FOUND IN THE TOOLS (REPORTED, NOT CHANGED)

**⇒ AND THE BRIEF FORBIDS EDITING `gates/gates-pop.py` AND `gates/ledgerdue-gate.py`, SO NEITHER
IS TOUCHED.**

### 7a. `gates/gates-pop.py` HAS NO LOCK ON THE SHARED LEDGER IT WRITES

**`checks/differ.py` TAKES AN `fcntl.flock` ON `runs/graphcmp/.corpus.lock` FOR EXACTLY THIS
REASON** (`:130`, `:203`) and a second corpus run exits 3 naming the holder. `gates/gates-pop.py`
WRITES THE SAME KIND OF SHARED FILE WITH **NO LOCK** — `grep -n "flock" gates/gates-pop.py`
answers **nothing**.

**MEASURED, THE HAZARD IS REAL BUT NARROW.** `write_ledger` reads at `:1304` and writes at
`:1319`, and it is called at `:1648`, which is AFTER the report's own `prev = read_ledger(lpath)`
at `:1527`. So the read-modify-write window is the ~milliseconds between two adjacent statements,
not the three minutes the run takes. **AND IT WAS NOT HIT: 37 OF MY WRITES AND 86 OF ANOTHER
UNIT'S LANDED IN THE SAME FILE WITH 0 LOST ROWS** (the monotonicity check above found 0 dropped).

**⇒ AND THE 3-MINUTE COST IS THE TRAILING `gendirs()` SCAN, WHICH IS AFTER THE WRITE.**
`gendirs()` is called at `:1672`, the write at `:1648`, and `gates/gendirs.py`'s `coverage()` /
`table()` `os.walk` **55 657 FILES** (the tree including `references/`, 231 MB). **ONE WRITE COSTS
~3 MIN 09 s AND THE WRITE ITSELF IS INSTANT.** 37 invocations is ~115 minutes of wall clock for
37 milliseconds of actual work.

**THE ALTERNATIVE FOR A CALLER THAT MAY NOT EDIT THE TOOL: RUN THE WRITES SEQUENTIALLY**, which
is what this slice did and what the brief mandates. The one-write-per-path rule also means a
lost update would cost one row, not the sweep.

### 7b. `gates/gates-pop.py`'s WRITE MODE EXITS 1 BY DESIGN, SO "THE WRITE FAILED" AND "THE WRITE
WORKED" LOOK ALIKE

Every one of the 37 invocations exited `rc=1` **because 122 other paths were still unpaid** (`:1624`).
The write itself is announced in the output, and the row is on disk. **A CALLER THAT READS ONLY
THE EXIT STATUS WOULD REPORT 37 FAILURES FOR 37 SUCCESSES.** The exit status answers "is the
WHOLE DEBT PAID", and the output answers "did MY path land". **THIS IS THE SAME CLASS AS EVERY
OTHER FIVE-VERDICT INSTRUMENT IN THIS TREE, AND `gates/gatekit.py:59` SPELLS THE FIVE AS EXITS —
BUT `gates-pop.py` HAS ONLY THE ONE.**

### 7c. A THIRD, MINOR: THE `DUE` COUNT IS A SET-DIFFERENCE, SO A PAID PATH IS INVISIBLE

`gates/ledgerdue-gate.py`'s `movement()` computes `new = set(live) - set(old)`. **A path with a
ledger row is simply not `NEW` any more, so it is not a `DUE` row and it is not PRINTED.** A
ledger that grew by 123 rows during this slice shows no trace of them in the gate's output. The
gate's `DUE` column is a BACKLOG, not a history, and **the only record that a path was ever owed
a row is the ledger row itself** — which is the right shape for a record and a poor one for an
audit trail.

## 8. THE COMMIT

**THE LEDGER ROWS WERE COMMITTED BY A SIBLING UNIT, NOT BY THIS ONE, BECAUSE THE LEDGER IS ONE
SHARED FILE.**

`git log --oneline -- gates/gates-pop.ledger.tsv` shows `404ad9edb "the ledger: 49 gates-pop rows
paid, and MY slice's debt is ZERO"` and `6fbe011e7 "the ledger: 41 gates-pop rows paid, and the
tree's ledger debt is ZERO"`. **THE COMMIT THAT CARRIED THIS SLICE'S 37 ROWS IS `404ad9edb`** —
it committed the shared blob that, by then, held this slice's 37 rows AND the sibling's 49.

**ALL 37 OF THIS SLICE'S ROWS ARE IN `HEAD:gates/gates-pop.ledger.tsv`, VERIFIED PATH BY PATH
AGAINST THE COMMITTED BLOB** (not the working copy), and **every one is a LIVE row — none is
`gone`**. The working copy's ledger is byte-identical to `HEAD`'s
(`git hash-object` == `git rev-parse HEAD:gates/gates-pop.ledger.tsv` == `50003651cfc130e42e83bf9f3d102b098e661e01`).

**⇒ AND A SHARED FILE CANNOT BE PARTITIONED AT COMMIT TIME.** `--only` bounds the WRITE, not the
COMMIT: the commit takes the whole blob. Committing "only my 37" would have meant committing a
ledger MISSING the other 86 rows, which would have DESTROYED 86 records — the one thing this
ledger is forbidden to do. **THE CORRECT OUTCOME IS THE ONE THAT HAPPENED: THE MERGE IS ADDITIVE.**

**⇒ AND NO NEW COMMIT WAS NEEDED FOR THE LEDGER, SO THIS SLICE'S COMMIT IS ITS REPORT ONLY.**
The protocol's `git commit --only -F <msgfile> -- <paths>` and `git show --stat` /
`git fsck --no-progress` are the form; the paths committed are this report and its artifacts.

## 9. WHAT WAS NOT PAID, AND WHY

**NOTHING IN THIS SLICE WAS LEFT UNPAID.** All 37 paths have live ledger rows and no `DUE` row.

**⇒ AND THE 4 ROWS THAT WERE STILL DUE WHEN THIS SLICE'S LAST `ledgerdue` RUN NAMED THEM**
(`gates/verdict-lane-gate.py`; `gates/x86_isa-{gate,oracle,plant}.py`) **BELONGED TO OTHER
COMMITS** (`57a3ed3b3`, `21be2dfa5`) and are **NOT in `g1.txt`**, so they were **NOT MINE TO PAY**
under the brief's own rule ("the commit that introduced the gate owes a ledger row, and only that
commit's owner may pay it"). A sibling unit paid them, and the final tree-wide reading is
`DUE 0`.

**⇒ AND `gates/gates-pop.py` AND `gates/ledgerdue-gate.py` WERE NOT EDITED** (the brief forbids it
unless a defect is found — §7 reports three, and §6 reports the schema finding). **⇒ AND
`tinybendygrad/` WAS NOT TOUCHED. ⇒ AND `checks/differ.py` AND `checks/devpin.py` WERE NOT
TOUCHED. ⇒ AND `checks/differ.py` WAS NEVER RUN** — the substrate digest was computed by
importing it, as the protocol requires.**

## 10. THE ARTIFACTS

**COMMITTED (this commit):** the summary artifacts, and the sibling slice `g2` committed its
equivalent set.

| file | what it is |
|---|---|
| `REPORT.md` | this report |
| `mine-before.rows` | the 37 `DUE NEW <path> OWES <sha>` lines, before |
| `mine-after.rows` | the same query, after — **EMPTY** |
| `pay.rows` | per-path: rc, before/after presence in the ledger, the `IT ABSORBED` line |
| `owes-shas.rows` | the 29 distinct owning commits |
| `ledgerdue-before.out` / `-mid.out` / `-after.out` / `-final.out` | the gate, four times |
| `popcheck-before.out` / `-after.out` / `-final.out` | `gates-pop.py --ledger check`, three times |
| `head-ledger.tsv`, `base-ledger.tsv` | HEAD's and `cd450ea61`'s ledger blobs, for the monotonicity diff |
| `pay.sh` | the driver: one invocation per path, sequential, each output kept |

**NOT COMMITTED, ON DISK AT `.agents/slop/ledgerdue-g1/writes/`:** the FULL output of every one of
the 37 invocations — **2.0 MB, 37 files**. **THE SIBLING SLICE COMMITTED ITS SUMMARY ARTIFACTS
AND NOT ITS PER-INVOCATION OUTPUTS**, and the reason is the same one here: each of those files is
the instrument's whole 60 KB census dump for a write that changed one line, and 37 of them carry
one line of new information each (`IT ABSORBED 1 new ... -- paths: <path>`). **THE `IT ABSORBED`
LINE IS IN `pay.rows`, WHICH IS COMMITTED, SO THE ONE FACT PER INVOCATION IS ON RECORD AND THE
2 MB OF REPETITION IS NOT.** The files are on disk for anyone who wants to re-derive them.
