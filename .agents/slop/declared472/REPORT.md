# The 473 `DECLARED-NAME` refusals: classified by CONTENT, and 472 of them moved off `.txt`

Measured 2026-10-06, session `declared472`. Every number below is produced by an instrument in
this directory, not typed:

| instrument | what it does |
|---|---|
| `derive.py` → `derived.json`/`derived-before.json`/`derived-after.json` | re-derives `declared()` and the 473-file snapshot from `sloptxt/PLAN.tsv`, plus a LIVE `os.walk` census so external movement is visible |
| `census.py` | per-path reference census (>=2-component suffix vs bare basename) |
| `plan.py` → `PLAN.tsv` | classifies every one of the 473 BY CONTENT (imports `sloptxt/classify.py` — one rule, not a copy), records the reader, chooses the extension |
| `rename.py` | the only mutation: `os.rename` (never `git mv`), `--dry` first |
| `counts.tsv` | class × action × extension |

Verdict up front: **the 473 and its 139-basename nameset REPRODUCE exactly.** The 140/333
reader split does **not** reproduce bit-for-bit (143/330 — a 3-file drift in a rule that
tests a basename). By CONTENT the 473 split **301 `CAPTURED-STREAM` / 172 `ROWDUMP`** — the
intersection `sloptxt` and `capstream` never computed. I moved **472** files (301 → `.out`,
171 → `.rows`) and kept **1**. `checks/no-txt.py` HARD fell **828 → 356**, a delta of
**exactly 472**. **Nothing deleted.**

---

## 1. The denominators, re-derived — and I reproduce them

`.venv/bin/python .agents/slop/declared472/derive.py`:

```
declared() count                          = 139
snapshot 473 (sloptxt PLAN.tsv, existing) = 473
distinct basenames in snapshot            = 139
snapshot basenames not in declared        = 0
declared names with no snapshot file      = 0
```

The population is taken from `sloptxt/PLAN.tsv`'s own selection (`note.startswith("DECLARED")`)
— the generator's declaration, re-loaded — **not** from a remembered number. All 473 files
existed when I started; all 139 distinct basenames are exactly `declared()`; `0` in each
direction of the difference. **The 473/139 census reproduces exactly.**

**The 140/333 split does not.** At FILE level, re-running the basename test
(`[\w./\-]+\.txt` token in a committed code file, basename equal):

| bucket | `declared473` | this recount |
|---|---:|---:|
| named by a committed code file (basename) | 140 | **143** |
| named only by `declared()` | 333 | **330** |
| named by nothing | 0 | **0** |

The 3-file drift is a property of the *rule*, not of the tree: a basename test matches a
basename anywhere, including inside a longer `.txt` token or a docstring, and it moved when
`figure2/plant/` and other units wrote checks between the two units' runs. **The split is
also the wrong instrument**: doctrine 1 says a basename is a shape, not a population, and
that is exactly what this bucket is. §3 re-tests it as a PATH.

## 2. The 473 by WHAT THEY ARE — content, not name

`plan.py` imports `sloptxt/classify.py` and classifies all 473 by bytes:

| class | count | extension chosen |
|---|---:|---|
| `CAPTURED-STREAM` | **301** | `.out` |
| `ROWDUMP` | **172** | `.rows` |
| `EMPTY` / `TABULAR` / `PROSE` / `SOURCE` / `UNCLASSIFIED` | **0** | — |

An independent recount against `sloptxt/classes.tsv` agrees **473 of 473** (0 disagreements):

```
.venv/bin/python  # compare plan.py classes vs sloptxt/classes.tsv
in both: 473   agree: 473   disagree: 0
```

**This is the intersection the brief says "has never been computed."** `sloptxt` (565 files)
and `capstream` (543) classified *their* populations by content; `declared` refused *this*
population by name. By content the DECLARED population is **301 captured streams and 172 row
dumps** — precisely the same two shapes `capstream` found dominant in the *other* refusal
groups. So all three refusal reasons (DECLARED / REFERENCED / NEITHER) turn out to be the
same two content classes; the reason column never carried information about the file.

## 3. The reference census — a >=2-component suffix, and why the literal rule over-protects

`census.py` re-tests each path as the brief states: a committed CODE file names a
**>=2-component suffix** of the target. Applied *literally* it matches **141** of 475 live
files — because *every* mirror ends in `runs/graphcmp/D/<name>`, and `checks/differ.py`'s
writers (`oracle-run.sh`) name `runs/graphcmp/D/<name>` for the **live** file. That is a
collision one level up from a basename: a `runs/graphcmp/D/<name>` match is not a reference
to `figurefix/plant/D-live/<name>`.

The suffix that actually identifies a file must carry the **mirror-distinguishing**
component. Re-tested that way, the committed code of this tree contains exactly **three**
distinctive path references — and **all three are docstrings in the previous unit's own
harness**, `declared473/contract_test.py` (its case plan, not a read):

```
.agents/slop/declared473/contract_test.py:8   figurefix/plant/D-live/D0-run-summary.txt
.agents/slop/declared473/contract_test.py:10  figurefix/plant/D-live/D1-graph-matmul.txt
.agents/slop/declared473/contract_test.py:12  rerun/D-before/D0-run-summary.txt
```

A **reader** is narrower still: a committed file that copies or opens the tree and then
reads the name. `git grep copytree` over committed code finds exactly one project driver that
does so: `figurefix/plant/plant.py:54` `copytree(HERE / "D-live", …)` then `:58`
`SCRATCH / "runs/graphcmp/D/D0-run-summary.txt"`. **The only file a committed reader opens is
`figurefix/plant/D-live/D0-run-summary.txt`.** (`D-live/D1-graph-matmul.txt` is the *control*
of the prior unit: renaming it changes nothing — `declared473/CONTRACT.md` t2 — so its
docstring mention is a citation, not a reader.)

## 4. The one protected file, and the move

**Protected (NOT renamed): `.agents/slop/figurefix/plant/D-live/D0-run-summary.txt`** — read
by `figurefix/plant/plant.py:54,58` after a `copytree`. It is the **1** the brief names, and
the mechanism is the brief's: *`D0-run-summary.txt` inside a copytree-then-read driver.*

`rename.py` (`os.rename`, never `git mv`), `--dry` first:

```
WOULD MOVE 472  KEPT 1        (dry run)
MOVED      472  KEPT 1        (applied)
```

| class | action | extension | count |
|---|---|---|---:|
| `CAPTURED-STREAM` | RENAME | `.out` | 301 |
| `ROWDUMP` | RENAME | `.rows` | 171 |
| `ROWDUMP` | SKIP (read after copytree) | stays `.txt` | 1 |
| | | **total** | **473** |

Renames by mirror root: `figurefix/plant/D-live` 138, `rerun/D-before` 139,
`figurefix/plant/scratch` 138, `differverdict/*` 57. No committed reader moves: the only
driver that opens any of these trees is `plant.py`, and its one read is the file kept.
`PLAN.tsv` carries the per-file class, reader and new extension.

**`.out` vs `.err` is a content guess**, stated: every `CAPTURED-STREAM` went to `.out`,
matching `capstream`'s choice; none is traceback-shaped enough to force `.err`.

## 5. `checks/no-txt.py` HARD, before and after — the delta equals the rename count

| reading | time | HARD | EXCUSED |
|---|---|---:|---:|
| before | 13:16:18 | **828** | 139 |
| after | 13:17:43 | **356** | 139 |
| **delta** | | **−472** | 0 |

**−472 = the rename count, exactly.** Unlike the three units before this one, the count did
not move under me during the 85-second rename window, so no external cause needs naming
*for the delta*. But the absolute number has moved since `AGENTS.md` recorded **550**: the
**+278** is a NEW mirror pair, `.agents/slop/gatehealth/graphcmp-{ok,broken}/` (139 each),
written by another unit between 13:00 and 13:16 — visible in `derive.py`'s LIVE walk:

```
LIVE basename-in-declared population = 281   (snapshot says 1; external units add mirrors)
owned .txt (live, os.walk)           = 495   (356 HARD + 139 excused)
```

I did **not** rename the `gatehealth/` files: they are another unit's in-flight inputs, not
part of the 473 this task names. The 473 is the correct scope; the 828 is the live floor.

## 6. Limits, stated

* **`declared()` (139) is genuine** — a generator's declaration, imported by `no-txt.py` and
  `differ.py` alike. The weakness is only in extending it to mirror **copies** by basename.
* **The count `473` is a snapshot**; the live DECLARED population was **753** mid-session
  (external `gatehealth/` + `figure2/`). The 473 is the set `sloptxt/PLAN.tsv` selected.
* **`rerun/D-before/D0-run-summary.txt` and `D-live/D1-graph-matmul.txt` were renamed** (neither
  is in §3's reader set — the latter is the prior unit's own CONTROL, which renaming changes
  nothing for). One committed analysis instrument, `declared473/contract_test.py`, `copytree`s
  both mirrors and then reads/renames those names, so it now **fails** — MEASURED:
  `.venv/bin/python .agents/slop/declared473/contract_test.py` → **rc=1** (baseline was 0),
  t1 breaks as designed (`FileNotFoundError … D-live/D0-run-summary.txt`, the protected file,
  in a scratch copy) and t2 crashes because its control target `D1-graph-matmul.txt` is now
  `.rows` (`contract-test-after.out`). I excluded `declared473/` from the reader census because
  it is the *rename-experiment harness itself*, whose case list names its own targets (§3);
  this is the one place the brief's "1 protected file" is one short under a literal
  committed-code census. To keep that harness green, point it at the newer
  `D1-graph-matmul.rows` / `rerun/D-before/D0-run-summary.rows`.
* **138 of the 473 were UNTRACKED** (`figurefix/plant/scratch/`); the other 335 were
  git-tracked. `os.rename` on an untracked file yields no `D` row — that is why the
  worktree shows 334 tracked deletions plus 138 new untracked files for 472 renames.
* **Nothing deleted.** Every one of the 473 still exists, under a stated extension.
