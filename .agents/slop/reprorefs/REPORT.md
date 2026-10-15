# `checks/repro-paths.py`: the population was a SUFFIX SET, and its denominator asked the INDEX

**2026-10-15, HEAD `db24cf3d0`.** `checks/repro-paths.py` asks whether every path a committed report
tells a reader to run actually resolves. Two defects were fixed in it, and the second was found by the
first.

## Defect 1 — the population was a five-item SUFFIX SET

It was replaced with a permissive extraction intersected with the filesystem.

| | `named` | `resolve` | `DANGLING` | `rc` |
| --- | --- | --- | --- | --- |
| BEFORE — `...[\w./-]+\.(?:sh\|py\|bend\|mjs\|json)` | 560 | 483 of 560 | 77 | 1 |
| AFTER — `...[\w./-]*\.[A-Za-z0-9]+`, then `os.path.exists` | **714** | **606 of 714** | **108** | 1 |

Population: **541 `.md` files at HEAD**. Over the SAME 541, the permissive pattern **ADDS 164 paths,
125 of which RESOLVE, and LOSES 10**. `714 - 560 = 154 = 164 - 10`. ✓

Extensions of the 164 added: `.rows` 40, `.out` 33, `.txt` 25, `.md` 19, `.tsv` 15, `.err` 5,
`.bin` 4, `.said` 3, `.pyc` 3, none 2, `.patch` 1, `.tramp` 1, `.in` 1, `.FIXED` 1. The 125 that
resolve are real references that could not be verified before, including the two `--prove` inputs
moved into `checks/` this session, `checks/gatesweep-cost.out` and `checks/gatesweep-run.tsv`.

### WHY "IT ONLY MISSED THINGS" WAS THE WRONG WORRY

A suffix set does not merely fail to match; it matches **less than the token**, and a prefix of a path
is a different path. It stopped at a REMEMBERED extension instead of the real one, and wrote false
rows in **both** directions:

- `untrack/REPORT.md:142` names `.../gitinput/__pycache__/blastradius.cpython-312.pyc`. The set
  stopped at `.py` and reported `...blastradius.cpython-312.py` — **a name that never existed — as
  DANGLING.** (Three such `.pyc` rows.)
- `whosecache/REPORT.md:73` names `gates/tn_graph_census-gate.py.bak`. The set stopped at `.py`, found
  `gates/tn_graph_census-gate.py`, **A FILE THAT EXISTS — so a broken reference counted as RESOLVED.**
  The false pass is the worse of the two.

Both now read correctly. The replacement is therefore not a widening but a **correction whose net is
+31 dangling and +123 resolve**, and nothing was added to a list. The `.txt` carve-out for
`runs/graphcmp/D/` went with it: `checks/differ.py`'s `declared()` makes those names a CONTRACT, and a
real path that exists was never this file's business.

The history is why the list had to go, and it is the same failure three times: the set was
`sh|py|bend`; `.mjs` was ADDED when `checks/e2e.py`'s two `.mjs` stage inputs proved invisible (9 of
15 counted), and **restoring them moved this tool's output by exactly zero**; and the five-item set
was still blind to 164 of 714.

## Defect 2 — the DENOMINATOR asked the INDEX while the EVIDENCE came from HEAD

Found by the first, because the corrected tool printed **541** reports where every number above had
been measured against **584**. `committed_reports()` ran `git ls-files`, which reads the git **INDEX**,
and then took the text from `git show HEAD:<rel>`. So:

- the population moved with the index's **arming state** — 584 while the default index carried 462
  `jj` intent-to-add placeholders, 541 once it agreed with HEAD — while the word printed was
  *committed*;
- and it **inherited `GIT_INDEX_FILE`**, so an agent that commits the prescribed way
  (`GIT_INDEX_FILE=.git/agent-index`) ran a different population than one that did not. **That is the
  same defect and the same shape as `checks/index-arm-gate.py`'s false `PASS`** — an instrument that
  reads whatever the shell happens to point it at.

**FIXED to `git ls-tree -r --name-only HEAD`**, which is what `git show HEAD:` reads. HEAD is not a
shell variable, so nothing needs scrubbing, and the denominator and the evidence are now the same
source by construction. MEASURED 2026-10-15T10:27:04Z: **541 under the default index, under
`GIT_INDEX_FILE=.git/agent-index`, and under a bogus path that exists nowhere** — three shells, one
number — and `541` equals `git ls-tree -r --name-only HEAD | grep -c '\.md$'`.

**The differential above is unaffected by the 43 phantom entries**, because their `git show HEAD:`
fails and they contribute no tokens — which is also why the defect hid: the denominator was wrong and
the findings were right. The first commit's message quotes 584 for that reason, and this note is the
correction.

## What was NOT done

**The 108 DANGLING rows are not triaged.** They are reports naming paths that are gone: `.py` 33,
`.txt` 23, `.bend` 18, `.sh` 13, `.json` 3, `.pyc` 3. Some are TRUE — `cstyle-live/port.txt` and
`coldness/population.txt` are reports pointing at files that were moved or pruned. A **5 of 108**
subset is noise: three `__pycache__/*.pyc` and two shadow-tree `...root/.agents` fragments. Triaging
108 rows is its own unit, and the gate was ALREADY red (77 → 108 is a correction, not a new failure
class).

## Reproduce

```
.venv/bin/python .agents/slop/reprorefs/probe.py     # the differential: OLD vs permissive
.venv/bin/python checks/repro-paths.py               # the gate, live
```

`probe.py` SPELLS BOTH PATTERNS, including the replaced one: reading the old pattern out of
`checks/repro-paths.py` would compare the change to itself and print `ADDED 0` — MEASURED, 7 lines, a
green about nothing. Artifacts: `probe.out` (67 lines) and `repropaths-after.out` (222 lines).

**THE READING IS LIVE AND IT MOVES.** Three reads at 10:20:21Z agreed at 125/39 after an earlier read
of the SAME code said 124/40, because `os.path.exists` is asked at run time in a tree another session
is writing; and the absolute counts moved by one more when HEAD advanced. Quote these with their
timestamps.

## Flagged, not edited

`AGENTS.md`'s doctrine-1 table row and `.agents/slop/agend2/REPLACEMENTS.md:294` both record
`checks/repro-paths.py`'s `REF` as **fixed** BY the suffix set — `(?:sh|py|bend|mjs|json)` — which is
the claim defect 1 refutes. That document was not edited in this pass.
