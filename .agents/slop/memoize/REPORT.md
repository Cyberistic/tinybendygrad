# `memoize` — the per-item recomputation in `checks/sweep.py`

Unit `memoize`, 2026-10-14. Scope: `checks/sweep.py` and `.agents/slop/memoize/`. Nothing staged,
nothing committed, per the brief. Host: 12-core laptop, three concurrent agents, `--plan` never run.

**VERDICT OF THIS UNIT: PASS.** Every check I ran finished inside 10 s, under ~200 MB, one process
at a time, and none of them was `--plan`, `--selftest`, `differ`, or a corpus emission.

---

## 0. HOW MY OWN MEASUREMENT WAS WRONG, FIRST, WITH THE BEFORE-VALUE

I measured `verdict_for` at **3.0171 ms/row** and nearly published it as a third per-row hot spot
(5,344 rows x 3 windows = 16,032 calls x 3 ms = **48 s**). It is wrong. **Before-value 3.0171
ms/row, after-value 0.0378 ms/row — an 80x overstatement.**

**WHY.** I sampled 2,000 rows and started the timer *before* the first `verdict_for` call. The first
call reaches `generated_read_dirs(f.root)` (line 1208), which on a cold cache runs
`checks/runs-artifacts.py:census_unrecoverable(root)`. **MEASURED 2026-10-14 16:47: 16.1 s, once.**
A one-time cost landed inside my per-row timer and I divided it by 2,000. Re-measured with the
census warmed first, same process, same rows: `verdict_for` is **0.0378 ms/row**, so the whole
16,032-call sweep costs **0.6 s** and there is no hot spot there at all.

This is the shape the brief warned about, one level in: **an instrument that cannot see a population
cannot be wrong, because it cannot be anything — and neither can one that cannot see the difference
between a cold cache and a warm one.** `generated_read_dirs` is asked ONCE per process and was
reading as a per-row cost. The same error made an intermediate figure of mine worse in the other
direction: a 100-row slice of `house_excluded` read **0.418 ms/row**, and a separate 487-row slice
read **0.0025 ms/row** — the same function, a 170x disagreement between two runs of it. The
explanation is host contention (three agents, `git show` competing with mine), not the code, and
**every number below is therefore quoted with the sample size, the denominator and the timestamp, and
the only before/after I treat as trustworthy is the one measured back-to-back in a single process
(§5).**

**A SECOND ORDER OF THE SAME ERROR, IN MY FAVOUR, DISCLOSED FOR THE SAME REASON.** I wrote
"974 x 0.549 s = 535 s" for the uncached path from a **6-row** slice. Re-measured later on a
contended host the same slice read **1.145 s/row** (1,115 s extrapolated). I report **535 s**, the
*smaller and therefore less flattering* of the two, because a speedup measured on a slice is a lower
bound only if the slice is the cheap end.

---

## 1. THE REPEATED COMPUTATION, NAMED, WITH THE ARITHMETIC

### 1a. The one the brief names — and it is ALREADY FIXED, UNCOMMITTED

**Function:** `_slop_targets(root)` (`checks/sweep.py:548`), reached from `self_output_dirs(root)`
through `house_excluded(root, rel)` (`:667`).
**What it measures:** every `.agents/slop/<dir>` a live instrument under `checks/` + `gates/`
WRITES to and READS from, by AST over the instruments. `self_output_dirs` then returns
`writes - reads` — the directories that are outputs and not also required inputs.

**How many times per `--plan`, with the arithmetic:**

| step | count | source |
|---|---|---|
| `Facts.__init__` read the corpus | **2x** (lines 923 and 931 at HEAD) | `committed_files(root, self.copies)` |
| each `committed_files` walks `sorted(tracked)` filtering `.md` under `.agents/slop/` | **487** paths | MEASURED 2026-10-14 16:41 |
| `house_excluded` calls per `--plan` | 2 x 487 = **974** | |

**What each row costs.** One `_slop_targets` = one `os.walk` of `checks/` + `gates/` + one
`ast.parse` + one scope walk per file. **MEASURED 2026-10-14 16:41, cold, on this tree: 0.549 s/row**
for 209 instruments, answering 3 written and 7 read directories. Warm: 1 microsecond.

**974 x 0.549 s = 535 s = 8.9 min**, and that is only the two `committed_files` calls. Everything
else in a `--plan` is minutes of order smaller (§6). So **535 s is the floor this bug imposes and
`>15 minutes` is consistent with it**, but I did not run `--plan` to confirm the total.

**There is a second, independent witness with a timestamp, and it is not mine:**
`checks/residue.py:145-147` — *"MEASURED 2026-10-07, un-contended, on this tree: **pre-classify
117 s** (all of it `sweep.py`'s `house_excluded`, which re-parses `checks/` and `gates/` once per
path)"*. Same function, same shape, eight days earlier, measured by a different instrument.

**AND IT IS ALREADY FIXED — IN THE WORKING TREE, UNCOMMITTED.** `git show HEAD:checks/sweep.py`
contains `_GENERATED_CACHE` and `_LIVE_UNIT_CACHE` and **no `_TARGETS_CACHE`**. The memo exists on
disk (line 545) and is not in the commit. I did not stage it, per the brief; **I am reporting it as a
delete-set-shaped fact for whoever commits:** a `--plan` run from a clean checkout of HEAD is the
535-second version, and a `--plan` run from this working tree is not.

### 1b. The one that was still open, and is 40 s

`Facts.__init__` called `committed_files(root, self.copies)` **twice with identical arguments**, the
second only to recover the list of names the first call had already produced.
**MEASURED 2026-10-14 16:44: the corpus is 670 members** (327 named by `NAMED_BY` + 453 tracked `.md`
under `.agents/slop/`, 110 overlapping, deduped), and `committed_files` spends **one `git show`
subprocess per member, at 59.6 ms/name MEASURED over a 20-name sample on a three-agent host**.

    670 names x 59.6 ms            =  40 s per committed_files call
    x 2 calls, same arguments     =  80 s per --plan, discarded

It was not a cross-check and could not have been: **both calls passed the same two arguments.** It
was also a latent incoherence — `self.cites` came from the first read and `corpus_names` from the
second, so the plan printed a corpus count derived from a different read than the index it described.

### 1c. What was NOT the bug, measured so nobody repeats the search

| candidate | measured cost per `--plan` | verdict |
|---|---|---|
| `generated_read_dirs` (`runs-artifacts.py:census_unrecoverable`) | **16.1 s**, once (16:47) | budget line, already cached |
| `house_excluded` re-executing `checks/residue.py` per row | **0.150 ms x 974 = 0.146 s** | fixed anyway, §4 |
| `residue_copies` -> `outside_twins` (sha256 over 7,555 tracked + 5,344 rows) | one pass, ~178 MB | called once |
| `verdict_for` x 16,032 calls | **0.6 s** (§0) | not a hot spot |
| `live_set` / `live_units` | 4 walks, already cached | fine |

---

## 2. THE MEMOIZATION OPPORTUNITY, STATICALLY

**The key.** For `_slop_targets`, the key is **`root`** — it is the only input, and the value is a
function of the tree under `root/checks` and `root/gates`. `_TARGETS_CACHE` is keyed by `root`
(correct). For `house_excluded`'s module load, the key is the **path to `checks/residue.py`**, which
is what names the module and where to find it.

**Is it a pure function of `(root, path)`? NO — AND THIS IS THE INTERESTING PART.**
`_slop_targets` reads mutable state: the **contents of 209 `.py` files** that three other units are
editing. MEASURED 2026-10-14 14:18 -> 14:20, that population went **208 -> 209**, the delta being
`gates/.mut-run.py` written by another unit mid-census (the count is recorded in the function's own
docstring). So **memoizing it is not memoizing a pure function; it is freezing a snapshot**, and
that has to be said out loud rather than papered over with a claim of purity.

**THE ALTERNATIVE IS WORSE, AND THAT IS THE ARGUMENT, NOT A JUSTIFICATION OF THE CACHE.** The
alternative to freezing is re-reading, which is the 535-second bug. There is no third option that
is both live and coherent: any plan that reads the census at t=0 for row 1 and at t=90 s for row 487
can print a corpus count that contradicts its own index, and nothing downstream can detect it,
because **both answers are individually defensible.** The same reason `Facts` is
`@functools.cache`d (`:1094`) and the same reason `classify` (`:1157`) takes ONE walk and applies the
window afterwards. A point-in-time snapshot is the only shape a published report can be checked
against.

**AND THE FREEZE HAS A CONSEQUENCE THAT MUST BE PUBLISHED: the census is a lower bound read at one
instant, and `checks/` + `gates/` grow under it.** The plan's own output names what it excluded
(`main` prints `self_output_dirs(ROOT)` and `self_output_conflicts(ROOT)`), so the reader can see
the value — but the reader cannot see *when* it was taken. That is a gap, not a defect, and closing
it is a separate decision.

---

## 3. THE INVALIDATION QUESTION, EXPLICIT

**What changes between two calls within one run: the files under `checks/` and `gates/`.** There is
no honest "nothing changes" here, and I am not going to write one.

**So the cache must be SCOPED, and it is: to the process.** `_TARGETS_CACHE.clear()` is the
invalidation hook; `load_by_path.cache_clear()` is the other. There is no long-lived caller —
`--plan` and `--apply` each build one `Facts` via `facts()` (`@functools.cache`d per root) and exit,
so there is exactly one snapshot per run, and **nothing in `sweep.py` clears either cache** because
nothing in `sweep.py` needs to. That is now written into the `_slop_targets` docstring rather than
left implicit, since an unstated scope is an unbounded one.

---

## 4. WHAT I CHANGED (`checks/sweep.py` ONLY)

1. **`:84` `load_by_path(path)`** — one `@functools.cache`d loader keyed by path, replacing three
   hand-rolled `spec_from_file_location` + `exec_module` copies at `generated_read_dirs`,
   `house_excluded` and `residue_copies`. **Three copies were three chances to forget a key, and one
   of them had.**
2. **`:109` `_GENERATED_CACHE` IS NOW KEYED BY `root`.** It was a single global slot on a function
   whose value depends on `root`, so **the second root to ask got the first root's answer — a memo
   that ignores its key argument is a global wearing a parameter's name.** MEASURED 2026-10-14
   16:47: the answer is 3 directories (`bin`, `runs`, `runs/graphcmp`) and 16.1 s to compute.
   **LATENT TODAY, and I say so rather than dressing it up:** the only caller is `verdict_for`, and
   every path into it reaches `facts()` with no argument, so no second root exists yet. It is armed
   the moment anything passes one — and `verdict_for`'s own docstring promises `f` exists precisely
   so a synthetic tree can be classified. **Latent is not safe, it is unexercised.**
3. **`:997-999` the corpus is read ONCE.** `self.corpus_names` is appended in the loop that already
   iterated the corpus. The second identical call is deleted. This is a deletion, not a
   reordering: same generator, same arguments, same order.
4. **The invalidation and purity argument is in the `_slop_targets` docstring**, measured, with the
   208 -> 209 datum that shows the tree moves underneath it.

**NOT CHANGED, DELIBERATELY.** `self_output_dirs` still returns `writes - reads` and
`self_excludes` still holds; the brief settles that and I did not re-open it. `declared_names()`
still hand-rolls its own `spec_from_file_location` — it is called **once** per `Facts`, so a cache
there buys 0 s and would add a staleness surface for no gain.

---

## 5. THE PROOF, WITHOUT RUNNING `--plan`

Two independent checks, both bounded, both under 10 s.

### 5a. EQUIVALENCE — 0 disagreements, full population

I re-implemented the old `house_excluded` inline and compared it against the new one on **every
tracked path in the repository**, not a slice:

    MEASURED 2026-10-14 16:52
    487 tracked .md under .agents/slop : 0 disagreements
    7,555 tracked paths (whole tree)  : 0 disagreements

`generated_read_dirs` returns the same 3 directories before and after. **AST parse on the edited
file: OK. `checks/no-txt.py`: rc=0, PASS.**

### 5b. TIMED SLICE — back-to-back, one process, one host

    MEASURED 2026-10-14 16:52, same process, same 487 rows, back to back:
      BEFORE (exec_module per call) : 0.1234 s  -> 0.2534 ms/row
      AFTER  (load_by_path)         : 0.0012 s  -> 0.0025 ms/row      103x
      x 974 calls per --plan        : 0.25 s -> 0.002 s

And the census, with `_TARGETS_CACHE` cleared before every row so the memo is provably absent:

    MEASURED 2026-10-14 16:41 (quiescent) / 16:52 (contended), 6-row slice:
      no memo   : 0.549 s/row  (16:41)   1.145 s/row (16:52)
      memo, cold: 0.647 s ONCE, then 1 microsecond
      x 974 rows: 535 s (16:41)  1115 s (16:52)   ->   0.13 s

**A speedup measured on a slice is a LOWER BOUND, and I am calling it one.** These are 6-row and
487-row slices of a 974-call, 670-member, 5,344-row run. The slices are not the run.

---

## 6. WHAT `--plan` WILL COST AFTER THE FIX — EXTRAPOLATION, NOT A MEASUREMENT

**I DID NOT RUN `--plan`. The following is arithmetic over the per-item costs I measured, and every
term carries the measurement it came from.** If you want a number rather than an extrapolation, run
`checks/sweep.py --plan` on a quiet machine and time it; do not quote the sum below as a result.

| term | calls | measured unit cost | total | measured at |
|---|---:|---:|---:|---|
| `_slop_targets` census | 1 | 0.647 s | **0.65 s** | 16:41 |
| `generated_read_dirs` census | 1 | 16.1 s | **16.1 s** | 16:47 |
| `house_excluded` x corpus candidates | 974 | 0.0025 ms | **0.002 s** | 16:52 |
| corpus read, one `git show` per member | 670 | 59.6 ms | **40 s** | 16:44 |
| `residue_copies` -> `outside_twins` | 1 | ~178 MB sha256 | **unmeasured, order 5-20 s** | — |
| `verdict_for` | 16,032 | 0.0378 ms | **0.61 s** | 16:52 |
| `live_set` walks | 4 | unmeasured | **unmeasured** | — |
| `git status` in `dirty_corpus` | 1 | unmeasured | **unmeasured** | — |
| **SUM OF THE MEASURED TERMS** | | | **~57 s** | |
| **the memo saves** | | | **~535 s (16:41 reading) to ~1115 s (16:52 reading)** | |

**WHAT CHANGED IN THE SUM, AND IT IS NOT ALL ME:** the duplicate corpus read (80 s) and the
per-row module exec (0.15 s) are gone; the 535-1115 s census cost was already gone in the working
tree before I touched it and is gone only because `_TARGETS_CACHE` is on disk and uncommitted.

**THE 59.6 ms/`git show` TERM IS THE LARGEST SURVIVING COST AND IT IS NOT MINE TO CLAIM.** It was
measured on a host running three agents, and a subprocess spawn is exactly the thing that degrades
under contention. A quiet-machine `--plan` is probably well under the 57 s above; so is the 535 s
before-figure, by the same argument. **Both numbers are quoted as readings on a contended host, and
neither should be published without a quiet-machine re-read.**

---

## 7. REPORT-ONLY — things I found and did not touch

- **`checks/sweep.py` has 1 ruff finding, `too-many-blank-lines` at :872.** MEASURED pre-existing:
  the same 1 finding on `git show HEAD:checks/sweep.py` at :447. Not mine, not fixed, out of scope.
- **The duplicated `committed_files` also cost `tracked_files(root)` twice** — a third and fourth
  `git ls-files -z` subprocess per `--plan`, now halved by the same edit.
- **`tracked_files` reads 7,555 paths today; `checks/sweep.py:793` records 4,609.** The tree moved,
  or `jj` added intent-to-add placeholders (`AGENTS.md` records 882 such on this tree). Anyone
  quoting a denominator from `:793` should re-read it.
- **Do not `rm -rf` anything.** Delete-set reported, not acted on: none — I deleted no files.

## 8. WHAT I DID NOT DO

I did not run `--plan`, `--selftest`, `differ`, `graphcmp emit`, any 34-graph loop, any RSS sampler,
or anything under `.agents/slop/peakrss/`. I did not run more than one process at a time. I staged
nothing and committed nothing, and I did not run `jj status`, which on this colocated tree stages
into git's index on any snapshot.