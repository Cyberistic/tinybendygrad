# ONE SPELLING: a census of instruments that read one spelling of a thing and call it the population

**MEASURED 2026-10-17T03:32Z at HEAD `25daf8555c70abc1ee92f50e3fabf8d045748741`** (the tree is a
moving target; another session commits continuously). **This run is green: `selfcheck : OK -- 6
controls`** and rc 0 — the fourth refusal, and it was the control's, not the instrument's; see THE
SELF-CHECK below. Instrument: `census.py`, 559 lines. Rows: `findings.rows`, 320 lines,
TAB-separated `site / kind / verdict / second_spelling_found / evidence`. `.venv/bin/python census.py
--selfcheck` exits 3 without writing anything if the control fails.

**KNOWN BLIND SPOT, introduced by that repair:** `checks/repro-paths.py:64` is no longer in this
census's population at all (0 rows), so no future one-spelling defect in that file can be found here,
and the self-check cannot see that it cannot. Stated in `census.py`'s docstring.

## THE CLASS

Four defects found in one day are one shape: **an instrument that reads ONE SPELLING of a thing and
reports the result as the whole population.** The four, each verified by reading the code:

| # | site | one spelling | the second spelling it cannot see |
|---|---|---|---|
| 1 | `checks/repro-paths.py:64` `REF` | a path is preceded by `^` or whitespace | markdown writes it inside BACKTICKS — **RESOLVED at `0895758717`**, which re-anchored it to `(?<![\w/.])` |
| 2 | `.agents/TOOLS.md` and the reports | `differ.py` is a file | 4 tracked files are |
| 3 | `.agents/slop/toolsledger/extract.py:15` `ROOT` | every token resolves under one base | the ledger writes `uop/ops.bend` for `tinybendygrad/uop/ops.bend` |
| 4 | `checks/sweep.py:257` `FS_WRITES` | a write is `("os", "makedirs")` | it is also `p.mkdir()` — which is why the table has a companion |

## THE DENOMINATOR, AND HOW IT WAS ENUMERATED

Nothing is listed; everything is walked.

```
population : 1901 committed .py, 572 committed .md, 7461 committed paths
             -- every one from `git ls-tree -r HEAD`, never from the index
module-level literals examined : 101549  (from 1433 .py parsed; 468 dropped by the column-0 grammar gate)
CANDIDATE SITES : 320
   extension-set=51  module-attr-table=3  prose-basename-citation=258  regex-anchor-set=2  single-base-resolver=6
bare basenames cited : 4429, ambiguous 258
VERDICTS : NEGATIVE=31  POSITIVE=263  UNKNOWN=26
```

**How the 101,549 were enumerated.** `ast.parse` over the committed `.py`, then every module-level
`Assign`/`AnnAssign` whose target is a bare name. A line that starts at column 0 with an identifier
and `=` is a NECESSARY condition of that, so 468 files were dropped before parsing — reported above,
not swallowed — and dropping them lost no candidate: the literal count is identical with and without
the gate (101,549).

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

### POSITIVE — 263

**`regex-anchor-set`, 2 sites, and this is known positive #1 no longer among them.** `checks/repro-paths.py:64`
`REF` was this class's only confirmed instance and it is **RESOLVED** — `0895758717` replaced its
`(?:^|\s)` delimiter class with the lookbehind `(?<![\w/.])`, and a POSITIVE asserts a defect that
exists, so a repaired site correctly stops being reported. The **whole population is now 2 sites, both
in `.agents/slop/reprorefs/probe.py`**, over the 572 committed `.md`: `:26 OLD` anchors **603** names,
the same pattern with its anchor dropped names **1433**, so **830 spellings are invisible** (preceding
delimiters `` ` ``×5653, space×1531, `\n`×160, `/`×88, `"`×45); `:27 PERMISSIVE` anchors **782**,
anchor-dropped **3652**, **2870 invisible** (`` ` ``×9800, space×3239, `'`×724, `/`×673, `\n`×218).

**THE COST OF THAT REPAIR, MEASURED, AND IT IS NOT SMALL:** `widened()` recognises a leading
`(?:^|…)` and nothing else, so a lookbehind-anchored regex is never a candidate and `checks/repro-paths.py`
now contributes **0 rows**. **This census is structurally blind to that file, and the self-check cannot
see that it is blind** — a control that asserts a POSITIVE there refuses rather than reporting the
loss. Fixing the defect put the file outside the instrument's kind definition, which is a change to the
kind definition and not a control fix. The same trade the census makes everywhere: a quiet instrument
and a blind instrument print the same thing.

**`single-base-resolver`, 3 sites, and this is known positive #3.**
`.agents/slop/toolsledger/extract.py:15`, `.agents/slop/shapecensus/toolsmd.py:20`,
`.agents/slop/ledgerdrift/drift.py:38`. Each `chdir`s to one root and resolves every backticked token
in `.agents/TOOLS.md` against it. **26** of those tokens do not resolve there and do under a root the
tree contains: `LAWS/spec.bend` → `tinybendygrad/LAWS/spec.bend`,
`codegen/decomp/dtype.bend` → `tinybendygrad/codegen/decomp/dtype.bend`. Verified by hand:
`tinybendygrad/uop/ops.bend` exists at HEAD and `.agents/TOOLS.md` writes `uop/ops.bend` 8 times.

**`prose-basename-citation`, 258 of 4429 cited bare basenames, and this is known positive #2.**
`differ.py` = 4 tracked files, `gatekit.py` = 3, `extract.py` = 2
(`.agents/slop/shapecensus/extract.py`, `.agents/slop/toolsledger/extract.py`). The severity is not
uniform and the collision count is in the evidence: `REPORT.md` 208, `__init__.py` 65, `README.md` 56,
`plant.py` 31, `census.py` 26. A bare `census.py` in prose names 26 files.

### NEGATIVE — 31

**`module-attr-table`, 3 of 3 — including the trap.** `checks/sweep.py:285` `FS_DELETES` is keyed
module-form only, and it is **DEAD**: 0 reads, because a comment is not an AST node. A table nothing
reads cannot mislead a reader, so charging it would be a false charge; the instrument prints `0 reads`
in the evidence and the self-check fails if that string is ever absent. Its two LIVE siblings are
NEGATIVE because the companion is **proved, not assumed**: `FS_WRITES` shares `mkdir, open, rename,
replace` with `FS_METHOD_WRITES`, `FS_READS` shares `lstat, readlink, stat` with `FS_READ_METHODS`.
The name overlap is the evidence that the two tables are two spellings of one vocabulary rather than
two unrelated lists.

**`extension-set`, 28.** A set handed to `endswith`/`fnmatch` truncates nothing: `"x.cpp".endswith(".c")`
is `False`, because both compare the tail exactly. These 28 are at such a call. (Getting this wrong
was my own first draft, which charged 13 sites on the *prefix* relation; reading `checks/substrate.py:844`
— `f.endswith(POP_SUFFIXES)` with `(".bend", ".c", ".js", ".mjs")` — showed the charge was false, and
it was withdrawn.)

### UNKNOWN — 26, and each says why

- **4 `extension-set`, regex-spelled, where the measurement IS made.** The pattern is run over **4704**
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
scope. That question is open on **all 51** extension-set rows and closed on none of them.

## THE SELF-CHECK, AND WHAT IT REFUSED

`--selfcheck` asserts six controls (the known positives by kind and verdict, the known negative),
the trap, and that the extractor reads both AST spellings. It has **refused four times during
development, and each refusal found a real bug — except the fourth, which found a real REPAIR** —
which is the point of shipping it:

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

4. **`no POSITIVE regex-anchor-set site matching checks/repro-paths.py`** — **the CONTROL was wrong, not
   the instrument.** The control pinned the one TRUE instance of its own kind, so the commit that
   repaired it turned a passing assertion into a refusal. A control that pins a defect cannot survive
   the defect's repair. `frag` became `None`, which asks the population question the control was
   always for — *does this kind still yield this verdict anywhere* — and still catches a broken
   `widened()` or an inverted `probe_regex`; what it gives up is sensitivity to losing **one** site,
   and that loss is the census's job to report, not the control's to forbid. A path fragment in a
   control tuple is also doctrine 1's forbidden hand list. **No row total changed**: the file was already
   contributing 0, so `320` sites and `263` positives are the same numbers before and after the fix.
   Full argument with the measurements, and the two fixes considered and rejected:
   `.agents/slop/onespelling-control/decision.md`.

## WHAT I COULD NOT DETERMINE

- **Whether a read `(module, attribute)` table has a second spelling.** 29 sites are UNKNOWN for this.
  Deciding it needs a subject oracle — a mapping from `os.remove` to `Path.unlink` — and that mapping
  is a hand list, which is doctrine 1's forbidden shape.
- **The corpus a regex is applied to.** The anchor probe runs over the committed `.md` set, which is
  right for `checks/repro-paths.py` and a guess for the other two. Stated in the row, not hidden.
- **Whether a base's tokens are *meant* relative to it.** The 26 lost tokens under
  `tinybendygrad/` may be a second spelling or may be the corpus being wrong.
- **Severity of the 258 basename citations.** Ambiguity is measured; whether a given reader was
  misled is not, and the collision count is the proxy.
- **Files the gate drops.** 468 `.py` with no column-0 bare-name assignment. The grammar says no
  candidate can hide there; I did not verify it 468 times, and I am not claiming I did.
- **Whether `checks/repro-paths.py` still has a defect.** It has left this census's population, so this
  instrument's silence about it is not evidence either way, and the residual question is **not measured
  here**. A separate brief measured it at HEAD `444890672` over that HEAD's **568** `.md` — the shipped
  lookbehind naming **3612** against **3618** for the anchor-dropped form, leaving **6** invisible
  spellings, all `/`-prefixed or relative forms (`.agents/slop/onespelling-control/measure.py`,
  `decision.md` §6). **Do not read those as current**: the corpus is 572 `.md` here and those counts
  will have moved. Whether reading a `/`-joined tail is wrong depends on the subject, which the tree
  does not state — **not charged, not cleared.**

## COST

~7–11 s CPU, ~24 s wall at 54 % of one core on a machine this session was told is near capacity —
`ast.parse` of the committed `.py` is ~3.7 s of it and is irreducible for this population. A first
draft was 20 s because `root_constant` walked every one of the 100,951 literals; it now answers
`Constant`/`Call` without looking inside anything else. Nothing was run that `AGENTS.md` forbids:
no `bend`, no corpus, no `gates/*.py` execution, no `pytest`, no `mypy`, no `ruff`. The gates under
`gates/` were read and parsed, never run. Files written: these three, all under
`.agents/slop/onespelling/`. No `.txt` was created.