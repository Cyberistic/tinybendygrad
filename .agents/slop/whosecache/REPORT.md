# whosecache — WHICH CACHE IS AUTHORITATIVE, AND WHAT A STALE ONE SHOULD DO

Unit `whosecache`. All numbers MEASURED 2026-10-10 in this tree at `HEAD a8903ba0d`.
Nothing committed, nothing staged (`git diff --cached --name-only | wc -l` = 0, verified
against `git ls-tree -r HEAD`, not `git ls-files`).

Scope touched: `.agents/slop/graphcmp.py`, `checks/census.py`, `.agents/slop/whosecache/`.
`checks/rows/` not modified — see §1 for why nothing there needed to be.

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG FIRST, WITH THE BEFORE-VALUES

Ten, and the first one invalidates a whole table I was about to report.

**0.1 — the big one, and it is a corpus-wide number.** I measured "does this cache agree with
its generator" by calling `graphcmp.emit_py(g, None)` for all 34 graphs **in one process**.
That is wrong, and not harmlessly wrong: `UOp.unique_num` (`tinygrad/uop/ops.py:839`) is a
module-level `itertools.count` that reaches the row stream through
`Tensor.empty`'s `ParamArg(next(UOp.unique_num), ...)` and out through `graphcmp.py:708`'s
`u(pa.slot)`. Graph 1 emits `P(i0,…)`, graph 2 emits `P(i13,…)`, and by graph 34 every row
carries a number no published artifact could contain.

| cache | my WRONG value | correct, one fresh process per graph |
|---|---|---|
| `checks/rows-FLAT` | 9 fresh / 25 stale of 34 | **11 / 23** |
| `checks/both-FLAT` | 9 fresh / 25 stale of 34 | **11 / 23** |
| `oracles` | 17 fresh / 8 stale of 34 | **7 / 18** (of 25 held) |
| `checks/rows/DIR` | **2 fresh / 25 stale of 34** | **27 / 0** |

`.agents/slop/hermetic/isolate.py` exists for exactly this and says so in its own header.
Every number in §1 comes from `isolate.emit`, one fresh process per graph.

**0.2** `censusclaims.py` passed `g_flip` to `isolate.emit`; `GRAPHS` is keyed by the **bare**
name. 18 WALLs, all `KeyError: 'g_flip'` from `graphcmp.py:1613`, all my own `g_` prefix. A
WALL is not a verdict.

**0.3** `censusclaims.py` AST-parsed `.agents/slop/graphcmp.bend`. It is not Python;
`SyntaxError` at line 1664. The bend fixture keeps its censuses in `#` comments, so they are
not docstrings and cannot be reached by `ast.get_docstring`.

**0.4** `dircensus.py` v1 built cache templates by CHARACTER alignment.
`rows-flip-py.rows` vs `rows-matmul-py.rows` differ at index 5 and every index after, so one
`*` per pass and a fixpoint both degenerate to `rows-************`, which covers a real cache.
**DENOMINATOR 0 over all 100 directories walked** — a zero that hides 100 directories is
worse than no instrument.

**0.5** `dircensus.py` v2 aligned on TOKEN arity. `rows-flip-py.rows` is 3 fields and
`rows-threefry-bend.rows` is 4, so grouping by field count **split one population in two at
the length of the graph's own name**, which is not a cache property at all.

**0.6** `dircensus.py` v3 took only the LARGEST single-arity group per directory. `oracles/`
is flat — 329 files — so its largest group was `tinybendygrad_…rows` and the
`rows-<graph>-<side>.rows` population, the whole subject, was dropped as "covers nothing".
That reported **DENOMINATOR 5 and hid four of them**.

**0.7** `discover.py` v1 took `write_text`'s `args[0]` as the path. That is the **content**;
for `recv.write_text(x)` the path is the receiver. 166 sites were reported with their
contents as if those were their paths.

**0.8** My first `g_flip` edit mangled line 1361 into `srcs[0], UOp): return srcs[0]`, and
quoted the old false census back inside my own prose — so my own instrument then found
`WRONG flip docstring={'GROUP': 1}` in the sentence explaining that there is no `GROUP`.
Quoting a census-shaped token inside a docstring creates the thing the docstring denies.

**0.9** My first `census.py` key implementation was wrong twice, and both are MEASURED and
now written into the file: (a) `write_key` emitted **two** tab-separated fields while
`read_keys` demanded **three**, so `--fresh --only flip` returned rc=0, wrote the cache, wrote
the key, and the very next run answered `STALE` on both lanes; (b) see §2 — I keyed **per
side**, which is the class one level down, and I shipped it for one measurement cycle.

**0.10** `gates/gate-surface.py --report` returned **rc=1**,
`FileNotFoundError: gates/tn_graph_census-gate.py.bak`, at 16:14. Not mine: another unit was
mid-edit in `gates/` (`git status -- gates/` shows `gatekit.py`, `gates-pop.ledger.tsv`,
`msgdiff-gate.py`, `tn_graph_census-gate.py` modified and two untracked `rng_graph_census*`
files). Re-run: **rc=0, `SHELL HALF: 18`**. A first run of a gate under concurrent edits is
not a verdict either.

---

## 1. WHICH CACHE IS AUTHORITATIVE, AND BY WHAT RULE

### The rule, derived rather than assumed

A cache's authority follows from **its generator**, and it has two halves. Both, not either:

1. **a generator whose write path IS this path** — derived by walking the tree's own write
   sites, never a hand list; and
2. **that generator's ability to say the slot is stale** — a key, a `--check`, anything that
   turns "old" into a verdict instead of a silent serve.

**Content resemblance is not authority, and the `flip` pair proves it in both directions.**
`oracles/rows-flip-bend.rows` has the right ROW COUNT (6, no phantom `GROUP`) and is still
the wrong file: its FLIP arg reads `n(i1,i0)`, the pre-`ABoolList` rendering.
`checks/rows/rows-flip-bend.rows` has the right ARG (`n(b1,b0)`) and is still the wrong file:
it carries a 7th row. Each is half-right in a different axis. **Neither half is authority.**

### The measurement

**Py lane, 34 graphs from `graphcmp.GRAPHS` (the generator's own declaration, loaded by
path), each graph emitted by `isolate.emit` in a FRESH PROCESS, compared byte-for-byte:**

| cache | slots held | reproduce | STALE | generator write site | can it say STALE? |
|---|---|---|---|---|---|
| `checks/rows-<g>-<side>.rows` | 34 | **11** | **23** | `checks/census.py:128` | no, until §2 |
| `checks/both-rows-<g>-<side>.rows` | 34 | **11** | **23** | `checks/both-census.py:74` | **no** |
| `oracles/rows-<g>-<side>.rows` | 25 | **7** | **18** | **none found** | no |
| `checks/rows/rows-<g>-<side>.rows` | 27 | **27** | **0** | `checks/hermetic-census.py:134` | **yes** |

**Both lanes, from the instrument that owns them.**
`DEV=CPU .venv/bin/python checks/hermetic-census.py --check` → **rc=3**,
`# --check: 39/68 published row sets reproduce; 29 do not`. Of the 29, **28 are `ABSENT`**
(never published) and **exactly one is a content mismatch**:

```
# STALE flip/bend: published rows=7 fresh rows=6 md5 cd34beb2f7d59538651c502e346d5fd3 vs 7c334c319d6c6da4d13e71ac8322b3e3
```

### The verdict

**`checks/rows/` is authoritative for 39 of its 40 slots and MEASURABLY STALE for exactly one
— `flip/bend` — and the instrument that owns it already says so, with a denominator, at rc=3.
`oracles/` is authoritative for none of the 18 py slots it is stale on, and has no generator
to appeal to.**

### Two corrections to the brief's framing, both measured

**It is not "two caches from two generations".** The two sets are not independent witnesses;
one is a subset of the other. `7fc222c02` deleted 28 files from `checks/rows/` claiming they
were byte-identical duplicates of `oracles/`. **MEASURED: all 28 are byte-identical to the
CURRENT `oracles/` files.** `checks/rows/` today is exactly the 40 slots that *differ* from
`oracles/`.

**`checks/rows/rows-flip-bend.rows` was never corrupt — it is DATED.** `git show
2a889e7aa:.agents/slop/graphcmp.bend` (the commit that staged `checks/rows/`) reads at 1354-1355:

```
1354:  +fl = O.UOp.new(..., O.OpsFLIP{}, ..., O.ABoolList{[True{}, False{}]}, ...)
1355:  O.UOp.new(O.Found.ar(fl), O.OpsGROUP{}, [O.Found.i(fl)], O.ANone{}, O.TNone{})
```

and `HEAD`'s fixture has no line after the FLIP. **MEASURED: today's live bend rows plus that
one `GROUP` line reconstruct `checks/rows/rows-flip-bend.rows` BYTE-EXACTLY.** So the file is
a faithful emission of a real generator state. Its content was right. **Its key was never
recorded, so nothing could say it was old** — which is this whole report in one sentence.

### `oracles/` has no generator. Established by discovery, not by absence of a grep.

AST over every `.py` in the repo for write sites naming both `oracles` and `rows`: **32
sites, none of which writes `oracles/rows-<graph>-<side>.rows`.** Ten files *read* it
(`checks/no-txt.py`, `.agents/slop/argowner/handoff.py:99-101`, `.agents/slop/whichgroup/`,
others). `checks/unowned.py:112` declares a generator for the `checks/rows-` prefix only.
**A diary has readers and no author.** That is the definition, and it is measured.

---

## 2. WHAT A STALE CACHE SHOULD DO — REFUSE. Here is the costing.

| option | cost | verdict |
|---|---|---|
| **refuse** | one sha256 per side per run; `hermetic-census.py --check` already does the whole thing at **rc=3** in ~40 s | **CHOSEN** |
| regenerate | silently overwrites the evidence and makes a wrong answer look fresh; costs a `bend` process per slot — the same money as the check, and it produces no verdict | rejected |
| carry the commit | **wrong key.** Units commit into this tree while a run is in flight, so a commit key churns for edits that cannot change a row, and it is a plain falsehood whenever the worktree is dirty | rejected |
| delete | the cache exists to avoid re-paying `bend`; `emit --graph flip --side bend` measured ~1.2 s wall for both lanes, so the full corpus is ~40 s; deleting destroys the 39 published slots that DO reproduce | rejected |

**The key is the generating fixture's bytes, not a commit.** If `graphcmp.py` has not changed,
`emit_py` cannot have; if `graphcmp.bend` has not changed, `emit_bend` cannot have. Both paths
come from the module (`_GRAPH`, `G.BEND_PROBE`) and are never retyped.

### Is `.agents/slop/SUBJECTS.rows`'s shape what `census.py`'s cache needs?

**Right SHAPE, wrong CONTENT — and, taken alone, insufficient.**

`SUBJECTS.rows` carries `path  in_head  on_disk  readable_now`. One row per claim, claim and
truth side by side, drift visible in the file itself. That is the correct instinct and I used
it: `checks/rows-key.rows` is `graph<TAB>side<TAB>sha256`, one row per slot, same shape.

But it answers **"is this path still there"**, and a cache's failure mode is not a path going
missing — it is a path staying exactly where it was while the thing that fills it moved
underneath it. `checks/rows/rows-flip-bend.rows` is in HEAD, on disk, readable, correct-shaped,
and 21 commits out of date. **And a column cannot stop `side()` serving. Serving is the whole
failure.** Drift visible to a reader is necessary and is not sufficient; the refusal has to be
in the code path that decides whether to serve.

### The bug I shipped and then measured, because it is the class one level down

**I first keyed per SIDE.** The reasoning was real — one generator file emits one lane for all
34 graphs, so one digest decides all 34. True of the *decision*, false of the *key*.

MEASURED: `--fresh --only flip` recorded the py digest having written exactly **one** slot,
and the next `checks/census.py --only allred` **served a slot that is measurably stale** —
`allred` py, live sha256 `c132f982b000` vs cached `a26fae5f072e` — off that key, and exited 0.
The scope column reading `ALL rows-*-py.rows` was the lie that let it through. **A key whose
scope is wider than the run that wrote it is this whole report, one level down.** Fixed to one
row per slot.

*(A related misreading, in the same measurement: I narrated `alu` as one of the 23 stale slots
because the list ran together. It is not — `freshness.py`'s stale list is `allred binblob bit
buffer bw cast cdiv commute flip group late lin matmul move mstack mulacc reduce stage sym
threefry unshard where wmma`, and `alu` is absent from it. `alu` reproduces.)*

### `checks/census.py` after the change — five states, all MEASURED

| state | command | rc | what it printed |
|---|---|---|---|
| cache present, no key | `checks/census.py` | **3** | `STALE : 68 of 68 slots …`, `reached PY 0`, served **NEITHER** |
| re-emit | `checks/census.py --fresh --only flip` | 0 | `# flip py=OK 6 bend=OK 6`, key written for 2 slots |
| key matches | `checks/census.py --only flip` | 0 | `# flip py=CACHE 6 bend=CACHE 6` |
| **slot with no key, measurably stale** | `checks/census.py --only allred` | **3** | `# allred py=STALE 0 bend=STALE 0` — **not served** |
| generator bytes change | append one line to `graphcmp.bend`, re-run | **3** | `# flip py=CACHE 6 bend=STALE 0` — one lane's refusal does not take the other with it |

`checks/rows-key.rows` introduces no new tracked path: `.gitignore:167` is `checks/rows-*.rows`
and covers it (verified with `git check-ignore -v`). `checks/unowned.py:112`'s pin on the
literal `rows-{name}-{which}.rows` still resolves (`checks/census.py:128`).

**Two slots of the cache were rewritten by the verification itself**: `--fresh --only flip`
re-emitted `checks/rows-flip-py.rows` and `checks/rows-flip-bend.rows`. Those two files are
now fresh; the other 67 carry no key and are correctly `STALE`.

---

## 3. `graphcmp.py:1357` — FIXED, WITH THREE SIBLINGS, AND FOUR LEFT WITH THE OWNER NAMED

**It is prose, and that is why it could rot.** MEASURED: **0 docstring-read sites** across
`checks/*.py`, `gates/*.py`, `.agents/slop/*.py`, `oracles/*.py` (AST: every
`Attribute(attr="__doc__")` and every `Name(id ∈ {getdoc, cleandoc})`). A census in a
docstring breaks nothing mechanically, so the bend half corrected its own and the py half did
not, and the pair then disagreed about what the census is.

**MEASURED, live:** `emit --graph flip --side py` → 6 rows, census
`ALLOC=1 CONST=2 FLIP=1 RESHAPE=1 STACK=1`; `--side bend` → 6 rows, `# root=6 nodes=7
settled=True`; the two files byte-identical. `GROUP=1` was false, and so was
`**EXPECTED TO DISAGREE, ON \`arg\`.**`

**Census claims in `graphcmp.py` docstrings: 18 total, 8 WRONG before this change, 4 after.**
Audited by `.agents/slop/whosecache/censusclaims.py` (`ast.get_docstring` over the `def g_*`
functions, compared against `isolate.emit`).

| graph | docstring said | live rows say | action |
|---|---|---|---|
| `flip` | `… FLIP=1 GROUP=1 …` | `ALLOC=1 CONST=2 FLIP=1 RESHAPE=1 STACK=1` | **fixed**, `:1356-1383` |
| `mulacc` | `ALLOC=3 CONST=3 GROUP=1 MULACC=1 RESHAPE=3 STACK=3` | `ALLOC=3 CONST=2 MULACC=1 RESHAPE=3 STACK=1` | **fixed**, `:1495` |
| `getaddr` | `ALLOC=1 GROUP=1 GETADDR=1` (2 rows cannot carry 3 ops) | `ALLOC=1 GETADDR=1` | **fixed**, `:1506` |
| `unshard` | `ALLOC=1 CONST=2 GROUP=1 RANGE=1 RESHAPE=1 STACK=1 UNSHARD=1` ("4 nodes") | `ALLOC=1 CONST=3 RANGE=1 RESHAPE=1 STACK=1 UNSHARD=1`, 8 rows | **fixed**, `:1517` |
| `lin` `:1140` | `… SHRINK=2 … WHERE=0` | no `SHRINK`, no `WHERE` | **LEFT** |
| `loop` `:1161` | 6 ops | 14 ops, the docstring's are a strict subset | **LEFT** |
| `threefry` `:1483` | `ALLOC=2 … RESHAPE=2 STACK=2 …` | `ALLOC=3 … RESHAPE=3 STACK=1 …` | **LEFT** |
| `wmma` `:1529` | `… CONST=3 GROUP=1 … STACK=3` | `ALLOC=3 CONST=2 RESHAPE=3 STACK=2 WMMA=1` | **LEFT** |

**Why the other three were fixed and these four were not.** `graphcmp.bend` explicitly
disputes the py docstring for all four I fixed, in its own comments at `:1353` (`flip`),
`:1380` (`getaddr`), `:1388` (`unshard`) and `:1424` (`mulacc`) — and `:1388` already states
the rule: *"the py fixture's docstring claims `GROUP=1`, but its own rows carry none, so the
rows win."* Those are the **two halves of one pair disagreeing**, which is what I was sent to
stop. `graphcmp.bend` says nothing about `lin`, `loop`, `threefry` or `wmma`; there is no pair
to reconcile, and `checks/disagree-gate.py`'s `PIN` table discusses `lin` and `loop` at length
as graphs that **left** the disagreeing set, so their docstrings are the record of that
history. **Owner: whoever owns `disagree-gate.py`'s `PIN` set.** Reported, not rewritten.

**Line-count discipline.** `checks/disagree-gate.py:119-124` PINS `.agents/slop/graphcmp.py`
lines **1386, 1394, 1413, 1458** by line number. `g_flip`'s docstring was rewritten
**28 lines in, 28 lines out** precisely so those four do not move; the three later docstrings
sit below 1458. Re-verified after every edit: all four resolve. File 3109 → 3113 lines.
`ast.parse` clean; `emit --graph flip` still answers 6 rows.

**Also MEASURED, NOT FIXED — out of my surface.** `checks/disagree-gate.py`'s own `CITES`
table: **14 line-pins, 12 resolve, 2 FAIL**, and both are pre-existing:

- `.agents/slop/graphcmp.bend:1571` should contain `def rows.pick3` — it contains a `+r0 =`
  statement;
- `.agents/slop/graphcmp.bend:777` should contain `OpsGROUP` — it contains a comment. This is
  the pin that reads *"the bend fixture builds that GROUP by hand, bypassing `UOp.group`"*,
  and the fixture no longer has a GROUP there. **The pin and the proof it carries have drifted
  together, in the file that carries the proof for `flip`.** Owner: whoever owns that table.

---

## 4. THE CLASS, CENSUSED BY DISCOVERY

**Population:** a directory walk over `checks/`, `gates/`, `oracles/`, `runs/` with
`os.walk(followlinks=False)` (matching `find -type f`, which does not descend a symlinked
directory), grouping files by **(first field, extension)** — `rows-flip-py.rows` →
`('rows', '.rows')`. Token/arity alignment was tried and rejected (§0.4, §0.5): a key's length
is not a property of the cache. Every arity group of ≥8 members is reported, not just the
largest, because taking only the largest dropped the subject (§0.6).

> **DENOMINATOR: 15 groups of ≥8 files, over 100 directories holding 1418 files, in 4 trees.**
> A group is a **shape**. It does not name a generator and it does not date anything.

The four `rows-*.rows` groups in it, each asked the two questions:

| cache | files | generator (write site) | generator runs? | can it say STALE? | py-lane reproduces |
|---|---|---|---|---|---|
| `checks/rows-<g>-<side>.rows` | 70 | `checks/census.py:128` | **yes — rc=3 since §2** (was **rc=0**) | **yes, as of §2** | 11 / 34 |
| `checks/both-rows-<g>-<side>.rows` | 68 | `checks/both-census.py:74` | yes, rc=0 | **no** — no `--check` mode exists | 11 / 34 |
| `checks/rows/rows-<g>-<side>.rows` | 40 | `checks/hermetic-census.py:134` | yes — rc=0 publish, **rc=3 `--check`** | **yes** | **27 / 27** |
| `oracles/rows-<g>-<side>.rows` | 54 | **NONE FOUND** (32 write sites examined; 10 readers) | n/a | no | 7 / 25 |

**A fifth cache exists outside the four trees:** `.agents/slop/whichgroup/rows/`, 68 files.
Its generator is `.agents/slop/whichgroup/corpus_fresh.py:59-60` — and that generator **never
reads its own output**, it re-emits every run. **So it is a fixture, not a cache, and it
cannot go stale.** A previous unit (`whichgroup`) reached the same conclusion about
`checks/rows-*.rows` from the other direction; its header is worth reading.

> **DENOMINATOR, stated the way the brief asks: of the 5 caches of the 34-graph corpus that
> exist, 4 are inside `checks/`/`gates/`/`oracles/`/`runs/`, 1 has no generator at all, and
> before this unit exactly 1 of those 4 could say it was stale. It is now 2 of 4.**
> The other two are still open: `checks/both-census.py`'s cache is byte-identical to
> `checks/census.py`'s on all 34 py slots — same emitter, same rows, same age — and has no
> check. **Deleting it is a reduction and costs nothing**: nothing reads
> `checks/both-rows-*.rows`, and `checks/census.py` already reproduces its census. Owner: the
> `both-census.py` unit.

---

## 5. VERIFICATIONS (all re-run against the final tree)

| check | rc | evidence |
|---|---|---|
| `checks/no-txt.py` | **0** | |
| `checks/nl-gate.py` | **0** | `gated 205  agree 205  disagree []` · `AGREE` |
| `gates/gate-surface.py --report` | **0** | `II SHELL HALF: 18` |
| `flip` both lanes | — | `py=6 bend=6` **BYTE-IDENTICAL** |
| `checks/census.py` bare, cache present, no key | **3** | `STALE : 68 of 68 slots` |
| `.agents/slop/graphcmp.bend` vs `HEAD` | — | byte-identical, sha256 `2e180103720eccde…` |
| staged files | **0** | `git diff --cached --name-only \| wc -l`, verified against `ls-tree` |

**Not committed, not staged.** Diff surface: `.agents/slop/graphcmp.py` (+62/−34 lines of
prose and 4 docstring censuses), `checks/census.py` (+96/−4: the key, `STALE`, exit 3, and a
header that names all three caches instead of two), and the untracked
`.agents/slop/whosecache/`.

## 6. INSTRUMENTS LEFT IN THIS UNIT'S DIRECTORY

`discover.py` (write sites, AST + shell) · `dircensus.py` (the directory walk) ·
`freshness.py` (per-cache py-lane reproducibility, fresh process per graph) ·
`censusclaims.py` (docstring census vs live rows).

**`discover.py`'s headline, for whoever wants the write-site map:** 237 write sites over the
four trees; 71 literal-path (an artifact, no population); 166 keyed. Two of the keyed ones
are `checks/census.py:74` and `checks/both-census.py:82`, and they are the same generator
writing two caches of one corpus into one directory. `gates/checks` (25 sites) is
`gendirs.py`'s scratch tree, not a cache directory, and is excluded for that reason rather
than counted.