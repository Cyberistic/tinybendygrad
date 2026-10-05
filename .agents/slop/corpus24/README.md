# corpus24 — classifying the 24 ops the corpus does not reach

One job: for each of the 24 ops outside the `UNION` in `CORPUS.md`, decide which of
three classes it belongs to, and say which class dominates.

- **PORT GAP** — `tinygrad` builds the op, the port has no def for it.
- **CORPUS GAP** — the port HAS the def, no corpus graph reaches it.
- **NOT PORTABLE** — the op has no meaning in this device model.

Method: reproduce the figure with `checks/corpus-figure.py` (the only authority), then
for each op cite the upstream `tinygrad/` `file:line` that DEFINES it, plus the port
side (`.bend` def or its absence) measured by walk. Generated port files are cited by
NAME, never by line. `.agents/slop/differverdict/` and `.agents/slop/xd1/` hold copies
of source trees and are excluded from every walk.