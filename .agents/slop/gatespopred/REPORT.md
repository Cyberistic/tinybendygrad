# `gates/gates-pop.py`: is the RED a finding about the tree, or a limit of the instrument?

**READ `clauses.rows` FIRST. SIX CLAUSES, SIX ROWS, ALL SIX VERDICTED
`INSTRUMENT_LIMITATION`. NOT ONE IS A REAL DEFECT IN THE TREE.**

Measured 2026-10-16 **14:35–14:42 UTC**, HEAD **`03500a26202aa8560adbab980f705ad9c0a7cbfb`**
(re-read at 14:41, unchanged). `gates/gates-pop.py` was **read and parsed, never run**; no gate,
`bend`, `checks/*`, or `gates/*` executable was executed. Everything below is my own
reimplementation (`.agents/slop/gatespopred/repro.py`) or the instrument's own functions loaded
by path and called on read-only measurements. Scratch files live in this directory; no `.txt`.

---

## 0. The one-paragraph answer

**The RED is a data string.** The whole verdict reduces to one clause, `1 resolve outside the
repo`, and that one row is `checks/cites-census.py` — whose real root is
`checks/cites-census.py:18`, `ROOT = Path(__file__).resolve().parent.parent`, which evaluates to
the repo root *exactly*. The instrument missed that line because `ROOT_CONST`'s tail is the
literal `\.parents\[(\d)\]`, so `.parent.parent` is invisible to it. It then fell through to
`ROOT_INLINE`, which matched a **string literal** at `checks/cites-census.py:664` — one element
of the file's own `--selftest` needle table — and `resolve_root` evaluated *that string's*
expression against the live file path. Remove that one string, in memory, and the row goes green.
**This is the fifth instance of the class this session found four times.**

---

## 1. What each clause measures, in its own terms

The summary line is `gates/gates-pop.py:1092-1094`, inside `report()`.

| Clause | Expression | What it actually counts |
|---|---|---|
| **I** entry points | `len(rows)` | One row per file in `checks/` + `gates/` whose *immediate* regular file `entry_reason()` returns `py-main`, `sh-dispatch`, `sh-selfref` or `js-main`. Python by AST (`if __name__` guard), shell by self-dispatch (`exec`/`$0`, two tokenizers unioned), JS by ESM syntax with no `export`. **Not** a suffix set — `entry_reason` reads the language out of the file. |
| **II** name a root | `named` | Files for which `root_facts()[0] != "-"`, i.e. `ROOT_CONST` or `ROOT_INLINE` matched a `parents[n]` expression, **or** the fallback at `:684` fired because a line `^\s*HERE\s*=` exists. |
| **III** assert it | `named - unasserted` | Of those, files whose `code_of()`-stripped source matches **both** `REFUSE` *and* `MARKER` — two literal regexes ANDed. |
| **IV** resolve outside the repo | `offroot` | Of those, files whose matched root expression, **evaluated** (not pattern-matched), does not resolve to the repo root. |
| **V** generated directories | `len(grows)` | `gates/gendirs.py`'s `table()` — distinct directories something in the tree *writes into*, found by scanning every source file under `SKIP_TOP` for a write site and propagating path constants to a fixpoint. |

**The RED is one clause.** In the default `--ledger write` mode, `report()` sets `red = 1` from
exactly one branch — `if offroot: red = 1` (`:1029-1030`). Every other red-setting branch is
gated on `ledger_mode == "check"`. So **clause IV alone decides the verdict**, and the other four
clauses are printed context.

**"308 generated directories" is shared.** `gates/gendirs.py` is loaded by path by both
`gates-pop.py` and `gates/retention-check.py`, deliberately: two instruments holding two lists
would have no authority over each other. That part of the design is sound, and I did not test
`retention-check.py` (I was told not to run anything under `gates/`).

---

## 2. Reproduction, with denominators

### Clauses I–IV: my own reimplementation, then the instrument's own ledger

`repro.py` reimplements `code_of`, `is_python_entry`, `is_literal_data`, `entry_reason`,
`resolve_root`, `root_facts`, `gate_homes` and `_buckets` from the source. I did **not** import
the module: agreement would then be a tautology, and disagreement would be a crash.

**My denominators:**

- **954** immediate regular files read across the **14** top-level candidate directories of the
  commit tree.
- **2 of 14** qualify as gate homes — `checks` (17 certified witnesses), `gates` (3). Matches the
  number the file's own prose carries.
- Inside the two homes: **494** immediate regular files (`checks` 251 + `gates` 245) → **197
  entries + 64 modules + 233 opaque**.

**The independent cross-check.** `gates/gates-pop.ledger.tsv` is the instrument's own snapshot
of its population, written by a run I did not perform (mtime **2026-10-16T14:10:22Z**, ~25 min
before I started). It holds **196** rows. Against it:

- **196 of 196 shared rows agree on every field. Zero disagreements.**
- The instrument's ledger independently totals **79** named, **23** asserted, **1** off-root.
- My one extra row is `checks/unrunnable-recipes.py`, mtime **14:15:30Z** — created **five
  minutes after** that snapshot. That single fact accounts for the 196→197.

| Clause | reported | reproduced | ledger agrees |
|---|---|---|---|
| I entry points | 189 | **197** | 196 (one file newer than it) |
| II name a root | 75 | **79** | 79 |
| III assert it | 21 | **23** | 23 |
| IV off-repo | 1 | **1** | 1 |

**The arithmetic is not the problem.** 189→197 is tree growth; three of the four clauses moved
together (197/79/23 against a reported 189/75/21) and the instrument's own same-day ledger
agrees with me to the row. **0 of 197** entry points are untracked. Note the provenance split,
which is honest but worth stating: `gate_homes` reads the **commit tree** (`git ls-tree -r HEAD`,
never the index), while `_buckets` enumerates the **working copy** (`iterdir()`).

### Clause V: `gendirs.discovered()`, sharded

A full pass is ~13.2 s (measured: 150 files at 5.7 ms/file over 2 318), over my 10 s budget, so I
sharded by *source* top-level directory — sound because the population key is the write **target**
(`os.path.dirname(rel)` for a file write), not the writer, so a `checks/` source writing into
`gates/artifacts` contributes the key `gates/artifacts` in the `checks` shard and the union is the
full population. 13 shards, **2 315 source files**, union = **311**.

`coverage()` reports `read=2319 present=3281` — the scan reads 2 319 of 3 281 source files; the
rest are under `SKIP_TOP` (`references`, `node_modules`, `.venv`, `__pycache__`, `bin`).

**Composition of the 311**, as four **disjoint** parts that sum to the total
(174 + 30 + 35 + 72 = 311):

| part | count | share |
|---|---|---|
| `.agents/slop/**` agent scratch | 174 | 56% |
| `examples/mlperf/**` upstream-vendored, not already counted | 30 | 10% |
| **parser artifacts**, not under `.agents/slop/` | **35** | **11%** |
| other real output dirs in the tree | 72 | 23% |

Counted over all 311 regardless of prefix, **74 rows (24%) are parser artifacts**, of which 39
are themselves under `.agents/slop/`. *I first printed this table with 31 mlperf and 74 artifacts
side by side as "disjoint"; 174+31+74+72 = 351 ≠ 311, so the overlap was real and the label was
false. The disjoint figures above are the measured ones.*

---

## 3. Verdict per clause

### I — entry points, 189 → 197 — **INSTRUMENT_LIMITATION**

The count is **reproduced and arithmetically sound**, and it contributes nothing to the RED. The
limit is population precision, and it is the same class: the clause counts an *entry point*, while
the file's own written definition of a gate (`gates/gates-pop.py:687-695`) additionally requires
**"it reports a verdict, meaning one of the five statuses `gates/gatekit.py` names, carrying a
denominator."** **14 of 197** (11 `-mutate.py`, 3 `-gen.py`) are mutation/generator harnesses that
do not, and no clause separates them. The file names four cases in its definition and reaches the
denominator honestly by printing the opaque bucket — but it never asks the *entry* bucket whether
the entry is a gate.

### II — name a root, 75 → 79 — **INSTRUMENT_LIMITATION**

**21 of the 118** files scored `root_const="-"` — "declares no root" — **do declare a correct
root**, in a spelling `ROOT_CONST` cannot read:

- **9** files: `ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))`
  (`checks/no-txt.py:62`, `citation-gate.py:8`, `graphcmp-census-audit.py:12`,
  `no-shrink.py:10`, `repro-paths.py`, `runs-artifacts.py`, `sweep.py`, `txt-owners.py`,
  `unowned.py`, `unrunnable-recipes.py`)
- **8** files: `ROOT = Path(__file__).resolve().parent.parent`
  (`gates/indexread-gate.py`, `rand_census-gate.py`, `state_census-gate.py`,
  `onnx_census-gate.py`, `crp_graph_census-oracle.py`, `ops_python_census-oracle.py`,
  `checks/devpin.py`, `checks/wallcheck.py`)
- **1** file: `ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))`
  (`checks/git-index-guard.py:8`)

Separately, **31** more entries are credited the **fabricated** string `"__file__.parent"` by the
fallback at `:684`, which names a *shape* rather than the file's expression. Altogether **52 of
197** root declarations are mis-read.

`ROOT_CONST` is not a small regex: it handles both `parents[n]` spellings (from a FILE and from a
DIRECTORY), which is the mistake this repo has made four times. It is still anchored on **one
syntactic form of path arithmetic**.

### III — assert it, 21 → 23 — **INSTRUMENT_LIMITATION**

**56 of the 79** named entries score `asserts=0`. `asserts` is `MARKER and REFUSE` — **two
four-way literal regexes, ANDed.**

- `MARKER` is the literal **`pyproject.toml`**. It appears in **2 of the 56**. The other 54 gate
  on something else: `tinybendygrad` **26**, `.git` **5**, `runs/` **4**, `oracles/` **1**, `.jj` **1**.
- `REFUSE` requires `refuse(` | `exit 3` | `not at the repo root` | `REFUSED, NOT A VERDICT`.
  Measured against `code_of()` — comments and docstrings stripped, so **no prose is credited** —
  **54 of 56** carry a refusal under one of ten alternative shapes: `sys.exit(N)` **51**, gatekit's
  imported **`REFUSED`** identifier **37**, `raise ValueError` **20**, `raise SystemExit` **14**,
  `assert` **8**, `refuse(` **8**.

**The exemplar, and it is not a close call.** `checks/abi_gate.py` — the file `gates-pop.py` cites
by name in its own docstring as a gate that refuses on a wrong root:

```
:24   REPO = HERE.parents[0]
:27   C_LANE = REPO / "tinybendygrad" / "runtime" / "dtype.c"
:32   def refuse(*why: str) -> None:
:43   if not C_LANE.is_file():
:44       refuse(f"REPO does not hold the tree: {REPO} is not the repo root ...")
```

`REFUSE` matches this file (it contains `refuse(`). `MARKER` does not. `asserts = False`. It is
scored *"names a root, does not assert"* purely because the marker it gates on is not the six
letters `pyproject.toml`. And `REFUSED` is the one identifier `gates-pop.py:87` imports rather
than re-spells — and the regex misses the identifier while matching the *prose* `"REFUSED, NOT A
VERDICT"`.

I am not claiming all 56 are undeclared. `checks/differ.py` genuinely has no root refusal
(`sys.exit(main())` and nothing else) and is a true positive. The claim is narrower and holds:
**the instrument's notion of "asserts" cannot see the tree's dominant idioms.**

### IV — resolve outside the repo, 1 → 1 — **INSTRUMENT_LIMITATION**

This is the whole RED. The row is `checks/cites-census.py`, reported `const =
'Path(__file__).resolve().parents[3]'`, resolving to `/Users/cyberistic/src`.

**The gate is not off-repo.** `checks/cites-census.py:18` declares
`ROOT = Path(__file__).resolve().parent.parent`, which evaluates to
`/Users/cyberistic/src/tries/2026-09-30-tinybendygrad` — the repo root, verified by hand,
`equal = True`.

**Two failures compose:**

1. `ROOT_CONST`'s tail is the literal `\.parents\[(\d)\]`. `.parent.parent` does not match. The
   real root at `:18` is invisible.
2. `ROOT_INLINE` is then consulted over the **whole file** and matches at
   **`checks/cites-census.py:664`**:

   ```python
   for kind, needle, gap, src in (
           ("code", "declared_values()", "", ""),
           ("code", "pathlib.Path(__file__).resolve().parents[3]", "", ""),
           ...
   ```

   That is **data**: a fixture in the file's own `--selftest`, a needle the census must classify
   as *code-shaped* — which is precisely why the string is in the table. `resolve_root` then
   evaluates *the string's* expression against the live file path.

**The decisive experiment** (in memory; the file on disk is byte-identical afterwards, verified):

| | `ROOT_CONST` | `ROOT_INLINE` | `const` | `onroot` |
|---|---|---|---|---|
| as the tree stands | `None` | `Path(__file__).resolve().parents[3]` | `'Path(__file__).resolve().parents[3]'` | **`False`** |
| that one string removed | `None` | `None` | `'-'` | **`True`** |

`offroot` is counted only inside `if const != "-"`, so `'-'` contributes 0. **One string literal
in a self-test table is the entire RED.**

### V — generated directories, 308 → 311 — **INSTRUMENT_LIMITATION**

**Is it growing, and why?** Growing, and **because the tree grew — the population did not widen.**

- `SKIP_TOP` and `SOURCE_SUFFIXES` are **byte-identical at HEAD and in the working copy** and
  unchanged since 2026-10-07.
- The same code measured **195** at `a8053cdf6` on 2026-10-06. 195 → 308 → 311.
- 308→311 is three more rows of *today's* scratch: **174 of 311 (56%)** are `.agents/slop/**`
  agent scratch, and that directory currently holds **365** immediate unit directories.

So this clause mostly counts this session's own agents.

**But 74 of 311 rows (24%; 35 of them outside `.agents/slop/`) are artifacts of the scanner's own
resolution** — the same class, one level down:

- **37** keys carry an **unexpanded shell variable**: `checks/$D`, `checks/$GT`, `checks/$OUT`,
  `checks/$RUN`, `checks/$SL`, `checks/$W`, `checks/$W/p2r`, `checks/$W/tinybendygrad`,
  `checks/$WORK`, `langs/$OUT`, `oracles/gateport/oracles/$TMP`, and 26 under `.agents/slop`.
- **28** keys **concatenate an absolute path onto a preceding segment**:
  `checks/differ.py/Users/cyberistic/src/...`, `gates/decomp_graph_census.bend/Users/...`,
  `tinybendygrad/private/var/folders/.../T/opencode/stalefix-matrix/old`.
- **15** keys contain a glob; **2** are degenerate (`""` and `"."`, i.e. "writes at the repo
  root", a real signal collapsed into one row).

These are exactly the shape `gates/gendirs.py`'s own docstring warns about in the abstract —
*"it resolves about a DIFFERENT POPULATION than the one it reports on"* — and here it demonstrably
does. One sharding caveat I should state rather than hide: my `dirs` set is a union across
shards, so a directory written into from sources under two different top-levels is counted once,
which is what `discovered()` does too.

### VI — the RED verdict — **INSTRUMENT_LIMITATION**

Restating clause IV as the finding it is: **the gate is RED for a finding about its own reader,
and silent about the tree.** At HEAD, once a data string is not mistaken for code, **0** entry
points compute a root resolving outside the repo. The RED is not a smaller finding than a real
one — it is the *same class of defect* this session found four times, wearing a verdict.

---

## 4. Is this the "one spelling" class? Yes — and it is the fifth instance, in two independent halves

The class: **a shape that cannot see its own second spelling.** This session's four prior
instances were a suffix set (`repro-paths.py`'s `REF`), a `(module, attr)` key table, a
single-base path resolver, and a basename regex (`ORACLE_WORD`). `gates-pop.py` contributes
**four** more instances, in two files, and they are *documented in its own prose*:

| Where | The shape | The spelling it cannot see | Measured cost |
|---|---|---|---|
| `ROOT_CONST` (`:541`) | tail is `\.parents\[(\d)\]` | `.parent`, `.parent.parent`, `abspath(os.path.dirname(…))` | **21 of 118** "declares no root" are declared; **31** more get a fabricated constant |
| `REFUSE` (`:561`) | 4 literal alternatives | `sys.exit(N)` (**51**), the imported `REFUSED` identifier (**37**) | **54 of 56** misses |
| `MARKER` (`:562`) | the literal `pyproject.toml` | `tinybendygrad` (**26**), `.git` (5), `runs/` (4) | **54 of 56** misses |
| `ROOT_INLINE` (`:554`) | a regex over raw text | a **string literal** in another gate's `--selftest` | the entire RED |

The cruel detail is that this file has already been bitten by the identical fault **three times
and repaired it each time in prose**:

- `:257-262` — "Without this, the instrument matched its OWN PROSE" → `code_of` blanks comments and docstrings.
- `:650-671` — "**A FIXTURE IS NOT EITHER: A STRING THAT HOLDS SOURCE IS DATA TO THIS INSTRUMENT
  WHOSE SOURCE IT IS NOT**" → `FIXTURES`, scoped by ownership: *"A FIXTURE IS DATA ONLY TO THE FILE
  THAT OWNS IT"*.
- `:617-626` — "A VARIABLE'S NAME CANNOT TELL YOU WHETHER IT HOLDS A FILE OR A DIRECTORY" → the
  `.parent` shape test in `resolve_root`.

**The ownership scoping is what opened this hole.** It was added deliberately (to stop plants 1 and
5 from being blanked), and its exact consequence is that a string fixture in *another* file is now
invisible to the blanker — so the class the file names for itself has re-entered through the fix
for itself. A `.parent`-chain root and a `sys.exit(3)` are not exotic spellings; they are what
`checks/abi_gate.py` and `checks/cites-census.py` write, in the files `gates-pop.py` cites by name.

**The honest asymmetry**, which the file already states about itself and which this measurement
confirms: `gates-pop.py` closed the "relative to itself" half of the class and is blind to the
"one spelling" half — **and the blind one is the blind one.**

---

## 5. Caveats, stated rather than hidden

- **The tree moved under me.** Source-file count went 2 314 → 2 315 → 2 319 across ~6 minutes and
  `checks/unrunnable-recipes.py` appeared at 14:15:30Z. Every count above carries its timestamp.
  HEAD was stable at `03500a26` for the whole session.
- **`gates/gates-pop.py` was never executed.** `repro.py` is a reimplementation; the one place I
  called the instrument's own code is `gendirs.discovered()` and `coverage()`, both read-only, both
  loaded by path, with `--plant` not invoked. I did not run `gates/retention-check.py`, so clause
  V's *shared* claim (that both instruments print the same number) is **CANNOT DETERMINE** here and
  I do not assert it.
- **Clause III is a census of spellings, not of intent.** "54 of 56 carry a refusal under another
  spelling" does not prove 54 correctly refuse *on a wrong root* — `sys.exit(N)` alone is not proof.
  I gave one true positive (`checks/differ.py`) and one airtight exemplar
  (`checks/abi_gate.py`, where the refusal and the marker were read directly). The claim I stand
  behind is the weaker and sufficient one: **the regex cannot see the tree's dominant idioms.**
- **The 311 is a union over 13 shards**, not one `discovered()` call, for the budget reason given.
- **Fix nothing.** This is a report. No gate was run, no tree file was modified, nothing committed.

## 6. Files

| Path | What |
|---|---|
| `clauses.rows` | 6 clause rows, 5 fields, TAB-separated — the required verdict table |
| `repro.py` | independent reimplementation of `gates-pop.py` clauses I–IV |
| `repro1.json` | its output: 197 rows, homes, derivation, opaque-by-suffix |
| `spellings.py` / `spellings.out` / `spellings.json` | clause III second-spelling census, taken against `code_of` |
| `rootblind.py` / `rootblind.json` | `ROOT_CONST` blindness matrix and the 61 affected files |
| `classes.py` / `classes.out` | the three residue classes, with the offending lines |
| `decisive.py` / `decisive.out` | the in-memory removal of `checks/cites-census.py:664` |
| `gendirs_shard.py`, `gd-*.json`, `gendirs-union.out` | clause V, sharded, and its composition |
