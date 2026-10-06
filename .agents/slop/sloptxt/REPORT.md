# `.agents/slop/**/*.txt` — classification and migration

Measured 2026-10-06, session `sloptxt`. Instrument source in this directory
(`features.py`, `readers.py`, `classify.py`, `plan.py`); every number below is produced
by one of them, not typed. `PLAN.tsv` is the per-file table (path, class, rule, reader,
new_path, note) over the full 565-file population.

**Verdict up front: 22 renamed, 543 not.** The 22 are the files with a content class AND no
name-claim anywhere in tracked code. The 543 are reported with the exact reason they stayed —
473 because the name is a generator's own declaration, 65 because live code still names them,
5 because they are EMPTY. No file was deleted.

---

## 1. Population, by discovery (not by `no-txt.py`'s number)

`features.py` walks the repo with `no-txt.py`'s ownership rule (`os.walk`, `.endswith('.txt')`,
`SKIP`/`SKIP_PREFIX`) and re-derives the set. **At session start it reproduced `no-txt.py`
exactly: 711 owned `.txt` = 572 HARD + 139 EXCUSED.**

| top-level dir | owned `.txt` |
|---|---|
| `.agents` (all under `.agents/slop`) | 565 |
| `runs` | 144 (139 are the EXCUSED `runs/graphcmp/D` artifacts; 5 HARD) |
| `oracles` | 1 (`rows-bd.txt`, 0 bytes) |
| `test` | 1 (`test/models/efficientnet/…labels.txt`) |

So **565 / 711 = 79% of the owned population is under `.agents/slop/`, and it is the population
this unit owns.** `oracles/`, `runs/`, `test/` are out of scope (already migrated / excused /
upstream). `no-txt.py`'s 572/139 **is reproduced.**

## 2. The rule (content, never basename)

`classify.py` reads bytes only. Ordered cascade, first match wins:

* **EMPTY** — zero bytes.
* **SOURCE** — line 1 is a shebang, OR ≥2 flush-left `def/class/fn/struct/impl/pub` lines, OR
  ≥2 `import`/`from` lines. (A first version used `compile()`; it called **114 row dumps
  "source"**, because `key=value` data lines are valid Python. Removed.)
* **ROWDUMP** — homogeneous data records. Either
  (a) **≥90%** of non-blank lines are `key=value` with a symbol-safe key, or
  (b) **≥50%** of non-comment lines are **canonical rows**: every whitespace token is
  `digits:payload` (the port's UOp dump form, e.g. `2:i1 5:PARAM 3:f32 …`).
* **TABULAR** — ≥3 non-blank lines, every one carries the same positive tab count.
* **PROSE** — ≥50%, and ≥3, of non-blank lines are natural-language sentences (≥6 tokens,
  ≥60% alphabetic, no `=`). (The ≥3 floor was added because a two-line stub was being called prose.)
* **CAPTURED-STREAM** — everything else non-empty: verdicts, reports, logs.
* **UNCLASSIFIED** — a classifiable file whose bytes are not UTF-8. (None found.)

`AGENTS.md`: *"a sweep that reads basenames cannot tell a row dump from a diary entry."*
No predicate above reads the filename. **EMPTY and UNCLASSIFIED are not ROWDUMP:** an empty
file proves nothing about its shape, which is why `oracles/rows-bd.txt` stayed a `.txt`.

## 3. Class counts (denominator = the 565 `.agents/slop` files)

| class | count | renamed |
|---|---:|---:|
| CAPTURED-STREAM | 369 | 19 |
| ROWDUMP | 190 | 3 |
| PROSE | 1 | 0 |
| EMPTY | 5 | 0 |
| SOURCE | 0 | — |
| TABULAR | 0 | — |
| UNCLASSIFIED | 0 | — |
| **total** | **565** | **22** |

## 4. What moved, what did not, and the live readers

Renamed with **`os.rename`** (never `git mv`):

`.rows` — `bitcastrow/port-post.txt`, `i64shl/base.bd.txt`, `wk-f32-table.txt`

`.out` — `dup/stage1-census.txt`, `e2estage8/artifacts/{diff.live,diff.live2,diff.plants,s6.run1,s6.run2}.txt`,
`i64shl/magicgu.txt`, `name-census-report.txt`, `nvrows/census-MATRIX.txt`,
`reader-fork-census.txt`, `rerun/probe-{flip-CPU,lin-cpu,loop-CPU,loop-METAL,loop-NULL}.txt`,
`shfinish/ref/{post,pre,tree-sha}.txt`, `e2epy/fixtures/plant/runs/e2e/e2e-jsstage.txt`

Not renamed, by reason (`plan.py`; `PLAN.tsv` carries the first reader for each):

* **473 — DECLARED-NAME.** Their basename is in `checks/differ.py`'s `declared()` set. That is a
  *generator's own declaration* (doctrine 1's canonical population), and it is the exact reason the
  139 canonical `runs/graphcmp/D/*.txt` are kept. This is the whole `D*` nameset mirrored into
  `.agents/slop/figurefix/plant/{D-live,scratch/runs/graphcmp/D}`, `.agents/slop/rerun/D-before`,
  and `.agents/slop/differverdict/*`. **They are read, not merely declared:** `figurefix/plant/plant.py:54`
  `shutil.copytree(HERE/"D-live", SCRATCH/"runs/graphcmp/D")` then reads `D0-run-summary.txt` at `:58`
  and `:98`; `differverdict/plant.py` does the same through a copied `differ.py`; and the tree's own
  `plant.py:23` says the scratch exists "so the tree is left with no duplicate `.txt` artifact names".
  Renaming a copy breaks the copy-then-read driver **and** violates that stated design.
* **65 — REFERENCED.** Named by live code. Dominated by the `e2epy/fixtures/**/runs/e2e/*.txt` set
  (46 files) that `checks/e2e.py` opens as `RUN / "e2e-mm-bend.txt"` etc.; also `dd-gate*.txt`,
  `strays-root/{before,after,closure}.txt` (`checks/no-strays.py`), `norm/gate.txt`, `dtypeb/gate.txt`,
  `jsfp8/gate.txt`, `fp8fix/gate.txt`, `opsbend-milestone/*`. `PLAN.tsv` names the reader `file:line`.
* **5 — EMPTY.** `e2epy/fixtures/plant-deadbend/runs/e2e/e2e-mm-bend.txt`,
  `rerun/probe-{flip,lin}-{METAL,NULL}.txt`.
* **1 — PROSE but referenced:** `norm/census.txt` is written by name at `norm/lint_norm.py:251`
  (`(HERE / "census.txt").write_text(...)`), so the generator owns the name.

Basename-only hits inside citation/census artifacts (`_cite/cites.json`, `txtexec/notxt-after.out`,
`checks/txt-owners.py`, which *reads generator sources* not the files) were **not** treated as readers;
`readers.py` classifies readers as code files (`.py/.sh/.mjs/.js/.ts/.bend`) that name the target.

## 5. `checks/no-txt.py` HARD, before and after

| reading | HARD |
|---|---:|
| before (session start) | **572** |
| immediately after the 22 renames | **551** |
| at report time | **553** |

**The delta is not 22, and here is why.** HARD fell by **21**, not 22, because a *concurrent unit*
created `.agents/slop/*.txt` while this one ran:

* `.agents/slop/inst13/tree/.agents/slop/e2e-gpu-probe.txt` (mtime 12:42:45)
* `.agents/slop/rerun2/summary-run1.txt` and `.agents/slop/rerun2/verdicts-run1.txt` (mtime 12:47:06)

Accounting: `572 − 22 (renamed) + 1 (present at the post-rename reading) = 551`; the other two
arrived later, giving `550 + 3 = 553`. A transient `runs/graphcmp/D/.tmp.*.txt` (a live differ run's
temp file, unexcused, not in `declared()`) was also observed and disappeared. **The number moves
because another unit is writing the same tree; it is not this unit's rename bookkeeping.** The three
new paths above are outside this unit's 565-file census and are not in `PLAN.tsv`.

## 6. Limits, stated

* **stdout vs stderr is not decidable from content**, so CAPTURED-STREAM maps to `.out` uniformly;
  `.err` would be a guess. `no-txt.py` accepts both.
* `i64shl/magicgu.txt` is authored commentary but carries `=`, so the rule files it CAPTURED-STREAM
  (`.out`). A stricter PROSE predicate would need an authorship signal content does not carry.
* Classifying the COPY of a generator-declared name as `.rows`/`.out` is true of its bytes and false
  of its role; the role (doctrine 1) wins, so it stays `.txt`. That is the 473.

## Instrument

`.venv/bin/python .agents/slop/sloptxt/features.py` · `readers.py` · `classify.py` · `plan.py [--dry]`.
Artifacts: `features.tsv`, `features.json`, `readers.json`, `classes.tsv`, `PLAN.tsv`.
