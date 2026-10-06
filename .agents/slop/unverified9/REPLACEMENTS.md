# Paste-ready `AGENTS.md` corrections for the flag-table header and the 14 rows

**Moment: 2026-10-06 ~13:10 +0300. Every OLD below is the CURRENT `AGENTS.md` text (grep-verified
this run); the `flagtable/table_rows.json` line numbers are stale.**

---

## 1. THE HEADER SENTENCE (`AGENTS.md:281-283`) — the one owed correction

The table's header names neither of the two ways a `Default` cell can carry *no literal*, and
the two are **doing different jobs in the same column**: `—` (which `flagtable-rows` keeps for
eight rows on purpose) and the `flagtable` verdict `UNVERIFIABLE` (which keeps fourteen rows as
unchecked). A reader cannot tell them apart today.

**OLD (`AGENTS.md:281-283`):**
```
Tinygrad Flags

Most important ones are DEBUG and VIZ. You can mock hardware with DEBUG.
```

**NEW:**
```
Tinygrad Flags

Most important ones are DEBUG and VIZ. You can mock hardware with DEBUG.

The `Default` column is the value the source passes when the variable is unset: a `—` there means
the default is the empty string, a computed path, or a variable name and cannot be written as a
literal — it is NOT "no default"; and a row whose flag is named nowhere in this tree (no
`getenv`, no mention) is `UNVERIFIABLE` — a transcription, not a reading, and never counted as
checked out.
```

*(One sentence, as asked; the em-dash clause separates the two meanings — `—` is a stated shape,
`UNVERIFIABLE` is an absent measurement.)*

---

## 2. The 14 rows — **no cell value is wrong; no OLD/NEW is owed**

Rule: `git grep -n -w -F -e FLAG` over tracked files minus `AGENTS.md`/`.agents/` (`gather.json`).

- **4 rows are RIGHT and were mislabelled `UNVERIFIABLE`**, because `flagtable` looked only in
  `tinygrad/` and these live in `extra/`:

  | flag | `AGENTS.md` cell | tree `file:line` | match |
  |---|---|---|---|
  | `APL_REMOTE_SOCK` | `temp path` | `extra/hcq1/remote.py:128` `getenv("APL_REMOTE_SOCK", temp("tinygpu.sock"))` | ✓ |
  | `HCQDEV_WAIT_TIMEOUT_MS` | `30000` | `extra/hcq1/hcq.py:255` `getenv("HCQDEV_WAIT_TIMEOUT_MS", 30000)` | ✓ |
  | `AMD_SDMA_BIND` | `0` | `extra/hcq1/ops_amd_old.py:513` `getenv("AMD_SDMA_BIND", 0)` | ✓ |
  | `MLX_IP` | `10.0.0.1` | `extra/mlx_driver/loopback.py:15`, `mlxdev.py:106` `getenv("MLX_IP", "10.0.0.1")` | ✓ |

  Their **cells** are correct, so they need no edit in `AGENTS.md`; the wrong spelling is in the
  *ledger* (`flagtable/results.json` calls them `UNVERIFIABLE`), not in the table.

- **10 rows cannot be refuted by this tree** (0 in `tinygrad/`, 0 in the port): `GRAPH_ONE_KERNEL`,
  `BROWSER`, `THREADS` are named only as CI-set / prose / a local variable, and `NOLOCALS`,
  `JIT_BATCH_SIZE`, `PCONTIG`, `TINYFS_ENDPOINT`, `TINYFS_TIMEOUT`, `ASYNC_COPY_WORKERS`,
  `FIX_METAL_ICB` are named **nowhere but `AGENTS.md`**. Their defaults (`0`,`32`,`0`,
  `localhost:6767`,`60`,`4`,`—`) are unverified, but **nothing contradicts them**, so rewriting a
  cell would trade ignorance for a guess.

  **No OLD/NEW is owed.** The truthful change is §1 (say what an unchecked row is) and the flagtable
  ledger, not the table.

---

## 3. Optional footnote — only if provenance should be visible in `AGENTS.md`

If the orchestrator wants the fourteen named in the document rather than only in the ledger, this
block is paste-ready immediately after the `### Optimizer / training knobs` table (end of the flag
section):

```
> **FLAGS THIS TREE CANNOT CHECK.** Fourteen rows name a flag with no `getenv` anywhere in
> `tinygrad/`: `NOLOCALS` `JIT_BATCH_SIZE` `PCONTIG` `GRAPH_ONE_KERNEL` `BROWSER` `THREADS`
> `APL_REMOTE_SOCK` `TINYFS_ENDPOINT` `TINYFS_TIMEOUT` `ASYNC_COPY_WORKERS`
> `HCQDEV_WAIT_TIMEOUT_MS` `AMD_SDMA_BIND` `FIX_METAL_ICB` `MLX_IP`. Four of them are nonetheless
> read in `extra/` (`APL_REMOTE_SOCK`, `HCQDEV_WAIT_TIMEOUT_MS`, `AMD_SDMA_BIND`, `MLX_IP`) and
> their defaults here are correct; the other ten are named nowhere in this tree at all and stand
> as transcriptions, not readings. See `.agents/slop/unverified9/REPORT.md`.
```

---

## Not replaced here

- **The 27 `DISAGREE` rows** — already handled: `dd9507e13` corrected **19**, left **8** on
  purpose (`CACHEDB`, `XDG_CACHE_HOME`, `REWRITE_DATA`, `PROFILE_DATA`, `HCQ_VISIBLE_DEVICES`,
  `EMULATE`, `AMD_AQL`, `PMC_COUNTERS`). Re-measured current values confirm the 19 are in place.
- **The "9 UNVERIFIED"** — not an `AGENTS.md` row and not nameable; see `REPORT.md` §1.
