# AGENTS.md op-count replacements — paste-ready

Each OLD below is verified `AGENTS.md`.count(OLD) == 1 (measurement in the VERIFY block at the end).
Each NEW names its denominator (`X of 70 program ops` / `X of 77 enum members`) and, where the number
moves, the reading that produced it. Do not re-derive; paste.

---

## R1 — `AGENTS.md:9` (preamble; wrong denominator + stale numerator)

OLD:
```
census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.
```

NEW:
```
census from 66 of 70 program ops (66 of 77 enum members; 30-graph corpus, read 2026-10-06 13:55) to 26 of 77 (the enum denominator it was measured against; a 25-graph `SPEC=2` reading, not re-taken) with 14 of 25 graphs failing.
```

---

## R2 — `AGENTS.md:295` (the `SPEC` table cell)

OLD:
```
MEASURED here on the corpus: `SPEC=1` 61 of 77 ops · `SPEC=2` 26 of 77, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77, all 25 FAIL
```

NEW:
```
MEASURED: `SPEC=1` 66 of 70 program ops (66 of 77 enum members) on the current 30-graph corpus, read 2026-10-06 13:55 · `SPEC=2` 26 of 77 enum members, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77 enum members, all 25 FAIL — the `SPEC=2` and `SPEC=3` rows are 25-graph readings, STALE now that the corpus is 30 graphs; re-taking them needs `bend`
```

---

## R3 — `AGENTS.md:209` (corpus-size figure, same growth)

OLD:
```
(`46c52f30d`, TWO FULL 25-GRAPH RUNS)
```

NEW:
```
(`46c52f30d`, TWO FULL RUNS OF THE THEN-25-GRAPH CORPUS; the corpus is 30 graphs as of 2026-10-06 13:55)
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

Expected: `[1, 1, 1]`.
