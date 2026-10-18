# WHAT `substrate_digest()` STILL DOES NOT COVER

**HEAD `5f31663e48e7` · read `2026-10-18T18:56:26Z` · scope: read-only, `ast.parse` only.**
No `bend`, no corpus loop, no `gates/`, no `differ.py run`, no `pytest`/`mypy`/`ruff`.
Writes confined to `.agents/slop/drivercov/`. Nothing committed — this unit was told to write only
here, so it did **not** tick anything off in `.agents/TODO.md`.

## 0. THE TREE MOVED THREE TIMES WHILE THIS WAS MEASURED

Recorded because every number below is a reading and the readings disagree with each other by
exactly this much:

| when (UTC) | HEAD | `substrate_digest()` |
|---|---|---|
| 18:49 | `e92adbb5cc10` | `7e81e1057d4923e7…` |
| 18:54 | `cea5fc2ac5d3` | `2020a283f0c7f09a7…` |
| 18:56 | `5f31663e48e7` | `28e11db5492a7334…` |
| 18:57 | `5f31663e48e7` (**unchanged**) | `ba4f99cc1c516680…` |

Three different HEADs and four different digests, with **no edit by this unit**.

**THE LAST ROW IS THE ONE THAT MATTERS: THE SAME COMMIT PRODUCED TWO DIFFERENT DIGESTS, 70
SECONDS APART.** `substrate_digest()` walks the **working copy**, not a tree object, so an
uncommitted edit to anything under `tinybendygrad/` or `tinygrad/` moves it while HEAD stands
still. That is the digest working exactly as its docstring says it should — content-keyed, and a
mid-run substrate move must be caught — and it is also the reason `substrate_entries()` **cannot**
be reproduced from a commit. The reproducibility a digest is usually wanted *for* is a function of
the commit; this one is a function of the working copy, and the two come apart the moment a second
agent is in the tree.

Re-running the whole pipeline changed exactly one line of `coverage.rows` — the stamp — and left
all 20 rows byte-identical, so the census itself is deterministic against a fixed tree.

## 1. THE RE-TAKEN POPULATION

Taken **in-process from the generator** — `import checks.differ` then `substrate_entries()` — so
this is the generator's own answer and not a second walk of the same tree.

**387 declared inputs = 379 walked + 8 named.**
`SUBSTRATE_WALKS = ("tinybendygrad", "tinygrad")` — `tinybendygrad/` **150**, `tinygrad/` **229**.

| question | answer | denominator |
|---|---|---|
| `tinygrad/*.py` covered? | **213 / 213** — 0 uncovered | 213 `.py` on disk |
| `.agents/slop/*.py` covered? | **4 / 1016 = 0.394 %** | 1016 `.py` on disk, excluding this unit's own 5 |
| `tinygrad/` fully covered? | **yes** — 229 walked members, all pinned | 229 |

**THE PARENT'S NUMBER, AND WHY IT IS NOT RE-DERIVED BUT ALSO NOT REPRODUCED.** The brief reports
"5 of the 977 `.agents/slop/*.py` drivers". I measure **4 of 1016**. Both halves moved. The `5`
is recoverable if you count all five `graphcmp*` members of `SUBSTRATE_INPUTS` — but one of those
five is `graphcmp.bend`, so by the `.py` filter the numerator is **4**, and the four are exactly
`graphcmp.py`, `graphcmp-oracle.py`, `graphcmp-dbg-oracle.py`, `graphcmp-p13-ops.py`. The
denominator 977 → 1016 is the tree moving under both measurements. **I report 4 / 1016 and refuse
to reconcile the earlier reading**, because reconciling it would require a second population and
Doctrine 1 says the population is the generator's declaration, loaded by path.

**THE FIX IS CONFIRMED AND IT IS THE RIGHT FIX.** The old population's 156 inputs covered **0 of
213** `tinygrad/*.py` — the reference every verdict is relative to. That is now 213/213. A digest
that omits the subject of the comparison is a pin on the scale, not the subject.

## 2. THE EXECUTED-DRIVER CENSUS

**The population is DISCOVERED, not listed.** `.agents/slop/drivercov/runpath.py` walks the AST of
`checks/differ.py` and follows five edge kinds — `subprocess` argv, `importlib.util.
spec_from_file_location` args, local imports, **calls to this module's own functions**, and
**path-shaped arguments at those call sites** — folding module constants, `ROOT / "x"` path
expressions, `Path("x")` and `str(x)` so a path named in five different syntactic positions
resolves to one file. Every gap below is a gap that instrument had to be taught; each is recorded
in its source, because the interesting number is not the answer but how many wrong answers the
instrument gave on the way to it.

**Root: `cmd_run`** (`:687`), the entry `checks/differ.py run` dispatches to. The run issues seven
graphcmp subcommands, read out of the `run(...)` calls inside `cmd_run`:
**`conf`, `control`, `cross`, `dbg`, `diff`, `emit`, `selfcheck`.**

### Executed, and IN the digest — 8 of 10

| artifact | why it runs |
|---|---|
| `checks/differ.py` | the orchestrator itself |
| `checks/devpin.py` | `IMPORTLIB` edge `devices()` → `:1094` |
| `.agents/slop/graphcmp.py` | `gc()` → `:400` |
| `.agents/slop/graphcmp.bend` | `emit` → `emit_bend` `graphcmp.py:2171` |
| `.agents/slop/graphcmp-oracle.py` | `capture()` `:907` |
| `.agents/slop/graphcmp-dbg-oracle.py` | `capture()` `:910` |
| `.agents/slop/graphcmp-p13-ops.py` | `capture()` `:914` |
| `bin/bend` | argv[0] of every bend call — its **bytes** only, see §3 |

### Executed, and NOT in the digest — 2. NAMED.

**`.agents/slop/graphcmp-dbg.bend`** — the port fixture for the `dbg` lane.
`cmd_run` issues `run("D8-dbg-012.txt", "dbg", "--levels", "0,1,2")` and
`run("D8-dbg-03.txt", "dbg", "--levels", "0,3")`; `_dispatch` `graphcmp.py:3288` routes `dbg` to
`debug_run`, which runs `subprocess.run([str(BEND), str(BEND_DBG)], …)` at **`graphcmp.py:3021`**
with `BEND_DBG = SLOP / "graphcmp-dbg.bend"` at `:274`. **`SUBSTRATE_INPUTS` names `graphcmp.bend`
and not `graphcmp-dbg.bend`.** The file is git-tracked (`git ls-files` = 1) and on disk (10,151 B).

**`.agents/slop/graphcmp-empty.bend`** — the zerorow-guard fixture.
`differ.py:897` binds `probe = Path(".agents/slop/graphcmp-empty.bend")` and `:903-904` runs
`run(f"{D10}.txt", "emit", "--side", "bend", "--bend-probe", str(probe))` **in the `else`
branch**. **That branch is taken**: the file is present, 110 B. (The `if` branch's own comment at
`:901` claims it was "deleted in 371cc64c9" — that is now false, and it is the *only* thing that
made the probe's absence a `REFUSED` verdict. The guard is now guarding a file that is back.)
Uncovered, git-tracked.

**Both are `.bend` fixtures under `.agents/slop/`, both git-tracked, both one line from covered.**
The digest's 8 named inputs list `graphcmp.bend` and neither of these: the list was written when
those were the only two, and it was never re-derived from what the run actually executes.

### Named by the run but NOT executed — 4, and a text census would have got all 4 wrong

An independent grep witness (`.agents/slop/drivercov/grep-witness.rows`) over the run-path sources
for `.agents/slop/*.py|bend|sh` returns **10** names. It **disagrees with the AST closure in both
directions**, which is why both witnesses are kept:

* **over-inclusive by 4.** `graphcmp-p14d.py`, `graphcmp-probe-optq.bend`, `graphcmp-run.sh`,
  `graphcmp-repro.sh` appear **only inside docstrings** (`graphcmp.py:2`, `:1127`, `:1276`;
  `differ.py:2`). An AST check for *standalone* string literals finds none of them in an
  executable position. A grep census reports 4 phantom drivers.
* **under-inclusive by 1.** `graphcmp-dbg.bend` is built from `SLOP / "graphcmp-dbg.bend"`, so the
  full-path grep pattern never matches it — **the one uncovered input is invisible to grep.**

A census needs the AST. A grep is a witness, not a population.

### Not executed by `differ.py run` — 3, correctly not on the run path

`gates/gatekit.py` (reached only from `plant()` `:1498` and `cmd_repro` `:1662`);
`checks/runs-artifacts.py` (the `snap` subcommand only, `:1843`);
`.agents/slop/diffpy/oracle-run.sh` and `oracle-repro.sh` (pinned by `ORACLE_PIN` `:62`, and
`GCMP_RUN` is read **only** by `oracle-repro.sh:124` — `differ.py` never reads it, so `differ.py run`
does not drive the shell oracle).

## 3. WHAT `bin/bend` RESOLVES TO

The shim's last line is `exec bun "$_d/../references/bend/bend2/main.ts" "$@"`.

| question | measured answer |
|---|---|
| target | `references/bend/bend2/main.ts`, 38,563 B |
| inside the repo working tree? | **YES** — `realpath` stays under the repo root |
| tracked in git? | **NO** — `git ls-files references` = **0**; `.gitignore:2` is `references/` |
| walked by `SUBSTRATE_WALKS`? | **NO** — the walks are `tinybendygrad` and `tinygrad` |
| so pinned by the digest? | **NO** |
| compiler clone state | `references/bend` @ `4ff8545f19b0`, `git status --porcelain` = 0 lines |
| how much is behind it | `references/bend` = 2,024 files; `bend2` alone = 93 files / 1.4 MB |
| the runtime | `bun` 1.3.13 at `/Users/cyberistic/.bun/bin/bun` — **outside the repo** |

**SO: PHYSICALLY INSIDE, VERSIONED NOWHERE.** The compiler is not outside the repo — it is inside
the working tree and outside **git**, which is the worse position, because a path can be inside a
directory and still be unreproducible from it. `tools/get-bend.sh` (1,180 B) is the fetcher; it is
the only tracked description of how 93 files of compiler arrive.

**THE DIGEST PINS THE POINTER, NOT THE POINTEE.** `bin/bend`'s 5 lines ARE in `SUBSTRATE_INPUTS`.
The 93 files its last line names are not. Editing `references/bend/bend2/*.ts`, or re-running
`tools/get-bend.sh` onto a different commit, changes what compiles every `.bend` in the port and
`substrate_digest()` does not move.

**AND `bin/bend` IS ITSELF UNTRACKED, WHICH BREAKS THE DIGEST ACROSS CLONES.** Measured with the
same generator, `bin/bend` forced to its `ABSENT` token:

```
digest as measured now   2020a283f0c7f09a7be819467bd392b27964a01d844e6bb10d6b5a1aa7269377
digest with bin/bend ABSENT b0b34dc9266067239c9f44bac3c02409710bddbf9d4c8244faf76217527b6cb2
EQUAL? False
```

A fresh clone has no `bin/bend` (`.gitignore:5`, `git ls-files bin/` = **0**), so **two clones of
the same commit produce two different `substrate_digest()` values** and `REPRO_SUBSTRATE` from one
cannot be compared against the other. `substrate_digest()`'s docstring says it is keyed on content
"never on `st_mtime` … so a fresh clone of one tree writes every file at the moment it is cloned,
so an mtime key is a fact about THIS TREE and two clones would disagree" — and then solves the
mtime half and misses the **existence** half. **The "one substrate" claim holds within a tree
that has run `tools/get-bend.sh`, and silently does not hold across a clone boundary.**

Also measured, and not used by the shim: `references/references` is a stray symlink to another
worktree's `references`. It is not on `bin/bend`'s path and changes nothing; recorded so the next
reader who sees a symlink in `references/` does not go looking for a second compiler.

## 4. THE RESIDUAL GAP, CLASSIFIED

Denominators stated, because a count without one is not a result.

**Tier A — in-repo files the run reads: 389, pinned 387 = 99.49 %.**
(10 named/executed files + 379 walked.) The 2 unpinned are the two `.bend` fixtures of §2.

**Tier B — the unversioned in-repo shim: 1, pinned 1 = 100 % of its bytes, 0 % of its meaning**,
and per §3 not comparable across clones.

**Tier C — the toolchain: ~962 files, pinned 0 = 0 %.**
`references/bend/bend2` 93 files, `bun` 1, `.venv` 868 `.py` plus binaries. By count the whole run
is pinned **387 / 1351 = 28.6 %**.

| | class | verdict |
|---|---|---|
| (a) **the reference** | `tinygrad/` | **FIXED.** 213/213 `.py`. The largest correctness gap is closed. |
| (b) **the compiler** | `references/bend/bend2` + `bun` | **OUT OF REACH** — gitignored, outside `SUBSTRATE_WALKS`, and cross-clone unstable. Closable by one walk root (§5), but only honestly. |
| (c) **the drivers** | `.agents/slop/*.py` | **MEASURABLE NOW.** 2 git-tracked `.bend` fixtures, uncovered. Closed by two strings (§5). |
| (d) **something else** | **the interpreter tier**, and **two ways the digest is not a function of the commit** | Not previously on anyone's list. `.venv` (868 `.py`) and `bun` are the same class as (b) and are counted by nobody. Then §0 (**working-copy keyed**: same HEAD, two digests) and §3 (**clone-unstable**: `bin/bend` untracked ⇒ `ABSENT` on a fresh clone). Both are *separate* from coverage — the pin can be complete and still not reproducible. |

**The honest headline: correctness inputs are 99.5 % pinned; the run is ~29 % pinned by file count,
and the missing 71 % is entirely the toolchain that decides what the port's `.bend` files MEAN.**

## 5. THE CHEAPEST CHANGE THAT CLOSES THE LARGEST GAP

**Proposed, NOT implemented** — this unit was scoped read-only outside this directory.

**Do this one, first, because it closes the entire in-repo gap: add two strings to
`SUBSTRATE_INPUTS` at `checks/differ.py:1174`:**

```python
SUBSTRATE_INPUTS = (..., ".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend")
```

Two strings. Both files are git-tracked, so the digest becomes a function of the commit for the
last time. Both get the existing `ABSENT` treatment for free — `substrate_entries()` already
appends `ABSENT` for a declared path that is missing (`:1227`), so this cannot shrink the
population silently, which is the `quiesce/snapshot.py:80-85` defect the docstring warns about.
**Largest gap closed: 2 of 2 uncovered in-repo inputs, at the cost of 2 lines.**

**Then, the compiler — but NOT as a bare walk root, and here is why.** `"references/bend"` in
`SUBSTRATE_WALKS` looks like one more word, and it is a trap: `rglob` over a **missing** directory
yields **nothing**, not an `ABSENT` token, so a clone without the toolchain would produce a
*smaller* population and a *different* digest that still looks internally consistent — repeating
the exact defect the docstring documents. The correct shape is to walk it **and** emit one
declared row for the toolchain's own identity — `references/bend`'s HEAD, `bun --version`, and a
sha256 over `main.ts` — so a missing or moved toolchain arrives as a named **`REFUSED`**, which is
what `gatekit` already has a word for, rather than as a quietly shorter pin. **This is bigger than
one line and I am not pretending otherwise: it is the only change here that needs a design, and it
should not be smuggled in beside a two-line fix.**

**The structural fix, which is the one I would actually argue for.** Both misses are the same
shape as `checks/sweep.py`'s `LIVE_UNITS`, `checks/differ.py`'s old `find -name '*.txt'`, and
`repro-paths.py`'s suffix set — a population **declared by hand** instead of discovered.
`SUBSTRATE_INPUTS` is a hand list, and a hand list cannot see a file that was added downstream.
`differ.py` already contains the fix for this elsewhere: `corpus()` (`:108`) loads `graphcmp.py` by
path **because `graphcmp.py` declares its own `GRAPHS`**, and that is why the corpus denominator
cannot drift. The same move applies: have the run **report** the set of files it executed and
assert that set is a subset of `substrate_entries()`, the way `checks/index-arm-gate.py` asks
"is the default index armed?". **Today nothing in the tree asks that question**, which is why two
`.bend` fixtures survived a digest whose whole purpose is to prove one run measured one substrate.
The census in this directory is that instrument, in ~180 lines of `ast.parse`, and it needs no
`bend` and no run to work.

## 6. WHAT THE INSTRUMENT GOT WRONG FIRST (so the next reader does not trust it blind)

Eight defects, each of which produced a *wrong answer*, not a crash — recorded because a census
that has only ever been right is a census nobody has checked.

1. **Tuple targets dropped every paired constant.** `PY, GCMP = "a", "b"` puts a `Tuple` in
   `targets[0]`, so an `isinstance(..., ast.Name)` guard dropped both. Closure read **3 files**
   where the true answer is 13. It found `bin/bend` (a literal argv) and missed the driver family.
2. **Literal-only argv resolution.** Fixing (1) exposed that `graphcmp.py:3021` writes
   `str(BEND_DBG)`. Not unwrapping `str()` reported the `dbg` lane as unrun — the exact claim the
   `D8b-*` artifact exists to support.
3. **A denylist of traversable extensions.** `("*.bend","*.js","*.md")` handed `.venv/bin/python`
   to `ast.parse` → `source code string cannot contain null bytes`. Replaced by an **allowlist**
   `(".py",".sh")`, which fails on the unknown member instead of the known one.
4. **`isfile`, not `exists`.** `GCMP_REPO = "."` resolved to the repo ROOT and printed `.` as an
   input.
5. **`spec_from_file_location` args[0] is the MODULE NAME.** Reading it instead of `args[1]` made
   `checks/devpin.py` — *a declared substrate input* — invisible, and an instrument that cannot
   see a pinned file reports it as uncovered.
6. **Constant folding that folded `"a"` but not `ROOT / "a"`, `Path("a")`, or `A and B or C`.**
   Three separate misses (`BEND_DBG`, `probe`, `probe or BEND_PROBE`), each of which hid a file
   the run executes.
7. **A basename collision inventing a driver.** `run(…, "emit", "--side", "bend", …)` — and
   `checks/bend` **is a real 153-byte file**, so the side-token resolved and the closure grew an
   eighth driver nothing runs. Fixed by requiring an argument edge to be **path-shaped** (contains
   `/` or `.`). *This is the `ORACLE_WORD` basename-shape trap met in the argument position.*
8. **`all()` over an empty set reported `yes`.** `references/bend/bend2/**` came back **pinned** —
   because no walk member starts with it and `all(∅)` is `True`. **A vacuous universal quantifier
   in a coverage column is "compared nothing reads as agreement" wearing a different hat**, and it
   asserted that the compiler was pinned. It is not.

Plus one **shadowing** defect: `checks/census.py` exists, so `import census` from
`.agents/slop/drivercov/` resolved to **that file** at `sys.path[0]` and raised
`AttributeError: module 'census' has no attribute 'stamp'`. Renamed to `runpath.py`. A module name
that collides with an existing one is a silent wrong answer waiting for a `try`.

## 7. REPRODUCING

```
.venv/bin/python .agents/slop/drivercov/pop.py        # §1 population, from the generator
.venv/bin/python .agents/slop/drivercov/runpath.py    # §2/§4 closure + subprocess inventory
.venv/bin/python .agents/slop/drivercov/emit_rows.py  # coverage.rows
```

None of the three compiles anything, imports no `tinygrad`, and runs no `bend`. Each is a single
process, well under a second and a megabyte or two. `runpath.py` must be re-run before
`emit_rows.py`: the latter reads `census.json` rather than re-walking, so it will happily print a
stale table against a moved tree — which is what §0 is about.