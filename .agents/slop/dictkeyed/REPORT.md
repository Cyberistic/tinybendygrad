# THE DICT-KEYED READER BLIND SPOT CLASS — how many git readers can represent a duplicate path entry at all

**MEASURED 2026-10-17T05:11Z – 05:18Z · HEAD at start `c0795853ae9bc75b4442db43eb6cf035ddddf4a6` ·
HEAD at end `030a34fe19fddb9a1e166294460ef92836621ee2` · the tree is a MOVING TARGET and both readings are named below.**

Subject commit `591f6b499` is immutable, so every subject number in this report is stable regardless of HEAD.

---

## 0. THE HEADLINE

**A committed instrument asserts that the duplicate is impossible, and the malformed commit falsifies it.**

`checks/runs-artifacts.py:338`:

```python
for t in dict.fromkeys(paths):  # A SET OF LANES. `git ls-tree` cannot repeat a path, and
```

and `checks/runs-artifacts.py:1058-1061`:

> `# L -- THE POPULATION IS A SET OF LANES, NOT A LIST OF OCCURRENCES. `git ls-tree` cannot`
> `#     repeat a path, so this is defensive -- and it is ASSERTED rather than assumed,`

The dedup is asserted — but against a **hand-built list**, `:1062-1063`:

```python
once = len(shell_lanes(r, tracked=[lanes["a.sh"]]))
twice = len(shell_lanes(r, tracked=[lanes["a.sh"]] * 3))
```

So the instrument tests its own dedup and never tests its premise. **`git ls-tree -r 591f6b499` emits
126 paths three times each.** The premise is false, the assertion is against a synthetic list, and the
malformed commit is the counterexample sitting in this repository's own history.

---

## 1. THE POPULATION AND ITS DENOMINATORS

Per doctrine 1, the population is a **directory walk plus an AST pass**, never a hand list. A mention of
`git ls-tree` in a comment cannot enter the population: only a string constant that survives `ast.parse`
can. The classifier requires the verb and `git` in the **same** string constant — without that
conjunction `diff` matches `difflib.unified_diff`, which is a classifier error of exactly the kind
doctrine 1 exists to catch (`.agents/slop/dictkeyed/discover.py`, vocabularies recorded at `:16-31`).

| step | count | instrument |
|---|---|---|
| roots walked | `checks/`, `gates/`, **`bin/` ABSENT (0 files)** | `discover.py:11` |
| `.py` walked by `ast.parse` | **280** (checks 82, gates 198) | `discover.py` |
| `.sh` walked but **NOT** AST-classified | **19** | `discover.py` |
| `.py` naming a git verb as a string constant | **113** of 280 | `discover.rows` |
| … naming an **ENUMERATOR** (`ls-tree`/`ls-files`/`status`/`diff`/`for-each-ref`/`show-ref`) | **42** of 113 | `p42.rows` |
| … of those, uncommitted | **0** of 42 (all committed, `git ls-files -s`) | verified |
| … importing `.agents/slop/` by AST module name | **0** of 42 | verified |
| **path-production FUNCTIONS** (a git enumeration turned into paths) | **31**, across **25** of the 42 | `funcs.py` → `funcs.out` |
| hand-verified against source | **31 of 31** | see §3 |

**The `.agents/slop/` clause in the brief, answered.** No member of the 42 loads a census from
`.agents/slop/` by AST name, and the one committed instrument that loads one **by path**,
`checks/corpus-figure.py:135` → `.agents/slop/graphcmp.py`, is **not a git reader**: 3 252 lines,
committed (blob `b12dcb55`), and its 5 `git` occurrences are all prose (`significant`, a `rev-list`
in a comment, "git history"). A second such path, `.agents/slop/quiesce/snapshot.py` (named by
`checks/substrate-id.py` and two slop tools), is **ABSENT** — outside this census's subject, recorded
so the next unit does not re-measure it.

**Admitted limits of this discovery, stated rather than absorbed.**

1. **19 `.sh` files were not AST-classified.** One shell reader exists: `checks/disarm.sh:26`, which
   pipes `git diff --cached --name-only; git status --porcelain` through `sort | uniq` — and because
   `sort` makes copies adjacent, **`uniq` collapses them**. It is classified anyway, from source.
2. **A reader that assembles argv from variables is invisible to this classifier.** No member of the 42
   is known to be one, and I did not prove that none is.
3. `funcs.py` detects two shapes only (TAB-partition, and `splitlines`/`split`). A reader that gets
   paths out of git by a third shape would be missed.

---

## 2. THE MEASUREMENT — THE DICT-DROP ON THE MALFORMED COMMIT

Reproduced **read-only**, by copying `checks/index-arm-gate.py:114-119` verbatim in shape — same
`partition("\t")`, same `meta.split()`, same `len(fields) >= 3` guard — so the number below is the
gate's own arithmetic and not a paraphrase of it. `.agents/slop/dictkeyed/dictdrop.py`, re-derivable
with `isolate.py`.

`591f6b499` is malformed in its **root tree object** `d83cf685f89af04f607a49a3c6d2c8ef0c1eec65`, which
`git cat-file -p` shows naming `gates` **three times with the identical OID `5dee0c1b`**. No custom
git hook is installed (`.git/hooks/` holds only samples). The duplicate is in the object database, so
no index reset, no checkout and no commit can remove it.

```
shape        rev         git emitted  reader reports      delta  verdict
------------------------------------------------------------------------------
OVERWRITE    591f6b499          7505            7253     -252  COLLAPSED
SET          591f6b499          7505            7253     -252  COLLAPSED
LIST         591f6b499          7505            7505       +0  both copies survive
ACCUMULATE   591f6b499          7505            7505       +0  INFLATED (a number, not a shape)
------------------------------------------------------------------------------
OVERWRITE    HEAD              7501            7501       +0  clean
SET          HEAD              7501            7501       +0  clean
LIST         HEAD              7501            7501       +0  clean
```

Self-contained decomposition of the subject, with **no second commit anywhere in the measurement**:

```
lines git emitted ............... 7505
distinct (dir,path) pairs ....... 7253
arithmetic check: 7127x1 + 126x3 = 7505  OK
entries lost by a dict ......... 252
per-path OID test ............... 126 REPEATED (same blob), 0 CONFLICTING (two OIDs)
```

With `-t` the figures are 8 572 emitted / 8 318 distinct / **254** lost, 127 repeated paths. So the
background unit's two readings are both right and they differ by the flag: `-r` collapses **252**,
`-r -t` collapses **254**.

**All 126 are REPEATED — same blob, three times. Zero are CONFLICTING.** The `gates` subtree object
`5dee0c1b` holds 126 blob entries with 126 distinct names; it is the **tree entry** that is triplicated,
not its contents. This matters for the arm in §5: the cheap case is a redundant copy, and the
expensive case — two OIDs for one path, where `git fsck` semantics bite — has **not** been observed in
this repository and must not be assumed absent.

### Two wrong numbers I produced and corrected, because both were clean

1. I compared 591f6b499 against HEAD to locate the lost entries and reported
   `gates 378 vs 277, delta +101`. **That delta is not the duplicate.** 591f6b499's `gates` tree holds
   126 entries and HEAD's `gates/` holds 279 — the subtree has *grown*. A cross-commit diff cannot
   separate "enumerated twice" from "newer". Fixed by comparing the commit **against itself**:
   `gates` emits **378** where the deduplicated truth is **126**, **delta +252**, which matches the
   dict drop exactly.
2. My first isolate script reported `distinct OIDs among repeats = 126 → CONFLICTING`. It flattened
   every repeated OID into one set, answering "how many blobs are involved" (one per path, so always
   126) instead of "does ONE path carry two blobs". The per-path test is the one that answers it.

---

## 3. THE CONTROL — IT PASSES

**Required: the collapse appears on `591f6b499` and NOT on a known-good commit. It does not.**

| rev | emitted | distinct | dict drop | repeated | per-dir inflation |
|---|---|---|---|---|---|
| `591f6b499` (subject) | 7505 | 7253 | **252** | 126 ×3 | `gates` +252 |
| `HEAD` @ `c0795853` | 7501 | 7501 | **0** | 0 | none |
| `HEAD` @ `030a34fe` | 7501 | 7501 | **0** | 0 | none |
| `HEAD~1` | 7501 | 7501 | **0** | 0 | — |
| `ad117c928` | 2446 | 2446 | **0** | 0 | — |

HEAD moved **during** this session, so the control was re-taken at the new HEAD rather than trusted once.
The two HEADs differ by exactly **1** path (`gates/gatekit.py`, modified — not added or deleted), which
is why both read 7 501: the control is stable and its stability is explained, not assumed.

**The control is not a formality.** A dict-drop reproduction that collapsed on every commit would "prove"
nothing, and the per-directory inflation table is the control's second half: it reports "none" on a good
commit rather than a number that happens to be small.

---

## 4. THE CLASSIFICATION, AND WHICH DICT-KEYED READERS GO GREEN

Full table with evidence: **`.agents/slop/dictkeyed/sites.rows`** — 46 sites, 5 columns.

The binary question "is it a dict" is **the wrong question**, and measuring it that way would have
produced a false result. `gates/gendirs.py:496` is `out[d] = out.get(d, 0) + 1` — a dict keyed by
`os.path.dirname(path)` whose value is a **count**. A second occurrence **moves the count**. It cannot
name the path, but it is not the silent collapse an overwrite is. The classes that matter are:

| class | sites | what a duplicate does |
|---|---|---|
| **DICT-OVERWRITE** `d[path]=v` | **4** | second write **destroys** the first. Silent. |
| **DICT-ACCUMULATE** `d[k]=d.get(k,0)+1` | **1** | moves a **count**, never an identity |
| **SET / SET-COMPREHENSION** | **11** | deduplicated at insert. Silent. |
| **SCALAR-COUNTER** `n+=1` | **1** | moves a number, names nothing |
| **SHELL** `sort \| uniq` | **2** | `sort` makes copies adjacent, `uniq` collapses |
| DICT-OF-LIST `setdefault(k,[]).append` | 1 | **both copies survive** |
| LIST (incl. sorted comprehensions) | **11** | **both copies survive** |
| NOT-PATH-KEYED | 12 | keyed by a name, a verdict, a class label, a module |

**The 4 DICT-OVERWRITE sites, and `index-arm-gate.py` in particular.**

`checks/index-arm-gate.py:109-120` is `ent[path] = fields[2]`. On `591f6b499` it returns **7 253** where
git emitted **7 505**. **It would report a clean tree**, and not only silently — *structurally*:

- its five shapes are `DELETION`, `INTENT`, `FOREIGN`, `STALE`, `EMPTIED` (`:142-146`), and **all five
  are index-vs-tree**. A duplicate is **internal to the tree**, so no index can witness it.
- `census()` never compares the tree to itself or to a line count. There is no `len(tree)` assertion
  anywhere in it.
- `git ls-tree -r 591f6b499` **exits 0**, so the `rc != 0 → RuntimeError` at `:113` cannot fire, and
  there is no `REFUSED` to report. `gates/gates-pop.py`'s own header warns about exactly this trap:
  *"`git ls-tree` WITHOUT `--name-only` … a naive split enumerates 6 296 identical-looking names"*.

The other three: `index_entries` (`:95-106`) and `not_intent_to_add` (`:149-163`) are the **index**
side, where a duplicate is a *multi-stage* entry — `ls-files --stage` emits one line per stage during a
merge conflict and the dict keeps the last. **UNMEASURED**: this index holds 8 194 entries, all stage
0, 0 multi-stage paths, so I have no live example and do not claim one.
`gates/docnum-census.py:169-179 pin_trees` is the same shape as `head_tree` **and its rev is an
arbitrary pin**, so it can be pointed at `591f6b499` by editing one string.

**`gates/gendirs.py` is the highest-leverage member, and it is loaded BY PATH.** `tracked_dirs()` is the
git half of the shared generated-directory population; `gates/gates-pop.py` and `gates/retention-check.py`
both load that same file the same way. Its per-directory inflation is real and measured (+252 on
`gates`) but it has **no baseline to compare against**, so it prints a number rather than a verdict.

**Would any of them go GREEN on a malformed tree? Measured: yes — every DICT-OVERWRITE and every SET
site, 15 of 15, and they go green for the structural reason above rather than by accident.**

**And nothing in the population would FLAG it.** I grepped all 42 for a duplicate-entry shape: every
hit is about census **row names** (`gates/crp_graph_census-gate.py:343`
`len(want) - len(set(want))`; `gates/state_census-gate.py:44` `len(set(emitted)) == len(emitted)`) or
docstring self-repair. **Zero instruments check a committed tree for a repeated path entry.** The
vocabulary and the arithmetic already exist in this tree — applied to rows. That is the whole gap.

---

## 5. THE PROPOSED ARM — NOT IMPLEMENTED

**A `DUPLICATE` shape, split `REPEATED` / `CONFLICTING`. Proposal only; nothing in this directory
implements it.**

```
DUPLICATE
  REPEATED     one path, N>1 entries, all OIDs equal      -- redundant copy, 126 of them on 591f6b499
  CONFLICTING  one path, N>1 entries, >1 distinct OID     -- TWO CLAIMS ABOUT WHAT A PATH IS
```

They must not share an arm. `REPEATED` is a hygiene finding; `CONFLICTING` is a **content** question,
because two OIDs mean git can resolve the path two ways and every consumer's answer becomes
commit-dependent. **Zero `CONFLICTING` instances have been observed here**, so an arm that reports only
one severity would be calibrated on one sample.

**Why the split is `set(oids)` and not a count.** The first version of my own isolate script flattened
the OIDs and got `CONFLICTING` wrong (§2). `len(oids) == 1` **per path** is the whole discriminator.

**Where it belongs.** As a **clause in the tree reader, not in the lane dedup**. `checks/runs-artifacts.py`
already spends a plant on deduping lanes and justifies it with a claim that is false; adding a second
dedup there would harden a wrong premise. The reader that already has the right authority is
`checks/index-arm-gate.py:109-120` — it is the file that says *"THE TREE. `git ls-tree -r <rev>`. Never
the index"* (`:110`) and it already owns the committed-tree population. A sixth shape there costs one
`Counter` and reuses the `n_tree` denominator it already prints. Second-best home, and the one with the
widest blast radius: `gates/gendirs.py`, because two other instruments load it by path.

**The population it must read: committed TREES, never the index.** The brief states this and the tree
confirms it — the index holds **8 194 entries, all stage 0, 0 multi-stage paths**, so it cannot exhibit
the shape at all, and a duplicate lives in a *tree object* that no index reset can reach. Concretely,
`git ls-tree -r <rev>` compared against `len(dict)`, plus `-t` for the tree entries themselves — and
`-t` is the only flag under which the root-level `gates` entry is visible at all.

**The precondition, in the tree's own vocabulary.** `591f6b499` is not on this branch, so an arm reading
only `HEAD` is green at rest and blind by construction. It needs the same treatment
`gates/indexread-gate.py:20-25` gives its baseline: a **growth** claim against a pinned baseline for the
**history** (`git rev-list` over the pushed range), with `--strict` for the stronger claim. Per
`AGENTS.md`, **a gate's input belongs beside the gate in git** — not in `gates/artifacts/`, which is
`.gitignore`d and is where gate runs write, so one `rm -rf` deletes it and git cannot restore it.

**What it must print.** `REPEATED`/`CONFLICTING` counts, the paths, the OIDs, and **the line count vs the
distinct count** (7 505 vs 7 253) — because a reader that can name the paths should also be able to say
how many entries it did not keep. **And the denominator**: zero repeated paths over N commits examined.
A count without that denominator is a claim.

---

## 6. WHAT I DID NOT DO

- **I did not run `checks/index-arm-gate.py`.** It writes: `:241 plant()` creates a scratch repo and runs
  `git add`/`git commit` at `:255-256`, reachable only via `--plant` (`:289`). The reproduction in
  `dictdrop.py` is the substitute, and it copies the gate's arithmetic rather than invoking the gate.
- **I changed nothing outside `.agents/slop/dictkeyed/`.** No git write, no `jj` mutation, no `bend`, no
  `gates/` run, no `differ.py`, no `pytest`/`mypy`/`ruff`. Every git command was `env -u GIT_INDEX_FILE`
  prefixed and read-only (`ls-tree`, `ls-files`, `cat-file`, `rev-parse`, `diff-tree`).
- **Two classifier bugs of my own were found and corrected, not shipped** (§2). A cleaner number than the
  truth was the more dangerous failure mode in this task, and both are recorded because the corrected
  arithmetic is what the reader is asked to trust.
