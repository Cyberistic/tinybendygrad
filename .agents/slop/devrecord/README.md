# THE FOUR PRECONDITION ROWS — what is written, where it is captured, and what it is checked against

`checks/differ.py` is the only writer of `runs/graphcmp/D/D0-run-summary.txt`, so the rows live in
`cmd_run`'s summary block (`differ.py:529-580`) and nowhere else. **One summary, one authority.**

    .venv/bin/python checks/differ.py plant          # 4 plants, no bend, no write into runs/
    .venv/bin/python .agents/slop/devrecord/xcheck.py   # the same thing driven through BOTH consumers

## THE FOUR ROWS, EXACTLY AS WRITTEN

| row | value the tree produces now | captured at | why THAT place |
|---|---|---|---|
| `dev=` | `CPU` | the artifacts, via `devices()` | `ENV["DEV"]` is **dead** — see below |
| `lc_all=` | `C` | `ENV["LC_ALL"]` | `ENV` is the dict every child was handed |
| `noopt=` | `0` | `ENV["NOOPT"]` | same; `unset` and `empty` are spelled apart |
| `pythonhashseed=` | `0` | `ENV["PYTHONHASHSEED"]` | same |

Four rows, not a new file, because the summary is already parsed as `key=value` by
`gates/retention-check.py` (CLAUSE IV, via `differ.unhealthy()`), `checks/corpus-figure.py:140`,
`checks/disagree-gate.py:128` and `checks/env-precond.py` METHOD B. **No new parser exists
anywhere.** A new file would be a *third* place the device is claimed.

## `ENV["DEV"]` IS DEAD — MEASURED, not assumed

`ENV` (`:47`) is handed to every child at `:285` and `:314`. Each one overwrites `DEV` before
`tinygrad`'s `Device.DEFAULT` resolves at import:

| child | line | what it does |
|---|---|---|
| `graphcmp.py` | `:2853` | `os.environ["DEV"] = a.dev`, whose `--dev` default is `CPU` (`:2839`) |
| `graphcmp-oracle.py` | `:186` | `os.environ["DEV"] = graphcmp_dev()`, read from `graphcmp.py`'s AST |
| `graphcmp-p13-ops.py` | `:28` | `os.environ["DEV"] = "CPU"` |
| `graphcmp-dbg-oracle.py` | `:48` | builds its own child env with `DEV="NULL"` |

So the only place the device survives is the artifacts — 99 of them name it.

## THE WITNESSES, AND THE TWO METHODS

`checks/devpin.py`'s `observed()`, IMPORTED (not retyped — it already knows `N` is `ATOMS["none"]`
and not a device called `N`). Measured over the live 139 artifacts:

    header  (# devices py=['sCPU'])        51 files
    field   (SGLOBAL,sCPU inside P(...))   50 files
    both answer                            {'CPU'}
    tinygrad imported by the reader?       NO

`devices()` returns both and refuses unless they are **equal singletons**, so a disagreement is a
`DISPUTED headers=… fields=…` row rather than a silent pick.

## THE THIRD PLANT — AN ARTIFACT MOVED WITH THE ROW UNCHANGED

`checks/differ.py plant`, PLANT 3: rewrite `SGLOBAL,sCPU` → `SGLOBAL,sMETAL` in
`D2-canon-py-lin.txt`, leave the summary alone:

    dev=CPU but the artifacts say DISPUTED headers=['CPU'] fields=['CPU', 'METAL']

**It goes red.** The row is a claim, not a label. `xcheck.py` drives the same mutation through
`gates/retention-check.py`'s CLAUSE IV callable *and* `checks/env-precond.py`.

## `env-precond.py --check`, BEFORE AND AFTER

    BEFORE  METHOD A  differ.py:47 MISSING · differ.py:509 MISSING · graphcmp.py:1800 MISSING
            METHOD B  dev= / pythonhashseed= / noopt= / lc_all= all MISSING          exit 1

    AFTER   METHOD A  differ.py:47 ok · differ.py:509 ok · graphcmp.py:1800 MISSING  <- NOT MINE
            METHOD B  ok ok ok ok, on a summary carrying differ.py's rows

METHOD B on the **live** summary still reads MISSING, and that is correct: the summary on disk was
written by a `cmd_run` from before this change, and hand-stamping a row into it would assert
`pythonhashseed=0` for a run that had it **unset** — a green row that can never go red.

## `gates/retention-check.py` CLAUSE IV, BEFORE AND AFTER

    BEFORE   IV FIRES runs/graphcmp/D/: 2 complaint(s)
             IV              oracle-selfcheck=# ORACLE SELFCHECK: FAIL (expected # ORACLE SELFCHECK: OK)
             IV              census-rc=rc=1 (expected rc=0)

    AFTER    IV FIRES runs/graphcmp/D/: 6 complaint(s)
             …the same 2, plus
             IV              dev ABSENT -- a precondition nothing records is a precondition nobody can audit
             IV              lc_all ABSENT -- …
             IV              noopt ABSENT -- …
             IV              pythonhashseed ABSENT -- …

    AFTER, on a tree that carries the rows (--dir graphcmp=<copy>): back to 2 complaint(s)

**`gates/retention-check.py` needed no edit.** CLAUSE IV already calls `differ.unhealthy()` by
reference (`:292`), so `preconditions_bad()` lands there for free — the point of "one summary, one
authority", demonstrated rather than asserted.

## `PYTHONHASHSEED` — WHAT IT IS, AND THE 4 SET-PRINTS

**The run that exists did not pin it, and it is NOT recoverable as one integer.** Measured: the
four `PY-BEND OPS DIFFER:` lines of `D0-coverage-census.txt`, each rebuilt in row order from the
`D2-canon-{py,bend}-*.txt` rows that produced them and matched against `str(set)` for seeds 0..599:

    allred   members 6   seeds that reproduce the print: [329]
    cdiv     members 6   seeds: [189, 218, 271]
    flip     members 1   EVERY seed — a one-element set has one rendering
    late     members 8   NONE
    INTERSECTION ACROSS ALL FOUR: EMPTY

**And `late` is not merely unrecoverable — its MEMBERS are wrong.** Rebuilt from
`D2-canon-py-late.txt` they are `CMPEQ FDIV GROUP NEG SUB MUL PERMUTE REDUCE`; the census printed
`RECIPROCAL` and not `FDIV`. **So the search correctly finds nothing: the census and the canonical
files are about two different graphs.** That is the two-devices-in-one-run defect, and it is why
the census reads 313 nodes where the 25 `D2-canon-py-*.txt` files sum to **312** — the difference
is `late` alone, 13 vs 12.

So a single integer is not there to be recorded. What IS measured is that it was **not pinned**:
`.agents/slop/rerun/D-before/` and `runs/graphcmp/D` are the same tree, and exactly **3 of 196**
files differ —

    D0-coverage-census.txt   3 of its 4 `PY-BEND OPS DIFFER` set prints, order only
    D1-verdicts.txt          bookkeeping (the two runs predate a WANT change)
    D0-run-summary.txt       bookkeeping (same)

**3 of 196 files, and 1 of the 4 set-prints is `{'GROUP'}`, which cannot vary.** So: 4 set prints,
3 of them varying, and nothing else in the corpus moved. That is why the row carries a value for a
run that pinned the seed and `unset` for one that did not.

## `NOOPT` — EMPTY IS NOT ZERO, MEASURED

    NOOPT=0   .venv/bin/python -c "import tinygrad"   -> ok
    NOOPT=    .venv/bin/python -c "import tinygrad"   -> ValueError: invalid literal for int()
                                                        with base 10: ''   at tinygrad/helpers.py:163

Three states, three behaviours, three spellings. `_pinned()` returns `unset` / the value / `empty`
and never collapses them, because `NOOPT=0` recorded for a run that had `NOOPT=` would be a row
that cannot go red.

## THE PIN IS NOT REDUNDANT WITH THE SORT

Five seeds over one 6-member set: **5 distinct `set(...)` renderings, 1 sorted rendering.** A PIN IS
A SEED and a SORT IS A LAW — a pin fixes the order on *this* interpreter, a sort fixes it on *every*
interpreter, and "the port and CPython disagree" has to survive a Python upgrade. Recording the
seed is NECESSARY AND NOT SUFFICIENT. The sort itself is `graphcmp-oracle.py:233` — not this file's.

## THE LEDGER IS EIGHT, NOT 147

`DEV` `IMAGE` `NOOPT` `DEFAULT_FLOAT` `NO_COLOR` `DEBUG` `DEBUG_RANGEIFY` `MAX_BUFFER_SIZE`;
plus 5 that make the side unbuildable (`DISALLOW_BROADCAST`, `REWRITE_STACK_LIMIT`, `SPEC=2`,
`TEST_PICKLE`, `REGEN=2`); plus **128 measured inert**, because the comparison never REALIZES a
graph — every runtime and compiler flag sits downstream of a boundary this harness does not cross.
The port itself reads **five**: `DEBUG` `DEFAULT_FLOAT` `DEFAULT_INT` `NO_COLOR` `SUM_DTYPE`
(`tinybendygrad/helpers.bend:340-346` and `:308`), while `tinygrad/` exposes 147. The two sides of
the comparison do not share an environment contract at all.

## NAMED COUPLINGS

1. **`.agents/slop/graphcmp.py:1800`** — `env-precond.py`'s `GRAPH_LINES` wants `PYTHONHASHSEED` and
   `NOOPT` pinned in `clean_env`. **That requirement is over-broad and I did not satisfy it.**
   `clean_env` feeds exactly two subprocesses, `bin/bend` (`:1826`) and `bin/bend` on the dbg probe
   (`:2624`); `bin/bend` is a `/bin/sh` shim that `exec bun …/bend2/main.ts`. Neither variable has a
   reader downstream of that line. Adding them there would be an edit made to satisfy a regex
   rather than to fix anything. Exact text, if its owner wants it anyway:
   `e.update(LC_ALL="C", DEV=dev, PYTHONHASHSEED="0", NOOPT="0")`.
2. **`.agents/slop/graphcmp-oracle.py:91`** — already an assignment, already correct; `env-precond.py`
   asks nothing of it and reports `ok`.
3. **`checks/differ.py:47` and `:509`** — `env-precond.py` names them by LINE NUMBER. They still sit
   on those numbers (the pin is in-place and the census `capture()` carries a trailing comment), but
   a line-numbered pin is a population declared by hand: insert a comment above `:509` and METHOD A
   reads the wrong line. It fails LOUDLY, not silently — but it is fragile.
4. **`runs/graphcmp/D/**`** — not edited. The rows appear at the next `checks/differ.py run`, which
   needs `bend`. Until then the live summary has no rows, and both consumers say so.
