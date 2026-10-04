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
