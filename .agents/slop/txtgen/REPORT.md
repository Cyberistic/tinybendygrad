# `.txt` GENERATORS, not `.txt` FILES — what I found and what I changed

`.agents/slop/txtgen/` · 2026-10-06 · **nothing committed.**

Every instrument here is runnable and prints its own verdict. Nothing in this directory is prose
about a run somebody else did.

| instrument | question | verdict |
|---|---|---|
| `declared-completeness.py` | is `checks/differ.py`'s `declared()` COMPLETE? | **YES, measured twice** |
| `orphan-plant.py` | does the carve-out catch a `.txt` it does not declare? | **YES, both directions, planted** |
| `docs-agree-with-driver.py` | do three documents agree with `helpers-tc-gate.sh`? | was **NO ×3**, now **YES ×3** |
| `census-cache-plant.py` | did `census.py`'s rename move the READ site too? | **YES** |

## 1. THE THREE GENERATORS, AND THE COUNT

`checks/no-txt.py` before → after. **The hard set moved 451 → 403, and the excused set moved
103 → 139**, and NEITHER number is mine: seven units are deleting in parallel, and the excused set
grew because another unit extended `differ.py`'s tables from 8 to 16 graphs. What is mine is the
column below it.

| owning generator | before | after | what I did |
|---|---|---|---|
| `.agents/slop/helpers-tc-gate.sh` | **0** | **0** | fixed the generator: `$GT.py` → `$GT.rows` at all 4 sites |
| `checks/gate_norm.py` | **1** (`checks/gate.txt`) | **0** | generator now writes `checks/gate.out` |
| `checks/census.py` | **0 on disk, 1 latent** | **0 on disk, 0 latent** | generator would have written `checks/rows-*.txt`; now `.rows` |
| — no generator, **0 readers** — | 1 (`checks/census.txt`) | 0 | deleted |
| — no generator, **0 readers** — | 1 (`checks/e2e-mm-gate.txt`) | 0 | deleted |
| `gates/gatekit.py` | 0 | 0 | **NOT MINE** — see §5 |
| `runs/graphcmp/D` undeclared | 0 | 1 transient | another unit's interrupted run; §4 |
| **everything else (other units)** | ~447 | **395** | not mine |

**READ THE DELTA CAREFULLY. THE HARD SET IS FALLING FOR TWO REASONS AND ONLY ONE IS MINE.**
Mine is 3 → 0. The rest is seven units deleting in parallel: the set read **451 when I started and
398 when I finished, and I removed 3 files.** The excused set went 103 → 139 because another unit
extended `differ.py`'s tables from 8 to 16 graphs, which is *more* `.txt` being legitimately
declared. **Neither the 451 nor the 398 is a stable number while the sweep runs, so quote the
owned-generator column, not the total.**

**THE HEADLINE IS NOT THE COUNT. IT IS THAT ALL THREE GENERATORS ARE DEAD.**

| generator | input it needs | state |
|---|---|---|
| `helpers-tc-gate.sh` | `.agents/slop/helpers-oracle.py`, `helpers-tc.bend` | **DELETED by the sweep** |
| `gate_norm.py` | `canon.py` (`import canon` at `:47`) | **DELETED by the sweep** |
| `census.py` | `graphcmp` (`import graphcmp` at `:15`) | `checks/graphcmp.py` DELETED |

The sweep is commit `371cc64c9`, whose own message reads *"THE SWEEP DELETED 3,603 FILES AND TOOK
**166 REPRODUCTION PATHS** WITH THEM — BECAUSE A CITATION WAS A **SUFFICIENT** CONDITION FOR KEEPING
AND NOT A **NECESSARY** ONE."* It deleted the drivers' INPUTS and kept the drivers, the citations
and `tinybendygrad/helpers.bend:14`, which still tells a reader to `sh
.agents/slop/helpers-tc-gate.sh`. **A gate's inputs are a NECESSARY condition for the gate. This is
the same defect as the two `sys.exit(2)` gates and as e2e stages 3/5: a gate whose required input
was deletable while the gate still named it.**

So I fixed the generators anyway, and that is the right call for a reason that is not sentiment:
**a dead generator is exactly how a false rename survives.** `helpers-tc-gate.sh` could not run, so
the only evidence available about its output was three prose documents — and all three were wrong
about it. The fix had to be at the generator precisely because there was no run to catch it.

## 2. THE THREE DOCUMENTS WERE RIGHT ABOUT NOTHING

`REVIVE.md:217`, `.agents/TODO.md:320`, `bend2-constraints.md:24437` carried the **same pair** of
claims, and **both halves of both were false simultaneously**:

- claimed the file moved to **`oracles/helpers-tc-gate.rows`** — nothing was ever moved into
  `oracles/`; the driver's `GT=` prefix is `.agents/slop/helpers-tc-gate`;
- claimed **"the driver now writes `$GT.rows`"** — it wrote `$GT.py`. Sites `:34`, `:56`, `:58`.

And they quoted a run as evidence: `237 shared rows, 3 lanes identical`. **That line is printed by
the driver either way** — it is `wc -l < "$GT.$ext"` inside a script whose every site agreed with
itself. So the quoted output certified nothing about the extension at all.

`docs-agree-with-driver.py --against HEAD` replays the committed driver **and** the committed
documents together (`docs-agree-BEFORE.out`): **RC=1, all three DISAGREE**, on the extension and on
the destination. Against the working tree (`docs-agree-AFTER.out`): **RC=0, all three agree.**

**THE RULE THIS ADDS, now written into `bend2-constraints.md` as an amendment to V-9: a citation and
a write path are the same token, and three documents restating one another are ONE witness, not
three.** A rename claim is a claim about a `>` redirection, so it is checkable — read the `GT=`
prefix and the lane names, and believe prose about neither.

## 3. IS `declared()` COMPLETE? YES — MEASURED TWICE

`.agents/slop/difftxt/DECISION.md` rested the carve-out on *"103 of 103, 0 orphan match"*, and the
brief is right that this is evidence about **one run's tree**, not about the function. So
`declared-completeness.py` answers it by RUNNING `cmd_run` with `D` in a sandbox and every
subprocess stubbed to `rc=0`/0 bytes, then enumerating what the driver **wrote** and diffing that
against the declaration. Reading the source would only re-derive from the same tables; four static
checks could not find a single divergence, and the four `capture()`/write literals all sit in
`LITERALS` — which is exactly the evidence that CANNOT detect drift.

It is also the only method that survives the one write site which bypasses every choke point:
`differ.py:301` opens `D2-canon-{side}-{g}.txt` directly, so instrumenting `run`/`write`/`capture`
would have missed 32 names and reported a false pass.

| when | `declared()` | produced | either way |
|---|---|---|---|
| at DECISION.md's 103 | 103 | 103 | **0** |
| after another unit rewrote `cmd_run` to iterate `corpus()` not `WANT` | 139 | 139 | **0** |

**The second row is the load-bearing one.** It is the same question asked again after the driver's
iteration source changed structurally, and the declaration was still exact. That is the property
that matters: it does not rot silently, so long as somebody measures it — which is why the
measurement is a script and not a sentence.

**Honest limit of the method.** The stub returns `rc=0`, which takes the happy branch everywhere —
the branch producing the MOST names. A name reachable only on a failure path would be missed.
Residual 0 in both directions is therefore evidence of completeness on the paths a good run takes,
not a proof over all paths.

## 4. THE ORPHAN CASE, PLANTED BOTH WAYS (`orphan-plant.py`, RC=0)

`DECISION.md` planted one direction. The other one — a **declared name that is never written**, so
the declaration and the tree diverge *silently* — had never been planted by anyone. Both now are,
and both undo themselves in a `finally`.

| plant | expected | measured |
|---|---|---|
| **A** orphan `runs/graphcmp/D/D0-PLANTED-ORPHAN.txt` | unexcused, `UNEXPECTED` | **448 → 449**, `UNEXPECTED` |
| **B** declared `D0-coverage-census.txt` removed | `MISSING` | **`MISSING`**; hard count 449 → 448, correct because the FILE is gone |

Plant A reproduces DECISION.md's `602 → 603` on the live tree. **The carve-out is a DECLARATION and
not a blanket: an undeclared `.txt` under the excused directory is still reported.** Confirmed,
and now confirmed by a plant rather than by a one-off measurement.

**A REAL instance of plant B surfaced on its own, unplanted.** During this session `no-txt.py`
reported `runs/graphcmp/D/.tmp.D6-commute-ordered.txt` — a staged temp from `differ.py:191`
(`tmp = D / f".tmp.{out}"`) left by an **interrupted** run. It is not in `declared()`, so it was
correctly reported as unexcused. **The instrument caught a real leak with no plant involved.** That
is the strongest evidence available that the carve-out is not decorative. `differ.py` is another
unit's file, so I did not touch it — but a run killed between staging and `os.replace` leaves a
`.txt` the sweep cannot classify, and that is worth a cleanup at the generator.

## 5. WHAT IS NOT MINE

- **`gates/gatekit.py` is DIRTY in the working tree** — another unit is renaming `py.txt` →
  `py.rows` and `bd.txt`/`bn.txt` → `.out` **right now**. Per the house rule that change is not
  mine, and I did not edit the file. `gates/artifacts/*/` currently holds **0** `.txt`, so its
  contribution to the count is already 0 on its own.
- **`gates/mixin-op-gate.py:92` and `gates/beautiful-mnist-gate.py:89`** — not read, not edited.
  I note only what is checkable from outside: `gates/artifacts/mixin-op-gate/` is **empty** while
  its eight siblings each hold nine files, which is what a `sys.exit(2)` before `GATE.run()` looks
  like on disk. Another unit owns the fix.
- **`checks/bounded.py` is currently broken** — `NameError: name 'tree' is not defined` at `:235`,
  so every `checks/bounded.py -- CMD` invocation in this project currently dies. Not mine; it is
  why §6's gate runs are unguarded.

## 6. GATES RUN, BEFORE AND AFTER

| gate | before | after | note |
|---|---|---|---|
| `helpers-tc-gate.sh` | **RC=2, NO-VERDICT, 0 bytes** | **RC=2, NO-VERDICT, 0 bytes** | **cannot run** — inputs swept. Identical failure, so the rename introduced no regression, but **neither run is a measurement.** |
| `checks/gate_norm.py` | **`ModuleNotFoundError: No module named 'canon'`** | same | **cannot run** — `canon.py` swept. Never reached the write, so the new extension is verified by reading, not by a run. |
| `checks/census.py` | cannot import `graphcmp` | same | **cannot run.** Instead `census-cache-plant.py` stubs the dead import and plants a warm cache: **`CACHE, 1 row` — the read site moved with the write site, and a `.txt` cache left beside it is ignored.** |
| `checks/no-txt.py` | 451 hard, rc=1 | **398 hard, rc=1** | still red: 395 belong to other units |
| `declared-completeness.py` | — | **rc=0** | 139 = 139 |
| `orphan-plant.py` | — | **rc=0** | both plants caught |
| `docs-agree-with-driver.py --against HEAD` | **rc=1** | — | 3/3 disagreed |
| `docs-agree-with-driver.py` | — | **rc=0** | 3/3 agree |

**THREE OF THE FOUR GATES I TOUCHED CANNOT RUN ON THIS TREE.** That is the finding, not a
disclaimer on it. `checks/census.txt` and `checks/e2e-mm-gate.txt` were deleted only after
establishing they had **zero readers and zero writers** — `checks/e2e-mm-gate.txt` was byte-identical
to `runs/e2e/e2e-mm-gate.txt`, which is the file the live generator writes and the only one
`checks/e2e.py:340` reads.

## 7. UNSETTLED

- **`checks/census.py:5` still cites `.agents/slop/arith/rows-*.txt`**, describing `both-census.py`'s
  cache. That directory holds no `rows-*` files and `both-census.py` is not mine. Left alone.
- **`checks/check.out` is a 0-byte `.out` with no writer and no reader.** Not a `.txt`, so not in
  this count, but it is the same orphan shape as the two I deleted.
- **The `.tmp.*.txt` leak (§4)** belongs to `differ.py`, another unit's file.
- **The 395 remaining `.txt`** are in `oracles/` and `.agents/slop/` and belong to other units'
  oracles. `no-txt.py` stays red until they are done; it was red before I started.

## 8. I DID NOT COMMIT, BUT TWO OTHER COMMITS ABSORBED MY WORKING TREE

Worth stating plainly, because "not committed" is otherwise read as "still pending review", and
part of this is not:

| what | absorbed by |
|---|---|
| the 3 file deletions (`checks/{census,e2e-mm-gate,gate}.txt`) — staged by `git rm` | `a8fdc12f7` (the `abi4` unit) |
| `REVIVE.md:217`'s correction | `f541da0f1` (the `spine` unit) |

Both units committed from a shared index while my deletions and edits sat in it. The content is
what I intended and both corrections are verified present on disk, but **the review surface for
those four edits is a commit titled for a different unit**, and the three deletions are in a commit
whose message is about a regression in a gate. Anyone bisecting will not find my reasoning there.
Still uncommitted and mine alone: `helpers-tc-gate.sh`, `checks/gate_norm.py`, `checks/census.py`,
`TODO.md`, `TOOLS.md`, `bend2-constraints.md`, and this directory.