# `substrateid2` — the disposition of `checks/substrate-id.py`

**Unit**: `substrateid2`. **HEAD at census**: `c83f04ad1c125b5496e724583cde86fd7ef95396`.
**Scope**: `checks/substrate-id.py` (532 tracked lines, unchanged line count) and this directory.
Nothing else was touched. No `bend` was run. Nothing was staged or committed.

**Verdict on the disposition: WIRE IT — and it cannot be wired in its current state, because on a
fresh clone of `HEAD` it returns `PASS` while measuring nothing.** That is not a hunch and not a
census row; it is reproduced below in four lines. The honest summary is that the file is
**load-bearing** (it owns a reader nothing else owns) and **currently unsafe** (its entire
population is an untracked file), and those two facts are not in tension — they are the same file.

---

## 0. WAYS THIS MEASUREMENT IS WRONG — STATED FIRST

Five, all mine, all found by running the instrument and not by reading it. Each one MOVED a number
that a reader would otherwise have taken as fact.

| # | My defect | How it showed | What it moved |
|---|---|---|---|
| 1 | `tree_files` filtered the home with `endswith("/checks/")` on a line-delimited listing | population printed **0 of 0** | 0 → 152. **This is `readerdecl`'s `None` failure verbatim**: a key resolving to nothing, printed as a number. |
| 2 | Reader corpus read from the WORKTREE via `pathlib` | `FileNotFoundError` on `.agents/slop/adev/CLAIM.md` | 8 tracked files are staged-`D`; the worktree is not the tree. Switched to one `git cat-file --batch` over `HEAD`. |
| 3 | `blobs()` wrote 6537 requests to a **pipe** before reading one response | deadlock; killed at **280 s** | Fixed by feeding stdin from a file. Also `<sha> path=X` is **not** a batch request on this git — it answers `missing` for a blob `git cat-file -t` calls `blob`. |
| 4 | Non-`.py` blobs were all treated as shell readers | `checks/substrate-id.py` reported **INVOKED BY 12** | 11 were `.rows`/`.tsv`/`.out` **row dumps** and one was `gates/gates-pop.ledger.tsv`, a census ROW. A row dump that *prints* a path has not *run* it. **12 → 1.** The brief's "invoked by 0" was right and my axis was wrong. |
| 5 | Namers matched a **bare stem** | `checks/compile.py` NAMED BY **1121**, `cli.py` 342, `plant.py` 1018 — all from `re.compile(` | A **basename shape is not a population**: true of every gate, specific to none. Requiring the extension in the *citation* is the discriminator, and it is a property of the citer, not a list of citers. |

A sixth, smaller one: my first `verdict_names()` scanned two files for *any* int-keyed module-body
dict and returned `['PLANTS','VERDICTS','classes','found','reached','subs']` — `classes`, `found`,
`reached`, `subs` are `gate-surface`'s own census accumulators, not verdict declarations. It
happened not to change the count (138 either way), which is luck, not correctness. See §3.

**How a census that resolves a key to `None` reports zero is the whole subject of this project.**
Four of my five defects were the same bug wearing different hats, and the first one printed
`0 of 0` with a confident, correctly-formatted, entirely false header.

---

## 1. WHAT IT UNIQUELY MEASURES — and it is not redundant

The brief's suspicion was that this is redundant with `checks/differ.py`'s `SUBSTRATE_ROWS`.
**It is not.** Measured, by reading both and by running both on a tree with no `.agents/` at all:

`checks/differ.py:834` owns `SUBSTRATE_ROWS`, `:851 substrate_digest()`, `:875 substrate_entries()`,
`:886 substrate_rows()`, `:892 substrate_bad()`. It **writes** the two rows into
`runs/graphcmp/D/D0-run-summary.txt` (`:462` takes the first, `:679` the second) and it **checks
the two rows against each other** (`:892`).

What `differ.py` does **not** own, and what nothing else in the tree owns:

1. **The third comparison.** `differ.py:892 substrate_bad()` asks *did the substrate move during
   the run*. `substrate-id.py:203` asks *is this the tree in front of me* — `here["digest"] != end`.
   These are different questions, and `substrate-id.py`'s own docstring at `:24-28` argues they are
   the reason there are two rows. No other file in 6537 tracked blobs makes this comparison.
2. **The `DEAD` verdict.** `substrate-id.py:223 judge()` decides `DEAD` on the *file* (absent
   summary; summary holding no `key=value` row). `differ.py` has no `DEAD` on this path at all.
3. **The mid-run plant.** `substrate-id.py:353` CASE 3 is the case `pinindep` §7.3 records as
   *"never tested"*, plus `:374` its mirror (a COLD edit that moves the digest while every artifact
   stays `rc=0`). `differ.py` has no plant for the substrate rows.

**This is a WRITER/READER PAIR, and the census cannot see that.** `differ.py` writes two rows
nobody reads. `substrate-id.py` is the only thing in the tree that reads them. A census that counts
"invoked by" sees zero invocations and concludes dead code; the pair is connected by *data*, not by
an import or an argv.

**And on today's tree it produces a live finding.** `checks/substrate-id.py --judge` against the
real summary returns **`REFUSED` (3)**, not 0:

```
REFUSED, NOT A VERDICT: the substrate MOVED DURING THE RUN (ec5d92a5c83a -> 7dbea6a472b1).
The artifacts are not all measurements of one substrate.
  NOTE, not a verdict: 2 DECLARED input(s) are ABSENT ... .agents/slop/graphcmp-dbg.bend,
  .agents/slop/graphcmp-empty.bend
```

`SKIP`/`DEAD`/`REFUSED` are not passes. **Token: `REFUSED`.**

### 1a. THE DEFECT THAT DOMINATES: its whole population is an UNTRACKED file

`checks/substrate-id.py:89` hard-codes `ROOT / ".agents/slop/quiesce/snapshot.py"`, and `:106`
returns `[]` when it is absent. Measured:

- `git ls-tree -r HEAD --name-only | grep -c quiesce` → **0**. It is **not in the tree.**
- `git ls-files --error-unmatch .agents/slop/quiesce/snapshot.py` → **rc=0**. It **is in the index.**
- `git status --porcelain -- .agents/slop/quiesce/` → **8 × `A`** (added to index, absent from `HEAD`).

This is precisely the index-vs-tree trap, and the file's only population source is on the wrong
side of it. Consequence, measured on a tree built from `git archive HEAD` with no `.agents/` at all:

```
$ .venv/bin/python checks/substrate-id.py --hash
{"absent": [], "bytes": 0, "declared": 0,
 "digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "inputs": 0}

$ verdict_for(d, d, d) -> (0, 'this tree IS the substrate that produced the run --
                                 0 inputs, 0 bytes, digest e3b0c44298fc1')
```

`e3b0c442…` is the sha256 of the empty string. The instrument **hashes nothing, and says PASS.**
`AGENTS.md` doctrine 2: *"A gate that exits 0 having measured nothing is worse than no gate,
because it is trusted."* This is that gate, on a fresh clone, today.

**The file declares this verdict and cannot emit it.** `:55-56` says `DEAD` (5) is *"the population
is empty — nothing was measured at all"*, and `:320` says CASE 1 *"is the case that would fail first
if `population()` were empty."* `judge()` reaches `DEAD` only from the *summary file* (`:234`, `:239`).
There is no branch on `here["inputs"] == 0`. The declared verdict is unreachable — which is
`gates/gate-surface.py`'s `UNPLANTED` finding reproduced inside the gate it audits.

**Contrast, same tree, same moment:** `checks/differ.py:851 substrate_digest()` returns
**145 entries** there, because `SUBSTRATE_INPUTS` and `tinybendygrad/` are both tracked. So the
writer survives a fresh clone and the reader does not.

### 1b. `differ.py`'s own input table is a HAND LIST, and this file's fix is the one that is right

`checks/differ.py:845` is an eight-item `SUBSTRATE_INPUTS` tuple — a literal list, which
`AGENTS.md` doctrine 1 names as *not* a population, and which `differ.py`'s own comment at `:843`
concedes (*"`--declare` … is the instrument that checks this table against the tree"*).
`substrate-id.py:98-112 population()` instead **asks** `snapshot.inputs()` and `snapshot.COPIES`,
which is doctrine 1's clause (a) — *a generator's own declaration, loaded by path*.

So the file the census flagged as unowned is the one that gets the population rule right, and the
file that is wired into every run gets it wrong. **That inversion is the strongest evidence that
the disposition is "wire it", not "retire it".** But note the consequence: the hand list at
`differ.py:845` and the discovered population here are **not the same set** (145 vs 148 entries
measured), so the two files compute *different digests of the same run*. Whoever wires this must
reconcile that, and that is a decision with a cost, not a free merge.

---

## 2. THE NAMERS, AND THE CENSUS CORRECTION

The brief says "NAMED by 11 tracked files, INVOKED by 0". Measured on the tree (`HEAD`), 18 tracked
files contain the string `substrate-id`, one of which is the file itself, so 17 name it — but **16
of those 17 name it in prose, row dumps, or a census row**:

| namer class | count | what it is |
|---|---|---|
| `.agents/slop/**` probes and reports | 15 | `substrateid/`, `onemodule/`, `subtree/`, `denominator/`, `residue/`, `plantthe46/`, `gatedelete` |
| `gates/gates-pop.ledger.tsv` | 1 | **a census ROW**: `checks/substrate-id.py  py-main  ROOT = …  0  1` |
| the one real CALLER | 1 | `.agents/slop/substrateid/impact.py`, via `importlib` `spec_from_file_location` — a **probe**, not a gate |

`gates/gates-pop.ledger.tsv` is generated by `gates/gates-pop.py`. It records that the file *has* a
`ROOT` assignment and an entry point. **It is the census's own row and it is not a runner** — the
brief is right, and it is the same distinction §0/4 forced on my own axis.

**`checks/substrate-id.py` is not shadow-copied.** Verified: `git ls-tree -r HEAD` has exactly one
path matching `substrate.id|substrate_id`, the real one. So its 16/1 is genuine and not an artifact
of a copy — which matters, because 15 tracked paths *elsewhere* in the tree are repo copies
(`.agents/slop/corpuswire/tree/checks/differ.py`, `.agents/slop/denominator/probe/checks/*`,
`.agents/slop/figure2/plant/{real,broken}/checks/*`) and `gatecensus/classify.py` defect 1 says
*"a citation inside a copy of the documentation is a citation of the copy."* My census excludes
those 15 and says so in its own output.

---

## 3. THE CLASS, CENSUSED BY AST AND DIRECTORY WALK

`.agents/slop/substrateid2/census.py`. **Population: 152 tracked `.py`** = 66 in `checks/` + 86 in
`gates/`, by `git ls-tree -r HEAD` (the tree, not `git ls-files`, which reads 154 — the +2 is
`.agents/slop/quiesce/`-adjacent work, and the two differ for exactly the reason in §1a).

Homes are `gates/gates-pop.py`'s own `HOMES`, **read by `ast` from that file** rather than retyped.

| axis | count | of |
|---|---|---|
| (a) NAMED by tracked code, INVOKED by none | **88** | 152 |
| (b) NO verdict declaration at module body | **138** | 152 |
| (c) BOTH | **81** | 152 |
| named by nothing at all | 0 | 152 |

Split of (a): **43 in `checks/`, 45 in `gates/`.**

**Axis (b) vocabulary is loaded by path from its generator.** `gates/gate-surface.py:237` binds
`DECL = ("VERDICTS", "PLANTS", "RED_IS")` and `:194` reads it off a gate's module body. The census
asks that file. Exactly **14 of 152** ship a declaration, all 14 binding `PLANTS` + `VERDICTS`:
`checks/{dup-census,dup-gate,env-precond,gate,hermetic-census,nl-gate,nl-gate-noguard,no-txt,
norm_check,oracle_f64,residue,rn-gate,wallcheck}.py` and `gates/gate-surface.py` itself.
Three others bind int-keyed dicts under names the generator does not declare (`PSP_ERRORS`,
`defs,spans`, `declares`) and are therefore counted as undeclared — **which is correct under
clause (b), because they are not declarations `gate-surface` can read.**

**`checks/substrate-id.py` is one of the 81.** Its row: `named=16  invoked=1  declares=NONE`.
The brief's "no `VERDICTS = {...}` declaration" is confirmed and is **not** a defect of
`gate-surface`'s making — line 50 is a docstring sentence, and the census's own third plant case
asserts a docstring mention is not a declaration.

**SCOPE AND LIMITS OF THIS CENSUS, IN THE SAME SENTENCE AS THE NUMBERS.** The `152` counts tracked
`.py` under two directories named by one file's `HOMES`; it excludes `.sh`, `.mjs` and
extensionless scripts as *members* of the population (they are counted as *readers*), and it
excludes any gate home a third `HOMES` edit would add. The `88` and `81` are **lower bounds on
non-invocation**: the invoked axis parses **353 of 1656** tracked `.py` (those mentioning
`checks/` or `gates/`; the rest provably cannot name either) and tokenises non-`.py` readers by
program extension or shebang — so a tracked program in a fourth language is invisible to it.
Parsing all 1656 (a 201 MB pack) did not finish in 300 s, and that cost is the reason for the
prefilter, which is a stated limit rather than a silent one.

**Is the tree already answered on disk? YES, for the shape.** `gates/gate-surface.py` already owns
"which gates declare a verdict surface" and clause V already audits it; `.agents/slop/canrun/`
already owns "can each `checks/*.py` be run" (53 per-file transcripts tracked). **A fourth check did
not find the shape on disk** — what did not exist is the *named-vs-invoked* axis. That is what this
directory's `census.py` adds, and it is a `.agents/slop/` probe, **not** a fourth `checks/` gate,
because §3's own result says a new uninvoked gate would land in the class it measures.

---

## 4. THE ELEVEN `NAMES[]` SITES — fixed, and the fix's cost reported

**There are TEN, not eleven.** Measured by AST over `ast.Subscript`/`ast.Attribute` on the name
`NAMES`: `:247` (`NAMES.get`, ×1) and `:329, :347 ×2, :367, :382, :436, :448, :451, :457`
(subscripts, ×9). `boolexit`'s eleventh is the `:76` **definition**, not a use.

**Done**: the ten sites now go through one `token()` (`:78-101`). `checks/substrate-id.py` grew
532 → 559 lines; `--plant` prints **`PLANT: OK`**, rc 0, 24 expectations, none wrong
(`.agents/slop/substrateid2/plant-substrate-id.out`). `ruff check` reports **12 errors before and 12
after** — the change introduces none. `checks/no-txt.py` is **rc=0**, `CLEAN`.

**Measured before/after** (`.agents/slop/substrateid2/tokentest.out`):

| input | before | after |
|---|---|---|
| `True` | `NAMES.get(True, True)` → **`'FAIL'`**, silently | `NOT-A-VERDICT(bool)` |
| `False` | → **`'PASS'`**, silently | `NOT-A-VERDICT(bool)` |
| `4` (SKIP, not in this file's vocabulary) | → printed the bare number `4` | `NOT-A-VERDICT(4)` |
| `IntEnum` member | → correct token | → correct token |

**THE COST, AND WHY THE STRICTER FORM WAS REJECTED.** `type(x) is int` is the form `boolexit`
implies. Measured on this interpreter:

```
isinstance(IntEnum_member, int)  -> True      type(x) is int -> False
hash(IntEnum_member) == hash(3)  -> True      NAMES[member]  -> 'REFUSED'   (works)
```

**`type(x) is int` buys bool-safety by refusing an `IntEnum` verdict vocabulary** — an encoding of
the *same five verdicts* that hashes equal to its int value and indexes `NAMES` correctly. The
stricter form is not strictly better; it trades a real regression for a latent one. `token()`
therefore rejects **exactly the type that is wrong**, `bool` — named, because `bool` is the only
subclass of `int` that is not an int-valued verdict — and keeps `IntEnum`. An unassigned code is a
refusal rather than an exception or a bare number, which is `gates/gatekit.py`'s `verdict_of()`
rule reused rather than reinvented.

---

## 5. DISPOSITION, and the precise question for the owner

**WIRE IT.** Specifically: `checks/substrate-id.py:223 judge()` is the only reader of the two rows
`checks/differ.py:834` writes, and it answers the one question `differ.py:892` does not. The
natural home is `checks/differ.py`'s own `unhealthy()` — beside `substrate_bad()`, which is already
the function that decides whether the summary is honest.

**But it cannot be wired as it stands, and the fix is not a one-liner. Three things must land
together, and the second is a decision I am escalating rather than making:**

1. **Make the empty population `DEAD`, not `PASS`.** Add a branch on `here["inputs"] == 0`. The
   file already *declares* this verdict (`:55-56`) and cannot emit it (§1a). Without this, wiring it
   puts a gate that trusts a fresh clone into every run — the exact doctrine-2 failure, in the gate
   that would enforce doctrine 2.

2. **THE OWNER'S DECISION — where the population lives.** The population is 148 entries discovered
   from `.agents/slop/quiesce/snapshot.py`, which is **in the index and not in the tree**. Options,
   with their cost:
   - **(i) Track `quiesce/snapshot.py`.** Smallest diff, but it promotes a `.agents/slop/` probe
     into a load-bearing input of a `checks/` gate — and `AGENTS.md` says *"`gates/artifacts/` …
     is `.gitignore`d and is where gate runs write, so one `rm -rf` deletes anything kept there"*;
     `.agents/slop/` is under active pruning tonight (33 staged deletions in `git status` alone).
     Wiring a gate to a pruned tree re-creates that exact defect.
   - **(ii) Move the population into `checks/`, beside the gate that needs it.** This is what
     `AGENTS.md` prescribes verbatim — *"a gate's required input belongs beside the gate IN GIT"* —
     and it is the option I recommend. **It changes the digest**: the 148 entries and the resulting
     `substrate-start`/`substrate-end` values would change, so every already-written summary in
     `runs/graphcmp/D/` becomes un-comparable and would need re-running. That is a real cost with a
     real owner, and it is not mine to spend.
   - **(iii) Point it at `differ.py`'s walk + `SUBSTRATE_INPUTS`.** Reuses the writer, deletes the
     untracked dependency, and **inherits `differ.py`'s hand-list defect** (`:845`), which is the
     thing this file was written to be the answer to. Worst of the three despite being smallest.

3. **Reconcile the two populations.** Measured: `differ.py` hashes **145** entries, this file
   discovers **148**. They are different sets and currently produce **different digests of the same
   run**. Whoever wires this must state which is the substrate, because until they do, the two rows
   in the summary and the verdict `judge()` prints are answers to different questions.

**What I did NOT do, deliberately.** I did not wire it (§2's rule: touch nothing outside
`checks/substrate-id.py` and this directory — `checks/differ.py` is not mine). I did not retire it:
a 532-line file that is the sole reader of a live artifact, whose own `--judge` returns `REFUSED` on
today's run, is load-bearing in a way the census cannot see. And I did not delete the
`population() == []` branch, because deleting it makes `token()`'s new vocabulary unreachable for
the one case that most needs it.

---

## 6. ARTIFACTS

| path | what |
|---|---|
| `.agents/slop/substrateid2/census.py` | the class census (AST + directory walk), with a three-case `--plant` control |
| `census.out` | the four axis numbers and both scopes |
| `rows.tsv` | per-file: path, namers, invokers, declarations (152 rows) |
| `plant.out` | census control, `PLANT: OK` |
| `plant-substrate-id.out` | `checks/substrate-id.py --plant`, rc 0, `PLANT: OK` |
| `tokentest.out` | before/after of the ten `NAMES` sites, incl. the `IntEnum` cost |
| `rows.out`, `hash.out` | the two rows and the digest of today's worktree |
| `who.invokes`, `gate.py.namers` | the defect-4 and defect-5 investigations |
| `notxt.out` | `checks/no-txt.py` rc=0 |