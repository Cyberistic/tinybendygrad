# MUT-LEDGER — the mutated copies of the real tree, and the live tree's non-port files

Written 2026-10-05. Rule prefix **`MUT-`**. Instruments, all regenerable:
`.agents/slop/mutledger/classify.sh` (verdict per file), `BLOBHIST.tsv` (one-pass blob history),
`ALLSHADOW.tsv` (repo-wide verdict table), `PLANT-NATURE.txt` (semantic-vs-comment split),
`LIVE-AUDIT.tsv` (port membership of the live tree), `PROOF-GREP.txt` (the greping-reader proof).

## 1. Method, because the verdict rests entirely on it

Per file, three steps: byte-compare against the live file; if different, `git hash-object` the copy
and look that blob up in the set of blobs that have **ever** existed at that live path, built in
one pass from `git log --all --root --raw` (3,964 path/blob pairs over 406 paths). Then split the
differing lines into comment and non-comment.

- **`IDENTICAL`** — byte-identical to the live file right now. A duplicate, not a mutation.
- **`STALE`** — differs, but equals some **committed revision** of that live path. A real older
  version of a real file. Confusing, not wrong.
- **`PLANT`** — differs, and appears at **no** revision of any path. Unique content.
- **`NOREF`** — no live file at that path at all.

**`PLANT` alone does not mean "mutation".** It means "content nobody committed". That is also true
of a unit's half-finished file, snapshotted mid-edit. The second step is what separates them.

### One instrument bug, because it produced a false answer first

The first run classified **all 18** diffs as `NEVER-COMMITTED-AT-THIS-PATH`. That was wrong: the
probe was `"$c:tinybendygrad/$f"`, and **zsh ate `$c:t` as the `:t` parameter modifier**
("tail"), producing `…79b79binybendygrad/…`. Every `rev-parse` failed, the history set was empty,
and the verdict was vacuously "unique". Had I trusted it I would have reported 18 plants instead
of 2. Fixed with `${c}:`; the same trap is why `agent-core.md` says to verify an instrument before
believing its output.

## 2. Denominators — the scope I was given

| verdict | `MUTANT/` (was `mut/`) | `MUTANT2/` (was `mut2/`) |
|---|---|---|
| `IDENTICAL` | 124 | 95 |
| `STALE` | 17 | 40 |
| `PLANT` | **1** | **1** |
| `NOREF` | 1 | 8 |
| **total** | **143** | **144** |

- **287** files, **287 of 287** are shadow copies or derivatives — each shadows a real port file,
  at the identical relative path (278) or under a mutation suffix (9).
- **2 of 287 are armed plants.** Both are `PROOF.bend`, both are `mutate.py`'s own labelled
  experiments left behind by the last `fresh()`:

| file | `mutate.py` label | mutation |
|---|---|---|
| `MUTANT/tinybendygrad/PROOF.bend` | `M-del` | `def L.flip_preserves_numel(t, flags): {==}` **deleted**, replaced by a comment. Read as `tinybendygrad/PROOF.bend` it says the flip proof is discharged. |
| `MUTANT2/tinybendygrad/PROOF.bend` | `M-bs` | `Equal.cong(…, f, S.zip_max(ra,rb), S.elem_pick(ra,rb), ih)` — the two middle arguments **swapped**. Congruence on the wrong tail. |

- **59 of 287 differ from their live counterpart today; 57 are merely stale.** The sandbox was kept
  in sync by `fresh()` re-copying it, so "differs today" mostly means the live file moved on.
  Measured live: `helpers.bend` went from a 2-line diff to a 109-line diff **between two runs of my
  own classifier**, because a live unit is editing it right now.

## 3. The hazard is ~7× larger than the directory I was pointed at

`find . -name '*.bend' -not -path './tinybendygrad/*'` = **1,834 `.bend` files living in nested
copies of the tree**, across **13** shadow trees. Classifying all of them:

| verdict | count |
|---|---|
| `IDENTICAL` | 1,105 |
| `STALE` | 385 |
| `PLANT` (unique content) | **16** |
| `NOREF` | 59 |

Trees beyond the two I was sent: `render-wt/tinybendygrad` (138 files), `xd1/wt/tinybendygrad`
(136), `runs/gr-init/base/tinybendygrad` (140), `runs/margsym/snap/tinybendygrad` (140),
`dd-cone-wt/{ctl-comment,revert-add,revert-both,revert-push}` (145 each, no `tinybendygrad/`
wrapper), `ddcheck/tree`, `ind/work/tinybendygrad` (6), `strays/{origin,working}/tinybendygrad`
(21 each). `deadarm/bendarm.py:143` already names most of them and excludes them by depth.

**The 16 unique-content files are two different species, and conflating them would be a lie:**

- **2 are deliberate documented mutations** — the two `PROOF.bend` above, 3 and 2 diff lines.
- **14 are uncommitted intermediate states of other units' experiments**, 35 to 3,429 diff lines
  (`render-wt/…/uop/render.bend` 692; `xd1/wt/…/{codegen/decomp/dtype,runtime/ops_dsp,
  runtime/support/elf,runtime/webgpu_call}.bend` 2654/518/3429/297; `margsym/snap/…/ops_bend.bend`
  1254; the four `dd-cone-wt/*` + `ddcheck/tree` copies of `codegen/decomp/dtype.bend` ~1,075 each
  plus `ctl-comment/schedule/memory.bend` 35). Their deltas are whole-file, not clause-sized.

**So the count of armed deliberate mutations readable by any unit is 3, not 2:** the two
`PROOF.bend` plants, plus the live-tree one in §4. The other 14 are **not landmines, they are
somebody's uncommitted work**, and deleting them would be exactly the "restore that discards the
only copy of somebody's work" failure. I touched none of them — they are other units' slop trees.

## 4. Non-port files in the live tree — 31 of 144

Membership test: port iff `tinygrad/<same path, .bend→.py>` exists (186 upstream non-`__init__`
`.py`). `tinybendygrad/` holds 144 files; **31 have no upstream `.py`**. Full list in `LIVE-AUDIT.tsv`.

### A. ARMED PLANT IN THE LIVE TREE — 1 file, and it is the worst thing found

`tinybendygrad/runtime/ops_bend.mut.bend` (149,136 B), a copy of `runtime/ops_bend.bend`
(149,168 B) with **one clause deleted at line 144**:

    live:  Bool.or(is_lane(dt), Bool.or(String.eq(dt, "f32"), String.eq(dt, "bool")))
    plant: Bool.or(is_lane(dt), String.eq(dt, "f32"))

`"bool"` no longer dispatches to the f32 lane. Content unique — not any revision of `ops_bend.bend`.
Three distinct non-live variants of that one file exist in the repo (`ops_bend.mut.bend`,
`margsym/snap/…/ops_bend.bend`, `gr-init/base/…/ops_bend.bend`; four distinct md5s).

**Not removed: `tinybendygrad/` is off-limits to me.** `.agents/slop/e2e.sh:138` already calls it
"a scratch copy", so somebody knew. **This needs an owner.** It counts toward `bend=`.

### B. PROBES still in the routing total — 8 files, all `.bend`

| file | bytes | note |
|---|---|---|
| `probe_f32lit.bend` | 1,317 | **owned by a live unit — reported, not removed** |
| `runtime/zzprobe2.bend` | 2,611 | its own header says `# scratch probe -- DELETE.` |
| `runtime/zzdiag.bend` | 583 | prints diagnostic rows |
| `runtime/zzread.bend` | 350 | reads U32s from stdin |
| `runtime/zzsplit.bend` | 1,008 | probe |
| `runtime/_p6.bend` | 204 | prints F32 bits of 3 literals |
| `uop/probe-mmcore.bend` | 23,478 | self-declared standalone probe |
| `test/_probe/v5.bend` | 742 | probe |

**The router's denominator, measured.** `find tinybendygrad -name '*.bend' | wc -l` = **138**.
`substrate-check.sh:251` prints `ROUTE bend=$n_bend cc=$n_cc node=$n_node no-instrument=$n_none`,
counting every `.bend` it is handed. **`138 − probe_f32lit.bend = 137`.** The coordinator's
`bend=137` is the port count and **one probe is the entire discrepancy**; `ops_bend.mut.bend` is
another, so the honest range is **136–137**. **Every probe a unit forgets to delete moves the
router's own denominator.** Note also that `bendarm.py` excludes `.agents/slop/<dir>/<name>.bend`
at depth 2 but nothing inside `tinybendygrad/`, so `uop/probe-mmcore.bend` and
`test/_probe/v5.bend` are **not** excluded from its census.

### C. SEAM / LANE HALVES — 6 files, not `.bend`, so they route to `cc=`/`node=`. Keep.
`runtime/dtype.{c,js}`, `runtime/sz.{c,js}`, `runtime/webgpu_call.{js,mjs}`.

### D. PORT INFRASTRUCTURE with no 1:1 `.py` — 16 files. Keep.
Spec/proof layer: `LAWS.bend`, `LAWS/spec.bend`, `LAWS/alu.bend`, `LAWS/PROOF-ALL.bend`, `PROOF.bend`,
`PROOF2.bend`. Port-local by their own headers: `base.bend`, `codegen/rewriter.bend`. Ports of a
different upstream file: `codegen/kernel.bend` (`codegen/__init__.py`), `uop/fold.bend` (`uop/ops.py`),
`codegen/decomp/transcendental_f32.bend` (half of `transcendental.py`). Deliberate rule-1 merges,
self-documented: `renderer/tc_ptx.bend`, `renderer/nir_llvmir.bend`. Port of a file **absent from
this `tinygrad` reference**: `sz.bend` (`tinygrad/sz.py` does not exist here) and
`runtime/webgpu_call.bend` (`tinygrad/webgpu_call.py` does not exist here) — flagging, not judging.
Plus `test/dtype_oracle.bend`.

## 5. The shape elsewhere, historically — a habit, not one tree

`git log --all --name-only -- tinybendygrad` yields **61 paths ever present** that are not real port
files. Besides the 9 still in the sandboxes: `runtime/support/memory.staged-mem-{33281,33929,44257,
76137,89780}` (5×~153 KB), `runtime/support/nv/nvdev.staged-{nv,nv1,mmut}-*` (9),
`codegen/late/{gater,linearizer,regalloc}.staged-ra*` (12), `uop/ops.staged-blob-24323`,
`runtime/support/{elf,memory}.bend.mut`, `runtime/ops_amd.bend.mut`, `uop/fold.bend.mut`,
`uop/fold.mut`, `renderer/wgsl.bend.mut`, `uop/probe-mmcore.bend.mut`, `sz.bend.bak{3,4,5}`,
`codegen/late.bend.bak`, `nn/__init__.bend.bak`, `runtime/support/rdma/bnxtdev.bend.{mut,depord.bak,
sweep}`, `schedule/rangeify.staged-rf-60390`, `renderer/amd/generate.bend.gate`, `mixin/.claim`,
`viz/_*.txt`, ~10 `probe*.bend`/`PROBE6.bend`.

**The four the brief named are gone from the live tree, and I checked rather than assumed:**
`memory.staged-mem-*` = 125 commits, `ops.staged-blob-24323` = 111, `elf.bend.mut` = 440. Those
counts need a **glob** pathspec — an exact path returns 0 and reads as "never existed", which is
the same failure as §1. A zero-byte `tinybendygrad/trip` I cannot evidence at all (0 commits under
every path I tried), so I report it as **not found**, not as deleted.

## 6. Mechanism, and why it beats a README

**A sentinel in the directory name: `proof-close/mut` → `MUTANT`, `mut2` → `MUTANT2`.**

A README fails here mechanically, not stylistically. A greping reader's output line is
`path:line:text`, and **the path is the only component they cannot skip**. A `README` is not in the
output at all: a unit running `grep -rn 'def foo' .agents/slop/` never meets one. So a README can
be the ledger *behind* the mechanism, never the mechanism.

Rejected, each against a measured property:

- **Header line in all 287 files.** `mutate.py:10 fresh()` is `rmtree(MUT.parent)` +
  `copytree(LIVE, MUT)` — it destroys everything inside `MUTANT/` and rebuilds it from the live
  tree. 287 edits, all erased by the next experiment. A header also does not appear at the hit
  site, so it never reaches the one moment it is needed.
- **`.gitignore`.** These 287 files are **already tracked** (144 + 138 in the index).
  `.gitignore` does not apply to tracked paths, so it would hide nothing from `git` while
  pretending to.
- **Marker inside `MUTANT/`.** Same `rmtree`. The markers therefore sit **one level up** in
  `proof-close/`, the only level `fresh()` does not touch:
  `00-MUTANTS-READ-THIS-FIRST.txt` and `MUTANT-TREE.md`.
- **Delete the sandboxes.** Rejected, and it is the important rejection: `fresh()` rebuilds all 143
  files from the live tree on the next run, so **a delete is not a fix — it re-arms on the next
  experiment.** The durable fix is the label.

The rename is safe by measurement, not hope: `mutate.py:7` is the **only code** reference to the
path in the repo. Every other hit is prose (`F64-KERNEL.md:159`, `dup/stage3-multiset.md:31`,
`notes/bend2-constraints.md:25270`, `MEASURE.md:83`, `TODO.md:9487`, `f64/repair-dupes.py:21`
docstring) or a comment (`deadarm/bendarm.py:143,149`). `bendarm.py` excludes these trees by
**depth** (`len(relative_to(SLOP).parts) > 2`), not name, and the rename is depth-preserving, so its
exclusion still holds (verified: 4 and 5 parts). `mutate.py:7` is repointed and its docstring now
states that renaming the directory requires changing that line — otherwise `fresh()` silently
resurrects `proof-close/mut` and the mutant tree returns unlabelled.

## 7. Can a greping reader still reach a mutated copy by accident?

**By path, no.** `grep -rn 'flip_preserves_numel' .` returns 17 hits; the two sandbox ones now read
`MUTANT/tinybendygrad/PROOF.bend:` and `MUTANT2/tinybendygrad/PROOF.bend:`, and the sentinel is the
first thing on the line. Before the rename those two were `mut/` (3 characters) and `mut2/` (4). The
13 other trees in §3 are **not** renamed — they are other units' experiment worktrees and outside
my mandate — so a reader grepping the whole repo still meets 14 unlabelled shadow copies. Labelling
those needs the owning units, or one decision to rename every nested `tinybendygrad/`.

**Residual, stated plainly:** a reader who greps the **whole repo** and reads only the `:text`
column can still reach all 3 deliberate mutations. Killing that needs `git rm --cached` on the
tracked shadow copies plus an ignore rule — an index change, therefore a commit, which is the
coordinator's call. It is one command and it is the correct next step.

## 8. What I changed

**Renamed** `proof-close/mut` → `MUTANT`, `mut2` → `MUTANT2`; repointed `mutate.py:7` and
documented the coupling. **Added** `proof-close/00-MUTANTS-READ-THIS-FIRST.txt`,
`proof-close/MUTANT-TREE.md`, this ledger, and the 8 regenerable instruments under
`.agents/slop/mutledger/`. **Deleted nothing. Edited nothing under `tinybendygrad/`**, including
`probe_f32lit.bend`, which a live unit owns and which I only report. **Committed nothing.**