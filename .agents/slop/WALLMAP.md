# WALLMAP — a ranked, classified census of every refusal recorded in the port

**Scope measured against a FROZEN tree**, because seven units were live while this
was written and one of them was editing `tinybendygrad/uop/ops.bend` — the root of
the import closure — underneath the first pass of this census.

```
frozen at            2026-10-04T13:00:35Z
tracked .bend files  134          (manifest.sha256, all 134 verified on extract)
files carrying markers 82
markers              1,028        (checks/census.tsv, 1,028 rows + header)
drift during census  3 of 134 files moved (mixin/gradient.bend, uop/ops.bend, uop/render.bend)
                      the TOTAL stayed 1,028 throughout; the claim-line count went 817 -> 816
```

Reproduce the denominator exactly:

```bash
rg -a -o --no-heading -N 'TODO\((p[0-9]|pN|delete)\)' tinybendygrad/ | wc -l   # 1028
rg -a --no-heading -c '^\s*#\s*TODO\(' tinybendygrad/ | awk -F: '{s+=$2} END{print s}'  # 816
```

Every table below is stated against the **frozen** tree (817 claim lines). The live tree at
the time of writing reads 816. **The total is the stable number; the split is not, because
three live units are editing it.** That instability is itself the argument for ranking by
`n_targets` (a property of the *upstream* tree, which is pinned at `6c3d401cf324`) rather than
by marker count (a property of a moving working copy).

**`-a` is not optional.** `tinybendygrad/runtime/ops_dsp.bend` trips ripgrep's binary
heuristic and `rg` prints `WARNING: stopped searching binary file after match`,
silently truncating that file. Without `-a` the count is 1,026, not 1,028.

**One file is tracked but must not be counted.** `tinybendygrad/runtime/ops_bend.mut.bend`
carries 2 markers, is dated Oct 2 22:20, is ignored by `.gitignore:36` (`*mut.bend`)
and is tracked only because it predates the ignore rule. It is a mutation
harness's scratch copy of `ops_bend.bend`. Counted here: **no**. Including it gives
1,030 in 83 files.

---

## 1. THE CENSUS

| | n | /1,028 |
|---|---|---|
| tracked markers, all `.bend` | 1,030 | |
| − `ops_bend.mut.bend` (harness artefact, gitignored) | −2 | |
| **markers in the tree (the denominator)** | **1,028** | 100% |
| of which the comment line **begins** with the tag (a *claim*) | 817 | 79.5% |
| of which the tag appears **mid-line** (a *cross-reference*) | 211 | 20.5% |

Tags: `TODO(p3)` 1,023 · `TODO(p1)` 1 · `TODO(p4)` 1 · `TODO(p6)` 1 · `TODO(pN)` 1 ·
`TODO(delete)` 1.

The 817/211 split reconciles against the tag table as:
`813` p3 claim lines `+ 4` non-p3 claim lines (`p1`,`p4`,`p6`,`delete`) = **817 claims**;
`210` p3 mid-line references `+ 1` `TODO(pN)` reference = **211 references**. `813+210 = 1023`.

### 1a. 20% of the p3 count is not claims

Of the 1,023 `TODO(p3)` occurrences, **210 are a quote of a marker, not a marker.**
They sit mid-sentence:

```
codegen/kernel.bend:213   # `# TODO(p3) __init__.py:246  x.dtype != u.dtype` -- the guard, and the `cast` it
uop/fold.bend:6214        # TODO(p3) ops.py:801  def storage_base         -- `base` with UNSHARD, BITCAST and
```

and **107 of the 210 cite an upstream address that no claim line carries anywhere.**
`codegen/kernel.bend` records `__init__.py:246`, `__init__.py:411`, `__init__.py:509`
only inside quoted prose. `rg '^# TODO(p3)'` cannot see them; neither can
`.agents/slop/marker-audit.py`. They are real claims with no marker.

**This is the failure the brief predicted, and three instruments have now hit it
from three directions.** `marker-audit.py` read a fixed 14-line window and
over-counted (its own docstring: "reported 162 unexplained markers", real 76).
`grw-census.py` reads to the *next marker* and under-counts the other way. My own
first pass read only the marker line and produced "820 of 1,028 name no blocker",
which reading 22 of them proved was my tool's bug, not a finding. **Three
continuation rules, three different numbers, no shared definition.**

---

## 2. THE CLASSIFICATION — the deliverable

### A census of the live tree **cannot see closure.** That is structural.

An `ALREADY-CLOSED` marker is, by definition, absent from the tree. So the verdict
ladder splits across **two populations**, and conflating them is how the project ends
up quoting a count that cannot move.

### POPULATION A — the 1,028 markers in the tree

| verdict | n | /1,028 | /817 claims |
|---|---|---|---|
| **STILL-A-WALL** — the claim holds today | **799** | 77.7% | 97.8% |
| **PROSE-REFERENCE** — the tag is mid-line; not a claim at all | 211 | 20.5% | — |
| **UNVERIFIABLE** — and why | 17 | 1.7% | 2.1% |
| **NEVER-WAS-A-WALL** — the claim was wrong when written | 1 | 0.1% | 0.1% |
| **ALREADY-CLOSED** | 0 | — | 0% *(structurally impossible; see Population B)* |
| **SUPERSEDED** | 0 | 0% | 0% |

### How much of the 799 is actually verified

The 813 `TODO(p3)` claim lines, by whether the upstream subject is declared as a
Bend `def` **anywhere in the port tree**:

| | n | /813 | what it means |
|---|---|---|---|
| subject declared **nowhere** | **642** | **79.0%** | **the claim is TRUE as written** — a check that can fail, and it did |
| subject declared in the marker's **own** file | 60 | 7.4% | the container landed; the marker is about a residual arm. Read by hand |
| subject declared in a **different** file only | 72 | 8.9% | **a name is not a binding.** Needs import-closure resolution by hand |
| no upstream subject (module-level statement, or prose) | 39 | 4.8% | address-only markers |

So **642 of the 813 claims are verified true by a check that can fail**, and **132
are not verified by this census and are not claimed to be.** The project has four
measured instances of a name not being a binding; the 72 in the third row are
exactly that population, and they are where the next unit should look.

The 17 `UNVERIFIABLE`, each with its reason: 14 name no upstream `file:line` in the
marker's own text at all (`# TODO(p3) mixin/op.py  x.conv2d` — a path, no line);
3 cite a bare `__init__.py`/`dtype.py` that resolves to 2–10 upstream files and
needs a content probe the marker does not contain.

The 1 `NEVER-WAS-A-WALL`, verbatim, declaring its own closure:

```
tinybendygrad/renderer/__init__.bend:415
  # TODO(p3) __init__.py:11  with_storage     (done; kept for the line map)
```

**The brief expected `ALREADY-CLOSED` and `NEVER-WAS-A-WALL` to be substantial, and I am
not softening them: I report 5 and 1.** `ALREADY-CLOSED` is **0** in population A and
**5** in population B; `NEVER-WAS-A-WALL` is **1** and it declares itself in its own
text. I am reporting the numbers I measured, and the reason they are low is a property
of the artefact, not a defence of the port:

- `ALREADY-CLOSED` cannot appear in a census of the current tree at all. It is not
  under-counted, it is *unobservable* without a dated copy. Five exist and I found them;
  there may be more in `runs/margsym/snap`, which I did not diff.
- A marker that was *wrong when written* leaves no trace that distinguishes it from one
  that was right, **unless the def has since been ported** — and then it shows up as
  `ALREADY-CLOSED`, not `NEVER-WAS-A-WALL`. So `NEVER-WAS-A-WALL` is only detectable for
  the 1 marker that says so out loud. **The real NEVER-WAS-A-WALL population is the
  unidentifiable remainder of the 799**, and this census does not claim a number for it.

The project's own measurement agrees and is stronger than mine: `TODO.md:969` records
"~20 of 48 closed markers turned out to be *stale*". The stale ones were **removed**; the
ones still sitting in the tree were never identified. **The population that needs
auditing is the 799, and it has never been audited.**

### POPULATION B — the 79 claim lines deleted between 05:18Z and 13:00Z

Found only by diffing `runs/gr-init/base` (a full copy of the port, mtime Oct 4
05:18) against the frozen tree.

| verdict | n | evidence |
|---|---|---|
| **ALREADY-CLOSED** | **5** | def now declared in its own port file + the marker text removed by a named commit |
| ALREADY-CLOSED-by-name-only → **not credited**, reported `UNVERIFIABLE` | 10 | the name exists in a *different* file; the project has four measured instances of a name not being a binding |
| **SUPERSEDED** (duplicate collapsed) | 16 | the same label is still claimed by a live marker elsewhere |
| **SUPERSEDED** (moved to another file/address) | 18 | e.g. `get_idx`, `vmin`, `vmax`, `_min_max`, `_ranges` moved `ops.bend` ↔ `fold.bend` |
| **VOID-DELETED** — marker gone, no def landed, no surviving claim at that address | 48 | the finding below |

The 5, with commits (`git log -S'<marker text>'` on the file, not a name search):

| def | port file | commit |
|---|---|---|
| `ProgramInfo.vals` | `uop/ops.bend:7591` | **`ae8d290ea`** *"land ProgramInfo.vals"* |
| `print_uops` | `uop/render.bend:2754` | **`77a598240`** *"print_uops is THREE-FIELDS-CORRECT and two short, and the first 'wall' was my fixture"*; gated at `64493ca32` |
| `pm_rewrite` | `uop/ops.bend:3639` | `7fe55a593` *(a renumber commit; the def is present, the message does not name it)* |
| `resolve_returned_after` | `uop/ops.bend:7252` | `7fe55a593` *(ditto)* |
| `marg` | `uop/fold.bend:1375` | `21286a571` *(the def is present; the message does not name it)* |

Two of the five have a commit that names the landing. **Those two are the only
`ALREADY-CLOSED` in this census that meet the standard.**

### THE 48 VOID-DELETED — and why that is the real news

48 markers were deleted in the 7h40m window with **no def landing and no surviving
claim at their upstream address**. 43 of them name `ops.py`; 5 name `render.py`.

**21 of the 48 sit in `ops.py:1526–1777`** — `_broadcasted`, `__floordiv__`,
`__rfloordiv__`, `mod`, `match`, `deconstruct_function`, `universal_match` ×2,
`upat_deferred_compile`, `lazy_compile`, `__add__`, `rewrite` ×2,
`save_to_diskcache`, `add_trace_group`, `rewrite_group`, `_decorator`,
`__wrapper`, `print_match_stats`, `launch_viz`, `cached_bpm_rewrite`.

`.agents/TODO.md:944` says of exactly this band:

> **57 of these are the `UPat` COMPILER (`ops.py:1545`–`1790`), whose wall is stated
> once and applies to all of them.**

**Checked, and it is no longer true.** In the frozen tree:
- `rg 'TODO\(p3\)\s+ops\.py:1[5-7][0-9][0-9]' tinybendygrad/uop/ops.bend` → **0**
- `rg '1545|1790' tinybendygrad/uop/*.bend` → **0**
- no file in the tree states a shared wall for that band.

So 21 claims were removed against a stated shared wall that is no longer stated
anywhere. **A marker whose wall lives in a comment that has since been deleted is
not a closed marker; it is a silent gap.** This is the same shape as the
`graph_rewrite` header at `schedule/__init__.bend:7-13`, which `grw-stage4.md`
already found "argues for rank 3 and names rank 2" while rank 1 is bigger.

The other 27 void-deleted claims are scattered single defs — `is_inline_call`,
`has_unbound_outputs`, `unbound_outputs`, `vconst_like`, `ccast`, `range`, `_rop`,
`get_valid`, `copy_to_device`, `_mop`, `getaddr`, `device_range_src`,
`is_variable`, `is_bound_var`, `expr`, `unbound`, `unbind`, `unbind_all`, `set`,
`marg_str`, `render_marg`, and others.

---

## 3. WHAT EACH SURVIVING WALL BLOCKS, RANKED

`grw-stage4.md` set the discipline: *of 22 walls naming the `graph_rewrite`
dispatcher, 10 were for other walls and its removal unblocked none of them.* So
n_lines is **not** blast radius. For each root wall:

- **n_lines** — claim lines whose own block names it
- **n_targets** — distinct upstream symbols those lines name, **the blast radius**

| rank | wall | n_lines | n_files | **n_targets** | lines/target | actionable by this project? |
|---|---|---|---|---|---|---|
| 1 | **no `math.*`** — the transcendentals and float helpers | 31 | 12 | **35** | 0.9 | **yes** — write the defs |
| 2 | **no function values** — a rule body cannot take a `Callable` | 16 | 11 | **21** | 0.8 | **no** — language |
| 3 | **a def cannot raise** | 16 | 12 | **20** | 0.8 | **no** — language |
| 4 | **symbolic substitution** — needs the matcher machinery | 16 | 8 | **19** | 0.8 | yes, and it is Phase P3 |
| 5 | **no regex, no 64-bit float repr** | 18 | 12 | **18** | 1.0 | partly |
| 6 | **no process/IO seam in a pure def** (`stdin`/`stdout`/`os.environ`/`atexit`/`subprocess`) | 16 | 9 | **16** | 1.0 | **no** — language |
| 7 | **no set algebra, no mutable dict as a value** | 7 | 3 | **15** | 0.5 | **no** — language |
| 8 | **the `UPat` pattern COMPILER** (`ops.py:1545–1790`) | 9 | 6 | **14** | 0.6 | yes |
| 9 | **the rewrite dispatcher** (`graph_rewrite`/`walk_rewrite`) | 6 | 6 | **10** | 0.6 | already landed; see note |
| 10 | **the autogen Python modules have no Bend import surface** | 10 | 5 | **10** | 1.0 | **no** — needs codegen |
| 11 | **a process-wide mutable singleton** | 4 | 3 | **7** | 0.6 | **no** — language |
| 12 | **no sha256 / rotate / popcount** | 6 | 6 | **7** | 0.9 | partly |
| 13 | **the rewrite `ctx` must be a mutable accumulator** | 3 | 3 | **4** | 0.8 | needs a signature change in another unit |
| 14 | **Bend has no loop** (a walk is a fuel countdown) | 3 | 3 | **4** | 0.8 | **no** — language |

**The lines/target column is the load-bearing one.** Every root wall sits between
**0.5 and 1.1 claim lines per distinct target**. Unlike `graph_rewrite` (22 lines
for 12 real targets under the unbounded window), **there is no "one sentence, many
markers" collapse in the p3 population at all.** The markers are one-claim-per-target.
So `n_targets` *is* the blast radius, and it can be ranked directly.

### What that ranking says

**The tree is not blocked by the rewrite engine. It is blocked by the absence of a
maths library and by four Bend language features.**

Of the 14 root walls, **6 are Bend-language walls** (rows 2, 3, 6, 7, 11, 14) and
**close to zero work on this project can move them.** They account for
20+21+16+15+7+4 = **83 claim lines' worth of targets** — roughly a quarter of the
tree — and they are not on anyone's critical path because they cannot be. A plan
that counts them as backlog is wrong by about 83.

**Rank 1 is the finding.** 31 claim lines across 12 files, 35 distinct targets, all
waiting on the same absent thing: `math.*`. `mixin/elementwise.bend` alone carries
**45 p3 claim lines** and the bulk are `-- 1/math.log(2)`, `-- math.pi/2, asin`,
`-- exp()`. That is **one library, ~35 defs, and it is the single largest
actionable concentration in the port.**

**Rank 8 is the one to distrust.** `grw-stage4.md` ranks the `UPat` compiler
"#1, bigger than the header's own rank-3, and not in the header at all" — and it is
right about the header, but the `UPat` band's 21 markers were **deleted this
morning** and the shared wall that was supposed to cover them **no longer exists
anywhere in the tree**. Ranking it without restoring the wall ranks a phantom.

**Row 9 is already done and its removal is recorded.** `grw-stage4.md` measures the
dispatcher unblocking **12 of 22** ctx walls and **none of the other 10**. My count
under the own-block rule is **6 claim lines, 10 targets** — the same 22 is
`grw-census.py`'s number and it comes from reading to the *next marker*, so it
inherits the shared wall. Neither number is 22 real markers.

### The 22/14 vs 6 discrepancy, stated

The coordinator's "named walls: 22 across 14 files" is `grw-census.py`'s
`marker_blocks`, which reads the continuation **to the next marker** — an unbounded
window. Under the own-block rule it is **6 across 6 files**. `grw-census.py` also
reports "TODO(p3) markers in the tree: 880"; the tree has **1,023** occurrences and
**817** claim lines. Its `is_marker` accepts lines where the tag is mid-line but not
backticked, which is neither the strict rule (817) nor the loose one (1,023).
**Three numbers for one quantity, none of them printed with the rule that made it.**

---

## 4. THE TAG NAMESPACES — measured, and the answer is *undefined*

There are **five** tag namespaces. They are **three different kinds of thing**, and
**none is defined at the point of use.**

The p-scale is defined — as **phases of the port plan**, in `.agents/TODO.md`
lines 917–928 and nowhere else:

| phase | directory |
|---|---|
| P1 | "the contract" (`TODO.md:246`) |
| P2 | "trial run" (`TODO.md:292`) |
| P3 | `uop/` |
| P4 | `schedule/` `engine/` |
| P5 | `codegen/` `renderer/` |
| P6 | `runtime/` |
| P7 | `tensor` `mixin/` `nn/` |
| P8 | `llm/` `viz/` `function.py` `device.py` |

`.agents/slop/brief-port.md:177` gives the syntax. `tinybendygrad/engine/jit.bend:1091`
gives the only gloss of the meaning in the tree:

> A `# TODO(p3)` in the tree means "a phase owns this", not "nobody knows".

**That gloss is false, and it is falsifiable.** Cross-tabulating every marker's tag
against the phase table's directory assignment:

| phase dir | p1 | p3 | p4 | p6 | pN | delete | total |
|---|---|---|---|---|---|---|---|
| P3 `uop/` | | 214 | | | | | 214 |
| P4 `schedule/` `engine/` | | 117 | | | | | 117 |
| P5 `codegen/` `renderer/` | | 104 | | | | | 104 |
| P6 `runtime/` | 1 | **321** | | | | | 322 |
| P7 `tensor` `mixin/` `nn/` | | 235 | | | 1 | 1 | 237 |
| P8 `llm/` `viz/` `function.py` `device.py` | | 26 | | | | | 26 |
| unassigned (`helpers.bend`) | | 6 | 1 | 1 | | | 8 |

**Only 214 of 1,023 `TODO(p3)` markers (20.9%) are in P3's directory. 809 (79.1%)
are not.** So:

- **`p3` is not a phase. It is a default.** 1,023 of 1,028 markers (99.5%) carry it,
  in every directory. A default that is on 99.5% of items orders nothing, which is
  the answer to "why do 1,026 markers have no order".
- **`p1`** — one marker, `runtime/ops_metal.bend:277`. It means *"this whole file is
  a port of a superseded `ops_metal.py`"*. That is a **severity**, not a phase, and
  it is the only whole-file marker in the tree.
- **`p4`** — one marker, `helpers.bend:2327`: *"`time_sum_s` needs the engine's
  clock, which is a C effect."* P4's directory is `schedule/ engine/`; `helpers.bend`
  is in none. `uop/ops.bend:2894` says *"It is a P4 concern"* about a rewrite-rule
  visitor. **Two markers, two unrelated meanings, neither in P4's directory.**
- **`p6`** — one marker, `helpers.bend:430`: a `ContextVar._cache` KeyError.
  `uop/fold.bend:6140` says *"P3/P6"* about `sym_infer`. P6's directory is
  `runtime/`; `helpers.bend` is in none. **`p6` names two different things.**
- **`pN`** — one marker, `mixin/rand.bend:32`, which says in its own words:
  *"only W6 is a device-state wall. Each `TODO(pN)` below is the tracker."*
  **`pN` is an unnumbered placeholder, self-declared.**
- **`delete`** — one marker, `mixin/rand.bend:230`: *"delete both when `mxw_stk`
  grows `tn_shape_arg`'s one-element arm."* A **disposition**, not a priority. It
  is the only tag that says what to *do* rather than who owns it.

**There is no p2 and no p5 marker anywhere in the tree**, though both phases exist
and P5 owns 30 files. `p2` is absent because P2 was a trial run; `p5` is absent
because `codegen/` and `renderer/` use `p3` — the default — 104 times.

**An undefined priority scale is why 1,026 markers have no order.** Concretely: to
sort this tree you must first decide what `p3` means, and the only definition in
existence is 617 KB away in a different file and is **falsified by the tree's own
layout**.

---

## 5. WHAT I WOULD TELL THE OWNER TO PLAN AGAINST

> ### **~790**
>
> Live claim lines that are real claims. That is `1,028` markers minus `211` that are
> cross-references rather than claims, minus `17` that name no address, minus `1`
> that declares itself done.
>
> Of those ~790: **~83 are blocked on six Bend language features** and no work on
> this project moves them; **~35 are blocked on one absent `math.*` library** and are
> the largest actionable concentration in the tree; the remainder is Phase work
> spread thin at 0.5–1.1 markers per distinct target.
>
> **Plan against ~790 claim lines, ~700 of which are actionable, and a single
> `math.*` library that is worth more than any other unit of work on the board.**
>
> Two corrections to numbers currently in circulation: the marker count is **1,028,
> not 1,026** (`rg` needs `-a`; `ops_dsp.bend` trips the binary heuristic), and the
> graph_rewrite blast radius is **6 claim lines / 10 targets, not 22 / 14 files**.

**And one number that is not a count and should not be planned against at all:**
the 48 claims deleted this morning against a shared wall that no longer exists.
Nothing in the tree will ever report those again.

---

## 6. WHAT THIS CENSUS COULD NOT DO, AND WHY

- **The 799 `STILL-A-WALL` verdicts are a lower bound on truth, not a measurement of
  it.** "The upstream subject is not declared as a Bend def" is a check that can
  fail, and it did — it produced the `ALREADY-CLOSED` set. But for the **132**
  markers whose subject *is* declared somewhere (60 own-file, 72 elsewhere), that is
  a **name**, and the project has four measured instances of a name not being a
  binding. Every one of those 132 needs its import closure resolved by hand.
  **This census does not claim them.**
- **The `n_targets` ranking rests on keyword patterns in prose.** Each pattern was
  read against a sample and one was rejected for being a false-positive generator
  (`NN-BODY-CALLS` matched the token `elementwise` in `mixin/elementwise.bend`'s own
  markers and reported 68 where the truth is 31 for `MATH-LIB`). A rejected pattern
  that survived would have been a false finding, so the rejected one is recorded.
- **`ALREADY-CLOSED` needed a baseline that exists by accident.**
  `runs/gr-init/base` is a full copy of the port taken at Oct 4 05:18. Without it,
  closure is unobservable. It is a `runs/` directory, not a recorded artifact.
- **Three of 134 files moved during the census.** Every number here is against the
  frozen tree and the manifest. Against the live tree at the time of writing,
  `uop/ops.bend`, `uop/render.bend` and `mixin/gradient.bend` differ.

## 7. THE TOOLS, AND THE THREE INSTRUMENTS THAT DISAGREE

`checks/census.tsv` — all 1,028 markers, `W-1`…`W-1028`, with tag, claim-vs-reference,
verdict, label, resolved upstream path, reason. `wallmap/verdicts.json`,
`wallmap/closed.json`, `wallmap/rank.json`, `wallmap/manifest.sha256`,
`wallmap/tree.tar` (the frozen tree, 11 MB, hash-verified on extract).

Three instruments count "markers" in this tree and none of them agrees with
another, because each picked a different side of the same trade-off:

| instrument | rule | count |
|---|---|---|
| `rg -o 'TODO\(p3\)'` | the string, anywhere | **1,023** |
| this census | the comment line **begins** with the tag | **817** |
| `grw-census.py` | in a comment, tag **not** inside backticks | **880** |
| `marker-audit.py` | `^\s*#\s*TODO\(p3\)`, continuation to next marker | 815 *(at 05:18)* |

**A marker count in this project is meaningless without the rule that made it, and
three separate units have now shipped three rules.** That is the single most
reusable thing in this document: put the counting rule in the same sentence as the
count, or the count will be quoted forever, which is what happened to every number
in the brief.
