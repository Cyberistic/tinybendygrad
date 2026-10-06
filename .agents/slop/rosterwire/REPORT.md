# ROSTER WIRED: `LIVE_UNITS` -> `checks/sweep.py:live_units()`

Rule, now the code: a unit is live iff the newest file under `.agents/slop/<name>/`
is younger than the window. One walk, one level down, no names, no ledger.

## THE CHANGE

- `checks/sweep.py`: the 14-name `LIVE_UNITS` tuple is deleted. `verdict_for`'s
  `LIVE-UNIT` arm now reads `live_units(window)` -- one extra walk per window,
  cached per (minutes, root), the same shape as `live_set` being called once per
  window. `classify` passes its window down; `verdict_for` standalone callers
  (`checks/residue.py`) default to the shipped 60m.
- The load-bearing sentence survives where the tuple used to be AND where the
  rule now lives: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A
  GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."*
- The known limitation is stated in `live_units`' docstring, at the point of the
  rule: an mtime rule cannot see a dispatched-but-not-yet-written unit, so the
  roster is a LOWER BOUND on liveness, not an equality. If a dispatch-time record
  ever appears, the rule becomes `OR` with that record -- a declared input, not a
  tuple. (`checks/residue.py` had already concluded the same thing by hand.)

## PLANT (drives sweep.py itself, three fresh processes, cold cache each)

`.venv/bin/python .agents/slop/rosterwire/plant.py {fresh|aged|restore}`:

```
fresh     live_units(60m) names rosterwire: True   verdict_for(...fresh.md) = LIVE-UNIT
aged      live_units(60m) names rosterwire: False  verdict_for(...fresh.md) = DOC
restore   live_units(60m) names rosterwire: True   verdict_for(...fresh.md) = LIVE-UNIT
```

Aging every newest file under one top-level directory across the window moved
`sweep.py`'s own verdict, and restoring moved it back. The old tuple could not:
its 14 names held 433 files / held 10 stale dirs at 60m, invariant under the
same edit (roster2's plant). First attempt aged only the probe file and taught
us the rule reads the TOP-LEVEL dir's NEWEST file -- then it moved.

## COUNTS, WITH DENOMINATORS

`--plan --windows 60` (same Census shape, same commit basis):

| roster | dirs | files covered | LIVE-UNIT bucket |
|---|---|---|---|
| old tuple `LIVE_UNITS` | 14 names | 433 files | 433 files, 1.2 MB |
| new `live_units(60m)` | 7 dirs | 246 files | 242 files, 0.6 MB |

Denominator: 3,516 rows classified, 3,314 files under `.agents/slop` (one live
walk), 412 top-level dirs / 3,298 files on the roster2 frozen walk. The new
number is smaller because it is TRUE: 10 of the 14 old names sat on cold
directories. It also names dirs the tuple never heard of.

## WALL TIME

| | user | wall |
|---|---|---|
| before (tuple) | 123.6s | 3m34s |
| after (live_units) | 118.8s | 3m23s |

rc=0 both, `--plan`, one process each, nothing else compiling. No regression.

## WHAT BROKE / WHAT I COULD NOT SETTLE

- `.agents/slop/roster2/discover.py:load_tuple()` now AttributeErrors (the
  tuple it read is gone). Its `frozen.rows` and REPORT stand as the measurement
  OF the old tuple; I did not touch it. It now names a population that no longer
  exists in the tree.
- An "about to write" record naming each unit's slop dir does not exist in this
  tree (roster2 says so; `jj workspace list` carries none). Until one appears,
  `live_units` is the lower bound and I did not invent the `OR`.
- `LIVE` differed 201 vs 196 between the two runs -- time drift between two runs
  minutes apart, not the edit; LIVE-UNIT is the edit's number and it moved
  exactly as the plant predicts.
