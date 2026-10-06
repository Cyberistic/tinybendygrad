# Three numbers cite one population; the population moved; the citations did not

Unit `citetruth`. Measured 2026-10-06, readings taken at **2026-10-06T12:19–12:23Z** against
**HEAD `7f70b475081371a5eb4c1b2967cc706da1a1e2a7`**. Interpreter `.venv/bin/python` throughout.
`bend` never run. No commit, no `git add`. Files written only under `.agents/slop/citetruth/`
plus the four citation surfaces I own.

## 1. The three numbers, re-derived BY DISCOVERY

Every number carries the method that produced it. `rederive.rows` holds the same table.

| # | rule | command | value |
|---|---|---:|---:|
| N1 | `.bend` suffix on the port | `find tinybendygrad -name '*.bend' \| wc -l` | **134** |
| N2 | `sweep.py` `port_files()` — `os.walk`, **no** suffix filter | `.venv/bin/python -c "import importlib.util as u; s=u.spec_from_file_location('s','checks/sweep.py'); m=u.module_from_spec(s); s.loader.exec_module(m); print(len(m.port_files()))"` | **140** |
| N3 | volume ratio, non-comment lines, port / pin | `.venv/bin/python .agents/slop/citetruth/measure.py` | **39.4%** |

N3's rule, stated once and applied to both sides in `measure.py`: a **non-comment line** is a line
whose `strip()` is non-empty and does not start with `#`.
**Port = `tinybendygrad/**/*.bend` = 92,972** non-comment lines. **Pin = `tinygrad/**/*.py` excluding
`test/` = 235,885**. `92,972 / 235,885 = 39.41%`.
**A MINUTE LATER THE SAME SCRIPT READ 92,978 / 200,488 lines (39.42%) — the tree is LIVE (another unit
holds `tinybendygrad/uop/{ops,render}.bend` open), so the volume numerator drifts by a few lines and the
reading is a snapshot; the file COUNT (134/140) did not move.**

`measure.py` also reproduces the four relocated files' **1,837** non-comment lines, which is exactly
the `40.2%→39.4%` delta (`92,972 + 1,837 = 94,809`; `portpop` read `94,777`, `portzz` `94,805` — a
4-line spread between two un-pinned comment rules, which is why the rule is stated here and the ratio
is quoted to one decimal).

**Before → after, as one table:**

| number | rule | before | after |
|---|---|---:|---:|
| `134` | N1 | 138 | **134** |
| `140` | N2 | 144 | **140** |
| `39.4%` | N3 | 40.2% | **39.4%** |

**The `41%` is not a measurement in any owned file.** `grep -rn "41%\|\b0\.4x\b\|40\.2\|39\.4"` over
`AGENTS.md`, `.agents/TOOLS.md`, `.agents/TODO.md`, `checks/`, `gates/` returns **nothing**. The only
`40.2%`/`39.4%` live in `.agents/slop/portpop/REPORT.md` and `.agents/slop/portzz/REPORT.md`; the
`41%` lives only in the task prompt. **The volume ratio has no cite to move.** `0.4x` appears nowhere.

## 2. Every cite, its number, and whether it is DERIVED or DERIVABLE

A **DERIVED** number is a generator's output pasted in (a frozen reading); a **DERIVABLE** number is a
literal that could be recomputed, and **it rots** — `103`→`139`→`175` is the tree's own precedent.
The full census is `cites.rows` (44 rows). The one-line command for each literal is N1/N2/N3's, above:
**`find tinybendygrad -name '*.bend' | wc -l` for every `138`; `find tinybendygrad -type f | wc -l`
(= `port_files()`) for every `144`.**

The `138`/`144` cites fall into three classes:

- **DERIVABLE, present-tense** (the number asserts a property of the tree *now*) — **`TOOLS.md:406`
  (`compare.py` re-discovers by `rglob('*.bend')`) is the clean one**; these are the cites that must
  carry the new number.
- **DERIVED, a frozen run output** — `TOOLS.md:413,437,446` (a captured `bendpin/compare.py` run) and
  `AGENTS.md:71` (`43 of 138` from `.agents/slop/peakrss/census.rows`). **Overwriting these falsifies a
  reading**; the number was true at its reading, so the current value is *appended*.
- **DERIVED, dated historical** — the `TODO.md` blocks dated 2026-10-04/05 (`:257,263,265,266,6417,6422,
  10988,10991,11134,11163,11175,11202,11210,11696`). These are readings of a tree that then held 138/144.

## 3. Corrections landed

**3 CORRECTED** (a literal changed):
- **`AGENTS.md:60`** — `.agents/slop/peakrss/census.txt` → **`census.rows`**. A stale *path* cite of the
  same artifact; the file was renamed `.txt`→`.rows` and the doc kept the `.txt`. (No `.txt` ever.)
- **`checks/census.json:8271,8273`** — the `port_where` for `renderer/nir.bend`'s `go` named
  `runtime/zzdiag.bend` and `runtime/zzread.bend`, both **relocated out of the port by `portzz`**. The
  two moved paths are removed; `runtime/zzprobe2.bend` (still in the port) remains. JSON re-validated:
  1028 entries.

**24 ANNOTATED** (number kept as its reading; the re-derived value and its reading added):
- `AGENTS.md:71` — `43 of 138` **is** the frozen `census.rows` denominator (2026-10-05 20:59); appended
  `the port is 134 .bend as of 2026-10-06T12:19Z, HEAD 7f70b475`.
- `.agents/TOOLS.md:406,413,437,446` — the `bendpin` run's population; `134` appended with its reading.
- `.agents/TOOLS.md:907` and `.agents/TODO.md:6384,10972,11126,11680` — **one current-reading note per
  dated section header** (each names `134`/`140` and its command), so every dated count inside resolves
  against a live number and every dated number stays as its own reading.
- `.agents/TODO.md:263–266` (the "DENOMINATOR HAS FOUR VALUES" block) — a `RE-DERIVED` note appended:
  `134`/`140`, commands, and `THE 138/137/139 ABOVE ARE THE 2026-10-05 READING`.
- `.agents/TODO.md:279,293` — current reading appended inline.

**14 REPORTED, not corrected** (reason given per cite in `cites.rows`):
- **`checks/*.py`, `checks/*.sh` — NOT OWNED by this unit** (`sweep.py:579`; `substrate.py:118,133,548`;
  `no-strays.py:95,106,133`; `demo.sh:8,25`). `sweep.py:579`'s `all 144 files` is **prose only** (the
  code walks live), so the replacement is `144 → 140`; `substrate.py` is **being edited live by another
  unit** and its line numbers move under me — `:543`→`:548` during this run. **An owner of `checks/`
  should land these; the numbers are DERIVABLE, and the fix is one literal each.**
- `TOOLS.md:912,920` and `TODO.md:257,6422` — dated historical narratives, covered by their section note.

**3 EXCLUDED** — same digits, **different population**: `TOOLS.md:1086` (`shared 138` = differ *rows*),
`TODO.md:7328` (`15 of 138` = shared *rows*), `TODO.md:13435` (`144 NOT BROKEN` = *findings*). The rest
of the `138`/`144` grep hits are line numbers (`gradient.py:138`), byte values (`nbytes = 144`), or
section refs (`e2e.sh:138`) — not population counts.

## 4. `checks/census.json` is a frozen dataset, not a generator's output

Point 5 of the brief: do not hand-edit a generated file. **No script in the working tree writes
`checks/census.json`.** The only writers of a file named `census.json` write elsewhere
(`checks/oracle-txt-census.py:455` → `.agents/slop/oracletxt/census.json`; `checks/dup-census.py:276`
→ `checks/dup-census.json`; `shfinish/`, `declared472/`, `portexec/` write their own). No consumer
loads `checks/census.json` either (no `.py`/`.mjs`/`.sh` names the path, and `grep -rn port_where
--include='*.py'` is empty). **It is a committed 1028-row static dataset** (the schema — `port_file`,
`port_line`, `own`/`run`/`marker_text`, `port_where` — was produced by a generator that is no longer
in-tree). Editing it is therefore not overwritten — **but a restored generator would overwrite it, so
the two edits above are reported here rather than silently left.**

## 5. The one cite I could not settle

**`AGENTS.md:71`'s peak-RSS denominator.** `43 of 138` is true of the frozen `census.rows`, and the
live port is `134`, so the artifact and the tree now disagree — and **I cannot re-measure the census**:
it needs `bend`, which this session may not run (another unit holds it). Whether `43` still holds over
134 `.bend`, and whether the four relocated probes were among the `43 under 50 MB`, is **unknown**, so
I kept the artifact's `138` and appended the live `134` rather than invent a count.
**What would settle it:** a peak-RSS re-run of the current `tinybendygrad/**/*.bend` under
`checks/bounded.py --mb 1024`, sequentially, once `bend` is free — then the denominator and the
numerator move together.

## 6. Counts

- **44 cites surfaced** across `AGENTS.md`, `.agents/TOOLS.md`, `.agents/TODO.md`, `checks/`, `gates/`,
  `checks/census.json` (`cites.rows`).
- **3 corrected** (a literal/path changed: `AGENTS.md:60`; the two moved paths in `census.json`).
- **24 annotated** (number kept as its reading; re-derived value appended inline or via a section note).
- **14 reported, not corrected** (9 in `checks/*.py`/`*.sh`, which this unit does not own; 4 dated
  narratives; 1 the absent volume-ratio cite).
- **3 excluded** (same digits, different population).
- **Volume ratio:** 0 cites to move; the `40.2%`/`41%`/`0.4x` are absent from every owned surface.

Artifacts: `measure.py` (the non-comment rule, runnable), `rederive.rows` (the three numbers + method),
`cites.rows` (the census), `REPORT.md`. No `.txt` created.
