# prune3 — the two holes `prune2` left, and one it named by shape

Measured 2026-10-06 by discovery. Instruments: `measure.py` (`st_blocks`/lstat, symlink-aware),
`delete.py` (guarded delete), `verify_strays.py` (blob-history membership). Rows beside this file.
**No `bend` run. No `git add`, no `git mv`, no commit.** Sizes are `st_blocks`/lstat unless a `du`
is named.

## 0. Headline

`prune2` reported two things it could not delete. One of its two premises is **false**:

- **`strays/` DID leave a report.** It is not a `REPORT.md` — it is the tracked
  `.agents/slop/strays/MANIFEST.tsv` plus the commit `ac85760c2` that applied it. `prune2` searched
  for `REPORT.md`/`FINDINGS.md` only and concluded "no report". Per the rule ("a unit with no report
  is not deletable"), `prune2` correctly stopped; but the record it looked for exists under another
  name, so the files are **not** unaudited. See §1.
- **`loopfix/`'s `.bin` is 14 files, not 11** — and 11 of the 14 have a committed generator. They
  are a build product and are deleted. See §2–§4.

```
deleted     11 files   10 543 104 B   (10.05 MB)   `st_blocks`
spared       3 files      348 160 B   (0.33 MB)   insprobe*.bin, no committed generator
du .agents/slop/loopfix   11 432 KB -> 1 136 KB   (delta 10 296 KB = 10 543 104 B, exact)
```

## 1. `strays/` — the report exists; the KEEP verdict holds

**History search.** There is **no `.md` report under `strays/` and there never was**
(`git log --all --diff-filter=D --name-only -- '.agents/slop/strays/*.md'` = empty; no `.md` ever
added there). **The report is the manifest plus its commit:**

- **`ac85760c2`** (2026-10-05, also duplicated at `8be1da2a2`), subject
  *"sweep: `strays/` 49 -> 29 FILES, `strays-root/` GONE, AND THE PROTECTION WAS NOT ONLY
  UNWARRANTED — IT WAS WORSE THAN `PROTECTED`…"*. Its body is a full audit: 21 tree paths duplicated
  across two arms + 6 artifacts = 27; `origin/` is a **mixed snapshot** (18 live, 2 older, 1 matching
  nothing); `working/` is a **full mutation**; nothing outside the directory reads it (only docstring
  prose).
- **`.agents/slop/strays/MANIFEST.tsv`**, tracked, **53 rows** = `arm / role / path / verdict / why /
  restore`. **25 DELETE (applied) + 28 KEEP.** Every row carries its own restore command, which
  `ac85760c2` says was re-run: *"all 25 deleted again and only column 6 re-run: 25 commands, 0
  failures."*

On disk now: **28 data files + `MANIFEST.tsv` = 29 files**, `st_blocks` **3 731 456 B** (3.56 MB),
`du -sk` = **3644 KB**. That is exactly the 28 KEEP rows.

**I re-audited the manifest's central claim, and it HOLDS.** For each `working/` and `origin/` KEEP
row, I asked whether that exact blob content ever sat at the live `tinybendygrad/<rel>` path in **any**
commit (`verify_strays.py`, one batched `git cat-file`): **0 of 24 reproducible.** E.g.
`working/tinybendygrad/uop/fold.bend` is unique against **115** historical revisions; `device.bend`
against 12. So these are genuinely single-copy bytes, not a redundant port mirror.

**No committed reader of the directory.** `git grep` for `.agents/slop/strays` in code finds only
comments: `checks/nvrows-deadrow-gate.py:192`, `:273`, `checks/sweep.py:261`. **`checks/no-strays.py`
is about the repository ROOT**, not this directory — its name misleads; it never opens `strays/`.

**Decision: SPARE — do not delete.** The premise that triggered `prune2`'s "no report" pause is
refuted: the report is committed and it classifies these 28 as KEEP, and I verified the classification.
Deleting them would discard bytes that exist nowhere else. **I did not touch `strays/`**
(`git status --porcelain .agents/slop/strays` is empty).

**If the orchestrator overrides the manifest** (the analysis is spent; the bytes survive in history),
the exact list is the whole directory — all 29 are committed, so it needs `git rm`, not `rm`:

```
git rm -r --cached .agents/slop/strays      # + rm the working-tree files
```

`git ls-files .agents/slop/strays` = **29** (28 data + `MANIFEST.tsv`). **A narrower option: remove the
21 `working/` mutations only** (the bulk, ~2.4 MB) — but the manifest's own reason is that they are
unreproducible, which I confirmed, so this is an archival call, not a redundancy call.

## 2. `loopfix/` — the `.bin`, identified

**14 files, all `Mach-O 64-bit executable arm64`** (`file`), all untracked and all matched by
`.gitignore:8 *.bin` (`git check-ignore` confirms; the ledger `.agents/slop/gitignore/unanchored.json`
names them individually). **`git ls-files '*.bin'` = 0** — none is tracked.

**Count.** `prune2` said "11". It is **14**; `prune2`'s own §2 prose ("five near-identical variants
each of fold/gcmp/insprobe + rss-ledger/fold.bin") is internally inconsistent, and the 14 rows in
`bin-before.rows` sum to the 10.9 MB it quoted.

**From what.** Each is a `bend -o` native compile; the exact command is recorded in the committed
`.err` beside it. Representative, from `.agents/slop/loopfix/b-fold-new.err`:

```
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=1509 MB  :: ./bin/bend .agents/slop/loopfix/tree/tinybendygrad/uop/fold.bend -o
```

`fold-*.bin` / `rss-ledger/fold.bin` compile `fold.bend` (self-test, 334 rows); `gcmp-*.bin` compile
`tree/drivers/one/gcmp.bend`; `insprobe*.bin` compile `tree/drivers/one/insprobe.bend`.

**Committed generator?** The source `tree/` was deleted by the earlier prune, so I asked which
sources survive in git:

| source | committed? | backs |
|---|---|---|
| `tinybendygrad/uop/fold.bend` | **yes** | `fold-*.bin` (5) + `rss-ledger/fold.bin` |
| `.agents/slop/graphcmp.bend` | **yes** (byte-equal to `tree/drivers/one/gcmp.bend`, `FINDINGS.md` §0) | `gcmp-*.bin` (5) |
| `tree/drivers/one/insprobe.bend` | **NO — never in any commit** (`git log --all -- '*insprobe.bend'` empty) | `insprobe*.bin` (3) |

**Reader?** No committed `.sh`/`.py`/`.bend` invokes any of the 14 basenames (`git grep -l` over those
extensions = none). Only committed **build logs** name them (`.err`/`.out`, the gitignore ledger). The
output of every `.bin` is committed as `.rows` (`selftest-*.rows`, `insprobe*.rows`, `base/*.rows`).

**Verdict.** 11 are **build products with a committed generator** → redundant. 3 (`insprobe*.bin`)
have **no committed generator** → spared (§5).

## 3. Measurements — `st_blocks`/lstat, never `getsize`

`e2epy` is the trap `prune2` named and it reproduces: `measure.py` (lstat) = **745 472 B with 196
symlinks**; `os.path.getsize` follows the symlinks and charges the walk ~1495 MB for system binaries it
does not own. Every number below is lstat-based.

| path | before (14:4x) | after |
|---|---:|---:|
| `du -sh .agents/slop` | **67 M** | **58 M** |
| `du -sk .agents/slop/loopfix` | **11 432 KB** | **1 136 KB** |
| `du -sk .agents/slop/strays` | 3 644 KB | 3 644 KB |
| `measure.py .agents/slop` | 70 627 328 B | 60 407 808 B |
| `measure.py .agents/slop/loopfix` | 11 706 368 B | 1 163 264 B |
| `measure.py .agents/slop/strays` | 3 731 456 B | 3 731 456 B |

**The `measure.py` whole-`slop` delta (−10.2 MB) is NOT the freed measure** — the tree is being
written by other units right now (dir count rose 572→579 and regular-file count fell only 11−8 while
this ran). The honest freed number is `delete.py`'s own lstat sum, **10 543 104 B**, which equals
`du -sk loopfix`'s drop **exactly** (11 432 − 1 136 = 10 296 KB). **A row count from a moving tree is
not a measurement; the exact-match `du` delta is.**

## 4. DELETE — what went

11 files, guarded by `delete.py` (aborts unless each path exists, ends `.bin`, is **not tracked in
HEAD**, and **is `.gitignore`-matched**):

```
.agents/slop/loopfix/fold-{base,new,old,probe,v2}.bin          5 × 1 081 344
.agents/slop/loopfix/gcmp-{base,final,new,old,v2}.bin          5 ×   811 008
.agents/slop/loopfix/rss-ledger/fold.bin                       1 × 1 081 344
TOTAL freed 10 543 104 bytes over 11 files
```

## 5. TRACKED before/after, and `git rm --cached`

`git ls-files` is **not a clean witness** — another unit wrote 7 files across the window (prune2 saw
the same). All `.bin` are untracked and ignored, so **no tracked file was removed and NO `git rm
--cached` is needed for this deletion**.

| scope | before | after | note |
|---|---:|---:|---|
| `git ls-files` (repo) | 6102 | 6109 | +7 from a concurrent unit, not from me |
| `git ls-files .agents/slop` | 3717 | 3724 | ditto |
| `git ls-files .agents/slop/loopfix` | **298** | **298** | unchanged — `.bin` were untracked |
| `git ls-files .agents/slop/strays` | **29** | **29** | unchanged — untouched |
| `git ls-files '*.bin'` | **0** | **0** | still none tracked |

`git rm --cached` is needed **only** if the orchestrator overrides the `strays` KEEP (§1).

## 6. Spared, one line each

| path | bytes | reason |
|---|---:|---|
| `loopfix/insprobe.bin`, `insprobe-old.bin`, `insprobe-v2.bin` | 348 160 | generator `insprobe.bend` **never committed**; no committed regenerator → not proven redundant |
| `loopfix/belt.py`, `belt2-*.rows`, `selftest-*.rows`, `rss-ledger/*.err`, `base/*`, variant dirs | ~1.2 MB | **committed evidence**, the `.rows` are the output of the deleted `.bin` |
| `strays/` (all 29) | 3 731 456 | report committed (`MANIFEST.tsv` + `ac85760c2`); 24/24 KEEP blobs verified unique |
| `e2epy/…/sandbox` 196 symlinks | 745 472 (not ~1495 MB) | lstat, not `getsize`; the win is the measurement, not a byte |

## 7. The one thing I could not settle

**The three `insprobe*.bin`.** They look redundant — their `.rows` outputs are committed — but their
only generator, `tree/drivers/one/insprobe.bend`, is deleted and **was never committed**, so I can
neither regenerate them nor prove the committed `.rows` came from them rather than from an interpreted
lane. "No generator found" is an **absence**, and an absence is not a proof of redundancy. Settling it
needs one of: the `insprobe.bend` source recovered from somewhere, or a run of `insprobe.bin` diffed
against the committed `insprobe.rows` (not done here — a compiled artifact, and I did not run it).
