# unverified9 — the NINE that cannot be named, and the FOURTEEN re-checked by name

**Moment: 2026-10-06, ~13:10 +0300. `AGENTS.md` line numbers below are the CURRENT tree's,
read with `grep -n` (the `flagtable/table_rows.json` line numbers are STALE — they predate
`agend2-applied`/`flagtable-rows`, which shifted the tables by ~35 lines).**

Artifacts this report produced (all under `.agents/slop/unverified9/`):

| file | rule |
|---|---|
| `classify.py` → `classify.json` | `git grep -n -w` over TRACKED files, worktree vs PIN |
| `gather.py` → `gather.json` | `git grep -n -w -F -e FLAG` minus `AGENTS.md`/`.agents/` |

(An earlier `rglob`-based `sweep.py` was removed: over `.py`/`.bend` it reported all 14 "named
anywhere" because `\bTHREADS\b` matches the English word — two witnesses disagreeing about the
same population, so the word-boundary `git grep` one is kept.)

---

## 1. The 9 — **NOT NAMEABLE. That is the finding.**

**The premise is not in the artifacts it is attributed to. `flagtable` left *fourteen*
`UNVERIFIABLE` and *twenty-seven* `DISAGREE` — both named, every one. It left no "9".**

The string `9 UNVERIFIED` occurs **exactly once** in the whole repo (rule: `rg -n "UNVERIFIED"
.agents/slop/agend2/` and `grep -rn "9 UNVERIFIED" .` excluding `.git`):

```
.agents/slop/agend2/REPORT.md:29:| **9 UNVERIFIED** | the ~180 upstream flag-table rows (transcribed, not this tree's) |
```

That is a **bucket label**, not a list. What the bucket is:

- It is the **residual of `agend2`'s own denominator**: `REPORT.md:22-30` declares **76 measured
  claims**, then names `46 re-measured` + `21 UNMEASURED`, leaving **76 − 46 − 21 = 9**.
- Its single stated content is "**the ~180 upstream flag-table rows**" — a description that
  **contradicts a count of 9** (≈180 rows ≠ 9 claims).
- `agend2`'s own §3 enumeration table (`REPORT.md:65-139`) contains **exactly ONE `UNVERIFIED`
  row** — line 139, `| L276-453 | tinygrad flag tables (~180 rows) | upstream transcription |
  UNVERIFIED |`. **One row, not nine.**
- The §3 table is also **internally inconsistent with §1**: 73 rows total (rule: count `|`-rows
  between the header and `**Re-measured`), verdicts **31 MATCH · 20 MOVED · 20 UNMEASURED · 1
  UNVERIFIED · 1 NOTE**, against §1's claimed **25 MATCH · 21 MOVED · 21 UNMEASURED · 9
  UNVERIFIED**.
- `flagtable`'s committed tree (commit `55ea30db6`, 11 files) contains **no enumeration of 9**;
  its commit body names the **14** and the **27**. `agend2`'s commit body (`eebfff05c`) names
  **no 9-flag list** either.

**Verdict: 0 of 9 named.** An unverified count with no list — and the list it was said to
summarise (the ~180 flag rows) is the one place a reader *can* look, while the count says 9.

---

## 2. The 14 `UNVERIFIABLE` — re-checked by the flag NAME, not by `getenv`

For each: is it **named anywhere** outside `AGENTS.md` and this audit's own artifacts; is it
**declared by a real `getenv`/`ContextVar`** in the tracked tree; is it in `tinygrad/`; is it in
the **port** (`tinybendygrad/`)? (Rule: `git grep -n -w -F -e FLAG -- ':!AGENTS.md' ':!.agents/'`,
`gather.json`.)

| flag | AGENTS.md (line · table) | named in tree? | getenv-declared? | in `tinygrad/` | in port |
|---|---|---|---|---|---|
| `APL_REMOTE_SOCK` | 416 · Device & runtime | **YES** | **YES** `extra/hcq1/remote.py:128` | 0 | 0 |
| `HCQDEV_WAIT_TIMEOUT_MS` | 425 · Device & runtime | **YES** | **YES** `extra/hcq1/hcq.py:255` | 0 | 0 |
| `AMD_SDMA_BIND` | 438 · Backend-specific | **YES** | **YES** `extra/hcq1/ops_amd_old.py:513` | 0 | 0 |
| `MLX_IP` | 452 · Backend-specific | **YES** | **YES** `extra/mlx_driver/loopback.py:15`, `mlxdev.py:106` | 0 | 0 |
| `GRAPH_ONE_KERNEL` | 374 · Scheduler, JIT & graph | YES (set, not read) | no | 0 | 0 |
| `BROWSER` | 398 · Debug, validation & dev infra | YES (prose only) | no | 0 | prose only |
| `THREADS` | 408 · Device & runtime | YES (a local var) | no | 0 | prose only |
| `NOLOCALS` | 340 · Compiler & kernel search | **nowhere** | no | 0 | 0 |
| `JIT_BATCH_SIZE` | 364 · Scheduler, JIT & graph | **nowhere** | no | 0 | 0 |
| `PCONTIG` | 366 · Scheduler, JIT & graph | **nowhere** | no | 0 | 0 |
| `TINYFS_ENDPOINT` | 420 · Device & runtime | **nowhere** | no | 0 | 0 |
| `TINYFS_TIMEOUT` | 421 · Device & runtime | **nowhere** | no | 0 | 0 |
| `ASYNC_COPY_WORKERS` | 422 · Device & runtime | **nowhere** | no | 0 | 0 |
| `FIX_METAL_ICB` | 450 · Backend-specific | **nowhere** | no | 0 | 0 |

**The "named" evidence, with `file:line`:**

- `APL_REMOTE_SOCK` — `extra/hcq1/remote.py:128`:
  `sock_path, sock = getenv("APL_REMOTE_SOCK", temp("tinygpu.sock")), …`.
- `HCQDEV_WAIT_TIMEOUT_MS` — `extra/hcq1/hcq.py:255`:
  `timeout = timeout or getenv("HCQDEV_WAIT_TIMEOUT_MS", 30000)`; also exported in 21
  `examples/mlperf/**/*.sh` and 1 `test/` file.
- `AMD_SDMA_BIND` — `extra/hcq1/ops_amd_old.py:513`:
  `if not getenv("AMD_SDMA_BIND", 0) or not dev.is_am(): return`; also
  `extra/hcqfuzz/spec.py:39`.
- `MLX_IP` — `extra/mlx_driver/loopback.py:15` `MLX_IP = getenv("MLX_IP", "10.0.0.1")` and
  `extra/mlx_driver/mlxdev.py:106` `ip:str=getenv("MLX_IP", "10.0.0.1")`.
- `GRAPH_ONE_KERNEL` — `.github/workflows/benchmark.yml:604-605`
  `GRAPH_ONE_KERNEL=1 NSZ=8192 python3 …` (**set by CI, never `getenv`-read**).
- `BROWSER` — prose/comments only: `checks/e2e.sh:108,138,191`, `checks/run-port-mm.sh:8`,
  `tinybendygrad/runtime/ops_webgpu.bend:3,129`, `webgpu_call.bend:303,598,1104`.
- `THREADS` — a **local variable / C macro**, not a flag: `docs/abstractions4.py:23 THREADS = 256`,
  `extra/gemm/*.py`, `extra/gptoss_kernels/**/*.{py,cpp}`; the port hit is the verb in
  `tinybendygrad/codegen/decomp/transcendental.bend:899` ("EVERY STEP THREADS THE ARENA").

---

## 3. Counts, with denominators

Rule for each: `git grep -n -w -F -e FLAG` over tracked files, minus `AGENTS.md` and `.agents/`.

```
14 checked
  named anywhere in the tree ..........  7 / 14
  named NOWHERE but AGENTS.md .........  7 / 14
  getenv-declared somewhere ...........  4 / 14   (all four under extra/)
  read by tinygrad/ ...................  0 / 14
  read by the port (tinybendygrad/) ...  0 / 14
```

**The 4 that ARE verifiable and were mislabelled `UNVERIFIABLE`:** `APL_REMOTE_SOCK`,
`HCQDEV_WAIT_TIMEOUT_MS`, `AMD_SDMA_BIND`, `MLX_IP` — all declared in `extra/`, none in
`tinygrad/`. **And their AGENTS.md defaults are RIGHT** (`temp path`/`30000`/`0`/`10.0.0.1` all
match the `getenv` call), so these four are `AGREE`, not `UNVERIFIABLE`.

**The 7 named nowhere:** `NOLOCALS`, `JIT_BATCH_SIZE`, `PCONTIG`, `TINYFS_ENDPOINT`,
`TINYFS_TIMEOUT`, `ASYNC_COPY_WORKERS`, `FIX_METAL_ICB`. Their rows assert defaults
(`0`,`32`,`0`,`localhost:6767`,`60`,`4`,`—`) that **no file in this tree corroborates** — not
even `docs/env_vars.md`.

**The 9:** 0 / 9 nameable (§1).

---

## 4. Why the instrument could not see four of them — doctrine 1, one level down

`flagtable`'s source side is scoped to **one directory**: `find_decls.py:5,13` and
`compare.py:5` set `TINYGRAD = ROOT / "tinygrad"` and walk `TINYGRAD.rglob("*.py")`. A flag
declared in `extra/` — outside that single hard-coded root — is **invisible**, and the
`results.json` reason string says so exactly: *"No `ContextVar`/`getenv` declaration found in
**`tinygrad/`**"*. `unverifiable`-by-`getenv`-in-`tinygrad/` is not `unverifiable`-by-mention:
**4 of the 14 are read by `extra/`, 0 are read by `tinygrad/`.**

### 4a. A DEAD artifact in the same directory

`.agents/slop/flagtable/read_coverage.json` (committed, `55ea30db6`) records **84** of 146
table flags as found **nowhere** in `tinygrad/`. That is impossible beside `results.json` from
the same unit ten minutes earlier (105 `AGREE`, every one needing a `tinygrad/` declaration).
**Re-running its own `read_coverage.py` today prints `NOT found: 14` — exactly the
`UNVERIFIABLE` set** (rule: `.venv/bin/python .agents/slop/flagtable/read_coverage.py`). The
committed `84` is a **DEAD reading** (ran and produced a number the same instrument cannot
reproduce); it was restored to HEAD after this check.

### 4b. The re-vendor did NOT move these

All 14 give **identical** hits in the worktree and at the PIN `ad117c928^` (rule:
`git grep -n -w -F -e FLAG ad117c928^`). None of the files that carry them was touched by
`ad117c928`, so the `14` is not a pin artefact.

### 4c. The provenance claim is unsupported

`agend2:139` says the block is "~180 upstream `docs/env_vars.md` rows transcribed". **Only 12 of
the 146 table flags appear in `docs/env_vars.md`** (rule: word-grep each table flag against the
file), the file is **73 lines**, and **none of the 14** is in it — at the worktree *or* at the
PIN (`git show 'ad117c928^:docs/env_vars.md'` is 73 lines, 0 hits). So the tables are
transcribed from an upstream revision **this tree does not vendor**, and the pin cannot settle
any of the 14.

---

## 5. The port reads FIVE flags; none of the 14 is among them

The port's whole `getenv` surface (rule: `grep -rn 'getenv_str("\|getenv_int("' tinybendygrad/`):

```
tinybendygrad/helpers.bend:308  getenv_int("DEBUG", 0)
tinybendygrad/helpers.bend:342  getenv_str("NO_COLOR", "")
tinybendygrad/helpers.bend:343  getenv_str("DEFAULT_FLOAT", "float32")
tinybendygrad/helpers.bend:344  getenv_str("DEFAULT_INT", "int32")
tinybendygrad/helpers.bend:345  getenv_str("SUM_DTYPE", "float32")
```

`tinygrad/` declares **148** unique flag names (rule: unique `(ContextVar|getenv|_DEV)\("NAME"`
across `tinygrad/**/*.py`; the brief's `147` differs by its rule, not the tree). **So 148 flags
are documented in the vendored source and the port reads 5 of them** — 143 are documented flags
the port ignores. Of the 14, **0 are read by `tinygrad/` and 0 by the port**, so the category
"a flag read by `tinygrad/` but not by the port" is *empty for this set* — these are flags read
**nowhere in the port and nowhere in `tinygrad/`**.

---

## 6. What this changes in `AGENTS.md`

Nothing about the 27 `DISAGREE` rows: `flagtable-rows` (`dd9507e13`) already corrected **19**
and deliberately left **8** (`CACHEDB`, `XDG_CACHE_HOME`, `REWRITE_DATA`, `PROFILE_DATA`,
`HCQ_VISIBLE_DEVICES`, `EMULATE`, `AMD_AQL`, `PMC_COUNTERS`, where `—` is the honest answer).

The open correction is the **header of the `Tinygrad Flags` table**, which today says nothing
about what a `Default` cell means when it is `—`, and nothing about a row this tree cannot
check. See `REPLACEMENTS.md`.
