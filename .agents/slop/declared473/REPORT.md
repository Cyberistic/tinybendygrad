# The 473 `DECLARED-NAME` refusals: a nameset applied by basename

Measured 2026-10-06. Instruments in this directory: `derive.py` (denominators),
`reader_census.py` (who names them), `summarize.py` (buckets -> `counts.tsv`),
`contract_test.py` (the rename tests). **Nothing in the live tree was renamed.**

## 1. The two denominators, re-derived

| number | rule | value |
|---|---|---|
| `declared()` | call `checks/differ.py:260`'s `declared()` directly | **139** |
| the 473 | `.agents/slop/sloptxt/PLAN.tsv` rows whose `note` column starts with `DECLARED` (the branch at `plan.py:89-90`) | **473** |

`.venv/bin/python .agents/slop/declared473/derive.py`:

```
declared() count              = 139
PLAN.tsv DECLARED rows        = 473
distinct basenames among 473  = 139
473 basenames not in declared = 0
declared names not among 473  = 0
declared names reused by >=2 files = 139
```

## 2. The mismatch is a census of two different things, not a bug

`473 != 139` because **`plan.py:89` tests `os.path.basename(t) in DEC`** — a *basename*
membership test against a set of 139 names. The 473 are **files**; the 139 are **names**.
The two sets agree exactly: the set of distinct basenames over the 473 *is* `declared()`
(0 in each direction of the difference). Every one of the 139 names is reused **3 to 9
times** across committed mirror trees:

```
 139  .agents/slop/figurefix/plant/D-live
 139  .agents/slop/rerun/D-before
 138  .agents/slop/figurefix/plant/scratch/runs/graphcmp/D
  12  .agents/slop/differverdict/shell-D       (subset)
  11  .agents/slop/differverdict/pristine/runs/graphcmp/D
  10  .agents/slop/differverdict/warm-{oracle,planted,python}   (each)
   4  .agents/slop/differverdict/py-D
```

Top multiplicities: `D0-coverage-census.txt` 9, `D4-cross-range.txt` 9, `D0-selfcheck.txt`
8, `D1-verdicts.txt` 8. **No name in the 473 is outside `declared()`, and no declared name
is missing from the 473.** So the 473 are a faithful *file* projection of the 139-name
*generator* nameset.

## 3. The contract, and where it is weaker than the claim

The 139 names are genuinely **declared by a generator**: `checks/differ.py:declared()`
(`:260`), built from `LITERALS`+`REPORTS` (`:251-257`) over `corpus()`/`CONTROLS`/`PLANTS`/
`STAB`. That one nameset is asked by import in two places — `checks/no-txt.py`'s `.txt`
carve-out and `differ.py`'s `artefacts_ok()` — which is doctrine 1's canonical shape and is
why the 139 live `runs/graphcmp/D/*.txt` stay `.txt`.

**But the 473 mirror files do not inherit that contract. They inherit its *basename*.** The
mirrors are snapshots; the readers that name those basenames open the **live**
`runs/graphcmp/D`, not the snapshot. Measured:

| bucket | rule | count |
|---|---|---:|
| named by a committed reader | target **basename** appears literally in a committed code file (`reader_census.py`) | **140** |
| named only by `declared()` | basename in `declared()` but spelled with `.txt` in **no** committed code file (constructed by differ's f-strings) | **333** |
| named by nothing at all | basename not in `declared()` | **0** |

`0` in the last row is the point: **every one of the 473 is named, because `plan.py:89`
selected them *by* `declared()`.** "Named by nothing" cannot occur in this population.

The 140's readers, by file (all read the **live** tree):

```
 87  .agents/slop/diffpy/oracle-run.sh        (the generator's own writer/reader)
 19  .agents/slop/devrecord/xcheck.py:46
 19  .agents/slop/diffpy/oracle-repro.sh
  3  .agents/slop/unsetexp/selftest.py
  3  checks/disagree-gate.py
  3  .agents/slop/arghalf/tree/drivers/one/gcmp.bend
  3  .agents/slop/devpin/{lin-decision,envsweep}.py
```

**Only ONE committed file opens a mirror tree by path**: `git grep D-live -- '*.py'` returns
`.agents/slop/figurefix/plant/plant.py:54  shutil.copytree(HERE / "D-live", SCRATCH / "runs/graphcmp/D")`.
And of the 139 files in that copy, the driver then reads **one** by name (`plant.py:58`
`SCRATCH/"runs/graphcmp/D/D0-run-summary.txt"`). `rerun/D-before` and all nine
`differverdict/*` mirrors are opened by **no** committed code.

## 4. The rename tests (contract tested on three of the 473)

`.venv/bin/python .agents/slop/declared473/contract_test.py`, scratch trees under
`.agents/slop/declared473/tree/`, `os.rename` (never `git mv`):

| case | target renamed | reader run | baseline rc | renamed rc | what broke |
|---|---|---|---:|---:|---|
| t1 | `figurefix/plant/D-live/D0-run-summary.txt` | `figurefix/plant/plant.py:54,58` | 1 | 1 | **`FileNotFoundError`** at `set_summary` -> `SCRATCH/.../D0-run-summary.txt` |
| t2 | `figurefix/plant/D-live/D1-graph-matmul.txt` | same `plant.py` | 1 | 1 | **nothing** — identical `RUN HEALTH` output |
| t3 | `rerun/D-before/D0-run-summary.txt` | `devrecord/xcheck.py:46` | **0** | **1** | **`FileNotFoundError`** reading the temp copy of `D0-run-summary.txt` |

* t1 **confirms the contract where a copy-then-read driver exists**, and the break is a
  `FileNotFoundError`, not a silent pass.
* t2 is the control: renaming a non-summary name in the same tree changes nothing. The
  contract is **name-specific**, not tree-wide.
* t3 shows the `D0-run-summary.txt` name is load-bearing for `xcheck.py` (0 -> 1). But
  `xcheck.py` reads its own `ROOT/runs/graphcmp/D`, **not** the `rerun/D-before` mirror; I
  populated its root from that mirror to make the rename observable. In the live tree the
  committed mirror is opened by nothing.

**Verdict.** Of the 473: **1** (`D0-run-summary.txt`, in each mirror that a copy-then-read
driver consumes) is protected by a contract a rename can actually break; **472** are refused
on a basename match against a real generator nameset and break **no** reader when renamed.
The nameset is genuine; extending it to the mirrors by basename is the weaker step.

## 5. Answer to the brief's five questions

1. `declared()` = **139** (called). The 473 = **473** `PLAN.tsv` `DECLARED` rows
   (`note.startswith("DECLARED")`). Difference = **334 file copies of the 139 names**.
2. It is a census of **two different things** — files vs names — not a census bug. The 139
   distinct basenames over the 473 equal `declared()` exactly.
3. The contract does exist for the nameset (§3, pasted-ready in `CONTRACT.md`), but the
   refusal applied it to mirror **copies** by basename, where only `D0-run-summary.txt` is
   actually opened.
4. Tested on three: t1 breaks (`plant.py`), t2 does not (control), t3 breaks for `xcheck.py`
   (0->1) though it reads its own root, not the mirror.
5. named by a committed reader: **140**; named only by `declared()`: **333**; named by
   nothing: **0**.
