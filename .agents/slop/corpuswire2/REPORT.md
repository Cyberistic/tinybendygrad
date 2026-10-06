# Corpus wire 2: the 34/20 gap, the health gate that could not see it, and the smallest change that makes it fail

Measured 2026-10-06 14:19 (+0300), `HEAD` `c0d2689e7`, **no `bend` run**. **THE TREE IS MOVING**
— `checks/differ.py` was rewritten at 14:18:33 while this report was being taken, and
`.agents/slop/graphcmp.bend` at 14:08:30. Every number below carries the artifact it was read
from.

```
78e0c0d620f6…  checks/corpus-figure.py   (this unit's only edit)
e88753d952fc…  checks/differ.py          (mtime 14:18:33; WANT and PINS UNCHANGED by that edit)
47a48d65f134…  .agents/slop/graphcmp.py  (mtime 13:58:00; 34 graphs)
1b8d86e356f5…  .agents/slop/graphcmp.bend (mtime 14:08:30)
runs/graphcmp/D/D0-run-summary.txt       (mtime 12:50:21; a 25-graph run)
```

---

## 1. The gap, BY NAME, and each name's bend-arm status

Definitions, all by discovery (no number typed; `armcensus.py` reads each source):

| population | source | `file:line` | count |
|---|---|---|---|
| corpus | `graphcmp.GRAPHS` | `.agents/slop/graphcmp.py:1590` | **34** |
| table | `differ.WANT` | `checks/differ.py:124` | **20** |
| arms | `rows.pick3` rungs | `.agents/slop/graphcmp.bend:1421` | **26** |

`WANT ∖ GRAPHS = ∅`. `GRAPHS ∖ WANT = 14`:

| graph | bend arm? |
|---|---|
| `alu` `bit` `bw` `getaddr` `move` `mulacc` `threefry` `unshard` `where` `wmma` | **ARMED** (10) |
| `custom_function` `mselect` `mstack` `stage` | **NO ARM → falls through to `g_matmul()`** (4) |

The dispatcher's bottom rung is `g_matmul()` (`graphcmp.bend:1448`), so an unarmed graph is
rendered with MATMUL's nodes — a disagreement of the DISPATCHER, not the port
(`graphcmp.bend:1458-1464`). Over the WHOLE corpus, 8 graphs are unarmed: the 4 above plus
`allred` `cdiv` `late` (in `WANT` as `DISAGREE`, the matmul substitution) and `matmul` itself
(the default).

The brief's "a prior unit armed five; another is arming three more; three may still substitute"
does not match the tree as measured at 14:19: **ten** of the gap are armed (the five
`threefry mulacc getaddr unshard wmma` plus the five old-unset `alu bit bw move where`) and
**four** still substitute. `armcensus.out` is the reading.

---

## 2. THE CENTRAL QUESTION: (a), a NEW condition that compares the corpus to the artifact

Chosen: **(a)**, because the corpus size is a DISCOVERY (doctrine 1), not a fact about the port
or the run.

- **(b) a `differ.py` `PINS` row** — bumping `"graphs"` `"25"`→`"34"` at `checks/differ.py:221`
  goes red once, then rots on the next growth exactly as it rotted here. **A SECOND HAND
  LITERAL IS THE SAME DEFECT ONE COMMIT LATER.** It is also another unit's file (read-only
  to this unit).
- **(c) a measured refusal** — the same as (a) framed as an exit status; (a) already carries
  the rc through `main`'s existing `and health_ok` (`checks/corpus-figure.py:279`).
- **(a)** — `run_health` already holds the summary and imports `differ.PINS`; `main` already
  holds `gc`. So the corpus size is read from the SAME generator `differ.corpus()` reads
  (`checks/differ.py:106-110`), and compared to the artifact's `graphs=`.

**The line the figure could not fail: `checks/corpus-figure.py:176-177`** — the old
`red = [... for k in pins ...]` consulted the literal `PINS["graphs"]="25"` against a summary
that also said `25`, so the two agreed and the gap never entered `red`. `main:279`'s
`and health_ok` was green over a nine-graph gap.

---

## 3. The landing, failing on the live tree and passing where they agree

Edit: `checks/corpus-figure.py` only (diff reviewed; signature `run_health(declared: int)`,
call `run_health(len(gc.GRAPHS))` at `:256`). `graphs` is removed from the pinned set and
compared to the LIVE corpus; a stale artifact is named:

```
RED  (live):  RUN HEALTH : **FAILED** -- 16 of 17 pins green. RED: graphs=25 but the corpus
              DECLARES 34 -- the ARTIFACT and the CORPUS disagree, so the health gate is
              reading a stale run.
              rc=1
```

`plant.py` builds two throwaway roots (copies of `corpus-figure.py`/`devpin.py`/`differ.py`,
a symlink to the real `.agents/`, their own summary) and varies exactly `graphs=`:

```
RED STATE   (artifact graphs=25, corpus declares 34): rc=1  <- as above
GREEN STATE (artifact graphs=34, corpus declares 34): rc=0
  RUN HEALTH : OK -- 17 of 17 pins green (… plus `graphs` COMPARED TO THE CORPUS; `graphs=34` …)
PLANT: TWO STATES DISTINGUISHABLE
```

`runs/graphcmp/D/` is asserted unmutated before and after. **THE HONEST ANSWER: the gate is
RED now and MUST STAY RED until a run writes `graphs=34`.** A gate red for a true reason is
doing its job; the previous green was the defect.

**Consequence to flag:** `.agents/slop/figure2/plant.py` builds its "real" state from the
recorded summary and expects `rc=0`; that premise is now (correctly) false, so that scratch
plant will fail until the run catches up. Its green string is otherwise preserved
(`OK -- 17 of 17 pins green`), so only the stale-artifact premise breaks it.

---

## 4. What `differ.py:221`'s `PINS` must become

`checks/differ.py:221` is read-only to this unit; it is still consumed by `differ.unhealthy()`
(`:789`) and `gates/retention-check.py`, so it must be reported even though this unit derived
around it in `corpus-figure.py`.

| key | old | new | knowable now? |
|---|---|---|---|
| `graphs` | `25` | **`34`** | yes — `len(corpus())` |
| `graphs-unset` | `5` | **`14`** (unwired) · `9` (the five wired) · `5` (nine wired) | yes — `corpus()∖WANT` |
| `graphs-answered` | `20` | **`20`** · `25` · `29` (same three cases) | yes — `corpus()∩WANT` |
| `graphs-agree` | `21` | **UNKNOWN until the run** | no — a port property |
| `byte-identical` | `21` | **UNKNOWN until the run** | no — a port property |
| `expect-moved`, `not-comparable` | `0` | stays `0` (zero-tolerance invariants) | yes |

`graphs-agree` and `byte-identical` are over ALL 34 graphs (unset included, `differ.py:560-562`),
so they are not guesses from the 25-graph run and are not computable from the corpus. **Say
"unknown until the run" and stop.**

---

## 5. `env-precond.py:327`'s fallback

`checks/env-precond.py:327`:

```python
real = SUMMARY.read_text() if SUMMARY.exists() else "graphs=25\n"
```

**Do NOT move it to `34`.** It is a placeholder for the `--plant`'s fabricated tree that is
read by NO asserted path: `check()` reads only `RECORD_KEYS = ("dev","pythonhashseed","noopt",
"lc_all")` (`:122`, `:239`), and `graphs` is not one of them, so the literal is inert. `34`
would only refresh an inert lie in the corpus-literal class this whole task is about. The
clean value is `""` — or, if a line is wanted, derived from the corpus. Nothing depends on it.

---

## 6. The plant, counts with denominators, and the reading

Artifacts (all under `.agents/slop/corpuswire2/`, no `.txt`):

```
live-before.out   before the edit: graphs declared 34, RUN HEALTH OK, rc=0   (the defect)
live-after.out    after: 16 of 17 pins green, RED names the corpus/artifact gap, rc=1
plant.out         RED rc=1 / GREEN rc=0, TWO STATES DISTINGUISHABLE
armcensus.out     corpus 34, WANT 20, gap 14 (10 armed, 4 substitute), 26 rungs
plant.py          the two-state driver (copies; runs/graphcmp/D/ asserted unmutated)
armcensus.py      the gap + arm census, by discovery
```

Counts and denominators, with the reading:

| claim | numerator / denominator | source (reading) |
|---|---|---|
| corpus | 34 | `graphcmp.GRAPHS`, sha `47a48d65…`, mtime 13:58 |
| in `WANT` | 20 / 34 | `checks/differ.py:124`, sha `e88753d9…`, mtime 14:18 |
| the gap | 14 / 34 (10 armed, 4 substitute) | `graphcmp.bend` sha `1b8d86e3…`, mtime 14:08 |
| artifact's corpus | 25 | `runs/graphcmp/D/D0-run-summary.txt`, mtime 12:50 |
| health conditions | 17 (16 non-`graphs` pins + 1 derived `graphs`) | `checks/corpus-figure.py` |
| live verdict | `FAILED`, 16 / 17 green, rc=1 | `live-after.out` |
| plant | RED rc=1, GREEN rc=0 | `plant.out` |

**THE READING: the artifact is a 25-graph run (12:50) against a 34-graph corpus (13:58+).**
The gate now names that gap instead of counting the pins the artifact and the instrument
share. It stays red until the next run writes `graphs=34`, at which point §4's
`graphs-agree`/`byte-identical` become readable and are the ONLY pins still unknown.
