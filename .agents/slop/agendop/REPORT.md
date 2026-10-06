# AGENTS.md op-count audit — report

Read-only. Nothing in `AGENTS.md` was edited. Instrument and readings below.

## Instrument and reading

```
env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/graphcmp-oracle.py --selfcheck
```

- The oracle takes **no CLI arguments** (no `argparse`, `main()` ignores `sys.argv`), so `--selfcheck`
  is a no-op and the run is the oracle's default `main()`. Full stdout captured at
  `.agents/slop/agendop/oracle.out`; `rc=0`; `# ORACLE SELFCHECK: OK` at line 67.
- Moment: started `2026-10-06 13:54:52`, finished `2026-10-06 13:55:52` (`.agents/slop/agendop/READING.out`).

Lines it printed that matter here (verbatim, from `oracle.out`):

```
# TOTAL: 30 graphs, 355 nodes per side, 66 distinct ops: ADD ... XOR
# OPS PER ENUM SECTION (parsed from tinygrad/uop/__init__.py): 1 defines/special: 3; 2 non op uops: 13; 3 load/store: 4; 4 math: 31; 5 control flow / consts / custom: 10; 6 ops that don't exist in programs: 15; 7 pattern compiler IR (used in upat.py): 1
# NOT REACHED (11 of 77 ENUM MEMBERS): REWRITE_ERROR PROGRAM SOURCE CUSTOM CUSTOMI INS STAGE MSELECT MSTACK CUSTOM_FUNCTION PYLITERAL
#   OF WHICH 7 CANNOT APPEAR IN A PROGRAM GRAPH AT ALL (by construction): CUSTOM CUSTOMI INS PROGRAM PYLITERAL REWRITE_ERROR SOURCE
#   AND 4 ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised): CUSTOM_FUNCTION MSELECT MSTACK STAGE
# DENOMINATOR: 77 enum members -> 70 PROGRAM OPS (7 excluded by the enum's own markers: aren't rendered, renderer, pattern compiler IR, output strings into codegen, machine instruction)
# COVERAGE: 66 of 70 program ops === 66 of 77 enum members (the denominators answer different questions)
```

**The three current numbers: 66 reached · 70 program ops · 77 enum members · 30 graphs.**
The **numerator moves** as graphs are authored, so 66 carries the reading above; it is not a constant.

Independent witness that the port defines the whole vocabulary (run beside the oracle, same session):
enum members `77`; `Ops<NAME>` definitions in `tinybendygrad/**/*.bend` cover `77`, missing `[]`.

## 1. Every line in AGENTS.md carrying an op count

**The denominator: 2 lines carry an explicit op-count claim** (lines 9 and 295). A third line (209)
carries a corpus-size figure that the same corpus growth invalidates. Token occurrences:

| line | text | tokens |
|---|---|---|
| 9 | `census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.` | `61 of 77 ops`, `26 of 77`, `14 of 25 graphs` |
| 295 | `...MEASURED here on the corpus: \`SPEC=1\` 61 of 77 ops · \`SPEC=2\` 26 of 77, 14 of 25 graphs FAIL, exit 1 · \`SPEC=3\` 0 of 77, all 25 FAIL` | `61 of 77 ops`, `26 of 77`, `0 of 77`, `14 of 25`, `all 25` |
| 209 | `(\`46c52f30d\`, TWO FULL 25-GRAPH RUNS)` | `25-GRAPH` (corpus size, not ops) |

Occurrence totals in AGENTS.md: `61 of 77` ×2 · `26 of 77` ×2 · `0 of 77` ×1 · `25-GRAPH` ×1.

No other line carries an op count. (Lines 171/172/174 `670 of 675`, `6 of 15`, `2,353 of 4,455`, and
line 101 `17 of 17`, are file/pin counts, not ops.)

## 2. Wrong vs stale, per line

**The two failure modes are different and must be corrected differently.**

- **WRONG denominator** — `77` is the whole `Ops` enum; 7 members *cannot* be a program node, so the
  program-op denominator is `70`. Any reading presented as `X of 77 ops` is mis-denominated. The oracle
  keeps `66 of 77 enum members` *beside* `66 of 70 program ops` because the two answer different questions.
- **STALE numerator** — the corpus grew from **25 to 30 graphs** (5 authored: `threefry`, `mulacc`,
  `getaddr`, `unshard`, `wmma`), so any numerator is a reading of a corpus that may no longer exist.

| line | token | verdict | why |
|---|---|---|---|
| 9 | `61 of 77 ops` | **WRONG denominator + STALE** | `77` is the enum (program denominator is 70); the SPEC=1 numerator now reads **66** |
| 9 | `26 of 77` | **STALE** | a `SPEC=2` reading of the 25-graph corpus; cannot be re-taken without `bend` |
| 9 | `14 of 25 graphs` | **STALE** | corpus is 30 graphs |
| 295 | `SPEC=1 61 of 77 ops` | **WRONG denominator + STALE** | same as line 9; current reading `66 of 70 program ops` |
| 295 | `SPEC=2 26 of 77` | **STALE** | 25-graph reading; **may still be right**, but is unverifiable here |
| 295 | `14 of 25 graphs FAIL` | **STALE** | corpus is 30 graphs |
| 295 | `SPEC=3 0 of 77, all 25 FAIL` | **STALE** | 25-graph reading; the `0` cannot be re-affirmed on the grown corpus without `bend` |
| 209 | `TWO FULL 25-GRAPH RUNS` | **STALE** | the run corpus is now 30 graphs |

**Which claim is which:** only the `61 of 77` occurrences are *wrong* (denominator). Every other figure
is merely *stale* — a true reading of the 25-graph corpus of 2026-10-06 that the corpus has outgrown.

## 3. The SPEC table specifically

`AGENTS.md:295` records `SPEC=1` 61 of 77 · `SPEC=2` 26 of 77 · `SPEC=3` 0 of 77, with `14 of 25 graphs
FAIL` / `all 25 FAIL`.

- **The SPEC=2 and SPEC=3 rows were measured against the SAME (25-graph) corpus as the SPEC=1 row** —
  the same `14 of 25` / `all 25` denominators say so. Since the corpus is now **30 graphs**, all three
  rows are readings of a corpus that **no longer exists**.
- **Re-taking them needs `bend`** (each row is `bend` running the corpus under a different `SPEC`), which
  this task forbids. So they are left marked STALE, not corrected. The SPEC=1 row can be *restated*
  from the coverage oracle (66 of 70 program ops) because SPEC=1's census **is** the coverage census;
  SPEC=2/3 cannot be restated at all without `bend`.
- Line 9 is the **same claim propagated** into the preamble — a second witness with one source.

## Replacement

Paste-ready OLD/NEW in `.agents/slop/agendop/REPLACEMENTS.md`; every OLD is verified `text.count(old)==1`
in `AGENTS.md`, every NEW names its denominator and, where the number moves, its reading.
