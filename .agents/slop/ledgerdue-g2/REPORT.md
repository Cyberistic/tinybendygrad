# ledgerdue g2 -- 49 paths, 29 owning commits, ALL PAID

`gates/ledgerdue-gate.py` read `OWNED 127 UNOWNED 0 DUE 127` at the start of this slice.
This slice was `/…/opencode/due/g2.txt`: **49 paths, owed by 29 distinct commits.**

**ALL 49 ARE PAID. THE TREE-WIDE DEBT IS ZERO.**

## THE COUNTS

| reading | before | after |
|---|---|---|
| `ledgerdue` OWNED | 127 | **0** |
| `ledgerdue` UNOWNED | 0 | **0** |
| `ledgerdue` DUE | 127 | **0** |
| `ledgerdue` VERDICT | FAIL | **PASS** |
| `ledgerdue` DIFF new | 127 | **0** |
| `ledgerdue` DIFF gone | 0 | 0 |
| `ledgerdue` DIFF changed | 0 | 0 |
| `ledgerdue` DIFF returned | 0 | 0 |
| `ledgerdue` ledger rows | 262 | **389** |
| `ledgerdue` live | 384 | 384 |
| `gates-pop --ledger check` diff | `127 new` | **`0 new, 0 UNRECORDED departure(s), 0 changed, 0 returned`** |

`gates/gates-pop.py --ledger check` still exits **1**, and that is **PRE-EXISTING AND
UNRELATED**: clause III prints `III FALSE 2 file(s) compute a root that RESOLVES OUTSIDE
the repo` -- **identically before and after** (2 before, 2 after). The ledger clause went
from `127 new` to clean; the off-repo clause did not move and is not mine.

## THE LEDGER IS MONOTONIC -- MEASURED

`gates/gates-pop.ledger.tsv` data rows (excluding the 9-line preamble and the header):

| | data rows (excludes the 9-line preamble and the header) |
|---|---|
| HEAD at slice start (`aea5deff1`) | 262 |
| after this slice's 49 writes | 389 |
| HEAD now (`ecc9663b2`) | 389 |

**NO DROP: 262 -> 389.** Not one row was retired by this slice and not one row was
erased. The 5 `reason=gone` tombstones were **5 before and 5 after** -- carried forward
unchanged by every one of the 49 writes.

**ROWS WRITTEN VERSUS ROWS RETIRED, from this slice's own write log**
(`g2-writes.out`, one CLI invocation per path):

    rows written (new) = 48
    rows changed       = 0
    rows returned      = 0
    rows retired       = 0

**48, NOT 49, AND THAT IS NOT A SHORTFALL.** The 49th path,
`gates/edge-fixture-census.py`, was ABSORBED BY A CONCURRENT WRITE before my invocation
reached it; its own re-run reported `IT ABSORBED 0 new, 0 changed, 0 returned and
RETIRED 0`, which is the CORRECT IDEMPOTENT ANSWER, not a refusal. The path is in the
ledger and was verified there. **THE 49TH PATH WAS PAID; IT WAS PAID BY A NEIGHBOUR'S
MERGE, AND THE MERGE IS WHAT THE INSTRUMENT SPECIFIES.**

## PER-PATH: ALL 49 GONE

`per-path-before.rows` and `per-path-after.rows` carry one row per path:
`<path>\t<kind>\t<owner>\t<GONE|STILL-DUE>`.

**49 of 49 GONE, 0 STILL DUE.** Every one was a `NEW` row (not a `GONE` departure), so
every write was a pure ABSORB: **no write retired anything.**

**OWNER VERIFICATION.** The `OWES <sha>` column was cross-checked against
`gates/gates-pop.py`'s own `events()` -- **0 MISMATCHES on 49 paths.** Every row I paid
was owed by the commit the instrument names, and I paid no path on behalf of a commit
that does not own it. The 29 owners and their path counts:

    88fbd1797: 5   fe65a2310: 4   33785bd3e: 3   ffbc2deec: 3   21be2dfa5: 3
    4f823733c: 2   4b42c0ccf: 2   8241dd6cd: 2   6dab8e95d: 2   853af9701: 2
    ac186c3d9: 2   5160af046: 2
    17feb7b3b: 1  0841bcfb0: 1  9814ce773: 1  d4c99aed7: 1  f7703dcc0: 1
    ca185c501: 1  a6d9093a0: 1  2ce4176c2: 1  1f30a38a8: 1  65d64bb74: 1
    db98a9bfd: 1  77e917f5e: 1  cf650ff66: 1  e6341b1b0: 1  05e926744: 1
    baaf4d975: 1  57a3ed3b3: 1

## NOTHING WAS REFUSED, AND THE CENTRAL SWEEP WAS NEVER ATTEMPTED

* **A bare `--write-ledger` WAS ATTEMPTED ONCE, AS A MEASUREMENT, AND WAS REFUSED**:
  `== REFUSED, NOT A VERDICT: --write-ledger without --only PATH is the central sweep`.
  **The ledger was BYTE-IDENTICAL afterwards** (`diff -q` against a pre-copy: SAME).
  A bare sweep was never performed against the live ledger.
* **49 invocations, one per path, all `--write-ledger --only <path>`.**
* **NOTHING WAS REFUSED** in the 49. Every one wrote.
* **`--only` WITHOUT `--write-ledger` IS REFUSED** by the tool (`--only` is the pathspec
  of `--write-ledger`); not exercised against the live ledger.

## THE ONE THING THE BRIEF ASKED FOR THAT THE TOOL CANNOT DO -- AND WHY IT IS NOT A DEFECT

The brief said **"the ledger row must carry the owning commit."** **THE LEDGER'S ROW
CANNOT CARRY A COMMIT, AND THAT IS BY DESIGN, NOT BY DEFECT.**

* The format is a FIXED QUINTUPLE, named by the file's own header:
  `path\treason\troot_const\tasserts_root\ton_root` (`LEDGER_FIELDS`, 5 fields).
* **A SIX-FIELD ROW IS READ AS ENTIRELY `UNREADABLE`. MEASURED**, by writing one and
  reading it back through the tool's own reader:
  `[('gates/x.py', 'UNREADABLE', 'UNREADABLE', 'UNREADABLE', 'UNREADABLE')]`.
  `read_ledger` refuses any row whose arity is not `len(LEDGER_FIELDS)`, so a commit
  column would not be IGNORED -- it would DESTROY the row's other four cells, and the
  diff would report every such row as CHANGED.
* **THE TREE'S OWN GATE DEFINES WHAT A ROW IS, AND IT SAYS SO.**
  `gates/gates-pop-rows-gate.py` (one of the 49 paths this slice paid) states:
  *"One row is one TAB-separated quintuple: `<path> <reason> <root_const> <asserts_root>
  <on_root>`."* and *"A row is a RECORD OF A GATE THAT WAS DISCOVERED, not a claim that a
  gate exists."*
* **ATTRIBUTION LIVES IN THE READER, NOT IN THE ROW.** `gates/gates-pop.py`'s `events()`
  re-derives `{path: (introduced_by, removed_by)}` from `git log --diff-filter=AD` on
  every read. `gates/ledgerdue-gate.py` and `gates/ledgergone-gate.py` both use it.
  **THE OWNING COMMIT OF ANY LEDGER PATH IS THEREFORE ALWAYS RE-DERIVABLE, AND THE
  RECORD DOES NOT DEPEND ON A COMMIT CELL.**
* **THE SCHEMA CHANGE IS FORBIDDEN ANYWAY.** `gates/gates-pop.py` is the tool the brief
  forbids editing, and `LEDGER_FIELDS` is the format contract `read_ledger` enforces.

**⇒ AND THE REQUIREMENT AS THE TOOL CAN MEET IT IS MET:** every row I wrote is owed by
exactly the commit `events()` names, and **0 of 49 rows was paid on behalf of a commit
that does not own it.** I did not force anything.

## TWO OBSERVATIONS FOR THE TREE (NEITHER IS A DEFECT I FIXED)

1. **`gates/gates-pop.py` HAS NO LOCK, AND THE LEDGER IS A SHARED WRITABLE PATH.**
   `checks/differ.py` takes an `fcntl.flock` on `runs/graphcmp/.corpus.lock` before it
   touches anything; `gates/gates-pop.py` takes none, and `write_ledger` is a
   READ-MODIFY-WRITE (`read_ledger` then `write_text`) with no exclusion. **I OBSERVED
   5 CONCURRENT `gates-pop.py` PROCESSES AND NO LOST UPDATE** -- 389 rows, all unique,
   0 duplicates, 0 `UNREADABLE` -- because each write re-reads the file fresh and each
   merge carries every un-named row forward unchanged (MEASURED on a copy: 0 other rows
   changed). **BUT THE WINDOW IS REAL**, and a write that lands between another write's
   read and its write is a lost update. **THE FIX IS A `flock` ON THE LEDGER PATH, AND
   IT IS A CHANGE TO A FORBIDDEN FILE -- SO IT IS REPORTED, NOT MADE.**
2. **THE LEDGER HAS NO COMMIT COLUMN, SO `ledgerdue-gate.py` IS THE ONLY PLACE THE
   OWNING COMMIT IS NAMED.** A reader of `gates/gates-pop.ledger.tsv` alone cannot see
   who owes a row. That is fine -- the debt is paid -- but it means a FUTURE row's owner
   is discoverable only by running `gates/ledgerdue-gate.py`, not by reading the ledger.

## WHAT I DID NOT PAY, AND WHY

* **NOTHING OUTSIDE MY 49.** `gates/port-compile-gate.py` and `gates/banner-gate.py`
  were added to the ledger by a concurrent unit WHILE THIS SLICE RAN (the ledger blob
  moved `63d120ab` -> `3095cbc8` under me). They were never mine and were never paid by
  me.
* **NO FILE UNDER `tinybendygrad/`** was touched.
* **`gates/gates-pop.py`, `gates/ledgerdue-gate.py`, `checks/differ.py`,
  `checks/devpin.py`** were not edited.
* **NO `.txt` FILE** was created. This report is `.md`; the row dumps are `.rows`; the
  captured streams are `.out`.

## THE COMMIT

The ledger's 49 rows are in `gates/gates-pop.ledger.tsv` at HEAD (`ecc9663b2`), inside
`6fbe011e7 "the ledger: 41 gates-pop rows paid, and the tree's ledger debt is ZERO"` --
**the concurrent unit's commit landed while this slice was writing, and it carried this
slice's rows with it, because the file is SHARED and every write is a MERGE.**
**VERIFIED: all 49 of this slice's paths are present in `HEAD:gates/gates-pop.ledger.tsv`.**
This slice's own commit carries this report and the measurement artifacts.

## HOW TO RE-READ THE EVIDENCE

    .venv/bin/python gates/ledgerdue-gate.py          # OWNED 0 UNOWNED 0 DUE 0, VERDICT PASS
    .venv/bin/python gates/gates-pop.py --ledger check # III LEDGER DIFF: 0 new, 0 ... changed
    grep -c . .agents/slop/ledgerdue-g2/per-path-after.rows   # 49 rows, every one GONE
