# `sweepdirs` — `self_output_dirs()` returns 1; the population is 22 directories; the difference is **85 deletable paths**

Unit report, **2026-10-15T09:01Z – 09:21Z**, HEAD **1b4983301** (it moved twice while this ran —
`b23f4a885` at 09:01:21Z, `265d31b7d` at 09:04:36Z — as other units committed).
**Landed: `.agents/slop/sweepdirs/` only. `checks/sweep.py` WAS NOT TOUCHED: the correction is
REFUSED, with the set in §3.** No `sweep.py` entry point was run (machine budget), so no `--plan`
transcript exists; every number below comes from four text/AST runs of my own instrument.

## 0. THE ANSWER

| question | answer | denominator | when |
|---|---|---|---|
| what `self_output_dirs()` returns | **1** (`.agents/slop/residue`) | the resolver's census: 3 written, 7 read → 1 unread | 09:04:36Z |
| **corpus members that shipped entry removes** | **0 of 692** — it is INERT | 692 = `corpus(("residue",))` = `corpus(())` | 09:21:32Z |
| the same question, population by WALK | **22** directories | 1,934 tracked `.py` → **49 written**, 48 read | 09:14:25Z |
| the same question, + the shell belt | **48** directories | 2,548 tracked code files (614 non-`.py`) | 09:14:44Z |
| **paths newly authorised for DELETE by 22 dirs** | **85**, 3,635,633 B | 5,435 residue rows | 09:14:25Z |
| **paths newly authorised for DELETE by 48 dirs** | **86**, 3,639,317 B | 5,435 rows | 09:14:44Z |
| the same claim at FILE granularity | **130 files, 0 new deletions** | 1,934 tracked `.py` | 09:15:13Z |

**THE BRIEF'S "ROUGHLY 190 OUTPUT DIRECTORIES" IS `gates/gendirs.py`'s 194, AND IT IS A DIFFERENT
QUESTION.** `.agents/slop/gendirs/TABLE.md:25` counts **194** distinct target directories for a scan
of 1,560 source files — *every* directory anything in the tree writes into, including
`runs/graphcmp/D/`, `checks/gen/`, `langs/out/`, `gates/oracles/`, `oracle/gateport/oracles/`. Its own
`.agents/slop/**` row is "**~380 dirs**" (`TABLE.md:55`). `self_output_dirs()` is scoped to
`.agents/slop/<dir>` by `slop_dir()`, so neither 194 nor 380 is its population. **The number is not
reproducible for the question that is asked; the answer to that question is 22, and 22 is worse than
1.**

## 1. WHAT IT COMPUTES, AND WHY IT RETURNS 1 — READ, NOT RUN

Three functions stacked, and each one narrows the population by a rule that is not the tree's.

1. **Which files are instruments** — `_instrument_files()`, `checks/sweep.py:538-553`:

   ```python
   for base in ("checks", "gates"):                                        # :549
   ...
       out += [os.path.join(dirpath, f) for f in sorted(filenames) if f.endswith(".py")]   # :552
   ```

   A walk inside **two hand-written directory names**, filtered to **one suffix**. Doctrine 1 calls
   `("checks", "gates")` a hand list and `.py` a suffix set; neither is a population. Its own
   docstring (:541-547) says the walk beats a glob and prints the denominator, and is silent about
   the scope.

2. **Which path a call writes** — `_slop_targets()` (:559-617) parses each instrument and asks
   `_path_slots()` for the write slots. This half is correct and was corrected again on 2026-10-14.

3. **Which directory that path names** — `slop_dir()`, `checks/sweep.py:521-535`:

   ```python
   head = value.split(SLOP_PREFIX + "/", 1)[1].strip("/").split("/")[0]   # :532
   if not head or "." in head or UNKNOWN_MARK in head:                     # :533
       return None
   return SLOP_PREFIX + "/" + head                                         # :535
   ```

   One component, no dot, opaque head refused. **A claim about a FILE is truncated to the whole
   DIRECTORY** — `.agents/slop/residue/000-the-residue.md` becomes `.agents/slop/residue`, i.e. every
   authored `REPORT.md` beside a generated row dump is claimed by the same sentence.

The answer, then, is whatever survives all three. MEASURED 09:04:36Z over 224 `.py` in `checks/` +
`gates/`:

```
writes (3)               = declare, oracletxt, residue
reads  (7)               = clangshim, declare, disagree, f64, jslane2, norm, oracletxt
self_output_dirs()       = writes - reads = { residue }  -> 1        (:661)
self_output_conflicts()  = 2, printed, refused           (:664-670, main() :1361)
```

`checks/sweep.py:649-654` already states this trio correctly and calls the result **1**. So the code
is not lying; **it is answering a question about two directories, and the answer is stable for a
reason that has nothing to do with the tree.** `checks/sweep.py:1262` is the load-bearing line and it
is not in this function at all:

```python
if belt_b and not {c for c in belt_b if not in_residue(c)}:
    return f"{UNKNOWN}:residue-internal-citer (…) "                     # :1263
```

## 2. THE CORRECT POPULATION

**Definition chosen — the code's own question, with the population DERIVED.** An *output directory* is
a `.agents/slop/<dir>` into which an instrument of this tree writes a path, the instrument population
being a **directory walk of the tree's tracked `.py`** (`git ls-files`, 1,934 files) rather than the
two-name hand list. I did not choose "190" or "194": those count directories in `runs/`, `checks/` and
`langs/`, which `slop_dir()` cannot name and this function has never claimed.

`.venv/bin/python .agents/slop/sweepdirs/census.py` — the resolver, the write vocabulary and the read
vocabulary are `checks/sweep.py`'s, **loaded by path**; only `_instrument_files` is replaced:

| population | files | written | read | **written − read** |
|---|---|---|---|---|
| `code` — `checks/` + `gates/`, `.py` (the shipped walk) | 224 | 3 | 7 | **1** |
| `tree` — every tracked `.py` | 1,934 | **49** | 48 | **22** |
| `tree` + `.sh`/`.mjs`/`.js`/`.bend` redirect belt | 2,548 | 75 (49 ∪ 26, disjoint) | 48 | **48** |
| `.py` of the whole tree, **FILE** granularity | 1,934 | **130 files** | — | 130 |

`code` read **224** `.py` at 09:04:36Z and **225** at 09:16:31Z (`census.out`) — another unit was
writing `checks/` while I counted — and the census it yields is **3 written / 7 read / 1** in both.

The 22, at 2026-10-15T09:14:25Z, HEAD `265d31b7d`:
`agend2 devrecord exitzero figurefix flipthird foldgap gatecensus instrepair jjhazard jjreset
oraclerestore prune4 restorekit rosterwire speccite substrate3 sweepport twopass unshardfold
unverified9 w64` (+ the shipped `residue`).

**Everything about the shipped answer is a coincidence of the filter.** The population is 1 instead of
22 because the walk misses 1,710 of 1,934 instruments; and the 22 is not "the answer" either, it is
the same truncation applied to a wider census. `.agents/slop/w64` is in the 22 and holds **0** tracked
`.md`; `.agents/slop/sweepport` holds the *previous* unit's `--plan` transcripts. Neither distinction
is visible from `slop_dir()`'s one component.

## 3. THE SAFETY ANSWER — A SET, NOT A NUMBER

**85 paths, 3,635,633 B, from 5,435 rows at 2026-10-15T09:14:25Z (HEAD `265d31b7d`), every one of them
`UNKNOWN:residue-internal-citer` before and `DELETE` after. 21 committed reports leave the corpus
(648 → 627).** The 48-directory arm is `86 / 3,639,317 B` at 09:14:44Z.

```sh
.venv/bin/python .agents/slop/sweepdirs/delset.py --ast      # 85  -> delset-ast.out
.venv/bin/python .agents/slop/sweepdirs/delset.py --union    # 86  -> delset-union.out
```

**THE 85 IS REPRODUCIBLE, AND THE SECOND RUN IS IN THE DIRECTORY.** `delset.out` is an earlier
revision of the instrument at 09:09:00Z (5 minutes before, HEAD `265d31b7d`, **5,428 rows** against
5,435 here) and it reports the same **85 NEW-DELETE / 21 lost corpus members**. Two row counts, two
revisions, one set.

**THE FILTER, NAMED, BECAUSE "0 PATHS" WITHOUT IT IS A COINCIDENCE AND SO IS "85".** An exclusion does
not touch a row; it removes CORPUS MEMBERS, and the only place the exclusion is read is
`house_excluded` (`:699`) inside `committed_files` (`:822`, and `:815` for the git pathspecs). So the
delta is exactly: *rows whose only citer was a report that just left the corpus.* All 85 were held by
`checks/sweep.py:1262` — the refusal that fires when **every** citer of a row lives inside the
residue. Remove the citer and the refusal cannot fire: the row does not become *known junk*, it loses
the record that anything ever named it, and the next line the classifier reaches is `:1297 return
"DELETE"`. **THE EXCLUSION IS NOT A FILTER ON EVIDENCE HERE; IT IS THE SWITCH THAT DECIDES 85 ROWS.**

```
.agents/slop/agend2/measured.json                     .agents/slop/prune4/committed-unnamed.rows
.agents/slop/bitcastrow/fold.bend.FIXED               .agents/slop/prune4/dircopies.py
.agents/slop/bitcastrow/oracle.rows                   .agents/slop/prune4/duphash.py
.agents/slop/citeresolve/classified.tsv               .agents/slop/prune4/floor.py
.agents/slop/citeresolve/scan.tsv                     .agents/slop/prune4/HANDOFF.rows
.agents/slop/closure/p-scope/one/rows-gate-py.rows    .agents/slop/prune4/liveness.py
.agents/slop/closure/p-scope/per/rows-gate-py.rows    .agents/slop/prune4/movecopy.py
.agents/slop/figurefix/after-devcpu.out               .agents/slop/prune4/orphan.py
.agents/slop/figurefix/after-devunset.out             .agents/slop/prune4/prove.py
.agents/slop/figurefix/before-devcpu.out              .agents/slop/prune4/settle-insprobe.py
.agents/slop/figurefix/before-devunset.out            .agents/slop/substrate3/node.out
.agents/slop/flipthird/arg22.py                       .agents/slop/substrate3/pop.after.out
.agents/slop/flipthird/argseam.rows                   .agents/slop/substrate3/pop.before.out
.agents/slop/flipthird/flipsites.py                   .agents/slop/substrate3/pop.files
.agents/slop/flipthird/flipsites.rows                 .agents/slop/substrate3/pop138.after.out
.agents/slop/flipthird/radius.py                      .agents/slop/substrateid/population.rows
.agents/slop/flipthird/radius.rows                    .agents/slop/sweepport/plan-after-stderr.err
.agents/slop/foldgap/fold.diff.out                    .agents/slop/sweepport/plan-before-stderr.err
.agents/slop/foldgap/population-before-edit.rows      .agents/slop/sweepport/plan-before.out
.agents/slop/foldgap/population.py                    .agents/slop/sweepport/pop.out
.agents/slop/foldgap/population.rows                  .agents/slop/twopass/base-check.out
.agents/slop/foldgap/wmma-broadcast.rows              .agents/slop/twopass/diff-flip.out
.agents/slop/gatesrun/oracle.rows                     .agents/slop/twopass/fold-gate.rows
.agents/slop/instrepair/reclass.py                    .agents/slop/twopass/fold.bend.PRE
.agents/slop/instrepair/RECLASS.tsv                   .agents/slop/twopass/land-check.out
.agents/slop/instrepair/repoint.py                    .agents/slop/twopass/oracle.rows
.agents/slop/instrepair/rerun.json                    .agents/slop/twopass/plant.bend
.agents/slop/instrepair/rerun.py                      .agents/slop/twopass/refusal-after.rows
.agents/slop/instrepair/RESTORED.tsv                  .agents/slop/twopass/regress.rows
.agents/slop/instrepair/TCPTX-REPOINT.tsv             .agents/slop/twopass/twopass-oracle.py
.agents/slop/jjhazard/correlate.tsv                   .agents/slop/twopass/twopass-regress.py
.agents/slop/jjhazard/mechanism_demo.py               .agents/slop/txtexec/tally.py
.agents/slop/jjhazard/mechanism-demo.out              .agents/slop/unverified9/classify.json
.agents/slop/jjhazard/passive-watch.tsv               .agents/slop/unverified9/gather.json
.agents/slop/jjhazard/primitive_tests.py              .agents/slop/unverified9/gather.py
.agents/slop/jjhazard/primitive-tests.out             .agents/slop/whichgroup/rows/rows-gate-py.rows
.agents/slop/jjhazard/repro_index_reset.py            .agents/slop/whichgroup/snap/rows-gate-py.rows
.agents/slop/jjhazard/repro_mechanism.py              .agents/slop/jjreset/jj-facts.rows
.agents/slop/jjhazard/repro-mechanism.out             .agents/slop/livenum/named.tsv
.agents/slop/jjhazard/watch_correlate.py              .agents/slop/livenum/scan-before.tsv
.agents/slop/jjhazard/watch_index.py                  .agents/slop/oraclerestore/debt.rows
.agents/slop/oraclerestore/prove.out                  .agents/slop/oraclerestore/prove.py
.agents/slop/oraclerestore/verify.out
```

3.47 MB, including `prune4/prove.py`, `twopass/twopass-oracle.py`, `instrepair/reclass.py` — tools
whose only citers were among the 21 committed reports the widened walk drops (residue reports, and
**not necessarily in the file's own directory**: `gatesrun/oracle.rows` is in the 85 while `gatesrun`
is in none of the 22). **The set is dominated by the CLASS of row the refusal exists to protect, not
by junk**: 37 further rows moved the other way
(`UNKNOWN` → `KEEP-CITED`) because removing one belt's citer ended a belt disagreement, so the
exclusion is not even uniformly destructive — it is destructive about exactly the rows nothing else
names.

**AND THE ENTRY THE ANSWER ALREADY SHIPS REMOVES NOTHING: IT IS INERT, WHICH IS THE NUMBER THAT
SHOULD STOP A LANE.** MEASURED 2026-10-15T09:21:32Z, HEAD `1b4983301`:

```sh
.venv/bin/python .agents/slop/sweepdirs/delset.py --inert        # -> inert.out
# shipped   self_output_dirs() = ['.agents/slop/residue'] -> corpus 692
# no entry  self_output_dirs() = ()                       -> corpus 692
# INERT=True  removed_by_the_entry=0
```

`checks/residue.py:EXCLUDED_DIRS` (`:122-134`) already names `residue`, so `house_excluded`
(`checks/sweep.py:699`) answers `True` for every `residue/` path before the entry is consulted; and
`NAMED_BY`'s first pathspec is `:(glob).agents/slop/*.md` (`:188`), **one level deep**, so the git
pathspec `:(exclude).agents/slop/residue/**` (`:675`) cannot reach `.agents/slop/residue/000-the-residue.md`
either. Both routes already cover it. **The one directory `self_output_dirs()` returns is doing no
work at all: the shipped answer is not merely too small, it is a no-op on this tree.**

## 4. REFUSED, AND WHAT IS REFUSED WITH

**Nothing was landed in `checks/sweep.py`.** The corrected population is 22 (or 48), and it authorises
85 (or 86) deletions. Per the brief — and because I cannot run `--plan` on this host to chase the
consequence — the set and the risk are reported instead.

**AND THE DEFECT IS NOT THE RESOLVER'S BLINDNESS. IT IS THE GRANULARITY.** The evidence names a
**file**; `slop_dir()` (`:532`) keeps one component and the exclusion becomes a **directory**. Measured
at file granularity, with the *same* widened walk and no directory rule at all:

```sh
.venv/bin/python .agents/slop/sweepdirs/delset.py --files    # 0 new deletions -> delset-files.out
```

`130` files written by this tree's instruments, of which **7** are `.md`: the 3 `residue/*.md`
(`000-the-residue.md`, `002-unknown.md`, `003-disagreements.md` — out of census in BOTH arms via
`residue.EXCLUDED_DIRS`), `rosterwire/plantprobe/fresh.md` (not a corpus member), and
`todo2/{dashboard,discover,dup}.md` — which ARE corpus members and ARE written by an instrument, so
this arm, which drops the directory entry and installs the 130 files in its place, loses exactly
those 3: the corpus goes `648 → 645` and the ONLY row movement is `UNKNOWN → KEEP-CITED: 1`. A row
is rescued, none is lost. So:

> **1 directory is the shipped answer, 22 is the same answer with the walk fixed, and 130 files is the
> same answer with the truncation fixed. Only the last one is safe, and its safety is structural: a
> write claim about `residue/002-unknown.md` cannot take a sibling report with it.**

That is a contract change — `self_output_dirs()` is named for directories, `house_excluded` (`:699`) is
a prefix test, `self_excludes` (`:675`) emits `:(exclude)<dir>/**` — and it is the shape a later unit
should land, with the `--files` arm as its delete-set proof. It is **reported, not done**: reshaping a
load-bearing exclusion and its three call sites is a repair, and the brief prefers the refusal.
`FS_DELETES` (`:285`, DEAD 5) was not touched.

## 5. METHOD, AND WHAT THESE NUMBERS ARE NOT

- One resolver, loaded by path: `census.py` calls `sweep._scopes`, `_path_slots`, `_resolve` and
  `SLOP_PREFIX`; `delset.py` calls `sweep.committed_files`'s membership rule, `tracked_files`,
  `residue_copies`, `declared_names`, `mentioned_filenames`, `whole_path_tokens`, `verdict_for`,
  `bucket`, `walk_residue`, `live_units`. **No resolver, tokenizer or classifier was re-implemented.**
- The corpus is read once for both arms with `git cat-file --batch` (one process) instead of 648
  `git show`s; the text is `HEAD:<path>`, as `committed_files` uses, and index-only entries answer
  `missing` and are skipped exactly as `git show`'s rc≠0 skips them.
- **NOT APPLIED: the per-file liveness overlay** (`classify()`'s `live_set`). Both arms share its
  absence, so the DELTA is unaffected; the absolute `DELETE=2537` is a superset of the sweep's.
- **`.py` only for the AST arms.** The `.sh`/`.mjs`/`.bend` half is a line regex (`shell_belt`), which
  is why §2 gives 22 and 48 rather than one number.
- The tree moved while I measured: HEAD `b23f4a885` at 09:01:21Z → `265d31b7d` at 09:04:36Z →
  `1b4983301` at 09:21:32Z; the row count read 5,428 / 5,430 / 5,435 / 5,437 across four runs;
  `LIVE-UNIT` read 15 / 20 / 22. Every number above carries its own timestamp.
- `--inert` (`delset.py`, 3.9 s) is the one mode that touches no classifier: it answers whether the
  shipped entry removes a corpus member at all, and it answers `692 = 692`.
- No gate was run: no `sweep.py --plan`, no `bend`, no `differ.py`, one process at a time, longest
  run 29.4 s. Nothing was staged, committed or deleted; `checks/sweep.py` is clean in `git status`.
