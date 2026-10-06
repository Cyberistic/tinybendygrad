# reprofix — the `D0-coverage-census.txt: 2 runs DIFFER` difference is an UNSORTED SET, and the sort is already the law

Unit: reproducibility pins only (`checks/differ.py`). No `bend` was run. No commit. No write into
`runs/graphcmp/D/`. Evidence in this directory: `census.py`, `census.out`, `plant.py`, `plant.out`,
`reproducer.py`, `reproducer.out`, `envprecond.out`.

**HEADLINE.** The byte-difference is a `set` render, and the fix is a SORT at the site —
`graphcmp-oracle.py:233` and `:278`, landed in `46c52f30d` and `64b174c0a`. `checks/differ.py`
needs **no** change: the pin it was asked to add is already there (`:47`,
`PYTHONHASHSEED: "0"`), so the brief's premise *"PYTHONHASHSEED is not pinned or scrubbed"* is
**FALSE as measured today**. `PINS` contains a `census-rc` row (`:232`) and no `repro` pin; my
change moves neither.

---

## 1. WHICH FILES THE BYTE-COMPARISON COVERS, AND WHO WRITES THE CENSUS

`cmd_repro` (`checks/differ.py:929-947`) runs `run` twice via `clean_run` (`:893-926`), and after
each run snapshots the whole artifact directory with `snap()` (`:727-743`): a sha256 over the
NON-BLANK lines of **every file** under `runs/graphcmp/D`, dot-files pruned, sorted by path. So
the comparison covers **196 files** — every artifact, not a named subset. Two sha-files are
compared byte-for-byte at `:941`.

`D0-coverage-census.txt` is written by:

* **`checks/differ.py:511`** — `capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)`,
  where `capture` (`:309-319`) runs that script with `ENV` and merges **stdout+stderr** into the
  file, then appends `rc=N`.
* Its bytes are therefore the *output text of `graphcmp-oracle.py`*, and a code path in **that**
  file is what can produce two different bytes for the same tree.

The producing code was **`graphcmp-oracle.py:232-233`** (pre-fix):

```python
same = "same" if py["ops"] == bd["ops"] else f"PY-BEND OPs DIFFER: {py['ops'] ^ bd['ops']}"
```

`py["ops"] ^ bd["ops"]` is a **set of strings** and it was interpolated raw. A `set` of `str`
iterates in per-process string-hash order, so the same tree rendered six spellings of one fact.
The second member of the same class is `graphcmp-oracle.py:230`
(`for m in py["residual"] | bd["residual"]: all_res[m] += 1`) — a `Counter` whose **insertion
order** follows a set union, now printed sorted at `:278` (`dict(sorted(all_res.items()))`).

**It is a `set` iteration order, not a seed.** The fix is a sort (a law), not a pinned seed. The
seed ALSO happens to be pinned; see §5.

## 2. THE COUNTEREXAMPLE — from EXISTING artifacts, no `bend`

Two runs of the same tree, both on disk, render the SAME op-set in TWO orders:

```
.agents/slop/rerun/D-before/D0-coverage-census.txt            (PRE-fix,  raw set)
  allred ... [PY-BEND OPs DIFFER: {'RANGE', 'PERMUTE', 'COPY', 'REDUCE', 'ALLREDUCE', 'MUL'}]
  cdiv   ... [PY-BEND OPs DIFFER: {'CDIV', 'GROUP', 'CMOD', 'PERMUTE', 'REDUCE', 'MUL'}]

.agents/slop/figurefix/plant/D-live/D0-coverage-census.txt    (POST-fix, sorted list)
  allred ... [PY-BEND OPs DIFFER: ['ALLREDUCE', 'COPY', 'MUL', 'PERMUTE', 'RANGE', 'REDUCE']]
  cdiv   ... [PY-BEND OPs DIFFER: ['CDIV', 'CMOD', 'GROUP', 'MUL', 'PERMUTE', 'REDUCE']]
```

Same tree, same membership, two renderings. `flip` (`{'GROUP'}`) is a one-element set and so
constrains nothing — which is exactly the shape that made the difference survive on only 1 of 196
files.

## 3. THE FIX — at the site, cited

| site | before | after | commit |
|---|---|---|---|
| `graphcmp-oracle.py:233` | `{py['ops'] ^ bd['ops']}` | `{sorted(py['ops'] ^ bd['ops'])}` | `46c52f30d` |
| `graphcmp-oracle.py:278` | `{dict(all_res.items())}` | `{dict(sorted(all_res.items()))}` | `64b174c0a` |

`checks/differ.py` needs **no** edit. Its own writes are already deterministic: `D2-bytediff.txt`
is built from `sorted(D.glob(...))` (`:470`), `artefacts_ok()` reports `sorted(...)` diffs
(`:819-823`), `declared()` is a set used only for membership/sorted diffs, and `device_of_run()`
calls `next(iter(heads))` only after proving `len(heads) == 1` (`:685`).

## 4. PROOF WITHOUT `bend` — the two hashes

`.agents/slop/reprofix/reproducer.py` reads the op sets out of the canonical wire files
`runs/graphcmp/D/D2-canon-{py,bend}-*.txt` (one row per node) and renders
`novel = py_ops ^ bend_ops` BOTH ways — `repr(novel)` (the pre-fix spelling) and
`repr(sorted(novel))` (the post-fix spelling) — over `allred, cdiv, flip, late`. Run under three
seeds:

```
PYTHONHASHSEED=1   RAW sha256=7c893ce3b4a05fcce51c1a7cb2b4d82cedeaff02faf51dc3266208e672ce9db4
                   SORTED sha256=37de984a07676253dd6032246d0fac76a4b06a1af455fab448b35fb458cf5c1b
PYTHONHASHSEED=2   RAW sha256=75a82b22bf52e27d603db29876ad0c24214e62f77e5ddabc7e4c5638caea29a7
                   SORTED sha256=37de984a07676253dd6032246d0fac76a4b06a1af455fab448b35fb458cf5c1b
PYTHONHASHSEED=3   RAW sha256=61721c038bdf70a894ef868050309fc1dd993bde4abab6e26c496c6dea516183
                   SORTED sha256=37de984a07676253dd6032246d0fac76a4b06a1af455fab448b35fb458cf5c1b
```

* **BEFORE (RAW): 3 distinct hashes over 3 seeds** — `7c893ce3…`, `75a82b22…`, `61721c03…`.
* **AFTER (SORTED): 1 hash over 3 seeds** — `37de984a07676253dd6032246d0fac76a4b06a1af455fab448b35fb458cf5c1b`.

The SORTED lines byte-match the PY-BEND rows in the live `runs/graphcmp/D/D0-coverage-census.txt`,
so the reproducer's inputs ARE the live artifacts.

## 5. THE DENOMINATOR — the unsorted-iteration census

`.agents/slop/reprofix/census.py` — population **by discovery, not a hand list**: the artifact
producing scripts are the `.py` literals `checks/differ.py` itself hands to a subprocess. A *write
site* is a `print(...)`/`write*` call. A site is a *candidate* when an order-bearing construct
(a set, a set/dict comprehension, a set operator `^|&`, `.items/.keys/.values`, `dir/glob/listdir`)
reaches its output, directly or through a name bound from such an expression, without a `sorted(...)`
guard. `plant.py` proves both halves.

```
population   = 6 artifact-producing scripts (graphcmp.py, graphcmp-oracle.py,
               graphcmp-dbg-oracle.py, graphcmp-p13-ops.py, checks/differ.py, checks/devpin.py)
write sites  = 119
CANDIDATES   =   9   <- vetted by hand, ALL false positives (see below)
live unsorted=   0
```

Vetting of the 9: `graphcmp-oracle.py:325` and `p13-ops.py:168` iterate `sorted(tal)`/`sorted(tal)` and
only INDEX the counters; `p13-ops.py:79,106` use `dir(...)`, which returns a **sorted list**;
`p13-ops.py:66,51` use dicts built by `enumerate(toposort)`/insertion and read them by key;
`graphcmp.py:2678` walks `digs.items()` where `digs` is filled in `levels` order;
`graphcmp.py:2821` prints a list built by in-order `append`; `differ.py:431,531` print the ordered
list `moved`.

**The instrument is not silent — it fires on the actual offender:**

```
$ .venv/bin/python .agents/slop/reprofix/plant.py
  PASS  BEFORE the sort (the offending shape) FLAGS        observed: ['via name same']
  PASS  AFTER  the sort (the fix) is QUIET                  observed: []
  PASS  the REAL pre-fix oracle FLAGS                       observed: ['via name same', ...]
PLANT: GREEN (3/3)
```

Note the honest limit: a flow-insensitive, scope-blind screen **cannot** prove absence — it missed
`same` until names bound from an order-bearing expression were tracked, and it still over-flags. So
"0 live" is a measurement over 119 write sites, not a proof over all reachable states.

## 6. `PINS`, AND WHETHER THIS MOVES ONE

* `PINS` contains **`"census-rc": "rc=0"`** (`checks/differ.py:232`) and **no `repro` pin** — the
  repro lane is the `cmd_repro` byte-compare itself, not a summary row.
* This unit makes **no edit**, so it moves **no** pin. `census-rc` is the oracle's exit status; the
  sort does not touch it (live summary reads `census-rc=rc=0`, matching the pin). No verdict pin was
  touched — per the brief, the orchestrator drops those separately.

## 7. WHY NO EDIT — a seed is still a needed BACKSTOP (and the pin is already in place)

The task says *do not pin `PYTHONHASHSEED` if a sort removes the dependence*. The sort DOES remove
**this** dependence (proven in §4). But the tree pins the seed already (`checks/differ.py:47`,
`ENV = {…, "PYTHONHASHSEED": "0", …}`) and records it as a precondition row
(`precondition_rows()` at `:688-690` → `pythonhashseed=0` in `D0-run-summary.txt`), declared in
`checks/env-precond.py`. The tree's considered position is **both**: the code comment at
`checks/differ.py:626-631` and `.agents/slop/preconds/FINDINGS.md` §3 argue the pin is *necessary
and not sufficient*.

* What a sort could **not** fix: a site **nobody has found**. The census in §5 is a measurement over
  119 write sites, not a proof; a value that is a `set` returned by a function is invisible to a
  flow-insensitive screen. The seed is the only backstop for an un-audited site on this interpreter.
* Removing the pin is **not** a one-line change and was **not** done: it would force
  `ROW_VALUES`/`precondition_rows` and `checks/env-precond.py` (another unit's instrument) to move
  in the same commit, or `unhealthy()` would refuse the run.

If the orchestrator wants the seed scrubbed, the sort must be shown to cover the **whole** census
(needs `bend`, not available to this unit) and the precondition machinery must move with it.

## 8. ADJACENT OBSERVATION (not this unit's file)

`checks/env-precond.py --check` **exits 1** today: METHOD A reports
`checks/differ.py:509 lacks PYTHONHASHSEED,NOOPT` and `.agents/slop/graphcmp.py:1800 lacks
PYTHONHASHSEED,NOOPT`. The differ row is LINE DRIFT — the comment env-precond expects at `:509`
now sits at `:511`; the `graphcmp.py:1800` `clean_env` really does omit both, relying on
inheritance from `differ.py`'s `ENV`. Reported, not edited.
