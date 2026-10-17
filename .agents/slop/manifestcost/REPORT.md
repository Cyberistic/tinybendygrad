# MANIFESTCOST — WHICH FILE MOVED, ANSWERABLE, AND WHAT IT COSTS

Read 2026-10-17. Every number below is ONE reading of the live tree unless it carries a
`MEASURED` timestamp or says it is a frozen copy. The tree moves under other units: the live
writer digest went `be6874cab3df` (10:20Z) → `454e85956b37` (00:34Z) during this session, so an
unsigned digest in this report would be a claim about nothing.

**DELIVERABLE:** `checks/substrate-manifest.py`, 581 lines / 298 statements, `ruff` clean,
`--plant` **28 of 28, rc=0**, sensitivity census **3 of 3 caught, 0 not applied**.

---

## 1. CAN YOU NAME EVERY DIFFERING MEMBER, OR DOES THE DIGEST COMPARE DIFFERENT POPULATIONS?

**Both answers are now reachable, and they are two different sentences.** A digest is a fold, so
`recorded != live` is ONE BIT over a population of 151 — a file edited, a file added and a file
deleted all print it identically. The manifest is the digest's own input, unfolded, so both cases
are decided:

| case | verdict | the sentence |
|---|---|---|
| same paths, different bytes | `FAIL` (1) | `1 of 151 member(s) differ -- the population is the same and these are the bytes that moved` + `MOVED <rel> recorded=<12> live=<12>` per member |
| the recorded paths ≠ the tree's paths | `FAIL` (1) | `THE DIGEST IS OVER A DIFFERENT POPULATION -- 151 recorded member(s) against 152 here` + `RECORDED-ONLY` / `TREE-ONLY` per path |
| a manifest that does not fold to the run's own recorded row | `REFUSED` (3) | `A MANIFEST FROM A DIFFERENT RUN` |
| no manifest | `REFUSED` (3) | `the run recorded a digest and 0 of 151 members per-path` |
| nothing moved | `PASS` (0) | `0 of 151 recorded member(s) differ` |

**MEASURED on the REAL 151 members, on a frozen copy** (all 151 declared members copied by asking
`differ.substrate_entries()`, the population discovered and never listed):

```
frozen: copied 151 of 151 declared members (+2 lanes)
UNMOVED                  rc=0  PASS: 0 of 151 recorded member(s) differ
ONE BYTE in that member  rc=1  FAIL: 1 of 151 member(s) differ
                              MOVED  tinybendygrad/helpers.bend  recorded=6195863c0622 live=58400dd04f95
PLUS one member          rc=1  FAIL: THE DIGEST IS OVER A DIFFERENT POPULATION -- 151 against 152
                              TREE-ONLY  tinybendygrad/zzz-new.bend
```

**THE NEGATIVE, AND IT IS THE POINT.** For the run that is actually recorded —
`substrate-end=5d3f31197e88` — this manifest **does not exist and cannot be reconstructed.** A
sha256 fold is many-to-one and the preimage space is every one of the `2^151` subsets of the
members' contents, so the recorded digest does not determine one byte of any member. There is no
recovery path, and there never will be. **The manifest must be written BY THE RUN, or the question
stays unanswerable for that run forever** — which is the same sentence that made a unit decline to
write a lane into `D/`.

**THE MANIFEST IS THE DIGEST, UNFOLDED.** `differ.substrate_digest()` (`differ.py:919`) folds
`relpath NUL sha256(bytes).hexdigest() NUL` over `sorted(substrate_entries())`. So the member rows
are not a second encoding of the digest — they are its input — and **`sha256(fold(rows)) == the
manifest's own `substrate=` header == the run's recorded `substrate-end`**, which is what makes a
stale manifest detectable. **MEASURED, live tree, 151 rows re-folded through this file's own code
against the writer's digest: `454e85956b37` == `454e85956b37`.**

## 2. WHAT IT COSTS, AND THE TRADE

`--cost`, **MEASURED 2026-10-17T00:35:45Z**:

```
members 151   rows written 153   bytes on disk 15164
digest 13.7 ms per pass, and the manifest adds no hashing: its rows ARE the
  digest's input, so a run that stamps it has already paid for the digest it is
  stamped with -- the marginal cost is the sort and the 15164 B write
against the 2 `substrate-` rows it accompanies: 153 rows where there were 2
```

**THE MARGINAL HASHING IS ZERO AND THAT IS THE WHOLE DEFENCE OF THE TRADE.** A run that stamps the
manifest has already called `substrate_entries()` to compute `substrate_start`. The rows are that
same list. So the price is one sort and one 15 KB write, not a second pass over 151 files.

**THE NOISE IS THE BUY, AND ITS SIZE IS MEASURED NOT ASSUMED.** Moving one member yields
**`1 of 151` differing rows**. So the common case is a one-row diff EITHER WAY — what changes is
that the row now **names a path**. The other 150 rows are identical and cost 15 KB.

**THE BRIEF's ARTEFACT MEASUREMENT IS A DIFFERENT POPULATION AND IS NOT THE SAME TRADE.** OF THE
**176** declared artefacts under `runs/graphcmp/D/` (`MEASURED` live: 242 files = **176**
declared-shape + **66** `.err`) exactly **1** changed across a substrate change. **That is 1 row
over 176 ARTEFACTS; the manifest is 151 rows over 151 MEMBERS.** They are not substitutes, and the
brief's framing invites the wrong comparison:

- the artefact row names a **symptom**. Knowing `D1-graph-matmul.txt` changed does not say whether
  `matmul.bend`, `graphcmp.bend` or `checks/devpin.py` caused it, and cannot: three members feed
  one artefact.
- the manifest row names the **cause**. Every artefact a symptom implicates is traceable to the
  members that produced it.

**WHEN THE MANIFEST IS A BAD TRADE, MEASURED.** The live substrate moved `be6874cab3df` →
`454e85956b37` inside this one session. When members are churning, a manifest reads `N of 151` with
a large `N` — strictly noisier than the digest pair's one bit. **But that is exactly the case the
run already refuses**: `differ.py:747` writes `substrate-start`/`substrate-end` and
`substrate_bad()` reports `THE SUBSTRATE MOVED WHILE THE RUN WAS IN FLIGHT`, so a manifest whose
`N` is large is never consulted for a verdict, only for a diagnosis after one. The noise is bounded
by the condition under which you stop reading it. **That is a structural argument, not a hope.**

## 3. THE DENOMINATOR, AND WHY IT MATCHES ITS NUMERATOR's SUBJECT

Every count is `len(writer.substrate_entries())` on the root being measured, **asked of
`checks/differ.py` and never re-derived here**: `stamp`, `diagnose`, `residual_noise` and
`--cost` all call `live()`, which is `sorted(w.substrate_entries())`. So the numerator ("0 of 151
recorded member(s) differ") counts **members of the writer's population** and the denominator (151)
is **the same list, read from the same call**. `runs/graphcmp/D/` is 176 artefacts, `tinybendygrad/`
is a directory walk, `checks/substrate-snapshot.py`'s `COPIES` is 153 — **none of them is this
instrument's denominator**, and using 153 would produce a manifest that cannot fold to the run's own
digest and would therefore be wrong by construction, not by rounding.

**TWO DENOMINATORS THAT WERE AVAILABLE AND ARE REFUSED, NAMED SO A LATER EDIT CANNOT PICK ONE UP
BY ACCIDENT:** `checks/substrate-snapshot.py`'s `COPIES` (**153**, the READER's population — wrong
instrument), and `differ.declared()` (**176**, the ARTEFACT population — wrong subject). This is
the cohort's own lesson applied forwards: `checks/runs-artifacts.py`'s `DENOMINATOR` printed CALL
SITES where a reader read LANES.

**POPULATION SOURCE, MEASURED, NOT `git ls-files`:** `differ.substrate_entries()` =
`(ROOT/"tinybendygrad").rglob("*")` **plus** `differ.SUBSTRATE_INPUTS`. The index is ARMED
(`git ls-tree -r HEAD` = 7386, `git ls-files` = 8025, `.git/agent-index` = 38), so `git ls-files`
was used **nowhere** for a population. `.agents/slop/quiesce/` is the counter-example: it held
**9** files on disk and **0** under `git ls-tree -r HEAD`.

## 4. WHAT A `checks/differ.py` CHANGE WOULD LOOK LIKE — REPORTED, NOT MADE

`checks/differ.py` is another unit's. Three edits, in the order they are owed:

**(a) THE HOOK — one line in `cmd_run()`, at the instant of `:525`.**
```python
substrate_start = substrate_digest()                    # differ.py:525, unchanged
substrate_manifest.stamp(ROOT, D.parent / "MANIFEST.tsv", writer=sys.modules[__name__])
```
with `substrate_manifest` loaded **BY PATH** at differ's import, not `import substrate_manifest`:
`checks/` is `sys.path[0]` when differ runs as a script, so a by-name import binds a module chosen
by the caller's path (`substrate-id.py:132-141` is the house rule against it).
**ONE manifest at `substrate-start` is sufficient and two would be waste:** if the substrate moves
mid-run and stays moved, `substrate_bad()` already refuses; if it moves and moves BACK, `start ==
end` and the tree at the end is the tree the manifest describes. A second manifest would answer a
question already refused.

**(b) THE POPULATION — `SUBSTRATE_INPUTS` (`differ.py:913`) IS A HAND LIST MISSING 2 DECLARED
MEMBERS.** The repair is to ask the declarer, NOT to append two literals (appending them re-creates
`gates/gates-pop.py`'s `HOMES` defect and the next added member is invisible again):
```python
SUBSTRATE_INPUTS = tuple(                       # the declarer's COPIES minus the walk it covers
    rel for rel in _snap.COPIES if not (ROOT / rel).is_file() or (ROOT / rel).is_dir())
```
which yields **10** today, is a derivation rather than a list, and closes `bin/` vs `bin/bend` —
currently equal **by accident**, because `bin/` holds exactly one file (`bin/bend`, 2097 B).

**(c) `gates/retention-check.py` CLAUSE IV** — a sibling of `differ.substrate_bad()` that consumes
`runs/graphcmp/MANIFEST.tsv` and names the member. **NOT NEEDED FOR THE MANIFEST TO EXIST**; it is
the wiring that makes the answer appear in a gate anybody reads.

**`LITERALS` DOES NOT NEED THE NAME.** MEASURED: planting a `MANIFEST.tsv` in a copy of
`runs/graphcmp/D` and calling the REAL `differ.artefacts_ok()` takes it from **0 findings to 1**,
and the finding is `UNEXPECTED MANIFEST.tsv` — that function walks `D/` and reports anything
`declared()` does not name. So the manifest goes **one level up**, at `runs/graphcmp/MANIFEST.tsv`
(`.gitignore:207` `/runs/`, untracked), and `artefacts_ok()` is **0 findings** with it there.
**MEASURED live after writing it: `D/` holds 242 files, `MANIFEST.tsv` inside `D/` = False, beside
`D/` = True at 15164 B, `artefacts_ok()` = 0 findings.**

## 5. THE PLANT, THE THREE SEEDS, THE HASH

`--plant` → **rc=0, 28 of 28**, real functions, real copies of both lanes in a scratch tree (so
`ROOT` is the scratch tree in both and no step can measure the tree it was launched from).

**THE THREE EDITS TO THE COMPARISON**, each paired with **its own scenario**, `MUTATION 3 of 3
caught; NOT APPLIED: none; not caught: none`:

| edit | scenario | caught |
|---|---|---|
| accept any manifest, not the run's (`if False:`) | `other-run` (the summary records a different `substrate-end`) | yes |
| compare the **LIVE** digest instead of the recorded one | `bytes` | yes |
| drop the POPULATION arm and report content drift only | `population` (one member added) | yes |

**THE PLANT WENT RED FOUR TIMES, ON FOUR REAL DEFECTS, THREE OF THEM IN THE PLANT:**

| the red assertion | the defect it found |
|---|---|
| `and it NAMES that member` | the `MOVED` detail was a **3-line block**, so a caller could not read one member per line. Fixed in the CODE, not the assertion. |
| `plant sensitivity census -- accept any manifest … IS caught` and `-- compare the LIVE digest …` | **both patches had not applied at all**: the marker `'if head != recorded:'` occurs **0** times (the real line is `if recorded is not None and head != recorded:`), and `_patched()` returned `None` for a non-unique marker, which the census counted as `not caught`. **An instrument that could not edit anything was reported as an instrument with a blind spot.** Fixed by using the whole-line marker, by splitting `NOT-APPLIED` from `not caught` in the printed census, and by giving each mutation its own scenario. |
| `a TRUNCATED manifest … is caught, not believed` → got `FAIL` | **a real misdiagnosis, not a wrong assertion.** With a `substrate=` header alone, a manifest that lost one row answered `FAIL -- THE DIGEST IS OVER A DIFFERENT POPULATION` and named the lost path **`TREE-ONLY`**, i.e. it claimed **the tree had gained a file it never had**. That is why `members=` is a second header row, and the plant now asserts the refusal names **no path at all**. |
| `because calling it POPULATION-DRIFT would name the lost path TREE-ONLY …` | the new assertion matched the REFUSAL's own explanatory text, which contains the word. Fixed to match lines that **start** with `TREE-ONLY`/`RECORDED-ONLY`. |

**THE THREE SEEDS, SEPARATE PROCESSES, `PYTHONHASHSEED` 1 / 7 / 4242** — and note the brief's own
warning, honoured: one interpreter checking three seeds is theatre.

```
frozen copy, 151 members:  seed 1/7/4242  rows=153  bytes=15164  sha256=6397472f56c1bb35…  (all three equal)
LIVE tree,   151 members:  seed 1/7/4242  sha256=6397472f56c1bb351e0c94b98b98cf294968cf8d09c187a78bb2713236e4b740
MEASURED 2026-10-17T00:36:01Z
```
**THE HASH — AND IT IS THE SAME HASH ON A FROZEN COPY AND ON THE LIVE TREE**, which is the
manifest being path-free and mtime-free for the same reason `differ.substrate_digest()` is.

## 6. FOUND AND NOT DONE

- **`checks/substrate-manifest.py` IS NOT CALLED BY ANYTHING.** The hook is (4a). Until it lands,
  `--write` is a command a human runs and `--check` on the live tree answers
  `REFUSED: … 0 of 151 members per-path`, which is the correct reading of a run with no manifest
  and is **not** a regression — it is the residual, made a verdict.
- **`MANIFEST.tsv` IS LEFT ON THE LIVE TREE** (`runs/graphcmp/MANIFEST.tsv`, 15164 B, gitignored).
  It is deliberate evidence: `--check` against the recorded summary answers
  `A MANIFEST FROM A DIFFERENT RUN — substrate=454e85956b37 but the run recorded 5d3f31197e88`,
  which is the anti-staleness property working on the real record. Delete it with
  `rm runs/graphcmp/MANIFEST.tsv`.
- **`checks/substrate-current.py --report` NOW PRINTS FOUR LANES, NOT THREE** — my file is walked
  by its `census()` and classified `reads the two rows`, which is what it does: it reads
  `substrate-end` and never writes it into a summary. **MEASURED**, not asserted. Its `--plant` is
  still **19 of 19** because its scratch tree does not contain this file.
- **NO FULL RUN.** `differ.py run` is 172 s and a third pass re-arms `retention-check`'s
  `II LEFTOVER`; not attempted. The live-tree readings above come from `substrate_digest()` and
  `substrate_entries()`, not from a run.
- **THE 176-ARTEFACT MEASUREMENT IS THE BRIEF's AND IS NOT RE-DERIVED.** The 176/66 split IS
  re-measured live (242 files in `D/`, 176 declared-shape + 66 `.err`). The "exactly 1 changed"
  half was taken as given and is attributed, not claimed.
- **`ruff check .` OVER THE TREE IS rc=1 AND WAS BEFORE THIS FILE** (18 781–19 679 findings across
  four readings in `AGENTS.md`); `checks/substrate-manifest.py` alone is clean.
- **`differ.substrate_bad()` IS UNTOUCHED**, so `unhealthy()` is byte-identical before and after.
