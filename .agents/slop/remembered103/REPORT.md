# remembered103 — one superseded number, and the witness the handoff named was the wrong line

**SUBJECT**: the sentence at `checks/differ.py` that named the size of `differ.declared()` — the
excused graphcmp `.txt` set — as `103`. **The live line is `245`, not `243`** (the handoff, and
`.agents/slop/notxt139/REPORT.md:23`, both cite `243`; the file grew two lines after that snapshot,
and the fixture copies below still carry `243`). Measured 2026-10-06, `.venv/bin/python`.

## 1. What the sentence CLAIMS

```
# THE ARTIFACT NAMES ARE AN OUTPUT CONTRACT, NOT CONSTANTS, and this is the declaration of it.
# `oracle-run.sh` writes all 103 and reads twelve of them by name in its own summary block;
# `oracle-repro.sh` reads one by name (`:61`) and globs five families (`:105`, `:114`); this file
# reads twelve by name and globs the rest; `checks/corpus-figure.py:72` reads `D0-run-summary.txt`
# ...
LITERALS = (...)   # 251-253, then REPORTS, then:
def declared() -> set[str]:   # 260  "Every `.txt` artifact `cmd_run` writes"
```

It is **a count of the declared set**, present tense — *"`oracle-run.sh` writes all N"* where N is
the population `declared()` owns. It is **not** historical tense and **not** a different population.
`checks/README.md:53` (pre-fix) used the identical number for the identical set — *"carves out
exactly the 103 names `differ.declared()` returns"* — and `checks/no-txt.py` excuses exactly that
set. **Three witnesses, one population.**

## 2. Verdict: (a) a stale literal of THIS population — and its true value is not 139 either

`103` was **correct when written**. `git log -S 'writes all 103'` pins its introduction to
`41fbd8793` (2026-10-05 23:33). At that commit `declared()` iterated **`WANT`** — the 16-name table
— so it returned `13 LITERALS + 4×16 graphs + 5 controls + 7 plants + 4 D6 + 10 STAB = 103`, and the
sentence told the truth. Commit **`924990af5`** (2026-10-06 00:34) rewrote `declared()` to iterate
**`corpus()`** (`differ.py:276`, `graphs = corpus()`), which today is **34 graphs** — so the number
moved out from under the sentence without anyone editing it.

**The task's premise is itself a superseded witness.** The handoff says *"THE TRUE VALUE HAS BEEN
139 ALL SESSION."* **No: 139 was true only for the 25-graph corpus.** `3ae870111` (2026-10-06
14:09:59, `buffergraphs`) grew the corpus to 34, and a `declared()` over 34 graphs is
`13 + 4×34 + 5 + 7 + 4 + 10 = **175**` (measured). `139` is the **on-disk** count
`runs/graphcmp/D` still holds from the last 25-graph run — the number `no-txt.py` prints as
EXCUSED, because it intersects the declaration with what exists. So three values are all "right for
a subject": **103** = declared() at the 16-graph `WANT` era, **139** = declared() at 25 graphs (and
what is on disk now), **175** = declared() now. Writing either literal back in would plant a fresh
stale number on the next corpus move.

## 3. The fix — defer to the generator, never type the count

```diff
-# `oracle-run.sh` writes all 103 and reads twelve of them by name in its own summary block;
+# `oracle-run.sh` writes all `declared()` names and reads twelve of them by name in its own
+# summary block;
```

This is the shape `checks/no-txt.py:20-22` already argues for one file over: *"a number in this
docstring is a second witness to a set one function already owns."* The count is now whatever the
one owner says.

- `checks/differ.py` sha256 **before** `5808bb3c25d16075675bebd71c2527e020126c13c6d1629a4ea06f9222d5bdaf`
- `checks/differ.py` sha256 **after**  `e88753d952fcad675a3f8b8c3356f2102a49fdb02240053005773e066ed7e468`

## 4. PLANT IT — a derived number that cannot move is a literal wearing a function's name

`.agents/slop/remembered103/plant.py` edits `declared()`'s source in place (`corpus()[:30]`, four
fewer graphs), re-reads it, then restores the exact bytes and asserts the restore by sha256:

```
HASH before plant : e88753d952fcad675a3f8b8c3356f2102a49fdb02240053005773e066ed7e468
len(declared())   : 175
PLANTED (corpus[:30]) len(declared()): 159     # 4 graphs × 4 names
HASH after revert : e88753d952fcad675a3f8b8c3356f2102a49fdb02240053005773e066ed7e468 (RESTORED)
```

`175 → 159 → 175`, hash restored. The number **moves with the set it names**, so the sentence now
tracks it. (`159 = 175 − 16`; each graph contributes `D1-graph`, `D2-canon-py`, `D2-canon-bend`,
`D2-cmp`.)

## 5. Census — every REMAINING `103`, and the denominator

`.agents/slop/remembered103/census.py` walks the tree (excluding `.git`, `.jj`, `references`,
`.venv`, upstream `tinygrad/` pruned into its own bucket), one line per `\b103\b`, into raw
`.agents/slop/remembered103/census.out`.

| bucket | count |
|---|---|
| **ABOUT THIS POPULATION** (`declared()`/graphcmp `.txt` size) | **49** |
| ├─ live source/docs | **0**  ← the defect is gone from the live tree |
| ├─ fixture snapshots (copies of `differ.py` inside a slop plant tree) | 10 |
| └─ records / ledgers / reports | 39 |
| UNRELATED, owned (line numbers, byte offsets, shared-row counts, enum members, oracle values) | 762 |
| UNRELATED, vendored upstream `tinygrad/` (autogen enums, byte offsets) | 74 |
| BINARY files merely containing the bytes `103` (e2e sandbox `node`, `.jj` op store) | 466 |
| **TOTAL `\b103\b` occurrences walked** | **1351** |

**False positives the classifier took, and why they are NOT this defect** (the reason a token sweep
grows a false census): `.agents/slop/sloptxt/PLAN.tsv:{162,300,456}` and
`.agents/slop/declared473/counts.tsv:241` — a `differ.py:103` **line number** inside a path;
`.agents/slop/declared472/contract-test-after.out:8` — a traceback path; `.agents/slop/emptyblob/*`
— a line number; `oracles/**` and `oracles259/MANIFEST.tsv:37` — **byte offsets / row values**;
`TODO.md`'s `94 → 103` — the **shared-row** count, a different population entirely;
`.agents/slop/staleruns/…:87` — `103 .txt` removed from **`.agents/runs/`**, yet another `.txt`
population.

**Missed by the keyword heuristic** (no `declared`/`graphcmp`/`.txt` on the line) but **are** this
population, and are reported rather than edited:

- `AGENTS.md:96` — *"THE `103` WAS FIXED IN BOTH WITNESSES … so only this file still needs it moved
  off `103`"* and `AGENTS.md:99` — *"moved off `103`"*. **Off-limits to this unit** (do-not-touch).
  These are prose *about* the stale number and are themselves now stale (differ.py is fixed).
- `.agents/TODO.md:10` — *"(103, then 139 after another unit rewrote `cmd_run`)"*.

**The records that still say `103` — historical narrative, in `.agents/slop/` and the ledgers, none
live source:** `.agents/TODO.md:{12794,12802,12803,13629}`, `.agents/TOOLS.md:1481`,
`.agents/slop/{sweepport/REPORT.md:120, txtgen/REPORT.md:85, txtgen/declared-completeness.py:5,
txtgen/orphan-plant.py:13, want/DECISION.md:129, todo2/{dashboard.md:153,sections.tsv:174,
discover.md:307}, notxt139/REPORT.md:{14,15,16,17,19,20,23,77}, difftxt/DECISION.md:{1,13,18,19,90,97},
difftxt/inventory.out:{1,4,15}, agend/REPORT.md:{191,307}}`. They describe the migration
(`103 → 139 → 175`) and are correct as records of a past reading.

**The 10 fixture snapshots** carry the un-fixed sentence because they are *test inputs*, not the
tree's source: `.agents/slop/{figure2/plant/{broken,real}, corpuswire/tree, declared473/tree/{t1,t2}}
/checks/differ.py:245`, `corpuswire/tree/checks/differ_wantdummy.py:246`,
`figurefix/plant/scratch/checks/differ.py:243`, `notxt139/differ.py.orig:243`. Editing a fixture
would corrupt another unit's plant.

## 6. `checks/no-txt.py`, before and after

```
BEFORE (pre-edit, 2026-10-06)          AFTER (post-edit)
  139 `.txt` EXCUSED                      139 `.txt` EXCUSED
   24 .txt FILE(S)                         24 .txt FILE(S)      rc=1 both
```

Unchanged, exactly as expected: the edit is prose, `declared()` returns the same set, and the
EXCUSED count is `|on-disk ∩ declared()| = 139` (the 175-name declaration minus 36 names for the 9
graphs the last run never wrote). **The reading carries its own date: the tree is moving** (other
units were writing during this walk; the total moved 1084 → 1087 → 1351 between passes).

## Reproduction

```
.venv/bin/python .agents/slop/remembered103/plant.py     # 175 → 159 → 175, hash-restored
.venv/bin/python .agents/slop/remembered103/census.py    # denominator + every `103`, classified
.venv/bin/python checks/no-txt.py                        # 139 EXCUSED / 24 hard, rc=1
```
