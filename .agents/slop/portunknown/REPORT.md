# The port arm's 24 `UNKNOWN:<needs>` rows — by name, by class, and whether `--apply` should reach them

Unit `portunknown`. Measured 2026-10-06 **14:16–14:22 +0300**. Interpreter `.venv/bin/python`
throughout; `bend` never run. `checks/sweep.py` was **read, never edited** (owned by `sweepport`).
No commit, no `git add`. Read-only against the tree; the only files written are under this directory.

Denominator throughout: **24 `UNKNOWN` rows of the 144-file shipped port** (`tinybendygrad/`).
Population by DISCOVERY: `sweep.port_files()` (`checks/sweep.py:575-596`, `os.walk`, no suffix
filter). Nothing below is a hand list; every name came out of the arm's own output.

---

## Verdict

- **All 24 are `.bend` source; NONE is machine-generated** (0 markers). 5 of the 24 are
  scratch/mutant *derivatives* (not canonical port files) and **`checks/no-strays.py` cannot see
  them** — a name-shape guard, measured (its deep walk runs, finds 0, `rc=0`).
- **The class split is not a property of the port — it is a property of who has cited the port so
  far, and the `sweepport` unit's own REPORT changed it.** `plan-after.out` (14:08) reads
  `residue-internal-citer 16 · belts-disagree 4 · commit-the-report 4`. The same population reads
  `20 · 4 · 0` at 14:21 because `sweepport/REPORT.md` — committed at **14:14:33** (`c0d2689e7`),
  which names all 24 in its §2 — is *inside* `.agents/slop`, so every `commit-the-report` row
  gained a residue-internal citer and moved class. **A census that names the rows it counts becomes
  a citer of them.** (Doctrine: a count carries its timestamp.)
- **No class among the 24 is DEAD IN THIS CALLER (0/24).** The `residue.main` fault `needsaudit`
  found **does not transfer**: `port_report` (`:599-622`) calls `verdict_for` on every port file with
  no `sweep=DELETE` filter, so the `untracked`- and `witness`-dependent branches are reachable there.
  The `witness` branch **fires** (`commit-the-report`, 4 rows in `plan-after.out`); the `untracked`
  branch is reachable but fires **0/144**, because 143/144 port files are tracked and the one that is
  not (`test/_probe/v5.bend`) is cited, so it is `KEEP-CITED`.
- **The refusal to append the port to `rows` STILL HOLDS.** The fallthrough is `return "DELETE"`
  (`:803`); today the port is `0 DELETE / 144`, but the port also yields **1 `ORACLE`** whose
  `--apply ORACLE` action is `shutil.move` into `oracles/` (`:955-964`) — a *move out of the shipped
  tree*. Appendability would make the shipped port **movable and removable**. Report-only is correct.

---

## 1. THE 24, BY NAME AND CLASS

Class column A = the port arm's own output at 14:12 (`.agents/slop/sweepport/probe.out`, the only
captured read that prints **paths**; `plan-after.out` prints counts only). Column B = this unit's
re-read at 14:21 (`probe.out` here).

| # | path (`tinybendygrad/…`) | class A (14:12) | class B (14:21) | tracked | kind | outcome |
|---|---|---|---|---|---|---|
| 1 | `codegen/decomp/dtype.bend` | belts-disagree | belts-disagree | yes | source | **artifact** |
| 2 | `codegen/decomp/transcendental_f32.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 3 | `codegen/gpudims.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 4 | `codegen/late/coalesce.bend` | commit-the-report | residue-internal-citer | yes | source | **reachable** |
| 5 | `dtype.bend` | belts-disagree | belts-disagree | yes | source | **artifact** |
| 6 | `engine/worker.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 7 | `mixin/dtype.bend` | belts-disagree | belts-disagree | yes | source | **artifact** |
| 8 | `nn/datasets.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 9 | `runtime/ops_null.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 10 | `runtime/support/am/ip_scratch_sweep.bend` | residue-internal-citer | residue-internal-citer | yes | **scratch** | **reachable** |
| 11 | `runtime/support/amd.bend` | commit-the-report | residue-internal-citer | yes | source | **reachable** |
| 12 | `runtime/support/autogen.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 13 | `runtime/support/compiler_amd.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 14 | `runtime/support/compiler_cpu.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 15 | `runtime/support/compiler_cuda.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 16 | `runtime/support/compiler_llvm.bend` | commit-the-report | residue-internal-citer | yes | source | **reachable** |
| 17 | `runtime/support/compiler_qcom.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 18 | `runtime/support/compileserver.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |
| 19 | `runtime/support/rdma/bnxtdev.bend` | belts-disagree | belts-disagree | yes | source | **reachable** (artifact hides it) |
| 20 | `runtime/support/zz_objc_mutant.bend` | commit-the-report | residue-internal-citer | yes | **mutant** | **reachable** |
| 21 | `runtime/zzdiag.bend` | residue-internal-citer | residue-internal-citer | yes | **probe** | **reachable** |
| 22 | `runtime/zzread.bend` | residue-internal-citer | residue-internal-citer | yes | **probe** | **reachable** |
| 23 | `runtime/zzsplit.bend` | residue-internal-citer | residue-internal-citer | yes | **probe** | **reachable** |
| 24 | `viz/cli.bend` | residue-internal-citer | residue-internal-citer | yes | source | **reachable** |

Plus the one non-`UNKNOWN` row of interest: `test/dtype_oracle.bend` = **`ORACLE`** (basename
matches `ORACLE_WORD`, cited by the corpus), which `--apply ORACLE` would **move out of the port**
into `oracles/` (`:955-964`). The remaining 119 are `KEEP-CITED`.

---

## 2. WHY THE SPLIT MOVED (`16 · 4 · 4` → `20 · 4 · 0`)

Measured facts, not inference:

- `sweepport/REPORT.md` is **committed** (`git ls-files` lists it; `git log` → `c0d2689e7`,
  **2026-10-06 14:14:33 +0300**).
- It names all 24 (§2 of that report is this exact list).
- `committed_files` reads `git show HEAD:<path>` for tracked `.md` under `.agents/slop` at ANY depth
  (`checks/sweep.py:343-345`), so the report entered the citation corpus the moment it was committed.
- It is inside `.agents/slop`, so every file it names gains a citer for which `in_residue` is True.

Consequence: the 5 rows that were `commit-the-report` (no citer at all) became
`residue-internal-citer` (every citer inside residue). **The `commit-the-report` class is
self-erasing the moment a slop report names the file** — which is what a census of the file does.
It is not a bug in the port arm; it is the arm measuring a live tree.

Per-file citers (14:21, from `probe.out`): every one of the 20 `residue-internal-citer` rows has
**`citers_outside_residue = []`**. `coalesce.bend`, `amd.bend`, `compiler_llvm.bend`,
`zz_objc_mutant.bend`, `viz/cli.bend` are now named **only** by `.agents/slop/sweepport/REPORT.md`
— this report's own ancestor.

---

## 3. THE THREE OUTCOMES — COUNTS, EACH WITH ITS DENOMINATOR (24)

| outcome | n / 24 | what it means here |
|---|---:|---|
| **REACHABLE** — condition constructible, row unwritten | **21** | a committed report **outside** `.agents/slop` and `runs` (a `checks/*.md`/`gates/*.md` report, `.agents/*.md`, or `AGENTS.md`) naming the basename flips the row to `KEEP-CITED`. **Named constructor:** that citation. Demonstrated by rows 1/5/7, which have 18 such citers and would be `KEEP-CITED` if not for the belt branch (§4). |
| **DEAD IN THIS CALLER** | **0** | none. The `residue.main` filter fault does **not** transfer to `port_report` (§5). |
| **CLASS RIGHT, FILE FINE** — tokenizer artifact | **3** | rows 1, 5, 7 (`codegen/decomp/dtype.bend`, `dtype.bend`, `mixin/dtype.bend`): `belts-disagree` is a pure tokenizer disagreement, and these files already have **18 authoritative citers (8 `checks/*.py` + 3 `gates/*.py` + 7 `.agents/*.md`)**. The class is true about the *corpus* and says nothing wrong about the file; the file needs nothing. |

Row 19 (`runtime/support/rdma/bnxtdev.bend`) is counted **REACHABLE**: its `belts-disagree` is
`only_A = ['.agents/slop/MUT-LEDGER.md']` — i.e. the tokenizer artifact is *hiding an
only-in-residue state*. Belts fixed, it becomes `residue-internal-citer` with
`citers_outside_residue = []`. It is the 21st reachable row, not a 4th artifact.

**So: 21 reachable · 0 dead-in-caller · 3 class-right/file-fine. Denominator 24.**

---

## 4. WHAT WOULD CONSTRUCT EACH REACHABLE ROW (the named constructor)

`verdict_for` fires `residue-internal-citer` at `:768-769`:
`if belt_b and not {c for c in belt_b if not in_residue(c)}` — **every citer lives in `.agents/slop`
or `runs`**. `in_residue` (`:465-473`) is True for `.agents/slop/**` and `runs/**` only.

Therefore a row leaves `UNKNOWN` when a citer appears **outside those two roots**. Concretely, for
any of the 21: commit a report under `checks/` or `gates/`, or add the basename to
`.agents/TOOLS.md` / `AGENTS.md`, **naming the basename as a whole path token**. The belts index the
basename (`:530`), so `tinybendygrad/codegen/gpudims.bend` and `gpudims.bend` both count. This is
literally "nobody wrote the row": the file is shipped source, and the only rows naming it are slop
diaries.

For the 3 artifacts, no content edit helps: `belts-disagree` (`:745-752`) is the **tokenizer** —
belt A (`mentioned_filenames`, regex ending `\.[A-Za-z0-9]+`) and belt B (`whole_path_tokens`,
`str.translate`) disagree on a citer. Measured diff:

- rows 1, 5, 7: `only_A = ['checks/wallcheck.py']`, `only_B = []` — belt A sees a `dtype.bend`
  token in `checks/wallcheck.py` that belt B splits as a longer hyphenated token.
- row 19: `only_A = ['.agents/slop/MUT-LEDGER.md']`, `only_B = []`.

Because the `belts-disagree` branch **precedes** the citation branch (`:792`), a file with 18
authoritative citers is still `UNKNOWN`. The repair is a classifier change, not a port change.

---

## 5. THE DEAD-IN-CALLER QUESTION — DOES IT TRANSFER? (NO)

`needsaudit/REPORT.md` §3 measured that `residue.py`'s `commit-or-drop` and
`commit-the-report-that-explains-it` **fire 0 live** because `residue.main` classifies only
`sweep=DELETE` rows, and `verdict_for` returns `UNKNOWN` for exactly those rows, so they never reach
`residue.classify`.

**`port_report` (`checks/sweep.py:599-622`) does not do that.** It loops every `port_files()` row and
calls `verdict_for(rel, f.mentioned, f, set())` directly; it is not fed by `residue`. So the filter
that kills the two residue clauses is absent. **Per file:** for all 24, the class that fired is the
one `verdict_for` chose unfiltered — reachable, by construction.

The one branch that is structurally quiet here is `commit-or-drop` (`:797`, `rel not in f.tracked`):
it is **reachable** (nothing filters it) but **fires 0/144**, because 143 of 144 port files are
tracked (`git ls-files`; the exception is `tinybendygrad/test/_probe/v5.bend`, which is cited, so it
is `KEEP-CITED` and never reaches the branch). So the honest statement is: **not dead in the caller;
dead in the tree — for now.** One `git rm --cached` of an uncited port file makes it fire.

---

## 6. `.bend` SOURCE vs GENERATED, AND `checks/no-strays.py`

- **24/24 are `.bend` files.**
- **0/24 are machine-generated.** No generation marker (`DO NOT EDIT`, `generated by`,
  `autogenerated`, `machine-generated`) in any of them. 19 carry a header
  `# <name>.bend -- tinygrad/<…>.py`; the generator `runtime/support/autogen.bend` is itself
  *source* (a port of `tinygrad/runtime/support/autogen.py`), not an output.
- **5/24 are scratch/mutant DERIVATIVES, not canonical port files** — a different problem from a
  generated file, and the same problem as a stray:
  - `runtime/zzdiag.bend`, `runtime/zzread.bend`, `runtime/zzsplit.bend` — headerless `import Base`
    probes; `.agents/slop/MUT-LEDGER.md:116-118` and `PROBES.md:158-160` name them **"prints
    diagnostic rows" / "reads U32s from stdin" / "probe"** and `PROBES.md:124` lists them as probes
    already swept into a commit.
  - `runtime/support/zz_objc_mutant.bend` — its own first line names a DIFFERENT file
    (`objc.bend`), i.e. a mutation leftover.
  - `runtime/support/am/ip_scratch_sweep.bend` — its own first line names `support/am/ip.bend`,
    i.e. a copy under a scratch name.
- **`checks/no-strays.py`'s deep guard does NOT catch any of them.** Measured: run at 14:19,
  `0 scratch-shaped in source trees`, `rc=0`. Its `RESIDUE_NAME` regex
  (`no-strays.py:99`) is `\.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$` — a **basename
  shape**. `zz_objc_mutant.bend` ends in `.bend`, not `.mut`; the `zz*` probes end in `.bend`; none
  matches. Grep of the whole port for `RESIDUE_NAME`: **0 hits**. **This is doctrine 1 one level
  down: the deep guard declares its population by a suffix shape, so a scratch file with the shipped
  extension is invisible to it.** A `.bend` scratch probe in the shipped tree is exactly the class
  the guard exists for, and it cannot see it.

---

## 7. SHOULD THE PORT ARM'S ROWS BE `--apply`-REACHABLE? — **NO. THE REFUSAL HOLDS.**

`sweepport/REPORT.md` §4 refused `RESIDUE_ROOTS += ("tinybendygrad",)` because the fallthrough is
`return "DELETE"` (`:803`). **Every part of that reasoning is still true, and two measured facts
strengthen it:**

1. **`DELETE` is still the fallthrough** (`:803`). The port reads `0 DELETE / 144` today, but that is
   a property of the *citations*, not of the arm: the 20 `residue-internal-citer` rows exist only
   because slop reports name them, and the 5 `commit-the-report` rows exist only because nothing
   did. A restructure that un-names a port file reaches `DELETE`.
2. **`--apply ORACLE` is a MOVE** (`:955-964`, `shutil.move` into `ORACLES`). The port has exactly
   one `ORACLE` row (`test/dtype_oracle.bend`). Appending the port to `rows` would let
   `--apply ORACLE` **move a shipped, imported file out of the port into `oracles/`** — the shipped
   tree built differently, or not built. `--apply GATE` is the same move-shaped hazard for any port
   file that ever classifies `GATE`.

So appendability is not merely "a DELETE risk": it is a **MOVE risk** on a tree that SHIPS, and
moving a file the port imports by path is a build break with no `--yes` gate (`:936` gates DELETE
only).

**What a SAFE arm would need** (if the owner wants the port rows to carry MOVEs, e.g. to keep an
oracle in the port's own home):

- A **distinct fallthrough that cannot be `DELETE`.** The clean shape is a port-specific verdict
  function that maps the bare `DELETE` branch to a tagged `UNKNOWN:port-uncited` — `bucket()` =
  `"UNKNOWN"`, and `--apply UNKNOWN` is already refused at `:826-830`. A shipped source file is
  never "an output nobody owns"; that is the claim `DELETE` makes and the claim the port arm must
  not make.
- **An `--apply` guard on shipped source roots.** Before acting on any row, skip rows under
  `tinybendygrad/` (and `tinygrad/`, `test/`, `examples/` if ever walked) regardless of verdict. The
  arm that MOVEs must not be able to point at a shipped path.
- **These are coupled.** A distinct verdict alone still lets `--apply ORACLE` MOVE the port's
  oracle; the root guard alone still leaves the arm inheriting the `DELETE` fallthrough for any port
  file that is not a role/oracle. Both are required, and neither is needed today because the arm is
  report-only and **already prints everything a report needs** (`--plan` names the buckets, the
  `needs=` split, and the `needs=` tags).

**Recommendation: keep `port_report` report-only.** Its current output is the whole finding. Making
it appendable buys nothing (the port's only non-`KEEP` buckets are `UNKNOWN` and `ORACLE`) and costs
a MOVE capability over a tree that ships.

---

## 8. PASTE-READY TEXT AND ORDERED HANDOFF (do not edit `checks/sweep.py` in this unit)

For the `sweepport` owner, in order:

1. **No change required to `checks/sweep.py`.** The report-only arm (`:575-596`, `:599-622`, the
   block at `:900-913`) is correct as it stands; this unit recommends leaving it.
2. **If appendability is later wanted**, the two paste-ready edits, together:
   - In `verdict_for`, replace the bare fallthrough `return "DELETE"` (`:803`) with
     `return "DELETE" if not SHIPPABLE_SEARCH.search(rel) else f"{UNKNOWN}:port-uncited (shipped source; no authority renders or names it)"`,
     where `SHIPPABLE_SEARCH = re.compile(r"^(tinybendygrad|tinygrad|test|examples)/")`.
   - In the `--apply` loop (`:947`), before `if v not in (args.apply or ())`, add
     `if SHIPPABLE_SEARCH.search(rel): continue` so no verdict — including `GATE`/`ORACLE` — can MOVE
     a shipped file.
3. **Re-take the port reading after any corpus commit** — the split is a function of citation, and
   this very report's commit will move rows again (§2). The instrument to re-run, cheaply and
   without a 5-minute bare `sweep.py`, is `.agents/slop/portunknown/probe.py` (one cached corpus
   pass, ≈70 s).
4. **For the scratch/mutant 5** (`runtime/zz{diag,read,split}.bend`,
   `runtime/support/zz_objc_mutant.bend`, `runtime/support/am/ip_scratch_sweep.bend`): the owner
   should decide provenance, not delete — they are `git`-tracked and named by slop reports. If
   `no-strays.py` is to enforce this class, its `RESIDUE_NAME` must stop being a suffix shape.

---

## Reproduce

```
.venv/bin/python .agents/slop/portunknown/probe.py   # 144 files; prints the 24 UNKNOWN rows row-by-row
.venv/bin/python checks/no-strays.py                 # rc=0, "0 scratch-shaped in source trees"
date '+%Y-%m-%d %H:%M:%S %z'                         # the count carries its timestamp
```

Artifacts of this unit: `probe.py`, `probe.out` (14:21 read, all 24 rows with citers and belt
diffs), `probe.err` (empty). No `.txt` file was created. `checks/sweep.py` unchanged
(`git diff --stat -- checks/sweep.py` empty for this unit).
