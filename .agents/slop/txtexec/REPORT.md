# txt259 execution — renaming `oracles/**/*.txt` by class

**Verdict: executed and landed.** 258 of 259 `.txt` under `oracles/` are renamed to their
class's extension and the rename is in commit `4d0a2b258` (`notxt139`, author `Cyberistic`,
2026-10-06 12:04:32). Residual `.txt` under `oracles/` is **1** — `oracles/rows-bd.txt`,
0 bytes, `rowdump?/empty`, deliberately UNCLASSIFIED and left. `checks/no-txt.py` HARD fell
**exactly 258**. The MANIFEST's digest column had **18/259** rows carrying another row's
hash; all 18 are corrected and **259/259** restores verified. This is a `git`/`jj` tree with
a concurrent unit writing it; the tree moved under the plan and that is recorded in §0.

---

## 0. THE TREE MOVED UNDER THE PLAN — measured, and why the rename is already in history

- At session start `os.walk("oracles") + endswith(".txt")` returned **259**, matching
  `PLAN.tsv` exactly. That was the **working tree**, and it was pre-rename.
- `git log -1` is **`4d0a2b258 notxt139`**, authored `2026-10-06 12:04:32`, and its tree
  already holds `oracles/AFTER-pins.rows` etc. Its parent **`b504abf77`** holds the `.txt`
  names. `265 files changed`, the rename among them.
- The commit's target names match **my** per-class mapping, including the two deviations the
  plan's own `new_path` column would not produce (`oracles/usb-arith-rows.bend`, not
  `…bend.rows`; `oracles/fold-mut.rows` beside the pre-existing `oracles/fold-mut.py`). So
  the staged `git mv` I ran is what `4d0a2b258` records.
- `jj diff -- oracles` on the working copy `@` (`pymzsouo`, parent `4d0a2b258`) is
  **0 files changed**: `oracles/` on disk equals the committed state. `git status | grep -c '^R'`
  is **0** for the same reason.

So step 2's "execute the renames" and the commit are one event. Everything below is verified
against git's tree, not against the rename script's own report.

## 1. Population, re-derived before executing (denominator 259)

Instrument: `os.walk("oracles")` + `endswith(".txt")`. The session-start walk returned 259
(the working tree was pre-rename); because the rename has since landed, the walk now returns
1, so the pre-rename population is reproduced from git's own pre-rename tree
(`git ls-tree -r b504abf77 -- oracles`, filter `.txt`) by `.agents/slop/txtexec/derive_pre.py`
→ `derive-before.out` (259, set-equal, `only in walk: []`, `only in plan: []`). The post-rename
walk is `derive-after.out` (1).

| measure | value |
|---|---|
| `.txt` under `oracles/`, walk | **259** |
| rows in `PLAN.tsv` | **259** |
| walk set == plan set | **True** (0 only-walk, 0 only-plan) |
| classes | rowdump 240 · crash-dump 7 · `?/md` 5 · `?/tsv` 3 · source 3 · `?/empty` 1 |
| reach | LIVE 4 · SHADOW 0 · STALE 30 · NOTHING 225 |

Every number in the brief's class list reproduced. **The count is 259, so the plan was
executed as given.**

## 2. The renames, verified against git's own tree (denominator 259)

Executed with `git mv`, one class at a time (`.agents/slop/txtexec/rename.py`). Renamed
counts are then re-derived from `git ls-tree` at `b504abf77` (old name present) and
`4d0a2b258` (new name present) by `.agents/slop/txtexec/verify_renamed.py` — `bad: []`.

| class | n | target | verified in git tree |
|---|---|---|---|
| rowdump | 240 | `.rows` | 240 |
| crash-dump-in-txt | 7 | `.err` | 7 |
| `rowdump?/md` | 5 | `.md` | 5 |
| `rowdump?/tsv` | 3 | `.tsv` | 3 |
| source-in-txt | 3 | 1×`.bend`, 2×`.rows` (see §7) | 3 |
| **total renamed** | **258** | | **258 / 258** |
| `rowdump?/empty` | 1 | left `.txt` | — |

**Residual `.txt` under `oracles/`: 1 / 259**, `oracles/rows-bd.txt`, **0 bytes**. Left because
it is `UNCLASSIFIED` — the census's own `shape()` could not classify it (`probe=empty`), and
the report §5 says an empty file "must not become `.rows`". Renaming it would assert a content
class the file does not evidence. `git ls-tree HEAD -- oracles | wc -l` is 358 both before and
after (a rename, not an add/delete). Extension tally after: `.rows` 277 · `.py` 7 · `.bend` 16
· `.err` 12 · `.md` 5 · `.tsv` 4 · `.json` 20 · `.txt` **1**.

## 3. LIVE readers — repointed and shown to resolve (denominator 4 LIVE files)

Authority on reach is `checks/oracle-txt-census.py`'s token resolution, not the PLAN's
`readers` column (a basename superset). The census names **one** reader: it reports

```
LIVE  4 / 259
  oracles/BEFORE-rows.txt                 <- .agents/slop/oracles259/ordering.py  at oracles/BEFORE-rows.txt
  oracles/sb-oracle.txt                   <- .agents/slop/oracles259/ordering.py  at oracles/sb-oracle.txt
  oracles/schedule-bodies/BEFORE-rows.txt <- .agents/slop/oracles259/ordering.py  at oracles/schedule-bodies/BEFORE-rows.txt
  oracles/schedule-bodies/sb-oracle.txt   <- .agents/slop/oracles259/ordering.py  at oracles/schedule-bodies/sb-oracle.txt
```

| file:line | old path | new path |
|---|---|---|
| `.agents/slop/oracles259/ordering.py:39` | `oracles/BEFORE-rows.txt` | `oracles/BEFORE-rows.rows` |
| `.agents/slop/oracles259/ordering.py:40` | `oracles/schedule-bodies/BEFORE-rows.txt` | `oracles/schedule-bodies/BEFORE-rows.rows` |
| `.agents/slop/oracles259/ordering.py:42` | `oracles/sb-oracle.txt` | `oracles/sb-oracle.rows` |
| `.agents/slop/oracles259/ordering.py:43` | `oracles/schedule-bodies/sb-oracle.txt` | `oracles/schedule-bodies/sb-oracle.rows` |

`:53` is a print string, not a read. The four `.txt` literals were the **source side** of a
rename this scratch tool performed itself; repointing them to `.rows` makes each path
expression name an existing file. Run (`.agents/slop/txtexec/ordering-after.out`):

```
  reader targets that RESOLVE: 4/4
    OK   oracles/BEFORE-rows.rows
    OK   oracles/schedule-bodies/BEFORE-rows.rows
    OK   oracles/sb-oracle.rows
    OK   oracles/schedule-bodies/sb-oracle.rows
  census after the rename: files=1  stale=1  live=0
```

The census itself confirms it: `LIVE 4 → 0`, `files 259 → 1`.

**The other basename-mentioners are NOT LIVE reads, and were not touched:**
- `checks/sb-gate.sh:42,51` sets `D=.agents/slop/schedule-bodies`, so it opens
  `.agents/slop/schedule-bodies/BEFORE-rows.txt` — **absent** (STALE), already `exit 3`.
  Renaming `oracles/` cannot change it. `:149` writes `$D/sb-oracle.txt` (a write, not this file).
- `.agents/slop/sbgate/plant.py:82,125` builds a **throwaway tree under `$TMPDIR`** and writes
  fixtures there; it never opens `oracles/`.
- `.agents/slop/oracles259/plants.py:143` names `oracles/schedule-bodies/BEFORE-rows.txt`, but
  the census **excludes plants.py from `code_files()`** (`census:203`) because it writes into
  the population under test — so it is not a LIVE reader and was not repointed.

**No production gate opens any `oracles/*.txt` at a present path.** The 30 STALE basenames
already pointed at absent `.agents/slop/…` paths *before* this rename; renaming `oracles/`
neither fixed nor broke them.

## 4. MANIFEST digest column — 18/259 wrong, now 0/259 (denominator 259)

The manifest's restore is `git cat-file blob $(git rev-parse HEAD:<old path>)`, so the digest
it should hold is `sha256(HEAD:<old path>)` as of the tree it was written against — the
pre-rename commit **`b504abf77`** (`4d0a2b258^`). Audited by
`.agents/slop/txtexec/digest_audit.py b504abf77`:

| measure | before fix | after fix |
|---|---|---|
| HEAD-path blobs resolving at `b504abf77` | 259/259 | 259/259 |
| digest **correct** | **241 / 259** | **259 / 259** |
| digest **wrong** | **18 / 259** | **0 / 259** |
| restore verified by bytes | 259/259 | 259/259 (258 non-empty + 1 empty) |

The 18 are exactly the "handed another row's hash" pattern the report predicted: `fold-landed.txt`
and `fold2_base.txt` share one manifest hash while their real blobs differ;
`py_mv.txt` carries `FINAL_mv.txt`'s hash; `cstyle-capture-oracle.txt` and
`tinybendygrad_renderer_cstyle.bend.renderer_oracle.txt` share one. All 18 were corrected **in
the digest column only** (`.agents/slop/txtexec/fix_manifest2.py`, log `manifest-fix.out`); the
`path`, `bytes`, `disposition` and `restore` columns are untouched. The file is **CRLF** (260
CRLF endings): the fix starts from the HEAD blob and rewrites only field 1, so
`git diff --numstat HEAD -- MANIFEST.tsv` is exactly **18/18**, not a whole-file rewrite. A
wrong hash makes a good restore look broken; the command was right for all 259 and only the
digest was wrong.

## 5. `checks/no-txt.py` before and after (denominator: owned `.txt`)

| reading | HARD | EXCUSED | owned | rc |
|---|---|---|---|---|
| before (session start, `.agents/slop/txtexec/notxt-before.out`) | **830** | 139 | 969 | 1 |
| after (`.agents/slop/txtexec/notxt-after.out`) | **572** | 139 | 711 | 1 |
| **delta** | **−258** | 0 | −258 | — |

The drop is **exactly 258**, the renamed count. `rows-bd.txt` is the one `oracles/` path still
in the HARD list. Note the brief's "553 HARD" is a **stale** reading — `4d0a2b258^` was 830
(the AGENTS.md correction to 572/711 agrees with the after-reading here). Both readings are
kept with the file that produced them; the number moves as units write.

## 6. What the MANIFEST restore commands become (NOT rewritten)

Measured by `.agents/slop/txtexec/restore_paths.py` (denominator 259):

```
restore old-path resolves at HEAD 4d0a2b258: 1/259  ['oracles/rows-bd.txt']
restore old-path resolves at PRE  b504abf77: 259/259
```

Each of the 258 restore commands names a path that **no longer exists at HEAD**. They become
one of two forms — the manifest is a record, so the column is **not** silently rewritten:

- restore the ORIGINAL name from the pre-rename tree:
  `git cat-file blob $(git rev-parse b504abf77:oracles/X.txt) > oracles/X.txt`
- follow the file to its NEW name:
  `git cat-file blob $(git rev-parse 4d0a2b258:oracles/X.rows) > oracles/X.rows`

The one still-resolving command is `oracles/rows-bd.txt` (still `.txt`). A `HEAD:`-rooted
restore is now wrong for 258 rows because `HEAD` moved past the rename; that is a fact about
`HEAD` moving, not about the command having been written wrong.

## 7. Discrepancies found and how each was resolved

1. **`PLAN.tsv`'s `new_path` column is mechanically `path[:-4]+'.rows'` for all 259**
   (`all(new_path == path[:-4]+'.rows')` is `True`), disagreeing with its own `cls` for 19
   rows (7 crash → should be `.err`, 5 md, 3 tsv, 3 source, 1 empty). The brief's class→ext
   map is the spec, so the extension was derived from `cls`, not from `new_path`.
2. **"3 source" is really 1 source + 2 run reports.** `oracles/usb-arith-rows.bend.txt` is
   bend source (`def t_wire…`) → `oracles/usb-arith-rows.bend`. `fold-mut.txt` and
   `ops-mutations.txt` begin `baseline: N rows, both lanes identical` — they are the **output**
   of mutation harnesses; their `probe` is `rows` and the plan's own `new_path` is `.rows`.
   Also **`oracles/fold-mut.py` already exists** and differs (11,584 B harness vs 6,190 B
   report), so `.py` would have clobbered the real generator. Both → `.rows`.
3. **The MANIFEST digest column is wrong on 18/259**, as the brief said — fixed (§4).
4. **The tree moved under the plan** (a concurrent unit's `notxt139` commit) — recorded in §0.
   The rename is landed; residual is 1.

## Reproduction

```
.venv/bin/python .agents/slop/txtexec/derive_pre.py     # 259, plan set-equal (pre-rename tree)
.venv/bin/python .agents/slop/txtexec/rename.py         # git mv by class (already landed)
.venv/bin/python .agents/slop/txtexec/verify_renamed.py # vs git tree: 258 renamed, bad []
.venv/bin/python .agents/slop/oracles259/ordering.py    # LIVE reader: 4/4 resolve
.venv/bin/python .agents/slop/txtexec/digest_audit.py b504abf77   # 18/259 -> 0/259 after fix
.venv/bin/python checks/no-txt.py                       # 572 HARD + 139 EXCUSED
.venv/bin/python .agents/slop/txtexec/restore_paths.py # 1/259 old paths resolve at HEAD
```

Artifacts, all under `.agents/slop/txtexec/`: `derive-before.out`, `derive-after.out`,
`census-before.out`, `notxt-before.out`, `notxt-after.out`, `rename.out`,
`verify-renamed.out`, `digest-audit.out`, `manifest-fix.out`, `ordering-after.out`,
`restore-paths.out`, and the scripts above.
