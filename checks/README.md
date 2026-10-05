# checks/ — the gates that live at the top of the tree

`differ.py` drives the `graphcmp` corpus (`.agents/slop/graphcmp.py`): it runs the CPython-vs-
port comparison for every graph, writes every artifact, and then checks that ONE run of that
is reproducible. It is the Python successor of `.agents/slop/graphcmp-run.sh` and
`graphcmp-repro.sh`; both `.sh` files are now `exec` shims that still work, and the shell's
bodies are frozen in `.agents/slop/diffpy/oracle-*.sh` as the oracle the port is diffed
against.

## Run it

```sh
.venv/bin/python checks/differ.py --help     # what each gate claims
.venv/bin/python checks/differ.py run        # every artifact under runs/graphcmp/D
.venv/bin/python checks/differ.py repro      # the gate: two clean runs, byte-compared
.venv/bin/python checks/differ.py snap       # the snapshot both of those are built from
```

`repro` takes `[WAIT_MINUTES]` (default 9) and costs about 20 minutes: it runs the whole
driver twice, and the driver runs `graphcmp.py` 37 times plus a 155-second census.

`run` prints one line — `wrote runs/graphcmp/D` — and the artifacts are the output. Read
`runs/graphcmp/D/D0-run-summary.txt` first: it is the run's verdict, one `key=value` per
line, and it is what `repro` pins.

## The artifacts, by name

| file | what it is |
|---|---|
| `D0-selfcheck.txt` | the differ's own selfcheck; must be `# SELFCHECK: OK` |
| `D1-graph-NAME.txt` | **the per-graph verdict**: one `# VERDICT:` line under one `# DENOMINATOR:` line, so `AGREE` on 2 nodes never prints like `AGREE` on 19 |
| `D1-verdicts.txt` | every graph's verdict ASSERTED against the driver's table |
| `D2-canon-{py,bend}-NAME.txt` | the canonical row stream per side |
| `D2-cmp-NAME.txt`, `D2-bytediff.txt` | py vs bend, byte for byte, with a 0-byte guard |
| `D3-control-NAME.txt` | each side against ITSELF |
| `D4-cross-range.txt` | one graph against a different graph, both sides |
| `D5-plant-NAME.txt` | 7 plants, each of which must DISAGREE and name something |
| `D6-NAME-{ordered,equiv}.txt` | the same reordered fixture under two comparison rules |
| `D7-conf.txt` | 4 conflations |
| `D8-dbg-*.txt` | the DEBUG-level comparison, graph held fixed |
| `D9-stability-NAME-{a,b}.txt`, `D9-stability.txt` | five two-run pairs, and the verdict on each |
| `D10-zerorow-guard.txt` | the 0-row guard, fired on purpose |
| `D0-coverage-census.txt` | the both-sides coverage denominator, with its own `rc=` |
| `D8b-cpython-dbg1-reachability.txt` | whether CPython's own `DEBUG>=1` site is reachable here |
| `D0-ops-probe.txt` | the raw CPython measurements every coverage claim rests on |
| `D0-run-summary.txt` | the run's verdict, and the only file `repro` reads for health |

`*.txt.err` is each step's stderr and is legitimately empty; every other `.txt` must have a
body, or `repro` refuses the run.

## Why these 103 names end in `.txt`, and why that is not `checks/no-txt.py`'s business

`checks/no-txt.py` refuses `.txt` everywhere else in this project and carves out exactly the 103
names in the table above. The reason is that these names are an **output contract between two
drivers**, not constants in one script: `.agents/slop/diffpy/oracle-run.sh` writes all 103 and is
**sha256-pinned** by `differ.py:58`, and `oracle-repro.sh` — pinned the same way — reads
`D0-run-summary.txt` by name at `:61` and globs `*.txt` at `:105`. `checks/corpus-figure.py:72`
reads `D0-run-summary.txt` and refuses on it. **All 103 are named by two or more instruments.**

Renaming them is not merely effortful; it is that **a sha256 over an oracle's BYTES does not cover
the names that oracle READS.** Measured 2026-10-05 in `.agents/slop/difftxt/`, by changing one
extension and nothing else:

| population | `artefacts_ok()` findings | `check_oracle()` |
|---|---|---|
| the tree as it is | **53** | `[]` — PIN INTACT |
| renamed `.txt` → `.rows` | **0** | `[]` — PIN INTACT |
| no files at all | **0** | `[]` — PIN INTACT |

The emptiness guard fell from 53 findings to zero while the pin still certified the oracle, and the
third row is the sharper one: **it reported zero on a directory holding nothing, so the rename only
revealed a guard that was never one.** So `artefacts_ok()` now takes its population from
`differ.declared()` — the generator's own declaration — and reports `MISSING` for a declared
artifact that is absent and `UNEXPECTED` for one no command writes. On the renamed population it
now reports **103 `MISSING`** where it used to report none.

**The carve-out is the declared set, imported — not the directory.** A `.txt` under
`runs/graphcmp/D/` that `differ.declared()` does not name is still reported, by `no-txt.py` and by
`artefacts_ok()` alike, which is the residue case that matters.

## Two things to know before you trust a green run

**`?=0` is not a verdict.** It measures omission — a field that was never filled — so a
graph can be complete and still wrong. `lin` and `loop` DISAGREE on purpose, for named
measured causes, and that is the healthy state, not a bug to fix.

**The run is only reproducible under a settled substrate.** `bend --check-only` EXITS 1 on a
clean file (`dtype.bend`'s 14 permanently-red laws), so `repro` reads its FIRST LINE and never
its exit status. `repro` waits for `ALL PROOFS CHECK` before it starts and re-reads the
summary afterwards; if the substrate moved mid-run, the summary's `rc=` and
`oracle-selfcheck` pins say so.

See `.agents/slop/DIFFPY.md` for the port, its measured agreement with the shell, and the
pins.

## `checks/residue.py` — a second opinion on `sweep.py`'s DELETE bucket

`checks/sweep.py` sorts the residue into four buckets and acts on three. `checks/residue.py`
**consumes `sweep.verdict_for()` and never replaces it**, and exists because `DELETE` is
`verdict_for`'s *default* rather than a verdict: it is reached whenever `PROTECTED`,
`LIVE_UNITS`, `ORACLE_WORD` and the citation test all decline to fire, so every "I am not sure"
leaks into the only bucket `--apply` destroys.

    .venv/bin/python checks/residue.py                  # classify, write the report, act on nothing
    .venv/bin/python checks/residue.py --plant          # assert every verdict on a synthetic tree
    .venv/bin/python checks/residue.py --disarm NAME    # plant again with one resolver OFF; a pass is exit 3

The three positive questions are `AUTHORED` (does a naming authority **render** this name —
`differ.declared()`, the same call `checks/no-txt.py` already makes), `LIVE` (is a **directory**
being written, measured per directory so no roster can go stale), and `DERIVED` (regenerable by
construction). Everything a test cannot answer is **`UNKNOWN`, which is reported, never acted on,
and carries the `needs=` that would settle it.** `UNNAMED` is the only deletion *candidate* and is
explicitly not a verdict.

**MEASURED, and the reason to read the report rather than the bucket count: 181 of the residue's
rows are rendered by `checks/differ.py` out of `declared()` and are visible as a literal token in
`checks/` + `gates/` exactly once.** The corpus indexes literal tokens; the project's naming
authority constructs names. **The DELETE bucket is a count of files unreferenced by the INSTRUMENT,
not a count of junk.**

**Its own output is excluded from its own citation corpus, by a belt.** `000-the-residue.md` names
every residue row by path, so a bare `git add` of it made the next run find every row cited by this
check's own report. `--plant` builds a `git init`ed temp tree with `os.utime` ages and a
hand-written expectation column, and `--disarm` requires each of the eight branches to MOVE.
