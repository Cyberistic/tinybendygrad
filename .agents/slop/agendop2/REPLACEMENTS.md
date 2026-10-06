# AGENTS.md op-count replacements — apply-ready

## FORMAT CONTRACT (the previous file failed here, not on content)

`.agents/slop/agendop/REPLACEMENTS.md` presents each pair as a level-`## ` heading followed by
a bare line `OLD:` and a bare fenced block, then `NEW:` and a bare fenced block. An apply script
that keyed on `### ` headings found none, because the headings are `## ` and the `OLD:`/`NEW:`
labels are plain text, not fenced. That is the whole of the `applied 0, skipped 0` failure.

THIS file uses, for every pair:

- a level-`### ` heading, one pair per heading;
- the OLD text in a fence opened with `OLD`;
- the NEW text in a fence opened with `NEW`.

A trivial parser: split on `/^### /m`; in each chunk, the text between ```` ```OLD ```` and the
next ```` ``` ```` is the OLD, and between ```` ```NEW ```` and the next ```` ``` ```` is the NEW.
Each OLD is byte-for-byte a substring of `AGENTS.md` and is verified `AGENTS.md`.count(OLD) == 1
below.

## READING PROVENANCE

The numerator moves as graphs land, so every number below quotes its reading. The reading is the
PY-side graphcmp coverage census — `.agents/slop/graphcmp-oracle.py`'s `COVERAGE:` and
`DENOMINATOR:` lines — taken WITHOUT running `bend` (forbidden in this unit):

    env -u PYTHONPATH .venv/bin/python .agents/slop/agendop2/reading.py

which imports that same oracle, makes its one `bend` call vacuous (`emit_bend -> ([],)`, oracle
`main()` line 287), and re-runs `main()`. The coverage numerator (`len(tal)`) and the denominator
(`program_op_split`) are both PY-side and enum-side respectively, so the vacuous bend lane does not
move either. Raw output: `.agents/slop/agendop2/reading.out`.

    # TOTAL: 34 graphs, 386 nodes per side, 70 distinct ops
    # DENOMINATOR: 77 enum members -> 70 PROGRAM OPS (7 excluded by the enum's own markers)
    # COVERAGE: 70 of 70 program ops === 70 of 77 enum members
    #   AND 0 ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised)

Read 2026-10-06 14:16. `SPEC` is unset in the environment, so this is the `SPEC=1` (default)
reading; `SPEC=2`/`SPEC=3` were NOT re-taken (they need `bend`).

---

### R1 — `AGENTS.md:9` (preamble; wrong denominator + stale numerator)

```OLD
census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.
```

```NEW
census from 70 of 70 program ops (70 of 77 enum members; 34-graph corpus, read 2026-10-06 14:16) to 26 of 77 (the enum denominator it was measured against; a 25-graph `SPEC=2` reading, not re-taken) with 14 of 25 graphs failing.
```

---

### R2 — `AGENTS.md:295` (the `SPEC` table cell)

```OLD
MEASURED here on the corpus: `SPEC=1` 61 of 77 ops · `SPEC=2` 26 of 77, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77, all 25 FAIL
```

```NEW
MEASURED: `SPEC=1` 70 of 70 program ops (70 of 77 enum members) on the 34-graph corpus, read 2026-10-06 14:16 · `SPEC=2` 26 of 77 enum members, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77 enum members, all 25 FAIL — the `SPEC=2` and `SPEC=3` rows are 25-graph readings, STALE now that the corpus is 34 graphs, and re-taking them needs `bend`
```

---

### R3 — `AGENTS.md:209` (corpus-size figure, same growth)

```OLD
(`46c52f30d`, TWO FULL 25-GRAPH RUNS)
```

```NEW
(`46c52f30d`, TWO FULL RUNS OF THE THEN-25-GRAPH CORPUS; the corpus is 34 graphs as of 2026-10-06 14:16)
```

---

## VERIFY — every OLD counts exactly once

Run under `.venv/bin/python`; reads `AGENTS.md` READ-ONLY, writes nothing.

```python
t = open('AGENTS.md').read()
olds = [
 'census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.',
 'MEASURED here on the corpus: `SPEC=1` 61 of 77 ops · `SPEC=2` 26 of 77, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77, all 25 FAIL',
 '(`46c52f30d`, TWO FULL 25-GRAPH RUNS)',
]
assert all(t.count(o) == 1 for o in olds), [t.count(o) for o in olds]
```

Measured result: `[1, 1, 1]` — 3 pairs, 3 verified `count == 1`, 0 unmatched.
