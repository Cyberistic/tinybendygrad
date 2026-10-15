# `.agents/TOOLS.md` — the drift, re-measured 2026-10-15T19:15:56Z

Scope: **one tracked file**, `.agents/TOOLS.md` (1,631 lines), read as the
COMMITTED blob (`git cat-file blob HEAD:.agents/TOOLS.md`), asserted byte-equal
to the working tree (sha256 `2c016b02…0cdc` both ways). Instrument:
`.agents/slop/ledgerdrift/drift.py`, one command, 3.9 s. Outputs: `paths.rows`
(the deliverable), `lanes.rows` (per-token detail), `measure.out` (this run's
stdout). Every number below carries its denominator and was produced by that one
run unless the line says otherwise.

## 1. The extraction rule, stated

Every **backtick-quoted span** of the file containing `/`; normalized by
stripping markdown emphasis (`*_[]()`), trailing `.,;:)"(`, and a leading `./`;
URLs, `git@` and `//` excluded; tokens carrying whitespace, `$` or `::`
excluded. This is **byte-for-byte the rule the ledger's own generator declares**
(`.agents/slop/toolsledger/extract.py:20-27`) — which is why the denominator is
comparable to the ledger's own.

**The method is proven, not assumed.** Under this rule, **8 of the 11** revisions
of `.agents/TOOLS.md` before 2026-10-09 extract to **exactly 333** distinct
paths. The figure the ledger records therefore belongs to a specific revision:
`cb2e5ad4f` (2026-10-07T16:55:24+03:00), 1,548 lines, denominator **333**. This
is why the delta below is decomposed: *text growth*, *tree movement* and *the
rule itself* move the answer, and only one of them is drift.

## 2. Resolution: the ledger's instrument has a single-base blind spot

`.agents/slop/toolsledger/extract.py:29-32` resolves a token against **one**
base, the repo root, and calls it ABSENT otherwise. The ledger does not write
paths from the repo root. It writes:

- **port paths port-relative** — `uop/ops.bend` for `tinybendygrad/uop/ops.bend` (25 tokens);
- **Bend `import` targets** — `../helpers.bend` (TOOLS.md:179,201,242,271), which resolve relative to the importing `.bend`;
- **compiler-checkout paths** — `bend2/base.bend` for `references/bend/bend2/base.bend` (TOOLS.md:71);
- **`tinygrad/` oracle paths** — `autogen/nv.py` for `tinygrad/runtime/autogen/nv.py` (5 tokens).

So no base is **listed** here — a base list is the same defect one level down.
A token **RESOLVES iff some path that exists ends with it**, over an index built
by discovery (`git ls-tree -r HEAD`, 7,268 paths, plus a disk walk of the
gitignored checkouts). Three outcomes are kept apart:

| lane | meaning | today |
|---|---|---|
| `exact` | exists where the ledger writes it | **193** |
| `suffix` | exists, but only as the tail of another path (base unstated) | **42** |
| `absent` | exists nowhere on disk and nowhere in HEAD | **132** |

Denominator **367** = 193 + 42 + 132. Of the 42 suffix resolutions: 25 land in
`tinybendygrad/`, 8 in `.agents/slop/`, 5 in `tinygrad/`, 4 in `references/`.
**Two of the 42 land in `.agents/slop/rf2root/`, a mirror tree, not the port**
(`runtime/`, `schedule/rf2_work.bend`) — those are PRESENT by this rule and
should not be read as "the port has a `runtime/` at the repo root".

## 3. The delta, both timestamps side by side

| reading | when | denominator | present | absent | absent under `.agents/slop/` |
|---|---|---|---|---|---|
| **ledger header** (`TOOLS.md:12-14`) | 2026-10-07 | 333 | 164 | 169 | 85 |
| **`toolsledger/paths.tsv`** (333 rows, on disk) + its `REPORT.md` | 2026-10-06 | 333 | 160 | 173 | 96 |
| **`AGENTS.md`** (same 333, different split) | 2026-10-06 13:00 | 333 | 153 | 180 | 96 |
| **mine, ROOT lane, that rev's own tree** | 2026-10-15 | 333 | **165** | **168** | 84 |
| **mine, SUFFIX lane, that rev's own tree** | 2026-10-15 | 333 | **203** | **130** | — |
| **mine, ROOT lane** (today's tree) | 2026-10-15T19:15:56Z | **367** | 193 | 174 | 86 |
| **mine, SUFFIX lane** (today's tree) | 2026-10-15T19:15:56Z | **367** | **235** | **132** | 86 |

Reading the delta:

- **The denominator grew 333 → 367 (+34 tokens)**, from 1,548 to 1,631 lines of
  ledger. That is text growth, not drift.
- **At the old revision and the old tree, the ROOT lane reads 165/168 against
  the ledger's 164/169.** Off by one, in both directions. The cause is known and
  I cannot repair it: `extract.py:18` asked **`git ls-files`** — the index of
  that day — while I asked `git ls-tree -r cb2e5ad4f`. **REFUSED: I cannot
  reproduce 164/169 exactly, because the index it read no longer exists.**
  The denominator is a function of rule + text only, which is why 333 reproduces
  exactly and the split does not.
- **The rule, not the tree, is the bigger error: 38 of those 168 "absent" paths
  were relative references to files that existed at that very revision.** They
  were never missing; the instrument could not see them. Today the same defect
  hides **42 of 367 (11.5%)**.
- **The 86 absent under `.agents/slop/` is unchanged between lanes** — pruning,
  not resolution, and it matches no witness above (85 / 96 / 96).

## 4. The dangerous class: the absent paths a live instrument still names

Split by whether a live `checks/*.py` / `gates/*.py` source carries the path in a
**string literal** (parsed with `ast`, so a `#` comment cannot make a path look
invoked; 226 `.py` and 17 `.sh` sources read). Of the **132** absent:

| class | count | meaning |
|---|---|---|
| **INSTRUMENT** | **1** | a live check names it as an input |
| PROSE | 131 | named only in the ledger, or by another report |

**The one INSTRUMENT — the actual dangerous row:**

> **`.agents/slop/xd1/render-gate-oracle.py`** — invoked by literal at
> **`checks/rn-gate.py:74`**: `ORACLE = [".agents/slop/xd1/render-gate-oracle.py", "--gate"]`.
> Absent from disk and from HEAD. A live check names a file that is not there.

**Three more absent paths that are near-misses, and why they are NOT counted:**

- `.agents/slop/xd1/wt-sync.sh` — absent, but the live file is `checks/wt-sync.sh`. **Stale location**, a file that moved.
- `.agents/slop/trigger/bc-oracle.py` — absent, but `gates/bc-u32-gate.py:60` names `.agents/slop/bitcastrow/bc-oracle.py`, which exists. **Stale location.**
- `checks/graphcmp.py` — absent; 9 live checks name `.agents/slop/graphcmp.py`, which exists, and `checks/census.py:37-38` says in its own docstring that the `checks/` copy "was already dead at `3f0e70ff1`". **Stale location.**

My first pass called all three INSTRUMENTS. They were **basename collisions** —
`bc-oracle.py` in the ledger and `bc-oracle.py` in a gate are the same basename
and a different file — and they are the same defect `checks/repro-paths.py`'s
own ledger row records, where a suffix set read `…-gate.py.bak` as `…-gate.py`,
**a file that exists**, and counted a broken reference as RESOLVED. Confirmed
here: `gates/tn_graph_census-gate.py` exists (7,690 B), and the ledger's absent
token is `gates/tn_graph_census-gate.py.bak`. I classify on a **path-tail match**
(`L == t`, or one tails the other with a real directory segment on both sides),
not on a basename.

**Classifier comparison.** `.agents/slop/toolsledger/extract.py:34` classifies by
a **basename regex** (`gate|check|sweep|differ|…`) and calls **5** of the 132
absent INSTRUMENT. **2 of those 5 are the classifier errors `AGENTS.md` already
records**: `xd1/pin` (a revision reference — `git cat-file -t` answers `commit`)
and `.agents/slop/runs/elf-checkonly-2026-10-04.txt` (110 B of captured stdout).
The other 3 are `.agents/slop/dd-gate-base-172.txt` (a data row dump),
`gates/tn_graph_census-gate.py.bak` (a backup of a file that exists) and
`.agents/slop/xd1/mutate.py` (the one the regex is right about, for the wrong
reason — it matches `mutate`). **My live-citation rule finds 1. The two
classifiers disagree on 6 of the 132 absent rows**, and on each of the other 5 the
regex is the wrong answer.

## 5. `xd1/mutate.py`

**GONE, and independently confirmed** (4 checks, 2026-10-15):

1. not on disk — and `.agents/slop/xd1/` itself is gone;
2. `git cat-file -e HEAD:.agents/slop/xd1/mutate.py` → **rc=128**, no such path in HEAD;
3. `git log --all -- .agents/slop/xd1/mutate.py` → **0 commits**;
4. `git rev-list --all --objects` → **0 of 41,478 distinct history paths** match `xd1/mutate.py` (193,329 objects total).

`AGENTS.md` quotes "ALL 75,336 HISTORY PATHS" for the same search; today's
equivalent count of **distinct** paths is 41,478 and the raw object count is
193,329, so that figure is from a different measure or a smaller tree. The
**conclusion is unchanged either way: no blob, no ref, no path.**

## 6. Contradictions, stated rather than deferred to

1. **The ledger contradicts its own generator output.** `TOOLS.md:12-14` says
   333 / **164** present / **169** absent / **85** under `.slop/`.
   `.agents/slop/toolsledger/paths.tsv`, sitting in the same directory, has 333
   rows and reads **160 / 173 / 96**. Both cannot be the output of
   `extract.py` on the same tree. The file the ledger names as its own refresh
   mechanism disagrees with the number in the ledger's own header.
2. **`AGENTS.md` gives a THIRD split for the same denominator** (153/180/96). Three
   witnesses, one denominator, three present-counts.
3. **`extract.py`'s single-base resolution is a wrong instrument, not a stale
   number**: it calls 42 present files absent today, 38 at the old revision.
   Re-running it as written will keep reporting drift that is not drift.
4. **The absent population contains tokens that are not paths at all.** 31 of the
   132 absent have no dot in their last segment; of those, at least
   `try/finally`, `plant.out/err`, `range.out/err`, `DIR/tinybendygrad`,
   `oracle_pmul0/1` and `DSPAllocator._alloc/_free/_offset` are notation — a
   Python keyword, a template, a glob. So the denominator 367 overstates the
   path population by a handful. I did **not** subtract them: guessing which
   tokens a writer "meant" is exactly the inference that makes these counts
   uncheckable. They are reported as-is and named here.

## 7. REFUSED

- **REFUSED — reproducing the ledger's 164/169 split.** `extract.py:18` read the
  git **index**; no index of 2026-10-07 exists. The 333 denominator reproduces
  exactly (rule + text only); the split does not, and I will not present my
  number as "the same number, updated".
- **REFUSED — a unique revision for the figure.** 8 revisions extract to 333. I
  report `cb2e5ad4f`, the newest of them, and say so rather than claiming to
  have found *the* revision.
- **NOT MEASURED — whether any of the 132 absent paths are load-bearing in a
  shell-only, `bend`-only, or human-only workflow.** The INSTRUMENT class is
  scoped to `checks/*.py` + `gates/*.py` string literals. A path cited only
  from `AGENTS.md`, from another `.agents/slop/` report, or by a person reading
  the ledger is PROSE by that definition, which is a statement about the
  instrument's reach, not a claim that the path is unimportant.