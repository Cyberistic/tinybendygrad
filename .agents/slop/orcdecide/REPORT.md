# `orcdecide` — deciding `.agents/slop/oracles259/`, and sweeping for undecided directories

Measured 2026-10-07 by discovery. Instruments: `enumerate.py`, `sweep.py`, `verdicts.py`
(rows beside this file). **No commit, no `git add`, no `@`.**
`checks/no-txt.py`, `gates/`, `AGENTS.md`, `tinybendygrad/` untouched.

**Headline.** `oracles259/` is **not** residue: it is the working directory of a finished unit, and
it holds **2 live inputs** (`MANIFEST.tsv`, `census.json`) and **19 files nothing opens by path**.
The compound claim that it "was deleted" is false — `orcfix` disproved it and this confirms it
(`plants.py` is tracked, byte-identical to HEAD, `e6e31707`). **Verdict: SPLIT** — keep the record,
retire the workshop. The directory's own decision is now landed in
`.agents/slop/oracles259/REPORT.md`.

---

## 1. The 21 files — size, tracked, and reader

All **21 tracked, all present** (`git ls-files` = 21 = `ls` = 21; `git status` clean). The reader
test is a tracked **`.py/.sh/.bend/.mjs/.ts/.js`** file outside the directory naming the file's
**full path** (`git grep -l -F`). A basename join was rejected as doctrine-1 noise: `census.json`,
`classify.py`, `plants.py`, `paths.rows` are generic strings with a dozen namesakes each.

| file | bytes | code readers | verdict |
|---|---:|---:|---|
| `MANIFEST.tsv` | 106424 | 9 | **KEEP (live input)** |
| `census.json` | 64430 | 1 | **KEEP (live input)** |
| `plants.py` | 9989 | 3 citations | RETIRE (superseded) |
| `classified.json` | 53082 | 0 | RETIRE |
| `othercopies.json` | 18189 | 0 | RETIRE |
| `paths.rows` | 7798 | 0 | RETIRE |
| `census.out` | 7701 | 0 | RETIRE |
| `manifest.py` | 6029 | 0 | RETIRE |
| `basenames2.rows` | 5726 | 0 | RETIRE |
| `bn.rows` | 5726 | 0 | RETIRE |
| `basenames.rows` | 5363 | 0 | RETIRE |
| `gate.out` | 4520 | 0 | RETIRE |
| `classify.py` | 4011 | 0 | RETIRE |
| `cited.py` | 3755 | 0 | RETIRE |
| `othercopies.py` | 3093 | 0 | RETIRE |
| `ordering.py` | 2980 | 0 | RETIRE |
| `declared_join.py` | 1362 | 0 | RETIRE |
| `ordering.out` | 419 | 0 | RETIRE |
| `manifest-write.out` | 308 | 0 | RETIRE |
| `manifest-prove.out` | 181 | 0 | RETIRE |
| `classify.err` | 60 | 0 | RETIRE |

Full reasons in `VERDICTS.tsv`. **The `plants.py` "3 readers" are citations, not readers**:
`orcfix/identity.py:15` and `orcfix/skipdelta.py:15` name the literal to audit it, and
`checks/oracle-txt-census.py` names it only inside a docstring recording the **removed** hand-list
(`skip = (me, ".agents/slop/oracles259/plants.py")`). None opens it.

## 2. History — which unit, and what it claimed

40 commits touch the directory (`git log --all --oneline -- .agents/slop/oracles259/`). The oldest
is `cce8ae296` (empty message, 3 files: `classified.json`, `classify.err`, `classify.py`). The
substantive unit is **`oracles259`**, whose report is **`ce24dd609`'s commit body** — **there is no
`REPORT.md` and never was one** (`git log --all --diff-filter=D --name-only -- '.agents/slop/oracles259/*.md'`
= empty; this project's rule holds: *the commit message is a HYPOTHESIS, three of tonight's were
false*). It claimed the directory's product was: **classify the 259 `oracles/**/*.txt` by content,
prove a restore for each, and only then rename.**

- `ce24dd609` (07:08→08:32) — `MANIFEST.tsv`, 259 rows; `RESTORE PROVEN 241/259`; **nothing deleted**
  (*"THE MANIFEST PRECEDES THE DELETE, WHICH IS THE PRECEDENT"*); plant 2 left **FAILING on purpose**.
- `dcd97943e` (txtexec, 12:10) — the rename lands: 258 → `.rows`/`.err`/`.md`/`.tsv`/`.bend`;
  `no-txt.py` HARD 830 → 572 (**exactly −258**). This is why `plants.py` now crashes.
- `1db00c1e6` (oraclerestore, 12:43) — adds `restore_at_HEAD`; the old `restore` column resolved
  **1/259** at HEAD. The manifest is kept as **the record**, not rewritten.

So the directory's artifacts are the unit's **workshop** (`classify.py`, `manifest.py`, …), its
**record** (`MANIFEST.tsv`, `census.json`), and its **raw outputs** (`*.out`, `*.err`, `*.rows`).

## 3. `plants.py` — exact failure, and RENAMED LITERAL vs DEAD SUBJECT

```
File ".agents/slop/oracles259/plants.py", line 68, in plant1
    rows_src = (oracles / "rows-cast-bend.txt").read_text()
FileNotFoundError: '…/oracles/rows-cast-bend.txt'
```

**The immediate cause is a RENAMED LITERAL.** Both donors exist at HEAD under post-rename names:
`oracles/rows-cast-bend.rows` (366 B) and `oracles/ext_oracle_0.err` (32905 B); `plants.py:143`'s
`BEFORE-rows.txt` is now `BEFORE-rows.rows`. A one-line repoint restores execution.

**But the SUBJECT is superseded, so repointing is not the fix.** The instrument `plants.py` tests is
`checks/oracle-txt-census.py`, and that census's population was `rglob("*.txt")` under `oracles/` —
now **1 file** (`oracles/rows-bd.txt`, 0 B). The census's own docstring now says *"THE SUBJECT HAS
MOVED … the census below describes a remnant"*, and its `code_files()` no longer carries the
`oracles259/plants.py` hand-list at all: it **loads the plant's exclusion by path from
`.agents/slop/oracletxt/plant.py`** (`plant_exclusions()`). **The instrument repointed itself to the
successor.**

**Does the successor cover the SAME claims, or less?** Same and more — verified by reading both:

| claim | old `oracles259/plants.py` | new `oracletxt/plant.py` |
|---|---|---|
| rowdump at a no-hint name stays rowdump | ✓ | ✓ |
| source named `*-rows.txt` is still source | ✓ (rename) | ✓ **stronger** — same name, different bytes must MOVE the verdict |
| crash dump at a rows-looking name is still a crash dump | ✓ | ✓ |
| reach: STALE vs ABSENT are distinct | ✗ (asserted the false "ABSENT reads as STALE") | ✓ beat 1/2 |
| reach: SHADOW and LIVE | ✓ (3 states) | ✓ (4 distinct beats) |
| does not mutate the population under test | ✗ — writes into real `oracles/` | ✓ — private `tempfile` tree |

The old plant's one unique assertion — *"removing the input returns the census to its starting
state"* — is not a loss: the new plant asserts the donor is unedited and the four beats are
distinct. **This is a LOSS-FREE supersession, not a retirement of coverage.** `oracletxt/plant.py`
runs green here (`ALL PLANTS PASS`), and its `selftest.py` makes it red under the pre-fix census.
**RETIRE `oracles259/plants.py`.**

## 4. The decision and the retire list

**SPLIT.** Keep `MANIFEST.tsv` (the record) and `census.json` (a live input); write
`oracles259/REPORT.md` (done); **retire the 19 files** in §1. `git rm --cached` list, **NOT applied**:

```
.agents/slop/oracles259/basenames.rows
.agents/slop/oracles259/basenames2.rows
.agents/slop/oracles259/bn.rows
.agents/slop/oracles259/census.out
.agents/slop/oracles259/cited.py
.agents/slop/oracles259/classified.json
.agents/slop/oracles259/classify.err
.agents/slop/oracles259/classify.py
.agents/slop/oracles259/declared_join.py
.agents/slop/oracles259/gate.out
.agents/slop/oracles259/manifest-prove.out
.agents/slop/oracles259/manifest-write.out
.agents/slop/oracles259/manifest.py
.agents/slop/oracles259/ordering.out
.agents/slop/oracles259/ordering.py
.agents/slop/oracles259/othercopies.json
.agents/slop/oracles259/othercopies.py
.agents/slop/oracles259/paths.rows
.agents/slop/oracles259/plants.py
```

## 5. The broader question — every undecided tracked directory

`sweep.py` walks **`git ls-files`** (a walk, not a hand list): **256** tracked
`.agents/slop/<dir>/<file>` directories, plus **277** loose files directly under `.agents/slop/`.

| measure | count |
|---|---:|
| tracked `.agents/slop/*/` directories | **256** |
| with a report (`REPORT.md`/`README.md`/`FINDINGS.md`) | 146 |
| with **no report and no `MANIFEST.tsv`** | **110** |
| with **no report, no manifest, and no full-path reference from any code/doc** | **17** |

**The 17 truly-undecided directories** (tracked, no declaration, nothing reads into them):

```
backlog  bf16fix  censusmarker  citemass  citeresolve  coindependent  devgate  fp8dec
gatespop  helpers-mut  i64div  jjreset  jsbf16  jslane  prefixtxt  readback  run34b
```

They are small (1–5 files each): raw `.out`/`.err` captures (`censusmarker`, `prefixtxt`, `run34b`),
one-off scripts (`citemass/resolve.py`, `citeresolve/scan.py`, `coindependent/vocab.py`,
`jjreset/churn.py`), and free-standing `.md` notes (`devgate`, `fp8dec`, `jslane`, `readback`,
`jsbf16/JSBF16.md`). `oracles259` is itself in the **110** (no report, but referenced) — which is
exactly why it was reported and not silently missed.

**The guard reads the TRACKED tree** (`git ls-files`), so it sees the tree the guard must audit, not
an uncommitted working file: `oracles259/` still counts as undeclared here **because
`oracles259/REPORT.md` is untracked** (this run is forbidden to `git add`). Once that file is
committed it leaves the 110 and the 17. A guard that read the working tree would let an uncommitted
`REPORT.md` silence it — the same shape as a plant that rewrites its own population.

## 6. The guard — and whether it can be one

**A directory can declare its own purpose, and `strays/` is the precedent.** `.agents/slop/strays/`
has no `REPORT.md`; `prune3` audited it anyway because it holds a tracked **`MANIFEST.tsv`**
(53 rows = `arm · role · path · verdict · why · restore`) plus the applying commit. `prune3`'s own
words: *"the record it looked for exists under another name."* `oracles259/MANIFEST.tsv` is the same
shape for its subject population (8 columns), so the hide-and-seek is real.

**The generalised guard is a WALK, no hand list:** for every tracked `.agents/slop/<dir>/`, require a
tracked declaration — `REPORT.md`/`README.md`/`FINDINGS.md` **or** a `MANIFEST.tsv`. `sweep.py` is
that guard's body; it reports the dirs that declare nothing. This is `AGENTS.md` doctrine 1 (b):
a directory walk, not a suffix set or a literal list.

**Be honest about its ceiling:** the guard finds the **absence** of a declaration; it cannot author
one, because a report is a human artifact. And a `MANIFEST.tsv` is itself a per-file list — but it
is doctrine-1(a) compliant **only when it is the unit's own declaration loaded by path**
(`differ.declared()`, `plant.excluded()`), never a second copy typed into the guard. So the
deliverable is: **a sweep that names the 17 (today) undeclared directories and fails until each
either states its purpose or is retired** — the decision being the human's, the detection being the
walk's.

## Reproduction

```
.venv/bin/python .agents/slop/orcdecide/verdicts.py      # 21 files, per-file KEEP/RETIRE with readers
.venv/bin/python .agents/slop/orcdecide/sweep.py         # 256 dirs; 110 undeclared; 17 undecided
.venv/bin/python .agents/slop/oracletxt/plant.py         # ALL PLANTS PASS (the successor)
.venv/bin/python .agents/slop/oracles259/plants.py       # FileNotFoundError at :68 (retired)
```
