# THE ROSTER, REPLACED BY A TREE PROPERTY

Instrument: `.agents/slop/roster2/discover.py`. Reproduce:

```
.venv/bin/python .agents/slop/roster2/discover.py --snap          # freeze the walk to frozen.rows
.venv/bin/python .agents/slop/roster2/discover.py --from .agents/slop/roster2/frozen.rows
.venv/bin/python .agents/slop/roster2/discover.py --plant --from .agents/slop/roster2/frozen.rows
```

## THE RULE, AS A TREE PROPERTY

> A unit is LIVE iff the NEWEST file under `.agents/slop/<name>/` is younger
> than the window. Nothing names a unit. The roster is a DERIVED VIEW of mtimes,
> and the walk is the population.

This is doctrine 1 in its own wording: the population is a **directory walk**
(`os.walk` over `.agents/slop`, one level down), not a basename shape, not a
suffix set, not a hand list. `checks/residue.py:232` already uses exactly this
(`sweep.live_set`, per-file mtime) and excludes by it; `discover.py` lifts the
same predicate one level, to the directory, which is where `LIVE_UNITS` made
its false claim. No ledger is needed: the input is the tree itself, and
`--snap`/`--from` make it reproducible — the reference clock travels in the
snapshot's first line, so a run is a function of ONE file, not of when you
looked.

## PLANT

`--plant` edits exactly one field of the frozen input: the newest mtime of one
directory moves from <60m to 180m. The rule's answer must move, and it does:

    roster(60m): 1 dirs covering 1 file -> 0 dirs covering 0 files; the edited
    directory leaves the roster. LIVE_UNITS: still 14 names, unchanged.

A rule invariant under its own condition is a label (clause II, and G8: its
disarm moved the count by 0 at every window). This one moves. Plant: PASS.

## MEASURED AGAINST THE CURRENT TREE

One frozen walk, `--from frozen.rows`, now=1791273838: **412 top-level
directories, 3,298 files** — the denominator, quoted with the walk that
produced it. (`.agents/slop` only; `sweep.py`'s 4,455-file census also walks
`runs/` and was not the population here.)

| window | rule names | files covered | tuple also names | tuple stale | rule-only dirs |
|---|---|---|---|---|---|
| 0m | 0 | 0 of 3298 | 0 | 10 | 0 |
| 60m | 1 | 1 of 3298 | 0 | 10 | 1 |
| 1440m | 344 | 3222 of 3298 | 10 | 0 | 334 |

Three measured facts:

1. **The tuple is stale right now.** At the shipped 60m window, 10 of the 14
   `LIVE_UNITS` names sit on directories whose newest file is already cold —
   the second belt cannot see what its own tree is doing.
2. **The tuple is blind right now.** At 60m the rule names 1 directory the
   tuple has never heard of; at 1440m, 334 of 344 live-by-mtime directories.
   The 14-name tuple has been wrong four times because it is a snapshot of
   somebody's dispatch order, and dispatch order churns.
3. **The rule needs no entries because it IS the tree's own declaration of
   recentness.** `.gitignore` was measured by the dead agent's
   `roster.measure.py` to be a declaration of intent and says "never track",
   not "alive now" — a different sentence. A citation index is not available:
   three times this session a citation index built over a tree containing the
   instrument cited the instrument itself. jj workspace descriptions name a
   source edit, not a slop directory.

## WHAT THIS RULE CANNOT SEE — MEASURED, NOT ASSUMED

A unit that has been dispatched but has not yet WRITTEN its first file. At
w=0m the rule names 0 directories while house rules say 21 units were running.
That is the entire justification `LIVE_UNITS` ever had, and it is real. But the
tree property that would carry it — a dispatch-time record naming each unit's
slop directory — does not exist in this tree, and is exactly what a hand tuple
was doing badly. The rule's contract is therefore: **live means has-written-
recently**, and "about to write" is out of census until the first write,
visibly (the w=0 column is printed next to the w=60 column for precisely this
reason), rather than invisibly (a tuple nobody updates).

## WHAT I COULD NOT SETTLE

Whether some out-of-tree dispatch record names the running units. I have no
source for one; `jj workspace list` was checked (dead agent's measurement,
candidate (c)) and carries no mapping to `.agents/slop/<name>/`. If such a
record appears, the rule becomes an `OR` — has-written-recently OR declared-
dispatched — with the record as a second, declared input, not a tuple.

## WHY NOT THE OTHER CANDIDATES (measured by the dead agent, re-cited)

- (b) `.gitignore`: a declaration of intent, not of liveness — every live
  unit's directory is tracked (`roster.measure.py`).
- (c) jj workspace descriptions: name a source edit, not a slop directory.
- (d) citation index: cited the instrument itself, three times this session.
- G8 (`g8.count.py`): dead as stated — disarm moved the count by 0 at 0/60/
  1440m; structural, not fixable by a plant, because the corpus filter already
  excludes the byte-copies G8 would ask about.
