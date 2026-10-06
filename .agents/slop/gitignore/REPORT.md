# One unanchored rule: `.gitignore`'s `runs/` matched at any depth

Measured 2026-10-06, session `gitignore`. Every number below is produced by an instrument in
this directory, not typed. The instrument's population is the whole tree (a `os.walk`, not a
list) and it is **validated against git**: `.agents/slop/gitignore/matchlib.py` agrees with
`git check-ignore --no-index` on **0 of 8,992 paths wrong** (the file prints
`mismatches=0`; re-validated after the change).

| instrument | what it does |
|---|---|
| `enumerate.py` → `unanchored.json` | every rule with no leading `/` and no directory prefix |
| `matchlib.py` | gitignore matcher for this tree's rules, **validated against `git check-ignore`** |
| `analyze.py` → `analysis.json` | per-rule matches, where, and what anchoring frees |
| `investigate.py`, `freedreport.py` | the `runs/` composition: output vs evidence |
| `state.py`, `perdir.py`, `summarize.py` | before/after counts and the enumeration table |
| `plant.py` | the two-state demonstration (§6) |

**Verdict.** Exactly **one** unanchored rule was written for the root and is not deliberately
broad: **`.gitignore:157` `runs/`** (now `:172` `​/runs/`). It is anchored. Every other unanchored
rule is deliberate any-depth output/scratch and is **left**. Anchoring `runs/` freed **715
untracked paths, 100% of them under `.agents/slop/`**, and dropped the ignored-untracked
population by **exactly 715** (§5); it changed the tracked status of **zero** paths.

---

## 1. Every unanchored rule, `file:line`, and what it matches

`.gitignore` is `.gitignore:1-172`. An **unanchored** rule has no leading `/` and no interior
`/` before its final segment, so it matches at *any depth*. The table is
`.venv/bin/python .agents/slop/gitignore/summarize.py` (the `FREED` column is
`len(analyze.py freed)` — paths the rule matches that *no other rule* would ignore).

| file:line | rule | matches | untracked | freed by anchoring | decision |
|---|---|---:|---:|---:|---|
| `.gitignore:2` | `references/` | 0 | 0 | 0 | **LEAVE** — cloned third-party checkouts; no nested `references/` exists, so anchoring is a no-op |
| `.gitignore:8` | `*.bin` | 38 | 38 | 27 | **LEAVE** — `bend -o` output lands anywhere; deliberately broad |
| `.gitignore:9` | `*.gpu` | 0 | 0 | 0 | **LEAVE** — same class as `*.bin` |
| `.gitignore:13` | `__pycache__/` | 485 | 485 | 68 | **LEAVE** — interpreter output exists at every depth; anchoring would unleash 68 real `__pycache__` trees |
| `.gitignore:14` | `*.py[cod]` | 416 | 416 | 0 | **LEAVE** — all matches already sit inside an ignored `__pycache__/` |
| `.gitignore:15` | `*.egg-info/` | 6 | 6 | 0 | **LEAVE** — build metadata, any depth |
| `.gitignore:16` | `.hypothesis/` | 0 | 0 | 0 | **LEAVE** — tool scratch, any depth |
| `.gitignore:17` | `.venv/` | 0 | 0 | 0 | **LEAVE** — interpreter, any depth |
| `.gitignore:28` | `*.bak` | 0 | 0 | 0 | **LEAVE** — in-place backup beside any source |
| `.gitignore:29` | `*.orig` | 2 | 1 | 1 | **LEAVE** — same class |
| `.gitignore:30` | `*.rej` | 0 | 0 | 0 | **LEAVE** — same class |
| `.gitignore:34` | `*.mut.bend` | 0 | 0 | 0 | **LEAVE** — deliberate mutants, any depth |
| `.gitignore:35` | `_mut_*.bend` | 0 | 0 | 0 | **LEAVE** — same |
| `.gitignore:36` | `*mut.bend` | 0 | 0 | 0 | **LEAVE** — same |
| `.gitignore:37` | `probe-*.bend` | 3 | 2 | 2 | **LEAVE** — probes, any depth |
| `.gitignore:38` | `probe-*.bend.mut` | 0 | 0 | 0 | **LEAVE** — same |
| `.gitignore:51` | `*probe.bend` | 4 | 4 | 4 | **LEAVE** — same (comment at `:39-50` documents the depth match as intended) |
| `.gitignore:52` | `_*[0-9].bend` | 2 | 1 | 1 | **LEAVE** — same |
| **`.gitignore:157`** | **`runs/`** | **951** | **942** | **715** | **ANCHOR → `/runs/`** |

`references/`, `*.gpu`, `.hypothesis/`, `.venv/`, `*.bak`, `*.rej` and the three `*mut.bend`
forms match **zero** on-disk paths here; they are kept as deliberately broad guards.

**Footnote on `references/` and `.venv/` = 0.** The census walk skips `references/` and `.venv/`
as foreign/interpreters (`matchlib.walk_paths`), so those two rules show 0 *in the population the
instruments measure*; they do match their own root directory, and `references/` has no nested
namesake, which is why anchoring it is still a no-op in practice.

**"The same shape may be elsewhere" was checked and is false for these 18 rules.** The
root `.gitignore` is also not the only ignore source: `load_all_rules()` **discovers 13 tracked
`.gitignore` files** (`langs/`, `extra/*/`, `examples/*/`, `.agents/slop/clearfix/`) plus
untracked ones, by walking the disk — which is why the matcher agrees with git even on
`extra/hcqfuzz/reports`.

## 2. The worked example: `runs/`

`runs/` (no leading slash) matches a directory named `runs` **at any depth**. The rule was
written for `runs/e2e/` and `runs/graphcmp/D/` at the root. `freedreport.py` splits the 951
matches by depth:

```
broad_population   = 951   (894 files)
  root runs/       = 227   <- what `/runs/` still ignores, and the target
  nested runs/     = 724   <- 9 already-tracked + 715 untracked
nested_untracked_before = 715  (100% under .agents/slop/)
```

**Where the 715 untracked paths are** (grouped by the directory holding the `runs/`
component; `.venv/bin/python` re-derivation of `freedreport.py`'s population):

| parent of the `runs/` component | untracked freed |
|---|---:|
| `.agents/slop/declared473/tree/t1/.agents/slop/figurefix/plant/scratch/runs` | 199 |
| `.agents/slop/declared473/tree/t2/.agents/slop/figurefix/plant/scratch/runs` | 198 |
| `.agents/slop/figurefix/plant/scratch/runs` | 198 |
| `.agents/slop/checkshells/runs` | 22 |
| `.agents/slop/differverdict/pristine/runs` | 14 |
| `.agents/slop/e2epy/fixtures/{plant,repro-skip,repro-green,repro-fail}/runs` | 8 each (32) |
| `.agents/slop/e2epy/fixtures/{plant-pass,plant-no-zsh,plant-refuse,plant-no-node,plant-passskip}/runs` | 7 each (35) |
| `.agents/slop/figure2/plant/{broken,real}/runs` | 4 each (8) |
| `.agents/slop/e2epy/fixtures/{plant-deadbend,plant-thin}/runs` | 3 each (6) |
| `.agents/slop/e2epy/fixtures/plant-stage1red/runs` | 2 |
| `.agents/slop/runs` | 1 |
| **root `runs/...`** | **0** (still ignored) |

`nested_untracked_not_under_slop = []` — **not one freed path is outside `.agents/slop/`.**

### The four symptoms, measured

1. `figure2/plant/*/runs/graphcmp/D/D0-run-summary.txt` — matched at depth 4.
2. `e2epy/fixtures/repro-*/runs/e2e/*.txt` — matched at depth 3.
3. `runs/e2e/` — the rule's actual target, kept.
4. **The last 22 of `checks/no-txt.py`'s 24 `.txt`.** `no-txt.py` lists 24 HARD `.txt`; **22 sit
   under a `runs/` component** (2 `figure2`, 15 `e2epy/repro-*`, 5 root `runs/e2e`), and the only
   two not under `runs/` are `oracles/rows-bd.txt` and
   `test/models/efficientnet/imagenet1000_clsidx_to_labels.txt`. `.agents/slop/declared472/`
   (a prior unit) moved 472 `.txt` and reported it could commit **323 of 472** — the 149 it
   could not are the renames whose destination landed in a nested `runs/`. Verified from the
   plan itself: `.agents/slop/declared472/PLAN.tsv` has 473 rows, of which **149 carry a `runs/`
   component**.

### Output or evidence? — the measurement that settles it

`freedreport.py` classifies the 715 untracked freed paths by owning directory:

| class | untracked freed |
|---|---:|
| OUTPUT (graphcmp run artifacts / scratch trees) | 618 |
| EVIDENCE (e2epy fixtures, figure2 plants) | 83 |
| EVIDENCE (differverdict pristine oracle baselines) | 14 |
| **already-tracked** nested paths (pure `fixture`) | **9 (unchanged)** |

Extension mix: `.out 273 · .rows 172 · .err 184 · .txt 17 · .md 24 · .tsv 1 · dirs 44`.

**This is why anchoring is the fix and not a hazard.** The 97 evidence-class freed paths are the
*renamed/duplicate* siblings of evidence that is **already in the index** (`freedreport`:
`nested_tracked_before = 9`, all still tracked). Anchoring tracks nothing and untracks nothing —
it only stops *hiding* the renamed copies the prior unit needed to commit. **Zero tracked paths
change state** (§5).

## 3. What anchoring would UNTRACK, per rule, before landing

Anchoring a rule cannot remove anything from the index — a `.gitignore` rule never untracks
(recorded in this file at `:81-82`, `:105-108`). What anchoring *changes* is which paths are
**hidden**: it un-hides the nested matches. Per rule the un-hidden count is the `FREED` column
of §1. It is non-trivial for exactly three rules:

- `runs/` — **715**, all `.agents/slop/` run artifacts and rename-blocked evidence.
- `__pycache__/` — 68, real interpreter trees → would appear as untracked. **LEAVE.**
- `*.bin` — 27, `bend -o` build output → would appear as untracked. **LEAVE.**

For `runs/`, every one of the 715 is **output or a rename of already-tracked evidence**; none is
untracked evidence that has no tracked counterpart.

## 4. The landed change

`git diff -- .gitignore` is 31 insertions / 3 deletions. The behavioural line:

```
-.gitignore:157   runs/
+.gitignore:172   /runs/
```

plus a corrected comment at `:132-140` (the old bullet claimed `runs/` is *"tracked on
purpose … tabulated in `runs/README.md`"* — `runs/README.md` **does not exist** and
`git ls-files runs/` is **0**; that stale sentence is what hid the bug). The change is mine;
the working tree already carried another unit's uncommitted `checks/gen/`-block, visible in the
same diff.

### `git ls-files` per affected directory, before → now

A `.gitignore` change cannot add to the index by itself, so this column is *what a concurrent
`git add` did with the paths the change freed* (see §5). Source: `perdir.py` at 14:03.

| directory | tracked before | tracked now |
|---|---:|---:|
| `runs/` (root) | 0 | **0** — still ignored |
| `.agents/slop/checkshells/runs` | 0 | 21 |
| `.agents/slop/figurefix` | 206 | 401 |
| `.agents/slop/declared473` | 421 | 812 |
| `.agents/slop/differverdict/pristine` | 11 | 22 |
| `.agents/slop/e2epy/fixtures` | 288 | 339 |
| `.agents/slop/figure2/plant` | 8 | 10 |
| `.agents/slop/corpuswire` | 4 | 5 |

Root `runs/` stays at **0** — the anchored rule still guards it.

## 5. Before / after, and the external cause

`.agents/slop/gitignore/{before,after,now}-state.rows`, `{before,after,now}-lsfiles.rows`.

| measurement | before 14:01 | after 14:04 | delta |
|---|---:|---:|---:|
| rule line | `:157 runs/` | `:172 ​/runs/` | anchored |
| `runs/` matches | 951 | 227 | −724 nested |
| ignored-untracked (whole tree) | **1690** | **975** | **−715** |
| `git ls-files` total | 6396 | 7099 | **+703** |
| `checks/no-txt.py` HARD | **24** | **24** | **0** |
| `checks/no-txt.py` EXCUSED | 139 | 139 | 0 |

- **The ignored-untracked delta is exactly the anchoring: −715 = the freed set, to the path.**
- **`no-txt.py` HARD did NOT move (24 → 24).** `no-txt.py` walks the disk
  (`checks/no-txt.py:81`), so it is blind to `.gitignore`; anchoring renames nothing. The 22
  `.txt` are now *committable*, not renamed — that is a separate unit's move.
- **`ls-files` +703 does NOT match my anchoring, and the cause is named by re-walking, not
  assumed.** I did not `git add` or commit. `comm -13 before-lsfiles.rows now-lsfiles.rows` gives
  **703 added, 0 removed**, of which **671 carry a `/runs/` component** — and the freed set was
  **exactly 671 files** (715 entries incl. 44 directories). So **671 of the 703 additions are the
  paths my anchoring freed, committed by a concurrent unit**; the other **32** are that unit's own
  files (`.agents/slop/bendsuite/bend/test_*.out`, `.agents/slop/buffergraphs/*`,
  `.agents/slop/substratepop/*`, `.agents/slop/{bendarms,corpuswire}/REPORT.md`) plus, swept in by
  the same `git add`, eight of my own scratch files under `.agents/slop/gitignore/`.

## 6. PLANT — two states, and cleanup

`.venv/bin/python .agents/slop/gitignore/plant.py` (creates probes, checks, deletes):

```
state=A path=.agents/slop/gitignore/plant/nested/runs/plant-evidence.rows
state=A check-ignore=NOT-IGNORED rule=(none)          <- was IGNORED by `runs/` (broad)
state=B path=runs/plant-probe/plant-output.rows
state=B check-ignore=IGNORED rule=.gitignore:172:/runs/  <- still ignored (the target)
state=REAL path=.agents/slop/e2epy/fixtures/repro-green/runs/e2e/e2e-f64.txt
state=REAL check-ignore=NOT-IGNORED rule=(none)       <- one of the 22 .txt, now visible
```

State A: a nested `runs/` path is now **NOT-IGNORED** and eligible for `git add`. State B: a path
under **root** `runs/` — the rule's original purpose — is **still IGNORED** by `/runs/`. The
before-state of A is the 715-path freed set (§2); both probes are removed by the `finally`.

## 7. Residuals — what I did NOT change

- **Root `runs/` still ignores `runs/e2e/e2e-mm-oracle.json`**, which `checks/run-port-mm.sh:50`
  and `checks/e2e.py:157` *read*. That file is evidence in an ignored directory — a
  gates-vs-`.gitignore` contradiction `gates/retention-check.py` clause V already reports
  (`:479-494`, `:550-553`). It is **pre-existing** and out of scope for "anchor the unanchored
  rule"; anchoring does not deepen it. Flagged, not fixed.
- The 5 root `runs/e2e/*.txt` are correctly left ignored (generated per run); only the 17 nested
  `.txt` are freed. `no-txt.py` still reports 24.
- 18 other unanchored rules are left broad, with the per-rule reason in §1.
- I did not `git add`, commit, or `@` anyone; `.gitignore` is the only source file I edited.
