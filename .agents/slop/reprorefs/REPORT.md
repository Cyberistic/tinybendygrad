# `checks/repro-paths.py`: the population was a SUFFIX SET, and it wrote false rows in BOTH directions

**2026-10-15.** `checks/repro-paths.py` asks whether every path a committed report tells a reader to
run actually resolves. Its `REF` decided which tokens count, and `REF` was a five-item list of
extensions. This replaces it with a permissive extraction intersected with the filesystem, and reports
what moved.

## The claim, and the denominator, before and after

| | `named` | `resolve` | `DANGLING` | `rc` |
| --- | --- | --- | --- | --- |
| BEFORE — `...[\w./-]+\.(?:sh\|py\|bend\|mjs\|json)` | 559 | 482 of 559 | 77 | 1 |
| AFTER — `...[\w./-]*\.[A-Za-z0-9]+`, then `os.path.exists` | **713** | **605 of 713** | **108** | 1 |

Population: **584 committed `.md` reports** (`git ls-files '*.md'` under `.agents/slop`, `.agents`,
`checks`, `gates`, and the root; the text is read from `git show HEAD:<rel>`, so only committed
bytes count). Over the SAME 584, the permissive pattern **ADDS 164 paths (125 of them RESOLVE) and
LOSES 10**. `164 - 10 = 154 = 713 - 559`. ✓

Extensions of the 164 added: `.rows` 40, `.out` 33, `.txt` 25, `.md` 19, `.tsv` 15, `.err` 5,
`.bin` 4, `.said` 3, `.pyc` 3, none 2, `.patch` 1, `.tramp` 1, `.in` 1, `.FIXED` 1. **The 124 paths
that resolve are real references the instrument could not verify yesterday** — including the two
`--prove` inputs this session moved into `checks/`, `checks/gatesweep-cost.out` and
`checks/gatesweep-run.tsv`, which are `.out`/`.tsv` and were invisible.

## WHY "IT ONLY MISSED THINGS" WAS THE WRONG WORRY

A suffix set does not merely fail to match; it matches **less than the token**, and a prefix of a
path is a different path. It stopped at a REMEMBERED extension instead of at the real one:

- `untrack/REPORT.md:142` names `.../gitinput/__pycache__/blastradius.cpython-312.pyc`. The set
  stopped at `.py` and reported **`...blastradius.cpython-312.py` — a name that never existed — as
  DANGLING.** A false finding. (Three such `.pyc` rows.)
- `whosecache/REPORT.md:73` names `gates/tn_graph_census-gate.py.bak`. The set stopped at `.py` and
  found `gates/tn_graph_census-gate.py`, **A FILE THAT EXISTS — so a broken reference counted as
  RESOLVED.** A false pass, which is the worse of the two.

Both now read correctly (confirmed in the live output: `...312.pyc` is the row, and
`...gate.py.bak` is the row). The replacement is therefore not a widening: it is a **correction whose
net is +31 dangling and +123 resolve**.

## The change, and why it is not another list

```
REF = re.compile(r"(?:^|\s)((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
```

The population is now "tokens under a directory this project owns that name a path", and the
FILESYSTEM decides membership — `os.path.exists` two lines below, which was always the second half of
the test. `PATTERN` still separates a family (`...`, `//`) from a file and is unchanged. Nothing was
added to a list, and the `.txt` special case for `runs/graphcmp/D/` is GONE: `checks/differ.py`'s
`declared()` makes those names a CONTRACT, so a report naming one names a REAL path, and a real path
that exists was never this file's business.

The history is why the list had to go, and it is the same failure three times: the set was
`sh|py|bend`; `.mjs` was ADDED when `checks/e2e.py`'s two `.mjs` stage inputs proved invisible (9 of
15 counted), and **restoring them moved this tool's output by exactly zero**; and the five-item set
was still blind to 164 of 713.

## What was NOT done

**The 108 DANGLING rows are not triaged.** They are not one defect: they are reports naming paths
that are gone (`.py` 33, `.txt` 23, `.bend` 18, `.sh` 13, `.json` 3, `.pyc` 3, `.mjs` 2, `.md` 2,
`.bin` 2, `.bin`-less 2). Some are TRUE — `cstyle-live/port.txt` and `coldness/population.txt` are
reports pointing at files that were moved or pruned. A **5 of 108** subset is noise: three
`__pycache__/*.pyc` and two shadow-tree `...root/.agents` fragments. Triaging 108 rows is its own unit,
and the gate was ALREADY red (77) before this change, so nothing here creates a new failure class.

## Reproduce

```
.venv/bin/python .agents/slop/reprorefs/probe.py            # the differential: OLD vs permissive
.venv/bin/python checks/repro-paths.py                      # the gate, live
```

Artifacts: `.agents/slop/reprorefs/probe.out` (67 lines, the differential), and
`.agents/slop/reprorefs/repropaths-after.out` (222 lines, the gate's output after the change).
`probe.py` SPELLS BOTH PATTERNS, including the replaced one: reading the old pattern out of
`checks/repro-paths.py` would compare the change to itself and print `ADDED 0` — MEASURED, 7 lines,
a green about nothing.

**THE READING IS LIVE AND IT MOVED BY ONE.** Three reads at 2026-10-15T10:20:21Z agree at 125/39; an
earlier read of the SAME code said 124/40, because `os.path.exists` is asked at run time and this
tree is being written by another session. Quote these numbers with their timestamps.

## Flagged, not edited

`AGENTS.md`'s doctrine-1 table row and `.agents/slop/agend2/REPLACEMENTS.md:294` both record
`checks/repro-paths.py`'s `REF` as **fixed** BY the suffix set — `(?:sh|py|bend|mjs|json)` — which is
the claim this measurement refutes. That is a handoff list for the governing doc, and the governing
doc was not edited in this pass.
