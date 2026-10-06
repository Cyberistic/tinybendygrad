# EMPTY BLOBS — paths that exist, are tracked, are counted, and say nothing

**Discovery pinned at `dd256b0ec`** (2026-10-06). HEAD advanced to `87a11555f` while this
report was being written; the count is stable (**4832 → 4839 tree paths, 273 empty both
times**), so the number holds across that move but the tree is being committed continuously
and this figure must be re-run, not quoted.

**Answer, in one line.** `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` (git's empty blob) is
the committed blob of **273 of 4832 tracked paths**. All 273 are **0 bytes on disk**. By
name: **58 INTENTIONAL · 4 TRUNCATED · 201 SENTINEL/UNKNOWN · 10 UNCLASSIFIED.** The count
**grew 246 → 273 inside this session**, and the growth is **new empty capture files**, not
truncations.

> **The prescribed walk is not a population by itself.** `git ls-files -s` prints `e69de29…`
> for `git add --intent-to-add` placeholders too. At `c53ace4e8` it returned **1252**
> empty-blob entries, of which **1006 were intent-to-add** (not in HEAD, not staged), and
> **815 of the 1252 had non-zero content on disk**. `checks/differ.py`-style discipline says
> name the denominator: the real committed-empty population was **246**, not 1252.

---

## 1. Population — declared by discovery, not by a list

| source | command | tracked paths | at empty blob |
|---|---|---|---|
| HEAD tree (pinned `dd256b0ec`) | `git ls-tree -r HEAD` | 4832 | **273** |
| index, same moment | `git ls-files -s` | 4832 | 273 |
| index earlier, `c53ace4e8` | `git ls-files -s` | 5558 | 1252 = 246 real + 1006 intent-to-add |

The walk: `git ls-files -s` → field **0=MODE, 1=SHA, 2=STAGE** (`gates/gendirs.py:469`
records the same trap: confusing the fields "is how `checks/gen/` looked like a normal
file"). Compare **field 1** to `e69de29…`. No glob, no name list.

### The instrument flaw (doctrine 1, reproduced)
`git ls-files -s` cannot distinguish three states under `e69de29…`:
* committed empty in HEAD → `git ls-tree -r HEAD` names the path;
* staged empty with content → `git diff --cached --name-only` names the path;
* **`git add -N` placeholder** → neither, `git status --porcelain=v2` reports `1 .A N... 0000 0000`.

At `c53ace4e8`, 1006 index entries were the third kind. `gates/gendirs.py:465 tracked_dirs()`
walks the same `git ls-files -s`, so `gates/retention-check.py` clause V printed, e.g.,
`.agents/slop/arghalf/pin-tree/tinygrad/uop: 10 entries, 10 at git's EMPTY BLOB` — **while
those ten files were 0–17 KB on disk**. A confident wrong answer, exactly as briefed.

---

## 2. Classes, with denominators

| class | count | evidence |
|---|---|---|
| **INTENTIONAL** | **58** | 35 `__init__.py` never non-empty + 1 `tinygrad/py.typed` + 21 `plant*` fixtures + 1 `empty.bend` |
| **TRUNCATED** | **4** | blob was non-empty in HEAD history, now `e69de29…` (named commit below) |
| **SENTINEL/UNKNOWN** | **201** | empty `.err`/`.out`/`.stdout`/`.stderr`; "no output" plausible, but no per-file proof |
| **UNCLASSIFIED** | **10** | neither named, nor truncated, nor a capture (listed below) |

Total 273. **`UNCLASSIFIED` is not `INTENTIONAL`.** By extension: `.err` 150 · `.out` 68 ·
`.py` 36 · `.txt` 6 · `.said` 3 · `.stderr` 3 · `.stdout` 2 · `.md` 1 · `.bend` 1 · `.log` 1
· `.all` 1 · `.typed` 1.

### (a) INTENTIONAL — 58
* 35 `__init__.py` across `test/`, `tinygrad/`, `extra/`, `examples/` — package markers,
  `git log HEAD -- <path>` has **one commit and blob 0 ever since**. (`tinygrad/mixin/__init__.py`
  is the 36th `__init__.py` and is **not** here — see TRUNCATED.)
* `tinygrad/py.typed` — PEP 561 marker; read by `pyproject.toml:52` and `.agents/UPSTREAM-PIN.md:402`.
* 21 `plant*` fixtures: `.agents/slop/e2epy/fixtures/plant*/runs/e2e/e2e-mm-bend.{err,txt}`,
  `.agents/slop/e2epy/artifacts/plant-*.oracle.err`, `.agents/slop/rerun/D-before/D5-plant-*.txt.err`.
  A plant is a deliberately-planted fixture; empty is the planted state.
* `.agents/slop/substrate/fixtures/empty.bend` — the filename is the evidence.

### (b) TRUNCATED — 4, each an EVENT with a commit
| path | went | commit | note |
|---|---|---|---|
| `.agents/slop/e2epy/artifacts/live.oracle.err` | 1168 → 0 | `2f98d012` "e2esh" (2026-10-06, 69 commits back) | reader: `.agents/slop/unknowns/{after,before}.rows` |
| `.agents/slop/e2epy/artifacts/live.port.err` | 1168 → 0 | `2f98d012` | same |
| `.agents/slop/e2epy/artifacts/plant-no-node.port.out` | 1366 → 0 | `2f98d012` | reader: `.agents/slop/e2esh/FINDINGS.md:111` |
| `tinygrad/mixin/__init__.py` | 102552 → 0 | `e0c70b6b` "mixin/op.py [PR] (#16926)" (2026-07-07) | **EXPLAINED-INTENTIONAL**: `tinybendygrad/mixin/__init__.bend:3` states "`tinygrad/mixin/__init__.py` is ZERO BYTES", and the commit is an **upstream tinygrad PR**. A blanket `__init__.py → INTENTIONAL` rule hid this; it is a real content transition that is *correct* |

### (c) SENTINEL/UNKNOWN — 201
Empty `.err`/`.out`/`.stdout`/`.stderr`/`.said` captures that were **created empty and never
non-empty**. A run that exits 0 with empty stderr and a run that was killed both leave a
0-byte file; the file cannot tell them apart. **What would settle it: the producer's exit
status per capture** — a `WITHIN-LIMITS`/`PASS` run makes empty legitimate, a `KILLED`/
`TIMED-OUT` run makes it DEAD.

### (d) UNCLASSIFIED — 10
```
oracles/rows-bd.txt                        0 B  named only by meta-censuses (see §4)
oracles/ops501-py.txt.all                  0 B  NO reader anywhere
langs/out/clang.log                        0 B  build log; written langs/verify.sh:57,
                                                 read only on FAIL (langs/verify.sh:58)
.agents/slop/rerun/probe-{flip,lin}-{METAL,NULL}.txt (4)  0 B  probe captures; only meta readers
.agents/slop/abi4check/at-135bf0204/bind-lt.shipped.said     0 B
.agents/slop/abi4check/now/bind-eq.bend.said                 0 B
.agents/slop/abi4check/now/bind-eq.shipped.said              0 B
```
`oracles/rows-bd.txt` is a **0-byte `.txt`** — it violates the no-txt rule by extension *and*
by emptiness. `AGENTS.md` now calls it "deliberately unclassified"; this report confirms it
is named by **no gate**: its only exact matches are `.agents/slop/agend/oracletxt.rows:103`,
`.agents/slop/oracles259/MANIFEST.tsv:154`, `.agents/slop/oracles259/census.json:1725`.

---

## 3. (b) Readers — 207 exact, 42 basename-only, 24 none

Exact-path reader: **207**. But almost all are the meta-censuses `.agents/slop/residue/*.md`
and `.agents/slop/unknowns/*.rows` that merely *enumerate* the empties. **Only 8 paths have a
reader outside `.agents/slop`, and 7 of those are `tinybendygrad/*/__init__.bend` documenting
that upstream is zero bytes; the 8th is `checks/check.out` named in `.agents/TODO.md`.**
**No gate consumes these files as data.** Full `file:line` per path in `EMPTY.tsv`.

---

## 4. (c) Censuses that count them as PRESENT

* **`gates/gendirs.py:465 tracked_dirs()`** — walks `git ls-files -s`, yields `n_tracked`
  (present, by path) **and** `n_empty_blob` (separately). Consumed by
  **`gates/retention-check.py` clause V (`:461-462`, `:482-484`)**, which prints
  `"N at git's EMPTY BLOB"`. This is *the* census the brief cites. It **sees** emptiness —
  but `n_tracked` calls a 0-byte file present, and its input is the same `git ls-files -s`
  that reported 1006 placeholders, so its empty counts were inflated at `c53ace4e8`.
  Live at `dd256b0ec`: 692 dirs with entries, 4818 entries, **273 empty across 72 dirs**
  (top: `.agents/slop/rerun/D-before` 54, `.agents/slop/canrun/census` 42,
  `.agents/slop/gatesrun` 27, `.agents/slop/spine` 19).
* **`checks/sweep.py:381 tracked_files()`** — `git ls-files -z` + `os.path.lexists`, **no
  content check**. Every empty file counts as present. Its own docstring `:376-379` names the
  `e69de29` intent-to-add SHA as a thing it measured to be 0 — a premise not re-measured.
* **`checks/no-txt.py:81`** — `os.walk` counts `.txt` by extension, no content check, so the
  **6 empty `.txt`** (incl. `oracles/rows-bd.txt`, `oracles/ops501-py.txt.all`) fall in its HARD number.
* `gates/gates-pop.py` — population is entry points, so a 0-byte `.py` is invisible (correct).

**A path counted present that contains nothing inflates a coverage number.** The retention
census is honest because it prints the empty count *beside* the entry count; `sweep.py` and
`no-txt.py` are not — they have no content axis at all.

---

## 5. Is the count GROWING? Yes — by ADDING empties, not by truncating

Last commits, newest→oldest (empty-blob count in each tree):

```
87a11555f  273     21f98c20d  273  +27   <- "gatesrun" added 27 empty captures
dd256b0ec  273     7f9b2944b  246
872f33f22  273     4d0a2b258  246
dcd97943e  273     b504abf77  246
                   56e8280ed  246  +2    <- needsaudit: live.err, plant.err
                   20d0df208  244  +1    <- rosterwire/plantprobe/fresh.md
                   847dde87c  243
```

* **246 → 273 in this session.** +27 at `21f98c20d` (all `.agents/slop/gatesrun/*.out/.err`),
  +2 at `56e8280ed`, +1 at `20d0df208`. **No commit in the last 40 EMPTIED a previously
  non-empty file** (`git log HEAD --numstat -40`: zero files with 0 additions and non-zero
  deletions).
* Truncation events exist but are **older**: `2f98d012` (69 commits back) and `e0c70b6b`
  (2026-07-07). **So "the empty-blob count" is two different facts — a growing pile of empty
  captures, and a small set of truncation events — and a bare number cannot date either.**

---

## 6. Stale claim found while measuring

`gates/retention-check.py:23` and `AGENTS.md` say **"`checks/gen/` … tracked as two EMPTY
BLOBS"**. **MEASURED, falsified:** `git ls-files checks/gen/` → **0**, `git ls-tree -r HEAD --
checks/gen/` → **0**. `checks/gen/` is written at runtime by `checks/abi_gate.py:608-616`
(`gendir = HERE / "gen"`), but it is **not tracked today**. The "two empty blobs" is a
past state of a directory that no longer exists in the index.

---

## 7. What would settle the open questions

1. **SENTINEL vs DEAD (201 files):** tie each capture to its producer's exit status/token. A
   0-byte `.err` after `WITHIN-LIMITS` is legitimate; after `KILLED-ON-MEMORY` it is DEAD.
2. **`.agents/slop/gatesrun/*` (27, all with no reader):** confirm whether
   `gatesrun/run.py`/`finalize.py` read them back or whether they are write-only residue.
3. **Intent-to-add contamination:** make `gendirs.tracked_dirs()` reject index entries that
   `git diff --cached` does not name (i.e. `add -N` placeholders), so its `n_tracked` is a
   count of committed paths.

## Artifacts (`READ-ONLY` elsewhere; nothing outside this dir was modified)
* `EMPTY.tsv` — 273 rows: path, blob, on_disk_bytes, class, ever_nonempty, reader_exact, reader_basename_approx.
* `discover.py` / `classify.py` / `analyze.py` / `fix_readers.py` / `build_tsv.py` — the instruments.
* `summary.json`, `classified.json`, `analysis.json` — raw measurements.
* `retention.out` / `retention.err` — the live clause-V census at `c53ace4e8`.
