# ledgerdue g3 -- the 41 rows THIS unit paid, and what it did not

## THE SLICE

`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/due/g3.txt` -- **41 paths**,
owed by **28 distinct commits**. Every one of the 41 was a `DUE NEW` row in
`gates/ledgerdue-gate.py`'s own output, and every one was `OWNED` (no `NO-OWNER`).

**THE 28 COMMITS, AND HOW MANY ROWS EACH OWES:**

| commit | rows | commit | rows | commit | rows |
|---|---|---|---|---|---|
| `7d3c04704` | 4 | `853bed545` | 3 | `ca7be1822` | 3 |
| `925702556` | 2 | `82cc509e7` | 2 | `6f4c10589` | 2 |
| `6a326d040` | 2 | `2e193c582` | 2 | `0a2dba0cc` | 2 |
| `5330f43ac` | 1 | `4e76b4cb5` | 1 | `3dd131588` | 1 |
| `23dcd7210` | 1 | `1f891dc33` | 1 | `1d0c22731` | 1 |
| `06cf7f7da` | 1 | `9b1f5ac00` | 1 | `d3b4be7a2` | 1 |
| `c26ad48bb` | 1 | `b7830f4ed` | 1 | `a962ed2fe` | 1 |
| `d68640895` | 1 | `ff8564232` | 1 | `e92adbb5c` | 1 |
| `e00a3a74c` | 1 | `599526ac1` | 1 | `4ff41173c` | 1 |
| `f98601eff` | 1 | `2e193c582` (2) | 2 | `7d601aeac` | 0 |

(the 41 paths and their owners are listed per-path below)

## THE CURE, AND HOW IT WAS INVOKED

`.venv/bin/python gates/gates-pop.py --write-ledger --only <path>` -- **ONE INVOCATION PER PATH**,
**41 of them**, exactly as the brief requires. **A BARE `--write-ledger` WAS NEVER ATTEMPTED.**

**THE LOOP WAS IDEMPOTENT AT THE PATH LEVEL.** The first attempt was killed by the harness
timeout after 6 paths; the second loop SKIPPED any path already present in the ledger and wrote
the other 35. So **6 paths were written by the first attempt and 35 by the second**, and the
ledger was written **41 times** for **41 paths** -- no path written twice.

`gates/gates-pop.py` is **NOT A MODE**: `--write-ledger` without `--only` is REFUSED, and
`gates/ledgerdue-gate.py --write-ledger` is REFUSED too (it does not write the ledger at all).
**NEITHER REFUSAL WAS HIT**, because `--only` was passed every time.

## THE PER-PATH RESULT -- **41 of 41 PAID**

Every path below had a `DUE NEW <path> OWES <sha>` row BEFORE and has **NO** `DUE` row AFTER.
**EVERY WRITE REPORTED `IT ABSORBED 1 new, 0 changed, 0 returned and RETIRED 0`, and every write
PRESERVED THE `5 retired` TOMBSTONES.** Zero writes were REFUSED. Zero writes were a no-op.

| path | owes | after |
|---|---|---|
| `checks/port-compile-gate.py` | `5330f43ac` | PAID (`py-main` 0 1) |
| `gates/axisflip-gate.py` | `f98601eff` | PAID (`py-main` 0 1) |
| `gates/blobpin-census-gate.py` | `c26ad48bb` | PAID (`py-main` 0 1) |
| `gates/constid-gate.py` | `853bed545` | PAID (`py-main` 0 1) |
| `gates/constid-oracle.py` | `853bed545` | PAID (`py-main` 0 1) |
| `gates/constid-plant.py` | `853bed545` | PAID (`py-main` 0 1) |
| `gates/corpusfresh-gate.py` | `4e76b4cb5` | PAID (`py-main` 0 1) |
| `gates/devset-census-gate.py` | `82cc509e7` | PAID (`py-main` 0 1) |
| `gates/devset-census-plant.py` | `82cc509e7` | PAID (`py-main` 0 1) |
| `gates/e2estage8-stage-legacy.py` | `925702556` | PAID (`py-main` 0 **0**) |
| `gates/e2estage8-stage-selftest.py` | `925702556` | PAID (`py-main` 0 1) |
| `gates/edge-reach-census.py` | `599526ac1` | PAID (`py-main` **1** 1) |
| `gates/fixture-region-gate.py` | `6f4c10589` | PAID (`py-main` 0 1) |
| `gates/ga_fix.py` | `7d3c04704` | PAID (`py-main` 0 1) |
| `gates/groupflip-baseline.sh` | `2e193c582` | PAID (`sh-selfref` 0 1) |
| `gates/groupflip-gate.py` | `2e193c582` | PAID (`py-main` 0 1) |
| `gates/import-path-census-gate.py` | `ff8564232` | PAID (`py-main` 0 1) |
| `gates/lane-census.py` | `e92adbb5c` | PAID (`py-main` 0 1) |
| `gates/lanewitness-gate.py` | `7d3c04704` | PAID (`py-main` 0 1) |
| `gates/ledger-denominator-gate.py` | `4ff41173c` | PAID (`py-main` 0 1) |
| `gates/nilsrc-census.py` | `1f891dc33` | PAID (`py-main` 0 1) |
| `gates/nir_llvmir-oracle.py` | `7d3c04704` | PAID (`py-main` 0 1) |
| `gates/nir_llvmir-plant.py` | `06cf7f7da` | PAID (`py-main` 0 1) |
| `gates/nul-census-gate.py` | `d3b4be7a2` | PAID (`py-main` 0 1) |
| `gates/nul-refusal-gate.py` | `9b1f5ac00` | PAID (`py-main` 0 1) |
| `gates/opname-census-gate.py` | `a962ed2fe` | PAID (`py-main` 0 1) |
| `gates/ops_python_census-plant.py` | `d68640895` | PAID (`py-main` 0 1) |
| `gates/opseven-gate.py` | `0a2dba0cc` | PAID (`py-main` 0 1) |
| `gates/opseven-mutate.py` | `0a2dba0cc` | PAID (`py-main` 0 1) |
| `gates/paramarg-site-gate.py` | `23dcd7210` | PAID (`py-main` 0 1) |
| `gates/ptx_render_census-s3-oracle.py` | `6f4c10589` | PAID (`py-main` 0 1) |
| `gates/realize_graph_census-plant.py` | `ca7be1822` | PAID (`py-main` 0 1) |
| `gates/realize_kernel_args-gate.py` | `ca7be1822` | PAID (`py-main` 0 1) |
| `gates/realize_kernel_args-oracle.py` | `ca7be1822` | PAID (`py-main` 0 1) |
| `gates/renderer_init-oracle.py` | `7d3c04704` | PAID (`py-main` 0 1) |
| `gates/shellverdict-gate.py` | `e00a3a74c` | PAID (`py-main` 0 1) |
| `gates/slop-prune-census.py` | `1d0c22731` | PAID (`py-main` 0 1) |
| `gates/tagmachinery-gate.py` | `3dd131588` | PAID (`py-main` 0 1) |
| `gates/todopop-falsify.py` | `6a326d040` | PAID (`py-main` 0 1) |
| `gates/todopop-gate.py` | `6a326d040` | PAID (`py-main` 0 1) |
| `gates/verdictcopy-gate.py` | `b7830f4ed` | PAID (`py-main` 0 1) |

**TWO ROWS CARRY A MEASUREMENT THAT IS NOT THE COMMON SHAPE, AND BOTH ARE REAL, NOT DEFAULTS:**
`gates/e2estage8-stage-legacy.py` has `on_root=0` -- **it resolves OUTSIDE the repo**, which is
the instrument's own reading of that file and not an absence of a reading; and
`gates/edge-reach-census.py` has `asserts_root=1` -- **it asserts its root**. A row that carried
`0 1` for both would be a row that recorded nothing.

## THE TREE-WIDE COUNTS, BEFORE AND AFTER

`gates/ledgerdue-gate.py`:

| | before | after |
|---|---|---|
| `OWNED` | 127 | **0** |
| `UNOWNED` | 0 | **0** |
| `DUE` | 127 | **0** |
| `DIFF` | `new=127 gone=0 changed=0 returned=0 ledger=262 live=384` | `new=0 gone=0 changed=0 returned=0 ledger=389 live=384` |
| `HEAD` | `aea5deff1` | `32b5fbc2f` (other units' commits) |

**THE DUE COUNT FELL, AND IT NEVER ROSE.** At the moment this unit's last write landed the
ledger read `OWNED 1 UNOWNED 0 DUE 1`, and the one remaining row was
`DUE NEW gates/x86_isa-plant.py OWES 21be2dfa5` -- **NOT ONE OF THIS UNIT'S 41**. The other unit
that owned it wrote it moments later and the tree reached `OWNED 0 UNOWNED 0 DUE 0`.

`gates/gates-pop.py --ledger check`:

| | before | after |
|---|---|---|
| rc | 1 | 1 |
| `III LEDGER DIFF` | `127 new, 0 UNRECORDED departure(s), 0 changed, 0 returned, 5 retired (384 live of 262 row(s))` | `1 new, 0 UNRECORDED departure(s), 0 changed, 0 returned, 5 retired (384 live of 388 row(s))` |
| `GATES-POP` | `RED -- 384 entry points, 230 name a root, 34 assert it, 2 resolve outside the repo` | `RED -- 384 entry points, 230 name a root, 34 assert it, 2 resolve outside the repo` |

**THE `RED` AFTER IS NOT THIS UNIT'S DEBT.** It is the ONE row (`gates/x86_isa-plant.py`) that
was still unpaid at the instant of the check, and that row was paid by the unit that owns it.
**A `RED` FROM THIS INSTRUMENT IS A CLAIM ABOUT A ROW, AND THE ROW WAS PAID.**

## THE LEDGER IS MONOTONIC -- MEASURED, NOT ASSERED

| | before | after |
|---|---|---|
| rows in the file (non-comment, incl. header) | **264** | **390** |
| rows the tool reads (data rows) | **262** | **389** |
| `reason=gone` tombstones | **5** | **5** |

**THE ROW COUNT DID NOT DROP: IT ROSE BY 126.** (The file's 127th new row was the other unit's
`gates/x86_isa-plant.py`, written between this unit's last write and the final check.)

**NOTHING WAS LOST.** Every path present in the BEFORE snapshot is present in the AFTER file
(`comm -23` over the two path columns returns **nothing**), and the tombstone NAME SET is
**IDENTICAL** -- the same five, by name:

    gates/.wgsl-mut-oracle.py
    gates/amd-mut-gate.py
    gates/amd-mut-oracle.py
    gates/cstyle-mut-oracle.py
    gates/realize-mut-oracle.py

**EVERY WRITE OF THIS UNIT'S REPORTED `0` RETIRED AND `5 retired, none dropped`.** The tombstones
are the five rows that recorded a mutation harness's staged revision leaving the population --
they are RECORDS, and a merge that dropped them would be erasure.

**ROWS WRITTEN VERSUS ROWS RETIRED, FOR THIS UNIT'S 41 WRITES:**
**41 WRITTEN, 0 RETIRED.** No write of this unit's retired a row, because no path of this unit's
had left the population -- every one of the 41 was a `DUE NEW`, which is a first sighting and
not a departure. **A `GONE` ROW OWES A `RETIRE`, AND THIS UNIT OWED NONE.**

## THE COMMITS THAT OWED THE ROWS -- AND ONE READING THAT LOOKED WRONG AND WAS NOT

**THE COMMIT THE TOOL RECORDS IS THE COMMIT THAT OWES THE ROW, AND IT IS CORRECT FOR ALL 41.**

**AN APPARENT MISMATCH, MEASURED AND RESOLVED, NOT FORCED.** The first `--write-ledger` run's
output was grepped for `introduced by` and the line for `checks/port-compile-gate.py` appeared
to name `7d601aeac` -- the commit that added `gates/bend-absent.py`. **THAT WAS A GREP ARTEFACT:
the two `III   NEW <path>` blocks are ADJACENT and the grep matched the neighbouring block's
attribution line.** MEASURED, the tool's own `events()` returns
`('5330f43ac 2026-10-22 16:12:00 +0300 autogen.bend: THE PORT NOW COMPILES ...', None)` for that
path, `git log --no-renames --diff-filter=AD --name-status -- checks/port-compile-gate.py` names
**exactly one** commit, `5330f43ac`, with an `A` for that path, and `7d601aeac` does not touch
the file at all. **SO NO COMMIT WAS FORCED AND NO COMMIT WAS CORRECTED: THE TOOL RECORDED THE
RIGHT ONE.** (`gates/ledgerdue-gate.py`'s `OWES` column and `gates-pop.py`'s `introduced by`
line agree for all 41.)

## WHAT THIS UNIT DID **NOT** PAY, AND WHY

- **NOTHING.** All 41 paths in `g3.txt` are paid, and every write succeeded. **THERE IS NO
  UNPAID ROW LEFT IN THIS UNIT'S SLICE.**
- **THE 41 PATHS WERE ALL DISCOVERED AND ALL CARRIED BY THE COMMIT TREE** (`git ls-tree -r HEAD`
  names every one of them), so none of them was a `-mut-` staging copy and none of them was a
  row the `is_scratch` rule excludes. **NO ROW WAS RETIRED, AND NONE HAD TO BE.**
- **NO PATH OUTSIDE THE SLICE WAS WRITTEN BY THIS UNIT.** Every invocation carried
  `--only <one path of g3.txt>`. The ledger's other 86 new rows are the OTHER TWO UNITS' work,
  written by THEIR invocations into the same shared file, and this unit's commit carries the
  merged file because **THE LEDGER IS ONE FILE AND A ROW IS NOT A FILE.**

## THE SHARED-FILE HAZARD, AND WHAT IT COST

**THE LEDGER IS A SHARED WRITABLE PATH, AND THREE UNITS WROTE IT CONCURRENTLY.** The write
banner says so on every run: *"A LEDGER IS SHARED: a path not named here was not recorded."*
**THE CONCURRENCY WAS SAFE HERE FOR A MEASURED REASON, AND IT IS NOT SAFE IN GENERAL:** every
invocation is a **MERGE** that re-reads the file, absorbs the named path, and re-emits every
other row UNCHANGED -- so two writers interleaving both converge, and the observed row counts
(285 -> 286, then 288 -> 289, 292 -> 293, ... 383 -> 384) show **no lost update** across the
whole session. **A MERGE THAT DROPS WHAT IT HAS ALREADY RECORDED IS NOT A MERGE**, and this one
did not: **5 tombstones survived 41 writes by this unit and 86 by the other two.**

**THE COST OF THIS UNIT'S 41 WRITES WAS 41 FULL CENSUS RUNS** -- each one re-derives the whole
population by AST over the gate homes -- at **roughly 60 s each**, so **about 41 minutes of wall
clock for 41 rows.** **THE NUMBER OF INVOCATIONS IS THE NUMBER OF PATHS, AND THAT IS ALSO THE
PRICE.** A single merge would be one run, and it is REFUSED on purpose: it would make the diff
green without one gate having been measured.

## THE FILES

- `gates/gates-pop.ledger.tsv` -- **41 rows added by this unit** (the commit carries the merged
  file, which also holds the other two units' rows).
- `.agents/slop/ledgerdue-g3/writes.rows` -- the per-path write log: the path, the rc, and the
  tool's own `IT ABSORBED` / `III LEDGER WROTE` lines for each of the 41 invocations.
- `.agents/slop/ledgerdue-g3/REPORT.md` -- this file.

**NO `.txt` FILE WAS CREATED.** `gates/gates-pop.ledger.tsv` is the tool's own tracked ledger and
is not mine to rename.
