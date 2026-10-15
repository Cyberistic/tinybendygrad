# EXIT CODES vs THE FIVE-VERDICT VOCABULARY

**Scope:** every `*.py` under `checks/` and `gates/`, parsed with `ast`, never run.
**Reading:** `2026-10-15T19:11:15Z` – `2026-10-15T19:15:20Z` (UTC).
**Reproduce:** `.venv/bin/python .agents/slop/exitcodes/census.py` → `.agents/slop/exitcodes/codes.rows`.
**Rows:** `codes.rows`, 388 data rows + 1 header, one row per (instrument, exit code), no duplicate pair
(measured: `awk` over column 1+2 → 0 duplicates).

Nothing in `checks/`, `gates/`, `AGENTS.md` or `.agents/TODO.md` was edited. Nothing was executed.

---

## 0. THE DENOMINATOR

**226** `.py` files, discovered by `os.walk` over `checks/` and `gates/` filtered on
`filename.endswith(".py")` — not from any document's list (`AGENTS.md` doctrine 1). Of those:

| population | count | what it means |
|---|---|---|
| all instruments walked | **226** | the denominator for every class below |
| ≥1 literal exit code reachable | **86** | the denominator for the UNOWNED and UNDECLARED classes |
| exit code not statically determinable | **92** | REFUSED — see §5 |
| hand a NON-INT to the exit (`sys.exit("…")`) | **24** | 57 sites — see §6 |
| no exit path at all (modules, not entry points) | **76** | `gates/gatekit.py`, `gates/gates-pop.py`, oracles, mutators |

The five codes `AGENTS.md` doctrine 2 names, read by **importing `gates/gatekit.py` by path**
(`importlib.util.spec_from_file_location`) and never retyped: `PASS 0 · FAIL 1 · REFUSED 3 · SKIP 4 ·
DEAD 5`.

## 1. HOW MANY DISTINCT EXIT CODES EXIST

**8**, over the 86 instruments that can produce a literal one: **0, 1, 2, 3, 4, 5, 126, 127**.

Five of the eight are in `VERDICT`. Three are not: **2, 126, 127**. 126 and 127 are the only ones
with no second witness anywhere in the tree — see §3.

## 2. THE UNOWNED CLASS — 20 rows over 18 instruments

An instrument can return an exit code `gates/gatekit.py` has no name for. A caller reading only
`$?` cannot tell what happened.

### 2a. Code `2` — 18 rows, 18 instruments (THE argparse/USAGE CLASS — NOT A DEFECT)

Reported because the class exists, exactly as briefed, and confirmed rather than called a bug:

- **`checks/dup-gate.py:362–370` records the decision in its own source.** Verbatim: *"`2` IS
  `USAGE` AND STAYS `USAGE`. It is `argparse`'s own exit code, and `gates/gatekit.py:75` records
  that 13 files here return `2` on purpose … `gates/gatekit.py:97`'s `verdict_of()` gives an
  unassigned code a name that is NOT `DEAD`, and `.agents/slop/exitcode/plant.py:74` PLANTS that
  `VERDICT[2]` raises `KeyError` as the correct design. Adding `2` to `gates/gatekit.py`'s
  `VERDICT` would break that planted assertion … `2` is UNOWNED BY `gatekit`, which is
  `gates/gate-surface.py`'s `UNOWNED` class doing its job, and NOT a defect in this file."*
- **The plant is live and says what the comment claims.** `.agents/slop/exitcode/plant.py` exists on
  disk (3,609 B, also at `56b73ebac`); lines 70–74 do `try: gatekit.VERDICT[2] … except KeyError`.
  So the assertion that makes `2` unownable is a real file, not a citation to a pruned tree.
- **Two spellings of `2` ship in `VERDICTS` declarations**, which is `gates/gate-surface.py:98–100`'s
  recorded collision, confirmed live:
  - `2: "USAGE"` — `checks/dup-gate.py:370`, `checks/wallcheck.py:692`
  - `2: "REFUSED"` — `checks/env-precond.py:452`, `gates/gate-surface.py:136`
- **9 of the 18 import `argparse`**, so 2 is argparse's own usage code there: `checks/disagree-gate.py`,
  `checks/dup-gate.py`, `checks/env-precond.py`, `checks/nvrows-deadrow-gate.py`,
  `checks/substrate-id.py`, `checks/substrate-snapshot.py`, `checks/wallcheck.py`,
  `gates/gate-surface.py`, `gates/gates-pop.py`.
- **9 do NOT import argparse**, so their `2` is a chosen number and not argparse's:
  `checks/al-verdict.py`, `checks/e2e.py`, `checks/repair-dupes.py`, `checks/txt-owners.py`,
  `gates/amd_dsl_census-mutate.py`, `gates/beautiful-mnist-gate.py`, `gates/crp_graph_census-mutate.py`,
  `gates/linearizer_census-oracle.py`, `gates/mixin-op-gate.py`. Two of those nine —
  `gates/mixin-op-gate.py:99` and `gates/beautiful-mnist-gate.py:89` — exit 2 at **module scope**
  when an input is absent, which is a REFUSED shape deliberately on a number argparse owns.

### 2b. Code `126` and `127` — 2 rows, 1 instrument: `checks/e2e.py`

**The only two UNOWNED codes in the tree with no second witness, and they are POSIX conventions
leaking through a gate.** `checks/e2e.py:294` computes
`status = 127 if isinstance(exc, FileNotFoundError) else 126` and forwards that child's status out
through `main()`'s `return rc` to `sys.exit(main())` at `:566`. `e2e.py`'s own docstring says so —
`:62` (*"So is rc 127: no `zsh`, nothing measured"*) and `:265` — so the instrument DECLARES them
in prose; `gates/gatekit.py`'s `VERDICT` has no entry, so a runner aggregating `e2e.py` sees 127,
has no name for it, and `charge()` bills it `REFUSED` (`gates/gatekit.py:110`). A "command not
found" would be reported as a refusal to run.

## 3. THE UNDECLARED CLASS — 140 rows over 73 instruments, of which 14 are sharp

An instrument can return a code `VERDICT` names whose meaning its own prose never states.

**The measurement is a LEXICAL test and is the LOWER BOUND, not a reading.** `declared=yes` means the
instrument's own prose block — module docstring plus the leading comment lines, stopping at the first
statement — contains the number in a shape that assigns it a meaning (`exit 3`, `return 3`, `3 =`,
`code 3`, `rc 3`, `3 is`, or the number adjacent to a verdict word). It can be fooled by a row count
and it can miss a meaning stated without the digit. The class is therefore **140 rows over 73
instruments**, of which:

- **64 of the 140 are code `0`** (64 PASS, 45 FAIL, 27 REFUSED, 3 DEAD, 1 SKIP). This is the class's
  real shape and it is worth stating plainly: **`PASS`/`0` is the one code nobody bothers to
  document, because documenting it implies it can fail.** A gate whose header says "exit 1 on a
  disagreement" has stated `FAIL` completely and `PASS` not at all.
- **The 14 sharp cases** — the instrument declares at least one code in prose *and* leaves another
  VERDICT-named code undeclared, so the omission is a gap inside a declaration that exists rather
  than an absence of one:

| instrument | declared in prose | undeclared |
|---|---|---|
| `checks/census.py` | 3 REFUSED | 0 |
| `checks/devgate.py` | 1 FAIL | 0 |
| `checks/differ.py` | 1 FAIL | 0, 3 REFUSED |
| `checks/e2e.py` | 1 FAIL, 3 REFUSED, 4 SKIP | 0 |
| `checks/nl-gate-noguard.py` | 0 PASS | 1 FAIL, 3 REFUSED |
| `checks/nl-gate.py` | 1 FAIL | 0, 3 REFUSED |
| `checks/residue.py` | 3 REFUSED | 0 |
| `checks/slop-declare.py` | 0 PASS | 1 FAIL, 3 REFUSED, **5 DEAD** |
| `checks/substrate.py` | 0 PASS, 3 REFUSED | 1 FAIL |
| `gates/amd_dsl_census-mutate.py` | 0 PASS | 1 FAIL |
| `gates/crp_graph_census-gate.py` | 0 PASS | 1 FAIL |
| `gates/decomp_value-gate.py` | 1 FAIL | 0 |
| `gates/gates-pop.py` | 0 PASS | 1 FAIL |
| `gates/i64-shr-gate.py` | 1 FAIL | 0 |

`checks/slop-declare.py` is the sharpest: it declares `0 PASS` and returns `1`, `3` **and `5`** — and
`5` is `DEAD`, the state `AGENTS.md` doctrine 2 calls "the one nobody writes down."

## 4. `verdict_of()` — CONFIRMED, WITH A LINE-NUMBER CORRECTION

`gates/gatekit.py`'s `verdict_of()` gives an unassigned code a name that is **not** `DEAD`. Measured:
the function opens at `:70`; the assigned branch is `:96 if code in VERDICT:` / `:97 return
VERDICT[code]`; the unassigned name is `:98 return f"UNASSIGNED (code {code!r} is not one of the
five)"`. The brief's citation of `:97` points at the **assigned** branch, one line above the
unassigned name.

Its docstring states the reason and it is the right one: `DEAD` is "a claim about EXECUTION, which
only something that watched the process can make"; a code the table does not define has not been
shown to have run at all, so the absent precondition is a **DEFINITION** and the state is `REFUSED`.
`charge()` (`:101–110`) resolves it consistently — an assigned code resolves to itself, an
unassigned one charges `REFUSED`, and a `bool` is refused rather than aliased (`True == 1`, which
`:94` handles first and by name).

## 5. REFUSED — 92 instruments whose exit codes could not be determined statically

Reported as REFUSED and **not guessed**. 283 sites across 92 instruments, each row naming the site
and the reason:

| reason | sites | what it means |
|---|---|---|
| a local name bound at runtime | 158 | `return rc`, `return code` — the value is decided by a branch this file does not evaluate |
| a FOREIGN call | 67 | the callee is **imported from another module**, so its surface is not in this file |
| another runtime value | 58 | a subscript, a binop, a boolop — the code is an expression over data |
| **total** | **283** | |

- **53 of the 92 delegate their verdict to `gates/gatekit.py`.** The `gates/*.py` shape is
  `sys.exit(gate(...))` / `sys.exit(main(...))` / `sys.exit(run_gate(...))` with `gate`,
  `main` and `run_gate` **imported**, so resolution is same-module by name and cannot cross the
  import boundary. Their surface is not missing — it is **owned by `gates/gatekit.py`, which
  declares it** (`VERDICT` at `:61`, `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` at `:60`).
  Named in each row rather than left for the reader to find.
- **32 of the 92 also yield at least one literal code** — a literal path and a runtime path in the
  same instrument. **60 yield none.**
- **73 are under `gates/`, 19 under `checks/`.**
- No instrument's exit status is computed from a `subprocess` return code *in the instrument's own
  exit statement* that this file mis-reads — the one such case, `checks/e2e.py`, was resolved
  through `main()` to the literal codes 0/1/3/4 plus §2b's 126/127.

**Limits of the parse, stated rather than hidden:** resolution is same-module by name only, is
depth-limited at 14, and treats a name bound twice as both bindings. A file whose exit path leaves
the module is reported UNDETERMINED — which is not a claim that it has no other codes, only that
this instrument cannot see them.

## 6. A CLASS THE BRIEF DID NOT ASK FOR, WHICH IS THE SHARPEST FINDING HERE

**24 instruments hand a NON-INT to the exit — 57 sites.** `sys.exit(f"…")`, `raise SystemExit("…")`.
CPython prints the string to stderr and exits **1**.

**So to `$?`, all 57 are `FAIL`, whatever their text says.** The verdict TOKEN is the only witness,
which is exactly what doctrine 2 demands of a reader — and here the token is a human sentence
invented at the call site, not a member of the vocabulary. A caller that reads only the exit status
sees an honest disagreement.

Instruments: `checks/abi4_gate.py`, `checks/abi_gate.py`, `checks/al-verdict.py`,
`checks/cl-port-gate.py`, `checks/corpus-figure.py`, `checks/dup-gate.py`, `checks/gate.py`,
`checks/gate_dtype.py`, `checks/gate_norm.py`, `checks/jsfix_gate.py`, `checks/oracle_f64.py`,
`checks/plant.py`, `checks/residue.py`, `gates/crp_graph_census-mutate.py`,
`gates/crp_graph_census-oracle.py`, `gates/gendirs.py`, `gates/i64-shr-gate.py`,
`gates/ops_python_census-oracle.py`, `gates/ops_python_exec-gate.py`, `gates/ops_python_exec-gen.py`,
`gates/ptx_render_census-gen.py`, `gates/ptx_render_census-mutate.py`, `gates/retention-check.py`,
`gates/tc_ptx_types-mutate.py`. Row `code` is `str`, verdict `MESSAGE-EXIT`.

## 7. TWO CITATIONS IN THE SOURCES I READ, CORRECTED

Neither is a defect in an instrument; both are the stale-number shape `AGENTS.md` warns about, and
both are recorded here because the audit rests on them.

1. **`gates/gatekit.py:75` says "13 files in this tree do [return `2`] on purpose."** Measured over
   the 226 instruments walked: **18** can return a literal `2`. Denominators differ and are
   unstated on either side ("this tree" is not a count of a walked population), so this is a
   disagreement to report, not a proven error. Of the 18, **9 import argparse** and **9 do not**.
   Only **4** ship a `VERDICTS` declaration that names `2` at all.
2. **`gates/gate-surface.py:523–528` says `checks/wallcheck.py` "sat at `4: "NO-ROW"` while the owner
   said `4: "SKIP"`".** Measured now: `checks/wallcheck.py:692` reads
   `VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}` — six entries,
   agreeing with `gates/gatekit.py` on every code including the five. The `RENAMED` collision that
   paragraph describes has been **fixed**; the prose describing it reads as live.

## 8. WHAT THIS DOES NOT SAY

- **Nothing here was run.** No gate, no `bend`, no subprocess. Every number is `ast` over source read
  at one timestamp, and a second reading tomorrow can differ (other units were writing the tree).
- **The `declared` column is a lexical test's verdict, not a reader's**, and §3 reports it as the
  lower bound it is. Only the 14 sharp cases and the two §7 citations were hand-read.
- **A code appearing in `codes.rows` means it is REACHABLE in the source**, not that a run was
  observed to produce it. `gates/gate-surface.py`'s own census distinguishes declared from reached,
  and that distinction is untouched by this audit.
- **Nothing was fixed.** `checks/`, `gates/`, `AGENTS.md` and `.agents/TODO.md` are byte-unchanged by
  this unit.