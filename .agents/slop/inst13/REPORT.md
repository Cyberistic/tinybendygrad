# The 13 RECOVERABLE instruments — bytes exist, but do they ENFORCE?

Read-only audit, 2026-10-06. Nothing was restored into the live tree; the 13 were
restored into the scratch tree `.agents/slop/inst13/tree/` and executed there.
Orchestrator applies; this unit reports only.

The brief said 13 instruments were verified to EXIST and none verified to still do
its job. This is the second half. Short answer: **1 of 13 is LIVE; 12 are not.**

---

## 0. The denominator, re-derived by discovery (not trusted from `INSTRUMENTS.tsv`)

`.agents/slop/inst13/recount.py` reproduces the generator rule that names the
population — `toolsledger/extract.py`'s **rule A**: every backtick-quoted token in
`.agents/TOOLS.md` containing `/`, normalised and filtered — read-only, without
writing its `paths.tsv`. Measured now (the tree moves while other units write, so
this carries its time):

| rule A (extract.py), reproduced | count |
|---|---|
| distinct path tokens | **333** |
| present | **153** |
| absent | **180** |
| absent `INSTRUMENT` by `kind()` (basename regex) | **16** |
| of those, absent under `.agents/slop/` | 96 |

My present/absent split (153/180) differs from the sibling census's 160/173 because
the tree changed between runs. The **333** and the **16** are stable.

Then classified BY CONTENT, not by `kind()`'s basename shape (doctrine 1):

| content class | count | which |
|---|---|---|
| RUNNABLE-SCRIPT | **13** | the 13 instruments |
| CAPTURED-STREAM | 1 | `runs/elf-checkonly-2026-10-04.txt` (a stdout, not an instrument) |
| REVISION-REF | 1 | `xd1/pin` (names revision `6c3d401cf324`) |
| GONE | 1 | `.agents/slop/xd1/mutate.py` (no blob) |

**Denominator by discovery: 13 instruments.** This matches the brief. `kind()`'s 16
is 2 too high, for the two classifier errors the sibling census already named.

---

## 1. The four classes, counted

| class | count | instruments |
|---|---|---|
| **LIVE** (runs, claim exists, subject resolves) | **1** | `e2e_gpu_probe.mjs` |
| **ORPHANED** (runs/loads, but its claim or subject is gone) | **3** | `pin-tables.py`, `substrate-audit.py`, `rf2-mutate.py` |
| **BROKEN** (exists, does not run) | **5** | `cstyle-shapes-selftest.py`, `ga_mutate.py`, `nn-init-mutate.py`, `state-mutate.py`, `tools/mutate-dm.py` |
| **READ-ONLY/UNSETTLED** (loads, needs `bend`; claim + subject resolve) | **4** | `fold-rng-mutate.py`, `mixin-op-mutate.py`, `tcptx-mutate.py`, `tools/mutate-sz.py` |

Denominator 13 = 1 + 3 + 5 + 4.

*Boundary note:* `rf2-mutate.py` is counted ORPHANED because its SUBJECT
(`rf2_work.bend`) is gone — the substantive, self-contained fact. It ALSO fails to
import (`patch_not_apply` gone), so under a strict "ORPHANED must execute" reading
it is BROKEN as well; either way the bytes enforce nothing. `tcptx-mutate.py`'s
subject is only partially gone (14 of 51 anchors), so it stays READ-ONLY with the
partial-death recorded in its row, not promoted to ORPHANED.

**The claim "still exists" for all 13** — every one is still named in
`.agents/TOOLS.md` and/or `.agents/TODO.md` (see `STATUS.tsv` for the `file:line`),
and five are named by a present, runnable `.agents/slop/` script. **Nothing in this
file names any of the 13 in `checks/` or `gates/`** (the only `checks/` hit is
`checks/census.json:5452`, a DATA record of `nn-init-mutate.py`'s table, not an
invocation), and **`AGENTS.md` names none of the 13**. A claim surviving in prose is
not a claim anyone runs.

**The systemic cause, and it is why restoring the 13 is not enough:** every missing
dependency below was deleted by the same commit, `371cc64c9` ("sweep: THE SWEEP
DELETED 3,603 FILES…"). The instruments and their wiring died together:

| missing dependency | deleted by | used by |
|---|---|---|
| `.agents/slop/loadwatch.py` | `371cc64c9` | `rebase-gate.py:164` → every instrument that loads it |
| `.agents/slop/oracle_py.py` | `371cc64c9` | `rebase-gate.py:165` |
| `.agents/slop/patch_not_apply.py` | `371cc64c9` | `ga_mutate.py`, `nn-init-mutate.py`, `state-mutate.py`, `rf2-mutate.py` |
| `.agents/slop/revision-ledger.py` | `371cc64c9` | `substrate-audit.py` S1 |
| `.agents/slop/wire_parse.py` | `371cc64c9` | `substrate-audit.py` S2 |
| `.agents/slop/rebase-scan-oracles.py` | `371cc64c9` | `substrate-audit.py` S2 |
| `.agents/slop/rf2root/schedule/rf2_work.bend` | `371cc64c9` | `rf2-mutate.py` |

`rebase-gate.py` is PRESENT and is the shared reader a live gate (`cstyle-gate.py`)
still claims to use — **and it is itself broken at import** (`import loadwatch`,
line 164). A live referrer that cannot load is the same as a missing one.

---

## 2. The 13, one line each

### LIVE (1)

- **`.agents/slop/e2e_gpu_probe.mjs`** — `rc=0`. Ran under `node`; launched
  chrome-stable headless, `requestAdapter()` → vendor `apple` arch `metal-3`, then
  dispatched ONE WGSL kernel and read back `[3,7,13,21,31,43,57,65]`, bit-exact to
  `EXPECT`. Claim `TOOLS.md:703` / `TODO.md:5175`, referrers `e2e_negctl.sh:48`,
  `e2e_mm_run.mjs:13`; subjects `xd2/cdp.mjs` + `xd2/serve.mjs` both present.
  **This is the one instrument that still does its job.**

### ORPHANED (3) — *the bytes are recoverable and mean nothing*

- **`.agents/slop/pin-tables.py`** — `rc=1`. Bare run prints its docstring (by
  design); `--out DIR` fails `no such table: ag-mutations.txt`. Its SUBJECT is the
  set of ~30 mutation tables it pins; **only `bend_mutations.md` of the named tables
  still exists**; `ag-mutations.txt`, `rf2-mutations.txt`, `c-mutations.txt`, … are
  gone. A pinner for tables that are not there is a claim about nothing.
  Claim `TOOLS.md:1177` / `TODO.md:7878`.
- **`.agents/slop/substrate-audit.py`** — `rc=1`, **1 of 4 checks hold**. S1
  `FileNotFoundError: revision-ledger.py`; S2 `FileNotFoundError: wire_parse.py`;
  S3 `ModuleNotFoundError: No module named 'loadwatch'` (via `rebase-gate.py`); S4
  `ok`. Three of its four named subjects were deleted by the sweep. Claim
  `TOOLS.md:1040`; referrer `formblind-census.py:439`.
- **`.agents/slop/rf2-mutate.py`** — its SUBJECT `rf2root/schedule/rf2_work.bend` is
  GONE, so all 42 anchors resolve 0 times; it also `import patch_not_apply` (gone).
  Claim `TOOLS.md:319`; referrers `zero-audit.py:67`, `table-pin.py:67`,
  `formblind-census.py:114`.

### BROKEN (5) — exists, cannot load

Four of these **would be READ-ONLY (needs `bend`) if their import were intact**; the
import is the harder failure and it lands first.

- **`.agents/slop/cstyle-shapes-selftest.py`** — `rc=1`,
  `ModuleNotFoundError: No module named 'loadwatch'`: it loads `rebase-gate.py`,
  which imports the deleted `loadwatch`. Its real-lane subjects
  (`blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt`,
  `cstyle-parity/oracle.txt`) are ALSO gone. Claim `TOOLS.md:1208`; live referrers
  `cstyle-gate.py:192`, `reader-guard.py:164`; `TODO.md:8331` already admits its
  "REAL LANES" case fails.
- **`.agents/slop/ga_mutate.py`** — `import patch_not_apply as PNA` (gone) fails
  before any `bend` call. SUBJECT `renderer/amd/generate.bend` resolves fully
  (41/41 anchors). Claim `TOOLS.md:575` ("40 move gate rows") is now unfalsifiable.
- **`.agents/slop/nn-init-mutate.py`** — same missing import. SUBJECT
  `nn/__init__.bend` 15/15 anchors. Claim `TOOLS.md:53`; its recorded table is data
  at `checks/census.json:5452`.
- **`.agents/slop/state-mutate.py`** — same missing import. SUBJECT `nn/state.bend`
  12/12 anchors. Claim `TOOLS.md:53`.
- **`.agents/slop/tools/mutate-dm.py`** — `importlib` is USED at `:24`/`:25` and
  **never imported** (`NameError` at module load), and it then loads
  `rebase-gate.py`→`loadwatch` (gone). SUBJECT `uop/divandmod.bend` resolves
  (18/18: 13 unique, 4 the harness's replace-all accepts, 1 the runtime-built
  `old_s`). Claim `TOOLS.md:42`.

### READ-ONLY/UNSETTLED (4) — the honest verdict per the brief

These load clean and need `bin/bend`, which this unit may not run.

- **`.agents/slop/fold-rng-mutate.py`** — SUBJECT `uop/fold.bend`, **19/19 anchors**.
  Also needs `jj`. Claim `TOOLS.md:731` / `TODO.md:852`.
- **`.agents/slop/mixin-op-mutate.py`** — SUBJECT `mixin/op.bend`, **17/17**.
  Writes into the live tree and restores from a byte snapshot. Claim `TOOLS.md:50`.
- **`.agents/slop/tcptx-mutate.py`** — SUBJECT `renderer/tc_ptx.bend`,
  **37/51 anchors; 14 are DEAD** — the `tc.py` half (`def cd`, `def AX_K`,
  `Tc.used`, `Tc.threads`, `cacc`, `fnv`, …) was split out into
  `renderer/tc.bend` and no longer lives in `tc_ptx.bend`. The harness prints
  `EDIT MATCHES 0 TIMES` and skips them. **Partially orphaned by a file split.**
  Claim `TOOLS.md:55`.
- **`.agents/slop/tools/mutate-sz.py`** — SUBJECT `sz.bend`, **9/9** (7 unique + 2
  the harness's `in src` test accepts). Loads clean. Claim `TOOLS.md:45`.

---

## 3. What a mutator "works" would even mean here

The brief: *"a mutator's job is to CHANGE a subject and be CAUGHT. A mutator that
runs and is not caught is worse than absent."* None of the 9 mutators could be RUN
in this session. What I could settle without `bend`:

- **Do the anchors still resolve?** (a mutator whose anchor is gone is a no-op).
  Yes for 7 (fold-rng, ga, mixin-op, nn-init, state, dm, sz), part for 1 (tcptx
  37/51), no for 1 (rf2 0/42).
- **Do they LOAD?** No for 5 (the missing `patch_not_apply` × 4 and mutate-dm's
  missing `importlib`). So 5 of 9 die before they ever reach `bend`.
- **Would they be CAUGHT?** Unsettled — that requires `bend`. This is the one thing
  I could not settle.

## 4. The ONE I could not settle

**`tcptx-mutate.py`: whether its 37 surviving anchors still MOVE rows when run, and
whether the 14 dead ones are recoverable by re-pointing them at `renderer/tc.bend`.**

The subject split (`tc_ptx.bend` → `tc_ptx.bend` + `tc.bend`) is measured; what is
not measured is whether the surviving 37 still reproduce the table's claim
(`TOOLS.md:55`, "51 one-edit mutations"). What would settle it: run the harness under
`bin/bend` after repointing the 14 `tc.py`-half anchors at `renderer/tc.bend` and
diffing the moved-row set against the claim — which needs the `bend` this session
reserved for another unit. The same `bend` precondition leaves the other three
READ-ONLY mutators (fold-rng, mixin-op, mutate-sz) unresolved, but tcptx is the only
one where a fix is nameable from the tree alone.

## 5. Recommended (orchestrator applies; this unit changed nothing live)

1. Do **not** restore the 13 into the live tree expecting enforcement. Restoring the
   13 without their 7 deleted dependencies (all in `371cc64c9`) changes nothing that
   runs: only `e2e_gpu_probe.mjs` is LIVE, and its dependencies (`xd2/cdp.mjs`,
   `xd2/serve.mjs`) are among the survivors.
2. If any is to be revived, restore the DEPENDENCY SET first, not just the file.
   `loadwatch.py`, `oracle_py.py`, `patch_not_apply.py`, `revision-ledger.py`,
   `wire_parse.py`, `rebase-scan-oracles.py` and `rf2_work.bend` all have history.
3. Fix `AGENTS.md`'s **"14 INSTRUMENTS by content"** clause: it is now known that
   **1 of the 13 runs and enforces; 3 are ORPHANED, 5 are BROKEN, 4 are
   READ-ONLY/UNSETTLED.** "13 recoverable" is a statement about bytes; this report is
   the statement about work.

## Reproduce

```
.venv/bin/python .agents/slop/inst13/recount.py     # denominator by discovery
.venv/bin/python .agents/slop/inst13/restore.py     # 13 -> .agents/slop/inst13/tree
.venv/bin/python .agents/slop/inst13/deps.py        # deps + subjects exist?
.venv/bin/python .agents/slop/inst13/anchors.py     # do the mutation anchors resolve?
.venv/bin/python .agents/slop/inst13/runner.py      # run the 4 non-bend instruments
```

Artifacts: `STATUS.tsv` (the table), `anchors.json`, `run.out` (captured rc/stdout/
stderr of the four executed instruments).
