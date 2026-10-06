# REPORT — AGENTS.md op-figure replacements (agendop2)

Date 2026-10-06. `AGENTS.md` READ-ONLY; nothing committed; `bend` not run.

## 1. The previous file's ACTUAL format (why `applied 0, skipped 0`)

`.agents/slop/agendop/REPLACEMENTS.md` does **not** use `### ` headings. Its markers, verbatim:

- the heading is level **`## `** (two hashes): `## R1 — \`AGENTS.md:9\` (...)` (bytes at line 9);
- the label `OLD:` and `NEW:` sit on their **own bare lines** — they are plain text, **not** info
  strings and **not** headings;
- each value is a **plain triple-backtick fence** (no language/info string): ```` ``` ````;
- pairs are separated by a bare `---` line.

So a script that searched for `### ` + fences matched **zero headings**, and a script keying on
fenced `OLD`/`NEW` info strings matched **zero fences**. The content was fine; the shape was not.

First pair, byte-for-byte (from an `open(...).read()` per-line `repr`):

```
'## R1 — `AGENTS.md:9` (preamble; wrong denominator + stale numerator)'
''
'OLD:'
'```'
'census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.'
'```'
''
'NEW:'
'```'
'census from 66 of 70 program ops (66 of 77 enum members; 30-graph corpus, read 2026-10-06 13:55) to 26 of 77 (the enum denominator it was measured against; a 25-graph `SPEC=2` reading, not re-taken) with 14 of 25 graphs failing.'
'```'
```

**AND ITS CONTENT IS NOW STALE TOO**: it says `66 of 70 program ops` on a `30-graph corpus`
(read 13:55). The current reading (14:16) is `70 of 70 program ops` on a `34-graph corpus`.

## 2. Every remaining op figure in `AGENTS.md`, by line, with its replacement

`grep -nE '61 of 77|26 of 77|0 of 77|77 ops|of 77' AGENTS.md` returns **2** lines:

| line | quoted figure | correct replacement |
|---|---|---|
| `9` | `census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.` | `census from 70 of 70 program ops (70 of 77 enum members; 34-graph corpus, read 2026-10-06 14:16) to 26 of 77 ...` |
| `295` | `MEASURED here on the corpus: \`SPEC=1\` 61 of 77 ops · \`SPEC=2\` 26 of 77, 14 of 25 graphs FAIL, exit 1 · \`SPEC=3\` 0 of 77, all 25 FAIL` | `MEASURED: \`SPEC=1\` 70 of 70 program ops (70 of 77 enum members) on the 34-graph corpus, read 2026-10-06 14:16 · ...` |

A third line carries a **corpus-size** figure rather than an op figure, tied to the same growth, and
is replaced as R3:

| line | quoted figure | correct replacement |
|---|---|---|
| `209` | `(\`46c52f30d\`, TWO FULL 25-GRAPH RUNS)` | `(\`46c52f30d\`, TWO FULL RUNS OF THE THEN-25-GRAPH CORPUS; the corpus is 34 graphs as of 2026-10-06 14:16)` |

## 3. The reading (`COVERAGE:` / `DENOMINATOR:`)

`env -u PYTHONPATH .venv/bin/python .agents/slop/graphcmp-oracle.py` **cannot complete here**: its
second census per graph calls `bend` (`graphcmp-oracle.py:287`), and `bend` is forbidden in this
unit. MEASURED: `emit bend: 0 rows after 5 attempts`, `rc=1`, then `SystemExit` before any
`COVERAGE:` line.

The coverage numerator and the denominator are both independent of that lane:
`tal.update(py["per_op"])` (`:303`) is PY-side, and `program_op_split` (`:234`) reads the enum
source. So `.agents/slop/agendop2/reading.py` imports the same oracle, makes `emit_bend` vacuous,
and re-runs its `main()`. Raw output in `.agents/slop/agendop2/reading.out`:

```
# TOTAL: 34 graphs, 386 nodes per side, 70 distinct ops
# NOT REACHED (7 of 77 ENUM MEMBERS): REWRITE_ERROR PROGRAM SOURCE CUSTOM CUSTOMI INS PYLITERAL
#   OF WHICH 7 CANNOT APPEAR IN A PROGRAM GRAPH AT ALL (by construction)
#   AND 0 ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised)
# DENOMINATOR: 77 enum members -> 70 PROGRAM OPS (7 excluded by the enum's own markers)
# COVERAGE: 70 of 70 program ops === 70 of 77 enum members
```

**READING (2026-10-06 14:16, DEV=CPU, default `SPEC`):**
**`70 of 70 program ops` = `70 of 77 enum members`**, on a **34-graph** corpus, 0 unexercised.

Note `--selfcheck` is a NO-OP: `graphcmp-oracle.py` imports no `argparse` and never reads
`sys.argv`, so the flag is silently ignored. (Confirmed by grep: no `argparse`, no `sys.argv`.)

## 4. The `SPEC` table (`AGENTS.md:295`)

The three cells share one **25-graph** corpus that the tree has outgrown (now 34 graphs).

| cell | old | becomes | restatable? |
|---|---|---|---|
| `SPEC=1` | `61 of 77 ops` | **`70 of 70 program ops` (`70 of 77 enum members`)**, read 14:16 | **YES** — this IS the default-SPEC coverage reading above |
| `SPEC=2` | `26 of 77`, `14 of 25 graphs FAIL`, exit 1 | **CANNOT be restated without `bend`** — needs a re-run | NO |
| `SPEC=3` | `0 of 77`, `all 25 FAIL` | **CANNOT be restated without `bend`** — needs a re-run | NO |

Do **not** guess a `SPEC=2` number. Its only honest change today is a label change: the existing
`26 of 77` figure is a 25-graph reading, so it must be marked STALE (and its denominator named
`enum members`, not `ops`), pending a `bend` re-run on the 34-graph corpus.

## 5. Counts with denominators

- Lines carrying an op figure: **2** (`AGENTS.md:9`, `:295`).
- Additional corpus-size figure replaced: **1** (`AGENTS.md:209`).
- Pairs produced: **3**.
- Pairs verified `count==1` and `old` absent from `new`: **3/3** (`.agents/slop/agendop2/applycheck.py`
  parses the new file with the documented rule and prints `verified: 3/3`).
- Pairs that could not be matched: **0**.
- `SPEC` cells restatable without `bend`: **1 of 3** (`SPEC=1`); `SPEC=2`, `SPEC=3` need a re-run.

## 6. Deliverable shape

`.agents/slop/agendop2/REPLACEMENTS.md` = `### ` heading per pair, ```` ```OLD ```` block,
```` ```NEW ```` block. A replacement whose OLD does not match is a diff, not a patch — here every
OLD is a byte-for-byte substring of the current `AGENTS.md` and `count == 1`, measured, not asserted.
