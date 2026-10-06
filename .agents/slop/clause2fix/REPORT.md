# CLAUSE II FIX — retention-check.py

## The defect
Clause II's measure was a LINE measure of a STRUCTURAL property: `writer_exits`
counted `return`s after the first `self.dir` attribute reference. Measured by
`.agents/slop/slopfinal/clause2.py`: delete the `finally` from `Gate.run()` and the
line measure does NOT move (11/13 → 11/13). A clause invariant under the change it
claims to measure is not a clause.

## The fix
`writer_exits` in `gates/retention-check.py` now yields, for every `return` in
`Gate.run()`, the depth of the innermost cleanup `try` enclosing it (depth > 0),
excluding nested scopes. An exit counts COVERED iff it is at depth > 0 inside a
`try` whose `finalbody` is non-empty, or it follows that `try` in the same body
(the finally has already run on it). One comprehension feeds the count; no new
module; depth, not id-keyed containment (which `clause2.py` showed is unsound —
`ast.Load` nodes are interned, so a set of ids answers TRUE for returns below the
`finally`).

## The plant, against the real gate
- intact tree:        `II OK    gates/gatekit.py: 0/13 exits NOT covered by a cleanup 'finally'`
- finally DELETED (in-memory rewrite via `clause2.break_the_finally`, tree restored after):
                      `II FALSE gates/gatekit.py: 13/13 exits NOT covered by a cleanup 'finally'`
- restored:           `II OK    gates/gatekit.py: 0/13 ...`  (git diff: gatekit.py unmodified)

The new measure moves (0 → 13) where the line measure did not (11 → 11). It is a clause.

## retention-check.py verdict, before vs after (NOT our change)
- BEFORE: `II FALSE ... 11/13 exits after the first write`, `IV FIRES runs/graphcmp/D/`
  (4 complaints), exit RED.
- AFTER:  `II OK ... 0/13`, `IV FIRES runs/graphcmp/D/` UNCHANGED, exit RED.
- Clause IV still fires on stale `runs/graphcmp/D` artifacts (`expect-moved=1`,
  `graphs-agree=20 (expected 19)`, `selfcheck=FAIL`). That is pre-existing and is
  attributed to stale corpus artifacts, not to this change.

## New count and denominator (clause II)
Covered exits in `Gate.run()`: **12 inside the cleanup `try` + 1 after it = 13/13,
0 uncovered.** Denominator: 13 `return` exits in `run()`.
