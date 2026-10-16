# ONE SPELLING: a census of instruments that read one spelling of a thing and call it the population

**MEASURED 2026-10-16T13:21:36Z at HEAD `037d5d536e215b599d7770955ca3733f79b02fca`** (the tree is a
moving target; another session commits continuously, and this HEAD is not the one this file was
written against). Instrument: `census.py`, 543 lines. Rows: `findings.rows`, 307 lines, TAB-separated
`site / kind / verdict / second_spelling_found / evidence`. `.venv/bin/python census.py --selfcheck`
exits 3 without writing anything if the control fails.

## THE CLASS

Four defects found in one day are one shape: **an instrument that reads ONE SPELLING of a thing and
reports the result as the whole population.** The four, each verified by reading the code:

| # | site | one spelling | the second spelling it cannot see |
|---|---|---|---|
| 1 | `checks/repro-paths.py:64` `REF` | a path is preceded by `^` or whitespace | markdown writes it inside BACKTICKS |
| 2 | `.agents/TOOLS.md` and the reports | `differ.py` is a file | 4 tracked files are |
| 3 | `.agents/slop/toolsledger/extract.py:15` `ROOT` | every token resolves under one base | the ledger writes `uop/ops.bend` for `tinybendygrad/uop/ops.bend` |
| 4 | `checks/sweep.py:257` `FS_WRITES` | a write is `("os", "makedirs")` | it is also `p.mkdir()` — which is why the table has a companion |

## THE DENOMINATOR, AND HOW IT WAS ENUMERATED

Nothing is listed; everything is walked.

```
population : 1835 committed .py, 551 committed .md, 7308 committed paths
             -- every one from `git ls-tree -r HEAD`, never from the index
module-level literals examined : 100951  (from 1369 .py parsed; 466 dropped by the column-0 grammar gate)
CANDIDATE SITES : 307
   extension-set=47  module-attr-table=3  prose-basename-citation=248  regex-anchor-set=3  single-base-resolver=6
bare basenames cited : 4228, ambiguous 248
VERDICTS : NEGATIVE=27  POSITIVE=254  UNKNOWN=26
```

**How the 100,951 were enumerated.** `ast.parse` over the committed `.py`, then every module-level
`Assign`/`AnnAssign` whose target is a bare name. A line that starts at column 0 with an identifier
and `=` is a NECESSARY condition of that, so 466 files were dropped before parsing — reported above,
not swallowed — and dropping them lost no candidate: the literal count is identical with and without
the gate (100,951).

**The four candidate kinds**, and what makes a site one:

- `module-attr-table` — a module-level literal whose every member is a 2-tuple of string constants,
  **and** at least one of whose first elements is a module the file actually imports. That last test
  removed 35 of 38: `PF_DTS = [("uchar", "uint8"), …]` is a dtype table, not a call table, and
  without the test its neighbour `DT` was reported as its method-form companion — two confident wrong
  answers out of one unexamined shape.
- `extension-set` — a literal whose every member is `^\.[A-Za-z0-9]{1,7}$`, or a pattern that spells
  an **alternation** of extensions (`(?:py|sh)`, `(?:\.py|\.sh)`). An alternation of *directories*
  (`(?:\.agents|slop)`) is not one and yields nothing.
- `regex-anchor-set` — a `re.compile` whose source opens with a `(?:^|…)` delimiter class.
- `single-base-resolver` — a module-level constant naming a directory (or a computed
  `os.path.dirname`/`abspath` chain) that is handed to `os.chdir` or `os.path.join`.
- `prose-basename-citation` — a backticked token with no `/` that several tracked files answer to.

## THE VERDICTS, WITH MEMBERS NAMED

### POSITIVE — 254

**`regex-anchor-set`, 3 sites, and this is known positive #1.** `checks/repro-paths.py:64` `REF`, over
the 551 committed `.md`: the anchored pattern names **728** distinct group-1 matches, the same pattern
with its anchor dropped names **3510**, so **2782 spellings are invisible**. The preceding delimiter
histogram is measured, not guessed: `` ` ``×8983, space×3136, `'`×718, `/`×666, newline×203. The
other two are `.agents/slop/reprorefs/probe.py:26` `OLD` (572 → 1340, 768 invisible) and `:27`
`PERMISSIVE` (728 → 3510, the same numbers, which is the cross-check: that file reproduces the shipped
pattern). `checks/repro-paths.py`'s own corpus, measured the same way, is **726 named + 2 patterns**
against 551 reports — the tree moved between the brief's reading (543 reports, 716/3473) and this one,
so quote the pair, never either number alone.

**`single-base-resolver`, 3 sites, and this is known positive #3.**
`.agents/slop/toolsledger/extract.py:15`, `.agents/slop/shapecensus/toolsmd.py:20`,
`.agents/slop/ledgerdrift/drift.py:38`. Each `chdir`s to one root and resolves every backticked token
in `.agents/TOOLS.md` against it. **26** of those tokens do not resolve there and do under a root the
tree contains: `LAWS/spec.bend` → `tinybendygrad/LAWS/spec.bend`,
`codegen/decomp/dtype.bend` → `tinybendygrad/codegen/decomp/dtype.bend`. Verified by hand:
`tinybendygrad/uop/ops.bend` exists at HEAD and `.agents/TOOLS.md` writes `uop/ops.bend` 8 times.

**`prose-basename-citation`, 248 of 4228 cited bare basenames, and this is known positive #2.**
`differ.py` = 4 tracked files, `gatekit.py` = 3, `extract.py` = 2
(`.agents/slop/shapecensus/extract.py`, `.agents/slop/toolsledger/extract.py`). The severity is not
uniform and the collision count is in the evidence: `REPORT.md` 208, `__init__.py` 65, `README.md` 56,
`plant.py` 31, `census.py` 26. A bare `census.py` in prose names 26 files.

### NEGATIVE — 27

**`module-attr-table`, 3 of 3 — including the trap.** `checks/sweep.py:285` `FS_DELETES` is keyed
module-form only, and it is **DEAD**: 0 reads, because a comment is not an AST node. A table nothing
reads cannot mislead a reader, so charging it would be a false charge; the instrument prints `0 reads`
in the evidence and the self-check fails if that string is ever absent. Its two LIVE siblings are
NEGATIVE because the companion is **proved, not assumed**: `FS_WRITES` shares `mkdir, open, rename,
replace` with `FS_METHOD_WRITES`, `FS_READS` shares `lstat, readlink, stat` with `FS_READ_METHODS`.
The name overlap is the evidence that the two tables are two spellings of one vocabulary rather than
two unrelated lists.

**`extension-set`, 24.** A set handed to `endswith`/`fnmatch` truncates nothing: `"x.cpp".endswith(".c")`
is `False`, because both compare the tail exactly. These 24 are at such a call. (Getting this wrong
was my own first draft, which charged 13 sites on the *prefix* relation; reading `checks/substrate.py:844`
— `f.endswith(POP_SUFFIXES)` with `(".bend", ".c", ".js", ".mjs")` — showed the charge was false, and
it was withdrawn.)

### UNKNOWN — 26, and each says why

- **4 `extension-set`, regex-spelled, where the measurement IS made.** The pattern is run over **4591**
  tracked filenames and the ones it reads as a member plus a tail are named — e.g.
  `checks/cites-census.py:105` `LOCATORISH` (`\.(?:md|py|rows|out|err|tsv|txt|bend|c|h|js|mjs|json)\b`)
  reads `D0-selfcheck.txt.err` as `D0-selfcheck.txt` + `.err`;
  `gates/msgdiff-gate.py:111` `PATH` reads `D-after.sha256` as `D-after.sha` + `256`.
  **The second spelling exists; whether reading it is WRONG depends on the subject, which the tree does
  not state.** For a locator heuristic it is benign. Charging it would be the confident wrong answer,
  so the verdict is UNKNOWN with the measurement attached.
- **19 `extension-set`, literal sets** whose use site was not located, with the count of longer tracked
  extensions named in the row as an unproven risk.
- **3 `single-base-resolver`** whose first `open()` is a `.rows`/`.tsv`/`.json` this census does not
  carry. Their single-base shape is unprobed, and the reason is in the row.

### Completeness is out of scope and is UNKNOWN for every extension row

A set that is merely INCOMPLETE — `CODE_EXT` without `.md` — is this class in the general case, and it
is not decidable here: without the subject, a missing `.md` is indistinguishable from a deliberate
scope. That question is open on **all 47** extension-set rows and closed on none of them.

## THE SELF-CHECK, AND WHAT IT REFUSED

`--selfcheck` asserts six controls (the three known positives by site and verdict; the known negative),
the trap, and that the extractor reads both AST spellings. It has **refused three times during
development, and each refusal found a real bug** — which is the point of shipping it:

1. **`no POSITIVE single-base-resolver … toolsledger`** — `os.path.dirname` is an attribute OF an
   attribute, so `func.value.id == "os"` is false for it. The instrument had the second spelling of
   the same module and could not see it: this class, in the instrument itself.
2. **`no site was extracted from a frozenset(Set) literal`** — the control was asking about sites
   when the question is about extraction. Moved to the population census, where it is answerable.
3. **`no module-attr-table from a Set/List/Tuple literal`** — unsatisfiable *after* the import test,
   because all three real module-call tables in this tree are `Dict`s. Replaced by the honest
   measurement: of the (a, b) tables the extractor read, `Dict` and `Set`/`List`/`Tuple` both
   contribute.

**The control the brief names** — an extractor that reads `Dict` with `.elts` skips the whole family —
is discharged on the population, not on a fixture: literal spellings read are `Tuple=6070, Dict=2147,
List=593, re.compile=325, Set=128, frozenset(Set)=26, sorted(List)=2, sorted(Set)=1`, and both a `Dict`
and a non-`Dict` (a, b) table were read. `FS_DELETES` is still found and still NEGATIVE. Exit codes:
0 written, 3 REFUSED (self-check failed, nothing written), 1 error.

## WHAT I COULD NOT DETERMINE

- **Whether a read `(module, attribute)` table has a second spelling.** 29 sites are UNKNOWN for this.
  Deciding it needs a subject oracle — a mapping from `os.remove` to `Path.unlink` — and that mapping
  is a hand list, which is doctrine 1's forbidden shape.
- **The corpus a regex is applied to.** The anchor probe runs over the committed `.md` set, which is
  right for `checks/repro-paths.py` and a guess for the other two. Stated in the row, not hidden.
- **Whether a base's tokens are *meant* relative to it.** The 26 lost tokens under
  `tinybendygrad/` may be a second spelling or may be the corpus being wrong.
- **Severity of the 248 basename citations.** Ambiguity is measured; whether a given reader was
  misled is not, and the collision count is the proxy.
- **Files the gate drops.** 466 `.py` with no column-0 bare-name assignment. The grammar says no
  candidate can hide there; I did not verify it 466 times, and I am not claiming I did.

## COST

~7–11 s CPU, ~24 s wall at 54 % of one core on a machine this session was told is near capacity —
`ast.parse` of the committed `.py` is ~3.7 s of it and is irreducible for this population. A first
draft was 20 s because `root_constant` walked every one of the 100,951 literals; it now answers
`Constant`/`Call` without looking inside anything else. Nothing was run that `AGENTS.md` forbids:
no `bend`, no corpus, no `gates/*.py` execution, no `pytest`, no `mypy`, no `ruff`. The gates under
`gates/` were read and parsed, never run. Files written: these three, all under
`.agents/slop/onespelling/`. No `.txt` was created.