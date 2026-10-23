# THE CLASS, IN `tinybendygrad/runtime/` -- 225 FALSE CITATIONS, RE-POINTED

Unit: citefix-runtime. Date: 2026-10-23. Commit: `056eeb1d5`.
Tree at the measurement: `HEAD 056eeb1d5` (a frozen `git archive` of it).

## 1. THE SLICE, BEFORE AND AFTER

The census (`.agents/slop/citeclass/census.py`) counts a citation FALSE when the
pin-cite census does not hold it at the pin, and counts it in the SLICE when the
todo-cite gate does not read it. The slice is the class the brief named.

| | rows | FALSE | the census SLICE (false AND unmeasured) |
|---|---|---|---|
| BEFORE (`slice-A.rows`) | 2624 tree-wide | 603 | **225** under `tinybendygrad/runtime/` |
| AFTER (`pin-HEAD.rows`) | 2547 tree-wide | 12 under `runtime/` | **0** |

Measured with the SAME instrument on the SAME tree state: `gates/pin-cite-gate.py`
on a FROZEN copy (`--tree`), cross-referenced with `gates/todo-cite-gate.py`'s own
row set, exactly as `census.py` does it.

`gates/todo-cite-gate.py` on the committed tree: **1131 rows, 0 false** (PASS).

**EVERY ONE OF THE 225 ORIGINAL ROWS** was checked against the committed tree by
`(rel, at)`: **0** of those lines still carries a false citation.

## 2. THE TWO ROWS LEFT DANGLING, AND WHY THEY ARE CORRECT

`gates/pin-cite-gate.py` still reports 2 dangling claims, and BOTH are rows that SAY
the upstream construct is GONE at this pin:

- `tinybendygrad/runtime/ops_amd.bend:231` -- `runtime/ops_amd.py:515 symbol=_amd_program_image
  -- the md5 digest slice -- NOT IN upstream at this pin`. The claim tokens are
  `hashlib`/`md5`, which upstream's `runtime/ops_amd.py` does not have at ANY revision,
  so the census cannot hold the row -- and the row is telling the truth.
- `tinybendygrad/runtime/ops_cl.bend:159` -- `runtime/ops_cl.py:139 symbol=_wait_signal
  -- upstream's old OSX_TIMING_RATIO`. Same shape.

A census cannot express "this is absent"; it can only say "the claim holds nowhere".
Both rows are MEASURED by the todo-cite gate and RESOLVE there.

## 3. THE KINDS OF CHANGE

| kind | what it means | examples |
|---|---|---|
| LINE MOVED | the construct is there at the pin; the port's line number was stale | `ops_dsp.py:79` -> `:87-91 _free`; `ops_qcom.py:303` -> `:298 flag`; `device.py:365` -> `:352 iter_sig`; `helpers.py:69` -> `:70 round_up` |
| SYMBOL NAMED | the citation now carries `symbol=<name>`, the field `todo-cite-gate.py` judges | every re-pointed row |
| UPSTREAM GONE | upstream DELETED the construct; the surviving one is named | `Compiled.pm_bufferize` (deleted in upstream `9ff6db7b0`, "hcq2 no tags") -> `Compiled.pm_encode`/`pm_lower`/`pm_link` at `device.py:374-376`; `Device._copyout_sharded` (deleted in `4e4f6b9fb`) -> `DiskAllocator._copyout` at `ops_disk.py:69-77`; `BufferSpec(nolru=True)` in `ops_metal.py` (deleted in `b41c51306`, "metal icb rm nolru") |
| CLAIM WAS WRONG | the port said something upstream does not do | `ops_webgpu.py:78` keys the binding type off the ADDRSPACE, not off the POSITION -- the port said the opposite and concluded the two derivations agree only by luck; `ops_qcom.py` allocates the stack with `name="stack"`, and upstream's `Device.tag` is GONE (so the stub's `AttributeError` is about the PORT's stub); `ops_amd.py`'s `pm_encode` matches SINK nodes carrying `KernelInfo`, NOT `CUSTOM_FUNCTION` nodes (that was the OLD `AMDDevice.pm_encode`) |
| NEVER EXISTED UPSTREAM | the cited file is OURS | `tinygrad/runtime/ops_bend.py` was OURS until the purge `c2a66ea41` moved it out of `tinygrad/`; `ops_bend.bend`'s table now names the upstream `tinygrad/runtime/ops_python.py` construct each def FORKS |

## 4. THE FINDING THAT MADE MOST OF IT POSSIBLE

**A BARE BASENAME IS NOT A CITATION THE PIN-CITE CENSUS CAN READ.** The census
resolves `helpers.py` with ITS OWN resolver, which REFUSES an ambiguous basename:
`helpers.py` is SEVEN upstream files, so `helpers.py:161` names no file at all and the
row lands in `at_no_revision` -- which is FALSE. The todo-cite gate's resolver CAN
disambiguate it (the port file's own declared target directory is the ambient), so the
two instruments disagreed about the same citation.

Every citation this commit touches now names its file by the FULL upstream path
(`tinygrad/runtime/support/hcq2.py:114`), which BOTH instruments resolve to ONE file.

## 5. THE PROOFS

**COMMENT-ONLY.** `checks/port-compile-gate.py`'s OWN `strip_comments()`, loaded BY
PATH, blank lines dropped, over all 35 files: **35 COMMENT-ONLY, 0 FAILED**
(`.agents/slop/citefix-runtime/commentonly.py`).

**COMPILE.** `.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE
bend process at a time, reading the VERDICT TOKEN:

```
35 files: 35 WITHIN-LIMITS, 0 KILLED-ON-MEMORY, 0 TIMED-OUT
peak: ops_python.bend 1542 MB, system.bend 725 MB, ops_bend.bend 463 MB (ceiling 2048)
```

**PLANT.** `.agents/slop/citefix-runtime/plant.py` edits a COPY of the port tree (never
`git show HEAD:`), moving ONE cited line by six:

```
CONTROL : 0 false row(s) in the 35 file(s) this unit touched
PLANT   : 1 false row(s) in the 35 file(s) this unit touched
   NEW  tinybendygrad/runtime/ops_amd.bend:12  tinygrad/runtime/ops_amd.py:380  [WRONG-LINE]  symbol-moved
PLANT OK
```

**DIGEST.** `checks/differ.py`'s `substrate_digest()` over the port tree:

```
BEFORE 271b8025eac3de9057841ecbb20190dace684321c12546e7cd7d662f100f4434
AFTER  eb6ef8608ec64647a195d5521a4712dd1a288cf9f1cefef9e08e83c003dc56bc
```

(BEFORE = the working tree with this unit's 35 files restored from HEAD.)

**COMMIT.** `git commit --only -F <msgfile> -- <35 paths>`; `git show --stat` and
`git fsck --no-progress` in the SAME command. The commit carries 35 files, all under
`tinybendygrad/runtime/`. `git fsck` reports the 3 PRE-EXISTING malformed trees
(`d57bc484`, `d83cf685`, `3a60f33f`) and nothing else.

## 6. WHAT WAS NOT FIXED, AND WHY

- The 2 dangling rows of section 2: their claims are TRUE ("upstream does not have
  this"), and the census has no class for a true absence.
- The `WALL(p3)` rows in OTHER units' files (13 of them at the time of the last
  reading): not this unit's slice, and they are other units' in-flight edits.
- The `WALL(p3)` rows inside `runtime/` that are FALSE but MEASURED (11 of them at the
  last reading: `ops_metal.bend:202`, `ops_npy.bend:88,89`, `ops_rdma.bend:136`,
  `compiler_cuda.bend:51,64`, `compiler_llvm.bend:83`, `compiler_mesa.bend:78,106`,
  `compiler_qcom.bend:71`, `hcq2.bend:108`): they were NOT in the census's slice (the
  census counted them as measured), and the todo-cite gate resolves every one of them.
  `hcq2.bend:108` was re-pointed anyway.

## 7. THE INSTRUMENTS THIS UNIT WROTE

All under `.agents/slop/citefix-runtime/`, all reading the tree's OWN instruments BY
PATH so they cannot drift from them:

| file | what it is |
|---|---|
| `sym.py` | WHERE IS AN UPSTREAM CONSTRUCT AT THE PIN -- the gate's own resolver, declarations and body spans |
| `find.py` | the claim tokens' locations in an upstream file, with the enclosing construct |
| `plan.py` | a mechanical re-point PLAN for a human to read (not applied) |
| `repoint.py` | a mechanical re-point, with a symbol the gate can resolve |
| `mk.py` / `apply.py` | the patch table and its applier (guard: the line must contain the expected text) |
| `fullpath.py` | rewrite every citation on a touched line to its FULL upstream path |
| `commentonly.py` | the COMMENT-ONLY PROOF, over `checks/port-compile-gate.py`'s own `strip_comments()` |
| `plant.py` | THE PLANT |
| `slice-A.rows` / `slice-C.rows` | the slice, before and after |
| `pin-*.rows` / `todo-*.rows` | the census and the gate's own rows, per reading |
| `compile.out` | the per-file compile verdicts |
| `PLAN.tsv`, `repoint.tsv`, `fullpath.tsv`, `patch-*.tsv` | the patch tables, one per batch |
