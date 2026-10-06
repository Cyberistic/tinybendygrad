# flagtable — the 146-row flag table, verified against the port's own source

**THE UNIT THAT MADE THIS MEASUREMENT DIED ON A RATE LIMIT BEFORE IT COULD WRITE THIS FILE.
EVERY NUMBER BELOW COMES FROM THE ARTIFACT IT LEFT, `.agents/slop/flagtable/results.json`
(46 KB, `summary` + `agrees` + `disagrees` + `unverifiable`), AND THE SPOT-CHECKS MARKED
"HAND-CHECKED" WERE RE-DERIVED BY THE ORCHESTRATOR FROM `tinygrad/`. NOTHING HERE IS
REMEMBERED.**

## The headline

```
total 146   agrees 105   disagrees 27   unverifiable 14
```

`AGENTS.md`'s audit named this as **"the largest unverified block in the file"** — an earlier
revision spot-checked only `SPEC`. **27 of 146 rows assert a default the port's own source
contradicts, and 14 more cannot be checked from this tree at all.**

## The 27 disagreements, each with its source location

| flag | table says | source says | where |
|---|---|---|---|
| `BEAM_UOPS_MAX` | 1500 | **3000** | `tinygrad/codegen/opt/search.py:68` |
| `BEAM_TIMEOUT_SEC` | — | **10** | `tinygrad/codegen/opt/search.py:59` |
| `BEAM_MIN_PROGRESS` | — | 0.01 | `tinygrad/codegen/opt/search.py:118` |
| `BEAM_MAX_TASKS_PER_CHILD` | — | 16 | `tinygrad/engine/worker.py:47` |
| `BEAM_PADTO` | — | 0 | `tinygrad/codegen/opt/search.py:18` |
| `BEAM_STRICT_MODE` | — | 0 | `tinygrad/codegen/opt/search.py:75` |
| `BEAM_DEV_TIMEOUT` | — | 1 | `tinygrad/codegen/opt/search.py:145` |
| `CACHEDB` | — | computed path | `tinygrad/helpers.py:402` |
| `XDG_CACHE_HOME` | std | `~/Library/Caches` / `~/.cache` | `tinygrad/helpers.py:401` |
| `MV_BLOCKSIZE` | — | 4 | `tinygrad/codegen/opt/heuristic.py:61` |
| `MV_THREADS_PER_ROW` | — | 8 | `tinygrad/codegen/opt/heuristic.py:61` |
| `MV_ROWS_PER_THREAD` | — | 4 | `tinygrad/codegen/opt/heuristic.py:61` |
| `EXPAND_SSA` | — | 0 | `tinygrad/renderer/cstyle.py:253` |
| `REWRITE_DATA` | — | `""` | `tinygrad/uop/ops.py:1761` |
| `PROFILE_DATA` | — | `""` | `tinygrad/uop/ops.py:1762` |
| `REMOTE_TIMEOUT` | — | 60 | `tinygrad/runtime/support/system.py:391` |
| `HCQ2` | — | 1 | `tinygrad/helpers.py:248` |
| `HCQ_VISIBLE_DEVICES` | — | `""` | `tinygrad/runtime/support/system.py:12` |
| `ROCM_PATH` | — | `/opt/rocm` | `tinygrad/runtime/support/compiler_amd.py:102` |
| `AMD_AQL` | — | `int(self.xccs > 1)` | `tinygrad/runtime/ops_amd.py:883` |
| `AMD_KFD_QUEUE_PRIORITY` | — | 7 | `tinygrad/runtime/ops_amd.py:687` |
| `WAVES_PER_SH` | — | 0 | `tinygrad/runtime/ops_amd.py:423` |
| `SQTT_BUFFER_SIZE` | — | 256 | `tinygrad/runtime/ops_amd.py:905` |
| `MAX_SQTT_PKTS` | — | 50_000 | `tinygrad/viz/serve.py:536` |
| `PMC_COUNTERS` | — | `pmc_default` | `tinygrad/runtime/ops_amd.py:913` |
| `AM_RESET` | — | 0 | `tinygrad/runtime/support/am/amdev.py:183` |
| `EMULATE` | — | `""` | `tinygrad/runtime/ops_null.py:65` |

**HAND-CHECKED, BOTH DIRECTIONS, AND BOTH CONFIRM:**
- **`BEAM_UOPS_MAX`** — `search.py:68` reads `(uops_max:=getenv("BEAM_UOPS_MAX", 3000))`.
  **THE TABLE SAYS 1500. THAT IS A WRONG NUMBER, NOT A MISSING ONE.**
- **`BEAM_TIMEOUT_SEC`** — `search.py:59` reads `signal.alarm(getenv("BEAM_TIMEOUT_SEC", 10))`.
  **THE TABLE SAYS `—`, WHICH CLAIMS NO DEFAULT EXISTS.**

## The 27 are not one kind of error, and collapsing them would be the next stale number

1. **A WRONG NUMBER (1 of 27).** `BEAM_UOPS_MAX` states 1500 where the source states 3000. This is
   the only row where the table gives a *value* the source contradicts.
2. **A MISSING DEFAULT (21 of 27).** The table's `—` claims no default; the source has a concrete
   one (`10`, `0.01`, `16`, `4`, `8`, `256`, `50_000`, `/opt/rocm`, …). **`—` is not "unknown", it
   is "I did not look", and the README for this table says the column is the *default*.**
3. **AN EMPTY-OR-COMPUTED DEFAULT (5 of 27).** `REWRITE_DATA` `""`, `PROFILE_DATA` `""`,
   `HCQ_VISIBLE_DEVICES` `""`, `EMULATE` `""`, `CACHEDB`/`XDG_CACHE_HOME` computed paths. **These
   are the rows where `—` is DEFENSIBLE** — an empty-string default and "unset" are hard to
   distinguish at the call site. **Flagged rather than overwritten: "fixing" them to `""` would
   trade one imprecision for another.**

## The 14 unverifiable — `SKIP`, NOT `PASS`

`NOLOCALS` · `JIT_BATCH_SIZE` · `PCONTIG` · `GRAPH_ONE_KERNEL` · `BROWSER` · `THREADS` ·
`APL_REMOTE_SOCK` · `TINYFS_ENDPOINT` · `TINYFS_TIMEOUT` · `ASYNC_COPY_WORKERS` ·
`HCQDEV_WAIT_TIMEOUT_MS` · `AMD_SDMA_BIND` · `FIX_METAL_ICB` · `MLX_IP`

**NO `getenv` DECLARATION WAS FOUND FOR THESE IN THIS TREE.** They are named nowhere, or their
default is not a literal a parser can read. **They are counted as `unverifiable` and NOT as
`agrees` — a table row nobody checked is not a row that checked out.**

## Reproduce

```
.venv/bin/python .agents/slop/flagtable/parse_table.py      # -> table_rows.json
.venv/bin/python .agents/slop/flagtable/find_decls.py       # -> declarations.json
.venv/bin/python .agents/slop/flagtable/compare.py          # -> results.json
.venv/bin/python .agents/slop/flagtable/read_coverage.py    # -> read_coverage.json
```

`declarations.json` carries each flag's `file`, `line` and `default_expr`; `results.json` carries
`flag`, `alias`, `table_default`, `source_default`, `source_file`, `source_line`, `section`,
`table_line`, `agreement`, `note`. **THE POPULATION IS DISCOVERED FROM `AGENTS.md`'S OWN TABLE ROWS
(146) AND THE SOURCE SIDE IS DISCOVERED FROM `tinygrad/`'S OWN `getenv` CALLS — NOT FROM A LIST.**

## What was NOT done

- **`AGENTS.md` WAS NOT EDITED BY THIS UNIT** (it was read-only for it). The correction is a
  separate commit; this table is the input to it.
- **`read_coverage.py` / `read_coverage.json`** were written at `11:26`, after `results.json`
  (`11:16`) — a second measurement of which flags the port actually READS. **Its numbers are not
  summarised here because the unit died before it could state them, and I will not quote an
  artifact I have not read.**
