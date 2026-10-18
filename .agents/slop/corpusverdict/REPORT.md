# REPORT: IS THE `graphcmp` CORPUS VERDICT CURRENT?

Unit: `corpusverdict`. Date: 2026-10-18. Private index: `.git/agent-index-corpusverdict`
(chosen once, same string in every command).

## 1. THE INDEX, BEFORE AND AFTER

`checks/index-arm-gate.py` on the **default** index, before anything else:

```
INDEX-ARM HEAD 2ed115d62e60  TREE 7618  INDEX 8477
INDEX-ARM SHAPES deletion=0 stale=2 foreign-add=0 intent-to-add=859
INDEX-ARM STALE (2): .agents/TODO.md, AGENTS.md
INDEX-ARM REFUSED ... rc=3
```

**ARMED. rc=3 REFUSED.** Independent confirmation: HEAD tree 7618 entries, index 8477.

**The two stale paths are a SILENT REVERSION, live right now** — and they are the two files
this unit may not touch:

| path | HEAD blob | INDEX blob | worktree | index B | HEAD B |
|---|---|---|---|---|---|
| `AGENTS.md` | `9ebee3f7` | `910825eb` | `9ebee3f7` | 48226 | 49123 |
| `.agents/TODO.md` | `a3ae005c` | `35c91284` | `a3ae005c` | 1586846 | 1587775 |

worktree == HEAD, index holds an **older** blob. A bare `git commit` would revert both.
`910825eb` is the blob of commit `5bd4963a4`; `35c91284` of `2ed115d62`.

**Private index, verified disarmed by direct measurement** (the gate deliberately scrubs
`GIT_INDEX_FILE` at `checks/index-arm-gate.py:84-86`, so it never answers about a private
index and this had to be measured separately):

```
TREE=7618 INDEX=7618  only-in-tree=0  only-in-index=0  sha mismatch=0
```

After: identical (`8fc35f67…`, 243 files, `runs/graphcmp/` byte-identical throughout).

## 2. WAS THE CORPUS RE-RUN? **NO.** MEASURED REASON

**`.agents/slop/graphcmp.bend` does not typecheck against the port.**

```
$ .venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend .agents/slop/graphcmp.bend --check-only
[bounded] WITHIN-LIMITS  rc=1  peak-RSS=378 MB (ceiling 2048)  1s
SOME PROOFS FAIL
- expected : a declared constructor (tinybendygrad/uop/ops.Op declares ...OpsMULACC, ...)
- observed : O.OpsGROUP{}
Location: g_group
791 |   O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}, ...)
```

`graphcmp.bend:791` constructs `O.OpsGROUP{}`. `OpsGROUP` occurs **0 times** in
`tinybendygrad/uop/ops.bend` and **nowhere in the whole port** (`grep -rl` empty). Upstream
reimplemented GROUP/FLIP; the `Op` union now has **75** constructors.

`settled()` (`differ.py:1038`) reads that probe's first line, and `differ.ready(0)` returns
**False — called directly, today**. So:

- **`differ.py run` is UNGATED.** `differ.py:1357` dispatches `return {"run": cmd_run, ...}`
  directly, with no readiness check, and `cmd_run` overwrites `D/` artifact by artifact.
  Running it would replace 243 files of evidence with a dead bend lane.
- **`differ.py repro` IS gated** (`clean_run`, `differ.py:1288`) and refuses. Measured:
  `repro 0` printed `# run A: no healthy run in 0 attempts -- this is NOT a measurement`,
  rc=2, and left all 243 files byte-identical.

**So the number cannot be refreshed today, and the tree cannot be run green without first
repairing `graphcmp.bend` for the removed `OpsGROUP` constructor.** Both were deliberately
not run: `run` is destructive, and `repro`'s refusal is the correct refusal.

## 3. THE VERDICT, BEFORE AND AFTER, WITH DENOMINATORS

`runs/graphcmp/D/D0-run-summary.txt` (mtime `Oct 17 01:50`), **denominator = 34 graphs**:

```
graphs=34  graphs-answered=34  graphs-agree=34  graphs-disagree=0
byte-identical=34  not-comparable=0  expect-moved=0  selfcheck=# SELFCHECK: OK
substrate-start=5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3
substrate-end  =5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3
```

**AFTER: there is no current verdict.** Not "0 of 34" — there is no denominator at all,
because the bend lane cannot build. Live `substrate_digest()` = `96f40eead5f3c326…`.

The corpus verdict is not merely old; **it describes a tree that no longer exists.**

## 4. EVERY ROW THAT CHANGED, OLD → NEW

No row changed in `D/`, because nothing was re-run. What changed is the **substrate the rows
describe**: `5d3f3119…` → `96f40eea…` (156 declared inputs: 142 `.bend` + 8 `SUBSTRATE_INPUTS`).

The changed rows are therefore *unknown* — 34 graphs, no per-graph verdict. Between the
`01:50` run (`e6ce80b8e`) and now, **20 `.bend` files, 730 insertions / 583 deletions**:

```
mixin/gradient.bend 70   mixin/movement.bend 231   nn/optim.bend 67
runtime/support/autogen.bend 103   schedule/multi.bend 72   uop/ops.bend 179
uop/spec.bend 208   uop/symbolic.bend 251   uop/fold.bend 53   uop/validate.bend 23
codegen/decomp/dtype.bend 2  codegen/late/regalloc.bend 4  renderer/ptx.bend 11
runtime/ops_python.bend 3  schedule/indexing.bend 3  schedule/prepare.bend 13
schedule/rangeify.bend 6  tensor.bend 6  uop/render.bend 2  viz/serve.bend 6
```

`uop/spec.bend`, `uop/symbolic.bend`, `uop/ops.bend` and `uop/validate.bend` are the emission
logic itself. **Not marginal drift.**

Substrate quiescence was measured over a 180 s window (12 samples, 15 s apart): digest
**stable throughout**, 1 file written in the preceding 10 min (`uop/ops.bend`, at 03:19 local).
Quiescence was never the blocker.

## 5. PEAK RSS AND RUNTIME PER LANE

Machine: 16.0 GB, 60% budget = 9.6 GB. **Everything ran SEQUENTIALLY — never two concurrent
`bend` processes.** Sum parallelised under: **1 lane, 378 MB of 9.6 GB (3.9%)**.

| lane | command | token | peak RSS | wall |
|---|---|---|---|---|
| py | `graphcmp.py emit --side py --graph matmul` | 20 rows | — | 0.35 s |
| bend | `graphcmp.bend --check-only` | `WITHIN-LIMITS` | **378 MB** | 0.97 s |
| LAWS | `LAWS.bend --check-only` | `WITHIN-LIMITS` | 9 MB | — |
| PROOF | `PROOF.bend --check-only` | `WITHIN-LIMITS` | 95 MB | — |

Census context (`.agents/slop/peakrss/census.rows`): `graphcmp.bend` 748 MB, `symbolic.bend`
745, `spec.bend` 566, `ops.bend` 345, median 207. The measured 378 MB here is a **failed
check**, so it is a lower bound on what a succeeding emit costs.

## 6. `git fsck` AND WHAT THE COMMIT CARRIED

See the commit for `--stat` and `fsck` output; both were run in the same command as the commit.

## 7. NUMBERS IN THE TREE THAT THIS RUN INVALIDATED, NAMED WITH PATHS

1. **`gates/corpuslane-gate.py:9-19` — NOW FALSE.** The header claims the re-vendor
   `a741a469f` "made it raise on **30 of its 34 graphs**", "**30 raised, 4 emitted**", and
   "`ParamArg.size`, 26 reads, 26 graphs". **MEASURED today: rc=0, PASS — 43 lane runs
   produced rows, 34 graphs + 7 declared plants + 2 unwired plants, 0 missing attrs,
   75 Ops members, 0 symbolic size refusals.** The CPython lane is alive; its header is a
   pre-repair reading. (The gate's *verdict* is right for the wrong reason.)
2. **`AGENTS.md`, Tinygrad Flags `SPEC` row: "70 of 77 enum members" — the 77 IS STALE.**
   **MEASURED: `tinygrad.uop.Ops` has 75 members today**, and the port's `uop/ops.bend`
   declares exactly 75 constructors. Every citation of **77** is two constructors out of date.
   `.agents/TODO.md:19017` already flags the "77" against the dumps.
3. **`checks/differ.py:148` — "run with 34 of 34 graphs byte-identical" (2026-10-13)** now
   describes a substrate two re-vendors old.
4. **THE NUMBER COLLISION — two different `34`s are quoted as one.** The corpus's **34 graphs**
   and `LAWS.bend`'s **34 `law` decls** (`grep -c '^law '` = **34, measured**) are unrelated
   populations that share a numeral. `.agents/slop/AUDIT-CAN-FAIL.md:14` and
   `.agents/slop/laws17/REPORT.md:62` carry "**34/34 ALL PROOFS CHECK**", where the 34 is
   `grep -c '^law '` and **bend prints no count at all** — the file itself records that.
   `.agents/TODO.md:82` (`proofs 34/34`) is this one, not the corpus. Neither file may be
   edited by this unit.

## 8. FOUND, NOT DONE

- **`AGENTS.md` and `.agents/TODO.md` are BOTH stale in the index** (table in §1) and both are
  outside this unit's grant. Until someone runs `git reset` on a private index, **a bare
  `git commit` reverts them.**
- **`LAWS.bend` (34 TODOs) and `PROOF.bend` (18 TODOs) both read `SOME PROOFS FAIL`** under
  `--check-only`. The counts in `AGENTS.md` (34 and 18) are **CURRENT** — measured today.
- The corpus cannot go green until `graphcmp.bend` is repaired for the removed `OpsGROUP`
  constructor. That is a `.bend`-adjacent port change in a lane other units own; not attempted.
- `HEAD` moved `2ed115d62e60` → `13f43808b451` **during this session**, and `gates/opseven-pins.rows`
  entered the stale set between two runs. Other units are writing this tree now.

## THE INSTRUMENT THIS RUN ADDED

`gates/corpusverdict-gate.py` — answers "is the recorded corpus verdict current?" from
`differ.substrate_digest()`. **No `bend`, no re-run, and it never writes under
`runs/graphcmp/`.** Its positive control plants a digest that differs from the reference and
requires `STALE`, and requires identical digests to read `CURRENT` — because this gate's
failure mode is *silently reading CURRENT*.

Measured, four cases: real tree **FAIL(1)**; planted matching digest reports
`substrate.verdict=CURRENT` (**the gate is not unconditionally red**); absent summary
**REFUSED(3)**.