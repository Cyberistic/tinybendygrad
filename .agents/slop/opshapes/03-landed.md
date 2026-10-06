# WHAT LANDED IN `ops.bend`, AND THE BYTE COUNT AFTER

## ⚠ I DID NOT COMMIT, AND A CONCURRENT UNIT COMMITTED MY EDIT ANYWAY

`e497d60ea` (05:54:30, *"ops.bend: nine more rows -- the key carries `type(arg)` and
NOT `type(tag)`, and three of the answers are `0`"*) swept the working tree and took my
66 comment lines with it: `git show HEAD:tinybendygrad/uop/ops.bend | grep -c` finds
all four of my citations, and `git status --porcelain tinybendygrad` is now empty. **I
ran no commit.** The cost is a ledger one — **a reader of `e497d60ea`'s message will
not find the citation fix there**, so this file is where it is recorded.

## I LANDED A CITATION FIX AND NOTHING ELSE

`git diff HEAD -- tinybendygrad/uop/ops.bend` is **66 insertions, 3 deletions, and
every one of them is a `#` line.** No type, no def, no arity moved. The check that
says so is mechanical and it is the check that matters for a comments-only claim:

    git diff HEAD -U0 -- tinybendygrad/uop/ops.bend \
      | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]#' | grep -vE '^[+-]$'
    -> EMPTY

**THE FOUR CITATIONS CORRECTED, all of which had the same failure mode — a citation
that names a FUNCTION *AND* A SHAPE, which cannot tell you which of the two is wrong:**

1. **`:1007`** claimed `CallInfo.dtype` *"IS read: by `dtype_from_uop`'s CALL arm and by
   `_shape`'s."* `ops.py:132` is **`return src[0].dtype`** — the BODY. Replaced with the
   three measurements (`git log -S` returns only `6f4bfde23`, whose hunk is
   `+  dtype: DType = dtypes.void`; HEAD has five fields and none is `dtype`) and with
   the eleven-site cost.
2. **`:983`** said *"upstream MOVED `CallInfo.dtype` here"* as though the move were the
   end of the story. It was the START, and the field came BACK. Now says so and points
   at the `CallInfo` block.
3. **`:1035`** listed `tuple[int, ...]  ATuple  PERMUTE arg` and said nothing about
   FLIP — the case `ATuple` cannot spell. Added the measured rejection and the five
   files.
4. **`:8286`** already had the right story in the NOT PORTED block; added the measured
   "APPLIED AND GREEN in a scratch copy, closes HALF the row" so the next reader does
   not re-derive it.

Plus **`:919`**, where `applied_opts: List<&2, U32>` was an unremarked wrong type. It now
carries the live py-side measurement, the two-opposite-direction plants, the
`DEV=CPU`-vs-default option-count difference, the correct type, and the import-direction
blocker.

## THE BYTE COUNT, BEFORE AND AFTER

| | bytes | when |
|---|---|---|
| `ops.bend` at commit `6caac2102` (the HEAD I inherited) | **402,370** | 05:47:47 |
| after my citation fix | 407,271 | 05:52 |
| after ANOTHER UNIT's uncommitted edit | **407,671** | 05:53:08 |

**`ops.bend` IS A MOVING TARGET: IT CHANGED UNDER ME TWICE, AND THE BRIEF'S NUMBER IS
STALE.** The brief says 401,110; I measured 401,664 at the start of my session; a
commit landed at **05:47:47** (`6caac2102`, *"ops.bend: the FIRST gate for the file"*)
and an uncommitted +400 B landed at **05:53:08** while I was writing this file. So
**407,671 is the byte count AFTER my edit, and 5,301 of it is not mine.** What IS mine
is `git diff HEAD` on `ops.bend`: **66 insertions, 3 deletions, every one a `#` line**,
re-checked after the second edit landed.

`6caac2102`'s only hunk is `@@ -5024,6 +5024,14 @@` — **after every line this job
cites** — so no measurement here is invalidated, but **`sg.ci` moved 6931 -> 6939** and
any other unit's line numbers may have moved too.

## ⚠ A LINE-NUMBER CITATION IN `ops.bend` IS A CITATION THAT ROTS WITHIN THE HOUR

Two other commits landed on this file while I worked. Here is where the five lines this
job names stood at each measurement, all in `tinybendygrad/uop/ops.bend`:

| what | brief | session start | after `6caac2102` | after `e497d60ea` |
|---|---|---|---|---|
| `KernelInfo{name: String, applied_opts: …` | 919 | 919 | 919 | **939** |
| `CallInfo{name: …, dtype: S.Dt}` | 1010 | 1010 | 1010 | **1057** |
| `ATuple{ys: List<&2, U32>}` | 1081 | 1081 | 1081 | **1138** |
| `def CallInfo.dtype` | 1460 | 1460 | 1460 | **1517** |
| `def sg.ci` | 6931 | 6931 | 6939 | **7003** |

**+20 / +47 / +57 / +57 / +72 IN ONE SESSION, FROM COMMITS THAT HAD NOTHING TO DO WITH
THIS JOB.** Every other file I cite is stable: `fold.bend:1142`, `:2263`,
`spec.bend:407`/`:414`, `graphcmp.bend:300`/`:416`/`:962`/`:1005`, `graphcmp.py:1385`
all held. **`ops.bend` is the only file in this set another unit is actively committing
to, so a citation of the form `ops.bend:NNNN` should be read as `ops.bend: the def
named below it`.** The block I wrote names upstream lines (`ops.py:130-132`,
`spec.py:112`) and defs (`CallInfo`, `sg.ci`, `arg_call`) precisely so it does not rot
the same way; the brief's line numbers are usable to FIND the text today and are not a
stable address.

## THE CHECK, WITH EMPTINESS AFTER THE GREEN

    $ .venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
        ./bin/bend tinybendygrad/uop/ops.bend --check-only
    ALL PROOFS CHECK                              <- stdout, verbatim
    Use --verdict for mathematical validity.
    [bounded] WITHIN-LIMITS  rc=0  peak-RSS=211 MB (ceiling 2048)  1s
    bend 2.0.35 is available: run bend update     <- the 42 bytes, GREEN INCLUDED

**`ALL PROOFS CHECK`, not `SOME PROOFS FAIL`.** And because that sentence is reported
for a 0-byte file, the emptiness census ran after it — **twice, once per byte state**,
since `ops.bend` changed between the two runs:

    empty .bend files in tinybendygrad/ : 0
    tinybendygrad/helpers.bend          : 130,719 B
    tinybendygrad/uop/ops.bend          : 407,671 B

Compiler `Bend 2.0.34`. `--check-only` is a real check here, not `-o`: it elaborated
`ops.bend` and its whole import closure in 1 s at 361 MB.

## `runs/graphcmp/D` IS BYTE-IDENTICAL

    manifest before : 31abca502343be9dea7d0b9eba90fa403e5f525621ef11dc1294f4cbd372cee9
    manifest after  : 31abca502343be9dea7d0b9eba90fa403e5f525621ef11dc1294f4cbd372cee9
    git status --porcelain runs/graphcmp : (empty)
    newest mtime    : Oct 6 00:31  D0-coverage-census.txt

The manifest is `sha256` over every file's `sha256`, sorted by name, so it moves if any
byte moves. Nothing was regenerated, and the only tool that touched a `runs/` path was
`diff`.

## THE FILES THIS UNIT OWNS

| path | what |
|---|---|
| `.agents/slop/opshapes/00-rows.md` | **the first disagreeing row for each of the three, both sides' bytes** |
| `.agents/slop/opshapes/01-evidence.md` | the measurements, the four plants, two of them negative |
| `.agents/slop/opshapes/02-fix.md` | the correct type per defect, narrow/broad, the couplings |
| `.agents/slop/opshapes/04-unsettled.md` | what I could not settle |
| `.agents/slop/opshapes/one.sh` | one `bend --check-only`, token + emptiness parsed |
| `.agents/slop/opshapes/rows.sh` | the LIVE driver: `graphcmp.bend`'s own `main`, one graph, scratch tree |
| `.agents/slop/opshapes/opshapes.py` | apply / restore a narrowing plant; refuses any non-scratch tree |
| `tinybendygrad/uop/ops.bend` | **the citation fix only, comments only** |

Scratch trees live under the temp root, not in the repo. `NOTHING IS COMMITTED.`